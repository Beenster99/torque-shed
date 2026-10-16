class_name EngineSynth
extends RefCounted
## The engine sound's recipe. Nothing is recorded: every bike's sound is built from how its
## engine actually works. Each cylinder fires on its own crank angle (a 270 degree twin's
## off-beat, a V-twin's lope, a triple's 240 degree warble, a flat-plane four's even scream,
## a crossplane's growl); each firing sends a pressure pulse down its header pipe, which rings
## at the pipe's length; the pulses meet in the collector and pass through the silencer (a
## stock can soaks them up, a straight pipe lets them crack out). The intake side has its own
## pulses, sucked through the runners into the airbox, which howls (a triple's induction rasp),
## and the mechanical layer adds valve-train ticks, a dry clutch's rattle and a two-stroke's
## ring-ding.
##
## The sound is baked, not run live: for a ladder of engine speeds ("buckets"), on the throttle
## and off it, a short loop is rendered for the exhaust side and one for the engine/intake side.
## Each loop is a whole number of engine cycles so it repeats seamlessly. EngineSound then plays
## the loops on 3D players, crossfading and pitch-shifting between the two nearest buckets, the
## way racing games play their recorded engine loops. One-shots (overrun pops, downshift bangs,
## gear shifts, the starter and the kick) are rendered through the same exhaust.

const RATE := 32000
const LOOP_SECONDS := 0.4     # each loop is at least this long, a whole number of engine cycles
const WARMUP := 2400          # samples run through the pipes before a loop starts, so it loops seamlessly
const BUCKET_STEP := 1.2      # each bucket this much faster than the last
const SOUND_SPEED_HOT := 520.0   # m/s in the exhaust gas
const SOUND_SPEED_AIR := 343.0
const LAYERS := ["ex_on", "ex_off", "in_on", "in_off"]

## How each layout sounds: header length (m) and the second header group's length relative to it,
## how long a firing pulse lasts (crank degrees), how sharp its front is, the exhaust's colour
## (resonant peaks: [Hz, Q, gain]), the silencer body, how loud the intake is and how it howls,
## and how unevenly the cylinders breathe (a triple's warble).
const VOICES := {
	"single": {"hdr": 0.95, "hdr2": 1.0, "open": 240.0, "sharp": 0.45, "formants": [[380.0, 2.0, 0.5], [1100.0, 3.0, 0.2]],
		"body": 85.0, "intake": 0.5, "runner": 0.32, "airbox": 140.0, "howl": [700.0, 3.0], "rasp_hz": 1500.0, "imbalance": 0.0, "tail": 0.6},
	"twin": {"hdr": 0.85, "hdr2": 1.0, "open": 235.0, "sharp": 0.55, "formants": [[480.0, 2.0, 0.45], [1300.0, 3.0, 0.2]],
		"body": 90.0, "intake": 0.45, "runner": 0.3, "airbox": 150.0, "howl": [750.0, 3.0], "rasp_hz": 1600.0, "imbalance": 0.06, "tail": 0.55},
	"parallel": {"hdr": 0.8, "hdr2": 1.0, "open": 235.0, "sharp": 0.5, "formants": [[520.0, 2.0, 0.45], [1450.0, 3.0, 0.25]],
		"body": 85.0, "intake": 0.5, "runner": 0.28, "airbox": 155.0, "howl": [820.0, 3.0], "rasp_hz": 1700.0, "imbalance": 0.08, "tail": 0.55},
	"vtwin": {"hdr": 0.95, "hdr2": 0.7, "open": 245.0, "sharp": 0.42, "formants": [[340.0, 1.8, 0.6], [950.0, 3.0, 0.2]],
		"body": 72.0, "intake": 0.5, "runner": 0.3, "airbox": 130.0, "howl": [680.0, 3.0], "rasp_hz": 1400.0, "imbalance": 0.12, "tail": 0.6},
	"boxer": {"hdr": 0.85, "hdr2": 1.07, "open": 235.0, "sharp": 0.55, "formants": [[600.0, 2.5, 0.5], [1500.0, 3.0, 0.2]],
		"body": 95.0, "intake": 0.5, "runner": 0.3, "airbox": 160.0, "howl": [900.0, 3.0], "rasp_hz": 1700.0, "imbalance": 0.14, "tail": 0.5},
	"triple": {"hdr": 0.7, "hdr2": 1.0, "open": 230.0, "sharp": 0.5, "formants": [[900.0, 2.5, 0.45], [2100.0, 3.0, 0.3]],
		"body": 100.0, "intake": 1.0, "runner": 0.24, "airbox": 190.0, "howl": [1150.0, 3.5], "rasp_hz": 2200.0, "imbalance": 0.18, "tail": 0.5},
	"inline": {"hdr": 0.5, "hdr2": 1.0, "open": 225.0, "sharp": 0.55, "formants": [[1700.0, 2.5, 0.6], [3100.0, 3.5, 0.4]],
		"body": 110.0, "intake": 0.75, "runner": 0.2, "airbox": 210.0, "howl": [1500.0, 3.0], "rasp_hz": 2800.0, "imbalance": 0.05, "tail": 0.45},
	"2stroke": {"hdr": 0.0, "hdr2": 1.0, "open": 190.0, "sharp": 0.3, "formants": [[2100.0, 3.0, 0.5], [3400.0, 4.0, 0.35]],
		"body": 120.0, "intake": 0.35, "runner": 0.18, "airbox": 220.0, "howl": [1300.0, 3.0], "rasp_hz": 3000.0, "imbalance": 0.05, "tail": 0.4},
}
## How each style of exhaust treats the sound: the silencer's low-pass, how much of its body
## boom comes through, the turbulent rasp, how much the tail pipe rings, overall level, and how
## readily it pops on the overrun (pops a second at most).
const EXHAUSTS := {
	"stock": {"lp": 1400.0, "body": 0.9, "rasp": 0.06, "ring": 0.25, "gain": 0.55, "pops": 0.25},
	"slip": {"lp": 2400.0, "body": 0.6, "rasp": 0.16, "ring": 0.35, "gain": 0.75, "pops": 0.9},
	"full": {"lp": 3300.0, "body": 0.5, "rasp": 0.24, "ring": 0.4, "gain": 0.9, "pops": 1.3},
	"race": {"lp": 5000.0, "body": 0.35, "rasp": 0.36, "ring": 0.45, "gain": 1.05, "pops": 2.0},
	"straight": {"lp": 8500.0, "body": 0.2, "rasp": 0.55, "ring": 0.55, "gain": 1.2, "pops": 2.8},
}


