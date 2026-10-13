class_name Swing
extends Node3D
## A part hanging from a hook: swings like a pendulum when it's knocked or caught by the spray,
## and settles again. The part is a child, hanging below this pivot.

const GRAVITY := 9.8

var length := 0.55          # hook to the part's middle, in metres
var damping := 0.9          # how quickly the swing dies away
var _angle := Vector2.ZERO  # tilt about the pivot's x and z axes, radians
var _rate := Vector2.ZERO


## A shove at the part, in world space (metres per second worth of push).
func push(world_velocity: Vector3) -> void:
	var local := global_transform.basis.inverse() * world_velocity
	# Moving the part along +z tilts it about +x, and along +x about -z.
	_rate += Vector2(local.z, -local.x) / maxf(length, 0.1)


func angle() -> Vector2:
	return _angle


func _physics_process(delta: float) -> void:
	if _angle.length_squared() < 1e-7 and _rate.length_squared() < 1e-7:
		return
	var acc := -GRAVITY / length * Vector2(sin(_angle.x), sin(_angle.y)) - damping * _rate
	_rate += acc * delta
	_angle += _rate * delta
	_angle = _angle.clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
	if _angle.length() < 0.0005 and _rate.length() < 0.002:
		_angle = Vector2.ZERO
		_rate = Vector2.ZERO
	rotation = Vector3(_angle.x, 0.0, _angle.y)
