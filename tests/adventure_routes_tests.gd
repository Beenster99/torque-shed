extends RefCounted
## The paper map of an adventure's road (AdventureMap), run from tests/run_tests.gd: its _test_adv_routes_* functions
## hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Out on an adventure in the game: the paper map comes out once stopped (from its key or the Esc menu, not while
## riding) with the whole route and everyone on it, and folds away.
func test_map() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	Adventure.start(AdventurePlans.tour("dales"), 42)
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	check(trip.on_trip(), "out on an adventure")
	trip.jump(3000.0)
	for i in 45:
		await t.get_tree().physics_frame
	# Riding: no map.
	main.bike.speed = 10.0
	check(trip.map_reason() != "", "no map while riding along")
	main.bike.linear_velocity = Vector3.ZERO
	main.bike.speed = 0.0
	await t.get_tree().physics_frame
	main.menu.show_pause()
	check(main.menu._paper_map.visible and not main.menu._paper_map.disabled, "the Esc menu offers the paper map once stopped")
	main.menu._paper_map.pressed.emit()
	await t.get_tree().process_frame
	check(trip.map_open() and not main.menu.visible, "and it opens from there")
	var m: AdventureMap = trip._map
	await _frames(2)
	check(m._lines.size() > 100 and m._riders.size() == 1 and m._sites.any(func(e): return str(e["site"]["kind"]) == "finish"),
		"with the whole route (%d stretches, %d sites), the destination and you on it" % [m._lines.size(), m._sites.size()])
	m._input(_key_event("paper_map"))
	check(not trip.map_open(), "and it folds away")
	Shed.request({"a": "adventure_end"})
	for i in 10:
		await t.get_tree().physics_frame
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)


static func _key_event(action: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev
