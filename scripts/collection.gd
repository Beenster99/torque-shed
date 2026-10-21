class_name Collection
extends RefCounted
## Every player's own bike collection, kept at their house (Simon: "We need the concept of a bike
## garage for each player, you are allowed three slots at the start of the game and as you level
## up a maximum of 20 bikes. these bikes must be bought with personal money").
##
## A collection's bikes belong to the player, not the shed. Each player has a house (HomePlots:
## one plot each, its style and place from their name, kept with the shed) with the collection on
## show in a ring in its courtyard, an information stand in front of each bike (HomesView). How
## many bikes a collection holds goes with the player's level (slots_for_level).
##
## Getting bikes, and what can be done with them (all of it asked for with Shed.request, checked
## and done by the host, see check() and apply()):
##   home_buy       buy one of the shed's finished bikes from the business with your own money, at
##                  its asking price (what it's listed at in the showroom, else the sales PC's
##                  recommended price): it's delivered to your house, on show.
##   home_take      at your house, take one out to ride: it's left in front of the garages, ready to
##                  ride away, and its place in the ring stands empty while it's out. It's still
##                  yours: nobody else can ride it or wheel it off.
##   home_return    put it back: done for you as soon as you get off it (or let go of it) in your
##                  own courtyard.
##   home_sell      sell one back to the business for SELL_BACK of what it's worth, paid from the
##                  garage's account into your own money; it goes in the yard as the shed's stock,
##                  for the business to sell on at a profit.
##   home_offer     at a friend's bike, offer them your own money for it. The money's held until
##                  they answer (home_answer: accept or decline) or you take the offer back
##                  (home_withdraw); on a yes the bike moves into your collection and the money to
##                  them.
## Money from your own cash is taken on your own machine first (as BikeCopy's orders are), and
## whatever the host doesn't take goes back. Money owed to a player who has left (an offer turned
## down while they were away) is paid out when they next come back to the shed.
##
## The state is Shed.homes (see empty()), saved with the shed and sent to the crew whenever it
## changes (only what changed, see Shed.homes_touched). A bike at home is packed up (pack(): the
## bike and every part on it, exactly as it was), out of Shed.bikes and Shed.items, so the shed's
## own systems (sales, insurance, the staff, the TVs) never see it; taken out it's unpacked again
## into an ordinary bike marked with its owner ("owner", "cid").

## Slots: START_SLOTS at the start, one more every LEVELS_PER_SLOT levels, up to MAX_SLOTS
## (3 at level 1, 4 at level 3, 5 at level 5 ... 20 at level 35).
const START_SLOTS := 3
const LEVELS_PER_SLOT := 2
const MAX_SLOTS := 20
## Selling a bike back to the business fetches this share of what it's worth (so the business
## makes its money selling it on).
const SELL_BACK := 0.7
## Offers waiting for an answer, at most, in all.
const MAX_OFFERS := 30
const MIN_OFFER := 1


# ---------------------------------------------------------------------------- state

## A new shed's: nobody's house yet. players: name -> {plot, style}; bikes: collection id ->
## {id, owner, spot (its place in the ring), out (the shed bike while it's out, else 0), name,
## value (what it's worth, worked out as it came home), paid (what its owner paid for it), pack};
## offers: id -> {id, bike, from, to, amount, level (the buyer's, for their slots)}; owed: name ->
## pounds to pay them when they're next here; next: the next id.
static func empty() -> Dictionary:
	return {"players": {}, "bikes": {}, "offers": {}, "owed": {}, "next": 1}


## A saved or sent collection made safe to use (older saves have none).
static func sanitize(h) -> Dictionary:
	var out := empty()
	if not (h is Dictionary):
		return out
	for key in ["players", "bikes", "offers", "owed"]:
		if h.get(key) is Dictionary:
			out[key] = h[key]
	out["next"] = maxi(1, int(h.get("next", 1)))
	for cid in out["bikes"].keys():
		var e = out["bikes"][cid]
		if not (e is Dictionary) or (int(e.get("out", 0)) == 0 and not (e.get("pack") is Dictionary)):
			out["bikes"].erase(cid)
	return out


static func _st() -> Dictionary:
	if not (Shed.homes is Dictionary) or not Shed.homes.has("bikes"):
		Shed.homes = empty()
	return Shed.homes


