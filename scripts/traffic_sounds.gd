class_name TrafficSounds
extends Node
## The traffic's engines, kept cheap: a small pool of 3D players (POOL) handed to the nearest
## few vehicles within RANGE of the camera, a few times a second, and kept on a vehicle while it
## stays among the nearest (so nothing restarts as they shuffle). Each plays one of two short
## synthesised loops (a petrol four for cars, a diesel's clatter for vans, lorries and coaches),
## pitched to its road speed through its gears, louder as it pulls away or climbs, with a touch
## of Doppler as it passes. Everything else in the traffic is silent: far off it would be lost
## under the wind and your own engine anyway.
##
## A child of whatever owns the vehicles (TrafficStream, RoadTraffic): it listens to the
## TrafficVehicle children of its parent that are being drawn.

const POOL := 4
const RANGE := 140.0
const PICK_EVERY := 0.2
## The loops: sample rate, and how many samples one firing cycle (the wave's period) takes.
const RATE := 22050
const PETROL_CYCLE := 460      # 48 Hz: a four at about 1,450 rpm
const DIESEL_CYCLE := 700      # 31.5 Hz: a big six at 630 rpm
const LOOP_CYCLES := {"petrol": 48, "diesel": 32}
## Per kind: [loop, pitch, loudness (dB), how far a gear goes (m/s), how many gears].
const VOICE := {
	"hatchback": ["petrol", 1.08, -6.0, 7.0, 5], "saloon": ["petrol", 0.96, -6.0, 8.0, 5],
	"estate": ["petrol", 1.0, -6.0, 8.0, 5], "suv": ["diesel", 1.3, -5.0, 8.0, 6],
	"van": ["diesel", 1.25, -4.0, 7.0, 5], "lorry": ["diesel", 0.8, 0.0, 3.6, 10], "coach": ["diesel", 0.9, -1.0, 4.0, 8],
}

## The loops once made: "petrol" / "diesel" -> AudioStreamWAV (made on a worker thread).
static var _loops := {}
static var _making := -1
static var _mutex := Mutex.new()

var players: Array[AudioStreamPlayer3D] = []
## Which vehicle each player follows (null: none), and its distance last frame (for Doppler).
var _who: Array = []
var _last_d := PackedFloat32Array()
var _doppler := PackedFloat32Array()
var _timer := 0.0
## How many vehicles were heard last pick (tests and the profiler).
var heard := 0


func _ready() -> void:
	for k in POOL:
		var p := AudioStreamPlayer3D.new()
		p.name = "Engine%d" % k
		p.bus = "SFX"
		p.unit_size = 7.0
		p.max_distance = RANGE
		p.attenuation_filter_cutoff_hz = 4500.0
		p.attenuation_filter_db = -24.0
		p.panning_strength = 0.8
		add_child(p)
		players.append(p)
		_who.append(null)
	_last_d.resize(POOL)
	_doppler.resize(POOL)
	_doppler.fill(1.0)
	prepare()


## Starts making the loops (once a game) on a worker thread.
static func prepare() -> void:
	_mutex.lock()
	var start := _loops.is_empty() and _making < 0
	if start:
		_making = WorkerThreadPool.add_task(_make_all, false, "Traffic engine loops")
	_mutex.unlock()


static func _make_all() -> void:
	var made := {"petrol": make_loop("petrol"), "diesel": make_loop("diesel")}
	_mutex.lock()
	_loops = made
	_mutex.unlock()


## The loop for `which`, or null while it's still being made.
static func loop(which: String) -> AudioStreamWAV:
	_mutex.lock()
	var out: AudioStreamWAV = _loops.get(which)
	_mutex.unlock()
	return out


