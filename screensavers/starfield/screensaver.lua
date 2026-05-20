-- Starfield — flying through space. Stars at different "depths" parallax
-- past the camera, with closer stars moving faster and rendering brighter.
-- Lua port of the Phase A C++ animator (now retired to a hard fallback).

screensaver = {
    id = "starfield",
    name = "Starfield",
    description = "Parallax star field flying through deep space.",
    author = "Cleat",
    version = "1.0.0",
    fps = 30,
}

local stars = {}
local last_rows = 0
local last_cols = 0

local function seed_star(s, cols, rows)
    s.x = math.random() * cols
    s.y = math.random() * rows
    -- Depth in [1.0, 3.0). Closer stars zoom by + draw bright.
    s.depth = 1.0 + math.random() * 2.0
end

local function rebuild(rows, cols)
    last_rows = rows
    last_cols = cols
    local area = rows * cols
    local count = math.max(20, math.floor(area * 0.10))
    stars = {}
    for i = 1, count do
        local s = {}
        seed_star(s, cols, rows)
        table.insert(stars, s)
    end
end

function init(term, cfg)
    math.randomseed(os.time())
    rebuild(term:rows(), term:cols())
end

function frame(term, dt, cfg)
    local rows = term:rows()
    local cols = term:cols()
    if rows ~= last_rows or cols ~= last_cols then
        rebuild(rows, cols)
    end

    term:clear({ bg = "#000000" })

    local base_speed = 8.0 -- cells/sec at depth 1.0
    for _, s in ipairs(stars) do
        s.x = s.x + dt * base_speed * s.depth
        if s.x >= cols + 1 then
            s.x = 0
            s.y = math.random() * rows
            s.depth = 1.0 + math.random() * 2.0
        end
    end

    for _, s in ipairs(stars) do
        local row = math.floor(s.y) + 1
        local col = math.floor(s.x) + 1
        if s.depth < 1.5 then
            term:set(row, col, ".", { fg = "#606060", dim = true })
        elseif s.depth < 2.2 then
            term:set(row, col, "*", { fg = "#B0B0B0" })
        else
            term:set(row, col, "+", { fg = "#FFFFFF", bold = true })
        end
    end
end
