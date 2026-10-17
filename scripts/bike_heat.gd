class_name BikeHeat
extends RefCounted
## Heat on the ridden bike: each tyre's tread surface and carcass, each brake's disc and pads,
## and the engine (its coolant, or its cylinder head if it's air-cooled) and oil.
##
## Every temperature is a lump of mass that heat flows into and out of each physics step:
##   tyres   heated by sliding (slip speed times the force it carries) on the tread and by
##           flexing as they roll (the rolling resistance) in the carcass; cooled by the air,
##           more the faster they go, and by the road under them. A wet road cools them hard.
##   brakes  the braking work goes into the disc (and a little into the pads); the disc sheds
##           it to the air, more at speed and, red hot, by glowing.
##   engine  friction and pumping heat grow with the revs, and a share of the power made; a
##           radiator behind a thermostat (and a fan when it's hot) or the fins carry it away,
##           in proportion to the airflow. An air-cooled engine idling hot with no air through
##           its fins keeps climbing. The oil follows the engine more slowly.
## What it does to the bike, each softened by Riding realism (see soften):
##   grip    each tyre compound works in a window: race slicks need real heat, a touring or
##           dual-sport tyre works almost cold, and any tyre goes greasy overcooked. The air in
##           the tyre warms with the carcass, so the pressure rises from the cold setting.
##   brakes  pads bite a little less cold (race carbon a lot less) and fade when overcooked.
##   engine  a cold engine idles fast (on the choke) and makes a little less power until the
##           oil is warm; overheating, it loses power.
## Kept on the rider's own bike only: nothing here is saved or sent over the network.

const KELVIN := 273.15
## The temperature tyre pressures are set at in the shed, °C.
const SET_AT := 20.0
## Each compound's working window: [full grip from °C, greasy above °C, grip share stone cold].
const WINDOWS := {
	"super soft": [70.0, 110.0, 0.55],
	"soft": [35.0, 95.0, 0.8],
	"medium": [15.0, 90.0, 0.9],
	"dual": [10.0, 95.0, 0.92],
	"hard": [10.0, 85.0, 0.9],
}
## An off-road knobbly's soft compound is made to work in the cold mud.
const OFFROAD_SOFT := [15.0, 85.0, 0.9]
const OVERHEAT_SPAN := 45.0     # °C past the window over which an overcooked tyre goes greasy
const OVERHEAT_LOSS := 0.25     # ... losing this much grip
const OFF_ROAD_SHARE := 0.4     # on dirt and grass the compound's temperature matters this much
## Pads by type: [bite fully from °C, bite share cold, fade from °C].
const PADS := {
	"organic": [40.0, 1.0, 250.0],
	"semi-metallic": [80.0, 0.95, 350.0],
	"sintered": [80.0, 0.94, 450.0],
	"ceramic": [120.0, 0.9, 520.0],
	"carbon-ceramic": [250.0, 0.65, 650.0],
}
const FADE_SPAN := 180.0        # °C past the fade point to the worst of the fade
const FADE_LOSS := 0.45         # ... losing this much bite
const DRUM_FADE := 240.0        # a drum's shoes fade early, cooking inside the drum
## How much of the effects Riding realism 1 takes away (0 keeps them whole, realism 0 always does).
const SOFTEN := 0.75
## The engine: liquid-cooled by coolant temperature, air-cooled by head temperature, °C.
const LIQUID := {"warm": 60.0, "hot": 108.0, "loss_from": 112.0, "loss_span": 23.0, "running": 85.0,
	"thermostat": 78.0, "fan_on": 102.0, "fan_off": 96.0}
const AIR := {"warm": 70.0, "hot": 200.0, "loss_from": 210.0, "loss_span": 50.0, "running": 120.0}
const OIL_WARM := 60.0           # °C the oil has to reach for full power
const COLD_POWER := 0.9          # share of the power a stone cold engine makes
const FAST_IDLE := 0.35          # how far over its idle a cold engine runs on the choke

## [front, rear]: {surface, carcass, pressure (bar), grip (0..1+)}.
var tyres: Array = [{}, {}]
var discs := PackedFloat32Array([20.0, 20.0])
var pads := PackedFloat32Array([20.0, 20.0])
var engine := 20.0               # coolant (liquid) or cylinder head (air), °C
var oil := 20.0
var air := 15.0                  # the air around the bike, °C
var road := 15.0                 # the road surface, °C
var liquid := false
var fan := false
## The effects as they are this step (softened): grip and brake bite per wheel, engine power, idle.
var grip := PackedFloat32Array([1.0, 1.0])
var bite := PackedFloat32Array([1.0, 1.0])
var power := 1.0
var idle := 1.0
var soften := 0.0

