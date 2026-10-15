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
## A picture or poster print's data arrived (see share_blob).
signal blob_arrived(id: int)

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
	"horn": 0.6, "ecu": 0.2, "panniers": 0.6, "top_box": 0.3, "fog_lights": 0.6,
	"tail": 0.9, "fairing": 0.4, "mirrors": 0.2}
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
## The tyre slot that goes with each wheel slot: a wheel comes off the bike with its tyre still on.
const WHEEL_TYRE := {"front_wheel": "front_tyre", "rear_wheel": "rear_tyre"}
const TYRE_REMOVE_TIME := 2.5   # seconds to lever a tyre off on the tyre changer
## How fast a badly seated bead lets a tyre down, in bar per km at the worst.
const BEAD_LEAK := 0.02

## bike id -> {id, name, paint, slots{bike slot: item id or 0}, bolted{slot: bool}, rider, bay, xf, original, delivered,
## stand ("" upright on its wheels or the bay's paddock stand, "side", "centre" or "down" when it has fallen over),
## pusher (peer wheeling it about, or 0), tune{map, ignition, limiter}, dyno{n, runs: the last two dyno runs}}
var bikes := {}
## item id -> {id, part, kind, rust, dirt, wear, color, finish, boxed, at, ref}, where
## at is "bike", "engine", "held", "spot", "floor" (ref is then the Transform3D it was put down at)
## or "wheel" (a tyre on a wheel that's off the bike: ref is the wheel's id, and the wheel carries
## tyre: the tyre's id). A tyre fitted on the tyre changer carries bead: how well it was seated, 0..1.
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
## The business's own account, in pounds (see Money: a new shed opens with START_FUNDS).
var garage_money := 0
## Garage upgrades bought (GarageUpgrades): upgrade id -> true.
var upgrades := {}
## The looks chosen for the finishes bought (GarageUpgrades.OPTIONS): upgrade id -> {option: choice}.
## A finish with none here looks as it always did.
var looks := {}
const MAX_GARAGE_MONEY := 100000000
## Everything else about the business's money: wage cut, owner, ledger, loans (see Money.defaults).
var bank := Money.defaults()
var _clock_hours := -1.0       # host: the clock last frame, to see midnight pass
## Customers at reception and the jobs taken on for them (see Contracts).
var contracts := {}
var lights_on := true     # the shed's strip lights
## The side rooms' own lights, each with a switch by its door: room name -> on.
var room_lights := {"paint": true, "storage": true}
## (The sales office's "sales" switch is saved with them; it starts on, so it isn't listed above.)
const LIT_ROOMS: Array[String] = ["paint", "storage", "sales"]
var stations: Array = []    # [{name, genre, url}] from data/radio.json
var board := BoardData.empty()   # what's drawn and written on the shed whiteboard
## Bigger bits of data that go out in chunks (see share_blob): the pictures players put on the
## whiteboard (WebP) and the whiteboard drawings turned into posters. blob id -> PackedByteArray.
var blobs := {}
## Whiteboard drawings saved as posters to order from the parts computer:
## design id -> {id, name, by, blob (its marks, compressed), imgs (blob ids of its pictures)}.
var posters := {}
## What each screen is tuned to: screen key (see TvChannels) -> {ch: channel id, rider: the peer
## its live channel follows, 0 for whoever is out first}. Screens not in here show their home channel.
var screens := {}
## The dyno room's kit (see DynoRoom): the extraction hose ("hook", "bike" or "held" with
## hose_by the peer holding it), the cooling fan and the room's own lights (on/off), the four
## straps on the rig (front left, front right, rear left, rear right), who is wearing the ear
## defenders (0: on their hook), how hot the engine on the rig is (0..1) and how much exhaust
## haze hangs in the room (0..1).
var dyno := dyno_defaults()
## Bikes saved as blueprints in geometry mode, to build again: blueprint id -> {id, name, parts
## {slot: part id or "none"}, colors {slot: {color, finish}}, paint, geo (its parts' fit, see
## GeoGizmo), from (the bike it was taken from)}.
var blueprints := {}
## Blueprint builds waiting for a frame: bay -> a copy of the blueprint (bp: its id, bay, ordered
## {slot: item id} for parts already ordered). Once a frame goes on the bay's stand the copy
## moves onto that bike as its "blueprint", and goes when the bike is built.
var holograms := {}
const MAX_BLUEPRINTS := 40

