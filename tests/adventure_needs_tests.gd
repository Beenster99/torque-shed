extends RefCounted
## Stopping on adventure rides (AdventureNeeds, AdventureNeedsView): sitting down (with a mate
## beside you), sleeping the night for the crew and carrying the adventure on from a save; and
## that nothing wears down as you ride (the hunger, thirst and tiredness meters are gone). Run from tests/run_tests.gd: its _test_adv_needs_* functions hand over to these.
## A second rider is played on the host's side (peer MATE, with a crew entry of their own).

const Rides := preload("res://tests/rides.gd")

const MATE := 2

var t: Node   # the test runner: check(), get_tree()


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


## A stand-in for one of the stops' places (see AdventureNeedsView): a node in `group` at `xf`
## (in the adventure world), drawn as a plain block so it shows in pictures.
static func stub(world: Node3D, group: String, xf: Transform3D, places := 1, meta := {}) -> Node3D:
	var n := Node3D.new()
	n.name = "Stub_" + group
	n.add_to_group(group)
	n.set_meta("places", places)
	for k in meta:
		n.set_meta(k, meta[k])
	world.add_child(n)
	n.global_transform = xf
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	var w := 0.6 * places if group == AdventureNeeds.SEAT_GROUP else (0.9 * places if group == AdventureNeeds.BED_GROUP else 1.6)
	match group:
		AdventureNeeds.SEAT_GROUP:
			box.size = Vector3(w + 0.2, 0.06, 0.45)
			mesh.position = Vector3(0.0, -0.03, 0.05)
			mat.albedo_color = Color(0.45, 0.3, 0.16)
			for side in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var lb := BoxMesh.new()
				lb.size = Vector3(0.08, 0.42, 0.4)
				leg.mesh = lb
				leg.material_override = mat
				leg.position = Vector3(side * (w * 0.5), -0.27, 0.05)
				n.add_child(leg)
			var back := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(w + 0.2, 0.4, 0.05)
			back.mesh = bb
			back.material_override = mat
			back.position = Vector3(0.0, 0.25, 0.27)
			n.add_child(back)
		AdventureNeeds.BED_GROUP:
			# A sleeping mat in through the door (the node), as in a tent.
			box.size = Vector3(w, 0.1, 2.0)
			mesh.position = Vector3(0.0, 0.05, -AdventureNeedsView.BED_IN)
			mat.albedo_color = Color(0.85, 0.85, 0.9)
		_:
			box.size = Vector3(w, 1.0, 0.6)
			mesh.position = Vector3(0.0, 0.5, 0.0)
			mat.albedo_color = Color(0.6, 0.2, 0.15)
	mesh.mesh = box
	mesh.material_override = mat
	n.add_child(mesh)
	return n


## Starts the game and an adventure of `km` on `seed`: the host (you) on Old Faithful at the
## start, with a tank bag fitted to it. Returns the main scene.
func _start(seed := 91, km := 20.0, bag := true) -> Node:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	if bag:
		_fit_bag(faithful)
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	return main


## Fits a magnetic tank bag to `bike_id`, bolted on.
func _fit_bag(bike_id: int) -> int:
	var bag: int = Shed._new_item("mag_tank_bag_8", 0.0, 0.0, 0.0)
	Shed.bikes[bike_id]["slots"]["tank_bag"] = bag
	Shed.bikes[bike_id]["bolted"]["tank_bag"] = true
	Shed._move(bag, "bike", bike_id)
	return bag


func _go(main: Node, seed := 91, km := 20.0) -> void:
	Rides.start(km, seed)
	await _ticks(10)


## A second rider in the crew, on the adventure (played on this side).
func _add_mate(name := "Mate") -> void:
	Shed.crew[MATE] = {"name": name, "tool": "hands", "activity": "", "riding": 0, "fitted": 0, "removed": 0, "cleaned": 0,
		"repaired": 0, "painted": 0, "km": 0.0, "top_kmh": 0.0, "kmh": 0.0, "slot": 1}
	Shed._apply(MATE, {"a": "adventure_join", "bike": 0})
	# They've got off their bike already (nobody plays them to ride it).
	if Shed.riding(MATE) != 0:
		Shed.bikes[Shed.riding(MATE)]["rider"] = 0


func _end(main: Node) -> void:
	if Adventure.active():
		Shed.request({"a": "adventure_end"})
		await _ticks(5)
	main.queue_free()
	AdventureTrip.instant = false
	Shed.crew.erase(MATE)
	Shed.stop()
	await _frames(3)


