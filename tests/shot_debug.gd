extends "res://tests/screenshots.gd"
## Quick screenshots of the newest features only, for checking them without the full set:
##   xvfb-run godot --path . res://tests/shot_debug.tscn -- --out=/tmp/shots


func _ready() -> void:
	# The old demo bikes these were written round (a player's new shed starts empty).
	Shed.demo_bikes = true
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
	if "--guards" in OS.get_cmdline_user_args():
		await _guard_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--weather" in OS.get_cmdline_user_args():
		await _weather_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--graphics" in OS.get_cmdline_user_args():
		await _graphics_shots()
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
	if "--looks" in OS.get_cmdline_user_args():
		await _look_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--upgrades" in OS.get_cmdline_user_args():
		await _upgrade_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--building" in OS.get_cmdline_user_args():
		await _building_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--gear" in OS.get_cmdline_user_args():
		await _gear_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--lighting" in OS.get_cmdline_user_args():
		await _lighting_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
	if "--signs" in OS.get_cmdline_user_args():
		await _sign_shots()
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


## Front mudguards: Old Faithful with each one (from the front quarter), then the parts
## computer's grouped list, sorted and filtered. `-- --guards` takes just these.
func _guard_shots() -> void:
	var bike := _bike_named("Old Faithful")
	var view: Node3D = main.workshop.bike_views[bike]
	var at := view.global_position
	var side := view.global_transform.basis.x
	var back := view.global_transform.basis.z
	var pc: PartsComputer = main.computer
	main._open_computer()
	await _frames(5)
	await _shot("fm_computer_bike_aisle")
	pc._show_kind("front_mudguard")
	await _frames(5)
	await _shot("fm_computer_mudguards")
	pc.set_sort("price_up")
	pc.set_fits_bike(bike)
	pc._show_kind("tyre")
	await _frames(5)
	await _shot("fm_computer_tyres_fit_sorted")
	pc._show_section("shed")
	await _frames(5)
	await _shot("fm_computer_shed_aisle")
	pc.close_computer()
	for id in PartsDB.by_kind["front_mudguard"]:
		_swap_part(bike, "front_mudguard", id)
		await _frames(5)
		await _look_from(at - back * 1.6 + side * 1.6, at + Vector3(0.0, 0.4, 0.0) - back * 0.7, "fm_" + id)


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
	for i in 260:
		await get_tree().physics_frame
		if w.blast:
			w.blast.turn(Vector2(0.004 * sin(i * 0.01), 0.0))
		w._look(0.0025 * sin(i * 0.09), 0.0012 * cos(i * 0.011))
		if i == 220:
			await _shot("c8_sandblaster_mid_blast")
	Input.action_release("act")
	await _frames(10)
	await _shot("c9_sandblaster_bare_patches")
	await _look_from(at + Vector3(0.7, 0.0, 1.25), pivot.global_position, "c9b_sandblaster_satin_closeup")
	# The scan: red where there's still rust to blast, and the readout of what's left.
	if w.blast:
		w.toggle_blast_scan()
	await _frames(40)
	await _shot("c9c_sandblaster_scan")
	if w.blast:
		w.toggle_blast_scan()
	w.finish_blast()
	await _frames(10)
	# Stepped back: the bare patches stay.
	await _look_from(at + Vector3(0.7, 0.0, 1.25), pivot.global_position, "c9d_sandblaster_after_step_back")
	# Blasted bare all over, hung in the paint shop and given a clear coat.
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	var res := {}
	for id in rusty:
		res[id] = [0.95, 0.0]
	Shed.request({"a": "blast", "spot": spot, "parts": res})
	await _frames(5)
	await _look_from(at + Vector3(0.7, 0.0, 1.25), pivot.global_position, "c9e_sandblaster_all_bare")
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var hook: String = Shed.furniture_spots(booth)[2]
	Shed.request({"a": "take", "spot": spot})
	Shed.request({"a": "place", "spot": hook})
	Shed.request({"a": "coat", "item": engine, "coat": "clear", "gun": true, "quality": 0.95})
	await _frames(20)
	var hung: Node3D = main.workshop._spot_nodes[hook]
	var mid := hung.global_position + Vector3.UP * 0.3
	await _look_from(mid + Vector3(-1.6, -mid.y, 0.4), mid, "c9f_engine_hung_clear_coat")


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


