class_name BikeBuild
extends RefCounted
## A bike as a set of chosen parts in some condition, plus every stat the physics and the
## garage dashboards derive from them. Rust, dirt and wear on a part sap its performance,
## and engine parts have to suit each other: a big engine needs enough fuel and cooling.
## Fluids count too: the petrol in the tank, the oil in the engine and the brake fluid in each
## master cylinder, how much there is and how old it is. A part's condition can carry its
## "fluid" as {type, litres, age}; without one the bike is taken as freshly serviced.
## A tune (see TUNE_LIMITS) adjusts it in the dyno room: fuel map, ignition, rev limiter,
## suspension clickers, tyre pressures, gearing and the ECU's rider aids. Parts drilled and trimmed for lightness
## carry "lightened" in their condition.

const RIDER_MASS := 75.0
## Battery, wiring, side panels and brackets (the tail unit weighs its own). A frame can carry its own
## figure as "fixed_mass": an MX bike has next to none of it, a big steel cruiser or tourer a lot.
const FIXED_MASS := 36.0
const FUEL_DENSITY := 0.74    # kg per litre
const OIL_DENSITY := 0.87
## Litres of petrol per kWh the cylinders make. Some of that goes in the engine's own friction and
## pumping, a mean pressure in bar that climbs with revs (and with a head's "thirst": big valves and
## long cam overlap waste fuel at part throttle), so a revvy, hot-cammed engine cruising high up the
## rev range drinks more than a lazy one doing the same work.
const FUEL_PER_KWH := 0.32
const FRICTION_BAR := 1.7
const FRICTION_BAR_PER_KRPM := 0.3
## A two-stroke loses some of its fresh charge out of the exhaust.
const TWO_STROKE_THIRST := 1.35
## How fast torque falls away past its peak: power then peaks about a quarter above peak torque.
const TORQUE_FADE := 1.5
const AIR_DENSITY := 1.2
const DRIVETRAIN_EFFICIENCY := 0.92
const ROLLING := 0.015
## A tyre bead seated at least this well on the tyre changer (0..1) holds its pressure and grips fully.
const BEAD_OK := 0.6
## The fork's offset ahead of the steering axis (m) for a fork in the catalogue without one, by
## its style: with the rake and the front wheel's size it sets the trail.
const FORK_OFFSET := {"conventional": 0.045, "usd": 0.032, "girder": 0.045, "springer": 0.08, "leading_link": 0.05}
## How a fork's axle travels as it compresses, by its style (degrees tipped forward from its
## legs): a telescopic fork slides straight up its raked legs, so braking pushes it down them as
## well as loading it (it dives); the links of a girder, springer or leading-link fork swing the
## axle up more nearly straight, which holds the nose up on the brakes (anti-dive).
const FORK_PATH_TILT := {"conventional": 0.0, "usd": 0.0, "girder": 14.0, "springer": 10.0, "leading_link": 30.0}
## A leading-link (Earles) fork's swinging arm, m, by style: its brake is mounted on the arm, so
## braking also pushes the arm down, which holds the fork up (the bike barely dives).
const FORK_LINK := {"leading_link": 0.3}
## How far each frame style leans before something hard touches down (footboards, pipes, the
## frame), degrees: a low cruiser grounds out long before its tyres give up.
const LEAN_CLEARANCE := {"softail": 31.0, "cruiser": 32.0, "chopper": 30.0}
## How much quicker than the ordinary bike a bike of each style rolls from one lean to the other
## (Bike.LEAN_RATE_MAX times this): a light, short bike with a low front and narrow clip-ons flicks
## through a chicane where a cruiser or a tourer lumbers over. A bike that is only mostly one of
## these gets a share of it (see flick, FLICK_STYLES).
const FLICK := {"race": 3.0, "sport": 2.8, "naked": 2.2}
## How much stiffer a spring gets towards the end of its travel, for a part in the catalogue
## without its own "progression": the rate at the bottom is (1 + 3 x this) times the rate at the top.
## Forks by style, shocks by their type (air springs ramp up hardest, linkages next).
const FORK_PROGRESSION := {"conventional": 0.2, "usd": 0.25, "girder": 0.05, "springer": 0.05, "leading_link": 0.1}
const SHOCK_PROGRESSION := {"air": 0.7, "linkage": 0.45, "mono": 0.3, "twin": 0.1}
## Stock spring preload, at the wheel along its travel (m), and how far a preload clicker moves it
## either way: preload pre-squashes the spring, so the bike sags less without the spring getting
## any stiffer.
const PRELOAD_STOCK := 0.008
const PRELOAD_CLICK := 0.008
## Chain pitch (520/525/530 chain, 5/8 in), m: with the teeth it sets each sprocket's size.
const CHAIN_PITCH := 0.015875
## Where the gearbox sprocket sits from the swingarm pivot (bike space, m: +y up, +z back).
const COUNTERSHAFT := Vector3(0.0, 0.03, -0.075)
## Trail shorter than this (m) makes for nervous steering: the bike info says so.
const SHORT_TRAIL := 0.06
## Where a prototype's flat spot sits (a share of the peak torque revs) and how wide it is.
const FLAT_SPOT_AT := 0.72
const FLAT_SPOT_WIDTH := 0.12
## The least trail a bike that turns up already built has (see sensible_fork), m.
const STOCK_TRAIL := 0.075
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
	# The ECU's rider aids, where it has them: 0 off, then level 1 (gentle) .. AID_LEVELS (firm).
	"aid_traction": [0.0, 5.0], "aid_stability": [0.0, 5.0], "aid_anti_wheelie": [0.0, 5.0],
	"damper": [-1.0, 1.0],         # steering damper clicker: softer .. firmer
	"screen": [0.0, 1.0],          # an adjustable screen: right down .. right up (the rider sets it riding)
}
## The rider aids the dyno desk sets, aid -> its tune key (see TUNE_LIMITS). Level AID_STOCK is
## how the ECU comes from the factory; AID_SCALE is how firmly each level steps in next to that.
const AID_KEYS := {"traction": "aid_traction", "stability": "aid_stability", "anti_wheelie": "aid_anti_wheelie"}
const AID_LEVELS := 5
const AID_STOCK := 3
const AID_SCALE: Array[float] = [0.0, 0.4, 0.7, 1.0, 1.25, 1.5]
## The pressures each style of tyre works best at, front and rear, in bar.
const PSI_BEST := {"road": [2.3, 2.5], "offroad": [1.0, 1.0], "slick": [2.1, 1.8]}
## How much drilling and trimming takes off each kind of part, as a fraction of its mass.
const LIGHTEN := {"frame": 0.08, "fork": 0.06, "shock": 0.06, "wheel": 0.12, "disc": 0.15, "saddle": 0.25,
	"handlebars": 0.15, "exhaust": 0.15, "final_drive": 0.3, "gearbox": 0.06, "side_stand": 0.3, "centre_stand": 0.3}
