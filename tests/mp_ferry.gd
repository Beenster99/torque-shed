extends Node
## Two-process co-op check of crossing on a ferry together (phase D round 3, D7), run by tests/mp_test.sh: a ride on
## the road network over the Corran Ferry (tests/fixtures/ferry: the two cells either side of Loch Linnhe, their
## features and the land along the road). Both games plan the same route over the crossing; the host rides onto the
## ramp first and must wait aboard (the ferry leaves only once the client's aboard too); both cross on the same boat,
## held on its deck, and land on the far side's road, the sat nav on along the route from there; each sees the other
## there. The host ends the ride.
##
## Also a rig: --role=solo rides it alone (the ferry leaves at once), and --place=iow, shodo or islesboro plans over the
## live world store instead (Southampton to East Cowes, Takamatsu to Shodoshima, Lincolnville to Islesboro in Maine).
## With --shots=DIR (solo, drawn: xvfb-run -a godot --rendering-driver opengl3 --path . res://tests/mp_ferry.tscn --
## --role=solo --shots=DIR) it saves pictures of each crossing: at the ramp, aboard, out on the water, the far side's
## name coming up, and landed.

const WORLD := "res://tests/fixtures/ferry"
const SEED := 4711
## Each place: its ferry's terminals (lat, lon), the crossing found as the link whose ends are nearest them.
const PLACES := {
	"corran": {"geo": [Vector2(56.7227, -5.2431), Vector2(56.7215, -5.2355)], "fixture": true},
	"iow": {"geo": [Vector2(50.8960, -1.4062), Vector2(50.7591, -1.2906)], "fixture": false},
	"shodo": {"geo": [Vector2(34.3540, 134.0489), Vector2(34.4890, 134.1729)], "fixture": false},
	"islesboro": {"geo": [Vector2(44.2805, -69.0057), Vector2(44.2809, -68.9429)], "fixture": false},
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
		boarded = await _until(func(): return trip.ferry.phase in ["aboard", "sailing"], 20.0)
		if role == "host":
			# (still at the ramp a while on, alone aboard and held: it waits for the client)
			await _wait(5.0)
			waited = trip.ferry.phase == "aboard" and _aboard() == 1 and trip.crew_hold()
		print("MP ferry note %s: aboard %s %s, waited for the crew %s" % [role, f["name"], boarded, waited])
		if not boarded:
			print("MP ferry note %s: not aboard: phase %s, sailing %s, near %s, speed %.2f, crew_hold %s" % [role, trip.ferry.phase,
				Shed.adventure.get("ferry", {}), trip.ferry._terminal_near(main.bike.global_position, FerryCrossing.BOARD_R),
				main.bike.speed, trip.crew_hold()])
			break
		# Across together: sailing, held on the deck, landed on the far side.
		var went := await _until(func(): return trip.ferry.phase == "sailing", 30.0)
		var kept := [true]
		# (once it's eased up the ramp to its slot, toward the stern: a big ship's is far from its middle)
		var reach := float((FerryScenery.BOATS[str(f["size"])] as Dictionary)["len"]) * 0.5 + 15.0
		var taken := {}
		var down := await _until(func():
			if shots != "" and trip.ferry.phase == "sailing":
				var total := FerryCrossing.total_of(trip.ferry.sailing)
				for k: Array in [["aboard", 2.0], ["water", total * 0.35], ["name", total - FerryCrossing.NAME_FROM + 4.0]]:
					if not taken.has(k[0]) and trip.ferry.t >= float(k[1]):
						taken[k[0]] = true
						_shot("%s_%d_%s" % [place, int(f["step"]), k[0]])
			if trip.ferry.phase == "sailing" and trip.ferry._ease >= 1.0 and main.bike != null:
				var boat := _boat(trip)
				if boat != null and main.bike.global_position.distance_to(boat.global_position) > reach:
					if kept[0]:
						print("MP ferry note %s: off the deck %.1f m at t %.1f" % [role,
							main.bike.global_position.distance_to(boat.global_position), trip.ferry.t])
					kept[0] = false
			return went and trip.ferry.phase == "" and main.bike != null and not main.bike.freeze, FerryCrossing.total_of({"seconds": float(f["seconds"])}) + 30.0)
		if shots != "":
			await _wait(2.0)
			_shot("%s_%d_landed" % [place, int(f["step"])])
		# (put off on the far side's road: up it from the terminal, clear of the water, one behind another)
		var far := trip.ferry.landing_xf(int(f["to"])).origin
		var dist: float = Vector2(main.bike.global_position.x - far.x, main.bike.global_position.z - far.z).length() if main.bike != null else INF
		down = down and dist < 20.0
		var nav := NetNav.of(trip.world)
		var on := await _until(func():
			nav.update(Vector2(main.bike.global_position.x, main.bike.global_position.z), Vector2(-sin(main.bike.rotation.y), -cos(main.bike.rotation.y)))
			return nav.status == "on_route" and nav.progress >= int(f["step"]), 5.0)
		print("MP ferry note %s: sailed %s, held on the deck %s, landed %s (%.1f m from where riders are put off there), sat nav on along the route %s (progress %d, step %d)" % [
			role, went, kept[0], down, dist, on, nav.progress, int(f["step"])])
		sailed = sailed and went
		held = held and kept[0]
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


## Puts the bike on the road leading to terminal junction `node`, a few metres short of it, and lets it roll on slowly.
func _to_ramp(trip: AdventureTrip, node: int) -> void:
	var p := trip.world.roads.net.region.node_pos[node]
	trip.world.roads.preload_round([p], 300.0)
	var xf := trip.ferry.landing_xf(node, 0.0, false)   # (just short of the road's end, whatever its height)
	main.bike.place(xf.origin, xf.basis.get_euler().y + PI)   # (facing the water)
	main.camera.snap()


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
