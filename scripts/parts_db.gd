extends Node
## Part catalogue loaded from data/parts.json. Parts come in kinds (fork, tyre, spark plugs...),
## and a bike has slots that each take one part of a kind. Front and rear slots share a kind,
## so a tyre fits either wheel. The engine is its own assembly: a block with slots of its own
## for the head, fuel system, filters, plugs, cooling and gearbox, built up on the engine stand.
## Parts mount onto each other, so some have to come off before others (see MOUNTS).

const KINDS: Array[String] = ["frame", "fork", "shock", "wheel", "tyre", "disc", "caliper", "pads", "master", "tank",
	"saddle", "handlebars", "dashboard", "engine", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling",
	"gearbox", "exhaust", "final_drive", "chain", "side_stand", "centre_stand", "headlight", "horn", "ecu",
	"panniers", "top_box", "fog_lights", "tail", "fairing", "mirrors", "front_mudguard", "indicators", "side_panels",
	"rearsets", "guards", "number_boards", "swingarm", "steering_damper"]
## Fluids come in containers you carry and pour; they don't bolt on anywhere.
const FLUID_KINDS: Array[String] = ["petrol", "oil", "brake_fluid", "chain_lube"]
const KIND_NAMES := {
	"frame": "Frame", "fork": "Front fork", "shock": "Rear suspension", "wheel": "Wheel", "tyre": "Tyre",
	"disc": "Brake disc", "caliper": "Brake caliper", "pads": "Brake pads", "master": "Master cylinder",
	"tank": "Fuel tank", "saddle": "Saddle", "handlebars": "Handlebars", "dashboard": "Dashboard",
	"engine": "Engine block", "head": "Cylinder head", "fuel": "Fuel system", "air_filter": "Air filter",
	"oil_filter": "Oil filter", "spark_plugs": "Spark plugs", "cooling": "Cooling", "gearbox": "Gearbox",
	"exhaust": "Exhaust", "final_drive": "Sprockets", "chain": "Chain", "side_stand": "Side stand", "centre_stand": "Centre stand",
	"headlight": "Headlight", "horn": "Horn", "ecu": "ECU", "panniers": "Panniers", "top_box": "Top box",
	"fog_lights": "Fog lights", "tail": "Tail unit", "fairing": "Fairing", "mirrors": "Mirrors", "front_mudguard": "Front mudguard", "indicators": "Indicators",
	"side_panels": "Side panels", "rearsets": "Footpegs and rearsets", "guards": "Engine guards", "number_boards": "Number boards",
	"swingarm": "Swingarm", "steering_damper": "Steering damper", "petrol": "Petrol", "oil": "Engine oil", "brake_fluid": "Brake fluid", "chain_lube": "Chain lube",
}
## Slots on the bike itself.
const BIKE_SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive", "chain",
	"side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box", "fog_lights", "tail", "fairing", "mirrors",
	"front_mudguard", "indicators", "side_panels", "rearsets", "guards", "number_boards", "swingarm", "steering_damper"]
## Bike slots a bike can be ridden without. "none" in a build means nothing is fitted there.
const OPTIONAL_SLOTS: Array[String] = ["side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box",
	"fog_lights", "fairing", "mirrors", "front_mudguard", "indicators", "side_panels", "rearsets", "guards", "number_boards",
	"swingarm", "steering_damper"]
## The bolt-on bits that finish a bike in its style (indicators, side panels, rearsets, guards,
## number boards and a swingarm of its own in place of the frame's). Bikes saved before they
## existed get the slots empty.
const FILLER_SLOTS: Array[String] = ["indicators", "side_panels", "rearsets", "guards", "number_boards", "swingarm"]
## Parts low down on a bike that you have to crouch to reach while it's in the frame.
const LOW_SLOTS: Array[String] = ["side_stand", "centre_stand", "oil_filter", "final_drive", "chain", "rearsets", "guards"]
## Slots on an engine block. They travel with the block when it comes out of the frame.
const ENGINE_SLOTS: Array[String] = ["head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox"]
## Engine parts you can change with the engine still in the frame. The rest need the engine stand.
const SERVICE_SLOTS: Array[String] = ["air_filter", "oil_filter", "spark_plugs"]
const SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive", "chain",
	"side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box", "fog_lights", "tail", "fairing", "mirrors", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox",
	"front_mudguard", "indicators", "side_panels", "rearsets", "guards", "number_boards", "swingarm", "steering_damper"]
