class_name Roadside
extends RefCounted
## Fixing a bike at the side of the road on an adventure. Only on an adventure: an ordinary ride
## out of the shed still has no roadside fixing (a bike out on the road is just a bike to ride,
## see Shed.road_bike_block), exactly as before.
##
## An adventure never harms a bike: nothing wears or works loose out there, a drop does no harm
## and the tyres keep their air (Shed._wear_from_ride). What can still want seeing to on the way
## is something the bike already had when it set off: the chain left slack, or the oil low (the
## oil light). Each has a clear symptom (a sound, a dash light) and a hint. And a bike that's run
## out of petrol can be pushed, or towed by a mate.
##
## Stopped on an adventure you get off, and the bike stands at the roadside on its stand (drawn
## for the whole crew by RoadsideView, with its toolbox open and parts out on a cloth when
## they're being worked on). You fix it with only what its toolbox holds: each fix needs its kit
## (the tool roll, a litre of oil), and what gets used up is gone from the box (shown as gone,
## until it's packed again in the shed). No toolbox, or not the right thing in it, and that can't
## be fixed here: push the bike (wheel it along on foot), or a mate tows you to the next stop on
## a strap from their bike.
## With the toolbox open the crew can also take its spanners to the bike's small parts, and fit
## the spare parts packed in it: see ToolboxSpares.
##
## Shared state, all in Shed (so the crew see it and it's saved):
##   bikes[id]["roadside"]  where a bike was left on this adventure, in the route's frame (the
##                          floating origin moves, the route frame doesn't): {trip, x, y, z, yaw,
##                          s, open (the toolbox), out (slots of parts laid out on the cloth)}.
##   bikes[id]["push"]      true while its rider is wheeling it along on foot.
##   bikes[id]["tow"]       the peer whose bike is towing it, while it's on the strap.
##   items[box]["used"]     what's been used up out of a toolbox (gone till it's packed again),
##   items[box]["left"]     and how many goes are left of the kit that has several (the lube).

const KINDS: Array[String] = ["chain_slack", "oil"]
## A chain this slack (mm) is the slack chain fault (the shed's own reading, see BikeBuild).
const SLACK_FAULT := 50.0
## The oil light comes on below this share of the engine's oil.
const OIL_LIGHT := 0.45
const OIL_TOP_UP := 1.0        # litres in the toolbox's bottle
## The toolbox kit that gets used up, and how many goes there are in it (the tool roll and the
## never runs out).
const USES := {"oil": 1, "brake_fluid": 1, "chain_lube": 4}
## Pushing it: walking pace. The strap from a mate's bike: this long (m), and the tow comes off
## once you're this close to the next stop and slowed right down.
const PUSH_SPEED := 1.6
const STRAP := 4.0
const TOW_REACH := 15.0
const TOW_STOPPED := 2.0   # m/s: slower than this counts as stopped when asking for a tow
const STOP_REACH := 30.0

## What each fault is called, how it shows itself, a hint, what it takes to fix (toolbox kit)
## and what gets used up doing it.
const INFO := {
	"chain_slack": {"name": "Slack chain", "light": "",
		"symptom": "A slapping and clunking from the back: the chain's gone slack and snatches on and off the throttle.",
		"hint": "Stop and tighten it: crouch at the chain with the wrench (the tool roll's spanners).",
		"needs": ["tools"]},
	"oil": {"name": "Low oil", "light": "OIL",
		"symptom": "The oil light's on: it's low on oil. Top it up before the engine suffers for it.",
		"hint": "Stop and top it up from the toolbox's bottle of oil (hands, at the engine).",
		"needs": ["oil"]},
}


## The share of its oil the engine has, 0..1 (1 with no engine).
static func oil_level(bike_id: int) -> float:
	var engine := Shed.item_on(bike_id, "engine")
	if engine == 0:
		return 1.0
	var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
	return clampf(float(Shed.items[engine].get("fluid", {}).get("litres", cap)) / maxf(cap, 0.1), 0.0, 1.0)


# ---------------------------------------------------------------------------- what's wrong

