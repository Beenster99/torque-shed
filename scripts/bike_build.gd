class_name BikeBuild
extends RefCounted
## A bike as a set of chosen parts in some condition, plus every stat the physics and the
## garage dashboards derive from them. Rust, dirt and wear on a part sap its performance.

const RIDER_MASS := 75.0
const FIXED_MASS := 48.0      # tank and fuel, seat, battery, electrics, bodywork, fluids
const AIR_DENSITY := 1.2
const DRIVETRAIN_EFFICIENCY := 0.92

var parts: Dictionary          # slot -> part id
var condition: Dictionary      # slot -> {rust, dirt, wear}, each 0 (as new) .. 1 (ruined)
var health := {}               # slot -> 0..1

# Chassis
var bike_mass := 0.0           # kg, without rider
var total_mass := 0.0          # kg, with rider
var wheelbase := 1.4
var com_height := 0.62         # centre of mass above the ground, m
var rake_deg := 25.0
var seat_height := 0.85
var frame_color := Color(0.1, 0.1, 0.1)
var cda := 0.55                # drag area, m^2

# Suspension
var front_travel := 0.13
var front_spring := 30000.0
var front_damping := 2600.0
var fork_length := 0.75
var rear_travel := 0.11
var rear_spring := 36000.0
var rear_damping := 2900.0

# Wheels
var front_radius := 0.3
var rear_radius := 0.31
var tyre_width := 0.16
var tyre_style := "road"
var grip := {}
var front_inertia := 0.6
var rear_inertia := 0.8

# Engine
var cylinders := 2
var displacement := 700.0
var peak_torque := 70.0
var peak_torque_rpm := 7000.0
var redline := 9500.0
var idle_rpm := 1300.0
var engine_color := Color(0.2, 0.2, 0.2)
var torque_mult := 1.0         # intake, exhaust and engine condition combined
var exhaust_loudness := 1.0

# Drivetrain
var primary := 2.9
var gear_ratios: Array = []
var final_drive := 3.5
var shift_time := 0.12
var drivetrain_efficiency := DRIVETRAIN_EFFICIENCY

# Brakes
var front_brake_torque := 1500.0
var rear_brake_torque := 550.0


func _init(build: Dictionary = {}, part_condition: Dictionary = {}) -> void:
	parts = PartsDB.sanitize_build(build)
	condition = part_condition
	_compute()


## How healthy a part is from its condition: worn internals hurt most, then rust, then grime.
static func part_health(cond: Dictionary) -> float:
	var h := 1.0 - 0.6 * float(cond.get("wear", 0.0)) - 0.35 * float(cond.get("rust", 0.0)) \
		- 0.12 * float(cond.get("dirt", 0.0))
	return clampf(h, 0.15, 1.0)


func _cond(slot: String, key: String) -> float:
	return float(condition.get(slot, {}).get(key, 0.0))


## Average health of all the parts, as a 0..1 rating.
func overall_health() -> float:
	var total := 0.0
	for slot in PartsDB.SLOTS:
		total += float(health.get(slot, 1.0))
	return total / PartsDB.SLOTS.size()


