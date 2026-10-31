extends RefCounted
## Checks from Simon's 30 Oct ride (run from tests/run_tests.gd, its _test_ride_fb_* functions hand over to these): the
## houses' windows lit after dark (WindowLights), a respawn on the road network facing the way you were riding
## (AdventureWorld.back_on_road), and the Route planner map drawing its roads and names in one go (WorldView).

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The windows: none lit by day, coming on as dusk falls, most through the evening, the odd one deep in the night and
## a few more before dawn; each window marked in the buildings' colours with a roll of its own, so a street has some on
## and some off; and the town's buildings drawn with the material that lights them.
func test_windows() -> void:
	check(WindowLights.share(13.0, 0.0) == 0.0 and WindowLights.share(7.0, 0.0) == 0.0, "by day no windows are lit")
	var dusk := WindowLights.share(19.5, 0.4)
	var evening := WindowLights.share(20.5, 1.0)
	var late := WindowLights.share(23.0, 1.0)
	var night := WindowLights.share(3.0, 1.0)
	var dawn := WindowLights.share(6.0, 1.0)
	check(dusk > 0.0 and dusk < evening and absf(evening - WindowLights.EVENING) < 0.01,
		"they come on as dusk falls (%.2f), most through the evening (%.2f)" % [dusk, evening])
	check(late < evening and late > night and absf(night - WindowLights.NIGHT) < 0.01 and night < 0.1,
		"then go off through the late evening (%.2f) to the odd one deep in the night (%.2f)" % [late, night])
	check(dawn > night and dawn <= WindowLights.EARLY + 0.01, "and a few come on before dawn (%.2f)" % dawn)
	# Marked windows: a roll of their own, the same for the same place, spread so some are on and some off.
	var rolls := []
	for i in 200:
		var c := WindowLights.mark(Color(0.2, 0.25, 0.3), Vector3(i * 1.7, 3.0, -i * 0.9))
		rolls.append(WindowLights.roll(c))
	var on := rolls.filter(func(r): return r < evening).size()
	check(rolls.all(func(r): return r >= 0.0 and r <= 1.0) and on > 80 and on < 160,
		"each window a roll of its own: %d of 200 lit in the evening" % on)
	check(WindowLights.roll(Color(0.2, 0.25, 0.3)) < 0.0 and WindowLights.mark(Color.BLUE, Vector3.ONE) == WindowLights.mark(Color.BLUE, Vector3.ONE),
		"a wall isn't a window, and a window keeps its roll")
	# A town's buildings: their glass marked.
	var a := AdventureProps.new_arrays()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kit := RegionKit.at_frame(54.0, -2.0, 0.0, 0.0)
	RegionBuildings.real_building(a, Vector3.ZERO, 12.0, 9.0, 0.0, 7.0, "house", kit, {})
	var windows := 0
	for c: Color in a["c"]:
		windows += 1 if WindowLights.roll(c) >= 0.0 else 0
	check(windows >= 12, "a house's windows are marked to light up (%d corners of glass)" % windows)
	var sh := WindowLights.material().shader.code
	check(not sh.contains("%") and sh.contains("EMISSION"), "and the buildings' material lights them")
	WindowLights.set_share(0.42)
	check(absf(float(WindowLights.material().get_shader_parameter("share")) - 0.42) < 1e-4, "the clock sets how many")
	WindowLights.set_share(0.0)


