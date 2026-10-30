extends RefCounted
## Borders, tolls and airfields' checks (Ride Anywhere v2, phase D round 3, D8: scripts/scenery/journey_marks.gd and
## scripts/borders.gd), run from tests/run_tests.gd: its _test_journey_marks_* functions hand over to these. Small graphs
## of their own (road_block_tests.gd's) over flat land; no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func flat(_x: float, _z: float) -> float:
	return 10.0


static func box(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## The rows of `features` (RealRegion.features' shape) whose kit names this script, each with its kit in `region`, as
## the streamer hands them over.
static func rows_of(features: Dictionary, region := "") -> Dictionary:
	var out := {"points": [], "lines": [], "areas": []}
	for part in out:
		for row: Array in features.get(part, []):
			var k := SceneryStreamer.kit(str(row[0]), region)
			if str(k.get("model", "")).begins_with("journey_marks:"):
				(out[part] as Array).append([row, k])
	return out


## Every block from `keys` laid out: {items: {model: [Transform3D in the region frame]}, dress: [each block's], ms (the
## slowest)}.
static func lay_all(net: RoadNet, features: Dictionary, keys: Array, region := "") -> Dictionary:
	var rows := rows_of(features, region)
	var all := {}
	var dress := []
	var worst := 0.0
	for key: Vector2i in keys:
		var t0 := Time.get_ticks_usec()
		var b := JourneyMarks.lay_out(net, key, rows)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		var o := Vector3(key.x * 512.0, 0.0, key.y * 512.0)
		for m: String in b["items"]:
			if not all.has(m):
				all[m] = []
			for xf: Transform3D in b["items"][m]:
				(all[m] as Array).append(Transform3D(xf.basis, xf.origin + o))
		if b.has("dress"):
			dress.append([key, b["dress"]])
	return {"items": all, "dress": dress, "ms": worst}


## Every D8 kind names a model of this script in every region (but the regions' borders, which have nothing of their
## own yet), every model there is has a mesh, and every country's board has its words baked.
func test_kits() -> void:
	var kinds: Dictionary = SceneryStreamer.kits()["kinds"]
	var bad := []
	for kind: String in kinds:
		if str(kinds[kind].get("round", "")) != "D8" or kind == "region_border":
			continue
		for region in [""] + RegionKit.regions():
			if not str(SceneryStreamer.kit(kind, region).get("model", "")).begins_with("journey_marks:"):
				bad.append("%s/%s" % [kind, region])
		for region: String in (kinds[kind].get("regions", {}) as Dictionary):
			if not region in RegionKit.regions():
				bad.append("%s/%s (no such region)" % [kind, region])
	check(bad.is_empty(), "every border, toll and airfield kind is modelled in every region (%s)" % str(bad))
	var missing := []
	for m in ["customs_house", "sentry", "booth", "toll_booth", "canopy", "toll_roof:white", "toll_roof:blue", "canopy_leg",
			"arm_post", "arm", "tarmac", "strip", "taxi", "paint", "paint_y", "threshold", "aim", "tile:apron", "tile:tarmac",
			"helipad", "lamp:w", "lamp:g", "lamp:r", "lamp:b", "approach", "windsock", "tower", "hangar_small", "plane",
			"board:FR:blue", "board:JP:blue", "board:MA:green", "flag:FR", "flag:GB", "flag:US", "flag:SE", "flag:ZZ"]:
		var mesh := JourneyMarks.mesh(m)
		if mesh == null or mesh.get_surface_count() == 0 or mesh.get_aabb().size.length() <= 0.0:
			missing.append(m)
	check(missing.is_empty(), "every model has its mesh (%s)" % str(missing))
	# (each board's words baked, in every script the game writes)
	var unbaked := []
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/border_words.json"))
	var countries: Dictionary = v["countries"]
	for code: String in countries:
		for w in [countries[code]["name"], countries[code]["welcome"]]:
			if not SignWords.has(str(w)):
				unbaked.append("%s %s" % [code, w])
	check(countries.size() >= 200 and unbaked.is_empty(), "every country's board words are baked (%d countries; %s)" % [countries.size(), str(unbaked.slice(0, 5))])
	check(str(countries["ES"]["name"]) == "ESPAÑA" and str(countries["FR"]["welcome"]) == "BIENVENUE" and str(countries["JP"]["script"]) == "Jpan",
		"a board is in its country's language and script (%s)" % str(countries["ES"]))
	# (a board wider than its name: the words fit the panel)
	var board := JourneyMarks.mesh("board:DE:blue").get_aabb()
	check(board.size.x < 4.8 and board.size.y > 3.0, "a board is a panel on legs, its words on it (%s)" % str(board.size))
	var c1 := JourneyMarks._flag_colour("v", [Color.BLUE, Color.WHITE, Color.RED], 0.1, 0.5)
	var c2 := JourneyMarks._flag_colour("h", [Color.BLACK, Color.RED, Color.YELLOW], 0.5, 0.9)
	check(c1 == Color.BLUE and c2 == Color.YELLOW, "a tricolour's stripes run the right way")


## Borders: which side of a named border line a point is, at the line itself, round its bends, and none where a cell has
## no named border; RegionKit.at_frame switches the kit (and the side of the road) there, quickly.
func test_borders() -> void:
	# (a line west to east through the middle of a cell in the Pyrenees, France to its left (north), Spain to its right)
	var cell := RealRegion.cell_of(42.8, -0.4)
	var key := "%d_%d" % [cell.x, cell.y]
	var mid := RealRegion.cell_middle(cell)
	var lat := roundi(mid.x * 1e5)
	var lon := roundi((mid.y - 0.1) * 1e5)
	# (west to east, a bend north and back halfway)
	var row := [0, null, null, 0, 1, null, lat, lon, 0, 10000, 300, 0, 0, 10000]
	var f := {"kinds": ["country_border"], "names": ["", "FR|ES"], "lines": [row], "points": [], "areas": []}
	var lines := Borders.lines_of(f, mid)
	check(lines.size() == 1 and str(lines[0][1]) == "FR" and str(lines[0][2]) == "ES", "a named border is read (%s)" % str(lines))
	var m := RealTerrain.metres_per_degree(mid.x)
	check(Borders.side_country(lines, Vector2(-0.05 * m.y, 200.0)) == "FR" and Borders.side_country(lines, Vector2(-0.05 * m.y, -200.0)) == "ES",
		"north of the line is France, south of it Spain")
	# (round the step north halfway: west of it France, east of it Spain, and so round its corners)
	var top := 300e-5 * m.x
	check(Borders.side_country(lines, Vector2(-30.0, top * 0.5)) == "FR" and Borders.side_country(lines, Vector2(30.0, top * 0.5)) == "ES",
		"either side of the step north, its own country")
	check(Borders.side_country(lines, Vector2(-20.0, top + 20.0)) == "FR" and Borders.side_country(lines, Vector2(20.0, top - 20.0)) == "ES",
		"round the step's corner, each on its own side")
	check(Borders.lines_of({"kinds": ["country_border"], "names": ["", ""], "lines": [row]}, mid).is_empty(), "a border the baker didn't name is no switch")
	Borders.given = {key: f}
	CellStore.offline = true
	RegionKit.forget()
	var lat0 := mid.x
	var lon0 := mid.y
	var north := RegionKit.at_frame(lat0, lon0, -0.05 * m.y, -300.0)   # (z south: -300 is north)
	var south := RegionKit.at_frame(lat0, lon0, -0.05 * m.y, 300.0)
	check(str(north.get("country", "")) == "FR" and str(south.get("country", "")) == "ES",
		"the kit is France's north of the line and Spain's south of it, in one cell (%s, %s)" % [north.get("country"), south.get("country")])
	check(str(north.get("region", "")) != str(south.get("region", "")), "so its look changes at the line (%s, %s)" % [north.get("region"), south.get("region")])
	var t0 := Time.get_ticks_usec()
	for i in 20000:
		RegionKit.at_frame(lat0, lon0, -0.05 * m.y + float(i % 200) * 3.0, -60.0 + float(i % 37) * 4.0)
	var us := float(Time.get_ticks_usec() - t0) / 20000.0
	check(us < 25.0, "a point's kit by a border is quick once asked (%.1f µs a call)" % us)
	Borders.given = {}
	CellStore.offline = false
	RegionKit.forget()
	var plain := RegionKit.at_frame(lat0, lon0, 0.0, 300.0)
	check(Borders.country_at(lat0 - 300.0 / m.x, lon0) == "", "a cell with no named border has no switch")
	check(plain is Dictionary, "and its kit is the cell's as before")
	RegionKit.forget()


## A made-up road crossing a border: a board each way in the new country's words on the side it drives on, its flag, a
## customs post at the line (canopy over the road on legs past the verge, booths, arms that lift), nothing on the road.
func test_crossing() -> void:
	var r := Roads.tee()
	# (a border north to south at x 250 across the main road: going south, France is to its left (east))
	r.features = {"points": [], "areas": [], "lines": [
		["country_border", PackedVector2Array([Vector2(250, -300), Vector2(250, 500)]), null, null, 0, "FR|ES", "b1"]]}
	var net := RoadNet.new(r, flat)
	var got := lay_all(net, r.features, [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0)])
	var all: Dictionary = got["items"]
	check(all.has("board:FR:blue") and all.has("board:ES:blue"), "a board each way (%s)" % str(all.keys()))
	if not (all.has("board:FR:blue") and all.has("board:ES:blue")):
		return
	var fr: Transform3D = all["board:FR:blue"][0]
	var es: Transform3D = all["board:ES:blue"][0]
	check(fr.origin.x > 250.0 and es.origin.x < 250.0, "each board in the country it welcomes you to (%.0f, %.0f)" % [fr.origin.x, es.origin.x])
	# (both drive on the right: going east the right is the south (z more), going west the north)
	check(fr.origin.z > 100.0 + 3.0 and es.origin.z < 100.0 - 3.0, "each on the right, as France and Spain drive (%.1f, %.1f)" % [fr.origin.z, es.origin.z])
	check(fr.basis.z.x < -0.9 and es.basis.z.x > 0.9, "each facing the rider coming to it")
	check(all.has("flag:FR") and all.has("flag:ES"), "the flags of both")
	check(all.has("canopy") and all.has("booth") and all.has("canopy_leg"), "a modern post at the line (%s)" % str(all.keys()))
	var probe := Fields._Block.new(net, Vector2i.ZERO)
	var on_road := []
	for m: String in all:
		if m == "canopy":
			continue   # (its roof is over the road, 6 m up)
		for xf: Transform3D in all[m]:
			var p := Vector2(xf.origin.x, xf.origin.z)
			if probe.gap(p) < JourneyMarks.CLEAR - 0.01:
				on_road.append("%s at %s" % [m, p])
	check(on_road.is_empty(), "nothing but the canopy's roof stands on the road or its verge (%s)" % str(on_road))
	var roof: Transform3D = all["canopy"][0]
	check(JourneyMarks.mesh("canopy").get_aabb().position.y > 5.0 and roof.basis.x.length() > net.width_of(0), "the canopy's roof is high over the whole road")
	var arms := 0
	for d: Array in got["dress"]:
		arms += (d[1]["arms"] as Array).size()
	check(arms == 2, "an arm each way (%d)" % arms)
	# (an old post where the region's border is open: the house beside the road, the arms up)
	var old := lay_all(net, r.features, [Vector2i(0, 0)], "western_europe")
	check(old["items"].has("customs_house") and not old["items"].has("canopy"), "an old customs house in western Europe (%s)" % str(old["items"].keys()))
	var open := true
	for d: Array in old["dress"]:
		for a: Dictionary in d[1]["arms"]:
			open = open and bool(a["open"])
	check(open, "its barriers are up")
	# Britain drives on the left: the board for entering it is on the left.
	r.features["lines"][0][5] = "GB|FR"
	var gb := lay_all(RoadNet.new(r, flat), r.features, [Vector2i(0, 0)])
	var board: Transform3D = gb["items"]["board:GB:blue"][0]
	check(board.origin.x > 250.0 and board.origin.z < 100.0 - 3.0, "entering Britain going east, its board is on the left (north) (%s)" % str(board.origin))
	# No names (a cell baked before the borders were named): nothing.
	r.features["lines"][0][5] = ""
	check(lay_all(RoadNet.new(r, flat), r.features, [Vector2i(0, 0)])["items"].is_empty(), "an unnamed border has no boards")


