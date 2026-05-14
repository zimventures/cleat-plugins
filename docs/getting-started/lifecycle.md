# Plugin lifecycle

Plugins are scheduled, sandboxed Lua programs. Cleat's plugin engine
calls into your plugin at well-defined moments; this page walks
through those moments.

## The three callbacks

Every plugin defines (some subset of) three top-level functions:

```lua
function collect(ssh, cfg)
    -- Fetch raw data from the remote host.
    return "..."
end

function transform(raw, cfg)
    -- Parse raw data into a structured value.
    return { ... }
end

function render(ctx, store, cfg)
    -- Draw the UI from store data.
    ctx:section({ ... })
end
```

`collect` and `transform` are required for plugins that produce data
(snapshot / timeseries / log / table). `render` is optional but
expected for plugins with a visible panel.

## How cleat schedules them

```
  ┌─────────────────────────────────────────┐
  │  Scheduler thread (one per cleat run)   │
  ├─────────────────────────────────────────┤
  │  every default_interval seconds:        │
  │    raw = collect(ssh, cfg)              │ ← runs on scheduler thread
  │    value = transform(raw, cfg)          │ ← runs on scheduler thread
  │    store.append(value)                  │
  └────────────────┬────────────────────────┘
                   │
                   ▼ store data
  ┌─────────────────────────────────────────┐
  │  Main thread (UI render loop, 60fps)    │
  ├─────────────────────────────────────────┤
  │  on plugin panel visible:               │
  │    render(ctx, store, cfg)              │ ← runs on main thread
  └─────────────────────────────────────────┘
```

The key takeaways:

- **`collect` blocks the scheduler thread.** Use timeouts on
  long-running commands (`ssh:exec("...", timeout_ms)`). The
  scheduler runs your plugin in series with every other plugin
  on the same connection, so a 30-second `collect` blocks
  everyone.
- **`transform` runs immediately after `collect`** on the same
  thread, with the raw return value. Pure function — no host
  access (the `ssh` arg is not available here).
- **`render` runs on the UI thread.** Keep it fast — it's called
  every frame the panel is visible. Don't do I/O or expensive
  parsing here; that belongs in `transform`.

## Streaming mode

For plugins that consume a continuous data stream (logs, syscall
traces, etc.), set `streaming = true` in metadata. Then:

- `collect(ssh, cfg)` is called **once** at plugin start. It returns
  the command string to stream.
- `transform(line, cfg)` is called for each line of output, with the
  individual line as `raw`. Returns a value to append to the store.
- `render(ctx, store, cfg)` is unchanged.

The engine maintains the channel and restarts it on
`streaming_idle_seconds` of silence.

## The `cfg` argument

`cfg` is the user's per-plugin configuration as filled in by the
Plugin Manager's Settings panel. Values are typed according to the
plugin's `settings = { ... }` array:

```lua
plugin = {
    ...
    settings = {
        { key = "warn_pct", label = "Warning %",  type = "number", default = "80" },
        { key = "skip_lo",  label = "Skip lo iface", type = "boolean", default = "true" },
        { key = "mode",     label = "Mode", type = "string", default = "polling",
          values = { "polling", "streaming" } },
    },
}

function collect(ssh, cfg)
    if cfg.skip_lo then ... end       -- boolean
    local threshold = cfg.warn_pct    -- number
    local mode = cfg.mode             -- string
end
```

See the [manifest settings reference](../manifest/settings.md) for
the full schema.

## Data types

Each plugin declares a `data_type` in its metadata. This drives how
the engine stores returned values and what methods are available on
`store` in `render()`:

| `data_type`  | `transform()` returns | `store:*` methods                    | Best for |
|--------------|------------------------|--------------------------------------|----------|
| `snapshot`   | a table — exposed as `store` directly | (none — `store` is the table itself) | "Latest value" data: uptime, OS info, summary stats |
| `timeseries` | a table of `{ name = value, ... }` numeric values (one tick at a time) | `latest`, `range`, `avg`, `max`, `min`, `count` | Graphed metrics — CPU, memory, latency |
| `log`        | a table of log entries `{ t, level, message, source, labels }` | `logs`, `latest_logs`, `count_logs` | Tailing events — auth failures, error logs |
| `table`      | a table — exposed as `store` directly | (none — `store` is the table itself) | Structured rows: containers, ports, processes |

Snapshot and table both bypass the data-store query API — they pass
the latest `transform()` return verbatim to `render()` as `store`.
Timeseries and log accumulate data across ticks and expose query
helpers via the [store API](../api/store.md).

## Sandbox guarantees

Cleat runs each plugin instance in its own Lua state with the
standard library pruned: `io`, `os.execute`, `os.exit`, `os.remove`,
`os.rename`, `os.tmpname`, `debug`, `loadfile`, `dofile`, `package`,
`load`, `loadstring`, `rawset`, `rawget`, `rawequal`, `rawlen` are
all removed.

Plugins only reach outside their Lua state through the explicitly
provided API: `ssh:*`, `cleat:*`, `cleat.kv:*`, `ctx:*`, `store:*`.
Anything else — direct filesystem access, child processes,
arbitrary network calls — is not available.

## What cleat doesn't do

- **No retries on `collect()` errors.** If `collect()` raises a Lua
  error, the engine logs it, increments the plugin's error
  counter, and tries again on the next tick. After enough
  consecutive failures, the plugin enters paused state with an
  exponential backoff. The user can hit **Retry now** in the
  Actions row to short-circuit.
- **No deduplication of state across ticks.** If you want to track
  "did anything change since last tick?", store the last seen value
  via `cleat.kv:set()` and compare in the next call.
- **No cross-pane shared state by default.** Each (pane × plugin)
  pair gets its own data store. Use [`cleat.kv:*`](../api/cleat-kv.md)
  for per-connection shared state across plugins.