const OCTANE := {"unleaded_95": 95.0, "super_98": 98.0, "race_fuel": 102.0}
## The ride modes a dashboard with "modes" offers, on an ECU with rider aids: the level each aid
## steps in at (as the dyno desk's 0..AID_LEVELS), how much of the engine's power comes through,
## how quickly the throttle answers (opening, a share a second; 0 straight away) and whether the
## ABS looks after the back wheel as well as the front (Sport lets it lock to back it in).
const RIDE_MODES := {
	"sport": {"name": "Sport", "traction": 1, "anti_wheelie": 1, "stability": 1, "power": 1.0, "rate": 0.0, "abs_rear": false},
	"tour": {"name": "Tour", "traction": 3, "anti_wheelie": 3, "stability": 3, "power": 0.92, "rate": 6.0, "abs_rear": true},
	"wet": {"name": "Wet", "traction": 5, "anti_wheelie": 5, "stability": 5, "power": 0.7, "rate": 2.5, "abs_rear": true},
}
## The order the dash's mode button steps through them: "" is Custom, the dyno desk's own levels.
const MODE_ORDER: Array[String] = ["", "sport", "tour", "wet"]
## What each dashboard feature is called in the parts computer.
const DASH_FEATURE_NAMES := {"speed": "speed", "rpm": "revs", "gear": "gear", "shift_light": "shift light",
	"top_speed": "top speed", "trip": "trip", "economy": "fuel economy", "range": "range",
	"cruise": "cruise control", "modes": "ride modes"}

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
var fuel_capacity := 15.0      # the tank and any auxiliary tank together, litres
var main_capacity := 15.0      # the tank on its own
var aux_capacity := 0.0        # an auxiliary tank's, 0 with none fitted
var dash_features: Array = ["speed"]
var headlight_lumens := 0.0    # 0 with no headlight fitted
var fog_lumens := 0.0          # 0 with no fog lights
var fog_color := Color(1.0, 0.92, 0.78)
var horn_tones: Array = []     # frequencies of the horn, empty with none fitted
var horn_style := ""
var horn_loudness := 0.0
var horn_sound := ""           # the horn's recordings (an Sfx sound), "" for a synthesised one
var ecu_features: Array = []   # rider aids the ECU gives: traction, abs, anti_wheelie, stability
var ecu_aid := 0.0             # how firmly those aids step in, 0..1
## The ride mode chosen on the dash (a key of RIDE_MODES) while ridden, "" for none: then the
## aids are at the dyno desk's levels. Only counts on a bike with ride modes (has_ride_modes).
var ride_mode := ""
var luggage_litres := 0.0
## The adventure kit: the tyres' kinds (see TyreGrip), what's packed in the toolbox (PartsDB
## TOOLBOX_CONTENTS ids), what the sat nav shows (empty with none), and an adjustable screen: how
## far it can rise (m), how far it's up now (m), and how much wind gets past it to the rider's
## helmet, 0 (calm air) .. 1 (none of it stopped).
var tyre_kind_front := "road"
var tyre_kind_rear := "road"
var toolbox_contents: Array = []
var toolbox_slots := 0
var satnav_features: Array = []
var screen_adjust := 0.0
var screen_raise := 0.0
var wind_buffet := 1.0
var has_side_stand := false
var has_centre_stand := false
var centre_lift := 0.04

# Fluids
var fuel_litres := 0.0         # in the tank and any auxiliary tank together
var aux_litres := 0.0          # in the auxiliary tank
var fuel_type := "unleaded_95"
var fuel_age := 0.0            # 0 fresh .. 1 stale, gummed-up petrol
var oil_capacity := 2.5
var oil_litres := 2.5
var oil_age := 0.0             # 0 fresh .. 1 black sludge
var oil_type := "semi_10w40"
var oil_protection := 0.88     # how well the oil looks after the engine, 0..1
var brake_fluid := {"front": 1.0, "rear": 1.0}   # how full each side's master cylinder is, 0..1
var economy_mult := 1.0        # how far each litre goes: fuel grade, tune and condition
var friction_mult := 1.0       # the head's thirst at part throttle (see friction_kw)

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
## How much each spring firms up towards the bottom (see FORK_PROGRESSION), its preload (m, see
## PRELOAD_STOCK), and the wheel speed (m/s) past which the bump damping's valving blows off.
var front_progression := 0.2
var rear_progression := 0.2
var front_preload := PRELOAD_STOCK
var rear_preload := PRELOAD_STOCK
var front_knee := 1.0
var rear_knee := 1.0
## The way the front axle moves as the fork compresses, bike space (up its legs for a telescopic
## fork, tipped forward for linked forks: see FORK_PATH_TILT).
var fork_path := Vector3(0.0, 0.9, 0.42)
## A leading-link fork's arm (see FORK_LINK), m, 0 for any other fork.
var fork_link := 0.0
## How far the bike leans before it grounds out (see LEAN_CLEARANCE), rad.
var lean_clearance := deg_to_rad(52.0)
## How quickly the bike rolls between leans, as a multiple of an ordinary bike's (see FLICK).
var flick := 1.0
## The swingarm: its pivot (bike space, the back wheel fully extended at (0, 0, wheelbase / 2)),
## and its length, m. The back axle swings up round it.
var swing_pivot := Vector3(0.0, 0.16, 0.1)
var swing_length := 0.6
## The gearbox and rear sprockets' pitch radii, m.
var sprocket_r_front := 0.05
var sprocket_r_rear := 0.11
## How much of the squat from the weight going back under power the swingarm and chain pull hold
## off, at the bike's sag (1 holds it level, more lifts the back): see anti_squat_at.
var anti_squat := 1.0
## How far each end sags under the bike and rider standing still, m along its travel.
var front_sag := 0.03
var rear_sag := 0.03

# Wheels and tyres
var front_radius := 0.3
var rear_radius := 0.31
var front_rim_radius := 0.22
var rear_rim_radius := 0.22
var front_tyre_width := 0.12   # section widths, metres, straight from the tyres (180/55 is 0.18)
var rear_tyre_width := 0.16
var tyre_style := "road"
var grip := {}                 # average of both tyres, for dashboards
var grip_front := {}
var grip_rear := {}
var front_inertia := 0.6
var rear_inertia := 0.8
## Each tyre's Magic Formula numbers (see TyreModel.params_of), with the pressure taken into account.
var tyre_front := {}
var tyre_rear := {}
## Mechanical trail (m): how far the front contact patch trails the steering axis. It makes the
## front steer itself into a lean and lines the wheel up with where it's rolling.
var trail := 0.1
## How heavy the steering is to swing: the front wheel, fork and bars about the steering axis, kg m^2.
var steer_inertia := 0.3
## The weight out on the fork offset that swings with the bars (wheel, tyre, disc, caliper), kg.
var steer_mass := 20.0
## How far the front axle sits ahead of the steering axis (the yokes and fork feet together), m.
var fork_offset := 0.045
## The steering damper: viscous damping (N m per rad/s) and friction (N m), 0 with none fitted.
var damper_damping := 0.0
var damper_friction := 0.0
## Where the parts sit moves the centre of mass from the frame's own figure (bike space, m: +y up,
## +z back), and their spread adds to (or takes from) the pitch, yaw and roll inertia, kg m^2.
var com_offset := Vector3.ZERO
var inertia_add := Vector3.ZERO

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
var flat_dip := 0.0            # a manufacturer prototype's flat spot: torque lost in the mid-range (see ContractTestRide)
var engine_stress := 1.0       # how hard the tune works the engine: multiplies its wear
var rolling := ROLLING         # rolling resistance; soft tyres drag
var tyre_wear := {"front": 1.0, "rear": 1.0}   # how fast each tyre wears at its pressure
## Air each tyre has lost from its set pressure (a puncture, see Puncture), bar, and how flat
## that leaves it: 0 holding its shape .. 1 rolling on the rim.
var deflate := {"front": 0.0, "rear": 0.0}
var flat := {"front": 0.0, "rear": 0.0}

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


