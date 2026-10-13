class_name BikeBuild
extends RefCounted
## A bike as a set of chosen parts in some condition, plus every stat the physics and the
## garage dashboards derive from them. Rust, dirt and wear on a part sap its performance,
## and engine parts have to suit each other: a big engine needs enough fuel and cooling.
## Fluids count too: the petrol in the tank, the oil in the engine and the brake fluid in each
## master cylinder, how much there is and how old it is. A part's condition can carry its
## "fluid" as {type, litres, age}; without one the bike is taken as freshly serviced.

const RIDER_MASS := 75.0
const FIXED_MASS := 39.0      # battery, wiring, lights, bodywork, fluids
const FUEL_DENSITY := 0.74    # kg per litre
const OIL_DENSITY := 0.87
## Litres of petrol per kWh at the crank, and the engine's own thirst ticking over per litre of capacity.
const FUEL_PER_KWH := 0.5
const IDLE_FUEL_PER_LITRE := 0.9   # litres an hour
const AIR_DENSITY := 1.2
const DRIVETRAIN_EFFICIENCY := 0.92
const ROLLING := 0.015

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
var headlight_lumens := 0.0    # 0 with no headlight fitted
var fog_lumens := 0.0          # 0 with no fog lights
var fog_color := Color(1.0, 0.92, 0.78)
var horn_tones: Array = []     # frequencies of the horn, empty with none fitted
var horn_style := ""
var horn_loudness := 0.0
var ecu_features: Array = []   # rider aids the ECU gives: traction, abs, anti_wheelie, stability
var ecu_aid := 0.0             # how firmly those aids step in, 0..1
var luggage_litres := 0.0
var gear_whine := 0.3          # how loudly the gearbox sings
var has_side_stand := false
var has_centre_stand := false
var centre_lift := 0.04

# Fluids
var fuel_litres := 0.0
var fuel_type := "unleaded_95"
var fuel_age := 0.0            # 0 fresh .. 1 stale, gummed-up petrol
var oil_capacity := 2.5
var oil_litres := 2.5
var oil_age := 0.0             # 0 fresh .. 1 black sludge
var oil_type := "semi_10w40"
var oil_protection := 0.88     # how well the oil looks after the engine, 0..1
var brake_fluid := {"front": 1.0, "rear": 1.0}   # how full each side's master cylinder is, 0..1
var economy_mult := 1.0        # how far each litre goes: fuel grade, tune and condition

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
var chain_slack := 30.0        # mm of free play in the chain
var chain_lube := 1.0          # 0 bone dry .. 1 freshly lubed

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


func has_part(slot: String) -> bool:
	return parts.get(slot, "none") != "none"


## The fluid in a slot's part as {type, litres, age}. Unknown means full and fresh.
func _fluid(slot: String, default_type: String, capacity: float) -> Dictionary:
	var f = condition.get(slot, {}).get("fluid", null)
	if f is Dictionary and f.has("litres"):
		var t := str(f.get("type", ""))
		return {"type": t if t != "" else default_type, "litres": clampf(float(f["litres"]), 0.0, capacity),
			"age": clampf(float(f.get("age", 0.0)), 0.0, 1.0)}
	return {"type": default_type, "litres": capacity, "age": 0.0}


func part(slot: String) -> Dictionary:
	return PartsDB.get_part(parts[slot])


## Average health of all the parts, as a 0..1 rating.
func overall_health() -> float:
	var total := 0.0
	var n := 0
	for slot in PartsDB.SLOTS:
		if has_part(slot):
			total += float(health.get(slot, 1.0))
			n += 1
	return total / maxf(n, 1)


