plugin = {
    id = "error-log-monitor",
    name = "Error Log Monitor",
    description = "Tails system logs for ERROR/CRITICAL severity entries",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Logs",
    default_interval = 30,
    min_interval = 5,
    data_type = "log",
    retention = "1000",
    -- Plugin can run in either polling (default) or streaming mode.
    streaming = true,
    streaming_idle_seconds = 60,
    settings = {
        { key = "mode", label = "Collection mode", type = "string", default = "polling",
          values = { "polling", "stream" } },
        { key = "since", label = "Lookback window (polling only)", type = "string", default = "5m" },
    },
}

-- Module state — keeps the last seen cursor across collect() calls within a
-- single plugin process so we don't re-emit duplicates. The plugin engine
-- preserves the Lua VM between ticks.
local last_seen_ts = 0

local function shell_escape(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function collect(ssh, cfg)
    local mode = (cfg and cfg.mode) or "polling"
    if mode == "stream" then
        -- Engine handles the persistent channel. journalctl with -f tails
        -- the journal forever, scoped to err-priority and above.
        --
        -- journalctl block-buffers when its stdout is a pipe (cleat reads
        -- via libssh2 channel — not a tty). `stdbuf -oL` forces it
        -- back to line buffering so entries reach us as soon as they're
        -- emitted rather than waiting for an internal buffer to fill.
        return "stdbuf -oL journalctl -f -p err -o short-iso --no-pager"
    end

    local since = (cfg and cfg.since) or "5m"

    -- journalctl path (modern Linux): JSON output is easiest to parse.
    -- Filter by priority <= 3 (err/crit/alert/emerg).
    local linux = ssh:exec(
        "journalctl --since=" .. shell_escape(since) ..
        " -p err -o short-iso --no-pager 2>/dev/null"
    ) or ""

    if linux ~= "" then
        return "linux\n" .. linux
    end

    -- Fallback for systems without journalctl: tail syslog/messages.
    local syslog = ssh:exec(
        "tail -n 200 /var/log/syslog /var/log/messages 2>/dev/null | " ..
        "grep -iE 'error|critical|emerg|alert' || true"
    ) or ""

    if syslog ~= "" then
        return "syslog\n" .. syslog
    end

    -- macOS path.
    local mac = ssh:exec(
        "log show --last " .. shell_escape(since) ..
        " --style syslog --predicate 'eventMessage CONTAINS \"error\" OR eventMessage CONTAINS \"fault\"' 2>/dev/null"
    ) or ""

    return "mac\n" .. mac
end

local function classify_level(line)
    local lower = line:lower()
    if lower:find("crit") or lower:find("emerg") or lower:find("alert") or lower:find("fatal") then
        return "crit"
    elseif lower:find("error") or lower:find("err ") then
        return "error"
    elseif lower:find("warn") then
        return "warn"
    end
    return "info"
end

local kMonths = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

-- Best-effort parse of common log timestamp shapes. Returns unix epoch or 0.
local function parse_timestamp(s)
    -- ISO 8601: "2026-04-30T12:34:56" or "2026-04-30 12:34:56"
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
        -- Month rollover: if the parsed month is later than the current,
        -- the line is from late last year (e.g. Dec entry seen in Jan).
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

-- Bounded set of recently-emitted line hashes. Used as a backup dedup
-- mechanism for entries whose timestamp couldn't be parsed (ts==0):
-- without it, every tick would re-emit the same lines from
-- `--since=Xm`. Bounded to avoid unbounded memory growth on busy hosts.
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

-- Iterator over input lines that handles either tick mode:
--   - Polling: raw is a string with a "<platform>\n<body>" prefix.
--   - Streaming: raw is a Lua table of lines from the engine.
local function lines_from(raw)
    if type(raw) == "table" then
        local i = 0
        return function()
            i = i + 1
            return raw[i]
        end
    end
    local _, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""
    return body:gmatch("([^\n]+)")
end

function transform(raw, cfg)
    local platform = (type(raw) == "string") and (raw:match("^(%a+)\n") or "stream") or "stream"
    local iter = lines_from(raw)

    local logs = {}
    for line in iter do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and #line < 4096 then
            local ts = parse_timestamp(line)
            -- Try to split off a "host service[pid]:" prefix as the source.
            local source, message = line:match("^%S+%s+%S+%s+(%S+):%s+(.+)$")
            if not source then
                message = line
                source = ""
            end

            -- Skip entries we've already emitted. For parseable timestamps
            -- the `last_seen_ts` cursor is exact; for unparseable lines
            -- (ts==0) we fall back to a bounded set of line hashes so the
            -- same syslog lines aren't re-emitted on every tick.
            local emit
            if ts > 0 then
                emit = ts > last_seen_ts
            else
                emit = should_emit_unparsed(line)
            end
            if emit then
                table.insert(logs, {
                    timestamp = ts,
                    level = classify_level(line),
                    message = message,
                    source = source,
                })
                if ts > last_seen_ts then last_seen_ts = ts end
            end
        end
    end

    return {
        platform = platform or "unknown",
        last_seen_ts = last_seen_ts,
        new_count = #logs,
        _logs = logs,
    }
end

function render(ctx, store, cfg)
    local entries = (store.latest_logs and store:latest_logs(500)) or {}
    ctx:log_viewer({
        title = string.format("Recent errors (%d in buffer)", #entries),
        entries = entries,
        height = 320,
        auto_scroll = true,
        show_source = true,
    })
end
