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
