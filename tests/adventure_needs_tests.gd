extends RefCounted
## Hunger, thirst and tiredness on adventure rides (AdventureNeeds, AdventureNeedsView): the
## meters' rates, their effects, packing a lunch and eating it, buying at a counter, sitting
## down (with a mate: a picnic), sleeping the night for the crew and carrying the adventure on
## from a save. Run from tests/run_tests.gd: its _test_adv_needs_* functions hand over to these.
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

## The meters drain at their tuned rates: riding 90 minutes wants a drink at about 45 and a bite
## by an hour (a stop or two), and the tiredness warning comes at nearly two hours, so a 3 hour
## ride needs a sleep. On foot you tire slower, sat down you get some rest back (not all), and
## starving makes you tire faster.
func test_rates() -> void:
	Shed.start_new("Tester", 7)
	Rides.start(30.0, 5)
	var me := Shed.me()
	Shed._apply(me, {"a": "adventure_join", "bike": t._bike_named("Old Faithful")})
	check(Shed.riding(me) != 0 and AdventureNeeds.of(me).get("food") == 1.0, "joining the adventure starts you full up, on a bike")
	var thirsty := -1
	var hungry := -1
	var tired := -1
	var spent := -1
	for minute in 200:
		AdventureNeeds.tick(60.0)
		if thirsty < 0 and AdventureNeeds.level(me, "drink") < AdventureNeeds.LOW:
			thirsty = minute + 1
		if hungry < 0 and AdventureNeeds.level(me, "food") < AdventureNeeds.LOW:
			hungry = minute + 1
		if minute == 89:
			check(AdventureNeeds.level(me, "food") < AdventureNeeds.EMPTY and AdventureNeeds.level(me, "drink") <= 0.0,
				"90 minutes' riding without a stop empties you (food %.2f, drink %.2f)" % [AdventureNeeds.level(me, "food"), AdventureNeeds.level(me, "drink")])
	check(thirsty >= 40 and thirsty <= 50 and hungry >= 50 and hungry <= 62,
		"riding, thirst warns %d minutes in and hunger %d: one or two stops in a 90 minute ride" % [thirsty, hungry])
	# Eating and drinking as you go, the tiredness on its own.
	Shed._apply(me, {"a": "needs_debug", "food": 1.0, "drink": 1.0, "rest": 1.0})
	for minute in 200:
		AdventureNeeds.tick(60.0)
		Shed._apply(me, {"a": "needs_debug", "food": 1.0, "drink": 1.0})
		if tired < 0 and AdventureNeeds.level(me, "rest") < AdventureNeeds.LOW:
			tired = minute + 1
		if spent < 0 and AdventureNeeds.level(me, "rest") <= 0.0:
			spent = minute + 1
	check(tired >= 100 and tired <= 125 and spent >= 140 and spent <= 160,
		"tiredness warns %d minutes in and runs out by %d: a 3 hour ride needs a sleep" % [tired, spent])
	# On foot, sat down, starving.
	Shed._apply(me, {"a": "needs_debug", "food": 1.0, "drink": 1.0, "rest": 1.0})
	Shed.bikes[Shed.riding(me)]["rider"] = 0
	AdventureNeeds.tick(600.0)
	var foot_rest := AdventureNeeds.level(me, "rest")
	check(absf((1.0 - foot_rest) - 0.5 * 10.0 / AdventureNeeds.REST_MINUTES) < 0.01, "on foot you tire at half the rate (%.3f after 10 minutes)" % foot_rest)
	Shed._apply(me, {"a": "needs_debug", "rest": 0.1})
	Shed._apply(me, {"a": "needs_sit", "key": "seat:test#0", "s": 100.0, "on": true})
	AdventureNeeds.tick(600.0)
	var sat_rest := AdventureNeeds.level(me, "rest")
	AdventureNeeds.tick(3000.0)
	check(sat_rest > 0.3 and AdventureNeeds.level(me, "rest") <= AdventureNeeds.SIT_REST_CAP + 0.001,
		"sat down you get your breath back (%.2f after 10 minutes), but only so far (%.2f): a bench is no bed" % [sat_rest, AdventureNeeds.level(me, "rest")])
	Shed._apply(me, {"a": "needs_sit", "on": false})
	Shed._apply(me, {"a": "needs_debug", "food": 0.0, "drink": 1.0, "rest": 1.0})
	AdventureNeeds.tick(600.0)
	var starving := 1.0 - AdventureNeeds.level(me, "rest")
	check(absf(starving - AdventureNeeds.EMPTY_TIRING * 0.5 * 10.0 / AdventureNeeds.REST_MINUTES) < 0.01, "starving, you tire faster")
	# Changes go to the crew only as they move on a bit, not every frame.
	Shed._dirty = false
	AdventureNeeds.tick(0.05)
	check(not Shed._dirty, "a frame's worth of hunger doesn't send the crew a change")
	Shed.request({"a": "adventure_end"})
	Shed.stop()


