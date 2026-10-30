extends RefCounted
## The ECU line-up from Simon's v0.39.0 list (no stock ECU or ABS controller; a Performance 2 remap
## and ECU Safety with lean-angle traction control), and the rider aids set on the bike as it's
## ridden. Run from tests/run_tests.gd (its _test_ecu_safety_* functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The catalogue: the old stock ECU and ABS controller gone, the two new ones in with their figures,
## and every reference bike and contract naming a real ECU.
func test_catalogue() -> void:
	var ecus: Array = PartsDB.by_kind["ecu"]
	check(not ecus.has("stock_ecu") and not ecus.has("abs_ecu") and ecus.has("remap2_ecu") and ecus.has("ecu_safety"),
		"no stock ECU or ABS controller; a Performance 2 remap and ECU Safety %s" % [ecus])
	check(PartsDB.is_optional("ecu") and PartsDB.DEFAULT_BUILD["ecu"] == "none", "the ECU is optional: no ECU is the stock state")
	var p2 := PartsDB.get_part("remap2_ecu")
	var p1 := PartsDB.get_part("remap_ecu")
	check(p2["name"] == "Performance 2 remap ECU" and is_equal_approx(float(p2["power"]), 1.10)
		and int(p2["rev_add"]) > int(p1["rev_add"]) and BikeBuild.new({"ecu": "remap2_ecu"}).ecu_features.is_empty(),
		"the Performance 2 remap: 10% more power, more revs than the first remap, no aids")
	# Against the first remap (same map range, 6% up), everything else the same.
	var remap := BikeBuild.new({"ecu": "remap_ecu"})
	var remap2 := BikeBuild.new({"ecu": "remap2_ecu"})
	var gain := remap2.torque_mult / remap.torque_mult * 1.06
	check(absf(gain - 1.10) < 0.005 and remap2.hp() > remap.hp() and remap2.stock_redline > remap.stock_redline,
		"it makes 10%% more power than stock maps (x%.3f), more than the first remap (%.0f vs %.0f hp)" % [gain, remap2.hp(), remap.hp()])
	var safety := BikeBuild.new({"ecu": "ecu_safety"})
	check(PartsDB.part_name("ecu_safety") == "ECU Safety" and safety.rider_aids() == ["abs", "traction", "lean_traction", "anti_wheelie"],
		"ECU Safety: ABS, traction control, lean-angle traction control and anti-wheelie %s" % [safety.rider_aids()])
	check(safety.tune_block("aid_lean_traction") == "" and safety.tune_block("aid_abs") == "" and safety.tune_block("aid_stability") != ""
		and BikeBuild.new({"ecu": "sport_ecu"}).tune_block("aid_lean_traction") != "",
		"its aids can be set, the ones it hasn't can't")
	check(PartsDB.ECU_AID_NAMES.has("lean_traction") and PartsDB.spec_line("ecu_safety").contains("lean-angle traction control"),
		"lean-angle traction control is named in its spec: %s" % PartsDB.spec_line("ecu_safety"))
	var bad := []
	for style in Contracts.STYLE_ENGINE:
		var ecu := str(Contracts.STYLE_ENGINE[style].get("ecu", "none"))
		if ecu != "none" and PartsDB.get_part(ecu).is_empty():
			bad.append(style)
	check(bad.is_empty() and str(Contracts.STYLE_ENGINE["tourer"]["ecu"]) == "ecu_safety",
		"the reference bikes that had the ABS controller have ECU Safety %s" % [bad])
	# On the dyno desk too, ABS reads on or off.
	check(TuningComputer.value_text("aid_abs", 1.0, safety) == "On" and TuningComputer.value_text("aid_abs", 0.0, safety) == "Off"
		and TuningComputer.value_text("aid_lean_traction", 3.0, safety).contains("factory"), "the desk reads ABS as on or off, the others by level")


