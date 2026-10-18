class_name ChaseCamera
extends Camera3D
## Follows the bike: a smooth chase view the rider can swing round the bike with the mouse or
## right stick, a first-person view from the rider's helmet looking down over the bars and
## clocks, a ride-by view from the roadside ahead that watches the bike go past, and a slow
## orbit for the title screen.

enum Mode { CHASE, HELMET, ORBIT, RIDE_BY }

## Mouse movement to orbit angle, radians a pixel.
const MOUSE_ORBIT := 0.004
## Right stick fully over: radians a second.
const STICK_ORBIT := 2.6
## How far the chase view tilts up over the bike, or down towards the road.
const PITCH_MIN := -0.3
const PITCH_MAX := 1.1
## Seconds without orbit input before the chase view eases back behind the bike.
const RECENTRE_DELAY := 1.5
const RECENTRE_RATE := 2.5
## First person: how far you can turn your head.
const HEAD_YAW := 1.9
const HEAD_PITCH := 0.9
## The ride-by camera: the shortest and longest it watches before going back.
const RIDE_BY_MIN := 3.0
const RIDE_BY_MAX := 7.0

var target: Node3D
var mode := Mode.CHASE
var orbit_center := Vector3.ZERO
var orbit_radius := 4.5
var orbit_height := 1.6
## The rider's swing of the chase view round the bike: yaw (+ swings the camera round to the
## bike's right, so the view turns left) and pitch (+ higher up, looking down), radians from
## straight behind. In first person they turn your head the same way.
var orbit_yaw := 0.0
var orbit_pitch := 0.0
## Ease back behind the bike after a moment without orbit input (Settings: camera recentre).
var recentre := true
var _orbit_angle := 0.0
var _smoothed_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _initialized := false
var _idle := 0.0          # seconds since the rider last swung the camera
var _pivot := Vector3.ZERO
var _heading := 0.0       # smoothed world angle the camera sits at round the bike
var _elev := 0.0          # smoothed angle above the bike
## Ride-by: where the camera stands, how long it has left and the view to go back to.
var _by_pos := Vector3.ZERO
var _by_left := 0.0
var _by_return := Mode.CHASE
## Fly-by as a view of its own (picked with the view toggle): when the bike has gone past, the
## camera hops on to a new spot ahead instead of going back.
var fly_by := false


func _ready() -> void:
	near = 0.05
	far = 2500.0
	fov = 70.0 + Graphics.fov_offset()


## The view toggle: third person, then first person, then fly-by, then round again. A one-off
## ride-by (V) ends back on the view it came from.
func cycle_mode() -> void:
	if mode == Mode.RIDE_BY:
		set_mode(Mode.CHASE if fly_by else _by_return)
		return
	set_mode(Mode.HELMET if mode == Mode.CHASE else Mode.RIDE_BY)


func set_mode(new_mode: Mode) -> void:
	if new_mode == Mode.RIDE_BY:
		fly_by = true
		_by_return = Mode.CHASE
		mode = Mode.CHASE
		start_ride_by()
		if mode == Mode.RIDE_BY:
			return
	fly_by = false
	mode = new_mode
	_initialized = false
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	_set_helmet_hidden(mode == Mode.HELMET)


## The first-person camera sits inside the rider's helmet, so it leaves the helmet out.
func _set_helmet_hidden(hidden: bool) -> void:
	set_cull_mask_value(BikeModel.HELMET_LAYER, not hidden)


func snap() -> void:
	_initialized = false


## The world's origin moved by `d` (see AdventureWorld): everything the camera remembers moves
## with it, so the view doesn't jump.
func shift_origin(d: Vector3) -> void:
	global_position -= d
	_smoothed_pos -= d
	_look -= d
	_pivot -= d
	_by_pos -= d


