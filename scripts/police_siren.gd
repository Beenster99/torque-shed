class_name PoliceSiren
extends AudioStreamPlayer3D
## A police car's siren, synthesised: a British wail (a rising and falling sweep) that breaks
## into the faster yelp when the car's close behind whoever it's after, with the pitch bent by
## how fast the car and the listener close on each other (the Doppler shift: higher coming,
## lower going). Set `on`, `yelp`, and each frame `velocity` (the car's, m/s); the listener is
## the camera, its speed worked out from how it moves.

const MIX_RATE := 22050.0
## The wail's sweep (Hz) and how long one rise and fall takes (s); the yelp's, much quicker.
const WAIL_LO := 620.0
const WAIL_HI := 1350.0
const WAIL_TIME := 3.2
const YELP_TIME := 0.32
## The speed of sound (m/s), and how far the shift is let go either way.
const SOUND := 343.0
const SHIFT_MIN := 0.7
const SHIFT_MAX := 1.45

var on := false
var yelp := false
## The car's velocity (m/s, global): set it each frame.
var velocity := Vector3.ZERO
## The pitch shift being applied now (1 none, above 1 closing), for the tests and the mirror.
var shift := 1.0

var _playback: AudioStreamGeneratorPlayback
var _t := 0.0          # where the sweep is (s)
var _phase := 0.0
var _gain := 0.0
var _last_ear := Vector3.INF
var _ear_v := Vector3.ZERO


func _ready() -> void:
	bus = "SFX"
	unit_size = 30.0
	max_db = 4.0
	max_distance = 900.0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## The pitch shift heard by a listener at `ear` moving at `ear_v` from a siren at `at` moving at
## `v`: SOUND over SOUND less how fast the siren comes on along the line between them (net of
## the listener's own closing speed), kept within SHIFT_MIN..SHIFT_MAX.
static func doppler(at: Vector3, v: Vector3, ear: Vector3, ear_v: Vector3) -> float:
	var to_ear := ear - at
	if to_ear.length() < 0.01:
		return 1.0
	var n := to_ear.normalized()
	var closing_src := v.dot(n)          # the siren towards the ear
	var closing_ear := -ear_v.dot(n)     # the ear towards the siren
	return clampf((SOUND + closing_ear) / maxf(SOUND - closing_src, 1.0), SHIFT_MIN, SHIFT_MAX)


## The siren's note (Hz) `t` seconds into its sweep, wailing or yelping.
static func note(t: float, yelping: bool) -> float:
	var period := YELP_TIME if yelping else WAIL_TIME
	var x := fmod(t, period) / period
	# A quick rise and a slower fall, as the motor-driven sirens do.
	var up := smoothstep(0.0, 0.35, x) if x < 0.35 else 1.0 - smoothstep(0.35, 1.0, x)
	return lerpf(WAIL_LO, WAIL_HI, up)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var ear := cam.global_position
		if _last_ear != Vector3.INF and delta > 0.0:
			var ev := (ear - _last_ear) / delta
			# A jump (the floating origin moving, the camera snapping) isn't speed.
			_ear_v = _ear_v.lerp(ev, 0.2) if ev.length() < 120.0 else _ear_v
		_last_ear = ear
		shift = doppler(global_position, velocity, ear, _ear_v)
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	if not on and _gain <= 0.0:
		_playback.push_buffer(buf)   # silence (resize leaves it zeroed)
		return
	var dt := 1.0 / MIX_RATE
	var target := 0.55 if on else 0.0
	for i in frames:
		_gain = move_toward(_gain, target, dt * 3.0)
		if _gain <= 0.0 and not on:
			buf[i] = Vector2.ZERO
			continue
		_t += dt
		var f := note(_t, yelp) * shift
		_phase = fmod(_phase + f * dt, 1.0)
		# A bright, horn-like tone: the fundamental with odd harmonics, softly clipped.
		var x := sin(TAU * _phase) + 0.35 * sin(TAU * _phase * 3.0) + 0.15 * sin(TAU * _phase * 5.0)
		var y := tanh(x * 1.6) * _gain * 0.6
		buf[i] = Vector2(y, y)
	_playback.push_buffer(buf)
