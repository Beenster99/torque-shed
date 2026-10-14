class_name Daylight
extends Node
## Time of day: moves the sun across the sky, warms it at dawn and dusk, hands over to a dim
## blue moon at night, and darkens the sky (with stars), fog and ambient light to match.
## The World makes one; find it in group "daylight" or through Daylight.current, or just read
## World.time_of_day() and World.darkness().
##
## Solo or hosting, the Settings drive it. On a co-op client the host's clock wins: the host
## broadcasts its time every second through Net and clients ease toward it.

## Emitted when darkness() moves by a hundredth or more (and on any jump in time).
signal darkness_changed(value: float)

const DAY_LENGTHS := [20, 60, 120, 180, 240, 360]   # minutes of real time per 24 h, for the settings menu (up to 6 hours)
const SYNC_INTERVAL := 1.0
const TILT := 0.61                      # how far south the sun's path leans (35 degrees)
const SUN_ENERGY := 1.25
const MOON_ENERGY := 0.16
## Volumetric fog density by day (the world's own light haze) and at night, for headlights in the air.
const DAY_FOG := 0.006
const NIGHT_FOG := 0.009
## Depth fog: the world's light haze, and how much fog weather and rain add to it.
const WORLD_FOG := 0.0007
const FOG_WEATHER := 0.03
const RAIN_HAZE := 0.004
## Lights in this group with a "night_energy" meta are switched on at dusk at that energy.
const NIGHT_LIGHTS := "night_lights"

static var current: Daylight

var hours := 9.0
## 0 in full daylight .. 1 at night.
var dark := 0.0
## Unit vector from the ground toward the sun (below the horizon at night).
var sun_dir := Vector3.UP
## 0 by day, ramps to 1 as dusk falls: how strongly lamps should be on.
var lamps := 0.0

var _env: Environment
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _cloud_q := {}
var _noise_tex: NoiseTexture2D
## The exposure and glow for the time of day; Lighting adds eye adaptation on top of these
## (without a Lighting they go straight onto the environment).
var exposure := 1.0
var glow_intensity := 0.4
var glow_bloom := 0.05
var _sky_hours := -100.0
var _sky_weather := Vector3(-1.0, -1.0, -1.0)
var _signalled_dark := -1.0
var _host_hours := 0.0
var _host_rate := 0.0
var _synced := false
var _was_client := false
var _send_timer := 0.0


static func time_of_day() -> float:
	return current.hours if current else 12.0


static func darkness() -> float:
	return current.dark if current else 0.0


## "18:45" for menus.
static func clock_text(h: float) -> String:
	var mins := int(roundf(wrapf(h, 0.0, 24.0) * 60.0)) % (24 * 60)
	return "%02d:%02d" % [mins / 60, mins % 60]


## `env` gets a new sky; `sun` is moved and coloured every frame.
func setup(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun
	_sky_mat = ShaderMaterial.new()
	set_cloud_quality(Lighting.option("gfx_clouds"))
	if _env.sky == null:
		_env.sky = Sky.new()
	_env.sky.sky_material = _sky_mat
	# Sky uniforms change slowly, so spread the reflection and ambient refresh over frames.
	_env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.72, 1.0)
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_moon.directional_shadow_max_distance = 120.0
	_moon.light_angular_distance = 0.5
	_moon.light_volumetric_fog_energy = 0.6
	_moon.visible = false
	add_child(_moon)
	hours = wrapf(Settings.time_of_day, 0.0, 24.0)
	_apply(true)


func _ready() -> void:
	add_to_group("daylight")
	current = self
	Net.time_received.connect(_on_host_time)


func _exit_tree() -> void:
	if current == self:
		current = null


## Hours of game time that pass per real second (0 with the cycle switched off).
static func local_rate() -> float:
	if not Settings.day_night_cycle:
		return 0.0
	return 24.0 / (maxf(float(Settings.day_length), 1.0) * 60.0)


## True on a co-op client, where the host sets the time.
static func set_by_host() -> bool:
	return Net.is_online() and not Net.is_host()


## Jump to `h` hours (solo or host only; ignored on a client).
func set_time(h: float) -> void:
	if set_by_host():
		return
	hours = wrapf(h, 0.0, 24.0)
	Settings.time_of_day = hours
	_send_timer = 0.0
	_apply(true)


func _process(delta: float) -> void:
	if _env == null:
		return
	var client := set_by_host()
	if client and _synced:
		_host_hours = wrapf(_host_hours + _host_rate * delta, 0.0, 24.0)
		var diff := wrapf(_host_hours - hours, -12.0, 12.0)
		if absf(diff) > 0.5:
			hours = _host_hours
			_apply(true)
		else:
			hours = wrapf(hours + _host_rate * delta + diff * minf(1.0, delta * 2.0), 0.0, 24.0)
	else:
		if _was_client and not client:
			# Left a co-op session: back to our own clock.
			hours = wrapf(Settings.time_of_day, 0.0, 24.0)
			_synced = false
			_apply(true)
		hours = wrapf(hours + local_rate() * delta, 0.0, 24.0)
		if not client:
			Settings.time_of_day = hours
			if Net.is_host():
				_send_timer -= delta
				if _send_timer <= 0.0:
					_send_timer = SYNC_INTERVAL
					Net.send_time(hours, local_rate())
	_was_client = client
	_apply(false)


