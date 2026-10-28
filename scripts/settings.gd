extends Node
## Player settings and input bindings, saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := "Rider"
var last_ip := "127.0.0.1"
var current_save := ""     # the save game played last (an id under user://saves/, see SaveGame)
## Riding realism: 0 = full sim (the front can tuck, a slide can high-side), 0.5 = the rider
## protects the front and smooths the throttle, 1 = the easiest, with the most help balancing.
var assist := 0.5
## Direct bars: the steer input turns into torque on the handlebars instead of a lean to aim for.
var direct_bars := false
## The telemetry overlay at the side of the screen while riding (F3 toggles it).
var telemetry_overlay := false
## The sat nav's map on the HUD too, while riding a bike with one fitted ({satnav_hud}).
var satnav_hud := true
## The sat nav as you like it: the map over a live picture from above ({satnav_satellite}),
## standing tall rather than wide on the HUD ({satnav_portrait}), how far it's zoomed out (1 as
## it comes, {satnav_zoom_in} / {satnav_zoom_out}), and the HUD's copy's size and where it sits
## (across and down the space it has, 0..1: 0, 1 is the bottom left corner; it comes in the middle
## at the bottom).
var satnav_satellite := false
var satnav_portrait := false
var satnav_zoom := 1.0
var satnav_scale := 1.0
var satnav_x := 0.5
var satnav_y := 1.0
const SATNAV_ZOOM := [0.4, 3.0]
const SATNAV_SCALE := [0.6, 2.2]
var auto_shift := true
## The chase camera eases back behind the bike after a moment of not swinging it round.
var camera_recentre := true
## Riders look into the corner: the head (and a little the shoulders) turn into the inside of a
## bend and towards its exit, and so does your view in first person (see RiderStyle.look_yaw).
var look_into_corner := true
## On foot, the view from behind your shoulder with your whole figure in it, instead of from
## your eyes (V, or View on a pad, toggles it; see WalkerView).
var walk_third_person := false
var high_quality := true
var sfx_volume := 0.8
var engine_volume := 0.8
var radio_volume := 0.6
var units := "metric"     # or "imperial"
var day_night_cycle := true
var day_length := 120      # real minutes per 24 h game day
var time_of_day := 9.0     # hours; kept up to date while playing so the clock carries on next time
## Weather: "auto" (it changes by itself) or held at one of Weather.STATES.
var weather := "auto"
var weather_now := "clear"   # the weather when last played, so it carries on next time
var snap_placement := true # equipment you carry snaps square and flush to walls and corners
var money_graph_range := "day"   # the money graphs' time unit: minute, hour, day, week, month or year (see MoneyGraph)
var free_rotate := false   # the rotate keys turn what you hold freely (5 degree taps, smooth held) rather than a quarter a press

## Emitted whenever a graphics setting (gfx_*) changes.
signal graphics_changed
# Graphics (Esc menu > Graphics; see Graphics for what each does and its allowed values).
var gfx_preset := "high"         # "low", "medium", "high", "ultra" or "custom"
var gfx_window_mode := "windowed" # "windowed", "borderless" or "fullscreen" (exclusive)
var gfx_resolution := "1600x900"  # window size, or the 3D render resolution in fullscreen
var gfx_monitor := -1             # -1 = wherever the window opens
var gfx_vsync := "on"             # "off", "on", "adaptive", "mailbox"
var gfx_fps_cap := 0              # 0 = unlimited
var gfx_fov := 75.0
var gfx_brightness := 1.0
var gfx_render_scale := 1.0       # 0.5..1.0 upscaled, 1.0..2.0 supersampled
var gfx_upscaler := "fsr2"        # "fsr2", "fsr1", "bilinear" or "off" (native resolution, no scaling)
var gfx_sharpness := 0.8          # 0 soft .. 1 sharpest
var gfx_msaa := "2x"              # "off", "2x", "4x", "8x"
var gfx_taa := false
var gfx_screen_aa := "fxaa"       # "off", "fxaa", "smaa"
var gfx_detail := "high"          # mesh detail and texture filtering: "low".."ultra"
var gfx_draw_distance := 1.0      # 0.5..2.0
var gfx_shadows := "high"         # "low", "medium", "high", "ultra"
var gfx_gi := "sdfgi"             # "off", "ssil", "sdfgi"
var gfx_volumetrics := "high"     # "off", "low", "high"
var gfx_clouds := "high"          # "off", "low", "medium", "high", "ultra"
var gfx_ssr := true
var gfx_ssao := true
var gfx_glow := true
var gfx_driver := "vulkan"        # "vulkan" or "d3d12" (Windows; from the next start)
var gfx_fps_counter := false
var gfx_avatar_shadows := true    # whether players', staff's and townsfolk's figures cast shadows
var gfx_mirrors := "medium"       # the ridden bike's live mirrors: "off" (plain glass), "low".."ultra" (see BikeMirrors)
const GFX_KEYS := ["gfx_preset", "gfx_window_mode", "gfx_resolution", "gfx_monitor", "gfx_vsync", "gfx_fps_cap",
	"gfx_fov", "gfx_brightness", "gfx_render_scale", "gfx_upscaler", "gfx_sharpness", "gfx_msaa", "gfx_taa",
	"gfx_screen_aa", "gfx_detail", "gfx_draw_distance", "gfx_shadows", "gfx_gi", "gfx_volumetrics", "gfx_clouds",
	"gfx_ssr", "gfx_ssao", "gfx_glow", "gfx_driver", "gfx_fps_counter", "gfx_avatar_shadows", "gfx_mirrors"]


