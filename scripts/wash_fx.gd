class_name WashFx
extends Node3D
## Where a pressure washer's jet lands, for whoever's washing (yours, and everyone else's from
## where the shed says their jet is landing): a few fine droplets flicked back off the surface, a
## thick cloud of fine mist billowing up off it, dirty water running off across the floor to the nearest drain, and a wet
## patch on the floor that spreads while you wash and dries off slowly after. The drain gurgles
## while water's running into it.

const FLOOR_Y := 0.015
const RUN_SPEED := 0.9        # m/s the water runs across the floor
const PUDDLE_MAX := 1.3       # metres across the wet patch gets
const DRY_TIME := 50.0        # seconds the wet patch takes to dry off
const MIST_AMOUNT := 1600     # mist puffs alive at once where the jet lands

var _splash: CPUParticles3D
var _mist: GPUParticles3D
var _runoff: CPUParticles3D
var _puddle: MeshInstance3D
var _puddle_mat: StandardMaterial3D
var _gurgle: AudioStreamPlayer3D
var _wet := 0.0               # how big the wet patch is, 0..1
var _flow := 0.0              # how much water's running to the drain, 0..1
var _drain := Wash.BAY_DRAIN
var firing := false


func _ready() -> void:
	# A few fine droplets flicked off, short-lived and faint: the water mostly goes to mist, not
	# drops raining down (Simon: more mist, fewer drips).
	_splash = _particles(36, 0.14, false)
	_splash.spread = 70.0
	_splash.flatness = 0.3
	_splash.initial_velocity_min = 1.2
	_splash.initial_velocity_max = 2.8
	_splash.gravity = Vector3(0.0, -9.8, 0.0)
	_splash.damping_min = 3.0
	_splash.damping_max = 6.0
	_splash.scale_amount_min = 0.3
	_splash.scale_amount_max = 0.6
	_splash.particle_flag_align_y = true
	var drop := CylinderMesh.new()
	drop.top_radius = 0.0008
	drop.bottom_radius = 0.0012
	drop.height = 0.025
	drop.radial_segments = 4
	drop.rings = 1
	drop.material = _water_mat(Color(0.85, 0.93, 1.0, 0.4), false)
	_splash.mesh = drop
	_splash.color_ramp = _fade(Color(1, 1, 1, 0.5))
	add_child(_splash)
	# A thick cloud of fine mist billowing off where it lands and hanging there, drifting on the
	# air and swelling as it thins: lots of soft, faint puffs (on the GPU), not blobs.
	_mist = WaterSpray.make_mist(MIST_AMOUNT, 2.6, Vector2(0.05, 0.16), 2.4, 0.09)
	var mp := _mist.process_material as ParticleProcessMaterial
	mp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mp.emission_sphere_radius = 0.12
	mp.spread = 75.0
	mp.initial_velocity_min = 0.5
	mp.initial_velocity_max = 2.6
	mp.damping_min = 1.8
	mp.damping_max = 3.5
	mp.gravity = Vector3(0.0, 0.1, 0.0)
	mp.turbulence_enabled = true
	mp.turbulence_noise_strength = 0.8
	mp.turbulence_noise_scale = 2.5
	mp.turbulence_influence_min = 0.03
	mp.turbulence_influence_max = 0.1
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
		_splash.direction = (back * 0.3 + n * 0.8).normalized()
		_mist.global_position = at + n * 0.08
		(_mist.process_material as ParticleProcessMaterial).direction = (n + Vector3.UP * 0.6).normalized()
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
