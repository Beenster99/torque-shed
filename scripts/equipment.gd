class_name Equipment
extends RefCounted
## Everything for the shed that the parts computer sells besides parts: engine stands, shelving,
## parts washers, repair machines, workbenches, and posters, seats and TVs to make it home.
## Floor equipment is pushed about with F; posters and TVs hang on a wall.
##
## Each model has a kind, a footprint `size` (width, height, depth in metres) and, for the ones
## that hold parts, a number of places. Compact models are for a shed that's filling up.

const KINDS: Array[String] = ["stand", "shelf", "washer", "repair", "blaster", "bench", "trolley", "booth", "changer", "poster", "seat", "tv",
	"ramp", "obstacle", "barrier", "marker"]
const KIND_NAMES := {"stand": "Engine stands", "shelf": "Shelving", "washer": "Parts washers",
	"repair": "Repair machines", "blaster": "Sandblasting cabinets", "bench": "Workbenches", "trolley": "Trolleys", "booth": "Paint booths", "changer": "Tyre changers", "poster": "Wall posters", "seat": "Seats", "tv": "Wall TVs",
	"ramp": "Jump ramps", "obstacle": "Things to jump", "barrier": "Walls and fences", "marker": "Cones, posts and flags", "whiteboard": "Whiteboard",
	"trinket": "Trinkets"}
## Kinds that live outside in the yard, to ride over, round and through.
const YARD_KINDS: Array[String] = ["ramp", "obstacle", "barrier", "marker"]
## Kinds that hang on a wall rather than stand on the floor. The crew whiteboard is one too,
## though it comes with the shed rather than being sold (it isn't in KINDS).
const WALL_KINDS: Array[String] = ["poster", "tv", "whiteboard"]
## Kinds whose top is a free surface: parts go down anywhere on it there's room for them, as
## many as fit, rather than in a set number of places (see Shed.surface). Each board of a
## shelving unit is a surface of its own. A trolley's deck is one too: what's on it rolls along
## with it when it's pushed.
const SURFACE_KINDS: Array[String] = ["washer", "repair", "bench", "shelf", "trolley"]
## Kept clear round the edge of a surface, in metres.
const SURFACE_MARGIN := 0.05
## What the places on each kind are called in spot names: "<prefix>_<furniture id>_<n>".
## Kinds built into the shed: not sold, and can't be moved.
const FIXED_KINDS: Array[String] = ["booth", "changer"]
const SPOT_PREFIX := {"shelf": "shelf", "washer": "washer", "repair": "repair", "bench": "wb", "trolley": "trolley", "booth": "booth", "changer": "changer",
	"blaster": "blast"}
