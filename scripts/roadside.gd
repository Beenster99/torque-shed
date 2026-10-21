class_name Roadside
extends RefCounted
## Breaking down out on an adventure, and fixing it at the side of the road. Only on an
## adventure: an ordinary ride out of the shed still has no roadside fixing (a bike out on the
## road is just a bike to ride, see Shed.road_bike_block), exactly as before.
##
## What can go wrong (as well as punctures, see Puncture): the chain goes slack or snaps, the
## oil runs low (the oil light), a bolt works loose and something rattles, a drop snaps the
## clutch or brake lever, a fuse blows (the lights, or the ignition). The chance rises with the
## parts' wear, loose ground (gravel and sand most), drops, and maintenance skipped (a dry chain,
## old oil); tuned so a two-hour adventure (gravel and all) sees about one thing go wrong, a
## puncture included, on a fairly kept bike: not several.
## Each has a clear symptom (a sound, a dash light, the way it rides) and a hint.
##
## Stopped on an adventure you get off, and the bike stands at the roadside on its stand (drawn
## for the whole crew by RoadsideView, with its toolbox open and parts out on a cloth when
## they're being worked on). You fix it with only what its toolbox holds: each fix needs its kit
## (the tool roll, a spare chain, a litre of oil, levers, fuses, the plug kit, the pump), and what
## gets used up is gone from the box (shown as gone, until it's packed again in the shed). No
## toolbox, or not the right thing in it, and that can't be fixed here: push the bike (wheel it
## along on foot), or a mate tows you to the next stop on a strap from their bike.
## With the toolbox open the crew can also take its spanners to the bike's small parts, and fit
## the spare parts packed in it: see ToolboxSpares.
##
## Shared state, all in Shed (so the crew see it and it's saved):
##   bikes[id]["faults"]    {chain_snap: true, rattle: slot, lever: "clutch"|"brake",
##                           fuse: "lights"|"ignition"}; a slack chain and low oil are the
##                           chain's own slack and the engine's own oil, as in the shed.
##   bikes[id]["roadside"]  where a bike was left on this adventure, in the route's frame (the
##                          floating origin moves, the route frame doesn't): {trip, x, y, z, yaw,
##                          s, open (the toolbox), out (slots of parts laid out on the cloth)}.
##   bikes[id]["push"]      true while its rider is wheeling it along on foot.
##   bikes[id]["tow"]       the peer whose bike is towing it, while it's on the strap.
##   items[box]["used"]     what's been used up out of a toolbox (gone till it's packed again),
##   items[box]["left"]     and how many goes are left of the kit that has several (plugs, fuses).

const KINDS: Array[String] = ["chain_slack", "chain_snap", "oil", "rattle", "lever", "fuse"]
## Chance of each going wrong per km on tarmac, on a well kept bike.
const PER_KM := {"chain_slack": 0.00025, "chain_snap": 0.00002, "oil": 0.00014, "rattle": 0.0003, "fuse": 0.00011, "lever": 0.0}
## How much more often things shake loose or go wrong on each surface.
const SURFACE := {"tarmac": 1.0, "concrete": 1.0, "gravel": 2.6, "dirt": 2.2, "sand": 2.2, "snow": 1.4, "grass": 1.8}
## Chance a drop (a crash) snaps a lever, or knocks something loose.
const DROP := {"lever": 0.4, "rattle": 0.15}
## A chain this slack (mm) is the slack chain fault (the shed's own reading, see BikeBuild).
const SLACK_FAULT := 50.0
const SLACK_GONE := 64.0       # how slack a chain goes when it's let go
## The oil light comes on below this share of the engine's oil, and a leak leaves it at OIL_LEFT.
const OIL_LIGHT := 0.45
const OIL_LEFT := 0.3
const OIL_TOP_UP := 1.0        # litres in the toolbox's bottle
## The parts that can work loose and rattle, in the order they're picked from (those fitted).
const RATTLE_SLOTS: Array[String] = ["exhaust", "front_mudguard", "number_boards", "side_panels", "headlight", "mirrors",
	"top_box", "panniers", "fairing", "indicators", "guards", "tail"]
