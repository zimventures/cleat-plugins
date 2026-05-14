plugin = {
    id = "statusbar-network",
    name = "Net",
    description = "Primary interface throughput (bytes/sec) for the status bar",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "Status Bar",
    default_interval = 5,
    min_interval = 2,
    data_type = "snapshot",
    statusbar = true,
    statusbar_order = 50,
    -- Off by default: 5s polling adds steady network noise on the SSH
    -- channel that not every user wants. Toggle on via Plugin Manager.
    default_disabled = true,
    settings = {
        { key = "interface",   label = "Interface (blank = autodetect)", type = "string", default = "" },
        { key = "warn_mbps",   label = "Warning Threshold (Mbps)",       type = "number", default = "100" },
        { key = "crit_mbps",   label = "Critical Threshold (Mbps)",      type = "number", default = "500" },
    },
}

-- Module state: last seen counters, used to compute byte rate against this tick.
local last_rx, last_tx, last_ts, last_iface = nil, nil, nil, nil

function collect(ssh, cfg)
    local iface = (cfg and cfg.interface) or ""
    iface = (iface or ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- Linux: /proc/net/dev gives per-interface rx/tx byte counters.
    -- /proc/net/route's "default" line points to the primary outbound iface.
    -- We grab both and let transform() pick.
    local linux = ssh:exec("cat /proc/net/route 2>/dev/null && echo --- && cat /proc/net/dev 2>/dev/null") or ""
    if linux:match("Iface") then
        return "linux\n" .. iface .. "\n" .. linux
    end

    -- macOS: netstat -ibn outputs interface byte counters.
    -- `route -n get default` reports the primary interface.
    local mac = ssh:exec("route -n get default 2>/dev/null && echo --- && netstat -ibn 2>/dev/null") or ""
    return "mac\n" .. iface .. "\n" .. mac
end

local function pick_default_linux(route_section)
    -- /proc/net/route: tab-separated columns; the "default" line has a
    -- destination of 00000000.
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
    -- "route -n get default" output looks like:
    --   route to: default
    --   ...
    --      interface: en0
    return route_section:match("interface:%s*(%S+)")
end

local function rate_human(bps)
    -- bps comes from drx/dt and may be fractional. %.0f rounds without
    -- triggering Lua's "number has no integer representation" check that
    -- %d performs.
    if bps >= 1024 * 1024 then return string.format("%.1fM", bps / 1048576) end
    if bps >= 1024        then return string.format("%.1fK", bps / 1024)    end
    return string.format("%.0fB", bps)
end

function transform(raw, cfg)
    local platform, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""

    local iface_pref = body:match("^([^\n]*)\n") or ""
    local rest = body:match("^[^\n]*\n(.*)$") or ""
    local route_section, dev_section = rest:match("^(.-)\n%-%-%-\n(.+)$")
    if not dev_section then return { error = "no data" } end

    local iface, rx_bytes, tx_bytes
    local now = os.time()

    -- Reject loopback interfaces when picking a fallback. /proc/net/route
    -- may not have an IPv4 default (IPv6-only hosts, containers without a
    -- default gateway) — without this filter, the first row of
    -- /proc/net/dev is typically `lo` and we'd report loopback traffic as
    -- "the network".
    local function is_loopback(name)
        if not name then return true end
        return name == "lo" or name == "lo0" or name:match("^lo[0-9]") ~= nil
    end

    if platform == "linux" then
        iface = (iface_pref ~= "" and iface_pref) or pick_default_linux(route_section)
        -- /proc/net/dev: first two lines are headers, then "iface: rxBytes ... txBytes ..."
        for line in dev_section:gmatch("([^\n]+)") do
            local name, data = line:match("^%s*([%w%.@:%-]+):%s*(.+)$")
            if name and not is_loopback(name) then
                if not iface or iface == "" then iface = name end
                if name == iface then
                    local fields = {}
                    for f in data:gmatch("%S+") do table.insert(fields, f) end
                    -- Layout: rxBytes rxPackets rxErrs rxDrop rxFifo rxFrame rxCompressed rxMulticast
                    --         txBytes txPackets txErrs txDrop txFifo txColls txCarrier txCompressed
                    rx_bytes = tonumber(fields[1])
                    tx_bytes = tonumber(fields[9])
                    break
                end
            end
        end
    elseif platform == "mac" then
        iface = (iface_pref ~= "" and iface_pref) or pick_default_mac(route_section)
        -- netstat -ibn columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        -- Multiple rows per interface (one per address family); first hit is fine.
        for line in dev_section:gmatch("([^\n]+)") do
            local fields = {}
            for f in line:gmatch("%S+") do table.insert(fields, f) end
            if (not iface or iface == "") and #fields >= 10 and not is_loopback(fields[1])
                    and tonumber(fields[7]) and tonumber(fields[10]) then
                iface = fields[1]
            end
            if #fields >= 10 and fields[1] == iface and tonumber(fields[7]) and tonumber(fields[10]) then
                rx_bytes = tonumber(fields[7])
                tx_bytes = tonumber(fields[10])
                break
            end
        end
    end

    if not iface or not rx_bytes or not tx_bytes then
        return { iface = iface or "?", error = "interface not found" }
    end

    local rx_rate, tx_rate = 0, 0
    if last_iface == iface and last_rx and last_tx and last_ts and now > last_ts then
        local dt = now - last_ts
        local drx = rx_bytes - last_rx
        local dtx = tx_bytes - last_tx
        -- Counters can wrap on 32-bit kernels; treat negative deltas as 0.
        if drx >= 0 then rx_rate = drx / dt end
        if dtx >= 0 then tx_rate = dtx / dt end
    end

    last_iface, last_rx, last_tx, last_ts = iface, rx_bytes, tx_bytes, now

    return {
        iface = iface,
        rx_bps = rx_rate,
        tx_bps = tx_rate,
        rx_total = rx_bytes,
        tx_total = tx_bytes,
    }
end

function render_statusbar(ctx, store, cfg)
    if not store or not store.iface or store.error then return nil end

    local rx = store.rx_bps or 0
    local tx = store.tx_bps or 0
    local total_mbps = (rx + tx) * 8 / 1048576  -- bytes/sec → megabits/sec

    local warn = tonumber(cfg and cfg.warn_mbps) or 100
    local crit = tonumber(cfg and cfg.crit_mbps) or 500
    local color = ctx:threshold_color(total_mbps, warn, crit)

    return {
        label = "Net",
        value = string.format("\xe2\x86\x93%s \xe2\x86\x91%s", rate_human(rx) .. "/s", rate_human(tx) .. "/s"),
        color = color,
        tooltip = string.format("%s: rx %s/s, tx %s/s\nTotal: %.1f Mbps",
                                store.iface, rate_human(rx), rate_human(tx), total_mbps),
        icon = "",
    }
end
