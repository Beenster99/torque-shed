extends Node
## Screenshots of a bike's brake light and indicators at night, from behind and in front:
##   xvfb-run -a godot --path . res://tests/lamps_shots.tscn -- --out=/tmp/shots [--build=indicators:stalk_amber]
var out_dir := "/tmp/shots"
var build := {}
var cam: Camera3D
var bike: Bike


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--build="):
			for pair in a.trim_prefix("--build=").split(","):
				var kv := pair.split(":")
				build[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.012, 0.025)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.12, 0.14, 0.2)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.9
	env.environment.glow_bloom = 0.05
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40.0, 150.0, 0.0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.6, 0.7, 1.0)
	add_child(moon)
	add_child(TestGround.new(200.0, "tarmac"))
	bike = Bike.new()
	bike.setup(BikeBuild.new(build))
	add_child(bike)
	bike.place(Vector3.ZERO, 0.0)
	bike.engine_on = true
	bike.beam = 1
	cam = Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.make_current()
	await _settle(120)
	var tag := "_".join(build.values()) if not build.is_empty() else "stock"
	# From behind: tail light, braking, then each side's indicators mid-flash.
	_aim(Vector3(1.2, 1.25, 3.4))
	await _shot("%s_rear_tail" % tag, false, 0)
	await _shot("%s_rear_braking" % tag, true, 0)
	await _shot("%s_rear_left" % tag, false, -1)
	await _shot("%s_rear_right" % tag, false, 1)
	# From in front.
	_aim(Vector3(-1.2, 1.3, -3.4))
	await _shot("%s_front_left" % tag, false, -1)
	await _shot("%s_front_right" % tag, false, 1)
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		bike.throttle = 0.0
		bike.lean_input = 0.0
		await get_tree().physics_frame


func _aim(offset: Vector3) -> void:
	var at := bike.global_position + Vector3(0.0, 0.65, 0.0)
	cam.global_position = bike.global_position + offset
	cam.look_at(at, Vector3.UP)


## One picture with the brake held or not and indicating `side` (-1, 0, 1), caught while the
## indicators are lit.
func _shot(name: String, braking: bool, side: int) -> void:
	bike.front_brake = 1.0 if braking else 0.0
	bike.rear_brake = 0.0
	bike.lamps.set_side(side)
	await _settle(4)
	for i in 120:
		if side == 0 or bike.lamps.lit():
			break
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " stop ", bike.model.stop_lit(), " signals ", bike.model.signals())
