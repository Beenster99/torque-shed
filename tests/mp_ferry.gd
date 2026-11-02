extends Node
## Two-process co-op check of crossing on a ferry together (phase D round 3, D7), run by tests/mp_test.sh: a ride on
## the road network over the Corran Ferry (tests/fixtures/ferry: the two cells either side of Loch Linnhe, their
## features and the land along the road). Both games plan the same route over the crossing; the host rides up the
## ramp, over the bridge and onto the boat's deck first and must wait aboard (the ferry leaves only once the client's
## ridden aboard too); both cross on the same boat, carried on its deck (each drawn on it by the other's game), and
## ride off down the ramp at the far side and up the road, the sat nav on along the route from there; each sees the
## other there. The host ends the ride.
##
## Also a rig: --role=solo rides it alone (the ferry leaves at once, and halfway over the rider gets off, walks about
## the deck and gets back on), and --place=iow, shodo, islesboro, mallaig or holyhead plans over the live world store
## instead (Southampton to East Cowes, Takamatsu to Shodoshima, Lincolnville to Islesboro in Maine, Mallaig to Armadale,
## Holyhead to Dublin). With --shots=DIR (solo, drawn: xvfb-run -a godot --rendering-driver opengl3 --path .
## res://tests/mp_ferry.tscn -- --role=solo --shots=DIR) it saves pictures of each crossing: at the ramp, aboard, out
## on the water, the far side's name coming up, and landed.
##
## The bike's ridden by a Pilot (steering for the ramps, the bridge and the deck's lane at a jogging pace), so it's on
## and off under its own power, as a player rides it.

const WORLD := "res://tests/fixtures/ferry"
const SEED := 4711
## Each place: its ferry's terminals (lat, lon), the crossing found as the link whose ends are nearest them.
const PLACES := {
	"corran": {"geo": [Vector2(56.7227, -5.2431), Vector2(56.7215, -5.2355)], "fixture": true},
	"iow": {"geo": [Vector2(50.8960, -1.4062), Vector2(50.7591, -1.2906)], "fixture": false},
	"shodo": {"geo": [Vector2(34.3540, 134.0489), Vector2(34.4890, 134.1729)], "fixture": false},
	"islesboro": {"geo": [Vector2(44.2805, -69.0057), Vector2(44.2809, -68.9429)], "fixture": false},
	"mallaig": {"geo": [Vector2(57.0062, -5.8282), Vector2(57.0648, -5.8946)], "fixture": false},
	"holyhead": {"geo": [Vector2(53.3179, -4.6198), Vector2(53.3477, -6.1989)], "fixture": false},
}
## The pins are road junctions this far (m) from each terminal, on its side of the water.
const PIN_FROM := [2500.0, 3500.0]

