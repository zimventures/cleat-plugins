# Testing locally

Cleat is designed for fast plugin iteration. This page covers the
edit-save-reload loop, what to watch for in the Activity Log, and
how to sanity-check a plugin before submitting it to the registry.

## The edit-save-reload loop

After [creating a plugin](../getting-started/quickstart.md):

1. Edit `plugin.lua` in your external editor
2. Save the file
3. In Plugin Manager → Installed tab, click your plugin's row
4. Click **Reload** in the Actions row

**Reload** triggers an immediate `collect()` tick on every active
instance of the plugin (across all connected panes), so you don't
have to wait for the next scheduled poll.

If your plugin has a UI panel open, the next render after the tick
will reflect your changes. If you don't see them, check the
**Activity Log** at the bottom of the cleat window.

## Reading the Activity Log

The Activity Log records every plugin event:

- `PluginEngine: tick start <plugin>` — `collect()` was called
- `PluginEngine: tick complete <plugin>` — success
- `Plugin '<id>' error: <Lua message>` — `collect()` or
  `transform()` raised an error
- Health-status transitions (Active → Paused on repeated errors)

Filter by `Filter:` field at the top of the log to narrow to your
plugin's id while iterating.

## Debugging tips

### Print to the Activity Log

Cleat captures any Lua `print(...)` call from your plugin and routes
it to the Activity Log at info level. Useful for poking at
intermediate values:

```lua
function transform(raw, cfg)
    print("[my-plugin] raw bytes:", #raw, "first 80:", raw:sub(1, 80))
    -- ...
end
```

Remove these before submitting — gratuitous prints make the
Activity Log noisy for users.

### Inspect cfg values

If your plugin isn't getting the settings you expect:

```lua
function collect(ssh, cfg)
    for k, v in pairs(cfg) do
        print("[my-plugin] cfg." .. k .. " =", tostring(v), type(v))
    end
    -- ...
end
```

### Force an error

To verify error handling, raise from `transform()`:

```lua
function transform(raw, cfg)
    error("intentional test failure")
end
```

The Activity Log will show the error and the plugin will eventually
enter Paused state if errors keep firing. Click **Retry now** in the
Actions row to short-circuit the backoff.

## Sanity check: the install-preview audit

When you submit a plugin to the registry, end users see an
install-preview dialog that scans your `plugin.lua` for
`ssh:exec(...)` and `ssh:read_file(...)` calls and shows them as a
"capability audit". This same view is reachable from the
**Import Plugin...** flow in Plugin Manager.

Before submitting, do a self-audit:

1. Package your plugin's directory as a `.zip` with the structure
   `<your-id>/plugin.lua` inside
2. In Plugin Manager → toolbar → **Import Plugin...** → pick the
   zip
3. Review the **Commands** and **Reads** sections in the preview

Anything that shows up as `(dynamic — argument is not a literal
string)` means your plugin builds the command/path dynamically and
the audit can't show it. Consider whether the dynamic form is
necessary or if a constant would work — registry reviewers and end
users will trust the audit more when commands are statically
visible.

## Reproducible builds

Cleat plugins are pure Lua source — there's nothing to build. The
only "build" is what the registry's CI does when you submit:

```bash
# What CI does:
python tools/validate.py    # lint manifest + plugin.lua cross-check
python tools/build.py       # build the zip + update index.json
```

You can run both locally in a `cleat-plugins` checkout to preview
exactly what the registry will publish. See the
[Submitting](submitting.md) page for the full flow.

## Common gotchas

### `collect()` returning `nil`

If `collect()` returns nothing (or `nil`), cleat skips the tick
silently. Make sure you always return a string (possibly empty) even
on errors:

```lua
function collect(ssh, cfg)
    local out, err = ssh:exec("...")
    return out or ""   -- always return something
end
```

### Mistaking `transform()` for `collect()`

`transform()` does NOT have access to `ssh`. If you try to call
`ssh:exec` from inside `transform()` you'll get a nil-indexing
error. Keep all host I/O in `collect()`.

### Forgetting to handle empty `store`

The very first render after a plugin is enabled (or after a Reload)
may run before `collect()` has produced any data. Guard your
`render()`:

```lua
function render(ctx, store, cfg)
    if not store or (data_type == "timeseries" and not store:latest()) then
        ctx:text("Collecting...")
        return
    end
    -- ...
end
```

### Long-running `ssh:exec`

If your `collect()` runs a command that takes 30s, every other
plugin on that connection waits behind it. Set explicit timeouts:

```lua
ssh:exec("slow-command", 5000)  -- 5s ceiling
```

5–10 seconds is a reasonable ceiling for most things.

### Trusting `os.time()` for cross-host correlation

`os.time()` in your plugin returns the **client's** clock, not the
remote host's. If you need server-side timestamps (e.g. parsing log
lines with their own times), parse them from the command output.