## A prototype's quirk kept on one of its parts (see ContractTestRide), 0 when there's none.
func _proto(slot: String, key: String) -> float:
	var p = condition.get(slot, {}).get("proto")
	return float(p.get(key, 0.0)) if p is Dictionary else 0.0


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
	main_capacity = tank["capacity"]
	var fuel := _fluid("tank", "unleaded_95", main_capacity)
	fuel_litres = fuel["litres"]
	fuel_type = fuel["type"]
	fuel_age = fuel["age"]
	# An auxiliary tank carries more petrol, fed into the main one as it goes down.
	aux_capacity = PartsDB.fluid_capacity(parts["aux_tank"]) if has_part("aux_tank") else 0.0
	aux_litres = float(_fluid("aux_tank", "unleaded_95", aux_capacity)["litres"]) if aux_capacity > 0.0 else 0.0
	fuel_capacity = main_capacity + aux_capacity
	fuel_litres += aux_litres
	oil_capacity = PartsDB.fluid_capacity(parts["engine"])
	var oil := _fluid("engine", "semi_10w40", oil_capacity)
	oil_litres = oil["litres"]
	oil_age = oil["age"]
	oil_type = oil["type"]
	var oil_part := PartsDB.get_part(oil["type"])
	oil_protection = float(oil_part.get("protection", 0.8)) * lerpf(1.0, 0.55, oil_age)
	bike_mass = float(frame.get("fixed_mass", FIXED_MASS)) + fuel_litres * FUEL_DENSITY + oil_litres * OIL_DENSITY
	for slot in parts:
		bike_mass += _part_mass(slot)
	total_mass = bike_mass + RIDER_MASS

	wheelbase = frame["wheelbase"]
	com_height = frame["com_height"]
	rake_deg = frame["rake_deg"]
	seat_height = float(frame["seat_height"]) + float(saddle["height"])
	cda = float(frame["cda"]) + float(bars["cda"]) + float(part("panniers").get("cda", 0.0)) + float(part("top_box").get("cda", 0.0)) \
		+ float(part("tank_bag").get("cda", 0.0))
	# A fairing parts the air round the rider (a cracked, grimy one less well); mirrors stick out into it.
	cda += float(part("fairing").get("cda", 0.0)) * lerpf(0.7, 1.0, health.get("fairing", 1.0))
	cda += float(part("mirrors").get("cda", 0.0))
	luggage_litres = float(part("panniers").get("litres", 0.0)) + float(part("top_box").get("litres", 0.0)) \
		+ float(part("tank_bag").get("litres", 0.0))
	_compute_kit()
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
	horn_sound = str(horn.get("sound", ""))
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
	# The clickers: preload pre-squashes the spring (less sag, the same rate), bump and rebound
	# the damping.
	front_preload = maxf(float(fork.get("preload", PRELOAD_STOCK)) + PRELOAD_CLICK * tune_value("f_preload"), 0.0)
	front_bump *= 1.0 + 0.45 * tune_value("f_bump")
	front_rebound *= 1.0 + 0.45 * tune_value("f_rebound")
	rear_preload = maxf(float(shock.get("preload", PRELOAD_STOCK)) + PRELOAD_CLICK * tune_value("r_preload"), 0.0)
	rear_bump *= 1.0 + 0.45 * tune_value("r_bump")
	rear_rebound *= 1.0 + 0.45 * tune_value("r_rebound")
	var fork_style := str(fork.get("style", "conventional"))
	front_progression = float(fork.get("progression", FORK_PROGRESSION.get(fork_style, 0.2)))
	rear_progression = float(shock.get("progression", _shock_progression(str(shock.get("type", "")))))
	# Top-spec dampers (the ones with every adjuster) have proper high-speed valving that opens
	# sooner on a sharp hit.
	front_knee = float(fork.get("knee", 0.6 if int(fork.get("adjust", 0)) >= 4 else 1.0))
	rear_knee = float(shock.get("knee", 0.6 if int(shock.get("adjust", 0)) >= 4 else 1.0))
	var path_rake := deg_to_rad(float(frame["rake_deg"]) - float(FORK_PATH_TILT.get(fork_style, 0.0)))
	fork_path = Vector3(0.0, cos(path_rake), sin(path_rake))
	fork_link = float(fork.get("link", FORK_LINK.get(fork_style, 0.0)))
	lean_clearance = deg_to_rad(float(frame.get("clearance", LEAN_CLEARANCE.get(str(frame.get("style", "")), 52.0))))
	flick = flick_of(parts)
	# The swingarm pivots where the frame says (the same point the bike's drawn with).
	var geo: Dictionary = frame.get("geo", {})
	swing_pivot = Vector3(0.0, float(geo.get("pivot_y", 0.16)), float(frame["wheelbase"]) * 0.5 - float(geo.get("arm", 0.6)))
	swing_length = (Vector3(0.0, 0.0, float(frame["wheelbase"]) * 0.5) - swing_pivot).length()

	_compute_wheels()
	_compute_engine(block, head)
	_compute_brakes()

	var gearbox := part("gearbox")
	var sprocket := part("final_drive")
	primary = gearbox["primary"]
	gear_ratios = _spread(gearbox["ratios"], tune_value("spread"))
	final_drive = tune_value("sprocket_r") / tune_value("sprocket_f")
	shift_time = float(gearbox.get("shift_time", 0.12))
	drivetrain_efficiency = DRIVETRAIN_EFFICIENCY * lerpf(0.8, 1.0, health["gearbox"]) * lerpf(0.88, 1.0, health["final_drive"])
	_compute_chain()
	_compute_mass_spread()
	_compute_squat()


