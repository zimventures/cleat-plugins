plugin = {
    id = "network-traffic",
    name = "Network Traffic",
    description = "Per-interface RX/TX throughput with history graph",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "Network",
    default_interval = 5,
    min_interval = 2,
    data_type = "timeseries",
    retention = "24h",
    -- Off by default: 5s polling on every enabled connection adds steady
    -- chatter on the SSH channel that not every user wants. Opt-in via
    -- Plugin Manager.
    default_disabled = true,
    settings = {
        -- The engine treats `key = "interval"` specially: it overrides the
        -- metadata default_interval when set in plugin settings. Default
        -- matches default_interval above so the value the user sees in
        -- Plugin Manager and the actual sampling rate stay in sync.
        { key = "interval",        label = "Sampling interval (seconds)",                 type = "number",  default = "5" },
        { key = "interfaces",      label = "Interfaces (blank = primary; csv allowlist)", type = "string",  default = "" },
        { key = "history_minutes", label = "Graph history (minutes)",                     type = "number",  default = "30" },
        { key = "show_all",        label = "Graph all watched interfaces",                type = "boolean", default = "false" },
    },
}

-- Per-interface counter state for rate computation. Keyed by interface
-- name; each value is { rx, tx, ts }. We don't carry across plugin
-- reloads, but that's fine — first tick after reload shows zeros and
-- subsequent ticks compute against fresh baselines.
local last = {}

local function trim(s)
    -- Wrap in parens so only the trimmed string is returned, not the
    -- (string, replacement_count) tuple gsub yields. Otherwise the count
    -- can leak into multi-arg call sites and confuse table.insert etc.
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Series name for a (direction, interface) pair. Interface names can
-- contain ':' (VLAN), '.' (sub-interface), '@' (Linux NIC alias) — the
-- timeseries store keys on exact-match strings, but downstream tooling
-- may not handle non-word chars gracefully, so we hex-escape them. The
-- bracketing underscores make the encoding round-trip-safe and prevent
-- collisions like 'eth0:1' / 'eth0.1' both mapping to 'eth0_1'.
local function series_name(dir, iface)
    local escaped = iface:gsub("[^%w]", function(c)
        return string.format("_%02x_", string.byte(c))
    end)
    return dir .. "_" .. escaped
end

local function parse_csv(s)
    local out = {}
    if not s or s == "" then return out end
    for f in (s .. ","):gmatch("([^,]*),") do
        local t = trim(f)
        if t ~= "" then table.insert(out, t) end
    end
    return out
end

local function is_loopback(name)
    if not name then return true end
    return name == "lo" or name == "lo0" or name:match("^lo[0-9]") ~= nil
end

local function pick_default_linux(route_section)
    -- /proc/net/route: the "default" line has destination 00000000.
    for line in route_section:gmatch("([^\n]+)") do
        local fields = {}
        for f in line:gmatch("%S+") do table.insert(fields, f) end
        if #fields >= 2 and fields[2] == "00000000" then
            return fields[1]
        end
    end
    return nil
end

local function pick_default_mac(route_section)
    -- "route -n get default" output:
    --     interface: en0
    return route_section:match("interface:%s*(%S+)")
end

local function rate_human(bps)
    if bps >= 1024 * 1024 then return string.format("%.1fM", bps / 1048576) end
    if bps >= 1024        then return string.format("%.1fK", bps / 1024)    end
    return string.format("%.0fB", bps)
end

function collect(ssh, cfg)
    -- Linux: /proc/net/dev gives per-interface rx/tx byte counters.
    --        /proc/net/route's default line points to the primary outbound iface.
    -- macOS: netstat -ibn outputs interface byte counters; route -n get default
    --        reports the primary interface.
    -- We grab both and let transform() pick the platform from the contents.
    local linux = ssh:exec("cat /proc/net/route 2>/dev/null && echo --- && cat /proc/net/dev 2>/dev/null") or ""
    if linux:match("Iface") then
        return "linux\n" .. linux
    end
    local mac = ssh:exec("route -n get default 2>/dev/null && echo --- && netstat -ibn 2>/dev/null") or ""
    return "mac\n" .. mac
