extends RefCounted
## Air and oil filters serviced with the engine in the frame, run from tests/run_tests.gd (its
## _test_filter_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

const FILTERS: Array[String] = ["air_filter", "oil_filter"]
## Where a player's eyes are, standing and crouched (Walker.EYE, Walker.CROUCH_EYE).
const EYES := {"standing": Walker.EYE, "crouched": Walker.CROUCH_EYE}


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A bike model of `parts`, standing in the runner's tree as it stands in a bay (wheels on the
## floor), well away from anything else. Wait a physics frame before aiming at it.
func model_of(parts: Dictionary) -> BikeModel:
	var build := BikeBuild.new(PartsDB.sanitize_build(parts))
	var m := BikeModel.new()
	t.add_child(m)
	m.position = FAR + Vector3.UP * (build.rear_radius + 0.06)
	m.build_from(build, Color(0.6, 0.1, 0.1), {}, null, false)
	m.build_pickers({"bike": 1})
	return m


## Where the test bikes stand, out of the way of anything else in the runner's world.
const FAR := Vector3(400.0, 0.0, -400.0)


## Points on a slot's drawn (visible) meshes to aim at, global.
static func aim_points(m: BikeModel, slot: String) -> Array:
	var out := []
	for mi in m._slot_meshes.get(slot, []):
		if not (mi as Node3D).is_visible_in_tree():
			continue
		var box: AABB = (mi as VisualInstance3D).get_aabb()
		var xf := (mi as Node3D).global_transform
		out.append(xf * box.get_center())
		for sx in [-0.3, 0.3]:
			for sy in [-0.3, 0.3]:
				for sz in [-0.3, 0.3]:
					out.append(xf * (box.get_center() + box.size * Vector3(sx, sy, sz)))
	return out


## What a crosshair ray from `from` towards `to` lands on first within reach: the collider, or null.
static func first_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Object:
	var q := PhysicsRayQueryParameters3D.create(from, from + (to - from).normalized() * Walker.REACH, 1 | BikeModel.PICK_LAYER | Workshop.INTERACT_LAYER)
	q.exclude = exclude
	var hit := Walker.past_stand(space, q, space.intersect_ray(q))
	return hit["collider"] if hit else null


## Where a player could stand to aim at `slot`, and at what: [{eye, at}] (global) for eyes
## `eye_y` above the floor beside the bike, out of its way either side. `floor` is the bike's
## place on the floor; with `first` it stops at the first one it finds.
static func aims(m: BikeModel, slot: String, eye_y: float, floor: Transform3D, first := true, exclude: Array[RID] = []) -> Array:
	var targets := aim_points(m, slot)
	if targets.is_empty():
		return []
	var mid := Vector3.ZERO
	for p in targets:
		mid += floor.affine_inverse() * p
	mid /= targets.size()
	var space := m.get_world_3d().direct_space_state
	var out := []
	for side in [1.0, -1.0]:
		for off in [0.75, 0.95, 1.2]:
			for dz in [0.0, -0.3, 0.3, -0.6, 0.6]:
				var eye := floor * Vector3(side * off, eye_y, mid.z + dz)
				for p in targets:
					var c := first_hit(space, eye, p, exclude)
					if c != null and c.has_meta("slot") and str(c.get_meta("slot")) == slot and m.is_ancestor_of(c as Node):
						out.append({"eye": eye, "at": p})
						if first:
							return out
	return out


## Whether a slot shows on a model: some of its meshes drawn, not all tucked away out of sight.
static func shown(m: BikeModel, slot: String) -> bool:
	var meshes: Array = m._slot_meshes.get(slot, [])
	return not meshes.is_empty() and meshes.any(func(mi): return (mi as Node3D).is_visible_in_tree())


## The bikes to try: every style's own build with every engine in the catalogue in it.
static func builds() -> Array:
	var out := []
	for style in PartsDB.STYLES:
		var base := Contracts.style_build(style)
		for engine in PartsDB.by_kind["engine"]:
			var b := base.duplicate()
			b["engine"] = engine
			out.append({"style": style, "engine": str(engine), "parts": b})
	return out


