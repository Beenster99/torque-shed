class_name GarageUpgrades
extends RefCounted
## Garage upgrades bought with the garage's money (Shed.garage_money): an extension with more
## bays, more storage, and luxury finishes. Anyone in the crew can buy one from the parts
## computer (Garage upgrades); the host checks it, takes the money and adds it to
## Shed.upgrades (id -> true), which is saved with the shed. The workshop then rebuilds
## (WorkshopUpgrades). Everything built goes behind the shed, away from the yard.

## The catalogue, in shop order. cat: which group it's listed under; price in pounds; needs:
## upgrades it must come after.
const CATALOGUE := {
	"wing": {"name": "Workshop extension", "cat": "build", "price": 30000, "needs": [],
		"desc": "A new wing behind the paint shop, knocked through the back wall behind bay 4: a big open floor for more kit, with its own lights and roof."},
	"bays_56": {"name": "Bays 5 and 6", "cat": "build", "price": 20000, "needs": ["wing"],
		"desc": "Two more work bays in the extension, each with a motorbike lift that raises the bike to working height, a bay light and its own screen. More bikes on the go at once."},
	"bay_7": {"name": "Bay 7", "cat": "build", "price": 12500, "needs": ["bays_56"],
		"desc": "A seventh bay at the far end of the extension, with its own bike lift and screen."},
	"annex": {"name": "Storage annex", "cat": "storage", "price": 15000, "needs": [],
		"desc": "A big, deep, tall storage building behind the storage room, through a wide doorway in its back wall: room for rows of racking."},
	"racking": {"name": "Pallet racking", "cat": "storage", "price": 4500, "needs": ["annex"],
		"desc": "Three runs of heavy-duty racking put up in the annex. Parts go down anywhere on the shelves, and they can be moved like any shelving."},
	"mezzanine": {"name": "Mezzanine floor", "cat": "storage", "price": 35000, "needs": ["annex"],
		"desc": "A steel mezzanine across the back of the annex with a staircase up the side and a railing: room underneath for racking and a deck on top for more stock."},
	"epoxy": {"name": "Painted epoxy floor", "cat": "luxury", "price": 3500, "needs": [],
		"desc": "A glossy charcoal resin floor with a speckled flake finish, through the shed and the extension."},
	"led": {"name": "LED lighting", "cat": "luxury", "price": 6000, "needs": [],
		"desc": "Bright cool-white LED battens and an LED strip round the top of the walls."},
	"cladding": {"name": "Wall cladding", "cat": "luxury", "price": 9000, "needs": [],
		"desc": "Clean white wall panels over brushed aluminium chequer plate, with a red pinstripe."},
	"signage": {"name": "Branded signage", "cat": "luxury", "price": 5000, "needs": [],
		"desc": "A lit TORQUE SHED light box over the roller door, and a neon sign inside."},
	"lounge": {"name": "Crew lounge", "cat": "luxury", "price": 22000, "needs": [],
		"desc": "A room of its own upstairs, on top of the workshop, up an outside staircase: leather sofa, coffee table, drinks fridge, pool table, rug, a lamp and an arcade machine."},
	"showroom": {"name": "Showroom finish", "cat": "luxury", "price": 250000, "needs": ["epoxy", "led", "cladding", "lounge"],
		"desc": "The works: a gloss black and white chequered floor, a honeycomb LED ceiling over the shed and the extension, and chrome trim."},
	# Kit for the paint mixing bay off the paint shop (see PaintBay).
	"paint_stainless": {"name": "Stainless mixing bench", "cat": "paint", "price": 1800, "needs": [],
		"desc": "A stainless steel top for the mixing bench, steadier to pour on, with racks under it for the tins of base."},
	"paint_effects_rack": {"name": "Effects tint rack", "cat": "paint", "price": 4000, "needs": [],
		"desc": "A second rack over the mixing bench for the effect tints: pearls, candy dyes, flakes and chameleons (each unlocks at its level)."},
	"paint_fine_scale": {"name": "Precision scale", "cat": "paint", "price": 1500, "needs": [],
		"desc": "The mixing bench's digital scale reads to 0.1 g."},
	"paint_auto_shaker": {"name": "Automatic paint shaker", "cat": "paint", "price": 3500, "needs": [],
		"desc": "Mixes a tin even in seconds, no stirring, and remixes a saved colour from the swatch wall in one go."},
	"paint_meter": {"name": "Colour meter", "cat": "paint", "price": 6000, "needs": [],
		"desc": "Reads the paint on any part (right mouse with empty hands) and sets it as the mixing bench's target, for matching."},
	"paint_curved_panel": {"name": "Curved spray-out panel", "cat": "paint", "price": 1000, "needs": [],
		"desc": "Test cards on a curved panel, to see a metallic, pearl or chameleon's flop from every angle at once."},
	# The recovery rig (see Recovery): a level gate as well as a price.
	"recovery_rig": {"name": "Recovery truck and bike trailer", "cat": "vehicles", "price": 14500, "needs": [], "level": 8,
		"desc": "A double-cab pickup and a two-bike trailer with a ramp, winch, ratchet straps and a dolly tray, parked in the yard. The phone starts ringing with barn finds and crash rescues to fetch. Needs character level 8."},
}
const CATEGORIES := {"build": "Building work", "storage": "Storage", "luxury": "Luxury", "paint": "Paint mixing bay",
	"vehicles": "Vehicles"}
