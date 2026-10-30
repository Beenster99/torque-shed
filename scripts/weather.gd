class_name Weather
extends Node
## The weather: clear skies, cloud, fog or rain, changing every few minutes by itself or held
## at one kind from the Esc menu. Each change drifts in over BLEND_TIME. Daylight reads the
## blended cloud cover, mist and rain to darken and grey the sky, dim the sun and thicken the
## fog; this node draws the rain round the camera (never inside the shed's rooms), plays it
## outside and drumming on the roof indoors, and soaks the roads: darker and shinier, and a
## little less grip (grip_mult, read by the bike's tyres).
##
## Solo or hosting, Settings.weather drives it; on a co-op client the host's weather wins: the
## host sends it every SYNC_INTERVAL through Net. The World makes one; find it as Weather.current.

const STATES: Array[String] = ["clear", "cloudy", "fog", "rain"]
const NAMES := {"clear": "Clear skies", "cloudy": "Cloudy", "fog": "Fog", "rain": "Rain"}
## How each looks: cloud cover (0 a few wisps .. 1 overcast), mist (0 .. 1 thick fog) and rain.
const LOOK := {"clear": {"cover": 0.2, "fog": 0.0, "rain": 0.0}, "cloudy": {"cover": 0.78, "fog": 0.05, "rain": 0.0},
	"fog": {"cover": 0.6, "fog": 1.0, "rain": 0.0}, "rain": {"cover": 1.0, "fog": 0.25, "rain": 1.0}}
## Changing by itself: where each kind of weather can go next (repeats make it likelier).
const NEXT := {"clear": ["cloudy", "cloudy", "cloudy", "fog"], "cloudy": ["clear", "clear", "rain", "rain", "fog"],
	"fog": ["clear", "cloudy"], "rain": ["cloudy", "cloudy", "clear"]}
## Seconds of real time each spell of weather lasts when it changes by itself.
const SPELL := Vector2(240.0, 600.0)
const BLEND_TIME := 40.0     # seconds one kind of weather takes to turn into the next
const SOAK_TIME := 80.0      # seconds of full rain to soak the roads
const DRY_TIME := 300.0      # seconds for soaked roads to dry out
const SYNC_INTERVAL := 2.0
## How many rooms' roofs the rain shader keeps the rain out from under (Workshop.rooms()).
const SHELTERS := 10
## Tyre grip on soaked ground, as a share of dry grip.
const WET_GRIP := {"tarmac": 0.85, "dirt": 0.9, "grass": 0.9}
const DROPS := 2400
const RAIN_BOX := Vector3(28.0, 16.0, 28.0)   # the block of falling rain kept round the camera

static var current: Weather
## Out on an adventure, the theme's odds of each kind of weather ({state: weight}, see
## AdventureTheme "weather"): when it changes by itself it's drawn from these instead of NEXT.
## Empty back at the shed (and on a varied ride).
static var odds := {}

var state := "clear"       # the weather it is (or is turning into)
var from := "clear"        # the weather it's turning from
var blend := 1.0           # 0 (all `from`) .. 1 (all `state`)
var wet := 0.0             # how soaked the ground is, 0..1
## The blended look right now (see LOOK).
var cover := 0.2
var mist := 0.0
var rain := 0.0
## Where the camera is: true inside one of the shed's rooms (the rain is on the roof).
var indoors := false

var _spell := 0.0
var _send_timer := 0.0
var _synced := false
var _was_client := false
var _world: Node
var _rain_mesh: MultiMeshInstance3D
var _rain_mat: ShaderMaterial
var _outside: AudioStreamPlayer
var _roof: AudioStreamPlayer
var _wet_shown := -1.0
var _rng := RandomNumberGenerator.new()


static func rain_level() -> float:
	return current.rain if current else 0.0


static func wetness() -> float:
	return current.wet if current else 0.0


static func cover_level() -> float:
	return current.cover if current else LOOK["clear"]["cover"]


static func fog_level() -> float:
	return current.mist if current else 0.0


## How much grip a tyre has on `surface` with the ground as wet as it is now (1 when dry).
static func grip_mult(surface: String) -> float:
	return lerpf(1.0, float(WET_GRIP.get(surface, 1.0)), wetness())


## "Rain", "Clear skies" ... for menus and the HUD.
static func state_name(s: String) -> String:
	return str(NAMES.get(s, s.capitalize()))


## True on a co-op client, where the host sets the weather.
static func set_by_host() -> bool:
	return Net.is_online() and not Net.is_host()


func _ready() -> void:
	current = self
	_rng.randomize()
	Net.weather_received.connect(_on_host_weather)
	# A player who joins hears the weather straight away, not at the next regular send.
	Net.player_joined.connect(func(_id: int, _info: Dictionary) -> void: _send_timer = 0.0)
	var start := Settings.weather if STATES.has(Settings.weather) else Settings.weather_now
	state = start if STATES.has(start) else "clear"
	from = state
	blend = 1.0
	wet = 1.0 if state == "rain" else 0.0
	_spell = _rng.randf_range(SPELL.x, SPELL.y)
	_mix()


func _exit_tree() -> void:
	if current == self:
		current = null