## An engine of each layout, the smallest and the biggest.
static func engine_picks() -> Array:
	var by := {}
	for id in PartsDB.by_kind["engine"]:
		var lay := str(PartsDB.parts[id].get("layout", ""))
		var cc := float(PartsDB.parts[id].get("displacement", 0.0))
		if not by.has(lay):
			by[lay] = [id, id]
		if cc < float(PartsDB.parts[by[lay][0]]["displacement"]):
			by[lay][0] = id
		if cc > float(PartsDB.parts[by[lay][1]]["displacement"]):
			by[lay][1] = id
	var out := []
	for lay in by:
		for id in by[lay]:
			if not out.has(id):
				out.append(id)
	return out


# ---------------------------------------------------------------------------- the rules

## Every style with every engine: both filters unbolt, come off, go back on and bolt up with the
## engine in the frame, standing or crouched; nothing else has to come off first.
func test_rules() -> void:
	Shed.start_new("Tester", 21)
	var me := Shed.me()
	for style in PartsDB.STYLES:
		var bad := []
		for b in builds():
			if b["style"] != style:
				continue
			var bike := Shed._new_bike(b["parts"], 3, "Filter test", 0.2)
			var block := Shed.item_on(bike, "engine")
			for slot in FILTERS:
				for crouched in [false, true]:
					var why := _service(me, bike, slot, crouched)
					if why != "":
						bad.append("%s %s %s: %s" % [b["engine"], slot, "crouched" if crouched else "standing", why])
			if Shed.item_on(bike, "engine") != block or not Shed.is_bolted(bike, "engine"):
				bad.append("%s: the engine moved" % b["engine"])
			_scrap_bike(bike)
		check(bad.is_empty(), "%s: air and oil filters change in the frame on every engine, standing or crouched%s" % [PartsDB.style_name(style),
			"" if bad.is_empty() else " (%d failed, e.g. %s)" % [bad.size(), bad[0]]])
	# The order still matters where it should: on the engine being built up on the stand, the
	# air filter only goes on once the carbs are on, and they only come off with it off.
	var block := Shed.item_at_spot(Shed.stand_spots()[0])
	if Shed.engine_item(block, "air_filter") == 0:
		Shed._move(Shed._new_item("paper_airbox", 0.0, 0.0, 0.0), "held", me)
		Shed.request({"a": "install", "engine": block, "slot": "air_filter"})
	Shed.request({"a": "unbolt", "engine": block, "slot": "fuel"})
	check(Shed.check(me, {"a": "remove", "engine": block, "slot": "fuel"}).contains("air filter"),
		"the carbs don't come off with the air filter still on them")
	Shed.request({"a": "unbolt", "engine": block, "slot": "air_filter"})
	Shed.request({"a": "remove", "engine": block, "slot": "air_filter"})
	var air := Shed.held_by(me)
	Shed._move(air, "floor", Transform3D())
	Shed.request({"a": "remove", "engine": block, "slot": "fuel"})
	var carbs := Shed.held_by(me)
	Shed._move(carbs, "floor", Transform3D())
	Shed.request({"a": "take", "item": air})
	check(Shed.check(me, {"a": "install", "engine": block, "slot": "air_filter"}).contains("fuel"),
		"and the air filter needs the carbs on first (%s)" % Shed.check(me, {"a": "install", "engine": block, "slot": "air_filter"}))
	Shed._move(air, "floor", Transform3D())
	Shed.request({"a": "take", "item": carbs})
	Shed.request({"a": "install", "engine": block, "slot": "fuel"})
	Shed.request({"a": "take", "item": air})
	Shed.request({"a": "install", "engine": block, "slot": "air_filter"})
	check(Shed.engine_item(block, "fuel") == carbs and Shed.engine_item(block, "air_filter") == air, "carbs first, then the air filter, and both are back on")