var _next_id := 1
var _dirty := false
var _sync_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _dyno_busy_until := 0      # msec: the host won't start another dyno run until this one is done
var _washer_by := {}           # item id -> peer who put it in a parts washer, for their XP
## Distinct parts taken off a bike before its rebuild counts as a build (see _milestones).
const BUILD_STRIP := 5
## Parts on a free surface (see surface): how far one may hang over the edge, and how much two
## may touch before they count as in each other's way.
const SURFACE_OVERHANG := 0.06
const SURFACE_GAP := 0.005


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
	garage_money = Money.START_FUNDS
	bank = Money.defaults()
	Money.log_entry(bank, Money.START_FUNDS, "Opening funds", garage_money)
	Money._mark_milestones(bank, garage_money)
	contracts = Contracts.empty()
	upgrades = {}
	looks = {}
	door_open = true
	lights_on = true
	room_lights = {"paint": true, "storage": true}
	screens = {}
	blueprints = {}
	holograms = {}
	dyno = dyno_defaults()
	_dyno_busy_until = 0
	items.clear()
	crew.clear()
	board = BoardData.empty()
	_clear_prints()
	board_changed.emit()
	_next_id = 1
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	active = true
	_add_crew(me(), player_name)
	_new_bike({"frame": "steel_backbone", "fork": "enduro_usd", "shock": "enduro_mono", "front_wheel": "spoked_21",
		"rear_wheel": "spoked_18", "front_tyre": "knobbly_mx_90", "rear_tyre": "knobbly_mx", "front_disc": "wave_270",
		"rear_disc": "wave_270", "front_caliper": "twin_piston", "rear_caliper": "single_piston", "front_pads": "sintered",
		"rear_pads": "sintered", "front_master": "axial_12", "rear_master": "axial_14", "tank": "enduro_12",
		"saddle": "enduro_seat", "handlebars": "mx_tall", "dashboard": "lcd_basic", "engine": "single_450",
		"exhaust": "stock_muffler", "final_drive": "mx_13_52", "head": "four_valve", "fuel": "flat_slide_carbs",
		"air_filter": "foam_filter", "oil_filter": "paper_oil", "spark_plugs": "copper_plugs", "cooling": "single_radiator",
		"gearbox": "six_wide_enduro"}, 0, "Rusty Ranger", 0.75, PAINTS[2])
	var cafe := _new_bike({"frame": "steel_cradle", "fork": "classic_conventional", "shock": "twin_shock",
		"front_wheel": "wire_19_chrome", "rear_wheel": "spoked_18", "front_tyre": "vintage_ribbed_100", "rear_tyre": "vintage_ribbed",
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
	_new_bike({"frame": "alu_twin_spar", "fork": "usd_sport", "shock": "sport_mono", "front_wheel": "cast_17_front",
		"rear_wheel": "cast_17", "front_tyre": "sport_road_120", "rear_tyre": "sport_road", "front_disc": "floating_310",
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
			_put_on_bench(id)
	for id in furniture:
		furniture[id]["mover"] = 0
		# Equipment renamed since the save was made (the wall TVs grew): the model it is now.
		furniture[id]["model"] = Equipment.current_id(str(furniture[id].get("model", "")))
	# Shelves from before parts could go anywhere on them: what sat in a numbered place stays
	# just where it was, now as a part put down on that board.
	for id in items:
		if items[id]["at"] == "spot" and not (items[id].get("place") is Transform3D) and spot_role(str(items[id]["ref"])) == "shelf":
			items[id]["place"] = item_place(id)
	# Nobody is holding the hose or wearing the ear defenders in a new session.
	if dyno["hose"] == "held":
		dyno["hose"] = "hook"
	dyno["hose_by"] = 0
	dyno["headphones"] = 0
	# Peer ids don't carry over between sessions, so live channels follow whoever rides first.
	for key in screens.keys():
		if not (screens[key] is Dictionary) or not TvChannels.screen_exists(str(key)):
			screens.erase(key)
		else:
			screens[key]["rider"] = 0
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
	_add_new_slots()
	ensure_fixtures()
	_mark_dirty()
	changed.emit()


## Sheds saved before tail units, fairings and mirrors: every bike gets the tail unit that suits
## it (fitted and bolted where its frame is on, else on the bench), in the same state as its
## frame, and empty fairing and mirror slots. Blueprints and holograms get the tail on their plan.
func _add_new_slots() -> void:
	for id in bikes:
		var bike: Dictionary = bikes[id]
		var original: Dictionary = bike.get("original", {})
		if not original.has("tail"):
			original["tail"] = PartsDB.fitting_tail(PartsDB.sanitize_build(original.duplicate()))
		for slot in ["fairing", "mirrors"]:
			if not original.has(slot):
				original[slot] = "none"
			if not bike["slots"].has(slot):
				bike["slots"][slot] = 0
				bike["bolted"][slot] = false
		if bike["slots"].has("tail"):
			continue
		var frame := int(bike["slots"].get("frame", 0))
		var like: Dictionary = items.get(frame, {"rust": 0.3, "dirt": 0.3, "wear": 0.2})
		var tail := _new_item(str(original["tail"]), float(like["rust"]), float(like["dirt"]), float(like["wear"]))
		if frame != 0:
			_move(tail, "bike", id)
			bike["slots"]["tail"] = tail
			bike["bolted"]["tail"] = true
		else:
			bike["slots"]["tail"] = 0
			bike["bolted"]["tail"] = false
			_put_on_bench(tail)
	var plans: Array = blueprints.values() + holograms.values()
	for id in bikes:
		if bikes[id].get("blueprint") is Dictionary:
			plans.append(bikes[id]["blueprint"])
	for plan in plans:
		if plan is Dictionary and plan.get("parts") is Dictionary and not plan["parts"].has("tail"):
			plan["parts"]["tail"] = PartsDB.fitting_tail(PartsDB.sanitize_build(plan["parts"].duplicate()))


func join_remote() -> void:
	garage_money = 0
	bank = Money.defaults()
	contracts = Contracts.empty()
	upgrades = {}
	looks = {}
	board = BoardData.empty()
	_clear_prints()
	board_changed.emit()
	bikes.clear()
	furniture.clear()
	radio = {"on": false, "station": 0}
	screens = {}
	blueprints = {}
	holograms = {}
	dyno = dyno_defaults()
	_dyno_busy_until = 0
	items.clear()
	crew.clear()
	active = true


func stop() -> void:
	garage_money = 0
	bank = Money.defaults()
	_clock_hours = -1.0
	contracts = Contracts.empty()
	upgrades = {}
	looks = {}
	_washer_by.clear()
	board = BoardData.empty()
	_clear_prints()
	board_changed.emit()
	furniture.clear()
	radio = {"on": false, "station": 0}
	screens = {}
	blueprints = {}
	holograms = {}
	dyno = dyno_defaults()
	_dyno_busy_until = 0
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
		if float(item.get("lighten_extra", 0.0)) > 0.0:
			cond["lighten_extra"] = float(item["lighten_extra"])
	if item.has("bead"):
		cond["bead"] = item["bead"]
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
	var tune := tune_of(bike_id)
	if float(bike.get("tune_reach", 0.0)) > 0.0:
		# Tuned by someone with Fine Tuning: the map, ignition and limiter go further.
		tune["reach"] = float(bike["tune_reach"])
	return BikeBuild.new(parts, cond, tune)


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


static func dyno_defaults() -> Dictionary:
	return {"hose": "hook", "hose_by": 0, "fan": false, "lights": true, "straps": [false, false, false, false],
		"headphones": 0, "heat": 0.0, "haze": 0.0}


## Whether every strap on the rig is done up.
func strapped() -> bool:
	return dyno_bike() != 0 and (dyno["straps"] as Array).all(func(on): return bool(on))


## How many of the rig's straps are done up.
func straps_done() -> int:
	return (dyno["straps"] as Array).count(true)


## Who is carrying the dyno's exhaust hose about, or 0.
func hose_holder() -> int:
	return int(dyno.get("hose_by", 0)) if dyno.get("hose", "hook") == "held" else 0


## Whether `peer` has the ear defenders on.
func wearing_headphones(peer: int) -> bool:
	return peer != 0 and int(dyno.get("headphones", 0)) == peer


## Why `peer` can't do a dyno room job, or "".
func _dyno_check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var on_rig := dyno_bike()
	match a:
		"dyno_strap":
			var point := int(action.get("point", -1))
			if point < 0 or point >= 4:
				return "There's no strap there."
			if on_rig == 0:
				return "Wheel a bike onto the rig first."
			if bikes[on_rig].get("pusher", 0) != 0:
				return "Let go of the bike first."
			if hose_holder() == peer:
				return "Your hands are full of exhaust hose."
		"dyno_hose":
			var to := str(action.get("to", ""))
			var now := str(dyno.get("hose", "hook"))
			match to:
				"held":
					if now == "held":
						return "Someone's already got the hose."
					if held_by(peer) != 0:
						return "Put the part down first."
					if pushing_bike(peer) != 0 or moving(peer) != 0:
						return "Let go of what you're moving first."
				"bike":
					if hose_holder() != peer:
						return "Take the exhaust hose off its hook first."
					if on_rig == 0:
						return "Wheel a bike onto the rig first."
					if item_on(on_rig, "exhaust") == 0:
						return "There's no exhaust fitted to put it on."
				"hook":
					if hose_holder() != peer:
						return "You're not holding the hose."
				_:
					return "Put it where?"
		"dyno_fan", "dyno_lights":
			pass
		"dyno_headphones":
			var wearer := int(dyno.get("headphones", 0))
			if wearer != 0 and wearer != peer:
				return "Someone's wearing them."
	return ""


## Does a dyno room job (already checked) and says what happened.
func _dyno_apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	match a:
		"dyno_strap":
			var point := int(action["point"])
			var straps: Array = dyno["straps"]
			straps[point] = not bool(straps[point])
			if straps[point]:
				_xp(peer, "dyno_strap", 1.0, "strap:%d" % point)
			if straps.all(func(on): return bool(on)):
				return "Strapped down: %s is ready for a run." % bikes[dyno_bike()]["name"]
			return ("Strap done up (%d of 4)" if straps[point] else "Strap undone (%d of 4 done up)") % straps.count(true)
		"dyno_hose":
			var to := str(action["to"])
			var was := str(dyno["hose"])
			dyno["hose"] = to
			dyno["hose_by"] = peer if to == "held" else 0
			if to == "bike":
				_xp(peer, "dyno_hose", 1.0, "bike:%d" % dyno_bike())
				return "Extraction hose on the exhaust. The fumes go outside."
			if to == "held":
				return "Got the extraction hose. Hold the work button on the bike's exhaust to fit it." if was == "hook" \
					else "Took the hose off the exhaust."
			return "Hose back on its hook."
		"dyno_fan":
			dyno["fan"] = bool(action.get("on", not bool(dyno["fan"])))
			return "Cooling fan %s" % ("on" if dyno["fan"] else "off")
		"dyno_lights":
			dyno["lights"] = bool(action.get("on", not bool(dyno["lights"])))
			return "Dyno room lights %s" % ("on" if dyno["lights"] else "off")
		"dyno_headphones":
			var wearing := int(dyno["headphones"]) == peer
			dyno["headphones"] = 0 if wearing else peer
			return "Hung the ear defenders back up." if wearing else "Ear defenders on: the dyno's roar is muffled."
	return ""


## Keeps the dyno kit straight when the bike leaves the rig (or the hose holder has gone).
func _tidy_dyno() -> void:
	if dyno_bike() == 0:
		dyno["straps"] = [false, false, false, false]
		if dyno["hose"] == "bike":
			dyno["hose"] = "hook"
	if dyno["hose"] == "held" and not crew.has(int(dyno.get("hose_by", 0))):
		dyno["hose"] = "hook"
		dyno["hose_by"] = 0
	if int(dyno.get("headphones", 0)) != 0 and not crew.has(int(dyno["headphones"])):
		dyno["headphones"] = 0


const DYNO_HEAT_FAN := 0.08      # how much hotter the engine gets in one run with the fan on
const DYNO_HEAT_NO_FAN := 0.4    # and without it
const DYNO_HEAT_POWER := 0.07    # power lost at the top of the sweep, fully heat soaked


## The engine's temperature on the dyno, in degrees C, from its heat 0..1.
static func dyno_temp(heat: float) -> float:
	return 85.0 + heat * 45.0


## A hot engine fades as the sweep goes on: power and torque fall away towards the limiter.
static func _heat_run(run: Dictionary, heat: float) -> void:
	run["heat"] = heat
	run["temp_c"] = roundf(dyno_temp(heat))
	if heat <= 0.05:
		return
	var n: int = (run["hp"] as Array).size()
	var best_hp := 0.0
	var best_nm := 0.0
	for i in n:
		var fade := 1.0 - DYNO_HEAT_POWER * heat * (0.3 + 0.7 * float(i) / maxf(n - 1, 1))
		run["hp"][i] = snappedf(float(run["hp"][i]) * fade, 0.01)
		run["nm"][i] = snappedf(float(run["nm"][i]) * fade, 0.01)
		if float(run["hp"][i]) > best_hp:
			best_hp = float(run["hp"][i])
			run["peak_hp_rpm"] = float(run["rpm"][i])
		if float(run["nm"][i]) > best_nm:
			best_nm = float(run["nm"][i])
			run["peak_nm_rpm"] = float(run["rpm"][i])
	run["hp_per_tonne"] = float(run["hp_per_tonne"]) * best_hp / maxf(float(run["peak_hp"]), 0.01)
	run["peak_hp"] = best_hp
	run["peak_nm"] = best_nm


## The engine on the rig cools down, quickly with the fan on; the haze clears, quickly with
## the extraction hose on. Synced in steps so it doesn't flood the network.
func _cool_dyno(delta: float) -> void:
	var heat := float(dyno.get("heat", 0.0))
	var haze := float(dyno.get("haze", 0.0))
	var fan := bool(dyno.get("fan", false))
	var heat_now := maxf(0.0, heat - delta * (0.03 if fan else 0.004))
	var haze_now := maxf(0.0, haze - delta * ((0.02 if dyno.get("hose", "") == "bike" else 0.006) + (0.01 if fan else 0.0)))
	dyno["heat"] = heat_now
	dyno["haze"] = haze_now
	if floori(heat_now * 20.0) != floori(heat * 20.0) or floori(haze_now * 20.0) != floori(haze * 20.0):
		_mark_dirty()


# ---------------------------------------------------------------------------- the sandblaster

const BLAST_WEAR := 0.12     # wear a part picks up if every patch of it were blasted too long


## The blast cabinet someone is working at (their hands in its gloves), or 0.
func blasting(peer: int) -> int:
	return int(crew.get(peer, {}).get("blaster", 0))


## Who is working at a blast cabinet, or 0.
func blaster_user(furniture_id: int) -> int:
	for peer in crew:
		if int(crew[peer].get("blaster", 0)) == furniture_id:
			return int(peer)
	return 0


func _blast_check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	match a:
		"blast_use":
			if not action.get("on", true):
				return ""
			var spot := str(action.get("spot", ""))
			if spot_role(spot) != "blaster":
				return "That's not a sandblaster."
			var f := furniture_of_spot(spot)
			var engine := item_at_spot(spot)
			if engine == 0 or not is_engine(engine) or items[engine].get("boxed", false):
				return "Put an engine in the sandblaster first."
			var user := blaster_user(int(f["id"]))
			if user != 0 and user != peer:
				return "%s is using it." % str(crew.get(user, {}).get("name", "Someone"))
			if int(f.get("mover", 0)) != 0:
				return "Someone's moving it."
			if held_by(peer) != 0:
				return "Put the part down first: it takes both hands."
			if riding(peer) != 0 or pushing_bike(peer) != 0 or moving(peer) != 0:
				return "Let go of what you've got first."
		"blast_aim":
			if blasting(peer) == 0:
				return "You're not at a sandblaster."
		"blast", "blast_tick":
			var spot := str(action.get("spot", ""))
			var f := furniture_of_spot(spot)
			if f.is_empty() or blasting(peer) != int(f["id"]):
				return "You're not at that sandblaster."
			var engine := item_at_spot(spot)
			if engine == 0 or not is_engine(engine):
				return "The engine has gone."
			if not (action.get("parts") is Dictionary):
				return "Nothing was blasted."
		_:
			return "Unknown action."
	return ""


func _blast_apply(peer: int, action: Dictionary) -> String:
	var c: Dictionary = crew.get(peer, {})
	match str(action["a"]):
		"blast_use":
			if action.get("on", true):
				c["blaster"] = int(furniture_of_spot(str(action["spot"]))["id"])
				c["blast_rot"] = Vector2.ZERO
				c["blast_fire"] = false
				# How every part was when the work started: the live updates strip from there.
				var base := {}
				var engine := item_at_spot(str(action["spot"]))
				for id in _blast_parts(engine):
					base[id] = [float(items[id]["rust"]), float(items[id]["dirt"]), float(items[id]["wear"])]
				c["blast_base"] = base
				return "Hands in the gloves. Turn the engine with W A S D (or hold right mouse), blast with left mouse. F to step back."
			c["blaster"] = 0
			c["blast_fire"] = false
			c.erase("blast_base")
		"blast_aim":
			var r = action.get("rot", Vector2.ZERO)
			var at = action.get("at", Vector3.ZERO)
			c["blast_rot"] = r if r is Vector2 else Vector2.ZERO
			c["blast_fire"] = bool(action.get("fire", false))
			c["blast_at"] = at if at is Vector3 else Vector3.ZERO
		"blast_tick":
			# Live, while blasting: the rust and muck come off as the metal comes up bare.
			_blast_strip(c, item_at_spot(str(action["spot"])), action["parts"])
		"blast":
			var engine := item_at_spot(str(action["spot"]))
			var stripped := _blast_strip(c, engine, action["parts"])
			var done := 0
			var cover_sum := 0.0
			var pitted := []
			for id in stripped:
				var cover: float = stripped[id][0]
				var over: float = stripped[id][1]
				var strip := clampf(cover / BlastGame.DONE, 0.0, 1.0)
				if over > 0.08:
					pitted.append(PartsDB.slot_name(PartsDB.slots_for_kind(str(items[id]["kind"]))[0]).to_lower())
				cover_sum += cover
				done += 1
				if strip >= 0.3:
					_xp(peer, "sandblast", clampf(strip * (1.0 - over * 0.8), 0.1, 1.0), "item:%d" % id)
				_check_part(peer, id)
			c["blaster"] = 0
			c["blast_fire"] = false
			c.erase("blast_base")
			c["repaired"] = int(c.get("repaired", 0)) + done
			if done == 0:
				return ""
			var text := "Blasted %d part%s: %d%% back to bare metal" % [done, "" if done == 1 else "s", roundi(cover_sum / done * 100.0)]
			if not pitted.is_empty():
				text += ", but you've pitted the %s" % ", ".join(pitted.slice(0, 3))
			return text
	return ""


## The engine and everything fitted to it.
func _blast_parts(engine: int) -> Array:
	var out := []
	if engine == 0 or not items.has(engine):
		return out
	out.append(engine)
	for slot in PartsDB.ENGINE_SLOTS:
		if engine_item(engine, slot) != 0:
			out.append(engine_item(engine, slot))
	return out


## Strips each part of `engine` by its blast coverage (`parts`: item id -> [covered, over]), from
## how it was when the blasting started, so it can be sent again and again as the work goes on.
## Returns what it used: item id -> [covered, over].
func _blast_strip(c: Dictionary, engine: int, parts: Dictionary) -> Dictionary:
	var on_engine := {}
	for id in _blast_parts(engine):
		on_engine[id] = true
	var base: Dictionary = c.get("blast_base", {})
	var out := {}
	for key in parts:
		var id := int(key)
		var r = parts[key]
		if not on_engine.has(id) or not (r is Array) or (r as Array).size() < 2:
			continue
		var cover := clampf(float(r[0]), 0.0, 1.0)
		var over := clampf(float(r[1]), 0.0, 1.0)
		if cover < 0.02:
			continue
		var it: Dictionary = items[id]
		if not base.has(id):
			base[id] = [float(it["rust"]), float(it["dirt"]), float(it["wear"])]
			c["blast_base"] = base
		var was: Array = base[id]
		var strip := clampf(cover / BlastGame.DONE, 0.0, 1.0)
		_note_low(id)
		# Never puts back rust that's already come off (a late or repeated update).
		it["rust"] = 0.0 if strip >= 0.999 else minf(float(it["rust"]), float(was[0]) * (1.0 - strip))
		it["dirt"] = 0.0 if strip >= 0.999 else minf(float(it["dirt"]), float(was[1]) * (1.0 - strip))
		it["wear"] = maxf(float(it["wear"]), minf(1.0, float(was[2]) + over * BLAST_WEAR))
		out[id] = [cover, over]
	return out


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
	if item.has("bead"):
		text += "\n" + bead_text(item)
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
		if bay_is_free(bay) and not holograms.has(bay):
			return bay
	return -1


func bay_is_free(bay: int) -> bool:
	for id in bikes:
		if bikes[id]["xf"].origin.distance_to(Workshop.bay_transform(bay).origin) < 2.5:
			return false
	return true


## The bay whose paddock stand is near `at`, or -1.
func bay_at(at: Vector3) -> int:
	for bay in Workshop.bay_count():
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
	if spot.begins_with("bench_"):
		# Parts put down anywhere along the workbench: bench_<n> for any n.
		return spot.trim_prefix("bench_").is_valid_int() and int(spot.trim_prefix("bench_")) >= 0
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return false
	if f["kind"] == "stand":
		return true
	var n := int(spot.get_slice("_", 2))
	if Equipment.SURFACE_KINDS.has(str(f["kind"])):
		return spot.get_slice("_", 2).is_valid_int() and n >= 0
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
	if SPOTS.has(spot) or spot.begins_with("bench_"):
		return "bench"
	var f := furniture_of_spot(spot)
	return "" if f.is_empty() else str(f["kind"])


## The places on one piece of equipment. A washer, repair machine or workbench takes parts
## anywhere on top (see surface): its places are the ones it had before that, plus one for
## every part on it.
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
	if Equipment.SURFACE_KINDS.has(str(f["kind"])):
		var start := "%s_%d_" % [prefix, id]
		for item_id in items:
			var it: Dictionary = items[item_id]
			if it["at"] == "spot" and str(it["ref"]).begins_with(start) and not out.has(str(it["ref"])):
				out.append(str(it["ref"]))
	return out


## Every spot that exists right now, fixed ones first.
func all_spots() -> Array:
	var out: Array = SPOTS.duplicate()
	for id in furniture:
		out.append_array(furniture_spots(id))
	for item_id in items:
		var it: Dictionary = items[item_id]
		if it["at"] == "spot" and str(it["ref"]).begins_with("bench_") and not out.has(str(it["ref"])):
			out.append(str(it["ref"]))
	return out


func stand_spots() -> Array:
	return all_spots().filter(func(s): return is_stand_spot(s))


## Where a part on a spot sits in the world. Equipment carries its places with it.
func spot_transform(spot: String) -> Transform3D:
	var key := surface_of_spot(spot)
	if key != "":
		var s := surface(key)
		if not s.is_empty():
			var id := item_at_spot(spot)
			if id != 0 and items[id].get("place") is Transform3D:
				return (s["xf"] as Transform3D) * (items[id]["place"] as Transform3D)
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return Workshop.spot_transform(spot)
	return (f["xf"] as Transform3D) * local_spot_transform(spot)


## Where a spot is on its piece of equipment, in the equipment's own space.
func local_spot_transform(spot: String) -> Transform3D:
	var f := furniture_of_spot(spot)
	if f.is_empty():
		return Transform3D()
	if Equipment.SURFACE_KINDS.has(str(f["kind"])):
		var id := item_at_spot(spot)
		if id != 0 and items[id].get("place") is Transform3D:
			return items[id]["place"]
	return Equipment.local_place(str(f["model"]), 0 if f["kind"] == "stand" else int(spot.get_slice("_", 2)))


# ---------------------------------------------------------------------------- free surfaces

## The surface a spot is on, when it's one parts go anywhere on: "bench" for the shed's own
## workbench, "f<id>" for a washer, repair machine or bought workbench, else "".
func surface_of_spot(spot: String) -> String:
	if spot.begins_with("bench_"):
		return "bench"
	var f := furniture_of_spot(spot)
	if not f.is_empty() and Equipment.SURFACE_KINDS.has(str(f["kind"])):
		if f["kind"] == "shelf":
			# Each board of a shelving unit is its own surface: the one the part sits on.
			var id := item_at_spot(spot)
			var y := item_place(id).origin.y if id != 0 else 0.0
			return "f%ds%d" % [int(f["id"]), Equipment.shelf_level(str(f["model"]), y)]
		return "f%d" % int(f["id"])
	return ""


## A surface parts are put down anywhere on: {xf: its frame in the world (+Z the front, y up),
## rect: the area in x and z (Rect2 x, y = z), top: the height parts sit at in the frame,
## prefix: the start of its spot names, kind ("bench", "washer", "repair"), furniture: its id
## (0 for the shed's workbench), rated: how many parts it works on at full speed}, or {}.
func surface(key: String) -> Dictionary:
	if key == "bench":
		var a := Workshop.spot_transform("bench_0").origin
		var b := Workshop.spot_transform("bench_3").origin
		var length := b.z - a.z + 1.2
		# Turned so its front faces into the shed (+X), and x runs along it.
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(a.x, 0.0, (a.z + b.z) * 0.5))
		return {"xf": xf, "rect": Rect2(-length * 0.5 + 0.05, -0.42, length - 0.1, 0.84), "top": a.y, "prefix": "bench_",
			"kind": "bench", "furniture": 0, "rated": SPOTS.size(), "key": key}
	# "f<id>" for a washer, repair machine or bench; "f<id>s<board>" for one board of a shelving unit.
	var bits := key.substr(1).split("s")
	if not key.begins_with("f") or bits.size() > 2 or not bits[0].is_valid_int() or (bits.size() == 2 and not bits[1].is_valid_int()):
		return {}
	var id := int(bits[0])
	var f: Dictionary = furniture.get(id, {})
	if f.is_empty() or not Equipment.SURFACE_KINDS.has(str(f["kind"])):
		return {}
	var model := str(f["model"])
	if f["kind"] == "shelf":
		var level := int(bits[1]) if bits.size() == 2 else 0
		if level < 0 or level >= int(Equipment.get_model(model).get("levels", 1)):
			return {}
		return {"xf": f["xf"], "rect": Equipment.surface_rect(model), "top": Equipment.shelf_top(model, level),
			"prefix": "shelf_%d_" % id, "kind": "shelf", "furniture": id, "rated": Equipment.places(model),
			"key": "f%ds%d" % [id, level], "level": level}
	if bits.size() == 2:
		return {}
	return {"xf": f["xf"], "rect": Equipment.surface_rect(model), "top": Equipment.work_height(model),
		"prefix": "%s_%d_" % [Equipment.SPOT_PREFIX[f["kind"]], id], "kind": str(f["kind"]), "furniture": id,
		"rated": Equipment.places(model), "key": key}


## A surface's name for the info panel: "Workbench", "Parts washer"...
func surface_name(key: String) -> String:
	if key == "bench":
		return "Workbench"
	var s := surface(key)
	if not s.is_empty() and s["kind"] == "shelf":
		return "%s, shelf %d" % [furniture_name(furniture[int(s["furniture"])]), int(s["level"]) + 1]
	return "" if s.is_empty() else furniture_name(furniture[int(s["furniture"])])


## Every part sitting on a surface.
func surface_items(key: String) -> Array:
	var s := surface(key)
	var out := []
	if s.is_empty():
		return out
	for id in items:
		if items[id]["at"] == "spot" and str(items[id]["ref"]).begins_with(str(s["prefix"])) and surface_of_spot(str(items[id]["ref"])) == str(s["key"]):
			out.append(id)
	return out


## Where a part on a surface sits, in the surface's frame: where it was put down, or for one
## left there before parts could go anywhere (an older save), its old fixed place.
func item_place(item_id: int) -> Transform3D:
	var it: Dictionary = items[item_id]
	if it.get("place") is Transform3D:
		return it["place"]
	var spot := str(it["ref"])
	if spot.begins_with("bench_"):
		return (surface("bench")["xf"] as Transform3D).affine_inverse() * Workshop.spot_transform(spot)
	return local_spot_transform(spot)


## How much room an item takes up: its width and depth in its own frame (x, z).
func item_footprint(item_id: int) -> Vector2:
	var it: Dictionary = items[item_id]
	var size := BikeModel.footprint(str(it["part"]), bool(it.get("boxed", false)))
	var tyre := tyre_on_wheel(item_id)
	if tyre != 0:
		size = size.max(BikeModel.footprint(str(items[tyre]["part"])))
	if is_engine(item_id) and not it.get("boxed", false):
		size *= 1.15   # whatever is bolted to the block sticks out a bit
	return Vector2(maxf(size.x, 0.06), maxf(size.z, 0.06))


## The area a footprint covers on a surface, put down at `place`.
static func foot_rect(place: Transform3D, foot: Vector2) -> Rect2:
	var r := Rect2(Vector2(place.origin.x, place.origin.z), Vector2.ZERO)
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var p: Vector3 = place * (corner * Vector3(foot.x * 0.5, 0.0, foot.y * 0.5))
		r = r.expand(Vector2(p.x, p.z))
	return r


## Why `item_id` can't go down on a surface at `place` (in the surface's frame), or "" when it
## fits: inside the top (a part can hang over the edge a little) and clear of everything on it.
func surface_fits(key: String, item_id: int, place: Transform3D) -> String:
	var s := surface(key)
	if s.is_empty() or not items.has(item_id):
		return "You can't put it there."
	return _fits(s, item_id, foot_rect(place, item_footprint(item_id)), _surface_rects(key, item_id))


func _fits(s: Dictionary, item_id: int, r: Rect2, others: Array) -> String:
	var area: Rect2 = (s["rect"] as Rect2).grow(SURFACE_OVERHANG)
	if not area.encloses(r):
		var foot := item_footprint(item_id)
		var room: Vector2 = area.size
		if maxf(foot.x, foot.y) > maxf(room.x, room.y) or minf(foot.x, foot.y) > minf(room.x, room.y):
			return "The %s is too big for the %s." % [item_title(item_id).to_lower(), surface_name(str(s["key"])).to_lower()]
		return "That's over the edge. Put it further on."
	for o in others:
		if (o[1] as Rect2).grow(-SURFACE_GAP).intersects(r):
			return "No room there: the %s is in the way." % item_title(int(o[0])).to_lower()
	return ""


## [item id, the area it covers] for everything on a surface but `skip`.
func _surface_rects(key: String, skip := 0) -> Array:
	var out := []
	for id in surface_items(key):
		if id != skip:
			out.append([id, foot_rect(item_place(id), item_footprint(id))])
	return out


## The nearest place to `at` (x, z on the surface) where `item_id` fits, turned `yaw` or a
## quarter turn from it: a Transform3D in the surface's frame, or null when there's no room
## anywhere near. Looks out in rings up to 0.6 m.
func find_room(key: String, item_id: int, at: Vector2, yaw := 0.0):
	var s := surface(key)
	if s.is_empty() or not items.has(item_id):
		return null
	var rect: Rect2 = s["rect"]
	at = at.clamp(rect.position, rect.end)
	var others := _surface_rects(key, item_id)
	var foot := item_footprint(item_id)
	var top := float(s["top"])
	for ring in 13:
		var n := 1 if ring == 0 else 6 + ring * 3
		for k in n:
			var a := TAU * float(k) / float(n)
			var p := at + Vector2(cos(a), sin(a)) * (ring * 0.05)
			for turn in [0.0, PI * 0.5]:
				var place := Transform3D(Basis(Vector3.UP, yaw + turn), Vector3(p.x, top, p.y))
				if _fits(s, item_id, foot_rect(place, foot), others) == "":
					return place
	return null


## A spot name nobody on the surface is using yet.
func _free_surface_spot(key: String) -> String:
	var prefix := str(surface(key)["prefix"])
	var used := {}
	for id in items:
		if items[id]["at"] == "spot" and str(items[id]["ref"]).begins_with(prefix):
			used[str(items[id]["ref"])] = true
	var n := 0
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


## A put-down place cleaned up: flat on the surface at its top, turned only about the vertical.
func _flat_place(xf: Transform3D, top: float) -> Transform3D:
	var yaw := xf.basis.get_euler().y
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(xf.origin.x, top, xf.origin.z))


## How hard a washer or repair machine is working: 1 with up to its rated number of parts on
## it, slowing in step past that, so piling more on doesn't get more done at once.
static func load_factor(count: int, rated: int) -> float:
	return maxf(1.0, float(count) / float(maxi(1, rated)))


## The crew whiteboard (see Whiteboard): its furniture id, or 0.
func whiteboard_id() -> int:
	for id in furniture:
		if furniture[id]["kind"] == "whiteboard":
			return id
	return 0


## How big a piece of equipment is as it stands (width, height, depth): its model's size, or
## for a poster the size it was printed at, on its side when it's been turned a quarter.
static func furniture_size(f: Dictionary) -> Vector3:
	var model := str(f.get("model", ""))
	if Equipment.kind_of(model) != "poster":
		return Equipment.get_model(model).get("size", Vector3.ONE)
	var art := Equipment.poster_size(model, str(f.get("psize", "")))
	return Vector3(art.y, art.x, art.z) if int(f.get("turn", 0)) % 2 == 1 else art


func furniture_name(f: Dictionary) -> String:
	var n := str(Equipment.get_model(str(f.get("model", ""))).get("name", "Equipment"))
	if f["kind"] == "shelf" and str(f.get("label", "")) != "":
		return "%s: %s" % [n, f["label"]]
	return n


## The shed's built-in kit: the paint booth in its lean-to and the tyre changer by the end of
## the workbench. Adds whatever is missing (a new shed, or a save from before it was built in).
func ensure_fixtures() -> void:
	var have := {}
	var booths := []
	for id in furniture:
		match str(furniture[id]["kind"]):
			"booth":
				booths.append(id)
			"changer":
				furniture[id]["xf"] = Workshop.CHANGER_XF
				have["changer"] = true
	booths.sort()
	if booths.is_empty():
		_new_furniture("booth", Workshop.BOOTH_XF, Workshop.BOOTH_MODEL)
	else:
		# Older sheds had a smaller booth (or more than one): there's one big spray bay now, and
		# everything that hung in the old ones moves onto its hooks, in order.
		var main: int = booths[0]
		var hung := []
		for id in booths.slice(1):
			for spot in furniture_spots(id):
				var it := item_at_spot(spot)
				if it != 0:
					hung.append(it)
			furniture.erase(id)
		furniture[main]["model"] = Workshop.BOOTH_MODEL
		furniture[main]["xf"] = Workshop.BOOTH_XF
		furniture[main]["mover"] = 0
		# Parts on the main booth keep their hooks (it only gained some).
		var free := furniture_spots(main).filter(func(s): return item_at_spot(s) == 0)
		for i in hung.size():
			if i < free.size():
				_move(hung[i], "spot", free[i])
			else:
				var at := Workshop.BOOTH_ROOM_CENTER + Vector3(-2.6, 0.0, -4.5 + (i - free.size()) * 0.6)
				_move(hung[i], "floor", Transform3D(Basis(), at))
	if not have.has("changer"):
		_new_furniture("changer", Workshop.CHANGER_XF, "tyre_changer")
	# The crew whiteboard can be hung on any wall; a save from before that keeps it where it was.
	if whiteboard_id() == 0:
		_new_furniture("whiteboard", Transform3D(Basis(Vector3.UP, Whiteboard.FACING), Whiteboard.MOUNT), "whiteboard")
	# Kit left where the bigger spray bay stands now goes to the paint shop's walkway.
	var bay := Workshop.booth_footprint()
	var n := 0
	for id in furniture:
		var f: Dictionary = furniture[id]
		if Equipment.FIXED_KINDS.has(str(f["kind"])) or Equipment.is_wall(str(f["model"])):
			continue
		var at: Vector3 = (f["xf"] as Transform3D).origin
		if bay.has_point(Vector2(at.x, at.z)):
			f["xf"] = Transform3D(Basis(Vector3.UP, PI * 0.5), Workshop.BOOTH_ROOM_CENTER + Vector3(-2.6, 0.0, -3.0 + n * 1.4))
			n += 1


## Whether a side room's lights are on ("paint" or "storage"; "" is the shed itself).
func room_lit(room: String) -> bool:
	if room == "":
		return lights_on
	return bool(room_lights.get(room, true))


## The tyre on a loose wheel (one that's off the bike), or 0.
func tyre_on_wheel(wheel_id: int) -> int:
	var t := int(items.get(wheel_id, {}).get("tyre", 0))
	return t if items.has(t) else 0


## The tyre changer's place for a wheel, or "".
func changer_spot() -> String:
	for id in furniture:
		if furniture[id]["kind"] == "changer":
			return str(furniture_spots(id)[0])
	return ""


## "Bead seated perfectly (96%)": how well a tyre went on at the tyre changer.
func bead_text(item: Dictionary) -> String:
	if not item.has("bead"):
		return ""
	var q := float(item["bead"])
	if q >= 0.9:
		return "Bead seated perfectly (%d%%)" % roundi(q * 100.0)
	if q >= BikeBuild.BEAD_OK:
		return "Bead seated well (%d%%)" % roundi(q * 100.0)
	return "Bead badly seated (%d%%): it loses pressure and grips less. Refit it on the tyre changer." % roundi(q * 100.0)


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


## How long the grinder takes over a batch on a repair machine: the worst part sets the pace,
## and a machine with more on it than it's rated for slows in step (see load_factor).
func repair_time(ids: Array) -> float:
	var worst := 0.0
	var speed := 1.0
	var rated := 0
	for id in ids:
		if not items.has(int(id)):
			continue
		worst = maxf(worst, float(items[int(id)]["rust"]) + float(items[int(id)]["wear"]))
		var f := furniture_of_spot(str(items[int(id)]["ref"]))
		if not f.is_empty():
			speed = float(Equipment.get_model(str(f["model"])).get("speed", 1.0))
			rated = Equipment.places(str(f["model"]))
	var t := (2.0 + 4.0 * worst + 0.6 * maxi(0, ids.size() - 1)) / speed
	return t * load_factor(ids.size(), rated) if rated > 0 else t


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
	for bay in Workshop.bay_count():
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
		for m in PartsDB.part_mounts(slot, str(items[item_id]["part"])):
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
	if a.begins_with("contract_"):
		return Contracts.check(peer, action)
	if a.begins_with("dyno_") and a != "dyno_run":
		return _dyno_check(peer, action)
	if a.begins_with("blast"):
		return _blast_check(peer, action)
	if a.begins_with("money_"):
		return Money.check(peer, action)
	if hose_holder() == peer and a in ["take", "remove", "install", "grab", "grab_bike", "mount", "unpack"]:
		return "You've got the exhaust hose in your hands. Fit it or hang it back up."
	match a:
		"unbolt", "bolt", "remove":
			var host := host_of(bike_id, slot, engine_id)
			var item_id := int(host.get("slots", {}).get(slot, 0))
			if item_id == 0:
				return "That part isn't fitted."
			var bolted := bool(host["bolted"].get(slot, false))
			if a in ["unbolt", "remove"] and engine_id == 0 and WHEEL_TYRE.values().has(slot):
				return "The tyre comes off with its wheel: take the wheel off and change the tyre on the tyre changer."
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
					if int(host["slots"].get(dep, 0)) != 0 and not (engine_id == 0 and WHEEL_TYRE.get(slot, "") == dep):
						return "Take the %s off first." % PartsDB.slot_name(dep).to_lower()
				# Parts that bolt onto this one as well as their own mounts (fairing-mount mirrors).
				for other in host["slots"]:
					var on := int(host["slots"][other])
					if on != 0 and items.has(on) and PartsDB.part_mounts(str(other), str(items[on]["part"])).has(slot) \
							and not PartsDB.MOUNTS.get(other, []).has(slot):
						return "Take the %s off first." % PartsDB.slot_name(str(other)).to_lower()
		"install":
			if held == 0:
				return "You're not holding a part."
			if items[held].get("boxed", false):
				return "Unpack it first."
			if items[held]["kind"] == "tyre" and engine_id == 0:
				return "Tyres go on at the tyre changer: take the wheel off and put it on the changer by the workbench."
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
			if spot_role(str(action.get("spot", ""))) == "blaster" and blaster_user(int(furniture_of_spot(str(action["spot"]))["id"])) != 0:
				return "Someone's blasting it."
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
			if spot_role(spot) in ["washer", "repair", "changer"] and items[held].get("boxed", false):
				return "Unpack it first."
			if spot_role(spot) == "changer" and items[held]["kind"] != "wheel":
				return "Only a wheel goes on the tyre changer. Fit tyres to a wheel on it."
			if spot_role(spot) == "blaster" and (not is_engine(held) or items[held].get("boxed", false)):
				return "The sandblaster is for engines: put an engine in it, ancillaries and all."
		"set_down":
			# Down anywhere on a workbench, washer or repair machine there's room for it.
			if held == 0:
				return "You're not holding a part."
			var s := surface(str(action.get("top", "")))
			if s.is_empty() or not (action.get("xf") is Transform3D):
				return "You can't put it there."
			if str(s["kind"]) in ["washer", "repair"] and items[held].get("boxed", false):
				return "Unpack it first."
			return surface_fits(str(action["top"]), held, _flat_place(action["xf"], float(s["top"])))
		"tyre_fit", "tyre_remove":
			var spot := str(action.get("spot", ""))
			if spot_role(spot) != "changer":
				return "Use the tyre changer."
			var wheel := item_at_spot(spot)
			if wheel == 0:
				return "Put a wheel on the tyre changer first."
			var on := tyre_on_wheel(wheel)
			if a == "tyre_fit":
				if held == 0 or items[held]["kind"] != "tyre":
					return "Hold a tyre to fit it."
				if items[held].get("boxed", false):
					return "Unpack it first."
				if on != 0:
					return "There's already a tyre on that wheel. Lever it off first."
				var why := PartsDB.tyre_fit_reason(str(items[held]["part"]), str(items[wheel]["part"]))
				if why != "":
					return why
				var q = action.get("quality", 1.0)
				if not (q is float or q is int):
					return "Work the tyre on first."
			else:
				if on == 0:
					return "There's no tyre on that wheel."
				if held != 0:
					return "Your hands are full."
		"radio":
			var st := int(action.get("station", radio["station"]))
			if st < 0 or st >= stations.size():
				return "No such station."
		"order_part":
			if PartsDB.get_part(str(action.get("part", ""))).is_empty():
				return "Unknown part."
			if free_delivery_xf() == null:
				return "The delivery area outside is full. Bring some boxes in first."
			var cost := Money.buy_price(str(action["part"]), peer)
			if cost > garage_money:
				return "The business can't afford it: %s, and it has %s." % [TvChannels.money_text(cost), TvChannels.money_text(garage_money)]
		"order_furniture":
			var model := Equipment.current_id(str(action.get("model", Equipment.DEFAULT.get(str(action.get("kind", "")), ""))))
			if Equipment.get_model(model).is_empty():
				return "Unknown equipment."
			if Equipment.FIXED_KINDS.has(Equipment.kind_of(model)):
				return "The paint booth is built into the shed: it's in the paint shop on the east side."
			if model == Equipment.BOARD_POSTER and not posters.has(int(action.get("design", 0))):
				return "That whiteboard poster isn't in the shop any more."
			if str(action.get("psize", "")) != "" and (Equipment.kind_of(model) != "poster" or not Equipment.POSTER_SIZES.has(str(action["psize"]))):
				return "That size isn't sold."
			if Equipment.kind_of(model) == "whiteboard":
				return "The shed has its whiteboard already. Press F on it to hang it somewhere else."
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
			if blaster_user(int(f["id"])) != 0:
				return "Someone's working at it."
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
		"turn_poster":
			var f: Dictionary = furniture.get(int(action.get("furniture", 0)), {})
			if f.is_empty() or f["mover"] != peer:
				return "You're not carrying that."
			if f["kind"] != "poster":
				return "Only posters turn round: the %s hangs one way up." % furniture_name(f).to_lower()
			if not (action.get("turn") is int or action.get("turn") is float):
				return "Turn it which way?"
		"scrap":
			return scrap_check(peer, action)
		"label":
			var f: Dictionary = furniture.get(int(action.get("furniture", 0)), {})
			if f.is_empty() or f["kind"] != "shelf":
				return "Only shelves take labels."
		"rename_bike":
			if not bikes.has(bike_id):
				return "That bike's gone."
			if str(action.get("name", "")).strip_edges() == "":
				return "Give it a name."
		"door":
			pass
		"lights":
			var room := str(action.get("room", ""))
			if room != "" and not LIT_ROOMS.has(room):
				return "There's no light switch for that."
		"bin":
			if held == 0:
				return "You're not holding a part."
			return bin_check(held, str(action.get("bin", "general")))
		"tv_channel":
			if not TvChannels.screen_exists(str(action.get("screen", ""))):
				return "That screen has gone."
			if not int(action.get("step", 0)) in [-1, 1]:
				return "Pick the next or previous channel."
		"tip":
			if held == 0 or not items[held].has("fluid") or float(items[held]["fluid"]["litres"]) <= 0.0:
				return "Nothing to tip away."
			if str(action.get("bin", "general")) != "general":
				return "Tip it away at the general waste bin."
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
			if on_dyno(bike_id) and straps_done() > 0:
				return "Undo the straps first (hold the work button at each one)."
			if on_dyno(bike_id) and dyno["hose"] == "bike":
				return "Take the extraction hose off the exhaust first."
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
				return "It's on the dyno rig."
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
			if bay < 0 or bay >= Workshop.bay_count():
				return "Take it to one of the bays."
			if not bay_is_free(bay):
				return "There's already a bike in bay %d." % (bay + 1)
		"geo_save", "geo_blueprint", "bp_rename", "bp_delete", "bp_build", "bp_cancel", "bp_order":
			return _blueprint_check(action)
		"order":
			if free_bay(Workshop.bay_count()) < 0:
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
			if not strapped():
				return "Strap it down first: %d of the 4 straps are done up." % straps_done()
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
		"garage_money":
			if peer != 1:
				return "Only the host can change the garage's money."
			if not (action.get("value") is int or action.get("value") is float):
				return "How much?"
		"buy_upgrade":
			return GarageUpgrades.check(str(action.get("id", "")), upgrades, garage_money)
		"restyle_upgrade":
			return GarageUpgrades.check_restyle(str(action.get("id", "")), action.get("looks"), upgrades, looks, garage_money)
		_:
			return "Unknown action."
	return ""


## Why `item_id` can't go in `which` bin ("general", "plastic" or "metal"), or "". General waste
## takes anything; a recycling bin only takes its own material, empty and unboxed.
func bin_check(item_id: int, which: String) -> String:
	if not PartsDB.BINS.has(which):
		return "That's not a bin."
	if not items.has(item_id) or which == "general":
		return ""
	var it: Dictionary = items[item_id]
	var part := str(it["part"])
	if it.get("boxed", false):
		return "Unpack it first."
	if is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			if engine_item(item_id, slot) != 0:
				return "Strip the engine down first: there are parts still on it."
	if it.has("fluid") and float(it["fluid"].get("litres", 0.0)) > 0.01:
		if PartsDB.is_fluid(part):
			return "Empty it first: tip it away at the general waste bin."
		return "Drain the %s out of it first." % str(PartsDB.KIND_NAMES.get(PartsDB.fluid_kind(part), "fluid")).to_lower()
	var want := PartsDB.bin_for(part)
	if want != which:
		var mat := str(PartsDB.MATERIAL_NAMES.get(PartsDB.material(part), "mixed")).to_lower()
		return "That's %s: %s." % [mat, "general waste" if want == "general" else str(PartsDB.BIN_NAMES[want]).to_lower()]
	return ""


## Why `peer` can't scrap what the action names, or "": {furniture: the equipment they're
## carrying} or {item: the part in their hands}. The shed's own kit (the spray bay, the tyre
## changer and the whiteboard) can't be scrapped.
func scrap_check(peer: int, action: Dictionary) -> String:
	if action.has("furniture"):
		var f: Dictionary = furniture.get(int(action["furniture"]), {})
		if f.is_empty():
			return "That has gone."
		if Equipment.FIXED_KINDS.has(str(f["kind"])) or f["kind"] == "whiteboard":
			return "The %s is part of the shed: it can't be scrapped." % furniture_name(f).to_lower()
		if f["mover"] != peer:
			return "Take hold of it first (F), then hold the scrap key."
		if blaster_user(int(f["id"])) != 0:
			return "Someone's working at it."
		return ""
	var item_id := int(action.get("item", 0))
	if item_id == 0 or not items.has(item_id) or held_by(peer) != item_id:
		return "Hold the part you want to scrap."
	return ""


## Scraps equipment or a part for good (see scrap_check). Whatever was on or in it goes on the
## floor first: the parts on a shelf or bench under where they sat, and the parts bolted to an
## engine or the tyre on a wheel at `at` (where the player is looking, on the floor).
func _scrap(_peer: int, action: Dictionary) -> String:
	if action.has("furniture"):
		var id := int(action["furniture"])
		var f: Dictionary = furniture[id]
		var what := furniture_name(f).to_lower()
		var floor_y: float = (f["xf"] as Transform3D).origin.y
		var dropped := 0
		for spot in furniture_spots(id):
			var on := item_at_spot(spot)
			if on == 0:
				continue
			var xf := spot_transform(spot)
			_move(on, "floor", Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), Vector3(xf.origin.x, floor_y, xf.origin.z)))
			_washer_by.erase(on)
			dropped += 1
		screens.erase("f%d" % id)
		furniture.erase(id)
		if dropped > 0:
			return "Scrapped the %s. What was on it is on the floor." % what
		return "Scrapped the %s" % what
	var item_id := int(action["item"])
	var at := Transform3D(Basis(), Workshop.CENTER)
	if action.get("at") is Transform3D and (action["at"] as Transform3D).origin.distance_to(Workshop.CENTER) < 400.0 \
			and (action["at"] as Transform3D).origin.y > -5.0:
		at = action["at"]
	var dropped := []
	var tyre := tyre_on_wheel(item_id)
	if tyre != 0:
		items[item_id].erase("tyre")
		items[tyre].erase("bead")
		dropped.append(tyre)
	if is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := engine_item(item_id, slot)
			if sub != 0:
				items[item_id]["slots"][slot] = 0
				items[item_id]["bolted"][slot] = false
				dropped.append(sub)
	for i in dropped.size():
		var d: int = dropped[i]
		_move(d, "floor", at.translated_local(Vector3((i % 4 - 1.5) * 0.3, 0.0, -(i / 4) * 0.3)))
	var name_was := item_title(item_id).to_lower()
	_erase_item(item_id)
	if dropped.is_empty():
		return "Scrapped the %s" % name_was
	return "Scrapped the %s. The %d part%s on it are on the floor." % [name_was, dropped.size(), "" if dropped.size() == 1 else "s"] \
		if dropped.size() != 1 else "Scrapped the %s. The %s on it is on the floor." % [name_was, item_title(dropped[0]).to_lower()]