## An engine loop as 16-bit samples at RATE: a firing cycle's harmonics (worked out once, for one
## cycle, then repeated, so it loops exactly), uneven from cylinder to cylinder, with induction
## and exhaust noise pulsing with the firing; the diesel with a knock at each firing.
static func make_loop(which: String) -> AudioStreamWAV:
	var diesel := which == "diesel"
	var cyc := DIESEL_CYCLE if diesel else PETROL_CYCLE
	var n := cyc * int(LOOP_CYCLES[which])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if diesel else 1717
	# Two firing cycles (the odd one slightly different, as no two cylinders are the same).
	var table := PackedFloat32Array()
	table.resize(cyc * 2)
	var amps := []
	for h in 10:
		amps.append([pow(1.0 / (h + 1), 0.6 if diesel else 0.8) * rng.randf_range(0.7, 1.0), rng.randf() * TAU])
	for i in cyc * 2:
		var ph := TAU * float(i) / cyc
		var x := 0.0
		for h in 10:
			x += float(amps[h][0]) * sin(ph * (h + 1) + float(amps[h][1]))
		x += 0.18 * sin(ph * 0.5)   # the half-order beat of an uneven cycle
		table[i] = x
	var out := PackedFloat32Array()
	out.resize(n + cyc)
	var lo := 0.0
	var lo2 := 0.0
	var knock := 0.0
	var kb := 0.0
	var ka := 0.0
	var a_lo := 1.0 - exp(-TAU * (500.0 if diesel else 900.0) / RATE)
	for i in n + cyc:
		var c := float(i % cyc) / cyc
		var pulse := exp(-c * 6.0)
		lo += (rng.randf() * 2.0 - 1.0 - lo) * a_lo
		lo2 += (lo - lo2) * a_lo
		var x := table[i % (cyc * 2)] * 0.55 + lo2 * (0.9 + 1.6 * pulse)
		if diesel:
			# The clatter: a short ringing knock (around 1.6 kHz) at the start of each firing.
			if i % cyc == 0:
				knock = rng.randf_range(0.7, 1.0)
			var nz := (rng.randf() * 2.0 - 1.0) * knock
			knock *= 0.985
			kb += (nz - kb) * 0.35
			ka += (kb - ka) * 0.35
			x += (kb - ka) * 1.4
		out[i] = x
	# The seam: one cycle more was made past the end, and it fades into the start (the tones
	# repeat exactly, so only the noise is blended), so the loop goes round with no click.
	for i in cyc:
		var a := float(i) / cyc
		out[i] = out[i] * sqrt(a) + out[n + i] * sqrt(1.0 - a)
	out.resize(n)
	var peak := 0.0
	for x in out:
		peak = maxf(peak, absf(x))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(out[i] / maxf(peak, 0.001) * 0.8, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_timer -= delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		Perf.add("traffic_sound", pt)
		return
	if _timer <= 0.0:
		_timer = PICK_EVERY
		_pick(cam.global_position)
	for k in POOL:
		var car = _who[k]
		var p := players[k]
		if car == null or not is_instance_valid(car):
			if p.playing:
				p.stop()
			_who[k] = null
			continue
		var c: TrafficVehicle = car
		p.global_position = c.global_position + Vector3(0.0, 0.7, 0.0)
		var dist := cam.global_position.distance_to(p.global_position)
		# Doppler: closing in, it's higher; going away, lower (smoothed, as the frames jitter).
		var closing := (float(_last_d[k]) - dist) / maxf(delta, 0.001)
		_last_d[k] = dist
		_doppler[k] = lerpf(float(_doppler[k]), clampf(343.0 / (343.0 - clampf(closing, -60.0, 60.0)), 0.85, 1.2), minf(delta * 6.0, 1.0))
		var voice: Array = VOICE.get(c.kind, VOICE["saloon"])
		p.pitch_scale = clampf(revs(c.speed, voice) * float(voice[1]) * float(_doppler[k]), 0.3, 3.5)
		p.volume_db = float(voice[2]) + lerpf(-5.0, 2.0, c.pull) + minf(c.speed * 0.15, 3.0)
	Perf.add("traffic_sound", pt)


## How fast its engine turns, as a pitch (1 at the loop's own revs): rising through each gear
## with road speed, dropping at each change; ticking over when it's stood.
static func revs(v: float, voice: Array) -> float:
	if v < 0.5:
		return 0.62
	var band := float(voice[3])
	var gear := mini(int(v / band), int(voice[4]) - 1)
	var frac := clampf((v - gear * band) / band, 0.0, 1.4)
	return lerpf(0.75, 1.55, frac) if gear > 0 else lerpf(0.62, 1.5, frac)


## Hands the players to the nearest vehicles in hearing that are being drawn, keeping each on
## the vehicle it's on if that's still among them.
func _pick(at: Vector3) -> void:
	var near := []
	var owner_node := get_parent()
	if owner_node != null:
		for c in owner_node.get_children():
			if c is TrafficVehicle and (c as TrafficVehicle).is_visible_in_tree():
				var d := (c as Node3D).global_position.distance_to(at)
				if d < RANGE:
					near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	near.resize(mini(near.size(), POOL))
	heard = near.size()
	var wanted := near.map(func(e): return e[1])
	var stream_p := loop("petrol")
	var stream_d := loop("diesel")
	# Let go of the ones no longer near.
	for k in POOL:
		if _who[k] != null and (not is_instance_valid(_who[k]) or not wanted.has(_who[k])):
			_who[k] = null
			players[k].stop()
	for car in wanted:
		if _who.has(car):
			continue
		var k := _who.find(null)
		if k < 0:
			break
		var voice: Array = VOICE.get((car as TrafficVehicle).kind, VOICE["saloon"])
		var s: AudioStreamWAV = stream_d if voice[0] == "diesel" else stream_p
		if s == null:
			continue   # the loops aren't made yet
		_who[k] = car
		var p := players[k]
		p.stream = s
		p.global_position = (car as Node3D).global_position
		_last_d[k] = at.distance_to(p.global_position)
		_doppler[k] = 1.0
		p.play(randf() * s.get_length())


## The vehicles being heard now.
func heard_vehicles() -> Array:
	return _who.filter(func(c): return c != null and is_instance_valid(c))
