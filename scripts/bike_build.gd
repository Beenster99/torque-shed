class_name BikeBuild
extends RefCounted
## A bike as a set of chosen parts in some condition, plus every stat the physics and the
## garage dashboards derive from them. Rust, dirt and wear on a part sap its performance,
## and engine parts have to suit each other: a big engine needs enough fuel and cooling.

const RIDER_MASS := 75.0
const FIXED_MASS := 39.0      # battery, wiring, lights, bodywork, fluids
const FUEL_DENSITY := 0.74    # kg per litre; tanks are taken as half full
const AIR_DENSITY := 1.2
const DRIVETRAIN_EFFICIENCY := 0.92

var parts: Dictionary          # slot -> part id
var condition: Dictionary      # slot -> {rust, dirt, wear, color}, each 0 (as new) .. 1 (ruined)
var health := {}               # slot -> 0..1
var notes: Array[String] = []  # problems with how the parts suit each other

# Chassis
var bike_mass := 0.0           # kg, without rider
var total_mass := 0.0          # kg, with rider
var wheelbase := 1.4
var com_height := 0.62         # centre of mass above the ground, m
var rake_deg := 25.0
var seat_height := 0.85
var cda := 0.55                # drag area, m^2
var steer_rate := 4.0          # how quickly the bars turn, rad/s; wider bars give more leverage
var fuel_capacity := 15.0
var dash_features: Array = ["speed"]

# Suspension
var front_travel := 0.13
var front_spring := 30000.0
var front_bump := 2100.0       # compression damping
var front_rebound := 3100.0    # extension damping
var fork_length := 0.75
var rear_travel := 0.11
var rear_spring := 36000.0
var rear_bump := 2300.0
var rear_rebound := 3500.0

# Wheels and tyres
var front_radius := 0.3
var rear_radius := 0.31
var front_rim_radius := 0.22
var rear_rim_radius := 0.22
var front_tyre_width := 0.12
var rear_tyre_width := 0.16
var tyre_style := "road"
var grip := {}                 # average of both tyres, for dashboards
var grip_front := {}
var grip_rear := {}
var front_inertia := 0.6
var rear_inertia := 0.8

# Engine
var cylinders := 2
var layout := "parallel"
var displacement := 700.0
var peak_torque := 70.0
var peak_torque_rpm := 7000.0
var redline := 9500.0
var idle_rpm := 1300.0
var torque_mult := 1.0         # every engine part and its condition combined
var exhaust_loudness := 1.0
var engine_heat := 0.7
var cooling_capacity := 1.0

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


func part(slot: String) -> Dictionary:
	return PartsDB.get_part(parts[slot])


## Average health of all the parts, as a 0..1 rating.
func overall_health() -> float:
	var total := 0.0
	for slot in PartsDB.SLOTS:
		total += float(health.get(slot, 1.0))
	return total / PartsDB.SLOTS.size()


func _compute() -> void:
	notes.clear()
	for slot in PartsDB.SLOTS:
		health[slot] = part_health(condition.get(slot, {}))
	var frame := part("frame")
	var fork := part("fork")
	var shock := part("shock")
	var block := part("engine")
	var head := part("head")
	var tank := part("tank")
	var saddle := part("saddle")
	var bars := part("handlebars")

	cylinders = int(block["cylinders"])
	bike_mass = FIXED_MASS + float(tank["capacity"]) * FUEL_DENSITY * 0.5
	for slot in parts:
		var p := part(slot)
		bike_mass += float(p.get("mass", float(p.get("mass_per_cyl", 0.0)) * cylinders))
	total_mass = bike_mass + RIDER_MASS

	wheelbase = frame["wheelbase"]
	com_height = frame["com_height"]
	rake_deg = frame["rake_deg"]
	seat_height = float(frame["seat_height"]) + float(saddle["height"])
	cda = float(frame["cda"]) + float(bars["cda"])
	steer_rate = 4.0 * float(bars["width"]) / 720.0
	fuel_capacity = tank["capacity"]
	dash_features = part("dashboard")["features"]

	front_travel = fork["travel"]
	front_spring = fork["spring"] * lerpf(0.85, 1.0, health["fork"])
	front_bump = fork["bump"] * lerpf(0.45, 1.0, health["fork"])
	front_rebound = fork["rebound"] * lerpf(0.45, 1.0, health["fork"])
	fork_length = fork["length"]
	rear_travel = shock["travel"]
	rear_spring = shock["spring"] * lerpf(0.85, 1.0, health["shock"])
	rear_bump = shock["bump"] * lerpf(0.45, 1.0, health["shock"])
	rear_rebound = shock["rebound"] * lerpf(0.45, 1.0, health["shock"])

	_compute_wheels()
	_compute_engine(block, head)
	_compute_brakes()

	var gearbox := part("gearbox")
	var sprocket := part("final_drive")
	primary = gearbox["primary"]
	gear_ratios = gearbox["ratios"]
	final_drive = float(sprocket["rear"]) / float(sprocket["front"])
	shift_time = float(gearbox.get("shift_time", 0.12))
	drivetrain_efficiency = DRIVETRAIN_EFFICIENCY * lerpf(0.8, 1.0, health["gearbox"]) * lerpf(0.88, 1.0, health["final_drive"])


