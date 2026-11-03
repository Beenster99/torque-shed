extends Node
## Pictures of the Bike shop's new-bike configurator, for visual checks:
##   xvfb-run godot --path . res://tests/shop_shots.tscn -- --out=/tmp/shots

var out_dir := "user://screenshots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Shed.start_new("Simon", 61)
	Progress.set_money(100000)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tab := BikeShopTab.new()
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.offset_left = 40
	tab.offset_top = 60
	tab.offset_right = -40
	tab.offset_bottom = -40
	add_child(tab)
	await _frames(5)
	tab._new_style("tourer")
	tab.show_mode("new")
	await _frames(40)
	await _shot("01_configurator")
	var cp: ColorPickerButton = tab.find_child("Colour_paint", true, false)
	if cp:
		var at: Vector2 = cp.get_global_rect().get_center()
		for down in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = down
			ev.position = at
			ev.global_position = at
			Input.parse_input_event(ev)
			await _frames(2)
		await _frames(10)
		await _shot("02_colour_popup")
		var picker := cp.get_picker()
		for c in [Color.RED, Color.ORANGE, Color.GOLD, Color.SEA_GREEN, Color.ROYAL_BLUE, Color.PURPLE, Color.WHITE, Color.DIM_GRAY, Color.BROWN, Color.PINK]:
			picker.add_recent_preset(c)
		_unfold(picker)
		# (and click the headings open, in case they aren't folding containers)
		for c in picker.find_children("*", "Button", true, false) + _all(picker):
			if c is Button and str((c as Button).text) in ["Swatches", "Recent Colors"] and not (c as Button).button_pressed:
				(c as Button).toggle_mode = (c as Button).toggle_mode
				(c as Button).pressed.emit()
				if (c as Button).toggle_mode:
					(c as Button).button_pressed = true
		await _frames(10)
		await _shot("03_colour_popup_open")
		cp.get_popup().hide()
		await _frames(5)
		cp = tab.find_child("Colour_mudguards", true, false)
		for c in [Color.RED, Color.ORANGE, Color.GOLD, Color.SEA_GREEN, Color.ROYAL_BLUE]:
			cp.get_picker().add_recent_preset(c)
		(tab._left.get_parent() as ScrollContainer).scroll_vertical = 10000
		await _frames(5)
		at = cp.get_global_rect().get_center()
		for down in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = down
			ev.position = at
			ev.global_position = at
			Input.parse_input_event(ev)
			await _frames(2)
		await _frames(5)
		for c in _all(cp.get_picker()):
			if c is Button and str((c as Button).text) in ["Swatches", "Recent Colors"] and not (c as Button).button_pressed:
				(c as Button).pressed.emit()
				if (c as Button).toggle_mode:
					(c as Button).button_pressed = true
		await _frames(10)
		var pp := cp.get_popup()
		print("DBG pop ", pp.position, pp.size, " min ", cp.get_picker().get_combined_minimum_size(), " contents ", pp.get_contents_minimum_size(), " max ", pp.max_size, " wrap ", pp.wrap_controls)
		await _shot("03b_mudguard_popup_open")
		cp.get_popup().hide()
	await _frames(5)
	tab._new_style("cafe")
	tab.show_mode("new")
	tab.set_part("panniers", "canvas_throwover")
	tab.set_part("top_box", "wooden_crate")
	tab.set_part("tail", "classic_mudguard")
	tab.set_colour("mudguards", Color(0.75, 0.1, 0.08))
	await _frames(40)
	await _shot("04_cafe_luggage_red_guards")
	tab.set_spinning(false)
	tab._preview.zoom_by(2.2)
	await _frames(20)
	await _shot("05_stopped_zoomed")
	get_tree().quit()


## Opens every folded section under `n` (the picker's Swatches and Recent colours).
func _unfold(n: Node) -> void:
	for c in n.get_children(true):
		if "folded" in c:
			c.set("folded", false)
		_unfold(c)


func _all(n: Node) -> Array:
	var out := []
	for c in n.get_children(true):
		out.append(c)
		out.append_array(_all(c))
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
