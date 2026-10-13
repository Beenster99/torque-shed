class_name EngineAudio
extends AudioStreamPlayer3D
## Synthesised engine note: firing pulses at the engine's firing frequency, shaped by throttle.

const MIX_RATE := 16000.0

var rpm := 1000.0
var throttle := 0.0
var cylinders := 2
var loudness := 1.0         # exhaust: stock muffler 0.6 .. straight pipe 1.3

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
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
	var fire_hz := rpm / 60.0 * cylinders * 0.5
	var step := fire_hz / MIX_RATE
	var load := 0.35 + 0.65 * throttle
	var cutoff := clampf(0.08 + rpm / 22000.0 + throttle * 0.15 + (loudness - 0.8) * 0.12, 0.05, 0.9)
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_phase += step
		if _phase >= 1.0:
			_phase -= 1.0
			_sub = _rng.randf_range(0.85, 1.15)  # combustion varies a little each stroke
		var p := 1.0 - _phase
		var pulse := p * p * p * p * p * p * 2.2 * _sub - 0.3
		var buzz := (_phase * 2.0 - 1.0) * 0.25
		var noise := _rng.randf_range(-1.0, 1.0) * 0.12 * throttle
		var s := (pulse + buzz + noise) * load
		_y += (s - _y) * cutoff
		buf[i] = Vector2(_y, _y) * 0.3 * loudness
	_playback.push_buffer(buf)
