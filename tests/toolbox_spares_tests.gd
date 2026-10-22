extends RefCounted
## Spare parts in a toolbox and working on a bike at the roadside with its tools (see
## ToolboxSpares): what fits in a toolbox and what doesn't, packing spares and taking them out,
## the wrench and hands on the bike's small parts with the toolbox open, a mate helping through
## the host, and the walker's plans for all of it. Run from tests/run_tests.gd: its
## _test_toolbox_spares_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()

const KIT: Array[String] = ["tools", "plug_kit", "pump"]


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


## An aluminium toolbox (six places) on `bike`, packed with `kit`.
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


## A new loose part of `part`, in `peer`'s hands.
func _hold(peer: int, part: String, wear := 0.0) -> int:
	var id := Shed._new_item(part, 0.0, 0.0, wear)
	Shed._move(id, "held", peer)
	return id


## A second player in the crew (a mate), for the host to take requests from.
func _mate() -> int:
	var mate := 4242
	Shed.crew[mate] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0}
	return mate


## What fits: the small spares a ride wants go in, the big parts never do, whatever the kind.
func test_fits() -> void:
	for kind in ["spark_plugs", "pads", "oil_filter", "master", "mirrors", "indicators", "final_drive"]:
		var first := str(PartsDB.by_kind[kind][0])
		check(ToolboxSpares.fits(first), "%s can go in a toolbox as a spare (%s)" % [PartsDB.KIND_NAMES[kind], first])
	for kind in ["engine", "frame", "wheel", "tank", "exhaust", "fork", "swingarm", "tyre", "panniers", "fairing"]:
		var all_out := true
		for id in PartsDB.by_kind[kind]:
			if ToolboxSpares.fits(str(id)):
				all_out = false
		check(all_out, "%s never go in a toolbox" % PartsDB.KIND_NAMES[kind])
	check(ToolboxSpares.fit_reason(str(PartsDB.by_kind["engine"][0])).contains("far too big"), "and it says it's far too big")
	var heavy := 0
	for kind in ToolboxSpares.SPARE_KINDS:
		for id in PartsDB.by_kind[kind]:
			if float(PartsDB.get_part(str(id)).get("mass", 0.0)) > ToolboxSpares.SPARE_MAX_KG:
				heavy += 1
				check(not ToolboxSpares.fits(str(id)) and ToolboxSpares.fit_reason(str(id)).contains("heavy"),
					"the %s is too heavy for a toolbox" % PartsDB.part_name(str(id)))
	var useful := 0
	for kind in ToolboxSpares.SPARE_KINDS:
		useful += PartsDB.by_kind[kind].filter(func(id): return ToolboxSpares.fits(str(id))).size()
	check(useful > 60, "a good list of spares to carry: %d parts (%d too heavy)" % [useful, heavy])
	check(ToolboxSpares.roadside_slot("front_pads") and ToolboxSpares.roadside_slot("spark_plugs") and ToolboxSpares.roadside_slot("mirrors")
		and not ToolboxSpares.roadside_slot("engine") and not ToolboxSpares.roadside_slot("frame") and not ToolboxSpares.roadside_slot("front_wheel"),
		"at the roadside the small stuff comes off, not the engine, frame or wheels")