## Everyone out riding right now, by peer id, lowest first.
func riders() -> Array:
	var out := []
	for peer in crew:
		var bike := int(crew[peer].get("riding", 0))
		if bike != 0 and bikes.has(bike) and int(bikes[bike].get("rider", 0)) == int(peer):
			out.append(int(peer))
	out.sort()
	return out


## The channel a screen is showing: {ch, rider}, its home channel if nobody has changed it.
func screen_channel(key: String) -> Dictionary:
	var s = screens.get(key, null)
	if s is Dictionary and TvChannels.channels_for(key).has(str(s.get("ch", ""))):
		return {"ch": str(s["ch"]), "rider": int(s.get("rider", 0))}
	return {"ch": TvChannels.home(key), "rider": 0}


## Gives `peer` XP for `key` through the Progress autoload, when it's there (host only).
func _award(peer: int, key: String, mult := 1.0) -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog and prog.has_method("award"):
		prog.award(peer, key, mult)


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
	if str(action.get("a", "")).begins_with("money_"):
		_money_apply(peer, action)
		return
	var why := check(peer, action)
	if why != "":
		_tell(peer, why, false)
		return
	var a := str(action["a"])
	Contracts.note_action(peer, action)
	if a.begins_with("contract_"):
		var said_c := Contracts.apply(peer, action)
		if said_c != "":
			_tell(peer, said_c, true)
		_mark_dirty()
		changed.emit()
		return
	if a.begins_with("blast"):
		var told := _blast_apply(peer, action)
		if told != "":
			_tell(peer, told, true)
		_mark_dirty()
		changed.emit()
		return
	if a.begins_with("dyno_") and a != "dyno_run":
		var said := _dyno_apply(peer, action)
		if said != "":
			_tell(peer, said, true)
		_mark_dirty()
		changed.emit()
		return
	var bike_id := int(action.get("bike", 0))
	var engine_id := int(action.get("engine", 0))
	var slot := str(action.get("slot", ""))
	var c: Dictionary = crew.get(peer, {})
	var text := ""
	# The part a bike or engine job is on, for its XP.
	var on_target := item_at_target(action) if slot != "" and (bike_id != 0 or engine_id != 0) else 0
	match a:
		"unbolt":
			host_of(bike_id, slot, engine_id)["bolted"][slot] = false
			text = "%s unbolted" % PartsDB.slot_name(slot)
			_xp(peer, "unbolt", 1.0, "item:%d" % on_target)
		"bolt":
			host_of(bike_id, slot, engine_id)["bolted"][slot] = true
			text = "%s bolted up" % PartsDB.slot_name(slot)
			if engine_id == 0 and is_complete(bike_id):
				text += ". The bike is ready to ride!"
			elif engine_id != 0 and engine_missing(engine_id).is_empty():
				text += ". The engine is complete."
			_xp(peer, "bolt", 1.0, "item:%d" % on_target)
			if engine_id == 0:
				_milestones(peer, bike_id)
			elif engine_missing(engine_id).is_empty() and PartsDB.ENGINE_SLOTS.all(func(s2): return engine_bolted(engine_id, s2)):
				_xp(peer, "engine_build", 1.0, "item:%d" % engine_id)
		"remove":
			var host := host_of(bike_id, slot, engine_id)
			var item_id := int(host["slots"][slot])
			host["slots"][slot] = 0
			host["bolted"][slot] = false
			_move(item_id, "held", peer)
			if engine_id == 0 and WHEEL_TYRE.has(slot):
				# The tyre stays on its wheel: take them both to the tyre changer.
				var ts: String = WHEEL_TYRE[slot]
				var tyre := int(host["slots"].get(ts, 0))
				if tyre != 0:
					host["slots"][ts] = 0
					host["bolted"][ts] = false
					items[item_id]["tyre"] = tyre
					_move(tyre, "wheel", item_id)
			_bump(c, "removed")
			_xp(peer, "remove", 1.0, "item:%d" % item_id)
			if engine_id == 0:
				_note_stripped(bike_id, slot)
			text = "Removed the %s" % PartsDB.part_name(items[item_id]["part"])
			if engine_id == 0 and slot == "frame":
				# Nothing left of it: the bay is free for the next project.
				text += ". Bay %d is free." % (bikes[bike_id]["bay"] + 1)
				var plan = bikes[bike_id].get("blueprint")
				var bay := int(bikes[bike_id]["bay"])
				if plan is Dictionary and bay >= 0 and not holograms.has(bay):
					# A blueprint build stripped back to nothing: its hologram waits for another frame.
					holograms[bay] = plan
				bikes.erase(bike_id)
		"install":
			var item_id := held_by(peer)
			var s: String = install_slot(action, item_id)["slot"]
			var host := host_of(bike_id, s, engine_id)
			host["slots"][s] = item_id
			host["bolted"][s] = false
			_move(item_id, "engine" if PartsDB.is_engine_slot(s) else "bike", int(host["id"]))
			var tyre := tyre_on_wheel(item_id)
			if tyre != 0 and WHEEL_TYRE.has(s) and int(host["slots"].get(WHEEL_TYRE[s], 0)) == 0:
				# A wheel goes back on with its tyre seated on it.
				host["slots"][WHEEL_TYRE[s]] = tyre
				host["bolted"][WHEEL_TYRE[s]] = true
				_move(tyre, "bike", int(host["id"]))
				items[item_id].erase("tyre")
			_bump(c, "fitted")
			_xp(peer, "fit", 1.0, "item:%d" % item_id)
			text = "Fitted the %s as the %s. Bolt it up with the wrench." % [PartsDB.part_name(items[item_id]["part"]),
				PartsDB.slot_name(s).to_lower()]
			if engine_id == 0 and _blueprint_done(bike_id):
				text += " That's every part on its blueprint: the hologram is gone."
			elif engine_id != 0 and _bike_of(engine_id) != 0 and _blueprint_done(_bike_of(engine_id)):
				text += " That's every part on its blueprint: the hologram is gone."
		"take":
			var item_id := int(action["item"]) if action.has("item") else item_at_spot(str(action["spot"]))
			_move(item_id, "held", peer)
			_washer_by.erase(item_id)
		"drop":
			var item_id := held_by(peer)
			_move(item_id, "floor", action["xf"])
			_xp(peer, "carry", 1.0, "item:%d" % item_id)
		"place":
			var item_id := held_by(peer)
			_move(item_id, "spot", str(action["spot"]))
			_xp(peer, "carry", 1.0, "item:%d" % item_id)
			if spot_role(str(action["spot"])) == "washer":
				_washer_by[item_id] = peer
			if is_stand_spot(str(action["spot"])):
				text = "Engine on the stand. Strip it down or build it up."
			elif spot_role(str(action["spot"])) == "washer":
				text = "Into the %s" % furniture_name(furniture_of_spot(str(action["spot"]))).to_lower()
			elif spot_role(str(action["spot"])) == "changer":
				text = "Wheel clamped on the tyre changer. %s" % ("Lever the old tyre off, or lift the wheel off again." \
					if tyre_on_wheel(item_id) != 0 else "Hold a tyre that fits it and work it on.")
		"set_down":
			var item_id := held_by(peer)
			var key := str(action["top"])
			var s := surface(key)
			_move(item_id, "spot", _free_surface_spot(key))
			items[item_id]["place"] = _flat_place(action["xf"], float(s["top"]))
			_xp(peer, "carry", 1.0, "item:%d" % item_id)
			if s["kind"] == "washer":
				_washer_by[item_id] = peer
				text = "Into the %s" % surface_name(key).to_lower()
		"tyre_fit":
			var wheel := item_at_spot(str(action["spot"]))
			var tyre := held_by(peer)
			var q := clampf(float(action.get("quality", 1.0)), 0.0, 1.0)
			items[wheel]["tyre"] = tyre
			_move(tyre, "wheel", wheel)
			items[tyre]["bead"] = q
			_bump(c, "fitted")
			_xp(peer, "tyre_fit", q, "item:%d" % tyre)
			text = "Fitted the %s to the %s. %s" % [item_title(tyre), item_title(wheel), bead_text(items[tyre])]
		"tyre_remove":
			var wheel := item_at_spot(str(action["spot"]))
			var tyre := tyre_on_wheel(wheel)
			items[wheel].erase("tyre")
			items[tyre].erase("bead")
			_move(tyre, "held", peer)
			_bump(c, "removed")
			_xp(peer, "tyre_remove", 1.0, "item:%d" % tyre)
			text = "Levered the %s off the %s" % [item_title(tyre), item_title(wheel)]
		"order_part":
			var part_id := str(action["part"])
			var cost := Money.buy_price(part_id, peer)
			charge_garage(cost, "Bought %s" % PartsDB.part_name(part_id))
			var item_id := _new_item(part_id, 0.0, 0.0, 0.0)
			# Parts come boxed; cans and bottles of fluid are left as they are.
			items[item_id]["boxed"] = not PartsDB.is_fluid(part_id)
			_move(item_id, "floor", free_delivery_xf())
			text = "Ordered %s for %s. %s outside by the roller door." % [PartsDB.part_name(part_id), TvChannels.money_text(cost),
				"The box is" if items[item_id]["boxed"] else "It's"]
		"order_furniture":
			var model := Equipment.current_id(str(action.get("model", Equipment.DEFAULT.get(str(action.get("kind", "")), ""))))
			var kind := Equipment.kind_of(model)
			if Equipment.is_yard(model):
				_new_furniture(kind, free_yard_xf(model), model)
				text = "Ordered the %s. It's in the yard by the drag strip: press F on it to move it where you want it." % \
					Equipment.get_model(model)["name"].to_lower()
			else:
				var fid := _new_furniture(kind, free_delivery_xf(), model)
				var what := str(Equipment.get_model(model)["name"]).to_lower()
				if kind == "poster":
					# Printed A2, A1, A0 or as a big banner (A1 unless the order says).
					var psize := str(action.get("psize", ""))
					furniture[fid]["psize"] = psize if Equipment.POSTER_SIZES.has(psize) else Equipment.POSTER_SIZE_DEFAULT
					furniture[fid]["turn"] = 0
				if model == Equipment.BOARD_POSTER:
					# A print of a whiteboard drawing: it shows that design.
					var design := int(action.get("design", 0))
					furniture[fid]["design"] = design
					what = "\"%s\" poster" % str(posters[design]["name"])
				var how := "press F on it to carry it in and hang it on a wall" if Equipment.is_wall(model) else \
					("hold F on it to move it" if kind == "seat" else "press F on it to push it in")
				if kind == "poster":
					what = "%s %s" % [Equipment.POSTER_SIZES[furniture[fid]["psize"]]["name"], what]
				text = "Ordered the %s. It's outside by the roller door: %s." % [what, how]
		"start_build":
			var id := _empty_bike(held_by(peer), int(action["bay"]))
			_bump(c, "fitted")
			_xp(peer, "start_build", 1.0, "bike:%d" % id)
			text = "%s is on the paddock stand in bay %d. Fit the forks, shock and the rest to it, then bolt it all up." % [
				bikes[id]["name"], int(action["bay"]) + 1]
			if holograms.has(int(action["bay"])):
				text = _start_blueprint(id, int(action["bay"]))
		"unpack":
			items[int(action["item"])]["boxed"] = false
			text = "Unpacked the %s" % item_title(int(action["item"]))
			_xp(peer, "unbox", 1.0, "item:%d" % int(action["item"]))
		"grab":
			furniture[int(action["furniture"])]["mover"] = peer
		"move_furniture":
			furniture[int(action["furniture"])]["xf"] = action["xf"]
		"release":
			furniture[int(action["furniture"])]["xf"] = action["xf"]
			furniture[int(action["furniture"])]["mover"] = 0
		"turn_poster":
			var f: Dictionary = furniture[int(action["furniture"])]
			f["turn"] = posmod(int(action["turn"]), 4)
			text = "Landscape" if f["turn"] % 2 == 1 else "Portrait"
			var art := Equipment.poster_size(str(f["model"]), str(f.get("psize", "")))
			if art.x > art.y:
				text = "Portrait" if f["turn"] % 2 == 1 else "Landscape"
			text += " (%s)" % ["the right way up", "turned left", "upside down", "turned right"][int(f["turn"])]
		"scrap":
			text = _scrap(peer, action)
		"rename_bike":
			bikes[bike_id]["name"] = str(action["name"]).strip_edges().left(28)
			text = "Named it %s" % bikes[bike_id]["name"]
		"garage_money":
			# The debug tab: set the shed's account (reset to 0).
			var was := garage_money
			garage_money = clampi(int(action.get("value", 0)), 0, MAX_GARAGE_MONEY)
			Money.log_entry(bank, garage_money - was, "Debug: account set", garage_money)
			text = "Garage money set to %s" % TvChannels.money_text(garage_money)
		"buy_upgrade":
			text = _buy_upgrade(peer, str(action["id"]), action.get("looks"))
		"restyle_upgrade":
			text = _restyle_upgrade(str(action["id"]), action.get("looks"))
		"door":
			door_open = bool(action.get("open", not door_open))
			text = "Roller door %s" % ("going up" if door_open else "coming down")
		"lights":
			var room := str(action.get("room", ""))
			if room == "":
				lights_on = bool(action.get("on", not lights_on))
				text = "Lights %s" % ("on" if lights_on else "off")
			else:
				room_lights[room] = bool(action.get("on", not room_lit(room)))
				text = "%s lights %s" % [{"paint": "Paint shop", "sales": "Sales office"}.get(room, "Storage room"), "on" if room_lights[room] else "off"]
		"label":
			furniture[int(action["furniture"])]["label"] = str(action.get("text", "")).strip_edges().left(24)
			text = "Labelled the shelves \"%s\"" % furniture[int(action["furniture"])]["label"]
		"bin":
			var item_id := held_by(peer)
			var which := str(action.get("bin", "general"))
			if which == "general":
				text = "Binned the %s" % PartsDB.part_name(items[item_id]["part"])
			else:
				text = "Recycled the %s in the %s bin" % [PartsDB.part_name(items[item_id]["part"]), which]
			_erase_item(item_id)
			_award(peer, "bin" if which == "general" else "recycle_" + which)
		"tv_channel":
			var key := str(action["screen"])
			var was: Dictionary = screens.get(key, {})
			screens[key] = TvChannels.step(key, was, int(action["step"]), riders())
		"clean_many":
			var n := 0
			for id in action["items"]:
				if items.has(int(id)) and items[int(id)]["at"] != "held" and items[int(id)]["dirt"] >= 0.02 \
						and not items[int(id)].get("boxed", false):
					_note_low(int(id))
					items[int(id)]["dirt"] = 0.0
					n += 1
					_xp(peer, "brush", 1.0, "item:%d" % int(id))
					_check_part(peer, int(id))
			_bump(c, "cleaned")
			c["cleaned"] = int(c["cleaned"]) + n - 1
			text = "Scrubbed %d part%s clean" % [n, "" if n == 1 else "s"]
		"clean":
			_note_low(int(action["item"]))
			items[int(action["item"])]["dirt"] = 0.0
			_bump(c, "cleaned")
			_xp(peer, "brush", 1.0, "item:%d" % int(action["item"]))
			_check_part(peer, int(action["item"]))
			text = "Cleaned the %s" % item_title(int(action["item"]))
		"repair":
			var it: Dictionary = items[int(action["item"])]
			_note_low(int(action["item"]))
			it["rust"] = 0.0
			it["wear"] = 0.0
			_bump(c, "repaired")
			_xp(peer, "repair", 1.0, "item:%d" % int(action["item"]))
			_check_part(peer, int(action["item"]))
			text = "Restored the %s" % item_title(int(action["item"]))
		"repair_many":
			var n := 0
			for id in action["items"]:
				if items.has(int(id)) and (items[int(id)]["rust"] > 0.0 or items[int(id)]["wear"] > 0.0):
					_note_low(int(id))
					items[int(id)]["rust"] = 0.0
					items[int(id)]["wear"] = 0.0
					n += 1
					_xp(peer, "repair", 1.0, "item:%d" % int(id))
					_check_part(peer, int(id))
			c["repaired"] = int(c.get("repaired", 0)) + n
			text = "Restored %d part%s" % [n, "" if n == 1 else "s"] if n != 1 else "Restored the %s" % item_title(int(action["items"][0]))
		"adjust_chain":
			var chain := item_on(bike_id, "chain")
			var was := float(items[chain].get("slack", CHAIN_SLACK_SET))
			items[chain]["slack"] = CHAIN_SLACK_SET
			text = "Chain %s to %d mm of slack" % ["tightened" if was > CHAIN_SLACK_SET else "slackened off", roundi(CHAIN_SLACK_SET)]
			_xp(peer, "chain_tension", 1.0, "item:%d" % chain)
		"lube":
			# How well it went on: coverage along the chain, less any flung off where it was overdone.
			var chain := int(action["item"])
			var q := clampf(float(action.get("quality", 1.0)) + _finish_bonus(peer), 0.0, 1.0)
			var waste := clampf(float(action.get("waste", 0.0)), 0.0, 1.0)
			var can: Dictionary = items[held_by(peer)]["fluid"]
			can["litres"] = maxf(0.0, float(can["litres"]) - LUBE_USE * (1.0 + waste * 2.0))
			items[chain]["lube"] = maxf(float(items[chain].get("lube", 0.0)), lerpf(0.5, 1.0, q))
			items[chain]["lube_type"] = str(can["type"])
			text = "Lubed the chain with %s: %s" % [PartsDB.part_name(str(can["type"])), _job_word(q, waste, "lube")]
			_xp(peer, "chain_lube", q, "item:%d" % chain)
		"paint":
			var idx := clampi(int(action.get("color", 0)), 0, PAINTS.size() - 1)
			var finish := str(action.get("finish", "gloss"))
			if not FINISHES.has(finish):
				finish = "gloss"
			var it: Dictionary = items[int(action["item"])]
			it["color"] = PAINTS[idx]
			it["finish"] = finish
			# Showroom Shine (a skill) gives a better finish.
			var q := clampf(float(action.get("quality", 1.0)) + _finish_bonus(peer), 0.0, 1.0)
			var runs := clampf(float(action.get("waste", 0.0)), 0.0, 1.0)
			if it["at"] == "spot" and spot_role(str(it["ref"])) == "booth":
				# No dust settling in the wet paint: a booth gives a cleaner finish.
				var booth := furniture_of_spot(str(it["ref"]))
				q = minf(1.0, q + float(Equipment.get_model(str(booth["model"])).get("finish", 0.05)))
			it["paint_quality"] = q
			it["paint_runs"] = runs
			_bump(c, "painted")
			text = "Sprayed the %s %s: %s" % [item_title(int(action["item"])), paint_text(it).to_lower(), _job_word(q, runs, "paint")]
			_xp(peer, "paint", q, "item:%d" % int(action["item"]))
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
				text = "%s is on the dyno. Strap it down at the four posts (hold the work button), then tune and run it at the desk." % bikes[bike_id]["name"]
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
				var prog := _prog()
				if prog and float(prog.tune_reach(peer)) > float(bikes[bike_id].get("tune_reach", 0.0)):
					bikes[bike_id]["tune_reach"] = float(prog.tune_reach(peer))
				var r := build_of(bike_id).tune_range(key)
				if not holder.has("tune"):
					holder["tune"] = {}
				holder["tune"][field] = clampf(float(action["value"]), r.x, r.y)
			_xp(peer, "tune", 1.0, "%d:%s" % [bike_id, key])
		"lighten":
			var it: Dictionary = items[int(action["item"])]
			# Featherweight (a skill) takes a little more off.
			var prog := _prog()
			var extra: float = float(prog.lighten_bonus(peer)) if prog else 0.0
			var kg := float(PartsDB.get_part(str(it["part"])).get("mass", 0.0)) * BikeBuild.lighten_cut(str(it["part"]), extra)
			it["lightened"] = true
			if extra > 0.0:
				it["lighten_extra"] = extra
			_xp(peer, "lighten", 1.0, "item:%d" % int(action["item"]))
			it["wear"] = minf(1.0, float(it["wear"]) + LIGHTEN_WEAR)
			text = "Drilled and trimmed the %s: %.1f kg lighter, but a little weaker" % [item_title(int(action["item"])), kg]
		"dyno_run":
			var build := build_of(bike_id)
			var run := build.dyno_run()
			# Heat: the engine gets hotter every run, far hotter without the cooling fan, and a hot
			# engine makes less power as the sweep goes on.
			var fan := bool(dyno["fan"])
			dyno["heat"] = clampf(float(dyno["heat"]) + (DYNO_HEAT_FAN if fan else DYNO_HEAT_NO_FAN), 0.0, 1.0)
			_heat_run(run, float(dyno["heat"]))
			run["fan"] = fan
			run["hose"] = dyno["hose"] == "bike"
			if not fan and float(dyno["heat"]) > 0.6:
				# Cooking it costs a little engine life.
				var block := item_on(bike_id, "engine")
				if block != 0:
					items[block]["wear"] = minf(1.0, float(items[block]["wear"]) + 0.004)
			if dyno["hose"] != "bike":
				# No extraction: the room fills with exhaust.
				dyno["haze"] = clampf(float(dyno["haze"]) + 0.55, 0.0, 1.0)
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
			if dyno["hose"] != "bike":
				text += " No extraction hose on: the room's filling with fumes."
			if not fan and float(dyno["heat"]) > 0.5:
				text += " It's running hot: switch the fan on."
			_xp(peer, "dyno_run", 1.0, "bike:%d" % bike_id)
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
			_xp(peer, "fluids", 1.0, "item:%d" % int(action["item"]))
		"tip":
			var can: Dictionary = items[held_by(peer)]
			can["fluid"]["litres"] = 0.0
			can["fluid"]["age"] = 0.0
			text = "Tipped it away for recycling"
			_xp(peer, "tip")
		"wash":
			var n := 0
			# An upgraded pressure washer and Elbow Grease blast off more muck a pass.
			var prog := _prog()
			var jet := JET_CLEAN * (float(prog.jet_clean_mult(peer)) if prog else 1.0)
			var washing := {}     # bike id -> how muddy it was before this pass
			for id in action["items"]:
				if items.has(int(id)) and not items[int(id)].get("boxed", false) and items[int(id)]["dirt"] > 0.0:
					var on_bike := _bike_of(int(id))
					if on_bike != 0 and not washing.has(on_bike):
						washing[on_bike] = _bike_dirt(on_bike)
					_note_low(int(id))
					items[int(id)]["dirt"] = maxf(0.0, items[int(id)]["dirt"] - jet)
					if items[int(id)]["dirt"] == 0.0:
						n += 1
						_xp(peer, "wash_part", 1.0, "item:%d" % int(id))
						_check_part(peer, int(id))
			c["cleaned"] = int(c.get("cleaned", 0)) + n
			for b in washing:
				# The whole bike clean: more for a muddier one, and a one-off for a real mud monster.
				var peak := maxf(float(bikes[b].get("mud_peak", 0.0)), float(washing[b]))
				if _bike_dirt(b, true) < 0.02:
					bikes[b].erase("mud_peak")
					_xp(peer, "pressure_wash", 1.0 + 4.0 * peak, "bike:%d" % b)
					if peak > 0.25:
						_xp(peer, "muddy_wash", 1.0, "bike:%d" % b)
				else:
					bikes[b]["mud_peak"] = peak
		"geo_save", "geo_blueprint", "bp_rename", "bp_delete", "bp_build", "bp_cancel", "bp_order":
			text = _blueprint_apply(action, peer)
		"order":
			var id := _random_bike(free_bay(Workshop.bay_count()))
			# A project bike costs a little more than it would fetch as it comes (see Money).
			var cost := Money.project_price(id)
			if not charge_garage(cost, "Bought %s" % bikes[id]["name"]):
				remove_bike(id)
				_tell(peer, "The business can't afford a project bike: this one was %s, and it has %s." % [
					TvChannels.money_text(cost), TvChannels.money_text(garage_money)], false)
				changed.emit()
				return
			text = "%s has been delivered to bay %d, for %s" % [bikes[id]["name"], bikes[id]["bay"] + 1, TvChannels.money_text(cost)]
		"radio":
			radio = {"on": bool(action.get("on", radio["on"])), "station": int(action.get("station", radio["station"]))}
			text = "Radio: %s" % station_name() if radio["on"] else "Radio off"
		"status":
			c["tool"] = str(action.get("tool", c.get("tool", "")))
			c["activity"] = str(action.get("activity", "")).left(60)
			c["changer"] = int(action.get("changer", 0))   # the tyre changer they're working at, to spin it
		"ride":
			var bike := int(c.get("riding", 0))
			if bikes.has(bike):
				_wear_from_ride(bike, action)
			c["km"] = float(c.get("km", 0.0)) + clampf(float(action.get("km", 0.0)), 0.0, 5.0)
			c["top_kmh"] = maxf(float(c.get("top_kmh", 0.0)), clampf(float(action.get("top_kmh", 0.0)), 0.0, 400.0))
			c["kmh"] = clampf(float(action.get("kmh", 0.0)), 0.0, 400.0)
	if text != "":
		_tell(peer, text, true)
	_tidy_dyno()
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
		# Rolled onto the dyno: square on the drum, ready to strap down.
		bike["xf"] = rig
		bike["stand"] = ""
		return
	if _park_on_show(bike_id):
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
	# Tyres wear, faster at the wrong pressure, and a badly seated bead slowly lets one down.
	for side in ["front", "rear"]:
		var tyre := item_on(bike_id, side + "_tyre")
		if tyre != 0:
			items[tyre]["wear"] = minf(1.0, float(items[tyre]["wear"]) + km * TYRE_WEAR * float(build.tyre_wear[side]))
			var bead := float(items[tyre].get("bead", 1.0))
			if bead < BikeBuild.BEAD_OK and km > 0.0:
				var key := "psi_f" if side == "front" else "psi_r"
				var tune: Dictionary = items[tyre].get("tune", {})
				var psi := float(tune.get("pressure", build.tune_default(key)))
				tune["pressure"] = maxf(float(BikeBuild.TUNE_LIMITS[key][0]), psi - km * BEAD_LEAK * (1.0 - bead / BikeBuild.BEAD_OK))
				items[tyre]["tune"] = tune
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
	if not is_authority() and str(op.get("a", "")) in ["board_draw", "board_text", "board_image", "board_move"]:
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
		"board_image":
			var why := ""
			if BoardData.find(board, int(op["id"])) >= 0:
				return
			if BoardData.image_count(board) >= BoardData.MAX_IMAGES:
				why = "The board holds %d pictures at most. Rub one out or undo one first." % BoardData.MAX_IMAGES
			elif not image_ok(int(op["img"])):
				why = "That picture didn't arrive in one piece. Try adding it again."
			if why != "":
				# The author put it up on their own board straight away: take it back off there.
				if peer != me():
					_board_op.rpc_id(peer, {"a": "board_remove", "ids": [int(op["id"])]})
				_tell(peer, why, false)
				return
			BoardData.apply(board, op)
			# The picture's bytes go to everyone else first, then the mark that shows it.
			_send_blob(int(op["img"]), peer)
			_board_send(op)
		"board_move":
			# Anyone can move a picture. The mover has it there already (and the host may too,
			# when it's the host moving it), so it goes out whether or not it changed here.
			var k := BoardData.find(board, int(op["id"]))
			if k < 0 or not BoardData.is_image(board["marks"][k]):
				return
			BoardData.apply(board, op)
			_board_send(op, peer)
		"board_poster":
			_make_poster(peer, str(action.get("name", "")))
			return
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