## Garage upgrades: the shed as it starts, then with every upgrade bought (the extension with
## bays 5 to 7 and the lounge, the storage annex with racking and the mezzanine, and the
## luxury finishes). `-- --upgrades` takes just these.
func _upgrade_shots() -> void:
	Settings.weather = "clear"
	if Weather.current:
		Weather.current.change_to("clear", true)
	Daylight.current.set_time(13.0)
	for pass_name in ["none", "all"]:
		if pass_name == "all":
			Shed.request({"a": "garage_money", "value": 1000000})
			for id in GarageUpgrades.CATALOGUE:
				Shed.request({"a": "buy_upgrade", "id": id})
			await _frames(10)
			print("built: ", main.workshop.upgrades.built())
		await _aerial(Vector3(22.0, 14.0, 38.0), Vector3(2.0, 0.0, 57.0), "u1_aerial_back_%s" % pass_name)
		await _aerial(Vector3(-22.0, 13.0, 40.0), Vector3(-6.0, 0.0, 55.0), "u2_aerial_west_%s" % pass_name)
		await _look_from(Vector3(-1.0, 0.0, 69.0), Vector3(3.0, 1.6, 59.5), "u3_shed_back_wall_%s" % pass_name)
		await _look_from(Vector3(-4.5, 0.0, 69.5), Vector3(4.0, 1.4, 62.0), "u4_shed_inside_%s" % pass_name)
		await _look_from(Vector3(0.0, 0.0, 82.0), Vector3(0.0, 3.0, 70.8), "u5_shed_front_%s" % pass_name)
		if pass_name == "none":
			continue
		await _look_from(Vector3(6.0, 0.0, 58.6), Vector3(10.5, 1.0, 51.5), "u6_wing_bays")
		await _look_from(Vector3(8.0, 0.0, 55.6), Vector3(13.6, 1.0, 58.2), "u7_lounge")
		await _look_from(Vector3(-8.6, 0.0, 53.2), Vector3(-13.0, 1.6, 48.0), "u8_annex_mezzanine")
		await _look_from(Vector3(-10.9, 0.0, 60.5), Vector3(-10.9, 1.4, 50.0), "u9_annex_doorway")
		await _look_from(Vector3(5.75, 0.0, 66.0), Vector3(5.75, 1.6, 59.5), "u10_extension_doorway")
		Daylight.current.set_time(22.0)
		await _frames(10)
		await _look_from(Vector3(0.0, 0.0, 82.0), Vector3(0.0, 3.0, 70.8), "u11_sign_at_night")
		await _look_from(Vector3(8.0, 0.0, 55.6), Vector3(13.6, 1.0, 58.2), "u12_lounge_at_night")


## A shot from a camera anywhere (up in the air), then back to the walker's eyes.
func _aerial(from: Vector3, at: Vector3, name: String) -> void:
	var cam := Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.current = true
	await _frames(15)
	await _shot(name)
	cam.queue_free()
	main.walker.camera.current = true


## Rider gear and trinkets (`-- --gear`): a line-up of riders in different outfits, close-ups
## of the helmets, the Shop tab's turntable, a rider on a bike in race leathers, and trinkets
## put about the shed.
const OUTFITS := [
	{},
	{"helmet": "helmet_kestrel", "jacket": "jacket_kestrel", "trousers": "trousers_kestrel", "boots": "boots_kestrel", "gloves": "gloves_kestrel"},
	{"helmet": "helmet_mx", "jacket": "jacket_mx", "trousers": "trousers_mx", "boots": "boots_mx", "gloves": "gloves_mx"},
	{"helmet": "helmet_pudding", "jacket": "jacket_ironside", "trousers": "trousers_jeans", "boots": "boots_engineer", "gloves": "gloves_brookstone"},
	{"helmet": "helmet_sprint", "jacket": "jacket_hivis", "trousers": "trousers_strata", "boots": "boots_strata", "gloves": "gloves_hivis"},
	{"helmet": "helmet_open_cream", "jacket": "jacket_wax", "trousers": "trousers_wax", "boots": "boots_trainers", "gloves": "gloves_rigger"},
	{"helmet": "helmet_chequer", "jacket": "jacket_denim", "trousers": "trousers_ironside", "boots": "boots_work", "gloves": "gloves_strata"},
	{"helmet": "helmet_stealth", "jacket": "jacket_strata", "trousers": "trousers_overalls", "boots": "boots_mx", "gloves": "gloves_work"},
]


