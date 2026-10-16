class_name PaintBay
extends RefCounted
## The paint mixing bay: a room off the paint shop, behind a glass door, where paint is mixed
## by hand (see PaintMix for the maths). Its stations:
##   bench      the mixing bench: a tin on the digital scale, bottles tipped over it to pour, a
##              stick to stir it (F to step up to it; see PaintBench for the game); the paint
##              shop has a compact twin of it by the spray bay (SHOP_BENCH), the same bench
##   rack       the tint rack over the bench: the stock rack's 16 bottles, and the effects
##              rack's 12 (pearls, candies, flakes, chameleons) once the garage buys it
##   shaker     drop a tin in for an even mix (the automatic one is quick, and remixes a saved
##              colour from the swatch wall in one go)
##   shelf      the tin shelf: saved tins, labelled, to carry to the paint shop and pour into the
##              spray gun's cup, or to hand a mate
##   swatch     the swatch wall: every saved recipe as a sprayed card with its name; a card
##              loads its recipe onto the bench to mix again, or pins it to the whiteboard
##   stand      the spray-out stand: the last test card sprayed from the bench
##   booth      the daylight booth: the test card under daylight, the shop's strip lights and
##              a sunset, side by side
##   tape       the masking tape roll on its hook: tape a stripe or two-tone on a painted part,
##              spray the second colour over it and peel it off
## Bases and tints are bought with the garage's money (from the parts computer's Paint
## supplies, or the bench's Supplies page); a tin of base is a litre, a bottle of tint 250 g.
##
## All of it is host-authoritative shed state in Shed.paint_bay (saved with the shed). Players
## ask for changes with Shed.request({"a": "paint_..."}), which Shed hands to check()/apply().
## Everything here is static, working on the Shed autoload, like CoffeeShop.

## The room: interior x/z rectangle, off the paint shop's east wall, the glass door at its
## front end (the paint shop's east wall, between the spray bay and the front wall).
const ROOM := Rect2(14.2, 59.8, 2.8, 10.4)
const HEIGHT := 3.4
const DOOR_Z := 69.6
const DOOR_HALF := 0.42
const DOOR_HEIGHT := 2.2
const WALL_X := 14.1           # the middle of the wall shared with the paint shop
## The bench along the east wall, its top's height, where the scale sits on it, and the
## shaker at its far end.
const BENCH := Rect2(16.35, 62.8, 0.65, 4.0)
const BENCH_TOP := 0.92
const SCALE_AT := Vector3(16.62, BENCH_TOP, 64.6)
const SHAKER_AT := Vector3(16.62, BENCH_TOP, 66.25)
## Where you stand at the bench, facing it (+X), and the camera over the scale while mixing.
const BENCH_STAND := Vector3(15.6, 0.0, 64.6)
const BENCH_EYE := Vector3(15.95, 1.55, 64.6)
## The paint shop's own compact mixing bench, against its back wall beside the spray bay: the
## same bench as the bay's (one tin on the scale, one person mixing at a time, the same stock
## and recipes), with a scale and a rack of bottles of its own. bench()["at"] says which of the
## two is in use ("bay" or "shop"); the tin on the scale is drawn there. You stand at it facing
## the back wall (-Z).
const SHOP_BENCH := Rect2(7.05, 59.8, 1.8, 0.6)
const SHOP_SCALE_AT := Vector3(7.75, BENCH_TOP, 60.1)
const SHOP_STAND := Vector3(7.75, 0.0, 61.0)
const SHOP_EYE := Vector3(7.75, 1.62, 60.88)
const SHOP_RACK_Z := 59.86
const SHOP_RACK_Y := [1.3, 1.6]
const SHOP_RACK_X0 := 7.14
const SHOP_RACK_STEP := 0.115
## The tint rack over the bench: two shelves of the stock rack, then the effects rack beside it.
const RACK_X := 16.86
const RACK_Y := [1.32, 1.72]
const RACK_Z0 := 62.95
const RACK_STEP := 0.25
## The tin shelf by the door end of the east wall: 3 shelves of 4.
const SHELF_X := 16.72
const SHELF_Z := 67.6
const SHELF_Y := [0.45, 0.95, 1.45]
const SHELF_SLOTS := 12
## The swatch wall on the west wall (the paint shop's side): columns along z, rows down it.
const SWATCH_X := 14.22
const SWATCH_Z0 := 61.4
const SWATCH_COLS := 8
const SWATCH_ROWS := 4
const SWATCH_STEP := Vector2(0.78, 0.46)
const SWATCH_TOP := 2.35
const MAX_SWATCHES := 32
## The spray-out panel stand and the daylight booth at the far (north) end.
const STAND_AT := Vector3(15.5, 0.0, 61.4)
const BOOTH := Rect2(14.6, 59.8, 2.2, 0.62)
const BOOTH_Y := Vector2(0.95, 1.85)
## The masking tape roll's hook, by the door.
const TAPE_AT := Vector3(14.24, 1.3, 68.6)
## The shaker: seconds to mix a tin, the plain one and the automatic upgrade.
const SHAKE_TIME := 20.0
const AUTO_SHAKE_TIME := 4.0
## A new shed's (and an old shed's) first stock, so the bay works from the start: litres of
## each base and grams of each stock rack tint.
const STARTER := {"W": 3.0, "B": 2.0, "S": 2.0, "L": 2.0}
const STARTER_TINT := 120.0
const MAX_STOCK := 100000.0
const MAX_RECIPES := 80
const MAX_TINS := 24
## The garage upgrades that kit out the bay (GarageUpgrades.CATALOGUE, category "paint").
const KIT := {"stainless": "paint_stainless", "effects": "paint_effects_rack", "scale": "paint_fine_scale",
	"shaker": "paint_auto_shaker", "meter": "paint_meter", "curved": "paint_curved_panel"}
## XP: a saved mix, a test card, a stirred tin and a target matched.
const XP_MIX := "paint_mix"
const XP_TEST := "test_panel"
const XP_STIR := "paint_stir"
const XP_MATCH := "colour_match"
const XP_TAPE := "masking"
## Actions that need your hands, which you can't do holding a tin or the tape (CoffeeShop
## has the same list for its trays).
const HANDS_NEEDED := CoffeeShop.HANDS_NEEDED


# ---------------------------------------------------------------------------- state

## A new shed's bay: starter stock, nothing mixed yet.
static func empty() -> Dictionary:
	var stock := {}
	for b in STARTER:
		stock[b] = float(STARTER[b])
	for code in PaintMix.TINT_ORDER:
		if str(PaintMix.TINTS[code]["rack"]) == "base":
			stock[code] = STARTER_TINT
	return {"stock": stock, "tins": {}, "recipes": {}, "next": 1, "bench": {"by": 0, "tin": 0, "seq": {}, "tilt": 0.0, "tint": "",
		"recipe": {}, "target": {}, "stir_at": 0.0, "at": "bay", "tare": 0.0, "tare_tin": 0, "pour_n": 0}, "shaker": {"tin": 0, "left": 0.0}, "test": {}, "cups": {}, "held": {},
		"mixed": 0}


## Saved or synced bay made safe to use: anything missing (sheds from before it) gets its default.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
	var bench: Dictionary = empty()["bench"]
	bench.merge(out["bench"], true)
	out["bench"] = bench
	return out


static func _st() -> Dictionary:
	if not (Shed.paint_bay is Dictionary) or not Shed.paint_bay.has("tins"):
		Shed.paint_bay = empty()
	return Shed.paint_bay


static func tins() -> Dictionary:
	return _st()["tins"]


static func recipes() -> Dictionary:
	return _st()["recipes"]


static func bench() -> Dictionary:
	return _st()["bench"]


static func stock() -> Dictionary:
	return _st()["stock"]


static func stock_of(code: String) -> float:
	return float(stock().get(code, 0.0))


static func kit(key: String) -> bool:
	return GarageUpgrades.owned(str(KIT.get(key, "")))


static func level_of(peer: int) -> int:
	if peer == Shed.me():
		return Progress.level()
	return int(Progress.summary(peer).get("level", 1))


static func _next() -> int:
	var s := _st()
	var id := int(s["next"])
	s["next"] = id + 1
	return id


## The tin on the bench's scale, or {}.
static func bench_tin() -> Dictionary:
	return tins().get(int(bench().get("tin", 0)), {})


## Which bench is in use: "bay" (the mixing bay's) or "shop" (the paint shop's compact one).
static func station() -> String:
	return "shop" if str(bench().get("at", "bay")) == "shop" else "bay"


## The bench nearer `p`: the bay's inside the mixing bay, the paint shop's anywhere else.
static func station_near(p: Vector3) -> String:
	return "bay" if in_room(p) else "shop"


## Where the scale in use stands (the tin on it sits here).
static func scale_at(where := "") -> Vector3:
	return SHOP_SCALE_AT if (where if where != "" else station()) == "shop" else SCALE_AT


## What the scale reads for `grams` in the tin on it: the weight since the last tare (Tare
## zeroes it so the next tint can be weighed on its own; the tin's real total is untouched).
static func net_grams(tin: Dictionary, grams: float) -> float:
	var b := bench()
	if tin.is_empty() or int(b.get("tare_tin", 0)) != int(tin.get("id", -1)):
		return grams
	return grams - float(b.get("tare", 0.0))


## Whether the scale's been zeroed with the tin on it now.
static func tared(tin: Dictionary) -> bool:
	return not tin.is_empty() and int(bench().get("tare_tin", 0)) == int(tin.get("id", -1))


## Where a tint's bottle stands on the paint shop bench's little rack (its foot), facing the
## bench (+Z): two shelves of 14 on the back wall.
static func shop_bottle_xf(code: String) -> Transform3D:
	var i := PaintMix.TINT_ORDER.find(code)
	return Transform3D(Basis(), Vector3(SHOP_RACK_X0 + (i % 14) * SHOP_RACK_STEP, float(SHOP_RACK_Y[clampi(i / 14, 0, 1)]), SHOP_RACK_Z))


## Who's at the bench (0: nobody).
static func at_bench() -> int:
	return int(bench().get("by", 0))


## What `peer` is carrying from the bay: {kind: "tin", tin} or {kind: "tape", pattern}, or {}.
static func held(peer: int) -> Dictionary:
	return _st()["held"].get(peer, {})


static func carrying(peer: int) -> bool:
	return not held(peer).is_empty()


static func held_tin(peer: int) -> Dictionary:
	var h := held(peer)
	return tins().get(int(h.get("tin", 0)), {}) if str(h.get("kind", "")) == "tin" else {}


## `peer`'s spray gun cup: {mix (a spec), litres, name}, or {}.
static func cup_of(peer: int) -> Dictionary:
	return _st()["cups"].get(peer, {})


## A tin's paint spec, worked out from what's in it.
static func spec_of(tin: Dictionary) -> Dictionary:
	if tin.is_empty():
		return {}
	var s := PaintMix.spec(tin, str(tin.get("name", "")))
	return s


## The shelf slot a tin's on, or -1.
static func slot_of(tin: Dictionary) -> int:
	return int(tin.get("ref", -1)) if str(tin.get("at", "")) == "shelf" else -1


static func tin_in_slot(slot: int) -> Dictionary:
	for id in tins():
		if str(tins()[id].get("at", "")) == "shelf" and int(tins()[id].get("ref", -1)) == slot:
			return tins()[id]
	return {}


static func free_slot() -> int:
	for i in SHELF_SLOTS:
		if tin_in_slot(i).is_empty():
			return i
	return -1