var role := "host"
var place := "corran"
var main: Node
var shots := ""


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--place="):
			place = a.trim_prefix("--place=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots)
	var spec: Dictionary = PLACES[place]
	if bool(spec["fixture"]):
		CellStore.dir = WORLD
		CellStore.offline = true
		RealRegion.cell_dirs = [WORLD] as Array[String]
		HeightTiles.dirs = [WORLD.path_join("heights")] as Array[String]
		HeightTiles.offline = true
		HeightTiles.reset()
	Settings.player_name = "Ferry %s" % role
	AdventureWorld.network = true
	var plan := plan_for(place)
	var pack := AdventurePlans.pack_for(plan) if not plan.is_empty() else null
	var planned := pack != null and not pack.ferries.is_empty()
	print("MP ferry note %s: planned over the ferry %s (%s), %.1f km" % [role, planned, str(pack.ferries) if pack else "no plan",
		pack.max_km() if pack else 0.0])
	Shed.feedback.connect(func(text, _ok = true): print("MP ferry note %s: said %s" % [role, text]))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var solo := role == "solo"
	if solo:
		SaveGame.slot_override = "ferry_solo"
		main.menu.new_shed = true
		main._start_session()
	elif role == "host":
		main._host()
	elif role == "client":
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var crew := 1 if solo else 2
	var ok_start := planned and await _until(func():
		if role != "client" and Shed.crew.size() >= crew - (1 if solo else 0) and not Adventure.active() and not trip.on_trip():
			Shed.request({"a": "adventure_start", "plan": plan, "seed": SEED, "title": "Over the water"})
		return trip.on_trip() and main.bike != null and trip.ferry != null and (solo or _remote_bike() != null), 90.0)
	print("MP ferry note %s: on the ride %s" % [role, ok_start])
	if shots != "":
		# (a clear late morning, no opening film over it)
		for v in get_tree().root.find_children("*", "SplashVideo", true, false):
			(v as SplashVideo).skip()
		if Weather.current != null:
			Weather.current.change_to("clear", true)
		if Daylight.current != null:
			Daylight.current.set_time(11.0)
		Daylight.adventure_rate = 0.0
		Engine.max_physics_steps_per_frame = 30   # (a slow frame drawn mustn't slow the game's clock: the host's is real)
	# Each crossing in turn (Southampton's route takes the Cowes floating bridge first): the host to the ramp first,
	# the client a while after, so the host must wait aboard for it.
	var boarded := ok_start
	var waited := solo or role == "client"
	var sailed := ok_start
	var held := true
	var landed := ok_start
	var on_route := ok_start
	for f: Dictionary in (pack.ferries if ok_start else []):
		if not (boarded and landed):
			break
		if role == "client":
			# (once the host's aboard this crossing's boat and has waited a while: it must wait for us)
			await _until(func():
				var on := AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {}))
				return not on.is_empty() and str(on["id"]) == str(f["id"]) and (on["aboard"] as Dictionary).has(1), 60.0)
			await _wait(7.0)
		await _to_ramp(trip, int(f["from"]))
		if shots != "":
			await _wait(6.0)   # (the land and the scenery round the ramp in)
			_shot("%s_%d_ramp" % [place, int(f["step"])])
		# Ridden on: up the ramp, over the bridge out to the boat and down the lane onto its deck.
		var slot := 0 if role != "client" else 1
		var way_on: Array = await _way_on(trip, int(f["from"]), slot)
		boarded = await _ride(trip, way_on, func(): return trip.ferry.phase in ["aboard", "sailing"], 60.0)
		if role == "host":
			# (still at the ramp a while on, alone aboard: it waits for the client)
			await _wait(5.0)
			waited = trip.ferry.phase == "aboard" and _aboard() == 1
		print("MP ferry note %s: ridden aboard %s %s, waited for the crew %s" % [role, f["name"], boarded, waited])
		if not boarded:
			print("MP ferry note %s: not aboard: phase %s, sailing %s, bike %s, on the deck %s, speed %.2f" % [role, trip.ferry.phase,
				Shed.adventure.get("ferry", {}), main.bike.global_position, trip.ferry.on_deck(main.bike.global_position), main.bike.speed])
			break
		# Across together: sailing, carried on the deck (solo: off the bike and walking about it a while, then back on).
		var went := await _until(func(): return trip.ferry.phase == "sailing", 90.0)
		var kept := [true]
		var walked := [false]   # (solo: off the bike and about the deck; as a crew, the other drawn aboard)
		var taken := {}
		var bike_id: int = main.riding_id
		var docked := await _until(func():
			if shots != "" and trip.ferry.phase == "sailing":
				var total := FerryCrossing.total_of(trip.ferry.sailing)
				for k: Array in [["aboard", 2.0], ["water", total * 0.35], ["name", total - FerryCrossing.NAME_FROM + 4.0]]:
					if not taken.has(k[0]) and trip.ferry.t >= float(k[1]):
						taken[k[0]] = true
						_shot("%s_%d_%s" % [place, int(f["step"]), k[0]])
			var me: Node3D = main.bike if main.bike != null else main.walker
			if not solo and trip.ferry.phase == "sailing" and trip.ferry.t > FerryCrossing.PREP + 10.0 and not taken.has("mate"):
				# (the mate drawn aboard with us, out on the water: not left behind the boat by the network's delay)
				taken["mate"] = true
				var rb := _remote_bike()
				walked[0] = rb != null and trip.ferry.on_deck(rb.global_position, 0.3)
				print("MP ferry note %s: the other drawn on the deck out on the water %s (%s, boat %s)" % [role, walked[0],
					rb.global_position if rb != null else null, trip.ferry._xf.origin])
			if trip.ferry.phase == "sailing" and me != null and not trip.ferry.on_deck(me.global_position):
				if kept[0]:
					print("MP ferry note %s: off the deck at t %.1f (%s, boat %s)" % [role, trip.ferry.t, me.global_position, trip.ferry._xf.origin])
				kept[0] = false
			if solo and trip.ferry.phase == "sailing" and trip.ferry.t > FerryCrossing.PREP + 6.0 and not taken.has("off"):
				taken["off"] = true
				main.bike.front_brake = 1.0
				main._get_off()
				taken["off_at"] = trip.ferry.t
			if taken.has("off_at") and not taken.has("on") and trip.ferry.t > float(taken["off_at"]) + 8.0:
				taken["on"] = true
				var parked := Roadside.xf_in(trip.world, Roadside.spot_of(bike_id))
				walked[0] = main.walker != null and trip.ferry.on_deck(main.walker.global_position) and trip.ferry.on_deck(parked.origin) \
					and main.walker.is_on_floor()
				print("MP ferry note %s: walked about on deck %s (walker %s, the bike left at %s, boat %s)" % [role, walked[0],
					main.walker.global_position, parked.origin, trip.ferry._xf.origin])
				main._try_mount(bike_id)
			return trip.ferry.phase == "docked" and main.bike != null, FerryCrossing.total_of({"seconds": float(f["seconds"])}) + 60.0)
		if solo:
			await _wait(1.0)
			walked[0] = walked[0] and main.bike != null and trip.ferry.on_deck(main.bike.global_position)
			if main.bike != null:
				# (wheeled round to face the way off, as a rider would before getting back on: it's left as it was
				# parked, across the lane maybe, and there's no room to turn it ridden)
				var out_way: Vector3 = trip.ferry._xf.basis * Vector3(0, 0, trip.ferry.end_at(int(f["to"])))
				main.bike.place(main.bike.global_position - Vector3.UP * (main.bike.build.rear_radius + 0.05), atan2(-out_way.x, -out_way.z))
		# Ridden off down the ramp at the far side, over the bridge and up the road.
		await _wait(FerryCrossing.RAMP_MOVE + 0.5)
		var down := docked and await _ride(trip, _way_off(trip, int(f["to"])), func(): return is_instance_valid(trip) and trip.ferry != null \
			and trip.ferry.phase == "" and main.bike != null and not trip.ferry.carrying(main.bike.global_position), 60.0)
		if shots != "":
			await _wait(2.0)
			_shot("%s_%d_landed" % [place, int(f["step"])])
		var nav := NetNav.of(trip.world)
		var on := await _until(func():
			nav.update(Vector2(main.bike.global_position.x, main.bike.global_position.z), Vector2(-sin(main.bike.rotation.y), -cos(main.bike.rotation.y)))
			return nav.status == "on_route" and nav.progress >= int(f["step"]), 5.0)
		print("MP ferry note %s: sailed %s, kept on the deck %s, walked about it %s, tied up %s, ridden off %s, sat nav on along the route %s (progress %d, step %d)" % [
			role, went, kept[0], walked[0], docked, down, on, nav.progress, int(f["step"])])
		held = held and kept[0] and walked[0]
		sailed = sailed and went
		landed = landed and down
		on_route = on_route and on
	# Each sees the other on the far side.
	var seen := solo
	if landed and not solo:
		seen = await _until(func():
			var rb := _remote_bike()
			return rb != null and main.bike != null and rb.global_position.distance_to(main.bike.global_position) < 40.0 \
				and rb.global_position.distance_to(main.bike.global_position) > 2.0, 20.0)   # (near, not on top of each other)
		var rb := _remote_bike()
		print("MP ferry note %s: the other seen by us on the far side %s (%s m off)" % [role, seen,
			rb.global_position.distance_to(main.bike.global_position) if rb != null and main.bike != null else "no bike"])
		await _wait(4.0)
	var asked := [false]
	var home := solo or await _until(func():
		if role == "host" and Adventure.active() and not asked[0]:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and not Adventure.active(), 30.0)
	var ok := planned and ok_start and boarded and waited and sailed and held and landed and on_route and seen and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while not solo and Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP ferry %s %s: planned over the ferry=%s, on the ride=%s, aboard=%s, waited for the crew=%s, sailed=%s, held on the deck=%s, landed on the far side=%s, sat nav on=%s, seen there=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, planned, ok_start, boarded, waited, sailed, held, landed, on_route, seen, home])
	get_tree().quit(0 if ok else 1)


