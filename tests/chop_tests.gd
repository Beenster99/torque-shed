extends RefCounted
## Engines sat in chopper frames: every engine in every frame a chopper can be built on clears
## the frame's tubes and the tank, and the other frames are left as they were. Run from
## tests/run_tests.gd (its _test_chop_* functions hand over to these).

var t: Node   # the test runner: check(), add_child()

## How far (m) an engine may touch a tube or the tank before it counts as poking through.
const TOUCH := 0.0005


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The frames a chopper can be built on (tagged "chopper" in the catalogue).
static func chopper_frames() -> Array:
	return PartsDB.by_kind["frame"].filter(func(id): return PartsDB.styles_of(str(id)).has("chopper"))


## A chopper's parts with `frame` and `engine` in it.
static func chopper_parts(frame: String, engine: String) -> Dictionary:
	var parts := Contracts.style_build("chopper")
	parts["frame"] = frame
	parts["engine"] = engine
	return parts


## The engine's size as it's drawn everywhere else (see BikeModel._layout_cylinders).
static func usual_size(build: BikeBuild) -> float:
	return clampf(pow(build.displacement / 700.0, 0.3), 0.55, 1.2)


## Every engine in every chopper frame sits inside the frame's tubes and under the tank, measured
## on the engine's own cases, barrels and heads, and isn't shrunk much to get there.
func test_engines_fit() -> void:
	var m := BikeModel.new()
	m.look = BikeLook.CLASSIC   # (_fit_bay is the Classic look's layout; Rig built's is BikeRig, tests/bike_rig_tests.gd)
	t.add_child(m)
	var frames := chopper_frames()
	var engines: Array = PartsDB.by_kind["engine"]
	var bad := []
	var worst := [0.0, 0.0]
	var smallest := [1.0, ""]
	var smallest_chop := [1.0, ""]
	for f in frames:
		for e in engines:
			var build := BikeBuild.new(chopper_parts(str(f), str(e)))
			m.build_engine_bay(build)
			var c := m.engine_clash()
			worst[0] = maxf(worst[0], c["tube"])
			worst[1] = maxf(worst[1], c["tank"])
			if c["tube"] > TOUCH or c["tank"] > TOUCH:
				bad.append("%s in %s: %.0f mm into a tube, %.0f mm into the tank (%s)" % [e, f, c["tube"] * 1000.0, c["tank"] * 1000.0, c["where"]])
			var k: float = m._eng_s / usual_size(build)
			if k < smallest[0]:
				smallest = [k, "%s in %s" % [e, f]]
			if k < smallest_chop[0] and str(PartsDB.get_part(str(f)).get("style", "")) == "chopper":
				smallest_chop = [k, "%s in %s" % [e, f]]
	check(frames.size() >= 5, "there are chopper frames to check (%d)" % frames.size())
	check(bad.is_empty(), "every engine (%d) clears the tubes and the tank of every chopper frame (%d): deepest %.1f mm into a tube, %.1f mm into a tank %s"
		% [engines.size(), frames.size(), worst[0] * 1000.0, worst[1] * 1000.0, bad.slice(0, 6)])
	# A raked chopper frame has room for anything; the short softail and rigid bobber frames a
	# chopper can also be built on draw their biggest engines smaller to fit.
	check(smallest_chop[0] >= 0.9, "every engine keeps (nearly) its size in a raked chopper frame (smallest %d%%, %s)" % [roundi(smallest_chop[0] * 100.0), smallest_chop[1]])
	check(smallest[0] >= 0.65, "no engine is drawn much smaller to fit a short softail or bobber frame (smallest %d%% of its usual size, %s)" % [roundi(smallest[0] * 100.0), smallest[1]])
	# The stock chopper's big V-twin stays big.
	var stock := BikeBuild.new(chopper_parts("chopper_raked", "vtwin_1800"))
	m.build_engine_bay(stock)
	check(m._eng_s >= usual_size(stock) * 0.9, "the stock chopper's 1800 V-twin keeps its size (%d%%)" % roundi(m._eng_s / usual_size(stock) * 100.0))
	check(m._spine_kink != Vector3.ZERO and m._tank_b.y > m._seat_front.y + 0.15,
		"its backbone and tank run high over the heads and drop to the low seat (tank %.2f m over the seat)" % (m._tank_b.y - m._seat_front.y))
	m.free()