func _compute_wheels() -> void:
	var tf := part("front_tyre")
	var tr := part("rear_tyre")
	var wf := part("front_wheel")
	var wr := part("rear_wheel")
	front_rim_radius = float(wf["diameter"]) * 0.0127
	rear_rim_radius = float(wr["diameter"]) * 0.0127
	front_tyre_width = float(tf["width"]) * 0.7 / 1000.0
	rear_tyre_width = float(tr["width"]) / 1000.0
	front_radius = front_rim_radius + front_tyre_width * float(tf["aspect"])
	rear_radius = rear_rim_radius + rear_tyre_width * float(tr["aspect"])
	tyre_style = tr["style"]
	grip_front = {}
	grip_rear = {}
	grip = {}
	var scale_f := lerpf(0.7, 1.0, health["front_tyre"]) * lerpf(0.92, 1.0, health["front_wheel"])
	var scale_r := lerpf(0.7, 1.0, health["rear_tyre"]) * lerpf(0.92, 1.0, health["rear_wheel"])
	for surf in tr["grip"]:
		grip_front[surf] = float(tf["grip"][surf]) * scale_f
		grip_rear[surf] = float(tr["grip"][surf]) * scale_r
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	var mass_f := float(wf["mass"]) + float(tf["mass"])
	var mass_r := float(wr["mass"]) + float(tr["mass"])
	front_inertia = 0.8 * mass_f * front_radius * front_radius
	rear_inertia = 0.8 * mass_r * rear_radius * rear_radius + 0.15  # plus spinning drivetrain


func _compute_engine(block: Dictionary, head: Dictionary) -> void:
	var fuel := part("fuel")
	var air := part("air_filter")
	var oil := part("oil_filter")
	var plugs := part("spark_plugs")
	var cooling := part("cooling")
	var exhaust := part("exhaust")
	layout = block["layout"]
	displacement = block["displacement"]
	peak_torque = displacement * float(block["torque_per_cc"])
	peak_torque_rpm = float(block["peak_torque_rpm"]) * float(head["peak_shift"]) * float(fuel["peak_shift"])
	redline = float(block["redline"]) + float(head["redline_add"])
	idle_rpm = block["idle_rpm"]

	torque_mult = float(head["torque_mult"]) * lerpf(0.75, 1.0, health["head"])
	# The fuel system has to keep up with the engine, or it runs lean and gutless.
	var demand := displacement * float(head["peak_shift"])
	var flow := float(fuel["flow"]) * lerpf(0.8, 1.0, health["fuel"])
	torque_mult *= float(fuel["torque_mult"])
	if flow < demand:
		torque_mult *= maxf(0.7, lerpf(1.0, flow / demand, 0.6))
		notes.append("Fuel starved: the %s can't feed %d cc." % [str(fuel["name"]).to_lower(), int(displacement)])
	# Clogged filters rob power.
	var clog := clampf(_cond("air_filter", "dirt") * float(air["dirt_sensitivity"]), 0.0, 1.0)
	torque_mult *= float(air["flow"]) * (1.0 - 0.2 * clog) * lerpf(0.9, 1.0, health["air_filter"])
	if clog > 0.5:
		notes.append("Air filter is clogged.")
	# Worn plugs misfire; how fast they wear out depends on the plug.
	var plug_health := clampf(1.0 - (1.0 - float(health["spark_plugs"])) / float(plugs["life"]), 0.0, 1.0)
	torque_mult *= float(plugs["torque_mult"]) * lerpf(0.72, 1.0, plug_health)
	if plug_health < 0.5:
		notes.append("Misfiring: the spark plugs are worn out.")
	# A tired engine is weaker, and a poor oil filter lets it suffer more.
	var protection := float(oil["protection"]) * lerpf(0.5, 1.0, health["oil_filter"])
	var block_health: float = 1.0 - (1.0 - float(health["engine"])) * (1.4 - 0.5 * protection)
	torque_mult *= lerpf(0.55, 1.0, clampf(block_health, 0.0, 1.0))
	# Hot heads need cooling to match.
	engine_heat = displacement / 1000.0 * float(head["heat"])
	cooling_capacity = float(cooling["capacity"]) * lerpf(0.6, 1.0, health["cooling"])
	if engine_heat > cooling_capacity:
		torque_mult *= maxf(0.8, 1.0 - (engine_heat - cooling_capacity) * 0.4)
		notes.append("Runs hot: the %s can't cope." % str(cooling["name"]).to_lower())
	# Rotten pipes leak and lose power.
	torque_mult *= float(exhaust["torque_mult"]) * (1.0 - 0.15 * _cond("exhaust", "rust")) * lerpf(0.9, 1.0, health["exhaust"])
	peak_torque *= torque_mult
	exhaust_loudness = float(exhaust["loudness"])


func _side_brake(side: String) -> float:
	var disc := part(side + "_disc")
	var caliper := part(side + "_caliper")
	var pads := part(side + "_pads")
	var master := part(side + "_master")
	var h := 0.0
	for s in ["disc", "caliper", "pads", "master"]:
		h += float(health[side + "_" + s]) * (0.4 if s == "pads" else 0.2)
	return 1600.0 * float(disc["diameter"]) / 300.0 * float(caliper["force"]) * float(pads["mu"]) / 0.42 \
		* float(master["ratio"]) * lerpf(0.5, 1.0, h)


func _compute_brakes() -> void:
	front_brake_torque = _side_brake("front")
	rear_brake_torque = _side_brake("rear") * 0.7


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