## XP for buying one, scaled up with its price (see award_mult).
const XP_KEY := "garage_upgrade"


static func exists(id: String) -> bool:
	return CATALOGUE.has(id)


static func owned(id: String) -> bool:
	return Shed.upgrades.has(id)


## The character level the buyer needs for `id` (1 for most).
static func level_needed(id: String) -> int:
	return int(CATALOGUE.get(id, {}).get("level", 1))


static func price(id: String) -> int:
	return int(CATALOGUE.get(id, {}).get("price", 0))


static func title(id: String) -> String:
	return str(CATALOGUE.get(id, {}).get("name", id))


## The upgrades `id` needs that haven't been bought yet.
static func missing_needs(id: String, have: Dictionary) -> Array:
	var out := []
	for n in CATALOGUE.get(id, {}).get("needs", []):
		if not have.has(n):
			out.append(n)
	return out


## Why the garage can't buy `id` right now, or "".
static func check(id: String, have: Dictionary, money: int) -> String:
	if not CATALOGUE.has(id):
		return "There's no upgrade like that."
	if have.has(id):
		return "The garage already has the %s." % title(id).to_lower()
	var need := missing_needs(id, have)
	if not need.is_empty():
		return "Needs the %s first." % " and the ".join(need.map(func(n): return title(n).to_lower()))
	if money < price(id):
		return "The garage can't afford it: %s, and it has %s." % [TvChannels.money_text(price(id)), TvChannels.money_text(money)]
	return ""


## XP multiplier for buying an upgrade: bigger jobs are worth more.
static func award_mult(id: String) -> float:
	return clampf(1.0 + price(id) / 50000.0, 1.0, 8.0)


## The bays the extension adds, after the shed's own four.
static func extra_bays(have: Dictionary) -> int:
	return (2 if have.has("bays_56") else 0) + (1 if have.has("bay_7") else 0)


## A save's upgrades, kept to ones that still exist (old saves have none).
static func sanitize(saved) -> Dictionary:
	var out := {}
	if saved is Dictionary:
		for id in saved:
			if CATALOGUE.has(str(id)):
				out[str(id)] = true
	return out


# ---------------------------------------------------------------------------- looks (options)

