class_name Sales
extends RefCounted
## Selling bikes from the showroom. A bike is put up for sale by standing it on one of the
## sales office's four display stands (ride it on or wheel it on: see Shed._park_on_show) and
## pricing it at the office PC upstairs (SalesComputer). Only bikes on a stand can be sold.
##
## The PC shows what each one has cost (bought for, parts fitted, the crew's labour), what it's
## worth (its parts as they are, complete and ready to ride), how unusual it is (parts changed,
## fancy parts, paint, a scratch build) and a recommended price from those and a target margin.
##
## Two kinds of buyer:
##   online   interest comes in over time, more of it the fairer the asking price. A buyer
##            sends an offer to the Sales page (a cash till rings at the PC and in the shed, and
##            the garage TVs' Sales channel shows it). Accept it, turn it down, or counter-offer:
##            the buyer replies a little later, accepting, meeting you halfway or walking off.
##            On a sale the buyer walks in, gets on the bike and rides it away.
##   px       a part-exchange buyer rides their own bike up, parks on the forecourt, walks in to
##            the bike they're after and asks what you'll give for theirs. The Sales page shows
##            their bike (model, parts, condition, mileage, retail and trade value); agree an
##            allowance and they ride off on yours, paying the difference, and theirs is the
##            shed's, parked out front.
##
## All of it is host-authoritative shed state in Shed.sales (saved with the shed). Players ask
## for changes with Shed.request({"a": "sale_..."}), which Shed hands to check()/apply().
## Everything here is static, working on the Shed autoload, like Contracts.

## Target margins the PC offers (profit as a share of the price).
const MARGINS: Array[float] = [0.1, 0.2, 0.3, 0.4]
const DEFAULT_MARGIN := 0.2
## A one-off build fetches up to this much more than its parts are worth.
const UNIQUE_PREMIUM := 0.3
## The recommended price goes up to this far over the fair price to reach the target margin.
const OVER_FAIR := 0.15
## Online buyers a game day for a bike priced at its fair value (fewer dearer, more cheaper).
const BUYERS_PER_DAY := 2.0
const MAX_OFFERS := 6
const MAX_OFFERS_PER_BIKE := 2
## Game hours an offer stands before the buyer gives up waiting.
const OFFER_HOURS := 8.0
## Game hours a buyer takes to answer a counter-offer.
const REPLY_HOURS := 0.25
## Counter-offers a buyer will go through before giving up.
const MAX_ROUNDS := 3
## A counter this far over what a buyer would pay sends them off.
const INSULT := 1.2
## Part-exchange visitors: the first a little after a bike is listed, then every so often.
const PX_FIRST := 3.0
const PX_HOURS := Vector2(6.0, 14.0)
const PX_PATIENCE := 5.0
## An allowance this far under what they'd take sends a part-exchange buyer off.
const PX_INSULT := 0.75
## Where part-exchange buyers park, on the forecourt paving east of the walkway, nose to the glass.
const PX_SPOTS: Array[Transform3D] = [Transform3D(Basis(), Vector3(31.2, 0.0, 74.0)), Transform3D(Basis(), Vector3(33.2, 0.0, 74.0))]
## Visitor figures' ids (CustomerView), well clear of contract customers'.
const PX_ID_BASE := 900000
const BUYER_ID_BASE := 950000
const MAX_DEALS := 20
const MAX_NEWS := 14
const MAX_COLLECT := 6
const COLLECT_HOURS := 2.0
const DAY := 24.0

const OPENERS := ["Lovely bike. Would you take %s?", "I've had my eye on this one. %s, cash?", "Is %s any good to you?",
	"Seen it online. I can do %s.", "Proper job, that. %s and I'll collect.", "%s, and I'll come for it today."]


# ---------------------------------------------------------------------------- state

## A new shed's sales: nothing listed, nobody interested yet.
static func empty() -> Dictionary:
	return {"clock": 0.0, "next": 1, "listings": {}, "offers": {}, "px": {}, "next_px_at": PX_FIRST, "deals": [], "news": [],
		"collect": [], "alerts": 0, "earned": 0}


## Saved or synced sales made safe to use: anything missing (sheds from before selling from
## the showroom) gets its default.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
		elif s.has(key) and key in ["clock", "next_px_at"] and (s[key] is int or s[key] is float):
			out[key] = float(s[key])
	return out


static func _st() -> Dictionary:
	if not (Shed.sales is Dictionary) or not Shed.sales.has("listings"):
		Shed.sales = empty()
	return Shed.sales


static func clock() -> float:
	return float(_st()["clock"])


static func listings() -> Dictionary:
	return _st()["listings"]


static func offers() -> Dictionary:
	return _st()["offers"]


static func px() -> Dictionary:
	return _st()["px"]


static func money(v: int) -> String:
	return TvChannels.money_text(v)


static func _nice(v: float) -> int:
	return Money._nice(maxf(v, 0.0))


static func _news(text: String) -> void:
	var news: Array = _st()["news"]
	news.push_front({"at": clock(), "text": text.left(90)})
	while news.size() > MAX_NEWS:
		news.pop_back()


## The stand (0..3) a bike is on, or -1.
static func stand_of(bike_id: int) -> int:
	return Shed.showroom_spot_of(bike_id)


## Whether a bike is on a stand with nobody on it or wheeling it: on show.
static func on_show(bike_id: int) -> bool:
	if not Shed.bikes.has(bike_id) or stand_of(bike_id) < 0:
		return false
	return int(Shed.bikes[bike_id].get("rider", 0)) == 0 and int(Shed.bikes[bike_id].get("pusher", 0)) == 0


## The bike on stand `i`, or 0.
static func bike_on_stand(i: int) -> int:
	for id in Shed.bikes:
		if stand_of(int(id)) == i:
			return int(id)
	return 0


## A customer's bike in for a job (or one of the shed's being worked on for a contract).
static func is_customer_bike(bike_id: int) -> bool:
	return Shed.bikes.has(bike_id) and (Shed.bikes[bike_id].get("contract", false) or not Contracts.job_for_bike(bike_id).is_empty())


