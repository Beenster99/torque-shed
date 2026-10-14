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
	var w: Walker = main.walker
	if "--beam" in OS.get_cmdline_user_args():
		await _beam_shots()
		get_tree().quit()
		return
	if "--tails" in OS.get_cmdline_user_args():
		await _tail_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--weather" in OS.get_cmdline_user_args():
		await _weather_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--blast" in OS.get_cmdline_user_args():
		await _blast_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--office" in OS.get_cmdline_user_args():
		await _office_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--geo" in OS.get_cmdline_user_args():
		await _geo_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	# Full-width bay screens either side of the narrower dyno room doorway.
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, 4.5), Vector3(0.0, 1.9, 59.2), "c1_bay_screens_doorway")
	# The dyno room: a bike strapped down at all four posts, the extraction hose on its
	# exhaust, the fan running, and the ear defenders on their hook by the door.
	var faithful := _bike_named("Old Faithful")
	Shed.request({"a": "grab_bike", "bike": faithful})
	var near := DynoRoom.rig_transform().translated(Vector3(0.2, 0.0, 0.4))
	Shed.request({"a": "move_bike", "bike": faithful, "xf": near})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": near})
	for i in 4:
		Shed.request({"a": "dyno_strap", "point": i})
	Shed.request({"a": "dyno_hose", "to": "held"})
	Shed.request({"a": "dyno_hose", "to": "bike"})
	Shed.request({"a": "dyno_fan", "on": true})
	await _frames(10)
	await _look_from(Vector3(-3.4, 0.0, 53.0), Vector3(0.6, 0.8, 57.2), "c2_dyno_room_strapped_hose")
	await _look_from(Vector3(3.6, 0.0, 58.6), Vector3(-0.4, 0.7, 54.4), "c3_dyno_fan_and_hose")
	await _look_from(Vector3(-1.0, 0.0, 57.4), Vector3(-1.7, 1.45, 59.2), "c4_dyno_switches_and_ear_defenders")
	Shed.request({"a": "dyno_headphones", "on": true})
	await _frames(10)
	await _look_from(Vector3(-2.6, 0.0, 57.8), Vector3(0.0, 0.8, 55.0), "c5_wearing_ear_defenders")
	Shed.request({"a": "dyno_headphones", "on": false})
	Shed.request({"a": "dyno_hose", "to": "held"})
	Shed.request({"a": "dyno_hose", "to": "hook"})
	for i in 4:
		Shed.request({"a": "dyno_strap", "point": i})
	Shed.request({"a": "grab_bike", "bike": faithful})
	var home := Workshop.CENTER + Vector3(-4.0, 0.0, 1.0)
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Transform3D(Basis(), home)})
	await _blast_shots()
	await _beam_shots()
	SaveGame.delete_slot("shots")
	get_tree().quit()


## The headlight at night: a soft beam in the night air rather than a solid cone. (Only the
## stand-in glow shows here: volumetric fog needs Forward+, which the cloud can't render.)
## `-- --beam` takes just these.
func _beam_shots() -> void:
	Daylight.current.set_time(22.0)
	main._try_mount(_bike_named("Old Faithful"))
	await _frames(10)
	main.bike.start_engine()
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(40)
	await _shot("c10_low_beam_night")
	main.bike.cycle_beam()
	await _frames(20)
	await _shot("c11_high_beam_night")


## Geometry mode on the Rusty Ranger (move, rotate and scale handles on its tank), and a
## blueprint build: the hologram in an empty bay, then half built with ghosts for the rest.
## `-- --geo` takes just these.
func _geo_shots() -> void:
	var w: Walker = main.walker
	var ranger := _bike_named("Rusty Ranger")
	var view: Node3D = main.workshop.bike_views[ranger]
	w.place(Transform3D(Basis(), view.global_position + Vector3(1.6, 0.1, 0.4)))
	await _frames(5)
	main.open_geometry()
	var geo: GeometryMode = main.geometry
	geo.select("tank")
	geo.set_part_offset("tank", {"p": Vector3(0.0, 0.04, -0.03), "r": Vector3(-8.0, 0.0, 0.0), "s": Vector3(1.0, 1.0, 1.15)})
	await _frames(20)
	await _shot("g1_geometry_move")
	geo.set_mode(GeoGizmo.Mode.ROTATE)
	await _frames(5)
	await _shot("g2_geometry_rotate")
	geo.set_mode(GeoGizmo.Mode.SCALE)
	geo.select("handlebars")
	await _frames(5)
	await _shot("g3_geometry_scale_bars")
	geo.save_blueprint("Desert Ranger")
	geo.request_exit()
	await _frames(5)
	var bp := Shed.blueprint_named("Desert Ranger")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	await _frames(10)
	var bay := Workshop.bay_transform(3)
	await _look_from(bay.origin + Vector3(-1.9, 0.0, 2.6), bay.origin + Vector3(0.0, 0.7, 0.0), "g4_hologram_in_bay")
	await _look_from(bay.origin + Vector3(-0.6, 0.0, 3.0), Vector3(Workshop.BAY_SCREEN_X[3], 2.5, Workshop.CENTER.z - Workshop.HALF.y), "g5_bay_screen_blueprint")
	var frame := Shed._new_item(str(Shed.blueprints[bp]["parts"]["frame"]), 0.0, 0.0, 0.0)
	Shed._move(frame, "held", Shed.me())
	Shed.request({"a": "start_build", "bay": 3})
	var built := Shed.bike_in_bay(3)
	for slot in ["fork", "front_wheel", "front_tyre", "tank", "engine"]:
		var item := Shed._new_item(str(Shed.blueprints[bp]["parts"][slot]), 0.0, 0.0, 0.0)
		Shed.bikes[built]["slots"][slot] = item
		Shed._move(item, "bike", built)
	Shed.changed.emit()
	await _frames(10)
	await _look_from(bay.origin + Vector3(-1.9, 0.0, 2.6), bay.origin + Vector3(0.0, 0.7, 0.0), "g6_half_built_with_ghosts")


