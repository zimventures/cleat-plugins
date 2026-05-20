-- Pipes — growing box-drawing pipe network. Multiple pipes grow from random
-- starting points, turning at right angles. When the screen fills up past a
-- threshold the whole thing resets. Loosely modelled on the BSD pipes(6)
-- screensaver — gentle, hypnotic.

screensaver = {
    id = "pipes",
    name = "Pipes",
    description = "Growing pipe network in box-drawing characters.",
    author = "Cleat",
    version = "1.0.0",
    fps = 15,
}

-- Direction enum. 1=up, 2=right, 3=down, 4=left.
local DIR_UP, DIR_RIGHT, DIR_DOWN, DIR_LEFT = 1, 2, 3, 4
local DRS = { 0, 0, 0, 0 } -- dr by dir index
local DCS = { 0, 0, 0, 0 } -- dc by dir index
-- (Initialized below — Lua doesn't allow table-key initializer expressions
-- inline cleanly, and explicit assignments read more obviously.)
DRS[DIR_UP] = -1; DCS[DIR_UP] = 0
DRS[DIR_RIGHT] = 0; DCS[DIR_RIGHT] = 1
DRS[DIR_DOWN] = 1; DCS[DIR_DOWN] = 0
DRS[DIR_LEFT] = 0; DCS[DIR_LEFT] = -1

-- Pipe segment glyphs for (incoming dir -> outgoing dir). Indexed by
-- (prev_dir, dir). Picked from U+2500-U+257F (light box-drawing).
--   ─ ━ │ ┃ ┌ ┐ └ ┘ etc.
local GLYPHS = {}
local function set_glyph(prev, dir, ch)
    GLYPHS[prev * 10 + dir] = ch
end
-- Straight segments.
set_glyph(DIR_RIGHT, DIR_RIGHT, "─")
set_glyph(DIR_LEFT,  DIR_LEFT,  "─")
set_glyph(DIR_UP,    DIR_UP,    "│")
set_glyph(DIR_DOWN,  DIR_DOWN,  "│")
-- Corners. Reading: came in going `prev`, now going `dir`. The glyph is the
-- bend that connects the previous cell's exit to this cell's exit.
set_glyph(DIR_RIGHT, DIR_DOWN,  "┐")
set_glyph(DIR_RIGHT, DIR_UP,    "┘")
set_glyph(DIR_LEFT,  DIR_DOWN,  "┌")
set_glyph(DIR_LEFT,  DIR_UP,    "└")
set_glyph(DIR_UP,    DIR_RIGHT, "┌")
set_glyph(DIR_UP,    DIR_LEFT,  "┐")
set_glyph(DIR_DOWN,  DIR_RIGHT, "└")
set_glyph(DIR_DOWN,  DIR_LEFT,  "┘")

local pipes = {}
local cells_drawn = 0
local last_rows = 0
local last_cols = 0

local PALETTE = {
    "#e2a04a", "#7bc96f", "#56b6c2", "#c678dd", "#e06c75",
    "#abb2bf", "#d19a66", "#61afef", "#98c379", "#be5046",
}

local function rand_color()
    return PALETTE[math.random(1, #PALETTE)]
end

local function spawn_pipe(rows, cols)
    -- Resize can briefly hand us a tiny grid; clamp the spawn box so
    -- math.random(lo, hi) never sees hi < lo (Lua errors on that).
    local row_hi = math.max(2, rows - 1)
    local col_hi = math.max(2, cols - 1)
    local p = {
        row = math.random(math.min(2, row_hi), row_hi),
        col = math.random(math.min(2, col_hi), col_hi),
        dir = math.random(1, 4),
        prev_dir = nil,
        color = rand_color(),
        alive = true,
    }
    p.prev_dir = p.dir
    return p
end

local function reset(term, rows, cols)
    pipes = {}
    cells_drawn = 0
    term:clear({ bg = "#000000" })
    -- Bail on absurdly small grids — nothing to draw and spawn_pipe's range
    -- guards would just emit a degenerate pipe at (1,1).
    if rows < 2 or cols < 2 then
        return
    end
    for i = 1, 4 do
        table.insert(pipes, spawn_pipe(rows, cols))
    end
end

function init(term, cfg)
    math.randomseed(os.time())
    last_rows = term:rows()
    last_cols = term:cols()
    reset(term, last_rows, last_cols)
end

function frame(term, dt, cfg)
    local rows = term:rows()
    local cols = term:cols()
    if rows ~= last_rows or cols ~= last_cols then
        last_rows, last_cols = rows, cols
        reset(term, rows, cols)
    end

    -- When the screen is more than 60% pipes, fade out and restart. Without
    -- the reset the wall-of-pipes plateau gets visually static.
    if cells_drawn > rows * cols * 0.6 then
        reset(term, rows, cols)
        return
    end

    -- Steps per frame scales with dt; one step = one cell extension.
    local steps = math.max(1, math.floor(dt * 30))
    for s = 1, steps do
        for _, p in ipairs(pipes) do
            if p.alive then
                -- Small chance to turn at each cell — keeps pipes from
                -- looking like straight lines.
                if math.random() < 0.15 then
                    -- Turn 90° in a random direction (never reverse).
                    if math.random() < 0.5 then
                        p.dir = (p.dir % 4) + 1
                    else
                        p.dir = ((p.dir + 2) % 4) + 1
                    end
                end

                local glyph = GLYPHS[p.prev_dir * 10 + p.dir] or "·"
                term:set(p.row, p.col, glyph, { fg = p.color })
                cells_drawn = cells_drawn + 1

                p.prev_dir = p.dir
                p.row = p.row + DRS[p.dir]
                p.col = p.col + DCS[p.dir]
                -- Bounce off edges by reversing direction (with a turn).
                if p.row < 1 or p.row > rows or p.col < 1 or p.col > cols then
                    p.alive = false
                end
            end
        end
        -- Respawn dead pipes so the screen keeps growing.
        for i, p in ipairs(pipes) do
            if not p.alive then
                pipes[i] = spawn_pipe(rows, cols)
            end
        end
    end
end
