# cleat-plugins

Official registry of community plugins for [cleat](https://github.com/zimventures/cleat).

Each merged entry appears in the **Browse Marketplace** tab inside cleat's Plugin
Manager. End users install plugins from this registry with one click — no need
to hunt down URLs or hashes manually.

## What this repo contains

```
plugins/
└── <plugin-id>/
    └── plugin.json    # one manifest per plugin
```

On every merge to `main`, CI walks every `plugins/<id>/plugin.json`, validates
it, aggregates them into a single `index.json`, and deploys to GitHub Pages at:

```
https://zimventures.github.io/cleat-plugins/index.json
```

cleat fetches that URL (configurable via `plugins.marketplace.index_url`).

## Submitting a plugin

Open a PR adding `plugins/<your-id>/plugin.json`. CI will validate the entry
on the PR — schema check, sha256 verification against the bytes hosted at
`source_url`, id uniqueness, etc. A maintainer reviews + merges; the index
is republished automatically.

See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for the full walkthrough and
[`docs/SCHEMA.md`](docs/SCHEMA.md) for the manifest reference.

## Trust model

A plugin's presence in this registry represents a maintainer review.
That review is the trust signal — there is no separate "verified" flag
on individual entries.

The `sha256` field is what makes the review durable: once merged, the
registry has committed to one specific archive at `source_url`. If the
author's hosting later serves different bytes (intentional or otherwise),
cleat's pre-install hash check fails and the install is refused. The
review covers *the bytes that existed at merge time*, not whatever
`source_url` happens to serve later.

## Local development

```bash
# Validate every plugin manifest in the tree
python tools/validate.py

# Build the aggregated index.json the same way CI does
python tools/aggregate.py > index.json
```

Validation requires Python 3.9+ and the `requests` package for the
sha256-of-downloaded-bytes check.

## License

Manifests in this repository are released under the MIT License (see
[`LICENSE`](LICENSE)). Each plugin's *code* is governed by the license its
author publishes alongside the plugin .zip — read the plugin's homepage or
the archive itself before trusting third-party plugins on your servers.
