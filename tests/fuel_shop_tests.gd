extends RefCounted
## The fuel station shops on an adventure and what's by a bike (see FuelShop, FuelShopView):
## buying on the business's account, put down next to the bike on the forecourt whatever it is,
## picking it up to fit and putting things down, strapped on when it's ridden off (the weight of
## it) with what's too big sent on to the shed, a mate doing the same through the host, and
## everything put in the delivery area at home. And the wrench out of the shed with no toolbox. Run from tests/run_tests.gd: its _test_fuel_shop_* functions hand
## over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree(), _bike_named()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Parts in the delivery area (on its floor or racking) and loose about the shed: their ids.
func _loose_parts(part: String) -> Array:
	var out := []
	for id in Shed.items:
		if str(Shed.items[id]["part"]) == part and str(Shed.items[id]["at"]) in ["floor", "spot"]:
			out.append(int(id))
	return out


## Rides `bike` out on an adventure and stands it at the roadside.
func _at_roadside(bike: int) -> void:
	var me := Shed.me()
	Rides.start(20.0, 6)
	Shed.bikes[bike]["rider"] = me
	Shed.crew[me]["riding"] = bike
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(Basis(), Vector3(3.0, 0.0, -6000.0)),
		"roadside": {"x": 100.0, "y": 2.0, "z": -900.0, "yaw": 0.0, "s": 500.0}})


## The rules: buying, the weight limits, the straps, a mate, and home again.
func test_rules() -> void:
	Shed.start_new("Tester", 82)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	Shed.garage_money = 100000
	var mirrors := str(PartsDB.by_kind["mirrors"][0])
	var screen := ""   # (the heaviest panniers that go on the straps)
	for id in PartsDB.by_kind["panniers"]:
		if screen == "" or FuelShop.part_kg(str(id)) > FuelShop.part_kg(screen):
			screen = str(id)
	check(Shed.check(me, {"a": "shop_buy", "part": mirrors, "bike": bike}).contains("out on an adventure"), "no fuel station shops at home")
	_at_roadside(bike)
	check(Roadside.parked(bike), "stood at the roadside on an adventure")
	var mass0: float = Shed.build_of(bike).total_mass
	var money0 := Shed.garage_money
	var cost := Money.buy_price(mirrors, me)
	# Bought: boxed and put down by the bike, paid by the business.
	check(Shed.check(me, {"a": "shop_buy", "part": "no_such_part", "bike": bike}) != "", "only parts in the catalogue")
	check(Shed.check(me, {"a": "shop_buy", "part": mirrors, "bike": bike}) == "", "mirrors can be bought")
	Shed.request({"a": "shop_buy", "part": mirrors, "bike": bike})
	check(FuelShop.cargo_of(bike).size() == 1 and str(FuelShop.cargo_of(bike)[0]["part"]) == mirrors and FuelShop.cargo_of(bike)[0].get("boxed", false),
		"the mirrors, boxed, by the bike")
	check(Shed.garage_money == money0 - cost and Shed.bank.size() > 0, "paid from the business's account (%d)" % cost)
	check(not FuelShop.cargo_of(bike)[0].has("id") and not FuelShop.cargo_of(bike)[0].has("at"), "kept as a part's record, not somewhere in the shed")
	check(Shed.build_of(bike).total_mass > mass0 + 0.1, "the bike's that bit heavier (%.2f kg)" % (Shed.build_of(bike).total_mass - mass0))
	# With no bike on the forecourt it's sent on to the shed.
	var engine := "twin_700"
	check(Shed.check(me, {"a": "shop_buy", "part": engine, "bike": bike}) == "", "but whatever's bought goes by the bike, an engine too")
	var before := _loose_parts(engine).size()
	Shed.request({"a": "shop_buy", "part": engine, "bike": 0})
	var sent := _loose_parts(engine)
	check(sent.size() == before + 1, "bought with no bike on the forecourt: sent to the shed")
	var at_home: Dictionary = Shed.items[sent[-1]] if not sent.is_empty() else {}
	check(at_home.get("boxed", false) and str(at_home.get("at", "")) in ["floor", "spot"], "boxed in the delivery area")
	# Off the straps, out of its box, in your hands.
	check(Shed.check(me, {"a": "cargo_take", "bike": bike, "index": 0, "part": "nothing"}) != "", "the part has to be the one asked for")
	Shed.request({"a": "cargo_take", "bike": bike, "index": 0, "part": mirrors})
	var held := Shed.held_by(me)
	check(held != 0 and str(Shed.items[held]["part"]) == mirrors and not Shed.items[held].get("boxed", false), "the mirrors picked up and out of the box, in your hands")
	check(FuelShop.cargo_of(bike).is_empty(), "nothing by the bike now")
	check(Shed.check(me, {"a": "mount", "bike": bike}).contains("down by the bike"), "can't ride off holding them: put them down by the bike")
	check(Shed.check(me, {"a": "cargo_take", "bike": bike, "index": 0}) != "", "one thing at a time")
	Shed.request({"a": "cargo_strap", "bike": bike})
	check(Shed.held_by(me) == 0 and not Shed.items.has(held) and FuelShop.cargo_of(bike).size() == 1, "put back down by the bike")
	check(Shed.check(me, {"a": "cargo_strap", "bike": bike}).contains("not holding"), "nothing in your hands to put down")
	# Whatever's bought goes by the bike, an engine too; ridden off, it's all left behind, gone
	# (Simon, 6 Nov).
	if screen != "":
		for i in 6:
			Shed.request({"a": "shop_buy", "part": screen, "bike": bike})
		Shed.request({"a": "shop_buy", "part": engine, "bike": bike})
		check(FuelShop.cargo_of(bike).size() == 8, "six panniers and an engine by the bike too (%.1f kg)" % FuelShop.cargo_kg(bike))
		var engines := _loose_parts(engine).size()
		var n_items := Shed.items.size()
		var mass_before: float = Shed.build_of(bike).total_mass
		Shed.request({"a": "mount", "bike": bike})
		check(Shed.riding(me) == bike and FuelShop.cargo_of(bike).is_empty(), "ridden off: nothing's by it any more")
		check(_loose_parts(engine).size() == engines and Shed.items.size() == n_items, "left behind, gone: nothing sent to the shed")
		check(Shed.build_of(bike).total_mass < mass_before - 1.0, "and the bike carries none of it")
		Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(Basis(), Vector3(3.0, 0.0, -6000.0)),
			"roadside": {"x": 100.0, "y": 2.0, "z": -900.0, "yaw": 0.0, "s": 500.0}})
		check(Roadside.parked(bike) and FuelShop.ride_off(bike) == "", "off again, nothing to leave behind")
		Shed.request({"a": "shop_buy", "part": mirrors, "bike": bike})
		Shed.request({"a": "shop_buy", "part": screen, "bike": bike})
	# A mate takes one off through the host.
	var mate := 4242
	Shed.crew[mate] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0}
	var n_cargo := FuelShop.cargo_of(bike).size()
	Shed._apply(mate, {"a": "cargo_take", "bike": bike, "index": 0, "part": mirrors})
	check(Shed.held_by(mate) != 0 and FuelShop.cargo_of(bike).size() == n_cargo - 1, "a mate takes the mirrors off the straps")
	Shed._apply(mate, {"a": "cargo_strap", "bike": bike})
	check(Shed.held_by(mate) == 0 and FuelShop.cargo_of(bike).size() == n_cargo, "and straps them back on")
	# Saved mid-ride and loaded: the adventure's over and it's all in the delivery area.
	var cargo_parts := FuelShop.cargo_of(bike).map(func(r): return str(r["part"]))
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	check((saved["bikes"][bike].get("cargo", []) as Array).size() == n_cargo, "the cargo is saved with the bike")
	var mirrors_before := _loose_parts(mirrors).size()
	Shed.load_state(saved, "Tester")
	check(FuelShop.cargo_of(bike).is_empty(), "loaded: nothing left strapped on")
	check(_loose_parts(mirrors).size() == mirrors_before + 1 and _loose_parts(screen).size() >= cargo_parts.count(screen),
		"and every part of it is in the shed (%d things)" % cargo_parts.size())
	# The end of an adventure does the same.
	_at_roadside(bike)
	Shed.request({"a": "shop_buy", "part": mirrors, "bike": bike})
	check(FuelShop.cargo_of(bike).size() == 1, "bought on the next ride")
	Shed.request({"a": "adventure_end"})
	check(FuelShop.cargo_of(bike).is_empty() and _loose_parts(mirrors).size() == mirrors_before + 2, "home: it's in the delivery area")
	Shed.stop()


