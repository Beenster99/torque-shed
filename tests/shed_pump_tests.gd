extends RefCounted
## The shed's petrol pump on the front wall (ShedPump, ShedPumpView), run from tests/run_tests.gd
## (its _test_shed_pump_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A bike's petrol, main tank and any auxiliary one together.
static func _litres(bike: int) -> float:
	var n := 0.0
	for slot in ["tank", "aux_tank"]:
		var id := Shed.item_on(bike, slot)
		if id != 0:
			n += float(Shed.items[id].get("fluid", {}).get("litres", 0.0))
	return n


## Wheels a bike to `at` (side on to the pump, facing along the wall) and lets go of it there.
static func _wheel_to(bike: int, at: Vector3, peer := 0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), at)
	if peer == 0:
		Shed.request({"a": "grab_bike", "bike": bike})
		Shed.request({"a": "move_bike", "bike": bike, "xf": xf})
		Shed.request({"a": "release_bike", "bike": bike, "xf": xf})
	else:
		Shed._apply(peer, {"a": "grab_bike", "bike": bike})
		Shed._apply(peer, {"a": "move_bike", "bike": bike, "xf": xf})
		Shed._apply(peer, {"a": "release_bike", "bike": bike, "xf": xf})


## Stands a bike at `at` as if it had been wheeled there (with the nozzle in hand, you can't).
static func _stand(bike: int, at: Vector3) -> void:
	Shed.bikes[bike]["xf"] = Transform3D(Basis(Vector3.UP, PI * 0.5), at)


## Where a bike stands to be filled: in front of the pump, a stride out from the wall.
static func _by_pump() -> Vector3:
	return Vector3(ShedPump.X, 0.0, ShedPump.WALL_Z + 1.3)