## Swings the chase view round the bike (or turns your head in first person) by `yaw` and
## `pitch` radians. Mouse: pass the motion times MOUSE_ORBIT; stick: STICK_ORBIT times delta.
func add_orbit(yaw: float, pitch: float) -> void:
	if mode == Mode.HELMET:
		orbit_yaw = clampf(orbit_yaw + yaw, -HEAD_YAW, HEAD_YAW)
		orbit_pitch = clampf(orbit_pitch + pitch, -HEAD_PITCH, HEAD_PITCH)
	elif mode == Mode.CHASE:
		orbit_yaw = wrapf(orbit_yaw + yaw, -PI, PI)
		orbit_pitch = clampf(orbit_pitch + pitch, PITCH_MIN, PITCH_MAX)
	else:
		return
	if absf(yaw) + absf(pitch) > 0.0:
		_idle = 0.0


## Whether the rider has swung the view away from straight behind.
func orbiting() -> bool:
	return absf(orbit_yaw) > 0.02 or absf(orbit_pitch) > 0.02


## Drops the camera at the roadside ahead of the bike to watch it go past, then goes back to
## the view it came from. Calling it again, or changing view, ends it early.
func start_ride_by() -> void:
	if target == null:
		return
	if mode == Mode.RIDE_BY:
		set_mode(_by_return)
		return
	_place_ride_by()
	_by_return = mode if mode in [Mode.CHASE, Mode.HELMET] else Mode.CHASE
	mode = Mode.RIDE_BY
	_set_helmet_hidden(false)


## Picks the roadside spot ahead of the bike and how long to stay there.
func _place_ride_by() -> void:
	var t := target.global_transform
	var flat := _flat_forward(t)
	var right := flat.cross(Vector3.UP)
	var speed := absf(target.speed) if target is Bike else 0.0
	# Far enough ahead that it takes a second or two to get there, then a few metres off the line.
	var ahead := clampf(speed * 1.6, 7.0, 70.0)
	var side := 4.0 + speed * 0.05
	var spot := t.origin + flat * ahead + right * side
	var space := get_world_3d().direct_space_state
	# Stand it on the ground, not in a hill or under the road.
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 30.0, spot + Vector3.DOWN * 30.0, 1)
	var ground := space.intersect_ray(down)
	if ground:
		spot = ground["position"] + Vector3.UP * 1.1
	else:
		spot.y = t.origin.y + 1.1
	# And not behind a wall or tree from the bike.
	var from := t.origin + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, spot, 1)
	q.exclude = [target.get_rid()] if target is CollisionObject3D else []
	var hit := space.intersect_ray(q)
	if hit:
		spot = hit["position"] + (from - spot).normalized() * 0.4
	_by_pos = spot
	_by_left = clampf(ahead / maxf(speed, 1.0) + 2.0, RIDE_BY_MIN, RIDE_BY_MAX)


## Seconds the ride-by view has left (0 when it isn't on).
func ride_by_left() -> float:
	return _by_left if mode == Mode.RIDE_BY else 0.0


## Where the ride-by camera is standing.
func ride_by_spot() -> Vector3:
	return _by_pos


func _physics_process(delta: float) -> void:
	var pt := Perf.t0()
	_physics_process_body(delta)
	Perf.add("camera", pt)


func _physics_process_body(delta: float) -> void:
	_idle += delta
	match mode:
		Mode.ORBIT:
			_orbit(delta)
		Mode.HELMET:
			_helmet(delta)
		Mode.RIDE_BY:
			_ride_by(delta)
		_:
			_chase(delta)


static func _flat_forward(t: Transform3D) -> Vector3:
	var fwd := -t.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	return flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD


## Eases the rider's swing back to straight behind, once they've let go for a moment.
func _recentre(delta: float) -> void:
	if recentre and _idle > RECENTRE_DELAY:
		var k := 1.0 - exp(-RECENTRE_RATE * delta)
		orbit_yaw = lerpf(orbit_yaw, 0.0, k)
		orbit_pitch = lerpf(orbit_pitch, 0.0, k)