## Tail units, fairings and mirrors: Old Faithful tried with every tail unit (from behind), then
## each fairing with mirrors (from the front quarter). `-- --tails` takes just these.
func _tail_shots() -> void:
	var bike := _bike_named("Old Faithful")
	var view: Node3D = main.workshop.bike_views[bike]
	var at := view.global_position
	var side := view.global_transform.basis.x
	var back := view.global_transform.basis.z
	for id in PartsDB.by_kind["tail"]:
		_swap_part(bike, "tail", id)
		await _frames(5)
		await _look_from(at + back * 2.2 + side * 1.4, at + Vector3(0.0, 0.5, 0.0) + back * 0.6, "t_tail_" + id)
	_swap_part(bike, "tail", "sport_tail_tidy")
	var mirrors := ["fairing_mirrors", "bar_end_mirrors", "fairing_mirrors", "touring_mirrors", "fairing_mirrors", "sport_mirrors"]
	var i := 0
	for id in PartsDB.by_kind["fairing"]:
		_swap_part(bike, "fairing", id)
		_swap_part(bike, "mirrors", mirrors[i % mirrors.size()])
		i += 1
		await _frames(5)
		await _look_from(at - back * 2.2 + side * 1.5, at + Vector3(0.0, 0.7, 0.0) - back * 0.6, "t_fairing_" + id)
	await _look_from(at + side * 2.6, at + Vector3(0.0, 0.6, 0.0), "t_side_view")


func _swap_part(bike: int, slot: String, part: String) -> void:
	var old := Shed.item_on(bike, slot)
	if old != 0:
		Shed.items.erase(old)
	var item := Shed._new_item(part, 0.0, 0.0, 0.0)
	Shed.bikes[bike]["slots"][slot] = item
	Shed.bikes[bike]["bolted"][slot] = true
	Shed._move(item, "bike", bike)
	Shed.changed.emit()


## The weather from the yard: clear, cloudy, fog and rain at midday, rain from inside the shed
## looking out of the roller door, rain at dusk, and the Esc menu's settings and Debug tabs.
## `-- --weather` takes just these.
func _weather_shots() -> void:
	Settings.day_night_cycle = false
	Daylight.current.set_time(13.0)
	var yard := Vector3(6.0, 0.0, 92.0)
	var shed := Workshop.CENTER + Vector3(0.0, 1.5, 0.0)
	for st in (["rain"] if "--rain" in OS.get_cmdline_user_args() else Weather.STATES):
		Settings.weather = st
		Weather.current.change_to(st, true)
		await _frames(10)
		await _look_from(yard, shed, "w_%s" % st)
	await _look_from(Vector3(10.0, 0.0, 118.0), Vector3(-6.0, 1.0, 98.0), "w_rain_wet_yard")
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, 1.5), Vector3(0.0, 1.4, 90.0), "w_rain_from_inside")
	Daylight.current.set_time(19.2)
	await _frames(10)
	await _look_from(yard, shed, "w_rain_dusk")
	Settings.weather = "auto"
	main.menu.show_pause()
	await _frames(10)
	await _shot("w_menu_settings")
	main.menu._tabs.current_tab = main.menu._tabs.get_tab_idx_from_control(main.menu.debug)
	await _frames(10)
	await _shot("w_menu_debug")
	main._close_menu()