## Every action a player can rebind, in the order the Key bindings tab lists them:
## [action, what it does, contexts]. Two actions clash when they share a key or button and a
## context: "foot" (walking about the shed), "ride" (on a bike), "spray" (a spray can or gun in
## your hand, on foot) and "board" (at the whiteboard, where its own keys take over).
const ACTIONS := [
	["move_forward", "Walk forward", ["foot"]], ["move_back", "Walk back", ["foot"]],
	["move_left", "Walk left", ["foot"]], ["move_right", "Walk right", ["foot"]],
	["sprint", "Run", ["foot"]], ["crouch", "Crouch", ["foot"]], ["jump", "Jump", ["foot"]],
	["walk_camera", "Camera on foot: first or third person", ["foot"]],
	["act", "Work / use (hold)", ["foot", "board"]], ["alt_act", "Second work button (hold)", ["foot", "board"]],
	["tool_next", "Next tool", ["foot", "board"]], ["tool_prev", "Previous tool", ["foot", "board"]],
	["tool_1", "Hands", ["foot", "board"]], ["tool_2", "Wrench", ["foot", "board"]], ["tool_3", "Brush", ["foot", "board"]],
	["tool_4", "Grinder", ["foot", "board"]], ["tool_5", "Spray can", ["foot", "board"]],
	["tool_6", "Pressure washer", ["foot", "board"]], ["tool_7", "Spray gun", ["foot", "board"]],
	["tool_8", "Stopwatch", ["foot", "board"]], ["tool_9", "Polisher", ["foot"]],
	["spray_colour", "Spray colour", ["spray"]], ["spray_finish", "Spray finish", ["spray"]],
	["rename", "Name a bike", ["foot"]], ["order_bike", "Looking at a bike: order one of these or copy its blueprint", ["foot"]], ["blast_scan", "Sandblaster: scan the engine", ["foot"]],
	["rotate_left", "Turn what you hold left", ["foot", "board"]], ["rotate_right", "Turn what you hold right", ["foot", "board"]],
	["rotate_free", "Free rotate on / off (quarter turns or any angle)", ["foot"]],
	["scrap", "Scrap equipment or a part, or take down an adventure photo (hold)", ["foot"]],
	["interact", "Use / get on / get off", ["foot", "ride"]], ["ping", "Ping", ["foot"]],
	["visor", "Flick your helmet visor (or goggles) up or down", ["foot", "ride"]],
	["emote_menu", "Emotes: open the bar (then 1 to 6)", ["foot"]], ["emote_wave", "Emote: wave", ["foot"]],
	["emote_thumbs", "Emote: thumbs up", ["foot"]], ["emote_point", "Emote: point", ["foot"]],
	["emote_shrug", "Emote: shrug", ["foot"]], ["emote_cheer", "Emote: cheer", ["foot"]], ["emote_dance", "Emote: dance", ["foot"]],
	["stopwatch", "Stopwatch start / stop", ["foot", "ride"]], ["menu", "Menu", ["foot", "ride", "board"]],
	["board_text", "Whiteboard: write text", ["board"]], ["board_undo", "Whiteboard: undo", ["board"]],
	["board_wipe", "Whiteboard: wipe (hold)", ["board"]], ["board_colour", "Whiteboard: next colour", ["board"]],
	["board_image", "Whiteboard: add a picture", ["board"]], ["board_move", "Whiteboard: move a picture", ["board"]],
	["board_bigger", "Whiteboard: picture bigger", ["board"]], ["board_smaller", "Whiteboard: picture smaller", ["board"]],
	["board_poster", "Whiteboard: make a poster", ["board"]],
	["throttle", "Throttle", ["ride"]], ["front_brake", "Front brake (truck: brake, hold when stopped to reverse)", ["ride"]], ["rear_brake", "Rear brake (truck: handbrake while held)", ["ride"]],
	["lean_left", "Lean left", ["ride"]], ["lean_right", "Lean right", ["ride"]],
	["body_back", "Weight back", ["ride"]], ["body_forward", "Weight forward", ["ride"]],
	["shift_up", "Shift up", ["ride"]], ["shift_down", "Shift down (truck: into reverse when stopped)", ["ride"]],
	["clutch", "Clutch in (hold): rev it in any gear", ["ride"]],
	["toggle_auto_shift", "Auto-shift on / off", ["ride"]], ["ignition", "Engine on / off", ["ride"]],
	["respawn", "Reset after a crash", ["ride"]], ["camera", "Camera: third person, first person, fly-by", ["ride"]],
	["horn", "Horn", ["ride"]], ["headlight", "Headlights: off, dipped, main beam", ["ride"]],
	["indicate_left", "Indicate left (again to cancel)", ["ride"]], ["indicate_right", "Indicate right (again to cancel)", ["ride"]],
	["handbrake", "Truck: handbrake on / off (stays on till let off)", ["ride"]],
	["look_back", "Reverse view: tap to toggle, hold to look behind", ["ride"]],
	["ride_mode", "Ride mode: Custom, Sport, Tour, Wet (dashes with ride modes)", ["ride"]],
	["cruise", "Cruise control on / off (dashes with it; the brakes or clutch cancel it)", ["ride"]],
	["nod", "Nod to a biker (hold: wave)", ["ride"]], ["ride_ping", "Ping (riding or driving)", ["ride"]],
	["tow", "Adventure: ask a mate for a tow, or let the strap go", ["ride"]],
	["ride_by", "Ride-by camera", ["ride"]], ["telemetry", "Telemetry overlay on / off", ["ride"]],
	["satnav_hud", "Sat nav: map, trip computer, then off the HUD", ["ride"]],
	["satnav_zoom_in", "Sat nav: zoom in", ["ride"]], ["satnav_zoom_out", "Sat nav: zoom out", ["ride"]],
	["satnav_satellite", "Sat nav: satellite view on / off", ["ride"]],
	["satnav_portrait", "Sat nav on the HUD: portrait or landscape", ["ride"]],
	["paper_map", "Adventure: the paper map of the route (when stopped)", ["foot", "ride"]],
	["photo", "Adventure: take a photo (hold to film a clip)", ["foot", "ride"]],
	["photo_camera", "Adventure: hold the camera up on foot (zoom, friends in shot)", ["foot"]],
	["movie", "Film a 10-second movie (a countdown first; again to stop)", ["foot", "ride"]],
	["ride_radio", "Adventure: the radio, the local stations (each press the next, then off)", ["ride"]],
	["screen_up", "Adjustable screen up", ["ride"]], ["screen_down", "Adjustable screen down", ["ride"]],
	["geometry_mode", "Geometry mode on / off", ["foot", "geo"]],
	["perf_overlay", "Performance profiler on / off", ["foot", "ride"]],
	["perf_record", "Performance profiler: record 60 s to a file", ["foot", "ride"]],
	["geo_move", "Geometry: move", ["geo"]], ["geo_rotate", "Geometry: rotate", ["geo"]],
	["geo_scale", "Geometry: scale / stretch", ["geo"]], ["geo_snap", "Geometry: snap (hold)", ["geo"]],
	["geo_undo", "Geometry: undo", ["geo"]], ["geo_reset", "Geometry: reset the part", ["geo"]],
]
const CONTEXT_NAMES := {"foot": "on foot", "ride": "riding or driving", "spray": "with a spray can or gun", "board": "at the whiteboard",
	"geo": "in geometry mode"}
