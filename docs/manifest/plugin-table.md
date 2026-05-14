# The `plugin = {}` table

Every plugin.lua starts with a top-level table named `plugin`:

```lua
plugin = {
    id = "process-list",
    name = "Process List",
    description = "Top processes by CPU/memory",
    version = "1.2.0",
    author = "alice",
    category = "System",
    default_interval = 30,
    min_interval = 10,
    data_type = "timeseries",
    retention = "24h",
    statusbar = false,
    settings = { ... },
    permissions = { ... },
}
```

Cleat's `PluginLoader::parseMetadata` reads this table on every load.
Below is every field it recognizes.

## Required fields

### `id`

| | |
|---|---|
| **Type** | string |
| **Required** | yes — load fails if missing |
| **Format** | `[A-Za-z0-9_-]+`, starts with alphanumeric, ≤64 chars |
| **Effect** | Stable, filesystem-safe identifier. Used as the on-disk directory name and the unique key in the registry. Must be unique across all plugins in the registry. |

### `name`

| | |
|---|---|
| **Type** | string |
| **Required** | yes — load fails if missing |
| **Effect** | Human-readable name shown throughout the Plugin Manager. Conventionally Title Case. |

### `version`

| | |
|---|---|
| **Type** | string |
| **Required** | yes — load fails if missing |
| **Format** | `MAJOR.MINOR.PATCH` semver (e.g. `1.0.0`, `2.3.1`) |
| **Effect** | The marketplace update checker compares this against the registry's published version to decide whether to flag an update. Must match the `version` in the sibling `plugin.json` when published to the registry. |

## Identity & display

### `description`

| | |
|---|---|
| **Type** | string |
| **Default** | empty |
| **Effect** | One-sentence summary shown in the Plugin Manager. The Browse list truncates long descriptions in the row preview. |

### `author`

| | |
|---|---|
| **Type** | string |
| **Default** | empty |
| **Effect** | Author handle or display name. Free-form; shown verbatim. |

### `icon`

| | |
|---|---|
| **Type** | string (asset filename or reference) |
| **Default** | empty (default icon fallback) |
| **Effect** | Identifier for the plugin's icon. Format depends on the cleat asset loader; broken icons fall back gracefully. |

### `category`

| | |
|---|---|
| **Type** | string |
| **Default** | empty |
| **Effect** | Free-form category label. Used for grouping plugins in both the Installed and Browse lists. Conventional values: `System`, `Network`, `Logs`, `Docker`, `Status Bar`, `Custom`. |

## Scheduling

### `default_interval`

| | |
|---|---|
| **Type** | integer (seconds) |
| **Default** | `30` |
| **Effect** | How often the scheduler calls your `collect()` callback. Users can override per-plugin in the Plugin Manager, but not below `min_interval`. |

### `min_interval`

| | |
|---|---|
| **Type** | integer (seconds) |
| **Default** | `5` |
| **Effect** | Floor on the polling interval. The Plugin Manager won't let the user dial the interval below this — useful when going below would either be too noisy or hit the host too hard. |

### `streaming`

| | |
|---|---|
| **Type** | boolean |
| **Default** | `false` |
| **Effect** | If true, the plugin runs in [streaming mode](../getting-started/lifecycle.md#streaming-mode): `collect()` is called once and returns a command; `transform(line, cfg)` then runs per output line. Mutually exclusive with the per-tick polling model. |

### `streaming_idle_seconds`

| | |
|---|---|
| **Type** | integer (seconds) |
| **Default** | `30` |
| **Effect** | Used only when `streaming = true`. If no output arrives for this many seconds, the engine closes and reopens the channel. |

## Data & persistence

### `data_type`

| | |
|---|---|
| **Type** | string |
| **Default** | empty (treated as generic; nothing is stored) |
| **Values** | `"snapshot"`, `"timeseries"`, `"log"`, `"table"` |
| **Effect** | Drives how `transform()`'s return value is stored and what query methods are available on `store` in `render()`. See [the lifecycle data-types table](../getting-started/lifecycle.md#data-types). |

### `retention`

| | |
|---|---|
| **Type** | string (duration) |
| **Default** | `"24h"` |
| **Format** | `<number><unit>` where unit is `h` / `d` / `w` (e.g., `"6h"`, `"7d"`, `"2w"`) |
| **Effect** | Tells the data store how long to retain historical samples / log entries. Only meaningful for `data_type = "timeseries"` and `"log"`. |

## UI & status bar

### `statusbar`

| | |
|---|---|
| **Type** | boolean |
| **Default** | `false` |
| **Effect** | If true, the plugin contributes a per-pane status-bar segment in addition to (or instead of) its full panel. The plugin's `render()` is still used for the panel; the status-bar widget is rendered from `store` data via the runtime. |

### `statusbar_order`

| | |
|---|---|
| **Type** | integer |
| **Default** | `0` |
| **Effect** | Sort order among status-bar plugins. Lower values appear first (left-to-right). |

### `default_disabled`

| | |
|---|---|
| **Type** | boolean |
| **Default** | `false` |
| **Effect** | On first install, leave the plugin disabled by default. The user must explicitly enable it from the Plugin Manager. Useful for plugins that poll aggressively, add SSH chatter, or are demos that not everyone will want. The user's enable/disable choice persists across launches — `default_disabled` only applies on first install. |

## Compatibility

### `cleat_min_version`

| | |
|---|---|
| **Type** | string (`MAJOR.MINOR.PATCH` semver) |
| **Default** | empty (no constraint) |
| **Effect** | Minimum cleat version required to load the plugin. Plugins declaring a version newer than the running cleat are surfaced in the Plugin Manager as incompatible (amber dot, Install button disabled). Set this only when your plugin actually depends on a feature added in a specific cleat release. |

### `api_version`

| | |
|---|---|
| **Type** | string |
| **Default** | empty (treated as the v1 baseline) |
| **Values** | currently `"1"` is the only accepted value |
| **Effect** | Opaque token gating the plugin against backwards-incompatible changes to the API surface. Will get new tokens (`"2"`, etc.) when cleat introduces breaking changes to the `render()` signature, `ctx:*` methods, etc. Set only when targeting a non-baseline version. |

## Settings + permissions

These two fields have their own pages because they're structured
arrays rather than scalar values:

- [`settings = { ... }`](settings.md) — user-configurable per-plugin
  options shown in Plugin Manager
- [`permissions = { ... }`](permissions.md) — opt-in capabilities
  the plugin needs (`cleat:notify` requires `"notifications"`)

## Example

A timeseries plugin with full metadata:

```lua
plugin = {
    id = "cpu-memory",
    name = "CPU & Memory",
    description = "CPU and memory usage monitoring",
    version = "1.0.1",
    author = "Cleat",
    icon = "",
    category = "System",
    default_interval = 15,
    min_interval = 10,
    data_type = "timeseries",
    retention = "24h",
    settings = {
        { key = "warn_threshold", label = "Warning Threshold (%)", type = "number", default = "70" },
        { key = "crit_threshold", label = "Critical Threshold (%)", type = "number", default = "90" },
    },
}
```
