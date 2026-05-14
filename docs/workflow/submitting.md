# Submitting to the registry

When your plugin's ready to share, the path is a PR to
[zimventures/cleat-plugins](https://github.com/zimventures/cleat-plugins).

The high-level shape is in [`CONTRIBUTING.md`](../CONTRIBUTING.md);
this page focuses on what your *plugin* needs to look like at PR
time, common CI failures, and version-bump etiquette for updates.

## Repository layout

Your plugin lives in its own directory:

```
plugins/
└── <your-plugin-id>/
    ├── plugin.lua     # the source you authored
    └── plugin.json    # the registry manifest (metadata only)
```

CI walks this directory on every merge, builds a zip, computes the
sha256, and aggregates everything into the registry's published
`index.json`.

## Step-by-step

1. **Fork** `cleat-plugins`
2. **Create** `plugins/<your-id>/`
3. **Copy** your `plugin.lua` into it
4. **Write** `plugin.json` (metadata only — no `source_url` /
   `sha256`)
5. **Run** `python tools/validate.py` locally
6. **Open a PR** — CI runs the same validator, plus a build dry-run

See [`SCHEMA.md`](../SCHEMA.md) for the full `plugin.json` field
catalog. The minimum:

```json
{
  "id": "your-plugin-id",
  "name": "Your Plugin Name",
  "description": "One sentence about what it does",
  "author": "your-handle",
  "category": "System",
  "version": "1.0.0",
  "homepage": "https://github.com/you/your-plugin-source"
}
```

**Critical**: the `id` and `version` in `plugin.json` must **match**
the values inside `plugin.lua`'s `plugin = { ... }` table. CI
cross-checks both.

## What CI validates

| Check | What goes wrong |
|---|---|
| `plugin.json` is well-formed JSON | Trailing commas, wrong quote style — the usual suspects |
| Required fields present | Missing `id`, `name`, `version`, `description`, `author`, `category` |
| `id` matches dirname | If your dir is `plugins/foo` but `plugin.json` says `"id": "bar"`, fails |
| `id` is filesystem-safe | Lowercase alphanumeric + hyphens + underscores; ≤ 64 chars; starts alphanumeric |
| `version` is strict semver | `1.0.0` good; `v1.0.0`, `1.0`, `1.0.0-beta` bad |
| `plugin.lua` exists at entry root | Not under a subdirectory |
| `id` inside `plugin.lua` matches | The Lua `plugin.id` field equals the manifest `id` |
| `version` inside `plugin.lua` matches | Same idea |
| `id` is globally unique in the registry | No conflicts with other published plugins |
| No `source_url` or `sha256` in `plugin.json` | These are CI-generated; submitter must not include them |

Run `python tools/validate.py` locally to catch all of these before
opening the PR. Output is annotated per-file so you can see exactly
what went wrong.

## Publishing flow

Once a maintainer merges:

1. The publish workflow walks `plugins/<id>/` for every plugin
2. Each directory becomes a `_site/zips/<id>-vX.Y.Z.zip`
3. Cleat-plugins computes the sha256 and adds the entry to
   `_site/index.json`
4. The whole `_site/` directory is deployed to GitHub Pages
5. Cleat clients fetch the updated `index.json` on their next
   refresh (the default cache TTL is 24h, but users can hit
   **Refresh Index** in Browse Marketplace for immediate pickup)

End-to-end, expect ~1 minute from merge to "your plugin shows up
in Browse Marketplace".

## Versioning

Cleat's update checker compares the registry's `version` against
the user's installed `version` semantically (strict-newer-semver).
That means:

- **Bug fix or polish** (no API changes): bump patch (e.g.
  `1.0.0` → `1.0.1`)
- **New feature, backwards-compatible** (new settings field, new
  optional behavior): bump minor (`1.0.1` → `1.1.0`)
- **Breaking change** (removed/renamed settings, changed data
  shape): bump major (`1.1.0` → `2.0.0`)

Bumping the version is what makes the fix visible to existing
installs — cleat's update checker only flags strictly-newer-semver,
so a same-version republish (e.g. you replace the bytes without
bumping) won't trigger an Update prompt. That's intentional: a
plugin that quietly changes behavior under the user without a
version bump is a worse experience than just shipping the change as
an explicit update.

## Updates

Update PRs follow the same flow:

1. Bump the `version` in **both** `plugin.json` and the `plugin = {
   ... }` table in `plugin.lua` (matching exactly)
2. Make the code changes
3. Open a PR — same author, ideally same handle as the original
   submission. If you're transferring ownership, mention it in the
   PR body

CI re-validates everything; the maintainer reviews the diff and
merges.

## Removing a plugin

Open a PR deleting `plugins/<your-id>/`. CI rebuilds the index
without the entry. Existing installs aren't affected (they keep
working) but the plugin no longer shows up in Browse for new
users.

## Common rejections

What gets bounced back as "please revise":

- **`id` collision** with an existing entry. Pick a different `id`.
- **`id` in manifest doesn't match `id` in plugin.lua**. Make them
  match.
- **`version` doesn't match** between manifest and plugin.lua source.
- **Author includes `source_url` or `sha256`**. Remove them; CI
  generates them.
- **`plugin.lua` missing**, or under a subdirectory rather than
  `plugins/<id>/plugin.lua`.
- **Naked spam / promo plugins** with no functional value.
- **Plugins that exfiltrate data** or otherwise violate user trust
  on the connected host. Borderline cases: open an issue first.

Borderline-case plugins (educational toys, demos, niche tooling) are
case-by-case. Open an issue describing the plugin before submitting
if you're unsure whether it fits.