func _compute() -> void:
	notes.clear()
	for slot in PartsDB.SLOTS:
		health[slot] = part_health(condition.get(slot, {})) if has_part(slot) else 1.0
	var frame := part("frame")
	var fork := part("fork")
	var shock := part("shock")
	var block := part("engine")
	var head := part("head")
	var tank := part("tank")
	var saddle := part("saddle")
	var bars := part("handlebars")

	cylinders = int(block["cylinders"])
	fuel_capacity = tank["capacity"]
	var fuel := _fluid("tank", "unleaded_95", fuel_capacity)
	fuel_litres = fuel["litres"]
	fuel_type = fuel["type"]
	fuel_age = fuel["age"]
	oil_capacity = PartsDB.fluid_capacity(parts["engine"])
	var oil := _fluid("engine", "semi_10w40", oil_capacity)
	oil_litres = oil["litres"]
	oil_age = oil["age"]
	oil_type = oil["type"]
	var oil_part := PartsDB.get_part(oil["type"])
	oil_protection = float(oil_part.get("protection", 0.8)) * lerpf(1.0, 0.55, oil_age)
	bike_mass = FIXED_MASS + fuel_litres * FUEL_DENSITY + oil_litres * OIL_DENSITY
	for slot in parts:
		var p := part(slot)
		bike_mass += float(p.get("mass", float(p.get("mass_per_cyl", 0.0)) * cylinders))
	total_mass = bike_mass + RIDER_MASS

	wheelbase = frame["wheelbase"]
	com_height = frame["com_height"]
	rake_deg = frame["rake_deg"]
	seat_height = float(frame["seat_height"]) + float(saddle["height"])
	cda = float(frame["cda"]) + float(bars["cda"]) + float(part("panniers").get("cda", 0.0)) + float(part("top_box").get("cda", 0.0))
	luggage_litres = float(part("panniers").get("litres", 0.0)) + float(part("top_box").get("litres", 0.0))
	steer_rate = 4.0 * float(bars["width"]) / 720.0
	# A fat front tyre is slower to turn in.
	steer_rate *= clampf(1.0 - 0.3 * (float(part("front_tyre")["width"]) - 160.0) / 160.0, 0.85, 1.12)
	dash_features = part("dashboard")["features"]
	headlight_lumens = float(part("headlight").get("lumens", 0.0)) * lerpf(0.6, 1.0, health.get("headlight", 1.0))
	var fog := part("fog_lights")
	fog_lumens = float(fog.get("lumens", 0.0)) * lerpf(0.6, 1.0, health.get("fog_lights", 1.0))
	if fog.has("beam"):
		fog_color = _color(fog["beam"])
	var horn := part("horn")
	horn_tones = horn.get("tones", [])
	horn_style = str(horn.get("style", ""))
	horn_loudness = float(horn.get("loudness", 0.0)) * lerpf(0.5, 1.0, health.get("horn", 1.0))
	var ecu := part("ecu")
	ecu_features = ecu.get("features", []).filter(func(f): return f != "remap")
	ecu_aid = float(ecu.get("aid_level", 0.0)) * lerpf(0.5, 1.0, health.get("ecu", 1.0))
	has_side_stand = has_part("side_stand")
	has_centre_stand = has_part("centre_stand")
	centre_lift = float(part("centre_stand").get("lift", 0.04))

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
	gear_whine = float(gearbox.get("whine", 0.3))
	drivetrain_efficiency = DRIVETRAIN_EFFICIENCY * lerpf(0.8, 1.0, health["gearbox"]) * lerpf(0.88, 1.0, health["final_drive"])
	_compute_chain()


## The chain soaks up some power on its own; a dry one more, and a slack or tight one more again.
func _compute_chain() -> void:
	var chain := part("chain")
	var c: Dictionary = condition.get("chain", {})
	chain_slack = clampf(float(c.get("slack", 30.0)), 5.0, 90.0)
	chain_lube = clampf(float(c.get("lube", 1.0)), 0.0, 1.0)
	var loss := float(chain.get("friction", 0.025)) * (1.0 + (1.0 - chain_lube) * 2.5)
	if chain_slack > 40.0:
		loss += (chain_slack - 40.0) * 0.0012
		notes.append("The chain is slapping about: tighten it (crouch, wrench, right mouse)." if chain_slack < 65.0
			else "The chain is so slack it could jump off! Tighten it.")
	elif chain_slack < 20.0:
		loss += (20.0 - chain_slack) * 0.002
		notes.append("The chain is too tight and will wear the sprockets. Slacken it off.")
	if chain_lube < 0.3:
		notes.append("The chain is dry and rusty-sounding. Give it some chain lube.")
	drivetrain_efficiency *= (1.0 - loss) * lerpf(0.9, 1.0, health["chain"])


## Power per kilo with the rider on: the number weight-saving parts improve.
## Whether the ECU gives this rider aid: "traction", "abs", "anti_wheelie" or "stability".
func has_aid(aid: String) -> bool:
	return ecu_features.has(aid)


func power_to_weight() -> float:
	return hp() / maxf(total_mass, 1.0)


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
	# Section width: a wider tyre lays more rubber on tarmac, a narrow one cuts into mud. And it has
	# to suit the rim it's on, or it's pinched or ballooned and the contact patch suffers.
	var fit_f := rim_fit(front_tyre_width * 1000.0, float(wf.get("rim_width", 3.5)))
	var fit_r := rim_fit(rear_tyre_width * 1000.0, float(wr.get("rim_width", 4.5)))
	for fit in [[fit_f, "front", tf, wf], [fit_r, "rear", tr, wr]]:
		if fit[0] != 0:
			notes.append("The %s tyre is too %s for its %.1f\" rim." % [fit[1], "wide" if fit[0] > 0 else "narrow",
				float(fit[3].get("rim_width", 0.0))])
	for surf in tr["grip"]:
		var road: bool = surf == "tarmac"
		grip_front[surf] = float(tf["grip"][surf]) * scale_f * _width_grip(front_tyre_width / 0.7, road) * (0.9 if fit_f != 0 else 1.0)
		grip_rear[surf] = float(tr["grip"][surf]) * scale_r * _width_grip(rear_tyre_width, road) * (0.9 if fit_r != 0 else 1.0)
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	var mass_f := float(wf["mass"]) + float(tf["mass"])
	var mass_r := float(wr["mass"]) + float(tr["mass"])
	front_inertia = 0.8 * mass_f * front_radius * front_radius
	rear_inertia = 0.8 * mass_r * rear_radius * rear_radius + 0.15  # plus spinning drivetrain