## The adventure kit: the toolbox and what's in it, the sat nav, the tyres' kinds, and an
## adjustable screen. A screen raised pushes a little more air (and the taller the screen
## stands, the less wind reaches the rider's helmet: see wind_buffet).
func _compute_kit() -> void:
	tyre_kind_front = TyreGrip.kind_of(part("front_tyre"))
	tyre_kind_rear = TyreGrip.kind_of(part("rear_tyre"))
	toolbox_slots = int(part("toolbox").get("slots", 0)) if has_part("toolbox") else 0
	toolbox_contents = []
	if has_part("toolbox"):
		for c in condition.get("toolbox", {}).get("contents", []):
			if PartsDB.TOOLBOX_CONTENTS.has(str(c)) and toolbox_contents.size() < toolbox_slots:
				toolbox_contents.append(str(c))
	satnav_features = part("satnav").get("features", ["map"]) if has_part("satnav") else []
	var fairing := part("fairing")
	screen_adjust = float(fairing.get("screen_adjust", 0.0)) if has_part("fairing") else 0.0
	screen_raise = 0.0
	_set_screen_raise(tune_value("screen") * screen_adjust)


## Puts an adjustable screen `v` (0 right down .. 1 right up) of the way up its rails, as the
## rider does on the move: the drag and the wind on the helmet follow.
func set_screen(v: float) -> void:
	tune["screen"] = clampf(v, 0.0, 1.0)
	_set_screen_raise(tune_value("screen") * screen_adjust)


func _set_screen_raise(raise: float) -> void:
	cda += (raise - screen_raise) * 0.12
	screen_raise = raise
	var fairing := part("fairing")
	var screen := (float(fairing.get("screen", 0.0)) + screen_raise) if has_part("fairing") else 0.0
	wind_buffet = clampf(1.0 - (screen - 0.08) / 0.42, 0.0, 1.0)


## Whether the toolbox has `what` packed in it (a PartsDB.TOOLBOX_CONTENTS id).
func has_kit(what: String) -> bool:
	return toolbox_contents.has(what)


## The grip of a tyre (the front's or the back's) on `surf` with the ground `wet` 0..1: its own
## figure for the town's ground, or its tarmac one for the adventure surfaces, times what its
## kind of tread makes of that surface (see TyreGrip).
func tyre_grip(front: bool, surf: String, wet: float) -> float:
	return TyreGrip.grip_on(grip_front if front else grip_rear, tyre_kind_front if front else tyre_kind_rear, surf, wet)


## Where each slot's part sits on a bike: [share of the wheelbase back from the front axle,
## height above the ground in m]. Slots not listed sit in the middle of the bike.
const PART_SPOT := {
	"frame": [0.45, 0.55], "fork": [0.06, 0.62], "shock": [0.72, 0.5], "front_wheel": [0.0, 0.3], "rear_wheel": [1.0, 0.31],
	"front_tyre": [0.0, 0.3], "rear_tyre": [1.0, 0.31], "front_disc": [0.0, 0.3], "rear_disc": [1.0, 0.31],
	"front_caliper": [0.0, 0.35], "rear_caliper": [1.0, 0.33], "front_master": [0.14, 1.0], "rear_master": [0.68, 0.38],
	"tank": [0.32, 0.86], "saddle": [0.62, 0.82], "handlebars": [0.14, 1.0], "dashboard": [0.12, 1.02],
	"engine": [0.45, 0.42], "head": [0.4, 0.66], "fuel": [0.42, 0.62], "air_filter": [0.45, 0.68], "oil_filter": [0.4, 0.28],
	"spark_plugs": [0.4, 0.7], "cooling": [0.22, 0.52], "gearbox": [0.55, 0.38], "exhaust": [0.72, 0.38],
	"final_drive": [0.62, 0.32], "chain": [0.8, 0.32], "side_stand": [0.58, 0.2], "centre_stand": [0.62, 0.2],
	"headlight": [-0.04, 0.95], "horn": [0.1, 0.55], "ecu": [0.65, 0.65], "panniers": [0.92, 0.62], "top_box": [1.02, 0.98],
	"fog_lights": [-0.02, 0.6], "tail": [0.9, 0.8], "fairing": [0.06, 0.98], "mirrors": [0.14, 1.12],
	"front_mudguard": [0.0, 0.62], "indicators": [0.5, 0.85], "side_panels": [0.6, 0.65], "rearsets": [0.68, 0.38],
	"guards": [0.38, 0.4], "number_boards": [0.75, 0.75], "swingarm": [0.82, 0.35], "steering_damper": [0.16, 0.92],
	"tank_bag": [0.3, 1.0], "satnav": [0.12, 1.12], "aux_tank": [0.9, 0.65], "toolbox": [0.9, 0.5],
	"lever_guards": [0.14, 1.0],
}
## Where the auxiliary tank and the toolbox sit depends on their style: low by the engine, on
## the rails, under the rack or up on top of it.
const STYLE_SPOT := {
	"aux_tank": {"twin": [0.3, 0.42], "rear": [0.95, 0.78], "cell": [0.88, 0.58], "can": [0.92, 0.6], "bladder": [1.02, 0.98]},
	"toolbox": {"bash": [0.42, 0.14], "roll": [0.03, 0.62], "tube": [0.86, 0.48], "box": [0.92, 0.5], "case": [1.05, 0.95]},
}


## Where a slot's part sits (see PART_SPOT and STYLE_SPOT).
func part_spot(slot: String) -> Array:
	var by_style: Dictionary = STYLE_SPOT.get(slot, {})
	if not by_style.is_empty() and has_part(slot):
		return by_style.get(str(part(slot).get("style", "")), PART_SPOT.get(slot, [0.5, 0.5]))
	return PART_SPOT.get(slot, [0.5, 0.5])


## The parts' own spread: each slot's part weighs more or less than the stock part there
## (PartsDB.DEFAULT_BUILD), at its spot on the bike, and so does the petrol against a 15 litre tank.
## The frame's own centre of mass height is for a stock set of parts with a rider on; this moves
## it, so a top box and full panniers sit the weight high and back and a big lump of an engine
## sits it low, and adds their spread to the inertia (luggage out the back makes it slow to turn).
func _compute_mass_spread() -> void:
	com_offset = Vector3.ZERO
	inertia_add = Vector3.ZERO
	var base := Vector3(0.0, com_height, 0.06)
	var extra := []   # [mass difference, position]
	for slot in PartsDB.SLOTS:
		var stock := PartsDB.get_part(str(PartsDB.DEFAULT_BUILD.get(slot, "none")))
		var m0 := float(stock.get("mass", float(stock.get("mass_per_cyl", 0.0)) * 2.0))
		var dm := (_part_mass(slot) if has_part(slot) else 0.0) - m0
		if absf(dm) < 0.01:
			continue
		var spot: Array = part_spot(slot)
		extra.append([dm, Vector3(0.0, float(spot[1]), (float(spot[0]) - 0.5) * wheelbase)])
	var spot_tank: Array = PART_SPOT["tank"]
	extra.append([(fuel_litres - aux_litres - 15.0) * FUEL_DENSITY, Vector3(0.0, float(spot_tank[1]), (float(spot_tank[0]) - 0.5) * wheelbase)])
	if aux_litres > 0.0:
		var spot_aux := part_spot("aux_tank")
		extra.append([aux_litres * FUEL_DENSITY, Vector3(0.0, float(spot_aux[1]), (float(spot_aux[0]) - 0.5) * wheelbase)])
	for e in extra:
		com_offset += float(e[0]) * ((e[1] as Vector3) - base) / maxf(total_mass, 1.0)
	com_offset = com_offset.clamp(Vector3(0.0, -0.1, -0.12), Vector3(0.0, 0.1, 0.12))
	var com := base + com_offset
	for e in extra:
		var d: Vector3 = (e[1] as Vector3) - com
		inertia_add += float(e[0]) * Vector3(d.y * d.y + d.z * d.z, d.z * d.z, d.y * d.y)
	com_height += com_offset.y


