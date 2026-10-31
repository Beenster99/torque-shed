extends RefCounted
## Simon's new tanks, fairings and frames (the Cleaning list, item 12), run from tests/run_tests.gd
## (its _test_parts_refresh_* functions hand over to these): ten tanks and ten fairings in plain
## paint, trestle frames instead of the trellis ones, wrap-around bars, super-fat rear tyres and
## discs with their holes cut through, and old saves' parts moved over to the new ones.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A bike of `parts` with the code-built shapes the Classic look keeps (the new look's Blender-made
## ones are checked in tests/blender_parts_tests.gd).
func _model(parts: Dictionary) -> BikeModel:
	var m := BikeModel.new()
	m.look = BikeLook.CLASSIC
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
	return m


## Ten of each, one colour each (sprayed to taste), priced, every style with a tank that suits it,
## and no trellis frames left: two trestle frames, the engine hung from them.
func test_catalogue() -> void:
	var tanks: Array = PartsDB.by_kind["tank"]
	var fairings: Array = PartsDB.by_kind["fairing"]
	var schemes := (tanks + fairings).filter(func(id): var lk: Dictionary = PartsDB.get_part(id).get("look", {}); return lk.has("paint") or lk.has("accent"))
	var unpriced := (tanks + fairings).filter(func(id): return not PartsDB.get_part(id).has("price"))
	# (Thirteen tanks since three angular ones came in.)
	check(tanks.size() == 13 and fairings.size() == 10 and schemes.is_empty() and unpriced.is_empty(),
		"thirteen tanks and ten fairings, all plain and priced (%d, %d) %s %s" % [tanks.size(), fairings.size(), schemes, unpriced])
	var shapes := {}
	for id in tanks:
		shapes[str(PartsDB.get_part(id)["look"]["shape"])] = true
	var bare := PartsDB.STYLES.filter(func(s): return not tanks.any(func(id): return PartsDB.styles_of(id).has(s)))
	check(shapes.size() == tanks.size() and bare.is_empty() and shapes.keys().all(func(k): return BikeModel.TANK_SHAPES.has(k)),
		"each tank a shape of its own, and every style has one that suits it %s" % [bare])
	var frames: Array = PartsDB.by_kind["frame"]
	var trellis := frames.filter(func(id): return str(PartsDB.get_part(id).get("style", "")) == "trellis" or "trellis" in PartsDB.part_name(id).to_lower())
	var trestle := frames.filter(func(id): return str(PartsDB.get_part(id).get("style", "")) == "trestle")
	check(trellis.is_empty() and trestle.size() == 2, "no trellis frames, two trestle frames %s %s" % [trellis, trestle])
	var bad := []
	for old in PartsDB.retired:
		var now := PartsDB.current_id(old)
		if PartsDB.parts.has(old) or not (PartsDB.parts.has(now) or now == "none"):
			bad.append(old)
	check(PartsDB.retired.size() > 80 and bad.is_empty(), "every part taken out has one in its place (%d) %s" % [PartsDB.retired.size(), bad])


