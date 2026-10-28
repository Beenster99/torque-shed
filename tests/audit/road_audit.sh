#!/usr/bin/env bash
# The world road audit (road_audit.gd): the road network's faults in the world's cells, from the data alone.
#   tests/audit/road_audit.sh --places                 # the postcards' places, map checks only (a minute or two)
#   tests/audit/road_audit.sh --cells=268_547 --heights   # one cell, with the land's heights (fetched)
#   tests/audit/road_audit.sh --all                    # every cell in the world's store
# Findings go to --out (/tmp/road-audit by default): report.json, summary.txt, and each cell's own in cells/, kept so a
# cell that hasn't changed isn't audited again. The cells and heights it fetches are kept in --cache (~/.cache/road-audit
# by default). GODOT names the Godot to use.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(command -v godot)}"
CACHE="${HOME}/.cache/road-audit"
ARGS=()
for a in "$@"; do
	case "$a" in
		--cache=*) CACHE="${a#--cache=}" ;;
		*) ARGS+=("$a") ;;
	esac
done
mkdir -p "$CACHE"
# (user:// is the cache: the fetched cells and heights are kept there, and nothing of yours is touched)
XDG_DATA_HOME="$(cd "$CACHE" && pwd)" "$GODOT" --headless --path . res://tests/audit/road_audit.tscn -- "${ARGS[@]}"
