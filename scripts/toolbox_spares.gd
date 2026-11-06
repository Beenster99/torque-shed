class_name ToolboxSpares
extends RefCounted
## Spare parts carried in a bike's toolbox, and working on a bike with the spanner out of the
## shed: at the side of the road on an adventure, or wherever it's left on an ordinary ride.
##
## A toolbox still packs its kit as it always has (the tool roll, oil, brake fluid and chain lube:
## PartsDB.TOOLBOX_CONTENTS, see Shed.toolbox_pack). As well as that, a real
## part from the catalogue can go in it as a spare, as long as it's one of the small things worth
## carrying on a ride (SPARE_KINDS: spark plugs, brake pads, filters, a master cylinder or caliper,
## a headlight, a chain and sprockets, mirrors, indicators, the horn, the ECU...) and it weighs no
## more than SPARE_MAX_KG. Engines, frames, wheels, tanks, exhausts and the like never fit.
## Each spare takes one of the box's places, the same as a piece of kit.
##
## Anywhere a bike is stood with nobody on it out of the shed (stood_out: at an adventure's
## roadside, or left out on the road on an ordinary ride), the crew can take the wrench to it.
## No toolbox needed: the wrench is your own (Simon, 5 Nov: "I can use the wrench to add and
## remove any item there and then. I do not need a toolbox", reversing the old rule that a bike
## out on the road was only for riding). It works on the bolt-on parts a bike rides without
## (BOLT_ON_SLOTS: mudguards, panels, luggage, lights...) and the small parts a toolbox's spares
## are for. One go of the wrench takes a part off and puts it down by the bike ("spanner_off"),
## and the second button fits a part from beside the bike and bolts it up ("spanner_on"): what's
## by the bike is FuelShop's cargo, where a fuel station's shop puts what you buy. Hands still
## work as in the shed too (unbolt, take off, fit, bolt up). Everything goes through
## Shed.request, so the host decides it and every mate sees it and can lend a hand.
##
## Shared state, in Shed (so the crew see it and it's saved):
##   items[box]["spares"]   the spare parts in a toolbox: each an item's record as it was when it
##                          went in (part, kind, rust, dirt, wear, colour...), without its id or
##                          place, in the order they went in. Taken out, it's an item again.

## The kinds of part small enough, and useful enough, to carry as a spare.
const SPARE_KINDS: Array[String] = ["spark_plugs", "pads", "oil_filter", "air_filter", "master", "caliper", "final_drive",
	"chain", "mirrors", "indicators", "horn", "headlight", "dashboard", "ecu", "fog_lights", "steering_damper", "satnav",
	"side_stand"]
## The bolt-on parts a bike rides without that the toolbox's spanners take off and fit at the
## roadside as well (Simon, 3 Nov: "we may want to remove mudguards or other non essential
## items"): mudguards, the tail unit, fairing and panels, luggage, lights, guards and the like.
## Never the engine, gearbox, frame, wheels, tyres, suspension, bars, tank, the rider's seat or
## the chain's drive; and only where the Rig built fit says it simply bolts on (see rig_says).
const BOLT_ON_SLOTS: Array[String] = ["front_mudguard", "tail", "fairing", "side_panels", "number_boards", "panniers",
	"top_box", "tank_bag", "guards", "lever_guards", "centre_stand", "headlight", "fog_lights", "indicators", "mirrors",
	"horn", "satnav", "steering_damper"]
## Nothing heavier than this (kg) goes in a toolbox, whatever it is.
const SPARE_MAX_KG := 2.5
## The shed's own jobs a bike stood out of the shed can have done (see roadside_check).
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


## The bike slots that can be worked on at the roadside: the ones the spares are for, and the
## bolt-on parts a bike rides without (BOLT_ON_SLOTS).
static func roadside_slot(slot: String) -> bool:
	return SPARE_KINDS.has(str(PartsDB.SLOT_KIND.get(slot, ""))) or BOLT_ON_SLOTS.has(slot)