static func players() -> Dictionary:
	return _st()["players"]


static func bikes() -> Dictionary:
	return _st()["bikes"]


static func offers() -> Dictionary:
	return _st()["offers"]


static func money(v: int) -> String:
	return TvChannels.money_text(v)


static func _next() -> int:
	var n := int(_st()["next"])
	_st()["next"] = n + 1
	return n


# ---------------------------------------------------------------------------- slots and owners

## How many bikes a collection holds at `level`.
static func slots_for_level(level: int) -> int:
	return clampi(START_SLOTS + (maxi(level, 1) - 1) / LEVELS_PER_SLOT, START_SLOTS, MAX_SLOTS)


## The level a collection gets its `slots`th slot.
static func level_for_slots(slots: int) -> int:
	if slots <= START_SLOTS:
		return 1
	return 1 + (mini(slots, MAX_SLOTS) - START_SLOTS) * LEVELS_PER_SLOT


## A player's level, as this machine knows it (their reported summary for the others).
static func level_of(peer: int) -> int:
	if peer == Shed.me():
		return Progress.level()
	return int(Progress.summary(peer).get("level", 1))


static func slots_of(peer: int) -> int:
	return slots_for_level(level_of(peer))


static func name_of(peer: int) -> String:
	return str(Shed.crew.get(peer, {}).get("name", "")).strip_edges()


## The peer of the player called `player_name` in the shed now, or 0.
static func peer_of(player_name: String) -> int:
	for p in Shed.crew:
		if str(Shed.crew[p].get("name", "")).strip_edges() == player_name:
			return int(p)
	return 0


## The plot `player_name`'s house is on, or -1.
static func plot_of(player_name: String) -> int:
	return int(players().get(player_name, {}).get("plot", -1))


static func style_of(player_name: String) -> String:
	return str(players().get(player_name, {}).get("style", HomePlots.style_for(player_name)))


## Who lives on plot `plot`, or "".
static func owner_of_plot(plot: int) -> String:
	for n in players():
		if int(players()[n].get("plot", -1)) == plot:
			return str(n)
	return ""


## `player_name`'s bikes (collection ids), in ring order.
static func bikes_of(player_name: String) -> Array:
	var out := []
	for cid in bikes():
		if str(bikes()[cid]["owner"]) == player_name:
			out.append(int(cid))
	out.sort_custom(func(a, b): return int(bikes()[a].get("spot", 0)) < int(bikes()[b].get("spot", 0)))
	return out


static func count_of(player_name: String) -> int:
	return bikes_of(player_name).size()


static func entry(cid: int) -> Dictionary:
	return bikes().get(cid, {})


## The bike in `player_name`'s ring at `spot`, or 0.
static func at_spot(player_name: String, spot: int) -> int:
	for cid in bikes():
		if str(bikes()[cid]["owner"]) == player_name and int(bikes()[cid].get("spot", -1)) == spot:
			return int(cid)
	return 0


static func _free_spot(player_name: String) -> int:
	for s in HomePlots.RING_SPOTS:
		if at_spot(player_name, s) == 0:
			return s
	return -1


## The collection a shed bike out on the road belongs to, or 0 for one of the shed's own.
static func cid_of_bike(bike_id: int) -> int:
	return int(Shed.bikes.get(bike_id, {}).get("cid", 0))


## Whose a shed bike is: "" for the shed's own.
static func owner_of_bike(bike_id: int) -> String:
	return str(Shed.bikes.get(bike_id, {}).get("owner", ""))


static func is_private(bike_id: int) -> bool:
	return owner_of_bike(bike_id) != ""


## Host: gives `player_name` a house if they haven't one: the plot their name picks (see
## HomePlots.preferred_plot), or the next free one round from it. When every plot is taken, the
## house of someone who isn't here and owns no bikes is let go to make room. -1 when there's none.
static func ensure_home(player_name: String) -> int:
	player_name = player_name.strip_edges()
	if player_name == "":
		return -1
	if players().has(player_name):
		return plot_of(player_name)
	var want := HomePlots.preferred_plot(player_name)
	var n := HomePlots.PLOTS.size()
	for k in n:
		var plot := (want + k) % n
		if owner_of_plot(plot) == "":
			players()[player_name] = {"plot": plot, "style": HomePlots.style_for(player_name)}
			return plot
	for k in n:
		var plot := (want + k) % n
		var other := owner_of_plot(plot)
		if peer_of(other) == 0 and count_of(other) == 0:
			players().erase(other)
			players()[player_name] = {"plot": plot, "style": HomePlots.style_for(player_name)}
			return plot
	return -1


