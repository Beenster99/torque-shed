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
var contract_panel: ContractPanel   # a customer's offer card and the jobs list
var contracts_view: ContractsView   # the customers walking in to reception
var traffic: RoadTraffic        # other bikers out on the roads
var sales_pc: SalesComputer     # the Sales page on the sales office's PC
var sales_view: SalesView       # part-exchange buyers, buyers collecting, the till, the stands' prices
var coffee_panel: CoffeePanel   # the cafe counter's menu, and talking to a biker about their bike
var coffee_view: CoffeeView     # the bikers at the cafe, its barista and the trays put down
var paint_bench: PaintBench     # the paint mixing bay's bench, stepped up to (see PaintBay)
var geometry: GeometryMode      # fitting a bike's parts by hand (F2)
var emote_bar: EmoteBar         # the emotes and their keys, while the bar is open (B)
var recovery: RecoveryView      # the recovery truck and trailer, and driving it (see Recovery)
var recovery_panel: RecoveryPanel   # the recovery jobs clipboard and a recovered bike's assessment
var audio: EngineSound
var saver: SaveGame
var remotes := {}     # peer id -> RemotePlayer
var in_session := false
var _send_timer := 0.0
var _stats_timer := 0.0
var _ride_km := 0.0
var _ride_top := 0.0
var _mounted_at := 0
var _dirt_km := 0.0
var _lap_seen := []           # the ride logger's lap counter: stretches of the test route passed (see ContractTestRide.lap_step)
var _laps := 0               # laps of it since the last ride stats went
var _fly_km := 0.0         # distance at speed since the last stats, for dead flies on the front
var _ride_dirt := 0.0      # road muck picked up since getting on, for drawing it on the bike
var _ride_view := ChaseCamera.Mode.CHASE
var _dash: Label3D
var telemetry_overlay: TelemetryOverlay   # live tyre and handling numbers at the side while riding (F3)
var _kb_bars := 0.0        # the keyboard's steer in Direct bars mode, ramped like a hand pushing harder
var _kb_lean := 0.0        # the keyboard's lean asked for, ramped (see ramp_lean)
## Seconds a lean key has to be held past a road rider's lean to ask for all the tyres will give.
const KEY_LEAN_ON := 1.25
## The last place the bike had both wheels on the map, to put it back if it goes off the edge.
var _safe_xf := Transform3D()
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
	telemetry_overlay = TelemetryOverlay.new()
	telemetry_overlay.visible = false
	ui.add_child(telemetry_overlay)
	emote_bar = EmoteBar.new()
	ui.add_child(emote_bar)
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
	contract_panel = ContractPanel.new()
	contract_panel.visible = false
	ui.add_child(contract_panel)
	contract_panel.closed.connect(func(): _capture_mouse(true))
	traffic = RoadTraffic.new()
	traffic.name = "Traffic"
	traffic.main = self
	traffic.world = world
	world.add_child(traffic)
	contracts_view = ContractsView.new()
	contracts_view.name = "Customers"
	contracts_view.main = self
	world.add_child(contracts_view)
	contracts_view.talk_requested.connect(func(id):
		contract_panel.open_offer(id)
		_capture_mouse(false))
	sales_pc = SalesComputer.new()
	sales_pc.visible = false
	ui.add_child(sales_pc)
	sales_pc.closed.connect(func(): _capture_mouse(true))
	sales_view = SalesView.new()
	sales_view.name = "SalesVisitors"
	sales_view.main = self
	world.add_child(sales_view)
	sales_view.talk_requested.connect(func(id):
		sales_pc.open_px(id)
		_capture_mouse(false))
	coffee_panel = CoffeePanel.new()
	coffee_panel.visible = false
	ui.add_child(coffee_panel)
	coffee_panel.closed.connect(func(): _capture_mouse(true))
	paint_bench = PaintBench.new()
	paint_bench.visible = false
	ui.add_child(paint_bench)
	paint_bench.closed.connect(func():
		if walker:
			walker.camera.current = true
		_capture_mouse(true))
	coffee_view = CoffeeView.new()
	coffee_view.name = "CafeVisitors"
	coffee_view.main = self
	world.add_child(coffee_view)
	coffee_view.talk_requested.connect(func(id):
		coffee_panel.open_visitor(id)
		_capture_mouse(false))
	coffee_view.order_requested.connect(func():
		coffee_panel.open_menu()
		_capture_mouse(false))
	recovery = RecoveryView.new()
	recovery.main = self
	world.add_child(recovery)
	recovery_panel = RecoveryPanel.new()
	recovery_panel.visible = false
	ui.add_child(recovery_panel)
	recovery_panel.closed.connect(func(): _capture_mouse(true))
	geometry = GeometryMode.new()
	ui.add_child(geometry)
	geometry.closed.connect(_geometry_closed)
	menu = MainMenu.new()
	ui.add_child(menu)
	menu.ride_solo.connect(func(): _start_session())
	menu.host_game.connect(_host)
	menu.join_game.connect(_join)
	menu.resume.connect(_close_menu)
	menu.leave_session.connect(_leave)
	menu.load_game.connect(load_game)
	menu.save_as.connect(func(called): saver.save_as(called))
	menu.save_renamed.connect(func(id, called):
		if in_session and id == SaveGame.active_slot():
			saver.save_name = called)
	menu.order_bike.connect(func():
		Shed.request({"a": "order"})
		_close_menu())
	menu.geometry_mode.connect(func():
		_close_menu()
		open_geometry())
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
	Shed.emoted.connect(_on_emote)
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
	hud.flash("Hosting. Opening the port on your router... the {menu} menu shows the address to give friends.", 6.0)


func _on_internet_status() -> void:
	if not Net.is_host():
		return
	if Net.internet_status == "open":
		hud.flash("Friends over the internet can join with %s" % (Net.external_ip if Net.external_ip != "" else "your public IP"), 8.0)
	elif Net.internet_status == "closed":
		hud.flash("Your router didn't open port %d automatically. See the {menu} menu for how to let friends in." % Net.PORT, 8.0, true)
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
		# Joining someone else's shed: your character comes from your own profile.json.
		Progress.select(Settings.player_name)
		Shed.join_remote()
	else:
		# Solo or hosting: the save game holds your character (outside the test scenes).
		if not SaveGame.characters_in_saves():
			Progress.select(Settings.player_name)
		if menu.new_shed:
			if menu.new_name != "":
				SaveGame.use_slot(SaveGame.new_id(menu.new_name))
			Shed.start_new(Settings.player_name)
			saver.begin_new(menu.new_name)
		elif not saver.continue_shed():
			Shed.start_new(Settings.player_name)
			saver.begin_new()
	menu.new_shed = false
	menu.new_name = ""
	walker = Walker.new()
	world.add_child(walker)
	walker.place(Workshop.walker_spawn(Net.local_slot()))
	walker.mount_requested.connect(_try_mount)
	walker.computer_requested.connect(_open_computer)
	walker.tuning_requested.connect(_open_tuning)
	walker.sales_requested.connect(_open_sales)
	walker.paint_bench_requested.connect(func():
		paint_bench.open()
		if paint_bench.visible:
			_capture_mouse(false))
	walker.label_requested.connect(func(id):
		label_dialog.open(id)
		_capture_mouse(false))
	walker.rename_requested.connect(func(id):
		label_dialog.open_bike(id)
		_capture_mouse(false))
	walker.camera.current = true
	hud.walker = walker
	emote_bar.walker = walker
	hud.visible = true
	for id in Net.players:
		if not remotes.has(id):
			_on_player_joined(id, Net.players[id])
	workshop.sync_state()
	_capture_mouse(true)
	hud.flash("Welcome to the shed. {menu} for the menu.", 4.0)
	saver.session_started()
	if SaveGame.last_saved == 0 and SaveGame.characters_in_saves():
		saver.save_soon()   # a new game shows on the Load screen (with its picture) in a moment


## Plays the save game `id`: saves and closes the one in play first (a co-op host's crew is
## sent back to their title screens), then opens it solo or hosted.
func load_game(id: String, as_host: bool) -> void:
	if in_session:
		saver.save_now()
		Net.leave()
		_end_session()
	SaveGame.use_slot(id)
	menu.new_shed = false
	if as_host:
		_host()
	else:
		_start_session()


func _leave() -> void:
	saver.save_now()
	Net.leave()
	_end_session()
	menu.show_title()


func _end_session() -> void:
	in_session = false
	computer.visible = false
	tuning.visible = false
	sales_pc.visible = false
	label_dialog.visible = false
	contract_panel.visible = false
	recovery_panel.visible = false
	coffee_panel.visible = false
	paint_bench.visible = false
	PaintBayRoom.live = {}
	recovery.stop_driving(false)
	if geometry.active:
		geometry.close()
	_stop_riding()
	for id in remotes.keys():
		remotes[id].queue_free()
	remotes.clear()
	if walker:
		walker.queue_free()
		walker = null
	Shed.stop()
	Progress.release(Settings.player_name)
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


## The sales office PC: the Sales page.
func _open_sales() -> void:
	sales_pc.open()
	_capture_mouse(false)


## The dyno desk: tune the bike on the rig, or one close by, and run it.
func _open_tuning() -> void:
	tuning.open(walker.global_position if walker else Vector3.ZERO)
	_capture_mouse(false)


## The recovery jobs clipboard (see RecoveryPanel).
func open_recovery() -> void:
	recovery_panel.open_list()
	_capture_mouse(false)


func _close_menu() -> void:
	menu.hide()
	_capture_mouse(true)


# ---------------------------------------------------------------------------- geometry mode

## The bike geometry mode would edit: the one you're looking at, else the nearest parked one
## within a few metres. 0 when there's none.
func geometry_bike() -> int:
	if walker == null:
		return 0
	var t: Dictionary = walker.target
	if t.get("kind", "") == "part" and int(t.get("bike", 0)) != 0 and workshop.bike_views.has(int(t["bike"])):
		return int(t["bike"])
	var best := 0
	var best_d := 4.0
	for id in workshop.bike_views:
		var d: float = (workshop.bike_views[id] as Node3D).global_position.distance_to(walker.global_position)
		if d < best_d and Shed.bikes.has(id) and Shed.bikes[id]["rider"] == 0:
			best_d = d
			best = id
	return best


## Opens geometry mode on the bike you're at: the mouse is freed and the camera orbits it.
func open_geometry() -> void:
	if bike != null or walker == null:
		return
	var id := geometry_bike()
	if id == 0:
		hud.flash("Walk up to a bike and look at it to fit its parts in geometry mode.", 2.5, true)
		return
	if not Shed.bike_at_work(id):
		hud.flash("Out here it's just a bike to ride. Ride it back to the shed to fit its parts.", 2.5, true)
		return
	if not geometry.open(id, workshop, walker.camera):
		hud.flash("That bike can't be edited right now.", 2.0, true)
		return
	walker.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	_capture_mouse(false)


func _geometry_closed() -> void:
	if not in_session:
		return
	hud.visible = true
	if walker:
		walker.process_mode = Node.PROCESS_MODE_INHERIT
		if bike == null:
			walker.camera.current = true
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
	_refit_ridden_bikes()
	if Recovery.driver() == Shed.me() and not recovery.driving and bike == null:
		recovery.start_driving()
	elif recovery.driving and Recovery.driver() != Shed.me():
		recovery.stop_driving(false)
	var mine := Shed.riding(Shed.me())
	if mine != 0 and bike == null:
		_start_riding(mine)
	elif mine == 0 and bike != null and riding_id != 0:
		_stop_riding()


## A fit saved in geometry mode shows at once on the bikes out riding too (yours and the
## crew's), not only on the next ride.
func _refit_ridden_bikes() -> void:
	if bike != null and riding_id != 0 and Shed.bikes.has(riding_id):
		_refit_model(bike.model, Shed.geometry_of(riding_id))
	for peer in remotes:
		var rp = remotes[peer]
		if is_instance_valid(rp) and rp.bike != null and Shed.bikes.has(rp.riding_bike):
			_refit_model(rp.bike.model, Shed.geometry_of(rp.riding_bike))


static func _refit_model(model: BikeModel, geo: Dictionary) -> void:
	if model != null and str(model.geometry) != str(geo):
		model.apply_geometry(geo.duplicate(true))


func _start_riding(bike_id: int) -> void:
	var data: Dictionary = Shed.bikes[bike_id]
	riding_id = bike_id
	bike = Bike.new()
	bike.rider_color = _paint()
	bike.rider_gear = RiderGear.worn_of(Shed.me())
	bike.skills = Progress.rider_skills()
	bike.ride_xp = RideXP.new(bike_id)
	bike.telemetry = RideTelemetry.new(str(data.get("name", "")))
	bike.setup(Shed.build_of(bike_id), data["paint"])
	# Tyres, brakes and engine as cold as the shed, or still warm from a ride a moment ago.
	BikeHeat.resume(bike_id, bike.heat)
	bike.model.apply_geometry(Shed.geometry_of(bike_id))
	bike.set_meta("shed_bike", bike_id)   # so the shed TVs know whose ride this is
	world.add_child(bike)
	var xf: Transform3D = data["xf"]
	bike.place(xf.origin, xf.basis.get_euler().y)
	_safe_xf = Transform3D()
	bike.crashed.connect(func(): hud.flash("Crashed!", 1.5, true))
	# You get on with the engine off and start it yourself.
	bike.engine_on = false
	bike.rpm = 0.0
	bike.engine_changed.connect(func(running, reason):
		if running:
			hud.flash("Engine running", 1.2)
			if bike and bike.ride_xp:
				bike.ride_xp.engine_started()
		elif reason != "":
			hud.flash(reason, 3.0, true))
	audio = EngineSound.new()   # engine, exhaust, pops, gear shifts and the starter
	bike.add_child(audio)
	audio.setup(bike.build, bike.model)
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
	_lap_seen = []
	_laps = 0
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
	Sfx.play_at("switch", bike.global_position, -10.0)   # the starter itself is the engine sound's


func _stop_riding() -> void:
	if bike:
		BikeHeat.park(riding_id, bike.heat)
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
	if not in_session or geometry.active:
		return   # geometry mode takes its own keys, Esc and F2 included
	if event.is_action_pressed("geometry_mode") and bike == null and walker and not menu.visible and not computer.visible \
			and not tuning.visible and not sales_pc.visible and not label_dialog.visible and not contract_panel.visible and not coffee_panel.visible \
			and not paint_bench.visible:
		get_viewport().set_input_as_handled()
		open_geometry()
		return
	if event.is_action_pressed("menu"):
		if label_dialog.visible:
			label_dialog.close_dialog()
		elif contract_panel.visible:
			contract_panel.close_dialog()
		elif recovery_panel.visible:
			recovery_panel.close_dialog()
		elif coffee_panel.visible:
			coffee_panel.close_dialog()
		elif paint_bench.visible:
			paint_bench.close_dialog()
		elif computer.visible:
			computer.close_computer()
		elif tuning.visible:
			tuning.close_computer()
		elif sales_pc.visible:
			sales_pc.close_computer()
		elif menu.visible:
			_close_menu()
		else:
			saver.grab_thumbnail()   # before the menu covers the shed
			menu.show_pause()
			_capture_mouse(false)
		get_viewport().set_input_as_handled()
		return
	if menu.visible or computer.visible or tuning.visible or sales_pc.visible or label_dialog.visible or contract_panel.visible or coffee_panel.visible \
			or paint_bench.visible or recovery_panel.visible or (bike == null and not recovery.driving):
		return
	if recovery.driving:
		if recovery.drive_input(event):
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ping"):
			PingMarker.ping_from(camera, [recovery.car.get_rid()])
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
		# Swing the chase camera round the bike (or turn your head in first person).
		var rel: Vector2 = event.relative
		camera.add_orbit(-rel.x * ChaseCamera.MOUSE_ORBIT, rel.y * ChaseCamera.MOUSE_ORBIT)
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
	elif event.is_action_pressed("ride_by"):
		camera.start_ride_by()
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
	elif event.is_action_pressed("telemetry"):
		Settings.telemetry_overlay = not Settings.telemetry_overlay
		hud.flash("Telemetry %s" % ("on" if Settings.telemetry_overlay else "off"), 1.2)
	elif event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		hud.flash("Auto-shift %s" % ("on" if Settings.auto_shift else "off"), 1.5)


