extends "res://tests/postcards/postcards.gd"
## Pictures of a river beside a real road on the road network, as a ride sees it (the postcards' sky and settling), for
## checking the water and its banks (RealLand) before and after a change:
##   xvfb-run -a godot --path . res://tests/river_shots.tscn -- --out=/tmp/shots --from=46.36,8.97 --to=46.31,9.0 [--n=3]
## The world's cells are fetched from its store as a ride would (CellStore), so it needs the network; run it with a
## user:// of its own (XDG_DATA_HOME). Spots are the first places along the road, STEP_APART apart, with river or lake
## (RealPack.WATER cover) NEAR to FAR off it; each is seen from the verge, from part-way to the water and from above.
## --probe prints the cover, heights, ground and water level (RealTerrain.water_at) out from the road to each instead.

const NEAR := 20.0
const FAR := 140.0
const STEP_APART := 600.0

var from := Vector2.ZERO
var to := Vector2.ZERO
var n := 3


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--from="):
			var v := a.trim_prefix("--from=").split(",")
			from = Vector2(float(v[0]), float(v[1]))
		elif a.begins_with("--to="):
			var v := a.trim_prefix("--to=").split(",")
			to = Vector2(float(v[0]), float(v[1]))
		elif a.begins_with("--n="):
			n = int(a.trim_prefix("--n="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cell := RealRegion.cell_of(from.x, from.y)
	print("river_shots: fetching ", cell, " ", CellStore.fetch_cells([cell] as Array[Vector2i]))
	get_window().size = size
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
	var place := {"id": "river", "title": "River", "from": [from.x, from.y], "to": [to.x, to.y]}
	var plan := plan_of(place)
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		push_error("river_shots: no plan: %s" % res.get("error", ""))
		get_tree().quit(1)
		return
	var pack: RealPack = res["pack"]
	AdventureWorld.network = true
	var w := AdventureWorld.new()
	w.roads_region = RealRegion.get_region(str(plan["region"]))
	w.setup(pack, 1)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	Daylight.set_tint(w.route.look["sky"] if w.route.look.has("sky") else AdventureTheme.get_value(w.route.theme, "sky", {}))
	if Daylight.current:
		Daylight.current.set_time(11.0)
	var spots: Array = []
	var last := -INF
	var t := pack.terrain
	var s := 0.0
	while s < w.route.length and spots.size() < n:
		s += 20.0
		if s - last < STEP_APART:
			continue
		for lat: float in [NEAR, -NEAR, 40.0, -40.0, 70.0, -70.0, 100.0, -100.0, FAR, -FAR]:
			var p := w.transform_at(s, lat).origin
			if t.cover(p.x + w.origin.x, p.z + w.origin.z) == RealPack.WATER:
				spots.append([s, lat])
				last = s
				break
	print("river_shots: spots ", spots)
	if OS.get_cmdline_user_args().has("--probe"):
		for sp: Array in spots:
			for k in 25:
				var lat := float(sp[1]) * k / 16.0
				var p := w.transform_at(float(sp[0]), lat).origin + w.origin
				print("probe s %d lat %.0f cover %d h %.2f ground %.2f water %s" % [int(sp[0]), lat, t.cover(p.x, p.z), t.height(p.x, p.z), w.route.ground_at(p.x, p.z), str(t.water_at(p.x, p.z))])
		get_tree().quit()
		return
	for sp: Array in spots:
		var ss := float(sp[0])
		var lat := float(sp[1])
		for view in ["verge", "bank", "above"]:
			var eye: Vector3
			if view == "verge":
				eye = w.transform_at(ss - 30.0, signf(lat) * (w.route.width_at_s(ss) * 0.5 + 2.0)).origin + Vector3.UP * 1.7
			elif view == "bank":
				eye = w.transform_at(ss - 30.0, lat * 0.55).origin + Vector3.UP * 4.0
			else:
				eye = w.transform_at(ss - 70.0, -lat * 0.5).origin + Vector3.UP * 40.0
			cam.global_position = eye
			w.follow(cam.global_position)
			await _settle(w)
			var at := w.transform_at(ss + 40.0, lat).origin
			cam.global_transform = Transform3D(Basis.looking_at(at - cam.global_position, Vector3.UP), cam.global_position)
			await _frames(6)
			var name := "river_%05dm_%s.png" % [int(ss), view]
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
			print("river_shots: saved ", name)
	get_tree().quit()