# ---------------------------------------------------------------------------- pictures and posters

const BLOB_CHUNK := 24000        # bytes in each chunk sent, well inside what one message carries
const MAX_BLOB := 600000         # the biggest picture or poster print taken
const MAX_IMAGE_BYTES := 300000  # a picture from a player's PC, after it's been shrunk
const MAX_BLOBS := 64            # past this, data nothing uses any more is dropped
const MAX_POSTERS := 24
const MAX_INCOMING := 16         # pictures part-way through arriving at once
var _blob_in := {}               # blob id -> {from, n, parts: {i: bytes}} while it arrives
var _textures := {}              # blob id -> ImageTexture, made when first shown
var _marks_cache := {}           # blob id -> a poster print's marks, unpacked


func _clear_prints() -> void:
	blobs = {}
	posters = {}
	_blob_in = {}
	_textures = {}
	_marks_cache = {}


func new_blob_id() -> int:
	var id := 1 + randi() % 2000000000
	while blobs.has(id) or _blob_in.has(id):
		id = 1 + randi() % 2000000000
	return id


## Keeps `data` here as blob `id` and sends it on in chunks: a player's to the host, the host's
## to everyone. Send the op that uses it after this, so it arrives first.
func share_blob(id: int, data: PackedByteArray) -> void:
	_store_blob(id, data)
	if not Net.is_online():
		return
	if is_authority():
		_send_blob(id)
	else:
		_send_chunks(1, id, data)


