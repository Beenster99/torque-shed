class_name SfxSynth
extends RefCounted
## Every shed sound, synthesised from small physical models instead of recordings: metal
## parts ring with the inharmonic modes of bars and plates, impacts are a contact pulse (short
## for hard things, long for soft ones) exciting the object's modes and the surface's, motors
## are tones that follow the shaft speed under load, water is noise with bubbles in it. Each
## one-shot comes in several variants (different part sizes, bounces, timings), and loops are
## long enough, and joined seamlessly, so they don't sound like a stuck record.
##
## Sfx asks for `make(sound, variant)`; everything here is deterministic for a given sound and
## variant (seeded), and touches nothing outside itself, so it can run on a worker thread.

const RATE := 44100
const R := 44100.0

## How many variants each one-shot has; anything not listed has one.
const VARIANTS := {
	"clink": 8, "clunk": 6, "pickup": 6, "scrap": 5, "switch": 5, "ting": 4,
	"door_start": 2, "door_stop": 3, "grinder_up": 3, "grinder_down": 3, "jet_on": 2, "jet_off": 3,
	"gun_on": 3, "gun_off": 3, "pump_on": 2, "pump_off": 2, "blast_on": 2, "blast_off": 2, "comp_on": 2, "comp_off": 3,
	"bead_pop": 4, "slide_open": 3, "slide_close": 3, "slide_shut": 3, "tube_start": 3, "creak": 5,
	"wash_ding": 3,
}
const STEP_VARIANTS := 8
const IMPACT_VARIANTS := 4
## What a part can be made of, for impacts (PartsDB materials map onto these), and what it lands on.
const MATERIALS: Array[String] = ["metal", "plastic", "rubber", "soft", "cardboard"]
const SURFACES: Array[String] = ["concrete", "wood", "steel", "ground"]
## Floors footsteps know: the shed's concrete or epoxy, wooden stairs, the steel mezzanine and
## dyno plate, the showroom's tiles, carpet upstairs, and outside tarmac, gravel, grass and puddles.
const STEP_SURFACES: Array[String] = ["concrete", "epoxy", "wood", "metal", "gravel", "grass", "tarmac", "puddle", "tile", "carpet"]

## Loudness each sound is brought to: ["rms", x] for steady loops, ["peak", x] for one-shots.
const LEVELS := {
	"ratchet": ["peak", 0.85], "scrub": ["rms", 0.12], "grinder": ["rms", 0.17], "spray": ["rms", 0.13], "spray_gun": ["rms", 0.12],
	"washer": ["rms", 0.13], "static": ["rms", 0.1], "jet": ["rms", 0.2], "pour": ["rms", 0.12], "door": ["rms", 0.15],
	"fan": ["rms", 0.15], "blast": ["rms", 0.22], "rain": ["rms", 0.12], "rain_roof": ["rms", 0.14], "changer": ["rms", 0.12],
	"dyno_roller": ["rms", 0.14], "compressor": ["rms", 0.16], "shaker": ["rms", 0.13], "hum_fluoro": ["rms", 0.05], "hum_led": ["rms", 0.035],
	"tone_shed": ["rms", 0.04], "tone_sales": ["rms", 0.04], "amb_out": ["rms", 0.07], "amb_town": ["rms", 0.05], "birds": ["peak", 0.35],
	"crickets": ["peak", 0.25],
	"screech": ["peak", 0.36], "starter": ["peak", 0.61], "chirp": ["peak", 1.0], "gear": ["peak", 0.64], "ping": ["peak", 0.44],
	"beep": ["peak", 0.18], "levelup": ["peak", 0.37], "bell": ["peak", 0.37], "bell_chime": ["peak", 0.36],
	"clink": ["peak", 0.6], "clunk": ["peak", 0.75], "pickup": ["peak", 0.45], "scrap": ["peak", 0.6], "switch": ["peak", 0.5],
	"ting": ["peak", 0.45], "blast_scan": ["peak", 0.4], "step": ["peak", 0.6], "door_start": ["peak", 0.6], "door_stop": ["peak", 0.6],
	"grinder_up": ["peak", 0.6], "grinder_down": ["peak", 0.55], "jet_on": ["peak", 0.6], "jet_off": ["peak", 0.55],
	"gun_on": ["peak", 0.4], "gun_off": ["peak", 0.4], "pump_on": ["peak", 0.5], "pump_off": ["peak", 0.45],
	"blast_on": ["peak", 0.6], "blast_off": ["peak", 0.6], "comp_on": ["peak", 0.65], "comp_off": ["peak", 0.65],
	"bead_pop": ["peak", 0.8], "slide_open": ["peak", 0.45], "slide_close": ["peak", 0.45], "slide_shut": ["peak", 0.5],
	"tube_start": ["peak", 0.4], "creak": ["peak", 0.5], "sale_offer": ["peak", 0.55], "desk_bell": ["peak", 0.5],
	"wash_ding": ["peak", 0.5], "wash_clean": ["peak", 0.55],
}
## Footstep loudness by floor (concrete is the reference).
const STEP_PEAK := {"concrete": 0.5, "epoxy": 0.5, "wood": 0.55, "metal": 0.55, "gravel": 0.5, "grass": 0.35, "tarmac": 0.45,
	"puddle": 0.6, "tile": 0.55, "carpet": 0.3}

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


## How many variants `sound` has.
static func variant_count(sound: String) -> int:
	if sound == "step" or sound.begins_with("step_"):
		return STEP_VARIANTS
	if sound.begins_with("impact_"):
		return IMPACT_VARIANTS
	return int(VARIANTS.get(sound, 1))


## Every sound name there is, loops and one-shots, impacts and footsteps included, roughly in
## the order a new shed needs them (the worker makes them in this order).
static func all_sounds() -> Array[String]:
	var out: Array[String] = ["step_concrete", "step_epoxy", "step", "switch", "pickup", "clink", "clunk", "ratchet", "scrub",
		"impact_metal_concrete", "impact_metal_wood", "impact_metal_steel", "grinder", "spray", "spray_gun", "washer", "jet",
		"pour", "changer", "door", "static", "fan", "blast", "dyno_roller", "compressor", "shaker", "scrap", "screech", "chirp", "starter",
		"gear", "ping", "beep", "levelup", "ting", "bell", "bell_chime", "desk_bell", "sale_offer", "wash_ding", "wash_clean", "rain", "rain_roof",
		"tone_shed", "tone_sales", "hum_fluoro", "hum_led", "amb_out", "birds", "crickets", "amb_town"]
	for s in VARIANTS:
		if not out.has(s):
			out.append(s)
	for s in STEP_SURFACES:
		if not out.has("step_" + s):
			out.append("step_" + s)
	for m in MATERIALS:
		for s in SURFACES:
			if not out.has("impact_%s_%s" % [m, s]):
				out.append("impact_%s_%s" % [m, s])
	return out


## Makes variant `v` of `sound` as samples at RATE, mono, about -1..1.
static func make(sound: String, v: int) -> PackedFloat32Array:
	var s := SfxSynth.new(absi(hash(sound)) % 1000003 * 31 + v * 7919 + 17)
	var d := s._make(sound, v)
	return s._level(sound, d)


func _make(sound: String, v: int) -> PackedFloat32Array:
	if sound == "step":
		return _step("concrete")
	if sound.begins_with("step_"):
		return _step(sound.trim_prefix("step_"))
	if sound.begins_with("impact_"):
		var bits := sound.split("_")
		return _impact(bits[1], bits[2] if bits.size() > 2 else "concrete")
	match sound:
		"ratchet": return _ratchet()
		"scrub": return _scrub()
		"grinder": return _grinder()
		"spray": return _spray(false)
		"spray_gun": return _spray(true)
		"static": return _static()
		"washer": return _washer()
		"jet": return _jet()
		"pour": return _pour()
		"door": return _door()
		"fan": return _fan()
		"blast": return _blast()
		"rain": return _rain(false)
		"rain_roof": return _rain(true)
		"changer": return _changer()
		"dyno_roller": return _dyno_roller()
		"compressor": return _compressor()
		"shaker": return _shaker()
		"hum_fluoro": return _hum(false)
		"hum_led": return _hum(true)
		"tone_shed": return _room_tone(false)
		"tone_sales": return _room_tone(true)
		"amb_out": return _outdoors()
		"amb_town": return _town()
		"birds": return _birds()
		"crickets": return _crickets()
		"clink": return _clink()
		"clunk": return _clunk()
		"pickup": return _pickup()
		"scrap": return _scrap()
		"switch": return _switch()
		"ting": return _ting()
		"blast_scan": return _blast_scan()
		"door_start": return _door_tail(true)
		"door_stop": return _door_tail(false)
		"grinder_up": return _grinder_tail(true)
		"grinder_down": return _grinder_tail(false)
		"jet_on": return _jet_tail(true)
		"jet_off": return _jet_tail(false)
		"gun_on": return _gun_tail(true)
		"gun_off": return _gun_tail(false)
		"pump_on": return _pump_tail(true)
		"pump_off": return _pump_tail(false)
		"blast_on": return _blast_tail(true)
		"blast_off": return _blast_tail(false)
		"comp_on": return _comp_tail(true)
		"comp_off": return _comp_tail(false)
		"bead_pop": return _bead_pop()
		"slide_open": return _slide(true)
		"slide_close": return _slide(false)
		"slide_shut": return _slide_shut()
		"tube_start": return _tube_start()
		"creak": return _creak()
		"starter": return _starter()
		"screech": return _screech()
		"chirp": return _chirp()
		"gear": return _gear()
		"ping": return _chime()
		"beep": return _beep()
		"levelup": return _levelup()
		"bell": return _shop_bell()
		"bell_chime": return _door_chime()
		"desk_bell": return _desk_bell()
		"sale_offer": return _till()
		"wash_ding": return _wash_ding(v)
		"wash_clean": return _wash_clean()
	return buf(0.1)


# ---------------------------------------------------------------------------- building blocks

