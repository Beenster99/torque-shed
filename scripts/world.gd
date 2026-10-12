class_name World
extends Node3D
## The test map: rolling hills, a 1 km riding loop of tarmac and dirt, and the Build Yard
## with its garage, drag strip, skid pad and jump ramps. Generated from a seed so every
## player in a session gets the same map.

const MAP_HALF := 400.0
const GRID := 200
const ROAD_HALF_WIDTH := 4.0
const ROAD_STEP := 2.0
const YARD_CENTER := Vector2(0.0, 100.0)
const YARD_HALF := Vector2(65.0, 45.0)
const DIRT_START := 0.55   # fraction of the loop where tarmac turns to dirt

var road_points: PackedVector3Array = []     # centre line, every ROAD_STEP metres
var road_tangents: PackedVector3Array = []
var _road_length := 0.0
var _noise := FastNoiseLite.new()
var _road_grid := {}     # Vector2i cell -> Array of road sample indices
var _rng := RandomNumberGenerator.new()
var _sun: DirectionalLight3D
var _env: WorldEnvironment


func generate(seed_value := 1) -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.45
	_build_environment()
	_build_road_path()
	_build_terrain()
	_build_road_meshes()
	_build_yard()
	_build_garage()
	_build_trees()


# ---------------------------------------------------------------------------- queries

func road_length() -> float:
	return _road_length


## A transform on the road centre line at fraction t (0..1) of the loop, facing along it.
func road_transform(t: float) -> Transform3D:
	var i := int(wrapf(t, 0.0, 1.0) * road_points.size()) % road_points.size()
	var tan := road_tangents[i]
	return Transform3D(Basis(Vector3.UP, atan2(-tan.x, -tan.z)), road_points[i] + Vector3.UP * 0.1)


## Where player number `index` starts: lined up in front of the garage, facing the yard.
func spawn_point(index: int) -> Transform3D:
	var x := -9.0 + (index % 7) * 3.0
	var z := 84.0 + (index / 7) * 4.0
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.05, z))


func surface_height(x: float, z: float) -> float:
	var from := Vector3(x, 500.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else 0.0


# ---------------------------------------------------------------------------- environment

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.72)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.25)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	env.ssr_enabled = Settings.high_quality
	env.sdfgi_enabled = Settings.high_quality
	env.sdfgi_use_occlusion = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.77, 0.86)
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = Settings.high_quality
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	_env.environment = env
	add_child(_env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	_sun.light_color = Color(1.0, 0.95, 0.86)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 220.0
	_sun.light_angular_distance = 0.6
	_sun.light_volumetric_fog_energy = 1.2
	add_child(_sun)


# ---------------------------------------------------------------------------- terrain height

func _yard_mask(x: float, z: float) -> float:
	var dx := maxf(absf(x - YARD_CENTER.x) - YARD_HALF.x, 0.0)
	var dz := maxf(absf(z - YARD_CENTER.y) - YARD_HALF.y, 0.0)
	return smoothstep(8.0, 70.0, Vector2(dx, dz).length())


func _natural_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var amp := 16.0 + 70.0 * smoothstep(250.0, 390.0, r)
	return _noise.get_noise_2d(x, z) * amp * _yard_mask(x, z) + smoothstep(330.0, 400.0, r) * 25.0


# ---------------------------------------------------------------------------- road

func _loop_point(theta: float) -> Vector3:
	var f := 1.0 + 0.1 * sin(3.0 * theta + 0.5) + 0.05 * sin(5.0 * theta + 2.0)
	return Vector3(185.0 * f * sin(theta), 0.0, 126.0 * f * cos(theta))


func _build_road_path() -> void:
	# Dense samples by angle, then resample evenly by distance.
	var dense: Array[Vector3] = []
	var n := 4000
	for i in n:
		dense.append(_loop_point(TAU * i / n))
	dense.append(dense[0])
	var total := 0.0
	for i in n:
		total += dense[i].distance_to(dense[i + 1])
	var count := int(total / ROAD_STEP)
	var step := total / count
	var pts: Array[Vector3] = []
	var seg := 0
	var seg_start := 0.0
	for k in count:
		var target := k * step
		while seg_start + dense[seg].distance_to(dense[seg + 1]) < target:
			seg_start += dense[seg].distance_to(dense[seg + 1])
			seg += 1
		var seg_len := dense[seg].distance_to(dense[seg + 1])
		pts.append(dense[seg].lerp(dense[seg + 1], (target - seg_start) / seg_len))
	_road_length = total

	# Heights follow the land, smoothed so climbs and dips stay rideable.
	var raw: Array[float] = []
	for p in pts:
		raw.append(_natural_height(p.x, p.z))
	var window := 18
	road_points.resize(count)
	for i in count:
		var sum := 0.0
		for j in range(-window, window + 1):
			sum += raw[(i + j + count) % count]
		var p := pts[i]
		p.y = sum / (2 * window + 1)
		if _yard_mask(p.x, p.z) == 0.0:
			p.y = 0.0
		road_points[i] = p
	road_tangents.resize(count)
	for i in count:
		road_tangents[i] = (road_points[(i + 1) % count] - road_points[(i - 1 + count) % count]).normalized()
	_road_grid.clear()
	for i in count:
		var cell := _cell(road_points[i].x, road_points[i].z)
		if not _road_grid.has(cell):
			_road_grid[cell] = []
		_road_grid[cell].append(i)


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / 20.0), floori(z / 20.0))


