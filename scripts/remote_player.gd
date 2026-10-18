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
var driving := false    # in the recovery truck

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
var _walk_phase := 0.0     # how far through their stride their legs are (see RiderFigure.walk_pose)
var _walk_from := Vector3.INF
## The emote they're doing (see Emotes), how far into it they are, and for a point where at.
var emote := ""
var emote_time := 0.0
var emote_at = null        # a world point to point at, or null for straight ahead
var emotes_seen: Array[String] = []   # every emote they've done here, in order
var _bubble: Label3D       # what they're doing, over their head


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
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0.0, 2.28, 0.0)
	_bubble.font_size = 40
	_bubble.outline_size = 10
	_bubble.pixel_size = 0.005
	_bubble.modulate = Color(1.0, 0.85, 0.35)
	_bubble.visible = false
	_figure.add_child(_bubble)


## Plays an emote (see Emotes) on their figure. `at` is a world point for a point, or null.
func play_emote(e: String, at = null) -> void:
	if not Emotes.is_emote(e) or riding_bike != 0:
		return
	emote = e
	emote_time = 0.0
	emotes_seen.append(e)
	if emotes_seen.size() > 20:
		emotes_seen.pop_front()
	emote_at = at if at is Vector3 else null
	_bubble.text = "*%s*" % Emotes.VERBS[e]
	_bubble.visible = true


## Swings their arms, head and body through the emote under way, and back to rest after.
func _animate_emote(delta: float) -> void:
	var arm_r := _body_look.get_node_or_null("ArmR") as Node3D
	var arm_l := _body_look.get_node_or_null("ArmL") as Node3D
	var w := 0.0
	var p := {}
	if emote != "":
		emote_time += delta
		w = Emotes.weight(emote, emote_time)
		var aim := Vector3.ZERO
		if emote_at is Vector3:
			aim = _figure.global_transform.affine_inverse() * (emote_at as Vector3)
			if aim.length() < 0.01:
				aim = Vector3(0.0, 0.0, -0.02)
		p = Emotes.pose(emote, emote_time, aim)
		if emote_time >= float(Emotes.LENGTH.get(emote, 2.0)):
			emote = ""
			_bubble.visible = false
	if arm_r:
		arm_r.quaternion = Quaternion.IDENTITY.slerp(Emotes.arm_turn(true, p.get("r", Vector3.ZERO)), w)
	if arm_l:
		arm_l.quaternion = Quaternion.IDENTITY.slerp(Emotes.arm_turn(false, p.get("l", Vector3.ZERO)), w)
	_body_look.position.y = float(p.get("bob", 0.0)) * w
	_body_look.rotation.y = float(p.get("twist", 0.0)) * w
	_head_look.position.y = float(p.get("bob", 0.0)) * w
	_head_look.rotation = Vector3(float(p.get("nod", 0.0)) * w, float(p.get("twist", 0.0)) * w, float(p.get("tilt", 0.0)) * w)
	# The tool in their hand would float off when the arm goes up: it's put away meanwhile.
	_hand.visible = w < 0.05


## Feeds a network snapshot: [0, x, y, z, yaw, pitch] on foot, or [1, bike id, bike state...] riding.
func push_state(state: PackedFloat32Array) -> void:
	if state.is_empty():
		return
	if state[0] > 1.5:
		# Driving the recovery truck (see RecoveryView): the figure's in the cab.
		if riding_bike != 0:
			_stop_riding()
		driving = true
		_figure.visible = false
		if RecoveryView.current:
			RecoveryView.current.remote_state(peer, state)
		return
	var driving_left := driving
	if driving:
		driving = false
		_figure.visible = true
	if state[0] > 0.5 and state.size() >= 21:
		var bike_id := int(state[1])
		if bike_id != riding_bike or bike == null:
			_start_riding(bike_id)
		if bike:
			bike.push_state(state.slice(2))
		return
	var was_riding := riding_bike != 0
	if was_riding:
		_stop_riding()
	if state.size() < 6:
		return
	if was_riding or driving_left:
		# Off the bike (or out of the truck): stood where they got off at once, not shown for a
		# frame back where they were last on foot (the garage, often) before walking there.
		_snapshots.clear()
		_figure.global_transform = Transform3D(Basis(Vector3.UP, state[4]), Vector3(state[1], state[2], state[3]))
		_walk_from = Vector3.INF
		_step_from = Vector3.INF
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


func _physics_process(delta: float) -> void:
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
	_walk(pos, delta)
	_head.rotation.x = lerpf(sa[5], sb[5], f) * 0.6
	_hand.rotation.x = _head.rotation.x
	# Crouching: squash the figure down to about two thirds of its height.
	var low := sb.size() > 6 and sb[6] > 0.5
	_figure.scale.y = move_toward(_figure.scale.y, 0.62 if low else 1.0, 0.08)


## Swings their legs as they walk, by how fast they're going.
func _walk(pos: Vector3, delta: float) -> void:
	var speed := 0.0
	if _walk_from != Vector3.INF and delta > 0.0:
		speed = Vector2(pos.x - _walk_from.x, pos.z - _walk_from.z).length() / delta
	_walk_from = pos
	if speed > 12.0:
		speed = 0.0   # a jump across the shed, not a walk
	_walk_phase = step_walk(_body_look, _walk_phase, speed, delta, self)


