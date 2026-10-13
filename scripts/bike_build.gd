class_name BikeBuild
extends RefCounted
## A bike as a set of chosen parts in some condition, plus every stat the physics and the
## garage dashboards derive from them. Rust, dirt and wear on a part sap its performance,
## and engine parts have to suit each other: a big engine needs enough fuel and cooling.
## Fluids count too: the petrol in the tank, the oil in the engine and the brake fluid in each
## master cylinder, how much there is and how old it is. A part's condition can carry its
## "fluid" as {type, litres, age}; without one the bike is taken as freshly serviced.
## A tune (see TUNE_LIMITS) adjusts it in the dyno room: fuel map, ignition, rev limiter,
## suspension clickers, tyre pressures and gearing. Parts drilled and trimmed for lightness
## carry "lightened" in their condition.

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
## Every tuning setting and its widest range, [min, max]. A setting missing from a tune is left
## stock. The ECU narrows the map and ignition and caps the limiter (see tune_range), and the
## suspension clickers only work on parts with that adjuster (see tune_block).
const TUNE_LIMITS := {
	"map": [-1.0, 1.0],            # fuel map: lean (economy) .. rich (low-down power)
	"ignition": [-1.0, 1.0],       # retarded .. advanced (power, until it pinks)
	"limiter": [-2500.0, 1000.0],  # rpm moved from the stock redline
	"f_preload": [-1.0, 1.0], "f_bump": [-1.0, 1.0], "f_rebound": [-1.0, 1.0],
	"r_preload": [-1.0, 1.0], "r_bump": [-1.0, 1.0], "r_rebound": [-1.0, 1.0],
	"psi_f": [0.6, 3.2], "psi_r": [0.6, 3.2],   # tyre pressures, bar
	"sprocket_f": [12.0, 18.0], "sprocket_r": [36.0, 56.0],
	"spread": [-1.0, 1.0],         # cassette gearboxes: closer .. wider ratios
	"chain": [10.0, 70.0],         # chain slack, mm (kept on the chain itself)
}
## The pressures each style of tyre works best at, front and rear, in bar.
const PSI_BEST := {"road": [2.3, 2.5], "offroad": [1.0, 1.0], "slick": [2.1, 1.8]}
## How much drilling and trimming takes off each kind of part, as a fraction of its mass.
const LIGHTEN := {"frame": 0.08, "fork": 0.06, "shock": 0.06, "wheel": 0.12, "disc": 0.15, "saddle": 0.25,
	"handlebars": 0.15, "exhaust": 0.15, "final_drive": 0.3, "gearbox": 0.06, "side_stand": 0.3, "centre_stand": 0.3}
const OCTANE := {"unleaded_95": 95.0, "super_98": 98.0, "race_fuel": 102.0}

var parts: Dictionary          # slot -> part id
var condition: Dictionary      # slot -> {rust, dirt, wear, color}, each 0 (as new) .. 1 (ruined)
var tune := {}                 # the tune asked for: setting -> value (see TUNE_LIMITS)
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
var stock_redline := 9500.0    # where the limiter sits before it's moved
var tune_low := 0.0            # a rich map fattens the torque below the peak, a lean one thins it
var tune_high := 0.0           # ignition advance sharpens the top end
var engine_stress := 1.0       # how hard the tune works the engine: multiplies its wear
var rolling := ROLLING         # rolling resistance; soft tyres drag
var tyre_wear := {"front": 1.0, "rear": 1.0}   # how fast each tyre wears at its pressure

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


