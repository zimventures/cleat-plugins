-- Matrix Rain — falling character columns with a bright head and fading tail.
-- Classic and beloved. Each column has its own length, speed, and reset
-- cadence so the rain looks organic rather than mechanical.

screensaver = {
    id = "matrix-rain",
    name = "Matrix Rain",
    description = "Falling green characters with bright heads and fading tails.",
    author = "Cleat",
    version = "1.0.0",
    fps = 20,
}

-- Per-column state. `head_row` is fractional so speed is time-based.
local columns = {}
local last_rows = 0
local last_cols = 0

-- Print-safe characters — staying out of the control / weird Unicode range
-- keeps the cell shapes uniform regardless of host font.
local CHARSET =
    "01ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()_+-=[]{}<>?:;~"

local function rand_char()
    local i = math.random(1, #CHARSET)
    return CHARSET:sub(i, i)
end

local function reset_column(c, rows)
    -- Window resize can briefly hand us 1-row terminals; clamp every range
    -- below so math.random(lo, hi) never sees hi < lo (which throws in Lua).
    local headOffsetMax = math.max(1, math.floor(rows * 0.5))
    local lengthHi = math.max(4, math.floor(rows * 0.6))
    c.head_row = -math.random(1, headOffsetMax)
    c.speed = 8.0 + math.random() * 14.0 -- rows/sec
    c.length = math.random(4, lengthHi)
    -- Pre-pick the column's character so it doesn't shimmer every frame —
    -- shimmer is reserved for the head, which gets a fresh char as it moves.
    c.chars = {}
    for i = 1, c.length do
        c.chars[i] = rand_char()
    end
    c.head_char = rand_char()
end

local function rebuild(rows, cols)
    last_rows = rows
    last_cols = cols
    columns = {}
    for col = 1, cols do
        local c = {}
        reset_column(c, rows)
        table.insert(columns, c)
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

    local head = "#FFFFFF"
    local bright = "#A0FFA0"
    local mid = "#00FF00"
    local dim = "#005500"

    for col_idx, c in ipairs(columns) do
        c.head_row = c.head_row + dt * c.speed
        -- Once the entire tail has scrolled past the bottom, reset.
        if math.floor(c.head_row) - c.length > rows then
            reset_column(c, rows)
            -- Occasionally pick a fresh head char even mid-flight so the
            -- leading glyph shimmers — pure aesthetics.
        end
        if math.random() < 0.2 then
            c.head_char = rand_char()
        end

        local head_int = math.floor(c.head_row)
        -- Draw head + tail. Tail fades from bright -> mid -> dim across the
        -- column's length. Cells outside the grid are no-ops at the API level.
        for i = 0, c.length - 1 do
            local row = head_int - i + 1 -- +1 because Lua coords are 1-based
            if row >= 1 and row <= rows then
                local color
                local ch
                if i == 0 then
                    color = head
                    ch = c.head_char
                elseif i < 3 then
                    color = bright
                    ch = c.chars[((i - 1) % c.length) + 1]
                elseif i < c.length * 0.6 then
                    color = mid
                    ch = c.chars[((i - 1) % c.length) + 1]
                else
                    color = dim
                    ch = c.chars[((i - 1) % c.length) + 1]
                end
                term:set(row, col_idx, ch, { fg = color, bold = (i == 0) })
            end
        end
    end
end
