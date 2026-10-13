extends Node
## The shared state of the shed: every bike, every loose part and what each player is doing.
## The host owns it. Players ask for changes with request(); the host checks each one,
## applies it and sends the new state to everyone, so two people working on the same bike
## always agree on which bolts are done up.

signal changed
signal feedback(text: String, ok: bool)
## Someone pointed at something for the crew: {at, what, item, furniture, name}.
signal pinged(peer: int, ping: Dictionary)
## The whiteboard's marks changed (see BoardData).
signal board_changed

## The fixed workbench along the wall. Equipment adds its own places: engine stands
## ("stand_<id>") and the rest "<prefix>_<id>_<n>" (see Equipment.SPOT_PREFIX).
const SPOTS: Array[String] = ["bench_0", "bench_1", "bench_2", "bench_3"]
const DELIVERY_ROWS := 3
const DELIVERY_COLS := 4
const PAINTS := [Color(0.78, 0.09, 0.08), Color(0.1, 0.35, 0.8), Color(0.95, 0.6, 0.05), Color(0.1, 0.6, 0.3),
	Color(0.55, 0.15, 0.7), Color(0.9, 0.9, 0.9), Color(0.06, 0.06, 0.06), Color(0.0, 0.6, 0.7),
	Color(0.72, 0.73, 0.75), Color(0.8, 0.62, 0.2), Color(0.95, 0.85, 0.1), Color(0.95, 0.4, 0.6),
	Color(0.42, 0.06, 0.1), Color(0.45, 0.28, 0.14), Color(0.9, 0.85, 0.7), Color(0.35, 0.4, 0.18)]
const PAINT_NAMES := ["red", "blue", "orange", "green", "purple", "white", "black", "teal", "silver", "gold",
	"yellow", "pink", "burgundy", "brown", "cream", "olive"]
## How the paint looks: "" is the part's factory finish, the rest come out of the spray can.
const FINISHES: Array[String] = ["gloss", "matte", "metallic", "chrome", "patina"]
const FINISH_NAMES := {"gloss": "Gloss", "matte": "Matte", "metallic": "Metallic flake", "chrome": "Chrome",
	"patina": "Old patina"}
const BIKE_NAMES := ["Barn Find", "Rusty Ranger", "Basket Case", "Old Faithful", "The Widowmaker", "Rattler",
	"Hedge Hopper", "Midnight Special", "Scrapyard Dog", "Grandad's Pride", "Mud Puppy", "Iron Maiden"]
## Chains: slack in mm. Adjusted right it sits between these; lube 0 (dry) .. 1 (just done).
const CHAIN_SLACK_GOOD := Vector2(20.0, 40.0)
const CHAIN_SLACK_SET := 30.0
const LUBE_USE := 0.03         # litres of chain lube a full coat takes
const JET_CLEAN := 0.07        # dirt the pressure washer blasts off each part per pass
## How much road dirt each part picks up per kilometre ridden off-road (tarmac is a fraction of it).
const ROAD_DIRT := 0.3
const DIRT_EXPOSURE := {"front_tyre": 1.0, "rear_tyre": 1.0, "front_wheel": 0.9, "rear_wheel": 0.9, "fork": 0.7,
	"shock": 0.8, "final_drive": 1.0, "exhaust": 0.8, "engine": 0.6, "front_disc": 0.8, "rear_disc": 0.8,
	"front_caliper": 0.8, "rear_caliper": 0.8, "front_pads": 0.6, "rear_pads": 0.6, "frame": 0.5, "side_stand": 0.9,
	"centre_stand": 0.9, "cooling": 0.6, "oil_filter": 0.6, "air_filter": 0.5, "gearbox": 0.5, "rear_master": 0.5,
	"tank": 0.25, "saddle": 0.25, "headlight": 0.5, "handlebars": 0.15, "dashboard": 0.1, "front_master": 0.15,
	"horn": 0.6, "ecu": 0.2, "panniers": 0.6, "top_box": 0.3, "fog_lights": 0.6}
## Litres a second poured from a container, or drained out of a bike.
const POUR_RATE := {"petrol": 2.0, "oil": 0.8, "brake_fluid": 0.15}
const SYNC_INTERVAL := 0.1
## Tuning (the dyno room): where each setting is kept. The engine's calibration belongs to the
## bike ("bike": its tune{}); the rest live on the part they adjust, in its tune{}, so they go
## with it when it's swapped. Chain tension is the chain's own slack.
const TUNE_HOME := {"map": ["bike", "map"], "ignition": ["bike", "ignition"], "limiter": ["bike", "limiter"],
	"f_preload": ["fork", "preload"], "f_bump": ["fork", "bump"], "f_rebound": ["fork", "rebound"],
	"r_preload": ["shock", "preload"], "r_bump": ["shock", "bump"], "r_rebound": ["shock", "rebound"],
	"psi_f": ["front_tyre", "pressure"], "psi_r": ["rear_tyre", "pressure"],
	"sprocket_f": ["final_drive", "front"], "sprocket_r": ["final_drive", "rear"], "spread": ["gearbox", "spread"],
	"chain": ["chain", "slack"]}
const LIGHTEN_WEAR := 0.08     # condition a part gives up to being drilled and trimmed
const TYRE_WEAR := 0.0002      # tyre wear per km at the right pressure
const MAX_PAINT_RUST := 0.2

## bike id -> {id, name, paint, slots{bike slot: item id or 0}, bolted{slot: bool}, rider, bay, xf, original, delivered,
## stand ("" upright on its wheels or the bay's paddock stand, "side", "centre" or "down" when it has fallen over),
## pusher (peer wheeling it about, or 0), tune{map, ignition, limiter}, dyno{n, runs: the last two dyno runs}}
var bikes := {}
## item id -> {id, part, kind, rust, dirt, wear, color, finish, boxed, at, ref}, where
## at is "bike", "engine", "held", "spot" or "floor" (ref is then the Transform3D it was put down at).
## Engine blocks also carry slots{} and bolted{} for the parts fitted to them. Tanks, engines, master
## cylinders and fluid containers carry fluid{type, litres, age}: petrol, oil or brake fluid.
var items := {}
## furniture id -> {id, kind (see Equipment.KINDS), model (an Equipment model id), xf, label,
## mover (peer pushing it, or 0)}
var furniture := {}
var crew := {}      # peer id -> {name, tool, activity, riding, fitted, removed, cleaned, repaired, painted, km, top_kmh}
var active := false
## The shed radio everyone hears: on or off, and which of `stations` it's tuned to.
var radio := {"on": false, "station": 0}
var door_open := true     # the roller door
var lights_on := true     # the shed's strip lights
var stations: Array = []    # [{name, genre, url}] from data/radio.json
var board := BoardData.empty()   # what's drawn and written on the shed whiteboard

var _next_id := 1
var _dirty := false
var _sync_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _dyno_busy_until := 0      # msec: the host won't start another dyno run until this one is done


func _ready() -> void:
	var file := FileAccess.open("res://data/radio.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			stations = parsed
	Net.player_joined.connect(_on_player_joined)
	Net.player_updated.connect(func(id, info): _on_player_joined(id, info))
	Net.player_left.connect(_on_player_left)


func is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func me() -> int:
	return Net.local_id()


# ---------------------------------------------------------------------------- session

## Opens the shed with a few project bikes waiting. Only the host (or a solo player) does this;
## joiners receive the host's shed instead.
func start_new(player_name: String, seed_value := 0) -> void:
	bikes.clear()
	furniture.clear()
	radio = {"on": false, "station": 0}
	door_open = true
	lights_on = true
	items.clear()
	crew.clear()
	board = BoardData.empty()
	board_changed.emit()
	_next_id = 1
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	active = true
	_add_crew(me(), player_name)
	_new_bike({"frame": "steel_backbone", "fork": "enduro_usd", "shock": "enduro_mono", "front_wheel": "spoked_21",
		"rear_wheel": "spoked_18", "front_tyre": "knobbly_mx", "rear_tyre": "knobbly_mx", "front_disc": "wave_270",
		"rear_disc": "wave_270", "front_caliper": "twin_piston", "rear_caliper": "single_piston", "front_pads": "sintered",
		"rear_pads": "sintered", "front_master": "axial_12", "rear_master": "axial_14", "tank": "enduro_12",
		"saddle": "enduro_seat", "handlebars": "mx_tall", "dashboard": "lcd_basic", "engine": "single_450",
		"exhaust": "stock_muffler", "final_drive": "mx_13_52", "head": "four_valve", "fuel": "flat_slide_carbs",
		"air_filter": "foam_filter", "oil_filter": "paper_oil", "spark_plugs": "copper_plugs", "cooling": "single_radiator",
		"gearbox": "six_wide_enduro"}, 0, "Rusty Ranger", 0.75, PAINTS[2])
	var cafe := _new_bike({"frame": "steel_cradle", "fork": "classic_conventional", "shock": "twin_shock",
		"front_wheel": "wire_19_chrome", "rear_wheel": "spoked_18", "front_tyre": "vintage_ribbed", "rear_tyre": "vintage_ribbed",
		"front_disc": "drilled_280", "rear_disc": "solid_240", "front_caliper": "twin_piston", "rear_caliper": "single_piston",
		"front_pads": "organic", "rear_pads": "organic", "front_master": "axial_14", "rear_master": "axial_14",
		"tank": "cafe_15", "saddle": "cafe_hump", "handlebars": "clip_ons", "dashboard": "analog_speedo",
		"engine": "twin_700", "exhaust": "stock_muffler", "final_drive": "stock_15_45", "head": "two_valve_stock",
		"fuel": "twin_carbs", "air_filter": "paper_airbox", "oil_filter": "centrifugal_oil", "spark_plugs": "vintage_plugs",
		"cooling": "air_fins", "gearbox": "four_vintage"}, 1, "Barn Find", 0.6, PAINTS[0])
	# The barn find arrives half stripped: exhaust, sprockets, chain and front tyre are on the
	# bench, the engine is on the stand, and its spark plugs and air filter were lost in the barn.
	var bench := 0
	for slot in ["exhaust", "chain", "final_drive", "front_tyre"]:
		_detach(cafe, slot, "spot", "bench_%d" % bench)
		bench += 1
	var stand := _new_furniture("stand", Transform3D(Basis(), Workshop.CENTER + Vector3(Workshop.HALF.x - 0.9, 0.0, -0.4)))
	# The shed's own parts washer and repair bench, against the front wall. They can be moved,
	# and more bought from the parts computer.
	_new_furniture("washer", Transform3D(Basis(Vector3.UP, PI), Workshop.CENTER + Vector3(Workshop.HALF.x - 1.05, 0.0, Workshop.HALF.y - 0.6)))
	_new_furniture("repair", Transform3D(Basis(Vector3.UP, PI), Workshop.CENTER + Vector3(3.4, 0.0, Workshop.HALF.y - 0.6)))
	ensure_fixtures()
	var block := _detach(cafe, "engine", "spot", "stand_%d" % stand)
	for slot in ["spark_plugs", "air_filter"]:
		var gone: int = items[block]["slots"][slot]
		items[block]["slots"][slot] = 0
		items[block]["bolted"][slot] = false
		items.erase(gone)
	_new_bike({"frame": "alu_twin_spar", "fork": "usd_sport", "shock": "sport_mono", "front_wheel": "cast_17",
		"rear_wheel": "cast_17", "front_tyre": "sport_road", "rear_tyre": "sport_road", "front_disc": "floating_310",
		"rear_disc": "solid_240", "front_caliper": "four_piston_radial", "rear_caliper": "twin_piston",
		"front_pads": "sintered", "rear_pads": "semi_metallic", "front_master": "radial_19x20", "rear_master": "axial_14",
		"tank": "sport_17", "saddle": "sport_solo", "handlebars": "clip_ons", "dashboard": "tft_colour",
		"engine": "four_1000", "exhaust": "slip_on", "final_drive": "stock_15_45", "head": "four_valve",
		"fuel": "throttle_bodies", "air_filter": "paper_airbox", "oil_filter": "high_flow_oil", "spark_plugs": "iridium_plugs",
		"cooling": "single_radiator", "gearbox": "six_close"}, 2, "Old Faithful", 0.35, PAINTS[1])
	_set_up_yard()
	_mark_dirty()
	changed.emit()


## The practice area just past the drag strip starts with a jump line, a slalom and some things
## to jump. Everything can be pushed about with F, and more ordered from the parts computer.
func _set_up_yard() -> void:
	var north := Basis()                     # a ramp's deck rises towards its back (-Z)
	var south := Basis(Vector3.UP, PI)       # turned round: ridden heading south, away from the drag strip
	# A jump line along x = -2, ridden south off the drag strip: the big ramp onto a landing.
	_new_furniture("ramp", Transform3D(south, Vector3(-2.0, 0.0, 118.0)), "ramp_large")
	_new_furniture("ramp", Transform3D(north, Vector3(-2.0, 0.0, 132.0)), "ramp_landing")
	_new_furniture("marker", Transform3D(north, Vector3(0.5, 0.0, 137.0)), "flag_chequered")
	_new_furniture("ramp", Transform3D(south, Vector3(-9.0, 0.0, 114.0)), "ramp_small")
	_new_furniture("ramp", Transform3D(south, Vector3(-15.0, 0.0, 116.0)), "ramp_medium")
	_new_furniture("obstacle", Transform3D(south, Vector3(12.0, 0.0, 124.0)), "tabletop")
	# A slalom of cones and posts, with flags at the gate.
	_new_furniture("marker", Transform3D(north, Vector3(4.6, 0.0, 109.0)), "flag_red")
	_new_furniture("marker", Transform3D(north, Vector3(8.4, 0.0, 109.0)), "flag_blue")
	for i in 6:
		_new_furniture("marker", Transform3D(north, Vector3(5.8 + (i % 2) * 1.5, 0.0, 113.0 + i * 4.0)), "cone" if i % 3 != 2 else "post")
	# Things to jump, and a short wall and fence.
	_new_furniture("obstacle", Transform3D(north, Vector3(-15.0, 0.0, 126.0)), "barrels")
	_new_furniture("obstacle", Transform3D(north, Vector3(-9.0, 0.0, 124.0)), "log")
	_new_furniture("obstacle", Transform3D(north, Vector3(-9.0, 0.0, 130.0)), "hay_bales")
	_new_furniture("obstacle", Transform3D(north, Vector3(18.5, 0.0, 140.0)), "tyre_stack")
	_new_furniture("obstacle", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-15.0, 0.0, 136.0)), "car_wreck")
	_new_furniture("barrier", Transform3D(north, Vector3(15.0, 0.0, 136.0)), "wall_concrete")
	_new_furniture("barrier", Transform3D(north, Vector3(17.2, 0.0, 136.0)), "wall_concrete")
	_new_furniture("barrier", Transform3D(north, Vector3(6.0, 0.0, 142.0)), "fence_wood")
	_new_furniture("barrier", Transform3D(north, Vector3(10.0, 0.0, 142.0)), "fence_mesh")
	_new_furniture("barrier", Transform3D(north, Vector3(-8.0, 0.0, 142.0)), "wall_brick")