func _on_host_time(h: float, rate: float) -> void:
	if not set_by_host():
		return
	_host_hours = wrapf(h, 0.0, 24.0)
	_host_rate = clampf(rate, 0.0, 1.0)
	if not _synced:
		_synced = true
		hours = _host_hours
		_apply(true)


# ---------------------------------------------------------------------------- the look

## Where the sun is at `h` hours: rises in the east (+X) at 6, highest in the south (+Z) at
## noon, sets in the west at 18.
static func sun_direction(h: float) -> Vector3:
	var a := (h - 12.0) / 24.0 * TAU
	return Vector3(-sin(a), cos(a) * cos(TILT), cos(a) * sin(TILT)).normalized()


func _apply(force: bool) -> void:
	sun_dir = sun_direction(hours)
	var s := sun_dir.y
	dark = 1.0 - smoothstep(-0.24, 0.06, s)
	lamps = smoothstep(0.25, 0.6, dark)
	var light_day := clampf((s + 0.06) / 0.3, 0.0, 1.0)
	var warm := 1.0 - smoothstep(0.02, 0.42, s)
	var twilight := exp(-pow(s / 0.13, 2.0))
	# The weather (see Weather): cloud cover greys the sky and dims the sun, mist and rain thicken
	# the fog and the haze.
	var cover := Weather.cover_level()
	var mist := Weather.fog_level()
	var rain := Weather.rain_level()
	var overcast := smoothstep(0.35, 1.0, cover)
	twilight *= 1.0 - 0.7 * overcast

	# Sun: golden and low, then gone.
	_sun.visible = s > -0.06
	if _sun.visible:
		_sun.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(s) < 0.99 else Vector3.FORWARD)
		_sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.52, 0.26), warm)
		_sun.light_energy = SUN_ENERGY * pow(light_day, 0.55) * (1.0 - 0.72 * overcast) * (1.0 - 0.35 * mist)
		# Under cloud the shadows go soft and faint.
		_sun.shadow_opacity = lerpf(1.0, 0.35, maxf(overcast, mist))
	# Moon: roughly opposite the sun, cool and dim, only once the sun is down.
	var moon_dir := sun_direction(hours + 12.0).rotated(Vector3.UP, 0.35)
	_moon.visible = s <= -0.06 and moon_dir.y > -0.02
	if _moon.visible:
		_moon.basis = Basis.looking_at(-moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.FORWARD)
		_moon.light_energy = MOON_ENERGY * (1.0 - smoothstep(-0.2, -0.06, s)) * smoothstep(-0.02, 0.2, moon_dir.y) * (1.0 - 0.8 * overcast)

	# Ambient and fog: night is dark blue, not black, so the yard stays readable.
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.25, dark)
	_env.ambient_light_color = Color(0.32, 0.4, 0.62).lerp(Color(0.75, 0.55, 0.5), twilight * (1.0 - dark))
	_env.ambient_light_energy = lerpf(0.9, 0.22, dark) + 0.35 * twilight * (1.0 - dark)
	_env.ambient_light_energy *= 1.0 - 0.18 * overcast
	var fog := Color(0.7, 0.77, 0.86).lerp(Color(0.85, 0.58, 0.44), twilight * 0.6).lerp(Color(0.62, 0.65, 0.68), maxf(overcast * 0.6, mist)) \
		.lerp(Color(0.03, 0.04, 0.07), dark)
	_env.fog_light_color = fog
	# Depth fog works on every renderer: a light haze by default, thick in fog, misty in rain.
	_env.fog_density = WORLD_FOG + mist * FOG_WEATHER + rain * RAIN_HAZE
	_env.fog_sky_affect = lerpf(0.25, 0.95, maxf(mist, rain * 0.5))
	_env.fog_aerial_perspective = lerpf(0.3, 0.0, maxf(mist, rain * 0.6))
	_env.fog_light_energy = 1.0
	_env.fog_sun_scatter = 0.25 * twilight
	_env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95).lerp(Color(0.5, 0.55, 0.7), dark)
	# A touch more haze in the night air, so headlights (and the moon) show softly in it.
	_env.volumetric_fog_density = lerpf(DAY_FOG, NIGHT_FOG, dark) + mist * 0.01 + rain * 0.003
	exposure = lerpf(1.0, 1.35, dark)
	glow_intensity = lerpf(0.4, 0.75, dark)
	glow_bloom = lerpf(0.05, 0.02, dark)
	if Lighting.current == null:
		_env.tonemap_exposure = exposure
		_env.glow_intensity = glow_intensity
		_env.glow_bloom = glow_bloom

	var weather_now := Vector3(cover, mist, rain)
	if force or absf(wrapf(hours - _sky_hours, -12.0, 12.0)) > 0.01 or weather_now.distance_to(_sky_weather) > 0.01:
		_sky_hours = hours
		_sky_weather = weather_now
		_update_sky(s, moon_dir, warm, twilight, overcast, mist, rain)
	if force or absf(dark - _signalled_dark) >= 0.01:
		_signalled_dark = dark
		_update_lamps()
		darkness_changed.emit(dark)