## The choices a finish offers before it's bought (and can be changed after, for a fee):
## upgrade id -> its option groups, in the order they're shown. Each group: key, name, kind
## ("colour": swatches; "style": named buttons), the default choice (today's look, which old
## saves keep) and its choices. A choice has an id, a name, a swatch colour and whatever the
## look needs (UpgradeLooks reads them).
const OPTIONS := {
	"epoxy": [
		{"key": "colour", "name": "Colour", "kind": "colour", "default": "charcoal", "choices": [
			{"id": "charcoal", "name": "Charcoal", "color": Color(0.2, 0.22, 0.25)},
			{"id": "slate", "name": "Slate grey", "color": Color(0.42, 0.45, 0.48)},
			{"id": "red", "name": "Racing red", "color": Color(0.5, 0.05, 0.04)},
			{"id": "blue", "name": "Garage blue", "color": Color(0.07, 0.18, 0.42)},
			{"id": "green", "name": "Racing green", "color": Color(0.05, 0.24, 0.13)},
			{"id": "sand", "name": "Sand", "color": Color(0.6, 0.53, 0.4)},
			{"id": "white", "name": "Gloss white", "color": Color(0.84, 0.85, 0.86)},
			{"id": "black", "name": "Jet black", "color": Color(0.035, 0.035, 0.045)}]},
		{"key": "effect", "name": "Effect", "kind": "style", "default": "flake", "choices": [
			{"id": "flake", "name": "Speckled flake", "rough": 0.12, "metal": 0.15},
			{"id": "metallic", "name": "Metallic swirl", "rough": 0.18, "metal": 0.65},
			{"id": "gloss", "name": "Plain gloss", "rough": 0.05, "metal": 0.05},
			{"id": "satin", "name": "Satin", "rough": 0.4, "metal": 0.05}]},
	],
	"led": [
		{"key": "tone", "name": "Light colour", "kind": "colour", "default": "cool", "choices": [
			{"id": "cool", "name": "Cool white", "color": Color(0.92, 0.96, 1.0)},
			{"id": "daylight", "name": "Daylight", "color": Color(0.85, 0.92, 1.0)},
			{"id": "neutral", "name": "Neutral white", "color": Color(1.0, 0.97, 0.9)},
			{"id": "warm", "name": "Warm white", "color": Color(1.0, 0.85, 0.66)}]},
		{"key": "strip", "name": "Wall strip", "kind": "colour", "default": "match", "choices": [
			{"id": "match", "name": "Same as the lights", "color": Color(0.92, 0.96, 1.0)},
			{"id": "red", "name": "Red", "color": Color(1.0, 0.12, 0.08)},
			{"id": "amber", "name": "Amber", "color": Color(1.0, 0.55, 0.08)},
			{"id": "green", "name": "Green", "color": Color(0.15, 1.0, 0.3)},
			{"id": "blue", "name": "Blue", "color": Color(0.15, 0.4, 1.0)},
			{"id": "purple", "name": "Purple", "color": Color(0.6, 0.2, 1.0)},
			{"id": "pink", "name": "Pink", "color": Color(1.0, 0.3, 0.75)}]},
		{"key": "fx", "name": "Strip effect", "kind": "style", "default": "steady", "choices": [
			{"id": "steady", "name": "Steady"}, {"id": "pulse", "name": "Slow pulse"},
			{"id": "rainbow", "name": "Colour cycle"}]},
	],
	"cladding": [
		{"key": "upper", "name": "Wall panels", "kind": "colour", "default": "white", "choices": [
			{"id": "white", "name": "White", "color": Color(0.94, 0.94, 0.95)},
			{"id": "grey", "name": "Light grey", "color": Color(0.7, 0.72, 0.74)},
			{"id": "cream", "name": "Cream", "color": Color(0.9, 0.86, 0.74)},
			{"id": "anthracite", "name": "Anthracite", "color": Color(0.2, 0.21, 0.23)},
			{"id": "blue", "name": "Garage blue", "color": Color(0.16, 0.3, 0.55)},
			{"id": "red", "name": "Racing red", "color": Color(0.62, 0.1, 0.08)},
			{"id": "green", "name": "Racing green", "color": Color(0.1, 0.3, 0.18)}]},
		{"key": "lower", "name": "Chequer plate", "kind": "colour", "default": "alu", "choices": [
			{"id": "alu", "name": "Brushed aluminium", "color": Color(0.72, 0.74, 0.77), "metal": 0.9, "rough": 0.32},
			{"id": "black", "name": "Black", "color": Color(0.08, 0.08, 0.09), "metal": 0.6, "rough": 0.35},
			{"id": "copper", "name": "Copper", "color": Color(0.75, 0.46, 0.3), "metal": 0.9, "rough": 0.3},
			{"id": "red", "name": "Painted red", "color": Color(0.6, 0.07, 0.05), "metal": 0.3, "rough": 0.4}]},
		{"key": "stripe", "name": "Pinstripe", "kind": "colour", "default": "red", "choices": [
			{"id": "red", "name": "Red", "color": Color(0.7, 0.08, 0.06)},
			{"id": "blue", "name": "Blue", "color": Color(0.1, 0.3, 0.75)},
			{"id": "yellow", "name": "Yellow", "color": Color(0.95, 0.75, 0.05)},
			{"id": "green", "name": "Green", "color": Color(0.1, 0.55, 0.2)},
			{"id": "white", "name": "White", "color": Color(0.95, 0.95, 0.95)},
			{"id": "black", "name": "Black", "color": Color(0.05, 0.05, 0.05)},
			{"id": "none", "name": "No stripe", "color": Color(0.5, 0.5, 0.5, 0.0)}]},
	],
	"signage": [
		{"key": "neon", "name": "Neon colour", "kind": "colour", "default": "blue", "choices": [
			{"id": "blue", "name": "Electric blue", "color": Color(0.4, 0.6, 1.0), "text": Color(0.6, 1.6, 3.0), "edge": Color(0.1, 0.35, 0.9)},
			{"id": "red", "name": "Red", "color": Color(1.0, 0.25, 0.2)},
			{"id": "pink", "name": "Hot pink", "color": Color(1.0, 0.3, 0.8)},
			{"id": "green", "name": "Green", "color": Color(0.3, 1.0, 0.4)},
			{"id": "orange", "name": "Orange", "color": Color(1.0, 0.55, 0.15)},
			{"id": "purple", "name": "Purple", "color": Color(0.65, 0.3, 1.0)},
			{"id": "white", "name": "White", "color": Color(0.95, 0.95, 1.0)}]},
		{"key": "box", "name": "Light box edge", "kind": "colour", "default": "orange", "choices": [
			{"id": "orange", "name": "Orange", "color": Color(1.0, 0.55, 0.1)},
			{"id": "red", "name": "Red", "color": Color(1.0, 0.15, 0.1)},
			{"id": "blue", "name": "Blue", "color": Color(0.2, 0.5, 1.0)},
			{"id": "green", "name": "Green", "color": Color(0.2, 1.0, 0.35)},
			{"id": "white", "name": "White", "color": Color(1.0, 1.0, 1.0)}]},
		{"key": "fx", "name": "Neon effect", "kind": "style", "default": "steady", "choices": [
			{"id": "steady", "name": "Steady"}, {"id": "flicker", "name": "Old flicker"}, {"id": "pulse", "name": "Slow pulse"}]},
	],
	"lounge": [
		{"key": "sofa", "name": "Sofa leather", "kind": "colour", "default": "oxblood", "choices": [
			{"id": "oxblood", "name": "Oxblood", "color": Color(0.32, 0.09, 0.06)},
			{"id": "black", "name": "Black", "color": Color(0.05, 0.05, 0.055)},
			{"id": "tan", "name": "Tan", "color": Color(0.55, 0.33, 0.16)},
			{"id": "green", "name": "Bottle green", "color": Color(0.06, 0.2, 0.12)},
			{"id": "cream", "name": "Cream", "color": Color(0.8, 0.75, 0.64)}]},
		{"key": "rug", "name": "Rug", "kind": "colour", "default": "red", "choices": [
			{"id": "red", "name": "Red", "color": Color(0.55, 0.12, 0.1)},
			{"id": "charcoal", "name": "Charcoal", "color": Color(0.2, 0.2, 0.22)},
			{"id": "navy", "name": "Navy", "color": Color(0.1, 0.14, 0.32)},
			{"id": "mustard", "name": "Mustard", "color": Color(0.7, 0.52, 0.12)},
			{"id": "teal", "name": "Teal", "color": Color(0.08, 0.4, 0.4)}]},
		{"key": "neon", "name": "Neon sign", "kind": "colour", "default": "pink", "choices": [
			{"id": "pink", "name": "Pink", "color": Color(1.0, 0.35, 0.8), "text": Color(3.0, 0.5, 2.2), "edge": Color(0.8, 0.1, 0.6)},
			{"id": "blue", "name": "Blue", "color": Color(0.35, 0.6, 1.0)},
			{"id": "green", "name": "Green", "color": Color(0.3, 1.0, 0.45)},
			{"id": "orange", "name": "Orange", "color": Color(1.0, 0.55, 0.15)},
			{"id": "white", "name": "White", "color": Color(0.95, 0.95, 1.0)}]},
	],
	"showroom": [
		{"key": "floor", "name": "Floor", "kind": "colour", "default": "classic", "choices": [
			{"id": "classic", "name": "Black and white chequer", "color": Color(0.92, 0.92, 0.92), "b": Color(0.05, 0.05, 0.06)},
			{"id": "redblack", "name": "Red and black chequer", "color": Color(0.6, 0.06, 0.05), "b": Color(0.05, 0.05, 0.06)},
			{"id": "greywhite", "name": "Grey and white chequer", "color": Color(0.92, 0.92, 0.92), "b": Color(0.42, 0.43, 0.45)},
			{"id": "bluewhite", "name": "Blue and white chequer", "color": Color(0.92, 0.92, 0.92), "b": Color(0.08, 0.2, 0.5)},
			{"id": "black", "name": "Mirror black", "color": Color(0.03, 0.03, 0.035), "b": Color(0.03, 0.03, 0.035)},
			{"id": "white", "name": "Gallery white", "color": Color(0.9, 0.9, 0.9), "b": Color(0.9, 0.9, 0.9)}]},
		{"key": "tiles", "name": "Tile size", "kind": "style", "default": "mid", "choices": [
			{"id": "small", "name": "30 cm", "uv": 1.66}, {"id": "mid", "name": "60 cm", "uv": 0.83},
			{"id": "large", "name": "1.2 m", "uv": 0.415}]},
		{"key": "ceiling", "name": "Ceiling", "kind": "style", "default": "hex", "choices": [
			{"id": "hex", "name": "Honeycomb", "r": 0.7}, {"id": "hex_small", "name": "Fine honeycomb", "r": 0.45},
			{"id": "hex_big", "name": "Giant honeycomb", "r": 1.05}]},
		{"key": "glow", "name": "Ceiling light", "kind": "colour", "default": "white", "choices": [
			{"id": "white", "name": "Cool white", "color": Color(0.97, 0.99, 1.0)},
			{"id": "warm", "name": "Warm white", "color": Color(1.0, 0.86, 0.68)},
			{"id": "ice", "name": "Ice blue", "color": Color(0.55, 0.8, 1.0)},
			{"id": "red", "name": "Race red", "color": Color(1.0, 0.2, 0.15)},
			{"id": "purple", "name": "Purple", "color": Color(0.65, 0.35, 1.0)}]},
		{"key": "trim", "name": "Trim", "kind": "colour", "default": "chrome", "choices": [
			{"id": "chrome", "name": "Chrome", "color": Color(0.85, 0.86, 0.88), "metal": 1.0, "rough": 0.15},
			{"id": "gold", "name": "Gold", "color": Color(0.9, 0.68, 0.28), "metal": 1.0, "rough": 0.2},
			{"id": "black", "name": "Black chrome", "color": Color(0.08, 0.08, 0.09), "metal": 1.0, "rough": 0.12},
			{"id": "red", "name": "Red", "color": Color(0.7, 0.08, 0.06), "metal": 0.5, "rough": 0.35}]},
	],
}
## Changing a bought finish's look: this share of its price, kept between these amounts.
const RESTYLE_SHARE := 0.05
const RESTYLE_MIN := 250
const RESTYLE_MAX := 5000