## Opens a saved shed (see SaveGame): the host's side of _sync. Nothing is held, ridden, pushed
## or wheeled any more (a bike someone was on is parked where it stood), the crew is just who is
## here now, and new ids carry on past every id in the save.
func load_state(state: Dictionary, player_name: String) -> void:
	var was_moving := []
	var saved_bikes: Dictionary = state.get("bikes", {})
	for id in saved_bikes:
		if int(saved_bikes[id].get("rider", 0)) != 0 or int(saved_bikes[id].get("pusher", 0)) != 0:
			saved_bikes[id]["rider"] = 0
			saved_bikes[id]["pusher"] = 0
			was_moving.append(id)
	_sync(state)
	for id in was_moving:
		_park(id)
	for id in items:
		if items[id]["at"] == "held":
			_move(id, "spot", _free_spot())
	for id in furniture:
		furniture[id]["mover"] = 0
	crew.clear()
	_add_crew(me(), player_name)
	for peer in Net.players:
		_add_crew(peer, str(Net.players[peer].get("name", "Rider")))
	# Anything keyed by its own id (bikes, items, furniture and whatever comes next) counts.
	var top := 0
	for key in state:
		if state[key] is Dictionary:
			for id in state[key]:
				if id is int and state[key][id] is Dictionary and state[key][id].get("id", 0) == id:
					top = maxi(top, id)
	_next_id = maxi(_next_id, top + 1)
	_rng.seed = int(Time.get_unix_time_from_system())
	ensure_fixtures()
	_mark_dirty()
	changed.emit()


func join_remote() -> void:
	board = BoardData.empty()
	board_changed.emit()
	bikes.clear()
	furniture.clear()
	radio = {"on": false, "station": 0}
	items.clear()
	crew.clear()
	active = true


func stop() -> void:
	board = BoardData.empty()
	board_changed.emit()
	furniture.clear()
	radio = {"on": false, "station": 0}
	active = false
	bikes.clear()
	items.clear()
	crew.clear()
	changed.emit()


# ---------------------------------------------------------------------------- queries

## The thing a slot belongs to: the bike itself, or for engine slots the engine block in it.
## Pass `engine_id` for an engine that isn't in a bike (on the stand). Empty when there's none.
func host_of(bike_id: int, slot: String, engine_id := 0) -> Dictionary:
	if engine_id != 0:
		return items.get(engine_id, {}) if is_engine(engine_id) else {}
	if not bikes.has(bike_id):
		return {}
	if PartsDB.is_engine_slot(slot):
		var block := int(bikes[bike_id]["slots"].get("engine", 0))
		return items.get(block, {})
	return bikes[bike_id]


func is_engine(item_id: int) -> bool:
	return items.has(item_id) and items[item_id]["kind"] == "engine"


func item_on(bike_id: int, slot: String) -> int:
	return int(host_of(bike_id, slot).get("slots", {}).get(slot, 0))


func is_bolted(bike_id: int, slot: String) -> bool:
	return bool(host_of(bike_id, slot).get("bolted", {}).get(slot, false))


func engine_item(engine_id: int, slot: String) -> int:
	return int(host_of(0, slot, engine_id).get("slots", {}).get(slot, 0))


func engine_bolted(engine_id: int, slot: String) -> bool:
	return bool(host_of(0, slot, engine_id).get("bolted", {}).get(slot, false))


## Item fitted at a target: {bike, slot} or {engine, slot}.
func item_at_target(t: Dictionary) -> int:
	var slot := str(t.get("slot", ""))
	if int(t.get("engine", 0)) != 0:
		return engine_item(int(t["engine"]), slot)
	return item_on(int(t.get("bike", 0)), slot)


func bolted_at_target(t: Dictionary) -> bool:
	var slot := str(t.get("slot", ""))
	if int(t.get("engine", 0)) != 0:
		return engine_bolted(int(t["engine"]), slot)
	return is_bolted(int(t.get("bike", 0)), slot)


func held_by(peer: int) -> int:
	for id in items:
		if items[id]["at"] == "held" and items[id]["ref"] == peer:
			return id
	return 0


## Loose parts put down anywhere: on the floor, a bench top or another surface.
func floor_items() -> Array:
	var out := []
	for id in items:
		if items[id]["at"] == "floor":
			out.append(id)
	return out


func item_at_spot(spot: String) -> int:
	for id in items:
		if items[id]["at"] == "spot" and items[id]["ref"] == spot:
			return id
	return 0


func riding(peer: int) -> int:
	for id in bikes:
		if bikes[id]["rider"] == peer:
			return id
	return 0


## Empty slots, including the engine's own when an engine is fitted.
func missing_slots(bike_id: int) -> Array:
	var out := []
	for slot in PartsDB.BIKE_SLOTS:
		if item_on(bike_id, slot) == 0 and not PartsDB.is_optional(slot):
			out.append(slot)
	if item_on(bike_id, "engine") != 0:
		for slot in PartsDB.ENGINE_SLOTS:
			if item_on(bike_id, slot) == 0:
				out.append(slot)
	return out


func loose_slots(bike_id: int) -> Array:
	var out := []
	for slot in PartsDB.SLOTS:
		if item_on(bike_id, slot) != 0 and not is_bolted(bike_id, slot):
			out.append(slot)
	return out


func engine_missing(engine_id: int) -> Array:
	var out := []
	for slot in PartsDB.ENGINE_SLOTS:
		if engine_item(engine_id, slot) == 0:
			out.append(slot)
	return out


func is_complete(bike_id: int) -> bool:
	return bikes.has(bike_id) and missing_slots(bike_id).is_empty() and loose_slots(bike_id).is_empty()


func condition_of(item: Dictionary) -> Dictionary:
	var cond := {"rust": item["rust"], "dirt": item["dirt"], "wear": item["wear"], "color": item["color"],
		"finish": item.get("finish", "")}
	if item.has("fluid"):
		cond["fluid"] = item["fluid"]
	if item.has("slack"):
		cond["slack"] = item["slack"]
		cond["lube"] = item.get("lube", 1.0)
	if item.get("lightened", false):
		cond["lightened"] = true
	return cond


## The bike's build from the parts on it. Missing parts fall back to what it was delivered
## with, so the numbers stay comparable. `swap` puts a loose item in `swap_slot` for previews.
func build_of(bike_id: int, swap := 0, swap_slot := "") -> BikeBuild:
	var bike: Dictionary = bikes[bike_id]
	var parts: Dictionary = bike["original"].duplicate()
	var cond: Dictionary = bike.get("original_cond", {}).duplicate()
	for slot in PartsDB.SLOTS:
		var item_id := item_on(bike_id, slot)
		if item_id != 0:
			parts[slot] = items[item_id]["part"]
			cond[slot] = condition_of(items[item_id])
		elif PartsDB.is_optional(slot):
			parts[slot] = "none"
	if swap != 0 and items.has(swap) and swap_slot != "":
		var it: Dictionary = items[swap]
		parts[swap_slot] = it["part"]
		cond[swap_slot] = condition_of(it)
		if is_engine(swap):
			for slot in PartsDB.ENGINE_SLOTS:
				var sub := engine_item(swap, slot)
				if sub != 0:
					parts[slot] = items[sub]["part"]
					cond[slot] = condition_of(items[sub])
	return BikeBuild.new(parts, cond, tune_of(bike_id))


## A bike's tune gathered from where each setting is kept (see TUNE_HOME), for BikeBuild.
## Settings never touched are left out, so they stay stock.
func tune_of(bike_id: int) -> Dictionary:
	var out := {}
	if not bikes.has(bike_id):
		return out
	var own: Dictionary = bikes[bike_id].get("tune", {})
	for key in TUNE_HOME:
		var home: Array = TUNE_HOME[key]
		if home[0] == "bike":
			if own.has(home[1]):
				out[key] = float(own[home[1]])
		elif key != "chain":
			var id := item_on(bike_id, str(home[0]))
			if id != 0 and items[id].get("tune", {}).has(home[1]):
				out[key] = float(items[id]["tune"][home[1]])
	return out


