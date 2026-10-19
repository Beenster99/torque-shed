extends RefCounted
## Out on an adventure with friends (Simon's v0.15.0 rides): a crash off the road puts you back
## on it, the sat nav says which way to go (and when you're facing the wrong way), how far ahead
## or behind the rest of the crew are along the road, getting off on a snowy mountainside leaves
## the bike stood there and you beside it, and a bike stays put with a menu up. Run from
## tests/run_tests.gd: its _test_adv_fix_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## The game with its session started and you on Old Faithful on an alpine adventure (the Alps:
## steep, with snow over the tops).
func _ride_out(km := 60.0) -> Node:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Adventure.start(91, km, "alpine")
	await _ticks(10)
	return main


func _done(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await t.get_tree().process_frame


## Jumps your bike to `s` along the road (the chunks there built) and stands it `lat` across.
func _stand_at(main: Node, s: float, lat: float) -> void:
	var trip: AdventureTrip = main.trip
	trip.jump(s - trip.world.distance_of(main.bike.global_position, "own"))
	await _ticks(5)
	var xf := trip.world.transform_at(s, lat)
	# Off the road the land's its own height: found from above.
	var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 80.0, xf.origin + Vector3.DOWN * 80.0, 1)
	var hit := trip.world.get_world_3d().direct_space_state.intersect_ray(q)
	main.bike.place((hit["position"] if hit else xf.origin) + Vector3.UP * 0.05, trip.world.heading_at(s))


## The first metre of snow on the road.
static func _snow_s(r: AdventureRoute) -> float:
	var s := 0.0
	while s < r.length:
		if r.surface_at_s(s) == "snow":
			return s
		s += 20.0
	return -1.0


## Crashing off the road: a few seconds later you and the bike are back on it, at the nearest
## point along it, on the left half and facing on to the destination. On the road you're picked
## up where you lie, as in town.
func test_crash() -> void:
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	var w := trip.world
	var r := w.route
	var s0 := 3000.0
	await _stand_at(main, s0, r.width_at_s(s0) * 0.5 + 14.0)
	await _ticks(120)
	var off_hit := w.locate_local(main.bike.global_position)
	check(absf(float(off_hit["lat"])) > r.width_at_s(s0) * 0.5 + 5.0, "stood off the road (%.1f m from the middle)" % float(off_hit["lat"]))
	check(w.back_on_road(main.bike.global_position) is Transform3D and w.back_on_road(w.transform_at(s0, -1.0).origin) == null,
		"off it there's a place back on the road; on it there isn't")
	# Turned round to face back the way, then off.
	main.bike.place(main.bike.global_position, w.heading_at(s0) + PI)
	await _ticks(30)
	main.bike.crash()
	await _ticks(60)
	check(main.bike.is_crashed, "crashed off the road")
	var waited := 0.5
	while main.bike.is_crashed and waited < Bike.AUTO_RESPAWN_TIME + 1.0:
		await _ticks(1)
		waited += 1.0 / 120.0
	var told: String = main.hud._message.text
	await _ticks(10)
	var hit := w.locate_local(main.bike.global_position)
	var fwd: Vector3 = -main.bike.global_transform.basis.z
	var along := w.transform_at(float(hit["s"]) + 5.0).origin - w.transform_at(float(hit["s"])).origin
	check(not main.bike.is_crashed and absf(float(hit["lat"])) < r.width_at_s(float(hit["s"])) * 0.5 and float(hit["lat"]) < 0.0,
		"a moment later it's back on the road, on the left half (%.1f m across)" % float(hit["lat"]))
	check(absf(float(hit["s"]) - s0) < 30.0, "at the nearest point along it (%.0f m on from where it went off)" % (float(hit["s"]) - s0))
	check(fwd.dot(along.normalized()) > 0.95, "facing on towards the destination")
	check(told.contains("Back on the road") and waited < Bike.AUTO_RESPAWN_TIME + 0.2, "after %.1f s, and it says so (%s)" % [waited, told])
	# The respawn key does the same.
	await _stand_at(main, s0 + 400.0, -r.width_at_s(s0 + 400.0) * 0.5 - 20.0)
	await _ticks(60)
	main.bike.crash()
	await _ticks(10)
	main.bike.respawn()
	hit = w.locate_local(main.bike.global_position)
	check(absf(float(hit["lat"])) < r.width_at_s(float(hit["s"])) * 0.5, "the respawn key puts it back on the road too")
	# On the road: picked up where it lies.
	await _stand_at(main, s0 + 800.0, -1.5)
	await _ticks(60)
	var lay: Vector3 = main.bike.global_position
	main.bike.crash()
	await _ticks(int((Bike.AUTO_RESPAWN_TIME + 0.5) * 120.0))
	check(not main.bike.is_crashed and main.bike.global_position.distance_to(lay) < 4.0,
		"a crash on the road: picked up where it lies (%.1f m)" % main.bike.global_position.distance_to(lay))
	await _done(main)
	# In town, as ever: where it lies.
	var bike := Bike.new()
	bike.respawn_at = func(_p): return null
	check(bike.respawn_at.call(Vector3.ZERO) == null, "and a respawn with nowhere else to go is where it lies")
	bike.free()


## The sat nav on an adventure: the way to the destination whichever way you face, an arrow to it
## relative to your heading, and facing back the way you came, a warning to turn round.
func test_satnav() -> void:
	var adv := AdventureWorld.new()
	adv.setup(42, 60.0)
	adv.focus = func(): return [adv.transform_at(20.0).origin]
	t.add_child(adv)
	var nav := Satnav.AdventureNav.new(adv)
	var at := adv.transform_at(1500.0)
	var fwd3 := -at.basis.z
	var on := Satnav.view_for(nav, at.origin, fwd3, 20.0)
	var back := Satnav.view_for(nav, at.origin, -fwd3, 20.0)
	check(not bool(on["guide"]["wrong_way"]) and absf(float(on["guide"]["turn"])) < deg_to_rad(45.0),
		"facing on: no warning, the arrow ahead (%.0f deg)" % rad_to_deg(float(on["guide"]["turn"])))
	check(bool(back["guide"]["wrong_way"]) and absf(float(back["guide"]["turn"])) > deg_to_rad(135.0),
		"turned round: the wrong way, the arrow behind you (%.0f deg)" % rad_to_deg(float(back["guide"]["turn"])))
	var r_on: PackedVector2Array = on["route"]
	var r_back: PackedVector2Array = back["route"]
	var end_on := adv.distance_of(Vector3(r_on[r_on.size() - 1].x, 0.0, r_on[r_on.size() - 1].y))
	var end_back := adv.distance_of(Vector3(r_back[r_back.size() - 1].x, 0.0, r_back[r_back.size() - 1].y))
	check(end_on > 1900.0 and end_back > 1900.0, "the way picked out runs on to the destination either way (to %.0f m, %.0f m)" % [end_on, end_back])
	var last := r_back[r_back.size() - 1]
	var rel := last - Vector2(at.origin.x, at.origin.z)
	check(rel.dot(Vector2(-fwd3.x, -fwd3.z)) < 0.0, "turned round, it's behind you on the heading-up map")
	var p_on: Array = (on["points"] as Array).map(func(q): return "%s %.0f" % [q["kind"], q["distance"]])
	var p_back: Array = (back["points"] as Array).map(func(q): return "%s %.0f" % [q["kind"], q["distance"]])
	check(p_on == p_back and (back["stops"] as Array).size() == (on["stops"] as Array).size(),
		"the fuel, the destination and the stops are the ones on the way, either way %s" % str(p_back))
	# Side on to the road, the arrow points along it (left or right of the heading).
	var side := Satnav.view_for(nav, at.origin, at.basis.x, 20.0)
	check(not bool(side["guide"]["wrong_way"]) and float(side["guide"]["turn"]) < -deg_to_rad(45.0),
		"side on, facing right across it: the arrow points left, along the way on (%.0f deg)" % rad_to_deg(float(side["guide"]["turn"])))
	# Drawn, both ways (the unit's screen and the HUD's).
	for v in [on, back]:
		var screen := SatnavScreen.new()
		screen.size = Vector2(KitModel.SCREEN_PX)
		t.add_child(screen)
		screen.show_view(v)
		await t.get_tree().process_frame
		check(screen.view == v, "the screen draws it")
		screen.queue_free()
	adv.queue_free()
	await t.get_tree().process_frame


