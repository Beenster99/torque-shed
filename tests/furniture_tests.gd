extends RefCounted
## Furniture's checks (Ride Anywhere v2, phase D round 3, D9: scripts/scenery/furniture.gd and the mapped roadside's
## stand-back in scripts/mapped_roadside.gd), run from tests/run_tests.gd: its _test_furniture_* functions hand over
## to these. Small graphs of their own (road_block_tests.gd's); no scene, no network.

const Roads := preload("res://tests/road_block_tests.gd")
const D9 := ["street_lamp", "bench", "picnic_table", "post_box", "bus_stop", "charging_station", "cattle_grid", "gate",
	"kissing_gate", "stile", "bollard", "lift_gate"]

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The rows of `features` whose kit names furniture, by block, as the streamer hands them over.
static func rows_of(features: Dictionary, region_id := "") -> Dictionary:
	var by := {}
	for part: String in ["points", "lines", "areas"]:
		for row: Array in features.get(part, []):
			var kit := SceneryStreamer.kit(str(row[0]), region_id)
			if not str(kit.get("model", "")).begins_with("furniture:"):
				continue
			var keys := {}
			if part == "points":
				keys[RoadBlock.key_of(float(row[1]), float(row[2]))] = true
			else:
				for p: Vector2 in row[1]:
					keys[RoadBlock.key_of(p.x, p.y)] = true
			for key: Vector2i in keys:
				if not by.has(key):
					by[key] = {"points": [], "lines": [], "areas": []}
				(by[key][part] as Array).append([row, kit])
	return by


## Every block of `by` laid out: {items: {model: [Transform3D in the region frame]}, ms (the slowest block)}.
static func lay_all(net: RoadNet, by: Dictionary) -> Dictionary:
	var items := {}
	var ms := 0.0
	for k: Vector2i in by:
		var t0 := Time.get_ticks_usec()
		var b := Furniture.lay_out(net, k, by[k])
		ms = maxf(ms, (Time.get_ticks_usec() - t0) / 1000.0)
		var o := Vector3(k.x, 0, k.y) * RoadBlock.SIZE
		for m: String in b["items"]:
			if not items.has(m):
				items[m] = []
			for xf: Transform3D in b["items"][m]:
				(items[m] as Array).append(Transform3D(xf.basis, xf.origin + o))
	return {"items": items, "ms": ms}


## Every D9 kind's kit names one of furniture's models, in every region; every model is built as one surface (one
## draw call a block); a post box by its country.
func test_models() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var models := Furniture.all_models()
	var bad := []
	for kind: String in D9:
		var row: Dictionary = kinds.get(kind, {})
		check(row.get("round") == "D9", "%s is D9's" % kind)
		for region in [""] + RegionKit.regions():
			var k := SceneryStreamer.kit(kind, region)
			var m := str(k.get("model", ""))
			if not m.begins_with("furniture:"):
				bad.append("%s (%s): %s" % [kind, region, m])
			var style := str(k.get("style", ""))
			var full := m.get_slice(":", 1) + ("_" + style if style != "" else "")
			if kind in ["bench", "bollard", "gate"] and not full in models:
				bad.append("%s (%s): %s" % [kind, region, full])
			if kind == "street_lamp" and not "lamp_%s_%s" % [style, k.get("light")] in models:
				bad.append("%s (%s): %s %s" % [kind, region, style, k.get("light")])
			if kind == "bus_stop" and not (str(k.get("flag")) in models and "shelter_" + str(k.get("shelter")) in models):
				bad.append("%s (%s)" % [kind, region])
	for region in [""] + RegionKit.regions():
		var k := SceneryStreamer.kit("region_border", region)
		if k.get("model") != "furniture:boundary" or not "boundary_" + str(k.get("plate")) in models:
			bad.append("region_border (%s)" % region)
	check(bad.is_empty(), "every D9 kind's kit (and a region's boundary) names a furniture model, in every region (%s)" % str(bad))
	var post: Dictionary = SceneryStreamer.kit("post_box")
	for code: String in post.get("countries", {}):
		if not str(post["countries"][code]) in models:
			bad.append(code)
	check(bad.is_empty() and post["countries"]["GB"] == "pillar_red" and post["countries"]["DE"] == "box_yellow"
		and post["countries"]["US"] == "drop_blue", "a post box's shape and colour by its country (%s)" % str(bad))
	var flat := []
	for m: String in models:
		var mesh := Furniture.mesh(m)
		if mesh.get_surface_count() != 1 or mesh.get_faces().size() < 12:
			flat.append(m)
	check(flat.is_empty(), "%d models built, one surface each (%s)" % [models.size(), flat])
	check(Furniture.mesh("lamp_column_white") == Furniture.mesh("lamp_column_white"), "a model is built once")
	check(Furniture.mesh("pool_warm").surface_get_material(0) == Furniture.pool_material(), "a lamp's pool is only light")


