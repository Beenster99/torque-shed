class_name HomeDisplay
extends Node3D
## One house's collection on show (see Collection and HomesView): the bikes in a ring in the
## courtyard, facing in, each with an information stand in front of it. Look at a stand and
## press {interact} for the bike's card (HomePanel): its numbers, and what you can do with it.
##
## Kept cheap: from the road each bike is a few boxes (one mesh for the whole ring). Only once
## you're within DRESS_NEAR is each drawn as itself, a baked model (BikeModel.baked), one every
## DRESS_GAP seconds across every house, never while you ride up; they're dropped again when
## you're well away. The stands are one mesh, their name boards a Label3D each, seen close up.

const DRESS_NEAR := 60.0
const UNDRESS_FAR := 160.0
const DRESS_GAP := 0.25
const CHECK_EVERY := 0.3
const BOX_RANGE := 350.0
const LABEL_RANGE := 18.0
static var _dressed_at := -100000

var plot := -1
var homes: HomesView
## spot -> {cid, sig}: what's on show now.
var shown := {}
## spot -> the bike drawn as itself (a Node3D holding its BikeModel).
var models := {}
var _boxes: MeshInstance3D
var _stands: MeshInstance3D
var _labels := {}          # spot -> Label3D
var _targets := {}         # spot -> StaticBody3D (what the crosshair finds)
var _solid: StaticBody3D   # the bikes' collision
var _wait := 0.0
var _near := false


func _ready() -> void:
	_solid = StaticBody3D.new()
	_solid.name = "Bikes"
	_solid.collision_layer = 1
	_solid.collision_mask = 0
	add_child(_solid)


## Catches up with the collection: what's on show where, and its stands.
func sync() -> void:
	var now := {}
	for spot in HomePlots.RING_SPOTS:
		var cid := Collection.on_show(plot, spot)
		if cid == 0:
			continue
		var e := Collection.entry(cid)
		var p: Dictionary = e.get("pack", {})
		var sig := "%d|%s|%d|%d" % [cid, str(e.get("name", "")), hash(p.get("bike", {}).get("slots", {})), int(e.get("value", 0))]
		now[spot] = {"cid": cid, "sig": sig}
	if str(now) == str(shown):
		return
	for spot in models.keys():
		if not now.has(spot) or str(now[spot]["sig"]) != str(shown.get(spot, {}).get("sig", "")):
			(models[spot] as Node).queue_free()
			models.erase(spot)
	shown = now
	_rebuild()


## The ring's stands, their boards and targets, the far-off boxes and the bikes' collision.
func _rebuild() -> void:
	for n in [_boxes, _stands]:
		if n:
			n.queue_free()
	for spot in _labels:
		(_labels[spot] as Node).queue_free()
	for spot in _targets:
		(_targets[spot] as Node).queue_free()
	_labels.clear()
	_targets.clear()
	for c in _solid.get_children():
		c.queue_free()
	_boxes = null
	_stands = null
	if shown.is_empty():
		return
	var inv := HomePlots.frame(plot).affine_inverse()
	var boxes := AdventureProps.new_arrays()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spot in shown:
		var cid := int(shown[spot]["cid"])
		var e := Collection.entry(cid)
		var xf: Transform3D = inv * HomePlots.ring_xf(plot, int(spot))
		var sxf: Transform3D = inv * HomePlots.stand_xf(plot, int(spot))
		var paint: Color = (e.get("pack", {}).get("bike", {}) as Dictionary).get("paint", Color.WHITE)
		_box_bike(boxes, xf, paint)
		_stand(st, sxf)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.75, 1.1, 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf * Transform3D(Basis(), Vector3(0.0, 0.55, 0.0))
		_solid.add_child(cs)
		var label := Label3D.new()
		label.name = "Board%d" % int(spot)
		label.text = "%s\n%s" % [str(e.get("name", "Bike")), Collection.money(int(e.get("value", 0)))]
		label.font_size = 36
		label.pixel_size = 0.0018
		label.outline_size = 6
		label.modulate = Color(0.95, 0.93, 0.88)
		label.outline_modulate = Color(0, 0, 0, 0.7)
		label.width = 260.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.transform = sxf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.06, 0.06))
		label.visibility_range_end = LABEL_RANGE
		add_child(label)
		_labels[spot] = label
		var body := StaticBody3D.new()
		body.name = "Stand%d" % int(spot)
		body.collision_layer = Workshop.INTERACT_LAYER
		body.collision_mask = 0
		body.set_meta("use_node", self)
		body.set_meta("use", {"what": "home_stand", "plot": plot, "spot": int(spot)})
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.7, 1.2, 0.5)
		var bcs := CollisionShape3D.new()
		bcs.shape = bs
		bcs.position.y = 0.6
		body.add_child(bcs)
		body.transform = sxf
		add_child(body)
		_targets[spot] = body
	_boxes = MeshInstance3D.new()
	_boxes.name = "Boxes"
	_boxes.mesh = AdventureProps.to_mesh(boxes)
	_boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boxes.visibility_range_end = BOX_RANGE
	add_child(_boxes)
	_stands = MeshInstance3D.new()
	_stands.name = "Stands"
	_stands.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.2
	_stands.material_override = m
	_stands.visibility_range_end = 120.0
	add_child(_stands)
	_update_boxes()