## The sandblaster, mid-blast: a rusty engine turning on the turntable, satin bare metal
## coming up where the jet has been, and the live readout.
func _blast_shots() -> void:
	var w: Walker = main.walker
	# The sandblaster, mid-blast: the barn find's engine turning on the turntable, bare metal
	# coming up where the jet has been.
	Shed.request({"a": "order_furniture", "model": "blaster_cabinet"})
	var cab := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "blaster":
			cab = id
	var spot := "blast_%d_0" % cab
	var at := Workshop.CENTER + Vector3(1.5, 0.0, 1.8)
	Shed.request({"a": "grab", "furniture": cab})
	Shed.request({"a": "release", "furniture": cab, "xf": Transform3D(Basis(), at)})
	var engine := 0
	for s in Shed.stand_spots():
		if engine == 0 and Shed.is_engine(Shed.item_at_spot(s)):
			engine = Shed.item_at_spot(s)
			Shed.request({"a": "take", "spot": s})
	Shed.request({"a": "place", "spot": spot})
	await _frames(10)
	var view: EquipmentView = main.workshop.furniture_nodes[cab]
	var pivot: Node3D = view.get_node("Pivot")
	# A rusty, grubby engine, so the bare metal shows.
	var rusty := [engine]
	for slot in PartsDB.ENGINE_SLOTS:
		if Shed.engine_item(engine, slot) != 0:
			rusty.append(Shed.engine_item(engine, slot))
	for id in rusty:
		Shed.items[id]["rust"] = 0.85
		Shed.items[id]["dirt"] = 0.5
	Shed.changed.emit()
	await _frames(10)
	pivot = view.get_node("Pivot")
	await _look_from(at + Vector3(2.0, 0.0, 2.8), at + Vector3(0.0, 1.1, 0.0), "c6_sandblaster_cabinet")
	await _look_from(at + Vector3(0.0, 0.0, 1.3), pivot.global_position, "c7_sandblaster_ready")
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	await _frames(5)
	# Sweep the jet over one side in bands, turning the engine a little between them.
	Input.action_press("act")
	for i in 900:
		await get_tree().physics_frame
		if w.blast:
			w.blast.turn(Vector2(0.004 * sin(i * 0.01), 0.0))
		w._look(0.0025 * sin(i * 0.09), 0.0012 * cos(i * 0.011))
		if i == 700:
			await _shot("c8_sandblaster_mid_blast")
	Input.action_release("act")
	await _frames(10)
	await _shot("c9_sandblaster_bare_patches")
	await _look_from(at + Vector3(0.7, 0.0, 1.25), pivot.global_position, "c9b_sandblaster_satin_closeup")
	w.finish_blast()
	await _frames(10)


## The sales office: from the car park by day and lit up at night, the showroom with bikes on its
## plinths, the reception and viewing sofas, the kitchen, the stairs and the mezzanine office.
## `-- --office` takes just these.
const MEZZ := SalesOffice.MEZZ_Y


func _office_shots() -> void:
	Settings.day_night_cycle = false
	Settings.weather = "clear"
	Weather.current.change_to("clear", true)
	Daylight.current.set_time(11.0)
	var n := 0
	for name in ["Old Faithful", "Rusty Ranger"]:
		var bike := _bike_named(name)
		if bike == 0:
			continue
		var spot: Transform3D = SalesOffice.SHOWROOM_SPOTS[n]
		Shed.request({"a": "grab_bike", "bike": bike})
		Shed.request({"a": "release_bike", "bike": bike, "xf": spot.translated(Vector3(0.3, 0.0, 0.2))})
		n += 1
	await _frames(10)
	var o := SalesOffice.CENTER
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			only = a.trim_prefix("--shot=")
	var shots := [
		["o1_outside_day", Vector3(31.0, 0.0, 88.0), o + Vector3(-1.0, 2.6, 0.0)],
		["o2_outside_day_wide", Vector3(4.0, 0.0, 92.0), o + Vector3(-6.0, 2.5, 0.0)],
		["o3_showroom", o + Vector3(-0.8, 0.0, 5.4), o + Vector3(4.5, 0.8, -1.5)],
		["o4_showroom_from_stairs", o + Vector3(5.6, 0.0, -5.4), o + Vector3(1.0, 0.8, 4.0)],
		["o5_reception_lounge", o + Vector3(2.0, 0.0, 2.0), o + Vector3(-4.5, 0.9, 2.0)],
		["o6_kitchen", o + Vector3(-2.2, 0.0, -1.8), o + Vector3(-4.6, 0.9, -5.4)],
		["o7_mezzanine_office", o + Vector3(-5.6, MEZZ, -2.0), o + Vector3(-2.4, 3.6, 1.6)],
		["o8_office_overlooking_showroom", o + Vector3(-4.3, MEZZ, 2.3), o + Vector3(4.0, 0.6, 1.5)],
		["o9_stairs", o + Vector3(6.4, 0.0, -2.6), o + Vector3(0.5, 2.0, -5.4)],
	]
	for s in shots:
		if only == "" or str(s[0]).contains(only):
			await _look_from(s[1], s[2], s[0])
	Daylight.current.set_time(22.5)
	await _frames(20)
	for s in [["o10_outside_night", Vector3(31.0, 0.0, 88.0), o + Vector3(-1.0, 2.6, 0.0)],
			["o11_outside_night_wide", Vector3(10.0, 0.0, 90.0), o + Vector3(-4.0, 2.5, 0.0)],
			["o12_showroom_night", o + Vector3(-0.8, 0.0, 5.4), o + Vector3(4.5, 0.8, -1.5)]]:
		if only == "" or str(s[0]).contains(only):
			await _look_from(s[1], s[2], s[0])
	Shed.request({"a": "lights", "room": "sales", "on": false})
	await _frames(10)
	if only == "" or "lights_off".contains(only):
		await _look_from(Vector3(31.0, 0.0, 88.0), o + Vector3(-1.0, 2.6, 0.0), "o13_outside_night_lights_off")
