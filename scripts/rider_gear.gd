class_name RiderGear
extends RefCounted
## Rider gear for the player's avatar: helmets, jackets, trousers, boots and gloves, bought in
## the Esc menu's Shop tab with the player's own money and worn on foot and on the bike.
##
## What a player owns and wears lives in their Progress profile (profile["gear"] = {owned: [ids],
## worn: {slot: id}}), so it goes with them between sheds. The free default of each slot is
## always owned. The worn set goes out in the player's Progress summary, so everyone in the
## shed sees it (see RemotePlayer and BikeModel._build_rider); RiderFigure draws it.
##
## Each item: slot, name, price (pounds), desc, finish (how the material looks), base / trim /
## accent colours ("tint" = the player's own colour, "tint_dark" a shade darker), pattern (see
## RiderFigure.PATTERNS), and for some a shape: helmets "cap", "mx" or one of HelmetModel.MODELS;
## boots a shaft height `high` in metres; `extras` for bits stuck on (hump, collar, pockets,
## knees, cuffs, knuckles, buckles, sole, toe).
##
## The worn set also carries the helmet's options, the same whichever helmet is on: "shell" (a
## SHELLS colour), "visor" (a VISORS tint), "goggles" (an open face's, on or off) and "visor_up"
## (flicked up: see flick_visor). worn_of adds "peer", whose it is, so a helmet's visor can
## follow its rider live.

const SLOTS: Array[String] = ["helmet", "jacket", "trousers", "boots", "gloves"]
const SLOT_NAMES := {"helmet": "Helmets", "jacket": "Jackets", "trousers": "Trousers", "boots": "Boots", "gloves": "Gloves"}
## The free gear every rider starts in (and gets back on a profile from before gear).
const DEFAULTS := {"helmet": "helmet_cap", "jacket": "jacket_overalls", "trousers": "trousers_overalls",
	"boots": "boots_work", "gloves": "gloves_work"}

const BLACK := Color(0.06, 0.06, 0.07)
const WHITE := Color(0.92, 0.92, 0.9)
const RED := Color(0.78, 0.08, 0.07)
const BLUE := Color(0.08, 0.2, 0.62)
const ORANGE := Color(0.95, 0.42, 0.05)
const HIVIS := Color(0.85, 0.95, 0.1)
const SILVER := Color(0.75, 0.77, 0.8)
const OLIVE := Color(0.27, 0.3, 0.17)
const DENIM := Color(0.16, 0.24, 0.42)
const TAN := Color(0.62, 0.45, 0.27)
const BROWN := Color(0.33, 0.2, 0.11)
const CREAM := Color(0.9, 0.86, 0.74)
const GREY := Color(0.32, 0.34, 0.37)
const GOLD := Color(0.95, 0.66, 0.12)

## Shell colours a helmet can be had in (free, any helmet): "" is as it comes, "crew" your own
## colour. A pattern's stripes and panels keep their own colour.
const SHELLS := {"": {"name": "As it comes"}, "crew": {"name": "Your crew colour"},
	"black": {"name": "Black", "color": Color(0.05, 0.05, 0.06)}, "white": {"name": "White", "color": WHITE},
	"red": {"name": "Red", "color": RED}, "blue": {"name": "Blue", "color": BLUE},
	"green": {"name": "British racing green", "color": Color(0.04, 0.24, 0.12)}, "orange": {"name": "Orange", "color": ORANGE},
	"yellow": {"name": "Yellow", "color": Color(0.95, 0.76, 0.08)}, "cream": {"name": "Cream", "color": CREAM},
	"silver": {"name": "Silver", "color": SILVER}, "gunmetal": {"name": "Gunmetal", "color": Color(0.2, 0.21, 0.23)}}
