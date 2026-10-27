extends RefCounted
## Co-op on the road network's checks (AdventureCrew, Ride Anywhere v2 T9), run from tests/run_tests.gd: its
## _test_coop_* functions hand over to these. Plain functions, no scene and no network (tests/mp_network.gd rides it).

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The builder and ride hashes: the same parts the same hash, any part changed a different one, and why a game that
## doesn't match is turned away.
func test_hashes() -> void:
	var a := AdventureCrew.builds_of([4, 8, 1, "kits", "countries"])
	check(a.length() == 12 and a == AdventureCrew.builds_of([4, 8, 1, "kits", "countries"]), "the same builders, the same hash (%s)" % a)
	check(a != AdventureCrew.builds_of([5, 8, 1, "kits", "countries"]), "a road block version bumped, a different hash")
	check(a != AdventureCrew.builds_of([4, 8, 1, "kits2", "countries"]), "the regional kits changed, a different hash")
	check(AdventureCrew.builds() == AdventureCrew.builds() and AdventureCrew.builds().length() == 12, "this game has one")
	var r := AdventureCrew.ride_hash_of(a, "cells1", "profile1")
	check(r != AdventureCrew.ride_hash_of(a, "cells2", "profile1"), "different map cells, a different ride hash")
	check(r != AdventureCrew.ride_hash_of(a, "cells1", "profile2"), "a different place profile, a different ride hash")
	check(r != AdventureCrew.ride_hash_of(AdventureCrew.builds_of([5]), "cells1", "profile1"), "different builders, a different ride hash")
	var region := RealRegion.get_region("dales")
	check(AdventureCrew.ride_hash(region) != "" and AdventureCrew.ride_hash(region) == AdventureCrew.ride_hash(region),
		"a bundled region has a steady ride hash")
	check(AdventureCrew.ride_hash(null) == "", "no region, no ride hash")
	var info := {"builds": a, "ride_hash": r}
	check(AdventureCrew.ride_mismatch(info, a, r) == "", "the same builders and map: on the ride")
	check(AdventureCrew.ride_mismatch(info, "other", r).contains("different version"), "a different version is told to update")
	check(AdventureCrew.ride_mismatch(info, a, "other").contains("map of this area"), "a different copy of the map is told so")
	check(AdventureCrew.ride_mismatch(info, a, "").contains("doesn't have"), "no copy of the map at all is told so")
	var crew := {1: {"name": "Host", "builds": a}, 2: {"name": "Sam", "builds": "old"}, 3: {"name": "Jo"}}
	check(Array(AdventureCrew.odd_ones(crew, a)) == ["Sam"], "the odd one out named, one who hasn't said not counted")


