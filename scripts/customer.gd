class_name CustomerView
extends Node3D
## A customer: a simple low-poly person (the same primitive style as the crew) who walks in
## from the car park to the sales office reception, rings the bell, and waits to be talked to
## (F). When they go, they walk back out the way they came. Drawn from Shed.contracts by
## ContractsView; nothing here is shared state.

signal arrived(view: CustomerView)

var customer_id := 0
var customer_name := ""
var path := PackedVector3Array()
var leaving := false
var at_counter := false
var _leg := 0
var _figure: StaticBody3D
var _label: Label3D
var _legs: Array[Node3D] = []
var _walk_phase := 0.0
var _face := Basis()


## Builds the figure for customer `data` and starts it walking along `walk` (or standing at
## the end of it already, when `already_there`).
func setup(data: Dictionary, walk: PackedVector3Array, face: Basis, already_there := false) -> void:
	customer_id = int(data.get("id", 0))
	customer_name = str(data.get("name", "Customer"))
	name = "Customer%d" % customer_id
	path = walk
	_face = face
	add_to_group("sales_visitor")
	add_to_group("customers")
	var look: Dictionary = data.get("look", {})
	var top: Color = look.get("top", Color(0.2, 0.3, 0.6))
	var legs: Color = look.get("legs", Color(0.15, 0.15, 0.2))
	var skin: Color = look.get("skin", Color(0.85, 0.66, 0.52))
	var hair: Color = look.get("hair", Color(0.2, 0.12, 0.06))
	var tall: float = float(look.get("tall", 1.0))
	_figure = StaticBody3D.new()
	_figure.collision_layer = Workshop.INTERACT_LAYER
	_figure.collision_mask = 0
	_figure.set_meta("customer", customer_id)
	_figure.scale = Vector3.ONE * tall
	add_child(_figure)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	_figure.add_child(cs)
	var shirt := _mat(top)
	var trousers := _mat(legs)
	var shoes := _mat(Color(0.1, 0.08, 0.07))
	_part(_figure, CapsuleMesh.new(), Vector3(0.0, 1.15, 0.0), Vector3(0.6, 0.6, 0.42), shirt)
	for side in [-1.0, 1.0]:
		# Arms hang at the sides; legs swing as they walk.
		_part(_figure, CapsuleMesh.new(), Vector3(0.34 * side, 1.12, 0.0), Vector3(0.14, 0.55, 0.14), shirt)
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, 0.85, 0.0)
		_figure.add_child(hip)
		_part(hip, CapsuleMesh.new(), Vector3(0.0, -0.4, 0.0), Vector3(0.22, 0.85, 0.22), trousers)
		_part(hip, BoxMesh.new(), Vector3(0.0, -0.8, -0.05), Vector3(0.13, 0.1, 0.26), shoes)
		_legs.append(hip)
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.62, 0.0)
	_figure.add_child(head)
	_part(head, SphereMesh.new(), Vector3.ZERO, Vector3(0.24, 0.27, 0.25), _mat(skin))
	_part(head, SphereMesh.new(), Vector3(0.0, 0.06, 0.03), Vector3(0.26, 0.18, 0.26), _mat(hair))
	if look.get("hat", false):
		_part(head, CylinderMesh.new(), Vector3(0.0, 0.15, 0.0), Vector3(0.3, 0.1, 0.3), _mat(legs.darkened(0.2)))
	if look.get("vip", false):
		# The exclusive customer: a dark suit with a gold tie.
		_part(_figure, BoxMesh.new(), Vector3(0.0, 1.2, -0.215), Vector3(0.06, 0.3, 0.01), _mat(Color(0.9, 0.7, 0.2)))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.font_size = 44
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	_label.modulate = Color(1.0, 0.85, 0.5)
	_figure.add_child(_label)
	set_hint(false)
	if already_there or path.size() < 2:
		position = path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
		_leg = path.size()
		_stand()
	else:
		position = path[0]
		_leg = 1


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, size: Vector3, mat: Material) -> void:
	if mesh is CapsuleMesh:
		mesh.radius = 0.5
		mesh.height = 2.0
		size.y *= 0.5
	elif mesh is SphereMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	elif mesh is CylinderMesh:
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)


## Shows "F: talk" under the name while someone looks at them.
func set_hint(on: bool) -> void:
	if _label == null:
		return
	var key := Settings.binding_text("interact", false)
	_label.text = customer_name + ("\n%s: talk" % (key if key != "" else "F") if on and at_counter and not leaving else "")


## Walks to a new place in the queue.
func move_to(spot: Vector3) -> void:
	if leaving or path.is_empty():
		return
	if path[path.size() - 1].distance_to(spot) < 0.05:
		return
	path[path.size() - 1] = spot
	if at_counter:
		at_counter = false
		_leg = path.size() - 1
		path[_leg - 1] = position


## Turns round and walks back out, then is gone.
func leave() -> void:
	if leaving:
		return
	leaving = true
	at_counter = false
	set_hint(false)
	var back := PackedVector3Array([position])
	for i in range(path.size() - 2, -1, -1):
		back.append(path[i])
	path = back
	_leg = 1


func _stand() -> void:
	at_counter = true
	basis = _face
	for leg in _legs:
		leg.rotation.x = 0.0


func _process(delta: float) -> void:
	if _leg >= path.size():
		if leaving:
			queue_free()
		return
	var target := path[_leg]
	var to := target - position
	to.y = 0.0
	var step := CustomerView.walk_speed() * delta
	if to.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		_leg += 1
		if _leg >= path.size():
			if leaving:
				queue_free()
			else:
				_stand()
				arrived.emit(self)
		return
	position += to.normalized() * step
	basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	_walk_phase += delta * 7.0
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk_phase + PI * i) * 0.45


static func walk_speed() -> float:
	return Contracts.WALK_SPEED
