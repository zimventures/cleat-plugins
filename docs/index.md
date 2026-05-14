# cleat plugins

[cleat](https://zimventures.com/cleat/) lets plugins extend the
SSH client with custom data collection, visualization, and host
introspection. Plugins are small Lua programs that run inside an
isolated sandbox per pane, collect data from the connected host, and
render widgets in cleat's Plugin Manager and status bar.

This site documents how to **author** a plugin, **test** it locally,
and **submit** it to the official registry.

## Quick links

<div class="grid cards" markdown>

-   :material-rocket-launch: **[Quickstart](getting-started/quickstart.md)**

    ---

    Write your first plugin in 10 minutes using cleat's built-in
    Create New Plugin wizard.

-   :material-api: **[Lua API reference](api/index.md)**

    ---

    Every function plugins can call: `ssh:*`, `cleat.kv:*`,
    `cleat:notify`, `ctx:*`, and `store:*`.

-   :material-file-cog: **[Plugin manifest](manifest/plugin-table.md)**

    ---

    Every field cleat reads from the `plugin = { ... }` table at
    the top of your `plugin.lua`.

-   :material-source-pull: **[Submitting to the registry](workflow/submitting.md)**

    ---

    Open a PR adding `plugins/<your-id>/`, CI validates + builds +
    publishes — no zip packaging required.

</div>

## What is a cleat plugin?

A plugin is a single `plugin.lua` file (plus an optional
`plugin.json` manifest when published to the registry) that defines:

1. **Metadata** — id, name, version, the data type it produces.
2. **`collect(ssh, cfg)`** — what to fetch from the remote host every
   tick. Runs in cleat's scheduler thread with a `ssh:*` API for
   running commands, reading files, getting host info.
3. **`transform(raw, cfg)`** — turn the raw collected text into a
   structured value cleat will store.
4. **`render(ctx, store, cfg)`** — draw the widget UI when the user
   opens the plugin's panel. Uses `ctx:*` to build widgets and
   `store:*` to query the data store.

Cleat handles the scheduling, sandboxing, data persistence, and UI
rendering. You write Lua that produces and visualizes data.

## How does distribution work?

Plugins live in the [`cleat-plugins`](https://github.com/zimventures/cleat-plugins)
registry as directories under `plugins/<id>/`. On every merge to
`main`, CI walks each directory, zips it, computes the sha256, and
publishes both the zip and an aggregated `index.json` to GitHub
Pages. Cleat's Plugin Manager fetches that index, shows the
catalog under **Browse Marketplace**, and installs from the
pinned zip URL.

Authors submit source files. CI handles packaging, hashing, and
hosting — there's no per-author zip pipeline to maintain.

## Trust model

A plugin's presence in the registry means a maintainer reviewed the
PR that introduced it. The `sha256` cleat publishes alongside each
entry is, by construction, the hash of the bytes that were reviewed
at merge time. Cleat's client verifies that hash on every install:
tampered bytes are refused with an explicit error.

See the [registry's trust model details](SCHEMA.md#trust-model) for
the full story.