## Everything wrong with the bike that a roadside fix can sort out: [{kind, slot}], read off its
## parts (a slack chain, low oil).
static func active(bike_id: int) -> Array:
	var out := []
	if not Shed.bikes.has(bike_id):
		return out
	var chain := Shed.item_on(bike_id, "chain")
	if chain != 0 and float(Shed.items[chain].get("slack", Shed.CHAIN_SLACK_SET)) >= SLACK_FAULT:
		out.append({"kind": "chain_slack", "slot": "chain"})
	if Shed.item_on(bike_id, "engine") != 0 and oil_level(bike_id) < OIL_LIGHT:
		out.append({"kind": "oil", "slot": "engine"})
	return out


## The fault of `kind` on the bike, or {}.
static func find(bike_id: int, kind: String) -> Dictionary:
	for f in active(bike_id):
		if str(f["kind"]) == kind:
			return f
	return {}


## The faults whose fix is done at `slot` (what the crosshair's on).
static func at_slot(bike_id: int, slot: String) -> Array:
	var out := []
	for f in active(bike_id):
		var s := str(f["slot"])
		if s == slot:
			out.append(f)
	return out


## The fault's name.
static func name_of(f: Dictionary) -> String:
	var kind := str(f.get("kind", ""))
	return str(INFO.get(kind, {}).get("name", kind))


## How the fault shows itself, as the rider's told when it's noticed.
static func symptom(f: Dictionary) -> String:
	return str(INFO.get(str(f.get("kind", "")), {}).get("symptom", ""))


static func hint(f: Dictionary) -> String:
	return str(INFO.get(str(f.get("kind", "")), {}).get("hint", ""))


## The kit a fault needs from the toolbox.
static func needs(kind: String) -> Array:
	return INFO.get(kind, {}).get("needs", [])


## What gets used up fixing it.
static func uses(kind: String) -> Array:
	return needs(kind).filter(func(w): return USES.has(str(w)))


## Whether the bike's in a state to want a tow: out of fuel (`dry`, the rider's own tank
## reading) or carrying a roadside fault.
static func needs_tow(bike_id: int, dry := false) -> bool:
	return dry or not active(bike_id).is_empty()


# ---------------------------------------------------------------------------- the toolbox

static func toolbox_of(bike_id: int) -> int:
	return Shed.item_on(bike_id, "toolbox")


## What's in the bike's toolbox now.
static func kit_of(bike_id: int) -> Array:
	var box := toolbox_of(bike_id)
	return Shed.toolbox_contents(box) if box != 0 else []


## What's been used up out of it (gone till it's packed again).
static func used_of(box: int) -> Array:
	var u = Shed.items.get(box, {}).get("used", [])
	return u if u is Array else []


## Goes left of a kit in the box (coats in the can of chain lube): 1 for the rest.
static func goes_left(box: int, what: String) -> int:
	if not Shed.toolbox_contents(box).has(what):
		return 0
	var left = Shed.items[box].get("left", {})
	if left is Dictionary and left.has(what):
		return int(left[what])
	return int(USES.get(what, 1))


## Uses one go of `what` from the toolbox: once the last is gone it comes out of the box and is
## shown as used up.
static func use_kit(box: int, what: String) -> void:
	if not USES.has(what) or not Shed.items.has(box):
		return
	var n := goes_left(box, what) - 1
	var left = Shed.items[box].get("left", {})
	if not (left is Dictionary):
		left = {}
	if n > 0:
		left[what] = n
	else:
		left.erase(what)
		var packed: Array = Shed.toolbox_contents(box).duplicate()
		packed.erase(what)
		Shed.items[box]["contents"] = packed
		var used: Array = used_of(box).duplicate()
		if not used.has(what):
			used.append(what)
		Shed.items[box]["used"] = used
	Shed.items[box]["left"] = left


## Packing `what` in the shed (or emptying the box) makes it whole again: not used up, every go.
static func repacked(box: int, what := "") -> void:
	if not Shed.items.has(box):
		return
	if what == "":
		Shed.items[box].erase("used")
		Shed.items[box].erase("left")
		return
	var used: Array = used_of(box).duplicate()
	used.erase(what)
	Shed.items[box]["used"] = used
	var left = Shed.items[box].get("left", {})
	if left is Dictionary:
		left.erase(what)


## Why the toolbox can't fix `kind` ("" when it can): no toolbox, or not the right kit in it.
static func kit_missing(bike_id: int, kind: String) -> String:
	if toolbox_of(bike_id) == 0:
		return "There's no toolbox on %s, so there's nothing to fix it with out here. Push it, or get a mate to tow you." % str(Shed.bikes[bike_id]["name"])
	var kit := kit_of(bike_id)
	var box := toolbox_of(bike_id)
	for what in needs(kind):
		if not kit.has(what):
			var info: Dictionary = PartsDB.TOOLBOX_CONTENTS.get(str(what), {})
			var gone := used_of(box).has(what)
			return "%s the %s in the toolbox. Push it, or get a mate to tow you." % ["You've used up" if gone else "There's no",
				str(info.get("short", what))] if str(what) == "tools" \
				else "%s the %s in the toolbox." % ["You've used up" if gone else "There's no", str(info.get("short", what))]
	return ""


## The toolbox's lines for the HUD: each thing packed (with goes left), then what's used up.
static func kit_lines(box: int) -> Array:
	var out := []
	if box == 0:
		return out
	for what in Shed.toolbox_contents(box):
		var info: Dictionary = PartsDB.TOOLBOX_CONTENTS.get(str(what), {})
		var n := goes_left(box, str(what))
		out.append({"what": str(what), "name": str(info.get("name", what)), "left": n if USES.has(str(what)) and int(USES[str(what)]) > 1 else -1, "gone": false})
	for what in used_of(box):
		var info: Dictionary = PartsDB.TOOLBOX_CONTENTS.get(str(what), {})
		out.append({"what": str(what), "name": str(info.get("name", what)), "left": 0, "gone": true})
	return out


# ---------------------------------------------------------------------------- where it stands

## Whether the bike was left at the roadside on the adventure on now.
static func parked(bike_id: int) -> bool:
	var r = Shed.bikes.get(bike_id, {}).get("roadside", null)
	return r is Dictionary and Adventure.active() and int(r.get("trip", 0)) == int(Shed.adventure.get("id", -1)) \
		and int(Shed.bikes[bike_id].get("rider", 0)) == 0


static func spot_of(bike_id: int) -> Dictionary:
	var r = Shed.bikes.get(bike_id, {}).get("roadside", null)
	return r if r is Dictionary and int(r.get("trip", 0)) == int(Shed.adventure.get("id", -1)) else {}


## A roadside record for a bike stood at local `xf` in `world` (route frame, so it holds still
## as the origin moves).
static func spot_for(world: AdventureWorld, xf: Transform3D) -> Dictionary:
	var xz := world.route_xz(xf.origin)
	var fwd := -xf.basis.z
	var s := world.distance_of(xf.origin)
	return {"x": xz[0], "y": xf.origin.y, "z": xz[1], "yaw": atan2(-fwd.x, -fwd.z), "s": maxf(s, 0.0)}


## The local transform of a roadside record in `world`: on the crew's ferry's deck where it was left on one (and the
## boat's there to stand on: FerryCrossing.deck_xf), as the boat's drawn when `drawn` (between physics ticks).
static func xf_in(world: AdventureWorld, r: Dictionary, drawn := false) -> Transform3D:
	var deck = r.get("deck")
	if deck is Dictionary and world != null:
		var ferry := world.get_node_or_null("FerryCrossing") as FerryCrossing
		var boat = ferry.deck_xf(str(deck.get("id", "")), drawn) if ferry != null else null
		if boat is Transform3D:
			return (boat as Transform3D) * Transform3D(Basis(Vector3.UP, float(deck.get("yaw", 0.0))),
				Vector3(float(deck.get("x", 0.0)), float(deck.get("y", 0.0)), float(deck.get("z", 0.0))))
	return Transform3D(Basis(Vector3.UP, float(r.get("yaw", 0.0))),
		world.to_local_pos(float(r.get("x", 0.0)), float(r.get("y", 0.0)), float(r.get("z", 0.0))))


