#!/usr/bin/env bash
# Starts a host and a client on this machine and checks each sees the other's bike move.
# Then a second pair rides an adventure together (tests/mp_adventure.gd), a third breaks down
# on one and fixes it at the roadside (a mate swapping its pads from the toolbox), then tows (tests/mp_wrench.gd), a fourth eats, sits
# and sleeps on one (tests/mp_needs.gd),
# a fifth starts one along a planned journey and arrives at its destination together (tests/mp_dest.gd),
# a sixth keeps the Adventure Diary: the host's shared highlights, both riders' photos in each diary (tests/mp_diary.gd),
# a seventh rides with one of the other bikers on an adventure (tests/mp_bikers.gd),
# an eighth rides a real road together and sleeps at an inn along it (tests/mp_real.gd), a ninth plans a
# journey together on the Route planner and rides it (tests/mp_journey.gd), a tenth rides the road network
# in two different cells of the map, joins a ride in progress and agrees to leave the route (tests/mp_network.gd), and an
# eleventh rides the eighth's real road on the road network, end to end (tests/mp_real_net.gd).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Each pair: its scene, and how it runs (the other bikers' pair runs at the real frame rate). Pass pair names
# (tests/mp_test.sh mp_real mp_journey) to run just those: CI runs them spread over several machines.
ALL="mp_test mp_adventure mp_wrench mp_needs mp_dest mp_diary mp_bikers mp_real mp_journey mp_network mp_real_net"
failed=""
for pair in ${*:-$ALL}; do
	if [ ! -f "tests/$pair.tscn" ]; then
		echo "No such pair: $pair"
		failed="$failed $pair"
		continue
	fi
	fps="--fixed-fps 60"
	[ "$pair" = "mp_bikers" ] && fps=""
	"$GODOT" --headless $fps --path . "res://tests/$pair.tscn" -- --role=host > "/tmp/torque_${pair}_host.log" 2>&1 &
	host=$!
	sleep 4
	"$GODOT" --headless $fps --path . "res://tests/$pair.tscn" -- --role=client > "/tmp/torque_${pair}_client.log" 2>&1
	client=$?
	wait $host
	hostrc=$?
	grep -h "^MP " "/tmp/torque_${pair}_host.log" "/tmp/torque_${pair}_client.log"
	if [ $hostrc -ne 0 ] || [ $client -ne 0 ]; then
		failed="$failed $pair"
	fi
done
if [ -n "$failed" ]; then
	echo "Multiplayer test failed:$failed"
	exit 1
fi
echo "Multiplayer test passed"
