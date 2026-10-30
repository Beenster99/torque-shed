extends RefCounted
## Rider styles and looking into the corner, run from tests/run_tests.gd (its _test_rider_style_*
## functions hand over to these): the pose each style takes at a set lean or under braking, the
## head turning the right way, the Gameplay toggle, saving the style and sending it round in co-op.

var t: Node   # the test runner: check(), get_tree()

const STEP := 1.0 / 60.0


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A model of a `bike_style` bike (see Contracts.style_build) with a rider in riding style `style`
## and `helmet`, in the runner's tree.
func _model(style: String, bike_style := "sport", helmet := "helmet_stealth") -> BikeModel:
	var m := BikeModel.new()
	m.rider_gear = RiderGear.clean_worn({"helmet": helmet, "jacket": "jacket_kestrel", "trousers": "trousers_kestrel", "style": style})
	t.add_child(m)
	m.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(bike_style))))
	return m


## Rides the model's rider at a steady `lean`, `steer`, `speed` and `brake` for `secs`.
static func _hold(m: BikeModel, lean: float, steer: float, speed: float, brake: float, secs := 2.0) -> void:
	for i in int(secs / STEP):
		m.update_rider(lean, steer, speed, brake, STEP)


## The leg on `side` now: {knee, ankle, slider} in the model's space, and how high the slider is
## off the road with the bike leaned over `lean`.
static func leg_now(m: BikeModel, side: float, lean: float) -> Dictionary:
	var leg: Dictionary = m._legs[side]
	var xf: Transform3D = m._rider.transform * (leg["node"] as Node3D).transform
	var knee: Vector3 = leg["knee"]
	var ankle: Vector3 = xf * ((leg["shin"] as Node3D).transform * ((leg["ankle"] as Vector3) - knee))
	var slider: Vector3 = xf * (leg["slider"] as Vector3)
	var h := (slider.y - m.foot_ground_y()) * cos(lean) - slider.x * sin(lean)
	return {"knee": xf * knee, "ankle": ankle, "slider": slider, "height": h}


## How far each hand is off its grip (m), the worse of the two.
static func hands_off(m: BikeModel) -> float:
	var worst := 0.0
	for side in m._arm_at:
		var a: Dictionary = m._arm_at[side]
		var grip: Vector3 = a["grip"]
		var hand: Vector3 = m._rider.transform * ((a["node"] as Node3D).transform * (m._head + grip - (a["sh"] as Vector3)))
		worst = maxf(worst, hand.distance_to(m._steer_node.transform * grip))
	return worst


## How far each foot on a peg is off it (m), the worse of the two, leaving out the side whose leg is out.
static func feet_off(m: BikeModel, lean: float, skip := 0.0) -> float:
	var worst := 0.0
	for side in m._legs:
		if side == skip:
			continue
		worst = maxf(worst, (leg_now(m, side, lean)["ankle"] as Vector3).distance_to(m._legs[side]["peg"]))
	return worst


## Where the head looks, in the model's space (its forward, flat).
static func head_forward(m: BikeModel) -> Vector3:
	var f: Vector3 = (m._rider.transform.basis * m._rider_head.basis) * Vector3.FORWARD
	return Vector3(f.x, 0.0, f.z).normalized()


