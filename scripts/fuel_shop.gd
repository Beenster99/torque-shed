class_name FuelShop
extends RefCounted
## The shop in every fuel station's kiosk on an adventure (route rides and network rides alike):
## walk up to its counter (the kiosk door's "adv_counter" node, see AdventureStops.fuel_shop) and
## {interact} opens the parts computer's catalogue (PartsComputer in its shop mode, see
## FuelShopView), every part for a bike at the parts computer's prices, paid from the business's
## account as an order from the shed is.
##
## What's bought is put down next to the bike stood on the forecourt (the bike you came in on),
## whatever it is (Simon, 5 Nov: "whatever I buy is put next to my bike"): fit it there and then
## with the wrench (see ToolboxSpares, "spanner_on"), or pick it up with your hands. What's by a
## bike is its "cargo", and so is what the wrench takes off it out of the shed. When the bike's
## ridden off it comes along strapped on (its weight counts), all but what's too big and heavy
## to carry on a bike (an engine, a frame), which is sent on to the shed's delivery area (see
## ride_off). Home again, it all goes in the delivery area. Nothing bought, and nothing taken off
## a bike out of the shed, is ever lost. With nobody on the forecourt it's sent on to the shed.
##
## Everything goes through Shed.request, so the host decides it, every mate sees it and it's
## saved. Shared state, in Shed:
##   bikes[id]["cargo"]   what's by a bike (or strapped on it while it's ridden): item records as
##                        they were when put down (part, kind, boxed, rust, wear, colour...),
##                        without their id or place, in the order they went down. Picked up or
##                        fitted, each is an item again.

## The most one strapped-on part may weigh (kg), and all of them on one bike, when it's ridden off.
const CARRY_ONE_KG := 25.0
const CARRY_KG := 40.0
## How far from the shop's counter (m) a bike still counts as on the forecourt, to put what's
## bought next to.
const FORECOURT := 40.0


## What's strapped on a bike (item records, see the top of this file).
static func cargo_of(bike_id: int) -> Array:
	var c = Shed.bikes.get(bike_id, {}).get("cargo", [])
	return c if c is Array else []


## What it weighs, kg (it goes on the bike's weight, see Shed.build_of).
static func cargo_kg(bike_id: int) -> float:
	var kg := 0.0
	for rec in cargo_of(bike_id):
		kg += part_kg(str(rec.get("part", "")))
	return kg


## A part's weight, kg (an engine's by its cylinders).
static func part_kg(part: String) -> float:
	var p := PartsDB.get_part(part)
	return float(p.get("mass", float(p.get("mass_per_cyl", 0.0)) * float(p.get("cylinders", 2))))


## Why `part` can't be strapped on `bike_id` ("" when it can): too heavy for straps, or the
## bike's loaded up already.
static func carry_reason(bike_id: int, part: String) -> String:
	var kg := part_kg(part)
	var name := PartsDB.part_name(part).to_lower()
	if kg > CARRY_ONE_KG:
		return "The %s is too big and heavy to strap on a bike (%s; %s at most)." % [name, Units.mass(kg, 0), Units.mass(CARRY_ONE_KG, 0)]
	if cargo_kg(bike_id) + kg > CARRY_KG:
		return "%s is loaded up already (%s strapped on; %s at most)." % [str(Shed.bikes[bike_id]["name"]),
			Units.mass(cargo_kg(bike_id), 0), Units.mass(CARRY_KG, 0)]
	return ""


## What a part by the bike is called in the lists: "Touring screen (boxed)".
static func cargo_name(rec: Dictionary) -> String:
	return "%s%s" % [PartsDB.part_name(str(rec.get("part", ""))), " (boxed)" if rec.get("boxed", false) else ""]


## The lines the part info shows for a bike's cargo, with "> " at `pick`.
static func lines(bike_id: int, pick := -1) -> Array:
	var out := []
	var c := cargo_of(bike_id)
	for i in c.size():
		out.append("%s%s" % ["> " if i == pick else "", cargo_name(c[i])])
	return out


# ---------------------------------------------------------------------------- the rules

