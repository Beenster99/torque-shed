class_name AdventureNeeds
extends RefCounted
## Hunger, thirst and tiredness out on an adventure ride, and what the crew does about them: a
## packed lunch and a flask packed in the shed before leaving (they ride in a tank bag, top box
## or panniers, with so many portions), eating and drinking from them or buying at a counter on
## the way, sitting down at a bench (beside your mates: two or more sat together is a picnic),
## and sleeping at an inn or campsite, which skips the night for the whole crew and saves the
## adventure so it can be carried on another day from the shed.
##
## The meters are host-run shared state, in Shed.adventure["needs"]: peer -> {food, drink, rest
## (each 1 full .. 0 empty), sat (the seat place's key, "" standing), sat_s (how far along the
## road the seat is), bed, bed_s (the same for a bed), eat (a count of mouthfuls, so the crew
## sees you eat), eat_what}. The host drains them (tick) at rates tuned so a 90 minute ride wants
## a stop or two to eat and drink, and a 3 hour one a night's sleep. AdventureNeedsView shows
## them, puts the effects on you (a tired rider steers slower and the edges of the screen go
## dark, with a slow blink now and then) and does the sitting, eating and buying.
##
## Shed.adventure_save: {} or the adventure put away by the last night's sleep (see make_save),
## kept in the shed's save so the host can carry it on later (adventure_resume, see Adventure).
##
## Actions (Shed.request): needs_pack {item, what: "lunch" or "flask"} in the shed; needs_eat
## {src: "lunch", "flask" or "buy" (with name, food, drink, rest, paid)}; needs_sit {key, s, on};
## needs_bed {key, s, on}; needs_sleep (the host, everyone abed); needs_debug {food, drink, rest}.

## Real minutes riding from full to empty: food, drink, and rest (the last only riding; on foot
## you tire at FOOT_REST of that).
const FOOD_MINUTES := 75.0
const DRINK_MINUTES := 60.0
const REST_MINUTES := 150.0
const FOOT_REST := 0.5
## Sat down, food and drink go at this share of the rate, and you get your breath back: rest
## comes back over SIT_REST_MINUTES, but only up to SIT_REST_CAP (a bench is no bed).
const SAT_DRAIN := 0.5
const SIT_REST_MINUTES := 40.0
const SIT_REST_CAP := 0.5
## Below LOW the meter warns; below EMPTY its effects come on.
const LOW := 0.25
const EMPTY := 0.08
## Starving or parched, you tire this much faster.
const EMPTY_TIRING := 1.5
## A packed lunch and a flask: portions when full, what packing one costs the business, and what
## a portion gives.
const LUNCH_PORTIONS := 4
const FLASK_CUPS := 4
const PACK_PRICE := {"lunch": 8, "flask": 3}
const PACK_NAMES := {"lunch": "packed lunch", "flask": "flask of tea"}
const PORTION := {"lunch": {"food": 0.4, "drink": 0.05, "rest": 0.0}, "flask": {"food": 0.0, "drink": 0.4, "rest": 0.04}}
const PORTION_NAMES := {"lunch": "a sandwich from the packed lunch", "flask": "a cup of tea from the flask"}
## The luggage a lunch and a flask can ride in.
const LUGGAGE: Array[String] = ["tank_bag", "top_box", "panniers"]
## Eating sat down goes further; sat with mates it's a picnic and goes further still.
const SAT_BONUS := 1.5
const PICNIC_BONUS := 2.0
const PICNIC_REST := 0.05
## Riders sat this close along the road (m) are sat together.
const PICNIC_REACH := 15.0
## The most one bought thing may give of each meter.
const MAX_BUY := 0.7
## What a counter sells when its node has no "menu" meta of its own: name, price (your own
## money), and what it gives.
const DEFAULT_MENU := [
	{"name": "Bacon roll", "price": 4, "food": 0.45, "drink": 0.0},
	{"name": "Mug of tea", "price": 2, "food": 0.0, "drink": 0.4, "rest": 0.04},
	{"name": "Sandwich and a can of pop", "price": 6, "food": 0.35, "drink": 0.35},
	{"name": "Bottle of water", "price": 1, "food": 0.0, "drink": 0.3},
]
## A night's sleep ends at this hour, and leaves you a bit peckish.
const MORNING := 7.0
const NIGHT_HUNGER := 0.1
## The groups the stops' interaction nodes are in (see AdventureNeedsView).
const SEAT_GROUP := "adv_seat"
const COUNTER_GROUP := "adv_counter"
const BED_GROUP := "adv_bed"

