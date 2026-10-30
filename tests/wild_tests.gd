extends RefCounted
## Mountains and wild ground's checks (Ride Anywhere v2, phase D round 2, D4: scripts/scenery/wild.gd), run from
## tests/run_tests.gd: its _test_wild_* functions hand over to these. Small graphs of their own (road_block_tests.gd's)
## over made-up land, and the bundled regions' own features over their own land; no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The made-up mountain: a pass running north to south over a saddle at (100, 100), the land climbing east and west
## away from the road (0.25 in 1) and falling north and south of the top (0.08 in 1), 1200 m at the saddle; a cliff's
## drop east of x 400 (40 m down over 10 m).
static func land(x: float, z: float) -> float:
	var h := 1200.0 + absf(x - 100.0) * 0.25 - absf(z - 100.0) * 0.08
	if x > 400.0:
		h -= clampf((x - 400.0) * 4.0, 0.0, 40.0)
	return h


## A pass road north to south over the saddle at (100, 100), and a lane off it to the east at (100, 400).
static func pass_road() -> RealRegion:
	return Roads.graph([[100, -300], [100, 400], [100, 600], [500, 400]],
		[[0, 1, "secondary"], [1, 2, "secondary"], [1, 3, "residential"]])


## The kit of `kind` as the made-up place has it (its default, its "countries" left off: there is no country here),
## with `over` laid over it.
static func kit(kind: String, over := {}) -> Dictionary:
	var k := SceneryStreamer.kit(kind)
	k.erase("countries")
	k.merge(over, true)
	return k


## The rows of `features` (RealRegion.features' shape) each with its kit, as the streamer hands them over.
static func rows_of(features: Dictionary, over := {}) -> Dictionary:
	var out := {"points": [], "lines": [], "areas": []}
	for part in out:
		for row: Array in features.get(part, []):
			var k := kit(str(row[0]), over)
			if str(k.get("model", "")).begins_with("wild:"):
				(out[part] as Array).append([row, k])
	return out


## How far `p` is past the verge of the nearest road of `net` (m: negative on one), from every road's line.
static func past_verge(net: RoadNet, p: Vector2) -> float:
	var best := INF
	for e in net.region.edge_count():
		var line := net.line_of(e)
		var half := net.width_of(e) * 0.5 + RoadNet.VERGE
		for k in range(1, line.size()):
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k]).distance_to(p) - half)
	return best


static func count(items: Dictionary, prefix: String) -> int:
	var c := 0
	for m: String in items:
		if m.begins_with(prefix):
			c += (items[m] as Array).size()
	return c


## Every kind of D4's names a model of this script in the kit library, over every region, with stones, signs, summits
## and sands there are; and every model a block can name has a mesh.
func test_kits() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var bad := []
	var d4 := 0
	for kind: String in kinds:
		var row: Dictionary = kinds[kind]
		if str(row.get("round", "")) != "D4":
			continue
		d4 += 1
		for region in [""] + RegionKit.regions():
			var k := SceneryStreamer.kit(kind, region)
			if not str(k.get("model", "")).begins_with("wild:"):
				bad.append("%s/%s" % [kind, region])
			var looks := [k]
			for c: Dictionary in (k.get("countries", {}) as Dictionary).values():
				var kc := k.duplicate()
				kc.merge(c, true)
				looks.append(kc)
			for kk: Dictionary in looks:
				for f in ["stone", "cairn", "rim"]:
					if kk.has(f) and not Wild.STONES.has(str(kk[f])):
						bad.append("%s/%s %s %s" % [kind, region, f, kk[f]])
				if kk.has("sign") and not Wild.SIGNS.has(str(kk["sign"])):
					bad.append("%s/%s sign %s" % [kind, region, kk["sign"]])
				if kk.has("summit") and not str(kk["summit"]) in Wild.SUMMITS:
					bad.append("%s/%s summit %s" % [kind, region, kk["summit"]])
				if kk.has("sand") and not Wild.SANDS.has(str(kk["sand"])):
					bad.append("%s/%s sand %s" % [kind, region, kk["sand"]])
			if float(k.get("reach", 0.0)) > SceneryStreamer.FAR_MOST:
				bad.append("%s/%s reach" % [kind, region])
		for region: String in (row.get("regions", {}) as Dictionary):
			if not region in RegionKit.regions():
				bad.append("%s/%s (no such region)" % [kind, region])
	check(d4 == 13, "the thirteen wild kinds are D4's (%d)" % d4)
	check(bad.is_empty(), "every wild kind is modelled in every region and country, with looks there are (%s)" % str(bad))
	check(SceneryStreamer.kit("saddle").get("countries", {}).get("FR", {}).get("sign", "") == "col"
		and SceneryStreamer.kit("saddle").get("countries", {}).get("CH", {}).get("sign", "") == "passhoehe"
		and SceneryStreamer.kit("saddle", "british_isles").get("sign", "") == "cairn"
		and SceneryStreamer.kit("saddle", "east_asia").get("sign", "") == "toge",
		"a col sign in France, a Passhöhe board in Switzerland, a cairn in Scotland, a tōge marker in Japan")
	var missing := []
	var models := ["crag:granite:0", "crag:limestone:2", "boulder:basalt:1", "boulder:reef:0", "cairn:gritstone", "cave:limestone",
		"cross", "trig", "post", "panorama", "marram", "wild:cairn:granite"]
	for style: String in Wild.SIGNS:
		models.append("sign:" + style + (":gritstone" if style == "cairn" else ""))
	for m: String in models:
		var mesh := Wild.mesh(m)
		if mesh == null or mesh.get_surface_count() == 0 or mesh.get_aabb().size.length() <= 0.0:
			missing.append(m)
	check(missing.is_empty(), "every model has its mesh (%s)" % str(missing))
	var crag := Wild.mesh("crag:granite:1").get_aabb()
	check(crag.position.x > -0.2 and crag.end.x < 1.3 and absf(crag.size.y - 1.0) < 0.15 and absf(crag.size.z - 1.0) < 0.15,
		"a crag is a unit slab, its face at x 0 (%s)" % str(crag))
	for skin in ["snow", "ice", "scree:limestone", "sand:black", "shingle", "ash", "gravel"]:
		var m := Wild.skin_material(skin)
		check(m != null and m.shader != null, "the %s sheet has its look" % skin)


