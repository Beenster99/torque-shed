extends RefCounted
## Simon's v0.18.0 riding controls: the new pad layout (Y on and off, LB the clutch, RB a look over
## your shoulder, LB and RB together the engine, R3 a nod, L3 a ping, the D-pad lights, horn and
## view), the tow on T with no pad button, holding the clutch in to blip the revs in any gear, and
## the nod and wave that the crew see. Run from tests/run_tests.gd: its _test_controls_* functions
## hand over to these.

var t: Node   # the test runner: check(), ride(), _done()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## A pad button pushed or let go through Input, as a real one is (so it's held for the riding
## code, which reads Input).
func _pad(button: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button as JoyButton
	ev.pressed = down
	ev.pressure = 1.0 if down else 0.0
	Input.parse_input_event(ev)


func _codes(action: String, pad: bool) -> Array:
	return Settings.events_of(action, pad).map(func(e): return Settings.code_of(e))


## The pad layout Simon asked for, the keys for the new actions, no clashes, the Key bindings tab
## showing it all, and no pad button left for the tow.
func test_layout() -> void:
	Settings.reset_bindings()
	check(Settings.clashes().is_empty(), "the new layout doesn't clash %s" % str(Settings.clashes().slice(0, 3)))
	var want := {"interact": JOY_BUTTON_Y, "shift_down": JOY_BUTTON_X, "shift_up": JOY_BUTTON_A, "rear_brake": JOY_BUTTON_B,
		"nod": JOY_BUTTON_RIGHT_STICK, "horn": JOY_BUTTON_LEFT_STICK, "clutch": JOY_BUTTON_LEFT_SHOULDER,
		"look_back": JOY_BUTTON_RIGHT_SHOULDER, "headlight": JOY_BUTTON_DPAD_UP, "indicate_left": JOY_BUTTON_DPAD_LEFT,
		"indicate_right": JOY_BUTTON_DPAD_RIGHT, "camera": JOY_BUTTON_DPAD_DOWN}
	var wrong := []
	for a in want:
		if _codes(a, true) != ["joy:%d" % want[a]]:
			wrong.append("%s %s" % [a, Settings.binding_text(a, true)])
	check(wrong.is_empty(), "Y on/off, X down, A up, B rear brake, R3 nod, L3 horn, LB clutch, RB look back, D-pad up lights, left and right indicators, down view %s" % str(wrong))
	check(_codes("ignition", true).is_empty() and Controls.key("ignition", true) == "LB + RB" and Controls.key("ignition", false) == "I",
		"the engine is LB and RB together on a pad, I on the keys (%s)" % Controls.key("ignition", true))
	check(_codes("tow", true).is_empty() and Settings.binding_text("tow", false) == "T" and Controls.key("tow", true) == "T",
		"the tow is T, with no pad button (a pad player's hint still says T)")
	# Riding, no pad button but X shifts down any more (it used to ask for a tow as well).
	var on_x := []
	for a in Settings.ACTIONS:
		if Settings._contexts(a[0]).has("ride") and _codes(a[0], true).has("joy:%d" % JOY_BUTTON_X):
			on_x.append(a[0])
	check(on_x == ["shift_down"], "riding, X is only shift down %s" % str(on_x))
	for a in ["look_back", "nod", "clutch", "toggle_auto_shift"]:
		check(Settings.binding_text(a, false) != "", "%s has a key (%s)" % [Settings.action_name(a), Settings.binding_text(a, false)])
	# The weight goes on the left stick now LB and RB are the clutch and the look back.
	check(_codes("body_back", true).is_empty() and Controls.key("body_back", true) == "Left stick", "weight back is the left stick on a pad")
	var tab := KeybindTab.new()
	t.add_child(tab)
	await t.get_tree().process_frame
	var row: Dictionary = tab._rows["ignition"]
	check((row["pad"] as Button).text == "LB + RB" and (tab._rows["tow"]["kbm"] as Button).text == "T" and (tab._rows["tow"]["pad"] as Button).text == "-"
		and (tab._rows["nod"]["pad"] as Button).text == "R3" and (tab._rows["look_back"]["pad"] as Button).text == "RB",
		"the Key bindings tab shows LB + RB for the engine, T and no pad button for the tow, R3 nod and RB look back")
	check(tab.warning() == "", "and no clash warning (%s)" % tab.warning())
	tab.queue_free()
	# Every riding hint names its keys by action: the tow's too.
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(main_src.contains("{tow}: ask a mate for a tow") and main_src.contains("{tow}: let it go") and not main_src.contains("{work2}: ask a mate"),
		"the tow hints say {tow}")
	check(Controls.hint("{tow}: ask a mate for a tow", false) == "T: ask a mate for a tow", "and read T")
	await t.get_tree().process_frame


## Holding the clutch in: the throttle revs the engine freely in gear, standing or on the move,
## with nothing driving the back wheel; let out, the revs come back to the wheel's smoothly and
## the drive takes up without a jolt.
func test_clutch() -> void:
	# Stood still in first, engine running: clutch in and the throttle wide open.
	var st := {"max_v": 0.0, "max_rpm": 0.0, "drive": 0.0, "load": 0.0}
	var r: Dictionary = await t.ride({}, 2.5, func(bike: Bike, at: float):
		bike.auto_shift = false
		if at < 0.05:
			bike.gear = 1
		bike.clutch_in = true
		bike.front_brake = 0.0
		bike.throttle = 1.0 if at > 0.5 else 0.0
		if at > 1.0:
			st["max_v"] = maxf(st["max_v"], absf(bike.speed))
			st["max_rpm"] = maxf(st["max_rpm"], bike.rpm)
			st["drive"] = maxf(st["drive"], absf(float(bike.wheels[1]["drive_torque"])))
			st["load"] = bike.sound_load())
	var b: Bike = r["bike"]
	check(st["max_v"] < 0.3 and st["max_rpm"] > b.build.idle_rpm + 3000.0 and st["drive"] < 0.001 and b.gear == 1,
		"clutch in, in first: the throttle revs it to %.0f rpm and the bike stays put (%.2f m/s, drive %.1f N m)" % [st["max_rpm"], st["max_v"], st["drive"]])
	check(st["load"] > 0.9, "and the engine note carries the throttle (%.2f)" % st["load"])
	await t._done(r)
	# On the move in third: clutch in, blip it, then let it out.
	var mv := {"v_in": -1.0, "v_out": -1.0, "gap": 0.0, "rpm_jump": 0.0, "max_acc": 0.0, "last_rpm": 0.0, "last_v": 0.0,
		"after": -1.0, "rpm_free": 0.0}
	r = await t.ride({}, 9.0, func(bike: Bike, at: float):
		var dt := 1.0 / Engine.physics_ticks_per_second
		if at < 5.0:
			bike.throttle = 0.7
			return
		bike.auto_shift = false
		if at < 6.5:
			# Clutch in at speed, throttle blipped wide open.
			bike.clutch_in = true
			bike.throttle = 1.0 if fmod(at, 0.5) < 0.25 else 0.0
			if mv["v_in"] < 0.0:
				mv["v_in"] = bike.speed
			mv["rpm_free"] = maxf(mv["rpm_free"], bike.rpm - _wheel_rpm(bike))
			mv["drive"] = absf(float(bike.wheels[1]["drive_torque"]))
			mv["v_out"] = bike.speed
		else:
			bike.clutch_in = false
			bike.throttle = 0.3
			if at > 6.5 + dt * 2.0:
				mv["rpm_jump"] = maxf(mv["rpm_jump"], absf(bike.rpm - float(mv["last_rpm"])))
				mv["max_acc"] = maxf(mv["max_acc"], absf(bike.speed - float(mv["last_v"])) / dt)
			if at > 7.0 and mv["after"] < 0.0:
				mv["after"] = absf(bike.rpm - _wheel_rpm(bike)) / maxf(_wheel_rpm(bike), 1.0)
		mv["last_rpm"] = bike.rpm
		mv["last_v"] = bike.speed)
	b = r["bike"]
	check(mv["v_in"] > 8.0 and mv["v_out"] <= mv["v_in"] + 0.1 and mv["rpm_free"] > 1500.0,
		"clutch in at %.0f km/h: the blips rev it %.0f rpm past the wheel's and it doesn't drive on (%.1f -> %.1f m/s)" % [
			mv["v_in"] * 3.6, mv["rpm_free"], mv["v_in"], mv["v_out"]])
	check(not r["crashed"] and mv["max_acc"] < 12.0 and mv["rpm_jump"] < 400.0,
		"let out, it takes up smoothly: at most %.1f m/s2 and %.0f rpm a tick" % [mv["max_acc"], mv["rpm_jump"]])
	check(mv["after"] >= 0.0 and mv["after"] < 0.03 and b.clutch == 0.0, "half a second later the revs are the wheel's again (%.1f%% off)" % (mv["after"] * 100.0))
	await t._done(r)


static func _wheel_rpm(bike: Bike) -> float:
	return float(bike.wheels[1]["omega"]) * bike.build.overall_ratio(maxi(bike.gear, 1)) * 60.0 / TAU


## The rider in a session, sat on Old Faithful: {main, bike}.
func _riding() -> Dictionary:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await _ticks(3)
	Shed.request({"a": "mount", "bike": t._bike_named("Old Faithful")})
	await _ticks(5)
	return {"main": main, "bike": main.bike}


func _leave(main: Node) -> void:
	for a in ["nod", "look_back", "clutch"]:
		Input.action_release(a)
	main._leave()
	main.queue_free()
	await t.get_tree().physics_frame
	Controls.active_device = -1
	Controls.set_using_pad(false)


## A tap of the nod button nods the rider's head, held it raises the left hand off the bar in a
## wave; each goes to the crew, a crew mate's rider does it on their bike (baked or not), and a
## biker in the traffic nearby nods back.
func test_nod_wave() -> void:
	var rig: Dictionary = await _riding()
	var main: Node = rig["main"]
	var bike: Bike = rig["bike"]
	var model: BikeModel = bike.model
	check(model._rider_head != null and model._arm_left != null and model._rider_head.get_child_count() > 0
		and model._arm_left.get_child_count() >= 3, "the rider's head and left arm are on pivots of their own")
	var sent := []
	var on_emote := func(_peer: int, d: Dictionary): sent.append(str(d.get("e", "")))
	Shed.emoted.connect(on_emote)
	# A biker in the traffic just ahead.
	var other := BikeModel.new()
	other.rider_color = Color(0.2, 0.4, 0.9)
	other.baked = true
	t.add_child(other)
	other.build_from(BikeBuild.new({}), Color.BLUE)
	var slot := 0
	var traffic: RoadTraffic = main.traffic
	traffic.process_mode = Node.PROCESS_MODE_DISABLED   # held as it is, with the one biker put in it
	var was: Dictionary = traffic._views[slot]
	traffic._views[slot] = {"model": other, "pos": bike.global_position + Vector3(0.0, 0.0, -12.0), "seed": 1}
	Input.action_press("nod")
	await _ticks(4)
	Input.action_release("nod")
	await _ticks(36)
	var dip := absf(model._rider_head.basis.get_euler().x)
	check(model.gesture_now() == "nod" and dip > 0.15 and model.wave_amount() < 0.05,
		"a tap nods the head (%.2f rad), hands on the bars" % dip)
	check(sent == ["nod"], "and it goes round the crew (%s)" % str(sent))
	await _ticks(int(Engine.physics_ticks_per_second * 0.6))
	check(other.gesture_now() == "nod", "the biker passing nods back")
	await _ticks(Engine.physics_ticks_per_second)
	check(model.gesture_now() == "" and model._rider_head.basis.is_equal_approx(Basis()), "then the head's back up")
	Input.action_press("nod")
	await _ticks(int(Engine.physics_ticks_per_second * (main.WAVE_HOLD + 0.4)))
	check(model.gesture_now() == "ride_wave" and model.wave_amount() > 0.5 and sent == ["nod", "ride_wave"],
		"held, the left hand comes up off the bar in a wave (%.2f) and the crew are told (%s)" % [model.wave_amount(), str(sent)])
	Input.action_release("nod")
	await _ticks(Engine.physics_ticks_per_second * 2)
	check(model.wave_amount() < 0.05 and sent.size() == 2, "and goes back on the bar, with no nod on letting go (%s)" % str(sent))
	Shed.emoted.disconnect(on_emote)
	traffic._views[slot] = was
	traffic.process_mode = Node.PROCESS_MODE_INHERIT
	other.queue_free()
	# A crew mate's rider does it on their bike, on this screen.
	var rp := RemotePlayer.new()
	main.world.add_child(rp)
	rp.setup(77, "Mate", Color.GREEN)
	rp._start_riding(t._bike_named("Rusty Ranger"))
	await t.get_tree().process_frame
	rp.play_emote("nod")
	await _ticks(10)
	check(rp.bike != null and rp.bike.model.gesture_now() == "nod" and absf(rp.bike.model._rider_head.basis.get_euler().x) > 0.1,
		"a crew mate's nod plays on their (baked) bike's rider")
	rp.play_emote("ride_wave")
	await _ticks(int(Engine.physics_ticks_per_second * 0.6))
	check(rp.bike.model.wave_amount() > 0.5, "and their wave (%.2f)" % rp.bike.model.wave_amount())
	rp.play_emote("dance")
	check(rp.emote == "", "a dance on foot isn't done on the bike")
	rp.queue_free()
	await _leave(main)


## Holding the reverse view cuts straight to a view behind, like a reversing camera, for as long as it is held:
## from your eyes in first person, round in front of the bike looking back in the chase view, with no swing round and no
## turn of the rider's head. LB and RB together start the engine without looking back; LB alone holds the clutch in.
func test_look_back_and_chord() -> void:
	var rig: Dictionary = await _riding()
	var main: Node = rig["main"]
	var bike: Bike = rig["bike"]
	var cam: ChaseCamera = main.camera
	cam.set_mode(ChaseCamera.Mode.CHASE)
	await _ticks(30)
	var fwd := -bike.global_basis.z
	check((cam.global_position - bike.global_position).dot(fwd) < 0.0, "the chase view starts behind the bike")
	Input.action_press("look_back")
	await _ticks(2)
	check(cam.looking_back() == 1.0 and (cam.global_position - bike.global_position).dot(fwd) > 1.0 and (-cam.global_basis.z).dot(fwd) < -0.5,
		"held, the view cuts at once to in front of the bike looking back past the rider (%.2f)" % cam.looking_back())
	await _ticks(Engine.physics_ticks_per_second)
	check(absf(bike.model._rider_head.basis.get_euler().y) < 0.05, "and the rider's head isn't turned: it's a camera, not a look over the shoulder")
	cam.set_mode(ChaseCamera.Mode.HELMET)
	await _ticks(2)
	check((-cam.global_basis.z).dot(fwd) < -0.85, "in first person it's straight back down the road (%.2f)" % (-cam.global_basis.z).dot(fwd))
	Input.action_release("look_back")
	await _ticks(Engine.physics_ticks_per_second)
	check(cam.looking_back() < 0.02 and (-cam.global_basis.z).dot(fwd) > 0.5, "let go, you look ahead again")
	cam.set_mode(ChaseCamera.Mode.CHASE)
	# Only while it's held: a tap doesn't leave it on.
	Input.action_press("look_back")
	await _ticks(6)
	Input.action_release("look_back")
	await _ticks(Engine.physics_ticks_per_second)
	check(not cam.look_back and cam.looking_back() < 0.02, "a tap doesn't leave the reverse view on")
	# The horizon where it is looking ahead: the same way down at the road, in either view.
	for m in [ChaseCamera.Mode.CHASE, ChaseCamera.Mode.HELMET]:
		cam.set_mode(m)
		await _ticks(Engine.physics_ticks_per_second)
		var ahead := (-cam.global_basis.z).y
		Input.action_press("look_back")
		await _ticks(Engine.physics_ticks_per_second)
		var behind := (-cam.global_basis.z).y
		Input.action_release("look_back")
		await _ticks(Engine.physics_ticks_per_second)
		check(absf(behind - ahead) < 0.04, "%s: looking back, the view's as level as looking ahead (%.3f, %.3f)" % [["chase", "helmet"][0 if m == ChaseCamera.Mode.CHASE else 1], ahead, behind])
	# Leant over in a corner, the rider holds their head nearly level: the first person view keeps the horizon flat.
	cam.set_mode(ChaseCamera.Mode.HELMET)
	var upright := bike.global_transform
	bike.global_basis = Basis(-upright.basis.z.normalized(), 0.6) * upright.basis
	cam._helmet()
	var ahead := -cam.global_basis.z
	var roll := absf(cam.global_basis.x.signed_angle_to(ahead.cross(Vector3.UP).normalized(), ahead))
	bike.global_transform = upright
	check(roll < 0.6 * (1.0 - ChaseCamera.HEAD_LEVEL) + 0.05, "leant 34 degrees, the view is tilted only %.0f degrees" % rad_to_deg(roll))
	# A crash is watched from the roadside, on the rider thrown off, till they're back on: then the view they had.
	for m in [ChaseCamera.Mode.HELMET, ChaseCamera.Mode.CHASE]:
		cam.set_mode(m)
		await _ticks(3)
		bike.linear_velocity = -bike.global_basis.z * 20.0
		bike.crash()
		await _ticks(30)
		var thrown := bike.ragdoll_body()
		check(cam.mode == ChaseCamera.Mode.RIDE_BY and cam.watching_crash() and thrown != null
			and (-cam.global_basis.z).dot((thrown.global_position - cam.global_position).normalized()) > 0.9,
			"crashed in the %s view: the roadside view, on the rider tumbling" % ["chase", "helmet"][1 if m == ChaseCamera.Mode.HELMET else 0])
		await _ticks(Engine.physics_ticks_per_second * 2)
		check(cam.mode == ChaseCamera.Mode.RIDE_BY, "and it stays on them while they're down")
		bike.respawn()
		await _ticks(3)
		check(cam.mode == m and not cam.watching_crash(), "back on the bike, the view they had before")
	cam.set_mode(ChaseCamera.Mode.CHASE)
	# The engine on LB and RB together.
	bike.stop_engine()
	await _ticks(3)
	check(not bike.engine_on and not bike.is_starting(), "engine off")
	_pad(JOY_BUTTON_LEFT_SHOULDER, true)
	await _ticks(6)
	check(bike.clutch_in and not bike.is_starting() and not bike.engine_on, "LB alone pulls the clutch in, and doesn't start it")
	_pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _ticks(6)
	check(bike.is_starting() or bike.engine_on, "LB and RB together start the engine")
	check(not cam.look_back and Controls.chord_held(), "and don't look back while they're held")
	_pad(JOY_BUTTON_LEFT_SHOULDER, false)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _ticks(Engine.physics_ticks_per_second * 2)
	check(bike.engine_on and not bike.clutch_in and not Controls.chord_held(), "it fires, and the clutch is out again")
	check(not cam.look_back, "letting go of the chord doesn't leave the reverse view on")
	_pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _ticks(10)
	check(cam.look_back and bike.engine_on, "RB on its own looks back, the engine left running")
	_pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _ticks(3)
	await _leave(main)
