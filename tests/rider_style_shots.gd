extends Node
## Screenshots of the rider styles (see RiderStyle): each style mid-corner from the side and the
## front, the scratcher's knee down with sparks, and the Rossi leg out braking into a corner:
##   xvfb-run -a godot --path . res://tests/rider_style_shots.tscn -- --out=/tmp/shots [--bike=sport] [--helmet=helmet_kestrel]
var out_dir := "/tmp/shots"
var bike_style := "sport"
var helmet := "helmet_kestrel"
var cam: Camera3D
var pivot: Node3D
var model: BikeModel


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--bike="):
			bike_style = a.trim_prefix("--bike=")
		elif a.begins_with("--helmet="):
			helmet = a.trim_prefix("--helmet=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	# The road: tarmac with a white line down the middle.
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	road.mesh = plane
	var tarmac := StandardMaterial3D.new()
	tarmac.albedo_color = Color(0.2, 0.2, 0.21)
	tarmac.roughness = 0.95
	road.material_override = tarmac
	add_child(road)
	var line := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(0.12, 80.0)
	line.mesh = strip
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.9, 0.88)
	line.material_override = paint
	line.position = Vector3(-1.2, 0.002, 0.0)
	add_child(line)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()
	Settings.look_into_corner = true
	var tag := "%s_" % bike_style if bike_style != "sport" else ""
	for s in RiderStyle.STYLES:
		_make(s)
		await _pose(0.65, 0.0, 20.0, 0.0, 120)
		_aim(Vector3(3.2, 0.9, -0.6), Vector3(0.0, 0.55, 0.0))
		await _shot("%s%s_corner_side" % [tag, s])
		_aim(Vector3(0.6, 1.0, -4.2), Vector3(0.0, 0.6, 0.0))
		await _shot("%s%s_corner_front" % [tag, s])
	# The scratcher right over, the knee slider on the road throwing sparks.
	_make("scratcher")
	await _pose(0.85, 0.0, 22.0, 0.0, 150)
	_aim(Vector3(2.6, 0.55, -2.2), Vector3(0.3, 0.3, 0.1))
	await _shot("%sscratcher_knee_sparks" % tag)
	_aim(Vector3(1.0, 0.5, -3.2), Vector3(0.2, 0.35, 0.0))
	await _shot("%sscratcher_knee_sparks_front" % tag)
	# The Rossi leg out, braking hard into a left-hander.
	_make("rossi")
	await _pose(-0.06, 0.0, 22.0, 1.0, 90)
	_aim(Vector3(-3.4, 1.0, -0.4), Vector3(0.0, 0.5, 0.0))
	await _shot("%srossi_leg_out_side" % tag)
	_aim(Vector3(-0.8, 1.0, -4.2), Vector3(0.0, 0.5, 0.0))
	await _shot("%srossi_leg_out_front" % tag)
	get_tree().quit()


## A new bike and rider in riding style `style`, upright on the ground.
func _make(style: String) -> void:
	if pivot:
		pivot.free()
	pivot = Node3D.new()
	add_child(pivot)
	model = BikeModel.new()
	model.rider_gear = RiderGear.clean_worn({"helmet": helmet, "jacket": "jacket_kestrel", "trousers": "trousers_kestrel",
		"boots": "boots_kestrel", "gloves": "gloves_kestrel", "style": style})
	model.rider_color = Color(0.1, 0.35, 0.8)
	pivot.add_child(model)
	model.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(bike_style))))
	model.position = Vector3(0.0, -model.foot_ground_y(), 0.0)


## Holds the bike leaned over `lean` (rad, + right) about its tyres, riding at `speed` and
## braking `brake`, for `frames` frames, the rider posing all the while.
func _pose(lean: float, steer: float, speed: float, brake: float, frames: int) -> void:
	pivot.basis = Basis(Vector3.FORWARD, lean)
	for i in frames:
		model.update_pose_from(steer, i * 0.3, i * 0.3, 0.0, 0.0, 0.0, clampf(lean / 0.6, -1.0, 1.0) * 0.6)
		model.update_rider(lean, steer, speed, brake, 1.0 / 60.0)
		await get_tree().process_frame


func _aim(offset: Vector3, at: Vector3) -> void:
	cam.global_position = offset
	cam.look_at(at, Vector3.UP)


func _shot(shot_name: String) -> void:
	# The pose keeps going while the picture's taken, so the sparks keep coming.
	for i in 3:
		model.update_rider(model.rider_pose()["lean"], 0.0, 22.0, 0.0 if model.rider_style() != "rossi" else 1.0, 1.0 / 60.0)
		await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " pose ", model.rider_pose(), " knee down ", model.knee_down, " sparks ", model.sparks_flying())