## Distance to the road centre line (capped at 40 m) and the road height there.
func _road_info(x: float, z: float) -> Vector2:
	var c := _cell(x, z)
	var best := 40.0
	var height := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _road_grid.has(key):
				continue
			for i in _road_grid[key]:
				var p: Vector3 = road_points[i]
				var d := Vector2(p.x - x, p.z - z).length()
				if d < best:
					best = d
					height = p.y
	return Vector2(best, height)


func _build_road_meshes() -> void:
	var count := road_points.size()
	var dirt_from := int(count * DIRT_START)
	_road_strip(0, dirt_from, "tarmac", _road_material(Color(0.13, 0.13, 0.14), 0.82))
	_road_strip(dirt_from, count, "dirt", _road_material(Color(0.42, 0.31, 0.2), 1.0))
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.92, 0.92, 0.88)
	line_mat.roughness = 0.6
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		_ribbon(0, dirt_from, side * (ROAD_HALF_WIDTH - 0.35), 0.12, 0.065, line_mat)
	# Kickers on the dirt section.
	for t in [0.7, 0.86]:
		var i := int(count * t)
		var xf := Transform3D(Basis(Vector3.UP, atan2(-road_tangents[i].x, -road_tangents[i].z)), road_points[i])
		_kicker(xf, 4.5, 1.1, 5.0, "dirt")


func _road_material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.albedo_texture = _noise_texture(0.08, Color(0.75, 0.75, 0.75), Color(1.1, 1.1, 1.1))
	m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	return m


func _noise_texture(freq: float, dark: Color, light: Color) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 5
	tex.noise = n
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	tex.color_ramp = ramp
	return tex