## Lean-angle traction control: its slip allowance tightens as the bike leans and at a firmer
## level, and out on dirt it holds a spinning back tyre that plain traction control (off) doesn't.
func test_lean_traction() -> void:
	var b := BikeBuild.new({"ecu": "ecu_safety"})
	var upright := b.lean_slip_allowance(0.0)
	var leaned := b.lean_slip_allowance(deg_to_rad(45.0))
	check(leaned < upright * 0.6 and is_equal_approx(b.lean_slip_allowance(-deg_to_rad(45.0)), leaned),
		"it allows less spin leaned over (%.3f at 45 deg) than upright (%.3f), either way" % [leaned, upright])
	var firm := BikeBuild.new({"ecu": "ecu_safety"}, {}, {"aid_lean_traction": 5.0})
	var gentle := BikeBuild.new({"ecu": "ecu_safety"}, {}, {"aid_lean_traction": 1.0})
	var off := BikeBuild.new({"ecu": "ecu_safety"}, {}, {"aid_lean_traction": 0.0})
	check(firm.lean_slip_allowance(0.6) < gentle.lean_slip_allowance(0.6) and not off.aid_on("lean_traction")
		and off.lean_slip_allowance(0.6) > 1.0 and BikeBuild.new({"ecu": "sport_ecu"}).lean_slip_allowance(0.6) > 1.0,
		"a firmer level allows less; off, or on an ECU without it, it never cuts in")
	# Riding: full gas on loose dirt, the rider no help and plain traction control off.
	var spins := []
	for level in [0.0, 5.0]:
		var spin := [0.0, 0]
		var r: Dictionary = await t.ride({"engine": "four_1000", "ecu": "ecu_safety"}, 3.0, func(bk, tm):
			bk.build.tune["aid_traction"] = 0.0
			bk.build.tune["aid_lean_traction"] = level
			bk.build.tune["aid_anti_wheelie"] = 5.0
			bk.assist = 0.0
			bk.throttle = 1.0 if tm > 0.3 else 0.0
			if tm > 0.6 and bk.wheels[1]["contact"]:
				spin[0] += (float(bk.wheels[1]["omega"]) * bk.build.rear_radius - bk.speed) / maxf(bk.speed, 1.0)
				spin[1] += 1, "dirt")
		spins.append(spin[0] / maxf(1.0, float(spin[1])))
		await t._done(r)
	check(spins[0] > spins[1] * 1.15, "lean-angle traction control on holds the back tyre that spins up with it off (slip %.2f vs %.2f)" % spins)


