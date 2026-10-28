extends RefCounted
## The mix's checks: the volume buses and their sliders, every player on one of them, nothing
## left sounding round the wash bay and the roller door, and a loose part's rattle. Run from
## tests/run_tests.gd (its _test_audio_* functions hand over to these).

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree(), _bike_named()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## The bus `bus` ends up in on its way to Master: "SFX", "Engines" or "Radio" (or "Master" for
## a player that skips the sliders).
static func slider_bus(bus: String) -> String:
	var b := bus
	for i in 8:
		if b in ["SFX", "Engines", "Radio", "Master"] or AudioServer.get_bus_index(b) < 0:
			return b
		b = AudioServer.get_bus_send(AudioServer.get_bus_index(b))
	return b


static func _db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


## The buses: effects, engines and the radio each straight into Master, the rooms' acoustics
## under effects and the engines' own pair under engines; each slider sets its own bus only,
## and the ear defenders muffle effects and engines both.
func test_buses() -> void:
	for b in ["SFX", "Engines", "Radio"]:
		check(AudioServer.get_bus_index(b) >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index(b)) == "Master",
			"the %s bus goes straight to Master" % b)
	check(slider_bus("Room") == "SFX" and slider_bus("Far") == "SFX" and slider_bus("AmbOut") == "SFX",
		"the rooms' acoustics and the outdoor ambience are under the sound effects")
	check(slider_bus("EngineRoom") == "Engines" and slider_bus("EngineFar") == "Engines", "the engines have their own room and far buses")
	var at := Workshop.CENTER + Vector3(0.0, 1.0, 0.0)
	Sfx.set_listener_room("shed")
	check(Sfx.bus_for(at) == "Room" and Sfx.bus_for(at, true) == "EngineRoom" and Sfx.bus_for(Workshop.WASH_CENTER, true) == "EngineFar",
		"an engine's sound picks the room or far bus of its own pair")
	var rv := AudioServer.get_bus_effect(AudioServer.get_bus_index("EngineRoom"), 0) as AudioEffectReverb
	check(rv != null and is_equal_approx(rv.room_size, Sfx.room_reverb().room_size), "and the engines get the room's reverb too")
	var kept := [Settings.sfx_volume, Settings.engine_volume, Settings.radio_volume]
	Settings.sfx_volume = 0.25
	Settings.engine_volume = 1.0
	Settings.radio_volume = 0.5
	Sfx.apply_volumes()
	check(absf(_db("SFX") - linear_to_db(0.25)) < 0.01 and absf(_db("Engines")) < 0.01 and absf(_db("Radio") - linear_to_db(0.5)) < 0.01,
		"each slider sets its own bus (effects %.1f dB, engines %.1f dB, radio %.1f dB)" % [_db("SFX"), _db("Engines"), _db("Radio")])
	Sfx.set_muffled(true)
	check(Sfx.is_muffled() and _db("SFX") < linear_to_db(0.25) - 6.0 and _db("Engines") < -6.0, "ear defenders muffle the effects and the engines")
	Sfx.set_muffled(false)
	check(not Sfx.is_muffled() and absf(_db("Engines")) < 0.01, "and take them off again")
	Settings.sfx_volume = kept[0]
	Settings.engine_volume = kept[1]
	Settings.radio_volume = kept[2]
	Sfx.apply_volumes()
	Sfx.set_listener_room("")