## The chain soaks up some power on its own; a dry one more, and a slack or tight one more again.
func _compute_chain() -> void:
	var chain := part("chain")
	var c: Dictionary = condition.get("chain", {})
	chain_slack = clampf(float(c.get("slack", 30.0)), 5.0, 90.0)
	chain_lube = clampf(float(c.get("lube", 1.0)), 0.0, 1.0)
	var loss := float(chain.get("friction", 0.025)) * (1.0 + (1.0 - chain_lube) * 2.5)
	if chain_slack > 40.0:
		loss += (chain_slack - 40.0) * 0.0012
		notes.append("The chain is slapping about: tighten it (crouch, wrench, {work2})." if chain_slack < 65.0
			else "The chain is so slack it could jump off! Tighten it.")
	elif chain_slack < 20.0:
		loss += (20.0 - chain_slack) * 0.002
		notes.append("The chain is too tight and will wear the sprockets. Slacken it off.")
	if chain_lube < 0.3:
		notes.append("The chain is dry and rusty-sounding. Give it some chain lube.")
	drivetrain_efficiency *= (1.0 - loss) * lerpf(0.9, 1.0, health["chain"])


## A shock's progression from its type, for one in the catalogue without its own.
static func _shock_progression(kind: String) -> float:
	var t := kind.to_lower()
	for key in ["air", "linkage", "mono", "twin"]:
		if t.contains(key):
			return float(SHOCK_PROGRESSION[key])
	return 0.2


## The spring's push at the wheel (N) squashed `q` m into its `travel`, preloaded `pre` m.
static func spring_force(rate: float, q: float, travel: float, progression: float, pre: float) -> float:
	var x := q / maxf(travel, 0.01)
	return rate * (q + pre + progression * q * x * x)


## Where the back axle is (bike space) with the shock squashed `q` m along the wheel's travel:
## swung up round the swingarm pivot.
func rear_axle_at(q: float) -> Vector3:
	var arm := Vector3(0.0, 0.0, wheelbase * 0.5) - swing_pivot
	return swing_pivot + arm.rotated(Vector3.RIGHT, -q / maxf(swing_length, 0.2))


## The way the back axle moves as the shock squashes further from `q` (bike space, unit): square
## to the swingarm, up and a little back (forward once the arm's swung past level).
func rear_path_at(q: float) -> Vector3:
	var arm := rear_axle_at(q) - swing_pivot
	return Vector3(0.0, arm.z, -arm.y).normalized()


## The way the chain pulls the back sprocket (bike space, unit, towards the gearbox sprocket)
## with the back axle at `axle`: the top run under power, the bottom run on the over-run
## (engine braking).
func chain_pull_at(axle: Vector3, top := true) -> Vector3:
	var front := swing_pivot + COUNTERSHAFT
	var d := axle - front
	var dist := maxf(d.length(), 0.1)
	var dn := d / dist
	var side := Vector3(0.0, dn.z, -dn.y) * (1.0 if top else -1.0)
	# The run is the line touching both sprockets on that side.
	var s := clampf(-(sprocket_r_rear - sprocket_r_front) / dist, -0.9, 0.9)
	var m := side * sqrt(1.0 - s * s) + dn * s
	return -((axle + m * sprocket_r_rear) - (front + m * sprocket_r_front)).normalized()


## Anti-squat with the back squashed `q` m: how much of the extra load the back tyre takes under
## power (the weight going back) the swingarm's angle and the chain's pull hold off the shock. 1
## is 100%: the back neither squats nor rises as it drives.
func anti_squat_at(q: float) -> float:
	var t := rear_path_at(q)
	var axle := rear_axle_at(q)
	var forward := Vector3(0.0, 0.0, -1.0)
	# Per newton of drive at the road: the push along the road and the chain's pull (both lift
	# the back on a sloping arm) against the weight coming onto the back wheel.
	var hold := -(forward.dot(t) + rear_radius / sprocket_r_rear * chain_pull_at(axle).dot(t))
	var gain := com_height / wheelbase * t.y
	return hold / maxf(gain, 1e-3)


## The sag at each end, the sprockets' sizes and the anti-squat at sag.
func _compute_squat() -> void:
	sprocket_r_front = CHAIN_PITCH / (2.0 * sin(PI / maxf(tune_value("sprocket_f"), 8.0)))
	sprocket_r_rear = CHAIN_PITCH / (2.0 * sin(PI / maxf(tune_value("sprocket_r"), 8.0)))
	# The weight on each wheel standing still, from where the centre of mass sits.
	var behind := clampf(0.5 + (0.06 + com_offset.z) / wheelbase, 0.2, 0.8)
	front_sag = _sag(total_mass * 9.81 * (1.0 - behind) * fork_path.y, front_spring, front_travel, front_progression, front_preload)
	rear_sag = _sag(total_mass * 9.81 * behind * rear_path_at(0.0).y, rear_spring, rear_travel, rear_progression, rear_preload)
	anti_squat = anti_squat_at(rear_sag)


## How far a spring squashes (m) under `weight` N along its travel.
static func _sag(weight: float, rate: float, travel: float, progression: float, pre: float) -> float:
	var lo := 0.0
	var hi := travel
	for i in 30:
		var mid := (lo + hi) * 0.5
		if spring_force(rate, mid, travel, progression, pre) > weight:
			hi = mid
		else:
			lo = mid
	return lo


## Power per kilo with the rider on: the number weight-saving parts improve.
## Whether the ECU gives this rider aid: "traction", "abs", "anti_wheelie" or "stability".
func has_aid(aid: String) -> bool:
	return ecu_features.has(aid)


## How firmly an aid steps in as it's set on the dyno desk: 0 when the ECU hasn't got it or it's
## switched off, the ECU's own `ecu_aid` at the factory level, up to 1.2 at the firmest. Aids
## the desk doesn't set (ABS) are always at the factory level.
func aid_strength(aid: String) -> float:
	if not has_aid(aid):
		return 0.0
	if not AID_KEYS.has(aid):
		return ecu_aid
	var level := clampi(roundi(tune_value(str(AID_KEYS[aid]))), 0, AID_LEVELS)
	var mode := _mode()
	if not mode.is_empty():
		level = int(mode[aid])
	return clampf(ecu_aid * AID_SCALE[level], 0.0, 1.2)


## A ride mode's name on the dash ("" is Custom: the levels set on the dyno desk).
static func mode_name(mode: String) -> String:
	return str(RIDE_MODES[mode]["name"]) if RIDE_MODES.has(mode) else "Custom"


