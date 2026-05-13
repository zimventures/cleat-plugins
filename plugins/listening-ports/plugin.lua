plugin = {
    id = "listening-ports",
    name = "Listening Ports",
    description = "TCP services listening on the host (port, protocol, process, PID)",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "Network",
    default_interval = 60,
    min_interval = 15,
    data_type = "table",
}

function collect(ssh, cfg)
    -- Linux: ss is the modern replacement for netstat. -t = TCP, -l = listening,
    -- -n = numeric, -p = process info (requires sudo for full info on some distros).
    local linux = ssh:exec("ss -tlnp 2>/dev/null") or ""
    if linux ~= "" and linux:match("LISTEN") then
        return "linux\n" .. linux
    end

    -- Linux fallback when ss isn't installed.
    local netstat = ssh:exec("netstat -tlnp 2>/dev/null") or ""
    if netstat ~= "" and netstat:match("LISTEN") then
        return "netstat\n" .. netstat
    end

    -- macOS: lsof is the most reliable way to list TCP listeners with process info.
    local mac = ssh:exec("lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null") or ""
    return "mac\n" .. mac
end

local function parse_ss_addr(addr)
    -- "0.0.0.0:22"  -> "*", "22"
    -- "[::]:22"     -> "*", "22"
    -- "127.0.0.1:6379" -> "127.0.0.1", "6379"
    -- "[::1]:631"  -> "::1", "631"
    local host, port = addr:match("^%[(.+)%]:(%d+)$")  -- IPv6 form
    if not host then
        host, port = addr:match("^(.-):(%d+)$")        -- IPv4 form
    end
    if host == "0.0.0.0" or host == "::" or host == "*" then host = "*" end
    return host or "?", port or "?"
end

local function parse_ss_users(s)
    -- users:(("sshd",pid=1234,fd=3),("sshd",pid=1235,fd=4))
    -- Capture the first (process, pid) pair.
    local proc, pid = s:match('%(%("([^"]+)",pid=(%d+)')
    return proc, pid
end

function transform(raw, cfg)
    local platform, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""

    local rows = {}
    local first = true

    if platform == "linux" then
        -- ss -tlnp: "State   Recv-Q Send-Q  Local Address:Port  Peer Address:Port  [users]"
        for line in body:gmatch("([^\n]+)") do
            if first then
                first = false
            else
                local fields = {}
                for f in line:gmatch("%S+") do table.insert(fields, f) end
                -- Layout depends on ss version; usually: state, rq, sq, local, peer, users
                if #fields >= 5 then
                    local local_addr = fields[4]
                    local users      = fields[6] or ""
                    local host, port = parse_ss_addr(local_addr)
                    local proc, pid  = parse_ss_users(users)
                    table.insert(rows, { port, "tcp", proc or "?", pid or "?", host })
                end
            end
        end
    elseif platform == "netstat" then
        -- netstat -tlnp: "Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program name"
        for line in body:gmatch("([^\n]+)") do
            if line:match("^tcp") then
                local fields = {}
                for f in line:gmatch("%S+") do table.insert(fields, f) end
                if #fields >= 7 then
                    local local_addr = fields[4]
                    local pidprog    = fields[7]
                    local host, port = parse_ss_addr(local_addr)
                    local pid, proc  = pidprog:match("^(%d+)/(.+)$")
                    table.insert(rows, { port, "tcp", proc or "?", pid or "?", host })
                end
            end
        end
    elseif platform == "mac" then
        -- lsof: "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
        for line in body:gmatch("([^\n]+)") do
            if first then
                first = false
            else
                local fields = {}
                for f in line:gmatch("%S+") do table.insert(fields, f) end
                if #fields >= 9 then
                    local proc = fields[1]
                    local pid  = fields[2]
                    local name = fields[#fields]                  -- "*:22 (LISTEN)" / "127.0.0.1:631"
                    local addr = name:match("^(.-)%s") or name
                    local host, port = parse_ss_addr(addr)
                    table.insert(rows, { port, "tcp", proc, pid, host })
                end
            end
        end
    end

    -- Sort by numeric port asc.
    table.sort(rows, function(a, b)
        local pa = tonumber(a[1]) or 0
        local pb = tonumber(b[1]) or 0
        return pa < pb
    end)

    -- Note: don't name this `count` — the StoreAPI registers a `count` method
    -- on every store table (for timeseries plugins) and would shadow the field.
    return {
        platform = platform or "unknown",
        rows = rows,
        listener_count = #rows,
    }
end

function render(ctx, store, cfg)
    if not store then
        ctx:text("No data.")
        return
    end

    ctx:text(string.format("%d listening TCP service(s)", store.listener_count or 0))
    ctx:space(4)

    if not store.rows or #store.rows == 0 then
        ctx:text("No listening sockets found.")
        return
    end

    ctx:table({
        title = "Open ports",
        columns = { "Port", "Proto", "Process", "PID", "Bind" },
        rows = store.rows,
    })
end
