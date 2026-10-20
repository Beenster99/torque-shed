extends RefCounted
## "Order one of these" and "Copy its blueprint" (BikeCopy, BikeCopyView, BikeOrderPanel, the
## adventure cafes' ParkedBike), run from tests/run_tests.gd (its _test_bike_copy_* functions
## hand over to these).

var t: Node   # the test runner: check(), get_tree(), _press(), _bike_named()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
		await t.get_tree().process_frame


## The items ordered (by the note on the box) and still in the delivery area.
func _ordered() -> Array:
	var out := []
	for id in Shed.items:
		if str(Shed.items[id].get("by", "")) != "" and not (str(Shed.items[id]["at"]) in ["bike", "engine"]):
			out.append(id)
	return out


## Ordering one of a shed bike: every part on its build at the parts computer's price, out of the
## player's own money; boxed in its colours; what doesn't fit waits on order and comes later.
func test_order() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var garage := Shed.garage_money
	Progress.set_money(500000)
	var a: int = t._bike_named("Rusty Ranger")
	var src := {"bike": a}
	var plan := BikeCopy.plan_of(src)
	var rows := BikeCopy.lines(plan, Shed.me())
	var cost := BikeCopy.total(rows)
	var expect := 0
	for r in rows:
		expect += Money.buy_price(str(r["part"]), Shed.me())
	check(rows.size() > 25 and rows.any(func(r): return r["slot"] == "frame") and rows.any(func(r): return r["slot"] == "engine")
		and rows.any(func(r): return r["slot"] == "head") and cost == expect and cost > 0,
		"its list is the whole build, frame and engine and all, at the parts computer's prices (%d parts, %s)" % [rows.size(), TvChannels.money_text(cost)])
	check(rows.all(func(r): return str(r["part"]) == str(plan["parts"][r["slot"]])), "every row is the part on that bike")
	check(BikeCopy.order(src) == "", "ordering one goes through")
	var got := _ordered()
	check(Progress.money() == 500000 - cost and Shed.garage_money == garage, "paid from your own money, not the business's (%s)" % TvChannels.money_text(cost))
	check(got.size() + Shed.on_order.size() == rows.size(), "every part is boxed or on order (%d boxed, %d on order)" % [got.size(), Shed.on_order.size()])
	var boxes_ok := true
	for id in got:
		var it: Dictionary = Shed.items[id]
		boxes_ok = boxes_ok and (it["boxed"] or PartsDB.is_fluid(str(it["part"]))) and str(it["by"]) == Shed.orderer_name(Shed.me()) \
			and int(it["paid"]) == Money.buy_price(str(it["part"]), Shed.me())
	check(boxes_ok, "boxed in the delivery area with your name on the note and what each cost")
	var tank := Shed.item_on(a, "tank")
	var tank_box: Array = got.filter(func(id): return Shed.items[id]["part"] == Shed.items[tank]["part"])
	check(not tank_box.is_empty() and Shed.items[tank_box[0]]["color"] == Shed.items[tank]["color"], "in that bike's colours")
	# Short of money: nothing's taken.
	Progress.set_money(10)
	check(BikeCopy.order(src).contains("you have"), "can't afford it: says so")
	check(Progress.money() == 10, "and nothing's taken")
	# The host works the price out itself: paid short (prices changed), it all goes back.
	Progress.set_money(1000)
	var before := _ordered().size() + Shed.on_order.size()
	Shed.request({"a": "copy_order", "src": src, "paid": 900})
	check(Progress.money() == 1900 and _ordered().size() + Shed.on_order.size() == before, "an order the host turns down is refunded in full")
	Progress.set_money(cost + 500)
	Shed.request({"a": "copy_order", "src": src, "paid": cost + 500})
	check(Progress.money() == cost + 500 + 500, "paid over, the change comes back")
	# Fill the delivery area: what doesn't fit waits on order, already paid for.
	Progress.set_money(5000000)
	for i in 6:
		if not Shed.on_order.is_empty():
			break
		BikeCopy.order(src)
	check(not Shed.on_order.is_empty() and Shed.on_order.all(func(o): return int(o["paid"]) > 0 and str(o["by"]) != ""),
		"with the delivery area full, the rest wait on order (%d)" % Shed.on_order.size())
	# Kept with the shed.
	var waiting := Shed.on_order.size()
	var state: Dictionary = Shed.save_snapshot().duplicate(true)
	Shed.start_new("Tester", 41)
	check(Shed.on_order.is_empty(), "a new shed has nothing on order")
	Shed.load_state(state, "Tester")
	check(Shed.on_order.size() == waiting, "what's on order comes back with the save")
	var old := state.duplicate(true)
	old.erase("on_order")
	Shed.load_state(old, "Tester")
	check(Shed.on_order.is_empty(), "an older save opens with nothing on order")
	Shed.load_state(state, "Tester")
	# Make room: they come.
	for id in _ordered():
		Shed._erase_item(id)
	for i in 30:
		Shed._deliver_on_order(1.5)
	check(Shed.on_order.size() < waiting and _ordered().size() >= mini(waiting, 4), "with room made, they're boxed up outside (%d left on order, %d boxed)" % [Shed.on_order.size(), _ordered().size()])
	Progress.profile = saved
	Shed.stop()


