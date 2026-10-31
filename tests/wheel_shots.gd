extends Node3D
## Close-ups of wheels and tyres made in Blender (assets/bike_parts/wheel and tyre) on whole bikes,
## each beside the same bike with BikeModel's own code-built wheels and tyres, for the bike look
## overhaul's contact sheets:
##   xvfb-run -a godot --path . res://tests/wheel_shots.tscn -- --out=/tmp/shots
## (Until the loader hooks into the New look, a BikeModel here draws its wheels the Blender way
## itself: each wheel's glb, and its tyre bent round from its tread's section, in BikeModel's own
## colours, as the bike shader isn't in yet.)

## [the style the bike is built in, front wheel, rear wheel]
const BIKES := [
	["classic", "wire_19_chrome", "wire_18_drum"],
	["cafe", "cafe_alloy_wire_18", "cafe_drum_19"],
	["sport", "forged_17_mag", "sport_split_spoke"],
	["race", "race_mag_gold", "race_carbon_split"],
	["mx", "mx_21_blue", "mx_19_red"],
	["adventure", "adv_21_tubeless", "adv_17_cast"],
	["bobber", "bobber_wire_16_black", "bobber_moon_16"],
	["cruiser", "cruiser_cast_21_front", "cruiser_cast_slotted"],
	["naked", "naked_cast_stripe", "naked_split_gold"],
	["supermoto", "sm_17_red", "sm_17_black_gold"],
]


## A BikeModel drawing its wheels and tyres from the Blender pieces.
class BlenderWheelModel extends BikeModel:
	func _draw_rim(wheel: Node3D, rim_r: float, rim_w: float) -> void:
		var node := BlenderParts.instance(BlenderParts.path_for("wheel", _part_id()), Transform3D())
		if node == null:
			super(wheel, rim_r, rim_w)
			return
		wheel.add_child(node)
		var rim := _mat(_col(), 0.9, 0.25)
		for mi in node.find_children("lod*", "MeshInstance3D", false, false):
			_paint_like(mi as MeshInstance3D, rim)
		if _current_slot == "rear_wheel":
			wheel.add_child(BlenderParts.instance(BlenderParts.ROOT + "wheel/fitting/cush_drive.glb", Transform3D()))

	func _draw_tyre(wheel: Node3D, rim_r: float, radius: float, width: float, rim_w: float) -> void:
		var lods := BlenderParts.tyre_hoop(BlenderParts.tyre_path(BikeModel.tread_pattern(_part())), rim_r, radius, width, rim_w)
		var node := BlenderParts.lod_node(lods, "BlenderTyre")
		wheel.add_child(node)
		var rubber := _mat(_col(), 0.0, 0.88)
		for mi in node.get_children():
			_paint_like(mi as MeshInstance3D, rubber)
		# The sidewall lettering is still BikeModel's.
		var holder := MeshInstance3D.new()
		holder.rotation.z = PI * 0.5
		wheel.add_child(holder)
		_tyre_lettering(holder, rim_r, radius, width)

	## Today's colours on the Blender surfaces: the part's own on its main surface, chrome,
	## polished and black finishes as BikeModel draws them.
	func _paint_like(mi: MeshInstance3D, mat: Material) -> void:
		for s in mi.mesh.get_surface_count():
			match BlenderParts.tag_of(mi.mesh.surface_get_material(s)):
				"chrome":
					mi.set_surface_override_material(s, _look_finish("chrome", mat))
				"black_metal":
					mi.set_surface_override_material(s, _look_finish("black", mat))
				"raw_steel", "brushed_steel":
					mi.set_surface_override_material(s, _mat(Color(0.6, 0.61, 0.64), 1.0, 0.3))
				"anodised":
					mi.set_surface_override_material(s, _look_finish("gold", mat))
				"paint_2":
					var sc = _look().get("stripe", [0.7, 0.1, 0.1])
					mi.set_surface_override_material(s, _mat(Color(float(sc[0]), float(sc[1]), float(sc[2])), 0.2, 0.4))
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
			var parts := Contracts.style_build(str(b[0]))
			parts["front_wheel"] = b[1]
			parts["rear_wheel"] = b[2]
			var build := BikeBuild.new(PartsDB.sanitize_build(parts))
			var m: BikeModel = BlenderWheelModel.new() if blender else BikeModel.new()
			add_child(m)
			m.build_from(build, Color(0.12, 0.2, 0.42), {}, null, false)
			m.position.y = build.rear_radius
			# The whole bike from the right, a little ahead and above, then the rear wheel close up.
			var c: Vector3 = m.to_global(Vector3(0.0, 0.0, 0.0))
			var name := "%s_%s_%s_%s" % [b[0], b[1], b[2], "blender" if blender else "code"]
			await _shot_from(c + Vector3(3.4, 0.9, -1.3), c + Vector3(0.0, 0.05, 0.0), name)
			var rear: Vector3 = m._rear_wheel.global_position
			await _shot_from(rear + Vector3(1.0, 0.25, 0.35), rear, name + "_rear")
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
