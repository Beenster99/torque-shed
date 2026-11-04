extends Node
## Pictures of the Bike shop as the player sees it: in the real Esc menu over the shed, at the
## window size given (4K by default), for visual checks:
##   xvfb-run -s "-screen 0 3840x2160x24" godot --path . res://tests/menu_shop_shots.tscn -- --out=/tmp/shots

var out_dir := "user://screenshots"


func _ready() -> void:
	var size := Vector2i(3840, 2160)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--size="):
			var wh := a.trim_prefix("--size=").split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = size
	Shed.start_new("Simon", 61)
	Progress.set_money(100000)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var menu := MainMenu.new()
	add_child(menu)
	await _frames(3)
	menu.show_pause()
	menu.open_tab(menu.bike_shop)
	await _frames(5)
	menu.bike_shop.show_mode("new")
	menu.bike_shop.set_finish("frame", "chrome")
	menu.bike_shop.set_finish("tank", "metallic")
	menu.bike_shop.set_finish("saddle", "matte")
	await _frames(40)
	await _shot("01_menu_bike_shop")
	var cp := menu.bike_shop
	cp.set_logo("wings")
	cp.set_brand("Bennett")
	cp.badge["brand_font"] = "lobster"
	cp.show_mode("new")
	(cp._left.get_parent() as ScrollContainer).scroll_vertical = 10000
	await _frames(30)
	await _shot("02_menu_bike_shop_badge")
	menu._profile_tabs.current_tab = 0
	await _frames(5)
	await _shot("03_menu_profile")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
