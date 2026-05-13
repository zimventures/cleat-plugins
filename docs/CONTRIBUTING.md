# Contributing a plugin

This walkthrough covers everything from "I have a plugin idea" to "my
plugin is live in the registry."

## Prerequisites

- Your plugin works end-to-end against a real SSH connection. Develop
  it locally in cleat using **Create New Plugin...** in Plugin Manager,
  iterate via **Reload**, then write it up here once it's ready.
- You're submitting just source files. The registry's CI builds the
  zip, computes its sha256, and hosts it on GitHub Pages — authors do
  **not** package, hash, or host anything.

## Steps

### 1. Fork this repo and create the entry directory

Create a directory at `plugins/<your-plugin-id>/` containing:

```
plugins/my-plugin/
├── plugin.lua     # your plugin source
└── plugin.json    # the metadata manifest
```

The directory name *must* match the `id` field inside both files. See
[`SCHEMA.md`](SCHEMA.md) for the full manifest reference.

### 2. Write `plugin.json` (metadata only)

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "What it does, one sentence",
  "author": "your-handle",
  "category": "System",
  "version": "1.0.0",
  "homepage": "https://github.com/you/my-plugin"
}
```

Do **not** include `source_url` or `sha256` — CI generates those.

### 3. Validate locally (optional but quick)

```bash
python tools/validate.py
```

This runs the same lint CI does. No third-party dependencies; just
Python 3.9+.

### 4. (Optional) Preview the build

```bash
python tools/build.py --out _site --base-url https://example.com/
```

Inspect `_site/zips/<id>-vX.Y.Z.zip` and `_site/index.json` to see
exactly what CI will publish. The `--base-url` is just for the
`source_url` field in the local preview; the production publish uses
the Pages URL.

### 5. Open the PR

The PR template will prompt for the same checklist. Push your branch,
open the PR, wait for the `validate` workflow to go green. If anything
fails, the workflow output points at the exact problem (id mismatch,
malformed version, etc.).

### 6. Wait for review

A maintainer reviews:

- Is the plugin clearly useful?
- Does the description match what the code does?
- Does the author handle look real (not impersonating someone)?
- Anything obviously sketchy in the `plugin.lua` (exfil, arbitrary
  remote-payload execution, etc.)?

On merge, the `publish.yml` workflow runs:

1. Builds a zip of your `plugins/<id>/` directory
2. Computes its sha256
3. Aggregates all merged plugins into a fresh `index.json` with
   `source_url` and `sha256` filled in
4. Uploads both the zips and the index to GitHub Pages

cleat clients pick up the new entry on their next index refresh
(default: every 24h, or immediately if the user clicks **Refresh
Index** in the Browse tab).

## Updating an existing plugin

Same flow — open a PR bumping `version` in both `plugin.json` and
inside the `version =` field of `plugin.lua`. Don't change `id` (it's
stable identity), don't change `author` to a different person without
explaining why (open an issue if you're transferring ownership).

cleat's background update checker notices the version bump on its
next probe and surfaces an Update badge to users with the previous
version installed.

## Removing a plugin

Open a PR deleting `plugins/<id>/`. CI republishes the index without
that entry. Existing installs aren't affected (they keep working) but
the plugin no longer shows up in Browse for new users.

## What gets rejected

- `id` collision with an existing entry
- `id` in the manifest doesn't match the `id` inside `plugin.lua`
- `version` doesn't match between the manifest and the `plugin.lua` source
- Author tries to include `source_url` or `sha256` in `plugin.json`
- `plugin.lua` missing from the entry directory
- Naked spam / promotional plugins with no functional value
- Plugins that obviously exfiltrate data, run arbitrary remote
  payloads, or otherwise violate user trust on the connected host

Borderline cases (educational toys, demos, very specific niche
plugins) are case-by-case — open an issue first if you're unsure.
