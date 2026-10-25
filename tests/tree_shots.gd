extends Node
## Pictures of the trees beside a planned road (planted from the canopy map, RealTerrain.trees_at): from the road, and
## from up above, at the first few places along a region's tour with trees thick within TREES_NEAR of it:
##   xvfb-run -a godot --path . res://tests/tree_shots.tscn -- --out=/tmp/shots [--n=3] [--region=dales] [--no-canopy]
## (--no-canopy leaves the canopy map out: the trees scattered by the land cover alone, as before it.)

var out_dir := "/tmp/shots"
var count := 3
var region := "dales"
const TREES_NEAR := 120.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--region="):
			region = a.trim_prefix("--region=")
		elif a.begins_with("--n="):
			count = int(a.trim_prefix("--n="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	var cam := Camera3D.new()
	cam.far = 4000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	var pack := AdventurePlans.pack_for(AdventurePlans.tour(region))
	var look := pack.terrain   # (where the trees are, to pick the places: kept when they're left out of the ride)
	if OS.get_cmdline_user_args().has("--no-canopy"):
		look = RealTerrain.new()
		look.lat0 = pack.terrain.lat0
		look.lon0 = pack.terrain.lon0
		look._m = pack.terrain._m
		look._tree_cells = pack.terrain._tree_cells
		pack.terrain._tree_cells = []
	var w := AdventureWorld.new()
	w.setup(pack, 11, 0.0)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	# Places along the road with trees thick off to one side: [s, lat] of them, a kilometre apart at least.
	var spots: Array = []
	var last := -INF
	var route := w.route
	for i in range(0, route.px.size(), 8):
		if spots.size() >= count:
			break
		if i * AdventureRoute.STEP - last < 1000.0:
			continue
		for lat: float in [-TREES_NEAR, -80.0, -50.0, -30.0, 30.0, 50.0, 80.0, TREES_NEAR]:
			var x := route.px[i] + cos(route.hd[i]) * lat
			var z := route.pz[i] + sin(route.hd[i]) * lat
			var v := look.trees_at(x, z)
			if v > 0 and (v >> 5) & 7 >= 6:
				spots.append([i * AdventureRoute.STEP, lat])
				last = i * AdventureRoute.STEP
				break
	for sp: Array in spots:
		var s := float(sp[0])
		var lat := float(sp[1])
		for view in ["road", "above"]:
			var from: Array = [s - 40.0, signf(lat) * 1.5, 2.0] if view == "road" else [s - 60.0, -lat * 0.6, 45.0]
			for pass_k in 2:
				var xf: Transform3D = w.transform_at(float(from[0]), float(from[1]))
				cam.global_transform = Transform3D(Basis(), xf.origin + Vector3.UP * float(from[2]))
				if pass_k == 0:
					var end := Time.get_ticks_msec() + 90000
					var frames := 0
					while Time.get_ticks_msec() < end:
						w.follow(w.to_local(cam.global_position))   # (as the ride has the land follow the rider)
						await get_tree().process_frame
						frames += 1
						var wanted: Array = w.wanted_chunks()
						if frames > 30 and not wanted.is_empty() and wanted.all(func(c): return w.chunks.has(c)) and not w.land.busy():
							break
					for i in 12:
						await get_tree().process_frame
			var at: Transform3D = w.transform_at(s, lat)
			cam.look_at(at.origin, Vector3.UP)
			for i in 4:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var name := "trees_%dm_%s" % [int(s), view]
			img.save_png(out_dir.path_join(name + ".png"))
			print("saved ", name)
	get_tree().quit()
