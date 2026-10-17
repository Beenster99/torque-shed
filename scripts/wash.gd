class_name Wash
extends RefCounted
## Pressure washing bikes, on the host's side: where the hose reaches (the wash bay beside the
## shed, and the shed itself, whose floor drains into the drain in the middle of it), the jet
## each washer is firing and where it lands (so the whole crew sees the water: "wash_aim"), and
## the dirt their WashJob has washed off each part, region by region ("wash_cells": each region's
## dirt times a factor, so two people washing the same bike both count), with the parts it calls
## clean. A part gone clean is worth its XP once; the whole bike clean, the bike-washed XP (more
## for a muddier one), as the quick wash always was.

## The drain in the middle of the shed floor, and the wash bay's.
const SHED_DRAIN := Vector3(0.0, 0.0, 65.0)
const BAY_DRAIN := Vector3(-9.3, 0.0, 66.6)


## Whether the hose reaches a bike at `at`: in the wash bay (or just outside it), or in the shed.
static func reaches(at: Vector3) -> bool:
	return at.distance_to(Workshop.WASH_POS) <= Workshop.WASH_REACH or Workshop.room_at(at) in ["shed", "wing"]


## The drain the water from washing at `at` runs into.
static func drain_near(at: Vector3) -> Vector3:
	return BAY_DRAIN if at.distance_to(BAY_DRAIN) < at.distance_to(SHED_DRAIN) and Workshop.room_at(at) == "" else SHED_DRAIN


## Who is firing the jet and where it lands: [{peer, at, normal, from}] (see "wash_aim").
static func jets() -> Array:
	var out := []
	for peer in Shed.crew:
		var c: Dictionary = Shed.crew[peer]
		if c.get("wash_fire", false) and c.get("wash_at") is Vector3:
			out.append({"peer": int(peer), "at": c["wash_at"], "normal": c.get("wash_n", Vector3.UP), "bike": int(c.get("wash_bike", 0))})
	return out


static func check(peer: int, action: Dictionary) -> String:
	match str(action.get("a", "")):
		"wash_aim":
			return ""
		"wash_cells":
			var bike := int(action.get("bike", 0))
			if not Shed.bikes.has(bike):
				return "That bike has gone."
			if int(Shed.bikes[bike].get("rider", 0)) != 0:
				return "Someone is riding that bike."
			if not reaches((Shed.bikes[bike]["xf"] as Transform3D).origin):
				return "The hose doesn't reach. Wash it in the shed or the wash bay."
			if not (action.get("parts", {}) is Dictionary) or (action.get("parts", {}) as Dictionary).size() > PartsDB.SLOTS.size():
				return "Nothing was washed."
			if not (action.get("clean", []) is Array):
				return "Nothing was washed."
	return ""


static func apply(peer: int, action: Dictionary) -> String:
	var c: Dictionary = Shed.crew.get(peer, {})
	match str(action.get("a", "")):
		"wash_aim":
			var at = action.get("at", Vector3.ZERO)
			var n = action.get("n", Vector3.UP)
			c["wash_fire"] = bool(action.get("fire", false))
			c["wash_at"] = at if at is Vector3 else Vector3.ZERO
			c["wash_n"] = n if n is Vector3 else Vector3.UP
			c["wash_bike"] = int(action.get("bike", 0))
			return ""
		"wash_cells":
			return _wash_cells(peer, c, action)
	return ""


static func _wash_cells(peer: int, c: Dictionary, action: Dictionary) -> String:
	var bike := int(action["bike"])
	var before := Shed._bike_dirt(bike)
	var parts: Dictionary = action.get("parts", {})
	for key in parts:
		var id := int(key)
		if not Shed.items.has(id) or Shed._bike_of(id) != bike or not (parts[key] is Dictionary):
			continue
		var it: Dictionary = Shed.items[id]
		var levels := Dirt.cells(it)
		for cell in parts[key]:
			var k := int(cell)
			if k >= 0 and k < Dirt.CELLS:
				levels[k] *= clampf(float(parts[key][cell]), 0.0, 1.0)
		Dirt.store(it, levels)
	var n := 0
	for key in action.get("clean", []):
		var id := int(key)
		if not Shed.items.has(id) or Shed._bike_of(id) != bike:
			continue
		var was_dirty := float(Shed.items[id]["dirt"]) > 0.0
		Shed._note_low(id)
		Dirt.clear(Shed.items[id])
		if was_dirty:
			n += 1
			Shed._xp(peer, "wash_part", 1.0, "item:%d" % id)
			Shed._check_part(peer, id)
	c["cleaned"] = int(c.get("cleaned", 0)) + n
	# The whole bike clean: more for a muddier one, and a one-off for a real mud monster.
	var b: Dictionary = Shed.bikes[bike]
	var peak := maxf(float(b.get("mud_peak", 0.0)), before)
	if Shed._bike_dirt(bike, true) < 0.02:
		if peak > 0.0:
			b.erase("mud_peak")
			Shed._xp(peer, "pressure_wash", 1.0 + 4.0 * peak, "bike:%d" % bike)
			if peak > 0.25:
				Shed._xp(peer, "muddy_wash", 1.0, "bike:%d" % bike)
			return "Spotless! %s is clean as a whistle." % str(b.get("name", "The bike"))
	elif peak > 0.0:
		b["mud_peak"] = peak
	return ""