const SHELL_ORDER: Array[String] = ["", "crew", "black", "white", "red", "blue", "green", "orange", "yellow", "cream", "silver", "gunmetal"]
## Visors (and goggle lenses): tinted see-through ones, and mirror-finish iridium coats.
const VISORS := {"clear": {"name": "Clear", "color": Color(0.85, 0.9, 0.95), "alpha": 0.12},
	"light": {"name": "Light smoke", "color": Color(0.22, 0.24, 0.27), "alpha": 0.45},
	"dark": {"name": "Dark smoke", "color": Color(0.03, 0.03, 0.04), "alpha": 0.88},
	"blue": {"name": "Blue iridium", "color": Color(0.1, 0.38, 1.0), "alpha": 0.96, "mirror": true},
	"gold": {"name": "Gold iridium", "color": Color(1.0, 0.7, 0.12), "alpha": 0.96, "mirror": true},
	"red": {"name": "Red iridium", "color": Color(1.0, 0.2, 0.08), "alpha": 0.96, "mirror": true},
	"green": {"name": "Green iridium", "color": Color(0.15, 0.85, 0.3), "alpha": 0.96, "mirror": true},
	"silver": {"name": "Silver mirror", "color": Color(0.88, 0.9, 0.93), "alpha": 0.94, "mirror": true}}
const VISOR_ORDER: Array[String] = ["clear", "light", "dark", "blue", "gold", "red", "green", "silver"]

