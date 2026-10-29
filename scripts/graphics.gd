class_name Graphics
extends CanvasLayer
## Applies the graphics settings (Settings.gfx_*) to the game window, the main viewport and
## the camera: window mode, resolution, monitor, VSync, frame-rate cap, render scale and
## upscaler (FSR 2.2, FSR 1, bilinear, or off for the native resolution), anti-aliasing, mesh
## detail, texture filtering, draw distance, field of view and whether people's figures cast
## shadows. Also draws the FPS counter. Settings adds one of these as its child at start-up and
## it re-applies whenever Settings.graphics_changed fires.
## The lighting (GI, volumetric fog, clouds, SSR, SSAO, glow, shadows, brightness) is applied
## to the environment by the lighting code, from the same settings, and the ridden bike's live
## mirrors (Mirror detail) by BikeMirrors.
##
## The rendering driver (Vulkan or DirectX 12) can only be picked before the renderer starts,
## so it's written to OVERRIDE_PATH, which project.godot names as its settings override
## (application/config/project_settings_override): Godot reads it at the next launch.

## Engine checks done for Godot 4.6.2 (no DLSS, XeSS, ray tracing or HDR display output):
## Viewport.scaling_3d_mode has BILINEAR, FSR (1.0), FSR2 (2.2) and MetalFX (Apple only);
## Viewport.screen_space_aa has FXAA and SMAA; D3D12 is in the official Windows export
## templates, and rendering_device/fallback_to_vulkan (on by default) falls back if it fails.

const OVERRIDE_PATH := "user://graphics_override.cfg"
const DRIVER_KEY := "rendering_device/driver.windows"

## Room lamps (the shed's, the side rooms', the cafe's: lights reaching no further than
## ROOM_LIGHT_RANGE) fade out past LIGHT_FADE metres from the camera, and their shadows past
## SHADOW_FADE: from across the yard or the road you don't see a lamp's light inside, but each
## one in view still drew its shadow map whenever anything under it moved.
const ROOM_LIGHT_RANGE := 20.0
const LIGHT_FADE := 70.0
const SHADOW_FADE := 30.0

## Common 16:9, 16:10 and 21:9 sizes, up to 4K.
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1440, 900),
	Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1080),
	Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 1600), Vector2i(3840, 2160)]
const FPS_CAPS := [30, 60, 120, 144, 165, 240, 0]   # 0 = unlimited
const QUALITY := ["low", "medium", "high", "ultra"]
## The mirror detail slider's steps, left to right (see BikeMirrors.LEVELS).
const MIRROR_LEVELS := ["off", "low", "medium", "high", "ultra"]

## The allowed values of every option setting (anything else in a settings file is ignored).
const CHOICES := {
	"gfx_preset": ["low", "medium", "high", "ultra", "custom"],
	"gfx_window_mode": ["windowed", "borderless", "fullscreen"],
	"gfx_vsync": ["off", "on", "adaptive", "mailbox"],
	"gfx_upscaler": ["fsr2", "fsr1", "bilinear", "off"],
	"gfx_msaa": ["off", "2x", "4x", "8x"],
	"gfx_screen_aa": ["off", "fxaa", "smaa"],
	"gfx_detail": QUALITY,
	"gfx_shadows": QUALITY,
	"gfx_gi": ["off", "ssil", "sdfgi"],
	"gfx_volumetrics": ["off", "low", "high"],
	"gfx_clouds": MIRROR_LEVELS,
	"gfx_driver": ["vulkan", "d3d12"],
	"gfx_mirrors": MIRROR_LEVELS,
}
## [min, max] of the number settings.
const RANGES := {
	"gfx_fov": [60.0, 110.0], "gfx_brightness": [0.5, 1.5], "gfx_render_scale": [0.5, 2.0],
	"gfx_sharpness": [0.0, 1.0], "gfx_draw_distance": [0.5, 2.0], "gfx_monitor": [-1, 15], "gfx_bloom": [0.0, 2.0],
}

