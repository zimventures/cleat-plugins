#!/usr/bin/env python3
"""Validate every plugins/*/plugin.json against the registry schema.

Exits 0 if all manifests pass, 1 otherwise. Prints one line per problem
found, prefixed with the manifest path so CI annotations point at the
right file.

Checks:
  1. JSON is well-formed.
  2. All required fields present with correct types.
  3. `id` matches the parent directory name.
  4. `id` is filesystem-safe: [A-Za-z0-9_-]+, starts with alphanumeric, <=64 chars.
  5. `version` and `cleat_min_version` (if present) match MAJOR.MINOR.PATCH.
  6. `source_url` is https://.
  7. `sha256` is 64 lowercase hex chars.
  8. Downloading `source_url` produces bytes that hash to `sha256`.
  9. `id` is globally unique across all manifests.

Run locally with: `python tools/validate.py`
Requires Python 3.9+ and the `requests` package.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: this script requires the `requests` package. Install with: pip install requests",
          file=sys.stderr)
    sys.exit(2)


REQUIRED_FIELDS = {
    "id": str,
    "name": str,
    "description": str,
    "author": str,
    "category": str,
    "version": str,
    "source_url": str,
    "sha256": str,
}
OPTIONAL_FIELDS = {
    "cleat_min_version": str,
    "api_version": str,
    "homepage": str,
}

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

# Max bytes we'll download for the hash check — matches the cleat client
# ceiling and keeps a malicious manifest from hosing CI runners.
MAX_BYTES = 5 * 1024 * 1024  # 5 MiB


def fail(path: Path, msg: str, errors: list[str]) -> None:
    errors.append(f"{path}: {msg}")


def check_manifest(path: Path, errors: list[str]) -> dict | None:
    try:
        with path.open() as f:
            doc = json.load(f)
    except json.JSONDecodeError as e:
        fail(path, f"invalid JSON: {e}", errors)
        return None

    if not isinstance(doc, dict):
        fail(path, "root must be a JSON object", errors)
        return None

    # Required fields present + correct type.
    for field, ftype in REQUIRED_FIELDS.items():
        if field not in doc:
            fail(path, f"missing required field `{field}`", errors)
            continue
        if not isinstance(doc[field], ftype):
            fail(path, f"`{field}` must be {ftype.__name__}, got {type(doc[field]).__name__}", errors)

    # Optional fields, when present, must have the right type.
    for field, ftype in OPTIONAL_FIELDS.items():
        if field in doc and not isinstance(doc[field], ftype):
            fail(path, f"`{field}` must be {ftype.__name__}, got {type(doc[field]).__name__}", errors)

    pid = doc.get("id", "")
    parent_name = path.parent.name
    if pid and pid != parent_name:
        fail(path, f"id `{pid}` does not match directory name `{parent_name}`", errors)

    if pid and not ID_RE.match(pid):
        fail(path, f"id `{pid}` is not filesystem-safe (allowed: [A-Za-z0-9_-]+, start alnum, <=64 chars)",
             errors)

    version = doc.get("version", "")
    if version and not SEMVER_RE.match(version):
        fail(path, f"version `{version}` is not strict MAJOR.MINOR.PATCH semver", errors)

    cmv = doc.get("cleat_min_version", "")
    if cmv and not SEMVER_RE.match(cmv):
        fail(path, f"cleat_min_version `{cmv}` is not strict MAJOR.MINOR.PATCH semver", errors)

    source_url = doc.get("source_url", "")
    if source_url and not source_url.lower().startswith("https://"):
        fail(path, f"source_url `{source_url}` must start with https://", errors)

    sha = doc.get("sha256", "")
    if sha and not SHA256_RE.match(sha):
        fail(path, f"sha256 `{sha}` is not 64 lowercase hex chars", errors)

    return doc


def verify_download_hash(path: Path, doc: dict, errors: list[str]) -> None:
    source_url = doc.get("source_url", "")
    expected = doc.get("sha256", "")
    if not source_url or not expected:
        return # earlier checks already flagged this

    print(f"  downloading {source_url} ...")
    try:
        r = requests.get(source_url, allow_redirects=True, stream=True, timeout=60)
    except requests.RequestException as e:
        fail(path, f"failed to fetch source_url: {e}", errors)
        return

    if r.status_code != 200:
        fail(path, f"source_url returned HTTP {r.status_code}", errors)
        return

    h = hashlib.sha256()
    total = 0
    for chunk in r.iter_content(chunk_size=64 * 1024):
        if not chunk:
            continue
        total += len(chunk)
        if total > MAX_BYTES:
            fail(path, f"source_url body exceeds {MAX_BYTES // (1024 * 1024)} MiB limit", errors)
            r.close()
            return
        h.update(chunk)

    actual = h.hexdigest()
    if actual != expected:
        fail(path, f"sha256 mismatch — manifest says `{expected}`, downloaded bytes hash to `{actual}`",
             errors)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    plugins_dir = root / "plugins"
    if not plugins_dir.is_dir():
        print(f"WARN: no plugins/ directory at {plugins_dir}; nothing to validate.")
        return 0

    manifests = sorted(plugins_dir.glob("*/plugin.json"))
    if not manifests:
        print("WARN: no plugin manifests found.")
        return 0

    errors: list[str] = []
    seen_ids: dict[str, Path] = {}

    for path in manifests:
        print(f"validating {path.relative_to(root)} ...")
        doc = check_manifest(path, errors)
        if doc is None:
            continue
        pid = doc.get("id", "")
        if pid:
            if pid in seen_ids:
                fail(path, f"duplicate id `{pid}` (also in {seen_ids[pid].relative_to(root)})", errors)
            else:
                seen_ids[pid] = path
        verify_download_hash(path, doc, errors)

    # Plain ASCII — Windows consoles default to cp1252 and choke on
    # check/cross glyphs; CI logs read fine either way.
    if errors:
        print("")
        print(f"FAIL: {len(errors)} validation error(s):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("")
    print(f"OK: {len(manifests)} manifest(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
