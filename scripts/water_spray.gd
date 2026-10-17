class_name WaterSpray
extends CPUParticles3D
## The pressure washer jet: a tight, fast fan of fine high-pressure water, thin streaks
## stretched along their flight (lots of small fast ones, not a few fat drops), with a thin glassy
## pencil of water at the nozzle (the "Core" child) and a fine mist hanging round it (the "Mist"
## child). Fires along -Z from where it sits. Set `emitting` like any CPUParticles3D; the mist
## follows. set_reach() stops the water where it lands, so it doesn't go through what it hits.

const SPEED := 30.0          # m/s out of the nozzle (a real one's faster still, but this reads)
const REACH := 3.0           # metres it flies when it doesn't hit anything

var _mist: GPUParticles3D
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
	jet.color_ramp = _fade(Color(0.92, 0.97, 1.0, 0.7), Color(0.88, 0.94, 1.0, 0.1))
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

	# A cloud of fine mist hanging all along the jet, drifting out round it (on the GPU, so
	# there can be plenty of it): it lies along the water as far as it reaches (set_reach).
	var mist := make_mist(1200, 1.3, Vector2(0.03, 0.09), 2.2, 0.11)
	mist.name = "Mist"
	var mp := mist.process_material as ParticleProcessMaterial
	mp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mp.emission_box_extents = Vector3(0.03, 0.02, REACH * 0.5)
	mp.emission_shape_offset = Vector3(0.0, 0.0, -REACH * 0.5)
	mp.direction = Vector3(0.0, 0.0, -1.0)
	mp.spread = 180.0
	mp.initial_velocity_min = 0.15
	mp.initial_velocity_max = 1.4
	mp.damping_min = 1.0
	mp.damping_max = 2.5
	mp.gravity = Vector3(0.0, 0.04, 0.0)
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
		var mp := _mist.process_material as ParticleProcessMaterial
		mp.emission_box_extents = Vector3(0.03, 0.02, d * 0.5)
		mp.emission_shape_offset = Vector3(0.0, 0.0, -d * 0.5)
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


## A cloud of fine mist: soft, faint dots drawn on the GPU, so there can be lots of them for
## little cost. `amount` alive at once, each living about `life` seconds, `size` metres across
## (smallest, largest) and growing `grow` times over its life, at most `alpha` opaque, fading in
## and out. It sits in the world (not dragged along with whatever it's on). Set the direction,
## speeds and emission shape on its process material.
static func make_mist(amount: int, life: float, size: Vector2, grow: float, alpha: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6.0, -4.0, -6.0), Vector3(12.0, 8.0, 12.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = size.x
	pm.scale_max = size.y
	pm.lifetime_randomness = 0.35
	var curve := Curve.new()
	curve.max_value = maxf(grow, 1.0)
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, grow))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.93, 0.96, 1.0, alpha)
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true   # no hard edge where a puff meets the bike or a wall
	m.proximity_fade_distance = 0.25
	quad.material = m
	p.draw_pass_1 = quad
	return p


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
