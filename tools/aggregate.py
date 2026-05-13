#!/usr/bin/env python3
"""Aggregate every plugins/*/plugin.json into a single index.json document.

Prints the result to stdout. The publish workflow redirects stdout into
the Pages artifact:

    python tools/aggregate.py > _site/index.json

The output shape matches what the cleat client expects (see
docs/marketplace-index-schema.md in the cleat repo and SCHEMA.md in
this repo for per-entry fields).

Does not validate — call `validate.py` first for that. This script
assumes its input is already known-good.
"""
from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    plugins_dir = root / "plugins"

    entries: list[dict] = []
    if plugins_dir.is_dir():
        for path in sorted(plugins_dir.glob("*/plugin.json")):
            with path.open() as f:
                entries.append(json.load(f))

    doc = {
        "schema_version": 1,
        "updated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "plugins": entries,
    }
    json.dump(doc, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
