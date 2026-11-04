class_name BikeShop
extends RefCounted
## The Bike shop (the Esc menu's Profile panel, its Bike shop tab: BikeShopTab), where a player
## buys a whole bike with their own money:
##   Second hand  a list of made-up bikes for sale, of every style, from tidy to tired, each with
##                its seller, its miles and its price (the parts at its quality, see
##                BikeCopy.price_factor). It comes built and ready to ride, as worn as it's
##                listed (BikeCopy.order with built, see BikeCopy.used_age). The list changes
##                every day.
##   New          a configurator: pick a style, then its parts slot by slot from the ones that
##                suit it (or anything that fits), its extras (mudguards, panniers, a top box,
##                a sat nav, a toolbox), each part's colour, and a badge of its own: a logo and a
##                brand name stamped on the tank (BikeBadge). It comes new, built in those colours
##                (BikeCopy.order at quality 1).
## Either way the host checks and prices it, and the bike is named after who bought it ("Simon's
## cafe racer").

## How many second-hand bikes are for sale at once.
const FOR_SALE := 16
## The slots the configurator offers a choice in (the rest follow from them, see sanitize_build).
const CONFIG_SLOTS: Array[String] = ["frame", "engine", "tank", "fairing", "saddle", "exhaust", "front_wheel",
	"rear_wheel", "fork", "headlight", "handlebars", "dashboard", "front_mudguard", "tail", "panniers", "top_box", "satnav", "toolbox"]
## The slots a second-hand bike's last owner might have changed (not its luggage: a race bike
## with panniers on it would be a strange thing to find for sale).
const SWAP_SLOTS: Array[String] = ["frame", "engine", "tank", "fairing", "saddle", "exhaust", "front_wheel",
	"rear_wheel", "fork", "headlight", "handlebars", "dashboard"]
## What the configurator calls a slot where the parts list's name for it isn't clear enough.
const SLOT_LABELS := {"tail": "Rear guard, tail"}
## Groups of parts a colour can be given to at once (besides any one slot by its own name): the
## wheels, and the mudguards (front and rear; a tail cowl is bodywork, so it keeps its own colour).
const COLOUR_GROUPS := {"wheels": "Wheels", "mudguards": "Mudguards"}
const SELLERS := ["Dave from Settle", "A retired postman", "Mags at the bike club", "A lad in Leeds", "Two-stroke Tony",
	"A vicar, oddly", "The farm down the lane", "A dealer's trade-in", "Someone's uncle", "A courier, moving abroad",
	"The cafe's owner", "A young couple, baby on the way"]
const WORDS := [[0.85, "Immaculate"], [0.7, "Tidy"], [0.55, "Honest"], [0.4, "Well used"], [0.0, "Tired"]]

## The second-hand bikes bought from this machine this session (their keys), off the list.
static var sold := {}


## Today's second-hand bikes: [{key, title, style, parts, paint, quality, miles, seller}], the same all
## day on this machine (`day` days since 1970, today's when left out).
static func for_sale(day := -1) -> Array:
	if day < 0:
		day = int(Time.get_unix_time_from_system() / 86400.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bike_shop_%d" % day)
	var out := []
	var styles := PartsDB.STYLES.duplicate()
	for i in FOR_SALE:
		var style: String = styles[i % styles.size()] if i < styles.size() else styles[rng.randi() % styles.size()]
		var parts: Dictionary = Contracts.style_build(style).duplicate()
		# Somebody's had it a while: a couple of its parts changed for others that suit it.
		for k in 2:
			var slot: String = SWAP_SLOTS[rng.randi() % SWAP_SLOTS.size()]
			var opts := options(slot, style, parts)
			if not opts.is_empty():
				parts[slot] = opts[rng.randi() % opts.size()]
		parts = PartsDB.sanitize_build(parts)
		var q := snappedf(rng.randf_range(0.3, 0.95), BikeCopy.QUALITY_STEP)
		var miles := roundi(lerpf(60000.0, 1500.0, q) * rng.randf_range(0.75, 1.25) / 100.0) * 100
		out.append({"key": "%d_%d" % [day, i], "title": "%s %s" % [word_for(q), PartsDB.style_noun(style)], "style": style, "parts": parts,
			"paint": Shed.PAINTS[rng.randi() % Shed.PAINTS.size()], "quality": q, "miles": miles,
			"seller": SELLERS[rng.randi() % SELLERS.size()]})
	return out


## How a seller sums up a bike at `quality` ("Tidy").
static func word_for(quality: float) -> String:
	for w in WORDS:
		if quality >= float(w[0]):
			return str(w[1])
	return "Tired"


## The parts slot `slot` can have on a `style` bike built of `parts`: the ones that suit the style
## (all of that kind when hardly any do), "none" too where the slot can be empty, and whatever's
## there now.
static func options(slot: String, style: String, parts: Dictionary) -> Array:
	var kind: String = PartsDB.SLOT_KIND.get(slot, "")
	if kind == "" or not PartsDB.by_kind.has(kind):
		return []
	var all: Array = PartsDB.by_kind[kind].map(func(id): return str(id))
	var suits := all.filter(func(id): return PartsDB.styles_of(id).has(style))
	var out: Array = suits if suits.size() >= 2 else all.duplicate()
	if PartsDB.may_be_empty(slot) and not out.has("none"):
		out.append("none")
	var now := str(parts.get(slot, ""))
	if now != "" and not out.has(now):
		out.push_front(now)
	return out


## The configurator's name for `slot` ("Front mudguard").
static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, PartsDB.slot_name(slot)))


