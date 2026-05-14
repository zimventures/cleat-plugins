# Quickstart

The fastest path from "idea" to "running plugin" is cleat's built-in
**Create New Plugin** wizard. It scaffolds a working plugin from a
template, opens it in your editor, and reloads it live as you iterate.

## Prerequisites

- A working cleat install (any recent version)
- A saved SSH connection you can test against (the local machine via
  `localhost` works fine)
- A text editor configured in cleat (Settings → SFTP → External editor)

## 1. Create the plugin

1. Open the Plugin Manager (default shortcut: command palette →
   *Plugin Manager*).
2. On the **Installed** tab toolbar, click **Create New Plugin...**.
3. Pick a template that matches what you want to build:
    - **Snapshot** — one-shot "latest value" data (uptime, OS info)
    - **Timeseries** — graphed numeric trends (CPU, memory)
    - **Log** — append-only timestamped entries (auth failures, errors)
    - **Table** — structured rows (containers, ports)
4. Give it an id (kebab-case, e.g. `my-disk-watcher`) and a display
   name. Click **Create**.

Cleat writes `~/.config/cleat/plugins/<id>/plugin.lua` from the
template, opens it in your external editor, and shows the new plugin
in the Installed tab.

## 2. Edit and reload

Open the plugin in your editor. The template has three callable
functions:

```lua
function collect(ssh, cfg)
    -- Run something on the remote host, return raw text.
    return ssh:exec("uname -a") or ""
end

function transform(raw, cfg)
    -- Parse the raw text into a structured value.
    return { uname = raw }
end

function render(ctx, store, cfg)
    -- Draw the UI. `store` exposes whatever transform() returned.
    ctx:section({
        title = "System",
        children = function(ctx)
            ctx:text(store.uname or "—")
        end,
    })
end
```

Change anything you want, save the file, then back in cleat's Plugin
Manager click the plugin's row and hit **Reload** in the Actions row.
The next collect tick will run your updated code.

!!! tip "Iteration loop"
    The fastest dev cycle is: edit → save → **Reload** → check the
    plugin's panel in a connected pane. Cleat's scheduler runs your
    `collect()` at the plugin's `default_interval` (defaults to
    30s); **Reload** also triggers an immediate tick.

## 3. Open the plugin's panel

To see your plugin's `render()` output:

1. Connect a terminal pane to your saved SSH connection.
2. Right-click the pane → *Plugin Views* → your plugin's name.
3. The plugin's panel opens in a side panel; it'll populate after the
   next collect tick.

If something doesn't show up, check the **Activity Log** at the
bottom of the cleat window for plugin errors (uncaught Lua errors,
`collect()` returning nil, etc.).

## 4. Iterate

The realistic loop:

1. Tweak `collect()` to fetch what you want — try `ssh:read_file`,
   `ssh:stat`, multiple `ssh:exec` calls joined with a delimiter.
2. Tweak `transform()` to parse cleanly. The
   [string-splitting examples in the API docs](../api/widget-context.md)
   are good starting points.
3. Tweak `render()` to make the UI useful. The
   [widget reference](../api/widget-context.md) has all the
   primitives.

When your plugin's good enough to share, jump to
[**Submitting to the registry**](../workflow/submitting.md).

## What you didn't have to do

Compared to typical plugin systems, cleat does a lot of plumbing for
you:

- **No package manager** — author your plugin as plain Lua source.
  Cleat handles loading, sandboxing, and isolation.
- **No build step** — save the file, hit Reload. There's no compile,
  no bundle, no transpile.
- **No zip packaging for the registry** — the registry's CI does that.
  Your job is the source code; CI does the rest.
- **No hash management** — when you publish, CI computes and pins the
  sha256. Clients verify it on install.

## Next

- [Plugin lifecycle](lifecycle.md) — understand how `collect`,
  `transform`, and `render` get scheduled
- [Lua API reference](../api/index.md) — every function plugins can
  call
- [Plugin manifest](../manifest/plugin-table.md) — every field you
  can put in the `plugin = { ... }` table