## Whether the dash offers ride modes: one with "modes", on an ECU with rider aids to set.
func has_ride_modes() -> bool:
	return dash_features.has("modes") and not ecu_features.is_empty()


## The ride mode in use (see RIDE_MODES), or {} when there's none.
func _mode() -> Dictionary:
	return RIDE_MODES.get(ride_mode, {}) if ride_mode != "" and has_ride_modes() else {}


## How much of the engine's power the ride mode lets through (1 with none).
func mode_power() -> float:
	return float(_mode().get("power", 1.0))


## How quickly the ride mode lets the throttle open (a share a second), 0 for straight away.
func mode_throttle_rate() -> float:
	return float(_mode().get("rate", 0.0))


## Whether the ABS looks after this wheel: always the front, the back unless the ride mode is Sport.
func abs_on(is_front: bool) -> bool:
	if not has_aid("abs"):
		return false
	return is_front or bool(_mode().get("abs_rear", true))


## Whether the ECU has this aid and it's switched on.
func aid_on(aid: String) -> bool:
	return aid_strength(aid) > 0.0


func power_to_weight() -> float:
	return hp() / maxf(total_mass, 1.0)


func _compute_wheels() -> void:
	var tf := part("front_tyre")
	var tr := part("rear_tyre")
	var wf := part("front_wheel")
	var wr := part("rear_wheel")
	front_rim_radius = float(wf["diameter"]) * 0.0127
	rear_rim_radius = float(wr["diameter"]) * 0.0127
	front_tyre_width = float(tf["width"]) / 1000.0
	rear_tyre_width = float(tr["width"]) / 1000.0
	front_radius = front_rim_radius + front_tyre_width * float(tf["aspect"])
	rear_radius = rear_rim_radius + rear_tyre_width * float(tr["aspect"])
	tyre_style = tr["style"]
	grip_front = {}
	grip_rear = {}
	grip = {}
	var scale_f := lerpf(0.7, 1.0, health["front_tyre"]) * lerpf(0.92, 1.0, health["front_wheel"])
	var scale_r := lerpf(0.7, 1.0, health["rear_tyre"]) * lerpf(0.92, 1.0, health["rear_wheel"])
	# Section width: a wider tyre lays more rubber on tarmac, a narrow one cuts into mud. A tyre
	# can only be fitted to a rim it suits (on the tyre changer), but a bike from an older save may
	# still wear one that doesn't: it's pinched or ballooned and the contact patch suffers.
	var fit_f := rim_fit(str(parts.get("front_tyre", "")), str(parts.get("front_wheel", "")))
	var fit_r := rim_fit(str(parts.get("rear_tyre", "")), str(parts.get("rear_wheel", "")))
	for fit in [[fit_f, "front", tf, wf], [fit_r, "rear", tr, wr]]:
		if fit[0] == 2:
			notes.append("The %s tyre isn't made for a %s rim. Change it on the tyre changer." % [fit[1],
				PartsDB.inch_text(float(fit[3].get("diameter", 17.0)))])
		elif fit[0] != 0:
			notes.append("The %s tyre is too %s for its %.1f\" rim. Change it on the tyre changer." % [fit[1],
				"wide" if fit[0] > 0 else "narrow", float(fit[3].get("rim_width", 0.0))])
	# A bead that wasn't seated properly on the changer lets the tyre squirm on the rim.
	var bead_f := float(condition.get("front_tyre", {}).get("bead", 1.0))
	var bead_r := float(condition.get("rear_tyre", {}).get("bead", 1.0))
	for b in [[bead_f, "front"], [bead_r, "rear"]]:
		if float(b[0]) < BEAD_OK:
			notes.append("The %s tyre's bead isn't seated right: it grips less and loses pressure. Refit it on the tyre changer." % b[1])
	for surf in tr["grip"]:
		var road: bool = surf == "tarmac"
		grip_front[surf] = float(tf["grip"][surf]) * scale_f * _width_grip(front_tyre_width, road) * (0.9 if fit_f != 0 else 1.0) * bead_grip(bead_f)
		grip_rear[surf] = float(tr["grip"][surf]) * scale_r * _width_grip(rear_tyre_width, road) * (0.9 if fit_r != 0 else 1.0) * bead_grip(bead_r)
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	# Tyre pressures: off the tyre's best, it grips less on tarmac. A little soft finds more
	# grip in the dirt, but squirms, drags and wears.
	# A punctured tyre has lost air from that: nearly flat, it folds and rolls on the rim.
	for side in ["front", "rear"]:
		deflate[side] = maxf(float(condition.get(side + "_tyre", {}).get("deflate", 0.0)), 0.0)
	var dev_f := pressure_offset("front")
	var dev_r := pressure_offset("rear")
	flat["front"] = Puncture.flat_of(pressure_now("front"), tune_default("psi_f"))
	flat["rear"] = Puncture.flat_of(pressure_now("rear"), tune_default("psi_r"))
	for surf in grip_rear:
		grip_front[surf] *= _pressure_grip(dev_f, surf) * Puncture.flat_grip(flat["front"])
		grip_rear[surf] *= _pressure_grip(dev_r, surf) * Puncture.flat_grip(flat["rear"])
		grip[surf] = (grip_front[surf] + grip_rear[surf]) * 0.5
	rolling = ROLLING * (clampf(1.0 - 0.9 * dev_f, 0.6, 2.5) * (1.0 + Puncture.FLAT_DRAG * flat["front"])
		+ clampf(1.0 - 0.9 * dev_r, 0.6, 2.5) * (1.0 + Puncture.FLAT_DRAG * flat["rear"])) * 0.5
	for side in ["front", "rear"]:
		if flat[side] > 0.0:
			notes.append("The %s tyre is flat: it wallows and grips badly, and riding on it ruins the tyre and rim. Plug it, or change it, and pump it up." % side)
		elif float(condition.get(side + "_tyre", {}).get("puncture", 0.0)) > 0.0:
			notes.append("The %s tyre has a puncture: it's losing air. Plug it, or change it on the tyre changer." % side)
	tyre_wear = {"front": 1.0 + 2.5 * absf(dev_f), "rear": 1.0 + 2.5 * absf(dev_r)}
	if minf(dev_f, dev_r) < -0.3 and maxf(flat["front"], flat["rear"]) == 0.0:   # a flat one says so itself
		notes.append("The tyres are soft: they'll squirm, drag and wear out fast.")
	elif maxf(dev_f, dev_r) > 0.3:
		notes.append("The tyres are rock hard: less grip, and they skip over bumps.")
	var mass_f := _part_mass("front_wheel") + float(tf["mass"])
	var mass_r := _part_mass("rear_wheel") + float(tr["mass"])
	front_inertia = 0.8 * mass_f * front_radius * front_radius
	rear_inertia = 0.8 * mass_r * rear_radius * rear_radius + 0.15  # plus spinning drivetrain
	tyre_front = tyre_params(tf, dev_f)
	tyre_rear = tyre_params(tr, dev_r)
	var fork := part("fork")
	fork_offset = float(fork.get("offset", FORK_OFFSET.get(str(fork.get("style", "")), 0.04)))
	# A manufacturer's prototype can come with yokes of its own, offset more than the fork's.
	fork_offset += _proto("fork", "offset")
	trail = clampf(trail_of(front_radius, rake_deg, fork_offset), -0.05, 0.4)
	if trail < SHORT_TRAIL:
		notes.append("The trail is very short (%d mm): the steering will be nervous and may shake its head. Fit a fork with less offset, or a steering damper." % roundi(trail * 1000.0))
	# What swings with the bars, about the steering axis: the wheel (about its diameter, and
	# carried round on the offset), the fork legs either side, and what's bolted to the front end.
	steer_mass = mass_f + _part_mass("front_disc") + _part_mass("front_caliper")
	steer_inertia = 0.5 * front_inertia + (mass_f + _part_mass("front_disc")) * fork_offset * fork_offset + 0.012 * float(fork.get("mass", 9.0))
	for spot in [["handlebars", 0.3], ["dashboard", 0.22], ["headlight", 0.26], ["fog_lights", 0.2], ["front_mudguard", 0.2],
			["front_caliper", 0.16], ["front_master", 0.3], ["mirrors", 0.4]]:
		if has_part(spot[0]):
			steer_inertia += _part_mass(spot[0]) * float(spot[1]) * float(spot[1])
	# The steering damper: a worn, leaky one damps less, and its clicker firms it up or softens it.
	var damper := part("steering_damper")
	var dh := float(health.get("steering_damper", 1.0))
	var click := 1.0 + 0.6 * tune_value("damper")
	damper_damping = float(damper.get("damping", 0.0)) * lerpf(0.4, 1.0, dh) * click
	damper_friction = float(damper.get("friction", 0.0)) * lerpf(0.5, 1.0, dh) * click


