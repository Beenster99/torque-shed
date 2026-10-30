extends RefCounted
## The bike look overhaul (see BikeLook): the Classic bikes kept just as they were, the Debug
## tab's switch between Classic and New, run from tests/run_tests.gd (its _test_bike_look_*
## functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()

## Each style's stock bike as the Classic look draws it, recorded when the overhaul began: a
## change to the shared bike code that alters a Classic bike fails here rather than slipping by.
## After a change meant to reach Classic too (a fix to a part's shape, say), write it again with
##   godot --headless --path . res://tests/test_runner.tscn -- --only=_test_bike_look_write_classic
const CLASSIC_PRINTS := "res://tests/bike_look_classic.json"


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A model of `parts` in `look`, in the runner's tree.
func _model(parts: Dictionary, look: String, baked := false) -> BikeModel:
	var m := BikeModel.new()
	m.look = look
	m.baked = baked
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)))
	return m


## What a style's stock bike looks like to the check: its pieces, triangles, materials, outline
## (to the centimetre) and the colours it's painted in.
static func fingerprint(m: BikeModel) -> Dictionary:
	var s := BikeLook.stats(m)
	var colours := {}
	var bounds := AABB()
	var first := true
	for slot in m._slot_meshes:
		for mi in m._slot_meshes[slot]:
			if not (mi is MeshInstance3D) or not (mi as MeshInstance3D).is_visible_in_tree():
				continue
			var g := mi as MeshInstance3D
			var box := m.global_transform.affine_inverse() * g.global_transform * g.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for i in g.mesh.get_surface_count():
				var mat := g.get_active_material(i)
				if mat is BaseMaterial3D:
					var c := (mat as BaseMaterial3D).albedo_color
					colours["%.2f,%.2f,%.2f,%.1f,%.1f" % [c.r, c.g, c.b, (mat as BaseMaterial3D).metallic, (mat as BaseMaterial3D).roughness]] = true
	var keys := colours.keys()
	keys.sort()
	return {"meshes": str(s["meshes"]), "tris": str(s["tris"]), "materials": str(s["materials"]),
		"size": "%.2f,%.2f,%.2f" % [bounds.size.x, bounds.size.y, bounds.size.z],
		"colours": "%08x" % str(keys).hash()}


func _prints() -> Dictionary:
	var out := {}
	for style in PartsDB.STYLES:
		var m := _model(Contracts.style_build(style), BikeLook.CLASSIC)
		out[style] = fingerprint(m)
		m.free()
	return out


## Every style's stock bike in the Classic look is just as it was when the overhaul began.
func test_classic_unchanged() -> void:
	var text := FileAccess.get_file_as_string(CLASSIC_PRINTS)
	var want = JSON.parse_string(text) if text != "" else null
	check(want is Dictionary and (want as Dictionary).size() == PartsDB.STYLES.size(), "the Classic bikes were recorded")
	if not (want is Dictionary):
		return
	var now := _prints()
	for style in PartsDB.STYLES:
		var a: Dictionary = want.get(style, {})
		var b: Dictionary = now[style]
		var same := a.size() == b.size()
		for k in b:
			same = same and str(a.get(k, "")) == str(b[k])
		check(same, "the Classic %s looks as it did %s" % [PartsDB.style_noun(style), "" if same else "(was %s, now %s)" % [a, b]])


func write_classic() -> void:
	var f := FileAccess.open(CLASSIC_PRINTS, FileAccess.WRITE)
	f.store_string(JSON.stringify(_prints(), "\t", true) + "\n")
	f.close()
	check(true, "wrote " + CLASSIC_PRINTS)


## Every part in the catalogue builds on a bike in the Classic look: each slot's parts are dealt
## out over a few bikes, one of each on every bike, and each shows.
func test_classic_every_part() -> void:
	var by_slot := {}
	var most := 0
	for id in PartsDB.parts:
		var slots := PartsDB.slots_for_kind(PartsDB.kind_of(id))
		if slots.is_empty():
			continue
		var slot: String = slots[0]
		if not by_slot.has(slot):
			by_slot[slot] = []
		by_slot[slot].append(id)
		most = maxi(most, (by_slot[slot] as Array).size())
	var missing := []
	var built := 0
	for i in most:
		var parts := {}
		for slot in by_slot:
			parts[slot] = by_slot[slot][i % (by_slot[slot] as Array).size()]
		var m := BikeModel.new()
		m.look = BikeLook.CLASSIC
		t.add_child(m)
		m.build_from(BikeBuild.new(parts))
		for slot in parts:
			var id: String = parts[slot]
			if str(m._build.parts.get(slot, "")) == id and (m._slot_meshes.get(slot, []) as Array).is_empty() and not missing.has(id):
				missing.append(id)
		built += 1
		m.free()
	check(built > 0 and missing.is_empty(), "every part in the catalogue (%d) is drawn by the Classic look, over %d bikes %s" % [PartsDB.parts.size(), built, missing])