## Sharing on purpose: with a spray can or gun out, the second button picks the colour.
## B on a pad jumps on foot, but with a spray can or gun out it's the finish (the spray comes first).
## View on a pad turns what you hold or carry; with nothing in hand it switches the camera.
## D-pad left is the stopwatch, but riding it indicates left (the stopwatch is P there).
## D-pad right indicates right on a bike and is the handbrake in the truck, which has no indicators.
const SHARED_OK := [["alt_act", "spray_colour"], ["jump", "spray_finish"], ["rotate_right", "walk_camera"], ["stopwatch", "indicate_left"],
	["handbrake", "indicate_right"]]
## The spray context sits on top of on foot: a spray key also clashes with on-foot keys.
const CONTEXT_ALSO := {"spray": ["foot"]}

## The performance profiler's panel (F4; see PerfOverlay).
var perf: PerfOverlay

## action -> the events it had before any rebinding, for Reset to defaults.
var _defaults := {}


func _ready() -> void:
	_setup_inputs()
	_pad_ui()
	for a in ACTIONS:
		_defaults[a[0]] = InputMap.action_get_events(a[0]).duplicate()
	load_settings()
	add_child(Graphics.new())
	perf = PerfOverlay.new()
	add_child(perf)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		last_ip = cfg.get_value("player", "last_ip", last_ip)
		current_save = str(cfg.get_value("player", "save", current_save))
		assist = cfg.get_value("riding", "assist", assist)
		auto_shift = cfg.get_value("riding", "auto_shift", auto_shift)
		direct_bars = bool(cfg.get_value("riding", "direct_bars", direct_bars))
		telemetry_overlay = bool(cfg.get_value("riding", "telemetry", telemetry_overlay))
		satnav_hud = bool(cfg.get_value("riding", "satnav_hud", satnav_hud))
		satnav_satellite = bool(cfg.get_value("riding", "satnav_satellite", satnav_satellite))
		satnav_portrait = bool(cfg.get_value("riding", "satnav_portrait", satnav_portrait))
		satnav_zoom = clampf(float(cfg.get_value("riding", "satnav_zoom", satnav_zoom)), SATNAV_ZOOM[0], SATNAV_ZOOM[1])
		satnav_scale = clampf(float(cfg.get_value("riding", "satnav_scale", satnav_scale)), SATNAV_SCALE[0], SATNAV_SCALE[1])
		satnav_x = clampf(float(cfg.get_value("riding", "satnav_x", satnav_x)), 0.0, 1.0)
		satnav_y = clampf(float(cfg.get_value("riding", "satnav_y", satnav_y)), 0.0, 1.0)
		if not cfg.has_section_key("riding", "satnav_centred") and satnav_x == 0.0 and satnav_y == 1.0:
			satnav_x = 0.5   # it used to come in the bottom left corner: left there, it moves to the new place
		camera_recentre = bool(cfg.get_value("riding", "camera_recentre", camera_recentre))
		look_into_corner = bool(cfg.get_value("riding", "look_into_corner", look_into_corner))
		walk_third_person = bool(cfg.get_value("walking", "third_person", walk_third_person))
		high_quality = cfg.get_value("video", "high_quality", high_quality)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		engine_volume = float(cfg.get_value("audio", "engines", engine_volume))
		radio_volume = cfg.get_value("audio", "radio", radio_volume)
		units = cfg.get_value("display", "units", units)
		day_night_cycle = cfg.get_value("world", "day_night_cycle", day_night_cycle)
		day_length = int(cfg.get_value("world", "day_length", day_length))
		time_of_day = float(cfg.get_value("world", "time_of_day", time_of_day))
		weather = str(cfg.get_value("world", "weather", weather))
		weather_now = str(cfg.get_value("world", "weather_now", weather_now))
		if cfg.has_section("bindings"):
			for action in cfg.get_section_keys("bindings"):
				var codes = cfg.get_value("bindings", action, [])
				if _defaults.has(action) and (codes is Array or codes is PackedStringArray):
					_set_events(action, codes)
		snap_placement = bool(cfg.get_value("building", "snap", snap_placement))
		free_rotate = bool(cfg.get_value("building", "free_rotate", free_rotate))
		money_graph_range = str(cfg.get_value("display", "money_graph", money_graph_range))
		if not MoneyGraph.RANGES.has(money_graph_range):
			money_graph_range = MoneyGraph.DEFAULT_RANGE
		_load_graphics(cfg)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("player", "save", current_save)
	cfg.set_value("riding", "assist", assist)
	cfg.set_value("riding", "auto_shift", auto_shift)
	cfg.set_value("riding", "direct_bars", direct_bars)
	cfg.set_value("riding", "telemetry", telemetry_overlay)
	cfg.set_value("riding", "satnav_hud", satnav_hud)
	cfg.set_value("riding", "satnav_satellite", satnav_satellite)
	cfg.set_value("riding", "satnav_portrait", satnav_portrait)
	cfg.set_value("riding", "satnav_zoom", satnav_zoom)
	cfg.set_value("riding", "satnav_scale", satnav_scale)
	cfg.set_value("riding", "satnav_x", satnav_x)
	cfg.set_value("riding", "satnav_y", satnav_y)
	cfg.set_value("riding", "satnav_centred", true)
	cfg.set_value("riding", "camera_recentre", camera_recentre)
	cfg.set_value("riding", "look_into_corner", look_into_corner)
	cfg.set_value("walking", "third_person", walk_third_person)
	cfg.set_value("video", "high_quality", high_quality)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "engines", engine_volume)
	cfg.set_value("audio", "radio", radio_volume)
	cfg.set_value("display", "units", units)
	cfg.set_value("world", "day_night_cycle", day_night_cycle)
	cfg.set_value("world", "day_length", day_length)
	cfg.set_value("world", "time_of_day", time_of_day)
	cfg.set_value("world", "weather", weather)
	cfg.set_value("world", "weather_now", weather_now)
	# Only what differs from the defaults is kept, so new defaults reach everything else.
	for a in ACTIONS:
		var codes := binding_codes(a[0])
		if codes != _codes_of(_defaults.get(a[0], [])):
			cfg.set_value("bindings", a[0], codes)
	cfg.set_value("building", "snap", snap_placement)
	cfg.set_value("building", "free_rotate", free_rotate)
	cfg.set_value("display", "money_graph", money_graph_range)
	for k in GFX_KEYS:
		cfg.set_value("graphics", k, get(k))
	cfg.save(PATH)