## The plan for `which` (PLACES): pins at road junctions either side of its ferry, the same on every machine.
static func plan_for(which: String) -> Dictionary:
	var spec: Dictionary = PLACES[which]
	var geo: Array = spec["geo"]
	var probe_id := RealRegion.cells_area_id(AdventureJourney.cells_for(geo))
	if not bool(spec["fixture"]):
		RealRegion.fetch_area(probe_id)   # (the live world store's cells: Simon's test places)
	var probe := RealRegion.get_region(probe_id)
	if probe == null:
		return {}
	var links := FerryLinks.of(probe)
	var ends: Array[Vector2] = []
	for g: Vector2 in geo:
		ends.append(probe.geo_to_xz(g.x, g.y))
	var i := -1
	var best_m := 1000.0
	for k in links.links.size():
		var pa := probe.node_pos[int(links.links[k]["a"])]
		var pb := probe.node_pos[int(links.links[k]["b"])]
		var m := minf(pa.distance_to(ends[0]) + pb.distance_to(ends[1]), pa.distance_to(ends[1]) + pb.distance_to(ends[0]))
		if m < best_m:
			best_m = m
			i = k
	if i < 0:
		return {}
	var pins_geo: Array = []
	for e in 2:
		var end := int(links.links[i]["a" if e == 0 else "b"])
		var best := -1
		var best_d := INF
		for n in probe.node_count():
			if probe.component[n] != probe.component[end] or probe.adjacent[n].size() < 3:
				continue
			var d := absf(probe.node_pos[n].distance_to(probe.node_pos[end]) - float(PIN_FROM[e]))
			if d < best_d:
				best_d = d
				best = n
		var g := probe.xz_to_geo(probe.node_pos[best].x, probe.node_pos[best].y)
		pins_geo.append(Vector2(g[0], g[1]))
	var cells := AdventureJourney.cells_for(pins_geo + geo)
	if not bool(spec["fixture"]):
		RealRegion.fetch_area(RealRegion.cells_area_id(cells))
	var frame := RealRegion.cell_middle(cells[0])
	var pins: Array = []
	for g: Vector2 in pins_geo:
		var xz := RealRegion.to_frame(frame, g.x, g.y)
		pins.append([snappedf(xz.x, 0.1), snappedf(xz.y, 0.1)])
	return AdventurePlans.clean({"region": RealRegion.cells_area_id(cells), "region_hash": "", "pins": pins,
		"names": ["This side", "The far side"], "mode": "main"})


