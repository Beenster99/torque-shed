extends Node
## The shared state of the shed: every bike, every loose part and what each player is doing.
## The host owns it. Players ask for changes with request(); the host checks each one,
## applies it and sends the new state to everyone, so two people working on the same bike
## always agree on which bolts are done up.

signal changed
signal feedback(text: String, ok: bool)

const SPOTS: Array[String] = ["bench_0", "bench_1", "bench_2", "bench_3", "bench_4", "bench_5", "washer", "repair"]
const PAINTS := [Color(0.78, 0.09, 0.08), Color(0.1, 0.35, 0.8), Color(0.95, 0.6, 0.05), Color(0.1, 0.6, 0.3),
	Color(0.55, 0.15, 0.7), Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), Color(0.0, 0.6, 0.7)]
const BIKE_NAMES := ["Barn Find", "Rusty Ranger", "Basket Case", "Old Faithful", "The Widowmaker", "Rattler",
	"Hedge Hopper", "Midnight Special", "Scrapyard Dog", "Grandad's Pride", "Mud Puppy", "Iron Maiden"]
const WASH_RATE := 0.18        # dirt removed per second in the parts washer
const SYNC_INTERVAL := 0.1

var bikes := {}     # bike id -> {id, name, paint, slots{slot: item id or 0}, bolted{slot: bool}, rider, xf, delivered}
var items := {}     # item id -> {id, part, slot, rust, dirt, wear, at ("bike" | "held" | "spot"), ref}
var crew := {}      # peer id -> {name, tool, activity, riding, fitted, removed, cleaned, repaired, km, top_kmh}
var active := false

var _next_id := 1
var _dirty := false
var _sync_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
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
	items.clear()
	crew.clear()
	_next_id = 1
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	active = true
	_add_crew(me(), player_name)
	_new_bike({"frame": "steel_backbone", "fork": "enduro_usd", "shock": "enduro_mono", "wheels": "knobbly_21_18",
		"brakes": "wave_disc_mx", "engine": "single_450", "intake": "stock_airbox", "exhaust": "stock_muffler",
		"gearbox": "six_wide_enduro", "final_drive": "mx_13_52"}, 0, "Rusty Ranger", 0.75)
	var cafe := _new_bike({"frame": "steel_cradle", "fork": "classic_conventional", "shock": "twin_shock",
		"wheels": "road_17", "brakes": "drum_brakes", "engine": "twin_700", "intake": "stock_airbox",
		"exhaust": "stock_muffler", "gearbox": "four_vintage", "final_drive": "stock_15_45"}, 1, "Barn Find", 0.6)
	# The barn find arrives half stripped: its exhaust, brakes and wheels are on the bench.
	for slot in ["exhaust", "brakes", "wheels"]:
		var item_id: int = bikes[cafe]["slots"][slot]
		bikes[cafe]["slots"][slot] = 0
		bikes[cafe]["bolted"][slot] = false
		_move(item_id, "spot", _free_spot_from(0))
	_new_bike({"frame": "alu_twin_spar", "fork": "usd_sport", "shock": "sport_mono", "wheels": "road_17",
		"brakes": "twin_disc_sport", "engine": "four_1000", "intake": "fuel_injection", "exhaust": "slip_on",
		"gearbox": "six_close", "final_drive": "stock_15_45"}, 2, "Old Faithful", 0.35)
	_mark_dirty()
	changed.emit()


func join_remote() -> void:
	bikes.clear()
	items.clear()
	crew.clear()
	active = true


func stop() -> void:
	active = false
	bikes.clear()
	items.clear()
	crew.clear()
	changed.emit()


# ---------------------------------------------------------------------------- queries

func item_on(bike_id: int, slot: String) -> int:
	if not bikes.has(bike_id):
		return 0
	return int(bikes[bike_id]["slots"].get(slot, 0))


func is_bolted(bike_id: int, slot: String) -> bool:
	return bikes.has(bike_id) and bool(bikes[bike_id]["bolted"].get(slot, false))


func held_by(peer: int) -> int:
	for id in items:
		if items[id]["at"] == "held" and items[id]["ref"] == peer:
			return id
	return 0


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


func missing_slots(bike_id: int) -> Array:
	var out := []
	for slot in PartsDB.SLOTS:
		if item_on(bike_id, slot) == 0:
			out.append(slot)
	return out


func loose_slots(bike_id: int) -> Array:
	var out := []
	for slot in PartsDB.SLOTS:
		if item_on(bike_id, slot) != 0 and not is_bolted(bike_id, slot):
			out.append(slot)
	return out