## The Debug tab's switch: every bike in the tree is drawn again in the chosen look there and
## then, a bike pinned to a look stays, loose parts are left, and the choice is kept.
func test_switch() -> void:
	var was := Settings.bike_look
	Settings.bike_look = BikeLook.NEW
	var follows := _model(Contracts.style_build("cafe"), "")
	var pinned := _model(Contracts.style_build("cafe"), BikeLook.CLASSIC)
	var loose := BikeModel.assembly_display({"tank": Contracts.style_build("cafe")["tank"]}, {})
	t.add_child(loose)
	var first := follows.get_child(0)
	var pinned_first := pinned.get_child(0)
	var loose_count := (loose.get_meta("model") as Node).get_child_count()
	check(follows.drawn_look() == BikeLook.NEW and pinned.drawn_look() == BikeLook.CLASSIC, "a bike draws in the player's look unless pinned to one")
	BikeLook.choose(BikeLook.CLASSIC)
	check(Settings.bike_look == BikeLook.CLASSIC and follows.drawn_look() == BikeLook.CLASSIC, "choosing Classic switches the look")
	check(not is_instance_valid(first) or first.is_queued_for_deletion(), "a bike following the player's look is drawn again at once")
	check(is_instance_valid(pinned_first), "a bike pinned to its own look is left as it is")
	check((loose.get_meta("model") as Node).get_child_count() == loose_count, "a loose part stays a loose part")
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	check(str(cfg.get_value("display", "bike_look", "")) == BikeLook.CLASSIC, "the choice is kept in the settings")
	BikeLook.choose(BikeLook.NEW)
	check(follows.drawn_look() == BikeLook.NEW and follows.get_child_count() > 0, "and back to New")
	var tab := DebugTab.new()
	t.add_child(tab)
	var picker := tab.find_child("BikeLookPicker", true, false) as OptionButton
	check(picker != null and picker.item_count == 2 and picker.get_item_text(picker.selected) == "New",
		"the Debug tab has the Bike look switch, showing the look in use")
	tab.free()
	follows.free()
	pinned.free()
	loose.free()
	BikeLook.choose(was)


## The new look's budgets, per stock bike of each style ridden past (see BikeLookNew): draws
## for the bike itself (the rider's aside, out of this overhaul), shadow draws, and the
## triangles drawn a mate's bike's distance off (30 m) and far down the road (120 m).
const BUDGET := {"draws": 40, "shadow_draws": 45, "tris_near": 26000, "tris_far": 22000}


func test_new_budgets() -> void:
	BikeLookNew.lods_now = true
	var over := []
	var worst := {}
	for style in PartsDB.STYLES:
		var parts := Contracts.style_build(style)
		var classic := _model(parts, BikeLook.CLASSIC, true)
		var m := _model(parts, BikeLook.NEW, true)
		var c := BikeLook.stats(classic)
		var s := BikeLook.stats(m)
		var got := {"draws": s["draws"] - s["rider_draws"], "shadow_draws": s["shadow_draws"], "tris_near": s["tris_lod1"], "tris_far": s["tris_lod2"]}
		for k in BUDGET:
			worst[k] = maxi(int(worst.get(k, 0)), int(got[k]))
			if got[k] > BUDGET[k]:
				over.append("%s %s %d" % [style, k, got[k]])
		if got["draws"] * 3 > c["draws"] - c["rider_draws"] or s["tris"] != c["tris"]:
			over.append("%s: %d draws, Classic %d; %d triangles close up, Classic %d" % [style, got["draws"], c["draws"] - c["rider_draws"], s["tris"], c["tris"]])
		classic.free()
		m.free()
	BikeLookNew.lods_now = false
	check(over.is_empty(), "every style's bike is inside the new look's budgets, at most a third of Classic's draws and all its detail close up %s %s" % [worst, over])


## Every part of a new-look bike is just where it is in Classic, merged or not, and the Bike
## detail setting moves where its levels of detail change: the rider's own bike at the setting,
## everyone else's a step lower.
func test_new_parts_and_detail() -> void:
	BikeLookNew.lods_now = true
	var parts := Contracts.style_build("scrambler")
	var classic := _model(parts, BikeLook.CLASSIC, true)
	var m := _model(parts, BikeLook.NEW, true)
	var off := []
	for slot in classic._slot_meshes:
		var a := classic.slot_bounds(slot)
		var b := m.slot_bounds(slot)
		# A bent tube's own box is a touch looser than round its corners: a few mm either way.
		if a.position.distance_to(b.position) > 0.004 or a.end.distance_to(b.end) > 0.004:
			off.append("%s %s / %s" % [slot, a, b])
	check(off.is_empty() and not m._shared.is_empty(), "every part is the same size and in the same place as in Classic %s" % [off])
	var was := Settings.gfx_bike_detail
	Settings.gfx_bike_detail = "high"
	var mine := _model(parts, BikeLook.NEW, true)
	mine.own_rider = true
	BikeLook.apply_detail(t.get_tree())
	var bias := func(model: BikeModel) -> float:
		return (model._shared[0] as GeometryInstance3D).lod_bias
	check(BikeLook.detail_of(mine) == "high" and BikeLook.detail_of(m) == "medium" and bias.call(mine) > bias.call(m),
		"your bike is drawn at the Bike detail setting, everyone else's a step lower")
	Settings.gfx_bike_detail = "low"
	BikeLook.apply_detail(t.get_tree())
	var lods = (m._shared[0] as MeshInstance3D).mesh.get_meta(&"lod_tris")
	check(BikeLook.detail_of(mine) == "low" and BikeLook.detail_of(m) == "low"
		and BikeLook.lod_tris(lods, 15.0, bias.call(m)) < BikeLook.lod_tris(lods, 15.0, BikeLook.LOD_BIAS["ultra"]),
		"Low thins bikes out nearer than Ultra, and nobody's drops below Low")
	Settings.gfx_bike_detail = was
	BikeLook.apply_detail(t.get_tree())
	BikeLookNew.lods_now = false
	classic.free()
	m.free()
	mine.free()


