extends Node
## Boots the map behind the title screen, then runs a session: you on foot in the shed,
## the bike you're riding when you take one out, and everyone else in the session.

const MAP_SEED := 1234
const GET_OFF_SPEED := 2.0
const GET_OFF_DELAY := 0.6  # seconds after getting on before the same button gets you off

var world: World
var workshop: Workshop
var walker: Walker
var bike: Bike
var riding_id := 0
var camera: ChaseCamera
var hud: HUD
var menu: MainMenu
var computer: PartsComputer
var tuning: TuningComputer
var label_dialog: LabelDialog
var audio: EngineAudio
var saver: SaveGame
var remotes := {}     # peer id -> RemotePlayer
var in_session := false
var _send_timer := 0.0
var _stats_timer := 0.0
var _ride_km := 0.0
var _ride_top := 0.0
var _mounted_at := 0
var _dirt_km := 0.0
var _ride_dirt := 0.0      # road muck picked up since getting on, for drawing it on the bike
var _ride_view := ChaseCamera.Mode.CHASE
var _dash: Label3D
## How much road dirt a kilometre of each surface throws up, relative to a dirt track.
const SURFACE_DIRT := {"tarmac": 0.06, "dirt": 1.0, "grass": 0.7}


func _ready() -> void:
	world = World.new()
	add_child(world)
	world.generate(MAP_SEED)
	workshop = world.workshop
	camera = ChaseCamera.new()
	world.add_child(camera)
	_title_camera()
	camera.current = true

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = HUD.new()
	hud.visible = false
	ui.add_child(hud)
	computer = PartsComputer.new()
	computer.visible = false
	ui.add_child(computer)
	computer.closed.connect(func(): _capture_mouse(true))
	tuning = TuningComputer.new()
	tuning.visible = false
	ui.add_child(tuning)
	tuning.closed.connect(func(): _capture_mouse(true))
	label_dialog = LabelDialog.new()
	label_dialog.visible = false
	ui.add_child(label_dialog)
	label_dialog.closed.connect(func(): _capture_mouse(true))
	menu = MainMenu.new()
	ui.add_child(menu)
	menu.ride_solo.connect(func(): _start_session())
	menu.host_game.connect(_host)
	menu.join_game.connect(_join)
	menu.resume.connect(_close_menu)
	menu.leave_session.connect(_leave)
	menu.order_bike.connect(func():
		Shed.request({"a": "order"})
		_close_menu())
	saver = SaveGame.new()
	saver.name = "SaveGame"
	saver.main = self
	add_child(saver)

	Net.player_joined.connect(_on_player_joined)
	Net.player_updated.connect(_on_player_updated)
	Net.player_left.connect(_on_player_left)
	Net.state_received.connect(_on_state)
	Net.connected.connect(func(): _start_session())
	Net.internet_status_changed.connect(_on_internet_status)
	Net.connection_failed.connect(func(reason): menu.show_title(reason))
	Net.disconnected.connect(func(): _end_session(); menu.show_title("The host closed the shed."))
	Shed.changed.connect(_on_shed_changed)
	Shed.feedback.connect(func(text, ok): hud.flash(text, 2.5 if ok else 2.0, not ok))
	Shed.pinged.connect(_on_ping)
	menu.show_title()


func _title_camera() -> void:
	camera.target = null
	camera.mode = ChaseCamera.Mode.ORBIT
	camera.orbit_center = Vector3(0.0, 1.5, 76.0)
	camera.orbit_radius = 13.0
	camera.orbit_height = 3.0


func _paint() -> Color:
	return Shed.PAINTS[Net.local_slot() % Shed.PAINTS.size()]


func _local_info() -> Dictionary:
	return {"name": Settings.player_name, "color": _paint()}