## Whether rear part `id` (a tail unit) is a mudguard, a fender or a guard, so it takes the
## mudguards' colour; a cowl or a tail tidy doesn't.
static func is_rear_guard(id: String) -> bool:
	var n := PartsDB.part_name(id).to_lower()
	return PartsDB.kind_of(id) == "tail" and (n.contains("guard") or n.contains("fender"))


## The slots on a bike of `parts` that colour key `key` paints: a slot by its name (when there's
## a part in it), or a group (COLOUR_GROUPS).
static func colour_slots(key: String, parts: Dictionary) -> Array:
	match key:
		"wheels":
			return ["front_wheel", "rear_wheel"]
		"mudguards":
			var out := []
			if str(parts.get("front_mudguard", "none")) != "none":
				out.append("front_mudguard")
			if is_rear_guard(str(parts.get("tail", "none"))):
				out.append("tail")
			return out
	return [key] if PartsDB.SLOT_KIND.has(key) and str(parts.get(key, "none")) != "none" else []


## The colour slot `slot` of a bike of `parts` painted `paint` comes in from the factory: the
## paint on the tank and fairing, the catalogue's colour on the rest.
static func factory_colour(slot: String, parts: Dictionary, paint: Color) -> Color:
	if slot in BikeCopy.PAINTED:
		return paint
	return PartsDB.default_color(str(parts.get(slot, "none")))


## A second-hand bike or a configured new one as BikeCopy takes it: {"build": ...}. `colours`
## (a slot or a group of COLOUR_GROUPS -> Color) colours the new one's parts, a tank's colour
## being its paint too; one left out stays as the factory makes it. `badge` (BikeBadge) is
## stamped on its tank. `finishes` (a slot or group -> one of Shed.FINISHES) is how each part's
## paint looks; one left out keeps the factory's finish.
static func src_of(title: String, parts: Dictionary, paint: Color, colours := {}, badge := {}, finishes := {}) -> Dictionary:
	if colours.get("tank") is Color:
		paint = colours["tank"]
	var colors := {}
	for key in colours:
		if colours[key] is Color:
			for slot in colour_slots(str(key), parts):
				colors[slot] = {"color": colours[key], "finish": ""}
	var src := BikeCopy.build_src(title, parts, paint, {}, true)
	var c: Dictionary = (src["build"] as Dictionary)["colors"]
	c.merge(colors, true)
	# Each finish picked (a slot or a group, as colours) on its parts, in their colour now.
	for key in finishes:
		var f := str(finishes[key])
		if not Shed.FINISHES.has(f):
			continue
		for slot in colour_slots(str(key), parts):
			if c.get(slot) is Dictionary:
				c[slot]["finish"] = f
			else:
				c[slot] = {"color": paint if slot == "tank" else factory_colour(slot, parts, paint), "finish": f}
	var b := BikeBadge.clean(badge)
	if not b.is_empty() and str(parts.get("tank", "none")) != "none":
		if not (c.get("tank") is Dictionary):
			c["tank"] = {"color": paint, "finish": ""}
		c["tank"]["badge"] = b
	return src


## What `src` costs this player at `quality`.
static func price(src: Dictionary, quality: float) -> int:
	var plan := BikeCopy.plan_of(src)
	return BikeCopy.total(BikeCopy.lines(plan, Shed.me(), quality, true)) if not plan.is_empty() else 0


## Buys second-hand bike `listing` (one of for_sale's). Why not, or "".
static func buy_used(listing: Dictionary) -> String:
	var src := src_of(str(listing["title"]), listing["parts"], listing["paint"])
	return BikeCopy.order(src, float(listing["quality"]), true)


## Orders a new bike configured as `parts` in these colours, with `badge` on its tank. Why not, or "".
static func buy_new(title: String, parts: Dictionary, paint: Color, colours: Dictionary, badge := {}, finishes := {}) -> String:
	return BikeCopy.order(src_of(title, parts, paint, colours, badge, finishes), 1.0)


## The fabrication a configured bike takes beyond its style's stock one (BikeRig's fit report),
## said for the configurator, or "" when it all bolts together. The works makes it as it builds the
## bike, and it's on the price (BikeCopy.lines).
static func fab_text(parts: Dictionary, style: String) -> String:
	var work := fab_work(parts, style)
	if work.is_empty():
		return ""
	return "Needs fabrication, done by the works: %s (%s)." % [", ".join(work.map(func(w): return str(w["what"]))),
		TvChannels.money_text(work.reduce(func(t, w): return t + int(w["cost"]), 0))]


## The fabrication a bike of `parts` takes that a stock `style` bike doesn't: [{what, hours, cost}].
static func fab_work(parts: Dictionary, style: String) -> Array:
	var stock: Array = BikeRig.fit(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style))))["work"]
	var out := []
	for what in BikeRig.fit(BikeBuild.new(parts))["work"]:
		if not stock.has(what):
			out.append(BikeRig.fab_job(str(what)))
	return out
