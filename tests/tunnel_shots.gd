extends Node
## Pictures of a planned road's tunnel (RealPack.tunnels): its portal from the road, from off to one side and up, and
## inside it:
##   xvfb-run -a godot --path . res://tests/tunnel_shots.tscn -- --out=/tmp/shots
## The road under the hill on Shodoshima's east coast (RoutePlannerTests.test_tunnels).

var out_dir := "/tmp/shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
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
	var r := RealRegion.get_region("shodoshima")
	var res := RoutePlanner.plan(r, {"pins": [r.geo_to_xz(34.48875, 134.34511), r.geo_to_xz(34.47647, 134.33166)], "mode": "main", "seed": 2})
	var pack: RealPack = res["pack"]
	RealPack.register(pack)
	var w := AdventureWorld.new()
	w.setup(pack, 11, 0.0)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	var s0 := float(pack.tunnels[0]) * pack.step
	var s1 := float(pack.tunnels[1]) * pack.step
	# [where from (s, lat, up), what at (s, lat, up)]
	var views := {
		"road": [[s0 - 45.0, -1.0, 2.0], [s0, 0.0, 3.0]],
		"side": [[s0 - 70.0, -40.0, 25.0], [s0, 0.0, 4.0]],
		"inside": [[s0 + 120.0, -1.2, 1.6], [s0 + 170.0, 0.0, 2.0]],
		"out": [[s1 - 60.0, -1.2, 1.6], [s1 + 20.0, 0.0, 2.0]],
	}
	for view: String in views:
		var v: Array = views[view]
		for pass_k in 2:
			var from: Transform3D = w.transform_at(float(v[0][0]), float(v[0][1]))
			cam.global_transform = Transform3D(Basis(), from.origin + Vector3.UP * float(v[0][2]))
			if pass_k == 0:
				var end := Time.get_ticks_msec() + 90000
				var frames := 0
				while Time.get_ticks_msec() < end:
					await get_tree().process_frame
					frames += 1
					var wanted: Array = w.wanted_chunks()
					if frames > 30 and not wanted.is_empty() and wanted.all(func(c): return w.chunks.has(c)):
						break
				for i in 12:
					await get_tree().process_frame
		var at: Transform3D = w.transform_at(float(v[1][0]), float(v[1][1]))
		cam.look_at(at.origin + Vector3.UP * float(v[1][2]), Vector3.UP)
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var name := "tunnel_%s" % view
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name, " shelter ", snappedf(Daylight.shelter, 0.01))
	get_tree().quit()