## A roadside record's place on a ferry's deck, sanitised (null for none): {id (the ferry route's), x, y, z (in the
## boat's frame), yaw (against the boat's)}.
static func deck_of(r: Dictionary):
	var d = r.get("deck")
	if not d is Dictionary or str(d.get("id", "")) == "":
		return null
	return {"id": str(d["id"]), "x": float(d.get("x", 0.0)), "y": float(d.get("y", 0.0)), "z": float(d.get("z", 0.0)),
		"yaw": float(d.get("yaw", 0.0))}


## The next stop along the road after `s` (any site but the start), or {}.
static func next_stop(route: AdventureRoute, s: float) -> Dictionary:
	var best := {}
	for st in route.sites:
		if str(st.get("kind", "")) == "start" or float(st["s"]) < s - 10.0:
			continue
		if best.is_empty() or float(st["s"]) < float(best["s"]):
			best = st
	return best


# ---------------------------------------------------------------------------- actions

static func _on_adventure(bike_id: int) -> String:
	if not Adventure.active():
		return "Out here %s is just a bike to ride. Ride it back to the shed to work on it." % str(Shed.bikes[bike_id]["name"]) \
			if Shed.bikes.has(bike_id) else "There's no adventure on."
	return ""


static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var bike_id := int(action.get("bike", 0))
	match a:
		"roadside_fix", "roadside_open":
			if not Shed.bikes.has(bike_id):
				return "That bike has gone."
			var why := _on_adventure(bike_id)
			if why != "":
				return why
			if not parked(bike_id):
				return "Stop and get off first: you can only work on it at the roadside."
			if Shed.held_by(peer) != 0:
				return "Put down what you're holding first."
			if a == "roadside_open":
				if toolbox_of(bike_id) == 0:
					return "There's no toolbox on it."
				return ""
			var kind := str(action.get("fault", ""))
			if find(bike_id, kind).is_empty():
				return "Nothing like that wrong with it."
			if kind == "chain_slack" and not action.get("crouched", false):
				return "Crouch down to get at the chain ({crouch})."
			return kit_missing(bike_id, kind)
		"roadside_push":
			var why := _on_adventure(bike_id)
			if why != "":
				return why
			if not parked(bike_id):
				return "It's not stood at the roadside."
			if Shed.riding(peer) != 0:
				return "You're riding already."
			if Shed.held_by(peer) != 0:
				return "Put down what you're holding first."
			return ""
		"roadside_tow":
			var towed := Shed.riding(peer)
			if not Adventure.active() or towed == 0:
				return "Get on your bike first, then a mate can tow you."
			if not needs_tow(towed, bool(action.get("dry", false))):
				return "Your bike runs fine: no tow needed."
			var by := int(action.get("by", 0))
			var theirs := Shed.riding(by)
			if by == peer or theirs == 0:
				return "Nobody's on a bike to tow you."
			if int(Shed.bikes[theirs].get("tow", 0)) != 0:
				return "Their bike's on a tow strap itself."
			for id in Shed.bikes:
				if int(Shed.bikes[id].get("tow", 0)) == by and int(id) != towed:
					return "They're towing someone already."
			return ""
		"roadside_untow":
			var ridden := Shed.riding(peer)
			for id in Shed.bikes:
				if int(Shed.bikes[id].get("tow", 0)) != 0 and (int(id) == ridden or int(Shed.bikes[id]["tow"]) == peer):
					return ""
			return "Nobody's on a tow strap."
	return "Unknown roadside action."


