plugin = {
    id = "statusbar-load",
    name = "Load",
    description = "System load average for status bar (with rich tooltip)",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Status Bar",
    default_interval = 15,
    min_interval = 10,
    data_type = "timeseries",
    retention = "1h",
    statusbar = true,
    statusbar_order = 20,
    settings = {
        { key = "warn_threshold", label = "Warning Threshold", type = "number", default = "0.7" },
        { key = "crit_threshold", label = "Critical Threshold", type = "number", default = "1.0" },
    },
}

function collect(ssh, cfg)
    local load = ssh:exec("cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null || uptime") or ""
    local cpus = ssh:exec("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1") or "1"
    return load .. "\n---\n" .. cpus
end

function transform(raw, cfg)
    local sections = {}
    for section in raw:gmatch("([^%-%-%-]+)") do
        table.insert(sections, section)
    end

    local load_raw = (sections[1] or ""):match("^%s*(.-)%s*$") or ""
    local cpus_raw = (sections[2] or ""):match("^%s*(%d+)") or "1"
    local ncpus = tonumber(cpus_raw) or 1

    -- Parse load1, load5, load15 from various formats.
    local load1, load5, load15 = 0, 0, 0
    local l1, l5, l15 = load_raw:match("^(%d+%.?%d*)%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
    if l1 then
        load1, load5, load15 = tonumber(l1) or 0, tonumber(l5) or 0, tonumber(l15) or 0
    else
        l1, l5, l15 = load_raw:match("{%s*(%d+%.?%d*)%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
        if l1 then
            load1, load5, load15 = tonumber(l1) or 0, tonumber(l5) or 0, tonumber(l15) or 0
        else
            l1, l5, l15 = load_raw:match("load average:%s*(%d+%.?%d*),%s*(%d+%.?%d*),%s*(%d+%.?%d*)")
            if l1 then
                load1, load5, load15 = tonumber(l1) or 0, tonumber(l5) or 0, tonumber(l15) or 0
            end
        end
    end

    return {
        load1 = load1,
        load5 = load5,
        load15 = load15,
        ncpus = ncpus,
        ratio = (ncpus > 0) and (load1 / ncpus) or 0,
        _ts = {
            { series = "load1", value = load1 },
        },
    }
end

function render_statusbar(ctx, store, cfg)
    if not store or not store.load1 then return nil end

    local ratio = store.ratio or 0
    local warn = (cfg and tonumber(cfg.warn_threshold)) or 0.7
    local crit = (cfg and tonumber(cfg.crit_threshold)) or 1.0
    local color = ctx:threshold_color(ratio, warn, crit)
    local ncpus = store.ncpus or 1

    -- Build a sparkline from the last 30 minutes of load1.
    local values = {}
    if store.range then
        local pts = store:range("30m", "load1") or {}
        for _, pt in ipairs(pts) do
            table.insert(values, pt.v)
        end
    end

    -- Per-segment stat rows for the rich tooltip.
    local stats = {
        { label = "1 min",  value = string.format("%.2f", store.load1 or 0), color = color },
        { label = "5 min",  value = string.format("%.2f", store.load5 or 0) },
        { label = "15 min", value = string.format("%.2f", store.load15 or 0) },
        { label = "CPUs",   value = tostring(ncpus) },
        { label = "Util",   value = string.format("%.0f%%", ratio * 100), color = color },
    }

    return {
        label = "Load",
        value = string.format("%.2f", store.load1),
        color = color,
        icon = "",
        tooltip = {
            sparkline = (#values > 0) and {
                values = values,
                color = color,
                title = "Last 30 min",
                height = 28,
                show_minmax = true,
            } or nil,
            stats = stats,
            footer = "Click to open Load panel",
            clickable = true,
        },
    }
end

-- Optional render() so the plugin view panel has something meaningful when
-- opened by clicking the status bar segment.
function render(ctx, store, cfg)
    if not store or not store.load1 then return end
    local ncpus = store.ncpus or 1

    ctx:stat_row({
        cards = {
            { label = "1 min",  value = string.format("%.2f", store.load1),  color = ctx:threshold_color((store.load1  or 0) / ncpus, 0.7, 1.0) },
            { label = "5 min",  value = string.format("%.2f", store.load5),  color = ctx:threshold_color((store.load5  or 0) / ncpus, 0.7, 1.0) },
            { label = "15 min", value = string.format("%.2f", store.load15), color = ctx:threshold_color((store.load15 or 0) / ncpus, 0.7, 1.0) },
        },
    })

    ctx:space(4)

    local data = (store.range and store:range("1h", "load1")) or {}
    ctx:line_graph({
        title = "Load (1h)",
        series = {
            { name = "1 min", color = "green", data = data },
        },
        y_min = 0,
        warn = ncpus * 0.7,
        crit = ncpus,
        height = 120,
    })
end
