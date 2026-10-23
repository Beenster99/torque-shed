class_name RiderStyle
extends RefCounted
## How a rider sits on the bike and moves on it through a corner: their riding style, picked on
## the Profile tab and kept with their gear (RiderGear's worn set carries it as "style", so it's
## saved in their profile and everyone in the shed sees it). Purely for looks: the riding is
## the same whichever style you ride in.
##
## BikeModel builds the rider's body in the style (how far forward the back is, how far out the
## elbows go) and poses it every frame from the bike's lean, steering, speed and braking
## (BikeModel.update_rider), using the numbers here:
## - "situp", Sit-up adventure: a straight back, tall in the saddle, neutral through corners.
## - "scratcher", Knee-down scratcher: tucked in, hangs off into corners, and the inside knee
##   drops lower the further over the bike goes, down onto the road (sparks off the slider).
## - "naked", Elbows-out naked: leant forward over the tank, elbows out, a bit of knee out.
## - "rossi", Rossi leg out: braking hard into a corner the inside leg comes off the peg and
##   dangles forward and out, and goes back on as the brakes come off and the bike leans in.
## On a cruiser or chopper (feet forward, wide bars) every style sits up more and hangs off less.
##
## Also here: where the rider looks through a corner (look_yaw), into the inside and towards
## the exit, which Settings.look_into_corner turns off.

const STYLES: Array[String] = ["situp", "scratcher", "naked", "rossi"]
## The style a rider rides in until they pick one (and the plain rider with no gear chosen).
const DEFAULT := "situp"

## Per style: its name and a line about it; `torso` from the hips to the shoulders (m, the
## rider's space: -z is forward); how far the elbows go out (m); and through a corner at full
## lean, `hang` (m the body moves to the inside), `roll` (rad the body tips in past the bike),
## `knee` (rad the inside knee swings out and down about the line from hip to foot) and
## `lean_in` (how much of the old lean-input shift the body keeps); `leg_out`, whether the
## inside leg comes off the peg under hard braking.
const INFO := {
	"situp": {"name": "Sit-up adventure", "desc": "Straight back, tall in the saddle, and neutral through the corners.",
		"torso": Vector3(0.0, 0.57, -0.13), "elbow_out": 0.05, "hang": 0.0, "roll": 0.0, "knee": 0.04, "lean_in": 0.3, "leg_out": false},
	"scratcher": {"name": "Knee-down scratcher", "desc": "Tucked in and hanging off: the further over you go, the lower the inside knee, till the slider's on the road throwing sparks.",
		"torso": Vector3(0.0, 0.42, -0.4), "elbow_out": 0.11, "hang": 0.15, "roll": 0.24, "knee": 1.25, "lean_in": 1.0, "leg_out": false},
	"naked": {"name": "Elbows-out naked", "desc": "Leant forward over the tank with the elbows out, and a bit of knee out in the corners.",
		"torso": Vector3(0.0, 0.45, -0.37), "elbow_out": 0.19, "hang": 0.05, "roll": 0.08, "knee": 0.5, "lean_in": 1.0, "leg_out": false},
	"rossi": {"name": "Rossi leg out", "desc": "Braking hard into a corner, the inside leg comes off the peg and dangles forward and out; it goes back on as the bike leans in.",
		"torso": Vector3(0.0, 0.45, -0.35), "elbow_out": 0.1, "hang": 0.09, "roll": 0.12, "knee": 0.65, "lean_in": 1.0, "leg_out": true},
}

## Cruiser and chopper seating (feet forward): every style's back comes most of the way up to
## this, and the hanging off, knee and leg out are cut down to these shares.
const LAID_BACK_TORSO := Vector3(0.0, 0.56, -0.05)
const LAID_BACK := {"torso": 0.75, "hang": 0.3, "roll": 0.35, "knee": 0.35, "leg_out": 0.45}

## The lean (rad) at which a style's corner pose is all the way in.
const FULL_LEAN := 0.8
## Looking into the corner: the head turns up to LOOK_MAX (rad) into the inside, and the
## shoulders SHOULDER_SHARE of that; it eases there over LOOK_TIME seconds.
const LOOK_MAX := 0.5
const SHOULDER_SHARE := 0.3
const LOOK_TIME := 0.35
## How long the body takes to move over for a corner, and the leg to come out and go back.
const BODY_TIME := 0.3
const LEG_OUT_TIME := 0.25
const LEG_BACK_TIME := 0.45