## A toll plaza where booths are mapped on a road: its roof over the road, legs and booths past the verge, an arm each
## way that lifts; booths close together are one plaza.
func test_toll() -> void:
	var r := Roads.tee()
	r.features = {"lines": [], "areas": [], "points": [
		["toll_booth", 300.0, 98.0, null, null, null, "", "t1"], ["toll_booth", 304.0, 102.0, null, null, null, "", "t2"],
		["toll_booth", -150.0, 250.0, null, null, null, "", "t3"]]}   # (off any road: a booth on its own)
	var net := RoadNet.new(r, flat)
	var got := lay_all(net, r.features, [Vector2i(0, 0), Vector2i(-1, 0)])
	var all: Dictionary = got["items"]
	check((all.get("toll_roof:white", []) as Array).size() == 1, "two booths on the road are one plaza (%s)" % str(all.keys()))
	check((all.get("toll_booth", []) as Array).size() == 3, "a booth each side of the road, and the one off it (%d)" % (all.get("toll_booth", []) as Array).size())
	var probe := Fields._Block.new(net, Vector2i.ZERO)
	for m in ["toll_booth", "canopy_leg", "arm_post"]:
		for xf: Transform3D in all.get(m, []):
			check(probe.gap(Vector2(xf.origin.x, xf.origin.z)) >= JourneyMarks.CLEAR - 0.01, "%s past the verge" % m)
	var arms: Array = []
	for d: Array in got["dress"]:
		arms.append_array(d[1]["arms"])
	check(arms.size() == 2 and arms.all(func(a): return not bool(a["open"])), "an arm each way, down until a rider comes")
	var reach := 0.0
	for a: Dictionary in arms:
		reach = maxf(reach, float(a["length"]))
	check(reach >= net.width_of(0) * 0.5, "each arm reaches over its half of the road (%.1f m)" % reach)
	var red := lay_all(net, r.features, [Vector2i(0, 0)], "south_asia")
	check(red["items"].has("toll_roof:red"), "the roof's colour by region")