## Host: each rider's meters at full precision (the shared state keeps them rounded, so the crew
## isn't sent a change every frame): peer -> [food, drink, rest].
static var _live := {}
## Host: when the last picnic was announced (ticks), so sitting down again doesn't repeat it.
static var _picnic_at := -100000


static func defaults() -> Dictionary:
	return {"food": 1.0, "drink": 1.0, "rest": 1.0, "sat": "", "sat_s": 0.0, "bed": "", "bed_s": 0.0, "eat": 0, "eat_what": ""}


## Every rider's needs ({} with no adventure on).
static func all() -> Dictionary:
	if not Adventure.active():
		return {}
	if not (Shed.adventure.get("needs") is Dictionary):
		Shed.adventure["needs"] = {}
	return Shed.adventure["needs"]


## `peer`'s needs, or {} if they have none (not on the adventure).
static func of(peer: int) -> Dictionary:
	var n = all().get(peer, {})
	return n if n is Dictionary else {}


## One meter of `peer`'s, 1 with none.
static func level(peer: int, key: String) -> float:
	return float(of(peer).get(key, 1.0))


## Whether `peer` is sat down, or in bed.
static func sat(peer: int) -> bool:
	return str(of(peer).get("sat", "")) != ""


static func abed(peer: int) -> bool:
	return str(of(peer).get("bed", "")) != ""


## A rider joined the adventure: full up, or as they were when it was put away (carrying one on).
static func joined(peer: int) -> void:
	var n := defaults()
	var saved = Shed.adventure.get("needs_saved", {})
	var who := str(Shed.crew.get(peer, {}).get("name", ""))
	if saved is Dictionary and saved.get(who) is Dictionary:
		n["food"] = clampf(float(saved[who].get("food", 1.0)), 0.0, 1.0)
		n["drink"] = clampf(float(saved[who].get("drink", 1.0)), 0.0, 1.0)
		n["rest"] = clampf(float(saved[who].get("rest", 1.0)), 0.0, 1.0)
	all()[peer] = n
	_live.erase(peer)


## Sets one of `peer`'s meters (state and the host's live copy).
static func _set_level(peer: int, key: String, v: float) -> void:
	var n := of(peer)
	if n.is_empty():
		return
	n[key] = clampf(v, 0.0, 1.0)
	if _live.has(peer):
		_live[peer][["food", "drink", "rest"].find(key)] = n[key]


# ---------------------------------------------------------------------------- the host's clock

## Real seconds' worth of hunger, thirst and tiredness for everyone on the adventure (the host,
## every frame; Shed calls it). Riding uses you up at the full rates, on foot you tire slower, sat
## down you get some of your breath back, and in bed nothing goes.
static func tick(delta: float) -> void:
	var needs := all()
	if needs.is_empty():
		return
	var gone := []
	for peer in needs:
		if not Shed.crew.has(peer):
			gone.append(peer)
			continue
		var n: Dictionary = needs[peer]
		if not _live.has(peer):
			_live[peer] = [float(n.get("food", 1.0)), float(n.get("drink", 1.0)), float(n.get("rest", 1.0))]
		var v: Array = _live[peer]
		if str(n.get("bed", "")) == "":
			var sitting := str(n.get("sat", "")) != ""
			var riding := Shed.riding(int(peer)) != 0
			var eat_rate := (SAT_DRAIN if sitting else 1.0) * delta / 60.0
			v[0] = maxf(0.0, v[0] - eat_rate / FOOD_MINUTES)
			v[1] = maxf(0.0, v[1] - eat_rate / DRINK_MINUTES)
			var tiring := EMPTY_TIRING if v[0] < EMPTY or v[1] < EMPTY else 1.0
			if sitting:
				if v[2] < SIT_REST_CAP:
					v[2] = minf(SIT_REST_CAP, v[2] + delta / 60.0 / SIT_REST_MINUTES)
			else:
				v[2] = maxf(0.0, v[2] - (1.0 if riding else FOOT_REST) * tiring * delta / 60.0 / REST_MINUTES)
		# The crew's copy only changes when it's moved on a bit.
		var changed := false
		for k in 3:
			var key: String = ["food", "drink", "rest"][k]
			if absf(float(n.get(key, 1.0)) - v[k]) >= 0.002:
				n[key] = snappedf(v[k], 0.001)
				changed = true
		if changed:
			Shed._mark_dirty()
	for peer in gone:
		needs.erase(peer)
		_live.erase(peer)


