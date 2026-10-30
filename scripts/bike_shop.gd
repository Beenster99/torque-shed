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
##                suit it (or anything that fits), and the colours of its paint, frame and
##                wheels. It comes new, built in those colours (BikeCopy.order at quality 1).
## Either way the host checks and prices it, and the bike is named after who bought it ("Simon's
## cafe racer").

## How many second-hand bikes are for sale at once.
const FOR_SALE := 16
## The slots the configurator offers a choice in (the rest follow from them, see sanitize_build).
const CONFIG_SLOTS: Array[String] = ["frame", "engine", "tank", "fairing", "saddle", "exhaust", "front_wheel",
	"rear_wheel", "fork", "headlight", "handlebars", "dashboard"]
## The colours a new bike can be ordered in: its paint (tank and fairing), the frame and the wheels.
const COLOUR_PARTS := {"paint": "Paint (tank and fairing)", "frame": "Frame", "wheels": "Wheels"}
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
			var slot: String = CONFIG_SLOTS[rng.randi() % CONFIG_SLOTS.size()]
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


## A second-hand bike or a configured new one as BikeCopy takes it: {"build": ...}. `colours`
## ({paint, frame, wheels} -> Color) colours the new one's parts.
static func src_of(title: String, parts: Dictionary, paint: Color, colours := {}) -> Dictionary:
	var colors := {}
	for key in ["frame", "wheels"]:
		if colours.get(key) is Color:
			for slot in (["front_wheel", "rear_wheel"] if key == "wheels" else [key]):
				colors[slot] = {"color": colours[key], "finish": ""}
	var src := BikeCopy.build_src(title, parts, paint, {}, true)
	(src["build"] as Dictionary)["colors"].merge(colors, true)
	return src


## What `src` costs this player at `quality`.
static func price(src: Dictionary, quality: float) -> int:
	var plan := BikeCopy.plan_of(src)
	return BikeCopy.total(BikeCopy.lines(plan, Shed.me(), quality)) if not plan.is_empty() else 0


## Buys second-hand bike `listing` (one of for_sale's). Why not, or "".
static func buy_used(listing: Dictionary) -> String:
	var src := src_of(str(listing["title"]), listing["parts"], listing["paint"])
	return BikeCopy.order(src, float(listing["quality"]), true)


## Orders a new bike configured as `parts` in these colours. Why not, or "".
static func buy_new(title: String, parts: Dictionary, paint: Color, colours: Dictionary) -> String:
	return BikeCopy.order(src_of(title, parts, paint, colours), 1.0)
