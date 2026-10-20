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
## player's own money. New, it comes built (see test_built); used, laid out in its colours, and
## what doesn't fit waits on order and comes later.
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
	var bikes_before := Shed.bikes.size()
	check(BikeCopy.order(src) == "", "ordering one goes through")
	check(Progress.money() == 500000 - cost and Shed.garage_money == garage, "paid from your own money, not the business's (%s)" % TvChannels.money_text(cost))
	check(Shed.bikes.size() == bikes_before + 1 and _ordered().is_empty() and Shed.on_order.is_empty(),
		"ordered new, it comes built: one more bike, no boxes of parts")
	# Short of money: nothing's taken.
	Progress.set_money(10)
	check(BikeCopy.order(src).contains("you have"), "can't afford it: says so")
	check(Progress.money() == 10, "and nothing's taken")
	# The host works the price out itself: paid short (prices changed), it all goes back.
	Progress.set_money(1000)
	var before := Shed.bikes.size()
	Shed.request({"a": "copy_order", "src": src, "paid": 900})
	check(Progress.money() == 1900 and Shed.bikes.size() == before, "an order the host turns down is refunded in full")
	Progress.set_money(cost + 500)
	Shed.request({"a": "copy_order", "src": src, "paid": cost + 500})
	check(Progress.money() == cost + 500 + 500 and Shed.bikes.size() == before + 1, "paid over, the change comes back")
	# Ordered used, the parts come laid out in its colours, each with what it cost on the note.
	Progress.set_money(5000000)
	var used_rows := BikeCopy.lines(plan, Shed.me(), 0.5)
	check(BikeCopy.order(src, 0.5) == "", "ordering one used goes through")
	var got := _ordered()
	check(got.size() + Shed.on_order.size() == used_rows.size(), "every part is laid out or on order (%d out, %d on order)" % [got.size(), Shed.on_order.size()])
	var price_of := {}
	for r in used_rows:
		price_of[str(r["part"])] = int(r["price"])
	var notes_ok := true
	for id in got:
		var it: Dictionary = Shed.items[id]
		notes_ok = notes_ok and str(it["by"]) == Shed.orderer_name(Shed.me()) and int(it["paid"]) == int(price_of.get(str(it["part"]), -1))
	check(notes_ok, "in the delivery area with your name on the note and what each cost")
	var tank := Shed.item_on(a, "tank")
	var tank_box: Array = got.filter(func(id): return Shed.items[id]["part"] == Shed.items[tank]["part"])
	check(not tank_box.is_empty() and Shed.items[tank_box[0]]["color"] == Shed.items[tank]["color"], "in that bike's colours")
	# Fill the delivery area: what doesn't fit waits on order, already paid for.
	for i in 6:
		if not Shed.on_order.is_empty():
			break
		BikeCopy.order(src, 0.5)
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
	check(Shed.on_order.size() < waiting and _ordered().size() >= mini(waiting, 4), "with room made, they're laid out outside (%d left on order, %d out)" % [Shed.on_order.size(), _ordered().size()])
	Progress.profile = saved
	Shed.stop()


