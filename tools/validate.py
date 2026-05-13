#!/usr/bin/env python3
"""Validate every plugins/<id>/ entry in the registry.

Exits 0 if all entries pass, 1 otherwise. Prints one line per problem
found, prefixed with the offending path so CI annotations point at the
right file.

Checks per entry:
  1. plugin.json is well-formed JSON.
  2. All required manifest fields are present with correct types.
  3. `id` matches the parent directory name.
  4. `id` is filesystem-safe: [A-Za-z0-9_-]+, starts with alnum, <=64 chars.
  5. `version` and `cleat_min_version` (if present) match MAJOR.MINOR.PATCH.
  6. plugin.lua exists in the entry directory.
  7. The `id` declared inside plugin.lua matches the manifest's `id`.
  8. The `version` declared inside plugin.lua matches the manifest's `version`.

Cross-cutting:
  9. `id` is globally unique across all entries.

NOTE: this script does NOT need to download anything — CI builds the
zips and computes their sha256 hashes itself (see tools/build.py).
Authors don't supply `source_url` or `sha256` in `plugin.json`; those
are CI-generated fields in the published `index.json`.

Run locally with: `python tools/validate.py`
Requires only Python 3.9+ (no external packages).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REQUIRED_MANIFEST_FIELDS = {
    "id": str,
    "name": str,
    "description": str,
    "author": str,
    "category": str,
    "version": str,
}
OPTIONAL_MANIFEST_FIELDS = {
    "cleat_min_version": str,
    "api_version": str,
    "homepage": str,
}

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")

# Lua-string match: capture the value of `id = "X"` / `version = "X"` from
# the plugin's metadata table. We're not running Lua, just doing a simple
# field-by-field scan. Matches both single and double quotes; rejects the
# long-bracket form (no plugin we ship uses it for these fields).
LUA_FIELD_RE = re.compile(r'(\w+)\s*=\s*["\']([^"\']*)["\']')


def fail(path: Path, msg: str, errors: list[str]) -> None:
    errors.append(f"{path}: {msg}")


def parse_lua_metadata(lua_path: Path) -> dict[str, str]:
    """Extract id/version/etc. from a plugin.lua. Best-effort string parser
    — sufficient for the manifest-cross-check we do here. Returns a dict of
    the first occurrences of each scanned field."""
    try:
        text = lua_path.read_text(encoding="utf-8")
    except OSError:
        return {}
    # Only look at the first metadata block — stop at the closing `}` so
    # we don't pick up id assignments elsewhere in the file.
    end = text.find("}", text.find("plugin"))
    head = text if end < 0 else text[:end]
    result: dict[str, str] = {}
    for match in LUA_FIELD_RE.finditer(head):
        key = match.group(1)
        if key in {"id", "name", "version", "description", "author", "category"} and key not in result:
            result[key] = match.group(2)
    return result


def check_entry(entry_dir: Path, errors: list[str]) -> dict | None:
    manifest = entry_dir / "plugin.json"
    lua = entry_dir / "plugin.lua"

    if not manifest.is_file():
        fail(entry_dir, "missing plugin.json", errors)
        return None
    if not lua.is_file():
        fail(entry_dir, "missing plugin.lua", errors)
        return None

    try:
        with manifest.open() as f:
            doc = json.load(f)
    except json.JSONDecodeError as e:
        fail(manifest, f"invalid JSON: {e}", errors)
        return None

    if not isinstance(doc, dict):
        fail(manifest, "root must be a JSON object", errors)
        return None

    # Required fields + types.
    for field, ftype in REQUIRED_MANIFEST_FIELDS.items():
        if field not in doc:
            fail(manifest, f"missing required field `{field}`", errors)
        elif not isinstance(doc[field], ftype):
            fail(manifest, f"`{field}` must be {ftype.__name__}, got {type(doc[field]).__name__}", errors)

    # Optional fields: type-checked if present.
    for field, ftype in OPTIONAL_MANIFEST_FIELDS.items():
        if field in doc and not isinstance(doc[field], ftype):
            fail(manifest, f"`{field}` must be {ftype.__name__}, got {type(doc[field]).__name__}", errors)

    # Reject any author-provided source_url/sha256 — those are CI-generated
    # in this registry and accepting author input would muddy the trust
    # model. Flag explicitly so a copy-paste from older docs gets caught.
    for forbidden in ("source_url", "sha256"):
        if forbidden in doc:
            fail(manifest,
                 f"`{forbidden}` is CI-generated and must not appear in plugin.json — remove it",
                 errors)

    pid = doc.get("id", "")
    parent_name = entry_dir.name
    if pid and pid != parent_name:
        fail(manifest, f"id `{pid}` does not match directory name `{parent_name}`", errors)
    if pid and not ID_RE.match(pid):
        fail(manifest,
             f"id `{pid}` is not filesystem-safe (allowed: [A-Za-z0-9_-]+, start alnum, <=64 chars)",
             errors)

    version = doc.get("version", "")
    if version and not SEMVER_RE.match(version):
        fail(manifest, f"version `{version}` is not strict MAJOR.MINOR.PATCH semver", errors)

    cmv = doc.get("cleat_min_version", "")
    if cmv and not SEMVER_RE.match(cmv):
        fail(manifest, f"cleat_min_version `{cmv}` is not strict MAJOR.MINOR.PATCH semver", errors)

    # Cross-check plugin.lua's declared metadata against the manifest.
    lua_meta = parse_lua_metadata(lua)
    lua_id = lua_meta.get("id", "")
    if lua_id and pid and lua_id != pid:
        fail(lua, f"plugin.lua declares id `{lua_id}` but the manifest says `{pid}`", errors)
    lua_version = lua_meta.get("version", "")
    if lua_version and version and lua_version != version:
        fail(lua,
             f"plugin.lua declares version `{lua_version}` but the manifest says `{version}` — bump both",
             errors)

    return doc


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    plugins_dir = root / "plugins"
    if not plugins_dir.is_dir():
        print(f"WARN: no plugins/ directory at {plugins_dir}; nothing to validate.")
        return 0

    entry_dirs = sorted([p for p in plugins_dir.iterdir() if p.is_dir()])
    if not entry_dirs:
        print("WARN: no plugin entries found.")
        return 0

    errors: list[str] = []
    seen_ids: dict[str, Path] = {}

    for entry_dir in entry_dirs:
        print(f"validating {entry_dir.relative_to(root)} ...")
        doc = check_entry(entry_dir, errors)
        if doc is None:
            continue
        pid = doc.get("id", "")
        if pid:
            if pid in seen_ids:
                fail(entry_dir,
                     f"duplicate id `{pid}` (also in {seen_ids[pid].relative_to(root)})",
                     errors)
            else:
                seen_ids[pid] = entry_dir

    if errors:
        print("")
        print(f"FAIL: {len(errors)} validation error(s):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("")
    print(f"OK: {len(entry_dirs)} entry/entries valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
