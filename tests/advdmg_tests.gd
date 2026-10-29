extends RefCounted
## Simon: "Please stop any bike damage being incurred on an adventure, we shouldn't hear any
## rattles." Then: "remove the idea of a bike taking damage on an adventure tour", punctures and
## all. Out on an adventure the bike takes no harm: nothing wears, not even the tyres, nothing
## works loose, a drop breaks nothing, no tyre goes down, and it comes home as it set off
## (muddier and lighter on petrol). Run from tests/run_tests.gd:
## its _test_advdmg_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

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


## Everything about a bike's parts that is its health (not its muck, and not the petrol in its
## tank): slot -> {wear, rust, coat_q, slack, lube, fluid age, the shine's gloss and coat}.
static func _health(bike_id: int) -> Dictionary:
	var out := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0:
			continue
		var it: Dictionary = Shed.items[id]
		var h := {"wear": float(it.get("wear", 0.0)), "rust": float(it.get("rust", 0.0)), "coat_q": float(it.get("coat_q", -1.0)),
			"slack": float(it.get("slack", -1.0)), "lube": float(it.get("lube", -1.0))}
		if it.get("fluid") is Dictionary:
			h["age"] = float(it["fluid"].get("age", 0.0))
		if Detail.has(it):
			var d := Detail.data(it)
			h["shine"] = [Array(d["g"]), Array(d["c"])]
		out[slot] = h
	return out


