extends Node
## What a group ride's bikes cost to draw, Classic against New (see BikeLook): four riders'
## bikes side by side a few metres ahead of the camera and eight more parked at a cafe stop
## further off, all ridden-past (baked), drawn for a few hundred frames each way:
##   xvfb-run -a godot --path . res://tests/bike_look_bench.tscn [-- --frames=300]
## Prints the mean and worst frame time for each look. Under xvfb it's drawn in software, so the
## numbers only compare the two looks, not what a real graphics card does.
var frames := 300


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
	BikeLookNew.lods_now = true
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0.0, 1.6, 4.0)
	cam.look_at(Vector3(0.0, 0.6, -6.0), Vector3.UP)
	var results := {}
	for look in BikeLook.LOOKS:
		var holder := Node3D.new()
		add_child(holder)
		var styles := ["sport", "adventure", "cafe", "naked", "cruiser", "tourer", "scrambler", "mx", "classic", "bobber", "race", "roader"]
		for i in styles.size():
			var m := BikeModel.new()
			m.look = look
			m.baked = true
			m.own_rider = i == 0
			holder.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(styles[i]))), Color.from_hsv(i / 12.0, 0.7, 0.8))
			# Four riders two abreast ahead, then eight parked in a row up the road.
			m.position = Vector3(-0.8 + (i % 2) * 1.6, 0.0, -2.0 - (i / 2) * 3.0) if i < 4 else Vector3(-6.0 + (i - 4) * 1.6, 0.0, -30.0)
			m.rotation.y = 0.0 if i < 4 else PI * 0.5
		for i in 30:
			await get_tree().process_frame
		var times := []
		var last := Time.get_ticks_usec()
		for i in frames:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		times.sort()
		var total := 0.0
		for v in times:
			total += v
		results[look] = {"mean_ms": snappedf(total / times.size(), 0.01), "p95_ms": snappedf(times[int(times.size() * 0.95)], 0.01),
			"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
		print("BENCH ", look, " ", results[look])
		holder.free()
		await get_tree().process_frame
	get_tree().quit()
