extends Node3D
## Side and three-quarter pictures of choppers (and the other long, low frames) with big and small
## engines in them, for checking the engine sits in its frame under the tank:
##   xvfb-run -a godot --path . res://tests/chop_shots.tscn -- --out=/tmp/shots [--tag=before]

## [frame, engine, the style the rest of the bike is built in]
const BIKES := [
	["chopper_raked", "vtwin_1800", "chopper"],
	["chopper_long_rake", "vtwin_1200", "chopper"],
	["chopper_chrome_frame", "inline_1000", "chopper"],
	["chopper_raked", "twin_750", "chopper"],
	["softail_hardtail", "vtwin_1500", "bobber"],
	["softail_hardtail", "vtwin_1800", "chopper"],
	["bobber_rigid", "vtwin_1800", "chopper"],
	["bobber_rigid", "boxer_1200", "bobber"],
	["cruiser_cradle", "vtwin_1800", "cruiser"],
]

var out_dir := "/tmp/shots"
var tag := ""
var cam := Camera3D.new()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=") + "_"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.4, 0.0)
	fill.light_energy = 0.5
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.31, 0.3)
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam.fov = 32.0
	add_child(cam)
	cam.current = true
	get_viewport().size = Vector2i(1280, 800)
	for b in BIKES:
		var parts := Contracts.style_build(str(b[2]))
		parts["frame"] = b[0]
		parts["engine"] = b[1]
		var build := BikeBuild.new(PartsDB.sanitize_build(parts))
		var m := BikeModel.new()
		add_child(m)
		# A light tank, so where it meets the engine shows against the dark heads.
		m.build_from(build, Color(0.7, 0.08, 0.06), {}, {"tank": {"color": Color(0.85, 0.6, 0.12)}}, false)
		m.position.y = build.rear_radius
		var e: Vector3 = m.position + m.slot_bounds("engine").get_center()
		var name := "%s%s_%s" % [tag, b[0], b[1]]
		await _shot_from(e + Vector3(2.6, 0.15, 0.0), e, name + "_side")
		await _shot_from(e + Vector3(1.9, 0.75, -1.5), e, name + "_threequarter")
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _shot_from(from: Vector3, at: Vector3, name: String) -> void:
	cam.look_at_from_position(from, at)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)
