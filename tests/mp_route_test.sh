#!/usr/bin/env bash
# Checks the route handshake in co-op: players on the same baked route can join each other, players on
# different maps are turned away. Starts a host and a client on this machine each time.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
ROUTE="res://data/routes/shodoshima"
FAIL=0

run() {   # run <expect> <host extra args> <client extra args>
	local expect=$1 host_args=$2 client_args=$3
	"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_route_test.tscn -- --role=host --expect="$expect" $host_args > /tmp/torque_mpr_host.log 2>&1 &
	local host=$!
	sleep 5
	"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_route_test.tscn -- --role=client --expect="$expect" $client_args > /tmp/torque_mpr_client.log 2>&1
	local client=$?
	wait $host
	local hostrc=$?
	grep -h "MP ROUTE" /tmp/torque_mpr_host.log /tmp/torque_mpr_client.log
	if [ $hostrc -ne 0 ] || [ $client -ne 0 ]; then FAIL=1; fi
}

if [ -f "data/routes/shodoshima/pack.json" ]; then
	run match "--route=$ROUTE" "--route=$ROUTE"
	run mismatch "--route=$ROUTE" ""
	run mismatch "" "--route=$ROUTE"
fi
if [ $FAIL -ne 0 ]; then
	echo "Route multiplayer test failed"
	exit 1
fi
echo "Route multiplayer test passed"