func _physics_process(delta: float) -> void:
	if not in_session:
		return
	var active := not menu.visible and not computer.visible and not tuning.visible and not sales_pc.visible and not label_dialog.visible \
		and not contract_panel.visible and not coffee_panel.visible and not paint_bench.visible and not geometry.active \
		and not recovery_panel.visible
	# The whiteboard's picture file dialog is up: hands off the controls till it closes.
	active = active and not get_tree().get_nodes_in_group("whiteboard").any(func(b): return b.picking)
	if walker:
		walker.controls_enabled = active
	if bike:
		var stick := Controls.stick()
		if active:
			bike.throttle = maxf(Input.get_action_strength("throttle"), Controls.trigger(true))
			bike.front_brake = maxf(Input.get_action_strength("front_brake"), Controls.trigger(false))
			bike.rear_brake = Input.get_action_strength("rear_brake")
			bike.lean_input = _steer_input(stick.x, delta)
			bike.body_shift = clampf(Input.get_axis("body_back", "body_forward") - stick.y, -1.0, 1.0)
			# The right stick swings the camera round, as the mouse does.
			var look := Controls.stick(true)
			if look != Vector2.ZERO:
				camera.add_orbit(-look.x * ChaseCamera.STICK_ORBIT * delta, look.y * ChaseCamera.STICK_ORBIT * delta)
		else:
			bike.throttle = 0.0
			bike.lean_input = 0.0
			bike.body_shift = 0.0
			bike.front_brake = 1.0
			bike.rear_brake = 1.0
		bike.auto_shift = Settings.auto_shift
		camera.recentre = Settings.camera_recentre
		bike.assist = Settings.assist
		bike.direct_bars = Settings.direct_bars
		bike.horn = active and Input.is_action_pressed("horn")
		audio.rpm = bike.rpm
		audio.gear = bike.gear
		audio.throttle = bike.sound_load()
		audio.running = bike.engine_on
		audio.speed = bike.speed
		audio.cranking = bike.is_starting()
		audio.view = "rider" if camera.mode == ChaseCamera.Mode.HELMET else "chase"
		var km := absf(bike.speed) * delta / 1000.0
		_ride_km += km
		hud.trip_km += km
		_ride_top = maxf(_ride_top, absf(bike.speed) * 3.6)
		_track_lap()
		if bike.wheels[1]["contact"] or bike.wheels[0]["contact"]:
			# Loose ground and wheelspin throw muck all over the bike, more of it the faster you go,
			# and a wet road throws up a lot more spray (mud more still: see Dirt.accrue).
			var wet := Weather.wetness()
			var paved: bool = bike.surface in ["tarmac", "concrete"]
			var pace := 0.7 + 0.3 * minf(absf(bike.speed) * 3.6 / 50.0, 2.0)
			var muck := km * float(SURFACE_DIRT.get(bike.surface, 0.3)) * (1.0 + float(bike.wheels[1]["slip"])) \
				* (1.0 + wet * (3.0 if paved else 1.0)) * pace
			_dirt_km += muck
			_ride_dirt += muck * Shed.ROAD_DIRT * 0.8
		# Dead flies on the front at speed (fewer in the rain).
		_fly_km += km * clampf((absf(bike.speed) * 3.6 - 30.0) / 70.0, 0.0, 1.5) * (1.0 - 0.6 * Weather.rain_level())
		_update_dash()
		_keep_on_map()
		_stats_timer += delta
		if _stats_timer >= 1.0:
			_stats_timer = 0.0
			_send_ride_stats()
	recovery.drive_physics(delta, active)
	telemetry_overlay.bike = bike
	telemetry_overlay.visible = bike != null and Settings.telemetry_overlay and not menu.visible
	_send_timer += delta
	if _send_timer >= 1.0 / 30.0:
		_send_timer = 0.0
		Net.send_state(_net_state())


