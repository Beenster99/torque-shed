class_name PlugGame
extends TyreGame
## Plugging a puncture is a little skill game, run like the tyre changer's (see TyreGame: the work
## button held, the mouse or right stick moving the tool). The tread is laid out as a strip:
##   find  sweep the soapy spray along it; the nearer the nozzle is to the hole, the more it
##         foams. Hold the nozzle over the hole a moment and you've found it.
##   plug  the reamer and the plug go in while the tyre creeps on its stand: keep the tool over
##         the hole as it drifts. How steadily you held it is how well the plug seals.
## Never found it before the soap ran out: quality() is 0, and no plug is used.

const FIND_TIME := 9.0        # seconds of soapy spray to find the hole with
const LOCK_TIME := 0.6        # held this long over the hole, it's found
const PLUG_TIME := 3.0        # seconds the plug takes to push in
const HOLE_SIZE := 0.07       # how close (strip half-widths) counts as over the hole
const FOAM_SPREAD := 0.14     # how far from the hole the bubbles still show
const DRIFT := 0.22           # how far the hole wanders while the plug goes in
const PLUG_TOLERANCE := 0.12  # off the hole by this much, that moment scores nothing

var hole := 0.0               # where the hole is along the strip, -1..1
var found := false
var _lock := 0.0
var _plug_t := 0.0
var _plug_score := 0.0
var _drift_phase := 0.0


func _init(seed_value := 0) -> void:
	super()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	hole = rng.randf_range(-0.8, 0.8)
	_drift_phase = rng.randf() * TAU
	cursor = Vector2(-0.95 if hole > 0.0 else 0.95, 0.0)


## Where the hole is right now: still while you hunt for it, creeping once the plug's going in.
func hole_now() -> float:
	if not found:
		return hole
	return clampf(hole + DRIFT * sin(_drift_phase + _plug_t * 1.7) * minf(_plug_t, 1.0), -1.0, 1.0)


## Mouse movement slides the nozzle (or the reamer) along the tread.
func move(relative: Vector2) -> void:
	cursor.x = clampf(cursor.x + relative.x * MOUSE_SCALE * 0.6, -1.0, 1.0)


## A pad's stick pushes it along.
func aim(stick: Vector2) -> void:
	if absf(stick.x) > 0.2:
		cursor.x = clampf(cursor.x + stick.x * 0.02, -1.0, 1.0)


## How much the soap foams where the nozzle is, 0..1: thick bubbles right over the hole.
func foam() -> float:
	var d := absf(cursor.x - hole_now())
	return exp(-d * d / (FOAM_SPREAD * FOAM_SPREAD))


## How well the tool is on the hole right now, 0..1.
func on_target() -> float:
	return clampf(1.0 - absf(cursor.x - hole_now()) / PLUG_TOLERANCE, 0.0, 1.0)


func step(delta: float) -> bool:
	if done():
		return true
	t += delta
	if not found:
		if absf(cursor.x - hole) < HOLE_SIZE:
			_lock += delta
			if _lock >= LOCK_TIME:
				found = true
		else:
			_lock = maxf(0.0, _lock - delta * 0.5)
	else:
		_plug_t += delta
		_plug_score += on_target() * delta
	return done()


## The share of finding it held over the hole so far, 0..1 (for the HUD).
func lock_progress() -> float:
	return 1.0 if found else clampf(_lock / LOCK_TIME, 0.0, 1.0)


func plug_progress() -> float:
	return clampf(_plug_t / PLUG_TIME, 0.0, 1.0)


func done() -> bool:
	return (not found and t >= FIND_TIME) or _plug_t >= PLUG_TIME


func progress() -> float:
	if found:
		return 0.5 + 0.5 * plug_progress()
	return 0.5 * clampf(t / FIND_TIME, 0.0, 1.0)


## How well the plug went in: 0 if the hole was never found, else how steadily the reamer was
## kept on it (with a little slack, so a good job seals fully).
func quality() -> float:
	if not found:
		return 0.0
	if _plug_t <= 0.0:
		return 0.0
	return clampf(_plug_score / _plug_t * 1.15, 0.05, 1.0)


## How long the whole job can take, seconds (for the hold's timer).
static func duration() -> float:
	return FIND_TIME + PLUG_TIME
