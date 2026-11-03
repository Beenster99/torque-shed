extends RefCounted
## Simon's 2026-11-03 asks: getting off a bike leaves its engine running (it ticks over where it's
## left, for everyone, till someone gets back on, switches it off or does anything else with it),
## and pushing a bike at the roadside shows the rider walking it along beside it, hands on it.
## Run from tests/run_tests.gd: its _test_idle_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _start() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	return main


func _done(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await t.get_tree().process_frame


## On `bike_id` with its engine running (started on the key, as a player does).
func _on_and_running(main: Node, bike_id: int) -> void:
	main._left_bike = 0
	main._try_mount(bike_id)
	await _ticks(3)
	if main.bike == null:
		return
	if not main.bike.engine_on:
		main._ignition()
		for i in 480:
			await _ticks(1)
			if main.bike.engine_on and not main.bike.is_starting():
				break
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(5)


## In the shed: off with it running, it ticks over (drawn so: its idle, smoke and lamps); back on
## and it's still running; off with it switched off it's quiet; the key on foot switches it off,
## and so does wheeling it about. Nobody's bike is left running in a loaded save.
func test_shed() -> void:
	var main: Node = await _start()
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	await _on_and_running(main, faithful)
	check(main.bike != null and main.bike.engine_on, "on Old Faithful with its engine running")
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Shed.idling(faithful), "got off with it running: it's left ticking over")
	check(main.workshop.bike_views.has(faithful) and IdlingEngine.of(main.workshop.bike_model(faithful)) != null,
		"the parked bike is drawn ticking over (its idle, exhaust and lamps)")
	main._left_bike = 0
	main._try_mount(faithful)
	await _ticks(3)
	check(main.bike != null and main.bike.engine_on and main.bike.rpm > 0.0 and main.bike.gear == Bike.NEUTRAL,
		"back on, it's still running, in neutral (%.0f rpm)" % (main.bike.rpm if main.bike else 0.0))
	main.bike.stop_engine()
	await _ticks(30)
	main._get_off()
	await _ticks(3)
	check(not Shed.idling(faithful) and IdlingEngine.of(main.workshop.bike_model(faithful)) == null,
		"switched off before getting off: it's left quiet")
	check(Shed.check(me, {"a": "engine_off", "bike": faithful}) != "", "and there's no engine to switch off")
	# The key on foot.
	await _on_and_running(main, faithful)
	main._get_off()
	await _ticks(3)
	check(Shed.idling(faithful) and Shed.check(me, {"a": "engine_off", "bike": faithful}) == "", "left running again, the key can switch it off")
	Shed.request({"a": "engine_off", "bike": faithful})
	await _ticks(3)
	check(not Shed.idling(faithful) and IdlingEngine.of(main.workshop.bike_model(faithful)) == null, "the key on foot switches it off")
	# Wheeling it about switches it off.
	await _on_and_running(main, faithful)
	main._get_off()
	await _ticks(3)
	var grab := {"a": "grab_bike", "bike": faithful}
	var why := Shed.check(me, grab)
	Shed.request(grab)
	await _ticks(3)
	check(why == "" and not Shed.idling(faithful), "taking hold of it to wheel it about switches it off (%s)" % why)
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Shed.bikes[faithful]["xf"]})
	await _ticks(3)
	# Never left running in a loaded save.
	Shed.bikes[faithful]["idling"] = true
	Roadside.bring_home()
	check(not Shed.idling(faithful), "no engine's left running in a loaded save")
	await _done(main)


## Out on an adventure: off with it running at the roadside it ticks over there; pushing it, you
## walk beside it in your own gear, the left hand on the left grip, legs stepping as it goes, and
## the engine's off.
func test_roadside() -> void:
	AdventureTrip.instant = true
	var main: Node = await _start()
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(60.0, 91)
	await _ticks(10)
	var trip: AdventureTrip = main.trip
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	await _ticks(30)
	if main.bike != null and not main.bike.engine_on:
		main._ignition()
		for i in 480:
			await _ticks(1)
			if main.bike.engine_on and not main.bike.is_starting():
				break
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(10)
	check(main.bike.engine_on, "out on the road, its engine running")
	main._get_off()
	await _ticks(3)
	check(Roadside.parked(faithful) and Shed.idling(faithful) and view != null and IdlingEngine.of(view.model_of(faithful)) != null,
		"got off at the roadside with it running: it's stood there ticking over")
	Shed.request({"a": "roadside_push", "bike": faithful})
	await _ticks(5)
	check(main.bike != null and main.bike.pushing and not main.bike.engine_on and not Shed.idling(faithful),
		"pushing it: the engine's off")
	var pusher := main.bike.get_node_or_null("Pusher") as BikePusher
	check(pusher != null and pusher.is_visible_in_tree() and not main.bike.model._rider.visible,
		"pushing it, you're drawn walking beside it, not sat on it")
	Input.action_press("throttle", 1.0)
	var swung := 0.0
	for i in 240:
		await _ticks(1)
		var leg := pusher._body.get_node_or_null("LegR") as Node3D if pusher and pusher._body else null
		if leg:
			swung = maxf(swung, absf(leg.rotation.x))
	Input.action_release("throttle")
	check(swung > 0.1, "walking it along, the legs step (%.2f rad)" % swung)
	if pusher:
		var bike_xf: Transform3D = main.bike.model.global_transform
		var side: float = bike_xf.basis.x.dot(pusher.global_position - bike_xf.origin)
		check(side < -0.3, "on its left (%.2f m)" % side)
		var arm := pusher._body.get_node("ArmR") as Node3D
		var hand: Vector3 = arm.global_transform * (((RiderFigure.ARM_R["wrist"] - RiderFigure.ARM_R["shoulder"]) as Vector3).normalized() * BikePusher.ARM_REACH)
		var grip: Vector3 = main.bike.model.grip_point(-1.0)
		check(hand.distance_to(grip) < 0.12, "a hand on the left grip (%.2f m off)" % hand.distance_to(grip))
		var feet_y: float = pusher.global_position.y
		var ground_y: float = (bike_xf * Vector3(0.0, -main.bike.build.rear_radius, 0.0)).y
		check(absf(feet_y - ground_y) < 0.2, "feet on the ground (%.2f m)" % (feet_y - ground_y))
	main._get_off()
	await _ticks(3)
	check(main.bike == null and Roadside.parked(faithful) and not Shed.idling(faithful), "stood on its stand again, quiet")
	await _done(main)