const SLOT_KIND := {
	"frame": "frame", "fork": "fork", "shock": "shock", "front_wheel": "wheel", "rear_wheel": "wheel",
	"front_tyre": "tyre", "rear_tyre": "tyre", "front_disc": "disc", "rear_disc": "disc",
	"front_caliper": "caliper", "rear_caliper": "caliper", "front_pads": "pads", "rear_pads": "pads",
	"front_master": "master", "rear_master": "master", "tank": "tank", "saddle": "saddle",
	"handlebars": "handlebars", "dashboard": "dashboard", "engine": "engine", "exhaust": "exhaust",
	"final_drive": "final_drive", "chain": "chain", "head": "head", "fuel": "fuel", "air_filter": "air_filter",
	"oil_filter": "oil_filter", "spark_plugs": "spark_plugs", "cooling": "cooling", "gearbox": "gearbox",
	"side_stand": "side_stand", "centre_stand": "centre_stand", "headlight": "headlight", "horn": "horn", "ecu": "ecu",
	"panniers": "panniers", "top_box": "top_box", "fog_lights": "fog_lights", "tail": "tail", "fairing": "fairing",
	"mirrors": "mirrors", "front_mudguard": "front_mudguard", "indicators": "indicators", "side_panels": "side_panels",
	"rearsets": "rearsets", "guards": "guards", "number_boards": "number_boards", "swingarm": "swingarm",
	"steering_damper": "steering_damper",
}
const DEFAULT_BUILD := {
	"frame": "steel_cradle", "fork": "telescopic_road", "shock": "twin_shock", "front_wheel": "cast_17_front",
	"rear_wheel": "cast_17", "front_tyre": "sport_road_120", "rear_tyre": "sport_road", "front_disc": "floating_310",
	"rear_disc": "solid_240", "front_caliper": "four_piston_axial", "rear_caliper": "single_piston",
	"front_pads": "semi_metallic", "rear_pads": "semi_metallic", "front_master": "axial_14", "rear_master": "axial_14",
	"tank": "cafe_15", "saddle": "flat_bench", "handlebars": "flat_bar", "dashboard": "twin_clocks",
	"engine": "twin_700", "exhaust": "stock_muffler", "final_drive": "short_14_50", "chain": "oring_520", "head": "four_valve",
	"fuel": "twin_carbs", "air_filter": "paper_airbox", "oil_filter": "paper_oil", "spark_plugs": "iridium_plugs",
	"cooling": "oil_cooler", "gearbox": "five_wide", "side_stand": "stamped_side", "centre_stand": "none",
	"headlight": "round_7", "horn": "disc_horn", "ecu": "none", "panniers": "none", "top_box": "none", "fog_lights": "none",
	"tail": "classic_mudguard", "fairing": "none", "mirrors": "none", "front_mudguard": "chrome_classic", "indicators": "none",
	"side_panels": "none", "rearsets": "none", "guards": "none", "number_boards": "none", "swingarm": "none",
	"steering_damper": "none",
}
## What each slot bolts onto. A part can only go on once its mounts are fitted, and has to
## come off before any of them can. Engine slots mount on the block ("engine").
const MOUNTS := {
	"frame": [], "fork": ["frame"], "shock": ["frame"],
	"front_wheel": ["fork"], "rear_wheel": ["shock"],
	"front_tyre": ["front_wheel"], "rear_tyre": ["rear_wheel"],
	"front_disc": ["front_wheel"], "rear_disc": ["rear_wheel"],
	"front_caliper": ["front_disc"], "rear_caliper": ["rear_disc"],
	"front_pads": ["front_caliper"], "rear_pads": ["rear_caliper"],
	"handlebars": ["fork"], "dashboard": ["handlebars"], "front_master": ["handlebars"], "rear_master": ["frame"],
	"tank": ["frame"], "saddle": ["frame"],
	"engine": ["frame"], "exhaust": ["engine"], "final_drive": ["engine", "rear_wheel"], "chain": ["final_drive"],
	"head": ["engine"], "oil_filter": ["engine"], "cooling": ["engine"], "gearbox": ["engine"],
	"spark_plugs": ["head"], "fuel": ["head"], "air_filter": ["fuel"],
	"side_stand": ["frame"], "centre_stand": ["frame"], "headlight": ["fork"],
	"horn": ["frame"], "ecu": ["frame"], "panniers": ["frame"], "top_box": ["frame"], "fog_lights": ["fork"],
	# The tail unit carries the rear light and mudguard; a fairing goes on over the headlight;
	# mirrors bolt to the bars (or to the fairing, for parts that say so: see part_mounts).
	"tail": ["frame"], "fairing": ["headlight"], "mirrors": ["handlebars"],
	# The front mudguard bolts to the fork legs (or under the bottom yoke, for a high fender).
	"front_mudguard": ["fork"],
	# The style bits all bolt to the frame (rearsets replace the frame's own pegs).
	"indicators": ["frame"], "side_panels": ["frame"], "rearsets": ["frame"], "guards": ["frame"], "number_boards": ["frame"],
	# A swingarm of its own pivots in the frame in place of the one the frame comes with.
	"swingarm": ["frame"],
	# A steering damper links the frame to the fork's yokes.
	"steering_damper": ["fork"],
}
## Which fluid each part holds, and how much (litres; the tank and engine work theirs out).
const FLUID_HOLDERS := {"tank": "petrol", "engine": "oil", "master": "brake_fluid"}
const MASTER_FLUID := 0.25
const ECU_AID_NAMES := {"traction": "traction control", "abs": "ABS", "anti_wheelie": "anti-wheelie",
	"stability": "stability control"}

