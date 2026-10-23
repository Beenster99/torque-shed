extends RefCounted
## Buses to jump, the big and huge launch ramps with their landings, the steep kicker, and the
## yard kit drawn properly, run from tests/run_tests.gd (its _test_yard_items_* functions hand
## over to these). Also lays out the bus jump for tests/yard_shots.gd.

var t: Node   # the test runner: check(), get_tree()

## The kit this round added.
const NEW := ["ramp_kicker", "ramp_xl", "ramp_huge", "landing_xl", "landing_huge", "bus", "bus_row"]
## Somewhere well clear of anything else the tests build.
const AWAY := Vector3(6000.0, 0.0, -6000.0)


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _tree() -> SceneTree:
	return t.get_tree()


## In the catalogue: the buses are things to jump, the new ramps are jump ramps; the old small
## ramp stays alongside the new kicker, which is a different, steeper thing; the huge ramp's lip
## and the huge landing's top are bus height, so the three line up.
func test_catalogue() -> void:
	for id in NEW:
		var m := Equipment.get_model(id)
		check(not m.is_empty() and Equipment.is_yard(id) and bool(m.get("solid", false)) and str(m.get("desc", "")) != "",
			"%s is yard kit: %s, %s" % [id, str(m.get("name", "?")), Equipment.KIND_NAMES.get(str(m.get("kind", "")), "?")])
		check(Equipment.by_kind(Equipment.kind_of(id)).has(id), "the parts computer sells the %s" % str(m.get("name", id)).to_lower())
		check(Equipment.spec_line(id).contains("For the yard outside"), "and says it's for the yard (%s)" % Equipment.spec_line(id))
	check(Equipment.kind_of("bus") == "obstacle" and Equipment.kind_of("bus_row") == "obstacle", "buses are things to jump")
	var row: Vector3 = Equipment.get_model("bus_row")["size"]
	var bus: Vector3 = Equipment.get_model("bus")["size"]
	check(is_equal_approx(row.z, bus.z * 5.0) and row.x == bus.x and row.y == YardKit.BUS_HEIGHT,
		"the row is five buses side by side, %.1f m across, %.1f m high" % [row.z, row.y])
	var kicker := YardKit.lip_angle("ramp_kicker")
	var small := YardKit.lip_angle("ramp_small")
	check(not Equipment.get_model("ramp_small").is_empty() and kicker > 33.0 and kicker < 45.0 and small < 18.0,
		"the old small ramp is kept (a %.0f degree lip); the kicker is steep (%.0f degrees) and short (%.1f m)" % [small, kicker, Equipment.get_model("ramp_kicker")["size"].z])
	check(Equipment.get_model("ramp_kicker")["name"] != Equipment.get_model("ramp_small")["name"], "and they go by different names")
	var heights := ["ramp_large", "ramp_xl", "ramp_huge"].map(func(id): return float(Equipment.get_model(id)["size"].y))
	check(heights[0] < heights[1] and heights[1] < heights[2], "big and huge launch ramps, taller than the large one %s" % str(heights))
	check(is_equal_approx(YardKit.deck_height("ramp_huge", -4.5), YardKit.BUS_HEIGHT) and is_equal_approx(YardKit.deck_height("landing_huge", -6.5), YardKit.BUS_HEIGHT),
		"the huge ramp's lip and the huge landing's top are bus height")
	for pair in [["ramp_xl", "landing_xl"], ["ramp_huge", "landing_huge"]]:
		var a: Vector3 = Equipment.get_model(pair[0])["size"]
		var b: Vector3 = Equipment.get_model(pair[1])["size"]
		check(is_equal_approx(a.y, b.y) and b.z > a.z and YardKit.lip_angle(pair[0]) > 15.0 and YardKit.lip_angle(pair[0]) < 26.0,
			"the %s has its own landing, as high and longer (%.1f m vs %.1f m), off a %.0f degree lip" % [Equipment.get_model(pair[0])["name"].to_lower(), b.z, a.z, YardKit.lip_angle(pair[0])])


