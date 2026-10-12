extends Node
## Boots the map behind the title screen, then runs a riding session: the local bike, camera,
## HUD, garage and everyone else's bikes.

const MAP_SEED := 1234
const PAINTS := [Color(0.78, 0.09, 0.08), Color(0.1, 0.35, 0.8), Color(0.95, 0.6, 0.05), Color(0.1, 0.6, 0.3),
	Color(0.55, 0.15, 0.7), Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), Color(0.0, 0.6, 0.7)]

var world: World
var bike: Bike
var camera: ChaseCamera
var hud: HUD
var garage: GarageUI
var menu: MainMenu
var audio: EngineAudio
var remotes := {}     # peer id -> RemoteBike
var in_session := false
var _send_timer := 0.0


func _ready() -> void:
	world = World.new()
	add_child(world)
	world.generate(MAP_SEED)
	camera = ChaseCamera.new()
	world.add_child(camera)
	camera.mode = ChaseCamera.Mode.ORBIT
	_title_camera()
	camera.current = true

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = HUD.new()
	hud.visible = false
	ui.add_child(hud)
	garage = GarageUI.new()
	garage.visible = false
	ui.add_child(garage)
	garage.build_applied.connect(_on_build_applied)
	garage.closed.connect(_close_garage)
	menu = MainMenu.new()
	ui.add_child(menu)
	menu.ride_solo.connect(func(): _start_session())
	menu.host_game.connect(_host)
	menu.join_game.connect(_join)
	menu.resume.connect(func(): menu.hide())
	menu.leave_session.connect(_leave)

	Net.player_joined.connect(_on_player_joined)
	Net.player_updated.connect(_on_player_updated)
	Net.player_left.connect(_on_player_left)
	Net.state_received.connect(_on_state)
	Net.connected.connect(func(): _start_session())
	Net.connection_failed.connect(func(reason): menu.show_title(reason))
	Net.disconnected.connect(func(): _end_session(); menu.show_title("The host ended the session."))
	menu.show_title()


func _title_camera() -> void:
	camera.mode = ChaseCamera.Mode.ORBIT
	camera.orbit_center = Vector3(0.0, 0.0, 112.0)
	camera.orbit_radius = 26.0
	camera.orbit_height = 7.0


func _paint() -> Color:
	return PAINTS[Net.local_slot() % PAINTS.size()]


func _local_info() -> Dictionary:
	return {"name": Settings.player_name, "build": Settings.current_build, "color": _paint()}


func _host() -> void:
	var err := Net.host(_local_info())
	if err != OK:
		menu.set_status("Could not host on port %d (error %d)." % [Net.PORT, err])
		return
	_start_session()
	hud.flash("Hosting. Friends join with %s" % ", ".join(Net.local_addresses()), 6.0)


func _join(ip: String) -> void:
	if ip == "":
		menu.set_status("Enter the host's IP address.")
		return
	var err := Net.join(ip, _local_info())
	menu.set_status("Connecting to %s..." % ip if err == OK else "Could not start connecting (error %d)." % err)


func _start_session() -> void:
	if in_session:
		return
	in_session = true
	menu.hide()
	Net.update_local_info(_local_info())
	_spawn_bike(Settings.current_build, world.spawn_point(Net.local_slot()))
	hud.visible = true
	camera.mode = ChaseCamera.Mode.CHASE
	camera.snap()
	for id in Net.players:
		if not remotes.has(id):
			_on_player_joined(id, Net.players[id])
	_refresh_player_list()


func _spawn_bike(build: Dictionary, at: Transform3D) -> void:
	if bike:
		bike.queue_free()
	bike = Bike.new()
	bike.setup(BikeBuild.new(build))
	world.add_child(bike)
	bike.model.build_from(bike.build, _paint())
	bike.place(at.origin, at.basis.get_euler().y)
	bike.crashed.connect(func(): hud.flash("Crashed!", 1.5))
	audio = EngineAudio.new()
	audio.cylinders = bike.build.cylinders
	bike.add_child(audio)
	camera.target = bike
	hud.bike = bike


func _leave() -> void:
	Net.leave()
	_end_session()
	menu.show_title()


