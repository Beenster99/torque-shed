extends RefCounted
## The fuel station shops on an adventure and what's strapped on a bike (see FuelShop,
## FuelShopView): buying on the business's account, strapped on the bike on the forecourt or
## sent to the shed when it's too big to carry, taking it off the straps to fit and strapping
## things on, the weight of it, a mate doing the same through the host, and everything put in
## the delivery area at home. Run from tests/run_tests.gd: its _test_fuel_shop_* functions hand
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
		if FuelShop.part_kg(str(id)) <= FuelShop.CARRY_ONE_KG and (screen == "" or FuelShop.part_kg(str(id)) > FuelShop.part_kg(screen)):
			screen = str(id)
	check(Shed.check(me, {"a": "shop_buy", "part": mirrors, "bike": bike}).contains("out on an adventure"), "no fuel station shops at home")
	_at_roadside(bike)
	check(Roadside.parked(bike), "stood at the roadside on an adventure")
	var mass0: float = Shed.build_of(bike).total_mass
	var money0 := Shed.garage_money
	var cost := Money.buy_price(mirrors, me)
	# Bought: boxed and strapped on, paid by the business.
	check(Shed.check(me, {"a": "shop_buy", "part": "no_such_part", "bike": bike}) != "", "only parts in the catalogue")
	check(Shed.check(me, {"a": "shop_buy", "part": mirrors, "bike": bike}) == "", "mirrors can be bought")
	Shed.request({"a": "shop_buy", "part": mirrors, "bike": bike})
	check(FuelShop.cargo_of(bike).size() == 1 and str(FuelShop.cargo_of(bike)[0]["part"]) == mirrors and FuelShop.cargo_of(bike)[0].get("boxed", false),
		"the mirrors, boxed, strapped on the bike")
	check(Shed.garage_money == money0 - cost and Shed.bank.size() > 0, "paid from the business's account (%d)" % cost)
	check(not FuelShop.cargo_of(bike)[0].has("id") and not FuelShop.cargo_of(bike)[0].has("at"), "kept as a part's record, not somewhere in the shed")
	check(Shed.build_of(bike).total_mass > mass0 + 0.1, "the bike's that bit heavier (%.2f kg)" % (Shed.build_of(bike).total_mass - mass0))
	# Too big to carry: an engine's sent on to the shed.
	var engine := "twin_700"
	check(FuelShop.carry_reason(bike, engine).contains("too big"), "an engine won't go on the straps")
	check(Shed.check(me, {"a": "shop_buy", "part": engine, "bike": bike}).contains("too big"), "so it can't be strapped on")
	var before := _loose_parts(engine).size()
	Shed.request({"a": "shop_buy", "part": engine, "bike": 0})
	var sent := _loose_parts(engine)
	check(sent.size() == before + 1, "bought with nowhere to strap it: sent to the shed")
	var at_home: Dictionary = Shed.items[sent[-1]] if not sent.is_empty() else {}
	check(at_home.get("boxed", false) and str(at_home.get("at", "")) in ["floor", "spot"], "boxed in the delivery area")
	# Off the straps, out of its box, in your hands.
	check(Shed.check(me, {"a": "cargo_take", "bike": bike, "index": 0, "part": "nothing"}) != "", "the part has to be the one asked for")
	Shed.request({"a": "cargo_take", "bike": bike, "index": 0, "part": mirrors})
	var held := Shed.held_by(me)
	check(held != 0 and str(Shed.items[held]["part"]) == mirrors and not Shed.items[held].get("boxed", false), "the mirrors off the straps and out of the box, in your hands")
	check(FuelShop.cargo_of(bike).is_empty(), "nothing strapped on now")
	check(Shed.check(me, {"a": "mount", "bike": bike}).contains("Strap the"), "can't ride off holding them: strap them on")
	check(Shed.check(me, {"a": "cargo_take", "bike": bike, "index": 0}) != "", "one thing at a time")
	Shed.request({"a": "cargo_strap", "bike": bike})
	check(Shed.held_by(me) == 0 and not Shed.items.has(held) and FuelShop.cargo_of(bike).size() == 1, "strapped back on")
	check(Shed.check(me, {"a": "cargo_strap", "bike": bike}).contains("not holding"), "nothing in your hands to strap on")
	# Loaded up: the straps take so much.
	if screen != "":
		var n := 0
		while Shed.check(me, {"a": "shop_buy", "part": screen, "bike": bike}) == "" and n < 20:
			Shed.request({"a": "shop_buy", "part": screen, "bike": bike})
			n += 1
		check(n > 0 and n < 20 and FuelShop.cargo_kg(bike) <= FuelShop.CARRY_KG, "panniers strapped on till it's loaded up (%d, %.1f kg)" % [n, FuelShop.cargo_kg(bike)])
		check(Shed.check(me, {"a": "shop_buy", "part": screen, "bike": bike}).contains("loaded up"), "then it says it's loaded up")
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
	check(pc._order.text.begins_with("Buy it") and pc._order.text.contains("strapped on Old Faithful"), "Buy: strapped on the bike (%s)" % pc._order.text)
	pc.order()
	await _ticks(3)
	check(FuelShop.cargo_of(faithful).size() == 1, "bought and strapped on")
	pc._show_kind("engine")
	pc._show_part("twin_700")
	check(pc._order.text.contains("sent to the shed"), "an engine's sent to the shed (%s)" % pc._order.text)
	var engines := Shed.items.values().filter(func(it): return str(it["part"]) == "twin_700").size()
	pc.order()
	await _ticks(3)
	check(Shed.items.values().filter(func(it): return str(it["part"]) == "twin_700").size() == engines + 1 and FuelShop.cargo_of(faithful).size() == 1,
		"the engine's at home, not on the bike")
	pc._search.text = "mirror"
	pc._refresh_list()
	var shed_hits := 0
	for c in pc._variants.get_children():
		if c is Button and c.get_meta("part", "") != "" and Equipment.get_model(str(c.get_meta("part"))).size() > 0:
			shed_hits += 1
	check(shed_hits == 0, "the shop's search finds bike parts only")
	pc.close_computer()
	check(not pc.visible and pc.shop.is_empty() and pc._bike_btn.visible and pc._head_title.text == "PARTS COMPUTER", "closed, it's the shed's parts computer again")
	# At the bike: take the mirrors off the straps, then strap them back on.
	w.place(Transform3D(Basis(), Roadside.xf_in(trip.world, Roadside.spot_of(faithful)).origin + Vector3(1.0, 0.05, 0.0)))
	w.tool = "hands"
	w.target = {"kind": "part", "bike": faithful, "slot": "tail", "roadside": true}
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "cargo_take" and w.alt_plan["blocked"] == "", "empty-handed at the bike: the second button takes it off the straps")
	var info := "\n".join(w.roadside_lines(faithful, "tail"))
	check(info.contains("Strapped on") and info.contains(PartsDB.part_name(mirrors)), "the part info lists what's strapped on")
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	check(Shed.held_by(me) != 0 and FuelShop.cargo_of(faithful).is_empty(), "the mirrors in your hands")
	w.target = {"kind": "part", "bike": faithful, "slot": "tail", "roadside": true}
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "cargo_strap" and w.alt_plan.get("blocked", "x") == "",
		"holding them: the second button straps them on")
	if w.alt_plan.is_empty():
		w.alt_plan = {"action": {"a": "cargo_strap", "bike": faithful}}
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	check(Shed.held_by(me) == 0 and FuelShop.cargo_of(faithful).size() == 1, "strapped back on")
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	var drawn := false
	if view != null and view._views.has(faithful):
		drawn = (view._views[faithful]["node"] as Node).find_child("Cargo0", true, false) != null
	check(drawn, "the bike's drawn with its load strapped on")
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null, "back on with it strapped on")
	await _end(main)


func _end(main: Node) -> void:
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
