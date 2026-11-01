extends RefCounted
## The Rig built look's lines and its bike rig (BikeRig), run from tests/run_tests.gd: its
## _test_bike_rig_* functions hand over to these. data/bike_lines.json holds the eight lines of
## each style's reference bike (see /mnt/project-files/torque-shed/bike-look/lines-agreement.md).

var t: Node

const LINES := "res://data/bike_lines.json"
const LINE_KEYS := ["1_backbone", "2_tank", "3_tank_seat", "4_seat", "5_rider", "6_drive", "7_front", "8_ground"]
## How far a stock bike's catalogue numbers may sit from its reference bike's published ones.
const WHEELBASE_TOL := 0.06   # m
const SEAT_TOL := 0.05        # m
const RAKE_TOL := 4.5         # degrees
## Choppers are customs: built longer and more raked than any factory one.
const CUSTOM_LONG := ["chopper"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func lines() -> Dictionary:
	var f := FileAccess.open(LINES, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d.get("styles", {}) if d is Dictionary else {}


## Every style has its reference bike and all eight lines, and the stock bike's wheelbase, seat
## height and rake (the catalogue's, which both looks and the riding share) are the reference's.
func test_lines_table() -> void:
	var styles := lines()
	check(not styles.is_empty(), "data/bike_lines.json loads")
	for style in PartsDB.STYLES:
		var s: Dictionary = styles.get(style, {})
		check(not str(s.get("reference", "")).is_empty(), "the %s has a reference bike" % style)
		var l: Dictionary = s.get("lines", {})
		var missing := LINE_KEYS.filter(func(k): return not l.has(k))
		check(missing.is_empty(), "the %s has all eight lines (missing %s)" % [style, missing])
		if s.is_empty():
			continue
		var pub: Dictionary = s["published"]
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
		var wb := float(pub["wheelbase_mm"]) / 1000.0
		if style in CUSTOM_LONG:
			check(build.wheelbase >= wb - WHEELBASE_TOL, "the stock %s is at least as long as a %s (%.2f m)" % [style, s["reference"], build.wheelbase])
		else:
			check(absf(build.wheelbase - wb) <= WHEELBASE_TOL,
				"the stock %s's wheelbase %.3f m is a %s's %.3f" % [style, build.wheelbase, s["reference"], wb])
			check(absf(build.rake_deg - float(pub["rake_deg"])) <= RAKE_TOL,
				"the stock %s's rake %.1f deg is a %s's %.1f" % [style, build.rake_deg, s["reference"], float(pub["rake_deg"])])
		check(absf(build.seat_height - float(pub["seat_mm"]) / 1000.0) <= SEAT_TOL,
			"the stock %s's seat %.2f m is a %s's %.2f" % [style, build.seat_height, s["reference"], float(pub["seat_mm"]) / 1000.0])
		var u := [l["3_tank_seat"]["tank_rear_u"], l["4_seat"]["front_u"], l["4_seat"]["rider_u"]]
		check(u.all(func(x): return float(x) > 0.2 and float(x) < 0.9), "the %s's lines sit between the wheels" % style)