## Whether `id` offers choices.
static func has_options(id: String) -> bool:
	return OPTIONS.has(id)


## `id`'s option groups (none for most building work).
static func options(id: String) -> Array:
	return OPTIONS.get(id, [])


static func _group(id: String, key: String) -> Dictionary:
	for g in options(id):
		if str(g["key"]) == key:
			return g
	return {}


## Today's look for `id`: every option at its default.
static func default_looks(id: String) -> Dictionary:
	var out := {}
	for g in options(id):
		out[str(g["key"])] = str(g["default"])
	return out


## `chosen` made whole and safe for `id`: every option there, anything unknown at its default.
static func clean_looks(id: String, chosen) -> Dictionary:
	var out := default_looks(id)
	if chosen is Dictionary:
		for g in options(id):
			var key := str(g["key"])
			if chosen.has(key):
				for c in g["choices"]:
					if str(c["id"]) == str(chosen[key]):
						out[key] = str(c["id"])
	return out


## The looks the shed has for `id` (`saved` is Shed.looks): its defaults where none were chosen.
static func looks_of(id: String, saved: Dictionary) -> Dictionary:
	return clean_looks(id, saved.get(id, {}))


## The choice picked for option `key` of `id` in `chosen` (its default when it's missing).
static func choice(id: String, key: String, chosen: Dictionary) -> Dictionary:
	var g := _group(id, key)
	if g.is_empty():
		return {}
	var want := str(chosen.get(key, g["default"]))
	var fallback: Dictionary = {}
	for c in g["choices"]:
		if str(c["id"]) == want:
			return c
		if str(c["id"]) == str(g["default"]):
			fallback = c
	return fallback