## The rest of the crew: how far ahead or behind along the road (not as the crow flies), on the
## HUD, the sat nav and the paper map.
func test_friends() -> void:
	check(AdventureTrip.friend_text("Dave", 1234.0) == "Dave 1.2 km ahead" and AdventureTrip.friend_text("Sam", -304.0) == "Sam 300 m behind"
		and AdventureTrip.friend_text("Jo", 12.0) == "Jo with you", "Dave 1.2 km ahead, Sam 300 m behind, Jo with you")
	var was: String = Settings.units
	Settings.units = "imperial"
	check(AdventureTrip.friend_text("Dave", 3218.7) == "Dave 2.0 mi ahead" and AdventureTrip.friend_text("Sam", -100.0) == "Sam 110 yd behind",
		"in miles: %s, %s" % [AdventureTrip.friend_text("Dave", 3218.7), AdventureTrip.friend_text("Sam", -100.0)])
	Settings.units = was
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	var w := trip.world
	await _stand_at(main, 2000.0, -1.5)
	await _ticks(30)
	check(trip.friends().is_empty() and trip.crew_text() == "", "riding alone, nobody to say")
	# A mate along the road (a stand-in for the RemotePlayer: where they are and their name).
	var mate := _Mate.new()
	mate.at = w.transform_at(3250.0, 1.5).origin
	mate.player_name = "Dave"
	main.remotes[77] = mate
	Shed.crew[77] = {"name": "Dave"}
	var f := trip.friends()
	check(f.size() == 1 and absf(float(f[0]["ahead"]) - 1250.0) < 3.0, "Dave's 1250 m on along the road (%.0f)" % (float(f[0]["ahead"]) if f.size() else -1.0))
	check(trip.crew_text() == "Dave 1.3 km ahead", "the HUD: %s" % trip.crew_text())
	var v := Satnav.view_for(Satnav.AdventureNav.new(w), main.bike.global_position, -main.bike.global_transform.basis.z)
	check((v["friends"] as Array).size() == 1 and str(v["friends"][0]["name"]) == "Dave" and absf(float(v["friends"][0]["ahead"]) - 1250.0) < 3.0,
		"and the sat nav has him")
	await _ticks(40)
	check(trip._crew.visible and trip._crew.text.begins_with("Dave 1.") and trip._crew.text.ends_with("km ahead") and not trip._wrong.visible, "on the HUD, top right, and no wrong-way warning (%s, %s, %s)" % [trip._crew.visible, trip._crew.text, trip._wrong.visible])
	# Turned round on the road: the HUD says so too (sat nav or not).
	main.bike.place(main.bike.global_position, w.heading_at(2000.0) + PI)
	await _ticks(40)
	check(trip.wrong_way() and trip._wrong.visible and trip._wrong.text.contains("TURN AROUND"), "turned round: WRONG WAY: TURN AROUND on the HUD")
	main.bike.place(main.bike.global_position, w.heading_at(2000.0))
	await _ticks(40)
	check(not trip._wrong.visible, "and facing on again, it goes")
	mate.at = w.transform_at(1500.0, 1.5).origin
	check(trip.crew_text() == "Dave 500 m behind", "behind you: %s" % trip.crew_text())
	# Round a hairpin: just across the bend as the crow flies, a long way round by the road.
	var best := Vector3(0.0, 0.0, INF)   # s, metres along, crow
	var s := 2600.0
	while s < w.route.length - 2000.0 and best.z == INF:
		var me := w.transform_at(s).origin
		for d in range(400, 1600, 50):
			var there := w.transform_at(s + d).origin
			if Vector2(there.x - me.x, there.z - me.z).length() < float(d) * 0.5:
				best = Vector3(s, float(d), Vector2(there.x - me.x, there.z - me.z).length())
				break
		s += 100.0
	check(best.z < INF, "a hairpin: %.0f m round by the road, %.0f m across" % [best.y, best.z])
	if best.z < INF:
		await _stand_at(main, best.x, -1.5)
		await _ticks(10)
		mate.at = w.transform_at(best.x + best.y, 1.5).origin
		var hf := trip.friends()
		check(hf.size() == 1 and absf(float(hf[0]["ahead"]) - best.y) < 25.0, "Dave round it is %.0f m ahead by the road, not %.0f m as the crow flies" % [
			float(hf[0]["ahead"]) if hf.size() else -1.0, best.z])
	main.remotes.erase(77)
	Shed.crew.erase(77)
	mate.free()
	await _done(main)


