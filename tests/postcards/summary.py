#!/usr/bin/env python3
"""The postcards' stats (postcards.gd's stats.json) as a Markdown table, for a CI run's summary page.

    python3 tests/postcards/summary.py postcards/stats.json >> "$GITHUB_STEP_SUMMARY"
"""
import json
import sys


def table(stats):
    views = list(stats.get("views", []))
    for p in stats.get("places", []):
        for v in p.get("views", {}):
            if v not in views:
                views.append(v)
    out = ["### Postcards", "",
           "%s graphics on %s, %d places in %.0f s. Frame times are mean / 95th percentile ms on this machine (no graphics"
           " card): compare them run to run. The contact sheet is in the **postcards** artifact."
           % (str(stats.get("preset", "")).capitalize(), stats.get("renderer", ""), len(stats.get("places", [])),
              float(stats.get("seconds", 0.0))), "",
           "| Place | km | Laid out | Memory | " + " | ".join(views) + " |",
           "|---|---|---|---|" + "---|" * len(views)]
    for p in stats.get("places", []):
        if p.get("error"):
            out.append("| %s | | **%s** | |%s" % (p.get("title", p["id"]), p["error"], " |" * len(views)))
            continue
        cells = []
        for v in views:
            t = p.get("views", {}).get(v, {})
            cell = "%.0f / %.0f ms, %d draws" % (t["ms"], t["p95"], t["draws"]) if "ms" in t else ""
            if not t.get("settled", True):
                cell += " (not all built)"
            cells.append(cell)
        out.append("| %s | %.1f | %.1f s | %.0f MB | %s |" % (p.get("title", p["id"]), float(p.get("km", 0)),
                   float(p.get("load_s", 0)), float(p.get("static_mb", 0)), " | ".join(cells)))
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        sys.stdout.write(table(json.load(f)))
