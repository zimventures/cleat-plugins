plugin = {
    id = "statusbar-memory",
    name = "Mem",
    description = "Memory usage in the status bar; multi-series breakdown in the panel",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Status Bar",
    default_interval = 15,
    min_interval = 10,
    -- Promoted to timeseries so the panel can graph used / cached / buffers
    -- / free over time. Status bar still shows a single instantaneous value.
    data_type = "timeseries",
    retention = "6h",
    statusbar = true,
    statusbar_order = 40,
    settings = {
        { key = "warn_pct", label = "Warning Threshold (%)",  type = "number", default = "80" },
        { key = "crit_pct", label = "Critical Threshold (%)", type = "number", default = "95" },
    },
}

function collect(ssh, cfg)
    local meminfo = ssh:exec("cat /proc/meminfo 2>/dev/null") or ""
    if meminfo ~= "" then
        return "linux\n" .. meminfo
    end
    -- macOS: hw.memsize for total, vm.swapusage for swap, vm_stat for the
    -- page-counter breakdown. vm_stat's first line declares the page size;
    -- we parse it instead of assuming 4 KiB so Apple Silicon (16 KiB pages)
    -- reports correct numbers.
    local mac = ssh:exec(
        "echo $(sysctl -n hw.memsize 2>/dev/null) && " ..
        "echo --SWAP-- && sysctl -n vm.swapusage 2>/dev/null && " ..
        "echo --VMSTAT-- && vm_stat 2>/dev/null"
    ) or ""
    return "mac\n" .. mac
end

function transform(raw, cfg)
    local platform = raw:match("^(%a+)")
    local body = raw:match("^%a+\n(.+)") or ""

    -- All values in GiB for graph readability; percent for status bar.
    local total_gb, used_gb, free_gb, cached_gb, buffers_gb = 0, 0, 0, 0, 0
    local swap_total_gb, swap_used_gb = 0, 0
    local percent = 0

    if platform == "linux" then
        -- /proc/meminfo values are in KiB.
        local function kb(field)
            return tonumber(body:match(field .. ":%s*(%d+)")) or 0
        end
        local total_kb   = kb("MemTotal")
        local avail_kb   = kb("MemAvailable")
        local free_kb    = kb("MemFree")
        local cached_kb  = kb("Cached")
        local buffers_kb = kb("Buffers")
        local swap_total = kb("SwapTotal")
        local swap_free  = kb("SwapFree")
        if total_kb > 0 then
            total_gb   = total_kb / 1048576
            free_gb    = free_kb / 1048576
            cached_gb  = cached_kb / 1048576
            buffers_gb = buffers_kb / 1048576
            used_gb    = (total_kb - avail_kb) / 1048576
            percent    = math.floor((total_kb - avail_kb) / total_kb * 100)
        end
        if swap_total > 0 then
            swap_total_gb = swap_total / 1048576
            swap_used_gb  = (swap_total - swap_free) / 1048576
        end
    elseif platform == "mac" then
        local memsize = tonumber(body:match("^(%d+)")) or 0
        total_gb = memsize / (1024 * 1024 * 1024)

        -- vm.swapusage line: "total = N.NM  used = N.NM  free = N.NM ..."
        local swap_section = body:match("%-%-SWAP%-%-\n([^\n]*)") or ""
        local function mb_field(name)
            return tonumber(swap_section:match(name .. "%s*=%s*(%d+%.?%d*)M")) or 0
        end
        local swap_total_mb = mb_field("total")
        local swap_used_mb  = mb_field("used")
        if swap_total_mb > 0 then
            swap_total_gb = swap_total_mb / 1024
            swap_used_gb  = swap_used_mb / 1024
        end

        local vmstat = body:match("%-%-VMSTAT%-%-\n(.+)$") or ""
        -- "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
        local page = tonumber(vmstat:match("page size of (%d+) bytes")) or 4096
        local function pages(field)
            return tonumber(vmstat:match(field .. ":%s*(%d+)")) or 0
        end
        local free_pages     = pages("Pages free")
        local inactive_pages = pages("Pages inactive")
        local active_pages   = pages("Pages active")
        local wired_pages    = pages("Pages wired down")
        local cached_bytes   = inactive_pages * page
        local free_bytes     = free_pages * page
        local used_bytes     = (active_pages + wired_pages) * page
        if memsize > 0 then
            free_gb   = free_bytes / (1024^3)
            cached_gb = cached_bytes / (1024^3)
            used_gb   = used_bytes / (1024^3)
            percent   = math.floor(used_bytes / memsize * 100)
        end
    end

    -- Round display values to one decimal.
    local function r1(x) return math.floor(x * 10 + 0.5) / 10 end

    return {
        total_gb   = r1(total_gb),
        used_gb    = r1(used_gb),
        free_gb    = r1(free_gb),
        cached_gb  = r1(cached_gb),
        buffers_gb = r1(buffers_gb),
        percent    = percent,
        swap_total_gb = r1(swap_total_gb),
        swap_used_gb  = r1(swap_used_gb),
        warn_pct = tonumber(cfg and cfg.warn_pct) or 80,
        crit_pct = tonumber(cfg and cfg.crit_pct) or 95,
        _ts = {
            { series = "used",    value = used_gb,    unit = "GB" },
            { series = "cached",  value = cached_gb,  unit = "GB" },
            { series = "buffers", value = buffers_gb, unit = "GB" },
            { series = "free",    value = free_gb,    unit = "GB" },
            { series = "swap_used", value = swap_used_gb, unit = "GB" },
        },
    }
