plugin = {
    id = "docker-containers",
    name = "Docker Containers",
    description = "Running Docker containers (name, image, status, ports, uptime)",
    version = "1.0.1",
    author = "Cleat",
    icon = "",
    category = "Docker",
    default_interval = 30,
    min_interval = 10,
    data_type = "table",
    settings = {
        { key = "include_stopped", label = "Include stopped containers", type = "boolean", default = "false" },
    },
}

function collect(ssh, cfg)
    local include_stopped = cfg and cfg.include_stopped
    if include_stopped == "true" or include_stopped == true then
        include_stopped = true
    else
        include_stopped = false
    end

    -- Use one-line-per-container format with tab separators. Avoids JSON
    -- escaping concerns and works on docker engines too old for `--format json`.
    local fmt = "{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\\t{{.RunningFor}}"
    local cmd
    if include_stopped then
        cmd = "docker ps -a --format \"" .. fmt .. "\" 2>/dev/null"
    else
        cmd = "docker ps --format \"" .. fmt .. "\" 2>/dev/null"
    end
    local out = ssh:exec(cmd) or ""
    return out
end

local function trim(s)
    -- The outer parens collapse gsub's multi-return (string, count) down
    -- to just the string. Without them, callers like
    -- `table.insert(t, trim(f))` would pass both values, and table.insert
    -- would treat the count as a pos index — breaking parsing at runtime.
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function transform(raw, cfg)
    local rows = {}
    local up = 0
    local down = 0

    for line in raw:gmatch("([^\n]+)") do
        local fields = {}
        for f in (line .. "\t"):gmatch("([^\t]*)\t") do
            table.insert(fields, trim(f))
        end
        if #fields >= 5 and fields[1] ~= "" then
            local status = fields[3]
            if status:lower():find("^up") then
                up = up + 1
            else
                down = down + 1
            end
            -- Ports field can be very long; truncate for table display.
            local ports = fields[4]
            if #ports > 60 then ports = ports:sub(1, 57) .. "..." end
            table.insert(rows, { fields[1], fields[2], status, ports, fields[5] })
        end
    end

    return {
        rows = rows,
        running = up,
        stopped = down,
        total = up + down,
    }
end

function render(ctx, store, cfg)
    if not store or not store.rows then
        ctx:text("docker not available on this host.")
        return
    end

    ctx:stat_row({
        cards = {
            { label = "Running", value = tostring(store.running or 0), color = "green" },
            { label = "Stopped", value = tostring(store.stopped or 0),
              color = (store.stopped and store.stopped > 0) and "yellow" or "green" },
            { label = "Total",   value = tostring(store.total or 0) },
        },
    })

    ctx:space(6)

    if #store.rows == 0 then
        ctx:text("No containers.")
        return
    end

    ctx:table({
        title = "Containers",
        columns = { "Name", "Image", "Status", "Ports", "Uptime" },
        rows = store.rows,
    })
end