## The Settings tab's sliders: sound effects, engines and radio next to each other; moving one
## sets its bus, and they're saved and loaded with the other settings.
func test_sliders() -> void:
	var kept := [Settings.sfx_volume, Settings.engine_volume, Settings.radio_volume]
	var menu := MainMenu.new()
	t.add_child(menu)
	await t.get_tree().process_frame
	var sfx := menu.find_child("SfxVolume", true, false) as HSlider
	var eng := menu.find_child("EngineVolume", true, false) as HSlider
	var radio := menu.find_child("RadioVolume", true, false) as HSlider
	check(sfx != null and eng != null and radio != null and sfx.get_parent() == eng.get_parent() and eng.get_parent() == radio.get_parent(),
		"the Settings panel's Sound tab has sound effects, engines and radio sliders together")
	if sfx == null or eng == null:
		menu.queue_free()
		return
	var tab := menu.find_child("Sound", true, false) as Control
	menu.open_tab(tab)
	await t.get_tree().process_frame
	var shown := tab.get_global_rect().intersection(t.get_viewport().get_visible_rect())
	check(tab is ScrollContainer and shown.encloses(radio.get_global_rect()),
		"they're at the top of the Settings tab, on screen (the radio slider's bottom at %.0f of %.0f)" % [radio.get_global_rect().end.y, shown.end.y])
	var sib := sfx.get_parent()
	check(sib.get_child(sfx.get_index() - 1) is Label and (sib.get_child(sfx.get_index() - 1) as Label).text == "Sound effects volume"
		and (sib.get_child(eng.get_index() - 1) as Label).text == "Engines volume", "each labelled")
	sfx.value = 0.3
	eng.value = 0.65
	check(is_equal_approx(Settings.sfx_volume, 0.3) and absf(_db("SFX") - linear_to_db(0.3)) < 0.01,
		"the sound effects slider turns the effects bus down (%.1f dB)" % _db("SFX"))
	check(is_equal_approx(Settings.engine_volume, 0.65) and absf(_db("Engines") - linear_to_db(0.65)) < 0.01 and absf(_db("SFX") - linear_to_db(0.3)) < 0.01,
		"the engines slider sets the engines bus and leaves the effects alone (%.1f dB)" % _db("Engines"))
	Settings.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	check(is_equal_approx(float(cfg.get_value("audio", "sfx", -1.0)), 0.3) and is_equal_approx(float(cfg.get_value("audio", "engines", -1.0)), 0.65),
		"both are saved with the settings")
	Settings.sfx_volume = 0.9
	Settings.engine_volume = 0.1
	Settings.load_settings()
	check(is_equal_approx(Settings.sfx_volume, 0.3) and is_equal_approx(Settings.engine_volume, 0.65), "and come back next time")
	menu.queue_free()
	Settings.sfx_volume = kept[0]
	Settings.engine_volume = kept[1]
	Settings.radio_volume = kept[2]
	Settings.save_settings()
	Sfx.apply_volumes()


## In the shed and out on a bike, every player that's sounding goes through a slider's bus:
## the engines (yours, the customers', the traffic) through Engines, tools, the washer, knocks,
## dings, horns and the ambience through SFX, the radio through Radio. None straight to Master.
func test_routing() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await _ticks(10)
	var at: Vector3 = main.walker.global_position
	var shots := [Sfx.play_at("clink", at), Sfx.impact("metal", "concrete", 0.8, at), Sfx.play_at("wash_ding", at)]
	# (read now: a short variant can have played out and gone by the time of the check)
	var shot_buses: Array = shots.map(func(s): return slider_bus(s.bus) if s != null else "")
	Sfx.play_ui("wash_ding")
	Sfx.set_loop(main.walker._work_sound, "jet")
	var faithful: int = t._bike_named("Old Faithful")
	Shed.request({"a": "mount", "bike": faithful})
	await _ticks(5)
	check(main.bike != null and main.audio != null, "on a bike, its engine sound is there")
	if main.bike:
		main.bike.engine_on = true
		main.audio.running = true
	await _ticks(30)
	var wrong := []
	var engines := 0
	var effects := 0
	for p in t.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false) + t.get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		var bus := slider_bus(str(p.get("bus")))
		var engine := false
		var n: Node = p
		while n:
			if n is EngineSound or n is TrafficSounds:
				engine = true
			n = n.get_parent()
		if bus == "Master" or bus not in ["SFX", "Engines", "Radio"]:
			wrong.append("%s on %s" % [p.get_path(), p.get("bus")])
		elif engine and bus != "Engines":
			wrong.append("engine %s on %s" % [p.get_path(), p.get("bus")])
		elif not engine and bus == "Engines":
			wrong.append("effect %s on the engines bus" % p.get_path())
		if bus == "Engines":
			engines += 1
		elif bus == "SFX":
			effects += 1
	check(wrong.is_empty() and engines > 0 and effects > 0, "every player goes through its slider's bus (%d engines, %d effects) %s" % [engines, effects, str(wrong.slice(0, 6))])
	var eng_bus := ""
	if main.audio:
		var players: Array = main.audio.find_children("*", "AudioStreamPlayer3D", true, false)
		eng_bus = str(players[0].bus) if not players.is_empty() else ""
	check(eng_bus.begins_with("Engine"), "the bike's engine is on the engines bus (%s)" % eng_bus)
	check(shot_buses.all(func(b): return b == "SFX"), "a knock, a part landing and a ding are on the effects bus %s" % str(shot_buses))
	main._leave()
	main.queue_free()
	await _ticks(2)