## Ordered new, one of these comes built (Simon: "when i order a new bike it should come ready
## made, not as parts"): the same build in its colours and fit, ready to ride with at least half
## a tank, in the yard by the roller door (a free bay once that's full), noted as bought for what
## it cost; with nowhere to leave it the host says so.
func test_built() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(50000000)
	var a: int = t._bike_named("Rusty Ranger")
	Shed.request({"a": "geo_save", "bike": a, "geo": {"tank": {"p": Vector3(0.0, 0.05, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}}})
	var src := {"bike": a}
	var plan := BikeCopy.plan_of(src)
	var cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me()))
	var before: Array = Shed.bikes.keys()
	var spot = Shed.free_retrieve_xf()
	check(BikeCopy.order(src) == "", "ordering one new goes through")
	var id := 0
	for b in Shed.bikes:
		if not before.has(b):
			id = int(b)
	check(id != 0, "a new bike is the shed's")
	if id == 0:
		Progress.profile = saved
		Shed.stop()
		return
	var bike: Dictionary = Shed.bikes[id]
	var same := true
	for slot in plan["parts"]:
		same = same and Contracts.current_parts(id)[slot] == str(plan["parts"][slot])
	check(same and str(bike["name"]) == "Rusty Ranger", "the very build it was ordered from, by name")
	var colours_ok := true
	var as_new := true
	for slot in PartsDB.SLOTS:
		var it := Shed.item_on(id, slot)
		if it == 0:
			continue
		as_new = as_new and float(Shed.items[it]["rust"]) == 0.0 and float(Shed.items[it]["wear"]) == 0.0 and float(Shed.items[it]["dirt"]) == 0.0 \
			and not Shed.items[it].get("boxed", false) and Shed.is_bolted(id, slot)
		if plan["colors"].has(slot):
			colours_ok = colours_ok and Shed.items[it]["color"] == plan["colors"][slot]["color"]
	check(as_new and colours_ok and bike["paint"] == Shed.bikes[a]["paint"], "every part on it, bolted up and as new, in that bike's colours and paint")
	check(is_equal_approx((Shed.geometry_of(id)["tank"]["p"] as Vector3).y, 0.05), "and its fit")
	var build := Shed.build_of(id)
	var engine: Dictionary = Shed.items[Shed.item_on(id, "engine")]
	check(Shed.is_complete(id) and Money.rideable(id) and build.fuel_litres >= build.fuel_capacity * 0.5 - 0.01
		and is_equal_approx(float(engine["fluid"]["litres"]), PartsDB.fluid_capacity(str(engine["part"]))) and float(engine["fluid"]["age"]) == 0.0,
		"ready to ride: complete, fresh oil to the mark and %.1f of %.1f litres of petrol" % [build.fuel_litres, build.fuel_capacity])
	check(spot is Transform3D and int(bike["bay"]) == -1 and (bike["xf"] as Transform3D).origin.distance_to((spot as Transform3D).origin) < 0.01
		and str(bike["stand"]) != "down" and Shed.bike_at_work(id), "left in the yard by the roller door, on its stand (%s)" % str(bike["stand"]))
	check(int(bike["bought"]) == cost and _ordered().is_empty(), "noted as bought for what it cost, and nothing boxed")
	# With the yard row full, the next goes in a free bay; with no bay either, the host says so.
	var guard := 0
	while Shed.free_retrieve_xf() != null and guard < 20:
		BikeCopy.order(src)
		guard += 1
	var bay := Shed.free_bay(Workshop.bay_count())
	before = Shed.bikes.keys()
	check(bay >= 0 and BikeCopy.order(src) == "", "with the yard full, one more goes through")
	var in_bay := 0
	for b in Shed.bikes:
		if not before.has(b):
			in_bay = int(b)
	check(in_bay != 0 and int(Shed.bikes[in_bay]["bay"]) == bay and Shed.on_paddock(in_bay), "and is left in bay %d, on its paddock stand" % (bay + 1))
	while Shed.free_bay(Workshop.bay_count()) >= 0 and guard < 30:
		BikeCopy.order(src)
		guard += 1
	var money := Progress.money()
	var why := BikeCopy.order(src)
	check(why.contains("nowhere") and Progress.money() == money, "nowhere left to put one: the host says so and nothing's taken (%s)" % why)
	check(BikeCopy.order(src, 0.5) == "", "but it can still be ordered used, as parts")
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
	var bikes_before := Shed.bikes.size()
	panel.press("Order one of these")
	await _frames(2)
	check(not panel.visible and Progress.money() == 500000 - cost and Shed.bikes.size() == bikes_before + 1 and ws.bike_views.size() == Shed.bikes.size(),
		"Order one of these: paid from your money, and it's in the yard, built and drawn")
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