## A bike that's listed, priced, and on its stand: buyers can find it.
static func active(bike_id: int) -> bool:
	return listings().has(bike_id) and int(listings()[bike_id].get("ask", 0)) > 0 and on_show(bike_id)


# ---------------------------------------------------------------------------- pricing

## Everything the PC shows to price a bike: what it's cost the business (`bought`, `parts`,
## `labour`, `sunk`), what it's worth (`worth` its parts as they are, `retail` with the bonus for
## being complete and ready to ride, `condition` 0..1), how unusual it is (`unique` 0..1 and
## `unique_why`, `premium` the extra it earns), the `fair` price, the `trade` price a dealer
## pays now, and at `margin` the `target` price and the `recommended` one with `why`.
static func appraise(bike_id: int, margin := -1.0) -> Dictionary:
	if not Shed.bikes.has(bike_id):
		return {}
	var bike: Dictionary = Shed.bikes[bike_id]
	if margin < 0.0:
		margin = float(listings().get(bike_id, {}).get("margin", DEFAULT_MARGIN))
	margin = clampf(margin, 0.0, 0.8)
	var original: Dictionary = bike.get("original", {})
	var parts_cost := 0
	var labour := int(bike.get("labour", 0))
	var worth := 0.0
	var health := 0.0
	var count := 0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or not Shed.items.has(id):
			continue
		var it: Dictionary = Shed.items[id]
		var part := str(it["part"])
		if it.has("paid"):
			parts_cost += int(it["paid"])
		elif str(original.get(slot, part)) != part:
			parts_cost += Money.part_price(part)   # fitted before parts were costed: about what it cost
		labour += int(it.get("labour", 0))
		worth += Money.item_worth(it)
		health += BikeBuild.part_health(Shed.condition_of(it))
		count += 1
	var bought_known := bike.has("bought")
	var bought := int(bike.get("bought", 0)) if bought_known else estimate_bought(bike_id)
	var sunk := bought + parts_cost + labour
	var complete := Shed.is_complete(bike_id)
	var rideable := Money.rideable(bike_id)
	var bonus := 1.0 + (Money.BONUS_COMPLETE if complete else 0.0) + (Money.BONUS_RIDEABLE if rideable else 0.0)
	var retail := worth * bonus
	var uq := uniqueness(bike_id)
	var premium := float(uq["score"]) * UNIQUE_PREMIUM
	var fair := _nice(retail * (1.0 + premium))
	var target := _nice(sunk / maxf(1.0 - margin, 0.05))
	var rec := _nice(maxf(float(fair), minf(float(target), fair * (1.0 + OVER_FAIR))))
	var why := ""
	if target <= fair:
		why = "Its parts, condition and build make it worth %s; that clears your %d%% margin, so ask what it's worth." % [
			money(fair), roundi(margin * 100.0)]
	elif rec >= target:
		why = "Worth %s, so ask a little over that (%s) to make your %d%% margin. Buyers will haggle." % [money(fair), money(rec),
			roundi(margin * 100.0)]
	else:
		why = "Worth %s; your %d%% margin needs %s, more than buyers will pay. %s keeps it selling." % [money(fair),
			roundi(margin * 100.0), money(target), money(rec)]
	if rec < sunk:
		why += " You'll lose %s on it: it's had more spent on it than it's worth." % money(sunk - rec)
	elif not complete:
		why += " Finish it (every part fitted and bolted) and it's worth a good deal more."
	elif not rideable:
		why += " Petrol and oil in it, ready to ride, adds %d%%." % roundi(Money.BONUS_RIDEABLE * 100.0)
	return {"bought": bought, "bought_known": bought_known, "parts": parts_cost, "labour": labour, "sunk": sunk,
		"worth": roundi(worth), "retail": roundi(retail), "condition": health / maxf(1.0, float(count)), "complete": complete,
		"rideable": rideable, "unique": float(uq["score"]), "unique_why": uq["why"], "premium": premium, "fair": fair,
		"trade": Money.bike_sale(bike_id), "margin": margin, "target": target, "recommended": rec, "why": why}


## What a bike the shed has had since before purchases were noted probably cost: what it
## would have fetched as it came (its parts and their state when it arrived), with the project
## bike mark-up. A scratch build's frame is counted with the parts.
static func estimate_bought(bike_id: int) -> int:
	var bike: Dictionary = Shed.bikes[bike_id]
	if bike.get("scratch", false):
		return 0
	var original: Dictionary = bike.get("original", {})
	var cond: Dictionary = bike.get("original_cond", {})
	var total := 0.0
	for slot in original:
		var part := str(original[slot])
		if part == "none" or PartsDB.get_part(part).is_empty() or PartsDB.is_fluid(part):
			continue
		var c: Dictionary = cond.get(slot, {}) if cond.get(slot) is Dictionary else {}
		var h := BikeBuild.part_health(c) if not c.is_empty() else 0.6
		total += Money.part_price(part) * h * h
	return _nice(total * Money.SELL_RATE * (1.0 + Money.BONUS_COMPLETE) * Money.PROJECT_MARKUP)