# ---------------------------------------------------------------------------- lunch and flask

## What's packed in a piece of luggage: {"lunch": portions, "flask": cups}.
static func packed(item_id: int) -> Dictionary:
	var f = Shed.items.get(item_id, {}).get("food", {})
	return f if f is Dictionary else {}


static func full_of(what: String) -> int:
	return LUNCH_PORTIONS if what == "lunch" else FLASK_CUPS


## What packing `item_id` would do next: "lunch" or "flask" (whichever isn't full, the lunch
## first), or "" when both are full or it can't carry them.
static func next_pack(item_id: int) -> String:
	if not LUGGAGE.has(str(Shed.items.get(item_id, {}).get("kind", ""))):
		return ""
	var p := packed(item_id)
	for what in ["lunch", "flask"]:
		if int(p.get(what, 0)) < full_of(what):
			return what
	return ""


## "Packed lunch (3 of 4 left), flask of tea (4 cups)" for a piece of luggage, "" with nothing in it.
static func packed_text(item_id: int) -> String:
	var p := packed(item_id)
	var bits := []
	if int(p.get("lunch", 0)) > 0:
		bits.append("packed lunch (%d of %d left)" % [int(p["lunch"]), LUNCH_PORTIONS])
	if int(p.get("flask", 0)) > 0:
		bits.append("flask of tea (%d %s)" % [int(p["flask"]), "cup" if int(p["flask"]) == 1 else "cups"])
	return "" if bits.is_empty() else ("Packed: " + ", ".join(bits))


## The piece of luggage on `bike_id` with some `what` left, or 0.
static func luggage_with(bike_id: int, what: String) -> int:
	if not Shed.bikes.has(bike_id):
		return 0
	for slot in LUGGAGE:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and int(packed(id).get(what, 0)) > 0:
			return id
	return 0


## The bike `peer` came on: the one they're riding, else the one they took on the adventure.
static func bike_of(peer: int) -> int:
	var b := Shed.riding(peer)
	if b != 0:
		return b
	return int(Shed.adventure.get("riders", {}).get(peer, 0))


## Portions of `what` left on `peer`'s bike, all its luggage counted.
static func left(peer: int, what: String) -> int:
	var b := bike_of(peer)
	var n := 0
	if Shed.bikes.has(b):
		for slot in LUGGAGE:
			var id := Shed.item_on(b, slot)
			if id != 0:
				n += int(packed(id).get(what, 0))
	return n


# ---------------------------------------------------------------------------- sitting together

## The riders sat within PICNIC_REACH of `peer` (them included), by peer id.
static func sat_with(peer: int) -> Array:
	var me := of(peer)
	if str(me.get("sat", "")) == "":
		return []
	var out := []
	var needs := all()
	for p in needs:
		var n: Dictionary = needs[p]
		if str(n.get("sat", "")) != "" and absf(float(n.get("sat_s", 0.0)) - float(me.get("sat_s", 0.0))) <= PICNIC_REACH:
			out.append(int(p))
	out.sort()
	return out


## How far a mouthful goes for `peer` now: 1 standing, SAT_BONUS sat, PICNIC_BONUS sat with mates.
static func bonus(peer: int) -> float:
	var together := sat_with(peer).size()
	if together >= 2:
		return PICNIC_BONUS
	return SAT_BONUS if together == 1 else 1.0


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


# ---------------------------------------------------------------------------- the menu

