class_name EngineSound
extends Node3D
## A bike's engine as you hear it: the baked loops of its EngineBank played on 3D players, the
## exhaust side at the tail pipe and the engine/intake side at the airbox, crossfaded and pitched
## to the revs and the throttle. On top: pops and burbles when the throttle snaps shut at high
## revs (more from loud pipes) and the backfire's flame; every gear change, up or down, engine
## running or not, is the box's own mechanical click or clunk (heavier into first and on a big
## bike, lighter up the box and on a small one, a soft click finding neutral) with a recorded
## gear lever on top, and nothing else; and the starter motor cranking it over (Simon's
## recordings, a labouring take when the start's a struggle; the made one, or the kick start,
## when there are none), the engine catching and settling to idle. Used by the ridden bike, other players'
## bikes, customers' bikes, the truck and the dyno.

signal backfired(strength: float)

const SLOTS := 3              # players per layer: two buckets crossfading and one spare
## How loud each side is from where you're listening: in the helmet you hear the airbox, on
## the chase camera the pipe, and other people's bikes are mostly pipe.
const VIEW_MIX := {"rider": [0.75, 1.3], "chase": [1.0, 0.7], "remote": [1.0, 0.55], "room": [1.0, 0.85]}
## The recorded gear lever layered on each shift, by the gearbox's feel (Sfx "shift_<feel>"):
## [dB, lowest pitch, highest pitch]. The quickshifter's slick tick is light and high, a sports
## box clicks as recorded, a basic or old box clunks low and heavy.
const SHIFT_FEEL := {"slick": [-8.0, 0.97, 1.05], "click": [-4.0, 0.96, 1.04], "clunk": [-1.0, 0.95, 1.03]}
## How loud each step of a gear change is (dB): into first the loudest clunk, finding neutral
## a soft click.
const STEP_DB := {"first": 0.0, "low": -3.0, "high": -5.0, "down": -2.0, "neutral": -9.0}
## Seconds the starter takes to fade once the engine fires (or the button's let go).
const STARTER_FADE := 0.06
## The recorded starter (Sfx "starter", or "starter_struggle" for a hard start): a crank longer
## than a take carries on into another take from STARTER_LOOP_FROM seconds in (past the
## solenoid's clack), crossfaded over STARTER_XFADE seconds before the take's last
## STARTER_TAIL seconds (the motor running down) would play. Played STARTER_DB loud.
const STARTER_LOOP_FROM := 0.4
const STARTER_TAIL := 0.3
const STARTER_XFADE := 0.08
const STARTER_DB := -3.0

var rpm := 0.0
var throttle := 0.0
var running := true
var gear := 1
var speed := 0.0              # m/s
var cranking := false         # the starter is turning it over (set by the owner)
var struggle := 0.0           # how hard it is to start (Bike.start_struggle), set by the owner
var infer_cranking := false   # other players' bikes: guess cranking from the revs rising with the engine off
var view := "remote":
	set(v):
		view = v if VIEW_MIX.has(v) else "remote"
var volume_db := 0.0
var spec: Dictionary
var bank: EngineBank
var exhaust_at: Node3D        # where the pipe ends
var engine_at: Node3D         # the airbox and engine
var flame: ExhaustFlame
## Counters, for tests and the HUD.
var pops := 0
var shifts := 0
var last_shift := ""          # the box's feel on the last change ("slick", "click", "clunk")
var last_step := ""           # and which step it was (EngineSynth.GEAR_STEPS)
var gear_sounds := 0          # gear-change clicks and clunks played
var starts := 0               # starter (or kick) sounds played
var catches := 0              # the engine catching
var last_start: AudioStream   # the starter take played last
var last_start_kind := ""     # what it was: "starter" or "starter_struggle" (recorded), "made" or "kick"
var starter_takes := 0        # recorded starter takes played, a long crank carrying on into more
## Recorded gear-lever sounds played (tests).
var lever_sounds := 0