## How much of a one-off a bike is, 0..1, and why: parts changed from how it came, fancy and
## light parts, its paint (two-tone, chrome, metallic or patina finishes), built from a bare
## frame, a name of its own, and nothing like it in the shed.
static func uniqueness(bike_id: int) -> Dictionary:
	var bike: Dictionary = Shed.bikes[bike_id]
	var original: Dictionary = bike.get("original", {})
	var score := 0.0
	var why: Array[String] = []
	var changed := 0
	var fitted := 0
	var fancy := 0
	var colours := {}
	var finishes := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or not Shed.items.has(id):
			continue
		var it: Dictionary = Shed.items[id]
		var part := str(it["part"])
		fitted += 1
		if str(original.get(slot, part)) != part:
			changed += 1
		var ids: Array = PartsDB.by_kind.get(PartsDB.kind_of(part), [])
		if PartsDB.is_lightweight(part) or (ids.size() > 2 and ids.find(part) >= int(ids.size() * 0.75)):
			fancy += 1
		if slot in ["frame", "tank", "fairing", "tail", "front_mudguard"] and it.get("color") is Color:
			colours[Shed.paint_index(it["color"])] = true
		var fin := str(it.get("finish", ""))
		if fin in ["chrome", "metallic", "patina"]:
			finishes[fin] = true
	if bike.get("scratch", false):
		score += 0.15
		why.append("built from a bare frame")
	elif fitted > 0 and changed > 0:
		var frac := float(changed) / float(fitted)
		score += minf(0.35, frac * 0.7)
		why.append("%d part%s changed from how it came" % [changed, "" if changed == 1 else "s"])
	if fancy > 0:
		score += minf(0.2, fancy * 0.025)
		why.append("%d top-end or light part%s" % [fancy, "" if fancy == 1 else "s"])
	if colours.size() >= 2:
		score += 0.08
		why.append("two-tone paint")
	if not finishes.is_empty():
		score += minf(0.12, finishes.size() * 0.06)
		var names: Array[String] = []
		for f in finishes:
			names.append(str(Shed.FINISH_NAMES.get(f, f)).to_lower())
		why.append("%s finish" % " and ".join(names))
	var nm := str(bike.get("name", ""))
	if nm != "" and not Shed.BIKE_NAMES.has(nm) and not nm.begins_with("Scratch build") and not nm.begins_with("Part-ex"):
		score += 0.03
		why.append("a name of its own")
	var same := false
	for other in Shed.bikes:
		if int(other) != bike_id and Shed.item_on(int(other), "engine") != 0 and Shed.item_on(bike_id, "engine") != 0 \
				and str(Shed.items[Shed.item_on(int(other), "engine")]["part"]) == str(Shed.items[Shed.item_on(bike_id, "engine")]["part"]) \
				and Shed.item_on(int(other), "frame") != 0 and Shed.item_on(bike_id, "frame") != 0 \
				and str(Shed.items[Shed.item_on(int(other), "frame")]["part"]) == str(Shed.items[Shed.item_on(bike_id, "frame")]["part"]):
			same = true
	if not same:
		score += 0.05
		why.append("nothing like it in stock")
	return {"score": clampf(score, 0.0, 1.0), "why": why}


## Expected online buyers a game day for a bike at its asking price: BUYERS_PER_DAY at a fair
## price, falling away fast above it and climbing below it; a good reputation helps a little.
static func interest(bike_id: int, ask := -1) -> float:
	var ap := appraise(bike_id)
	if ap.is_empty():
		return 0.0
	if ask < 0:
		ask = int(listings().get(bike_id, {}).get("ask", 0))
	if ask <= 0:
		return 0.0
	var r := float(ask) / maxf(1.0, float(ap["fair"]))
	var rate := BUYERS_PER_DAY * (1.0 + (0.95 - r) * 3.0 if r <= 0.95 else exp(-6.0 * (r - 0.95)))
	return minf(rate * (1.0 + 0.01 * mini(Contracts.reputation(), 30)), 8.0)


## "Lively", "Steady", "Slow", "Hardly any" for a buyers-a-day rate.
static func interest_text(rate: float) -> String:
	if rate >= 2.5:
		return "Lively: offers coming in several times a day"
	if rate >= 1.2:
		return "Steady: an offer or two a day"
	if rate >= 0.4:
		return "Slow: an offer every few days"
	return "Hardly any: it's priced well over what it's worth"


## "profit £1,200 (18%)" or "loss £300" for a sale at `amount` of a bike that cost `sunk`.
static func margin_text(amount: int, sunk: int) -> String:
	var p := amount - sunk
	if p < 0:
		return "loss %s" % money(-p)
	return "profit %s (%d%%)" % [money(p), roundi(100.0 * p / maxf(1.0, float(amount)))]


## Profit as a share of the price, -1..1.
static func margin_of(amount: int, sunk: int) -> float:
	return clampf(float(amount - sunk) / maxf(1.0, float(amount)), -1.0, 1.0)


# ---------------------------------------------------------------------------- part-exchange bikes

## What a part-exchange bike is worth: {retail, trade, condition} from its parts and their state
## (it comes complete and ridden in, so with both bonuses).
static func px_values(parts: Dictionary, cond: Dictionary) -> Dictionary:
	var worth := 0.0
	var health := 0.0
	var n := 0
	for slot in parts:
		var part := str(parts[slot])
		if part == "none" or PartsDB.get_part(part).is_empty():
			continue
		var c: Dictionary = cond.get(slot, {}) if cond.get(slot) is Dictionary else {}
		var h := BikeBuild.part_health(c)
		worth += Money.part_price(part) * h * h
		health += h
		n += 1
	var retail := worth * (1.0 + Money.BONUS_COMPLETE + Money.BONUS_RIDEABLE)
	return {"retail": _nice(retail), "trade": _nice(retail * Money.SELL_RATE), "condition": health / maxf(1.0, float(n))}


## "700cc twin", from the engine.
static func model_text(parts: Dictionary) -> String:
	var e := PartsDB.get_part(str(parts.get("engine", "")))
	if e.is_empty():
		return "Bike"
	var cyl := int(e.get("cylinders", 1))
	var word: String = {1: "single", 2: "twin", 3: "triple", 4: "four", 6: "six"}.get(cyl, "%d-cylinder" % cyl)
	return "%dcc %s" % [int(e.get("displacement", 0)), word]