## `world` (a World) gives the road and ground materials to soak.
func setup(world: Node) -> void:
	_world = world
	_build_rain()
	_outside = _loop_player("rain")
	_roof = _loop_player("rain_roof")
	_apply_effects(0.0)


## Turns the weather to `to` (solo or host only), over BLEND_TIME or at once with `instant`.
func change_to(to: String, instant := false) -> void:
	if set_by_host() or not STATES.has(to):
		return
	if to != state:
		# Part way through a change: carry on from what it looks like now.
		from = state if blend >= 0.5 else from
		state = to
		blend = 0.0
		# The crew hear about it at once.
		_send_timer = 0.0
	if instant:
		blend = 1.0
		from = state
		if state == "rain":
			wet = 1.0
		elif state == "clear":
			wet = 0.0
	Settings.weather_now = state
	_spell = _rng.randf_range(SPELL.x, SPELL.y)
	_send_timer = 0.0
	_mix()


## What a save keeps: the weather now and how wet it is.
func save_data() -> Dictionary:
	return {"state": state, "wet": wet}


## Puts saved weather back (solo or host).
func restore(data: Dictionary) -> void:
	var s := str(data.get("state", state))
	if STATES.has(Settings.weather):
		s = Settings.weather
	change_to(s, true)
	wet = clampf(float(data.get("wet", wet)), 0.0, 1.0)


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("sky_weather", pt)


func _process_body(delta: float) -> void:
	var client := set_by_host()
	if client:
		if _synced:
			blend = minf(blend + delta / BLEND_TIME, 1.0)
	else:
		if _was_client:
			# Left a co-op session: back to our own weather.
			_synced = false
			change_to(Settings.weather_now if STATES.has(Settings.weather_now) else "clear", true)
		if STATES.has(Settings.weather):
			if Settings.weather != state:
				change_to(Settings.weather)
		else:
			_spell -= delta
			if _spell <= 0.0:
				var options: Array = NEXT[state]
				var next := str(options[_rng.randi() % options.size()])
				if not odds.is_empty():
					next = AdventureTheme.weather_pick_from(odds, _rng.randf())
				change_to(next)
		blend = minf(blend + delta / BLEND_TIME, 1.0)
		# Rain soaks the ground; once it stops it dries out slowly.
		_mix()
		if rain > 0.05:
			wet = minf(wet + rain * delta / SOAK_TIME, 1.0)
		else:
			wet = maxf(wet - delta / DRY_TIME, 0.0)
		if Net.is_host():
			_send_timer -= delta
			if _send_timer <= 0.0:
				_send_timer = SYNC_INTERVAL
				Net.send_weather(state, from, blend, wet)
	_was_client = client
	_mix()
	_apply_effects(delta)


func _on_host_weather(s: String, f: String, b: float, w: float) -> void:
	if not set_by_host() or not STATES.has(s) or not STATES.has(f):
		return
	if not _synced or s != state or absf(b - blend) > 0.1:
		state = s
		from = f
		blend = clampf(b, 0.0, 1.0)
	_synced = true
	wet = clampf(w, 0.0, 1.0)
	_mix()


## The blended look from `from` to `state`.
func _mix() -> void:
	var k := smoothstep(0.0, 1.0, blend)
	var a: Dictionary = LOOK[from]
	var b: Dictionary = LOOK[state]
	cover = lerpf(float(a["cover"]), float(b["cover"]), k)
	mist = lerpf(float(a["fog"]), float(b["fog"]), k)
	# Rain starts late in the change to it and stops early in the change away.
	var ra := float(a["rain"]) * (1.0 - smoothstep(0.0, 0.6, blend))
	var rb := float(b["rain"]) * smoothstep(0.4, 1.0, blend)
	rain = maxf(ra, rb)


# ---------------------------------------------------------------------------- what it does

