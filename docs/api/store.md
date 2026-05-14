# Data store (`store:*`)

The `store` argument to `render(ctx, store, cfg)` exposes whatever
`transform()` has accumulated for this (pane, plugin) pair. Its
shape depends on the plugin's `data_type`.

## Snapshot and table

For `data_type = "snapshot"` and `data_type = "table"`, `store` **is**
the last value `transform()` returned — a plain Lua table. There are
no query methods; you index it directly.

```lua
plugin = { ..., data_type = "snapshot" }

function transform(raw, cfg)
    return { uname = raw, ts = os.time() }
end

function render(ctx, store, cfg)
    if not store then return end
    ctx:text(store.uname or "—")
    ctx:text("Updated: " .. os.date("%H:%M:%S", store.ts))
end
```

The runtime guards against shadowing: if your snapshot table has a
field that collides with one of the reserved method names below (it
doesn't matter for snapshot/table since those methods aren't
attached, but the warning fires if you later switch the plugin to
timeseries), cleat logs a warning so you know the name is reserved.

## Timeseries

For `data_type = "timeseries"`, `store` is a stateful object that
queries the plugin's per-pane timeseries store. Each tick,
`transform()` returns a table of numeric series (`{ cpu = 42.5,
mem_pct = 81 }`); the engine appends each as a `(timestamp, value)`
sample for that series name.

### `store:latest([series])`

```lua
local pt = store:latest("cpu")  -- or just store:latest() for the default series
```

**Returns** — `{ t = timestamp, v = value }` for the most recent
sample, or `nil` if the series has no data yet.

### `store:range(duration [, series])`

```lua
local points = store:range("5m", "cpu")
```

**Arguments**

- `duration` (string, required) — duration ending at "now", e.g.
  `"5m"`, `"1h"`, `"24h"`, `"7d"`
- `series` (string, optional, default empty) — series name; empty
  for the default series

**Returns** — array of `{ t, v }` tables, oldest-first. Empty array
if no data in the window.

### `store:avg(duration [, series])`

```lua
local mean = store:avg("5m", "cpu")
```

**Returns** — numeric average of all samples in the window, or `0`
if no data.

### `store:max(duration [, series])`

Same shape as `:avg`; returns the max sample value in the window
(or `0` if empty).

### `store:min(duration [, series])`

Same shape; returns the min.

### `store:count([series])`

```lua
local n = store:count("cpu")  -- all-time count, not windowed
```

**Returns** — total samples retained for this series.

### Timeseries example

```lua
function render(ctx, store, cfg)
    ctx:line_graph({
        title = "CPU over last 5 minutes",
        unit = "%",
        y_min = 0, y_max = 100,
        warn = cfg.warn_pct, crit = cfg.crit_pct,
        series = {
            { name = "cpu", color = "green", data = store:range("5m", "cpu") },
        },
    })

    local current = store:latest("cpu")
    if current then
        ctx:stat_card({
            label = "Now",
            value = string.format("%.0f", current.v),
            unit = "%",
            color = ctx:threshold_color(current.v, cfg.warn_pct, cfg.crit_pct),
        })
    end
end
```

## Log

For `data_type = "log"`, `store` queries the plugin's per-pane log
store. `transform()` returns either:

- a single log entry `{ t, level, message, source, labels }`, or
- an array of such entries (for batched parsers)

### `store:logs(duration)`

```lua
local entries = store:logs("1h")
```

**Returns** — array of log entries in the window:

| Field | Type | Notes |
|---|---|---|
| `t` | number | Unix epoch seconds |
| `level` | string | `"info"`, `"warn"`, `"error"`, etc. — your plugin chooses values |
| `message` | string | the log line |
| `source` | string | optional source identifier (filename, syslog facility, etc.) |
| `labels` | string | optional key=value labels (your plugin's convention) |

### `store:latest_logs([n])`

```lua
local recent = store:latest_logs(50)  -- last 50 entries, oldest-first
```

**Arguments**

- `n` (integer, optional, default `100`) — how many to return

**Returns** — most-recent N entries, oldest-first. Empty array if
no data.

### `store:count_logs()`

```lua
local total = store:count_logs()
```

**Returns** — total log entries retained.

### Log example

```lua
function render(ctx, store, cfg)
    ctx:log_viewer({
        title = "Recent failures",
        entries = store:latest_logs(200),
        height = 300,
        auto_scroll = true,
    })
end
```

## Duration strings

All duration-taking methods (`:range`, `:avg`, `:max`, `:min`,
`:logs`) accept strings like:

- `"30s"` — 30 seconds
- `"5m"` — 5 minutes
- `"1h"` — 1 hour
- `"24h"` — 24 hours
- `"7d"` — 7 days

Parsing is forgiving but undocumented for unusual forms; stick to
the conventional `<number><unit>` shape.

## When `store` is empty

A common gotcha: on the very first render after a plugin is
enabled, the data store may be empty (the first `collect()` tick
hasn't happened yet). Always guard:

```lua
function render(ctx, store, cfg)
    local pt = store:latest("cpu")
    if not pt then
        ctx:text("Collecting...")
        return
    end
    -- ...
end
```
