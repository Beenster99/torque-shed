#!/usr/bin/env bash
# Starts a host and a client on this machine and checks each sees the other's bike move.
# Then a second pair rides an adventure together (tests/mp_adventure.gd), a third breaks down
# on one and fixes it at the roadside, then tows (tests/mp_wrench.gd), a fourth eats, sits
# and sleeps on one (tests/mp_needs.gd), and a fifth starts one from the magazine and arrives at
# its destination together (tests/mp_dest.gd).
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
# Roadside wrenching: the client breaks down, the host sees the bike at the roadside fixed, then tows it.
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_wrench.tscn -- --role=host > /tmp/torque_mp_wrench_host.log 2>&1 &
WHOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_wrench.tscn -- --role=client > /tmp/torque_mp_wrench_client.log 2>&1
WCLIENT=$?
wait $WHOST
WHOSTRC=$?
grep -h "MP wrench" /tmp/torque_mp_wrench_host.log /tmp/torque_mp_wrench_client.log
# Hunger, thirst and tiredness on the adventure: eating, sitting together and sleeping, seen by both.
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_needs.tscn -- --role=host > /tmp/torque_mp_needs_host.log 2>&1 &
NHOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_needs.tscn -- --role=client > /tmp/torque_mp_needs_client.log 2>&1
NCLIENT=$?
wait $NHOST
NHOSTRC=$?
grep -h "MP needs" /tmp/torque_mp_needs_host.log /tmp/torque_mp_needs_client.log
# The destination: the host starts one from the magazine, both arrive together, both get the photo.
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_dest.tscn -- --role=host > /tmp/torque_mp_dest_host.log 2>&1 &
DHOST=$!
sleep 4
"$GODOT" --headless --fixed-fps 60 --path . res://tests/mp_dest.tscn -- --role=client > /tmp/torque_mp_dest_client.log 2>&1
DCLIENT=$?
wait $DHOST
DHOSTRC=$?
grep -h "MP dest" /tmp/torque_mp_dest_host.log /tmp/torque_mp_dest_client.log
if [ $HOSTRC -ne 0 ] || [ $CLIENT -ne 0 ] || [ $AHOSTRC -ne 0 ] || [ $ACLIENT -ne 0 ] || [ $WHOSTRC -ne 0 ] || [ $WCLIENT -ne 0 ] || [ $NHOSTRC -ne 0 ] || [ $NCLIENT -ne 0 ] || [ $DHOSTRC -ne 0 ] || [ $DCLIENT -ne 0 ]; then
	echo "Multiplayer test failed"
	exit 1
fi
echo "Multiplayer test passed"
