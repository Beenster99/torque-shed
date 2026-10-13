class_name ChaseCamera
extends Camera3D
## Follows the bike: a smooth chase view, a first-person view from the rider's helmet looking
## down over the bars and clocks, and a slow orbit for the title screen.

enum Mode { CHASE, HELMET, ORBIT }

var target: Node3D
var mode := Mode.CHASE
var orbit_center := Vector3.ZERO
var orbit_radius := 4.5
var orbit_height := 1.6
var _orbit_angle := 0.0
var _smoothed_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	near = 0.05
	far = 2500.0
	fov = 70.0


func cycle_mode() -> void:
	set_mode(Mode.HELMET if mode == Mode.CHASE else Mode.CHASE)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_initialized = false
	_set_helmet_hidden(mode == Mode.HELMET)


## The first-person camera sits inside the rider's helmet, so it leaves the helmet out.
func _set_helmet_hidden(hidden: bool) -> void:
	set_cull_mask_value(BikeModel.HELMET_LAYER, not hidden)


func snap() -> void:
	_initialized = false


func _physics_process(delta: float) -> void:
	match mode:
		Mode.ORBIT:
			_orbit(delta)
		Mode.HELMET:
			_helmet()
		_:
			_chase(delta)


func _chase(delta: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	var fwd := -t.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	var speed := 0.0
	if target is Bike:
		speed = absf(target.speed)
	var dist := 4.6 + speed * 0.04
	var desired := t.origin - flat * dist + Vector3.UP * (1.7 + speed * 0.008)
	var look := t.origin + Vector3.UP * 0.9 + flat * 2.0
	# Keep the camera out of hills and walls.
	var from := t.origin + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		desired = hit["position"] + (from - desired).normalized() * 0.3
	if not _initialized:
		_smoothed_pos = desired
		_look = look
		_initialized = true
	_smoothed_pos = _smoothed_pos.lerp(desired, 1.0 - exp(-7.0 * delta))
	_look = _look.lerp(look, 1.0 - exp(-12.0 * delta))
	global_position = _smoothed_pos
	if global_position.distance_to(_look) > 0.1:
		look_at(_look, Vector3.UP)
	fov = lerpf(fov, 68.0 + clampf(speed * 0.35, 0.0, 22.0), 1.0 - exp(-3.0 * delta))


func _helmet() -> void:
	if target == null:
		return
	if target is Bike and target.model:
		var model: BikeModel = target.model
		global_transform = model.global_transform * model.eye_transform()
	else:
		global_transform = target.global_transform.translated_local(Vector3(0.0, 1.5, 0.0))
	fov = 80.0


func _orbit(delta: float) -> void:
	_set_helmet_hidden(false)
	_orbit_angle += delta * 0.25
	var pos := orbit_center + Vector3(sin(_orbit_angle) * orbit_radius, orbit_height, cos(_orbit_angle) * orbit_radius)
	global_position = pos
	look_at(orbit_center + Vector3.UP * 0.6, Vector3.UP)
	fov = 55.0
