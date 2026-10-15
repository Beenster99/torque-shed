class_name GraphicsTab
extends VBoxContainer
## The Esc menu's Graphics tab: a quality preset, then display, upscaling, anti-aliasing,
## lighting and detail options and the rendering driver. Every change goes through
## Settings.set_graphics (which marks the preset Custom) and takes effect straight away,
## except the driver, which needs a restart. Saved with the rest of the settings.

const LABEL_WIDTH := 250.0
const NOTE_COLOR := Color(1, 1, 1, 0.55)

## key -> {"kind": "option" / "slider" / "check", "control": Control, "values": Array, "text": Label}
var _controls := {}
var _rt: CheckBox
var _scale_note: Label
var _window_note: Label
var _driver_note: Label
var _monitor_row: Control


func _ready() -> void:
	name = "Graphics"
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.add_child(_label("Quality preset"))
	var preset := _option_button("gfx_preset", [["low", "Low"], ["medium", "Medium"], ["high", "High"],
		["ultra", "Ultra"], ["custom", "Custom"]])
	top.add_child(preset)
	var help := UITheme.label("Changing any option below makes it Custom.", 14, NOTE_COLOR)
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(help)
	add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	_build_display(body)
	_build_upscaling(body)
	_build_aa(body)
	_build_quality(body)
	_build_driver(body)
	Settings.graphics_changed.connect(refresh)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func _build_display(body: VBoxContainer) -> void:
	body.add_child(UITheme.title("Display", 20))
	_option(body, "gfx_window_mode", "Window mode", [["windowed", "Windowed"],
		["borderless", "Borderless fullscreen"], ["fullscreen", "Exclusive fullscreen"]])
	var res := []
	for r in Graphics.RESOLUTIONS:
		res.append([Graphics.resolution_text(r), "%d x %d  (%s)" % [r.x, r.y, Graphics.aspect_text(r)]])
	_option(body, "gfx_resolution", "Resolution", res)
	_window_note = _note(body, "")
	var screens := [[-1, "Where the window opens"]]
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		screens.append([i, "Screen %d  (%d x %d)" % [i + 1, s.x, s.y]])
	_monitor_row = _option(body, "gfx_monitor", "Monitor", screens)
	_option(body, "gfx_vsync", "VSync", [["off", "Off"], ["on", "On"],
		["adaptive", "Adaptive (tears only when slow)"], ["mailbox", "Mailbox (triple buffered)"]])
	var caps := []
	for c in Graphics.FPS_CAPS:
		caps.append([c, "Unlimited" if c == 0 else "%d FPS" % c])
	_option(body, "gfx_fps_cap", "Frame-rate cap", caps)
	_slider(body, "gfx_fov", "Field of view", 60.0, 110.0, 1.0, func(v): return "%d degrees" % roundi(v))
	_slider(body, "gfx_brightness", "Brightness", 0.5, 1.5, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_check(body, "gfx_fps_counter", "Show the frame rate (top left corner)")


func _build_upscaling(body: VBoxContainer) -> void:
	body.add_child(UITheme.title("Upscaling", 20))
	_slider(body, "gfx_render_scale", "Render scale", 0.5, 2.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_option(body, "gfx_upscaler", "Upscaler", [["fsr2", "AMD FSR 2.2 (temporal, best looking)"],
		["fsr1", "AMD FSR 1.0 (spatial, fastest)"], ["bilinear", "Bilinear (plain stretch)"]])
	_slider(body, "gfx_sharpness", "Sharpness", 0.0, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_scale_note = _note(body, "")
	_note(body, "DLSS and XeSS: not available. The Godot engine this game is built on (4.6) doesn't include "
		+ "NVIDIA DLSS or Intel XeSS. AMD FSR 2.2 is its temporal upscaler and works on NVIDIA, AMD and Intel cards alike.")


func _build_aa(body: VBoxContainer) -> void:
	body.add_child(UITheme.title("Anti-aliasing", 20))
	_option(body, "gfx_msaa", "MSAA (smooth edges)", [["off", "Off"], ["2x", "2x"], ["4x", "4x"], ["8x", "8x"]])
	_check(body, "gfx_taa", "TAA: temporal anti-aliasing (smoothest, a little soft; FSR 2.2 does its own)")
	_option(body, "gfx_screen_aa", "Screen-space AA", [["off", "Off"], ["fxaa", "FXAA (fast)"], ["smaa", "SMAA (sharper)"]])


func _build_quality(body: VBoxContainer) -> void:
	body.add_child(UITheme.title("Quality", 20))
	var levels := [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]]
	_option(body, "gfx_shadows", "Shadows", levels)
	_option(body, "gfx_detail", "Detail level (meshes, textures)", levels)
	_slider(body, "gfx_draw_distance", "Draw distance", 0.5, 2.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_option(body, "gfx_gi", "Global illumination", [["off", "Off"], ["ssil", "SSIL (screen-space bounce light)"],
		["sdfgi", "SDFGI (real-time global illumination)"]])
	_rt = CheckBox.new()
	_rt.text = "Ray-traced lighting (uses SDFGI)"
	_rt.toggled.connect(func(v): Settings.set_graphics("gfx_gi", "sdfgi" if v else "ssil"))
	body.add_child(_rt)
	_note(body, "Godot 4.6 has no hardware ray tracing (RTX / DXR). Its best lighting is SDFGI, real-time global "
		+ "illumination that bounces sun, sky and lamp light around the shed, so this switch turns SDFGI on (off uses SSIL).")
	var vol := [["off", "Off"], ["low", "Low"], ["high", "High"]]
	_option(body, "gfx_volumetrics", "Volumetric fog and light", vol)
	_option(body, "gfx_clouds", "Volumetric clouds", vol)
	_check(body, "gfx_ssr", "Screen-space reflections")
	_check(body, "gfx_ssao", "Ambient occlusion (SSAO)")
	_check(body, "gfx_glow", "Glow and bloom")
	var blur := CheckBox.new()
	blur.text = "Motion blur (the game has none, so it's always off)"
	blur.disabled = true
	body.add_child(blur)
	_note(body, "HDR: the game always renders in HDR inside and tone-maps it for your screen; HDR displays "
		+ "(HDR10 output) aren't supported by the engine yet.")


func _build_driver(body: VBoxContainer) -> void:
	body.add_child(UITheme.title("Rendering driver", 20))
	var row := _option(body, "gfx_driver", "Graphics API", [["vulkan", "Vulkan"], ["d3d12", "DirectX 12 (Windows)"]])
	if OS.get_name() != "Windows":
		var ob: OptionButton = _controls["gfx_driver"]["control"]
		ob.set_item_disabled(1, true)
	row.tooltip_text = "Takes effect the next time the game starts."
	_driver_note = _note(body, "")
	_note(body, "The driver is picked when the game starts: restart to apply. If DirectX 12 won't start, "
		+ "the game falls back to Vulkan by itself.")


## Puts every control back in step with Settings (without firing their signals).
func refresh() -> void:
	for k in _controls:
		var c: Dictionary = _controls[k]
		var v = Settings.get(k)
		match c["kind"]:
			"option":
				var ob: OptionButton = c["control"]
				var values: Array = c["values"]
				ob.set_block_signals(true)
				ob.selected = values.find(v)
				ob.set_block_signals(false)
			"slider":
				var s: HSlider = c["control"]
				s.set_value_no_signal(float(v))
				var fmt: Callable = c["fmt"]
				(c["text"] as Label).text = fmt.call(float(v))
			"check":
				(c["control"] as CheckBox).set_pressed_no_signal(bool(v))
	_rt.set_pressed_no_signal(Settings.gfx_gi == "sdfgi")
	var scale := Settings.gfx_render_scale
	_scale_note.text = "At 100% the 3D view renders at full resolution and no upscaler runs." if absf(scale - 1.0) < 0.005 \
		else ("Above 100% the game renders bigger and shrinks it down (supersampling, very sharp but slow; bilinear only)."
			if scale > 1.0 else "Below 100% the 3D view renders smaller and the upscaler brings it back up (faster).")
	_window_note.text = "Windowed: the window's size (no bigger than your screen)." if Settings.gfx_window_mode == "windowed" \
		else "Fullscreen: the screen keeps its own size; this sets how sharp the 3D view renders, with the menus kept crisp."
	_monitor_row.visible = DisplayServer.get_screen_count() > 1
	var g := _graphics()
	_driver_note.text = g.driver_note() if g else ""


func _graphics() -> Graphics:
	for c in Settings.get_children():
		if c is Graphics:
			return c
	return null


# ---------------------------------------------------------------------------- building blocks

func _label(text: String) -> Label:
	var l := UITheme.label(text, 15)
	l.custom_minimum_size.x = LABEL_WIDTH
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _note(body: VBoxContainer, text: String) -> Label:
	var l := UITheme.label(text, 14, NOTE_COLOR)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 640.0
	body.add_child(l)
	return l


func _row(body: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label(text))
	body.add_child(row)
	return row


## An OptionButton for `key` from [value, text] pairs.
func _option_button(key: String, items: Array) -> OptionButton:
	var ob := OptionButton.new()
	var values := []
	for it in items:
		ob.add_item(str(it[1]))
		values.append(it[0])
	ob.item_selected.connect(func(i): Settings.set_graphics(key, values[i]))
	_controls[key] = {"kind": "option", "control": ob, "values": values}
	return ob


func _option(body: VBoxContainer, key: String, text: String, items: Array) -> HBoxContainer:
	var row := _row(body, text)
	row.add_child(_option_button(key, items))
	return row


func _slider(body: VBoxContainer, key: String, text: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := _row(body, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 280.0
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v): Settings.set_graphics(key, v))
	row.add_child(s)
	var value := UITheme.label("", 15, NOTE_COLOR)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	_controls[key] = {"kind": "slider", "control": s, "text": value, "fmt": fmt}


func _check(body: VBoxContainer, key: String, text: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.toggled.connect(func(v): Settings.set_graphics(key, v))
	body.add_child(cb)
	_controls[key] = {"kind": "check", "control": cb}
