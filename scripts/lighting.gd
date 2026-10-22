class_name Lighting
extends Node
## The lighting quality: turns the Graphics settings (Settings.gfx_*) into the environment's
## global illumination (SDFGI or the lighter SSIL), screen-space reflections and ambient
## occlusion, glow, volumetric fog, the cloud sky's quality and the shadows; tunes every light in
## the world (how much it lights the fog, whether it casts shadows at this quality); marks which
## meshes take part in global illumination; fills the shed with drifting dust and the paint shop
## with overspray haze (fog volumes, Forward+ only); and lets your eyes adjust when you walk
## from the bright yard into a dark room.
##
## The World makes one (World/Lighting, or Lighting.current). It re-applies itself when
## Settings emits graphics_changed (when it has that signal), and also notices any change to the
## settings by itself twice a second. On the compatibility renderer the Forward+-only features
## are simply left out: the sky keeps its flat clouds and the rooms their plain look.

## The settings it reads, with what they are when a settings file doesn't have them.
const DEFAULTS := {"gfx_gi": "sdfgi", "gfx_volumetrics": "high", "gfx_clouds": "high", "gfx_ssr": true,
	"gfx_ssao": true, "gfx_glow": true, "gfx_shadows": "high", "gfx_draw_distance": 1.0, "gfx_brightness": 1.0}
## The same with the old "high quality" switch turned off (and no Graphics settings yet).
const LOW := {"gfx_gi": "off", "gfx_volumetrics": "off", "gfx_clouds": "low", "gfx_ssr": false,
	"gfx_ssao": true, "gfx_glow": true, "gfx_shadows": "low", "gfx_draw_distance": 1.0, "gfx_brightness": 1.0}
## Shadows at each quality: the sun's shadow map size and soft filter (0 hard .. 5 ultra), its
## splits and reach, the size of the lamps' shadow atlas, whether round lamps (omni) cast
## shadows, whether the yard floodlights do (god rays through the night air), and soft
## contact-hardening shadows (PCSS) from the size of each lamp, and the smallest thing (its
## longest side, metres) that still casts a shadow: bolts, labels and the like throw shadows
## too small to see, and with a shed full of bikes there are hundreds of them in every lamp's
## shadow map.
const SHADOWS := {
	"low": {"atlas": 2048, "soft": 1, "splits": 2, "distance": 90.0, "positional": 2048, "omni": false, "floods": false, "pcss": false, "caster_min": 0.3},
	"medium": {"atlas": 4096, "soft": 2, "splits": 4, "distance": 150.0, "positional": 4096, "omni": true, "floods": false, "pcss": false, "caster_min": 0.18},
	"high": {"atlas": 8192, "soft": 3, "splits": 4, "distance": 220.0, "positional": 4096, "omni": true, "floods": true, "pcss": false, "caster_min": 0.1},
	"ultra": {"atlas": 8192, "soft": 5, "splits": 4, "distance": 320.0, "positional": 8192, "omni": true, "floods": true, "pcss": true, "caster_min": 0.05},
}
## The biggest of those (anything this size or more always keeps its shadow).
const CASTER_MAX := 0.3
## The rooms whose lamps can't shine on anything you can see from a room, so they are left
## out while you're in it (outdoors nothing is). Each room listed is sealed off from it, or
## three doorways away: the lounge upstairs is only reached by the outside stairs, and the
## ground-floor rooms off the shed only open into the shed. Lamps outdoors are never left out.
const HIDDEN_FROM := {
	"shed": ["lounge"],
	"paint": ["lounge", "annex"],
	"mixing": ["lounge", "storage", "annex", "wing", "dyno"],
	"storage": ["lounge", "mixing"],
	"annex": ["lounge", "mixing", "paint", "wing", "dyno"],
	"wing": ["lounge", "mixing", "annex"],
	"dyno": ["lounge", "mixing", "annex"],
	"lounge": ["shed", "paint", "mixing", "storage", "annex", "wing", "dyno"],
	"sales": ["paint", "mixing", "storage", "annex", "wing", "dyno"],
	"sales_office": ["paint", "mixing", "storage", "annex", "wing", "dyno"],
	"cafe": ["paint", "mixing", "storage", "annex", "wing", "dyno"],
}
## How much of the volumetric fog a lamp lights when nobody chose: a round lamp lights the air a
## little, a downlight more (a cone of light in the shed's dust).
const OMNI_FOG := 0.35
const SPOT_FOG := 0.8
## Dust in the shed and paint overspray: how thick each fog volume gets.
const DUST_DENSITY := 0.03
const OVERSPRAY_DENSITY := 0.07
## Your eyes adjusting: how much brighter the picture is made in a room with the lights on or
## off, by day and by night, and how fast they adjust to the light and to the dark (per second).
const EYE_LIT := Vector2(1.08, 0.92)
const EYE_DARK := Vector2(1.5, 1.3)
const ADAPT_TO_LIGHT := 2.5
const ADAPT_TO_DARK := 0.55

