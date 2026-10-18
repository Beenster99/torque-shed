class_name RemoteBike
extends AnimatableBody3D
## Another player's bike: drawn from their streamed state, smoothed by interpolating
## slightly in the past, and solid so bikes can bump into each other.

const DELAY := 0.1

var player_name := ""
var model: BikeModel
var audio: EngineSound
var _build: BikeBuild
var _snapshots: Array = []   # [{t, state}]
var _label: Label3D
var _last := PackedFloat32Array()
var _effects: BikeEffects
var _horn: HornAudio
var _fog: Array = []
var _mark_key := ""         # its tyre's name in the shared skid marks
var _marking := false        # its back tyre was laying rubber last frame
## The rider's gear (slot -> RiderGear item id); set before setup. Empty dresses them as before.
var rider_gear := {}


func setup(rider_name: String, build: BikeBuild, paint: Color, rider_color := Color(0, 0, 0, 0)) -> void:
	add_to_group("ridden_bike")   # shed TVs follow whoever is out riding
	player_name = rider_name
	_build = build
	sync_to_physics = false
	collision_layer = 2
	collision_mask = 0
	for child in get_children():
		child.free()
	model = BikeModel.new()
	model.rider_color = rider_color
	model.rider_gear = rider_gear
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
	add_child(audio)
	audio.setup(_build, model)
	audio.set_distant_filter(true)
	_effects = BikeEffects.new()
	add_child(_effects)
	_effects.setup(model.exhaust_tip(), Vector3(0.0, -_build.rear_radius, _build.wheelbase * 0.5), model.lamp_position(),
		_build.headlight_lumens)


func push_state(state: PackedFloat32Array) -> void:
	if state.size() < 19:
		return
	_snapshots.append({"t": Time.get_ticks_msec() / 1000.0, "s": state})
	while _snapshots.size() > 30:
		_snapshots.pop_front()


func _physics_process(delta: float) -> void:
	var pt := Perf.t0()
	_physics_process_body(delta)
	Perf.add("remote_bikes", pt)


func _physics_process_body(delta: float) -> void:
	if _snapshots.is_empty():
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
	var pos := Vector3(sa[0], sa[1], sa[2]).lerp(Vector3(sb[0], sb[1], sb[2]), f)
	var rot := Quaternion(sa[3], sa[4], sa[5], sa[6]).slerp(Quaternion(sb[3], sb[4], sb[5], sb[6]), f)
	global_transform = Transform3D(Basis(rot), pos)
	_last = sb
	model.update_pose_from(lerpf(sa[10], sb[10], f), sb[11], sb[12], lerpf(sa[13], sb[13], f),
		lerpf(sa[14], sb[14], f), sb[18], 0.0)
	model.set_rider_visible(sb[17] < 0.5)
	audio.rpm = sb[15]
	audio.throttle = sb[16]
	var running := sb.size() < 20 or sb[19] > 0.5
	audio.running = running
	var v := Vector3(sb[7], sb[8], sb[9])
	audio.speed = v.length()
	_effects.update(delta, v.length(), sb[16], running, _build.overall_health(), "", true, 0.0)
	_effects.set_screech(sb[20] if sb.size() > 20 else 0.0)
	# Their horn, while held; it stops if their snapshots stop coming (a dropped connection).
	_horn.pressed = sb.size() > 21 and sb[21] > 0.5 and render_t + DELAY - float(_snapshots[-1]["t"]) < 0.5
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


func current_speed() -> float:
	if _last.size() < 10:
		return 0.0
	return Vector3(_last[7], _last[8], _last[9]).length()
