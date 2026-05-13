plugin = {
    id = "cpu-memory",
    name = "CPU & Memory",
    description = "CPU and memory usage monitoring",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "System",
    default_interval = 15,
    min_interval = 10,
    data_type = "timeseries",
    retention = "24h",
    settings = {
        { key = "warn_threshold", label = "Warning Threshold (%)", type = "number", default = "70" },
        { key = "crit_threshold", label = "Critical Threshold (%)", type = "number", default = "90" },
        { key = "graph_range", label = "Graph Time Range", type = "string", default = "1h" },
    },
}

function collect(ssh, cfg)
    local os_type = ssh:os()

    if os_type == "Linux" then
        local stat = ssh:exec("head -1 /proc/stat") or ""
        local meminfo = ssh:exec("head -3 /proc/meminfo") or ""
        return "linux\n---\n" .. stat .. "\n---\n" .. meminfo
    elseif os_type == "Darwin" then
        local top = ssh:exec("top -l 1 -n 0 | head -10") or ""
        local vm = ssh:exec("vm_stat") or ""
        local mem = ssh:exec("sysctl hw.memsize") or ""
        return "darwin\n---\n" .. top .. "\n---\n" .. vm .. "\n---\n" .. mem
    else
        return "unknown\n---\n\n---\n"
    end
end

function transform(raw, cfg)
    local sections = {}
    for section in raw:gmatch("([^%-%-%-]+)") do
        table.insert(sections, section)
    end

    local os_type = (sections[1] or ""):match("^%s*(.-)%s*$") or ""
    local cpu_user = 0
    local cpu_system = 0
    local mem_total = 0
    local mem_used = 0
    local mem_pct = 0

    if os_type == "linux" then
        -- Parse /proc/stat: cpu user nice system idle ...
        local stat_line = sections[2] or ""
        local user, nice, system, idle = stat_line:match("cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if user then
            local u = tonumber(user) or 0
            local n = tonumber(nice) or 0
            local s = tonumber(system) or 0
            local i = tonumber(idle) or 0
            local total = u + n + s + i
            if total > 0 then
                cpu_user = (u + n) / total * 100
                cpu_system = s / total * 100
            end
        end

        -- Parse /proc/meminfo
        local meminfo = sections[3] or ""
        local mem_total_kb = tonumber(meminfo:match("MemTotal:%s*(%d+)")) or 0
        local mem_avail_kb = tonumber(meminfo:match("MemAvailable:%s*(%d+)")) or 0
        mem_total = mem_total_kb / 1024 / 1024 -- GB
        mem_used = (mem_total_kb - mem_avail_kb) / 1024 / 1024
        if mem_total > 0 then
            mem_pct = mem_used / mem_total * 100
        end

    elseif os_type == "darwin" then
        -- Parse top output for CPU
        local top_out = sections[2] or ""
        local user_pct = top_out:match("(%d+%.?%d*)%%  user") or top_out:match("CPU usage: (%d+%.?%d*)%%  user")
        local sys_pct = top_out:match("(%d+%.?%d*)%%  sys")
        cpu_user = tonumber(user_pct) or 0
        cpu_system = tonumber(sys_pct) or 0

        -- Parse vm_stat for memory
        local vm_out = sections[3] or ""
        local page_size = 16384
        local ps = vm_out:match("page size of (%d+)")
        if ps then page_size = tonumber(ps) or 16384 end

        local free = tonumber(vm_out:match("Pages free:%s*(%d+)")) or 0
        local active = tonumber(vm_out:match("Pages active:%s*(%d+)")) or 0
        local inactive = tonumber(vm_out:match("Pages inactive:%s*(%d+)")) or 0
        local wired = tonumber(vm_out:match("Pages wired down:%s*(%d+)")) or 0
        local speculative = tonumber(vm_out:match("Pages speculative:%s*(%d+)")) or 0

        local total_mem_str = sections[4] or ""
        local total_bytes = tonumber(total_mem_str:match("hw.memsize:%s*(%d+)")) or 0
        mem_total = total_bytes / 1024 / 1024 / 1024

        local used_pages = active + wired
        mem_used = used_pages * page_size / 1024 / 1024 / 1024
        if mem_total > 0 then
            mem_pct = mem_used / mem_total * 100
        end
    end

    return {
        cpu_user = cpu_user,
        cpu_system = cpu_system,
        cpu_total = cpu_user + cpu_system,
        mem_total_gb = mem_total,
        mem_used_gb = mem_used,
        mem_pct = mem_pct,
        _ts = {
            { series = "cpu_user", value = cpu_user, unit = "%" },
            { series = "cpu_system", value = cpu_system, unit = "%" },
            { series = "mem_used", value = mem_pct, unit = "%" },
        },
    }
end

function render(ctx, store, cfg)
    if not store then return end

    local warn = (cfg and cfg.warn_threshold) or 70
    local crit = (cfg and cfg.crit_threshold) or 90
    local graph_range = (cfg and cfg.graph_range) or "1h"

    local cpu_total = (store.cpu_total or 0)
    local cpu_color = ctx:threshold_color(cpu_total, warn, crit)
    local mem_pct = (store.mem_pct or 0)
    local mem_color = ctx:threshold_color(mem_pct, warn, crit)

    ctx:stat_row({
        cards = {
            {
                label = "CPU",
                value = string.format("%.0f", cpu_total),
                unit = "%",
                color = cpu_color,
                tooltip = string.format("User: %.1f%%, System: %.1f%%", store.cpu_user or 0, store.cpu_system or 0),
            },
            {
                label = "Memory",
                value = string.format("%.0f", mem_pct),
                unit = "%",
                color = mem_color,
                tooltip = string.format("%.1f / %.1f GB", store.mem_used_gb or 0, store.mem_total_gb or 0),
            },
        },
    })

    ctx:space(4)

    -- CPU usage over time
    local cpu_user_data = store:range(graph_range, "cpu_user")
    local cpu_sys_data = store:range(graph_range, "cpu_system")

    ctx:line_graph({
        title = "CPU Usage (" .. graph_range .. ")",
        series = {
            { name = "user", color = "green", data = cpu_user_data },
            { name = "system", color = "yellow", data = cpu_sys_data },
        },
        unit = "%",
        y_min = 0,
        y_max = 100,
        warn = warn,
        crit = crit,
        height = 100,
    })

    ctx:space(4)

    -- Memory usage over time
    local mem_data = store:range(graph_range, "mem_used")

    ctx:line_graph({
        title = "Memory Usage (" .. graph_range .. ")",
        series = {
            { name = "memory", color = "blue", data = mem_data },
        },
        unit = "%",
        y_min = 0,
        y_max = 100,
        warn = warn,
        crit = crit,
        height = 100,
    })
end