## Copying a bike's blueprint: named after it, its parts, colours, paint and fit; from a bike that
## isn't the shed's too; built from the usual way.
func test_copy() -> void:
	Shed.start_new("Tester", 42)
	var me := Shed.me()
	var a: int = t._bike_named("Rusty Ranger")
	Shed.request({"a": "geo_save", "bike": a, "geo": {"tank": {"p": Vector3(0.0, 0.06, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}}})
	check(Shed.check(me, {"a": "copy_blueprint", "src": {"bike": a}}) == "", "the host lets a bike's blueprint be copied")
	Shed.request({"a": "copy_blueprint", "src": {"bike": a}})
	var bp := Shed.blueprint_named("Rusty Ranger")
	var plan: Dictionary = Shed.blueprints.get(bp, {})
	check(bp != 0 and plan["parts"]["frame"] == Shed.items[Shed.item_on(a, "frame")]["part"] and plan["paint"] == Shed.bikes[a]["paint"]
		and plan["colors"].has("tank") and is_equal_approx((plan["geo"]["tank"]["p"] as Vector3).y, 0.06),
		"copied as \"Rusty Ranger\", with its parts, colours, paint and fit")
	Shed.request({"a": "copy_blueprint", "src": {"bike": a}})
	check(Shed.blueprint_named("Rusty Ranger 2") != 0 and Shed.blueprints.size() == 2, "copying it again keeps both (Rusty Ranger 2)")
	# A cafe biker's bike (not the shed's): its build as the game draws it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var b := CoffeeShop._make_bike(rng)
	var paint: Color = Shed.PAINTS[int(b["paint"])]
	var src := BikeCopy.build_src("Dave's Cafe racer", b["parts"], paint)
	Shed.request({"a": "copy_blueprint", "src": src})
	var dave := Shed.blueprint_named("Dave's Cafe racer")
	check(dave != 0 and Shed.blueprints[dave]["parts"] == PartsDB.sanitize_build(b["parts"].duplicate())
		and Shed.blueprints[dave]["paint"] == paint and Shed.blueprints[dave]["colors"]["tank"]["color"] == paint,
		"a biker's bike copies as theirs, its build and paint (tank in the paint)")
	# A made-up build is cleaned up by the host; no name gives it one.
	Shed.request({"a": "copy_blueprint", "src": {"build": {"parts": {"frame": "rocket", "tank": "sport_17"}, "paint": paint}}})
	var made := Shed.blueprints.values().filter(func(p): return str(p["parts"].get("tank", "")) == "sport_17" and p["name"] != "Rusty Ranger")
	check(made.size() == 1 and PartsDB.get_part(str(made[0]["parts"]["frame"])).get("kind", "") == "frame" and str(made[0]["name"]).contains("cc"),
		"a build that isn't one is made a real one, named for what it is (%s)" % (str(made[0]["name"]) if not made.is_empty() else "none"))
	check(Shed.check(me, {"a": "copy_blueprint", "src": {"bike": 99999}}) != "" and Shed.check(me, {"a": "copy_blueprint", "src": {"build": 3}}) != "",
		"a bike that's gone can't be copied")
	# Built from the usual way.
	Shed.request({"a": "bp_build", "bp": dave, "bay": 3})
	check(Shed.holograms.has(3) and Shed.plan_at(3)["name"] == "Dave's Cafe racer", "the copy builds from Blueprints like any other")
	while Shed.blueprints.size() < Shed.MAX_BLUEPRINTS:
		Shed.request({"a": "copy_blueprint", "src": {"bike": a}})
	check(Shed.check(me, {"a": "copy_blueprint", "src": {"bike": a}}).contains("Delete one"), "no more than %d blueprints" % Shed.MAX_BLUEPRINTS)
	Shed.stop()


## Every kind of bike has a real build behind it: customers', cafe bikers', riders on the roads,
## and the bikes parked at an adventure's cafes, drawn as themselves up close.
func test_sources() -> void:
	var look := RoadTraffic.look_of(7)
	check(look["parts"] == PartsDB.sanitize_build(look["parts"].duplicate()) and look["paint"] is Color, "a rider on the roads has a real build")
	var pb := ParkedBike.make(Transform3D(), 1234, Color(0.1, 0.35, 0.7), true, 220.0)
	var pb2 := ParkedBike.make(Transform3D(), 1234, Color(0.1, 0.35, 0.7), true, 220.0)
	check(pb.parts() == pb2.parts() and pb.parts() == PartsDB.sanitize_build(pb.parts().duplicate()) and str(pb.parts()["side_stand"]) != "none",
		"a bike parked at a cafe has a real build, the same on every machine, on its side stand")
	var src := pb.bike_src()
	var plan := BikeCopy.plan_of(src)
	check(plan["parts"] == pb.parts() and plan["colors"]["tank"]["color"] == Color(0.1, 0.35, 0.7), "and copies as drawn: tank in its colour")
	var bodies := pb.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == 1 and bodies[0].get_meta("parked_bike") == pb and (bodies[0] as StaticBody3D).collision_layer & 1, "it's solid and can be looked at")
	t.add_child(pb)
	pb.dress()
	check(pb.model != null and pb.model.get_child_count() > 0 and not pb._boxes.visible, "up close it's drawn as the bike itself, the boxes gone")
	pb.queue_free()
	pb2.free()
	# A stop's cafe has them.
	var found: Array = load("res://tests/adventure_stops_tests.gd")._find("cafe")
	var r := AdventureRoute.new()
	r.plan(int(found[0]), 150.0)
	var t0 := Time.get_ticks_usec()
	var node := AdventureStops.build(r, found[1], Transform3D(Basis(), Vector3(0, 100, 0)))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var parked := node.find_children("*", "ParkedBike", true, false)
	check(parked.size() >= 4 and parked.all(func(p): return not (p as ParkedBike).parts().is_empty()),
		"a bike cafe's forecourt has %d parked bikes, each with its own build (built in %.1f ms)" % [parked.size(), ms])
	var styles := {}
	for p in parked:
		styles[str(PartsDB.detect_style((p as ParkedBike).parts())["style"])] = true
	check(styles.size() >= 2, "of different styles %s" % str(styles.keys()))
	node.free()