## The four styles, named; the default; and the gear's worn set carrying the style.
func test_styles() -> void:
	check(RiderStyle.STYLES == ["situp", "scratcher", "naked", "rossi"], "four rider styles: %s" % str(RiderStyle.STYLES))
	var names := RiderStyle.STYLES.map(func(s): return RiderStyle.style_name(s))
	check(names == ["Sit-up adventure", "Knee-down scratcher", "Elbows-out naked", "Rossi leg out"], "named %s" % str(names))
	check(RiderStyle.DEFAULT == "situp" and RiderStyle.clean("wheelie") == "situp" and RiderStyle.clean(3) == "situp",
		"anything else is the sit-up adventure, the default")
	check(RiderGear.style_of({}) == "situp" and RiderGear.style_of({"style": "rossi"}) == "rossi", "a worn set says its style")
	check(RiderGear.clean_worn({"style": "naked"})["style"] == "naked" and not RiderGear.clean_worn({"style": "lean"}).has("style"),
		"a real style is kept with the gear, nonsense dropped")
	check(RiderGear.sig({"style": "naked"}) != RiderGear.sig({"style": "rossi"}), "a new style draws the rider again")
	# Each style builds the body its own way: sit-up straightest, the scratcher and naked forward.
	var up := {}
	for s in RiderStyle.STYLES:
		var torso: Vector3 = RiderStyle.INFO[s]["torso"]
		up[s] = rad_to_deg(torso.angle_to(Vector3.UP))
	check(up["situp"] < 15.0 and up["naked"] > 35.0 and up["scratcher"] > up["naked"] and up["rossi"] > 30.0,
		"backs from upright: sit-up %.0f, naked %.0f, scratcher %.0f, Rossi %.0f degrees" % [up["situp"], up["naked"], up["scratcher"], up["rossi"]])
	check(float(RiderStyle.INFO["naked"]["elbow_out"]) > float(RiderStyle.INFO["situp"]["elbow_out"]) * 2.0, "the naked rider's elbows go out")
	var m := _model("naked")
	var sit := _model("situp")
	var elbow := func(model: BikeModel) -> float:
		var arm := model._arm_right
		var elbows := arm.get_children().map(func(n): return absf((n as Node3D).position.x))
		return elbows.max()
	check(m.rider_style() == "naked" and sit.rider_style() == "situp", "the bike's rider sits in the style worn")
	check(float(elbow.call(m)) > float(elbow.call(sit)) + 0.03, "and a naked rider's arm sticks out further than a sit-up one's")
	m.queue_free()
	sit.queue_free()
	var plain := BikeModel.new()
	t.add_child(plain)
	plain.build_from(BikeBuild.new())
	check(plain.rider_style() == "situp", "a plain rider (no gear chosen) sits up")
	plain.queue_free()
	await t.get_tree().process_frame


## The pose each style takes through a corner at a set lean, and the knee going down.
func test_corner_pose() -> void:
	var lean := 0.6   # right, about 34 degrees
	var got := {}
	for s in RiderStyle.STYLES:
		var m := _model(s)
		var rest := leg_now(m, 1.0, 0.0)
		_hold(m, lean, 0.0, 20.0, 0.0)
		var p := m.rider_pose()
		var now := leg_now(m, 1.0, lean)
		got[s] = {"hang": p["hang"], "roll": p["roll"], "knee": p["knee"][1.0], "out": (now["knee"] as Vector3).x - (rest["knee"] as Vector3).x,
			"outer_knee": p["knee"][-1.0], "hands": hands_off(m), "feet": feet_off(m, lean)}
		m.queue_free()
	var line := func(s: String) -> String:
		var g: Dictionary = got[s]
		return "%s: hang %.2f m, tip %.2f, knee %.2f rad (%.2f m out), hands %.3f, feet %.3f" % [s, g["hang"], g["roll"], g["knee"], g["out"], g["hands"], g["feet"]]
	check(absf(got["situp"]["hang"]) < 0.005 and absf(got["situp"]["roll"]) < 0.005 and got["situp"]["out"] < 0.03,
		"sit-up adventure stays neutral in a corner (%s)" % line.call("situp"))
	check(got["scratcher"]["hang"] > 0.08 and got["scratcher"]["roll"] > 0.12 and got["scratcher"]["out"] > 0.12,
		"the scratcher hangs off to the inside, knee out (%s)" % line.call("scratcher"))
	check(got["naked"]["out"] > 0.04 and got["naked"]["out"] < got["scratcher"]["out"] and got["naked"]["hang"] < got["scratcher"]["hang"],
		"naked: some knee out, less hanging off (%s)" % line.call("naked"))
	check(got["rossi"]["hang"] > 0.03 and got["rossi"]["out"] > 0.04, "Rossi hangs off a bit with the knee out (%s)" % line.call("rossi"))
	check(RiderStyle.STYLES.all(func(s): return absf(float(got[s]["outer_knee"])) < 0.01), "the outside knee stays in against the tank")
	check(RiderStyle.STYLES.all(func(s): return float(got[s]["hands"]) < 0.03 and float(got[s]["feet"]) < 0.03),
		"hands stay on the grips and feet on the pegs however they hang off (%s)" % ", ".join(RiderStyle.STYLES.map(func(s): return line.call(s))))
	# Left-handers mirror it.
	var m := _model("scratcher")
	_hold(m, -lean, 0.0, 20.0, 0.0)
	var p := m.rider_pose()
	check(float(p["hang"]) < -0.08 and float(p["knee"][-1.0]) > 0.3 and float(p["knee"][1.0]) < 0.01, "a left-hander hangs off and puts the left knee out")
	# The knee drops lower the further over, and at full lean it's on the road with sparks.
	var heights := []
	for l in [0.0, 0.3, 0.5, 0.7]:
		_hold(m, l, 0.0, 20.0, 0.0)
		heights.append(float(leg_now(m, 1.0, l)["height"]))
	check(heights[0] > heights[1] and heights[1] > heights[2] and heights[2] > heights[3], "the scratcher's knee gets lower and lower as the bike leans (%s m)" %
		", ".join(heights.map(func(h): return "%.2f" % h)))
	_hold(m, 0.85, 0.0, 22.0, 0.0)
	var down := leg_now(m, 1.0, 0.85)
	check(m.knee_down and absf(float(down["height"]) - BikeModel.SLIDER_GAP) < 0.01, "right over, the knee slider's on the road and no further (%.3f m)" % down["height"])
	check(m.sparks_flying() and m._sparks.position.distance_to(down["slider"]) < 0.02, "sparks fly off the slider")
	check(m._rider.find_children("KneeSlider", "MeshInstance3D", true, false).size() == 2, "the scratcher wears knee sliders")
	_hold(m, 0.85, 0.0, 2.0, 0.0, 0.5)
	check(not m.sparks_flying(), "no sparks at walking pace")
	_hold(m, 0.2, 0.0, 22.0, 0.0)
	check(not m.knee_down and not m.sparks_flying(), "and none when the knee's off the road")
	m.queue_free()
	for s in ["situp", "naked", "rossi"]:
		var o := _model(s)
		_hold(o, 0.85, 0.0, 22.0, 0.0)
		check(not o.knee_down and not o.sparks_flying(), "%s: no knee on the road" % s)
		o.queue_free()
	await t.get_tree().process_frame