## The furniture at its points: each kind laid out where the map has it, beside the road and never on it or its verge;
## a gate across the road its posts either side and the gate open along the verge; a cattle grid its wings either
## side; a lamp's arm and pool over the road; a bus stop's shelter facing the road; the same every time.
func test_points() -> void:
	var r := Roads.tee()
	r.features = {"points": [
		["street_lamp", 250.0, 108.0, null, null, null, "", null],     # south of the main road, by it
		["street_lamp", -100.0, 92.0, null, null, null, "", null],     # north of it
		["bench", 300.0, 115.0, null, null, null, "", null],
		["picnic_table", 320.0, 140.0, null, null, null, "", null],
		["post_box", 200.0, 100.5, null, null, null, "", null],        # on the main road: stood off it
		["bus_stop", -50.0, 109.0, null, null, null, "", null],
		["charging_station", 150.0, 130.0, null, null, null, "", null],
		["cattle_grid", 100.0, 300.0, null, null, null, "", null],     # across the side road
		["gate", 300.0, 100.0, null, null, null, "", null],            # across the main road
		["gate", 360.0, 130.0, null, null, null, "", null],            # a field's, off the road
		["kissing_gate", 0.0, 120.0, null, null, null, "", null],
		["stile", 30.0, 80.0, null, null, null, "", null],
		["bollard", 120.0, 120.0, null, null, null, "", null],
		["lift_gate", 100.0, 250.0, null, null, null, "", null],       # across the side road
		["bench", 100.0, 100.0, null, null, null, "", null],           # in the tee: left out
	], "lines": [
		["gate", PackedVector2Array([Vector2(-150, 140), Vector2(-146, 140)]), null, null, 0, "", null],
		["region_border", PackedVector2Array([Vector2(40, 200), Vector2(160, 205)]), null, null, 0, "GB-NYK|GB-LAN", null],
	], "areas": []}
	var net := RoadNet.new(r, Roads.flat)
	var by := rows_of(r.features)
	var got := lay_all(net, by)
	var items: Dictionary = got["items"]
	for m in ["lamp_column_white", "pool_white", "bench", "picnic_table", "box_red", "bus_flag", "charger", "grid_wing",
			"gate_post", "gate_leaf", "gate", "kissing_gate", "stile", "bollard", "barrier_post", "barrier_rest"]:
		check(items.has(m), "%s laid out (%s)" % [m, items.keys()])
	check((items.get("bench", []) as Array).size() == 1, "the bench in the junction is left out")
	check((items.get("gate", []) as Array).size() == 2, "a field's gate and the one mapped as a line, closed (%d)" % (items.get("gate", []) as Array).size())
	# Nothing stands on a carriageway or its verge (the pools are only light; a lamp's arm is far overhead).
	var on_road := []
	for m: String in items:
		if m.begins_with("pool_"):
			continue
		for xf: Transform3D in items[m]:
			if not History.clear_of_roads(net, Vector2(xf.origin.x, xf.origin.z), 0.0):
				on_road.append(m)
	check(on_road.is_empty(), "nothing on a road or its verge (%s)" % str(on_road))
	# The gate across the main road: a post either side of it, the leaf hung along the road (its +x east or west).
	var posts: Array = items.get("gate_post", [])
	check(posts.size() == 2 and signf(posts[0].origin.z - 100.0) != signf(posts[1].origin.z - 100.0),
		"the gate's posts either side of the road (%s)" % str(posts.map(func(x): return x.origin)))
	var leaf: Transform3D = items["gate_leaf"][0]
	check(absf(leaf.basis.x.normalized().x) > 0.99, "the gate open along the verge (%s)" % str(leaf.basis.x))
	# The cattle grid's wings either side of the side road (x 100), running out from it.
	var wings: Array = items.get("grid_wing", [])
	check(wings.size() == 2 and signf(wings[0].origin.x - 100.0) != signf(wings[1].origin.x - 100.0)
		and absf(wings[0].basis.x.normalized().x) > 0.99, "the grid's wings either side, out from the road")
	# A lamp's arm reaches out over the road and its pool lies on it: south of the road the lamp faces north (-z).
	for xf: Transform3D in items["lamp_column_white"]:
		var face := xf.basis.z.normalized()
		check(face.z * signf(xf.origin.z - 100.0) < -0.9, "a lamp faces the road (%s at %s)" % [face, xf.origin])
	var pools: Array = items.get("pool_white", [])
	check(pools.size() == 2 and pools.all(func(x): return absf(x.origin.z - 100.0) < 6.0),
		"a pool of light on the road under each lamp (%s)" % str(pools.map(func(x): return x.origin)))
	# Where the side road crosses a county's boundary, a sign each way past the line facing its traffic, and a stone.
	var signs: Array = items.get("boundary_white", [])
	check(signs.size() == 2 and (items.get("boundary_stone", []) as Array).size() == 1
		and signs.all(func(x): return (x.origin.z - 202.0) * x.basis.z.z < 0.0),
		"a boundary sign each way facing the rider who's crossed, and its stone (%s)" % str(signs.map(func(x): return x.origin)))
	# Laid out again, the same (and quick, the place's kits loaded the first time).
	var again := lay_all(RoadNet.new(r, Roads.flat), by)
	check(str(again["items"]) == str(items), "the same every time")
	again = lay_all(net, by)
	check(float(again["ms"]) < 10.0, "laid out quickly once its roads are known (%.1f ms the slowest block)" % float(again["ms"]))
	# Into a block: a ticker for the night, nothing a bike can touch.
	var node := Node3D.new()
	t.add_child(node)
	Furniture.dress(node, true)
	check(node.get_node_or_null("FurnitureTick") != null, "the lamps' ticker")
	check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "nothing a bike can touch")
	node.queue_free()