## The lines the Sales page shows about a part-exchange bike's parts: the ones a buyer looks at.
static func px_part_lines(p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var parts: Dictionary = p.get("parts", {})
	var cond: Dictionary = p.get("cond", {})
	for slot in ["frame", "engine", "exhaust", "fork", "shock", "front_wheel", "rear_tyre", "front_disc", "ecu", "fairing", "panniers"]:
		var part := str(parts.get(slot, "none"))
		if part == "none":
			continue
		var c: Dictionary = cond.get(slot, {}) if cond.get(slot) is Dictionary else {}
		out.append("%s: %s, %d%%" % [str(slot).capitalize(), PartsDB.part_name(part), roundi(BikeBuild.part_health(c) * 100.0)])
	return out


# ---------------------------------------------------------------------------- time passing

## The host's clock moves on: buyers make offers, answer counter-offers and give up waiting,
## part-exchange buyers come and go. `delta` is real seconds.
static func process(delta: float) -> void:
	advance(delta * Contracts.hours_rate())


## Moves the sales clock on `hours` game hours (host only).
static func advance(hours: float) -> void:
	var s := _st()
	var before := float(s["clock"])
	s["clock"] = before + maxf(hours, 0.0)
	var now := float(s["clock"])
	var changed := false
	var rng: RandomNumberGenerator = Shed._rng
	# Listings of bikes that have gone (sold to the trade, scrapped, ridden off for good).
	for b in listings().keys():
		if not Shed.bikes.has(int(b)):
			listings().erase(b)
			changed = true
	# Offers: answers to counter-offers, lapsed offers, offers on bikes that have gone.
	for id in offers().keys():
		if not offers().has(id):
			continue
		var o: Dictionary = offers()[id]
		var b := int(o["bike"])
		if not Shed.bikes.has(b) or not listings().has(b):
			offers().erase(id)
			changed = true
		elif str(o["state"]) == "waiting" and now >= float(o.get("reply_at", 0.0)):
			_answer_counter(o)
			changed = true
		elif str(o["state"]) == "open" and now >= float(o.get("expires", 0.0)):
			_news("%s's offer on %s lapsed." % [o["buyer"], o["bike_name"]])
			offers().erase(id)
			changed = true
	# New buyers for each bike on show at a price.
	for b in listings().keys():
		if not active(int(b)) or offers().size() >= MAX_OFFERS or _offers_on(int(b)) >= MAX_OFFERS_PER_BIKE:
			continue
		var rate := interest(int(b))
		if rng.randf() < 1.0 - exp(-rate * maxf(hours, 0.0) / DAY):
			make_offer(int(b))
			changed = true
	# Part-exchange buyers.
	for id in px().keys():
		if now >= float(px()[id].get("leave_at", 0.0)) or not active(int(px()[id].get("target", 0))):
			_news("%s gave up waiting about a part-exchange and rode off." % px()[id]["name"])
			_px_leave(int(id))
			changed = true
	if now >= float(s["next_px_at"]):
		s["next_px_at"] = now + rng.randf_range(PX_HOURS.x, PX_HOURS.y)
		if px().is_empty() and _active_listings().size() > 0 and free_px_spot() >= 0:
			spawn_px()
			changed = true
	var collect: Array = s["collect"]
	for d in collect.duplicate():
		if not (d is Dictionary) or now - float(d.get("at", 0.0)) > COLLECT_HOURS:
			collect.erase(d)
			changed = true
	if changed or floor(before) != floor(now):
		Shed._mark_dirty()
	if changed:
		Shed.changed.emit()


static func _offers_on(bike_id: int) -> int:
	return offers().values().filter(func(o): return int(o["bike"]) == bike_id).size()


static func _active_listings() -> Array:
	return listings().keys().filter(func(b): return active(int(b)))


static func _person(rng: RandomNumberGenerator) -> Dictionary:
	var person_name := "%s %s" % [Contracts.FIRST_NAMES[rng.randi() % Contracts.FIRST_NAMES.size()],
		Contracts.LAST_NAMES[rng.randi() % Contracts.LAST_NAMES.size()]]
	var look := {"top": Contracts.CLOTHES[rng.randi() % Contracts.CLOTHES.size()],
		"legs": (Contracts.CLOTHES[rng.randi() % Contracts.CLOTHES.size()] as Color).darkened(0.3),
		"skin": Contracts.SKINS[rng.randi() % Contracts.SKINS.size()], "hair": Contracts.HAIR[rng.randi() % Contracts.HAIR.size()],
		"hat": rng.randf() < 0.3, "tall": rng.randf_range(0.92, 1.06), "vip": false}
	return {"name": person_name, "look": look}


# ---------------------------------------------------------------------------- online buyers

## A buyer makes an offer on a listed bike (host only). What they'd pay at most (`max`, hidden)
## is round the fair price; their opening offer is under it, and never over the asking price.
## Returns the offer's id.
static func make_offer(bike_id: int) -> int:
	var s := _st()
	var rng: RandomNumberGenerator = Shed._rng
	var ap := appraise(bike_id)
	var ask := int(listings()[bike_id]["ask"])
	var value := float(ap["fair"]) * rng.randf_range(0.88, 1.12)
	var top := 0
	var opening := 0
	if value >= ask:
		top = ask
		opening = _nice(ask * rng.randf_range(0.9, 0.98))
	else:
		top = roundi(value)
		opening = _nice(value * rng.randf_range(0.82, 0.93))
	opening = clampi(opening, 1, ask)
	var who := _person(rng)
	var id := int(s["next"])
	s["next"] = id + 1
	var line := str(OPENERS[rng.randi() % OPENERS.size()]) % money(opening)
	offers()[id] = {"id": id, "bike": bike_id, "bike_name": str(Shed.bikes[bike_id]["name"]), "buyer": who["name"], "look": who["look"],
		"amount": opening, "max": top, "ask": ask, "rounds": 0, "state": "open", "at": clock(), "expires": clock() + OFFER_HOURS,
		"said": line, "history": [{"who": "buyer", "amt": opening}], "final": false, "counter": 0, "by": 0}
	s["alerts"] = int(s["alerts"]) + 1
	_news("%s offered %s for %s." % [who["name"], money(opening), Shed.bikes[bike_id]["name"]])
	Shed._mark_dirty()
	return id


## The buyer answers a counter-offer: takes it if it's within what they'll pay (Haggler lifts
## that a little for whoever made it), walks off if it's well over or they've had enough
## rounds, otherwise comes up halfway (or to their limit, as a final offer).
static func _answer_counter(o: Dictionary) -> void:
	var counter := int(o["counter"])
	var top := float(o["max"]) * (1.0 + Money.HAGGLE_SELL * Money._haggle(int(o.get("by", 0))))
	o["rounds"] = int(o["rounds"]) + 1
	if counter <= top:
		var b := int(o["bike"])
		if active(b):
			o["history"].append({"who": "buyer", "amt": counter})
			_news("%s accepted your %s for %s." % [o["buyer"], money(counter), o["bike_name"]])
			_sell(b, counter, str(o["buyer"]), o["look"], int(o.get("by", 1)), "online")
			_st()["alerts"] = int(_st()["alerts"]) + 1
			return
		_news("%s would have paid %s, but %s is off its stand." % [o["buyer"], money(counter), o["bike_name"]])
		offers().erase(int(o["id"]))
		return
	if counter > top * INSULT or int(o["rounds"]) > MAX_ROUNDS or bool(o.get("final", false)):
		_news("%s said no to %s for %s and walked away." % [o["buyer"], money(counter), o["bike_name"]])
		offers().erase(int(o["id"]))
		return
	var half := _nice((float(o["amount"]) + counter) * 0.5)
	if half >= floori(top):
		o["amount"] = floori(top)
		o["final"] = true
		o["said"] = "%s is as far as I can go. Final offer." % money(int(o["amount"]))
	else:
		o["amount"] = maxi(half, int(o["amount"]))
		o["said"] = "Meet me halfway? %s." % money(int(o["amount"]))
	o["history"].append({"who": "buyer", "amt": int(o["amount"])})
	o["state"] = "open"
	o["expires"] = clock() + OFFER_HOURS
	_st()["alerts"] = int(_st()["alerts"]) + 1
	_news("%s came back with %s for %s." % [o["buyer"], money(int(o["amount"])), o["bike_name"]])


## The bike is sold (host): the money goes to the business, the bike and the other offers on
## it go, and the buyer comes to ride it away (kept in "collect" for everyone to see). `allowance`
## and the visitor are for a part-exchange.
static func _sell(bike_id: int, price: int, buyer: String, look, peer: int, kind: String, allowance := 0, visitor := -1) -> void:
	var s := _st()
	var ap := appraise(bike_id)
	var bike: Dictionary = Shed.bikes[bike_id]
	var bike_name := str(bike["name"])
	var deals: Array = s["deals"]
	deals.push_front({"day": Contracts.day_number(), "bike": bike_name, "buyer": buyer, "price": price, "sunk": int(ap["sunk"]),
		"fair": int(ap["fair"]), "profit": price - int(ap["sunk"]), "kind": kind, "allowance": allowance})
	while deals.size() > MAX_DEALS:
		deals.pop_back()
	var collect: Array = s["collect"]
	var cid := int(s["next"])
	s["next"] = cid + 1
	var entry := {"id": cid, "name": buyer, "look": look if look is Dictionary else {}, "parts": Contracts.current_parts(bike_id),
		"paint": bike["paint"], "cond": Shed.build_of(bike_id).condition.duplicate(true), "xf": bike["xf"], "at": clock()}
	if visitor >= 0:
		entry["visitor"] = visitor
	collect.append(entry)
	while collect.size() > MAX_COLLECT:
		collect.pop_front()
	listings().erase(bike_id)
	for id in offers().keys():
		if int(offers()[id]["bike"]) == bike_id:
			offers().erase(id)
	for id in px().keys():
		if int(px()[id].get("target", 0)) == bike_id and int(id) != visitor:
			_px_leave(int(id))
	Shed._xp(peer, "sell_bike", 1.0, "bike:%d" % bike_id)
	Shed.remove_bike(bike_id)
	var cash := price - allowance
	if cash > 0:
		Shed.credit_garage(cash, ("Sold %s to %s" if kind != "px" else "Part-ex: sold %s to %s") % [bike_name, buyer])
	elif cash < 0:
		Shed.charge_garage(-cash, "Part-ex: %s's bike for %s" % [buyer, bike_name])
	s["earned"] = int(s["earned"]) + cash
	Shed._mark_dirty()


## Host: a bike on a stand is sold to the trade (Money's "money_sell_bike"): into the deals,
## and off sale with its offers.
static func note_trade(bike_id: int, price: int) -> void:
	var ap := appraise(bike_id)
	var deals: Array = _st()["deals"]
	deals.push_front({"day": Contracts.day_number(), "bike": str(Shed.bikes[bike_id]["name"]), "buyer": "the trade", "price": price,
		"sunk": int(ap["sunk"]), "fair": int(ap["fair"]), "profit": price - int(ap["sunk"]), "kind": "trade", "allowance": 0})
	while deals.size() > MAX_DEALS:
		deals.pop_back()
	listings().erase(bike_id)
	for id in offers().keys():
		if int(offers()[id]["bike"]) == bike_id:
			offers().erase(id)
	for id in px().keys():
		if int(px()[id].get("target", 0)) == bike_id:
			_px_leave(int(id))
	_st()["earned"] = int(_st()["earned"]) + price
	_news("Sold %s to the trade for %s." % [Shed.bikes[bike_id]["name"], money(price)])


# ---------------------------------------------------------------------------- part-exchange buyers

## A forecourt parking spot no part-exchange buyer has and no bike stands in, or -1.
static func free_px_spot() -> int:
	var taken := {}
	for id in px():
		taken[int(px()[id].get("park", -1))] = true
	for i in PX_SPOTS.size():
		if taken.has(i):
			continue
		var at := PX_SPOTS[i].origin
		var clear := true
		for b in Shed.bikes.values():
			var o: Vector3 = (b["xf"] as Transform3D).origin
			if Vector2(o.x - at.x, o.z - at.z).length() < 1.4:
				clear = false
		if clear:
			return i
	return -1


## A part-exchange buyer rides in on their own bike after one of the listed ones (host only).
## `target` picks the bike (0: one at random). Returns their id, or 0.
static func spawn_px(target := 0) -> int:
	var spot := free_px_spot()
	var listed := _active_listings()
	if spot < 0 or listed.is_empty():
		return 0
	var rng: RandomNumberGenerator = Shed._rng
	if target == 0 or not listed.has(target):
		target = int(listed[rng.randi() % listed.size()])
	var parts := Contracts.random_parts(rng, true)
	if str(parts.get("side_stand", "none")) == "none" and str(parts.get("centre_stand", "none")) == "none":
		parts["side_stand"] = PartsDB.DEFAULT_BUILD["side_stand"]
	var age := rng.randf_range(0.08, 0.6)
	var cond := {}
	for slot in parts:
		if str(parts[slot]) == "none":
			continue
		cond[slot] = {"rust": clampf(age * rng.randf_range(0.15, 0.9), 0.0, 1.0), "dirt": clampf(age * rng.randf_range(0.4, 1.3), 0.0, 1.0),
			"wear": clampf(age * rng.randf_range(0.3, 1.0), 0.0, 1.0)}
	var km := roundi(age * 45000.0 + rng.randf_range(0.0, 9000.0))
	var values := px_values(parts, cond)
	var want := _nice(float(values["retail"]) * rng.randf_range(0.85, 1.0))
	var least := mini(_nice(float(values["trade"]) * rng.randf_range(0.95, 1.12)), want)
	var who := _person(rng)
	var s := _st()
	var id := int(s["next"])
	s["next"] = id + 1
	var paint := rng.randi() % Shed.PAINTS.size()
	var ask := int(listings()[target]["ask"])
	px()[id] = {"id": id, "name": who["name"], "look": who["look"], "target": target, "target_name": str(Shed.bikes[target]["name"]),
		"park": spot, "parts": parts, "paint": paint, "cond": cond, "km": km, "age": age, "model": model_text(parts),
		"retail": int(values["retail"]), "trade": int(values["trade"]), "condition": float(values["condition"]), "want": want,
		"min": least, "rounds": 0, "arrived": clock(), "leave_at": clock() + PX_PATIENCE, "final": false,
		"said": "I'm after your %s. What'll you give me for mine against it? I was thinking %s." % [Shed.bikes[target]["name"], money(want)],
		"ask": ask}
	s["alerts"] = int(s["alerts"]) + 1
	_news("%s rode in on a %s to part-exchange for %s." % [who["name"], model_text(parts), Shed.bikes[target]["name"]])
	Shed._mark_dirty()
	return id


static func _px_leave(id: int) -> void:
	px().erase(id)


## The deal: they ride off on the listed bike, paying its price less the allowance, and their
## bike is the shed's, parked where they left it on the forecourt.
static func _px_deal(peer: int, id: int, allowance: int) -> String:
	var p: Dictionary = px()[id]
	var target := int(p["target"])
	var price := int(listings()[target]["ask"])
	var parts: Dictionary = p["parts"]
	var paint = Shed.PAINTS[int(p["paint"]) % Shed.PAINTS.size()]
	var theirs := Shed._new_bike(parts, 0, "Part-ex %s" % str(p["model"]), float(p.get("age", 0.3)), paint)
	var bike: Dictionary = Shed.bikes[theirs]
	bike["bay"] = -1
	bike["xf"] = PX_SPOTS[clampi(int(p["park"]), 0, PX_SPOTS.size() - 1)]
	var cond: Dictionary = p.get("cond", {})
	for slot in cond:
		var it_id := Shed.item_on(theirs, str(slot))
		if it_id != 0 and cond[slot] is Dictionary:
			for k in ["rust", "dirt", "wear"]:
				Shed.items[it_id][k] = float(cond[slot].get(k, Shed.items[it_id][k]))
	bike["stand"] = Shed._rest_stand(theirs)
	bike["bought"] = allowance
	bike["km"] = int(p.get("km", 0))
	Contracts.refresh_delivered(theirs)
	var what := str(Shed.bikes[target]["name"])
	var who := str(p["name"])
	_sell(target, price, who, p["look"], peer, "px", allowance, id)
	px().erase(id)
	Shed._xp(peer, "px_deal", 1.0, "px:%d" % id)
	_news("Part-ex: %s took %s, with %s off for their %s." % [who, what, money(allowance), p["model"]])
	var diff := price - allowance
	return "Done: %s rides off on %s and %s. Their %s is parked out front, ready to bring in." % [who, what,
		("pays %s on top" % money(diff)) if diff >= 0 else ("the business pays them %s" % money(-diff)), p["model"]]


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a "sale_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	match a:
		"sale_list":
			var b := int(action.get("bike", 0))
			if not Shed.bikes.has(b):
				return "That bike has gone."
			if stand_of(b) < 0:
				return "Put it on one of the showroom's display stands first."
			if is_customer_bike(b):
				return "That's a customer's bike: it isn't the shed's to sell."
			var ask := int(action.get("ask", 0))
			if ask <= 0 or ask > 10000000:
				return "Set a price."
		"sale_unlist":
			if not listings().has(int(action.get("bike", 0))):
				return "It isn't for sale."
		"sale_accept", "sale_reject", "sale_counter":
			var id := int(action.get("offer", 0))
			if not offers().has(id):
				return "That offer has gone."
			var o: Dictionary = offers()[id]
			if a == "sale_reject":
				return ""
			if str(o["state"]) == "waiting":
				return "Waiting for %s to answer." % o["buyer"]
			if not on_show(int(o["bike"])):
				return "%s has to be on its stand to sell it." % o["bike_name"]
			if a == "sale_counter":
				var amt := int(action.get("amount", 0))
				if amt <= int(o["amount"]):
					return "That's no more than they offered: accept it instead."
				if amt > int(listings().get(int(o["bike"]), {}).get("ask", 0)):
					return "That's more than you're asking for it."
		"sale_px_offer", "sale_px_accept", "sale_px_decline":
			var id := int(action.get("px", 0))
			if not px().has(id):
				return "They've gone."
			if a == "sale_px_decline":
				return ""
			var p: Dictionary = px()[id]
			if not active(int(p["target"])):
				return "%s has to be on its stand, priced, to do the deal." % p["target_name"]
			var price := int(listings()[int(p["target"])]["ask"])
			var allowance := int(p["want"]) if a == "sale_px_accept" else int(action.get("amount", 0))
			if a == "sale_px_offer":
				if allowance <= 0:
					return "Offer them something for their bike."
				if allowance >= int(p["want"]):
					return "That's at least what they asked: accept their figure instead."
			if allowance - price > Shed.garage_money:
				return "The business can't pay them the %s difference." % money(allowance - price)
		_:
			return "Unknown action."
	return ""


## Host: does a checked "sale_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	match a:
		"sale_list":
			var b := int(action["bike"])
			var ask := int(action["ask"])
			var was: Dictionary = listings().get(b, {})
			var margin := clampf(float(action.get("margin", was.get("margin", DEFAULT_MARGIN))), 0.0, 0.8)
			listings()[b] = {"bike": b, "ask": ask, "margin": margin, "since": float(was.get("since", clock()))}
			for id in offers():
				if int(offers()[id]["bike"]) == b:
					offers()[id]["ask"] = ask
			if was.is_empty():
				_news("%s is up for sale at %s on stand %d." % [Shed.bikes[b]["name"], money(ask), stand_of(b) + 1])
				# A buyer or two will come soon after a bike first goes up.
				_st()["next_px_at"] = minf(float(_st()["next_px_at"]), clock() + PX_FIRST)
			return "%s is for sale at %s on stand %d." % [Shed.bikes[b]["name"], money(ask), stand_of(b) + 1]
		"sale_unlist":
			var b := int(action["bike"])
			listings().erase(b)
			for id in offers().keys():
				if int(offers()[id]["bike"]) == b:
					offers().erase(id)
			return "%s is off sale." % (Shed.bikes[b]["name"] if Shed.bikes.has(b) else "It")
		"sale_accept":
			var o: Dictionary = offers()[int(action["offer"])]
			var amt := int(o["amount"])
			var what := str(o["bike_name"])
			_news("You took %s's %s for %s." % [o["buyer"], money(amt), what])
			_sell(int(o["bike"]), amt, str(o["buyer"]), o["look"], peer, "online")
			return "Sold %s to %s for %s. They're on their way to collect it." % [what, o["buyer"], money(amt)]
		"sale_reject":
			var o: Dictionary = offers()[int(action["offer"])]
			offers().erase(int(action["offer"]))
			_news("You turned down %s's %s for %s." % [o["buyer"], money(int(o["amount"])), o["bike_name"]])
			return "Turned down %s's offer." % o["buyer"]
		"sale_counter":
			var o: Dictionary = offers()[int(action["offer"])]
			o["counter"] = int(action["amount"])
			o["by"] = peer
			o["state"] = "waiting"
			o["reply_at"] = clock() + REPLY_HOURS
			o["history"].append({"who": "you", "amt": int(action["amount"])})
			_news("You countered %s with %s for %s." % [o["buyer"], money(int(action["amount"])), o["bike_name"]])
			return "Counter-offer of %s sent to %s." % [money(int(action["amount"])), o["buyer"]]
		"sale_px_accept":
			var id := int(action["px"])
			return _px_deal(peer, id, int(px()[id]["want"]))
		"sale_px_offer":
			var id := int(action["px"])
			var p: Dictionary = px()[id]
			var amt := int(action["amount"])
			p["rounds"] = int(p["rounds"]) + 1
			if amt >= int(p["min"]):
				return _px_deal(peer, id, amt)
			if amt < float(p["min"]) * PX_INSULT or int(p["rounds"]) > MAX_ROUNDS or bool(p.get("final", false)):
				var who := str(p["name"])
				_news("%s wouldn't take %s for their %s and rode off." % [who, money(amt), p["model"]])
				_px_leave(id)
				return "%s won't take %s for it. They're off." % [who, money(amt)]
			var down := maxi(int(p["min"]), _nice((float(p["want"]) + amt) * 0.5))
			p["want"] = down
			p["final"] = down <= int(p["min"])
			p["said"] = ("%s and it's a deal. I can't go lower." if p["final"] else "Come on, it's worth more than that. %s?") % money(down)
			p["leave_at"] = maxf(float(p["leave_at"]), clock() + 1.0)
			return "%s: \"%s\"" % [p["name"], p["said"]]
		"sale_px_decline":
			var id := int(action["px"])
			var who := str(px()[id]["name"])
			_news("You sent %s away." % who)
			_px_leave(id)
			return "%s rides off on their own bike." % who
	return ""


# ---------------------------------------------------------------------------- labour

## The bike and parts the request being done now is about, for its wages (see add_labour).
static var _labour_bike := 0
static var _labour_items: Array = []
static var _labour_frame := -1


## Host: notes what a request works on, before it's done (Shed._apply).
static func note_action(action: Dictionary) -> void:
	_labour_frame = Engine.get_process_frames()
	_labour_items = []
	_labour_bike = 0
	var b := int(action.get("bike", 0)) if (action.get("bike") is int or action.get("bike") is float) else 0
	for key in ["item", "engine"]:
		var v = action.get(key, 0)
		if (v is int or v is float) and Shed.items.has(int(v)):
			_labour_items.append(int(v))
	for v in Array(action.get("items", [])):
		if (v is int or v is float) and Shed.items.has(int(v)):
			_labour_items.append(int(v))
	if b != 0 and Shed.bikes.has(b) and _labour_items.is_empty():
		_labour_bike = b


## Host: a wage of `gross` was paid for the request being done: it goes on the parts (or the
## bike) it was for, as labour sunk into them.
static func add_labour(gross: int) -> void:
	if gross <= 0 or _labour_frame != Engine.get_process_frames():
		return
	if not _labour_items.is_empty():
		var share := maxi(1, roundi(float(gross) / _labour_items.size()))
		for id in _labour_items:
			if Shed.items.has(id):
				Shed.items[id]["labour"] = int(Shed.items[id].get("labour", 0)) + share
	elif _labour_bike != 0 and Shed.bikes.has(_labour_bike):
		Shed.bikes[_labour_bike]["labour"] = int(Shed.bikes[_labour_bike].get("labour", 0)) + gross


# ---------------------------------------------------------------------------- screens

## The Sales TV channel: what's on the stands, the offers in, a part-exchange buyer waiting,
## and the last deals.
static func tv_data() -> Dictionary:
	var stands := []
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		var b := bike_on_stand(i)
		if b == 0:
			stands.append({"stand": i + 1, "name": "", "ask": 0})
		else:
			stands.append({"stand": i + 1, "name": str(Shed.bikes[b]["name"]), "ask": int(listings().get(b, {}).get("ask", 0))})
	var offer_rows := []
	for id in offers():
		var o: Dictionary = offers()[id]
		var sunk := int(appraise(int(o["bike"])).get("sunk", 0))
		offer_rows.append({"buyer": str(o["buyer"]), "bike": str(o["bike_name"]), "amount": int(o["amount"]), "ask": int(o["ask"]),
			"state": str(o["state"]), "margin": margin_of(int(o["amount"]), sunk), "profit": int(o["amount"]) - sunk})
	var px_rows := []
	for id in px():
		var p: Dictionary = px()[id]
		px_rows.append({"name": str(p["name"]), "model": str(p["model"]), "target": str(p["target_name"]), "want": int(p["want"]),
			"retail": int(p["retail"]), "trade": int(p["trade"])})
	var deals := []
	for d in (_st()["deals"] as Array).slice(0, 4):
		deals.append({"bike": str(d.get("bike", "")), "price": int(d.get("price", 0)), "profit": int(d.get("profit", 0)),
			"kind": str(d.get("kind", ""))})
	return {"stands": stands, "offers": offer_rows, "px": px_rows, "deals": deals, "earned": int(_st()["earned"])}


## Draws the Sales channel's page.
static func draw_tv(c: Control, font: Font, data: Dictionary) -> void:
	var good := Dashboard.GOOD
	var dim := Dashboard.DIM
	TvChannels._text(c, font, Vector2(24, 50), "SALES", 40, TvChannels.HEADER_INK)
	TvChannels._text(c, font, Vector2(520, 48), "Showroom takings " + money(int(data.get("earned", 0))), 24, TvChannels.HEADER_INK, 480,
		HORIZONTAL_ALIGNMENT_RIGHT)
	# The stands across the top.
	var stands: Array = data.get("stands", [])
	for i in stands.size():
		var st: Dictionary = stands[i]
		var r := Rect2(24 + i * 245, 84, 230, 96)
		c.draw_rect(r, TvChannels.PANEL)
		c.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), TvChannels.ORANGE if int(st["ask"]) > 0 else Color(1, 1, 1, 0.2))
		TvChannels._text(c, font, r.position + Vector2(18, 28), "STAND %d" % int(st["stand"]), 18, dim)
		var nm := str(st["name"])
		TvChannels._text(c, font, r.position + Vector2(18, 56), nm.left(16) if nm != "" else "empty", 22, Color.WHITE if nm != "" else dim)
		TvChannels._text(c, font, r.position + Vector2(18, 86), money(int(st["ask"])) if int(st["ask"]) > 0 else ("not priced" if nm != "" else ""),
			24, TvChannels.AMBER)
	# Offers on the left, part-exchange and deals on the right.
	TvChannels._text(c, font, Vector2(24, 222), "OFFERS", 22, TvChannels.ORANGE)
	var offs: Array = data.get("offers", [])
	if offs.is_empty():
		TvChannels._text(c, font, Vector2(24, 262), "No offers in yet", 24, dim)
	var y := 262.0
	for o in offs:
		c.draw_rect(Rect2(14, y - 30, 590, 58), TvChannels.PANEL)
		TvChannels._text(c, font, Vector2(28, y - 4), "%s  ·  %s" % [str(o["buyer"]).left(16), str(o["bike"]).left(16)], 20)
		var col := good if float(o["margin"]) >= 0.0 else Dashboard.BAD
		TvChannels._text(c, font, Vector2(28, y + 20), ("%s profit" % money(int(o["profit"]))) if int(o["profit"]) >= 0 else
			("%s loss" % money(-int(o["profit"]))), 16, col)
		TvChannels._text(c, font, Vector2(380, y + 6), money(int(o["amount"])), 30, TvChannels.AMBER, 210, HORIZONTAL_ALIGNMENT_RIGHT)
		if str(o["state"]) == "waiting":
			TvChannels._text(c, font, Vector2(200, y + 20), "waiting for their answer", 16, dim)
		y += 66.0
		if y > Dashboard.PX.y - 20:
			break
	TvChannels._text(c, font, Vector2(630, 222), "PART EXCHANGE", 22, TvChannels.ORANGE)
	var pxs: Array = data.get("px", [])
	var py := 262.0
	if pxs.is_empty():
		TvChannels._text(c, font, Vector2(630, py), "Nobody waiting", 24, dim)
		py += 40.0
	for p in pxs:
		c.draw_rect(Rect2(620, py - 30, 380, 84), TvChannels.PANEL)
		TvChannels._text(c, font, Vector2(634, py - 4), "%s, a %s" % [str(p["name"]).left(14), str(p["model"])], 20)
		TvChannels._text(c, font, Vector2(634, py + 20), "for %s, wants %s" % [str(p["target"]).left(14), money(int(p["want"]))], 17, TvChannels.AMBER)
		TvChannels._text(c, font, Vector2(634, py + 44), "retail %s  ·  trade %s" % [money(int(p["retail"])), money(int(p["trade"]))], 16, dim)
		py += 96.0
	TvChannels._text(c, font, Vector2(630, py + 10), "LAST DEALS", 22, TvChannels.ORANGE)
	py += 46.0
	for d in data.get("deals", []):
		TvChannels._text(c, font, Vector2(634, py), str(d["bike"]).left(16), 20)
		TvChannels._text(c, font, Vector2(800, py), money(int(d["price"])), 20, good if int(d["profit"]) >= 0 else Dashboard.BAD, 190,
			HORIZONTAL_ALIGNMENT_RIGHT)
		py += 30.0
		if py > Dashboard.PX.y - 10:
			break
