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
	# A cafe racer with its own badge, luggage and red mudguards.
	tab._new_style("cafe")
	tab.set_logo("wings")
	tab.badge["logo_color"] = Color(0.95, 0.78, 0.25)
	tab.set_brand("Bennett")
	tab.badge["brand_color"] = Color(0.95, 0.95, 0.92)
	tab.badge["logo_size"] = 1.3
	tab.badge["logo_y"] = 0.1
	tab.badge["brand_size"] = 0.8
	tab.badge["brand_x"] = 0.05
	tab.badge["brand_y"] = -0.15
	tab.badge["brand_font"] = "lobster"
	tab.show_mode("new")
	tab.set_part("panniers", "canvas_throwover")
	tab.set_part("tail", "classic_mudguard")
	tab.set_colour("front_mudguard", Color(0.75, 0.1, 0.08))
	tab.set_colour("tail", Color(0.75, 0.1, 0.08))
	tab.set_colour("tank", Color(0.1, 0.22, 0.5))
	await _frames(40)
	tab._preview.spinning = false
	tab._preview.pivot.rotation.y = -PI / 2.0 + 0.25
	await _frames(10)
	await _shot("02_cafe_badge")
	tab._preview.zoom_by(2.6)
	tab._preview.look = Vector2(-0.12, 0.18)
	tab._preview._clamp_look()
	tab._preview._place_camera()
	await _frames(10)
	await _shot("03_badge_close")
	tab._preview.pivot.rotation.y = PI / 2.0 - 0.25
	tab._preview.look = Vector2(0.12, 0.18)
	tab._preview._clamp_look()
	tab._preview._place_camera()
	await _frames(10)
	await _shot("03b_badge_close_other_side")
	tab._preview.reset_view()
	tab._preview.pivot.rotation.y = -PI / 2.0 + 0.25
	# The colour panel, with swatches and recent colours, from the lowest colour on the list.
	for c in [Color.RED, Color.ORANGE, Color.GOLD, Color.SEA_GREEN, Color.ROYAL_BLUE, Color.PURPLE]:
		ColourChoice.remember(c)
	(tab._left.get_parent() as ScrollContainer).scroll_vertical = 10000
	await _frames(5)
	var cp: ColourChoice = tab.find_child("Colour_brand", true, false)
	cp.open()
	await _frames(10)
	await _shot("04_colour_panel")
	cp._popup.hide()
	# Tyres: a sports rim at the back of a tourer, and the rear tyres that go on it.
	tab._new_style("tourer")
	tab.set_part("rear_wheel", "race_mag_gold")
	await _frames(20)
	(tab._left.get_parent() as ScrollContainer).scroll_vertical = 0
	await _frames(5)
	var ob: OptionButton = tab.find_child("Slot_rear_tyre", true, false)
	ob.show_popup()
	await _frames(10)
	await _shot("06_tyres")
	ob.get_popup().hide()
	# Every logo, side by side.
	var t0 := Time.get_ticks_msec()
	var sheet := Image.create(BikeBadge.SIZE * 5, BikeBadge.SIZE * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.16, 0.18))
	var i := 0
	for id in BikeBadge.LOGOS:
		BikeBadge._textures.erase(id)
		var img := BikeBadge.texture(str(id)).get_image()
		img.decompress()
		if img.has_mipmaps():
			img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % 5) * BikeBadge.SIZE, (i / 5) * BikeBadge.SIZE))
		i += 1
	print("LOGOS drawn in %d ms" % (Time.get_ticks_msec() - t0))
	sheet.save_png(out_dir.path_join("05_logos.png"))
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
