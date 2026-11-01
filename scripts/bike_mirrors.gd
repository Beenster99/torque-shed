class_name BikeMirrors
extends Node
## The ridden bike's live mirrors: each mirror's glass shows what's behind, drawn by a camera of
## its own into a small SubViewport. That camera sits where the eye that's looking (yours in
## first person, the chase camera's in third) is reflected through the glass's plane, and looks
## back through the glass with an off-axis frustum whose near plane is the glass itself: the
## stalk, the bars and the front of the bike in front of it are cut away, and the picture lies
## straight across the glass, so what's in it is what a real mirror there would show. The
## glass hangs off the bars, so it turns with them as they steer.
##
## Settings.gfx_mirrors sets the detail (LEVELS): how sharp the picture is, how often it's drawn
## (every Nth frame, the two mirrors taking turns), how far back it sees and which effects it
## has. It's drawn with a cheap copy of the world's environment (no GI, volumetric fog,
## reflections or glow) in linear HDR, so the main view tonemaps and blooms it the same as
## everything else, and its cull mask leaves out the rider's head and body (BikeModel's
## HELMET_LAYER) and the mirror glass (GLASS_LAYER). Off, there are no viewports at all and the
## glass keeps the plain shiny material it was drawn with. Only the local player's ridden bike
## has one of these (main adds it); everyone else's bikes keep plain glass.

## The render layer the live glass is moved to, for the mirror cameras to leave out.
const GLASS_LAYER := 11
## Each detail level: the picture's height in pixels at most, and how many of its pixels go to
## each of the glass's on the screen (over 1 is supersampled: smoother), drawn every how many
## frames, how far it sees (metres), the mesh LOD threshold (higher is coarser), MSAA, the lamps' shadow
## atlas (0: the lamps cast no shadows in it) and ambient occlusion.
const LEVELS := {
	"low": {"px": 128, "sample": 0.8, "every": 3, "far": 150.0, "lod": 4.0, "msaa": Viewport.MSAA_DISABLED, "shadows": 0, "ssao": false},
	"medium": {"px": 192, "sample": 1.25, "every": 2, "far": 300.0, "lod": 2.0, "msaa": Viewport.MSAA_DISABLED, "shadows": 0, "ssao": false},
	"high": {"px": 256, "sample": 1.75, "every": 1, "far": 500.0, "lod": 1.5, "msaa": Viewport.MSAA_2X, "shadows": 1024, "ssao": false},
	"ultra": {"px": 384, "sample": 2.5, "every": 1, "far": 900.0, "lod": 1.0, "msaa": Viewport.MSAA_4X, "shadows": 2048, "ssao": true},
}
## The heights the picture steps between: smaller while the glass is small on the screen (in the
## chase view it's a few dozen pixels across).
const SIZES := [32, 48, 64, 96, 128, 192, 256, 384]
## A bike mirror's reflection is a touch darker and bluer than the world.
const TINT := Color(0.74, 0.77, 0.82)
## Seconds between fresh copies of the world's environment (the time of day and weather move it).
const ENV_EVERY := 1.0

const SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_back;

uniform sampler2D view : filter_linear, repeat_disable;
uniform vec4 row_x;
uniform vec4 row_y;
uniform vec3 tint = vec3(0.74, 0.77, 0.82);
uniform float round_glass = 0.0;
varying vec2 uv_m;

void vertex() {
	uv_m = vec2(dot(row_x.xyz, VERTEX) + row_x.w, dot(row_y.xyz, VERTEX) + row_y.w);
}

