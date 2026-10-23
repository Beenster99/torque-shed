class_name BikeEffects
extends Node3D
## Exhaust smoke, dust thrown up off loose ground, tyre smoke from burnouts and skids, and the
## headlight beam, for a ridden bike and for other players' bikes. Lives on the bike body; feed
## it with update() every frame (and set_tyre_smoke() while the back tyre is spinning or locked).

const DUSTY := {"dirt": 1.0, "grass": 0.45, "gravel": 0.8, "sand": 1.15, "snow": 0.7}
## Alpha over a puff's life, as [offset, alpha] pairs: fade in fast, linger, thin out.
const SMOKE_PROFILE := [[0.0, 0.0], [0.07, 1.0], [0.45, 0.55], [1.0, 0.0]]
const DUST_PROFILE := [[0.0, 0.0], [0.06, 1.0], [0.3, 0.75], [0.7, 0.3], [1.0, 0.0]]
const TYRE_PROFILE := [[0.0, 0.0], [0.05, 0.9], [0.3, 1.0], [0.65, 0.5], [1.0, 0.0]]
const GRIT_PROFILE := [[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]]
const PUFF_FRAME := 64   # pixels per puff in the 2x2 atlas of soft noisy puffs

static var _puff_tex: ImageTexture
static var _mote_tex: ImageTexture