func _chase(delta: float) -> void:
	if target == null:
		return
	_recentre(delta)
	var t := target.global_transform
	var flat := _flat_forward(t)
	var speed := 0.0
	if target is Bike or target is Car:
		speed = absf(target.speed)
	# A bigger thing to follow (the recovery truck and its trailer) is followed from further back.
	var scale: float = float(target.get_meta("chase_scale", 1.0))
	var dist := (4.6 + speed * 0.04) * scale
	var height := (1.7 + speed * 0.008) * sqrt(scale)
	var radius := sqrt(dist * dist + height * height)
	var want_heading := atan2(-flat.x, -flat.z) + orbit_yaw
	var want_elev := clampf(atan2(height, dist) + orbit_pitch, -0.12, 1.35)
	if not _initialized:
		_pivot = t.origin
		_heading = want_heading
		_elev = want_elev
		_look = t.origin + Vector3.UP * 0.9 + flat * 2.0
		_initialized = true
	# Swing round the bike, never through it: the angles are smoothed, not the position.
	var k := 1.0 - exp(-(14.0 if _idle < 0.2 else 7.0) * delta)
	_heading = lerp_angle(_heading, want_heading, k)
	_elev = lerpf(_elev, want_elev, k)
	_pivot = _pivot.lerp(t.origin, 1.0 - exp(-10.0 * delta))
	var dir := Vector3(sin(_heading) * cos(_elev), sin(_elev), cos(_heading) * cos(_elev))
	var desired := _pivot + dir * radius
	# Looking ahead down the road from behind; at the bike itself once swung round it.
	var swung := clampf(absf(orbit_yaw) / 0.6, 0.0, 1.0)
	var look := t.origin + Vector3.UP * 0.9 + flat * 2.0 * (1.0 - swung)
	# Keep the camera out of hills and walls.
	var from := t.origin + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		desired = hit["position"] + (from - desired).normalized() * 0.3
	_smoothed_pos = desired
	_look = _look.lerp(look, 1.0 - exp(-12.0 * delta))
	global_position = _smoothed_pos
	if global_position.distance_to(_look) > 0.1:
		look_at(_look, Vector3.UP)
	fov = lerpf(fov, 68.0 + Graphics.fov_offset() + clampf(speed * 0.35, 0.0, 22.0), 1.0 - exp(-3.0 * delta))


func _helmet(delta := 0.0) -> void:
	if target == null:
		return
	_recentre(delta)
	if target is Bike and target.model:
		var model: BikeModel = target.model
		global_transform = model.global_transform * model.eye_transform()
	elif target.has_method("eye_transform"):
		global_transform = target.global_transform * target.eye_transform()
	else:
		global_transform = target.global_transform.translated_local(Vector3(0.0, 1.5, 0.0))
	if orbiting():
		# Turning your head inside the helmet.
		global_basis = global_basis * Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, -orbit_pitch)
	fov = 80.0 + Graphics.fov_offset()


## Stood at the roadside, following the bike past with a slightly long lens.
func _ride_by(delta: float) -> void:
	if target == null:
		set_mode(_by_return)
		return
	_by_left -= delta
	# On the fly-by view, hop on ahead once the bike is past and pulling away (or time's up).
	if fly_by and (_by_left <= 0.0 or _gone_past()):
		_place_ride_by()
	elif _by_left <= 0.0:
		set_mode(_by_return)
		snap()
		return
	global_position = _by_pos
	var aim := target.global_position + Vector3.UP * 0.7
	if global_position.distance_to(aim) > 0.3:
		look_at(aim, Vector3.UP)
	var d := global_position.distance_to(aim)
	fov = clampf(70.0 - d * 0.6, 35.0, 65.0) + Graphics.fov_offset() * 0.5


## Whether the bike has ridden past the fly-by camera and is a fair way off.
func _gone_past() -> bool:
	var to_cam := _by_pos - target.global_position
	to_cam.y = 0.0
	return to_cam.dot(_flat_forward(target.global_transform)) < 0.0 and to_cam.length() > 25.0


func _orbit(delta: float) -> void:
	_set_helmet_hidden(false)
	_orbit_angle += delta * 0.25
	var pos := orbit_center + Vector3(sin(_orbit_angle) * orbit_radius, orbit_height, cos(_orbit_angle) * orbit_radius)
	global_position = pos
	look_at(orbit_center + Vector3.UP * 0.6, Vector3.UP)
	fov = 55.0