# ---------------------------------------------------------------------------- graphics

func _load_graphics(cfg: ConfigFile) -> void:
	if not cfg.has_section("graphics"):
		# A settings file from before the Graphics tab: "high quality" off becomes the Low preset.
		if not high_quality:
			for k in Graphics.PRESETS["low"]:
				set(k, Graphics.PRESETS["low"][k])
			gfx_preset = "low"
		return
	for k in GFX_KEYS:
		if cfg.has_section_key("graphics", k):
			_set_checked(k, cfg.get_value("graphics", k))
	high_quality = gfx_preset != "low"


## Sets graphics key `k` to `v` if it's a value it can take (the right type, one of its
## choices, within its range); returns whether it did.
func _set_checked(k: String, v) -> bool:
	var cur = get(k)
	if cur is bool:
		if not v is bool:
			return false
	elif cur is int or cur is float:
		if not (v is int or v is float):
			return false
		if Graphics.RANGES.has(k):
			v = clampf(float(v), float(Graphics.RANGES[k][0]), float(Graphics.RANGES[k][1]))
		if k == "gfx_fps_cap" and not Graphics.FPS_CAPS.has(int(v)):
			return false
		v = int(v) if cur is int else float(v)
	elif cur is String:
		v = str(v)
		if Graphics.CHOICES.has(k) and not Graphics.CHOICES[k].has(v):
			return false
		if k == "gfx_resolution" and Graphics.resolution_text(Graphics.parse_resolution(v)) != v:
			return false
	set(k, v)
	return true