# ---------------------------------------------------------------------------- the recipe

## The sound recipe for a built bike: its engine, crank, exhaust, air filter and gearbox.
static func spec_from_build(build: BikeBuild) -> Dictionary:
	var block := build.part("engine") if build.has_part("engine") else {}
	var ex := build.part("exhaust") if build.has_part("exhaust") else {}
	var air := build.part("air_filter") if build.has_part("air_filter") else {}
	var box := build.part("gearbox") if build.has_part("gearbox") else {}
	var plugs := float(build.health.get("spark_plugs", 1.0))
	var opts := {
		"crank": str(block.get("crank", "")),
		"idle": build.idle_rpm, "redline": build.redline, "peak": build.peak_torque_rpm,
		"exhaust": exhaust_style(ex), "loud": float(ex.get("loudness", 0.8)) if not ex.is_empty() else 1.4,
		"intake": str(air.get("style", "airbox")) if not air.is_empty() else "cone",
		"shift": shift_feel(box), "quickshifter": bool(box.get("quickshifter", false)),
		"dry_clutch": bool(box.get("dry_clutch", false)),
		"rust": clampf(float(build.condition.get("exhaust", {}).get("rust", 0.0)), 0.0, 1.0),
		"misfire": clampf((0.6 - plugs) * 0.6, 0.0, 0.3),
		"kick": str(block.get("layout", "")) == "2stroke" and int(block.get("cylinders", 1)) == 1
			or str(block.get("layout", "")) == "single" and str(build.parts.get("gearbox", "")) == "four_vintage",
	}
	return make_spec(build.layout, build.cylinders, build.displacement, opts)


## A recipe from the bare facts (tests, and anything without a whole bike). Unknown options
## take sensible defaults for the layout.
static func make_spec(layout: String, cylinders: int, displacement: float, opts := {}) -> Dictionary:
	if not VOICES.has(layout):
		layout = "inline" if cylinders >= 4 else ("triple" if cylinders == 3 else ("parallel" if cylinders == 2 else "single"))
	var crank := str(opts.get("crank", ""))
	if crank == "":
		crank = {"inline": "flat", "parallel": "270", "twin": "360", "vtwin": "90v", "boxer": "boxer", "triple": "240"}.get(layout, layout)
	var idle := float(opts.get("idle", 1200.0))
	var redline := float(opts.get("redline", 10000.0))
	var exhaust := str(opts.get("exhaust", "slip"))
	if not EXHAUSTS.has(exhaust):
		exhaust = "slip"
	return {
		"layout": layout, "cylinders": maxi(cylinders, 1), "cc": maxf(displacement, 20.0), "crank": crank,
		"idle": idle, "redline": maxf(redline, idle * 2.0), "peak": float(opts.get("peak", redline * 0.75)),
		"exhaust": exhaust, "loud": float(opts.get("loud", 0.8)), "intake": str(opts.get("intake", "airbox")),
		"shift": str(opts.get("shift", "click")), "quickshifter": bool(opts.get("quickshifter", false)),
		"dry_clutch": bool(opts.get("dry_clutch", false)),
		"rust": float(opts.get("rust", 0.0)), "misfire": float(opts.get("misfire", 0.0)), "kick": bool(opts.get("kick", false)),
	}


## The exhaust part's character: stock, slip-on, full system, race or straight pipe.
static func exhaust_style(ex: Dictionary) -> String:
	if ex.is_empty():
		return "straight"   # nothing fitted: open ports
	var style := str(ex.get("style", "stock"))
	if style == "full" and float(ex.get("loudness", 1.0)) >= 1.1:
		return "race"
	return style if EXHAUSTS.has(style) else "slip"


