class_name HornAudio
extends AudioStreamPlayer3D
## A bike's horn, synthesised: disc horns, snail and air trumpets, a klaxon, a bulb honker,
## a scooter beeper, the musical horn and the goose. Set `pressed` while the button is held.

const MIX_RATE := 22050.0
## La Cucaracha: note (index into the horn's tones, or -1 for a rest) and length in seconds.
const TUNE := [[0, 0.13], [0, 0.13], [0, 0.13], [3, 0.38], [4, 0.42], [-1, 0.12],
	[0, 0.13], [0, 0.13], [0, 0.13], [3, 0.38], [4, 0.5], [-1, 0.4]]

var style := "disc"
var tones: Array = [420.0]
var loudness := 0.6
var pressed := false

var _playback: AudioStreamGeneratorPlayback
var _phases: Array = []
var _env := 0.0
var _held := 0.0      # seconds since the button went down
var _honk := 0.0      # a bulb or beeper plays its short sound out even if you let go
var _rng := RandomNumberGenerator.new()
var _lp := 0.0


func setup_from(build: BikeBuild) -> void:
	style = build.horn_style
	tones = build.horn_tones.duplicate()
	loudness = build.horn_loudness


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	stream = gen
	bus = "SFX"
	unit_size = 25.0
	max_db = 6.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func has_horn() -> bool:
	return not tones.is_empty()


## Whether it's making a sound right now.
func sounding() -> bool:
	return _env > 0.02


func _process(delta: float) -> void:
	if _playback == null or tones.is_empty():
		return
	if pressed:
		if _held == 0.0 and style in ["bulb", "beep"]:
			_honk = 0.36 if style == "bulb" else 0.3
		_held += delta
	else:
		_held = 0.0
	_honk = maxf(_honk - delta, 0.0)
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	while _phases.size() < maxi(tones.size(), 4):
		_phases.append(_rng.randf())
	var on := pressed or _honk > 0.0
	var buf := PackedVector2Array()
	buf.resize(frames)
	var t0 := _held
	for i in frames:
		var t := t0 + i / MIX_RATE
		var gate := 1.0 if on else 0.0
		var s := 0.0
		match style:
			"melody":
				s = _melody(t) if pressed else 0.0
			"klaxon":
				# AOOGA: the pitch swoops up and the motor rasps.
				var swoop := clampf(t / 0.45, 0.0, 1.0)
				s = _saw(0, float(tones[0]) * lerpf(0.55, 1.0, sqrt(swoop))) * (0.7 + 0.3 * sin(t * TAU * 31.0))
			"bulb":
				var k := 1.0 - _honk / 0.36
				s = _saw(0, float(tones[0]) * lerpf(1.15, 0.85, k)) * 0.8 + _rng.randf_range(-0.2, 0.2)
			"beep":
				# beep-beep
				var k := 0.3 - _honk
				gate *= 1.0 if (k < 0.11 or (k > 0.17 and k < 0.28)) else 0.0
				s = _square(0, float(tones[0]))
			"goose":
				var wob := 1.0 + 0.04 * sin(t * TAU * 7.0) + 0.02 * _rng.randf_range(-1.0, 1.0)
				s = _saw(0, float(tones[0]) * wob) * 0.6 + _square(1, float(tones[0]) * 2.0 * wob) * 0.25
			"air", "snail":
				var vib := 1.0 + 0.006 * sin(t * TAU * 5.0)
				for n in tones.size():
					s += _saw(n, float(tones[n]) * vib) / tones.size()
			_:
				for n in tones.size():
					s += _square(n, float(tones[n])) * 0.75 / tones.size()
		_env += (gate - _env) * (0.02 if gate > _env else 0.006)
		var bright := 0.5 if style in ["air", "snail", "beep"] else 0.3
		_lp += (s - _lp) * bright
		var out := _lp * _env * 0.35 * clampf(loudness, 0.2, 1.3)
		buf[i] = Vector2(out, out)
	_playback.push_buffer(buf)


func _melody(t: float) -> float:
	var total := 0.0
	for n in TUNE:
		total += float(n[1])
	var at := fmod(t, total)
	for n in TUNE:
		if at < float(n[1]):
			var idx := int(n[0])
			if idx < 0 or idx >= tones.size() or at > float(n[1]) - 0.02:
				return 0.0
			return _saw(idx, float(tones[idx]))
		at -= float(n[1])
	return 0.0


func _advance(n: int, hz: float) -> float:
	var ph: float = _phases[n] + hz / MIX_RATE
	ph -= floorf(ph)
	_phases[n] = ph
	return ph


func _saw(n: int, hz: float) -> float:
	return _advance(n, hz) * 2.0 - 1.0


func _square(n: int, hz: float) -> float:
	return 1.0 if _advance(n, hz) < 0.5 else -1.0
