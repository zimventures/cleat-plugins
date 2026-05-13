# `plugin.json` schema

Each plugin gets its own directory under `plugins/` containing a single
`plugin.json`. The schema mirrors the per-entry shape that cleat ultimately
sees in the aggregated `index.json` — there's no separate "registry-side
format". One manifest in, one entry out.

## Required vs optional fields

| Field               | Type    | Required | Notes                                                                                              |
|---------------------|---------|----------|----------------------------------------------------------------------------------------------------|
| `id`                | string  | yes      | Plugin id. Must match the directory name (`plugins/<id>/plugin.json` → this `id`). `[A-Za-z0-9_-]`, must start with alphanumeric, ≤64 chars. Globally unique across the registry. |
| `name`              | string  | yes      | Human-readable name shown in cleat's Browse list.                                                  |
| `description`       | string  | yes      | One sentence. The Browse list truncates long descriptions in the row preview.                      |
| `author`            | string  | yes      | Author handle / name as you want it shown.                                                         |
| `category`          | string  | yes      | Free-form category label. Used for grouping in the Browse list. Conventional values: `System`, `Network`, `Logs`, `Docker`, `Status Bar`, `Custom`. |
| `version`           | string  | yes      | Strict `MAJOR.MINOR.PATCH` semver. Must match the `version` declared inside the .zip's `plugin.lua`. |
| `cleat_min_version` | string  | no       | Minimum cleat version required to run this plugin. Same compat gate as cleat issue #103. Omit if your plugin runs on the v0.1.0 baseline. |
| `api_version`       | string  | no       | Plugin host-API token (see cleat issue #103). Currently `"1"` is the only valid value. Omit when targeting the v1 baseline. |
| `source_url`        | string  | yes      | HTTPS URL pointing at your plugin `.zip`. Any host with a valid CA-rooted certificate works — GitHub Releases, S3, your own site, etc. |
| `sha256`            | string  | yes      | 64-char lowercase hex sha256 of the `.zip` at `source_url`. CI **downloads the URL and verifies** this matches on every PR. |
| `homepage`          | string  | no       | URL the user can click to read about the plugin (typically the source repo).                        |

## Example

```json
{
  "id": "process-list",
  "name": "Process List",
  "description": "Top processes by CPU/memory with sort + filter",
  "author": "alice",
  "category": "System",
  "version": "1.2.0",
  "cleat_min_version": "0.2.0",
  "api_version": "1",
  "source_url": "https://github.com/alice/cleat-process-list/releases/download/v1.2.0/process-list.zip",
  "sha256": "abc123...64 hex chars...",
  "homepage": "https://github.com/alice/cleat-process-list"
}
```

## Validation rules (what CI checks)

1. JSON is well-formed.
2. All required fields are present and have the correct type.
3. `id` matches the parent directory name (`plugins/<id>/plugin.json`).
4. `id` is filesystem-safe (`[A-Za-z0-9_-]+`, starts with alphanumeric, ≤64 chars).
5. `version`, and `cleat_min_version` if present, match strict `MAJOR.MINOR.PATCH`.
6. `source_url` starts with `https://`.
7. `sha256` is 64 lowercase hex chars.
8. The bytes at `source_url` (HEAD-then-GET, with normal redirects allowed but pinned to HTTPS) hash to the declared `sha256`.
9. `id` is unique across all entries in the registry.

A PR that fails any check gets a red ✗ on the validate workflow. Fix the
manifest (or your release asset), push again, and the run reruns automatically.

## Trust model

The registry vouches for the *bytes that hash to* `sha256` at the moment
the PR was merged. If you later replace your release asset with different
bytes (intentional or not), cleat's pre-install hash check will fail and
the install is refused — the user sees an explicit "sha256 doesn't match"
error. To publish a new version, open a new PR bumping `version`,
`source_url`, and `sha256`.

## Updates

Plugin updates are just a follow-up PR to your own `plugins/<id>/plugin.json`
bumping `version`, `source_url`, and `sha256`. Same validation, same
review. Once merged and the index republishes, cleat clients with the
older version installed will see an Update prompt the next time their
background update checker runs.