## The looks in words: "Racing red, metallic swirl".
static func looks_text(id: String, chosen: Dictionary) -> String:
	var names := []
	for g in options(id):
		names.append(str(choice(id, str(g["key"]), chosen).get("name", "")))
	var text := ", ".join(names)
	return text.substr(0, 1) + text.substr(1).to_lower() if text != "" else ""


## What changing the look of a bought `id` costs.
static func restyle_fee(id: String) -> int:
	return clampi(snappedi(int(price(id) * RESTYLE_SHARE), 50), RESTYLE_MIN, RESTYLE_MAX)


## Why the garage can't change `id` to `chosen` right now, or "".
static func check_restyle(id: String, chosen, have: Dictionary, saved: Dictionary, money: int) -> String:
	if not has_options(id):
		return "There's nothing to choose on that."
	if not have.has(id):
		return "Buy the %s first." % title(id).to_lower()
	if not (chosen is Dictionary) or clean_looks(id, chosen) == looks_of(id, saved):
		return "That's how it looks already."
	if money < restyle_fee(id):
		return "The garage can't afford the %s to change it." % TvChannels.money_text(restyle_fee(id))
	return ""


## A save's looks, kept to upgrades the shed has, with every option there (old saves have none).
static func sanitize_looks(saved, have: Dictionary) -> Dictionary:
	var out := {}
	if saved is Dictionary:
		for id in saved:
			if has_options(str(id)) and have.has(str(id)):
				out[str(id)] = clean_looks(str(id), saved[id])
	return out

