extends Node
## Part catalogue loaded from data/parts.json. Parts come in kinds (fork, tyre, spark plugs...),
## and a bike has slots that each take one part of a kind. Front and rear slots share a kind,
## so a tyre fits either wheel. The engine is its own assembly: a block with slots of its own
## for the head, fuel system, filters, plugs, cooling and gearbox, built up on the engine stand.
## Parts mount onto each other, so some have to come off before others (see MOUNTS).

const KINDS: Array[String] = ["frame", "fork", "shock", "wheel", "tyre", "disc", "caliper", "pads", "master", "tank",
	"saddle", "handlebars", "dashboard", "engine", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling",
	"gearbox", "exhaust", "final_drive", "chain", "side_stand", "centre_stand", "headlight", "horn", "ecu",
	"panniers", "top_box", "fog_lights"]
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
	"fog_lights": "Fog lights", "petrol": "Petrol", "oil": "Engine oil", "brake_fluid": "Brake fluid", "chain_lube": "Chain lube",
}
## Slots on the bike itself.
const BIKE_SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive", "chain",
	"side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box", "fog_lights"]
## Bike slots a bike can be ridden without. "none" in a build means nothing is fitted there.
const OPTIONAL_SLOTS: Array[String] = ["side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box",
	"fog_lights"]
## Parts low down on a bike that you have to crouch to reach while it's in the frame.
const LOW_SLOTS: Array[String] = ["side_stand", "centre_stand", "oil_filter", "final_drive", "chain"]
## Slots on an engine block. They travel with the block when it comes out of the frame.
const ENGINE_SLOTS: Array[String] = ["head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox"]
## Engine parts you can change with the engine still in the frame. The rest need the engine stand.
const SERVICE_SLOTS: Array[String] = ["air_filter", "oil_filter", "spark_plugs"]
const SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive", "chain",
	"side_stand", "centre_stand", "headlight", "horn", "ecu", "panniers", "top_box", "fog_lights", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox"]
const SLOT_KIND := {
	"frame": "frame", "fork": "fork", "shock": "shock", "front_wheel": "wheel", "rear_wheel": "wheel",
	"front_tyre": "tyre", "rear_tyre": "tyre", "front_disc": "disc", "rear_disc": "disc",
	"front_caliper": "caliper", "rear_caliper": "caliper", "front_pads": "pads", "rear_pads": "pads",
	"front_master": "master", "rear_master": "master", "tank": "tank", "saddle": "saddle",
	"handlebars": "handlebars", "dashboard": "dashboard", "engine": "engine", "exhaust": "exhaust",
	"final_drive": "final_drive", "chain": "chain", "head": "head", "fuel": "fuel", "air_filter": "air_filter",
	"oil_filter": "oil_filter", "spark_plugs": "spark_plugs", "cooling": "cooling", "gearbox": "gearbox",
	"side_stand": "side_stand", "centre_stand": "centre_stand", "headlight": "headlight", "horn": "horn", "ecu": "ecu",
	"panniers": "panniers", "top_box": "top_box", "fog_lights": "fog_lights",
}
const DEFAULT_BUILD := {
	"frame": "steel_cradle", "fork": "telescopic_road", "shock": "twin_shock", "front_wheel": "cast_17",
	"rear_wheel": "cast_17", "front_tyre": "sport_road", "rear_tyre": "sport_road", "front_disc": "floating_310",
	"rear_disc": "solid_240", "front_caliper": "four_piston_axial", "rear_caliper": "single_piston",
	"front_pads": "semi_metallic", "rear_pads": "semi_metallic", "front_master": "axial_14", "rear_master": "axial_14",
	"tank": "cafe_15", "saddle": "flat_bench", "handlebars": "flat_bar", "dashboard": "twin_clocks",
	"engine": "twin_700", "exhaust": "stock_muffler", "final_drive": "short_14_50", "chain": "oring_520", "head": "four_valve",
	"fuel": "twin_carbs", "air_filter": "paper_airbox", "oil_filter": "paper_oil", "spark_plugs": "iridium_plugs",
	"cooling": "oil_cooler", "gearbox": "five_wide", "side_stand": "stamped_side", "centre_stand": "none",
	"headlight": "round_7", "horn": "disc_horn", "ecu": "none", "panniers": "none", "top_box": "none", "fog_lights": "none",
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
	"petrol": "metal", "oil": "plastic", "brake_fluid": "plastic", "chain_lube": "metal",
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
		"wheel":
			var dia := float(p["diameter"])
			bits = [p["type"], ("%d\"" % roundi(dia)) if is_equal_approx(dia, roundf(dia)) else ("%.1f\"" % dia)]
			if p.has("rim_width"):
				bits.append("%.2f\" rim (tyres %d-%d mm)" % [float(p["rim_width"]), roundi(float(p["rim_width"]) * 24.0 / 10.0) * 10, roundi(float(p["rim_width"]) * 62.0 / 10.0) * 10])
			if p.has("spokes"):
				bits.append("%d spokes" % int(p["spokes"]))
		"tyre":
			bits = [p["type"], p["compound"] + " compound", "%d mm wide (%d mm as a front)" % [int(p["width"]), roundi(float(p["width"]) * 0.7)],
				"grip %.2f tarmac / %.2f dirt" % [p["grip"]["tarmac"], p["grip"]["dirt"]]]
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
	return "  ·  ".join(bits.map(func(b): return str(b)))


## Returns a complete build, filling missing or unknown slots with defaults.
func sanitize_build(build: Dictionary) -> Dictionary:
	var clean := {}
	for slot in SLOTS:
		var id: String = str(build.get(slot, ""))
		if id == "none" and is_optional(slot):
			clean[slot] = id
			continue
		if not parts.has(id) or parts[id]["kind"] != SLOT_KIND[slot]:
			id = DEFAULT_BUILD[slot]
		clean[slot] = id
	return clean