func is_complete(bike_id: int) -> bool:
	return bikes.has(bike_id) and missing_slots(bike_id).is_empty() and loose_slots(bike_id).is_empty()


func condition_of(item: Dictionary) -> Dictionary:
	return {"rust": item["rust"], "dirt": item["dirt"], "wear": item["wear"]}


## The bike's build from the parts on it. Missing parts fall back to what it was delivered
## with, so the numbers stay comparable. `swap` puts a loose item in its slot for previews.
func build_of(bike_id: int, swap := 0) -> BikeBuild:
	var bike: Dictionary = bikes[bike_id]
	var parts: Dictionary = bike["original"].duplicate()
	var cond := {}
	for slot in PartsDB.SLOTS:
		var item_id := item_on(bike_id, slot)
		if item_id != 0:
			parts[slot] = items[item_id]["part"]
			cond[slot] = condition_of(items[item_id])
	if swap != 0 and items.has(swap):
		var it: Dictionary = items[swap]
		parts[it["slot"]] = it["part"]
		cond[it["slot"]] = condition_of(it)
	return BikeBuild.new(parts, cond)


func fitted_map(bike_id: int) -> Dictionary:
	var out := {}
	for slot in PartsDB.SLOTS:
		out[slot] = item_on(bike_id, slot) != 0
	return out


func item_title(item_id: int) -> String:
	if not items.has(item_id):
		return ""
	var it: Dictionary = items[item_id]
	return PartsDB.part_name(it["part"])


func condition_text(item: Dictionary) -> String:
	return "Condition %d%%   Rust %d%%   Dirt %d%%   Wear %d%%" % [
		roundi(BikeBuild.part_health(condition_of(item)) * 100.0), roundi(item["rust"] * 100.0),
		roundi(item["dirt"] * 100.0), roundi(item["wear"] * 100.0)]


func free_bay(bay_count: int) -> int:
	for bay in bay_count:
		var taken := false
		for id in bikes:
			if bikes[id]["bay"] == bay and bikes[id]["xf"].origin.distance_to(Workshop.bay_transform(bay).origin) < 2.5:
				taken = true
		if not taken:
			return bay
	return -1


