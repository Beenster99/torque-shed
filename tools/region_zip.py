#!/usr/bin/env python3
"""Zips a baked region folder for the game to download (scripts/region_store.gd), and prints its index entry:

    python3 tools/region_zip.py data/regions/shodoshima out/shodoshima.zip

The zip holds the folder's files at its top level. The entry goes in data/regions/index.json under the region's id,
with the url the zip is served from added."""
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import region_bake as rg  # noqa: E402


def zip_region(folder, out):
    """Writes the zip; returns the index entry {title, hash, bytes, format}."""
    with open(os.path.join(folder, "region.json")) as f:
        meta = json.load(f)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in sorted(os.walk(folder)):
            for fn in sorted(files):
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, folder))
    return {"title": meta.get("title", meta.get("name")), "hash": rg.region_hash(folder), "bytes": os.path.getsize(out),
            "format": meta.get("format")}


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 2:
        print(__doc__)
        return 2
    entry = zip_region(argv[0], argv[1])
    print(json.dumps({os.path.basename(os.path.normpath(argv[0])): entry}, indent=1))


if __name__ == "__main__":
    sys.exit(main())
