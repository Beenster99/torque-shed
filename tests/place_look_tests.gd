extends RefCounted
## Climate look (PlaceLook): the eight postcard places each get a look of their own, the rules that choose it (the kit
## by climate zone and altitude, the grass by the month's rain, autumn, crops, snow, the weather's odds), the satellite's
## ground, the sun's path by latitude and month, and the kits' plants. Profiles in, looks out, no scene, so each runs in
## a moment. Run from tests/run_tests.gd (its _test_place_look_* functions hand over to these).

var t: Node   # the test runner: check()

## The postcard places' cells (tests/postcards/places.json), whose baked profiles the postcards keep.
const PLACES := {"dales": "577_711", "bavaria": "550_764", "atlas": "485_690", "oaxaca": "428_333",
	"shodoshima": "497_1257", "coromandel": "212_1421", "pyrenees": "531_720", "polder": "570_739"}
const PROFILES := "res://tests/postcards/world/profile/c%s.json"


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func profile(place: String) -> Dictionary:
	return PlaceProfile.parse(JSON.parse_string(FileAccess.get_file_as_string(PROFILES % PLACES[place])))


static func _dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_eight_places() -> void:
	var want := {"dales": "temperate", "bavaria": "temperate", "atlas": "mediterranean", "oaxaca": "tropical_dry",
		"shodoshima": "temperate", "coromandel": "temperate", "pyrenees": "alpine", "polder": "temperate"}
	for month in [6, 10]:
		var looks := {}
		var kits := {}
		for place in PLACES:
			var l := PlaceLook.choose(profile(place), month)
			looks[place] = l
			kits[place] = l["kit"]
			if t.verbose:
				print("    %s in month %d: %s, grass %s, green %.2f, sky haze %.5f, weather %s, plants %s" % [place, month, l["kit"],
					(l["land"]["tarmac"] as Color).to_html(false), float(l["green"]), float(l["sky"]["haze"]), l["weather"], l["plants"]])
		check(kits == want, "in month %d each place's vegetation kit is its climate's: %s" % [month, kits])
		# No two places share a palette: their grass, woods, crops and sky are a fair way apart, or their plants differ.
		var close := []
		var names := PLACES.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: Dictionary = looks[names[i]]
				var b: Dictionary = looks[names[j]]
				var d := _dist(a["land"]["tarmac"], b["land"]["tarmac"]) + _dist(a["woods"], b["woods"]) \
					+ _dist(a["cover"]["crop"][0], b["cover"]["crop"][0]) + _dist(a["sky"]["horizon"], b["sky"]["horizon"]) \
					+ _dist(a["sky"]["top"], b["sky"]["top"])
				var grass := _dist(a["land"]["tarmac"], b["land"]["tarmac"])
				if t.verbose:
					print("    %s/%s: grass %.3f, palette %.3f" % [names[i], names[j], grass, d])
				if grass < 0.04 or d < 0.1:
					close.append("%s/%s (grass %.3f, palette %.3f)" % [names[i], names[j], grass, d])
		check(close.is_empty(), "in month %d the eight postcard places don't share a palette%s" % [month, "" if close.is_empty() else ": too close " + ", ".join(close)])
	var oct := {}
	for place in PLACES:
		oct[place] = PlaceLook.choose(profile(place), 10)
	check(oct["oaxaca"]["plants"].has("cactus") and oct["oaxaca"]["plants"].has("agave") and not oct["atlas"]["plants"].has("cactus"),
		"cactus and agave in Oaxaca, none in the Atlas (only the Americas have them)")
	check(oct["atlas"]["plants"].has("olive") and oct["pyrenees"]["plants"].has("tussock") and oct["dales"]["plants"].has("oak"),
		"olives in the Atlas, tussock grass in the Pyrenees, oaks in the Dales")
	check(oct["dales"]["bounds"][0] == "wall_hedge" and float(oct["polder"]["field_m"]) > float(oct["dales"]["field_m"]),
		"walls and hedges round small fields in the Dales, big open fields in the polder")
	var atlas: Color = oct["atlas"]["land"]["tarmac"]
	var dales: Color = oct["dales"]["land"]["tarmac"]
	check(atlas.r > atlas.g and dales.g > dales.r, "the Atlas's ground is tawny, the Dales' green (%s, %s)" % [atlas.to_html(false), dales.to_html(false)])


