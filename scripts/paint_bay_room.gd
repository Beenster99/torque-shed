class_name PaintBayRoom
extends Node3D
## The paint mixing bay as drawn (see PaintBay for its rules): a narrow white room off the
## paint shop's east wall, through a sliding glass door at its front end. Along the east wall
## the mixing bench with its digital scale, the tint rack over it and the shaker at the end;
## the tin shelf by the door; the swatch wall down the west wall; the daylight booth across the
## back with the spray-out panel stand in front of it; the masking tape on its hook by the door.
## It's lit on the paint shop's light switch.
##
## What changes (tins, swatch cards, the test card, the kit the garage has bought) is redrawn
## when it changes; the tin on the scale, the bottle being poured and the stirring stick move
## every frame, from the host's state and what the local player is doing at the bench
## (PaintBayRoom.live, set by PaintBench).

const GLASS_REACH := 1.7
const BOOTH_LIGHTS := [
	["DAYLIGHT", Color(0.97, 0.98, 1.0), 2.4],
	["SHOP LIGHT", Color(0.86, 1.0, 0.9), 2.0],
	["SUNSET", Color(1.0, 0.55, 0.28), 2.6],
]

## What the local player is doing at the bench, for drawing it before the host hears of it:
## {g: grams poured not yet on the host's tin, code: the tint, tilt: 0..1, stir: stir not yet sent,
## stirring: bool}. PaintBench keeps it up to date.
static var live := {}

var ws: Node3D
var bench_camera: Camera3D
var _mats := {}
var _dyn: Node3D
var _sig := ""
var _door_leaf: Node3D
var _door_open := 0.0
var _scale_label: Label3D
var _bench_tin: Node3D
var _bench_tin_sig := ""
var _paint_disc: MeshInstance3D
var _pour_bottle: Node3D
var _pour_code := ""
var _stream: MeshInstance3D
var _stick: Node3D
var _stir_angle := 0.0
var _shaker_body: Node3D
var _shaker_tin: Node3D
var _shaker_sig := ""
var _probe: ReflectionProbe
var _lights: Array[Light3D] = []
var _glow: Array[StandardMaterial3D] = []
var _lit_shown := true
var _pour_seen := {"sig": "", "t": 0.0}
var _stir_seen := {"v": 0.0, "t": 0.0}
var _t := 0.0


func build(workshop: Node3D) -> void:
	ws = workshop
	add_to_group("paint_bay_room")
	_make_materials()
	_build_shell()
	_build_door()
	_build_bench()
	_build_booth()
	_build_fixtures()
	_build_lights()
	_dyn = Node3D.new()
	_dyn.name = "Dynamic"
	add_child(_dyn)
	bench_camera = Camera3D.new()
	bench_camera.name = "BenchCamera"
	bench_camera.fov = 52.0
	add_child(bench_camera)
	bench_camera.look_at_from_position(PaintBay.BENCH_EYE, PaintBay.SCALE_AT + Vector3(0.12, 0.12, 0.0), Vector3.UP)
	Shed.changed.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------------------- materials

func _mat(color: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m


func _make_materials() -> void:
	_mats["white"] = _mat(Color(0.92, 0.93, 0.94), 0.0, 0.4)
	_mats["cladding"] = _mat(Color(0.36, 0.38, 0.4), 0.3, 0.6)
	_mats["roof"] = _mat(Color(0.3, 0.31, 0.33), 0.4, 0.5)
	_mats["floor"] = _mat(Color(0.62, 0.63, 0.64), 0.0, 0.35)
	_mats["bench"] = _mat(Color(0.32, 0.25, 0.18), 0.0, 0.8)
	_mats["steel"] = _mat(Color(0.78, 0.8, 0.82), 0.9, 0.22)
	_mats["cabinet"] = _mat(Color(0.25, 0.35, 0.5), 0.2, 0.55)
	_mats["dark"] = _mat(Color(0.08, 0.08, 0.09), 0.2, 0.5)
	_mats["grey"] = _mat(Color(0.45, 0.45, 0.46), 0.0, 0.9)   # the booth's neutral grey
	_mats["alu"] = _mat(Color(0.7, 0.72, 0.74), 0.85, 0.3)
	_mats["tin"] = _mat(Color(0.82, 0.83, 0.85), 0.85, 0.28)
	_mats["tape"] = _mat(Color(0.9, 0.83, 0.62), 0.0, 0.85)
	_mats["wood"] = _mat(Color(0.75, 0.62, 0.42), 0.0, 0.8)
	_mats["card"] = _mat(Color(0.95, 0.95, 0.93), 0.0, 0.7)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.76, 0.8, 0.18)
	glass.metallic = 0.3
	glass.metallic_specular = 0.9
	glass.roughness = 0.03
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = glass
	var lcd := _mat(Color(0.1, 0.16, 0.12), 0.0, 0.3)
	lcd.emission_enabled = true
	lcd.emission = Color(0.25, 0.45, 0.3)
	lcd.emission_energy_multiplier = 0.6
	_mats["lcd"] = lcd


# ---------------------------------------------------------------------------- building blocks

