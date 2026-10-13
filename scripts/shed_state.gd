extends Node
## The shared state of the shed: every bike, every loose part and what each player is doing.
## The host owns it. Players ask for changes with request(); the host checks each one,
## applies it and sends the new state to everyone, so two people working on the same bike
## always agree on which bolts are done up.

signal changed
signal feedback(text: String, ok: bool)

const SPOTS: Array[String] = ["bench_0", "bench_1", "bench_2", "bench_3", "delivery_0", "delivery_1", "delivery_2",
	"delivery_3", "engine_stand", "washer", "repair"]
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
const WASH_RATE := 0.18        # dirt removed per second in the parts washer
const SYNC_INTERVAL := 0.1
const MAX_PAINT_RUST := 0.2

## bike id -> {id, name, paint, slots{bike slot: item id or 0}, bolted{slot: bool}, rider, bay, xf, original, delivered}
var bikes := {}
## item id -> {id, part, kind, rust, dirt, wear, color, finish, at, ref}, where
## at is "bike", "engine", "held", "spot" or "floor" (ref is then the Transform3D it was put down at).
## Engine blocks also carry slots{} and bolted{} for the parts fitted to them.
var items := {}
var crew := {}      # peer id -> {name, tool, activity, riding, fitted, removed, cleaned, repaired, painted, km, top_kmh}
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
	# The barn find arrives half stripped: exhaust, final drive and tyres are on the bench, the
	# engine is on the stand, and its spark plugs and air filter were lost in the barn.
	var bench := 0
	for slot in ["exhaust", "final_drive", "front_tyre", "rear_tyre"]:
		_detach(cafe, slot, "spot", "bench_%d" % bench)
		bench += 1
	var block := _detach(cafe, "engine", "spot", "engine_stand")
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
		if item_on(bike_id, slot) == 0:
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
	return {"rust": item["rust"], "dirt": item["dirt"], "wear": item["wear"], "color": item["color"],
		"finish": item.get("finish", "")}


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
	return BikeBuild.new(parts, cond)


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
	return "Condition %d%%   Rust %d%%   Dirt %d%%   Wear %d%%   %s" % [
		roundi(BikeBuild.part_health(condition_of(item)) * 100.0), roundi(item["rust"] * 100.0),
		roundi(item["dirt"] * 100.0), roundi(item["wear"] * 100.0), paint_text(item)]


func free_bay(bay_count: int) -> int:
	for bay in bay_count:
		var taken := false
		for id in bikes:
			if bikes[id]["bay"] == bay and bikes[id]["xf"].origin.distance_to(Workshop.bay_transform(bay).origin) < 2.5:
				taken = true
		if not taken:
			return bay
	return -1


func free_delivery_spot() -> String:
	for i in 4:
		if item_at_spot("delivery_%d" % i) == 0:
			return "delivery_%d" % i
	return ""


## Where a held part would go on a target, or why it can't: {slot} or {error}.
## Prefers the slot being looked at, then the same side (front or rear), then any free slot.
func install_slot(action: Dictionary, item_id: int) -> Dictionary:
	if not items.has(item_id):
		return {"error": "You're not holding a part."}
	var k: String = items[item_id]["kind"]
	var candidates := PartsDB.slots_for_kind(k)
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
	if not (block["at"] == "spot" and block["ref"] == "engine_stand"):
		return "Put the engine on the engine stand first."
	return ""