## A named pass: where the road crosses the saddle, its sign in the kit's style with the name and the height, a cairn
## and a panorama board and a lay-by of gravel beside the road, none of it on the road; a saddle no road comes near
## has a cairn; an unnamed one beside a named one no second sign.
func test_pass() -> void:
	Wild.forget()
	var r := pass_road()
	r.features = {"points": [
		["saddle", 130.0, 110.0, null, 1234.0, null, "Col du Test", "col"],    # 30 m off the road
		["saddle", 105.0, -100.0, null, null, null, null, "unnamed"],             # on the road, beside the named one
		["saddle", 420.0, -250.0, null, 1300.0, null, "Hourquette", "away"],    # nowhere near a road
	], "lines": [], "areas": []}
	var net := RoadNet.new(r, land)
	var t0 := Time.get_ticks_usec()
	var b := Wild.lay_out(net, Vector2i(0, 0), rows_of(r.features, {"sign": "col"}))
	var b1 := Wild.lay_out(net, Vector2i(0, -1), rows_of(r.features, {"sign": "col"}))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var items: Dictionary = b["items"]
	check((items.get("sign:col", []) as Array).size() == 1, "the col has its sign (%s)" % str(items.keys()))
	check((items.get("panorama", []) as Array).size() == 1, "and its panorama board")
	check(count(items, "cairn:") == 1, "and its cairn (%d)" % count(items, "cairn:"))
	var words := ((b["dress"] as Dictionary)["labels"] as Array).map(func(l): return str(l["text"]))
	check(words.has("Col du Test") and words.has("Altitude 1234 m"), "it reads Col du Test, Altitude 1234 m (%s)" % str(words))
	check(words.count("Col du Test") == 2, "on both faces of the board")
	var sheets: Dictionary = (b["dress"] as Dictionary)["sheets"]
	check(sheets.has("gravel"), "a lay-by of gravel (%s)" % str(sheets.keys()))
	# Nothing on the road: the sign, the cairn and the board past its verge, and the lay-by from the verge out.
	var half := net.width_of(0) * 0.5 + RoadNet.VERGE
	var worst := INF
	for m: String in items:
		for xf: Transform3D in items[m]:
			worst = minf(worst, absf(xf.origin.x - 100.0) - half)
	check(worst > 1.0, "nothing stands on the road or its verge (%.2f m past it at the nearest)" % worst)
	if sheets.has("gravel"):
		var verts: PackedVector3Array = sheets["gravel"][Mesh.ARRAY_VERTEX]
		var inner := INF
		var outer := 0.0
		for v in verts:
			inner = minf(inner, absf(v.x - 100.0) - half)
			outer = maxf(outer, absf(v.x - 100.0) - half)
			var g := net.ground_at(v.x, v.z, land(v.x, v.z), {})
			if absf(v.y - g) >= 0.5:
				check(false, "the lay-by lies on the land (%.2f over at %s)" % [v.y - g, str(v)])
				break
		check(inner >= 0.0 and inner < 1.0 and outer > 4.0, "the lay-by runs from the verge %.1f m out to %.1f m" % [inner, outer])
	# The sign stands at the top: where the road is highest near the saddle.
	var sign: Transform3D = items["sign:col"][0]
	check(absf(sign.origin.z - 100.0) < 30.0, "the sign is at the top of the pass (z %.0f)" % sign.origin.z)
	var away: Dictionary = Wild.lay_out(net, Vector2i(0, -1), rows_of({"points": [r.features["points"][2]]}))["items"]
	check(count(away, "cairn:") == 1 and count(away, "sign:") == 0, "a saddle off every road has a cairn and no sign (%s)" % str(away.keys()))
	check(count(b1["items"], "sign:") == 0, "the unnamed saddle beside the named one has no sign of its own (%s)" % str((b1["items"] as Dictionary).keys()))
	# Styles: a Passhöhe board, a Scottish cairn, a tōge marker, and heights in feet in the States.
	for style in ["passhoehe", "cairn", "toge", "board"]:
		var bs := Wild.lay_out(net, Vector2i(0, 0), rows_of({"points": [r.features["points"][0]]}, {"sign": style}))
		check(count(bs["items"], "sign:" + style) == 1, "the %s style stands" % style)
	var us := Wild.lay_out(net, Vector2i(0, 0), rows_of({"points": [r.features["points"][0]]}, {"sign": "board", "country": "US"}))
	var us_words := ((us["dress"] as Dictionary)["labels"] as Array).map(func(l): return str(l["text"]))
	check(us_words.has("Elevation 4,049 ft"), "in the States the height is in feet (%s)" % str(us_words))
	check(ms < 40.0, "laid out quickly (%.2f ms)" % ms)


