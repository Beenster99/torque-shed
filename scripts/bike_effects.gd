class_name BikeEffects
extends Node3D
## Exhaust smoke, dust thrown up off loose ground and the headlight beam, for a ridden bike
## and for other players' bikes. Lives on the bike body; feed it with update() every frame.

const DUSTY := {"dirt": 1.0, "grass": 0.45}

var _smoke: CPUParticles3D
var _dust: CPUParticles3D
var _beam: SpotLight3D
var _lamp_glow: OmniLight3D
var _surface := "tarmac"
var _probe_timer := 0.0


## `exhaust` is the tailpipe tip and `rear_contact` where the back tyre meets the ground, both
## in the bike's own space. `lamp` is where the headlight sits; `lumens` 0 means no headlight.
func setup(exhaust: Vector3, rear_contact: Vector3, lamp: Vector3, lumens: float) -> void:
	_smoke = _particles(36, 1.6, _puff_material(Color(0.55, 0.55, 0.57, 0.35)))
	_smoke.position = exhaust
	_smoke.direction = Vector3(0.0, 0.25, 1.0)
	_smoke.spread = 14.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.2
	_smoke.gravity = Vector3(0.0, 0.35, 0.0)
	_smoke.scale_amount_min = 0.12
	_smoke.scale_amount_max = 0.2
	_smoke.scale_amount_curve = _grow_curve(4.5)
	_smoke.color_ramp = _fade(Color(1, 1, 1, 0.55))
	_dust = _particles(70, 1.8, _puff_material(Color(0.62, 0.5, 0.36, 0.5)))
	_dust.position = rear_contact + Vector3(0.0, 0.08, 0.15)
	_dust.direction = Vector3(0.0, 0.6, 1.0)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 3.5
	_dust.gravity = Vector3(0.0, -1.2, 0.0)
	_dust.damping_min = 1.5
	_dust.damping_max = 2.5
	_dust.scale_amount_min = 0.25
	_dust.scale_amount_max = 0.45
	_dust.scale_amount_curve = _grow_curve(4.0)
	_dust.color_ramp = _fade(Color(1, 1, 1, 0.7))
	if lumens > 0.0:
		_beam = SpotLight3D.new()
		_beam.position = lamp + Vector3(0.0, 0.0, -0.08)
		_beam.rotation.x = deg_to_rad(-4.0)
		_beam.spot_range = 18.0 + lumens / 100.0
		_beam.spot_angle = 24.0
		_beam.light_energy = lumens / 450.0
		_beam.light_color = Color(1.0, 0.92, 0.78) if lumens < 2000.0 else Color(0.92, 0.96, 1.0)
		_beam.shadow_enabled = false
		add_child(_beam)
		_lamp_glow = OmniLight3D.new()
		_lamp_glow.position = lamp + Vector3(0.0, 0.0, -0.12)
		_lamp_glow.omni_range = 0.8
		_lamp_glow.light_energy = 0.4
		_lamp_glow.light_color = _beam.light_color
		add_child(_lamp_glow)


func _particles(amount: int, life: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mat
	p.mesh = quad
	p.angle_min = 0.0
	p.angle_max = 360.0
	add_child(p)
	return p


## A soft round billboard puff that takes the particle colour.
func _puff_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	return m


func _grow_curve(to: float) -> Curve:
	var c := Curve.new()
	c.max_value = to
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, to))
	return c


func _fade(start: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, start)
	g.set_color(1, Color(start.r, start.g, start.b, 0.0))
	return g


## `engine_on` runs smoke and lights; `throttle` 0..1 and a tired `health` thicken the smoke.
## `surface` and `rear_contact` decide the dust; pass surface "" to have it looked up.
func update(delta: float, speed: float, throttle: float, engine_on: bool, health: float, surface: String,
		rear_contact: bool, slip: float) -> void:
	if _smoke == null:
		return
	if surface == "":
		_probe_timer -= delta
		if _probe_timer <= 0.0:
			_probe_timer = 0.25
			_surface = _probe_surface()
		surface = _surface
	_smoke.emitting = engine_on
	var dark := clampf(1.0 - health, 0.0, 1.0)
	_smoke.color_ramp.set_color(0, Color(lerpf(0.9, 0.35, dark), lerpf(0.9, 0.35, dark), lerpf(0.92, 0.38, dark),
		lerpf(0.18, 0.6, clampf(throttle * 0.7 + dark * 0.6, 0.0, 1.0))))
	_smoke.initial_velocity_max = 1.2 + throttle * 2.0
	var dusty := float(DUSTY.get(surface, 0.0))
	var kick := clampf((absf(speed) - 2.0) / 12.0, 0.0, 1.0) + slip
	_dust.emitting = rear_contact and dusty > 0.0 and kick > 0.05
	_dust.color_ramp.set_color(0, Color(1, 1, 1, clampf(0.25 + 0.5 * kick, 0.0, 0.8) * dusty))
	_dust.initial_velocity_max = 1.5 + 3.0 * kick
	if _beam:
		_beam.visible = engine_on
		_lamp_glow.visible = engine_on


func _probe_surface() -> String:
	if not is_inside_tree():
		return "tarmac"
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
		return str((hit["collider"] as Object).get_meta("surface"))
	return "grass" if hit else "tarmac"


func smoke_emitting() -> bool:
	return _smoke != null and _smoke.emitting


func dust_emitting() -> bool:
	return _dust != null and _dust.emitting


func light_on() -> bool:
	return _beam != null and _beam.visible