## Puts the bike on the road leading to terminal junction `node`, a few metres short of it, facing the water, its
## engine running in first.
func _to_ramp(trip: AdventureTrip, node: int) -> void:
	var p := trip.world.roads.net.region.node_pos[node]
	trip.world.roads.preload_round([p], 300.0)
	var xf := trip.ferry.landing_xf(node, 0.0, false)   # (just short of the road's end, whatever its height)
	main.bike.place(xf.origin, xf.basis.get_euler().y + PI)   # (facing the water)
	main.camera.snap()
	main.bike.start_engine()
	await _until(func(): return main.bike.engine_on, 10.0)


## The way aboard at terminal `node` (region frame): to the road's end, the ramp's foot, its tip, out along the bridge to the boat's
## ramp, and down the lane onto the deck to slot `slot`'s row.
func _way_on(trip: AdventureTrip, node: int, slot: int) -> Array:
	await _until(func(): return trip.ferry._shown and int(trip.ferry._docked().x) == node, 20.0)
	var ramp := FerryScenery.ramp_of(trip.world.roads.net, trip.ferry.links, trip.ferry.link, node)
	var boat: Transform3D = trip.ferry._xf
	var size := trip.ferry._size()
	var end := trip.ferry.end_at(node)
	var hinge := FerryScenery.hinge(size, end)
	var pts: Array = [ramp["road"], ramp["foot"], ramp["tip"]]
	for local: Vector3 in [hinge + Vector3(0, 0, end * FerryScenery.FLAP_LEN), hinge, Vector3(FerryScenery.slot_at(size, slot).x, hinge.y, end * 2.0)]:
		pts.append(_region(trip, boat * local))
	print("MP ferry note %s: the way on: %s (boat at %s heading %s)" % [role, pts, _region(trip, boat.origin), boat.basis.get_euler().y])
	return pts