## The host sends blob `id` to every player but `skip`.
func _send_blob(id: int, skip := 0) -> void:
	if not Net.is_online() or not is_authority() or not blobs.has(id):
		return
	for p in multiplayer.get_peers():
		if p != skip:
			_send_chunks(p, id, blobs[id])


func _send_chunks(to: int, id: int, data: PackedByteArray) -> void:
	var n := maxi(1, ceili(data.size() / float(BLOB_CHUNK)))
	for i in n:
		_blob_chunk.rpc_id(to, id, i, n, data.slice(i * BLOB_CHUNK, (i + 1) * BLOB_CHUNK))


## A player joining gets every picture and poster print in use, after the shed itself.
func _send_blobs_to(peer: int) -> void:
	for id in blobs_in_use():
		_send_chunks(peer, id, blobs[id])


@rpc("any_peer", "call_remote", "reliable")
func _blob_chunk(id: int, i: int, n: int, data: PackedByteArray) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not is_authority() and from != 1:
		return
	if id <= 0 or n <= 0 or i < 0 or i >= n or data.size() > BLOB_CHUNK or (n - 1) * BLOB_CHUNK >= MAX_BLOB:
		return
	if blobs.has(id):
		return
	var inc: Dictionary = _blob_in.get(id, {})
	if inc.is_empty() or int(inc["from"]) != from or int(inc["n"]) != n:
		if _blob_in.size() >= MAX_INCOMING:
			_blob_in.erase(_blob_in.keys()[0])
		inc = {"from": from, "n": n, "parts": {}}
		_blob_in[id] = inc
	inc["parts"][i] = data
	if inc["parts"].size() < n:
		return
	var all := PackedByteArray()
	for k in n:
		all.append_array(inc["parts"][k])
	_blob_in.erase(id)
	if all.size() <= MAX_BLOB:
		_store_blob(id, all)


