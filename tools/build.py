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


def build_one_zip(entry_dir: Path, zips_out: Path, kind: str = "plugin") -> tuple[Path, str, str]:
    """Zip up `entry_dir`'s contents into `zips_out/<id>-vX.Y.Z.zip`,
    return (zip_path, sha256_hex, archive_inner_top_dir). Cleat expects
    the archive to wrap everything in a single top-level directory whose
    name is the entry id — we always honor that here regardless of
    what `entry_dir.name` happens to be (kept in lockstep by the validator
    earlier in CI).

    `kind` selects the manifest + script filenames ("plugin" or
    "screensaver"). Both follow identical packaging rules; only the names
    differ."""
    manifest_path = entry_dir / f"{kind}.json"
    with manifest_path.open() as f:
        manifest = json.load(f)
    entry_id = manifest["id"]
    version = manifest["version"]

    zip_name = f"{entry_id}-v{version}.zip"
    zip_path = zips_out / zip_name
    top_dir = entry_id

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

    # <kind>.lua must live at the entry root, not in a subdirectory.
    # Cleat's loader expects `<id>/<kind>.lua` inside the zip; a nested
    # `<id>/subdir/<kind>.lua` would silently produce an unloadable
    # archive even though the file exists somewhere in the tree.
    lua_name = f"{kind}.lua"
    has_root_lua = any(
        f.parent == entry_dir and f.name == lua_name for f in files
    )
    if not has_root_lua:
        raise RuntimeError(f"{entry_dir}: no {lua_name} at the root of the entry")

    # ZIP_DEFLATED gives reasonable compression on Lua source. Determinism
    # is not strictly required (each entry version is intended to be
    # written once and never overwritten), but we set times to a fixed
    # epoch so repeated builds of the same source produce identical
    # zips, which makes the sha256 in index.json stable across re-runs.
    # Text-source extensions get CRLF normalized to LF before packing.
    # Belt-and-suspenders alongside the repo's .gitattributes: even if a
    # contributor's editor writes CRLF, the published zip stays
    # byte-identical across builds on different OSes.
    TEXT_EXTS = {".lua", ".md", ".json", ".txt"}

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            rel = f.relative_to(entry_dir).as_posix()
            arcname = f"{top_dir}/{rel}"
            zi = zipfile.ZipInfo(filename=arcname, date_time=(2024, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o644 << 16) | 0x20  # FILE_ATTRIBUTE_ARCHIVE
            data = f.read_bytes()
            if f.suffix.lower() in TEXT_EXTS:
                data = data.replace(b"\r\n", b"\n")
            zf.writestr(zi, data)

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
    screensavers_dir = root / "screensavers"
    out_dir = Path(args.out).resolve()
    zips_dir = out_dir / "zips"
    # Screensaver zips go in a subdirectory of zips/ so a screensaver and a
    # plugin can share an id without their archives colliding on the CDN.
    ss_zips_dir = zips_dir / "screensavers"

    # Wipe only the artifacts we own (zips/ and index.json). Leave any
    # other files in out_dir alone — the publish workflow builds the
    # mkdocs site into the same directory first, and this script's job
    # is to add the registry artifacts on top without removing them.
    if zips_dir.exists():
        shutil.rmtree(zips_dir)
    zips_dir.mkdir(parents=True, exist_ok=True)
    ss_zips_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "index.json").unlink(missing_ok=True)

    def collect(entry_root: Path, kind: str, zips_target: Path, url_prefix: str) -> list[dict]:
        """Build zips + assemble index entries for every directory under
        `entry_root`. `kind` ("plugin" / "screensaver") selects the manifest
        filename + propagates to the JSON entry's `type` field."""
        out: list[dict] = []
        if not entry_root.is_dir():
            return out
        for entry_dir in sorted(p for p in entry_root.iterdir() if p.is_dir()):
            manifest_name = f"{kind}.json"
            manifest_path = entry_dir / manifest_name
            if not manifest_path.is_file():
                # Validator should catch this; build skips it defensively.
                print(f"WARN: {entry_dir.relative_to(root)} has no {manifest_name}, skipping")
                continue
            with manifest_path.open() as f:
                manifest = json.load(f)

            zip_path, sha, _ = build_one_zip(entry_dir, zips_target, kind=kind)
            zip_url = base_url + url_prefix + zip_path.name

            # Build the index entry: author-supplied metadata + CI-derived
            # source_url + sha256 + type. Strip any forbidden fields the
            # author might have left in (defense in depth — validator already
            # rejected them).
            entry = {k: v for k, v in manifest.items() if k not in ("source_url", "sha256", "type")}
            entry["type"] = kind
            entry["source_url"] = zip_url
            entry["sha256"] = sha
            out.append(entry)

            print(f"built {zip_path.relative_to(out_dir)} (sha256 {sha[:16]}...) -> {zip_url}")
        return out

    plugin_entries = collect(plugins_dir, "plugin", zips_dir, "zips/")
    screensaver_entries = collect(screensavers_dir, "screensaver", ss_zips_dir, "zips/screensavers/")

    doc = {
        "schema_version": 1,
        "updated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "plugins": plugin_entries,
    }
    # Only emit the screensavers array when there's at least one entry. Keeps
    # the index byte-identical to the pre-screensavers format for registries
    # that haven't published any yet.
    if screensaver_entries:
        doc["screensavers"] = screensaver_entries

    index_path = out_dir / "index.json"
    with index_path.open("w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print(f"wrote {index_path.relative_to(root)} "
          f"({len(plugin_entries)} plugin(s), {len(screensaver_entries)} screensaver(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
