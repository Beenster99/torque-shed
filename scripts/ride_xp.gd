class_name RideXP
extends RefCounted
## Riding XP, worked out on the rider's own machine as they ride (the bike only exists there):
## jumps, wheelies, stoppies, burnouts, knee-down corners, distance, speed records and 0-100
## times. Every event goes through Progress.rider_event, so the host pays it like any other XP.
## Personal bests and the running distance are kept in the rider's own profile.

const MIN_AIR := 0.5          # seconds in the air before it counts as a jump
const LANDING_JUDGE := 0.6    # seconds after touchdown a crash still spoils the jump
const MIN_WHEELIE := 10.0     # metres
const MIN_STOPPIE := 5.0
const KNEE_LEAN := deg_to_rad(40.0)
const SPEED_BANDS := [50, 80, 100, 130, 160, 200, 240, 280, 320]   # km/h, each pays once ever
const SPRINT_BANDS := [8.0, 6.0, 5.0, 4.0, 3.5, 3.0]               # 0-100 km/h, seconds

var bike_id := 0
## Where events go: Progress.rider_event unless a test catches them.
var sink := Callable()

var _air := 0.0
var _landing := -1.0
var _land_air := 0.0
var _land_clean := true
var _wheelie := 0.0
var _stoppie := 0.0
var _burn := 0.0
var _km := 0.0
var _km_note := 0.0
var _lean_t := 0.0
var _sprint_t := -1.0


func _init(bike := 0) -> void:
	bike_id = bike


func _emit(action: String, mult := 1.0, detail := "") -> void:
	if sink.is_valid():
		sink.call(action, mult, detail)
	else:
		Progress.rider_event(action, mult, detail)


## The engine fired: the first time a bike ever starts pays once (the host checks it's the first).
func engine_started() -> void:
	if bike_id != 0:
		_emit("first_start", 1.0, "bike:%d" % bike_id)


## One physics step of riding.
func step(b: Bike, delta: float) -> void:
	var front: bool = b.wheels[0]["contact"]
	var rear: bool = b.wheels[1]["contact"]
	var v := absf(b.speed)
	if b.is_crashed or b.freeze:
		# A crash spoils whatever trick was under way (and a bike held still, as on a ferry's deck, does no tricks).
		_air = 0.0
		_landing = -1.0
		_wheelie = 0.0
		_stoppie = 0.0
		_lean_t = 0.0
		_sprint_t = -1.0
		return
	_jumps(b, front, rear, delta)
	_one_wheel(b, front, rear, v, delta)
	_burnout(b, delta)
	_knee_down(b, front, rear, v, delta)
	_distance(front or rear, v, delta)
	_speed(front, rear, v, delta)


func _jumps(b: Bike, front: bool, rear: bool, delta: float) -> void:
	if not front and not rear:
		_air += delta
	else:
		if _air >= MIN_AIR and _landing < 0.0:
			_landing = 0.0
			_land_air = _air
			# Clean: upright and not nose-planted or looped when the wheels touch.
			_land_clean = absf(b.lean_angle) < deg_to_rad(20.0) and absf(b.pitch_angle) < deg_to_rad(25.0)
		_air = 0.0
	if _landing >= 0.0:
		_landing += delta
		if _landing >= LANDING_JUDGE:
			_landing = -1.0
			landed(_land_air, _land_clean)


## A jump landed and ridden away from: more for longer, half again for a clean landing.
func landed(air: float, clean: bool) -> void:
	_emit("jump", pow(air / MIN_AIR, 1.1) * (1.5 if clean else 1.0))
	if air > Progress.record("air"):
		var was := Progress.record("air")
		Progress.set_record("air", snappedf(air, 0.01))
		if air >= 0.8 and was > 0.0:
			_emit("jump_record", 1.0 + air)


func _one_wheel(b: Bike, front: bool, rear: bool, v: float, delta: float) -> void:
	if rear and not front and b.pitch_angle > deg_to_rad(8.0) and v > 3.0:
		_wheelie += v * delta
	elif _wheelie > 0.0:
		wheelie_done(_wheelie)
		_wheelie = 0.0
	if front and not rear and b.pitch_angle < -deg_to_rad(5.0) and v > 1.5:
		_stoppie += v * delta
	elif _stoppie > 0.0:
		stoppie_done(_stoppie)
		_stoppie = 0.0


func wheelie_done(metres: float) -> void:
	if metres < MIN_WHEELIE:
		return
	_emit("wheelie", metres / MIN_WHEELIE)
	var best := Progress.record("wheelie")
	if metres > best:
		Progress.set_record("wheelie", roundf(metres))
		if best > 0.0 and metres >= 30.0:
			_emit("wheelie_record", metres / 30.0)


func stoppie_done(metres: float) -> void:
	if metres < MIN_STOPPIE:
		return
	_emit("stoppie", metres / MIN_STOPPIE)
	var best := Progress.record("stoppie")
	if metres > best:
		Progress.set_record("stoppie", roundf(metres))
		if best > 0.0 and metres >= 10.0:
			_emit("stoppie_record", metres / 10.0)


func _burnout(b: Bike, delta: float) -> void:
	if b.burnout > 0.4:
		_burn += delta
		if _burn >= 2.0:
			_burn -= 2.0
			_emit("burnout")
	else:
		_burn = maxf(0.0, _burn - delta)


func _knee_down(b: Bike, front: bool, rear: bool, v: float, delta: float) -> void:
	if front and rear and v > 12.0 and absf(b.lean_angle) > KNEE_LEAN:
		if _lean_t >= 0.0:
			_lean_t += delta
			if _lean_t >= 1.5:
				_emit("knee_down")
				_lean_t = -1.0   # once per corner: stand it up to earn another
	elif absf(b.lean_angle) < deg_to_rad(25.0):
		_lean_t = 0.0


func _distance(on_ground: bool, v: float, delta: float) -> void:
	if not on_ground:
		return
	var km := v * delta / 1000.0
	_km += km
	_km_note += km
	if _km_note >= 0.1:
		Progress.set_record("km", snappedf(Progress.record("km") + _km_note, 0.01))
		_km_note = 0.0
	if _km >= 1.0:
		_km -= 1.0
		_emit("distance")


func _speed(front: bool, rear: bool, v: float, delta: float) -> void:
	var kmh := v * 3.6
	if kmh > Progress.record("kmh") + 1.0:
		Progress.set_record("kmh", roundf(kmh))
	var bands := Progress.speed_bands()
	for band in SPEED_BANDS:
		if kmh >= band and not bands.has(band):
			Progress.add_speed_band(band)
			_emit("top_speed", band / 50.0)
	# 0-100: armed when stopped on both wheels, timed until 100 km/h.
	if kmh < 2.0 and front and rear:
		_sprint_t = 0.0
	elif _sprint_t >= 0.0:
		_sprint_t += delta
		if kmh >= 100.0:
			sprint_done(_sprint_t)
			_sprint_t = -1.0
		elif _sprint_t > 30.0:
			_sprint_t = -1.0


## A standing start to 100 km/h in `t` seconds: pays for every time band newly beaten.
func sprint_done(t: float) -> void:
	var best := Progress.record("sprint")
	if best > 0.0 and t >= best:
		return
	Progress.set_record("sprint", snappedf(t, 0.01))
	var top := -1
	for i in SPRINT_BANDS.size():
		var band: float = SPRINT_BANDS[i]
		if t <= band and (best <= 0.0 or best > band):
			top = i
	if top >= 0:
		_emit("sprint", 1.0 + 0.5 * top)