func _apply_effects(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	indoors = cam != null and Workshop.room_at(cam.global_position) != ""
	if _rain_mat:
		# In an adventure's tunnel no rain falls round you, and the outside's rain is heard faintly.
		_rain_mesh.visible = rain > 0.01 and Daylight.shelter < 0.6
		_rain_mat.set_shader_parameter("amount", rain)
		var night := Daylight.darkness()
		_rain_mat.set_shader_parameter("tint", Color(0.75, 0.8, 0.88).lerp(Color(0.22, 0.25, 0.32), night))
	# Rain heard outside, or drumming on the roof from indoors; it eases across at the door.
	var out_target := rain * (0.0 if indoors else 1.0 - 0.85 * Daylight.shelter)
	var roof_target := rain * (1.0 if indoors else 0.0)
	_fade(_outside, out_target, delta, 0.0)
	_fade(_roof, roof_target, delta, 3.0)
	if absf(wet - _wet_shown) > 0.01:
		_wet_shown = wet
		_soak()
	# The bikes too, though not in the dry of the shed.
	BikeShader.set_wet(0.0 if indoors else wet)


func _loop_player(sound: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = Sfx.stream(sound)
	p.volume_db = -80.0
	p.set_meta("level", 0.0)
	add_child(p)
	return p


func _fade(p: AudioStreamPlayer, target: float, delta: float, boost_db: float) -> void:
	if p == null:
		return
	var level: float = p.get_meta("level", 0.0)
	level = move_toward(level, target, delta * 1.5) if delta > 0.0 else target
	p.set_meta("level", level)
	if level > 0.01:
		p.volume_db = linear_to_db(level * 0.5) + boost_db
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()


## Wet ground: darker and shinier as it soaks (World.wet_surfaces).
func _soak() -> void:
	if _world == null or not ("wet_surfaces" in _world):
		return
	for entry in _world.wet_surfaces:
		var mat: StandardMaterial3D = entry["mat"]
		var color: Color = entry["color"]
		var rough: float = entry["rough"]
		var shine: float = entry["shine"]
		mat.albedo_color = Color(color.r * lerpf(1.0, 0.62, wet), color.g * lerpf(1.0, 0.62, wet), color.b * lerpf(1.0, 0.64, wet), color.a)
		mat.roughness = lerpf(rough, lerpf(rough, 0.18, shine), wet)


## Whether rain is falling where `at` is (outside, under the open sky: not in a tunnel).
static func raining_at(at: Vector3) -> bool:
	return rain_level() > 0.05 and Workshop.room_at(at) == "" and AdventureWorld.shelter_at(at) < 0.5


## The rain: thin streaks drawn from one MultiMesh, falling in a block that stays round the
## camera, all moved by the shader (nothing per drop on the CPU). Drops inside the shed's rooms,
## below their roofs, are never drawn.
func _build_rain() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.55)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = DROPS
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in DROPS:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	mm.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	_rain_mesh = MultiMeshInstance3D.new()
	_rain_mesh.name = "Rain"
	_rain_mesh.multimesh = mm
	_rain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mesh.extra_cull_margin = 16384.0
	_rain_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = RAIN_SHADER
	_rain_mat.shader = sh
	_rain_mat.set_shader_parameter("box", RAIN_BOX)
	refresh_shelters()
	_rain_mesh.material_override = _rain_mat
	_rain_mesh.visible = false
	add_child(_rain_mesh)


## Tells the rain shader where the rooms' roofs are (Workshop.rooms()), so no drops are drawn
## under them. Call again when the rooms change.
func refresh_shelters() -> void:
	if _rain_mat == null:
		return
	var rects := []
	var tops := []
	var all := Workshop.rooms()
	for room in all:
		if rects.size() >= SHELTERS:
			break
		if room == "sales_office":
			continue   # upstairs in "sales", under the same roof
		var r: Rect2 = all[room]
		r = r.grow(0.6)
		rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		tops.append(shelter_top(room))
	while rects.size() < SHELTERS:
		rects.append(Vector4.ZERO)
		tops.append(-1000.0)
	_rain_mat.set_shader_parameter("shelters", PackedVector4Array(rects))
	_rain_mat.set_shader_parameter("shelter_tops", PackedFloat32Array(tops))


## The height of a room's roof: no rain is drawn under it.
static func shelter_top(room: String) -> float:
	match room:
		"shed":
			return Workshop.HEIGHT + 0.35
		"dyno":
			return DynoRoom.HEIGHT + 0.3
		"sales", "sales_office":
			return SalesOffice.CEIL_Y + 0.4
		"wing":
			return GarageUpgrades.WING_HEIGHT + 0.3
		"annex":
			return GarageUpgrades.ANNEX_HEIGHT + 0.3
	return Workshop.ROOM_HEIGHT + 0.2


const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords, fog_disabled;

uniform vec3 box = vec3(28.0, 16.0, 28.0);
uniform float amount = 1.0;
uniform float speed = 11.0;
uniform vec3 wind = vec3(0.8, 0.0, 0.4);
uniform vec4 tint : source_color = vec4(0.75, 0.8, 0.88, 1.0);
uniform vec4 shelters[10];
uniform float shelter_tops[10];

varying float fade;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = TIME * speed * (0.85 + 0.3 * seed.w);
	vec3 fall = normalize(vec3(wind.x, -speed, wind.z));
	// Each drop falls through the block and wraps round, the block centred on the camera.
	vec3 p = seed.xyz * box + fall * t;
	vec3 base = cam - box * vec3(0.5, 0.35, 0.5);
	p = base + mod(p - base, box);
	bool hidden = seed.w > amount;
	for (int i = 0; i < 10; i++) {
		vec4 r = shelters[i];
		if (p.x > r.x && p.x < r.z && p.z > r.y && p.z < r.w && p.y < shelter_tops[i]) {
			hidden = true;
		}
	}
	// A thin streak along the fall, turned to face the camera.
	vec3 to_cam = cam - p;
	vec3 side = normalize(cross(fall, to_cam));
	VERTEX = hidden ? vec3(0.0, -10000.0, 0.0) : p + side * VERTEX.x + fall * VERTEX.y;
	float d = length(to_cam);
	fade = smoothstep(box.x * 0.5, box.x * 0.3, d) * smoothstep(0.4, 1.5, d);
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = tint.rgb;
	ALPHA = 0.32 * fade * across * smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
}
"""