## What each kind of part is mostly made of, which decides the bin it goes in when it's thrown
## away (see bin_for). A part can say otherwise with its own "material" in data/parts.json:
## carbon bodywork, plastic or alloy luggage, a rubber bulb horn.
const KIND_MATERIAL := {
	"frame": "metal", "fork": "metal", "shock": "metal", "wheel": "metal", "tyre": "rubber", "disc": "metal",
	"caliper": "metal", "pads": "mixed", "master": "metal", "tank": "metal", "saddle": "mixed", "handlebars": "metal",
	"dashboard": "electronics", "engine": "metal", "head": "metal", "fuel": "metal", "air_filter": "mixed",
	"oil_filter": "metal", "spark_plugs": "mixed", "cooling": "metal", "gearbox": "metal", "exhaust": "metal",
	"final_drive": "metal", "chain": "metal", "side_stand": "metal", "centre_stand": "metal", "headlight": "electronics",
	"horn": "metal", "ecu": "electronics", "panniers": "fabric", "top_box": "plastic", "fog_lights": "electronics",
	"tail": "plastic", "fairing": "plastic", "mirrors": "mixed", "front_mudguard": "plastic",
	"indicators": "electronics", "side_panels": "plastic", "rearsets": "metal", "guards": "metal", "number_boards": "plastic",
	"swingarm": "metal", "steering_damper": "metal", "petrol": "metal", "oil": "plastic", "brake_fluid": "plastic", "chain_lube": "metal",
}
const MATERIAL_NAMES := {"metal": "Metal", "plastic": "Plastic", "rubber": "Rubber", "carbon": "Carbon fibre",
	"mixed": "Mixed materials", "electronics": "Electronics", "fabric": "Fabric", "leather": "Leather", "wood": "Wood"}
## The shed's three bins, by the roller door: general waste takes anything; the recycling
## bins take only their own material.
const BINS: Array[String] = ["general", "plastic", "metal"]
const BIN_NAMES := {"general": "General waste", "plastic": "Plastic recycling", "metal": "Metal recycling"}

var parts := {}    # part id -> Dictionary of stats (with "id" and "kind" added)
var by_kind := {}  # kind -> Array of part ids, in catalogue order


func _ready() -> void:
	load_catalogue("res://data/parts.json")


func load_catalogue(path: String) -> void:
	parts.clear()
	by_kind.clear()
	for k in KINDS + FLUID_KINDS:
		by_kind[k] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open part catalogue %s" % path)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	for k in data:
		for id in data[k]:
			var part: Dictionary = data[k][id]
			part["id"] = id
			part["kind"] = k
			parts[id] = part
			by_kind[k].append(id)


func get_part(id: String) -> Dictionary:
	return parts.get(id, {})


func part_name(id: String) -> String:
	return str(get_part(id).get("name", id))


func kind_of(id: String) -> String:
	return str(get_part(id).get("kind", ""))


## What a part is made of: "metal", "plastic", "rubber", "carbon", "mixed" and so on.
func material(id: String) -> String:
	var p := get_part(id)
	return str(p.get("material", KIND_MATERIAL.get(str(p.get("kind", "")), "mixed")))


## Which bin a part goes in: "metal" or "plastic" recycling, or "general" waste for the rest.
func bin_for(id: String) -> String:
	var m := material(id)
	return m if m in ["metal", "plastic"] else "general"


## "Metal: metal recycling bin" for the info panel.
func bin_text(id: String) -> String:
	var m := material(id)
	return "%s: goes in the %s bin" % [MATERIAL_NAMES.get(m, m.capitalize()), str(BIN_NAMES[bin_for(id)]).to_lower()]


func default_color(id: String) -> Color:
	var c: Array = get_part(id).get("color", [0.5, 0.5, 0.5])
	return Color(c[0], c[1], c[2])


## "Front brake caliper", "Rear tyre", "Spark plugs".
func slot_name(slot: String) -> String:
	var k: String = SLOT_KIND.get(slot, slot)
	var n: String = KIND_NAMES.get(k, slot)
	if n.begins_with("Front "):
		return n   # the front mudguard is front by kind already
	if slot.begins_with("front_"):
		return "Front " + n.to_lower()
	if slot.begins_with("rear_"):
		return "Rear " + n.to_lower()
	return n


func is_optional(slot: String) -> bool:
	return OPTIONAL_SLOTS.has(slot)


func is_fluid(id: String) -> bool:
	return FLUID_KINDS.has(kind_of(id))


## The fluid a part holds ("petrol", "oil", "brake_fluid"), or "" for parts that hold none.
## Fluid containers hold their own kind.
func fluid_kind(id: String) -> String:
	var k := kind_of(id)
	if FLUID_KINDS.has(k):
		return k
	return str(FLUID_HOLDERS.get(k, ""))