static func _on_adventure() -> String:
	return "" if Adventure.active() else "The fuel station shops are out on an adventure."


## Why `peer` can't do `action` ("" when they can).
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if a.begins_with("cargo_"):
		return _by_bike_check(peer, action)
	var why := _on_adventure()
	if why != "":
		return why
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	var bike := int(action.get("bike", 0))
	match a:
		"shop_buy":
			var part := str(action.get("part", ""))
			if PartsDB.get_part(part).is_empty() or not PartsDB.KINDS.has(PartsDB.kind_of(part)) and not PartsDB.is_fluid(part):
				return "The shop doesn't sell that."
			if action.has("look"):
				var bad := PartColours.check(part, action["look"])
				if bad != "":
					return bad
			var cost := Money.buy_price(part, peer)
			if cost > Shed.garage_money:
				return "The business can't afford it: %s, and it has %s." % [TvChannels.money_text(cost), TvChannels.money_text(Shed.garage_money)]
			if bike == 0:
				if not Shed.delivery_room(part):
					return "The shed's delivery area is full, racking and all: nowhere to send it."
				return ""
			if not Shed.bikes.has(bike) or not Roadside.parked(bike):
				return "There's no bike stood on the forecourt to put it by."
			return ""
	return _by_bike_check(peer, action)


## The rules for picking up what's by a bike ("cargo_take") and putting what you hold down by it
## ("cargo_strap"), anywhere it's stood out of the shed (see ToolboxSpares.stood_out).
static func _by_bike_check(peer: int, action: Dictionary) -> String:
	var bike := int(action.get("bike", 0))
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	match str(action.get("a", "")):
		"cargo_take":
			if not ToolboxSpares.stood_out(bike):
				return "Stop and get off first: things by the bike are picked up when it's stood still."
			if Shed.held_by(peer) != 0:
				return "Your hands are full."
			var c := cargo_of(bike)
			var i := int(action.get("index", 0))
			if c.is_empty():
				return "There's nothing by the bike."
			if i < 0 or i >= c.size() or (action.has("part") and str(c[i].get("part", "")) != str(action["part"])):
				return "That isn't by the bike any more."
			return ""
		"cargo_strap":
			if not ToolboxSpares.stood_out(bike):
				return "Stop and get off first: put things down by the bike when it's stood still."
			var held := Shed.held_by(peer)
			if held == 0:
				return "You're not holding anything to put down."
			if Shed.tyre_on_wheel(held) != 0 or Shed.is_engine(held) and not (Shed.items[held].get("slots", {}) as Dictionary).values().all(func(v): return int(v) == 0):
				return "Take it apart first: one part at a time."
			return ""
	return "Unknown shop action."


## Applies a checked action; returns what to tell the player.
static func apply(peer: int, action: Dictionary) -> String:
	var bike := int(action.get("bike", 0))
	match str(action.get("a", "")):
		"shop_buy":
			var part := str(action["part"])
			var cost := Money.buy_price(part, peer)
			Shed.charge_garage(cost, "Bought %s at a fuel station" % PartsDB.part_name(part))
			var id := Shed._new_item(part, 0.0, 0.0, 0.0)
			PartColours.apply(Shed.items[id], action.get("look", {}))
			Shed.items[id]["paid"] = cost
			Shed.items[id]["boxed"] = not PartsDB.is_fluid(part)
			Shed.items[id]["by"] = Shed.orderer_name(peer)
			if bike == 0:
				_send_home(id)
				return "Bought %s for %s on the business's account. No bike on the forecourt, so the shop's sending it on: it's in the shed's delivery area." \
					% [PartsDB.part_name(part), TvChannels.money_text(cost)]
			_strap(bike, id)
			return "Bought %s for %s on the business's account: it's next to %s. Fit it there with the wrench ({alt_act} at the bike)." \
				% [PartsDB.part_name(part), TvChannels.money_text(cost), str(Shed.bikes[bike]["name"])]
		"cargo_take":
			var c: Array = cargo_of(bike).duplicate()
			var rec: Dictionary = (c[int(action.get("index", 0))] as Dictionary).duplicate(true)
			c.remove_at(int(action.get("index", 0)))
			Shed.bikes[bike]["cargo"] = c
			var was_boxed := bool(rec.get("boxed", false))
			rec["boxed"] = false   # out of its box on the forecourt
			var id := _make_item(rec)
			Shed._move(id, "held", peer)
			return "Picked up the %s%s: fit it with your hands, then bolt it up with the wrench." % [
				PartsDB.part_name(str(rec["part"])).to_lower(), " and took it out of its box" if was_boxed else ""]
		"cargo_strap":
			var held := Shed.held_by(peer)
			var name := Shed.item_title(held).to_lower()
			_strap(bike, held)
			return "Put the %s down by %s: it comes along when you ride off." % [name, str(Shed.bikes[bike]["name"])]
	return ""