## M1: each finish is told apart for the shader's close-up detail, and an exhaust colours with
## heat by its head, more the more it's been used.
func test_finishes() -> void:
	var F := BikeLookNew.Finish
	var red := Color(0.7, 0.1, 0.08)
	var black := Color(0.05, 0.05, 0.05)
	var got := [BikeLookNew.finish_of(red, 0.0, 0.3, 0.7, ""), BikeLookNew.finish_of(red, 0.5, 0.35, 0.8, ""),
		BikeLookNew.finish_of(Color.WHITE, 1.0, 0.1, 0.0, ""), BikeLookNew.finish_of(Color.WHITE, 1.0, 0.25, 0.0, ""),
		BikeLookNew.finish_of(black, 0.0, 0.9, 0.0, ""), BikeLookNew.finish_of(red, 0.0, 0.6, 0.0, "grain"),
		BikeLookNew.finish_of(black, 0.25, 0.3, 1.0, "carbon"), BikeLookNew.finish_of(Color.WHITE, 1.0, 0.38, 0.0, "brushed"),
		BikeLookNew.finish_of(red, 0.6, 0.45, 0.0, "")]
	var want := [F.PAINT, F.METAL_FLAKE, F.CHROME, F.ALLOY, F.RUBBER, F.LEATHER, F.CARBON, F.BRUSHED, F.PLAIN]
	check(got == want, "paint, metallic paint, chrome, alloy, rubber, leather, carbon and brushed are told apart %s" % [got])
	var hottest := {}
	for wear in [0.0, 0.9]:
		var cond := {}
		for s in PartsDB.SLOTS:
			cond[s] = {"wear": wear}
		var parts := Contracts.style_build("classic")
		var m := BikeModel.new()
		m.look = BikeLook.NEW
		m.baked = true
		t.add_child(m)
		m.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)), Color(0.7, 0.12, 0.1), {}, cond)
		var hot := 0.0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if (mi as MeshInstance3D).material_override != BikeShader.material() or mesh == null:
				continue
			var c3 = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM3]
			if c3 is PackedFloat32Array:
				for i in range(1, (c3 as PackedFloat32Array).size(), 4):
					hot = maxf(hot, c3[i])
		hottest[wear] = hot
		check(not m._exhaust_ports.is_empty(), "the exhaust's ports are known (wear %.1f)" % wear)
		m.free()
	check(hottest[0.0] > 0.1 and hottest[0.9] > hottest[0.0] * 2.0 and hottest[0.9] <= 1.0,
		"a new exhaust shows a little heat colour by the head, a well-used one much more %s" % [hottest])


## M2: a part's wear and the brake dust on the wheels ride on its vertices for the shader, and
## the rain wets every bike at once.
func test_wear_and_wet() -> void:
	var seen := {}
	for wear in [0.0, 0.8]:
		var cond := {}
		for s in PartsDB.SLOTS:
			cond[s] = {"wear": wear}
		var m := BikeModel.new()
		m.look = BikeLook.NEW
		m.baked = true
		t.add_child(m)
		m.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("roader"))), Color(0.7, 0.12, 0.1), {}, cond)
		var most := Vector2.ZERO   # the most wear, and the most dust
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if (mi as MeshInstance3D).material_override != BikeShader.material() or mesh == null:
				continue
			var c3 = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM3]
			if c3 is PackedFloat32Array:
				for i in range(0, (c3 as PackedFloat32Array).size(), 4):
					most = Vector2(maxf(most.x, c3[i + 2]), maxf(most.y, c3[i + 3]))
		seen[wear] = most
		m.free()
	check(seen[0.0] == Vector2.ZERO and is_equal_approx(seen[0.8].x, 0.8) and seen[0.8].y > 0.5,
		"a fresh bike shows no wear or brake dust, a worn one both %s" % [seen])
	BikeShader.set_wet(1.0)
	var wet := float(BikeShader.material().get_shader_parameter("wet"))
	BikeShader.set_wet(0.0)
	check(is_equal_approx(wet, 1.0) and is_zero_approx(float(BikeShader.material().get_shader_parameter("wet"))),
		"the rain wets the bikes, and they dry again")