## The trail a set of parts gives (m), straight from the catalogue: the frame's rake, the fork's
## offset and the front wheel and tyre's size.
static func parts_trail(build: Dictionary) -> float:
	var frame := PartsDB.get_part(str(build.get("frame", "")))
	var fork := PartsDB.get_part(str(build.get("fork", "")))
	var wheel := PartsDB.get_part(str(build.get("front_wheel", "")))
	var tyre := PartsDB.get_part(str(build.get("front_tyre", "")))
	var radius := float(wheel.get("diameter", 17.0)) * 0.0127 + float(tyre.get("width", 120.0)) / 1000.0 * float(tyre.get("aspect", 0.7))
	var offset := float(fork.get("offset", FORK_OFFSET.get(str(fork.get("style", "")), 0.04)))
	return trail_of(radius, float(frame.get("rake_deg", 25.0)), offset)


## How quickly a bike built of `parts` rolls between leans, as a multiple of an ordinary bike's: a
## proper sports, race or naked bike gets all of its style's FLICK, a bike that is mostly one (its
## style all over, short of proper) a share of it by how much of it agrees, and anything else 1.
static func flick_of(parts: Dictionary) -> float:
	var d := PartsDB.detect_style(parts)
	var st := str(d.get("style", ""))
	if not FLICK.has(st):
		return 1.0
	var share := clampf(float(d.get("coherence", 0.0)) / PartsDB.PROPER_STYLE, 0.0, 1.0)
	return 1.0 + (float(FLICK[st]) - 1.0) * share


## Bikes that turn up already built (project bikes, customers' bikes) were put together by
## someone who knew what they were doing: a fork that leaves the trail under STOCK_TRAIL is
## swapped for one that suits the frame. Only a player can build a bike that shakes its head.
static func sensible_fork(build: Dictionary, seed_value := 0) -> Dictionary:
	if parts_trail(build) >= STOCK_TRAIL:
		return build
	var out := build.duplicate()
	var frame_styles: Array = PartsDB.styles_of(str(build.get("frame", "")))
	var fits := []
	var any := []
	for id in PartsDB.by_kind.get("fork", []):
		out["fork"] = id
		if parts_trail(out) >= STOCK_TRAIL:
			any.append(id)
			if PartsDB.styles_of(str(id)).any(func(s): return frame_styles.has(s)):
				fits.append(id)
	var from: Array = fits if not fits.is_empty() else any
	out["fork"] = from[absi(seed_value) % from.size()] if not from.is_empty() else build.get("fork", "")
	return out


## Mechanical trail (m) for a front wheel of rolling radius `radius` on a steering head raked back
## `rake_deg`, with the axle `offset` ahead of the steering axis: how far the contact patch trails
## the point where the axis meets the road.
static func trail_of(radius: float, rake_deg: float, offset: float) -> float:
	var rake := deg_to_rad(rake_deg)
	return (radius * sin(rake) - offset) / cos(rake)


## A tyre's Magic Formula numbers (TyreModel.params_of) at a pressure `dev` off its best: soft
## squirms (slips further before it peaks, builds grip over a longer roll), hard is twitchier.
static func tyre_params(tyre: Dictionary, dev := 0.0) -> Dictionary:
	var p := TyreModel.params_of(tyre)
	var firm := clampf(1.0 + 0.35 * dev, 0.75, 1.2)
	p["kappa_peak"] = float(p["kappa_peak"]) / firm
	p["alpha_peak"] = float(p["alpha_peak"]) / firm
	p["relax"] = float(p["relax"]) / firm
	return p


## Grip from a tyre's section width (metres): wider grips tarmac better, narrower digs into dirt.
static func _width_grip(width: float, tarmac: bool) -> float:
	var mm := width * 1000.0
	if tarmac:
		return clampf(1.0 + 0.14 * (mm - 160.0) / 160.0, 0.9, 1.06)
	return clampf(1.0 - 0.1 * (mm - 120.0) / 120.0, 0.9, 1.06)


## Whether a tyre suits a wheel's rim: 0 if it does, 1 too wide, -1 too narrow, 2 made for a
## different rim diameter (see PartsDB.tyre_fit).
static func rim_fit(tyre_id: String, wheel_id: String) -> int:
	return PartsDB.tyre_fit(tyre_id, wheel_id)


## Grip from how well a tyre's bead was seated on the changer, 0..1: a sloppy job costs up to 8%.
static func bead_grip(bead: float) -> float:
	return lerpf(0.92, 1.0, clampf(bead / BEAD_OK, 0.0, 1.0))