## How the gearbox feels through the lever: "slick" (a race box with a quickshifter),
## "click" (a positive sports box) or "clunk" (a basic or old box).
static func shift_feel(box: Dictionary) -> String:
	if box.has("shift_feel"):
		return str(box["shift_feel"])
	var t := float(box.get("shift_time", 0.12))
	return "slick" if t <= 0.05 else ("click" if t <= 0.1 else "clunk")


## Everything that changes the baked sound, as a key for sharing banks between bikes.
static func signature(spec: Dictionary) -> String:
	return "%s|%d|%d|%s|%d|%d|%d|%s|%s|%s|%d|%d|%s" % [spec["layout"], spec["cylinders"], roundi(spec["cc"] / 25.0), spec["crank"],
		roundi(spec["idle"] / 50.0), roundi(spec["redline"] / 100.0), roundi(spec["peak"] / 100.0), spec["exhaust"], spec["intake"],
		spec["dry_clutch"], roundi(spec["rust"] * 4.0), roundi(spec["misfire"] * 10.0), spec["kick"]]


static func is_two_stroke(spec: Dictionary) -> bool:
	return spec["layout"] == "2stroke"


## Crank degrees in one engine cycle: two turns for a four-stroke, one for a two-stroke.
static func cycle_degrees(spec: Dictionary) -> float:
	return 360.0 if is_two_stroke(spec) else 720.0


## When each cylinder fires, as [crank degrees into the cycle, header group]. Cylinders on the
## same group share a pipe (or pipes of equal length); a V-twin's front and rear headers differ,
## and each two-stroke cylinder has its own expansion chamber.
static func firing_events(spec: Dictionary) -> Array:
	var n: int = spec["cylinders"]
	match str(spec["crank"]):
		"single":
			return [[0.0, 0]]
		"360":
			return [[0.0, 0], [360.0, 0]]
		"270":
			return [[0.0, 0], [270.0, 0]]
		"90v":
			return [[0.0, 0], [270.0, 1]]   # a 90 degree V: 270 then 450 degrees, the lope
		"45v":
			return [[0.0, 0], [315.0, 1]]   # a narrow V: potato-potato
		"boxer":
			return [[0.0, 0], [360.0, 1]]
		"240":
			return [[0.0, 0], [240.0, 0], [480.0, 0]]
		"flat":
			return [[0.0, 0], [180.0, 0], [360.0, 0], [540.0, 0]]
		"crossplane":
			return [[0.0, 0], [270.0, 0], [450.0, 0], [540.0, 0]]   # 270-180-90-180: the uneven growl
		"bigbang":
			return [[0.0, 0], [90.0, 0], [360.0, 0], [450.0, 0]]    # pairs firing close together
		"2stroke":
			var out := []
			for c in n:
				out.append([360.0 * c / n, c])
			return out
	var even := []
	for c in n:
		even.append([cycle_degrees(spec) * c / n, 0])
	return even


## Firing pulses a second at `rpm`: the engine's basic note.
static func firing_hz(spec: Dictionary, rpm: float) -> float:
	return rpm / 60.0 * firing_events(spec).size() * (1.0 if is_two_stroke(spec) else 0.5)


## The ladder of engine speeds the loops are baked at, from below idle to past the redline.
static func bucket_rpms(spec: Dictionary) -> PackedFloat32Array:
	var lo: float = spec["idle"] * 0.85
	var hi: float = spec["redline"] * 1.05
	var count := clampi(ceili(log(hi / lo) / log(BUCKET_STEP)) + 1, 5, 20)
	var out := PackedFloat32Array()
	for i in count:
		out.append(loop_rpm(spec, lo * pow(hi / lo, float(i) / (count - 1))))
	return out


## The rpm nearest `rpm` whose loop is a whole number of cycles a whole number of samples long.
static func loop_rpm(spec: Dictionary, rpm: float) -> float:
	var info := loop_info(spec, rpm)
	return info["rpm"]


## [rpm, samples, cycles] for a loop near `rpm`.
static func loop_info(spec: Dictionary, rpm: float) -> Dictionary:
	var cycle_s := 60.0 / rpm * cycle_degrees(spec) / 360.0
	var cycles := maxi(ceili(LOOP_SECONDS / cycle_s), 2)
	var n := roundi(cycles * cycle_s * RATE)
	var exact := cycles * cycle_degrees(spec) / 360.0 * 60.0 * RATE / n
	return {"rpm": exact, "n": n, "cycles": cycles}


# ---------------------------------------------------------------------------- loops

## One baked loop: `layer` is "ex_on", "ex_off", "in_on" or "in_off". Returns the samples (a whole
## number of cycles, seamless) at the bucket's exact rpm.
static func render_loop(spec: Dictionary, layer: String, rpm: float, seed := 1) -> PackedFloat32Array:
	var info := loop_info(spec, rpm)
	var on := layer.ends_with("_on")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(signature(spec)) + seed * 7919 + (0 if on else 31) + (0 if layer.begins_with("ex") else 101)
	var events := _cycle_events(spec, info, on, rng)
	if layer.begins_with("ex"):
		return _exhaust(spec, info["rpm"], 1.0 if on else 0.0, events, info["n"], WARMUP, rng)
	return _intake(spec, info["rpm"], 1.0 if on else 0.0, events, info["n"], WARMUP, rng)