## How many litres a part holds: a tank its capacity, an engine its sump, a master cylinder
## its reservoir and brake line, a container what it says on the label.
func fluid_capacity(id: String) -> float:
	var p := get_part(id)
	match str(p.get("kind", "")):
		"tank":
			return float(p["capacity"])
		"engine":
			return snappedf(1.0 + float(p["displacement"]) / 400.0, 0.1)
		"master":
			return MASTER_FLUID
	if is_fluid(id):
		return float(p["litres"])
	return 0.0


## How much lighter this part is than the heaviest of its kind, in kg. Weight saving is free
## performance: less to accelerate, stop and turn.
func weight_saving(id: String) -> float:
	var k := kind_of(id)
	var p := get_part(id)
	if not p.has("mass") or FLUID_KINDS.has(k):
		return 0.0
	var heaviest := 0.0
	for other in by_kind.get(k, []):
		heaviest = maxf(heaviest, float(get_part(other).get("mass", 0.0)))
	return heaviest - float(p["mass"])


func is_lightweight(id: String) -> bool:
	return bool(get_part(id).get("lightweight", false))


func is_engine_slot(slot: String) -> bool:
	return ENGINE_SLOTS.has(slot)


## Every slot (bike or engine) that takes this kind of part.
func slots_for_kind(k: String) -> Array:
	var out := []
	for s in SLOTS:
		if SLOT_KIND[s] == k:
			out.append(s)
	return out


## Slots that bolt onto this one, which must be removed before it can come off. Engine parts
## ride along with the block, so they don't stop it coming out of the frame.
func dependents(slot: String) -> Array:
	var scope := ENGINE_SLOTS if is_engine_slot(slot) else BIKE_SLOTS
	var out := []
	for s in scope:
		if MOUNTS[s].has(slot):
			out.append(s)
	return out


