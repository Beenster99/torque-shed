#!/usr/bin/env bash
# Starts a host and a client on this machine and checks each sees the other's bike move.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_test.tscn -- --role=host > /tmp/torque_mp_host.log 2>&1 &
HOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_test.tscn -- --role=client > /tmp/torque_mp_client.log 2>&1
CLIENT=$?
wait $HOST
HOSTRC=$?
grep -h "MP " /tmp/torque_mp_host.log /tmp/torque_mp_client.log
if [ $HOSTRC -ne 0 ] || [ $CLIENT -ne 0 ]; then
	echo "Multiplayer test failed"
	exit 1
fi
echo "Multiplayer test passed"
