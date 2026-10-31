class_name EngineBank
extends RefCounted
## One engine's baked sounds (see EngineSynth): a seamless loop for each rpm bucket, on and off
## the throttle, exhaust side and engine side, plus its pops and bangs, its gearbox's clicks and
## clunks, and its starter (or kick) and the engine catching.
## Baking runs on a worker thread, the buckets nearest idle first, so the bike sounds within a
## moment of getting on; the rest fill in over a second or so. Bikes with the same engine,
## exhaust and gearbox share one bank.

const MAX_BANKS := 10
const SAMPLE_ROOTS := ["user://engine_samples", "res://audio/engines"]
## Recordings of real bikes ticking over (Simon's), one loop per kind of engine, named
## <key>_<rpm>.wav: the key is the most specific of <layout>_<crank>_<exhaust>, <layout>_<crank>,
## <layout>_<exhaust> or <layout>, and the rpm is the speed it was recorded at. Made with
## tools/idle_loop.py. A bike with one plays it around idle in place of the made sound.
const IDLE_ROOTS := ["user://engine_samples/idle", "res://audio/engines/idle"]

static var _banks := {}       # signature -> EngineBank

var spec: Dictionary
var signature := ""
var rpms := PackedFloat32Array()
var loops := {}               # layer -> Array of PackedFloat32Array (empty until baked)
var streams := {}             # layer -> Array of AudioStreamWAV (null until baked)
var baked := PackedInt32Array()   # bucket indices that are baked, in rpm order
var oneshots := {}            # name -> Array of AudioStreamWAV
var bake_ms := 0.0            # how long the whole bank took to bake
var recorded := false         # the loops come from recordings (see load_samples)
var recorded_shots: Array = []   # one-shot kinds that come from recordings
var exhaust_only := false     # recorded loops of the whole bike, with no engine-side layers of their own
var idle_loop: AudioStreamWAV   # a recording of a real bike of this kind ticking over, or null
var idle_rpm := 0.0           # the rpm it was recorded at
var idle_rms := 0.0           # its loudness (RMS, 0..1)
var idle_made_rms := Vector2.ZERO   # the made idle's loudness, exhaust side and engine side (off the throttle)
var _idle_bucket := -1         # the made bucket nearest idle, whose loudness the recording matches
var _mutex := Mutex.new()
var _done: Array = []         # finished work waiting for the main thread: [kind, key, index, samples]
var _task := -1
var _finished := false
var _used := 0


## The bank for this recipe, shared and baking in the background if it's new.
static func for_spec(engine_spec: Dictionary) -> EngineBank:
	var sig := EngineSynth.signature(engine_spec)
	if _banks.has(sig):
		var b: EngineBank = _banks[sig]
		b._used = Time.get_ticks_msec()
		return b
	if _banks.size() >= MAX_BANKS:
		# Forget the bank used longest ago (players still holding it keep it alive).
		var oldest := ""
		var t := 1 << 62
		for k in _banks:
			if _banks[k]._used < t and _banks[k]._finished:
				t = _banks[k]._used
				oldest = k
		if oldest != "":
			_banks.erase(oldest)
	var bank := EngineBank.new(engine_spec)
	_banks[sig] = bank
	var folder := sample_folder(engine_spec)
	if folder != "":
		bank.load_samples(folder)
	if not bank.recorded:
		bank.load_idle(idle_recording(engine_spec))
	bank.start_bake()
	return bank


## A folder of recorded sounds for this engine, if someone has supplied one: the most specific
## of <layout>_<cylinders>_<exhaust>, <layout>_<cylinders>, <layout>_<exhaust> or <layout>,
## under user://engine_samples (drop files in, no import needed) or res://audio/engines
## (shipped with the game: Simon's single-cylinder two-stroke, 2stroke_1).
static func sample_folder(engine_spec: Dictionary) -> String:
	var keys := ["%s_%d_%s" % [engine_spec["layout"], engine_spec["cylinders"], engine_spec["exhaust"]],
		"%s_%d" % [engine_spec["layout"], engine_spec["cylinders"]],
		"%s_%s" % [engine_spec["layout"], engine_spec["exhaust"]], str(engine_spec["layout"])]
	for root in SAMPLE_ROOTS:
		for key in keys:
			var dir: String = root.path_join(key)
			if DirAccess.dir_exists_absolute(dir):
				return dir
	return ""