## The generic roadside stands back from the mapped: a road block's fence, wall or hedge where the map has its own
## along the road, and its marker posts where a mapped lamp or gate stands; nothing mapped (or only a stand-in's
## kinds), the generic roadside as it was.
func test_mapped() -> void:
	var r := Roads.tee()
	r.features = {"points": [
		["street_lamp", 250.0, 108.0, null, null, null, "", null],
		["ferry_terminal", 50.0, 108.0, null, null, null, "", null],   # (no D6 or D9 kind: no stand-back)
	], "lines": [
		["wall", PackedVector2Array([Vector2(-150, 104), Vector2(-50, 104), Vector2(-50, 160)]), null, null, 0, "", null],
	], "areas": [
		["hedge", PackedVector2Array([Vector2(300, 120), Vector2(340, 120), Vector2(340, 160), Vector2(300, 160)]), null, null, "", null],
	]}
	r.features_hash = "test"
	MappedRoadside.forget()
	var m := MappedRoadside.of(r)
	check(m == MappedRoadside.of(r), "built once a region")
	check(m.walled(-100.0, 107.0) and m.walled(-48.0, 130.0) and not m.walled(-100.0, 112.0) and not m.walled(-20.0, 104.0),
		"a generic wall stands back within 5 m of a mapped wall, not past it or its end")
	check(m.walled(320.0, 117.0) and m.walled(343.0, 140.0) and not m.walled(320.0, 140.0),
		"and of an outline's every side (a mapped hedge round a field), not its middle")
	check(m.taken(251.0, 106.0) and not m.taken(255.0, 108.0) and not m.taken(50.0, 107.0),
		"a marker post stands back from a mapped lamp, not from a kind no D6 or D9 row draws")
	var bare := Roads.tee()
	check(MappedRoadside.of(bare).is_empty(), "nothing mapped: the roadside as it was")
	MappedRoadside.forget()

## The bundled regions' furniture as the game lays it out over their own land and roads: the Dales' gates, stiles,
## cattle grids and red pillar boxes, Shodoshima's bus stops; each block quickly once its roads are known, nothing on
## a road.
func test_regions() -> void:
	if OS.get_environment("FURNITURE_PROFILE") != "":
		profile()
		return
	for id in ["dales", "shodoshima"]:
		RealRegion.forget(id)
		var r := RealRegion.get_region(id)
		var h: Callable = r.terrain.height if r.terrain != null else func(x, z): return 20.0 + sin(x * 0.01) * 6.0
		var net := RoadNet.new(r, h)
		var by_block := {}
		for part in ["points", "lines", "areas"]:
			for row: Array in r.features[part]:
				var at: Vector2 = Vector2(float(row[1]), float(row[2])) if part == "points" else (row[1] as PackedVector2Array)[0]
				var region_id := str(RegionKit.at_frame(r.frame_lat, r.frame_lon, at.x, at.y).get("region", ""))
				var k := SceneryStreamer.kit(str(row[0]), region_id)
				if not str(k.get("model", "")).begins_with("furniture:"):
					continue
				for key: Vector2i in SceneryStreamer.file_features({part: [row]}).keys():
					if not by_block.has(key):
						by_block[key] = {"points": [], "lines": [], "areas": []}
					(by_block[key][part] as Array).append([row, k])
		# (each block twice: the first time round a place waits on its roads' heights, as the road blocks do)
		for key: Vector2i in by_block:
			Furniture.lay_out(net, key, by_block[key])
		var worst := 0.0
		var over := 0
		var total := 0.0
		var pieces := {}
		var on_road := 0
		for key: Vector2i in by_block:
			var t0 := Time.get_ticks_usec()
			var b := Furniture.lay_out(net, key, by_block[key])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			over += 1 if ms > 2.0 else 0
			for m: String in b["items"]:
				pieces[m] = int(pieces.get(m, 0)) + (b["items"][m] as Array).size()
				if m.begins_with("pool_"):
					continue
				for xf: Transform3D in b["items"][m]:
					var p := Vector2(xf.origin.x, xf.origin.z) + Vector2(key) * RoadBlock.SIZE
					var on := net.locate(p.x, p.y, -1, false)
					if not on.is_empty() and int(on["node"]) < 0 and bool(on["on_road"]):
						on_road += 1
		print("  %s: %d blocks of furniture, %s; %d over 2 ms, the slowest %.2f ms, %.1f ms in all" % [id, by_block.size(),
			str(pieces), over, worst, total])
		check(on_road == 0, "%s: nothing on a road (%d)" % [id, on_road])
		check(worst < 40.0, "%s: every block quickly (%.2f ms at worst)" % [id, worst])
		if id == "dales":
			check(int(pieces.get("gate", 0)) > 200 and int(pieces.get("stile", 0)) > 50 and int(pieces.get("grid_wing", 0)) > 10
				and int(pieces.get("pillar_red", 0)) > 10, "the Dales' gates, stiles, cattle grids and red pillar boxes")
		else:
			check(int(pieces.get("bus_flag", 0)) > 100 and int(pieces.get("pillar_red", 0)) > 0, "Shodoshima's bus stops and post boxes")


