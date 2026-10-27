#!/usr/bin/env bash
# The postcards (postcards.gd): the eight places, four views each, and their contact sheet with frame times and memory.
#   tests/postcards/postcards.sh                     # all eight, into /tmp/postcards (about six minutes)
#   tests/postcards/postcards.sh --only=dales        # one place, under a minute, to check a change of your own
#   tests/postcards/postcards.sh --only=dales --quick   # just the pictures, no frame times
#   tests/postcards/postcards.sh --only=dales --network # the network ride (Esc > Debug): fetches the heights round it
#   tests/postcards/postcards.sh --group=1/4 --out=DIR --label="PR 61"   # CI: the second of every four places
#   tests/postcards/postcards.sh --merge=DIR,DIR --out=DIR               # CI: one sheet of the machines' shares
#   tests/postcards/postcards.sh --fetch             # fill world/heights for the rides (after bake.py; needs the network)
# Each place is drawn by a game of its own, so its memory is its own and not what the places before it left behind. It
# needs a screen, so it runs under xvfb-run when there isn't one, with a user:// of its own (fresh settings, nothing of
# yours touched). GODOT names the Godot to use.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(command -v godot)}"
OUT=/tmp/postcards
ONLY=""
GROUP="0/1"
LABEL=""
SINGLE=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--out=*) OUT="${a#--out=}" ;;
		--only=*) ONLY="${a#--only=}" ;;
		--group=*) GROUP="${a#--group=}" ;;
		--label=*) LABEL="${a#--label=}" ;;
		--merge=*|--fetch) SINGLE=1; ARGS+=("$a") ;;
		*) ARGS+=("$a") ;;
	esac
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$HOME_DIR"' EXIT

godot_run() {
	# (cut off at ten minutes: a script that fails to load leaves Godot waiting for ever)
	local run=(timeout 600 env XDG_DATA_HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR" "$GODOT" --path . --audio-driver Dummy
		res://tests/postcards/postcards.tscn -- "$@")
	if [ -z "${DISPLAY:-}" ]; then
		xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}"
	else
		"${run[@]}"
	fi
}

if [ "$SINGLE" = 1 ]; then
	godot_run --out="$OUT" --only="$ONLY" --group="$GROUP" --label="$LABEL" "${ARGS[@]}"
	exit
fi

# The places this run takes (places.json's order; --only, then the Kth of every N for --group=K/N).
IDS=$(python3 - "$ONLY" "$GROUP" <<'PY'
import json, sys
only = [i for i in sys.argv[1].split(",") if i]
k, n = (int(v) for v in sys.argv[2].split("/"))
ids = [p["id"] for p in json.load(open("tests/postcards/places.json"))["places"] if not only or p["id"] in only]
print(" ".join(i for x, i in enumerate(ids) if x % n == k))
PY
)
status=0
DIRS=()
for id in $IDS; do
	godot_run --out="$OUT/$id" --only="$id" --no-sheet "${ARGS[@]}" || status=1
	DIRS+=("$OUT/$id")
done
if [ "${#DIRS[@]}" -gt 0 ]; then
	godot_run --out="$OUT" --merge="$(IFS=,; echo "${DIRS[*]}")" --label="$LABEL" || status=1
	rm -rf "${DIRS[@]}"
fi
exit $status