## `id` if it's a style, else the default.
static func clean(id) -> String:
	return str(id) if STYLES.has(str(id)) else DEFAULT


static func style_name(id: String) -> String:
	return str(INFO[clean(id)]["name"])


## A style's numbers, cut down for cruiser and chopper seating when `laid_back`.
static func numbers(id: String, laid_back := false) -> Dictionary:
	var n: Dictionary = (INFO[clean(id)] as Dictionary).duplicate()
	n["leg_out"] = 1.0 if n["leg_out"] else 0.0
	if laid_back:
		n["torso"] = (n["torso"] as Vector3).lerp(LAID_BACK_TORSO, float(LAID_BACK["torso"]))
		for k in ["hang", "roll", "knee", "leg_out"]:
			n[k] = float(n[k]) * float(LAID_BACK[k])
	return n


## How far into its corner pose the rider is, 0..1: from the lean, and only once the bike's
## going (a lean at walking pace is balancing, not cornering).
static func corner_amount(lean: float, speed: float) -> float:
	var over := clampf((absf(lean) - 0.05) / (FULL_LEAN - 0.05), 0.0, 1.0)
	return pow(over, 1.2) * smoothstep(3.0, 10.0, absf(speed))


## Where a style wants the body: {hang (m, + to the right), roll (rad, + tipped to the right),
## knee (rad the inside knee goes out), side (+1 a right-hander, -1 a left)}.
static func body_target(id: String, lean: float, speed: float, laid_back := false) -> Dictionary:
	var n := numbers(id, laid_back)
	var c := corner_amount(lean, speed)
	var side := 1.0 if lean >= 0.0 else -1.0
	return {"hang": side * float(n["hang"]) * c, "roll": side * float(n["roll"]) * c, "knee": float(n["knee"]) * c, "side": side}


## How far the Rossi leg wants to be out, 0..1: braking hard (`brake` 0..1) at speed, before
## the bike's leaned in; it comes back on the peg as the braking eases or the lean comes in.
static func leg_out_target(id: String, lean: float, speed: float, brake: float, laid_back := false) -> float:
	var n := numbers(id, laid_back)
	if float(n["leg_out"]) <= 0.0:
		return 0.0
	var hard := smoothstep(0.3, 0.75, brake) * smoothstep(7.0, 14.0, absf(speed))
	var upright := 1.0 - smoothstep(0.3, 0.6, absf(lean) / FULL_LEAN)
	return hard * upright * float(n["leg_out"])


## Where the rider looks through a corner (rad, + to the left like Basis(Vector3.UP, yaw)):
## into the inside of the turn and on to the exit. Mostly from the lean, which leads a turn and
## doesn't flick about; at low speed, where the bike turns on its bars more than its lean, from
## the steering too. Small leans and wobbles are left alone so the head doesn't twitch.
static func look_yaw(lean: float, steer: float, speed: float) -> float:
	var v := absf(speed)
	var from_lean := signf(lean) * clampf((absf(lean) - 0.07) / 0.55, 0.0, 1.0) * smoothstep(3.0, 12.0, v)
	var from_bars := signf(steer) * clampf((absf(steer) - 0.04) / 0.35, 0.0, 1.0) * smoothstep(0.8, 3.0, v) * (1.0 - smoothstep(4.0, 9.0, v))
	return -LOOK_MAX * clampf(from_lean + from_bars * 0.7, -1.0, 1.0)


## How far a bike with basis `b` is leaned over (rad, + to the right), the way Bike measures
## its own lean: for a bike seen only from its snapshots (see RemoteBike).
static func lean_of(b: Basis) -> float:
	var fwd := -b.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.01:
		flat = Vector3(b.y.x, 0.0, b.y.z)
	if flat.length() < 0.0001:
		return 0.0
	var right := flat.normalized().cross(Vector3.UP)
	return atan2(b.y.dot(right), b.y.dot(Vector3.UP))


## How hard a bike seen only from its snapshots is braking, 0..1: from how fast it's slowing
## (`decel`, m/s/s), the stop lamp saying it's the brakes and not just rolling off.
static func brake_from(decel: float, stop_lamp: bool) -> float:
	return clampf(decel / 7.0, 0.0, 1.0) * (1.0 if stop_lamp else 0.5)


## A step of easing `now` towards `want` over about `time` seconds.
static func ease_to(now: float, want: float, time: float, delta: float) -> float:
	return lerpf(now, want, 1.0 - exp(-delta / maxf(time, 0.001)))