## The quality to order one at (Simon: "Add a slider for bike quality when ordering one into the
## shed"): from worn used parts up to new, setting the state the parts come in and the price;
## the host checks the quality and works the price out itself; what waits on order keeps it.
func test_quality() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var a: int = t._bike_named("Rusty Ranger")
	var src := {"bike": a}
	var plan := BikeCopy.plan_of(src)
	var new_cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me()))
	var worn_cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me(), 0.0))
	var used_cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me(), 0.5))
	check(BikeCopy.total(BikeCopy.lines(plan, Shed.me(), 1.0)) == new_cost and worn_cost < used_cost and used_cost < new_cost
		and absf(float(worn_cost) / new_cost - BikeCopy.USED_PRICE) < 0.05,
		"the price goes with the quality: worn %s, used %s, new %s" % [TvChannels.money_text(worn_cost), TvChannels.money_text(used_cost), TvChannels.money_text(new_cost)])
	check(BikeCopy.used_cond(1.0).is_empty() and float(BikeCopy.used_cond(0.0)["wear"]) > float(BikeCopy.used_cond(0.5)["wear"])
		and BikeBuild.part_health(BikeCopy.used_cond(0.0)) < 0.5 and BikeBuild.part_health(BikeCopy.used_cond(0.75)) > 0.75,
		"and the state the parts come in (worn %d%%, used %d%%, nearly new %d%%)" % [roundi(BikeBuild.part_health(BikeCopy.used_cond(0.0)) * 100.0),
			roundi(BikeBuild.part_health(BikeCopy.used_cond(0.5)) * 100.0), roundi(BikeBuild.part_health(BikeCopy.used_cond(0.75)) * 100.0)])
	check(BikeCopy.quality_name(0.0) == "Worn" and BikeCopy.quality_name(0.5) == "Used" and BikeCopy.quality_name(1.0) == "New"
		and BikeCopy.quality_text(0.5).contains("% condition") and BikeCopy.quality_text(1.0).begins_with("New"),
		"each step along it is named (%s)" % BikeCopy.quality_text(0.5))
	# The host checks it.
	for q in [1.5, -0.2, NAN, "new"]:
		check(Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": new_cost, "quality": q}).contains("quality"),
			"a quality off the slider (%s) is turned down" % str(q))
	check(Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": used_cost, "quality": 0.5}) == ""
		and Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": worn_cost, "quality": 0.5}).contains("you paid"),
		"paid for worn but asked for used: the host prices it itself and says no")
	# Ordered used: worn parts, unboxed, each at its share of the price.
	Progress.set_money(used_cost + 100)
	check(BikeCopy.order(src, 0.5) == "", "ordering one used goes through")
	check(Progress.money() == 100, "paid the used price (%s)" % TvChannels.money_text(used_cost))
	var got: Array = _ordered()
	var cond := BikeCopy.used_cond(0.5)
	var all_used := true
	for id in got:
		var it: Dictionary = Shed.items[id]
		if PartsDB.is_fluid(str(it["part"])):
			continue
		all_used = all_used and not it["boxed"] and absf(float(it["wear"]) - float(cond["wear"])) < 0.001 \
			and absf(float(it["rust"]) - float(cond["rust"])) < 0.001 and int(it["paid"]) == maxi(1, roundi(Money.buy_price(str(it["part"]), Shed.me()) * BikeCopy.price_factor(0.5)))
	check(not got.is_empty() and all_used, "the parts come used: worn and rusty as the slider said, unboxed, each at 65%% of its price (%d parts)" % got.size())
	var told := Shed.condition_text(Shed.items[got[0]])
	check(told.begins_with("Condition"), "and say so when looked at (%s)" % told.split("\n")[0])
	# Paid over for used: the change comes back.
	Progress.set_money(used_cost + 300)
	Shed.request({"a": "copy_order", "src": src, "paid": used_cost + 300, "quality": 0.5})
	check(Progress.money() == used_cost + 300 + 300, "paid over, the change comes back")
	# Fill the delivery area: what waits on order keeps its quality, and comes that way.
	Progress.set_money(5000000)
	for i in 8:
		if not Shed.on_order.is_empty():
			break
		BikeCopy.order(src, 0.25)
	var waiting: Array = Shed.on_order.filter(func(o): return o.has("used"))
	check(not waiting.is_empty() and waiting.all(func(o): return absf(float(o["used"]["wear"]) - float(BikeCopy.used_cond(0.25)["wear"])) < 0.001),
		"with the delivery area full, the rest wait on order as worn as they were ordered (%d)" % waiting.size())
	for id in _ordered():
		Shed._erase_item(id)
	for i in 30:
		Shed._deliver_on_order(1.5)
	var came: Array = _ordered().filter(func(id): return not PartsDB.is_fluid(str(Shed.items[id]["part"])))
	var as_ordered := func(id): return absf(float(Shed.items[id]["wear"]) - float(BikeCopy.used_cond(0.25)["wear"])) < 0.001 and not Shed.items[id]["boxed"]
	check(not came.is_empty() and came.all(as_ordered), "and come that way when there's room (%d)" % came.size())
	# New: built, at the full price (see test_built).
	for id in _ordered():
		Shed._erase_item(id)
	Shed.on_order.clear()
	Progress.set_money(new_cost)
	var bikes_before := Shed.bikes.size()
	check(BikeCopy.order(src) == "" and Progress.money() == 0 and _ordered().is_empty() and Shed.bikes.size() == bikes_before + 1,
		"ordered new: it comes built, at the full price")
	Progress.profile = saved
	Shed.stop()