## Whether a bike is strapped down on the dyno rig.
func on_dyno(bike_id: int) -> bool:
	return bikes.has(bike_id) and (bikes[bike_id]["xf"] as Transform3D).origin.distance_to(DynoRoom.rig_transform().origin) < 0.3


## The bike on the dyno, or 0.
func dyno_bike() -> int:
	for id in bikes:
		if on_dyno(id) and bikes[id]["rider"] == 0:
			return id
	return 0


## A stock bike built around an engine on the stand, so its numbers can be compared.
func engine_build(engine_id: int, swap := 0, swap_slot := "") -> BikeBuild:
	var asm := engine_assembly(engine_id)
	var parts: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	var cond: Dictionary = asm["cond"]
	for slot in asm["parts"]:
		parts[slot] = asm["parts"][slot]
	if swap != 0 and items.has(swap) and swap_slot != "":
		parts[swap_slot] = items[swap]["part"]
		cond[swap_slot] = condition_of(items[swap])
	return BikeBuild.new(parts, cond)


func fitted_map(bike_id: int) -> Dictionary:
	var out := {}
	for slot in PartsDB.SLOTS:
		out[slot] = item_on(bike_id, slot) != 0
	return out


## An engine and what's fitted to it, for drawing it on its own: {parts, fitted, cond}.
func engine_assembly(engine_id: int) -> Dictionary:
	var it: Dictionary = items[engine_id]
	var parts := {"engine": it["part"]}
	var fitted := {"engine": true}
	var cond := {"engine": condition_of(it)}
	for slot in PartsDB.ENGINE_SLOTS:
		var sub := engine_item(engine_id, slot)
		fitted[slot] = sub != 0
		if sub != 0:
			parts[slot] = items[sub]["part"]
			cond[slot] = condition_of(items[sub])
	return {"parts": parts, "fitted": fitted, "cond": cond}


func item_title(item_id: int) -> String:
	if not items.has(item_id):
		return ""
	return PartsDB.part_name(items[item_id]["part"])


func paint_name(c: Color) -> String:
	return PAINT_NAMES[paint_index(c)]


func station_name(index := -1) -> String:
	var i: int = radio["station"] if index < 0 else index
	return str(stations[i]["name"]) if i >= 0 and i < stations.size() else ""


## "Gloss red", or just "Red" for a part still in its factory finish.
func paint_text(item: Dictionary) -> String:
	var f: String = item.get("finish", "")
	var n := paint_name(item["color"])
	return n.capitalize() if f == "" else "%s %s" % [FINISH_NAMES[f], n]


## The palette colour closest to `c`.
func paint_index(c: Color) -> int:
	var best := 0
	var best_d := INF
	for i in PAINTS.size():
		var p: Color = PAINTS[i]
		var d := Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func condition_text(item: Dictionary) -> String:
	if item.get("boxed", false):
		return "Brand new, still in its box"
	if PartsDB.is_fluid(item["part"]):
		return fluid_text(item)
	var text := "Condition %d%%   Rust %d%%   Dirt %d%%   Wear %d%%   %s" % [
		roundi(BikeBuild.part_health(condition_of(item)) * 100.0), roundi(item["rust"] * 100.0),
		roundi(item["dirt"] * 100.0), roundi(item["wear"] * 100.0), paint_text(item)]
	if item.has("slack"):
		text += "\n" + chain_text(item)
	if item.has("paint_quality"):
		text += "\n" + finish_text(item)
	return text


## How a sprayed job came out, from its coverage quality and how much was overdone.
func _job_word(q: float, overdone: float, what: String) -> String:
	var word := "a perfect coat" if q > 0.95 else ("a good coat" if q > 0.85 else ("a bit patchy" if q > 0.7 else "patchy"))
	if overdone > 0.15:
		word += ", with runs" if what == "paint" else ", and plenty flung off"
	elif overdone > 0.04:
		word += ", a few runs" if what == "paint" else ", a bit wasted"
	return word


## "Paint: good coat (91%), a few runs" for parts that have been sprayed.
func finish_text(item: Dictionary) -> String:
	if not item.has("paint_quality"):
		return ""
	var q := float(item["paint_quality"])
	return "Paint job: %s (%d%%)" % [_job_word(q, float(item.get("paint_runs", 0.0)), "paint"), roundi(q * 100.0)]


## "Slack 52 mm (too slack)  ·  Lube 20% (dry)".
func chain_text(item: Dictionary) -> String:
	var slack := float(item.get("slack", CHAIN_SLACK_SET))
	var lube := float(item.get("lube", 1.0))
	var tension := "just right"
	if slack > CHAIN_SLACK_GOOD.y:
		tension = "too slack"
	elif slack < CHAIN_SLACK_GOOD.x:
		tension = "too tight"
	var oiled := "freshly lubed" if lube > 0.8 else ("fine" if lube > 0.3 else "dry")
	return "Chain slack %d mm (%s)   Lube %d%% (%s)" % [roundi(slack), tension, roundi(lube * 100.0), oiled]


## "Fuel: 3.2 of 15 L, stale". Empty for parts that hold no fluid.
func fluid_text(item: Dictionary) -> String:
	if not item.has("fluid"):
		return ""
	var f: Dictionary = item["fluid"]
	var cap := PartsDB.fluid_capacity(item["part"])
	var k := PartsDB.fluid_kind(item["part"])
	var what: String = {"petrol": "Petrol", "oil": "Oil", "brake_fluid": "Brake fluid", "chain_lube": "Chain lube"}.get(k, "Fluid")
	var amount := ("%.2f of %.2f L" if cap < 1.0 else "%.1f of %.0f L") % [float(f["litres"]), cap]
	if float(f["litres"]) <= 0.001:
		return "%s: empty (holds %s L)" % [what, ("%.2f" if cap < 1.0 else "%.0f") % cap]
	var kind_name := PartsDB.part_name(str(f["type"])) if str(f["type"]) != "" else what
	var age := float(f.get("age", 0.0))
	var state := "fresh" if age < 0.25 else ("used" if age < 0.6 else ("stale" if k == "petrol" else "old and dirty"))
	return "%s: %s  ·  %s, %s" % [what, amount, kind_name, state]


## The part on a bike or engine that holds `kind` of fluid, as an item id: the tank, the engine,
## or the master cylinder looked at (`slot`), else the front one.
func fluid_holder(target: Dictionary, kind: String) -> int:
	var slot := str(target.get("slot", ""))
	match kind:
		"petrol":
			slot = "tank"
		"oil":
			slot = "engine"
		"brake_fluid":
			if not slot in ["front_master", "rear_master"]:
				slot = "rear_master" if slot.begins_with("rear_") else "front_master"
	if int(target.get("engine", 0)) != 0:
		return int(target["engine"]) if kind == "oil" else 0
	return item_on(int(target.get("bike", 0)), slot)


func free_bay(bay_count: int) -> int:
	for bay in bay_count:
		if bay_is_free(bay):
			return bay
	return -1


func bay_is_free(bay: int) -> bool:
	for id in bikes:
		if bikes[id]["xf"].origin.distance_to(Workshop.bay_transform(bay).origin) < 2.5:
			return false
	return true


## The bay whose paddock stand is near `at`, or -1.
func bay_at(at: Vector3) -> int:
	for bay in Workshop.BAY_COUNT:
		var o := Workshop.bay_transform(bay).origin
		if Vector2(at.x - o.x, at.z - o.z).length() < 1.6:
			return bay
	return -1


## Where the next delivery is left outside the roller door, beside the drive so bikes can still
## get out. Returns null when the delivery area is full.
func free_delivery_xf():
	for row in DELIVERY_ROWS:
		for col in DELIVERY_COLS:
			var at := Workshop.CENTER + Vector3(3.2 + col * 0.85, 0.0, Workshop.HALF.y + 1.3 + row * 0.9)
			if _clear_at(at, 0.5):
				return Transform3D(Basis(Vector3.UP, PI), at)
	return null


## Where yard kit is dropped off: the west end of the yard just past the drag strip, clear of the
## jumps already set up. Returns null when it's all taken.
func free_yard_xf(model: String):
	var size: Vector3 = Equipment.get_model(model).get("size", Vector3.ONE)
	var r := maxf(size.x, size.z) * 0.5 + 0.5
	for row in 3:
		for col in 8:
			var at := Vector3(-60.0 + col * 4.0, 0.0, 107.0 + row * 3.0 + size.z * 0.5)
			if _clear_at(at, r):
				return Transform3D(Basis(), at)
	return null


## Nothing put down or parked within `radius` of `at` on the ground.
func _clear_at(at: Vector3, radius: float) -> bool:
	for id in items:
		if items[id]["at"] == "floor" and Vector2(items[id]["ref"].origin.x - at.x, items[id]["ref"].origin.z - at.z).length() < radius:
			return false
	for id in furniture:
		if Vector2(furniture[id]["xf"].origin.x - at.x, furniture[id]["xf"].origin.z - at.z).length() < radius + 0.4:
			return false
	return true


# ---------------------------------------------------------------------------- spots and furniture

func is_spot(spot: String) -> bool:
	if SPOTS.has(spot):
		return true
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return false
	if f["kind"] == "stand":
		return true
	var n := int(spot.get_slice("_", 2))
	return n >= 0 and n < Equipment.places(str(f["model"]))


func is_stand_spot(spot: String) -> bool:
	return spot.begins_with("stand_")


## The equipment a spot belongs to, or {}.
func furniture_of_spot(spot: String) -> Dictionary:
	var prefix := spot.get_slice("_", 0)
	if prefix != "stand" and not Equipment.SPOT_PREFIX.values().has(prefix):
		return {}
	if prefix != "stand" and spot.get_slice_count("_") != 3:
		return {}
	var f: Dictionary = furniture.get(int(spot.get_slice("_", 1)), {})
	if f.is_empty():
		return {}
	var want: String = "stand" if f["kind"] == "stand" else str(Equipment.SPOT_PREFIX.get(f["kind"], "-"))
	return f if want == prefix else {}


## What a spot is part of: "bench" (the fixed workbench or a bought one), "shelf", "washer",
## "repair", "stand" or "".
func spot_role(spot: String) -> String:
	if SPOTS.has(spot):
		return "bench"
	var f := furniture_of_spot(spot)
	return "" if f.is_empty() else str(f["kind"])


## The places on one piece of equipment.
func furniture_spots(id: int) -> Array:
	var f: Dictionary = furniture.get(id, {})
	if f.is_empty():
		return []
	if f["kind"] == "stand":
		return ["stand_%d" % id]
	var prefix: String = Equipment.SPOT_PREFIX.get(f["kind"], "")
	if prefix == "":
		return []
	var out := []
	for n in Equipment.places(str(f["model"])):
		out.append("%s_%d_%d" % [prefix, id, n])
	return out


## Every spot that exists right now, fixed ones first.
func all_spots() -> Array:
	var out: Array = SPOTS.duplicate()
	for id in furniture:
		out.append_array(furniture_spots(id))
	return out


func stand_spots() -> Array:
	return all_spots().filter(func(s): return is_stand_spot(s))


## Where a part on a spot sits in the world. Equipment carries its places with it.
func spot_transform(spot: String) -> Transform3D:
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return Workshop.spot_transform(spot)
	return (f["xf"] as Transform3D) * local_spot_transform(spot)


## Where a spot is on its piece of equipment, in the equipment's own space.
func local_spot_transform(spot: String) -> Transform3D:
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return Transform3D()
	return Equipment.local_place(str(f["model"]), 0 if f["kind"] == "stand" else int(spot.get_slice("_", 2)))


