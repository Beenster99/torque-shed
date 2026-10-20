class_name BikeCopy
extends RefCounted
## "Order one of these" and "Copy its blueprint" (Simon: "It should be possible to 'order one of
## these' when you are hovered over a bike object", and "When I go up to a bike in the cafe I want
## to be able to copy its blueprint"). Look at any bike on foot (one of the shed's, wherever it
## is, a crew mate's while they ride it, a customer's, a biker's at the cafe, a rider going past
## in town, one parked at an adventure's bike cafe: see BikeCopyView) and {order_bike} opens its
## card (BikeOrderPanel):
##   copy_order      buys every part on its build from the parts computer's catalogue, each at
##                   what that player pays for it there (Money.buy_price: Haggler counts), out of
##                   their own money. They're boxed outside the roller door in its colours straight
##                   away; whatever the delivery area hasn't room for waits on order (Shed.on_order)
##                   and comes as soon as there is room. The card's quality slider (Simon: "Add a
##                   slider for bike quality when ordering one into the shed") orders it anywhere
##                   from worn-out used parts up to new: the parts come in that condition, unboxed
##                   when they're used, for less (see used_cond and price_factor). The request
##                   carries "quality" (0 worn .. 1 new); the host checks it and prices it itself.
##   copy_blueprint  keeps the bike as a blueprint (its parts, their colours, its paint and fit),
##                   named after it, to build from or order the usual way ({menu}, Blueprints).
##
## A request carries where the bike is: {"bike": id} for one of the shed's (the host reads it as
## it is now, like geometry mode's Save + blueprint), else {"build": {name, parts, colors, paint}}
## for a bike that isn't the shed's, as the asking player's game draws it (every machine draws the
## same: cafe bikers come from Shed.coffee, the riders in town and the bikes parked at a stop from
## a seed). The host checks the build is a real one (PartsDB.sanitize_build) and works out the
## price itself; the cash was taken on the asking player's machine first (see order()) and what
## the host doesn't spend goes back.

## The parts that wear a bike's paint when it isn't the shed's (as SalesView._bike_look draws them).
const PAINTED: Array[String] = ["tank", "fairing"]
const NAME_MAX := 28
const DELIVERY := "Straight away, boxed outside the roller door. Whatever won't fit in the delivery area waits on order and comes as soon as there's room."
## The quality slider: from worn (0) to new (1), in steps of this.
const QUALITY_STEP := 0.05
## What the worst used parts cost, as a share of the new price (it rises in step to new).
const USED_PRICE := 0.3
## How worn, rusty and dirty the worst used parts are (better ones in step to none).
const USED_WEAR := 0.65
const USED_RUST := 0.45
const USED_DIRT := 0.7
## Names along the slider, from the top: [at least this quality, what it's called].
const QUALITY_NAMES := [[1.0, "New"], [0.75, "Nearly new"], [0.45, "Used"], [0.2, "Well used"], [0.0, "Worn"]]


# ---------------------------------------------------------------------------- what a bike is

## A bike's build as a blueprint holds it ({name, parts, colors, paint, geo, from}), from a
## request's "src" (see the top). Empty when that bike has gone or the build isn't one.
static func plan_of(src) -> Dictionary:
	if not (src is Dictionary):
		return {}
	if src.has("bike"):
		var id := int(src["bike"])
		if not Shed.bikes.has(id):
			return {}
		var plan: Dictionary = Shed.blueprint_of(id)
		plan["name"] = str(Shed.bikes[id]["name"])
		return plan
	var b = src.get("build")
	if not (b is Dictionary) or not (b.get("parts") is Dictionary):
		return {}
	var parts: Dictionary = PartsDB.sanitize_build((b["parts"] as Dictionary).duplicate())
	var paint: Color = b["paint"] if b.get("paint") is Color else Shed.PAINTS[0]
	var colors := {}
	var given: Dictionary = b.get("colors", {}) if b.get("colors") is Dictionary else {}
	for slot in given:
		if parts.has(slot) and given[slot] is Dictionary and given[slot].get("color") is Color:
			colors[slot] = {"color": given[slot]["color"], "finish": str(given[slot].get("finish", "")).left(16)}
	var n := clean_name(str(b.get("name", "")))
	return {"name": n if n != "" else default_name(parts), "parts": parts, "colors": colors, "paint": paint, "geo": {}, "from": n}


