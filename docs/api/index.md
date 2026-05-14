# Lua API reference

Every Lua surface cleat exposes to plugins, organized by namespace.

| Namespace | What you call it on | Pages |
|---|---|---|
| `ssh:*` | The `ssh` argument passed to `collect()` | [Host API](ssh.md) |
| `cleat.kv:*` | The global `cleat.kv` object | [Shared state](cleat-kv.md) |
| `cleat:notify` | The global `cleat` object | [Notifications](cleat-notify.md) |
| `store:*` | The `store` argument passed to `render()` | [Data store](store.md) |
| `ctx:*` | The `ctx` argument passed to `render()` | [Widget context](widget-context.md) |

## Where each runs

- **`ssh:*`** is available only in `collect()`. It's network-blocking
  — calls go over the SSH transport to the connected host.
- **`cleat.kv:*`** is available in any callback (`collect`,
  `transform`, `render`). State persists per-connection across
  plugin reloads.
- **`cleat:notify`** is available in any callback. Fire-and-forget,
  throttled, requires the `"notifications"` permission.
- **`store:*`** is only meaningful in `render()`. The shape of
  `store` depends on the plugin's `data_type`:
    - For `snapshot` and `table`, `store` is whatever `transform()`
      returned on the last tick — a plain Lua table you index
      directly.
    - For `timeseries` and `log`, `store` is a stateful object with
      query methods like `store:latest()`, `store:range("5m")`,
      `store:logs("1h")`.
- **`ctx:*`** is available only in `render()`. Drives the UI widgets.

## Error semantics, at a glance

| API | Failure shape |
|---|---|
| `ssh:exec`, `ssh:read_file`, `ssh:stat`, `ssh:env` | return `nil, error_string` |
| `ssh:os`, `ssh:cpu_count`, `ssh:hostname`, `ssh:ping`, `ssh:meta` | never fail; return sentinel values (`"unknown"`, `1`, `-1`, `{}`) |
| `cleat.kv:set`, `cleat.kv:delete` | return `nil, error_string` on validation failure |
| `cleat.kv:get`, `cleat.kv:list` | never error; return `nil` / empty table on miss |
| `cleat:notify` | fire-and-forget; silently no-ops on permission denial or throttling |
| `store:*` | never error; return `nil` / sentinel value / empty table when the store is empty |
| `ctx:*` | fire-and-forget; build widget output |

## API version

These docs describe **`api_version = "1"`** — the baseline cleat
plugin API. Plugins that don't declare an `api_version` are
assumed to target v1. Future breaking changes to any of the
surfaces below will be gated behind a new token.
