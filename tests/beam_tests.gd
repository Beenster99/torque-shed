extends RefCounted
## The dipped beam (Simon: "The dipped beam needs to be more dipped"), run from tests/run_tests.gd
## (its _test_beam_* functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## How bright the dipped beam's cut-off lets through towards `angle_up` degrees above the middle of
## the cone (a spot light's projector is laid over the cone as tan(angle / 2)).
static func _through(tex: ImageTexture, angle_up: float) -> float:
	var img := tex.get_image()
	var y := clampi(int((0.5 - 0.5 * tan(deg_to_rad(angle_up) * 0.5)) * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(img.get_width() / 2, y).r


## How brightly the core lights a point `at` (in the effects' space), as far as its cut-off goes:
## 0 above the line, 1 below it.
static func _lit(core: SpotLight3D, at: Vector3) -> float:
	if core.light_projector == null:
		return 1.0
	var local := core.transform.affine_inverse() * at
	var up := rad_to_deg(atan2(local.y, -local.z))
	return _through(core.light_projector as ImageTexture, up)


## Dipped and main beam at night, side by side: dipped aims down at the near road with a sharp
## level cut-off (no light above it, so signs and trees further up the road stay dark) and its
## flood stops short; main beam is as it was, aimed nearly level and reaching far, no cut-off.
func test_dipped() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	t.add_child(sun)
	var dl := Daylight.new()
	t.add_child(dl)
	var cycle := Settings.day_night_cycle
	Settings.day_night_cycle = false
	dl.setup(env, sun)
	dl.set_time(0.0)
	var fx := BikeEffects.new()
	t.add_child(fx)
	# A lamp a metre up, at the front of the bike (-Z ahead).
	fx.setup(Vector3(0.2, 0.4, 0.8), Vector3(0.0, 0.0, 0.7), Vector3(0.0, 1.0, -0.8), 1000.0)
	var core: SpotLight3D = fx._beam
	var flood: SpotLight3D = fx._flood
	fx.beam_mode = 1
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	var lands := core.position.y / tan(-core.rotation.x)
	check(lands > 6.0 and lands < 16.0, "dipped, the middle of the beam lands %.1f m up the road (it was about 30 m)" % lands)
	check(core.light_projector is ImageTexture, "the dipped beam has a cut-off")
	var cut := BikeEffects.LOW_AIM - BikeEffects.LOW_CUTOFF
	var tex := core.light_projector as ImageTexture
	if tex:
		var below := _through(tex, cut - BikeEffects.CUTOFF_SOFT)
		var above := _through(tex, cut + BikeEffects.CUTOFF_SOFT)
		check(below > 0.95 and above < 0.05,
			"the cut-off is sharp: full light %.2f degrees below the line (%.2f), none %.2f degrees above it (%.2f)" % [BikeEffects.CUTOFF_SOFT, below, BikeEffects.CUTOFF_SOFT, above])
		check(_through(tex, -20.0) > 0.95 and _through(tex, 20.0) < 0.01, "lit all the way below the line, dark all the way above")
	# What it lights and what it doesn't, along a road from a lamp a metre up.
	var road_near := _lit(core, Vector3(0.0, 0.0, -10.0))
	var road_on := _lit(core, Vector3(0.0, 0.0, -30.0))
	var sign_far := _lit(core, Vector3(3.0, 2.4, -40.0))
	var tree_far := _lit(core, Vector3(-5.0, 4.0, -25.0))
	var sign_head := _lit(core, Vector3(3.0, 2.0, -15.0))
	check(road_near > 0.95 and road_on > 0.95, "it lights the road 10 m and 30 m ahead (%.2f, %.2f)" % [road_near, road_on])
	check(sign_far < 0.05 and tree_far < 0.05 and sign_head < 0.05,
		"but not a sign 40 m on (%.2f), a tree's crown 25 m on (%.2f) or a sign at head height 15 m on (%.2f)" % [sign_far, tree_far, sign_head])
	check(core.global_transform.basis.z.y > 0.0, "it's aimed down")
	var low_range := core.spot_range
	check(flood.spot_range <= 20.0 and flood.light_projector == null,
		"the flood round it only fills the near road and verges (%.0f m)" % flood.spot_range)
	check(low_range >= 50.0 and low_range <= 80.0, "the dipped beam reaches %.0f m along the road, no further" % low_range)
	# Main beam: as it was.
	fx.beam_mode = 2
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	check(core.light_projector == null and flood.light_projector == null, "main beam has no cut-off")
	check(is_equal_approx(core.rotation.x, deg_to_rad(-0.6)) and core.spot_range >= 180.0 and is_equal_approx(core.spot_angle, 20.0)
		and flood.spot_range >= core.spot_range * 0.85,
		"main beam is as it was: aimed nearly level, reaching %.0f m, the flood nearly as far" % core.spot_range)
	check(_lit(core, Vector3(3.0, 2.4, -40.0)) > 0.95, "and it lights the sign 40 m on")
	# And back to dipped.
	fx.beam_mode = 1
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	check(core.light_projector == tex and is_equal_approx(core.spot_range, low_range), "dipped again: the cut-off's back")
	Settings.day_night_cycle = cycle
	fx.queue_free()
	dl.queue_free()
	sun.queue_free()
	await t.get_tree().process_frame


## Riding: the headlight switch takes the real bike's beam from dipped to main and back, and the
## cut-off comes and goes with it; a stronger lamp's dipped beam still stops at the same line.
func test_ride() -> void:
	var r: Dictionary = await t.ride({"headlight": "led_projector"}, 0.3, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	bike.engine_on = true
	bike.beam = 1
	for i in 3:
		await t.get_tree().physics_frame
	var beam: SpotLight3D = bike.effects._beam
	var dipped_cut := beam != null and beam.light_projector != null
	check(dipped_cut and beam.rotation.x < deg_to_rad(-3.0), "riding on dipped beam: aimed down, with the cut-off")
	bike.cycle_beam()
	for i in 3:
		await t.get_tree().physics_frame
	check(bike.beam == 2 and beam.light_projector == null and beam.rotation.x > deg_to_rad(-1.0), "the switch to main beam: no cut-off, aimed level")
	bike.cycle_beam()
	bike.beam = 1
	bike.effects.beam_mode = 1
	for i in 3:
		await t.get_tree().physics_frame
	check(beam.light_projector != null and beam.rotation.x < deg_to_rad(-3.0), "back on dipped: the cut-off again")
	await t._done(r)
