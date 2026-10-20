extends RefCounted
## Roadside wrenching on adventures (see Roadside): the odds of a breakdown, fixing it with only
## what the toolbox holds, the bike stood at the roadside for everyone, pushing it and the tow,
## and normal rides keeping no roadside fixing at all. Run from tests/run_tests.gd: its
## _test_adv_wrench_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()

const KEPT := {"chain_wear": 0.05, "chain_lube": 1.0, "chain_slack": 30.0, "oil_age": 0.1, "oil_level": 1.0,
	"engine_wear": 0.05, "wear": 0.05}
const NEGLECTED := {"chain_wear": 0.7, "chain_lube": 0.05, "chain_slack": 44.0, "oil_age": 2.5, "oil_level": 0.8,
	"engine_wear": 0.6, "wear": 0.6}
const KIT: Array[String] = ["tools", "spare_chain", "oil", "fuses", "levers", "plug_kit", "pump"]


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


## The expected number of breakdowns (and punctures) over `km` at `rates` on tarmac.
static func _expected(rates: Dictionary, km: float, surface := "tarmac") -> float:
	var n := 0.0
	for k in rates:
		n += float(rates[k]) * km
	return n + 2.0 * float(Puncture.PER_KM.get(surface, 0.003)) * km


## The odds: a couple of hours on a well kept bike might see one small thing; neglect, gravel and
## sand bring a lot more; a drop can snap a lever or knock something loose.
func test_odds() -> void:
	var kept := Roadside.rates(KEPT, "tarmac")
	var two_hours := _expected(kept, 140.0)
	check(two_hours > 0.3 and two_hours < 1.3, "two hours (140 km) on a well kept bike on tarmac: about %.2f small things expected" % two_hours)
	var gravel := _expected(Roadside.rates(KEPT, "gravel"), 140.0, "gravel")
	var sand := _expected(Roadside.rates(KEPT, "sand"), 140.0, "sand")
	check(gravel > two_hours * 1.8 and sand > two_hours * 1.5, "gravel and sand shake more loose (%.2f, %.2f)" % [gravel, sand])
	var worn := _expected(Roadside.rates(NEGLECTED, "tarmac"), 140.0)
	check(worn > two_hours * 3.0, "a worn, dry, badly kept bike breaks down far more (%.2f)" % worn)
	var dry := KEPT.duplicate()
	dry["chain_lube"] = 0.0
	check(float(Roadside.rates(dry, "tarmac")["chain_snap"]) > float(kept["chain_snap"]) * 3.0
		and float(Roadside.rates(dry, "tarmac")["chain_slack"]) > float(kept["chain_slack"]) * 2.0, "skipping the chain lube makes the chain go")
	var old_oil := KEPT.duplicate()
	old_oil["oil_age"] = 2.0
	check(float(Roadside.rates(old_oil, "tarmac")["oil"]) > float(kept["oil"]) * 2.0, "old oil runs low sooner")
	var low := KEPT.duplicate()
	low["oil_level"] = 0.3
	low["chain_slack"] = 60.0
	var lr := Roadside.rates(low, "tarmac")
	check(float(lr["oil"]) == 0.0 and float(lr["chain_slack"]) == 0.0, "what's gone already doesn't go again")
	check(Roadside.roll(kept, 1.0, 0.0) == "chain_slack" and Roadside.roll(kept, 1.0, 0.99) == "", "a roll picks a fault, or nothing")
	check(Roadside.drop_faults(0.1, 0.9) == ["lever"] and Roadside.drop_faults(0.9, 0.1) == ["rattle"] and Roadside.drop_faults(0.9, 0.9).is_empty(),
		"a drop can snap a lever or knock something loose")
	# Ridden out: two hundred two-hour rides on the kept bike, km by km.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var total := 0
	var none := 0
	for ride in 200:
		var n := 0
		for km in 140:
			if Roadside.roll(kept, 1.0, rng.randf()) != "":
				n += 1
		total += n
		none += 1 if n == 0 else 0
	check(float(total) / 200.0 > 0.15 and float(total) / 200.0 < 0.9 and none > 80,
		"over 200 two-hour rides: %.2f breakdowns a ride, %d rides with none at all" % [float(total) / 200.0, none])


