extends Node
## Part catalogue loaded from data/parts.json. Every bike is a choice of one part per slot.

const SLOTS: Array[String] = ["frame", "fork", "shock", "wheels", "engine", "gearbox", "sprocket"]
const SLOT_NAMES := {
	"frame": "Frame",
	"fork": "Front fork",
	"shock": "Rear shock",
	"wheels": "Wheels and tyres",
	"engine": "Engine",
	"gearbox": "Gearbox",
	"sprocket": "Final drive",
}
const DEFAULT_BUILD := {
	"frame": "steel_cradle",
	"fork": "telescopic_road",
	"shock": "twin_shock",
	"wheels": "road_17",
	"engine": "twin_700",
	"gearbox": "five_wide",
	"sprocket": "short_14_50",
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


## Returns a complete build, filling missing or unknown slots with defaults.
func sanitize_build(build: Dictionary) -> Dictionary:
	var clean := {}
	for slot in SLOTS:
		var id: String = str(build.get(slot, ""))
		if not parts.has(id) or parts[id]["slot"] != slot:
			id = DEFAULT_BUILD[slot]
		clean[slot] = id
	return clean
