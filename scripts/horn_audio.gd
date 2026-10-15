class_name HornAudio
extends AudioStreamPlayer3D
## A bike's horn. Horns with recordings (the part's "sound", an Sfx sound such as "horn_air")
## play a take of them: a held horn sounds for as long as the button's down (its steady note
## loops) and stops when you let go, a pip or a ship's horn plays its whole blast, and the
## police horn keeps yelping while held, a different take each time. Horns without recordings
## (or whose files are missing) are synthesised: disc horns, snail and air trumpets, a klaxon,
## a bulb honker, a scooter beeper, the musical horn and the goose. Set `pressed` while the
## button is held.

const MIX_RATE := 22050.0
## La Cucaracha: note (index into the horn's tones, or -1 for a rest) and length in seconds.
const TUNE := [[0, 0.13], [0, 0.13], [0, 0.13], [3, 0.38], [4, 0.42], [-1, 0.12],
	[0, 0.13], [0, 0.13], [0, 0.13], [3, 0.38], [4, 0.5], [-1, 0.4]]
## How each recorded horn plays: "hold" (the default) sounds while held, "once" plays its whole
## take each press, "repeat" plays takes one after another while held.
const PLAY_MODES := {"horn_pip": "once", "horn_ship": "once", "horn_tug": "once", "horn_police": "repeat"}
## Where a held horn's recorded steady note loops from (seconds; the files are cut for it).
const LOOP_FROM := 0.25
## Seconds a held recorded horn takes to die away when you let go.
const RELEASE := 0.07

var style := "disc"
var tones: Array = [420.0]
var loudness := 0.6
var sound := ""
var pressed := false
## Recorded takes started (tests).
var takes := 0

var _recorded := false
var _was_pressed := false
var _gain := 0.0
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
	sound = build.horn_sound


func _ready() -> void:
	bus = "SFX"
	unit_size = 25.0
	max_db = 6.0
	_recorded = _use_recordings()
	if _recorded:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## Whether this horn plays recordings: it has a sound and Sfx has its files. A held horn's
## takes are set to loop their steady note.
func _use_recordings() -> bool:
	var sfx := get_node_or_null("/root/Sfx")
	if sound == "" or tones.is_empty() or sfx == null or not sfx.has_method("recordings"):
		return false
	var takes_here: Array = sfx.call("recordings", sound)
	if takes_here.is_empty():
		return false
	if str(PLAY_MODES.get(sound, "hold")) == "hold":
		for s in takes_here:
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
				(s as AudioStreamOggVorbis).loop_offset = LOOP_FROM
	return true


func has_horn() -> bool:
	return not tones.is_empty()


## Whether it plays recordings rather than a synthesised horn.
func is_recorded() -> bool:
	return _recorded


## Whether it's making a sound right now.
func sounding() -> bool:
	if _recorded:
		return playing and _gain > 0.02
	return _env > 0.02


func _process(delta: float) -> void:
	if _recorded:
		_play_recorded(delta)
		return
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


func _play_recorded(delta: float) -> void:
	var mode := str(PLAY_MODES.get(sound, "hold"))
	if pressed and not _was_pressed:
		_take()
	elif pressed and mode == "repeat" and not playing:
		_take()
	_was_pressed = pressed
	if mode == "hold" and not pressed and playing:
		_gain = move_toward(_gain, 0.0, delta / RELEASE)
		volume_db = _base_db() + linear_to_db(maxf(_gain, 0.0001))
		if _gain <= 0.0:
			stop()


## Starts a take of the recordings, a different one from last time (Sfx.pick).
func _take() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var s: AudioStream = sfx.call("pick", sound) if sfx else null
	if s == null:
		return
	stream = s
	_gain = 1.0
	volume_db = _base_db()
	pitch_scale = _rng.randf_range(0.985, 1.015)
	play()
	takes += 1


## The recorded horn's level: louder horns are louder, and a worn one quieter.
func _base_db() -> float:
	return linear_to_db(clampf(loudness, 0.2, 1.3))


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