## Unbolts, takes off, refits and bolts up a bike's `slot` as `me`, standing or crouched. "" when
## it all works, or what stopped it.
func _service(me: int, bike: int, slot: String, crouched: bool) -> String:
	var item := Shed.item_on(bike, slot)
	if item == 0:
		return "no filter fitted"
	for step in [{"a": "unbolt"}, {"a": "remove"}, {"a": "install"}, {"a": "bolt"}]:
		var act: Dictionary = step.duplicate()
		act.merge({"bike": bike, "slot": slot, "crouched": crouched})
		var why := Shed.check(me, act)
		if why != "":
			return "%s: %s" % [act["a"], why]
		Shed.request(act)
		if act["a"] == "remove" and Shed.held_by(me) != item:
			return "remove: it didn't come off into your hands"
	if Shed.item_on(bike, slot) != item or not Shed.is_bolted(bike, slot):
		return "it didn't go back on bolted"
	return ""


## Takes a test bike and its parts out of the shed again.
static func _scrap_bike(bike: int) -> void:
	for slot in PartsDB.SLOTS:
		var on := Shed.item_on(bike, slot)
		if on != 0:
			if Shed.is_engine(on):
				for es in PartsDB.ENGINE_SLOTS:
					Shed.items.erase(Shed.engine_item(on, es))
			Shed.items.erase(on)
	Shed.bikes.erase(bike)


# ---------------------------------------------------------------------------- seeing and aiming

## Every style with every engine in it: each filter shows and can be aimed at with the engine in
## the frame, from a standing and a crouched eye height beside the bike. And each kind of air
## filter on each style, with each layout of engine.
func test_aim() -> void:
	var t0 := Time.get_ticks_msec()
	var floor := Transform3D(Basis(), FAR)
	for style in PartsDB.STYLES:
		var bad := []
		var cases := []
		for b in builds():
			if b["style"] == style:
				cases.append(b)
		var base := Contracts.style_build(style)
		for engine in engine_picks():
			for air in PartsDB.by_kind["air_filter"]:
				if air != base["air_filter"]:
					var parts := base.duplicate()
					parts["engine"] = engine
					parts["air_filter"] = air
					cases.append({"engine": "%s with %s" % [engine, air], "parts": parts})
		for c in cases:
			var m := model_of(c["parts"])
			await t.get_tree().physics_frame
			for slot in FILTERS:
				if not shown(m, slot):
					bad.append("%s: %s out of sight" % [c["engine"], slot])
					continue
				for pose in EYES:
					if aims(m, slot, float(EYES[pose]), floor).is_empty():
						bad.append("%s: can't aim at the %s %s" % [c["engine"], slot, pose])
			m.free()
		check(bad.is_empty(), "%s: both filters show and can be aimed at standing and crouched, on every engine and air filter (%d bikes)%s" % [
			PartsDB.style_name(style), cases.size(), "" if bad.is_empty() else " (%d failed, e.g. %s)" % [bad.size(), bad[0]]])
	print("    (aimed at %d s)" % ((Time.get_ticks_msec() - t0) / 1000))


## Every engine, built up off the bike as it sits on the engine stand, with each kind of air
## filter: both filters show and can be aimed at standing and crouched beside it.
func test_stand_aim() -> void:
	var floor := Transform3D(Basis(), FAR)
	var bad := []
	var n := 0
	for engine in PartsDB.by_kind["engine"]:
		for air in PartsDB.by_kind["air_filter"]:
			var parts := {"engine": engine}
			for slot in PartsDB.ENGINE_SLOTS:
				parts[slot] = PartsDB.DEFAULT_BUILD[slot]
			parts["air_filter"] = air
			var cond := {}
			for slot in parts:
				cond[slot] = {}
			var display := BikeModel.assembly_display(parts, cond)
			t.add_child(display)
			# Up on the stand's top, about as high as the real one holds it.
			display.position = FAR + Vector3.UP * 0.65
			var m: BikeModel = display.get_meta("model")
			m.build_pickers({"engine": 1})
			await t.get_tree().physics_frame
			n += 1
			for slot in FILTERS:
				if not shown(m, slot):
					bad.append("%s with %s: %s out of sight" % [engine, air, slot])
					continue
				for pose in EYES:
					if aims(m, slot, float(EYES[pose]), floor).is_empty():
						bad.append("%s with %s: can't aim at the %s %s" % [engine, air, slot, pose])
			display.free()
	check(bad.is_empty(), "on the engine stand, both filters show and can be aimed at standing and crouched, on every engine with every air filter (%d)%s" % [
		n, "" if bad.is_empty() else " (%d failed, e.g. %s)" % [bad.size(), bad[0]]])


