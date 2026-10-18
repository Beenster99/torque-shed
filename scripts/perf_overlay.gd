class_name PerfOverlay
extends CanvasLayer
## The performance profiler (F4, or Esc > Debug): a panel at the top left with the frame rate,
## the frame's CPU, physics and GPU times, what the renderer drew (draw calls, primitives,
## objects), the counts of objects, nodes and orphan nodes, memory, the sound players alive, and
## the big per-frame systems' own CPU time, slowest first (see Perf). F11 (or the button on the
## Debug tab) records 60 seconds of it all to a CSV and a JSON file in the game's perf folder,
## to send in; the path is shown, and copied to the clipboard.
##
## Off, nothing here runs: the systems' timers hand back straight away (Perf.on is false) and
## this node doesn't process.

## How long a recording runs, seconds.
const RECORD_S := 60.0
## The folder recordings go in.
const DIR := "user://perf/"
## The engine's monitors put in a recording: [name, Performance monitor, scale].
const MONITORS := [
	["process_ms", Performance.TIME_PROCESS, 1000.0], ["physics_ms", Performance.TIME_PHYSICS_PROCESS, 1000.0],
	["draw_calls", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, 1.0],
	["primitives", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, 1.0],
	["objects_drawn", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, 1.0],
	["video_mem_mb", Performance.RENDER_VIDEO_MEM_USED, 1.0 / 1048576.0],
	["texture_mem_mb", Performance.RENDER_TEXTURE_MEM_USED, 1.0 / 1048576.0],
	["buffer_mem_mb", Performance.RENDER_BUFFER_MEM_USED, 1.0 / 1048576.0],
	["static_mem_mb", Performance.MEMORY_STATIC, 1.0 / 1048576.0],
	["static_mem_max_mb", Performance.MEMORY_STATIC_MAX, 1.0 / 1048576.0],
	["objects", Performance.OBJECT_COUNT, 1.0], ["resources", Performance.OBJECT_RESOURCE_COUNT, 1.0],
	["nodes", Performance.OBJECT_NODE_COUNT, 1.0], ["orphan_nodes", Performance.OBJECT_ORPHAN_NODE_COUNT, 1.0],
	["physics_active", Performance.PHYSICS_3D_ACTIVE_OBJECTS, 1.0],
	["physics_pairs", Performance.PHYSICS_3D_COLLISION_PAIRS, 1.0],
	["physics_islands", Performance.PHYSICS_3D_ISLAND_COUNT, 1.0],
]

## The panel is up.
var shown := false
## Seconds left of a recording, or 0.
var record_left := 0.0
## Where the last recording went (an OS path), for the panel and tests.
var last_file := ""
## The scene's counts, refreshed every couple of seconds while shown: name -> number.
var counts := {}

var _panel: PanelContainer
var _text: Label
var _refresh := 0.0
var _count_t := 0.0
var _note := ""
var _note_t := 0.0
var _mon_sums := {}     # a recording's monitors: name -> [sum, peak, min]
var _frame_ms_sum := 0.0
var _frame_ms_peak := 0.0
var _frames := 0
var _gpu_sum := 0.0
var _cpu_render_sum := 0.0
var _record_s := RECORD_S
var _was_on_before := false   # the panel was up when the recording started


func _ready() -> void:
	layer = 121
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000   # last of the frame, so every system has added its time
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(8.0, 30.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.035, 0.045, 0.82)
	bg.set_content_margin_all(8.0)
	bg.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])
	_text.add_theme_font_override("font", mono)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	_panel.visible = false
	set_process(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if InputMap.has_action("perf_overlay") and event.is_action_pressed("perf_overlay"):
		toggle()
	elif InputMap.has_action("perf_record") and event.is_action_pressed("perf_record"):
		record()


## Shows or hides the panel.
func toggle(on = null) -> void:
	shown = (not shown) if on == null else bool(on)
	_panel.visible = shown
	_set_running()
	_refresh = 0.0
	_count_t = 0.0


## Starts a recording of `seconds` (60 by default); the panel comes up while it runs.
func record(seconds := RECORD_S) -> void:
	if record_left > 0.0:
		return
	_record_s = seconds
	record_left = seconds
	_was_on_before = shown
	if not shown:
		toggle(true)
	_mon_sums = {}
	_frame_ms_sum = 0.0
	_frame_ms_peak = 0.0
	_gpu_sum = 0.0
	_cpu_render_sum = 0.0
	_frames = 0
	Perf.start_recording()
	_count_scene()
	_flash("Recording %d s..." % int(seconds))


func recording() -> bool:
	return record_left > 0.0


func _set_running() -> void:
	var run := shown or record_left > 0.0
	Perf.on = run
	set_process(run)
	if not Graphics.is_headless():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), run)
	if not run:
		Perf.end_frame()   # drop anything half counted