func _gear_shots() -> void:
	# A profile of its own, so the money and gear bought here don't stay on the test rider.
	Progress.path = "user://profile_gear_shots.json"
	Progress.select("Shot Rider")
	if not "--trinkets" in OS.get_cmdline_user_args():   # `-- --gear --trinkets`: just the bike and the trinkets
		await _outfit_shots()
	await _ride_and_trinket_shots()


func _outfit_shots() -> void:
	var riders := []
	var base := Workshop.CENTER + Vector3(-2.8, 0.0, 2.6)
	for i in OUTFITS.size():
		var peer := 900 + i
		Progress._summaries[peer] = {"name": "Rider %d" % (i + 1), "gear": RiderGear.clean_worn(OUTFITS[i])}
		var rp := RemotePlayer.new()
		main.world.add_child(rp)
		rp.setup(peer, "Rider %d" % (i + 1), Shed.PAINTS[i % Shed.PAINTS.size()])
		rp.global_position = base + Vector3(i * 0.8, 0.0, 0.0)
		rp.rotation.y = PI   # facing +Z, towards the camera
		riders.append(rp)
	await _frames(10)
	await _look_from(base + Vector3(2.8, 0.0, 4.6), base + Vector3(2.8, 1.0, 0.0), "r1_rider_gear_lineup")
	await _look_from(base + Vector3(0.8, 0.0, 2.2), base + Vector3(0.8, 1.1, 0.0), "r2_outfits_left")
	await _look_from(base + Vector3(4.4, 0.0, 2.2), base + Vector3(4.4, 1.1, 0.0), "r3_outfits_right")
	# Helmets up close, and from the side and behind.
	await _look_from(base + Vector3(1.2, -0.25, 1.3), base + Vector3(1.2, 1.55, 0.0), "r4_helmets_close")
	for rp in riders:
		rp.rotation.y = PI * 0.5
	await _look_from(base + Vector3(2.8, 0.0, 3.4), base + Vector3(2.8, 1.1, 0.0), "r5_lineup_side")
	for rp in riders:
		rp.rotation.y = 0.0
	await _look_from(base + Vector3(2.8, 0.0, 3.4), base + Vector3(2.8, 1.1, 0.0), "r6_lineup_back")
	for rp in riders:
		rp.queue_free()
	# The Shop tab, its turntable showing the race leathers.
	Progress.set_money(2500)
	main.menu.show_pause()
	var shop: ShopTab = main.menu.shop
	main.menu._tabs.current_tab = main.menu._tabs.get_tab_idx_from_control(shop)
	shop.show_category("jacket")
	shop.select("jacket_kestrel")
	await _frames(30)
	await _shot("r7_shop_tab_jacket")
	shop.show_category("trinket")
	shop.select("trinket_neon")
	await _frames(30)
	await _shot("r8_shop_tab_trinket")
	main.menu.hide()