func _init(build: Dictionary = {}, part_condition: Dictionary = {}, tune_settings: Dictionary = {}) -> void:
	parts = PartsDB.sanitize_build(build)
	condition = part_condition
	tune = tune_settings
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
		bike_mass += _part_mass(slot)
	total_mass = bike_mass + RIDER_MASS

	wheelbase = frame["wheelbase"]
	com_height = frame["com_height"]
	rake_deg = frame["rake_deg"]
	seat_height = float(frame["seat_height"]) + float(saddle["height"])
	cda = float(frame["cda"]) + float(bars["cda"]) + float(part("panniers").get("cda", 0.0)) + float(part("top_box").get("cda", 0.0))
	luggage_litres = float(part("panniers").get("litres", 0.0)) + float(part("top_box").get("litres", 0.0))
	steer_rate = 4.0 * float(bars["width"]) / 720.0
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
	# The clickers: preload firms the spring up, bump and rebound the damping.
	front_spring *= 1.0 + 0.18 * tune_value("f_preload")
	front_bump *= 1.0 + 0.45 * tune_value("f_bump")
	front_rebound *= 1.0 + 0.45 * tune_value("f_rebound")
	rear_spring *= 1.0 + 0.18 * tune_value("r_preload")
	rear_bump *= 1.0 + 0.45 * tune_value("r_bump")
	rear_rebound *= 1.0 + 0.45 * tune_value("r_rebound")

	_compute_wheels()
	_compute_engine(block, head)
	_compute_brakes()

	var gearbox := part("gearbox")
	var sprocket := part("final_drive")
	primary = gearbox["primary"]
	gear_ratios = _spread(gearbox["ratios"], tune_value("spread"))
	final_drive = tune_value("sprocket_r") / tune_value("sprocket_f")
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
	for surf in tr["grip"]:
		grip_front[surf] = float(tf["grip"][surf]) * scale_f
		grip_rear[surf] = float(tr["grip"][surf]) * scale_r
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	# Tyre pressures: off the tyre's best, it grips less on tarmac. A little soft finds more
	# grip in the dirt, but squirms, drags and wears.
	var dev_f := pressure_offset("front")
	var dev_r := pressure_offset("rear")
	for surf in grip_rear:
		grip_front[surf] *= _pressure_grip(dev_f, surf)
		grip_rear[surf] *= _pressure_grip(dev_r, surf)
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	rolling = ROLLING * (clampf(1.0 - 0.9 * dev_f, 0.6, 2.5) + clampf(1.0 - 0.9 * dev_r, 0.6, 2.5)) * 0.5
	tyre_wear = {"front": 1.0 + 2.5 * absf(dev_f), "rear": 1.0 + 2.5 * absf(dev_r)}
	if minf(dev_f, dev_r) < -0.3:
		notes.append("The tyres are soft: they'll squirm, drag and wear out fast.")
	elif maxf(dev_f, dev_r) > 0.3:
		notes.append("The tyres are rock hard: less grip, and they skip over bumps.")
	var mass_f := _part_mass("front_wheel") + float(tf["mass"])
	var mass_r := _part_mass("rear_wheel") + float(tr["mass"])
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
	var ecu := part("ecu")
	stock_redline = float(block["redline"]) + float(head["redline_add"]) + float(ecu.get("rev_add", 0.0))
	redline = stock_redline + tune_value("limiter")
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
	var lean := maxf(-tune_value("map"), 0.0)
	engine_heat = displacement / 1000.0 * float(head["heat"]) * (1.0 + 0.15 * lean + 0.06 * maxf(tune_value("ignition"), 0.0))
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
	_tune_engine()
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
	# Lean is thrifty, rich is thirsty; a touch of advance burns it more completely.
	economy_mult *= (1.0 - 0.14 * tune_value("map")) * (1.0 + 0.04 * tune_value("ignition"))


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
	var t := peak_torque * clampf(shape, 0.3, 1.0)
	if x < 0.0:
		t *= 1.0 + tune_low * minf(-x * 2.0, 1.0)
	else:
		t *= 1.0 + tune_high * minf(x * 2.0, 1.0)
	return t


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
			var resist := 0.5 * AIR_DENSITY * cda * v * v + rolling * total_mass * 9.81
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
	var kw := (0.5 * AIR_DENSITY * cda * v * v * v + rolling * total_mass * 9.81 * v) / drivetrain_efficiency / 1000.0
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


# ---------------------------------------------------------------------------- tuning

## A part's mass, less what drilling and trimming took off it.
func _part_mass(slot: String) -> float:
	var p := part(slot)
	var m := float(p.get("mass", float(p.get("mass_per_cyl", 0.0)) * cylinders))
	if condition.get(slot, {}).get("lightened", false):
		m *= 1.0 - lighten_cut(str(parts[slot]))
	return m