## Whether the Rig built fit call is there (BikeRig.part_tier, see
## /mnt/project-files/torque-shed/bike-look/fit-tiers-interface.md): looked up once, so the
## roadside works the same before it's in the game.
static var _rig_tier := -1


static func _has_rig_tier() -> bool:
	if _rig_tier < 0:
		_rig_tier = 0
		for m in (BikeRig as Script).get_script_method_list():
			if str(m.get("name", "")) == "part_tier":
				_rig_tier = 1
	return _rig_tier == 1


## Why the Rig built fit says `part` (or "none": taking it off) can't go into `slot` on `bike`
## at the roadside, or "" when it simply bolts on. Fabrication, or a change the bike can't take,
## is a job for the shed.
static func rig_says(bike: int, slot: String, part: String) -> String:
	if not _has_rig_tier():
		return ""
	var f = (BikeRig as Script).call("part_tier", bike, slot, part)
	if not (f is Dictionary) or str(f.get("tier", "bolts on")) == "bolts on":
		return ""
	var reason := str(f.get("reason", "")).strip_edges()
	return (reason + " " if reason != "" else "") + "That's a job for the shed."


# ---------------------------------------------------------------------------- the roadside's jobs

## Whether a bike is stood out of the shed with nobody on it or wheeling it: at the roadside on
## an adventure, or left out on the road on an ordinary ride (not a recovery job, nor one of the
## crew's own bikes on show at the house). The spanner works on it there.
static func stood_out(bike: int) -> bool:
	if not Shed.bikes.has(bike):
		return false
	if Roadside.parked(bike):
		return true
	var b: Dictionary = Shed.bikes[bike]
	return not Adventure.active() and int(b.get("rider", 0)) == 0 and int(b.get("pusher", 0)) == 0 \
		and not Shed.bike_at_work(bike) and Recovery.job_of(bike).is_empty() and not Collection.parked(bike)


## Whether `action` is a wrench or hands job on a bike stood out of the shed (which the shed's
## "out on the road" rule leaves to this file).
static func roadside_job(action: Dictionary) -> bool:
	if not JOBS.has(str(action.get("a", ""))) or int(action.get("engine", 0)) != 0:
		return false
	return stood_out(int(action.get("bike", 0)))


## Why `peer` can't do a job on a bike stood out of the shed ("" when they can, or when it's no
## such job): only the bolt-on parts it rides without and the small parts the spares are for
## come off out here. The shed's own rules go on to say the rest (unbolt it first, take the pads
## off before the caliper...).
static func roadside_check(peer: int, action: Dictionary) -> String:
	if not roadside_job(action):
		return ""
	var a := str(action.get("a", ""))
	var bike := int(action["bike"])
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	var slot := str(action.get("slot", ""))
	if a == "install":
		var held := Shed.held_by(peer)
		if held == 0:
			return "You're not holding a part."
		var where := Shed.install_slot(action, held)
		if where.has("error"):
			return str(where["error"])
		slot = str(where["slot"])
	return _slot_says(bike, slot, a, str(Shed.items[Shed.held_by(peer)]["part"]) if a == "install" else "none")


## Why `slot` on `bike` can't be worked on out of the shed (`a`: what's being done, `part`: what's
## going on), or "".
static func _slot_says(bike: int, slot: String, a: String, part: String) -> String:
	if not roadside_slot(slot):
		return "The %s is a job for the shed: out here it's bolt-on parts the bike rides without, and small parts like plugs and pads." \
			% PartsDB.slot_name(slot).to_lower()
	if a in ["unbolt", "remove"] and PartsDB.may_be_empty(slot):
		return rig_says(bike, slot, "none")   # (a part it can't do without, the pads say, comes off only to swap it: the fit's asked of the new one)
	if a == "install":
		return rig_says(bike, slot, part)
	return ""


