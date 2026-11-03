extends RefCounted
## The notice that the crew's road is planned (RouteReady, HUD.route_notice), run from tests/run_tests.gd: its
## _test_route_ready_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## When a notice goes up: only for a plan seen being worked out for a while, once, and a failed one says why.
func test_rules() -> void:
	var plan := AdventurePlans.tour("shodoshima", 3)
	check(not plan.is_empty(), "a plan to watch")
	var done := {"ok": true, "error": "", "pack": null}
	var w := RouteReady.new()
	# Ready as it was first seen (planned before, or quick): nothing.
	check(w.watch(plan, done, 1000).is_empty(), "no notice for a plan that was ready at once")
	check(w.watch(plan, done, 90000).is_empty(), "nor later on")
	# Worked out quickly while you watched: nothing.
	w = RouteReady.new()
	w.watch(plan, {}, 0)
	check(w.watch(plan, done, RouteReady.QUIET_MS - 1000).is_empty(), "no notice for a quick plan")
	# Worked out over minutes: one notice, naming where it goes, then quiet.
	w = RouteReady.new()
	w.watch(plan, {}, 0)
	check(w.watch(plan, {}, 300000).is_empty(), "nothing while it's still being worked out")
	var n := w.watch(plan, done, 600000)
	check(str(n.get("title", "")) == "ROUTE READY", "a notice once it's planned: %s" % str(n))
	check(bool(n.get("ok", false)), "good news")
	check(str(n.get("line", "")).contains(str(plan["names"][-1])), "it names where the road goes: %s" % str(n.get("line", "")))
	check(str(n.get("line", "")).contains("{menu}"), "and says how to get to the planner")
	check(w.watch(plan, done, 601000).is_empty(), "only once")
	# The map still being finished (planned again shortly) is still on its way.
	w = RouteReady.new()
	w.watch(plan, {}, 0)
	check(w.watch(plan, {"ok": false, "error": AdventurePlans.FINISHING, "retry": true, "map": true}, 200000).is_empty(),
		"no notice while the map is still being finished")
	var bad := w.watch(plan, {"ok": false, "error": "No road joins those pins."}, 400000)
	check(str(bad.get("title", "")) == "ROUTE COULDN'T BE PLANNED" and not bool(bad.get("ok", true)), "a failed plan says so: %s" % str(bad))
	check(str(bad.get("line", "")).contains("No road joins those pins."), "and why")
	# A new plan (a pin moved) is watched afresh; none at all forgets it.
	var other := AdventurePlans.tour("shodoshima", 4)
	check(w.watch(other, done, 500000).is_empty(), "a new plan, ready at once: nothing")
	check(w.watch({}, {}, 500100).is_empty() and w.watching == "", "no plan: nothing watched")


## In the game: the crew's plan being worked out at the shed puts the notice up on the HUD when it's done, without the
## planner open (here on foot, away from the TVs).
func test_in_game() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var tour := AdventurePlans.tour("shodoshima", 3)
	AdventurePlans.wait_all()
	AdventurePlans.forget(tour)
	var pins: Array = []
	for i in (tour["pins"] as Array).size():
		pins.append({"x": float(tour["pins"][i][0]), "z": float(tour["pins"][i][1]), "name": str(tour["names"][i])})
	Shed.journey = {"region": "shodoshima", "pins": pins, "mode": str(tour["mode"])}
	var plan := AdventureJourney.plan_of(Shed.journey)
	check(AdventurePlans.key(plan) == AdventurePlans.key(tour), "the journey is the tour's plan")
	var trip: AdventureTrip = main.trip
	trip._route_timer = 0.0   # (looked at on the next frame)
	for i in 5:
		await t.get_tree().process_frame
	check(main.hud.route_showing() == "", "no notice yet")
	# (watched being worked out: as if it had been at it for minutes)
	check(trip.route_ready.watching == AdventurePlans.key(plan), "the trip watches the crew's plan")
	trip.route_ready.since -= RouteReady.QUIET_MS * 4
	var waited := 0
	while main.hud.route_showing() == "" and waited < 3000:
		await t.get_tree().process_frame
		waited += 1
	check(not AdventurePlans.result(plan).is_empty(), "the plan was worked out")
	check(main.hud.route_showing() == "ROUTE READY", "the notice is up: '%s'" % main.hud.route_showing())
	AdventurePlans.wait_all()
	main.queue_free()
	await t.get_tree().process_frame
