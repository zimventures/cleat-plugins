# Widget context (`ctx:*`)

The `ctx` argument passed to `render(ctx, store, cfg)` lets your
plugin build the panel UI. It exposes layout primitives, text
widgets, and a small library of data-visualization widgets.

`render()` runs on cleat's UI thread every frame the panel is
visible — keep it cheap. Pre-shape data in `transform()`; here, just
draw.

## Layout primitives

### `ctx:row(children)`

Stack children horizontally.

```lua
ctx:row(function(ctx)
    ctx:stat_card({ label = "CPU",    value = "45", unit = "%" })
    ctx:stat_card({ label = "Memory", value = "8.1", unit = "GB" })
end)
```

The `children` function receives the same `ctx` object — recurse
freely.

### `ctx:section(opts)`

A titled, optionally-collapsible container.

```lua
ctx:section({
    title = "Network",
    open = true,  -- default true
    children = function(ctx)
        ctx:text("eth0: up")
    end,
})
```

| Field | Type | Default |
|---|---|---|
| `title` | string | (required) |
| `open` | boolean | `true` |
| `children` | function(ctx) | (required) |

### `ctx:separator()`

Renders a horizontal rule.

```lua
ctx:text("Above")
ctx:separator()
ctx:text("Below")
```

### `ctx:space([height])`

Vertical spacer. Height in pixels.

```lua
ctx:space(16)
```

## Text

### `ctx:text(s)`

Plain text in the theme's default body color.

```lua
ctx:text("Updated: " .. os.date("%H:%M:%S"))
```

### `ctx:text_colored(opts)`

Text in a chosen color.

```lua
ctx:text_colored({ text = "Status: Up", color = "green" })
```

| Field | Type | Notes |
|---|---|---|
| `text` | string | required |
| `color` | string | one of `"green"`, `"yellow"`, `"red"`, `"blue"`, `"orange"`, `"gray"`; or a `"#RRGGBB"` hex |

## Stat cards

### `ctx:stat_card(opts)`

A single labeled metric with optional unit, color, tooltip, and
inline sparkline.

```lua
ctx:stat_card({
    label = "Latency",
    value = "12.4",
    unit = "ms",
    color = "green",
    tooltip = "Median over the last minute",
})
```

| Field | Type | Notes |
|---|---|---|
| `label` | string | required |
| `value` | string | required — pre-formatted |
| `unit` | string | optional |
| `color` | string | optional — defaults to `"green"`; use `ctx:threshold_color(...)` for value-driven coloring |
| `tooltip` | string | optional — shown on hover |
| `sparkline` | array of `{t, v}` | optional — small trend line beside the value |

### `ctx:stat_row(opts)`

Lay out multiple stat cards in a row.

```lua
ctx:stat_row({
    cards = {
        { label = "CPU",    value = "45", unit = "%", color = "yellow" },
        { label = "Memory", value = "8.1", unit = "GB", color = "green" },
        { label = "Disk",   value = "230", unit = "GB" },
    },
})
```

## Tables

### `ctx:table(opts)`

A sortable table of string values.

```lua
ctx:table({
    title = "Listening ports",
    columns = {
        { header = "Port",    sortable = true },
        { header = "Process", sortable = true },
        "Address",
    },
    rows = {
        { "22",  "sshd",  "0.0.0.0" },
        { "80",  "nginx", "0.0.0.0" },
        { "443", "nginx", "0.0.0.0" },
    },
})
```

Columns can be either:

- a string — header text only, not sortable
- a table `{ header = "...", sortable = true|false }`

Rows are arrays of strings. Format numeric values yourself before
passing them in.

## Gauges

### `ctx:gauge(opts)`

Circular dial.

```lua
ctx:gauge({
    label = "CPU",
    value = 42,
    min = 0, max = 100,
    warn = 70, crit = 90,
    unit = "%",
    size = 100,
})
```

| Field | Type | Default |
|---|---|---|
| `label` | string | (required) |
| `value` | number | (required) |
| `min` | number | `0` |
| `max` | number | `100` |
| `warn` | number | `70` |
| `crit` | number | `90` |
| `unit` | string | `"%"` |
| `size` | number (px) | `80` |

