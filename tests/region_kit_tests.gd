extends RefCounted
## Regional kits (RegionKit, RegionBuildings): the country facts table, the kit a place's profile chooses, and every
## building and place of worship of every region drawn sound and light. Plain data in and out, no scene, so each runs
## in a moment. Run from tests/run_tests.gd (its _test_region_kit_* functions hand over to these).

var t: Node   # the test runner: check()

## The postcard places' baked profiles (tests/postcards/world/profile), by place.
const POSTCARDS := {"dales": "577_711", "bavaria": "550_764", "atlas": "485_690", "oaxaca": "428_333",
	"shodoshima": "497_1257", "coromandel": "212_1421", "pyrenees": "531_720", "polder": "570_739"}
const WORSHIP_KINDS := ["church", "chapel", "orthodox", "campanile", "mission", "mosque", "mandir", "wat", "pagoda",
	"temple", "shrine", "stupa", "synagogue"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func postcard(place: String) -> Dictionary:
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://tests/postcards/world/profile/c%s.json" % POSTCARDS[place]))
	return PlaceProfile.parse(v)


## Every country the world's towns name has a row, every row is whole and its values are ones the game knows, and
## the facts that are easy to get wrong are right.
func test_countries() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/countries.json"))
	var missing := []
	for name in world:
		if RegionKit.facts(str(world[name])).is_empty():
			missing.append(world[name])
	check(missing.is_empty(), "every country the world's towns are in has its facts (missing %s)" % str(missing))
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RegionKit.COUNTRIES))["countries"]
	var regions := RegionKit.regions()
	check(regions.size() >= 12, "about a dozen region kits (%d)" % regions.size())
	var bad := []
	for code in table:
		var f: Dictionary = table[code]
		var ok: bool = regions.has(f["region"]) and f["drive"] in ["left", "right"] and f["speed"] in ["mph", "kmh"] \
			and f["centre"] in ["white", "yellow"] and f["edge"] in ["white", "yellow", "none"] \
			and f["warning"] in ["triangle", "diamond"] and f["limit"] in ["ring", "rect"] \
			and (f["posts"] in RegionKit.POST_STYLES or f["posts"] == "none") \
			and (RegionKit.KERB_PAINT.has(f["kerb"]) or f["kerb"] == "none") and str(f["script"]).length() == 4 \
			and not (f["worship"] as Dictionary).is_empty()
		for k in f["worship"]:
			ok = ok and k in WORSHIP_KINDS
		if not ok:
			bad.append(code)
	check(bad.is_empty(), "every country's facts are ones the game knows (not %s)" % str(bad))
	var left := ["GB", "IE", "JP", "AU", "NZ", "IN", "ZA", "TH", "ID", "KE"]
	var right := ["FR", "DE", "US", "MX", "MA", "CN", "BR", "NL", "RU"]
	check(left.all(func(c): return RegionKit.facts(c)["drive"] == "left") and right.all(func(c): return RegionKit.facts(c)["drive"] == "right"),
		"the side of the road is right (left in Britain, Japan, Australia, India; right in France, the US, Mexico)")
	check(RegionKit.facts("GB")["speed"] == "mph" and RegionKit.facts("US")["speed"] == "mph" and RegionKit.facts("IE")["speed"] == "kmh"
		and RegionKit.facts("FR")["speed"] == "kmh", "miles an hour in Britain and the US, km/h in Ireland and France")
	check(RegionKit.facts("US")["centre"] == "yellow" and RegionKit.facts("GB")["centre"] == "white" and RegionKit.facts("IE")["edge"] == "yellow",
		"yellow centre lines in the US, white in Britain; Ireland's edge lines are yellow")
	check(RegionKit.facts("US")["warning"] == "diamond" and RegionKit.facts("DE")["warning"] == "triangle" and RegionKit.facts("US")["limit"] == "rect",
		"diamond warning signs and the white speed limit board in the US, triangles in Germany")
	check(RegionKit.facts("JP")["script"] == "Jpan" and RegionKit.facts("MA")["script"] == "Arab" and RegionKit.facts("RU")["script"] == "Cyrl"
		and RegionKit.facts("GR")["script"] == "Grek" and RegionKit.facts("IN")["script"] == "Deva", "each country's own script for its shop fronts")
	check(RegionKit.facts("ma")["region"] == "north_africa_middle_east" and RegionKit.region_of("JP") == "east_asia"
		and RegionKit.region_of("NZ") == "australia_nz" and RegionKit.region_of("XX") == "", "a country's region kit, whatever its case; none for a code nobody has")