end

-- Parse /proc/net/dev section into { iface_name -> { rx_bytes, tx_bytes } }.
local function parse_linux_dev(dev_section)
    local result = {}
    for line in dev_section:gmatch("([^\n]+)") do
        local name, data = line:match("^%s*([%w%.@:%-]+):%s*(.+)$")
        if name and not is_loopback(name) then
            local fields = {}
            for f in data:gmatch("%S+") do table.insert(fields, f) end
            -- Layout: rxBytes rxPackets ... (8 cols), then txBytes ... (8 cols).
            local rx = tonumber(fields[1])
            local tx = tonumber(fields[9])
            if rx and tx then
                result[name] = { rx = rx, tx = tx }
            end
        end
    end
    return result
end

-- Parse `netstat -ibn` section into { iface_name -> { rx_bytes, tx_bytes } }.
-- macOS prints multiple rows per interface (one per address family); the byte
-- counters are the same in each, so first hit per name wins.
local function parse_mac_netstat(dev_section)
    local result = {}
    for line in dev_section:gmatch("([^\n]+)") do
        local fields = {}
        for f in line:gmatch("%S+") do table.insert(fields, f) end
        if #fields >= 10 and not is_loopback(fields[1]) then
            local rx = tonumber(fields[7])
            local tx = tonumber(fields[10])
            if rx and tx and not result[fields[1]] then
                result[fields[1]] = { rx = rx, tx = tx }
            end
        end
    end
    return result
end

function transform(raw, cfg)
    local platform, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""
    local route_section, dev_section = body:match("^(.-)\n%-%-%-\n(.+)$")
    if not dev_section then return { error = "no data", interfaces = {}, watched = {}, primary = nil } end

    local counters
    local primary
    if platform == "linux" then
        counters = parse_linux_dev(dev_section)
        primary = pick_default_linux(route_section)
    elseif platform == "mac" then
        counters = parse_mac_netstat(dev_section)
        primary = pick_default_mac(route_section)
    else
        return { error = "unknown platform", interfaces = {}, watched = {}, primary = nil }
    end

    -- Fall back: if route didn't yield a primary (IPv6-only host, container
    -- without a default gateway), pick the first interface seen in counters.
    -- Stable ordering matters across ticks so we sort.
    local sorted_names = {}
    for name, _ in pairs(counters) do table.insert(sorted_names, name) end
    table.sort(sorted_names)
    if (not primary or primary == "") and #sorted_names > 0 then
        primary = sorted_names[1]
    end

    -- Decide watched set: explicit allowlist overrides primary-only.
    -- Dedupe via a seen-set so a sloppy "eth0,eth0" allowlist doesn't
    -- emit duplicate stat cards or write two _ts points per tick to the
    -- same series (which would distort store:range / store:latest).
    local allowlist = parse_csv(cfg and cfg.interfaces or "")
    local watched = {}
    local seen = {}
    if #allowlist > 0 then
        for _, name in ipairs(allowlist) do
            if counters[name] and not seen[name] then
                seen[name] = true
                table.insert(watched, name)
            end
        end
    elseif primary and counters[primary] then
        table.insert(watched, primary)
    end

    local now = os.time()
    local ts = {}
    local rates = {}

    for _, name in ipairs(watched) do
        local cur = counters[name]
        local rx_bps, tx_bps = 0, 0
        local prev = last[name]
        if prev and prev.ts and now > prev.ts then
            local dt = now - prev.ts
            local drx = cur.rx - prev.rx
            local dtx = cur.tx - prev.tx
            -- 32-bit kernels can wrap byte counters; treat negative deltas as 0.
            if drx >= 0 then rx_bps = drx / dt end
            if dtx >= 0 then tx_bps = dtx / dt end
        end
        last[name] = { rx = cur.rx, tx = cur.tx, ts = now }

        rates[name] = { rx_bps = rx_bps, tx_bps = tx_bps, rx_total = cur.rx, tx_total = cur.tx }

        -- Only record timeseries once we have a real delta. Otherwise the
        -- first tick after a reload paints a misleading "0 B/s" point.
        if prev then
            table.insert(ts, { series = series_name("rx", name), value = rx_bps, unit = "B/s",
                               labels = { iface = name, dir = "rx" } })
            table.insert(ts, { series = series_name("tx", name), value = tx_bps, unit = "B/s",
                               labels = { iface = name, dir = "tx" } })
        end
    end

    return {
        interfaces = sorted_names,
        watched = watched,
        primary = primary,
        rates = rates,
        _ts = ts,
    }
