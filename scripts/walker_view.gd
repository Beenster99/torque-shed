class_name WalkerView
extends Node3D
## Third person on foot: a camera behind your right shoulder that follows you about, with your
## own figure in view (the same one the crew see, in your rider gear, legs swinging as you walk
## and squashed down when you crouch). The mouse and right stick swing it round you as they
## turn and tilt your head, so it orbits with your view.
##
## Aiming is unchanged underneath: the walker's own eye camera still does every ray (hover
## targets, work, F on things, pings), but in third person it is turned each tick to look at
## whatever is under the crosshair, so you work on what the crosshair is over, as far as your
## arm reaches from where you stand.
##
## The jobs where you need to see right down your arm switch to first person by themselves and
## back after: spraying with the can or gun, pressure washing a bike with the wash controls up,
## the sandblaster's gloves, the tyre changer's game, and sitting down.
##
## The walker adds this as a child; the setting is Settings.walk_third_person (V, or View on a
## pad, toggles it).

## The camera's spot behind the shoulder: how far back, how far right and how far up from your
## eye, outdoors and under a roof (the shed's rooms are small, so it comes in closer).
const ARM_OUT := 2.7
const ARM_IN := 1.7
const SHOULDER_OUT := 0.75
const SHOULDER_IN := 0.62
const LIFT := 0.22
## The camera stays this far off walls and ceilings, so it never sees through them.
const MARGIN := 0.2
## Closer to your head than this and your figure is hidden, so it doesn't fill the screen.
const TOO_CLOSE := 0.45
## The crosshair looks this far for what it's over.
const AIM_RANGE := 60.0
## How fast the camera pulls back out after a wall's pushed it in (it comes in at once).
const ARM_EASE := 4.0

var walker: Walker
var camera: Camera3D       # the third-person camera
var body: Node3D           # your figure, feet at the walker's origin
var _look: Node3D          # its meshes in your gear
var _head: Node3D
var _head_look: Node3D
var _hand: Node3D
var _gear_sig := ""
var _hand_sig := ""
var _arm := ARM_IN         # the camera's distance back from your shoulder as it is now
var _was_on := false
var _walk_phase := 0.0
var _indoors := true
var _roof_check := 0.0
## Why first person has taken over for now ("" when it hasn't), for the feedback line.
var _forced_for := ""


func _init(w: Walker) -> void:
	walker = w
	name = "ThirdPerson"


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "ThirdPersonCamera"
	camera.near = 0.05
	camera.far = 2500.0
	camera.fov = Settings.gfx_fov
	camera.add_to_group("gfx_fov")
	add_child(camera)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_look = Node3D.new()
	body.add_child(_look)
	_head = Node3D.new()
	_head.position = Vector3(0.0, Walker.EYE, 0.0)
	body.add_child(_head)
	_head_look = Node3D.new()
	_head.add_child(_head_look)
	_hand = Node3D.new()
	_hand.position = Vector3(0.28, 1.0, -0.35)
	body.add_child(_hand)
	body.visible = false
	_dress()


## Whether third person is what you've picked on foot.
static func wanted() -> bool:
	return Settings.walk_third_person


## Why the view has to be first person right now, or "" when third person is fine.
func forced_reason() -> String:
	var w := walker
	if w.seat != 0:
		return "sitting down"
	if w.blast or Shed.blasting(Shed.me()) != 0:
		return "the sandblaster"
	if w.tyre_game:
		return "the tyre changer"
	if not w.wash_mode.is_empty():
		return "washing"
	if not w.spray_mode.is_empty() or (w.spray != null and w.spray.live) \
			or (not w._cover.is_empty() and bool(w._cover.get("live", false))):
		return "spraying"
	return ""


## Whether the third-person view is the one in use now.
func active() -> bool:
	return wanted() and _forced_for == ""


## Switches between first and third person on foot (the walk_camera key), and remembers it.
func toggle() -> void:
	Settings.walk_third_person = not Settings.walk_third_person
	Settings.save_settings()
	var reason := forced_reason()
	if Settings.walk_third_person and reason != "":
		Shed.feedback.emit("Third person: back when you've finished %s." % reason, true)
	else:
		Shed.feedback.emit("Third person" if Settings.walk_third_person else "First person", true)
	update(0.0)


## Called by the walker every physics tick before it works out its target, and every frame:
## places the camera, shows or hides your figure and, in third person, turns the walker's eye
## to what the crosshair is over.
func update(delta: float, aim := false) -> void:
	_forced_for = forced_reason() if wanted() else ""
	var on := active()
	if on != _was_on:
		_switch(on)
	if not on:
		return
	_place_camera(delta)
	if aim:
		_aim_eye()


func _switch(on: bool) -> void:
	_was_on = on
	body.visible = on
	# The tool and part drawn in front of your eyes are for first person only.
	walker.camera.visible = not on
	if on:
		_arm = 0.6
		if walker.camera.current:
			camera.current = true
	else:
		walker.camera.rotation = Vector3(walker.pitch(), 0.0, 0.0)
		if camera.current:
			walker.camera.current = true