func _store_blob(id: int, data: PackedByteArray) -> void:
	blobs[id] = data
	_textures.erase(id)
	_marks_cache.erase(id)
	if blobs.size() > MAX_BLOBS:
		# Drop the oldest that nothing uses, leaving the newest few (one may be on its way to the board).
		var used := blobs_in_use()
		var keys := blobs.keys()
		for k in keys.slice(0, maxi(0, keys.size() - 8)):
			if blobs.size() <= MAX_BLOBS:
				break
			if not used.has(k):
				blobs.erase(k)
	blob_arrived.emit(id)
	board_changed.emit()


## Every blob the board's pictures and the poster prints use.
func blobs_in_use() -> Array:
	var out := BoardData.images_in(board.get("marks", []))
	for d in posters:
		var p: Dictionary = posters[d]
		for id in [int(p.get("blob", 0))] + Array(p.get("imgs", [])):
			if not out.has(int(id)) and blobs.has(int(id)):
				out.append(int(id))
	return out.filter(func(id): return blobs.has(id))


## Whether blob `id` is a picture fit to put on the board.
func image_ok(id: int) -> bool:
	if not blobs.has(id) or (blobs[id] as PackedByteArray).size() > MAX_IMAGE_BYTES or not _is_webp(blobs[id]):
		return false
	var img := Image.new()
	if img.load_webp_from_buffer(blobs[id]) != OK:
		return false
	return maxi(img.get_width(), img.get_height()) <= BoardData.IMAGE_PX and img.get_width() > 0


## Whether `data` starts like a WebP file, before it's handed to the decoder.
static func _is_webp(data: PackedByteArray) -> bool:
	return data.size() > 12 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP"


## The picture in blob `id` to draw, or null while it hasn't arrived (or isn't a picture).
func image_texture(id: int) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	if not blobs.has(id) or not _is_webp(blobs[id]):
		return null
	var img := Image.new()
	if img.load_webp_from_buffer(blobs[id]) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_textures[id] = tex
	return tex


