plugin = {
    id = "statusbar-disk",
    name = "Disk",
    description = "Root filesystem in the status bar; all mountpoints in the panel",
    version = "1.1.0",
    author = "Cleat",
    icon = "",
    category = "Status Bar",
    default_interval = 60,
    min_interval = 30,
    data_type = "snapshot",
    statusbar = true,
    statusbar_order = 30,
    settings = {
        { key = "warn_pct", label = "Warning Threshold (%)",  type = "number",  default = "80" },
        { key = "crit_pct", label = "Critical Threshold (%)", type = "number",  default = "95" },
        { key = "skip_special", label = "Hide tmpfs / overlay / squashfs", type = "boolean", default = "true" },
    },
    -- Opt into the notifications capability so cleat:notify() works from
    -- collect/transform. The user can revoke per-plugin in the Plugin
    -- Manager — we still get bound to a no-op then, no runtime error.
    permissions = { "notifications" },
}

-- Track per-mountpoint "we already notified" state at module scope so we
-- emit one toast per threshold crossing rather than one per tick. Cleared
-- when the mount drops back below crit so a future re-cross fires again.
local notified_crit = {}

-- Collect the root mount for the status bar and ALL mounts for the panel
-- in a single round-trip. Format: "ROOT\n<root df line>\nALL\n<full df>"
function collect(ssh, cfg)
    local root = ssh:exec("df -P / 2>/dev/null | tail -1") or ""
    -- df -PT (Linux) adds the fs type column; macOS df rejects -T so fall through.
    local all_typed = ssh:exec("df -PT 2>/dev/null") or ""
    local all = (all_typed ~= "" and all_typed) or (ssh:exec("df -P 2>/dev/null") or "")
    local platform = (all_typed ~= "") and "linux" or "generic"
    return platform .. "\nROOT\n" .. root .. "\nALL\n" .. all
end

local function pct_of(field)
    -- gsub returns (string, count); the bare tonumber(s:gsub(...)) call
    -- forwards the count as a base argument and crashes when it's outside
    -- [2,36]. Extra parens drop the count, leaving just the cleaned string.
    return tonumber(((field or ""):gsub("%%", ""))) or 0
end

local function should_skip(fstype, skip_special)
    if not skip_special then return false end
    return fstype == "tmpfs" or fstype == "devtmpfs" or fstype == "squashfs"
        or fstype == "proc" or fstype == "sysfs" or fstype == "cgroup" or fstype == "cgroup2"
        or fstype == "overlay" or fstype == "fuse.snapfuse"
end

local function human_size_kb(kb)
    -- Input is 1024-byte blocks (POSIX df). Stack 1024 at each step:
    --   1 TiB = 1024 GiB = 1024 * 1024 MiB = 1024 * 1024 * 1024 KiB
    if kb >= 1073741824 then return string.format("%.1f T", kb / 1073741824) end
    if kb >= 1048576    then return string.format("%.1f G", kb / 1048576)    end
    if kb >= 1024       then return string.format("%.1f M", kb / 1024)       end
    return string.format("%d K", kb)
end