# ---------------------------------------------------------------------------- a bike packed away

## A shed bike packed up for its owner's house: the bike and every part on it, as they are now.
static func pack(bike_id: int) -> Dictionary:
	var bike: Dictionary = (Shed.bikes[bike_id] as Dictionary).duplicate(true)
	for key in ["rider", "pusher", "push", "tow", "roadside", "bay", "xf", "stand", "blueprint", "owner", "cid"]:
		bike.erase(key)
	var its := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			its[id] = (Shed.items[id] as Dictionary).duplicate(true)
	return {"bike": bike, "items": its}


## Host: a packed bike unpacked into the shed at `xf` with new ids for it and its parts. Returns
## the bike's id.
static func unpack(p: Dictionary, xf: Transform3D) -> int:
	var map := {}
	for old in p["items"]:
		map[int(old)] = Shed._next_id
		Shed._next_id += 1
	var id := Shed._next_id
	Shed._next_id += 1
	var bike: Dictionary = (p["bike"] as Dictionary).duplicate(true)
	bike["id"] = id
	for slot in bike["slots"]:
		bike["slots"][slot] = int(map.get(int(bike["slots"][slot]), 0))
	bike["rider"] = 0
	bike["pusher"] = 0
	bike["bay"] = -1
	bike["xf"] = xf
	bike["stand"] = ""
	Shed.bikes[id] = bike
	for old in p["items"]:
		var it: Dictionary = (p["items"][old] as Dictionary).duplicate(true)
		it["id"] = int(map[int(old)])
		if str(it.get("at", "")) == "bike":
			it["ref"] = id
		elif str(it.get("at", "")) == "engine":
			it["ref"] = int(map.get(int(it["ref"]), 0))
		if it.get("slots") is Dictionary:
			for slot in it["slots"]:
				it["slots"][slot] = int(map.get(int(it["slots"][slot]), 0))
		Shed.items[it["id"]] = it
	bike["stand"] = Shed._rest_stand(id)
	return id


## The part a packed bike has in `slot` (its engine's, for the engine's own slots), or {}.
static func _pack_item(p: Dictionary, slot: String) -> Dictionary:
	var bike: Dictionary = p.get("bike", {})
	var its: Dictionary = p.get("items", {})
	if PartsDB.is_engine_slot(slot):
		var block: Dictionary = its.get(int(bike.get("slots", {}).get("engine", 0)), {})
		return its.get(int(block.get("slots", {}).get(slot, 0)), {})
	return its.get(int(bike.get("slots", {}).get(slot, 0)), {})


## A packed bike as it's drawn and its numbers worked out: {parts, cond, fitted, tune, paint,
## geo, name}, as Shed.build_of has them for a bike in the shed.
static func look(p: Dictionary) -> Dictionary:
	var bike: Dictionary = p.get("bike", {})
	var parts: Dictionary = (bike.get("original", PartsDB.DEFAULT_BUILD) as Dictionary).duplicate()
	var cond: Dictionary = (bike.get("original_cond", {}) as Dictionary).duplicate()
	var fitted := {}
	for slot in PartsDB.SLOTS:
		var it := _pack_item(p, slot)
		fitted[slot] = not it.is_empty()
		if not it.is_empty():
			parts[slot] = str(it["part"])
			cond[slot] = Shed.condition_of(it)
		elif PartsDB.is_optional(slot):
			parts[slot] = "none"
	var tune := {}
	var own: Dictionary = bike.get("tune", {}) if bike.get("tune") is Dictionary else {}
	for key in Shed.TUNE_HOME:
		var home: Array = Shed.TUNE_HOME[key]
		if home[0] == "bike":
			if own.has(home[1]):
				tune[key] = float(own[home[1]])
		elif key != "chain":
			var it := _pack_item(p, str(home[0]))
			if it.get("tune", {}).has(home[1]):
				tune[key] = float(it["tune"][home[1]])
	if float(bike.get("tune_reach", 0.0)) > 0.0:
		tune["reach"] = float(bike["tune_reach"])
	var geo = bike.get("geo", {})
	return {"parts": parts, "cond": cond, "fitted": fitted, "tune": tune, "paint": bike.get("paint", Color.WHITE),
		"geo": geo if geo is Dictionary else {}, "name": str(bike.get("name", "Bike"))}


## The build of collection bike `cid` (at home or out).
static func build_of(cid: int) -> BikeBuild:
	var e := entry(cid)
	if e.is_empty():
		return BikeBuild.new()
	if int(e.get("out", 0)) != 0 and Shed.bikes.has(int(e["out"])):
		return Shed.build_of(int(e["out"]))
	var l := look(e.get("pack", {}))
	return BikeBuild.new(l["parts"], l["cond"], l["tune"])


## What a shed bike is worth (the sales PC's fair price for it as it is).
static func worth(bike_id: int) -> int:
	return int(Sales.appraise(bike_id).get("fair", 0))


## What the business asks a player for one of its bikes: its asking price in the showroom when
## it's listed there, else the sales PC's recommended price.
static func buy_price(bike_id: int) -> int:
	if not Shed.bikes.has(bike_id):
		return 0
	var ask := int(Sales.listings().get(bike_id, {}).get("ask", 0))
	if ask > 0:
		return ask
	return maxi(1, int(Sales.appraise(bike_id).get("recommended", 0)))


## What the business pays for collection bike `cid` (SELL_BACK of what it's worth).
static func sell_price(cid: int) -> int:
	return maxi(1, roundi(float(entry(cid).get("value", 0)) * SELL_BACK))


## The bike at plot `plot`'s ring `spot`: its collection id, or 0.
static func on_show(plot: int, spot: int) -> int:
	var who := owner_of_plot(plot)
	if who == "":
		return 0
	var cid := at_spot(who, spot)
	return cid if cid != 0 and int(entry(cid).get("out", 0)) == 0 else 0


# ---------------------------------------------------------------------------- the stand's card

## Everything a bike's information stand tells you: {name, owner, style, lines [[label, value]],
## highlights [String]}.
static func stats(cid: int) -> Dictionary:
	var e := entry(cid)
	if e.is_empty():
		return {}
	var b := build_of(cid)
	var parts: Dictionary = b.parts
	var l := look(e.get("pack", {})) if e.get("pack") is Dictionary else {"parts": parts}
	var peak := b.peak_power()
	var sixty := b.zero_to(96.56)
	var imperial := Units.imperial()
	var lines := [
		["Power", "%d bhp at %d rpm" % [roundi(b.hp()), roundi(float(peak.get("rpm", 0.0)))]],
		["Torque", "%d Nm at %d rpm" % [roundi(b.peak_torque), roundi(b.peak_torque_rpm)]],
		["Top speed", Units.kmh(b.top_speed_estimate() * 3.6)],
		["0-60 mph" if imperial else "0-100 km/h", ("%.1f s" % (sixty if imperial else b.zero_to_100())) if sixty > 0.0 else "--"],
		["Weight", Units.mass(b.bike_mass)],
		["Economy", Units.economy(b.cruise_economy())],
		["Engine", Sales.model_text(parts)],
		["Condition", "%d%%" % roundi(b.overall_health() * 100.0)],
		["Value", money(int(e.get("value", 0)))],
	]
	if int(e.get("paid", 0)) > 0:
		lines.append(["Paid", money(int(e["paid"]))])
	return {"name": str(e.get("name", l.get("name", "Bike"))), "owner": str(e["owner"]),
		"style": PartsDB.style_text(parts), "lines": lines, "highlights": highlights(parts)}


## The parts worth pointing out on a build: the engine and frame, and anything top-end or light.
static func highlights(parts: Dictionary) -> Array:
	var out := []
	for slot in ["engine", "frame"]:
		if str(parts.get(slot, "none")) != "none":
			out.append("%s: %s" % [PartsDB.slot_name(slot), PartsDB.part_name(str(parts[slot]))])
	for slot in PartsDB.SLOTS:
		var part := str(parts.get(slot, "none"))
		if slot in ["engine", "frame"] or part == "none" or PartsDB.get_part(part).is_empty() or PartsDB.is_fluid(part):
			continue
		var ids: Array = PartsDB.by_kind.get(PartsDB.kind_of(part), [])
		if PartsDB.is_lightweight(part) or (ids.size() > 2 and ids.find(part) >= int(ids.size() * 0.75)):
			out.append("%s: %s" % [PartsDB.slot_name(slot), PartsDB.part_name(part)])
		if out.size() >= 7:
			break
	return out


