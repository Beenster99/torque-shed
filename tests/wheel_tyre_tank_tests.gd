extends RefCounted
## Simon's v0.39.0 wheels, tyres, tanks and mudguards, run from tests/run_tests.gd (its
## _test_wtt_* functions hand over to these): wheels listed by rim size, a tread on every tyre
## but a slick, three angular tanks, and mudguards that end in a curve rather than a square cut.

var t: Node   # the test runner: check(), get_tree()

## The angular tanks and the shapes they're drawn in.
const ANGULAR := {"angular_gt_19": "gt", "angular_naked_15": "streetfighter", "angular_sport_17": "wedge"}


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


## Whether wheel ids `ids` run smallest rim first, then narrowest rim, then by name.
static func _by_size(ids: Array) -> bool:
	for i in ids.size() - 1:
		if PartsDB.wheel_before(ids[i + 1], ids[i]):
			return false
	return true


## Wheels come smallest rim first wherever they're listed: the catalogue, the parts computer
## (under a heading for each size) and the new-bike shop's pickers.
func test_wheel_order() -> void:
	var wheels: Array = PartsDB.by_kind["wheel"]
	check(wheels.size() > 10 and _by_size(wheels), "the catalogue's wheels run smallest rim first: %s" % [wheels.map(func(w): return PartsDB.get_part(w)["diameter"])])
	var first := PartsDB.get_part(wheels[0])
	var last := PartsDB.get_part(wheels[wheels.size() - 1])
	check(float(first["diameter"]) == 16.0 and float(last["diameter"]) == 21.0, "16\" wheels first, 21\" last")
	# Same size: the narrower rim first.
	var seventeens := wheels.filter(func(w): return float(PartsDB.get_part(w)["diameter"]) == 17.0)
	var widths: Array = seventeens.map(func(w): return float(PartsDB.get_part(w)["rim_width"]))
	var sorted_widths := widths.duplicate()
	sorted_widths.sort()
	check(widths == sorted_widths, "17\" wheels narrowest rim first: %s" % [widths])
	var pc: Node = load("res://scripts/parts_computer.gd").new()
	pc.sort_key = "shop"
	var listed: Array = pc.listed("wheel")
	check(listed == wheels and _by_size(listed), "the parts computer lists wheels by size")
	check(pc.wheel_group("supermoto_16_5") == "16.5\" WHEELS" and pc.wheel_group("cast_17") == "17\" WHEELS",
		"each size has a heading: %s, %s" % [pc.wheel_group("supermoto_16_5"), pc.wheel_group("cast_17")])
	pc.sort_key = "price_up"
	check(pc.listed("wheel").size() == wheels.size(), "the other sorts still list every wheel")
	pc.free()
	for style in ["sport", "chopper", "adventure"]:
		var opts: Array = BikeShop.options("rear_wheel", style, {}).filter(func(w): return w != "none")
		check(_by_size(opts), "the bike shop's %s wheel picker runs by size" % style)