## Tired, the bars answer slower, the screen's edges darken and your eyes blink shut now and
## then; hungry or thirsty you're warned, and starving you walk slower. Fresh, nothing changes.
func test_effects() -> void:
	var main := await _start(92, 20.0, false)
	await _go(main, 92)
	var view: AdventureNeedsView = main.trip.needs
	var step := func(want: float) -> float:
		var got := 0.0
		for i in 12:
			got = view.steer(want, 1.0 / 120.0)
		return got
	view.steer(0.0, 1.0)
	check(is_equal_approx(step.call(1.0), 1.0) and view.vignette < 0.01 and not view._vignette.visible, "fresh, the bars answer at once and the screen is clear")
	check(main.trip.needs._meters.visible, "the meters are up on the adventure")
	Shed.request({"a": "needs_debug", "food": 0.2, "drink": 0.5, "rest": 0.02})
	await _ticks(2)
	check(main.hud._message.text.contains("hungry") or main.hud._message.text.contains("tired") or main.hud._message.text.contains("exhausted"),
		"running low you're warned (%s)" % main.hud._message.text)
	view.steer(0.0, 1.0)
	var tired_step: float = step.call(1.0)
	check(tired_step < 0.5, "tired, the bars are slow to follow (%.2f of a full steer after 0.1 s)" % tired_step)
	# The bike gets the slowed steer through main.
	view._next_blink = 0.0
	var blinked := false
	for i in 400:
		await t.get_tree().process_frame
		blinked = blinked or view.blink > 0.9
	check(view.vignette > 0.4 and view._vignette.visible and blinked, "the edges go dark (%.2f) and your eyes close in a slow blink" % view.vignette)
	Shed.request({"a": "needs_debug", "food": 0.02})
	await _ticks(2)
	check(main.walker.pace_scale < 1.0 and main.hud._message.text.contains("starving"), "starving you're told, and walk slower (%.2f)" % main.walker.pace_scale)
	Shed.request({"a": "needs_debug", "food": 1.0, "drink": 1.0, "rest": 1.0})
	await _ticks(2)
	check(main.walker.pace_scale == 1.0 and AdventureNeedsView.steer_lag(AdventureNeeds.of(Shed.me())) == 0.0, "topped up, it all clears")
	Shed.request({"a": "adventure_end"})
	await _ticks(5)
	await _frames(2)
	check(not view._meters.visible and not view._vignette.visible, "back at the shed the meters are gone")
	await _end(main)