## The key numbers of a part, for the parts computer and the info panel.
func spec_line(id: String) -> String:
	var p := get_part(id)
	var bits := []
	match str(p.get("kind", "")):
		"frame":
			bits = [p["type"], "%.2f m wheelbase" % p["wheelbase"], "%.0f° rake" % p["rake_deg"]]
		"fork", "shock":
			bits = [p["type"], "%d mm travel" % roundi(p["travel"] * 1000.0), "bump %d" % roundi(p["bump"]),
				"rebound %d" % roundi(p["rebound"]), "adjust: " + str(p["adjust_name"])]
			if p.has("offset"):
				bits.insert(2, "%d mm offset" % roundi(float(p["offset"]) * 1000.0))
		"wheel":
			var dia := float(p["diameter"])
			bits = [p["type"], ("%d\"" % roundi(dia)) if is_equal_approx(dia, roundf(dia)) else ("%.1f\"" % dia)]
			if p.has("rim_width"):
				var r := tyre_range(id)
				bits.append("%.2f\" rim: takes %d-%d mm tyres made for %s rims" % [float(p["rim_width"]), r.x, r.y, inch_text(dia)])
			if p.has("spokes"):
				bits.append("%d spokes" % int(p["spokes"]))
		"tyre":
			bits = [p["type"], p["compound"] + " compound", "%d mm wide, %d%% profile" % [int(p["width"]), roundi(float(p["aspect"]) * 100.0)],
				"fits " + tyre_rims_text(id), "grip %.2f tarmac / %.2f dirt" % [p["grip"]["tarmac"], p["grip"]["dirt"]]]
			bits.append(tyre_handling_text(p))
		"disc":
			bits = [p["type"], "%d mm" % int(p["diameter"])]
		"caliper":
			bits = [p["type"], "%d piston%s" % [p["pistons"], "" if p["pistons"] == 1 else "s"]]
		"pads":
			bits = [p["type"], "friction %.2f" % p["mu"]]
		"master":
			bits = [p["type"], "leverage %.2f" % p["ratio"]]
		"tank":
			bits = ["%d litres" % int(p["capacity"]), str(p["style"]).capitalize()]
		"saddle":
			bits = [str(p["style"]).capitalize(), "comfort %d%%" % roundi(p["comfort"] * 100.0)]
		"handlebars":
			bits = [p["style"], "%d mm wide" % int(p["width"])]
		"dashboard":
			bits = [", ".join(p["features"]).replace("_", " ")]
		"engine":
			bits = [p["type"], "%d cc" % int(p["displacement"]), "%.0f x %.1f mm" % [p["bore"], p["stroke"]],
				"redline %d" % int(p["redline"])]
		"head":
			bits = ["%d valves per cylinder" % int(p["valves"]), str(p["cam"]) + " cam", "%.1f:1" % p["compression"]]
		"fuel":
			bits = [p["type"], "feeds up to %d cc" % int(p["flow"])]
		"air_filter":
			bits = ["flow %+d%%" % roundi((p["flow"] - 1.0) * 100.0), "clogs x%.1f" % p["dirt_sensitivity"]]
		"oil_filter":
			bits = ["engine protection %d%%" % roundi(p["protection"] * 100.0)]
		"spark_plugs":
			bits = ["power %+d%%" % roundi((p["torque_mult"] - 1.0) * 100.0), "life %d%%" % roundi(p["life"] * 100.0)]
		"cooling":
			bits = [p["type"], "capacity %.1f" % p["capacity"]]
		"gearbox":
			bits = [p["type"], "%d speeds" % p["ratios"].size()]
			if p.get("cassette", false):
				bits.append("cassette: ratio spacing tunable")
		"exhaust":
			bits = ["power %+d%%" % roundi((p["torque_mult"] - 1.0) * 100.0), "loudness %d%%" % roundi(p["loudness"] * 100.0)]
		"final_drive":
			bits = [p["type"]]
		"chain":
			bits = [p["type"], "power loss %.1f%%" % (float(p["friction"]) * 100.0), "stretches %s" % ("slowly" if p["stretch"] < 6.0 else "fast" if p["stretch"] > 10.0 else "normally"),
				"lube lasts %s" % Units.distance(float(p["lube_life"]), 0)]
		"chain_lube":
			bits = [p["container"], "%.1f L (about %d coats)" % [p["litres"], roundi(float(p["litres"]) / 0.03)], "lasts x%.1f" % float(p["lasts"])]
		"side_stand":
			bits = [p["type"], "leans %d°" % int(p["lean"]), "springs up by itself" if p["auto_retract"] else "kick it up"]
		"centre_stand":
			bits = [p["type"], "lifts %d mm" % roundi(p["lift"] * 1000.0), "easy to lift" if p["effort"] < 0.8 else "a heave to lift"]
		"headlight", "fog_lights":
			bits = [p["type"], "%d lumens" % int(p["lumens"])]
		"horn":
			bits = [p["type"], "loudness %d%%" % roundi(float(p["loudness"]) * 100.0)]
		"ecu":
			var aids: Array = p["features"].filter(func(f): return f != "remap").map(func(f): return ECU_AID_NAMES.get(f, f))
			bits = ["Aids: " + (", ".join(aids) if not aids.is_empty() else "none"), "power %+d%%" % roundi((float(p["power"]) - 1.0) * 100.0)]
			if int(p["rev_add"]) > 0:
				bits.append("+%d rpm limit" % int(p["rev_add"]))
			bits.append("map tunable %d%%" % roundi(float(p.get("tune_range", 0.25)) * 100.0))
		"panniers", "top_box":
			bits = [p["type"], "%d litres" % int(p["litres"])]
		"tail":
			bits = [p["type"], str(TAIL_LIGHT_NAMES.get(str(p.get("light", "")), "rear light"))]
		"fairing":
			bits = [p["type"], "%d%% less drag" % roundi(-float(p["cda"]) / 0.55 * 100.0),
				"%d mm screen" % roundi(float(p.get("screen", 0.0)) * 1000.0)]
		"front_mudguard":
			bits = [p["type"], "keeps off %d%% of the spray" % roundi(float(p.get("cover", 0.7)) * 100.0),
				"mounts high under the yoke" if mudguard_high(id) else "mounts low on the fork legs"]
		"indicators", "side_panels", "guards", "number_boards", "swingarm":
			bits = [p["type"]]
		"steering_damper":
			bits = [p["type"], "damping %.0f N·m·s" % float(p.get("damping", 0.0))]
			if float(p.get("friction", 0.0)) > 0.0:
				bits.append("%.1f N·m friction" % float(p["friction"]))
			if int(p.get("adjust", 0)) > 0:
				bits.append("adjustable on the dyno desk")
		"rearsets":
			bits = [p["type"], peg_text(id)]
		"mirrors":
			bits = [p["type"]]
			if not p.get("mounts_on", []).is_empty():
				bits.append("needs a %s fitted" % ", ".join(p["mounts_on"].map(func(s): return slot_name(str(s)).to_lower())))
		"petrol":
			bits = [p["container"], "%.0f L" % p["litres"]] if p.get("empty", false) else [p["container"], "%.0f L" % p["litres"],
				"power %+d%%" % roundi((p["power"] - 1.0) * 100.0), "economy %+d%%" % roundi((p["economy"] - 1.0) * 100.0)]
		"oil":
			bits = [p["container"], "%.0f L" % p["litres"]] if p.get("empty", false) else [p["container"], "%.0f L" % p["litres"],
				"protection %d%%" % roundi(p["protection"] * 100.0)]
		"brake_fluid":
			bits = [p["container"], "%.1f L" % p["litres"]] if p.get("empty", false) else [p["container"], "%.1f L" % p["litres"],
				"bite %+d%%" % roundi((p["brake"] - 1.0) * 100.0)]
	if p.has("mass") or p.has("mass_per_cyl"):
		bits.append(Units.mass(float(p.get("mass", p.get("mass_per_cyl", 0.0))), 1))
	if is_lightweight(id):
		bits.append("Lightweight: saves %s" % Units.mass(weight_saving(id), 1))
	if not styles_of(id).is_empty():
		bits.append("Suits: " + styles_text(id))
	return "  ·  ".join(bits.map(func(b): return str(b)))


## "17\"" or "16.5\"".
static func inch_text(d: float) -> String:
	return ("%d\"" % roundi(d)) if is_equal_approx(d, roundf(d)) else ("%.1f\"" % d)