## The swatch wall's cards, newest first.
static func swatch_order() -> Array:
	var ids: Array = recipes().keys()
	ids.sort_custom(func(a, b): return int(a) > int(b))
	return ids.slice(0, MAX_SWATCHES)


## Where swatch card `i` (in swatch_order) hangs, facing into the room (+X).
static func swatch_xf(i: int) -> Transform3D:
	var col := i % SWATCH_COLS
	var row := i / SWATCH_COLS
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(SWATCH_X, SWATCH_TOP - row * SWATCH_STEP.y, SWATCH_Z0 + col * SWATCH_STEP.x))


## Where shelf slot `i` holds a tin (its foot).
static func slot_xf(i: int) -> Transform3D:
	var row := clampi(i / 4, 0, SHELF_Y.size() - 1)
	var col := i % 4
	return Transform3D(Basis(), Vector3(SHELF_X, float(SHELF_Y[row]), SHELF_Z + (col - 1.5) * 0.3))


## Where a tint's bottle stands on the rack (its foot): the stock rack's two shelves of 8, then
## the effects rack's two shelves of 6 beside it.
static func bottle_xf(code: String) -> Transform3D:
	var i := PaintMix.TINT_ORDER.find(code)
	var row := 0
	var col := 0
	if i < 16:
		row = i / 8
		col = i % 8
	else:
		row = (i - 16) / 6
		col = 8 + (i - 16) % 6
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(RACK_X, float(RACK_Y[row]), RACK_Z0 + col * RACK_STEP))


## The tints on the rack now (the effects rack's once it's bought).
static func rack() -> Array:
	return PaintMix.TINT_ORDER.filter(func(c): return PaintMix.on_rack(str(c), kit("effects")))


static func in_room(at: Vector3) -> bool:
	return ROOM.grow(0.1).has_point(Vector2(at.x, at.z))


# ---------------------------------------------------------------------------- the text

## "Tin: Midnight Blue (metallic), 0.8 l" for the HUD and info panels.
static func tin_text(tin: Dictionary) -> String:
	if tin.is_empty():
		return ""
	var s := spec_of(tin)
	var nm := str(tin.get("name", ""))
	return "%s: %s, %.2f l  ·  %s" % ["Tin" if nm != "" else "Unnamed tin", nm if nm != "" else PaintMix.effect_name(str(s["effect"])).to_lower(),
		float(tin.get("litres", PaintMix.litres_of(tin))), PaintMix.full_code(tin)]


static func stock_text(code: String) -> String:
	if PaintMix.BASES.has(code):
		return "%.2f l" % stock_of(code)
	return "%d g" % roundi(stock_of(code))


static func item_name(code: String) -> String:
	if PaintMix.BASES.has(code):
		return str(PaintMix.BASES[code]["name"])
	return str(PaintMix.TINTS.get(code, {}).get("name", code))


## What a supply costs: a 1 litre tin of base, or a bottle of tint.
static func price(code: String) -> int:
	if PaintMix.BASES.has(code):
		return int(PaintMix.BASES[code]["price"])
	return int(PaintMix.TINTS.get(code, {}).get("price", 0))


## How much a supply order of one brings: a litre, or a bottle's grams.
static func pack(code: String) -> float:
	return 1.0 if PaintMix.BASES.has(code) else PaintMix.BOTTLE_G


## Everything the bay sells, in shop order.
static func supplies() -> Array:
	var out: Array = []
	out.append_array(PaintMix.BASE_ORDER)
	out.append_array(PaintMix.TINT_ORDER)
	return out


## Why `peer` can't use a tint (or base) yet: the level, or the rack it goes on. "" if they can.
static func locked(peer: int, code: String) -> String:
	var lv := level_of(peer)
	var need := int(PaintMix.BASES[code]["level"]) if PaintMix.BASES.has(code) else int(PaintMix.TINTS.get(code, {}).get("level", 1))
	if lv < need:
		return "Level %d" % need
	if PaintMix.TINTS.has(code) and not PaintMix.on_rack(code, kit("effects")):
		return "Effects rack"
	return ""


# ---------------------------------------------------------------------------- rules