## Why `peer` can't do `action` right now, or "" when they can.
func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var held := held_by(peer)
	var bike_id := int(action.get("bike", 0))
	var engine_id := int(action.get("engine", 0))
	var slot := str(action.get("slot", ""))
	if a in ["unbolt", "bolt", "remove", "install", "mount"]:
		if engine_id != 0:
			if not is_engine(engine_id):
				return "That engine has gone."
		elif not bikes.has(bike_id):
			return "That bike has gone."
		elif bikes[bike_id]["rider"] != 0:
			return "Someone is riding that bike."
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
			var where := install_slot(action, held)
			if where.has("error"):
				return where["error"]
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
			if not SPOTS.has(spot):
				return "You can't put it there."
			if item_at_spot(spot) != 0:
				return "That spot is taken."
			if spot == "engine_stand" and not is_engine(held):
				return "Only an engine goes on the engine stand."
		"order_part":
			if PartsDB.get_part(str(action.get("part", ""))).is_empty():
				return "Unknown part."
			if free_delivery_spot() == "":
				return "The delivery pallets are full. Clear one first."
		"bin":
			if held == 0:
				return "You're not holding a part."
		"clean", "repair", "paint":
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
			if a == "paint" and it["rust"] > MAX_PAINT_RUST:
				return "Too rusty to paint. Grind it back on the repair bench first."
			if a == "paint" and it.get("finish", "") == str(action.get("finish", "gloss")) \
					and paint_index(it["color"]) == int(action.get("color", 0)) and it["color"] == PAINTS[paint_index(it["color"])]:
				return "It's already %s." % paint_text(it).to_lower()
		"mount":
			if riding(peer) != 0:
				return "You're already riding."
			if held != 0:
				return "Put the part down first."
			var missing := missing_slots(bike_id)
			if not missing.is_empty():
				return "Missing: %s." % _slot_list(missing)
			var loose := loose_slots(bike_id)
			if not loose.is_empty():
				return "Not bolted up: %s." % _slot_list(loose)
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
			match str(action["spot"]):
				"washer":
					text = "Into the parts washer"
				"engine_stand":
					text = "Engine on the stand. Strip it down or build it up."
		"order_part":
			var part_id := str(action["part"])
			var spot := free_delivery_spot()
			var item_id := _new_item(part_id, 0.0, 0.0, 0.0)
			_move(item_id, "spot", spot)
			text = "Ordered a %s. It's on delivery pallet %d." % [PartsDB.part_name(part_id), int(spot.trim_prefix("delivery_")) + 1]
		"bin":
			var item_id := held_by(peer)
			text = "Binned the %s" % PartsDB.part_name(items[item_id]["part"])
			_erase_item(item_id)
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
		"paint":
			var idx := clampi(int(action.get("color", 0)), 0, PAINTS.size() - 1)
			var finish := str(action.get("finish", "gloss"))
			if not FINISHES.has(finish):
				finish = "gloss"
			var it: Dictionary = items[int(action["item"])]
			it["color"] = PAINTS[idx]
			it["finish"] = finish
			_bump(c, "painted")
			text = "Sprayed the %s %s" % [item_title(int(action["item"])), paint_text(it).to_lower()]
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
		if (spot.begins_with("bench") or spot.begins_with("delivery")) and item_at_spot(spot) == 0:
			return spot
	return "bench_0"


func _new_item(part: String, rust: float, dirt: float, wear: float, color = null) -> int:
	var id := _next_id
	_next_id += 1
	var k := PartsDB.kind_of(part)
	items[id] = {"id": id, "part": part, "kind": k, "rust": rust, "dirt": dirt, "wear": wear,
		"color": PartsDB.default_color(part) if color == null else color, "finish": "", "at": "spot", "ref": ""}
	if k == "engine":
		items[id]["slots"] = {}
		items[id]["bolted"] = {}
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
		"rider": 0, "bay": bay, "xf": Workshop.bay_transform(bay), "original": parts.duplicate()}
	bikes[id] = bike
	var cond := {}
	for slot in PartsDB.BIKE_SLOTS:
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
	bike["original_cond"] = cond
	bike["delivered"] = BikeBuild.new(parts, cond).summary()
	return id


func _random_bike(bay: int) -> int:
	var parts := {}
	var pick := {}
	for slot in PartsDB.SLOTS:
		var k: String = PartsDB.SLOT_KIND[slot]
		# A random bike wears a matching pair of tyres; everything else is picked per slot.
		var key: String = k if k == "tyre" else slot
		if not pick.has(key):
			var options: Array = PartsDB.by_kind[k]
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
