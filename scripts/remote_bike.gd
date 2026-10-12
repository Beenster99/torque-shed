class_name RemoteBike
extends AnimatableBody3D
## Another player's bike: drawn from their streamed state, smoothed by interpolating
## slightly in the past, and solid so bikes can bump into each other.

const DELAY := 0.1

var player_name := ""
var model: BikeModel
var audio: EngineAudio
var _build: BikeBuild
var _snapshots: Array = []   # [{t, state}]
var _label: Label3D
var _last := PackedFloat32Array()


func setup(rider_name: String, build: BikeBuild, paint: Color) -> void:
	player_name = rider_name
	_build = build
	sync_to_physics = false
	collision_layer = 2
	collision_mask = 0
	for child in get_children():
		child.free()
	model = BikeModel.new()
	add_child(model)
	model.build_from(_build, paint)
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
	audio = EngineAudio.new()
	audio.cylinders = _build.cylinders
	audio.loudness = _build.exhaust_loudness
	audio.volume_db = -6.0
	add_child(audio)


func push_state(state: PackedFloat32Array) -> void:
	if state.size() < 19:
		return
	_snapshots.append({"t": Time.get_ticks_msec() / 1000.0, "s": state})
	while _snapshots.size() > 30:
		_snapshots.pop_front()


func _physics_process(_delta: float) -> void:
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


func current_speed() -> float:
	if _last.size() < 10:
		return 0.0
	return Vector3(_last[7], _last[8], _last[9]).length()