## Every firing in the loop: [sample time, amplitude, header group, cylinder]. Combustion varies
## a little from stroke to stroke on the throttle; off it, the charge is thin and some cycles
## barely light (the burble), and a two-stroke four-strokes at idle.
static func _cycle_events(spec: Dictionary, info: Dictionary, on: bool, rng: RandomNumberGenerator) -> Array:
	var fires := firing_events(spec)
	var cycle_len: float = float(info["n"]) / info["cycles"]
	var voice: Dictionary = VOICES[spec["layout"]]
	var imbalance: float = voice["imbalance"]
	var rpm: float = info["rpm"]
	var two := is_two_stroke(spec)
	var skip := float(spec["misfire"]) * (0.5 if on else 1.0)
	if not on:
		skip += 0.08
		if two:
			skip += 0.35 * clampf(1.0 - (rpm - spec["idle"]) / (spec["peak"] * 0.5), 0.0, 1.0)
	elif two:
		skip += 0.08 * clampf(1.0 - rpm / (spec["peak"] * 0.6), 0.0, 1.0)   # bogging below the powerband
	var out := []
	for c in info["cycles"]:
		for i in fires.size():
			if rng.randf() < skip:
				continue
			var a := 1.0 + imbalance * (0.9 if i == 0 else (-0.6 if i == 1 else 0.3))
			a *= (1.0 + rng.randfn(0.0, 0.07)) if on else rng.randf_range(0.35, 1.3)
			var t: float = (c + float(fires[i][0]) / cycle_degrees(spec)) * cycle_len + rng.randfn(0.0, 0.004) * cycle_len
			out.append([t, a, int(fires[i][1]), i])
	return out