var _windows: Array = [[], []]
var _tyre_mass := PackedFloat32Array([4.0, 5.0])
var _tread_area := PackedFloat32Array([0.25, 0.3])
var _side_area := PackedFloat32Array([0.2, 0.25])
var _set_psi := PackedFloat32Array([2.3, 2.5])
var _best_psi := PackedFloat32Array([2.3, 2.5])
var _dev_build := PackedFloat32Array([0.0, 0.0])
var _disc_c := PackedFloat32Array([700.0, 600.0])
var _disc_area := PackedFloat32Array([0.06, 0.05])
var _disc_cool := PackedFloat32Array([1.0, 1.0])
var _pad: Array = [[], []]
var _engine_c := 15000.0
var _radiator := 100.0           # W/K the cooling passes at full airflow (or fins at 25 m/s)
var _oil_follow := 1.0
var _head := 1.0                 # how hot the head runs against a stock one
var _displacement := 700.0
var _idle_rpm := 1300.0
var _build: BikeBuild
var _air_timer := 0.0
## Session memory of each shed bike's heat when its rider got off, so getting back on a bike just
## ridden finds it still warm: bike id -> {"heat": BikeHeat, "at": msec}.
static var parked := {}
## Pins the air (and road) temperature, °C, for tests; NAN follows the time of day and weather.
static var fixed_air := NAN


func setup(build: BikeBuild) -> void:
	_build = build
	var sides := ["front", "rear"]
	for i in 2:
		var tyre := build.part(sides[i] + "_tyre")
		_windows[i] = window_of(tyre)
		_tyre_mass[i] = maxf(float(tyre.get("mass", 4.5)), 1.0)
		var r := build.front_radius if i == 0 else build.rear_radius
		var rim := build.front_rim_radius if i == 0 else build.rear_rim_radius
		var w := build.front_tyre_width if i == 0 else build.rear_tyre_width
		_tread_area[i] = TAU * r * w * 1.2
		_side_area[i] = TAU * maxf(r * r - rim * rim, 0.005)
		var key := "psi_f" if i == 0 else "psi_r"
		_set_psi[i] = build.tune_value(key)
		_best_psi[i] = maxf(build.tune_default(key), 0.1)
		_dev_build[i] = build.pressure_offset(sides[i])
		var disc := build.part(sides[i] + "_disc")
		var drum := str(disc.get("style", "")) == "drum"
		var d := float(disc.get("diameter", 280.0)) / 1000.0
		_disc_c[i] = (float(disc.get("mass", 1.0)) + 0.5) * 480.0
		_disc_area[i] = PI * d * 0.06 if drum else TAU * maxf(pow(d * 0.5, 2.0) - pow(d * 0.5 - 0.04, 2.0), 0.01)
		_disc_cool[i] = 0.5 if drum else (1.25 if str(disc.get("style", "")) in ["drilled", "wave", "floating"] else 1.0)
		var pad := build.part(sides[i] + "_pads")
		var p: Array = (PADS.get(str(pad.get("type", "")).to_lower(), PADS["semi-metallic"]) as Array).duplicate()
		if drum:
			p[2] = minf(float(p[2]), DRUM_FADE)
		_pad[i] = p
	var cooling: Dictionary = build.part("cooling") if build.has_part("cooling") else {}
	var kind := str(cooling.get("type", "Air")).to_lower()
	liquid = kind.contains("liquid")
	_displacement = maxf(build.displacement, 30.0)
	_idle_rpm = maxf(build.idle_rpm, 500.0)
	_head = clampf(build.engine_heat / maxf(_displacement / 1000.0, 0.03), 0.5, 2.0)
	var cap := maxf(build.cooling_capacity, 0.2)
	if liquid:
		_engine_c = 6000.0 + 12.0 * _displacement
		_radiator = cap * (60.0 + 0.08 * _displacement)
		_oil_follow = 1.0
	else:
		_engine_c = 1500.0 + 3.0 * _displacement
		_radiator = cap * (10.0 + 0.018 * _displacement)
		_oil_follow = 0.6 if kind.contains("oil") else 0.75
	air = ambient_c()
	road = road_c()
	warm_through()


