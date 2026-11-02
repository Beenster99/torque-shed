extends RefCounted
## How the stock bikes ride against the real bikes they're modelled on (Simon: "the motorbikes
## performance similar to real life"), run from tests/run_tests.gd: its _test_realism_* functions
## hand over to these. Each style's stock bike (Contracts.style_build) is ridden on flat dry
## tarmac, auto-shift and Riding realism at 0.5 as the other ride tests: flat out from a standstill,
## stopped as hard as it'll go from 60 mph, and leaned as far as the input goes in a steady turn.
## _test_style_performance checks the same bikes' power, top speed, economy and weight on paper.

var t: Node   # the test runner: check(), ride(), _done()

const MPH60 := 26.8224   # m/s

## What a magazine road test of each kind of bike gets (see docs/bike_style_performance.md), with
## room either side: 0-60 mph (s), 60 mph to a stop (m), the lean a steady turn settles at with the
## input held full (deg) and the sideways g it pulls there. Cruisers ground their pegs and boards
## about 30 degrees over; an MX bike's knobblies and a cafe or scrambler's tyres hold less than road
## rubber. An MX bike's 0-60 is on tarmac, where its knobblies let go.
const REAL := {
	"classic": {"t60": [4.2, 6.5], "stop": [34.0, 44.0], "lean": [40.0, 52.0], "g": [0.8, 1.1]},
	"cafe": {"t60": [3.3, 4.5], "stop": [33.0, 42.0], "lean": [40.0, 52.0], "g": [0.8, 1.1]},
	"scrambler": {"t60": [3.6, 5.0], "stop": [34.0, 44.0], "lean": [36.0, 48.0], "g": [0.7, 1.0]},
	"tourer": {"t60": [3.2, 4.2], "stop": [33.0, 42.0], "lean": [42.0, 52.0], "g": [0.85, 1.1]},
	"roader": {"t60": [3.0, 3.8], "stop": [32.0, 40.0], "lean": [44.0, 54.0], "g": [0.9, 1.2]},
	"naked": {"t60": [2.9, 3.6], "stop": [32.0, 39.0], "lean": [44.0, 54.0], "g": [0.9, 1.2]},
	"sport": {"t60": [3.0, 3.7], "stop": [32.0, 39.0], "lean": [44.0, 54.0], "g": [0.9, 1.2]},
	"race": {"t60": [2.7, 3.4], "stop": [32.0, 38.0], "lean": [44.0, 54.0], "g": [0.9, 1.2]},
	"bobber": {"t60": [3.8, 5.0], "stop": [33.0, 44.0], "lean": [27.0, 35.0], "g": [0.45, 0.75]},
	"chopper": {"t60": [3.8, 5.0], "stop": [33.0, 44.0], "lean": [27.0, 35.0], "g": [0.45, 0.75]},
	"cruiser": {"t60": [3.8, 5.0], "stop": [33.0, 44.0], "lean": [27.0, 35.0], "g": [0.45, 0.75]},
	"adventure": {"t60": [3.3, 4.5], "stop": [33.0, 42.0], "lean": [40.0, 50.0], "g": [0.8, 1.1]},
	"supermoto": {"t60": [3.2, 4.2], "stop": [32.0, 40.0], "lean": [44.0, 54.0], "g": [0.9, 1.15]},
	"mx": {"t60": [4.0, 6.5], "stop": [36.0, 48.0], "lean": [30.0, 42.0], "g": [0.6, 0.9]},
}


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) and v <= float(band[1])


## Flat out from a standstill, tucked in: 0-60 mph against the road tests.
func test_launches() -> void:
	for style in REAL:
		var real: Dictionary = REAL[style]
		var t60 := [-1.0]
		var r: Dictionary = await t.ride(Contracts.style_build(style), 8.0, func(bike, at):
			bike.throttle = 1.0
			bike.body_shift = 0.6   # weight over the tank to keep the front down
			if t60[0] < 0.0 and bike.speed >= MPH60:
				t60[0] = at)
		var nm := PartsDB.style_name(style)
		check(not r["crashed"] and _in(t60[0], real["t60"]), "%s: 0-60 mph in %.1f s (real ones %.1f-%.1f s)" % [
			nm, t60[0], real["t60"][0], real["t60"][1]])
		await t._done(r)