# ---------------------------------------------------------------------------- the wrench in one go

## Why `peer` can't take the part in `action.slot` off with one go of the wrench, putting it down
## by the bike ("spanner_off"), or fit the `action.index`th thing by the bike and bolt it up
## ("spanner_on"); "" when they can.
static func spanner_check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var bike := int(action.get("bike", 0))
	if not Shed.bikes.has(bike):
		return "That bike has gone."
	if Shed.riding(peer) != 0:
		return "Get off your bike first."
	if int(Shed.bikes[bike].get("rider", 0)) != 0:
		return "Someone is riding that bike."
	if not stood_out(bike):
		return "Work on it in the shed." if Shed.bike_at_work(bike) else "Stop and get off first: the spanner works on it stood still."
	match a:
		"spanner_off":
			var slot := str(action.get("slot", ""))
			var item := Shed.item_on(bike, slot)
			if item == 0:
				return "That part isn't fitted."
			var why := _slot_says(bike, slot, "remove", "none")
			if why != "":
				return why
			return Shed.parts_on_it(Shed.bikes[bike], slot)
		"spanner_on":
			var c := FuelShop.cargo_of(bike)
			var i := int(action.get("index", 0))
			if c.is_empty():
				return "There's nothing by the bike to fit."
			if i < 0 or i >= c.size() or (action.has("part") and str(c[i].get("part", "")) != str(action["part"])):
				return "That isn't by the bike any more."
			var part := str(c[i].get("part", ""))
			var kind := PartsDB.kind_of(part)
			if PartsDB.slots_for_kind(kind).is_empty() or PartsDB.is_engine_slot(PartsDB.slots_for_kind(kind)[0]):
				return "The %s doesn't bolt straight on a bike." % PartsDB.part_name(part).to_lower()
			var where := Shed.install_slot_of({"bike": bike, "slot": str(action.get("slot", ""))}, kind, part)
			if where.has("error"):
				return str(where["error"])
			return _slot_says(bike, str(where["slot"]), "install", part)
	return "Unknown spanner job."


## Does a checked "spanner_off" or "spanner_on"; returns what to tell the player.
static func spanner_apply(peer: int, action: Dictionary) -> String:
	var bike := int(action["bike"])
	var host: Dictionary = Shed.bikes[bike]
	match str(action["a"]):
		"spanner_off":
			var slot := str(action["slot"])
			var item := int(host["slots"][slot])
			host["slots"][slot] = 0
			host["bolted"][slot] = false
			Shed._xp(peer, "unbolt", 1.0, "item:%d" % item)
			Shed._xp(peer, "remove", 1.0, "item:%d" % item)
			var name := PartsDB.part_name(str(Shed.items[item]["part"]))
			FuelShop._strap(bike, item)
			return "Took the %s off: it's by the bike (ride off and it's left behind)." % name.to_lower()
		"spanner_on":
			var c: Array = FuelShop.cargo_of(bike).duplicate()
			var i := int(action.get("index", 0))
			var rec: Dictionary = (c[i] as Dictionary).duplicate(true)
			var part := str(rec.get("part", ""))
			var slot := str(Shed.install_slot_of({"bike": bike, "slot": str(action.get("slot", ""))}, PartsDB.kind_of(part), part)["slot"])
			c.remove_at(i)
			host["cargo"] = c
			rec["boxed"] = false
			var item := FuelShop._make_item(rec)
			host["slots"][slot] = item
			host["bolted"][slot] = true
			Shed._move(item, "bike", bike)
			Shed._xp(peer, "bolt", 1.0, "item:%d" % item)
			return "Fitted the %s and bolted it up." % PartsDB.part_name(part).to_lower()
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
	if a.begins_with("spanner_"):
		return spanner_check(peer, action)
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
	if str(action["a"]).begins_with("spanner_"):
		return spanner_apply(peer, action)
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