## The steer input: a lean to aim for, or with Direct bars the push on the bars. Keys are all or
## nothing, so on Direct bars they're ramped up like a hand pushing harder (and let off quicker);
## the stick is squared there, for fine pushes near the middle. Leaning on keys, a key held asks
## for a road rider's lean straight away and only creeps on towards the most the tyres hold if
## it's kept held (see ramp_lean).
func _steer_input(stick_x: float, delta: float) -> float:
	var keys := Input.get_axis("lean_left", "lean_right")
	if not Settings.direct_bars:
		_kb_bars = 0.0
		_kb_lean = ramp_lean(_kb_lean, keys, delta)
		return clampf(_kb_lean + stick_x, -1.0, 1.0)
	_kb_lean = 0.0
	_kb_bars = ramp_bars(_kb_bars, keys, delta)
	return clampf(_kb_bars + stick_x * absf(stick_x), -1.0, 1.0)


## Leaning on keys: the lean input `held` so far for the keys' `keys` (-1, 0 or 1). Pressed, it
## goes straight to Bike.ROAD_INPUT (an ordinary road lean); held on, it creeps the rest of the
## way over KEY_LEAN_ON seconds, so only a long, committed press leans the bike right over.
## Let go, it comes back at once.
static func ramp_lean(held: float, keys: float, delta: float) -> float:
	if keys == 0.0:
		return move_toward(held, 0.0, 8.0 * delta)
	var a := absf(held) if keys * held > 0.0 else 0.0
	if a < Bike.ROAD_INPUT:
		a = minf(a + 6.0 * delta, Bike.ROAD_INPUT)
	else:
		a = minf(a + (1.0 - Bike.ROAD_INPUT) / KEY_LEAN_ON * delta, 1.0)
	return a * signf(keys)


## Direct bars on keys: the push `held` so far moves towards the keys' `keys` (-1, 0 or 1),
## building up over 0.4 s and let off quicker.
static func ramp_bars(held: float, keys: float, delta: float) -> float:
	var easing := absf(keys) < absf(held) or keys * held < 0.0
	return move_toward(held, keys, (6.0 if easing else 2.5) * delta)


## Off the edge of the map (or through it): the bike goes back to the last place it had its
## wheels on the ground, rather than falling forever.
func _keep_on_map() -> void:
	var p := bike.global_position
	var lost := p.y < world.terrain_height(p.x, p.z) - 15.0 or absf(p.x) > World.MAP_HALF - 1.0 or absf(p.z) > World.MAP_HALF - 1.0
	if lost and _safe_xf != Transform3D():
		var fwd := -_safe_xf.basis.z
		bike.place(_safe_xf.origin, atan2(-fwd.x, -fwd.z) + PI)
		hud.flash("That's the edge of the map. Turned round and put back on the ground.", 3.0, true)
		camera.snap()
	elif not lost and bike.wheels[0]["contact"] and bike.wheels[1]["contact"] and not bike.is_crashed \
			and absf(p.x) < World.MAP_HALF - 12.0 and absf(p.z) < World.MAP_HALF - 12.0:
		_safe_xf = Transform3D(bike.global_basis, p - Vector3.UP * bike.build.rear_radius)