## Why `peer` can't do `action` right now, or "" when they can.
func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var held := held_by(peer)
	var bike_id := int(action.get("bike", 0))
	var slot := str(action.get("slot", ""))
	if a in ["unbolt", "bolt", "remove", "install", "mount"]:
		if not bikes.has(bike_id):
			return "That bike has gone."
		if bikes[bike_id]["rider"] != 0:
			return "Someone is riding that bike."
	match a:
		"unbolt", "bolt", "remove":
			var item_id := item_on(bike_id, slot)
			if item_id == 0:
				return "That part isn't fitted."
			if a == "unbolt" and not is_bolted(bike_id, slot):
				return "It's already unbolted."
			if a == "bolt" and is_bolted(bike_id, slot):
				return "It's already bolted up."
			if a == "remove":
				if held != 0:
					return "Your hands are full."
				if is_bolted(bike_id, slot):
					return "Unbolt it with the wrench first."
				for dep in PartsDB.dependents(slot):
					if item_on(bike_id, dep) != 0:
						return "Take the %s off first." % PartsDB.SLOT_NAMES[dep].to_lower()
		"install":
			if held == 0:
				return "You're not holding a part."
			var s: String = items[held]["slot"]
			if item_on(bike_id, s) != 0:
				return "There's already a %s fitted." % PartsDB.SLOT_NAMES[s].to_lower()
			for m in PartsDB.MOUNTS[s]:
				if item_on(bike_id, m) == 0:
					return "Fit the %s first." % PartsDB.SLOT_NAMES[m].to_lower()
		"take":
			if held != 0:
				return "Your hands are full."
			if item_at_spot(str(action.get("spot", ""))) == 0:
				return "Nothing there."
		"place":
			if held == 0:
				return "You're not holding a part."
			if not SPOTS.has(str(action.get("spot", ""))):
				return "You can't put it there."
			if item_at_spot(str(action.get("spot", ""))) != 0:
				return "That spot is taken."
		"shelf_take":
			if held != 0:
				return "Your hands are full."
			if PartsDB.get_part(str(action.get("part", ""))).is_empty():
				return "Unknown part."
		"bin":
			if held == 0:
				return "You're not holding a part."
		"clean", "repair":
			var item_id := int(action.get("item", 0))
			if not items.has(item_id):
				return "That part has gone."
			var it: Dictionary = items[item_id]
			if it["at"] == "held":
				return "Put it down first."
			if a == "clean" and it["dirt"] < 0.02:
				return "It's already clean."
			if a == "repair":
				if not (it["at"] == "spot" and it["ref"] == "repair"):
					return "Put the part on the repair bench first."
				if it["rust"] < 0.02 and it["wear"] < 0.02:
					return "It's already in top condition."
		"mount":
			if riding(peer) != 0:
				return "You're already riding."
			if held != 0:
				return "Put the part down first."
			var missing := missing_slots(bike_id)
			if not missing.is_empty():
				return "Missing: %s." % ", ".join(missing.map(func(m): return PartsDB.SLOT_NAMES[m].to_lower()))
			var loose := loose_slots(bike_id)
			if not loose.is_empty():
				return "Not bolted up: %s." % ", ".join(loose.map(func(m): return PartsDB.SLOT_NAMES[m].to_lower()))
		"dismount":
			if not bikes.has(bike_id) or bikes[bike_id]["rider"] != peer:
				return "You're not riding that bike."
		"order":
			if free_bay(Workshop.BAY_COUNT) < 0:
				return "Every bay is full. Ride a bike out or strip one down first."
		"status", "ride":
			pass
		_:
			return "Unknown action."
	return ""


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
	var why := check(peer, action)
	if why != "":
		_tell(peer, why, false)
		return
	var a := str(action["a"])
	var bike_id := int(action.get("bike", 0))
	var slot := str(action.get("slot", ""))
	var c: Dictionary = crew.get(peer, {})
	var text := ""
	match a:
		"unbolt":
			bikes[bike_id]["bolted"][slot] = false
			text = "%s unbolted" % PartsDB.SLOT_NAMES[slot]
		"bolt":
			bikes[bike_id]["bolted"][slot] = true
			text = "%s bolted up" % PartsDB.SLOT_NAMES[slot]
			if is_complete(bike_id):
				text += ". The bike is ready to ride!"
		"remove":
			var item_id := item_on(bike_id, slot)
			bikes[bike_id]["slots"][slot] = 0
			bikes[bike_id]["bolted"][slot] = false
			_move(item_id, "held", peer)
			_bump(c, "removed")
			text = "Removed the %s" % PartsDB.part_name(items[item_id]["part"])
		"install":
			var item_id := held_by(peer)
			var s: String = items[item_id]["slot"]
			bikes[bike_id]["slots"][s] = item_id
			bikes[bike_id]["bolted"][s] = false
			_move(item_id, "bike", bike_id)
			_bump(c, "fitted")
			text = "Fitted the %s. Bolt it up with the wrench." % PartsDB.part_name(items[item_id]["part"])
		"take":
			_move(item_at_spot(str(action["spot"])), "held", peer)
		"place":
			var item_id := held_by(peer)
			_move(item_id, "spot", str(action["spot"]))
			if action["spot"] == "washer":
				text = "Into the parts washer"
		"shelf_take":
			var item_id := _new_item(str(action["part"]), 0.0, 0.0, 0.0)
			_move(item_id, "held", peer)
			text = "Picked up a new %s" % PartsDB.part_name(str(action["part"]))
		"bin":
			var item_id := held_by(peer)
			text = "Binned the %s" % PartsDB.part_name(items[item_id]["part"])
			items.erase(item_id)
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
		"mount":
			bikes[bike_id]["rider"] = peer
			c["riding"] = bike_id
		"dismount":
			bikes[bike_id]["rider"] = 0
			bikes[bike_id]["xf"] = action.get("xf", bikes[bike_id]["xf"])
			c["riding"] = 0
		"order":
			var id := _random_bike(free_bay(Workshop.BAY_COUNT))
			text = "%s has been delivered to bay %d" % [bikes[id]["name"], bikes[id]["bay"] + 1]
		"status":
			c["tool"] = str(action.get("tool", c.get("tool", "")))
			c["activity"] = str(action.get("activity", "")).left(60)
		"ride":
			c["km"] = float(c.get("km", 0.0)) + clampf(float(action.get("km", 0.0)), 0.0, 5.0)
			c["top_kmh"] = maxf(float(c.get("top_kmh", 0.0)), clampf(float(action.get("top_kmh", 0.0)), 0.0, 400.0))
			c["kmh"] = clampf(float(action.get("kmh", 0.0)), 0.0, 400.0)
	if text != "":
		_tell(peer, text, true)
	_mark_dirty()
	changed.emit()