## An airfield beside a road: the runway's tarmac in pieces never over the road, its markings and lights, approach
## lights only where clear of the road, a tower by the apron, an aircraft landing; a grass strip with its windsock; a
## helipad; aprons as tiles.
func test_airfield() -> void:
	var r := Roads.graph([[-1500, 0], [1500, 0], [0, 0]], [[0, 2, "primary"], [2, 1, "primary"]])
	# (a 2 km runway east to west 300 m north of the road; its approach from the west over the land, from the east too;
	# the airport's land round it with an apron south of it, between it and the road)
	r.features = {"points": [["helipad", 600.0, 200.0, null, null, null, "", "h1"]], "lines": [
		["runway", PackedVector2Array([Vector2(-1000, -300), Vector2(1000, -300)]), null, 45.0, 0, "", "rw1"],
		["taxiway", PackedVector2Array([Vector2(-600, -260), Vector2(600, -260)]), null, null, 0, "", "tw1"],
		["runway", PackedVector2Array([Vector2(-400, 400), Vector2(200, 400)]), null, null, 0, "", "gs1"],
	], "areas": [
		["airport", box(-1100, -420, 1100, -60), null, null, "", "ap1"],
		["apron", box(-200, -200, 200, -100), null, null, "", "apr1"],
		["airstrip", box(-450, 350, 250, 450), null, null, "", "as1"],
	]}
	var net := RoadNet.new(r, flat)
	var keys := []
	for x in range(-4, 4):
		for z in range(-2, 2):
			keys.append(Vector2i(x, z))
	var got := lay_all(net, r.features, keys)
	var all: Dictionary = got["items"]
	for m in ["tarmac", "paint", "threshold", "aim", "lamp:w", "lamp:g", "lamp:r", "approach", "taxi", "paint_y", "lamp:b",
			"tile:apron", "tower", "strip", "windsock", "hangar_small", "helipad"]:
		check(all.has(m) and not (all[m] as Array).is_empty(), "%s laid out (%s)" % [m, all.keys()])
	var probe := Fields._Block.new(net, Vector2i.ZERO)
	var on_road := []
	for m: String in all:
		for xf: Transform3D in all[m]:
			var p := Vector2(xf.origin.x, xf.origin.z)
			var pad := JourneyMarks.CLEAR + (absf(xf.basis.x.length()) * 0.5 if m in ["tarmac", "strip", "taxi"] else 0.0)
			if probe.gap(p) < pad - 0.05:
				on_road.append("%s at %s" % [m, p])
	check(on_road.is_empty(), "nothing on the road (%s)" % str(on_road.slice(0, 5)))
	# (the approach lights reach out past the runway's ends; the strip's tarmac is green, unlit)
	var far := 0.0
	for xf: Transform3D in all["approach"]:
		far = maxf(far, absf(xf.origin.x))
	check(far > 1600.0, "approach lights reach out from the thresholds (%.0f)" % far)
	var lit := false
	for xf: Transform3D in all["lamp:w"]:
		lit = lit or xf.origin.z > 300.0
	check(not lit, "a grass strip has no lights")
	var tower: Transform3D = all["tower"][0]
	check(Geometry2D.is_point_in_polygon(Vector2(tower.origin.x, tower.origin.z), box(-260, -260, 260, -40)), "the tower beside the apron (%s)" % str(tower.origin))
	var planes := []
	for d: Array in got["dress"]:
		for p: Dictionary in d[1]["planes"]:
			planes.append(p)
	check(planes.size() == 1, "one aircraft lands on the long runway (%d)" % planes.size())
	check(got["ms"] < 120.0, "each block quickly (%.1f ms at worst)" % got["ms"])