func _host() -> void:
	var err := Net.host(_local_info())
	if err != OK:
		menu.set_status("Could not host on port %d (error %d)." % [Net.PORT, err])
		return
	_start_session()
	hud.flash("Hosting. Opening the port on your router... the Esc menu shows the address to give friends.", 6.0)


func _on_internet_status() -> void:
	if not Net.is_host():
		return
	if Net.internet_status == "open":
		hud.flash("Friends over the internet can join with %s" % (Net.external_ip if Net.external_ip != "" else "your public IP"), 8.0)
	elif Net.internet_status == "closed":
		hud.flash("Your router didn't open port %d automatically. See the Esc menu for how to let friends in." % Net.PORT, 8.0, true)
	if menu.visible:
		menu.show_pause()


func _join(ip: String) -> void:
	var where := Net.parse_address(ip)
	if where["host"] == "":
		menu.set_status("Enter the host's IP address.")
		return
	var err := Net.join(ip, _local_info())
	menu.set_status("Connecting to %s, port %d..." % [where["host"], where["port"]] if err == OK
		else "Couldn't find %s. Check the address (error %d)." % [where["host"], err])


func _start_session() -> void:
	if in_session:
		return
	in_session = true
	menu.hide()
	Net.update_local_info(_local_info())
	if Net.is_online() and not Net.is_host():
		Shed.join_remote()
	elif menu.new_shed or not saver.continue_shed():
		Shed.start_new(Settings.player_name)
	menu.new_shed = false
	walker = Walker.new()
	world.add_child(walker)
	walker.place(Workshop.walker_spawn(Net.local_slot()))
	walker.mount_requested.connect(_try_mount)
	walker.computer_requested.connect(_open_computer)
	walker.tuning_requested.connect(_open_tuning)
	walker.label_requested.connect(func(id):
		label_dialog.open(id)
		_capture_mouse(false))
	walker.rename_requested.connect(func(id):
		label_dialog.open_bike(id)
		_capture_mouse(false))
	walker.camera.current = true
	hud.walker = walker
	hud.visible = true
	for id in Net.players:
		if not remotes.has(id):
			_on_player_joined(id, Net.players[id])
	workshop.sync_state()
	_capture_mouse(true)
	hud.flash("Welcome to the shed. Esc for the menu.", 4.0)
	saver.session_started()


func _leave() -> void:
	saver.save_now()
	Net.leave()
	_end_session()
	menu.show_title()


func _end_session() -> void:
	in_session = false
	computer.visible = false
	tuning.visible = false
	label_dialog.visible = false
	_stop_riding()
	for id in remotes.keys():
		remotes[id].queue_free()
	remotes.clear()
	if walker:
		walker.queue_free()
		walker = null
	Shed.stop()
	hud.walker = null
	hud.visible = false
	_title_camera()
	camera.current = true
	_capture_mouse(false)


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _open_computer() -> void:
	computer.open()
	_capture_mouse(false)


## The dyno desk: tune the bike on the rig, or one close by, and run it.
func _open_tuning() -> void:
	tuning.open(walker.global_position if walker else Vector3.ZERO)
	_capture_mouse(false)


func _close_menu() -> void:
	menu.hide()
	_capture_mouse(true)


# ---------------------------------------------------------------------------- riding

func _try_mount(bike_id: int) -> void:
	var why := Shed.check(Shed.me(), {"a": "mount", "bike": bike_id})
	if why != "":
		hud.flash(why, 2.5, true)
		return
	Shed.request({"a": "mount", "bike": bike_id})


func _on_shed_changed() -> void:
	if not in_session:
		return
	workshop.sync_state()
	var mine := Shed.riding(Shed.me())
	if mine != 0 and bike == null:
		_start_riding(mine)
	elif mine == 0 and bike != null and riding_id != 0:
		_stop_riding()


