class_name ToolboxSpares
extends RefCounted
## Spare parts carried in a bike's toolbox, and working on the bike with its tools at the side
## of the road on an adventure.
##
## A toolbox still packs its kit as it always has (the tool roll, oil, brake fluid and chain lube:
## PartsDB.TOOLBOX_CONTENTS, see Shed.toolbox_pack). As well as that, a real
## part from the catalogue can go in it as a spare, as long as it's one of the small things worth
## carrying on a ride (SPARE_KINDS: spark plugs, brake pads, filters, a master cylinder or caliper,
## a headlight, a chain and sprockets, mirrors, indicators, the horn, the ECU...) and it weighs no
## more than SPARE_MAX_KG. Engines, frames, wheels, tanks, exhausts and the like never fit.
## Each spare takes one of the box's places, the same as a piece of kit.
##
## Out on an adventure, with the bike stood at the roadside and its toolbox open (see Roadside),
## the crew can take the wrench from the box's tool roll and work on the bike as they do in the
## shed: unbolt, take off and refit the parts a toolbox's spares are for (ROADSIDE slots), put
## the old part in the box, and fit a spare from it. Everything goes through Shed.request, so
## the host decides it and every mate sees it and can lend a hand.
##
## Shared state, in Shed (so the crew see it and it's saved):
##   items[box]["spares"]   the spare parts in a toolbox: each an item's record as it was when it
##                          went in (part, kind, rust, dirt, wear, colour...), without its id or
##                          place, in the order they went in. Taken out, it's an item again.

## The kinds of part small enough, and useful enough, to carry as a spare.
const SPARE_KINDS: Array[String] = ["spark_plugs", "pads", "oil_filter", "air_filter", "master", "caliper", "final_drive",
	"chain", "mirrors", "indicators", "horn", "headlight", "dashboard", "ecu", "fog_lights", "steering_damper", "satnav",
	"side_stand"]
## Nothing heavier than this (kg) goes in a toolbox, whatever it is.
const SPARE_MAX_KG := 2.5
## The jobs a bike stood at the roadside can have done with the toolbox's tools.
const JOBS: Array[String] = ["unbolt", "bolt", "remove", "install"]


## Why a part (a catalogue id) can't go in a toolbox as a spare, or "" when it can.
static func fit_reason(part: String) -> String:
	var p := PartsDB.get_part(part)
	if p.is_empty():
		return "That isn't a part."
	var kind := PartsDB.kind_of(part)
	var name := PartsDB.part_name(part)
	if not SPARE_KINDS.has(kind):
		return "The %s is far too big to go in a toolbox." % name.to_lower() if kind in ["frame", "engine", "fork", "wheel", "tank", "exhaust",
			"swingarm", "gearbox", "panniers", "top_box", "fairing", "aux_tank", "saddle", "tyre", "shock", "head", "cooling"] \
			else "The %s isn't something you carry in a toolbox." % name.to_lower()
	if float(p.get("mass", 0.0)) > SPARE_MAX_KG:
		return "The %s is too big and heavy for a toolbox (%s; %s at most)." % [name.to_lower(), Units.mass(float(p["mass"]), 1),
			Units.mass(SPARE_MAX_KG, 1)]
	return ""


static func fits(part: String) -> bool:
	return fit_reason(part) == ""


## The spare parts in a toolbox (item records, see the top of this file).
static func spares_of(box: int) -> Array:
	var s = Shed.items.get(box, {}).get("spares", [])
	return s if s is Array else []


## How many places the box has left, for kit or spares.
static func room_left(box: int) -> int:
	return Shed.toolbox_slots(box) - Shed.toolbox_contents(box).size() - spares_of(box).size()


## The weight of the spares in a box, kg (it goes on the bike's weight with the kit).
static func spares_kg(box: int) -> float:
	var kg := 0.0
	for s in spares_of(box):
		kg += float(PartsDB.get_part(str(s.get("part", ""))).get("mass", 0.0))
	return kg


## What a spare is called in the lists: "Iridium spark plugs (new)", "Sintered pads (40% worn)".
static func spare_name(rec: Dictionary) -> String:
	var wear := float(rec.get("wear", 0.0))
	var state := "new" if wear < 0.05 and float(rec.get("rust", 0.0)) < 0.05 else "%d%% worn" % roundi(wear * 100.0)
	return "%s (%s)" % [PartsDB.part_name(str(rec.get("part", ""))), state]


## Where a spare would go on a bike: the slots of its kind, as the part info says them
## ("front or rear brake pads").
static func goes_on(rec: Dictionary) -> String:
	var slots := PartsDB.slots_for_kind(str(rec.get("kind", PartsDB.kind_of(str(rec.get("part", ""))))))
	var names := slots.map(func(s): return PartsDB.slot_name(str(s)).to_lower())
	return " or ".join(names)


## The lines a toolbox's spares show in the toolbox's list, with "> " at `pick`.
static func lines(box: int, pick := -1) -> Array:
	var out := []
	var spares := spares_of(box)
	for i in spares.size():
		out.append("%s%s: for the %s" % ["> " if i == pick else "", spare_name(spares[i]), goes_on(spares[i])])
	return out


## The bike slots that can be worked on at the roadside: the ones the spares are for.
static func roadside_slot(slot: String) -> bool:
	return SPARE_KINDS.has(str(PartsDB.SLOT_KIND.get(slot, "")))