var _smoke: CPUParticles3D
var _dust: CPUParticles3D
var _grit: CPUParticles3D
var _tyre: CPUParticles3D
var _beam: SpotLight3D      # the beam's core: lights the road, never the air
var _flood: SpotLight3D     # a wide, dim, very soft flood round it: fills the edges and lights the fog
var _cone: MeshInstance3D
var _motes: CPUParticles3D   # dust drifting through the headlight beam
var _mote_shape := Vector2.ZERO   # the beam (length, radius) the motes were scattered for
const MOTES := 36
## How much the beam lights the night fog (light energy x fog energy), low and high beam. Only
## the wide soft flood lights the air, so what shows is a faint haze, not a shaft with edges.
const BEAM_FOG_LOW := 1.6
const BEAM_FOG_HIGH := 2.6
## The flood: how much wider than the core, how bright next to it, how far it reaches (as a share
## of the core's reach) and how much lower it's aimed, onto the near road and the verges. It used
## to stop at two thirds of the core's reach, which drew an arc of darkness across the road about
## 20 m ahead: now it fades out with distance long before its end, so it has no edge to show.
const FLOOD_WIDER := 26.0
const FLOOD_SHARE := 0.35
const FLOOD_REACH := 0.9
const FLOOD_DIP := 4.0
## How the core and the flood fade with distance (SpotLight3D.spot_attenuation): a real lamp's
## hot spot is aimed far up the road, so a slower fade than a bare bulb's keeps the road lit
## well ahead without the near road glaring.
const CORE_DECAY := 0.55
const FLOOD_DECAY := 1.0
## The headlight's reach (m) on dipped and main beam: a base plus so much per lumen.
const LOW_REACH := [58.0, 1.0 / 80.0]
const HIGH_REACH := [150.0, 1.0 / 15.0]
## Dipped beam (Simon: "The dipped beam needs to be more dipped"): aimed well down, so its hot
## spot lands on the road a short way ahead, and cut off sharply along a level line LOW_CUTOFF
## degrees below the horizon, as a real dipped lamp's is: nothing above it is lit, so the signs
## and trees further up the road (and oncoming drivers' eyes) stay dark. Main beam has no cut-off.
const LOW_AIM := 5.0
const LOW_CUTOFF := 1.3
## How soft the cut-off's edge is (degrees from lit to dark).
const CUTOFF_SOFT := 0.35
## How far the dipped beam's flood reaches (m): the near road and verges only.
const FLOOD_LOW_REACH := 16.0
## Cone falloff (SpotLight3D.spot_angle_attenuation): below 1 the light fades from the middle
## outwards, so there is next to nothing left at the cone's edge to show as a line.
const CORE_FALLOFF := 0.7
const FLOOD_FALLOFF := 0.35
static var _soft_tex: GradientTexture2D
static var _cutoff_tex := {}
var beam_mode := 1      # headlight switch: 0 off, 1 dipped (low), 2 main (high), 3 main with the fog lights
const BEAM_NAMES := ["off", "low beam", "high beam", "high beam and fog lights"]
var _lamp_glow: OmniLight3D
var _surface := "tarmac"
var _screech: AudioStreamPlayer3D
var _probe_timer := 0.0
var _wind_time := randf() * 100.0
var _tyre_level := 0.0
var _mark_keys: Array = []    # the skid marks' names for this bike's two tyres (made once)


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
		_beam.rotation.x = deg_to_rad(-LOW_AIM)
		_beam.spot_range = LOW_REACH[0] + lumens * LOW_REACH[1]
		_beam.spot_angle = 30.0
		_beam.spot_attenuation = CORE_DECAY
		_beam.light_energy = lumens / 300.0
		_beam.set_meta("day_energy", _beam.light_energy)
		_beam.set_meta("lumens", lumens)
		_beam.light_color = Color(1.0, 0.92, 0.78) if lumens < 2000.0 else Color(0.92, 0.96, 1.0)
		_beam.shadow_enabled = false
		# The cone's own falloff fades the pool on the road to nothing at its edge, so there is no
		# ring. (No soft round projector: its blurred spot was already under half strength two
		# thirds of the way out, so the lit pool was much narrower than the cone.) Dipped, its
		# projector is the cut-off, a level line and nothing else (see cutoff_texture).
		_beam.spot_angle_attenuation = CORE_FALLOFF
		_beam.light_projector = cutoff_texture(LOW_AIM - LOW_CUTOFF)
		add_child(_beam)
		_flood = SpotLight3D.new()
		_flood.name = "Flood"
		_flood.light_color = _beam.light_color
		_flood.shadow_enabled = false
		_flood.spot_angle_attenuation = FLOOD_FALLOFF
		_flood.spot_attenuation = FLOOD_DECAY   # fades with distance faster than the core: no long tube
		_flood.rotation.x = deg_to_rad(-FLOOD_DIP)
		_flood.light_specular = 0.2
		_beam.add_child(_flood)
		_lamp_glow = OmniLight3D.new()
		_lamp_glow.position = lamp + Vector3(0.0, 0.0, -0.12)
		_lamp_glow.omni_range = 0.8
		_lamp_glow.light_energy = 0.4
		_lamp_glow.light_color = _beam.light_color
		_lamp_glow.light_volumetric_fog_energy = 0.0   # right at the lens: it would light the air as a white ball
		add_child(_lamp_glow)
		# Light in the night air: the beam lights the volumetric fog (Forward+), soft and diffuse
		# rather than a shape; a faint stand-in glow only where there's no volumetric fog.
		_beam.light_volumetric_fog_energy = 0.0
		if not volumetric_beams():
			_cone = _make_cone(_beam.light_color)
			_beam.add_child(_cone)
		_motes = _make_motes(_beam.light_color)
		_beam.add_child(_motes)


## A soft round spot for light projectors: white in the middle, fading smoothly (no edge at
## all) to black at the rim.
static func soft_spot_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.62, 0.86, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1), Color(0.86, 0.86, 0.86), Color(0.42, 0.42, 0.42),
			Color(0.08, 0.08, 0.08), Color(0, 0, 0)])
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 128
		_soft_tex.height = 128
	return _soft_tex