## Positions in the region's frame: two machines whose origins are kilometres apart (riders in different cells) agree
## where each rider is to the centimetre, and who a player joining a ride in progress is put by.
func test_positions() -> void:
	# A rider at region (-2140.25, y, 1310.5) seen from an origin near them, a walker at region (6015.75, 3020.125).
	var o1 := Vector3(-2048.0 - AdventureWorld.ANCHOR.x, 0.0, 1280.0 - AdventureWorld.ANCHOR.z)
	var o2 := Vector3(6144.0 - AdventureWorld.ANCHOR.x, 0.0, 3072.0 - AdventureWorld.ANCHOR.z)
	var rider := PackedFloat32Array([1, 7, -2140.25 - o1.x, 312.0, 1310.5 - o1.z, 0.1, 0.2])
	var walker := PackedFloat32Array([0, 6015.75 - o2.x, 280.0, 3020.125 - o2.z, 0.0])
	var tag1 := rider.duplicate()
	tag1.append_array([o1.x, o1.z, AdventureWorld.NET_TAG])
	var tag2 := walker.duplicate()
	tag2.append_array([o2.x, o2.z, AdventureWorld.NET_TAG])
	var at1 = AdventureCrew.region_xz(tag1)
	var at2 = AdventureCrew.region_xz(tag2)
	check(at1 is Vector2 and (at1 as Vector2).distance_to(Vector2(-2140.25, 1310.5)) < 0.01, "a rider's snapshot gives their map point (%s)" % str(at1))
	check(at2 is Vector2 and (at2 as Vector2).distance_to(Vector2(6015.75, 3020.125)) < 0.01, "a walker's too (%s)" % str(at2))
	check(AdventureCrew.region_xz(rider) == null, "an untagged one (in the shed) has none")
	var c1 := RealRegion.cell_of(54.34, -2.04 + (-2140.25) / 65000.0)
	var c2 := RealRegion.cell_of(54.34, -2.04 + 6015.75 / 65000.0)
	check(c1 != c2, "the two are in different cells of the world (%s, %s)" % [c1, c2])
	# Each seen in the other's local frame, where untag puts them: the same map point.
	var seen := AdventureWorld.untag(tag1, o2)
	var back := Vector2(seen[2] + o2.x, seen[4] + o2.z)
	check(back.distance_to(Vector2(-2140.25, 1310.5)) < 0.01, "seen from 8 km away, still to the centimetre (off by %.4f m)" % back.distance_to(Vector2(-2140.25, 1310.5)))
	check(not AdventureCrew.near(at1, at2) and AdventureCrew.near(at1, at1 + Vector2(500, 300)), "a mate 8 km off isn't near; 600 m off is")
	var start := Vector2(-2000.0, 1300.0)
	check(AdventureCrew.join_by({2: at2, 3: at1}, start) == -1, "a mate still at the start: the joiner starts on the grid")
	check(AdventureCrew.join_by({3: at2, 2: at2 + Vector2(10, 0)}, start) == 2, "all under way: by the lowest peer (the host when out)")
	check(AdventureCrew.join_by({}, start) == -1, "nobody out: the grid")


## The "leave the route?" call: a majority decides, a tie keeps things as they are, silence is no once the time's up,
## a crew of one changes at once.
func test_call() -> void:
	var route := AdventureCrew.sanitize_route({})
	check(route["mode"] == "route" and int(route["version"]) == 0 and (route["call"] as Dictionary).is_empty(), "the crew starts on its agreed route")
	check(AdventureCrew.call_check(route, 2, "rejoin", [1, 2]) != "", "can't ask to rejoin a route you're on")
	check(AdventureCrew.call_check(route, 5, "leave", [1, 2]) != "", "only a rider out on the trip asks")
	check(AdventureCrew.call_check(route, 2, "detour", [1, 2]) != "", "only the calls there are")
	check(AdventureCrew.call_check(route, 2, "leave", [1, 2]) == "", "a rider asks to leave it")
	var c := AdventureCrew.open_call(route, 2, "leave", 1000)
	check(AdventureCrew.call_check(route, 1, "leave", [1, 2]) != "", "one call at a time")
	check(int(c["id"]) == 1 and bool(c["votes"][2]) and int(c["ends"]) == 31000, "the caller's own answer is yes; 30 s to answer")
	check(AdventureCrew.outcome(c, [1, 2], 2000) == "", "two riders, one yes: still open")
	c["votes"][1] = false
	check(AdventureCrew.outcome(c, [1, 2], 2000) == "no", "a tie keeps things as they are")
	c["votes"][1] = true
	check(AdventureCrew.outcome(c, [1, 2], 2000) == "yes", "both yes: off the route")
	c["votes"].erase(1)
	check(AdventureCrew.outcome(c, [1, 2, 3], 2000) == "", "three riders, one yes: open")
	check(AdventureCrew.outcome(c, [1, 2, 3], 31000) == "no", "time up: silence is no")
	c["votes"][3] = true
	check(AdventureCrew.outcome(c, [1, 2, 3], 2000) == "yes", "two of three: yes, without waiting for the third")
	c["votes"][3] = false
	c["votes"][1] = false
	check(AdventureCrew.outcome(c, [1, 2, 3], 2000) == "no", "two of three no: no")
	check(AdventureCrew.outcome(c, [2], 2000) == "yes", "a crew of one: at once")
	check(AdventureCrew.vote_check(route, 1, 9, [1, 2]) != "" and AdventureCrew.vote_check(route, 1, 1, [1, 2]) == "", "answers go to the open call")
	var said := AdventureCrew.settle(route, "yes")
	check(route["mode"] == "free" and int(route["version"]) == 1 and (route["call"] as Dictionary).is_empty() and said.contains("leaving"),
		"yes: the crew's off the route, its version one up (%s)" % said)
	check(AdventureCrew.call_check(route, 1, "leave", [1, 2]) != "" and AdventureCrew.call_check(route, 1, "rejoin", [1, 2]) == "",
		"off the route, the call is to get back on it")
	AdventureCrew.open_call(route, 1, "rejoin", 5000)
	said = AdventureCrew.settle(route, "no")
	check(route["mode"] == "free" and int(route["version"]) == 1 and said.contains("off the route"), "no: as it was (%s)" % said)
	# Sent over the network and back: whole.
	AdventureCrew.open_call(route, 1, "rejoin", 5000)
	var again := AdventureCrew.sanitize_route(JSON.parse_string(JSON.stringify(route)))
	check(again["mode"] == "free" and int((again["call"] as Dictionary)["id"]) == 3 and bool((again["call"]["votes"] as Dictionary)[1]),
		"the route state survives the trip over the network")
	check((AdventureCrew.sanitize_route({"call": {"id": 1, "kind": "nonsense"}})["call"] as Dictionary).is_empty(), "a broken call is dropped")


