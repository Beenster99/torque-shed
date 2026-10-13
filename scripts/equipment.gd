class_name Equipment
extends RefCounted
## Everything for the shed that the parts computer sells besides parts: engine stands, shelving,
## parts washers, repair machines, workbenches, and posters, seats and TVs to make it home.
## Floor equipment is pushed about with F; posters and TVs hang on a wall.
##
## Each model has a kind, a footprint `size` (width, height, depth in metres) and, for the ones
## that hold parts, a number of places. Compact models are for a shed that's filling up.

const KINDS: Array[String] = ["stand", "shelf", "washer", "repair", "bench", "poster", "seat", "tv",
	"ramp", "obstacle", "barrier", "marker"]
const KIND_NAMES := {"stand": "Engine stands", "shelf": "Shelving", "washer": "Parts washers",
	"repair": "Repair machines", "bench": "Workbenches", "poster": "Wall posters", "seat": "Seats", "tv": "Wall TVs",
	"ramp": "Jump ramps", "obstacle": "Things to jump", "barrier": "Walls and fences", "marker": "Cones, posts and flags"}
## Kinds that live outside in the yard, to ride over, round and through.
const YARD_KINDS: Array[String] = ["ramp", "obstacle", "barrier", "marker"]
## Kinds that hang on a wall rather than stand on the floor.
const WALL_KINDS: Array[String] = ["poster", "tv"]
## What the places on each kind are called in spot names: "<prefix>_<furniture id>_<n>".
const SPOT_PREFIX := {"shelf": "shelf", "washer": "washer", "repair": "repair", "bench": "wb"}
## The model each kind defaults to (and what an order without a model gets).
const DEFAULT := {"stand": "engine_stand", "shelf": "shelf_standard", "washer": "washer_standard",
	"repair": "repair_standard", "bench": "bench_standard", "poster": "poster_tt", "seat": "seat_stool", "tv": "tv_43",
	"ramp": "ramp_medium", "obstacle": "barrels", "barrier": "wall_concrete", "marker": "cone"}

const MODELS := {
	# Engine stands hold one engine each.
	"engine_stand": {"kind": "stand", "name": "Engine stand", "size": Vector3(0.7, 0.9, 0.8), "places": 1,
		"desc": "A wheeled stand to strip and build an engine on. Get more than one and you can build engines while the bikes are being worked on."},
	"engine_stand_folding": {"kind": "stand", "name": "Folding engine stand", "compact": true, "size": Vector3(0.5, 0.9, 0.6), "places": 1,
		"desc": "Folds flat against a wall when it's not in use. Takes up less floor than the full-size stand."},

	# Shelving: cols x levels places. Every unit has a label plate on top.
	"shelf_compact": {"kind": "shelf", "name": "Compact shelving", "compact": true, "size": Vector3(0.8, 2.0, 0.45),
		"cols": 2, "levels": 4, "desc": "Narrow four-shelf unit that fits in the gaps."},
	"shelf_standard": {"kind": "shelf", "name": "Shelving unit", "size": Vector3(1.2, 2.0, 0.5),
		"cols": 3, "levels": 4, "desc": "Steel shelving for parts and boxed stock, with a label plate on top so everyone knows what goes where."},
	"shelf_tall": {"kind": "shelf", "name": "Tall shelving", "size": Vector3(1.2, 2.5, 0.5),
		"cols": 3, "levels": 5, "desc": "Five shelves up to the rafters. Same floor space as the standard unit, more places."},
	"shelf_wide": {"kind": "shelf", "name": "Wide shelving", "size": Vector3(1.8, 2.0, 0.55),
		"cols": 4, "levels": 4, "desc": "Long boltless shelving for a whole bike's worth of parts."},
	"shelf_racking": {"kind": "shelf", "name": "Heavy-duty racking", "size": Vector3(2.4, 2.2, 0.6),
		"cols": 5, "levels": 4, "desc": "Warehouse pallet racking cut down for the shed. Holds engines and frames without bowing."},

	# Parts washers: everything in one gets cleaned on its own, `rate` dirt a second.
	"washer_compact": {"kind": "washer", "name": "Benchtop parts washer", "compact": true, "size": Vector3(0.7, 1.0, 0.6),
		"places": 1, "rate": 0.14, "desc": "A small solvent tank on legs. One part at a time."},
	"washer_standard": {"kind": "washer", "name": "Parts washer", "size": Vector3(1.3, 1.6, 0.9),
		"places": 2, "rate": 0.18, "desc": "The classic solvent sink with a pump and brush. Two parts at once."},
	"washer_ultrasonic": {"kind": "washer", "name": "Ultrasonic cleaner", "compact": true, "size": Vector3(0.9, 1.1, 0.7),
		"places": 2, "rate": 0.35, "desc": "Shakes the grime off with sound. Small, quick and quiet."},
	"washer_cabinet": {"kind": "washer", "name": "Spray wash cabinet", "size": Vector3(1.2, 1.7, 1.0),
		"places": 3, "rate": 0.28, "desc": "Hot jets in a closed cabinet. Three parts on the turntable."},
	"washer_industrial": {"kind": "washer", "name": "Industrial parts washer", "size": Vector3(1.9, 1.7, 1.0),
		"places": 4, "rate": 0.25, "desc": "A big heated tank that takes a full engine's worth of parts."},

	# Repair machines: the grinder restores every part on one together, `speed` times as fast.
	"repair_compact": {"kind": "repair", "name": "Grinder stand", "compact": true, "size": Vector3(0.8, 1.2, 0.6),
		"places": 1, "speed": 0.9, "desc": "A pedestal grinder and a small vice. One part at a time."},
	"repair_standard": {"kind": "repair", "name": "Repair bench", "size": Vector3(1.8, 1.2, 0.9),
		"places": 2, "speed": 1.0, "desc": "Vice, grinder and welder on a steel bench. Two parts restored at once."},
	"repair_blaster": {"kind": "repair", "name": "Bead blast cabinet", "compact": true, "size": Vector3(1.1, 1.6, 0.8),
		"places": 2, "speed": 1.5, "desc": "Blasts rust off in a sealed cabinet. Small and fast."},
	"repair_pro": {"kind": "repair", "name": "Restoration station", "size": Vector3(2.2, 1.3, 1.0),
		"places": 3, "speed": 1.3, "desc": "Welder, grinder, lathe and press. Three parts at once."},
	"repair_workshop": {"kind": "repair", "name": "Machine shop bench", "size": Vector3(2.8, 1.4, 1.0),
		"places": 4, "speed": 1.6, "desc": "Everything a machinist needs. Four parts at once, and quick."},

	# Workbenches: places to lay parts out along the top.
	"bench_compact": {"kind": "bench", "name": "Folding workbench", "compact": true, "size": Vector3(1.0, 0.9, 0.6),
		"places": 2, "desc": "A sturdy fold-up bench. Two places."},
	"bench_mobile": {"kind": "bench", "name": "Mobile tool bench", "compact": true, "size": Vector3(1.2, 0.95, 0.6),
		"places": 2, "desc": "Tool chest on castors with a wooden top. Two places, and it goes where you need it."},
	"bench_standard": {"kind": "bench", "name": "Workbench", "size": Vector3(1.8, 0.95, 0.75),
		"places": 3, "desc": "A plain steel bench with a hardwood top. Three places."},
	"bench_long": {"kind": "bench", "name": "Long workbench", "size": Vector3(2.4, 0.95, 0.75),
		"places": 4, "desc": "Room to lay out a whole top end. Four places."},
	"bench_pro": {"kind": "bench", "name": "Pro workstation", "size": Vector3(2.4, 0.95, 0.8),
		"places": 4, "desc": "Drawers, pegboard and a stainless top. Four places, and it looks the business."},

	# Posters: art drawn on the paper.
	"poster_tt": {"kind": "poster", "name": "Island TT 1967 poster", "size": Vector3(0.6, 0.85, 0.01),
		"title": "ISLAND TT", "sub": "MOUNTAIN COURSE 1967", "paper": Color(0.92, 0.85, 0.66), "ink": Color(0.7, 0.08, 0.06),
		"band": Color(0.1, 0.2, 0.45), "desc": "Faded race poster from the golden age of road racing."},
	"poster_cafe": {"kind": "poster", "name": "Café racer club poster", "size": Vector3(0.6, 0.85, 0.01),
		"title": "CAFE RACERS", "sub": "TON UP BOYS - EST. 1959", "paper": Color(0.08, 0.08, 0.08), "ink": Color(0.95, 0.8, 0.2),
		"band": Color(0.85, 0.85, 0.82), "desc": "Black and gold club poster. Ton-up or bust."},
	"poster_mx": {"kind": "poster", "name": "Motocross nationals poster", "size": Vector3(0.6, 0.85, 0.01),
		"title": "MX NATIONALS", "sub": "SUNDAY - GATES 9AM", "paper": Color(0.95, 0.95, 0.92), "ink": Color(0.1, 0.1, 0.1),
		"band": Color(0.95, 0.45, 0.05), "desc": "Loud orange flyer for a muddy Sunday."},
	"poster_oil": {"kind": "poster", "name": "Gold Seal motor oil sign", "size": Vector3(0.9, 0.6, 0.01),
		"title": "GOLD SEAL", "sub": "MOTOR OIL - FOR MEN WHO RIDE", "paper": Color(0.1, 0.35, 0.2), "ink": Color(0.98, 0.85, 0.3),
		"band": Color(0.75, 0.1, 0.08), "desc": "Old enamel-look advert for an oil nobody makes any more."},
	"poster_salt": {"kind": "poster", "name": "Salt flats speed record poster", "size": Vector3(0.6, 0.85, 0.01),
		"title": "SPEED WEEK", "sub": "SALT FLATS - 1956", "paper": Color(0.85, 0.9, 0.95), "ink": Color(0.15, 0.25, 0.55),
		"band": Color(0.9, 0.2, 0.2), "desc": "Streamliners on the salt, chasing the record."},
	"poster_shed": {"kind": "poster", "name": "Torque Shed racing banner", "size": Vector3(1.4, 0.5, 0.01),
		"title": "TORQUE SHED RACING", "sub": "STRIP IT - FIX IT - RIDE IT", "paper": Color(0.12, 0.12, 0.14), "ink": Color(1.0, 0.85, 0.35),
		"band": Color(0.8, 0.12, 0.1), "desc": "The crew's own banner."},

	# Seats: F sits you down; hold F to move one.
	"seat_stool": {"kind": "seat", "name": "Shop stool", "compact": true, "size": Vector3(0.45, 0.7, 0.45), "sit": 0.68,
		"style": "stool", "color": Color(0.75, 0.1, 0.08), "desc": "Swivel stool with a red vinyl top."},
	"seat_creeper": {"kind": "seat", "name": "Creeper seat", "compact": true, "size": Vector3(0.5, 0.5, 0.6), "sit": 0.45,
		"style": "creeper", "color": Color(0.1, 0.1, 0.1), "desc": "Low roller seat with a tray underneath, for working on wheels and brakes."},
	"seat_chair": {"kind": "seat", "name": "Folding chair", "compact": true, "size": Vector3(0.5, 0.85, 0.5), "sit": 0.46,
		"style": "chair", "color": Color(0.2, 0.35, 0.2), "desc": "Canvas camp chair. For watching someone else do the work."},
	"seat_bench": {"kind": "seat", "name": "Garage bench seat", "size": Vector3(1.4, 0.8, 0.5), "sit": 0.46,
		"style": "bench", "color": Color(0.45, 0.28, 0.14), "desc": "Wooden slat bench for the whole crew."},
	"seat_sofa": {"kind": "seat", "name": "Old leather sofa", "size": Vector3(1.8, 0.85, 0.85), "sit": 0.45,
		"style": "sofa", "color": Color(0.35, 0.15, 0.08), "desc": "Saggy, cracked and the comfiest thing in the shed."},

	# Wall TVs: show whoever is out riding, or the crew board when nobody is.
	"tv_32": {"kind": "tv", "name": "32\" wall TV", "compact": true, "size": Vector3(0.72, 0.42, 0.06), "inches": 32,
		"desc": "Small screen. Shows whoever's out riding, from the chase camera, or the crew board when nobody is."},
	"tv_43": {"kind": "tv", "name": "43\" wall TV", "size": Vector3(0.96, 0.56, 0.06), "inches": 43,
		"desc": "Watch the crew ride from the shed. Shows the crew board when nobody is out."},
	"tv_55": {"kind": "tv", "name": "55\" wall TV", "size": Vector3(1.22, 0.7, 0.06), "inches": 55,
		"desc": "Big screen for the shed. Live riding feed, or the crew board."},
	"tv_65": {"kind": "tv", "name": "65\" wall TV", "size": Vector3(1.44, 0.82, 0.07), "inches": 65,
		"desc": "Cinema in the shed. Live riding feed, or the crew board."},

	# Yard kit: pushed about with F like the shed equipment. Ramps rise away from their front (+Z),
	# so ride at the low end. `solid` ones stop a bike; markers you can ride straight past.
	"ramp_small": {"kind": "ramp", "name": "Small kicker ramp", "size": Vector3(1.6, 0.45, 2.0), "solid": true,
		"desc": "A little wooden kicker. Hop a foot or two in the air."},
	"ramp_medium": {"kind": "ramp", "name": "Medium jump ramp", "size": Vector3(2.0, 0.9, 3.2), "solid": true,
		"desc": "Proper air. Steady throttle up the face and keep your weight central."},
	"ramp_large": {"kind": "ramp", "name": "Big jump ramp", "size": Vector3(2.6, 1.6, 4.8), "solid": true,
		"desc": "Steel-framed launch ramp. Bring speed, and a landing."},
	"ramp_landing": {"kind": "ramp", "name": "Landing ramp", "size": Vector3(2.8, 1.5, 7.0), "solid": true,
		"desc": "Long gentle slope to land on. Turn it to face a jump ramp, a bike's length or three away."},
	"tabletop": {"kind": "obstacle", "name": "Dirt tabletop", "size": Vector3(3.2, 1.2, 9.0), "solid": true,
		"desc": "Up, across the flat top, and down the far side. Clear the top for the big landing."},
	"barrels": {"kind": "obstacle", "name": "Row of oil drums", "size": Vector3(1.9, 0.62, 0.9), "solid": true,
		"desc": "Three drums on their sides. The classic stunt-show jump."},
	"log": {"kind": "obstacle", "name": "Log", "size": Vector3(2.4, 0.45, 0.45), "solid": true,
		"desc": "Trials practice: wheelie the front over and let the back follow."},
	"tyre_stack": {"kind": "obstacle", "name": "Tyre stack", "size": Vector3(0.75, 0.9, 0.75), "solid": true,
		"desc": "Old car tyres piled up. A marker you can lean on, or a target to miss."},
	"hay_bales": {"kind": "obstacle", "name": "Hay bales", "size": Vector3(2.2, 0.5, 1.0), "solid": true,
		"desc": "Two bales side by side. Soft-ish."},
	"car_wreck": {"kind": "obstacle", "name": "Old car", "size": Vector3(1.75, 1.35, 4.0), "solid": true,
		"desc": "A rusty saloon with no engine. Jump it, if you dare."},
	"wall_concrete": {"kind": "barrier", "name": "Concrete barrier", "size": Vector3(2.0, 0.8, 0.6), "solid": true,
		"desc": "Road-works barrier. Builds a track edge that stays put."},
	"wall_brick": {"kind": "barrier", "name": "Brick wall section", "size": Vector3(2.4, 1.2, 0.3), "solid": true,
		"desc": "A short run of brick wall on a frame."},
	"fence_wood": {"kind": "barrier", "name": "Wooden fence panel", "size": Vector3(2.4, 1.1, 0.12), "solid": true,
		"desc": "Post and rail fence for marking out a paddock."},
	"fence_mesh": {"kind": "barrier", "name": "Mesh fence panel", "size": Vector3(3.0, 2.0, 0.15), "solid": true,
		"desc": "Site fencing on concrete feet. Keeps spectators back."},
	"cone": {"kind": "marker", "name": "Traffic cone", "compact": true, "size": Vector3(0.36, 0.5, 0.36),
		"desc": "Orange cone for slaloms and braking markers. Ride through it, it won't hurt."},
	"post": {"kind": "marker", "name": "Marker post", "compact": true, "size": Vector3(0.15, 1.0, 0.15),
		"desc": "Black and yellow bollard post."},
	"flag_red": {"kind": "marker", "name": "Red course flag", "compact": true, "size": Vector3(0.6, 2.2, 0.1),
		"color": Color(0.85, 0.08, 0.05), "desc": "A flag on a pole to mark a turn."},
	"flag_blue": {"kind": "marker", "name": "Blue course flag", "compact": true, "size": Vector3(0.6, 2.2, 0.1),
		"color": Color(0.1, 0.25, 0.85), "desc": "A flag on a pole to mark the other side of a gate."},
	"flag_chequered": {"kind": "marker", "name": "Chequered flag", "compact": true, "size": Vector3(0.6, 2.2, 0.1),
		"color": Color(1, 1, 1), "desc": "Start, finish, or just showing off."},
}


