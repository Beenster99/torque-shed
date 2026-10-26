extends Node
## Postcards: the same eight places of the world (places.json) seen the same four ways on every build, made into one
## contact sheet with each place's frame times and memory, so a change to how the world looks or runs shows up before
## anyone rides it. Run it with postcards.sh, which gives it a screen:
##   tests/postcards/postcards.sh [--only=dales,atlas] [--out=DIR]
## Everything it reads is in tests/postcards/world/ (bake.py, then --fetch for the heights): it never touches the network,
## so a postcard only changes when the game does.
##
## Each place is a short ride planned between its two pins, as the shed's map plans one (AdventurePlans), laid out by the
## game's own AdventureWorld under the game's own sky (World's environment, Daylight, Lighting) at a fixed hour, without
## traffic or weather so two runs agree. The views stand a third of the way along (the middle has the fuel stop):
##   road   eye level on the road, looking along it
##   side   on the verge, looking out across the land
##   back   a little above the road, looking back the way it came
##   vista  high above and behind, looking down the road ahead over the land

const Sheet := preload("res://tests/postcards/sheet.gd")
const WORLD := "res://tests/postcards/world"
const PLACES := "res://tests/postcards/places.json"
## Frames timed at each view once it has settled, and the frames it waits for the land before giving up on it.
const TIMED := 12
const SETTLE_MS := 60000

var out_dir := "user://postcards"
## The size each view is rendered at.
var size := Vector2i(1280, 720)
var only: Array = []
## This run's share of the places, [K, N]: the Kth of every N (CI renders them on several machines at once).
var group := [0, 1]
var fetch := false
## No frame times: just the pictures (a quick look at a change of your own).
var quick := false
## Just the pictures and stats.json: postcards.sh makes the sheet once every place is done.
var no_sheet := false
## Folders of runs to make one sheet of, instead of running (CI's machines' shares).
var merge: Array = []
var label := ""
## The graphics preset (Graphics.PRESETS) the views are drawn at: medium is what a machine without a graphics card
## can draw a frame of in half a second.
var preset := "medium"
var stats := {"places": []}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(",", false))
		elif a.begins_with("--group="):
			var kn := a.trim_prefix("--group=").split("/")
			group = [int(kn[0]), maxi(1, int(kn[1]))]
		elif a.begins_with("--label="):
			label = a.trim_prefix("--label=")
		elif a.begins_with("--size="):
			var wh := a.trim_prefix("--size=").split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("--preset="):
			preset = a.trim_prefix("--preset=")
		elif a.begins_with("--merge="):
			merge = Array(a.trim_prefix("--merge=").split(",", false))
		elif a == "--fetch":
			fetch = true
		elif a == "--no-sheet":
			no_sheet = true
		elif a == "--quick":
			quick = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES))
	if not merge.is_empty():
		stats = merged(spec, merge, out_dir)
	else:
		await _run(spec)
	stats["label"] = label
	stats["views"] = spec["views"]
	var f := FileAccess.open(out_dir.path_join("stats.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(stats, " "))
	f.close()
	if not fetch and not no_sheet:
		var sheet: Image = await Sheet.make(self, spec, stats, out_dir)
		sheet.save_png(out_dir.path_join("contact-sheet.png"))
		sheet.save_jpg(out_dir.path_join("contact-sheet.jpg"), 0.88)
	print("postcards: done in %.1f s, %s" % [float(stats.get("seconds", 0.0)), ProjectSettings.globalize_path(out_dir)])
	get_tree().quit(0 if stats["places"].all(func(p): return p.get("error", "") == "") else 1)


func _run(spec: Dictionary) -> void:
	use_own_world(fetch)
	get_window().size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Settings.day_night_cycle = false
	Settings.apply_preset(preset)
	var sky := World.new()
	sky.name = "Sky"
	add_child(sky)
	sky._build_environment()
	var cam := Camera3D.new()
	cam.far = 9000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	var t_all := Time.get_ticks_msec()
	for place: Dictionary in chosen(spec["places"], only, group):
		var got := await _place(place, spec, cam)
		stats["places"].append(got)
		print("postcards: %s %s" % [place["id"], JSON.stringify(got)])
	stats["seconds"] = snappedf((Time.get_ticks_msec() - t_all) / 1000.0, 0.1)
	stats["preset"] = preset
	stats["renderer"] = "%s, %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()]
	stats["version"] = str(ProjectSettings.get_setting("application/config/version", ""))


## The places of `places` a run takes: those named in `ids` (all when it's empty), and of those the Kth of every N for
## `group` [K, N].
static func chosen(places: Array, ids: Array, group: Array) -> Array:
	var out: Array = []
	var i := 0
	for p: Dictionary in places:
		if not ids.is_empty() and not ids.has(p["id"]):
			continue
		if i % int(group[1]) == int(group[0]):
			out.append(p)
		i += 1
	return out


## One run's stats from the runs in folders `dirs` (each a share of the places), the places in places.json's order, and
## their pictures copied into `into`. Its time is the shares' added up.
static func merged(spec: Dictionary, dirs: Array, into: String) -> Dictionary:
	var out := {"places": [], "seconds": 0.0}
	var by_id := {}
	for d: String in dirs:
		var v = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("stats.json")))
		if not v is Dictionary:
			continue
		for k in ["preset", "renderer", "version"]:
			if v.has(k):
				out[k] = v[k]
		out["seconds"] = float(out["seconds"]) + float(v.get("seconds", 0.0))
		for p: Dictionary in v.get("places", []):
			by_id[p["id"]] = p
		for name in DirAccess.get_files_at(d):
			if name.ends_with(".png") and not name.begins_with("contact-sheet") and d != into:
				DirAccess.copy_absolute(d.path_join(name), into.path_join(name))
	for p: Dictionary in spec["places"]:
		if by_id.has(p["id"]):
			out["places"].append(by_id[p["id"]])
	return out


