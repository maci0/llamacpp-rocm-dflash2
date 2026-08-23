#!/usr/bin/env python3
"""Print the latest TheRock linux dist tarball URL for a lemonade family."""
from __future__ import annotations

import json
import re
import sys
import urllib.request

FAMILY_S3 = {
    "gfx110X": "gfx110X-all",
    "gfx103X": "gfx103X-all",
    "gfx120X": "gfx120X-all",
    "gfx1150": "gfx1150",
    "gfx1151": "gfx1151",
    "gfx90a": "gfx90a",
    "gfx908": "gfx908",
}

INDEX = "https://rocm.nightlies.amd.com/tarball-multi-arch/"


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in FAMILY_S3:
        print("usage: resolve-therock.py <" + "|".join(FAMILY_S3) + ">", file=sys.stderr)
        return 2
    s3 = FAMILY_S3[sys.argv[1]]
    prefix = f"therock-dist-linux-{s3}-"
    html = urllib.request.urlopen(INDEX, timeout=60).read().decode("utf-8", "replace")
    m = re.search(r"const files = (\[.*?\])\s*;", html, re.S)
    if not m:
        print("could not parse TheRock index", file=sys.stderr)
        return 1
    files = json.loads(m.group(1))
    pat = re.compile(
        r"^" + re.escape(prefix) + r"([0-9]+\.[0-9]+\.[0-9]+(?:a|rc)[0-9]+)\.tar\.gz$"
    )
    best = None
    for f in files:
        name = f.get("name") or ""
        mm = pat.match(name)
        if not mm:
            continue
        ver = mm.group(1)
        if best is None or ver > best[0]:
            best = (ver, name)
    if best is None:
        print(f"no tarball for {prefix}", file=sys.stderr)
        return 1
    print(f"{INDEX}{best[1]}")
    print(best[0], file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