## Under a full fairing the filters come out through quick-release caps on the right-hand panel:
## the caps are the filters' own, so they go when the filter comes off and you aim at them.
func test_fairing_caps() -> void:
	for style in ["sport", "race"]:
		var parts := Contracts.style_build(style)
		var m := model_of(parts)
		await t.get_tree().physics_frame
		for slot in FILTERS:
			var caps: Array = m._slot_meshes[slot].filter(func(mi): return (mi as Node).has_meta("service_cap"))
			var hidden: bool = m._slot_meshes[slot].any(func(mi): return not (mi as Node3D).is_visible_in_tree())
			if hidden:
				check(caps.size() == 1 and (caps[0] as Node3D).is_visible_in_tree(),
					"%s: the %s, out of sight under the fairing, comes out through a cap on its side" % [PartsDB.style_name(style), PartsDB.slot_name(slot).to_lower()])
			else:
				check(caps.is_empty() and shown(m, slot),
					"%s: the %s shows clear of the fairing, and needs no cap" % [PartsDB.style_name(style), PartsDB.slot_name(slot).to_lower()])
		m.free()
		var off := {}
		for slot in PartsDB.SLOTS:
			off[slot] = slot != "air_filter"
		var bare := BikeModel.new()
		t.add_child(bare)
		bare.build_from(BikeBuild.new(PartsDB.sanitize_build(parts)), Color.RED, off, null, false)
		# (Under a Rig built panel set the airbox sits under the tank, clear of the panels, and
		# has no cap: it just goes.)
		var capped: bool = bare._set_drawn != "" or bare._slot_meshes["air_filter"].any(func(mi): return (mi as Node).has_meta("service_cap"))
		check(capped and bare._slot_meshes["air_filter"].all(func(mi): return not (mi as Node3D).visible),
			"%s: with the air filter off its cap goes too" % PartsDB.style_name(style))
		bare.free()


# ---------------------------------------------------------------------------- in the shed, with the real crosshair

