extends Node3D
## Close-ups of one slot's part on a stock bike of each style in the Rig built look, from the right,
## the left and side on, for the Blender parts' contact sheets (with --code, BlenderParts.on is off:
## the code-built shapes):
##   xvfb-run -a godot --path . res://tests/part_shots.tscn -- --slot=fuel --out=/tmp/shots [--styles=mx,race]
##     [--part=flat_slide_carbs] [--code] [--near=0.8]

var out_dir := "/tmp/shots"
var cam := Camera3D.new()


func _ready() -> void:
	var styles: Array = PartsDB.STYLES.duplicate()
	var slot := "fuel"
	var part := ""
	var code := false
	var near := 1.1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--styles="):
			styles = Array(a.trim_prefix("--styles=").split(","))
		elif a.begins_with("--slot="):
			slot = a.trim_prefix("--slot=")
		elif a.begins_with("--part="):
			part = a.trim_prefix("--part=")
		elif a.begins_with("--near="):
			near = float(a.trim_prefix("--near="))
		elif a == "--code":
			code = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	# (A sky, so chrome and polished alloy have something to reflect.)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.9, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.4, 0.0)
	fill.light_energy = 0.6
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.28)
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	get_viewport().size = Vector2i(900, 700)
	BlenderParts.on = not code
	for style in styles:
		for blender in [true]:
			var parts := Contracts.style_build(str(style))
			if part != "":
				parts[slot] = part
			# (A full fairing covers the engine: off, to see it.)
			parts.erase("fairing")
			var build := BikeBuild.new(PartsDB.sanitize_build(parts))
			var m := BikeModel.new()
			add_child(m)
			m.build_from(build, Color(0.12, 0.2, 0.42), {}, null, false)
			m.position.y = build.rear_radius
			var box := m.slot_bounds(slot)
			var c: Vector3 = m.to_global(box.get_center()) if box.size != Vector3.ZERO else m.to_global(m._engine_c)
			var name := "%s_%s" % [style, str(parts.get(slot, ""))]
			await _shot_from(c + Vector3(near, 0.12 * near, -0.3 * near), c, name + "_right")
			await _shot_from(c + Vector3(-near, 0.12 * near, -0.3 * near), c, name + "_left")
			var mid: Vector3 = m.to_global(Vector3(0.0, c.y - m.global_position.y, 0.0))
			await _shot_from(mid + Vector3(3.2, 0.5, 0.0), mid + Vector3(0.0, 0.1, 0.0), name + "_side")
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