# ---------------------------------------------------------------------------- the new rooms

## The extension wing: interior x/z rectangle, behind the paint shop and east of the dyno room.
const WING := Rect2(5.0, 50.4, 9.6, 8.8)
const WING_HEIGHT := 3.8
## The doorway knocked through the shed's back wall into the wing, behind bay 4.
const WING_DOOR_X := 5.75
const WING_DOOR_HALF := 0.7
const WING_DOOR_HEIGHT := 2.4
## The storage annex: interior rectangle behind the storage room, wider than it and deep.
const ANNEX := Rect2(-17.0, 40.0, 11.4, 13.8)
const ANNEX_HEIGHT := 6.0
const ANNEX_DOOR_X := -10.9
const ANNEX_DOOR_HALF := 1.2
const ANNEX_DOOR_HEIGHT := 2.8
## The mezzanine deck across the back of the annex, and its stairs up the east wall: x across
## the flight, z from its foot to the deck's edge, with a clear landing in front of the foot.
const MEZZ_TOP := 3.0
const MEZZ_DEPTH := 4.0
const STAIR_X := Vector2(-6.85, -5.65)
const STAIR_Z := Vector2(40.0 + 4.0 + 4.6, 40.0 + 4.0)
## The crew lounge: a room upstairs on top of the shed (its roof is the floor), reached by a
## steel staircase up the front of the paint shop to a landing at the lounge's door.
const LOFT := Rect2(-6.3, 59.7, 12.6, 10.6)
const LOFT_FLOOR := 4.8
const LOFT_HEIGHT := 2.8
const LOFT_DOOR_X := 5.4
const LOFT_DOOR_HALF := 0.55
const LOFT_DOOR_HEIGHT := 2.2
## The outside stairs: x from the foot to the top, z across the flight; the landing runs on
## from the top of the stairs to LOFT_LANDING_X, in front of the door.
const LOFT_STAIR_X := Vector2(14.2, 7.0)
const LOFT_STAIR_Z := Vector2(70.6, 71.8)
const LOFT_LANDING_X := 4.5
## Where each extension bay's paddock stand is (x), all facing the wing's back wall.
const WING_BAY_X := [6.6, 9.8, 13.0]
const WING_BAY_Z := 52.4
## The extension bays' bike lifts: how high the platform goes and how fast (m/s).
const LIFT_TOP := 0.9
const LIFT_SPEED := 0.3


