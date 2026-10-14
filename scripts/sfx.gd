extends Node
## Shed sounds, made from scratch when the game starts so there are no audio files to ship:
## the wrench ratchet, brush scrub, grinder, spray can hiss, parts washer, footsteps and the
## clunks of parts going down. Sets up the SFX and Radio buses that the Esc menu volume
## sliders control.

const RATE := 22050
const LOOPS: Array[String] = ["ratchet", "scrub", "grinder", "spray", "washer", "static", "jet", "pour", "screech", "door"]
## Which loop each kind of work makes while you hold the button.
const WORK_LOOPS := {"unbolt": "ratchet", "bolt": "ratchet", "clean": "scrub", "clean_many": "scrub", "repair": "grinder", "paint": "spray",
	"pour": "pour", "drain": "pour", "tip": "pour", "wash": "jet", "repair_many": "grinder", "adjust_chain": "ratchet", "lube": "spray",
	"tyre_fit": "ratchet", "tyre_remove": "ratchet"}
## Which loop a tool makes in someone else's hands while they work.
const TOOL_LOOPS := {"wrench": "ratchet", "brush": "scrub", "repair": "grinder", "spray": "spray", "lance": "jet", "gun": "spray"}
## The one-shot when a job is done.
const DONE_SOUNDS := {"unbolt": "clink", "bolt": "clink", "remove": "pickup", "install": "clunk", "take": "pickup",
	"place": "clunk", "drop": "clunk", "set_down": "clunk", "bin": "scrap", "order_part": "clunk", "set_stand": "clunk", "adjust_chain": "clink",
	"tyre_remove": "pickup"}

var _cache := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for bus in ["SFX", "Radio"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	apply_volumes()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Radio"), linear_to_db(maxf(Settings.radio_volume, 0.0001)))


func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _make(sound)
	return _cache[sound]


## Plays a one-shot at a point in the world.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, parent: Node = null) -> void:
	var host: Node = parent if parent else get_tree().current_scene
	if host == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.unit_size = 4.0
	p.max_distance = 40.0
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## A looping player for work sounds, parked on `parent`. Set its stream to start a loop.
func make_loop_player(parent: Node3D) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.unit_size = 4.0
	p.max_distance = 40.0
	parent.add_child(p)
	return p


## Plays a one-shot that isn't anywhere in the world: menu and HUD sounds.
func play_ui(sound: String, volume_db := 0.0) -> void:
	var host: Node = get_tree().current_scene if get_tree() else null
	if host == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.bus = "SFX"
	p.volume_db = volume_db
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Starts `sound` looping on `p`, or stops it for "".
func set_loop(p: AudioStreamPlayer3D, sound: String) -> void:
	if sound == "":
		if p.playing:
			p.stop()
		return
	var s := stream(sound)
	if p.stream != s:
		p.stream = s
		p.play()
	elif not p.playing:
		p.play()


# ---------------------------------------------------------------------------- synthesis

func _make(sound: String) -> AudioStreamWAV:
	var data := PackedFloat32Array()
	match sound:
		"ratchet":
			data = _ratchet()
		"scrub":
			data = _scrub()
		"grinder":
			data = _grinder()
		"spray":
			data = _hiss(1.0, 0.35, 0.92)
		"static":
			data = _hiss(1.0, 0.25, 0.6)
		"washer":
			data = _washer()
		"clink":
			data = _ring([2350.0, 3710.0, 5200.0], 0.45, 0.5)
		"clunk":
			data = _thud(85.0, 0.32, 0.8)
		"pickup":
			data = _thud(160.0, 0.14, 0.45)
		"step":
			data = _step()
		"scrap":
			data = _scrap()
		"switch":
			data = _thud(900.0, 0.04, 0.5)
		"starter":
			data = _starter()
		"jet":
			data = _jet()
		"pour":
			data = _pour()
		"screech":
			data = _screech()
		"gear":
			data = _gear()
		"ping":
			data = _chime()
		"door":
			data = _door()
		"beep":
			data = _beep()
		"levelup":
			data = _levelup()
		_:
			data.resize(RATE / 10)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(roundi(data[i] * 32767.0), -32768, 32767))
	wav.data = bytes
	if LOOPS.has(sound):
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size()
	return wav


