extends RefCounted
## The scenery pipeline's checks (Ride Anywhere v2, phase D round 0: features.json, the kit library and SceneryStreamer),
## run from tests/run_tests.gd: its _test_scenery_* functions hand over to these. The bundled regions' features, and
## small graphs of their own (road_block_tests.gd's), no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")
const Standin := preload("res://scripts/scenery/standin.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The bundled regions carry their features, in their own frame, and the roads never change with them.
func test_features() -> void:
	for id in ["dales", "shodoshima"]:
		RealRegion.forget(id)
		var r := RealRegion.get_region(id)
		var f := r.features
		check((f["points"] as Array).size() > 100 and (f["lines"] as Array).size() > 10 and (f["areas"] as Array).size() > 10,
			"%s has points, lines and areas (%d, %d, %d)" % [id, (f["points"] as Array).size(), (f["lines"] as Array).size(),
			(f["areas"] as Array).size()])
		var inside := 0
		for p: Array in f["points"]:
			if r.bounds.grow(50.0).has_point(Vector2(float(p[1]), float(p[2]))):
				inside += 1
		check(inside == (f["points"] as Array).size(), "%s: every point is in the region's frame, inside its box (%d of %d)"
			% [id, inside, (f["points"] as Array).size()])
		check(r.features_hash.length() == 12, "%s: its features have a hash (%s)" % [id, r.features_hash])
		var meta = JSON.parse_string(FileAccess.get_file_as_string(RealRegion.dir_of(id).path_join("region.json")))
		check(r.hash == str(meta["hash"]) and RegionStore.hash_of_dir(RealRegion.dir_of(id)) == r.hash,
			"%s: the region's own hash (the roads' seeds) is the one it was baked with, features or not" % id)
		var kits: Dictionary = SceneryStreamer.kits()["kinds"]
		var unknown := {}
		for part in ["points", "lines", "areas"]:
			for row: Array in f[part]:
				if not kits.has(row[0]):
					unknown[row[0]] = true
		check(unknown.is_empty(), "%s: every kind it has is in the kit library (%s)" % [id, unknown.keys()])
	var dales := RealRegion.get_region("dales")
	var named := (dales.features["points"] as Array).filter(func(p): return p[0] == "peak" and p[6] != "")
	check(not named.is_empty() and named[0][4] != null, "the Dales' peaks have names and heights (%s)" % str(named.slice(0, 1)))
	var ferries := (RealRegion.get_region("shodoshima").features["lines"] as Array).filter(func(l): return l[0] == "ferry")
	check(not ferries.is_empty() and (ferries[0][1] as PackedVector2Array).size() >= 2, "Shodoshima's ferries are lines")
	# The crew's hash takes them in; a region without any keeps the one it had.
	var a := AdventureCrew.ride_hash_of("b", "r", "p")
	check(AdventureCrew.ride_hash_of("b", "r", "p", "") == a and AdventureCrew.ride_hash_of("b", "r", "p", "f1") != a
		and AdventureCrew.ride_hash_of("b", "r", "p", "f1") != AdventureCrew.ride_hash_of("b", "r", "p", "f2"),
		"different features, a different ride hash; none, the same as before")
	# A file of a format this game doesn't read is left out.
	var into := {"points": [], "lines": [], "areas": []}
	RealRegion.add_features(into, {"format": 99, "kinds": ["peak"], "names": [""], "points": [[0, 5430000, -200000, null, 1, null, 0, "x"]]},
		Vector2(54.3, -2.0))
	check((into["points"] as Array).is_empty(), "another format is left out")
	RealRegion.add_features(into, {"format": RealRegion.FEATURES_FORMAT, "kinds": ["peak"], "names": ["", "Top"],
		"points": [[0, 5430000, -200000, null, 700, null, 1, "x"]], "lines": [[0, null, null, 1, 0, null, 5430000, -200000, 100, 0]]},
		Vector2(54.3, -2.0))
	var p0: Array = into["points"][0]
	check(p0[0] == "peak" and absf(float(p0[1])) < 0.5 and absf(float(p0[2])) < 0.5 and p0[4] == 700 and p0[6] == "Top",
		"a point at the frame's middle, with its kind, height and name (%s)" % str(p0))
	var l0: Array = into["lines"][0]
	check((l0[1] as PackedVector2Array).size() == 2 and (l0[1] as PackedVector2Array)[1].y < -100.0 and l0[4] == 1,
		"a line's steps north (-z) with its flags (%s)" % str(l0))


## The kit library: a row for a kind, a region's laid over its default.
func test_kits() -> void:
	var k := SceneryStreamer.kit("wind_turbine")
	check(":" in str(k.get("model", "")) and k.get("round") == "D1" and float(k.get("reach", 0)) > 1000.0,
		"a turbine is round 1's, seen from afar (%s)" % k)
	check(SceneryStreamer.kit("no_such_thing").is_empty(), "a kind the library hasn't got has no row")
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var bad := []
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		var model := str((row.get("default", {}) as Dictionary).get("model", ""))
		if not str(row.get("round", "")) in Standin.ROUND_COLOURS or not ":" in model or SceneryStreamer.script_of(model) == null:
			bad.append(kind)
		for region: String in (row.get("regions", {}) as Dictionary):
			if not region in RegionKit.regions():
				bad.append("%s/%s" % [kind, region])
	check(bad.is_empty(), "every row names a round, a model whose script there is and only real regional kits (%s)" % str(bad))
	var post := SceneryStreamer.model_mesh("standin:post_D1")
	check(post is ArrayMesh and post.get_aabb().size.y > 2.0, "the stand-in's script makes its post")
	# A library of stand-ins only places nothing on an ordinary ride; one real model and it does.
	var was := standins()
	check(not SceneryStreamer.models_beyond_standin(), "stand-ins only: an ordinary ride places nothing")
	SceneryStreamer._kits["kinds"]["wind_turbine"]["default"]["model"] = "skyline:turbine"
	check(SceneryStreamer.models_beyond_standin(), "a round's own model: an ordinary ride places it")
	# A region's row over the default (made up here).
	SceneryStreamer._kits = {"kinds": {"x": {"round": "D1", "default": {"model": "standin:post", "reach": 100},
		"regions": {"nordic": {"reach": 900, "colour": "red"}}}}}
	var n := SceneryStreamer.kit("x", "nordic")
	check(n["reach"] == 900 and n["colour"] == "red" and n["model"] == "standin:post" and SceneryStreamer.kit("x", "east_asia")["reach"] == 100,
		"a region's fields laid over the default, other regions the default's")
	SceneryStreamer._kits = was


## Swaps in the kit library with every model a stand-in (so these tests stay the same as the rounds model kinds), and
## returns the one it replaced, to put back.
static func standins() -> Dictionary:
	var was := SceneryStreamer.kits()
	var fake: Dictionary = was.duplicate(true)
	for row: Dictionary in (fake.get("kinds", {}) as Dictionary).values():
		(row["default"] as Dictionary)["model"] = "standin:post"
		for r: Dictionary in (row.get("regions", {}) as Dictionary).values():
			r.erase("model")
	SceneryStreamer._kits = fake
	return was


## A block's stand-ins: on the land, off the carriageway, none in a junction, none at all unless asked for.
func test_lay_out() -> void:
	var kits_was := standins()
	var r := Roads.tee()
	r.features = {"points": [
		["wind_turbine", 300.0, 300.0, 90.0, null, null, "", "a"],    # out in a field
		["level_crossing", 250.0, 101.0, null, null, 90.0, "", "b"],  # on the main road, 1 m right of its middle
		["toll_booth", 100.0, 100.0, null, null, null, "", "c"],      # in the middle of the tee
		["no_such_thing", 320.0, 300.0, null, null, null, "", "d"],   # a kind the library hasn't got
	], "lines": [], "areas": []}
	var net := RoadNet.new(r, Roads.flat)
	var filed := SceneryStreamer.file_features(r.features)
	check(filed.size() == 1 and (filed[Vector2i(0, 0)]["points"] as PackedInt32Array).size() == 4, "all four filed in their block")
	var was := SceneryStreamer.show_standins
	SceneryStreamer.show_standins = false
	check((SceneryStreamer.lay_out(net, filed, Vector2i(0, 0))["items"] as Dictionary).is_empty(), "no stand-ins unless asked for")
	SceneryStreamer.show_standins = true
	var b := SceneryStreamer.lay_out(net, filed, Vector2i(0, 0))
	SceneryStreamer.show_standins = was
	var all: Array = []
	for slot: String in b["items"]:
		all.append_array(b["items"][slot])
	check(all.size() == 2 and int(b["moved"]) == 1 and int(b["skipped"]) == 1,
		"the turbine and the crossing stand, the crossing moved off the road, the one in the junction left out (%s)" % str(b))
	var clear := net.width_of(1) * 0.5 + RoadNet.VERGE + SceneryStreamer.CLEAR
	var off := 0
	for xf: Transform3D in all:
		var on := net.locate(xf.origin.x, xf.origin.z, -1, false)
		if on.is_empty() or (int(on["node"]) < 0 and absf(float(on["lat"])) >= clear - 0.01):
			off += 1
		check(absf(xf.origin.y - (10.0 - 0.1)) < 0.6, "stood on the land (%.2f)" % xf.origin.y)
	check(off == 2, "neither stands on a carriageway or its verge")
	check(b["reach"].values().all(func(v): return float(v) >= 600.0), "each drawn as far as its kind's reach")
	check(float(b["ms"]) < 25.0, "laid out quickly (%.2f ms)" % float(b["ms"]))
	# Into the world: one MultiMesh a model and round, no collision anywhere.
	var s := SceneryStreamer.new()
	s.world = AdventureWorld.new()
	var node := s.commit(b)
	var multis := node.get_children().filter(func(c): return c is MultiMeshInstance3D)
	var bodies := node.find_children("*", "CollisionObject3D", true, false)
	check(multis.size() == b["items"].size() and bodies.is_empty() and int(s.stats["items"]) == 2,
		"one MultiMesh a model and round, nothing a bike can touch")
	check(b["items"].keys().all(func(m): return str(m).begins_with("standin:post_")), "drawn by the stand-in's script (%s)" % str(b["items"].keys()))
	s.world.free()
	s.free()
	SceneryStreamer._kits = kits_was


## Lines and areas are filed in every block their box touches; a block holding a kind seen from afar is laid out that
## far; unknown ground is sea level only when asked.
func test_filing() -> void:
	var f := {"points": [["wind_turbine", 3000.0, 100.0, null, null, null, "", "a"], ["bench", 100.0, 100.0, null, null, null, "", null]],
		"lines": [["railway", PackedVector2Array([Vector2(100, 100), Vector2(100, 1100)]), null, null, 0, "", "b"]],
		"areas": [["quarry", PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10)]), null, null, "", "c"]]}
	var filed := SceneryStreamer.file_features(f)
	var with_line := filed.keys().filter(func(k): return not (filed[k]["lines"] as PackedInt32Array).is_empty())
	check(with_line.size() == 3 and filed.has(Vector2i(0, 2)), "a line 1 km north to south in the three blocks it crosses (%s)" % str(with_line))
	check((filed[Vector2i(-1, -1)]["areas"] as PackedInt32Array).size() == 1 and (filed[Vector2i(0, 0)]["areas"] as PackedInt32Array).size() == 1,
		"an area round a block corner in each block it touches")
	check(SceneryStreamer.in_block(Vector2i(0, 1), Vector2(100, 600)) and not SceneryStreamer.in_block(Vector2i(0, 0), Vector2(100, 600)),
		"a model asks which block a line's point is in")
	var kits_was := standins()
	var far := SceneryStreamer.far_blocks(f, filed)
	SceneryStreamer._kits = kits_was
	check(far.has(RoadBlock.key_of(3000.0, 100.0)) and float(far[RoadBlock.key_of(3000.0, 100.0)]) > SceneryStreamer.REACH
		and not far.has(Vector2i(0, 2)), "the turbine's block is wanted from afar, the railway's only near (%s)" % str(far))
	var r := Roads.tee()
	var net := RoadNet.new(r, func(_x, _z): return NAN)
	check(is_nan(SceneryStreamer.stand(net, Vector2(300, 300)).y) and SceneryStreamer.stand(net, Vector2(300, 300), null, true).y == 0.0,
		"unknown ground: left out, or at sea level when the kit says it may stand at sea")