func furniture_name(f: Dictionary) -> String:
	var n := str(Equipment.get_model(str(f.get("model", ""))).get("name", "Equipment"))
	if f["kind"] == "shelf" and str(f.get("label", "")) != "":
		return "%s: %s" % [n, f["label"]]
	return n


## The shed's built-in kit: the paint booth in its lean-to. Adds whatever is missing (a new shed,
## or a save from before it was built in).
func ensure_fixtures() -> void:
	for id in furniture:
		if furniture[id]["kind"] == "booth":
			furniture[id]["xf"] = Workshop.BOOTH_XF
			return
	_new_furniture("booth", Workshop.BOOTH_XF, "booth_pro")


func _new_furniture(kind: String, xf: Transform3D, model := "") -> int:
	if model == "" or Equipment.kind_of(model) != kind:
		model = str(Equipment.DEFAULT.get(kind, ""))
	var id := _next_id
	_next_id += 1
	furniture[id] = {"id": id, "kind": kind, "model": model, "xf": xf, "label": "", "mover": 0}
	return id


## Repairable parts sitting on the same repair machine as `spot`.
func repair_batch(spot: String) -> Array:
	var f := furniture_of_spot(spot)
	if f.is_empty() or f["kind"] != "repair":
		return []
	var out := []
	for s in furniture_spots(int(f["id"])):
		var id := item_at_spot(s)
		if id != 0 and not items[id].get("boxed", false) and (items[id]["rust"] >= 0.02 or items[id]["wear"] >= 0.02):
			out.append(id)
	return out


## How long the grinder takes over a batch on a repair machine: the worst part sets the pace.
func repair_time(ids: Array) -> float:
	var worst := 0.0
	var speed := 1.0
	for id in ids:
		if not items.has(int(id)):
			continue
		worst = maxf(worst, float(items[int(id)]["rust"]) + float(items[int(id)]["wear"]))
		var f := furniture_of_spot(str(items[int(id)]["ref"]))
		if not f.is_empty():
			speed = float(Equipment.get_model(str(f["model"])).get("speed", 1.0))
	return (2.0 + 4.0 * worst + 0.6 * maxi(0, ids.size() - 1)) / speed


func moving(peer: int) -> int:
	for id in furniture:
		if furniture[id]["mover"] == peer:
			return id
	return 0


func pushing_bike(peer: int) -> int:
	for id in bikes:
		if bikes[id].get("pusher", 0) == peer:
			return id
	return 0


## Whether a bike sits on its bay's paddock stand: parked square in the bay, or missing a wheel.
func on_paddock(bike_id: int) -> bool:
	var bike: Dictionary = bikes[bike_id]
	if bike["xf"].origin.distance_to(Workshop.bay_transform(bike["bay"]).origin) < 0.5:
		return true
	for slot in ["front_wheel", "rear_wheel", "front_tyre", "rear_tyre"]:
		if item_on(bike_id, slot) == 0:
			return true
	return false


## Why a bike can't be wheeled about, or "".
func _wheel_check(bike_id: int) -> String:
	for slot in ["front_wheel", "rear_wheel", "front_tyre", "rear_tyre"]:
		if item_on(bike_id, slot) == 0:
			return "It won't roll without both wheels and tyres."
	return ""


## The stand a bike drops onto when you let go of it or get off: the side stand if it has one,
## then the centre stand, otherwise it falls over.
func _rest_stand(bike_id: int) -> String:
	if item_on(bike_id, "side_stand") != 0:
		return "side"
	if item_on(bike_id, "centre_stand") != 0:
		return "centre"
	return "down"


## A free bay whose parking spot is close to `xf`, or -1.
func _bay_near(xf: Transform3D, bike_id: int) -> int:
	for bay in Workshop.BAY_COUNT:
		var spot := Workshop.bay_transform(bay)
		if spot.origin.distance_to(xf.origin) > 0.9:
			continue
		var taken := false
		for id in bikes:
			if id != bike_id and bikes[id]["xf"].origin.distance_to(spot.origin) < 1.5:
				taken = true
		if not taken:
			return bay
	return -1


## Where a held part would go on a target, or why it can't: {slot} or {error}.
## Prefers the slot being looked at, then the same side (front or rear), then any free slot.
func install_slot(action: Dictionary, item_id: int) -> Dictionary:
	if not items.has(item_id):
		return {"error": "You're not holding a part."}
	var k: String = items[item_id]["kind"]
	var candidates := PartsDB.slots_for_kind(k)
	if candidates.is_empty():
		return {"error": "That doesn't bolt on anywhere."}
	var engine_id := int(action.get("engine", 0))
	var bike_id := int(action.get("bike", 0))
	var on_engine := PartsDB.is_engine_slot(candidates[0])
	if engine_id != 0 and not on_engine:
		return {"error": "That doesn't go on an engine."}
	var host := host_of(bike_id, candidates[0], engine_id)
	if host.is_empty():
		return {"error": "Fit an engine first." if on_engine else "That bike has gone."}
	var looked := str(action.get("slot", ""))
	var side := "front_" if looked.begins_with("front_") else ("rear_" if looked.begins_with("rear_") else "")
	candidates.sort_custom(func(a, b): return _slot_rank(a, looked, side) < _slot_rank(b, looked, side))
	var missing_mount := ""
	for slot in candidates:
		if int(host["slots"].get(slot, 0)) != 0:
			continue
		var ok := true
		for m in PartsDB.MOUNTS[slot]:
			if m == "engine" and on_engine:
				continue
			if int(host["slots"].get(m, 0)) == 0:
				ok = false
				if missing_mount == "":
					missing_mount = m
		if ok:
			return {"slot": slot}
	if missing_mount != "":
		return {"error": "Fit the %s first." % PartsDB.slot_name(missing_mount).to_lower()}
	return {"error": "There's already a %s fitted." % PartsDB.KIND_NAMES[k].to_lower()}


func _slot_rank(slot: String, looked: String, side: String) -> int:
	if slot == looked:
		return 0
	if side != "" and slot.begins_with(side):
		return 1
	return 2


## Engine work needs the engine on the stand, except for service parts in the frame.
func _engine_access(action: Dictionary, slot: String) -> String:
	if not PartsDB.is_engine_slot(slot):
		return ""
	var engine_id := int(action.get("engine", 0))
	if engine_id == 0:
		if PartsDB.SERVICE_SLOTS.has(slot):
			return ""
		return "Take the engine out and put it on the engine stand to get at the %s." % PartsDB.slot_name(slot).to_lower()
	var block: Dictionary = items[engine_id]
	if not (block["at"] == "spot" and is_stand_spot(str(block["ref"]))):
		return "Put the engine on the engine stand first."
	return ""