func _start_riding(bike_id: int) -> void:
	var data: Dictionary = Shed.bikes[bike_id]
	riding_id = bike_id
	bike = Bike.new()
	bike.rider_color = _paint()
	bike.setup(Shed.build_of(bike_id), data["paint"])
	world.add_child(bike)
	var xf: Transform3D = data["xf"]
	bike.place(xf.origin, xf.basis.get_euler().y)
	bike.crashed.connect(func(): hud.flash("Crashed!", 1.5, true))
	# You get on with the engine off and start it yourself.
	bike.engine_on = false
	bike.rpm = 0.0
	bike.engine_changed.connect(func(running, reason):
		if running:
			hud.flash("Engine running", 1.2)
		elif reason != "":
			hud.flash(reason, 3.0, true))
	audio = EngineAudio.new()
	audio.cylinders = bike.build.cylinders
	audio.layout = bike.build.layout
	audio.loudness = bike.build.exhaust_loudness
	audio.displacement = bike.build.displacement
	audio.whine = bike.build.gear_whine
	bike.add_child(audio)
	bike.gear_changed.connect(func(_g): Sfx.play_at("gear", bike.global_position, -6.0, bike))
	camera.target = bike
	camera.set_mode(_ride_view)
	camera.snap()
	camera.current = true
	hud.bike = bike
	_set_walker_active(false)
	_ride_km = 0.0
	_ride_top = 0.0
	_dirt_km = 0.0
	_ride_dirt = 0.0
	hud.trip_km = 0.0
	hud.trip_fuel = 0.0
	_dash = bike.model.dash_readout()
	_mounted_at = Time.get_ticks_msec()
	var build := bike.build
	if build.fuel_litres <= 0.0:
		hud.flash("The tank is empty. Fill it from a can of petrol before you ride.", 4.0, true)
	elif not build.notes.is_empty():
		hud.flash(build.notes[0], 3.0, true)