## Runs the host's pump for `seconds` (or until it stops pouring).
static func _pour_for(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		if ShedPump.pouring() == 0:
			return
		ShedPump.process(1.0 / 60.0)


## The rules, on the host: lift the nozzle, pour into a bike by the pump at the town's price
## charged to the business when you let go, the nozzle cutting off when it's full, the hose's
## reach, the account running dry, hanging it back up, and a mate's requests checked.
func test_rules() -> void:
	Shed.start_new("Tester", 19)
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	var tank := Shed.item_on(faithful, "tank")
	Shed.items[tank]["fluid"] = {"type": "unleaded_95", "litres": 2.0, "age": 0.4}
	check(ShedPump.holder() == 0 and ShedPump.pouring() == 0 and Shed.pump["litres"] == 0.0, "a new shed's pump has its nozzle hung up")
	check(is_equal_approx(ShedPump.price(), Shed.PUMP_PRICE) and is_equal_approx(Shed.PUMP_PRICE, 1.6),
		"petrol at the shed's pump is the town's price, %dp a litre" % roundi(ShedPump.price() * 100.0))
	_wheel_to(faithful, _by_pump())
	check(ShedPump.reaches(faithful), "wheeled up beside the pump, the hose reaches its filler (%.2f m)" % ShedPump.filler_point(faithful).distance_to(ShedPump.HOSE_ROOT))
	check(Shed.check(me, {"a": "pump_pour", "on": true, "bike": faithful}).contains("Lift the nozzle"), "no pouring before the nozzle's off the pump")
	Shed.request({"a": "pump_nozzle", "to": "held"})
	check(ShedPump.holder() == me, "lifting the nozzle off the pump: it's in your hand")
	check(Shed.check(me, {"a": "grab_bike", "bike": faithful}).contains("nozzle") and Shed.check(me, {"a": "dyno_hose", "to": "held"}).contains("nozzle"),
		"with the nozzle in your hand, it's all you can hold")
	# Pouring: the litres go in at the pump's rate, the account pays when you let go.
	var money := Shed.garage_money
	Shed.request({"a": "pump_pour", "on": true, "bike": faithful})
	check(ShedPump.pouring() == faithful, "squeezing the trigger on the bike pours")
	_pour_for(2.0)
	var put := float(Shed.pump["litres"])
	check(absf(put - ShedPump.FILL_RATE * 2.0) < 0.05 and absf(_litres(faithful) - 2.0 - put) < 0.01,
		"the petrol goes into the tank at %.1f L a second (%.2f L in two seconds)" % [ShedPump.FILL_RATE, put])
	check(is_equal_approx(float(Shed.pump["cost"]), put * 1.6), "the display shows the cost as it goes (£%.2f)" % float(Shed.pump["cost"]))
	Shed.request({"a": "pump_pour", "on": false})
	var first := ceili(put * Shed.PUMP_PRICE - 0.0001)
	check(ShedPump.pouring() == 0 and Shed.garage_money == money - first,
		"letting go of the trigger charges the business %s for %.2f L" % [TvChannels.money_text(first), put])
	var ledger: Array = Shed.bank["ledger"]
	check(str(ledger[-1]["why"]).begins_with("Petrol") and int(ledger[-1]["amt"]) == -first, "it's in the books as petrol (%s)" % str(ledger[-1]))
	var fluid: Dictionary = Shed.items[tank]["fluid"]
	check(str(fluid["type"]) == "unleaded_95" and float(fluid["age"]) < 0.4, "fresh unleaded freshens what was in the tank")
	# Brimming it: the nozzle cuts off by itself.
	var said := []
	var hear := func(text: String, _ok: bool): said.append(text)
	Shed.feedback.connect(hear)
	Shed.request({"a": "pump_pour", "on": true, "bike": faithful})
	_pour_for(60.0)
	Shed.feedback.disconnect(hear)
	var total := float(Shed.pump["litres"])
	check(ShedPump.pouring() == 0 and Shed.fuel_space(faithful) < 0.01, "it cuts off when the tank's full (%.2f L in all)" % total)
	check(said.any(func(s): return str(s).contains("cut off")), "and says so: %s" % str(said))
	check(Shed.garage_money == money - ceili(total * Shed.PUMP_PRICE - 0.0001),
		"the whole sale, %.2f L, cost the business %s" % [total, TvChannels.money_text(money - Shed.garage_money)])
	check(Shed.check(me, {"a": "pump_pour", "on": true, "bike": faithful}).contains("full"), "a full tank takes no more")
	# The hose only reaches so far.
	Shed.items[tank]["fluid"]["litres"] = 1.0
	Shed.request({"a": "pump_nozzle", "to": "pump"})
	_wheel_to(faithful, _by_pump() + Vector3(0.0, 0.0, ShedPump.HOSE + 1.5))
	Shed.request({"a": "pump_nozzle", "to": "held"})
	check(Shed.pump["litres"] == 0.0, "lifting the nozzle again starts a new sale on the display")
	check(Shed.check(me, {"a": "pump_pour", "on": true, "bike": faithful}) == ShedPump.NO_REACH, "a bike out of the hose's reach can't be filled")
	check(ShedPump.overstretched(ShedPump.HOSE_ROOT + Vector3(0.0, 0.0, ShedPump.HOSE + ShedPump.ARM + 0.2))
		and not ShedPump.overstretched(ShedPump.HOSE_ROOT + Vector3(0.0, 0.0, ShedPump.HOSE)), "walked too far with it, the hose is pulled taut")
	_stand(faithful, _by_pump())
	Shed.request({"a": "pump_pour", "on": true, "bike": faithful})
	_pour_for(0.5)
	var going := ShedPump.pouring() == faithful
	_stand(faithful, _by_pump() + Vector3(0.0, 0.0, 6.0))
	_pour_for(0.1)
	check(going and ShedPump.pouring() == 0, "and the bike taken out of the hose's reach, the pump stops")
	_stand(faithful, _by_pump())
	# The account running dry: it pours what the business can pay for, and no more.
	Shed.items[tank]["fluid"]["litres"] = 1.0
	var paid_before := int(Shed.pump["charged"])
	Shed.garage_money = 3
	Shed.request({"a": "pump_pour", "on": true, "bike": faithful})
	_pour_for(10.0)
	var sale := float(Shed.pump["litres"])
	check(ShedPump.pouring() == 0 and Shed.garage_money == 0 and Shed.fuel_space(faithful) > 0.5,
		"with %s in the account the pump stops when it's spent (%.2f L this sale)" % [TvChannels.money_text(3), sale])
	check(int(Shed.pump["charged"]) - paid_before == 3 and sale * Shed.PUMP_PRICE <= float(int(Shed.pump["charged"])) + 0.001,
		"never more petrol than the business paid for, and no overdraft")
	check(Shed.check(me, {"a": "pump_pour", "on": true, "bike": faithful}).contains("can't afford"), "with nothing in the account, no petrol")
	Shed.garage_money = money
	# Hung back up.
	Shed.request({"a": "pump_nozzle", "to": "pump"})
	check(ShedPump.holder() == 0 and ShedPump.pouring() == 0 and Shed.check(me, {"a": "grab_bike", "bike": faithful}) == "",
		"hung back on the pump, your hands are free")
	# A mate's requests come to the host, who checks them as their own.
	var mate := 4242
	Shed.crew[mate] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0}
	Shed._apply(mate, {"a": "pump_pour", "on": true, "bike": faithful})
	check(ShedPump.pouring() == 0, "a mate can't pour without the nozzle in their hand")
	Shed.request({"a": "pump_nozzle", "to": "held"})
	Shed._apply(mate, {"a": "pump_nozzle", "to": "held"})
	check(ShedPump.holder() == me and Shed.check(mate, {"a": "pump_nozzle", "to": "held"}).contains("Tester"), "nor take it while you've got it")
	Shed._apply(mate, {"a": "pump_nozzle", "to": "pump"})
	check(ShedPump.holder() == me, "nor hang it up out of your hand")
	Shed.request({"a": "pump_nozzle", "to": "pump"})
	Shed._apply(mate, {"a": "pump_nozzle", "to": "held"})
	check(ShedPump.holder() == mate, "with it hung up, they lift it")
	_wheel_to(faithful, _by_pump() + Vector3(0.0, 0.0, ShedPump.HOSE + 1.5))
	Shed._apply(mate, {"a": "pump_pour", "on": true, "bike": faithful})
	check(ShedPump.pouring() == 0, "the host won't let them pour into a bike the hose can't reach")
	_wheel_to(faithful, _by_pump())
	var before := Shed.garage_money
	Shed._apply(mate, {"a": "pump_pour", "on": true, "bike": faithful})
	_pour_for(1.0)
	check(ShedPump.pouring() == faithful and float(Shed.pump["litres"]) > 1.0, "a bike in reach, the host pours for them")
	# They go home with it in their hand: back on the pump, and what went in paid for.
	Shed.crew.erase(mate)
	Shed._tidy_dyno()
	check(ShedPump.holder() == 0 and ShedPump.pouring() == 0 and Shed.garage_money < before, "a mate leaving with the nozzle: it's back on the pump, and the petrol paid for")
	# Saved and loaded: the nozzle's on the pump.
	Shed.request({"a": "pump_nozzle", "to": "held"})
	var snap: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(snap, "Tester")
	check(ShedPump.holder() == 0 and ShedPump.pouring() == 0, "a save opened again has the nozzle on the pump")
	snap.erase("pump")
	Shed.load_state(snap, "Tester")
	check(ShedPump.holder() == 0 and Shed.pump.has("litres"), "and a save from before the pump has one")
	Shed.stop()