## The fraction of a part's mass lightening it takes off: 0 for parts already built light or
## with nothing to trim.
static func lighten_cut(part_id: String) -> float:
	if PartsDB.is_lightweight(part_id):
		return 0.0
	return float(LIGHTEN.get(PartsDB.kind_of(part_id), 0.0))


## Why a setting can't be changed on this bike's parts, or "" when it can.
func tune_block(key: String) -> String:
	if not TUNE_LIMITS.has(key):
		return "There's nothing like that to adjust."
	if key.ends_with("_preload") or key.ends_with("_bump") or key.ends_with("_rebound"):
		var p := part("fork" if key.begins_with("f_") else "shock")
		var what := key.get_slice("_", 1)
		var need := 1 if what == "preload" else (2 if what == "rebound" else 4)
		if int(p.get("adjust", 0)) < need:
			return "The %s has no %s adjuster." % [str(p.get("name", "suspension")).to_lower(), what]
	elif key == "spread" and not part("gearbox").get("cassette", false):
		return "Only a cassette gearbox lets you respace the ratios."
	return ""


## How far the ECU lets the fuel map and ignition move either way: a little with none fitted
## (jets and the ignition plate), all the way with a remap or race ECU.
func ecu_reach() -> float:
	return float(part("ecu").get("tune_range", 0.25)) if has_part("ecu") else 0.25


## The range a setting can take on this bike.
func tune_range(key: String) -> Vector2:
	var lim: Array = TUNE_LIMITS.get(key, [0.0, 0.0])
	var r := Vector2(float(lim[0]), float(lim[1]))
	if key in ["map", "ignition"]:
		r = Vector2(-ecu_reach(), ecu_reach())
	elif key == "limiter":
		r.y = float(part("ecu").get("limiter_add", 0.0)) if has_part("ecu") else 0.0
	return r


## A setting as it comes from the factory.
func tune_default(key: String) -> float:
	match key:
		"psi_f", "psi_r":
			var tyre := part("front_tyre" if key == "psi_f" else "rear_tyre")
			var best: Array = PSI_BEST.get(str(tyre.get("style", "road")), PSI_BEST["road"])
			return float(best[0 if key == "psi_f" else 1])
		"sprocket_f":
			return float(part("final_drive").get("front", 15.0))
		"sprocket_r":
			return float(part("final_drive").get("rear", 45.0))
		"chain":
			return 30.0
	return 0.0


## A setting as it's applied: the tune's value kept within what the parts allow, or stock.
func tune_value(key: String) -> float:
	if not tune.has(key) or tune_block(key) != "":
		return tune_default(key)
	var r := tune_range(key)
	return clampf(float(tune[key]), r.x, r.y)


## How far a tyre is off its best pressure, as a fraction: -0.2 is 20% soft.
func pressure_offset(side: String) -> float:
	var key := "psi_f" if side == "front" else "psi_r"
	var best := tune_default(key)
	return (tune_value(key) - best) / best


func _pressure_grip(dev: float, surf: String) -> float:
	if surf == "tarmac":
		return 1.0 - 0.5 * dev * dev - 0.12 * maxf(dev, 0.0)
	return 1.0 + 0.15 * clampf(-dev, 0.0, 0.4) - 0.5 * dev * dev


## Ratios respaced about top gear: closer (spread < 0) or wider (> 0).
func _spread(ratios: Array, spread: float) -> Array:
	if spread == 0.0 or ratios.is_empty():
		return ratios
	var top := float(ratios[-1])
	var out := []
	for r in ratios:
		out.append(top * pow(float(r) / top, 1.0 + 0.3 * spread))
	return out


## How much advance the petrol takes before the engine pinks.
func knock_margin() -> float:
	return 0.45 + (float(OCTANE.get(fuel_type, 95.0)) - 95.0) * 0.12


