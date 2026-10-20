class_name FuelPump
extends Node3D
## A petrol pump: a tall cabinet with a lit price display, a hose and nozzle on its side. Any
## node in the "fuel_pump" group is a place to fill up (see FuelStop): ride up beside it, stop
## and hold {interact}. The adventure world's fuel stations use the same group; a pump may say
## its own price (price_per_litre), else it's the town's (Shed.PUMP_PRICE).
##
## build_forecourt puts the town's filling station on the High Street, east of the shed: a
## concrete forecourt off the road under a lit canopy, an island with two pumps, a kiosk and a
## price board by the kerb.

const GROUP := "fuel_pump"
## Where the town's forecourt is: its middle (x, z) and its size along and back from the street.
const TOWN_AT := Vector2(124.0, 78.0)
const TOWN_SIZE := Vector2(26.0, 18.0)
## How close (m) a bike has to be to a pump's middle to fill up from it.
const REACH := 4.0

## Pounds a litre at this pump (0: the town's price, Shed.PUMP_PRICE).
@export var price := 0.0
var brand := Color(0.05, 0.45, 0.2)


func _ready() -> void:
	add_to_group(GROUP)


## Pounds a litre.
func price_per_litre() -> float:
	return price if price > 0.0 else Shed.PUMP_PRICE


## Builds the pump's cabinet, display, hoses and nozzles (it stands on its own base, facing +Z
## and -Z, a nozzle each side).
func build_model() -> void:
	var body := _mat(Color(0.9, 0.9, 0.88), 0.1, 0.45)
	var band := _mat(brand, 0.1, 0.4)
	var dark := _mat(Color(0.05, 0.05, 0.055), 0.2, 0.5)
	var steel := _mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	_box(Vector3(0.0, 0.08, 0.0), Vector3(1.1, 0.16, 0.7), _mat(Color(0.55, 0.55, 0.53), 0.0, 0.9))
	_box(Vector3(0.0, 0.95, 0.0), Vector3(0.9, 1.6, 0.5), body)
	_box(Vector3(0.0, 1.85, 0.0), Vector3(0.92, 0.25, 0.52), band)
	_box(Vector3(0.0, 0.4, 0.0), Vector3(0.92, 0.08, 0.52), band)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.1, 0.12, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 1.0, 0.6)
	glow.emission_energy_multiplier = 1.2
	for side in [-1.0, 1.0]:
		# The display each side, with its price window, and a nozzle in its holster.
		_box(Vector3(0.0, 1.35, side * 0.255), Vector3(0.6, 0.32, 0.01), dark)
		_box(Vector3(0.0, 1.4, side * 0.262), Vector3(0.5, 0.1, 0.006), glow)
		_box(Vector3(0.0, 1.26, side * 0.262), Vector3(0.3, 0.06, 0.006), glow)
		var holster := Vector3(0.38 * side, 0.95, 0.0)
		_box(holster, Vector3(0.12, 0.2, 0.14), dark)
		var nozzle := _box(holster + Vector3(0.04 * side, 0.08, 0.0), Vector3(0.05, 0.05, 0.22), band)
		nozzle.rotation.x = 0.4
		# The hose looping down from the top of the cabinet to the nozzle.
		var pts := [Vector3(0.42 * side, 1.7, 0.0), Vector3(0.62 * side, 1.2, 0.05), Vector3(0.6 * side, 0.55, 0.1), Vector3(0.45 * side, 0.85, 0.05)]
		for i in pts.size() - 1:
			_tube(pts[i], pts[i + 1], 0.02, dark)
	_box(Vector3(0.0, 2.02, 0.0), Vector3(0.7, 0.1, 0.3), steel)


func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


