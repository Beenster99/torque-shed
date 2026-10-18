class_name World
extends Node3D
## The riding map, about four kilometres across: the shed on the High Street of a little town
## (WorldTown, with the people walking its pavements), its yard behind it (laid out as a bike
## test area, see WorldYard), the 1 km tarmac loop round them, a network of tarmac roads out to the
## villages and farms and over a mountain pass with hairpins, and dirt tracks off them, the
## hardest up in the mountains. Woods, rocks, fences, barriers, signs, houses and farmyards
## (WorldProps) fill it in. Generated from a seed so every player in a session gets the same
## map; the land is WorldTerrain, the roads WorldRoads and the plan WorldLayout.

const MAP_HALF := WorldTerrain.HALF
const ROAD_HALF_WIDTH := 4.0     # the loop's (other roads are a little narrower)
const YARD_CENTER := WorldYard.CENTER
const YARD_HALF := WorldYard.HALF
## Near terrain (full detail) out to this far, times the draw distance setting; the coarse
## mesh beyond. Roads, props and markings have their own ranges.
const TERRAIN_NEAR := 700.0
const ROAD_CHUNK := 48           # road samples per mesh chunk

## What generating the same seed again can reuse in this run (the land, the roads and their
## meshes), so going back to the menu and starting again doesn't make it all over again.
static var _cache := {}

var terrain: WorldTerrain
var roads: WorldRoads
var yard: WorldYard
var props: WorldProps
var town: WorldTown
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var workshop: Workshop
var daylight: Daylight
var weather: Weather
var lighting: Lighting
## Ground that rain soaks (see Weather): [{mat, color, rough, shine}], shine 0 (stays matt) .. 1.
var wet_surfaces := []
## [GeometryInstance3D, range end, range begin] for every node the draw distance scales.
var _ranged := []


func generate(seed_value := 1) -> void:
	_build_environment()
	var data := _data_for(seed_value)
	terrain = data["terrain"]
	roads = data["roads"]
	_build_terrain(data)
	_build_roads(data)
	yard = WorldYard.new()
	add_child(yard)
	yard.build(self)
	_build_garage()
	_build_yard_lights()
	town = WorldTown.new()
	town.name = "Town"
	add_child(town)
	town.build(self)
	props = WorldProps.new()
	props.name = "Props"
	add_child(props)
	props.build(self, data)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(self)
	_apply_draw_distance()
	if Settings.has_signal("graphics_changed"):
		Settings.graphics_changed.connect(_apply_draw_distance)


## The land, the roads and the meshes for `seed_value`, made once per run.
static func _data_for(seed_value: int) -> Dictionary:
	if _cache.has(seed_value):
		return _cache[seed_value]
	var t := WorldTerrain.new(seed_value)
	var r := WorldRoads.new()
	r.build(t)
	t.build(r)
	var data := {"terrain": t, "roads": r, "seed": seed_value}
	var count := WorldTerrain.chunk_count()
	var near := []
	var far := []
	for cz in count:
		for cx in count:
			near.append(t.chunk_mesh(cx, cz, 1))
			far.append(t.chunk_mesh(cx, cz, WorldTerrain.COARSE))
	data["near"] = near
	data["far"] = far
	data["shape"] = t.make_shape()
	data["horizon"] = t.horizon_mesh()
	data["road_chunks"] = _road_chunks(r)
	data["props"] = WorldProps.plan(t, r, seed_value)
	_cache.clear()   # only the latest map is kept
	_cache[seed_value] = data
	return data


# ---------------------------------------------------------------------------- queries

## The length of the 1 km loop, in metres.
func road_length() -> float:
	return float(roads.roads[0]["length"])


## A transform on the loop's centre line at fraction t (0..1) of the way round, facing along it.
func road_transform(t: float) -> Transform3D:
	var loop: Dictionary = roads.roads[0]
	var n := (loop["xz"] as PackedVector2Array).size()
	return road_transform_on("loop", wrapf(t, 0.0, 1.0) * n * WorldRoads.STEP)


## A transform on road `road_name`'s centre line `metres` from its start, facing along it.
func road_transform_on(road_name: String, metres: float) -> Transform3D:
	var ri := int(roads.by_name[road_name])
	var r: Dictionary = roads.roads[ri]
	var n := (r["xz"] as PackedVector2Array).size()
	var i := clampi(int(metres / WorldRoads.STEP), 0, n - 1)
	var dir: Vector2 = (r["dir"] as PackedVector2Array)[i]
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), roads.point(ri, i) + Vector3.UP * 0.1)


