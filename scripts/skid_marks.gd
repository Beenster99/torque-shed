class_name SkidMarks
extends MultiMeshInstance3D
## Black rubber left on the ground by skidding tyres: one shared ring of short strips that the
## oldest marks are recycled from, so they fade out of existence as new ones go down.

const MAX_MARKS := 3000
const STEP := 0.12        # metres of travel between strips

static var _shared: SkidMarks

var _next := 0
var _last := {}           # wheel key -> where its last strip went down


## The one set of skid marks in the world, made on first use.
static func shared(tree: SceneTree) -> SkidMarks:
	if is_instance_valid(_shared) and _shared.is_inside_tree():
		return _shared
	_shared = SkidMarks.new()
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	host.add_child(_shared)
	return _shared


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.roughness = 0.6
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_MARKS
	multimesh.visible_instance_count = 0
	custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))


## Lays rubber from `key`'s last point to `at` while it skids, `strength` 0..1. Pass strength 0
## when it stops skidding so the next skid starts a fresh line.
func mark(key: String, at: Vector3, normal: Vector3, width: float, strength: float, surface: String) -> void:
	if strength <= 0.0:
		_last.erase(key)
		return
	if not _last.has(key):
		_last[key] = at
		return
	var from: Vector3 = _last[key]
	var run := at - from
	var length := run.length()
	if length < STEP:
		return
	if length > 2.0:
		_last[key] = at
		return
	_last[key] = at
	var along := run / length
	var side := normal.cross(along).normalized()
	var b := Basis(side * width, normal, along * (length + 0.02))
	var xf := Transform3D(b, (from + at) * 0.5 + normal * 0.012)
	multimesh.set_instance_transform(_next, xf)
	var rubber := Color(0.05, 0.05, 0.05) if surface == "tarmac" else Color(0.22, 0.16, 0.1)
	rubber.a = clampf(0.45 + strength * 0.5, 0.0, 0.92)
	multimesh.set_instance_color(_next, rubber)
	_next = (_next + 1) % MAX_MARKS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, mini(_next if _next > 0 else MAX_MARKS, MAX_MARKS))


func count() -> int:
	return multimesh.visible_instance_count if multimesh else 0
