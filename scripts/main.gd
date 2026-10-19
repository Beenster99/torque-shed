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
var staff_panel: StaffPanel     # talking to one of the staff and giving them a job
var staff_view: StaffView       # the garage's staff at work
var paint_bench: PaintBench     # the paint mixing bay's bench, stepped up to (see PaintBay)
var geometry: GeometryMode      # fitting a bike's parts by hand (F2)
var emote_bar: EmoteBar         # the emotes and their keys, while the bar is open (B)
var recovery: RecoveryView      # the recovery truck and trailer, and driving it (see Recovery)
var recovery_panel: RecoveryPanel   # the recovery jobs clipboard and a recovered bike's assessment
var trip: AdventureTrip         # out on an adventure ride: its road, and getting there and back
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
var _was_bottomed := [false, false]   # each wheel's suspension bottomed last frame (a kerb or pothole hit)
var _flat_told := [false, false]      # told the rider this tyre has gone flat, this ride
var _fault_seen := {}      # the ridden bike's faults as last told to the rider (see Roadside)
var _fault_wait := 0.0     # seconds before the next breakdown roll (one asked for is on its way)
var _fault_rates := {}     # the ridden bike's chance of each breakdown a km, worked out now and then
var _rates_timer := 0.0
var _rattle_timer := 0.0   # the next rattle or chain slap, seconds
var _tow_check := 0.0
var _ride_view := ChaseCamera.Mode.CHASE
var _dash: Label3D
var fuel_stop: FuelStop    # filling up at a pump, and the low fuel warning, while riding
var satnav: Satnav         # the sat nav's live map while riding a bike with one
var hud_satnav: SatnavScreen   # the sat nav's map on the HUD (Settings.satnav_hud)
var telemetry_overlay: TelemetryOverlay   # live tyre and handling numbers at the side while riding (F3)
var _kb_bars := 0.0        # the keyboard's steer in Direct bars mode, ramped like a hand pushing harder
var _kb_lean := 0.0        # the keyboard's lean asked for, ramped (see ramp_lean)
## Seconds a lean key has to be held past a road rider's lean to ask for all the tyres will give.
const KEY_LEAN_ON := 1.25
## The last place the bike had both wheels on the map, to put it back if it goes off the edge.
var _safe_xf := Transform3D()
var _neutral_hint_at := 0   # ticks: when the "in neutral" hint may show again
var _fade: ColorRect        # the black that fades in and out going back to the garage
var _going_home := false
## The bike you've just got off, and when (ticks, ms): online the shed still has you on it
## until the host hears, and getting back on it meanwhile (back where it was got on, often the
## garage) flashed you there and back. A refused dismount gives it back after LEFT_WAIT_MS.
var _left_bike := 0
var _left_at := 0
const LEFT_WAIT_MS := 3000
## Further than this (m, from the shed's middle) and outside every room, you're out in the world
## and the Esc menu offers to take you back to the garage.
const HOME_RANGE := 30.0
## The first spot of the row in the Build Yard where bikes brought home are parked when every bay
## is taken (see garage_spot): clear of the jumps, facing up the yard. The row runs east and back.
const YARD_ROW := Vector3(14.0, 0.0, 32.0)
## How much road dirt a kilometre of each surface throws up, relative to a dirt track.
const SURFACE_DIRT := {"tarmac": 0.06, "dirt": 1.0, "grass": 0.7, "gravel": 0.6, "sand": 0.45, "snow": 0.3}


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
	hud_satnav = SatnavScreen.new()
	hud_satnav.framed = true
	hud_satnav.visible = false
	hud_satnav.anchor_top = 1.0
	hud_satnav.anchor_bottom = 1.0
	hud_satnav.offset_left = 24.0
	hud_satnav.offset_right = 24.0 + 300.0
	hud_satnav.offset_top = -24.0 - 200.0
	hud_satnav.offset_bottom = -24.0
	ui.add_child(hud_satnav)
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
	staff_panel = StaffPanel.new()
	staff_panel.visible = false
	ui.add_child(staff_panel)
	staff_panel.closed.connect(func(): _capture_mouse(true))
	staff_view = StaffView.new()
	staff_view.name = "Staff"
	staff_view.main = self
	world.add_child(staff_view)
	staff_view.talk_requested.connect(func(id):
		staff_panel.open_worker(id)
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
	menu.staff.talk_requested.connect(func(id):
		menu.hide()
		staff_panel.open_worker(id)
		_capture_mouse(false))
	menu.home_check = home_reason
	menu.go_home.connect(func():
		_close_menu()
		go_home())
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
	trip = AdventureTrip.new()
	trip.main = self
	add_child(trip)

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
	if Shed.is_authority() and not Progress._in_tests():
		AdventureDest.hang_album(Settings.player_name)   # your adventure photos go up in your own shed too
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
	staff_panel.visible = false
	paint_bench.visible = false
	PaintBayRoom.live = {}
	recovery.stop_driving(false)
	if geometry.active:
		geometry.close()
	_stop_riding()
	trip.reset()
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


# ---------------------------------------------------------------------------- back to the garage

## Whether "Back to the garage" can be used now: "" when it can, "home" when you're already at
## the garage (the menu hides it), otherwise why not.
func home_reason() -> String:
	if not in_session or walker == null:
		return "home"
	if trip.on_trip():
		return trip.home_reason()
	if recovery.driving:
		return "You're in the truck: drive it back, or get out ({interact}) first."
	if recovery.riding_along:
		return "You're in the truck's passenger seat: get out ({interact}) first."
	var at: Vector3 = bike.global_position if bike else walker.global_position
	if Workshop.room_at(at) != "" or Vector2(at.x - Workshop.CENTER.x, at.z - Workshop.CENTER.z).length() < HOME_RANGE:
		return "home"
	if bike == null and (Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0):
		return "Let go of what you're pushing first."
	return ""


## Stranded out in the world: a short fade to black, then you're back at the shed door on foot,
## and the bike you were riding is parked in its bay (another free one, or the yard by the roller
## door when they're all full), so it isn't left out on the road. `instant` skips the fade (tests).
func go_home(instant := false) -> void:
	if _going_home or home_reason() != "":
		return
	_going_home = true
	if not instant:
		await _fade_to(1.0)
	if bike != null:
		if bike.is_crashed:
			bike.respawn()   # picks the rider up off the road first
		_send_ride_stats()
		# Through the shed's state like getting off, so a co-op client's bike is parked for everyone.
		Shed.request({"a": "dismount", "bike": riding_id, "xf": garage_spot(riding_id)})
		_stop_riding()
	walker.place(Workshop.walker_spawn(Net.local_slot()))
	camera.snap()
	hud.flash("Back at the garage.", 2.0)
	_going_home = false
	if not instant:
		await _fade_to(0.0)


func _fade_to(alpha: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 90
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.35)
	await tw.finished


## Where a bike brought back to the garage is parked: its own bay if it's free, else another free
## bay, else a free spot in a row at the front of the Build Yard behind the shed (YARD_ROW; the
## forecourt out front is the car park and the street).
static func garage_spot(bike_id: int) -> Transform3D:
	var own := int(Shed.bikes[bike_id].get("bay", -1)) if Shed.bikes.has(bike_id) else -1
	var order := [own] if own >= 0 and own < Workshop.bay_count() else []
	for bay in Workshop.bay_count():
		if bay != own:
			order.append(bay)
	for bay in order:
		var o := Workshop.bay_transform(bay).origin
		if not Shed.holograms.has(bay) and not _bike_near(o, 2.5, bike_id):
			return Workshop.bay_transform(bay)
	for i in 24:
		var at := YARD_ROW + Vector3(float(i % 6) * 2.0, 0.0, -float(i / 6) * 3.0)
		if not _bike_near(at, 1.4, bike_id):
			return Transform3D(Basis(), at)
	return Transform3D(Basis(), YARD_ROW)


## Whether any bike but `except` stands within `r` metres of `at`.
static func _bike_near(at: Vector3, r: float, except: int) -> bool:
	for id in Shed.bikes:
		if int(id) != except and (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(at) < r:
			return true
	return false


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
	_left_bike = 0
	Shed.request({"a": "mount", "bike": bike_id})


func _on_shed_changed() -> void:
	if not in_session:
		return
	trip.sync()
	workshop.sync_state()
	_refit_ridden_bikes()
	_sync_faults()
	if Recovery.driver() == Shed.me() and not recovery.driving and bike == null and not recovery.just_left(true):
		recovery.start_driving()
	elif recovery.driving and Recovery.driver() != Shed.me():
		recovery.stop_driving(false)
	var mine := Shed.riding(Shed.me())
	if mine == 0 or mine != _left_bike or Time.get_ticks_msec() - _left_at > LEFT_WAIT_MS \
			or bool(Shed.bikes[mine].get("push", false)):   # taken hold of to push it at the roadside (see Roadside)
		_left_bike = 0
	if mine != 0 and bike == null and mine != _left_bike:
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
	if trip.on_trip():
		# Out on an adventure: on the grid at its start, or where it was left at the roadside.
		var spot := Roadside.spot_of(bike_id)
		xf = Roadside.xf_in(trip.world, spot) if not spot.is_empty() else trip.start_xf()
	bike.place(xf.origin, xf.basis.get_euler().y)
	bike.respawn_at = trip.respawn_spot   # a crash off an adventure's road: back on it
	_safe_xf = Transform3D()
	bike.crashed.connect(func():
		hud.flash("Crashed!", 1.5, true)
		_drop_faults())
	# You get on with the engine off and the box in neutral, as a parked bike is, and start it yourself.
	bike.engine_on = false
	bike.rpm = 0.0
	bike.gear = Bike.NEUTRAL
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
	_was_bottomed = [false, false]
	_flat_told = [false, false]
	_fault_seen = {}
	_fault_wait = 2.0
	_rates_timer = 0.0
	_sync_faults()
	_lap_seen = []
	_laps = 0
	hud.trip_km = 0.0
	hud.trip_fuel = 0.0
	_dash = bike.model.dash_readout()
	fuel_stop = FuelStop.new(bike)
	hud.fuel_stop = fuel_stop
	satnav = Satnav.new(bike, world)
	satnav.hud_screen = hud_satnav
	add_child(satnav)
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
	var step := ground - right * 0.9
	if trip.on_trip():
		step = trip.step_off_spot(ground, heading)   # onto ground you can stand on, across a mountainside
	walker.place(Transform3D(Basis(Vector3.UP, heading), step))
	_send_ride_stats()
	var off := {"a": "dismount", "bike": riding_id, "xf": Transform3D(Basis(Vector3.UP, heading), ground)}
	if trip.on_trip():
		# Out on an adventure it stays where it's left, for everyone (see Roadside, RoadsideView).
		off["roadside"] = Roadside.spot_for(trip.world, Transform3D(Basis(Vector3.UP, heading), ground))
	Shed.request(off)
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


## Moves an adjustable screen `by` (a share of its travel) up or down its rails while riding:
## at once on this bike, and the shed is told so it stays where it's set (Shed "screen").
func _move_screen(by: float) -> void:
	var build := bike.build
	if build.screen_adjust <= 0.0:
		hud.flash("This screen doesn't adjust" if build.has_part("fairing") else "No screen to adjust", 1.5)
		return
	var v := clampf(build.tune_value("screen") + by, 0.0, 1.0)
	build.set_screen(v)
	bike.model.set_screen_raise(build.screen_raise)
	Shed.request({"a": "screen", "value": v, "bike": riding_id})
	hud.flash("Screen %s" % ("right up" if v >= 0.99 else "right down" if v <= 0.01 else "%d%% up" % roundi(v * 100.0)), 1.0)


func _stop_riding() -> void:
	if fuel_stop:
		var paid := fuel_stop.finish()
		if paid != "":
			hud.flash(paid, 2.5)
	fuel_stop = null
	hud.fuel_stop = null
	hud.ride_hint = ""
	hud.warn_lights = []
	if satnav:
		satnav.queue_free()
		satnav = null
	if bike:
		BikeHeat.park(riding_id, bike.heat)
	if riding_id != 0:
		_left_bike = riding_id
		_left_at = Time.get_ticks_msec()
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
			and not tuning.visible and not sales_pc.visible and not label_dialog.visible and not contract_panel.visible and not coffee_panel.visible and not staff_panel.visible \
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
		elif staff_panel.visible:
			staff_panel.close_dialog()
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
	if menu.visible or computer.visible or tuning.visible or sales_pc.visible or label_dialog.visible or contract_panel.visible or coffee_panel.visible or staff_panel.visible \
			or paint_bench.visible or recovery_panel.visible or (bike == null and not recovery.driving and not recovery.riding_along):
		return
	if recovery.riding_along:
		if recovery.passenger_input(event):
			get_viewport().set_input_as_handled()
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
		# Stopped at a pump with room in the tank, holding it fills up (see FuelStop); else off you get.
		var fuelled := false
		if fuel_stop and fuel_stop.pump_here() != null and fuel_stop.space() >= 0.05:
			var why := fuel_stop.start()
			fuelled = why == ""
			if not fuelled:
				hud.flash(why, 2.0, true)
		if not fuelled and Time.get_ticks_msec() - _mounted_at >= GET_OFF_DELAY * 1000.0:
			_get_off()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("alt_act") and trip.on_trip():
		_tow_button()
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
	elif event.is_action_pressed("satnav_hud"):
		Settings.satnav_hud = not Settings.satnav_hud
		if bike.build.has_part("satnav"):
			hud.flash("Sat nav on the HUD %s" % ("on" if Settings.satnav_hud else "off"), 1.2)
		else:
			hud.flash("No sat nav on this bike", 1.5)
	elif event.is_action_pressed("screen_up") or event.is_action_pressed("screen_down"):
		_move_screen(0.2 if event.is_action_pressed("screen_up") else -0.2)
	elif event.is_action_pressed("telemetry"):
		Settings.telemetry_overlay = not Settings.telemetry_overlay
		hud.flash("Telemetry %s" % ("on" if Settings.telemetry_overlay else "off"), 1.2)
	elif event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		hud.flash("Auto-shift %s" % ("on" if Settings.auto_shift else "off"), 1.5)


func _physics_process(delta: float) -> void:
	var pt := Perf.t0()
	_physics_process_body(delta)
	Perf.add("main_ride", pt)


func _physics_process_body(delta: float) -> void:
	if not in_session:
		return
	var active := not menu.visible and not computer.visible and not tuning.visible and not sales_pc.visible and not label_dialog.visible \
		and not contract_panel.visible and not coffee_panel.visible and not staff_panel.visible and not paint_bench.visible and not geometry.active \
		and not recovery_panel.visible and not trip.map_open() and not trip.magazine_open()
	# The whiteboard's picture file dialog is up: hands off the controls till it closes.
	active = active and not get_tree().get_nodes_in_group("whiteboard").any(func(b): return b.picking)
	if walker:
		# Holding the cursor on a touch screen (see ScreenTouch) you stand still.
		walker.controls_enabled = active and (walker.touch == null or walker.touch.focused == "")
	if bike:
		var stick := Controls.stick()
		bike.controls_enabled = active   # a menu up: brakes on, and held still once stopped
		if active:
			bike.throttle = maxf(Input.get_action_strength("throttle"), Controls.trigger(true))
			bike.front_brake = maxf(Input.get_action_strength("front_brake"), Controls.trigger(false))
			bike.rear_brake = Input.get_action_strength("rear_brake")
			if trip.police_hold():
				# Pulled over by the police: off the throttle and braking to a stop, still steering.
				bike.throttle = 0.0
				bike.front_brake = maxf(bike.front_brake, 0.35)
				bike.rear_brake = maxf(bike.rear_brake, 0.5)
			# Tired out on an adventure the bars answer slower (see AdventureNeedsView.steer).
			bike.lean_input = trip.needs.steer(_steer_input(stick.x, delta), delta)
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
		_puncture_rolls(km)
		if trip.on_trip():
			_roadside_step(km, delta)
		if fuel_stop:
			var filled := fuel_stop.update(delta, active and Input.is_action_pressed("interact"))
			if filled != "":
				hud.flash(filled, 3.0)
			var low := fuel_stop.warning()
			if low != "":
				hud.flash(low, 4.0, true)
		# Dead flies on the front at speed (fewer in the rain).
		_fly_km += km * clampf((absf(bike.speed) * 3.6 - 30.0) / 70.0, 0.0, 1.5) * (1.0 - 0.6 * Weather.rain_level())
		_update_dash()
		if bike.gear == Bike.NEUTRAL and not bike.auto_shift and bike.engine_on and bike.throttle > 0.3 \
				and Time.get_ticks_msec() > _neutral_hint_at:
			# Revving away in neutral with a manual box: say how to find first.
			_neutral_hint_at = Time.get_ticks_msec() + 5000
			hud.flash("In neutral. {shift_down} for first gear.", 2.0)
		_keep_on_map()
		_stats_timer += delta
		if _stats_timer >= 1.0:
			_stats_timer = 0.0
			_send_ride_stats()
	recovery.drive_physics(delta, active)
	telemetry_overlay.bike = bike
	telemetry_overlay.visible = bike != null and Settings.telemetry_overlay and not menu.visible
	hud_satnav.visible = bike != null and satnav != null and satnav.fitted() and bike.engine_on and Settings.satnav_hud and not menu.visible
	_send_timer += delta
	if _send_timer >= 1.0 / 30.0:
		_send_timer = 0.0
		Net.send_state(trip.tag_state(_net_state()))


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
	if trip.on_trip():
		return   # the adventure keeps you on its own road (AdventureTrip._keep_on_road)
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
	_sync_tyre_air()
	bike.fuel_used = 0.0
	_ride_km = 0.0
	_dirt_km = 0.0
	_fly_km = 0.0
	# The muck builds up on the bike as you ride (as the shed has it: a moment behind online).
	var riding := Shed.riding(Shed.me())
	if riding != 0 and Shed.bikes.has(riding) and bike.model:
		bike.model.show_dirt(Dirt.of_bike(riding))


## Now and then a tyre picks up a puncture: a nail or a thorn as the km go by (more off the road),
## or a pinch from a hard hit on a kerb or a pothole (see Puncture). The bike starts letting its
## air out straight away; the shed is told, so the crew see it and it's saved.
func _puncture_rolls(km: float) -> void:
	if bike.heat == null or bike.is_crashed:
		return
	for i in 2:
		var w: Dictionary = bike.wheels[i]
		var hit: bool = bool(w.get("bottomed", false)) and not _was_bottomed[i]
		_was_bottomed[i] = bool(w.get("bottomed", false))
		if not w["contact"] or bike.heat.leak[i] > 0.0:
			continue
		if Puncture.ride_punctures(str(w.get("surface", bike.surface)), km, randf()) \
				or (hit and Puncture.hit_punctures(bike.speed, randf())):
			var kind := Puncture.kind_of_roll(randf())
			bike.heat.leak[i] = Puncture.rate_of_kind(kind)
			Shed.request({"a": "puncture", "side": "front" if i == 0 else "rear", "kind": kind})


## Out on an adventure, now and then something goes wrong with the bike as the km go by (see
## Roadside: more on loose ground, worn parts and skipped maintenance): the shed is told, and
## the rider hears and sees it (_sync_faults). Also its rattles and chain slap, and the tow strap.
func _roadside_step(km: float, delta: float) -> void:
	var pt := Perf.t0()
	_rates_timer -= delta
	if _rates_timer <= 0.0:
		_rates_timer = 1.0
		_fault_rates = Roadside.rates(Roadside.condition(riding_id), bike.surface)
	_fault_wait -= delta
	if _fault_wait <= 0.0 and not bike.is_crashed and not bike.pushing and km > 0.0:
		var kind := Roadside.roll(_fault_rates, km, randf())
		if kind != "" and Shed.check(Shed.me(), {"a": "roadside_fault", "kind": kind}) == "":
			Shed.request({"a": "roadside_fault", "kind": kind})
			_fault_wait = 3.0
	_roadside_sounds(delta)
	_tow_step(delta)
	if bike.pushing and bike.model:
		bike.model.set_rider_visible(false)   # walking beside it
	var hint := ""
	if int(Shed.bikes[riding_id].get("tow", 0)) != 0:
		hint = "On the tow strap to the next stop   ·   {work2}: let it go"
	elif bike.pushing:
		hint = "Pushing it: {throttle} to walk it along   ·   {interact}: stop and stand it up"
	elif absf(bike.speed) < 2.0 and not bike.is_crashed and (Roadside.dead(riding_id) or not Roadside.active(riding_id).is_empty()):
		hint = "{interact}: get off and fix it at the roadside   ·   {work2}: ask a mate for a tow"
	hud.ride_hint = hint
	Perf.add("roadside", pt)


## A drop on an adventure can snap a lever or knock something loose.
func _drop_faults() -> void:
	if not trip.on_trip() or riding_id == 0:
		return
	for kind in Roadside.drop_faults(randf(), randf()):
		if Shed.check(Shed.me(), {"a": "roadside_fault", "kind": kind}) == "":
			Shed.request({"a": "roadside_fault", "kind": kind})


## The ridden bike's faults onto it (how it rides), and the rider told of a new one: what it is,
## how it shows and what to do.
func _sync_faults() -> void:
	if bike == null or riding_id == 0 or not Shed.bikes.has(riding_id):
		return
	bike.faults = Roadside.faults_of(riding_id).duplicate()
	bike.pushing = bool(Shed.bikes[riding_id].get("push", false))
	if bike.pushing and bike.engine_on:
		bike.stop_engine()
	var now := {}
	for f in Roadside.active(riding_id):
		now[str(f["kind"])] = f
	for kind in now:
		if not _fault_seen.has(kind) and kind not in ["puncture", "pressure"] and trip.on_trip():
			hud.flash("%s %s" % [Roadside.symptom(now[kind]), Controls.hint(Roadside.hint(now[kind]))], 7.0, true)
			if kind == "chain_snap":
				Sfx.play_at("clunk", bike.global_position, 2.0)
				Sfx.play_at("scrap", bike.global_position, -2.0)
			elif kind == "fuse":
				Sfx.play_at("switch", bike.global_position, 0.0)
	_fault_seen = now
	var lights := []
	if now.has("oil"):
		lights.append("OIL")
	if str(bike.faults.get("fuse", "")) == "lights":
		lights.append("LIGHTS OUT")
	hud.warn_lights = lights


## What the faults sound like on the move: a loose part rattling, a slack chain slapping.
func _roadside_sounds(delta: float) -> void:
	_rattle_timer -= delta
	if _rattle_timer > 0.0 or absf(bike.speed) < 3.0:
		return
	var f := bike.faults
	var slack := _fault_seen.has("chain_slack")
	if str(f.get("rattle", "")) != "" or slack:
		var v := clampf(absf(bike.speed) / 25.0, 0.0, 1.0)
		if slack and (randf() < 0.5 or str(f.get("rattle", "")) == ""):
			Sfx.play_at("clunk", bike.global_transform * Vector3(0.0, 0.3, 0.5), lerpf(-14.0, -4.0, v))
		else:
			Sfx.play_at("clink", bike.global_transform * Vector3(0.0, 0.6, 0.0), lerpf(-16.0, -6.0, v))
		_rattle_timer = randf_range(0.12, 0.45) / maxf(v, 0.3)


## On the tow strap: the towing bike's back is where the strap pulls to, and the bars follow it
## round (whatever the towed rider adds of their own). Near the next stop and slowed down, the
## strap comes off.
func _tow_step(delta: float) -> void:
	var by := int(Shed.bikes[riding_id].get("tow", 0)) if Shed.bikes.has(riding_id) else 0
	var tower: Node3D = null
	if by != 0 and remotes.has(by) and is_instance_valid(remotes[by]) and remotes[by].bike != null:
		tower = remotes[by].bike
	if tower == null:
		bike.tow_anchor = Vector3.INF
		return
	bike.tow_anchor = tower.global_transform * Vector3(0.0, 0.0, 1.0)
	bike.tow_speed = float(tower.call("current_speed")) if tower.has_method("current_speed") else 0.0
	if absf(Input.get_axis("lean_left", "lean_right")) < 0.1 and absf(Controls.stick().x) < 0.1:
		var to: Vector3 = bike.global_transform.affine_inverse() * bike.tow_anchor
		bike.lean_input = clampf(atan2(to.x, -to.z) * 1.5, -0.6, 0.6)
	_tow_check -= delta
	if _tow_check <= 0.0:
		_tow_check = 1.0
		var s := trip.world.distance_of(bike.global_position, "own")
		var stop := Roadside.next_stop(trip.world.route, s - 200.0)
		if not stop.is_empty() and absf(float(stop["s"]) - s) < Roadside.STOP_REACH and absf(bike.speed) < 3.0:
			Shed.request({"a": "roadside_untow"})
			hud.flash("At the stop: the tow strap's off.", 3.0)


## The second work button while riding on an adventure: ask the nearest mate on a bike for a
## tow (or let the strap go).
func _tow_button() -> void:
	if Shed.check(Shed.me(), {"a": "roadside_untow"}) == "":
		Shed.request({"a": "roadside_untow"})
		return
	# Only a broken-down (or dry) bike that's stopped asks for a tow, so a stray press while riding
	# along doesn't strap you to whoever's nearby.
	var riding := Shed.riding(Shed.me())
	if not Roadside.needs_tow(riding, bike.fuel_litres <= 0.0):
		return
	if absf(bike.speed) > Roadside.TOW_STOPPED:
		hud.flash("Stop first, then ask a mate for a tow.", 2.0, true)
		return
	var best := 0
	var best_d := Roadside.TOW_REACH
	for peer in remotes:
		var rp = remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			var d: float = rp.bike.global_position.distance_to(bike.global_position)
			if d < best_d:
				best_d = d
				best = int(peer)
	if best == 0:
		hud.flash("Nobody on a bike close enough to tow you (within %d m)." % int(Roadside.TOW_REACH), 2.5, true)
		return
	Shed.request({"a": "roadside_tow", "by": best, "dry": bike.fuel_litres <= 0.0})


## Keeps the ridden bike's punctures in step with the shed's (one given from the Debug tab, say),
## and tells the rider once when a tyre has gone flat.
func _sync_tyre_air() -> void:
	var riding := Shed.riding(Shed.me())
	if bike.heat == null or not Shed.bikes.has(riding):
		return
	for i in 2:
		var side := "front" if i == 0 else "rear"
		var tyre := Shed.item_on(riding, side + "_tyre")
		if tyre != 0 and Puncture.punctured(Shed.items[tyre]):
			bike.heat.leak[i] = Puncture.rate(Shed.items[tyre])
		if bike.heat.flat(i) > 0.3 and not _flat_told[i]:
			_flat_told[i] = true
			hud.flash("The %s tyre's gone flat: it'll wallow and slide. %s" % [side, "Stop and plug it at the roadside from the toolbox, and pump it up."
				if trip.on_trip() else "Get it back to the shed to plug it, and go easy."], 5.0, true)


## The ride logger's lap counter: which stretch of the test route (The Loop) the bike is on, if
## it's on it, and a lap counted when it's been along all of them.
func _track_lap() -> void:
	if world == null or world.roads == null or trip.on_trip():
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
	var gear := ("N" if bike.gear == Bike.NEUTRAL else "G%d" % bike.gear) if b.dash_features.has("gear") else ""
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


## [0, x, y, z, yaw, pitch, crouched] on foot, [1, bike id, bike state...] riding, the truck's
## snapshot driving it (RecoveryView.net_state), or [3] in its passenger seat.
func _net_state() -> PackedFloat32Array:
	if recovery and recovery.driving:
		return recovery.net_state()
	if recovery and recovery.riding_along:
		return PackedFloat32Array([3.0])   # in the truck's passenger seat (drawn sat there: RecoveryView)
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
		remotes[id].push_state(trip.untag_state(state))