## The rules in the shed's state: packing spares in the shed (sharing the box's places with its
## kit, and its weight), taking them out, then at the roadside the wrench and hands with the box
## open, a mate doing the same through the host, and nothing of it on a normal ride.
func test_rules() -> void:
	Shed.start_new("Tester", 82)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	var box := _toolbox(bike, KIT)
	var mass0: float = Shed.build_of(bike).total_mass
	# In the shed: a part in your hands goes in as a spare.
	var plugs := _hold(me, "iridium_plugs")
	var pads := str(PartsDB.by_kind["pads"][0])
	Shed.request({"a": "spare_stow", "item": box})
	check(not Shed.items.has(plugs) and ToolboxSpares.spares_of(box).size() == 1 and Shed.held_by(me) == 0,
		"spark plugs packed in the toolbox as a spare")
	check(str(ToolboxSpares.spares_of(box)[0]["part"]) == "iridium_plugs" and not ToolboxSpares.spares_of(box)[0].has("at"),
		"kept as the part it was, not somewhere in the shed")
	check(Shed.toolbox_text(Shed.items[box]).contains("Packed (4 of 6)") and Shed.toolbox_text(Shed.items[box]).contains("spark plugs"),
		"the toolbox's info lists the spare and counts its place: %s" % Shed.toolbox_text(Shed.items[box]).replace("\n", " / "))
	check(Shed.build_of(bike).total_mass > mass0, "and the bike's that bit heavier (%.2f kg)" % (Shed.build_of(bike).total_mass - mass0))
	var engine := _hold(me, "twin_700")
	check(Shed.check(me, {"a": "spare_stow", "item": box}).contains("too big"), "an engine won't go in a toolbox")
	Shed.items.erase(engine)
	var exhaust := _hold(me, str(PartsDB.by_kind["exhaust"][0]))
	check(Shed.check(me, {"a": "spare_stow", "item": box}).contains("too big"), "nor an exhaust")
	Shed.items.erase(exhaust)
	_hold(me, pads)
	Shed.request({"a": "spare_stow", "item": box})
	_hold(me, str(PartsDB.by_kind["mirrors"][0]))
	Shed.request({"a": "spare_stow", "item": box})
	check(ToolboxSpares.room_left(box) == 0 and Shed.next_kit(box) == "", "kit and spares fill its six places: no more kit to pack")
	_hold(me, str(PartsDB.by_kind["oil_filter"][0]))
	check(Shed.check(me, {"a": "spare_stow", "item": box}).contains("packed full"), "and no room for another spare")
	check(Shed.check(me, {"a": "toolbox_pack", "item": box, "what": "fuses"}).contains("packed full"), "nor more kit")
	Shed.items.erase(Shed.held_by(me))
	# Taken out again: the mirrors, as they went in.
	check(Shed.check(me, {"a": "spare_take", "item": box, "index": 2, "part": "nothing"}) != "", "the spare has to be the one asked for")
	Shed.request({"a": "spare_take", "item": box, "index": 2, "part": str(PartsDB.by_kind["mirrors"][0])})
	var mirrors := Shed.held_by(me)
	check(mirrors != 0 and str(Shed.items[mirrors]["part"]) == str(PartsDB.by_kind["mirrors"][0]) and str(Shed.items[mirrors]["at"]) == "held",
		"the mirrors out of the box, in your hands")
	check(ToolboxSpares.spares_of(box).size() == 2 and ToolboxSpares.room_left(box) == 1, "a place free again")
	check(Shed.check(me, {"a": "spare_take", "item": box, "index": 0}).contains("hands are full"), "one thing at a time")
	Shed.items.erase(mirrors)
	# Out on an adventure, at the roadside.
	Rides.start(20.0, 6)
	check(Adventure.active(), "an adventure on")
	Shed.bikes[bike]["rider"] = me
	Shed.crew[me]["riding"] = bike
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}) != "", "no spanners on it while it's being ridden")
	Shed.request({"a": "dismount", "bike": bike, "xf": Transform3D(Basis(), Vector3(3.0, 0.0, -6000.0)),
		"roadside": {"x": 100.0, "y": 2.0, "z": -900.0, "yaw": 0.0, "s": 500.0}})
	check(Roadside.parked(bike), "stood at the roadside")
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}).contains("Open the toolbox"), "the toolbox has to be open to work on it")
	check(Shed.check(me, {"a": "spare_take", "item": box, "index": 0}).contains("Open the toolbox"), "and to get at the spares")
	Shed.request({"a": "roadside_open", "bike": bike, "open": true})
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}) == "", "open, the wrench can unbolt the front pads")
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "engine"}).contains("job for the shed")
		and Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_wheel"}).contains("job for the shed")
		and Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "frame"}).contains("job for the shed"), "but not the engine, a wheel or the frame")
	check(Shed.check(me, {"a": "toolbox_pack", "item": box, "what": "fuses"}).contains("Ride it back"), "kit's still packed in the shed only")
	Shed.items[box]["contents"] = ["plug_kit", "pump"]
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}).contains("tool roll"), "no tool roll, no spanners")
	Shed.items[box]["contents"] = KIT.duplicate()
	# Worn pads off and a fresh spare on, all at the roadside.
	var old_pads := Shed.item_on(bike, "front_pads")
	Shed.items[old_pads]["wear"] = 0.9
	check(Shed.check(me, {"a": "remove", "bike": bike, "slot": "front_pads"}).contains("Unbolt"), "unbolt them before they come off")
	Shed.request({"a": "unbolt", "bike": bike, "slot": "front_pads"})
	check(not Shed.is_bolted(bike, "front_pads"), "front pads unbolted at the roadside")
	Shed.request({"a": "remove", "bike": bike, "slot": "front_pads"})
	check(Shed.item_on(bike, "front_pads") == 0 and Shed.held_by(me) == old_pads, "and off, in your hands")
	Shed.request({"a": "spare_stow", "item": box})
	check(not Shed.items.has(old_pads) and ToolboxSpares.spares_of(box).size() == 3, "the worn pads go in the toolbox")
	var fresh_at := -1
	var spares := ToolboxSpares.spares_of(box)
	for i in spares.size():
		if str(spares[i]["kind"]) == "pads" and float(spares[i].get("wear", 0.0)) < 0.1:
			fresh_at = i
	check(fresh_at >= 0, "the fresh spare pads are in there")
	Shed.request({"a": "spare_take", "item": box, "index": fresh_at, "part": pads})
	var fresh := Shed.held_by(me)
	check(fresh != 0 and float(Shed.items[fresh]["wear"]) < 0.1, "the fresh pads out of the toolbox")
	check(Shed.check(me, {"a": "install", "bike": bike, "slot": "front_caliper"}) == "", "and they fit at the caliper")
	Shed.request({"a": "install", "bike": bike, "slot": "front_caliper"})
	check(Shed.item_on(bike, "front_pads") == fresh, "fitted as the front pads")
	# A mate helps: bolting them up goes through the host like any of the shed's jobs.
	var mate := _mate()
	check(Shed.check(mate, {"a": "bolt", "bike": bike, "slot": "front_pads"}) == "", "a mate can bolt them up")
	Shed._apply(mate, {"a": "bolt", "bike": bike, "slot": "front_pads"})
	check(Shed.is_bolted(bike, "front_pads"), "the mate's bolted the front pads up")
	Shed._apply(mate, {"a": "unbolt", "bike": bike, "slot": "spark_plugs"})
	check(not Shed.is_bolted(bike, "spark_plugs"), "and undone the plugs, with the engine still in the frame")
	Shed._apply(mate, {"a": "remove", "bike": bike, "slot": "spark_plugs"})
	check(Shed.held_by(mate) != 0 and Shed.item_on(bike, "spark_plugs") == 0, "the mate has the old plugs out")
	Shed._apply(mate, {"a": "install", "bike": bike, "slot": "spark_plugs"})
	Shed._apply(mate, {"a": "bolt", "bike": bike, "slot": "spark_plugs"})
	check(Shed.item_on(bike, "spark_plugs") != 0 and Shed.is_bolted(bike, "spark_plugs") and Shed.held_by(mate) == 0, "and back in, tight")
	# Bigger jobs wait for the shed.
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "handlebars"}).contains("job for the shed"), "the bars stay on out here")
	# Shut, it's back to the toolbox's own fixes.
	Shed.request({"a": "roadside_open", "bike": bike, "open": false})
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}).contains("Open the toolbox"), "shut, no more spanners")
	# Saved and loaded, the spares are still in the box.
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed.load_state(saved, "Tester")
	check(ToolboxSpares.spares_of(box).size() == 2, "the spares are saved with the toolbox")
	# A normal ride: none of it.
	Shed.request({"a": "adventure_end"})
	Shed.bikes[bike]["xf"] = Transform3D(Basis(), Vector3(0.0, 0.0, 140.0))
	check(not Shed.bike_at_work(bike) and not Roadside.parked(bike), "out on the town's road, no roadside")
	check(Shed.check(me, {"a": "unbolt", "bike": bike, "slot": "front_pads"}).contains("Ride it back"), "a normal ride: no spanners on the road")
	check(Shed.check(me, {"a": "spare_take", "item": box, "index": 0}).contains("Ride it back"), "nor spares out of its toolbox")
	Shed.stop()


