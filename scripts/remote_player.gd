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
var _work_sound: AudioStreamPlayer3D
var _phones: Node3D     # ear defenders, shown while they wear them (the dyno room's)
var _body_look: Node3D  # the figure's meshes in their gear, and the head's
var _head_look: Node3D
## The rider gear they're drawn in: slot -> item id (see RiderGear).
var gear := {}
var _gear_sig := ""
var _stride := 0.0         # how far they've walked since their last footstep
var _step_from := Vector3.INF


func setup(peer_id: int, rider_name: String, paint: Color) -> void:
	peer = peer_id
	player_name = rider_name
	add_to_group("remote_players")
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
	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.62, 0.0)
	_figure.add_child(_head)
	# Their rider gear (see RiderGear), drawn again whenever they change it.
	_body_look = Node3D.new()
	_figure.add_child(_body_look)
	_head_look = Node3D.new()
	_head.add_child(_head_look)
	_dress()
	_phones = DynoRoom.headphones_model()
	_phones.position = Vector3(0.0, 0.035, 0.0)
	_phones.scale = Vector3(0.95, 0.95, 0.95)
	_phones.visible = false
	_head.add_child(_phones)
	_hand = Node3D.new()
	_hand.position = Vector3(0.28, 1.0, -0.35)
	_figure.add_child(_hand)
	_work_sound = Sfx.make_loop_player(_hand)
	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	_figure.add_child(_label)


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
	bike.rider_gear = gear
	add_child(bike)
	bike.setup(player_name, Shed.build_of(bike_id), Shed.bikes[bike_id]["paint"], color)
	bike.model.apply_geometry(Shed.geometry_of(bike_id))   # the parts as that bike's own fit has them
	bike.set_meta("shed_bike", bike_id)   # so the shed TVs know whose ride this is
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
	_footsteps(pos)
	_head.rotation.x = lerpf(sa[5], sb[5], f) * 0.6
	_hand.rotation.x = _head.rotation.x
	# Crouching: squash the figure down to about two thirds of its height.
	var low := sb.size() > 6 and sb[6] > 0.5
	_figure.scale.y = move_toward(_figure.scale.y, 0.62 if low else 1.0, 0.08)


## Their footsteps, by the floor they walk on (a step every 0.7 m or so).
func _footsteps(pos: Vector3) -> void:
	if _step_from != Vector3.INF:
		var moved := Vector2(pos.x - _step_from.x, pos.z - _step_from.z).length()
		if moved < 2.0:
			_stride += moved
	_step_from = pos
	if _stride > 0.75:
		_stride = 0.0
		Sfx.footstep(pos, false, -12.0)


## Whether they've got the dyno room's ear defenders on.
func wearing_phones() -> bool:
	return _phones != null and _phones.visible


## Dresses the figure in what they wear now (their Progress summary), and their bike's rider.
func _dress() -> void:
	gear = RiderGear.worn_of(peer)
	_gear_sig = RiderGear.sig(gear)
	for c in _body_look.get_children():
		c.free()
	for c in _head_look.get_children():
		c.free()
	RiderFigure.standing(_body_look, _head_look, gear, color)
	if bike and bike.model:
		bike.model.redress(gear)


func _process(_delta: float) -> void:
	_phones.visible = Shed.wearing_headphones(peer)
	if RiderGear.sig(RiderGear.worn_of(peer)) != _gear_sig:
		_dress()
	# What's in their hand: a part they carry, else their tool.
	var held := Shed.held_by(peer)
	var tool := str(Shed.crew.get(peer, {}).get("tool", "hands"))
	# You hear their tools while they work.
	var working := riding_bike == 0 and str(Shed.crew.get(peer, {}).get("activity", "")) != ""
	Sfx.set_loop(_work_sound, Sfx.TOOL_LOOPS.get(tool, "") if working else "")
	var jet := _hand.get_node_or_null("Jet") as CPUParticles3D
	if jet:
		jet.emitting = working and tool == "lance"
	var stage := Progress.tool_stage(peer, tool)
	var sig := "%d|%s|%d" % [held, tool, stage]
	if sig == _hand_sig:
		return
	_hand_sig = sig
	for c in _hand.get_children():
		if c != _work_sound:
			c.queue_free()
	if held != 0:
		var part := BikeModel.item_display(held)
		var size: Vector3 = part.get_meta("size", Vector3.ONE)
		part.scale = Vector3.ONE * clampf(0.6 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
		part.position = Vector3(-0.28, -0.1, -0.1)
		_hand.add_child(part)
	else:
		_hand.add_child(Walker.make_tool_mesh(tool, Color(0.9, 0.75, 0.1), stage))
		if tool == "lance":
			var spray := Walker.make_jet()
			spray.name = "Jet"
			spray.position = Vector3(0.0, 0.0, -0.6)
			_hand.add_child(spray)


func world_position() -> Vector3:
	return bike.global_position if bike else _figure.global_position


## Where they are and which way they face: their bike's, while they ride.
func world_transform() -> Transform3D:
	return bike.global_transform if bike else _figure.global_transform
