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
##
## With --network the same rides are drawn on the road network (AdventureWorld.network, the Esc > Debug toggle) at the
## same spots, and each place measures what is round its road either way (measure), so the sheet shows the gap between
## the two and how it closes (postcards.sh --both draws every place both ways).

const Sheet := preload("res://tests/postcards/sheet.gd")
const WORLD := "res://tests/postcards/world"
const PLACES := "res://tests/postcards/places.json"
## Frames timed at each view once it has settled, and the frames it waits for the land before giving up on it.
const TIMED := 12
const SETTLE_MS := 90000
## The land near the camera (m: RealLand.NET_NEAR, where the network ride's is finest) a view waits for, and how long it
## waits after that for the far land before taking the view as it is (ms).
const NEAR_LAND := 1100.0
const FAR_WAIT_MS := 15000
## How far round the road view's spot measure counts what there is (m), and how far along the road either side it
## follows its height and heading, every STEP.
const REACH := 400.0
const STRETCH := 300.0
const STEP := 2.0
## The names the things set beside the road are given (AdventureProps, AdventureJunctions, AdventureStops), counted by
## measure.
const SITES := ["LimitSign", "FuelStation", "Banner", "Junction_", "Stop_"]

var out_dir := "user://postcards"
## The size each view is rendered at.
var size := Vector2i(1280, 720)
var only: Array = []
## This run's share of the places, [K, N]: the Kth of every N (CI renders them on several machines at once).
var group := [0, 1]
var fetch := false
## No frame times: just the pictures (a quick look at a change of your own).
var quick := false
## The network ride (AdventureWorld.network, the Esc > Debug toggle): every road round the camera, not just the plan's.
## Its land follows the camera off the ride's own tiles: --fetch --network fills world/heights with those too.
var network := false
## Just the pictures and stats.json: postcards.sh makes the sheet once every place is done.
var no_sheet := false
## Folders of runs to make one sheet of, instead of running (CI's machines' shares).
var merge: Array = []
var label := ""
## The graphics preset (Graphics.PRESETS) the views are drawn at: medium is what a machine without a graphics card
## can draw a frame of in half a second.
var preset := "medium"
## The renderer the views must be drawn with ("" any): CI asks for forward_plus, so a machine whose Vulkan didn't come
## up fails rather than quietly drawing its share with OpenGL.
var renderer := ""
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
		elif a.begins_with("--renderer="):
			renderer = a.trim_prefix("--renderer=")
		elif a.begins_with("--merge="):
			merge = Array(a.trim_prefix("--merge=").split(",", false))
		elif a == "--fetch":
			fetch = true
		elif a == "--no-sheet":
			no_sheet = true
		elif a == "--quick":
			quick = true
		elif a == "--network":
			network = true
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
	if renderer != "" and not fetch and RenderingServer.get_current_rendering_method() != renderer:
		stats["places"].append({"id": "renderer", "error": "Drawn with %s, not %s: is the Vulkan driver there?" % [
			RenderingServer.get_current_rendering_method(), renderer]})
		push_error(stats["places"][0]["error"])
		return
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
			by_id["%s %s" % [p["id"], p.get("mode", "single")]] = p
		for name in DirAccess.get_files_at(d):
			if name.ends_with(".png") and not name.begins_with("contact-sheet") and d != into:
				DirAccess.copy_absolute(d.path_join(name), into.path_join(name))
	for p: Dictionary in spec["places"]:
		for mode in ["single", "network"]:
			if by_id.has("%s %s" % [p["id"], mode]):
				out["places"].append(by_id["%s %s" % [p["id"], mode]])
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
	PlaceLook.month_override = int(place.get("month", spec.get("month", 0)))
	var plan := plan_of(place)
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		got["error"] = str(res.get("error", "no plan"))
		return got
	var pack: RealPack = res["pack"]
	got["plan_s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	got["km"] = snappedf(pack.max_km(), 0.01)
	var a: Array = place["from"]
	var prof := PlaceProfile.of_cell(RealRegion.cell_of(float(a[0]), float(a[1])))
	got["profile"] = "%s · %s · %s · %s%s" % [prof.get("country", "?"), prof.get("koppen", "?"), prof.get("altitude_band", "?"),
		prof.get("density", "?"), " (guessed)" if bool(prof.get("guessed", false)) else ""]
	got["theme"] = pack.theme
	got["month"] = PlaceLook.month_override
	got["mode"] = "network" if network else "single"
	if fetch and not network:
		return got   # (planning fetched the ride's heights: that's all a fetch is for)
	var w := AdventureWorld.new()
	AdventureWorld.network = network
	if network:
		w.roads_region = RealRegion.get_region(str(plan["region"]))
	w.setup(pack, 1)
	if w.route.look.has("kit"):
		got["theme"] = "%s, %s" % [str(w.route.look["kit_name"]).to_lower(), ["January", "February", "March", "April", "May", "June",
			"July", "August", "September", "October", "November", "December"][int(w.route.look["month"]) - 1]]
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	Daylight.set_tint(w.route.look["sky"] if w.route.look.has("sky") else AdventureTheme.get_value(w.route.theme, "sky", {}))
	if Daylight.current:
		Daylight.current.set_time(float(place.get("hour", spec.get("hour", 11.0))))
	var s := float(place.get("s", w.route.length * 0.35))
	got["s"] = roundi(s)
	for view: String in spec["views"]:
		cam.global_transform = view_xf(w, s, view)
		w.follow(cam.global_position)   # (as a ride does under its rider: the land and skyline round the camera)
		var t_view := Time.get_ticks_msec()
		var settled := await _settle(w)
		print("postcards: %s %s %s in %.1f s" % [place["id"], view, "built" if settled else "not all built", (Time.get_ticks_msec() - t_view) / 1000.0])
		got["load_s"] = got.get("load_s", (Time.get_ticks_msec() - t0) / 1000.0)
		if view == spec["views"][0]:
			got["gap"] = measure(w, s)
		if fetch:
			continue   # (the network ride's land fetched its heights round the camera: that's all a fetch is for)
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(picture(place["id"], network, view)))
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


