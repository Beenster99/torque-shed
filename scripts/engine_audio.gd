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
var _level := 1.0           # fades the note in and out as the engine starts and stops

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0           # position in the engine's cycle, 0..1 (two turns of the crank on a four-stroke)
var _since := 1.0           # time since the last cylinder fired, in average firing gaps
var _sub := 0.0
var _y := 0.0
var _rng := RandomNumberGenerator.new()


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
		_since += gap_step
		var p := maxf(1.0 - _since, 0.0)
		var pulse := p * p * p * p * p * p * 2.2 * _sub - 0.3
		var buzz := (fmod(_since, 1.0) * 2.0 - 1.0) * 0.25
		var noise := _rng.randf_range(-1.0, 1.0) * (0.12 * throttle + (0.1 if layout == "2stroke" else 0.0))
		var s := (pulse + buzz + noise) * load
		_y += (s - _y) * cutoff
		buf[i] = Vector2(_y, _y) * 0.3 * loudness * _level
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