## Every tyre has a tread but a slick, a pattern suited to it, cut into the rubber.
func test_treads() -> void:
	var bad := []
	var stand := ["knobs", "blocks", "studs", "sipes"]
	for id in PartsDB.by_kind["tyre"]:
		var p := PartsDB.get_part(id)
		var tread := BikeModel.tread_pattern(p)
		var slick := str(p.get("style", "")) == "slick"
		if slick != (tread == "") or not (slick or TextureKit.TREADS.has(tread) or stand.has(tread)):
			bad.append("%s (%s)" % [id, tread])
	check(bad.is_empty(), "every tyre but a slick has a tread pattern, and slicks have none %s" % [bad])
	var expect := {"sport_road_190": "sport", "touring_road_150": "touring", "trail_road_110": "trail", "vintage_ribbed": "rib",
		"cruiser_whitewall_130": "cruiser", "fat_road_240": "cruiser", "knobbly_mx": "knobs", "adv_5050_110": "blocks"}
	for id in expect:
		check(BikeModel.tread_pattern(PartsDB.get_part(id)) == expect[id], "%s has a %s tread" % [id, expect[id]])
	# Each groove pattern has grooves in the crown and smooth sidewalls.
	for kind in TextureKit.TREADS:
		var low := 1.0
		var high := 0.0
		var wall := 1.0
		for i in 64:
			for j in 64:
				var h := TextureKit.tread_height(kind, i / 64.0, 0.5 + (j / 63.0 - 0.5) * TextureKit.TREAD_BAND * 1.9)
				low = minf(low, h)
				high = maxf(high, h)
			wall = minf(wall, TextureKit.tread_height(kind, i / 64.0, 0.1))
		check(low < 0.05 and high > 0.95 and wall == 1.0, "the %s tread has grooves (%.2f..%.2f), the wall none" % [kind, low, high])
	# On a bike: the road tyres' rubber carries its pattern, made once and shared; a slick's is plain.
	var m := _model({"frame": "alu_twin_spar", "front_tyre": "sport_road_120", "rear_tyre": "sport_road_190"})
	var tyres := _tyres(m)
	var mats: Array = tyres.map(func(mi): return (mi as MeshInstance3D).material_override as StandardMaterial3D)
	check(tyres.size() == 2 and mats.all(func(mt): return mt.get_meta("tread", "") == "sport" and mt.normal_texture != null and mt.albedo_texture != null),
		"both sport tyres have their grooves cut in")
	check(mats.size() == 2 and mats[0].normal_texture == mats[1].normal_texture, "the pattern's textures are shared, not made per tyre")
	var mesh: ArrayMesh = (tyres[0] as MeshInstance3D).mesh
	check(mesh != null and not (mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT] as PackedFloat32Array).is_empty(), "the tyre has tangents for its tread")
	m.queue_free()
	var s := _model({"frame": "alu_twin_spar", "front_tyre": "race_slick_120", "rear_tyre": "race_slick"})
	var slicks: Array = _tyres(s).map(func(mi): return (mi as MeshInstance3D).material_override as StandardMaterial3D)
	check(slicks.size() == 2 and slicks.all(func(mt): return not mt.has_meta("tread") and mt.normal_texture == null), "a slick is smooth")
	s.queue_free()


## The tyres on a model (the lofted meshes carrying their hoop sizes; a rim's barrel carries one too).
static func _tyres(m: BikeModel) -> Array:
	return m.find_children("*", "MeshInstance3D", true, false).filter(func(mi): return (mi as Node).has_meta("hoop") and (mi as MeshInstance3D).mesh is ArrayMesh)


## Three angular tanks, folded from creased panels, suiting naked bikes, tourers and sports bikes,
## that build on every kind of frame between the bars and the seat.
func test_angular_tanks() -> void:
	var covers := {}
	for id in ANGULAR:
		var p := PartsDB.get_part(id)
		check(not p.is_empty() and str(p["look"]["shape"]) == ANGULAR[id] and bool(BikeModel.TANK_SHAPES[ANGULAR[id]].get("facet", false)),
			"%s is in the catalogue, drawn faceted" % id)
		for st in PartsDB.styles_of(id):
			check(PartsDB.STYLE_NAMES.has(st), "%s suits a real style (%s)" % [id, st])
			covers[st] = true
	check(covers.has("naked") and covers.has("tourer") and covers.has("sport"), "they suit naked bikes, tourers and sports bikes %s" % [covers.keys()])
	for frame in ["alu_twin_spar", "steel_cradle", "steel_backbone"]:
		for id in ANGULAR:
			var m := _model({"frame": frame, "tank": id, "handlebars": "clip_ons"})
			var body: MeshInstance3D = m.find_child("TankBody", true, false)
			var verts := PackedVector3Array()
			if body and body.mesh:
				verts = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(verts.size() > 100, "%s on a %s builds a body (%d vertices)" % [id, frame, verts.size()])
			var tank := m.slot_bounds("tank")
			var seat := m.slot_bounds("saddle")
			check(tank.size.y > 0.1 and tank.position.z > m._head.z + 0.04 and tank.end.z < seat.position.z + 0.12,
				"%s on a %s sits between the bars and the seat" % [id, frame])
			if frame == "alu_twin_spar" and body:
				# Sharp creases: neighbouring panels' normals meet at an angle, not smoothly.
				var normals: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
				var at := {}   # a point on the skin -> the normals it's drawn with
				for i in verts.size():
					var key := verts[i].snappedf(0.0001)
					if not at.has(key):
						at[key] = []
					(at[key] as Array).append(normals[i])
				var sharp := 0
				for key in at:
					var ns: Array = at[key]
					if ns.any(func(n): return absf((n as Vector3).dot(ns[0])) < 0.95):
						sharp += 1
				check(sharp > 20, "%s has crisp creases (%d)" % [id, sharp])
				# The high front shoulder slopes down to the seat.
				var secs: Array = m._tank_secs
				var front_top := float(secs[4]["c"].y) + float(secs[4]["up"])
				var back_top := float(secs[secs.size() - 2]["c"].y) + float(secs[secs.size() - 2]["up"])
				check(front_top > back_top + 0.05, "%s rises at the front and slopes back (%.2f, %.2f)" % [id, front_top, back_top])
			m.queue_free()