## The card's quality slider: the prices, the total and the button follow it; ordered from the card
## the parts come at that quality.
func test_quality_card() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await t.get_tree().physics_frame
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(500000)
	var a: int = t._bike_named("Rusty Ranger")
	var panel: BikeOrderPanel = main.bike_order_panel
	panel.open_bike({"bike": a}, "Rusty Ranger")
	await _frames(2)
	var plan := BikeCopy.plan_of({"bike": a})
	var new_cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me()))
	check(panel.visible and is_equal_approx(panel.quality(), 1.0) and panel.text().contains("New: built and ready to ride") and panel.text().contains("at least half a tank")
		and panel._order.text.contains(TvChannels.money_text(new_cost)), "the card opens at new, built and ready to ride, at the full price (%s)" % TvChannels.money_text(new_cost))
	panel.set_quality(0.3)
	await _frames(1)
	var cost := BikeCopy.total(BikeCopy.lines(plan, Shed.me(), 0.3))
	check(panel.text().contains(BikeCopy.quality_text(0.3)) and panel.text().contains("Total: %s" % TvChannels.money_text(cost))
		and panel._order.text.contains(TvChannels.money_text(cost)) and panel.text().contains("laid out"),
		"slid down to well used: its condition, the lower total and the button's price (%s: %s)" % [BikeCopy.quality_text(0.3), TvChannels.money_text(cost)])
	panel.press("Order one of these")
	await _frames(2)
	var got := _ordered().filter(func(id): return not PartsDB.is_fluid(str(Shed.items[id]["part"])))
	check(not panel.visible and Progress.money() == 500000 - cost and not got.is_empty()
		and got.all(func(id): return absf(float(Shed.items[id]["wear"]) - float(BikeCopy.used_cond(0.3)["wear"])) < 0.001),
		"ordered from the card: paid %s, the parts come well used" % TvChannels.money_text(cost))
	panel.set_quality(1.0)
	Progress.profile = saved
	main.queue_free()
	await _frames(2)
	Shed.stop()