## Peaks: the summit mark by the kit (a cross, a trig pillar, a cairn) with its name; a cave's mouth facing downhill
## with its sign.
func test_peaks_and_caves() -> void:
	Wild.forget()
	var r := pass_road()
	r.features = {"points": [
		["peak", 300.0, 100.0, null, 1260.0, null, "Pic Test", "pk"],
		["cave_entrance", 250.0, 300.0, null, null, null, "Test Pot", "cv"],
	], "lines": [], "areas": []}
	var net := RoadNet.new(r, land)
	for summit in ["cross", "trig", "cairn", "post"]:
		var b := Wild.lay_out(net, Vector2i(0, 0), rows_of(r.features, {"summit": summit}))
		var items: Dictionary = b["items"]
		var model: String = summit if summit != "cairn" else "cairn:granite"
		check((items.get(model, []) as Array).size() >= 1, "a peak's %s (%s)" % [summit, str(items.keys())])
		var words := ((b["dress"] as Dictionary)["labels"] as Array).map(func(l): return str(l["text"]))
		check(words.has("Pic Test"), "with its name")
		if summit == "cross":
			var xf: Transform3D = items["cross"][0]
			check(absf(xf.origin.y - land(300, 100)) < 0.5, "standing on the top (%.1f)" % xf.origin.y)
			var cave: Array = items.get("cave:limestone", [])
			check(cave.size() == 1, "a cave's mouth (%s)" % str(items.keys()))
			if cave.size() == 1:
				# (the land falls away west here, towards the road: the mouth looks west)
				var face: Vector3 = (cave[0] as Transform3D).basis.z.normalized()
				check(face.x < -0.7, "facing downhill (%s)" % str(face))
			check(words.has("Test Pot") and (items.get("post", []) as Array).size() == 1, "with a sign by it naming it")


