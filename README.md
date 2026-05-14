# cleat-plugins

Official registry of community plugins for [cleat](https://github.com/zimventures/cleat).

Each merged entry appears in the **Browse Marketplace** tab inside cleat's Plugin
Manager. End users install plugins from this registry with one click — no need
to hunt down URLs or hashes manually.

> **New here?** The full plugin-authoring documentation — quickstart, lifecycle,
> Lua API reference, submission flow — lives at
> **<https://zimventures.github.io/cleat-plugins/>**.

## What this repo contains

```
plugins/
└── <plugin-id>/
    ├── plugin.lua     # the plugin source
    └── plugin.json    # author-facing metadata manifest
```

Authors submit source files. CI does the packaging: on every merge to `main`,
the publish workflow walks each `plugins/<id>/`, zips it, computes the sha256,
aggregates the result into a single `index.json`, and deploys both the zips and
the index to GitHub Pages:

```
https://zimventures.github.io/cleat-plugins/index.json        ← the index
https://zimventures.github.io/cleat-plugins/zips/<id>-vX.Y.Z.zip  ← built zips
```

cleat fetches the index URL (configurable via `plugins.marketplace.index_url`)
and downloads each plugin's zip on install. Verifies the sha256 matches the
index entry before unpacking.

## Submitting a plugin

Open a PR adding `plugins/<your-id>/plugin.lua` + `plugins/<your-id>/plugin.json`.
CI validates the entry — schema check, id matches the directory and the .lua
source, id uniqueness, version matches between the manifest and the .lua,
etc. A maintainer reviews + merges; the publish workflow rebuilds zips and
republishes the index automatically.

See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for the full walkthrough and
[`docs/SCHEMA.md`](docs/SCHEMA.md) for the manifest reference.

## Trust model

A plugin's presence in this registry represents a maintainer review.
That review is the trust signal — there is no separate "verified" flag
on individual entries.

The registry's CI is the only thing that produces published zips:
on every merge to `main`, the publish workflow zips each
`plugins/<id>/` directory, computes its sha256, and writes both the
zip and the resulting hash into the public `index.json`. Authors
don't host or hash anything — the `sha256` in the index is by
construction the hash of the exact bytes that were reviewed at merge
time.

Cleat's client verifies that hash on every install: if the published
bytes ever change without a corresponding new merge (which would
require a CI / Pages compromise), users get an explicit error
instead of silently installing tampered code.

## Local development

```bash
# Lint every entry in plugins/
python tools/validate.py

# Build the zips + index.json the same way CI does (writes to _site/)
python tools/build.py --out _site
```

Both scripts need only Python 3.9+ (no third-party packages).

## License

Manifests in this repository are released under the MIT License (see
[`LICENSE`](LICENSE)). Each plugin's *code* is governed by the license its
author publishes alongside the plugin .zip — read the plugin's homepage or
the archive itself before trusting third-party plugins on your servers.