## The Rossi leg comes out under hard braking into a corner, and goes back as the bike leans in.
func test_leg_out() -> void:
	var m := _model("rossi")
	_hold(m, -0.05, 0.0, 22.0, 1.0, 1.0)   # braking hard, just starting to lean left
	var p := m.rider_pose()
	var leg := leg_now(m, -1.0, -0.05)
	var peg: Vector3 = m._legs[-1.0]["peg"]
	var off: Vector3 = (leg["ankle"] as Vector3) - peg
	check(float(p["leg_out"]) > 0.9 and float(p["leg_side"]) == -1.0, "braking hard into a left-hander the left leg comes out (%.2f)" % p["leg_out"])
	check(off.x < -0.1 and off.z < -0.15 and off.length() > 0.25, "off the peg, forward and out (%.2f m out, %.2f forward)" % [-off.x, -off.z])
	check(feet_off(m, -0.05, -1.0) < 0.03 and hands_off(m) < 0.03, "the other foot stays on its peg and the hands on the bars")
	# Easing off the brakes and leaning in, it goes back on the peg.
	var outs := []
	for i in 5:
		_hold(m, -0.1 - 0.1 * i, 0.0, 18.0, 0.8 - 0.2 * i, 0.25)
		outs.append(float(m.rider_pose()["leg_out"]))
	check(outs[0] > outs[2] and outs[2] > outs[4], "back in as the braking eases and the lean comes in (%s)" % ", ".join(outs.map(func(o): return "%.2f" % o)))
	_hold(m, -0.55, 0.0, 18.0, 0.0, 1.5)
	check(float(m.rider_pose()["leg_out"]) < 0.02 and feet_off(m, -0.55) < 0.03, "and on the peg through the corner")
	_hold(m, 0.0, 0.0, 22.0, 0.15, 1.0)
	check(float(m.rider_pose()["leg_out"]) < 0.02, "a light brake doesn't put it out")
	_hold(m, 0.0, 0.0, 4.0, 1.0, 1.0)
	check(float(m.rider_pose()["leg_out"]) < 0.02, "nor stopping at low speed")
	m.queue_free()
	for s in ["situp", "scratcher", "naked"]:
		var o := _model(s)
		_hold(o, -0.05, 0.0, 22.0, 1.0, 1.0)
		check(float(o.rider_pose()["leg_out"]) < 0.001 and feet_off(o, -0.05) < 0.03, "%s keeps both feet on the pegs braking hard" % s)
		o.queue_free()
	check(RiderStyle.leg_out_target("rossi", 0.0, 22.0, 1.0) > 0.99 and RiderStyle.leg_out_target("rossi", 0.6, 22.0, 1.0) < 0.01
		and RiderStyle.leg_out_target("rossi", 0.0, 22.0, 0.0) == 0.0, "the leg's out braking hard upright, in leant over or off the brakes")
	await t.get_tree().process_frame