## Grip from a tyre's section width (metres): wider grips tarmac better, narrower digs into dirt.
static func _width_grip(width: float, tarmac: bool) -> float:
	var mm := width * 1000.0
	if tarmac:
		return clampf(1.0 + 0.14 * (mm - 160.0) / 160.0, 0.9, 1.06)
	return clampf(1.0 - 0.1 * (mm - 120.0) / 120.0, 0.9, 1.06)


## Whether a tyre this wide (mm) suits a rim this wide (inches): 0 if it does, 1 too wide, -1 too narrow.
static func rim_fit(tyre_mm: float, rim_in: float) -> int:
	if tyre_mm / rim_in > 62.0:
		return 1
	if tyre_mm / rim_in < 24.0:
		return -1
	return 0


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
	var ecu := part("ecu")
	redline = float(block["redline"]) + float(head["redline_add"]) + float(ecu.get("rev_add", 0.0))
	idle_rpm = block["idle_rpm"]

	torque_mult = float(head["torque_mult"]) * lerpf(0.75, 1.0, health["head"]) * float(ecu.get("power", 1.0))
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
	# Better petrol is a little stronger; stale petrol from a barn is not.
	var petrol := PartsDB.get_part(fuel_type)
	torque_mult *= float(petrol.get("power", 1.0)) * lerpf(1.0, 0.82, fuel_age)
	if fuel_age > 0.5 and fuel_litres > 0.0:
		notes.append("The petrol has gone stale. Drain the tank and fill it fresh.")
	# Low or old oil: more friction now, and the engine wears out fast when ridden.
	var oil_level := oil_litres / maxf(oil_capacity, 0.1)
	torque_mult *= 2.0 - float(PartsDB.get_part(oil_type).get("friction", 1.0))
	if oil_level < 0.5:
		torque_mult *= lerpf(0.7, 1.0, oil_level / 0.5)
		notes.append("No oil in the engine!" if oil_level <= 0.01 else "Low on oil: top it up before it wrecks the engine.")
	elif oil_age > 0.7:
		notes.append("The oil is old and black. Drain it and fill it fresh.")
	peak_torque *= torque_mult
	exhaust_loudness = float(exhaust["loudness"])
	# How far a litre goes: the petrol, the plugs, the filter and how healthy the engine is.
	economy_mult = float(petrol.get("economy", 1.0)) * lerpf(0.82, 1.0, plug_health) * (1.0 - 0.15 * clog) \
		* lerpf(0.85, 1.0, clampf(block_health, 0.0, 1.0)) * lerpf(0.9, 1.0, health["fuel"])


func _side_brake(side: String) -> float:
	var disc := part(side + "_disc")
	var caliper := part(side + "_caliper")
	var pads := part(side + "_pads")
	var master := part(side + "_master")
	var h := 0.0
	for s in ["disc", "caliper", "pads", "master"]:
		h += float(health[side + "_" + s]) * (0.4 if s == "pads" else 0.2)
	# Low fluid makes the lever spongy; old fluid has soaked up water and fades.
	var fluid := _fluid(side + "_master", "dot4", PartsDB.MASTER_FLUID)
	var level: float = fluid["litres"] / PartsDB.MASTER_FLUID
	brake_fluid[side] = level
	var fluid_mult := lerpf(0.25, 1.0, clampf(level / 0.6, 0.0, 1.0)) * float(PartsDB.get_part(fluid["type"]).get("brake", 1.0)) \
		* lerpf(1.0, 0.82, fluid["age"])
	if level < 0.6:
		notes.append("%s brake is spongy: top up the brake fluid." % side.capitalize())
	return 1600.0 * float(disc["diameter"]) / 300.0 * float(caliper["force"]) * float(pads["mu"]) / 0.42 \
		* float(master["ratio"]) * lerpf(0.5, 1.0, h) * fluid_mult


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
			var resist := 0.5 * AIR_DENSITY * cda * v * v + ROLLING * total_mass * 9.81
			if drive >= resist:
				best = maxf(best, v)
			rpm += 50.0
	return best


## Litres an hour the engine burns making `kw` at the crank while turning `rpm`.
func fuel_rate(kw: float, rpm: float) -> float:
	var idle := IDLE_FUEL_PER_LITRE * displacement / 1000.0 * clampf(rpm / maxf(idle_rpm * 3.0, 1.0), 0.33, 2.5)
	return (maxf(kw, 0.0) * FUEL_PER_KWH + idle) / maxf(economy_mult, 0.3)


## Kilometres per litre at a steady 90 km/h, for comparing bikes.
func cruise_economy() -> float:
	var v := 25.0
	var kw := (0.5 * AIR_DENSITY * cda * v * v * v + ROLLING * total_mass * 9.81 * v) / drivetrain_efficiency / 1000.0
	var rpm := v / rear_radius * overall_ratio(gear_count()) * 60.0 / TAU
	return 90.0 / fuel_rate(kw, rpm)


## How far the petrol in the tank goes at a steady 90 km/h.
func range_km() -> float:
	return fuel_litres * cruise_economy()


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
		"economy": cruise_economy(),
		"pw": power_to_weight(),
	}