## The stand's card as text (tests, and the look-at panel's summary).
static func stats_text(cid: int) -> String:
	var s := stats(cid)
	if s.is_empty():
		return ""
	var out := ["%s (%s's)" % [s["name"], s["owner"]], s["style"]]
	for l in s["lines"]:
		out.append("%s: %s" % [l[0], l[1]])
	for h in s["highlights"]:
		out.append(h)
	return "\n".join(out)


# ---------------------------------------------------------------------------- from this machine

## Buys shed bike `bike_id` from the business with this player's own money. Returns why not, or "".
static func buy(bike_id: int) -> String:
	var price := buy_price(bike_id)
	var action := {"a": "home_buy", "bike": bike_id, "paid": price}
	var why := check(Shed.me(), action)
	if why != "":
		return why
	if not Progress.spend(price, "Bought %s" % str(Shed.bikes[bike_id]["name"]).left(40)):
		return "That's %s and you have %s." % [money(price), money(Progress.money())]
	Shed.request(action)
	return ""


## Offers `amount` of this player's own money for collection bike `cid`. Returns why not, or "".
static func make_offer(cid: int, amount: int) -> String:
	var action := {"a": "home_offer", "bike": cid, "amount": amount, "paid": amount}
	var why := check(Shed.me(), action)
	if why != "":
		return why
	if not Progress.spend(amount, "Offer for %s" % str(entry(cid).get("name", "a bike")).left(40)):
		return "You only have %s." % money(Progress.money())
	Shed.request(action)
	return ""


## The offer `player_name` has made on `cid` and not had answered, or {}.
static func offer_from(player_name: String, cid: int) -> Dictionary:
	for id in offers():
		var o: Dictionary = offers()[id]
		if int(o["bike"]) == cid and str(o["from"]) == player_name:
			return o
	return {}


## Offers waiting for `player_name` to answer, oldest first.
static func offers_to(player_name: String) -> Array:
	var out := []
	for id in offers():
		if str(offers()[id]["to"]) == player_name:
			out.append(offers()[id])
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out


# ---------------------------------------------------------------------------- the host