## In the game: at the roadside on an adventure the walker opens the toolbox, picks a spare
## with the turn keys, takes the wrench to the front pads, takes them off, swaps them for the
## spare from the box and bolts them up, the toolbox's list showing the spares throughout.
func test_session() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 10)
	await t.get_tree().physics_frame
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	var box := _toolbox(faithful, KIT)
	var pads := str(PartsDB.by_kind["pads"][0])
	var w: Walker = main.walker
	# Packing in the shed: the walker's plan with a part in hand at the toolbox.
	_hold(me, pads)
	w.tool = "hands"
	w.target = {"kind": "part", "bike": faithful, "slot": "toolbox"}
	var p: Dictionary = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "spare_stow" and p["blocked"] == "", "pads in hand at the toolbox: pack them as a spare")
	Shed.request(p["action"])
	_hold(me, "iridium_plugs")
	Shed.request(w._make_plan()["action"])
	check(ToolboxSpares.spares_of(box).size() == 2, "pads and plugs packed")
	w.spare_pick = 0
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "spare_take", "empty-handed at it, the second button takes a spare out")
	w.pick_spare(1)
	w.pick_spare(1)
	w._make_plan()
	check(w.spare_pick == 2 and str(w.alt_plan.get("action", {}).get("a", "")) == "toolbox_pack", "pick past the spares and it's back to packing kit")
	w.pick_spare(1)
	check(w.spare_pick == 0, "and round to the first spare again")
	# Out on the adventure.
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(20.0, 92)
	await _ticks(10)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null and Shed.riding(me) == faithful, "out on an adventure on Old Faithful")
	trip.world.preload_range(0.0, 1200.0)
	await _until_built(trip, 400.0)
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(5)
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Roadside.parked(faithful), "off at the roadside")
	w = main.walker
	var old_pads := Shed.item_on(faithful, "front_pads")
	Shed.items[old_pads]["wear"] = 0.85
	# The wrench at the pads with the box shut: open it first.
	w.tool = "wrench"
	w.target = {"kind": "part", "bike": faithful, "slot": "front_pads", "roadside": true}
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "unbolt" and str(p["blocked"]).contains("Open the toolbox"), "the wrench at the pads: open the toolbox first")
	w.tool = "hands"
	w.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "roadside": true}
	Shed.request(w._make_plan()["action"])
	await _ticks(2)
	check(Roadside.spot_of(faithful).get("open", false), "the toolbox open beside it")
	w.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "roadside": true}
	w.spare_pick = 5
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "spare_take" and w.spare_pick == 1, "the second button takes out a spare (kept to the list)")
	var info := "\n".join(w.roadside_lines(faithful, "toolbox"))
	check(info.contains("Spare parts") and info.contains("> ") and info.contains("pads"),
		"the part info lists the spares: %s" % info.replace("\n", " / ").left(200))
	# The wrench: unbolt the worn pads, hands take them off, into the box.
	w.tool = "wrench"
	w.target = {"kind": "part", "bike": faithful, "slot": "front_pads", "roadside": true}
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "unbolt" and p["blocked"] == "", "the wrench at the pads: unbolt them (%s)" % str(p.get("blocked", "")))
	Shed.request(p["action"])
	w.tool = "hands"
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "remove" and p["blocked"] == "", "hands: take them off")
	Shed.request(p["action"])
	await _ticks(2)
	check(Shed.held_by(me) == old_pads and Shed.item_on(faithful, "front_pads") == 0, "the worn pads in your hands")
	w.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "roadside": true}
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "spare_stow" and p["blocked"] == "", "at the toolbox: in they go")
	Shed.request(p["action"])
	await _ticks(2)
	# The fresh spare out, on and bolted up.
	var spares := ToolboxSpares.spares_of(box)
	var at := -1
	for i in spares.size():
		if str(spares[i]["kind"]) == "pads" and float(spares[i].get("wear", 0.0)) < 0.1:
			at = i
	w.target = {"kind": "part", "bike": faithful, "slot": "toolbox", "roadside": true}
	w.spare_pick = at
	w._make_plan()
	check(str(w.alt_plan.get("action", {}).get("a", "")) == "spare_take" and int(w.alt_plan["action"]["index"]) == at and w.alt_plan["blocked"] == "",
		"the turn keys picked the fresh pads")
	Shed.request(w.alt_plan["action"])
	await _ticks(2)
	var fresh := Shed.held_by(me)
	check(fresh != 0 and float(Shed.items[fresh]["wear"]) < 0.1, "the fresh pads in your hands")
	w.target = {"kind": "part", "bike": faithful, "slot": "front_caliper", "roadside": true}
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "install" and p["blocked"] == "", "at the caliper: fit them (%s)" % str(p.get("blocked", "")))
	Shed.request(p["action"])
	await _ticks(2)
	check(Shed.item_on(faithful, "front_pads") == fresh, "the fresh pads on")
	w.tool = "wrench"
	w.target = {"kind": "part", "bike": faithful, "slot": "front_pads", "roadside": true}
	p = w._make_plan()
	check(str(p.get("action", {}).get("a", "")) == "bolt" and p["blocked"] == "", "the wrench: bolt them up")
	Shed.request(p["action"])
	await _ticks(2)
	check(Shed.is_bolted(faithful, "front_pads") and Shed.is_complete(faithful), "bolted up: the bike's whole again")
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	check(view != null and view._views.has(faithful) and str(view._views[faithful]["sig"]).ends_with("|%d" % ToolboxSpares.spares_of(box).size()),
		"the roadside view draws it with its spares")
	# The frame's no roadside job: no plan for it.
	w.target = {"kind": "part", "bike": faithful, "slot": "frame", "roadside": true}
	check(w._make_plan().is_empty(), "nothing for the wrench on the frame out here")
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and main.bike.start_engine() == "", "back on, and it starts")
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)


func _until_built(trip: AdventureTrip, s: float) -> void:
	var end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end and not trip.world.has_ground(s):
		await t.get_tree().process_frame
