extends Node
## Screenshots of a real road, for checking how it looks without riding it:
##   xvfb-run -a godot --path . res://tests/real_shots.tscn -- --out=/tmp/shots [--pack=shodoshima] [--s=300,4000,9000]
## A camera stands on the road at each distance, looking along it, a little above the verge.

var out_dir := "/tmp/shots"
var pack := "shodoshima"
var stops := [300.0, 3000.0, 6500.0, 10000.0, 14000.0, 18000.0, 22000.0]
var height := 2.4
var side := 0.0


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
	cam.far = 4000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	var w := AdventureWorld.new()
	w.setup(AdventurePlans.pack_for(AdventurePlans.tour(pack)), 11, 23.0)
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	for s: float in stops:
		var xf := w.transform_at(s, side)
		cam.global_transform = Transform3D(xf.basis, xf.origin + Vector3.UP * height)
		var end := Time.get_ticks_msec() + 60000
		while Time.get_ticks_msec() < end:
			await get_tree().process_frame
			if w.wanted_chunks().all(func(c): return w.chunks.has(c)):
				break
		for i in 12:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s_%05d.png" % [pack, int(s)]))
		print("saved ", s)
	get_tree().quit()
