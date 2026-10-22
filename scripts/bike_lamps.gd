class_name BikeLamps
extends RefCounted
## A bike's stop lamp and indicators: which side is indicating, the flash, and the self-cancel.
## The ridden bike (Bike) and other players' bikes (RemoteBike, from their snapshots) each keep
## one and show it on their BikeModel with set_signals.
##
## Press a side to start it flashing, the same side again to cancel, the other side to switch.
## Like real self-cancelling indicators they go off by themselves once the turn is done: the
## bike has leant (or, slowly round a junction, turned) that way and come back upright.

## Flashes a second (on and off once each), as real ones do (1 to 2 Hz).
const FLASH_HZ := 1.5
## A brake pulled this far (0..1) lights the stop lamp.
const BRAKE_ON := 0.05
## Leant this far the way it's indicating (radians, about 12 degrees), the turn has begun.
const TURN_LEAN := 0.21
## Or turned this far that way (radians, about 35 degrees): a slow turn round a junction.
const TURN_YAW := 0.6
## Back under this lean (about 5 degrees) and barely turning (rad/s), the turn is over.
const UPRIGHT_LEAN := 0.09
const STRAIGHT_RATE := 0.2

var side := 0            # -1 indicating left, 1 right, 0 off
var braking := false     # the stop lamp is lit
var flash_t := 0.0       # seconds since this side started flashing
var _turning := false    # the bike has made a start on the turn it's indicating for
var _turned := 0.0       # how far it has turned that way since (radians)


## Presses one side's switch (-1 left, 1 right): starts it, or cancels it if it's on already.
func press(which: int) -> void:
	set_side(0 if side == which else which)


## Indicates `which` way (-1, 0 off, 1), from the start of a flash.
func set_side(which: int) -> void:
	which = signi(which)
	if which == side:
		return
	side = which
	flash_t = 0.0
	_turning = false
	_turned = 0.0


## Whether the indicators flashing now are in the lit half of the flash (they light at once).
func lit() -> bool:
	return side != 0 and fmod(flash_t * FLASH_HZ, 1.0) < 0.5


func left_lit() -> bool:
	return side < 0 and lit()


func right_lit() -> bool:
	return side > 0 and lit()


## Moves the flash on by `delta` and watches for the turn: `lean` (radians, + to the right) and
## `turn_rate` (rad/s, + turning right). Returns 1 when a flash came on (the relay's tick), -1
## when one went off (its tock), else 0.
func step(delta: float, lean: float, turn_rate: float) -> int:
	if side == 0:
		return 0
	var was := lit()
	flash_t += delta
	var heard := 0
	if lit() != was:
		heard = 1 if lit() else -1
	_turned += turn_rate * delta * side
	if not _turning:
		_turning = lean * side > TURN_LEAN or _turned > TURN_YAW
	elif absf(lean) < UPRIGHT_LEAN and absf(turn_rate) < STRAIGHT_RATE:
		set_side(0)   # through the turn and upright again: it cancels itself
		return -1 if was else 0
	return heard


## Sets the stop lamp from the brakes as the bike uses them (0..1 each).
func set_brakes(front: float, rear: float) -> void:
	braking = front > BRAKE_ON or rear > BRAKE_ON


## Takes the stop lamp (0 or 1) and side (-1, 0, 1) from someone's snapshot (Bike.get_net_state).
## The flash runs here from when the side was switched on, so it keeps time without being sent.
func from_net(brake: float, which: float) -> void:
	braking = brake > 0.5
	set_side(roundi(which))


## The relay's tick and tock: two short clicks, the tock a little lower.
static var _clicks := {}


static func click(tick: bool) -> AudioStreamWAV:
	if _clicks.has(tick):
		return _clicks[tick]
	var rate := 22050
	var n := int(rate * 0.035)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if tick else 11
	var pitch := 2400.0 if tick else 1700.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 260.0)
		var v := (sin(TAU * pitch * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	_clicks[tick] = s
	return s
