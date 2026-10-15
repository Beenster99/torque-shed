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
}
const CATEGORIES := {"build": "Building work", "storage": "Storage", "luxury": "Luxury"}
## XP for buying one, scaled up with its price (see award_mult).
const XP_KEY := "garage_upgrade"


static func exists(id: String) -> bool:
	return CATALOGUE.has(id)


static func owned(id: String) -> bool:
	return Shed.upgrades.has(id)


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


## A save's lifts that are up (bay -> true), kept to bays that have one.
static func sanitize_lifts(saved, have: Dictionary) -> Dictionary:
	var out := {}
	var bays := lift_bays(have)
	if saved is Dictionary:
		for bay in saved:
			if str(bay).is_valid_int() and bays.has(int(bay)) and bool(saved[bay]):
				out[int(bay)] = true
	return out


## Whether `at` (x, z) is on the outside stairs or landing up to the crew lounge.
static func on_loft_stairs(at: Vector2) -> bool:
	return at.x >= LOFT_LANDING_X and at.x <= LOFT_STAIR_X.x and at.y >= LOFT_STAIR_Z.x and at.y <= LOFT_STAIR_Z.y


## The height of the lounge stairs' walking surface at x (0 at the foot, LOFT_FLOOR at the top).
static func loft_stair_height(x: float) -> float:
	return clampf((LOFT_STAIR_X.x - x) / (LOFT_STAIR_X.x - LOFT_STAIR_X.y), 0.0, 1.0) * LOFT_FLOOR