## Bought from the parts computer, each is left in the yard's drop-off, can be taken hold of,
## pushed somewhere else and put down there, and scrapped.
func test_buy_place() -> void:
	Shed.start_new("Tester", 22)
	var me := Shed.me()
	for id in NEW:
		var n := Shed.furniture.size()
		var why := Shed.check(me, {"a": "order_furniture", "model": id})
		Shed.request({"a": "order_furniture", "model": id})
		var fid: int = Shed.furniture.keys().max()
		var f: Dictionary = Shed.furniture[fid]
		var at: Vector3 = (f["xf"] as Transform3D).origin
		check(why == "" and Shed.furniture.size() == n + 1 and f["model"] == id and WorldYard.DROP_OFF.grow(7.0).has_point(Vector2(at.x, at.z)),
			"the %s is ordered and left in the yard (%s %s)" % [Equipment.get_model(id)["name"].to_lower(), why, str(at)])
		check(Shed.check(me, {"a": "grab", "furniture": fid}) == "", "you can take hold of it")
		Shed.request({"a": "grab", "furniture": fid})
		var to := Transform3D(Basis(Vector3.UP, 0.5), Vector3(20.0, 0.0, -40.0))
		Shed.request({"a": "move_furniture", "furniture": fid, "xf": to})
		Shed.request({"a": "release", "furniture": fid, "xf": to})
		check(Shed.furniture[fid]["xf"] == to and int(Shed.furniture[fid]["mover"]) == 0, "push it across the yard and put it down there")
		Shed.request({"a": "scrap", "furniture": fid})
		check(not Shed.furniture.has(fid), "and scrap it")


## Every piece of yard kit is drawn as one mesh shared by every copy of it, a few materials
## each, and its collision sits on what's drawn: rays down on the deck of every ramp and the
## tabletop hit the collision where they hit the drawing, as do the tops of the buses, walls
## and the rest; markers have none, so you ride through them.
func test_fit() -> void:
	var models: Array = []
	for kind in Equipment.YARD_KINDS:
		models.append_array(Equipment.by_kind(kind))
	var root := Node3D.new()
	t.add_child(root)
	var views := {}
	for i in models.size():
		var v := Node3D.new()
		v.position = AWAY + Vector3((i % 6) * 18.0, 0.0, (i / 6) * 18.0)
		v.rotation.y = 0.3 * i
		root.add_child(v)
		YardKit.build(v, models[i])
		views[models[i]] = v
	var again := Node3D.new()
	root.add_child(again)
	YardKit.build(again, "bus_row")
	await _tree().physics_frame
	await _tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	check((again.get_node("Kit") as MeshInstance3D).mesh == (views["bus_row"].get_node("Kit") as MeshInstance3D).mesh,
		"two of the same are drawn with the same mesh")
	var most := 0
	for id in models:
		most = maxi(most, (views[id].get_node("Kit") as MeshInstance3D).mesh.get_surface_count())
	check(most <= 16, "every piece is one mesh of at most %d materials" % most)
	var worst := {}
	for id: String in models:
		var v: Node3D = views[id]
		var m := Equipment.get_model(id)
		var size: Vector3 = m["size"]
		var tri := ((v.get_node("Kit") as MeshInstance3D).mesh as ArrayMesh).generate_triangle_mesh()
		var spots: Array[Vector3] = []
		if m.has("profile"):
			var hw := YardKit.deck_half_width(id) - 0.12
			for i in 25:
				for x in [-hw, 0.0, hw]:
					spots.append(Vector3(x, 0.0, size.z * 0.5 - 0.05 - (size.z - 0.1) * i / 24.0))
		elif id in ["bus", "bus_row"]:
			for b in roundi(size.z / YardKit.BUS_WIDTH):
				for x in [-3.0, 0.0, 3.0]:
					spots.append(Vector3(x, 0.0, -size.z * 0.5 + YardKit.BUS_WIDTH * (b + 0.5)))
		else:
			spots.append(Vector3(0.55, 0.0, 0.0) if id == "hay_bales" else Vector3.ZERO)
		var off := 0.0
		var missed := 0
		for s in spots:
			var top := Vector3(s.x, size.y + 2.0, s.z)
			var drawn: Dictionary = tri.intersect_ray(top, Vector3.DOWN)
			var q := PhysicsRayQueryParameters3D.create(v.global_transform * top, v.global_transform * Vector3(s.x, -0.5, s.z), 1)
			var hit := space.intersect_ray(q)
			if not m.get("solid", false):
				if not hit.is_empty():
					missed += 1
				continue
			if hit.is_empty() or drawn.is_empty():
				missed += 1
				continue
			var hy := (v.global_transform.affine_inverse() * (hit["position"] as Vector3)).y
			off = maxf(off, absf(hy - (drawn["position"] as Vector3).y))
		worst[id] = off
		var limit := 0.004 if m.has("profile") else 0.08
		check(missed == 0 and off <= limit, "%s: the collision sits on what's drawn (within %.1f cm at %d points%s)" % [id, off * 100.0, spots.size(),
			", nothing to hit: ride through it" if not m.get("solid", false) else ""])
	root.queue_free()