var _players := {}            # layer -> Array of AudioStreamPlayer3D
var _assigned := {}           # layer -> {bucket: player}
var _oneshot_ex: Array = []
var _oneshot_en: Array = []
var _next_ex := 0
var _next_en := 0
var _lever: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _load := 0.0              # smoothed throttle as the sound hears it
var _level := 0.0             # fades the engine in as it catches and out as it dies
var _blip := 0.0              # the bark as it catches
var _cut := 0.0               # ignition cut: quickshifter or clutch in
var _last_gear := -1
var _overrun := 0.0           # seconds since the throttle shut with the revs up
var _since_crank := 9.0       # seconds since the starter last turned it over
var _was_running := false
var _was_cranking := false
var _last_rpm := 0.0
var _starter: AudioStreamPlayer3D   # playing the starter now
var _starter_stream: AudioStream
var _starter_players: Array = []   # the recorded starter's two players, crossfading on a long crank
var _starter_next := 0
var _starter_old: AudioStreamPlayer3D   # the take before, fading out under the next
var _starter_t := 0.0         # seconds into the recorded take playing now
var _starter_len := 0.0
var _starter_pitch := 1.0
var _xfade := 1.0             # 0..1 through a crossfade from one take to the next
var _catch_t := 1.0           # seconds since it caught: the running sound comes in a touch slower
var _crank_guess := 0.0
var _bus_t := 0.0
var _bus := "Engines"


## Sets the sound up for a bike. `model` gives where the pipe and engine are; without one they
## sit at sensible spots round this node.
func setup(build: BikeBuild, model: BikeModel = null) -> void:
	setup_spec(EngineSynth.spec_from_build(build), model)


func setup_spec(engine_spec: Dictionary, model: BikeModel = null) -> void:
	spec = engine_spec
	bank = EngineBank.for_spec(spec)
	_rng.randomize()
	if exhaust_at == null:
		exhaust_at = Node3D.new()
		exhaust_at.name = "Exhaust"
		add_child(exhaust_at)
		engine_at = Node3D.new()
		engine_at.name = "Engine"
		add_child(engine_at)
		for layer in EngineSynth.LAYERS:
			var list := []
			for i in SLOTS:
				list.append(_make_player(exhaust_at if layer.begins_with("ex") else engine_at, 12.0 if layer.begins_with("ex") else 8.0))
			_players[layer] = list
			_assigned[layer] = {}
		for i in 4:
			_oneshot_ex.append(_make_player(exhaust_at, 14.0))
		for i in 2:
			_oneshot_en.append(_make_player(engine_at, 6.0))
		_lever = _make_player(engine_at, 4.0)
		for i in 2:
			_starter_players.append(_make_player(engine_at, 6.0))
		flame = ExhaustFlame.new()
		exhaust_at.add_child(flame)
	exhaust_at.position = Vector3(0.18, 0.4, 0.75)
	engine_at.position = Vector3(0.0, 0.6, -0.1)
	if model:
		exhaust_at.position = model.exhaust_tip()
		var box := model.slot_bounds("engine")
		if box.size != Vector3.ZERO:
			engine_at.position = box.get_center() + Vector3(0.0, box.size.y * 0.4, 0.0)
	for layer in _assigned:
		for b in _assigned[layer]:
			_assigned[layer][b].stop()
		_assigned[layer] = {}