func _samples(seconds: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(int(RATE * seconds))
	return d


## A socket wrench: a dozen ratchet clicks a second, each a tick of noise and a metallic ring.
func _ratchet() -> PackedFloat32Array:
	var d := _samples(1.0)
	var clicks := 11
	var period := d.size() / clicks
	for c in clicks:
		var start := c * period + _rng.randi_range(-200, 200)
		var pitch := _rng.randf_range(0.9, 1.1)
		for i in int(RATE * 0.05):
			var j := start + i
			if j < 0 or j >= d.size():
				continue
			var t := float(i) / RATE
			var env := exp(-t * 140.0)
			var ring := sin(TAU * 3100.0 * pitch * t) * 0.5 + sin(TAU * 4700.0 * pitch * t) * 0.3
			d[j] += (ring + _rng.randf_range(-1.0, 1.0) * 0.6) * env * 0.5
	return d


## A stiff brush going back and forth: band-limited noise swelling with each stroke.
func _scrub() -> PackedFloat32Array:
	var d := _samples(1.0)
	var fast := 0.0
	var slow := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var stroke := pow(absf(sin(TAU * 2.0 * t)), 0.6)
		var n := _rng.randf_range(-1.0, 1.0)
		fast += (n - fast) * 0.45
		slow += (n - slow) * 0.05
		d[i] = (fast - slow) * stroke * 0.7
	return d


## An angle grinder: a motor whine with harmonics over a bright shower of sparks.
func _grinder() -> PackedFloat32Array:
	var d := _samples(1.0)
	var spark := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var whine := 0.0
		for h in [1, 2, 3, 5]:
			whine += sin(TAU * 190.0 * h * t) / float(h)
		var n := _rng.randf_range(-1.0, 1.0)
		spark = n - spark * 0.6
		var wobble := 0.85 + 0.15 * sin(TAU * 6.0 * t)
		d[i] = (whine * 0.22 + spark * 0.25) * wobble
	return d


## The starter motor: a whirring crank that speeds up, then the engine catches.
func _starter() -> PackedFloat32Array:
	var d := _samples(0.8)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var crank := lerpf(7.0, 13.0, t / 0.7)
		phase += crank / RATE
		var whirr := sin(TAU * 420.0 * t) * 0.15 + sin(TAU * 840.0 * t) * 0.06
		var chug := pow(1.0 - fmod(phase, 1.0), 6.0) * 0.8
		var env := clampf(t * 30.0, 0.0, 1.0) * clampf((0.8 - t) * 12.0, 0.0, 1.0)
		d[i] = (whirr + chug + _rng.randf_range(-0.05, 0.05)) * env * 0.6
	return d


## A pressure washer: a hard jet of water over a pump's buzz.
func _jet() -> PackedFloat32Array:
	var d := _hiss(1.0, 0.5, 0.75)
	for i in d.size():
		var t := float(i) / RATE
		d[i] += (sin(TAU * 100.0 * t) * 0.12 + sin(TAU * 200.0 * t) * 0.05) * (0.9 + 0.1 * sin(TAU * 6.0 * t))
	return d


## Fluid glugging out of a can.
func _pour() -> PackedFloat32Array:
	var d := _samples(1.0)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.06
		var glug := pow(maxf(sin(TAU * 4.0 * t), 0.0), 3.0)
		d[i] = lp * (0.6 + 1.4 * glug) * 0.9 + sin(TAU * (180.0 + 60.0 * glug) * t) * 0.08 * glug
	return d


## Steady hiss. `bright` near 1 keeps the high end, lower softens it.
func _hiss(seconds: float, level: float, bright: float) -> PackedFloat32Array:
	var d := _samples(seconds)
	var lp := 0.0
	for i in d.size():
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * bright
		d[i] = lp * level
	return d


## The parts washer: a pump hum with water sloshing over it.
func _washer() -> PackedFloat32Array:
	var d := _samples(2.0)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var hum := sin(TAU * 50.0 * t) * 0.25 + sin(TAU * 100.0 * t) * 0.12
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.08
		var slosh := lp * (0.6 + 0.4 * sin(TAU * 1.5 * t))
		d[i] = (hum + slosh * 1.4) * 0.4
	return d


## Inharmonic partials ringing out, like a spanner dropped on concrete.
func _ring(partials: Array, seconds: float, level: float) -> PackedFloat32Array:
	var d := _samples(seconds)
	for i in d.size():
		var t := float(i) / RATE
		var s := 0.0
		var k := 1.0
		for f in partials:
			s += sin(TAU * float(f) * t) * exp(-t * 9.0 * k) / k
			k += 0.6
		var click := _rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)
		d[i] = (s * 0.6 + click * 0.4) * level
	return d


