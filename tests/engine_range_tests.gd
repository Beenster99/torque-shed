extends RefCounted
## Simon's v0.39.0 engine round, run from tests/run_tests.gd (its _test_engine_range_* functions
## hand over to these): the smallest engines of most families and the big two-strokes taken out
## (old saves' ones become the nearest kept), one two-stroke heading, a one-valve flathead head,
## 45 and 60 degree V-twins for the American-style bikes, and 660 and 1100 cc triples.

var t: Node   # the test runner: check(), get_tree()

## Taken out, and what a save's copy of each becomes.
const GONE := {"2stroke_600": "2stroke_500", "2stroke_750": "2stroke_500", "2stroke_800": "2stroke_500",
	"2stroke_1000": "2stroke_500", "2stroke_1100": "2stroke_500", "2stroke_1200": "2stroke_500",
	"twin_50": "twin_500", "twin_125": "twin_500", "twin_350": "twin_500",
	"parallel_50": "parallel_600", "parallel_125": "parallel_600", "parallel_350": "parallel_600", "parallel_500": "parallel_600",
	"vtwin_50": "vtwin_750", "vtwin_125": "vtwin_750", "vtwin_350": "vtwin_750", "vtwin_500": "vtwin_750", "vtwin_600": "vtwin_750",
	"boxer_50": "boxer_350", "boxer_125": "boxer_350", "inline_50": "inline_500", "inline_125": "inline_500", "inline_350": "inline_500"}
## The new V-twins: their V and size.
const NEW_VTWINS := {"vtwin45_750": [45, 750], "vtwin45_883": [45, 883], "vtwin45_1200": [45, 1200], "vtwin45_1450": [45, 1450],
	"vtwin45_1800": [45, 1800], "vtwin60_1000": [60, 1000], "vtwin60_1200": [60, 1200], "vtwin60_1500": [60, 1500]}