## A lunch and a flask packed into the tank bag in the shed (paid by the business), eaten out on
## the road a portion at a time: only stopped, each mouthful going further sat down. The bike
## got off at the roadside stays there, to be got back on.
func test_eat() -> void:
	var main := await _start(93)
	var faithful: int = t._bike_named("Old Faithful")
	var bag := Shed.item_on(faithful, "tank_bag")
	var money := Shed.garage_money
	check(AdventureNeeds.next_pack(bag) == "lunch", "an empty tank bag can take a packed lunch")
	Shed.request({"a": "needs_pack", "item": bag, "what": "lunch"})
	Shed.request({"a": "needs_pack", "item": bag})
	check(AdventureNeeds.packed(bag) == {"lunch": AdventureNeeds.LUNCH_PORTIONS, "flask": AdventureNeeds.FLASK_CUPS}
		and Shed.garage_money == money - AdventureNeeds.PACK_PRICE["lunch"] - AdventureNeeds.PACK_PRICE["flask"],
		"packed: a lunch and a flask of tea, bought from the business's account (%s)" % Shed.condition_text(Shed.items[bag]).get_slice("\n", 1))
	check(AdventureNeeds.next_pack(bag) == "" and Shed.check(Shed.me(), {"a": "needs_pack", "item": bag, "what": "lunch"}) != "", "and once both are full there's nothing more to pack")
	await _go(main, 93)
	var me := Shed.me()
	var view: AdventureNeedsView = main.trip.needs
	check(AdventureNeeds.left(me, "lunch") == 4 and AdventureNeeds.left(me, "flask") == 4, "out on the road the lunch and flask ride along on the bike")
	Shed.request({"a": "needs_debug", "food": 0.3, "drink": 0.3, "rest": 0.9})
	main.bike.linear_velocity = -main.bike.global_basis.z * 10.0
	main.bike.speed = 10.0
	check(view.eat() != "", "you can't eat on the move")
	main.bike.linear_velocity = Vector3.ZERO
	main.bike.speed = 0.0
	check(view.eat() == "" and is_equal_approx(AdventureNeeds.level(me, "food"), 0.3 + AdventureNeeds.PORTION["lunch"]["food"])
		and AdventureNeeds.left(me, "lunch") == 3, "stopped, {eat} has a sandwich: food %.2f, 3 left" % AdventureNeeds.level(me, "food"))
	check(view.eat() == "" and AdventureNeeds.left(me, "lunch") == 3, "and the next mouthful waits till you've finished that one")
	await _frames(3)
	check(is_instance_valid(view._food) and view._food.get_parent() == main.walker.camera, "the sandwich comes up in front of your eyes")
	view._eat_ready = 0
	view.eat()   # thirstier than hungry now: the flask
	check(AdventureNeeds.left(me, "flask") == 3 and AdventureNeeds.level(me, "drink") > 0.6, "then a cup of tea from the flask (drink %.2f)" % AdventureNeeds.level(me, "drink"))
	# Off the bike at the roadside: it stays there, drawn, and you can get back on it there.
	var s: float = main.trip.world.distance_of(main.bike.global_position, "own")
	var at: Vector3 = main.bike.global_position
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Roadside.parked(faithful)
		and Roadside.xf_in(main.trip.world, Roadside.spot_of(faithful)).origin.distance_to(at) < 1.0,
		"got off at the side of the road, the bike stays parked where you left it")
	view._eat_ready = 0
	Shed.request({"a": "needs_debug", "food": 0.3})
	view.eat()
	var standing := AdventureNeeds.level(me, "food") - 0.3
	Shed.request({"a": "needs_debug", "food": 0.3})
	Shed.request({"a": "needs_sit", "key": "seat:x#0", "s": s, "on": true})
	view._eat_ready = 0
	view.eat()
	var sitting := AdventureNeeds.level(me, "food") - 0.3
	check(is_equal_approx(sitting, standing * AdventureNeeds.SAT_BONUS), "sat down a sandwich goes further (%.2f against %.2f stood up)" % [sitting, standing])
	Shed.request({"a": "needs_sit", "on": false})
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and main.bike.global_position.distance_to(at) < 1.5, "and you get back on it where it stands, not back at the start")
	main._get_off()
	await _ticks(3)
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	check(Shed.bikes[faithful]["rider"] == 0 and not Shed.bikes[faithful].has("roadside") and Shed.bay_at((Shed.bikes[faithful]["xf"] as Transform3D).origin) >= 0,
		"left by the road as the adventure ends, the bike's brought back to its bay")
	await _end(main)