func _compute_engine(block: Dictionary, head: Dictionary) -> void:
	var fuel := part("fuel")
	var air := part("air_filter")
	var oil := part("oil_filter")
	var plugs := part("spark_plugs")
	var cooling := part("cooling")
	var exhaust := part("exhaust")
	layout = block["layout"]
	flat_dip = clampf(_proto("engine", "dip"), 0.0, 0.6)
	displacement = block["displacement"]
	peak_torque = displacement * float(block["torque_per_cc"])
	peak_torque_rpm = float(block["peak_torque_rpm"]) * float(head["peak_shift"]) * float(fuel["peak_shift"])
	var ecu := part("ecu")
	stock_redline = float(block["redline"]) + float(head["redline_add"]) + float(ecu.get("rev_add", 0.0))
	redline = stock_redline + tune_value("limiter")
	idle_rpm = block["idle_rpm"]
	friction_mult = float(head.get("thirst", 1.0))

	torque_mult = float(head["torque_mult"]) * lerpf(0.75, 1.0, health["head"]) * float(ecu.get("power", 1.0))
	# The fuel system has to keep up with the engine, or it runs lean and gutless. A big, slow-revving
	# engine breathes less air (and makes less heat) than its size alone says.
	var breathing := float(block.get("breathing", 1.0))
	var demand := displacement * float(head["peak_shift"]) * breathing
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
	engine_heat = displacement / 1000.0 * float(head["heat"]) * breathing * (1.0 + 0.15 * lean + 0.06 * maxf(tune_value("ignition"), 0.0))
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
	# A drum bites less than a disc its size: one cam (single leading shoe) least, two or four
	# leading shoes nearly as well.
	var drum := float({"sls": 0.7, "tls": 0.85, "4ls": 0.95}.get(str(disc.get("shoes", "sls")), 0.7)) if str(disc.get("style", "")) == "drum" else 1.0
	return 1600.0 * float(disc["diameter"]) / 300.0 * float(caliper["force"]) * float(pads["mu"]) / 0.42 \
		* float(master["ratio"]) * lerpf(0.5, 1.0, h) * fluid_mult * drum


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
	# Past its peak the torque fades faster than it builds, so power peaks a little short of the limiter.
	var shape := 1.0 - (0.7 if x < 0.0 else TORQUE_FADE) * x * x
	var t := peak_torque * clampf(shape, 0.3, 1.0)
	if x < 0.0:
		t *= 1.0 + tune_low * minf(-x * 2.0, 1.0)
	else:
		t *= 1.0 + tune_high * minf(x * 2.0, 1.0)
	if flat_dip > 0.0:
		# A flat spot: the torque sags through a band of revs below the peak, then comes back.
		var d := (rpm / peak_torque_rpm - FLAT_SPOT_AT) / FLAT_SPOT_WIDTH
		t *= 1.0 - flat_dip * exp(-d * d)
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
	var litres := (maxf(kw, 0.0) + friction_kw(rpm)) * FUEL_PER_KWH * (TWO_STROKE_THIRST if layout == "2stroke" else 1.0)
	return litres / maxf(economy_mult, 0.3)


## kW the engine spends turning itself over at `rpm`: friction and pumping, a mean pressure on the
## pistons over one power stroke every two turns.
func friction_kw(rpm: float) -> float:
	var rpm_on := maxf(rpm, idle_rpm)
	var bar := (FRICTION_BAR + FRICTION_BAR_PER_KRPM * rpm_on / 1000.0) * friction_mult
	return bar * 100000.0 * displacement / 1000000.0 * rpm_on / 120.0 / 1000.0


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
		m *= 1.0 - lighten_cut(str(parts[slot]), float(condition[slot].get("lighten_extra", 0.0)))
	if slot == "toolbox":
		# What's packed in it weighs too.
		for c in condition.get(slot, {}).get("contents", []):
			m += float(PartsDB.TOOLBOX_CONTENTS.get(str(c), {}).get("mass", 0.0))
		m += float(condition.get(slot, {}).get("spares_kg", 0.0))   # and any spare parts (see ToolboxSpares)
	return m


## The fraction of a part's mass lightening it takes off: 0 for parts already built light or
## with nothing to trim. `extra` is how much more the Featherweight skill takes (0.1 = 10% more).
static func lighten_cut(part_id: String, extra := 0.0) -> float:
	if PartsDB.is_lightweight(part_id):
		return 0.0
	return minf(float(LIGHTEN.get(PartsDB.kind_of(part_id), 0.0)) * (1.0 + extra), 0.5)


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
	elif key.begins_with("aid_") and not has_aid(key.trim_prefix("aid_")):
		return "This ECU has no %s." % str(PartsDB.ECU_AID_NAMES.get(key.trim_prefix("aid_"), "rider aid"))
	elif key == "screen":
		if not has_part("fairing"):
			return "There's no fairing fitted."
		if float(part("fairing").get("screen_adjust", 0.0)) <= 0.0:
			return "This screen doesn't adjust."
	elif key == "damper":
		if not has_part("steering_damper"):
			return "There's no steering damper fitted."
		if int(part("steering_damper").get("adjust", 0)) < 1:
			return "This steering damper has no adjuster."
	return ""


## How far the ECU lets the fuel map and ignition move either way: a little with none fitted
## (jets and the ignition plate), all the way with a remap or race ECU.
func ecu_reach() -> float:
	return float(part("ecu").get("tune_range", 0.25)) if has_part("ecu") else 0.25


## The range a setting can take on this bike.
func tune_range(key: String) -> Vector2:
	var lim: Array = TUNE_LIMITS.get(key, [0.0, 0.0])
	var r := Vector2(float(lim[0]), float(lim[1]))
	# Tuned by someone with the Fine Tuning skill: the engine settings go a little further.
	var reach := 1.0 + float(tune.get("reach", 0.0))
	if key in ["map", "ignition"]:
		var e := minf(ecu_reach() * reach, float(lim[1]))
		r = Vector2(-e, e)
	elif key == "limiter":
		r.y = float(part("ecu").get("limiter_add", 0.0)) * reach if has_part("ecu") else 0.0
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
		"aid_traction", "aid_stability", "aid_anti_wheelie":
			return float(AID_STOCK)
	return 0.0


## A setting as it's applied: the tune's value kept within what the parts allow, or stock.
func tune_value(key: String) -> float:
	if not tune.has(key) or tune_block(key) != "":
		return tune_default(key)
	var r := tune_range(key)
	return clampf(float(tune[key]), r.x, r.y)


## How far a tyre is off its best pressure, as a fraction: -0.2 is 20% soft (-1 with no air in it).
func pressure_offset(side: String) -> float:
	var key := "psi_f" if side == "front" else "psi_r"
	var best := tune_default(key)
	return (pressure_now(side) - best) / best


## A tyre's cold pressure as it is, bar: what it's set to, less any air a puncture has let out.
func pressure_now(side: String) -> float:
	return maxf(tune_value("psi_f" if side == "front" else "psi_r") - float(deflate.get(side, 0.0)), 0.0)


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
	return zero_to(100.0)


## Seconds from a standstill to `kmh` (0-60 mph is 96.56 km/h), as zero_to_100; -1 when it never gets there.
func zero_to(kmh: float) -> float:
	var v := 0.0
	var t := 0.0
	var gear := 1
	var dt := 0.01
	var mu := float(grip_rear.get("tarmac", 1.0))
	var max_a := minf(mu * 9.81 * 0.75, 9.81 * wheelbase * 0.55 / com_height)
	while v < kmh / 3.6:
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