## Changes one graphics setting from the menu. Changing anything a preset sets makes the
## preset "Custom". Picking a driver writes it for the next start.
func set_graphics(k: String, v) -> void:
	if not GFX_KEYS.has(k) or not _set_checked(k, v):
		return
	if k == "gfx_preset":
		if Graphics.PRESETS.has(v):
			apply_preset(v)
		return
	if Graphics.PRESETS["high"].has(k):
		gfx_preset = "custom"
	if k == "gfx_driver":
		Graphics.write_driver_override(gfx_driver)
	high_quality = gfx_preset != "low"
	graphics_changed.emit()


## Sets every option a preset ("low", "medium", "high", "ultra") covers.
func apply_preset(preset: String) -> void:
	if not Graphics.PRESETS.has(preset):
		return
	var values: Dictionary = Graphics.PRESETS[preset]
	for k in values:
		set(k, values[k])
	gfx_preset = preset
	high_quality = preset != "low"
	graphics_changed.emit()


## Whether the rotate keys turn what you hold freely (a 5 degree tap, smooth while held) rather
## than a quarter turn a press: free rotate is on, or snapping is off.
func turns_freely() -> bool:
	return free_rotate or not snap_placement


## Keyboard, mouse and gamepad-button bindings. Gamepad sticks and triggers are read by the
## Controls autoload instead, so a stuck or odd axis can't hold an action down.
func _setup_inputs() -> void:
	# Riding
	_bind("throttle", [KEY_W, KEY_UP], [])
	_bind("front_brake", [KEY_S, KEY_DOWN], [])
	_bind("rear_brake", [KEY_SPACE], [JOY_BUTTON_B])
	_bind("lean_left", [KEY_A, KEY_LEFT], [])
	_bind("lean_right", [KEY_D, KEY_RIGHT], [])
	# On a pad the weight goes back and forward on the left stick (see PAD_STICKS in Controls).
	_bind("body_back", [KEY_SHIFT], [])
	_bind("body_forward", [KEY_CTRL], [])
	_bind("shift_up", [KEY_E], [JOY_BUTTON_A])
	_bind("shift_down", [KEY_Q], [JOY_BUTTON_X])
	# Held: the clutch in (rev it in any gear), and a look back over your shoulder.
	_bind("clutch", [KEY_Z], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("look_back", [KEY_X], [JOY_BUTTON_RIGHT_SHOULDER])
	# The dash's ride mode and cruise control (no pad buttons spare).
	_bind("ride_mode", [KEY_B], [])
	_bind("cruise", [KEY_O], [])
	# A nod to another biker (held, a wave with the left hand).
	_bind("nod", [KEY_N], [JOY_BUTTON_RIGHT_STICK])
	_bind("respawn", [KEY_R], [JOY_BUTTON_BACK])
	_bind("camera", [KEY_C], [JOY_BUTTON_DPAD_DOWN])
	_bind("toggle_auto_shift", [KEY_U], [])
	# Out on an adventure: ask a mate for a tow, or let the strap go. No pad button.
	_bind("tow", [KEY_T], [])
	# On a pad the engine is LB and RB together (see PAD_CHORDS in Controls).
	_bind("ignition", [KEY_I], [])
	# The horn is a press of the left stick on a pad, as in driving games: the D-pad's left and
	# right are the indicators.
	_bind("horn", [KEY_H], [JOY_BUTTON_LEFT_STICK])
	# The indicators: , and . (the < and > keys) or the D-pad's left and right; again to cancel.
	_bind("indicate_left", [KEY_COMMA], [JOY_BUTTON_DPAD_LEFT])
	_bind("indicate_right", [KEY_PERIOD], [JOY_BUTTON_DPAD_RIGHT])
	# The truck's handbrake, pulled up and left on (the truck has no indicators to work).
	_bind("handbrake", [KEY_J], [JOY_BUTTON_DPAD_RIGHT])
	_bind("headlight", [KEY_L], [JOY_BUTTON_DPAD_UP])
	# Ping while riding or driving (the left stick's press is the horn: no pad button spare).
	_bind("ride_ping", [KEY_G], [], [MOUSE_BUTTON_MIDDLE])
	# Drop a camera at the roadside ahead and watch yourself ride past (no pad button spare).
	_bind("ride_by", [KEY_V], [])
	_bind("telemetry", [KEY_F3], [])
	# The sat nav's map on the HUD, and an adjustable screen up and down on the move.
	_bind("satnav_hud", [KEY_M], [])
	_bind("satnav_zoom_in", [KEY_EQUAL, KEY_KP_ADD], [])
	_bind("satnav_zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT], [])
	_bind("satnav_satellite", [KEY_BRACKETRIGHT], [])
	_bind("satnav_portrait", [KEY_BRACKETLEFT], [])
	# Out on an adventure: the paper map of the whole route, once you have stopped.
	_bind("paper_map", [KEY_TAB], [])
	# The camera for the Adventure Diary: a photo (held, a clip), and on foot holding it up to your eye.
	_bind("photo", [KEY_K], [])
	_bind("photo_camera", [KEY_L], [])
	# A ten-second film, saved as a video (see MovieClip): the key beside L. Every pad button's taken.
	_bind("movie", [KEY_SEMICOLON], [])
	# The bike's radio out on an adventure: 0, as every letter's taken riding and the number keys are tools on foot.
	_bind("ride_radio", [KEY_0], [])
	_bind("screen_up", [KEY_PAGEUP], [])
	_bind("screen_down", [KEY_PAGEDOWN], [])
	_bind("stopwatch", [KEY_P], [JOY_BUTTON_DPAD_LEFT])
	# On foot in the shed
	_bind("move_forward", [KEY_W, KEY_UP], [])
	_bind("move_back", [KEY_S, KEY_DOWN], [])
	_bind("move_left", [KEY_A, KEY_LEFT], [])
	_bind("move_right", [KEY_D, KEY_RIGHT], [])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	# Space is the handbrake in the truck and the back brake on a bike; on foot it jumps.
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_B])
	_bind("act", [], [JOY_BUTTON_A], [MOUSE_BUTTON_LEFT])
	_bind("tool_next", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [MOUSE_BUTTON_WHEEL_DOWN])
	_bind("tool_prev", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [MOUSE_BUTTON_WHEEL_UP])
	for i in 9:
		_bind("tool_%d" % (i + 1), [KEY_1 + i], [])
	_bind("spray_colour", [KEY_R], [JOY_BUTTON_X], [MOUSE_BUTTON_RIGHT])
	# The finish is T or the mouse's back side button: the middle button is ping's.
	_bind("spray_finish", [KEY_T], [JOY_BUTTON_B], [MOUSE_BUTTON_XBUTTON1])
	# Point at something and ping it for the crew to see.
	_bind("ping", [KEY_G], [JOY_BUTTON_DPAD_RIGHT], [MOUSE_BUTTON_MIDDLE])
	# Emotes the rest of the crew sees: B opens the bar, F5 to F10 do one straight away.
	_bind("emote_menu", [KEY_B], [])
	_bind("emote_wave", [KEY_F5], [])
	_bind("emote_thumbs", [KEY_F6], [])
	_bind("emote_point", [KEY_F7], [])
	_bind("emote_shrug", [KEY_F8], [])
	_bind("emote_cheer", [KEY_F9], [])
	_bind("emote_dance", [KEY_F10], [])
	_bind("rename", [KEY_N], [])
	# Looking at any bike: order one of these, or copy its blueprint (see BikeCopy). No pad button spare.
	_bind("order_bike", [KEY_O], [])
	# At the sandblaster's gloves: scan the engine for what's still to blast.
	_bind("blast_scan", [KEY_X], [JOY_BUTTON_DPAD_UP])
	# Turn a part in your hands, equipment you're carrying, a poster before you hang it or a
	# picture on the whiteboard: , and . (the < and > keys); View on a pad turns it right.
	_bind("rotate_left", [KEY_COMMA], [])
	_bind("rotate_right", [KEY_PERIOD], [JOY_BUTTON_BACK])
	# Switches the rotate keys between quarter turns and turning freely to any angle.
	_bind("rotate_free", [KEY_SLASH], [])
	# Hold to scrap the equipment you're carrying or the part in your hands, for good.
	_bind("scrap", [KEY_DELETE], [JOY_BUTTON_DPAD_DOWN])
	# The second work button: drains fluids into a held container.
	_bind("alt_act", [KEY_R], [JOY_BUTTON_X], [MOUSE_BUTTON_RIGHT])
	_bind("crouch", [KEY_C, KEY_CTRL], [JOY_BUTTON_RIGHT_STICK])
	# First or third person on foot. C (the riding camera key) crouches on foot, so it's the key
	# beside it; on a pad it's View, which only turns things while you hold or carry them.
	_bind("walk_camera", [KEY_V], [JOY_BUTTON_BACK])
	# At the whiteboard: write a line of text, undo your last mark (Z or Ctrl+Z), hold to wipe it.
	_bind("board_text", [KEY_T], [])
	_bind("board_undo", [KEY_Z], [JOY_BUTTON_DPAD_LEFT])
	_bind("board_wipe", [KEY_X], [])
	_bind("board_colour", [], [JOY_BUTTON_B])
	# Pictures from your PC on the board: add one, move it about and size it.
	_bind("board_image", [KEY_U], [])
	_bind("board_move", [KEY_M], [JOY_BUTTON_DPAD_UP])
	_bind("board_bigger", [KEY_EQUAL, KEY_KP_ADD], [])
	_bind("board_smaller", [KEY_MINUS, KEY_KP_SUBTRACT], [])
	# Turn what's on the board into a poster to order from the parts computer.
	_bind("board_poster", [KEY_K], [JOY_BUTTON_DPAD_DOWN])
	# Geometry mode: fit a bike's parts with move, rotate and scale handles, Blender style.
	_bind("geometry_mode", [KEY_F2], [])
	# The performance profiler (see PerfOverlay), and a recording of it to send in.
	_bind("perf_overlay", [KEY_F4], [])
	_bind("perf_record", [KEY_F11], [])
	_bind("geo_move", [KEY_W], [])
	_bind("geo_rotate", [KEY_E], [])
	_bind("geo_scale", [KEY_R], [])
	_bind("geo_snap", [KEY_CTRL], [])
	_bind("geo_undo", [KEY_Z], [])
	_bind("geo_reset", [KEY_BACKSPACE], [])
	# Both
	_bind("interact", [KEY_F], [JOY_BUTTON_Y])
	# The visor: every letter is taken on foot or on the bike, so the apostrophe key, by Enter.
	_bind("visor", [KEY_APOSTROPHE], [])
	_bind("menu", [KEY_ESCAPE], [JOY_BUTTON_START])