static var current: Lighting
## Settings to use in place of Settings' own (for tests and screenshots); empty normally.
static var overrides := {}

var env: Environment
var sun: DirectionalLight3D
var daylight: Daylight
## What apply() last set (see profile()).
var profile_now := {}
## The eye adaptation now: the picture's exposure is the time of day's times this.
var adapt := 1.0
var dust: FogVolume
var overspray: FogVolume
## How much overspray is hanging in the paint shop's air, 0..1.
var overspray_level := 0.0

var _opts := {}
var _pending: Array[Node] = []
var _lights: Array[Light3D] = []
var _probes: Array[ReflectionProbe] = []
## Small meshes whose shadow depends on the quality (see tune_caster()).
var _casters: Array[GeometryInstance3D] = []
## Which room each lamp is in (looked at again now and then), and the room you're in.
var _light_rooms := {}
var _rooms_in := 0.0
var _lights_seen := 0
var _cam_room := ""
var _poll := 0.0
var _hq := true
var _adapted := false


# ---------------------------------------------------------------------------- settings

## One graphics setting, or its default (LOW ones with "high quality" off) when Settings hasn't
## got it.
static func option(key: String) -> Variant:
	if overrides.has(key):
		return overrides[key]
	var v: Variant = Settings.get(key)
	if v != null:
		return v
	var hq: Variant = Settings.get("high_quality")
	return (LOW if hq != null and not bool(hq) else DEFAULTS).get(key)


static func options() -> Dictionary:
	var out := {}
	for k in DEFAULTS:
		out[k] = option(k)
	return out


## True on the Forward+ renderer (where SDFGI, volumetric fog and fog volumes exist).
static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## What the options turn into on this renderer.
static func profile(opts: Dictionary, fp: bool) -> Dictionary:
	var gi := str(opts.get("gfx_gi", "sdfgi"))
	var vol := str(opts.get("gfx_volumetrics", "high"))
	var tier := str(opts.get("gfx_shadows", "high"))
	if not SHADOWS.has(tier):
		tier = "high"
	var best := tier == "high" or tier == "ultra"
	return {
		"sdfgi": fp and gi == "sdfgi",
		"ssil": fp and gi == "ssil",
		"ssr": bool(opts.get("gfx_ssr", true)),
		"ssao": bool(opts.get("gfx_ssao", true)),
		"glow": bool(opts.get("gfx_glow", true)),
		"volumetric_fog": vol != "off",
		"fog_volumes": fp and vol != "off",
		"fog_size": 128 if vol == "high" else 64,
		"fog_depth": 96 if vol == "high" else 48,
		"fog_length": 96.0 if vol == "high" else 56.0,
		"fog_filter": vol == "high",
		"sdfgi_cascades": 6 if best else 4,
		"sdfgi_min_cell": 0.15 if best else 0.25,
		"sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_96 if tier == "ultra" else (RenderingServer.ENV_SDFGI_RAY_COUNT_64 if best else RenderingServer.ENV_SDFGI_RAY_COUNT_32),
		"clouds": CloudSky.quality(str(opts.get("gfx_clouds", "high")), fp),
		"shadow_tier": tier,
		"shadow": SHADOWS[tier],
		"probe_shadows": best,
		# Below ultra, only the lamps of the room you're in (and the shed's, which has the dust
		# in its air, and the ones outdoors) light the volumetric fog: see _cull_room_lights().
		"fog_all_rooms": tier == "ultra",
		"draw_distance": clampf(float(opts.get("gfx_draw_distance", 1.0)), 0.5, 2.0),
		"brightness": clampf(float(opts.get("gfx_brightness", 1.0)), 0.5, 1.5),
	}