## The rooms the upgrades add, for Workshop.rooms(): "wing" and "annex" once they're built.
static func rooms(have: Dictionary) -> Dictionary:
	var out := {}
	if have.has("wing"):
		out["wing"] = WING
	if have.has("annex"):
		out["annex"] = ANNEX
	return out


## Where the racking the "racking" upgrade puts up goes: under the mezzanine along the back
## wall, and down the west wall.
static func racking_xfs() -> Array:
	var back := Basis()   # facing +Z, into the room
	return [Transform3D(back, Vector3(ANNEX.position.x + 1.5, 0.0, ANNEX.position.y + 0.35)),
		Transform3D(back, Vector3(ANNEX.position.x + 4.1, 0.0, ANNEX.position.y + 0.35)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(ANNEX.position.x + 0.35, 0.0, ANNEX.position.y + 8.0))]


## The bays with a bike lift (the extension's), of those built with `have`.
static func lift_bays(have: Dictionary) -> Array:
	var out := []
	for i in extra_bays(have):
		out.append(Workshop.BAY_COUNT + i)
	return out


## A save's lifts that are up (bay -> true), kept to bays that have one (and the wash bay's).
static func sanitize_lifts(saved, have: Dictionary) -> Dictionary:
	var out := {}
	var bays := lift_bays(have)
	if saved is Dictionary:
		for bay in saved:
			if str(bay).is_valid_int() and (bays.has(int(bay)) or int(bay) == Wash.LIFT) and bool(saved[bay]):
				out[int(bay)] = true
	return out


## Whether `at` (x, z) is on the outside stairs or landing up to the crew lounge.
static func on_loft_stairs(at: Vector2) -> bool:
	return at.x >= LOFT_LANDING_X and at.x <= LOFT_STAIR_X.x and at.y >= LOFT_STAIR_Z.x and at.y <= LOFT_STAIR_Z.y


## The height of the lounge stairs' walking surface at x (0 at the foot, LOFT_FLOOR at the top).
static func loft_stair_height(x: float) -> float:
	return clampf((LOFT_STAIR_X.x - x) / (LOFT_STAIR_X.x - LOFT_STAIR_X.y), 0.0, 1.0) * LOFT_FLOOR