## The dipped beam's cut-off as a light projector for a spot aimed `below` degrees under the
## cut-off line: lit beneath the line, dark above it, with a CUTOFF_SOFT edge between. (A spot
## light's projector is laid over its cone as tan(angle off the middle / 2), whatever the cone's
## size, so the line sits at the same place in the picture for any spread.)
static func cutoff_texture(below: float) -> ImageTexture:
	var key := snappedf(below, 0.01)
	if _cutoff_tex.has(key):
		return _cutoff_tex[key]
	const SIZE := 512
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		# The angle above the middle of the cone this row of the picture shows (row 0 is the top).
		var up := rad_to_deg(2.0 * atan((0.5 - (y + 0.5) / SIZE) * 2.0))
		var lit := 1.0 - smoothstep(below - CUTOFF_SOFT * 0.5, below + CUTOFF_SOFT * 0.5, up)
		img.fill_rect(Rect2i(0, y, SIZE, 1), Color(lit, lit, lit))
	var tex := ImageTexture.create_from_image(img)
	_cutoff_tex[key] = tex
	return tex


## Whether the headlight shows as light scattered in the night air through volumetric fog
## (Forward+ with the quality setting on). Otherwise a faint soft glow stands in for it.
static func volumetric_beams() -> bool:
	return Lighting.forward_plus() and str(Lighting.option("gfx_volumetrics")) != "off"


## The stand-in for the beam where there's no volumetric fog (the compatibility renderer): a
## very faint, soft glow along the beam with no hard edge, brightest at the lamp and gone
## well before the end. Just enough to hint at the light in the air.
func _make_cone(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 1.0
	cyl.height = 10.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 24
	cyl.rings = 4
	mi.mesh = cyl
	mi.rotation.x = PI * 0.5   # the narrow top (+Y) turns to +Z, back at the lamp
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	# Diffuse: the glow falls away smoothly towards the rim of the cone (seen edge-on it's gone),
	# along its length and close to the eye, so there's never a visible surface.
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.02;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);   // 0 at the lamp, 1 at the far end
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Gone right at the silhouette, but full strength by a modest angle, so it still shows
	// from behind the bike, looking down the beam.
	float a = strength * pow(1.0 - along, 2.4) * smoothstep(0.0, 0.35, facing);
	// Soften where the cone meets the road or anything else, and right in front of the eye.
	float scene = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene);
#endif
	vec4 p = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float gap = -p.z / p.w + VERTEX.z;
	a *= smoothstep(0.0, 1.5, gap) * smoothstep(0.5, 3.0, -VERTEX.z);
	ALBEDO = tint.rgb * a;
	ALPHA = 1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", color)
	mi.material_override = m
	return mi


