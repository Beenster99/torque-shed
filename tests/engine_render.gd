extends Node
## Renders engine sounds to .wav files for listening outside the game:
##   godot --headless --path . res://tests/engine_render.tscn -- --out=DIR [--only=triple]
## For each engine: a rev sweep (idle, a pull to the redline, roll off with pops, a blip and a
## downshift bang), plus the gear-shift sounds and the starters. Mixed the way the chase camera
## hears it: mostly exhaust, some engine.

const CASES := [
	["single_450_stock", "single", 1, 450.0, {"idle": 1500.0, "redline": 11000.0, "peak": 8000.0, "exhaust": "stock"}],
	["single_450_straight", "single", 1, 450.0, {"idle": 1500.0, "redline": 11000.0, "peak": 8000.0, "exhaust": "straight", "kick": true}],
	["twin360_750_slip", "twin", 2, 750.0, {"idle": 1050.0, "redline": 7700.0, "peak": 5300.0, "exhaust": "slip"}],
	["parallel270_700_full", "parallel", 2, 700.0, {"idle": 1300.0, "redline": 9500.0, "peak": 7000.0, "exhaust": "full"}],
	["vtwin90_1100_race", "vtwin", 2, 1100.0, {"idle": 1000.0, "redline": 8100.0, "peak": 5200.0, "exhaust": "race", "dry_clutch": true,
		"shift": "slick", "quickshifter": true}],
	["boxer_1200_stock", "boxer", 2, 1200.0, {"idle": 950.0, "redline": 7900.0, "peak": 5300.0, "exhaust": "stock"}],
	["triple_850_slip", "triple", 3, 850.0, {"idle": 1250.0, "redline": 10500.0, "peak": 7500.0, "exhaust": "slip"}],
	["triple_850_full_cone", "triple", 3, 850.0, {"idle": 1250.0, "redline": 10500.0, "peak": 7500.0, "exhaust": "full", "intake": "cone"}],
	["inline4_1000_race", "inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "peak": 9500.0, "exhaust": "race"}],
	["inline4_600_stock", "inline", 4, 600.0, {"idle": 1100.0, "redline": 14000.0, "peak": 10000.0, "exhaust": "stock"}],
	["crossplane_1000_full", "inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0, "peak": 9500.0, "exhaust": "full", "crank": "crossplane"}],
	["2stroke_125_straight", "2stroke", 1, 125.0, {"idle": 1450.0, "redline": 14600.0, "peak": 11250.0, "exhaust": "straight", "kick": true}],
	["2stroke_500_twin_full", "2stroke", 2, 500.0, {"idle": 1150.0, "redline": 11400.0, "peak": 8800.0, "exhaust": "full"}],
	["2stroke_750_triple_race", "2stroke", 3, 750.0, {"idle": 1050.0, "redline": 10600.0, "peak": 8150.0, "exhaust": "race"}],
]


func _ready() -> void:
	var out_dir := "user://engine_wavs"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if OS.get_cmdline_user_args().has("--time"):
		var sp := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0})
		for layer in EngineSynth.LAYERS:
			var t := Time.get_ticks_usec()
			var s := EngineSynth.render_loop(sp, layer, 8000.0)
			print("%s: %d samples in %d ms" % [layer, s.size(), (Time.get_ticks_usec() - t) / 1000])
		var t1 := Time.get_ticks_usec()
		EngineSynth.render_pop(sp, 1.0)
		print("pop %d ms" % ((Time.get_ticks_usec() - t1) / 1000))
		t1 = Time.get_ticks_usec()
		EngineSynth.render_starter(sp)
		print("starter %d ms" % ((Time.get_ticks_usec() - t1) / 1000))
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--loops"):
		# Raw loops at idle, mid and near the redline, every layer, unnormalised (for tuning).
		for c in CASES:
			if only != "" and not str(c[0]).contains(only):
				continue
			var sp := EngineSynth.make_spec(c[1], c[2], c[3], c[4])
			for r in [float(sp["idle"]), float(sp["redline"]) * 0.5, float(sp["redline"]) * 0.95]:
				for layer in EngineSynth.LAYERS:
					var s := EngineSynth.render_loop(sp, layer, r)
					var rep := PackedFloat32Array()
					while rep.size() < EngineSynth.RATE:
						rep.append_array(s)
					EngineSynth.save_wav(rep, out_dir.path_join("loop_%s_%d_%s.wav" % [c[0], roundi(r), layer]))
		get_tree().quit()
		return
	for c in CASES:
		if only != "" and not str(c[0]).contains(only):
			continue
		var spec := EngineSynth.make_spec(c[1], c[2], c[3], c[4])
		var t0 := Time.get_ticks_msec()
		var bank := EngineBank.new(spec)
		bank.bake_now()
		var baked := Time.get_ticks_msec() - t0
		var drive := render_drive(bank)
		EngineSynth.save_wav(drive, out_dir.path_join("%s_sweep.wav" % c[0]))
		print("%s: baked %d loops in %d ms, %.1f s rendered" % [c[0], bank.loop_count(), baked, drive.size() / float(EngineSynth.RATE)])
	if only == "" or only == "shift":
		var all := PackedFloat32Array()
		for kind in ["slick", "click", "clunk", "neutral"]:
			for i in 3:
				all.append_array(EngineSynth.render_shift(kind, i))
			all.append_array(_silence(0.3))
		EngineSynth.save_wav(all, out_dir.path_join("gear_shifts_slick_click_clunk_neutral.wav"))
		var spec := EngineSynth.make_spec("inline", 4, 1000.0, {"idle": 1200.0, "redline": 13500.0})
		var st := EngineSynth.render_starter(spec, false)
		st.append_array(_silence(0.3))
		st.append_array(EngineSynth.render_starter(EngineSynth.make_spec("2stroke", 1, 125.0, {"idle": 1450.0}), true, 0.8))
		EngineSynth.save_wav(st, out_dir.path_join("starter_and_kick.wav"))
	get_tree().quit()


