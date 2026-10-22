extends RefCounted
## Brake lights and indicators (see BikeLamps), run from tests/run_tests.gd (its _test_lamps_*
## functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## A model's lens material for a group ("tail", "ind_l", "ind_r"), or null.
static func _lens(m: BikeModel, group: String) -> StandardMaterial3D:
	for l in m._lamps:
		if l["group"] == group:
			return l["mat"]
	return null


## Whether the stop lamp's red light is shining (it's only made once the brakes first go on).
static func _red(m: BikeModel) -> bool:
	return m._stop_glow != null and m._stop_glow.visible


static func _glowing(m: BikeModel, group: String) -> bool:
	var mat := _lens(m, group)
	return mat != null and mat.emission_enabled and mat.emission_energy_multiplier > 0.0


## Either brake lights the stop lamp bright (and the red lamp behind it), letting go puts it
## back: dark with the headlight off, a dim tail light with it on. No ignition, no stop lamp.
func test_brake_light() -> void:
	var r: Dictionary = await t.ride({}, 0.3, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	var m := bike.model
	bike.beam = 0
	bike.front_brake = 0.0
	bike.rear_brake = 0.0
	await _frames(3)
	check(not m.stop_lit() and not _glowing(m, "tail") and not _red(m), "riding along, lights off and no brakes: the rear light is dark")
	check(m.find_children("*", "Light3D", true, false).is_empty(),
		"and until the brakes first go on the model has no lamp of its own (a parked bike or a part is no light in the shed)")
	bike.front_brake = 0.8
	await _frames(3)
	check(m.stop_lit() and _glowing(m, "tail") and is_equal_approx(_lens(m, "tail").emission_energy_multiplier, BikeModel.STOP_ENERGY)
		and _red(m), "the front brake lights the stop lamp bright, with its red glow")
	check(bike.get_net_state()[25] > 0.5, "and the snapshot says so")
	bike.front_brake = 0.0
	await _frames(3)
	check(not m.stop_lit() and not _red(m), "let go and it goes out")
	bike.rear_brake = 0.5
	await _frames(3)
	check(m.stop_lit(), "the back brake lights it too")
	bike.rear_brake = 0.0
	bike.beam = 1
	await _frames(3)
	check(not m.stop_lit() and _glowing(m, "tail") and is_equal_approx(_lens(m, "tail").emission_energy_multiplier, BikeModel.TAIL_ENERGY),
		"headlight on, brakes off: a dim tail light (%.1f)" % _lens(m, "tail").emission_energy_multiplier)
	bike.rear_brake = 1.0
	await _frames(3)
	check(is_equal_approx(_lens(m, "tail").emission_energy_multiplier, BikeModel.STOP_ENERGY), "and braking it brightens to the stop lamp")
	bike.engine_on = false
	await _frames(3)
	check(not m.stop_lit() and not _glowing(m, "tail") and not _red(m), "with the engine off the brake lights nothing")
	await t._done(r)


## They flash 1.5 times a second, on the side asked for, lit at once; front and back.
func test_flash() -> void:
	var lamps := BikeLamps.new()
	lamps.press(-1)
	check(lamps.side == -1 and lamps.left_lit() and not lamps.right_lit(), "pressing left lights the left side at once")
	var dt := 1.0 / 120.0
	var ons := 0
	var ticks := 0
	var lit_frames := 0
	var right := 0
	var was := lamps.lit()
	for i in 240:   # two seconds
		var heard := lamps.step(dt, 0.0, 0.0)
		if heard > 0:
			ticks += 1
		if lamps.lit() and not was:
			ons += 1
		if lamps.lit():
			lit_frames += 1
		if lamps.right_lit():
			right += 1
		was = lamps.lit()
	check(ons == 2 and ticks == 2 and right == 0, "in two seconds it comes on again twice after the first (1.5 Hz), only on the left: %d, %d ticks" % [ons, ticks])
	check(absf(lit_frames / 240.0 - 0.5) < 0.05, "lit half the time (%.0f%%)" % (lit_frames / 2.4))
	# On a bike: the right side's lenses front and back flash, the left's stay dark.
	var r: Dictionary = await t.ride({}, 0.2, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	var m := bike.model
	check(m.has_indicators(), "the stock bike has its little stock indicators")
	check(bike.indicate(1) == "", "indicating right works")
	await _frames(12)   # 0.1 s
	check(_glowing(m, "ind_r") and not _glowing(m, "ind_l") and m.signals() == [false, false, true], "the right indicators light first")
	await _frames(48)   # 0.5 s
	check(not _glowing(m, "ind_r") and not _glowing(m, "ind_l"), "then go out a third of a second in")
	var pieces := 0
	for slot in ["headlight", "tail"]:
		for mi in m._slot_meshes.get(slot, []):
			var mat := (mi as MeshInstance3D).material_override
			if mat == _lens(m, "ind_r"):
				pieces += 1
	check(pieces >= 2, "the right side has lenses at the front and the back (%d meshes)" % pieces)
	check(int(bike.get_net_state()[26]) == 1, "the snapshot says right")
	await t._done(r)
	# A bike with a set of indicators fitted flashes those.
	r = await t.ride({"indicators": "stalk_amber"}, 0.2, func(_b, _t): pass)
	bike = r["bike"]
	check(bike.indicate(-1) == "" and bike.model._indicator_slots == ["indicators"], "fitted indicators are the ones that flash")
	await _frames(6)
	check(_glowing(bike.model, "ind_l") and not _glowing(bike.model, "ind_r"), "left lit, right dark")
	await t._done(r)


## The same side again cancels; the other side switches over.
func test_cancel() -> void:
	var lamps := BikeLamps.new()
	lamps.press(1)
	lamps.press(1)
	check(lamps.side == 0 and not lamps.lit(), "pressing right twice cancels it")
	lamps.press(1)
	lamps.step(0.2, 0.0, 0.0)
	lamps.press(-1)
	check(lamps.side == -1 and lamps.left_lit(), "pressing left while indicating right switches to left, lit straight away")
	var r: Dictionary = await t.ride({}, 0.2, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	bike.indicate(-1)
	bike.indicate(-1)
	await _frames(3)
	check(bike.lamps.side == 0 and m_dark(bike.model), "on the bike too: twice and they're off")
	bike.indicate(1)
	bike.engine_on = false
	await _frames(3)
	check(bike.lamps.side == 0 and m_dark(bike.model), "the engine going off puts them off")
	check(bike.indicate(1) != "", "and with it off they won't come on (%s)" % bike.indicate(1))
	await t._done(r)
	r = await t.ride({"frame": "race_carbon_white", "indicators": "none"}, 0.1, func(_b, _t): pass)
	bike = r["bike"]
	check(not bike.model.has_indicators() and bike.indicate(1) == "No indicators on this bike",
		"a race bike without indicators fitted has none to work (%s)" % bike.indicate(1))
	await t._done(r)


static func m_dark(m: BikeModel) -> bool:
	return not _glowing(m, "ind_l") and not _glowing(m, "ind_r")


## They cancel themselves once the bike has leant that way and come back upright, or (slowly
## round a junction) turned that way; leaning the other way, or not yet back upright, doesn't.
func test_self_cancel() -> void:
	var dt := 1.0 / 120.0
	var lamps := BikeLamps.new()
	lamps.press(1)
	for i in 120:
		lamps.step(dt, 0.0, 0.0)
	check(lamps.side == 1, "riding straight it keeps flashing")
	for i in 60:
		lamps.step(dt, -0.4, -0.5)
	for i in 30:
		lamps.step(dt, 0.0, 0.0)
	check(lamps.side == 1, "a lean the other way (a swerve) doesn't cancel it")
	for i in 120:
		lamps.step(dt, 0.35, 0.6)
	check(lamps.side == 1, "while leant over into the turn it's still on")
	for i in 60:
		lamps.step(dt, lerpf(0.35, 0.0, i / 59.0), lerpf(0.6, 0.0, i / 59.0))
	check(lamps.side == 0, "upright again after the turn: it has cancelled itself")
	# Slowly round a junction: hardly any lean, but the bike turns left through 90 degrees.
	lamps.press(-1)
	for i in 240:
		lamps.step(dt, -0.03, -0.7)
	check(lamps.side == -1, "turning slowly left it stays on through the turn")
	for i in 30:
		lamps.step(dt, 0.0, 0.0)
	check(lamps.side == 0, "and cancels once it's straight again")
	# On the bike itself: lean it right into a turn, then straighten up.
	var r: Dictionary = await t.ride({}, 4.0, func(b, _t): b.throttle = 0.5)
	var bike: Bike = r["bike"]
	bike.indicate(1)
	var steps := 0
	while steps < 600 and bike.lean_angle < BikeLamps.TURN_LEAN + 0.05:
		bike.throttle = 0.3
		bike.lean_input = 1.0
		await _frames(1)
		steps += 1
	check(bike.lamps.side == 1 and bike.lamps._turning, "riding, leant into the right turn (%.0f deg): still indicating" % rad_to_deg(bike.lean_angle))
	steps = 0
	while steps < 900 and bike.lamps.side != 0:
		bike.lean_input = clampf(-bike.lean_angle * 4.0, -1.0, 1.0)
		await _frames(1)
		steps += 1
	check(bike.lamps.side == 0, "back upright the indicator cancels itself (%.1f s)" % (steps / 120.0))
	await t._done(r)


## The new actions are in the bindings list with their keys and pad buttons, nothing clashes,
## and the horn and the truck's handbrake have moved aside for them.
func test_bindings() -> void:
	Settings.reset_bindings()
	var codes := func(a: String, pad: bool) -> Array:
		return Settings.events_of(a, pad).map(func(e): return Settings.code_of(e))
	check(codes.call("indicate_left", true) == ["joy:%d" % JOY_BUTTON_DPAD_LEFT] and codes.call("indicate_right", true) == ["joy:%d" % JOY_BUTTON_DPAD_RIGHT],
		"the D-pad's left and right indicate (%s / %s)" % [Settings.binding_text("indicate_left", true), Settings.binding_text("indicate_right", true)])
	check(Settings.binding_text("indicate_left", false) == "Comma" or Settings.binding_text("indicate_left", false) == ",",
		"comma indicates left (%s)" % Settings.binding_text("indicate_left", false))
	check(Settings.binding_text("indicate_right", false) == "Period" or Settings.binding_text("indicate_right", false) == ".",
		"full stop indicates right (%s)" % Settings.binding_text("indicate_right", false))
	var listed := Settings.ACTIONS.map(func(a): return a[0])
	check(listed.has("indicate_left") and listed.has("indicate_right") and Settings._contexts("indicate_left") == ["ride"],
		"both are in the Key bindings list, for riding")
	check(codes.call("horn", true) == ["joy:%d" % JOY_BUTTON_LEFT_STICK], "the horn has moved to the left stick's press (%s)" % Settings.binding_text("horn", true))
	check(Settings.clashes().is_empty(), "nothing clashes %s" % str(Settings.clashes().slice(0, 3)))


## A crew member's stop lamp and indicators reach your copy of their bike from their snapshots,
## and flash there in time.
func test_remote() -> void:
	var r: Dictionary = await t.ride({}, 0.2, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	bike.front_brake = 1.0
	bike.indicate(-1)
	await _frames(2)
	var state := bike.get_net_state()
	check(state[25] > 0.5 and int(state[26]) == -1, "the snapshot carries the stop lamp and the left indicators")
	var rb := RemoteBike.new()
	t.add_child(rb)
	rb.setup("Crew", BikeBuild.new({}), Color.RED)
	rb.push_state(state)
	await _frames(3)
	check(rb.model.stop_lit() and _red(rb.model), "their stop lamp lights on your screen")
	check(rb.lamps.side == -1 and _glowing(rb.model, "ind_l") and not _glowing(rb.model, "ind_r"), "their left indicators flash")
	var off := 0
	for i in 60:
		await _frames(1)
		if not _glowing(rb.model, "ind_l"):
			off += 1
	check(off > 10 and off < 50, "on and off (%d of 60 frames dark)" % off)
	bike.front_brake = 0.0
	bike.indicate(-1)
	await _frames(2)
	rb.push_state(bike.get_net_state())
	var since := Time.get_ticks_msec()   # snapshots are timed on the clock
	while Time.get_ticks_msec() - since < 250:
		await _frames(1)
	check(not rb.model.stop_lit() and rb.lamps.side == 0 and m_dark(rb.model), "they let go and cancel: dark again")
	var old := state.slice(0, 25)
	rb.push_state(old)
	since = Time.get_ticks_msec()
	while Time.get_ticks_msec() - since < 250:
		await _frames(1)
	check(not rb.model.stop_lit(), "an older game's shorter snapshot shows no signals")
	rb.queue_free()
	await t._done(r)
