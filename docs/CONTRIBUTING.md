# Contributing a plugin

This walkthrough covers everything from "I have a plugin .zip" to "my plugin
is live in the registry."

## Prerequisites

- Your plugin is a cleat plugin that runs end-to-end against a real SSH
  connection. Test it locally first via Plugin Manager → **Install from
  URL...** before submitting.
- Your `.zip` is hosted somewhere with a valid HTTPS URL. GitHub Releases is
  the conventional choice but anything CA-rooted works.
- The .zip's structure matches what cleat expects: exactly one top-level
  directory containing a `plugin.lua` at its root.

## Steps

### 1. Compute the sha256 of your .zip

```bash
# macOS / Linux
shasum -a 256 my-plugin.zip

# Windows PowerShell
Get-FileHash my-plugin.zip -Algorithm SHA256
```

The lowercase hex value (64 chars) goes into your manifest's `sha256` field.

### 2. Fork this repo and create your manifest

Create a single file at `plugins/<your-plugin-id>/plugin.json`:

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "What it does, one sentence",
  "author": "your-handle",
  "category": "System",
  "version": "1.0.0",
  "source_url": "https://github.com/you/my-plugin/releases/download/v1.0.0/my-plugin.zip",
  "sha256": "abc123...",
  "homepage": "https://github.com/you/my-plugin"
}
```

The directory name *must* match the `id`. See [`SCHEMA.md`](SCHEMA.md) for
all fields and validation rules.

### 3. Validate locally (optional but recommended)

```bash
pip install requests
python tools/validate.py
```

This runs the same checks CI does — schema, sha256 verification, id
uniqueness, etc.

### 4. Open the PR

The PR template will prompt for the same checks. Push your branch, open
the PR, wait for the `validate` workflow to go green. If anything fails,
the workflow output points at the exact problem (wrong sha256, malformed
URL, id collision, etc.).

### 5. Wait for review

A maintainer reviews:
- Is this clearly a useful plugin?
- Does the description match what the code does?
- Does the author look real (not impersonating someone)?
- Does the plugin.lua inside the .zip declare the same `id` as the manifest?

On merge, the publish workflow runs, regenerates `index.json`, and deploys
to GitHub Pages. cleat clients pick up the new entry on their next index
refresh (default: every 24h, or immediately if the user clicks **Refresh
Index** in the Browse tab).

## Updating an existing plugin

Same flow — open a PR bumping `version`, `source_url`, and `sha256` in
your existing `plugins/<id>/plugin.json`. Don't change `id` (it's a stable
identity), and don't change `author` to a different person (open an issue
if you're transferring ownership).

cleat's background update checker compares the index's `version` against
what each user has installed and surfaces an Update badge automatically
once the new entry lands.

## Removing a plugin

Open a PR deleting `plugins/<id>/`. The entry disappears from the next
publish. Existing installs aren't affected (they keep working) but the
plugin no longer shows up in Browse for new users.

## What gets rejected

- `id` collision with an existing entry
- `sha256` doesn't match the bytes at `source_url`
- `source_url` is HTTP (not HTTPS), 404s, or returns a non-zip payload
- `plugin.lua` inside the archive declares a different `id` than the manifest
- Naked spam / promotional plugins with no functional value
- Plugins that obviously exfiltrate data, run arbitrary remote payloads,
  or otherwise violate user trust on the connected host

Borderline cases (educational toy plugins, demos) are case-by-case; open
an issue first if you're unsure.