## The rider aids menu on the dash: Y steps through the ECU's aids, B steps the picked one's level,
## ABS goes on and off, a ride mode gives way to Custom, and the shed keeps it where the dyno does.
func test_on_bike() -> void:
	var bike := Bike.new()
	bike.build = BikeBuild.new({"ecu": "ecu_safety", "dashboard": "tft_colour"})
	var seen := []
	for i in 5:
		check(bike.next_menu_aid() == "", "the menu opens on an ECU with aids")
		seen.append(bike.aids_menu)
	check(seen == ["abs", "traction", "lean_traction", "anti_wheelie", ""] and not bike.aids_menu_open(),
		"each press picks the next aid the ECU has, then shuts the menu %s" % [seen])
	check(bike.step_aid().is_empty(), "with the menu shut there's nothing to step")
	bike.next_menu_aid()   # ABS
	var changed := bike.step_aid()
	check(changed == {"aid_abs": 0} and not bike.build.abs_on(true) and not bike.build.aid_on("abs"), "ABS switched off on the bike")
	bike.step_aid()
	check(bike.build.abs_on(true) and bike.build.aid_level("abs") == 1, "and on again")
	bike.next_menu_aid()   # traction control
	var levels := []
	for i in 4:
		bike.step_aid()
		levels.append(bike.build.aid_level("traction"))
	check(levels == [4, 5, 0, 1] and bike.build.aid_on("traction") and bike.build.aid_strength("traction") < bike.build.ecu_aid,
		"traction control steps up from the factory level, round to off and up again %s" % [levels])
	# In a ride mode, stepping an aid makes it Custom, the other aids where the mode had them.
	bike.build.ride_mode = "wet"
	bike.next_menu_aid()   # lean-angle traction control
	changed = bike.step_aid()
	check(bike.build.ride_mode == "" and bike.build.aid_level("lean_traction") == 0 and bike.build.aid_level("anti_wheelie") == 5
		and bike.build.aid_level("traction") == 5 and changed.size() == 4,
		"in Wet, stepping lean-angle traction (5 round to off) goes to Custom, keeping Wet's levels for the rest %s" % [changed])
	var plain := Bike.new()
	plain.build = BikeBuild.new({"ecu": "remap2_ecu"})
	check(plain.next_menu_aid() != "" and plain.aids_menu == "", "a remap has no rider aids to set")
	plain.free()
	bike.free()
	check(InputMap.has_action("rider_aids") and Settings.ACTIONS.any(func(a): return a[0] == "rider_aids"),
		"the rider aids key is bound and in the controls list")

	# The shed keeps it, for the rider on their own bike only, where the dyno desk keeps it.
	Shed.start_new("Tester", 7)
	var id: int = Shed.bikes.keys()[0]
	var me := Shed.me()
	var ecu := Shed._new_item("ecu_safety", 0.0, 0.0, 0.0)
	Shed._move(ecu, "bike", id)
	Shed.bikes[id]["slots"]["ecu"] = ecu
	Shed.bikes[id]["bolted"]["ecu"] = true
	check(Shed.check(me, {"a": "aid", "bike": id, "key": "aid_abs", "value": 0}) != "", "only the rider sets aids from the dash")
	Shed.bikes[id]["rider"] = me
	check(Shed.check(me, {"a": "aid", "bike": id, "key": "aid_stability", "value": 1}) != ""
		and Shed.check(me, {"a": "aid", "bike": id, "key": "map", "value": 1}) != "", "not an aid this ECU hasn't, nor any other setting")
	Shed.request({"a": "aid", "bike": id, "key": "aid_abs", "value": 0})
	Shed.request({"a": "aid", "bike": id, "key": "aid_lean_traction", "value": 5})
	var b := Shed.build_of(id)
	check(float(Shed.bikes[id]["tune"].get("aid_abs", -1.0)) == 0.0 and not b.abs_on(true) and b.aid_level("lean_traction") == 5
		and Shed.tune_of(id).get("aid_lean_traction", 0.0) == 5.0, "kept on the bike's tune, the same as the dyno desk's")
	Shed.bikes[id]["rider"] = 0
	Shed.request({"a": "tune", "bike": id, "key": "aid_abs", "reset": true})
	check(Shed.build_of(id).abs_on(true), "and the dyno desk can put it back to the factory setting")
	Shed.stop()