## Uses recorded sounds from `dir` in place of synthesised ones. Loops are named
## <layer>_<rpm>.wav (ex_on_6000.wav: the exhaust on the throttle, held at 6000 rpm; ex_off,
## in_on and in_off likewise), each a seamless loop. One-shots are pop*, bang*, crack*,
## shift* (every gear change), neutral*, starter* and catch*.wav (the engine firing up off the
## starter). Anything not supplied is synthesised as usual. An rpm with only one of a side's
## loops plays it both on and off the throttle; with no engine-side (in_) loops at all, the
## exhaust loops are the whole bike (exhaust_only) and play from the pipe.
func load_samples(dir: String) -> void:
	var found := {}   # rpm -> {layer: stream}
	var shots := {}
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() != "wav":
			continue
		var base := file.get_basename()
		var path := dir.path_join(file)
		var layer_hit := false
		for layer in EngineSynth.LAYERS:
			var tail := base.trim_prefix(layer + "_")
			if base.begins_with(layer + "_") and tail.is_valid_float():
				var wav := _load_wav(path, true)
				if wav:
					var r := float(tail)
					if not found.has(r):
						found[r] = {}
					found[r][layer] = wav
				layer_hit = true
		if layer_hit:
			continue
		for kind in ["pop", "bang", "crack", "shift", "neutral", "starter", "catch"]:
			if base.begins_with(kind):
				var wav := _load_wav(path, false)
				if wav:
					if not shots.has(kind):
						shots[kind] = []
					shots[kind].append(wav)
	for kind in shots:
		oneshots[kind] = shots[kind]
		recorded_shots.append(kind)
	if found.is_empty():
		return
	var keys := found.keys()
	keys.sort()
	rpms = PackedFloat32Array(keys)
	exhaust_only = true
	for r in keys:
		for side in ["ex", "in"]:
			var on = found[r].get(side + "_on")
			var off = found[r].get(side + "_off")
			if on == null and off != null:
				found[r][side + "_on"] = off
			elif off == null and on != null:
				found[r][side + "_off"] = on
		if found[r].has("in_on"):
			exhaust_only = false
	for layer in EngineSynth.LAYERS:
		var l := []
		var st := []
		for r in keys:
			l.append(PackedFloat32Array())
			st.append(found[r].get(layer))
		loops[layer] = l
		streams[layer] = st
	baked = PackedInt32Array(range(keys.size()))
	recorded = true


## The idle recording for this engine, if there is one: the path of the most specific match
## under IDLE_ROOTS (see there), or "".
static func idle_recording(engine_spec: Dictionary) -> String:
	var keys := ["%s_%s_%s" % [engine_spec["layout"], engine_spec["crank"], engine_spec["exhaust"]],
		"%s_%s" % [engine_spec["layout"], engine_spec["crank"]],
		"%s_%s" % [engine_spec["layout"], engine_spec["exhaust"]], str(engine_spec["layout"])]
	for root in IDLE_ROOTS:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var found := {}   # key -> file
		for f in DirAccess.get_files_at(root):
			var file := f.trim_suffix(".import").trim_suffix(".remap")
			if file.get_extension().to_lower() != "wav":
				continue
			var base := file.get_basename()
			var cut := base.rfind("_")
			if cut > 0 and base.substr(cut + 1).is_valid_float():
				found[base.substr(0, cut)] = file
		for key in keys:
			if found.has(key):
				return root.path_join(found[key])
	return ""


