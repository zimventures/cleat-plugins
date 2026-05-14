# Shared state (`cleat.kv:*`)

`cleat.kv` is a per-connection key-value store. Plugins running on
the same SSH connection can read each other's values via a namespaced
lookup syntax, enabling cross-plugin coordination without piping
through cleat's host or building your own IPC.

State persists across plugin reloads and survives reconnects (but is
scoped to the connection — a different SSH connection has its own
keyspace).

## `cleat.kv:set`

Write a value to your plugin's namespace.

```lua
local ok, err = cleat.kv:set(key, value)
```

**Arguments**

- `key` (string, required, no colons) — your namespace is implicit;
  don't qualify it
- `value` (any) — `nil`, boolean, number, string, or a "pure" Lua
  table (all keys sequential integers OR all keys strings; no
  mixed-key tables)

**Returns** — `true` on success; `nil, error_string` on validation
failure (empty key, contains `:`, unsupported type, value too large).

**Example**

```lua
local ok, err = cleat.kv:set("last_seen_uptime", uptime_seconds)
if not ok then
    -- log err
end
```

**Notes**

- Values are JSON-serialized internally; tables nest fine but
  functions, userdata, and threads will be rejected
- Per-value byte cap (a few KB by default; rejected with an
  explicit error)
- Colon in the key is reserved for the cross-plugin read syntax in
  `:get()` and will be rejected here

---

## `cleat.kv:get`

Read a value — yours or another plugin's.

```lua
local val = cleat.kv:get(key)
```

**Arguments**

- `key` (string, required) — either:
    - `"yourkey"` — looks in your own plugin's namespace
    - `"other-plugin-id:somekey"` — reads the named key from
      another plugin's namespace (cross-plugin read)

**Returns** — the deserialized value, or `nil` if the key isn't set
(absence is silent; not an error).

**Example: ambient cross-plugin read**

```lua
-- plugin-a writes:
cleat.kv:set("primary_iface", "eth0")

-- plugin-b reads:
local iface = cleat.kv:get("plugin-a:primary_iface")
```

**Notes**

- Cross-plugin reads don't require any opt-in from the writing
  plugin — `cleat.kv` is an ambient-read surface designed for
  cooperative plugins to share state
- Reads of non-existent keys return `nil`, not an error

---

## `cleat.kv:delete`

Remove a key from your own namespace.

```lua
local ok, err = cleat.kv:delete(key)
```

**Arguments**

- `key` (string, required, no colons)

**Returns** — `true` if the key existed and was removed, `false` if
it didn't exist. `nil, error_string` on validation failure (empty
key, contains `:`).

**Notes** — Cross-plugin *deletes* are not supported (unlike reads,
where the `:` syntax is allowed). Delete is always scoped to the
caller's plugin.

---

## `cleat.kv:list`

List all keys in your own namespace.

```lua
local keys = cleat.kv:list()
```

**Returns** — Lua array of strings, alphabetically sorted. Empty
table if no keys exist (or if the data store is unavailable).

**Example: cleanup**

```lua
-- Wipe all of this plugin's state.
for _, k in ipairs(cleat.kv:list()) do
    cleat.kv:delete(k)
end
```

Doesn't list other plugins' keys — you can't enumerate the global
keyspace.

## Use cases

- **Cross-tick state** within one plugin: cache last-seen values so
  `transform()` can compute deltas without re-reading them every tick
- **Cross-plugin coordination**: a `network-discovery` plugin
  publishes the primary interface; downstream `traffic`, `latency`,
  etc. plugins consume it
- **Lightweight history**: store the last N samples as a small array
  for plugins where the full data store is overkill