## The aircraft's approach: down the glide path, onto the runway, slowing along it, gone between landings; where it is
## is the clock's, the same on every machine.
func test_plane() -> void:
	var p := JourneyMarks._Plane.new()
	p.setup({"at": Vector3(0, 10, 0), "dir": Vector3(1, 0, 0), "long": 2500.0, "phase": 0.0})
	var period := JourneyMarks.PERIOD
	var base := floorf(Time.get_unix_time_from_system() / period) * period
	var start: Transform3D = p.placed(base + 1.0)
	check(start.origin.x < -8000.0 and start.origin.y - 10.0 > 400.0, "it comes in from far out and high (%s)" % str(start.origin))
	var mid: Transform3D = p.placed(base + 60.0)
	check(mid.origin.y < start.origin.y and mid.origin.x > start.origin.x, "down the glide path towards the runway")
	var fly := (JourneyMarks.PLANE_FROM + JourneyMarks.AIM) / JourneyMarks.SPEED
	var touch: Transform3D = p.placed(base + fly + 0.1)
	check(absf(touch.origin.y - 11.6) < 0.5 and absf(touch.origin.x - JourneyMarks.AIM) < 20.0, "on the wheels at the aiming point (%s)" % str(touch.origin))
	var roll: Transform3D = p.placed(base + fly + 15.0)
	check(roll.origin.x > touch.origin.x and roll.origin.x < 2500.0, "rolling on along the runway, short of its end (%.0f)" % roll.origin.x)
	check(p.placed(base + period - 1.0) == null, "gone until the next")
	check(p.placed(base + 60.0) == mid, "where it is is the clock's alone")
	p.free()