## Uses the recording at `path` (see idle_recording) for this engine's idle.
func load_idle(path: String) -> void:
	if path == "":
		return
	var wav := _load_wav(path, true)
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.data.size() < 1000:
		return
	idle_loop = wav
	var base := path.get_file().get_basename()
	idle_rpm = base.substr(base.rfind("_") + 1).to_float()
	if not wav.has_meta("rms"):
		# Every fourth sample is plenty to know how loud it is (measured the once, like the padding).
		var e := 0.0
		var n := 0
		var frames := int(wav.loop_end) * (2 if wav.stereo else 1)
		for i in range(0, frames, 4):
			var v := wav.data.decode_s16(i * 2) / 32768.0
			e += v * v
			n += 1
		wav.set_meta("rms", sqrt(e / maxi(n, 1)))
	idle_rms = float(wav.get_meta("rms"))
	_idle_bucket = bake_order()[0]


static func _rms(x: PackedFloat32Array) -> float:
	var e := 0.0
	for v in x:
		e += v * v
	return sqrt(e / maxi(x.size(), 1))


static func _load_wav(path: String, loop: bool) -> AudioStreamWAV:
	var wav: AudioStreamWAV = null
	if path.begins_with("res://"):
		wav = ResourceLoader.load(path) as AudioStreamWAV
	else:
		wav = AudioStreamWAV.load_from_file(path)
	if wav and loop and not wav.has_meta("padded"):
		# (The shipped ones are shared, cached by ResourceLoader: set up and padded the once.)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		EngineSynth.pad_loop(wav)
		wav.set_meta("padded", true)
	return wav


func _init(engine_spec: Dictionary) -> void:
	spec = engine_spec
	signature = EngineSynth.signature(spec)
	rpms = EngineSynth.bucket_rpms(spec)
	for layer in EngineSynth.LAYERS:
		var l := []
		var s := []
		l.resize(rpms.size())
		s.resize(rpms.size())
		for i in rpms.size():
			l[i] = PackedFloat32Array()
		loops[layer] = l
		streams[layer] = s
	_used = Time.get_ticks_msec()


func start_bake() -> void:
	if _task < 0 and not _finished:
		_task = WorkerThreadPool.add_task(_bake_all, false, "Engine sound")


## Bakes everything here and now (tests and the render tool).
func bake_now() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	elif not _finished:
		_bake_all()
	poll()


func is_baked() -> bool:
	return _finished and _done.is_empty()


## How many loops are baked so far.
func loop_count() -> int:
	return baked.size() * EngineSynth.LAYERS.size()


## The order buckets are baked in: idle first, then working outwards.
func bake_order() -> Array:
	var order := []
	for i in rpms.size():
		order.append(i)
	var idle: float = spec["idle"]
	order.sort_custom(func(a, b): return absf(log(rpms[a] / idle)) < absf(log(rpms[b] / idle)))
	return order


func _bake_all() -> void:
	var t0 := Time.get_ticks_usec()
	var order := [] if recorded else bake_order()
	var n := 0
	for i in order:
		var bucket := {}
		for layer in EngineSynth.LAYERS:
			bucket[layer] = EngineSynth.render_loop(spec, layer, rpms[i], i + 1)
		_push(["loop", "", i, bucket])
		n += 1
		if n == 2:
			_bake_oneshots()
	if n < 2:
		_bake_oneshots()
	bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_finished = true
	_mutex.unlock()


