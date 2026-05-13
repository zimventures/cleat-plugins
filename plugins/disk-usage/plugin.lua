plugin = {
    id = "disk-usage",
    name = "Disk Usage",
    description = "All mount points: % used bar chart + size/used/avail/fs table",
    version = "1.0.0",
    author = "Cleat",
    icon = "",
    category = "System",
    default_interval = 60,
    min_interval = 15,
    data_type = "table",
    settings = {
        { key = "warn_pct", label = "Warning Threshold (%)",  type = "number", default = "80" },
        { key = "crit_pct", label = "Critical Threshold (%)", type = "number", default = "90" },
        { key = "skip_special", label = "Skip tmpfs/devtmpfs/squashfs", type = "boolean", default = "true" },
    },
}

function collect(ssh, cfg)
    -- df -P gives POSIX-portable output: 1024-byte blocks, single-line per filesystem.
    -- -T adds the fs type column (Linux only — macOS df doesn't support -T, fall through).
    local linux = ssh:exec("df -PT 2>/dev/null") or ""
    if linux ~= "" and linux:match("Type") then
        return "linux\n" .. linux
    end
    -- Fallback (no Type column).
    local generic = ssh:exec("df -P 2>/dev/null") or ""
    return "generic\n" .. generic
end

local function should_skip(fstype, skip_special)
    if not skip_special then return false end
    -- Pseudo / overlay / read-only image filesystems.
    return fstype == "tmpfs" or fstype == "devtmpfs" or fstype == "squashfs"
        or fstype == "proc" or fstype == "sysfs" or fstype == "cgroup" or fstype == "cgroup2"
        or fstype == "overlay" or fstype == "fuse.snapfuse"
end

local function human_size_kb(kb)
    -- Input is 1024-byte blocks (POSIX df default), so kb is itself KiB.
    -- Threshold/divisors stack 1024 at each step:
    --   1 TiB = 1024 GiB = 1024 * 1024 MiB = 1024 * 1024 * 1024 KiB
    if kb >= 1073741824 then return string.format("%.1f T", kb / 1073741824) end
    if kb >= 1048576    then return string.format("%.1f G", kb / 1048576)    end
    if kb >= 1024       then return string.format("%.1f M", kb / 1024)       end
    return string.format("%d K", kb)
end

function transform(raw, cfg)
    local platform, body = raw:match("^(%a+)\n(.*)$")
    body = body or ""

    local skip_special = (cfg and cfg.skip_special)
    if skip_special == "false" or skip_special == false then skip_special = false else skip_special = true end

    local rows = {}      -- table rows for ctx:table()
    local bars = {}      -- bars for ctx:bar_chart()

    -- Skip header line. Each subsequent line is one filesystem.
    local first = true
    for line in body:gmatch("([^\n]+)") do
        if first then
            first = false
        else
            local fields = {}
            for f in line:gmatch("%S+") do table.insert(fields, f) end

            local fs, fstype, total_kb, used_kb, avail_kb, pct, mount
            -- gsub returns (string, count); a bare tonumber(string:gsub(...))
            -- forwards the count as a `base` argument and crashes if it's
            -- outside [2,36]. The extra parens around the gsub call drop
            -- the count, leaving just the cleaned string.
            if platform == "linux" and #fields >= 7 then
                fs       = fields[1]
                fstype   = fields[2]
                total_kb = tonumber(fields[3]) or 0
                used_kb  = tonumber(fields[4]) or 0
                avail_kb = tonumber(fields[5]) or 0
                pct      = tonumber(((fields[6] or ""):gsub("%%", ""))) or 0
                mount    = fields[7]
            elseif #fields >= 6 then
                fs       = fields[1]
                fstype   = "?"
                total_kb = tonumber(fields[2]) or 0
                used_kb  = tonumber(fields[3]) or 0
                avail_kb = tonumber(fields[4]) or 0
                pct      = tonumber(((fields[5] or ""):gsub("%%", ""))) or 0
                mount    = fields[6]
            end

            if mount and not should_skip(fstype, skip_special) then
                table.insert(rows, {
                    mount,
                    fstype or "?",
                    human_size_kb(total_kb),
                    human_size_kb(used_kb),
                    human_size_kb(avail_kb),
                    string.format("%d%%", pct),
                })
                table.insert(bars, { label = mount, value = pct, unit = "%" })
            end
        end
    end

    -- Sort bars by usage desc so the worst offenders are easy to spot.
    table.sort(bars, function(a, b) return a.value > b.value end)

    return {
        platform = platform,
        rows = rows,
        bars = bars,
        warn_pct = tonumber(cfg and cfg.warn_pct) or 80,
        crit_pct = tonumber(cfg and cfg.crit_pct) or 90,
    }
end

function render(ctx, store, cfg)
    if not store or not store.bars or #store.bars == 0 then
        ctx:text("No filesystem data.")
        return
    end

    ctx:bar_chart({
        title = "Mount usage (%)",
        bars = store.bars,
        y_min = 0,
        y_max = 100,
        warn = store.warn_pct or 80,
        crit = store.crit_pct or 90,
        height = 160,
    })

    ctx:space(6)

    ctx:table({
        title = "Filesystems",
        columns = { "Mount", "Type", "Size", "Used", "Avail", "Use%" },
        rows = store.rows or {},
    })
end
