extends Node
## The bike finishes close up (see BikeShader and BikeLookNew.finish_of): a ball of each, the
## Classic look's material on the left and the new look's bike shader on the right, and an
## exhaust header from cold to hot, under a sky so the metals have something to reflect:
##   xvfb-run -a godot --path . res://tests/finish_swatches.tscn -- --out=/tmp/swatches.png [--zoom=N]
## --zoom=N looks closely at the Nth pair instead (0 = paint, 1 = metallic...), new look on the right.


func _ready() -> void:
	var out := "/tmp/swatches.png"
	var zoom := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--zoom="):
			zoom = int(a.trim_prefix("--zoom="))
	get_window().size = Vector2i(1200, 700)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(-0.03, 0.03, 1.75)
	cam.look_at(Vector3(-0.03, 0.0, 0.0), Vector3.UP)
	var swatches := [
		["paint", _m(Color(0.7, 0.1, 0.08), 0.0, 0.3, 0.7)],
		["metallic", _m(Color(0.1, 0.2, 0.6), 0.5, 0.35, 0.8)],
		["chrome", _m(Color(0.86, 0.87, 0.89), 1.0, 0.1)],
		["alloy", _m(Color(0.8, 0.8, 0.8), 1.0, 0.25)],
		["brushed", _tex(_m(Color(0.7, 0.71, 0.73), 1.0, 0.38), "brushed")],
		["rubber", _m(Color(0.05, 0.05, 0.05), 0.0, 0.9)],
		["leather", _tex(_m(Color(0.35, 0.2, 0.12), 0.0, 0.6), "grain")],
		["carbon", _tex(_m(Color(0.07, 0.07, 0.08), 0.25, 0.3, 1.0), "carbon")],
	]
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.12
	ball.radial_segments = 48
	ball.rings = 24
	var kits := BikeLookNew._kit_textures()
	for i in swatches.size():
		var x := -0.66 + (i % 4) * 0.36
		var y := 0.2 if i < 4 else 0.02
		_pair(ball, swatches[i][1], Vector3(x, y, 0.0), kits, [], 0.0)
		if i == zoom:
			cam.global_position = Vector3(x + 0.07, y + 0.02, 0.3)
			cam.look_at(Vector3(x + 0.07, y, 0.0), Vector3.UP)
	# An exhaust header, hot where it leaves the head on the left, cooling along to the right:
	# chrome above, polished alloy below.
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.02
	pipe.bottom_radius = 0.02
	pipe.height = 1.3
	pipe.radial_segments = 32
	pipe.rings = 40
	for k in 2:
		var at := Vector3(0.0, -0.17 - k * 0.07, 0.0)
		var mat: Material = swatches[2][1] if k == 0 else swatches[3][1]
		var xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), at)
		var look := BikeLookNew._look_of(mat, {}, kits)
		look["ports"] = [Vector3(0.0, 0.65, 0.0)]   # its end, before it is laid on its side
		look["heat"] = 1.0
		var mi := MeshInstance3D.new()
		var arr := BikeLookNew._shaded_arrays([[pipe, 0, Transform3D.IDENTITY, look]])
		mi.mesh = ArrayMesh.new()
		mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _placed(arr, xf), [], {}, BikeLookNew.CUSTOM_FORMAT)
		mi.material_override = BikeShader.material()
		add_child(mi)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", out)
	get_tree().quit()


## A ball of `mat` at `at` as Classic draws it, and beside it as the new look does.
func _pair(mesh: Mesh, mat: Material, at: Vector3, kits: Dictionary, ports: Array, heat: float) -> void:
	var classic := MeshInstance3D.new()
	classic.mesh = mesh
	classic.material_override = mat
	classic.position = at
	add_child(classic)
	var look := BikeLookNew._look_of(mat, {}, kits)
	look["ports"] = ports
	look["heat"] = heat
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BikeLookNew._shaded_arrays([[mesh, 0, Transform3D.IDENTITY, look]]), [], {}, BikeLookNew.CUSTOM_FORMAT)
	mi.material_override = BikeShader.material()
	mi.position = at + Vector3(0.14, 0.0, 0.0)
	add_child(mi)


## `arr` (from _shaded_arrays) moved by `xf`, keeping the heat worked out where it was.
func _placed(arr: Array, xf: Transform3D) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = xf * v[i]
		n[i] = xf.basis * n[i]
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	return arr


func _m(color: Color, metallic: float, roughness: float, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.1
	return m


func _tex(m: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	TextureKit.apply(m, kind)
	return m