func test_rules() -> void:
	# Kits by zone and altitude.
	var base := {"lat": 45.0, "lon": 5.0, "altitude": {"min": 0, "mean": 100, "max": 300}}
	var kits := {}
	for z: Array in [["Af", "lowland"], ["Aw", "lowland"], ["BWh", "lowland"], ["Csa", "lowland"], ["Cfb", "lowland"],
			["Dfc", "lowland"], ["Dfb", "mountain"], ["ET", "upland"], ["Cfb", "high"]]:
		var p := base.duplicate(true)
		p["koppen"] = z[0]
		p["altitude_band"] = z[1]
		kits["%s %s" % z] = PlaceLook.kit_of(PlaceProfile.parse(p))
	check(kits.values() == ["tropical_wet", "tropical_dry", "arid", "mediterranean", "temperate", "boreal", "alpine", "alpine", "alpine"],
		"each climate zone's kit: %s" % kits)
	# The grass greens and browns with the month's rain.
	var atlas := profile("atlas")
	var dales := profile("dales")
	check(PlaceLook.greenness(atlas, 7) < 0.15 and PlaceLook.greenness(dales, 7) > 0.8 and PlaceLook.greenness(profile("oaxaca"), 8) > PlaceLook.greenness(profile("oaxaca"), 3),
		"the Atlas parched in July, the Dales lush, Oaxaca greener in its wet season than its dry")
	# The seasons: autumn colour in Bavaria in October, not June; spring in New Zealand in October; the crops by the month.
	var bav := profile("bavaria")
	var oct := PlaceLook.choose(bav, 10)
	check(float(oct["autumn"]) > 0.3 and float(PlaceLook.choose(bav, 6)["autumn"]) == 0.0 and oct["plants"].has("autumn_tree"),
		"Bavaria's woods turn in October (%.2f), not in June" % float(oct["autumn"]))
	check(int(PlaceLook.choose(profile("coromandel"), 10)["local_month"]) == 4 and float(PlaceLook.choose(profile("coromandel"), 10)["autumn"]) == 0.0,
		"October is spring in New Zealand")
	var crop_aug: Color = PlaceLook.choose(dales, 8)["cover"]["crop"][0]
	var crop_may: Color = PlaceLook.choose(dales, 5)["cover"]["crop"][0]
	check(crop_aug == PlaceLook.CROP["gold"] and crop_may == PlaceLook.CROP["green"], "the crops green in May and ripe in August")
	# Snow on the tops in a Pyrenean winter, none in summer.
	var pyr := profile("pyrenees")
	var jan := float(PlaceLook.choose(pyr, 1)["snow_line"])
	check(jan < float(pyr["altitude"]["max"]) and is_inf(float(PlaceLook.choose(pyr, 7)["snow_line"])),
		"snow down to %d m in the Pyrenees in January, none in July" % roundi(jan))
	# The weather's odds from the normals.
	var wd: Dictionary = PlaceLook.weather(dales, 11)
	var wa: Dictionary = PlaceLook.weather(atlas, 7)
	check(float(wd["rain"]) > float(wa["rain"]) * 3.0 and float(wa["clear"]) > 0.6 and float(wd["clear"]) < 0.3
		and absf(float(wd["clear"]) + float(wd["cloudy"]) + float(wd["fog"]) + float(wd["rain"]) - 1.0) < 0.01,
		"a Dales November is wet and grey %s, an Atlas July clear %s" % [wd, wa])
	# A dusty sky over a dry land, a deep clear blue up high.
	var sa: Dictionary = PlaceLook.choose(atlas, 7)["sky"]
	var sd: Dictionary = PlaceLook.choose(dales, 7)["sky"]
	check((sa["horizon"] as Color).r > (sd["horizon"] as Color).r and (sa["horizon"] as Color).b < (sd["horizon"] as Color).b,
		"the Atlas's horizon is dusty, the Dales' grey-blue")
	# Clear warm air over the Atlas and Oaxaca, thick grey in the Dales and over Shodoshima's damp inland sea.
	var haze := {}
	var warmth := {}
	for place in ["atlas", "oaxaca", "dales", "shodoshima", "pyrenees"]:
		var s: Dictionary = PlaceLook.choose(profile(place), 10)["sky"]
		haze[place] = float(s["haze"])
		warmth[place] = (s["fog"] as Color).r - (s["fog"] as Color).b
	check(haze["atlas"] < haze["dales"] - 0.0004 and haze["oaxaca"] < haze["shodoshima"] - 0.0004 and haze["pyrenees"] < haze["dales"]
		and warmth["atlas"] > warmth["dales"] + 0.08, "the air clear and warm in the Atlas and Oaxaca, thick in the Dales and Shodoshima %s %s" % [haze, warmth])
	# A guessed profile still gets a look.
	var g := PlaceLook.choose(PlaceProfile.guess(-3.0, 30.0), 3)
	check(str(g["kit"]) in PlaceLook.KITS and bool(g["guessed"]), "a guessed place gets a look (%s)" % g["kit"])