func _bake_oneshots() -> void:
	# The starter first: it's the first thing you hear. A few takes, so it's never quite the same.
	var kick: bool = spec["kick"]
	_push(["shot", "starter", 0, [EngineSynth.render_starter(spec, kick, 1.0, 1), EngineSynth.render_starter(spec, kick, 1.0, 2),
		EngineSynth.render_starter(spec, kick, 1.0, 3)]])
	_push(["shot", "catch", 0, [EngineSynth.render_catch(spec, kick, 1), EngineSynth.render_catch(spec, kick, 2)]])
	var pops := []
	for i in 4:
		pops.append(EngineSynth.render_pop(spec, 0.7 + 0.25 * i, i + 1))
	_push(["shot", "pop", 0, pops])
	_push(["shot", "bang", 0, [EngineSynth.render_pop(spec, 2.5, 11), EngineSynth.render_pop(spec, 2.2, 12)]])
	_push(["shot", "crack", 0, [EngineSynth.render_pop(spec, 4.0, 21)]])
	# The gearbox's clicks and clunks, three takes of each step ("shift" is the plain change).
	for step in EngineSynth.GEAR_STEPS:
		var takes := []
		for i in (2 if step == "neutral" else 3):
			takes.append(EngineSynth.render_gear(spec, step, i + 1))
		_push(["shot", "neutral" if step == "neutral" else "shift_" + step, 0, takes])
		if step == "low":
			_push(["shot", "shift", 0, takes.duplicate()])


func _push(item: Array) -> void:
	# Turn the samples into PCM bytes here, on the worker, so the main thread only wraps them.
	if item[0] == "loop":
		var b: Dictionary = item[3]
		var bytes := {}
		for layer in b:
			bytes[layer] = EngineSynth.to_bytes(b[layer])
		item.append(bytes)
	else:
		var bytes := []
		for s in item[3]:
			bytes.append(EngineSynth.to_bytes(s))
		item.append(bytes)
	_mutex.lock()
	_done.append(item)
	_mutex.unlock()


## Picks up whatever the worker has finished (main thread). Cheap when there's nothing new.
func poll() -> void:
	if _done.is_empty():
		return
	_mutex.lock()
	var items := _done
	_done = []
	_mutex.unlock()
	for item in items:
		if item[0] == "loop":
			var i: int = item[2]
			var samples: Dictionary = item[3]
			var bytes: Dictionary = item[4]
			for layer in samples:
				loops[layer][i] = samples[layer]
				streams[layer][i] = EngineSynth.to_stream(bytes[layer], true)
			if i == _idle_bucket:
				idle_made_rms = Vector2(_rms(samples["ex_off"]), _rms(samples["in_off"]))
			baked.append(i)
			baked.sort()
		else:
			var list := []
			for b in item[4]:
				list.append(EngineSynth.to_stream(b, false))
			if not recorded_shots.has(item[1]):
				oneshots[item[1]] = list
	if _finished and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## A random one-shot of a kind ("pop", "bang", "crack", "shift", "shift_first", "shift_low",
## "shift_high", "shift_down", "neutral", "starter", "catch"), or null if it isn't baked yet.
func oneshot(kind: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var list: Array = oneshots.get(kind, [])
	if list.is_empty():
		return null
	return list[rng.randi() % list.size()]


## Which loops to play for `rpm` and `load` (0 off the throttle .. 1 on it): a list of
## [layer, bucket, weight, pitch scale]. The two baked buckets either side of the rpm are
## crossfaded (equal power) and each is pitched to the exact rpm; on and off throttle crossfade
## the same way.
func mix_weights(rpm: float, load: float) -> Array:
	var out := []
	if baked.is_empty():
		return out
	rpm = maxf(rpm, 1.0)
	var lo := -1
	var hi := -1
	for i in baked:
		if rpms[i] <= rpm:
			lo = i
		elif hi < 0:
			hi = i
	var pairs := []
	if lo >= 0 and hi >= 0:
		var u := log(rpm / rpms[lo]) / log(rpms[hi] / rpms[lo])
		pairs = [[lo, cos(u * PI * 0.5)], [hi, sin(u * PI * 0.5)]]
	else:
		pairs = [[lo if lo >= 0 else hi, 1.0]]
	var l := clampf(load, 0.0, 1.0)
	var won := sin(l * PI * 0.5)
	var woff := cos(l * PI * 0.5)
	for p in pairs:
		var b: int = p[0]
		var pitch := rpm / rpms[b]
		for side in ["ex", "in"]:
			if won > 0.001:
				out.append([side + "_on", b, float(p[1]) * won, pitch])
			if woff > 0.001:
				out.append([side + "_off", b, float(p[1]) * woff, pitch])
	return out