## The toolbox kit that gets used up, and how many goes there are in it (the tool roll and the
## pump never run out).
const USES := {"plug_kit": 3, "spare_chain": 1, "oil": 1, "brake_fluid": 1, "chain_lube": 4, "levers": 2, "fuses": 3}
## The fuse box is under the seat; the clutch lever's on the bars, the brake lever's the master's.
const FUSE_SLOTS: Array[String] = ["saddle", "dashboard", "headlight", "ecu"]
const LEVER_SLOTS: Array[String] = ["handlebars", "front_master"]
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
	"chain_snap": {"name": "Snapped chain", "light": "",
		"symptom": "A bang and a clatter, and the engine revs with nothing driving the back wheel: the chain's snapped.",
		"hint": "Fit the spare chain with its split link (crouch at the chain, hands). No spare? Push it, or get a tow.",
		"needs": ["tools", "spare_chain"]},
	"oil": {"name": "Low oil", "light": "OIL",
		"symptom": "The oil light's on: it's low on oil, and the engine wears fast like this.",
		"hint": "Stop and top it up from the toolbox's bottle of oil (hands, at the engine).",
		"needs": ["oil"]},
	"rattle": {"name": "Rattling part", "light": "",
		"symptom": "Something's rattling: a bolt has worked loose.",
		"hint": "Stop, find what's rattling and bolt it up tight with the wrench (the tool roll).",
		"needs": ["tools"]},
	"lever": {"name": "Broken lever", "light": "",
		"symptom": "The lever snapped off in the drop.",
		"hint": "Fit a spare lever (hands, at the bars) from the toolbox's spare levers and the tool roll.",
		"needs": ["tools", "levers"]},
	"fuse": {"name": "Blown fuse", "light": "",
		"symptom": "A fuse has blown.",
		"hint": "Swap it from the spares in the toolbox: the fuse box is under the seat (hands, at the seat).",
		"needs": ["fuses"]},
	"puncture": {"name": "Puncture", "light": "",
		"symptom": "The tyre's going soft: it squirms and wallows. A puncture.",
		"hint": "Stop and plug it with the toolbox's plug kit (hands, at the tyre), then pump it up with the mini pump.",
		"needs": ["plug_kit"]},
	"pressure": {"name": "Soft tyre", "light": "",
		"symptom": "The tyre's soft.",
		"hint": "Pump it up with the toolbox's mini pump (hands, at the tyre, the second button).",
		"needs": ["pump"]},
}


# ---------------------------------------------------------------------------- the odds

## The chance per km of each fault for a bike in condition `c`, on `surface`:
## c = {chain_wear, chain_lube (0..1), chain_slack (mm), oil_age, oil_level (0..1), engine_wear,
## wear (the bike's parts on average)}. Pure, for the tests.
static func rates(c: Dictionary, surface: String) -> Dictionary:
	var ground := float(SURFACE.get(surface, 1.5))
	var shake := sqrt(ground)
	var chain_wear := clampf(float(c.get("chain_wear", 0.0)), 0.0, 1.0)
	var dry := 1.0 - clampf(float(c.get("chain_lube", 1.0)), 0.0, 1.0)
	var slack := float(c.get("chain_slack", 30.0))
	var wear := clampf(float(c.get("wear", 0.0)), 0.0, 1.0)
	var out := {}
	# A worn, dry chain stretches; one already slack goes on slackening, and loose ground snatches it.
	out["chain_slack"] = 0.0 if slack >= SLACK_FAULT else float(PER_KM["chain_slack"]) * ground * (1.0 + 4.0 * chain_wear) \
		* (1.0 + 2.0 * dry) * (2.0 if slack > 40.0 else 1.0)
	# Snapping takes a worn, dry, slack chain (or very bad luck).
	out["chain_snap"] = float(PER_KM["chain_snap"]) * ground * (1.0 + 30.0 * chain_wear * chain_wear) * (1.0 + 4.0 * dry) \
		* (3.0 if slack >= SLACK_FAULT else 1.0)
	# Old oil and a worn engine burn and weep it; one already low doesn't go low again.
	out["oil"] = 0.0 if float(c.get("oil_level", 1.0)) < OIL_LIGHT else float(PER_KM["oil"]) * shake \
		* (1.0 + 3.0 * clampf(float(c.get("engine_wear", 0.0)), 0.0, 1.0)) * (1.0 + clampf(float(c.get("oil_age", 0.0)), 0.0, 3.0))
	out["rattle"] = float(PER_KM["rattle"]) * ground * (1.0 + 3.0 * wear)
	out["fuse"] = float(PER_KM["fuse"]) * shake * (1.0 + 2.0 * wear)
	out["lever"] = 0.0
	return out


## The fault (a KINDS id) `km` of riding at `rates` brings, from a roll 0..1, or "".
static func roll(rate_of: Dictionary, km: float, roll_value: float) -> String:
	var acc := 0.0
	for k in KINDS:
		acc += float(rate_of.get(k, 0.0)) * km
		if roll_value < acc:
			return k
	return ""


## What a drop brings, from two rolls 0..1: the faults it caused (a lever, something loose).
static func drop_faults(roll_lever: float, roll_rattle: float) -> Array:
	var out := []
	if roll_lever < float(DROP["lever"]):
		out.append("lever")
	if roll_rattle < float(DROP["rattle"]):
		out.append("rattle")
	return out


## The condition rates() wants, read from bike `bike_id` in the shed.
static func condition(bike_id: int) -> Dictionary:
	var out := {}
	var chain := Shed.item_on(bike_id, "chain")
	if chain != 0:
		var ch: Dictionary = Shed.items[chain]
		out["chain_wear"] = float(ch.get("wear", 0.0))
		out["chain_lube"] = float(ch.get("lube", 1.0))
		out["chain_slack"] = float(ch.get("slack", Shed.CHAIN_SLACK_SET))
	var engine := Shed.item_on(bike_id, "engine")
	if engine != 0:
		var en: Dictionary = Shed.items[engine]
		out["engine_wear"] = float(en.get("wear", 0.0))
		out["oil_level"] = oil_level(bike_id)
		out["oil_age"] = float(en.get("fluid", {}).get("age", 0.0))
	var total := 0.0
	var n := 0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0:
			total += float(Shed.items[id].get("wear", 0.0))
			n += 1
	out["wear"] = total / maxf(float(n), 1.0)
	return out


## The share of its oil the engine has, 0..1 (1 with no engine).
static func oil_level(bike_id: int) -> float:
	var engine := Shed.item_on(bike_id, "engine")
	if engine == 0:
		return 1.0
	var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
	return clampf(float(Shed.items[engine].get("fluid", {}).get("litres", cap)) / maxf(cap, 0.1), 0.0, 1.0)


# ---------------------------------------------------------------------------- what's wrong

static func faults_of(bike_id: int) -> Dictionary:
	var f = Shed.bikes.get(bike_id, {}).get("faults", {})
	return f if f is Dictionary else {}


## Everything wrong with the bike that a roadside fix can sort out: [{kind, slot, detail}], the
## stored faults and the ones read off its parts (a slack chain, low oil, a puncture, a soft tyre).
static func active(bike_id: int) -> Array:
	var out := []
	if not Shed.bikes.has(bike_id):
		return out
	var f := faults_of(bike_id)
	var chain := Shed.item_on(bike_id, "chain")
	if f.get("chain_snap", false):
		out.append({"kind": "chain_snap", "slot": "chain"})
	elif chain != 0 and float(Shed.items[chain].get("slack", Shed.CHAIN_SLACK_SET)) >= SLACK_FAULT:
		out.append({"kind": "chain_slack", "slot": "chain"})
	if Shed.item_on(bike_id, "engine") != 0 and oil_level(bike_id) < OIL_LIGHT:
		out.append({"kind": "oil", "slot": "engine"})
	if str(f.get("rattle", "")) != "":
		out.append({"kind": "rattle", "slot": str(f["rattle"])})
	if str(f.get("lever", "")) != "":
		out.append({"kind": "lever", "slot": "handlebars" if str(f["lever"]) == "clutch" else "front_master", "detail": str(f["lever"])})
	if str(f.get("fuse", "")) != "":
		out.append({"kind": "fuse", "slot": "saddle", "detail": str(f["fuse"])})
	for side in ["front", "rear"]:
		var tyre := Shed.item_on(bike_id, side + "_tyre")
		if tyre == 0:
			continue
		if Puncture.punctured(Shed.items[tyre]):
			out.append({"kind": "puncture", "slot": side + "_tyre", "detail": side})
		elif Puncture.lost(Shed.items[tyre]) >= 0.05:
			out.append({"kind": "pressure", "slot": side + "_tyre", "detail": side})
	return out


## The fault of `kind` on the bike (and `detail`, a tyre's side), or {}.
static func find(bike_id: int, kind: String, detail := "") -> Dictionary:
	for f in active(bike_id):
		if str(f["kind"]) == kind and (detail == "" or str(f.get("detail", "")) == detail):
			return f
	return {}


## The faults whose fix is done at `slot` (what the crosshair's on).
static func at_slot(bike_id: int, slot: String) -> Array:
	var out := []
	for f in active(bike_id):
		var s := str(f["slot"])
		if s == slot or (str(f["kind"]) == "fuse" and FUSE_SLOTS.has(slot)) or (str(f["kind"]) == "lever" and LEVER_SLOTS.has(slot)):
			out.append(f)
	return out


## The fault's name, with which lever or fuse, or which tyre.
static func name_of(f: Dictionary) -> String:
	var kind := str(f.get("kind", ""))
	var n := str(INFO.get(kind, {}).get("name", kind))
	match kind:
		"lever":
			return "Broken %s lever" % str(f.get("detail", "clutch"))
		"fuse":
			return "Blown fuse (%s)" % ("the lights" if str(f.get("detail", "")) == "lights" else "the ignition")
		"puncture", "pressure":
			return "%s (%s tyre)" % [n, str(f.get("detail", "rear"))]
		"rattle":
			return "Rattling %s" % PartsDB.slot_name(str(f.get("slot", ""))).to_lower()
	return n


## How the fault shows itself, as the rider's told when it happens.
static func symptom(f: Dictionary) -> String:
	var kind := str(f.get("kind", ""))
	match kind:
		"lever":
			return "The %s lever snapped off in the drop: %s" % [str(f.get("detail", "clutch")),
				"the gears crunch and shift slowly without it." if str(f.get("detail", "")) == "clutch" else "the front brake's next to useless."]
		"fuse":
			return "A fuse has blown: %s" % ("the headlight's out." if str(f.get("detail", "")) == "lights"
				else "the engine cut out and the dash went dark. It won't start.")
		"rattle":
			return "Something's rattling: the %s has worked loose." % PartsDB.slot_name(str(f.get("slot", ""))).to_lower()
	return str(INFO.get(kind, {}).get("symptom", ""))


static func hint(f: Dictionary) -> String:
	return str(INFO.get(str(f.get("kind", "")), {}).get("hint", ""))


## The kit a fault needs from the toolbox.
static func needs(kind: String) -> Array:
	return INFO.get(kind, {}).get("needs", [])


## What gets used up fixing it.
static func uses(kind: String) -> Array:
	return needs(kind).filter(func(w): return USES.has(str(w)))