## On the network ride: the streamer stands the region's points round a rider, off the roads, and puts nothing a bike
## can touch into the world.
func test_ride() -> void:
	var plan := AdventurePlans.sample(20.0)
	var region := RealRegion.get_region(str(plan["region"]))
	var was := AdventureWorld.network
	var was_shown := SceneryStreamer.show_standins
	AdventureWorld.network = true
	SceneryStreamer.show_standins = true
	var w := AdventureWorld.new()
	w.roads_region = region
	w.setup(AdventurePlans.pack_for(plan), 1, 20.0)
	AdventureWorld.network = was
	check(w.scenery != null and w.scenery.net == w.roads.net, "the network ride has its scenery streamer")
	if w.scenery == null:
		w.free()
		SceneryStreamer.show_standins = was_shown
		return
	# The block with the most points within 3 km of the frame's middle.
	var best := Vector2i.ZERO
	var most := 0
	for k: Vector2i in w.scenery._filed:
		var n := (w.scenery._filed[k]["points"] as PackedInt32Array).size()
		if n > most and (Vector2(k) * RoadBlock.SIZE).length() < 3000.0:
			best = k
			most = n
	check(most > 0, "points to stand (%d in block %s)" % [most, best])
	var at := (Vector2(best) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
	w.focus = func(): return [w.to_local_pos(at.x, 0.0, at.y)]
	t.add_child(w)
	w.shift_origin_to(w.to_local_pos(at.x, 0.0, at.y))
	# (the first block waits on the roads' heights round it, worked out once for the road blocks too)
	var t0 := Time.get_ticks_msec()
	while not w.scenery.blocks.has(best) and Time.get_ticks_msec() - t0 < 60000:
		await t.get_tree().process_frame
	check(w.scenery.blocks.has(best), "its block is in the world (%s, ground in: %s, riders %s, tasks %s)" % [str(w.scenery.stats),
		w.scenery.can_build(best), str(w.scenery.riders()), str(w.scenery._tasks)])
	if w.scenery.blocks.has(best):
		var node: Node3D = w.scenery.blocks[best]
		var drawn := 0
		for mmi: MultiMeshInstance3D in node.get_children().filter(func(c): return c is MultiMeshInstance3D):
			drawn += mmi.multimesh.instance_count
		check(drawn == int(w.scenery.stats["items"]) and drawn > 0, "%d stand-ins drawn" % drawn)
		check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "and nothing a bike can touch")
		# Laid out again, now the roads' heights round it are known (as they are once its road blocks are in), it's
		# quick, and nothing stands on a road or its verge.
		var b := SceneryStreamer.lay_out(w.roads.net, w.scenery._filed, best)
		var o := Vector2(best) * RoadBlock.SIZE
		var on_road := 0
		for slot: String in b["items"]:
			for xf: Transform3D in b["items"][slot]:
				var hit := w.roads.net.locate(xf.origin.x + o.x, xf.origin.z + o.y, -1, false)
				if not hit.is_empty() and (int(hit["node"]) >= 0 or absf(float(hit["lat"])) < float(hit["width"]) * 0.5 + RoadNet.VERGE):
					on_road += 1
		check(on_road == 0, "none on a road or its verge (%d moved off one, %d in a junction left out)" % [int(b["moved"]), int(b["skipped"])])
		check(float(b["ms"]) < 25.0, "a block laid out in %.2f ms (the first, waiting on the roads' heights, %.0f ms)"
			% [float(b["ms"]), float(w.scenery.stats["build_ms_max"])])
	SceneryStreamer.show_standins = was_shown
	w.queue_free()