## How a tyre handles, in words: its construction, profile and how it lets go (see TyreModel).
static func tyre_handling_text(p: Dictionary) -> String:
	var t := TyreModel.params_of(p)
	var profile := float(t["profile"])
	var shape := "sharp sport profile" if profile < 0.95 else ("flat touring profile" if profile > 1.05 else "round profile")
	var slide := float(t["slide"])
	var lets_go := "lets go suddenly" if slide < 0.76 else ("slides progressively" if slide > 0.83 else "breaks away cleanly")
	return "%s, %s, %s" % ["radial" if t["construction"] == "radial" else "bias ply", shape, lets_go]


## The tyre widths (mm) a wheel's rim takes, smallest to widest.
func tyre_range(wheel_id: String) -> Vector2i:
	var p := get_part(wheel_id)
	var r: Array = p.get("tyres", [])
	if r.size() == 2:
		return Vector2i(int(r[0]), int(r[1]))
	# Older catalogues: worked out from the rim width.
	var rim := float(p.get("rim_width", 3.5))
	return Vector2i(roundi(rim * 24.0), roundi(rim * 62.0))


## The rim diameters (inches) a tyre is made for. Empty means any.
func tyre_rims(tyre_id: String) -> Array:
	return get_part(tyre_id).get("rims", [])


## Whether a tyre goes on a wheel: 0 if it does, 1 too wide for the rim, -1 too narrow,
## 2 made for a different rim diameter.
func tyre_fit(tyre_id: String, wheel_id: String) -> int:
	var t := get_part(tyre_id)
	var w := get_part(wheel_id)
	if t.is_empty() or w.is_empty():
		return 0
	var r := tyre_range(wheel_id)
	var mm := float(t.get("width", 120.0))
	if mm > r.y:
		return 1
	if mm < r.x:
		return -1
	var rims := tyre_rims(tyre_id)
	var dia := float(w.get("diameter", 17.0))
	if not rims.is_empty() and not rims.any(func(d): return is_equal_approx(float(d), dia)):
		return 2
	return 0


## Why a tyre won't go on a wheel, in words, or "" when it fits.
func tyre_fit_reason(tyre_id: String, wheel_id: String) -> String:
	var t := get_part(tyre_id)
	var w := get_part(wheel_id)
	match tyre_fit(tyre_id, wheel_id):
		2:
			return "That tyre is made for %s rims, not this %s wheel." % [" or ".join(tyre_rims(tyre_id).map(func(d): return inch_text(float(d)))),
				inch_text(float(w.get("diameter", 17.0)))]
		1, -1:
			var r := tyre_range(wheel_id)
			return "A %d mm tyre is too %s for this %.2f\" rim: it takes %d-%d mm." % [int(t.get("width", 0)),
				"wide" if tyre_fit(tyre_id, wheel_id) == 1 else "narrow", float(w.get("rim_width", 0.0)), r.x, r.y]
	return ""


## "17\" rims 4.25-6.0\" wide": the wheels in the catalogue a tyre goes on.
func tyre_rims_text(tyre_id: String) -> String:
	var dias := []
	var lo := INF
	var hi := 0.0
	for w in by_kind.get("wheel", []):
		if tyre_fit(tyre_id, w) == 0:
			var d := float(get_part(w).get("diameter", 17.0))
			if not dias.has(d):
				dias.append(d)
			lo = minf(lo, float(get_part(w).get("rim_width", 0.0)))
			hi = maxf(hi, float(get_part(w).get("rim_width", 0.0)))
	if dias.is_empty():
		return "no wheel in the catalogue"
	dias.sort()
	var sizes := " or ".join(dias.map(func(d): return inch_text(float(d))))
	if is_equal_approx(lo, hi):
		return "%s rims %.2f\" wide" % [sizes, lo]
	return "%s rims %.2f-%.2f\" wide" % [sizes, lo, hi]


## The catalogue tyres that go on a wheel.
func tyres_for(wheel_id: String) -> Array:
	return by_kind.get("tyre", []).filter(func(t): return tyre_fit(t, wheel_id) == 0)


## The catalogue wheels a tyre goes on.
func wheels_for(tyre_id: String) -> Array:
	return by_kind.get("wheel", []).filter(func(w): return tyre_fit(tyre_id, w) == 0)


## Returns a complete build, filling missing or unknown slots with defaults. A build from
## before tail units existed gets one that suits its saddle (see fitting_tail).
func sanitize_build(build: Dictionary) -> Dictionary:
	var clean := {}
	var no_tail := false
	var no_guard := false
	for slot in SLOTS:
		var id: String = str(build.get(slot, ""))
		if id == "none" and is_optional(slot):
			clean[slot] = id
			continue
		if not parts.has(id) or parts[id]["kind"] != SLOT_KIND[slot]:
			id = DEFAULT_BUILD[slot]
			no_tail = no_tail or slot == "tail"
			no_guard = no_guard or slot == "front_mudguard"
		clean[slot] = id
	if no_tail:
		clean["tail"] = fitting_tail(clean)
	if no_guard:
		clean["front_mudguard"] = fitting_front_mudguard(clean)
	return clean