## Gets you off your bike where it stands (stopped first) and stands you at `xf`.
func _walk_to(main: Node, xf: Transform3D) -> void:
	if main.bike != null:
		main.bike.linear_velocity = Vector3.ZERO
		main._get_off()
		await _ticks(3)
	main.walker.place(xf)
	await _ticks(2)


# ---------------------------------------------------------------------------- the tests

## Riding a long way, nothing wears down: no meters, nothing slows you and the bars answer as
## they always do; an old save's meters, and the lunch packed in its luggage, are let be.
func test_nothing_wears() -> void:
	var main := await _start(91, 20.0, true)
	await _go(main, 91)
	var me := Shed.me()
	var n := AdventureNeeds.of(me)
	check(not n.is_empty() and not n.has("food") and not n.has("drink") and not n.has("rest"), "on the adventure, no meters: %s" % str(n))
	for i in 120:
		await t.get_tree().physics_frame
	check(AdventureNeeds.of(me).keys() == AdventureNeeds.defaults().keys(), "and none come as you ride")
	check(Shed.check(me, {"a": "needs_eat", "src": "lunch"}) != "" and Shed.check(me, {"a": "needs_debug", "food": 0.1}) != "",
		"there's nothing to eat or drink, and nothing to top up")
	check(not InputMap.has_action("eat"), "and no key to eat with")
	check(not main.trip.needs.has_method("steer") and not ("_meters" in main.trip.needs), "nothing on the screen for it")
	var save := AdventureNeeds.sanitize_save({"adventure": {"seed": 5}, "at": {"Tester": 10.0}, "needs": {"Tester": {"food": 0.2}}})
	check(not save.is_empty() and not save.has("needs"), "an older save carries on, its meters dropped")
	await _end(main)


## Walking up to a bench and sitting down (held there, eyes at a sitter's height), a mate sat
## beside you on its other place (their figure sat down too). Walking off stands you up.
func test_sit() -> void:
	var main := await _start(95, 20.0, false)
	await _go(main, 95)
	_add_mate()
	var me := Shed.me()
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	var s := 80.0
	var lat := -w.route.width_at_s(s) * 0.5 + 0.8
	var bench := stub(w, AdventureNeeds.SEAT_GROUP, w.transform_at(s, lat).translated_local(Vector3(0.0, 0.45, 0.0)), 2)
	await _walk_to(main, w.transform_at(s - 1.0, lat))
	view.near = view.find_near()
	check(str(view.near.get("kind", "")) == "seat" and view.prompt_text().contains("sit"), "by a bench: %s" % Controls.hint(view.prompt_text()))
	view.take(view.near)
	await _ticks(3)
	var seat_key := str(AdventureNeeds.of(me).get("sat", ""))
	check(seat_key != "" and main.walker.perch != null and main.walker.camera.position.y == AdventureNeedsView.SIT_EYE
		and main.walker.global_position.distance_to(bench.global_position) < 0.7, "sat down on it (%s), held there with your eyes at a sitter's height" % seat_key)
	# The mate takes the other place.
	var other := seat_key.left(seat_key.length() - 1) + ("1" if seat_key.ends_with("0") else "0")
	check(Shed.check(MATE, {"a": "needs_sit", "key": seat_key, "s": s, "on": true}) != "", "your place is yours")
	Shed._apply(MATE, {"a": "needs_sit", "key": other, "s": s, "on": true})
	check(AdventureNeeds.sat(MATE) and str(AdventureNeeds.of(MATE)["sat"]) == other, "your mate sits beside you")
	# Their figure, as everyone else sees it, sat down.
	var rp := RemotePlayer.new()
	t.add_child(rp)
	rp.setup(MATE, "Mate", Color(0.2, 0.4, 0.9))
	for i in 90:
		await t.get_tree().process_frame
	var look: Node3D = rp._body_look
	check(look.position.y < -0.7 and (look.get_node("LegR") as Node3D).rotation.x > 0.8 and rp._head.position.y < 1.0,
		"their figure sits: hips down %.2f m, legs forward" % look.position.y)
	Shed._apply(MATE, {"a": "needs_sit", "on": false})
	for i in 90:
		await t.get_tree().process_frame
	check(absf(look.position.y) < 0.01 and absf(rp._head.position.y - Walker.EYE) < 0.01, "and stands up again when they get up")
	rp.queue_free()
	# Walking off stands you up, in front of the bench.
	view.stand_up()
	await _ticks(60)
	check(not AdventureNeeds.sat(me) and main.walker.perch == null and main.walker.camera.position.y > 1.5, "getting up you're on your feet again")
	await _end(main)