## Why `peer` can't do `action` right now, or "" when they can.
func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var held := held_by(peer)
	var bike_id := int(action.get("bike", 0))
	var engine_id := int(action.get("engine", 0))
	var slot := str(action.get("slot", ""))
	if a in ["unbolt", "bolt", "remove"] and engine_id == 0 and PartsDB.LOW_SLOTS.has(slot) \
			and not action.get("crouched", false):
		return "Crouch down to reach it (C)."
	if a in ["unbolt", "bolt", "remove", "install", "mount", "grab_bike", "set_stand", "adjust_chain"]:
		if engine_id != 0:
			if not is_engine(engine_id):
				return "That engine has gone."
		elif not bikes.has(bike_id):
			return "That bike has gone."
		elif bikes[bike_id]["rider"] != 0:
			return "Someone is riding that bike."
		elif bikes[bike_id].get("pusher", 0) != 0 and bikes[bike_id].get("pusher", 0) != peer:
			return "Someone is wheeling that bike about."
	match a:
		"unbolt", "bolt", "remove":
			var host := host_of(bike_id, slot, engine_id)
			var item_id := int(host.get("slots", {}).get(slot, 0))
			if item_id == 0:
				return "That part isn't fitted."
			var bolted := bool(host["bolted"].get(slot, false))
			if a == "unbolt" and not bolted:
				return "It's already unbolted."
			if a == "bolt" and bolted:
				return "It's already bolted up."
			if a == "remove":
				var access := _engine_access(action, slot)
				if access != "":
					return access
				if held != 0:
					return "Your hands are full."
				if bolted:
					return "Unbolt it with the wrench first."
				for dep in PartsDB.dependents(slot):
					if int(host["slots"].get(dep, 0)) != 0:
						return "Take the %s off first." % PartsDB.slot_name(dep).to_lower()
		"install":
			if held == 0:
				return "You're not holding a part."
			if items[held].get("boxed", false):
				return "Unpack it first."
			var where := install_slot(action, held)
			if where.has("error"):
				return where["error"]
			if engine_id == 0 and PartsDB.LOW_SLOTS.has(where["slot"]) and not action.get("crouched", false):
				return "Crouch down to reach it (C)."
			var access := _engine_access(action, where["slot"])
			if access != "":
				return access
		"take":
			if held != 0:
				return "Your hands are full."
			if action.has("item"):
				if not (items.has(int(action["item"])) and items[int(action["item"])]["at"] == "floor"):
					return "Nothing there."
			elif item_at_spot(str(action.get("spot", ""))) == 0:
				return "Nothing there."
		"drop":
			if held == 0:
				return "You're not holding a part."
			if not (action.get("xf") is Transform3D):
				return "You can't put it there."
			var at: Vector3 = (action["xf"] as Transform3D).origin
			if at.y < -5.0 or at.distance_to(Workshop.CENTER) > 400.0:
				return "You can't put it there."
		"place":
			if held == 0:
				return "You're not holding a part."
			var spot := str(action.get("spot", ""))
			if not is_spot(spot):
				return "You can't put it there."
			if item_at_spot(spot) != 0:
				return "That spot is taken."
			if is_stand_spot(spot) and (not is_engine(held) or items[held].get("boxed", false)):
				return "Only an engine goes on the engine stand."
			if spot_role(spot) in ["washer", "repair"] and items[held].get("boxed", false):
				return "Unpack it first."
		"radio":
			var st := int(action.get("station", radio["station"]))
			if st < 0 or st >= stations.size():
				return "No such station."
		"order_part":
			if PartsDB.get_part(str(action.get("part", ""))).is_empty():
				return "Unknown part."
			if free_delivery_xf() == null:
				return "The delivery area outside is full. Bring some boxes in first."
		"order_furniture":
			var model := str(action.get("model", Equipment.DEFAULT.get(str(action.get("kind", "")), "")))
			if Equipment.get_model(model).is_empty():
				return "Unknown equipment."
			if Equipment.FIXED_KINDS.has(Equipment.kind_of(model)):
				return "The paint booth is built into the shed: it's in the paint shop on the east side."
			if Equipment.is_yard(model):
				if free_yard_xf(model) == null:
					return "The drop-off by the drag strip is full. Move some of the yard kit first."
			elif free_delivery_xf() == null:
				return "The delivery area outside is full. Bring some boxes in first."
		"unpack":
			var box := int(action.get("item", 0))
			if not items.has(box) or not items[box].get("boxed", false):
				return "Nothing to unpack."
			if items[box]["at"] == "held":
				return "Put it down first."
		"grab":
			var f: Dictionary = furniture.get(int(action.get("furniture", 0)), {})
			if f.is_empty():
				return "That has gone."
			if Equipment.FIXED_KINDS.has(str(f["kind"])):
				return "The %s is built in." % furniture_name(f).to_lower()
			if f["mover"] != 0 and f["mover"] != peer:
				return "Someone else is moving that."
			if held != 0:
				return "Put the part down first."
			if moving(peer) != 0:
				return "You're already moving something."
		"move_furniture", "release":
			var f: Dictionary = furniture.get(int(action.get("furniture", 0)), {})
			if f.is_empty() or f["mover"] != peer:
				return "You're not moving that."
			if not (action.get("xf") is Transform3D):
				return "You can't put it there."
		"label":
			var f: Dictionary = furniture.get(int(action.get("furniture", 0)), {})
			if f.is_empty() or f["kind"] != "shelf":
				return "Only shelves take labels."
		"rename_bike":
			if not bikes.has(bike_id):
				return "That bike's gone."
			if str(action.get("name", "")).strip_edges() == "":
				return "Give it a name."
		"door", "lights":
			pass
		"bin":
			if held == 0:
				return "You're not holding a part."
		"tip":
			if held == 0 or not items[held].has("fluid") or float(items[held]["fluid"]["litres"]) <= 0.0:
				return "Nothing to tip away."
		"clean_many":
			var dirty := 0
			for id in action.get("items", []):
				if items.has(int(id)) and items[int(id)]["at"] != "held" and items[int(id)]["dirt"] >= 0.02 \
						and not items[int(id)].get("boxed", false):
					dirty += 1
			if dirty == 0:
				return "It's already clean."
		"repair_many":
			var batch: Array = action.get("items", [])
			if batch.is_empty():
				return "Nothing on it needs restoring."
			var machine := ""
			for id in batch:
				if not items.has(int(id)) or items[int(id)]["at"] != "spot" or spot_role(str(items[int(id)]["ref"])) != "repair":
					return "Put the parts on a repair machine first."
				var f := furniture_of_spot(str(items[int(id)]["ref"]))
				if machine != "" and machine != str(f["id"]):
					return "Those parts are on different machines."
				machine = str(f["id"])
				if items[int(id)].get("boxed", false):
					return "Unpack it first."
			if batch.all(func(id): return items[int(id)]["rust"] < 0.02 and items[int(id)]["wear"] < 0.02):
				return "It's all in top condition."
		"adjust_chain":
			var chain := item_on(bike_id, "chain")
			if chain == 0:
				return "There's no chain on it."
			if not action.get("crouched", false):
				return "Crouch down (C) to get at the chain adjusters."
			if bikes[bike_id]["rider"] != 0:
				return "Someone's riding it."
			var slack := float(items[chain].get("slack", CHAIN_SLACK_SET))
			if absf(slack - CHAIN_SLACK_SET) < 3.0:
				return "The chain tension is spot on."
		"lube":
			if held == 0 or PartsDB.kind_of(items[held]["part"]) != "chain_lube":
				return "You need a can of chain lube in your hands."
			if float(items[held].get("fluid", {}).get("litres", 0.0)) < LUBE_USE * 0.5:
				return "The can's empty."
			var chain := int(action.get("item", 0))
			if not items.has(chain) or items[chain]["kind"] != "chain":
				return "Aim at a chain."
			if items[chain]["at"] == "bike" and not action.get("crouched", false):
				return "Crouch down (C) to get at the chain."
			if float(items[chain].get("lube", 0.0)) > 0.95:
				return "It's freshly lubed."
		"clean", "repair", "paint":
			var item_id := int(action.get("item", 0))
			if not items.has(item_id):
				return "That part has gone."
			var it: Dictionary = items[item_id]
			if it["at"] == "held":
				return "Put it down first."
			if it.get("boxed", false):
				return "Unpack it first."
			if a == "clean" and it["dirt"] < 0.02:
				return "It's already clean."
			if a == "repair":
				if not (it["at"] == "spot" and spot_role(str(it["ref"])) == "repair"):
					return "Put the part on a repair machine first."
				if it["rust"] < 0.02 and it["wear"] < 0.02:
					return "It's already in top condition."
			if a == "paint" and action.get("gun", false) and not (it["at"] == "spot" and spot_role(str(it["ref"])) == "booth"):
				return "The spray gun runs off the paint booth's air line. Hang the part in a booth."
			if a == "paint" and it["rust"] > MAX_PAINT_RUST:
				return "Too rusty to paint. Grind it back on the repair bench first."
			if a == "paint" and it.get("finish", "") == str(action.get("finish", "gloss")) \
					and paint_index(it["color"]) == int(action.get("color", 0)) and it["color"] == PAINTS[paint_index(it["color"])]:
				return "It's already %s." % paint_text(it).to_lower()
		"pour", "drain":
			if held == 0 or not PartsDB.is_fluid(items[held]["part"]):
				return "You need a can or bottle of it in your hands."
			var into := int(action.get("item", 0))
			if not items.has(into) or not items[into].has("fluid") or PartsDB.is_fluid(items[into]["part"]):
				return "That doesn't take any fluid."
			var k := PartsDB.fluid_kind(items[into]["part"])
			var can_k := PartsDB.kind_of(items[held]["part"])
			if k != can_k:
				return "That takes %s, not %s." % [PartsDB.KIND_NAMES[k].to_lower(), PartsDB.KIND_NAMES[can_k].to_lower()]
			var room := PartsDB.fluid_capacity(items[into]["part"]) - float(items[into]["fluid"]["litres"])
			var can_room := PartsDB.fluid_capacity(items[held]["part"]) - float(items[held]["fluid"]["litres"])
			if a == "pour":
				if float(items[held]["fluid"]["litres"]) <= 0.001:
					return "It's empty."
				if room <= 0.005:
					return "It's already full."
			else:
				if k == "oil" and items[into]["at"] == "bike" and not action.get("crouched", false):
					return "Crouch down to get at the drain plug (C)."
				if float(items[into]["fluid"]["litres"]) <= 0.001:
					return "There's nothing to drain."
				if can_room <= 0.005:
					return "Your %s is full. Tip it in the scrap bin." % PartsDB.get_part(items[held]["part"])["container"].to_lower()
		"wash":
			var at = action.get("at", null)
			if not (at is Vector3) or (at as Vector3).distance_to(Workshop.WASH_POS) > Workshop.WASH_REACH:
				return "The hose doesn't reach. Bring the bike to the wash bay beside the shed."
			var any := false
			for id in action.get("items", []):
				if items.has(int(id)) and items[int(id)]["dirt"] >= 0.005 and not items[int(id)].get("boxed", false):
					any = true
			if not any:
				return "It's already clean."
		"grab_bike":
			var why := _wheel_check(bike_id)
			if why != "":
				return why
			if held != 0:
				return "Put the part down first."
			if moving(peer) != 0 or pushing_bike(peer) != 0:
				return "You're already moving something."
		"move_bike", "release_bike":
			if not bikes.has(bike_id) or bikes[bike_id].get("pusher", 0) != peer:
				return "You're not holding that bike."
			if not (action.get("xf") is Transform3D):
				return "You can't put it there."
		"set_stand":
			var which := str(action.get("stand", ""))
			if not which in ["side", "centre"]:
				return "Unknown stand."
			if item_on(bike_id, which + "_stand") == 0:
				return "There's no %s stand fitted." % which
			if bikes[bike_id].get("stand", "") == which:
				return "It's already on its %s stand." % which
			if on_paddock(bike_id):
				return "It's on the paddock stand in the bay."
			if on_dyno(bike_id):
				return "It's strapped down on the dyno."
		"mount":
			if riding(peer) != 0:
				return "You're already riding."
			if pushing_bike(peer) != 0:
				return "Let go of the bike first, then get on it."
			if held != 0:
				return "Put the part down first."
			if moving(peer) != 0:
				return "Let go of what you're pushing first."
			var missing := missing_slots(bike_id)
			if not missing.is_empty():
				return "Missing: %s." % _slot_list(missing)
			var loose := loose_slots(bike_id)
			if not loose.is_empty():
				return "Not bolted up: %s." % _slot_list(loose)
		"dismount":
			if not bikes.has(bike_id) or bikes[bike_id]["rider"] != peer:
				return "You're not riding that bike."
		"start_build":
			if held == 0 or items[held]["kind"] != "frame":
				return "Hold a frame to start a bike from scratch."
			if items[held].get("boxed", false):
				return "Unpack it first."
			var bay := int(action.get("bay", -1))
			if bay < 0 or bay >= Workshop.BAY_COUNT:
				return "Take it to one of the bays."
			if not bay_is_free(bay):
				return "There's already a bike in bay %d." % (bay + 1)
		"order":
			if free_bay(Workshop.BAY_COUNT) < 0:
				return "Every bay is full. Ride a bike out or strip one down first."
		"tune":
			if not bikes.has(bike_id):
				return "That bike has gone."
			if bikes[bike_id]["rider"] != 0:
				return "Someone is riding that bike."
			var key := str(action.get("key", ""))
			if not TUNE_HOME.has(key):
				return "There's nothing like that to adjust."
			var home: Array = TUNE_HOME[key]
			if home[0] != "bike" and item_on(bike_id, str(home[0])) == 0:
				return "There's no %s fitted." % PartsDB.slot_name(str(home[0])).to_lower()
			if not action.get("reset", false) and not (action.get("value") is float or action.get("value") is int):
				return "Pick a setting."
			var why := build_of(bike_id).tune_block(key)
			if why != "":
				return why
		"lighten":
			var id := int(action.get("item", 0))
			if not items.has(id):
				return "That part has gone."
			if items[id].get("boxed", false):
				return "Unpack it first."
			if items[id]["at"] == "bike" and bikes.has(int(items[id]["ref"])) and bikes[int(items[id]["ref"])]["rider"] != 0:
				return "Someone is riding that bike."
			if items[id].get("lightened", false):
				return "It's already been drilled and trimmed."
			if PartsDB.is_lightweight(str(items[id]["part"])):
				return "It's already as light as it goes."
			if BikeBuild.lighten_cut(str(items[id]["part"])) <= 0.0:
				return "There's nothing to trim off that."
		"dyno_run":
			if not on_dyno(bike_id):
				return "Wheel a bike onto the dyno first."
			if bikes[bike_id]["rider"] != 0 or bikes[bike_id].get("pusher", 0) != 0:
				return "Let go of it so it can be strapped down."
			if Time.get_ticks_msec() < _dyno_busy_until:
				return "It's mid-run. Wait for it to finish."
			var missing := missing_slots(bike_id)
			if not missing.is_empty():
				return "It won't run. Missing: %s." % _slot_list(missing)
			var loose := loose_slots(bike_id)
			if not loose.is_empty():
				return "Bolt it up first: %s." % _slot_list(loose)
			var build := build_of(bike_id)
			if build.fuel_litres < 0.05:
				return "There's no petrol in the tank."
			if build.oil_litres < 0.1:
				return "There's no oil in the engine. It would seize."
		"status", "ride", "tip":
			pass
		_:
			return "Unknown action."
	return ""


func _slot_list(slots: Array) -> String:
	var names: Array = slots.slice(0, 4).map(func(m): return PartsDB.slot_name(m).to_lower())
	if slots.size() > 4:
		names.append("and %d more" % (slots.size() - 4))
	return ", ".join(names)


# ---------------------------------------------------------------------------- changes

## Asks the host to do something. Solo, or as the host, it happens straight away.
func request(action: Dictionary) -> void:
	if is_authority():
		_apply(me(), action)
	else:
		_request.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _request(action: Dictionary) -> void:
	if is_authority():
		_apply(multiplayer.get_remote_sender_id(), action)