## A tyre's working window, [full grip from °C, greasy above °C, grip share stone cold], from its
## compound (a catalogue entry can set its own "temp_window" and "cold_grip").
static func window_of(tyre: Dictionary) -> Array:
	var compound := str(tyre.get("compound", "Medium")).to_lower()
	var w: Array = (WINDOWS.get(compound, WINDOWS["medium"]) as Array).duplicate()
	if str(tyre.get("style", "")) == "offroad" and compound == "soft":
		w = OFFROAD_SOFT.duplicate()
	if tyre.has("temp_window"):
		w[0] = float(tyre["temp_window"][0])
		w[1] = float(tyre["temp_window"][1])
	if tyre.has("cold_grip"):
		w[2] = float(tyre["cold_grip"])
	return w


## The temperature a tyre runs at once it's working, °C: well into its window.
func working(i: int) -> float:
	var w: Array = _windows[i]
	return float(w[0]) + 0.75 * (float(w[1]) - float(w[0]))


## Everything at the temperatures a bike settles at being ridden: the tyres working, the brakes
## biting, the engine warm. Where a bike starts when nobody says otherwise (tests, a fresh build).
func warm_through() -> void:
	for i in 2:
		var t := working(i)
		tyres[i] = {"surface": t, "carcass": t, "pressure": 0.0, "grip": 1.0}
		var p: Array = _pad[i]
		var b := minf(maxf(float(p[0]) + 60.0, 70.0), float(p[2]) - 60.0)
		discs[i] = b
		pads[i] = b
	engine = LIQUID["running"] if liquid else AIR["running"]
	oil = air + (engine - air) * _oil_follow
	_update_effects(0.0, 0.5)


## Everything at one temperature, as a bike that has stood a long while (in the shed, overnight).
func soak(t: float) -> void:
	for i in 2:
		tyres[i] = {"surface": t, "carcass": t, "pressure": 0.0, "grip": 1.0}
		discs[i] = t
		pads[i] = t
	engine = t
	oil = t
	fan = false
	_update_effects(0.0, 0.5)


## Lets a parked bike (engine off, standing still) cool for `seconds` in air at `t` °C.
func rest(seconds: float, t: float) -> void:
	air = t
	road = t
	var left := minf(seconds, 3.0 * 3600.0)
	while left > 0.0:
		var dt := minf(left, 2.0)
		_tyre_step(0, dt, 0.0, 0.0, 0.0, false, 0.0)
		_tyre_step(1, dt, 0.0, 0.0, 0.0, false, 0.0)
		_brake_step(0, dt, 0.0, 0.0)
		_brake_step(1, dt, 0.0, 0.0)
		_engine_step(dt, 0.0, 0.0, 0.0, false)
		left -= dt
	if seconds > 3.0 * 3600.0:
		soak(t)
	_update_effects(0.0, 0.5)


func copy_from(other: BikeHeat) -> void:
	for i in 2:
		tyres[i] = (other.tyres[i] as Dictionary).duplicate()
	discs = other.discs.duplicate()
	pads = other.pads.duplicate()
	engine = other.engine
	oil = other.oil
	fan = other.fan


## Called by the bike every physics step, after its wheels have worked out their forces.
func step(bike: Bike, delta: float) -> void:
	_air_timer -= delta
	if _air_timer <= 0.0:
		_air_timer = 1.0
		air = ambient_c()
		road = road_c()
	var v := absf(bike.speed)
	for i in 2:
		var w: Dictionary = bike.wheels[i]
		var on: bool = w["contact"] and not bike.is_crashed
		_tyre_step(i, delta, v, float(w.get("p_slip", 0.0)) if on else 0.0, float(w.get("p_roll", 0.0)) if on else 0.0,
			on, Weather.wetness())
		# The brake's work: its torque against the wheel's spin (a locked wheel heats the tyre instead).
		var omega := absf(float(w["omega"]))
		var p := float(w["brake_torque"]) * omega if omega > 0.5 else 0.0
		_brake_step(i, delta, v, p)
	_engine_step(delta, v, bike.rpm, bike.engine_kw, bike.engine_on)
	_update_effects(bike.assist, delta)


## Air temperature, °C, from the time of day and the weather: an autumn day, about 6° before
## dawn to 18° mid-afternoon under clear skies, a narrower swing under cloud, cooler in rain or fog.
static func ambient_c() -> float:
	if not is_nan(fixed_air):
		return fixed_air
	var h := Daylight.time_of_day()
	var cover := Weather.cover_level()
	var swing := 7.0 * (1.0 - 0.6 * cover)
	return 12.0 + swing * cos((h - 15.0) / 24.0 * TAU) - 3.0 * Weather.rain_level() - 1.5 * Weather.fog_level()


## The road's surface, °C: the air, plus what the sun puts into dry tarmac.
static func road_c() -> float:
	if not is_nan(fixed_air):
		return fixed_air
	var h := Daylight.time_of_day()
	var sun := maxf(cos((h - 13.0) / 24.0 * TAU * 1.6), 0.0) if absf(h - 13.0) < 7.5 else 0.0
	return ambient_c() + 10.0 * sun * (1.0 - Weather.cover_level()) * (1.0 - Weather.wetness())


