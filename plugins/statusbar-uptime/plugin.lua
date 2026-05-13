plugin = {
    id = "statusbar-uptime",
    name = "Up",
    description = "System uptime — status bar segment + reconnect-resilience panel",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Status Bar",
    default_interval = 60,
    min_interval = 30,
    -- Promoted from "snapshot" to "timeseries" so the panel can show a
    -- sparkline of uptime growth across reconnects. A reset of the
    -- sparkline is a strong visual signal that the host rebooted.
    data_type = "timeseries",
    retention = "24h",
    statusbar = true,
    statusbar_order = 10,
}

function collect(ssh, cfg)
    local raw = ssh:exec("cat /proc/uptime 2>/dev/null") or ""
    if raw == "" then
        raw = ssh:exec("echo $(sysctl -n kern.boottime 2>/dev/null | sed 's/.*sec = \\([0-9]*\\).*/\\1/') $(date +%s)") or ""
    end
    return raw
end

function transform(raw, cfg)
    local uptime_seconds = 0
    local secs = raw:match("^%s*(%d+%.?%d*)")
    if secs then
        uptime_seconds = math.floor(tonumber(secs))
    else
        local boot, now = raw:match("(%d+)%s+(%d+)")
        if boot and now then
            uptime_seconds = tonumber(now) - tonumber(boot)
            if uptime_seconds < 0 then uptime_seconds = 0 end
        end
    end

    -- Emit a single timeseries point per tick so the render() panel can
    -- graph uptime-over-time. A sudden drop in the line means the host
    -- rebooted between ticks.
    --
    -- Skip the _ts emission when uptime parsing failed (still 0). The panel
    -- treats drops to zero as a reboot signal, so a transient parse failure
    -- shouldn't fabricate a false reboot spike on the graph.
    local result = { uptime_seconds = uptime_seconds }
    if uptime_seconds > 0 then
        result._ts = { { series = "uptime_hours", value = uptime_seconds / 3600.0, unit = "h" } }
    end
    return result
end

local function format_uptime(secs)
    local days = math.floor(secs / 86400)
    local hours = math.floor((secs % 86400) / 3600)
    local mins = math.floor((secs % 3600) / 60)
    if days > 0 then return string.format("%dd %dh", days, hours) end
    return string.format("%dh %dm", hours, mins)
end

function render_statusbar(ctx, store, cfg)
    local secs = (store and store.uptime_seconds) or 0
    if secs <= 0 then return nil end

    local days = math.floor(secs / 86400)
    local hours = math.floor((secs % 86400) / 3600)
    return {
        label = "Up",
        value = format_uptime(secs),
        color = "green",
        tooltip = string.format("System uptime: %d days, %d hours", days, hours),
        icon = "",
    }
end

function render(ctx, store, cfg)
    local secs = (store and store.uptime_seconds) or 0

    -- Pull the last 24h of uptime samples for the trend sparkline. A flat
    -- line means a stable host; the line dropping near zero between
    -- samples is a reboot signal.
    local series = (store.range and store:range("24h", "uptime_hours")) or {}

    local boot_text = "?"
    if secs > 0 then
        local boot_epoch = os.time() - secs
        boot_text = os.date("%Y-%m-%d %H:%M", boot_epoch)
    end

    ctx:stat_row({
        cards = {
            { label = "Uptime",  value = format_uptime(secs), color = "green" },
            { label = "Booted",  value = boot_text },
            { label = "Samples", value = tostring(#series) },
        },
    })

    ctx:space(4)

    if #series > 0 then
        ctx:line_graph({
            title = "Uptime (hours, 24h)",
            series = {
                { name = "uptime_hours", color = "green", data = series },
            },
            unit = "h",
            y_min = 0,
            height = 120,
        })
    else
        ctx:text("Trend appears once a few ticks have collected.")
    end
end
