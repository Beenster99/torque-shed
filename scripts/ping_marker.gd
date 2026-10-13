class_name PingMarker
extends Node3D
## A ping: a glowing outline round whatever a player pointed at (or a beacon where they
## pointed), with their name and what it is, seen through walls for a few seconds.

const LIFE := 6.0

var _age := 0.0
var _mats: Array[StandardMaterial3D] = []
var _label: Label3D


## `at` is the world point pinged. `frame` is {xf, box} round the thing pinged, or {} for a spot.
static func spawn(parent: Node, at: Vector3, frame: Dictionary, text: String, color: Color) -> PingMarker:
	var m := PingMarker.new()
	parent.add_child(m)
	m._build(at, frame, text, color)
	Sfx.play_at("ping", at, 2.0)
	return m


func _glow(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.render_priority = 10
	_mats.append(m)
	return m


func _build(at: Vector3, frame: Dictionary, text: String, color: Color) -> void:
	var bright := color.lightened(0.35)
	var top := at
	if not frame.is_empty():
		var xf: Transform3D = frame["xf"]
		var box: AABB = frame["box"].grow(0.02)
		# A wire box round the thing: twelve edges.
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var c := []
		for i in 8:
			c.append(xf * (box.position + Vector3(box.size.x * (i & 1), box.size.y * ((i >> 1) & 1), box.size.z * ((i >> 2) & 1))))
		for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])
		im.surface_end()
		var wire := MeshInstance3D.new()
		wire.mesh = im
		wire.material_override = _glow(bright, 0.95)
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wire)
		# And a faint fill so it reads from across the shed.
		var fill := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		fill.mesh = bm
		fill.transform = xf * Transform3D(Basis(), box.get_center())
		fill.material_override = _glow(bright, 0.18)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fill)
		top = xf * (box.get_center() + Vector3(0.0, box.size.y * 0.5, 0.0))
	else:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.22
		t.outer_radius = 0.28
		ring.mesh = t
		ring.position = at + Vector3.UP * 0.02
		ring.material_override = _glow(bright, 0.85)
		add_child(ring)
	# A beam up from it, and the label on top.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.9
	beam.mesh = cyl
	beam.position = top + Vector3.UP * 0.45
	beam.material_override = _glow(bright, 0.6)
	add_child(beam)
	_label = Label3D.new()
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 30
	_label.outline_size = 8
	_label.modulate = bright
	_label.render_priority = 11
	_label.outline_render_priority = 10
	_label.position = top + Vector3.UP * 1.0
	add_child(_label)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	var pulse := 0.65 + 0.35 * sin(_age * 7.0)
	var fade := clampf((LIFE - _age) / 1.0, 0.0, 1.0)
	for m in _mats:
		var base: float = m.get_meta("a") if m.has_meta("a") else m.albedo_color.a
		if not m.has_meta("a"):
			m.set_meta("a", base)
		m.albedo_color.a = base * pulse * fade
	_label.modulate.a = fade


## Pings whatever is under the middle of `camera`'s view, up to `reach` metres away, for the
## whole crew to see. Returns what was pinged, for the HUD.
static func ping_from(camera: Camera3D, exclude: Array, reach := 60.0) -> String:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | Workshop.INTERACT_LAYER)
	q.exclude = exclude
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var c: Object = hit["collider"]
	var action := {"a": "ping", "at": hit["position"], "what": "Over here"}
	if c.has_meta("bike") and Shed.bikes.has(int(c.get_meta("bike"))):
		var bike := int(c.get_meta("bike"))
		var slot := str(c.get_meta("slot"))
		action["item"] = Shed.item_on(bike, slot)
		action["what"] = "%s: %s" % [Shed.bikes[bike]["name"], PartsDB.slot_name(slot).to_lower()]
	elif c.has_meta("engine") and Shed.is_engine(int(c.get_meta("engine"))):
		var item := Shed.engine_item(int(c.get_meta("engine")), str(c.get_meta("slot")))
		action["item"] = item
		action["what"] = PartsDB.part_name(Shed.items[item]["part"]) if item != 0 else "Engine"
	elif c.has_meta("spot"):
		var item := Shed.item_at_spot(str(c.get_meta("spot")))
		var f := Shed.furniture_of_spot(str(c.get_meta("spot")))
		if item != 0:
			action["item"] = item
			action["what"] = PartsDB.part_name(Shed.items[item]["part"])
		elif not f.is_empty():
			action["furniture"] = int(f["id"])
			action["what"] = Shed.furniture_name(f)
	elif c.has_meta("item") and Shed.items.has(int(c.get_meta("item"))):
		action["item"] = int(c.get_meta("item"))
		action["what"] = PartsDB.part_name(Shed.items[int(c.get_meta("item"))]["part"])
	elif (c.has_meta("furniture") or c.has_meta("label")) and Shed.furniture.has(int(c.get_meta("furniture") if c.has_meta("furniture") else c.get_meta("label"))):
		var id := int(c.get_meta("furniture") if c.has_meta("furniture") else c.get_meta("label"))
		action["furniture"] = id
		action["what"] = Shed.furniture_name(Shed.furniture[id])
	elif c.has_meta("pc"):
		action["what"] = "Parts computer"
	elif c.has_meta("radio"):
		action["what"] = "Radio"
	elif c.has_meta("bin"):
		action["what"] = "Scrap bin"
	elif c.has_meta("door_switch"):
		action["what"] = "Roller door switch"
	elif c.has_meta("light_switch"):
		action["what"] = "Light switch"
	elif c is RemoteBike:
		action["what"] = "%s's bike" % (c as RemoteBike).player_name
	elif c is Bike:
		action["what"] = "My bike"
	Shed.request(action)
	return str(action["what"])


## Draws a ping the Shed sent out, round the thing it names if it can find it here.
static func show_ping(parent: Node, d: Dictionary, color: Color) -> PingMarker:
	var view: Node = parent.get_tree().get_first_node_in_group("workshop")
	var frame := {}
	if view:
		if int(d.get("item", 0)) != 0:
			frame = view.item_frame(int(d["item"]))
		elif int(d.get("furniture", 0)) != 0:
			frame = view.furniture_frame(int(d["furniture"]))
	return spawn(parent, d["at"], frame, "%s: %s" % [d.get("name", ""), d.get("what", "")], color)
