class_name SkidMarks
extends MultiMeshInstance3D
## Black rubber left on the ground by skidding and spinning tyres: one shared ring of short strips
## that the oldest marks are recycled from. Each strip remembers when it went down and fades away
## (in the shader, so nothing is touched per frame) after a few minutes. A burnout on the spot
## smears a dark patch that blackens the longer it spins; on dirt only a faint brown scuff shows,
## and on grass nothing.

const MAX_MARKS := 3000
const STEP := 0.12        # metres of travel between strips
const HOLD := 120.0       # seconds a mark stays at full strength
const FADE := 120.0       # ... then the seconds it takes to fade away
const SCRUB_EVERY := 0.25 # seconds between the smears a tyre spinning on the spot lays
const SCRUB_LENGTH := 0.55   # metres: how long a burnout's patch is, along the bike
## How dark rubber goes down on each surface (none on grass, a faint scuff on dirt).
const RUBBER := {"tarmac": Color(0.04, 0.04, 0.04, 1.0), "concrete": Color(0.05, 0.05, 0.05, 0.9),
	"dirt": Color(0.2, 0.14, 0.09, 0.4), "gravel": Color(0.2, 0.15, 0.1, 0.3)}

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
uniform float now = 0.0;
uniform float hold = 120.0;
uniform float fade = 120.0;
varying float life;
void vertex() {
	life = clamp(1.0 - (now - INSTANCE_CUSTOM.r - hold) / fade, 0.0, 1.0);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	ALPHA = COLOR.a * life;
}
"""

static var _shared: SkidMarks

var _next := 0
var _laid := 0  # every strip ever laid, so a full ring still shows new marks
var _last := {}           # wheel key -> where its last strip went down
var _scrub := {}          # wheel key -> seconds since its last burnout smear
var _clock := 0.0         # seconds since the marks were made: what each strip's age is told from
var _mat: ShaderMaterial
var _born := PackedFloat32Array()   # when each strip went down (the shader has its own copy)
## The last strip laid: where its middle is and its colour (the renderer can't be read back headless).
var last_centre := Vector3.ZERO
var last_color := Color()


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
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("hold", HOLD)
	_mat.set_shader_parameter("fade", FADE)
	quad.material = _mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_MARKS
	multimesh.visible_instance_count = 0
	_born.resize(MAX_MARKS)
	custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))


func _process(delta: float) -> void:
	_clock += delta
	if _laid > 0:
		_mat.set_shader_parameter("now", _clock)


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
	_lay((from + at) * 0.5, run / length, normal, length + 0.02, width, clampf(0.45 + strength * 0.5, 0.0, 0.92), surface)


## A tyre spinning on the spot (a burnout): every SCRUB_EVERY seconds it smears a short patch of
## rubber into the road under it along `heading`, so the patch blackens the longer it spins. When
## it moves (a circle burnout, or riding off still spinning) it draws a line as mark() does.
func scrub(key: String, at: Vector3, normal: Vector3, heading: Vector3, width: float, strength: float, surface: String,
		delta: float) -> void:
	if strength <= 0.0:
		_last.erase(key)
		_scrub.erase(key)
		return
	if _last.has(key) and (_last[key] as Vector3).distance_to(at) >= STEP:
		# Moving: a line, and no smear across it until the tyre has sat in one place a moment.
		mark(key, at, normal, width, strength, surface)
		_scrub[key] = 0.0
		return
	if not _last.has(key):
		_last[key] = at
	var t: float = float(_scrub.get(key, SCRUB_EVERY)) + delta
	if t < SCRUB_EVERY:
		_scrub[key] = t
		return
	_scrub[key] = 0.0
	var along := heading - normal * heading.dot(normal)
	if along.length() < 0.01:
		return
	_lay(at, along.normalized(), normal, SCRUB_LENGTH, width * 1.1, 0.2 + 0.3 * strength, surface)


## Puts one strip down, centred on `centre`, recycling the oldest once the ring is full.
func _lay(centre: Vector3, along: Vector3, normal: Vector3, length: float, width: float, alpha: float, surface: String) -> void:
	var rubber: Color = RUBBER.get(surface, Color(0, 0, 0, 0))
	if rubber.a <= 0.0:
		return
	var side := normal.cross(along).normalized()
	var b := Basis(side * width, normal, along * length)
	last_centre = centre
	last_color = Color(rubber.r, rubber.g, rubber.b, alpha * rubber.a)
	multimesh.set_instance_transform(_next, Transform3D(b, centre + normal * 0.012))
	multimesh.set_instance_color(_next, last_color)
	multimesh.set_instance_custom_data(_next, Color(_clock, 0.0, 0.0, 0.0))
	_born[_next] = _clock
	_next = (_next + 1) % MAX_MARKS
	_laid += 1
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, mini(_next if _next > 0 else MAX_MARKS, MAX_MARKS))


## How strong strip `i` is now, 0 (faded away) .. 1, as the shader works it out (tests).
func life_of(i: int) -> float:
	return clampf(1.0 - (_clock - _born[i] - HOLD) / FADE, 0.0, 1.0)


## The newest strip's index, or -1 before any (tests).
func newest() -> int:
	return (_next - 1 + MAX_MARKS) % MAX_MARKS if _laid > 0 else -1


func count() -> int:
	return multimesh.visible_instance_count if multimesh else 0


## How many strips have been laid in total (keeps rising once the ring is full).
func laid() -> int:
	return _laid
