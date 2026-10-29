extends RefCounted
## Roadside wrenching on adventures (see Roadside): fixing what the bike set off with (a slack
## chain, low oil) with only what the toolbox holds, the bike stood at the roadside for everyone,
## pushing it and the tow, and normal rides keeping no roadside fixing at all. Run from tests/run_tests.gd: its
## _test_adv_wrench_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()

const KIT: Array[String] = ["tools", "oil", "brake_fluid", "chain_lube"]


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


## A toolbox on `bike` packed with `kit`.
func _toolbox(bike: int, kit: Array) -> int:
	var old := Shed.item_on(bike, "toolbox")
	if old != 0:
		Shed.items.erase(old)
	var id := Shed._new_item("alloy_toolbox", 0.0, 0.0, 0.0)
	Shed._move(id, "bike", bike)
	Shed.bikes[bike]["slots"]["toolbox"] = id
	Shed.bikes[bike]["bolted"]["toolbox"] = true
	Shed.items[id]["contents"] = kit.duplicate()
	return id


## The low oil the bike set off with, as the shed would have it.
func _low_oil(bike: int) -> void:
	var engine := Shed.item_on(bike, "engine")
	var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
	Shed.items[engine]["fluid"]["litres"] = cap * 0.3


## The rules, in the shed's state: an adventure harms nothing, the faults a bike set off with,
## the roadside record, fixing with only what's in the toolbox (used up and shown as gone), and
## home again afterwards.
func test_rules() -> void:
	Shed.start_new("Tester", 81)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	Shed.bikes[bike]["rider"] = me
	Shed.crew[me]["riding"] = bike
	Rides.start(20.0, 5)
	check(Adventure.active(), "an adventure on")
	check(Shed.check(me, {"a": "roadside_fault", "kind": "lever"}) != "" and Shed.check(me, {"a": "roadside_pump", "bike": bike, "side": "rear"}) != "",
		"nothing can break a bike out here, or let a tyre down")
	check(Shed.check(me, {"a": "roadside_tow", "by": 99}).contains("no tow needed"), "a bike that runs fine can't be put on a tow strap")
	check(not Shed.check(me, {"a": "roadside_tow", "by": 99, "dry": true}).contains("no tow needed"), "out of fuel it can")
	# It set off with a slack chain and low on oil.
	var chain := Shed.item_on(bike, "chain")
	Shed.items[chain]["slack"] = 62.0
	_low_oil(bike)
	check(Roadside.active(bike).map(func(f): return f["kind"]) == ["chain_slack", "oil"], "a slack chain and the oil light")
	check(Roadside.needs_tow(bike), "carrying a fault, it can have a tow")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_slack", "crouched": true}).contains("roadside"),
		"no fixing it while riding: stop and get off first")
	# Off at the roadside.
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(Basis(), Vector3(3.0, 0.0, -6000.0)),
		"roadside": {"x": 123456.25, "y": 2.0, "z": -987654.5, "yaw": 0.3, "s": 812.0}})
	var spot := Roadside.spot_of(bike)
	check(Roadside.parked(bike) and float(spot["x"]) == 123456.25 and float(spot["z"]) == -987654.5 and int(spot["trip"]) == int(Shed.adventure["id"]),
		"got off, it's stood at the roadside, kept in the route's frame")
	check(str(Shed.bikes[bike]["stand"]) == "side" and not Shed.abandoned_bikes().has(bike), "on its side stand, and not left for the recovery truck")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_slack", "crouched": true}).contains("no toolbox"),
		"no toolbox, nothing to fix it with")
	var box := _toolbox(bike, ["oil"])
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_slack", "crouched": true}).contains("tools"),
		"no tool roll in the toolbox, no tightening the chain (push it, or a tow)")
	Shed.items[box]["contents"] = KIT.duplicate()
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_slack"}).contains("Crouch"), "crouch to get at the chain")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "chain_slack", "crouched": true})
	check(float(Shed.items[chain]["slack"]) == Shed.CHAIN_SLACK_SET and Shed.toolbox_contents(box).has("tools"), "the chain tightened, tools kept")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_slack", "crouched": true}) != "", "nothing to fix twice")
	# The oil light: a litre from the toolbox.
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "oil"})
	check(Roadside.oil_level(bike) > Roadside.OIL_LIGHT and Roadside.find(bike, "oil").is_empty() and not Shed.toolbox_contents(box).has("oil"),
		"topped up from the toolbox's bottle (%.0f%%), the bottle's used" % (Roadside.oil_level(bike) * 100.0))
	_low_oil(bike)
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "oil"}).contains("used up"), "and there's no second bottle")
	# The toolbox, open, and what it says.
	Shed.request({"a": "roadside_open", "bike": bike, "open": true})
	check(Roadside.spot_of(bike).get("open", false), "the toolbox opened, its kit laid out")
	var lines := Roadside.kit_lines(box)
	var gone := lines.filter(func(k): return k["gone"]).map(func(k): return k["what"])
	check(gone == ["oil"] and lines.any(func(k): return k["what"] == "chain_lube" and k["left"] == 4),
		"the list shows what's used up as gone, and the lube left %s" % str(gone))
	# Pushing it: back on it, on foot.
	check(Shed.check(me, {"a": "roadside_push", "bike": bike}) == "", "you can push it along")
	Shed.request({"a": "roadside_push", "bike": bike})
	check(Shed.riding(me) == bike and Shed.bikes[bike].get("push", false), "pushing it: it moves with you")
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(), "roadside": {"x": 1.0, "y": 0.0, "z": 2.0, "yaw": 0.0, "s": 820.0}})
	check(not Shed.bikes[bike].has("push") and Roadside.parked(bike), "and stood up again further on")
	# The adventure's end: home to a bay, the low oil kept for the shed.
	Shed.request({"a": "adventure_end"})
	check(not Shed.bikes[bike].has("roadside") and Shed.bike_at_work(bike) and Shed.bay_at((Shed.bikes[bike]["xf"] as Transform3D).origin) >= 0,
		"the adventure over, the bike left at the roadside is home in a bay")
	check(not Roadside.find(bike, "oil").is_empty(), "its low oil still wants topping up")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "oil"}) != "", "back at the shed the roadside kit's put away")
	Shed.request({"a": "toolbox_pack", "item": box, "what": "oil"})
	check(Shed.toolbox_contents(box).has("oil") and not Roadside.used_of(box).has("oil"), "packing a new bottle of oil in the shed")
	# A save with a bike at the roadside comes home.
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	saved["bikes"][bike]["roadside"] = {"trip": 5, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "s": 0.0}
	saved["bikes"][bike]["push"] = true
	Shed.load_state(saved, "Tester")
	check(not Shed.bikes[bike].has("roadside") and not Shed.bikes[bike].has("push") and Shed.bike_at_work(bike), "a save loads with every bike home")
	Shed.stop()