## The head turns into the corner, the right way, smoothly, more with speed; the shoulders a little.
func test_look() -> void:
	var was := Settings.look_into_corner
	Settings.look_into_corner = true
	var m := _model("situp")
	_hold(m, 0.5, 0.0, 20.0, 0.0)
	var right := m.corner_look()
	var f := head_forward(m)
	check(right < -0.25 and f.x > 0.2, "in a right-hander the head turns right, into the corner (%.2f rad, looking %.2f right)" % [right, f.x])
	check(absf(m._torso.basis.get_euler().y) > 0.03 and absf(m._torso.basis.get_rotation_quaternion().get_angle()) < absf(right) * 0.5,
		"the shoulders turn a little with it")
	var e := m.eye_transform()
	check((e.basis * Vector3.FORWARD).x > 0.1, "your first-person view looks into the corner too")
	# The head's held a bit nearer level than the bike.
	var up: Vector3 = (Basis(Vector3.FORWARD, 0.5) * m._rider.transform.basis * m._rider_head.basis) * Vector3.UP
	check(up.angle_to(Vector3.UP) < 0.5 - 0.1, "and held nearer level than the bike (%.2f rad off upright, the bike 0.5)" % up.angle_to(Vector3.UP))
	_hold(m, -0.5, 0.0, 20.0, 0.0)
	f = head_forward(m)
	check(m.corner_look() > 0.25 and f.x < -0.2, "and left in a left-hander (%.2f)" % m.corner_look())
	# Smooth: not straight there, and a wobble doesn't flick it.
	_hold(m, 0.0, 0.0, 20.0, 0.0)
	var start := m.corner_look()
	m.update_rider(0.6, 0.0, 20.0, 0.0, STEP)
	var one := absf(m.corner_look() - start)
	check(absf(start) < 0.01 and one < 0.05 and one > 0.0, "it eases round, not in one jump (%.3f rad in a step)" % one)
	_hold(m, 0.0, 0.0, 20.0, 0.0)
	for i in 120:
		m.update_rider(0.05 * sin(i * 0.9), 0.02 * sin(i * 1.3), 20.0, 0.0, STEP)
	check(absf(m.corner_look()) < 0.02, "small wobbles leave the head alone (%.3f)" % m.corner_look())
	# More with speed: none at walking pace on the lean alone.
	var by_speed := []
	for v in [2.0, 6.0, 12.0, 25.0]:
		_hold(m, 0.4, 0.0, v, 0.0)
		by_speed.append(absf(m.corner_look()))
	check(by_speed[0] < 0.05 and by_speed[1] < by_speed[2] and by_speed[2] <= by_speed[3] + 0.001,
		"it grows with speed (%s)" % ", ".join(by_speed.map(func(y): return "%.2f" % y)))
	# Turning tight at low speed on the bars, the head looks round the turn.
	_hold(m, 0.0, 0.4, 2.5, 0.0)
	check(m.corner_look() < -0.15, "a slow tight turn on the bars to the right looks right (%.2f)" % m.corner_look())
	check(RiderStyle.look_yaw(0.5, 0.0, 20.0) < 0.0 and RiderStyle.look_yaw(-0.5, 0.0, 20.0) > 0.0 and RiderStyle.look_yaw(0.03, 0.0, 20.0) == 0.0,
		"look_yaw: right is negative, left positive, a tiny lean nothing")
	m.queue_free()
	Settings.look_into_corner = was
	await t.get_tree().process_frame