## The kit a profile chooses: each postcard place's region, the variant its altitude or climate makes, and eight
## kits that can't be mistaken for each other.
func test_choose() -> void:
	var want := {"dales": "british_isles", "bavaria": "western_europe", "atlas": "north_africa_middle_east",
		"oaxaca": "latin_america", "shodoshima": "east_asia", "coromandel": "australia_nz", "pyrenees": "western_europe",
		"polder": "western_europe"}
	var kits := {}
	var wrong := []
	for place in want:
		var kit := RegionKit.choose(postcard(place))
		kits[place] = kit
		if kit.get("region", "") != want[place]:
			wrong.append("%s: %s" % [place, kit.get("region", "none")])
	check(wrong.is_empty(), "each postcard place takes its country's region kit (%s)" % str(wrong))
	# What you'd see of a kit's buildings: its walls, roofs, how they're roofed and what they wear.
	var look := func(k: Dictionary) -> String:
		return "%s %s %s %s %s %s %s" % [str(k["walls"]), str(k["roofs"]), k["roof"], k["flat"], k["eaves"], k["timber"], k["facts"]["posts"]]
	var seen := {}
	for place in kits:
		seen[look.call(kits[place])] = place
	check(seen.size() == kits.size(), "the eight postcard places' kits all differ (%d of %d)" % [seen.size(), kits.size()])
	check(kits["bavaria"]["timber"] is Color and float(kits["bavaria"]["eaves"]) > 1.0 and float(kits["polder"]["pitch"]) > float(kits["bavaria"]["pitch"]),
		"Western Europe's upland is alpine (timber, deep eaves), its lowland steep brick")
	check(kits["atlas"]["roof"] == "flat" and kits["atlas"]["walls"] != RegionKit.choose(PlaceProfile.parse({"country": "MA", "altitude_band": "lowland", "koppen": "BWh"}))["walls"],
		"the Atlas's houses are flat-roofed red earth, not the lowland desert's pale ones")
	check(RegionKit.choose(PlaceProfile.parse({"country": ""})).is_empty() and RegionKit.choose(PlaceProfile.parse({"country": "XX"})).is_empty(),
		"no kit over open sea, nor for a country nobody has")
	var guessed := RegionKit.choose(PlaceProfile.guess(34.06, -4.98))
	check(guessed.get("region", "") == "north_africa_middle_east", "a guessed profile (offline) chooses its kit too (Fes: %s)" % guessed.get("region", "none"))
	check(RegionKit.matches({"koppen": ["Cs", "BS"]}, {"koppen": "BSk"}) and not RegionKit.matches({"koppen": ["Cs"]}, {"koppen": "Cfb"})
		and RegionKit.matches({}, {}) and not RegionKit.matches({"coast": true, "altitude": ["lowland"]}, {"coast": false, "altitude_band": "lowland"}),
		"a variant needs every condition it gives")
	var rolls := {}
	var india := RegionKit.choose(PlaceProfile.parse({"country": "IN"}))
	for k in 20:
		rolls[RegionKit.worship_kind(india, (k + 0.5) / 20.0)] = true
	check(rolls.has("mandir") and rolls.has("mosque") and not rolls.has("wat"), "India's places of worship are mandirs and mosques by their shares (%s)" % str(rolls.keys()))


## Every kind of building in every region's kit, and every place of worship and post style, draws whole triangles
## with sound normals, and none is heavier than a chunk can carry many of.
func test_buildings() -> void:
	var worst := {"verts": 0, "what": ""}
	var broken := []
	for region in RegionKit.regions():
		var code := ""
		var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RegionKit.COUNTRIES))["countries"]
		for c in table:
			if table[c]["region"] == region:
				code = c
				break
		for band in ["lowland", "mountain"]:
			var kit := RegionKit.choose(PlaceProfile.parse({"country": code, "altitude_band": band, "density": "rural"}))
			for kind in RealPack.BUILDING_KINDS:
				for n in 4:
					var a := AdventureProps.new_arrays()
					RegionBuildings.real_building(a, Vector3(n * 31.0, 0, 7.0), 7.0 + n * 3.0, 9.0 + n, 0.3 * n, 3.0 + n * 3.0, kind, kit)
					_measure(a, "%s %s %s" % [region, band, kind], worst, broken)
	var kit := RegionKit.choose(PlaceProfile.parse({"country": "GB"}))
	for kind in WORSHIP_KINDS:
		var a := AdventureProps.new_arrays()
		var rng := RandomNumberGenerator.new()
		RegionBuildings.worship(a, Transform3D(), 12.0, 20.0, 12.0, kind, kit, rng)
		_measure(a, kind, worst, broken)
	for style in RegionKit.POST_STYLES:
		var m := RegionKit.post_mesh(style)
		if m.get_surface_count() != 1 or m.surface_get_array_len(0) == 0 or m.surface_get_array_len(0) > 400:
			broken.append("post " + style)
	check(RegionKit.post_mesh("uk") == RegionKit.post_mesh("uk"), "a post style's mesh is shared")
	check(broken.is_empty(), "every building, place of worship and post draws whole, sound triangles (not %s)" % str(broken))
	check(int(worst["verts"]) <= 3000, "the heaviest is light enough for a chunk of them (%d vertices: %s)" % [worst["verts"], worst["what"]])


