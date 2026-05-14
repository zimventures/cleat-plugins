# Notifications (`cleat:notify`)

Surface toast notifications to the user. Useful for crossing
thresholds: failed-login bursts, disk-usage alarms, error spikes
in tailed logs.

## Permission requirement

`cleat:notify` only works if the plugin declares the
`"notifications"` permission in its metadata:

```lua
plugin = {
    ...
    permissions = { "notifications" },
}
```

Without the declaration, calls silently no-op and log a debug
message. The Plugin Manager surfaces declared permissions to the
user up-front so they can revoke per-plugin if they don't want
toasts from your plugin.

See [Permissions](../manifest/permissions.md).

## Signature

```lua
cleat:notify(options)
```

**`options`** is a table:

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `title` | string | **yes** | — | Short headline. Calls without a title silently no-op (with a warning log). |
| `body` | string | no | empty | Longer body text. Optional one-liner detail. |
| `level` | string | no | `"info"` | `"info"`, `"warn"`, or `"error"` — drives the toast's color and any platform notification urgency. |
| `ttl_ms` | integer | no | `5000` | How long the toast stays visible. Set `0` for "sticky until dismissed". Clamped to a platform max. |
| `on_click` | string | no | `"none"` | `"open_view"` (opens the plugin's panel), `"open_logs"` (opens the Activity Log), or `"none"`. |

**Returns** — nothing. Fire-and-forget; validation, permission, and
throttling failures are logged rather than surfaced to your code.

## Example: disk-fill alert

```lua
plugin = {
    id = "statusbar-disk",
    ...
    permissions = { "notifications" },
}

function transform(raw, cfg)
    local pct = parse_pct(raw)
    if pct >= cfg.crit_pct then
        cleat:notify({
            title = "Disk almost full",
            body = string.format("/ on %s at %d%%", ssh_hostname(), pct),
            level = "warn",
            ttl_ms = 10000,
            on_click = "open_view",
        })
    end
    return { pct = pct }
end
```

## Throttling

Cleat throttles `cleat:notify` to **3 notifications per minute per
plugin**. Excess calls are dropped silently; the user sees one
"X notifications suppressed" summary toast on the next render to
make sure they know the plugin is still trying.

The throttle is intentional — a plugin firing every tick for the
same condition would overwhelm the user. Use [`cleat.kv:*`](cleat-kv.md)
to remember which conditions you've already alerted on if you need
strict "fire once per state transition" semantics.

## Click actions

| `on_click` | Effect |
|---|---|
| `"none"` | Toast disappears when clicked / dismissed. No further action. |
| `"open_view"` | Opens your plugin's panel for the pane that fired the notification. |
| `"open_logs"` | Opens cleat's Activity Log. |

Other values are accepted but treated as `"none"`.

## What `cleat:notify` does NOT do

- **Doesn't return anything.** No way for the plugin code to know
  whether the toast was actually shown — by design.
- **Doesn't block.** It's queued to a thread-safe inbox; rendering
  happens on cleat's UI thread on the next frame.
- **Doesn't survive cleat restart.** Toasts are ephemeral. If you
  want persistence, use `cleat.kv` or the data store.