end

function render(ctx, store, cfg)
    if not store or store.error then
        ctx:text(store and store.error or "no data yet")
        return
    end

    local watched = store.watched or {}
    local rates = store.rates or {}

    if #watched == 0 then
        ctx:text("No matching interfaces found.")
        return
    end

    -- Stat row: one card per watched interface with current rx↓ / tx↑.
    local cards = {}
    for _, name in ipairs(watched) do
        local r = rates[name] or {}
        local rx = r.rx_bps or 0
        local tx = r.tx_bps or 0
        local label = name
        if name == store.primary then label = name .. " (primary)" end
        table.insert(cards, {
            label = label,
            value = string.format("\xe2\x86\x93%s/s \xe2\x86\x91%s/s", rate_human(rx), rate_human(tx)),
            tooltip = string.format("rx %s/s\ntx %s/s\nTotal: %.1f Mbps",
                                    rate_human(rx), rate_human(tx), (rx + tx) * 8 / 1048576),
        })
    end
    ctx:stat_row({ cards = cards })
    ctx:space(6)

    -- History graph. ctx:line_graph wants a fixed x-axis duration, so we
    -- pull each series with the same window and let the renderer align them.
    local minutes = tonumber(cfg and cfg.history_minutes) or 30
    if minutes < 1 then minutes = 30 end
    local window = string.format("%dm", minutes)

    local show_all = false
    local sa = cfg and cfg.show_all
    if sa == true or sa == "true" then show_all = true end

    local graph_ifaces = {}
    if show_all then
        for _, n in ipairs(watched) do table.insert(graph_ifaces, n) end
    elseif store.primary then
        for _, n in ipairs(watched) do
            if n == store.primary then table.insert(graph_ifaces, n); break end
        end
        if #graph_ifaces == 0 then table.insert(graph_ifaces, watched[1]) end
    else
        table.insert(graph_ifaces, watched[1])
    end

    -- Two series per interface (rx + tx) — pair distinct colors so the lines
    -- read at a glance rather than overlapping in one color. Single-interface
    -- (the default) uses green=download / blue=upload, the convention most
    -- traffic tools follow. Additional interfaces rotate through the
    -- remaining named colors.
    local color_pairs = {
        { rx = "green",  tx = "blue" },
        { rx = "yellow", tx = "magenta" },
        { rx = "cyan",   tx = "red" },
    }
    local series = {}
    for i, name in ipairs(graph_ifaces) do
        local p = color_pairs[((i - 1) % #color_pairs) + 1]
        table.insert(series, {
            name = name .. " ↓",
            color = p.rx,
            data = store:range(window, series_name("rx", name)),
        })
        table.insert(series, {
            name = name .. " ↑",
            color = p.tx,
            data = store:range(window, series_name("tx", name)),
        })
    end

    ctx:line_graph({
        title = string.format("Throughput (last %dm)", minutes),
        series = series,
        y_min = 0,
        height = 140,
    })
end
