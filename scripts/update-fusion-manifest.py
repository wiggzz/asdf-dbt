#!/usr/bin/env python3
"""Download and normalise the dbt Fusion CLI manifest.

The official install script published by dbt Labs fetches a JSON manifest that
maps fusion versions to per-platform tarballs. This helper reproduces the same
steps so the manifest can be cached locally for offline asdf installs.

Usage:
    python scripts/update-fusion-manifest.py --version 0.6.4 --output share/fusion-manifest.json

When invoked without --version the script downloads the manifest containing all
available versions.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any, Dict

DEFAULT_MANIFEST_URL = "https://dl.fusion.getdbt.com/cli/manifest.json"


def fetch_manifest(url: str) -> Dict[str, Any]:
    with urllib.request.urlopen(url) as response:  # nosec B310
        if response.status != 200:
            raise RuntimeError(f"Unexpected status code {response.status} fetching {url}")
        return json.load(response)


def filter_versions(manifest: Dict[str, Any], version: str | None) -> Dict[str, Any]:
    if version is None:
        return manifest
    versions = manifest.get("versions", {})
    if version not in versions:
        raise SystemExit(f"Version {version} not present in manifest")
    return {"versions": {version: versions[version]}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_MANIFEST_URL, help="Manifest URL to download")
    parser.add_argument("--version", help="Restrict to a single fusion version")
    parser.add_argument("--output", default="share/fusion-manifest.json", help="Path to write the manifest")
    args = parser.parse_args(argv)

    manifest = fetch_manifest(args.url)
    filtered = filter_versions(manifest, args.version)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(filtered, indent=2, sort_keys=True))
    print(f"Wrote manifest with {len(filtered.get('versions', {}))} version(s) to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