# ---------------------------------------------------------------------------- setting up

func _enter_tree() -> void:
	current = self
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	# Any lamp left out for the room you were in is put back.
	for l in _light_rooms:
		if is_instance_valid(l) and culled_by_room(l):
			(l as Light3D).remove_meta("room_cull")
			RenderingServer.instance_set_visible((l as Light3D).get_instance(), (l as Light3D).is_visible_in_tree())
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if current == self:
		current = null


## `env`, the `sun` and the `day` (Daylight) of the World this lights.
func setup(environment: Environment, sunlight: DirectionalLight3D, day: Daylight) -> void:
	env = environment
	sun = sunlight
	daylight = day
	if Settings.has_signal("graphics_changed"):
		Settings.connect("graphics_changed", apply)
	_hq = Settings.high_quality
	apply()
	# The rooms are built after the environment: pick up everything there once they are.
	_scan.call_deferred()


func _scan() -> void:
	if not is_inside_tree():
		return
	var root := get_parent() if get_parent() else self
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		_on_node_added(n)
		stack.append_array(n.get_children())
	apply()


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D or n is Light3D or n is ReflectionProbe:
		_pending.append(n)


## Puts the settings into effect (again). Safe to call any time.
func apply() -> void:
	if env == null:
		return
	_opts = options()
	var p := profile(_opts, forward_plus())
	profile_now = p
	_apply_environment(p)
	_apply_shadows(p)
	for l in _lights:
		if is_instance_valid(l):
			tune_light(l, p)
	for probe in _probes:
		if is_instance_valid(probe):
			probe.enable_shadows = bool(p["probe_shadows"])
	_casters = _casters.filter(func(g): return is_instance_valid(g))
	for g in _casters:
		tune_caster(g, p)
	if daylight and daylight.has_method("set_cloud_quality"):
		daylight.set_cloud_quality(str(_opts["gfx_clouds"]))
	_build_fog_volumes(p)
	_update_exposure(0.0)


func _apply_environment(p: Dictionary) -> void:
	# Global illumination: SDFGI fills the world with bounced light (the shed's floor and walls
	# glow with the light from the open door and the lamps); SSIL is the cheaper screen-space kind.
	env.sdfgi_enabled = p["sdfgi"]
	env.sdfgi_cascades = int(p["sdfgi_cascades"])
	env.sdfgi_min_cell_size = float(p["sdfgi_min_cell"])
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_energy = 1.0
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1
	if p["sdfgi"]:
		RenderingServer.environment_set_sdfgi_ray_count(int(p["sdfgi_rays"]))
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES)
		RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES)
	env.ssil_enabled = p["ssil"]
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.1
	env.ssil_normal_rejection = 1.0
	# Reflections on paint, chrome and wet roads.
	env.ssr_enabled = p["ssr"]
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25
	env.ssao_enabled = p["ssao"]
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	# Glow: only what's brighter than white blooms (lamps, tail lights, neon, screens); a wider
	# halo from the lower levels for the night.
	env.glow_enabled = p["glow"]
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	# A pixel gone wildly over-bright (a bad sample in the GI or the fog) blooms into a white blot;
	# capped, it stays a speck.
	env.glow_hdr_luminance_cap = 6.0
	env.set_glow_level(1, 0.8)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.35)
	env.set_glow_level(4, 0.2)
	# Volumetric fog: the air the sun, the lamps and the headlights shine through.
	env.volumetric_fog_enabled = p["volumetric_fog"]
	env.volumetric_fog_length = float(p["fog_length"])
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.95
	RenderingServer.environment_set_volumetric_fog_volume_size(int(p["fog_size"]), int(p["fog_depth"]))
	RenderingServer.environment_set_volumetric_fog_filter_active(bool(p["fog_filter"]))
	# The player's brightness setting.
	env.adjustment_enabled = true
	env.adjustment_brightness = float(p["brightness"])


