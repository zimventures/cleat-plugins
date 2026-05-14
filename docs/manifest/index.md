# Plugin manifest

Every plugin starts with a `plugin = { ... }` table at the top of
`plugin.lua`. This table is the **runtime manifest** — cleat reads it
to decide how to schedule, store, and render the plugin.

Pages in this section:

- **[The `plugin = {}` table](plugin-table.md)** — every field cleat
  reads, with type, default, and effect.
- **[Settings](settings.md)** — the `settings = { ... }` array for
  user-configurable options exposed in Plugin Manager.
- **[Permissions](permissions.md)** — the `permissions = { ... }`
  array for opt-in capabilities like `cleat:notify`.

## Two manifests, one source of truth

There are two manifest formats in the plugin ecosystem:

| | Where | Format | Who reads it |
|---|---|---|---|
| **Runtime manifest** | `plugin = {}` table at the top of `plugin.lua` | Lua table syntax | Cleat's plugin engine |
| **Registry manifest** | `plugin.json` next to `plugin.lua` | JSON | The cleat-plugins registry CI |

The two share most fields by convention — cleat-plugins's CI
cross-checks that `id` and `version` in `plugin.json` match the
values inside `plugin.lua`. The Lua-side has additional runtime
fields (`default_interval`, `data_type`, `settings`, etc.) that the
registry doesn't care about; the JSON-side has registry-only fields
(`source_url`, `sha256` — though those are CI-generated, not author-
supplied).

For the registry manifest schema, see
[`SCHEMA.md`](../SCHEMA.md). For the runtime manifest's full field
catalog, start with [the `plugin = {}` table](plugin-table.md).