func _apply(peer: int, action: Dictionary) -> void:
	if str(action.get("a", "")) == "ping":
		# A ping changes nothing in the shed: it just goes out to everyone.
		var at = action.get("at", Vector3.ZERO)
		var d := {"at": at if at is Vector3 else Vector3.ZERO, "what": str(action.get("what", "")).left(60),
			"item": int(action.get("item", 0)), "furniture": int(action.get("furniture", 0)),
			"name": str(crew.get(peer, {}).get("name", "Someone"))}
		pinged.emit(peer, d)
		if Net.is_online():
			_ping.rpc(peer, d)
		return
	if str(action.get("a", "")).begins_with("board_"):
		_board_apply(peer, action)
		return
	var why := check(peer, action)
	if why != "":
		_tell(peer, why, false)
		return
	var a := str(action["a"])
	var bike_id := int(action.get("bike", 0))
	var engine_id := int(action.get("engine", 0))
	var slot := str(action.get("slot", ""))
	var c: Dictionary = crew.get(peer, {})
	var text := ""
	match a:
		"unbolt":
			host_of(bike_id, slot, engine_id)["bolted"][slot] = false
			text = "%s unbolted" % PartsDB.slot_name(slot)
		"bolt":
			host_of(bike_id, slot, engine_id)["bolted"][slot] = true
			text = "%s bolted up" % PartsDB.slot_name(slot)
			if engine_id == 0 and is_complete(bike_id):
				text += ". The bike is ready to ride!"
			elif engine_id != 0 and engine_missing(engine_id).is_empty():
				text += ". The engine is complete."
		"remove":
			var host := host_of(bike_id, slot, engine_id)
			var item_id := int(host["slots"][slot])
			host["slots"][slot] = 0
			host["bolted"][slot] = false
			_move(item_id, "held", peer)
			_bump(c, "removed")
			text = "Removed the %s" % PartsDB.part_name(items[item_id]["part"])
			if engine_id == 0 and slot == "frame":
				# Nothing left of it: the bay is free for the next project.
				text += ". Bay %d is free." % (bikes[bike_id]["bay"] + 1)
				bikes.erase(bike_id)
		"install":
			var item_id := held_by(peer)
			var s: String = install_slot(action, item_id)["slot"]
			var host := host_of(bike_id, s, engine_id)
			host["slots"][s] = item_id
			host["bolted"][s] = false
			_move(item_id, "engine" if PartsDB.is_engine_slot(s) else "bike", int(host["id"]))
			_bump(c, "fitted")
			text = "Fitted the %s as the %s. Bolt it up with the wrench." % [PartsDB.part_name(items[item_id]["part"]),
				PartsDB.slot_name(s).to_lower()]
		"take":
			if action.has("item"):
				_move(int(action["item"]), "held", peer)
			else:
				_move(item_at_spot(str(action["spot"])), "held", peer)
		"drop":
			_move(held_by(peer), "floor", action["xf"])
		"place":
			var item_id := held_by(peer)
			_move(item_id, "spot", str(action["spot"]))
			if is_stand_spot(str(action["spot"])):
				text = "Engine on the stand. Strip it down or build it up."
			elif spot_role(str(action["spot"])) == "washer":
				text = "Into the %s" % furniture_name(furniture_of_spot(str(action["spot"]))).to_lower()
		"order_part":
			var part_id := str(action["part"])
			var item_id := _new_item(part_id, 0.0, 0.0, 0.0)
			# Parts come boxed; cans and bottles of fluid are left as they are.
			items[item_id]["boxed"] = not PartsDB.is_fluid(part_id)
			_move(item_id, "floor", free_delivery_xf())
			text = "Ordered %s. %s outside by the roller door." % [PartsDB.part_name(part_id),
				"The box is" if items[item_id]["boxed"] else "It's"]
		"order_furniture":
			var model := str(action.get("model", Equipment.DEFAULT.get(str(action.get("kind", "")), "")))
			var kind := Equipment.kind_of(model)
			if Equipment.is_yard(model):
				_new_furniture(kind, free_yard_xf(model), model)
				text = "Ordered the %s. It's in the yard by the drag strip: press F on it to move it where you want it." % \
					Equipment.get_model(model)["name"].to_lower()
			else:
				_new_furniture(kind, free_delivery_xf(), model)
				var how := "press F on it to carry it in and hang it on a wall" if Equipment.is_wall(model) else \
					("hold F on it to move it" if kind == "seat" else "press F on it to push it in")
				text = "Ordered the %s. It's outside by the roller door: %s." % [Equipment.get_model(model)["name"].to_lower(), how]
		"start_build":
			var id := _empty_bike(held_by(peer), int(action["bay"]))
			_bump(c, "fitted")
			text = "%s is on the paddock stand in bay %d. Fit the forks, shock and the rest to it, then bolt it all up." % [
				bikes[id]["name"], int(action["bay"]) + 1]
		"unpack":
			items[int(action["item"])]["boxed"] = false
			text = "Unpacked the %s" % item_title(int(action["item"]))
		"grab":
			furniture[int(action["furniture"])]["mover"] = peer
		"move_furniture":
			furniture[int(action["furniture"])]["xf"] = action["xf"]
		"release":
			furniture[int(action["furniture"])]["xf"] = action["xf"]
			furniture[int(action["furniture"])]["mover"] = 0
		"rename_bike":
			bikes[bike_id]["name"] = str(action["name"]).strip_edges().left(28)
			text = "Named it %s" % bikes[bike_id]["name"]
		"door":
			door_open = bool(action.get("open", not door_open))
			text = "Roller door %s" % ("going up" if door_open else "coming down")
		"lights":
			lights_on = bool(action.get("on", not lights_on))
			text = "Lights %s" % ("on" if lights_on else "off")
		"label":
			furniture[int(action["furniture"])]["label"] = str(action.get("text", "")).strip_edges().left(24)
			text = "Labelled the shelves \"%s\"" % furniture[int(action["furniture"])]["label"]
		"bin":
			var item_id := held_by(peer)
			text = "Binned the %s" % PartsDB.part_name(items[item_id]["part"])
			_erase_item(item_id)
		"clean_many":
			var n := 0
			for id in action["items"]:
				if items.has(int(id)) and items[int(id)]["at"] != "held" and items[int(id)]["dirt"] >= 0.02 \
						and not items[int(id)].get("boxed", false):
					items[int(id)]["dirt"] = 0.0
					n += 1
			_bump(c, "cleaned")
			c["cleaned"] = int(c["cleaned"]) + n - 1
			text = "Scrubbed %d part%s clean" % [n, "" if n == 1 else "s"]
		"clean":
			items[int(action["item"])]["dirt"] = 0.0
			_bump(c, "cleaned")
			text = "Cleaned the %s" % item_title(int(action["item"]))
		"repair":
			var it: Dictionary = items[int(action["item"])]
			it["rust"] = 0.0
			it["wear"] = 0.0
			_bump(c, "repaired")
			text = "Restored the %s" % item_title(int(action["item"]))
		"repair_many":
			var n := 0
			for id in action["items"]:
				if items.has(int(id)) and (items[int(id)]["rust"] > 0.0 or items[int(id)]["wear"] > 0.0):
					items[int(id)]["rust"] = 0.0
					items[int(id)]["wear"] = 0.0
					n += 1
			c["repaired"] = int(c.get("repaired", 0)) + n
			text = "Restored %d part%s" % [n, "" if n == 1 else "s"] if n != 1 else "Restored the %s" % item_title(int(action["items"][0]))
		"adjust_chain":
			var chain := item_on(bike_id, "chain")
			var was := float(items[chain].get("slack", CHAIN_SLACK_SET))
			items[chain]["slack"] = CHAIN_SLACK_SET
			text = "Chain %s to %d mm of slack" % ["tightened" if was > CHAIN_SLACK_SET else "slackened off", roundi(CHAIN_SLACK_SET)]
		"lube":
			# How well it went on: coverage along the chain, less any flung off where it was overdone.
			var chain := int(action["item"])
			var q := clampf(float(action.get("quality", 1.0)), 0.0, 1.0)
			var waste := clampf(float(action.get("waste", 0.0)), 0.0, 1.0)
			var can: Dictionary = items[held_by(peer)]["fluid"]
			can["litres"] = maxf(0.0, float(can["litres"]) - LUBE_USE * (1.0 + waste * 2.0))
			items[chain]["lube"] = maxf(float(items[chain].get("lube", 0.0)), lerpf(0.5, 1.0, q))
			items[chain]["lube_type"] = str(can["type"])
			text = "Lubed the chain with %s: %s" % [PartsDB.part_name(str(can["type"])), _job_word(q, waste, "lube")]
		"paint":
			var idx := clampi(int(action.get("color", 0)), 0, PAINTS.size() - 1)
			var finish := str(action.get("finish", "gloss"))
			if not FINISHES.has(finish):
				finish = "gloss"
			var it: Dictionary = items[int(action["item"])]
			it["color"] = PAINTS[idx]
			it["finish"] = finish
			var q := clampf(float(action.get("quality", 1.0)), 0.0, 1.0)
			var runs := clampf(float(action.get("waste", 0.0)), 0.0, 1.0)
			if it["at"] == "spot" and spot_role(str(it["ref"])) == "booth":
				# No dust settling in the wet paint: a booth gives a cleaner finish.
				var booth := furniture_of_spot(str(it["ref"]))
				q = minf(1.0, q + float(Equipment.get_model(str(booth["model"])).get("finish", 0.05)))
			it["paint_quality"] = q
			it["paint_runs"] = runs
			_bump(c, "painted")
			text = "Sprayed the %s %s: %s" % [item_title(int(action["item"])), paint_text(it).to_lower(), _job_word(q, runs, "paint")]
		"mount":
			if bikes[bike_id].get("stand", "") == "down":
				text = "You heave %s back upright" % bikes[bike_id]["name"]
			bikes[bike_id]["rider"] = peer
			bikes[bike_id]["stand"] = ""
			c["riding"] = bike_id
		"dismount":
			bikes[bike_id]["rider"] = 0
			bikes[bike_id]["xf"] = action.get("xf", bikes[bike_id]["xf"])
			c["riding"] = 0
			_park(bike_id)
			if bikes[bike_id]["stand"] == "down":
				text = "No stand fitted, so it falls over. Fit a side stand."
		"grab_bike":
			bikes[bike_id]["pusher"] = peer
			bikes[bike_id]["stand"] = ""
			text = "Got hold of %s. F to let go." % bikes[bike_id]["name"]
		"move_bike":
			bikes[bike_id]["xf"] = action["xf"]
		"release_bike":
			bikes[bike_id]["pusher"] = 0
			bikes[bike_id]["xf"] = action["xf"]
			_park(bike_id)
			if on_dyno(bike_id):
				text = "%s is strapped down on the dyno. Use the dyno desk (F) to tune it and run it." % bikes[bike_id]["name"]
			elif bikes[bike_id]["stand"] == "down":
				text = "No stand fitted, so it falls over."
			elif on_paddock(bike_id):
				text = "%s is on the paddock stand in bay %d" % [bikes[bike_id]["name"], bikes[bike_id]["bay"] + 1]
		"tune":
			var key := str(action["key"])
			var home: Array = TUNE_HOME[key]
			var holder: Dictionary = bikes[bike_id] if home[0] == "bike" else items[item_on(bike_id, str(home[0]))]
			var field := str(home[1])
			if key == "chain":
				holder["slack"] = BikeBuild.new().tune_default("chain") if action.get("reset", false) else \
					clampf(float(action["value"]), BikeBuild.TUNE_LIMITS["chain"][0], BikeBuild.TUNE_LIMITS["chain"][1])
			elif action.get("reset", false):
				if holder.has("tune"):
					holder["tune"].erase(field)
			else:
				var r := build_of(bike_id).tune_range(key)
				if not holder.has("tune"):
					holder["tune"] = {}
				holder["tune"][field] = clampf(float(action["value"]), r.x, r.y)
		"lighten":
			var it: Dictionary = items[int(action["item"])]
			var kg := float(PartsDB.get_part(str(it["part"])).get("mass", 0.0)) * BikeBuild.lighten_cut(str(it["part"]))
			it["lightened"] = true
			it["wear"] = minf(1.0, float(it["wear"]) + LIGHTEN_WEAR)
			text = "Drilled and trimmed the %s: %.1f kg lighter, but a little weaker" % [item_title(int(action["item"])), kg]
		"dyno_run":
			var build := build_of(bike_id)
			var run := build.dyno_run()
			var d: Dictionary = bikes[bike_id].get("dyno", {"n": 0, "runs": []})
			var runs: Array = d.get("runs", [])
			d["n"] = int(d.get("n", 0)) + 1
			run["n"] = d["n"]
			runs.append(run)
			while runs.size() > 2:
				runs.pop_front()
			d["runs"] = runs
			bikes[bike_id]["dyno"] = d
			_dyno_busy_until = Time.get_ticks_msec() + int(DynoRoom.run_time(build) * 1000.0)
			# A run burns a splash of petrol.
			var tank := item_on(bike_id, "tank")
			if tank != 0 and items[tank].has("fluid"):
				items[tank]["fluid"]["litres"] = maxf(0.0, float(items[tank]["fluid"]["litres"]) - 0.05)
			text = "Dyno run %d on %s..." % [d["n"], bikes[bike_id]["name"]]
		"set_stand":
			bikes[bike_id]["stand"] = str(action["stand"])
			text = "Up on the centre stand" if action["stand"] == "centre" else "Down on the side stand"
		"pour", "drain":
			var can: Dictionary = items[held_by(peer)]
			var into: Dictionary = items[int(action["item"])]
			var moved := _transfer(can, into) if a == "pour" else _transfer(into, can)
			var what: String = PartsDB.KIND_NAMES[PartsDB.fluid_kind(into["part"])].to_lower()
			text = ("Poured in %.2f L of %s" if moved < 1.0 else "Poured in %.1f L of %s") % [moved, what] if a == "pour" \
				else ("Drained %.2f L of %s" if moved < 1.0 else "Drained %.1f L of %s") % [moved, what]
		"tip":
			var can: Dictionary = items[held_by(peer)]
			can["fluid"]["litres"] = 0.0
			can["fluid"]["age"] = 0.0
			text = "Tipped it away for recycling"
		"wash":
			var n := 0
			for id in action["items"]:
				if items.has(int(id)) and not items[int(id)].get("boxed", false) and items[int(id)]["dirt"] > 0.0:
					items[int(id)]["dirt"] = maxf(0.0, items[int(id)]["dirt"] - JET_CLEAN)
					if items[int(id)]["dirt"] == 0.0:
						n += 1
			c["cleaned"] = int(c.get("cleaned", 0)) + n
		"order":
			var id := _random_bike(free_bay(Workshop.BAY_COUNT))
			text = "%s has been delivered to bay %d" % [bikes[id]["name"], bikes[id]["bay"] + 1]
		"radio":
			radio = {"on": bool(action.get("on", radio["on"])), "station": int(action.get("station", radio["station"]))}
			text = "Radio: %s" % station_name() if radio["on"] else "Radio off"
		"status":
			c["tool"] = str(action.get("tool", c.get("tool", "")))
			c["activity"] = str(action.get("activity", "")).left(60)
		"ride":
			var bike := int(c.get("riding", 0))
			if bikes.has(bike):
				_wear_from_ride(bike, action)
			c["km"] = float(c.get("km", 0.0)) + clampf(float(action.get("km", 0.0)), 0.0, 5.0)
			c["top_kmh"] = maxf(float(c.get("top_kmh", 0.0)), clampf(float(action.get("top_kmh", 0.0)), 0.0, 400.0))
			c["kmh"] = clampf(float(action.get("kmh", 0.0)), 0.0, 400.0)
	if text != "":
		_tell(peer, text, true)
	_mark_dirty()
	changed.emit()