## The Gameplay toggle: off, nobody looks into the corner; it's saved with the settings.
func test_toggle() -> void:
	var was := Settings.look_into_corner
	check(Settings.look_into_corner is bool, "looking into the corner is a setting")
	var m := _model("scratcher")
	Settings.look_into_corner = false
	_hold(m, 0.6, 0.0, 20.0, 0.0)
	check(absf(m.corner_look()) < 0.0001 and head_forward(m).x < 0.05 and m._rider_head.basis.get_euler().y == 0.0,
		"switched off, the head keeps looking ahead (%.3f)" % m.corner_look())
	check(float(m.rider_pose()["hang"]) > 0.05, "the riding style's pose carries on without it")
	Settings.look_into_corner = true
	_hold(m, 0.6, 0.0, 20.0, 0.0)
	check(m.corner_look() < -0.2, "back on, it turns in again")
	m.queue_free()
	# Saved and loaded with the other settings.
	var cfg := ConfigFile.new()
	Settings.look_into_corner = false
	Settings.save_settings()
	cfg.load(Settings.PATH)
	check(cfg.get_value("riding", "look_into_corner", true) == false, "it's saved in the settings file")
	Settings.look_into_corner = true
	Settings.load_settings()
	check(Settings.look_into_corner == false, "and loaded from it")
	Settings.look_into_corner = was
	Settings.save_settings()
	# On the Gameplay tab, on by default.
	var fresh: Node = load("res://scripts/settings.gd").new()
	check(fresh.get("look_into_corner") == true, "it's on by default")
	fresh.free()
	Shed.start_new("Tester", 5)
	var menu := MainMenu.new()
	t.add_child(menu)
	await t.get_tree().process_frame
	var box := menu.look_corner
	check(box != null and menu._gameplay.is_ancestor_of(box) and box.button_pressed == Settings.look_into_corner,
		"a check box for it on the Gameplay tab")
	box.button_pressed = not was
	check(Settings.look_into_corner == not was, "ticking it sets it")
	box.button_pressed = was
	# The rider style on the Profile tab.
	var pick := menu.rider_style
	check(pick != null and pick.item_count == 4 and pick.get_item_text(3) == "Rossi leg out", "a Rider style choice on the Profile tab")
	menu.queue_free()
	await t.get_tree().process_frame


## Your style saved in your profile, sent out in your summary, and drawn on your bike on every
## machine (a co-op client's bike from its snapshots too).
func test_save_and_sync() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_rider_style_test.json"
	DirAccess.remove_absolute(Progress.path)
	var real_pref := Settings.rider_style
	Settings.rider_style = ""
	Shed.start_new("Style Tester", 5)
	Progress.select("Style Tester")
	check(RiderGear.style_of(RiderGear.worn_of(Shed.me())) == "situp", "a new rider rides sit-up")
	var menu := MainMenu.new()
	t.add_child(menu)
	await t.get_tree().process_frame
	menu.pick_style("scratcher")
	check(RiderGear.style_of(RiderGear.worn_of(Shed.me())) == "scratcher", "picking a style on the Profile tab wears it")
	check(Progress.own_summary()["gear"]["style"] == "scratcher", "it goes out in your summary")
	Progress.save_profile()
	Progress.profile = {}
	Progress.select("Style Tester")
	check(RiderGear.style_of(RiderGear.worn_of(Shed.me())) == "scratcher", "kept in your profile")
	# Remembered as your preferred style: a brand new character (another save, someone else's
	# shed) rides that way too, and so does one that was saved riding another way.
	check(Settings.rider_style == "scratcher", "picking a style remembers it in the settings")
	Progress.use_profile({}, "Style Tester")
	check(RiderGear.style_of(RiderGear.worn_of(Shed.me())) == "scratcher", "a new save's character rides your preferred style")
	Progress.use_profile({"gear": {"worn": {"style": "rossi"}}}, "Style Tester")
	check(RiderGear.style_of(RiderGear.worn_of(Shed.me())) == "scratcher", "an older save takes your preferred style")
	Progress.release("Style Tester")
	Settings.rider_style = real_pref
	Settings.save_settings()
	menu.queue_free()
	# Someone else's summary: a real style kept, nonsense dropped.
	var clean: Dictionary = Progress._clean_summary({"gear": {"helmet": "helmet_sprint", "style": "rossi"}})["gear"]
	check(clean["style"] == "rossi" and RiderGear.style_of(clean) == "rossi", "a crewmate's style comes through their summary")
	clean = Progress._clean_summary({"gear": {"style": "flying"}})["gear"]
	check(not clean.has("style") and RiderGear.style_of(clean) == "situp", "a nonsense style in a summary is dropped")
	# Their bike, seen from their snapshots: sat in their style, leaning, braking and looking.
	var rb := RemoteBike.new()
	rb.rider_gear = RiderGear.clean_worn({"style": "rossi", "helmet": "helmet_pudding"})
	t.add_child(rb)
	rb.setup("Crew", BikeBuild.new({}), Color.RED)
	check(rb.model.rider_style() == "rossi", "their bike's rider sits in their style")
	var lean := Basis(Vector3.FORWARD, 0.5)   # leaned over to the right
	var snap := func(speed: float, braking: bool) -> PackedFloat32Array:
		var q := lean.get_rotation_quaternion()
		var s := PackedFloat32Array([0, 0, 0, q.x, q.y, q.z, q.w, 0, 0, -speed, 0.0, 0, 0, 0, 0, 3000, 0.3, 0, 0, 1, 0, 0, 3, 0, 1,
			1.0 if braking else 0.0, 0])
		return s
	for i in 60:
		rb.push_state(snap.call(20.0, false))
		await t.get_tree().physics_frame
	check(absf(RiderStyle.lean_of(lean) - 0.5) < 0.01, "their lean is read off their bike's roll")
	check(float(rb.model.rider_pose()["hang"]) > 0.02 and rb.model.corner_look() < -0.1, "hanging off and looking into their right-hander (%.2f, %.2f)" %
		[rb.model.rider_pose()["hang"], rb.model.corner_look()])
	check(RiderStyle.brake_from(8.0, true) == 1.0 and RiderStyle.brake_from(8.0, false) == 0.5 and RiderStyle.brake_from(-3.0, true) == 0.0,
		"their braking from how fast they slow, with the stop lamp")
	rb.model.redress(RiderGear.clean_worn({"style": "naked"}))
	check(rb.model.rider_style() == "naked", "a new style from their summary redraws them")
	rb.queue_free()
	Progress.save_profile()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)
	await t.get_tree().process_frame