func _compute() -> void:
	var frame := PartsDB.get_part(parts["frame"])
	var fork := PartsDB.get_part(parts["fork"])
	var shock := PartsDB.get_part(parts["shock"])
	var wheels := PartsDB.get_part(parts["wheels"])
	var engine := PartsDB.get_part(parts["engine"])
	var gearbox := PartsDB.get_part(parts["gearbox"])
	var sprocket := PartsDB.get_part(parts["final_drive"])
	var brakes := PartsDB.get_part(parts["brakes"])
	var intake := PartsDB.get_part(parts["intake"])
	var exhaust := PartsDB.get_part(parts["exhaust"])
	for slot in PartsDB.SLOTS:
		health[slot] = part_health(condition.get(slot, {}))

	bike_mass = FIXED_MASS
	for slot in parts:
		bike_mass += float(PartsDB.get_part(parts[slot]).get("mass", 0.0))
	total_mass = bike_mass + RIDER_MASS

	wheelbase = frame["wheelbase"]
	com_height = frame["com_height"]
	rake_deg = frame["rake_deg"]
	seat_height = frame["seat_height"]
	frame_color = _color(frame["color"])
	cda = frame["cda"]

	front_travel = fork["travel"]
	front_spring = fork["spring"] * lerpf(0.85, 1.0, health["fork"])
	front_damping = fork["damping"] * lerpf(0.45, 1.0, health["fork"])
	fork_length = fork["length"]
	rear_travel = shock["travel"]
	rear_spring = shock["spring"] * lerpf(0.85, 1.0, health["shock"])
	rear_damping = shock["damping"] * lerpf(0.45, 1.0, health["shock"])

	front_radius = wheels["front_radius"]
	rear_radius = wheels["rear_radius"]
	tyre_width = wheels["width"]
	tyre_style = wheels["style"]
	grip = {}
	var grip_scale := lerpf(0.7, 1.0, health["wheels"])
	for surf in wheels["grip"]:
		grip[surf] = float(wheels["grip"][surf]) * grip_scale
	var wheel_mass: float = wheels["mass"] * 0.5
	front_inertia = 0.8 * wheel_mass * front_radius * front_radius
	rear_inertia = 0.8 * wheel_mass * rear_radius * rear_radius + 0.15  # plus spinning drivetrain

	cylinders = int(engine["cylinders"])
	displacement = engine["displacement"]
	peak_torque = displacement * float(engine["torque_per_cc"])
	peak_torque_rpm = float(engine["peak_torque_rpm"]) * float(intake["peak_shift"])
	redline = engine["redline"]
	idle_rpm = engine["idle_rpm"]
	engine_color = _color(engine["color"])
	# Clogged filters and rotten pipes rob power; so does a tired engine.
	var intake_flow := 1.0 - 0.2 * clampf(_cond("intake", "dirt") * float(intake["dirt_sensitivity"]), 0.0, 1.0)
	torque_mult = float(intake["torque_mult"]) * intake_flow * lerpf(0.85, 1.0, health["intake"])
	torque_mult *= float(exhaust["torque_mult"]) * (1.0 - 0.15 * _cond("exhaust", "rust")) * lerpf(0.9, 1.0, health["exhaust"])
	torque_mult *= lerpf(0.55, 1.0, health["engine"])
	peak_torque *= torque_mult
	exhaust_loudness = float(exhaust["loudness"])

	primary = gearbox["primary"]
	gear_ratios = gearbox["ratios"]
	final_drive = float(sprocket["rear"]) / float(sprocket["front"])
	shift_time = float(gearbox.get("shift_time", 0.12))
	drivetrain_efficiency = DRIVETRAIN_EFFICIENCY * lerpf(0.8, 1.0, health["gearbox"]) * lerpf(0.88, 1.0, health["final_drive"])

	var brake_health: float = lerpf(0.5, 1.0, health["brakes"])
	front_brake_torque = float(brakes["front_torque"]) * brake_health
	rear_brake_torque = float(brakes["rear_torque"]) * brake_health


func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2])


func gear_count() -> int:
	return gear_ratios.size()


## Overall reduction from crank to rear wheel in the given gear (1-based).
func overall_ratio(gear: int) -> float:
	var g := clampi(gear, 1, gear_count())
	return primary * float(gear_ratios[g - 1]) * final_drive


## Full-throttle crank torque in Nm at the given rpm.
func engine_torque(rpm: float) -> float:
	if rpm > redline * 1.02:
		return 0.0
	var x := (rpm - peak_torque_rpm) / peak_torque_rpm
	var shape := 1.0 - 0.7 * x * x
	return peak_torque * clampf(shape, 0.3, 1.0)


func engine_power_kw(rpm: float) -> float:
	return engine_torque(rpm) * rpm * TAU / 60.0 / 1000.0


func peak_power() -> Dictionary:
	var best := {"kw": 0.0, "rpm": 0.0}
	var rpm := idle_rpm
	while rpm <= redline:
		var kw := engine_power_kw(rpm)
		if kw > best["kw"]:
			best = {"kw": kw, "rpm": rpm}
		rpm += 50.0
	return best


## Torque and power sampled from idle to redline, for the dyno graph.
func dyno_curve(samples := 60) -> Array:
	var out := []
	for i in samples + 1:
		var rpm := lerpf(idle_rpm, redline, float(i) / samples)
		out.append({"rpm": rpm, "torque": engine_torque(rpm), "kw": engine_power_kw(rpm)})
	return out


## Estimated top speed in m/s: the highest speed where wheel power still beats drag and rolling resistance.
func top_speed_estimate() -> float:
	var best := 0.0
	for gear in range(1, gear_count() + 1):
		var ratio := overall_ratio(gear)
		var rpm := idle_rpm * 2.0
		while rpm <= redline:
			var v := rpm / ratio * TAU / 60.0 * rear_radius
			var drive := engine_torque(rpm) * ratio * drivetrain_efficiency / rear_radius
			var resist := 0.5 * AIR_DENSITY * cda * v * v + 0.015 * total_mass * 9.81
			if drive >= resist:
				best = maxf(best, v)
			rpm += 50.0
	return best


func hp() -> float:
	return peak_power()["kw"] * 1.341


func to_dict() -> Dictionary:
	return parts.duplicate()


## Headline numbers for dashboards and part comparisons.
func summary() -> Dictionary:
	return {
		"hp": hp(),
		"torque": peak_torque,
		"top_kmh": top_speed_estimate() * 3.6,
		"mass": bike_mass,
		"health": overall_health(),
		"brake": front_brake_torque + rear_brake_torque,
		"grip": float(grip.get("tarmac", 1.0)),
	}
