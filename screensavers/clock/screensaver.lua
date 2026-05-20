-- Clock — large ASCII art clock displaying the current time, centered. The
-- digits are stamped from a built-in 5x4 cell font; no asset files needed.
-- Practical and minimal.

screensaver = {
    id = "clock",
    name = "Clock",
    description = "Big ASCII clock — useful as well as ambient.",
    author = "Cleat",
    version = "1.0.0",
    fps = 4,    -- the display only changes once a second; 4 fps is plenty
}

-- 5-row glyphs for digits 0-9 plus colon. Each glyph is 4 columns wide; cells
-- containing "#" get painted, anything else stays as background.
local GLYPHS = {
    ["0"] = { "####", "#  #", "#  #", "#  #", "####" },
    ["1"] = { " ## ", "  # ", "  # ", "  # ", " ###" },
    ["2"] = { "### ", "   #", " ## ", "#   ", "####" },
    ["3"] = { "### ", "   #", " ## ", "   #", "### " },
    ["4"] = { "#  #", "#  #", "####", "   #", "   #" },
    ["5"] = { "####", "#   ", "### ", "   #", "### " },
    ["6"] = { " ###", "#   ", "### ", "#  #", " ## " },
    ["7"] = { "####", "   #", "  # ", " #  ", " #  " },
    ["8"] = { " ## ", "#  #", " ## ", "#  #", " ## " },
    ["9"] = { " ## ", "#  #", " ###", "   #", "### " },
    [":"] = { "    ", "  # ", "    ", "  # ", "    " },
}

local GLYPH_H = 5
local GLYPH_W = 4
local GLYPH_GAP = 1

local function draw_string(term, top_row, left_col, text, color)
    local style = { fg = color, bold = true }
    local col = left_col
    for i = 1, #text do
        local ch = text:sub(i, i)
        local g = GLYPHS[ch]
        if g then
            for r = 1, GLYPH_H do
                local row = g[r]
                for c = 1, GLYPH_W do
                    if row:sub(c, c) == "#" then
                        term:set(top_row + r - 1, col + c - 1, "█", style)
                    end
                end
            end
            col = col + GLYPH_W + GLYPH_GAP
        end
    end
end

local function time_string()
    -- os.date is exposed by LuaSandbox's curated os subset (no leak path).
    return os.date("%H:%M:%S")
end

local function date_string()
    return os.date("%A, %B %d")
end

function init(term, cfg)
    -- Nothing to seed — every frame is recomputed from os.date.
end

function frame(term, dt, cfg)
    local rows = term:rows()
    local cols = term:cols()
    local accent = term:theme_color("accent") or "#e2a04a"
    local text   = term:theme_color("text_dim") or "#a0a0a0"

    term:clear({ bg = "#0d1117" })

    local t = time_string()
    local d = date_string()

    -- Width of the time string: each glyph is GLYPH_W cols + GLYPH_GAP. Last
    -- glyph has no trailing gap, so subtract one gap.
    local time_w = #t * (GLYPH_W + GLYPH_GAP) - GLYPH_GAP
    -- Lua coords are 1-based; add +1 to the centered offset so a row count
    -- exactly equal to GLYPH_H still renders the big clock (top == 1) instead
    -- of falling through to the plain-text fallback.
    local top    = math.floor((rows - GLYPH_H) / 2) + 1
    local left   = math.floor((cols - time_w) / 2) + 1

    if top < 1 or left < 1 or top + GLYPH_H - 1 > rows or left + time_w - 1 > cols then
        -- Window too small to fit the big clock — fall back to a plain
        -- centered string so the screensaver isn't silent.
        local center_row = math.floor(rows / 2)
        local center_col = math.floor((cols - #t) / 2) + 1
        term:print(center_row, center_col, t, { fg = accent, bold = true })
        return
    end

    draw_string(term, top, left, t, accent)

    -- Date below, centred. Use term:print for a one-cell-per-char render.
    local date_top = top + GLYPH_H + 2
    local date_col = math.floor((cols - #d) / 2) + 1
    if date_top <= rows then
        term:print(date_top, date_col, d, { fg = text })
    end
end