const ITEMS := {
	# Helmets. The cap is what you wear in the shed; on the bike it's a plain lid in your colour.
	# Each helmet's shape is one of HelmetModel's kinds; `visor` is the one it comes with (see
	# VISORS), `goggles` whether an open face comes with them, `touring_visor` half or bubble.
	"helmet_cap": {"slot": "helmet", "name": "Shed cap", "price": 0, "shape": "cap", "base": "tint", "pattern": "plain",
		"finish": "textile", "desc": "A peaked cap in your crew colour. On the bike you get a plain lid to match."},
	"helmet_pudding": {"slot": "helmet", "name": "Ton-Up Pudding Basin", "price": 95, "shape": "open_classic", "base": BLACK,
		"trim": CREAM, "pattern": "plain", "finish": "gloss", "goggles": true, "visor": "clear",
		"desc": "A shiny black classic open face with a tan leather lining, chrome snaps and a pair of round goggles. Pure café racer."},
	"helmet_open_cream": {"slot": "helmet", "name": "Brookstone Open Face", "price": 140, "shape": "open_classic", "base": CREAM,
		"trim": BLACK, "pattern": "stripe", "finish": "gloss", "visor": "light",
		"desc": "Cream classic open face with a thin black stripe over the top, chrome snaps and a leather chin strap."},
	"helmet_chequer": {"slot": "helmet", "name": "Gaffer Chequer", "price": 160, "shape": "open_classic", "base": WHITE,
		"trim": BLACK, "pattern": "check", "finish": "gloss", "visor": "dark",
		"desc": "Black and white chequers all over. Seen from the other end of the paddock."},
	"helmet_wayfarer": {"slot": "helmet", "name": "Wayfarer Jet Tourer", "price": 170, "shape": "open_touring", "base": GREY,
		"trim": ORANGE, "pattern": "panel", "finish": "matte", "visor": "light", "touring_visor": "half", "peak": true,
		"desc": "A roomy touring open face with a peak on snaps and a drop-down half visor. Wind in your face, flies in your teeth."},
	"helmet_bubble": {"slot": "helmet", "name": "Wayfarer Bubble", "price": 190, "shape": "open_touring", "base": RED,
		"trim": WHITE, "pattern": "stripe", "finish": "gloss", "visor": "gold", "touring_visor": "bubble",
		"desc": "Gloss red open face with a big seventies bubble visor that flips right up out of the way."},
	"helmet_stealth": {"slot": "helmet", "name": "Vantor Stealth", "price": 180, "shape": "full_modern", "base": BLACK,
		"pattern": "plain", "finish": "matte", "visor": "dark", "desc": "Matte black modern full face with a dark smoked visor. Says nothing."},
	"helmet_sprint": {"slot": "helmet", "name": "Vantor Sprint", "price": 240, "shape": "full_classic", "base": WHITE,
		"trim": RED, "pattern": "twin", "finish": "gloss", "visor": "light",
		"desc": "Gloss white classic full face, round as a pudding, with a round eyeport and twin red racing stripes front to back."},
	"helmet_apex": {"slot": "helmet", "name": "Vantor Apex GT", "price": 320, "shape": "full_modern", "base": BLUE,
		"trim": WHITE, "accent": RED, "pattern": "race", "finish": "gloss", "visor": "silver",
		"desc": "Sharp modern full face: vents on top and in the chin, a little spoiler, and a silver mirror visor."},
	"helmet_mx": {"slot": "helmet", "name": "Mudlark MX-7", "price": 210, "shape": "mx", "base": HIVIS,
		"trim": BLACK, "pattern": "panel", "finish": "gloss", "visor": "clear",
		"desc": "Off-road lid: big peak, long chin bar and goggles. Hi-vis yellow over black."},
	"helmet_kestrel": {"slot": "helmet", "name": "Kestrel RR Carbon", "price": 620, "shape": "race", "base": BLACK,
		"trim": Color(0.16, 0.16, 0.18), "pattern": "carbon", "finish": "carbon", "visor": "blue",
		"desc": "Bare carbon weave race lid: an aero spoiler, a big eyeport with tear-off posts and a blue iridium visor. Featherweight."},

	# Jackets.
	"jacket_overalls": {"slot": "jacket", "name": "Shed overalls", "price": 0, "base": "tint_dark", "pattern": "plain",
		"finish": "textile", "desc": "Work overalls in your crew colour. Free, and they hide the oil."},
	"jacket_mx": {"slot": "jacket", "name": "Mudlark MX Jersey", "price": 75, "base": ORANGE, "trim": BLACK,
		"pattern": "hoops", "finish": "textile", "desc": "Baggy motocross jersey in orange and black hoops."},
	"jacket_denim": {"slot": "jacket", "name": "Roadhouse Denim", "price": 90, "base": DENIM, "trim": Color(0.75, 0.6, 0.3),
		"pattern": "plain", "finish": "denim", "extras": ["pockets"], "desc": "A classic blue denim jacket with copper-buttoned pockets."},
	"jacket_hivis": {"slot": "jacket", "name": "Beacon Hi-Vis Tourer", "price": 150, "base": HIVIS, "trim": SILVER,
		"pattern": "hivis", "finish": "textile", "extras": ["collar"], "desc": "Fluorescent touring jacket with reflective bands. Drivers see you coming."},
	"jacket_wax": {"slot": "jacket", "name": "Fenway Waxed Cotton", "price": 180, "base": OLIVE, "trim": BROWN,
		"pattern": "plain", "finish": "wax", "extras": ["collar", "pockets"], "desc": "Olive waxed cotton with a cord collar and big flap pockets. Smells of the fifties."},
	"jacket_strata": {"slot": "jacket", "name": "Strata Adventure", "price": 220, "base": GREY, "trim": ORANGE,
		"pattern": "panel", "finish": "textile", "extras": ["collar", "pockets"], "desc": "Grey adventure jacket with orange panels, armour and more pockets than you'll ever fill."},
	"jacket_ironside": {"slot": "jacket", "name": "Ironside Café Leather", "price": 260, "base": BLACK, "trim": SILVER,
		"pattern": "plain", "finish": "leather", "extras": ["collar"], "desc": "Black cowhide café racer jacket with a snap collar."},
	"jacket_kestrel": {"slot": "jacket", "name": "Kestrel Race Leathers", "price": 480, "base": WHITE, "trim": RED,
		"accent": BLUE, "pattern": "race", "finish": "leather", "extras": ["hump"], "desc": "Race-cut leathers in white, red and blue, with an aero hump on the back."},

	# Trousers.
	"trousers_overalls": {"slot": "trousers", "name": "Shed overalls", "price": 0, "base": "tint_dark", "pattern": "plain",
		"finish": "textile", "desc": "The bottom half of your overalls, in your crew colour."},
	"trousers_jeans": {"slot": "trousers", "name": "Roadhouse Riding Jeans", "price": 70, "base": DENIM, "pattern": "plain",
		"finish": "denim", "desc": "Blue jeans with armour hidden in the knees."},
	"trousers_mx": {"slot": "trousers", "name": "Mudlark MX Pants", "price": 85, "base": BLACK, "trim": ORANGE,
		"accent": WHITE, "pattern": "race", "finish": "textile", "extras": ["knees"], "desc": "Motocross pants, black with orange panels and knee guards."},
	"trousers_wax": {"slot": "trousers", "name": "Fenway Waxed Breeks", "price": 110, "base": OLIVE, "pattern": "plain",
		"finish": "wax", "desc": "Olive waxed cotton breeks to go with the jacket."},
	"trousers_strata": {"slot": "trousers", "name": "Strata Cargo Overtrousers", "price": 130, "base": GREY, "trim": ORANGE,
		"pattern": "stripe", "finish": "textile", "extras": ["knees"], "desc": "Grey cargo overtrousers with an orange stripe down each leg."},
	"trousers_ironside": {"slot": "trousers", "name": "Ironside Leather Trousers", "price": 190, "base": BLACK, "pattern": "plain",
		"finish": "leather", "desc": "Black leather riding trousers."},
	"trousers_kestrel": {"slot": "trousers", "name": "Kestrel Race Leathers", "price": 240, "base": WHITE, "trim": RED,
		"accent": BLUE, "pattern": "race", "finish": "leather", "extras": ["knees"], "desc": "The bottom half of the race suit, with knee sliders."},

	# Boots: `high` is how far up the shin the boot comes, in metres.
	"boots_work": {"slot": "boots", "name": "Steel toe-caps", "price": 0, "base": BLACK, "trim": BLACK, "high": 0.13,
		"finish": "leather", "desc": "Scuffed black work boots with steel toe caps."},
	"boots_trainers": {"slot": "boots", "name": "Paddock Trainers", "price": 60, "base": WHITE, "trim": RED, "high": 0.08,
		"finish": "textile", "extras": ["sole"], "desc": "White trainers with a red flash. Not for riding in, but they look the part."},
	"boots_strata": {"slot": "boots", "name": "Strata Touring Boots", "price": 130, "base": BLACK, "trim": GREY, "high": 0.24,
		"finish": "leather", "extras": ["toe"], "desc": "Waterproof mid-height touring boots with grey toe guards."},
	"boots_engineer": {"slot": "boots", "name": "Ironside Engineer Boots", "price": 150, "base": BROWN, "trim": SILVER, "high": 0.3,
		"finish": "leather", "extras": ["buckles"], "desc": "Tall brown engineer boots with a strap and buckle at the top."},
	"boots_mx": {"slot": "boots", "name": "Mudlark MX Boots", "price": 180, "base": WHITE, "trim": BLACK, "high": 0.38,
		"finish": "gloss", "extras": ["buckles", "sole"], "desc": "Tall white motocross boots with four black buckles."},
	"boots_kestrel": {"slot": "boots", "name": "Kestrel Track Boots", "price": 220, "base": WHITE, "trim": RED, "high": 0.32,
		"finish": "leather", "extras": ["toe", "sole"], "desc": "Race boots in white and red with toe sliders."},

	# Gloves.
	"gloves_work": {"slot": "gloves", "name": "Work gloves", "price": 0, "base": BLACK, "finish": "textile",
		"desc": "Black grippy work gloves."},
	"gloves_rigger": {"slot": "gloves", "name": "Rigger Gloves", "price": 20, "base": TAN, "finish": "leather",
		"desc": "Tan leather riggers. Good for hot exhausts."},
	"gloves_mx": {"slot": "gloves", "name": "Mudlark MX Gloves", "price": 35, "base": ORANGE, "trim": BLACK,
		"finish": "textile", "extras": ["knuckles"], "desc": "Thin orange off-road gloves with black knuckles."},
	"gloves_hivis": {"slot": "gloves", "name": "Beacon Winter Gloves", "price": 45, "base": HIVIS, "trim": SILVER,
		"finish": "textile", "extras": ["cuffs"], "desc": "Thick hi-vis winter gloves with long cuffs."},
	"gloves_brookstone": {"slot": "gloves", "name": "Brookstone Gauntlets", "price": 70, "base": BROWN, "trim": CREAM,
		"finish": "leather", "extras": ["cuffs"], "desc": "Brown leather gauntlets with cream cuffs, vintage style."},
	"gloves_strata": {"slot": "gloves", "name": "Strata Carbon Knuckle", "price": 90, "base": BLACK, "trim": Color(0.16, 0.16, 0.18),
		"finish": "leather", "extras": ["knuckles"], "desc": "Black leather with carbon knuckle armour."},
	"gloves_kestrel": {"slot": "gloves", "name": "Kestrel Race Gauntlets", "price": 120, "base": WHITE, "trim": RED,
		"finish": "leather", "extras": ["cuffs", "knuckles"], "desc": "White and red race gauntlets with knuckle armour."},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


## Every item for one slot, the free one first, then cheapest up.
static func by_slot(slot: String) -> Array:
	var out := []
	for id in ITEMS:
		if ITEMS[id]["slot"] == slot:
			out.append(id)
	out.sort_custom(func(a, b): return int(ITEMS[a]["price"]) < int(ITEMS[b]["price"]) \
		or (int(ITEMS[a]["price"]) == int(ITEMS[b]["price"]) and str(a) < str(b)))
	return out


static func price(id: String) -> int:
	return int(get_item(id).get("price", 0))


# ---------------------------------------------------------------------------- the profile's gear

## A worn set with every slot filled by a real item of that slot (the default where it isn't).
static func clean_worn(w) -> Dictionary:
	var out := {}
	for slot in SLOTS:
		var id := str(w.get(slot, "")) if w is Dictionary else ""
		out[slot] = id if str(get_item(id).get("slot", "")) == slot else str(DEFAULTS[slot])
	if not w is Dictionary:
		return out
	# The helmet's options, kept only when they're real choices.
	var shell := str(w.get("shell", ""))
	if SHELLS.has(shell) and shell != "":
		out["shell"] = shell
	if VISORS.has(str(w.get("visor", ""))):
		out["visor"] = str(w["visor"])
	if w.get("goggles") is bool:
		out["goggles"] = w["goggles"]
	if w.get("visor_up") is bool and w["visor_up"]:
		out["visor_up"] = true
	if w.get("peer") is int:
		out["peer"] = w["peer"]
	return out


## A profile's gear: {owned: [ids, the defaults always among them], worn: {slot: id}}, with
## anything unknown or not owned dropped. A profile from before gear gets the defaults.
static func clean_gear(g) -> Dictionary:
	var owned: Array = []
	for slot in SLOTS:
		owned.append(str(DEFAULTS[slot]))
	if g is Dictionary and g.get("owned") is Array:
		for id in g["owned"]:
			if ITEMS.has(str(id)) and not owned.has(str(id)):
				owned.append(str(id))
	var worn := clean_worn(g.get("worn", {}) if g is Dictionary else {})
	for slot in SLOTS:
		if not owned.has(worn[slot]):
			worn[slot] = str(DEFAULTS[slot])
	return {"owned": owned, "worn": worn}


## The local player's gear from their profile (cleaned, so always complete).
static func mine() -> Dictionary:
	if not (Progress.profile.get("gear") is Dictionary):
		Progress.profile["gear"] = clean_gear({})
	return Progress.profile["gear"]


## What `peer` wears, as far as this machine knows: the local profile, else their summary.
static func worn_of(peer: int) -> Dictionary:
	var out := clean_worn(mine().get("worn", {}) if peer == Shed.me() else Progress.summary(peer).get("gear", {}))
	out["peer"] = peer
	return out


static func owns(id: String) -> bool:
	return (mine()["owned"] as Array).has(id)


static func wearing(id: String) -> bool:
	return str(mine()["worn"].get(str(get_item(id).get("slot", "")), "")) == id


## Buys `id` with the player's own money. "" when bought, else why not.
static func buy(id: String) -> String:
	var item := get_item(id)
	if item.is_empty():
		return "That isn't in the shop."
	if owns(id):
		return "You've got that already."
	var cost := int(item["price"])
	if not pay(cost, "Rider gear: %s" % item["name"]):
		return "You can't afford the %s (%s, you have %s)." % [item["name"], TvChannels.money_text(cost),
			TvChannels.money_text(Progress.money())]
	(mine()["owned"] as Array).append(id)
	Progress._touch()
	return ""


## Puts `id` on (it must be owned). "" when worn, else why not.
static func wear(id: String) -> String:
	var item := get_item(id)
	if item.is_empty():
		return "That isn't in the shop."
	if not owns(id):
		return "Buy it first."
	mine()["worn"][str(item["slot"])] = id
	Progress._touch()
	return ""


## Takes `cost` from the player's own money: Progress.spend where the money code has it, else
## straight off their cash. False (and nothing taken) when they can't afford it.
static func pay(cost: int, reason: String) -> bool:
	if cost <= 0:
		return true
	if Progress.has_method("spend"):
		return bool(Progress.call("spend", cost, reason))
	if Progress.money() < cost:
		return false
	Progress.set_money(Progress.money() - cost)
	return true


## One text line for the shop: price, and whether you own or wear it.
static func status_text(id: String) -> String:
	if wearing(id):
		return "Wearing"
	if owns(id):
		return "Owned"
	return "Free" if price(id) == 0 else TvChannels.money_text(price(id))


## A short signature of a worn set, to tell when it has to be drawn again: the five slots, then
## the helmet's colour, visor and goggles when chosen. (Not the visor going up and down: the
## helmet swings that itself.)
static func sig(worn: Dictionary) -> String:
	var bits := []
	for slot in SLOTS:
		bits.append(str(worn.get(slot, "")))
	for k in ["shell", "visor", "goggles"]:
		if worn.has(k):
			bits.append("%s=%s" % [k, str(worn[k])])
	return "|".join(bits)


# ---------------------------------------------------------------------------- the helmet

## Which HelmetModel kind helmet `id` is ("mx" for the motocross lid). The cap is ridden in as a
## plain modern full face.
static func helmet_model(id: String) -> String:
	var shape := str(get_item(id).get("shape", ""))
	match shape:
		"open", "retro":
			return "open_classic"
		"mx":
			return "mx"
	return shape if HelmetModel.MODELS.has(shape) else "full_modern"


## The colour the shell is painted, from the worn set's "shell" (`tint` for the crew colour), or
## a clear colour when it is as it comes.
static func shell_color(worn: Dictionary, tint: Color) -> Color:
	var id := str(worn.get("shell", ""))
	if id == "crew":
		return tint
	return SHELLS.get(id, {}).get("color", Color(0, 0, 0, 0))


## The visor tint worn (see VISORS): the one chosen, else the one the helmet comes with.
static func visor_of(worn: Dictionary) -> String:
	var id := str(worn.get("visor", ""))
	if VISORS.has(id):
		return id
	id = str(get_item(str(worn.get("helmet", ""))).get("visor", "light"))
	return id if VISORS.has(id) else "light"


## Whether a worn set's open face has goggles on: as chosen, else as the helmet comes.
static func goggles_on(worn: Dictionary) -> bool:
	if worn.get("goggles") is bool:
		return worn["goggles"]
	return bool(get_item(str(worn.get("helmet", ""))).get("goggles", false))


## Whether helmet `id`, worn this way, has a visor or goggles to flick up and down: every kind
## but the motocross lid, the classic open face only with goggles on. (The cap is ridden in a
## plain full face, so it has one on the bike.)
static func can_flip_item(id: String, worn: Dictionary) -> bool:
	var model := helmet_model(id)
	if model == "open_classic":
		return goggles_on(worn)
	return model != "mx"


## Whether a worn set's helmet has a visor or goggles to flick.
static func can_flip(worn: Dictionary) -> bool:
	return can_flip_item(str(worn.get("helmet", "")), worn)


## Sets a helmet option for the local player: "shell", "visor" or "goggles". A value it can't
## take puts it back as the helmet comes.
static func set_helmet_option(key: String, value) -> void:
	var worn: Dictionary = mine()["worn"]
	match key:
		"shell":
			if SHELLS.has(str(value)) and str(value) != "":
				worn["shell"] = str(value)
			else:
				worn.erase("shell")
		"visor":
			if VISORS.has(str(value)):
				worn["visor"] = str(value)
			else:
				worn.erase("visor")
		"goggles":
			if value is bool:
				worn["goggles"] = value
			else:
				worn.erase("goggles")
	Progress._touch()


## Whether `peer`'s visor is up: your own from your profile; anyone else's as the host last
## passed it round, else as their summary says.
static func visor_up(peer: int) -> bool:
	if peer == Shed.me():
		return bool(mine()["worn"].get("visor_up", false))
	if Shed.visors.has(peer):
		return bool(Shed.visors[peer])
	var g = Progress.summary(peer).get("gear", {})
	return g is Dictionary and bool(g.get("visor_up", false))


## Flicks the local player's visor (or goggles) up or down, for everyone to see. Says what
## happened, for the HUD.
static func flick_visor() -> String:
	var worn: Dictionary = mine()["worn"]
	if not can_flip(clean_worn(worn)):
		return "No visor on this helmet."
	var up := not bool(worn.get("visor_up", false))
	if up:
		worn["visor_up"] = true
	else:
		worn.erase("visor_up")
	Progress._touch()
	Shed.request({"a": "visor", "up": up})
	var what := "Goggles" if helmet_model(str(worn.get("helmet", ""))) == "open_classic" else "Visor"
	return "%s %s" % [what, "up" if up else "down"]
