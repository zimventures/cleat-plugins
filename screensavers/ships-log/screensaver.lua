-- Ship's Log — a vintage terminal aesthetic. Types out fictional nautical log
-- entries with a typewriter rhythm. The personality piece — entries blend
-- real nautical language with subtle sysadmin metaphors. Loaded from
-- entries.txt via load_asset.

screensaver = {
    id = "ships-log",
    name = "Ship's Log",
    description = "Vintage typewriter logs from HMS Cleat, with a sysadmin streak.",
    author = "Cleat",
    version = "1.0.0",
    fps = 20,
}

-- Entries pool — loaded once from entries.txt at init time. Each entry is a
-- multi-line paragraph; blank lines separate entries; `#` lines are skipped.
local entries = {}
local current_entry = nil
local current_text = ""
local current_pos = 0    -- characters revealed so far
local pause_until = 0    -- seconds remaining of the inter-entry pause
local time_acc = 0
local typing_speed = 28  -- chars/sec; varied by punctuation pauses

-- Walk the asset text one line at a time. Lua's gmatch("[^\n]*") returns an
-- empty string at every newline (and once at end-of-input), which would
-- treat *every* line break as a paragraph boundary instead of just blank
-- lines. Hand-rolled scan over the string avoids that footgun.
local function each_line(s)
    local i = 1
    local n = #s
    return function()
        if i > n then return nil end
        local j = s:find("\n", i, true)
        local line
        if j then
            line = s:sub(i, j - 1)
            i = j + 1
        else
            line = s:sub(i, n)
            i = n + 1
        end
        return line
    end
end

local function load_entries()
    local raw = load_asset("entries.txt")
    if not raw then return {} end
    local pool = {}
    local buf = {}
    for line in each_line(raw) do
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        if trimmed:sub(1, 1) == "#" then
            -- comment line; ignore
        elseif trimmed == "" then
            if #buf > 0 then
                table.insert(pool, table.concat(buf, "\n"))
                buf = {}
            end
        else
            table.insert(buf, trimmed)
        end
    end
    if #buf > 0 then
        table.insert(pool, table.concat(buf, "\n"))
    end
    return pool
end

local function pick_entry()
    if #entries == 0 then
        current_entry = "(no log entries loaded)"
    else
        current_entry = entries[math.random(1, #entries)]
    end
    current_text = current_entry
    current_pos = 0
end

function init(term, cfg)
    math.randomseed(os.time())
    entries = load_entries()
    pause_until = 0
    time_acc = 0
    pick_entry()
end

local function draw_frame(term, rows, cols, text_color)
    -- A thin double-line frame around the visible log area gives the
    -- vintage-terminal feel without being precious about it.
    term:box(2, 2, rows - 1, cols - 1, { fg = text_color, style = "double" })
    term:print(2, math.floor(cols / 2) - 9, " HMS Cleat — Log ", { fg = text_color })
end

function frame(term, dt, cfg)
    local rows = term:rows()
    local cols = term:cols()

    -- Theme-driven colors with sensible amber fallbacks for monochrome themes.
    local bg = "#0a0a0a"
    local text = term:theme_color("accent") or "#e2a04a"

    term:clear({ bg = bg })
    draw_frame(term, rows, cols, text)

    if pause_until > 0 then
        pause_until = pause_until - dt
        if pause_until <= 0 then
            pick_entry()
        end
    else
        time_acc = time_acc + dt
        local target = math.floor(time_acc * typing_speed)
        if target > #current_text then
            target = #current_text
        end
        current_pos = target
    end

    -- Inside-frame writable area: rows 4..rows-2, cols 4..cols-3.
    local top = 4
    local left = 4
    local right = cols - 3
    local inner_w = right - left + 1

    -- Render the revealed prefix. Honour explicit \n + soft-wrap at the
    -- inner width so long sentences don't run off the right side.
    local r = top
    local c = left
    local i = 1
    while i <= current_pos do
        local ch = current_text:sub(i, i)
        if ch == "\n" then
            r = r + 1
            c = left
        else
            term:set(r, c, ch, { fg = text })
            c = c + 1
            if c > right then
                r = r + 1
                c = left
            end
        end
        if r > rows - 2 then break end
        i = i + 1
    end

    -- Blinking cursor at the current write position so the audience knows
    -- the entry is "live" even between keystrokes. Toggle once per ~half-
    -- second by quantizing time_acc.
    if pause_until <= 0 and r <= rows - 2 then
        local blink = math.floor(time_acc * 2) % 2 == 0
        if blink then
            term:set(r, c, "_", { fg = text, bold = true })
        end
    end

    -- When fully typed, hold the entry for a beat before swapping to the next.
    if pause_until <= 0 and current_pos >= #current_text then
        pause_until = 3.0 + math.random() * 2.0
        time_acc = 0
    end
end
