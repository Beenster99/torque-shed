extends RefCounted
## The dashboards' trip computer, ride modes and cruise control, run from tests/run_tests.gd (its
## _test_dash_* functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## Every dash shows the gear, the trip, the fuel economy and the range; the colour TFTs add cruise
## control and ride modes, and the parts computer says so.
func test_catalogue() -> void:
	var cruise := 0
	var modes := 0
	for id in PartsDB.by_kind["dashboard"]:
		var f: Array = PartsDB.get_part(str(id))["features"]
		check(["speed", "gear", "trip", "economy", "range"].all(func(x): return f.has(x)), "%s shows the gear, trip, mpg and range %s" % [PartsDB.part_name(id), f])
		cruise += int(f.has("cruise"))
		modes += int(f.has("modes"))
	check(cruise >= 3 and modes >= 4 and cruise < PartsDB.by_kind["dashboard"].size(), "some dashes have cruise control (%d) and ride modes (%d), not all" % [cruise, modes])
	check(PartsDB.spec_line("tft_colour").contains("cruise control") and PartsDB.spec_line("tft_colour").contains("ride modes"),
		"the shop lists them: %s" % PartsDB.spec_line("tft_colour"))


## Ride modes need a dash with them and an ECU with aids. Sport lets the aids in least, all the
## power through and the back wheel's ABS off; Wet the aids in hardest, the power cut back and the
## throttle softened; Custom is the dyno desk's own levels. Ridden flat out, Wet is slower.
func test_modes() -> void:
	var plain := BikeBuild.new({"dashboard": "tft_colour", "ecu": "stock_ecu"})
	plain.ride_mode = "wet"
	check(not plain.has_ride_modes() and plain.mode_power() == 1.0, "no rider aids on the ECU: no ride modes")
	var b := BikeBuild.new({"dashboard": "tft_colour", "ecu": "sport_ecu"})
	check(b.has_ride_modes(), "a TFT dash on an ECU with aids has ride modes")
	var custom := b.aid_strength("traction")
	b.ride_mode = "sport"
	var sport := [b.aid_strength("traction"), b.aid_strength("anti_wheelie"), b.mode_power(), b.abs_on(false), b.abs_on(true)]
	b.ride_mode = "wet"
	var wet := [b.aid_strength("traction"), b.aid_strength("anti_wheelie"), b.mode_power(), b.abs_on(false), b.mode_throttle_rate()]
	check(float(sport[0]) < float(wet[0]) and float(sport[1]) < float(wet[1]), "Wet steps in harder than Sport (traction %.2f vs %.2f)" % [wet[0], sport[0]])
	check(float(sport[2]) == 1.0 and float(wet[2]) < 0.8 and float(wet[4]) > 0.0, "Sport has all the power, Wet less and a softer throttle")
	check(not sport[3] and sport[4] and wet[3], "Sport lets the back wheel lock (front ABS still on); Wet looks after both")
	b.ride_mode = ""
	check(b.aid_strength("traction") == custom and BikeBuild.mode_name("") == "Custom", "Custom is the dyno desk's levels")
	check(BikeBuild.new({"dashboard": "analog_speedo", "ecu": "sport_ecu"}).has_ride_modes() == false, "an analogue clock has no modes")
	var tops := {}
	for mode in ["sport", "wet"]:
		var r: Dictionary = await t.ride({"dashboard": "tft_colour", "ecu": "sport_ecu"}, 6.0, func(bike: Bike, _tm):
			bike.build.ride_mode = mode
			bike.throttle = 1.0)
		tops[mode] = r["bike"].speed
		await t._done(r)
	check(tops["wet"] < tops["sport"] * 0.95, "flat out for 6 s, Wet gets to %.0f km/h and Sport to %.0f" % [tops["wet"] * 3.6, tops["sport"] * 3.6])
	# The mode stays with the bike.
	Shed.start_new("Tester", 5)
	var bike_id: int = t._bike_named("Old Faithful")
	Shed.bikes[bike_id]["rider"] = Shed.me()
	Shed.request({"a": "ride_mode", "bike": bike_id, "mode": "tour"})
	check(Shed.mode_of(bike_id) == "tour" and Shed.build_of(bike_id).ride_mode == "tour", "the dash's mode is kept with the bike")
	Shed.bikes[bike_id]["rider"] = 0
	Shed.stop()


## Cruise control holds the speed it's set at with the throttle let go, and the brake cancels it.
## A dash without it says so.
func test_cruise() -> void:
	var st := {"set": false, "said": "?", "held": []}   # (a lambda's own locals don't last between calls)
	var r: Dictionary = await t.ride({"dashboard": "tft_colour"}, 14.0, func(bike: Bike, tm: float):
		if tm < 5.0:
			bike.throttle = 0.6 if bike.speed < 22.0 else 0.0
		elif not st["set"]:
			st["said"] = bike.toggle_cruise()
			st["set"] = true
			bike.throttle = 0.0
		elif tm > 8.0 and tm < 12.0:
			st["held"].append(bike.speed)
		elif tm >= 12.5:
			bike.front_brake = 0.5)
	var held: Array = st["held"]
	var said: String = st["said"]
	var bike: Bike = r["bike"]
	var lo: float = held.min() if not held.is_empty() else 0.0
	var hi: float = held.max() if not held.is_empty() else 0.0
	check(said == "" and lo > 18.0 and hi - lo < 1.5, "set at about 80 km/h with the throttle shut, it holds %.0f to %.0f km/h" % [lo * 3.6, hi * 3.6])
	check(bike.cruise_speed == 0.0, "the brake cancels it")
	await t._done(r)
	var r2: Dictionary = await t.ride({"dashboard": "analog_speedo"}, 0.2, func(_b, _t): pass)
	check(r2["bike"].toggle_cruise().contains("no cruise"), "an analogue clock has no cruise control")
	await t._done(r2)