## A model's mudguard tips in `slot`, each with its vertices in its own space (+Z out to the tip).
static func _tips(m: BikeModel, slot: String) -> Array:
	return (m._slot_meshes.get(slot, []) as Array).filter(func(mi): return is_instance_valid(mi) and str((mi as Node).name).begins_with("GuardTip"))


## Whether a tip is rounded: full width where it leaves the guard, narrowing towards its end, so
## its end isn't one straight cut across.
static func _rounded(tip: MeshInstance3D) -> bool:
	var verts: PackedVector3Array = tip.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var z0 := INF
	var z1 := -INF
	for v in verts:
		z0 = minf(z0, v.z)
		z1 = maxf(z1, v.z)
	var span := z1 - z0
	var root := 0.0
	var end := 0.0
	var end_zs := {}
	for v in verts:
		if v.z < z0 + span * 0.1:
			root = maxf(root, absf(v.x))
		if v.z > z1 - span * 0.3:
			end = maxf(end, absf(v.x))
		if absf(v.x) > root * 0.5 and root > 0.0:
			end_zs[snappedf(v.z, 0.002)] = true
	return span > 0.02 and root > 0.03 and end < root * 0.8 and end_zs.size() > 2


## Every front mudguard, and the rear mudguard on every kind of tail, ends in a curve.
func test_mudguard_ends() -> void:
	var flat := []
	for id in PartsDB.by_kind["front_mudguard"]:
		var m := _model({"frame": "steel_cradle", "front_mudguard": id})
		var tips := _tips(m, "front_mudguard")
		if tips.is_empty() or not tips.all(func(tip): return _rounded(tip)):
			flat.append("%s (%d tips)" % [id, tips.size()])
		m.queue_free()
	check(flat.is_empty(), "every front mudguard has rounded ends %s" % [flat])
	var styles := {}
	for id in PartsDB.by_kind["tail"]:
		var style := str(PartsDB.get_part(id).get("style", "classic"))
		if style == "tidy" or styles.has(style):
			continue   # a tail tidy is a tray, not a mudguard
		styles[style] = id
	var flat_rear := []
	for style in styles:
		var m := _model({"frame": "steel_cradle", "tail": styles[style]})
		var tips := _tips(m, "tail")
		if tips.is_empty() or not tips.all(func(tip): return _rounded(tip)) or not tips.all(func(tip): return m._rear_guard.has(tip)):
			flat_rear.append("%s (%s, %d tips)" % [styles[style], style, tips.size()])
		check(m.tyre_through_guard() <= 0.001, "the %s rear guard's tips clear the tyre (%.3f)" % [style, m.tyre_through_guard()])
		m.queue_free()
	check(flat_rear.is_empty() and styles.size() >= 3, "every kind of rear mudguard has rounded ends %s %s" % [flat_rear, styles.keys()])
