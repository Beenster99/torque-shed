extends Node
## Part catalogue loaded from data/parts.json. Every bike is a choice of one part per slot.
## Parts mount onto each other, so some have to come off before others (see MOUNTS).

const SLOTS: Array[String] = ["frame", "fork", "shock", "wheels", "brakes", "engine", "intake", "exhaust",
	"gearbox", "final_drive"]
const SLOT_NAMES := {
	"frame": "Frame",
	"fork": "Front fork",
	"shock": "Rear shock",
	"wheels": "Wheels and tyres",
	"brakes": "Brakes",
	"engine": "Engine",
	"intake": "Intake",
	"exhaust": "Exhaust",
	"gearbox": "Gearbox",
	"final_drive": "Final drive",
}
const DEFAULT_BUILD := {
	"frame": "steel_cradle",
	"fork": "telescopic_road",
	"shock": "twin_shock",
	"wheels": "road_17",
	"brakes": "single_disc",
	"engine": "twin_700",
	"intake": "stock_airbox",
	"exhaust": "stock_muffler",
	"gearbox": "five_wide",
	"final_drive": "short_14_50",
}
## What each slot bolts onto. A part can only go on once its mounts are fitted,
## and has to come off before any of them can.
const MOUNTS := {
	"frame": [],
	"fork": ["frame"],
	"shock": ["frame"],
	"wheels": ["fork", "shock"],
	"brakes": ["wheels"],
	"gearbox": ["frame"],
	"engine": ["gearbox"],
	"intake": ["engine"],
	"exhaust": ["engine"],
	"final_drive": ["gearbox", "wheels"],
}

var parts := {}    # part id -> Dictionary of stats (with "id" and "slot" added)
var by_slot := {}  # slot -> Array of part ids, in catalogue order


func _ready() -> void:
	load_catalogue("res://data/parts.json")


func load_catalogue(path: String) -> void:
	parts.clear()
	by_slot.clear()
	for slot in SLOTS:
		by_slot[slot] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open part catalogue %s" % path)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	for slot in data:
		for id in data[slot]:
			var part: Dictionary = data[slot][id]
			part["id"] = id
			part["slot"] = slot
			parts[id] = part
			by_slot[slot].append(id)


func get_part(id: String) -> Dictionary:
	return parts.get(id, {})


func part_name(id: String) -> String:
	return str(get_part(id).get("name", id))


func slot_of(id: String) -> String:
	return str(get_part(id).get("slot", ""))


## Slots that bolt onto this one, which must be removed before it can come off.
func dependents(slot: String) -> Array:
	var out := []
	for s in SLOTS:
		if MOUNTS[s].has(slot):
			out.append(s)
	return out


## Returns a complete build, filling missing or unknown slots with defaults.
func sanitize_build(build: Dictionary) -> Dictionary:
	var clean := {}
	for slot in SLOTS:
		var id: String = str(build.get(slot, ""))
		if not parts.has(id) or parts[id]["slot"] != slot:
			id = DEFAULT_BUILD[slot]
		clean[slot] = id
	return clean
