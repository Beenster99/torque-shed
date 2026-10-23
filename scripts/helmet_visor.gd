class_name HelmetVisor
extends Node3D
## A helmet's visor (or goggles) on its pivot (see HelmetModel): it flicks up or down with a
## short swing whenever its rider's visor changes (RiderGear.visor_up), so everyone sees it.
## It turns `angle` radians up about its pivot, front edge first, moving `lift` (helmet units)
## as it goes; goggles lift off the face onto the shell. Put it in place with place(), not by
## setting its position: the swing works from there.

## How long a flick takes, in seconds.
const TIME := 0.25

## Whose visor this is: it follows RiderGear.visor_up(peer). -1 (a preview) holds `up` as set.
var peer := -1
## Whether it is up (or going up).
var up := false:
	set(v):
		up = v
		if not is_inside_tree():
			amount = 1.0 if v else 0.0   # built as it is, no swing
			_pose()
var angle := 0.75:
	set(v):
		angle = v
		_pose()
var lift := Vector3.ZERO:
	set(v):
		lift = v
		_pose()
## How far up it is: 0 down, 1 up.
var amount := 0.0
var _rest := Vector3.ZERO


## Puts the pivot at `at` in the helmet.
func place(at: Vector3) -> void:
	_rest = at
	_pose()


func _ready() -> void:
	if peer >= 0:
		up = RiderGear.visor_up(peer)
		amount = 1.0 if up else 0.0   # as it is when it appears, no swing
		_pose()


func _process(delta: float) -> void:
	if peer >= 0:
		up = RiderGear.visor_up(peer)
	var target := 1.0 if up else 0.0
	if amount == target:
		return
	amount = move_toward(amount, target, delta / TIME)
	_pose()


## Whether it has finished moving.
func settled() -> bool:
	return amount == (1.0 if up else 0.0)


func _pose() -> void:
	var k := smoothstep(0.0, 1.0, clampf(amount, 0.0, 1.0))
	rotation.x = angle * k
	position = _rest + lift * k