func _flash(text: String, secs := 4.0) -> void:
	_note = text
	_note_t = secs


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_count_t -= delta
	if _count_t <= 0.0:
		_count_t = 2.0
		_count_scene()
	Perf.add("profiler", pt)
	Perf.end_frame()
	if record_left > 0.0:
		_sample(delta)
		record_left -= delta
		if record_left <= 0.0:
			record_left = 0.0
			_finish_recording()
	_note_t -= delta
	_refresh -= delta
	if _refresh <= 0.0 and shown:
		_refresh = 0.5
		_text.text = panel_text()


## One frame of the recording's monitors.
func _sample(delta: float) -> void:
	_frames += 1
	_frame_ms_sum += delta * 1000.0
	_frame_ms_peak = maxf(_frame_ms_peak, delta * 1000.0)
	_gpu_sum += _gpu_ms()
	_cpu_render_sum += _render_cpu_ms()
	for m in MONITORS:
		var v := Performance.get_monitor(m[1]) * float(m[2])
		var s: Array = _mon_sums.get(m[0], [0.0, -INF, INF])
		s[0] += v
		s[1] = maxf(s[1], v)
		s[2] = minf(s[2], v)
		_mon_sums[m[0]] = s


func _gpu_ms() -> float:
	if Graphics.is_headless():
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func _render_cpu_ms() -> float:
	if Graphics.is_headless():
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) \
		+ RenderingServer.get_frame_setup_time_cpu()


## Counts what's in the scene that tends to pile up: sound players (and how many play),
## particle emitters, lights, timers, meshes, bodies.
func _count_scene() -> void:
	var c := {"audio_players": 0, "audio_playing": 0, "particles": 0, "particles_emitting": 0, "lights": 0,
		"timers": 0, "mesh_instances": 0, "rigid_bodies": 0, "label3d": 0}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			c["audio_players"] += 1
			if n.playing:
				c["audio_playing"] += 1
		elif n is MeshInstance3D:
			c["mesh_instances"] += 1
		elif n is CPUParticles3D or n is GPUParticles3D:
			c["particles"] += 1
			if n.emitting:
				c["particles_emitting"] += 1
		elif n is Light3D:
			c["lights"] += 1
		elif n is Timer:
			c["timers"] += 1
		elif n is RigidBody3D:
			c["rigid_bodies"] += 1
		elif n is Label3D:
			c["label3d"] += 1
		stack.append_array(n.get_children())
	counts = c