## What each preset sets. Changing any of these keys by hand makes the preset "custom".
const PRESETS := {
	"low": {"gfx_shadows": "low", "gfx_detail": "low", "gfx_draw_distance": 0.6, "gfx_gi": "off",
		"gfx_volumetrics": "off", "gfx_clouds": "low", "gfx_ssr": false, "gfx_ssao": false, "gfx_glow": true,
		"gfx_msaa": "off", "gfx_taa": false, "gfx_screen_aa": "fxaa", "gfx_render_scale": 0.75, "gfx_upscaler": "fsr1",
		"gfx_mirrors": "off"},
	"medium": {"gfx_shadows": "medium", "gfx_detail": "medium", "gfx_draw_distance": 0.8, "gfx_gi": "ssil",
		"gfx_volumetrics": "low", "gfx_clouds": "medium", "gfx_ssr": false, "gfx_ssao": true, "gfx_glow": true,
		"gfx_msaa": "off", "gfx_taa": false, "gfx_screen_aa": "fxaa", "gfx_render_scale": 1.0, "gfx_upscaler": "fsr2",
		"gfx_mirrors": "low"},
	"high": {"gfx_shadows": "high", "gfx_detail": "high", "gfx_draw_distance": 1.0, "gfx_gi": "sdfgi",
		"gfx_volumetrics": "high", "gfx_clouds": "high", "gfx_ssr": true, "gfx_ssao": true, "gfx_glow": true,
		"gfx_msaa": "2x", "gfx_taa": false, "gfx_screen_aa": "fxaa", "gfx_render_scale": 1.0, "gfx_upscaler": "fsr2",
		"gfx_mirrors": "medium"},
	"ultra": {"gfx_shadows": "ultra", "gfx_detail": "ultra", "gfx_draw_distance": 1.5, "gfx_gi": "sdfgi",
		"gfx_volumetrics": "high", "gfx_clouds": "ultra", "gfx_ssr": true, "gfx_ssao": true, "gfx_glow": true,
		"gfx_msaa": "4x", "gfx_taa": true, "gfx_screen_aa": "smaa", "gfx_render_scale": 1.0, "gfx_upscaler": "fsr2",
		"gfx_mirrors": "ultra"},
}

## Mesh LOD threshold in pixels (lower keeps the detailed meshes further away) and texture
## anisotropy for each detail level.
const LOD_THRESHOLD := {"low": 4.0, "medium": 2.0, "high": 1.0, "ultra": 0.5}
const ANISOTROPY := {"low": Viewport.ANISOTROPY_2X, "medium": Viewport.ANISOTROPY_4X,
	"high": Viewport.ANISOTROPY_8X, "ultra": Viewport.ANISOTROPY_16X}
const MSAA := {"off": Viewport.MSAA_DISABLED, "2x": Viewport.MSAA_2X, "4x": Viewport.MSAA_4X, "8x": Viewport.MSAA_8X}
const SCREEN_AA := {"off": Viewport.SCREEN_SPACE_AA_DISABLED, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
	"smaa": Viewport.SCREEN_SPACE_AA_SMAA}
const VSYNC := {"off": DisplayServer.VSYNC_DISABLED, "on": DisplayServer.VSYNC_ENABLED,
	"adaptive": DisplayServer.VSYNC_ADAPTIVE, "mailbox": DisplayServer.VSYNC_MAILBOX}
## The field of view the cameras were tuned for; the slider shifts them all by the difference.
const BASE_FOV := 75.0
## Every mesh of a person's figure (players on foot and riding, staff, customers, townsfolk):
## the "Avatar shadow" setting turns their shadows off (see avatar_mesh).
const AVATAR_GROUP := "avatar_mesh"

## The driver Settings had when the game started: a different one now needs a restart.
var driver_at_start := ""
var _fps: Label
var _window_key := ""   # the display settings last put on the window, so other changes don't move it


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(func(n: Node):
		if n is OmniLight3D or n is SpotLight3D:
			fade_room_light.call_deferred(n))
	driver_at_start = Settings.gfx_driver
	_fps = Label.new()
	_fps.add_theme_font_size_override("font_size", 15)
	_fps.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	# Top left: the money and level panels sit top right.
	_fps.position = Vector2(10.0, 6.0)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps)
	Settings.graphics_changed.connect(apply)
	# A size or mode given on the command line (tests, screenshots) wins over the saved one.
	var args := OS.get_cmdline_args()
	if args.has("--resolution") or args.has("--fullscreen") or args.has("--windowed") or args.has("-f") or args.has("-w"):
		_window_key = _display_key()
	apply()


## Puts every graphics setting into effect (except the driver, which needs a restart).
func apply() -> void:
	apply_viewport(get_tree().root)
	apply_avatar_shadows(get_tree())
	if not is_headless():
		DisplayServer.window_set_vsync_mode(VSYNC.get(Settings.gfx_vsync, DisplayServer.VSYNC_ENABLED))
		Engine.max_fps = Settings.gfx_fps_cap
		var key := _display_key()
		if key != _window_key:
			_window_key = key
			apply_window(get_window())
	_fps.visible = Settings.gfx_fps_counter