static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var b := bench()
	var tin := bench_tin()
	match a:
		"paint_bench":
			if action.get("on", false):
				if at_bench() != 0 and at_bench() != peer:
					return "%s is at the mixing bench." % Shed.crew.get(at_bench(), {}).get("name", "Someone")
				if Shed.held_by(peer) != 0:
					return "Put the part down first."
		"paint_tin_new":
			if at_bench() != peer:
				return "Step up to the mixing bench first."
			if not tin.is_empty():
				return "There's a tin on the scale already."
			var base := str(action.get("base", ""))
			if not PaintMix.BASES.has(base):
				return "There's no base like that."
			var why := locked(peer, base)
			if why != "":
				return "The %s needs %s." % [item_name(base).to_lower(), why.to_lower()]
			if stock_of(base) < 1.0 - 0.001:
				return "No %s left. Order some from the parts computer (Paint supplies)." % item_name(base).to_lower()
			if tins().size() >= MAX_TINS:
				return "Too many tins about: bin some empties first."
		"paint_pour":
			if at_bench() != peer or tin.is_empty():
				return "Put a tin on the scale first."
			var code := str(action.get("tint", ""))
			var why := PaintMix.pour_problem(tin, code)
			if why != "":
				return why
			var lock := locked(peer, code)
			if lock != "":
				return "%s needs %s." % [item_name(code), lock.to_lower()]
			if stock_of(code) <= 0.001:
				return "The %s bottle's empty. Order more (Paint supplies)." % item_name(code).to_lower()
			if float(action.get("g", 0.0)) <= 0.0:
				return "Nothing poured."
		"paint_pour_stop":
			if at_bench() != peer:
				return "Step up to the mixing bench first."
		"paint_stir", "paint_add_base", "paint_tin_empty", "paint_test", "paint_shake", "paint_tin_save", "paint_tare":
			if at_bench() != peer:
				return "Step up to the mixing bench first."
			if tin.is_empty():
				return "There's no tin on the scale."
			match a:
				"paint_add_base":
					if PaintMix.total_grams(tin) + PaintMix.ADD_BASE_G > PaintMix.MAX_TIN_GRAMS:
						return "The tin won't take any more."
					if stock_of(str(tin["base"])) < PaintMix.ADD_BASE_G / 1000.0 - 0.001:
						return "No %s left to add." % item_name(str(tin["base"])).to_lower()
				"paint_test":
					if PaintMix.tint_grams(tin) <= 0.0 and str(tin["base"]) == "L":
						return "That's just lacquer: nothing to see on a card."
					if float(tin.get("stir", 1.0)) < 0.6:
						return "Stir it first: it'd spray blotchy."
				"paint_shake":
					if int(_st()["shaker"].get("tin", 0)) != 0:
						return "The shaker's busy."
				"paint_tin_save":
					var nm := str(action.get("name", "")).strip_edges()
					if nm == "":
						return "Give it a name first."
					if nm.length() > 32:
						return "That name's too long."
					if free_slot() < 0:
						return "The tin shelf's full. Use or bin a tin first."
					if PaintMix.level_needed(tin) > level_of(peer):
						return "You need level %d to mix that." % PaintMix.level_needed(tin)
		"paint_recipe":
			if at_bench() != peer and at_bench() != 0:
				return "%s is at the mixing bench." % Shed.crew.get(at_bench(), {}).get("name", "Someone")
			if PaintMix.parse_code(str(action.get("code", ""))).is_empty():
				return "That recipe card doesn't read."
		"paint_remix":
			if not kit("shaker"):
				return "Remixing a colour in one go needs the automatic shaker (a garage upgrade)."
			if int(_st()["shaker"].get("tin", 0)) != 0:
				return "The shaker's busy."
			var card := PaintMix.parse_code(str(action.get("code", "")))
			if card.is_empty():
				return "That recipe card doesn't read."
			if PaintMix.level_needed(card) > level_of(peer):
				return "You need level %d to mix that." % PaintMix.level_needed(card)
			if str(action.get("name", "")).strip_edges() == "" or str(action.get("name", "")).length() > 32:
				return "It needs a name."
			if tins().size() >= MAX_TINS:
				return "Too many tins about: bin some empties first."
			var base := str(card["base"])
			if stock_of(base) < float(card["base_g"]) / 1000.0 - 0.001:
				return "Not enough %s left. Order some (Paint supplies)." % item_name(base).to_lower()
			for code in card["tints"]:
				if not PaintMix.on_rack(str(code), kit("effects")):
					return "%s goes on the effects rack (a garage upgrade)." % item_name(str(code))
				if stock_of(str(code)) < float(card["tints"][code]) - 0.01:
					return "Not enough %s left for it. Order more (Paint supplies)." % item_name(str(code)).to_lower()
		"paint_target":
			if action.get("meter", false):
				if not kit("meter"):
					return "That needs the colour meter (a garage upgrade)."
				if at_bench() != 0 and at_bench() != peer:
					return "%s is at the mixing bench." % Shed.crew.get(at_bench(), {}).get("name", "Someone")
			elif at_bench() != peer:
				return "Step up to the mixing bench first."
		"paint_buy":
			var code := str(action.get("code", ""))
			var n := int(action.get("n", 1))
			if not supplies().has(code):
				return "There's no paint like that."
			if n < 1 or n > 20:
				return "Order between 1 and 20."
			if Shed.garage_money < price(code) * n:
				return "The garage can't afford it: %s." % TvChannels.money_text(price(code) * n)
			if stock_of(code) + pack(code) * n > MAX_STOCK:
				return "The bay's shelves are full of it."
		"paint_tin_take":
			var t: Dictionary = tins().get(int(action.get("tin", 0)), {})
			if t.is_empty():
				return "That tin has gone."
			if str(t.get("at", "")) != "shelf":
				return "That tin's in use."
			if carrying(peer) or CoffeeShop.carrying(peer) or Shed.held_by(peer) != 0:
				return "Your hands are full."
		"paint_tin_put":
			if held_tin(peer).is_empty():
				return "You're not holding a tin."
			var slot := int(action.get("slot", -1))
			if slot < 0 or slot >= SHELF_SLOTS:
				return "Put it on the tin shelf."
			if not tin_in_slot(slot).is_empty():
				return "There's a tin there."
		"paint_tin_bench":
			if held_tin(peer).is_empty():
				return "You're not holding a tin."
			if not tin.is_empty():
				return "There's a tin on the scale already."
			if at_bench() != 0 and at_bench() != peer:
				return "Someone's at the bench."
		"paint_tin_bin":
			if held_tin(peer).is_empty():
				return "You're not holding a tin."
		"paint_tin_give":
			if held_tin(peer).is_empty():
				return "You're not holding a tin."
			var to := int(action.get("to", 0))
			if not Shed.crew.has(to) or to == peer:
				return "They're not here."
			if carrying(to) or CoffeeShop.carrying(to) or Shed.held_by(to) != 0:
				return "Their hands are full."
		"paint_cup":
			var t := held_tin(peer)
			if t.is_empty():
				return "Hold a tin of paint to fill the gun's cup."
			if float(t.get("litres", 0.0)) <= 0.005:
				return "The tin's empty."
			if str(t.get("name", "")) == "":
				return "Name the tin at the bench first."
			var c := cup_of(peer)
			if not c.is_empty() and str(c.get("code", "")) == str(t.get("code", "")) and float(c.get("litres", 0.0)) >= PaintMix.CUP_LITRES - 0.005:
				return "The cup's full of it already."
		"paint_tape_take":
			if carrying(peer) or CoffeeShop.carrying(peer) or Shed.held_by(peer) != 0:
				return "Your hands are full."
			for p in _st()["held"]:
				if str(_st()["held"][p].get("kind", "")) == "tape":
					return "%s has the masking tape." % Shed.crew.get(int(p), {}).get("name", "Someone")
		"paint_tape_put":
			if str(held(peer).get("kind", "")) != "tape":
				return "You're not holding the tape."
		"paint_tape_pattern":
			if str(held(peer).get("kind", "")) != "tape":
				return "You're not holding the tape."
			if not PaintMix.TAPE_PATTERNS.has(str(action.get("pattern", ""))):
				return "There's no pattern like that."
		"paint_tape":
			if str(held(peer).get("kind", "")) != "tape":
				return "Take the masking tape off its hook by the mixing bay door."
			var it: Dictionary = Shed.items.get(int(action.get("item", 0)), {})
			if it.is_empty():
				return "That part has gone."
			if it["at"] == "held" or it.get("boxed", false):
				return "Put it down (and unpack it) first."
			var pattern := str(held(peer).get("pattern", "stripe"))
			if level_of(peer) < int(PaintMix.PATTERNS[pattern]["level"]):
				return "Masking needs level %d." % int(PaintMix.PATTERNS[pattern]["level"])
			if not it.has("paint_quality") or it.get("primer_top", false):
				return "Paint it first: the tape keeps its colour where the stripe goes."
			if it.get("tape") is Dictionary:
				return "It's taped already. Spray it, or peel the tape off."
		"paint_peel":
			var it: Dictionary = Shed.items.get(int(action.get("item", 0)), {})
			if it.is_empty() or not (it.get("tape") is Dictionary):
				return "There's no tape on it."
		"paint_pin":
			if not recipes().has(int(action.get("recipe", 0))):
				return "That card's gone."
		_:
			return "Unknown action."
	return ""