## The wrench out of the shed (see ToolboxSpares.BOLT_ON_SLOTS), no toolbox needed: at an
## adventure's roadside one go takes the front mudguard off and puts it down by the bike, which is
## lighter, panniers bought at the shop are fitted from beside the bike and bolted up in one go,
## hands still work as in the shed, the parts a bike can't do without stay a job for the shed,
## and on an ordinary ride the same works wherever the bike's left.
func test_spanner() -> void:
	Shed.start_new("Tester", 82)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	Shed.garage_money = 100000
	check(Shed.item_on(bike, "toolbox") == 0, "Old Faithful has no toolbox")
	var guard := Shed.item_on(bike, "front_mudguard")
	check(guard != 0, "Old Faithful has a front mudguard")
	_at_roadside(bike)
	var mass0: float = Shed.build_of(bike).total_mass
	# The front mudguard off at the roadside, in one go.
	var off := {"a": "spanner_off", "bike": bike, "slot": "front_mudguard"}
	check(Shed.check(me, off) == "", "the wrench takes the front mudguard off, no toolbox (%s)" % Shed.check(me, off))
	Shed.request(off)
	check(Shed.item_on(bike, "front_mudguard") == 0 and Shed.held_by(me) == 0, "the front mudguard off")
	check(FuelShop.cargo_of(bike).size() == 1 and str(FuelShop.cargo_of(bike)[0]["kind"]) == "front_mudguard", "and down by the bike")
	check(Shed.is_complete(bike) and Shed.missing_slots(bike).is_empty(), "still complete: it rides without one")
	check(Shed.check(me, {"a": "mount", "bike": bike}) == "", "and it can be ridden off")
	# Hands work too, as in the shed.
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "tail"}) == "", "the tail unit can be unbolted")
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "headlight"}) == "", "and the headlight")
	# What it can't do without stays on.
	for slot in ["engine", "frame", "front_wheel", "rear_tyre", "tank", "saddle", "fork", "shock", "handlebars", "exhaust", "gearbox"]:
		check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": slot}).contains("job for the shed"), "the %s is a job for the shed" % slot)
		check(Shed.check(me, {"a": "spanner_off", "bike": bike, "slot": slot}).contains("job for the shed"), "the wrench won't take the %s off" % slot)
	# The Rig built fit (BikeRig.part_tier) has its say: a bike can't do without its tank.
	check(ToolboxSpares.rig_says(bike, "tank", "none").ends_with("That's a job for the shed.") and ToolboxSpares.rig_says(bike, "mirrors", "none") == "",
		"the rig's fit call is asked: %s" % ToolboxSpares.rig_says(bike, "tank", "none"))
	# Panniers bought at the shop, fitted from beside the bike and bolted up in one go.
	var panniers := str(PartsDB.by_kind["panniers"][0])
	Shed.request({"a": "shop_buy", "part": panniers, "bike": bike})
	check(FuelShop.cargo_of(bike).size() == 2, "the panniers put down by the bike")
	var on := {"a": "spanner_on", "bike": bike, "index": 1, "part": panniers}
	check(Shed.check(me, on) == "", "they fit at the roadside (%s)" % Shed.check(me, on))
	check(Shed.check(me, {"a": "spanner_on", "bike": bike, "index": 1, "part": "nothing"}) != "", "the part has to be the one asked for")
	Shed.request(on)
	check(PartsDB.kind_of(str(Shed.items.get(Shed.item_on(bike, "panniers"), {}).get("part", ""))) == "panniers" and Shed.is_bolted(bike, "panniers"),
		"fitted and bolted up")
	check(FuelShop.cargo_of(bike).size() == 1, "only the mudguard left by the bike")
	check(Shed.build_of(bike).total_mass < mass0 + FuelShop.part_kg(panniers) + 0.5, "weights add up")
	# An engine by the bike won't go on with the wrench.
	Shed.request({"a": "shop_buy", "part": "twin_700", "bike": bike})
	check(Shed.check(me, {"a": "spanner_on", "bike": bike, "index": 1, "part": "twin_700"}) != "", "an engine's a job for the shed")
	check(Shed.check(me, {"a": "mount", "bike": bike}) == "", "ready to ride")
	# Home: the mudguard's in the delivery area, nothing lost.
	var loose := func() -> int:
		var n := 0
		for id in Shed.items:
			if str(Shed.items[id]["kind"]) == "front_mudguard" and str(Shed.items[id]["at"]) in ["floor", "spot"]:
				n += 1
		return n
	var before: int = loose.call()
	Shed.request({"a": "adventure_end"})
	check(int(loose.call()) == before + 1 and FuelShop.cargo_of(bike).is_empty(), "home: the front mudguard's in the delivery area")
	# An ordinary ride: the same wherever it's left.
	Shed.bikes[bike]["xf"] = Transform3D(Basis(), Vector3(0.0, 0.0, 140.0))
	Shed.bikes[bike]["rider"] = 0
	check(not Shed.bike_at_work(bike) and ToolboxSpares.stood_out(bike), "out on the town's road, stood")
	check(Shed.check(me, {"a": "spanner_off", "bike": bike, "slot": "panniers"}) == "", "the wrench takes the panniers off out here too")
	Shed.request({"a": "spanner_off", "bike": bike, "slot": "panniers"})
	check(Shed.item_on(bike, "panniers") == 0 and FuelShop.cargo_of(bike).size() == 1, "off and down by the bike")
	Shed.request({"a": "cargo_take", "bike": bike, "index": 0, "part": panniers})
	check(Shed.held_by(me) != 0, "picked up by hand")
	Shed.request({"a": "cargo_strap", "bike": bike})
	check(Shed.held_by(me) == 0 and FuelShop.cargo_of(bike).size() == 1, "and put back down")
	# Ridden off, the panniers are left behind, gone.
	var n_items := Shed.items.size()
	Shed.request({"a": "mount", "bike": bike})
	check(Shed.riding(me) == bike and FuelShop.cargo_of(bike).is_empty() and Shed.items.size() == n_items, "ridden off, the panniers left behind")
	Shed.stop()