## The power washer sits with the rest of the tools: its jet no louder than the grinder, and
## its start no louder than the grinder's.
func test_washer_level() -> void:
	var jet := _rms(Sfx.stream("jet"))
	var tools := {}
	for s in ["grinder", "scrub", "spray", "ratchet", "changer", "polisher"]:
		tools[s] = _rms(Sfx.stream(s))
	var loudest := 0.0
	for s in tools:
		loudest = maxf(loudest, tools[s])
	check(jet <= loudest * 1.02, "the pressure washer's jet is no louder than the other tools (%.3f rms, loudest tool %.3f)" % [jet, loudest])
	check(_peak(Sfx.stream("jet_on")) <= _peak(Sfx.stream("grinder_up")) and _peak(Sfx.stream("jet_off")) <= _peak(Sfx.stream("grinder_down")),
		"nor is it starting up and stopping")


static func _rms(w: AudioStreamWAV) -> float:
	var sum := 0.0
	var n := w.data.size() / 2
	for i in range(0, n, 4):
		var x := w.data.decode_s16(i * 2) / 32768.0
		sum += x * x
	return sqrt(sum / maxf(n / 4.0, 1.0))


static func _peak(w: AudioStreamWAV) -> float:
	var p := 0
	for i in range(0, w.data.size() - 1, 2):
		p = maxi(p, absi(w.data.decode_s16(i)))
	return p / 32768.0


## A loose part rattles: the made sound is a buzz of quick, irregular contacts with nothing
## ringing on, not a ping; on the move it's a loop from the loose part, louder and higher with
## the revs and the road, and no pinging one-shots. Bolted up, it stops.
func test_rattle() -> void:
	# The sound itself.
	var d := SfxSynth.make("rattle", 0)
	check(SfxSynth.is_loop("rattle") and d.size() > SfxSynth.RATE * 2, "the rattle is a loop (%.1f s)" % (d.size() / float(SfxSynth.RATE)))
	var frame := int(SfxSynth.RATE * 0.002)
	var env := PackedFloat32Array()
	for i in range(0, d.size() - frame, frame):
		var s := 0.0
		for j in frame:
			s = maxf(s, absf(d[i + j]))
		env.append(s)
	var top := 0.0
	for e in env:
		top = maxf(top, e)
	# Onsets: a frame jumping well up on the one before.
	var onsets := []
	for i in range(1, env.size()):
		if env[i] > top * 0.25 and env[i] > env[i - 1] * 1.8:
			onsets.append(i)
	var gaps := []
	for i in range(1, onsets.size()):
		gaps.append(float(onsets[i] - onsets[i - 1]) * 2.0)   # ms
	var mean := 0.0
	for g in gaps:
		mean += g
	mean /= maxf(gaps.size(), 1.0)
	var vari := 0.0
	for g in gaps:
		vari += (g - mean) * (g - mean)
	var cv := sqrt(vari / maxf(gaps.size(), 1.0)) / maxf(mean, 0.001)
	var buzz := gaps.filter(func(g): return g <= 12.0).size()
	check(onsets.size() > 60 and buzz > onsets.size() / 4, "a buzz of contacts: %d hits in 3 s, %d of them within 12 ms of the last" % [onsets.size(), buzz])
	check(cv > 0.6, "irregular, never a steady beat (gaps vary %.0f%% about %.0f ms)" % [cv * 100.0, mean])
	# Nothing rings on: between fits it's soon 20 dB down (the old clink rang for a good while).
	var low := 0
	for e in env:
		if e < top * 0.1:
			low += 1
	var quiet := low / float(env.size())
	check(quiet > 0.2 and _ring_ms(SfxSynth.make("clink", 0)) > 80.0,
		"no ringing ping: %.0f%% of the time it's 20 dB under its peaks (the old clink rang %.0f ms)" % [quiet * 100.0, _ring_ms(SfxSynth.make("clink", 0))])
	var zc := 0
	for i in range(1, d.size()):
		if (d[i] > 0.0) != (d[i - 1] > 0.0):
			zc += 1
	var bright := zc / 2.0 / (d.size() / float(SfxSynth.RATE))
	check(bright > 700.0 and bright < 6000.0, "metallic: its energy round %.0f Hz" % bright)
	# On the move.
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(20.0, 91)
	await _ticks(10)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null, "out on an adventure")
	if main.bike == null:
		main.queue_free()
		return
	trip.world.preload_range(0.0, 1200.0)
	main.bike.engine_on = true
	main.bike.fuel_litres = main.bike.build.fuel_capacity
	Shed.request({"a": "roadside_fault", "kind": "rattle", "slot": "exhaust"})
	await _ticks(3)
	# (the world's one-shots: a sat nav or menu blip isn't the rattle pinging)
	var in_world := func() -> Array:
		return t.get_tree().get_nodes_in_group(Sfx.ONESHOT_GROUP).filter(func(p): return p is AudioStreamPlayer3D and not p.is_queued_for_deletion())
	var before: int = in_world.call().size()
	var r: AudioStreamPlayer3D = main._rattle
	check(r != null and r.playing and str(r.get_meta("loop", "")) == "rattle" and r.get_parent() == main.bike,
		"the loose exhaust rattles on the bike (%s)" % (str(r.get_meta("loop", "")) if r else "nothing"))
	if r == null:
		main.queue_free()
		return
	var tip: Vector3 = main.bike.model.to_global(main.bike.model.slot_bounds("exhaust").get_center())
	check(r.global_position.distance_to(tip) < 0.2, "from the exhaust itself (%.2f m off)" % r.global_position.distance_to(tip))
	check(slider_bus(r.bus) == "SFX", "on the sound effects bus")
	main.bike.rpm = main.bike.build.idle_rpm
	main.bike.surface = "tarmac"
	main._rattle_sound()
	var idle := [float(r.get_meta("base_db")), r.pitch_scale]
	main.bike.rpm = main.bike.build.redline * 0.95
	main._rattle_sound()
	var revved := [float(r.get_meta("base_db")), r.pitch_scale]
	main.bike.linear_velocity = -main.bike.global_basis.z * 15.0
	main.bike.speed = 15.0
	main.bike.surface = "gravel"
	main._rattle_sound()
	var rough := [float(r.get_meta("base_db")), r.pitch_scale]
	check(revved[0] > idle[0] + 4.0 and revved[1] > idle[1], "it rattles louder and quicker with the revs (%.0f dB x%.2f idling, %.0f dB x%.2f revved)" % [idle[0], idle[1], revved[0], revved[1]])
	check(rough[0] > revved[0] and rough[1] >= revved[1], "and more on rough ground (%.0f dB x%.2f on gravel)" % [rough[0], rough[1]])
	await _ticks(120)
	var sounding: Array = in_world.call().map(func(p): return str(p.get_meta("sound", p.name)))
	check(sounding.size() <= before, "no pinging one-shots on top (%d, was %d: %s)" % [sounding.size(), before, str(sounding)])
	main.bike.engine_on = false
	main.bike.linear_velocity = Vector3.ZERO
	main.bike.speed = 0.0
	main._rattle_sound()
	check(not r.playing, "stopped with the engine off it's quiet")
	main.bike.engine_on = true
	main._rattle_sound()
	Roadside._fix(Shed.me(), faithful, "rattle", {"quality": 1.0})
	main._sync_faults()
	await _ticks(3)
	check(not r.playing, "bolted up, the rattle stops")
	AdventureTrip.instant = false
	main._leave()
	main.queue_free()
	await _ticks(2)


