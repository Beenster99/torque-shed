#!/usr/bin/env bash
# Starts a host and a client on this machine and checks each sees the other's bike move.
# Then a second pair rides an adventure together (tests/mp_adventure.gd), and a third eats,
# sits and sleeps on one (tests/mp_needs.gd).
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
# The adventure ride: both on it, seen by each other 30 km out after the origins have moved.
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_adventure.tscn -- --role=host > /tmp/torque_mp_adv_host.log 2>&1 &
AHOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_adventure.tscn -- --role=client > /tmp/torque_mp_adv_client.log 2>&1
ACLIENT=$?
wait $AHOST
AHOSTRC=$?
grep -h "MP adv" /tmp/torque_mp_adv_host.log /tmp/torque_mp_adv_client.log
# Hunger, thirst and tiredness on the adventure: eating, sitting together and sleeping, seen by both.
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_needs.tscn -- --role=host > /tmp/torque_mp_needs_host.log 2>&1 &
NHOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_needs.tscn -- --role=client > /tmp/torque_mp_needs_client.log 2>&1
NCLIENT=$?
wait $NHOST
NHOSTRC=$?
grep -h "MP needs" /tmp/torque_mp_needs_host.log /tmp/torque_mp_needs_client.log
if [ $HOSTRC -ne 0 ] || [ $CLIENT -ne 0 ] || [ $AHOSTRC -ne 0 ] || [ $ACLIENT -ne 0 ] || [ $NHOSTRC -ne 0 ] || [ $NCLIENT -ne 0 ]; then
	echo "Multiplayer test failed"
	exit 1
fi
echo "Multiplayer test passed"
