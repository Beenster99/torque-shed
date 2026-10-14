class_name TyreGame
extends RefCounted
## Fitting a tyre on the tyre changer is a little skill game. The wheel turns on the turntable and
## a marker goes once round the rim; you hold the work button and keep the tyre lever (moved with
## the mouse, or pointed with the right stick) on the marker, out at the rim, as it goes. How
## closely you followed it is how well the bead seats: quality() 0..1.

const DURATION := 5.0        # seconds for the marker to go once round the rim
const GRACE := 0.6           # it waits at the top this long, so you can get the lever on it
const MOUSE_SCALE := 0.006   # cursor travel per pixel of mouse movement (1.0 = the rim)
const TOLERANCE := 0.6       # radians off the marker before that moment scores nothing
const SEGMENTS := 48         # how finely the rim is marked good or bad, for drawing

var t := 0.0
var cursor := Vector2(0.0, -1.0)   # the lever, in rim radii from the hub; screen-style (+y down)
var _score := 0.0
var _time := 0.0
var _seg_score := PackedFloat32Array()
var _seg_time := PackedFloat32Array()


func _init() -> void:
	_seg_score.resize(SEGMENTS)
	_seg_time.resize(SEGMENTS)


## Where the marker is round the rim, radians clockwise from the top.
func marker_angle() -> float:
	return TAU * clampf((t - GRACE) / DURATION, 0.0, 1.0)


## A point on the rim `angle` radians clockwise from the top, screen-style.
static func on_rim(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


func marker() -> Vector2:
	return on_rim(marker_angle())


## Mouse movement nudges the lever.
func move(relative: Vector2) -> void:
	cursor = (cursor + relative * MOUSE_SCALE).limit_length(1.4)


## A pad's stick points the lever round the rim.
func aim(stick: Vector2) -> void:
	if stick.length() > 0.35:
		cursor = cursor.lerp(stick.normalized(), 0.35)


## How well the lever is on the marker right now, 0..1: round the rim and out at its edge.
func on_target() -> float:
	if cursor.length() < 0.05:
		return 0.0
	var err := absf(angle_difference(atan2(cursor.x, -cursor.y), marker_angle()))
	var radial := clampf(1.0 - absf(cursor.length() - 1.0) / 0.6, 0.0, 1.0)
	return clampf(1.0 - err / TOLERANCE, 0.0, 1.0) * radial


## Moves the game on; returns true once the marker has gone all the way round.
func step(delta: float) -> bool:
	t += delta
	if t > GRACE and not done():
		var s := on_target()
		_score += s * delta
		_time += delta
		var seg := clampi(int(marker_angle() / TAU * SEGMENTS), 0, SEGMENTS - 1)
		_seg_score[seg] += s * delta
		_seg_time[seg] += delta
	return done()


func done() -> bool:
	return t >= GRACE + DURATION


func progress() -> float:
	return clampf(t / (GRACE + DURATION), 0.0, 1.0)


## How well the bead went on: the share of the turn you kept the lever on the marker, with a
## little slack so a good, not perfect, job still seats it fully.
func quality() -> float:
	if _time <= 0.0:
		return 0.0
	return clampf(_score / _time * 1.1, 0.0, 1.0)


## How well each stretch of the rim went so far, 0..1, or -1 where the marker hasn't been yet.
func segment(i: int) -> float:
	return _seg_score[i] / _seg_time[i] if _seg_time[i] > 0.0 else -1.0