## Why `peer` can't do a "home_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var who := name_of(peer)
	if who == "":
		return "You're not in the shed."
	match a:
		"home_buy":
			var b := int(action.get("bike", 0))
			if not Shed.bikes.has(b):
				return "That bike has gone."
			var bike: Dictionary = Shed.bikes[b]
			if is_private(b):
				return "That's %s's own bike, not the shed's." % owner_of_bike(b) if owner_of_bike(b) != who else "It's yours already."
			if Sales.is_customer_bike(b):
				return "That's a customer's bike: it isn't the shed's to sell."
			if int(bike.get("rider", 0)) != 0:
				return "Someone is riding it."
			if int(bike.get("pusher", 0)) != 0:
				return "Someone is wheeling it about."
			if not Shed.is_complete(b):
				return "Only a finished bike can be bought: every part fitted and bolted up."
			if Shed.on_dyno(b) and Shed.strapped():
				return "Unstrap it from the dyno first."
			if Shed.lift_raised(b):
				return "It's up on the lift. Lower it first."
			if not Recovery.job_of(b).is_empty():
				return "It's a recovery job: it goes back to the yard on the trailer first."
			for w in Staff.workers().values():
				if int((w.get("job", {}) as Dictionary).get("bike", 0)) == b:
					return "%s is working on it." % Staff.first_name(w)
			if ShedPump.pouring() == b:
				return "It's being filled up at the pump."
			if plot_of(who) < 0 and players().size() >= HomePlots.PLOTS.size():
				return "There's no house free for you."
			if count_of(who) >= slots_of(peer):
				return "Your collection is full (%d of %d). %s" % [count_of(who), slots_of(peer), _next_slot_text(peer)]
			var price := buy_price(b)
			if int(action.get("paid", 0)) < price:
				return "That's %s now: you paid %s." % [money(price), money(int(action.get("paid", 0)))]
		"home_take":
			var cid := int(action.get("bike", 0))
			var e := entry(cid)
			if e.is_empty():
				return "That bike has gone."
			if str(e["owner"]) != who:
				return "That's %s's bike: only they can take it out." % str(e["owner"])
			if int(e.get("out", 0)) != 0:
				return "It's out already."
			if Shed.riding(peer) != 0:
				return "Park the bike you're on first."
			if Shed.held_by(peer) != 0:
				return "Put the part down first."
		"home_return":
			var b := int(action.get("bike", 0))
			if not Shed.bikes.has(b) or cid_of_bike(b) == 0:
				return "That isn't one of the collection's bikes."
			if owner_of_bike(b) != who:
				return "That's %s's bike." % owner_of_bike(b)
			if int(Shed.bikes[b].get("rider", 0)) != 0 or int(Shed.bikes[b].get("pusher", 0)) != 0:
				return "Get off it first."
			var plot := plot_of(who)
			if not HomePlots.in_courtyard(plot, (Shed.bikes[b]["xf"] as Transform3D).origin):
				return "Bring it back to your courtyard first."
		"home_sell":
			var cid := int(action.get("bike", 0))
			var e := entry(cid)
			if e.is_empty():
				return "That bike has gone."
			if str(e["owner"]) != who:
				return "That's %s's bike: only they can sell it." % str(e["owner"])
			if int(e.get("out", 0)) != 0:
				return "Bring it home first."
			if sell_price(cid) > Shed.garage_money:
				return "The business can't afford it: it only has %s." % money(Shed.garage_money)
			if Shed.ready_bike_place() == null:
				return "There's nowhere at the shed to leave it: the yard by the roller door and every bay are full."
		"home_offer":
			var cid := int(action.get("bike", 0))
			var e := entry(cid)
			var amount := int(action.get("amount", 0))
			if e.is_empty():
				return "That bike has gone."
			if str(e["owner"]) == who:
				return "It's yours already."
			if int(e.get("out", 0)) != 0:
				return "%s is out on it. Wait till it's back." % str(e["owner"])
			if amount < MIN_OFFER:
				return "How much?"
			if int(action.get("paid", 0)) < amount:
				return "That offer isn't paid for."
			if not offer_from(who, cid).is_empty():
				return "You've an offer on it already. Take that back first."
			if offers().size() >= MAX_OFFERS:
				return "There are too many offers waiting. Try again later."
			if count_of(who) >= slots_of(peer):
				return "Your collection is full (%d of %d). %s" % [count_of(who), slots_of(peer), _next_slot_text(peer)]
		"home_withdraw":
			var o: Dictionary = offers().get(int(action.get("offer", 0)), {})
			if o.is_empty():
				return "That offer's been answered."
			if str(o["from"]) != who:
				return "That isn't your offer."
		"home_answer":
			var o: Dictionary = offers().get(int(action.get("offer", 0)), {})
			if o.is_empty():
				return "That offer has gone."
			if str(o["to"]) != who:
				return "That offer isn't for you."
			if bool(action.get("yes", false)):
				var e := entry(int(o["bike"]))
				if e.is_empty() or str(e["owner"]) != who:
					return "That bike isn't yours any more."
				if int(e.get("out", 0)) != 0:
					return "Bring it home first, then accept."
				var buyer := str(o["from"])
				var room := slots_for_level(level_of(peer_of(buyer)) if peer_of(buyer) != 0 else int(o.get("level", 1)))
				if count_of(buyer) >= room:
					return "%s's collection is full." % buyer
		_:
			return "Unknown request."
	return ""


static func _next_slot_text(peer: int) -> String:
	var have := slots_of(peer)
	if have >= MAX_SLOTS:
		return "That's the most a collection holds."
	return "Another slot comes at level %d." % level_for_slots(have + 1)


