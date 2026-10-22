class_name AdventureJourney
extends RefCounted
## The crew's planning board for a journey across a real region (Shed.journey): pins on the map (JourneyMap), put down
## by anyone in the crew, and the style of ride. When the host likes it, the board becomes a plan (AdventurePlans) and
## the adventure starts along it.
##
## Shed.journey: {} when nothing is pinned, else {region (a RealRegion id), pins: [{x, z, name, by}], mode ("main",
## "scenic" or "tracks")}. Pins are on roads (junctions of the region's graph), so the same pins plan the same road.
##
## Actions (Shed.request, from any player): adventure_pin {region, x, z, at (where in the list, default the end)},
## adventure_unpin {i}, adventure_mode {mode}, adventure_clear.

const MAX_PINS := AdventurePlans.MAX_PINS
## A pin is put on the nearest junction within this (m); a place's name is taken from within NAME_REACH of it.
const SNAP_M := 800.0
const NAME_REACH := 350.0


static func sanitize(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var region := RealRegion.get_region(str(v.get("region", "")))
	if region == null:
		return {}
	var pins: Array = []
	var raw = v.get("pins")
	if raw is Array:
		for p in raw:
			if p is Dictionary and pins.size() < MAX_PINS:
				pins.append({"x": snappedf(float(p.get("x", 0.0)), 0.1), "z": snappedf(float(p.get("z", 0.0)), 0.1),
					"name": str(p.get("name", "")).left(AdventurePlans.MAX_NAME), "by": str(p.get("by", "")).left(24)})
	var mode := str(v.get("mode", "main"))
	return {"region": region.id, "pins": pins, "mode": mode if RoutePlanner.CLASS_COST.has(mode) else "main"}


## The plan the board makes ({} until it has two pins).
static func plan_of(journey: Dictionary) -> Dictionary:
	if journey.is_empty() or (journey["pins"] as Array).size() < 2:
		return {}
	var region := RealRegion.get_region(str(journey["region"]))
	if region == null:
		return {}
	var pins: Array = []
	var names: Array = []
	for p: Dictionary in journey["pins"]:
		pins.append([float(p["x"]), float(p["z"])])
		names.append(str(p["name"]))
	return AdventurePlans.clean({"region": region.id, "region_hash": region.hash, "pins": pins, "names": names, "mode": journey["mode"]})


static func check(peer: int, action: Dictionary) -> String:
	var journey: Dictionary = Shed.journey
	match str(action.get("a", "")):
		"adventure_pin":
			var region := RealRegion.get_region(str(action.get("region", "")))
			if region == null:
				return "This game doesn't have that map."
			if not journey.is_empty() and str(journey["region"]) == region.id and (journey["pins"] as Array).size() >= MAX_PINS:
				return "That's as many pins as the map holds (%d)." % MAX_PINS
			var n := region.nearest_connected(float(action.get("x", 0.0)), float(action.get("z", 0.0)), SNAP_M)
			if n < 0:
				return "There's no road near there."
			if not journey.is_empty() and str(journey["region"]) == region.id:
				var pins: Array = journey["pins"]
				var at := clampi(int(action.get("at", pins.size())), 0, pins.size())
				var at_node := region.node_pos[n]
				if at > 0 and Vector2(float(pins[at - 1]["x"]), float(pins[at - 1]["z"])).is_equal_approx(at_node):
					return "There's a pin there already."
			if Adventure.active():
				return "There's an adventure on already."
		"adventure_unpin":
			if journey.is_empty() or int(action.get("i", -1)) < 0 or int(action.get("i", -1)) >= (journey["pins"] as Array).size():
				return "There's no such pin."
		"adventure_mode":
			if not RoutePlanner.CLASS_COST.has(str(action.get("mode", ""))):
				return "There's no style of ride like that."
		"adventure_clear":
			pass
	return ""


static func apply(peer: int, action: Dictionary, who: String) -> String:
	match str(action.get("a", "")):
		"adventure_pin":
			var region := RealRegion.get_region(str(action["region"]))
			if Shed.journey.is_empty() or str(Shed.journey["region"]) != region.id:
				Shed.journey = {"region": region.id, "pins": [], "mode": "main"}
			var n := region.nearest_connected(float(action.get("x", 0.0)), float(action.get("z", 0.0)), SNAP_M)
			var pos := region.node_pos[n]
			var pins: Array = Shed.journey["pins"]
			var at := clampi(int(action.get("at", pins.size())), 0, pins.size())
			pins.insert(at, {"x": snappedf(pos.x, 0.1), "z": snappedf(pos.y, 0.1), "name": place_name(region, n), "by": who})
		"adventure_unpin":
			(Shed.journey["pins"] as Array).remove_at(int(action["i"]))
		"adventure_mode":
			if not Shed.journey.is_empty():
				Shed.journey["mode"] = str(action["mode"])
		"adventure_clear":
			Shed.journey = {}
	return ""


## A name for the place at junction `n`: the nearest named place (shop, village, peak...) within NAME_REACH, else the
## road, else "".
static func place_name(region: RealRegion, n: int) -> String:
	var here := region.node_pos[n]
	var best := ""
	var best_d := NAME_REACH
	for q: Dictionary in region.pois:
		if str(q.get("name", "")) == "":
			continue
		var d := Vector2(float(q["x"]), float(q["z"])).distance_to(here)
		if d < best_d:
			best_d = d
			best = str(q["name"])
	for m: Dictionary in region.landmarks:
		if str(m.get("name", "")) == "":
			continue
		var d := Vector2(float(m["x"]), float(m["z"])).distance_to(here)
		if d < best_d:
			best_d = d
			best = str(m["name"])
	if best != "":
		return best
	for ei in region.adjacent[n]:
		var raw := str(region.names[region.edge_name[ei]])
		if raw != "":
			return raw
	return ""


## Why the host can't start the board's journey ("" if they can).
static func start_reason(journey: Dictionary) -> String:
	if not Shed.is_authority():
		return "The host starts the ride."
	if Adventure.active():
		return "There's an adventure on already."
	if (journey.get("pins", []) as Array).size() < 2:
		return "Pin a start and somewhere to get to."
	return ""


## Checks an adventure_start that carries a plan ("" if all is well).
static func start_check(action: Dictionary) -> String:
	var plan := AdventurePlans.clean(action.get("plan"))
	if plan.is_empty():
		return "That journey can't be planned."
	var res := AdventurePlans.result(plan, true)
	if not bool(res["ok"]):
		return str(res["error"])
	if (res["pack"] as RealPack).max_km() < Adventure.MIN_KM:
		return "That's a short hop: pin somewhere at least %d km away." % int(Adventure.MIN_KM)
	if (res["pack"] as RealPack).max_km() > Adventure.MAX_KM:
		return "That's a long way: keep it under %d km." % int(Adventure.MAX_KM)
	return ""


## What a started adventure along `action`'s plan holds: {plan, real, real_hash, km, theme, dest (the last pin's place)}.
static func start_info(action: Dictionary) -> Dictionary:
	var plan := AdventurePlans.clean(action.get("plan"))
	var pack := AdventurePlans.pack_for(plan)
	var names: Array = plan.get("names", [])
	var dest := str(names[names.size() - 1]) if not names.is_empty() else ""
	if dest == "":
		var region := RealRegion.get_region(str(plan["region"]))
		dest = "the end of the road" if region == null else region.title
	return {"plan": plan, "real": pack.id, "real_hash": pack.hash, "km": floorf(pack.max_km() * 10.0) / 10.0, "theme": pack.theme, "dest": dest}