## A counter's menu (its node's "menu" meta, else DEFAULT_MENU), each entry made whole: {name,
## price, food, drink, rest}. An entry may give "kind" ("food", "drink" or "both") instead of
## its amounts.
static func menu_of(node: Node) -> Array:
	var raw = node.get_meta("menu") if node != null and node.has_meta("menu") else null
	if not (raw is Array) or (raw as Array).is_empty():
		raw = DEFAULT_MENU
	var out := []
	for e in raw:
		if not (e is Dictionary):
			continue
		var kind := str(e.get("kind", ""))
		var food := float(e.get("food", 0.45 if kind in ["food", "both"] else 0.0))
		var drink := float(e.get("drink", 0.4 if kind in ["drink", "both"] else 0.0))
		out.append({"name": str(e.get("name", "Something to eat")), "price": maxi(0, int(e.get("price", 3))),
			"food": clampf(food, 0.0, MAX_BUY), "drink": clampf(drink, 0.0, MAX_BUY), "rest": clampf(float(e.get("rest", 0.0)), 0.0, 0.2)})
	return out


# ---------------------------------------------------------------------------- saving a night's stop

## The adventure as it stands, put away to carry on another day: the road (everything in
## Shed.adventure but who's on it now), where each rider is by name, their meters, the time.
static func make_save() -> Dictionary:
	var adv := {}
	for k in Shed.adventure:
		if not str(k) in ["id", "riders", "arrived", "arrived_name", "needs", "resume", "needs_saved"]:
			adv[k] = Shed.adventure[k]
	var at := {}
	var meters := {}
	var needs := all()
	for p in needs:
		var who := str(Shed.crew.get(p, {}).get("name", ""))
		if who == "":
			continue
		var n: Dictionary = needs[p]
		at[who] = float(n.get("bed_s", n.get("sat_s", 0.0)))
		meters[who] = {"food": float(n.get("food", 1.0)), "drink": float(n.get("drink", 1.0)), "rest": float(n.get("rest", 1.0))}
	return {"adventure": adv.duplicate(true), "at": at, "needs": meters, "hours": MORNING,
		"nights": int(Shed.adventure.get("nights", 0)), "by": str(Shed.adventure.get("by", ""))}


## A saved adventure as received or loaded: kept if it has a road, else none.
static func sanitize_save(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("adventure") is Dictionary) or not (v["adventure"] as Dictionary).has("seed"):
		return {}
	var out: Dictionary = v.duplicate(true)
	if not (out.get("at") is Dictionary):
		out["at"] = {}
	if not (out.get("needs") is Dictionary):
		out["needs"] = {}
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


# ---------------------------------------------------------------------------- actions

static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if a == "needs_pack":
		var box := int(action.get("item", 0))
		if not Shed.items.has(box) or not LUGGAGE.has(str(Shed.items[box]["kind"])):
			return "Aim at a tank bag, top box or panniers."
		if Shed.items[box].get("boxed", false):
			return "Unpack it first."
		var what := str(action.get("what", next_pack(box)))
		if not PACK_PRICE.has(what):
			return "It's packed already: lunch and a full flask."
		if int(packed(box).get(what, 0)) >= full_of(what):
			return "That's packed already."
		if int(PACK_PRICE[what]) > Shed.garage_money:
			return "The business can't afford it."
		return ""
	if not Adventure.active():
		return "There's no adventure on."
	if a != "needs_sleep" and of(peer).is_empty():
		return "You're not on the adventure."
	match a:
		"needs_eat":
			if abed(peer):
				return "Not in bed."
			var src := str(action.get("src", ""))
			match src:
				"lunch", "flask":
					if luggage_with(bike_of(peer), src) == 0:
						return "There's no %s left on your bike." % ("packed lunch" if src == "lunch" else "tea in the flask")
				"buy":
					for key in ["food", "drink", "rest"]:
						var v = action.get(key, 0.0)
						if not (v is float or v is int) or float(v) < 0.0 or float(v) > MAX_BUY:
							return "That's not on the menu."
				_:
					return "Eat what?"
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
		"needs_debug":
			pass
		_:
			return "Unknown action."
	return ""