end

function render_statusbar(ctx, store, cfg)
    if not store or not store.total_gb or store.total_gb <= 0 then return nil end

    local pct = store.percent or 0
    local color = ctx:threshold_color(pct, store.warn_pct or 80, store.crit_pct or 95)

    local tooltip = string.format("Memory: %.1f GB used / %.1f GB total (%d%%)",
                                  store.used_gb, store.total_gb, pct)
    -- Only show the swap line when we know swap exists. The macOS branch
    -- now populates swap_total_gb via sysctl; the Linux branch reads
    -- /proc/meminfo. Either way we omit a "0.0 / 0.0 GB" line.
    if (store.swap_total_gb or 0) > 0 then
        tooltip = tooltip .. string.format("\nSwap: %.1f / %.1f GB",
                                           store.swap_used_gb or 0, store.swap_total_gb or 0)
    end

    return {
        label = "Mem",
        value = string.format("%.1f/%.0fG", store.used_gb, store.total_gb),
        color = color,
        tooltip = tooltip,
        icon = "",
    }
end

function render(ctx, store, cfg)
    if not store or not store.total_gb or store.total_gb <= 0 then
        ctx:text("No memory data.")
        return
    end

    -- Headline numbers.
    ctx:stat_row({
        cards = {
            { label = "Used",   value = string.format("%.1f G", store.used_gb),
              color = ctx:threshold_color(store.percent or 0, store.warn_pct or 80, store.crit_pct or 95) },
            { label = "Cached", value = string.format("%.1f G", store.cached_gb or 0) },
            { label = "Free",   value = string.format("%.1f G", store.free_gb or 0) },
            { label = "Total",  value = string.format("%.0f G", store.total_gb) },
        },
    })

    if (store.swap_total_gb or 0) > 0 then
        ctx:space(4)
        ctx:stat_row({
            cards = {
                { label = "Swap used",  value = string.format("%.1f G", store.swap_used_gb or 0),
                  color = ((store.swap_used_gb or 0) > 0) and "yellow" or "green" },
                { label = "Swap total", value = string.format("%.1f G", store.swap_total_gb or 0) },
            },
        })
    end

    ctx:space(6)

    -- Multi-series memory breakdown over the last hour.
    if store.range then
        local data_used    = store:range("1h", "used")
        local data_cached  = store:range("1h", "cached")
        local data_buffers = store:range("1h", "buffers")
        local data_free    = store:range("1h", "free")

        ctx:line_graph({
            title = "Memory breakdown (1h, GB)",
            series = {
                { name = "used",    color = "red",    data = data_used },
                { name = "cached",  color = "yellow", data = data_cached },
                { name = "buffers", color = "green",  data = data_buffers },
                { name = "free",    color = "#888888", data = data_free },
            },
            unit = "G",
            y_min = 0,
            warn = (store.warn_pct or 80) / 100 * store.total_gb,
            crit = (store.crit_pct or 95) / 100 * store.total_gb,
            height = 140,
        })
    end
end