func test_ground() -> void:
	var cell := Vector2i(485, 690)
	var g := PlaceLook.ground_of(cell, profile("atlas"))
	check(int(g.get("size", 0)) == 16 and (g["rgb"] as PackedByteArray).size() == 16 * 16 * 3, "the Atlas's satellite tint, 16 px a side")
	var mid := RealRegion.cell_middle(cell)
	var c := PlaceLook.ground_at([g], mid.x, mid.y)
	check(c.a > 0.5 and c.r > c.b, "the Atlas from space is tawny (%s)" % c.to_html(false))
	check(PlaceLook.ground_at([g], mid.x + 1.0, mid.y).a == 0.0, "nothing off the cell")
	# Over the sea the tint is no use: Shodoshima's open water gives nothing.
	var sc := Vector2i(497, 1257)
	var sg := PlaceLook.ground_of(sc, profile("shodoshima"))
	var water := 0
	var n := int(sg["size"])
	for y in n:
		for x in n:
			var lat := float(sg["north"]) - (y + 0.5) / n * RealRegion.CELL_DEG
			var lon := float(sg["west"]) + (x + 0.5) / n * RealRegion.CELL_DEG
			if PlaceLook.ground_at([sg], lat, lon).a == 0.0:
				water += 1
	check(water > 40, "Shodoshima's sea pixels give no ground colour (%d of %d)" % [water, n * n])
	check(PlaceLook.ground_share(10.0) < 0.35 and PlaceLook.ground_share(1000.0) > 0.6, "the satellite takes over away from the road")


func test_sun() -> void:
	var held := Daylight.tint
	Daylight.tint = {}
	var plain := Daylight.sun_direction(12.0)
	Daylight.tint = {"lat": rad_to_deg(Daylight.TILT), "decl": 0.0}
	var same := Daylight.sun_direction(9.0).distance_to(Vector3(0, 0, 0)) > 0.0 and Daylight.sun_direction(12.0).distance_to(plain) < 0.001
	var noon := {}
	for place: Array in [["dales", 54.3, 6], ["dales", 54.3, 12], ["coromandel", -36.8, 6], ["oaxaca", 17.1, 6]]:
		Daylight.tint = {"lat": place[1], "decl": PlaceLook.declination(place[2])}
		var s := Daylight.sun_direction(12.0)
		noon["%s %d" % [place[0], place[2]]] = [roundi(rad_to_deg(asin(s.y))), s.z > 0.0]
	Daylight.tint = {"lat": 54.3, "decl": PlaceLook.declination(6)}
	var dawn := Daylight.sun_direction(4.5).y > 0.0
	Daylight.tint = held
	check(same, "with the old default path the sun is where it always was")
	check(absi(int(noon["dales 6"][0]) - 59) <= 2 and absi(int(noon["dales 12"][0]) - 12) <= 2 and bool(noon["dales 6"][1])
		and not bool(noon["coromandel 6"][1]) and int(noon["oaxaca 6"][0]) > 80,
		"the noon sun: high over the Dales in June, low in December, in the north in New Zealand, near overhead in Oaxaca %s" % noon)
	check(dawn and PlaceLook.day_hours(54.3, 6) > 16.5 and PlaceLook.day_hours(54.3, 12) < 7.5, "a Dales June has the sun up by half past four")


func test_plants() -> void:
	var kinds := {}
	for kit in PlaceLook.KITS:
		for k in PlaceLook.KIT[kit]["plants"]:
			kinds[k] = true
		kinds[PlaceLook.KIT[kit]["broad"]] = true
	for k in PlaceLook.AMERICAS_PLANTS:
		kinds[k] = true
	kinds["palm"] = true
	kinds["autumn_tree"] = true
	var bad := []
	for k in kinds:
		var m := AdventureProps.mesh(k)
		var sorted: bool = k in AdventureChunk.TREES or k in AdventureChunk.BUSHES or k in ["rock", "red_rock", "sheep"]
		var sized: bool = not (k in AdventureChunk.TREES) or AdventureChunk.TREE_SIZE.has(k)
		if m.get_surface_count() == 0 or not AdventureChunk.RANGES.has(k) or not sorted or not sized:
			bad.append(k)
	check(bad.is_empty(), "every kit's plants have a mesh, a draw range, a size and a cover to grow on %s" % ("" if bad.is_empty() else str(bad)))
