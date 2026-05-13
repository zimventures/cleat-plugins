plugin = {
    id = "auth-failures",
    name = "Auth Failures",
    description = "Surfaces failed SSH authentication attempts (user, source IP, timestamp)",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Logs",
    default_interval = 30,
    min_interval = 5,
    data_type = "log",
    retention = "500",
    -- Plugin can run in either polling (default) or streaming mode.
    -- The engine consults metadata.streaming + cfg.mode to decide.
    streaming = true,
    streaming_idle_seconds = 60, -- journalctl -f stays silent forever otherwise
    settings = {
        { key = "mode", label = "Collection mode", type = "string", default = "polling",
          values = { "polling", "stream" } },
        { key = "since", label = "Lookback window (polling only)", type = "string", default = "1h" },
    },
}

local last_seen_ts = 0

local function shell_escape(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function collect(ssh, cfg)
    local mode = (cfg and cfg.mode) or "polling"
    if mode == "stream" then
        -- Engine handles the channel; we just declare what to run.
        --
        -- journalctl block-buffers when its stdout is a pipe (isatty=false),
        -- so we wrap it in `stdbuf -oL` to force line-buffered output.
        -- Without this, lines can sit in journalctl's buffer for many
        -- seconds before reaching us — the whole point of streaming is
        -- that they show up immediately.
        --
        -- We also drop the grep filter that the polling path uses: filtering
        -- in transform() (Lua) means we don't have a second buffering layer
        -- to fight, and the parser there already classifies non-auth lines
        -- via parse_entry's fallback.
        return "stdbuf -oL journalctl _SYSTEMD_UNIT=ssh.service _SYSTEMD_UNIT=sshd.service " ..
               "-f -o short-iso --no-pager"
    end

    local since = (cfg and cfg.since) or "1h"

    -- Linux: journalctl scoped to ssh.service.
    local linux = ssh:exec(
        "journalctl _SYSTEMD_UNIT=ssh.service _SYSTEMD_UNIT=sshd.service " ..
        "--since=" .. shell_escape(since) .. " -o short-iso --no-pager 2>/dev/null | " ..
        "grep -E 'Failed password|Invalid user|authentication failure' || true"
    ) or ""

    if linux ~= "" then
        return "linux\n" .. linux
    end

    -- Fallback: /var/log/auth.log
    local authlog = ssh:exec(
        "tail -n 500 /var/log/auth.log /var/log/secure 2>/dev/null | " ..
        "grep -E 'Failed password|Invalid user|authentication failure' || true"
    ) or ""

    if authlog ~= "" then
        return "authlog\n" .. authlog
    end

    -- macOS: log show predicate on sshd subsystem.
    local mac = ssh:exec(
        "log show --last " .. shell_escape(since) ..
        " --style syslog --predicate 'process == \"sshd\"' 2>/dev/null | " ..
        "grep -E 'Failed|Invalid' || true"
    ) or ""

    return "mac\n" .. mac
end

local kMonths = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

-- Best-effort parse of common log timestamp shapes. Returns unix epoch or 0.
local function parse_timestamp(s)
    -- ISO 8601
    local Y, M, D, h, m, sec = s:match("(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
    if Y then
        return os.time({
            year = tonumber(Y), month = tonumber(M), day = tonumber(D),
            hour = tonumber(h), min = tonumber(m), sec = tonumber(sec),
        })
    end
    -- Classic syslog (no year): "Apr 30 12:34:56"
    local mon, day, hh, mm, ss = s:match("(%a%a%a)%s+(%d+)%s+(%d%d):(%d%d):(%d%d)")
    if mon and kMonths[mon] then
        local now = os.date("*t")
        local year = now.year
        if kMonths[mon] > now.month + 1 then
            year = year - 1
        end
        return os.time({
            year = year, month = kMonths[mon], day = tonumber(day),
            hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss),
        })
    end
    return 0
end

-- Bounded line-hash set as a backup dedup for entries with no parseable
-- timestamp. See error-log-monitor for the rationale.
local kSeenMax = 500
local seen_lines = {}
local seen_count = 0
local function should_emit_unparsed(line)
    if seen_lines[line] then
        return false
    end
    seen_lines[line] = true
    seen_count = seen_count + 1
    if seen_count > kSeenMax then
        seen_lines = {}
        seen_count = 0
    end
    return true
end

-- Real-world OpenSSH + PAM auth-failure log shapes we care about. Each
-- pattern returns (user, ip) when matched.
--
--   sshd: "Failed password for invalid user admin from 1.2.3.4 port 41234 ssh2"
--   sshd: "Failed password for rob from ::1 port 41234 ssh2"
--   sshd: "Invalid user backup from 5.6.7.8 port 22"
--   sshd: "Connection closed by [authenticating|invalid] user X 1.2.3.4 port 22 [preauth]"
--   sshd: "Disconnected from [authenticating|invalid] user X 1.2.3.4 port 22 [preauth]"
--   pam_unix(sshd:auth): "authentication failure; ... rhost=::1  user=rob"
local function parse_entry(line)
    -- User candidates, tried in priority order.
    local user =
        line:match("for invalid user ([%w._%-]+)") or
        line:match("for ([%w._%-]+) from") or
        line:match("Invalid user ([%w._%-]+) from") or
        line:match("authenticating user ([%w._%-]+) ") or
        line:match("invalid user ([%w._%-]+) ") or
        line:match("user=([%w._%-]+)") or
        "?"

    -- IP candidates. Order matters: anchor on `port` where possible to
    -- avoid grabbing the wrong token, then fall through to softer patterns.
    local ip =
        line:match("from ([%d%.]+) port") or
        line:match("from ([0-9a-fA-F:]+) port") or
        line:match("rhost=([%w%.:]+)") or
        line:match("authenticating user [%w._%-]+ ([0-9a-fA-F.:]+) ") or
        line:match("invalid user [%w._%-]+ ([0-9a-fA-F.:]+) ") or
        line:match("from ([%d%.]+)") or
        line:match("from ([0-9a-fA-F:]+)") or
        "?"

    local pid = line:match("sshd%[(%d+)%]")
    return user, ip, pid
end

-- Build an iterator over input lines that handles either tick mode:
--   - Polling: raw is a string with a "<platform>\n<body>" prefix.
--   - Streaming: raw is a Lua table of lines from the engine.
local function lines_from(raw)
    if type(raw) == "table" then
        local i = 0
        return function()
            i = i + 1
            return raw[i]
        end, "stream"
    end
    local _, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""
    return body:gmatch("([^\n]+)"), nil
end

-- Streaming mode passes us every sshd journal entry. Polling mode
-- pre-filters via grep, so this check is a no-op there. Done as a
-- plain-string search so the patterns aren't interpreted as Lua patterns.
local function looks_like_auth_failure(line)
    return (line:find("Failed password", 1, true) ~= nil)
        or (line:find("Invalid user", 1, true) ~= nil)
        or (line:find("authentication failure", 1, true) ~= nil)
        or ((line:find("Connection closed by", 1, true) ~= nil) and (line:find("preauth", 1, true) ~= nil))
        or ((line:find("Disconnected from", 1, true) ~= nil) and (line:find("preauth", 1, true) ~= nil))
end

function transform(raw, cfg)
    local platform = (type(raw) == "string") and (raw:match("^(%a+)\n") or "stream") or "stream"
    local iter, _ = lines_from(raw)

    local logs = {}
    local by_ip = {}

    for line in iter do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and looks_like_auth_failure(line) then
            local ts = parse_timestamp(line)
            local emit
            if ts > 0 then
                emit = ts > last_seen_ts
            else
                emit = should_emit_unparsed(line)
            end
            if emit then
                local user, ip, pid = parse_entry(line)

                local message
                if user == "?" and ip == "?" then
                    -- Parsing yielded nothing structured — show the raw
                    -- post-prefix line so the user can still see what sshd
                    -- actually said. Trim a leading "TIMESTAMP host service[pid]: "
                    -- prefix when present.
                    message = line:match(":%s+(.+)$") or line
                else
                    message = string.format("user=%s ip=%s", user, ip)
                end

                table.insert(logs, {
                    timestamp = ts,
                    level = "warn",
                    message = message,
                    source = pid and ("sshd[" .. pid .. "]") or "sshd",
                })
                if ip ~= "?" then
                    by_ip[ip] = (by_ip[ip] or 0) + 1
                end
                if ts > last_seen_ts then last_seen_ts = ts end
            end
        end
    end

    -- Top offenders summary, sorted by count desc.
    local offenders = {}
    for ip, count in pairs(by_ip) do
        table.insert(offenders, { ip = ip, count = count })
    end
    table.sort(offenders, function(a, b) return a.count > b.count end)

    return {
        platform = platform or "unknown",
        last_seen_ts = last_seen_ts,
        new_count = #logs,
        offenders = offenders,
        _logs = logs,
    }
end

-- Build a (day-of-week × hour-of-day) grid of failure counts for the
-- last 7 days. Rows are 1=Sunday..7=Saturday to match Lua's os.date *t
-- wday convention; the hour bin is 0..23 (offset to a 1..24 Lua index
-- when assigning).
--
-- Note: store:latest_logs() returns entries keyed by `t` (unix epoch),
-- not `timestamp` — the StoreAPI binding renamed it for brevity. Using
-- the wrong field silently zeros every entry and the heatmap drops to
-- total=0 and renders nothing.
local function build_failure_heatmap(entries)
    local now = os.time()
    local cutoff = now - 7 * 86400
    local grid = {}
    for d = 1, 7 do
        grid[d] = {}
        for h = 1, 24 do grid[d][h] = 0 end
    end
    local total = 0
    for _, e in ipairs(entries) do
        local ts = e.t or e.timestamp or 0
        if ts >= cutoff then
            local t = os.date("*t", ts)
            if t and t.wday and t.hour then
                grid[t.wday][t.hour + 1] = grid[t.wday][t.hour + 1] + 1
                total = total + 1
            end
        end
    end
    return grid, total
end

function render(ctx, store, cfg)
    local entries = (store.latest_logs and store:latest_logs(500)) or {}

    if store.offenders and #store.offenders > 0 then
        local rows = {}
        for i = 1, math.min(#store.offenders, 10) do
            local o = store.offenders[i]
            table.insert(rows, { o.ip, tostring(o.count) })
        end
        ctx:table({
            title = "Top source IPs (this tick)",
            columns = { "Source IP", "Failures" },
            rows = rows,
        })
        ctx:space(4)
    end

    -- Failure-by-hour heatmap. Skipped when the buffer is empty so a
    -- freshly-deployed agent doesn't render an all-zero grid.
    local grid, total = build_failure_heatmap(entries)
    if total > 0 then
        ctx:heatmap({
            title = "Failed logins by hour (7d)",
            rows = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
            cols = { "00","01","02","03","04","05","06","07","08","09","10","11",
                     "12","13","14","15","16","17","18","19","20","21","22","23" },
            values = grid,
            unit = "failures",
            height = 160,
        })
        ctx:space(4)
    end

    ctx:log_viewer({
        title = string.format("SSH auth failures (%d in buffer)", #entries),
        entries = entries,
        height = 280,
        auto_scroll = true,
        show_source = true,
    })
end