## Pours as much as fits from one fluid holder into another and returns the litres moved.
## The mix takes the type of whichever there's more of, and its age is the average.
func _transfer(from: Dictionary, into: Dictionary) -> float:
	var src: Dictionary = from["fluid"]
	var dst: Dictionary = into["fluid"]
	var room := PartsDB.fluid_capacity(into["part"]) - float(dst["litres"])
	var moved := minf(float(src["litres"]), maxf(room, 0.0))
	if moved <= 0.0:
		return 0.0
	var before := float(dst["litres"])
	var src_type := str(src["type"]) if str(src["type"]) != "" else str(from["part"])
	if before <= 0.001 or moved >= before:
		dst["type"] = src_type
	dst["age"] = (float(dst.get("age", 0.0)) * before + float(src.get("age", 0.0)) * moved) / (before + moved)
	dst["litres"] = before + moved
	src["litres"] = float(src["litres"]) - moved
	if src["litres"] <= 0.0005:
		src["litres"] = 0.0
		if PartsDB.get_part(from["part"]).get("empty", false):
			src["type"] = ""
	return moved


## How long pouring between two holders takes, in seconds.
func pour_time(from: Dictionary, into: Dictionary) -> float:
	var room := PartsDB.fluid_capacity(into["part"]) - float(into["fluid"]["litres"])
	var moved := minf(float(from["fluid"]["litres"]), maxf(room, 0.0))
	return clampf(moved / float(POUR_RATE.get(PartsDB.fluid_kind(into["part"]), 1.0)), 0.6, 5.0)


## Leaves a bike standing where it was let go: snapped onto the paddock stand of a bay it's in,
## or on its own stand.
func _park(bike_id: int) -> void:
	var bike: Dictionary = bikes[bike_id]
	var rig := DynoRoom.rig_transform()
	if (bike["xf"] as Transform3D).origin.distance_to(rig.origin) < 1.0 and (dyno_bike() == 0 or dyno_bike() == bike_id):
		# Rolled onto the dyno: square on the drum and strapped down.
		bike["xf"] = rig
		bike["stand"] = ""
		return
	var bay := _bay_near(bike["xf"], bike_id)
	if bay >= 0:
		bike["bay"] = bay
		bike["xf"] = Workshop.bay_transform(bay)
		bike["stand"] = ""
	elif on_paddock(bike_id):
		bike["stand"] = ""
	else:
		bike["stand"] = _rest_stand(bike_id)


## What a ride does to a bike: road dirt on its parts, petrol used, oil and brake fluid aging,
## and engine wear, which climbs steeply when the oil is low or worn out.
func _wear_from_ride(bike_id: int, action: Dictionary) -> void:
	var km := clampf(float(action.get("km", 0.0)), 0.0, 5.0)
	var dirty := clampf(float(action.get("dirt_km", 0.0)), 0.0, 5.0)
	var build := build_of(bike_id)
	for slot in PartsDB.SLOTS:
		var id := item_on(bike_id, slot)
		if id != 0 and dirty > 0.0:
			items[id]["dirt"] = minf(1.0, float(items[id]["dirt"]) + dirty * ROAD_DIRT * float(DIRT_EXPOSURE.get(slot, 0.4)))
		if id != 0 and items[id].get("lightened", false):
			items[id]["wear"] = minf(1.0, float(items[id]["wear"]) + km * 0.0003)
	# Tyres wear, faster at the wrong pressure.
	for side in ["front", "rear"]:
		var tyre := item_on(bike_id, side + "_tyre")
		if tyre != 0:
			items[tyre]["wear"] = minf(1.0, float(items[tyre]["wear"]) + km * TYRE_WEAR * float(build.tyre_wear[side]))
	var tank := item_on(bike_id, "tank")
	if tank != 0 and items[tank].has("fluid"):
		var f: Dictionary = items[tank]["fluid"]
		f["litres"] = maxf(0.0, float(f["litres"]) - clampf(float(action.get("fuel", 0.0)), 0.0, 2.0))
	var block := item_on(bike_id, "engine")
	if block != 0 and items[block].has("fluid"):
		var oil: Dictionary = items[block]["fluid"]
		oil["age"] = minf(1.0, float(oil.get("age", 0.0)) + km / 1500.0)
		var level := float(oil["litres"]) / maxf(PartsDB.fluid_capacity(items[block]["part"]), 0.1)
		var protection := float(PartsDB.get_part(str(oil["type"])).get("protection", 0.7)) * lerpf(1.0, 0.55, float(oil["age"]))
		var rate := 0.0005 * (1.6 - protection)
		if level < 0.5:
			rate = lerpf(0.03, rate, level / 0.5)
		items[block]["wear"] = minf(1.0, float(items[block]["wear"]) + km * rate * build.engine_stress)
	var chain := item_on(bike_id, "chain")
	if chain != 0:
		var spec := PartsDB.get_part(items[chain]["part"])
		var lube := float(items[chain].get("lube", 1.0))
		var life := float(spec.get("lube_life", 400.0)) * float(PartsDB.get_part(str(items[chain].get("lube_type", ""))).get("lasts", 1.0))
		# Muck and rain wash the lube off faster off-road; a dry chain stretches and wears quicker.
		items[chain]["lube"] = maxf(0.0, lube - (km + dirty) / life)
		var stretch := float(spec.get("stretch", 8.0)) * (1.0 + (1.0 - lube) * 2.0) * (1.0 + float(items[chain]["wear"]))
		items[chain]["slack"] = minf(90.0, float(items[chain].get("slack", CHAIN_SLACK_SET)) + km * stretch / 1000.0 * 12.0)
		items[chain]["wear"] = minf(1.0, float(items[chain]["wear"]) + km * 0.0004 * (1.0 + (1.0 - lube) * 3.0))
	for slot in ["front_master", "rear_master"]:
		var m := item_on(bike_id, slot)
		if m != 0 and items[m].has("fluid"):
			items[m]["fluid"]["age"] = minf(1.0, float(items[m]["fluid"].get("age", 0.0)) + km / 4000.0)


# ---------------------------------------------------------------------------- whiteboard

## Draws or writes on the whiteboard. Your own marks show straight away; the host checks them
## and passes them on to everyone else as you go.
func board_request(op: Dictionary) -> void:
	if not is_authority() and str(op.get("a", "")) in ["board_draw", "board_text"]:
		var mine := BoardData.clean(op, me(), str(crew.get(me(), {}).get("name", Settings.player_name)))
		if not mine.is_empty() and BoardData.apply(board, mine):
			board_changed.emit()
	request(op)


func _board_apply(peer: int, action: Dictionary) -> void:
	var op := BoardData.clean(action, peer, str(crew.get(peer, {}).get("name", "Someone")))
	var a := str(op.get("a", ""))
	match a:
		"board_draw", "board_text":
			if not BoardData.apply(board, op):
				return
			# The finished mark goes back to its author too, in case a whole-shed sync
			# crossed with it on the way and wiped their copy.
			var done: bool = a == "board_text" or op["done"]
			_board_send(op, 0 if done else peer)
			if done:
				var gone := BoardData.tidy(board, int(op["id"]))
				if not gone.is_empty():
					var removal := {"a": "board_remove", "ids": gone}
					BoardData.apply(board, removal)
					_board_send(removal)
		"board_undo":
			var last := BoardData.last_of(board, peer)
			if last == 0:
				_tell(peer, "Nothing of yours on the board to undo.", false)
				return
			var removal := {"a": "board_remove", "ids": [last]}
			BoardData.apply(board, removal)
			_board_send(removal)
		"board_clear":
			BoardData.apply(board, op)
			_board_send({"a": "board_clear"})
			_tell(peer, "Whiteboard wiped clean.", true)
		_:
			return
	board_changed.emit()