func _apply_shadows(p: Dictionary) -> void:
	var sh: Dictionary = p["shadow"]
	RenderingServer.directional_shadow_atlas_set_size(int(sh["atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(sh["soft"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(sh["soft"]))
	if is_inside_tree() and get_viewport():
		get_viewport().positional_shadow_atlas_size = int(sh["positional"])
	var reach: float = float(sh["distance"]) * float(p["draw_distance"])
	if sun:
		tune_sun(sun, sh, reach)
	var moon: Variant = daylight.get("_moon") if daylight else null
	if moon is DirectionalLight3D:
		var m := moon as DirectionalLight3D
		m.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		m.directional_shadow_max_distance = minf(reach, 140.0)
		m.light_volumetric_fog_energy = 0.6


## The sun's shadows at a quality: more splits close in, so a bike and rider stay crisp while
## the far hills still get shadow.
static func tune_sun(light: DirectionalLight3D, sh: Dictionary, reach: float) -> void:
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(sh["splits"]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = reach
	light.directional_shadow_split_1 = 0.06
	light.directional_shadow_split_2 = 0.16
	light.directional_shadow_split_3 = 0.42
	light.directional_shadow_blend_splits = int(sh["soft"]) >= 3
	light.directional_shadow_fade_start = 0.85
	# A slightly larger sun at the top settings softens shadow edges with distance (PCSS).
	light.light_angular_distance = 0.9 if bool(sh["pcss"]) else 0.6
	light.light_volumetric_fog_energy = 1.2


## Whether `n` is part of a bike (its headlight, fog lights and the like look after
## themselves).
static func _on_a_bike(n: Node) -> bool:
	var p := n
	while p:
		if p is BikeEffects or p is Bike or p is RemoteBike or p is BikeModel:
			return true
		p = p.get_parent()
	return false


## A lamp at the quality `p` (see profile()): its glow in the fog (a sensible amount unless it
## was set on purpose) and its shadows. What the lamp had to begin with is kept, so a better
## setting later gets it back.
static func tune_light(l: Light3D, p: Dictionary) -> void:
	if l is DirectionalLight3D or l.has_meta("lighting_skip"):
		return
	if not l.has_meta("lighting_orig"):
		if _on_a_bike(l):
			l.set_meta("lighting_skip", true)
			return
		l.set_meta("lighting_orig", [l.shadow_enabled, l.light_volumetric_fog_energy, l.light_size])
	var orig: Array = l.get_meta("lighting_orig")
	var sh: Dictionary = p["shadow"]
	var fog: float = orig[1]
	if is_equal_approx(fog, 1.0):   # Godot's own default: nobody chose
		fog = OMNI_FOG if l is OmniLight3D else SPOT_FOG
	l.light_volumetric_fog_energy = 0.0 if l.get_meta("fog_cut", false) else fog
	var shadow: bool = orig[0]
	if l is OmniLight3D and not bool(sh["omni"]):
		shadow = false
	if l is SpotLight3D and l.is_in_group(Daylight.NIGHT_LIGHTS) and bool(sh["floods"]):
		shadow = true
	l.shadow_enabled = shadow
	l.light_size = 0.06 if bool(sh["pcss"]) and shadow else float(orig[2])


## What never casts a shadow at any quality: what you hold in front of you (it hangs off your
## camera, and you have no body for it to belong to) and particles (smoke, spray, water). Both
## change every frame, and anything casting a shadow that moves makes every lamp it's near
## draw its shadow map again, every frame: walking round the shed with a spanner in your hand
## redrew the shadows of every lamp in reach.
static func casts_no_shadow(g: GeometryInstance3D) -> bool:
	if g is CPUParticles3D or g is GPUParticles3D:
		return true
	var n := g.get_parent()
	while n:
		if n is Camera3D:
			return true
		n = n.get_parent()
	return false


## Whether a small mesh (under CASTER_MAX across) casts a shadow at the quality `p`: only when
## it's at least the quality's "caster_min". Its size is noted the first time, so a better
## setting later gives its shadow back. Returns false for anything this leaves alone (bigger
## things, and meshes whose shadow was set on purpose: off, double-sided or shadow only).
static func tune_caster(g: GeometryInstance3D, p: Dictionary) -> bool:
	if not g.has_meta("lighting_caster"):
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or not (g is MeshInstance3D or g is Label3D):
			return false
		var box := g.get_aabb()
		var size := box.size * (g.global_basis.get_scale().abs() if g.is_inside_tree() else Vector3.ONE)
		var longest := maxf(size.x, maxf(size.y, size.z))
		if longest >= CASTER_MAX or longest <= 0.0:
			return false
		g.set_meta("lighting_caster", longest)
	if p.is_empty():
		return true
	var small: bool = float(g.get_meta("lighting_caster")) < float((p["shadow"] as Dictionary).get("caster_min", 0.0))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true


## How a mesh takes part in global illumination: buildings and big fixed things are static
## (they bounce light and block it); anything that moves (bikes, riders, carried kit,
## particles, rain) or is small (parts, tools, props) is left out, so nothing leaves a stale
## ghost of bounced light behind when it moves.
static func gi_mode_for(g: GeometryInstance3D) -> int:
	if g is CPUParticles3D or g is GPUParticles3D or g is Label3D or g is SpriteBase3D:
		return GeometryInstance3D.GI_MODE_DISABLED
	var n: Node = g
	while n:
		if n is RigidBody3D or n is CharacterBody3D or n is VehicleBody3D or n is AnimatableBody3D:
			return GeometryInstance3D.GI_MODE_DISABLED
		if n is Bike or n is RemoteBike or n is BikeModel or n is BikeEffects or n is Walker or n is RemotePlayer \
				or n is EquipmentView or n is Weather or n is RiderRagdoll:
			return GeometryInstance3D.GI_MODE_DISABLED
		if n.is_in_group("customers"):
			return GeometryInstance3D.GI_MODE_DISABLED
		n = n.get_parent()
	if g is VisualInstance3D:
		var size: Vector3 = g.get_aabb().size * g.global_basis.get_scale() if g.is_inside_tree() else g.get_aabb().size
		if maxf(size.x, maxf(size.y, size.z)) < 0.8:
			return GeometryInstance3D.GI_MODE_DISABLED
	return GeometryInstance3D.GI_MODE_STATIC


# ---------------------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("sky_weather", pt)


func _process_body(delta: float) -> void:
	if not _pending.is_empty():
		_drain_pending()
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		if options() != _opts or Settings.high_quality != _hq:
			_hq = Settings.high_quality
			apply()
	_update_exposure(delta)
	_update_overspray(delta)
	_cull_room_lights(delta)


## The lamps of rooms you can't see into from the room you're in (HIDDEN_FROM) are left out
## of the picture: they light nothing you can see, but each still costs the GPU (in the fog,
## the GI and, shadowed, a shadow map of everything in its reach). It's done on the
## renderer's side of the lamp, so the light switches (which show and hide lamps) work as ever.
func _cull_room_lights(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	_rooms_in -= delta
	if _rooms_in <= 0.0 or _lights_seen != _lights.size():
		_rooms_in = 0.5
		_lights_seen = _lights.size()
		_light_rooms.clear()
		for l in _lights:
			if is_instance_valid(l) and l.is_inside_tree():
				_light_rooms[l] = Workshop.room_at(l.global_position)
	# The room you're in, every frame, so walking through a doorway catches up straight away.
	_cam_room = Workshop.room_at(cam.global_position) if cam else ""
	var hidden: Array = HIDDEN_FROM.get(_cam_room, [])
	var fog_all := bool(profile_now.get("fog_all_rooms", true)) or _cam_room == ""
	for l in _light_rooms:
		if not is_instance_valid(l):
			continue
		var light := l as Light3D
		var room: String = _light_rooms[l]
		var shown := light.is_visible_in_tree()
		var out := hidden.has(room)
		var key := int(shown) + 2 * int(out)
		if int(light.get_meta("room_cull", -1)) != key:
			light.set_meta("room_cull", key)
			RenderingServer.instance_set_visible(light.get_instance(), shown and not out)
		# Working out how every lamp lights the fog is a big part of drawing a frame indoors,
		# where dozens are in reach; a lamp in the next room only lights its air through the
		# doorway.
		var cut := not fog_all and room != _cam_room and room != "" and room != "shed"
		if bool(light.get_meta("fog_cut", false)) != cut and not light.has_meta("lighting_skip"):
			light.set_meta("fog_cut", cut)
			if not profile_now.is_empty():
				tune_light(light, profile_now)


## Whether a lamp is left out of the picture for the room you're in (see _cull_room_lights()).
static func culled_by_room(l: Light3D) -> bool:
	return int(l.get_meta("room_cull", 0)) >= 2


func _drain_pending() -> void:
	var p := profile_now
	var batch := _pending
	_pending = []
	var my_world := get_viewport().world_3d if is_inside_tree() and get_viewport() else null
	for n in batch:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if my_world and (n as Node3D).get_world_3d() != my_world:
			continue   # a preview in a menu, not the game world
		if n is DirectionalLight3D:
			continue   # the sun and moon: see _apply_shadows()
		if n is Light3D:
			if not _lights.has(n):
				_lights.append(n)
			if not p.is_empty():
				tune_light(n, p)
		elif n is ReflectionProbe:
			if not _probes.has(n):
				_probes.append(n)
			if not p.is_empty():
				(n as ReflectionProbe).enable_shadows = bool(p["probe_shadows"])
		elif n is GeometryInstance3D:
			(n as GeometryInstance3D).gi_mode = gi_mode_for(n)
			if casts_no_shadow(n):
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				continue
			var tracked := n.has_meta("lighting_caster")
			if tune_caster(n, p) and not tracked:
				_casters.append(n)
	_lights = _lights.filter(func(l): return is_instance_valid(l))
	_probes = _probes.filter(func(pr): return is_instance_valid(pr))


## Whether the lights are on in `room` (see Workshop.room_at()).
static func room_lit(room: String) -> bool:
	match room:
		"":
			return false
		"shed", "wing", "annex":
			return Shed.lights_on
		"dyno":
			return bool(Shed.dyno.get("lights", true))
		"mixing":
			return Shed.room_lit("paint")   # the mixing bay is on the paint shop's switch
		"sales_office":
			return Shed.room_lit("sales")
	return Shed.room_lit(room)


## How much your eyes open up (times the time of day's exposure): 1 outdoors; a little more in
## a lit room by day, a little less at night (the lamps are bright after the dark); a lot more
## in a room with its lights off.
static func eye_target(room: String, lit: bool, dark: float) -> float:
	if room == "":
		return 1.0
	var span := EYE_LIT if lit else EYE_DARK
	return lerpf(span.x, span.y, dark)


func _update_exposure(delta: float) -> void:
	if env == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	var room := Workshop.room_at(cam.global_position) if cam else ""
	var target := eye_target(room, room_lit(room) if room != "" else false, Daylight.darkness())
	if not _adapted:
		_adapted = true
		adapt = target
	elif delta > 0.0:
		# Eyes close down fast in bright light and open up slowly in the dark.
		var rate := ADAPT_TO_LIGHT if target < adapt else ADAPT_TO_DARK
		adapt = lerpf(adapt, target, 1.0 - exp(-delta * rate))
	var base := daylight.exposure if daylight else 1.0
	env.tonemap_exposure = base * adapt
	if daylight:
		env.glow_intensity = daylight.glow_intensity
		env.glow_bloom = daylight.glow_bloom


# ---------------------------------------------------------------------------- fog volumes

const DUST_SHADER := """
shader_type fog;

uniform float density = 0.03;
uniform vec3 albedo : source_color = vec3(0.95, 0.88, 0.75);
uniform sampler3D dust : repeat_enable, filter_linear;
uniform float scale = 0.12;
uniform float drift = 0.04;

void fog() {
	vec3 p = WORLD_POSITION * scale + vec3(1.0, 0.4, 0.7) * TIME * drift;
	float n = texture(dust, p).r;
	vec3 e = min(UVW, vec3(1.0) - UVW);
	float edge = smoothstep(0.0, 0.15, min(e.x, min(e.y, e.z)));
	DENSITY = density * (0.3 + 1.4 * n * n) * edge;
	ALBEDO = albedo;
}
"""


## Fog volumes (Forward+ with volumetric fog on): dust hanging in the shed, which the sun through
## the door and the lamps light into soft shafts, and the paint shop's overspray haze. Gone at
## "off" and on the compatibility renderer.
func _build_fog_volumes(p: Dictionary) -> void:
	var want := bool(p.get("fog_volumes", false))
	if not want:
		for v in [dust, overspray]:
			if is_instance_valid(v):
				v.queue_free()
		dust = null
		overspray = null
		return
	var parent := get_parent()
	if parent == null:
		return
	var low := str(_opts.get("gfx_volumetrics", "high")) == "low"
	if not is_instance_valid(dust):
		dust = _fog_box("ShedDust", Workshop.CENTER, Vector3(Workshop.HALF.x * 2.0, Workshop.HEIGHT, Workshop.HALF.y * 2.0),
			Color(0.95, 0.88, 0.76), 0.035)
		parent.add_child(dust)
	(dust.material as ShaderMaterial).set_shader_parameter("density", DUST_DENSITY * (0.6 if low else 1.0))
	if not is_instance_valid(overspray):
		var c := Workshop.BOOTH_ROOM_CENTER
		var h := Workshop.BOOTH_ROOM_HALF
		overspray = _fog_box("Overspray", c, Vector3(h.x * 2.0, Workshop.ROOM_HEIGHT, h.y * 2.0), Color(0.92, 0.93, 0.95), 0.02)
		parent.add_child(overspray)
	_update_overspray(0.0)


func _fog_box(node_name: String, floor_at: Vector3, size: Vector3, color: Color, drift: float) -> FogVolume:
	var v := FogVolume.new()
	v.name = node_name
	v.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	v.size = size
	v.position = floor_at + Vector3(0.0, size.y * 0.5, 0.0)
	var sh := Shader.new()
	sh.code = DUST_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("dust", CloudSky.detail_texture())
	m.set_shader_parameter("drift", drift)
	v.material = m
	return v


## The paint shop's air fills with haze while someone sprays the gun or can in there, and clears
## over half a minute or so.
func _update_overspray(delta: float) -> void:
	var spraying := false
	var w := get_tree().get_first_node_in_group("local_walker") if is_inside_tree() else null
	if w:
		var mist: Variant = w.get("_mist")
		if mist is CPUParticles3D and (mist as CPUParticles3D).emitting and (mist as Node3D).is_inside_tree():
			spraying = Workshop.room_at((mist as Node3D).global_position) == "paint"
			if spraying and is_instance_valid(overspray):
				var tint: Color = (mist as CPUParticles3D).color
				(overspray.material as ShaderMaterial).set_shader_parameter("albedo", Color(0.92, 0.93, 0.95).lerp(tint, 0.25))
	overspray_level = clampf(overspray_level + (0.1 if spraying else -0.035) * delta, 0.0, 1.0)
	if is_instance_valid(overspray):
		overspray.visible = overspray_level > 0.01
		(overspray.material as ShaderMaterial).set_shader_parameter("density", OVERSPRAY_DENSITY * overspray_level)
