plugin = {
    id = "load-average",
    name = "Load Average",
    description = "System load average with trend graphs",
    version = "1.0.1",
    author = "Cleat",
    icon = "",
    category = "System",
    default_interval = 15,
    min_interval = 10,
    data_type = "timeseries",
    retention = "24h",
}

function collect(ssh, cfg)
    local load = ssh:exec("cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null || uptime") or ""
    local cpus = ssh:cpu_count()
    return load .. "\n---\n" .. tostring(cpus)
end

function transform(raw, cfg)
    -- Split on literal "\n---\n" delimiter; the previous `[^%-%-%-]+`
    -- pattern was a negated character class containing just `-`, which
    -- split on any hyphen and shifted section indices.
    local sections = {}
    local pos = 1
    while true do
        local s, e = raw:find("\n---\n", pos, true)
        if not s then
            table.insert(sections, raw:sub(pos))
            break
        end
        table.insert(sections, raw:sub(pos, s - 1))
        pos = e + 1
    end

    local load_raw = (sections[1] or ""):match("^%s*(.-)%s*$") or ""
    local ncpus = tonumber((sections[2] or ""):match("(%d+)")) or 1

    local load1, load5, load15 = 0, 0, 0

    -- Try /proc/loadavg format: "0.50 0.30 0.20 1/234 5678"
    local l1, l5, l15 = load_raw:match("^(%d+%.?%d*)%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
    if l1 then
        load1 = tonumber(l1) or 0
        load5 = tonumber(l5) or 0
        load15 = tonumber(l15) or 0
    else
        -- macOS sysctl: "{ 0.50 0.30 0.20 }"
        l1, l5, l15 = load_raw:match("{%s*(%d+%.?%d*)%s+(%d+%.?%d*)%s+(%d+%.?%d*)")
        if l1 then
            load1 = tonumber(l1) or 0
            load5 = tonumber(l5) or 0
            load15 = tonumber(l15) or 0
        else
            -- uptime: "load average: 0.50, 0.30, 0.20"
            l1, l5, l15 = load_raw:match("load average:%s*(%d+%.?%d*),%s*(%d+%.?%d*),%s*(%d+%.?%d*)")
            if l1 then
                load1 = tonumber(l1) or 0
                load5 = tonumber(l5) or 0
                load15 = tonumber(l15) or 0
            end
        end
    end

    return {
        load1 = load1,
        load5 = load5,
        load15 = load15,
        ncpus = ncpus,
        _ts = {
            { series = "load1", value = load1, unit = "" },
            { series = "load5", value = load5, unit = "" },
            { series = "load15", value = load15, unit = "" },
        },
    }
end

function render(ctx, store, cfg)
    if not store then return end

    local ncpus = store.ncpus or 1
    local load1 = store.load1 or 0
    local load5 = store.load5 or 0
    local load15 = store.load15 or 0
    local ratio = (ncpus > 0) and (load1 / ncpus) or 0

    ctx:stat_row({
        cards = {
            {
                label = "1 min",
                value = string.format("%.2f", load1),
                color = ctx:threshold_color(ratio, 0.7, 1.0),
                tooltip = string.format("%.0f%% of %d CPUs", ratio * 100, ncpus),
            },
            {
                label = "5 min",
                value = string.format("%.2f", load5),
                color = ctx:threshold_color(load5 / ncpus, 0.7, 1.0),
            },
            {
                label = "15 min",
                value = string.format("%.2f", load15),
                color = ctx:threshold_color(load15 / ncpus, 0.7, 1.0),
            },
        },
    })

    ctx:space(4)

    -- Load average trend
    local data1 = store:range("1h", "load1")
    local data5 = store:range("1h", "load5")
    local data15 = store:range("1h", "load15")

    ctx:line_graph({
        title = "Load Average (1h)",
        series = {
            { name = "1 min", color = "green", data = data1 },
            { name = "5 min", color = "yellow", data = data5 },
            { name = "15 min", color = "red", data = data15 },
        },
        y_min = 0,
        warn = ncpus * 0.7,
        crit = ncpus,
        height = 120,
    })
end