func _tube(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	mi.transform = Transform3D(Basis(axis.normalized(), Vector3.UP.angle_to(dir)) if axis.length() > 0.001 else Basis(), (a + b) * 0.5)


## The town's filling station (see the top), built into `world`. Returns its pumps.
static func build_forecourt(world: World) -> Array:
	var root := Node3D.new()
	root.name = "FillingStation"
	world.add_child(root)
	var c := TOWN_AT
	var y := world.terrain_height(c.x, c.y) + 0.02
	root.position = Vector3(c.x, y, c.y)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.62, 0.62, 0.6)
	concrete.roughness = 0.85
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	white.roughness = 0.5
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.05, 0.45, 0.2)
	green.roughness = 0.4
	var canopy_glow := StandardMaterial3D.new()
	canopy_glow.albedo_color = Color(0.95, 0.95, 0.9)
	canopy_glow.emission_enabled = true
	canopy_glow.emission = Color(1.0, 0.97, 0.9)
	canopy_glow.emission_energy_multiplier = 0.8
	var parts := Node3D.new()
	root.add_child(parts)
	# The forecourt slab, flush with the road at the front (a dropped kerb), and its collision.
	var body := StaticBody3D.new()
	body.name = "ForecourtGround"
	body.set_meta("surface", "tarmac")
	root.add_child(body)
	_slab(parts, body, Vector3(0.0, -0.06, 0.0), Vector3(TOWN_SIZE.x, 0.12, TOWN_SIZE.y), concrete)
	# The pump island: a raised kerb with two pumps on it, along the street.
	_slab(parts, body, Vector3(0.0, 0.07, 0.0), Vector3(6.0, 0.14, 1.4), white)
	# The canopy over it on four posts, lit underneath.
	for x in [-4.5, 4.5]:
		for z in [-0.3, 0.3]:
			_post(parts, body, Vector3(x, 0.0, z), 0.12, 4.6, white)
	_box_mi(parts, Vector3(0.0, 4.75, 0.0), Vector3(12.0, 0.5, 7.0), white)
	_box_mi(parts, Vector3(0.0, 4.75, 3.51), Vector3(12.0, 0.36, 0.02), green)
	_box_mi(parts, Vector3(0.0, 4.75, -3.51), Vector3(12.0, 0.36, 0.02), green)
	_box_mi(parts, Vector3(0.0, 4.49, 0.0), Vector3(11.0, 0.02, 6.0), canopy_glow)
	# The kiosk at the back, its window lit, with the name over the door.
	_slab(parts, body, Vector3(0.0, 1.5, -TOWN_SIZE.y * 0.5 + 2.2), Vector3(8.0, 3.0, 4.0), white)
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(0.3, 0.4, 0.45)
	window.emission_enabled = true
	window.emission = Color(1.0, 0.92, 0.75)
	window.emission_energy_multiplier = 0.5
	_box_mi(parts, Vector3(0.0, 1.4, -TOWN_SIZE.y * 0.5 + 4.21), Vector3(5.0, 1.6, 0.02), window)
	_box_mi(parts, Vector3(0.0, 2.75, -TOWN_SIZE.y * 0.5 + 4.22), Vector3(6.0, 0.4, 0.02), green)
	var name_label := Label3D.new()
	name_label.text = "HIGH STREET FUEL"
	name_label.font_size = 64
	name_label.pixel_size = 0.006
	name_label.modulate = Color(0.95, 0.95, 0.9)
	name_label.position = Vector3(0.0, 2.75, -TOWN_SIZE.y * 0.5 + 4.24)
	parts.add_child(name_label)
	# A price board on a pole by the kerb.
	var board := Vector3(TOWN_SIZE.x * 0.5 - 1.5, 0.0, TOWN_SIZE.y * 0.5 - 1.2)
	_post(parts, body, board, 0.08, 3.0, white)
	_box_mi(parts, board + Vector3(0.0, 3.4, 0.0), Vector3(1.6, 1.1, 0.2), green)
	var price_label := Label3D.new()
	price_label.text = "UNLEADED\n%dp" % roundi(Shed.PUMP_PRICE * 100.0)
	price_label.font_size = 48
	price_label.pixel_size = 0.006
	price_label.modulate = Color(1.0, 0.95, 0.6)
	price_label.position = board + Vector3(0.0, 3.4, 0.11)
	parts.add_child(price_label)
	var back_label := price_label.duplicate() as Label3D
	back_label.position = board + Vector3(0.0, 3.4, -0.11)
	back_label.rotation.y = PI
	parts.add_child(back_label)
	var pumps := []
	for x in [-1.6, 1.6]:
		var pump := FuelPump.new()
		pump.name = "Pump"
		pump.position = Vector3(x, 0.14, 0.0)
		root.add_child(pump)
		pump.build_model()
		pumps.append(pump)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.9, 2.0, 0.5)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(x, 1.14, 0.0)
		body.add_child(cs)
	for child in parts.get_children():
		if child is GeometryInstance3D:
			world.ranged(child, 400.0)
	return pumps


static func _slab(parent: Node3D, body: StaticBody3D, at: Vector3, size: Vector3, mat: Material) -> void:
	_box_mi(parent, at, size, mat)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)


static func _post(parent: Node3D, body: StaticBody3D, at: Vector3, r: float, h: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at + Vector3.UP * h * 0.5
	parent.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = mi.position
	body.add_child(cs)


static func _box_mi(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi
