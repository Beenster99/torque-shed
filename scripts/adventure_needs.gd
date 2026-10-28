class_name AdventureNeeds
extends RefCounted
## Stopping on an adventure ride: sitting down at a bench (beside your mates if you like), and
## sleeping at an inn or campsite, which skips the night for the whole crew and saves the
## adventure so it can be carried on another day from the shed. (Riders used to get hungry,
## thirsty and tired as well; that's gone, so nothing here wears down.)
##
## Shared state, host-run, in Shed.adventure["needs"]: peer -> {sat (the seat place's key, ""
## standing), sat_s (how far along the road the seat is), bed, bed_s (the same for a bed), bed_at
## (on the network ride, the bed's place in the region's frame)}. AdventureNeedsView does the
## sitting down and lying in bed.
##
## Shed.adventure_save: {} or the adventure put away by the last night's sleep (see make_save),
## kept in the shed's save so the host can carry it on later (adventure_resume, see Adventure).
##
## Actions (Shed.request): needs_sit {key, s, on}; needs_bed {key, s, at, on}; needs_sleep (the
## host, everyone abed).

## A night's sleep ends at this hour.
const MORNING := 7.0
## The groups the stops' interaction nodes are in (see AdventureNeedsView).
const SEAT_GROUP := "adv_seat"
const BED_GROUP := "adv_bed"


static func defaults() -> Dictionary:
	return {"sat": "", "sat_s": 0.0, "bed": "", "bed_s": 0.0}


## Where every rider on the adventure is sat or lying ({} with no adventure on).
static func all() -> Dictionary:
	if not Adventure.active():
		return {}
	if not (Shed.adventure.get("needs") is Dictionary):
		Shed.adventure["needs"] = {}
	return Shed.adventure["needs"]


## Where `peer` is sat or lying, or {} if they're not on the adventure.
static func of(peer: int) -> Dictionary:
	var n = all().get(peer, {})
	return n if n is Dictionary else {}


## Whether `peer` is sat down, or in bed.
static func sat(peer: int) -> bool:
	return str(of(peer).get("sat", "")) != ""


static func abed(peer: int) -> bool:
	return str(of(peer).get("bed", "")) != ""


## A rider joined the adventure: on their feet.
static func joined(peer: int) -> void:
	all()[peer] = defaults()


# ---------------------------------------------------------------------------- seats and beds

## Whether every rider on the adventure (still here) is in a bed.
static func all_abed() -> bool:
	var needs := all()
	if needs.is_empty():
		return false
	for p in needs:
		if Shed.crew.has(p) and str(needs[p].get("bed", "")) == "":
			return false
	return true


## How many of the riders are in bed, and how many there are: [abed, all].
static func bed_count() -> Array:
	var needs := all()
	var n := 0
	var total := 0
	for p in needs:
		if Shed.crew.has(p):
			total += 1
			if str(needs[p].get("bed", "")) != "":
				n += 1
	return [n, total]


## Whether someone other than `peer` has the seat or bed place `key` (`field` "sat" or "bed").
static func taken(key: String, field: String, peer: int) -> bool:
	var needs := all()
	for p in needs:
		if int(p) != peer and str(needs[p].get(field, "")) == key:
			return true
	return false


# ---------------------------------------------------------------------------- saving a night's stop

## The adventure as it stands, put away to carry on another day: the road (everything in
## Shed.adventure but who's on it now, and an old ride's fork votes and picks), where each rider is by name (how far
## along the road, and on the network ride the bed's place in the region's frame, "where"), the time.
static func make_save() -> Dictionary:
	var adv := {}
	for k in Shed.adventure:
		if not str(k) in ["id", "riders", "arrived", "arrived_name", "needs", "resume", "resume_at", "needs_saved", "votes", "picks"]:
			adv[k] = Shed.adventure[k]
	var at := {}
	var where := {}
	var needs := all()
	for p in needs:
		var who := str(Shed.crew.get(p, {}).get("name", ""))
		if who == "":
			continue
		var n: Dictionary = needs[p]
		at[who] = float(n.get("bed_s", n.get("sat_s", 0.0)))
		if not _spot(n.get("bed_at")).is_empty():
			where[who] = _spot(n["bed_at"])
	return {"adventure": adv.duplicate(true), "at": at, "where": where, "hours": MORNING,
		"nights": int(Shed.adventure.get("nights", 0)), "by": str(Shed.adventure.get("by", ""))}


## A saved adventure as received or loaded: kept if it has a road, else none.
static func sanitize_save(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("adventure") is Dictionary) or not (v["adventure"] as Dictionary).has("seed"):
		return {}
	var out: Dictionary = v.duplicate(true)
	if not (out.get("at") is Dictionary):
		out["at"] = {}
	out.erase("needs")   # (an older save's meters: there are none now)
	var where := {}
	if out.get("where") is Dictionary:
		for who in out["where"]:
			var spot := _spot(out["where"][who])
			if not spot.is_empty():
				where[str(who)] = spot
	out["where"] = where
	out["hours"] = float(out.get("hours", MORNING))
	return out


## How far along a saved adventure's riders were: the furthest-back one (where everyone not
## named in it starts too).
static func save_s(save: Dictionary) -> float:
	var at: Dictionary = save.get("at", {})
	var lo := INF
	for who in at:
		lo = minf(lo, float(at[who]))
	return 0.0 if lo == INF else lo


## Where `who` carries a running adventure on from (Shed.adventure["resume"]), -1 when it isn't
## being carried on.
static func resume_s(who: String) -> float:
	var r = Shed.adventure.get("resume", null)
	if not (r is Dictionary) or (r as Dictionary).is_empty():
		return -1.0
	if r.has(who):
		return float(r[who])
	var lo := INF
	for k in r:
		lo = minf(lo, float(r[k]))
	return lo


## Where `who` slept on a network ride carried on (Shed.adventure["resume_at"]): [x, z, heading] in the region's frame,
## or [] (not carried on, or not slept on the network: then by resume_s).
static func resume_at(who: String) -> Array:
	var r = Shed.adventure.get("resume_at", null)
	if not (r is Dictionary) or not (r as Dictionary).has(who):
		return []
	return _spot(r[who])


# ---------------------------------------------------------------------------- actions

static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if not Adventure.active():
		return "There's no adventure on."
	if a != "needs_sleep" and of(peer).is_empty():
		return "You're not on the adventure."
	match a:
		"needs_sit", "needs_bed":
			var field := "sat" if a == "needs_sit" else "bed"
			if bool(action.get("on", true)):
				var key := str(action.get("key", ""))
				if key == "":
					return "Sit where?"
				if taken(key, field, peer):
					return "Someone's there already." if field == "sat" else "That bed's taken."
				if Shed.riding(peer) != 0:
					return "Get off the bike first."
		"needs_sleep":
			if not _is_host(peer):
				return "The host calls it a night."
			if not all_abed():
				var c := bed_count()
				return "Not everyone's in bed yet (%d of %d)." % [c[0], c[1]]
		_:
			return "Unknown action."
	return ""


## Applies a checked action; returns what to tell the player (or, starting with "*", the crew).
static func apply(peer: int, action: Dictionary) -> String:
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match str(action.get("a", "")):
		"needs_sit":
			var n := of(peer)
			if not bool(action.get("on", true)):
				n["sat"] = ""
				return ""
			n["sat"] = str(action["key"]).left(80)
			n["sat_s"] = float(action.get("s", 0.0))
			n["bed"] = ""
			return ""
		"needs_bed":
			var n := of(peer)
			if not bool(action.get("on", true)):
				n["bed"] = ""
				return ""
			n["bed"] = str(action["key"]).left(80)
			n["bed_s"] = float(action.get("s", 0.0))
			n["bed_at"] = _spot(action.get("at"))
			n["sat"] = ""
			var c := bed_count()
			if c[0] >= c[1]:
				return "*Everyone's in bed. The host can call it a night."
			return "*%s has gone to bed (%d of %d)." % [who, c[0], c[1]]
		"needs_sleep":
			Shed.adventure["nights"] = int(Shed.adventure.get("nights", 0)) + 1
			if Daylight.current:
				Daylight.current.set_time(MORNING)
			Shed.adventure_save = make_save()
			return "*Everyone sleeps till morning. The adventure's saved: carry on now, or another day from the shed (the host's menu, {menu})."
	return ""


## A bed's place in the region's frame as an action carries it ([x, z, heading]), or [] when it's not one.
static func _spot(v) -> Array:
	if not (v is Array) or (v as Array).size() != 3:
		return []
	for x in v:
		if not (x is float or x is int) or not is_finite(float(x)):
			return []
	return [float(v[0]), float(v[1]), float(v[2])]


static func _and_list(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])
