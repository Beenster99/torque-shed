extends Node
## Part catalogue loaded from data/parts.json. Parts come in kinds (fork, tyre, spark plugs...),
## and a bike has slots that each take one part of a kind. Front and rear slots share a kind,
## so a tyre fits either wheel. The engine is its own assembly: a block with slots of its own
## for the head, fuel system, filters, plugs, cooling and gearbox, built up on the engine stand.
## Parts mount onto each other, so some have to come off before others (see MOUNTS).

const KINDS: Array[String] = ["frame", "fork", "shock", "wheel", "tyre", "disc", "caliper", "pads", "master", "tank",
	"saddle", "handlebars", "dashboard", "engine", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling",
	"gearbox", "exhaust", "final_drive"]
const KIND_NAMES := {
	"frame": "Frame", "fork": "Front fork", "shock": "Rear suspension", "wheel": "Wheel", "tyre": "Tyre",
	"disc": "Brake disc", "caliper": "Brake caliper", "pads": "Brake pads", "master": "Master cylinder",
	"tank": "Fuel tank", "saddle": "Saddle", "handlebars": "Handlebars", "dashboard": "Dashboard",
	"engine": "Engine block", "head": "Cylinder head", "fuel": "Fuel system", "air_filter": "Air filter",
	"oil_filter": "Oil filter", "spark_plugs": "Spark plugs", "cooling": "Cooling", "gearbox": "Gearbox",
	"exhaust": "Exhaust", "final_drive": "Final drive",
}
## Slots on the bike itself.
const BIKE_SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive"]
## Slots on an engine block. They travel with the block when it comes out of the frame.
const ENGINE_SLOTS: Array[String] = ["head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox"]
## Engine parts you can change with the engine still in the frame. The rest need the engine stand.
const SERVICE_SLOTS: Array[String] = ["air_filter", "oil_filter", "spark_plugs"]
const SLOTS: Array[String] = ["frame", "fork", "shock", "front_wheel", "rear_wheel", "front_tyre", "rear_tyre",
	"front_disc", "rear_disc", "front_caliper", "rear_caliper", "front_pads", "rear_pads", "front_master",
	"rear_master", "tank", "saddle", "handlebars", "dashboard", "engine", "exhaust", "final_drive",
	"head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox"]
const SLOT_KIND := {
	"frame": "frame", "fork": "fork", "shock": "shock", "front_wheel": "wheel", "rear_wheel": "wheel",
	"front_tyre": "tyre", "rear_tyre": "tyre", "front_disc": "disc", "rear_disc": "disc",
	"front_caliper": "caliper", "rear_caliper": "caliper", "front_pads": "pads", "rear_pads": "pads",
	"front_master": "master", "rear_master": "master", "tank": "tank", "saddle": "saddle",
	"handlebars": "handlebars", "dashboard": "dashboard", "engine": "engine", "exhaust": "exhaust",
	"final_drive": "final_drive", "head": "head", "fuel": "fuel", "air_filter": "air_filter",
	"oil_filter": "oil_filter", "spark_plugs": "spark_plugs", "cooling": "cooling", "gearbox": "gearbox",
}
const DEFAULT_BUILD := {
	"frame": "steel_cradle", "fork": "telescopic_road", "shock": "twin_shock", "front_wheel": "cast_17",
	"rear_wheel": "cast_17", "front_tyre": "sport_road", "rear_tyre": "sport_road", "front_disc": "floating_310",
	"rear_disc": "solid_240", "front_caliper": "four_piston_axial", "rear_caliper": "single_piston",
	"front_pads": "semi_metallic", "rear_pads": "semi_metallic", "front_master": "axial_14", "rear_master": "axial_14",
	"tank": "cafe_15", "saddle": "flat_bench", "handlebars": "flat_bar", "dashboard": "twin_clocks",
	"engine": "twin_700", "exhaust": "stock_muffler", "final_drive": "short_14_50", "head": "four_valve",
	"fuel": "twin_carbs", "air_filter": "paper_airbox", "oil_filter": "paper_oil", "spark_plugs": "iridium_plugs",
	"cooling": "oil_cooler", "gearbox": "five_wide",
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
	"engine": ["frame"], "exhaust": ["engine"], "final_drive": ["engine", "rear_wheel"],
	"head": ["engine"], "oil_filter": ["engine"], "cooling": ["engine"], "gearbox": ["engine"],
	"spark_plugs": ["head"], "fuel": ["head"], "air_filter": ["fuel"],
}

var parts := {}    # part id -> Dictionary of stats (with "id" and "kind" added)
var by_kind := {}  # kind -> Array of part ids, in catalogue order


func _ready() -> void:
	load_catalogue("res://data/parts.json")


func load_catalogue(path: String) -> void:
	parts.clear()
	by_kind.clear()
	for k in KINDS:
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
			bits = [p["type"], "%d\"" % int(p["diameter"])]
		"tyre":
			bits = [p["type"], p["compound"] + " compound", "%d mm" % int(p["width"]),
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
		"exhaust":
			bits = ["power %+d%%" % roundi((p["torque_mult"] - 1.0) * 100.0), "loudness %d%%" % roundi(p["loudness"] * 100.0)]
		"final_drive":
			bits = [p["type"]]
	bits.append("%.1f kg" % float(p.get("mass", p.get("mass_per_cyl", 0.0))))
	return "  ·  ".join(bits.map(func(b): return str(b)))


## Returns a complete build, filling missing or unknown slots with defaults.
func sanitize_build(build: Dictionary) -> Dictionary:
	var clean := {}
	for slot in SLOTS:
		var id: String = str(build.get(slot, ""))
		if not parts.has(id) or parts[id]["kind"] != SLOT_KIND[slot]:
			id = DEFAULT_BUILD[slot]
		clean[slot] = id
	return clean