function transform(raw, cfg)
    local platform = raw:match("^(%a+)\n") or "generic"
    local root_section = raw:match("ROOT\n([^\n]*)") or ""
    local all_section = raw:match("ALL\n(.+)$") or ""

    local skip_special = cfg and cfg.skip_special
    if skip_special == "false" or skip_special == false then skip_special = false else skip_special = true end

    -- Parse the root df line for the status bar. df -P columns:
    --   filesystem  blocks  used  avail  capacity  mountpoint
    local root_pct, root_size, root_used, root_avail = 0, "", "", ""
    local rfields = {}
    for f in root_section:gmatch("%S+") do table.insert(rfields, f) end
    if #rfields >= 6 then
        root_size  = human_size_kb(tonumber(rfields[2]) or 0)
        root_used  = human_size_kb(tonumber(rfields[3]) or 0)
        root_avail = human_size_kb(tonumber(rfields[4]) or 0)
        root_pct   = pct_of(rfields[5])
    end

    -- Parse the full mount list for the panel.
    local rows = {}
    local bars = {}
    local first = true
    for line in all_section:gmatch("([^\n]+)") do
        if first then
            first = false
        else
            local fields = {}
            for f in line:gmatch("%S+") do table.insert(fields, f) end

            local fs, fstype, total_kb, used_kb, avail_kb, pct, mount
            if platform == "linux" and #fields >= 7 then
                fs       = fields[1]
                fstype   = fields[2]
                total_kb = tonumber(fields[3]) or 0
                used_kb  = tonumber(fields[4]) or 0
                avail_kb = tonumber(fields[5]) or 0
                pct      = pct_of(fields[6])
                mount    = fields[7]
            elseif #fields >= 6 then
                fs       = fields[1]
                fstype   = "?"
                total_kb = tonumber(fields[2]) or 0
                used_kb  = tonumber(fields[3]) or 0
                avail_kb = tonumber(fields[4]) or 0
                pct      = pct_of(fields[5])
                mount    = fields[6]
            end

            if mount and not should_skip(fstype, skip_special) then
                table.insert(rows, {
                    mount, fstype or "?",
                    human_size_kb(total_kb), human_size_kb(used_kb),
                    human_size_kb(avail_kb), string.format("%d%%", pct),
                })
                table.insert(bars, { label = mount, value = pct, unit = "%" })
            end
        end
    end

    -- Worst offenders first.
    table.sort(bars, function(a, b) return a.value > b.value end)

    -- Threshold-crossing notifications. Fire once per mount when it
    -- crosses crit_pct upward; clear the marker when it drops below so
    -- a future re-cross can fire again. Skips when cleat.kv / cleat:notify
    -- aren't bound (older binaries running this plugin file).
    local crit_pct = tonumber(cfg and cfg.crit_pct) or 95
    if cleat and cleat.notify then
        for _, b in ipairs(bars) do
            local mount = b.label or "?"
            local pct = b.value or 0
            if pct >= crit_pct and not notified_crit[mount] then
                cleat:notify({
                    title    = "Disk almost full",
                    body     = string.format("%s at %.0f%% (warn %d%%, crit %d%%)",
                                             mount, pct, tonumber(cfg and cfg.warn_pct) or 80, crit_pct),
                    level    = "error",
                    ttl_ms   = 0,           -- sticky — user should acknowledge
                    on_click = "open_view", -- open this plugin's panel for context
                })
                notified_crit[mount] = true
            elseif pct < crit_pct - 2 and notified_crit[mount] then
                -- Tiny hysteresis so a value bouncing right at the
                -- threshold doesn't fire a fresh toast on every tick.
                notified_crit[mount] = nil
            end
        end
    end

    return {
        percent = root_pct,
        size    = root_size,
        used    = root_used,
        avail   = root_avail,
        rows    = rows,
        bars    = bars,
        warn_pct = tonumber(cfg and cfg.warn_pct) or 80,
        crit_pct = crit_pct,
    }
end

function render_statusbar(ctx, store, cfg)
    if not store or not store.percent then return nil end

    local pct = store.percent
    local color = ctx:threshold_color(pct, store.warn_pct or 80, store.crit_pct or 95)

    return {
        label = "Disk",
        value = pct .. "%",
        color = color,
        tooltip = string.format("Root: %s used / %s total (%s free)",
                                store.used or "?", store.size or "?", store.avail or "?"),
        icon = "",
    }
end

function render(ctx, store, cfg)
    if not store or not store.bars or #store.bars == 0 then
        ctx:text("No filesystem data.")
        return
    end

    ctx:bar_chart({
        title = "All mounts (% used)",
        bars = store.bars,
        y_min = 0,
        y_max = 100,
        warn = store.warn_pct or 80,
        crit = store.crit_pct or 95,
        height = 160,
    })

    ctx:space(6)

    ctx:table({
        title = "Filesystems",
        columns = { "Mount", "Type", "Size", "Used", "Avail", "Use%" },
        rows = store.rows or {},
    })
end
