class_name Emotes
extends RefCounted
## Character emotes: wave, thumbs up, point, shrug, cheer and dance. On foot, B opens the emote
## bar (then 1 to 6 picks one) or F5 to F10 do them straight away. The host sends each one to
## the crew (Shed.emoted) and the other players see your figure do it (RemotePlayer). A ping
## makes your figure point at what you pinged, too.
##
## On a bike there are two more (RIDING): a nod to a biker you pass, and a wave with the left
## hand off the bar (hold the nod button). They go round the crew the same way, and the rider on
## your bike does them on everyone's screen (BikeModel.gesture).
##
## A pose is where each arm points, from its shoulder, in the figure's own space (it faces -Z,
## +X is its right): see pose().

const LIST: Array[String] = ["wave", "thumbs", "point", "shrug", "cheer", "dance"]
## The ones a rider does on the bike.
const RIDING: Array[String] = ["nod", "ride_wave"]
const NAMES := {"wave": "Wave", "thumbs": "Thumbs up", "point": "Point", "shrug": "Shrug", "cheer": "Cheer", "dance": "Dance",
	"nod": "Nod", "ride_wave": "Wave"}
## How it reads in the HUD: "Simon waves", "You wave".
const VERBS := {"wave": "waves", "thumbs": "gives a thumbs up", "point": "points", "shrug": "shrugs", "cheer": "cheers", "dance": "dances",
	"nod": "nods", "ride_wave": "waves"}
const YOU := {"wave": "You wave", "thumbs": "Thumbs up", "point": "You point", "shrug": "You shrug", "cheer": "You cheer", "dance": "You dance",
	"nod": "You nod", "ride_wave": "You wave"}
## How long each one plays, in seconds.
const LENGTH := {"wave": 2.4, "thumbs": 2.0, "point": 2.6, "shrug": 1.8, "cheer": 2.4, "dance": 4.0, "nod": 0.7, "ride_wave": 2.0}
## The time it takes to swing into a pose and back out of it.
const BLEND := 0.25


static func is_emote(e: String) -> bool:
	return LIST.has(e) or RIDING.has(e)


## Whether it's one a rider does on the bike (see RIDING).
static func is_riding(e: String) -> bool:
	return RIDING.has(e)


## The input action that does an emote straight away ("emote_wave").
static func action_of(e: String) -> String:
	return "emote_" + e


## How far into its pose the figure is `t` seconds into emote `e`: 0 at rest, 1 in the pose.
static func weight(e: String, t: float) -> float:
	var length := float(LENGTH.get(e, 2.0))
	if t < 0.0 or t >= length:
		return 0.0
	return clampf(minf(t, length - t) / BLEND, 0.0, 1.0)


## The rest direction of an arm, shoulder to wrist (see RiderFigure.ARM_R and ARM_L).
static func rest_dir(right: bool) -> Vector3:
	var arm: Dictionary = RiderFigure.ARM_R if right else RiderFigure.ARM_L
	return ((arm["wrist"] as Vector3) - (arm["shoulder"] as Vector3)).normalized()


## The pose `t` seconds into emote `e`: {r, l: where each arm points from its shoulder (unit
## vectors, or Vector3.ZERO to leave it at rest), bob: the body's rise in metres, twist: its turn
## in radians, nod and tilt: the head's}. `aim` is the point a point is aimed at, in the
## figure's space (Vector3.ZERO for straight ahead).
static func pose(e: String, t: float, aim := Vector3.ZERO) -> Dictionary:
	var p := {"r": Vector3.ZERO, "l": Vector3.ZERO, "bob": 0.0, "twist": 0.0, "nod": 0.0, "tilt": 0.0}
	match e:
		"wave":
			# Right hand up by the head, swinging side to side.
			p["r"] = Vector3(0.45 + 0.32 * sin(t * 9.0), 0.88, -0.18).normalized()
			p["tilt"] = 0.08
		"thumbs":
			# Right arm out in front, a little up.
			p["r"] = Vector3(0.12, 0.3 + 0.05 * sin(t * 4.0), -1.0).normalized()
			p["nod"] = -0.1 * sin(clampf(t * 3.0, 0.0, PI))
		"point":
			# With the arm on the side it's on, so it doesn't point through the body.
			if aim.length() < 0.01:
				p["r"] = Vector3(0.05, 0.05, -1.0).normalized()
			elif aim.x < 0.0:
				p["l"] = (aim - (RiderFigure.ARM_L["shoulder"] as Vector3)).normalized()
			else:
				p["r"] = (aim - (RiderFigure.ARM_R["shoulder"] as Vector3)).normalized()
		"shrug":
			# Both arms out to the sides, palms up, and the shoulders lifting.
			p["r"] = Vector3(0.75, -0.35, -0.55).normalized()
			p["l"] = Vector3(-0.75, -0.35, -0.55).normalized()
			p["bob"] = 0.03 * sin(clampf(t / float(LENGTH["shrug"]), 0.0, 1.0) * PI)
			p["tilt"] = 0.15
		"cheer":
			# Both arms up, pumping.
			var pump := 0.25 * sin(t * 10.0)
			p["r"] = Vector3(0.28, 1.0, -0.1 + pump).normalized()
			p["l"] = Vector3(-0.28, 1.0, -0.1 + pump).normalized()
			p["bob"] = 0.05 * absf(sin(t * 10.0))
			p["nod"] = 0.15
		"dance":
			# Arms swinging up and down in turn, the body bouncing and turning to the beat.
			var beat := t * 7.0
			p["r"] = Vector3(0.6, sin(beat), -0.5).normalized()
			p["l"] = Vector3(-0.6, -sin(beat), -0.5).normalized()
			p["bob"] = 0.06 * absf(sin(beat))
			p["twist"] = 0.35 * sin(beat * 0.5)
			p["tilt"] = 0.12 * sin(beat)
	return p


## The turn that swings an arm from rest to point along `dir` (in the figure's space).
static func arm_turn(right: bool, dir: Vector3) -> Quaternion:
	if dir.length() < 0.01:
		return Quaternion.IDENTITY
	var from := rest_dir(right)
	var to := dir.normalized()
	if from.dot(to) < -0.999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(from, to)


## A rider's gesture on the bike `t` seconds in (see RIDING): {nod: the head's dip forward (rad),
## arm: where the left arm points from its shoulder in the bike's space (Vector3.ZERO to keep
## the hand on the bar), w: how far into it, 0..1}.
static func riding_pose(e: String, t: float) -> Dictionary:
	var p := {"nod": 0.0, "arm": Vector3.ZERO, "w": weight(e, t)}
	match e:
		"nod":
			# One dip of the head and back up.
			p["nod"] = 0.32 * sin(clampf(t / float(LENGTH["nod"]), 0.0, 1.0) * PI)
		"ride_wave":
			# The left hand up off the bar and out to the side, the palm swinging a little.
			p["arm"] = Vector3(-0.75, 0.5 + 0.12 * sin(t * 8.0), -0.4).normalized()
			p["nod"] = 0.08 * float(p["w"])
	return p
