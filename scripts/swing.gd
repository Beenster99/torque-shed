class_name Swing
extends Node3D
## A part hanging on a hook: it, the hook and the wire swing together like a pendulum from the
## wire's mount on the ceiling rail when it's knocked or caught by the spray, for a few seconds,
## and settle again. This node is that mount; the wire, hook and part are children hanging
## below it. Anyone walking into the part (this player or another one) knocks it the way they
## were going.

const GRAVITY := 9.8
## How close someone has to come to the hanging part to knock it, and how hard it goes.
const KNOCK_RADIUS := 0.5
const KNOCK_GAIN := 0.5          # push per metre walked through it, at a walk
const MAX_ANGLE := 0.45           # radians either way, at most

var length := 0.55          # the rail mount to the part, in metres
var damping := 0.9          # how quickly the swing dies away (a knock swings for a few seconds)
var _angle := Vector2.ZERO  # tilt about the pivot's x and z axes, radians
var _rate := Vector2.ZERO
var _last := {}             # walker instance id -> where they were last frame


## A shove at the part, in world space (metres per second worth of push).
func push(world_velocity: Vector3) -> void:
	var local := global_transform.basis.inverse() * world_velocity
	# Moving the part along +z tilts it about +x, and along +x about -z.
	_rate += Vector2(local.z, -local.x) / maxf(length, 0.1)


func angle() -> Vector2:
	return _angle


## Where the hanging part is, at rest.
func part_position() -> Vector3:
	return global_position + Vector3.DOWN * length


## Knocks the part for anyone who has walked into it since last frame: a push along the way
## they moved, harder the faster they went.
func _knocks(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	var part := part_position()
	var seen := {}
	for group in ["local_walker", "remote_players"]:
		for n in get_tree().get_nodes_in_group(group):
			if not (n is Node3D) or not (n as Node3D).is_inside_tree():
				continue
			var at := (n as Node3D).global_position
			var key := n.get_instance_id()
			seen[key] = true
			var was: Vector3 = _last.get(key, at)
			_last[key] = at
			var near := Vector2(at.x - part.x, at.z - part.z).length() < KNOCK_RADIUS
			# Standing (feet below the part, head above it), not riding past outside.
			var level := at.y < part.y + 0.3 and at.y > part.y - 1.6
			var moved := at - was
			moved.y = 0.0
			if near and level and moved.length() > 0.0005 and moved.length() < 1.0:
				var speed := moved.length() / delta
				push(moved * KNOCK_GAIN * clampf(speed / 2.0, 0.5, 2.0))
	for key in _last.keys():
		if not seen.has(key):
			_last.erase(key)


func _physics_process(delta: float) -> void:
	_knocks(delta)
	if _angle.length_squared() < 1e-7 and _rate.length_squared() < 1e-7:
		return
	var acc := -GRAVITY / length * Vector2(sin(_angle.x), sin(_angle.y)) - damping * _rate
	_rate += acc * delta
	_angle += _rate * delta
	_angle = _angle.clamp(-Vector2.ONE * MAX_ANGLE, Vector2.ONE * MAX_ANGLE)
	if _angle.length() < 0.0005 and _rate.length() < 0.002:
		_angle = Vector2.ZERO
		_rate = Vector2.ZERO
	rotation = Vector3(_angle.x, 0.0, _angle.y)
