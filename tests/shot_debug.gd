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
