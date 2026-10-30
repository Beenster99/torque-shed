#!/usr/bin/env bash
# The network ride's frame times (ride_perf.gd), with a user:// of its own (fresh settings, nothing of yours touched).
#   tests/ride_perf/ride_perf.sh [--only=dales] [--metres=3000] [--speed=25] [--out=FILE]   # headless: the game's own work
#   tests/ride_perf/ride_perf.sh --draw [...]   # drawn under xvfb (lavapipe if LAVAPIPE names its folder): draw call counts
#   tests/ride_perf/ride_perf.sh --crew [...]   # a crew of two (a host and a client game here), into FILE-host and -client
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(command -v godot)}"
HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$HOME_DIR"' EXIT
OUT="$PWD/ride_perf.json"
ARGS=()
DRAW=0
CREW=0
for a in "$@"; do
	case "$a" in
		--crew) CREW=1 ;;
		--out=*) OUT="$(realpath -m "${a#--out=}")" ;;
		--draw) DRAW=1; ARGS+=("$a") ;;
		*) ARGS+=("$a") ;;
	esac
done
run=(timeout 1200 env XDG_DATA_HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR" "$GODOT" --path . --audio-driver Dummy)
if [ "$CREW" = 1 ]; then
	HOME2="$(mktemp -d)"
	"${run[@]}" --headless res://tests/ride_perf/ride_perf.tscn -- --crew=host --out="${OUT%.json}-host.json" "${ARGS[@]}" > "${OUT%.json}-host.log" 2>&1 &
	host=$!
	sleep 4
	timeout 1200 env XDG_DATA_HOME="$HOME2" XDG_CONFIG_HOME="$HOME2" "$GODOT" --path . --audio-driver Dummy --headless \
		res://tests/ride_perf/ride_perf.tscn -- --crew=client --out="${OUT%.json}-client.json" "${ARGS[@]}" > "${OUT%.json}-client.log" 2>&1
	wait $host
	rm -rf "$HOME2"
	grep -h "^RIDE PERF" "${OUT%.json}-host.log" "${OUT%.json}-client.log"
elif [ "$DRAW" = 1 ]; then
	if [ -n "${LAVAPIPE:-}" ]; then
		export VK_DRIVER_FILES="$LAVAPIPE/lvp_icd.json" VK_ICD_FILENAMES="$LAVAPIPE/lvp_icd.json" LD_LIBRARY_PATH="$LAVAPIPE${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	fi
	xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}" res://tests/ride_perf/ride_perf.tscn -- --out="$OUT" "${ARGS[@]}"
else
	"${run[@]}" --headless res://tests/ride_perf/ride_perf.tscn -- --out="$OUT" "${ARGS[@]}"
fi