## The file name of place `id`'s picture from `view`, on the road network or not.
static func picture(id: String, on_network: bool, view: String) -> String:
	return "%s%s_%s.png" % [id, "-net" if on_network else "", view]


## What there is round `s` metres along `w`'s road, to set one way of drawing it beside the other (the sheet's gap):
##   things     roadside things within REACH of it by kind (trees, bushes, posts, signs, stops...): MultiMesh instances
##              count one each, and a kind is its node's name without its MM_/Trees_ prefix and its number
##   road_pts   the points of the road's surface (and its markings: line_pts) within REACH, how finely it's made
##   bumps_cm   how far the road's height strays from its own 30 m average along STRETCH either side (RMS, and the
##              worst: bump_max_cm), so a lumpy road shows however hilly the place
##   kink_deg   the sharpest turn of the road's heading between two points STEP apart along the plan's line (on the
##              network, on the same road and out of its junctions)
##   found      the share of the plan's line with a road under it (the network's roads only follow the plan's)
static func measure(w: AdventureWorld, s: float) -> Dictionary:
	var centre := w.transform_at(s, 0.0).origin
	var things := {}
	var road_pts := 0
	var line_pts := 0
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = n.multimesh
			if mm == null:
				continue
			var xf: Transform3D = (n as Node3D).global_transform
			var k := _kind(n.name)
			for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
				if (xf * mm.get_instance_transform(i).origin).distance_to(centre) <= REACH:
					things[k] = int(things.get(k, 0)) + 1
		elif n is MeshInstance3D:
			var nm := str(n.name)
			var road := nm == "Road" or nm.begins_with("Deck_")
			if road or nm == "Lines":
				var pts := _points_within((n as MeshInstance3D), centre)
				if road:
					road_pts += pts
				else:
					line_pts += pts
		elif n is Label3D or (n.get_class() == "Node3D" and SITES.any(func(pre): return str(n.name).begins_with(pre))):
			# (a sign's words, and the things set beside the road: stops, junctions, banners, limit signs)
			if (n as Node3D).global_position.distance_to(centre) <= REACH:
				var k := "sign words" if n is Label3D else _kind(n.name)
				things[k] = int(things.get(k, 0)) + 1
	var ys: Array[float] = []
	var hs: Array[float] = []
	var edges: Array[int] = []   # (the network's road each point is on: a turn from one to the next isn't a kink)
	var tries := 0
	var hint := -1
	var t := maxf(0.0, s - STRETCH)
	while t <= minf(w.route.length, s + STRETCH):
		tries += 1
		if w.roads == null:
			ys.append(w.route.height_at_s(t))
			hs.append(w.route.heading_at_s(t))
			edges.append(0)
		else:
			var xz := w.route.xz_at(t, 0.0)
			var on := w.roads.net.locate(xz[0], xz[1], hint)
			if not on.is_empty() and bool(on["on_road"]):
				hint = int(on["edge"])
				ys.append(w.roads.net.road_y(hint, float(on["s"])))
				hs.append(float(on["heading"]))
				edges.append(hint if int(on["node"]) < 0 else -1 - edges.size())
		t += STEP
	var off: Array[float] = []
	var half := int(15.0 / STEP)
	for i in range(half, ys.size() - half):
		var sum := 0.0
		for j in range(i - half, i + half + 1):
			sum += ys[j]
		off.append(absf(ys[i] - sum / (half * 2 + 1)))
	var sq := 0.0
	var worst := 0.0
	for o in off:
		sq += o * o
		worst = maxf(worst, o)
	var kink := 0.0
	for i in range(1, hs.size()):
		if edges[i] != edges[i - 1]:
			continue
		kink = maxf(kink, absf(wrapf(hs[i] - hs[i - 1], -PI * 0.5, PI * 0.5)))
	return {"things": things, "road_pts": road_pts, "line_pts": line_pts,
		"bumps_cm": snappedf(sqrt(sq / maxi(1, off.size())) * 100.0, 0.1), "bump_max_cm": snappedf(worst * 100.0, 0.1),
		"kink_deg": snappedf(rad_to_deg(kink), 0.1), "found": snappedf(float(ys.size()) / maxi(1, tries), 0.01)}