static func get_model(id: String) -> Dictionary:
	return MODELS.get(id, {})


static func kind_of(id: String) -> String:
	return str(MODELS.get(id, {}).get("kind", ""))


static func by_kind(kind: String) -> Array:
	var out := []
	for id in MODELS:
		if MODELS[id]["kind"] == kind:
			out.append(id)
	return out


static func is_wall(id: String) -> bool:
	return WALL_KINDS.has(kind_of(id))


static func is_yard(id: String) -> bool:
	return YARD_KINDS.has(kind_of(id))


## How many parts one of these holds.
static func places(id: String) -> int:
	var m := get_model(id)
	if m.get("kind", "") == "shelf":
		return int(m["cols"]) * int(m["levels"])
	return int(m.get("places", 0))


## "Holds 12 parts  ·  1.2 x 0.5 m" for the parts computer.
static func spec_line(id: String) -> String:
	var m := get_model(id)
	var bits: Array[String] = []
	match str(m.get("kind", "")):
		"stand":
			bits.append("Holds one engine")
		"shelf":
			bits.append("%d shelves, %d places" % [int(m["levels"]), places(id)])
		"washer":
			bits.append("Washes %d part%s at once" % [places(id), "" if places(id) == 1 else "s"])
			bits.append("Cleans in about %d s" % roundi(1.0 / float(m["rate"])))
		"repair":
			bits.append("Restores %d part%s at once" % [places(id), "" if places(id) == 1 else "s"])
			bits.append("Speed x%.1f" % float(m["speed"]))
		"bench":
			bits.append("%d places on top" % places(id))
		"seat":
			bits.append("F: sit down  ·  hold F: move it")
		"tv":
			bits.append("%d inch" % int(m["inches"]))
		"ramp":
			bits.append("%.1f m high, %.1f m long" % [m["size"].y, m["size"].z])
		"obstacle", "barrier":
			bits.append("%.1f m high" % m["size"].y)
		"marker":
			bits.append("Ride past or through it")
	if is_yard(id):
		bits.append("For the yard outside")
	var size: Vector3 = m.get("size", Vector3.ONE)
	if is_wall(id):
		bits.append("%.2f x %.2f m  ·  hangs on a wall" % [size.x, size.y])
	else:
		bits.append("Floor space %.1f x %.1f m" % [size.x, size.z])
	if m.get("compact", false):
		bits.append("Compact")
	return "  ·  ".join(bits)


## Where place `n` sits on a piece of equipment, in its own space (+Z faces out the front).
static func local_place(model_id: String, n: int) -> Transform3D:
	var m := get_model(model_id)
	var size: Vector3 = m.get("size", Vector3.ONE)
	match str(m.get("kind", "")):
		"stand":
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0.0, 0.72, 0.0))
		"shelf":
			var cols := int(m["cols"])
			var levels := int(m["levels"])
			var pitch := (size.y - 0.15) / float(levels)
			var col_w := size.x / float(cols)
			return Transform3D(Basis(), Vector3(-size.x * 0.5 + col_w * (0.5 + n % cols), 0.08 + (n / cols) * pitch, 0.0))
		"washer", "repair", "bench":
			var count := maxi(1, places(model_id))
			var top := work_height(model_id)
			var w := size.x - 0.2
			var x := -w * 0.5 + w * (0.5 + n) / float(count)
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, top, 0.0))
	return Transform3D()


## Height of the working surface parts sit on.
static func work_height(model_id: String) -> float:
	match kind_of(model_id):
		"washer":
			return 0.86 if model_id != "washer_compact" else 0.8
		"repair":
			return 0.96
		"bench":
			return float(get_model(model_id)["size"].y) + 0.01
	return 0.9