## Host: does a checked "paint_*" request. Returns what to tell the player who asked ("" for
## nothing).
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	var b := bench()
	var tin := bench_tin()
	match a:
		"paint_bench":
			if action.get("on", false):
				b["by"] = peer
				b["seq"][peer] = int(action.get("seq", 0))
				b["at"] = "shop" if str(action.get("at", "bay")) == "shop" else "bay"
				b["tilt"] = 0.0
				b["tint"] = ""
				return ""
			if at_bench() == peer:
				b["by"] = 0
				b["tilt"] = 0.0
				b["tint"] = ""
			return ""
		"paint_tin_new":
			var base := str(action["base"])
			stock()[base] = stock_of(base) - 1.0
			var t := PaintMix.new_tin(base)
			var id := _next()
			t["id"] = id
			t["name"] = ""
			t["at"] = "bench"
			t["ref"] = 0
			t["by"] = str(Shed.crew.get(peer, {}).get("name", "Someone"))
			_refresh(t)
			tins()[id] = t
			b["tin"] = id
			return "A litre of %s on the scale." % item_name(base).to_lower()
		"paint_pour":
			var code := str(action["tint"])
			var g := minf(clampf(float(action.get("g", 0.0)), 0.0, 60.0), stock_of(code))
			g = minf(g, PaintMix.MAX_TIN_GRAMS - PaintMix.total_grams(tin))
			stock()[code] = maxf(0.0, stock_of(code) - g)
			var tints: Dictionary = tin["tints"]
			tints[code] = float(tints.get(code, 0.0)) + g
			tin["stir"] = PaintMix.unstir(float(tin.get("stir", 1.0)), g, PaintMix.total_grams(tin))
			b["tilt"] = clampf(float(action.get("tilt", 0.0)), 0.0, 1.0)
			b["tint"] = code
			b["pour_n"] = int(b.get("pour_n", 0)) + 1
			_seq(peer, action)
			_refresh(tin)
			return ""
		"paint_pour_stop":
			# The bottle goes back on the rack (everyone else stops drawing it over the tin).
			b["tilt"] = 0.0
			b["tint"] = ""
			return ""
		"paint_tare":
			b["tare"] = PaintMix.total_grams(tin)
			b["tare_tin"] = int(tin["id"])
			return ""
		"paint_stir":
			var was := float(tin.get("stir", 1.0))
			tin["stir"] = clampf(was + clampf(float(action.get("amount", 0.0)), 0.0, 0.5), 0.0, 1.0)
			b["stir_at"] = float(b.get("stir_at", 0.0)) + clampf(float(action.get("amount", 0.0)), 0.0, 0.5) * 20.0
			_seq(peer, action)
			_refresh(tin)
			if was < 0.98 and float(tin["stir"]) >= 0.98 and PaintMix.tint_grams(tin) > 0.0:
				Shed._xp(peer, XP_STIR, 1.0, "tin:%d" % int(tin["id"]))
				return "Stirred to an even mix."
			return ""
		"paint_add_base":
			var base := str(tin["base"])
			stock()[base] = stock_of(base) - PaintMix.ADD_BASE_G / 1000.0
			tin["base_g"] = float(tin["base_g"]) + PaintMix.ADD_BASE_G
			tin["stir"] = PaintMix.unstir(float(tin.get("stir", 1.0)), PaintMix.ADD_BASE_G, PaintMix.total_grams(tin))
			_refresh(tin)
			return "Added %d g more %s to bring it back. Stir it in." % [roundi(PaintMix.ADD_BASE_G), item_name(base).to_lower()]
		"paint_tin_empty":
			tins().erase(int(tin["id"]))
			b["tin"] = 0
			return "Tipped the tin away."
		"paint_tin_save":
			return _save_tin(peer, tin, str(action["name"]).strip_edges())
		"paint_test":
			return _test_card(peer, tin)
		"paint_shake":
			var sh: Dictionary = _st()["shaker"]
			sh["tin"] = int(tin["id"])
			sh["left"] = AUTO_SHAKE_TIME if kit("shaker") else SHAKE_TIME
			tin["at"] = "shaker"
			b["tin"] = 0
			return "In the shaker: %d seconds." % roundi(float(sh["left"]))
		"paint_remix":
			var card := PaintMix.parse_code(str(action["code"]))
			var base := str(card["base"])
			stock()[base] = stock_of(base) - float(card["base_g"]) / 1000.0
			for code in card["tints"]:
				stock()[str(code)] = maxf(0.0, stock_of(str(code)) - float(card["tints"][code]))
			var t := card
			var id := _next()
			t["id"] = id
			t["name"] = str(action["name"]).strip_edges()
			t["at"] = "shaker"
			t["ref"] = 0
			t["stir"] = 0.0
			t["by"] = str(Shed.crew.get(peer, {}).get("name", "Someone"))
			_refresh(t)
			tins()[id] = t
			_st()["shaker"] = {"tin": id, "left": AUTO_SHAKE_TIME}
			_st()["mixed"] = int(_st()["mixed"]) + 1
			return "Remixing %s in the automatic shaker: it'll be on the tin shelf in %d seconds." % [t["name"], roundi(AUTO_SHAKE_TIME)]
		"paint_recipe":
			var card := PaintMix.parse_code(str(action["code"]))
			b["recipe"] = {"name": str(action.get("name", "Recipe")), "code": str(action["code"]), "tin": card,
				"color": PaintMix.spec(card)["color"]}
			# The recipe's colour is what to match, too.
			b["target"] = {"name": str(action.get("name", "Recipe")), "color": PaintMix.spec(card)["color"],
				"effect": str(PaintMix.spec(card)["effect"])}
			return "Recipe card on the bench: %s." % str(action.get("name", "Recipe"))
		"paint_target":
			if action.get("clear", false):
				b["target"] = {}
				b["recipe"] = {}
				return "Recipe card and target put away."
			var c = action.get("color")
			if c is Color:
				b["target"] = {"name": str(action.get("name", "Target")), "color": c, "effect": str(action.get("effect", "solid")),
					"job": int(action.get("job", 0))}
				b["recipe"] = {}
			return ""
		"paint_buy":
			var code := str(action["code"])
			var n := int(action.get("n", 1))
			if not Shed.charge_garage(price(code) * n, "Paint supplies: %s" % item_name(code)):
				return "The garage can't afford it."
			stock()[code] = stock_of(code) + pack(code) * n
			return "Bought %d %s for the mixing bay: %s." % [n, ("tin%s of " % ("" if n == 1 else "s")) + item_name(code).to_lower()
				if PaintMix.BASES.has(code) else ("bottle%s of " % ("" if n == 1 else "s")) + item_name(code).to_lower(),
				TvChannels.money_text(price(code) * n)]
		"paint_tin_take":
			var t: Dictionary = tins()[int(action["tin"])]
			t["at"] = "held"
			t["ref"] = peer
			_st()["held"][peer] = {"kind": "tin", "tin": int(t["id"])}
			return ""
		"paint_tin_put":
			var t := held_tin(peer)
			t["at"] = "shelf"
			t["ref"] = int(action["slot"])
			_st()["held"].erase(peer)
			return ""
		"paint_tin_bench":
			var t := held_tin(peer)
			t["at"] = "bench"
			t["ref"] = 0
			_st()["held"].erase(peer)
			b["tin"] = int(t["id"])
			if action.has("at"):
				b["at"] = "shop" if str(action["at"]) == "shop" else "bay"
			return "On the scale: %s." % str(t.get("name", "the tin"))
		"paint_tin_bin":
			var t := held_tin(peer)
			tins().erase(int(t["id"]))
			_st()["held"].erase(peer)
			return "Binned the tin."
		"paint_tin_give":
			var t := held_tin(peer)
			var to := int(action["to"])
			t["ref"] = to
			_st()["held"].erase(peer)
			_st()["held"][to] = {"kind": "tin", "tin": int(t["id"])}
			Shed._tell(to, "%s hands you a tin of %s." % [Shed.crew.get(peer, {}).get("name", "Someone"), str(t.get("name", "paint"))], true)
			return "You hand %s the tin." % Shed.crew.get(to, {}).get("name", "them")
		"paint_cup":
			var t := held_tin(peer)
			var c := cup_of(peer)
			var have := float(c.get("litres", 0.0)) if str(c.get("code", "")) == str(t.get("code", "")) else 0.0
			var pour := minf(PaintMix.CUP_LITRES - have, float(t["litres"]))
			t["litres"] = maxf(0.0, float(t["litres"]) - pour)
			_st()["cups"][peer] = {"mix": spec_of(t), "litres": have + pour, "name": str(t.get("name", "")), "code": str(t.get("code", ""))}
			return "Spray gun's cup filled with %s (%.2f l). Pick it with R on the spray gun." % [str(t.get("name", "")), have + pour]
		"paint_tape_take":
			_st()["held"][peer] = {"kind": "tape", "pattern": "stripe"}
			return "Masking tape. R picks the pattern; hold left mouse on a painted part to tape it."
		"paint_tape_put":
			_st()["held"].erase(peer)
			return ""
		"paint_tape_pattern":
			_st()["held"][peer]["pattern"] = str(action["pattern"])
			return ""
		"paint_tape":
			var it: Dictionary = Shed.items[int(action["item"])]
			var pattern := str(held(peer).get("pattern", "stripe"))
			it["tape"] = {"pattern": pattern, "q": clampf(float(action.get("quality", 1.0)), 0.3, 1.0)}
			Shed._xp(peer, XP_TAPE, 0.5, "item:%d" % int(action["item"]))
			return "Taped a %s on the %s. Now spray the second colour over it." % [str(PaintMix.PATTERNS[pattern]["name"]).to_lower(),
				Shed.item_title(int(action["item"]))]
		"paint_peel":
			var it: Dictionary = Shed.items[int(action["item"])]
			it.erase("tape")
			return "Peeled the tape off: %s." % ("a crisp line" if it.get("mask") is Dictionary else "nothing sprayed over it")
		"paint_pin":
			return _pin(peer, recipes()[int(action["recipe"])])
	return ""


