# Settings

User-configurable options exposed in the Plugin Manager's Settings
panel. Each entry in the `settings = { ... }` array becomes one
input widget the user can edit per-plugin; the values arrive in
`collect()` / `transform()` / `render()` via the `cfg` argument.

## Shape

```lua
plugin = {
    ...
    settings = {
        { key = "...", label = "...", type = "...", default = "...", values = { ... } },
        { ... },
    },
}
```

Each entry is a table with the following fields:

| Field | Type | Required | Notes |
|---|---|---|---|
| `key` | string | yes | Identifier passed to your callbacks as `cfg.<key>`. Conventionally lowercase + underscores. |
| `label` | string | yes | Human-readable label shown in Plugin Manager. |
| `type` | string | yes | One of `"string"`, `"number"`, `"boolean"`. Drives the input widget. |
| `default` | string | no | Default value as a string. Converted to the appropriate type at runtime — e.g., `"30"` for a `number` becomes `30.0` in `cfg`. |
| `values` | array of strings | no | When present, the input is rendered as a dropdown. Only meaningful for `type = "string"`. |

Entries with an empty `key` are silently skipped by the loader.

## Type coercion

The Plugin Manager stores all values as strings (the underlying
SettingsManager uses a single string-typed schema for plugin
settings). The plugin engine coerces them at call-time:

- `type = "string"` → `cfg.<key>` is a Lua string.
- `type = "number"` → `cfg.<key>` is a Lua number. Parsed via
  `tonumber()`; unparseable values fall back to 0.
- `type = "boolean"` → `cfg.<key>` is a Lua boolean. Truthy strings:
  `"true"`, `"1"`, `"yes"`. Anything else is false.

## Example: dropdown

```lua
settings = {
    {
        key = "mode",
        label = "Collection mode",
        type = "string",
        default = "polling",
        values = { "polling", "streaming" },
    },
},
```

The user sees a dropdown with two choices; `cfg.mode` is one of
those two strings in your callbacks.

## Example: thresholds

```lua
settings = {
    { key = "warn_pct", label = "Warning threshold (%)",   type = "number",  default = "70" },
    { key = "crit_pct", label = "Critical threshold (%)",  type = "number",  default = "90" },
},

function transform(raw, cfg)
    local color = "green"
    if value >= cfg.crit_pct then color = "red"
    elseif value >= cfg.warn_pct then color = "yellow"
    end
    ...
end
```

## Example: opt-in feature

```lua
settings = {
    { key = "include_stopped", label = "Include stopped containers",
      type = "boolean", default = "false" },
},

function collect(ssh, cfg)
    local flag = cfg.include_stopped and "-a" or ""
    return ssh:exec("docker ps " .. flag .. " --format '{{json .}}'")
end
```

## Surfacing changes to running instances

When the user edits a setting, the Plugin Manager queues a reload of
that plugin's instances. Your `collect()` will see the new `cfg`
value on the next tick — no explicit refresh needed.
