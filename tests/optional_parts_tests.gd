extends RefCounted
## Simon's list of optional parts: what a bike can be without and still be complete and ridable,
## and the game naming what's missing. Run from tests/run_tests.gd (its _test_optional_parts_*
## functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

## Simon's list, by slot: headlight, indicators, front mudguard, ECU, steering damper, mirrors,
## lever guards, fairing, sat nav, tail unit, engine protectors, panniers, top box, tank bag,
## number boards, extra tank, tool kit, fog lights, horn and side panels.
const SIMONS := ["headlight", "indicators", "front_mudguard", "ecu", "steering_damper", "mirrors", "lever_guards",
	"fairing", "satnav", "tail", "guards", "panniers", "top_box", "tank_bag", "number_boards", "aux_tank", "toolbox",
	"fog_lights", "horn", "side_panels"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if str(Shed.bikes[id]["name"]) == n:
			return int(id)
	return 0


## The list itself: Simon's twenty plus the centre stand, and nothing the bike can't do without.
func test_list() -> void:
	var extra: Array = PartsDB.OPTIONAL_SLOTS.filter(func(s): return not SIMONS.has(s))
	var lost: Array = SIMONS.filter(func(s): return not PartsDB.is_optional(str(s)))
	check(lost.is_empty() and extra == ["centre_stand"], "Simon's twenty optional parts, and the centre stand (%s %s)" % [lost, extra])
	check(PartsDB.OPTIONAL_SLOTS.all(func(s): return PartsDB.BIKE_SLOTS.has(s) and PartsDB.may_be_empty(s)), "each is a bike slot that can be empty")
	check(not PartsDB.is_optional("side_stand") and not PartsDB.may_be_empty("side_stand"), "the side stand isn't optional any more")
	check(not PartsDB.is_optional("rearsets") and not PartsDB.is_optional("swingarm") and PartsDB.may_be_empty("rearsets")
		and PartsDB.may_be_empty("swingarm"), "rearsets and swingarm aren't extras, but empty they're the frame's own")
	for s in ["frame", "engine", "tank", "saddle", "front_tyre", "chain", "dashboard"]:
		check(not PartsDB.may_be_empty(s), "a bike needs its %s" % PartsDB.slot_name(s).to_lower())
	var text := PartsDB.optional_text()
	check(text.begins_with("headlight, indicators, front mudguard, ECU") and text.contains("tail unit") and text.contains("engine protectors")
		and text.contains("extra fuel tank") and text.contains("tool kit") and text.ends_with("side panels, centre stand"),
		"the list in plain words: %s" % text)
	# "none" is a real state for an optional part, and for the frame's own pegs and swingarm.
	var b := PartsDB.sanitize_build({"tail": "none", "side_stand": "none", "rearsets": "none", "swingarm": "none"})
	check(b["tail"] == "none" and b["rearsets"] == "none" and b["swingarm"] == "none", "no tail unit stays no tail unit")
	check(b["side_stand"] == PartsDB.DEFAULT_BUILD["side_stand"], "a build with no side stand gets one")
	check(PartsDB.sanitize_build({"saddle": "cafe_hump"})["tail"] == "cafe_tail", "a build from before tail units still gets one that suits it")
	var bare := BikeBuild.new({"tail": "none"})
	check(not bare.has_part("tail") and bare.bike_mass < BikeBuild.new({}).bike_mass, "a bike with no tail unit is a little lighter")
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(bare)
	check(m.tail_light_position() == Vector3.ZERO and m.find_child("TailLight", true, false) == null, "and has no rear light drawn")
	m.queue_free()
	# The parts computer says which parts a bike needs.
	check(PartsComputer.needed_text("tail").begins_with("Optional") and PartsComputer.needed_text("tail").contains("tool kit"),
		"a tail unit's page says it's optional, with the list")
	check(PartsComputer.needed_text("side_stand").begins_with("Needed") and PartsComputer.needed_text("tyre").begins_with("Needed"),
		"a side stand's and a tyre's say a bike needs one")
	check(PartsComputer.needed_text("rearsets").contains("frame's own") and PartsComputer.needed_text("petrol") == "",
		"rearsets fall back on the frame's pegs; petrol isn't a bike part")
	# The bike shop's options: "none" where a slot can be empty, never for the side stand.
	check(BikeShop.options("tail", "classic", {}).has("none") and BikeShop.options("rearsets", "classic", {}).has("none")
		and not BikeShop.options("side_stand", "classic", {}).has("none"), "the bike shop offers no tail unit, but always a side stand")


## Customers' and random bikes always have a side stand; road bikes keep their tail unit.
func test_random_bikes() -> void:
	var rng := RandomNumberGenerator.new()
	var no_stand := 0
	var road_no_tail := 0
	var bare_tail := 0
	for i in 120:
		rng.seed = 900 + i
		var road := Contracts.random_parts(rng, true)
		var any := Contracts.random_parts(rng)
		no_stand += int(str(road["side_stand"]) == "none") + int(str(any["side_stand"]) == "none")
		road_no_tail += int(str(road["tail"]) == "none")
		bare_tail += int(str(any["tail"]) == "none")
	check(no_stand == 0 and road_no_tail == 0, "every customer bike has a side stand, every road one a tail unit")
	check(bare_tail > 0, "now and then a workshop customer's bike has no tail unit (%d in 120)" % bare_tail)
	Shed.start_new("Tester", 77)
	var made := 0
	var stands := 0
	for id in Shed.bikes:
		made += 1
		stands += int(str(Shed.bikes[id]["original"]["side_stand"]) != "none")
	check(made > 0 and stands == made, "the shed's bikes all came with a side stand")
	# A project bike, as they come: always a side stand, now and then no tail unit.
	var project_tails := 0
	var project_stands := 0
	for i in 120:
		Shed._rng.seed = 4000 + i
		var p := Shed._random_bike(Workshop.bay_count() - 1, 0.5)
		project_stands += int(str(Shed.bikes[p]["original"]["side_stand"]) != "none")
		project_tails += int(str(Shed.bikes[p]["original"]["tail"]) == "none")
		Shed.bikes.erase(p)
	check(project_stands == 120 and project_tails > 0 and project_tails < 30,
		"project bikes always have a side stand, now and then no tail unit (%d in 120)" % project_tails)
	# A bike made with no tail unit is complete without one.
	var parts := Contracts.random_parts(rng, true)
	parts["tail"] = "none"
	var before := Shed.bikes.keys()
	var bay := Workshop.bay_count() - 1
	var id := Shed._new_bike(parts, bay, "Tailless", 0.0)
	check(Shed.item_on(id, "tail") == 0 and not Shed.missing_slots(id).has("tail") and not before.has(id), "a bike made without a tail unit has none, and doesn't need one")
	check(Shed.build_of(id).parts["tail"] == "none" and Shed.blueprint_of(id)["parts"]["tail"] == "none", "its build and blueprint say so")
	var fails := MotTest.fails(MotTest.inspect(id))
	check(fails.any(func(r): return str(r["name"]).contains("Rear light")) and not fails.any(func(r): return str(r["name"]).begins_with("Everything fitted")),
		"but it fails the MOT on its rear light, not for missing parts")
	Shed.stop()


## In the shed: a bike rides without its tail unit but not without its side stand, and the game
## names what's missing. A save with a bike missing its side stand loads, and it needs one.
func test_shed() -> void:
	Shed.start_new("Tester", 31)
	var me := Shed.me()
	var faithful := _bike_named("Old Faithful")
	check(Shed.is_complete(faithful), "Old Faithful starts complete")
	Shed.request({"a": "unbolt", "bike": faithful, "slot": "tail"})
	Shed.request({"a": "remove", "bike": faithful, "slot": "tail"})
	var tail := Shed.held_by(me)
	check(tail != 0 and Shed.item_on(faithful, "tail") == 0 and Shed.is_complete(faithful), "with the tail unit off it's still complete")
	check(Shed.build_of(faithful).parts["tail"] == "none", "and its build has no tail unit")
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER)})
	Shed.request({"a": "unbolt", "bike": faithful, "slot": "side_stand", "crouched": true})
	Shed.request({"a": "remove", "bike": faithful, "slot": "side_stand", "crouched": true})
	check(Shed.item_on(faithful, "side_stand") == 0 and Shed.missing_slots(faithful) == ["side_stand"] and not Shed.is_complete(faithful),
		"with the side stand off it isn't (%s)" % str(Shed.missing_slots(faithful)))
	Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.5, 0.0, 0.0))})
	var said := Shed.check(me, {"a": "mount", "bike": faithful})
	check(said.contains("side stand"), "getting on says what's missing: %s" % said)
	var lines := Workshop.missing_lines(Shed.missing_slots(faithful))
	check(lines == ["Needs to ride: side stand"], "the bay screen names it: %s" % str(lines))
	var long := Workshop.missing_lines(["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre", "side_stand"])
	check(long.size() >= 2 and long.all(func(l): return str(l).length() <= Workshop.MISSING_LINE) and str(long[-1]).ends_with("side stand"),
		"a long list wraps to fit the screen")
	check(Workshop.missing_lines([]).is_empty(), "a complete bike has no such lines")
	var text := PartsComputer.missing_text(faithful)
	check(text.begins_with("Missing: side stand.") and text.contains("Optional parts") and text.contains("tail unit"),
		"the parts computer's sale page names it, and lists what it can do without")
	check(MotTest.fails(MotTest.inspect(faithful)).any(func(r): return str(r["name"]).begins_with("Everything fitted")),
		"the MOT fails it for the missing side stand")
	# Saved like that (and with "none" in its delivered build, as old saves had), it loads.
	Shed.bikes[faithful]["original"]["side_stand"] = "none"
	Shed.bikes[faithful]["original"]["tail"] = "none"
	var snap: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.stop()
	Shed.load_state(snap, "Tester")
	faithful = _bike_named("Old Faithful")
	check(Shed.bikes.has(faithful) and Shed.missing_slots(faithful) == ["side_stand"] and not Shed.is_complete(faithful),
		"a saved bike with no side stand loads, and needs one fitting")
	var build := Shed.build_of(faithful)
	check(build.parts["tail"] == "none" and str(build.parts["side_stand"]) != "none", "its build loads too")
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(build)
	check(m.get_child_count() > 0, "and it draws")
	m.queue_free()
	check(StaffJobs.part_for(faithful, "side_stand") != "" and StaffJobs.part_for(faithful, "side_stand") != "none",
		"the crew know a side stand to order for it")
	Shed.stop()