## A town's buildings take the region's city styles: every region has several, each building one its height suits,
## every style draws sound triangles under a city's budget, and a street of them isn't all the same.
func test_city() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RegionKit.COUNTRIES))["countries"]
	var worst := {"verts": 0, "what": ""}
	var broken := []
	var samey := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for region in RegionKit.regions():
		var code := ""
		for c in table:
			if table[c]["region"] == region:
				code = c
				break
		var kit := RegionKit.choose(PlaceProfile.parse({"country": code, "density": "city"}))
		var seen := {}
		for k in 40:
			var kind: String = ["block", "shop", "civic", "house"][k % 4]
			var h: float = [4.0, 7.0, 10.0, 14.0, 22.0, 35.0, 70.0][k % 7] if kind != "house" else 7.0
			var w := 6.0 + float(k % 5) * 6.0
			var d := 8.0 + float(k % 3) * 5.0
			var style := RegionCity.style_for(kit, kind, w, d, h, rng.randf())
			if style.is_empty():
				broken.append("%s %s %.0f m: no style" % [region, kind, h])
				continue
			var name := str(style["style"])
			seen[name] = true
			var hs: Array = RegionCity.HEIGHTS[name]
			if h < float(hs[0]) or h > float(hs[1]):
				broken.append("%s %s at %.0f m" % [region, name, h])
			var a := AdventureProps.new_arrays()
			RegionCity.build(a, Transform3D(Basis(Vector3.UP, 0.4), Vector3(k * 50.0, 0, 0)), w, d, h, kind, style, kit, rng)
			_measure(a, "%s %s %.0f m" % [region, name, h], worst, broken)
		if seen.size() < 3:
			samey.append("%s %s" % [region, str(seen.keys())])
	check(broken.is_empty(), "every region's city buildings take a style their height suits and draw sound triangles (not %s)" % str(broken))
	check(samey.is_empty(), "every region's cities have three styles or more (not %s)" % str(samey))
	check(int(worst["verts"]) <= 8000, "the heaviest city building is light enough for a street of them (%d vertices: %s)" % [worst["verts"], worst["what"]])
	var gb := RegionKit.choose(PlaceProfile.parse({"country": "GB", "density": "city"}))
	var styles := {}
	for k in 200:
		styles[str(RegionCity.style_for(gb, "block", 20.0, 12.0, 13.0, (k + 0.5) / 200.0).get("style", ""))] = true
	check(styles.has("tenement") and styles.has("modern"), "a British city has tenements and modern blocks (%s)" % str(styles.keys()))
	var rural := RegionKit.choose(PlaceProfile.parse({"country": "GB", "density": "rural"}))
	check(RegionCity.style_for(rural, "house", 8.0, 9.0, 7.0, 0.5).is_empty() and not RegionCity.style_for(gb, "house", 30.0, 9.0, 7.0, 0.5).is_empty()
		and RegionCity.style_for(gb, "barn", 20.0, 12.0, 8.0, 0.5).is_empty(), "a country house stays a house, a town's row of houses takes a street style, a barn stays a barn")