static func _seq(peer: int, action: Dictionary) -> void:
	if action.has("seq"):
		bench()["seq"][peer] = maxi(int(bench()["seq"].get(peer, 0)), int(action["seq"]))


## Host: a tin's code, spec and litres brought up to date with what's in it.
static func _refresh(tin: Dictionary) -> void:
	tin["code"] = PaintMix.full_code(tin)
	tin["mix"] = spec_of(tin)
	if str(tin.get("at", "")) == "bench" or not tin.has("litres"):
		tin["litres"] = PaintMix.litres_of(tin)


## Host: the tin on the bench named and put on the shelf, its recipe on the swatch wall.
static func _save_tin(peer: int, tin: Dictionary, tin_name: String) -> String:
	var b := bench()
	tin["name"] = tin_name
	_refresh(tin)
	var slot := free_slot()
	tin["at"] = "shelf"
	tin["ref"] = slot
	b["tin"] = 0
	var s: Dictionary = tin["mix"]
	# A recipe the wall already has under the same name and code isn't added twice.
	var rid := 0
	for id in recipes():
		if str(recipes()[id]["name"]) == tin_name and str(recipes()[id]["code"]) == str(tin["code"]):
			rid = int(id)
	if rid == 0:
		rid = _next()
		recipes()[rid] = {"id": rid, "name": tin_name, "code": str(tin["code"]), "mix": s, "by": str(Shed.crew.get(peer, {}).get("name", "Someone"))}
		while recipes().size() > MAX_RECIPES:
			var oldest := int(recipes().keys().min())
			recipes().erase(oldest)
	_st()["mixed"] = int(_st()["mixed"]) + 1
	# How well it was done: stirred, close to the recipe card, close to the target.
	var q := 0.5 + 0.5 * float(tin.get("stir", 1.0))
	var notes: Array[String] = []
	var card: Dictionary = b.get("recipe", {})
	if not card.is_empty():
		var acc := PaintMix.recipe_accuracy(tin, card.get("tin", {}))
		q *= 0.6 + 0.4 * acc
		notes.append("%d%% to the recipe" % roundi(acc * 100.0))
	var target: Dictionary = b.get("target", {})
	if not target.is_empty() and target.get("color") is Color:
		var m := PaintMix.match_of(s["color"], target["color"], str(s["effect"]), str(target.get("effect", "")))
		notes.append("a %s match" % PaintMix.match_text(m))
		if m >= PaintMix.GOOD_MATCH:
			Shed._xp(peer, XP_MATCH, 1.0 + (m - PaintMix.GOOD_MATCH) * 10.0, "tin:%d" % int(tin["id"]))
	Shed._xp(peer, XP_MIX, q, "tin:%d" % int(tin["id"]))
	return "%s saved: on the tin shelf and the swatch wall%s." % [tin_name, "" if notes.is_empty() else " (%s)" % ", ".join(notes)]


