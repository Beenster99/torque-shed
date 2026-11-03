class_name BikePusher
extends Node3D
## Someone wheeling their bike along on foot at the roadside (Roadside, bikes[id]["push"]): their
## figure in their own gear, walking beside it on its left with a hand on the left grip, legs
## stepping with the bike's speed. Your own is one of these, put by
## the ridden bike (main); a mate's is their walking figure posed the same way (RemotePlayer), so
## the whole crew sees who's pushing.

## Where the figure stands from the left grip, in the bike's flat frame: out to the side, and a
## little behind the bars (m).
const SIDE := 0.45
const BEHIND := 0.25
## How far the figure's arm reaches, shoulder to the middle of the hand (m), and how much it may
## be let out or in to reach the grip on a taller or lower bike.
const ARM_REACH := 0.56
const REACH_GIVE := Vector2(0.85, 1.2)

var _body: Node3D
var _phase := 0.0
var _sig := ""


## A pusher in `gear` (slot -> RiderGear item id) and the player's colour `tint`.
static func make(gear: Dictionary, tint: Color) -> BikePusher:
	var p := BikePusher.new()
	p.name = "Pusher"
	p.top_level = true
	p.dress(gear, tint)
	return p


## Dresses the figure again (their gear changed).
func dress(gear: Dictionary, tint: Color) -> void:
	var sig := RiderGear.sig(gear) + str(tint)
	if sig == _sig and _body != null:
		return
	_sig = sig
	if _body:
		_body.free()
	_body = RiderFigure.make(gear, tint)
	add_child(_body)


## The figure's frame beside `model` (the pushed bike's): feet on the ground, facing the way the
## bike points, by its left grip. `rear_radius` puts the ground under the model's origin.
static func stand_xf(model: BikeModel, rear_radius: float) -> Transform3D:
	var flat := bars_frame(model)
	var at := model.grip_point(-1.0) + flat * Vector3(-SIDE, 0.0, BEHIND)
	at.y = (model.global_transform * Vector3(0.0, -rear_radius, 0.0)).y
	return Transform3D(flat, at)


## The bike's flat frame from its bars: -z the way they face, x to the right grip, y up.
static func bars_frame(model: BikeModel) -> Basis:
	var left := model.grip_point(-1.0) - model.grip_point(1.0)
	left.y = 0.0
	if left.length() < 0.01:
		left = -model.global_transform.basis.x
	var fwd := left.normalized().cross(Vector3.UP)
	return Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))


## Puts the figure's near hand (`body`'s "ArmR", see RiderFigure.standing: stood on the bike's
## left, its right side is to the bike) on the bike's left grip, however the bars turn, the arm
## let out or in a touch to reach it; the far arm hangs by their side.
static func hold_bars(body: Node3D, model: BikeModel) -> void:
	var arm := body.get_node_or_null("ArmR") as Node3D
	if arm == null:
		return
	var aim: Vector3 = body.global_transform.affine_inverse() * model.grip_point(-1.0) - arm.position
	arm.quaternion = Emotes.arm_turn(true, aim)
	arm.scale = Vector3.ONE * clampf(aim.length() / ARM_REACH, REACH_GIVE.x, REACH_GIVE.y)


## Lets go: the arms back to how they hang.
static func let_go(body: Node3D) -> void:
	for arm_name in ["ArmL", "ArmR"]:
		var arm := body.get_node_or_null(arm_name) as Node3D
		if arm:
			arm.quaternion = Quaternion.IDENTITY
			arm.scale = Vector3.ONE


## Walks it along beside `model` at `speed` m/s for `delta` seconds.
func follow(model: BikeModel, rear_radius: float, speed: float, delta: float) -> void:
	if model == null or not is_instance_valid(model) or _body == null:
		return
	global_transform = stand_xf(model, rear_radius)
	_phase = RemotePlayer.step_walk(_body, _phase, absf(speed), delta, self)
	hold_bars(_body, model)
