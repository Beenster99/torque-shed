class_name RemoteBike
extends AnimatableBody3D
## Another player's bike: drawn from their streamed state, smoothed by interpolating
## slightly in the past on their own clock (see NetTimeline), and solid so bikes can bump into each other.
## It's placed each drawn frame, not each physics tick, so it glides beside you rather than judders.

var player_name := ""
var model: BikeModel
var audio: EngineSound
var _build: BikeBuild
## Their snapshots on their clock.
var timeline := NetTimeline.new()
var _last_arrival := -INF     # (our clock, s)
var _label: Label3D
var _last := PackedFloat32Array()
var _effects: BikeEffects
var _horn: HornAudio
var _fog: Array = []
## Their stop lamp and indicators, from their snapshots (see BikeLamps.from_net).
var lamps := BikeLamps.new()
var _mark_key := ""         # its tyre's name in the shared skid marks
var _marking := false        # its back tyre was laying rubber last frame
## The rider's gear (slot -> RiderGear item id); set before setup. Empty dresses them as before.
var rider_gear := {}
## Wheeled along on foot (see Roadside): nobody's sat on it.
var pushed := false
## When (on the clock, s) their respawn's ghost is over, from their snapshots (see BikeGhost).
var _ghost_until := 0.0


## Where the thrown-off rider's pose starts in a snapshot (see Bike.get_net_state).
const RAGDOLL_AT := 28
## Their rider thrown off, while they're down (see _show_ragdoll).
var _ragdoll: RiderRagdoll

## Its speed along itself last step (m/s), and how fast it's slowing, eased (m/s/s).
var _speed_was := INF
var _decel := 0.0


func setup(rider_name: String, build: BikeBuild, paint: Color, rider_color := Color(0, 0, 0, 0)) -> void:
	add_to_group("ridden_bike")   # shed TVs follow whoever is out riding
	player_name = rider_name
	_build = build
	sync_to_physics = false
	# Not solid till its first snapshot puts it where they are: until then it stands wherever it
	# was added (the world's origin, which out on an adventure is near you) and its first move
	# there would shove your bike over.
	collision_layer = 0
	collision_mask = 0
	for child in get_children():
		child.free()
	model = BikeModel.new()
	model.rider_color = rider_color
	model.rider_gear = rider_gear
	model.baked = true   # ridden past, not worked on: far fewer draw calls (see BikeModel._bake_static)
	add_child(model)
	model.build_from(_build, paint)
	_fog = Bike.make_fog_lights(self, model, _build)
	_horn = HornAudio.new()
	_horn.setup_from(_build)
	_horn.position = model.lamp_position()
	add_child(_horn)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 1.1, _build.wheelbase + 0.5)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.45, 0.0)
	add_child(cs)
	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.1, 0.0)
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.006
	_label.no_depth_test = true
	add_child(_label)
	audio = EngineSound.new()
	audio.volume_db = -3.0
	audio.infer_cranking = true
	audio.struggle = Bike.struggle_for(_build, 20.0)   # their plugs and engine as the shed has them
	add_child(audio)
	audio.setup(_build, model)
	audio.set_distant_filter(true)
	_effects = BikeEffects.new()
	add_child(_effects)
	_effects.setup(model.exhaust_tip(), Vector3(0.0, -_build.rear_radius, _build.wheelbase * 0.5), model.lamp_position(),
		_build.headlight_lumens)


## Feeds their snapshot `state`, taken at `sent` on their clock (Net.send_state; below 0 when it isn't known, and
## then it's taken as when it arrived).
func push_state(state: PackedFloat32Array, sent := -1.0) -> void:
	if state.size() < 19:
		return
	var now := Time.get_ticks_usec() / 1000000.0
	_last_arrival = now
	timeline.push(state, sent if sent >= 0.0 else now, now)
	# Their ghost's time left [27]; drawn here a moment behind, like the rest of their snapshot.
	_ghost_until = now + timeline.delay + state[27] if state.size() > 27 and state[27] > 0.0 else 0.0


## Seconds left of their respawn's ghost, as you see it (0 once they're solid).
func ghost_left() -> float:
	return maxf(0.0, _ghost_until - Time.get_ticks_usec() / 1000000.0)


## Whether they're a ghost now, just respawned: your bike passes through theirs (see Bike._update_passing).
func is_ghost() -> bool:
	return ghost_left() > 0.0


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("remote_bikes", pt)


