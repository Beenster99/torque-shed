class_name EngineAudio
extends AudioStreamPlayer3D
## Synthesised engine note: firing pulses at the engine's firing frequency, shaped by throttle.

const MIX_RATE := 16000.0

var rpm := 1000.0
var throttle := 0.0
var cylinders := 2
var layout := "parallel"     # firing order shapes the beat: a V-twin lopes, a four screams
var loudness := 1.0         # exhaust: stock muffler 0.6 .. straight pipe 1.3
var running := true
var displacement := 700.0   # cc: big pistons thud low, little ones buzz
var gear := 1
var whine := 0.3            # gearbox whine: a straight-cut race box sings, a road box hums
var _level := 1.0           # fades the note in and out as the engine starts and stops

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0           # position in the engine's cycle, 0..1 (two turns of the crank on a four-stroke)
var _since := 1.0           # time since the last cylinder fired, in average firing gaps
var _sub := 0.0
var _y := 0.0
var _rng := RandomNumberGenerator.new()
var _r1 := 0.0              # the exhaust's body resonance (a two-pole resonator)
var _r2 := 0.0
var _whine_phase := 0.0
var _last_throttle := 0.0
var _pop := 0.0             # crackle on the overrun when the throttle snaps shut


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	stream = gen
	bus = "SFX"
	unit_size = 12.0
	max_db = 3.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var fires := firing_angles()
	var cycle_hz := rpm / 60.0 * (1.0 if layout == "2stroke" else 0.5)
	var step := cycle_hz / MIX_RATE
	var gap_step := step * fires.size()
	var load := 0.35 + 0.65 * throttle
	var cutoff := clampf(0.08 + rpm / 22000.0 + throttle * 0.15 + (loudness - 0.8) * 0.12, 0.05, 0.9)
	var per_cyl := displacement / maxf(cylinders, 1)
	# Big cylinders: long, deep pulses and a low body resonance. Small ones: short and buzzy.
	var sharp := clampf(sqrt(250.0 / maxf(per_cyl, 20.0)), 0.6, 1.9) * 6.0
	var res_hz := clampf(1800.0 / sqrt(maxf(per_cyl, 20.0) / 25.0), 220.0, 2200.0) * (1.25 if layout == "2stroke" else 1.0)
	if layout == "2stroke":
		# The expansion chamber comes on song in the powerband and the note hardens.
		res_hz *= lerpf(0.8, 1.3, clampf(rpm / 9000.0, 0.0, 1.0))
	var w := TAU * res_hz / MIX_RATE
	var r := 0.985
	var a1 := 2.0 * r * cos(w)
	var a2 := r * r
	var res_mix := clampf(0.18 + 0.12 * loudness, 0.15, 0.4)
	# Gear whine rises with road speed, a different pitch in each gear, loudest off the throttle.
	var whine_hz := rpm / 60.0 * 21.0 * (1.0 + gear * 0.06)
	var whine_amp := whine * (0.015 + 0.04 * (1.0 - throttle)) * clampf(rpm / 6000.0, 0.0, 1.0)
	var whine_step := TAU * whine_hz / MIX_RATE
	# Snap the throttle shut at high revs and a loud pipe pops and crackles.
	if _last_throttle - throttle > 0.3 and rpm > 4500.0:
		_pop = clampf(loudness - 0.5, 0.0, 1.0)
	_last_throttle = throttle
	var buf := PackedVector2Array()
	buf.resize(frames)
	var target := 1.0 if running else 0.0
	for i in frames:
		_level += (target - _level) * 0.0008
		var was := _phase
		_phase += step
		if _phase >= 1.0:
			_phase -= 1.0
		for f in fires:
			if (was < f and _phase >= f) or (_phase < was and (f > was or f <= _phase)):
				_since = 0.0
				_sub = _rng.randf_range(0.85, 1.15)  # combustion varies a little each stroke
				if _pop > 0.02 and _rng.randf() < 0.35:
					_sub += _rng.randf_range(1.5, 3.0) * _pop
		_since += gap_step
		var p := maxf(1.0 - _since, 0.0)
		var pulse := pow(p, sharp) * 2.2 * _sub - 0.3
		var buzz := (fmod(_since, 1.0) * 2.0 - 1.0) * 0.25
		var noise := _rng.randf_range(-1.0, 1.0) * (0.12 * throttle + (0.1 if layout == "2stroke" else 0.0))
		var s := (pulse + buzz + noise) * load
		_y += (s - _y) * cutoff
		var ring := a1 * _r1 - a2 * _r2 + s * (1.0 - r) * 2.0
		_r2 = _r1
		_r1 = ring
		_whine_phase = fmod(_whine_phase + whine_step, TAU)
		var out := _y * (1.0 - res_mix) + ring * res_mix * 3.0 + sin(_whine_phase) * whine_amp * (1.0 if running else 0.0)
		buf[i] = Vector2(out, out) * 0.3 * loudness * _level
	_pop = maxf(_pop - frames / MIX_RATE * 1.2, 0.0)
	_playback.push_buffer(buf)


## Where in the cycle (0..1) each cylinder fires: even for fours and boxers, a 270 degree
## parallel twin's off-beat, a V-twin's potato-potato.
func firing_angles() -> Array:
	match layout:
		"single":
			return [0.0]
		"vtwin":
			return [0.0, 315.0 / 720.0]
		"parallel":
			return [0.0, 270.0 / 720.0]
		"twin", "boxer":
			return [0.0, 0.5]
		"triple":
			return [0.0, 1.0 / 3.0, 2.0 / 3.0]
		"2stroke":
			# Every cylinder fires every turn; the cycle here is one turn.
			var out := []
			for c in cylinders:
				out.append(float(c) / cylinders)
			return out
	var even := []
	for c in cylinders:
		even.append(float(c) / cylinders)
	return even