func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


func _solid(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	if mat != null:
		_box(body, Vector3.ZERO, size, mat)
	return body


## An invisible click target (Workshop.INTERACT_LAYER) carrying `meta` for the walker.
func _target(parent: Node3D, center: Vector3, size: Vector3, meta: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.position = center
	for key in meta:
		body.set_meta(key, meta[key])
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


func _label(parent: Node3D, text: String, at: Vector3, rot_y: float, size := 0.0016, color := Color(0.1, 0.1, 0.12)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = 32
	l.outline_size = 0
	l.modulate = color
	l.position = at
	l.rotation.y = rot_y
	l.double_sided = false
	parent.add_child(l)
	return l


static func _cylinder(r: float, h: float, mat: Material, sides := 18) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	return mi


# ---------------------------------------------------------------------------- the room

func _build_shell() -> void:
	var r := PaintBay.ROOM
	var h := PaintBay.HEIGHT
	var cx := r.position.x + r.size.x * 0.5
	var cz := r.position.y + r.size.y * 0.5
	var floor_mi := _box(self, Vector3(cx, 0.006, cz), Vector3(r.size.x, 0.012, r.size.y), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Back, front and east walls, and the roof; the paint shop's east wall is this room's west side.
	_solid(Vector3(cx, h * 0.5, r.position.y - 0.1), Vector3(r.size.x + 0.2, h, 0.2), _mats["cladding"])
	_solid(Vector3(cx, h * 0.5, r.end.y + 0.1), Vector3(r.size.x + 0.2, h, 0.2), _mats["cladding"])
	_solid(Vector3(r.end.x + 0.075, h * 0.5, cz), Vector3(0.15, h, r.size.y + 0.4), _mats["cladding"])
	_solid(Vector3(cx, h + 0.08, cz), Vector3(r.size.x + 0.3, 0.12, r.size.y + 0.4), _mats["roof"])
	# White inside, the west face round the doorway.
	_box(self, Vector3(cx, h * 0.5, r.position.y + 0.005), Vector3(r.size.x, h, 0.01), _mats["white"])
	_box(self, Vector3(cx, h * 0.5, r.end.y - 0.005), Vector3(r.size.x, h, 0.01), _mats["white"])
	_box(self, Vector3(r.end.x - 0.005, h * 0.5, cz), Vector3(0.01, h, r.size.y), _mats["white"])
	for seg in Workshop._wall_runs(r.position.y, r.end.y, PaintBay.DOOR_Z, PaintBay.DOOR_HALF):
		_box(self, Vector3(r.position.x + 0.005, h * 0.5, seg[0]), Vector3(0.01, h, seg[1]), _mats["white"])
	_box(self, Vector3(r.position.x + 0.005, (h + PaintBay.DOOR_HEIGHT) * 0.5, PaintBay.DOOR_Z),
		Vector3(0.01, h - PaintBay.DOOR_HEIGHT, PaintBay.DOOR_HALF * 2.0), _mats["white"])
	var ceiling := _box(self, Vector3(cx, h - 0.005, cz), Vector3(r.size.x, 0.01, r.size.y), _mats["white"])
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Signs: over the door on the paint shop side, and the bay's name inside.
	_label(self, "PAINT MIXING", Vector3(PaintBay.WALL_X - 0.11, PaintBay.DOOR_HEIGHT + 0.22, PaintBay.DOOR_Z), -PI * 0.5, 0.0035)
	_label(self, "MIXING BAY  ·  bases and tints from the parts computer (Paint supplies)", Vector3(r.end.x - 0.012, 2.62, 64.8),
		-PI * 0.5, 0.0016)


## The sliding glass door: a framed leaf that slides along the wall (towards the back of the
## room) whenever someone's near it.
func _build_door() -> void:
	_door_leaf = Node3D.new()
	_door_leaf.name = "GlassDoor"
	_door_leaf.position = Vector3(PaintBay.WALL_X - 0.14, 0.0, PaintBay.DOOR_Z)
	add_child(_door_leaf)
	var w := PaintBay.DOOR_HALF * 2.0 + 0.06
	var hh := PaintBay.DOOR_HEIGHT
	_box(_door_leaf, Vector3(0.0, hh * 0.5, 0.0), Vector3(0.02, hh - 0.08, w - 0.08), _mats["glass"])
	for side in [-1.0, 1.0]:
		_box(_door_leaf, Vector3(0.0, hh * 0.5, side * (w * 0.5 - 0.02)), Vector3(0.04, hh, 0.04), _mats["alu"])
	_box(_door_leaf, Vector3(0.0, hh - 0.02, 0.0), Vector3(0.04, 0.04, w), _mats["alu"])
	_box(_door_leaf, Vector3(0.0, 0.03, 0.0), Vector3(0.04, 0.06, w), _mats["alu"])
	_box(_door_leaf, Vector3(-0.03, 1.05, -w * 0.5 + 0.1), Vector3(0.03, 0.4, 0.025), _mats["alu"])
	# The track over it.
	_box(self, Vector3(PaintBay.WALL_X - 0.14, PaintBay.DOOR_HEIGHT + 0.04, PaintBay.DOOR_Z - 0.45), Vector3(0.05, 0.06, 1.9), _mats["alu"])


func _build_bench() -> void:
	var b := PaintBay.BENCH
	var top := PaintBay.BENCH_TOP
	var cx := b.position.x + b.size.x * 0.5
	var cz := b.position.y + b.size.y * 0.5
	# The worktop and the cupboards under it (redrawn in stainless with the upgrade: see _refresh).
	var body := _solid(Vector3(cx, top * 0.5, cz), Vector3(b.size.x, top, b.size.y), null)
	body.name = "MixingBench"
	_target(self, Vector3(cx, top + 0.08, cz), Vector3(b.size.x, 0.16, b.size.y), {"paint_bay": "bench"})
	# The digital scale.
	var s := PaintBay.SCALE_AT
	_box(self, s + Vector3(0.0, 0.02, 0.0), Vector3(0.28, 0.04, 0.3), _mats["dark"])
	_box(self, s + Vector3(0.0, 0.043, 0.0), Vector3(0.22, 0.006, 0.22), _mats["steel"])
	_box(self, s + Vector3(-0.15, 0.03, 0.0), Vector3(0.03, 0.04, 0.18), _mats["lcd"])
	_scale_label = _label(self, "0 g", s + Vector3(-0.168, 0.032, 0.0), -PI * 0.5, 0.0009, Color(0.6, 1.0, 0.7))
	_scale_label.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	_scale_label.rotate_object_local(Vector3.RIGHT, -0.5)
	# The tint rack: shelves over the bench, the stock rack's and the effects rack's.
	for y in PaintBay.RACK_Y:
		_box(self, Vector3(PaintBay.RACK_X, float(y) - 0.01, PaintBay.RACK_Z0 + 6.5 * PaintBay.RACK_STEP), Vector3(0.22, 0.02, 14 * PaintBay.RACK_STEP + 0.1),
			_mats["wood"])
	_box(self, Vector3(PaintBay.RACK_X + 0.1, (float(PaintBay.RACK_Y[0]) + float(PaintBay.RACK_Y[1])) * 0.5 + 0.1, PaintBay.RACK_Z0 + 6.5 * PaintBay.RACK_STEP),
		Vector3(0.02, 0.75, 14 * PaintBay.RACK_STEP + 0.1), _mats["wood"])
	_label(self, "TINTS", Vector3(PaintBay.RACK_X - 0.112, float(PaintBay.RACK_Y[0]) - 0.05, PaintBay.RACK_Z0 + 3.5 * PaintBay.RACK_STEP), -PI * 0.5, 0.0012)
	# The shaker housing at the far end.
	_shaker_body = Node3D.new()
	_shaker_body.position = PaintBay.SHAKER_AT
	add_child(_shaker_body)
	_target(self, PaintBay.SHAKER_AT + Vector3(0.0, 0.18, 0.0), Vector3(0.36, 0.36, 0.36), {"paint_bay": "shaker"})
	# The tin shelf by the door: three shelves of four.
	for y in PaintBay.SHELF_Y:
		_box(self, Vector3(PaintBay.SHELF_X + 0.05, float(y) - 0.012, PaintBay.SHELF_Z), Vector3(0.38, 0.024, 1.3), _mats["steel"])
	for side in [-1.0, 1.0]:
		_box(self, Vector3(PaintBay.SHELF_X + 0.05, 0.85, PaintBay.SHELF_Z + side * 0.66), Vector3(0.38, 1.7, 0.03), _mats["steel"])
	_blocker(Vector3(PaintBay.SHELF_X + 0.05, 0.85, PaintBay.SHELF_Z), Vector3(0.38, 1.7, 1.34))
	for i in PaintBay.SHELF_SLOTS:
		var at := PaintBay.slot_xf(i).origin
		_target(self, at + Vector3(0.0, 0.09, 0.0), Vector3(0.3, 0.2, 0.28), {"paint_bay": "slot", "slot": i})
	_label(self, "TINS", Vector3(PaintBay.SHELF_X - 0.15, 1.75, PaintBay.SHELF_Z), -PI * 0.5, 0.0015)
	# A bin for empty tins, between the shelf and the door.
	var bin_at := Vector3(16.72, 0.0, 69.55)
	var bin := _cylinder(0.17, 0.5, _mats["dark"])
	bin.position = bin_at + Vector3(0.0, 0.25, 0.0)
	add_child(bin)
	_blocker(bin_at + Vector3(0.0, 0.25, 0.0), Vector3(0.34, 0.5, 0.34))
	_target(self, bin_at + Vector3(0.0, 0.4, 0.0), Vector3(0.4, 0.3, 0.4), {"paint_bay": "bin"})
	_label(self, "EMPTY TINS", bin_at + Vector3(-0.172, 0.35, 0.0), -PI * 0.5, 0.0009, Color(0.9, 0.9, 0.9))


func _blocker(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## The daylight booth across the back: three bays in neutral grey, each lit its own way, with a
## copy of the test card in each so you can see how the colour holds up.
func _build_booth() -> void:
	var b := PaintBay.BOOTH
	var y0 := PaintBay.BOOTH_Y.x
	var y1 := PaintBay.BOOTH_Y.y
	var w := b.size.x / 3.0
	_box(self, Vector3(b.position.x + b.size.x * 0.5, y0 - 0.03, b.position.y + b.size.y * 0.5), Vector3(b.size.x, 0.06, b.size.y), _mats["grey"])
	_box(self, Vector3(b.position.x + b.size.x * 0.5, y1 + 0.03, b.position.y + b.size.y * 0.5), Vector3(b.size.x, 0.06, b.size.y), _mats["grey"])
	_box(self, Vector3(b.position.x + b.size.x * 0.5, (y0 + y1) * 0.5, b.position.y + 0.02), Vector3(b.size.x, y1 - y0, 0.02), _mats["grey"])
	for i in 4:
		_box(self, Vector3(b.position.x + i * w, (y0 + y1) * 0.5, b.position.y + b.size.y * 0.5), Vector3(0.02, y1 - y0, b.size.y), _mats["grey"])
	# Its cabinet under it.
	_solid(Vector3(b.position.x + b.size.x * 0.5, (y0 - 0.06) * 0.5, b.position.y + b.size.y * 0.5), Vector3(b.size.x, y0 - 0.06, b.size.y), _mats["cabinet"])
	for i in 3:
		var cx := b.position.x + (i + 0.5) * w
		var spec: Array = BOOTH_LIGHTS[i]
		var spot := SpotLight3D.new()
		spot.position = Vector3(cx, y1 - 0.02, b.position.y + b.size.y * 0.7)
		spot.rotation.x = -PI * 0.5 + 0.35
		spot.spot_angle = 38.0
		spot.spot_range = 1.4
		spot.light_color = spec[1]
		spot.light_energy = float(spec[2])
		spot.shadow_enabled = false
		add_child(spot)
		_label(self, str(spec[0]), Vector3(cx, y1 + 0.1, b.end.y + 0.002), 0.0, 0.0012)
		var lamp := _mat(spec[1], 0.0, 0.4)
		lamp.emission_enabled = true
		lamp.emission = spec[1]
		lamp.emission_energy_multiplier = 2.0
		_box(self, Vector3(cx, y1 - 0.005, b.position.y + b.size.y * 0.7), Vector3(w * 0.6, 0.012, 0.05), lamp)
	_target(self, Vector3(b.position.x + b.size.x * 0.5, (y0 + y1) * 0.5, b.position.y + b.size.y * 0.5), Vector3(b.size.x, y1 - y0, b.size.y),
		{"paint_bay": "booth"})
	# The spray-out panel stand in front of it: a post and arm the test card clips to.
	var s := PaintBay.STAND_AT
	_box(self, s + Vector3(0.0, 0.02, 0.0), Vector3(0.4, 0.04, 0.4), _mats["dark"])
	_box(self, s + Vector3(0.0, 0.6, 0.0), Vector3(0.04, 1.2, 0.04), _mats["alu"])
	_blocker(s + Vector3(0.0, 0.6, 0.0), Vector3(0.4, 1.2, 0.4))
	_target(self, s + Vector3(0.0, 1.35, 0.0), Vector3(0.5, 0.5, 0.3), {"paint_bay": "stand"})


## The masking tape's hook, the swatch wall's rail and a few posters.
func _build_fixtures() -> void:
	var t := PaintBay.TAPE_AT
	_box(self, t + Vector3(0.02, 0.0, 0.0), Vector3(0.04, 0.02, 0.02), _mats["alu"])
	_target(self, t + Vector3(0.06, -0.04, 0.0), Vector3(0.14, 0.18, 0.18), {"paint_bay": "tape"})
	_label(self, "MASKING TAPE", t + Vector3(0.012, 0.14, 0.0), PI * 0.5, 0.001)
	_label(self, "SWATCHES", Vector3(PaintBay.SWATCH_X + 0.002, PaintBay.SWATCH_TOP + 0.36, PaintBay.SWATCH_Z0 + 3.5 * PaintBay.SWATCH_STEP.x),
		PI * 0.5, 0.0025)


func _build_lights() -> void:
	var r := PaintBay.ROOM
	var h := PaintBay.HEIGHT
	var glow := _mat(Color(1, 1, 1), 0.0, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(0.98, 0.99, 1.0)
	glow.emission_energy_multiplier = 4.0
	_glow.append(glow)
	for z in [62.0, 65.4, 68.6]:
		_box(self, Vector3(r.position.x + r.size.x * 0.5, h - 0.04, z), Vector3(0.18, 0.04, 1.4), glow)
		var spot := SpotLight3D.new()
		spot.position = Vector3(r.position.x + r.size.x * 0.5, h - 0.12, z)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 75.0
		spot.spot_range = 4.5
		spot.light_energy = 1.4
		spot.light_color = Color(0.97, 0.99, 1.0)
		spot.shadow_enabled = true
		add_child(spot)
		_lights.append(spot)
	_probe = ReflectionProbe.new()
	_probe.position = Vector3(r.position.x + r.size.x * 0.5, h * 0.5, r.position.y + r.size.y * 0.5)
	_probe.size = Vector3(r.size.x + 0.1, h, r.size.y + 0.1)
	_probe.interior = true
	_probe.box_projection = true
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color(0.82, 0.84, 0.88)
	_probe.ambient_color_energy = 0.6
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)


func _set_lit(on: bool) -> void:
	_lit_shown = on
	for l in _lights:
		l.visible = on
	for m in _glow:
		m.emission_energy_multiplier = 4.0 if on else 0.0
	_probe.ambient_color_energy = 0.6 if on else 0.0
	_probe.intensity = 1.0 if on else 0.15


# ---------------------------------------------------------------------------- models

## A tin of paint, standing on its base: the label round it in the paint's colour, a lid (or,
## open on the scale, the paint showing).
static func tin_model(tin: Dictionary, open := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Tin"
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.82, 0.83, 0.85)
	metal.metallic = 0.85
	metal.roughness = 0.28
	var body := _cylinder(0.055, 0.125, metal)
	body.position.y = 0.0625
	root.add_child(body)
	var s: Dictionary = tin.get("mix", {}) if tin.get("mix") is Dictionary else PaintBay.spec_of(tin)
	var band_m := StandardMaterial3D.new()
	band_m.albedo_color = s.get("color", Color(0.5, 0.5, 0.5))
	band_m.roughness = 0.5
	var band := _cylinder(0.0556, 0.07, band_m)
	band.position.y = 0.06
	root.add_child(band)
	if open:
		var paint := _cylinder(0.05, 0.004, PaintMix.material(s, float(s.get("flat", 0.0))), 24)
		paint.name = "Paint"
		paint.position.y = 0.118
		root.add_child(paint)
	else:
		var lid := _cylinder(0.057, 0.008, metal)
		lid.position.y = 0.128
		root.add_child(lid)
	var nm := str(tin.get("name", ""))
	if nm != "":
		var l := Label3D.new()
		l.text = nm.left(14)
		l.pixel_size = 0.0006
		l.font_size = 32
		l.modulate = Color(1, 1, 1) if Color(band_m.albedo_color).get_luminance() < 0.5 else Color(0.05, 0.05, 0.05)
		l.position = Vector3(0.0, 0.06, 0.057)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		root.add_child(l)
	return root


## The roll of masking tape.
static func tape_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Tape"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.83, 0.62)
	m.roughness = 0.85
	var roll := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.028
	tm.outer_radius = 0.05
	tm.rings = 18
	tm.ring_segments = 8
	roll.mesh = tm
	roll.material_override = m
	roll.rotation.x = PI * 0.5
	root.add_child(roll)
	return root


## A tint bottle: its body the tint's colour, a black cap.
static func bottle_model(code: String) -> Node3D:
	var root := Node3D.new()
	var t: Dictionary = PaintMix.TINTS.get(code, {})
	var m := StandardMaterial3D.new()
	m.albedo_color = t.get("color", Color.WHITE)
	m.roughness = 0.35
	match str(t.get("kind", "")):
		"alu", "sparkle", "flake":
			m.metallic = 0.85
			m.roughness = 0.25
		"pearl":
			m.metallic = 0.3
			m.roughness = 0.2
		"candy", "chameleon":
			m.metallic = 0.6
			m.roughness = 0.15
	var body := _cylinder(0.032, 0.1, m, 12)
	body.position.y = 0.05
	root.add_child(body)
	var cap_m := StandardMaterial3D.new()
	cap_m.albedo_color = Color(0.06, 0.06, 0.07)
	var cap := _cylinder(0.014, 0.04, cap_m, 10)
	cap.position.y = 0.12
	root.add_child(cap)
	var label_m := StandardMaterial3D.new()
	label_m.albedo_color = Color(0.95, 0.95, 0.93)
	var l := Label3D.new()
	l.text = code
	l.pixel_size = 0.0008
	l.font_size = 32
	l.modulate = Color(0.05, 0.05, 0.05)
	l.outline_modulate = Color(1, 1, 1)
	l.outline_size = 6
	l.position = Vector3(0.0, 0.05, 0.034)
	root.add_child(l)
	return root


## A test card or swatch: a white card with the paint sprayed on it (all over, or with the
## curved panel's bend to show the flop), its name under it.
func _card(parent: Node3D, s: Dictionary, size: Vector2, curved := false) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var flat := float(s.get("flat", 0.0))
	if curved:
		# A curved panel: the paint seen at every angle at once.
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.6
		cm.bottom_radius = size.x * 0.6
		cm.height = size.y
		cm.radial_segments = 32
		cm.rings = 1
		cyl.mesh = cm
		cyl.material_override = PaintMix.material(s, flat)
		cyl.position.z = -size.x * 0.45
		cyl.scale = Vector3(1.0, 1.0, 0.5)
		root.add_child(cyl)
	else:
		_box(root, Vector3(0.0, 0.0, -0.002), Vector3(size.x + 0.02, size.y + 0.02, 0.003), _mats["card"])
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = size
		face.mesh = q
		face.material_override = PaintMix.material(s, flat)
		root.add_child(face)
	return root


# ---------------------------------------------------------------------------- what changes

func _refresh() -> void:
	if not is_inside_tree():
		return
	var st := PaintBay._st()
	var tin_bits := []
	for id in PaintBay.tins():
		var t: Dictionary = PaintBay.tins()[id]
		if str(t.get("at", "")) == "shelf":
			tin_bits.append("%d:%d:%s:%s:%.2f" % [int(id), int(t.get("ref", -1)), str(t.get("code", "")), str(t.get("name", "")), float(t.get("litres", 0.0))])
	tin_bits.sort()
	var tape_out := false
	for p in st["held"]:
		if str(st["held"][p].get("kind", "")) == "tape":
			tape_out = true
	var kits := []
	for k in PaintBay.KIT:
		if PaintBay.kit(k):
			kits.append(k)
	var sig := "%s|%s|%s|%s|%s|%s" % [",".join(tin_bits), str(PaintBay.swatch_order()), str(st["test"].get("n", 0)), ",".join(kits), str(tape_out),
		str(PaintBay.stock().keys().filter(func(c): return PaintBay.stock_of(str(c)) > 0.5))]
	if sig == _sig:
		return
	_sig = sig
	for c in _dyn.get_children():
		c.queue_free()
	_draw_bench_top()
	_draw_rack()
	_draw_shelf()
	_draw_swatches()
	_draw_test_card()
	_draw_shaker_body()
	if not tape_out:
		var roll := tape_model()
		roll.position = PaintBay.TAPE_AT + Vector3(0.06, -0.05, 0.0)
		roll.rotation.y = PI * 0.5
		_dyn.add_child(roll)
	if PaintBay.kit("meter"):
		# The colour meter on the booth's ledge.
		var at := Vector3(PaintBay.BOOTH.end.x - 0.25, PaintBay.BOOTH_Y.x, PaintBay.BOOTH.end.y - 0.12)
		_box(_dyn, at + Vector3(0.0, 0.03, 0.0), Vector3(0.08, 0.06, 0.16), _mats["dark"])
		_box(_dyn, at + Vector3(0.0, 0.062, -0.03), Vector3(0.05, 0.004, 0.05), _mats["lcd"])
		var ml := _label(_dyn, "METER", at + Vector3(0.0, 0.066, 0.03), 0.0, 0.0006, Color(0.9, 0.9, 0.9))
		ml.rotation.x = -PI * 0.5


func _draw_bench_top() -> void:
	var b := PaintBay.BENCH
	var top := PaintBay.BENCH_TOP
	var cx := b.position.x + b.size.x * 0.5
	var cz := b.position.y + b.size.y * 0.5
	var stainless := PaintBay.kit("stainless")
	_box(_dyn, Vector3(cx, top - 0.025, cz), Vector3(b.size.x + 0.04, 0.05, b.size.y + 0.04), _mats["steel"] if stainless else _mats["bench"])
	_box(_dyn, Vector3(cx + 0.02, (top - 0.05) * 0.5, cz), Vector3(b.size.x - 0.04, top - 0.05, b.size.y - 0.04),
		_mats["steel"] if stainless else _mats["cabinet"])
	if stainless:
		# The under-bench tin racks: the bases in stock on the shelf under the worktop.
		var i := 0
		for base in PaintMix.BASE_ORDER:
			var n := mini(int(floor(PaintBay.stock_of(base))), 4)
			for k in n:
				var tin := tin_model({"base": base, "base_g": 1000.0, "tints": {}, "stir": 1.0, "mix": {"color": PaintMix.BASES[base]["color"]}})
				tin.position = Vector3(b.position.x - 0.03, 0.12, b.position.y + 0.25 + i * 0.75 + k * 0.13)
				_dyn.add_child(tin)
			i += 1
		_box(_dyn, Vector3(b.position.x - 0.02, 0.1, cz), Vector3(0.18, 0.02, b.size.y - 0.1), _mats["steel"])


func _draw_rack() -> void:
	for code in PaintBay.rack():
		var bottle := bottle_model(str(code))
		bottle.transform = PaintBay.bottle_xf(str(code))
		bottle.visible = PaintBay.stock_of(str(code)) > 0.5
		bottle.name = "Bottle_" + str(code)
		_dyn.add_child(bottle)
	if PaintBay.kit("effects"):
		_label(_dyn, "EFFECTS", Vector3(PaintBay.RACK_X - 0.112, float(PaintBay.RACK_Y[0]) - 0.05, PaintBay.RACK_Z0 + 10.5 * PaintBay.RACK_STEP), -PI * 0.5, 0.0012)


func _draw_shelf() -> void:
	for id in PaintBay.tins():
		var t: Dictionary = PaintBay.tins()[id]
		if str(t.get("at", "")) != "shelf":
			continue
		var tin := tin_model(t)
		tin.transform = PaintBay.slot_xf(int(t.get("ref", 0)))
		tin.rotation.y = -PI * 0.5
		_dyn.add_child(tin)


func _draw_swatches() -> void:
	var order := PaintBay.swatch_order()
	for i in order.size():
		var r: Dictionary = PaintBay.recipes()[order[i]]
		var holder := Node3D.new()
		holder.transform = PaintBay.swatch_xf(i)
		_dyn.add_child(holder)
		var card := _card(holder, r.get("mix", {}), Vector2(0.6, 0.28))
		card.position = Vector3(0.0, 0.04, 0.0)
		_label(holder, str(r.get("name", "")).left(22), Vector3(0.0, -0.15, 0.002), 0.0, 0.0009)
		_label(holder, str(r.get("code", "")).left(34), Vector3(0.0, -0.185, 0.002), 0.0, 0.0006, Color(0.3, 0.3, 0.32))
		_target(holder, Vector3(0.0, 0.0, 0.03), Vector3(0.66, 0.42, 0.06), {"paint_bay": "swatch", "recipe": int(order[i])})


func _draw_test_card() -> void:
	var test: Dictionary = PaintBay._st()["test"]
	if not (test.get("mix") is Dictionary):
		return
	var s: Dictionary = test["mix"]
	var stand := Node3D.new()
	stand.position = PaintBay.STAND_AT + Vector3(0.0, 1.38, 0.0)
	# Facing the room (+z), away from the booth.
	_dyn.add_child(stand)
	_card(stand, s, Vector2(0.3, 0.42), PaintBay.kit("curved"))
	_label(stand, str(test.get("name", "")) if str(test.get("name", "")) != "" else "Test card", Vector3(0.0, -0.26, 0.002), 0.0, 0.0009)
	# And one in each of the booth's three bays.
	var b := PaintBay.BOOTH
	var w := b.size.x / 3.0
	for i in 3:
		var holder := Node3D.new()
		holder.position = Vector3(b.position.x + (i + 0.5) * w, (PaintBay.BOOTH_Y.x + PaintBay.BOOTH_Y.y) * 0.5, b.position.y + 0.05)
		_dyn.add_child(holder)
		_card(holder, s, Vector2(0.22, 0.32), PaintBay.kit("curved"))


func _draw_shaker_body() -> void:
	for c in _shaker_body.get_children():
		c.queue_free()
	var auto := PaintBay.kit("shaker")
	var housing := _mat(Color(0.75, 0.2, 0.15) if auto else Color(0.35, 0.36, 0.38), 0.3, 0.5)
	_box(_shaker_body, Vector3(0.0, 0.03, 0.0), Vector3(0.34, 0.06, 0.34), housing)
	for side in [-1.0, 1.0]:
		_box(_shaker_body, Vector3(0.0, 0.18, side * 0.15), Vector3(0.3, 0.3, 0.03), housing)
	_box(_shaker_body, Vector3(0.0, 0.34, 0.0), Vector3(0.34, 0.04, 0.34), housing)
	_box(_shaker_body, Vector3(0.0, 0.065, 0.0), Vector3(0.12, 0.01, 0.12), _mats["steel"])
	_label(_shaker_body, "AUTO SHAKER" if auto else "SHAKER", Vector3(-0.172, 0.3, 0.0), -PI * 0.5, 0.0008, Color(0.95, 0.95, 0.95))


# ---------------------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	_t += delta
	if Shed.room_lit("paint") != _lit_shown:
		_set_lit(Shed.room_lit("paint"))
	_update_door(delta)
	if not Shed.active:
		return
	_update_bench(delta)
	_update_shaker()


func _update_door(delta: float) -> void:
	var near := false
	var at := Vector3(PaintBay.WALL_X, 0.0, PaintBay.DOOR_Z)
	if is_inside_tree():
		for group in ["local_walker", "remote_players"]:
			for n in get_tree().get_nodes_in_group(group):
				if n is Node3D:
					var p := (n as Node3D).global_position
					if Vector2(p.x - at.x, p.z - at.z).length() < GLASS_REACH and absf(p.y) < 2.0:
						near = true
	_door_open = move_toward(_door_open, 1.0 if near else 0.0, delta / 0.6)
	_door_leaf.position.z = PaintBay.DOOR_Z - smoothstep(0.0, 1.0, _door_open) * (PaintBay.DOOR_HALF * 2.0 + 0.05)


## The tin on the scale (with the paint showing), the scale's reading, the bottle tipped over
## it and the stirring stick.
func _update_bench(delta: float) -> void:
	var tin := PaintBay.bench_tin()
	var me_at := PaintBay.at_bench() == Shed.me()
	var extra := float(live.get("g", 0.0)) if me_at else 0.0
	var show_tin := tin.duplicate(true)
	if me_at and extra > 0.0 and not tin.is_empty() and str(live.get("code", "")) != "":
		var code := str(live["code"])
		show_tin["tints"][code] = float(show_tin["tints"].get(code, 0.0)) + extra
	var sig := "" if tin.is_empty() else PaintMix.full_code(show_tin) + str(snappedf(float(tin.get("stir", 1.0)), 0.05))
	if sig != _bench_tin_sig:
		_bench_tin_sig = sig
		if _bench_tin:
			_bench_tin.queue_free()
			_bench_tin = null
		if not tin.is_empty():
			var t2 := show_tin.duplicate()
			t2.erase("mix")
			t2.erase("name")
			_bench_tin = tin_model(t2, true)
			_bench_tin.position = PaintBay.SCALE_AT + Vector3(0.0, 0.046, 0.0)
			add_child(_bench_tin)
	# The reading: to the scale's step for whoever's at the bench.
	var by := PaintBay.at_bench()
	var step := PaintMix.scale_step(PaintBay.level_of(by) if by != 0 else 1, PaintBay.kit("scale"))
	_scale_label.text = "- - -" if tin.is_empty() else PaintMix.read_scale(PaintMix.total_grams(show_tin), step)
	# The bottle: what the local player is pouring, or what the host last heard poured.
	var code := ""
	var tilt := 0.0
	if me_at and str(live.get("code", "")) != "" and float(live.get("tilt", 0.0)) > 0.02:
		code = str(live["code"])
		tilt = float(live["tilt"])
	elif not me_at and by != 0:
		var b := PaintBay.bench()
		var psig := "%s|%.2f|%s" % [str(b.get("tint", "")), float(b.get("tilt", 0.0)), sig]
		if psig != str(_pour_seen["sig"]):
			_pour_seen = {"sig": psig, "t": _t}
		if _t - float(_pour_seen["t"]) < 0.5:
			code = str(b.get("tint", ""))
			tilt = float(b.get("tilt", 0.0))
	if tin.is_empty():
		code = ""
	if code != _pour_code:
		_pour_code = code
		if _pour_bottle:
			_pour_bottle.queue_free()
			_pour_bottle = null
		if _stream:
			_stream.queue_free()
			_stream = null
		if code != "":
			_pour_bottle = Node3D.new()
			add_child(_pour_bottle)
			var bottle := bottle_model(code)
			bottle.position = Vector3(0.0, -0.14, 0.0)   # pivot at the neck
			_pour_bottle.add_child(bottle)
			var sm := StandardMaterial3D.new()
			sm.albedo_color = PaintMix.TINTS[code]["color"]
			sm.roughness = 0.2
			_stream = _cylinder(0.0025, 1.0, sm, 6)
			add_child(_stream)
	if _pour_bottle:
		# The neck over the tin's rim; tipped towards it (towards -x, the bench edge) as it pours.
		var neck := PaintBay.SCALE_AT + Vector3(0.0, 0.3, 0.0)
		_pour_bottle.position = neck
		_pour_bottle.rotation = Vector3(0.0, 0.0, lerpf(0.7, 2.8, tilt))
		var flowing := PaintMix.pour_rate(tilt) > 0.0
		_stream.visible = flowing
		if flowing:
			var top := neck
			var bottom := PaintBay.SCALE_AT + Vector3(0.0, 0.165, 0.0)
			_stream.position = (top + bottom) * 0.5
			_stream.scale = Vector3(1.0 + tilt * 1.5, top.y - bottom.y, 1.0 + tilt * 1.5)
	# The stirring stick: turning while someone stirs.
	var stirring: bool = me_at and bool(live.get("stirring", false))
	if not me_at and not tin.is_empty():
		var sa := float(PaintBay.bench().get("stir_at", 0.0))
		if sa != float(_stir_seen["v"]):
			_stir_seen = {"v": sa, "t": _t}
		stirring = _t - float(_stir_seen["t"]) < 0.4
	if stirring and not tin.is_empty():
		if _stick == null:
			_stick = Node3D.new()
			add_child(_stick)
			var stick := _box(_stick, Vector3(0.0, 0.1, 0.0), Vector3(0.012, 0.26, 0.022), _mats["wood"])
			stick.rotation.z = 0.25
		_stir_angle += delta * 9.0
		_stick.position = PaintBay.SCALE_AT + Vector3(cos(_stir_angle) * 0.025, 0.08, sin(_stir_angle) * 0.025)
		_stick.rotation.y = _stir_angle
	elif _stick:
		_stick.queue_free()
		_stick = null


func _update_shaker() -> void:
	var sh: Dictionary = PaintBay._st()["shaker"]
	var id := int(sh.get("tin", 0))
	var sig := str(id)
	if sig != _shaker_sig:
		_shaker_sig = sig
		if _shaker_tin:
			_shaker_tin.queue_free()
			_shaker_tin = null
		var t: Dictionary = PaintBay.tins().get(id, {})
		if not t.is_empty():
			_shaker_tin = tin_model(t)
			add_child(_shaker_tin)
	if _shaker_tin:
		var j := Vector3(sin(_t * 61.0), 0.0, cos(_t * 47.0)) * 0.006
		_shaker_tin.position = PaintBay.SHAKER_AT + Vector3(0.0, 0.07, 0.0) + j
		_shaker_body.position = PaintBay.SHAKER_AT + j * 0.3
	else:
		_shaker_body.position = PaintBay.SHAKER_AT