Color tier: green below `warn`, yellow between `warn` and `crit`,
red at or above `crit`.

## Charts

### `ctx:line_graph(opts)`

Multi-series line graph, typically driven by timeseries `store`
queries.

```lua
ctx:line_graph({
    title = "Load over the last 5 minutes",
    unit  = "",
    y_min = 0, y_max = 4,
    warn  = 1.5, crit = 3.0,
    series = {
        { name = "load1",  color = "green",  data = store:range("5m", "load1") },
        { name = "load5",  color = "yellow", data = store:range("5m", "load5") },
        { name = "load15", color = "orange", data = store:range("5m", "load15") },
    },
    height = 200,
})
```

Each series's `data` is an array of `{ t = timestamp, v = value }`
tables — the exact shape `store:range()` returns.

### `ctx:sparkline(opts)`

Compact inline trend line. Same data shape as the line graph.

```lua
ctx:sparkline({
    data = store:range("5m", "cpu"),
    color = "yellow",
    width = 100,
    height = 20,
})
```

### `ctx:bar_chart(opts)`

Categorical bars (e.g. per-partition disk usage).

```lua
ctx:bar_chart({
    title = "Filesystem usage",
    bars = {
        { label = "/",     value = 78,  unit = "%", color = "yellow" },
        { label = "/home", value = 45,  unit = "%" },
        { label = "/var",  value = 92,  unit = "%", color = "red" },
    },
    y_min = 0, y_max = 100,
    height = 180,
})
```

### `ctx:heatmap(opts)`

2D grid of values; useful for time-of-day × day-of-week density,
correlation matrices, etc.

```lua
ctx:heatmap({
    title = "Auth failures by hour and day",
    cols = { "00", "01", "02", ..., "23" },
    rows = { "Mon", "Tue", ..., "Sun" },
    values = {            -- row-major
        { 0, 0, 1, 0, ... },
        { 0, 0, 0, 2, ... },
        ...
    },
    v_min = 0, v_max = 10,
    scale = "linear",     -- or "log"
    cell_label = true,
    height = 240,
    unit = "events",
})
```

| Field | Type | Notes |
|---|---|---|
| `values` | 2D array | row-major; cells with `NaN` render blank |
| `rows` | array of strings | row labels (optional) |
| `cols` | array of strings | column labels (optional) |
| `v_min` / `v_max` | number | bounds for color mapping; you can pin one and let the other auto |
| `scale` | string | `"linear"` or `"log"` |
| `palette` | array | optional custom color stops (default severity green→yellow→red) |

## Logs

### `ctx:log_viewer(opts)`

Scrolling, color-coded log list — typically driven by a log
data-type plugin's `store:logs()` or `store:latest_logs()`.

```lua
ctx:log_viewer({
    title = "Recent auth failures",
    entries = store:latest_logs(200),
    height = 300,
    auto_scroll = true,
    show_source = true,
})
```

Entry shape (from `store:logs()`):

```lua
{ t = 1715600000, level = "error", message = "Failed password for root from 1.2.3.4",
  source = "sshd", labels = "user=root,ip=1.2.3.4" }
```

| Field | Type | Default |
|---|---|---|
| `entries` | array of entries | (required) |
| `height` | number | `240` |
| `auto_scroll` | boolean | `true` |
| `show_source` | boolean | `true` |

## Helpers

### `ctx:threshold_color(value, warn, crit)`

Pick the conventional severity color for a value.

```lua
local color = ctx:threshold_color(cpu_pct, 70, 90)
ctx:stat_card({ label = "CPU", value = string.format("%.0f", cpu_pct), color = color })
```

| Condition | Returns |
|---|---|
| `value >= crit` | `"red"` |
| `value >= warn` | `"yellow"` |
| otherwise       | `"green"` |

## Data point format

Every time-series widget (`line_graph`, `sparkline`) takes data as
arrays of:

```lua
{ t = <unix-epoch-seconds>, v = <numeric-value> }
```

This is exactly what `store:range()`, `store:latest()`, etc. return —
plug them straight through.