## Whether a fault stops the bike: it won't go under its own power.
## Whether the bike's in a state to want a tow: dead, out of fuel (`dry`, the rider's own tank
## reading) or carrying a roadside fault.
static func needs_tow(bike_id: int, dry := false) -> bool:
	return dry or dead(bike_id) or not active(bike_id).is_empty()


static func dead(bike_id: int) -> bool:
	var f := faults_of(bike_id)
	return f.get("chain_snap", false) or str(f.get("fuse", "")) == "ignition"


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


## Goes left of a kit in the box (plugs in the plug kit, fuses): 1 for the rest.
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
				str(info.get("short", what))] if kind in ["chain_snap", "puncture"] or str(what) == "tools" \
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


## The local transform of a roadside record in `world`.
static func xf_in(world: AdventureWorld, r: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(r.get("yaw", 0.0))),
		world.to_local_pos(float(r.get("x", 0.0)), float(r.get("y", 0.0)), float(r.get("z", 0.0))))


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
		"roadside_fault":
			var ridden := Shed.riding(peer)
			if not Adventure.active() or ridden == 0:
				return "Only out on an adventure."
			var kind := str(action.get("kind", ""))
			if not KINDS.has(kind):
				return "Unknown fault."
			if kind == "lever" and Shed.item_on(ridden, "handlebars") == 0:
				return "No bars to snap a lever off."
			if kind == "rattle" and _rattle_slot(ridden, str(action.get("slot", ""))) == "":
				return "Nothing to work loose."
			if not find(ridden, kind).is_empty() or (kind == "chain_slack" and not find(ridden, "chain_snap").is_empty()):
				return "That's gone already."
			if kind in ["chain_slack", "chain_snap"] and Shed.item_on(ridden, "chain") == 0:
				return "There's no chain."
			if kind == "oil" and Shed.item_on(ridden, "engine") == 0:
				return "There's no engine."
			return ""
		"roadside_fix", "roadside_open", "roadside_pump":
			if not Shed.bikes.has(bike_id):
				return "That bike has gone."
			var at_shed := a == "roadside_fix" and Shed.bike_at_work(bike_id) and str(action.get("fault", "")) in ["lever", "fuse"] \
				and not Adventure.active()
			if not at_shed:
				var why := _on_adventure(bike_id)
				if why != "":
					return why
				if not parked(bike_id):
					return "Stop and get off first: you can only work on it at the roadside."
			elif int(Shed.bikes[bike_id].get("rider", 0)) != 0:
				return "Someone is riding that bike."
			if Shed.held_by(peer) != 0:
				return "Put down what you're holding first."
			if a == "roadside_open":
				if toolbox_of(bike_id) == 0:
					return "There's no toolbox on it."
				return ""
			var kind := str(action.get("fault", "puncture" if a == "roadside_fix" and action.has("side") else ""))
			if a == "roadside_pump":
				kind = "pressure"
			var detail := str(action.get("side", ""))
			var f := find(bike_id, kind, detail)
			if a == "roadside_pump":
				var tyre := Shed.item_on(bike_id, detail + "_tyre")
				if tyre == 0 or Puncture.lost(Shed.items[tyre]) < 0.05:
					return "It's up to its pressure."
				if Puncture.punctured(Shed.items[tyre]):
					return "It's still punctured: plug it first, or it'll just go down again."
				f = {"kind": "pressure"}
			if f.is_empty():
				return "Nothing like that wrong with it."
			if kind in ["chain_slack", "chain_snap"] and not action.get("crouched", false):
				return "Crouch down to get at the chain ({crouch})."
			if at_shed:
				return ""
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
		"roadside_fault":
			_break(Shed.riding(peer), str(action["kind"]), action)
			AdventureDiary.broke(peer, str(INFO.get(str(action["kind"]), {}).get("name", "a fault")))
			return ""   # the rider's own game tells them, as their bike changes (Main._sync_faults)
		"roadside_open":
			var r: Dictionary = Shed.bikes[bike_id]["roadside"]
			r["open"] = bool(action.get("open", not r.get("open", false)))
			return ""
		"roadside_pump":
			var tyre := Shed.item_on(bike_id, str(action["side"]) + "_tyre")
			Shed.items[tyre].erase("deflate")
			_lay_out(bike_id, "pump")
			return "Pumped the %s tyre back up with the mini pump." % str(action["side"])
		"roadside_fix":
			var kind := str(action.get("fault", "puncture"))
			var at_shed := not Adventure.active()
			var text := _fix(peer, bike_id, kind, action)
			if text.begins_with("!"):
				return text.substr(1)   # it didn't take: nothing used up
			if not at_shed:
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


