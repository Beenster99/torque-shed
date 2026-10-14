class_name BlastMarks
extends MultiMeshInstance3D
## Bare metal showing through on an engine in the sandblaster: a bright steel disc on each patch
## of its surface, fading in as the jet strips the rust and muck off it, and going dull and
## pitted where it's been blasted too long. One multimesh for the whole engine, so it's cheap.
## Lives on the engine's BikeModel, so it turns with it.

const BARE := Color(0.9, 0.91, 0.94)
const PITTED := Color(0.42, 0.42, 0.45)

var _count := 0
var _coats := PackedFloat32Array()   # kept here too: a headless renderer doesn't hold instance colours
var _over := 4.5


## `points` and `normals` are every patch on the engine, in the model's space; `cell` their size.
func setup(points: PackedVector3Array, normals: PackedVector3Array, cell: float, over_level: float) -> void:
	_count = points.size()
	_over = over_level
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(cell * 1.9, cell * 1.9)
	mm.mesh = quad
	mm.instance_count = _count
	_coats.resize(_count)
	_coats.fill(0.0)
	for i in _count:
		var n := normals[i].normalized() if normals[i].length() > 0.5 else Vector3.UP
		var side := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var b := Basis(side, n.cross(side), n).rotated(n, float(i % 7) * 0.9)
		mm.set_instance_transform(i, Transform3D(b, points[i] + n * 0.003))
		mm.set_instance_color(i, Color(BARE.r, BARE.g, BARE.b, 0.0))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PaintSplats._blob_texture()
	m.metallic = 0.75
	m.roughness = 0.28
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m


## Patch `i` has had `coats` of blasting (1 strips it to bare metal).
func set_coats(i: int, coats: float) -> void:
	if i < 0 or i >= _count:
		return
	_coats[i] = coats
	var a := clampf(coats, 0.0, 1.0)
	var c := BARE
	if coats > _over:
		# Overdone: the metal goes grey and pitted.
		c = BARE.lerp(PITTED, clampf((coats - _over) / _over, 0.0, 1.0))
	multimesh.set_instance_color(i, Color(c.r, c.g, c.b, a * 0.97))


## How many patches show any bare metal yet (for tests).
func bare_count() -> int:
	var n := 0
	for i in _count:
		if _coats[i] > 0.5:
			n += 1
	return n


func patch_count() -> int:
	return _count
