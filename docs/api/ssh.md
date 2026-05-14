# Host API (`ssh:*`)

The `ssh` argument passed to `collect(ssh, cfg)` exposes everything
your plugin can do against the connected host. All methods are
network-blocking and only available inside `collect()`.

## `ssh:exec`

Run a command on the remote host and return its stdout.

```lua
local out, err = ssh:exec(command [, timeout_ms])
```

**Arguments**

- `command` (string, required) — shell command to execute
- `timeout_ms` (integer, optional, default `10000`) — millisecond
  ceiling on the call

**Returns**

- on success: the command's stdout as a string
- on failure: `nil, error_string`
- on non-zero exit with output: `output_string, error_string` (both
  values — useful for commands like `grep` that exit 1 on no match)

**Example**

```lua
local uname = ssh:exec("uname -a")
if not uname then return "" end
return uname
```

**Notes**

- Blocks the scheduler thread until completion or timeout
- Combine multiple `ssh:exec` calls in one `collect()` if you can —
  each call has SSH channel overhead

---

## `ssh:os`

Get the remote OS name.

```lua
local name = ssh:os()
```

**Returns** — the string returned by `uname -s` (`"Linux"`,
`"Darwin"`, etc.), or `"unknown"` if the probe fails.

Cached after the first call for the lifetime of the plugin sandbox.

**Example**

```lua
local cmd = ssh:os() == "Darwin" and "sysctl -n hw.ncpu" or "nproc"
local n = ssh:exec(cmd)
```

---

## `ssh:cpu_count`

Get the remote CPU count.

```lua
local n = ssh:cpu_count()
```

**Returns** — integer ≥ 1. Tries `nproc` (Linux), then
`sysctl -n hw.ncpu` (macOS); falls back to `1` if both fail.

Cached after first call.

---

## `ssh:hostname`

Get the connection's display hostname from cleat's profile (not a
runtime `hostname` shell call).

```lua
local host = ssh:hostname()
```

**Returns** — the host string as stored in cleat's connection
profile. Read-only; never network-blocks.

---

## `ssh:meta`

Get the connection's metadata table.

```lua
local m = ssh:meta()
```

**Returns** — a table:

| Field | Type | Notes |
|---|---|---|
| `hostname` | string | from the connection profile |
| `port` | integer | SSH port |
| `username` | string | login username |
| `auth_method` | string | `"password"`, `"key"`, etc. |
| `connection_id` | integer | unique numeric id of this connection profile |
| `profile_name` | string | user-chosen connection name |
| `jump_host` | string \| nil | raw `"user@host:port"` if a custom jump host is set |
| `jump_host_id` | integer \| nil | profile id if the jump host is a saved profile |

`jump_host` and `jump_host_id` are mutually-exclusive-but-not-both-
nil iff a jump host is configured. Sensitive fields (key paths,
credentials) are deliberately omitted.

**Example**

```lua
local m = ssh:meta()
return string.format("%s (%s@%s:%d)", m.profile_name, m.username, m.hostname, m.port)
```

---

## `ssh:ping`

Measure SSH round-trip latency.

```lua
local ms = ssh:ping()
```

**Returns** — round-trip in milliseconds as a number. Returns `-1`
on failure.

Runs `echo pong` on the remote host with a 5-second timeout and
measures elapsed time client-side. Does *not* include the SSH
handshake (which has already happened — the channel is reused).

---

## `ssh:read_file`

Read a remote file's contents.

```lua
local body, err = ssh:read_file(path [, opts])
```

**Arguments**

- `path` (string, required) — absolute or shell-resolved path
- `opts` (table, optional)
    - `max_bytes` (integer, default `1048576` = 1 MiB; hard cap
      `16777216` = 16 MiB) — refuse to read more than this many
      bytes; on overflow, returns `nil, "file exceeds max_bytes (...)"`

**Returns** — `body_string` on success; `nil, error_string` on
failure (not found, unreadable, exceeds limit, transport down).

**Example**

```lua
local cgroup, err = ssh:read_file("/proc/self/cgroup", { max_bytes = 4096 })
if not cgroup then
    return ""
end
```

**Notes**

- Implementation: `head -c (max_bytes + 1)` on the remote — reads
  one byte past the cap so we can distinguish "fits" from "truncated"
- 30-second timeout
- Path is shell-escaped — spaces and special chars are safe

---

## `ssh:stat`

Get filesystem metadata for a remote path.

```lua
local info, err = ssh:stat(path)
```

**Returns** — table on success; `nil, error_string` on failure:

| Field | Type | Notes |
|---|---|---|
| `size` | integer | file size in bytes |
| `modified` | integer | mtime as Unix epoch seconds |
| `permissions` | string | octal mode string (`"0644"`) |
| `owner` | string | username |
| `group` | string | group name |

**Example**

```lua
local info = ssh:stat("/var/log/auth.log")
if info and info.size > 100 * 1024 * 1024 then
    return "log too large; refusing to read"
end
```

Tries GNU `stat -c` first, falls back to BSD `stat -f` for macOS.
5-second timeout.

---

## `ssh:env`

Read a remote environment variable.

```lua
local val, err = ssh:env(name)
```

**Arguments**

- `name` (string, required) — must match `[A-Za-z_][A-Za-z0-9_]*`;
  invalid names return `nil, "invalid env var name..."`

**Returns**

- variable *is set* (including to empty): the value as a string
- variable *is unset*: `nil` (no error)
- transport failed: `nil, error_string`

The implementation uses `printf '%s\n%s' "${NAME+x}" "${NAME-}"` to
distinguish "unset" from "set to empty" — that nuance matters for
variables like `DEBUG=` that toggle behavior by presence rather
than value.

**Example**

```lua
local docker_host = ssh:env("DOCKER_HOST")
if docker_host then
    -- DOCKER_HOST is set (possibly to empty)
end
```
