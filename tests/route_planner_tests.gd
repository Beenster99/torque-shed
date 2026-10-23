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


## The map: opens on the region, a click pins a road junction, a click on a pin takes it off, the panel and the plan follow.
func test_map() -> void:
	var r := RealRegion.get_region(REGION)
	Shed.adventure = {}
	Shed.journey = {}
	var map := JourneyMap.new()
	t.add_child(map)
	map.open(REGION)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	check(map.visible and map.region == r and map._view._scale > 0.0, "the map opens on the region, all of it in view")
	var a: Vector2 = pins()[0]
	var b: Vector2 = pins()[1]
	map._view.click(map._view.to_screen(a))
	map._view.click(map._view.to_screen(b))
	check((Shed.journey["pins"] as Array).size() == 2, "a click on the map puts a pin down")
	map.refresh()
	await t.get_tree().process_frame
	check(map._pin_box.get_child_count() == 2, "and the panel lists it")
	var end := Time.get_ticks_msec() + 20000
	while map._view.route_pts.size() < 2 and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
		map.refresh()
		await t.get_tree().create_timer(0.1).timeout
	check(map._view.route_pts.size() > 100 and "km" in map._facts.text, "the road is planned and shown (%s)" % map._facts.text.split("\n")[0])
	check(not map._start.disabled, "and the host can start it")
	map._view.click(map._view.to_screen(Vector2(float(Shed.journey["pins"][1]["x"]), float(Shed.journey["pins"][1]["z"]))))
	check((Shed.journey["pins"] as Array).size() == 1, "a click on a pin takes it off")
	map.refresh()
	check(map._start.disabled and "Pin where you start" in map._facts.text, "with one pin there is nothing to start")
	var img := JourneyView.shade_image(r)
	check(img.get_width() > 100 and img.get_height() > 50 and img.get_pixel(img.get_width() / 2, img.get_height() / 2).a >= 0.0, "the land is shaded for the map (%d x %d)" % [img.get_width(), img.get_height()])
	map.queue_free()
	Shed.journey = {}
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