func _road_strip(from: int, to: int, surface: String, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := road_points.size()
	var dist := 0.0
	var edges := [-ROAD_HALF_WIDTH - 1.8, -ROAD_HALF_WIDTH, ROAD_HALF_WIDTH, ROAD_HALF_WIDTH + 1.8]
	var drops := [-0.35, 0.06, 0.06, -0.35]
	for k in range(from, to + 1):
		var i := k % count
		var p := road_points[i]
		var right := road_tangents[i].cross(Vector3.UP).normalized()
		for e in edges.size():
			st.set_uv(Vector2(edges[e] / 8.0, dist / 8.0))
			st.add_vertex(p + right * edges[e] + Vector3.UP * drops[e])
		dist += ROAD_STEP
	var rows := to - from + 1
	for r in rows - 1:
		for e in edges.size() - 1:
			var a := r * 4 + e
			var b := a + 4
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	var mesh := st.commit()
	_static_mesh(mesh, mat, surface)


func _ribbon(from: int, to: int, offset: float, width: float, lift: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	st.set_normal(Vector3.UP)
	for i in range(from, to):
		var p := road_points[i]
		var right := road_tangents[i].cross(Vector3.UP).normalized()
		st.add_vertex(p + right * (offset - width * 0.5) + Vector3.UP * lift)
		st.add_vertex(p + right * (offset + width * 0.5) + Vector3.UP * lift)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _static_mesh(mesh: Mesh, mat: Material, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	return body


## A wedge ramp at `xf` (facing its -Z), `length` long and `height` tall at the lip.
func _kicker(xf: Transform3D, length: float, height: float, width: float, surface: String) -> void:
	var w := width * 0.5
	var pts := PackedVector3Array([
		Vector3(-w, -0.3, length * 0.5), Vector3(w, -0.3, length * 0.5),
		Vector3(-w, -0.3, -length * 0.5), Vector3(w, -0.3, -length * 0.5),
		Vector3(-w, 0.06, length * 0.5), Vector3(w, 0.06, length * 0.5),
		Vector3(-w, height, -length * 0.5), Vector3(w, height, -length * 0.5),
	])
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	body.transform = xf
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [[4, 5, 7, 6], [0, 2, 3, 1], [0, 4, 6, 2], [1, 3, 7, 5], [2, 6, 7, 3], [0, 1, 5, 4]]
	for q in quads:
		for idx in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(pts[idx])
	st.generate_normals()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.33, 0.22) if surface == "dirt" else Color(0.55, 0.4, 0.25)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if surface != "dirt":
		mat.albedo_texture = _noise_texture(0.2, Color(0.7, 0.7, 0.7), Color(1.0, 1.0, 1.0))
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


# ---------------------------------------------------------------------------- terrain

func _build_terrain() -> void:
	var size := GRID + 1
	var spacing := MAP_HALF * 2.0 / GRID
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var colors := PackedColorArray()
	colors.resize(size * size)
	var grass_a := Color(0.24, 0.36, 0.13)
	var grass_b := Color(0.36, 0.42, 0.18)
	var dirt := Color(0.36, 0.27, 0.17)
	var rock := Color(0.4, 0.39, 0.36)
	for zi in size:
		for xi in size:
			var x := -MAP_HALF + xi * spacing
			var z := -MAP_HALF + zi * spacing
			var h := _natural_height(x, z) - 0.3 * (1.0 - _yard_mask(x, z))
			var info := _road_info(x, z)
			var near := 0.0
			if info.x < 40.0:
				var hr := info.y - 0.25
				near = 1.0 - smoothstep(ROAD_HALF_WIDTH + 1.0, ROAD_HALF_WIDTH + 16.0, info.x)
				h = lerpf(h, hr, near)
			var c := grass_a.lerp(grass_b, clampf(_noise.get_noise_2d(x * 7.0, z * 7.0) * 0.8 + 0.5, 0.0, 1.0))
			c = c.lerp(dirt, clampf(near * 1.3 - 0.2, 0.0, 1.0) * 0.7)
			heights[zi * size + xi] = h
			colors[zi * size + xi] = c
	# Slope colouring after heights are final.
	for zi in range(1, size - 1):
		for xi in range(1, size - 1):
			var dx := heights[zi * size + xi + 1] - heights[zi * size + xi - 1]
			var dz := heights[(zi + 1) * size + xi] - heights[(zi - 1) * size + xi]
			var slope := Vector2(dx, dz).length() / (2.0 * spacing)
			colors[zi * size + xi] = colors[zi * size + xi].lerp(rock, smoothstep(0.45, 0.9, slope))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in size:
		for xi in size:
			st.set_color(colors[zi * size + xi])
			st.set_uv(Vector2(xi, zi) * 0.5)
			st.add_vertex(Vector3(-MAP_HALF + xi * spacing, heights[zi * size + xi], -MAP_HALF + zi * spacing))
	for zi in GRID:
		for xi in GRID:
			var a := zi * size + xi
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + size)
			st.add_index(a + 1)
			st.add_index(a + size + 1)
			st.add_index(a + size)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.albedo_texture = _noise_texture(0.05, Color(0.72, 0.72, 0.72), Color(1.12, 1.12, 1.12))
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	var body := _static_mesh(mesh, mat, "grass")
	body.name = "Terrain"


# ---------------------------------------------------------------------------- build yard

func _build_yard() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.56, 0.56, 0.54)
	concrete.roughness = 0.88
	concrete.albedo_texture = _noise_texture(0.15, Color(0.82, 0.82, 0.82), Color(1.08, 1.08, 1.08))
	concrete.uv1_scale = Vector3(12.0, 12.0, 12.0)
	var body := StaticBody3D.new()
	body.set_meta("surface", "tarmac")
	body.position = Vector3(YARD_CENTER.x, -0.25, YARD_CENTER.y)
	var shape := BoxShape3D.new()
	shape.size = Vector3(YARD_HALF.x * 2.0, 0.5, YARD_HALF.y * 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = concrete
	body.add_child(mi)
	add_child(body)

	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.85, 0.2)
	paint.roughness = 0.6
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.93)
	white.roughness = 0.6
	# Drag strip: two lanes, start and finish lines.
	for lane_z in [96.0, 104.0]:
		_paint_box(Vector3(0.0, 0.0, lane_z), Vector3(110.0, 0.02, 0.2), white)
	_paint_box(Vector3(0.0, 0.0, 100.0), Vector3(110.0, 0.02, 0.15), paint)
	_paint_box(Vector3(-52.0, 0.0, 100.0), Vector3(0.6, 0.02, 8.0), white)
	_paint_box(Vector3(52.0, 0.0, 100.0), Vector3(0.6, 0.02, 8.0), white)
	var finish := _checker(Vector3(52.0, 0.011, 100.0))
	finish.name = "FinishLine"
	# Skid pad ring.
	var ring := TorusMesh.new()
	ring.inner_radius = 14.0
	ring.outer_radius = 14.3
	ring.rings = 96
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = paint
	ring_mi.position = Vector3(36.0, -0.13, 122.0)
	add_child(ring_mi)
	# Jump ramps of three sizes along the west edge, facing north.
	var ramp_xf := Transform3D(Basis(), Vector3.ZERO)
	_kicker(ramp_xf.translated(Vector3(-50.0, 0.0, 128.0)), 4.0, 0.6, 4.0, "tarmac")
	_kicker(ramp_xf.translated(Vector3(-40.0, 0.0, 128.0)), 5.5, 1.3, 4.5, "tarmac")
	_kicker(ramp_xf.translated(Vector3(-28.0, 0.0, 128.0)), 7.0, 2.2, 5.0, "tarmac")
	# Cones around the skid pad.
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.4, 0.05)
	for i in 12:
		var a := TAU * i / 12.0
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.18
		cm.height = 0.5
		cone.mesh = cm
		cone.material_override = cone_mat
		cone.position = Vector3(36.0 + cos(a) * 9.0, 0.25, 122.0 + sin(a) * 9.0)
		add_child(cone)


