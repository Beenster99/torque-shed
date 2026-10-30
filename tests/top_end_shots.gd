extends Node3D
## Close-ups of twins' top ends made in Blender (assets/bike_parts/head/twin) on whole bikes, each
## beside the same bike with BikeModel's own code-built barrels and head, for the bike look
## overhaul's contact sheets:
##   xvfb-run -a godot --path . res://tests/top_end_shots.tscn -- --out=/tmp/shots
## (Until the loader hooks into the New look, this puts the Blender top end on by hand: it hides
## the code-built barrels and head and adds BlenderParts' node where BikeModel lays them out.)

## [frame, engine, head, the style the rest of the bike is built in]
const BIKES := [
	["steel_cradle", "twin_750", "two_valve_stock", "classic"],
	["featherbed_cradle", "twin_600", "four_valve", "cafe"],
	["scrambler_desert_cradle", "twin_800", "hot_cam", "scrambler"],
	["nickel_cradle", "twin_500", "one_valve_flathead", "classic"],
	["bobber_rigid", "twin_1200", "big_valve_ported", "bobber"],
	["cafe_lowboy_cradle", "twin_1000", "race_high_comp", "cafe"],
]

var out_dir := "/tmp/shots"
var cam := Camera3D.new()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.53, 0.57)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.6
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
	fill.light_energy = 0.5
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
	for b in BIKES:
		for blender in [false, true]:
			var parts := Contracts.style_build(str(b[3]))
			parts["frame"] = b[0]
			parts["engine"] = b[1]
			parts["head"] = b[2]
			var build := BikeBuild.new(PartsDB.sanitize_build(parts))
			var m := BikeModel.new()
			add_child(m)
			m.build_from(build, Color(0.12, 0.2, 0.42), {}, null, false)
			m.position.y = build.rear_radius
			if blender:
				_swap_top_end(m, str(b[2]))
			var e: Vector3 = m.to_global(m._engine_c)
			var name := "%s_%s_%s_%s" % [b[0], b[1], b[2], "blender" if blender else "code"]
			await _shot_from(e + Vector3(1.25, 0.55, -0.95), e + Vector3(0.0, 0.14, 0.0), name)
			m.queue_free()
			await get_tree().process_frame
	get_tree().quit()


## Hides the code-built barrels (the engine's pieces above its cases) and head, and puts the
## Blender top end on in their place.
func _swap_top_end(m: BikeModel, head: String) -> void:
	var case_top := m._engine_c.y + 0.13 * m._eng_s
	for slot in ["engine", "head"]:
		for mi in m._slot_meshes.get(slot, []):
			var g := mi as GeometryInstance3D
			if g == null:
				continue
			var mid := m.to_local(g.global_transform * g.get_aabb().get_center())
			if slot == "head" or mid.y > case_top:
				g.visible = false
	var node := BlenderParts.instance(BlenderParts.path_for("head", head, "twin"), BlenderParts.top_end_xform(m._cyls, m._eng_s))
	m.add_child(node)


func _shot_from(from: Vector3, at: Vector3, name: String) -> void:
	cam.look_at_from_position(from, at)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)