## The rules, in the shed's state: faults, the roadside record, fixing with only what's in the
## toolbox (used up and shown as gone), and home again afterwards.
func test_rules() -> void:
	Shed.start_new("Tester", 81)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	# Not on an adventure: no breakdowns, no roadside fixing.
	Shed.bikes[bike]["rider"] = me
	Shed.crew[me]["riding"] = bike
	check(Shed.check(me, {"a": "roadside_fault", "kind": "chain_snap"}) != "", "no breakdowns on a normal ride")
	Shed.request({"a": "adventure_start", "seed": 5, "km": 20.0})
	check(Adventure.active(), "an adventure on")
	check(Shed.check(me, {"a": "roadside_fault", "kind": "warp_drive"}) != "", "only real faults")
	check(Shed.check(me, {"a": "roadside_tow", "by": 99}).contains("no tow needed"), "a bike that runs fine can't be put on a tow strap")
	check(not Shed.check(me, {"a": "roadside_tow", "by": 99, "dry": true}).contains("no tow needed"), "out of fuel it can")
	Shed.request({"a": "roadside_fault", "kind": "chain_snap"})
	check(Roadside.faults_of(bike).get("chain_snap", false) and Roadside.dead(bike), "out on the adventure the chain snaps: the bike's dead")
	check(Shed.check(me, {"a": "roadside_fault", "kind": "chain_snap"}) != "", "it can't snap twice")
	check(not Shed.check(me, {"a": "roadside_tow", "by": 99}).contains("no tow needed") and Roadside.needs_tow(bike), "broken down, it can")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true}).contains("roadside"),
		"no fixing it while riding: stop and get off first")
	# Off at the roadside.
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(Basis(), Vector3(3.0, 0.0, -6000.0)),
		"roadside": {"x": 123456.25, "y": 2.0, "z": -987654.5, "yaw": 0.3, "s": 812.0}})
	var spot := Roadside.spot_of(bike)
	check(Roadside.parked(bike) and float(spot["x"]) == 123456.25 and float(spot["z"]) == -987654.5 and int(spot["trip"]) == int(Shed.adventure["id"]),
		"got off, it's stood at the roadside, kept in the route's frame")
	check(str(Shed.bikes[bike]["stand"]) == "side" and not Shed.abandoned_bikes().has(bike), "on its side stand, and not left for the recovery truck")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true}).contains("no toolbox"),
		"no toolbox, nothing to fix it with")
	var box := _toolbox(bike, ["tools", "oil"])
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true}).contains("spare chain"),
		"no spare chain in the toolbox, no new chain (push it, or a tow)")
	Shed.items[box]["contents"] = KIT.duplicate()
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_snap"}).contains("Crouch"), "crouch to get at the chain")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true, "quality": 0.1})
	check(Roadside.dead(bike) and Shed.toolbox_contents(box).has("spare_chain"), "a split link that didn't seat: still snapped, the spare's kept")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true, "quality": 0.8})
	check(not Roadside.dead(bike) and not Shed.toolbox_contents(box).has("spare_chain") and Roadside.used_of(box) == ["spare_chain"],
		"the spare chain goes on, and it's gone from the toolbox (shown used up)")
	check(Roadside.spot_of(bike)["out"].has("chain"), "the old chain's out on the cloth")
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true}) != "", "nothing to fix twice")
	# The oil light: a litre from the toolbox.
	Roadside._break(bike, "oil", {})
	check(Roadside.oil_level(bike) < Roadside.OIL_LIGHT and not Roadside.find(bike, "oil").is_empty(), "the oil runs low: the oil light")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "oil"})
	check(Roadside.oil_level(bike) > Roadside.OIL_LIGHT and Roadside.find(bike, "oil").is_empty() and not Shed.toolbox_contents(box).has("oil"),
		"topped up from the toolbox's bottle (%.0f%%), the bottle's used" % (Roadside.oil_level(bike) * 100.0))
	Roadside._break(bike, "oil", {})
	check(Shed.check(me, {"a": "roadside_fix", "bike": bike, "fault": "oil"}).contains("used up"), "and there's no second bottle")
	# A blown fuse: the spares go one at a time.
	Roadside._break(bike, "fuse", {"which": "ignition"})
	check(Roadside.dead(bike) and Roadside.goes_left(box, "fuses") == 3, "a blown ignition fuse")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "fuse", "quality": 0.7})
	check(not Roadside.dead(bike) and Roadside.goes_left(box, "fuses") == 2 and Shed.toolbox_contents(box).has("fuses"), "swapped: two spares left")
	# A rattle, the wrench and the tool roll (which never runs out).
	Roadside._break(bike, "rattle", {"slot": "exhaust"})
	check(str(Roadside.faults_of(bike).get("rattle", "")) == "exhaust" and Roadside.at_slot(bike, "exhaust").size() == 1, "the exhaust's worked loose")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "rattle"})
	check(Roadside.faults_of(bike).get("rattle", "") == "" and Shed.toolbox_contents(box).has("tools"), "bolted up tight, tools kept")
	# A snapped lever.
	Roadside._break(bike, "lever", {"which": "brake"})
	check(Roadside.at_slot(bike, "front_master").size() == 1 and Roadside.at_slot(bike, "handlebars").size() == 1, "the brake lever, fixed at the bars")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "lever", "quality": 0.9})
	check(not Roadside.faults_of(bike).has("lever") and Roadside.goes_left(box, "levers") == 1, "a spare lever on, one left")
	# A puncture: the plug kit's game, then the pump.
	Shed.puncture_tyre(bike, "rear", "fast", 1.2)
	var tyre := Shed.item_on(bike, "rear_tyre")
	check(not Roadside.find(bike, "puncture", "rear").is_empty(), "a puncture in the back tyre")
	check(Shed.check(me, {"a": "roadside_pump", "bike": bike, "side": "rear"}).contains("plug"), "pumping it up first is no good")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "puncture", "side": "rear", "quality": 0.85})
	check(not Puncture.punctured(Shed.items[tyre]) and Roadside.goes_left(box, "plug_kit") == 2, "plugged at the roadside: two plugs left")
	Shed.request({"a": "roadside_pump", "bike": bike, "side": "rear"})
	check(Puncture.lost(Shed.items[tyre]) < 0.05 and Shed.toolbox_contents(box).has("pump"), "and pumped back up with the mini pump")
	# The toolbox, open, and what it says.
	Shed.request({"a": "roadside_open", "bike": bike, "open": true})
	check(Roadside.spot_of(bike).get("open", false), "the toolbox opened, its kit laid out")
	var lines := Roadside.kit_lines(box)
	var gone := lines.filter(func(k): return k["gone"]).map(func(k): return k["what"])
	check(gone.has("spare_chain") and gone.has("oil") and lines.any(func(k): return k["what"] == "fuses" and k["left"] == 2),
		"the list shows what's used up as gone, and the fuses left %s" % str(gone))
	# Pushing it: back on it, on foot.
	check(Shed.check(me, {"a": "roadside_push", "bike": bike}) == "", "you can push it along")
	Shed.request({"a": "roadside_push", "bike": bike})
	check(Shed.riding(me) == bike and Shed.bikes[bike].get("push", false), "pushing it: it moves with you")
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(), "roadside": {"x": 1.0, "y": 0.0, "z": 2.0, "yaw": 0.0, "s": 820.0}})
	check(not Shed.bikes[bike].has("push") and Roadside.parked(bike), "and stood up again further on")
	# A save made out here, or the adventure's end: home to a bay, faults kept for the shed.
	Roadside._break(bike, "lever", {"which": "clutch"})
	Shed.request({"a": "adventure_end"})
	check(not Shed.bikes[bike].has("roadside") and Shed.bike_at_work(bike) and Shed.bay_at((Shed.bikes[bike]["xf"] as Transform3D).origin) >= 0,
		"the adventure over, the bike left at the roadside is home in a bay")
	check(str(Roadside.faults_of(bike).get("lever", "")) == "clutch", "its snapped lever still wants fixing")
	check(Shed.check(me, {"a": "roadside_pump", "bike": bike, "side": "rear"}) != "", "back at the shed the roadside kit's put away")
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "lever"})
	check(not Roadside.faults_of(bike).has("lever") and Roadside.goes_left(box, "levers") == 1, "in the shed a new lever comes from the shed's spares")
	Shed.request({"a": "toolbox_pack", "item": box, "what": "spare_chain"})
	check(Shed.toolbox_contents(box).has("spare_chain") and not Roadside.used_of(box).has("spare_chain"), "packing a new spare chain in the shed")
	# Bolting the rattling part up in the shed sorts it too, and a new chain the snapped one.
	Roadside._break(bike, "rattle", {"slot": "exhaust"})
	Shed.request({"a": "bolt", "bike": bike, "slot": "exhaust"})
	Shed.bikes[bike]["bolted"]["exhaust"] = false
	Shed.request({"a": "bolt", "bike": bike, "slot": "exhaust"})
	check(not Roadside.faults_of(bike).has("rattle"), "in the shed, bolting the loose part up sorts the rattle")
	# Old saves have none of it, and a save with a bike at the roadside comes home.
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	saved["bikes"][bike]["roadside"] = {"trip": 5, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "s": 0.0}
	saved["bikes"][bike]["push"] = true
	Shed.load_state(saved, "Tester")
	check(not Shed.bikes[bike].has("roadside") and not Shed.bikes[bike].has("push") and Shed.bike_at_work(bike), "a save loads with every bike home")
	var old: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	for id in old["bikes"]:
		old["bikes"][id].erase("faults")
	Shed.load_state(old, "Tester")
	check(Roadside.faults_of(bike).is_empty() and Roadside.active(bike).all(func(f): return f["kind"] == "oil"),
		"an old save loads with nothing wrong (but the oil it really is low on)")
	Shed.stop()