## The fuel map and ignition: a little rich and advanced makes the most power, lean saves
## petrol but runs hot, and too much advance for the petrol pinks and hurts the engine.
func _tune_engine() -> void:
	var m := tune_value("map")
	var a := tune_value("ignition")
	var knock := maxf(0.0, a - knock_margin())
	torque_mult *= (1.0 + 0.04 * m - 0.055 * m * m) * (1.0 + 0.045 * a - 0.02 * a * a) * (1.0 - 0.15 * knock)
	tune_low = 0.05 * m
	tune_high = 0.03 * a
	var over := maxf(tune_value("limiter"), 0.0)
	engine_stress = 1.0 + 1.2 * maxf(-m, 0.0) + 0.5 * maxf(a, 0.0) + 3.0 * knock + over / 1000.0
	if knock > 0.0:
		notes.append("Pinking: too much ignition advance for this petrol. Back it off or use higher octane.")
	if m < -0.5:
		notes.append("Running lean: thrifty, but hot and hard on the engine.")
	if over > 0.0:
		notes.append("The rev limiter is raised: more revs, more wear.")


## Top speed in each gear at the rev limiter, km/h.
func gear_speeds() -> Array:
	var out := []
	for g in range(1, gear_count() + 1):
		out.append(redline / overall_ratio(g) * TAU / 60.0 * rear_radius * 3.6)
	return out


## Seconds from a standstill to 100 km/h flat out with clean shifts, held back by traction,
## wheelies, drag and shift time. -1 when the bike can't get there.
func zero_to_100() -> float:
	var v := 0.0
	var t := 0.0
	var gear := 1
	var dt := 0.01
	var mu := float(grip_rear.get("tarmac", 1.0))
	var max_a := minf(mu * 9.81 * 0.75, 9.81 * wheelbase * 0.55 / com_height)
	while v < 100.0 / 3.6:
		if t > 40.0:
			return -1.0
		var ratio := overall_ratio(gear)
		var rpm := v / rear_radius * ratio * 60.0 / TAU
		if rpm >= redline * 0.98 and gear < gear_count():
			gear += 1
			t += shift_time
			continue
		rpm = maxf(rpm, peak_torque_rpm * 0.75)   # slipping the clutch off the line
		var drive := engine_torque(rpm) * ratio * drivetrain_efficiency / rear_radius
		var resist := 0.5 * AIR_DENSITY * cda * v * v + rolling * total_mass * 9.81
		var acc := minf(drive / total_mass, max_a) - resist / total_mass
		if acc <= 0.0:
			return -1.0
		v += acc * dt
		t += dt
	return t


## A rolling-road run: power and torque at the rear wheel from just off idle to the limiter,
## the speed in each gear and the headline numbers.
func dyno_run(samples := 48) -> Dictionary:
	var lo := maxf(idle_rpm * 1.5, redline * 0.2)
	var rpm := []
	var nm := []
	var hp_at := []
	for i in samples + 1:
		var r := lerpf(lo, redline, float(i) / samples)
		var tq := engine_torque(r) * drivetrain_efficiency
		rpm.append(snappedf(r, 1.0))
		nm.append(snappedf(tq, 0.01))
		hp_at.append(snappedf(tq * r * TAU / 60.0 / 1000.0 * 1.341, 0.01))
	var best_hp := 0.0
	var best_hp_rpm := 0.0
	var best_nm := 0.0
	var best_nm_rpm := 0.0
	var r := lo
	while r <= redline:
		var tq := engine_torque(r) * drivetrain_efficiency
		var p := tq * r * TAU / 60.0 / 1000.0 * 1.341
		if p > best_hp:
			best_hp = p
			best_hp_rpm = r
		if tq > best_nm:
			best_nm = tq
			best_nm_rpm = r
		r += 25.0
	return {"rpm": rpm, "nm": nm, "hp": hp_at, "peak_hp": best_hp, "peak_hp_rpm": best_hp_rpm, "peak_nm": best_nm,
		"peak_nm_rpm": best_nm_rpm, "redline": redline, "top_kmh": top_speed_estimate() * 3.6, "gears": gear_speeds(),
		"mass": bike_mass, "hp_per_tonne": best_hp / maxf(total_mass, 1.0) * 1000.0, "zero_100": zero_to_100(),
		"crank_hp": hp(), "economy": cruise_economy()}