## Up to just past 60 mph, then both brakes on hard (front full, back most of the way) with no
## weight shifted forward: metres from 60 mph to a stop. A careful rider (or ABS) works round the
## tyres' peak and keeps the back wheel near the road rather than holding a stoppie.
func test_stops() -> void:
	for style in REAL:
		var real: Dictionary = REAL[style]
		var st := {"braking": false, "from": Vector3.ZERO, "at": -1.0, "dist": -1.0, "nose": 0.0}
		var r: Dictionary = await t.ride(Contracts.style_build(style), 12.0, func(bike, at):
			if not st["braking"]:
				bike.throttle = 1.0
				bike.body_shift = 0.6
				st["braking"] = bike.speed >= MPH60 + 1.0
				return
			bike.throttle = 0.0
			bike.body_shift = 0.0
			bike.front_brake = 1.0
			bike.rear_brake = 0.6
			st["nose"] = minf(st["nose"], bike.pitch_angle)
			if st["at"] < 0.0 and bike.speed <= MPH60:
				st["at"] = at
				st["from"] = bike.global_position
			if st["at"] >= 0.0 and st["dist"] < 0.0 and bike.speed < 0.3:
				st["dist"] = bike.global_position.distance_to(st["from"]))
		var nm := PartsDB.style_name(style)
		check(not r["crashed"] and _in(st["dist"], real["stop"]), "%s: stops from 60 mph in %.1f m (real ones %.0f-%.0f m)" % [
			nm, st["dist"], real["stop"][0], real["stop"][1]])
		check(rad_to_deg(-st["nose"]) < 9.0, "%s: and the back wheel stays near the road (nose down %.1f deg at most)" % [
			nm, rad_to_deg(-st["nose"])])
		await t._done(r)


## At 20 m/s with the steer input held full: the lean it settles at and the sideways g, from the
## speed and the turn rate, over the last few seconds.
func test_corners() -> void:
	for style in REAL:
		var real: Dictionary = REAL[style]
		var acc := {"g": 0.0, "lean": 0.0, "n": 0}
		var r: Dictionary = await t.ride(Contracts.style_build(style), 12.0, func(bike, at):
			bike.throttle = clampf(0.25 + (20.0 - bike.speed) * 0.4, 0.0, 1.0)
			bike.lean_input = 0.0 if at < 6.0 else 1.0
			if at > 9.0:
				acc["g"] += absf(bike.angular_velocity.y * bike.speed) / 9.81
				acc["lean"] += absf(rad_to_deg(bike.lean_angle))
				acc["n"] += 1)
		var n := maxi(int(acc["n"]), 1)
		var g: float = acc["g"] / n
		var lean: float = acc["lean"] / n
		var nm := PartsDB.style_name(style)
		check(not r["crashed"], "%s: a full-lean turn at 20 m/s holds" % nm)
		check(_in(lean, real["lean"]) and rad_to_deg(r["max_lean"]) < float(real["lean"][1]) + 4.0,
			"%s: leans %.0f deg (most %.0f; real ones %.0f-%.0f)" % [nm, lean, rad_to_deg(r["max_lean"]), real["lean"][0], real["lean"][1]])
		check(_in(g, real["g"]), "%s: pulls %.2f g round it (real ones %.2f-%.2f)" % [nm, g, real["g"][0], real["g"][1]])
		await t._done(r)


## Simon: "the cruiser I was on (~70 hp) couldn't make it up some of the hills" in the mountains of
## Japan. The ECU's anti-wheelie read the bike's nose-up against the horizon, so a steep road looked
## like a wheelie and it shut the power down to a trickle. Flat out from a standstill and from 50 km/h
## on a 20% climb (steeper than any road the planner lays, see RoutePlanner.MAX_GRADE), with the
## anti-wheelie at its firmest: it pulls away and keeps climbing. And the aid still catches a real
## wheelie on that hill.
func test_hills() -> void:
	const GRADE := 0.20
	for start_v in [0.0, 14.0]:
		for ecu in ["none", "ecu_safety"]:
			var b := Contracts.style_build("cruiser")
			b["ecu"] = ecu
			var st := {"end": 0.0, "slowest": 99.0}
			var r: Dictionary = await t.ride_slope(b, 8.0, GRADE, start_v, func(bike, at):
				bike.build.tune["aid_anti_wheelie"] = 5.0
				bike.throttle = 1.0
				bike.body_shift = 0.3
				if at > 2.0:
					st["slowest"] = minf(st["slowest"], bike.speed)
				st["end"] = bike.speed)
			var what := "with %s anti-wheelie" % ("firm" if ecu != "none" else "no")
			check(not r["crashed"] and st["end"] > 25.0 and st["slowest"] > 8.0,
				"cruiser %s climbs a %.0f%% hill from %.0f km/h: %.0f km/h after 8 s, never under %.0f" % [what, GRADE * 100.0,
				start_v * 3.6, st["end"] * 3.6, st["slowest"] * 3.6])
			await t._done(r)
	# Weight right back and full gas on the same hill on a big four: the anti-wheelie still keeps the front down.
	for level in [0.0, 3.0]:
		var most := [0.0]
		var r: Dictionary = await t.ride_slope({"engine": "four_1000", "ecu": "race_ecu"}, 5.0, GRADE, 0.0, func(bike, at):
			bike.build.tune["aid_anti_wheelie"] = level
			bike.body_shift = -1.0
			bike.throttle = 1.0 if at > 0.5 else 0.0
			most[0] = maxf(most[0], rad_to_deg(bike.pitch_over_road)))
		if level > 0.0:
			check(not r["crashed"] and most[0] < 15.0, "on the hill the anti-wheelie still keeps the front near the road (%.0f deg up off it)" % most[0])
		else:
			check(most[0] > 15.0, "and with it off the front comes up there (%.0f deg)" % most[0])
		await t._done(r)
