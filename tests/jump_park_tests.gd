extends RefCounted
## The Build Yard doubled: the jump park in its west wing and the bus jump and jump lines in its
## east wing (WorldYard.LINES), run from tests/run_tests.gd (its _test_jump_park_* functions hand
## over to these).

var t: Node   # the test runner: check(), get_tree()

## Somewhere well clear of anything else the tests build.
const AWAY := Vector3(-6000.0, 0.0, 6000.0)


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _tree() -> SceneTree:
	return t.get_tree()


## Twice the old yard, the wings either side of the old test area, every line's pieces on the
## slab and clear of each other, the old markings, the yard kit and the row of bikes brought home.
func test_layout() -> void:
	var slab: Rect2 = WorldYard.GROUND[0]
	check(is_equal_approx(slab.get_area(), 2.0 * 130.0 * 90.0) and slab.size == WorldYard.HALF * 2.0,
		"the yard is twice the size it was (%.0f by %.0f m)" % [slab.size.x, slab.size.y])
	check(WorldTerrain.HOME.encloses(slab.grow(5.0)), "and the flat ground round the shed takes it in")
	var old := Rect2(-65.0, -55.0, 130.0, 90.0)
	var keep_clear := {"u_turn": WorldYard.UTURN, "drop_off": WorldYard.DROP_OFF, "old yard": old,
		"lane": Rect2(WorldYard.START_X - 4.0, WorldYard.LANE_Z.x - 3.0, WorldYard.RUN_END - WorldYard.START_X + 4.0, WorldYard.LANE_Z.y - WorldYard.LANE_Z.x + 6.0),
		"bikes brought home": Rect2(Vector2(13.0, 21.0), Vector2(13.0, 12.0))}
	var pieces := WorldYard.fixed_kit()
	check(pieces.size() >= 25, "%d ramps, jumps and landings built in" % pieces.size())
	var why := []
	for i in pieces.size():
		var item: Array = pieces[i]
		var r := WorldYard.footprint(item[0], item[1])
		if not slab.grow(-1.0).encloses(r):
			why.append("%s off the slab" % item[0])
		for k in keep_clear:
			if (keep_clear[k] as Rect2).intersects(r) and not (k == "old yard" and item[0] in ["ramp_huge"]):
				# The bus jump's run-up comes across the old yard, its ramp just inside it.
				why.append("%s in the %s" % [item[0], k])
		for j in range(i + 1, pieces.size()):
			if r.grow(-0.05).intersects(WorldYard.footprint(pieces[j][0], pieces[j][1]).grow(-0.05)):
				why.append("%s on %s" % [item[0], pieces[j][0]])
		for k: Array in WorldYard.starting_kit():
			if r.grow(3.0).has_point(Vector2((k[1] as Transform3D).origin.x, (k[1] as Transform3D).origin.z)):
				why.append("%s by the %s" % [item[0], k[2]])
	check(why.is_empty(), "every piece is on the slab, apart, and clear of the old test area's markings and kit %s" % str(why))
	# Lines a bike's width either side of each other, and every whoop clear of the rest.
	var whoops_ok := true
	for at in WorldYard.whoops():
		for item: Array in pieces:
			whoops_ok = whoops_ok and not WorldYard.footprint(item[0], item[1]).intersects(
				Rect2(at.x - WorldYard.WHOOPS_WIDTH * 0.5 - 0.5, at.z - WorldYard.WHOOPS_LENGTH * 0.5, WorldYard.WHOOPS_WIDTH + 1.0, WorldYard.WHOOPS_LENGTH))
	check(whoops_ok and WorldYard.whoops().size() == WorldYard.WHOOPS_COUNT, "%d whoops, clear of the ramps" % WorldYard.whoops().size())
	var wings_ok := true
	for i in WorldYard.LINES.size():
		var inside := false
		for w in WorldYard.WINGS:
			inside = inside or w.has_point(Vector2(WorldYard.line_point(WorldYard.LINES[i], 30.0).x, WorldYard.line_point(WorldYard.LINES[i], 30.0).z))
		wings_ok = wings_ok and (inside or str(WorldYard.LINES[i]["name"]) == "BUS JUMP")
	check(wings_ok, "the lines are in the two new wings")


## Every launch ramp with a landing, ridden down its line at the speed painted on its run-up:
## the bike clears the gap (and the car, and the buses), lands on the landing and rides on.
func test_ride(names: Array) -> void:
	for i in WorldYard.LINES.size():
		var line: Dictionary = WorldYard.LINES[i]
		if not names.has(line["name"]):
			continue
		var got := await ride_line(i)
		var landed_ok := true
		for jump: Dictionary in got["jumps"]:
			landed_ok = landed_ok and jump["landed"] == "landing"
		if not got["jumps"].is_empty():
			check(landed_ok, "%s: every jump lands on its landing %s" % [line["name"], str(got["jumps"])])
		check(not got["crashed"] and got["reached"], "%s: and the bike rides the whole line without falling off (%s, %.0f km/h at the end)" % [
			line["name"], "crashed at %.1f m" % got["crashed_at"] if got["crashed"] else "upright", got["end_speed"] * 3.6])


## Rides line `index` of WorldYard.LINES, built out on its own patch of flat ground: up to the
## painted speed for each launch ramp, a third throttle in the air, then on to the next.
## {jumps: [{lip (km/h at the lip), landed ("landing", or what it came down on), at (m past the
## lip)}], crashed, crashed_at, reached (got past the last piece), end_speed}.
func ride_line(index: int, each := Callable()) -> Dictionary:
	var line: Dictionary = WorldYard.LINES[index]
	var root := Node3D.new()
	t.add_child(root)
	var ground := TestGround.new(400.0)
	ground.position = AWAY
	root.add_child(ground)
	var start := WorldYard.line_point(line, 0.0)
	var shift := AWAY - start
	for item: Array in WorldYard.fixed_kit():
		if int(item[2]) != index:
			continue
		var v := Node3D.new()
		root.add_child(v)
		v.global_transform = Transform3D((item[1] as Transform3D).basis, (item[1] as Transform3D).origin + shift)
		YardKit.build(v, item[0])
	if index == WorldYard.WHOOPS_LINE:
		for at in WorldYard.whoops():
			var w := _whoop()
			root.add_child(w)
			w.global_transform = Transform3D(Basis(Vector3.UP, float(line["yaw"])), at + shift)
	# The jumps: lip, speed and where the landing's high end and toe are, along the line.
	var jumps := []
	var pieces: Array = line["pieces"]
	var last_end := 0.0
	for k in pieces.size():
		var p: Array = pieces[k]
		var half := float(Equipment.get_model(p[0])["size"].z) * 0.5
		last_end = maxf(last_end, float(p[1]) + half)
		if p.size() < 4:
			continue
		for m in range(k + 1, pieces.size()):
			if str(pieces[m][2]) == "back":
				var lh := float(Equipment.get_model(pieces[m][0])["size"].z) * 0.5
				jumps.append({"lip_s": float(p[1]) + half, "speed": float(p[3]) / 3.6,
					"land": Vector2(float(pieces[m][1]) - lh, float(pieces[m][1]) + lh)})
				break
	var fwd := WorldYard.line_forward(line)
	var right := Basis(Vector3.UP, float(line["yaw"])) * Vector3.RIGHT
	var bike := Bike.new()
	bike.setup(BikeBuild.new())
	root.add_child(bike)
	bike.place(AWAY - fwd * 40.0 + Vector3.UP * 0.05, float(line["yaw"]))
	await _tree().physics_frame
	var out := {"jumps": [], "crashed": false, "crashed_at": 0.0, "reached": false, "end_speed": 0.0}
	var air := 0
	var jump := -1
	for i in 3600:
		var p := bike.global_position - AWAY
		var s := p.dot(fwd)
		var on_ground := bike.wheels.any(func(w): return w["contact"])
		var yaw_err := wrapf(bike.rotation.y - float(line["yaw"]), -PI, PI)
		bike.lean_input = clampf(p.dot(right) * 0.25 + yaw_err * 1.2, -0.3, 0.3)
		var target := 7.0
		for k in jumps.size():
			if float(jumps[k]["lip_s"]) > s - 0.5:
				target = jumps[k]["speed"]
				break
		if air > 4:
			bike.throttle = 0.3
			bike.front_brake = 0.0
			bike.rear_brake = 0.0
		else:
			bike.throttle = clampf((target - bike.speed) * 1.2, 0.0, 1.0)
			var over := bike.speed - target - 0.8
			bike.front_brake = clampf(over * 0.15, 0.0, 0.35)
			bike.rear_brake = clampf(over * 0.15, 0.0, 0.35)
		for k in jumps.size():
			if absf(s - float(jumps[k]["lip_s"])) < 0.3 and on_ground:
				jump = k
				jumps[k]["lip_speed"] = bike.speed
		if not on_ground:
			air += 1
		else:
			if air > 8 and jump >= 0 and out["jumps"].size() == jump:
				var land: Vector2 = jumps[jump]["land"]
				var what := "landing" if s > land.x - 0.3 and s < land.y else ("short" if s <= land.x - 0.3 else "long")
				out["jumps"].append({"lip": snappedf(float(jumps[jump].get("lip_speed", 0.0)) * 3.6, 0.1), "landed": what,
					"at": snappedf(s - float(jumps[jump]["lip_s"]), 0.1)})
			air = 0
		if bike.is_crashed:
			out["crashed"] = true
			out["crashed_at"] = s
			break
		if each.is_valid():
			await each.call(i, bike)
		await _tree().physics_frame
		if s > last_end + 8.0:
			out["reached"] = true
			break
	# A jump never reached counts as missed.
	while out["jumps"].size() < jumps.size():
		out["jumps"].append({"lip": 0.0, "landed": "never", "at": 0.0})
	out["end_speed"] = bike.speed
	root.queue_free()
	return out


## One whoop roller, solid as the yard builds it (without its look).
func _whoop() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt")
	body.add_child(WorldYard.whoop_shape())
	return body