## The panel's text.
func panel_text() -> String:
	var fps := Engine.get_frames_per_second()
	var lines := PackedStringArray()
	lines.append("PERFORMANCE   %d fps  (%.1f ms)   %s off   %s record %ds" % [fps, 1000.0 / maxf(fps, 1.0),
		Controls.key("perf_overlay"), Controls.key("perf_record"), int(RECORD_S)])
	lines.append("CPU process %.2f ms   physics %.2f ms (%d Hz)   render CPU %.2f ms   GPU %.2f ms" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Engine.physics_ticks_per_second, _render_cpu_ms(), _gpu_ms()])
	lines.append("Drawn: %d draw calls   %dk primitives   %d objects" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	lines.append("Objects %d   nodes %d   orphans %d   resources %d" % [Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
	lines.append("Memory: static %.0f MB   video %.0f MB   physics bodies awake %d, pairs %d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	if not counts.is_empty():
		lines.append("Sounds %d (%d playing)   particles %d (%d on)   lights %d   meshes %d   timers %d" % [counts["audio_players"],
			counts["audio_playing"], counts["particles"], counts["particles_emitting"], counts["lights"], counts["mesh_instances"], counts["timers"]])
	lines.append("")
	lines.append("%-22s %7s %7s %6s" % ["System (CPU)", "avg ms", "peak", "calls"])
	var total := 0.0
	var rows := Perf.ranked()
	for r in rows:
		total += float(r[1])
	for i in mini(rows.size(), 22):
		var r: Array = rows[i]
		lines.append("%-22s %7.2f %7.2f %6.0f" % [str(r[0]).left(22), r[1], r[2], r[3]])
	lines.append("%-22s %7.2f" % ["(all timed)", total])
	if record_left > 0.0:
		lines.append("")
		lines.append("RECORDING... %d s left" % ceili(record_left))
	elif _note_t > 0.0:
		lines.append("")
		lines.append(_note)
	return "\n".join(lines)


func _finish_recording() -> void:
	Perf.stop_recording()
	var report := report_data()
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var base := DIR + "perf_" + stamp
	var jf := FileAccess.open(base + ".json", FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(report, "\t"))
		jf.close()
	var cf := FileAccess.open(base + ".csv", FileAccess.WRITE)
	if cf:
		cf.store_string(report_csv(report))
		cf.close()
	last_file = ProjectSettings.globalize_path(base + ".csv")
	if not Graphics.is_headless():
		DisplayServer.clipboard_set(ProjectSettings.globalize_path(DIR))
	_flash("Saved %s\n(and .json beside it; the folder is copied to the clipboard)" % last_file, 20.0)
	print("Perf report written: ", last_file)
	if not _was_on_before:
		# Leave the panel up a moment to say where the file went.
		_refresh = 0.0
	_set_running()


## Everything a recording found, as a Dictionary (what goes in the .json).
func report_data() -> Dictionary:
	var sys := []
	for r in Perf.recorded():
		sys.append({"system": r[0], "avg_ms": snappedf(r[1], 0.001), "peak_ms": snappedf(r[2], 0.001), "calls_per_frame": snappedf(r[3], 0.01)})
	var mons := {}
	for k in _mon_sums:
		var s: Array = _mon_sums[k]
		mons[k] = {"avg": snappedf(s[0] / maxf(_frames, 1), 0.001), "peak": snappedf(s[1], 0.001), "min": snappedf(s[2], 0.001)}
	var n := maxf(_frames, 1)
	return {
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"when": Time.get_datetime_string_from_system(),
		"seconds": _record_s, "frames": _frames,
		"fps_avg": snappedf(_frames / maxf(_frame_ms_sum / 1000.0, 0.001), 0.1),
		"frame_ms_avg": snappedf(_frame_ms_sum / n, 0.01), "frame_ms_peak": snappedf(_frame_ms_peak, 0.01),
		"gpu_ms_avg": snappedf(_gpu_sum / n, 0.01), "render_cpu_ms_avg": snappedf(_cpu_render_sum / n, 0.01),
		"physics_hz": Engine.physics_ticks_per_second,
		"cpu": OS.get_processor_name(), "cores": OS.get_processor_count(), "os": OS.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_video_adapter_api_version(),
		"window": str(get_viewport().get_visible_rect().size), "graphics_preset": Settings.gfx_preset,
		"players": Net.players.size() + 1 if Net.is_online() else 1,
		"systems": sys, "monitors": mons, "scene_counts": counts, "per_second": Perf.rec_seconds,
	}


## The same as CSV: a header block, the systems, then the monitors.
static func report_csv(r: Dictionary) -> String:
	var out := PackedStringArray()
	for k in ["game_version", "when", "seconds", "frames", "fps_avg", "frame_ms_avg", "frame_ms_peak", "gpu_ms_avg",
			"render_cpu_ms_avg", "physics_hz", "cpu", "cores", "os", "gpu", "driver", "window", "graphics_preset", "players"]:
		out.append("%s,%s" % [k, str(r.get(k, "")).replace(",", ";")])
	out.append("")
	out.append("system,avg_ms,peak_ms,calls_per_frame")
	for s in r["systems"]:
		out.append("%s,%s,%s,%s" % [s["system"], s["avg_ms"], s["peak_ms"], s["calls_per_frame"]])
	out.append("")
	out.append("monitor,avg,peak,min")
	for k in r["monitors"]:
		var m: Dictionary = r["monitors"][k]
		out.append("%s,%s,%s,%s" % [k, m["avg"], m["peak"], m["min"]])
	out.append("")
	out.append("count,value")
	for k in r["scene_counts"]:
		out.append("%s,%s" % [k, r["scene_counts"][k]])
	return "\n".join(out) + "\n"