## What each tail unit's rear light is, for the spec line.
const TAIL_LIGHT_NAMES := {"lucas": "big Lucas-style rear lamp", "round": "small round rear lamp",
	"strip": "LED strip rear light", "bullet": "bullet rear lamp", "led": "tiny LED rear light"}
## Which tail unit suits a saddle style, for bikes that never had one chosen.
const SADDLE_TAIL := {"cafe": "cafe_tail", "sport": "sport_tail_tidy", "enduro": "enduro_fender",
	"touring": "classic_mudguard", "bench": "classic_mudguard"}


## The tail unit that looks right on a build: a hump on a café seat, a high fender on an enduro,
## a tail tidy on a sports bike, a long mudguard on the rest (and a scrambler loop on knobblies).
func fitting_tail(build: Dictionary) -> String:
	var saddle := str(get_part(str(build.get("saddle", ""))).get("style", "bench"))
	var tail := str(SADDLE_TAIL.get(saddle, DEFAULT_BUILD["tail"]))
	if tail == "classic_mudguard" and str(get_part(str(build.get("rear_tyre", ""))).get("style", "")) == "offroad":
		tail = "scrambler_loop"
	return tail if parts.has(tail) else str(DEFAULT_BUILD["tail"])


## Which front mudguard goes with each style of tail unit, for bikes that never had one chosen.
const TAIL_FRONT_GUARD := {"enduro": "mx_high_fender", "loop": "enduro_front_fender", "cafe": "alloy_cafe_blade",
	"bobber": "bobbed_steel", "tidy": "road_hugger", "classic": "chrome_classic"}


## The front mudguard that looks right on a build: a high fender on knobblies, a cafe blade on a
## cafe racer, a bobbed blade on a bobber, a hugger on a sports bike, a chrome classic on the rest.
func fitting_front_mudguard(build: Dictionary) -> String:
	var tail := str(get_part(str(build.get("tail", ""))).get("style", "classic"))
	var guard := str(TAIL_FRONT_GUARD.get(tail, DEFAULT_BUILD["front_mudguard"]))
	if str(get_part(str(build.get("front_tyre", ""))).get("style", "")) == "offroad" and not tail in ["enduro", "loop"]:
		guard = "enduro_front_fender"
	return guard if parts.has(guard) else str(DEFAULT_BUILD["front_mudguard"])


## Whether a front mudguard sits up under the bottom yoke (off-road), rather than down on the
## fork legs following the tyre.
func mudguard_high(id: String) -> bool:
	return str(get_part(id).get("style", "")) in ["high", "enduro"]


## Everything a part in a slot needs fitted first: the slot's own mounts, plus any the part
## itself names ("mounts_on": fairing-mount mirrors need a fairing).
func part_mounts(slot: String, part_id: String) -> Array:
	var out: Array = MOUNTS.get(slot, []).duplicate()
	for m in get_part(part_id).get("mounts_on", []):
		if not out.has(str(m)):
			out.append(str(m))
	return out


## Where a set of footpegs puts your feet, in words.
func peg_text(id: String) -> String:
	var peg: Array = get_part(id).get("peg", [])
	if peg.size() != 2:
		return "pegs where the frame puts them"
	if float(peg[1]) < -0.2:
		return "feet forward"
	return "feet up and back" if float(peg[0]) > 0.06 else "feet a little further back"


# ---------------------------------------------------------------------------- styles

## The styles of bike the catalogue's parts are tagged with ("styles" in data/parts.json), in
## the order they're listed. Contracts call a sports bike "sport".
const STYLES: Array[String] = ["classic", "cafe", "bobber", "chopper", "cruiser", "scrambler", "adventure", "roader",
	"tourer", "sport", "race", "naked", "supermoto", "mx"]
const STYLE_NAMES := {"classic": "Classic", "cafe": "Cafe racer", "bobber": "Bobber", "chopper": "Chopper",
	"cruiser": "Cruiser", "scrambler": "Scrambler", "adventure": "Adventure bike", "roader": "Tall roader",
	"tourer": "Tourer", "sport": "Sports bike", "race": "Race bike", "naked": "Naked bike", "supermoto": "Supermoto", "mx": "MX bike"}
## How much each slot's part says about a bike's style: the frame most, then the big shapes
## you see first (tank, seat, bars, tail, fairing), then the rest.
const STYLE_WEIGHT := {"frame": 3.0, "tank": 2.0, "saddle": 2.0, "handlebars": 2.0, "tail": 2.0, "fairing": 2.0,
	"fork": 1.5, "exhaust": 1.5, "front_mudguard": 1.5, "number_boards": 1.5, "front_wheel": 1.0, "rear_wheel": 1.0,
	"headlight": 1.0, "panniers": 1.0, "side_panels": 1.0, "rearsets": 1.0, "guards": 1.0, "shock": 0.5,
	"front_tyre": 0.5, "rear_tyre": 0.5, "mirrors": 0.5, "top_box": 0.5, "fog_lights": 0.5, "dashboard": 0.5,
	"indicators": 0.5, "swingarm": 1.0}
