extends Node
## Two-process co-op check of hunger, thirst and tiredness on an adventure (see AdventureNeeds),
## run by tests/mp_test.sh after the adventure's own: a host and a client start the real game
## and the host starts an adventure. Each puts the same stand-in stops by the road (a bench for
## two, a counter, a double room). The client buys a bite at the counter and sits on the bench,
## and the host must see both; the host sits beside them, and both must see a picnic, and the
## host the client's figure sat down. Then both go to bed, the host calls it a night, and both
## must see the morning: rested, and the adventure saved to carry on. The host ends it after.

const SEED := 654
const KM := 20.0
const SITE_S := 60.0

var role := "host"
var main: Node
var notes := []


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Needs %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var on := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			Adventure.start(SEED, KM)
		return trip.on_trip() and main.bike != null and AdventureNeeds.all().size() == 2, 40.0)
	var me := Shed.me()
	var other := _other()
	var view: AdventureNeedsView = trip.needs
	var stubs := {}
	if on:
		stubs = _stubs(trip.world)
		await _until(func(): return main.bike != null and Time.get_ticks_msec() - main._mounted_at > 800, 5.0)
		main.bike.linear_velocity = Vector3.ZERO
		main._get_off()
	# The client buys a bite at the counter, then sits on the bench.
	var bought := false
	var seen_sat := false
	if on and role == "client":
		Progress.set_money(50)
		Shed.request({"a": "needs_debug", "food": 0.3})
		await _until(func(): return absf(AdventureNeeds.level(me, "food") - 0.3) < 0.01, 5.0)
		main.walker.place(_by(trip.world, SITE_S + 6.0))
		await _ticks(3)
		view.near = view.find_near()
		var why := view.buy(stubs["counter"], 0)
		bought = why == "" and Progress.money() == 46 and await _until(func(): return AdventureNeeds.level(me, "food") > 0.7, 5.0)
		main.walker.place(_by(trip.world, SITE_S))
		await _ticks(3)
		view.take(view.find_near())
		seen_sat = await _until(func(): return AdventureNeeds.sat(me), 5.0)
	elif on:
		bought = await _until(func(): return AdventureNeeds.level(other, "food") > 0.7, 20.0)
		seen_sat = await _until(func(): return AdventureNeeds.sat(other), 20.0)
		main.walker.place(_by(trip.world, SITE_S))
		await _ticks(3)
		view.take(view.find_near())
	notes.append("client bought and ate, seen=%s; client sat, seen=%s" % [bought, seen_sat])
	# Both sat on the bench: a picnic, as both see it; the host sees the client's figure sat down.
	var picnic := on and await _until(func(): return AdventureNeeds.sat_with(me).size() == 2 and AdventureNeeds.bonus(me) == AdventureNeeds.PICNIC_BONUS, 20.0)
	var posed := true
	if picnic and role == "host":
		posed = await _until(func():
			var rp = main.remotes.get(other)
			return is_instance_valid(rp) and rp._body_look.position.y < -0.6, 10.0)
	notes.append("picnic=%s, figure sat=%s" % [picnic, posed])
	# To bed: the client first, then the host, who calls it a night.
	var slept := false
	if picnic:
		if role == "client":
			await _wait(1500)
			view.stand_up()
			main.walker.place(_by(trip.world, SITE_S + 12.0))
			await _ticks(3)
			view.take(view.find_near())
		else:
			await _until(func(): return AdventureNeeds.abed(other), 20.0)
			view.stand_up()
			main.walker.place(_by(trip.world, SITE_S + 12.0))
			await _ticks(3)
			view.take(view.find_near())
			await _until(func(): return AdventureNeeds.all_abed(), 10.0)
			Shed.request({"a": "needs_sleep"})
		slept = await _until(func():
			return int(Shed.adventure.get("nights", 0)) == 1 and AdventureNeeds.level(me, "rest") == 1.0 and AdventureNeeds.level(other, "rest") == 1.0 \
				and not Shed.adventure_save.is_empty() and absf(Daylight.time_of_day() - AdventureNeeds.MORNING) < 0.3, 20.0)
	notes.append("slept till morning, rested and saved=%s (%s)" % [slept, Daylight.clock_text(Daylight.time_of_day())])
	# Home.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and not Adventure.active(), 25.0)
	var ok := on and bought and seen_sat and picnic and posed and slept and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP needs %s %s: on the adventure with meters=%s, %s, back home=%s" % ["PASS" if ok else "FAIL", role, on, ", ".join(notes), home])
	get_tree().quit(0 if ok else 1)


func _other() -> int:
	for p in Shed.crew:
		if int(p) != Shed.me():
			return int(p)
	return 0


## The stand-in stops, the same on both games: a bench for two, a counter and a double room.
func _stubs(w: AdventureWorld) -> Dictionary:
	var stub := load("res://tests/adventure_needs_tests.gd")
	var lat := -w.route.width_at_s(SITE_S) * 0.5 + 0.8
	return {
		"bench": stub.stub(w, AdventureNeeds.SEAT_GROUP, w.transform_at(SITE_S, lat).translated_local(Vector3(0.0, 0.45, 0.0)), 2, {"key": "bench"}),
		"counter": stub.stub(w, AdventureNeeds.COUNTER_GROUP, w.transform_at(SITE_S + 6.0, lat), 1, {"key": "counter"}),
		"bed": stub.stub(w, AdventureNeeds.BED_GROUP, w.transform_at(SITE_S + 12.0, lat), 2, {"key": "inn"}),
	}


## Where to stand to use the stop `s` along: a step back along the road from it.
func _by(w: AdventureWorld, s: float) -> Transform3D:
	return w.transform_at(s - 1.3, -w.route.width_at_s(s) * 0.5 + 0.8)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()
