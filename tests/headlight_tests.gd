extends RefCounted
## The twin bug-eye headlights, the old-school square headlights and the angular LED streetfighter pair, run from tests/run_tests.gd
## (its _test_headlight_* functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()

## The new lamps, the styles each suits and how many glasses each lights.
const LAMPS := {
	"bugeye_twin": {"styles": ["naked", "sport"], "lenses": 2},
	"square_chrome": {"styles": ["classic", "tourer", "cafe"], "lenses": 1},
	"square_xl": {"styles": ["tourer", "adventure", "scrambler", "classic"], "lenses": 1},
	"triple_led": {"styles": ["naked", "sport", "roader"], "lenses": 2},
	"triple_led_rs": {"styles": ["naked", "sport"], "lenses": 2},
}


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A model of `parts` (sorted out like a real build), in the runner's tree.
func _model(parts: Dictionary) -> BikeModel:
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(BikeBuild.sensible_fork(parts, 7))))
	return m


## The headlight's glasses on a model, and how many of them are glowing.
static func _lenses(m: BikeModel) -> Array:
	var all: Array = m._slot_meshes.get("headlight", []).filter(func(mi): return str((mi as Node).name).begins_with("Lens"))
	var lit := all.filter(func(mi): return ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled)
	return [all.size(), lit.size()]


## Whether a model's headlight glows: every "head" lens lit and worn by the headlight's meshes.
## (A ridden bike's model is baked, its glasses merged into one mesh a material.)
static func _head_lit(m: BikeModel) -> bool:
	var heads: Array = m._lamps.filter(func(l): return l["group"] == "head").map(func(l): return l["mat"])
	var worn: Array = m._slot_meshes.get("headlight", []).filter(func(mi): return heads.has((mi as MeshInstance3D).material_override))
	return not worn.is_empty() and heads.all(func(mat): return (mat as StandardMaterial3D).emission_enabled)


## Everything on the bike but the headlight, in the model's space.
static func _outline(m: BikeModel) -> AABB:
	var box := AABB()
	var first := true
	for slot in m._slot_meshes:
		if slot == "headlight" or (m._slot_meshes[slot] as Array).is_empty():
			continue
		var b := m.slot_bounds(slot)
		box = b if first else box.merge(b)
		first = false
	return box


## In the catalogue: headlights, priced and weighed like the others, tagged with the styles they
## suit, and offered in the shop with that style picked (and not with another).
func test_catalogue() -> void:
	var masses: Array = PartsDB.by_kind["headlight"].map(func(id): return float(PartsDB.get_part(str(id)).get("mass", 0.0)))
	var lo: float = masses.min()
	var hi: float = masses.max()
	for id in LAMPS:
		var p := PartsDB.get_part(id)
		var price := Money.part_price(id)
		check(PartsDB.kind_of(id) == "headlight" and float(p["lumens"]) >= 800.0 and float(p["lumens"]) <= 3000.0
			and price >= 60 and price <= 200 and float(p["mass"]) >= 0.8 and float(p["mass"]) <= 2.4,
			"%s is a headlight: %d lm, £%d, %.1f kg (the others weigh %.1f to %.1f kg)" % [PartsDB.part_name(id), int(p["lumens"]), price, float(p["mass"]), lo, hi])
		check(PartsDB.styles_of(id) == LAMPS[id]["styles"], "%s suits %s" % [PartsDB.part_name(id), PartsDB.styles_text(id)])
	for id in ["bugeye_twin", "triple_led", "triple_led_rs"]:
		check(not PartsDB.part_name(id).to_lower().contains("triumph") and not PartsDB.part_name(id).to_lower().contains("speed triple"),
			"%s goes by what it looks like, not a maker's name" % PartsDB.part_name(id))
	Shed.start_new("Tester", 64)
	var pc := PartsComputer.new()
	t.add_child(pc)
	pc.fits_bike = 0
	pc.affordable_only = false
	for style in PartsDB.STYLES:
		pc.style_filter = style
		var listed := pc.listed("headlight")
		for id in LAMPS:
			check(listed.has(id) == (LAMPS[id]["styles"] as Array).has(style),
				"%s %s in the shop's headlights for %s" % [PartsDB.part_name(id), "is" if listed.has(id) else "isn't", PartsDB.style_phrase(style)])
	pc.queue_free()


## On every style's stock bike it suits and on every frame in the catalogue, each lamp draws on
## the fork (turning with the bars), sits inside the rest of the bike's outline, clears the
## front tyre, and has its glasses; the bug-eyes' fly-screen goes when a fairing is fitted.
func test_builds() -> void:
	for id in LAMPS:
		var bad := []
		var builds := 0
		var setups := []
		for style in LAMPS[id]["styles"]:
			var b: Dictionary = Contracts.style_build(style).duplicate()
			b["fairing"] = "none"
			setups.append([style, b])
		for frame in PartsDB.by_kind["frame"]:
			setups.append([str(frame), {"frame": str(frame)}])
		for s in setups:
			var parts: Dictionary = (s[1] as Dictionary).duplicate()
			parts["headlight"] = id
			var m := _model(parts)
			builds += 1
			var lamp := m.slot_bounds("headlight")
			var out := _outline(m).grow(0.03)
			var wheel := m.slot_bounds("front_wheel")
			var steered: bool = m._slot_meshes["headlight"].all(func(mi): return m._steer_node.is_ancestor_of(mi))
			var n: int = _lenses(m)[0]
			if not (lamp.size.length() > 0.1 and lamp.size.length() < 0.6 and out.encloses(lamp) and lamp.position.y > wheel.end.y - 0.02
					and steered and n == LAMPS[id]["lenses"]):
				bad.append("%s (%s in %s, %d glasses)" % [s[0], lamp, out, n])
			m.free()
		check(bad.is_empty(), "%s goes on all %d bikes, on the fork, inside the outline and clear of the tyre %s" % [PartsDB.part_name(id), builds, bad])
	var bare := _model({"frame": "alu_trestle", "headlight": "bugeye_twin"})
	var shielded := _model({"frame": "alu_trestle", "headlight": "bugeye_twin", "fairing": "flyscreen"})
	check(bare.find_children("FlyScreen*", "", true, false).size() == 1 and shielded.find_children("FlyScreen*", "", true, false).is_empty()
		and bare.find_children("BugEye*", "", true, false).size() == 2 and bare.find_children("LampBracket*", "", true, false).size() == 1,
		"the bug-eyes are a pair on a bracket under a little fly-screen, which makes way for a fitted fairing")
	bare.free()
	shielded.free()
	var tri := _model({"frame": "alu_trestle", "headlight": "triple_led"})
	var brows: Array = tri.find_children("DRL*", "", true, false)
	var drl_off := brows.all(func(mi): return not ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled)
	tri.set_lights(true, false)
	check(tri.find_children("TripleLamp*", "", true, false).size() == 2 and brows.size() == 2 and drl_off
		and brows.all(func(mi): return ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled),
		"the streetfighter pair are two angular lamps whose running-light brows come on with the ignition")
	tri.free()
	# In the shop (and loose on the bench) a headlight or tail unit is just the lamp: the little
	# stock indicators a bike wears beside them stay on the bike.
	for id in ["round_7", "triple_led"]:
		var shown := BikeModel.part_display(id, {})
		var lm: BikeModel = shown.get_meta("model")
		var ambers: Array = lm._lamps.filter(func(l): return str(l["group"]).begins_with("ind")).map(func(l): return l["mat"])
		var worn: Array = lm._slot_meshes["headlight"].filter(func(mi): return ambers.has((mi as MeshInstance3D).material_override))
		check(worn.is_empty() and lm._stock_pieces.is_empty(), "%s in the shop has no indicators on it (%d amber pieces, %d stock)" % [PartsDB.part_name(id), worn.size(), lm._stock_pieces.size()])
		shown.free()
	var chrome := _model({"headlight": "square_chrome"})
	var xl := _model({"headlight": "square_xl"})
	var cb: Array = chrome.find_children("Bezel*", "", true, false)
	var xb: Array = xl.find_children("Bezel*", "", true, false)
	check(cb.size() == 4 and xb.size() == 4 and ((cb[0] as MeshInstance3D).material_override as StandardMaterial3D).metallic > 0.9
		and ((xb[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.v < 0.2, "the square lamps have a bezel round the glass: chrome, or black on the XL")
	check(xl.slot_bounds("headlight").size.x > chrome.slot_bounds("headlight").size.x * 1.1 and chrome.slot_bounds("headlight").size.x > 0.17,
		"the extra-large square lamp is bigger again (%.2f m wide against %.2f m)" % [xl.slot_bounds("headlight").size.x, chrome.slot_bounds("headlight").size.x])
	chrome.free()
	xl.free()


## Dark when parked; with the ignition on and the headlight switched on every glass glows (two on
## the bug-eyes, one on a square lamp, the reflector's hot spot in each), and the beam is the
## lamp's own lumens; another player's bike wears the same lamp.
func test_lit() -> void:
	for id in LAMPS:
		var m := _model({"headlight": id})
		var dark: Array = _lenses(m)
		m.set_lights(true, false)
		var ign: Array = _lenses(m)
		m.set_lights(true, true)
		var on: Array = _lenses(m)
		var heads: Array = m._lamps.filter(func(l): return l["group"] == "head")
		var n: int = LAMPS[id]["lenses"]
		check(dark[1] == 0 and ign[1] == 0 and on[0] == n and on[1] == n and heads.size() >= 2
			and heads.all(func(l): return (l["mat"] as StandardMaterial3D).emission_enabled),
			"%s: dark parked and on the ignition alone, then %d lit with the headlight on (%d of %d glasses)" % [PartsDB.part_name(id), n, on[1], on[0]])
		m.free()
	var r: Dictionary = await t.ride({"headlight": "bugeye_twin"}, 0.3, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	bike.engine_on = true
	bike.beam = 1
	for i in 3:
		await t.get_tree().physics_frame
	var beam: SpotLight3D = bike.effects._beam
	check(bike.effects.light_on() and beam != null and is_equal_approx(float(beam.get_meta("lumens")), bike.build.headlight_lumens)
		and bike.build.headlight_lumens > 1000.0 and _head_lit(bike.model),
		"riding at night the bug-eyes throw a %d lm beam and their glasses glow" % roundi(bike.build.headlight_lumens))
	await t._done(r)
	var rb := RemoteBike.new()
	t.add_child(rb)
	rb.setup("Other", BikeBuild.new({"headlight": "square_xl"}), Color(0.2, 0.4, 0.9))
	var st := PackedFloat32Array()
	st.resize(25)
	st[6] = 1.0
	st[24] = 1.0
	rb.push_state(st)
	for i in 3:
		await t.get_tree().physics_frame
	var own := _model({"headlight": "square_xl"})
	var size := own.slot_bounds("headlight").size
	own.free()
	check(rb.model != null and rb.model.slot_bounds("headlight").size.distance_to(size) < 0.005 and size.x > 0.2,
		"another player's bike wears the same square headlight (%s)" % rb.model.slot_bounds("headlight").size)
	rb.queue_free()