## A city's small pieces (its windows and their surrounds, sills, chimneys and rooftop odds) go in squares of their own,
## drawn close to only and without a shadow, and its street fronts' floors as bands of glass from there on (Simon, 5 Nov:
## "we were down at 20fps" in the cities): every triangle goes one way or the other, the small ones are small, the bands
## are few and light up after dark, the two swap over at once, and a ride that has no far bands draws as before.
func test_city_far() -> void:
	var kit := RegionKit.choose(PlaceProfile.parse({"country": "GB", "density": "city"}))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var a := AdventureProps.new_arrays()
	a["far"] = AdventureProps.new_arrays()
	var plain := AdventureProps.new_arrays()
	for k in 24:
		var kind: String = ["block", "shop", "civic", "house"][k % 4]
		var h: float = [7.0, 10.0, 14.0, 22.0][k % 4] if kind != "house" else 7.0
		var at := Vector3(20.0 + (k % 6) * 70.0, 0.0, 30.0 + (k / 6) * 110.0)
		RegionBuildings.real_building(a, at, 14.0 + (k % 3) * 6.0, 10.0, 0.0, h, kind, kit)
		RegionBuildings.real_building(plain, at, 14.0 + (k % 3) * 6.0, 10.0, 0.0, h, kind, kit)
	check(not plain.has("far") and (plain["v"] as PackedVector3Array).size() == (a["v"] as PackedVector3Array).size(),
		"buildings drawn without far bands (the planned road's) are drawn just as before")
	var tiles := RoadStreamer.building_tiles(a)
	var count := func(list: Array) -> int:
		return list.reduce(func(n, t): return n + (t["v"] as PackedVector3Array).size() / 3, 0)
	var shell: int = count.call(tiles["shell"])
	var fine: int = count.call(tiles["fine"])
	var far: int = count.call(tiles["far"])
	var total := (a["v"] as PackedVector3Array).size() / 3
	check(shell + fine == total and far == (a["far"]["v"] as PackedVector3Array).size() / 3,
		"every triangle is in the shell or the small pieces, once (%d + %d of %d)" % [shell, fine, total])
	var big := 0
	var edge := RoadStreamer.FINE_EDGE * RoadStreamer.FINE_EDGE
	for t: Dictionary in tiles["fine"]:
		var v: PackedVector3Array = t["v"]
		for i in range(0, v.size(), 3):
			if v[i].distance_squared_to(v[i + 1]) >= edge or v[i + 1].distance_squared_to(v[i + 2]) >= edge or v[i + 2].distance_squared_to(v[i]) >= edge:
				big += 1
	check(big == 0, "the small pieces are all small (%d aren't)" % big)
	check(fine > shell, "most of a city street's triangles are its small pieces (%d small, %d shell)" % [fine, shell])
	check(far > 0 and far * 4 < fine, "far off, its floors are a few bands of glass (%d triangles, for %d close to)" % [far, fine])
	var lit := 0
	for c in a["far"]["c"]:
		lit += int(WindowLights.roll(c) >= 0.0)
	check(lit == (a["far"]["c"] as PackedColorArray).size(), "the bands light up after dark, as the windows do")
	var i := 0
	while (tiles["fine"][i]["v"] as PackedVector3Array).is_empty() or (tiles["far"][i]["v"] as PackedVector3Array).is_empty():
		i += 1
	var sq := RoadStreamer.fine_square(tiles["fine"][i], tiles["far"][i], 350.0, "Windows_%d" % i)
	var near := sq.get_node("Near") as MeshInstance3D
	var far_mi := sq.get_node("Far") as MeshInstance3D
	check(near.visibility_range_end == 350.0 and near.visibility_range_begin == 0.0 and far_mi.visibility_range_begin == 350.0
		and far_mi.visibility_range_end == 0.0 and (near.mesh as ArrayMesh).custom_aabb == (far_mi.mesh as ArrayMesh).custom_aabb
		and (near.mesh as ArrayMesh).custom_aabb.encloses(far_mi.mesh.get_aabb()),
		"the small pieces are drawn close to, the bands from there on, swapping over at once (one box for both)")
	check(near.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and far_mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and Lighting.gi_mode_for(near) == GeometryInstance3D.GI_MODE_DISABLED, "neither casts a shadow or bounces light")
	sq.free()


func _measure(a: Dictionary, what: String, worst: Dictionary, broken: Array) -> void:
	var v: PackedVector3Array = a["v"]
	var n: PackedVector3Array = a["n"]
	var ok := v.size() > 0 and v.size() % 3 == 0 and n.size() == v.size() and (a["c"] as PackedColorArray).size() == v.size()
	for k in n.size():
		ok = ok and is_equal_approx(n[k].length(), 1.0) and not is_nan(v[k].x)
	if not ok:
		broken.append(what)
	if v.size() > int(worst["verts"]):
		worst["verts"] = v.size()
		worst["what"] = what


