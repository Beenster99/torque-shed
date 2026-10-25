extends RefCounted
## The in-game route planner's checks (RoutePlanner planning over a RealRegion), run from tests/run_tests.gd: its
## _test_planner_* functions hand over to these.

const REGION := "shodoshima"
const CellsTests := preload("res://tests/cells_tests.gd")
## Two ends of Shodoshima (where its first baked road ran, about 24 km apart by road).
const START := Vector2(34.518638, 134.269646)
const END := Vector2(34.499373, 134.347915)

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func pins() -> Array:
	var r := RealRegion.get_region(REGION)
	return [r.geo_to_xz(START.x, START.y), r.geo_to_xz(END.x, END.y)]


## Two places across the island, planned by the game: the road between them on the land it crosses.
func test_plan() -> void:
	var r := RealRegion.get_region(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	check(bool(res["ok"]), "the planner plans a route between two pins (%s)" % str(res["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	check(p.max_km() > 20.0 and p.max_km() < 30.0, "%.1f km (the baker's road between them was 24 km)" % p.max_km())
	check(p.x.size() == p.z.size() and p.x.size() == p.e.size() and p.chunks.size() == int(ceil((p.x.size() - 1) / 32.0)),
		"a knot every 4 m with a height each, and a row for each chunk")
	# The road rides on the land it crosses (smoothed over the bumps).
	var on := 0
	var known := 0
	for k in range(0, p.x.size(), 25):
		var h := p.terrain.height(p.x[k], p.z[k])
		if is_nan(h):
			continue
		known += 1
		on += int(absf(h - p.e[k]) < 6.0)
	check(known > p.x.size() / 25 * 0.9 and on > known * 0.9, "it lies on the land (%d of %d points within 6 m)" % [on, known])
	# No bend tighter than the bike's, no climb steeper than the grade.
	var tight := 0
	var steep := 0.0
	for i in range(1, p.x.size() - 1):
		var a := Vector2(p.x[i - 1], p.z[i - 1])
		var b := Vector2(p.x[i], p.z[i])
		var c := Vector2(p.x[i + 1], p.z[i + 1])
		var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
		if 2.0 * cross / maxf(a.distance_to(b) * b.distance_to(c) * a.distance_to(c), 1e-9) > 1.0 / 8.0:
			tight += 1
		steep = maxf(steep, absf(p.e[i + 1] - p.e[i]) / RoutePlanner.STEP)
	check(tight == 0 and steep <= 0.151, "no bend tighter than 8 m radius and no grade over %.1f%%" % (steep * 100.0))
	check(p.junctions.size() > 5 and p.pois.size() > 5 and p.building_count > 100 and p.buildings.size() > 5,
		"with %d junctions, %d places to stop and %d buildings along it" % [p.junctions.size(), p.pois.size(), p.building_count])
	var limited := 0
	for row: Array in p.chunks:
		if int(row[4]) > 0:
			limited += 1
	check(limited == p.chunks.size() and p.name_at(0.0) != "" and p.turns.size() > 5 and str(p.turns[p.turns.size() - 1]["turn"]) == "arrive",
		"every chunk has a name and a limit, and there are turns to the arrival")


## The same pins plan the same route, every time (and on every machine: the hash says so); other pins another.
func test_deterministic() -> void:
	var r := RealRegion.get_region(REGION)
	var a := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	var b := RoutePlanner.plan(r, {"pins": pins(), "mode": "main", "seed": 1})
	check(bool(a["ok"]) and bool(b["ok"]) and (a["pack"] as RealPack).hash == (b["pack"] as RealPack).hash and (a["pack"] as RealPack).x == (b["pack"] as RealPack).x,
		"the same pins plan the same road, with the same hash")
	var c := RoutePlanner.plan(r, {"pins": pins(), "mode": "scenic", "seed": 1})
	check(bool(c["ok"]) and (c["pack"] as RealPack).hash != (a["pack"] as RealPack).hash, "another style of ride is another road")
	var d := RoutePlanner.plan(r, {"pins": [pins()[0], r.geo_to_xz(34.53, 134.22)], "mode": "main"})
	check(bool(d["ok"]) and (d["pack"] as RealPack).hash != (a["pack"] as RealPack).hash and (d["pack"] as RealPack).max_km() < (a["pack"] as RealPack).max_km(),
		"and other pins another")


## Mistakes come back as words, not crashes.
func test_errors() -> void:
	var r := RealRegion.get_region(REGION)
	check(not bool(RoutePlanner.plan(r, {"pins": [Vector2.ZERO]})["ok"]), "one pin is not a journey")
	var far := RoutePlanner.plan(r, {"pins": [pins()[0], Vector2(90000, 90000)]})
	check(not bool(far["ok"]) and str(far["error"]).contains("far"), "a pin in the sea is too far from a road: \"%s\"" % str(far["error"]))
	var same := RoutePlanner.plan(r, {"pins": [pins()[0], pins()[0]]})
	check(not bool(same["ok"]), "the same place twice is nowhere to get to")
	check(not bool(RoutePlanner.plan(r, {"pins": pins(), "mode": "flying"})["ok"]), "and there is no flying style of ride")


## Planning is a job for a worker thread: it must not fill a frame (the heights and tiles load on first use, so the
## second plan is the one timed).
func test_speed() -> void:
	var r := RealRegion.get_region(REGION)
	RoutePlanner.plan(r, {"pins": pins()})
	var res := RoutePlanner.plan(r, {"pins": pins()})
	check(int(res["ms"]) < 4000, "a %.0f km route plans in %d ms %s" % [(res["pack"] as RealPack).max_km(), int(res["ms"]), str(res["parts"])])


## The planned road is ridden: the world builds it and streams it end to end.
func test_ride() -> void:
	var r := RealRegion.get_region(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "main"})
	var p: RealPack = res["pack"]
	RealPack.register(p)
	check(RealPack.get_pack(p.id) == p, "a planned road is found by its id")
	var w := AdventureWorld.new()
	w.setup(p, 5, 10.0)
	check(w.route.real == p and absf(w.route.length - 10000.0) < 0.1, "the world rides the planned road (%.1f km)" % (w.route.length / 1000.0))
	var spot := {}
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	var s := 20.0
	while s < w.route.total - 100.0:
		s += 100.0
		spot["p"] = w.transform_at(s).origin
		await t.get_tree().process_frame
		var held := Time.get_ticks_msec()
		while not w.chunks.has(AdventureRoute.chunk_of(minf(s + 300.0, w.route.total - 1.0))) and Time.get_ticks_msec() - held < 4000:
			await t.get_tree().process_frame
	check(w.chunks.has(AdventureRoute.chunk_of(s)), "and streams it from start to finish (%d chunks freed behind)" % int(w.stats["freed"]))
	w.queue_free()
	await t.get_tree().process_frame


## The crew's pins on the shared board: anyone adds, moves along, removes; the plan comes out; the host starts it.
## "I'm in": each rider says so for the journey as it stands; a pin moved or the style changed clears them, and the
## host's Start waits for everyone in the shed (or most of them). On their own, a rider just starts.
func test_im_in() -> void:
	var saved_adventure = Shed.adventure
	var saved_crew: Dictionary = Shed.crew.duplicate(true)
	Shed.adventure = {}
	Shed.journey = {}
	var me := Shed.me()
	Shed.crew = {me: {"name": "Sam"}}
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	Shed.request({"a": "adventure_pin", "region": REGION, "x": a.x, "z": a.y})
	Shed.request({"a": "adventure_in", "in": true})
	check(AdventureJourney.riders_in(Shed.journey).is_empty(), "one pin is nothing to be in on")
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	check(not AdventureJourney.needs_crew() and AdventureJourney.start_reason(Shed.journey) == "" and AdventureJourney.crew_line(Shed.journey) == "",
		"on your own, nobody need say they're in: you just start")
	# A crew of three: the host (this game), Jo and Kit.
	Shed.crew[2] = {"name": "Jo"}
	Shed.crew[3] = {"name": "Kit"}
	check(AdventureJourney.start_reason(Shed.journey).begins_with("Waiting for the crew: 0 of 3"),
		"with a crew, the host waits for them (%s)" % AdventureJourney.start_reason(Shed.journey))
	Shed.request({"a": "adventure_in", "in": true})
	Shed._apply(2, {"a": "adventure_in", "in": true})
	check(AdventureJourney.riders_in(Shed.journey) == ([me, 2] as Array[int]) and AdventureJourney.start_reason(Shed.journey) == ""
		and AdventureJourney.crew_line(Shed.journey).ends_with("in; waiting for Kit."),
		"two of three in: the host can start without the one who wandered off (%s)" % AdventureJourney.crew_line(Shed.journey))
	check(AdventureJourney.sanitize(Shed.journey) == Shed.journey, "who's in goes to the crew with the board")
	Shed._apply(3, {"a": "adventure_in", "in": true})
	check(AdventureJourney.crew_line(Shed.journey) == "Everyone's in.", "then everyone's in")
	Shed._apply(2, {"a": "adventure_in", "in": false})
	check(AdventureJourney.riders_in(Shed.journey) == ([me, 3] as Array[int]), "a rider can change their mind")
	Shed.request({"a": "adventure_view", "view": {"span": 20000.0}})
	check(AdventureJourney.riders_in(Shed.journey).size() == 2, "looking about the map changes nobody's say-so")
	Shed.request({"a": "adventure_mode", "mode": "scenic"})
	check(AdventureJourney.riders_in(Shed.journey).is_empty() and AdventureJourney.start_reason(Shed.journey) != "",
		"another style of ride is another journey: everyone's in is cleared")
	for p in [me, 2]:
		Shed._apply(p, {"a": "adventure_in", "in": true})
	Shed._apply(3, {"a": "adventure_unpin", "i": 1})
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	check(AdventureJourney.riders_in(Shed.journey).is_empty(), "and so is a pin moved")
	# One who's left the shed doesn't count either way.
	Shed._apply(2, {"a": "adventure_in", "in": true})
	Shed.crew.erase(3)
	check(AdventureJourney.riders_in(Shed.journey) == ([2] as Array[int]) and AdventureJourney.start_reason(Shed.journey).begins_with("Waiting for the crew: 1 of 2"),
		"only the riders in the shed count (%s)" % AdventureJourney.start_reason(Shed.journey))
	Shed.request({"a": "adventure_in", "in": true})
	Shed.request({"a": "adventure_start", "plan": AdventureJourney.plan_of(Shed.journey), "seed": 7, "title": "Over the tops"})
	check(Adventure.active() and not Shed.journey.has("in"), "once the ride starts, the next is to be agreed afresh")
	Shed.adventure = saved_adventure
	Shed.journey = {}
	Shed.crew = saved_crew


## Journeys kept: a ride's pins and style kept in each rider's diary, listed on the TV's Past rides to pin again with
## a touch, and a journey's code to paste to a mate.
func test_journeys_kept() -> void:
	var saved_adventure = Shed.adventure
	Shed.adventure = {}
	Shed.journey = {}
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	Shed.request({"a": "adventure_pin", "region": REGION, "x": a.x, "z": a.y})
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	Shed.request({"a": "adventure_mode", "mode": "scenic"})
	var board: Dictionary = Shed.journey.duplicate(true)
	var kept := AdventureJourney.kept_of(board)
	var code := AdventureJourney.code_of(kept)
	check(code.begins_with("TS1.") and code.length() < 200 and AdventureJourney.from_code("Ride this: %s !" % code) == kept,
		"a journey is a code (%d characters) that comes back the same, wherever it's pasted" % code.length())
	check(AdventureJourney.from_code("TS1.bm9wZQ").is_empty() and AdventureJourney.from_code("nothing here").is_empty()
		and AdventureJourney.sanitize_kept({"pins": [[95.0, 0.0, ""], [0.0, 0.0, ""]]}).is_empty(), "a code that isn't a journey is no journey")
	var from_plan := AdventureJourney.kept_of_plan(AdventureJourney.plan_of(board))
	var near := true
	for i in 2:
		near = near and Vector2(from_plan["pins"][i][0], from_plan["pins"][i][1]).distance_to(Vector2(kept["pins"][i][0], kept["pins"][i][1])) < 1e-4
	check(near and from_plan["mode"] == "scenic" and from_plan["pins"][1][2] == kept["pins"][1][2], "a ride's plan keeps the same journey")
	# Pinned again (a past ride, or a code pasted): the same pins on the same map, the same style.
	Shed.request({"a": "adventure_clear"})
	Shed.request({"a": "adventure_load", "journey": kept})
	var back := (Shed.journey.get("pins", []) as Array)
	check(back.size() == 2 and str(Shed.journey["region"]) == str(board["region"]) and str(Shed.journey["mode"]) == "scenic"
		and Vector2(back[1]["x"], back[1]["z"]).distance_to(Vector2(board["pins"][1]["x"], board["pins"][1]["z"])) < 1.0
		and AdventurePlans.key(AdventureJourney.plan_of(Shed.journey)) == AdventurePlans.key(AdventureJourney.plan_of(board)),
		"pinned again, it's the same journey, planned the same (%s on %s, against %s on %s)" % [str(back.map(func(p): return Vector2(p["x"], p["z"]))),
			Shed.journey.get("region", ""), str((board["pins"] as Array).map(func(p): return Vector2(p["x"], p["z"]))), board["region"]])
	check(AdventureJourney.check(1, {"a": "adventure_load", "journey": {"pins": [[1.0, 2.0, ""]]}}) != "", "one pin isn't a journey to load")
	# The diary keeps it, and the TV lists it.
	var root := "user://test_kept_diaries"
	RegionStore._remove_tree(root)
	AdventureDiary.root = root
	AdventureDiary.save_diary({"id": "ride1", "title": "Over the tops", "km": 31.0, "date": "2026-10-24", "journey": from_plan, "saved_at": 5})
	AdventureDiary.save_diary({"id": "ride0", "title": "No pins kept", "km": 12.0, "date": "2026-10-01", "saved_at": 2})
	var rides := RouteTv.past_rides()
	check(rides.size() == 1 and str(rides[0]["title"]) == "Over the tops" and AdventureJourney.sanitize_kept(rides[0]["journey"]) == from_plan,
		"each rider's diary keeps the ride's journey, and the TV's Past rides lists it")
	var dash := Dashboard.new("route", 3.4)
	t.add_child(dash)
	dash.show_page("route", {})
	var tv: RouteTv = dash._route
	Shed.request({"a": "adventure_clear"})
	tv.ask({"tab": "rides"})
	await _settle(func(): return tv._rides_box.visible and tv._past.get_child_count() == 1 and tv._past.get_child(0) is Button)
	var row: Button = tv._past.get_child(0) if tv._past.get_child_count() > 0 else null
	check(row != null and row.text.begins_with("Over the tops  (31 km"), "Past rides on the TV (%s)" % (row.text if row else "nothing"))
	if row != null:
		row.pressed.emit()
	await _settle(func(): return (Shed.journey.get("pins", []) as Array).size() == 2 and tv._plan_box.visible)
	check((Shed.journey.get("pins", []) as Array).size() == 2 and str(Shed.route_tv.get("tab", "")) == "plan" and float(Shed.route_tv.get("span", 0.0)) < 100000.0,
		"a touch pins it for the crew and shows it on the map")
	dash.queue_free()
	await t.get_tree().process_frame
	RegionStore._remove_tree(root)
	AdventureDiary.root = "user://diaries"
	Shed.adventure = saved_adventure
	Shed.journey = {}
	Shed.route_tv = {}


func test_board() -> void:
	var r := RealRegion.get_region(REGION)
	var saved_adventure = Shed.adventure
	Shed.adventure = {}
	Shed.journey = {}
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	Shed.request({"a": "adventure_pin", "region": REGION, "x": a.x + 40.0, "z": a.y - 30.0})
	check(Shed.journey.has("pins") and (Shed.journey["pins"] as Array).size() == 1, "a pin goes on the board")
	var first: Dictionary = (Shed.journey["pins"] as Array)[0]
	check(r.node_pos[r.nearest_node(float(first["x"]), float(first["z"]), 5.0)].distance_to(Vector2(float(first["x"]), float(first["z"]))) < 0.2,
		"on a road junction (%s)" % str(first))
	check(AdventureJourney.plan_of(Shed.journey).is_empty(), "one pin is no plan yet")
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
	check((Shed.journey["pins"] as Array).size() == 2, "the same place twice in a row isn't put down again")
	var plan := AdventureJourney.plan_of(Shed.journey)
	check(not plan.is_empty() and (plan["pins"] as Array).size() == 2 and plan["region_hash"] == r.hash, "two pins make a plan")
	var res := AdventurePlans.result(plan, true)
	check(bool(res["ok"]) and AdventurePlans.result(plan, true)["pack"] == res["pack"], "that is planned once and kept (%.1f km)" % (res["pack"] as RealPack).max_km())
	Shed.request({"a": "adventure_pin", "region": REGION, "x": 1.0e6, "z": 0.0})
	check((Shed.journey["pins"] as Array).size() == 2, "a pin far from any road is refused")
	Shed.request({"a": "adventure_mode", "mode": "scenic"})
	var scenic := AdventureJourney.plan_of(Shed.journey)
	check(AdventurePlans.key(scenic) != AdventurePlans.key(plan) and str(Shed.journey["mode"]) == "scenic", "another style of ride is another plan")
	# Round trip through the sync (the other players get it like this).
	check(AdventureJourney.sanitize(Shed.journey) == Shed.journey, "the board survives being sent to the crew")
	# The host starts it.
	Shed.request({"a": "adventure_mode", "mode": "main"})
	var go := AdventureJourney.plan_of(Shed.journey)
	Shed.request({"a": "adventure_start", "plan": go, "seed": 77, "title": "Across the island"})
	var adv: Dictionary = Shed.adventure
	check(int(adv.get("id", 0)) != 0 and adv.get("plan") is Dictionary and str(adv["real"]).begins_with("plan_"), "the host starts the adventure along the plan")
	var pack := RealPack.get_pack(str(adv.get("real", "")))
	check(pack != null and pack.hash == str(adv["real_hash"]) and absf(float(adv["km"]) - pack.max_km()) < 0.11 and str(adv["theme"]) == "coastal",
		"it is ridden at the road's own length (%.1f km), dressed for the coast" % float(adv.get("km", 0.0)))
	check(AdventureTrip.real_mismatch(adv) == "", "and this game agrees it is the host's road")
	var other := adv.duplicate(true)
	other["real_hash"] = "0000000000000000"
	check(AdventureTrip.real_mismatch(other) != "", "while a road that came out differently is refused: \"%s\"" % AdventureTrip.real_mismatch(other))
	var gone := adv.duplicate(true)
	(gone["plan"] as Dictionary)["region"] = "nowhere"
	check(AdventureTrip.real_mismatch(gone) != "", "as is a map this game doesn't have")
	var kept := Adventure.sanitize(adv)
	check(kept.get("plan") is Dictionary and kept["real"] == adv["real"] and kept["real_hash"] == adv["real_hash"], "a joiner's copy keeps the plan")
	Shed.request({"a": "adventure_clear"})
	check(Shed.journey.is_empty(), "the board is wiped clean")
	Shed.adventure = saved_adventure


## The Esc menu's planner (JourneyMap): the TVs' planner full screen, with the mouse. It opens on the crew's view,
## fills the screen keeping its shape, a click is a touch (it pins a road), the wheel zooms about the pointer for the
## whole crew, and it folds itself away when the ride starts.
func test_map() -> void:
	_world_fixtures(true)
	Shed.adventure = {}
	Shed.journey = {}
	var dale := _dales_place("Gunnerside").lerp(_dales_place("Grinton"), 0.5)
	Shed.route_tv = AdventureJourney.sanitize_view({"lat": dale.x, "lon": dale.y, "span": 20000.0})
	var map := JourneyMap.new()
	t.add_child(map)
	map.open()
	var p: RouteTv = map.planner
	await _settle(func(): return p != null and p._warm >= 8 and p.view.roads_shown() and not p.view.busy())
	var k := map._frame.scale.x
	check(map.visible and p.visible and k > 0.5 and is_equal_approx(map._frame.scale.y, k) and is_equal_approx(p.view.span, 20000.0)
		and p.view.roads_shown(), "the full-screen planner is the TVs' planner, on the crew's view and its roads (scaled %.2f)" % k)
	# A click pins a road, as a touch does.
	var g := _dales_place("Gunnerside")
	var at := p.view.to_screen(g.x, g.y)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	p.view._gui_input(ev)
	await _settle(func(): return (Shed.journey.get("pins", []) as Array).size() == 1)
	check((Shed.journey.get("pins", []) as Array).size() == 1, "a click on a road pins it")
	# The wheel: closer, about the pointer (the place under it stays put), for everyone.
	var corner := Vector2(p.view.size.x * 0.25, p.view.size.y * 0.3)
	var under := p.view.to_geo(corner)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = corner
	p.view._gui_input(wheel)
	await _settle(func(): return p.view.span < 20000.0)
	var still := p.view.to_geo(corner)
	check(is_equal_approx(float(Shed.route_tv["span"]), 20000.0 / WorldView.WHEEL_ZOOM) and still.distance_to(under) < 1e-4,
		"the wheel zooms the crew's view about the pointer (%.0f m across, the place under it moved %.6f deg)" % [p.view.span, still.distance_to(under)])
	# It folds away when the ride starts.
	var shut := [false]
	map.closed.connect(func(): shut[0] = true)
	Shed.adventure = {"id": 1}   # (an adventure on, as Adventure.active() sees it)
	await _settle(func(): return shut[0])
	check(shut[0], "and it folds itself away when the ride starts")
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	map.queue_free()
	await t.get_tree().process_frame
	_world_fixtures(false)


## A map link pasted on the planner (MapLink, RouteTv.paste_link): Google's, Apple's and OpenStreetMap's ways of saying
## where, plain "lat, lon", a short link followed through its redirects, and nothing where a link says nowhere.
func test_map_links() -> void:
	var cases := {
		"https://www.google.com/maps/@54.3801,-2.0123,13z": Vector2(54.3801, -2.0123),
		"https://www.google.com/maps/place/Reeth/@54.38,-1.95,15z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d54.3888!4d-1.9455": Vector2(54.3888, -1.9455),
		"https://maps.google.com/?q=34.48,134.25": Vector2(34.48, 134.25),
		"https://maps.apple.com/?ll=51.5007%2C-0.1246&q=Big%20Ben": Vector2(51.5007, -0.1246),
		"https://www.openstreetmap.org/#map=14/54.2988/-2.2001": Vector2(54.2988, -2.2001),
		"https://www.openstreetmap.org/?mlat=35.0&mlon=135.75#map=12/35.0/135.75": Vector2(35.0, 135.75),
		"  54.31, -1.83 ": Vector2(54.31, -1.83),
	}
	var all_ok := true
	for text in cases:
		var got := MapLink.parse(text)
		if got == Vector2.INF or got.distance_to(cases[text]) > 1e-5:
			all_ok = false
			print("  (link %s -> %s)" % [text, str(got)])
	check(all_ok, "Google's, Apple's and OpenStreetMap's links, and plain lat, lon, say where (%d of them)" % cases.size())
	check(MapLink.parse("https://www.google.com/maps") == Vector2.INF and MapLink.parse("hello") == Vector2.INF and MapLink.parse("95.0, 10.0") == Vector2.INF
		and MapLink.needs_following("https://maps.app.goo.gl/AbC123") and not MapLink.needs_following("54.3, -2.0"),
		"a link that says nowhere, or junk, is nowhere; a short link is to be followed")
	# A short link, followed: a stand-in plays the link service.
	var host := CellsTests.FakeHost.new()
	host.start()
	host.redirects["/s/abc"] = "http://127.0.0.1:%d/maps/place/Tonosho/@34.4870,134.1860,14z" % host.port
	var was_offline := CellStore.offline
	CellStore.offline = false
	var got := [Vector2.ZERO]
	var task := WorkerThreadPool.add_task(func(): got[0] = MapLink.resolve("http://127.0.0.1:%d/s/abc" % host.port))
	while not WorkerThreadPool.is_task_completed(task):
		host.serve()
		await t.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	host.stop()
	CellStore.offline = was_offline
	check((got[0] as Vector2).distance_to(Vector2(34.487, 134.186)) < 1e-5, "a short link is followed to where it points (%s)" % str(got[0]))
	# On the planner: pasted, the crew's view goes there.
	Shed.route_tv = {}
	var dash := Dashboard.new("route", 3.4)
	t.add_child(dash)
	dash.show_page("route", {})
	var board: RouteTv = dash._route
	await _settle(func(): return board != null and board._warm >= 8)
	board.paste_link("https://www.google.com/maps/@54.3801,-2.0123,13z")
	await _settle(func(): return Shed.route_tv.has("lat"))
	check(absf(float(Shed.route_tv.get("lat", 0.0)) - 54.3801) < 1e-5 and is_equal_approx(float(Shed.route_tv.get("span", 0.0)), RouteTv.FOUND_SPAN),
		"pasted on the planner, the crew's view goes there")
	check(RouteTv.credits_line(["Elevation: Mapterhorn (mapterhorn.com)...", "Roads: (c) OpenStreetMap contributors and others, Overture Maps Foundation (ODbL)."])
		== "Map data: roads © OpenStreetMap contributors and Overture Maps (ODbL); heights Mapterhorn.", "a road's map data is credited in a line")
	Shed.route_tv = {}
	dash.queue_free()
	await t.get_tree().process_frame


## The Swaledale cells and their land, for the world on the TV (see tests/cells_tests.gd); offline, with no index of
## the world's cells, so nothing is fetched.
func _world_fixtures(on: bool) -> void:
	var dirs: Array[String] = ["res://tests/fixtures/cells"]
	if not on:
		dirs = ["res://data/cells", "user://cells"]
	RealRegion.cell_dirs = dirs
	var heights: Array[String] = ["res://tests/fixtures/heights"]
	if not on:
		heights = ["res://data/heights"]
	HeightTiles.dirs = heights
	HeightTiles.offline = on
	HeightTiles.reset()
	CellStore.offline = on
	CellStore.dir = "user://test_no_cells" if on else "user://cells"
	CellStore.forget_index()
	RealRegion.forget_areas()


## (lat, lon) of a place in the Swaledale cells, by name.
func _dales_place(name: String) -> Vector2:
	var dales := RealRegion.get_region("dales")
	var xz: Vector2 = {"Gunnerside": Vector2(-2422, -4363), "Grinton": Vector2(7187, -4599)}[name]
	var g := dales.xz_to_geo(xz.x, xz.y)
	return Vector2(g[0], g[1])


## The route planner channel: a Dashboard page of kind "route" holding the planner (RouteTv) and the world on it
## (WorldView). Touched like any shed screen (a click into the page): the world first, a search that takes the crew to a
## place, a touch on the world that looks closer, the roads of the cells there, pins on them anywhere, the road the
## game plans between them, and the host's Start.
func test_tv() -> void:
	_world_fixtures(true)
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	var dash := Dashboard.new("route", 3.4)
	t.add_child(dash)
	dash.show_page("route", {})
	var board: RouteTv = dash._route
	# (the controls lay themselves out over the first frames: touches wait for that)
	await _settle(func(): return board != null and WorldMap.loaded() and not board.view.busy() and board._warm >= 8)
	check(board != null and board.visible and WorldMap.mesh("land") != null and board.view.span > 10000000.0,
		"the route planner shows the world (%.0f km across)" % (board.view.span / 1000.0 if board else 0.0))
	check(dash.kind == "route" and TvChannels.channels_for("f1").has("route") and TvChannels.channels_for("crew").has("route")
		and TvChannels.channels_for("bay0").has("route") and not TvChannels.screen_exists("route"),
		"it is a channel every TV has (the crew board and the bay screens too), not a screen of its own")
	# Find a place: the tab, a few letters, and a touch on what it finds takes the crew there.
	var tab: Button = board._tab_buttons["find"]
	dash.tap(tab.global_position + tab.size * 0.5)
	await _settle(func(): return board._find_box.visible)
	for ch in "LEEDS":
		var key := _key(board, ch)
		dash.tap(key.global_position + key.size * 0.5)
		await _settle(func(): return board._q().ends_with(ch.to_lower()))
	await _settle(func(): return board._results.get_child_count() > 0 and board._results.get_child(0) is Button)
	var hit: Button = board._results.get_child(0) if board._results.get_child_count() > 0 else null
	check(str(Shed.route_tv.get("q", "")) == "leeds" and hit is Button and (hit as Button).text.begins_with("Leeds"),
		"the keyboard types a search for every TV, and it finds Leeds (%s; typed %s, %d rows, tab %s)" % [(hit as Button).text if hit is Button else "nothing",
			str(Shed.route_tv.get("q", "")), board._results.get_child_count(), board._tab()])
	dash.tap(hit.global_position + hit.size * 0.5)
	await _settle(func(): return board._plan_box.visible and board.view.span < 100000.0)
	check(absf(board.view.lat - 53.8) < 0.2 and absf(board.view.lon + 1.55) < 0.2 and board.view.span <= RouteTv.FOUND_SPAN
		and str(Shed.route_tv.get("q", "x")) == "", "and a touch on it takes the crew there, close in (%.2f, %.2f)" % [board.view.lat, board.view.lon])
	# Out over the world a touch looks closer; Swaledale has roads.
	board.ask({"lat": 54.0, "lon": -2.0, "span": 2000000.0})
	await _settle(func(): return board.view.span > 1000000.0)
	var dale := _dales_place("Gunnerside").lerp(_dales_place("Grinton"), 0.5)
	dash.tap(board.view.global_position + board.view.to_screen(dale.x, dale.y))
	await _settle(func(): return board.view.span < 1000000.0)
	check(is_equal_approx(board.view.span, 2000000.0 / WorldView.TOUCH_ZOOM) and Shed.journey.is_empty(),
		"a touch on the world looks closer there, and pins nothing (%.0f km across)" % (board.view.span / 1000.0))
	board.ask({"lat": dale.x, "lon": dale.y, "span": 20000.0})
	await _settle(func(): return board.view.roads_shown() and not board.view.busy())
	check(board.view.roads_shown() and board.view.roads.id.begins_with(RealRegion.CELLS_PREFIX) and board.view.roads.edge_count() > 1000,
		"close in, the roads of the cells there are on the map (%d)" % (board.view.roads.edge_count() if board.view.roads else 0))
	# Pins on the roads: a journey anywhere, on the cells it needs.
	for name in ["Gunnerside", "Grinton"]:
		var g := _dales_place(name)
		var before := (Shed.journey.get("pins", []) as Array).size()
		dash.tap(board.view.global_position + board.view.to_screen(g.x, g.y))
		await _settle(func(): return (Shed.journey.get("pins", []) as Array).size() > before)
	var pins: Array = Shed.journey.get("pins", [])
	check(pins.size() == 2 and AdventureJourney.anywhere(Shed.journey) and pins[0].has("lat")
		and RealRegion.cells_of_area(str(Shed.journey["region"])).has(Vector2i(577, 711)),
		"a touch on a road pins it, the journey on the cells it needs (%s)" % str(Shed.journey.get("region", "")))
	var end := Time.get_ticks_msec() + 60000
	while board.view.route_geo.size() < 2 and Time.get_ticks_msec() < end:
		await t.get_tree().create_timer(0.1).timeout
	check(board.view.route_geo.size() > 100 and "km" in board._facts.text and not board._start.disabled,
		"the planned road is on the map, its facts on the panel and Start lit (%s)" % board._facts.text.split("\n")[0])
	check(board._pins.get_child_count() >= 2, "each pin is listed")
	var scenic: Button = board._mode_buttons["scenic"]
	dash.tap(scenic.global_position + scenic.size * 0.5)
	await t.get_tree().process_frame
	check(str(Shed.journey["mode"]) == "scenic", "a touch on Scenic changes the style for everyone")
	# (back to Quick: the land under the scenic way isn't in the test's map tiles, and there's no network)
	var quick: Button = board._mode_buttons["main"]
	dash.tap(quick.global_position + quick.size * 0.5)
	await t.get_tree().process_frame
	# A pin taken off with a touch, and put back.
	var first := AdventureJourney.pin_geo(Shed.journey, 0)
	dash.tap(board.view.global_position + board.view.to_screen(first.x, first.y))
	await _settle(func(): return (Shed.journey.get("pins", []) as Array).size() == 1)
	check((Shed.journey["pins"] as Array).size() == 1 and str(Shed.journey["pins"][0]["name"]) != "", "a touch on a pin takes it off")
	Shed.request({"a": "adventure_pin", "lat": first.x, "lon": first.y, "name": "Gunnerside", "at": 0})
	# The host starts it, once the panel has caught up with the board (its new road planned).
	end = Time.get_ticks_msec() + 60000
	while not (board._sig == board._signature() and JourneyMap.plan_ok(AdventureJourney.plan_of(Shed.journey)) and not board._start.disabled) \
			and Time.get_ticks_msec() < end:
		await t.get_tree().create_timer(0.1).timeout
	dash.tap(board._start.global_position + board._start.size * 0.5)
	await _settle(func(): return Adventure.active())
	check(Adventure.active() and Shed.adventure.get("plan") is Dictionary and str(Shed.adventure["real"]).begins_with("plan_"),
		"and a touch on Start starts the ride along it")
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	dash.queue_free()
	await t.get_tree().process_frame
	_world_fixtures(false)


func _key(board: RouteTv, ch: String) -> Button:
	for line in board._find_box.get_children():
		if line is HBoxContainer:
			for b in line.get_children():
				if b is Button and (b as Button).text == ch:
					return b
	return null


## Survey (Survey, the survey worker): over cells nobody has mapped, the TV offers it; a touch asks the surveyors
## (through the host) for the cells in view, every TV says they're being surveyed, and when the cells come into the
## world's index the roads are fetched and drawn. A stand-in on this machine plays GitHub and the survey worker.
func test_survey() -> void:
	_world_fixtures(true)
	var cells_tests := CellsTests.new(t)
	var host := CellsTests.FakeHost.new()
	check(host.start(), "a stand-in for GitHub and the surveyors listens on this machine")
	var store := "user://test_survey_cells"
	RegionStore._remove_tree(store)
	var index := {"format": 1, "release": "2026-10-21.0", "cells": {}}
	host.files["/index.json"] = JSON.stringify(index).to_utf8_buffer()
	host.files["/survey"] = JSON.stringify({"status": "baking", "cells": ["577_711", "577_712"], "message": "Surveying 2 cells: about ten minutes."}).to_utf8_buffer()
	CellStore.index_url = "http://127.0.0.1:%d/index.json" % host.port
	CellStore.dir = store
	CellStore.offline = false
	CellStore.forget_index()
	var dirs: Array[String] = [store]
	RealRegion.cell_dirs = dirs
	Survey.url = "http://127.0.0.1:%d/survey" % host.port
	Survey.look_every = 0.5
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	var dash := Dashboard.new("route", 3.4)
	t.add_child(dash)
	dash.show_page("route", {})
	var board: RouteTv = dash._route
	var pump := func(cond: Callable, seconds: float) -> bool:
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		while not cond.call() and Time.get_ticks_msec() < end:
			host.serve()
			Survey.poll()   # (the host's Shed does this each frame in a game)
			await t.get_tree().process_frame
		return cond.call()
	await pump.call(func(): return WorldMap.loaded() and board._warm >= 8, 10.0)
	var dale := _dales_place("Gunnerside").lerp(_dales_place("Grinton"), 0.5)
	board.ask({"lat": dale.x, "lon": dale.y, "span": 20000.0})
	var offered: bool = await pump.call(func(): return board._survey.visible, 20.0)
	check(offered and board.view.unmapped.has(Vector2i(577, 711)),
		"where nobody has baked the cells, the TV offers a survey (%d cells; the Dales bundled with the game drawn meanwhile)" % board.view.unmapped.size())
	dash.tap(board._survey.global_position + board._survey.size * 0.5)
	var asked: bool = await pump.call(func(): return not Survey.going().is_empty(), 20.0)
	var sent = JSON.parse_string(str(host.bodies.get("/survey", "{}")))
	var baking: Array[String] = ["577_711", "577_712"]
	check(asked and sent is Dictionary and (sent["cells"] as Array).has("577_711") and (sent["cells"] as Array).size() == board.view.unmapped.size()
		and Survey.going() == baking,
		"a touch asks the surveyors for the cells in view, and the crew's TVs know which are being baked (%s)" % str(Survey.going()))
	await pump.call(func(): return not board._survey.visible, 5.0)
	check(board.view.shown_note().begins_with("Being surveyed: 2 cells") and not board._survey.visible,
		"the map says they're being surveyed, and there's no second survey to ask for (%s)" % board.view.shown_note())
	# The cells come into the world's index: the TV fetches them and draws their roads.
	for name in ["c577_711", "c577_712"]:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CellsTests.CELLS.path_join(name).path_join("region.json")))
		host.files["/zips/%s.zip" % name] = cells_tests._zip_cell(name)
		index["cells"][name.trim_prefix("c")] = {"hash": meta["hash"], "bytes": (host.files["/zips/%s.zip" % name] as PackedByteArray).size(),
			"url": "http://127.0.0.1:%d/dl/%s" % [host.port, name]}
	host.files["/index.json"] = JSON.stringify(index).to_utf8_buffer()
	var came: bool = await pump.call(func(): return board.view.roads_shown() and board.view.roads.edge_count() > 1000 and not board.view.busy(), 60.0)
	check(came and board.view.surveying().is_empty() and not board.view.unmapped.has(Vector2i(577, 711)) and RealRegion.cell_dir(Vector2i(577, 711)).begins_with(store),
		"when the cells come into the index the TV fetches them and draws their roads (%d)" % (board.view.roads.edge_count() if board.view.roads else 0))
	# Busy surveyors: nothing more is baked, and the map says so.
	host.files["/survey"] = JSON.stringify({"status": "busy", "cells": [], "message": "The surveyors are busy: try again in a few minutes."}).to_utf8_buffer()
	Shed.request({"a": "adventure_survey", "cells": ["100_100"]})
	var answered: bool = await pump.call(func(): return str(Shed.route_tv.get("survey", {}).get("said", "")).begins_with("The surveyors are busy"), 20.0)
	check(answered and Survey.going().is_empty(), "busy surveyors bake nothing, and the crew is told")
	check(AdventureJourney.check(1, {"a": "adventure_survey", "cells": ["no"]}) != "" and Survey.cells_of(["1_1", "1_1", "2_2"]).size() == 2
		and Survey.cells_of(range(17).map(func(i): return "500_%d" % i)).is_empty(), "only cells can be surveyed, and not too many at once")
	host.stop()
	dash.queue_free()
	await t.get_tree().process_frame
	RegionStore._remove_tree(store)
	CellStore.index_url = CellStore.INDEX_URL
	Survey.url = Survey.URL
	Survey.look_every = 60.0
	Shed.route_tv = {}
	_world_fixtures(false)


## Pins anywhere (AdventureJourney): on the cells the journey needs, each pin in that area's frame, worked out again as
## pins go down and come off; a first pin where the game has no cells but a bundled region falls back to it; nowhere
## mapped, too far, and junk are turned down.
func test_anywhere() -> void:
	_world_fixtures(true)
	Shed.adventure = {}
	Shed.journey = {}
	var a := _dales_place("Gunnerside")
	var b := _dales_place("Grinton")
	check(AdventureJourney.check(1, {"a": "adventure_pin", "lat": a.x, "lon": a.y}) == "", "a pin can go down where the game has cells")
	Shed.request({"a": "adventure_pin", "lat": b.x, "lon": b.y, "name": "Grinton"})
	var one: Dictionary = Shed.journey.duplicate(true)
	Shed.request({"a": "adventure_pin", "lat": a.x, "lon": a.y, "name": "Gunnerside", "at": 0})
	var cells := RealRegion.cells_of_area(str(Shed.journey["region"]))
	var frame := RealRegion.frame_of(str(Shed.journey["region"]))
	var p0: Dictionary = Shed.journey["pins"][0]
	check(cells[0] == RealRegion.cell_of(a.x, a.y) and cells.size() >= 9 and str(one["region"]) != str(Shed.journey["region"])
		and RealRegion.to_frame(frame, a.x, a.y).distance_to(Vector2(float(p0["x"]), float(p0["z"]))) < 0.2,
		"a pin put first moves the journey's frame to its cell, and every pin is placed again in it (%d cells)" % cells.size())
	var extent := RealRegion.extent_of(str(Shed.journey["region"]))
	var plan := AdventureJourney.plan_of(Shed.journey)
	check(extent.size.x > 40000.0 and not plan.is_empty() and str(plan["region"]) == str(Shed.journey["region"]),
		"the journey's area is known by its cells without stitching them, and it plans")
	Shed.request({"a": "adventure_unpin", "i": 0})
	check(str(Shed.journey["region"]) == str(one["region"]) and (Shed.journey["pins"] as Array).size() == 1, "and taken off again, it is as it was")
	Shed.journey = {}
	check(AdventureJourney.check(1, {"a": "adventure_pin", "lat": 10.0, "lon": 20.0}) == "Nobody has mapped the roads there yet.",
		"nowhere mapped, no pin")
	check(AdventureJourney.check(1, {"a": "adventure_pin", "lat": NAN, "lon": 20.0}) != "", "a pin must be somewhere")
	var far := AdventureJourney.cells_for([a, a + Vector2(0.0, 10.0)])
	check(far.is_empty() and AdventureJourney.cells_for([a, b]).size() <= 16, "a journey that would need too many cells is turned down")
	# Where the game has no cells, a bundled region's map.
	RealRegion.cell_dirs.clear()
	var shodo := RealRegion.get_region("shodoshima")
	var g := shodo.xz_to_geo(pins()[0].x, pins()[0].y)
	Shed.request({"a": "adventure_pin", "lat": g[0], "lon": g[1]})
	check(str(Shed.journey.get("region", "")) == REGION and not AdventureJourney.anywhere(Shed.journey)
		and AdventureJourney.pin_geo(Shed.journey, 0).distance_to(Vector2(g[0], g[1])) < 0.01,
		"where the game has no cells, a first pin goes on a bundled region's map")
	check(AdventureJourney.check(1, {"a": "adventure_pin", "lat": a.x, "lon": a.y}).begins_with("That's off the"),
		"and the rest of the journey must be on it too")
	Shed.journey = {}
	_world_fixtures(false)


## Every Route planner TV shows the crew's one view (Shed.route_tv): two screens on the channel, whatever is pressed on
## either, show the same part of the world, as close in, on the same tab with the same search; and a view that came from
## the host (as a player's copy of the shed gets it) is what both show.
func test_tv_shared() -> void:
	_world_fixtures(true)
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	var dashes: Array[Dashboard] = []
	for w in [3.4, DynoRoom.PLAN_TV_WIDTH]:
		var d := Dashboard.new("route", w)
		t.add_child(d)
		d.show_page("route", {})
		dashes.append(d)
	var a: RouteTv = dashes[0]._route
	var b: RouteTv = dashes[1]._route
	var same := func() -> bool:
		return is_equal_approx(a.view.lat, b.view.lat) and is_equal_approx(a.view.lon, b.view.lon) and is_equal_approx(a.view.span, b.view.span) \
			and a._find_box.visible == b._find_box.visible and a._query.text == b._query.text
	await _settle(func(): return same.call() and WorldMap.loaded())
	check(same.call() and is_equal_approx(a.view.span, RouteTv.WORLD[2]), "two TVs on the planner show the world, the same")
	a.zoom(4.0)
	await _settle(func(): return same.call() and b.view.span < RouteTv.WORLD[2])
	var was := Vector2(b.view.lat, b.view.lon)
	b.pan(Vector2(0.3, -0.2))
	await _settle(func(): return same.call() and Vector2(a.view.lat, a.view.lon).distance_to(was) > 1.0)
	check(same.call() and is_equal_approx(a.view.span, RouteTv.WORLD[2] / 4.0) and Shed.route_tv.has("lat"),
		"a zoom on one and a move on the other: both show it (%.0f km across)" % (a.view.span / 1000.0))
	a.ask({"tab": "find"})
	b.type("t")
	b.type("o")
	await _settle(func(): return same.call() and b._find_box.visible and a._q() == "to")
	check(same.call() and a._find_box.visible and a._query.text.contains("TO") and a._results.get_child_count() > 0,
		"the search tab, and what is typed in it on either, are the same on both (%s)" % a._query.text)
	var at := _dales_place("Grinton")
	Shed.route_tv = AdventureJourney.sanitize_view({"lat": at.x, "lon": at.y, "span": 6000.0, "tab": "plan"})
	await _settle(func(): return same.call() and is_equal_approx(a.view.span, 6000.0) and a._plan_box.visible)
	check(same.call() and Vector2(a.view.lat, a.view.lon).distance_to(at) < 1e-5 and a._plan_box.visible,
		"a view that came from the host is on both screens")
	var bad := AdventureJourney.sanitize_view({"lat": NAN, "lon": 1.0, "span": 5.0, "tab": "sideways", "q": "Ödön-Hörváth 12345678901234567890"})
	var tiny := AdventureJourney.sanitize_view({"lat": 95.0, "lon": 190.0, "span": 1.0})
	check(not bad.has("lat") and bad["tab"] == "plan" and bad["q"] == "odonhorvath 123456789012" and is_equal_approx(float(tiny["span"]), AdventureJourney.SPAN_MIN)
		and float(tiny["lat"]) == 80.0 and float(tiny["lon"]) < 0.0 and AdventureJourney.sanitize_view("x").is_empty(),
		"a view that's no good is made safe (%s, %s)" % [str(bad), str(tiny)])
	check(AdventureJourney.check(2, {"a": "adventure_view", "view": "x"}) != "" and TvChannels.home("dyno") == "route"
		and TvChannels.screen_exists("dyno"), "a view must be a view, and the Dyno Room's TV is a screen that comes on at the planner")
	Shed.adventure = {}
	Shed.journey = {}
	Shed.route_tv = {}
	for d in dashes:
		d.queue_free()
	await t.get_tree().process_frame
	_world_fixtures(false)


## The world's map (WorldMap): read, the land in triangles, mercator there and back, the search and the nearest place.
## The main roads' sketch: further out than the roads, the world's index names each 5 degree block's sketch by its hash,
## and the TV fetches the blocks in view (kept on disk) and draws their motorways, trunk roads and A roads.
func test_sketch() -> void:
	var host := CellsTests.FakeHost.new()
	check(host.start(), "a stand-in for GitHub listens on this machine")
	var store := "user://test_sketch_cells"
	RegionStore._remove_tree(store)
	# A motorway and an A road in the Dales' cell (degrees x 1e5, each point after the first a step from the one before).
	# Its coast: the Dales cell all land, the one east of it half sea (land to the west of a line down its middle).
	var half := [5450000, -200000, 0, 12500, -25000, 0, 0, -12500]
	var block := JSON.stringify({"format": 1, "cells": {"577_711": [[0, [5430000, -220000, 1000, 2000, 500, 3000]], [2, [5435000, -210000, -800, 900]]]},
		"land": {"577_711": "all", "577_712": {"rings": [half], "holes": []}}})
	host.files["/sketch/b28_35.json"] = (block + "\n").to_utf8_buffer()
	var index := {"format": 1, "release": "2026-10-24.0", "cells": {}, "sketches": {"28_35": block.sha1_text().left(12)}}
	host.files["/index.json"] = JSON.stringify(index).to_utf8_buffer()
	CellStore.index_url = "http://127.0.0.1:%d/index.json" % host.port
	CellStore.dir = store
	CellStore.offline = false
	CellStore.forget_index()
	var view := WorldView.new()
	view.size = Vector2(800, 450)
	t.add_child(view)
	var pump := func(cond: Callable, seconds: float) -> bool:
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		while not cond.call() and Time.get_ticks_msec() < end:
			host.serve()
			view.poll()
			await t.get_tree().process_frame
		return cond.call()
	view.show_view(54.3, -2.1, 300000.0)
	var came: bool = await pump.call(func(): return not view.busy() and (view._sketch.get("28_35", []) as Array).size() == 2, 20.0)
	var first: PackedVector2Array = view._sketch.get("28_35", [[0, PackedVector2Array()]])[0][1] if came else PackedVector2Array()
	check(came and view.sketch_shown() and not view.roads_shown() and view.sketch_blocks().has("28_35")
		and first.size() == 3 and WorldMap.geo_of(first[2]).distance_to(Vector2(54.315, -2.15)) < 1e-3,
		"300 km across, the TV fetches the sketch of the main roads in view and reads its lines (%s)" % str(view._sketch.keys()))
	check(FileAccess.file_exists(store.path_join("sketch/b28_35.json")) and host.asked.has("/sketch/b28_35.json"), "and keeps it on disk")
	# Kept: not fetched again while the index names the same one.
	host.asked.clear()
	check((CellStore.sketch("28_35", index).get("cells", {}) as Dictionary).has("577_711") and not host.asked.has("/sketch/b28_35.json"), "the copy on disk is used while it is the one the index names")
	# A sketch that isn't the one the index names is not taken.
	var changed := index.duplicate(true)
	changed["sketches"]["28_35"] = "000000000000"
	CellStore.offline = true   # (it would be fetched again, from this thread: offline says no instead)
	check(CellStore.sketch("28_35", changed).is_empty() and CellStore.sketch("30_35", index).is_empty(),
		"a sketch the index doesn't name (or doesn't have) is not drawn")
	CellStore.offline = false
	var coast: Array = view._coast.get("28_35", [])
	check(coast.size() == 4 and (coast[1] as ArrayMesh).get_surface_count() == 1 and (coast[2] as ArrayMesh).get_surface_count() == 1
		and (coast[3] as ArrayMesh).get_surface_count() == 0 and view.coast_shown(),
		"the blocks bring the cells' own coast too: their sea and land, drawn from 300 km across in")
	var land_tris: PackedVector2Array = (coast[2] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if coast.size() == 4 else PackedVector2Array()
	check(land_tris.size() == 6 + 6, "the all-land cell is its box, the half-land one its land's two triangles (%d corners)" % land_tris.size())
	view.show_view(54.3, -2.1, 20000.0)
	check(not view.sketch_shown() and view.coast_shown() and view.sketch_blocks().has("28_35"), "close in, the roads instead of the sketch, and the cells' coast")
	view.show_view(30.0, 0.0, 9000000.0)
	check(view.sketch_blocks().is_empty(), "too far out, no sketch")
	host.stop()
	view.queue_free()
	await t.get_tree().process_frame
	RegionStore._remove_tree(store)
	CellStore.index_url = CellStore.INDEX_URL
	CellStore.dir = "user://cells"
	CellStore.forget_index()


func test_world_map() -> void:
	var ms := Time.get_ticks_msec()
	check(WorldMap.load_world() and WorldMap.mesh("land") != null and WorldMap.mesh("land_low") != null and WorldMap.lines("borders").size() > 1000
		and WorldMap.places().size() > 5000, "the world's map is read: land, lakes, rivers, borders and %d places (%d ms)" % [WorldMap.places().size(), Time.get_ticks_msec() - ms])
	var m := WorldMap.mercator(54.3, -2.0)
	var back := WorldMap.geo_of(m)
	check(back.distance_to(Vector2(54.3, -2.0)) < 1e-4 and WorldMap.mercator(0.0, -180.0).is_equal_approx(Vector2(0.0, 0.5)),
		"mercator there and back (%s)" % str(back))
	var hits := WorldMap.search("takam")
	check(not hits.is_empty() and str(hits[0][0]) == "Takamatsu" and str(WorldMap.search("LONDON")[0][0]) == "London"
		and WorldMap.fold("Zürich ") == "zurich ", "the search finds Takamatsu and London, whatever the case or the accents")
	check(WorldMap.nearest_place(51.51, -0.12) == "London" and WorldMap.nearest_place(34.34, 134.05) == "Takamatsu",
		"the nearest town or city to a point")


## Waits (ten seconds at most: a new map is shaded first) for `cond`, a frame at a time.
func _settle(cond: Callable) -> void:
	var end := Time.get_ticks_msec() + 10000
	while not cond.call() and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame


## Bridges (tools/span_bake.py's spans): Hawes to Leyburn crosses becks and the Ure on stone bridges. The planner finds
## the road's bridges, lays each straight from end to end over what it crosses, and they're in the plan's hash; the ride
## leaves the land under a deck as it is and builds the bridge, parapets and all.
func test_bridges() -> void:
	var r := RealRegion.get_region("dales")
	check(r != null and r.spans.size() > 50 and r.spans.all(func(sp): return int(sp[0]) in [0, 1]),
		"the Dales has its bridges and tunnels (%d)" % (r.spans.size() if r else 0))
	if r == null:
		return
	var req := {"pins": [r.geo_to_xz(54.3037, -2.1990), r.geo_to_xz(54.3103, -1.8296)], "mode": "main", "seed": 2}
	var res := RoutePlanner.plan(r, req)
	check(bool(res["ok"]), "Hawes to Leyburn plans (%s)" % str(res["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	var b := p.bridges
	check(b.size() >= 4 and b.size() % 2 == 0, "the road's bridges are found along it (%d)" % (b.size() / 2))
	# Each straight from end to end (the road's own smoothing aside), and none of them a road over nothing.
	var straight := true
	var deepest := 0.0
	for k in range(0, b.size() - 1, 2):
		var i0 := b[k]
		var i1 := b[k + 1]
		straight = straight and i1 > i0 and i1 - i0 < 120
		for i in range(i0 + 1, i1):
			var under := r.terrain.height(p.x[i], p.z[i]) if r.terrain else NAN
			if not is_nan(under):
				deepest = maxf(deepest, p.e[i] - under)
	check(straight and deepest > 2.0, "each a span of the road, over land up to %.1f m below it" % deepest)
	# Without the bridges it's another road, and the hash says so (co-op machines without them won't ride together).
	var kept := r.spans
	r.spans = []
	var flat := RoutePlanner.plan(r, req)
	r.spans = kept
	check(bool(flat["ok"]) and (flat["pack"] as RealPack).hash != p.hash and (flat["pack"] as RealPack).bridges.is_empty(),
		"without them it plans another road, with another hash")
	# The ride: the land under a deck is left as it is, below it; a bridge is built there.
	RealPack.register(p)
	var route := AdventureRoute.new()
	route.plan_real(p, 3, p.max_km(), [])
	var mid := (b[0] + b[1]) / 2
	var hx := route.px[mid]
	var hz := route.pz[mid]
	var below := route.land_height(mid, 0.0, hx, hz)
	check(route.deck[mid] == 1.0 and below <= route.ph[mid] - AdventureRoute.BRIDGE_DEPTH, "the land under the first bridge is under its deck (%.1f m below)" % (route.ph[mid] - below))
	var away := (b[1] + 60) if b.size() < 4 or b[2] > b[1] + 100 else b[b.size() - 1] + 60
	check(away < route.deck.size() and route.deck[away] == 0.0 and is_equal_approx(route.land_height(away, 0.0, route.px[away], route.pz[away]), route.ph[away]),
		"off it, the land meets the road as before")
	var c := mid / AdventureRoute.CHUNK_KNOTS
	var built := AdventureChunk.build(route, c)
	var bridge: Dictionary = built.get("bridge", {})
	check(not bridge.is_empty() and (bridge["v"] as PackedVector3Array).size() > 60, "and the chunk builds the bridge (%d corners)" % ((bridge["v"] as PackedVector3Array).size() if not bridge.is_empty() else 0))
	# The other way at a fork: the bridges past where it rejoins are still where the road crosses them.
	if route.forks.is_empty() or route.forks[0]["ways"].size() < 2:
		return
	var alt := route.path_copy({0: 1})
	alt._assemble_path()
	var shift := alt.px.size() - route.px.size()
	var past := -1
	for k in range(0, b.size() - 1, 2):
		if b[k] > int(route.forks[0]["i1"]) and b[k + 1] - b[k] > 2 * AdventureRoute.DECK_EASE:
			past = (b[k] + b[k + 1]) / 2
			break
	check(alt.deck.size() == alt.px.size() and alt.bore.size() == alt.px.size() and (past < 0 or alt.deck[past + shift] == 1.0),
		"on the other way at a fork the bridges past it are still under the road (%d knots on)" % shift)
	# And the other way's own bridges: found along it, laid straight across, and under the road when it's taken.
	var wr: Dictionary = p.forks[0]["way"]
	var wb: PackedInt32Array = wr.get("bridges", PackedInt32Array())
	check(wb.size() >= 2, "the other way at the fork has its own bridges (%d)" % (wb.size() / 2))
	if wb.size() < 2:
		return
	var longest := 0
	for k in range(0, wb.size() - 1, 2):
		if wb[k + 1] - wb[k] > wb[longest + 1] - wb[longest]:
			longest = k
	var w0 := wb[longest]
	var w1 := wb[longest + 1]
	var we: PackedFloat32Array = wr["e"]
	var off := 0.0
	for k in range(w0 + 3, w1 - 2):
		off = maxf(off, absf(we[k] - lerpf(we[w0 + 3], we[w1 - 3], float(k - w0 - 3) / maxf(w1 - w0 - 6, 1))))
	var at := int(route.forks[0]["i0"]) + (w0 + w1) / 2
	check(off < 0.5 and alt.deck[at] == 1.0,
		"its longest (%d m) laid straight across (%.2f m off at most), and under the road on that way (%.1f)" % [(w1 - w0) * 4, off, alt.deck[at]])


## Tunnels (tools/span_bake.py's spans of kind 1): on Shodoshima's east coast the road goes 640 m under a hill. The
## planner finds it and lays the road straight through, under the hill rather than over it, and it's in the hash; the
## ride keeps the hill over the road, cuts into it up to the portals and builds the tube, portals, lamps and boards.
func test_tunnels() -> void:
	var r := RealRegion.get_region(REGION)
	var req := {"pins": [r.geo_to_xz(34.48875, 134.34511), r.geo_to_xz(34.47647, 134.33166)], "mode": "main", "seed": 2}
	var res := RoutePlanner.plan(r, req)
	check(bool(res["ok"]), "the road through the hill plans (%s)" % str(res["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	var t := p.tunnels
	check(t.size() == 2 and (t[1] - t[0]) * RoutePlanner.STEP > 560.0 and (t[1] - t[0]) * RoutePlanner.STEP < 720.0,
		"the tunnel is found along it (%s knots)" % str(t))
	if t.size() != 2:
		return
	# Straight through (the road's own smoothing aside), well under the hill.
	var bent := 0.0
	var over := 0.0
	var a0 := t[0] + 6
	var a1 := t[1] - 6
	for i in range(a0, a1 + 1):
		bent = maxf(bent, absf(p.e[i] - lerpf(p.e[a0], p.e[a1], float(i - a0) / (a1 - a0))))
		var hill := r.terrain.height(p.x[i], p.z[i]) if r.terrain else NAN
		if not is_nan(hill):
			over = maxf(over, hill - p.e[i])
	check(bent < 1.0 and over > 25.0, "straight through (%.2f m off at most), up to %.0f m under the hill" % [bent, over])
	var kept := r.spans
	r.spans = []
	var flat := RoutePlanner.plan(r, req)
	r.spans = kept
	check(bool(flat["ok"]) and (flat["pack"] as RealPack).hash != p.hash and (flat["pack"] as RealPack).tunnels.is_empty(),
		"without it it plans another road, with another hash")
	# The ride: the hill is kept over the road, a cutting runs up to each portal, and the land is as before away from it.
	RealPack.register(p)
	var route := AdventureRoute.new()
	route.plan_real(p, 3, p.max_km(), [])
	check(route.bore.size() == route.px.size() and route.deck.size() == route.px.size() and route.cutting.size() == route.px.size(),
		"each knot knows whether it's on a bridge or in a tunnel")
	var mid := (t[0] + t[1]) / 2
	var e := route.width[mid] * 0.5
	var edge := route.land_height(mid, e + 0.5, route.px[mid] + cos(route.hd[mid]) * (e + 0.5), route.pz[mid] + sin(route.hd[mid]) * (e + 0.5))
	check(route.in_tunnel(mid) and route.tunnel_span(mid) == Vector2i(t[0], t[1]) and edge >= route.ph[mid] + AdventureRoute.TUNNEL_COVER - 0.01,
		"in the tunnel the hill stands over the road (%.1f m over it at the kerb)" % (edge - route.ph[mid]))
	var before := t[0] - 2
	check(not route.in_tunnel(before) and route.cutting[before] > 0.8 and route.cutting[t[0] - AdventureRoute.TUNNEL_APPROACH - 2] == 0.0,
		"up to the portal it's a cutting (%.2f), easing off further out" % route.cutting[before])
	check(not route._fit_for_stop(t[0] - 3) and not route._fit_for_stop(mid), "no stop goes in a tunnel or its cutting")
	# The chunks with it in are built with its tube, the rock over it, and a portal with its board at each end.
	var tubes := 0
	var portals := 0
	var lamps := 0
	var boards: Array = []
	for c in range(t[0] / AdventureRoute.CHUNK_KNOTS, t[1] / AdventureRoute.CHUNK_KNOTS + 1):
		var built := AdventureChunk.build(route, c)
		var tn: Dictionary = built.get("tunnel", {})
		if tn.is_empty():
			continue
		tubes += (tn["tube"]["v"] as PackedVector3Array).size()
		portals += (tn["portals"]["v"] as PackedVector3Array).size()
		lamps += (tn["lights"] as Array).size()
		for bd: Dictionary in tn["boards"]:
			boards.append(str(bd["text"]))
	check(tubes > 1000 and portals > 0 and lamps >= (t[1] - t[0]) / AdventureTunnels.LAMP_EVERY and boards.size() == 2 and boards[0].begins_with("Tunnel"),
		"its chunks build the tube (%d corners), %d lamps, and a portal at each end with its board (%s)" % [tubes, lamps, ", ".join(boards)])
	# Inside, your eyes open up to its lamps.
	check(Lighting.eye_target("", false, 0.0, 1.0) > 1.1 and Lighting.eye_target("", false, 0.0, 0.0) == 1.0, "your eyes open up in a tunnel")


## Becks and narrow rivers (tools/stream_bake.py: the water the land cover's polygons don't hold, mapped as lines):
## Hawes to Leyburn's bridges cross becks the cover hasn't, and the pack has them, in its hash; the land is a trough
## along each, and the land blocks draw a ribbon of water down it, under the bridges.
func test_streams() -> void:
	# A cell's own file of them: fetched for a journey on it, kept, and read into the region's frame.
	var host := CellsTests.FakeHost.new()
	check(host.start(), "a stand-in for GitHub listens on this machine")
	var was := [CellStore.index_url, CellStore.dir, CellStore.offline]
	var store := "user://test_streams_cells"
	RegionStore._remove_tree(store)
	var text := JSON.stringify({"streams": [[1, 5430000, -220000, 100, 200, 50, 300]]})
	host.files["/stream/c577_711.json"] = (text + "\n").to_utf8_buffer()
	var index := {"format": 1, "release": "2026-10-24.0", "cells": {}, "streams": {"577_711": text.sha1_text().left(12)}}
	CellStore.index_url = "http://127.0.0.1:%d/index.json" % host.port
	CellStore.dir = store
	CellStore.offline = false
	var got: Array = []
	var job := WorkerThreadPool.add_task(func(): got.append_array(CellStore.streams("577_711", index)))   # (a lambda can't assign the test's variable)
	while not WorkerThreadPool.is_task_completed(job):
		host.serve()
		await t.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(job)
	var lines := RealRegion._streams_in(got, Vector2(54.3, -2.2))
	var pts: PackedVector2Array = lines[0][1] if lines.size() == 1 else PackedVector2Array()
	check(pts.size() == 3 and pts[0].distance_to(RealRegion.to_frame(Vector2(54.3, -2.2), 54.3, -2.2)) < 0.01
		and FileAccess.file_exists(store.path_join("stream/c577_711.json")), "a cell's streams are fetched by their hash, kept, and read as lines (%d)" % pts.size())
	CellStore.offline = true
	var changed := index.duplicate(true)
	changed["streams"]["577_711"] = "000000000000"
	check(CellStore.streams("577_711", index).size() == 1 and CellStore.streams("577_711", changed).is_empty() and CellStore.streams("1_1", index).is_empty(),
		"the kept copy is used while the index names it, and none that it doesn't")
	CellStore.index_url = was[0]
	CellStore.dir = was[1]
	CellStore.offline = was[2]
	RegionStore._remove_tree(store)
	host.stop()
	var r := RealRegion.get_region("dales")
	check(r != null and r.streams.size() > 1000 and r.streams.all(func(l): return int(l[0]) in [0, 1, 2] and (l[1] as PackedVector2Array).size() >= 2),
		"the Dales has its becks and rivers as lines (%d)" % (r.streams.size() if r else 0))
	if r == null:
		return
	var req := {"pins": [r.geo_to_xz(54.3037, -2.1990), r.geo_to_xz(54.3103, -1.8296)], "mode": "main", "seed": 2}
	var res := RoutePlanner.plan(r, req)
	var p: RealPack = res["pack"]
	check(p.streams.size() > 20 and p.streams.size() < r.streams.size(), "the road's pack has those near it (%d of %d)" % [p.streams.size(), r.streams.size()])
	# Every bridge over water: the cover's, or a beck under it.
	var dry: Array = []
	var b := p.bridges
	for k in range(0, b.size() - 1, 2):
		var wet := false
		for i in range(b[k], b[k + 1] + 1):
			var near := p.stream_at(p.x[i], p.z[i])
			if p.terrain.cover(p.x[i], p.z[i]) == RealPack.WATER or near.x <= near.y + 2.0:
				wet = true
		if not wet:
			dry.append(b[k])
	check(dry.size() <= 1, "the road's bridges cross water (%d of %d with none under: %s)" % [dry.size(), b.size() / 2, str(dry)])
	# Without them it's other land beside the road, and the hash says so.
	var kept := r.streams
	r.streams = []
	var bare := RoutePlanner.plan(r, req)
	r.streams = kept
	check(bool(bare["ok"]) and (bare["pack"] as RealPack).hash != p.hash and (bare["pack"] as RealPack).streams.is_empty(), "without them it's another plan, with another hash")
	# The ride: a trough along a beck under a bridge, and the land block there draws its ribbon of water.
	RealPack.register(p)
	var w := AdventureWorld.new()
	w.setup(p, 3, 0.0)
	var route := w.route
	var at := Vector2.INF
	var bk := -1
	for k in range(0, b.size() - 1, 2):
		for i in range(b[k], b[k + 1] + 1):
			var near := p.stream_at(p.x[i], p.z[i])
			if near.x <= near.y and p.terrain.cover(p.x[i], p.z[i]) != RealPack.WATER:
				at = Vector2(p.x[i], p.z[i])
				bk = i
		if bk >= 0:
			break
	check(bk >= 0, "a bridge over a beck the cover hasn't")
	if bk < 0:
		w.free()
		return
	var raw := p.terrain.height(at.x, at.y)
	var bed := route.ground_at(at.x, at.y)
	check(raw - bed > AdventureRoute.STREAM_DEPTH * 0.5 and raw - bed <= AdventureRoute.STREAM_DEPTH + 0.01,
		"under it the land's a trough along the beck (%.2f m down)" % (raw - bed))
	var key := Vector2i(floori(at.x / RealLand.BLOCK), floori(at.y / RealLand.BLOCK))
	var water = w.land._water_arrays(key, 0)
	var wv: PackedVector3Array = water[Mesh.ARRAY_VERTEX] if water != null else PackedVector3Array()
	var under := false
	var on_road := 0
	for q in range(0, wv.size(), 4):
		var mid := Vector2((wv[q].x + wv[q + 2].x) * 0.5 + key.x * RealLand.BLOCK, (wv[q].z + wv[q + 2].z) * 0.5 + key.y * RealLand.BLOCK)
		if mid.distance_to(at) < 12.0:
			under = true
		var hit := route.locate(mid.x, mid.y)
		if not hit.is_empty() and float(hit["d"]) < route.width[int(hit["i"])] * 0.5 and not RealLand.near_deck(route, int(hit["i"])):
			on_road += 1
	check(under and on_road == 0, "and the block draws the beck's water under the bridge (%d pieces), none on the road (%d)" % [wv.size() / 4, on_road])
	w.free()


## The sharpest a planned road may turn from one knot to the next (rad): a 10 m radius bend at 4 m knots.
const TURN_MAX := 0.6
## How near a pin (m, where it snapped to the road) test_pin_cusps looks for a kink.
const PIN_NEAR := 200.0


## A pin on a side street or at the head of a dead-end road: the road goes in and comes back out the way it went, and
## turns round there without a kink (no two knots by it more than TURN_MAX apart in heading, and knots STEP apart); a dead-end
## last pin still has a run-out past it. Shodoshima's towns pinned at their middles (Tonosho, Ikeda, Kusakabe), and Keld
## at the head of Swaledale, then Grinton (and the other way round, Keld last); and test_via's stop.
func test_pin_cusps() -> void:
	var cases := [["shodoshima", [Vector2(-5881, 1526), Vector2(-306, 1293), Vector2(4560, 2074)]],
		["dales", [Vector2(-8223, -7330), Vector2(7187, -4599)]], ["dales", [Vector2(7187, -4599), Vector2(-8223, -7330)]],
		# (and test_via's stop, which the road goes round a block to and back from)
		[REGION, [pins()[0], RealRegion.get_region(REGION).geo_to_xz(34.53, 134.22), pins()[1]]]]
	for c: Array in cases:
		var r := RealRegion.get_region(str(c[0]))
		var res := RoutePlanner.plan(r, {"pins": c[1], "mode": "main", "seed": 2})
		check(bool(res["ok"]), "%s from %s plans (%s)" % [c[0], str(c[1][0]), str(res["error"])])
		if not bool(res["ok"]):
			continue
		var p: RealPack = res["pack"]
		# (by the pins: where they snapped to the roads, PIN_NEAR or nearer)
		var at_pins: Array[Vector2] = []
		for q: Vector2 in c[1]:
			at_pins.append(r.node_pos[r.nearest_connected(q.x, q.y, RoutePlanner.SNAP_M)])
		var worst := 0.0
		var at := 0
		var gap := INF
		var prev := 0.0
		for i in range(1, p.x.size()):
			var d := Vector2(p.x[i] - p.x[i - 1], p.z[i] - p.z[i - 1])
			if i < p.x.size() - 1:
				gap = minf(gap, d.length())
			var h := atan2(d.x, -d.y)
			var by_pin := at_pins.any(func(q): return q.distance_to(Vector2(p.x[i], p.z[i])) <= PIN_NEAR)
			if i > 1 and by_pin and absf(wrapf(h - prev, -PI, PI)) > worst:
				worst = absf(wrapf(h - prev, -PI, PI))
				at = i
			prev = h
		check(worst <= TURN_MAX and gap > RoutePlanner.STEP * 0.9 and p.run_out_m > 100.0,
			"%s: no kink at a pin (the sharpest turn between knots %.2f rad, at %.0f m), knots %.2f m apart at least, %.0f m run-out" % [c[0], worst, at * RoutePlanner.STEP, gap, p.run_out_m])


## The Dales region (Wensleydale, Swaledale): Hawes to Leyburn is a road of 25 km or so, with forks and a real inn or two.
func test_dales() -> void:
	var r := RealRegion.get_region("dales")
	check(r != null and r.country == "uk" and r.places.size() > 30 and RealRegion.list().has("dales"), "the game has the Dales region (%d places)" % (r.places.size() if r else 0))
	if r == null:
		return
	var res := RoutePlanner.plan(r, {"pins": [r.geo_to_xz(54.3037, -2.1990), r.geo_to_xz(54.3103, -1.8296)], "mode": "main", "seed": 2})
	check(bool(res["ok"]), "Hawes to Leyburn plans (%s)" % str(res["error"]))
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	check(p.max_km() > 20.0 and p.max_km() < 45.0 and p.region == "uk" and p.junctions.size() > 5 and p.pois.size() > 5,
		"%.1f km, with %d junctions, %d places to stop and %d forks, on UK limits" % [p.max_km(), p.junctions.size(), p.pois.size(), p.forks.size()])
	check(p.limit_at(10.0) >= 30.0, "with speed limits (%d km/h at the start)" % int(p.limit_at(10.0)))


## A pin the road has to go out to and back from (not just a dead-end street) is visited, and the way in is not
## cut out of the route as a spur.
func test_via() -> void:
	var r := RealRegion.get_region(REGION)
	var mid := r.geo_to_xz(34.53, 134.22)
	var res := RoutePlanner.plan(r, {"pins": [pins()[0], mid, pins()[1]]})
	check(bool(res["ok"]), "a journey with a stop in the middle plans")
	if not bool(res["ok"]):
		return
	var p: RealPack = res["pack"]
	var node := r.nearest_connected(mid.x, mid.y, 800.0)
	var best := INF
	for k in range(0, p.x.size()):
		best = minf(best, Vector2(p.x[k], p.z[k]).distance_to(r.node_pos[node]))
	var direct := RoutePlanner.plan(r, {"pins": pins()})["pack"] as RealPack
	check(best < 80.0 and p.max_km() > direct.max_km() + 0.5, "it goes out to the stop and turns round there (%.0f m short at the nearest) and the road is longer for it (%.1f km, %.1f direct)" % [best, p.max_km(), direct.max_km()])
	# A pin 100 m up a dead-end street is not driven into: the spur is shorter than SPUR_M each way.
	var steps: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(1, 0, 0)]
	check(RoutePlanner.strip_spurs(r, steps).is_empty() == (r.edge_len[0] <= RoutePlanner.SPUR_M), "an out-and-back of %.0f m is %s" % [r.edge_len[0], "cut out" if r.edge_len[0] <= RoutePlanner.SPUR_M else "kept"])


## A small graph of the tests' own: A-B-C along the bottom, B-D up, and A-D across.
func _square() -> RealRegion:
	return RealRegion.from_rows({"classes": ["primary", "tertiary"], "surfaces": ["tarmac"], "names": [""],
		"nodes": [[0, 0], [1000, 0], [2000, 0], [1000, 800]],
		"edges": [{"a": 0, "b": 1, "c": 0, "s": 0, "l": 0, "n": 0, "o": 1, "p": []},
			{"a": 1, "b": 2, "c": 0, "s": 0, "l": 0, "n": 0, "o": -1, "p": []},
			{"a": 1, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []},
			{"a": 0, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []}],
		"bans": [[3, 3, 2]]})


## One-way roads are driven their way only, and a prohibited turn is not taken.
func test_rules() -> void:
	var r := _square()
	check(r.passable(0, 0) and not r.passable(0, 1) and r.passable(1, 2) and not r.passable(1, 1) and r.passable(2, 3),
		"a one-way road is passable from its open end only")
	check(r.turn_banned(3, 3, 2) and not r.turn_banned(2, 3, 3), "the banned turn is known, its reverse isn't")
	var costs := PackedFloat64Array([1.0, 1.0])
	var ab = RoutePlanner._shortest(r, 0, 1, costs)
	check(ab != null and (ab as Array).size() == 1 and (ab as Array)[0].y == 0, "A to B goes straight along the one-way road")
	var ba = RoutePlanner._shortest(r, 1, 0, costs)
	check(ba != null and (ba as Array).size() == 2 and (ba as Array)[0].y == 2 and (ba as Array)[1].y == 3, "B to A can't go back along it: round by D")
	check(RoutePlanner._shortest(r, 1, 2, costs) == null, "B to C is against the one-way and there is no way round")
	var cb = RoutePlanner._shortest(r, 2, 1, costs)
	check(cb != null and (cb as Array).size() == 1, "C to B is with it")
	var ad = RoutePlanner._shortest(r, 0, 3, costs)
	check(ad != null and (ad as Array).size() == 1 and (ad as Array)[0].y == 3, "A to D takes the direct road")
	var ab2 = RoutePlanner._shortest(r, 0, 1, PackedFloat64Array([10.0, 1.0]))
	check(ab2 != null and (ab2 as Array).size() == 1 and (ab2 as Array)[0].y == 0, "A to B still can't go A-D-B: the turn at D onto D-B is banned, so the dear road it is")
	var db = RoutePlanner._shortest(r, 3, 1, PackedFloat64Array([10.0, 1.0]))
	check(db != null and (db as Array)[0].y == 2, "but from D itself the road to B is fine (no turn to ban)")


## A planned road has forks where the roads offer another way: the other way is a road of its own that meets the main
## road at both ends, and the adventure rides it.
func test_forks() -> void:
	var r := RealRegion.get_region(REGION)
	var res := RoutePlanner.plan(r, {"pins": pins(), "mode": "scenic", "seed": 3})
	var p: RealPack = res["pack"]
	check(bool(res["ok"]) and p.forks.size() >= 1, "the scenic island road has %d fork(s) (%d ms for them)" % [p.forks.size(), int(res["parts"].get("forks", 0)) - int(res["parts"].get("places", 0))])
	if p.forks.is_empty():
		return
	var ok := true
	for row: Dictionary in p.forks:
		var way: Dictionary = row["way"]
		var n := int(way["n"])
		var i0 := int(row["i0"])
		var i1 := int(row["i1"])
		var wx: PackedFloat64Array = way["x"]
		var wz: PackedFloat64Array = way["z"]
		var we: PackedFloat32Array = way["e"]
		if (n - 1) % 32 != 0 or i0 % 32 != 0 or i1 % 32 != 0 or i1 <= i0 or wx.size() != n or we.size() != n:
			ok = false
		if Vector2(wx[0] - p.x[i0], wz[0] - p.z[i0]).length() > 0.01 or Vector2(wx[n - 1] - p.x[i1], wz[n - 1] - p.z[i1]).length() > 0.01:
			ok = false
		if absf(we[0] - p.e[i0]) > 0.01 or absf(we[n - 1] - p.e[i1]) > 0.01:
			ok = false
		var line := PackedVector2Array()
		for k in n:
			line.append(Vector2(wx[k], wz[k]))
		if (way["chunks"] as Array).size() != (n - 1) / 32 or RoutePlanner.sharpest_turn(line) > RoutePlanner.MAX_TURN:
			ok = false
		var kinds: Array = row["kinds"]
		if kinds[0] != "main" or not ["scenic", "gravel"].has(str(kinds[1])) or str((row["names"] as Dictionary)[kinds[1]]) == "":
			ok = false
	check(ok, "each fork's other way runs from the main road's knot i0 to i1 in whole chunks, with their heights and a name")
	# The adventure rides it.
	RealPack.register(p)
	var route := AdventureRoute.new()
	route.plan_real(p, 3, p.max_km(), [])
	check(route.forks.size() == p.forks.size(), "the adventure has the planned forks (%d)" % route.forks.size())


## Finding places on the map: the region's towns and villages by name, and suggestions with nothing typed.
func test_places() -> void:
	var r := RealRegion.get_region(REGION)
	check(r.places.size() >= 30 and r.places.all(func(p): return str(p["name"]) != "" and ["town", "village"].has(str(p["kind"]))),
		"the region has %d towns and villages with names we can print" % r.places.size())
	var hits := JourneyMap.find_places(r, "fuku")
	check(hits.size() >= 1 and str(hits[0]["name"]).to_lower().contains("fuku"), "typing part of a name finds it (%s)" % str(hits.map(func(h): return h["name"])))
	check(JourneyMap.find_places(r, "zzzz").is_empty(), "and a name that isn't there finds nothing")
	var sug := JourneyMap.find_places(r, "")
	var apart := true
	for i in sug.size():
		for j in range(i + 1, sug.size()):
			if Vector2(float(sug[i]["x"]) - float(sug[j]["x"]), float(sug[i]["z"]) - float(sug[j]["z"])).length() < 3000.0:
				apart = false
	check(sug.size() >= 4 and sug.size() <= 8 and apart, "with nothing typed, %d suggested places spread about the island (%s)" % [sug.size(), str(sug.map(func(h): return h["name"]))])
	var oneway := 0
	for ei in r.edge_count():
		if r.edge_oneway[ei] != 0:
			oneway += 1
	check(oneway == int(r.counts.get("oneway", -1)) and oneway > 0, "%d one-way roads, as the bake counted" % oneway)