## Sleeping: you in one bed, your mate not yet in theirs and the host can't call it a night; once
## they're in, the night passes for everyone: morning, and the adventure saved for later with
## where each of you slept.
func test_sleep() -> void:
	var main := await _start(96, 20.0, false)
	await _go(main, 96)
	_add_mate()
	var me := Shed.me()
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	var s := 90.0
	var lat := -w.route.width_at_s(s) * 0.5 + 1.0
	stub(w, AdventureNeeds.BED_GROUP, w.transform_at(s, lat), 2)
	await _walk_to(main, w.transform_at(s - 1.4, lat))
	view.near = view.find_near()
	check(str(view.near.get("kind", "")) == "bed", "by a bed: %s" % Controls.hint(view.prompt_text()))
	view.take(view.near)
	await _ticks(3)
	check(AdventureNeeds.abed(me) and view.abed() and is_equal_approx(main.walker.camera.position.y, AdventureNeedsView.BED_EYE),
		"you lie down in it (%s, %s, eye %.2f)" % [AdventureNeeds.abed(me), view.abed(), main.walker.camera.position.y])
	check(Shed.check(me, {"a": "needs_sleep"}).contains("1 of 2") and not view._confirm.visible, "with your mate still up, the night can't pass yet")
	var key := str(AdventureNeeds.of(me)["bed"])
	Shed._apply(MATE, {"a": "needs_bed", "key": key.left(key.length() - 1) + ("1" if key.ends_with("0") else "0"), "s": s, "on": true})
	await _ticks(2)
	check(AdventureNeeds.all_abed() and view._confirm.visible and view._confirm_text.text.contains("sleep till morning"), "both in bed, the host is asked to call it a night")
	Daylight.current.set_time(23.0)
	Shed.request({"a": "needs_sleep"})
	await _ticks(2)
	check(absf(Daylight.time_of_day() - AdventureNeeds.MORNING) < 0.05, "the clock jumps to morning (%s)" % Daylight.clock_text(Daylight.time_of_day()))
	var save := Shed.adventure_save
	check(not save.is_empty() and int(save["adventure"]["seed"]) == 96 and absf(float(save["at"]["Tester"]) - s) < 2.0 and save["at"].has("Mate"),
		"the adventure is saved: its road and where each of you slept (%.0f m)" % float(save.get("at", {}).get("Tester", -1.0)))
	await _end(main)


## Carried on another day: the save made by the night's sleep goes through a save file, the shed
## is opened again (nobody's out on an adventure), the host's Esc menu offers to continue it, and
## it loads with you on your bike back at the distance you slept. A save from a build with
## forks on the road (the ways picked at them) carries on just the same.
func test_resume() -> void:
	var main := await _start(97, 60.0, false)
	await _go(main, 97, 60.0)
	_add_mate("Mate")
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	main.trip.jump(6000.0)
	await _ticks(10)
	var s := w.distance_of(main.bike.global_position, "own")
	var lat := -w.route.width_at_s(s) * 0.5 + 1.0
	stub(w, AdventureNeeds.BED_GROUP, w.transform_at(s, lat), 1, {"key": "inn"})
	await _walk_to(main, w.transform_at(s - 1.4, lat))
	view.take(view.find_near())
	Shed._apply(MATE, {"a": "needs_bed", "key": "bed:tent#0", "s": s + 30.0, "on": true})
	await _ticks(2)
	Shed.request({"a": "needs_sleep"})
	await _ticks(2)
	check(not Shed.adventure_save.is_empty(), "a night's sleep %.1f km along saves the adventure" % (s / 1000.0))
	# Quit: the save on disk, the game closed, opened again later.
	var text := var_to_str(Shed.save_snapshot())
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	check(not Adventure.active() and not Shed.adventure_save.is_empty() and Shed.bikes[faithful]["rider"] == 0 and not Shed.bikes[faithful].has("roadside"),
		"ending it there keeps the save, and the bikes come home")
	Shed.adventure_save = {}
	Shed.load_state(str_to_var(text), "Tester")
	Shed.crew[MATE] = {"name": "Mate", "slot": 1}
	await _ticks(2)
	check(not Adventure.active() and not Shed.adventure_save.is_empty(), "the shed opened again: nobody's out on the road, the adventure waits")
	# (as a save from before the forks were taken out has them: the ways picked and the votes, which are left be)
	Shed.adventure_save["adventure"]["picks"] = {0: 1, 1: 0}
	Shed.adventure_save["adventure"]["votes"] = {0: {1: 1}}
	main.menu.show_pause()
	check(main.menu._continue_adventure.visible and not main.menu._continue_adventure.disabled and main.menu._continue_adventure.text.begins_with("Continue adventure: %.1f" % (s / 1000.0)),
		"the host's Esc menu offers: %s" % main.menu._continue_adventure.text)
	main.menu.hide()
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	Shed.request({"a": "adventure_resume"})
	for i in 20:
		await t.get_tree().physics_frame
	var at: float = main.trip.world.distance_of(main.bike.global_position, "own") if main.trip.on_trip() and main.bike else -1.0
	check(main.trip.on_trip() and absf(at - s) < 6.0, "carried on: you're on your bike %.0f m along, where you slept (%.0f m)" % [at, s])
	check(not AdventureNeeds.abed(me) and not AdventureNeeds.sat(me), "up and about")
	check(absf(AdventureNeeds.resume_s("Mate") - (s + 30.0)) < 0.5 and absf(Daylight.time_of_day() - AdventureNeeds.MORNING) < 0.1,
		"your mate carries on from their tent, in the morning")
	check(not AdventureNeeds.make_save()["adventure"].has("picks"), "and the old forks' picks aren't saved again")
	Shed.crew.erase(MATE)
	await _end(main)