func _tell(peer: int, text: String, ok: bool) -> void:
	if peer == me():
		feedback.emit(text, ok)
	elif Net.is_online():
		_feedback.rpc_id(peer, text, ok)


@rpc("authority", "call_remote", "reliable")
func _feedback(text: String, ok: bool) -> void:
	feedback.emit(text, ok)


func _bump(c: Dictionary, key: String) -> void:
	c[key] = int(c.get(key, 0)) + 1


func _move(item_id: int, at: String, ref) -> void:
	items[item_id]["at"] = at
	items[item_id]["ref"] = ref


func _free_spot_from(start: int) -> String:
	for i in range(start, SPOTS.size()):
		if SPOTS[i].begins_with("bench") and item_at_spot(SPOTS[i]) == 0:
			return SPOTS[i]
	return "bench_0"


func _new_item(part: String, rust: float, dirt: float, wear: float) -> int:
	var id := _next_id
	_next_id += 1
	items[id] = {"id": id, "part": part, "slot": PartsDB.slot_of(part), "rust": rust, "dirt": dirt, "wear": wear,
		"at": "spot", "ref": ""}
	return id


## Adds a bike to a bay. `age` 0..1 sets how rusty, dirty and worn its parts are.
func _new_bike(parts: Dictionary, bay: int, bike_name: String, age: float) -> int:
	var id := _next_id
	_next_id += 1
	parts = PartsDB.sanitize_build(parts)
	var bike := {"id": id, "name": bike_name, "paint": PAINTS[_rng.randi() % PAINTS.size()], "slots": {}, "bolted": {},
		"rider": 0, "bay": bay, "xf": Workshop.bay_transform(bay), "original": parts.duplicate()}
	bikes[id] = bike
	var cond := {}
	for slot in PartsDB.SLOTS:
		var rust := clampf(age * _rng.randf_range(0.4, 1.2), 0.0, 1.0)
		var dirt := clampf(age * _rng.randf_range(0.8, 1.4), 0.0, 1.0)
		var wear := clampf(age * _rng.randf_range(0.2, 1.0), 0.0, 1.0)
		var item_id := _new_item(parts[slot], rust, dirt, wear)
		_move(item_id, "bike", id)
		bike["slots"][slot] = item_id
		bike["bolted"][slot] = true
		cond[slot] = {"rust": rust, "dirt": dirt, "wear": wear}
	bike["delivered"] = BikeBuild.new(parts, cond).summary()
	return id


func _random_bike(bay: int) -> int:
	var parts := {}
	for slot in PartsDB.SLOTS:
		var options: Array = PartsDB.by_slot[slot]
		parts[slot] = options[_rng.randi() % options.size()]
	var bike_name: String = BIKE_NAMES[_rng.randi() % BIKE_NAMES.size()]
	return _new_bike(parts, bay, bike_name, _rng.randf_range(0.35, 0.9))


func _add_crew(peer: int, player_name: String) -> void:
	if crew.has(peer):
		crew[peer]["name"] = player_name
		return
	crew[peer] = {"name": player_name, "tool": "hands", "activity": "", "riding": 0, "fitted": 0, "removed": 0,
		"cleaned": 0, "repaired": 0, "km": 0.0, "top_kmh": 0.0, "kmh": 0.0, "slot": crew.size()}


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
		_move(held, "spot", _free_spot_from(0))
	var bike_id := riding(id)
	if bike_id != 0:
		bikes[bike_id]["rider"] = 0
	crew.erase(id)
	_mark_dirty()
	changed.emit()


# ---------------------------------------------------------------------------- syncing

func _mark_dirty() -> void:
	_dirty = true


func _snapshot() -> Dictionary:
	return {"bikes": bikes, "items": items, "crew": crew, "next": _next_id}


@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	bikes = state.get("bikes", {})
	items = state.get("items", {})
	crew = state.get("crew", {})
	_next_id = int(state.get("next", 1))
	active = true
	changed.emit()


func _process(delta: float) -> void:
	if not active or not is_authority():
		return
	# The parts washer slowly cleans whatever is in it.
	var washing := item_at_spot("washer")
	if washing != 0 and items[washing]["dirt"] > 0.0:
		items[washing]["dirt"] = maxf(0.0, items[washing]["dirt"] - WASH_RATE * delta)
		_mark_dirty()
		if items[washing]["dirt"] == 0.0:
			changed.emit()
	_sync_timer -= delta
	if _dirty and _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_dirty = false
		if Net.is_online():
			_sync.rpc(_snapshot())
		changed.emit()