## A dull thump: a falling low tone with a burst of noise on the hit.
func _thud(freq: float, seconds: float, level: float) -> PackedFloat32Array:
	var d := _samples(seconds)
	var phase := 0.0
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		phase += TAU * freq * (1.0 - t * 0.8) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.2
		var env := exp(-t * 18.0 / seconds * 0.25)
		d[i] = (sin(phase) * 0.8 + lp * exp(-t * 60.0)) * env * level
	return d


## A boot on a concrete floor.
func _step() -> PackedFloat32Array:
	var d := _samples(0.14)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.25
		d[i] = (lp * 0.9 + sin(TAU * 110.0 * t) * 0.3) * exp(-t * 45.0) * 0.6
	return d


## A part landing in the scrap bin: a clatter of metal.
func _scrap() -> PackedFloat32Array:
	var d := _samples(0.9)
	for hit in 4:
		var start := int(RATE * (hit * 0.09 + _rng.randf_range(0.0, 0.03)))
		var f1 := _rng.randf_range(600.0, 1400.0)
		var f2 := f1 * _rng.randf_range(1.4, 2.7)
		for i in d.size() - start:
			var t := float(i) / RATE
			var env := exp(-t * (7.0 + hit * 3.0))
			d[start + i] += (sin(TAU * f1 * t) + sin(TAU * f2 * t) * 0.6 + _rng.randf_range(-1.0, 1.0) * exp(-t * 80.0)) \
				* env * 0.3 / (1.0 + hit * 0.4)
	return d


## Rubber squealing on tarmac: a wobbling high whine with a rough edge.
func _screech() -> PackedFloat32Array:
	var d := _samples(1.0)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / RATE
		# Whole number of wobbles per second so the loop joins up.
		var f := 1150.0 + 140.0 * sin(TAU * 7.0 * t) + 60.0 * sin(TAU * 13.0 * t)
		phase += f / RATE
		var tone := sin(TAU * phase) * 0.5 + sin(TAU * phase * 2.01) * 0.18
		d[i] = (tone + _rng.randf_range(-1.0, 1.0) * 0.12) * 0.45
	return d


## The gearbox clicking into the next gear: a short metallic knock.
func _gear() -> PackedFloat32Array:
	var d := _thud(140.0, 0.12, 0.6)
	var ring := _ring([1250.0, 2100.0], 0.12, 0.25)
	for i in mini(d.size(), ring.size()):
		d[i] += ring[i]
	return d


## A bright two-note chime: someone pinged something for the crew to look at.
func _chime() -> PackedFloat32Array:
	var d := _samples(0.7)
	for i in d.size():
		var t := float(i) / RATE
		var s := sin(TAU * 988.0 * t) * exp(-t * 7.0) * (1.0 if t < 0.12 else 0.4)
		if t >= 0.12:
			var u := t - 0.12
			s += sin(TAU * 1480.0 * u) * exp(-u * 6.0) + sin(TAU * 2960.0 * u) * exp(-u * 12.0) * 0.25
		d[i] = s * 0.35
	return d


## The roller door's motor and the slats rattling up or down.
func _door() -> PackedFloat32Array:
	var d := _samples(2.6)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.15, 0.0, 1.0) * clampf((2.6 - t) / 0.3, 0.0, 1.0)
		var motor := sin(TAU * 95.0 * t) * 0.3 + sin(TAU * 190.0 * t) * 0.15
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.3
		var rattle := lp * (0.5 + 0.5 * sin(TAU * 14.0 * t)) * 0.6
		d[i] = (motor + rattle) * env * 0.5
	return d


## The stopwatch's beep.
func _beep() -> PackedFloat32Array:
	var d := _samples(0.09)
	for i in d.size():
		var t := float(i) / RATE
		d[i] = (1.0 if fmod(t * 2600.0, 1.0) < 0.5 else -1.0) * 0.18 * clampf((0.09 - t) / 0.01, 0.0, 1.0)
	return d


## Level up: a bright rising arpeggio with a shimmer on the top note.
func _levelup() -> PackedFloat32Array:
	var d := _samples(1.3)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in d.size():
		var t := float(i) / RATE
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