## In the shed: crouched and standing beside a bike in its bay, the crosshair finds each filter
## and the wrench and your hands take it off and put it back, engine in the frame. Then the same
## on an engine being built up on the engine stand.
func test_in_shed() -> void:
	Shed.start_new("Tester", 21)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await t.get_tree().process_frame
	var w: Walker = main.walker
	for style in ["classic", "sport"]:
		var bike := Shed._new_bike(Contracts.style_build(style), 3, "Filter test", 0.2)
		Shed.changed.emit()
		var model_of_bike := func() -> BikeModel: return main.workshop.bike_model(bike)
		var floor: Transform3D = Workshop.bay_transform(3)
		for slot in FILTERS:
			for pose in EYES:
				var item := Shed.item_on(bike, slot)
				var aim := await _aim_walker(w, model_of_bike, slot, pose, floor)
				check(aim and str(w.target.get("slot", "")) == slot and int(w.target.get("bike", 0)) == bike,
					"%s, %s by the bike: the crosshair finds the %s (%s)" % [PartsDB.style_name(style), pose, PartsDB.slot_name(slot).to_lower(),
					str(w.target.get("slot", w.target.get("kind", "nothing")))])
				if not aim:
					continue
				w.set_tool("wrench")
				await t._hold_act(main)
				var unbolted := not Shed.is_bolted(bike, slot)
				w.set_tool("hands")
				await t._hold_act(main)
				var off := Shed.held_by(Shed.me()) == item and Shed.item_on(bike, slot) == 0
				# Put back: aimed at the bike, it goes back where it came from.
				await _aim_walker(w, model_of_bike, "tank", pose, floor)
				await t._hold_act(main)
				var on := Shed.item_on(bike, slot) == item
				await _aim_walker(w, model_of_bike, slot, pose, floor)
				w.set_tool("wrench")
				await t._hold_act(main)
				w.set_tool("hands")
				check(unbolted and off and on and Shed.is_bolted(bike, slot) and Shed.item_on(bike, "engine") != 0,
					"%s, %s: wrench, off, back on and bolted up, engine in the frame (%s %s %s %s)" % [PartsDB.style_name(style), pose,
					unbolted, off, on, Shed.is_bolted(bike, slot)])
		w.set_crouched(false)
		_scrap_bike(bike)
		Shed.changed.emit()
		await t.get_tree().process_frame
	# On the engine stand: the engine being built up there has its oil filter on and is waiting
	# for its air filter.
	var spot: String = Shed.stand_spots()[0]
	var block := Shed.item_at_spot(spot)
	var fresh := Shed._new_item("paper_airbox", 0.0, 0.0, 0.0)
	Shed._move(fresh, "held", Shed.me())
	Shed.request({"a": "install", "engine": block, "slot": "air_filter"})
	Shed.request({"a": "bolt", "engine": block, "slot": "air_filter"})
	Shed.changed.emit()
	await t.get_tree().process_frame
	check(Shed.engine_item(block, "air_filter") == fresh and Shed.engine_item(block, "oil_filter") != 0, "an engine on the stand with both filters on")
	var at: Vector3 = Shed.spot_transform(spot).origin
	var on_stand := func() -> BikeModel: return main.workshop._spot_nodes[spot].get_meta("model")
	for slot in FILTERS:
		for pose in EYES:
			var ground := Transform3D((on_stand.call() as BikeModel).global_transform.basis.orthonormalized(), Vector3(at.x, 0.0, at.z))
			var item := Shed.engine_item(block, slot)
			var aim := await _aim_walker(w, on_stand, slot, pose, ground)
			check(aim and str(w.target.get("slot", "")) == slot and int(w.target.get("engine", 0)) == block,
				"on the engine stand, %s: the crosshair finds the %s" % [pose, PartsDB.slot_name(slot).to_lower()])
			w.set_tool("wrench")
			await t._hold_act(main)
			w.set_tool("hands")
			await t._hold_act(main)
			var off := Shed.held_by(Shed.me()) == item and Shed.engine_item(block, slot) == 0
			Shed.request({"a": "install", "engine": block, "slot": slot})
			Shed.request({"a": "bolt", "engine": block, "slot": slot})
			check(off and Shed.engine_item(block, slot) == item, "and it comes off and goes back on (%s)" % str(off))
			Shed.changed.emit()
			await t.get_tree().process_frame
	w.set_crouched(false)
	main.queue_free()
	await t.get_tree().process_frame


## Puts the walker beside the model `model_now` gives, standing or crouched, where it can see `slot`, and aims the
## crosshair at it. False if there's nowhere to aim from.
func _aim_walker(w: Walker, model_now: Callable, slot: String, pose: String, floor: Transform3D) -> bool:
	w.set_crouched(pose == "crouched")
	# The shed redraws a bike when its parts change: aim at what's there now.
	await t.get_tree().process_frame
	await t.get_tree().physics_frame
	var found := aims(model_now.call(), slot, float(EYES[pose]), floor, true, [w.get_rid()])
	if found.is_empty():
		return false
	var eye: Vector3 = found[0]["eye"]
	w.place(Transform3D(Basis(), eye - Vector3.UP * float(EYES[pose])))
	await t._aim_point(w, found[0]["at"])
	return true