## The model each kind defaults to (and what an order without a model gets).
const DEFAULT := {"stand": "engine_stand", "shelf": "shelf_standard", "washer": "washer_standard",
	"repair": "repair_standard", "blaster": "blaster_cabinet", "bench": "bench_standard", "trolley": "trolley_parts", "booth": "booth_standard", "changer": "tyre_changer", "poster": "poster_tt", "seat": "seat_stool", "tv": "tv_120",
	"ramp": "ramp_medium", "obstacle": "barrels", "barrier": "wall_concrete", "marker": "cone", "whiteboard": "whiteboard"}

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
		"cols": 3, "levels": 5, "desc": "Five shelves up to the rafters. Same floor space as the standard unit, more shelf space."},
	"shelf_wide": {"kind": "shelf", "name": "Wide shelving", "size": Vector3(1.8, 2.0, 0.55),
		"cols": 4, "levels": 4, "desc": "Long boltless shelving for a whole bike's worth of parts."},
	"shelf_racking": {"kind": "shelf", "name": "Heavy-duty racking", "size": Vector3(2.4, 2.2, 0.6),
		"cols": 5, "levels": 4, "desc": "Warehouse pallet racking cut down for the shed. Holds engines and frames without bowing."},
	# The staff's parts rack in the storage room (Shed.STAFF_RACK): a board for each trade, not sold.
	"shelf_staff": {"kind": "shelf", "name": "Staff parts rack", "size": Vector3(1.8, 2.0, 0.55), "hidden": true,
		"cols": 4, "levels": 4, "desc": "The staff's own rack: the parts they've bought for a job and what's left over, a labelled board for each trade."},
	# The delivery racking fixed in the delivery area outside (Shed.DELIVERY_RACK): not sold.
	"shelf_delivery": {"kind": "shelf", "name": "Delivery racking", "size": Vector3(3.6, 2.2, 0.7), "hidden": true,
		"cols": 6, "levels": 4, "desc": "Racking in the delivery area: deliveries go on it when the floor's full."},

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

	# Sandblasting cabinets: an engine goes in whole, ancillaries and all, and you blast the rust
	# and muck off it by hand through the glove ports (see BlastGame). `rate` is how fast the
	# jet strips it, `jet` how wide it is.
	"blaster_cabinet": {"kind": "blaster", "name": "Sandblasting cabinet", "size": Vector3(1.7, 2.35, 1.7), "places": 1,
		"rate": 1.0, "jet": 1.0, "desc": "A glass-topped blast cabinet for engines. Put an engine in, hands in the gloves, and blast it back to bare metal."},
	"blaster_pro": {"kind": "blaster", "name": "Industrial blast cabinet", "size": Vector3(2.0, 2.45, 1.95), "places": 1,
		"rate": 1.35, "jet": 1.2, "desc": "A bigger cabinet with a bigger compressor: a wider, harder jet that strips an engine quicker. Easier to overdo, too."},

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

	# Trolleys: pushed about with F like other floor equipment, carrying whatever is on the deck.
	# The handle is at the front (+Z), the end you push from; `top` is the deck's height.
	"trolley_parts": {"kind": "trolley", "name": "Parts trolley", "compact": true, "size": Vector3(0.62, 0.95, 1.0), "places": 3,
		"top": 0.78, "desc": "A steel shop trolley on castors with a lipped deck. Load it up with parts and boxes and wheel them where they're needed."},
	"trolley_flatbed": {"kind": "trolley", "name": "Flatbed trolley", "size": Vector3(0.9, 0.95, 1.6), "places": 6,
		"top": 0.3, "desc": "A long, low platform truck for the heavy stuff: a whole delivery of boxes, an engine or a frame in one trip."},

	# Paint booths: parts hang from hooks on a rail, to be sprayed all over with the spray gun.
	"booth_compact": {"kind": "booth", "name": "Pop-up spray tent", "compact": true, "size": Vector3(1.6, 2.2, 1.4),
		"places": 2, "finish": 0.04, "desc": "A folding tent with an extractor fan. Two hooks: room for a tank and a mudguard."},
	"booth_standard": {"kind": "booth", "name": "Paint booth", "size": Vector3(2.6, 2.4, 1.8), "places": 4, "finish": 0.08,
		"desc": "Lit, filtered spray booth with four hooks on a rail. Hang the parts and go along them with the spray gun."},
	"booth_pro": {"kind": "booth", "name": "Downdraft spray booth", "size": Vector3(3.4, 2.5, 2.2), "places": 6, "finish": 0.12,
		"desc": "Pro booth: air pulled down through a floor grate so no dust lands in the paint. Six hooks."},
	# The paint shop's own spray bay: open topped under the shop's hex lights, two rails of five
	# hooks spaced so you can walk right round every part.
	"booth_shop": {"kind": "booth", "name": "Downdraft spray bay", "size": Vector3(8.0, 2.7, 4.7), "places": 10, "rails": 2,
		"open_top": true, "finish": 0.12,
		"desc": "The paint shop's spray bay: a floor grate pulls the air down, ten hooks on two rails with room to walk round each part."},

	# The tyre changer: a wheel lies on its turntable, and tyres are levered off and on there.
	"tyre_changer": {"kind": "changer", "name": "Tyre changer", "size": Vector3(0.8, 1.2, 0.9), "places": 1,
		"desc": "A pedestal tyre machine with a clamping turntable, a bead breaker and a mount head. Put a wheel on it to change its tyre."},

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

	# A print of a whiteboard drawing (the furniture's `design`, see Shed.posters). Ordered from
	# the parts computer's poster list, one entry for each saved design, not on its own.
	"poster_board": {"kind": "poster", "name": "Whiteboard poster", "size": Vector3(1.0, 0.5, 0.01), "hidden": true,
		"paper": Color(0.95, 0.96, 0.965), "desc": "The crew's own whiteboard drawing, printed and framed."},

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

	# Wall TVs: as big as the screens built into the shed, or bigger. Each one has channels: the
	# live riding feed, the crew board, XP goals, how to play, money and contracts (TvChannels).
	# 16:9 screens; the size is the panel, the bezel adds a little.
	"tv_120": {"kind": "tv", "name": "120\" wall TV", "size": Vector3(2.66, 1.5, 0.09), "inches": 120,
		"desc": "As big as the screens over the bays. Live riding, the crew board, XP goals and more: R changes the channel."},
	"tv_128": {"kind": "tv", "name": "128\" wall TV", "size": Vector3(2.83, 1.59, 0.09), "inches": 128,
		"desc": "Proper cinema size. Watch the crew ride from across the shed."},
	"tv_136": {"kind": "tv", "name": "136\" video wall", "size": Vector3(3.01, 1.69, 0.1), "inches": 136,
		"desc": "A whole wall of screen, as big as the crew board. Needs a clear stretch of wall."},

	# The crew whiteboard: one comes with the shed, on the front wall. F takes it down to hang it
	# on another wall, drawing and all (see Whiteboard). Not sold.
	"whiteboard": {"kind": "whiteboard", "name": "Crew whiteboard", "size": Vector3(2.47, 1.27, 0.05),
		"desc": "The crew's whiteboard for plans, lists and sketches. Take it down with {interact} and hang it on any wall."},

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


## The sizes every poster design is printed in: A2, A1 and A0 keep the design's shape with its
## long side this long; the large banner is a wide 2.4 by 0.8 m strip (a whiteboard print keeps
## its own shape, 2.4 m across). Posters bought before sizes came stay as they were.
const POSTER_SIZES := {"a2": {"name": "A2", "long": 0.594}, "a1": {"name": "A1", "long": 0.841},
	"a0": {"name": "A0", "long": 1.189}, "banner": {"name": "Large banner", "long": 2.4}}
const POSTER_SIZE_ORDER: Array[String] = ["a2", "a1", "a0", "banner"]
const POSTER_SIZE_DEFAULT := "a1"


## Model ids that have been renamed, old -> new, so saves made before still load. The wall TVs
## grew to match the shed's own screens.
## The model a whiteboard poster is printed on.
const BOARD_POSTER := "poster_board"
const RENAMED := {"tv_32": "tv_120", "tv_43": "tv_120", "tv_55": "tv_120", "tv_65": "tv_120", "tv_86": "tv_120",
	"tv_98": "tv_120", "tv_110": "tv_120"}


## The model an id means now: itself, or what it was renamed to.
static func current_id(id: String) -> String:
	return str(RENAMED.get(id, id))


## A model's entry: from MODELS, or a trinket bought in the Esc menu's Shop (Trinkets.MODELS).
static func get_model(id: String) -> Dictionary:
	return MODELS.get(id, Trinkets.MODELS.get(id, {}))


static func kind_of(id: String) -> String:
	return str(get_model(id).get("kind", ""))


## The models of a kind the shop lists (not the hidden whiteboard print).
static func by_kind(kind: String) -> Array:
	var out := []
	for id in MODELS:
		if MODELS[id]["kind"] == kind and not MODELS[id].get("hidden", false):
			out.append(id)
	return out


static func is_wall(id: String) -> bool:
	return WALL_KINDS.has(kind_of(id)) or bool(get_model(id).get("wall", false))


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
			bits.append("%d shelves: parts go anywhere on them, as many as fit" % int(m["levels"]))
		"washer":
			bits.append("Parts go anywhere in it, as many as fit")
			bits.append("Full speed with up to %d part%s" % [places(id), "" if places(id) == 1 else "s"])
			bits.append("Cleans in about %d s" % roundi(1.0 / float(m["rate"])))
		"blaster":
			bits.append("Takes an engine, ancillaries and all")
			bits.append("Blast x%.2f" % float(m["rate"]))
		"repair":
			bits.append("Parts go anywhere on it, as many as fit")
			bits.append("Full speed with up to %d part%s" % [places(id), "" if places(id) == 1 else "s"])
			bits.append("Speed x%.1f" % float(m["speed"]))
		"bench":
			bits.append("Parts go anywhere on top, as many as fit")
		"trolley":
			bits.append("Parts and boxes go anywhere on the deck and ride along when you push it")
			bits.append("Deck %.2f m high" % work_height(id))
		"whiteboard":
			bits.append("Draw, write and plan on it")
		"changer":
			bits.append("Takes one wheel at a time")
		"booth":
			bits.append("%d hooks" % places(id))
			bits.append("Spray gun finish +%d%%" % roundi(float(m["finish"]) * 100.0))
		"seat":
			bits.append("{interact}: sit down  ·  hold {interact}: move it")
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
		"booth":
			# Hooks along the rail (or rails, back to front), the parts hanging at chest height.
			var rails := maxi(1, int(m.get("rails", 1)))
			var per := ceili(maxi(1, places(model_id)) / float(rails))
			var w := size.x - 0.5
			var z := -0.1
			if rails > 1:
				z = lerpf(-size.z * 0.235, size.z * 0.235, float(mini(n / per, rails - 1)) / float(rails - 1))
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-w * 0.5 + w * (0.5 + n % per) / float(per), 0.85, z))
		"blaster":
			# On the turntable grate in the middle of the cabinet.
			return Transform3D(Basis(), Vector3(0.0, work_height(model_id), float(blaster_inside(model_id)["turn_z"])))
		"changer":
			# The wheel lies flat on the turntable (see Workshop), its hub on the centre post.
			return Transform3D(Basis(), Vector3(0.0, work_height(model_id), 0.08))
		"washer", "repair", "bench", "trolley":
			var count := maxi(1, places(model_id))
			var top := work_height(model_id)
			var w := size.x - 0.2
			var x := -w * 0.5 + w * (0.5 + n) / float(count)
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, top, 0.0))
	return Transform3D()


## The free surface on top of a washer, repair machine or workbench, in its own space: x across
## the front, y the depth (its z). Parts can go anywhere inside it.
static func surface_rect(model_id: String) -> Rect2:
	var size: Vector3 = get_model(model_id).get("size", Vector3.ONE)
	var w := maxf(0.1, size.x - SURFACE_MARGIN * 2.0)
	var d := maxf(0.1, size.z - SURFACE_MARGIN * 2.0)
	if model_id in ["washer_standard", "washer_industrial", "washer_cabinet"]:
		# The splash-back at the rear takes a strip off the depth.
		return Rect2(-w * 0.5, -d * 0.5 + 0.06, w, d - 0.06)
	return Rect2(-w * 0.5, -d * 0.5, w, d)


## How far apart a shelving unit's boards are.
static func shelf_pitch(model_id: String) -> float:
	var m := get_model(model_id)
	return (float(m.get("size", Vector3.ONE).y) - 0.15) / float(maxi(1, int(m.get("levels", 1))))


## The height parts sit at on board `level` of a shelving unit (0 is the bottom one). Parts left
## in the old numbered places sat at these heights too.
static func shelf_top(model_id: String, level: int) -> float:
	return 0.08 + level * shelf_pitch(model_id)


## Which board of a shelving unit something at height `y` (in its own space) is on.
static func shelf_level(model_id: String, y: float) -> int:
	var levels := int(get_model(model_id).get("levels", 1))
	return clampi(roundi((y - 0.08) / shelf_pitch(model_id)), 0, maxi(0, levels - 1))


## The size a poster of `model_id` is printed at in poster size `psize` (see POSTER_SIZES):
## width, height and depth before it's turned. "" (or one not known) is the design's own size.
static func poster_size(model_id: String, psize: String) -> Vector3:
	var native: Vector3 = get_model(model_id).get("size", Vector3(0.6, 0.85, 0.01))
	if not POSTER_SIZES.has(psize):
		return native
	var long := float(POSTER_SIZES[psize]["long"])
	if psize == "banner" and model_id != BOARD_POSTER:
		return Vector3(long, long / 3.0, native.z)
	var k := long / maxf(native.x, native.y)
	return Vector3(native.x * k, native.y * k, native.z)


## Height of the working surface parts sit on.
static func work_height(model_id: String) -> float:
	match kind_of(model_id):
		"washer":
			return 0.86 if model_id != "washer_compact" else 0.8
		"repair":
			return 0.96
		"blaster":
			return 0.72
		"changer":
			return 0.86
		"bench":
			return float(get_model(model_id)["size"].y) + 0.01
		"trolley":
			return float(get_model(model_id).get("top", 0.8))
	return 0.9


## The chamber of a sandblasting cabinet, in its own space: the grate the engine turns over
## (`floor`), the `roof`, the side walls (`half_w` either side), the `back` and `front` walls,
## the top of the low front wall the glass starts from (`front_top`), where the sloping glass
## meets the roof (`glass_z`), and where the turntable is (`turn_z`).
static func blaster_inside(model_id: String) -> Dictionary:
	var size: Vector3 = get_model(model_id).get("size", Vector3.ONE)
	var wall := 0.04
	var floor_y := work_height(model_id)
	var roof := size.y - 0.15
	var front_top := floor_y + 0.43
	return {"floor": floor_y, "roof": roof, "half_w": size.x * 0.5 - wall, "back": -size.z * 0.5 + wall,
		"front": size.z * 0.5 - wall, "front_top": front_top, "glass_z": size.z * 0.5 - wall - (roof - front_top) * 0.6,
		"turn_z": -size.z * 0.06}


## How high above the grate an engine of `size` (its box) turns in the sandblaster: high enough
## to tip right over without touching the grate.
static func blaster_lift(size: Vector3) -> float:
	return maxf(size.y * 0.5, Vector2(size.y, size.z).length() * 0.5) + 0.03


## Height of a paint booth's hook rail, in its own space: the parts' wires hang from it.
static func rail_height(model_id: String) -> float:
	return float(get_model(model_id).get("size", Vector3.ONE).y) - 0.35