func _ride_and_trinket_shots() -> void:
	# Riding in the race leathers: own the lot and wear it.
	for id in OUTFITS[1].values():
		Progress.profile["gear"]["owned"].append(id)
		RiderGear.wear(id)
	main._try_mount(_bike_named("Old Faithful"))
	await _frames(10)
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(40)
	await _shot("r9_riding_in_race_leathers")
	main._get_off()
	await _frames(10)
	# Trinkets about the shed: small ones on the workbench, the rest on the floor and walls.
	var wall_x := Workshop.CENTER.x - Workshop.HALF.x + 0.03
	var bench_x := Workshop.CENTER.x - Workshop.HALF.x + 0.4
	var bz: float = Shed.spot_transform("bench_0").origin.z
	var turn := Basis(Vector3.UP, PI * 0.5)
	var places := {
		"trinket_bobblehead": Vector3(bench_x, 0.95, bz + 0.2),
		"trinket_trophy": Vector3(bench_x, 0.95, bz + 0.6),
		"trinket_radio": Vector3(bench_x, 0.95, bz + 1.1),
		"trinket_lava": Vector3(bench_x, 0.95, bz + 1.5),
		"trinket_bike_model": Vector3(bench_x, 0.95, bz + 1.9),
		"trinket_gnome": Vector3(bench_x - 0.1, 0.0, bz - 1.0),
		"trinket_plant": Vector3(bench_x - 0.05, 0.0, bz - 1.6),
		"trinket_rug": Vector3(bench_x + 1.6, 0.0, bz + 1.0),
		"trinket_clock": Vector3(wall_x, 2.9, bz - 1.2),
		"trinket_neon": Vector3(wall_x, 3.7, bz + 1.6),
		"trinket_photo": Vector3(wall_x, 1.9, bz - 1.2),
	}
	# One at a time: each is moved in before the next is ordered, so the drop-off never fills.
	for id in Trinkets.all():
		Shed.request({"a": "order_furniture", "model": id})
		for fid in Shed.furniture:
			if str(Shed.furniture[fid]["model"]) == id:
				Shed.furniture[fid]["xf"] = Transform3D(turn, places[id])
	Shed.changed.emit()
	await _frames(20)
	var eye_at := Vector3(bench_x + 2.6, 0.0, bz + 0.6)
	await _look_from(eye_at, Vector3(bench_x, 1.2, bz + 0.4), "r10_trinkets_on_bench")
	await _look_from(Vector3(bench_x + 1.0, 0.0, bz + 0.9), Vector3(bench_x, 1.05, bz + 1.0), "r11_trinkets_close")
	await _look_from(Vector3(bench_x + 2.4, 0.0, bz - 0.6), Vector3(bench_x, 0.7, bz - 1.2), "r12_plant_gnome_photo")
	Daylight.current.set_time(22.0)
	Shed.request({"a": "lights", "room": "", "on": false})
	await _frames(20)
	await _look_from(eye_at, Vector3(bench_x, 1.5, bz + 1.0), "r13_neon_and_lava_at_night")
	Progress.save_profile()
	DirAccess.remove_absolute(Progress.path)


## The Esc menu's Graphics tab, at the top and scrolled down, with the FPS counter on.
func _graphics_shots() -> void:
	var fps := Settings.gfx_fps_counter
	Settings.set_graphics("gfx_fps_counter", true)
	main.menu.show_pause()
	main.menu._tabs.current_tab = main.menu._tabs.get_tab_idx_from_control(main.menu.graphics)
	await _frames(10)
	await _shot("gfx1_graphics_tab")
	var scroll: ScrollContainer = main.menu.graphics.get_child(1)
	scroll.scroll_vertical = 700
	await _frames(10)
	await _shot("gfx2_graphics_tab_scrolled")
	scroll.scroll_vertical = 2000
	await _frames(10)
	await _shot("gfx3_graphics_tab_end")
	main._close_menu()
	Settings.set_graphics("gfx_fps_counter", fps)
