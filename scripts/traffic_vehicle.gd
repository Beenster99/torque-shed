class_name TrafficVehicle
extends RefCounted
## The cars and lorries on the riding map's roads (see RoadTraffic), drawn in the same chunky
## low-poly style as the rest of the game: a handful of painted boxes, dark glass, four or
## six wheels with a pale hub so you can see them turn, and head and tail lamps. Everything is
## built from shared meshes and materials, so a car costs a few draw calls and no memory of
## its own, and the lamps of every vehicle share two materials that follow the time of day.
##
## A vehicle's look comes from a seed (see look), so every machine in the crew draws the same
## one. Vehicles face -Z, like the bikes, with their wheels on the ground at y = 0.

const CAR_MODELS: Array[String] = ["hatchback", "saloon", "estate", "van", "pickup"]
const TRUCK_MODELS: Array[String] = ["box_lorry", "flatbed", "tipper"]
const CAR_PAINTS: Array[Color] = [
	Color(0.62, 0.07, 0.07), Color(0.1, 0.2, 0.45), Color(0.82, 0.82, 0.8), Color(0.08, 0.08, 0.09),
	Color(0.55, 0.57, 0.6), Color(0.12, 0.32, 0.2), Color(0.85, 0.7, 0.12), Color(0.35, 0.2, 0.12),
	Color(0.7, 0.35, 0.1), Color(0.3, 0.55, 0.7),
]
const TRUCK_PAINTS: Array[Color] = [
	Color(0.9, 0.9, 0.88), Color(0.8, 0.62, 0.08), Color(0.12, 0.25, 0.5), Color(0.65, 0.1, 0.08),
	Color(0.15, 0.4, 0.22), Color(0.85, 0.4, 0.08),
]
## How bright the lamps burn at full strength.
const LAMP_ENERGY := 3.0

static var _meshes := {}
static var _mats := {}
static var _lamp_mats := {}
static var _lamp_level := 0.0