## Every style on every kind of bike and in every helmet: built and posed sensibly, feet forward
## and sitting up more on a cruiser or chopper.
func test_all_bikes() -> void:
	var bad := []
	var hang := {}
	for bs in PartsDB.STYLES:
		for s in RiderStyle.STYLES:
			var m := _model(s, bs)
			if m._rider_head == null or m._legs.size() != 2 or m._arm_at.size() != 2 or m._torso == null:
				bad.append("%s on %s: not rigged" % [s, bs])
				m.queue_free()
				continue
			_hold(m, 0.55, 0.0, 18.0, 0.0, 1.5)
			var p := m.rider_pose()
			if s == "scratcher":
				hang[bs] = float(p["hang"])
			var lean_feet := feet_off(m, 0.55)
			_hold(m, 0.0, 0.0, 20.0, 1.0, 1.0)
			var hands := hands_off(m)
			if lean_feet > 0.04 or hands > 0.04:
				bad.append("%s on %s: feet %.3f, hands %.3f" % [s, bs, lean_feet, hands])
			if s == "rossi":
				var side := float(m.rider_pose()["leg_side"])   # the right, from the right-hander before
				var out := (leg_now(m, side, 0.0)["ankle"] as Vector3).distance_to(m._legs[side]["peg"])
				if out < (0.05 if m._laid_back else 0.1):
					bad.append("Rossi leg on %s only %.2f m off the peg" % [bs, out])
			m.queue_free()
		await t.get_tree().process_frame
	check(bad.is_empty(), "every rider style sits on every style of bike, hands on the bars and feet on the pegs %s" % str(bad))
	var chop := _model("scratcher", "chopper")
	var sport := _model("scratcher", "sport")
	check(chop._laid_back and not sport._laid_back, "a chopper's seating is feet forward, a sports bike's isn't")
	check(hang["chopper"] < hang["sport"] * 0.5 and hang["cruiser"] < hang["sport"] * 0.5,
		"a scratcher on a chopper or cruiser hangs off far less (%.2f, %.2f m against %.2f)" % [hang["chopper"], hang["cruiser"], hang["sport"]])
	var torso_up := func(m: BikeModel) -> float: return rad_to_deg(m._torso_axis.angle_to(Vector3.UP))
	check(float(torso_up.call(chop)) < float(torso_up.call(sport)) - 10.0, "and sits up more on it (%.0f against %.0f degrees)" % [torso_up.call(chop), torso_up.call(sport)])
	chop.queue_free()
	sport.queue_free()
	# Every helmet model, every style: the head's on its pivot and turns.
	var lids := []
	for id in RiderGear.ITEMS:
		if str(RiderGear.ITEMS[id]["slot"]) == "helmet":
			lids.append(id)
	var heads_bad := []
	var models := {}
	for id in lids:
		models[RiderGear.helmet_model(id)] = true
		for s in RiderStyle.STYLES:
			var m := _model(s, "naked", id)
			_hold(m, 0.5, 0.0, 20.0, 0.0, 1.0)
			if m._rider_head.get_child_count() == 0 or m.corner_look() > -0.2:
				heads_bad.append("%s %s" % [id, s])
			m.queue_free()
	check(models.size() >= 5 and heads_bad.is_empty(), "every helmet (%d models) turns into the corner in every style %s" % [models.size(), str(heads_bad)])
	await t.get_tree().process_frame