## The lighting (`-- --lighting`): the cloud sky in each weather and at dusk and night, flat
## clouds against raymarched ones, and the shed from the yard and inside with its lights off.
## (Here only the compatibility renderer runs: no SDFGI, volumetric fog or fog volumes.)
func _lighting_shots() -> void:
	Settings.day_night_cycle = false
	var yard := Vector3(6.0, 0.0, 92.0)
	var up := Vector3(-40.0, 60.0, 30.0)
	for q in ["off", "high"]:
		Lighting.overrides = {"gfx_clouds": q}
		main.world.lighting.apply()
		for st in (Weather.STATES if q == "high" else ["clear", "cloudy"]):
			Settings.weather = st
			Weather.current.change_to(st, true)
			Daylight.current.set_time(14.0)
			await _frames(10)
			await _look_from(yard, up, "l_%s_clouds_%s" % [q, st])
	Settings.weather = "cloudy"
	Weather.current.change_to("cloudy", true)
	for h in [7.0, 18.6, 23.0]:
		Daylight.current.set_time(h)
		await _frames(10)
		await _look_from(yard, Vector3(60.0 if h < 12.0 else -60.0, 25.0, 90.0), "l_cloudy_%s" % Daylight.clock_text(h).replace(":", ""))
	Settings.weather = "clear"
	Weather.current.change_to("clear", true)
	Daylight.current.set_time(12.0)
	await _frames(10)
	await _look_from(Vector3(-8.0, 0.0, 95.0), Vector3(-3.0, 60.0, 0.0), "l_clear_sun_noon")
	Shed.request({"a": "door", "open": true})
	main.workshop.door_open_amount = 0.999
	await _frames(10)
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, -3.0), Vector3(0.0, 1.0, 90.0), "l_shed_looking_out")
	Shed.request({"a": "lights", "room": "", "on": false})
	await _frames(60)
	await _look_from(Workshop.CENTER + Vector3(2.0, 0.0, 3.0), Workshop.CENTER + Vector3(-3.0, 1.0, -4.0), "l_shed_lights_off_adapted")
	Shed.request({"a": "lights", "room": "", "on": true})
	Lighting.overrides = {}
	Settings.weather = "auto"



## Shed building (`-- --building`): a whole bike's parts packed in the delivery area, a bike up
## on a bay lift, the big annex and its mezzanine stairs, and the crew lounge upstairs with its
## outside stairs.
func _building_shots() -> void:
	Settings.weather = "clear"
	if Weather.current:
		Weather.current.change_to("clear", true)
	Daylight.current.set_time(13.0)
	Shed.request({"a": "garage_money", "value": 2000000})
	for id in GarageUpgrades.CATALOGUE:
		Shed.request({"a": "buy_upgrade", "id": id})
	var bp := Shed._save_blueprint(_bike_named("Old Faithful"), "Whole bike")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	Shed.request({"a": "bp_order", "bay": 3})
	for i in 60:
		Shed.request({"a": "order_part", "part": "sport_17" if i % 2 == 0 else "copper_plugs"})
	Shed.request({"a": "order"})
	Shed.request({"a": "order"})
	Shed.request({"a": "lift", "bay": 4, "up": true})
	await _frames(10)
	await _aerial(Vector3(6.8, 7.0, 84.0), Vector3(6.8, 0.0, 74.5), "b1_delivery_area")
	await _look_from(Vector3(12.0, 0.0, 79.5), Vector3(6.0, 0.6, 75.5), "b2_delivery_racking")
	for i in 240:
		await get_tree().physics_frame
	await _look_from(Vector3(9.0, 0.0, 56.5), Vector3(6.6, 1.0, 52.4), "b3_bay_lift_up")
	await _look_from(Vector3(-8.0, 0.0, 53.2), Vector3(-12.5, 2.2, 42.0), "b4_annex")
	await _look_from(Vector3(-8.8, 0.0, 52.0), Vector3(-6.25, 1.6, 45.5), "b5_mezzanine_stairs")
	await _aerial(Vector3(20.0, 6.0, 82.0), Vector3(8.0, 3.0, 71.0), "b6_lounge_stairs")
	await _look_from(Vector3(5.4, GarageUpgrades.LOFT_FLOOR, 69.6), Vector3(-3.0, GarageUpgrades.LOFT_FLOOR + 0.9, 63.5), "b7_lounge_inside")
	await _look_from(Vector3(-5.5, GarageUpgrades.LOFT_FLOOR, 60.4), Vector3(3.0, GarageUpgrades.LOFT_FLOOR + 0.8, 67.0), "b8_lounge_back")
	await _aerial(Vector3(-24.0, 16.0, 30.0), Vector3(-4.0, 0.0, 58.0), "b9_aerial_back")


