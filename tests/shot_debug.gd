extends "res://tests/screenshots.gd"
## Quick screenshots of the newest features only, for checking them without the full set:
##   xvfb-run godot --path . res://tests/shot_debug.tscn -- --out=/tmp/shots


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveGame.slot_override = "shots"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main.menu.new_shed = true
	main._start_session()
	await _frames(20)
	await _room_shots()
	if "--rooms" in OS.get_cmdline_user_args():
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	# Milestone B: a character with some XP, upgraded tools and skills.
	Progress.path = "user://profile_shots.json"
	Progress.select("Shots")
	Progress.profile["xp"] = Progress.xp_for_level(12) + 200
	for t in ["wrench", "wrench", "wrench", "wrench", "spray", "spray", "brush"]:
		Progress.upgrade_tool(t)
	for k in ["torque_feel", "torque_feel", "engine_whisperer", "steady_hand", "balance"]:
		Progress.buy_skill(k)
	var w: Walker = main.walker
	w.set_tool("wrench")
	main.hud.add_popup(6, "Cleaning")
	main.hud.add_popup(12, "Spraying")
	Progress.leveled_up.emit(12)
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, 3.0), Workshop.CENTER + Vector3(0.0, 1.2, -5.0), "b1_hud_wrench_stage4")
	w.set_tool("spray")
	await _frames(5)
	await _shot("b2_spray_stage2")
	main.menu.show_pause()
	main.menu._tabs.current_tab = main.menu._tabs.get_tab_count() - 1
	await _frames(10)
	await _shot("b3_character_tab")
	var scroll: ScrollContainer = main.menu._tabs.get_current_tab_control()
	scroll.scroll_vertical = 700
	await _frames(5)
	await _shot("b4_character_skills")
	scroll.scroll_vertical = 2000
	await _frames(5)
	await _shot("b5_character_goals")
	main.menu.hide()
	await _frames(5)
	# Bins by the roller door, the tyre changer, and a bay screen on the XP goals channel.
	await _look_from(Vector3(-3.3, 0.0, 67.4), Vector3(-3.6, 1.0, 70.4), "b6_bins")
	var cx: Vector3 = Workshop.CHANGER_XF.origin
	await _look_from(cx + Vector3(1.9, 0.0, 0.4), cx + Vector3(0.0, 0.9, 0.0), "b7_tyre_changer")
	for i in 8:
		if Shed.screen_channel("bay1")["ch"] == "xp":
			break
		Shed.request({"a": "tv_channel", "screen": "bay1", "step": 1})
		await _frames(2)
	await _look_from(Workshop.CENTER + Vector3(-1.5, 0.0, 0.5), Workshop.CENTER + Vector3(-1.5, 2.2, -5.5), "b8_tv_xp_channel")
	# High beam at night: dusty beam.
	Daylight.current.set_time(22.0)
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(40)
	main.bike.cycle_beam()
	await _frames(20)
	await _shot("b9_high_beam_dust")
	DirAccess.remove_absolute(Progress.path)
	SaveGame.delete_slot("shots")
	get_tree().quit()


## The side rooms: the TV wall with the lights off (no glow behind the screens), the paint shop
## under its hexagon lights with all ten hooks filled, its doorway from the shed, and the
## empty storage room.
func _room_shots() -> void:
	Daylight.current.set_time(22.0)
	Shed.request({"a": "lights", "on": false})
	await _frames(5)
	await _look_from(Workshop.CENTER + Vector3(-5.6, 0.0, -2.6), Workshop.CENTER + Vector3(2.0, 2.2, -5.5), "r1_tv_wall_dark_side")
	await _look_from(DynoRoom.CENTER + Vector3(-3.5, 0.0, -2.5), DynoRoom.CENTER + Vector3(1.0, 1.6, 3.6), "r2_dyno_side_of_tv_wall")
	Shed.request({"a": "lights", "on": true})
	Daylight.current.set_time(12.0)
	# Fill every hook in the spray bay with loose parts.
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hooks: Array = Shed.furniture_spots(booth)
	var parts := ["sport_17", "cast_17_front", "slip_on", "clip_ons", "sport_solo", "floating_310", "solid_240",
		"sport_road", "cast_17", "twin_piston", "sport_17", "slip_on"]
	for n in hooks.size():
		if Shed.item_at_spot(hooks[n]) == 0:
			Shed._move(Shed._new_item(parts[n % parts.size()], 0.0, 0.1, 0.0), "spot", hooks[n])
	Shed.changed.emit()
	await _frames(5)
	var pc := Workshop.BOOTH_ROOM_CENTER
	await _look_from(pc + Vector3(-3.2, 0.0, 4.6), pc + Vector3(1.0, 1.0, -2.0), "r3_paint_shop_hex")
	await _look_from(pc + Vector3(-2.9, 0.0, -4.7), pc + Vector3(1.5, 2.4, 1.5), "r4_paint_shop_ceiling")
	Shed.request({"a": "lights", "room": "paint", "on": false})
	await _frames(5)
	await _look_from(pc + Vector3(-3.2, 0.0, 4.6), pc + Vector3(1.0, 1.0, -2.0), "r5_paint_shop_lights_off")
	Shed.request({"a": "lights", "room": "paint", "on": true})
	await _look_from(Workshop.CENTER + Vector3(2.5, 0.0, 2.0), Vector3(6.6, 1.2, Workshop.PAINT_DOOR_Z), "r6_paint_door_from_shed")
	await _look_from(Workshop.CENTER + Vector3(-3.0, 0.0, -3.0), Vector3(-6.6, 1.2, Workshop.STORE_DOOR_Z), "r7_storage_door_from_shed")
	var sc := Workshop.STORE_CENTER
	await _look_from(sc + Vector3(3.6, 0.0, 3.0), sc + Vector3(-2.0, 1.0, -2.0), "r8_storage_room")
	await _look_from(pc + Vector3(4.5, 0.0, 9.0), pc + Vector3(0.0, 1.5, 0.0), "r9_paint_shop_outside")
