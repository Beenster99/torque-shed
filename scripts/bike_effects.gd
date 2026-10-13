class_name BikeEffects
extends Node3D
## Exhaust smoke, dust thrown up off loose ground, tyre smoke from burnouts and skids, and the
## headlight beam, for a ridden bike and for other players' bikes. Lives on the bike body; feed
## it with update() every frame (and set_tyre_smoke() while the back tyre is spinning or locked).

const DUSTY := {"dirt": 1.0, "grass": 0.45}
## Alpha over a puff's life, as [offset, alpha] pairs: fade in fast, linger, thin out.
const SMOKE_PROFILE := [[0.0, 0.0], [0.07, 1.0], [0.45, 0.55], [1.0, 0.0]]
const DUST_PROFILE := [[0.0, 0.0], [0.06, 1.0], [0.3, 0.75], [0.7, 0.3], [1.0, 0.0]]
const TYRE_PROFILE := [[0.0, 0.0], [0.05, 0.9], [0.3, 1.0], [0.65, 0.5], [1.0, 0.0]]
const GRIT_PROFILE := [[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]]
const PUFF_FRAME := 64   # pixels per puff in the 2x2 atlas of soft noisy puffs

static var _puff_tex: ImageTexture

var _smoke: CPUParticles3D
var _dust: CPUParticles3D
var _grit: CPUParticles3D
var _tyre: CPUParticles3D
var _beam: SpotLight3D
var _lamp_glow: OmniLight3D
var _surface := "tarmac"
var _screech: AudioStreamPlayer3D
var _probe_timer := 0.0
var _wind_time := randf() * 100.0
var _tyre_level := 0.0


## `exhaust` is the tailpipe tip and `rear_contact` where the back tyre meets the ground, both
## in the bike's own space. `lamp` is where the headlight sits; `lumens` 0 means no headlight.
func setup(exhaust: Vector3, rear_contact: Vector3, lamp: Vector3, lumens: float) -> void:
	# Exhaust: small wisps that leave the pipe quickly, slow, swirl and spread as they rise.
	_smoke = _particles(44, 1.9, Color(0.55, 0.55, 0.57))
	_smoke.position = exhaust
	_smoke.direction = Vector3(0.0, 0.25, 1.0)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.2
	_smoke.damping_min = 0.6
	_smoke.damping_max = 1.4
	_smoke.gravity = Vector3(0.0, 0.32, 0.0)
	_smoke.tangential_accel_min = -0.4
	_smoke.tangential_accel_max = 0.4
	_smoke.scale_amount_min = 0.1
	_smoke.scale_amount_max = 0.18
	_smoke.scale_amount_curve = _grow_curve(5.5)
	_smoke.color_ramp = _ramp(SMOKE_PROFILE, Color(0.9, 0.9, 0.92), 0.3)
	_smoke.color_initial_ramp = _variety(0.82, 1.0)
	# Dust: thrown up and back, slowed hard by the air so it billows, then sinks and settles.
	_dust = _particles(90, 2.8, Color(1.0, 1.0, 1.0))
	_dust.position = rear_contact + Vector3(0.0, 0.1, 0.18)
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 0.15
	_dust.direction = Vector3(0.0, 0.7, 1.0)
	_dust.spread = 38.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 3.5
	_dust.damping_min = 2.5
	_dust.damping_max = 4.0
	_dust.gravity = Vector3(0.0, -0.35, 0.0)
	_dust.tangential_accel_min = -0.8
	_dust.tangential_accel_max = 0.8
	_dust.scale_amount_min = 0.3
	_dust.scale_amount_max = 0.55
	_dust.scale_amount_curve = _grow_curve(5.0)
	_dust.color_ramp = _ramp(DUST_PROFILE, Color(1, 1, 1), 0.6)
	_dust.color_initial_ramp = _variety(0.8, 1.05)
	# Grit: little clods flicked off the knobbles that fall straight back down.
	_grit = _particles(28, 0.7, Color(0.33, 0.25, 0.17))
	_grit.position = _dust.position
	_grit.direction = Vector3(0.0, 1.0, 1.0)
	_grit.spread = 25.0
	_grit.initial_velocity_min = 2.0
	_grit.initial_velocity_max = 4.5
	_grit.gravity = Vector3(0.0, -9.8, 0.0)
	_grit.scale_amount_min = 0.025
	_grit.scale_amount_max = 0.05
	_grit.color_ramp = _ramp(GRIT_PROFILE, Color(1, 1, 1), 0.95)
	_make_tyre_smoke()
	_tyre.position = rear_contact
	if lumens > 0.0:
		_beam = SpotLight3D.new()
		_beam.position = lamp + Vector3(0.0, 0.0, -0.08)
		_beam.rotation.x = deg_to_rad(-4.0)
		_beam.spot_range = 18.0 + lumens / 100.0
		_beam.spot_angle = 24.0
		_beam.light_energy = lumens / 450.0
		_beam.set_meta("day_energy", _beam.light_energy)
		_beam.light_color = Color(1.0, 0.92, 0.78) if lumens < 2000.0 else Color(0.92, 0.96, 1.0)
		_beam.shadow_enabled = false
		add_child(_beam)
		_lamp_glow = OmniLight3D.new()
		_lamp_glow.position = lamp + Vector3(0.0, 0.0, -0.12)
		_lamp_glow.omni_range = 0.8
		_lamp_glow.light_energy = 0.4
		_lamp_glow.light_color = _beam.light_color
		add_child(_lamp_glow)


