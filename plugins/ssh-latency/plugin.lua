plugin = {
    id = "ssh-latency",
    name = "SSH Latency",
    description = "SSH round-trip latency monitoring",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "Network",
    default_interval = 15,
    min_interval = 5,
    data_type = "timeseries",
    retention = "24h",
    statusbar = true,
    statusbar_order = 5,
    settings = {
        { key = "warn_ms", label = "Warning Threshold (ms)", type = "number", default = "100" },
        { key = "crit_ms", label = "Critical Threshold (ms)", type = "number", default = "500" },
    },
}

function collect(ssh, cfg)
    local latency = ssh:ping()
    return tostring(latency)
end

function transform(raw, cfg)
    local ms = tonumber(raw) or -1
    if ms < 0 then
        return { latency_ms = 0, status = "error" }
    end

    return {
        latency_ms = ms,
        status = "ok",
        _ts = {
            { series = "", value = ms, unit = "ms" },
        },
    }
end

function render_statusbar(ctx, store, cfg)
    if not store or not store.latency_ms then return nil end

    local warn = tonumber(cfg and cfg.warn_ms) or 100
    local crit = tonumber(cfg and cfg.crit_ms) or 500

    local ms = store.latency_ms
    local color = ctx:threshold_color(ms, warn, crit)

    -- Pull the last 15 min of latency samples for the sparkline.
    local values = {}
    local sum, count, vmin, vmax = 0, 0, nil, nil
    if store.range then
        for _, pt in ipairs(store:range("15m") or {}) do
            table.insert(values, pt.v)
            sum = sum + pt.v
            count = count + 1
            if not vmin or pt.v < vmin then vmin = pt.v end
            if not vmax or pt.v > vmax then vmax = pt.v end
        end
    end
    local avg = (count > 0) and (sum / count) or ms

    local stats = {
        { label = "Now", value = string.format("%.0f ms", ms), color = color },
        { label = "Avg 15m", value = string.format("%.0f ms", avg) },
    }
    if vmin and vmax then
        table.insert(stats, { label = "Min", value = string.format("%.0f ms", vmin) })
        table.insert(stats, { label = "Max", value = string.format("%.0f ms", vmax),
                              color = ctx:threshold_color(vmax, warn, crit) })
    end

    return {
        label = "Latency",
        value = string.format("%.0fms", ms),
        color = color,
        icon = "",
        tooltip = {
            sparkline = (#values > 0) and {
                values = values,
                color = color,
                title = "Last 15 min",
                height = 28,
                show_minmax = true,
            } or nil,
            stats = stats,
            footer = "Click to open Latency panel",
            clickable = true,
        },
    }
end

function render(ctx, store, cfg)
    -- Current latency stat card
    local warn = (cfg and cfg.warn_ms) or 100
    local crit = (cfg and cfg.crit_ms) or 500

    local ms = store and store.latency_ms or 0
    local color = ctx:threshold_color(ms, warn, crit)

    -- Get historical data for sparkline
    local recent = store:range("5m")

    ctx:stat_card({
        label = "SSH Latency",
        value = string.format("%.0f", ms),
        unit = "ms",
        color = color,
        tooltip = string.format("Current SSH round-trip latency: %.1f ms", ms),
        sparkline = recent,
    })

    ctx:space(4)

    -- 1-hour trend line graph
    local data_1h = store:range("1h")
    ctx:line_graph({
        title = "Latency (1h)",
        series = {
            { name = "latency", color = "green", data = data_1h },
        },
        unit = "ms",
        y_min = 0,
        warn = warn,
        crit = crit,
        height = 120,
    })

    ctx:space(4)

    -- Stats summary
    local avg = store:avg("1h")
    local max_val = store:max("1h")
    local min_val = store:min("1h")
    local count = store:count()

    ctx:stat_row({
        cards = {
            { label = "Avg", value = string.format("%.0f", avg), unit = "ms", color = "green" },
            { label = "Max", value = string.format("%.0f", max_val), unit = "ms", color = ctx:threshold_color(max_val, warn, crit) },
            { label = "Min", value = string.format("%.0f", min_val), unit = "ms", color = "green" },
        },
    })
end