## A cliff stands along its line: its face at the line on the low ground, up past the high ground, the drop on its
## right; no piece on a road; none where the road runs along it.
func test_cliff() -> void:
	Wild.forget()
	var r := pass_road()
	r.features = {"points": [], "lines": [
		["cliff", PackedVector2Array([Vector2(405, 300), Vector2(405, 0)]), null, null, 0, "", "scar"],   # drop to the east
		["cliff", PackedVector2Array([Vector2(104, 300), Vector2(104, 150)]), null, null, 0, "", "onroad"],   # along the road
	], "areas": []}
	var net := RoadNet.new(r, land)
	var b := Wild.lay_out(net, Vector2i(0, 0), rows_of(r.features))
	var items: Dictionary = b["items"]
	var pieces := []
	for m: String in items:
		if m.begins_with("crag:"):
			pieces.append_array(items[m])
	check(pieces.size() >= 30, "the scar's face in pieces along it (%d)" % pieces.size())
	var on_road := 0
	var low := INF
	var high := -INF
	for xf: Transform3D in pieces:
		if absf(xf.origin.x - 100.0) < 30.0:
			on_road += 1
			continue
		if absf(xf.origin.x - 405.0) >= 0.1 or xf.basis.x.x >= 0.0:
			# (its depth into the high ground is along -x: the face looks east, down the drop)
			check(false, "the face is on the line, looking out over the drop (%s)" % str(xf))
			break
		low = minf(low, xf.origin.y)
		high = maxf(high, xf.origin.y + xf.basis.y.y)
	check(on_road == 0, "no piece of a cliff along the road (%d)" % on_road)
	var top := land(395.0, 150.0)
	var foot := land(415.0, 150.0)
	check(low < foot and high > top, "the face from the foot (%.0f under %.0f) up past the top (%.0f over %.0f)" % [low, foot, high, top])
	# A block over to the north holds the pieces whose middles are there: the line meets itself across the edge.
	var b2 := Wild.lay_out(net, Vector2i(0, -1), rows_of(r.features))
	check(count(b2["items"], "crag:") == 0, "and the next block none of them")