## A bike from far off: a few boxes on its side stand (as ParkedBike draws them), facing its -z.
static func _box_bike(a: Dictionary, xf: Transform3D, col: Color) -> void:
	var lean := xf * Transform3D(Basis(Vector3.BACK, 0.12), Vector3.ZERO)
	var tyre := Color(0.05, 0.05, 0.05)
	for wz: float in [-0.72, 0.72]:
		for turn: float in [0.0, PI * 0.25]:
			AdventureProps.box(a, lean * Transform3D(Basis(Vector3.RIGHT, turn), Vector3(0, 0.33, wz)) * Transform3D(Basis(), Vector3(0, -0.29, 0)),
				Vector3(0.12, 0.58, 0.58), tyre)
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.38, 0)), Vector3(0.28, 0.32, 0.9), Color(0.2, 0.2, 0.21))
	AdventureProps.box(a, lean * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.72, -0.12)), Vector3(0.34, 0.26, 0.6), col)
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.76, 0.45)), Vector3(0.28, 0.1, 0.6), Color(0.08, 0.08, 0.08))
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.95, -0.55)), Vector3(0.7, 0.04, 0.04), Color(0.1, 0.1, 0.1))


## An information stand: a post on a round foot with a sloping board on top, the board facing
## its +z (the middle of the ring).
static func _stand(st: SurfaceTool, xf: Transform3D) -> void:
	var steel := Color(0.18, 0.19, 0.2)
	WorldBuildings.cylinder(st, xf, 0.22, 0.22, 0.03, 12, steel, true)
	WorldBuildings.cylinder(st, xf, 0.035, 0.035, 0.95, 8, steel, false)
	var board := xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.0, 0.0))
	WorldBuildings.box(st, board, Vector3.ZERO, Vector3(0.56, 0.4, 0.03), steel)
	WorldBuildings.box(st, board, Vector3(0.0, 0.0, 0.017), Vector3(0.5, 0.34, 0.005), Color(0.08, 0.09, 0.1))
	WorldBuildings.box(st, board, Vector3(0.0, 0.15, 0.021), Vector3(0.5, 0.04, 0.004), UITheme.ACCENT)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = CHECK_EVERY
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or shown.is_empty():
		return
	var d := cam.global_position.distance_to(global_position)
	if d > UNDRESS_FAR:
		for spot in models.keys():
			(models[spot] as Node).queue_free()
		models.clear()
		_near = false
		_update_boxes()
		return
	var near := d < DRESS_NEAR
	if near != _near:
		_near = near
		for spot in models:
			(models[spot] as Node3D).visible = near
		_update_boxes()
	if not near:
		return
	for spot in shown:
		if models.has(spot):
			continue
		var w := get_tree().get_first_node_in_group("local_walker") as Node3D
		if w == null or not w.visible or not w.can_process():
			return   # riding up: wait till you're on foot
		if Time.get_ticks_msec() - _dressed_at < DRESS_GAP * 1000.0:
			_wait = 0.05
			return
		_dressed_at = Time.get_ticks_msec()
		dress(int(spot))
		return


## Draws the bike at `spot` as itself (a baked model), in place of its boxes.
func dress(spot: int) -> void:
	if not shown.has(spot) or models.has(spot):
		return
	var e := Collection.entry(int(shown[spot]["cid"]))
	var l := Collection.look(e.get("pack", {}))
	var build := BikeBuild.new(l["parts"], l["cond"], l["tune"])
	var holder := Node3D.new()
	holder.name = "Bike%d" % spot
	holder.transform = HomePlots.frame(plot).affine_inverse() * HomePlots.ring_xf(plot, spot)
	var lean := Node3D.new()
	holder.add_child(lean)
	var model := BikeModel.new()
	model.baked = true
	var lift := 0.0
	if build.has_side_stand:
		model.stand_pose = "side"
		lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(str(build.parts.get("side_stand", ""))).get("lean", 12.0))))
	elif build.has_centre_stand:
		model.stand_pose = "centre"
		lift = build.centre_lift
	model.position.y = build.rear_radius + lift
	model.geometry = l["geo"]
	lean.add_child(model)
	add_child(holder)
	model.build_from(build, l["paint"], l["fitted"], build.condition, false)
	holder.visible = _near
	models[spot] = holder
	_update_boxes()


## The boxes stand in for the bikes not drawn as themselves.
func _update_boxes() -> void:
	if _boxes:
		_boxes.visible = not (_near and models.size() >= shown.size())


## The crosshair on a stand (Walker's "use" target).
func use_text(t: Dictionary) -> String:
	var cid := Collection.on_show(plot, int(t.get("use", {}).get("spot", -1)))
	if cid == 0:
		return "An empty stand"
	var e := Collection.entry(cid)
	var mine := str(e["owner"]) == Collection.name_of(Shed.me())
	var lines := ["%s (%s's)" % [str(e["name"]), str(e["owner"])],
		"Worth %s" % Collection.money(int(e.get("value", 0))),
		"{interact}: its numbers, %s" % ("ride it out or sell it to the garage" if mine else "or make %s an offer for it" % str(e["owner"]))]
	return "\n".join(lines)


func use(t: Dictionary) -> void:
	var cid := Collection.on_show(plot, int(t.get("use", {}).get("spot", -1)))
	if cid != 0 and homes:
		homes.stand_used.emit(cid)