## Where the map gives a building no height (the baker's fallback for its kind), BuildingHeights gives it one that
## suits where it stands: low in a village, taller and mixed towards a big city's middle with the odd tower there, a
## street's heights hanging together; the same in every game; and a height the map gives is kept.
func test_heights() -> void:
	var r := RealRegion.new()
	r.places = [{"kind": "town", "name": "Big", "x": 0.0, "z": 0.0, "pop": 3000000},
		{"kind": "town", "name": "Small", "x": 30000.0, "z": 0.0, "pop": 4000},
		{"kind": "village", "name": "Quarter", "x": 500.0, "z": 0.0, "pop": 0}]
	var kit := RegionKit.choose(PlaceProfile.parse({"country": "US", "density": "city"}))
	var block := RealPack.BUILDING_KINDS.find("block")
	var house := RealPack.BUILDING_KINDS.find("house")
	var mid := []
	var edge := []
	var village := []
	var towers := 0
	for k in 400:
		var x := float(k % 20) * 37.0 - 370.0
		var z := float(k / 20) * 41.0 - 410.0
		mid.append(BuildingHeights.of(r, [x, z, 22.0, 18.0, 0.0, 14.0, block, 0], kit))
		edge.append(BuildingHeights.of(r, [x + 6500.0, z, 22.0, 18.0, 0.0, 14.0, block, 0], kit))
		village.append(BuildingHeights.of(r, [x + 30000.0, z, 22.0, 18.0, 0.0, 14.0, block, 0], kit))
		if float(mid[-1]) > 40.0:
			towers += 1
	var mean := func(a: Array) -> float:
		var s := 0.0
		for v in a:
			s += float(v)
		return s / a.size()
	var spread := {}
	for v in mid:
		spread[v] = true
	check(float(mean.call(mid)) > float(mean.call(edge)) + 5.0 and float(mean.call(edge)) >= float(mean.call(village)),
		"a big city's middle is taller than its edge, its edge than a small town (%.0f, %.0f, %.0f m)" % [mean.call(mid), mean.call(edge), mean.call(village)])
	check(spread.size() >= 6, "a city's middle has a mix of heights (%d)" % spread.size())
	check(towers > 0 and towers < 120, "and the odd tower (%d of 400)" % towers)
	check(float(village.max()) <= 6.0 * BuildingHeights.STOREY + BuildingHeights.GROUND, "a small town's blocks stay low (%.0f m)" % village.max())
	check(BuildingHeights.of(r, [10.0, 10.0, 22.0, 18.0, 0.0, 23.0, block, 0], kit) == 23.0
		and BuildingHeights.of(r, [10.0, 10.0, 22.0, 18.0, 0.0, 14.0, RealPack.BUILDING_KINDS.find("barn"), 0], kit) == 14.0,
		"a height the map gives is kept, and a barn is never guessed")
	check(BuildingHeights.of(r, [10.0, 10.0, 22.0, 18.0, 0.0, 14.0, block, 0], kit) == BuildingHeights.of(r, [10.0, 10.0, 22.0, 18.0, 0.0, 14.0, block, 0], kit),
		"the same building, the same height")
	check(BuildingHeights.of(r, [30200.0, 400.0, 8.0, 9.0, 0.0, 5.5, house, 0], kit) == 5.5, "a small town's houses stay as they were")
	var houses := {}
	for k in 50:
		houses[BuildingHeights.of(r, [float(k) * 9.0, 30.0, 12.0, 6.0, 0.0, 5.5, house, 0], kit)] = true
	check(houses.size() >= 2, "a city's town houses aren't all two storeys (%s)" % str(houses.keys()))
	# A street's neighbours mostly match: next-door blocks closer in height than blocks across town.
	var near := 0.0
	var far := 0.0
	for k in 200:
		var x := float(k) * BuildingHeights.STREET * 2.0 + 10.0   # (next door in the same street square)
		var a := BuildingHeights.guess("block", 20.0, 16.0, x, 0.0, 6.5, 0.9, "western_europe", 14.0)
		var b := BuildingHeights.guess("block", 20.0, 16.0, x + 4.0, 3.0, 6.5, 0.9, "western_europe", 14.0)
		var c := BuildingHeights.guess("block", 20.0, 16.0, x + 4000.0, 3000.0, 6.5, 0.9, "western_europe", 14.0)
		near += absf(a - b)
		far += absf(a - c)
	check(near < far * 0.8, "next-door blocks are closer in height than blocks across town (%.0f vs %.0f)" % [near, far])