## The shed is out of the wind and a little warmer than outside.
static func shed_c() -> float:
	return ambient_c() + 3.0


## A tyre: the tread surface and the carcass beneath it. `p_slip` (W) is the work of the tyre
## sliding over the road, `p_roll` (W) of it flexing as it rolls.
func _tyre_step(i: int, dt: float, v: float, p_slip: float, p_roll: float, touching: bool, wet: float) -> void:
	var t: Dictionary = tyres[i]
	var ts := float(t["surface"])
	var tc := float(t["carcass"])
	var c := _tyre_mass[i] * 1600.0
	var c_s := c * 0.12
	var c_c := c - c_s
	var flow := pow(v, 0.8)
	var h_tread := (5.0 + 2.5 * flow) * _tread_area[i] * (1.0 + 2.0 * wet)
	var h_side := (4.0 + 1.5 * flow) * _side_area[i]
	var g_road := (4.0 + 0.3 * v) * (1.0 + 2.0 * wet) if touching else 0.0
	var g_sc := 14.6 * _tread_area[i] / 0.35   # rubber conducting through about 6 mm of tread
	# Sliding heats the tread; flexing heats the tread and the carcass alike.
	var q_s := 0.6 * p_slip + 0.45 * p_roll + g_sc * (tc - ts) - h_tread * (ts - air) - g_road * (ts - road)
	var q_c := 0.1 * p_slip + 0.45 * p_roll + g_sc * (ts - tc) - h_side * (tc - air) - 3.0 * (tc - air)
	t["surface"] = ts + q_s * dt / c_s
	t["carcass"] = tc + q_c * dt / c_c


## A brake: the disc (or drum) takes the braking work and sheds it to the air; the pads follow it.
func _brake_step(i: int, dt: float, v: float, p: float) -> void:
	var td := discs[i]
	var tp := pads[i]
	var tk := td + KELVIN
	var ta := air + KELVIN
	var cool := (10.0 + 6.0 * pow(v, 0.8)) * _disc_area[i] * _disc_cool[i] * (td - air) \
		+ 0.5 * 5.67e-8 * _disc_area[i] * (tk * tk * tk * tk - ta * ta * ta * ta)
	var link := 8.0 * (td - tp)
	discs[i] = td + (0.92 * p - cool - link) * dt / _disc_c[i]
	pads[i] = tp + (0.08 * p + link - 1.0 * (tp - air)) * dt / 270.0


## The engine: friction and pumping heat with the revs plus a share of the power it makes, taken
## away by the radiator (behind its thermostat, with a fan when hot) or the fins, with the airflow.
func _engine_step(dt: float, v: float, rpm: float, kw: float, running: bool) -> void:
	var p := 0.0
	if running:
		var spin := maxf(rpm, 0.0) / _idle_rpm
		p = _head * (1.1 * _displacement * pow(spin, 0.6) + (350.0 if liquid else 120.0) * maxf(kw, 0.0))
	var flow := 0.06 + minf(v / 25.0, 2.6)
	var ua: float
	if liquid:
		if engine > LIQUID["fan_on"] and running:
			fan = true
		elif engine < LIQUID["fan_off"] or not running:
			fan = false
		if fan:
			flow = maxf(flow, 0.6)
		var open := clampf((engine - float(LIQUID["thermostat"])) / 10.0, 0.03, 1.0)
		ua = _radiator * flow * open + 4.0
	else:
		ua = _radiator * flow + 1.5
	engine += (p - ua * (engine - air)) * dt / _engine_c
	var target := air + (engine - air) * _oil_follow
	oil += (target - oil) * (1.0 - exp(-dt / 120.0))


## How far this tyre is into its working window: its grip share from temperature alone, unsoftened.
func temp_grip(i: int) -> float:
	var w: Array = _windows[i]
	var t := tyre_temp(i)
	var lo := float(w[0])
	var hi := float(w[1])
	if t < lo:
		return lerpf(float(w[2]), 1.0, clampf(t / maxf(lo, 1.0), 0.0, 1.0))
	if t > hi:
		return 1.0 - OVERHEAT_LOSS * clampf((t - hi) / OVERHEAT_SPAN, 0.0, 1.0)
	return 1.0


## The tyre's temperature where it meets the road, °C: mostly the tread, partly the carcass.
func tyre_temp(i: int) -> float:
	return 0.65 * float(tyres[i]["surface"]) + 0.35 * float(tyres[i]["carcass"])


