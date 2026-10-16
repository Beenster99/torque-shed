class_name SprayFx
extends Node3D
## What you see of the spray while you're laying a coat on (SprayJob): a soft cone of paint from
## the nozzle to the part, as wide as the fan where it lands; a ring on the surface showing the
## fan's footprint, coloured by how far off you're holding it (green: the sweet spot, red: too
## close, it'll run, blue: too far, it'll go on dry, grey: out of reach); and droplets landing and
## bouncing back off the surface. Lives in the world; update() it every frame, stop() when done.

const ZONE_COLORS := {"good": Color(0.35, 1.0, 0.5), "close": Color(1.0, 0.35, 0.2), "far": Color(0.35, 0.65, 1.0),
	"out": Color(0.7, 0.7, 0.7)}

const CONE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.2);
varying float along;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	along = 0.5 - VERTEX.y;   // 0 at the nozzle, 1 where it lands
}
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flicker = 0.8 + 0.2 * hash(vec2(floor(UV.x * 40.0), floor(TIME * 30.0)));
	float a = tint.a * pow(facing, 1.6) * mix(1.0, 0.45, along) * flicker;
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.5, 0.7);
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.82, 0.9, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.95, r)) * 0.12;
	float dot_mid = 1.0 - smoothstep(0.05, 0.09, r);
	ALBEDO = tint.rgb;
	ALPHA = clamp((ring + fill + dot_mid * 0.8) * tint.a, 0.0, 1.0);
}
"""

static var _cone_shader: Shader
static var _ring_shader: Shader

var cone: MeshInstance3D
var ring: MeshInstance3D
var droplets: CPUParticles3D
var zone := ""


func _init() -> void:
	name = "SprayFx"
	top_level = true
	if _cone_shader == null:
		_cone_shader = Shader.new()
		_cone_shader.code = CONE_SHADER
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	cone = MeshInstance3D.new()
	cone.name = "Cone"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	cone.mesh = cyl
	var cm := ShaderMaterial.new()
	cm.shader = _cone_shader
	cone.material_override = cm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	ring = MeshInstance3D.new()
	ring.name = "Footprint"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	ring.mesh = q
	var rm := ShaderMaterial.new()
	rm.shader = _ring_shader
	rm.render_priority = 3
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	droplets = CPUParticles3D.new()
	droplets.name = "Droplets"
	droplets.amount = 60
	droplets.lifetime = 0.45
	droplets.local_coords = false
	droplets.emitting = false
	droplets.direction = Vector3(0.0, 1.0, 0.0)
	droplets.spread = 70.0
	droplets.initial_velocity_min = 0.25
	droplets.initial_velocity_max = 0.9
	droplets.gravity = Vector3(0.0, -4.0, 0.0)
	droplets.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	droplets.emission_sphere_radius = 0.05
	droplets.scale_amount_min = 0.004
	droplets.scale_amount_max = 0.01
	var dm := QuadMesh.new()
	dm.size = Vector2.ONE
	var dmat := StandardMaterial3D.new()
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.billboard_keep_scale = true
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.vertex_color_use_as_albedo = true
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.6, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 16
	t.height = 16
	dmat.albedo_texture = t
	dm.material = dmat
	droplets.mesh = dm
	add_child(droplets)
	visible = false


## The spray this frame: from the nozzle `from` to `to` on a surface facing `normal`, landing
## `radius` wide, in paint `color`, held at `fan_zone` distance (see SprayJob.fan_at).
func update(from: Vector3, to: Vector3, normal: Vector3, radius: float, color: Color, fan_zone: String) -> void:
	visible = true
	zone = fan_zone
	var axis := from - to
	var length := axis.length()
	if length < 0.02:
		stop()
		return
	var y := axis / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	cone.global_transform = Transform3D(Basis(x * radius, y * length, z * radius), (from + to) * 0.5)
	var reach := fan_zone != "out"
	cone.visible = true
	(cone.material_override as ShaderMaterial).set_shader_parameter("tint", Color(color.r, color.g, color.b, 0.22 if reach else 0.08))
	var n := normal.normalized() if normal.length() > 0.5 else y
	var rx := n.cross(Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var ry := n.cross(rx)
	ring.global_transform = Transform3D(Basis(rx * radius, ry * radius, n * radius), to + n * 0.006)
	var rc: Color = ZONE_COLORS.get(fan_zone, Color.WHITE)
	(ring.material_override as ShaderMaterial).set_shader_parameter("tint", Color(rc.r, rc.g, rc.b, 0.75))
	# Droplets landing and bouncing back off the surface (none when it falls short).
	var up := n
	var ux := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	droplets.global_transform = Transform3D(Basis(ux, up, ux.cross(up)), to + n * 0.01)
	droplets.emission_sphere_radius = radius * 0.6
	droplets.color = color
	droplets.emitting = reach


func stop() -> void:
	visible = false
	if droplets:
		droplets.emitting = false
