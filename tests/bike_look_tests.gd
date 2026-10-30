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