void fragment() {
	vec2 uv = clamp(uv_m, 0.0, 1.0);
	vec3 c = texture(view, uv).rgb * tint;
	// A soft dark rim where the glass meets its shell.
	vec2 d = abs(uv_m - 0.5) * 2.0;
	float edge = round_glass > 0.5 ? length(d) : max(d.x, d.y);
	ALBEDO = c * (1.0 - 0.35 * smoothstep(0.82, 1.0, edge));
}
"""

static var _shader: Shader

## The Bike whose mirrors these are (its parent, if not set).
var bike: Node3D
## The level now: "off" or one of LEVELS.
var level := "off"
## One for each mirror: {"vp", "cam", "mat", "glass", "frame", "size", "plain", "layers", "px"}.
var views: Array = []
## How many mirrors were drawn this frame, and how many are in sight.
var drawn := 0
var in_sight := 0
var _model: BikeModel
var _frame := 0
var _env: Environment
var _env_in := 0.0


## The BikeMirrors on `b` (a Bike), or null.
static func of(b: Node) -> BikeMirrors:
	if b == null or not is_instance_valid(b):
		return null
	for c in b.get_children():
		if c is BikeMirrors:
			return c
	return null


func _ready() -> void:
	name = "Mirrors"
	if bike == null:
		bike = get_parent() as Node3D
	# After the cameras and the bike have moved for the frame.
	process_priority = 100
	Settings.graphics_changed.connect(apply)
	apply()


func _exit_tree() -> void:
	_clear()


## Puts Settings.gfx_mirrors into effect.
func apply() -> void:
	var want: String = Settings.gfx_mirrors if LEVELS.has(Settings.gfx_mirrors) else "off"
	if want == level and (want == "off" or not views.is_empty()):
		return
	level = want
	_clear()
	_env = null
	set_process(level != "off")


## Whether the mirrors are live (on, and the bike has some).
func live() -> bool:
	return level != "off" and not views.is_empty()


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_frame += 1
	_env_in -= delta
	var model: BikeModel = bike.get("model") if bike and is_instance_valid(bike) else null
	if model != _model or views.any(func(v): return not is_instance_valid(v["glass"])):
		_bind(model)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	update(cam)
	Perf.add("mirrors", pt)


## Sets up a viewport and camera for each of `model`'s mirrors, and puts the live look on its glass.
func _bind(model: BikeModel) -> void:
	_clear()
	_model = model
	if model == null or level == "off":
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var cfg: Dictionary = LEVELS[level]
	for m in model.mirrors:
		var glass: MeshInstance3D = m["glass"]
		if not is_instance_valid(glass):
			continue
		var vp := SubViewport.new()
		vp.name = "MirrorView"
		vp.use_hdr_2d = true   # linear and unclamped: the main view tonemaps it with everything else
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.positional_shadow_atlas_size = int(cfg["shadows"])
		vp.msaa_3d = int(cfg["msaa"])
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.mesh_lod_threshold = float(cfg["lod"])
		vp.size = _view_size(m["size"], int(cfg["px"]))
		add_child(vp)
		var cam := Camera3D.new()
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (aimed once a drawn frame, below)
		cam.projection = Camera3D.PROJECTION_FRUSTUM
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.cull_mask = cull_mask()
		cam.far = float(cfg["far"])
		vp.add_child(cam)
		cam.current = true
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("view", vp.get_texture())
		mat.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
		mat.set_shader_parameter("round_glass", 1.0 if glass.mesh is CylinderMesh else 0.0)
		var rows := uv_rows((m["frame"] as Node3D).transform.affine_inverse() * glass.transform, m["size"])
		mat.set_shader_parameter("row_x", rows[0])
		mat.set_shader_parameter("row_y", rows[1])
		views.append({"vp": vp, "cam": cam, "mat": mat, "glass": glass, "frame": m["frame"], "size": m["size"],
			"plain": glass.material_override, "layers": glass.layers, "px": vp.size.y})
		glass.material_override = mat
		glass.layers = 1 << (GLASS_LAYER - 1)


## Takes the viewports away and gives the glass back its plain look.
func _clear() -> void:
	for v in views:
		var glass: MeshInstance3D = v["glass"]
		if is_instance_valid(glass):
			glass.material_override = v["plain"]
			glass.layers = int(v["layers"])
		(v["vp"] as Node).queue_free()
	views.clear()
	_model = null
	drawn = 0
	in_sight = 0


## The mirror cameras' cull mask: everything but the rider's head and body and the mirror glass.
static func cull_mask() -> int:
	return 0xFFFFF & ~(1 << (BikeModel.HELMET_LAYER - 1)) & ~(1 << (GLASS_LAYER - 1))


## The viewport size for glass `size` (width, height) at `px` high.
static func _view_size(size: Vector2, px: int) -> Vector2i:
	return Vector2i(maxi(8, roundi(px * size.x / maxf(size.y, 0.001))), px)


## Aims each mirror's camera from `eye_cam`'s eye and draws the ones due this frame.
func update(eye_cam: Camera3D) -> void:
	drawn = 0
	in_sight = 0
	if views.is_empty() or eye_cam == null:
		return
	var cfg: Dictionary = LEVELS[level]
	var every := int(cfg["every"])
	if _env == null or _env_in <= 0.0:
		_env_in = ENV_EVERY
		_env = cheap_environment(_world_environment(), true, bool(cfg["ssao"]))
	# Where the eye and the mirrors are drawn this frame (eased between the physics ticks, see Bike._ready).
	var eye := eye_cam.get_global_transform_interpolated().origin
	var measure := Perf.on
	for i in views.size():
		var v: Dictionary = views[i]
		var glass: MeshInstance3D = v["glass"]
		var vp: SubViewport = v["vp"]
		if measure != bool(v.get("measured", false)):
			v["measured"] = measure
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), measure)
		if glass.material_override != v["mat"]:
			# Something gave the glass a new look (a respray): keep that one for when it's off.
			v["plain"] = glass.material_override
			glass.material_override = v["mat"]
		var frame := (v["frame"] as Node3D).get_global_transform_interpolated()
		var size: Vector2 = v["size"]
		var view := mirror_view(eye, frame, size)
		if view.is_empty() or not glass.is_visible_in_tree() or not _on_screen(eye_cam, frame, size):
			continue
		in_sight += 1
		if (_frame + i * maxi(1, every / 2)) % every != 0:
			continue
		var px := _pixels_for(eye_cam, eye.distance_to(frame.origin), size.y, float(cfg["sample"]), int(cfg["px"]), int(v["px"]))
		if px != int(v["px"]):
			v["px"] = px
			vp.size = _view_size(size, px)
		var cam: Camera3D = v["cam"]
		cam.global_transform = view["xf"]
		cam.set_frustum(float(view["size"]), view["offset"], float(view["near"]), float(cfg["far"]))
		if cam.environment != _env:
			cam.environment = _env
		if measure:
			# Its last drawing's time, counted for each time it's drawn.
			Perf.add_us("mirrors_gpu", roundi(1000.0 * (RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
				+ RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))))
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		drawn += 1


## The camera for a mirror with its face at `frame` (+Z out of the glass, X across it, Y up it)
## and `size` (width, height), seen from `eye`: {"xf": where it sits and faces, "near": the
## distance to the glass, "offset": the glass's centre off its axis, "size": the frustum's height
## at the glass}, all for Camera3D.set_frustum. Empty when `eye` is behind the glass.
static func mirror_view(eye: Vector3, frame: Transform3D, size: Vector2) -> Dictionary:
	var c := frame.origin
	var u := frame.basis.x.normalized()
	var w := frame.basis.y.normalized()
	var n := frame.basis.z.normalized()
	var d := (eye - c).dot(n)
	if d <= 0.005:
		return {}
	# The eye reflected through the glass's plane, looking back into the glass: its right is the
	# glass's left (the picture is flipped back across the glass, see uv_rows).
	var reflected := eye - 2.0 * d * n
	var xf := Transform3D(Basis(-u, w, -n), reflected)
	var rel := eye - c
	return {"xf": xf, "near": d, "offset": Vector2(rel.dot(u), -rel.dot(w)), "size": size.y}


## The shader's two rows taking a point on the glass mesh (in its own space) to the picture's UV,
## given `to_frame` (the glass mesh's space to the frame's) and the glass's `size`: across is
## flipped, as the mirror camera looks the other way.
static func uv_rows(to_frame: Transform3D, size: Vector2) -> Array:
	var b := to_frame.basis
	var o := to_frame.origin
	var rx := Vector3(b.x.x, b.y.x, b.z.x)
	var ry := Vector3(b.x.y, b.y.y, b.z.y)
	return [Vector4(-rx.x / size.x, -rx.y / size.x, -rx.z / size.x, 0.5 - o.x / size.x),
		Vector4(-ry.x / size.y, -ry.y / size.y, -ry.z / size.y, 0.5 - o.y / size.y)]


## The UV on the picture that a point `p` on the glass (in the glass mesh's space) shows.
static func uv_of(rows: Array, p: Vector3) -> Vector2:
	var a: Vector4 = rows[0]
	var b: Vector4 = rows[1]
	return Vector2(Vector3(a.x, a.y, a.z).dot(p) + a.w, Vector3(b.x, b.y, b.z).dot(p) + b.w)


## Whether any of the glass is in `cam`'s view.
static func _on_screen(cam: Camera3D, frame: Transform3D, size: Vector2) -> bool:
	var u := frame.basis.x.normalized() * size.x * 0.5
	var w := frame.basis.y.normalized() * size.y * 0.5
	for p in [frame.origin, frame.origin + u + w, frame.origin + u - w, frame.origin - u + w, frame.origin - u - w]:
		if cam.is_position_in_frustum(p):
			return true
	return false


## The picture height for glass `h` high, `dist` from `cam`: `sample` times the pixels it covers
## on the screen, at most `top`. `now` is the height it has, kept unless it's well off.
static func _pixels_for(cam: Camera3D, dist: float, h: float, sample: float, top: int, now: int) -> int:
	var screen_h := float(cam.get_viewport().get_visible_rect().size.y) if cam.get_viewport() else 720.0
	var on_screen := h / maxf(dist, 0.05) * screen_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var want: int = SIZES[SIZES.size() - 1]
	for s in SIZES:
		if s >= on_screen * sample:
			want = s
			break
	want = mini(want, top)
	# A step up as soon as it's needed; down only once well under, so it doesn't flick between two.
	if want > now or float(want) < now * 0.6:
		return want
	return mini(now, top)


func _world_environment() -> Environment:
	var w := get_viewport().find_world_3d() if is_inside_tree() else null
	if w and w.environment:
		return w.environment
	return Lighting.current.env if Lighting.current else null


## A copy of `world` for a little second view, less the costly extras each viewport would work
## out all over again (global illumination, volumetric fog, screen-space reflections and light).
## `hdr`: left linear for the main view to tonemap (no tonemapping, exposure, adjustments or
## glow of its own); otherwise tonemapped as the world is, for showing as it is. `ssao` keeps
## ambient occlusion.
static func cheap_environment(world: Environment, hdr: bool, ssao := false) -> Environment:
	if world == null:
		return null
	var env: Environment = world.duplicate()
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.ssao_enabled = ssao and world.ssao_enabled
	env.glow_enabled = false
	if hdr:
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.adjustment_enabled = false
	return env