func _update_sky(s: float, moon_dir: Vector3, warm: float, twilight: float, overcast := 0.0, mist := 0.0,
		rain := 0.0) -> void:
	var day_top := Color(0.22, 0.42, 0.75)
	var day_horizon := Color(0.68, 0.76, 0.86)
	var night_top := Color(0.01, 0.014, 0.035)
	var night_horizon := Color(0.035, 0.045, 0.085)
	# Overcast: a flat grey sky, darker in rain; fog washes it out to the fog's own grey.
	var grey := Color(0.55, 0.58, 0.62).lerp(Color(0.38, 0.4, 0.44), rain)
	day_top = day_top.lerp(grey, overcast * 0.85).lerp(Color(0.66, 0.68, 0.7), mist * 0.8)
	day_horizon = day_horizon.lerp(grey.lightened(0.12), overcast * 0.85).lerp(Color(0.7, 0.72, 0.74), mist * 0.9)
	night_top = night_top.lerp(Color(0.02, 0.022, 0.03), overcast)
	night_horizon = night_horizon.lerp(Color(0.04, 0.045, 0.055), overcast)
	var top := day_top.lerp(night_top, dark).lerp(Color(0.2, 0.22, 0.42), twilight * 0.35)
	var horizon := day_horizon.lerp(night_horizon, dark).lerp(Color(0.95, 0.56, 0.38), twilight * 0.55)
	var ground := Color(0.25, 0.27, 0.25).lerp(Color(0.012, 0.014, 0.02), dark)
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("ground_color", ground)
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.93, 0.8).lerp(Color(1.0, 0.5, 0.2), warm))
	_sky_mat.set_shader_parameter("sun_strength", smoothstep(-0.04, 0.02, s) * (1.0 - 0.95 * maxf(overcast, mist)))
	_sky_mat.set_shader_parameter("glow_color", Color(1.0, 0.45, 0.16))
	_sky_mat.set_shader_parameter("glow_strength", twilight * 1.4)
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	_sky_mat.set_shader_parameter("moon_strength", smoothstep(0.2, 0.8, dark) * (1.0 - 0.9 * overcast))
	_sky_mat.set_shader_parameter("star_strength", smoothstep(0.55, 0.95, dark) * (1.0 - overcast) * (1.0 - mist))
	_sky_mat.set_shader_parameter("cloud_cover", Weather.cover_level())
	# The raymarched clouds are lit by the sun, or by the moon once it's down; rain makes them
	# heavier and darker and the wind picks up.
	_sky_mat.set_shader_parameter("cloud_light_dir", sun_dir if s > -0.06 else moon_dir)
	_sky_mat.set_shader_parameter("cloud_rain", rain)
	_sky_mat.set_shader_parameter("wind", CloudSky.wind_for(rain))
	var cloud := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.64, 0.68), overcast * 0.7).lerp(Color(0.42, 0.44, 0.48), rain) \
		.lerp(Color(1.0, 0.7, 0.55), twilight * 0.8).lerp(Color(0.05, 0.06, 0.09), dark)
	_sky_mat.set_shader_parameter("cloud_color", cloud)
	_sky_mat.set_shader_parameter("cloud_shadow", Color(0.62, 0.68, 0.78).lerp(Color(0.32, 0.34, 0.38), overcast).lerp(Color(0.5, 0.32, 0.38), twilight * 0.8).lerp(Color(0.02, 0.025, 0.04), dark))


func _update_lamps() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(NIGHT_LIGHTS):
		if n is Light3D and n.has_meta("night_energy"):
			var full: float = n.get_meta("night_energy")
			n.light_energy = full * lamps
			n.visible = lamps > 0.01
		elif n is GeometryInstance3D and n.has_meta("night_emission"):
			var mat := (n as GeometryInstance3D).material_override as StandardMaterial3D
			if mat:
				var e: float = n.get_meta("night_emission")
				mat.emission_energy_multiplier = lerpf(0.05, e, lamps)


func _cloud_noise() -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.fractal_gain = 0.5
	n.seed = 7
	tex.noise = n
	return tex


## The sky shader at a cloud setting ("off", "low", "high"; see CloudSky.quality()). Rebuilt
## only when the quality actually changes.
func set_cloud_quality(setting: String) -> void:
	var q := CloudSky.quality(setting, Lighting.forward_plus())
	if q == _cloud_q and _sky_mat.shader != null:
		return
	_cloud_q = q
	_sky_mat.shader = CloudSky.make_shader(q)
	if _noise_tex == null:
		_noise_tex = _cloud_noise()
	_sky_mat.set_shader_parameter("cloud_noise", _noise_tex)
	if bool(q["volumetric"]):
		_sky_mat.set_shader_parameter("cloud_detail", CloudSky.detail_texture())
	if _env and _env.sky:
		_sky_hours = -100.0   # set every uniform again next frame


## The cloud quality the sky is drawn at now (see CloudSky.quality()).
func cloud_quality() -> Dictionary:
	return _cloud_q