## On a real stop (an inn, as AdventureStops builds it): sit on one of its seats, and take one of
## its rooms, paying for the night out of your own pocket.
func test_real_stop() -> void:
	var found: Array = load("res://tests/adventure_stops_tests.gd")._find("inn")
	check(not found.is_empty(), "an inn turns up on some seed")
	if found.is_empty():
		return
	var main := await _start(int(found[0]), 150.0, false)
	Adventure.start(AdventurePlans.tour(str(found[2])), int(found[0]))   # the tour the inn was found on
	await _ticks(10)
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	var s := float(found[1]["s"])
	main.trip.jump(s - 40.0 - w.distance_of(main.bike.global_position, "own"))
	w.preload_range(s - 200.0, s + 200.0)
	await _ticks(4)
	var near_s := func(group: String) -> Array:
		return t.get_tree().get_nodes_in_group(group).filter(func(n): return absf(float(n.get_meta("s", -1.0)) - s) < 1.0)
	var seats: Array = near_s.call(AdventureNeeds.SEAT_GROUP)
	var beds: Array = near_s.call(AdventureNeeds.BED_GROUP)
	check(not seats.is_empty() and not beds.is_empty(), "the inn %.1f km along has %d seats, %d beds" % [s / 1000.0, seats.size(), beds.size()])
	if seats.is_empty() or beds.is_empty():
		await _end(main)
		return
	var me := Shed.me()
	var seat: Node3D = seats[0]
	var h := float(seat.get_meta("height", 0.45))
	await _walk_to(main, Transform3D(seat.global_basis, seat.global_position - seat.global_basis.z * 0.6 - Vector3.UP * h))
	view.near = view.find_near()
	check(str(view.near.get("kind", "")) == "seat" and view.take(view.near) == "", "you sit on its %s" % str(seat.get_meta("seat", "seat")))
	await _ticks(3)
	check(AdventureNeeds.sat(me) and main.walker.global_position.distance_to(seat.global_position) < 0.7, "held on the seat, facing out")
	view.stand_up()
	await _ticks(3)
	Progress.set_money(200)
	var bed: Node3D = beds[0]
	main.walker.place(bed.global_transform)
	await _ticks(2)
	view.near = view.find_near()
	var night := ceili(float(bed.get_meta("price", 0.0)))
	var before := Progress.money()
	check(str(view.near.get("kind", "")) == "bed" and view.take(view.near) == "" and Progress.money() == before - night,
		"%s: paid %s for the night" % [str(bed.get_meta("name", "")), TvChannels.money_text(night)])
	await _ticks(3)
	check(AdventureNeeds.abed(me) and Shed.check(me, {"a": "needs_sleep"}) == "", "in bed, alone on the ride: the night can pass")
	view.stand_up()
	await _ticks(3)
	Progress.set_money(0)
	view.near = view.find_near()
	check(view.take(view.near) == "", "going back to the same bed the same night costs nothing more")
	await _end(main)