## Puts an item (loose, held, wherever) on a bike's straps: its record goes in the cargo and the
## item itself is gone from the shed's list.
static func _strap(bike: int, item_id: int) -> void:
	var rec: Dictionary = Shed.items[item_id].duplicate(true)
	for key in ["id", "at", "ref", "place"]:
		rec.erase(key)
	var c: Array = cargo_of(bike).duplicate()
	c.append(rec)
	Shed.bikes[bike]["cargo"] = c
	Shed.items.erase(item_id)


## An item again from a cargo record, with a new id (somewhere, till it's moved).
static func _make_item(rec: Dictionary) -> int:
	var id: int = Shed._next_id
	Shed._next_id += 1
	var it := rec.duplicate(true)
	it["id"] = id
	it["at"] = "spot"
	it["ref"] = ""
	Shed.items[id] = it
	return id


## Puts an item in the shed's delivery area, or on its floor when the area's full (kept either way).
static func _send_home(item_id: int) -> void:
	if Shed._deliver(item_id):
		return
	var c := Shed.DELIVERY_FLOOR.get_center()
	Shed._move(item_id, "floor", Transform3D(Basis(), Vector3(c.x, 0.0, c.y)))


# ---------------------------------------------------------------------------- riding off, and home again

## The bike's ridden off (host, as it's mounted): what's by it is strapped on, all but what's too
## big and heavy to carry, or more than the straps take, which is sent on to the shed's delivery
## area. Returns what to tell the rider ("" when nothing's sent on).
static func ride_off(bike_id: int) -> String:
	var c := cargo_of(bike_id)
	if c.is_empty():
		return ""
	var kept := []
	var sent := []
	var kg := 0.0
	for rec in c:
		var r: Dictionary = rec
		var w := part_kg(str(r.get("part", "")))
		if w <= CARRY_ONE_KG and kg + w <= CARRY_KG:
			kept.append(r)
			kg += w
		else:
			sent.append(r)
	Shed.bikes[bike_id]["cargo"] = kept
	if sent.is_empty():
		return ""
	var names := []
	for r in sent:
		var rr: Dictionary = (r as Dictionary).duplicate(true)
		if not PartsDB.is_fluid(str(rr.get("part", ""))):
			rr["boxed"] = true
		names.append(PartsDB.part_name(str(rr.get("part", ""))).to_lower())
		_send_home(_make_item(rr))
	return "Too much to carry on the bike, so the %s %s sent on to the shed's delivery area" % [", ".join(names), "is" if names.size() == 1 else "are"]


## Whatever's strapped on `bike_id` goes in the shed's delivery area (the bike's home). Host only.
static func unload(bike_id: int) -> int:
	var c := cargo_of(bike_id)
	if c.is_empty():
		return 0
	for rec in c:
		var r: Dictionary = (rec as Dictionary).duplicate(true)
		if not PartsDB.is_fluid(str(r.get("part", ""))):
			r["boxed"] = true   # boxed up again for the shelf (a part off the bike, packed away)
		_send_home(_make_item(r))
	Shed.bikes[bike_id].erase("cargo")
	return c.size()


## The adventure's over: every bike's cargo goes in the delivery area.
static func unload_all() -> void:
	for id in Shed.bikes.keys():
		unload(int(id))