## The way off at terminal `node`: along the lane to the boat's ramp there, over the bridge, down the ramp and on up the
## road.
func _way_off(trip: AdventureTrip, node: int) -> Array:
	var ramp := FerryScenery.ramp_of(trip.world.roads.net, trip.ferry.links, trip.ferry.link, node)
	var boat: Transform3D = trip.ferry._xf
	var size := trip.ferry._size()
	var end := trip.ferry.end_at(node)
	var hinge := FerryScenery.hinge(size, end)
	var pts: Array = []
	for local: Vector3 in [hinge, hinge + Vector3(0, 0, end * FerryScenery.FLAP_LEN)]:
		pts.append(_region(trip, boat * local))
	var road: Vector3 = ramp["road"]
	var inland: Vector3 = road - (ramp["tip"] as Vector3)
	inland.y = 0.0
	pts.append_array([ramp["tip"], ramp["foot"], road, road + inland.normalized() * (FerryCrossing.QUAY_NEAR + 4.0)])   # (just clear: the road may bend)
	print("MP ferry note %s: the way off: %s (boat at %s heading %s)" % [role, pts, _region(trip, boat.origin), boat.basis.get_euler().y])
	return pts


func _region(trip: AdventureTrip, p: Vector3) -> Vector3:
	var xz := trip.world.route_xz(p)
	return Vector3(xz[0], p.y, xz[1])


## Rides the bike slowly through `points` (region frame) in turn until `done` (or `seconds` pass): leaning for each
## point ahead, a jogging pace on the throttle, stopping at the last.
func _ride(trip: AdventureTrip, points: Array, done: Callable, seconds: float) -> bool:
	var pilot := Pilot.new()
	pilot.trip = trip
	pilot.points = points
	pilot.role = role
	main.process_physics_priority = -2   # (Main reads the keys first, then the pilot has the bike: see Pilot)
	add_child(pilot)
	var ok := await _until(func(): return done.call() or (pilot.k >= points.size() and main.bike != null and absf(main.bike.speed) < 0.3 and done.call()), seconds)
	print("MP ferry note %s: rode %d of %d points, done %s, bike %s, phase \"%s\"" % [role, pilot.k, points.size(), ok, main.bike.global_position if main.bike else null, trip.ferry.phase if is_instance_valid(trip) and trip.ferry else "gone"])
	pilot.queue_free()
	if main.bike != null:
		main.bike.gear = Bike.NEUTRAL   # (left in gear at a tickover it creeps on along the deck, as a rider wouldn't)
	return ok


