extends Node
## Pictures of a planned road's bridges (RealPack.bridges), from the road and from beside them:
##   xvfb-run -a godot --path . res://tests/bridge_shots.tscn -- --out=/tmp/shots [--n=3]
## The Dales' tour: its longest bridges, each from the road 60 m before it and from the bank 35 m off.

var out_dir := "/tmp/shots"
var count := 3


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
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
	var pack := AdventurePlans.pack_for(AdventurePlans.tour("dales"))
	var w := AdventureWorld.new()
	w.setup(pack, 11, 23.0)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	# The longest bridges first.
	var spans: Array = []
	for k in range(0, pack.bridges.size() - 1, 2):
		spans.append([pack.bridges[k + 1] - pack.bridges[k], pack.bridges[k], pack.bridges[k + 1]])
	spans.sort()
	spans.reverse()
	spans = spans.filter(func(sp): return float(sp[2]) * pack.step < 23000.0)
	for sp: Array in spans.slice(0, count):
		var s0 := float(sp[1]) * pack.step
		var s1 := float(sp[2]) * pack.step
		var mid := (s0 + s1) * 0.5
		for view in ["road", "bank"]:
			var at: Transform3D = w.transform_at(mid, 0.0)
			var from: Transform3D = w.transform_at(s0 - 60.0, 0.0) if view == "road" else w.transform_at(mid, 35.0)
			var eye := from.origin + Vector3.UP * (2.2 if view == "road" else -1.0)
			cam.global_transform = Transform3D(Basis(), eye)
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
			at = w.transform_at(mid, 0.0)
			from = w.transform_at(s0 - 60.0, 0.0) if view == "road" else w.transform_at(mid, 35.0)
			eye = from.origin + Vector3.UP * (2.2 if view == "road" else -1.0)
			cam.global_transform = Transform3D(Basis(), eye)
			cam.look_at(at.origin + Vector3.UP * (0.5 if view == "road" else -1.0), Vector3.UP)
			for i in 4:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var name := "bridge_%dm_%s" % [int(s1 - s0), view]
			img.save_png(out_dir.path_join(name + ".png"))
			print("saved ", name)
	get_tree().quit()