## How long after its loudest moment `d` takes to fall 20 dB and stay there (ms), on 2 ms frames.
static func _ring_ms(d: PackedFloat32Array) -> float:
	var frame := int(SfxSynth.RATE * 0.002)
	var env := PackedFloat32Array()
	for i in range(0, d.size() - frame, frame):
		var s := 0.0
		for j in frame:
			s = maxf(s, absf(d[i + j]))
		env.append(s)
	var at := 0
	for i in env.size():
		if env[i] > env[at]:
			at = i
	var floor_v := env[at] * 0.1
	var i2 := at
	while i2 < env.size() and env[i2] > floor_v:
		i2 += 1
	return (i2 - at) * 2.0


## The ringing tones (dings) in `d`: a narrow tone between `from` Hz (1 kHz unless said) and 5 kHz
## standing well over the sound's own level and ringing on for 0.2 s or more. [[seconds, Hz, ms], ...]
static func dings(d: PackedFloat32Array, from := 1000.0) -> Array:
	var win := 441   # 10 ms (a 100 Hz wide look, so the 4% steps miss nothing)
	var total := 0.0
	for x in d:
		total += x * x
	var rms := sqrt(total / maxf(d.size(), 1.0))
	var out := []
	var f := from
	while f < 5000.0:
		var w := TAU * f / SfxSynth.R
		var c := 2.0 * cos(w)
		var held := 0
		var top := 0.0
		var i := 0
		while i + win <= d.size():
			var s1 := 0.0
			var s2 := 0.0
			for j in win:
				var s := d[i + j] + c * s1 - s2
				s2 = s1
				s1 = s
			var a := sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) / (win * 0.5)
			if a > rms * 1.5 and a > top * 1.5:
				top = a
				held = 1
			elif top > 0.0 and a > top * 0.25:
				held += 1
			else:
				if held >= 20:
					out.append([snappedf(float(i) / SfxSynth.R, 0.1), roundi(f), held * 10])
				top = 0.0
				held = 0
			i += win
		f *= 1.04
	return out