## A counter sells food and drink out of your own money (its own menu, or the default one),
## and you can't buy what you can't pay for.
func test_buy() -> void:
	var main := await _start(94, 20.0, false)
	await _go(main, 94)
	var me := Shed.me()
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	var lat := -w.route.width_at_s(70.0) * 0.5 + 0.8
	var counter := stub(w, AdventureNeeds.COUNTER_GROUP, w.transform_at(70.0, lat),
		1, {"menu": [{"name": "Pasty", "price": 5, "food": 0.5}, {"name": "Coffee", "price": 3, "kind": "drink"}]})
	await _walk_to(main, w.transform_at(70.0, lat + 1.2))
	view.near = view.find_near()
	check(str(view.near.get("kind", "")) == "counter" and view.prompt_text().contains("pasty"), "at the counter its menu shows: %s" % Controls.hint(view.prompt_text()))
	Progress.set_money(20)
	Shed.request({"a": "needs_debug", "food": 0.2, "drink": 0.2})
	check(view.buy(counter, 0) == "" and Progress.money() == 15 and is_equal_approx(AdventureNeeds.level(me, "food"), 0.7),
		"a pasty costs £5 of your own money and fills you up (food %.2f)" % AdventureNeeds.level(me, "food"))
	view._eat_ready = 0
	view.menu_index = 1
	check(view.buy(counter, view.menu_index) == "" and Progress.money() == 12 and AdventureNeeds.level(me, "drink") > 0.55, "a coffee off the same menu: £3")
	view._eat_ready = 0
	Progress.set_money(2)
	check(view.buy(counter, 0) != "" and Progress.money() == 2, "with £2 on you there's no pasty")
	check(AdventureNeeds.menu_of(Node3D.new()).size() == AdventureNeeds.DEFAULT_MENU.size(), "a counter with no menu of its own sells the usual")
	await _end(main)


## Walking up to a bench and sitting down (held there, eyes at a sitter's height), a mate sat
## beside you on its other place (their figure sat down too), the two of you a picnic: food goes
## further still. Walking off stands you up.
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
	check(AdventureNeeds.bonus(me) == AdventureNeeds.SAT_BONUS, "sat alone, food goes half as far again")
	# The mate takes the other place.
	var other := seat_key.left(seat_key.length() - 1) + ("1" if seat_key.ends_with("0") else "0")
	check(Shed.check(MATE, {"a": "needs_sit", "key": seat_key, "s": s, "on": true}) != "", "your place is yours")
	Shed._apply(MATE, {"a": "needs_sit", "key": other, "s": s, "on": true})
	check(AdventureNeeds.sat_with(me).size() == 2 and AdventureNeeds.bonus(me) == AdventureNeeds.PICNIC_BONUS, "your mate sits beside you: a picnic")
	Shed.request({"a": "needs_debug", "food": 0.2})
	Shed.request({"a": "needs_eat", "src": "buy", "name": "Roll", "food": 0.2, "drink": 0.0, "rest": 0.0})
	check(is_equal_approx(AdventureNeeds.level(me, "food"), 0.2 + 0.2 * AdventureNeeds.PICNIC_BONUS), "and what you eat goes twice as far (food %.2f)" % AdventureNeeds.level(me, "food"))
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
## they're in, the night passes for everyone: morning, rested, a touch peckish, and the adventure
## saved for later with where each of you slept.
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
	Shed.request({"a": "needs_debug", "food": 0.6, "drink": 0.6, "rest": 0.1})
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
	check(AdventureNeeds.level(me, "rest") == 1.0 and AdventureNeeds.level(MATE, "rest") == 1.0 and AdventureNeeds.level(me, "food") < 0.6,
		"everyone wakes rested, and a little peckish")
	var save := Shed.adventure_save
	check(not save.is_empty() and int(save["adventure"]["seed"]) == 96 and absf(float(save["at"]["Tester"]) - s) < 2.0 and save["at"].has("Mate"),
		"the adventure is saved: its road and where each of you slept (%.0f m)" % float(save.get("at", {}).get("Tester", -1.0)))
	await _end(main)


