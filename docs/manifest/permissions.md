# Permissions

`permissions = { ... }` declares opt-in capabilities your plugin
needs to function. The Plugin Manager shows declared permissions in
the plugin's detail panel; the user can revoke per-plugin from there.

## Shape

```lua
plugin = {
    ...
    permissions = { "notifications" },
}
```

It's a simple array of strings. Cleat ships with a curated set of
recognized permission names; declaring an unrecognized name doesn't
fail loading — the Plugin Manager surfaces it as "declared but
unrecognized" so future cleat releases can add capabilities without
breaking older plugins.

## Recognized permissions

### `"notifications"`

Required to call [`cleat:notify(...)`](../api/cleat-notify.md). Plugins
without this declaration can call `cleat:notify(...)` — the call
silently no-ops and logs a debug message. Declare this when your
plugin legitimately needs to alert the user (failed-login alerts,
disk-full warnings, etc.).

```lua
plugin = {
    ...
    permissions = { "notifications" },
}

function transform(raw, cfg)
    if disk_usage >= cfg.crit_pct then
        cleat:notify({
            title = "Disk almost full",
            body = string.format("/var on %s at %d%%", host, disk_usage),
            level = "warn",
        })
    end
    return { ... }
end
```

The notification system is throttled to 3 notifications per minute
per plugin; excess calls drop with a single summary toast. See
[`cleat:notify`](../api/cleat-notify.md) for full details.

## Why declarations matter

The point of declared permissions is **informed consent** at install
time. Cleat's install-preview dialog (the modal that appears for
both URL-installed and marketplace-installed plugins) surfaces every
declared permission verbatim before the user clicks Install. A plugin
that *gains* a permission in a later version triggers a re-display of
the diff during the Update flow, so users see "this plugin now wants
to send notifications" before consenting.

If you don't need a capability, don't declare it — it'll just nag the
user about something they don't get.

## Adding new permissions

If you find yourself wanting a permission that doesn't exist, open
an issue in the cleat repo describing the use case. Permissions are
deliberately added one-by-one with explicit semantics, not auto-
inferred from API usage.