## The look of a car or truck ("car" or "truck") from its seed: {kind, model, paint, trim}.
static func look(kind: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var models := TRUCK_MODELS if kind == "truck" else CAR_MODELS
	var paints := TRUCK_PAINTS if kind == "truck" else CAR_PAINTS
	var model: String = models[rng.randi() % models.size()]
	var paint: Color = paints[rng.randi() % paints.size()]
	# A second colour for what a lorry carries on its back.
	var trim: Color = TRUCK_PAINTS[rng.randi() % TRUCK_PAINTS.size()] if kind == "truck" else paint
	return {"kind": kind, "model": model, "paint": paint, "trim": trim}


## Builds a vehicle from a look: {root, wheels (their pivots, to spin about X), radius, size
## (width, height, length)}.
static func build(lk: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var wheels: Array[Node3D] = []
	var paint: Color = lk["paint"]
	var size := Vector3.ZERO
	var radius := 0.31
	match str(lk["model"]):
		"hatchback":
			size = _car(root, paint, 3.9, 2.0, 0.35, 0.5)
		"saloon":
			size = _car(root, paint, 4.5, 1.9, 0.2, 0.48)
		"estate":
			size = _car(root, paint, 4.6, 2.9, 0.5, 0.52)
		"van":
			size = _van(root, paint)
		"pickup":
			size = _pickup(root, paint)
		"box_lorry", "flatbed", "tipper":
			radius = 0.5
			size = _lorry(root, str(lk["model"]), paint, lk["trim"])
	var w := size.x
	var length := size.z
	var axles: Array[float] = [-length * 0.5 + (1.0 if radius < 0.4 else 1.3), length * 0.5 - (0.9 if radius < 0.4 else 1.3)]
	if str(lk["model"]) in ["flatbed", "tipper"]:
		axles.append(length * 0.5 - 2.5)
	var tyre_w := 0.22 if radius < 0.4 else 0.3
	for z in axles:
		for side in [-1.0, 1.0]:
			wheels.append(_wheel(root, Vector3(side * (w * 0.5 - tyre_w * 0.5 - 0.02), radius, z), radius, tyre_w))
	return {"root": root, "wheels": wheels, "radius": radius, "size": size}


## Sets how brightly every vehicle's lamps burn, 0 (off) to 1; they're steady at a level so
## this does nothing when it hasn't changed.
static func set_lamps(level: float) -> void:
	var q := roundf(clampf(level, 0.0, 1.0) * 10.0) / 10.0
	if is_equal_approx(q, _lamp_level):
		return
	_lamp_level = q
	for k in _lamp_mats:
		_apply_lamp(_lamp_mats[k], k)


static func _apply_lamp(m: StandardMaterial3D, which: String) -> void:
	var c := Color(1.0, 0.93, 0.75) if which == "head" else Color(0.95, 0.06, 0.04)
	m.emission_enabled = _lamp_level > 0.01
	m.emission = c
	m.emission_energy_multiplier = LAMP_ENERGY * _lamp_level * (1.0 if which == "head" else 0.5)
	m.albedo_color = c.darkened(0.55 * (1.0 - _lamp_level))


# ---------------------------------------------------------------------------- the models

## A saloon, hatchback or estate: a low body with a glass cabin and a roof on it, `cab` long
## and `cab_z` back of the middle, `cab_h` tall. Returns (width, height, length).
static func _car(root: Node3D, paint: Color, length: float, cab: float, cab_z: float, cab_h: float) -> Vector3:
	var w := 1.74
	var ground := 0.22
	var body := _mat(paint, 0.35, 0.3)
	_box(root, Vector3(0.0, ground + 0.29, 0.0), Vector3(w, 0.58, length), body)
	_box(root, Vector3(0.0, ground + 0.58 + cab_h * 0.5, cab_z), Vector3(w - 0.12, cab_h, cab), _mat(Color(0.06, 0.09, 0.12), 0.1, 0.5))
	_box(root, Vector3(0.0, ground + 0.58 + cab_h + 0.03, cab_z), Vector3(w - 0.14, 0.06, cab - 0.12), body)
	_bumpers(root, w, length, ground + 0.12)
	_lamps(root, w, length, ground + 0.42)
	return Vector3(w, ground + 0.58 + cab_h + 0.06, length)


## A panel van: a short bonnet and a tall box behind it.
static func _van(root: Node3D, paint: Color) -> Vector3:
	var w := 1.85
	var length := 4.7
	var ground := 0.25
	var body := _mat(paint, 0.4, 0.2)
	_box(root, Vector3(0.0, ground + 0.34, -length * 0.5 + 0.7), Vector3(w, 0.68, 1.4), body)
	_box(root, Vector3(0.0, ground + 0.8, 0.65), Vector3(w, 1.6, length - 1.3), body)
	_box(root, Vector3(0.0, ground + 1.2, -length * 0.5 + 1.42), Vector3(w - 0.14, 0.5, 0.06), _mat(Color(0.06, 0.09, 0.12), 0.1, 0.5))
	_bumpers(root, w, length, ground + 0.12)
	_lamps(root, w, length, ground + 0.45)
	return Vector3(w, ground + 1.6, length)


## A pickup: a cab at the front and an open bed behind.
static func _pickup(root: Node3D, paint: Color) -> Vector3:
	var w := 1.85
	var length := 5.2
	var ground := 0.28
	var body := _mat(paint, 0.4, 0.2)
	_box(root, Vector3(0.0, ground + 0.3, -0.6), Vector3(w, 0.6, length - 1.2), body)
	_box(root, Vector3(0.0, ground + 0.86, -0.4), Vector3(w - 0.12, 0.52, 1.7), _mat(Color(0.06, 0.09, 0.12), 0.1, 0.5))
	_box(root, Vector3(0.0, ground + 1.14, -0.4), Vector3(w - 0.14, 0.06, 1.55), body)
	# The bed: a floor, two sides and a tailgate.
	var bed_z := length * 0.5 - 1.1
	_box(root, Vector3(0.0, ground + 0.4, bed_z), Vector3(w, 0.16, 2.2), body)
	for x in [-1.0, 1.0]:
		_box(root, Vector3(x * (w * 0.5 - 0.04), ground + 0.62, bed_z), Vector3(0.08, 0.36, 2.2), body)
	_box(root, Vector3(0.0, ground + 0.62, length * 0.5 - 0.04), Vector3(w, 0.36, 0.08), body)
	_bumpers(root, w, length, ground + 0.12)
	_lamps(root, w, length, ground + 0.45)
	return Vector3(w, ground + 1.17, length)


## A lorry: a cab, a chassis and a box, flat deck or tipper body behind it.
static func _lorry(root: Node3D, model: String, paint: Color, trim: Color) -> Vector3:
	var w := 2.4
	var length := 7.8 if model == "box_lorry" else 7.2
	var cab_len := 1.9
	var floor_y := 1.0
	var chassis := _mat(Color(0.12, 0.12, 0.13), 0.7, 0.2)
	var cab := _mat(paint, 0.4, 0.2)
	_box(root, Vector3(0.0, 0.8, 0.0), Vector3(1.9, 0.3, length), chassis)
	_box(root, Vector3(0.0, 1.9, -length * 0.5 + cab_len * 0.5), Vector3(w, 2.1, cab_len), cab)
	_box(root, Vector3(0.0, 2.35, -length * 0.5 - 0.02), Vector3(w - 0.2, 0.8, 0.06), _mat(Color(0.06, 0.09, 0.12), 0.1, 0.5))
	var back_len := length - cab_len - 0.15
	var back_z := length * 0.5 - back_len * 0.5
	var top := 3.0
	match model:
		"box_lorry":
			top = floor_y + 2.7
			_box(root, Vector3(0.0, floor_y + 1.35, back_z), Vector3(w + 0.05, 2.7, back_len), _mat(trim, 0.5, 0.1))
		"flatbed":
			top = 2.2
			_box(root, Vector3(0.0, floor_y + 0.09, back_z), Vector3(w + 0.05, 0.18, back_len), _mat(Color(0.35, 0.28, 0.2), 0.8, 0.0))
			var crate := _mat(Color(0.5, 0.36, 0.2), 0.85, 0.0)
			_box(root, Vector3(-0.5, floor_y + 0.55, back_z - 1.2), Vector3(1.0, 0.8, 1.1), crate)
			_box(root, Vector3(0.55, floor_y + 0.45, back_z + 0.3), Vector3(1.0, 0.6, 1.4), crate)
			_box(root, Vector3(-0.4, floor_y + 0.4, back_z + 1.7), Vector3(1.1, 0.5, 0.9), crate)
		"tipper":
			top = floor_y + 1.4
			var tip := _mat(trim, 0.6, 0.2)
			_box(root, Vector3(0.0, floor_y + 0.1, back_z), Vector3(w, 0.2, back_len), tip)
			for x in [-1.0, 1.0]:
				_box(root, Vector3(x * (w * 0.5 - 0.06), floor_y + 0.75, back_z), Vector3(0.12, 1.1, back_len), tip)
			_box(root, Vector3(0.0, floor_y + 0.85, back_z - back_len * 0.5 + 0.06), Vector3(w, 1.3, 0.12), tip)
			_box(root, Vector3(0.0, floor_y + 0.65, length * 0.5 - 0.1), Vector3(w, 0.9, 0.1), tip)
	_bumpers(root, w, length, 0.55)
	_lamps(root, w, length, 0.95)
	return Vector3(w + 0.05, top, length)


## Front and rear bumpers in dark trim.
static func _bumpers(root: Node3D, w: float, length: float, y: float) -> void:
	var trim := _mat(Color(0.1, 0.1, 0.11), 0.7, 0.1)
	for z in [-1.0, 1.0]:
		_box(root, Vector3(0.0, y, z * (length * 0.5 + 0.02)), Vector3(w - 0.05, 0.16, 0.08), trim)


## A pair of headlamps on the nose and tail lights on the back, lit by set_lamps.
static func _lamps(root: Node3D, w: float, length: float, y: float) -> void:
	for x in [-1.0, 1.0]:
		var head := _box(root, Vector3(x * (w * 0.5 - 0.3), y, -length * 0.5 - 0.02), Vector3(0.3, 0.13, 0.05), _lamp("head"))
		var tail := _box(root, Vector3(x * (w * 0.5 - 0.22), y, length * 0.5 + 0.02), Vector3(0.24, 0.12, 0.05), _lamp("tail"))
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A wheel on a pivot that spins about X: a dark tyre and a pale bar across the hub.
static func _wheel(root: Node3D, at: Vector3, r: float, width: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	root.add_child(pivot)
	var tyre := MeshInstance3D.new()
	var key := "tyre%.2f/%.2f" % [r, width]
	if not _meshes.has(key):
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = width
		cyl.radial_segments = 10
		cyl.rings = 1
		_meshes[key] = cyl
	tyre.mesh = _meshes[key]
	tyre.material_override = _mat(Color(0.05, 0.05, 0.055), 0.9, 0.0)
	tyre.rotation.z = PI * 0.5
	pivot.add_child(tyre)
	_box(pivot, Vector3.ZERO, Vector3(width + 0.03, r * 1.1, r * 0.3), _mat(Color(0.65, 0.66, 0.68), 0.4, 0.6))
	return pivot


static func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var key := "box%.3f/%.3f/%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func _lamp(which: String) -> StandardMaterial3D:
	if not _lamp_mats.has(which):
		var m := StandardMaterial3D.new()
		m.roughness = 0.3
		_apply_lamp(m, which)
		_lamp_mats[which] = m
	return _lamp_mats[which]
