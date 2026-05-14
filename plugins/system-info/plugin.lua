plugin = {
    id = "system-info",
    name = "System Info",
    description = "Basic system information",
    version = "1.0.1",
    author = "Cleat",
    icon = "i",
    category = "System",
    default_interval = 60,
    min_interval = 30,
    data_type = "snapshot",
}

-- Connection metadata header: a single line with pipe-separated fields,
-- prepended to collect()'s remote-command output so transform() can pick
-- up the connection profile / jump host / auth method without needing
-- ssh access itself (transform/render run without a Host API binding).
local function meta_header(ssh)
    local m = ssh:meta() or {}
    return string.format("%s|%s|%s",
        m.profile_name or "",
        m.jump_host or "",
        m.auth_method or "")
end

function collect(ssh, cfg)
    local header = meta_header(ssh)
    local uname = ssh:exec("uname -a") or ""
    local os_release = ssh:exec("cat /etc/os-release 2>/dev/null") or ""
    local sw_vers = ssh:exec("sw_vers 2>/dev/null") or ""
    local uptime_raw = ssh:exec("cat /proc/uptime 2>/dev/null || uptime") or ""
    return header .. "\n===\n" .. uname .. "\n---\n" .. os_release ..
           "\n---\n" .. sw_vers .. "\n---\n" .. uptime_raw
end

function transform(raw, cfg)
    -- Split off the meta header (everything before the "===" delimiter).
    local meta_line, body = raw:match("^([^\n]*)\n===\n(.*)$")
    if not body then
        -- No header — older plugin output shape; fall back to treating
        -- the whole input as the body so we don't break on a stale tick.
        meta_line = ""
        body = raw
    end
    local profile_name, jump_host, auth_method = meta_line:match("^([^|]*)|([^|]*)|([^|]*)$")
    profile_name = profile_name or ""
    jump_host = jump_host or ""
    auth_method = auth_method or ""

    -- Split body on the literal "\n---\n" delimiter that collect() emits
    -- between sections. The previous `[^%-%-%-]+` pattern was a negated
    -- character class containing just `-` (Lua deduplicates), so it split
    -- on any hyphen — breaking on kernel versions like "6.8.0-..." in
    -- `uname -a` output and shifting downstream sections[N] indices.
    local sections = {}
    local pos = 1
    while true do
        local s, e = body:find("\n---\n", pos, true)
        if not s then
            table.insert(sections, body:sub(pos))
            break
        end
        table.insert(sections, body:sub(pos, s - 1))
        pos = e + 1
    end

    local uname = (sections[1] or ""):match("^%s*(.-)%s*$") or ""
    local os_release_raw = sections[2] or ""
    local sw_vers_raw = sections[3] or ""
    local uptime_raw = sections[4] or ""

    -- Parse OS name
    local os_name = "Unknown"
    local pretty = os_release_raw:match('PRETTY_NAME="([^"]+)"')
    if pretty then
        os_name = pretty
    elseif sw_vers_raw:find("ProductName") then
        local name = sw_vers_raw:match("ProductName:%s*(.+)") or "macOS"
        local ver = sw_vers_raw:match("ProductVersion:%s*(.+)") or ""
        os_name = name .. " " .. ver
    end

    -- Parse kernel
    local kernel = uname:match("^(%S+%s+%S+)") or uname

    -- Parse arch
    local arch = uname:match("(%S+)%s*$") or "unknown"

    -- Parse uptime
    local uptime_seconds = 0
    local up_secs = uptime_raw:match("^%s*(%d+%.?%d*)")
    if up_secs then
        uptime_seconds = math.floor(tonumber(up_secs))
    end

    -- Parse hostname from uname
    local hostname = uname:match("^%S+%s+(%S+)") or "unknown"

    return {
        hostname = hostname,
        os = os_name,
        kernel = kernel,
        arch = arch,
        uptime_seconds = uptime_seconds,
        -- From ssh:meta() — surfaces in the rendered card so users can see
        -- which profile / jump host / auth method this pane is using
        -- without leaving the panel.
        profile_name = profile_name,
        jump_host = (jump_host ~= "") and jump_host or nil,
        auth_method = auth_method,
    }
end

function render(ctx, store, cfg)
    if not store then return end

    -- Format uptime
    local uptime = ""
    local secs = store.uptime_seconds or 0
    if secs > 86400 then
        uptime = string.format("%dd %dh %dm", math.floor(secs / 86400),
            math.floor((secs % 86400) / 3600), math.floor((secs % 3600) / 60))
    elseif secs > 3600 then
        uptime = string.format("%dh %dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
    elseif secs > 0 then
        uptime = string.format("%dm", math.floor(secs / 60))
    end

    ctx:section({
        title = "System Information",
        children = function(ctx)
            if store.profile_name and store.profile_name ~= "" then
                ctx:text("Profile: " .. store.profile_name)
            end
            ctx:text("Hostname: " .. (store.hostname or "unknown"))
            ctx:text("OS: " .. (store.os or "unknown"))
            ctx:text("Kernel: " .. (store.kernel or "unknown"))
            ctx:text("Architecture: " .. (store.arch or "unknown"))
            if uptime ~= "" then
                ctx:text("Uptime: " .. uptime)
            end
            if store.jump_host then
                ctx:text("Jump host: " .. store.jump_host)
            end
            if store.auth_method and store.auth_method ~= "" then
                ctx:text("Auth: " .. store.auth_method)
            end
        end,
    })
end
