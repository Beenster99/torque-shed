extends Node
## The network ride's frame times, measured the same way before and after a change (Simon, 30 Oct: "lag spikes while
## riding", "general slow FPS"). The real game (main.tscn) rides a bundled region's tour on the road network at a steady
## road speed in real time, traffic and all, and each frame's time, the main thread's process and physics time, the
## draw calls, objects and primitives (and those of the sun's shadow) and the systems Perf times are written down.
## Run it with ride_perf.sh:
##   tests/ride_perf/ride_perf.sh                          # the Dales and Shodoshima, headless: the main thread's times
##   tests/ride_perf/ride_perf.sh --draw                   # drawn (on the processor under xvfb): the draw call counts
##   tests/ride_perf/ride_perf.sh --only=dales --metres=3000 --speed=25
## Headless, nothing is drawn, so its frame times are the game's own work (the spikes); drawn on the processor the frame
## times are the software renderer's, so only the counts mean anything there.

const Rides := preload("res://tests/rides.gd")

## The rides: a bundled region's tour, from how far along it.
const RIDES := {"dales": {"region": "dales", "from": 1500.0}, "shodoshima": {"region": "shodoshima", "from": 300.0}}
## A frame this much longer than the ride's median is a spike (ms).
const SPIKE_MS := 12.0

var only: Array = []
var metres := 3000.0
var speed := 25.0
var draw := false
var out := "user://ride_perf.json"
## A crew of two (ride_perf.sh --crew): "host" or "client", each its own game on this machine; the client rides GAP m
## behind the host, and each also measures how smoothly the other's bike is drawn.
var crew := ""
const GAP := 30.0
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(",", false))
		elif a.begins_with("--metres="):
			metres = float(a.trim_prefix("--metres="))
		elif a.begins_with("--speed="):
			speed = float(a.trim_prefix("--speed="))
		elif a == "--draw":
			draw = true
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--crew="):
			crew = a.trim_prefix("--crew=")
	AdventureWorld.network = true
	AdventureTrip.instant = true
	Shed.demo_bikes = true
	if draw:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_window().size = Vector2i(1280, 720)
	Engine.max_fps = 0
	var results := {}
	for id: String in RIDES:
		if only.is_empty() or only.has(id):
			results[id] = await _ride(id)
			print("RIDE PERF %s %s" % [id, JSON.stringify(results[id])])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, " "))
	f.close()
	get_tree().quit(0)