func _process(delta: float) -> void:
	if walker == null or not walker.is_inside_tree():
		return
	update(delta)
	if not active():
		return
	# Whoever handed the view back to the walker gave it to its eye: it's this one in third person.
	if walker.camera.current:
		camera.current = true
	_animate(delta)


## The eye in the walker's head: where every ray you aim starts from.
func eye_point() -> Vector3:
	return walker.global_transform * Vector3(0.0, walker.camera.position.y, 0.0)


## Where the camera's arm starts: inside you, a little below your eye, where your own
## collision shape keeps the walls further off than the camera needs.
func arm_start() -> Vector3:
	return walker.global_transform * Vector3(0.0, clampf(walker.camera.position.y - 0.4, 0.5, 1.3), 0.0)


## Which way you're looking: the walker's turn, then your head's tilt.
func view_basis() -> Basis:
	return walker.global_basis * Basis(Vector3.RIGHT, walker.pitch())


func _place_camera(delta: float) -> void:
	var space := walker.get_world_3d().direct_space_state
	var eye := eye_point()
	_roof_check -= delta
	if _roof_check <= 0.0:
		# Under a roof (the shed and its rooms), the camera comes in closer.
		_roof_check = 0.25
		var up := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 12.0, 1)
		up.exclude = [walker.get_rid()]
		_indoors = not space.intersect_ray(up).is_empty()
	var vb := view_basis()
	var want := ARM_IN if _indoors else ARM_OUT
	var side := SHOULDER_IN if _indoors else SHOULDER_OUT
	var spot := eye + vb.x * side + Vector3.UP * LIFT + vb.z * want
	# The spring arm: a ball swept out from inside you to the spot stops short of anything solid.
	var start := arm_start()
	var ball := SphereShape3D.new()
	ball.radius = MARGIN
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis(), start)
	q.motion = spot - start
	q.collision_mask = 1
	q.exclude = [walker.get_rid()]
	var full := (spot - start).length()
	var room := 0.0
	if space.intersect_shape(q, 1).is_empty():
		var free := space.cast_motion(q)
		room = full * (free[0] if free.size() > 0 else 1.0)
	if room < _arm or delta <= 0.0:
		_arm = room
	else:
		_arm = minf(room, lerpf(_arm, full, 1.0 - exp(-ARM_EASE * delta)))
	var dir := (spot - start).normalized() if full > 0.01 else vb.z
	camera.global_transform = Transform3D(vb, start + dir * _arm)
	# Right up against your head (backed into a corner), your figure would fill the view.
	body.visible = _arm > TOO_CLOSE


## Turns the walker's eye to look at what's under the crosshair, so its rays (reach and all)
## go from your head to there.
func _aim_eye() -> void:
	var eye := eye_point()
	var dir := -camera.global_basis.z
	var from := camera.global_position
	# Start the crosshair's ray level with your head, not in what's between it and the camera.
	from += dir * maxf(0.0, (eye - from).dot(dir))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * AIM_RANGE, 1 | 2 | 4 | Workshop.INTERACT_LAYER)
	q.exclude = [walker.get_rid()]
	var hit := walker.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit["position"] if hit else from + dir * AIM_RANGE
	var to := at - eye
	if to.length() < 0.15 or to.normalized().dot(dir) < 0.2:
		to = dir
	walker.camera.global_basis = Basis.looking_at(to.normalized(), Vector3.UP if absf(to.normalized().y) < 0.999 else Vector3.FORWARD)


## Your figure: dressed in your gear, the tool or part in your hand, legs walking, head tilting
## with your look and squashed down for a crouch, as the crew see you.
func _animate(delta: float) -> void:
	if RiderGear.sig(RiderGear.worn_of(Shed.me())) != _gear_sig:
		_dress()
	var sig := RemotePlayer.hand_sig(Shed.me(), walker.tool)
	if sig != _hand_sig:
		_hand_sig = sig
		RemotePlayer.fill_hand(_hand, Shed.me(), walker.tool)
	var jet := _hand.get_node_or_null("Jet") as CPUParticles3D
	if jet:
		jet.emitting = walker._jet != null and walker._jet.emitting
	var flat := Vector2(walker.velocity.x, walker.velocity.z).length() if walker.is_on_floor() else 0.0
	_walk_phase = RemotePlayer.step_walk(_look, _walk_phase, flat, delta, self)
	_head.rotation.x = walker.pitch() * 0.6
	_hand.rotation.x = _head.rotation.x
	var low := walker.crouched
	body.scale.y = move_toward(body.scale.y, 0.62 if low else 1.0, delta * 9.6)


func _dress() -> void:
	var gear := RiderGear.worn_of(Shed.me())
	_gear_sig = RiderGear.sig(gear)
	for c in _look.get_children():
		c.free()
	for c in _head_look.get_children():
		c.free()
	RiderFigure.standing(_look, _head_look, gear, Shed.PAINTS[Net.local_slot() % Shed.PAINTS.size()])