## In the game: ride to a fuel station, get off, walk to the counter, the shop opens as the
## parts computer in its shop mode, buy mirrors (strapped on) and an engine (sent home), take the
## mirrors off the straps at the bike and strap them back on, the bike drawn with its load.
func test_session() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 10)
	Shed.garage_money = 100000
	await t.get_tree().physics_frame
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(20.0, 92)
	await _ticks(10)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null and Shed.riding(me) == faithful, "out on an adventure on Old Faithful")
	check(trip.shop != null, "the trip has its fuel station shops")
	var fuel: Array = trip.world.route.sites_of("fuel")
	check(not fuel.is_empty(), "a fuel station on the route")
	if fuel.is_empty():
		await _end(main)
		return
	var s := float(fuel[0]["s"])
	trip.world.preload_range(maxf(0.0, s - 300.0), s + 300.0)
	var counter: Node3D = null
	var end := Time.get_ticks_msec() + 30000
	while counter == null and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
		for n in t.get_tree().get_nodes_in_group(AdventureStops.COUNTER_GROUP):
			if str(n.get_meta("site_kind", "")) == "fuel" and absf(float(n.get_meta("s", 0.0)) - s) < 200.0:
				counter = n
	check(counter != null, "the fuel station's shop counter is built")
	if counter == null:
		await _end(main)
		return
	# Ride onto the forecourt (put there) and get off.
	var fwd := (counter.global_transform.basis.z).normalized()
	main.bike.global_transform = Transform3D(Basis(), counter.global_position + Vector3(0.0, 0.6, 0.0) + fwd * 6.0)
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(5)
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Roadside.parked(faithful), "off on the forecourt")
	var w: Walker = main.walker
	w.place(Transform3D(Basis(), counter.global_position + Vector3(0.0, 0.05, 0.0) + fwd * 0.8))
	await _ticks(2)
	check(trip.shop.find_near(w.global_position) == counter, "at the counter, the shop's in reach")
	check(trip.shop.forecourt_bike(counter.global_position) == faithful, "and Old Faithful's the bike on the forecourt")
	trip.shop._near_timer = 0.0
	await _ticks(2)
	check(trip.shop._prompt.text.contains("shop"), "the prompt offers the shop: %s" % trip.shop._prompt.text)
	check(trip.shop.open_at(counter) == "", "{interact} opens the shop")
	var pc: PartsComputer = main.computer
	check(pc.visible and not pc.shop.is_empty() and int(pc.shop["bike"]) == faithful, "the parts computer, as the station's shop")
	check(pc._head_title.text.ends_with("SHOP") and not pc._bike_btn.visible and not pc._section_btns["shed"].visible and pc._section_btns["bike"].visible,
		"only the Bike aisle, no project bikes or shed things: %s" % pc._head_title.text)
	var mirrors := str(PartsDB.by_kind["mirrors"][0])
	pc._show_kind("mirrors")
	pc._show_part(mirrors)
	check(pc._order.text.begins_with("Buy it") and pc._order.text.contains("next to Old Faithful"), "Buy: next to the bike (%s)" % pc._order.text)
	pc.order()
	await _ticks(3)
	check(FuelShop.cargo_of(faithful).size() == 1, "bought and put by the bike")
	pc._show_kind("engine")
	pc._show_part("twin_700")
	check(pc._order.text.contains("next to Old Faithful"), "an engine goes by the bike too (%s)" % pc._order.text)
	var engines := Shed.items.values().filter(func(it): return str(it["part"]) == "twin_700").size()
	pc.order()
	await _ticks(3)
	check(FuelShop.cargo_of(faithful).size() == 2, "the engine's by the bike")
	pc._search.text = "mirror"
	pc._refresh_list()
	var shed_hits := 0
	for c in pc._variants.get_children():
		if c is Button and c.get_meta("part", "") != "" and Equipment.get_model(str(c.get_meta("part"))).size() > 0:
			shed_hits += 1
	check(shed_hits == 0, "the shop's search finds bike parts only")
	pc.close_computer()
	check(not pc.visible and pc.shop.is_empty() and pc._bike_btn.visible and pc._head_title.text == "PARTS COMPUTER", "closed, it's the shed's parts computer again")
	# At the bike: the wrench's second button fits the mirrors; hands pick the engine up and put it down.
	w.place(Transform3D(Basis(), Roadside.xf_in(trip.world, Roadside.spot_of(faithful)).origin + Vector3(1.0, 0.05, 0.0)))
	var old_mirrors := Shed.item_on(faithful, "mirrors")
	if old_mirrors != 0:
		w.tool = "wrench"
		w.target = {"kind": "part", "bike": faithful, "slot": "mirrors", "roadside": true}
		w._make_plan()
		check(str(w.plan.get("action", {}).get("a", "")) == "spanner_off" and w.plan["blocked"] == "", "the wrench on the old mirrors: take them off")
		Shed.request(w.plan["action"])
		await _ticks(2)
		check(Shed.item_on(faithful, "mirrors") == 0 and FuelShop.cargo_of(faithful).size() == 3, "off and down by the bike")
	w.tool = "wrench"
	w.cargo_pick = 0
	w.target = {"kind": "part", "bike": faithful, "slot": "tail", "roadside": true}
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "spanner_on" and w.alt_plan["blocked"] == "",
		"the wrench's second button fits the new mirrors from beside the bike (%s)" % str(w.alt_plan.get("blocked", "")))
	var info := "\n".join(w.roadside_lines(faithful, "tail"))
	check(info.contains("By the bike") and info.contains(PartsDB.part_name(mirrors)), "the part info lists what's by the bike")
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	check(str(Shed.items.get(Shed.item_on(faithful, "mirrors"), {}).get("part", "")) == mirrors and Shed.is_bolted(faithful, "mirrors"), "the new mirrors fitted and bolted up")
	w.tool = "hands"
	w.cargo_pick = 0
	w.target = {"kind": "part", "bike": faithful, "slot": "tail", "roadside": true}
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "cargo_take" and w.alt_plan["blocked"] == "", "empty-handed at the bike: the second button picks it up")
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	check(Shed.held_by(me) != 0, "picked up")
	w.target = {"kind": "part", "bike": faithful, "slot": "tail", "roadside": true}
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "cargo_strap" and w.alt_plan.get("blocked", "x") == "",
		"holding it: the second button puts it down by the bike")
	if w.alt_plan.is_empty():
		w.alt_plan = {"action": {"a": "cargo_strap", "bike": faithful}}
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	var by_bike := FuelShop.cargo_of(faithful).size()
	check(Shed.held_by(me) == 0 and by_bike >= 1, "put back down")
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	var drawn := false
	if view != null and view._views.has(faithful):
		drawn = (view._views[faithful]["node"] as Node).find_child("Cargo0", true, false) != null
	check(drawn, "the bike's drawn with what's down by it")
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and FuelShop.cargo_of(faithful).is_empty(), "back on, what was by the bike left behind")
	await _end(main)


func _end(main: Node) -> void:
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