## Burnout and skid smoke: thick white-grey clouds that roll off the back tyre and hang in the
## air behind the bike.
func _make_tyre_smoke() -> void:
	if _tyre:
		return
	_tyre = _particles(120, 3.4, Color(0.9, 0.9, 0.9))
	_tyre.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_tyre.emission_sphere_radius = 0.18
	_tyre.direction = Vector3(0.0, 0.55, 1.0)
	_tyre.spread = 50.0
	_tyre.initial_velocity_min = 0.4
	_tyre.initial_velocity_max = 1.6
	_tyre.damping_min = 0.7
	_tyre.damping_max = 1.4
	_tyre.gravity = Vector3(0.0, 0.28, 0.0)
	_tyre.tangential_accel_min = -1.0
	_tyre.tangential_accel_max = 1.0
	_tyre.angular_velocity_min = -25.0
	_tyre.angular_velocity_max = 25.0
	_tyre.scale_amount_min = 0.35
	_tyre.scale_amount_max = 0.6
	_tyre.scale_amount_curve = _grow_curve(7.0)
	_tyre.color_ramp = _ramp(TYRE_PROFILE, Color(0.93, 0.93, 0.94), 0.6)
	_tyre.color_initial_ramp = _variety(0.78, 1.0)


func _particles(amount: int, life: float, tint: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.randomness = 0.6
	p.lifetime_randomness = 0.35
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _puff_material(tint)
	p.mesh = quad
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	# Each puff picks one of the four shapes in the atlas.
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	add_child(p)
	return p


## A soft, ragged billboard puff that takes the particle colour, fading where it meets the
## ground or a wall instead of cutting a hard line.
func _puff_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # or every puff draws at the full quad size
	m.particles_anim_h_frames = 2
	m.particles_anim_v_frames = 2
	m.particles_anim_loop = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	# Lit, but light wraps round and shines through from behind, the way it does through real
	# smoke and dust, so a puff between you and the sun glows instead of going black.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.75, 0.72, 0.68)
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.35
	m.albedo_texture = puff_texture()
	return m


## Four soft noisy puffs in a 2x2 atlas, made once and shared by every bike.
static func puff_texture() -> ImageTexture:
	if _puff_tex:
		return _puff_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.07
	n.fractal_octaves = 4
	n.fractal_gain = 0.55
	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.035
	warp.seed = 99
	var size := PUFF_FRAME * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := PUFF_FRAME * 0.5
	for frame in 4:
		var ox := (frame % 2) * PUFF_FRAME
		var oy := (frame / 2) * PUFF_FRAME
		var seed_off := frame * 257.0
		for y in PUFF_FRAME:
			for x in PUFF_FRAME:
				var dx := (x + 0.5 - half) / half
				var dy := (y + 0.5 - half) / half
				# A ragged edge: the radius wobbles with low-frequency noise.
				var r := sqrt(dx * dx + dy * dy) + warp.get_noise_2d(x + seed_off, y) * 0.35
				var body := 1.0 - smoothstep(0.25, 0.95, r)
				var detail := n.get_noise_2d(x + seed_off, y + seed_off) * 0.5 + 0.5
				var a := clampf(body * (0.35 + 0.9 * detail), 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				# Lighter on top, darker underneath and in the folds, for a bit of volume.
				var shade := clampf(0.78 + 0.22 * detail - dy * 0.1, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


## Ease-out growth: puffs swell fast as they leave, then spread slowly.
func _grow_curve(to: float) -> Curve:
	var c := Curve.new()
	c.max_value = to
	c.add_point(Vector2(0.0, 1.0), 0.0, (to - 1.0) * 2.2)
	c.add_point(Vector2(0.45, 1.0 + (to - 1.0) * 0.72))
	c.add_point(Vector2(1.0, to), (to - 1.0) * 0.4, 0.0)
	return c


func _ramp(profile: Array, color: Color, alpha: float) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for p in profile:
		offsets.append(float(p[0]))
		colors.append(Color(color.r, color.g, color.b, alpha * float(p[1])))
	g.offsets = offsets
	g.colors = colors
	return g


## Recolour a ramp made by _ramp, keeping its alpha profile.
func _tint(g: Gradient, profile: Array, color: Color, alpha: float) -> void:
	for i in profile.size():
		g.set_color(i, Color(color.r, color.g, color.b, alpha * float(profile[i][1])))


## Per-puff brightness variety, so a cloud isn't one flat grey.
func _variety(lo: float, hi: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(lo, lo, lo, 1.0))
	g.set_color(1, Color(minf(hi, 1.0), minf(hi, 1.0), minf(hi * 0.98, 1.0), 1.0))
	return g


## A gentle breeze that wanders, so smoke and dust drift instead of rising in a straight column.
func _process(delta: float) -> void:
	if _smoke == null and _tyre == null:
		return
	_wind_time += delta
	var t := _wind_time
	var wind := Vector3(0.22 + sin(t * 0.37) * 0.2 + sin(t * 1.7) * 0.06, sin(t * 0.9) * 0.04,
		0.08 + cos(t * 0.29) * 0.18 + cos(t * 1.3) * 0.05)
	if _smoke:
		_smoke.gravity = Vector3(0.0, 0.32, 0.0) + wind
		_dust.gravity = Vector3(0.0, -0.35, 0.0) + wind * 0.8
	if _tyre:
		_tyre.gravity = Vector3(0.0, 0.28, 0.0) + wind * 1.2


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
	var grey := lerpf(0.9, 0.32, dark)
	_tint(_smoke.color_ramp, SMOKE_PROFILE, Color(grey, grey, grey + 0.02),
		lerpf(0.16, 0.6, clampf(throttle * 0.7 + dark * 0.6, 0.0, 1.0)))
	_smoke.initial_velocity_max = 1.2 + throttle * 2.0
	var dusty := float(DUSTY.get(surface, 0.0))
	var kick := clampf((absf(speed) - 2.0) / 12.0, 0.0, 1.0) + slip
	_dust.emitting = rear_contact and dusty > 0.0 and kick > 0.05
	if _dust.emitting:
		_tint(_dust.color_ramp, DUST_PROFILE, Color(0.62, 0.5, 0.36) if surface == "dirt" else Color(0.55, 0.5, 0.38),
			clampf(0.25 + 0.5 * kick, 0.0, 0.8) * dusty)
		_dust.initial_velocity_max = 1.5 + 3.0 * kick
	_grit.emitting = _dust.emitting and kick * dusty > 0.35
	if _beam:
		_beam.visible = engine_on
		# The eye adjusts at night: the same lamp throws a much brighter pool on the road.
		var night := World.darkness()
		_beam.light_energy = float(_beam.get_meta("day_energy")) * (1.0 + 3.0 * night)
		_beam.spot_angle = lerpf(24.0, 30.0, night)
		_lamp_glow.visible = engine_on


## Thick tyre smoke from a burnout or skid: `level` 0 (none) .. 1 (full cloud), billowing from
## `at_local`, the rear tyre's contact patch in the bike's own space. Call it every frame.
func set_tyre_smoke(level: float, at_local: Vector3) -> void:
	_make_tyre_smoke()
	level = clampf(level, 0.0, 1.0)
	# Ease in so a flicker of wheelspin doesn't pop a full cloud, but cut quickly when it stops.
	_tyre_level = lerpf(_tyre_level, level, 0.35 if level > _tyre_level else 0.6)
	_tyre.position = at_local + Vector3(0.0, 0.12, 0.1)
	_tyre.emitting = _tyre_level > 0.03
	if _tyre.emitting:
		_tint(_tyre.color_ramp, TYRE_PROFILE, Color(0.93, 0.93, 0.94), lerpf(0.22, 0.7, _tyre_level))
		_tyre.initial_velocity_max = 0.7 + 1.8 * _tyre_level
		_tyre.scale_amount_max = 0.42 + 0.35 * _tyre_level
		_tyre.emission_sphere_radius = 0.12 + 0.12 * _tyre_level


func tyre_smoke_emitting() -> bool:
	return _tyre != null and _tyre.emitting


func _probe_surface() -> String:
	if not is_inside_tree():
		return "tarmac"
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
		return str((hit["collider"] as Object).get_meta("surface"))
	return "grass" if hit else "tarmac"


## Tyre screech and rubber on the road while the ridden bike's tyres skid.
func update_skids(bike: Bike) -> void:
	var marks := SkidMarks.shared(get_tree())
	var loudest := 0.0
	for i in bike.wheels.size():
		var w: Dictionary = bike.wheels[i]
		var hard := 0.0
		if w["contact"] and absf(bike.speed) > 2.0 and w["surface"] in ["tarmac", "dirt"]:
			hard = clampf((float(w["slip"]) - Bike.SKID_SLIP) / 0.5, 0.0, 1.0)
		var width: float = bike.build.front_tyre_width if w["is_front"] else bike.build.rear_tyre_width
		marks.mark("%d_%d" % [bike.get_instance_id(), i], w.get("contact_pos", Vector3.ZERO), w.get("normal", Vector3.UP),
			width, hard, str(w["surface"]))
		if w["surface"] == "tarmac":
			loudest = maxf(loudest, hard)
	bike.skid = loudest
	set_screech(loudest)


## The tyre squeal on its own, 0 (none) .. 1 (full lock-up), for other players' bikes too.
func set_screech(level: float) -> void:
	if _screech == null:
		_screech = Sfx.make_loop_player(self)
		_screech.max_distance = 80.0
		_screech.unit_size = 10.0
	if level > 0.02:
		Sfx.set_loop(_screech, "screech")
		_screech.volume_db = linear_to_db(clampf(0.3 + level * 0.9, 0.0, 1.2))
		_screech.pitch_scale = 0.9 + level * 0.25
	else:
		Sfx.set_loop(_screech, "")


func screeching() -> bool:
	return _screech != null and _screech.playing


func smoke_emitting() -> bool:
	return _smoke != null and _smoke.emitting


func dust_emitting() -> bool:
	return _dust != null and _dust.emitting


func light_on() -> bool:
	return _beam != null and _beam.visible