## Points the game's world store at the postcards' own copy (and nothing else), offline; with `fetching`, the heights
## the rides use are fetched into it (the one time it touches the network: postcards.sh --fetch).
static func use_own_world(fetching := false) -> void:
	CellStore.dir = WORLD
	CellStore.offline = true
	RealRegion.cell_dirs = [WORLD] as Array[String]
	HeightTiles.dirs = [WORLD.path_join("heights")] as Array[String]
	HeightTiles.offline = not fetching
	HeightTiles.disk = ProjectSettings.globalize_path(WORLD.path_join("heights")) if fetching else "user://postcards-no-heights"


## The plan of place `place`'s ride: from its first pin to its second, over the one cell its first pin is in.
static func plan_of(place: Dictionary) -> Dictionary:
	var a: Array = place["from"]
	var b: Array = place["to"]
	var cell := RealRegion.cell_of(float(a[0]), float(a[1]))
	var frame := RealRegion.cell_middle(cell)
	var pa := RealRegion.to_frame(frame, float(a[0]), float(a[1]))
	var pb := RealRegion.to_frame(frame, float(b[0]), float(b[1]))
	return AdventurePlans.clean({"region": RealRegion.cells_area_id([cell] as Array[Vector2i]), "region_hash": "",
		"pins": [[pa.x, pa.y], [pb.x, pb.y]], "names": [place.get("title", "")], "mode": "main"})


## Where the camera stands for view `view` at `s` metres along `w`'s road.
static func view_xf(w: AdventureWorld, s: float, view: String) -> Transform3D:
	var half := w.route.width_at_s(s) * 0.5
	match view:
		"side":
			var xf := w.transform_at(s, half + 2.5)
			return Transform3D(xf.basis.rotated(Vector3.UP, -PI * 0.5), xf.origin + Vector3.UP * 1.7)
		"back":
			var xf := w.transform_at(s, 0.0)
			var b := xf.basis.rotated(Vector3.UP, PI)
			return Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(-4.0)), xf.origin + Vector3.UP * 3.0)
		"vista":
			var xf := w.transform_at(maxf(0.0, s - 120.0), 0.0)
			var ahead := w.transform_at(s + 300.0, 0.0).origin
			var eye := xf.origin + Vector3.UP * 60.0
			return Transform3D(Basis.looking_at(ahead - eye, Vector3.UP), eye)
		_:
			var xf := w.transform_at(s, 0.0)
			return Transform3D(xf.basis, xf.origin + Vector3.UP * 1.6)


func _place(place: Dictionary, spec: Dictionary, cam: Camera3D) -> Dictionary:
	var got := {"id": place["id"], "title": place.get("title", place["id"]), "error": "", "views": {}}
	var t0 := Time.get_ticks_msec()
	var plan := plan_of(place)
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		got["error"] = str(res.get("error", "no plan"))
		return got
	var pack: RealPack = res["pack"]
	got["plan_s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	got["km"] = snappedf(pack.max_km(), 0.01)
	got["theme"] = pack.theme
	if fetch:
		return got   # (planning fetched the ride's heights: that's all a fetch is for)
	var w := AdventureWorld.new()
	w.setup(pack, 1)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	Daylight.set_tint(AdventureTheme.get_value(w.route.theme, "sky", {}))
	if Daylight.current:
		Daylight.current.set_time(float(place.get("hour", spec.get("hour", 11.0))))
	var s := float(place.get("s", w.route.length * 0.35))
	got["s"] = roundi(s)
	for view: String in spec["views"]:
		cam.global_transform = view_xf(w, s, view)
		var settled := await _settle(w)
		got["load_s"] = got.get("load_s", (Time.get_ticks_msec() - t0) / 1000.0)
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s_%s.png" % [place["id"], view]))
		var v := {} if quick else await _timed()
		v["settled"] = settled
		got["views"][view] = v
	got["load_s"] = snappedf(got["load_s"], 0.1)
	got["static_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	got["video_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	got["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	w.queue_free()
	await _frames(2)
	return got


## Waits until the world round the camera is all built (its chunks, land and ridges), then a few frames more for the
## shadows and the eye to adjust. False when it gave up waiting.
func _settle(w: AdventureWorld) -> bool:
	# Nothing is drawn while it builds: a frame on a machine without a graphics card takes half a second to draw, and the
	# world only takes in so much a frame, so drawing them would make the wait minutes long.
	RenderingServer.render_loop_enabled = false
	await _frames(4)
	var end := Time.get_ticks_msec() + SETTLE_MS
	var done := false
	while Time.get_ticks_msec() < end:
		await _frames(3)
		if w.wanted_chunks().all(func(c): return w.chunks.has(c)) and (w.land == null or not w.land.busy()):
			done = true
			break
	RenderingServer.render_loop_enabled = true
	await _frames(6)
	return done


## The frame times (ms: mean, 95th percentile, worst) over TIMED frames, and what the last of them drew.
func _timed() -> Dictionary:
	var ms: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in TIMED:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	return frame_stats(ms).merged({
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	})


## Mean, 95th percentile and worst of frame times `ms`.
static func frame_stats(ms: Array[float]) -> Dictionary:
	if ms.is_empty():
		return {"ms": 0.0, "p95": 0.0, "worst": 0.0}
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for m in ms:
		sum += m
	return {"ms": snappedf(sum / ms.size(), 0.1), "p95": snappedf(sorted[mini(ms.size() - 1, int(ms.size() * 0.95))], 0.1),
		"worst": snappedf(sorted[-1], 0.1)}


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