## Has the bike for the rig: run just after Main reads the keys (process_physics_priority), it steers it through its
## points at a walking pace.
class Pilot:
	extends Node
	var trip: AdventureTrip
	var points: Array = []
	var k := 0
	var role := ""
	var _t := 0.0
	var _started := false
	var _throttle := 0.0

	func _init() -> void:
		process_physics_priority = -1

	func _physics_process(delta: float) -> void:
		var bike: Bike = trip.main.bike
		if bike == null:
			return
		_t += delta
		if not bike.engine_on:
			bike.start_engine()
		elif bike.gear == Bike.NEUTRAL:
			bike.gear = 1
		var p := bike.global_position
		if not _started:
			# (already past the first points, say parked well up the deck: on from the first one ahead, not round back)
			_started = true
			while k < points.size() - 1:
				var here := Vector2(points[k].x, points[k].z)
				var next := Vector2(points[k + 1].x, points[k + 1].z)
				var xz := trip.world.route_xz(p)
				if Vector2(xz[0], xz[1]).distance_to(next) >= here.distance_to(next):
					break
				k += 1
		while k < points.size():
			var at := trip.world.to_local_pos(points[k].x, points[k].y, points[k].z)
			if Vector2(at.x - p.x, at.z - p.z).length() > 2.0:
				break
			k += 1
		if k >= points.size():
			bike.throttle = 0.0
			_throttle = 0.0
			bike.front_brake = 0.6
			bike.rear_brake = 0.6
			bike.lean_input = 0.0
			return
		var to: Vector3 = trip.world.to_local_pos(points[k].x, points[k].y, points[k].z) - p
		var fwd := -bike.global_basis.z
		var err := atan2(fwd.x * to.z - fwd.z * to.x, fwd.x * to.x + fwd.z * to.z)   # (+ the point's to the right)
		var want := 4.5 if absf(err) < 0.3 else (3.0 if absf(err) < 0.5 else 2.0)
		# (opened up and closed smoothly, as a rider would: snapped open from walking pace it spins the back tyre up a
		# steep slipway)
		_throttle = move_toward(_throttle, clampf(0.12 + (want - bike.speed) * 0.4, 0.0, 0.8), 1.5 * delta)
		bike.throttle = _throttle   # (its own: Main's just set the keys' none)
		bike.front_brake = clampf((bike.speed - want) * 0.3, 0.0, 0.5)
		bike.rear_brake = 0.0
		bike.lean_input = clampf(1.6 * err, -0.6, 0.6)
		if int(_t / 2.0) != int((_t - delta) / 2.0):
			print("MP ferry note %s: pilot point %d, v %.1f, err %.2f, at %s, to %s" % [role, k, bike.speed, err, p, to])
		if absf(bike.speed) < 0.3 and _t > 3.0 and int(_t / 5.0) != int((_t - delta) / 5.0):
			# (stuck: what's in the way)
			var q := PhysicsShapeQueryParameters3D.new()
			var ball := SphereShape3D.new()
			ball.radius = 1.2
			q.shape = ball
			q.transform = Transform3D(Basis.IDENTITY, bike.global_position - bike.global_basis.z * 0.9)
			q.exclude = [bike.get_rid()]
			q.collision_mask = 0xFFFFFFFF
			var hits := bike.get_world_3d().direct_space_state.intersect_shape(q, 8)
			print("MP ferry note %s: pilot stuck at point %d, %s, by %s (engine %s gear %d rpm %.0f throttle %.2f crashed %s)" % [role, k, p,
				hits.map(func(h): return "%s %s" % [h["collider"].get_class(), (h["collider"] as Node).get_path() if h["collider"] is Node else ""]),
				bike.engine_on, bike.gear, bike.rpm, bike.throttle, bike.is_crashed])


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_jpg(shots.path_join(name + ".jpg"), 0.85)
	var b: Node3D = main.bike
	var trip: AdventureTrip = main.trip
	var on := trip.world.roads.net.locate(b.global_position.x + trip.world.origin.x, b.global_position.z + trip.world.origin.z) if b != null else {}
	var boat := _boat(trip)
	print("MP ferry note %s: shot %s: bike %s visible %s, road y %s, boat %s, camera %s" % [role, name, b.global_position if b else null,
		b.is_visible_in_tree() if b else false, on.get("y", "-"), boat.global_position if boat else null, get_viewport().get_camera_3d().global_position])
	print("MP ferry note %s: saved %s" % [role, name])


func _aboard() -> int:
	return (AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {})).get("aboard", {}) as Dictionary).size()


func _boat(trip: AdventureTrip) -> Node3D:
	return trip.world.get_node_or_null("CrewFerry") as Node3D


func _local(trip: AdventureTrip, p: Vector2) -> Vector3:
	return trip.world.to_local_pos(p.x, main.bike.global_position.y if main.bike else 0.0, p.y)


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	await _until(func(): return Time.get_ticks_msec() > end, seconds + 1.0)


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0 * (6.0 if shots != "" else 1.0))   # (drawn, it's slow)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _remote_bike() -> Node3D:
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			return rp.bike
	return null