## An old save: its old tanks, fairings and trellis frames come back as the new ones, in the colour
## they were, on the bikes, in the blueprints and anywhere else a part's named.
func test_migrate() -> void:
	var red := Color(0.7, 0.1, 0.1)
	var xf := Transform3D(Basis(), Vector3(1, 2, 3))
	var old := {"items": {5: {"part": "cruiser_fatbob_flames", "color": red, "place": xf}, 6: {"part": "race_white_fairing"}},
		"bikes": {3: {"original": {"tank": "sport_red_two_tone", "frame": "chromoly_trellis", "engine": "twin_700"}}},
		"blueprints": {1: {"parts": ["adv_beak_red", "naked_trellis_green"]}}, "stock": {"tourer_blue": 2, "cafe_15": 1}}
	var now: Dictionary = PartsDB.migrate(old)
	var it: Dictionary = now["items"][5]
	check(it["part"] == "fatbob_23" and it["color"] == red and it["place"] == xf and now["items"][6]["part"] == "carbon_race_fairing",
		"the old flamed fat tank is the new fat bob tank, still red; the white race fairing the carbon one")
	check(now["bikes"][3]["original"] == {"tank": "sport_17", "frame": "steel_trestle", "engine": "twin_700"}
		and now["blueprints"][1]["parts"] == ["adventure_fairing", "alu_trestle"] and now["stock"] == {"touring_23": 2, "cafe_15": 1},
		"bikes, blueprints and lists keyed by part move over too: %s" % [now["stock"]])
	var b := PartsDB.sanitize_build({"tank": "mx_blue_tank", "fairing": "cafe_dome_cowl", "frame": "sm_trellis_red"})
	check(b["tank"] == "enduro_12" and b["fairing"] == "headlight_cowl" and b["frame"] == "steel_trestle",
		"a build naming old parts gets their new ones, not the stock parts")
	# And a whole save, written with old parts and opened again.
	Shed.start_new("Tester", 61)
	var saver := SaveGame.new()
	t.add_child(saver)
	var data := saver.capture()
	var bike: int = Shed.bikes.keys()[0]
	var tank := Shed.item_on(bike, "tank")
	data["shed"]["items"][tank]["part"] = "sm_white_tank"
	data["shed"]["items"][tank]["color"] = red
	check(saver.restore(data) and Shed.items[tank]["part"] == "enduro_12" and Shed.items[tank]["color"] == red,
		"a save with an old tank fitted opens with the new one in its place, in its own red")
	saver.queue_free()
	Shed.stop()


## The new bits drawn: a trestle frame's lattice and pivot plates with no rails round the engine,
## wrap-around bars, a 300 mm rear tyre on its fat wheel, and the holes through a drilled disc.
func test_drawn() -> void:
	var tr := _model({"frame": "steel_trestle", "engine": "vtwin_1000"})
	var plates := tr.find_children("*PivotPlate*", "", true, false)
	check(plates.size() == 2 and tr._slot_meshes.get("frame", []).size() > 12, "a trestle frame: its lattice and two pivot plates (%d pieces)" % tr._slot_meshes.get("frame", []).size())
	var cast := _model({"frame": "alu_trestle"})
	check(cast.find_children("*Trestle*", "", true, false).size() == 2, "the cast one has a deep beam a side")
	var wrap := _model({"guards": "wrap_bars"})
	check(wrap._slot_meshes.get("guards", []).size() == 3, "wrap-around bars: a hoop a side and a tube across")
	check(PartsDB.tyre_fit("fat_road_300", "fat_18_billet") == 0 and PartsDB.tyre_fit("fat_road_300", "cast_17") != 0
		and PartsDB.tyre_fit("fat_road_240", "fat_18_billet") == 0, "the super-fat tyres go on the fat billet wheel and nothing narrower")
	var fat := _model({"rear_wheel": "fat_18_billet", "rear_tyre": "fat_road_300"})
	check(is_equal_approx(fat._build.rear_tyre_width, 0.3), "a 300 mm rear tyre is drawn 300 mm wide")
	var face := BikeModel.disc_face("drilled").get_image()
	var holes := 0
	for k in 288:
		var a := k * TAU / 288.0
		var p := Vector2(cos(a), sin(a)) * 0.8 * 0.5 + Vector2(0.5, 0.5)
		if face.get_pixel(int(p.x * face.get_width()), int(p.y * face.get_height())).a < 0.5:
			holes += 1
	var plain := BikeModel.disc_face("round").get_image()
	check(holes > 40 and plain.get_pixel(int(0.5 * plain.get_width() + 0.4 * plain.get_width()), plain.get_height() / 2).a > 0.5,
		"a drilled disc has holes right through it (%d of 288 points round its middle row), a plain one none" % holes)
	var discs := _model({"front_disc": "drilled_280", "rear_disc": "solid_240"})
	check(discs.find_children("*Disc", "", true, false).size() == 2 and discs.find_children("*DiscCarrier*", "", true, false).size() == 1,
		"a drilled disc is a rotor and a dark carrier, a plain one a single piece")
	for m in [tr, cast, wrap, fat, discs]:
		m.queue_free()