## The shared state: the host's network choice and hashes go out with the ride, the crew's actions run through
## Adventure, and a lone rider's call changes the route at once.
func test_state() -> void:
	var was_adv := Shed.adventure
	var was_crew := Shed.crew
	Shed.crew = {1: {"name": "Host"}, 2: {"name": "Sam"}}
	Shed.adventure = Adventure.sanitize({"id": 5, "plan": AdventurePlans.tour("dales", 2), "riders": {1: 0, 2: 0}, "network": true})
	check(Adventure.network() and Adventure.route_mode() == "route" and Adventure.route_version() == 0 and Adventure.route_call().is_empty(),
		"a network ride starts on its agreed route")
	check(Adventure.check(1, {"a": "adventure_route_call", "kind": "leave"}) == "", "the host may ask")
	var said := Adventure.apply(1, {"a": "adventure_route_call", "kind": "leave"})
	check(said.begins_with("*Host asks") and not Adventure.route_call().is_empty(), "the crew's asked (%s)" % said)
	var id := int(Adventure.route_call()["id"])
	check(Adventure.check(2, {"a": "adventure_route_vote", "id": id, "yes": true}) == "", "Sam may answer")
	said = Adventure.apply(2, {"a": "adventure_route_vote", "id": id, "yes": true})
	check(Adventure.route_mode() == "free" and Adventure.route_version() == 1 and said.contains("leaving"), "both yes: off the route (%s)" % said)
	# Alone (Sam gone home): asking is deciding.
	Shed.crew.erase(2)
	said = Adventure.apply(1, {"a": "adventure_route_call", "kind": "rejoin"})
	check(Adventure.route_mode() == "route" and Adventure.route_version() == 2 and Adventure.route_call().is_empty(), "alone, back on it at once (%s)" % said)
	# The builder hash, told as you join the shed.
	Shed.crew[2] = {"name": "Sam"}
	said = Adventure.apply(2, {"a": "adventure_builds", "builds": "older"})
	check(str(Shed.crew[2]["builds"]) == "older" and said.contains("different version"), "a different version is caught on joining (%s)" % said)
	said = Adventure.apply(2, {"a": "adventure_builds", "builds": AdventureCrew.builds()})
	check(said == "", "the same version: nothing said")
	Shed.crew[2]["builds"] = "older"
	var net_was := AdventureWorld.network
	AdventureWorld.network = true
	var active := Shed.adventure
	Shed.adventure = {}
	var why := Adventure.check(1, {"a": "adventure_start", "plan": AdventurePlans.tour("dales", 2)})
	check(why.contains("Sam is on a different version"), "a network ride isn't set off with a mate on another version (%s)" % why)
	Shed.adventure = active
	AdventureWorld.network = net_was
	Shed.adventure = was_adv
	Shed.crew = was_crew
