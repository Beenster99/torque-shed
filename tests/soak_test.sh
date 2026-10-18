#!/usr/bin/env bash
# Soak test: a host and two clients on this machine play for a while (SOAK_SECS, 240 by default)
# with the game clock sped up; each checks its node, object, memory, sound and network counts
# don't keep growing. Logs go in SOAK_LOGS (default /tmp).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SECS="${SOAK_SECS:-240}"
LOGS="${SOAK_LOGS:-/tmp}"
"$GODOT" --headless --fixed-fps 60 --path . res://tests/soak_test.tscn -- --role=host --secs=$((SECS + 20)) > "$LOGS/torque_soak_host.log" 2>&1 &
HOST=$!
sleep 6
"$GODOT" --headless --fixed-fps 60 --path . res://tests/soak_test.tscn -- --role=client1 --secs=$SECS > "$LOGS/torque_soak_client1.log" 2>&1 &
C1=$!
sleep 2
"$GODOT" --headless --fixed-fps 60 --path . res://tests/soak_test.tscn -- --role=client2 --secs=$SECS > "$LOGS/torque_soak_client2.log" 2>&1
C2RC=$?
wait $C1
C1RC=$?
wait $HOST
HOSTRC=$?
grep -h "SOAK " "$LOGS/torque_soak_host.log" "$LOGS/torque_soak_client1.log" "$LOGS/torque_soak_client2.log"
if [ $HOSTRC -ne 0 ] || [ $C1RC -ne 0 ] || [ $C2RC -ne 0 ]; then
	echo "Soak test failed"
	exit 1
fi
echo "Soak test passed"