## In the game: a breakdown out on the adventure shows itself and changes how the bike goes;
## stopped and off, it stands at the roadside drawn for everyone, the walker fixes it with the
## toolbox's kit (the shed's own games), you get back on where you left it, or push it.
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
	Shed.puncture_tyre(faithful, "rear", "slow", 0.5)
	Shed.items[Shed.item_on(faithful, "chain")]["slack"] = 62.0
	check(not Shed.bike_at_work(faithful) and not Roadside.parked(faithful) and not Shed.bikes[faithful].has("roadside"),
		"a normal ride: left on the town's road, out of the shed, no roadside record")
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "chain", "road": true}
	main.walker.tool = "wrench"
	main.walker.crouched = true
	var road_plan: Dictionary = main.walker._make_plan()
	check(road_plan.is_empty() and main.walker.alt_plan.is_empty(), "with the wrench at its slack chain there's nothing to do (ride it home)")
	main.walker.tool = "hands"
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "rear_tyre", "road": true}
	check(main.walker._make_plan().is_empty() and main.walker.alt_plan.is_empty(), "nor at its punctured tyre")
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "road": true}
	check(main.walker._make_plan().is_empty(), "nor opening its toolbox")
	check(Shed.check(me, {"a": "roadside_fix", "bike": faithful, "fault": "chain_slack", "crouched": true}).contains("Ride it back to the shed")
		and Shed.check(me, {"a": "roadside_fix", "bike": faithful, "fault": "puncture", "side": "rear", "quality": 1.0}) != ""
		and Shed.check(me, {"a": "adjust_chain", "bike": faithful, "crouched": true}).contains("Ride it back to the shed"),
		"and the shed refuses roadside fixing and the workshop's own (a normal ride is just for riding)")
	check(Shed.check(me, {"a": "roadside_push", "bike": faithful}) != "" and Shed.check(me, {"a": "roadside_open", "bike": faithful, "open": true}) != "",
		"no roadside pushing or toolbox either")
	Shed.items[Shed.item_on(faithful, "chain")]["slack"] = 30.0
	Shed.items[Shed.item_on(faithful, "rear_tyre")].erase("puncture")
	Shed.items[Shed.item_on(faithful, "rear_tyre")].erase("deflate")
	Shed.bikes[faithful]["xf"] = home_xf
	# Now the adventure.
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0   # (getting back on the bike just left waits a few seconds otherwise)
	Adventure.start(91, 20.0)
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
	# The chain snaps on the move: the engine revs with nothing driving the wheel.
	main.bike.engine_on = true
	main.bike.gear = 1
	main.bike.fuel_litres = main.bike.build.fuel_capacity
	Shed.request({"a": "roadside_fault", "kind": "chain_snap"})
	await _ticks(2)
	check(main.bike.faults.get("chain_snap", false) and main.hud._message.text.contains("snapped"), "the chain snaps: the rider's told (%s)" % main.hud._message.text.left(60))
	main.bike.throttle = 0.8
	await _ticks(60)
	check(absf(float(main.bike.wheels[1]["drive_torque"])) < 0.01 and absf(main.bike.speed) < 1.0, "nothing drives the back wheel (%.1f m/s)" % main.bike.speed)
	main.bike.throttle = 0.0
	main.hud.queue_redraw()
	await _ticks(2)
	check(main.hud.ride_hint.contains("tow") and main.hud.ride_hint.contains("roadside"), "stopped, it says what to do: fix it at the roadside or get a tow")
	# A blown ignition fuse won't let it start; the oil light shows on the dash.
	Shed.request({"a": "roadside_fault", "kind": "fuse", "which": "ignition"})
	await _ticks(2)
	check(not main.bike.engine_on and main.bike.start_engine().contains("fuse"), "a blown ignition fuse: it cuts out and won't start")
	Shed.request({"a": "roadside_fault", "kind": "oil"})
	await _ticks(2)
	check(main.hud.warn_lights.has("OIL"), "the oil light comes on")
	Shed.request({"a": "roadside_fault", "kind": "lever", "which": "brake"})
	await _ticks(2)
	check(str(main.bike.faults.get("lever", "")) == "brake", "a snapped brake lever on the bike")
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
	check(info.contains("Snapped chain") and info.contains("Toolbox: tools, spare chain"), "the part info says what's wrong and what's in the toolbox")
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "chain", "roadside": true}
	main.walker.crouched = true
	p = main.walker._make_plan()
	check(str(p.get("game", "")) == "roadside" and str(p.get("kind", "")) == "chain" and p["blocked"] == "", "crouched at the chain, hands: the split link game")
	main.walker.tool = "wrench"
	check(main.walker._make_plan().is_empty(), "the wrench is no good on a snapped chain")
	main.walker.tool = "hands"
	main.walker.plan = p
	var game := RoadsideGame.new(7, "chain")
	game.cursor.x = game.hole
	for i in 60:
		game.step(1.0 / 60.0)
	check(game.found, "the split link found")
	while not game.done():
		game.cursor.x = game.hole_now()
		game.step(1.0 / 60.0)
	check(game.quality() > 0.8, "and the clip pressed on steadily (%d%%)" % roundi(game.quality() * 100.0))
	var a: Dictionary = p["action"].duplicate()
	a["quality"] = game.quality()
	Shed.request(a)
	await _ticks(2)
	check(not Roadside.faults_of(faithful).has("chain_snap") and Roadside.used_of(box).has("spare_chain"), "the spare chain's on, and gone from the toolbox")
	# The rest from the toolbox.
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "saddle", "roadside": true}
	p = main.walker._make_plan()
	check(str(p.get("kind", "")) == "fuse", "at the seat: the fuse box")
	Shed.request({"a": "roadside_fix", "bike": faithful, "fault": "fuse", "quality": 0.8})
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "engine", "roadside": true}
	p = main.walker._make_plan()
	check(str(p.get("action", {}).get("fault", "")) == "oil" and p["blocked"] == "", "at the engine: top the oil up")
	Shed.request(p["action"])
	main.walker.target = {"kind": "part", "bike": faithful, "slot": "handlebars", "roadside": true}
	p = main.walker._make_plan()
	check(str(p.get("kind", "")) == "lever", "at the bars: a spare lever")
	Shed.request({"a": "roadside_fix", "bike": faithful, "fault": "lever", "quality": 0.8})
	await _ticks(2)
	check(Roadside.active(faithful).is_empty(), "all fixed at the roadside")
	# Back on, where it was left; and ride off.
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and main.bike.global_position.distance_to(where) < 1.5, "back on it where it stood (%.2f m off), not back at the start" % (main.bike.global_position.distance_to(where) if main.bike else -1.0))
	check(main.bike.faults.is_empty() and main.bike.start_engine() == "", "it starts again")
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