## Shrinks a picture from a player's PC to at most BoardData.IMAGE_PX on its longest side and
## packs it as WebP, small enough to send; an empty array when it can't be done.
static func pack_image(img: Image) -> PackedByteArray:
	if img == null or img.is_empty():
		return PackedByteArray()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var px := BoardData.IMAGE_PX
	while px >= 64:
		var copy := img.duplicate() as Image
		var longest := maxi(copy.get_width(), copy.get_height())
		if longest > px:
			var k := float(px) / longest
			copy.resize(maxi(1, roundi(copy.get_width() * k)), maxi(1, roundi(copy.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		var data := copy.save_webp_to_buffer(true, 0.8)
		if not data.is_empty() and data.size() <= MAX_IMAGE_BYTES:
			return data
		px = px * 3 / 4
	return PackedByteArray()


## Puts a picture (packed with pack_image) up on the whiteboard: the top left at `at` and `sz`
## across, in board pixels. Its bytes go out first, then the mark. Gives the mark's id.
func board_add_image(data: PackedByteArray, at: Vector2, sz: Vector2) -> int:
	if data.is_empty() or data.size() > MAX_IMAGE_BYTES:
		feedback.emit("That picture is too big to put up.", false)
		return 0
	if BoardData.image_count(board) >= BoardData.MAX_IMAGES:
		feedback.emit("The board holds %d pictures at most. Rub one out or undo one first." % BoardData.MAX_IMAGES, false)
		return 0
	var img_id := new_blob_id()
	share_blob(img_id, data)
	var id := 1 + randi() % 1000000000
	board_request({"a": "board_image", "id": id, "img": img_id, "at": at, "sz": sz})
	return id


## The host turns what's on the whiteboard now into a poster design for the parts computer.
func _make_poster(peer: int, poster_name: String) -> void:
	var marks: Array = board.get("marks", [])
	if marks.is_empty():
		_tell(peer, "The board is clean: draw something to make a poster of.", false)
		return
	poster_name = poster_name.strip_edges().left(32)
	if poster_name == "":
		poster_name = "Whiteboard poster %d" % (posters.size() + 1)
	var raw := var_to_bytes(marks)
	var data := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if data.size() > MAX_BLOB:
		_tell(peer, "There's too much on the board for one poster. Rub some out first.", false)
		return
	if posters.size() >= MAX_POSTERS:
		# Make room: the oldest design that isn't hanging on a wall goes.
		var hung := {}
		for f in furniture:
			hung[int(furniture[f].get("design", 0))] = true
		var gone := 0
		for d in posters:
			if not hung.has(int(d)):
				gone = int(d)
				break
		if gone == 0:
			_tell(peer, "The shop holds %d whiteboard posters, all of them on the walls." % MAX_POSTERS, false)
			return
		posters.erase(gone)
	var blob := new_blob_id()
	_store_blob(blob, data)
	_send_blob(blob)
	var id := _next_id
	_next_id += 1
	posters[id] = {"id": id, "name": poster_name, "by": str(crew.get(peer, {}).get("name", "Someone")), "blob": blob,
		"raw": raw.size(), "imgs": BoardData.images_in(marks)}
	_mark_dirty()
	changed.emit()
	_tell(peer, "Saved the board as the poster \"%s\". Order it from the parts computer: Shed, Wall posters." % poster_name, true)


## The marks a poster design shows, or [] while its print hasn't arrived.
func poster_marks(design: int) -> Array:
	var p: Dictionary = posters.get(design, {})
	var blob := int(p.get("blob", 0))
	if _marks_cache.has(blob):
		return _marks_cache[blob]
	if not blobs.has(blob):
		return []
	var raw := (blobs[blob] as PackedByteArray).decompress(clampi(int(p.get("raw", 0)), 1, 16000000), FileAccess.COMPRESSION_ZSTD)
	var marks = bytes_to_var(raw) if not raw.is_empty() else null
	var out := []
	if marks is Array:
		for m in marks:
			if m is Dictionary and m.has("id"):
				out.append(m)
	_marks_cache[blob] = out
	return out


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


# ---------------------------------------------------------------------------- XP (see Progress)

func _prog() -> Node:
	return get_node_or_null("/root/Progress")


## Gives `peer` XP for a job. Guarded so the shed works without Progress.
func _xp(peer: int, action: String, mult := 1.0, detail := "") -> void:
	var prog := _prog()
	if prog:
		prog.award(peer, action, mult, detail)


func _finish_bonus(peer: int) -> float:
	var prog := _prog()
	return float(prog.finish_bonus(peer)) if prog else 0.0


## The bike a part is on, directly or in its engine, or 0.
func _bike_of(item_id: int) -> int:
	var it: Dictionary = items.get(item_id, {})
	if it.is_empty():
		return 0
	if it["at"] == "bike":
		return int(it["ref"]) if bikes.has(int(it["ref"])) else 0
	if it["at"] == "engine":
		return _bike_of(int(it["ref"]))
	return 0


## How muddy a bike is: the average dirt of its parts, or the worst part's with `worst`.
func _bike_dirt(bike_id: int, worst := false) -> float:
	var total := 0.0
	var top := 0.0
	var n := 0
	for slot in PartsDB.SLOTS:
		var id := item_on(bike_id, slot)
		if id != 0:
			total += float(items[id]["dirt"])
			top = maxf(top, float(items[id]["dirt"]))
			n += 1
	return top if worst else total / maxf(n, 1)


func _health(item_id: int) -> float:
	return BikeBuild.part_health(condition_of(items[item_id]))


## Remembers that a part was in a bad way before work on it, so bringing it back pays.
func _note_low(item_id: int) -> void:
	if items.has(item_id) and _health(item_id) < 0.6:
		items[item_id]["xp_low"] = true


## After work on a part: a one-off for bringing a bad part back to like new, then the bike's milestones.
func _check_part(peer: int, item_id: int) -> void:
	if not items.has(item_id):
		return
	if items[item_id].get("xp_low", false) and _health(item_id) >= 0.95:
		items[item_id].erase("xp_low")
		_xp(peer, "restore_part", 1.0, "item:%d" % item_id)
	var bike_id := _bike_of(item_id)
	if bike_id != 0:
		_milestones(peer, bike_id)


func _note_stripped(bike_id: int, slot: String) -> void:
	if not bikes.has(bike_id):
		return
	var off: Array = bikes[bike_id].get("stripped", [])
	if not off.has(slot):
		off.append(slot)
	bikes[bike_id]["stripped"] = off


## A bike's big one-offs, each paid once per bike: the build complete (a scratch build, or a bike
## stripped of at least BUILD_STRIP parts and built back up), and a project brought back to max
## health (every part at 95% or better).
func _milestones(peer: int, bike_id: int) -> void:
	if not bikes.has(bike_id) or not is_complete(bike_id):
		return
	var bike: Dictionary = bikes[bike_id]
	var scratch: bool = bike.get("scratch", false) or bike.get("original_cond", {}).is_empty()
	if scratch or bike.get("stripped", []).size() >= BUILD_STRIP:
		_xp(peer, "build_complete", 1.0, "bike:%d" % bike_id)
	if scratch:
		_xp(peer, "scratch_build", 1.0, "bike:%d" % bike_id)
	if not scratch and _was_project(bike_id):
		for slot in PartsDB.SLOTS:
			var id := item_on(bike_id, slot)
			if id != 0 and _health(id) < 0.95:
				return
		_xp(peer, "max_health", 1.0, "bike:%d" % bike_id)


## Whether a bike came in tired enough for restoring it to count.
func _was_project(bike_id: int) -> bool:
	var cond: Dictionary = bikes[bike_id].get("original_cond", {})
	if cond.is_empty():
		return false
	var total := 0.0
	for slot in cond:
		total += BikeBuild.part_health(cond[slot])
	return total / cond.size() < 0.85



func _move(item_id: int, at: String, ref) -> void:
	items[item_id]["at"] = at
	items[item_id]["ref"] = ref
	# Where it sat on a surface goes with it (set_down gives it a new one).
	items[item_id].erase("place")


## Takes a part off a bike (whatever is mounted on it stays put) and puts it somewhere.
func _detach(bike_id: int, slot: String, at: String, ref) -> int:
	_note_stripped(bike_id, slot)
	var item_id: int = bikes[bike_id]["slots"][slot]
	bikes[bike_id]["slots"][slot] = 0
	bikes[bike_id]["bolted"][slot] = false
	_move(item_id, at, ref)
	return item_id


func _erase_item(item_id: int) -> void:
	var tyre := tyre_on_wheel(item_id)
	if tyre != 0:
		items.erase(tyre)
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


## Puts a part down on the workbench wherever there's room for it, along from the door end;
## failing that, in a free one of its old places.
func _put_on_bench(item_id: int) -> void:
	var length: float = (surface("bench")["rect"] as Rect2).size.x
	for i in 9:
		var place = find_room("bench", item_id, Vector2(-length * 0.5 + length * i / 8.0, 0.0))
		if place is Transform3D:
			_move(item_id, "spot", _free_surface_spot("bench"))
			items[item_id]["place"] = place
			return
	_move(item_id, "spot", _free_spot())


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
		var item_id := 0
		if slot == "tail":
			# The tail unit has aged with the frame it's bolted to.
			var frame: Dictionary = items[bike["slots"]["frame"]]
			item_id = _new_item(parts[slot], frame["rust"], minf(1.0, float(frame["dirt"]) * 1.2), frame["wear"])
		else:
			item_id = _aged_item(parts[slot], age, paint_color if slot in ["tank", "fairing"] else null)
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
		"original_cond": {}, "delivered": BikeBuild.new(parts, {}).summary(), "scratch": true}
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
	# Each tyre has to suit its rim: the same make where one fits, else any tyre that does.
	for ws in WHEEL_TYRE:
		var ts: String = WHEEL_TYRE[ws]
		var wheel := str(parts[ws])
		var picked := str(parts[ts])
		if PartsDB.tyre_fit(picked, wheel) == 0:
			continue
		var fits: Array = PartsDB.tyres_for(wheel)
		if fits.is_empty():
			continue
		var family := picked.get_slice("_", 0)
		var same: Array = fits.filter(func(t): return str(t).begins_with(family))
		var from: Array = same if not same.is_empty() else fits
		parts[ts] = from[_rng.randi() % from.size()]
	# A fairing goes on over a headlight, and fairing-mount mirrors need the fairing.
	if parts["headlight"] == "none":
		parts["fairing"] = "none"
	if parts["mirrors"] != "none" and not PartsDB.part_mounts("mirrors", parts["mirrors"]).all(func(m): return parts.get(m, "none") != "none"):
		parts["mirrors"] = "round_mirrors"
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
	_send_blobs_to(id)
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
	_tidy_dyno()
	_mark_dirty()
	changed.emit()


# ---------------------------------------------------------------------------- geometry and blueprints

## A bike's own fit for its parts (see GeoGizmo): slot -> {p, r, s}. Never shared between bikes.
func geometry_of(bike_id: int) -> Dictionary:
	var geo = bikes.get(bike_id, {}).get("geo", {})
	return geo if geo is Dictionary else {}


func blueprint_named(bp_name: String) -> int:
	for id in blueprints:
		if str(blueprints[id]["name"]).to_lower() == bp_name.strip_edges().to_lower():
			return int(id)
	return 0


## The bike standing in a bay (on or near its stand), or 0.
func bike_in_bay(bay: int) -> int:
	for id in bikes:
		if int(bikes[id].get("bay", -1)) == bay and bikes[id]["rider"] == 0 \
				and (bikes[id]["xf"] as Transform3D).origin.distance_to(Workshop.bay_transform(bay).origin) < 2.5:
			return int(id)
	return 0


## The blueprint build under way in a bay: its hologram waiting for a frame, or the plan carried
## by the bike being built there. Empty when there's none.
func plan_at(bay: int) -> Dictionary:
	if holograms.has(bay):
		return holograms[bay]
	var bike := bike_in_bay(bay)
	if bike != 0 and bikes[bike].get("blueprint") is Dictionary:
		return bikes[bike]["blueprint"]
	return {}


## Every bay with a blueprint build under way.
func plan_bays() -> Array:
	var out := []
	for bay in Workshop.bay_count():
		if not plan_at(bay).is_empty():
			out.append(bay)
	return out


## The bike a bay's blueprint build is on, or 0 while its hologram still waits for a frame.
func plan_bike(bay: int) -> int:
	return 0 if holograms.has(bay) else bike_in_bay(bay)


## A blueprint build's checklist: one row per part on the blueprint, {slot, part, name, state},
## where state is "fitted" (that part is on), "other" (a different part fills the slot), "ordered"
## (delivered or on its way) or "needed".
func plan_rows(plan: Dictionary, bike_id: int) -> Array:
	var rows := []
	var parts: Dictionary = plan.get("parts", {})
	var ordered: Dictionary = plan.get("ordered", {}) if plan.get("ordered") is Dictionary else {}
	for slot in PartsDB.SLOTS:
		var part := str(parts.get(slot, "none"))
		if part == "none" or part == "" or PartsDB.get_part(part).is_empty():
			continue
		var state := "needed"
		var on := item_on(bike_id, slot) if bike_id != 0 and bikes.has(bike_id) else 0
		if on != 0:
			state = "fitted" if str(items[on]["part"]) == part else "other"
		elif ordered.has(slot) and items.has(int(ordered[slot])):
			var it: Dictionary = items[int(ordered[slot])]
			# Fitted to some other bike since, it doesn't count any more.
			if not (it["at"] == "bike" and int(it["ref"]) != bike_id):
				state = "ordered"
		rows.append({"slot": slot, "part": part, "name": PartsDB.part_name(part), "state": state})
	return rows


## What a part costs new, in pounds (see Money.part_price).
static func part_price(part_id: String) -> int:
	return Money.part_price(part_id)


func _blueprint_check(action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var bike_id := int(action.get("bike", 0))
	match a:
		"geo_save", "geo_blueprint":
			if not bikes.has(bike_id):
				return "That bike has gone."
			if bikes[bike_id]["rider"] != 0:
				return "Someone is riding that bike."
			if not (action.get("geo") is Dictionary):
				return "There's nothing to save."
			if a == "geo_blueprint":
				var n := str(action.get("name", "")).strip_edges()
				if n == "":
					return "Give the blueprint a name."
				if blueprints.size() >= MAX_BLUEPRINTS and blueprint_named(n) == 0:
					return "There are %d blueprints already. Delete one first (Esc, Blueprints)." % MAX_BLUEPRINTS
		"bp_rename", "bp_delete", "bp_build":
			if not blueprints.has(int(action.get("bp", 0))):
				return "That blueprint has gone."
			if a == "bp_rename":
				var n := str(action.get("name", "")).strip_edges()
				if n == "":
					return "Give it a name."
				var other := blueprint_named(n)
				if other != 0 and other != int(action["bp"]):
					return "There's already a blueprint called %s." % n
			if a == "bp_build":
				var bay := int(action.get("bay", -1))
				if bay < 0 or bay >= Workshop.bay_count():
					return "Pick a bay."
				if not bay_is_free(bay) or holograms.has(bay):
					return "Bay %d isn't empty. Pick an empty bay." % (bay + 1)
		"bp_cancel":
			if plan_at(int(action.get("bay", -1))).is_empty():
				return "There's no blueprint build in that bay."
		"bp_order":
			var bay := int(action.get("bay", -1))
			if bay >= 0 and plan_at(bay).is_empty():
				return "There's no blueprint build in that bay."
			if bay < 0 and plan_bays().is_empty():
				return "No blueprint builds under way. Start one from the Esc menu: Build from blueprint."
	return ""


func _blueprint_apply(action: Dictionary, peer := 1) -> String:
	var a := str(action.get("a", ""))
	var bike_id := int(action.get("bike", 0))
	match a:
		"geo_save":
			bikes[bike_id]["geo"] = GeoGizmo.sanitize(action["geo"])
			return "Saved the fit of %s's parts." % bikes[bike_id]["name"]
		"geo_blueprint":
			bikes[bike_id]["geo"] = GeoGizmo.sanitize(action["geo"])
			var bp := _save_blueprint(bike_id, str(action["name"]).strip_edges().left(28))
			return "Saved the fit of %s's parts, and the blueprint \"%s\" (Esc, Build from blueprint)." % [
				bikes[bike_id]["name"], blueprints[bp]["name"]]
		"bp_rename":
			blueprints[int(action["bp"])]["name"] = str(action["name"]).strip_edges().left(28)
			return "Renamed the blueprint %s." % blueprints[int(action["bp"])]["name"]
		"bp_delete":
			var gone := str(blueprints[int(action["bp"])]["name"])
			blueprints.erase(int(action["bp"]))
			return "Deleted the blueprint %s." % gone
		"bp_build":
			var bp := int(action["bp"])
			var bay := int(action["bay"])
			var plan: Dictionary = blueprints[bp].duplicate(true)
			plan.erase("id")
			plan["bp"] = bp
			plan["bay"] = bay
			plan["ordered"] = {}
			holograms[bay] = plan
			return "A hologram of %s is in bay %d. Order the missing parts at the parts computer, then put a frame on the stand and build it up." % [
				plan["name"], bay + 1]
		"bp_cancel":
			var bay := int(action["bay"])
			var plan := plan_at(bay)
			var what := str(plan.get("name", "the bike"))
			holograms.erase(bay)
			var bike := bike_in_bay(bay)
			if bike != 0:
				bikes[bike].erase("blueprint")
			return "Cancelled the blueprint build of %s in bay %d." % [what, bay + 1]
		"bp_order":
			var bays: Array = [int(action.get("bay", -1))] if int(action.get("bay", -1)) >= 0 else plan_bays()
			var sent := 0
			var left := 0
			var broke := 0
			var spent := 0
			for bay in bays:
				var got := _order_plan(plan_at(bay), plan_bike(bay), peer)
				sent += int(got[0])
				left += int(got[1])
				broke += int(got[2])
				spent += int(got[3])
			if sent == 0 and left == 0 and broke == 0:
				return "Everything on the blueprint is fitted or already ordered."
			var said := "Ordered %d part%s for the blueprint, for %s. They're boxed outside the roller door." % [sent,
				"" if sent == 1 else "s", TvChannels.money_text(spent)]
			if left > 0:
				said += " %d more didn't fit in the delivery area: bring some boxes in and order again." % left
			if broke > 0:
				said += " The business couldn't afford %d more." % broke
			return said
	return ""


## Stores what a bike is now as a blueprint: its parts (what it was delivered with where a slot
## is empty), each part's colour and finish, its paint and its parts' fit. One with the same
## name is replaced.
func _save_blueprint(bike_id: int, bp_name: String) -> int:
	var bike: Dictionary = bikes[bike_id]
	var parts := {}
	var colors := {}
	for slot in PartsDB.SLOTS:
		var on := item_on(bike_id, slot)
		if on != 0:
			parts[slot] = str(items[on]["part"])
			colors[slot] = {"color": items[on]["color"], "finish": str(items[on].get("finish", ""))}
		elif PartsDB.is_optional(slot):
			parts[slot] = "none"
		else:
			parts[slot] = str(bike.get("original", {}).get(slot, PartsDB.DEFAULT_BUILD.get(slot, "none")))
	var id := blueprint_named(bp_name)
	if id == 0:
		id = _next_id
		_next_id += 1
	blueprints[id] = {"id": id, "name": bp_name, "parts": parts, "colors": colors, "paint": bike["paint"],
		"geo": geometry_of(bike_id).duplicate(true), "from": str(bike["name"])}
	return id


## Orders whatever a blueprint build still needs, boxed outside the roller door in the
## blueprint's colours, each paid for by the business. Returns [parts ordered, parts that didn't
## fit in the delivery area, parts the business couldn't afford, pounds spent].
func _order_plan(plan: Dictionary, bike_id: int, peer := 1) -> Array:
	if plan.is_empty():
		return [0, 0, 0, 0]
	if not (plan.get("ordered") is Dictionary):
		plan["ordered"] = {}
	var sent := 0
	var left := 0
	var broke := 0
	var spent := 0
	var colors: Dictionary = plan.get("colors", {})
	for row in plan_rows(plan, bike_id):
		if row["state"] != "needed":
			continue
		var xf = free_delivery_xf()
		if xf == null:
			left += 1
			continue
		var part: String = row["part"]
		var cost := Money.buy_price(part, peer)
		if not charge_garage(cost, "Bought %s" % PartsDB.part_name(part)):
			broke += 1
			continue
		spent += cost
		var look: Dictionary = colors.get(row["slot"], {})
		var item_id := _new_item(part, 0.0, 0.0, 0.0, look.get("color"))
		items[item_id]["finish"] = str(look.get("finish", ""))
		items[item_id]["boxed"] = not PartsDB.is_fluid(part)
		_move(item_id, "floor", xf)
		plan["ordered"][row["slot"]] = item_id
		sent += 1
	return [sent, left, broke, spent]


## A frame has gone on a bay with a hologram waiting: the new bike takes on the blueprint's
## name, paint and fit, and carries the plan until it's built.
func _start_blueprint(bike_id: int, bay: int) -> String:
	var plan: Dictionary = holograms[bay]
	holograms.erase(bay)
	var bike: Dictionary = bikes[bike_id]
	bike["blueprint"] = plan
	bike["geo"] = GeoGizmo.sanitize(plan.get("geo", {}))
	bike["name"] = str(plan.get("name", bike["name"]))
	if plan.get("paint") is Color:
		bike["paint"] = plan["paint"]
	# The blueprint is what it's being built to: its numbers are what the bay screen compares with.
	var original: Dictionary = PartsDB.sanitize_build(plan.get("parts", {}).duplicate())
	original["frame"] = items[int(bike["slots"]["frame"])]["part"]
	bike["original"] = original
	bike["delivered"] = BikeBuild.new(original, {}).summary()
	_blueprint_done(bike_id)
	return "%s is on the stand in bay %d. Fit the parts the hologram shows: each ghost part goes as the real one goes on." % [
		bike["name"], bay + 1]


## Whether a bike being built to a blueprint now has every part on it; if so its plan (and
## hologram) goes and it keeps the blueprint's fit.
func _blueprint_done(bike_id: int) -> bool:
	if not bikes.has(bike_id) or not (bikes[bike_id].get("blueprint") is Dictionary):
		return false
	for row in plan_rows(bikes[bike_id]["blueprint"], bike_id):
		if not (row["state"] in ["fitted", "other"]):
			return false
	bikes[bike_id].erase("blueprint")
	return true


# ---------------------------------------------------------------------------- garage upgrades

## Buys a garage upgrade with the garage's money (already checked): takes the money, adds the
## upgrade and anything it comes with (the racking), and pays the buyer XP.
func _buy_upgrade(peer: int, id: String, chosen = null) -> String:
	var cost := GarageUpgrades.price(id)
	var paid := false
	if has_method("charge_garage"):
		paid = bool(call("charge_garage", cost, "Garage upgrade: " + GarageUpgrades.title(id)))
	elif garage_money >= cost:
		garage_money -= cost
		paid = true
	if not paid:
		return "The garage can't afford the %s." % GarageUpgrades.title(id).to_lower()
	upgrades[id] = true
	if GarageUpgrades.has_options(id):
		looks[id] = GarageUpgrades.clean_looks(id, chosen)
	if id == "racking":
		for xf in GarageUpgrades.racking_xfs():
			_new_furniture("shelf", xf, "shelf_racking")
	_xp(peer, GarageUpgrades.XP_KEY, GarageUpgrades.award_mult(id))
	return "%s bought for %s" % [GarageUpgrades.title(id), TvChannels.money_text(cost)]


## Changes the look of a finish already bought (already checked), for a small fee.
func _restyle_upgrade(id: String, chosen) -> String:
	var fee := GarageUpgrades.restyle_fee(id)
	var paid := false
	if has_method("charge_garage"):
		paid = bool(call("charge_garage", fee, "Restyled: " + GarageUpgrades.title(id)))
	elif garage_money >= fee:
		garage_money -= fee
		paid = true
	if not paid:
		return "The garage can't afford to change the %s." % GarageUpgrades.title(id).to_lower()
	looks[id] = GarageUpgrades.clean_looks(id, chosen)
	return "%s changed to %s for %s" % [GarageUpgrades.title(id), GarageUpgrades.looks_text(id, looks[id]).to_lower(),
		TvChannels.money_text(fee)]


# ---------------------------------------------------------------------------- syncing

func _mark_dirty() -> void:
	_dirty = true


## The whole shed. The regular syncs leave the whiteboard out: its marks go out one by one
## as they're drawn (_board_op), and whole only to players joining.
func _snapshot(with_board := true) -> Dictionary:
	var state := {"bikes": bikes, "items": items, "crew": crew, "furniture": furniture, "radio": radio, "next": _next_id,
		"door": door_open, "lights": lights_on, "room_lights": room_lights, "screens": screens, "posters": posters, "dyno": dyno,
		"blueprints": blueprints, "holograms": holograms, "garage_money": garage_money, "bank": bank, "contracts": contracts, "upgrades": upgrades, "looks": looks}
	if with_board:
		state["board"] = board
	return state


## The whole shed as a save keeps it: the snapshot plus every picture and poster print still in
## use (players joining get those in chunks instead, see _send_blobs_to).
func save_snapshot() -> Dictionary:
	var state := _snapshot()
	var keep := {}
	for id in blobs_in_use():
		keep[id] = Marshalls.raw_to_base64(blobs[id])   # far smaller in the text save than a byte list
	state["blobs"] = keep
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
	garage_money = clampi(int(state.get("garage_money", 0)), 0, MAX_GARAGE_MONEY)
	# Sheds saved before money (no bank yet) open the account with the starting funds.
	if not state.has("bank"):
		garage_money = maxi(garage_money, Money.START_FUNDS)
	bank = Money.sanitize(state.get("bank"))
	if not state.has("bank"):
		Money._mark_milestones(bank, garage_money)
	# Sheds saved before contracts have no customers or jobs.
	contracts = Contracts.sanitize(state.get("contracts"))
	# Sheds saved before garage upgrades have none.
	upgrades = GarageUpgrades.sanitize(state.get("upgrades", {}))
	# Sheds saved before the finishes had choices keep their looks as they were.
	looks = GarageUpgrades.sanitize_looks(state.get("looks", {}), upgrades)
	# Sheds saved before the side rooms had switches: their lights start on.
	room_lights = {"paint": true, "storage": true}
	var saved_rooms = state.get("room_lights", {})
	if saved_rooms is Dictionary:
		for room in LIT_ROOMS:
			if saved_rooms.has(room):
				room_lights[room] = bool(saved_rooms[room])
	screens = state["screens"] if state.get("screens") is Dictionary else {}
	dyno = dyno_defaults()
	_dyno_busy_until = 0
	if state.get("dyno") is Dictionary:
		dyno.merge(state["dyno"], true)
	_next_id = int(state.get("next", 1))
	posters = state["posters"] if state.get("posters") is Dictionary else {}
	# Sheds saved before blueprints have none.
	blueprints = state["blueprints"] if state.get("blueprints") is Dictionary else {}
	holograms = state["holograms"] if state.get("holograms") is Dictionary else {}
	if state.get("blobs") is Dictionary:
		# A save being opened: its pictures and poster prints.
		for id in state["blobs"]:
			var data = state["blobs"][id]
			if data is String:
				data = Marshalls.base64_to_raw(data)
			if data is PackedByteArray and not data.is_empty() and data.size() <= MAX_BLOB:
				blobs[int(id)] = data
	if state.get("board", null) is Dictionary:
		board = state["board"]
		board_changed.emit()
	active = true
	changed.emit()


func _process(delta: float) -> void:
	if not active or not is_authority():
		return
	_cool_dyno(delta)
	_money_clock()
	Contracts.process(delta)
	# Parts washers slowly clean whatever is in them.
	for id in furniture:
		if furniture[id]["kind"] != "washer":
			continue
		var rate := float(Equipment.get_model(str(furniture[id]["model"])).get("rate", 0.18))
		# Piled up past what it's rated for, each part takes longer (see load_factor).
		var busy := 0
		for spot in furniture_spots(id):
			var w := item_at_spot(spot)
			if w != 0 and items[w]["dirt"] > 0.0 and not items[w].get("boxed", false):
				busy += 1
		rate /= load_factor(busy, Equipment.places(str(furniture[id]["model"])))
		for spot in furniture_spots(id):
			var washing := item_at_spot(spot)
			if washing != 0 and items[washing]["dirt"] > 0.0 and not items[washing].get("boxed", false):
				items[washing]["dirt"] = maxf(0.0, items[washing]["dirt"] - rate * delta)
				_mark_dirty()
				if items[washing]["dirt"] == 0.0:
					# Whoever put it in gets the credit.
					if _washer_by.has(washing) and crew.has(int(_washer_by[washing])):
						_xp(int(_washer_by[washing]), "washer", 1.0, "item:%d" % washing)
						_check_part(int(_washer_by[washing]), washing)
					_washer_by.erase(washing)
					changed.emit()
	_sync_timer -= delta
	if _dirty and _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_dirty = false
		if Net.is_online():
			_sync.rpc(_snapshot(false))
		changed.emit()


# ---------------------------------------------------------------------------- money (see Money)

## Host: takes `amount` from the business's account for `reason`. False, and nothing taken, when
## it can't afford it.
func charge_garage(amount: int, reason: String) -> bool:
	if not is_authority() or amount < 0:
		return false
	if amount == 0:
		return true
	if garage_money < amount:
		return false
	garage_money -= amount
	Money.log_entry(bank, -amount, reason, garage_money)
	_mark_dirty()
	changed.emit()
	return true


## Host: money into the business's account (sales, contracts, the cut of wages, money sent in).
## The first time the account reaches each of Money.MILESTONES the whole crew gets XP for it.
func credit_garage(amount: int, reason: String) -> void:
	if not is_authority() or amount <= 0:
		return
	garage_money = mini(garage_money + amount, MAX_GARAGE_MONEY)
	Money.log_entry(bank, amount, reason, garage_money)
	for m in Money._mark_milestones(bank, garage_money):
		for p in crew:
			_xp(int(p), "money_milestone", 1.0, "bank:%d" % int(m))
			_tell(int(p), "The business has reached %s!" % TvChannels.money_text(int(m)), true)
	_mark_dirty()
	changed.emit()


## Host: pays `peer` a wage of `gross` pounds for a job: the business keeps its cut (bank.cut %),
## the worker gets the rest in their own cash. A worker who's gone leaves it all to the business.
func pay_worker(peer: int, gross: int, reason: String) -> void:
	if not is_authority() or gross <= 0:
		return
	var cut := Money.cut_of(gross, int(bank["cut"]))
	if not give_cash(peer, gross - cut, reason):
		cut = gross
	credit_garage(cut, "Cut of %s's wages" % str(crew.get(peer, {}).get("name", "the crew")))


## Host: hands a player cash (see Progress.give_cash). False when they couldn't get it.
func give_cash(peer: int, amount: int, reason: String) -> bool:
	if amount <= 0:
		return true
	var prog := _prog()
	return bool(prog.give_cash(peer, amount, reason)) if prog else false


## Takes a whole bike out of the shed, every part on it with it (sold, or a delivery called off).
func remove_bike(bike_id: int) -> void:
	if not bikes.has(bike_id):
		return
	for slot in PartsDB.SLOTS:
		if not PartsDB.is_engine_slot(slot):
			var id := item_on(bike_id, slot)
			if id != 0:
				_erase_item(id)
	for p in crew:
		if int(crew[p].get("riding", 0)) == bike_id:
			crew[p]["riding"] = 0
	bikes.erase(bike_id)
	_mark_dirty()


## A "money_*" request (see Money.check and Money.apply). Money a player sent that can't be
## passed on goes back to them.
func _money_apply(peer: int, action: Dictionary) -> void:
	var why := Money.check(peer, action)
	if why != "":
		if str(action.get("a", "")) == "money_send" and int(action.get("amount", 0)) > 0:
			give_cash(peer, mini(int(action["amount"]), Progress.MAX_MONEY), "Sent back")
		_tell(peer, why, false)
		return
	var text := Money.apply(peer, action)
	if text != "":
		_tell(peer, text, true)
	_tidy_dyno()
	_mark_dirty()
	changed.emit()


## Host: a new day starts when the clock passes midnight: loan repayments come out (see Money.new_day).
func _money_clock() -> void:
	if Daylight.current == null:
		_clock_hours = -1.0
		return
	var h := Daylight.time_of_day()
	if _clock_hours >= 0.0 and h < _clock_hours - 12.0:
		money_new_day()
	_clock_hours = h


## Host: moves the business on a day (the clock does this at midnight; tests call it).
func money_new_day() -> void:
	if not is_authority():
		return
	var said := Money.new_day()
	if said != "":
		for p in crew:
			_tell(int(p), said, not said.contains("MISSED"))
	_mark_dirty()
	changed.emit()


# ---------------------------------------------------------------------------- sales office

## The sales office's door bell rang (everyone hears it: see ring_bell).
signal bell_rang
## How many times the bell has rung here this session (for tests).
var bells_heard := 0


## Host-side: rings the sales office's door bell for every player, the shop bell over its doors
## and the chime in the shed (Sfx.bell). Customers coming in ring it.
func ring_bell() -> void:
	if not is_authority():
		return
	_bell()
	if Net.is_online():
		_bell_rpc.rpc()


@rpc("authority", "call_remote", "reliable")
func _bell_rpc() -> void:
	_bell()


func _bell() -> void:
	bells_heard += 1
	Sfx.bell(SalesOffice.BELL_POS)
	bell_rang.emit()


## Which showroom plinth a bike is on, or -1.
func showroom_spot_of(bike_id: int) -> int:
	if not bikes.has(bike_id):
		return -1
	var i := SalesOffice.spot_near((bikes[bike_id]["xf"] as Transform3D).origin)
	if i >= 0 and (bikes[bike_id]["xf"] as Transform3D).origin.distance_to(SalesOffice.SHOWROOM_SPOTS[i].origin) < 0.05:
		return i
	return -1


## A bike let go of by a free showroom plinth goes onto it, square and upright, on show.
func _park_on_show(bike_id: int) -> bool:
	var bike: Dictionary = bikes[bike_id]
	var i := SalesOffice.spot_near((bike["xf"] as Transform3D).origin)
	if i < 0:
		return false
	var spot: Transform3D = SalesOffice.SHOWROOM_SPOTS[i]
	for id in bikes:
		if id != bike_id and bikes[id]["rider"] == 0 and (bikes[id]["xf"] as Transform3D).origin.distance_to(spot.origin) < 1.2:
			return false
	bike["xf"] = spot
	bike["stand"] = ""
	return true