## Saves made with the old ECUs: the stock ECU goes (the slot empty, a loose one gone), the ABS
## controller becomes ECU Safety, in bikes, items, blueprints, shop stock and lists.
func test_saves() -> void:
	check(PartsDB.current_id("stock_ecu") == "none" and PartsDB.current_id("abs_ecu") == "ecu_safety"
		and PartsDB.RETIRED_PARTS["ecu"].size() == 2, "the stock ECU maps to no ECU, the ABS controller to ECU Safety")
	var old := {"items": {5: {"part": "abs_ecu"}}, "bikes": {3: {"original": {"ecu": "stock_ecu"}}, 4: {"original": {"ecu": "abs_ecu"}}},
		"blueprints": {1: {"parts": {"ecu": "stock_ecu"}}, 2: {"parts": ["abs_ecu", "stock_ecu", "race_ecu"]}},
		"stock": {"stock_ecu": 2, "abs_ecu": 1, "race_ecu": 1}}
	var now: Dictionary = PartsDB.migrate(old)
	check(now["items"][5]["part"] == "ecu_safety" and now["bikes"][3]["original"]["ecu"] == "none"
		and now["bikes"][4]["original"]["ecu"] == "ecu_safety" and now["blueprints"][1]["parts"]["ecu"] == "none"
		and now["blueprints"][2]["parts"] == ["ecu_safety", "race_ecu"] and now["stock"] == {"ecu_safety": 1, "race_ecu": 1},
		"bikes, items, blueprints, lists and stock move over: %s %s" % [now["blueprints"][2]["parts"], now["stock"]])
	check(PartsDB.sanitize_build({"ecu": "stock_ecu"})["ecu"] == "none" and PartsDB.sanitize_build({"ecu": "abs_ecu"})["ecu"] == "ecu_safety",
		"a build naming them gets no ECU and ECU Safety")
	# A whole save with a stock ECU fitted to one bike and a loose ABS controller.
	Shed.start_new("Tester", 61)
	var saver := SaveGame.new()
	t.add_child(saver)
	var ids: Array = Shed.bikes.keys()
	var bike: int = ids[0]
	var fitted := Shed._new_item("race_ecu", 0.0, 0.0, 0.0)
	Shed._move(fitted, "bike", bike)
	Shed.bikes[bike]["slots"]["ecu"] = fitted
	Shed.bikes[bike]["bolted"]["ecu"] = true
	var loose := Shed._new_item("race_ecu", 0.0, 0.0, 0.0)
	var data := saver.capture()
	data["shed"]["items"][fitted]["part"] = "stock_ecu"
	data["shed"]["items"][loose]["part"] = "abs_ecu"
	data["shed"]["bikes"][bike]["original"]["ecu"] = "stock_ecu"
	check(saver.restore(data) and not Shed.items.has(fitted) and Shed.item_on(bike, "ecu") == 0 and not Shed.is_bolted(bike, "ecu")
		and Shed.items.has(loose) and Shed.items[loose]["part"] == "ecu_safety"
		and not Shed.items.values().any(func(it): return str(it["part"]) == "none"),
		"the fitted stock ECU is gone, its slot empty; the loose ABS controller is ECU Safety")
	check(Shed.build_of(bike).parts["ecu"] == "none" and str(Shed.bikes[bike]["original"]["ecu"]) == "none", "and the bike runs with no ECU")
	saver.queue_free()
	Shed.stop()


## A key press sent to the game the way a real one comes.
static func _key(main: Node, code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.pressed = down
		main._unhandled_input(ev)


## In the game, riding: Y brings the rider aids menu up on the dash, B then switches ABS off, and
## the shed keeps it on the bike.
func test_dash() -> void:
	Settings.reset_bindings()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	for i in 3:
		await t.get_tree().physics_frame
	var id: int = t._bike_named("Old Faithful")
	var ecu := Shed._new_item("ecu_safety", 0.0, 0.0, 0.0)
	Shed._move(ecu, "bike", id)
	Shed.bikes[id]["slots"]["ecu"] = ecu
	Shed.bikes[id]["bolted"]["ecu"] = true
	Shed.request({"a": "mount", "bike": id})
	for i in 5:
		await t.get_tree().physics_frame
	var bike: Bike = main.bike
	check(bike != null and bike.build.has_aid("lean_traction"), "riding a bike with ECU Safety")
	_key(main, KEY_Y)
	check(bike.aids_menu_open() and bike.aids_menu == "abs", "Y brings the rider aids menu up, on ABS")
	var mode_was: String = bike.build.ride_mode
	_key(main, KEY_B)
	await t.get_tree().process_frame
	check(not bike.build.abs_on(true) and float(Shed.bikes[id].get("tune", {}).get("aid_abs", -1.0)) == 0.0
		and bike.build.ride_mode == mode_was, "B with the menu up switches ABS off, kept on the bike, and leaves the ride mode be")
	_key(main, KEY_Y)
	_key(main, KEY_B)
	check(bike.aids_menu == "traction" and float(Shed.bikes[id]["tune"].get("aid_traction", -1.0)) == 4.0,
		"Y again picks traction control, B steps it to level 4")
	main._leave()
	main.queue_free()
	await t.get_tree().physics_frame
