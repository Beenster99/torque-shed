extends Node
## Screenshots of a real road's land, for checking how it looks without riding it (like real_shots.gd, which it shares its
## options with), and how long the land takes to come in:
##   xvfb-run -a godot --path . res://tests/land_shots.tscn -- --out=/tmp/shots [--pack=dales] [--s=300,4000]
var out_dir := "/tmp/shots"
var pack := "shodoshima"
var stops := [3000.0, 10000.0, 16500.0]
var height := 2.4
var side := 0.0
var tag := ""
var noridge := false
var plan := false
var noland := false
var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--pack="):
			pack = a.trim_prefix("--pack=")
		elif a.begins_with("--height="):
			height = float(a.trim_prefix("--height="))
		elif a.begins_with("--side="):
			side = float(a.trim_prefix("--side="))
		elif a.begins_with("--yaw="):
			yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--pitch="):
			pitch = float(a.trim_prefix("--pitch="))
		elif a == "--plan":
			plan = true
		elif a == "--noridge":
			noridge = true
		elif a == "--noland":
			noland = true
		elif a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
		elif a.begins_with("--s="):
			stops = Array(a.trim_prefix("--s=").split(",")).map(func(v): return float(v))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	var cam := Camera3D.new()
	cam.far = 9000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	var w := AdventureWorld.new()
	if plan:
		# A journey planned over the region, as the shed's map does: Shodoshima's two ends.
		var r := RealRegion.get_region(pack)
		var res := RoutePlanner.plan(r, {"pins": [r.geo_to_xz(34.518638, 134.269646), r.geo_to_xz(34.499373, 134.347915)], "mode": "main"})
		var planned: RealPack = res["pack"]
		RealPack.register(planned)
		print("planned ", planned.id, " ", planned.max_km(), " km, theme ", planned.theme, " sea ", planned.sea)
		w.setup(planned, 5)
	else:
		w.setup(AdventurePlans.pack_for(AdventurePlans.tour(pack)), 11, 23.0)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	if noridge and w.ridges != null:
		w.ridges.queue_free()
		w.ridges = null
	if noland and w.land != null:
		w.land.queue_free()
		w.land = null
	for s: float in stops:
		var xf := w.transform_at(s, side)
		var basis := xf.basis * Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
		cam.global_transform = Transform3D(basis, xf.origin + Vector3.UP * height)
		var t0 := Time.get_ticks_msec()
		var end := t0 + 90000
		while Time.get_ticks_msec() < end:
			await get_tree().process_frame
			w.follow(cam.global_position)   # (the adventure's trip does this every frame)
			var ready: bool = w.wanted_chunks().all(func(c): return w.chunks.has(c)) and (w.land == null or not w.land.busy()) and (w.ridges == null or not w.ridges.busy())
			if ready:
				break
		for i in 12:
			await get_tree().process_frame
		if w.land != null:
			var best := INF
			var bm: MeshInstance3D = null
			for key in w.land._blocks:
				var mi: MeshInstance3D = w.land._blocks[key]["mi"]
				if mi != null:
					var d := (mi.global_position + Vector3(256, 0, 256) - cam.global_position).length()
					if d < best:
						best = d
						bm = mi
			var camr := Vector2(cam.global_position.x + w.origin.x, cam.global_position.z + w.origin.z)
			print("land _at ", w.land._at, " cam route ", camr, " queue ", w.land._queue.size(), " tasks ", w.land._tasks.size())
			var key0 := Vector2i(floori(camr.x / 512.0), floori(camr.y / 512.0))
			print("cam block ", key0, " has ", w.land._blocks.has(key0), " ", w.land._blocks.get(key0, {}).get("lod", -9), " null mi ", w.land._blocks.get(key0, {}).get("mi") == null)
			if bm != null:
				print("nearest land block ", bm.name, " ", bm.global_position, " visible ", bm.is_visible_in_tree(), " aabb ", bm.get_aabb(), " cam ", cam.global_position)
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s_%05d%s.png" % [pack, int(s), tag]))
		print("saved %s at %.0f m: ready in %d ms, land %s" % [pack, s, Time.get_ticks_msec() - t0, str(w.land.level_counts()) if w.land else "none"])
	get_tree().quit()