func _bind(action: String, keys: Array, buttons: Array, mouse := []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.device = -1   # any controller, not just the first one Windows lists
		ev.button_index = button
		InputMap.action_add_event(action, ev)
	for button in mouse:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)


## The pad works the menus too: A presses the button in focus and B goes back. (Godot's own
## ui_accept and ui_cancel only have keys; the d-pad and left stick already move the focus.)
func _pad_ui() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var ev := InputEventJoypadButton.new()
		ev.device = -1
		ev.button_index = pair[1]
		InputMap.action_add_event(pair[0], ev)


# ---------------------------------------------------------------------------- rebinding

## Whether an event is a gamepad button (as opposed to a key or mouse button).
static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton


## The action's bindings as saved: "key:<physical keycode>", "mouse:<button>", "joy:<button>".
func binding_codes(action: String) -> PackedStringArray:
	return _codes_of(InputMap.action_get_events(action) if InputMap.has_action(action) else [])


static func _codes_of(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for ev in events:
		var c := code_of(ev)
		if c != "":
			out.append(c)
	return out


static func code_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return "key:%d" % k
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "joy:%d" % ev.button_index
	return ""


static func event_of(code: String) -> InputEvent:
	var bits := code.split(":")
	if bits.size() != 2 or not bits[1].is_valid_int():
		return null
	var n := int(bits[1])
	match bits[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = n as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = n as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.device = -1
			j.button_index = n as JoyButton
			return j
	return null


func _set_events(action: String, codes) -> void:
	InputMap.action_erase_events(action)
	for c in codes:
		var ev := event_of(str(c))
		if ev:
			InputMap.action_add_event(action, ev)


## The action's keys and mouse buttons (pad = false) or its pad buttons (pad = true).
func events_of(action: String, pad: bool) -> Array:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action).filter(func(e): return code_of(e) != "" and is_pad(e) == pad)


## Puts `ev` on `action` in place of its keyboard and mouse bindings (or its pad button), and saves.
func rebind(action: String, ev: InputEvent) -> void:
	var code := code_of(ev)
	if code == "" or not InputMap.has_action(action):
		return
	var keep := InputMap.action_get_events(action).filter(func(e): return code_of(e) != "" and is_pad(e) != is_pad(ev))
	InputMap.action_erase_events(action)
	for e in keep:
		InputMap.action_add_event(action, e)
	InputMap.action_add_event(action, event_of(code))
	save_settings()


## Takes the action's keyboard and mouse (or pad) bindings off, and saves.
func clear_binding(action: String, pad: bool) -> void:
	for e in events_of(action, pad):
		InputMap.action_erase_event(action, e)
	save_settings()


## Every action back to how the game comes, and saves.
func reset_bindings() -> void:
	for action in _defaults:
		InputMap.action_erase_events(action)
		for e in _defaults[action]:
			InputMap.action_add_event(action, e)
	save_settings()


static func action_name(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


static func _contexts(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			var out: Array = a[2].duplicate()
			for c in a[2]:
				out.append_array(CONTEXT_ALSO.get(c, []))
			return out
	return []


## Keys or buttons that do two things at once: [{a, b, code, context}].
func clashes() -> Array:
	var out := []
	for i in ACTIONS.size():
		var a: String = ACTIONS[i][0]
		var ca := _contexts(a)
		var mine := binding_codes(a)
		for j in range(i + 1, ACTIONS.size()):
			var b: String = ACTIONS[j][0]
			if SHARED_OK.has([a, b]) or SHARED_OK.has([b, a]):
				continue
			var shared := ""
			for c in _contexts(b):
				if ca.has(c):
					shared = c
					break
			if shared == "":
				continue
			for code in binding_codes(b):
				if mine.has(code):
					out.append({"a": a, "b": b, "code": code, "context": shared})
	return out


## "R is also Spray colour (on foot)" for each clash `action` is in, from `found` (see clashes()).
func clash_text(action: String, found := []) -> String:
	var lines := []
	for c in (found if not found.is_empty() else clashes()):
		if c["a"] == action or c["b"] == action:
			var other: String = c["b"] if c["a"] == action else c["a"]
			lines.append("%s is also %s (%s)" % [code_text(c["code"]), action_name(other), CONTEXT_NAMES[c["context"]]])
	return ", ".join(lines)


const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right", JOY_BUTTON_MISC1: "Share"}
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down", MOUSE_BUTTON_WHEEL_LEFT: "Wheel left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right", MOUSE_BUTTON_XBUTTON1: "Mouse back", MOUSE_BUTTON_XBUTTON2: "Mouse forward"}


## A binding as a player reads it: "G", "Middle mouse", "D-pad right".
static func code_text(code: String) -> String:
	var ev := event_of(code)
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventMouseButton:
		var mb: int = (ev as InputEventMouseButton).button_index
		return str(MOUSE_NAMES.get(mb, "Mouse %d" % mb))
	if ev is InputEventJoypadButton:
		var jb: int = (ev as InputEventJoypadButton).button_index
		return str(PAD_NAMES.get(jb, "Button %d" % jb))
	return "?"


## The action's keyboard and mouse (or pad) bindings as text, "" when it has none.
func binding_text(action: String, pad: bool) -> String:
	return " / ".join(events_of(action, pad).map(func(e): return code_text(code_of(e))))