## A respawn on the road network: off the road, back on the road you were riding along (else the nearest) facing the
## way you were riding it (on your side), whichever way the road's drawn; on the road, where you lie but turned to face along the road the way
## you were going; with no heading to go by, where you lie as before.
func test_respawn() -> void:
	var w := AdventureWorld.new()
	w.roads = RoadStreamer.new()
	w.roads.net = RoadNet.new(Roads.graph([[-500, 0], [500, 0]], [[0, 1, "primary"]]), func(_x, _z): return 10.0)
	var east := -PI * 0.5   # (a heading: -z is north, turned a quarter right is east)
	var west := PI * 0.5
	var off := Vector3(40.0, 10.0, 30.0)
	var a = w.back_on_road(off, east + 0.3)
	var b = w.back_on_road(off, west - 0.4)
	var fwd := func(xf: Transform3D) -> Vector3: return -xf.basis.z
	check(a is Transform3D and (fwd.call(a) as Vector3).x > 0.99 and absf((a as Transform3D).origin.z) < 4.0,
		"off the road, riding east: back on it facing east (%s)" % str(a))
	check(b is Transform3D and (fwd.call(b) as Vector3).x < -0.99 and absf((b as Transform3D).origin.z) < 4.0,
		"riding west: facing west (%s)" % str(b))
	check(a is Transform3D and b is Transform3D and signf((a as Transform3D).origin.z) != signf((b as Transform3D).origin.z),
		"each on its own side of the road")
	var lying := Vector3(10.0, 10.0, 1.0)
	var c = w.back_on_road(lying, west + 0.6)
	check(c is Transform3D and (fwd.call(c) as Vector3).x < -0.99 and (c as Transform3D).origin.distance_to(lying) < 0.5,
		"on the road: where you lie, turned to face along it the way you were going (%s)" % str(c))
	check(w.back_on_road(lying) == null, "and with no heading, where you lie as before")
	w.roads.free()
	w.free()
	# Off the road it's the road you were riding along that you're put back on, facing the way you were riding it: not
	# the nearest road where the bike came to rest (a road beside it, the other leg of a hairpin), nor whichever way the
	# tumble left it heading, and even when it came to rest out of reach of any road.
	w = AdventureWorld.new()
	w.roads = RoadStreamer.new()
	w.roads.net = RoadNet.new(Roads.graph([[-500, 0], [500, 0], [500, -40], [-500, -40]],
		[[0, 1, "primary"], [2, 3, "primary"]]), func(_x, _z): return 10.0)
	w.note_ridden(Vector3(0.0, 10.0, -1.5), east)
	check(int(w.ridden_road.get("edge", -1)) == 0 and int(w.ridden_road.get("way", 0)) == 1, "riding east along the first road: noted (%s)" % str(w.ridden_road))
	w.note_ridden(Vector3(60.0, 10.0, 25.0), west)
	check(int(w.ridden_road.get("edge", -1)) == 0, "off any road it keeps the last one")
	var near_other := Vector3(100.0, 10.0, -30.0)
	var d = w.back_on_road(near_other, PI)
	check(d is Transform3D and absf((d as Transform3D).origin.z) < 4.0 and (fwd.call(d) as Vector3).x > 0.99,
		"crashed nearer the road beside it: back on the one you were riding, facing on east (%s)" % str(d))
	check(d is Transform3D and (d as Transform3D).origin.z < 0.0, "on the left half, as at home")
	var far := Vector3(200.0, 10.0, 70.0)
	var e = w.back_on_road(far, west)
	check(e is Transform3D and absf((e as Transform3D).origin.z) < 4.0 and (fwd.call(e) as Vector3).x > 0.99,
		"came to rest out of reach of any road: still back on it, facing on east (%s)" % str(e))
	w.ridden_road = {}
	check(w.back_on_road(near_other, west) is Transform3D and absf((w.back_on_road(near_other, west) as Transform3D).origin.z + 40.0) < 4.0,
		"with no road ridden yet, the nearest as before")
	w.roads.free()
	w.free()
	# The bike keeps the way it was ridden, for the respawn: not whichever way the crash left it lying.
	var bike := Bike.new()
	bike.heading_ridden = 1.0
	check(absf(bike.respawn_heading() - 1.0) < 1e-4, "a bike respawns facing the way it was ridden, not the way it lies")
	bike.free()


## The Route planner map: the roads in view made into each class's line pieces once (on the worker, as they come), and
## a redraw close in with them and the world's names is quick.
func test_map() -> void:
	var r := RealRegion.get_region("dales")
	var segs := WorldView._road_segments(r)
	var pieces := 0
	var want := 0
	for ei in r.edge_count():
		want += r.edge_line[ei].size() - 1
	for ci in segs:
		pieces += (segs[ci] as PackedVector2Array).size() / 2
	check(pieces == want and pieces > 1000, "the roads in view are made into %d line pieces, every one of them" % pieces)
	var view := WorldView.new()
	view.size = Vector2(1600, 900)
	t.add_child(view)
	var g := r.xz_to_geo(r.bounds.get_center().x, r.bounds.get_center().y)
	view.show_view(g[0], g[1], 8000.0)
	view._want = ""
	view.roads = r
	view._road_segs = segs
	var end := Time.get_ticks_msec() + 20000
	while not WorldMap.loaded() and Time.get_ticks_msec() < end:
		view.poll()
		await t.get_tree().process_frame
	var worst := 0.0
	for k in 5:
		view.show_view(g[0], g[1], 8000.0 * pow(1.6, k))
		var t0 := Time.get_ticks_usec()
		view.queue_redraw()
		await t.get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	check(view.roads_shown() and WorldMap.place_points().size() == WorldMap.places().size() and worst < 40.0,
		"zooming the map close in redraws it without a stutter (worst frame %.1f ms)" % worst)
	view.queue_free()
	await t.get_tree().process_frame