const AMERICAN := ["cruiser", "bobber", "chopper"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _model(parts: Dictionary) -> BikeModel:
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
	return m


## The angle between a drawn V-twin's two barrels, in degrees.
static func _drawn_v(m: BikeModel) -> float:
	return rad_to_deg((m._cyls[0]["up"] as Vector3).angle_to(m._cyls[1]["up"] as Vector3))


## What's left, what's new, every engine tagged with the styles it suits and every style with
## engines, and one heading per family in the parts computer (one for the two-strokes).
func test_catalogue() -> void:
	var engines: Array = PartsDB.by_kind["engine"]
	var still := GONE.keys().filter(func(id): return PartsDB.parts.has(id))
	check(still.is_empty(), "the small engines and big two-strokes Simon listed are gone %s" % [still])
	for keep in ["twin_700", "single_250", "single_450", "twin_500", "boxer_350", "parallel_600", "vtwin_750", "inline_500",
			"2stroke_50", "2stroke_125", "2stroke_350", "2stroke_500", "four_1000", "triple_850"]:
		check(PartsDB.kind_of(keep) == "engine", "%s is still sold" % keep)
	check(PartsDB.DEFAULT_BUILD["engine"] == "twin_700" and PartsDB.parts.has("twin_700"), "the stock build's 700 cc twin stays")
	var too_small := engines.filter(func(id):
		var p := PartsDB.get_part(str(id))
		var cc := float(p["displacement"])
		match str(p["layout"]):
			"2stroke": return cc > 500.0
			"twin": return cc < 500.0
			"parallel": return cc < 600.0
			"vtwin": return cc < 750.0
			"boxer": return cc < 350.0
			"inline": return cc < 500.0
		return false)
	check(too_small.is_empty(), "no engine left in the ranges Simon took out %s" % [too_small])
	# The new V-twins: named for their V, tagged for the American-style bikes.
	for id in NEW_VTWINS:
		var p := PartsDB.get_part(id)
		var want: Array = NEW_VTWINS[id]
		check(str(p.get("layout", "")) == "vtwin" and int(p.get("cylinders", 0)) == 2 and roundi(float(p.get("displacement", 0.0))) == want[1]
			and is_equal_approx(PartsDB.v_angle(id), float(want[0])) and PartsDB.part_name(id) == "%d cc %d° V-twin" % [want[1], want[0]]
			and AMERICAN.all(func(s): return PartsDB.styles_of(id).has(s)),
			"%s: a %d degree V-twin of %d cc for cruisers, bobbers and choppers (%s)" % [id, want[0], want[1], PartsDB.styles_text(id)])
	check(is_equal_approx(PartsDB.v_angle("vtwin_1200"), 90.0) and is_equal_approx(PartsDB.v_angle("twin_700"), 0.0),
		"the V-twins without an angle are 90 degree ones; other layouts have no V")
	var bore := func(id: String) -> float:
		var p := PartsDB.get_part(id)
		return PI / 4.0 * pow(float(p["bore"]) / 10.0, 2.0) * float(p["stroke"]) / 10.0 * int(p["cylinders"])
	for id in NEW_VTWINS.keys() + ["triple_660", "triple_1100"]:
		var cc := float(PartsDB.get_part(id)["displacement"])
		check(absf(bore.call(id) - cc) / cc < 0.02, "%s: its bore and stroke make its size (%.0f cc)" % [PartsDB.part_name(id), bore.call(id)])
	# The 45s lope along low down; the 60s rev a bit more.
	var b45 := BikeBuild.new({"engine": "vtwin45_1200"})
	var b60 := BikeBuild.new({"engine": "vtwin60_1200"})
	var b90 := BikeBuild.new({"engine": "vtwin_1200"})
	check(b45.redline < b60.redline and b45.redline < b90.redline and b45.peak_torque_rpm < b60.peak_torque_rpm,
		"a 45 degree twin is done earliest (redlines %d, %d for the 60, %d for the 90)" % [roundi(b45.redline), roundi(b60.redline), roundi(b90.redline)])
	# The triples.
	for want in [[660, "triple_660"], [850, "triple_850"], [1100, "triple_1100"]]:
		var p := PartsDB.get_part(want[1])
		check(str(p.get("layout", "")) == "triple" and int(p.get("cylinders", 0)) == 3 and roundi(float(p.get("displacement", 0.0))) == want[0]
			and PartsDB.part_name(want[1]) == "%d cc inline triple" % want[0], "a %d cc inline triple" % want[0])
	var t660 := BikeBuild.new({"engine": "triple_660"})
	var t1100 := BikeBuild.new({"engine": "triple_1100"})
	var t850 := BikeBuild.new({"engine": "triple_850"})
	check(t1100.hp() > t850.hp() and t850.hp() > t660.hp() and t1100.hp() > t660.hp() * 1.4 and t660.redline > t1100.redline,
		"the 1100 triple is much stronger than the 660, the 850 between, the 660 revvier (%.0f, %.0f, %.0f hp)" % [t1100.hp(), t850.hp(), t660.hp()])
	# Every engine suits some styles, and every style has engines.
	var untagged := engines.filter(func(id): return PartsDB.styles_of(str(id)).is_empty())
	check(untagged.is_empty(), "every engine says which styles it suits %s" % [untagged])
	for style in PartsDB.STYLES:
		var suits := engines.filter(func(id): return PartsDB.styles_of(str(id)).has(style))
		check(suits.size() >= 2, "%s: %d engines suit it" % [PartsDB.style_name(style), suits.size()])
		var ref := str(Contracts.style_build(style)["engine"])
		check(PartsDB.styles_of(ref).has(style), "%s: its reference engine (%s) suits it" % [PartsDB.style_name(style), PartsDB.part_name(ref)])
		var offered := BikeShop.options("engine", style, {})
		check(offered.size() >= 2 and offered.all(func(id): return PartsDB.styles_of(str(id)).has(style)),
			"%s: the bike shop offers %d engines that suit it" % [PartsDB.style_name(style), offered.size()])
	for style in AMERICAN:
		var offered := BikeShop.options("engine", style, {})
		check(offered.has("vtwin45_1200") and offered.has("vtwin60_1200"), "a %s can be ordered with a 45 or a 60 degree V-twin" % PartsDB.style_noun(style))
	# No two engines go by the same name (two 1000 cc inline fours looked like one listed twice).
	var names := {}
	for id in engines:
		names[PartsDB.part_name(str(id))] = int(names.get(PartsDB.part_name(str(id)), 0)) + 1
	var twice := names.keys().filter(func(n): return int(names[n]) > 1)
	check(twice.is_empty(), "every engine has a name of its own %s" % [twice])
	# One heading per family in the shop's list, every family known; the two-strokes under one.
	var unknown := engines.filter(func(id): return not PartsComputer.ENGINE_FAMILIES.has(str(PartsDB.get_part(str(id)).get("type", ""))))
	check(unknown.is_empty(), "every engine's family has its place in the shop's list %s" % [unknown])
	var two := engines.filter(func(id): return str(PartsDB.get_part(str(id))["layout"]) == "2stroke")
	check(two.all(func(id): return str(PartsDB.get_part(str(id))["type"]) == "Two-stroke" and PartsDB.part_name(str(id)).contains("two-stroke ")),
		"the two-strokes are one family, each named for its cylinders: %s" % [two.map(func(id): return PartsDB.part_name(str(id)))])
	Shed.start_new("Tester", 39)
	var pc := PartsComputer.new()
	t.add_child(pc)
	await t.get_tree().process_frame
	pc.fits_bike = 0
	pc.affordable_only = false
	pc.set_style_filter("")
	pc.set_sort("shop")
	pc._show_kind("engine")
	var heads: Array = []
	for c in pc._variants.get_children():
		if c is Label and not c.is_queued_for_deletion() and not str(c.text).ends_with("MODELS") and not str(c.text).contains("SHOWN"):
			heads.append(str(c.text))
	var seen := {}
	for h in heads:
		seen[h] = int(seen.get(h, 0)) + 1
	check(heads.count("TWO-STROKE") == 1 and seen.values().all(func(n): return int(n) == 1) and heads.has("45° V-TWIN") and heads.has("60° V-TWIN"),
		"the parts computer lists the engines under one heading per family, one for the two-strokes: %s" % [heads])
	check(PartsComputer.styled_kind("engine"), "the style filter works on engines")
	pc.set_style_filter("chopper")
	var listed := pc.listed("engine")
	check(listed.has("vtwin45_1800") and not listed.has("inline_1000"), "picking choppers shows their engines, not a superbike's (%d)" % listed.size())
	pc.queue_free()
	Shed.stop()


## Old saves: every engine taken out becomes a kept one of the same layout, the nearest size, in
## the bikes, blueprints, stock, contracts and spares a save holds, and in a whole save opened again.
func test_retired() -> void:
	for old in GONE:
		var now := PartsDB.current_id(old)
		check(now == GONE[old] and PartsDB.kind_of(now) == "engine" and PartsDB.RETIRED_PARTS["engine"].has(old)
			and str(PartsDB.get_part(now)["layout"]) == old.get_slice("_", 0), "a saved %s becomes the %s" % [old, PartsDB.part_name(now)])
	var stale := {"items": {4: {"part": "vtwin_500", "color": Color(0.1, 0.1, 0.1)}, 5: {"part": "inline_125"}},
		"bikes": {2: {"original": {"engine": "parallel_350", "head": "four_valve"}}},
		"blueprints": {1: {"parts": {"engine": "2stroke_1200", "frame": "steel_cradle"}}},
		"stock": {"boxer_50": 1, "twin_700": 2},
		"jobs": {7: {"goals": [{"t": "batch", "item": "engine", "part": "twin_125", "layout": "twin"}]}}}
	var now: Dictionary = PartsDB.migrate(stale)
	check(now["items"][4]["part"] == "vtwin_750" and now["items"][4]["color"] == Color(0.1, 0.1, 0.1) and now["items"][5]["part"] == "inline_500",
		"engines in the shed: a 500 V-twin is a 750 one, a 125 four a 500, in its own colour")
	check(now["bikes"][2]["original"]["engine"] == "parallel_600" and now["blueprints"][1]["parts"]["engine"] == "2stroke_500"
		and now["stock"] == {"boxer_350": 1, "twin_700": 2} and now["jobs"][7]["goals"][0]["part"] == "twin_500",
		"and on bikes, in blueprints, in stock and in contracts: %s" % [now["stock"]])
	var b := PartsDB.sanitize_build({"engine": "vtwin_125"})
	check(b["engine"] == "vtwin_750", "a build naming an old engine gets the nearest kept one, not the stock twin")
	# A whole save with an old engine in a bike, opened again.
	Shed.start_new("Tester", 62)
	var saver := SaveGame.new()
	t.add_child(saver)
	var data := saver.capture()
	var bike: int = Shed.bikes.keys()[0]
	var engine := Shed.item_on(bike, "engine")
	data["shed"]["items"][engine]["part"] = "twin_50"
	check(saver.restore(data) and Shed.items[engine]["part"] == "twin_500" and Shed.build_of(bike).displacement == 500.0,
		"a save with a 50 cc twin fitted opens with the 500 cc one in its place, and the bike runs on it")
	saver.queue_free()
	Shed.stop()
	# Nothing in the game's code still asks for an engine that's gone.
	var named := []
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "parts_db.gd":
			continue
		var text := FileAccess.get_file_as_string("res://scripts/" + f)
		for old in GONE:
			if text.contains("\"%s\"" % old):
				named.append("%s in %s" % [old, f])
	check(named.is_empty(), "no script names an engine that's gone %s" % [named])


## The 45 and 60 degree twins drawn at their V (the 90s as they were), the flathead's flat lid
## with no cam cover, and the V and the valves heard: the firing intervals and the valve ticks.
func test_drawn_and_heard() -> void:
	for frame in ["steel_cradle", "cruiser_cradle"]:
		var m45 := _model({"frame": frame, "engine": "vtwin45_1200"})
		var m60 := _model({"frame": frame, "engine": "vtwin60_1200"})
		var m90 := _model({"frame": frame, "engine": "vtwin_1200"})
		var bay: bool = frame == "cruiser_cradle"
		var was := 45.0 if bay else rad_to_deg(2.0 * atan(0.6 / cos(0.6)))
		check(absf(_drawn_v(m45) - 45.0) < 0.5 and absf(_drawn_v(m60) - 60.0) < 0.5 and absf(_drawn_v(m90) - was) < 0.5,
			"in a %s: the barrels drawn at 45 and 60 degrees, a 90's as before (%.0f, %.0f, %.0f)" % [PartsDB.part_name(frame), _drawn_v(m45), _drawn_v(m60), _drawn_v(m90)])
		check(m45.slot_bounds("engine").size.length() > 0.2 and m45.slot_bounds("head").size.length() > 0.1, "a 45 degree twin draws, heads and all")
		for m in [m45, m60, m90]:
			m.queue_free()
	var flat := _model({"head": "one_valve_flathead", "engine": "vtwin45_883"})
	var ohv := _model({"head": "two_valve_stock", "engine": "vtwin45_883"})
	var row := _model({"head": "one_valve_flathead", "engine": "inline_750"})
	check(flat.find_children("FlatHead*", "", true, false).size() == 2 and row.find_children("FlatHead*", "", true, false).size() == 4
		and row.find_children("CamCover*", "", true, false).is_empty() and flat.slot_bounds("head").size.length() > 0.1,
		"a flathead is a flat finned lid on each barrel, no cam cover")
	check(flat.slot_bounds("head").size.y < ohv.slot_bounds("head").size.y + 0.001, "and it sits lower than a rocker box")
	for m in [flat, ohv, row]:
		m.queue_free()
	# The head on paper and on the road: one valve, soft, frugal, done early.
	check(PartsDB.spec_line("one_valve_flathead").contains("1 valve per cylinder"), "its spec line: %s" % PartsDB.spec_line("one_valve_flathead"))
	var one := BikeBuild.new({"head": "one_valve_flathead"})
	var two := BikeBuild.new({"head": "two_valve_stock"})
	check(one.valves == 1 and two.valves == 2 and one.hp() < two.hp() and one.redline < two.redline
		and float(one.summary()["economy"]) > float(two.summary()["economy"]) and one.engine_heat < two.engine_heat,
		"a flathead is gentler than the two-valve head: %.0f vs %.0f hp, redline %d vs %d, %.1f vs %.1f km/l" % [one.hp(), two.hp(),
			roundi(one.redline), roundi(two.redline), float(one.summary()["economy"]), float(two.summary()["economy"])])
	check(Money.part_price("one_valve_flathead") < Money.part_price("two_valve_stock") and Money.part_price("four_valve") > 0,
		"the cheapest head in the shop (£%d)" % Money.part_price("one_valve_flathead"))
	# Heard: each V fires at its own interval, 360 less the V.
	for want in [["vtwin45_1200", "45v", 315.0], ["vtwin60_1200", "60v", 300.0], ["vtwin_1200", "90v", 270.0]]:
		var spec := EngineSynth.spec_from_build(BikeBuild.new({"engine": want[0]}))
		var fires := EngineSynth.firing_events(spec)
		check(spec["crank"] == want[1] and fires.size() == 2 and is_equal_approx(float(fires[1][0]), want[2]),
			"a %s fires %d then %d degrees apart" % [PartsDB.part_name(want[0]), roundi(want[2]), 720 - roundi(want[2])])
	# A 45's tickover lumps: its firings wander more than a 90's do.
	var spread := func(spec: Dictionary) -> float:
		var rng := RandomNumberGenerator.new()
		rng.seed = 39
		var info := {"n": 48000, "cycles": 24, "rpm": float(spec["idle"])}
		var ts: Array = EngineSynth._cycle_events(spec, info, true, rng).filter(func(e): return int(e[3]) == 0).map(func(e): return float(e[0]))
		var gaps := []
		for i in range(1, ts.size()):
			gaps.append(ts[i] - ts[i - 1])
		var mean: float = gaps.reduce(func(a, x): return a + x, 0.0) / gaps.size()
		return sqrt(gaps.reduce(func(a, x): return a + (x - mean) * (x - mean), 0.0) / gaps.size()) / mean
	var s45 := EngineSynth.spec_from_build(BikeBuild.new({"engine": "vtwin45_1200"}))
	var s90 := EngineSynth.spec_from_build(BikeBuild.new({"engine": "vtwin_1200"}))
	check(spread.call(s45) > spread.call(s90) * 1.5, "a 45 degree twin's idle lumps along (spread %.3f vs %.3f)" % [spread.call(s45), spread.call(s90)])
	# The flathead's one valve ticks once a cycle a cylinder, and it's a sound of its own.
	var sf := EngineSynth.spec_from_build(BikeBuild.new({"head": "one_valve_flathead"}))
	var sv := EngineSynth.spec_from_build(BikeBuild.new({"head": "four_valve"}))
	check(sf["valves"] == 1 and sv["valves"] == 4 and EngineSynth.signature(sf) != EngineSynth.signature(sv),
		"the engine sound knows a flathead from a four-valve head")