## Applies a checked action; returns what to tell the player (or, starting with "*", the crew).
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var bike_id := int(action.get("bike", 0))
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match a:
		"roadside_open":
			var r: Dictionary = Shed.bikes[bike_id]["roadside"]
			r["open"] = bool(action.get("open", not r.get("open", false)))
			return ""
		"roadside_fix":
			var kind := str(action.get("fault", ""))
			var text := _fix(peer, bike_id, kind)
			var box := toolbox_of(bike_id)
			for what in uses(kind):
				use_kit(box, str(what))
			_lay_out(bike_id, "tools")
			AdventureDiary.fixed(peer, str(INFO.get(kind, {}).get("name", kind)))
			return text
		"roadside_push":
			var bike: Dictionary = Shed.bikes[bike_id]
			bike["rider"] = peer
			bike["stand"] = ""
			bike["pusher"] = 0
			bike["push"] = true
			if Shed.crew.has(peer):
				Shed.crew[peer]["riding"] = bike_id
			return "You're wheeling %s along. {interact} to stop and stand it on its stand." % str(bike["name"])
		"roadside_tow":
			var towed := Shed.riding(peer)
			Shed.bikes[towed]["tow"] = int(action["by"])
			Shed.bikes[towed].erase("push")
			var by_name := str(Shed.crew.get(int(action["by"]), {}).get("name", "A mate"))
			AdventureDiary.towed(peer, int(action["by"]))
			return "*%s ties a tow strap from %s's bike to %s's: on to the next stop." % [who, by_name, who]
		"roadside_untow":
			var ridden := Shed.riding(peer)
			for id in Shed.bikes:
				if int(Shed.bikes[id].get("tow", 0)) != 0 and (int(id) == ridden or int(Shed.bikes[id]["tow"]) == peer):
					Shed.bikes[id].erase("tow")
			return "*The tow strap's off."
	return ""


## Puts something out on the cloth beside the bike (the toolbox's kit, a part off it).
static func _lay_out(bike_id: int, what: String) -> void:
	var r = Shed.bikes[bike_id].get("roadside", null)
	if not (r is Dictionary):
		return
	var out: Array = r.get("out", [])
	if not out.has(what):
		out.append(what)
	r["out"] = out


## Does the fix. Returns what the player's told.
static func _fix(peer: int, bike_id: int, kind: String) -> String:
	match kind:
		"chain_slack":
			var chain := Shed.item_on(bike_id, "chain")
			Shed.items[chain]["slack"] = Shed.CHAIN_SLACK_SET
			Shed._xp(peer, "chain_tension", 1.0, "item:%d" % chain)
			return "Chain tightened back to %d mm of slack at the roadside." % roundi(Shed.CHAIN_SLACK_SET)
		"oil":
			var engine := Shed.item_on(bike_id, "engine")
			var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
			var fl: Dictionary = Shed.items[engine].get("fluid", {"litres": 0.0, "type": "semi_10w40", "age": 0.0})
			fl["litres"] = minf(cap, float(fl.get("litres", 0.0)) + OIL_TOP_UP)
			Shed.items[engine]["fluid"] = fl
			return "Topped the oil up from the toolbox's bottle: %.1f of %.1f litres, the light's off." % [float(fl["litres"]), cap]
	return "Fixed %s." % str(Shed.bikes[bike_id]["name"])


# ---------------------------------------------------------------------------- the end of a trip

## The adventure's over (or a save is loading): bikes left at the roadside come home to a bay,
## and nobody's pushing or towing any more.
static func bring_home() -> void:
	for id in Shed.bikes:
		var bike: Dictionary = Shed.bikes[id]
		bike.erase("push")
		bike.erase("tow")
		if bike.has("roadside"):
			bike.erase("roadside")
			if int(bike.get("rider", 0)) == 0:
				bike["xf"] = home_spot(int(id))
				bike["stand"] = ""


## A free bay for a bike brought home, or a place in the yard (as Main.garage_spot).
static func home_spot(bike_id: int) -> Transform3D:
	var own := int(Shed.bikes[bike_id].get("bay", -1))
	var order := [own] if own >= 0 and own < Workshop.bay_count() else []
	for bay in Workshop.bay_count():
		if bay != own:
			order.append(bay)
	for bay in order:
		var o := Workshop.bay_transform(bay).origin
		if not Shed.holograms.has(bay) and not _bike_near(o, 2.5, bike_id):
			return Workshop.bay_transform(bay)
	for i in 24:
		var at := Vector3(14.0, 0.0, 32.0) + Vector3(float(i % 6) * 2.0, 0.0, -float(i / 6) * 3.0)
		if not _bike_near(at, 1.4, bike_id):
			return Transform3D(Basis(), at)
	return Transform3D(Basis(), Vector3(14.0, 0.0, 32.0))


static func _bike_near(at: Vector3, r: float, except: int) -> bool:
	for id in Shed.bikes:
		if int(id) != except and not Shed.bikes[id].has("roadside") and (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(at) < r:
			return true
	return false