class _Mate:
	extends Node3D
	var at := Vector3.ZERO
	var player_name := ""
	var bike = null
	var riding_bike := 0
	func world_position() -> Vector3:
		return at
	func shift_origin(d: Vector3) -> void:
		at -= d


## Getting off on the snow, on and off the road and across a mountainside: the bike stays stood
## where it was left, drawn for everyone, you're stood beside it (not dropped through the land
## below it), and pushing it works up and down the snowy slope at a walking pace.
func test_get_off() -> void:
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	var w := trip.world
	var r := w.route
	var faithful: int = t._bike_named("Old Faithful")
	var snow := _snow_s(r)
	check(snow > 0.0, "snow on the road over the top (%.1f km in)" % (snow / 1000.0))
	var view: RoadsideView = null
	for c in w.get_children():
		if c is RoadsideView:
			view = c
	# [m past the road's edge, what it is, how far from the bike you may end up, where along].
	# Across the mountainside 250 m into the snow the land where you step off is nearly two metres
	# above the ground under the bike: that's where Simon dropped through the land, left walking in
	# the wild with his bike gone. That slope (60 degrees) and a cutting's bank are too steep to
	# stand on, so you're stood on the road below the bike instead.
	for spot in [[0.0, "on the road", 2.5, 2400.0], [6.0, "across a steep mountainside, the land beside it well above it", 16.0, 250.0],
			[6.0, "up a cutting's bank", 16.0, 2550.0], [15.0, "well off it, on a slope you can stand on", 2.5, 2700.0],
			[2.0, "just off it, on the verge", 2.5, 2850.0]]:
		var s := snow + float(spot[3])
		var lat: float = 0.0 if float(spot[0]) == 0.0 else r.width_at_s(s) * 0.5 + float(spot[0])
		await _stand_at(main, s, lat)
		if float(spot[3]) == 250.0:
			# Come to rest there as it would ridden off the road: dropped onto the hillside.
			var xf := w.transform_at(s, lat)
			main.bike.place(xf.origin + Vector3.UP * 2.0, w.heading_at(s))
			await _ticks(240)
		await _ticks(30)
		main.bike.linear_velocity = Vector3.ZERO
		await _ticks(10)
		var where: Vector3 = main.bike.global_position
		var surf: String = "%s, crashed %s, %.1f m/s" % [main.bike.surface, main.bike.is_crashed, main.bike.speed]
		main._get_off()
		await _ticks(3)
		check(main.bike == null and Roadside.parked(faithful) and view._views.has(faithful), "%s (%s): off, it's stood at the roadside" % [spot[1], surf])
		await _ticks(240)
		var shown: Node3D = view._views[faithful]["node"] if view._views.has(faithful) else null
		var gap: float = shown.global_position.distance_to(main.walker.global_position) if shown else INF
		check(shown != null and shown.global_position.distance_to(where) < 1.0 and shown.is_visible_in_tree(), "%s: the bike's where it was left" % spot[1])
		var low := minf(where.y, r.height_at_s(s)) - 3.0
		check(gap < float(spot[2]) and main.walker.is_on_floor() and main.walker.global_position.y > low,
			"%s: two seconds on you're still by it, on your feet, not dropped through the land (%.1f m from it)" % [spot[1], gap])
		main._left_bike = 0
		main._try_mount(faithful)
		await _ticks(5)
	# Pushing it up and down the snowy slope, on foot.
	var steep := Vector2(0.0, snow)
	var s := snow
	while s < minf(snow + 4000.0, r.length - 100.0):
		var g := (r.height_at_s(s + 10.0) - r.height_at_s(s - 10.0)) / 20.0
		if r.surface_at_s(s) == "snow" and absf(g) > absf(steep.x):
			steep = Vector2(g, s)
		s += 10.0
	for dir in [1.0, -1.0]:
		await _stand_at(main, steep.y, -1.5)
		main.bike.place(main.bike.global_position, w.heading_at(steep.y) + (0.0 if dir > 0.0 else PI))
		await _ticks(120)
		main.bike.linear_velocity = Vector3.ZERO
		main._get_off()
		await _ticks(3)
		Shed.request({"a": "roadside_push", "bike": faithful})
		await _ticks(3)
		var up: bool = (dir > 0.0) == (steep.x > 0.0)
		var from: Vector3 = main.bike.global_position
		Input.action_press("throttle", 1.0)
		await _ticks(360)
		Input.action_release("throttle")
		var went: float = main.bike.global_position.distance_to(from)
		check(main.bike.pushing and went > 2.5 and absf(main.bike.speed) < Roadside.PUSH_SPEED + 0.4 and not main.bike.is_crashed,
			"pushed %s a %.0f%% snowy slope: %.1f m in 3 s at %.1f m/s" % ["up" if up else "down", absf(steep.x) * 100.0, went, main.bike.speed])
		await _ticks(90)
		var held: Vector3 = main.bike.global_position
		await _ticks(240)
		check(main.bike.global_position.distance_to(held) < 0.3, "let go of the throttle, it's held there, not rolling away (%.2f m)" % main.bike.global_position.distance_to(held))
		main._get_off()
		await _ticks(3)
		check(Roadside.parked(faithful), "and stood on its stand")
		main._left_bike = 0
		main._try_mount(faithful)
		await _ticks(5)
	# Should you ever drop through the land on foot all the same: stood back by the road.
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(10)
	main._get_off()
	await _ticks(3)
	var at := w.transform_at(steep.y, 0.0).origin
	main.walker.place(Transform3D(Basis(), at + Vector3.DOWN * 60.0))
	await _ticks(420)   # three and a half seconds of falling
	var back := w.locate_local(main.walker.global_position)
	check(main.walker.global_position.distance_to(at) < 8.0 and absf(float(back["lat"])) < r.width_at_s(steep.y) * 0.5 + 0.5,
		"fallen through the land on foot: put back on the road (%.1f m from it)" % main.walker.global_position.distance_to(at))
	await _ticks(60)
	check(main.walker.is_on_floor(), "on your feet there")
	await _done(main)