## The other long, low frames built the same way (softails and cruisers) clear the biggest engine
## of every kind, and whole bikes of every style still lay out round their engine as before.
func test_other_frames() -> void:
	var m := BikeModel.new()
	m.look = BikeLook.CLASSIC   # (_fit_bay is the Classic look's layout; Rig built's is BikeRig, tests/bike_rig_tests.gd)
	t.add_child(m)
	var biggest := {}
	for e in PartsDB.by_kind["engine"]:
		var p := PartsDB.get_part(str(e))
		var layout := str(p.get("layout", ""))
		if not biggest.has(layout) or float(p.get("displacement", 0.0)) > float(PartsDB.get_part(str(biggest[layout])).get("displacement", 0.0)):
			biggest[layout] = e
	var bad := []
	var bays := 0
	for f in PartsDB.by_kind["frame"]:
		if not str(PartsDB.get_part(str(f)).get("style", "")) in BikeModel.BAY_FRAMES or chopper_frames().has(f):
			continue
		bays += 1
		for e in biggest.values():
			m.build_engine_bay(BikeBuild.new(chopper_parts(str(f), str(e))))
			var c := m.engine_clash()
			if c["tube"] > TOUCH or c["tank"] > TOUCH:
				bad.append("%s in %s (%.0f, %.0f mm)" % [e, f, c["tube"] * 1000.0, c["tank"] * 1000.0])
	check(bays >= 3 and bad.is_empty(), "the biggest engine of each kind clears the softail and cruiser frames too (%d frames) %s" % [bays, bad])
	# Every other frame keeps its engine where it was, full size, under a straight top tube.
	var moved := []
	for style in PartsDB.STYLES:
		var parts := Contracts.style_build(style)
		var build := BikeBuild.new(parts)
		m.build_engine_bay(build)
		if str(PartsDB.get_part(str(parts["frame"])).get("style", "")) in BikeModel.BAY_FRAMES:
			continue
		var at := lerpf(m._head_bottom.z, m._pivot.z, m._geo("engine_at", 0.48))
		if m._spine_kink != Vector3.ZERO or m._head_k != 1.0 or m._eng_s != usual_size(build) or absf(m._engine_c.z - at) > 0.0001:
			moved.append(style)
	check(moved.is_empty(), "the other styles' frames lay their engines out just as before %s" % [moved])
	m.free()


## The measure itself sees an engine through the tank and through a tube.
func test_measure() -> void:
	var m := BikeModel.new()
	m.look = BikeLook.CLASSIC   # (_fit_bay is the Classic look's layout; Rig built's is BikeRig, tests/bike_rig_tests.gd)
	t.add_child(m)
	m.build_engine_bay(BikeBuild.new(chopper_parts("chopper_raked", "vtwin_1800")))
	var clear := m.engine_clash()
	for slot in ["engine", "head"]:
		for mi in m._slot_meshes[slot]:
			(mi as Node3D).position.y += 0.2
	var lifted := m.engine_clash()
	for slot in ["engine", "head"]:
		for mi in m._slot_meshes[slot]:
			(mi as Node3D).position += Vector3(0.0, -0.2, -0.25)
	var forward := m.engine_clash()
	check(clear["tube"] <= TOUCH and lifted["tank"] > 0.1 and forward["tube"] > 0.01,
		"the clash measure sees an engine lifted into the tank (%.0f mm) or pushed into the downtubes (%.0f mm, %s)"
		% [lifted["tank"] * 1000.0, forward["tube"] * 1000.0, forward["where"]])
	m.free()


## Whole choppers, every part drawn, pass the same measure.
func test_whole_bikes() -> void:
	var bad := []
	for f in chopper_frames():
		for e in ["vtwin_1800", "inline_1200", "twin_750"]:
			var m := BikeModel.new()
			m.look = BikeLook.CLASSIC   # (_fit_bay is the Classic look's layout; Rig built's is BikeRig, tests/bike_rig_tests.gd)
			t.add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(chopper_parts(str(f), e))))
			var c := m.engine_clash()
			if c["tube"] > TOUCH or c["tank"] > TOUCH:
				bad.append("%s in %s (%s)" % [e, f, c["where"]])
			m.free()
	check(bad.is_empty(), "whole choppers keep their engines inside the frame and under the tank %s" % [bad])