func _display_key() -> String:
	return "%s|%s|%d" % [Settings.gfx_window_mode, Settings.gfx_resolution, Settings.gfx_monitor]


## Anti-aliasing, render scale and upscaler, mesh detail and texture filtering on `vp`.
static func apply_viewport(vp: Viewport) -> void:
	vp.msaa_3d = MSAA.get(Settings.gfx_msaa, Viewport.MSAA_2X)
	vp.screen_space_aa = SCREEN_AA.get(Settings.gfx_screen_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	# Upscaler off: always the screen's own resolution, nothing scaled.
	var scale := 1.0 if Settings.gfx_upscaler == "off" else render_scale(vp)
	var mode := scaling_mode(Settings.gfx_upscaler, scale)
	vp.scaling_3d_mode = mode
	vp.scaling_3d_scale = scale
	# FSR 2.2 does its own temporal anti-aliasing, so TAA would only blur it twice.
	vp.use_taa = Settings.gfx_taa and mode != Viewport.SCALING_3D_MODE_FSR2
	vp.fsr_sharpness = fsr_sharpness(Settings.gfx_sharpness)
	var lod: float = LOD_THRESHOLD.get(Settings.gfx_detail, 1.0)
	vp.mesh_lod_threshold = lod / clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	vp.anisotropic_filtering_level = ANISOTROPY.get(Settings.gfx_detail, Viewport.ANISOTROPY_8X)


## The 3D render scale: the render-scale slider and, in fullscreen, the chosen resolution
## against the screen's own (the menus stay sharp at the screen's size).
static func render_scale(vp: Viewport) -> float:
	var scale := clampf(Settings.gfx_render_scale, 0.5, 2.0)
	if Settings.gfx_window_mode != "windowed" and vp is Window:
		var screen := DisplayServer.screen_get_size((vp as Window).current_screen)
		var res := parse_resolution(Settings.gfx_resolution)
		if screen.y > 0 and res.y > 0:
			scale *= float(res.y) / float(screen.y)
	return clampf(scale, 0.25, 2.0)


## The Viewport scaling mode for an upscaler and scale. At 100% (or with the upscaler off)
## nothing is scaled; above 100% (supersampling) only bilinear works, and the FSR upscalers are
## for scaling up only.
static func scaling_mode(upscaler: String, scale: float) -> int:
	if scale >= 0.995 or upscaler == "off":
		return Viewport.SCALING_3D_MODE_BILINEAR
	match upscaler:
		"fsr2":
			return Viewport.SCALING_3D_MODE_FSR2
		"fsr1":
			return Viewport.SCALING_3D_MODE_FSR
	return Viewport.SCALING_3D_MODE_BILINEAR


## The slider's 0 (soft) to 1 (sharpest) as FSR's sharpness, where 0 is sharpest and 2 softest.
static func fsr_sharpness(slider: float) -> float:
	return 2.0 * (1.0 - clampf(slider, 0.0, 1.0))


## Window mode, size and monitor.
func apply_window(w: Window) -> void:
	var screens := DisplayServer.get_screen_count()
	var mon := Settings.gfx_monitor
	if mon >= 0 and mon < screens and mon != w.current_screen:
		if w.mode != Window.MODE_WINDOWED:
			w.mode = Window.MODE_WINDOWED
		w.current_screen = mon
	match Settings.gfx_window_mode:
		"borderless":
			w.mode = Window.MODE_FULLSCREEN
		"fullscreen":
			w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			if w.mode != Window.MODE_WINDOWED:
				w.mode = Window.MODE_WINDOWED
			var scr := w.current_screen
			var usable := DisplayServer.screen_get_usable_rect(scr)
			var want := parse_resolution(Settings.gfx_resolution)
			if usable.size.x > 0:
				want = want.min(usable.size)
			w.size = want
			w.position = usable.position + (usable.size - want) / 2
	# The fullscreen render scale depends on the screen it ended up on.
	apply_viewport(w)


func _process(_delta: float) -> void:
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("graphics", pt)


func _process_body(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Draw distance: the camera's own far plane times the slider.
		if not cam.has_meta("gfx_base_far"):
			cam.set_meta("gfx_base_far", cam.far)
		var base: float = cam.get_meta("gfx_base_far")
		cam.far = base * clampf(Settings.gfx_draw_distance, 0.5, 2.0)
		if cam.is_in_group("gfx_fov"):
			cam.fov = Settings.gfx_fov
	if _fps.visible:
		_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]


## Makes a room lamp fade out at a distance (see LIGHT_FADE); other lights are left alone.
static func fade_room_light(node) -> void:
	if not is_instance_valid(node) or not (node is Light3D) or (node as Light3D).distance_fade_enabled:
		return
	var light := node as Light3D
	var reach := (light as OmniLight3D).omni_range if light is OmniLight3D else (light as SpotLight3D).spot_range
	if reach > ROOM_LIGHT_RANGE:
		return
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE
	light.distance_fade_length = 20.0
	light.distance_fade_shadow = SHADOW_FADE


## Marks `gi` as part of a person's figure, so the Avatar shadow setting decides whether it casts
## a shadow (its own shadow setting is kept for when it's on). Returns it.
static func avatar_mesh(gi: GeometryInstance3D) -> GeometryInstance3D:
	if not gi.has_meta("avatar_cast"):
		gi.set_meta("avatar_cast", gi.cast_shadow)
	gi.add_to_group(AVATAR_GROUP)
	_avatar_cast(gi)
	return gi


## Marks every mesh under `root` (and `root` itself) as part of a person's figure (avatar_mesh).
static func avatar_meshes(root: Node) -> void:
	if root is GeometryInstance3D:
		avatar_mesh(root)
	for c in root.get_children():
		avatar_meshes(c)


## Puts the Avatar shadow setting on every figure's meshes in `tree`.
static func apply_avatar_shadows(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(AVATAR_GROUP):
		_avatar_cast(n as GeometryInstance3D)


static func _avatar_cast(gi: GeometryInstance3D) -> void:
	if gi == null:
		return
	gi.cast_shadow = int(gi.get_meta("avatar_cast", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)) if Settings.gfx_avatar_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## How much the field-of-view slider moves the cameras off what they were tuned for.
static func fov_offset() -> float:
	return clampf(Settings.gfx_fov, 60.0, 110.0) - BASE_FOV


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## "1920x1080" -> Vector2i(1920, 1080); a bad string gives 1600x900.
static func parse_resolution(text: String) -> Vector2i:
	var bits := text.to_lower().split("x")
	if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
		var r := Vector2i(int(bits[0]), int(bits[1]))
		if r.x >= 640 and r.y >= 360 and r.x <= 3840 and r.y <= 2160:
			return r
	return Vector2i(1600, 900)


static func resolution_text(r: Vector2i) -> String:
	return "%dx%d" % [r.x, r.y]


## "16:9", "16:10" or "21:9" (and so on) for a resolution.
static func aspect_text(r: Vector2i) -> String:
	var a := float(r.x) / float(r.y)
	if absf(a - 16.0 / 9.0) < 0.02:
		return "16:9"
	if absf(a - 1.6) < 0.02:
		return "16:10"
	if a > 2.2:
		return "21:9"
	return "%.2f:1" % a


# ---------------------------------------------------------------------------- driver

## Writes the rendering driver for the next start to the settings override file (`path`).
## "d3d12" picks DirectX 12 on Windows; anything else Vulkan. If DirectX 12 won't start,
## Godot falls back to Vulkan by itself (rendering_device/fallback_to_vulkan).
static func write_driver_override(driver: String, path := OVERRIDE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)   # keep anything else in it
	cfg.set_value("rendering", DRIVER_KEY, "d3d12" if driver == "d3d12" else "vulkan")
	cfg.set_value("rendering", "rendering_device/fallback_to_vulkan", true)
	return cfg.save(path)


## The driver the game is running on now: "vulkan", "d3d12", "opengl3" or "" headless.
static func current_driver() -> String:
	return RenderingServer.get_current_rendering_driver_name()


static func driver_name(driver: String) -> String:
	return {"vulkan": "Vulkan", "d3d12": "DirectX 12", "opengl3": "OpenGL (compatibility)"}.get(driver, driver)


## A line for the menu about the driver: restart needed, fell back, or what's running.
func driver_note() -> String:
	var now := current_driver()
	if Settings.gfx_driver != driver_at_start:
		return "Restart the game to switch to %s." % driver_name(Settings.gfx_driver)
	if OS.get_name() != "Windows":
		return "DirectX 12 is for Windows only. Running on %s." % driver_name(now)
	if Settings.gfx_driver == "d3d12" and now != "d3d12" and now != "":
		return "DirectX 12 couldn't start on this PC, so the game fell back to %s." % driver_name(now)
	return "Running on %s." % driver_name(now) if now != "" else ""