## The tyre's pressure now, bar: the cold setting, risen (or fallen) with the air inside it.
func pressure(i: int) -> float:
	return _set_psi[i] * (float(tyres[i]["carcass"]) + KELVIN) / (SET_AT + KELVIN)


## The grip a tyre has on `surf` from its heat and the pressure that's brought, against the grip
## the bike was built with (1 = as built). Softened by Riding realism.
func tyre_grip(i: int, surf: String) -> float:
	var g := temp_grip(i)
	if surf != "tarmac" and surf != "concrete":
		g = 1.0 - (1.0 - g) * OFF_ROAD_SHARE
	if _build:
		# The pressure the tyre should run hot is the one it's set to cold, warmed to working heat.
		var dev_now := (_set_psi[i] / _best_psi[i]) * (float(tyres[i]["carcass"]) + KELVIN) / (working(i) + KELVIN) - 1.0
		var road_surf := "tarmac" if surf == "concrete" else surf
		g *= _build._pressure_grip(dev_now, road_surf) / maxf(_build._pressure_grip(_dev_build[i], road_surf), 0.1)
	return lerpf(g, 1.0, soften) if g < 1.0 else g


## The brake's bite from its heat (1 = full): a little less cold, much less overcooked.
func brake_temp_mult(i: int) -> float:
	var p: Array = _pad[i]
	var t := 0.7 * discs[i] + 0.3 * pads[i]
	var cold := lerpf(float(p[1]), 1.0, clampf((t - 10.0) / maxf(float(p[0]) - 10.0, 1.0), 0.0, 1.0))
	var fade := 1.0 - FADE_LOSS * clampf((t - float(p[2])) / FADE_SPAN, 0.0, 1.0)
	return cold * fade


func _update_effects(assist: float, _delta: float) -> void:
	soften = clampf(assist, 0.0, 1.0) * SOFTEN
	for i in 2:
		bite[i] = lerpf(brake_temp_mult(i), 1.0, soften)
		tyres[i]["pressure"] = pressure(i)
		tyres[i]["grip"] = tyre_grip(i, "tarmac")
		grip[i] = float(tyres[i]["grip"])
	var e: Dictionary = LIQUID if liquid else AIR
	var warm_oil := clampf((oil - 10.0) / (OIL_WARM - 10.0), 0.0, 1.0)
	var cold := lerpf(COLD_POWER, 1.0, warm_oil)
	var hot := 1.0 - 0.3 * clampf((engine - float(e["loss_from"])) / float(e["loss_span"]), 0.0, 1.0)
	power = lerpf(cold * hot, 1.0, soften)
	var warm_e := clampf((engine - 10.0) / (float(e["warm"]) - 10.0), 0.0, 1.0)
	idle = 1.0 + FAST_IDLE * (1.0 - warm_e) * (1.0 - soften)


## "cold", "warm" or "hot" for the HUD: the tyres together (either one cold or hot says so).
func tyre_state() -> String:
	var out := "warm"
	for i in 2:
		var w: Array = _windows[i]
		var t := tyre_temp(i)
		if t > float(w[1]):
			return "hot"
		if temp_grip(i) < 0.97 and t < float(w[0]):
			out = "cold"
	return out


func engine_state() -> String:
	var e: Dictionary = LIQUID if liquid else AIR
	if engine >= float(e["hot"]):
		return "hot"
	if engine < float(e["warm"]):
		return "cold"
	return "warm"


## True while either brake has lost a noticeable share of its bite to heat.
func brakes_fading() -> bool:
	for i in 2:
		var p: Array = _pad[i]
		if 0.7 * discs[i] + 0.3 * pads[i] > float(p[2]) + 20.0:
			return true
	return false


## The engine's temperature's name: coolant or cylinder head.
func engine_label() -> String:
	return "coolant" if liquid else "head"


## Remembers a shed bike's heat as its rider gets off.
static func park(bike_id: int, heat: BikeHeat) -> void:
	if heat:
		parked[bike_id] = {"heat": heat, "at": Time.get_ticks_msec()}


## Gives a bike someone gets on the heat it has: what's left of its last ride, cooled for as
## long as it stood, or the shed's temperature through and through.
static func resume(bike_id: int, heat: BikeHeat) -> void:
	var t := shed_c()
	var p: Dictionary = parked.get(bike_id, {})
	if p.is_empty() or not is_instance_valid(p["heat"]):
		heat.soak(t)
		return
	heat.copy_from(p["heat"])
	heat.rest((Time.get_ticks_msec() - int(p["at"])) / 1000.0, t)