func _silence(s: float) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(int(EngineSynth.RATE * s))
	return p


## A short ride on the spot: idle, pull to the redline, shut off (pops), blip, downshift bang.
func render_drive(bank: EngineBank) -> PackedFloat32Array:
	var spec := bank.spec
	var idle: float = spec["idle"]
	var red: float = spec["redline"]
	# [seconds, rpm at the end, throttle]
	var plan := [[1.2, idle, 0.0], [2.6, red * 0.97, 1.0], [0.25, red * 0.98, 1.0], [1.8, idle * 1.6, 0.0], [0.5, idle, 0.0],
		[0.25, red * 0.55, 1.0], [0.25, red * 0.6, 1.0], [1.0, idle * 1.4, 0.0], [0.6, idle, 0.0]]
	var rate := EngineSynth.RATE
	var total := 0
	for p in plan:
		total += int(p[0] * rate)
	var out := PackedFloat32Array()
	out.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pos := {}   # loop key -> play position
	var rpm := idle
	var load := 0.0
	var i := 0
	var overrun := 0.0
	for p in plan:
		var n := int(p[0] * rate)
		var from := rpm
		for j in n:
			var f := float(j) / n
			rpm = lerpf(from, p[1], f) if p[2] > 0.5 else lerpf(from, p[1], 1.0 - pow(1.0 - f, 2.0))
			load += (float(p[2]) - load) * (0.004 if p[2] > load else 0.002)
			var mix := bank.mix_weights(rpm, load)
			var s := 0.0
			for w in mix:
				var key: String = "%s/%d" % [w[0], w[1]]
				var loop: PackedFloat32Array = bank.loops[w[0]][w[1]]
				if loop.is_empty():
					continue
				var ph: float = pos.get(key, 0.0)
				var k := int(ph)
				var fr := ph - k
				var a := loop[k % loop.size()]
				var b := loop[(k + 1) % loop.size()]
				s += (a + (b - a) * fr) * float(w[2]) * (1.0 if str(w[0]).begins_with("ex") else 0.55)
				ph += float(w[3])
				if ph >= loop.size():
					ph -= loop.size()
				pos[key] = ph
			out[i] += s
			# Pops on the overrun.
			if p[2] < 0.5 and rpm > maxf(idle * 2.2, 3000.0):
				overrun += 1.0 / rate
				var chance: float = EngineSound.pop_rate(spec, rpm, overrun) / rate
				if rng.randf() < chance:
					var pop := EngineSynth.render_pop(spec, rng.randf_range(0.6, 1.4), rng.randi())
					for q in pop.size():
						if i + q < total:
							out[i + q] += pop[q] * 0.8
			else:
				overrun = 0.0
			i += 1
	# Normalise to a comfortable listening level.
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		var g := 0.9 / peak
		for q in out.size():
			out[q] *= g
	return out