## Applies a checked action; returns what to tell the player (or, starting with "*", the crew).
static func apply(peer: int, action: Dictionary) -> String:
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match str(action.get("a", "")):
		"needs_pack":
			var box := int(action["item"])
			var what := str(action.get("what", next_pack(box)))
			var p := packed(box).duplicate()
			Shed.charge_garage(int(PACK_PRICE[what]), "Adventure: %s" % PACK_NAMES[what])
			p[what] = full_of(what)
			Shed.items[box]["food"] = p
			return "Packed a %s in the %s (%d %s)" % [PACK_NAMES[what], Shed.item_title(box), full_of(what), "portions" if what == "lunch" else "cups"]
		"needs_eat":
			var src := str(action["src"])
			var give := {}
			var said := ""
			if src == "buy":
				give = {"food": float(action.get("food", 0.0)), "drink": float(action.get("drink", 0.0)), "rest": float(action.get("rest", 0.0))}
				said = str(action.get("name", "something")).left(40)
			else:
				var box := luggage_with(bike_of(peer), src)
				var p := packed(box).duplicate()
				p[src] = int(p[src]) - 1
				Shed.items[box]["food"] = p
				give = PORTION[src]
				said = "%s (%d left)" % [PORTION_NAMES[src], left(peer, src)]
			var b := bonus(peer)
			var n := of(peer)
			for key in ["food", "drink", "rest"]:
				if float(give.get(key, 0.0)) > 0.0:
					_set_level(peer, key, float(n[key]) + float(give[key]) * b)
			if b >= PICNIC_BONUS:
				_set_level(peer, "rest", float(n["rest"]) + PICNIC_REST)
			n["eat"] = int(n.get("eat", 0)) + 1
			n["eat_what"] = "flask" if src == "flask" or (src == "buy" and float(give.get("drink", 0.0)) > float(give.get("food", 0.0))) else "lunch"
			var how := "" if b <= 1.0 else (", sat down" if b < PICNIC_BONUS else ", picnicking with your mates")
			return "You have %s%s." % [said.to_lower() if src != "buy" else said, how]
		"needs_sit":
			var n := of(peer)
			if not bool(action.get("on", true)):
				n["sat"] = ""
				return ""
			n["sat"] = str(action["key"]).left(80)
			n["sat_s"] = float(action.get("s", 0.0))
			n["bed"] = ""
			var together := sat_with(peer)
			if together.size() >= 2 and Time.get_ticks_msec() - _picnic_at > 60000:
				_picnic_at = Time.get_ticks_msec()
				var names := together.map(func(p): return str(Shed.crew.get(p, {}).get("name", "Someone")))
				return "*Picnic: %s sat down together. Food goes further shared." % _and_list(names)
			return ""
		"needs_bed":
			var n := of(peer)
			if not bool(action.get("on", true)):
				n["bed"] = ""
				return ""
			n["bed"] = str(action["key"]).left(80)
			n["bed_s"] = float(action.get("s", 0.0))
			n["sat"] = ""
			var c := bed_count()
			if c[0] >= c[1]:
				return "*Everyone's in bed. The host can call it a night."
			return "*%s has gone to bed (%d of %d)." % [who, c[0], c[1]]
		"needs_sleep":
			var needs := all()
			for p in needs:
				var n: Dictionary = needs[p]
				n["rest"] = 1.0
				n["food"] = maxf(0.1, float(n.get("food", 1.0)) - NIGHT_HUNGER)
				n["drink"] = maxf(0.1, float(n.get("drink", 1.0)) - NIGHT_HUNGER)
				_live.erase(p)
			Shed.adventure["nights"] = int(Shed.adventure.get("nights", 0)) + 1
			if Daylight.current:
				Daylight.current.set_time(MORNING)
			Shed.adventure_save = make_save()
			return "*Everyone sleeps till morning. The adventure's saved: carry on now, or another day from the shed (the host's Esc menu)."
		"needs_debug":
			for key in ["food", "drink", "rest"]:
				if action.get(key) is float or action.get(key) is int:
					_set_level(peer, key, float(action[key]))
	return ""


static func _and_list(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])
