extends Node
## Boots the map behind the title screen, then runs a session: you on foot in the shed,
## the bike you're riding when you take one out, and everyone else in the session.

const MAP_SEED := 1234
const GET_OFF_SPEED := 2.0

var world: World
var workshop: Workshop
var walker: Walker
var bike: Bike
var riding_id := 0
var camera: ChaseCamera
var hud: HUD
var menu: MainMenu
var audio: EngineAudio
var remotes := {}     # peer id -> RemotePlayer
var in_session := false
var _send_timer := 0.0
var _stats_timer := 0.0
var _ride_km := 0.0
var _ride_top := 0.0


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

	Net.player_joined.connect(_on_player_joined)
	Net.player_updated.connect(_on_player_updated)
	Net.player_left.connect(_on_player_left)
	Net.state_received.connect(_on_state)
	Net.connected.connect(func(): _start_session())
	Net.connection_failed.connect(func(reason): menu.show_title(reason))
	Net.disconnected.connect(func(): _end_session(); menu.show_title("The host closed the shed."))
	Shed.changed.connect(_on_shed_changed)
	Shed.feedback.connect(func(text, ok): hud.flash(text, 2.5 if ok else 2.0, not ok))
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
	if Net.is_online() and not Net.is_host():
		Shed.join_remote()
	else:
		Shed.start_new(Settings.player_name)
	walker = Walker.new()
	world.add_child(walker)
	walker.place(Workshop.walker_spawn(Net.local_slot()))
	walker.mount_requested.connect(_try_mount)
	walker.camera.current = true
	hud.walker = walker
	hud.visible = true
	for id in Net.players:
		if not remotes.has(id):
			_on_player_joined(id, Net.players[id])
	workshop.sync_state()
	_capture_mouse(true)
	hud.flash("Welcome to the shed. Esc for the menu.", 4.0)


func _leave() -> void:
	Net.leave()
	_end_session()
	menu.show_title()


func _end_session() -> void:
	in_session = false
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
	bike.setup(Shed.build_of(bike_id), data["paint"])
	world.add_child(bike)
	var xf: Transform3D = data["xf"]
	bike.place(xf.origin, xf.basis.get_euler().y)
	bike.crashed.connect(func(): hud.flash("Crashed!", 1.5, true))
	audio = EngineAudio.new()
	audio.cylinders = bike.build.cylinders
	audio.loudness = bike.build.exhaust_loudness
	bike.add_child(audio)
	camera.target = bike
	camera.mode = ChaseCamera.Mode.CHASE
	camera.snap()
	camera.current = true
	hud.bike = bike
	_set_walker_active(false)
	_ride_km = 0.0
	_ride_top = 0.0


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
	Shed.request({"a": "dismount", "bike": riding_id, "xf": Transform3D(Basis(Vector3.UP, heading), ground)})
	_stop_riding()


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
		if menu.visible:
			_close_menu()
		else:
			menu.show_pause()
			_capture_mouse(false)
		get_viewport().set_input_as_handled()
		return
	if menu.visible or bike == null:
		return
	if event.is_action_pressed("interact"):
		_get_off()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("respawn"):
		bike.respawn()
	elif event.is_action_pressed("camera"):
		camera.cycle_mode()
	elif event.is_action_pressed("shift_up"):
		bike.shift_up()
	elif event.is_action_pressed("shift_down"):
		bike.shift_down()
	elif event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		hud.flash("Auto-shift %s" % ("on" if Settings.auto_shift else "off"), 1.5)


func _physics_process(delta: float) -> void:
	if not in_session:
		return
	var active := not menu.visible
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
		audio.rpm = bike.rpm
		audio.throttle = bike.throttle
		_ride_km += absf(bike.speed) * delta / 1000.0
		_ride_top = maxf(_ride_top, absf(bike.speed) * 3.6)
		_stats_timer += delta
		if _stats_timer >= 1.0:
			_stats_timer = 0.0
			Shed.request({"a": "ride", "km": _ride_km, "top_kmh": _ride_top, "kmh": absf(bike.speed) * 3.6})
			_ride_km = 0.0
	_send_timer += delta
	if _send_timer >= 1.0 / 30.0:
		_send_timer = 0.0
		Net.send_state(_net_state())


## [0, x, y, z, yaw, pitch] on foot, or [1, bike id, bike state...] riding.
func _net_state() -> PackedFloat32Array:
	if bike:
		var s := PackedFloat32Array([1.0, float(riding_id)])
		s.append_array(bike.get_net_state())
		return s
	if walker:
		var p := walker.global_position
		return PackedFloat32Array([0.0, p.x, p.y, p.z, walker.yaw(), walker.pitch()])
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


func _on_state(id: int, state: PackedFloat32Array) -> void:
	if remotes.has(id):
		remotes[id].push_state(state)