## In the game: a fault the bike set off with shows itself out on the adventure; stopped and off,
## it stands at the roadside drawn for everyone, the walker fixes it with the toolbox's kit, you
## get back on where you left it, or push it.
## And a normal ride: no roadside fixing at all, exactly as before.
func test_session() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	var box := _toolbox(faithful, KIT)
	var home_xf: Transform3D = Shed.bikes[faithful]["xf"]
	# First a normal ride out of the shed onto the road: no roadside fixing, as it always was.
	Shed.request({"a": "mount", "bike": faithful})
	await _ticks(3)
	check(main.bike != null, "on Old Faithful in the town")
	var road_xf := Transform3D(Basis(), Vector3(0.0, 0.0, 140.0))
	Shed.request({"a": "dismount", "bike": faithful, "xf": road_xf})
	main._stop_riding()
	await _ticks(2)
	Shed.items[Shed.item_on(faithful, "chain")]["slack"] = 62.0
	check(not Shed.bike_at_work(faithful) and not Roadside.parked(faithful) and not Shed.bikes[faithful].has("roadside"),
		"a normal ride: left on the town's road, out of the shed, no roadside record")
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "chain", "road": true}
	main.walker.tool = "wrench"
	main.walker.crouched = true
	var road_plan: Dictionary = main.walker._make_plan()
	check(road_plan.is_empty() and main.walker.alt_plan.is_empty(), "with the wrench at its slack chain there's nothing to do (ride it home)")
	main.walker.tool = "hands"
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "road": true}
	check(main.walker._make_plan().is_empty(), "nor opening its toolbox")
	check(Shed.check(me, {"a": "roadside_fix", "bike": faithful, "fault": "chain_slack", "crouched": true}).contains("Ride it back to the shed")
		and Shed.check(me, {"a": "adjust_chain", "bike": faithful, "crouched": true}).contains("Ride it back to the shed"),
		"and the shed refuses roadside fixing and the workshop's own (a normal ride is just for riding)")
	check(Shed.check(me, {"a": "roadside_push", "bike": faithful}) != "" and Shed.check(me, {"a": "roadside_open", "bike": faithful, "open": true}) != "",
		"no roadside pushing or toolbox either")
	Shed.bikes[faithful]["xf"] = home_xf
	# Now the adventure.
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0   # (getting back on the bike just left waits a few seconds otherwise)
	Rides.start(20.0, 91)
	await _ticks(10)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null and Shed.riding(me) == faithful, "out on an adventure on Old Faithful (%s, %s, %d vs %d)" % [trip.on_trip(), main.bike, Shed.riding(me), faithful])
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	check(view != null, "the adventure has its roadside view")
	trip.world.preload_range(0.0, 1200.0)
	await _until_built(trip, 400.0)
	# It set off with the chain slack and low on oil: the rider's told, and the oil light's on.
	main.bike.engine_on = true
	main.bike.fuel_litres = main.bike.build.fuel_capacity
	_low_oil(faithful)
	main._sync_faults()
	await _ticks(2)
	check(main.hud.warn_lights.has("OIL") and main.hud._message.text.contains("oil"), "the oil light comes on, and the rider's told (%s)" % main.hud._message.text.left(60))
	main.hud.queue_redraw()
	await _ticks(2)
	check(main.hud.ride_hint.contains("tow") and main.hud.ride_hint.contains("roadside"), "stopped, it says what to do: fix it at the roadside or get a tow")
	# Off at the roadside.
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(5)
	var where: Vector3 = main.bike.global_position
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Roadside.parked(faithful), "off the bike: it stays at the roadside")
	check(view._views.has(faithful), "and it's drawn there for the crew")
	var shown: Node3D = view._views[faithful]["node"]
	check(shown.global_position.distance_to(where) < 1.5, "where it was left (%.2f m off)" % shown.global_position.distance_to(where))
	var picks := shown.find_children("Pick_*", "StaticBody3D", true, false)
	check(picks.size() > 10 and picks[0].get_meta("bike", 0) == faithful, "its parts can be aimed at (%d)" % picks.size())
	# The walker at it: the toolbox, then the chain with the shed's split link game.
	main.walker.tool = "hands"
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "roadside": true}
	var p: Dictionary = main.walker._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "roadside_open" and p["blocked"] == "", "hands on the toolbox: open it")
	Shed.request(p["action"])
	await _ticks(2)
	var cloth := shown
	if view._views.has(faithful):
		cloth = view._views[faithful]["node"]
	check(cloth.get_child_count() > 3, "the kit's laid out on a cloth beside the bike")
	var info := "\n".join(main.walker.roadside_lines(faithful, "toolbox"))
	check(info.contains("Slack chain") and info.contains("Toolbox: tools, oil"), "the part info says what's wrong and what's in the toolbox (%s)" % info.replace("\n", " / "))
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "chain", "roadside": true}
	main.walker.crouched = true
	main.walker.tool = "wrench"
	p = main.walker._make_plan()
	check(str(p.get("action", {}).get("fault", "")) == "chain_slack" and p["blocked"] == "", "crouched at the chain with the wrench: tighten it")
	Shed.request(p["action"])
	main.walker.tool = "hands"
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "engine", "roadside": true}
	p = main.walker._make_plan()
	check(str(p.get("action", {}).get("fault", "")) == "oil" and p["blocked"] == "", "at the engine: top the oil up")
	Shed.request(p["action"])
	await _ticks(2)
	check(Roadside.active(faithful).is_empty() and Roadside.used_of(box).has("oil"), "all fixed at the roadside, the oil gone from the toolbox")
	# Back on, where it was left; and ride off.
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and main.bike.global_position.distance_to(where) < 1.5, "back on it where it stood (%.2f m off), not back at the start" % (main.bike.global_position.distance_to(where) if main.bike else -1.0))
	check(main.bike.start_engine() == "", "it starts")
	# Pushing it.
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(10)
	main._get_off()
	await _ticks(3)
	Shed.request({"a": "roadside_push", "bike": faithful})
	await _ticks(3)
	check(main.bike != null and main.bike.pushing and main.bike.start_engine().contains("pushing"), "holding F at it: pushing it along, no engine")
	var from: Vector3 = main.bike.global_position
	Input.action_press("throttle", 1.0)
	await _ticks(360)
	Input.action_release("throttle")
	var went: float = main.bike.global_position.distance_to(from)
	check(went > 2.0 and absf(main.bike.speed) < Roadside.PUSH_SPEED + 0.4 and not main.bike.is_crashed,
		"it walks along at a walking pace (%.1f m in 3 s, %.1f m/s)" % [went, main.bike.speed])
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(5)
	main._get_off()
	await _ticks(3)
	check(Roadside.parked(faithful) and not Shed.bikes[faithful].has("push"), "and stood back on its stand")
	# The end: home.
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	check(not trip.on_trip() and Shed.bike_at_work(faithful) and not Shed.bikes[faithful].has("roadside"), "the adventure over, it's back in the shed")
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)


func _until_built(trip: AdventureTrip, s: float) -> void:
	var end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end and not trip.world.has_ground(s):
		await t.get_tree().process_frame