## The decks ride smoothly: each leaves the ground level, never steps or kinks along its length
## (the slope changes by under a couple of degrees every few centimetres), and the lip is the
## top of a straight face with nothing standing proud of it. Where kit is meant to meet, it
## meets level: the bus roofs, the huge ramp's lip and the huge landing's flat top.
func test_smooth() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var models := []
	for id in Equipment.MODELS:
		if Equipment.get_model(id).has("profile"):
			models.append(id)
	var views := {}
	for i in models.size():
		var v := Node3D.new()
		v.position = AWAY + Vector3(i * 20.0, 0.0, 200.0)
		root.add_child(v)
		YardKit.build(v, models[i])
		views[models[i]] = v
	await _tree().physics_frame
	await _tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	for id: String in models:
		var v: Node3D = views[id]
		var size: Vector3 = Equipment.get_model(id)["size"]
		var hs: Array[float] = []
		var step := 0.01
		var n := floori(size.z / step)
		for i in n + 1:
			var z := size.z * 0.5 - 0.004 - i * (size.z - 0.008) / n
			var from := v.global_position + Vector3(0.3, size.y + 1.0, z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (size.y + 2.0), 1))
			hs.append((hit["position"] as Vector3).y - v.global_position.y if not hit.is_empty() else -1.0)
		var jump := 0.0
		var kink := 0.0
		var w := 5   # slopes over 5 cm
		for i in range(w, hs.size() - w, 1):
			var before := atan2(hs[i] - hs[i - w], w * step)
			var after := atan2(hs[i + w] - hs[i], w * step)
			kink = maxf(kink, absf(after - before))
		for i in hs.size() - 1:
			jump = maxf(jump, absf(hs[i + 1] - hs[i]))
		var toe := atan2(hs[w] - hs[0], w * step)
		var steepest := deg_to_rad(maxf(YardKit.lip_angle(id), 35.0))
		check(hs.min() >= 0.0 and hs[0] < 0.01 and absf(toe) < deg_to_rad(3.0), "%s leaves the ground level (%.1f cm, %.1f degrees at the toe)" % [id, hs[0] * 100.0, rad_to_deg(toe)])
		check(jump < tan(steepest) * step + 0.002 and kink < deg_to_rad(2.5),
			"%s: no steps or kinks along the deck (biggest step %.1f mm a cm, slope changes %.1f degrees in 5 cm at most)" % [id, jump * 1000.0, rad_to_deg(kink)])
		var prof := str(Equipment.get_model(id)["profile"])
		if prof in ["launch", "kicker"]:
			var lip := hs[hs.size() - 2]
			check(hs.max() <= size.y + 0.002 and absf(lip - size.y) < 0.02 and hs[hs.size() - 3] < lip,
				"%s: the lip's the top of the face, nothing proud of it (%.3f m, ramp %.2f m)" % [id, hs.max(), size.y])
	# The bus jump's joins: lip, roofs and landing all at bus height, the landing flat on top.
	var bus := Node3D.new()
	bus.position = AWAY + Vector3(0.0, 0.0, 300.0)
	root.add_child(bus)
	YardKit.build(bus, "bus_row")
	await _tree().physics_frame
	var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(bus.global_position + Vector3(0.0, 5.0, 0.0), bus.global_position + Vector3(0.0, -1.0, 0.0), 1))
	var flat := YardKit.deck_height("landing_huge", -6.4) - YardKit.deck_height("landing_huge", -5.6)
	check(not roof.is_empty() and absf((roof["position"] as Vector3).y - bus.global_position.y - YardKit.BUS_HEIGHT) < 0.002
		and absf(flat) < 0.01, "the buses' roofs are level with the huge ramp's lip and the huge landing's flat top (%.2f m)" % [
		(roof["position"] as Vector3).y - bus.global_position.y if roof else -1.0])
	root.queue_free()


## A bike ridden hard up the huge launch ramp flies over the row of buses and lands on the huge
## landing ramp beyond, and rides away.
func test_bus_jump() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var ground := TestGround.new(600.0)
	ground.position = AWAY + Vector3(0.0, 0.0, 600.0)
	root.add_child(ground)
	var line := lay_bus_jump(AWAY + Vector3(-40.0, 0.0, 600.0))
	for piece: Array in line["pieces"]:
		var v := Node3D.new()
		root.add_child(v)
		v.global_transform = piece[1]
		YardKit.build(v, piece[0])
	var bike := Bike.new()
	bike.setup(BikeBuild.new())
	root.add_child(bike)
	await _tree().physics_frame
	var got := await ride_jump(bike, line)
	check(got["lip_speed"] > 12.0, "up the huge ramp at %.0f km/h" % (got["lip_speed"] * 3.6))
	check(got["over_buses"] and got["clear"] > 0.3, "and over the row of buses (%.1f m above the roofs at the lowest)" % got["clear"])
	check(got["landed"] == "landing", "landing on the huge landing ramp (%s, %.1f m past the lip)" % [got["landed"], got["landed_at"]])
	check(not got["crashed"] and got["end_speed"] > 3.0, "and riding away (%.0f km/h, %s)" % [got["end_speed"] * 3.6, "crashed" if got["crashed"] else "upright"])
	root.queue_free()