## Where player number `index` starts: lined up on the forecourt in front of the garage,
## facing the street.
func spawn_point(index: int) -> Transform3D:
	var x := -9.0 + (index % 7) * 3.0
	var z := 80.0 + (index / 7) * 3.5
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.05, z))


## The height of whatever is solid under (x, z): ground, road, yard or a roof.
func surface_height(x: float, z: float) -> float:
	var from := Vector3(x, 1000.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2000.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else terrain_height(x, z)


## The height of the ground (not roads or buildings) at (x, z), straight off the land's grid.
func terrain_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## Distance to the nearest road's centre line (capped at 40 m) and that road's height there.
func _road_info(x: float, z: float) -> Vector2:
	var near := roads.nearest(x, z, 40.0)
	if near.is_empty():
		return Vector2(40.0, 0.0)
	return Vector2(float(near["d"]), float(near["h"]))


## The name of the village or farm nearest (x, z) within `reach` metres, or "".
static func place_near(x: float, z: float, reach := 400.0) -> String:
	var best := ""
	var best_d := reach
	for s in WorldLayout.SITES:
		var d := (s["at"] as Vector2).distance_to(Vector2(x, z))
		if d < best_d:
			best_d = d
			best = str(s["name"])
	return best


# ---------------------------------------------------------------------------- environment

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()   # Daylight gives it a day-night sky shader
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
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = Settings.high_quality
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	# Fairly even scattering: a forward-heavy fog turns a headlight seen end-on into a hard streak.
	env.volumetric_fog_anisotropy = 0.35
	# Blend each frame's fog with the last ones more, for a smoother, softer haze.
	env.volumetric_fog_temporal_reprojection_amount = 0.95
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

	daylight = Daylight.new()
	daylight.name = "Daylight"
	add_child(daylight)
	daylight.setup(env, _sun)

	# The lighting quality (Settings' Graphics options): GI, fog, clouds, shadows, eye adaptation.
	lighting = Lighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(env, _sun, daylight)


## The time of day in hours (0..24), from the session's Daylight. 12 when there's no world.
static func time_of_day() -> float:
	return Daylight.time_of_day()


## 0 in full daylight .. 1 at night. Read it every frame, or connect to
## `daylight.darkness_changed`.
static func darkness() -> float:
	return Daylight.darkness()



# ---------------------------------------------------------------------------- terrain

func _build_terrain(data: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.set_meta("surface", "grass")
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = data["shape"]
	# The height map is one unit between samples, scaled up (uniformly) to the grid spacing.
	cs.scale = Vector3.ONE * WorldTerrain.SPACING
	body.add_child(cs)
	add_child(body)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.albedo_texture = _noise_texture(0.05, Color(0.74, 0.74, 0.74), Color(1.12, 1.12, 1.12))
	_wet(mat, 0.15)
	var meshes := Node3D.new()
	meshes.name = "TerrainMesh"
	body.add_child(meshes)
	var count := WorldTerrain.chunk_count()
	for cz in count:
		for cx in count:
			var c := WorldTerrain.chunk_center(cx, cz)
			for lod in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = (data["near"] if lod == 0 else data["far"])[cz * count + cx]
				mi.material_override = mat
				mi.position = Vector3(c.x, 0.0, c.y)
				if lod == 0:
					_ranged.append([mi, TERRAIN_NEAR, 0.0])
				else:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_ranged.append([mi, 0.0, TERRAIN_NEAR])
				meshes.add_child(mi)
	var horizon := MeshInstance3D.new()
	horizon.name = "Horizon"
	horizon.mesh = data["horizon"]
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.vertex_color_is_srgb = true
	hm.roughness = 1.0
	horizon.material_override = hm
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meshes.add_child(horizon)


## Every node whose visibility range follows the draw distance setting, rescaled to it.
func _apply_draw_distance() -> void:
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	for entry in _ranged:
		var gi: GeometryInstance3D = entry[0]
		if not is_instance_valid(gi):
			continue
		var end: float = entry[1]
		var begin: float = entry[2]
		gi.visibility_range_end = end * scale if end > 0.0 else 0.0
		gi.visibility_range_end_margin = 30.0 if end > 0.0 else 0.0
		gi.visibility_range_begin = begin * scale if begin > 0.0 else 0.0
		gi.visibility_range_begin_margin = 30.0 if begin > 0.0 else 0.0


## Keeps `gi` drawn out to `end` metres away (times the draw distance setting) and no further.
func ranged(gi: GeometryInstance3D, end: float) -> void:
	_ranged.append([gi, end, 0.0])


# ---------------------------------------------------------------------------- roads

## The meshes of every road in chunks of ROAD_CHUNK samples: [{road, mesh, faces, marks,
## center}], made once per seed (see _data_for).
static func _road_chunks(r: WorldRoads) -> Array:
	var out := []
	for ri in r.roads.size():
		var road: Dictionary = r.roads[ri]
		var n := (road["xz"] as PackedVector2Array).size()
		var last := n if road["closed"] else n - 1
		var from := 0
		while from < last:
			var to := mini(from + ROAD_CHUNK, last)
			var surf := WorldRoadMesh.surface(road, from, to)
			out.append({"road": ri, "mesh": surf[0], "faces": surf[1], "center": surf[2],
				"marks": WorldRoadMesh.markings(road, from, to, surf[2])})
			from = to
	return out


func _build_roads(data: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Roads"
	add_child(holder)
	var tarmac := _wet(_road_material(Color.WHITE, 0.82), 1.0)   # the vertex colours carry the colour
	var dirt := _wet(_road_material(Color.WHITE, 1.0), 0.35)
	tarmac.vertex_color_use_as_albedo = true
	dirt.vertex_color_use_as_albedo = true
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.6
	_wet(paint, 0.6)
	for chunk in data["road_chunks"]:
		var road: Dictionary = roads.roads[int(chunk["road"])]
		var kind: String = road["kind"]
		var body := StaticBody3D.new()
		body.set_meta("surface", kind)
		body.set_meta("road", str(road["name"]))
		body.collision_layer = 1
		var c: Vector3 = chunk["center"]
		body.position = c
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(chunk["faces"])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = chunk["mesh"]
		mi.material_override = tarmac if kind == "tarmac" else dirt
		body.add_child(mi)
		_ranged.append([mi, 1600.0, 0.0])
		var marks = chunk["marks"]
		if marks is Mesh:
			var mm := MeshInstance3D.new()
			mm.mesh = marks
			mm.material_override = paint
			mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mm)
			_ranged.append([mm, 450.0, 0.0])
		holder.add_child(body)


# ---------------------------------------------------------------------------- yard and shed


## Floodlights on poles around the Build Yard that come on at dusk (Daylight drives them via
## its "night_lights" group).
func _build_yard_lights() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.33, 0.34)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.45
	# Round the edge of the test area, clear of the lanes, and along its side nearest the shed.
	var spots: Array[Vector3] = [Vector3(-20.0, 0.0, -16.5), Vector3(36.0, 0.0, -20.0), Vector3(-66.0, 0.0, -10.0),
		Vector3(0.0, 0.0, 36.5), Vector3(66.0, 0.0, -10.0), Vector3(-52.0, 0.0, 36.5), Vector3(52.0, 0.0, 36.5)]
	var aim := Vector3(YARD_CENTER.x, 0.0, YARD_CENTER.y + 8.0)
	for p in spots:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.13
		cyl.height = 8.0
		cyl.radial_segments = 8
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position = p + Vector3.UP * 4.0
		add_child(pole)
		var inward := (aim - p).normalized()
		var head_pos: Vector3 = p + Vector3.UP * 8.1 + inward * 0.35
		var head := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.18, 0.5)
		head.mesh = box
		var lens := StandardMaterial3D.new()
		lens.albedo_color = Color(0.9, 0.9, 0.85)
		lens.emission_enabled = true
		lens.emission = Color(1.0, 0.86, 0.62)
		lens.emission_energy_multiplier = 0.05
		head.material_override = lens
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.position = head_pos
		head.rotation.y = atan2(inward.x, inward.z)
		head.set_meta("night_emission", 6.0)
		head.add_to_group(Daylight.NIGHT_LIGHTS)
		add_child(head)
		var spot := SpotLight3D.new()
		spot.position = head_pos + Vector3.DOWN * 0.15
		spot.basis = Basis.looking_at(p + inward * 16.0 - spot.position, Vector3.UP)
		add_child(spot)
		spot.spot_range = 40.0
		spot.spot_angle = 52.0
		spot.spot_attenuation = 0.8
		spot.spot_angle_attenuation = 1.6
		spot.light_color = Color(1.0, 0.85, 0.62)   # sodium-ish warm
		spot.light_energy = 0.0
		spot.light_volumetric_fog_energy = 2.5
		spot.shadow_enabled = false
		spot.visible = false
		spot.set_meta("night_energy", 14.0)
		spot.add_to_group(Daylight.NIGHT_LIGHTS)
	daylight._update_lamps()



func _build_garage() -> void:
	workshop = Workshop.new()
	add_child(workshop)
	workshop.build()


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



# ---------------------------------------------------------------------------- materials

func _wet(mat: StandardMaterial3D, shine: float) -> StandardMaterial3D:
	wet_surfaces.append({"mat": mat, "color": mat.albedo_color, "rough": mat.roughness, "shine": shine})
	return mat


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