## The "build" a request carries for a bike that isn't the shed's: its parts and paint, with the
## paint on PAINTED unless `cond` (as the bike is drawn) gives a part a colour of its own.
static func build_src(bike_name: String, parts: Dictionary, paint: Color, cond := {}, painted := true) -> Dictionary:
	var colors := {}
	for slot in PartsDB.SLOTS:
		var c = cond.get(slot, {})
		if c is Dictionary and c.get("color") is Color:
			colors[slot] = {"color": c["color"], "finish": ""}
		elif painted and slot in PAINTED and str(parts.get(slot, "none")) != "none":
			colors[slot] = {"color": paint, "finish": ""}
	return {"build": {"name": clean_name(bike_name), "parts": parts.duplicate(), "colors": colors, "paint": paint}}


## "Cafe racer, 750cc twin": what a bike with no name of its own is called.
static func default_name(parts: Dictionary) -> String:
	var style := str(PartsDB.detect_style(parts).get("style", ""))
	var what := PartsDB.style_name(style) if style != "" else "Bike"
	return clean_name("%s, %s" % [what, Sales.model_text(parts)])


static func clean_name(n: String) -> String:
	return n.strip_edges().replace("\n", " ").left(NAME_MAX).strip_edges()


## Every part on a plan's build, one row each: {slot, part, name, price} with the price `peer`
## pays for it at the parts computer, at `quality` (see price_factor). The frame first, as the
## build goes.
static func lines(plan: Dictionary, peer: int, quality := 1.0) -> Array:
	var out := []
	for row in Shed.plan_rows({"parts": plan.get("parts", {})}, 0):
		var price := Money.buy_price(str(row["part"]), peer)
		if not is_new(quality) and not PartsDB.is_fluid(str(row["part"])):
			price = maxi(1, roundi(price * price_factor(quality)))
		out.append({"slot": row["slot"], "part": row["part"], "name": row["name"], "price": price})
	return out


# ---------------------------------------------------------------------------- quality

## A quality as an order can have it: 0 (worn) to 1 (new) in QUALITY_STEPs, or -1 for one that
## isn't (not a number, or off the slider's ends).
static func quality_of(q) -> float:
	if not (q is float or q is int) or is_nan(float(q)) or float(q) < -0.001 or float(q) > 1.001:
		return -1.0
	return clampf(snappedf(float(q), QUALITY_STEP), 0.0, 1.0)


static func is_new(quality: float) -> bool:
	return quality >= 1.0 - QUALITY_STEP * 0.5


## What parts at `quality` cost, as a share of the new price.
static func price_factor(quality: float) -> float:
	return 1.0 if is_new(quality) else lerpf(USED_PRICE, 1.0, clampf(quality, 0.0, 1.0))


## The state parts at `quality` come in: {rust, dirt, wear} ({} for new), as Shed.deliver_new
## takes it.
static func used_cond(quality: float) -> Dictionary:
	if is_new(quality):
		return {}
	var k := 1.0 - clampf(quality, 0.0, 1.0)
	return {"wear": USED_WEAR * k, "rust": USED_RUST * k, "dirt": USED_DIRT * k}


## What the slider calls `quality` ("Used").
static func quality_name(quality: float) -> String:
	for n in QUALITY_NAMES:
		if quality >= float(n[0]) - QUALITY_STEP * 0.5:
			return str(n[1])
	return "Worn"


## The slider's line: "Used: about 68% condition, unboxed, 65% of the new price".
static func quality_text(quality: float) -> String:
	if is_new(quality):
		return "New: boxed, at the full price"
	return "%s: about %d%% condition, unboxed, %d%% of the new price" % [quality_name(quality),
		roundi(BikeBuild.part_health(used_cond(quality)) * 100.0), roundi(price_factor(quality) * 100.0)]


static func total(rows: Array) -> int:
	var t := 0
	for r in rows:
		t += int(r["price"])
	return t