## The bus jump laid out from `at`, ridden towards +x: the huge launch ramp, a metre's gap, the
## row of buses, and the huge landing ramp butted up against their far side. {pieces: [[model,
## transform]], lip: the top of the lip, buses: [near x, far x], landing: [near x, far x]}.
static func lay_bus_jump(at: Vector3) -> Dictionary:
	var east := Basis(Vector3.UP, -PI * 0.5)    # ridden heading +x
	var west := Basis(Vector3.UP, PI * 0.5)
	var ramp: Vector3 = Equipment.get_model("ramp_huge")["size"]
	var row: Vector3 = Equipment.get_model("bus_row")["size"]
	var land: Vector3 = Equipment.get_model("landing_huge")["size"]
	var lip_x := at.x + ramp.z * 0.5
	var bus_x := lip_x + 1.0 + row.z * 0.5
	var land_x := bus_x + row.z * 0.5 + land.z * 0.5
	return {"pieces": [["ramp_huge", Transform3D(east, at)], ["bus_row", Transform3D(east, Vector3(bus_x, at.y, at.z))],
		["landing_huge", Transform3D(west, Vector3(land_x, at.y, at.z))]],
		"lip": Vector3(lip_x, at.y + ramp.y, at.z), "buses": [bus_x - row.z * 0.5, bus_x + row.z * 0.5],
		"landing": [land_x - land.z * 0.5, land_x + land.z * 0.5], "toe": at.x - ramp.z * 0.5}


## Rides `bike` at the jump laid out by lay_bus_jump: a run-up of `run_up` metres to
## `run_speed`, held all the way up the face, `air_throttle` in the air (a third holds the nose
## steady), then easing off after it lands. `each(frame, bike)` is called every physics frame
## (for pictures). What happened: {lip_speed, over_buses, clear (lowest height above the roofs
## while over them), landed ("landing", "roof", "ground" or ""), landed_at (m past the lip),
## pitch (degrees, nose up, as it landed), crashed, end_speed}.
func ride_jump(bike: Bike, line: Dictionary, each := Callable(), run_speed := 16.5, air_throttle := 0.3, run_up := 70.0) -> Dictionary:
	var lip: Vector3 = line["lip"]
	var z := lip.z
	bike.place(Vector3(float(line["toe"]) - run_up, lip.y - YardKit.BUS_HEIGHT + 0.05, z), -PI * 0.5)
	var out := {"lip_speed": 0.0, "over_buses": false, "clear": INF, "landed": "", "landed_at": 0.0, "crashed": false, "end_speed": 0.0}
	var flying := false
	var landed_frames := 0
	for i in 1800:
		var p := bike.global_position
		var on_ground := bike.wheels.any(func(w): return w["contact"])
		# Keep to the line down the middle of the ramps.
		var yaw_err := wrapf(bike.rotation.y + PI * 0.5, -PI, PI)
		bike.lean_input = clampf((p.z - z) * 0.25 + yaw_err * 1.2, -0.3, 0.3)
		if out["landed"] == "":
			if p.x < lip.x:
				# Holding the speed all the way up the face: it wants pulling up the ramp.
				bike.throttle = clampf((run_speed - bike.speed) * (0.6 if p.x < float(line["toe"]) else 2.0), 0.0, 1.0)
			else:
				bike.throttle = air_throttle
		else:
			bike.throttle = 0.0
			bike.rear_brake = 0.15 if landed_frames > 60 else 0.0
		if p.x < lip.x:
			out["lip_speed"] = bike.speed
		if p.x > lip.x + 0.5 and not on_ground:
			flying = true
		var buses: Array = line["buses"]
		if flying and p.x > float(buses[0]) and p.x < float(buses[1]):
			out["over_buses"] = true
			out["clear"] = minf(out["clear"], p.y - lip.y - bike.build.rear_radius)
		if flying and on_ground and out["landed"] == "":
			var landing: Array = line["landing"]
			out["landed_at"] = p.x - lip.x
			out["landed"] = "roof" if p.x < float(buses[1]) else ("landing" if p.x < float(landing[1]) else "ground")
			out["pitch"] = rad_to_deg(bike.pitch_angle)
		if out["landed"] != "":
			landed_frames += 1
		if bike.is_crashed:
			out["crashed"] = true
		if each.is_valid():
			await each.call(i, bike)
		await bike.get_tree().physics_frame
		if landed_frames > 240:
			break
	out["end_speed"] = bike.speed
	out["crashed"] = out["crashed"] or bike.is_crashed
	return out