## (FURNITURE_PROFILE set: each kind's mean cost a point in the Dales, and the helpers' a thousand calls)
func profile() -> void:
	var r := RealRegion.get_region("dales")
	var net := RoadNet.new(r, r.terrain.height)
	var by := {}
	for row: Array in r.features["points"]:
		var k := SceneryStreamer.kit(str(row[0]), "british_isles")
		if str(k.get("model", "")).begins_with("furniture:"):
			var key := RoadBlock.key_of(float(row[1]), float(row[2]))
			if not by.has(key):
				by[key] = []
			(by[key] as Array).append([row, k])
	for key: Vector2i in by:
		Furniture.lay_out(net, key, {"points": by[key]})
	var per := {}
	var n := {}
	for key: Vector2i in by:
		for pr: Array in by[key]:
			var t0 := Time.get_ticks_usec()
			Furniture.lay_out(net, key, {"points": [pr]})
			var kind := str(pr[0][0])
			per[kind] = float(per.get(kind, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0
			n[kind] = int(n.get(kind, 0)) + 1
	for kind: String in per:
		print("  %s: %d, %.3f ms each" % [kind, n[kind], per[kind] / n[kind]])
	var worst := Vector2i.ZERO
	for key: Vector2i in by:
		if (by[key] as Array).size() > (by.get(worst, []) as Array).size():
			worst = key
	var pts: Array = by[worst]
	var tw := Time.get_ticks_usec()
	for i in 10:
		Furniture.lay_out(net, worst, {"points": pts})
	print("  the busiest block (%d points): %.2f ms" % [pts.size(), (Time.get_ticks_usec() - tw) / 10000.0])
	for what in ["where", "stand", "road", "height", "ground_at"]:
		tw = Time.get_ticks_usec()
		for i in 10:
			var bb := Furniture._Block.new(net, worst)
			for pr: Array in pts:
				var p := Vector2(float(pr[0][1]), float(pr[0][2]))
				match what:
					"where": bb.where(p)
					"stand": bb.stand(p)
					"road": bb.road(p)
					"height": net.height.call(p.x, p.y)
					"ground_at": net.ground_at(p.x, p.y, 10.0, bb.memo)
		print("  %s: %.2f ms" % [what, (Time.get_ticks_usec() - tw) / 10000.0])
	var c := Vector2(float(r.features["points"][0][1]), float(r.features["points"][0][2]))
	for what in ["locate", "at_frame", "near", "height", "stand", "ground"]:
		var t1 := Time.get_ticks_usec()
		var memo := {}
		for i in 1000:
			var p := c + Vector2(i % 37, i / 37) * 3.0
			match what:
				"locate": net.locate(p.x, p.y, -1, false)
				"at_frame": RegionKit.at_frame(r.frame_lat, r.frame_lon, p.x, p.y)
				"near": net._near(p.x, p.y)
				"height": r.terrain.height.call(p.x, p.y)
				"stand": SceneryStreamer.stand(net, p, memo)
				"ground": net.ground_at(p.x, p.y, 10.0, memo)
		print("  1000 %s: %.2f ms" % [what, (Time.get_ticks_usec() - t1) / 1000.0])