## The part that works loose on the bike: `want` if it's fitted and can, else the first fitted.
static func _rattle_slot(bike_id: int, want: String) -> String:
	if want != "" and RATTLE_SLOTS.has(want) and Shed.item_on(bike_id, want) != 0:
		return want
	var fitted := RATTLE_SLOTS.filter(func(s): return Shed.item_on(bike_id, s) != 0)
	if fitted.is_empty():
		return ""
	return str(fitted[Shed._rng.randi() % fitted.size()])


## Gives the bike the fault; returns what its rider's told (the symptom and the hint).
static func _break(bike_id: int, kind: String, action: Dictionary) -> String:
	var bike: Dictionary = Shed.bikes[bike_id]
	var faults := faults_of(bike_id).duplicate()
	var f := {"kind": kind}
	match kind:
		"chain_slack":
			var chain := Shed.item_on(bike_id, "chain")
			Shed.items[chain]["slack"] = maxf(float(Shed.items[chain].get("slack", Shed.CHAIN_SLACK_SET)), SLACK_GONE)
			f["slot"] = "chain"
		"chain_snap":
			faults["chain_snap"] = true
		"oil":
			var engine := Shed.item_on(bike_id, "engine")
			var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
			var fl: Dictionary = Shed.items[engine].get("fluid", {"litres": cap, "type": "semi_10w40", "age": 0.0})
			fl["litres"] = minf(float(fl.get("litres", cap)), cap * OIL_LEFT)
			Shed.items[engine]["fluid"] = fl
		"rattle":
			var slot := _rattle_slot(bike_id, str(action.get("slot", "")))
			faults["rattle"] = slot
			f["slot"] = slot
		"lever":
			var which := str(action.get("which", ""))
			if not which in ["clutch", "brake"]:
				which = "clutch" if Shed._rng.randf() < 0.5 else "brake"
			faults["lever"] = which
			f["detail"] = which
		"fuse":
			var which := str(action.get("which", ""))
			if not which in ["lights", "ignition"]:
				which = "lights" if Shed._rng.randf() < 0.6 else "ignition"
			faults["fuse"] = which
			f["detail"] = which
	bike["faults"] = faults
	return "%s %s" % [symptom(f), hint(f)]


## Puts something out on the cloth beside the bike (the toolbox's kit, a part off it).
static func _lay_out(bike_id: int, what: String) -> void:
	var r = Shed.bikes[bike_id].get("roadside", null)
	if not (r is Dictionary):
		return
	var out: Array = r.get("out", [])
	if not out.has(what):
		out.append(what)
	r["out"] = out