func buf(seconds: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(int(R * seconds))
	return d


func nz() -> float:
	return rng.randf() * 2.0 - 1.0


func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


## One-pole filter coefficient for a cutoff at `hz`.
static func k(hz: float) -> float:
	return 1.0 - exp(-TAU * minf(hz, R * 0.45) / R)


## A ringing mode added into `d` from sample `start`: frequency, starting amplitude and decay
## rate (per second). A two-pole resonator, so it costs a couple of multiplies a sample. With
## `wrap` it carries on round from the start, for loops.
func ring(d: PackedFloat32Array, start: int, f: float, amp: float, decay: float, wrap := false) -> void:
	var size := d.size()
	if f <= 0.0 or f >= R * 0.45 or absf(amp) < 1e-6 or size == 0:
		return
	start = posmod(start, size) if wrap else start
	if start < 0 or start >= size:
		return
	var w := TAU * f / R
	var r := exp(-decay / R)
	var c := 2.0 * r * cos(w)
	var r2 := r * r
	var y2 := 0.0
	var y1 := amp * sin(w)
	# Until it has died away below hearing (about -90 dB of full scale).
	var n := mini(int(log(maxf(absf(amp), 4e-5) / 3e-5) * R / maxf(decay, 0.5)) + 1, size if wrap else size - start)
	var j := start
	for i in n:
		d[j] += y1
		var y := c * y1 - r2 * y2
		y2 = y1
		y1 = y
		j += 1
		if j >= size:
			j = 0


## Excites a set of modes ([[freq, amp, decay], ...]) with a contact pulse `tau` seconds long:
## the longer the contact (soft things), the less of the high modes it reaches.
func hit(d: PackedFloat32Array, start: int, modes: Array, tau: float, amp: float, wrap := false) -> void:
	for m in modes:
		var f := float(m[0])
		var g := 1.0 / (1.0 + pow(2.0 * f * tau, 2.0))
		ring(d, start, f, float(m[1]) * amp * g, float(m[2]), wrap)


## A burst of noise between `lo` and `hi` Hz, `attack` to its peak then dying at `decay` a second.
func burst(d: PackedFloat32Array, start: int, seconds: float, amp: float, decay: float, lo := 20.0, hi := 20000.0,
		wrap := false, attack := 0.0004) -> void:
	var size := d.size()
	if size == 0:
		return
	var n := int(seconds * R)
	var a := 0.0
	var b := 0.0
	var ka := k(hi)
	var kb := k(lo)
	var j := posmod(start, size) if wrap else start
	for i in n:
		if j >= size:
			if not wrap:
				return
			j = 0
		var t := float(i) / R
		a += (nz() - a) * ka
		b += (a - b) * kb
		if j >= 0:
			d[j] += (a - b) * amp * minf(t / attack, 1.0) * exp(-decay * t)
		j += 1


## Band-pass noise around `fc` (a state-variable filter; `q` small is narrow) shaped by an
## attack and decay.
func band(d: PackedFloat32Array, start: int, seconds: float, fc: float, q: float, amp: float, decay: float,
		attack := 0.001, wrap := false) -> void:
	var size := d.size()
	if size == 0:
		return
	var f := 2.0 * sin(PI * minf(fc, 9000.0) / R)
	var low := 0.0
	var bp := 0.0
	var n := int(seconds * R)
	var j := posmod(start, size) if wrap else start
	for i in n:
		if j >= size:
			if not wrap:
				return
			j = 0
		var t := float(i) / R
		low += f * bp
		var high := nz() - low - q * bp
		bp += f * high
		if j >= 0:
			d[j] += bp * q * amp * minf(t / attack, 1.0) * exp(-decay * t)
		j += 1


## An air bubble ringing in water (Minnaert resonance): a sine whose pitch rises as it dies.
func bubble(d: PackedFloat32Array, start: int, f: float, amp: float, decay: float, rise: float, wrap := false) -> void:
	var size := d.size()
	if size == 0:
		return
	var n := int(5.0 / decay * R)
	var ph := 0.0
	var j := posmod(start, size) if wrap else start
	for i in n:
		if j >= size:
			if not wrap:
				return
			j = 0
		var t := float(i) / R
		ph += f * (1.0 + rise * t) / R
		if j >= 0:
			d[j] += sin(TAU * ph) * amp * exp(-decay * t) * minf(t * 2000.0, 1.0)
		j += 1


## Joins the end of a loop onto its start: the last `seconds` fade into the first, and the
## result is that much shorter, so it plays round with no click.
func loopify(d: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var x := int(seconds * R)
	var n := d.size() - x
	var out := d.slice(0, n)
	for i in x:
		var a := float(i) / x
		out[i] = d[i] * sqrt(a) + d[n + i] * sqrt(1.0 - a)
	return out


## A frequency close to `f` that fits a whole number of cycles in `seconds`, so a steady tone
## loops seamlessly.
static func fit(f: float, seconds: float) -> float:
	return maxf(roundf(f * seconds), 1.0) / seconds


## A smooth periodic random curve, 0..1, with `bumps` raised sections over `n` samples.
func bumps(n: int, count: int, width_lo: float, width_hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for b in count:
		var at := rng.randi_range(0, n - 1)
		var w := int(rf(width_lo, width_hi) * R)
		var h := rf(0.6, 1.0)
		for i in range(-w, w):
			var x := float(i) / w
			var j := posmod(at + i, n)
			out[j] = maxf(out[j], h * 0.5 * (1.0 + cos(PI * x)))
	return out


func _level(sound: String, d: PackedFloat32Array) -> PackedFloat32Array:
	var key := sound
	if sound.begins_with("impact_"):
		key = "impact"
	var spec: Array = LEVELS.get(key, ["peak", 0.6])
	if sound.begins_with("step"):
		spec = ["peak", float(STEP_PEAK.get(sound.trim_prefix("step_") if sound != "step" else "concrete", 0.5))]
	if key == "impact":
		spec = ["peak", 0.8]
	var peak := 0.0
	var sum := 0.0
	for x in d:
		peak = maxf(peak, absf(x))
		sum += x * x
	if peak < 1e-6:
		return d
	var gain := 1.0
	if str(spec[0]) == "rms":
		gain = float(spec[1]) / sqrt(sum / d.size())
		gain = minf(gain, 0.97 / peak)
	else:
		gain = float(spec[1]) / peak
	for i in d.size():
		d[i] *= gain
	# A short fade at the very end of one-shots so nothing cuts off with a click.
	if not is_loop(sound):
		var f := mini(int(0.004 * R), d.size())
		for i in f:
			d[d.size() - 1 - i] *= float(i) / f
	return d


## Whether a sound is a loop (kept here so this file stands alone).
static func is_loop(sound: String) -> bool:
	return LOOP_SOUNDS.has(sound)


const LOOP_SOUNDS: Array[String] = ["ratchet", "scrub", "grinder", "spray", "spray_gun", "washer", "static", "jet", "pour",
	"screech", "door", "fan", "blast", "rain", "rain_roof", "changer", "dyno_roller", "compressor", "shaker", "hum_fluoro", "hum_led",
	"tone_shed", "tone_sales", "amb_out", "birds", "crickets", "amb_town"]


# ---------------------------------------------------------------------------- hand tools

## A socket ratchet being cranked: on each return stroke the pawl snaps over the teeth (every
## click the steel head ringing, with the pawl spring's faint boing), speeding up and slowing
## with the swing; on the drive stroke the bolt creaks round in its thread and the socket knocks.
func _ratchet() -> PackedFloat32Array:
	var d := buf(3.4)
	var n := d.size()
	var scale := rf(0.95, 1.05)
	var head := [[2850.0, 1.0, 220.0], [4620.0, 0.75, 300.0], [6750.0, 0.55, 380.0], [8900.0, 0.35, 480.0], [1780.0, 0.3, 160.0]]
	for m in head:
		m[0] = float(m[0]) * scale
	var t := 0.02
	while t < 3.4:
		var clicks := rng.randi_range(5, 9)
		var dur := rf(0.26, 0.42)
		var loud := rf(0.6, 1.0)
		for c in clicks:
			var u := (float(c) + rf(-0.1, 0.1)) / float(clicks - 1)
			u = clampf(u, 0.0, 1.0)
			# Teeth are evenly spaced in angle; the swing eases in and out (smoothstep), so the
			# time of each click is the inverse of that.
			var tc := t + dur * (0.5 - sin(asin(1.0 - 2.0 * u) / 3.0))
			var at := int(tc * R)
			var a := loud * rf(0.7, 1.0) * (0.6 + 0.4 * sin(PI * u))
			var modes := []
			for m in head:
				modes.append([float(m[0]) * rf(0.99, 1.01), float(m[1]) * rf(0.6, 1.0), float(m[2])])
			hit(d, at, modes, 0.00004, a * 0.5, true)
			burst(d, at, 0.003, a * 0.6, 1500.0, 2500.0, 16000.0, true)
			ring(d, at + int(0.0015 * R), rf(1050.0, 1200.0) * scale, a * 0.05, 45.0, true)
		t += dur + rf(0.04, 0.09)
		# The drive stroke: the socket takes up (a knock), then the bolt creaks round.
		var drive := rf(0.35, 0.6)
		var at2 := int(t * R)
		hit(d, at2, [[rf(380.0, 460.0), 0.5, 60.0], [rf(1300.0, 1500.0), 0.3, 120.0], [rf(3300.0, 3600.0), 0.2, 250.0]], 0.0002, 0.4, true)
		band(d, at2, drive, rf(500.0, 800.0), 0.25, rf(0.04, 0.09), 1.5, drive * 0.4, true)
		# A thread squeak now and then.
		if rng.randf() < 0.4:
			var sq := at2 + int(rf(0.05, drive * 0.6) * R)
			var f0 := rf(900.0, 1500.0)
			var ph := 0.0
			var ln := int(rf(0.06, 0.14) * R)
			for i in ln:
				var x := float(i) / ln
				ph += f0 * (1.0 + 0.15 * x + 0.04 * sin(TAU * 18.0 * x)) / R
				d[(sq + i) % n] += (sin(TAU * ph) + 0.4 * sin(TAU * 2.0 * ph)) * sin(PI * x) * 0.035
		t += drive + rf(0.03, 0.08)
	return d


## A stiff brush scrubbing: bristles flicking across the part (gritty bright noise in grains),
## brighter on the push stroke than the pull, a knock of the stock at each turn and a slurp of
## cleaner now and then.
func _scrub() -> PackedFloat32Array:
	var d := buf(3.2)
	var n := d.size()
	var t := 0.0
	var forward := true
	while t < 3.2:
		var dur := rf(0.2, 0.32)
		var at := int(t * R)
		var ln := int(dur * R)
		var fc := rf(3800.0, 5200.0) if forward else rf(2600.0, 3600.0)
		var amp := rf(0.7, 1.0) * (1.0 if forward else 0.75)
		var f := 2.0 * sin(PI * fc / R)
		var low := 0.0
		var bp := 0.0
		var grain := 0.0
		for i in ln:
			var x := float(i) / ln
			if rng.randf() < 0.02:
				grain = rf(0.4, 1.0)
			grain *= 0.995
			low += f * bp
			var high := nz() - low - 0.9 * bp
			bp += f * high
			var env := pow(sin(PI * x), 0.7)
			d[(at + i) % n] += bp * 0.5 * amp * env * (0.55 + 0.45 * grain)
		if rng.randf() < 0.5:
			hit(d, at + ln - int(0.01 * R), [[rf(180.0, 260.0), 0.4, 50.0], [rf(700.0, 900.0), 0.2, 90.0]], 0.002, 0.25, true)
		if rng.randf() < 0.25:
			bubble(d, at + int(ln * 0.5), rf(500.0, 900.0), 0.05, 60.0, 2.0, true)
		forward = not forward
		t += dur + rf(0.0, 0.03)
	return d


## An angle grinder cutting and grinding: the motor's whine and its gear mesh over the fan's
## rush, pulling down in pitch when the disc bites (the motor loads up), a harsh grinding rasp
## and a crackle of sparks while it's in contact, and back up again when it lifts.
func _grinder() -> PackedFloat32Array:
	var secs := 5.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var load := bumps(n, 4, 0.35, 0.8)
	# Shaft speed under load, then a disc frequency fitted so the tones loop round cleanly.
	var speed := PackedFloat32Array()
	speed.resize(n)
	var total := 0.0
	var lp := 0.0
	for i in n:
		lp += (load[i] - lp) * 0.0004
		speed[i] = 1.0 - 0.14 * lp
		total += speed[i]
	var disc := fit(185.0 * total / n, float(n) / R) * n / total
	var ph := 0.0
	var air_a := 0.0
	var air_a2 := 0.0
	var air_b := 0.0
	var grit_a := 0.0
	var grit_b := 0.0
	var spark := 0.0
	for i in n:
		var s := speed[i]
		ph += disc * s / R
		var p := TAU * ph
		var motor := sin(3.0 * p) * 0.35 + sin(6.0 * p) * 0.12 + sin(9.0 * p) * 0.05
		var gear := sin(11.0 * p) * 0.1 + sin(22.0 * p) * 0.04
		var hum := sin(p) * 0.18 + sin(2.0 * p) * 0.08
		air_a += (nz() - air_a) * 0.3
		air_a2 += (air_a - air_a2) * 0.3
		air_b += (air_a2 - air_b) * 0.02
		var air := (air_a2 - air_b) * 0.5 * s
		var scream := sin(33.0 * p) * 0.035 + sin(44.0 * p) * 0.02
		var l := load[i]
		grit_a += (nz() - grit_a) * 0.8
		grit_b += (grit_a - grit_b) * 0.08
		var rasp := (grit_a - grit_b) * l * (0.6 + 0.4 * sin(TAU * 3.0 * ph))
		if rng.randf() < 0.012 * l:
			spark = rf(0.4, 1.0)
		spark *= 0.82
		d[i] = (motor + gear) * (1.3 + 0.3 * s) + hum + scream + air + rasp * 0.8 + nz() * spark * 0.5
	return loopify(d, 0.1)


## A spray can (aerosol) or the spray gun: the nozzle's bright hiss with the propellant
## sputtering in it; the gun has the rush of the air cap under it and the fizz of paint.
func _spray(gun: bool) -> PackedFloat32Array:
	var d := buf(3.1)
	var n := d.size()
	var f := 2.0 * sin(PI * (rf(5500.0, 6500.0) if not gun else rf(3800.0, 4400.0)) / R)
	var low := 0.0
	var bp := 0.0
	var lp := 0.0
	var hp := 0.0
	var flutter := 0.0
	var air := 0.0
	var air2 := 0.0
	for i in n:
		var x := nz()
		low += f * bp
		var high := x - low - 0.6 * bp
		bp += f * high
		lp += (x - lp) * 0.8
		hp += (lp - hp) * 0.25
		flutter += (nz() - flutter) * 0.003
		var hiss := (lp - hp) * 0.45 + bp * 0.35
		if gun:
			air += (nz() - air) * 0.12
			air2 += (air - air2) * 0.01
			d[i] = hiss * (0.85 + 0.6 * flutter) + (air - air2) * 0.8
		else:
			d[i] = hiss * (0.8 + 1.2 * flutter)
	if not gun:
		# The can's sputter: little dropouts and spits.
		for s in 6:
			var at := rng.randi_range(0, n - 1)
			var ln := int(rf(0.01, 0.04) * R)
			for i in ln:
				d[(at + i) % n] *= 1.0 - 0.6 * sin(PI * float(i) / ln)
	return loopify(d, 0.1)


## Radio static: hiss with crackles.
func _static() -> PackedFloat32Array:
	var d := buf(2.1)
	var lp := 0.0
	for i in d.size():
		lp += (nz() - lp) * 0.55
		d[i] = lp * 0.5
	for c in 40:
		burst(d, rng.randi_range(0, d.size() - 1), 0.004, rf(0.3, 0.9), 900.0, 800.0, 12000.0, true)
	return loopify(d, 0.1)


## The parts washer: the pump's mains hum and impeller whine, the solvent stream splashing
## into the sink with bubbles in it, and the slow slosh in the tank.
func _washer() -> PackedFloat32Array:
	var secs := 5.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var whine := fit(330.0, secs)
	var a := 0.0
	var a2 := 0.0
	var b := 0.0
	var turb := 0.0
	var slosh := 0.0
	for i in n:
		var t := float(i) / R
		var hum := sin(TAU * 100.0 * t) * 0.3 + sin(TAU * 200.0 * t) * 0.1 + sin(TAU * 300.0 * t) * 0.04
		var imp := sin(TAU * whine * t) * 0.04
		a += (nz() - a) * 0.3
		a2 += (a - a2) * 0.3
		b += (a2 - b) * 0.04
		turb += (nz() - turb) * 0.002
		var stream := (a2 - b) * (0.7 + 2.0 * absf(turb))
		slosh += (nz() - slosh) * 0.004
		var swell := 0.5 + 0.5 * sin(TAU * 0.8 * t)
		d[i] = hum + imp + stream * 0.6 + slosh * swell * 1.5
	for k2 in 160:
		bubble(d, rng.randi_range(0, n - 1), rf(350.0, 1400.0), rf(0.02, 0.07), rf(50.0, 110.0), rf(1.0, 4.0), true)
	return loopify(d, 0.1)


## The pressure washer: the triplex pump's pulse and motor, a hard hiss of water at pressure
## (pulsing with the pump) and the spatter and drum of it hitting the bike.
func _jet() -> PackedFloat32Array:
	var secs := 4.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var pump := fit(72.5, secs)
	var a := 0.0
	var b := 0.0
	var c := 0.0
	var drum := 0.0
	var wander := 0.0
	for i in n:
		var t := float(i) / R
		var pp := fmod(pump * t, 1.0)
		var pulse := exp(-pp * 7.0)
		var motor := sin(TAU * 100.0 * t) * 0.08 + sin(TAU * pump * t) * 0.1 + sin(TAU * pump * 2.0 * t) * 0.05
		a += (nz() - a) * 0.75
		b += (a - b) * 0.15
		var hiss := (a - b) * (0.85 + 0.25 * pulse)
		c += (nz() - c) * 0.06
		wander += (nz() - wander) * 0.00005
		drum += (c - drum) * 0.3
		d[i] = hiss * 0.6 + motor + pulse * 0.12 * sin(TAU * 150.0 * t) + drum * (0.6 + 6.0 * absf(wander))
	for s in 700:
		burst(d, rng.randi_range(0, n - 1), 0.003, rf(0.05, 0.2), 1200.0, 1500.0, 12000.0, true)
	return loopify(d, 0.1)


## Fluid glugging out of a can: the stream's splash and an air bubble gulping back in.
func _pour() -> PackedFloat32Array:
	var d := buf(3.1)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	for i in n:
		a += (nz() - a) * 0.25
		b += (a - b) * 0.05
		d[i] = (a - b) * 0.35
	var t := 0.0
	while t < 3.0:
		var at := int(t * R)
		bubble(d, at, rf(160.0, 320.0), rf(0.35, 0.55), rf(14.0, 24.0), rf(1.0, 3.0), true)
		band(d, at, 0.12, rf(900.0, 1500.0), 0.5, 0.4, 25.0, 0.01, true)
		for k2 in 3:
			bubble(d, at + int(rf(0.02, 0.15) * R), rf(600.0, 1400.0), rf(0.05, 0.12), rf(60.0, 100.0), 3.0, true)
		t += rf(0.22, 0.34)
	return loopify(d, 0.1)


# ---------------------------------------------------------------------------- machines

## The roller door going up or down: its geared motor, the drive chain ticking, the slats
## knocking over the barrel one by one and the guides rumbling.
func _door() -> PackedFloat32Array:
	var secs := 3.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / R
		a += (nz() - a) * 0.08
		b += (a - b) * 0.01
		d[i] = sin(TAU * 100.0 * t) * 0.12 + sin(TAU * 450.0 * t) * 0.05 + (a - b) * 0.8
	var t2 := 0.0
	while t2 < secs:
		hit(d, int(t2 * R), [[rf(130.0, 180.0), 0.6, 30.0], [rf(380.0, 460.0), 0.4, 45.0], [rf(1100.0, 1500.0), 0.3, 80.0],
			[rf(2100.0, 2600.0), 0.15, 120.0]], 0.0006, rf(0.25, 0.45), true)
		t2 += rf(0.24, 0.3)
	var t3 := 0.0
	while t3 < secs:
		burst(d, int(t3 * R), 0.004, rf(0.05, 0.12), 900.0, 1500.0, 9000.0, true)
		t3 += 1.0 / 9.0 + rf(-0.005, 0.005)
	return loopify(d, 0.1)


## The dyno room's big cooling fan: the blades chopping the air (a rush pulsing at the blade
## rate), its tonal hum, the motor and a faint bearing whine.
func _fan() -> PackedFloat32Array:
	var secs := 3.0
	var d := buf(secs + 0.1)
	var bpf := fit(40.0, secs)
	var a := 0.0
	var b := 0.0
	for i in d.size():
		var t := float(i) / R
		a += (nz() - a) * 0.12
		b += (a - b) * 0.006
		var chop := 0.7 + 0.3 * pow(0.5 + 0.5 * sin(TAU * bpf * t), 2.0)
		d[i] = (a - b) * 0.7 * chop + sin(TAU * bpf * t) * 0.06 + sin(TAU * bpf * 2.0 * t) * 0.03 \
			+ sin(TAU * 100.0 * t) * 0.04 + sin(TAU * 1850.0 * t) * 0.006
	return loopify(d, 0.1)


## The sandblaster: the nozzle's roar of air, the hiss of grit blasting metal (thousands of
## tiny hits), the steel cabinet droning with it, and now and then a bigger chip pinging off.
func _blast() -> PackedFloat32Array:
	var secs := 4.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	var g := 0.0
	var gb := 0.0
	var cab := [[0.0, 0.0, 2.0 * sin(PI * 140.0 / R)], [0.0, 0.0, 2.0 * sin(PI * 235.0 / R)], [0.0, 0.0, 2.0 * sin(PI * 372.0 / R)]]
	var swell := 0.0
	for i in n:
		var x := nz()
		a += (x - a) * 0.6
		b += (a - b) * 0.03
		var roar := a - b
		g += (nz() - g) * 0.95
		gb += (g - gb) * 0.45
		swell += (nz() - swell) * 0.0005
		var grit := (g - gb) * (0.6 + 0.4 * absf(nz())) * (0.9 + 3.0 * absf(swell))
		var res := 0.0
		for c in cab:
			c[0] += float(c[2]) * float(c[1])
			var hi := roar * 0.05 - float(c[0]) - 0.05 * float(c[1])
			c[1] = float(c[1]) + float(c[2]) * hi
			res += float(c[1])
		d[i] = roar * 0.55 + grit * 0.5 + res * 0.4
	for s in 50:
		hit(d, rng.randi_range(0, n - 1), [[rf(2200.0, 4200.0), 1.0, 300.0], [rf(5000.0, 7000.0), 0.5, 500.0]], 0.00005, rf(0.08, 0.2), true)
	return loopify(d, 0.1)


## The tyre changer working a tyre on or off: the turntable's geared motor whining, rubber
## groaning as the bead stretches, the lever scraping round the rim and the odd squeak.
func _changer() -> PackedFloat32Array:
	var secs := 4.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var whine := fit(720.0, secs)
	var a := 0.0
	var b := 0.0
	var strain := bumps(n, 3, 0.4, 0.9)
	var ph := 0.0
	for i in n:
		var t := float(i) / R
		var motor := sin(TAU * 100.0 * t) * 0.15 + sin(TAU * 48.0 * t) * 0.1 + sin(TAU * whine * t) * 0.06 + sin(TAU * whine * 2.0 * t) * 0.02
		a += (nz() - a) * 0.15
		b += (a - b) * 0.15
		var s := strain[i]
		ph += (85.0 + 50.0 * s + 12.0 * sin(TAU * 0.75 * t)) / R
		var groan := (fmod(ph, 1.0) - 0.5) * s * 0.25
		d[i] = motor + b * (0.4 + 0.6 * s) + groan
	for q in 5:
		var at := rng.randi_range(0, n - 1)
		var f0 := rf(900.0, 1600.0)
		var ln := int(rf(0.08, 0.2) * R)
		var p2 := 0.0
		for i in ln:
			var x := float(i) / ln
			p2 += f0 * (1.0 + rf(-0.02, 0.02) + 0.3 * x) / R
			d[(at + i) % n] += sin(TAU * p2) * sin(PI * x) * 0.1
	return loopify(d, 0.1)


## The dyno's drum turning under a tyre, at about 60 km/h (Sfx pitches it with the drum's
## speed): the knurled drum's whine, tread roar and the bearing's hum.
func _dyno_roller() -> PackedFloat32Array:
	var secs := 3.0
	var d := buf(secs + 0.1)
	var rot := fit(8.3, secs)
	var a := 0.0
	var b := 0.0
	var f := 2.0 * sin(PI * 900.0 / R)
	var low := 0.0
	var bp := 0.0
	for i in d.size():
		var t := float(i) / R
		var p := TAU * rot * t
		var knurl := sin(12.0 * p) * 0.2 + sin(24.0 * p) * 0.08 + sin(36.0 * p) * 0.03
		var shaft := sin(p) * 0.1 + sin(2.0 * p) * 0.05
		low += f * bp
		var hi := nz() - low - 0.5 * bp
		bp += f * hi
		a += (nz() - a) * 0.05
		b += (a - b) * 0.005
		d[i] = knurl + shaft + bp * 0.25 * (0.85 + 0.15 * sin(12.0 * p)) + (a - b) * 0.8 + sin(TAU * 290.0 * rot * t) * 0.01
	return loopify(d, 0.1)


## The air compressor running: a two-cylinder pump thumping at crank speed, each stroke a
## knock of the pistons and a valve tick, over the motor's hum and the belt's flap.
func _compressor() -> PackedFloat32Array:
	var secs := 3.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var crank := fit(18.0, secs)
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / R
		a += (nz() - a) * 0.1
		b += (a - b) * 0.01
		d[i] = sin(TAU * 100.0 * t) * 0.07 + sin(TAU * 50.0 * t) * 0.05 + (a - b) * 0.25 * (0.8 + 0.2 * sin(TAU * crank * t))
	var strokes := int(crank * secs) * 2
	for s in strokes:
		var at := int((float(s) / (crank * 2.0) + rf(-0.002, 0.002)) * R)
		var amp := rf(0.8, 1.0)
		hit(d, at, [[rf(62.0, 72.0), 1.0, 22.0], [rf(140.0, 160.0), 0.5, 35.0], [rf(420.0, 480.0), 0.25, 60.0]], 0.002, amp * 0.6, true)
		ring(d, at + int(0.01 * R), rf(2600.0, 3200.0), amp * 0.06, 300.0, true)
		burst(d, at, 0.03, amp * 0.15, 60.0, 200.0, 1500.0, true, 0.005)
	return loopify(d, 0.1)


## The paint shaker running: the motor's whirr and the whine of its gearbox, over the rumble of
## the clamp swinging the tin round on its eccentric (a few times a second, the paint sloshing
## and the lid chattering with each swing) and a rattle of the cage on its springs.
func _shaker() -> PackedFloat32Array:
	var secs := 4.0
	var d := buf(secs + 0.1)
	var n := d.size()
	var rotor := fit(48.0, secs)
	var swing := fit(9.5, secs)
	var a := 0.0
	var a2 := 0.0
	var b := 0.0
	var slosh := 0.0
	var chat := 0.0
	var wob := 0.0
	for i in n:
		var t := float(i) / R
		wob += (nz() - wob) * 0.0005
		var p := TAU * rotor * t
		# The motor: a whirr in its harmonics, the gear mesh's whine riding on it.
		var motor := sin(p) * 0.22 + sin(2.0 * p) * 0.16 + sin(3.0 * p) * 0.08 + sin(5.0 * p) * 0.04
		var whine := (sin(23.0 * p) * 0.05 + sin(46.0 * p) * 0.015) * (1.0 + wob * 3.0)
		# Air through the fan blades and the housing.
		a += (nz() - a) * 0.25
		a2 += (a - a2) * 0.25
		b += (a2 - b) * 0.015
		var air := (a2 - b) * 0.35
		# The tin swinging round: a low throb, and the paint sloshing with each swing.
		var s := sin(TAU * swing * t)
		var throb := s * 0.18 + sin(2.0 * TAU * swing * t) * 0.06
		slosh += (nz() - slosh) * 0.01
		var sw := maxf(0.0, s)
		d[i] = motor + whine + air + throb + slosh * (0.5 + 1.5 * sw * sw) * 0.9
		# The lid and cage chattering at the end of each swing.
		chat *= 0.996
		d[i] += chat * nz()
	var swings := int(swing * secs)
	for k in swings:
		var at := int((float(k) / swing + 0.25 / swing + rf(-0.004, 0.004)) * R)
		hit(d, at, [[rf(380.0, 460.0), 0.6, 45.0], [rf(1300.0, 1700.0), 0.3, 90.0], [rf(3200.0, 3800.0), 0.15, 160.0]], 0.0008, rf(0.06, 0.12), true)
	return loopify(d, 0.1)


## The ceiling lights: a fluorescent's magnetic ballast humming at twice the mains frequency
## with a buzzy edge, or an LED driver's faint high whine.
func _hum(led: bool) -> PackedFloat32Array:
	var secs := 3.0
	var d := buf(secs + 0.1)
	var a := 0.0
	var flutter := 0.0
	# One cycle of the ballast's buzz (100 Hz and its harmonics, the odd ones weaker), repeated.
	var period := PackedFloat32Array()
	period.resize(int(R / 100.0))
	for i in period.size():
		var t := float(i) / R
		for h in 12:
			period[i] += sin(TAU * 100.0 * (h + 1) * t + h) / pow(h + 1.0, 1.1 if h % 2 == 0 else 1.4)
	for i in d.size():
		var t := float(i) / R
		flutter += (nz() - flutter) * 0.0004
		if led:
			d[i] = sin(TAU * 9600.0 * t) * 0.03 + sin(TAU * 100.0 * t) * 0.15 + sin(TAU * 200.0 * t) * 0.05 + nz() * 0.004
		else:
			a += (nz() - a) * 0.4
			d[i] = period[i % period.size()] * (0.95 + 2.0 * flutter) * 0.3 + a * 0.01 * (1.0 + period[i % period.size()])
	return loopify(d, 0.1)


## Room tone: the low rumble of a building (traffic and machinery far off through the
## ground), a breath of moving air and, in the shed, the odd tick of the steel roof. The
## showroom's is the air conditioning's soft rush instead.
func _room_tone(hvac: bool) -> PackedFloat32Array:
	var secs := 10.0
	var d := buf(secs + 0.2)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	var c := 0.0
	for i in n:
		var t := float(i) / R
		a += (nz() - a) * 0.01
		b += (nz() - b) * (0.2 if hvac else 0.05)
		c += (b - c) * 0.02
		d[i] = a * 2.5 + (b - c) * (0.5 if hvac else 0.2) + sin(TAU * 50.0 * t) * 0.01 + (sin(TAU * 160.0 * t) * 0.01 if hvac else 0.0)
	if not hvac:
		for s in 4:
			hit(d, rng.randi_range(0, n - 1), [[rf(400.0, 900.0), 0.6, 40.0], [rf(1500.0, 2500.0), 0.3, 80.0]], 0.001, rf(0.05, 0.12), true)
	return loopify(d, 0.2)


## Outside: wind in the trees coming and going, and traffic on a road somewhere beyond the
## fields: a steady murmur with now and then a car or lorry passing.
func _outdoors() -> PackedFloat32Array:
	var secs := 12.0
	var d := buf(secs + 0.3)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	var c := 0.0
	var e := 0.0
	var m1 := rf(0.0, TAU)
	var m2 := rf(0.0, TAU)
	for i in n:
		var t := float(i) / R
		var gust := 0.55 + 0.25 * sin(TAU * t / secs + m1) + 0.2 * sin(TAU * 3.0 * t / secs + m2)
		a += (nz() - a) * 0.02
		b += (nz() - b) * 0.5
		c += (b - c) * 0.1
		e += (nz() - e) * 0.006
		d[i] = a * 1.4 * gust + (b - c) * 0.05 * gust * gust + e * 2.2
	# Passing vehicles: a swell of tyre roar and engine drone, falling in pitch as it passes.
	for v in 3:
		var mid := rng.randi_range(0, n - 1)
		var half := int(rf(2.0, 3.5) * R)
		var lorry := rng.randf() < 0.35
		var f0 := rf(70.0, 110.0) if lorry else rf(110.0, 170.0)
		var ph := 0.0
		var lo := 0.0
		var bp := 0.0
		var amp := rf(0.15, 0.3)
		for i in range(-half, half):
			var x := float(i) / half
			var env := exp(-x * x * 5.0)
			var doppler := 1.0 - 0.06 * tanh(x * 3.0)
			ph += f0 * doppler / R
			var f := 2.0 * sin(PI * 600.0 * doppler / R)
			lo += f * bp
			var hi := nz() - lo - 0.8 * bp
			bp += f * hi
			d[posmod(mid + i, n)] += (bp * 0.6 + sin(TAU * ph) * 0.3 + sin(TAU * 2.0 * ph) * 0.1) * env * amp
	return loopify(d, 0.3)


## The town's bustle out on the High Street: people talking as they pass (bursts of voice-like
## formants in syllables and phrases, near and far), footsteps going by, a shop door's bell now
## and then and the pigeons cooing.
func _town() -> PackedFloat32Array:
	var secs := 12.0
	var d := buf(secs + 0.3)
	var n := d.size()
	for voice in 5:
		var near := rf(0.35, 1.0)
		var f1 := rf(330.0, 520.0) if voice % 2 == 0 else rf(480.0, 720.0)
		var t := rf(0.0, 2.0)
		while t < secs:
			var syllables := rng.randi_range(3, 9)
			for k2 in syllables:
				var ln := rf(0.07, 0.19)
				var at := int(t * R)
				var f := f1 * rf(0.85, 1.25)
				band(d, at, ln, f, 0.35, 0.06 * near, 9.0, 0.025, true)
				band(d, at, ln * 0.8, f * rf(2.2, 2.8), 0.4, 0.025 * near, 12.0, 0.02, true)
				t += ln + rf(0.03, 0.12)
			t += rf(0.6, 2.5)
	# Footsteps of people walking past.
	for walker in 3:
		var t2 := rf(0.0, secs)
		var pace := rf(0.48, 0.6)
		for step in rng.randi_range(6, 12):
			var loud := sin(PI * float(step) / 12.0) * 0.05
			burst(d, int((t2 + step * pace) * R), 0.035, loud, 140.0, 900.0, 5000.0, true)
	# A shop door's bell.
	for b in 2:
		var at2 := rng.randi_range(0, n - 1)
		ring(d, at2, 2650.0, 0.02, 5.0, true)
		ring(d, at2 + int(0.18 * R), 3120.0, 0.014, 6.0, true)
	# Pigeons: roo-COO-coo, low and soft.
	for c in 3:
		var start := rng.randi_range(0, n - 1)
		var f0 := rf(250.0, 320.0)
		var ph := 0.0
		for note: Array in [[0.0, 0.22, 0.6], [0.3, 0.42, 1.0], [0.8, 0.3, 0.7]]:
			var o := int(float(note[0]) * R)
			var ln2 := int(float(note[1]) * R)
			for i in ln2:
				var x := float(i) / ln2
				ph += f0 * (1.0 + 0.04 * sin(TAU * 7.0 * x)) * (1.0 - 0.1 * x) / R
				d[(start + o + i) % n] += sin(TAU * ph) * sin(PI * x) * 0.03 * float(note[2])
	return loopify(d, 0.3)


## Birdsong for daytime: a few birds at different distances, each with its own call (quick
## chirps, a warble, a fluting two-note whistle, a rising tweet).
func _birds() -> PackedFloat32Array:
	var secs := 16.0
	var d := buf(secs)
	var n := d.size()
	var birds := rng.randi_range(4, 6)
	for bird in birds:
		var kind := bird % 4
		var dist := rf(0.25, 1.0)
		var base := rf(2600.0, 4200.0)
		var t := rf(0.0, 3.0)
		while t < secs:
			var phrase := rng.randi_range(2, 6)
			for s in phrase:
				var at := int(t * R)
				var ln := 0.0
				match kind:
					0:
						ln = rf(0.035, 0.06)
						_syllable(d, at, ln, base * 1.3, base * 0.85, 0.0, 0.0, dist)
						t += ln + rf(0.05, 0.09)
					1:
						ln = rf(0.2, 0.35)
						_syllable(d, at, ln, base, base, base * 0.18, rf(20.0, 35.0), dist)
						t += ln + rf(0.08, 0.2)
					2:
						ln = rf(0.18, 0.3)
						_syllable(d, at, ln, base * 0.6, base * 0.62, base * 0.01, 7.0, dist)
						_syllable(d, at + int(ln * R), ln * 0.8, base * 0.78, base * 0.75, base * 0.01, 7.0, dist)
						t += ln * 1.8 + rf(0.3, 0.6)
					_:
						ln = rf(0.05, 0.09)
						_syllable(d, at, ln, base * 0.6, base * 1.4, 0.0, 0.0, dist)
						t += ln + rf(0.1, 0.18)
			t += rf(1.5, 5.0)
	return d


## One bird syllable: a pure tone gliding from `f0` to `f1`, with `fm` Hz of trill at `rate`.
func _syllable(d: PackedFloat32Array, start: int, seconds: float, f0: float, f1: float, fm: float, rate: float, amp: float) -> void:
	var n := d.size()
	var ln := int(seconds * R)
	var ph := 0.0
	for i in ln:
		var x := float(i) / ln
		var f := lerpf(f0, f1, x) + fm * sin(TAU * rate * x * seconds)
		ph += f / R
		var env := pow(sin(PI * x), 1.5)
		d[(start + i) % n] += (sin(TAU * ph) + 0.12 * sin(TAU * 2.0 * ph)) * env * amp


## Crickets at night: several, each chirping its own pulses at its own pitch, one trilling.
func _crickets() -> PackedFloat32Array:
	var secs := 8.0
	var d := buf(secs)
	var n := d.size()
	for c in rng.randi_range(4, 6):
		var f := rf(4200.0, 5200.0)
		var amp := rf(0.2, 1.0)
		var trill := c == 0
		var t := rf(0.0, 0.8)
		var pulses := rng.randi_range(3, 4)
		var gap := rf(0.45, 0.9)
		while t < secs:
			var count := 30 if trill else pulses
			for p in count:
				var at := int((t + p * (0.02 if trill else 0.032)) * R)
				var ln := int(0.014 * R)
				for i in ln:
					var x := float(i) / ln
					d[(at + i) % n] += sin(TAU * f * float(i) / R) * sin(PI * x) * amp * 0.5
			t += (count * 0.02 + rf(1.0, 2.5)) if trill else gap + rf(-0.05, 0.05)
	return d


## Rain. Outside, a wash of fine drops (each a tick, some a bubble in a puddle). On the roof,
## heard from inside, the steel sheets drum: a low roar with drops ringing the sheet, and the
## gutter trickling.
func _rain(roof: bool) -> PackedFloat32Array:
	var secs := 6.0
	var d := buf(secs + 0.2)
	var n := d.size()
	var a := 0.0
	var b := 0.0
	for i in n:
		a += (nz() - a) * (0.08 if roof else 0.6)
		b += (a - b) * (0.01 if roof else 0.08)
		d[i] = (a - b) * (0.9 if roof else 0.35)
	var drops := 900 if roof else 1800
	for k2 in drops:
		var at := rng.randi_range(0, n - 1)
		if roof:
			ring(d, at, rf(900.0, 3200.0), rf(0.01, 0.05), rf(120.0, 220.0), true)
		else:
			burst(d, at, 0.002, rf(0.03, 0.12), 2500.0, 2000.0, 14000.0, true)
	if roof:
		for k3 in 120:
			bubble(d, rng.randi_range(0, n - 1), rf(500.0, 1100.0), rf(0.01, 0.03), 70.0, 2.0, true)
	else:
		for k3 in 200:
			bubble(d, rng.randi_range(0, n - 1), rf(900.0, 3000.0), rf(0.01, 0.04), rf(80.0, 160.0), rf(2.0, 6.0), true)
	return loopify(d, 0.2)


# ---------------------------------------------------------------------------- one-shots

## A spanner or bolt dropping onto the floor: a small steel bar's modes (free-free bar
## ratios, slightly out of true) ringing, and a bounce or two.
func _clink() -> PackedFloat32Array:
	var d := buf(0.7)
	var f0 := rf(1700.0, 3200.0)
	var modes := []
	for r in [1.0, 2.756, 5.404, 8.933]:
		modes.append([f0 * float(r) * rf(0.98, 1.02), rf(0.5, 1.0) / sqrt(float(r)), rf(7.0, 12.0) * pow(float(r), 0.7)])
	modes.append([f0 * rf(1.4, 1.9), rf(0.3, 0.6), rf(10.0, 18.0)])
	var at := 0
	var amp := 1.0
	var gap := rf(0.05, 0.12)
	for bounce in rng.randi_range(1, 3):
		hit(d, at, modes, 0.00006, amp * 0.5)
		burst(d, at, 0.004, amp * 0.5, 1200.0, 1500.0, 16000.0)
		at += int(gap * R)
		gap *= rf(0.4, 0.6)
		amp *= rf(0.3, 0.5)
	return d


## A heavy part going on or down: a low thump with a hollow body ring and a short clank.
func _clunk() -> PackedFloat32Array:
	var d := buf(0.55)
	hit(d, 0, [[rf(70.0, 110.0), 1.0, 18.0], [rf(180.0, 260.0), 0.6, 26.0], [rf(380.0, 520.0), 0.4, 40.0],
		[rf(900.0, 1300.0), 0.3, 60.0], [rf(1900.0, 2600.0), 0.2, 90.0], [rf(3100.0, 3800.0), 0.12, 140.0]], 0.0004, 0.9)
	burst(d, 0, 0.03, 0.4, 150.0, 200.0, 5000.0)
	if rng.randf() < 0.6:
		var at := int(rf(0.03, 0.08) * R)
		hit(d, at, [[rf(1200.0, 2000.0), 0.4, 50.0], [rf(2600.0, 3600.0), 0.3, 80.0]], 0.0002, 0.25)
	return d


## Lifting something: a hand closing on it, the cloth of a glove, and whatever's loose on it
## jingling.
func _pickup() -> PackedFloat32Array:
	var d := buf(0.3)
	burst(d, 0, 0.12, 0.6, 30.0, 300.0, 3000.0, false, 0.01)
	hit(d, int(rf(0.0, 0.02) * R), [[rf(140.0, 220.0), 0.6, 40.0], [rf(500.0, 800.0), 0.3, 70.0]], 0.002, 0.5)
	for j in rng.randi_range(1, 3):
		ring(d, int(rf(0.01, 0.08) * R), rf(2200.0, 4500.0), rf(0.05, 0.15), rf(40.0, 80.0))
	return d


## A part landing in the scrap bin: it hits the steel bin's side and floor (big, slow
## ringing modes) and clatters about among the other scrap.
func _scrap() -> PackedFloat32Array:
	var d := buf(1.1)
	var bin := []
	for f in [155.0, 240.0, 410.0, 630.0, 890.0, 1270.0, 1840.0]:
		bin.append([float(f) * rf(0.95, 1.05), rf(0.4, 1.0), rf(5.0, 9.0) * pow(float(f) / 155.0, 0.4)])
	var t := 0.0
	var amp := 1.0
	for h in rng.randi_range(3, 6):
		var at := int(t * R)
		hit(d, at, bin, 0.0003, amp * 0.6)
		var f0 := rf(700.0, 2200.0)
		hit(d, at, [[f0, 1.0, 20.0], [f0 * 2.76, 0.5, 40.0], [f0 * rf(1.3, 1.7), 0.4, 35.0]], 0.0001, amp * 0.4)
		burst(d, at, 0.005, amp * 0.4, 800.0, 1000.0, 12000.0)
		t += rf(0.04, 0.15)
		amp *= rf(0.4, 0.75)
	return d


## A wall switch: the toggle's snap (two quick clicks of the mechanism) in its plastic box.
func _switch() -> PackedFloat32Array:
	var d := buf(0.12)
	for c in 2:
		var at := int((0.002 + c * rf(0.004, 0.009)) * R)
		var a := 1.0 if c == 0 else rf(0.4, 0.7)
		hit(d, at, [[rf(2800.0, 4200.0), 0.8, 500.0], [rf(6000.0, 8000.0), 0.4, 800.0], [rf(900.0, 1300.0), 0.6, 200.0]], 0.00005, a * 0.7)
		burst(d, at, 0.002, a * 0.4, 1500.0, 1000.0, 15000.0)
	return d


## A bright little metal ting (XP and the contract pin).
func _ting() -> PackedFloat32Array:
	var d := buf(0.6)
	var f0 := rf(2950.0, 3250.0)
	hit(d, 0, [[f0, 1.0, 7.0], [f0 * 1.502, 0.6, 9.0], [f0 * 2.23, 0.4, 13.0], [f0 * 2.9, 0.2, 18.0]], 0.00005, 0.8)
	burst(d, 0, 0.003, 0.3, 1500.0, 2000.0, 15000.0)
	return d


## The sandblaster's scan going on: a soft electronic sweep up, two quick blips at the top.
func _blast_scan() -> PackedFloat32Array:
	var d := buf(0.55)
	var phase := 0.0
	for i in int(0.32 * R):
		var t := float(i) / R
		var f := lerpf(500.0, 1800.0, t / 0.32)
		phase += TAU * f / R
		d[i] += sin(phase) * 0.35 * minf(1.0, t * 40.0) * (1.0 - t / 0.32 * 0.4)
	for k in 2:
		ring(d, int((0.34 + k * 0.09) * R), 2400.0, 0.3, 30.0)
	return d


## A footstep on `surface`: the heel strike and then the toe a moment later, each sounding
## the way that floor does, with the scuff and scatter that go with it.
func _step(surface: String) -> PackedFloat32Array:
	var d := buf(0.36)
	var heel := int(rf(0.002, 0.008) * R)
	var toe := heel + int(rf(0.05, 0.09) * R)
	var toe_amp := rf(0.4, 0.7)
	for c in 2:
		var at := heel if c == 0 else toe
		var a := 1.0 if c == 0 else toe_amp
		match surface:
			"concrete", "epoxy", "tarmac":
				var bright := 6500.0 if surface == "epoxy" else (4200.0 if surface == "tarmac" else 5200.0)
				burst(d, at, 0.03, a * 0.6, 170.0, 250.0, bright)
				ring(d, at, rf(95.0, 130.0), a * 0.35, 45.0)
				var grains := rng.randi_range(2, 6) if surface != "tarmac" else rng.randi_range(6, 12)
				for g in grains:
					burst(d, at + int(rf(0.0, 0.04) * R), 0.0015, a * rf(0.03, 0.08), 2000.0, 3000.0, 14000.0)
			"tile":
				burst(d, at, 0.02, a * 0.7, 260.0, 300.0, 9000.0)
				ring(d, at, rf(2200.0, 3400.0), a * 0.08, 120.0)
				ring(d, at, rf(130.0, 160.0), a * 0.3, 55.0)
			"wood":
				band(d, at, 0.04, rf(600.0, 900.0), 0.6, a * 0.7, 90.0)
				hit(d, at, [[rf(90.0, 120.0), 0.6, 22.0], [rf(180.0, 230.0), 0.45, 30.0], [rf(330.0, 420.0), 0.3, 45.0]], 0.002, a * 0.9)
			"metal":
				burst(d, at, 0.02, a * 0.4, 200.0, 300.0, 8000.0)
				var modes := []
				for f in [180.0, 310.0, 470.0, 730.0, 1150.0, 1600.0]:
					modes.append([float(f) * rf(0.92, 1.08), rf(0.4, 1.0), rf(10.0, 20.0)])
				hit(d, at, modes, 0.0008, a * 0.5)
				if c == 1 and rng.randf() < 0.5:
					hit(d, at + int(rf(0.02, 0.05) * R), [[rf(1200.0, 2400.0), 0.5, 60.0]], 0.0001, 0.15)
			"gravel":
				burst(d, at, 0.06, a * 0.35, 40.0, 60.0, 400.0)
				var count := rng.randi_range(50, 110)
				for g in count:
					var gt := absf(rng.randfn(0.0, 0.05))
					ring(d, at + int(gt * R), rf(1500.0, 6000.0), a * rf(0.02, 0.1) * exp(-gt * 10.0), 800.0)
			"grass":
				burst(d, at, 0.15, a * 0.35, 18.0, 600.0, 3500.0, false, 0.02)
				burst(d, at, 0.06, a * 0.3, 35.0, 40.0, 250.0)
			"puddle":
				band(d, at, 0.2, rf(1100.0, 1800.0), 0.9, a * 0.7, 22.0, 0.003)
				burst(d, at, 0.05, a * 0.3, 40.0, 40.0, 300.0)
				for b in rng.randi_range(6, 12):
					bubble(d, at + int(rf(0.0, 0.12) * R), rf(500.0, 2200.0), a * rf(0.08, 0.2), rf(40.0, 80.0), rf(1.0, 4.0))
			"carpet":
				burst(d, at, 0.06, a * 0.6, 50.0, 40.0, 400.0)
				ring(d, at, rf(80.0, 100.0), a * 0.3, 40.0)
				burst(d, at, 0.04, a * 0.05, 60.0, 1500.0, 5000.0, false, 0.005)
	# The scuff of the sole leaving the floor, or a squeak of rubber on epoxy.
	if surface in ["concrete", "tarmac", "tile", "wood"] and rng.randf() < 0.5:
		band(d, toe + int(0.03 * R), 0.06, rf(2000.0, 3200.0), 0.8, rf(0.05, 0.1), 30.0, 0.01)
	if surface == "epoxy" and rng.randf() < 0.35:
		var at2 := toe + int(0.01 * R)
		var ln := int(rf(0.03, 0.05) * R)
		var ph := 0.0
		var f0 := rf(1700.0, 2400.0)
		for i in ln:
			var x := float(i) / ln
			ph += f0 * (1.0 + 0.4 * x) / R
			if at2 + i < d.size():
				d[at2 + i] += (sin(TAU * ph) + 0.3 * sin(TAU * 2.0 * ph)) * sin(PI * x) * 0.1
	if surface == "wood" and rng.randf() < 0.2:
		_stick_slip(d, toe, rf(0.1, 0.2), rf(180.0, 320.0), 0.08)
	return d


## A creak: wood or metal sticking and slipping, a train of little jerks whose rate wanders.
func _stick_slip(d: PackedFloat32Array, start: int, seconds: float, rate: float, amp: float) -> void:
	var t := 0.0
	while t < seconds:
		var x := t / seconds
		var at := start + int(t * R)
		ring(d, at, rf(900.0, 1400.0), amp * sin(PI * x), 400.0)
		ring(d, at, rf(300.0, 450.0), amp * 0.6 * sin(PI * x), 150.0)
		t += 1.0 / (rate * (1.0 + 0.4 * sin(TAU * x * 1.5)))


## A part or a box dropped onto a surface. The object (its material decides its modes, how
## hard its contact is and how it bounces) and the surface both ring from each contact.
func _impact(material: String, surface: String) -> PackedFloat32Array:
	var d := buf(1.0)
	var obj := []
	var tau := 0.0002
	var bounce := 0.4
	var obj_amp := 1.0
	match material:
		"metal":
			var f0 := rf(500.0, 1500.0)
			for r in [1.0, 2.756, 5.404, 8.933]:
				obj.append([f0 * float(r) * rf(0.97, 1.03), rf(0.5, 1.0) / sqrt(float(r)), rf(6.0, 12.0) * pow(float(r), 0.6)])
			for p in 3:
				obj.append([f0 * rf(1.3, 4.5), rf(0.2, 0.5), rf(10.0, 25.0)])
			obj.append([rf(90.0, 180.0), 0.6, 40.0])
			tau = 0.00012
			bounce = 0.45
		"plastic":
			var f0 := rf(250.0, 700.0)
			for r in [1.0, rf(1.6, 1.9), rf(2.5, 3.2), rf(4.0, 5.0)]:
				obj.append([f0 * float(r), rf(0.5, 1.0), rf(35.0, 60.0) * sqrt(float(r))])
			tau = 0.0005
			bounce = 0.35
			obj_amp = 0.8
		"rubber":
			obj = [[rf(70.0, 110.0), 1.0, 18.0], [rf(160.0, 220.0), 0.6, 25.0], [rf(300.0, 360.0), 0.3, 40.0]]
			tau = 0.005
			bounce = 0.55
		"soft":
			obj = [[rf(80.0, 110.0), 0.8, 30.0], [rf(200.0, 260.0), 0.3, 50.0]]
			tau = 0.008
			bounce = 0.0
			obj_amp = 0.8
		"cardboard":
			obj = [[rf(110.0, 170.0), 1.0, 25.0], [rf(300.0, 450.0), 0.5, 50.0], [rf(700.0, 900.0), 0.2, 80.0]]
			tau = 0.002
			bounce = 0.15
	# The surface softens the contact and damps the ring once the thing lies on it.
	var damp := 1.0
	match surface:
		"concrete":
			damp = 1.5
		"wood":
			tau *= 2.5
			damp = 2.2
			bounce *= 0.7
		"steel":
			damp = 1.2
			bounce *= 1.1
		"ground":
			tau *= 6.0
			damp = 4.0
			bounce *= 0.2
	for m in obj:
		m[2] = float(m[2]) * damp
	var at := 0
	var amp := 1.0
	var gap := rf(0.07, 0.14) * (bounce / 0.45)
	var hard := material in ["metal", "plastic"]
	var contacts := 1 if bounce < 0.1 else rng.randi_range(2, 4)
	for c in contacts:
		if at >= d.size():
			break
		hit(d, at, obj, tau, amp * 0.7 * obj_amp)
		match surface:
			"concrete":
				burst(d, at, 0.012, amp * (0.45 if hard else 0.2), 500.0, 300.0, 9000.0 if hard else 2500.0)
				ring(d, at, rf(65.0, 90.0), amp * 0.25, 60.0)
				if hard:
					for g in rng.randi_range(2, 5):
						burst(d, at + int(rf(0.0, 0.03) * R), 0.0015, amp * rf(0.04, 0.1), 2000.0, 3000.0, 14000.0)
			"wood":
				hit(d, at, [[rf(140.0, 180.0), 0.6, 25.0], [rf(260.0, 320.0), 0.5, 32.0], [rf(410.0, 520.0), 0.35, 40.0],
					[rf(700.0, 900.0), 0.2, 50.0]], tau, amp * 0.7)
				burst(d, at, 0.02, amp * 0.25, 250.0, 200.0, 2500.0)
				if hard and c == 0:
					for g in rng.randi_range(1, 2):
						ring(d, at + int(rf(0.01, 0.04) * R), rf(2000.0, 6000.0), amp * 0.04, 80.0)
			"steel":
				var sheet := []
				for f in [220.0, 370.0, 610.0, 890.0, 1340.0, 1990.0, 2850.0]:
					sheet.append([float(f) * rf(0.95, 1.05), rf(0.3, 1.0), rf(6.0, 14.0)])
				hit(d, at, sheet, tau, amp * 0.45)
				if c == 0:
					for g in rng.randi_range(2, 4):
						hit(d, at + int(rf(0.04, 0.25) * R), [[rf(1200.0, 3000.0), 0.6, 60.0]], 0.0001, amp * rf(0.04, 0.1))
			"ground":
				burst(d, at, 0.08, amp * 0.5, 35.0, 40.0, 700.0)
				for g in rng.randi_range(15, 35):
					var gt := absf(rng.randfn(0.0, 0.03))
					ring(d, at + int(gt * R), rf(1500.0, 5000.0), amp * rf(0.02, 0.06), 900.0)
		at += int(gap * R)
		gap *= bounce
		amp *= bounce * rf(0.6, 0.9)
	return d


## The roller door's motor starting (the contactor's clunk, the motor winding up and the
## curtain jerking) or stopping (the brake and the slats settling with a rattle).
func _door_tail(start: bool) -> PackedFloat32Array:
	var d := buf(0.9)
	hit(d, 0, [[rf(110.0, 150.0), 1.0, 25.0], [rf(400.0, 500.0), 0.5, 50.0], [rf(1600.0, 2200.0), 0.3, 120.0]], 0.0003, 0.8)
	burst(d, 0, 0.005, 0.4, 600.0, 800.0, 10000.0)
	if start:
		var ph := 0.0
		for i in int(0.6 * R):
			var t := float(i) / R
			ph += 100.0 * minf(t / 0.25, 1.0) / R
			d[i] += sin(TAU * ph) * 0.2 * minf(t / 0.1, 1.0) * exp(-t * 2.0)
	else:
		for s in rng.randi_range(4, 7):
			hit(d, int(rf(0.05, 0.6) * R), [[rf(300.0, 500.0), 0.6, 40.0], [rf(1100.0, 1700.0), 0.3, 80.0]], 0.0005, rf(0.08, 0.25))
	return d


## A grinder spinning up from rest (the whine sweeping up to speed) or running down when
## the trigger's let go (sweeping down and fading over a second and a half).
func _grinder_tail(up: bool) -> PackedFloat32Array:
	var secs := 0.7 if up else 1.6
	var d := buf(secs)
	var ph := 0.0
	var a := 0.0
	var b := 0.0
	for i in d.size():
		var t := float(i) / R
		var x := t / secs
		var s := (1.0 - exp(-x * 5.0)) if up else exp(-x * 2.2)
		ph += 185.0 * s / R
		var p := TAU * ph
		a += (nz() - a) * 0.35
		b += (a - b) * 0.02
		var env := minf(t / 0.02, 1.0) * ((1.0 - smoothstep(0.75, 1.0, x)) if up else (1.0 - x))
		d[i] = (sin(3.0 * p) * 0.35 + sin(6.0 * p) * 0.12 + sin(11.0 * p) * 0.1 * s + sin(p) * 0.18 + (a - b) * 0.35 * s) * env
	if up:
		hit(d, 0, [[rf(2500.0, 3500.0), 0.6, 300.0], [rf(900.0, 1200.0), 0.4, 150.0]], 0.00005, 0.4)
	return d


## The pressure washer's trigger: pulled, the motor loads up with a thump and the jet
## bursts out; let go, the unloader valve clacks and the pressure hisses away with a drip.
func _jet_tail(on: bool) -> PackedFloat32Array:
	var d := buf(0.5 if on else 0.7)
	hit(d, 0, [[rf(2000.0, 3000.0), 0.6, 300.0], [rf(700.0, 1000.0), 0.5, 120.0]], 0.0001, 0.5)
	if on:
		ring(d, int(0.01 * R), rf(60.0, 80.0), 0.6, 15.0)
		burst(d, int(0.01 * R), 0.4, 0.5, 6.0, 1500.0, 12000.0, false, 0.03)
	else:
		hit(d, int(0.02 * R), [[rf(120.0, 160.0), 0.8, 30.0], [rf(500.0, 700.0), 0.4, 60.0]], 0.0005, 0.5)
		burst(d, int(0.02 * R), 0.6, 0.45, 7.0, 2000.0, 14000.0, false, 0.002)
		for b in 3:
			bubble(d, int(rf(0.2, 0.6) * R), rf(800.0, 1600.0), 0.08, 60.0, 3.0)
	return d


## The spray gun's trigger: a click and the air rushing up to full (on), or the click and a
## short pfft as it cuts off.
func _gun_tail(on: bool) -> PackedFloat32Array:
	var d := buf(0.35)
	hit(d, 0, [[rf(2500.0, 3800.0), 0.6, 400.0], [rf(5000.0, 7000.0), 0.3, 700.0]], 0.00005, 0.5)
	if on:
		burst(d, int(0.005 * R), 0.3, 0.4, 3.0, 800.0, 12000.0, false, 0.06)
	else:
		burst(d, int(0.003 * R), 0.15, 0.4, 25.0, 900.0, 12000.0)
	return d


## The parts washer's pump switching on (relay click, the motor's hum swelling, the first
## gush) or off (the hum dying and the last of the solvent gurgling down the drain).
func _pump_tail(on: bool) -> PackedFloat32Array:
	var d := buf(0.6 if on else 1.3)
	hit(d, 0, [[rf(1800.0, 2600.0), 0.5, 300.0], [rf(600.0, 900.0), 0.3, 150.0]], 0.0001, 0.4)
	for i in int(0.5 * R):
		var t := float(i) / R
		var env := minf(t / 0.2, 1.0) * exp(-t * 4.0) if on else exp(-t * 6.0)
		d[i] += (sin(TAU * 100.0 * t) * 0.3 + sin(TAU * 200.0 * t) * 0.1) * env
	if not on:
		for b in 14:
			bubble(d, int(rf(0.2, 1.1) * R), rf(250.0, 700.0), rf(0.05, 0.15), rf(25.0, 45.0), rf(1.0, 2.5))
	return d


## The sandblaster's valve: a solenoid clack and the blast thumping into the cabinet (on),
## or the clack and the air bleeding off (off).
func _blast_tail(on: bool) -> PackedFloat32Array:
	var d := buf(0.6)
	hit(d, 0, [[rf(1500.0, 2200.0), 0.6, 200.0], [rf(140.0, 180.0), 0.6, 30.0], [rf(230.0, 260.0), 0.4, 35.0]], 0.0002, 0.7)
	if on:
		burst(d, int(0.01 * R), 0.4, 0.6, 6.0, 300.0, 10000.0, false, 0.02)
	else:
		burst(d, int(0.01 * R), 0.5, 0.5, 9.0, 1500.0, 12000.0)
	return d


## The compressor kicking in (the motor straining up to speed, the pistons thumping faster
## and faster) or cutting out (running down, and the unloader valve's long PSSHT).
func _comp_tail(on: bool) -> PackedFloat32Array:
	var secs := 1.0 if on else 1.4
	var d := buf(secs)
	var ph := 0.0
	var last := 0
	for i in int((0.9 if on else 0.6) * R):
		var t := float(i) / R
		var s := minf(t / 0.7, 1.0) if on else exp(-t * 5.0)
		ph += 100.0 * s / R
		d[i] += sin(TAU * ph) * 0.25 * minf(t / 0.05, 1.0) * (1.0 if on else exp(-t * 3.0))
		var crank := int(ph * 0.36)
		if crank != last:
			last = crank
			hit(d, i, [[rf(62.0, 72.0), 1.0, 22.0], [rf(140.0, 160.0), 0.5, 35.0], [rf(420.0, 480.0), 0.25, 60.0]], 0.002, 0.5 * maxf(s, 0.2))
	if not on:
		hit(d, int(0.15 * R), [[rf(1500.0, 2000.0), 0.6, 200.0], [rf(500.0, 700.0), 0.4, 80.0]], 0.0001, 0.4)
		burst(d, int(0.16 * R), 1.2, 0.7, 2.5, 1800.0, 14000.0, false, 0.004)
	return d


## A tyre's bead snapping onto the rim: a sharp pop, the rubber thrumming and the rim ringing.
func _bead_pop() -> PackedFloat32Array:
	var d := buf(0.6)
	burst(d, 0, 0.004, 1.0, 700.0, 300.0, 8000.0, false, 0.0002)
	hit(d, 0, [[rf(280.0, 360.0), 0.8, 30.0], [rf(520.0, 640.0), 0.5, 45.0]], 0.001, 0.8)
	hit(d, 0, [[rf(1200.0, 1500.0), 0.5, 12.0], [rf(2300.0, 2700.0), 0.35, 18.0], [rf(3900.0, 4400.0), 0.2, 25.0]], 0.0001, 0.4)
	return d


## The sales office's sliding doors: the operator's motor whirring and the leaves rolling on
## their track, a bump at the end of opening.
func _slide(open: bool) -> PackedFloat32Array:
	var secs := 0.9
	var d := buf(secs + 0.2)
	var ph := 0.0
	var a := 0.0
	var b := 0.0
	for i in int(secs * R):
		var t := float(i) / R
		var x := t / secs
		var speed := sin(PI * x)
		ph += (550.0 + 300.0 * speed) / R
		a += (nz() - a) * 0.05
		b += (a - b) * 0.005
		d[i] = (sin(TAU * ph) * 0.12 + sin(TAU * ph * 2.0) * 0.04 + (a - b) * 0.9) * speed
	if open:
		hit(d, int(secs * R), [[rf(160.0, 220.0), 0.6, 40.0], [rf(900.0, 1200.0), 0.2, 80.0]], 0.002, 0.4)
	return d


## The sliding doors meeting as they close: rubber seals thumping and the glass ringing faintly.
func _slide_shut() -> PackedFloat32Array:
	var d := buf(0.5)
	hit(d, 0, [[rf(90.0, 130.0), 1.0, 30.0], [rf(220.0, 300.0), 0.4, 45.0]], 0.004, 0.8)
	hit(d, int(rf(0.01, 0.03) * R), [[rf(90.0, 130.0), 0.6, 30.0]], 0.004, 0.5)
	hit(d, 0, [[rf(1500.0, 1900.0), 0.2, 15.0], [rf(2600.0, 3200.0), 0.12, 20.0]], 0.0003, 0.3)
	return d


## A fluorescent tube starting: the starter ticking (a flicker of buzz each time) before it
## strikes with a ping and settles into its hum.
func _tube_start() -> PackedFloat32Array:
	var d := buf(1.4)
	var t := 0.0
	var ticks := rng.randi_range(2, 4)
	for c in ticks:
		var at := int(t * R)
		hit(d, at, [[rf(3000.0, 4500.0), 0.6, 400.0], [rf(1200.0, 1600.0), 0.3, 200.0]], 0.00005, 0.5)
		var ln := int(rf(0.04, 0.12) * R)
		for i in ln:
			var tt := float(i) / R
			if at + i < d.size():
				d[at + i] += (sin(TAU * 100.0 * tt) * 0.3 + sin(TAU * 200.0 * tt) * 0.15 + sin(TAU * 300.0 * tt) * 0.1) * sin(PI * float(i) / ln)
		t += rf(0.15, 0.35)
	ring(d, int(t * R), rf(2200.0, 2800.0), 0.25, 8.0)
	for i in range(int(t * R), d.size()):
		var tt := float(i) / R
		d[i] += (sin(TAU * 100.0 * tt) * 0.2 + sin(TAU * 200.0 * tt) * 0.1) * exp(-(tt - t) * 3.0)
	return d


## The building creaking: the roof sheets ticking as they warm or cool, or a beam groaning.
func _creak() -> PackedFloat32Array:
	var d := buf(0.6)
	if rng.randf() < 0.6:
		hit(d, 0, [[rf(350.0, 700.0), 0.8, 30.0], [rf(1200.0, 1800.0), 0.5, 60.0], [rf(2500.0, 3500.0), 0.3, 100.0]], 0.0006, 0.8)
	else:
		_stick_slip(d, 0, rf(0.2, 0.45), rf(60.0, 140.0), 0.4)
	return d


# ---------------------------------------------------------------------------- unchanged sounds

## The starter motor: a whirring crank that speeds up, then the engine catches.
func _starter() -> PackedFloat32Array:
	var d := buf(0.8)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / R
		var crank := lerpf(7.0, 13.0, t / 0.7)
		phase += crank / R
		var whirr := sin(TAU * 420.0 * t) * 0.15 + sin(TAU * 840.0 * t) * 0.06
		var chug := pow(1.0 - fmod(phase, 1.0), 6.0) * 0.8
		var env := clampf(t * 30.0, 0.0, 1.0) * clampf((0.8 - t) * 12.0, 0.0, 1.0)
		d[i] = (whirr + chug + rf(-0.05, 0.05)) * env * 0.6
	return d


## Rubber squealing on tarmac: a wobbling high whine with a rough edge.
func _screech() -> PackedFloat32Array:
	var d := buf(1.0)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / R
		var f := 1150.0 + 140.0 * sin(TAU * 7.0 * t) + 60.0 * sin(TAU * 13.0 * t)
		phase += f / R
		var tone := sin(TAU * phase) * 0.5 + sin(TAU * phase * 2.01) * 0.18
		d[i] = (tone + rf(-1.0, 1.0) * 0.12) * 0.45
	return d


## A tyre letting go: a sharp, bright bark that snaps in and dies quickly.
func _chirp() -> PackedFloat32Array:
	var d := buf(0.42)
	var phase := 0.0
	var lp := 0.0
	for i in d.size():
		var t := float(i) / R
		var f := 1750.0 - 520.0 * minf(t / 0.25, 1.0) + 90.0 * sin(TAU * 31.0 * t)
		phase += f / R
		var env := minf(t / 0.006, 1.0) * exp(-t * 9.0) * (1.0 + 0.6 * exp(-t * 40.0))
		lp += (nz() - lp) * 0.3
		var tone := sin(TAU * phase) * 0.55 + sin(TAU * phase * 2.02) * 0.22 + sin(TAU * phase * 0.5) * 0.12
		d[i] = (tone + lp * 0.35) * env * 0.85
	return d


## The gearbox clicking into the next gear: a short metallic knock.
func _gear() -> PackedFloat32Array:
	var d := buf(0.12)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / R
		phase += TAU * 140.0 * (1.0 - t * 0.8) / R
		d[i] = sin(phase) * 0.5 * exp(-t * 37.0)
	hit(d, 0, [[1250.0, 0.6, 30.0], [2100.0, 0.4, 40.0]], 0.0001, 0.3)
	burst(d, 0, 0.01, 0.2, 300.0, 300.0, 6000.0)
	return d


## A bright two-note chime: someone pinged something for the crew to look at.
func _chime() -> PackedFloat32Array:
	var d := buf(0.7)
	for i in d.size():
		var t := float(i) / R
		var s := sin(TAU * 988.0 * t) * exp(-t * 7.0) * (1.0 if t < 0.12 else 0.4)
		if t >= 0.12:
			var u := t - 0.12
			s += sin(TAU * 1480.0 * u) * exp(-u * 6.0) + sin(TAU * 2960.0 * u) * exp(-u * 12.0) * 0.25
		d[i] = s * 0.35
	return d


## The stopwatch's beep.
func _beep() -> PackedFloat32Array:
	var d := buf(0.09)
	for i in d.size():
		var t := float(i) / R
		d[i] = (1.0 if fmod(t * 2600.0, 1.0) < 0.5 else -1.0) * 0.18 * clampf((0.09 - t) / 0.01, 0.0, 1.0)
	return d


## Level up: a bright rising arpeggio with a shimmer on the top note.
func _levelup() -> PackedFloat32Array:
	var d := buf(1.3)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in d.size():
		var t := float(i) / R
		var s := 0.0
		for n in notes.size():
			var start: float = n * 0.11
			if t >= start:
				var u := t - start
				var f: float = notes[n]
				var decay := 3.0 if n == notes.size() - 1 else 7.0
				s += (sin(TAU * f * u) + 0.3 * sin(TAU * f * 2.0 * u) * (0.6 + 0.4 * sin(TAU * 6.0 * u))) * exp(-u * decay)
		d[i] = s * 0.22
	return d


## A brass shop bell on its spring, struck five times as it swings, softer each time.
func _shop_bell() -> PackedFloat32Array:
	var d := buf(1.8)
	var strikes := [[0.0, 1.0], [0.16, 0.7], [0.3, 0.5], [0.47, 0.32], [0.66, 0.18]]
	var partials := [[2093.0, 1.0, 3.2], [2093.0 * 2.32, 0.55, 5.0], [2093.0 * 3.16, 0.35, 7.0], [2093.0 * 4.11, 0.22, 9.0],
		[2093.0 * 0.51, 0.25, 2.2]]
	for st in strikes:
		var at := int(float(st[0]) * R)
		var h := float(st[1])
		for p in partials:
			# Real bell partials come in close pairs, so each beats slowly.
			ring(d, at, float(p[0]), float(p[1]) * h * 0.6, float(p[2]))
			ring(d, at, float(p[0]) * 1.0015, float(p[1]) * h * 0.4, float(p[2]))
		burst(d, at, 0.01, 0.3 * h, 600.0, 1000.0, 16000.0)
	return d


## The chrome service bell on the reception counter: the plunger's click, then one bright
## "ding" from the dome, its partials beating slowly as it rings away.
func _desk_bell() -> PackedFloat32Array:
	var d := buf(2.2)
	var f0 := rf(2580.0, 2640.0)
	burst(d, 0, 0.004, 0.35, 2500.0, 3000.0, 14000.0)
	for p in [[1.0, 1.0, 1.6], [2.76, 0.42, 3.4], [5.4, 0.2, 6.0], [8.9, 0.08, 9.0], [0.5, 0.12, 2.4]]:
		ring(d, 0, f0 * float(p[0]), float(p[1]) * 0.55, float(p[2]))
		ring(d, 0, f0 * float(p[0]) * 1.0021, float(p[1]) * 0.4, float(p[2]) * 1.1)
	return d


## A part washed clean: a bright, glassy little bell, struck once, with a sparkle of a higher
## one just after it. The variants climb a major chord, so a run of parts coming clean rings up.
func _wash_ding(v: int) -> PackedFloat32Array:
	var d := buf(1.3)
	var f0: float = [1318.5, 1661.2, 1975.5][posmod(v, 3)]
	burst(d, 0, 0.003, 0.22, 2200.0, 2500.0, 15000.0)
	for p in [[1.0, 1.0, 3.6], [2.0, 0.42, 5.0], [3.0, 0.2, 7.5], [4.18, 0.12, 11.0], [5.43, 0.05, 15.0]]:
		ring(d, 0, f0 * float(p[0]), float(p[1]) * 0.6, float(p[2]))
		ring(d, 0, f0 * float(p[0]) * 1.0016, float(p[1]) * 0.35, float(p[2]) * 1.1)
	var at := int(0.065 * R)
	ring(d, at, f0 * 2.0, 0.22, 6.0)
	ring(d, at, f0 * 3.0, 0.1, 9.0)
	return d


## The whole bike washed clean: a rising run of bells up a major chord to the octave, a held
## shimmering chord, and glints of high pings scattered over it.
func _wash_clean() -> PackedFloat32Array:
	var d := buf(2.6)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for i in notes.size():
		var at := int(i * 0.1 * R)
		var f: float = notes[i]
		var last := i == notes.size() - 1
		burst(d, at, 0.003, 0.18, 2200.0, 2500.0, 15000.0)
		for p in [[1.0, 1.0, 2.2 if last else 3.2], [2.0, 0.4, 4.0], [3.0, 0.18, 6.0], [4.18, 0.1, 9.0]]:
			ring(d, at, f * float(p[0]), float(p[1]) * (0.6 if last else 0.45), float(p[2]))
			ring(d, at, f * float(p[0]) * 1.002, float(p[1]) * 0.3, float(p[2]) * 1.1)
	var chord := int(0.42 * R)
	for f in [523.25, 659.25, 783.99, 1046.5]:
		ring(d, chord, float(f), 0.2, 1.4)
		ring(d, chord, float(f) * 1.003, 0.14, 1.5)
	for k in 14:
		var at := int(rf(0.35, 1.6) * R)
		ring(d, at, rf(3500.0, 6500.0), rf(0.04, 0.1), rf(14.0, 24.0))
	return d


## An old cash till (an offer in at the sales office): two keys clacked down, the bright
## "ching" of its bell, and the drawer rolling out to thump against its stop.
func _till() -> PackedFloat32Array:
	var d := buf(1.6)
	# The keys: plastic-capped levers bottoming out on the frame.
	for kk in 2:
		var at := int((0.02 + kk * 0.11) * R)
		hit(d, at, [[rf(1700.0, 2100.0), 0.7, 90.0], [rf(3800.0, 4400.0), 0.4, 160.0], [rf(420.0, 520.0), 0.6, 60.0]], 0.0001, 0.6)
		burst(d, at, 0.012, 0.35, 400.0, 600.0, 9000.0)
	# The bell: a small domed bell, struck once hard with a quick second bounce of the hammer.
	var bell_at := 0.27
	var f0 := rf(2550.0, 2650.0)
	for st in [[0.0, 1.0], [0.035, 0.35]]:
		var at := int((bell_at + float(st[0])) * R)
		var h := float(st[1])
		for pp in [[1.0, 1.0, 3.0], [2.31, 0.5, 4.5], [3.08, 0.32, 6.0], [4.2, 0.2, 8.0], [0.52, 0.18, 2.5]]:
			ring(d, at, f0 * float(pp[0]), float(pp[1]) * h * 0.55, float(pp[2]))
			ring(d, at, f0 * float(pp[0]) * 1.002, float(pp[1]) * h * 0.4, float(pp[2]))
		burst(d, at, 0.008, 0.3 * h, 700.0, 1500.0, 16000.0)
	# The drawer: a rattling roll out on its runners, then the thump at the end of its travel.
	var roll := int((bell_at + 0.04) * R)
	band(d, roll, 0.28, 900.0, 0.35, 0.22, 4.0, 0.01)
	burst(d, roll, 0.28, 0.08, 3.0, 150.0, 2500.0, false, 0.02)
	for r in 7:
		var at := roll + int(rf(0.01, 0.26) * R)
		hit(d, at, [[rf(1200.0, 2600.0), 0.3, 120.0]], 0.0002, 0.25)
	var stop := roll + int(0.3 * R)
	hit(d, stop, [[rf(140.0, 170.0), 0.9, 30.0], [rf(380.0, 440.0), 0.5, 45.0], [rf(1100.0, 1300.0), 0.3, 80.0]], 0.0008, 0.8)
	burst(d, stop, 0.02, 0.3, 200.0, 120.0, 4000.0)
	return d


## The chime box in the shed: a soft two-tone ding-dong.
func _door_chime() -> PackedFloat32Array:
	var d := buf(1.9)
	var notes := [[0.0, 659.25], [0.45, 523.25]]
	for i in d.size():
		var t := float(i) / R
		var s := 0.0
		for nn in notes:
			var u: float = t - float(nn[0])
			if u < 0.0:
				continue
			var f := float(nn[1])
			s += (sin(TAU * f * u) + 0.25 * sin(TAU * f * 2.0 * u) * exp(-u * 3.0) + 0.1 * sin(TAU * f * 3.0 * u) * exp(-u * 6.0)) * exp(-u * 2.2)
		d[i] = s * 0.25
	return d
