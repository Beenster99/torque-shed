class_name RemotePlayer
extends Node3D
## Another player: a figure walking about the shed with their tool or the part they carry,
## or, while they ride, the bike they're on.

const DELAY := 0.1

var peer := 0
var player_name := ""
var color := Color(0.8, 0.1, 0.1)
var riding_bike := 0
var bike: RemoteBike

var _figure: AnimatableBody3D
var _head: Node3D
var _hand: Node3D
var _label: Label3D
var _snapshots: Array = []
var _hand_sig := ""


func setup(peer_id: int, rider_name: String, paint: Color) -> void:
	peer = peer_id
	player_name = rider_name
	color = paint
	_figure = AnimatableBody3D.new()
	_figure.sync_to_physics = false
	_figure.collision_layer = 16
	_figure.collision_mask = 0
	add_child(_figure)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	_figure.add_child(cs)
	var overalls := _mat(color.darkened(0.35), 0.0, 0.7)
	var skin := _mat(Color(0.85, 0.66, 0.52), 0.0, 0.6)
	var boots := _mat(Color(0.08, 0.07, 0.06), 0.0, 0.6)
	_part(_figure, CapsuleMesh.new(), Vector3(0.0, 1.15, 0.0), Vector3(0.62, 0.62, 0.5), overalls)
	for side in [-1.0, 1.0]:
		_part(_figure, CapsuleMesh.new(), Vector3(0.12 * side, 0.45, 0.0), Vector3(0.24, 0.5, 0.24), overalls)
		_part(_figure, BoxMesh.new(), Vector3(0.12 * side, 0.06, -0.05), Vector3(0.14, 0.12, 0.28), boots)
	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.62, 0.0)
	_figure.add_child(_head)
	_part(_head, SphereMesh.new(), Vector3.ZERO, Vector3(0.24, 0.27, 0.25), skin)
	_part(_head, SphereMesh.new(), Vector3(0.0, 0.07, 0.02), Vector3(0.27, 0.16, 0.28), _mat(color, 0.1, 0.5))  # cap
	_part(_head, BoxMesh.new(), Vector3(0.0, 0.04, -0.17), Vector3(0.22, 0.02, 0.14), _mat(color, 0.1, 0.5))   # peak
	_hand = Node3D.new()
	_hand.position = Vector3(0.28, 1.0, -0.35)
	_figure.add_child(_hand)
	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	_figure.add_child(_label)


func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, size: Vector3, mat: Material) -> void:
	if mesh is CapsuleMesh:
		mesh.radius = 0.5
		mesh.height = 2.0
		size.y *= 0.5
	elif mesh is SphereMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)


## Feeds a network snapshot: [0, x, y, z, yaw, pitch] on foot, or [1, bike id, bike state...] riding.
func push_state(state: PackedFloat32Array) -> void:
	if state.is_empty():
		return
	if state[0] > 0.5 and state.size() >= 21:
		var bike_id := int(state[1])
		if bike_id != riding_bike or bike == null:
			_start_riding(bike_id)
		if bike:
			bike.push_state(state.slice(2))
		return
	if riding_bike != 0:
		_stop_riding()
	if state.size() < 6:
		return
	_snapshots.append({"t": Time.get_ticks_msec() / 1000.0, "s": state})
	while _snapshots.size() > 20:
		_snapshots.pop_front()


func _start_riding(bike_id: int) -> void:
	_stop_riding()
	if not Shed.bikes.has(bike_id):
		return
	riding_bike = bike_id
	bike = RemoteBike.new()
	add_child(bike)
	bike.setup(player_name, Shed.build_of(bike_id), Shed.bikes[bike_id]["paint"])
	_figure.visible = false
	_figure.process_mode = Node.PROCESS_MODE_DISABLED
	_snapshots.clear()


func _stop_riding() -> void:
	riding_bike = 0
	if bike:
		bike.queue_free()
		bike = null
	_figure.visible = true
	_figure.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process(_delta: float) -> void:
	if riding_bike != 0 or _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - DELAY
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[-1]
	for i in range(_snapshots.size() - 1):
		if _snapshots[i]["t"] <= render_t and _snapshots[i + 1]["t"] >= render_t:
			a = _snapshots[i]
			b = _snapshots[i + 1]
			break
	var sa: PackedFloat32Array = a["s"]
	var sb: PackedFloat32Array = b["s"]
	var span: float = b["t"] - a["t"]
	var f := 1.0 if span <= 0.0 else clampf((render_t - a["t"]) / span, 0.0, 1.0)
	var pos := Vector3(sa[1], sa[2], sa[3]).lerp(Vector3(sb[1], sb[2], sb[3]), f)
	_figure.global_transform = Transform3D(Basis(Vector3.UP, lerp_angle(sa[4], sb[4], f)), pos)
	_head.rotation.x = lerpf(sa[5], sb[5], f) * 0.6
	_hand.rotation.x = _head.rotation.x


func _process(_delta: float) -> void:
	# What's in their hand: a part they carry, else their tool.
	var held := Shed.held_by(peer)
	var tool := str(Shed.crew.get(peer, {}).get("tool", "hands"))
	var sig := "%d|%s" % [held, tool]
	if sig == _hand_sig:
		return
	_hand_sig = sig
	for c in _hand.get_children():
		c.queue_free()
	if held != 0:
		var it: Dictionary = Shed.items[held]
		var part := BikeModel.part_display(it["part"], Shed.condition_of(it))
		var size: Vector3 = part.get_meta("size", Vector3.ONE)
		part.scale = Vector3.ONE * clampf(0.6 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
		part.position = Vector3(-0.28, -0.1, -0.1)
		_hand.add_child(part)
	else:
		_hand.add_child(Walker.make_tool_mesh(tool))


func world_position() -> Vector3:
	return bike.global_position if bike else _figure.global_position