## The slots whose health differs between two _health() readings.
static func _changed(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for slot in a:
		if not b.has(slot) or var_to_str(a[slot]) != var_to_str(b[slot]):
			out.append(slot)
	return out


## A bike made ready to show any harm: a bare-metal frame with no coat (it would flash-rust), a
## coated exhaust (the coat would wear thinner), drilled bars (they'd wear faster), and its
## chain, oil and brake fluid part used (they'd dry, stretch and age).
static func _ready_to_wear(bike_id: int) -> void:
	var frame := Shed.item_on(bike_id, "frame")
	if frame != 0:
		Shed.items[frame]["blast"] = {"c": 1.0}
		Shed.items[frame].erase("coat")
	var exhaust := Shed.item_on(bike_id, "exhaust")
	if exhaust != 0:
		Shed.items[exhaust]["coat"] = str(Shed.COATS.keys()[0])
		Shed.items[exhaust]["coat_q"] = 0.8
	var bars := Shed.item_on(bike_id, "handlebars")
	if bars != 0:
		Shed.items[bars]["lightened"] = true
	var chain := Shed.item_on(bike_id, "chain")
	if chain != 0:
		Shed.items[chain]["lube"] = 0.7
		Shed.items[chain]["slack"] = 32.0


## The shed's side, as the host applies every rider's ride stats: ten minutes of rough tracks on
## an adventure (mud and all) burn petrol, and nothing on the bike changes, the tyres neither; a crew mate's ride on the adventure (a client's stats, applied on the host) the same;
## the last stats arriving just after the host ends it too; a ride at the shed meanwhile, or
## after, wears a bike as it always did.
func test_shed_wear() -> void:
	Shed.start_new("Tester", 33)
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	_ready_to_wear(faithful)
	Adventure.start(Rides.plan(30.0), 12)
	Shed.request({"a": "adventure_join", "bike": faithful})
	check(Adventure.active() and Shed.riding(me) == faithful and Shed.adventure["riders"].has(me), "out on an adventure on Old Faithful")
	var before := _health(faithful)
	var front := Shed.item_on(faithful, "front_tyre")
	var rear := Shed.item_on(faithful, "rear_tyre")
	var tyres := [float(Shed.items[front]["wear"]), float(Shed.items[rear]["wear"])]
	var tank := Shed.item_on(faithful, "tank")
	var fuel := float(Shed.items[tank]["fluid"]["litres"])
	var dirt := float(Shed.items[Shed.item_on(faithful, "frame")]["dirt"])
	# Ten minutes at 90 km/h, a stats report a second, every metre of it muck and gravel.
	for i in 600:
		Shed.request({"a": "ride", "km": 0.025, "top_kmh": 95.0, "kmh": 90.0, "dirt_km": 0.06, "fly_km": 0.02, "fuel": 0.0015,
			"spin": 0.01, "adv": true})
	var after := _health(faithful)
	var changed := _changed(before, after)
	check(changed.is_empty(), "ten minutes of rough tracks on an adventure: nothing on the bike changes %s" % str(changed))
	check(float(Shed.items[front]["wear"]) == float(tyres[0]) and float(Shed.items[rear]["wear"]) == float(tyres[1]),
		"not even the tyres wear, burnout and all (%.4f, %.4f)" % [float(Shed.items[front]["wear"]) - float(tyres[0]), float(Shed.items[rear]["wear"]) - float(tyres[1])])
	check(float(Shed.items[tank]["fluid"]["litres"]) < fuel - 0.5, "petrol burnt (%.2f l)" % (fuel - float(Shed.items[tank]["fluid"]["litres"])))
	check(float(Shed.items[Shed.item_on(faithful, "frame")]["dirt"]) > dirt, "and it's muddier")
	check(Roadside.active(faithful).is_empty() and not Shed.bikes[faithful].has("faults"), "no fault to show for it")
	# A crew mate on the adventure: their game's stats, applied on the host.
	var mate := 2
	var theirs := 0
	for id in Shed.bikes:
		if int(id) != faithful and int(Shed.bikes[id].get("rider", 0)) == 0 and Shed.item_on(int(id), "engine") != 0 and Shed.item_on(int(id), "frame") != 0:
			theirs = int(id)
			break
	check(theirs != 0, "a second bike for a crew mate")
	if theirs == 0:
		Shed.stop()
		return
	_ready_to_wear(theirs)
	Shed.crew[mate] = (Shed.crew[me] as Dictionary).duplicate(true)
	Shed.crew[mate]["name"] = "Mate"
	Shed.crew[mate]["riding"] = theirs
	Shed.bikes[theirs]["rider"] = mate
	Shed.adventure["riders"][mate] = theirs
	var mate_before := _health(theirs)
	for i in 120:
		Shed._ride_apply(mate, {"a": "ride", "km": 0.03, "dirt_km": 0.06, "fuel": 0.002})
	var mate_changed := _changed(mate_before, _health(theirs))
	check(mate_changed.is_empty(), "a crew mate's ride on the adventure (applied on the host) harms nothing either %s" % str(mate_changed))
	# Someone who stayed at the shed: their ride wears their bike as ever.
	Shed.adventure["riders"].erase(mate)
	Shed._ride_apply(mate, {"a": "ride", "km": 3.0, "dirt_km": 1.0})
	check(not _changed(mate_before, _health(theirs)).filter(func(s): return not str(s).ends_with("_tyre")).is_empty(),
		"a ride at the shed meanwhile (not on the adventure) wears the bike as it always did")
	# Home: the adventure over, and the last second's stats arriving after it.
	before = _health(faithful)
	Shed.request({"a": "adventure_end"})
	Shed.request({"a": "ride", "km": 0.03, "dirt_km": 0.06, "fuel": 0.002, "adv": true})
	var home := _changed(before, _health(faithful))
	check(not Adventure.active() and home.is_empty(), "home again: nothing put on the bike for the adventure, nor by the last stats after it %s" % str(home))
	Shed.request({"a": "ride", "km": 3.0, "dirt_km": 1.0})
	check(not _changed(before, _health(faithful)).filter(func(s): return not str(s).ends_with("_tyre")).is_empty(),
		"and an ordinary ride after it wears the bike again")
	Shed.stop()


## In the game: a couple of minutes ridden along an adventure's road (the roughest stretch of
## it) with the engine running: no fault comes up, no rattle or chain slap starts, the parts are
## as they were, tyres and all; a drop breaks nothing; and it comes home in the same nick.
func test_ride() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var me := Shed.me()
	var faithful: int = t._bike_named("Old Faithful")
	_ready_to_wear(faithful)
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	# The tour of the Dales by its tracks, for some gravel to ride.
	var plan := AdventurePlans.tour("dales")
	plan["mode"] = "tracks"
	Adventure.start(AdventurePlans.clean(plan), 27)
	await _ticks(30)
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null and Shed.riding(me) == faithful, "out on an adventure on Old Faithful")
	if not trip.on_trip() or main.bike == null:
		await _done(main)
		return
	var w := trip.world
	# The roughest 3 km of the road that's there to ride.
	var end := w.route.total - 3100.0
	var best_s := 200.0
	var best_n := -1
	var s0 := 200.0
	while s0 < end:
		var n := 0
		for k in 30:
			if not str(w.route.surface_at_s(s0 + k * 100.0)) in ["tarmac", "concrete"]:
				n += 1
		if n > best_n:
			best_n = n
			best_s = s0
		s0 += 500.0
	trip.jump(best_s - w.distance_of(main.bike.global_position, "own"))
	await _frames(60)
	var before := _health(faithful)
	var tank := Shed.item_on(faithful, "tank")
	var fuel := float(Shed.items[tank]["fluid"]["litres"])
	main.bike.engine_on = true
	main.bike.gear = 3
	main.bike.fuel_litres = main.bike.build.fuel_capacity
	# Two minutes at 25 m/s, a frame at a time (the bike put along the road each frame).
	var speed := 25.0
	var step := speed / 120.0
	var s := best_s
	var rough := {}
	var faults_seen := []
	var frames := 120 * 120
	for f in frames:
		s = minf(s + step, w.route.total - 30.0)
		var xf := w.transform_at(s, -1.6)
		if main.bike == null:
			break
		main.bike.place(xf.origin, w.heading_at(s))
		main.bike.linear_velocity = xf.basis * Vector3(0, 0, -speed)
		main.bike.engine_on = true
		await t.get_tree().process_frame
		if main.bike == null:
			break
		rough[str(main.bike.surface)] = int(rough.get(str(main.bike.surface), 0)) + 1
		if not main._fault_seen.is_empty():
			faults_seen.append(var_to_str(main._fault_seen.keys()))
	await _ticks(Engine.physics_ticks_per_second * 2)   # the last stats in
	print("    ADVENTURE RIDE: %.1f km in %d frames, surfaces %s" % [(s - best_s) / 1000.0, frames, str(rough)])
	var off_road := 0
	for k in rough:
		if not str(k) in ["tarmac", "concrete"]:
			off_road += int(rough[k])
	check(s - best_s > 2500.0 and off_road > 0, "two minutes ridden along the road, %.1f km, some of it off the tarmac (%d frames)" % [(s - best_s) / 1000.0, off_road])
	check(faults_seen.is_empty() and Roadside.active(faithful).is_empty(), "no fault came up on the way %s" % str(faults_seen.slice(0, 3)))
	check(not main._fault_seen.has("chain_slack"), "no chain slap")
	var changed := _changed(before, _health(faithful))
	check(changed.is_empty(), "every part's health as it was, the tyres' too %s" % str(changed))
	check(float(Shed.items[tank]["fluid"]["litres"]) < fuel, "and the petrol burnt")
	# A drop: nothing snaps or works loose.
	main.bike.crash()
	await _ticks(30)
	check(Roadside.active(faithful).is_empty() and main._fault_seen.is_empty(), "a drop breaks nothing (%s)" % str(Roadside.active(faithful)))
	main._get_off()   # (crashed: back on its wheels)
	await _ticks(30)
	check(main.bike != null and not main.bike.is_crashed, "back up after the drop")
	if main.bike:
		for i in 2:
			check(main.bike.heat.pressure(i) > 1.0, "the %s tyre holds its air (%.2f bar)" % ["front" if i == 0 else "rear", main.bike.heat.pressure(i)])
	# Home in the same nick.
	before = _health(faithful)
	Shed.request({"a": "adventure_end"})
	await _ticks(Engine.physics_ticks_per_second * 2)
	var home := _changed(before, _health(faithful))
	check(not trip.on_trip() and home.is_empty(), "home: nothing done to the bike for the adventure %s" % str(home))
	await _done(main)


func _done(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