## The exhaust side: pulses down the headers, into the collector and silencer, out of the tail pipe.
static func _exhaust(spec: Dictionary, rpm: float, load: float, events: Array, n: int, warm: int,
		rng: RandomNumberGenerator, bright := 0.0) -> PackedFloat32Array:
	var voice: Dictionary = VOICES[spec["layout"]]
	var style: Dictionary = EXHAUSTS[spec["exhaust"]]
	var two := is_two_stroke(spec)
	var per_cyl: float = spec["cc"] / spec["cylinders"]
	var deg_samples := 60.0 / rpm / 360.0 * RATE
	# The blowdown: most of the pulse comes out in the first part of the exhaust valve's opening.
	var tp := maxf(float(voice["open"]) * 0.32 * deg_samples, 4.0)
	var sharp: float = voice["sharp"] * (1.0 if load > 0.5 else 1.9)
	# How hard each pulse hits: bigger cylinders more, closed throttle far less.
	var amp := pow(per_cyl / 250.0, 0.35) * (1.0 if load > 0.5 else 0.32)
	var power := 1.0
	if two:
		# Coming on the pipe: below the powerband the note is thin, then it swells and hardens.
		var x: float = (rpm - spec["peak"]) / (spec["peak"] * 0.22)
		power = 0.45 + 1.1 * exp(-x * x) if load > 0.5 else 0.6
		sharp *= lerpf(1.0, 0.6, clampf(power - 0.45, 0.0, 1.0))
		amp *= power
	var groups := 1
	for e in events:
		groups = maxi(groups, int(e[2]) + 1)
	var total := n + warm
	var coll := PackedFloat32Array()
	coll.resize(total)
	var env := PackedFloat32Array()
	env.resize(n)
	# Excite each header group with its cylinders' pulses, then ring it at its length.
	# The pulse rises over its front (the lower `sharp`, the steeper) and tails away.
	var att := 0.5 + sharp
	var xpk := att / (att + 3.0)
	var norm := 1.0 / (pow(xpk, att) * pow(1.0 - xpk, 3.0))
	for g in groups:
		var ex := PackedFloat32Array()
		ex.resize(n)
		for e in events:
			if int(e[2]) != g:
				continue
			var t0: float = e[0]
			var a: float = float(e[1]) * amp
			var s := ceili(t0)
			var s_end := ceili(t0 + tp)
			while s < s_end:
				var x := (s - t0) / tp
				var idx := posmod(s, n)
				ex[idx] += a * norm * pow(x, att) * pow(1.0 - x, 3.0)
				s += 1
			# Blowdown turbulence: a burst of rasp at each pulse's front.
			var tau := maxf(tp * 0.12, 8.0)
			var k := 1.0
			s = ceili(t0)
			var decay := exp(-1.0 / tau)
			for j in int(tau * 5.0):
				env[posmod(s + j, n)] += a * k
				k *= decay
		var length: float = voice["hdr"] * (float(voice["hdr2"]) if g == 1 else 1.0)
		var fb := -0.55
		if two:
			# Each expansion chamber returns its wave in one turn of the crank at the powerband.
			length = SOUND_SPEED_HOT * 60.0 / spec["peak"] * 0.5 * (1.0 + 0.025 * g)
			fb = 0.72
		var d := clampi(roundi(2.0 * length / SOUND_SPEED_HOT * RATE), 2, 8000)
		var line := PackedFloat32Array()
		line.resize(d)
		var w := 0
		var lp := 0.0
		var m := posmod(-warm, n)
		for i in total:
			lp += (line[w] - lp) * 0.55
			var y := ex[m] + fb * lp
			line[w] = y
			w += 1
			if w >= d:
				w = 0
			coll[i] += y
			m += 1
			if m >= n:
				m = 0
	# The collector and tail pipe ring too, then the silencer, the rasp and the open air.
	var tail_d := clampi(roundi(2.0 * float(voice["tail"]) / SOUND_SPEED_HOT * RATE), 2, 4000)
	var tail := PackedFloat32Array()
	tail.resize(tail_d)
	var ring: float = -float(style["ring"])
	var rust: float = spec["rust"]
	var lp_hz: float = style["lp"] * (1.0 if load > 0.5 else 0.6) * (1.0 + rust * 0.8) * (1.0 + bright)
	var lpa := 1.0 - exp(-TAU * minf(lp_hz, RATE * 0.45) / RATE)
	var f: Array = voice["formants"]
	var r1 := _res(f[0][0], f[0][1])
	var r2 := _res(f[1][0], f[1][1])
	var g1: float = f[0][2] * 2.5
	var g2: float = f[1][2] * 2.5
	var rb := _res(voice["body"], 1.6)
	var body_g: float = style["body"] * 1.4
	var rr := _res(voice["rasp_hz"] * (1.0 + 0.4 * bright), 0.9)
	# Turbulent rasp grows with the gas speed, so with the revs.
	var gas := clampf(rpm / (float(spec["redline"]) * 0.6), 0.35, 1.3)
	var rasp_g: float = (style["rasp"] + rust * 0.4) * (1.0 if load > 0.5 else 0.45) * 6.0 * gas * (1.0 + bright)
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var tw := 0
	var tlp := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var f1y1 := 0.0
	var f1y2 := 0.0
	var f2y1 := 0.0
	var f2y2 := 0.0
	var by1 := 0.0
	var by2 := 0.0
	var ry1 := 0.0
	var ry2 := 0.0
	var rx1 := 0.0
	var rx2 := 0.0
	var prev := 0.0
	var dc := 0.0
	var gain: float = style["gain"] * 0.55
	var drive: float = 1.0 + style["ring"]
	var m2 := posmod(-warm, n)
	for i in total:
		tlp += (tail[tw] - tlp) * 0.5
		var rn := noise[m2] * env[m2]
		var ra := rr[0] * (rn - rx2) + rr[1] * ry1 - rr[2] * ry2
		ry2 = ry1
		ry1 = ra
		rx2 = rx1
		rx1 = rn
		m2 += 1
		if m2 >= n:
			m2 = 0
		var z := coll[i] + ring * tlp
		tail[tw] = z
		z += ra * rasp_g   # the rasp is made in the pipe and goes through the silencer too
		tw += 1
		if tw >= tail_d:
			tw = 0
		# Silencer: a two-pole low-pass, plus the can's boomy body.
		a1 += (z - a1) * lpa
		a2 += (a1 - a2) * lpa
		var f1 := r1[0] * (z - x2) + r1[1] * f1y1 - r1[2] * f1y2
		f1y2 = f1y1
		f1y1 = f1
		var f2 := r2[0] * (z - x2) + r2[1] * f2y1 - r2[2] * f2y2
		f2y2 = f2y1
		f2y1 = f2
		var bo := rb[0] * (z - x2) + rb[1] * by1 - rb[2] * by2
		by2 = by1
		by1 = bo
		x2 = x1
		x1 = z
		var flow := a2 + f1 * g1 + f2 * g2 + bo * body_g
		# What reaches the ear leans towards how fast the flow changes, less its slow drift.
		var p := flow - prev * 0.8
		prev = flow
		dc += (p - dc) * 0.004
		if i >= warm:
			var v := (p - dc) * gain * drive
			out[i - warm] = v / (1.0 + absf(v)) / drive * 1.6
	return out


## The engine side: intake pulses through the runners and airbox (the induction howl and rasp),
## plus the mechanical layer: valve-train ticks, a dry clutch rattling at idle, a two-stroke's
## ring-ding and piston rattle.
static func _intake(spec: Dictionary, rpm: float, load: float, events: Array, n: int, warm: int,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var voice: Dictionary = VOICES[spec["layout"]]
	var two := is_two_stroke(spec)
	var cone: bool = spec["intake"] != "airbox"   # a cone, pod filters or bare velocity stacks: open and loud
	var per_cyl: float = spec["cc"] / spec["cylinders"]
	var deg_samples := 60.0 / rpm / 360.0 * RATE
	var tp := maxf(200.0 * deg_samples, 8.0)
	var on := load > 0.5
	var amp := pow(per_cyl / 250.0, 0.3) * (1.0 if on else 0.3)
	var cycle_deg := cycle_degrees(spec)
	var ex := PackedFloat32Array()
	ex.resize(n)
	var env := PackedFloat32Array()
	env.resize(n)
	var tick := PackedFloat32Array()
	tick.resize(n)
	var rattle := PackedFloat32Array()
	rattle.resize(n)
	var cycle_len := 60.0 / rpm * cycle_deg / 360.0 * RATE
	var idle_ness := clampf(1.0 - (rpm - spec["idle"]) / 2500.0, 0.0, 1.0)
	for e in events:
		# The intake valve opens about a turn after the cylinder fired (half a turn on a two-stroke).
		var t0: float = float(e[0]) + (180.0 if two else 380.0) * deg_samples
		var a: float = absf(float(e[1])) * amp * (1.0 if on else 0.6)
		var s := ceili(t0)
		var s_end := ceili(t0 + tp)
		while s < s_end:
			var x := (s - t0) / tp
			var sv := sin(PI * x)
			ex[posmod(s, n)] -= a * sv * sv
			s += 1
		var tau := maxf(tp * 0.25, 10.0)
		var k := 1.0
		var decay := exp(-1.0 / tau)
		s = ceili(t0)
		for j in int(tau * 4.0):
			env[posmod(s + j, n)] += a * k
			k *= decay
		# Valve train: each valve seating ticks.
		if not two:
			for at in [360.0 + 15.0, 540.0 + 45.0]:
				var tt := roundi(float(e[0]) + at * deg_samples)
				tick[posmod(tt, n)] += 0.6 * rng.randf_range(0.7, 1.2)
		# A dry clutch rattles at idle; a two-stroke's piston clatters.
		if spec["dry_clutch"] and idle_ness > 0.0:
			for j in 3:
				var tt := roundi(float(e[0]) + rng.randf_range(0.0, 0.8) * cycle_len / events.size() * 2.0)
				rattle[posmod(tt, n)] += rng.randf_range(0.4, 1.0) * idle_ness * (1.4 if not on else 0.8)
		if two:
			var tt := roundi(float(e[0]) + 20.0 * deg_samples)
			rattle[posmod(tt, n)] += rng.randf_range(0.3, 0.8) * (0.6 + 0.4 * idle_ness)
	# The ring-ding: the barrel fins and pipe ring at each firing, strongest at low revs.
	var ding := 0.0
	if two:
		ding = (0.9 if not on else 0.35) * clampf(1.0 - (rpm - spec["idle"]) / (spec["peak"] * 0.55), 0.0, 1.0)
	var runner_d := clampi(roundi(2.0 * float(voice["runner"]) / SOUND_SPEED_AIR * RATE), 2, 4000)
	var line := PackedFloat32Array()
	line.resize(runner_d)
	var rbox := _res(voice["airbox"], 4.0)
	var howl: Array = voice["howl"]
	var rh := _res(howl[0], howl[1])
	var rr := _res(voice["rasp_hz"] * (1.3 if cone else 1.0), 1.1)
	var rt := _res(3300.0, 9.0)
	var rc := _res(2700.0, 5.0)
	var d1 := _res(1870.0, 40.0)
	var d2 := _res(3150.0, 45.0)
	var d3 := _res(4420.0, 50.0)
	var box_g := 0.25 if cone else 1.0
	var gas := clampf(rpm / (float(spec["redline"]) * 0.6), 0.1, 1.3)
	var rasp_g := (1.4 if cone else 1.0) * (1.0 if on else 0.35) * 0.9 * gas
	var howl_g := 1.2 if on else 0.4
	var mech_g := 0.12 * clampf(per_cyl / 300.0, 0.5, 1.4)
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var total := n + warm
	var out := PackedFloat32Array()
	out.resize(n)
	var w := 0
	var lp := 0.0
	var bx1 := 0.0
	var bx2 := 0.0
	var by1 := 0.0
	var by2 := 0.0
	var hy1 := 0.0
	var hy2 := 0.0
	var rx1 := 0.0
	var rx2 := 0.0
	var ry1 := 0.0
	var ry2 := 0.0
	var tx1 := 0.0
	var tx2 := 0.0
	var ty1 := 0.0
	var ty2 := 0.0
	var cx1 := 0.0
	var cx2 := 0.0
	var cy1 := 0.0
	var cy2 := 0.0
	var dx1 := 0.0
	var dx2 := 0.0
	var e1a := 0.0
	var e1b := 0.0
	var e2a := 0.0
	var e2b := 0.0
	var e3a := 0.0
	var e3b := 0.0
	var prev := 0.0
	var dc := 0.0
	var gain: float = float(voice["intake"]) * (1.5 if cone else 1.0) * 0.5
	var ila := 1.0 - exp(-TAU * (4500.0 if cone else 3400.0) / RATE)
	var il1 := 0.0
	var il2 := 0.0
	var m := posmod(-warm, n)
	for i in total:
		lp += (line[w] - lp) * 0.6
		var y := ex[m] - 0.5 * lp
		line[w] = y
		w += 1
		if w >= runner_d:
			w = 0
		var bo := rbox[0] * (y - bx2) + rbox[1] * by1 - rbox[2] * by2
		by2 = by1
		by1 = bo
		var ho := rh[0] * (y - bx2) + rh[1] * hy1 - rh[2] * hy2
		hy2 = hy1
		hy1 = ho
		bx2 = bx1
		bx1 = y
		var rn := noise[m] * env[m]
		var ra := rr[0] * (rn - rx2) + rr[1] * ry1 - rr[2] * ry2
		ry2 = ry1
		ry1 = ra
		rx2 = rx1
		rx1 = rn
		var flow := y * 0.15 + bo * box_g + ho * howl_g * 2.5 + ra * rasp_g
		var p0 := flow - prev * 0.75
		prev = flow
		# The airbox and filter soak up the top end (less so an open cone filter).
		il1 += (p0 - il1) * ila
		il2 += (il1 - il2) * ila
		var p := il2
		dc += (p - dc) * 0.004
		# The mechanical layer.
		var tk := tick[m]
		var to := rt[0] * (tk - tx2) + rt[1] * ty1 - rt[2] * ty2
		ty2 = ty1
		ty1 = to
		tx2 = tx1
		tx1 = tk
		var rk := rattle[m] * (noise[m] * 0.5 + 0.5)
		var co := rc[0] * (rk - cx2) + rc[1] * cy1 - rc[2] * cy2
		cy2 = cy1
		cy1 = co
		cx2 = cx1
		cx1 = rk
		var mech := (to * 0.6 + co * 0.9) * mech_g
		if ding > 0.0:
			var dk := rattle[m]
			var o1 := d1[0] * (dk - dx2) + d1[1] * e1a - d1[2] * e1b
			e1b = e1a
			e1a = o1
			var o2 := d2[0] * (dk - dx2) + d2[1] * e2a - d2[2] * e2b
			e2b = e2a
			e2a = o2
			var o3 := d3[0] * (dk - dx2) + d3[1] * e3a - d3[2] * e3b
			e3b = e3a
			e3a = o3
			dx2 = dx1
			dx1 = dk
			mech += (o1 + o2 * 0.7 + o3 * 0.5) * ding * 1.6
		m += 1
		if m >= n:
			m = 0
		if i >= warm:
			var v := (p - dc) * gain + mech
			out[i - warm] = v / (1.0 + absf(v)) * 1.4
	return out


## A two-pole resonator's coefficients [b0, a1, a2] at `hz` with quality `q`; peak gain about 1.
static func _res(hz: float, q: float) -> PackedFloat32Array:
	var f := minf(hz, RATE * 0.45)
	var bw := f / maxf(q, 0.3)
	var r := exp(-PI * bw / RATE)
	return PackedFloat32Array([(1.0 - r * r) * 0.5, 2.0 * r * cos(TAU * f / RATE), r * r])


# ---------------------------------------------------------------------------- one-shots

## A pop on the overrun: unburnt fuel lighting in the hot pipe. `strength` 1 is a pop, 2.5 a
## downshift bang, 4 a backfire crack. Rendered through this bike's own exhaust.
static func render_pop(spec: Dictionary, strength: float, seed := 1) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(signature(spec)) + seed * 131
	var n := int(RATE * (0.3 + 0.12 * strength))
	var events := []
	events.append([4.0, 2.2 * strength, 0, 0])
	# A crackle of smaller pops after the first, more after a big one.
	var crackles := rng.randi_range(1, 2) + int(strength * 1.5)
	var t := 4.0
	for i in crackles:
		t += rng.randf_range(0.012, 0.05) * RATE
		if t > n * 0.7:
			break
		events.append([t, rng.randf_range(0.4, 1.0) * strength * 1.2 / (1.0 + i * 0.4), 0, 0])
	# Fire them as very short, sharp pulses: a fast-burning puff, not a whole exhaust stroke.
	var pop_spec := spec.duplicate()
	var rpm := 9000.0 / maxf(strength, 1.0)
	var out := _exhaust(pop_spec, rpm, 1.0, events, n, 0, rng, 0.6)
	# Fade the tail out cleanly.
	var fade := int(RATE * 0.04)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return out


## The gearbox's sound for one shift: "slick" (a race quickshifter: a crisp double tick),
## "click" (a positive sports box: a clean detent click with a little body) or "clunk" (a
## basic or old box: a heavy dog engagement with a rattle). "neutral" is the solid clunk of
## dropping into first from neutral.
static func render_shift(kind: String, seed := 1) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 977 + hash(kind)
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	match kind:
		"slick":
			_ping(out, 0, 5200.0, 0.006, 0.45, rng)
			_ping(out, int(RATE * 0.009), 7800.0, 0.004, 0.25, rng)
			_thump(out, 0, 320.0, 0.012, 0.12)
		"click":
			_ping(out, 0, 3400.0, 0.012, 0.55, rng)
			_thump(out, int(RATE * 0.004), 210.0, 0.025, 0.4)
			_ping(out, int(RATE * 0.018), 2600.0, 0.008, 0.18, rng)
		"neutral":
			_thump(out, 0, 85.0, 0.09, 0.95)
			_ping(out, int(RATE * 0.003), 560.0, 0.1, 0.35, rng)
			_ping(out, int(RATE * 0.004), 1240.0, 0.06, 0.25, rng)
			_noise_burst(out, 0, 0.05, 1700.0, 0.3, rng)
		_:
			_thump(out, 0, 110.0, 0.07, 0.8)
			_ping(out, int(RATE * 0.002), 650.0, 0.09, 0.3, rng)
			_ping(out, int(RATE * 0.003), 1310.0, 0.05, 0.2, rng)
			_noise_burst(out, 0, 0.04, 1800.0, 0.25, rng)
			_thump(out, int(RATE * 0.032), 95.0, 0.05, 0.35)
	_limit(out)
	return out


## The starter motor: the solenoid clicks, the motor whirrs and labours at each compression,
## the engine chuffing over through its pipe. Or, for a kick-start bike, the lever clacks down,
## the engine turns over a few times and the lever springs back.
static func render_starter(spec: Dictionary, kick := false, seconds := 0.75) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(signature(spec)) + (5 if kick else 3)
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var comp_events := []
	var fires := firing_events(spec)
	if kick:
		_ping(out, 0, 1250.0, 0.03, 0.5, rng)
		_ping(out, 0, 3100.0, 0.015, 0.3, rng)
		_noise_burst(out, int(RATE * 0.01), 0.12, 900.0, 0.12, rng)
		# The kick spins it over quickly, then slower.
		var t := 0.05
		var gap := 0.06
		for i in 4:
			comp_events.append([t * RATE, 0.55 - i * 0.08, 0, 0])
			t += gap
			gap *= 1.35
		_ping(out, int(RATE * minf(seconds - 0.12, 0.5)), 1400.0, 0.025, 0.35, rng)   # the lever springs back up
	else:
		_ping(out, 0, 2500.0, 0.01, 0.4, rng)   # the solenoid
		var crank_rpm := 280.0
		var phase := 0.0
		var hz := 150.0
		var comp_gap := 60.0 / crank_rpm * cycle_degrees(spec) / 360.0 / fires.size()
		var next_comp := 0.06
		var labour := 0.0
		for i in n:
			var t := float(i) / RATE
			if t >= 0.03:
				if t >= next_comp:
					comp_events.append([float(i), 0.35, 0, 0])
					next_comp += comp_gap
					labour = 1.0
				labour *= 0.9993
				var target := lerpf(170.0, 300.0, clampf((t - 0.03) / 0.2, 0.0, 1.0)) * (1.0 - 0.22 * labour)
				hz += (target - hz) * 0.002
				phase = fmod(phase + hz / RATE, 1.0)
				# A whirring motor: a buzzy fundamental and its harmonics, and brush noise.
				var s := 0.0
				for k in range(1, 6):
					s += sin(TAU * phase * k * 3.0) / k
				var fade_in := clampf((t - 0.03) / 0.04, 0.0, 1.0)
				out[i] += (s * 0.09 + rng.randf_range(-1.0, 1.0) * 0.025) * fade_in
	# The engine turning over: soft compression chuffs through its own exhaust.
	if not comp_events.is_empty():
		var chuffs := _exhaust(spec, 900.0, 0.0, comp_events, n, 0, rng)
		for i in n:
			out[i] += chuffs[i] * 1.6
	var fade := int(RATE * 0.03)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	_limit(out)
	return out


## A ringing metallic ping: a short noise tick into a resonance.
static func _ping(out: PackedFloat32Array, at: int, hz: float, decay_s: float, amp: float, rng: RandomNumberGenerator) -> void:
	var w := TAU * hz / RATE
	var k := exp(-1.0 / (decay_s * RATE))
	var a := amp
	var ph := rng.randf() * TAU
	var i := at
	while i < out.size() and a > 0.0005:
		out[i] += sin(ph) * a
		ph += w
		a *= k
		i += 1


## A dull thud: a decaying low sine that drops a little in pitch.
static func _thump(out: PackedFloat32Array, at: int, hz: float, decay_s: float, amp: float) -> void:
	var k := exp(-1.0 / (decay_s * RATE))
	var a := amp
	var ph := 0.0
	var f := hz * 1.3
	var i := at
	while i < out.size() and a > 0.0005:
		out[i] += sin(ph) * a
		f += (hz - f) * 0.002
		ph += TAU * f / RATE
		a *= k
		i += 1


## A band of noise that dies away: a rattle or a hiss.
static func _noise_burst(out: PackedFloat32Array, at: int, decay_s: float, hz: float, amp: float, rng: RandomNumberGenerator) -> void:
	var r := _res(hz, 2.0)
	var k := exp(-1.0 / (decay_s * RATE))
	var a := amp
	var y1 := 0.0
	var y2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var i := at
	while i < out.size() and a > 0.0005:
		var x := rng.randf_range(-1.0, 1.0) * a * (1.0 if rng.randf() < 0.4 else 0.2)
		var y := r[0] * (x - x2) + r[1] * y1 - r[2] * y2
		y2 = y1
		y1 = y
		x2 = x1
		x1 = x
		out[i] += y * 3.0
		a *= k
		i += 1


## Soft-limit a buffer into -1..1.
static func _limit(out: PackedFloat32Array) -> void:
	for i in out.size():
		var v := out[i]
		out[i] = v / (1.0 + absf(v) * 0.5) * 1.0


# ---------------------------------------------------------------------------- streams

## 16-bit little-endian PCM bytes for a buffer (safe to make on a worker thread).
static func to_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	return data


## A playable stream from PCM bytes; `loop` repeats it seamlessly.
static func to_stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav


## Writes a buffer to a .wav file (for listening to renders outside the game).
static func save_wav(samples: PackedFloat32Array, path: String) -> Error:
	var wav := to_stream(to_bytes(samples), false)
	return wav.save_to_wav(path)