## The shed signs (`-- --signs`): the TORQUE SHED light box over the roller door, and every
## room-name sign under the LED and honeycomb ceilings, with every upgrade built.
func _sign_shots() -> void:
	Settings.weather = "clear"
	if Weather.current:
		Weather.current.change_to("clear", true)
	Daylight.current.set_time(20.5)
	Shed.request({"a": "garage_money", "value": 1000000})
	for id in GarageUpgrades.CATALOGUE:
		Shed.request({"a": "buy_upgrade", "id": id})
	await _frames(10)
	await _look_from(Vector3(0.0, 0.0, 79.0), Vector3(0.0, 3.8, 70.8), "s1_front_sign")
	var c := Workshop.CENTER
	await _look_from(Vector3(c.x + 2.0, 0.0, Workshop.PAINT_DOOR_Z), Vector3(c.x + Workshop.HALF.x, 3.0, Workshop.PAINT_DOOR_Z), "s3_paint_shop_sign")
	await _look_from(Vector3(c.x - 2.0, 0.0, Workshop.STORE_DOOR_Z), Vector3(c.x - Workshop.HALF.x, 3.0, Workshop.STORE_DOOR_Z), "s4_storage_sign")
	var r := GarageUpgrades.WING
	await _look_from(Vector3(GarageUpgrades.WING_DOOR_X, 0.0, r.position.y + 3.0), Vector3(GarageUpgrades.WING_DOOR_X, 2.9, r.end.y), "s6_workshop_sign")
	var a := GarageUpgrades.ANNEX
	await _look_from(Vector3(GarageUpgrades.ANNEX_DOOR_X, 0.0, a.end.y + 3.0), Vector3(GarageUpgrades.ANNEX_DOOR_X, 3.0, a.end.y), "s8_annex_sign")


## Garage upgrade colours and styles (`-- --looks`): every finish bought, then the inside in a
## few different choices, and the upgrades page with its swatches and preview room.
func _look_shots() -> void:
	Settings.weather = "clear"
	if Weather.current:
		Weather.current.change_to("clear", true)
	Daylight.current.set_time(13.0)
	Shed.request({"a": "garage_money", "value": 5000000})
	for id in GarageUpgrades.CATALOGUE:
		if id != "showroom":
			Shed.request({"a": "buy_upgrade", "id": id})
	await _frames(10)
	main.computer.open()
	main.computer.open_upgrades()
	var page: UpgradesPanel = main.computer.upgrades_panel
	page.show_upgrade("epoxy")
	page.choose("colour", "blue")
	page.choose("effect", "gloss")
	await _frames(10)
	await _shot("l6_page_epoxy")
	page.show_upgrade("showroom")
	page.choose("floor", "bluewhite")
	await _frames(10)
	await _shot("l7_page_showroom")
	page.start_peek()
	await _frames(10)
	await _shot("l8_peek")
	main.computer.close_computer()
	await _frames(5)
	await _look_from(Vector3(-4.5, 0.0, 69.5), Vector3(4.0, 1.4, 62.0), "l1_standard_looks")
	Shed.request({"a": "restyle_upgrade", "id": "epoxy", "looks": {"colour": "red", "effect": "metallic"}})
	Shed.request({"a": "restyle_upgrade", "id": "cladding", "looks": {"upper": "anthracite", "lower": "black", "stripe": "yellow"}})
	Shed.request({"a": "restyle_upgrade", "id": "led", "looks": {"tone": "warm", "strip": "purple"}})
	Shed.request({"a": "restyle_upgrade", "id": "signage", "looks": {"neon": "pink"}})
	await _frames(10)
	await _look_from(Vector3(-4.5, 0.0, 69.5), Vector3(4.0, 1.4, 62.0), "l2_red_metallic_anthracite_warm")
	await _look_from(Vector3(-2.0, 0.0, 66.0), Vector3(7.0, 2.8, 64.0), "l3_pink_neon")
	Shed.request({"a": "restyle_upgrade", "id": "lounge", "looks": {"sofa": "tan", "rug": "navy", "neon": "blue"}})
	await _frames(5)
	await _look_from(Vector3(8.0, 0.0, 55.6), Vector3(13.6, 1.0, 58.2), "l4_lounge_tan_navy")
	Shed.request({"a": "buy_upgrade", "id": "showroom", "looks": {"floor": "redblack", "tiles": "large", "ceiling": "hex_big", "glow": "ice", "trim": "gold"}})
	await _frames(10)
	await _look_from(Vector3(-4.5, 0.0, 69.5), Vector3(4.0, 1.4, 62.0), "l5_showroom_red_black_gold")