## The parts computer's project bike order (Simon: "when i order a bike from the shop pc i should
## be presented with the condition slider"): the order button opens a card with the same quality
## slider, its price following it; the host builds the bike to that condition (new: ready to
## ride) and every bike bought comes with at least half a tank of fuel.
func test_project_card() -> void:
	Shed.start_new("Tester", 62)
	var me := Shed.me()
	Shed.garage_money = 10000000
	for id in Shed.bikes.keys():
		Shed.remove_bike(id)
	var half := func(id: int) -> bool:
		var b := Shed.build_of(id)
		return b.fuel_litres >= b.fuel_capacity * Shed.ORDER_FUEL - 0.01
	var newest := func() -> int:
		var top := 0
		for id in Shed.bikes:
			top = maxi(top, int(id))
		return top
	# The price goes with the condition.
	check(Money.typical_project_price(0.0) < Money.typical_project_price(0.5) and Money.typical_project_price(0.5) < Money.typical_project_price(1.0)
		and Money.typical_style_price("cruiser", 0.2) < Money.typical_style_price("cruiser", 1.0),
		"a project bike's price goes with its condition: worn %s, used %s, new %s" % [TvChannels.money_text(Money.typical_project_price(0.0)),
			TvChannels.money_text(Money.typical_project_price(0.5)), TvChannels.money_text(Money.typical_project_price(1.0))])
	for q in [1.5, -0.3, NAN, "new"]:
		check(Shed.check(me, {"a": "order", "quality": q}).contains("condition"), "a condition off the slider (%s) is turned down" % str(q))
	# As they come (the old way, still): at least half a tank.
	Shed.request({"a": "order"})
	check(half.call(newest.call()), "a project bike as it comes has at least half a tank")
	# Worn and nearly new: as worn as asked, half a tank either way.
	Shed.request(PartsComputer.bike_order("", 0.0))
	var worn: int = newest.call()
	Shed.request(PartsComputer.bike_order("", 0.8))
	var good: int = newest.call()
	check(Contracts.bike_health(worn) < Contracts.bike_health(good) - 0.15 and half.call(worn) and half.call(good),
		"ordered worn it's worn (%d%%), nearly new it's good (%d%%); half a tank in both" % [roundi(Contracts.bike_health(worn) * 100.0), roundi(Contracts.bike_health(good) * 100.0)])
	# New: built, every part new, ready to ride, paid for by the business.
	var money := Shed.garage_money
	Shed.request(PartsComputer.bike_order("", 1.0))
	var fresh: int = newest.call()
	var as_new := true
	for slot in PartsDB.SLOTS:
		var it := Shed.item_on(fresh, slot)
		if it != 0:
			as_new = as_new and float(Shed.items[it]["rust"]) + float(Shed.items[it]["wear"]) + float(Shed.items[it]["dirt"]) == 0.0
	var engine: Dictionary = Shed.items[Shed.item_on(fresh, "engine")]
	check(as_new and Shed.is_complete(fresh) and Money.rideable(fresh) and half.call(fresh)
		and is_equal_approx(float(engine["fluid"]["litres"]), PartsDB.fluid_capacity(str(engine["part"]))) and int(Shed.bikes[fresh]["bought"]) == money - Shed.garage_money,
		"ordered new: every part new, ready to ride with fresh oil and half a tank, for %s from the business" % TvChannels.money_text(money - Shed.garage_money))
	for id in Shed.bikes.keys():
		Shed.remove_bike(id)
	# The parts computer: the order button opens the card, and the card orders at its slider.
	var pc := PartsComputer.new()
	t.add_child(pc)
	pc.open()
	pc.set_bike_style("cruiser")
	pc._bike_btn.pressed.emit()
	await _frames(1)
	var card: ProjectOrderCard = pc.bike_card
	check(card.visible and card.style == "cruiser" and is_equal_approx(card.quality(), ProjectOrderCard.START_QUALITY) and card.text().contains("CONDITION")
		and card.text().contains("ORDER A CRUISER") and card.text().contains(TvChannels.money_text(Money.typical_style_price("cruiser", card.quality()))) and Shed.bikes.is_empty(),
		"the order button opens the card with the condition slider and the price at it, and orders nothing yet")
	card.set_quality(1.0)
	await _frames(1)
	var new_price := Money.typical_style_price("cruiser", 1.0)
	check(card.text().contains("New: built and ready to ride") and card.text().contains("ORDER A NEW CRUISER") and card._go.text.contains(TvChannels.money_text(new_price))
		and card.text().contains("half a tank"), "slid to new: ready to ride, around %s" % TvChannels.money_text(new_price))
	card.set_quality(0.2)
	await _frames(1)
	check(card.text().contains(ProjectOrderCard.condition_text(0.2)) and card._go.text.contains(TvChannels.money_text(Money.typical_style_price("cruiser", 0.2)))
		and Money.typical_style_price("cruiser", 0.2) < new_price, "slid down to well used: its condition and a lower price (%s)" % ProjectOrderCard.condition_text(0.2))
	card.set_quality(1.0)
	card._go.pressed.emit()
	await _frames(1)
	var got: int = newest.call()
	check(not card.visible and got != 0 and str(Shed.bikes[got]["name"]) == "New cruiser" and str(Shed.bikes[got].get("style_order", "")) == "cruiser"
		and Money.rideable(got) and half.call(got), "Order it: a new cruiser in a bay, ready to ride (%s)" % (str(Shed.bikes[got]["name"]) if got != 0 else "none"))
	Shed.garage_money = 5
	pc.open_bike_order()
	await _frames(1)
	check(card._go.disabled and card.text().contains("The business has"), "without the money, the card says so and won't order")
	card.close()
	pc.queue_free()
	await _frames(1)
	Shed.stop()