## The sound name of `s`, one of Sfx's (a loop's synthesised take or a recording), or "".
static func sound_of(s: AudioStream) -> String:
	for k in Sfx._streams:
		if (Sfx._streams[k] as Array).has(s):
			return str(k)
	for k in Sfx._recorded:
		if (Sfx._recorded[k] as Array).has(s):
			return str(k)
	return ""


## Out by the roller door and in the wash bay, standing about: there's no shop bell or door
## ding anywhere in the background (not in the town's bustle, which is heard full there by the
## High Street, nor any other ambience loop, nor customers coming in), and nothing in the world
## is left sounding or ringing on there.
func test_idle_quiet() -> void:
	# The detector would catch a shop bell rung into a loop, so finding nothing means there's none.
	var syn := SfxSynth.new(5)
	var rung := SfxSynth.make("amb_town", 0)
	syn.ring(rung, int(SfxSynth.R * 3.0), 2650.0, 0.12, 5.0, true)
	check(not dings(rung).is_empty(), "the ding detector would catch a shop bell in the town's loop %s" % str(dings(rung).slice(0, 2)))
	for sound in ["amb_town", "amb_out", "tone_shed", "tone_sales", "hum_fluoro", "crickets"]:
		var found := dings(SfxSynth.make(sound, 0))
		check(found.is_empty(), "there's no bell in the %s loop: nothing rings round it %s" % [sound, str(found.slice(0, 3))])
	# Nor a held note lower down: pigeons cooing as pure tones came round as a chime every few seconds.
	var low := dings(SfxSynth.make("amb_town", 0), 150.0)
	check(low.is_empty(), "and nothing in the town's bustle holds a note, down to 150 Hz %s" % str(low.slice(0, 3)))
	# Nobody rings the shop bell or the door chime by themselves: customers come in quietly.
	for path in ["res://scripts/contracts_view.gd", "res://scripts/sales_view.gd", "res://scripts/customer.gd", "res://scripts/sfx_ambience.gd"]:
		var src := FileAccess.get_file_as_string(path)
		check(not src.contains("ring_bell") and not src.contains("Sfx.bell") and not src.contains("\"bell_chime\""),
			"%s rings no shop bell or door chime" % path.get_file())
	# In the shed, left alone a while, then stood at each spot.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	var wait := 0
	while not Sfx.synth_done and wait < 120 * 60:
		await t.get_tree().physics_frame
		wait += 1
	await _ticks(240)
	var spots := {"the roller door": Workshop.CENTER + Vector3(0.0, 0.0, Workshop.HALF.y + 1.5), "the wash bay": Workshop.WASH_CENTER}
	for spot in spots:
		var at: Vector3 = spots[spot]
		main.walker.place(Transform3D(Basis(), at))
		await _ticks(120)
		check(SfxAmbience.town_level(at, 0.0, 0.0) > 0.5, "at %s the town's bustle is heard (%.2f)" % [spot, SfxAmbience.town_level(at, 0.0, 0.0)])
		var seen := {}
		var near := []
		for k in 10:
			for p in t.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
				var a := p as AudioStreamPlayer3D
				if not a.playing or a.global_position.distance_to(at) > 10.0 or a.is_in_group(Sfx.ONESHOT_GROUP):
					continue
				# The compressor in the shed's back corner runs a while now and then and stops itself.
				if str(a.get_meta("loop", "")) == "compressor":
					continue
				near.append("%s (%s)" % [a.get_path(), str(a.get_meta("loop", sound_of(a.stream)))])
			for p in t.get_tree().get_nodes_in_group(Sfx.ONESHOT_GROUP):
				if p is Node3D and (p as Node3D).global_position.distance_to(at) < 12.0:
					seen[p.get_instance_id()] = true
			await _ticks(120)
		check(near.is_empty(), "at %s nothing's left sounding nearby over 10 s %s" % [spot, str(near.slice(0, 4))])
		check(seen.size() <= 2, "and nothing keeps going off there (%d one-shots in 10 s)" % seen.size())
		var amb := []
		for p in t.get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
			var a2 := p as AudioStreamPlayer
			if a2.playing and a2.volume_db > -40.0:
				amb.append(sound_of(a2.stream))
		check(amb.has("amb_town") and amb.all(func(s): return s in ["amb_out", "amb_town", "birds", "crickets", "tone_shed", "hum_fluoro", "hum_led", "rain", "rain_roof"]),
			"at %s only the outdoor ambience plays %s" % [spot, str(amb)])
	main._leave()
	main.queue_free()
	await _ticks(2)