## A blueprint name not taken yet: `base`, else "base 2", "base 3"...
static func free_name(base: String) -> String:
	base = clean_name(base)
	if base == "":
		base = "Blueprint"
	if Shed.blueprint_named(base) == 0:
		return base
	for i in range(2, 100):
		var n := "%s %d" % [base.left(NAME_MAX - 3).strip_edges(), i]
		if Shed.blueprint_named(n) == 0:
			return n
	return base


# ---------------------------------------------------------------------------- from this machine

## Orders one of the bike at `src` with this player's own money: the cash goes here first, then
## the host delivers it (and hands back anything it didn't spend). Returns why not, or "".
static func order(src: Dictionary, quality := 1.0) -> String:
	var plan := plan_of(src)
	if plan.is_empty():
		return "That bike has gone."
	var cost := total(lines(plan, Shed.me(), quality))
	var action := {"a": "copy_order", "src": src, "paid": cost, "quality": quality}
	var why := Shed.check(Shed.me(), action)
	if why != "":
		return why
	if not Progress.spend(cost, "Ordered: %s" % str(plan["name"]).left(40)):
		return "That's %s and you have %s." % [TvChannels.money_text(cost), TvChannels.money_text(Progress.money())]
	Shed.request(action)
	return ""


static func copy_blueprint(src: Dictionary) -> String:
	var why := Shed.check(Shed.me(), {"a": "copy_blueprint", "src": src})
	if why != "":
		return why
	Shed.request({"a": "copy_blueprint", "src": src})
	return ""


# ---------------------------------------------------------------------------- the host

static func check(peer: int, action: Dictionary) -> String:
	var plan := plan_of(action.get("src"))
	if plan.is_empty():
		return "That bike has gone."
	match str(action.get("a", "")):
		"copy_order":
			var quality := quality_of(action.get("quality", 1.0))
			if quality < 0.0:
				return "That isn't a quality the parts computer sells."
			var paid := int(action.get("paid", 0))
			var cost := total(lines(plan, peer, quality))
			if cost <= 0:
				return "There's nothing on it to order."
			if paid < cost:
				return "That's %s now: you paid %s." % [TvChannels.money_text(cost), TvChannels.money_text(paid)]
		"copy_blueprint":
			if Shed.blueprints.size() >= Shed.MAX_BLUEPRINTS:
				return "There are %d blueprints already. Delete one first ({menu}, Blueprints)." % Shed.MAX_BLUEPRINTS
		_:
			return "Unknown request."
	return ""


static func apply(peer: int, action: Dictionary) -> String:
	var plan := plan_of(action["src"])
	match str(action["a"]):
		"copy_order":
			var quality := quality_of(action.get("quality", 1.0))
			var used := used_cond(quality)
			var rows := lines(plan, peer, quality)
			var cost := total(rows)
			var paid := int(action.get("paid", 0))
			if paid > cost:
				Shed.give_cash(peer, paid - cost, "Order change")
			var by := Shed.orderer_name(peer)
			var colors: Dictionary = plan.get("colors", {})
			var boxed := 0
			for r in rows:
				var look: Dictionary = colors.get(r["slot"], {})
				var cond := {} if PartsDB.is_fluid(str(r["part"])) else used
				if Shed.deliver_new(str(r["part"]), look.get("color"), str(look.get("finish", "")), int(r["price"]), by, cond) != 0:
					boxed += 1
				else:
					var o := {"part": str(r["part"]), "color": look.get("color"), "finish": str(look.get("finish", "")), "paid": int(r["price"]), "by": by}
					if not cond.is_empty():
						o["used"] = cond
					Shed.on_order.append(o)
			var said := "Ordered one of %s%s: %d parts for %s." % [str(plan["name"]), "" if used.is_empty() else " (%s)" % quality_name(quality).to_lower(),
				rows.size(), TvChannels.money_text(cost)]
			var where := "boxed" if used.is_empty() else "laid out"
			if boxed == rows.size():
				said += " They're %s outside the roller door." % where
			else:
				said += " %d are %s outside the roller door; the other %d come as soon as there's room in the delivery area." % [boxed, where, rows.size() - boxed]
			return said
		"copy_blueprint":
			var n := free_name(str(plan["name"]))
			Shed.store_blueprint(n, plan)
			return "Copied its blueprint as \"%s\". Build it from {menu}, Blueprints." % n
	return ""
