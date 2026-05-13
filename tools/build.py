#!/usr/bin/env python3
"""Build the published registry artifacts from plugins/<id>/ source trees.

For each plugin entry:
  1. Zip its directory contents with the structure cleat expects:
     `<id>/plugin.lua` (and any other files at the dir's root) wrapped
     in a single top-level directory inside the archive.
  2. Compute sha256 of the zip.
  3. Add an index.json entry with source_url + sha256 filled in.

Output goes to `_site/`:
  - `_site/zips/<id>-vX.Y.Z.zip` — the archive served at source_url
  - `_site/index.json`            — the aggregated index cleat fetches

The `publish.yml` workflow uploads `_site/` as the Pages artifact, so
both the zips and the index end up on `zimventures.github.io/cleat-plugins/`.

Usage:
    python tools/build.py [--out _site] [--base-url https://.../]

`--base-url` controls the URL prefix written into each entry's
`source_url`. Defaults to the production Pages origin.

Requires only Python 3.9+ (no external packages).
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path


DEFAULT_BASE_URL = "https://zimventures.github.io/cleat-plugins/"


def build_one_zip(entry_dir: Path, zips_out: Path) -> tuple[Path, str, str]:
    """Zip up `entry_dir`'s contents into `zips_out/<id>-vX.Y.Z.zip`,
    return (zip_path, sha256_hex, archive_inner_top_dir). Cleat expects
    the archive to wrap everything in a single top-level directory whose
    name is the plugin id — we always honor that here regardless of
    what `entry_dir.name` happens to be (kept in lockstep by the validator
    earlier in CI)."""
    manifest_path = entry_dir / "plugin.json"
    with manifest_path.open() as f:
        manifest = json.load(f)
    plugin_id = manifest["id"]
    version = manifest["version"]

    zip_name = f"{plugin_id}-v{version}.zip"
    zip_path = zips_out / zip_name
    top_dir = plugin_id

    files: list[Path] = []
    for p in sorted(entry_dir.rglob("*")):
        if p.is_dir():
            continue
        # Reject symlinks — packaging a symlink would either follow it
        # (embedding the target's bytes into the published zip, breaking
        # the "what's in the repo is what gets published" trust contract)
        # or skip it silently. Better to fail loud and force the author
        # to commit real files.
        if p.is_symlink():
            raise RuntimeError(f"{entry_dir}: symlink not allowed in published source: {p.relative_to(entry_dir)}")
        files.append(p)

    # plugin.lua must live at the entry root, not in a subdirectory.
    # Cleat's loader expects `<id>/plugin.lua` inside the zip; a nested
    # `<id>/subdir/plugin.lua` would silently produce an unloadable
    # archive even though the file exists somewhere in the tree.
    has_root_lua = any(
        f.parent == entry_dir and f.name == "plugin.lua" for f in files
    )
    if not has_root_lua:
        raise RuntimeError(f"{entry_dir}: no plugin.lua at the root of the entry")

    # ZIP_DEFLATED gives reasonable compression on Lua source. Determinism
    # is not strictly required (each entry version is intended to be
    # written once and never overwritten), but we set times to a fixed
    # epoch so repeated builds of the same source produce identical
    # zips, which makes the sha256 in index.json stable across re-runs.
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            rel = f.relative_to(entry_dir).as_posix()
            arcname = f"{top_dir}/{rel}"
            zi = zipfile.ZipInfo(filename=arcname, date_time=(2024, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o644 << 16) | 0x20  # FILE_ATTRIBUTE_ARCHIVE
            zf.writestr(zi, f.read_bytes())

    h = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    return zip_path, h, top_dir


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="_site",
                    help="Output directory (default: _site)")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL,
                    help=f"Base URL for source_url fields (default: {DEFAULT_BASE_URL})")
    args = ap.parse_args()

    base_url = args.base_url.rstrip("/") + "/"
    root = Path(__file__).resolve().parent.parent
    plugins_dir = root / "plugins"
    out_dir = Path(args.out).resolve()
    zips_dir = out_dir / "zips"

    # Wipe + recreate the output dir so we don't leak stale artifacts
    # across builds. CI starts from a clean checkout anyway, but locally
    # this matters.
    if out_dir.exists():
        shutil.rmtree(out_dir)
    zips_dir.mkdir(parents=True)

    entries: list[dict] = []
    if plugins_dir.is_dir():
        for entry_dir in sorted(p for p in plugins_dir.iterdir() if p.is_dir()):
            manifest_path = entry_dir / "plugin.json"
            if not manifest_path.is_file():
                # Validator should catch this; build skips it defensively.
                print(f"WARN: {entry_dir.relative_to(root)} has no plugin.json, skipping")
                continue
            with manifest_path.open() as f:
                manifest = json.load(f)

            zip_path, sha, _ = build_one_zip(entry_dir, zips_dir)
            zip_url = base_url + f"zips/{zip_path.name}"

            # Build the index entry: author-supplied metadata + CI-derived
            # source_url + sha256. Strip any forbidden fields the author
            # might have left in (defense in depth — validator already
            # rejected them).
            entry = {k: v for k, v in manifest.items() if k not in ("source_url", "sha256")}
            entry["source_url"] = zip_url
            entry["sha256"] = sha
            entries.append(entry)

            print(f"built {zip_path.relative_to(out_dir)} (sha256 {sha[:16]}...) -> {zip_url}")

    doc = {
        "schema_version": 1,
        "updated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "plugins": entries,
    }
    index_path = out_dir / "index.json"
    with index_path.open("w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print(f"wrote {index_path.relative_to(root)} ({len(entries)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