func _end_session() -> void:
	in_session = false
	for id in remotes.keys():
		remotes[id].queue_free()
	remotes.clear()
	if bike:
		bike.queue_free()
		bike = null
	hud.visible = false
	garage.hide()
	camera.target = null
	_title_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not in_session:
		return
	if event.is_action_pressed("menu"):
		if garage.visible:
			_close_garage()
		elif menu.visible:
			menu.hide()
		else:
			menu.show_pause()
	elif menu.visible or garage.visible:
		return
	elif event.is_action_pressed("respawn"):
		bike.respawn()
	elif event.is_action_pressed("garage"):
		_open_garage()
	elif event.is_action_pressed("camera"):
		camera.cycle_mode()
	elif event.is_action_pressed("shift_up"):
		bike.shift_up()
	elif event.is_action_pressed("shift_down"):
		bike.shift_down()
	elif event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		hud.flash("Auto-shift %s" % ("on" if Settings.auto_shift else "off"), 1.5)
	elif event.is_action_pressed("help"):
		hud.toggle_help()


func _physics_process(delta: float) -> void:
	if not in_session or bike == null:
		return
	var riding := not menu.visible and not garage.visible
	if riding:
		bike.throttle = Input.get_action_strength("throttle")
		bike.front_brake = Input.get_action_strength("front_brake")
		bike.rear_brake = Input.get_action_strength("rear_brake")
		bike.lean_input = Input.get_axis("lean_left", "lean_right")
		bike.body_shift = Input.get_axis("body_back", "body_forward")
	else:
		bike.throttle = 0.0
		bike.lean_input = 0.0
		bike.body_shift = 0.0
		bike.front_brake = 1.0
		bike.rear_brake = 1.0
	bike.auto_shift = Settings.auto_shift
	bike.assist = Settings.assist
	audio.rpm = bike.rpm
	audio.throttle = bike.throttle
	_send_timer += delta
	if _send_timer >= 1.0 / 30.0:
		_send_timer = 0.0
		Net.send_state(bike.get_net_state())


func _open_garage() -> void:
	if absf(bike.speed) > 2.0 or bike.is_crashed:
		hud.flash("Stop the bike to open the garage", 2.0)
		return
	garage.open(Settings.current_build)
	hud.visible = false
	camera.mode = ChaseCamera.Mode.ORBIT
	camera.orbit_center = bike.global_position
	camera.orbit_radius = 3.6
	camera.orbit_height = 1.3


func _close_garage() -> void:
	garage.hide()
	hud.visible = true
	camera.mode = ChaseCamera.Mode.CHASE
	camera.snap()


func _on_build_applied(build: Dictionary) -> void:
	Settings.current_build = PartsDB.sanitize_build(build)
	Settings.save_settings()
	var fwd := -bike.global_transform.basis.z
	var at := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), bike.global_position - Vector3.UP * 0.25)
	_spawn_bike(Settings.current_build, at)
	Net.update_local_info(_local_info())
	_close_garage()
	hud.flash("New build ready. %d hp, %d kg" % [roundi(bike.build.hp()), roundi(bike.build.bike_mass)], 3.0)


func _on_player_joined(id: int, info: Dictionary) -> void:
	if not in_session:
		return
	var rb := RemoteBike.new()
	world.add_child(rb)
	rb.setup(info)
	remotes[id] = rb
	hud.flash("%s joined" % info["name"], 2.5)
	_refresh_player_list()


func _on_player_updated(id: int, info: Dictionary) -> void:
	if remotes.has(id):
		remotes[id].setup(info)
	else:
		_on_player_joined(id, info)
	_refresh_player_list()


func _on_player_left(id: int) -> void:
	if remotes.has(id):
		hud.flash("%s left" % remotes[id].player_name, 2.5)
		remotes[id].queue_free()
		remotes.erase(id)
	_refresh_player_list()


func _on_state(id: int, state: PackedFloat32Array) -> void:
	if remotes.has(id):
		remotes[id].push_state(state)


func _refresh_player_list() -> void:
	var names := []
	if Net.is_online():
		names.append("%s (you)" % Settings.player_name)
		for id in Net.players:
			names.append(Net.players[id]["name"])
	hud.set_players(names)
