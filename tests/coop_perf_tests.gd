extends RefCounted
## Co-op performance checks: what another player costs up close against further off. Run from
## tests/run_tests.gd (its _test_coop_perf_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

## The profiler's systems (see Perf) that look after you, the crew and what's near you.
const PLAYER_SYSTEMS := ["remote_bikes", "remote_players", "bike_physics", "main_ride", "walker", "camera", "bike_fx",
	"skid_marks", "engine_audio", "audio", "hud", "satnav", "workshop", "shed", "net_send", "net_receive"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## What's drawn under `n`: "all", the GeometryInstance3Ds seen (each a draw call of its own);
## "close", those of them only drawn up close (a visibility range ending within 30 m); and
## "casters", those drawn into the shadow maps (a draw in each split they're in).
static func draws(n: Node) -> Dictionary:
	var all := 0
	var casters := 0
	var close := []
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh == null:
			continue
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		all += 1
		if gi.visibility_range_end > 0.0 and gi.visibility_range_end < 30.0:
			close.append(gi)
	return {"all": all, "close": close, "casters": casters}


## Simon's 19 October round: "Performance has improved except for when we are a couple of
## metres from each other." A crew member's bike drew 88 more things once it came within 9 m,
## the tyre walls' letters, each a Label3D of its own, and close to the camera it's in all four
## of the sun's shadow splits, each a draw for every piece. Now each tyre's lettering is one
## mesh and the pieces on a node cast one shadow, and a crew member's bike or figure 2 m away
## costs the frame about what it does 30 m away.
func test_close() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	var faithful: int = t._bike_named("Old Faithful")
	var other := 0
	for id in Shed.bikes:
		if id != faithful:
			other = id
	# The crew's bike, as it's drawn: nothing much more for being close.
	var rb := RemoteBike.new()
	t.add_child(rb)
	rb.setup("Crew", Shed.build_of(faithful), Color.RED)
	var d := draws(rb)
	var letters: Array = rb.find_children("TyreLettering", "", true, false)
	var labels := rb.find_children("*", "Label3D", true, false).size()
	var faces := []
	for l in letters:
		var mesh: Mesh = (l as MeshInstance3D).mesh if l is MeshInstance3D else null
		faces.append(mesh.get_faces().size() / 3 if mesh else 0)
	check(letters.size() == 2 and faces.all(func(f): return f > 300 and f < 4000),
		"each tyre's lettering is one mesh, letters and all (%s triangles)" % str(faces))
	check((d["close"] as Array).size() <= 2 and labels <= 2,
		"only %d things on the crew's bike are drawn just up close (not the 88 letters there were), and %d labels (their name)" % [(d["close"] as Array).size(), labels])
	check(int(d["all"]) <= 150 and int(d["casters"]) <= 75,
		"the crew's bike is %d draws close or far, and %d in each shadow split it's in" % [int(d["all"]), int(d["casters"])])
	rb.queue_free()
	# Riding beside them and stood beside them, timed: 2 m against 30 m, turn about.
	var at := Vector3(14.0, 0.0, 30.0)
	for how in ["riding", "walking"]:
		if how == "riding":
			Shed.bikes[faithful]["xf"] = Transform3D(Basis(), at)
			main._try_mount(faithful)
			for i in 5:
				await t.get_tree().physics_frame
			check(main.bike != null, "you're on your bike in the yard")
			if main.bike == null:
				break
			main.bike.place(at, 0.0)
			main.bike.engine_on = true
		else:
			main._get_off()
			for i in 5:
				await t.get_tree().physics_frame
			main.walker.place(Transform3D(Basis(), at))
		var rp := RemotePlayer.new()
		main.world.add_child(rp)
		rp.setup(77, "Crew", Color.RED)
		main.remotes[77] = rp
		var cost := {2.0: [], 30.0: []}
		var systems := {2.0: {}, 30.0: {}}   # the profiler's systems, ms a frame added up over the rounds
		var pairs := {2.0: 0.0, 30.0: 0.0}
		for round in 3:
			for dist in [30.0, 2.0]:
				var there := at + Vector3(1.5 if dist < 5.0 else 0.0, 0.0, -dist)
				var state := _state(how, other, there)
				for i in 20:
					rp.push_state(state)
					await t.get_tree().process_frame
				(cost[dist] as Array).append(await _frame_cost(rp, state, systems[dist]))
				pairs[dist] = maxf(pairs[dist], Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
		var near := _median(cost[2.0])
		var far := _median(cost[30.0])
		# Which of the systems that deal with players cost more up close, most first (the
		# traffic and the town's people come and go by themselves, so they're left out).
		var more := []
		for key in systems[2.0]:
			if key in PLAYER_SYSTEMS:
				more.append([key, (float(systems[2.0][key]) - float(systems[30.0].get(key, 0.0))) / 3.0])
		more.sort_custom(func(x, y): return x[1] > y[1])
		var top := ", ".join(more.slice(0, 4).map(func(r): return "%s %+.3f" % [r[0], r[1]]))
		print("    CO-OP CLOSE (%s): %.2f ms a frame 2 m away, %.2f ms 30 m away; 2 m rounds %s; physics pairs %d / %d; up close: %s"
			% [how, near, far, str((cost[2.0] as Array).map(func(c): return snappedf(c, 0.01))), pairs[2.0], pairs[30.0], top])
		check(near <= far * 1.25 + 0.5 and (more.is_empty() or float(more[0][1]) < 0.5),
			"%s, a crew member 2 m away costs about what they do 30 m away (%.2f ms against %.2f a frame; most up close: %s)" % [how, near, far, top])
		if how == "riding":
			check(rp.bike != null and rp.bike.global_position.distance_to(main.bike.global_position) < 3.0, "(they were beside you)")
		main.remotes.erase(77)
		rp.queue_free()
		await t.get_tree().process_frame
	main._leave()
	main.queue_free()
	await t.get_tree().process_frame


## A crew member's snapshot: on `bike` at `at`, engine running and lights on; or on foot there.
static func _state(how: String, bike: int, at: Vector3) -> PackedFloat32Array:
	if how != "riding":
		return PackedFloat32Array([0.0, at.x, at.y, at.z, 0.0, 0.0, 0.0])
	var s := PackedFloat32Array([1.0, float(bike)])
	var b := PackedFloat32Array()
	b.resize(25)
	b[0] = at.x
	b[1] = at.y
	b[2] = at.z
	b[6] = 1.0      # upright
	b[15] = 1200.0  # ticking over
	b[19] = 1.0     # running
	b[24] = 1.0     # dipped beam
	s.append_array(b)
	return s


## The whole frame's cost, ms, by the clock (the tests step a fixed time a frame, so each takes
## as long as its work does), over 120 frames. The lower quartile, as whatever else the machine
## is doing only ever adds to it. The profiler's systems' ms a frame are added to `systems`.
func _frame_cost(rp: RemotePlayer, state: PackedFloat32Array, systems: Dictionary) -> float:
	var ms := []
	Perf.on = true
	Perf.start_recording()
	var last := Time.get_ticks_usec()
	for i in 120:
		if i % 3 == 0:
			rp.push_state(state)
		await t.get_tree().process_frame
		Perf.end_frame()
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	Perf.stop_recording()
	Perf.on = false
	for r in Perf.recorded():
		systems[r[0]] = float(systems.get(r[0], 0.0)) + float(r[1])
	ms.sort()
	return float(ms[ms.size() / 4])


static func _median(xs: Array) -> float:
	var s := xs.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if not s.is_empty() else 0.0