## With nothing fitted there, a slot still says something: no fairing is the naked look.
const EMPTY_STYLES := {"fairing": ["classic", "cafe", "bobber", "chopper", "cruiser", "scrambler", "naked", "supermoto", "mx"]}
## How much of a bike has to agree on a style for it to be a proper one ("a proper bobber").
const PROPER_STYLE := 0.7


func styles_of(id: String) -> Array:
	return get_part(id).get("styles", [])


func style_name(style: String) -> String:
	return str(STYLE_NAMES.get(style, style.capitalize()))


## A style's name in the middle of a sentence: "cafe racer", but "MX bike".
func style_noun(style: String) -> String:
	var nm := style_name(style)
	return nm if nm.left(2) == nm.left(2).to_upper() else nm.to_lower()


## "a cafe racer", "an adventure bike", "an MX bike".
func style_phrase(style: String) -> String:
	var nm := style_noun(style)
	return ("an " if nm.left(1).to_lower() in ["a", "e", "i", "o", "u"] or nm.begins_with("MX") else "a ") + nm


## "cafe racer, classic, naked bike" for the info panel.
func styles_text(id: String) -> String:
	return ", ".join(styles_of(id).map(func(s): return style_noun(str(s))))


## What style a set of parts adds up to: each slot's part votes for the styles it's tagged
## with, weighted by STYLE_WEIGHT. Returns {style (the best, or "" with nothing to go on),
## coherence 0..1 (how much of the bike agrees), scores (style -> weight for it), total,
## proper (coherence at least PROPER_STYLE, on a frame that suits it), odd (slots whose part
## doesn't suit the style)}.
func detect_style(parts: Dictionary) -> Dictionary:
	var scores := {}
	for st in STYLES:
		scores[st] = 0.0
	var total := 0.0
	var votes := {}
	for slot in STYLE_WEIGHT:
		var id := str(parts.get(slot, "none"))
		var tags: Array = EMPTY_STYLES.get(slot, []) if id == "none" or id == "" else styles_of(id)
		if tags.is_empty():
			continue
		var w := float(STYLE_WEIGHT[slot])
		total += w
		votes[slot] = tags
		for t in tags:
			if scores.has(t):
				scores[t] += w
	var best := ""
	for st in STYLES:
		if float(scores[st]) > 0.0 and (best == "" or float(scores[st]) > float(scores[best]) + 0.001):
			best = st
	var coherence := float(scores[best]) / total if best != "" and total > 0.0 else 0.0
	var odd := []
	for slot in votes:
		if not (votes[slot] as Array).has(best) and str(parts.get(slot, "none")) != "none":
			odd.append(slot)
	# A proper one needs a frame built for it too: no cafe racer was ever built on a chopper frame.
	var frame := str(parts.get("frame", "none"))
	var frame_ok := frame == "none" or frame == "" or styles_of(frame).has(best)
	return {"style": best, "coherence": coherence, "scores": scores, "total": total,
		"proper": coherence >= PROPER_STYLE - 0.0001 and frame_ok, "odd": odd}


## How well a set of parts matches one style, 0..1 (the share of the bike tagged with it).
func style_fit(style: String, parts: Dictionary) -> float:
	var d := detect_style(parts)
	return float(d["scores"].get(style, 0.0)) / float(d["total"]) if float(d["total"]) > 0.0 else 0.0


## "A proper bobber", "Mostly a scrambler" or "A mix of styles", for the info panels.
func style_text(parts: Dictionary) -> String:
	var d := detect_style(parts)
	if str(d["style"]) == "":
		return "No style yet"
	var pc := roundi(float(d["coherence"]) * 100.0)
	if d["proper"]:
		return "A proper %s (%d%%)" % [style_noun(str(d["style"])), pc]
	if float(d["coherence"]) >= 0.5:
		return "Mostly %s (%d%%)" % [style_phrase(str(d["style"])), pc]
	return "A mix of styles, nearest %s (%d%%)" % [style_phrase(str(d["style"])), pc]


## The style bits (FILLER_SLOTS) that suit a build, for bikes that turn up already put together:
## where the bike leans one way, a part tagged with that style in each slot, else nothing. No
## random draws, so it leaves the caller's dice alone; `seed_value` picks between parts that fit.
func dress_fillers(parts: Dictionary, seed_value := 0) -> Dictionary:
	var out := parts.duplicate()
	for slot in FILLER_SLOTS:
		out[slot] = "none"
	var d := detect_style(out)
	var st := str(d["style"])
	if st == "" or float(d["coherence"]) < 0.45:
		return out
	var i := 0
	for slot in FILLER_SLOTS:
		var fits: Array = by_kind.get(SLOT_KIND[slot], []).filter(func(id): return styles_of(str(id)).has(st))
		if not fits.is_empty():
			out[slot] = fits[absi(seed_value + i * 7) % fits.size()]
		i += 1
	return out