## Host: does a checked "home_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	var who := name_of(peer)
	match a:
		"home_buy":
			var b := int(action["bike"])
			var price := buy_price(b)
			var paid := int(action.get("paid", 0))
			if paid > price:
				Shed.give_cash(peer, paid - price, "Change")
			var plot := ensure_home(who)
			var what := str(Shed.bikes[b]["name"])
			Sales.note_trade(b, price, who, "crew")
			Shed.credit_garage(price, "%s bought %s" % [who, what])
			var cid := _take_home(b, who)
			entry(cid)["paid"] = price
			return "Bought %s for %s. It's on show at your house, %s." % [what, money(price), _where(plot)]
		"home_take":
			var cid := int(action["bike"])
			var e := entry(cid)
			var plot := plot_of(who)
			var id := unpack(e["pack"], _clear_pickup(plot))
			Shed.bikes[id]["owner"] = who
			Shed.bikes[id]["cid"] = cid
			e.erase("pack")
			e["out"] = id
			return "%s is out in front of the garages, ready to ride. Park it back in the courtyard to put it away." % str(e["name"])
		"home_return":
			var b := int(action["bike"])
			var what := str(Shed.bikes[b]["name"])
			_put_back(b)
			return "%s is back on show." % what
		"home_sell":
			var cid := int(action["bike"])
			var e := entry(cid)
			var price := sell_price(cid)
			var place: Dictionary = Shed.ready_bike_place()
			var id := unpack(e["pack"], place["xf"])
			var bike: Dictionary = Shed.bikes[id]
			bike["bay"] = int(place["bay"])
			bike["stand"] = "" if int(place["bay"]) >= 0 else Shed._rest_stand(id)
			bike["bought"] = price
			_drop_offers(cid, "%s sold it to the garage." % who)
			bikes().erase(cid)
			Shed.charge_garage(price, "Bought %s from %s" % [str(e["name"]), who])
			Shed.give_cash(peer, price, "Sold %s to the garage" % str(e["name"]).left(30))
			var at := "in the yard by the roller door" if int(place["bay"]) < 0 else "in bay %d" % (int(place["bay"]) + 1)
			return "Sold %s to the garage for %s. It's %s, the shed's to sell on." % [str(e["name"]), money(price), at]
		"home_offer":
			var cid := int(action["bike"])
			var e := entry(cid)
			var amount := int(action["amount"])
			var paid := int(action.get("paid", 0))
			if paid > amount:
				Shed.give_cash(peer, paid - amount, "Change")
			var id := _next()
			var owner := str(e["owner"])
			offers()[id] = {"id": id, "bike": cid, "from": who, "to": owner, "amount": amount, "level": level_of(peer)}
			var op := peer_of(owner)
			if op != 0 and op != peer:
				Shed._tell(op, "%s offers you %s for %s." % [who, money(amount), str(e["name"])], true)
			return "Offered %s %s for %s. The money's held till they answer." % [owner, money(amount), str(e["name"])]
		"home_withdraw":
			var o: Dictionary = offers()[int(action["offer"])]
			offers().erase(int(o["id"]))
			_refund(str(o["from"]), int(o["amount"]), "Offer back")
			return "Took your offer back: %s back to you." % money(int(o["amount"]))
		"home_answer":
			var o: Dictionary = offers()[int(action["offer"])]
			offers().erase(int(o["id"]))
			var buyer := str(o["from"])
			var bp := peer_of(buyer)
			var cid := int(o["bike"])
			var e := entry(cid)
			var amount := int(o["amount"])
			if not bool(action.get("yes", false)):
				_refund(buyer, amount, "Offer turned down")
				if bp != 0:
					Shed._tell(bp, "%s turned down your %s for %s." % [who, money(amount), str(e.get("name", "their bike"))], false)
				return "Turned down %s's offer." % buyer
			_refund(who, amount, "Sold %s to %s" % [str(e["name"]).left(30), buyer])
			ensure_home(buyer)
			e["owner"] = buyer
			e["spot"] = _free_spot(buyer)
			e["paid"] = amount
			_drop_offers(cid, "%s sold it to %s." % [who, buyer])
			if bp != 0:
				Shed._tell(bp, "%s took your offer: %s is yours, on show at your house." % [who, str(e["name"])], true)
			return "Sold %s to %s for %s." % [str(e["name"]), buyer, money(amount)]
	return ""