## Dust motes in the beam: tiny glints that only show where the light falls on them. They are
## scattered through the cone itself (see _scatter_motes), drift slowly, and stream back past
## the lamp as the bike moves, like dust in a torch beam. Cheap: one small CPU emitter a bike.
func _make_motes(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = MOTES
	p.lifetime = 2.6
	p.local_coords = true
	p.emitting = false
	p.randomness = 0.8
	p.lifetime_randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.direction = Vector3(0.0, 0.0, 1.0)
	p.spread = 25.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.15
	p.gravity = Vector3(0.0, -0.02, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r, color.g, color.b, 0.0)
	m.albedo_texture = mote_texture()
	m.disable_receive_shadows = true
	m.no_depth_test = false
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Points to start motes from, inside a cone `length` long (out along -Z from the lamp) that
## widens to `radius`, bunched towards the lamp where the beam is brightest.
func _scatter_motes(length: float, radius: float) -> void:
	var pts := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 160:
		var along := pow(rng.randf(), 1.6)
		var r := radius * along * sqrt(rng.randf()) * 0.9
		var a := rng.randf() * TAU
		pts.append(Vector3(cos(a) * r, sin(a) * r, -0.25 - along * length))
	_motes.emission_points = pts
	_mote_shape = Vector2(length, radius)


## A soft round glint for a dust mote.
static func mote_texture() -> ImageTexture:
	if _mote_tex:
		return _mote_tex
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_mote_tex = ImageTexture.create_from_image(img)
	return _mote_tex


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
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("bike_fx", pt)


func _process_body(delta: float) -> void:
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
		var dust_col: Color = AdventureSurface.DUST_COLOR.get(surface, Color(0.62, 0.5, 0.36) if surface == "dirt" else Color(0.55, 0.5, 0.38))
		_tint(_dust.color_ramp, DUST_PROFILE, dust_col,
			clampf(0.25 + 0.5 * kick, 0.0, 0.8) * dusty)
		_dust.initial_velocity_max = 1.5 + 3.0 * kick
	_grit.emitting = _dust.emitting and kick * dusty > 0.35
	if _beam:
		_beam.visible = engine_on and beam_mode > 0
		# The eye adjusts at night: the same lamp throws a much brighter pool on the road.
		var night := World.darkness()
		var high := beam_mode >= 2
		var lumens: float = _beam.get_meta("lumens")
		_beam.light_energy = float(_beam.get_meta("day_energy")) * (1.0 + 3.0 * night) * (3.0 if high else 1.7)
		_beam.spot_angle = 20.0 if high else lerpf(30.0, 36.0, night)
		var reach: Array = HIGH_REACH if high else LOW_REACH
		_beam.spot_range = float(reach[0]) + lumens * float(reach[1])
		# Dipped, the hot spot lands some 10 m up the road and nothing shines above the cut-off;
		# main beam goes out to the horizon.
		_beam.rotation.x = deg_to_rad(-0.6 if high else -LOW_AIM)
		var cut: Texture2D = null if high else cutoff_texture(LOW_AIM - LOW_CUTOFF)
		if _beam.light_projector != cut:
			_beam.light_projector = cut
		_lamp_glow.visible = engine_on and beam_mode > 0
		_lamp_glow.light_energy = 0.9 if high else 0.5
		# The core lights only the road; the flood, wide, dim and fading from its middle, fills
		# round it and is the only light the fog picks up: the same faint amount whatever the
		# lamp's power, a little more on high beam, nothing by day.
		_beam.light_volumetric_fog_energy = 0.0
		_flood.light_energy = _beam.light_energy * FLOOD_SHARE
		# Wide enough to light the hedges, walls, trees and signs either side.
		_flood.spot_angle = minf(_beam.spot_angle + FLOOD_WIDER, 62.0)
		# Dipped, it only fills the near road and verges: it stops short (it has no cut-off of its
		# own), so it never lights the trees and signs further on.
		_flood.spot_range = _beam.spot_range * FLOOD_REACH if high else FLOOD_LOW_REACH
		_flood.light_volumetric_fog_energy = night * (BEAM_FOG_HIGH if high else BEAM_FOG_LOW) / maxf(_flood.light_energy, 1.0)
		if _cone == null and not volumetric_beams() and night > 0.2:
			# Volumetric fog switched off while riding: the stand-in glow takes over.
			_cone = _make_cone(_beam.light_color)
			_beam.add_child(_cone)
		if _cone:
			var length := minf(_beam.spot_range * 0.5, 22.0)
			var radius := length * tan(deg_to_rad(_beam.spot_angle))
			var cyl := _cone.mesh as CylinderMesh
			cyl.height = length
			cyl.bottom_radius = radius
			_cone.position = Vector3(0.0, 0.0, -length * 0.5)
			_cone.visible = night > 0.2 and not volumetric_beams()
			(_cone.material_override as ShaderMaterial).set_shader_parameter("strength", beam_glow(night, high))
		if _motes:
			# Dust only shows up against the dark: barely there by day, a glittering beam at night.
			var length := minf(_beam.spot_range * 0.45, 18.0)
			var radius := length * tan(deg_to_rad(_beam.spot_angle))
			if absf(_mote_shape.x - length) > 0.5 or absf(_mote_shape.y - radius) > 0.2:
				_scatter_motes(length, radius)
			var glow := (0.08 + 0.92 * night) * (1.3 if high else 1.0)
			_motes.emitting = _beam.visible and night > 0.15
			var mm := (_motes.mesh as QuadMesh).material as StandardMaterial3D
			mm.albedo_color.a = clampf(glow * 0.35, 0.0, 1.0)
			# Riding along, the air streams back through the beam towards the lamp.
			var rush := minf(absf(speed), 30.0)
			_motes.initial_velocity_max = 0.15 + rush * 0.5
			_motes.initial_velocity_min = 0.02 + rush * 0.35
			_motes.lifetime = clampf(2.6 - rush * 0.06, 0.6, 2.6)
			_motes.spread = 25.0 if rush < 2.0 else 6.0


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


## Tyre screech and rubber on the road while the ridden bike's tyres skid, and a dark patch
## smeared where the back tyre spins on the spot in a burnout.
func update_skids(bike: Bike) -> void:
	var marks := SkidMarks.shared(get_tree())
	var loudest := 0.0
	if _mark_keys.is_empty():
		_mark_keys = ["%d_0" % bike.get_instance_id(), "%d_1" % bike.get_instance_id()]
	for i in bike.wheels.size():
		var w: Dictionary = bike.wheels[i]
		var hard := 0.0
		if w["contact"] and absf(bike.speed) > 2.0 and SkidMarks.RUBBER.has(w["surface"]):
			hard = clampf((float(w["slip"]) - Bike.SKID_SLIP) / 0.5, 0.0, 1.0)
		var width: float = bike.build.front_tyre_width if w["is_front"] else bike.build.rear_tyre_width
		var key: String = _mark_keys[mini(i, 1)]
		if not w["is_front"] and bike.burnout > 0.05 and w["contact"]:
			# Lit up: the spinning tyre smears rubber where it sits.
			marks.scrub(key, w.get("contact_pos", Vector3.ZERO), w.get("normal", Vector3.UP), -bike.global_basis.z,
				width, maxf(bike.burnout, hard), str(w["surface"]), bike.get_physics_process_delta_time())
		else:
			marks.mark(key, w.get("contact_pos", Vector3.ZERO), w.get("normal", Vector3.UP), width, hard, str(w["surface"]))
		if w["surface"] == "tarmac":
			loudest = maxf(loudest, hard)
			# Lighting the back tyre up on the spot squeals too.
			if not w["is_front"] and w["contact"]:
				loudest = maxf(loudest, bike.burnout * 0.8)
	bike.skid = loudest
	set_screech(loudest)


## How loud a long slide gets: the screech settles to this share of its level once the tyre
## has been sliding a while, so a held skid doesn't drown everything.
const SCREECH_SETTLE := 0.45
## How loud the bark is when a tyre lets go, at the softest and the sharpest break of grip.
const CHIRP_MIN_DB := -6.0
const CHIRP_MAX_DB := 6.0
var _skid_level := 0.0
var _skid_held := 0.0       # seconds the tyre has been sliding
var _skid_bite := 0.0       # 1 just as grip breaks, fading: the moment it lets go is loudest
var _skid_slow := 0.0       # the level eased over a fifth of a second
var _onset := -1.0          # seconds since grip started to go (-1: not letting go)
var _onset_peak := 0.0
## How long after grip starts to go the bark comes: long enough to tell a snap from a slow slide.
const CHIRP_WINDOW := 0.06
var _chirp_wait := 0.0
var _chirps := 0
var last_chirp := 0.0        # how hard the last bark was, 0..1


## The tyre squeal on its own, 0 (none) .. 1 (full lock-up), for other players' bikes too.
## The moment a tyre loses grip it barks (a sharp chirp, louder the faster grip goes) and the
## squeal starts loud; a slide that goes on settles to a quieter screech.
func set_screech(level: float) -> void:
	if _screech == null:
		_screech = Sfx.make_loop_player(self)
		_screech.max_distance = 80.0
		_screech.unit_size = 10.0
	var dt := get_physics_process_delta_time() if Engine.is_in_physics_frame() else get_process_delta_time()
	dt = clampf(dt, 0.001, 0.1)
	level = clampf(level, 0.0, 1.0)
	_chirp_wait = maxf(_chirp_wait - dt, 0.0)
	# Grip breaking: the level climbs from (nearly) nothing. How far it gets in the first
	# CHIRP_WINDOW says how suddenly the tyre let go, and sets how loud it barks.
	if _onset < 0.0 and level > 0.08 and _skid_level < 0.06 and _chirp_wait <= 0.0:
		_onset = 0.0
		_onset_peak = 0.0
	if _onset >= 0.0:
		_onset += dt
		_onset_peak = maxf(_onset_peak, level)
		if _onset >= CHIRP_WINDOW or level < 0.02:
			if _onset_peak > 0.15:
				chirp(_onset_peak)
			_onset = -1.0
	elif level - _skid_slow > 0.45 and _chirp_wait <= 0.0:
		# Already sliding and it suddenly lets go much more (the back stepping right out).
		chirp(level - _skid_slow)
	_skid_slow = lerpf(_skid_slow, level, 1.0 - exp(-dt / 0.2))
	if level > 0.02:
		_skid_held += dt
	else:
		_skid_held = 0.0
	_skid_bite = maxf(_skid_bite - dt / 0.5, 0.0)
	_skid_level = level
	if level > 0.02:
		Sfx.set_loop(_screech, "screech")
		_screech.volume_db = linear_to_db(screech_gain(level, _skid_held, _skid_bite))
		_screech.pitch_scale = 0.9 + level * 0.25 + _skid_bite * 0.08
	else:
		Sfx.set_loop(_screech, "")


## How loud the sliding squeal is (linear gain) at `level` after `held` seconds of sliding,
## with `bite` (1 .. 0) just after grip broke.
static func screech_gain(level: float, held: float, bite: float) -> float:
	var settle := lerpf(1.0, SCREECH_SETTLE, smoothstep(0.25, 1.6, held))
	return clampf((0.14 + 0.42 * level) * settle + 0.35 * bite * level, 0.0, 0.9)


## The bark of a tyre letting go: `strength` 0 (just) .. 1 (snapped loose all at once).
func chirp(strength: float) -> void:
	_chirp_wait = 0.35
	_skid_bite = 1.0
	_chirps += 1
	last_chirp = clampf(strength, 0.0, 1.0)
	if is_inside_tree():
		Sfx.play_at("chirp", global_position, lerpf(CHIRP_MIN_DB, CHIRP_MAX_DB, clampf(strength, 0.0, 1.0)), self)


## How many times a tyre has barked as it lost grip (for tests).
func chirp_count() -> int:
	return _chirps


func screeching() -> bool:
	return _screech != null and _screech.playing


func smoke_emitting() -> bool:
	return _smoke != null and _smoke.emitting


func dust_emitting() -> bool:
	return _dust != null and _dust.emitting


func light_on() -> bool:
	return _beam != null and _beam.visible


## How strong the stand-in glow is (no volumetric fog): faint, and only after dusk.
static func beam_glow(night: float, high: bool) -> float:
	return 0.07 * smoothstep(0.2, 1.0, night) * (1.4 if high else 1.0)


## How brightly the beam is lighting the night fog right now (light energy x fog energy).
func beam_fog() -> float:
	if _beam == null or not _beam.visible:
		return 0.0
	return _beam.light_energy * _beam.light_volumetric_fog_energy + _flood.light_energy * _flood.light_volumetric_fog_energy


## Whether dust motes are drifting through the beam (at night, with the headlight on).
func motes_showing() -> bool:
	return _motes != null and _motes.emitting