func _paint_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _checker(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.05)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	for i in 16:
		for j in 2:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.02, 0.5)
			mi.mesh = bm
			mi.material_override = black if (i + j) % 2 == 0 else white
			mi.position = Vector3(-0.25 + j * 0.5, 0.0, -4.0 + i * 0.5 + 0.25)
			root.add_child(mi)
	add_child(root)
	return root


func _build_garage() -> void:
	var shed := Node3D.new()
	shed.name = "Garage"
	shed.position = Vector3(0.0, 0.0, 70.0)
	add_child(shed)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.55, 0.2, 0.15)
	wall.roughness = 0.8
	wall.albedo_texture = _noise_texture(0.3, Color(0.85, 0.85, 0.85), Color(1.05, 1.05, 1.05))
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.32, 0.34, 0.36)
	roof.metallic = 0.6
	roof.roughness = 0.45
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.27, 0.3)
	steel.metallic = 0.8
	steel.roughness = 0.35
	# Walls: back, sides; open front facing the yard (+Z).
	_solid(shed, Vector3(0.0, 2.5, -6.0), Vector3(22.0, 5.0, 0.4), wall)
	_solid(shed, Vector3(-11.0, 2.5, 0.0), Vector3(0.4, 5.0, 12.0), wall)
	_solid(shed, Vector3(11.0, 2.5, 0.0), Vector3(0.4, 5.0, 12.0), wall)
	var roof_mi := _solid(shed, Vector3(0.0, 5.3, 0.4), Vector3(23.0, 0.25, 13.6), roof)
	roof_mi.rotation.x = 0.06
	# Workbenches and a tool wall.
	_solid(shed, Vector3(-6.0, 0.5, -5.0), Vector3(6.0, 1.0, 1.2), wood)
	_solid(shed, Vector3(6.0, 0.5, -5.0), Vector3(6.0, 1.0, 1.2), wood)
	_solid(shed, Vector3(0.0, 2.4, -5.75), Vector3(8.0, 1.6, 0.1), steel)
	for i in 8:
		_solid(shed, Vector3(-3.2 + i * 0.9, 2.5, -5.62), Vector3(0.08, 0.7 + (i % 3) * 0.15, 0.06), wood if i % 2 else roof)
	# Dyno rollers on the floor.
	_solid(shed, Vector3(0.0, 0.08, -1.0), Vector3(1.4, 0.16, 2.6), steel)
	var sign := Label3D.new()
	sign.text = "TORQUE SHED"
	sign.font_size = 160
	sign.outline_size = 24
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.position = Vector3(0.0, 4.6, 6.4)
	sign.pixel_size = 0.01
	shed.add_child(sign)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 4.2, -1.0)
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 2.5
	lamp.omni_range = 14.0
	lamp.shadow_enabled = true
	shed.add_child(lamp)