func _make_player(parent: Node3D, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Engines"
	p.unit_size = unit
	p.max_db = 6.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.attenuation_filter_cutoff_hz = 20500.0
	parent.add_child(p)
	return p


## Other players' bikes: the far-off sound loses its top end and they come and go with doppler.
func set_distant_filter(on: bool) -> void:
	for layer in _players:
		for p: AudioStreamPlayer3D in _players[layer]:
			p.attenuation_filter_cutoff_hz = 5000.0 if on else 20500.0
			p.attenuation_filter_db = -30.0 if on else -24.0
	for p: AudioStreamPlayer3D in _oneshot_ex:
		p.attenuation_filter_cutoff_hz = 6000.0 if on else 20500.0


## Overrun pops a second for this engine at `rpm`, `overrun_s` seconds after the throttle shut:
## a hot pipe pops most just after you roll off, then it settles to the odd burble. A
## two-stroke's pipe crackles and pops more readily, fed unburnt charge every turn.
static func pop_rate(engine_spec: Dictionary, at_rpm: float, overrun_s: float) -> float:
	var style: Dictionary = EngineSynth.EXHAUSTS[engine_spec["exhaust"]]
	var lo := maxf(float(engine_spec["idle"]) * 2.2, 3000.0)
	if at_rpm <= lo:
		return 0.0
	var revs := clampf((at_rpm - lo) / (float(engine_spec["redline"]) * 0.5), 0.0, 1.0)
	var settle := 0.3 + 0.7 * exp(-overrun_s / 1.2)
	var two := 1.6 if EngineSynth.is_two_stroke(engine_spec) else 1.0
	return float(style["pops"]) * 3.0 * revs * settle * (1.0 + float(engine_spec["rust"])) * two


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("engine_audio", pt)


func _process_body(delta: float) -> void:
	if bank == null:
		return
	bank.poll()
	_bus_t -= delta
	if _bus_t <= 0.0:
		_bus_t = 0.5
		_update_bus()
	if infer_cranking:
		# Another player's bike: the revs rising with the engine off is the starter turning it.
		if not running and rpm > 20.0 and rpm > _last_rpm + 1.0:
			_crank_guess = 0.3
		_crank_guess -= delta
		cranking = _crank_guess > 0.0
	_events(delta)
	_last_rpm = rpm
	# The sound's own throttle: it snaps open fast and closes a touch slower.
	var target := maxf(throttle, _blip)
	if _cut > 0.0:
		target = minf(target, 0.04)
	_load += (target - _load) * (1.0 - exp(-delta * (30.0 if target > _load else 16.0)))
	_blip = maxf(_blip - delta * 6.0, 0.0)
	_cut -= delta
	var alive := 1.0 if running else 0.0
	_catch_t += delta
	var rise := 5.0 if _catch_t < 0.3 else 14.0   # just caught: the catch one-shot carries it
	_level += (alive - _level) * (1.0 - exp(-delta * (rise if running else 4.0)))
	# Below idle (stalling, switched off) the note dies away with the revs.
	var idle: float = spec["idle"]
	var life := _level * clampf((rpm - idle * 0.25) / (idle * 0.5), 0.0, 1.0)
	var mix: Array = VIEW_MIX[view]
	if bank.exhaust_only:
		# Recordings of the whole bike: the pipe carries all of it, as loud as either side would be.
		mix = [maxf(mix[0], mix[1]), mix[1]]
	var weights := bank.mix_weights(rpm, _load) if life > 0.001 else []
	var wanted := {}
	for layer in EngineSynth.LAYERS:
		wanted[layer] = {}
	for w in weights:
		var g: float = float(w[2]) * life * (mix[0] if str(w[0]).begins_with("ex") else mix[1])
		var loud: float = 0.75 + 0.35 * float(spec["loud"]) if str(w[0]).begins_with("ex") else 1.0
		wanted[w[0]][w[1]] = [g * loud, float(w[3])]
	for layer in EngineSynth.LAYERS:
		_drive_layer(layer, wanted[layer])


## Points this layer's players at the buckets wanted, at their volume and pitch; frees the rest.
func _drive_layer(layer: String, want: Dictionary) -> void:
	var have: Dictionary = _assigned[layer]
	for b in have.keys():
		if not want.has(b):
			have[b].stop()
			have.erase(b)
	for b in want:
		var gain: float = want[b][0]
		var pitch: float = want[b][1]
		var p: AudioStreamPlayer3D = have.get(b)
		if p == null:
			if gain < 0.002:
				continue
			for cand: AudioStreamPlayer3D in _players[layer]:
				if not have.values().has(cand):
					p = cand
					break
			if p == null:
				continue
			var stream: AudioStream = bank.streams[layer][b]
			if stream == null:
				continue
			p.stream = stream
			have[b] = p
			# Start each loop somewhere different so layers don't line up and phase.
			p.play(_rng.randf() * stream.get_length())
		p.volume_db = linear_to_db(maxf(gain, 0.00001)) + volume_db
		p.pitch_scale = clampf(pitch, 0.05, 4.0)


## Gear changes, pops, the starter: the things that happen rather than hum.
func _events(delta: float) -> void:
	# The starter (or the kick), fading out once it fires or the button's let go.
	if cranking and not _was_cranking and not running:
		_start_starter()
	_was_cranking = cranking
	_since_crank = 0.0 if cranking else _since_crank + delta
	if _starter and cranking and not running and _starter_players.has(_starter):
		_keep_cranking(delta)
	if _starter_old and _xfade >= 1.0:
		_starter_old.stop()
		_starter_old = null
	if _starter and (not cranking or running):
		if _starter_old:
			_starter_old.stop()
			_starter_old = null
		if not _starter.playing or _starter.stream != _starter_stream:
			_starter = null
		else:
			_starter.volume_db -= 60.0 * delta / STARTER_FADE
			if _starter.volume_db < volume_db - 60.0:
				_starter.stop()
				_starter = null
	# Catching off the starter: the first ragged firings and the revs flaring and settling.
	if running and not _was_running and _since_crank < 0.5:
		if _play(_oneshot_ex, "catch", 0.0, _rng.randf_range(0.97, 1.03)):
			catches += 1
		_catch_t = 0.0
		_blip = 0.3
	_was_running = running
	# Gear changes: every one a click or a clunk of the box, engine running or not.
	if _last_gear < 0:
		_last_gear = gear
	if gear != _last_gear:
		_shift(_last_gear, gear)
	_last_gear = gear
	# Overrun: the throttle shut with the revs up.
	if running and throttle < 0.08 and _cut <= 0.0:
		_overrun += delta
		var rate := pop_rate(spec, rpm, _overrun)
		if rate > 0.0 and _rng.randf() < rate * delta:
			var style: Dictionary = EngineSynth.EXHAUSTS[spec["exhaust"]]
			if _rng.randf() < 0.04 * float(style["pops"]):
				_pop("crack", 1.0)
			else:
				_pop("pop", _rng.randf_range(0.6, 1.1))
	else:
		_overrun = 0.0


## Which recorded starter a start this hard (Bike.start_struggle) plays: "starter", or
## "starter_struggle" once it's a struggle (Bike.STRUGGLE_FROM); "" for a kick-started engine.
static func starter_sound(engine_spec: Dictionary, how_hard: float) -> String:
	if bool(engine_spec.get("kick", false)):
		return ""
	return "starter_struggle" if how_hard >= Bike.STRUGGLE_FROM else "starter"


## How a recorded starter is pitched for this engine: a little higher on a small one, lower on
## a big one.
static func starter_pitch(engine_spec: Dictionary) -> float:
	return lerpf(1.06, 0.88, clampf((float(engine_spec["cc"]) - 50.0) / 1300.0, 0.0, 1.0))


## A take of the recorded starter `kind` (Sfx picks them, never the same twice running), the
## healthy one if there's no struggling one (last_start_kind says which); null if there are no
## recordings at all.
func _starter_take(kind: String) -> AudioStream:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx == null or not sfx.has_method("recordings"):
		return null
	for k in [kind, "starter"]:
		if not (sfx.call("recordings", k) as Array).is_empty():
			last_start_kind = k
			return sfx.call("pick", k)
	return null


## The button's pressed: the recorded starter motor, or the made one (or the kick).
func _start_starter() -> void:
	var kind := starter_sound(spec, struggle)
	var take: AudioStream = _starter_take(kind) if kind != "" else null
	if take:
		_starter_pitch = starter_pitch(spec) * _rng.randf_range(0.97, 1.03)
		_xfade = 1.0
		_starter = _starter_play(take, 0.0)
	else:
		_starter = _play(_oneshot_en, "starter", 0.0, _rng.randf_range(0.97, 1.03))
		last_start_kind = "kick" if bool(spec["kick"]) else "made"
	_starter_stream = _starter.stream if _starter else null
	if _starter:
		starts += 1
		last_start = _starter_stream


## Plays a recorded starter take on the next starter player from `from` seconds in.
func _starter_play(take: AudioStream, from: float) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = _starter_players[_starter_next % _starter_players.size()]
	_starter_next += 1
	p.stream = take
	p.pitch_scale = _starter_pitch
	p.volume_db = STARTER_DB + volume_db
	p.play(from)
	_starter_t = from
	_starter_len = take.get_length()
	starter_takes += 1
	return p


## Still cranking: a long crank carries on into another take before this one runs down,
## crossfading (equal power) from the one to the other.
func _keep_cranking(delta: float) -> void:
	_starter_t += delta * _starter_pitch
	if _xfade < 1.0:
		_xfade = minf(_xfade + delta / STARTER_XFADE, 1.0)
		_starter.volume_db = STARTER_DB + volume_db + linear_to_db(maxf(sin(_xfade * PI * 0.5), 0.001))
		if _starter_old:
			_starter_old.volume_db = STARTER_DB + volume_db + linear_to_db(maxf(cos(_xfade * PI * 0.5), 0.001))
	if _starter_t < _starter_len - STARTER_TAIL - STARTER_XFADE * _starter_pitch:
		return
	var take := _starter_take(last_start_kind)
	if take == null:
		return
	if _starter_old:
		_starter_old.stop()
	_starter_old = _starter
	_starter = _starter_play(take, STARTER_LOOP_FROM)
	_starter.volume_db = STARTER_DB + volume_db - 60.0
	_starter_stream = take
	last_start = take
	_xfade = 0.0


## A gear change from `from` to `to` (0 is neutral): the box's click or clunk for that step with
## the recorded lever on top, and nothing else (no pops, bangs or blips). Going up with the
## engine running, the drive's cut for a blink as the clutch comes in (a quickshifter cuts the
## spark for less).
func _shift(from: int, to: int) -> void:
	shifts += 1
	var qs: bool = spec["quickshifter"]
	var step := EngineSynth.gear_step(from, to)
	if running and to > from and from > 0:
		_cut = 0.05 if qs else 0.12
	last_shift = "slick" if qs else str(spec["shift"])
	last_step = step
	var kind := "neutral" if step == "neutral" else "shift_" + step
	if bank and bank.recorded_shots.has("shift") and step != "neutral":
		kind = "shift"
	# The lever: a light tick finding neutral, a clunk into first, else the box's own feel. With
	# its recording there (Simon's clunks) that's all you hear; the made box sound is only for a
	# game without them.
	var feel := "slick" if step == "neutral" else ("clunk" if step == "first" else last_shift)
	var sfx := get_node_or_null("/root/Sfx")
	var recorded := sfx != null and not (sfx.call("recordings", "shift_" + feel) as Array).is_empty()
	if not recorded and _play(_oneshot_en, kind, float(STEP_DB.get(step, -3.0)), _rng.randf_range(0.96, 1.04)):
		gear_sounds += 1
	if _lever_sound(feel, -8.0 if step == "neutral" else 0.0, lerpf(1.05, 0.93, EngineSynth.gear_heft(spec))) and recorded:
		gear_sounds += 1


## The recorded gear lever and selector for this feel ("slick", "click", "clunk") on top of the
## made shift sound: a different take each time (Sfx picks them), pitched to the feel and by
## `pitch` (lower for a heavier box), `db` louder or quieter. Whether it played.
func _lever_sound(feel: String, db := 0.0, pitch := 1.0) -> bool:
	var sfx := get_node_or_null("/root/Sfx")
	if _lever == null or sfx == null or not sfx.has_method("pick"):
		return false
	var s: AudioStream = sfx.call("pick", "shift_" + feel)
	if s == null:
		return false
	var f: Array = SHIFT_FEEL.get(feel, SHIFT_FEEL["click"])
	_lever.stream = s
	_lever.volume_db = float(f[0]) + db + volume_db
	_lever.pitch_scale = _rng.randf_range(float(f[1]), float(f[2])) * pitch
	_lever.play()
	lever_sounds += 1
	return true


## An overrun pop or a backfire crack (or a bang), with the flame for the loud ones.
func _pop(kind: String, strength: float) -> void:
	pops += 1
	_play(_oneshot_ex, kind, linear_to_db(strength), _rng.randf_range(0.9, 1.1))
	var big := 0.4 if kind == "pop" else (0.8 if kind == "bang" else 1.0)
	var style: String = spec["exhaust"]
	if kind != "pop" or style in ["race", "straight"]:
		backfired.emit(big * strength)
		if flame:
			flame.flash(big * strength)


## Plays a one-shot of `kind` from the bank on the next player in `pool`; the player, or null
## if it isn't baked yet.
func _play(pool: Array, kind: String, db: float, pitch: float) -> AudioStreamPlayer3D:
	if bank == null or pool.is_empty():
		return null
	var s := bank.oneshot(kind, _rng)
	if s == null:
		return null
	var p: AudioStreamPlayer3D
	if pool == _oneshot_ex:
		p = pool[_next_ex % pool.size()]
		_next_ex += 1
	else:
		p = pool[_next_en % pool.size()]
		_next_en += 1
	p.stream = s
	p.volume_db = db + volume_db + (2.0 * (float(spec["loud"]) - 1.0) if pool == _oneshot_ex else 0.0)
	p.pitch_scale = pitch
	p.play()
	return p


## Keeps the listening camera tracked for doppler, and in the shed or out in the open picks the shed sounds' room and distance buses, when there are any.
func _update_bus() -> void:
	# Doppler needs the listening camera tracked too (cameras here move on the physics step).
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and cam.doppler_tracking == Camera3D.DOPPLER_TRACKING_DISABLED:
		cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	var sfx := get_node_or_null("/root/Sfx")
	if sfx == null or not sfx.has_method("bus_for") or not is_inside_tree():
		return
	var bus := str(sfx.call("bus_for", global_position, true))
	if bus == _bus or AudioServer.get_bus_index(bus) < 0:
		return
	_bus = bus
	for p in find_children("*", "AudioStreamPlayer3D", true, false):
		p.bus = bus


## The gear a bike ridden along by the game (a customer, another rider on the road) is in at
## `speed` m/s, a gear for every `per` m/s up to `top`, held a little past each change point so
## hovering at one doesn't click it up and down over and over.
static func gear_for_speed(current: int, speed: float, per: float, top: int) -> int:
	var want := clampi(1 + int(maxf(speed, 0.0) / per), 1, top)
	if current < 1 or want == current:
		return want
	var edge := float(maxi(want, current) - 1) * per
	return current if absf(speed - edge) < per * 0.15 and absi(want - current) == 1 else want


## How many loop players are sounding right now (tests).
func playing_count() -> int:
	var n := 0
	for layer in _assigned:
		n += _assigned[layer].size()
	return n