## A menu up on the bike: the game doesn't pause (alone or in co-op), so the bike's held where it
## is: not rolling down the hill, nor walking itself backwards on the held brake.
func test_menu_hold() -> void:
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	var r := trip.world.route
	var best := Vector2.ZERO
	var s := 200.0
	while s < 15000.0:
		var g := (r.height_at_s(s + 10.0) - r.height_at_s(s - 10.0)) / 20.0
		if absf(g) > absf(best.x):
			best = Vector2(g, s)
		s += 10.0
	await _stand_at(main, best.y, -1.5)
	await _ticks(120)
	for gear in [Bike.NEUTRAL, 1]:
		main.bike.gear = gear
		main.bike.linear_velocity = Vector3.ZERO
		await _ticks(10)
		var from: Vector3 = main.bike.global_position
		main.menu.show()
		await _ticks(600)
		check(main.bike.global_position.distance_to(from) < 0.02 and not main.bike.paddling,
			"%s on a %.0f%% hill, 5 s with the menu up: it stays put (%.3f m)" % ["in neutral" if gear == 0 else "in first", absf(best.x) * 100.0,
			main.bike.global_position.distance_to(from)])
		main.menu.hide()
		await _ticks(30)
		check(not main.bike.freeze, "menu down, it's let go")
	# On the flat in town the held brake used to walk it backwards (the paddle back).
	await _done(main)
	var flat: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(flat)
	await t.get_tree().process_frame
	flat._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	Shed.request({"a": "mount", "bike": t._bike_named("Old Faithful")})
	await _ticks(3)
	flat.bike.place(Vector3(0.0, 0.0, 140.0), 0.0)
	await _ticks(120)
	var at: Vector3 = flat.bike.global_position
	flat.menu.show()
	await _ticks(600)
	check(flat.bike.global_position.distance_to(at) < 0.02 and not flat.bike.paddling, "in town too: it doesn't roll back (%.3f m)" % flat.bike.global_position.distance_to(at))
	# At speed it brakes to a stop first, then holds.
	flat.menu.hide()
	await _ticks(10)
	flat.bike.linear_velocity = -flat.bike.global_transform.basis.z * 8.0
	flat.menu.show()
	await _ticks(600)
	check(absf(flat.bike.speed) < 0.05 and flat.bike.freeze, "riding along when it opens: brakes to a stop and holds there")
	flat.menu.hide()
	await _ticks(5)
	await _done(flat)
