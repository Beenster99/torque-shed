class_name WashFx
extends Node3D
## Where a pressure washer's jet lands, for whoever's washing (yours, and everyone else's from
## where the shed says their jet is landing): water splashing back off the surface, a fine mist
## drifting up off it, dirty water running off across the floor to the nearest drain, and a wet
## patch on the floor that spreads while you wash and dries off slowly after. The drain gurgles
## while water's running into it.

const FLOOR_Y := 0.015
const RUN_SPEED := 0.9        # m/s the water runs across the floor
const PUDDLE_MAX := 1.3       # metres across the wet patch gets
const DRY_TIME := 50.0        # seconds the wet patch takes to dry off

var _splash: CPUParticles3D
var _mist: CPUParticles3D
var _runoff: CPUParticles3D
var _puddle: MeshInstance3D
var _puddle_mat: StandardMaterial3D
var _gurgle: AudioStreamPlayer3D
var _wet := 0.0               # how big the wet patch is, 0..1
var _flow := 0.0              # how much water's running to the drain, 0..1
var _drain := Wash.SHED_DRAIN
var firing := false


func _ready() -> void:
	_splash = _particles(150, 0.45, false)
	_splash.spread = 55.0
	_splash.initial_velocity_min = 1.5
	_splash.initial_velocity_max = 4.5
	_splash.gravity = Vector3(0.0, -9.8, 0.0)
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.1
	_splash.particle_flag_align_y = true
	var drop := CylinderMesh.new()
	drop.top_radius = 0.0025
	drop.bottom_radius = 0.004
	drop.height = 0.07
	drop.radial_segments = 4
	drop.rings = 1
	drop.material = _water_mat(Color(0.85, 0.93, 1.0, 0.55), false)
	_splash.mesh = drop
	_splash.color_ramp = _fade(Color(1, 1, 1, 0.8))
	add_child(_splash)
	_mist = _particles(70, 1.8, false)
	_mist.spread = 75.0
	_mist.initial_velocity_min = 0.3
	_mist.initial_velocity_max = 1.4
	_mist.damping_min = 1.0
	_mist.damping_max = 2.5
	_mist.gravity = Vector3(0.0, 0.18, 0.0)
	_mist.angle_min = 0.0
	_mist.angle_max = 360.0
	_mist.scale_amount_min = 0.18
	_mist.scale_amount_max = 0.55
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	_mist.scale_amount_curve = grow
	var puff := QuadMesh.new()
	var pm := _water_mat(Color(0.92, 0.95, 1.0, 0.13), true)
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	pm.albedo_texture = WaterSpray._soft_dot()
	puff.material = pm
	_mist.mesh = puff
	_mist.color_ramp = _fade(Color(1, 1, 1, 1))
	add_child(_mist)
	_runoff = _particles(90, 3.0, false)
	_runoff.spread = 12.0
	_runoff.flatness = 1.0
	_runoff.gravity = Vector3.ZERO
	_runoff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_runoff.emission_sphere_radius = 0.35
	_runoff.scale_amount_min = 0.12
	_runoff.scale_amount_max = 0.3
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(1.0, 1.0)
	var rm := _water_mat(Color(0.55, 0.6, 0.62, 0.35), true)
	rm.albedo_texture = WaterSpray._soft_dot()
	sheet.material = rm
	_runoff.mesh = sheet
	_runoff.color_ramp = _fade(Color(1, 1, 1, 1))
	add_child(_runoff)
	_puddle = MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(1.0, 1.0)
	_puddle.mesh = disc
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puddle_mat.albedo_color = Color(0.05, 0.06, 0.07, 0.0)
	_puddle_mat.albedo_texture = WaterSpray._soft_dot()
	_puddle_mat.roughness = 0.04
	_puddle_mat.metallic_specular = 1.0
	_puddle.material_override = _puddle_mat
	_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puddle.visible = false
	add_child(_puddle)
	_gurgle = Sfx.make_loop_player(self)
	_gurgle.volume_db = -14.0


func _particles(count: int, life: float, local: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.local_coords = local
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _water_mat(c: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _fade(from: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, Color(from, 0.0))
	return g


## One frame: the jet from `from` landing at `at` on a surface facing `normal` (world), `firing`
## or not. `dirt` (0..1) is how dirty what it's washing is, for the colour of the run-off.
func update(delta: float, from: Vector3, at: Vector3, normal: Vector3, fire: bool, dirt := 0.3) -> void:
	firing = fire
	if fire:
		var d := (at - from).normalized()
		var n := normal.normalized() if normal != Vector3.ZERO else -d
		var back := (d - 2.0 * d.dot(n) * n).normalized()
		_splash.global_position = at
		_splash.direction = (back * 0.6 + n * 0.6).normalized()
		_mist.global_position = at + n * 0.05
		_mist.direction = (n + Vector3.UP * 0.6).normalized()
		var below := Vector3(at.x, FLOOR_Y, at.z)
		_drain = Wash.drain_near(at)
		var to_drain := _drain - below
		to_drain.y = 0.0
		var dist := to_drain.length()
		_runoff.global_position = below
		_runoff.direction = to_drain.normalized() if dist > 0.05 else Vector3.FORWARD
		_runoff.initial_velocity_min = RUN_SPEED * 0.8
		_runoff.initial_velocity_max = RUN_SPEED * 1.2
		_runoff.lifetime = clampf(dist / RUN_SPEED, 0.6, 7.0)
		_runoff.color = Color(0.85, 0.9, 0.92).lerp(Color(0.55, 0.42, 0.28), clampf(dirt, 0.0, 1.0) * 0.7)
		_wet = minf(1.0, _wet + delta / 12.0)
		_flow = minf(1.0, _flow + delta * 0.6)
		if not _puddle.visible or _puddle.global_position.distance_to(below) > 1.5:
			_puddle.global_position = below
		else:
			_puddle.global_position = _puddle.global_position.lerp(below, clampf(delta * 0.3, 0.0, 1.0))
	else:
		_wet = maxf(0.0, _wet - delta / DRY_TIME)
		_flow = maxf(0.0, _flow - delta * 0.25)
	_splash.emitting = fire
	_mist.emitting = fire
	_runoff.emitting = fire or _flow > 0.4
	_puddle.visible = _wet > 0.01
	if _puddle.visible:
		var size := lerpf(0.3, PUDDLE_MAX, sqrt(_wet))
		_puddle.scale = Vector3(size, 1.0, size * 1.2)
		_puddle_mat.albedo_color.a = 0.55 * minf(1.0, _wet * 3.0)
	_gurgle.global_position = _drain
	Sfx.set_loop(_gurgle, "pour" if _flow > 0.15 else "")


## Stops the jet's splash at once (the water already on the floor runs off and dries as usual).
func stop() -> void:
	firing = false
	_splash.emitting = false
	_mist.emitting = false