func _process_body(delta: float) -> void:
	if timeline.snaps.is_empty():
		return
	var now := Time.get_ticks_usec() / 1000000.0
	timeline.step(delta)
	var at := timeline.place(now, delta)
	var sa: PackedFloat32Array = at["a"]
	var sb: PackedFloat32Array = at["b"]
	var f: float = at["f"]
	var pos: Vector3 = at["pos"]
	pos += FerryCrossing.lead(pos, timeline.delay)   # (on the crew's ferry: where the boat's taken them since)
	global_transform = Transform3D(Basis(at["rot"]), pos)
	if collision_layer == 0:
		collision_layer = 2   # where they are: solid now, so bikes can bump into each other
	_last = sb
	model.update_pose_from(lerpf(sa[10], sb[10], f), sb[11], sb[12], lerpf(sa[13], sb[13], f),
		lerpf(sa[14], sb[14], f), sb[18], 0.0)
	# Their rider in their riding style (see BikeModel.update_rider): the lean from the bike's
	# roll, the braking from how fast it's slowing, with the stop lamp.
	var fwd_speed := Vector3(sa[7], sa[8], sa[9]).lerp(Vector3(sb[7], sb[8], sb[9]), f).dot(-global_transform.basis.z)
	if delta > 0.0 and _speed_was != INF:
		_decel = RiderStyle.ease_to(_decel, (_speed_was - fwd_speed) / delta, 0.15, delta)
	_speed_was = fwd_speed
	model.update_rider(RiderStyle.lean_of(global_transform.basis), lerpf(sa[10], sb[10], f), fwd_speed,
		RiderStyle.brake_from(_decel, sb.size() > 25 and sb[25] > 0.5), delta)
	model.set_rider_visible(sb[17] < 0.5 and not pushed)
	_show_ragdoll(sa, sb, f, pos)
	BikeGhost.apply(model, BikeGhost.look(ghost_left()))
	# Their left foot down as their bike comes to rest, by its speed as their snapshots have it.
	model.update_foot(Vector3(sb[7], sb[8], sb[9]).length(), delta, sb[17] < 0.5)
	audio.rpm = sb[15]
	audio.throttle = sb[16]
	var running := sb.size() < 20 or sb[19] > 0.5
	audio.running = running
	var v := Vector3(sb[7], sb[8], sb[9])
	audio.speed = v.length()
	_effects.update(delta, v.length(), sb[16], running, _build.overall_health(), "", true, 0.0)
	_effects.set_screech(sb[20] if sb.size() > 20 else 0.0)
	# Their horn, while held; it stops if their snapshots stop coming (a dropped connection).
	_horn.pressed = sb.size() > 21 and sb[21] > 0.5 and now - _last_arrival < 0.5
	if sb.size() > 24:
		_effects.beam_mode = int(sb[24])
	if sb.size() > 22:
		audio.gear = int(sb[22])
	if sb.size() > 23 and _effects.has_method("set_tyre_smoke"):
		_effects.call("set_tyre_smoke", sb[23], Vector3(0.0, -_build.rear_radius, _build.wheelbase * 0.5))
	_rubber(sb[23] if sb.size() > 23 else 0.0, sb[20] if sb.size() > 20 else 0.0, delta)
	var fog := running and _effects.beam_mode >= Bike.BEAM_FOG
	for l in _fog:
		l.visible = fog
	model.set_lights(running, _effects.beam_mode > 0, fog)
	# Their stop lamp and indicators, flashing here in time from when they switched on.
	lamps.from_net(sb[25] if sb.size() > 26 else 0.0, sb[26] if sb.size() > 26 else 0.0)
	lamps.step(delta, 0.0, 0.0)
	model.set_signals(lamps.braking, lamps.left_lit(), lamps.right_lit())


## Their back tyre's rubber on the road: a burnout's patch or a skid's line, laid from the
## snapshots (the ground under it is only looked up while it's marking).
func _rubber(burnout: float, skid: float, delta: float) -> void:
	if _mark_key == "":
		_mark_key = "remote_%d" % get_instance_id()
	var marks := SkidMarks.shared(get_tree())
	if burnout <= 0.05 and skid <= 0.05:
		if _marking:
			marks.mark(_mark_key, Vector3.ZERO, Vector3.UP, 0.0, 0.0, "")
			_marking = false
		return
	var at := global_transform * Vector3(0.0, 0.0, _build.wheelbase * 0.5)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * (_build.rear_radius + 0.6), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var surf := "tarmac"
	if hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
		surf = str((hit["collider"] as Object).get_meta("surface"))
	_marking = true
	if burnout > 0.05:
		marks.scrub(_mark_key, hit["position"], hit["normal"], -global_basis.z, _build.rear_tyre_width, burnout, surf, delta)
	else:
		marks.mark(_mark_key, hit["position"], hit["normal"], _build.rear_tyre_width, skid, surf)


## Their rider thrown off in a crash, tumbling as it does on their game (the pose in their
## snapshots, see Bike.get_net_state), or gone once they're picked up.
func _show_ragdoll(sa: PackedFloat32Array, sb: PackedFloat32Array, f: float, at: Vector3) -> void:
	var need := RAGDOLL_AT + RiderRagdoll.POSE_SIZE
	if sb[17] < 0.5 or sb.size() < need:
		if is_instance_valid(_ragdoll):
			_ragdoll.queue_free()
			_ragdoll = null
		return
	if not is_instance_valid(_ragdoll):
		_ragdoll = RiderRagdoll.puppet()
		add_child(_ragdoll)
		_ragdoll.dress(rider_gear, model.rider_color)
	_ragdoll.show_pose(sa if sa.size() >= need else sb, sb, RAGDOLL_AT, f, at)


## The world's origin moved by `d` (see AdventureWorld): the bike and its snapshots move with it.
func shift_origin(d: Vector3) -> void:
	timeline.shift(d)
	global_position -= d


## Their bike's velocity as their last snapshot has it (m/s).
func current_velocity() -> Vector3:
	if _last.size() < 10:
		return Vector3.ZERO
	return Vector3(_last[7], _last[8], _last[9])


func current_speed() -> float:
	if _last.size() < 10:
		return 0.0
	return Vector3(_last[7], _last[8], _last[9]).length()