## Passes a board op on to every other player, except the one who drew it (they already have it).
func _board_send(op: Dictionary, skip := 0) -> void:
	if not Net.is_online():
		return
	for p in multiplayer.get_peers():
		if p != skip:
			_board_op.rpc_id(p, op)


@rpc("authority", "call_remote", "reliable")
func _board_op(op: Dictionary) -> void:
	if BoardData.apply(board, op):
		board_changed.emit()


func _tell(peer: int, text: String, ok: bool) -> void:
	if peer == me():
		feedback.emit(text, ok)
	elif Net.is_online():
		_feedback.rpc_id(peer, text, ok)


@rpc("authority", "call_remote", "reliable")
func _feedback(text: String, ok: bool) -> void:
	feedback.emit(text, ok)


@rpc("authority", "call_remote", "reliable")
func _ping(peer: int, d: Dictionary) -> void:
	pinged.emit(peer, d)


func _bump(c: Dictionary, key: String) -> void:
	c[key] = int(c.get(key, 0)) + 1


func _move(item_id: int, at: String, ref) -> void:
	items[item_id]["at"] = at
	items[item_id]["ref"] = ref


## Takes a part off a bike (whatever is mounted on it stays put) and puts it somewhere.
func _detach(bike_id: int, slot: String, at: String, ref) -> int:
	var item_id: int = bikes[bike_id]["slots"][slot]
	bikes[bike_id]["slots"][slot] = 0
	bikes[bike_id]["bolted"][slot] = false
	_move(item_id, at, ref)
	return item_id


func _erase_item(item_id: int) -> void:
	if is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := engine_item(item_id, slot)
			if sub != 0:
				items.erase(sub)
	items.erase(item_id)


func _free_spot() -> String:
	for spot in SPOTS:
		if spot.begins_with("bench") and item_at_spot(spot) == 0:
			return spot
	return "bench_0"


func _new_item(part: String, rust: float, dirt: float, wear: float, color = null) -> int:
	var id := _next_id
	_next_id += 1
	var k := PartsDB.kind_of(part)
	items[id] = {"id": id, "part": part, "kind": k, "rust": rust, "dirt": dirt, "wear": wear,
		"color": PartsDB.default_color(part) if color == null else color, "finish": "", "boxed": false, "at": "spot", "ref": ""}
	if k == "engine":
		items[id]["slots"] = {}
		items[id]["bolted"] = {}
	if k == "chain":
		items[id]["slack"] = CHAIN_SLACK_SET
		items[id]["lube"] = 1.0
		items[id]["lube_type"] = ""
	if PartsDB.fluid_kind(part) != "":
		var full: bool = PartsDB.is_fluid(part) and not PartsDB.get_part(part).get("empty", false)
		items[id]["fluid"] = {"type": part if full else "", "litres": PartsDB.fluid_capacity(part) if full else 0.0, "age": 0.0}
	return id


func _aged_item(part: String, age: float, color = null) -> int:
	var rust := clampf(age * _rng.randf_range(0.4, 1.2), 0.0, 1.0)
	var dirt := clampf(age * _rng.randf_range(0.8, 1.4), 0.0, 1.0)
	var wear := clampf(age * _rng.randf_range(0.2, 1.0), 0.0, 1.0)
	return _new_item(part, rust, dirt, wear, color)


## Adds a bike to a bay. `age` 0..1 sets how rusty, dirty and worn its parts are.
func _new_bike(parts: Dictionary, bay: int, bike_name: String, age: float, paint = null) -> int:
	var id := _next_id
	_next_id += 1
	parts = PartsDB.sanitize_build(parts)
	var paint_color: Color = PAINTS[_rng.randi() % PAINTS.size()] if paint == null else paint
	var bike := {"id": id, "name": bike_name, "paint": paint_color, "slots": {}, "bolted": {},
		"rider": 0, "bay": bay, "xf": Workshop.bay_transform(bay), "original": parts.duplicate(), "stand": "", "pusher": 0}
	bikes[id] = bike
	var cond := {}
	for slot in PartsDB.BIKE_SLOTS:
		if parts[slot] == "none":
			bike["slots"][slot] = 0
			bike["bolted"][slot] = false
			continue
		var item_id := _aged_item(parts[slot], age, paint_color if slot == "tank" else null)
		_move(item_id, "bike", id)
		bike["slots"][slot] = item_id
		bike["bolted"][slot] = true
		cond[slot] = condition_of(items[item_id])
	var block: Dictionary = items[bike["slots"]["engine"]]
	for slot in PartsDB.ENGINE_SLOTS:
		var item_id := _aged_item(parts[slot], age)
		_move(item_id, "engine", block["id"])
		block["slots"][slot] = item_id
		block["bolted"][slot] = true
		cond[slot] = condition_of(items[item_id])
	_fill_fluids(id, age)
	for slot in ["tank", "engine", "front_master", "rear_master"]:
		cond[slot] = condition_of(items[item_on(id, slot)])
	bike["original_cond"] = cond
	bike["delivered"] = BikeBuild.new(parts, cond).summary()
	return id


## A bike started from a bare frame on a bay's paddock stand.
func _empty_bike(frame_id: int, bay: int) -> int:
	var id := _next_id
	_next_id += 1
	var builds := 1
	for b in bikes.values():
		if str(b["name"]).begins_with("Scratch build"):
			builds += 1
	var parts: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	parts["frame"] = items[frame_id]["part"]
	var bike := {"id": id, "name": "Scratch build %d" % builds, "paint": items[frame_id]["color"], "slots": {}, "bolted": {},
		"rider": 0, "bay": bay, "xf": Workshop.bay_transform(bay), "original": parts, "stand": "", "pusher": 0,
		"original_cond": {}, "delivered": BikeBuild.new(parts, {}).summary()}
	for slot in PartsDB.BIKE_SLOTS:
		bike["slots"][slot] = 0
		bike["bolted"][slot] = false
	bikes[id] = bike
	bike["slots"]["frame"] = frame_id
	bike["bolted"]["frame"] = true
	_move(frame_id, "bike", id)
	return id


## Project bikes come with whatever fluids were left in them: the older the bike, the less
## there is and the older it is.
func _fill_fluids(bike_id: int, age: float) -> void:
	var fills := {"tank": ["unleaded_95", _rng.randf_range(0.05, 0.5) * (1.0 - age * 0.6)],
		"engine": ["mineral_20w50" if age > 0.5 else "semi_10w40", _rng.randf_range(0.55, 1.0) * (1.0 - age * 0.4)],
		"front_master": ["dot4", _rng.randf_range(0.5, 1.0) * (1.0 - age * 0.3)],
		"rear_master": ["dot4", _rng.randf_range(0.5, 1.0) * (1.0 - age * 0.3)]}
	var chain := item_on(bike_id, "chain")
	if chain != 0:
		items[chain]["slack"] = snappedf(CHAIN_SLACK_SET + _rng.randf_range(5.0, 45.0) * (0.3 + age), 1.0)
		items[chain]["lube"] = clampf(_rng.randf_range(0.0, 0.6) * (1.0 - age), 0.0, 1.0)
	for slot in fills:
		var id := item_on(bike_id, slot)
		if id == 0:
			continue
		items[id]["fluid"] = {"type": fills[slot][0], "litres": snappedf(PartsDB.fluid_capacity(items[id]["part"]) * fills[slot][1], 0.01),
			"age": clampf(age * _rng.randf_range(0.9, 1.3), 0.0, 1.0)}


func _random_bike(bay: int) -> int:
	var parts := {}
	var pick := {}
	for slot in PartsDB.SLOTS:
		var k: String = PartsDB.SLOT_KIND[slot]
		# A random bike wears a matching pair of tyres; everything else is picked per slot.
		var key: String = k if k == "tyre" else slot
		if not pick.has(key):
			var options: Array = PartsDB.by_kind[k].duplicate()
			if PartsDB.is_optional(slot):
				options.append("none")
			pick[key] = options[_rng.randi() % options.size()]
		parts[slot] = pick[key]
	var bike_name: String = BIKE_NAMES[_rng.randi() % BIKE_NAMES.size()]
	return _new_bike(parts, bay, bike_name, _rng.randf_range(0.35, 0.9))


func _add_crew(peer: int, player_name: String) -> void:
	if crew.has(peer):
		crew[peer]["name"] = player_name
		return
	crew[peer] = {"name": player_name, "tool": "hands", "activity": "", "riding": 0, "fitted": 0, "removed": 0,
		"cleaned": 0, "repaired": 0, "painted": 0, "km": 0.0, "top_kmh": 0.0, "kmh": 0.0, "slot": crew.size()}


func _on_player_joined(id: int, info: Dictionary) -> void:
	if not active or not is_authority():
		return
	_add_crew(id, str(info.get("name", "Rider")))
	_mark_dirty()
	_sync.rpc_id(id, _snapshot())
	changed.emit()


func _on_player_left(id: int) -> void:
	if not active or not is_authority():
		return
	var held := held_by(id)
	if held != 0:
		_move(held, "spot", _free_spot())
	var bike_id := riding(id)
	if bike_id != 0:
		bikes[bike_id]["rider"] = 0
	var pushing := moving(id)
	if pushing != 0:
		furniture[pushing]["mover"] = 0
	var wheeling := pushing_bike(id)
	if wheeling != 0:
		bikes[wheeling]["pusher"] = 0
		_park(wheeling)
	crew.erase(id)
	_mark_dirty()
	changed.emit()


# ---------------------------------------------------------------------------- syncing

func _mark_dirty() -> void:
	_dirty = true


## The whole shed. The regular syncs leave the whiteboard out: its marks go out one by one
## as they're drawn (_board_op), and whole only to players joining.
func _snapshot(with_board := true) -> Dictionary:
	var state := {"bikes": bikes, "items": items, "crew": crew, "furniture": furniture, "radio": radio, "next": _next_id,
		"door": door_open, "lights": lights_on}
	if with_board:
		state["board"] = board
	return state


@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	bikes = state.get("bikes", {})
	items = state.get("items", {})
	crew = state.get("crew", {})
	furniture = state.get("furniture", {})
	radio = state.get("radio", radio)
	door_open = bool(state.get("door", true))
	lights_on = bool(state.get("lights", true))
	_next_id = int(state.get("next", 1))
	if state.get("board", null) is Dictionary:
		board = state["board"]
		board_changed.emit()
	active = true
	changed.emit()


func _process(delta: float) -> void:
	if not active or not is_authority():
		return
	# Parts washers slowly clean whatever is in them.
	for id in furniture:
		if furniture[id]["kind"] != "washer":
			continue
		var rate := float(Equipment.get_model(str(furniture[id]["model"])).get("rate", 0.18))
		for spot in furniture_spots(id):
			var washing := item_at_spot(spot)
			if washing != 0 and items[washing]["dirt"] > 0.0 and not items[washing].get("boxed", false):
				items[washing]["dirt"] = maxf(0.0, items[washing]["dirt"] - rate * delta)
				_mark_dirty()
				if items[washing]["dirt"] == 0.0:
					changed.emit()
	_sync_timer -= delta
	if _dirty and _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_dirty = false
		if Net.is_online():
			_sync.rpc(_snapshot(false))
		changed.emit()
