extends RefCounted
## Simon's recorded starter motors (healthy and struggling) and his two-stroke recordings, and
## the made two-stroke's buzz, pipe and crackle. Run from tests/run_tests.gd (its _test_sound_*
## functions hand over to these).

var t: Node   # the test runner: check(), get_tree(), add_child()

const STARTERS := ["starter1", "starter2", "starter3", "starter4"]
const STRUGGLES := ["starterstruggle1", "starterstruggle2", "starterstruggle3", "starterstruggle4"]
const TWO_STROKE_DIR := "res://audio/engines/2stroke_1"


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A Vorbis file's channel count, from its identification header.
static func _ogg_channels(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var head := f.get_buffer(64)
	var at := head.find(0x01)
	while at >= 0 and at + 11 < head.size():
		if head.slice(at + 1, at + 7).get_string_from_ascii() == "vorbis":
			return head[at + 11]
		at = head.find(0x01, at + 1)
	return 0


## The eight recordings are in the audio folder, mono, trimmed, and Sfx has them as the
## starter's takes, healthy and struggling.
func test_files() -> void:
	var ok := true
	var mono := true
	var trimmed := true
	for name in STARTERS + STRUGGLES:
		var path: String = Sfx.RECORDINGS_DIR + name + ".ogg"
		var s := load(path) as AudioStreamOggVorbis
		ok = ok and s != null
		mono = mono and _ogg_channels(ProjectSettings.globalize_path(path)) == 1
		trimmed = trimmed and s != null and s.get_length() > 1.8 and s.get_length() < 2.1
	check(ok, "all eight starter recordings load")
	check(mono and trimmed, "they're mono and trimmed of their silence (each under the 2.1 s recorded)")
	check(Sfx.recordings("starter").size() == 4 and Sfx.recordings("starter_struggle").size() == 4,
		"Sfx has four healthy starter takes and four struggling ones")


## Which start is a struggle: worn plugs, a tired engine and fuel system, a frozen engine; a
## struggle cranks longer and plays the struggling takes; a kick start has no starter motor.
func test_choice() -> void:
	var fresh := BikeBuild.new({"engine": "inline_1000"})
	check(Bike.struggle_for(fresh, 20.0) < 0.01 and is_equal_approx(Bike.start_time(Bike.struggle_for(fresh, 20.0)), Bike.START_TIME),
		"a healthy bike on a mild day spins over and fires in the usual time")
	var worn := BikeBuild.new({"engine": "inline_1000"})
	worn.health["spark_plugs"] = 0.2
	worn.health["engine"] = 0.6
	var s := Bike.struggle_for(worn, 20.0)
	check(s >= Bike.STRUGGLE_FROM and Bike.start_time(s) > Bike.START_TIME + 0.8,
		"worn plugs and a tired engine make it a struggle, cranking for longer (%.2f, %.1f s)" % [s, Bike.start_time(s)])
	check(Bike.struggle_for(fresh, -10.0) >= Bike.STRUGGLE_FROM and Bike.struggle_for(fresh, 5.0) < Bike.STRUGGLE_FROM,
		"a frozen engine struggles; a merely cool one doesn't")
	var a_bit := BikeBuild.new({"engine": "inline_1000"})
	a_bit.health["spark_plugs"] = 0.85
	check(Bike.struggle_for(a_bit, 20.0) < Bike.STRUGGLE_FROM, "slightly used plugs still start cleanly")
	var spec := EngineSynth.spec_from_build(fresh)
	check(EngineSound.starter_sound(spec, 0.0) == "starter" and EngineSound.starter_sound(spec, s) == "starter_struggle"
		and EngineSound.starter_sound(EngineSynth.spec_from_build(BikeBuild.new({"engine": "2stroke_125"})), s) == "",
		"healthy takes for an easy start, struggling ones for a hard one, none for a kick start")
	check(EngineSound.starter_pitch(spec) < EngineSound.starter_pitch(EngineSynth.make_spec("single", 1, 125.0)),
		"a big engine's starter is pitched lower than a little one's")


func _sound(spec: Dictionary) -> EngineSound:
	var es := EngineSound.new()
	t.add_child(es)
	es.setup_spec(spec)
	es.bank.bake_now()
	es.running = false
	es.rpm = 0.0
	return es


func _crank(es: EngineSound, seconds: float) -> void:
	es.cranking = true
	for i in int(seconds * 60.0):
		es._process(1.0 / 60.0)


func _release(es: EngineSound, fire: bool) -> void:
	es.cranking = false
	es.running = fire
	if fire:
		es.rpm = float(es.spec["idle"]) * 1.3
	for i in 12:
		es._process(1.0 / 60.0)


## On a bike: each press a random healthy take (never the same twice running), a struggling
## take when it's hard to start, the made kick for a kick start; a short press is cut with a
## quick fade, and the engine still catches after.
func test_played() -> void:
	var spec := EngineSynth.make_spec("triple", 3, 850.0, {"idle": 1250.0, "redline": 10500.0})
	var es := _sound(spec)
	var takes := []
	var repeats := 0
	for i in 8:
		_crank(es, 0.7)
		if i == 0:
			check(es.last_start_kind == "starter" and Sfx.recordings("starter").has(es.last_start),
				"pressing the button plays one of the recorded healthy starter takes")
		if not takes.is_empty() and takes[-1] == es.last_start:
			repeats += 1
		takes.append(es.last_start)
		_release(es, i % 2 == 0)
		es.running = false
		es.rpm = 0.0
		es._process(1.0 / 60.0)
	var distinct := {}
	for s in takes:
		distinct[s] = true
	check(distinct.size() >= 3 and repeats == 0 and takes.all(func(s): return Sfx.recordings("starter").has(s)),
		"each press picks a take at random (%d different in 8), never the same one twice running" % distinct.size())
	check(es.catches >= 4 and es._starter == null, "it still fires and catches after the recording, the starter faded out")
	es.struggle = 0.8
	_crank(es, 0.5)
	check(es.last_start_kind == "starter_struggle" and Sfx.recordings("starter_struggle").has(es.last_start),
		"a hard start plays one of the struggling takes")
	_release(es, false)
	check(es._starter == null, "letting go early cuts it with a short fade")
	es.queue_free()
	var kick := _sound(EngineSynth.spec_from_build(BikeBuild.new({"engine": "2stroke_125"})))
	_crank(kick, 0.3)
	check(kick.last_start_kind == "kick" and kick.bank.oneshots["starter"].has(kick.last_start), "a kick start keeps its made kick")
	kick.queue_free()
	await t.get_tree().process_frame


## A crank longer than a take carries on into more takes, crossfaded, the take's own run-down
## tail never heard until it's let go; a short one plays just the one take.
func test_long_crank() -> void:
	var es := _sound(EngineSynth.make_spec("parallel", 2, 700.0, {"idle": 1300.0, "redline": 9500.0}))
	es.struggle = 1.0
	_crank(es, 0.6)
	check(es.starter_takes == 1, "a short crank is the one take")
	_crank(es, 4.4)
	check(es.starter_takes >= 3 and Sfx.recordings("starter_struggle").has(es.last_start) and es._starter.playing,
		"five seconds of struggling carries on into more struggling takes (%d)" % es.starter_takes)
	check(es._starter_t < es._starter_len - EngineSound.STARTER_TAIL + 0.05, "never into a take's run-down tail while it's still cranking")
	_release(es, true)
	check(es._starter == null and es._starter_old == null and es.catches == 1, "it fires: the starter fades and it catches")
	es.queue_free()
	await t.get_tree().process_frame


## Simon's two-stroke single: steady loops cut from his recordings at idle and up the range,
## on and off the throttle, each a whole number of firings so it repeats seamlessly; a
## two-stroke single's bank plays them (from the pipe, as the whole bike), other engines
## don't.
func test_two_stroke_recorded() -> void:
	var spec := EngineSynth.spec_from_build(BikeBuild.new({"engine": "2stroke_125"}))
	check(EngineBank.sample_folder(spec) == TWO_STROKE_DIR, "a two-stroke single finds Simon's recordings")
	check(EngineBank.sample_folder(EngineSynth.make_spec("2stroke", 3, 750.0)) == ""
		and EngineBank.sample_folder(EngineSynth.make_spec("inline", 4, 1000.0)) == "", "a two-stroke triple and a four are still made")
	var bank := EngineBank.new(spec)
	bank.load_samples(TWO_STROKE_DIR)
	bank.bake_now()
	check(bank.recorded and bank.exhaust_only and bank.rpms.size() >= 5 and bank.rpms[0] < 1600.0 and bank.rpms[-1] > 12000.0,
		"loops from idle to past 12,000 rpm (%s)" % str(bank.rpms))
	var whole := true
	var looping := true
	for i in bank.rpms.size():
		for layer in ["ex_on", "ex_off"]:
			var st: AudioStreamWAV = bank.streams[layer][i]
			looping = looping and st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.format == AudioStreamWAV.FORMAT_16_BITS
			if st:
				var firings := st.get_length() * bank.rpms[i] / 60.0
				whole = whole and absf(firings - roundf(firings)) < 0.08
	check(looping, "every rpm has a loop on and off the throttle, uncompressed and looping")
	check(whole, "each loop is a whole number of firings, so it repeats without a seam")
	check(bank.oneshots.has("pop") and bank.oneshots.has("starter") and not bank.recorded_shots.has("pop"),
		"its pops and kick are still made, through the two-stroke's own pipe")
	var es := EngineSound.new()
	t.add_child(es)
	es.setup_spec(spec)
	es.bank.bake_now()
	es.rpm = 9960.0
	es.throttle = 1.0
	for i in 20:
		es._process(1.0 / 60.0)
	var recorded := false
	for b in es._assigned["ex_on"]:
		recorded = recorded or es._assigned["ex_on"][b].stream.resource_path.begins_with(TWO_STROKE_DIR)
	check(es.playing_count() > 0 and recorded and es._assigned["in_on"].is_empty(), "riding it plays the recorded loops from the pipe")
	es.queue_free()
	await t.get_tree().process_frame


## The made two-stroke (twins, triples, and anything without recordings): the pipe coming on
## at the powerband, the odd-harmonic buzz of the half-turn port, crackles off the throttle
## and more pops; four-strokes untouched.
func test_two_stroke_synth() -> void:
	var spec := EngineSynth.make_spec("2stroke", 3, 750.0, {"idle": 1050.0, "redline": 10600.0, "peak": 8150.0, "exhaust": "full"})
	check(EngineSynth.pipe_on(spec, 4000.0) < 0.01 and EngineSynth.pipe_on(spec, 8150.0) > 0.95, "off the pipe low down, on it at the powerband")
	var low := EngineSynth.render_loop(spec, "ex_on", EngineSynth.loop_rpm(spec, 4500.0))
	var band := EngineSynth.render_loop(spec, "ex_on", EngineSynth.loop_rpm(spec, 8150.0))
	check(t._rms(band) > t._rms(low) * 1.4, "it comes on the pipe: much louder in the powerband (%.3f against %.3f)" % [t._rms(band), t._rms(low)])
	var info := EngineSynth.loop_info(spec, 9000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var off := EngineSynth._cycle_events(spec, info, false, rng)
	var on := EngineSynth._cycle_events(spec, info, true, rng)
	var four := EngineSynth._cycle_events(EngineSynth.make_spec("inline", 4, 1000.0), EngineSynth.loop_info(EngineSynth.make_spec("inline", 4, 1000.0), 9000.0), false, rng)
	var cracks := func(ev: Array) -> int: return ev.filter(func(e): return e.size() > 4).size()
	check(cracks.call(off) > 0 and cracks.call(on) == 0 and cracks.call(four) == 0, "it crackles off the throttle, not on it; a four doesn't")
	var four_spec := EngineSynth.make_spec("inline", 4, 1000.0, {"exhaust": "full"})
	check(EngineSound.pop_rate(spec, 8000.0, 0.2) > EngineSound.pop_rate(four_spec, 8000.0, 0.2) * 1.4, "and pops more readily than a four")
	# The single's buzz: the port's square shoulders put the odd harmonics over the even.
	var single := EngineSynth.make_spec("2stroke", 1, 250.0, {"idle": 1400.0, "redline": 12500.0, "peak": 9500.0, "exhaust": "full"})
	var r := EngineSynth.loop_rpm(single, 6000.0)
	var x := EngineSynth.render_loop(single, "ex_on", r)
	var orders: Array = t._orders(single, x, r, 8)
	var odd := 0.0
	var even := 0.0
	for k in orders.size():
		if k % 2 == 0:
			odd += orders[k]
		else:
			even += orders[k]
	check(odd > even * 1.5, "a two-stroke single's buzz is strong in odd harmonics (%.2f odd to %.2f even)" % [odd, even])