## Does the fix. Returns what the player's told; starting with "!" it didn't take.
static func _fix(peer: int, bike_id: int, kind: String, action: Dictionary) -> String:
	var faults := faults_of(bike_id).duplicate()
	var name := str(Shed.bikes[bike_id]["name"])
	var q := clampf(float(action.get("quality", 1.0)), 0.0, 1.0)
	var text := ""
	match kind:
		"chain_slack":
			var chain := Shed.item_on(bike_id, "chain")
			Shed.items[chain]["slack"] = Shed.CHAIN_SLACK_SET
			Shed._xp(peer, "chain_tension", 1.0, "item:%d" % chain)
			text = "Chain tightened back to %d mm of slack at the roadside." % roundi(Shed.CHAIN_SLACK_SET)
		"chain_snap":
			if q < 0.25:
				return "!The split link didn't seat. Try again: keep the pliers on the clip."
			var chain := Shed.item_on(bike_id, "chain")
			faults.erase("chain_snap")
			Shed.items[chain]["wear"] = 0.05
			Shed.items[chain]["slack"] = Shed.CHAIN_SLACK_SET
			Shed.items[chain]["lube"] = 1.0
			_lay_out(bike_id, "chain")
			text = "The spare chain's on and the split link clipped in (%d%%). Off you go." % roundi(q * 100.0)
		"oil":
			var engine := Shed.item_on(bike_id, "engine")
			var cap := PartsDB.fluid_capacity(str(Shed.items[engine]["part"]))
			var fl: Dictionary = Shed.items[engine].get("fluid", {"litres": 0.0, "type": "semi_10w40", "age": 0.0})
			fl["litres"] = minf(cap, float(fl.get("litres", 0.0)) + OIL_TOP_UP)
			Shed.items[engine]["fluid"] = fl
			text = "Topped the oil up from the toolbox's bottle: %.1f of %.1f litres, the light's off." % [float(fl["litres"]), cap]
		"rattle":
			var slot := str(faults.get("rattle", ""))
			faults.erase("rattle")
			text = "Bolted the %s up tight: no more rattle." % PartsDB.slot_name(slot).to_lower()
		"lever":
			if q < 0.25:
				return "!The pivot bolt wouldn't line up. Try again: hold it steady."
			var which := str(faults.get("lever", "clutch"))
			faults.erase("lever")
			_lay_out(bike_id, "handlebars")
			text = "A spare %s lever's on (%d%%)." % [which, roundi(q * 100.0)]
		"fuse":
			if q < 0.25:
				return "!Couldn't find the blown one. Try again: watch for the test lamp."
			var which := str(faults.get("fuse", "lights"))
			faults.erase("fuse")
			_lay_out(bike_id, "saddle")
			text = "Swapped the blown fuse: %s." % ("the headlight's back" if which == "lights" else "the dash lights up again and it'll start")
		"puncture":
			var side := str(action.get("side", "rear"))
			var tyre := Shed.item_on(bike_id, side + "_tyre")
			if q <= 0.0:
				return "!Couldn't find the leak. Sweep the soapy spray round the tread and watch for the bubbles."
			q = clampf(q + Shed._finish_bonus(peer), 0.0, 1.0)
			Shed.items[tyre]["plug"] = q
			_lay_out(bike_id, side + "_tyre")
			if q >= Puncture.PLUG_SEALS:
				Shed.items[tyre].erase("puncture")
				text = "Plugged the %s tyre at the roadside (%d%%): it holds. Pump it back up with the mini pump." % [side, roundi(q * 100.0)]
			else:
				Shed.items[tyre]["puncture"] = Puncture.SLOW * Puncture.PLUG_WEEP
				text = "The plug's in crooked (%d%%): it still weeps air, but slowly." % roundi(q * 100.0)
			Shed._xp(peer, "tyre_plug", q, "item:%d" % tyre)
	Shed.bikes[bike_id]["faults"] = faults
	if not Adventure.active():
		text = text.replace(" at the roadside", "").replace("the toolbox's ", "the shed's ").replace(" from the toolbox's bottle", "")
	return text if text != "" else "Fixed %s." % name


# ---------------------------------------------------------------------------- the end of a trip

## The adventure's over (or a save is loading): bikes left at the roadside come home to a bay,
## and nobody's pushing or towing any more. Faults stay on the bikes, for the shed to sort out.
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
