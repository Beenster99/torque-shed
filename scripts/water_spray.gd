class_name WaterSpray
extends CPUParticles3D
## The pressure washer jet: a tight, fast fan of fine high-pressure water, thin streaks
## stretched along their flight (lots of small fast ones, not a few fat drops), with a thin glassy
## pencil of water at the nozzle (the "Core" child) and a fine mist hanging round it (the "Mist"
## child). Fires along -Z from where it sits. Set `emitting` like any CPUParticles3D; the mist
## follows. set_reach() stops the water where it lands, so it doesn't go through what it hits.

const SPEED := 30.0          # m/s out of the nozzle (a real one's faster still, but this reads)
const REACH := 3.0           # metres it flies when it doesn't hit anything

var _mist: CPUParticles3D
var _core: MeshInstance3D
var _reach := REACH


static func make() -> WaterSpray:
	var jet := WaterSpray.new()
	jet.emitting = false
	jet.amount = 420
	jet.lifetime = REACH / SPEED
	jet.local_coords = false
	jet.direction = Vector3(0.0, 0.0, -1.0)
	jet.spread = 3.0
	jet.flatness = 0.9   # a flat fan, like a 15-degree washer tip
	jet.initial_velocity_min = SPEED * 0.9
	jet.initial_velocity_max = SPEED * 1.1
	jet.gravity = Vector3(0.0, -9.8, 0.0)
	jet.particle_flag_align_y = true   # each streak lies along its velocity
	jet.scale_amount_min = 0.6
	jet.scale_amount_max = 1.1
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(0.3, 1.0))
	grow.add_point(Vector2(1.0, 1.0))
	jet.scale_amount_curve = grow
	jet.color_ramp = _fade(Color(0.92, 0.97, 1.0, 0.7), Color(0.88, 0.94, 1.0, 0.25))
	# A hair-thin rod reads the same from every side, unlike a flat quad; long, as fast water
	# blurs into a line.
	var streak := CylinderMesh.new()
	streak.top_radius = 0.0012
	streak.bottom_radius = 0.0022
	streak.height = 0.34
	streak.radial_segments = 4
	streak.rings = 1
	streak.cap_top = false
	streak.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.82, 0.9, 1.0, 0.55)
	m.metallic_specular = 1.0
	m.roughness = 0.05
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.emission_enabled = true   # a touch of glow so it still reads in a dim shed
	m.emission = Color(0.4, 0.47, 0.55)
	m.emission_energy_multiplier = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	streak.material = m
	jet.mesh = streak
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mist := CPUParticles3D.new()
	mist.name = "Mist"
	mist.emitting = false
	mist.amount = 220
	mist.lifetime = 0.45
	mist.local_coords = false
	mist.direction = Vector3(0.0, 0.0, -1.0)
	mist.spread = 5.0
	mist.flatness = 0.6
	mist.initial_velocity_min = 10.0
	mist.initial_velocity_max = 22.0
	mist.damping_min = 30.0
	mist.damping_max = 45.0
	mist.gravity = Vector3(0.0, -0.8, 0.0)
	mist.angle_min = 0.0
	mist.angle_max = 360.0
	# Fine: a centimetre or two across, never puffs.
	mist.scale_amount_min = 0.012
	mist.scale_amount_max = 0.035
	var puff := Curve.new()
	puff.add_point(Vector2(0.0, 0.4))
	puff.add_point(Vector2(1.0, 1.0))
	mist.scale_amount_curve = puff
	mist.color_ramp = _fade(Color(0.92, 0.96, 1.0, 0.16), Color(0.92, 0.96, 1.0, 0.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := StandardMaterial3D.new()
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.billboard_keep_scale = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _soft_dot()
	mm.disable_receive_shadows = true
	quad.material = mm
	mist.mesh = quad
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.position = Vector3(0.0, 0.0, -0.05)
	jet.add_child(mist)
	jet._mist = mist
	jet._core = _make_core()
	jet.add_child(jet._core)
	return jet


## The solid glassy rod of water right out of the nozzle, before it breaks into streaks.
static func _make_core() -> MeshInstance3D:
	var rod := CylinderMesh.new()
	rod.top_radius = 0.006       # far end, after rotation
	rod.bottom_radius = 0.002    # at the nozzle
	rod.height = 0.4
	rod.radial_segments = 10
	rod.rings = 1
	rod.cap_top = false
	rod.cap_bottom = false
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.93, 1.0, 0.7)
	m.albedo_texture = tex
	m.metallic_specular = 1.0
	m.roughness = 0.05
	m.rim_enabled = true
	m.rim = 0.8
	m.emission_enabled = true
	m.emission = Color(0.3, 0.38, 0.45)
	m.emission_energy_multiplier = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	rod.material = m
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = rod
	core.rotation.x = -PI * 0.5
	core.position = Vector3(0.0, 0.0, -0.2)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.visible = false
	return core


func _process(_delta: float) -> void:
	if _mist and _mist.emitting != emitting:
		_mist.emitting = emitting
	if _core:
		_core.visible = emitting


## How far the water flies before it lands (metres): it stops there, and the pencil at the
## nozzle reaches at most half way. Only changed when it changes by a fair bit, so the streaks
## already in the air carry on smoothly.
func set_reach(metres: float) -> void:
	var d := clampf(metres, 0.15, REACH)
	if absf(d - _reach) < 0.08 * _reach:
		return
	_reach = d
	lifetime = d / SPEED
	if _mist:
		_mist.lifetime = clampf(d / SPEED * 4.0, 0.12, 0.45)
	if _core:
		var len := minf(0.4, d * 0.5)
		_core.scale = Vector3(1.0, len / 0.4, 1.0)
		_core.position = Vector3(0.0, 0.0, -len * 0.5)


static func _fade(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	g.add_point(0.6, Color(from, from.a * 0.8))
	return g


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot = t
	return t