func _solid(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


# ---------------------------------------------------------------------------- trees

func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 8
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 2.4
	crown_mesh.height = 7.0
	crown_mesh.radial_segments = 10
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.3, 0.22, 0.15)
	trunk_mat.roughness = 0.9
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.12, 0.26, 0.12)
	crown_mat.roughness = 0.85
	crown_mat.albedo_texture = _noise_texture(0.4, Color(0.7, 0.75, 0.7), Color(1.1, 1.15, 1.05))

	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < 1400 and tries < 20000:
		tries += 1
		var x := _rng.randf_range(-MAP_HALF + 10.0, MAP_HALF - 10.0)
		var z := _rng.randf_range(-MAP_HALF + 10.0, MAP_HALF - 10.0)
		if _yard_mask(x, z) < 0.3:
			continue
		if _road_info(x, z).x < ROAD_HALF_WIDTH + 9.0:
			continue
		# Woods in clumps.
		if _noise.get_noise_2d(x * 2.5 + 500.0, z * 2.5) < -0.05:
			continue
		var h := _terrain_height_estimate(x, z)
		var s := _rng.randf_range(0.7, 1.4)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h, z)))

	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	trunks.instance_count = transforms.size()
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = crown_mesh
	crowns.instance_count = transforms.size()
	var tree_body := StaticBody3D.new()
	tree_body.name = "Trees"
	tree_body.set_meta("surface", "grass")
	for i in transforms.size():
		var t := transforms[i]
		trunks.set_instance_transform(i, t.translated_local(Vector3(0.0, 1.5, 0.0)))
		crowns.set_instance_transform(i, t.translated_local(Vector3(0.0, 5.5, 0.0)))
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3 * t.basis.get_scale().x
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = t.origin + Vector3.UP * 2.0
		tree_body.add_child(cs)
	add_child(tree_body)
	for pair in [[trunks, trunk_mat], [crowns, crown_mat]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = pair[0]
		mmi.material_override = pair[1]
		add_child(mmi)


func _terrain_height_estimate(x: float, z: float) -> float:
	var h := _natural_height(x, z)
	var info := _road_info(x, z)
	if info.x < 40.0:
		h = lerpf(h, info.y - 0.25, 1.0 - smoothstep(ROAD_HALF_WIDTH + 1.0, ROAD_HALF_WIDTH + 16.0, info.x))
	return h - 0.3