## In the game: looking at a bike shows the prompt, {order_bike} opens its card with the parts,
## total and delivery, and its buttons order one and copy its blueprint. A cafe bike, a customer's
## and a rider going by are picked out too.
func test_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await t.get_tree().physics_frame
	var saved: Dictionary = Progress.profile.duplicate(true)
	var ws: Workshop = main.workshop
	var w: Walker = main.walker
	var a: int = t._bike_named("Rusty Ranger")
	var view: Node3D = ws.bike_views[a]
	w.place(Transform3D(Basis(Vector3.UP, PI * 0.5), view.global_position + Vector3(1.4, 0.1, 0.0)))
	w._look(0.0, -0.7)
	await _frames(4)
	var bc: BikeCopyView = main.bike_copy
	check(bc.looked.get("src", {}) == {"bike": a} and w.bike_prompt.contains("order one of these") and w.bike_prompt.contains("copy its blueprint"),
		"looking at a bike in a bay: the prompt to order one or copy it (%s)" % w.bike_prompt)
	await t.get_tree().process_frame
	var hud: HUD = main.hud
	check(hud._prompt.text.contains("%s: order one of these" % Controls.key("order_bike")), "in the HUD's prompts, with its key (%s)" % hud._prompt.text.replace("\n", " / "))
	Progress.set_money(500000)
	t._press("order_bike")
	await _frames(2)
	var panel: BikeOrderPanel = main.bike_order_panel
	var rows := BikeCopy.lines(BikeCopy.plan_of({"bike": a}), Shed.me())
	var cost := BikeCopy.total(rows)
	check(panel.visible and not w.controls_enabled and panel._list.get_child_count() == rows.size() and panel.text().contains("Total: %s" % TvChannels.money_text(cost))
		and panel.text().contains("Delivery: Straight away") and panel._order.text.contains(TvChannels.money_text(cost)) and not panel._order.disabled,
		"{order_bike}: its card, every part with its price, the total and the delivery (%d parts, %s)" % [rows.size(), TvChannels.money_text(cost)])
	check(panel._preview.visible and panel._preview.showing.begins_with("bike:") and panel._preview.pivot.get_child_count() == 1, "with the bike on a turntable")
	panel.press("Order one of these")
	await _frames(2)
	check(not panel.visible and Progress.money() == 500000 - cost and _ordered().size() + Shed.on_order.size() == rows.size(),
		"Order one of these: paid from your money, the parts on their way")
	t._press("order_bike")
	await _frames(2)
	panel.press("Copy its blueprint")
	await _frames(2)
	check(not panel.visible and Shed.blueprint_named("Rusty Ranger") != 0, "Copy its blueprint keeps it as one, named after it")
	Progress.set_money(5)
	t._press("order_bike")
	await _frames(2)
	check(panel.visible and panel._order.disabled and panel.text().contains("short"), "without the money, the order button's off and says why")
	panel.close_dialog()
	await _frames(1)
	# A cafe biker's parked bike.
	var was_time: float = Settings.time_of_day
	Daylight.current.set_time(10.0)
	var ids := CoffeeShop.spawn_group(1)
	Shed.changed.emit()
	await _frames(1)
	var cview: CoffeeView = main.coffee_view
	for id in ids:
		CoffeeShop.visitors()[id]["arrived"] = CoffeeShop.clock() - 1.0
		(cview.views[id] as CoffeeVisitor).park_now()
		(cview.views[id] as CoffeeVisitor).sit_now(int(CoffeeShop.visitors()[id]["seat"]))
	var v: Dictionary = CoffeeShop.visitors()[ids[0]]
	var bay := CoffeeShop.park_xf(int(v["park"])).origin
	var stand_at := bay + Vector3(0.0, 0.0, 1.9 if int(v["park"]) < CoffeeShop.ROW_A_X.size() else -1.9)
	w.place(Transform3D(Basis(Vector3.UP, 0.0 if stand_at.z > bay.z else PI), stand_at))
	w._look(0.0, -0.45)
	await _frames(6)
	var bsrc: Dictionary = bc.looked.get("src", {})
	check(bsrc.has("build") and bsrc["build"]["parts"] == PartsDB.sanitize_build(v["bike"]["parts"].duplicate())
		and str(bsrc["build"]["name"]).begins_with(CoffeeShop.first_name(v)) and w.bike_prompt != "" and w.look_prompt.contains("talk to"),
		"a cafe biker's parked bike: its own build, theirs by name, alongside talking to them (%s)" % str(bsrc.get("build", {}).get("name", "")))
	t._press("order_bike")
	await _frames(2)
	panel.press("Copy its blueprint")
	await _frames(2)
	check(Shed.blueprint_named(str(bsrc["build"]["name"])) != 0, "and its blueprint copies")
	await _frames(1)
	# A rider going by on the road, picked out from further off: theirs carry their look's seed.
	var rv: Dictionary = main.traffic._make_view(0, {"road": 0, "s": 0.0, "dir": 1, "v": 5.0, "seed": 7})
	check(int((rv["body"] as Node).get_meta("traffic_seed", -1)) == 7, "a rider on the roads carries its look's seed")
	(rv["body"] as Node).free()
	var body := AnimatableBody3D.new()
	body.collision_layer = 2
	body.set_meta("traffic_seed", 11)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	cs.shape = shape
	body.add_child(cs)
	main.world.add_child(body)
	w._look(0.0, 0.8)   # up over the cafe, at the sky
	body.global_position = w.camera.global_position - w.camera.global_transform.basis.z * 15.0
	await _frames(4)
	var tsrc: Dictionary = bc.looked.get("src", {})
	check(tsrc.has("build") and tsrc["build"]["parts"] == RoadTraffic.look_of(11)["parts"] and w.bike_info.begins_with("A rider going by"),
		"a rider going by, 15 m off: their bike (%s)" % w.bike_info)
	body.queue_free()
	Settings.time_of_day = was_time
	Progress.profile = saved
	main.queue_free()
	await _frames(2)
	Shed.stop()