## Glaciers, scree, dunes and shingle lie over the land on its grid, never within reach of a road; a dune swells and
## grows marram, scree has boulders; a reef shows at low water.
func test_areas() -> void:
	Wild.forget()
	var r := pass_road()
	var sq := func(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	r.features = {"points": [], "lines": [], "areas": [
		["glacier", sq.call(20, 20, 200, 200), null, null, null, "ice"],     # across the road
		["scree", sq.call(250, 0, 350, 120), null, null, null, "scree"],
		["dune", sq.call(250, 300, 500, 500), null, null, null, "dune"],     # the lane runs through it
		["shingle", sq.call(150, 150, 220, 250), null, null, null, "shingle"],
	]}
	var net := RoadNet.new(r, land)
	var t0 := Time.get_ticks_usec()
	var b := Wild.lay_out(net, Vector2i(0, 0), rows_of(r.features))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sheets: Dictionary = (b["dress"] as Dictionary)["sheets"]
	for skin in ["ice", "scree:granite", "sand:pale", "shingle"]:
		check(sheets.has(skin), "%s lies over the land (%s)" % [skin, str(sheets.keys())])
	var near := INF
	var swell := 0.0
	for skin: String in sheets:
		var verts: PackedVector3Array = sheets[skin][Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := Vector2(v.x, v.z)
			near = minf(near, past_verge(net, p))
			var over := v.y - net.ground_at(p.x, p.y, land(p.x, p.y), {})
			if skin.begins_with("sand"):
				swell = maxf(swell, over)
			elif over < -0.3 or over > (6.5 if skin == "ice" else 0.3):
				check(false, "%s lies on the land (%.2f over at %s)" % [skin, over, str(p)])
				break
	check(near >= Wild.SHEET_CLEAR - 0.5, "no sheet within reach of a road (%.1f m past a verge at the nearest)" % near)
	check(swell > 1.0 and swell <= 4.1, "the dunes roll up to %.1f m over the land" % swell)
	var items: Dictionary = b["items"]
	check(count(items, "boulder:granite") > 10, "boulders over the scree (%d)" % count(items, "boulder:granite"))
	check(count(items, "marram") > 50, "marram grass on the dunes (%d)" % count(items, "marram"))
	check(ms < 60.0, "laid out quickly (%.2f ms)" % ms)
	# Ice is blue-white; a dune's sand by region (Iceland's black).
	var ice := Wild.skin_material("ice")
	var a: Color = ice.get_shader_parameter("tint_a")
	check(a.b > a.r and a.r > 0.6, "the ice is blue-white (%s)" % str(a))
	# A reef offshore: its heads at low water.
	var sea := func(x: float, z: float) -> float:
		return land(x, z) if x < 450.0 else -6.0
	var r2 := pass_road()
	r2.features = {"points": [], "lines": [], "areas": [["reef", sq.call(460, 0, 510, 200), null, null, null, "reef"]]}
	var heads: Array = Wild.lay_out(RoadNet.new(r2, sea), Vector2i(0, 0), rows_of(r2.features))["items"].values().reduce(
		func(acc, l): return acc + l, [])
	check(heads.size() > 20, "a reef's heads (%d)" % heads.size())
	var at_water := heads.all(func(xf: Transform3D): return absf(xf.origin.y - Wild.SEA) < 0.6)
	check(at_water, "showing at low water")


## The bundled regions' wild ground as the game lays it out over their own land: the Dales' scars, scree and caves,
## Shodoshima's cliffs by the coast road; each block quickly, nothing on a road.
func test_regions() -> void:
	for id in ["dales", "shodoshima"]:
		Wild.forget()
		RealRegion.forget(id)
		var r := RealRegion.get_region(id)
		var h: Callable = r.terrain.height if r.terrain != null else func(x, z): return 20.0 + sin(x * 0.01) * 6.0
		var net := RoadNet.new(r, h)
		var by_block := {}
		for part in ["points", "lines", "areas"]:
			for row: Array in r.features[part]:
				var k := SceneryStreamer.kit(str(row[0]))
				if not str(k.get("model", "")).begins_with("wild:"):
					continue
				k.erase("countries")
				var keys := SceneryStreamer.file_features({part: [row]}).keys()
				for key: Vector2i in keys:
					if not by_block.has(key):
						by_block[key] = {"points": [], "lines": [], "areas": []}
					(by_block[key][part] as Array).append([row, k])
		var worst := 0.0
		var worst_key := Vector2i.ZERO
		var over := 0
		var pieces := {}
		var sheets := {}
		var labels := 0
		# (each block twice: the first time round a place waits on its roads' heights, as the road blocks do)
		for key: Vector2i in by_block:
			Wild.lay_out(net, key, by_block[key])
		var total := 0.0
		for key: Vector2i in by_block:
			var t0 := Time.get_ticks_usec()
			var b := Wild.lay_out(net, key, by_block[key])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			if ms > 2.0:
				over += 1
			if ms > worst:
				worst = ms
				worst_key = key
			for m: String in b["items"]:
				var kind := m.get_slice(":", 0)
				pieces[kind] = int(pieces.get(kind, 0)) + (b["items"][m] as Array).size()
				for xf: Transform3D in b["items"][m]:
					var p := Vector2(xf.origin.x, xf.origin.z) + Vector2(key) * RoadBlock.SIZE
					var on := net.locate(p.x, p.y, -1, false)
					if not on.is_empty() and int(on["node"]) < 0 and bool(on["on_road"]):
						check(false, "%s: a %s on the road at %s" % [id, m, str(p)])
			for s: String in b["dress"]["sheets"]:
				sheets[s] = int(sheets.get(s, 0)) + (b["dress"]["sheets"][s][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			labels += (b["dress"]["labels"] as Array).size()
		print("  %s: %d blocks of wild ground, %s, sheets %s, %d words; %d over 2 ms, the slowest %.2f ms (%s), %.1f ms in all" % [id,
			by_block.size(), str(pieces), str(sheets), labels, over, worst, worst_key, total])
		if OS.get_environment("WILD_PROFILE") != "":
			var slow := {}
			for key: Vector2i in by_block:
				for part in ["points", "lines", "areas"]:
					for pair: Array in by_block[key][part]:
						var one := {"points": [], "lines": [], "areas": []}
						one[part] = [pair]
						var t0 := Time.get_ticks_usec()
						Wild.lay_out(net, key, one)
						var ms := (Time.get_ticks_usec() - t0) / 1000.0
						var kind := "%s %s" % [part, pair[0][0]]
						slow[kind] = maxf(float(slow.get(kind, 0.0)), ms)
			var e0 := Time.get_ticks_usec()
			Wild.lay_out(net, worst_key, {"points": [], "lines": [], "areas": []})
			print("  slowest by kind: %s; an empty block %.2f ms" % [str(slow), (Time.get_ticks_usec() - e0) / 1000.0])
			var bb := Wild._Block.new(net, worst_key)
			var c0 := (Vector2(worst_key) + Vector2(0.5, 0.5)) * RoadBlock.SIZE
			for what in ["bare", "gap", "ground"]:
				var t2 := Time.get_ticks_usec()
				for q in 1000:
					var pq := c0 + Vector2(q % 37, q / 37) * 7.0
					match what:
						"bare": bb.bare(pq)
						"gap": bb.gap(pq)
						"ground": bb.ground(pq)
				print("  1000 %s: %.2f ms" % [what, (Time.get_ticks_usec() - t2) / 1000.0])
		check(int(pieces.get("crag", 0)) > 100, "%s has its cliffs (%d pieces)" % [id, int(pieces.get("crag", 0))])
		check(worst < 60.0, "%s: every block quickly (%.2f ms at worst)" % [id, worst])
		if id == "dales":
			check(sheets.has("scree:granite") and int(pieces.get("cave", 0)) > 0, "the Dales' scree and caves")
	Wild.forget()