## Host: a test card sprayed from the bench tin, on the spray-out stand (and in the daylight
## booth), a little paint from the tin.
static func _test_card(peer: int, tin: Dictionary) -> String:
	var s := spec_of(tin)
	_st()["test"] = {"mix": s, "name": str(tin.get("name", "")), "by": str(Shed.crew.get(peer, {}).get("name", "Someone")),
		"n": int(_st()["test"].get("n", 0)) + 1}
	tin["base_g"] = maxf(1.0, float(tin["base_g"]) - PaintMix.TEST_CARD_G)
	_refresh(tin)
	Shed._xp(peer, XP_TEST, 1.0, "tin:%d:%d" % [int(tin["id"]), int(_st()["test"]["n"])])
	return "Test card sprayed: it's on the spray-out stand."


## Host: a recipe card pinned to the whiteboard, as a line of text with its code.
static func _pin(peer: int, r: Dictionary) -> String:
	var n := 0
	for m in Shed.board.get("marks", []):
		if str(m.get("text", "")).begins_with("PAINT:"):
			n += 1
	var op := {"a": "board_text", "id": 900000000 + Shed._rng.randi() % 99999999, "c": 0, "s": BoardData.TEXT_SIZES[0],
		"at": Vector2(30.0, 30.0 + (n % 12) * 40.0), "text": ("PAINT: %s  %s" % [r["name"], r["code"]]).left(BoardData.MAX_TEXT)}
	Shed._board_apply(peer, op)
	return "Pinned the %s card to the whiteboard." % str(r["name"])


## Host: the paint bay's own clock: the shaker.
static func process(delta: float) -> void:
	var sh: Dictionary = _st()["shaker"]
	var id := int(sh.get("tin", 0))
	if id == 0:
		return
	sh["left"] = float(sh["left"]) - delta
	if float(sh["left"]) > 0.0:
		return
	sh["tin"] = 0
	sh["left"] = 0.0
	var t: Dictionary = tins().get(id, {})
	if t.is_empty():
		return
	t["stir"] = 1.0
	t["at"] = ""
	_refresh(t)
	# A named tin (remixed from a card) goes on the shelf; one from the bench back on the scale.
	var slot := free_slot()
	if (str(t.get("name", "")) != "" or int(bench().get("tin", 0)) != 0) and slot >= 0:
		t["at"] = "shelf"
		t["ref"] = slot
	elif int(bench().get("tin", 0)) == 0:
		t["at"] = "bench"
		t["ref"] = 0
		bench()["tin"] = id
	else:
		tins().erase(id)   # nowhere to put it
	Shed._mark_dirty()
	Shed.changed.emit()