## A thing's kind from its node's name: "MM_autumn_tree" and "Trees_autumn_tree" are both "autumn tree".
static func _kind(node_name: String) -> String:
	var k := node_name.rstrip("0123456789_-@").trim_prefix("@")
	for pre in ["MM_", "Trees_", "kit_"]:
		k = k.trim_prefix(pre)
	return k.to_snake_case().replace("_", " ").strip_edges()


## How many of mesh `mi`'s points are within REACH of `centre`.
static func _points_within(mi: MeshInstance3D, centre: Vector3) -> int:
	if mi.mesh == null:
		return 0
	var xf := mi.global_transform
	if not (xf * mi.get_aabb()).grow(REACH).has_point(centre):
		return 0
	var n := 0
	for i in mi.mesh.get_surface_count():
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for p in v:
			if (xf * p).distance_to(centre) <= REACH:
				n += 1
	return n


## Waits until the world round the camera is all built (its chunks, land and ridges), then a few frames more for the
## shadows and the eye to adjust. False when it gave up waiting.
func _settle(w: AdventureWorld) -> bool:
	# Nothing is drawn while it builds: a frame on a machine without a graphics card takes half a second to draw, and the
	# world only takes in so much a frame, so drawing them would make the wait minutes long.
	RenderingServer.render_loop_enabled = false
	await _frames(4)
	var end := Time.get_ticks_msec() + SETTLE_MS
	var done := false
	var near_in := -1
	while Time.get_ticks_msec() < end:
		await _frames(3)
		# (the network ride's roads are its blocks, the planned road's its chunks)
		# (a block whose ground isn't all in can't be laid out: the land's wait covers that ground)
		var roads_in := RoadStreamer.wanted(w.roads.riders(), 600.0).all(func(k): return w.roads.blocks.has(k) or not w.roads.can_build(k)) \
			if w.roads != null else w.wanted_chunks().all(func(c): return w.chunks.has(c))
		if not roads_in:
			continue
		if w.land == null or not w.land.busy():
			done = true
			break
		# (the far land can take minutes more, where it's built up on the network ride: once the near land is in, it gets
		# FAR_WAIT_MS more and then the view is taken as it is)
		if _near_land_in(w.land):
			if near_in < 0:
				near_in = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - near_in > FAR_WAIT_MS:
				done = true
				break
	RenderingServer.render_loop_enabled = true
	await _frames(6)
	return done


## Whether `land` has laid out all it's going to within NEAR_LAND of where it follows (its finest blocks).
static func _near_land_in(land: RealLand) -> bool:
	for item: Dictionary in land._queue:
		if float(item["d"]) <= NEAR_LAND:
			return false
	for k: Vector2i in land._tasks:
		if RealLand._centre(k).distance_to(land._at) <= NEAR_LAND:
			return false
	return true


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