## In the shed: the pump on the outside of the front wall by the roller door, lifting the
## nozzle and seeing it in your hand on its hose, pouring into a bike with the display ticking,
## the hose's reach, a mate seeing the nozzle in their hand, and hanging it back up.
func test_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	var ws: Workshop = main.workshop
	var view: ShedPumpView = ws.pump_view
	check(view != null and view.is_inside_tree(), "the shed has a petrol pump")
	var door_edge := Workshop.CENTER.x - Workshop.DOOR_HALF
	check(ShedPump.X < door_edge - 0.5 and ShedPump.X > Workshop.CENTER.x - Workshop.HALF.x + 0.5
		and absf(ShedPump.WALL_Z - (Workshop.CENTER.z + Workshop.HALF.y + 0.3)) < 0.01,
		"it's on the outside of the front wall, beside the roller door (x %.1f, the door from %.1f)" % [ShedPump.X, door_edge])
	var faithful: int = t._bike_named("Old Faithful")
	var tank := Shed.item_on(faithful, "tank")
	Shed.items[tank]["fluid"] = {"type": "unleaded_95", "litres": 1.5, "age": 0.0}
	_wheel_to(faithful, _by_pump())
	Shed.changed.emit()
	for i in 5:
		await t.get_tree().process_frame
	var model := ws.bike_model(faithful)
	check(model.filler != Vector3.ZERO and ShedPump.filler_point(faithful).distance_to(model.global_transform * model.filler) < 0.01,
		"the nozzle goes in the bike's own filler cap")
	var nozzle := view.nozzle
	check(nozzle.global_position.distance_to(ShedPump.HOLSTER) < 0.4, "the nozzle hangs in its holster on the pump")
	# Lift it off.
	w.place(Transform3D(Basis(), Vector3(ShedPump.X + 0.6, 0.0, ShedPump.WALL_Z + 1.4)))
	await t._aim_point(w, view.get_node("PumpTarget").global_position)
	check(w.target.get("kind", "") == "shed_pump" and str(w.plan.get("verb", "")).contains("lift the nozzle"),
		"looking at the pump: hold the work button to lift the nozzle (%s)" % str(w.plan.get("verb", "")))
	check(Controls.hint(w.info).contains("%dp a litre" % roundi(ShedPump.price() * 100.0)), "and the price is up: %s" % Controls.hint(w.info).replace("\n", " / "))
	await t._hold_act(main)
	for i in 3:
		await t.get_tree().process_frame
	check(ShedPump.holder() == Shed.me(), "the work button lifts the nozzle")
	var cam := w.camera.global_transform
	check(nozzle.global_position.distance_to(cam * ShedPumpView.IN_HAND) < 0.05, "it's in your hand")
	var hose: MeshInstance3D = view.get_node("Hose")
	var aabb := hose.get_aabb()
	check(aabb.grow(0.05).has_point(ShedPump.HOSE_ROOT) and aabb.grow(0.05).has_point(nozzle.global_transform * ShedPumpView.TAIL),
		"its hose runs from the pump to the back of the nozzle")
	check(hose.mesh.get_surface_count() == 1 and hose.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the hose is one cheap mesh")
	# Pour into the bike.
	var money := Shed.garage_money
	await t._aim_at(main, faithful, "tank", Vector3(0.0, 0.0, -1.0))
	check(w.plan.get("pour", false) and w.plan["blocked"] == "", "holding the nozzle on the bike: hold the work button to fill it (%s)" % str(w.plan.get("verb", w.plan)))
	Input.action_press("act")
	for i in 120:
		await t.get_tree().physics_frame
	var poured := float(Shed.pump["litres"])
	await t.get_tree().process_frame
	check(ShedPump.pouring() == faithful and poured > 1.0, "holding it, the petrol runs (%.2f L)" % poured)
	check(nozzle.global_position.distance_to(ShedPump.filler_point(faithful)) < 0.35 and view.get_node("Petrol").visible,
		"the nozzle's in the filler, the petrol running in")
	var ticking := view.display.text
	Input.action_release("act")
	for i in 3:
		await t.get_tree().physics_frame
	await t.get_tree().process_frame
	check(ShedPump.pouring() == 0 and Shed.garage_money < money, "letting go stops it, and the business pays (%s)" % TvChannels.money_text(money - Shed.garage_money))
	var litres := float(Shed.pump["litres"])
	check(ticking != view.display.text and view.display.text.contains("%.2f L" % litres) and view.display.text.contains("%.2f" % (litres * ShedPump.price())),
		"the pump's display ticks up the pounds and litres as it goes (%s, then %s)" % [ticking.replace("\n", " / "), view.display.text.replace("\n", " / ")])
	# A mate sees the nozzle in their hand.
	Shed.request({"a": "pump_nozzle", "to": "pump"})
	var rp := RemotePlayer.new()
	t.add_child(rp)
	rp.setup(4242, "Mate", Color.RED)
	rp.global_position = Vector3(ShedPump.X - 0.8, 0.0, ShedPump.WALL_Z + 1.5)
	Shed.crew[4242] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0}
	Shed._apply(4242, {"a": "pump_nozzle", "to": "held"})
	rp._process(0.0)
	for i in 3:
		await t.get_tree().process_frame
	check(nozzle.global_position.distance_to(rp.hand_transform().origin) < 0.05, "a mate holding the nozzle has it in their hand (%s, hand %s)" % [nozzle.global_position, rp.hand_transform().origin])
	Shed._apply(4242, {"a": "pump_nozzle", "to": "pump"})
	Shed.crew.erase(4242)
	rp.queue_free()
	# Walked off too far with it, it goes back on the pump.
	Shed.request({"a": "pump_nozzle", "to": "held"})
	w.place(Transform3D(Basis(), ShedPump.HOSE_ROOT * Vector3(1, 0, 1) + Vector3(0.0, 0.0, ShedPump.HOSE + ShedPump.ARM + 1.0)))
	for i in 4:
		await t.get_tree().process_frame
	check(ShedPump.holder() == 0, "carried beyond the hose's reach, the nozzle's pulled back to the pump")
	await t.get_tree().process_frame
	check(nozzle.global_position.distance_to(ShedPump.HOLSTER) < 0.4, "and hangs in its holster again")
	# Lift it and hang it back up by hand.
	w.place(Transform3D(Basis(), Vector3(ShedPump.X + 0.6, 0.0, ShedPump.WALL_Z + 1.4)))
	await t._aim_point(w, view.get_node("PumpTarget").global_position)
	await t._hold_act(main)
	check(ShedPump.holder() == Shed.me(), "lifted again")
	await t._aim_point(w, view.get_node("PumpTarget").global_position)
	check(str(w.plan.get("verb", "")).contains("hang the nozzle"), "at the pump with it: hang it back up (%s)" % str(w.plan.get("verb", "")))
	await t._hold_act(main)
	check(ShedPump.holder() == 0, "and it's back on the pump")
	main._leave()
	main.queue_free()
	await t.get_tree().physics_frame