## Host: `peer` has gone: what they were carrying goes back (tins to the shelf, the tape to its
## hook), and they're away from the bench.
static func put_back(peer: int) -> void:
	var h := held(peer)
	if str(h.get("kind", "")) == "tin":
		var t: Dictionary = tins().get(int(h["tin"]), {})
		if not t.is_empty():
			var slot := free_slot()
			if slot >= 0:
				t["at"] = "shelf"
				t["ref"] = slot
			else:
				tins().erase(int(h["tin"]))
	_st()["held"].erase(peer)
	if at_bench() == peer:
		bench()["by"] = 0
		bench()["tilt"] = 0.0


## Host: after a save is opened nobody holds anything or stands at the bench, and cups are clean.
static func after_load() -> void:
	for p in _st()["held"].keys():
		put_back(int(p))
	_st()["held"] = {}
	_st()["cups"] = {}
	bench()["by"] = 0
	bench()["seq"] = {}
	for id in tins().keys():
		var t: Dictionary = tins()[id]
		if not (t.get("tints") is Dictionary):
			tins().erase(id)
			continue
		if str(t.get("at", "")) == "held":
			var slot := free_slot()
			t["at"] = "shelf"
			t["ref"] = slot
	# A tin left in the shaker comes out mixed.
	var sh: Dictionary = _st()["shaker"]
	if int(sh.get("tin", 0)) != 0:
		sh["left"] = 0.01


# ---------------------------------------------------------------------------- spraying from the cup

## What a part's mixed paint adds to its redraw signature (Workshop): the recipe, coats, a mask,
## tape and the lacquer's sheen.
static func paint_sig(it: Dictionary) -> String:
	var out := ""
	if it.get("mix") is Dictionary:
		out += "|mix %s %d %.2f" % [str(it["mix"].get("code", "")), int(it.get("mix_coats", 1)), float(it.get("paint_quality", 1.0))]
	if it.get("mask") is Dictionary:
		out += "|mask %s %s" % [str(it["mask"].get("pattern", "")), str(it["mask"].get("color", ""))]
	if it.get("tape") is Dictionary:
		out += "|tape %s" % str(it["tape"].get("pattern", ""))
	if float(it.get("flat", 0.0)) > 0.0:
		out += "|flat %.2f" % float(it["flat"])
	return out


## The wet look of a coat from the local player's cup on `it`, for the spray job to draw: its
## colour after this coat, roughness and metal. {} if the cup's empty.
static func cup_look(it: Dictionary) -> Dictionary:
	var c := cup_of(Shed.me())
	if c.is_empty() or not (c.get("mix") is Dictionary):
		return {}
	var s: Dictionary = c["mix"]
	if str(s.get("effect", "")) == "lacquer":
		var old: Color = it.get("color", Color(0.5, 0.5, 0.5))
		return {"color": old, "rough": lerpf(0.04, 0.8, clampf(float(s.get("flat", 0.0)) / 0.4, 0.0, 1.0)), "metal": 0.0}
	var same: bool = it.get("mix") is Dictionary and str(it["mix"].get("code", "")) == str(s.get("code", "")) and not it.get("primer_top", false)
	var coats := int(it.get("mix_coats", 0)) + 1 if same else 1
	var under: Color = Shed.PRIMER_COLOR if it.get("primer_top", false) else it.get("color", Color(0.5, 0.5, 0.5))
	if same:
		under = it.get("mix_under", under)
	return {"color": PaintMix.sprayed_color(s, coats, under), "rough": float(s.get("rough", 0.15)), "metal": float(s.get("metal", 0.05)) * 0.8}


## Host: what spraying a coat from the cup over `it` uses, and whether there's enough: litres,
## or -1 if the cup's short.
static func cup_use(peer: int, it: Dictionary, waste: float) -> float:
	var need := PaintMix.litres_for(PartsDB.kind_of(str(it["part"]))) * (1.0 + clampf(waste, 0.0, 1.0))
	return need if float(cup_of(peer).get("litres", 0.0)) + 0.001 >= need * 0.5 else -1.0


## Host: a coat from `peer`'s cup goes on `it` (checked): the colour, its coats (a second coat
## of the same paint adds to the first), tape turned into a masked stripe, and the cup used.
## Returns the paint quality factor for the coats (see PaintMix.coats_factor).
static func spray_from_cup(peer: int, it: Dictionary, waste: float, fade := "") -> float:
	var c := cup_of(peer)
	var s: Dictionary = (c["mix"] as Dictionary).duplicate(true)
	c["litres"] = maxf(0.0, float(c["litres"]) - cup_use(peer, it, waste))
	if str(s.get("effect", "")) == "lacquer":
		# Lacquer from the cup is a clear top coat: the colour stays, the sheen changes.
		it["flat"] = float(s.get("flat", 0.0))
		return 1.0
	var same: bool = it.get("mix") is Dictionary and str(it["mix"].get("code", "")) == str(s.get("code", "")) \
		and not it.get("primer_top", false) and fade == ""
	var coats := int(it.get("mix_coats", 0)) + 1 if same else 1
	if not same:
		it["mix_under"] = Shed.PRIMER_COLOR if it.get("primer_top", false) else it.get("color", Color(0.5, 0.5, 0.5))
		var tape = it.get("tape")
		if tape is Dictionary:
			# Sprayed over tape: the colour under it stays where the stripe goes.
			it["mask"] = {"pattern": str(tape["pattern"]), "color": it.get("color", Color.WHITE), "q": float(tape.get("q", 1.0)),
				"mix": it.get("mix", {})}
		elif fade != "":
			it["mask"] = {"pattern": fade, "color": it.get("color", Color.WHITE), "q": 1.0, "mix": it.get("mix", {})}
		elif not it.get("primer_top", false):
			it.erase("mask")
	it["mix"] = s
	it["mix_coats"] = mini(coats, 8)
	it["color"] = PaintMix.sprayed_color(s, coats, it.get("mix_under", Color(0.5, 0.5, 0.5)))
	it["finish"] = PaintMix.finish_of(s)
	return PaintMix.coats_factor(s, coats) * (0.7 + 0.3 * float(s.get("stir", 1.0)))
