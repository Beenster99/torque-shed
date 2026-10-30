extends Node3D
## Close-ups of exhausts made in Blender (assets/bike_parts/exhaust) on whole bikes, each beside the
## same bike with BikeModel's own code-built exhaust, for the bike look overhaul's contact sheets:
##   xvfb-run -a godot --path . res://tests/exhaust_shots.tscn -- --out=/tmp/shots
## (Until the loader hooks into the New look, a BikeModel here draws its exhaust the Blender way
## itself: its cans are the Blender cans, and its headers Blender pipe sections along the routes
## BikeModel works out, in BikeModel's own colours, as the bike shader isn't in yet.)

## [frame, engine, exhaust, the style the rest of the bike is built in]
const BIKES := [
	["steel_cradle", "twin_750", "stock_muffler", "classic"],
	["featherbed_cradle", "twin_600", "cafe_megaphone_black", "cafe"],
	["featherbed_cradle", "twin_600", "cafe_reverse_cones", "cafe"],
	["scrambler_desert_cradle", "twin_800", "scrambler_high_twin", "scrambler"],
	["mx_twin_loop", "single_450", "mx_tri_oval", "mx"],
	["mx_red_loop", "2stroke_125", "mx_two_stroke_chamber", "mx"],
	["sport_perimeter_red", "inline_1000", "titanium_race", "sport"],
	["sport_perimeter_red", "inline_1000", "underseat_twin", "sport"],
	["softail_hardtail", "vtwin45_1450", "cruiser_fishtail_duals", "cruiser"],
	["chopper_raked", "vtwin60_1500", "chopper_trumpet_shotguns", "chopper"],
	["bobber_rigid", "vtwin_1200", "bobber_turnouts", "bobber"],
	["steel_trestle", "vtwin_1000", "naked_stubby", "naked"],
	["adv_rally_trellis", "boxer_1200", "adv_high_titanium", "adventure"],
	["featherbed_cradle", "boxer_750", "tourer_twin", "classic"],
]


## A BikeModel drawing its exhaust from the Blender pieces.
class BlenderExhaustModel extends BikeModel:
	func _can(a: Vector3, b: Vector3, shape: String, mat: Material, r: float) -> Vector3:
		var path := BlenderParts.can_path(shape)
		var xform := BlenderParts.can_xform(a, b, r, shape)
		var node := BlenderParts.instance(path, xform)
		for mi in node.find_children("lod*", "MeshInstance3D", false, false):
			_paint_like(mi as MeshInstance3D, mat)
		add_child(node)
		return BlenderParts.can_outlet(path, xform)

	func _bend(path: Array, radius, mat: Material, parent: Node3D = self, sides := 12) -> MeshInstance3D:
		if _current_slot != "exhaust" or parent != self:
			return super(path, radius, mat, parent, sides)
		var finish := "wrap" if _look_trim("header").contains("wrap") else "plain"
		var lods := BlenderParts.sweep_section(BlenderParts.ROOT + "exhaust/pipe/%s.glb" % finish, path, radius)
		var node := BlenderParts.lod_node(lods)
		add_child(node)
		for mi in node.get_children():
			_paint_like(mi as MeshInstance3D, mat)
		return node.get_child(0) as MeshInstance3D

	## Today's colours on the Blender surfaces: the code's own material on the body, and the dark
	## and bare-steel ones on the tail pipes, clamps and end caps.
	func _paint_like(mi: MeshInstance3D, mat: Material) -> void:
		for s in mi.mesh.get_surface_count():
			match BlenderParts.tag_of(mi.mesh.surface_get_material(s)):
				"black_metal":
					mi.set_surface_override_material(s, _mat(Color(0.05, 0.05, 0.05), 0.4, 0.5))
				"brushed_steel", "raw_steel":
					mi.set_surface_override_material(s, _mat(Color(0.8, 0.81, 0.83), 1.0, 0.2))
				"fabric":
					mi.set_surface_override_material(s, mat)
				_:
					mi.set_surface_override_material(s, mat)


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
			parts["exhaust"] = b[2]
			var build := BikeBuild.new(PartsDB.sanitize_build(parts))
			var m: BikeModel = BlenderExhaustModel.new() if blender else BikeModel.new()
			add_child(m)
			m.build_from(build, Color(0.12, 0.2, 0.42), {}, null, false)
			m.position.y = build.rear_radius
			# From the right and a little ahead, the engine to the tail: the headers and the cans.
			var e: Vector3 = m.to_global(m._engine_c + Vector3(0.0, -0.08, 0.32))
			var name := "%s_%s_%s_%s" % [b[0], b[1], b[2], "blender" if blender else "code"]
			await _shot_from(e + Vector3(2.5, 0.55, -0.7), e, name)
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