## Carried on another day: the save made by the night's sleep goes through a save file, the shed
## is opened again (nobody's out on an adventure), the host's Esc menu offers to continue it, and
## it loads with you on your bike back at the distance you slept, the meters as they were.
func test_resume() -> void:
	var main := await _start(97, 60.0, false)
	await _go(main, 97, 60.0)
	_add_mate("Mate")
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	# Past the first fork, the host's way taken: the night's stop is along that way.
	var forked := not w.route.forks.is_empty() and (w.route.forks[0]["ways"] as Array).size() > 1
	var go := 6000.0
	if forked:
		Shed.request({"a": "adventure_vote", "fork": 0, "way": 1})
		await _ticks(3)
		go = float(w.route.forks[0]["s"]) + 1500.0
	main.trip.jump(go)
	await _ticks(10)
	var s := w.distance_of(main.bike.global_position, "own")
	var lat := -w.route.width_at_s(s) * 0.5 + 1.0
	stub(w, AdventureNeeds.BED_GROUP, w.transform_at(s, lat), 1, {"key": "inn"})
	await _walk_to(main, w.transform_at(s - 1.4, lat))
	view.take(view.find_near())
	Shed._apply(MATE, {"a": "needs_bed", "key": "bed:tent#0", "s": s + 30.0, "on": true})
	Shed.request({"a": "needs_debug", "food": 0.55})
	await _ticks(2)
	Shed.request({"a": "needs_sleep"})
	await _ticks(2)
	var saved_food := AdventureNeeds.level(me, "food")
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
	check(is_equal_approx(AdventureNeeds.level(me, "rest"), 1.0) and absf(AdventureNeeds.level(me, "food") - saved_food) < 0.01,
		"rested, and as hungry as you went to bed")
	check(absf(AdventureNeeds.resume_s("Mate") - (s + 30.0)) < 0.5 and absf(Daylight.time_of_day() - AdventureNeeds.MORNING) < 0.1,
		"your mate carries on from their tent, in the morning")
	check(forked and AdventureForks.pick_of(0) == 1 and main.trip.world != null and int(main.trip.world.route.choices.get(0, -1)) == 1,
		"and the road's the same: the way picked at the first fork is still the way (%s)" % str(AdventureForks.picks()))
	Shed.crew.erase(MATE)
	await _end(main)


## On a real stop (an inn, as AdventureStops builds it): sit on one of its seats, buy from its
## counter's menu, and take one of its rooms, paying for the night out of your own pocket.
func test_real_stop() -> void:
	var found: Array = load("res://tests/adventure_stops_tests.gd")._find("inn")
	check(not found.is_empty(), "an inn turns up on some seed")
	if found.is_empty():
		return
	var main := await _start(int(found[0]), 150.0, false)
	await _go(main, int(found[0]), 150.0)
	var view: AdventureNeedsView = main.trip.needs
	var w: AdventureWorld = main.trip.world
	var s := float(found[1]["s"])
	for f in w.route.forks.size():
		Shed.request({"a": "adventure_vote", "fork": f, "way": 0})   # the main road, where the inn was found
	await _ticks(2)
	main.trip.jump(s - 40.0 - w.distance_of(main.bike.global_position, "own"))
	w.preload_range(s - 200.0, s + 200.0)
	await _ticks(4)
	var near_s := func(group: String) -> Array:
		return t.get_tree().get_nodes_in_group(group).filter(func(n): return absf(float(n.get_meta("s", -1.0)) - s) < 1.0)
	var seats: Array = near_s.call(AdventureNeeds.SEAT_GROUP)
	var counters: Array = near_s.call(AdventureNeeds.COUNTER_GROUP)
	var beds: Array = near_s.call(AdventureNeeds.BED_GROUP)
	check(not seats.is_empty() and not counters.is_empty() and not beds.is_empty(), "the inn %.1f km along has %d seats, %d counters, %d beds" % [s / 1000.0, seats.size(), counters.size(), beds.size()])
	if seats.is_empty() or counters.is_empty() or beds.is_empty():
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
	var counter: Node3D = counters[0]
	main.walker.place(counter.global_transform)
	await _ticks(2)
	view.near = view.find_near()
	var menu := AdventureNeeds.menu_of(counter)
	Progress.set_money(200)
	Shed.request({"a": "needs_debug", "food": 0.1, "drink": 0.1})
	var price := int(menu[0]["price"])
	check(str(view.near.get("kind", "")) == "counter" and view.buy(counter, 0) == "" and Progress.money() == 200 - price
		and AdventureNeeds.level(me, "food") + AdventureNeeds.level(me, "drink") > 0.2 + 0.01,
		"%s at %s: %s for %s" % [str(menu[0]["name"]), str(counter.get_meta("shop", "")), Controls.hint(view.prompt_text()), TvChannels.money_text(price)])
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