## Moves a standing figure's stride on by `delta` at `speed` m/s and poses its legs; returns
## the new phase. The swing eases in and out with the speed (kept on `holder` as walk_amount).
static func step_walk(body: Node3D, phase: float, speed: float, delta: float, holder: Object) -> float:
	var want := clampf(speed / 3.2, 0.0, 1.3)
	var amount := move_toward(float(holder.get_meta("walk_amount", 0.0)), want, delta * 6.0)
	holder.set_meta("walk_amount", amount)
	# About 1.4 m a stride (two steps); stood still the legs settle back together.
	phase = wrapf(phase + speed / 1.4 * TAU * delta, 0.0, TAU) if amount > 0.01 else 0.0
	RiderFigure.walk_pose(body, phase, amount)
	return phase


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


func _process(delta: float) -> void:
	_animate_emote(delta)
	_phones.visible = Shed.wearing_headphones(peer)
	if RiderGear.sig(RiderGear.worn_of(peer)) != _gear_sig:
		_dress()
	# What's in their hand: a part they carry, a tray from the cafe, else their tool.
	var tool := str(Shed.crew.get(peer, {}).get("tool", "hands"))
	# You hear their tools while they work.
	var working := riding_bike == 0 and str(Shed.crew.get(peer, {}).get("activity", "")) != ""
	Sfx.set_loop(_work_sound, Sfx.TOOL_LOOPS.get(tool, "") if working else "")
	var jet := _hand.get_node_or_null("Jet") as CPUParticles3D
	if jet:
		jet.emitting = working and tool == "lance"
	# Their spray can or gun mists while they lay a coat on.
	var mist := _hand.get_node_or_null("Mist") as CPUParticles3D
	if mist:
		var act := str(Shed.crew.get(peer, {}).get("activity", ""))
		var on := working and (act.begins_with("Spraying") or act.begins_with("Priming") or act.begins_with("Coating"))
		mist.emitting = on
		(mist.get_node("Haze") as CPUParticles3D).emitting = on
	var sig := hand_sig(peer, tool)
	if sig == _hand_sig:
		return
	_hand_sig = sig
	fill_hand(_hand, peer, tool, _work_sound)


## What's in a player's hand, as a string that changes whenever it should be drawn again.
static func hand_sig(peer: int, tool: String) -> String:
	var tray := CoffeeShop.tray_of(peer)
	var bay := PaintBay.held(peer)
	return "%d|%s|%d|%s|%s" % [Shed.held_by(peer), tool, Progress.tool_stage(peer, tool), str(tray.get("items", "-")),
		str(bay) + str(PaintBay.held_tin(peer).get("code", ""))]


## Draws what's in a player's hand on a figure's `hand` node: a part they carry, a tray from
## the cafe, a tin or the tape from the mixing bay, else their tool (with its jet or mist,
## named "Jet" and "Mist"). Everything already on it but `keep` goes.
static func fill_hand(hand: Node3D, peer: int, tool: String, keep: Node = null) -> void:
	var held := Shed.held_by(peer)
	var stage := Progress.tool_stage(peer, tool)
	var tray := CoffeeShop.tray_of(peer)
	var bay := PaintBay.held(peer)
	for c in hand.get_children():
		if c != keep:
			c.queue_free()
	if held != 0:
		var part := BikeModel.item_display(held)
		var size: Vector3 = part.get_meta("size", Vector3.ONE)
		part.scale = Vector3.ONE * clampf(0.6 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
		part.position = Vector3(-0.28, -0.1, -0.1)
		hand.add_child(part)
	elif not tray.is_empty():
		var t := CoffeeView.tray_model(tray["items"])
		t.name = "Tray"
		t.position = Vector3(-0.28, 0.0, -0.2)
		hand.add_child(t)
	elif not bay.is_empty():
		# A tin of paint or the masking tape from the mixing bay (see PaintBay).
		var b := PaintBayRoom.tin_model(PaintBay.held_tin(peer)) if str(bay.get("kind", "")) == "tin" else PaintBayRoom.tape_model()
		b.name = "PaintBay"
		b.position = Vector3(-0.2, -0.05, -0.1)
		hand.add_child(b)
	else:
		hand.add_child(Walker.make_tool_mesh(tool, Color(0.9, 0.75, 0.1), stage))
		if tool == "lance":
			var spray := Walker.make_jet()
			spray.name = "Jet"
			spray.position = Vector3(0.0, 0.0, -0.6)
			hand.add_child(spray)
		elif tool in ["spray", "gun"]:
			var can_mist := Walker.make_mist()
			can_mist.name = "Mist"
			can_mist.color = Color(0.85, 0.85, 0.85)
			can_mist.position = Vector3(0.0, 0.1, -0.15)
			hand.add_child(can_mist)


func world_position() -> Vector3:
	if driving and RecoveryView.current and RecoveryView.current.remote_transform(peer) != null:
		return (RecoveryView.current.remote_transform(peer) as Transform3D).origin
	return bike.global_position if bike else _figure.global_position


## Where they are and which way they face: their bike's, while they ride.
func world_transform() -> Transform3D:
	return bike.global_transform if bike else _figure.global_transform