# ---------------------------------------------------------------------------- the roadside's jobs

## Whether `action` is a wrench or hands job on a bike stood at the roadside on an adventure
## (which the shed's "out on the road" rule leaves to this file).
static func roadside_job(action: Dictionary) -> bool:
	if not JOBS.has(str(action.get("a", ""))) or int(action.get("engine", 0)) != 0:
		return false
	var bike := int(action.get("bike", 0))
	return Shed.bikes.has(bike) and Roadside.parked(bike)


## Why `peer` can't do a roadside job on the bike ("" when they can, or when it's no roadside
## job): its toolbox has to be open beside it, the wrench needs the tool roll, and only the
## small parts the spares are for come off here. The shed's own rules go on to say the rest
## (unbolt it first, take the pads off before the caliper...).
static func roadside_check(peer: int, action: Dictionary) -> String:
	if not roadside_job(action):
		return ""
	var a := str(action.get("a", ""))
	var bike := int(action["bike"])
	var box := Roadside.toolbox_of(bike)
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	if box == 0:
		return "There's no toolbox on %s: nothing to work on it with out here." % str(Shed.bikes[bike]["name"])
	if not Roadside.spot_of(bike).get("open", false):
		return "Open the toolbox first ({act} on it, hands) and lay the tools out."
	if a in ["unbolt", "bolt"] and not Shed.toolbox_contents(box).has("tools"):
		return "There's no tool roll in the toolbox: nothing to undo the bolts with."
	var slot := str(action.get("slot", ""))
	if a == "install":
		var held := Shed.held_by(peer)
		if held == 0:
			return "You're not holding a part."
		var where := Shed.install_slot(action, held)
		if where.has("error"):
			return str(where["error"])
		slot = str(where["slot"])
	if not roadside_slot(slot):
		return "The %s is a job for the shed: out here it's the small stuff, what a toolbox's spares are for." % PartsDB.slot_name(slot).to_lower()
	return ""


# ---------------------------------------------------------------------------- packing spares

## Why the toolbox can't be got at to pack or unpack it, or "".
static func _reach(box: int) -> String:
	var bike := Shed._bike_of(box)
	if bike == 0:
		return "" if str(Shed.items[box].get("at", "")) != "held" else "Put it down first."
	if int(Shed.bikes[bike].get("rider", 0)) != 0:
		return "Someone is riding that bike."
	if Roadside.parked(bike):
		return "" if Roadside.spot_of(bike).get("open", false) else "Open the toolbox first ({act} on it, hands)."
	if not Shed.bike_at_work(bike):
		return "Out here %s is just a bike to ride. Ride it back to the shed to work on it." % str(Shed.bikes[bike]["name"])
	return ""


static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var box := int(action.get("item", 0))
	if not Shed.items.has(box) or str(Shed.items[box]["kind"]) != "toolbox":
		return "Aim at a toolbox."
	if Shed.items[box].get("boxed", false):
		return "Unpack it first."
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	var why := _reach(box)
	if why != "":
		return why
	var held := Shed.held_by(peer)
	match a:
		"spare_stow":
			if held == 0:
				return "You're not holding a part."
			if held == box:
				return "That's the toolbox itself."
			if Shed.items[held].get("boxed", false):
				return "Unpack it first."
			var reason := fit_reason(str(Shed.items[held]["part"]))
			if reason != "":
				return reason
			if room_left(box) <= 0:
				return "The %s is packed full (%d things). Take something out first." % [Shed.item_title(box).to_lower(), Shed.toolbox_slots(box)]
			return ""
		"spare_take":
			if held != 0:
				return "Your hands are full."
			var spares := spares_of(box)
			if spares.is_empty():
				return "There are no spare parts in it."
			var i := int(action.get("index", 0))
			if i < 0 or i >= spares.size():
				return "That spare isn't in there any more."
			if action.has("part") and str(spares[i].get("part", "")) != str(action["part"]):
				return "That spare isn't in there any more."
			return ""
	return "Unknown toolbox action."


## Applies a checked action; returns what to tell the player.
static func apply(peer: int, action: Dictionary) -> String:
	var box := int(action["item"])
	match str(action["a"]):
		"spare_stow":
			var held := Shed.held_by(peer)
			var rec: Dictionary = Shed.items[held].duplicate(true)
			for key in ["id", "at", "ref", "place"]:
				rec.erase(key)
			var spares: Array = spares_of(box).duplicate()
			spares.append(rec)
			Shed.items[box]["spares"] = spares
			Shed.items.erase(held)
			return "Packed the %s in the %s as a spare (%d of %d places used)." % [PartsDB.part_name(str(rec["part"])).to_lower(),
				Shed.item_title(box).to_lower(), Shed.toolbox_slots(box) - room_left(box), Shed.toolbox_slots(box)]
		"spare_take":
			var spares: Array = spares_of(box).duplicate()
			var rec: Dictionary = (spares[int(action.get("index", 0))] as Dictionary).duplicate(true)
			spares.remove_at(int(action.get("index", 0)))
			Shed.items[box]["spares"] = spares
			var id: int = Shed._next_id
			Shed._next_id += 1
			rec["id"] = id
			rec["at"] = "held"
			rec["ref"] = peer
			Shed.items[id] = rec
			return "Took the spare %s out of the toolbox: fit it with your hands, then bolt it up with the wrench." \
				% PartsDB.part_name(str(rec["part"])).to_lower()
	return ""