## Host: a shed bike packed into `player_name`'s collection at their house. Returns its id there.
static func _take_home(bike_id: int, player_name: String) -> int:
	var cid := _next()
	var e := {"id": cid, "owner": player_name, "spot": _free_spot(player_name), "out": 0,
		"name": str(Shed.bikes[bike_id]["name"]), "value": worth(bike_id), "paid": 0, "pack": pack(bike_id)}
	Shed.remove_bike(bike_id)
	bikes()[cid] = e
	return cid


## Host: a collection bike that's been out goes back on show (what it's worth now, worked out as
## it comes in).
static func _put_back(bike_id: int) -> void:
	var cid := cid_of_bike(bike_id)
	var e := entry(cid)
	if e.is_empty():
		return
	e["value"] = worth(bike_id)
	e["name"] = str(Shed.bikes[bike_id]["name"])
	e["pack"] = pack(bike_id)
	e["out"] = 0
	Shed.remove_bike(bike_id)


## Host: called whenever a bike is parked (got off, or let go of): one of a collection's bikes
## left in its owner's courtyard goes back on show. True when it did.
static func parked(bike_id: int) -> bool:
	if not Shed.bikes.has(bike_id) or cid_of_bike(bike_id) == 0:
		return false
	var plot := plot_of(owner_of_bike(bike_id))
	if plot < 0 or not HomePlots.in_courtyard(plot, (Shed.bikes[bike_id]["xf"] as Transform3D).origin):
		return false
	_put_back(bike_id)
	return true


## Where a bike taken out is left: in front of the garages, nudged along the doors if a bike is
## already standing there.
static func _clear_pickup(plot: int) -> Transform3D:
	var base := HomePlots.pickup_xf(plot)
	for k in HomePlots.DOOR_X.size():
		var xf := HomePlots.frame(plot) * Transform3D(Basis(Vector3.UP, PI), Vector3(HomePlots.DOOR_X[(k + 1) % HomePlots.DOOR_X.size()], 0.0, HomePlots.PICKUP.z))
		var taken := false
		for id in Shed.bikes:
			if ((Shed.bikes[id]["xf"] as Transform3D).origin - xf.origin).length() < 1.2:
				taken = true
		if not taken:
			return xf
	return base


## Every offer on `cid` called off, the money back to whoever made it.
static func _drop_offers(cid: int, why: String) -> void:
	for id in offers().keys():
		var o: Dictionary = offers()[id]
		if int(o["bike"]) != cid:
			continue
		offers().erase(id)
		_refund(str(o["from"]), int(o["amount"]), "Offer back")
		var p := peer_of(str(o["from"]))
		if p != 0:
			Shed._tell(p, "Your offer's off: %s %s back to you." % [why, money(int(o["amount"]))], false)


## Money to `player_name` (an offer back, or a bike sold): now if they're here, else when they
## next come.
static func _refund(player_name: String, amount: int, reason: String) -> void:
	var p := peer_of(player_name)
	if p != 0 and Shed.give_cash(p, amount, reason):
		return
	var owed: Dictionary = _st()["owed"]
	owed[player_name] = int(owed.get(player_name, 0)) + amount


## Host: a player is in the shed (opening it, or joining): their house. True when it's new.
static func arrived(peer: int) -> bool:
	var who := name_of(peer)
	if who == "":
		return false
	var had := players().has(who)
	ensure_home(who)
	return not had


static var _owed_wait := 0.0


## Host, every frame: money owed to players who are back (an offer of theirs turned down while
## they were away) is paid out once their character has reported in. True when any was.
static func process(delta: float) -> bool:
	_owed_wait -= delta
	var owed: Dictionary = _st()["owed"]
	if _owed_wait > 0.0 or owed.is_empty():
		return false
	_owed_wait = 2.0
	var paid := false
	for who in owed.keys():
		var p := peer_of(str(who))
		if p == 0 or (p != Shed.me() and not Progress._summaries.has(p)):
			continue
		if Shed.give_cash(p, int(owed[who]), "Offers back"):
			Shed._tell(p, "%s back from offers made while you were away." % money(int(owed[who])), true)
			owed.erase(who)
			paid = true
	return paid


## "412 m from the shed".
static func _where(plot: int) -> String:
	if plot < 0:
		return "at the house"
	return "%s from the shed" % Units.distance(HomePlots.from_shed(plot) / 1000.0, 1)