func _ride(id: String) -> Dictionary:
	var spec: Dictionary = RIDES[id]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var plan := AdventurePlans.tour(str(spec["region"]))
	var trip: AdventureTrip = main.trip
	if crew != "":
		Settings.player_name = "Perf %s" % crew
		if crew == "host":
			main._host()
		else:
			main._join("127.0.0.1")
		await _until(func():
			if crew == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
				Shed.request({"a": "adventure_start", "plan": plan, "seed": 42, "title": "Perf"})
			return trip.on_trip() and main.bike != null and _remote_bike() != null, 120.0)
	else:
		main._start_session()
		Shed.start_new("Tester", 7)
		await get_tree().physics_frame
		var faithful := 0
		for b in Shed.bikes:
			if Shed.bikes[b]["name"] == "Old Faithful":
				faithful = b
		main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
		main._left_bike = 0
		Adventure.start(plan, 42)
		await _until(func(): return trip.on_trip() and main.bike != null, 120.0)
	var got := {}
	if not trip.on_trip() or main.bike == null or (crew != "" and _remote_bike() == null):
		got["error"] = "not out on the ride"
		return await _done(got)
	var w := trip.world
	var from := float(spec["from"]) - (GAP if crew == "client" else 0.0)
	trip.jump(from - w.distance_of(main.bike.global_position, "own"))
	# Settled: the land and roads round the start built, as when a rider's been riding a while.
	var t_settle := Time.get_ticks_msec()
	var still := 0
	while still < 120 and Time.get_ticks_msec() - t_settle < 90000:
		var a := Time.get_ticks_usec()
		_hold(w, from)
		await get_tree().process_frame
		still = still + 1 if Time.get_ticks_usec() - a < 30000 else 0
	got["settle_s"] = snappedf((Time.get_ticks_msec() - t_settle) / 1000.0, 0.1)
	# A crew sets off together: the host a moment after both have settled, the client as soon as it sees the host go.
	if crew == "host":
		var go := Time.get_ticks_msec() + 3000
		await _until(func():
			_hold(w, from)
			return Time.get_ticks_msec() > go, 5.0)
	elif crew == "client":
		var start_s := [NAN]
		await _until(func():
			_hold(w, from)
			var rb := _remote_bike()
			if rb == null:
				return false
			var rs := w.distance_of(rb.global_position, "perf_them")
			if is_nan(start_s[0]):
				start_s[0] = rs
			return rs - float(start_s[0]) > 1.0, 60.0)
	if OS.get_cmdline_user_args().has("--census"):
		got["census"] = census(main, get_viewport().get_camera_3d())
	if OS.get_cmdline_user_args().has("--listeners"):
		for c in Shed.changed.get_connections():
			var cb: Callable = c["callable"]
			var q := Time.get_ticks_usec()
			cb.call()
			var obj := cb.get_object()
			print("LISTENER %.2f ms %s.%s" % [(Time.get_ticks_usec() - q) / 1000.0, obj.get_script().resource_path if obj and obj.get_script() else str(obj), cb.get_method()])
	Perf.on = true
	var frames: Array = []
	var s := from
	var last := Time.get_ticks_usec()
	var vp := get_viewport().get_viewport_rid()
	var t_ride := Time.get_ticks_msec()
	var them: Array = []   # [frame seconds, their distance along the road as drawn here]
	var ticks := Engine.get_physics_frames()
	while s < from + metres and s < w.route.total - 60.0:
		_hold(w, s)
		Perf.end_frame()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		s += speed * ms / 1000.0
		var f := {"ms": ms, "proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "ticks": Engine.get_physics_frames() - ticks}
		ticks = Engine.get_physics_frames()
		var sys := {}
		for k in Perf._frame:
			sys[k] = Perf._frame[k] / 1000.0
		f["sys"] = sys
		if draw:
			f["draws"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			f["objects"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			f["prims"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			f["shadow_draws"] = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			f["shadow_objects"] = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
			f["shadow_prims"] = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		frames.append(f)
		if crew != "" and _remote_bike() != null:
			them.append([ms / 1000.0, w.distance_of(_remote_bike().global_position, "perf_them")])
		if frames.size() > 40000:
			break
	Perf.on = false
	got["ride_s"] = snappedf((Time.get_ticks_msec() - t_ride) / 1000.0, 0.1)
	got["metres"] = roundi(s - from)
	got.merge(summary(frames, draw))
	if crew != "":
		got["them"] = smoothness(them, speed)
	got["streaming"] = w.timing_text()
	return await _done(got)


func _remote_bike() -> Node3D:
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			return rp.bike
	return null


## How smoothly the other rider's bike was drawn, from `them` ([frame s, their distance along the road]) while they rode
## steadily at `v`: how far each frame's move along the road was from v x the frame's time (m): the 99th percentile, the
## worst, and how many frames were out by more than half a metre (a jump you'd see) or went back.
static func smoothness(them: Array, v: float) -> Dictionary:
	var off: Array = []
	var back := 0
	for i in range(1, them.size()):
		var moved := float(them[i][1]) - float(them[i - 1][1])
		if absf(moved) > 200.0:
			continue   # (the road's distance wrapped or a jump along it)
		off.append(absf(moved - v * float(them[i][0])))
		if moved < -0.05:
			back += 1
	if off.is_empty():
		return {}
	off.sort()
	return {"frames": off.size(), "p99_m": snappedf(off[int(off.size() * 0.99)], 0.01), "worst_m": snappedf(off[-1], 0.01),
		"jumps": off.filter(func(x): return x > 0.5).size(), "back": back}


func _hold(w: AdventureWorld, s: float) -> void:
	if main.bike == null:
		return
	var xf := w.transform_at(s, -1.6)
	main.bike.place(xf.origin, w.heading_at(s))
	main.bike.linear_velocity = xf.basis * Vector3(0, 0, -speed)


func _done(got: Dictionary) -> Dictionary:
	if crew != "":
		# (stay a moment so the other finishes its ride with us on the road)
		var until := Time.get_ticks_msec() + (8000 if crew == "host" else 2000)
		await _until(func(): return Time.get_ticks_msec() > until, 10.0)
		Net.leave()
	main.queue_free()
	Shed.stop()
	for i in 3:
		await get_tree().process_frame
	return got


func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > seconds * 1000.0:
			return false
		await get_tree().process_frame
	return true


## What there is to draw round the camera: for each kind of thing (its node's name without numbers, and its parent's),
## how many there are within their visibility range (and 600 m), their triangles (a MultiMesh's times its instances) and how many
## of those cast a shadow, biggest first.
static func census(root: Node, cam: Camera3D) -> Array:
	var by := {}
	var stack: Array[Node] = [root]
	var re := RegEx.create_from_string("[-_]?[0-9]+")
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not n is GeometryInstance3D or not (n as Node3D).is_visible_in_tree():
			continue
		var g := n as GeometryInstance3D
		var d := g.global_position.distance_to(cam.global_position) if cam else 0.0
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end + 600.0:
			continue
		var tris := 0
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			tris = _tris((g as MeshInstance3D).mesh)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			tris = _tris(mm.mesh) * (mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count)
		var key := "%s/%s %s" % [re.sub(str(n.get_parent().name), "", true), re.sub(str(n.name), "", true), n.get_class()]
		var row: Array = by.get(key, [0, 0, 0])
		row[0] += 1
		row[1] += tris
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			row[2] += tris
		by[key] = row
	var keys := by.keys()
	keys.sort_custom(func(a, b): return int(by[a][1]) > int(by[b][1]))
	var total := [0, 0, 0]
	for k in keys:
		for i in 3:
			total[i] += int(by[k][i])
	var out := [["all", total]]
	for k in keys.slice(0, 40):
		out.append([k, by[k]])
	return out


static func _tris(m: Mesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		if not m is ArrayMesh:
			continue
		var idx: int = (m as ArrayMesh).surface_get_array_index_len(i)
		n += (idx if idx > 0 else (m as ArrayMesh).surface_get_array_len(i)) / 3
	return n


## The frames' average, median, 1% low (the 99th percentile frame time), worst, spikes, frames over 33 ms; the main
## thread's process and physics time on average; the systems that took the most in the spikes; and drawn, the counts.
static func summary(frames: Array, with_draws: bool) -> Dictionary:
	if frames.is_empty():
		return {"frames": 0}
	var ms: Array = frames.map(func(f): return float(f["ms"]))
	var sorted := ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var med: float = sorted[n / 2]
	var total := 0.0
	for x in ms:
		total += x
	var out := {"frames": n, "avg_ms": snappedf(total / n, 0.01), "median_ms": snappedf(med, 0.01),
		"p99_ms": snappedf(sorted[mini(n - 1, int(n * 0.99))], 0.01), "worst_ms": snappedf(sorted[-1], 0.1),
		"spikes": sorted.filter(func(x): return x > med + SPIKE_MS).size(), "over33": sorted.filter(func(x): return x > 33.0).size(),
		"fps": snappedf(1000.0 * n / total, 0.1)}
	var proc := 0.0
	var phys := 0.0
	for f in frames:
		proc += float(f["proc"])
		phys += float(f["phys"])
	out["process_ms"] = snappedf(proc / n, 0.01)
	var spiky: Array = frames.filter(func(f): return float(f["ms"]) > med + SPIKE_MS)
	out["ticks_in_spikes"] = snappedf(spiky.reduce(func(a, f): return a + int(f["ticks"]), 0) / maxf(1.0, spiky.size()), 0.1)
	out["ticks_a_frame"] = snappedf(frames.reduce(func(a, f): return a + int(f["ticks"]), 0) / float(n), 0.01)
	out["physics_ms"] = snappedf(phys / n, 0.01)
	# What took the time in the spikes, and on average.
	var in_spikes := {}
	var avg := {}
	for f in frames:
		for k in f["sys"]:
			avg[k] = float(avg.get(k, 0.0)) + float(f["sys"][k]) / n
			if float(f["ms"]) > med + SPIKE_MS:
				in_spikes[k] = maxf(float(in_spikes.get(k, 0.0)), float(f["sys"][k]))
	out["sys_avg"] = _top(avg, 12)
	var worst := frames.duplicate()
	worst.sort_custom(func(a, b): return float(a["ms"]) > float(b["ms"]))
	out["worst_frames"] = worst.slice(0, 8).map(func(f): return {"ms": snappedf(float(f["ms"]), 0.1), "ticks": f["ticks"],
		"sys": _top(f["sys"], 4)})
	out["sys_spike_max"] = _top(in_spikes, 12)
	if with_draws:
		for key in ["draws", "objects", "prims", "shadow_draws", "shadow_objects", "shadow_prims"]:
			var sum := 0.0
			var top := 0
			for f in frames:
				sum += float(f[key])
				top = maxi(top, int(f[key]))
			out[key] = roundi(sum / n)
			out[key + "_max"] = top
	return out


static func _top(d: Dictionary, k: int) -> Dictionary:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return float(d[a]) > float(d[b]))
	var out := {}
	for key in keys.slice(0, k):
		out[key] = snappedf(float(d[key]), 0.01)
	return out