## Tells the shed how far the bike went, how muddy it got and how much petrol it burnt.
func _send_ride_stats() -> void:
	if bike == null:
		return
	hud.trip_fuel += bike.fuel_used
	var ride := {"a": "ride", "km": _ride_km, "top_kmh": _ride_top, "kmh": absf(bike.speed) * 3.6,
		"dirt_km": _dirt_km, "fly_km": _fly_km, "fuel": bike.fuel_used, "spin": bike.take_burnout_time()}
	ride.merge(_logger_peaks(), true)
	if _laps > 0:
		ride["laps"] = _laps
		_laps = 0
	Shed.request(ride)
	bike.fuel_used = 0.0
	_ride_km = 0.0
	_dirt_km = 0.0
	_fly_km = 0.0
	# The muck builds up on the bike as you ride (as the shed has it: a moment behind online).
	var riding := Shed.riding(Shed.me())
	if riding != 0 and Shed.bikes.has(riding) and bike.model:
		bike.model.show_dirt(Dirt.of_bike(riding))


## The ride logger's lap counter: which stretch of the test route (The Loop) the bike is on, if
## it's on it, and a lap counted when it's been along all of them.
func _track_lap() -> void:
	if world == null or world.roads == null:
		return
	var p := bike.global_position
	var hit := world.roads.nearest(p.x, p.z, 9.0)
	if hit.is_empty():
		return
	var road: Dictionary = world.roads.roads[int(hit["road"])]
	if str(road["name"]) != ContractTestRide.LAP_ROAD:
		return
	var n := maxi(1, (road["xz"] as PackedVector2Array).size())
	if ContractTestRide.lap_step(_lap_seen, int(hit["i"]) * ContractTestRide.LAP_SECTORS / n):
		_laps += 1
		if Shed.bikes.get(riding_id, {}).get("proto", false):
			hud.flash("Lap of %s logged." % ContractTestRide.route_name(ContractTestRide.LAP_ROAD), 2.0)


## The ride logger's peaks since the last ride stats went (a test ride's checks, see
## ContractTestRide.note_ride): the most lean, the hardest braking, and the worst shake at speed.
func _logger_peaks() -> Dictionary:
	var tel := bike.telemetry if bike else null
	if tel == null or tel.size() == 0:
		return {}
	var out := {"lean": 0.0, "brake_g": 0.0, "wobble": 0.0}
	var t: PackedFloat32Array = tel.data["t"]
	var v: PackedFloat32Array = tel.data["speed"]
	for i in range(tel.index_since(1.5), tel.size()):
		out["lean"] = maxf(out["lean"], absf(tel.data["lean"][i]))
		# Braking over a quarter of a second or so, so a bump doesn't read as a stop.
		var j := i
		while j > 0 and t[i] - t[j] < 0.25:
			j -= 1
		if t[i] - t[j] > 0.1:
			out["brake_g"] = maxf(out["brake_g"], (v[j] - v[i]) / 3.6 / (t[i] - t[j]) / Bike.G)
		if tel.data["speed"][i] >= ContractTestRide.FAST:
			out["wobble"] = maxf(out["wobble"], tel.data["wobble"][i])
	return out


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
	if recovery and recovery.driving:
		return recovery.net_state()
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
		# And their figure points at it.
		if remotes.has(peer):
			remotes[peer].play_emote("point", d.get("at"))


## Someone did an emote (see Emotes): their figure does it here, and the HUD says so.
func _on_emote(peer: int, d: Dictionary) -> void:
	if not in_session:
		return
	var e := str(d.get("e", ""))
	if not Emotes.is_emote(e):
		return
	if peer == Shed.me():
		hud.flash(str(Emotes.YOU[e]), 1.2)
		return
	if remotes.has(peer):
		remotes[peer].play_emote(e, d.get("at"))
	hud.flash("%s %s" % [d.get("name", "Someone"), Emotes.VERBS[e]], 1.5)


func _on_state(id: int, state: PackedFloat32Array) -> void:
	if remotes.has(id):
		remotes[id].push_state(state)