func _get_off() -> void:
	if bike == null:
		return
	if bike.is_crashed:
		bike.respawn()
		return
	if absf(bike.speed) > GET_OFF_SPEED:
		hud.flash("Stop first, then get off.", 1.5, true)
		return
	var fwd := -bike.global_transform.basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	var ground := bike.global_position
	var q := PhysicsRayQueryParameters3D.create(ground + Vector3.UP, ground + Vector3.DOWN * 3.0, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		ground = hit["position"]
	var right := Basis(Vector3.UP, heading) * Vector3.RIGHT
	walker.place(Transform3D(Basis(Vector3.UP, heading), ground - right * 0.9))
	_send_ride_stats()
	Shed.request({"a": "dismount", "bike": riding_id, "xf": Transform3D(Basis(Vector3.UP, heading), ground)})
	_stop_riding()


## Starts or stops the engine on the key.
func _ignition() -> void:
	if bike.engine_on or bike.is_starting():
		bike.stop_engine()
		hud.flash("Engine off", 1.2)
		Sfx.play_at("switch", bike.global_position, -6.0)
		return
	var why := bike.start_engine()
	if why != "":
		hud.flash(why, 2.0, true)
		Sfx.play_at("switch", bike.global_position, -6.0)
		return
	Sfx.play_at("starter", bike.global_position + Vector3.UP * 0.4, -2.0)


func _stop_riding() -> void:
	riding_id = 0
	if bike:
		bike.queue_free()
		bike = null
	audio = null
	hud.bike = null
	if walker:
		_set_walker_active(true)
		walker.camera.current = true


func _set_walker_active(on: bool) -> void:
	walker.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	walker.visible = on
	walker.collision_layer = 16 if on else 0


# ---------------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not in_session:
		return
	if event.is_action_pressed("menu"):
		if label_dialog.visible:
			label_dialog.close_dialog()
		elif computer.visible:
			computer.close_computer()
		elif tuning.visible:
			tuning.close_computer()
		elif menu.visible:
			_close_menu()
		else:
			menu.show_pause()
			_capture_mouse(false)
		get_viewport().set_input_as_handled()
		return
	if menu.visible or computer.visible or tuning.visible or label_dialog.visible or bike == null:
		return
	if event.is_action_pressed("interact"):
		if Time.get_ticks_msec() - _mounted_at >= GET_OFF_DELAY * 1000.0:
			_get_off()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("respawn"):
		bike.respawn()
	elif event.is_action_pressed("camera"):
		camera.cycle_mode()
		_ride_view = camera.mode
	elif event.is_action_pressed("ignition"):
		_ignition()
	elif event.is_action_pressed("shift_up"):
		bike.shift_up()
	elif event.is_action_pressed("shift_down"):
		bike.shift_down()
	elif event.is_action_pressed("headlight"):
		hud.flash("Headlight: %s" % bike.cycle_beam(), 1.2)
	elif event.is_action_pressed("ping"):
		PingMarker.ping_from(camera, [bike.get_rid()])
	elif event.is_action_pressed("stopwatch") and walker:
		walker.stopwatch.start_stop()
		Sfx.play_at("beep", camera.global_position, -6.0)
	elif event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		hud.flash("Auto-shift %s" % ("on" if Settings.auto_shift else "off"), 1.5)


func _physics_process(delta: float) -> void:
	if not in_session:
		return
	var active := not menu.visible and not computer.visible and not tuning.visible and not label_dialog.visible
	if walker:
		walker.controls_enabled = active
	if bike:
		var stick := Controls.stick()
		if active:
			bike.throttle = maxf(Input.get_action_strength("throttle"), Controls.trigger(true))
			bike.front_brake = maxf(Input.get_action_strength("front_brake"), Controls.trigger(false))
			bike.rear_brake = Input.get_action_strength("rear_brake")
			bike.lean_input = clampf(Input.get_axis("lean_left", "lean_right") + stick.x, -1.0, 1.0)
			bike.body_shift = clampf(Input.get_axis("body_back", "body_forward") - stick.y, -1.0, 1.0)
		else:
			bike.throttle = 0.0
			bike.lean_input = 0.0
			bike.body_shift = 0.0
			bike.front_brake = 1.0
			bike.rear_brake = 1.0
		bike.auto_shift = Settings.auto_shift
		bike.assist = Settings.assist
		bike.horn = active and Input.is_action_pressed("horn")
		audio.rpm = bike.rpm
		audio.gear = bike.gear
		audio.throttle = bike.sound_load()
		audio.running = bike.engine_on
		var km := absf(bike.speed) * delta / 1000.0
		_ride_km += km
		hud.trip_km += km
		_ride_top = maxf(_ride_top, absf(bike.speed) * 3.6)
		if bike.wheels[1]["contact"] or bike.wheels[0]["contact"]:
			# Loose ground and wheelspin throw muck all over the bike.
			var muck := km * float(SURFACE_DIRT.get(bike.surface, 0.3)) * (1.0 + float(bike.wheels[1]["slip"]))
			_dirt_km += muck
			_ride_dirt += muck * Shed.ROAD_DIRT * 0.8
			bike.model.set_grime(clampf(_ride_dirt, 0.0, 0.85))
		_update_dash()
		_stats_timer += delta
		if _stats_timer >= 1.0:
			_stats_timer = 0.0
			_send_ride_stats()
	_send_timer += delta
	if _send_timer >= 1.0 / 30.0:
		_send_timer = 0.0
		Net.send_state(_net_state())


## Tells the shed how far the bike went, how muddy it got and how much petrol it burnt.
func _send_ride_stats() -> void:
	if bike == null:
		return
	hud.trip_fuel += bike.fuel_used
	Shed.request({"a": "ride", "km": _ride_km, "top_kmh": _ride_top, "kmh": absf(bike.speed) * 3.6,
		"dirt_km": _dirt_km, "fuel": bike.fuel_used})
	bike.fuel_used = 0.0
	_ride_km = 0.0
	_dirt_km = 0.0


## The rider's view of the clocks: needles for speed and revs on dial clocks, and speed, gear and
## fuel on the screen of digital ones.
func _update_dash() -> void:
	if _dash == null:
		return
	var b := bike.build
	var fuel := clampf(bike.fuel_litres / maxf(b.fuel_capacity, 0.1), 0.0, 1.0)
	var full_scale := 200.0 if Units.speed_unit() == "km/h" else 120.0
	bike.model.set_gauges(Units.speed_value(bike.speed) / full_scale, bike.rpm / maxf(b.redline * 1.1, 1000.0))
	var bars := roundi(fuel * 8.0)
	var gauge := "F " + "|".repeat(bars) + ".".repeat(8 - bars) + " E"
	var gear := "G%d" % bike.gear if b.dash_features.has("gear") else ""
	if bike.model.has_dials():
		_dash.text = ("OFF" if not bike.engine_on else gear) + "\n" + "|".repeat(bars) + ".".repeat(8 - bars)
		_dash.modulate = Color(0.8, 0.1, 0.05) if fuel < 0.15 else Color(0.1, 0.1, 0.1)
		return
	if not bike.engine_on:
		_dash.text = "%d %s\n%s" % [Units.speed_value(bike.speed), Units.speed_unit(), "STARTING" if bike.is_starting() else "ENGINE OFF"]
	else:
		var revs := ""
		if b.dash_features.has("rpm"):
			var seg := roundi(clampf(bike.rpm / b.redline, 0.0, 1.0) * 10.0)
			revs = "\n" + "#".repeat(seg) + "-".repeat(10 - seg) + " %d rpm" % (roundi(bike.rpm / 100.0) * 100)
		_dash.text = "%d %s   %s%s\n%s" % [Units.speed_value(bike.speed), Units.speed_unit(), gear, revs, gauge]
	_dash.modulate = Color(1.0, 0.45, 0.3) if fuel < 0.15 else Color(0.75, 1.0, 0.85)


## [0, x, y, z, yaw, pitch, crouched] on foot, or [1, bike id, bike state...] riding.
func _net_state() -> PackedFloat32Array:
	if bike:
		var s := PackedFloat32Array([1.0, float(riding_id)])
		s.append_array(bike.get_net_state())
		return s
	if walker:
		var p := walker.global_position
		return PackedFloat32Array([0.0, p.x, p.y, p.z, walker.yaw(), walker.pitch(), 1.0 if walker.crouched or walker.seat != 0 else 0.0])
	return PackedFloat32Array()


# ---------------------------------------------------------------------------- other players

func _on_player_joined(id: int, info: Dictionary) -> void:
	if not in_session or remotes.has(id):
		return
	var rp := RemotePlayer.new()
	world.add_child(rp)
	rp.setup(id, str(info.get("name", "Rider")), info.get("color", Color(0.8, 0.1, 0.1)))
	remotes[id] = rp
	hud.flash("%s joined the shed" % info.get("name", "Someone"), 2.5)


func _on_player_updated(id: int, info: Dictionary) -> void:
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)
	_on_player_joined(id, info)


func _on_player_left(id: int) -> void:
	if remotes.has(id):
		hud.flash("%s left" % remotes[id].player_name, 2.5)
		remotes[id].queue_free()
		remotes.erase(id)


## Someone pinged something: show it in their colour, round the thing if it's here.
func _on_ping(peer: int, d: Dictionary) -> void:
	if not in_session:
		return
	var color := _paint()
	if peer != Shed.me() and remotes.has(peer):
		color = remotes[peer].color
	PingMarker.show_ping(world, d, color)
	if peer != Shed.me():
		hud.flash("%s pinged %s" % [d.get("name", "Someone"), str(d.get("what", "something")).to_lower()], 2.0)


func _on_state(id: int, state: PackedFloat32Array) -> void:
	if remotes.has(id):
		remotes[id].push_state(state)
