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


## A guest whose copy of the map is only older than the host's (the world's store baked cells, or made their place
## profiles, while the route was planned) catches up instead of being turned away: a cell baked but not yet profiled
## counts as still being finished (no plan over it, and no guessed profile kept for it), a plan that can't be made only
## for now is planned again later, a guest on the host's version fetches the latest before giving up, and when that
## doesn't do it the crew's told to start the ride again.
func test_catch_up() -> void:
	var a := Vector2i(577, 711)
	var b := Vector2i(577, 712)
	var sea := Vector2i(577, 713)
	var idx := {"cells": {"577_711": {"hash": "h1"}, "577_712": {"hash": "h2"}, "577_713": {"empty": true}},
		"profiles": {"577_711": "p1"}}
	var cells: Array[Vector2i] = [a, b, sea, Vector2i(1, 1)]
	check(Array(CellStore.finishing(cells, idx)) == [b], "a cell baked but not yet profiled is still being finished; one profiled, the sea and one nobody baked aren't")
	check(CellStore.finishing(cells, {"cells": idx["cells"]}).is_empty(), "an index with no profiles at all has nothing being finished (an old one)")
	check(Array(RealRegion.area_cells("area:@577_711,577_712")) == [a, b] and RealRegion.area_cells("dales").is_empty(),
		"an area's cells are known whether the game has them or not; a bundled region has none")
	# The world's store as a game saw it in the minutes between: both cells baked, one with its profile.
	var store := "user://test_catch_up"
	RegionStore._remove_tree(store)
	DirAccess.make_dir_recursive_absolute(store)
	var was := [CellStore.dir, CellStore.offline, RealRegion.cell_dirs, HeightTiles.dirs, HeightTiles.offline]
	var save := func(index: Dictionary) -> void:
		var f := FileAccess.open(store.path_join("index.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(index))
		f.close()
		CellStore.forget_index()
	save.call({"format": 1, "cells": {"577_711": {"hash": "h1"}, "577_712": {"hash": "h2"}}, "profiles": {"577_711": "p1"}})
	CellStore.dir = store
	CellStore.offline = true
	PlaceProfile.forget()
	RegionKit.forget()
	var guessed := PlaceProfile.of_cell(b)
	check(bool(guessed["guessed"]), "a cell still being finished gets a guessed profile for now")
	# Its profile comes.
	var text := JSON.stringify({"format": PlaceProfile.FORMAT, "cell": "577_712", "lat": 54.3, "lon": -1.9, "country": "GB", "hash": "fresh0000000",
		"guessed": false})
	DirAccess.make_dir_recursive_absolute(store.path_join("profile"))
	var f := FileAccess.open(store.path_join("profile/c577_712.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	save.call({"format": 1, "cells": {"577_711": {"hash": "h1"}, "577_712": {"hash": "h2"}}, "profiles": {"577_711": "p1", "577_712": text.sha1_text().left(12)}})
	var real := PlaceProfile.of_cell(b)
	check(not bool(real["guessed"]) and str(real["hash"]) == "fresh0000000", "and once it's come the guess isn't kept: the real one's had (%s)" % str(real["hash"]))
	# A plan over cells still being finished waits for them, and is planned again once they're done.
	RealRegion.cell_dirs = ["res://tests/fixtures/cells"]
	HeightTiles.dirs = ["res://tests/fixtures/heights"]
	HeightTiles.offline = true
	HeightTiles.reset()
	RealRegion.forget_areas()
	save.call({"format": 1, "cells": {"577_711": {"hash": "h1"}, "577_712": {"hash": "h2"}}, "profiles": {"577_711": "p1"}})
	var plan := AdventurePlans.clean({"region": "area:swaledale", "pins": [[-2422, -4363], [7187, -4599]], "mode": "main"})
	AdventurePlans.forget(plan)
	var res := AdventurePlans.result(plan, true)
	check(not bool(res["ok"]) and bool(res.get("retry", false)) and bool(res.get("map", false)) and str(res["error"]) == AdventurePlans.FINISHING,
		"no plan over a cell still being finished: it says to try again shortly (%s)" % str(res["error"]))
	check(AdventurePlans.result(plan, true).get("at") == res.get("at"), "asked again at once, the answer's kept (not planned every frame)")
	save.call({"format": 1, "cells": {"577_711": {"hash": "h1"}, "577_712": {"hash": "h2"}}, "profiles": {"577_711": "p1", "577_712": text.sha1_text().left(12)}})
	AdventurePlans._lock.lock()
	AdventurePlans._done[AdventurePlans.key(plan)]["at"] = Time.get_ticks_msec() - AdventurePlans.RETRY_MS - 1
	AdventurePlans._lock.unlock()
	res = AdventurePlans.result(plan, true)
	check(bool(res["ok"]), "once the map's finished, the plan's made (%s)" % str(res.get("error", "")))
	# A guest turned away: on the host's version, a different map may only be an older one; another version can't catch up.
	var mine := AdventureCrew.builds()
	check(AdventureCrew.map_may_catch_up({"builds": mine}, {"ok": true}), "the same version but a different map: fetch the latest first")
	check(AdventureCrew.map_may_catch_up({"builds": mine}, {"ok": false, "map": true}), "the same version and the map not the host's: the same")
	check(not AdventureCrew.map_may_catch_up({"builds": mine}, {"ok": false}), "a plan that failed for another reason: no")
	check(not AdventureCrew.map_may_catch_up({"builds": "older"}, {"ok": true}), "another version: fetching the map won't help")
	check(AdventureCrew.ride_mismatch({"builds": mine, "ride_hash": "x"}, mine, "y").contains("Ask the host to end the ride and start it again")
		and not AdventureCrew.ride_mismatch({"builds": mine, "ride_hash": "x"}, mine, "y").contains("update the game"),
		"a different map on the same version is told to start the ride again, not to update")
	# The refresh: the index fetched afresh, the plan and every profile forgotten.
	PlaceProfile.of_cell(b)
	AdventurePlans.refresh(plan)
	AdventurePlans._lock.lock()
	var forgot := not AdventurePlans._done.has(AdventurePlans.key(plan))
	AdventurePlans._lock.unlock()
	PlaceProfile._lock.lock()
	forgot = forgot and PlaceProfile._cells.is_empty()
	PlaceProfile._lock.unlock()
	check(forgot, "fetching the latest forgets the plan and the profiles, so the next ask starts afresh")
	# The host's told, and its own map fetched afresh once it's back.
	var was_adv := Shed.adventure
	var was_crew := Shed.crew
	Shed.crew = {1: {"name": "Host"}, 2: {"name": "Sam"}}
	Shed.adventure = Adventure.sanitize({"id": 7, "plan": plan, "riders": {1: 0}, "network": true})
	AdventureTrip.host_refresh = {}
	check(Adventure.check(2, {"a": "adventure_cant", "id": 6}).contains("over"), "a ride that's over isn't told about")
	check(Adventure.check(1, {"a": "adventure_cant", "id": 7}) != "", "the host doesn't tell itself")
	check(Adventure.check(2, {"a": "adventure_cant", "id": 7}) == "", "a guest tells the host")
	var said := Adventure.apply(2, {"a": "adventure_cant", "id": 7})
	check(said.begins_with("*Sam couldn't join the ride") and said.contains("end the ride and start it again")
		and AdventurePlans.key(AdventureTrip.host_refresh) == AdventurePlans.key(plan),
		"the whole crew's told what to do, and the host's map is to be fetched afresh (%s)" % said)
	AdventureTrip.host_refresh = {}
	Shed.adventure = was_adv
	Shed.crew = was_crew
	AdventurePlans.forget(plan)
	CellStore.dir = was[0]
	CellStore.offline = was[1]
	RealRegion.cell_dirs = was[2]
	HeightTiles.dirs = was[3]
	HeightTiles.offline = was[4]
	HeightTiles.reset()
	CellStore.forget_index()
	RealRegion.forget_areas()
	PlaceProfile.forget()
	RegionKit.forget()
	RegionStore._remove_tree(store)


## The host decides the map: the ride carries the host's place profiles and copies of its cells (AdventureCrew.host_map),
## and a guest's game takes them in place of its own (use_host_map), so the two can't differ over a guess or an older copy.
func test_host_map() -> void:
	var was := [RealRegion.cell_dirs, CellStore.dir, CellStore.offline]
	var store := "user://test_host_map"
	RegionStore._remove_tree(store)
	DirAccess.make_dir_recursive_absolute(store.path_join("c577_711"))
	for f in DirAccess.get_files_at("res://tests/fixtures/cells/c577_711"):
		DirAccess.copy_absolute("res://tests/fixtures/cells/c577_711".path_join(f), store.path_join("c577_711").path_join(f))
	var dirs: Array[String] = [store]
	RealRegion.cell_dirs = dirs
	CellStore.dir = store
	CellStore.offline = true
	CellStore.forget_index()
	PlaceProfile.forget()
	RegionKit.forget()
	var a := Vector2i(577, 711)
	var area := "area:@577_711,577_712"
	# The host: what it has, the profile it rode with and its copy of the cell.
	var host_profile := PlaceProfile.parse({"format": PlaceProfile.FORMAT, "cell": "577_711", "lat": 54.3, "lon": -2.1, "country": "GB",
		"hash": "hostprofile0", "guessed": false})
	PlaceProfile.pin("577_711", host_profile)
	var map := AdventureCrew.host_map(area)
	var meta = JSON.parse_string(FileAccess.get_file_as_string(store.path_join("c577_711/region.json")))
	check(str(map["profiles"]["577_711"]["hash"]) == "hostprofile0" and not (map["profiles"] as Dictionary).has("577_712"),
		"the host's map carries the profiles it has (not ones it would have to fetch)")
	check(str(map["cells"]["577_711"]["meta"]) == str(meta["hash"]) and not (map["cells"] as Dictionary).has("577_712"),
		"and the copy of each cell it has, by its hash")
	check(AdventureCrew.host_map("dales").is_empty(), "a bundled region needs no map")
	# The guest: it had guessed that cell's profile; it takes the host's.
	PlaceProfile.forget()
	check(bool(PlaceProfile.of_cell(a)["guessed"]), "the guest's game guessed the profile")
	var url := AdventureCrew.STORE_RELEASES + "cells-x/c577_711-abc.zip"
	map["cells"]["577_711"]["hash"] = "abc"
	map["cells"]["577_711"]["url"] = url
	var fetch := AdventureCrew.use_host_map({"map": map})
	check(str(PlaceProfile.of_cell(a)["hash"]) == "hostprofile0" and not PlaceProfile.of_cell(a)["guessed"], "and rides the host's instead")
	check(fetch.is_empty(), "the same copy of the cell as the host's: nothing to fetch")
	check(not AdventureCrew.use_host_map({"map": map}).size() and str(PlaceProfile.of_cell(a)["hash"]) == "hostprofile0", "taking it again changes nothing")
	map["cells"]["577_711"]["meta"] = "newer"
	map["cells"]["577_712"] = {"meta": "m2", "hash": "h2", "url": AdventureCrew.STORE_RELEASES + "cells-x/c577_712-h2.zip"}
	fetch = AdventureCrew.use_host_map({"map": map})
	check(str(fetch.get("577_711", {}).get("url", "")) == url and (fetch as Dictionary).has("577_712"),
		"a cell the host has another copy of, or the guest hasn't got, is fetched as the host has it (%s)" % str(fetch.keys()))
	map["cells"]["577_711"]["url"] = "https://example.com/c577_711.zip"
	fetch = AdventureCrew.use_host_map({"map": map})
	check(not (fetch as Dictionary).has("577_711"), "but only from the world's store")
	check(AdventureCrew.use_host_map({}).is_empty() and AdventureCrew.use_host_map({"map": "junk"}).is_empty(), "no map, or junk: nothing")
	RealRegion.cell_dirs = was[0]
	CellStore.dir = was[1]
	CellStore.offline = was[2]
	CellStore.forget_index()
	RealRegion.forget_areas()
	PlaceProfile.forget()
	RegionKit.forget()
	RegionStore._remove_tree(store)
