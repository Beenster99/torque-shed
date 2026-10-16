class_name PaintMix
extends RefCounted
## The paint mixing bay's maths: what a tin of paint looks like from the base and the tints
## poured into it, how close it is to a colour it should match, the short recipe codes, the
## finishes and effects, the coats each needs, and the materials that show them on a part.
##
## A tin is a base (white, black, metallic silver, clear for candies, or clear lacquer for
## flattener) plus up to MAX_TINTS tints by weight. The colour is worked out like real pigment:
## each tint pulls the mix towards its own colour by its weight times its tinting strength, as
## a weighted geometric mean of the reflectances (blue and yellow make green, and a strong tint
## like phthalo blue goes a long way), so the base sets how light the colour can go. Effect
## tints add metal flake, pearl, big flake or a colour-shift pigment; a clear base with dyes in
## it is a candy, a coloured clear that darkens with each coat over its base coat.
##
## A tin, here, is a Dictionary: {base: base code, base_g: grams of base, tints: {code: grams},
## stir: 0..1}. spec() turns it into the paint's description (a "spec"), which is what is kept
## on a part once it's sprayed: {name, code, effect, color, metal, rough, pearl, pearl_tint,
## flake, flake_color, holo, flip, flip_a, flip_b, dye, depth, flat, need, stir}.
## Everything here is static and pure: the shared state lives in PaintBay (Shed.paint_bay).

const TIN_GRAMS := 1000.0       # a 1 litre tin's worth of base
const MAX_TIN_GRAMS := 2000.0   # with base added to bring an over-poured mix back
const MAX_TINTS := 5
const ADD_BASE_G := 250.0       # each "add base" pours in this much more
const GRAMS_PER_LITRE := 1000.0

## The bases: code -> {name, color (sRGB), opaque, metal, price (a 1 litre tin), level}.
const BASES := {
	"W": {"name": "White base", "color": Color(0.95, 0.95, 0.94), "opaque": true, "metal": 0.0, "price": 18, "level": 1},
	"B": {"name": "Black base", "color": Color(0.025, 0.025, 0.03), "opaque": true, "metal": 0.0, "price": 18, "level": 1},
	"S": {"name": "Metallic silver base", "color": Color(0.72, 0.73, 0.75), "opaque": true, "metal": 0.8, "price": 28, "level": 1},
	"C": {"name": "Clear base (candy)", "color": Color(0.9, 0.9, 0.9), "opaque": false, "metal": 0.0, "price": 24, "level": 8},
	"L": {"name": "Clear lacquer", "color": Color(0.9, 0.9, 0.9), "opaque": false, "metal": 0.0, "price": 22, "level": 1},
}
const BASE_ORDER: Array[String] = ["W", "B", "S", "C", "L"]

## The tints: code -> {name, color (sRGB), k (tinting strength), kind, rack ("base": the stock
## rack, "plus": the effects rack upgrade), level, price (a BOTTLE_G bottle)}. Kinds: "tint"
## (a solid pigment), "alu" (fine aluminium: metallic), "sparkle" (coarse aluminium), "pearl",
## "candy" (a dye for the clear base), "flake" (big metal flake), "chameleon" (colour shift,
## with flip colours a, b), "flattener" (in lacquer: satin and matt).
const TINTS := {
	"LY": {"name": "Lemon yellow", "color": Color(0.98, 0.88, 0.1), "k": 14.0, "kind": "tint", "rack": "base", "level": 1, "price": 14},
	"YO": {"name": "Yellow oxide", "color": Color(0.8, 0.58, 0.18), "k": 8.0, "kind": "tint", "rack": "base", "level": 1, "price": 12},
	"OR": {"name": "Orange", "color": Color(0.98, 0.45, 0.05), "k": 16.0, "kind": "tint", "rack": "base", "level": 1, "price": 15},
	"SC": {"name": "Scarlet", "color": Color(0.88, 0.1, 0.08), "k": 22.0, "kind": "tint", "rack": "base", "level": 1, "price": 16},
	"OX": {"name": "Oxide red", "color": Color(0.55, 0.15, 0.1), "k": 9.0, "kind": "tint", "rack": "base", "level": 1, "price": 12},
	"MG": {"name": "Magenta", "color": Color(0.75, 0.05, 0.45), "k": 18.0, "kind": "tint", "rack": "base", "level": 1, "price": 16},
	"VI": {"name": "Violet", "color": Color(0.35, 0.1, 0.6), "k": 12.0, "kind": "tint", "rack": "base", "level": 1, "price": 16},
	"UB": {"name": "Ultramarine blue", "color": Color(0.12, 0.15, 0.7), "k": 16.0, "kind": "tint", "rack": "base", "level": 1, "price": 15},
	"PB": {"name": "Phthalo blue", "color": Color(0.02, 0.2, 0.55), "k": 20.0, "kind": "tint", "rack": "base", "level": 1, "price": 18},
	"PG": {"name": "Phthalo green", "color": Color(0.0, 0.42, 0.3), "k": 26.0, "kind": "tint", "rack": "base", "level": 1, "price": 18},
	"BR": {"name": "Oxide brown", "color": Color(0.32, 0.2, 0.1), "k": 7.0, "kind": "tint", "rack": "base", "level": 1, "price": 12},
	"BK": {"name": "Jet black", "color": Color(0.02, 0.02, 0.025), "k": 25.0, "kind": "tint", "rack": "base", "level": 1, "price": 12},
	"WH": {"name": "Titanium white", "color": Color(0.97, 0.97, 0.96), "k": 4.0, "kind": "tint", "rack": "base", "level": 1, "price": 12},
	"AL": {"name": "Fine aluminium", "color": Color(0.78, 0.79, 0.8), "k": 3.0, "kind": "alu", "rack": "base", "level": 1, "price": 22},
	"AS": {"name": "Sparkle aluminium", "color": Color(0.82, 0.83, 0.85), "k": 2.0, "kind": "sparkle", "rack": "base", "level": 1, "price": 24},
	"FL": {"name": "Flattener", "color": Color(0.92, 0.92, 0.92), "k": 0.0, "kind": "flattener", "rack": "base", "level": 1, "price": 10},
	"PW": {"name": "Pearl white", "color": Color(0.95, 0.95, 0.97), "k": 0.6, "kind": "pearl", "rack": "plus", "level": 5, "price": 34,
		"pearl": Color(0.85, 0.9, 1.0)},
	"PU": {"name": "Pearl blue", "color": Color(0.7, 0.8, 1.0), "k": 0.8, "kind": "pearl", "rack": "plus", "level": 5, "price": 36,
		"pearl": Color(0.3, 0.55, 1.0)},
	"PO": {"name": "Pearl gold", "color": Color(0.95, 0.82, 0.5), "k": 0.8, "kind": "pearl", "rack": "plus", "level": 5, "price": 36,
		"pearl": Color(1.0, 0.75, 0.25)},
	"CR": {"name": "Candy red", "color": Color(0.75, 0.02, 0.05), "k": 30.0, "kind": "candy", "rack": "plus", "level": 8, "price": 38},
	"CB": {"name": "Candy blue", "color": Color(0.03, 0.15, 0.75), "k": 30.0, "kind": "candy", "rack": "plus", "level": 8, "price": 38},
	"CG": {"name": "Candy green", "color": Color(0.1, 0.65, 0.08), "k": 30.0, "kind": "candy", "rack": "plus", "level": 8, "price": 38},
	"FS": {"name": "Silver flake", "color": Color(0.86, 0.87, 0.9), "k": 0.3, "kind": "flake", "rack": "plus", "level": 10, "price": 42},
	"FG": {"name": "Gold flake", "color": Color(0.95, 0.75, 0.3), "k": 0.3, "kind": "flake", "rack": "plus", "level": 10, "price": 46},
	"FH": {"name": "Holo flake", "color": Color(0.85, 0.85, 0.95), "k": 0.3, "kind": "flake", "rack": "plus", "level": 10, "price": 52, "holo": true},
	"XP": {"name": "Chameleon purple-green", "color": Color(0.45, 0.1, 0.6), "k": 15.0, "kind": "chameleon", "rack": "plus", "level": 15, "price": 60,
		"a": Color(0.05, 0.6, 0.3), "b": Color(0.1, 0.3, 0.75)},
	"XB": {"name": "Chameleon blue-gold", "color": Color(0.1, 0.25, 0.75), "k": 15.0, "kind": "chameleon", "rack": "plus", "level": 15, "price": 60,
		"a": Color(0.85, 0.65, 0.15), "b": Color(0.6, 0.1, 0.4)},
	"XR": {"name": "Chameleon red-gold", "color": Color(0.7, 0.05, 0.1), "k": 15.0, "kind": "chameleon", "rack": "plus", "level": 15, "price": 60,
		"a": Color(0.95, 0.7, 0.1), "b": Color(0.3, 0.6, 0.2)},
}
## The rack's order: the stock rack's 16 bottles, then the effects rack's 12.
const TINT_ORDER: Array[String] = ["LY", "YO", "OR", "SC", "OX", "MG", "VI", "UB", "PB", "PG", "BR", "BK", "WH", "AL", "AS", "FL",
	"PW", "PU", "PO", "CR", "CB", "CG", "FS", "FG", "FH", "XP", "XB", "XR"]
const BOTTLE_G := 250.0

## The finishes and effects: what each looks like, the level it unlocks at, how many coats it
## needs, and what it adds to a bike's price as part of its paint (see uniqueness_bonus).
const EFFECTS := {
	"solid": {"name": "Solid", "level": 1, "need": 2, "value": 0.0, "letter": "S"},
	"metallic": {"name": "Metallic", "level": 1, "need": 2, "value": 0.02, "letter": "M"},
	"pearl": {"name": "Pearl", "level": 5, "need": 3, "value": 0.04, "letter": "P"},
	"candy": {"name": "Candy", "level": 8, "need": 3, "value": 0.06, "letter": "C"},
	"flake": {"name": "Flake", "level": 10, "need": 3, "value": 0.07, "letter": "F"},
	"chameleon": {"name": "Chameleon", "level": 15, "need": 3, "value": 0.1, "letter": "X"},
	"lacquer": {"name": "Lacquer", "level": 1, "need": 1, "value": 0.0, "letter": "L"},
}
const EFFECT_ORDER: Array[String] = ["solid", "metallic", "pearl", "candy", "flake", "chameleon"]
## Candy coats: the ideal is 3 or 4; it darkens with each one.
const CANDY_BEST := Vector2i(3, 4)
## Flattener in the lacquer: gloss, satin and matt (share of the lacquer's weight).
const SHEENS := {"gloss": 0.0, "satin": 0.15, "matt": 0.4}
## Masking and fades: the patterns a second colour can go on in, and the level each needs. The
## masked colour (under the tape, or the first colour under a fade) shows where the pattern is.
const PATTERNS := {
	"stripe": {"name": "Centre stripe", "level": 3, "tape": true},
	"twin": {"name": "Twin stripes", "level": 3, "tape": true},
	"pin": {"name": "Pinstripe", "level": 3, "tape": true},
	"two_tone": {"name": "Two-tone (top)", "level": 3, "tape": true},
	"fade_top": {"name": "Fade (top down)", "level": 12, "tape": false},
	"fade_rear": {"name": "Fade (front to back)", "level": 12, "tape": false},
}
const PATTERN_IDS := {"stripe": 1, "twin": 2, "pin": 3, "two_tone": 4, "fade_top": 5, "fade_rear": 6}
const TAPE_PATTERNS: Array[String] = ["stripe", "twin", "pin", "two_tone"]
const FADE_PATTERNS: Array[String] = ["fade_top", "fade_rear"]
const TAPE_COLOR := Color(0.18, 0.42, 0.85)
const TAPE_CREAM := Color(0.86, 0.79, 0.58)   # the cream sort, on a part too near the blue for that to show
## Paint a coat takes on each kind of part, in litres (a litre does about a tank, the guards and
## the side panels in two coats; a whole bike needs about two litres).
const LITRES := {"tank": 0.12, "fairing": 0.2, "side_panels": 0.07, "front_mudguard": 0.05, "guards": 0.06, "tail": 0.08,
	"frame": 0.25, "number_boards": 0.04, "top_box": 0.08, "panniers": 0.12, "headlight": 0.03, "wheel": 0.08, "fork": 0.06,
	"engine": 0.15, "shock": 0.04, "handlebars": 0.03, "saddle": 0.06, "mirrors": 0.02}
const DEFAULT_LITRES := 0.04
const CUP_LITRES := 0.6          # the spray gun's cup
const TEST_CARD_G := 15.0        # paint a test card takes from the tin
## Matching: a target is matched at this much, and below it a match job pays less.
const GOOD_MATCH := 0.95
const EFFECT_MISS := 0.12        # off the match for the wrong effect (solid for a metallic)

## The manufacturer colours (data/paint_colours.json), read once: [{id, brand, name, rgb, effect, finish, code}].
static var _library: Array = []


# ---------------------------------------------------------------------------- colour maths

static func to_linear(c: Color) -> Vector3:
	return Vector3(_lin(c.r), _lin(c.g), _lin(c.b))


static func to_srgb(v: Vector3) -> Color:
	return Color(_srgb(v.x), _srgb(v.y), _srgb(v.z))


static func _lin(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)


static func _srgb(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * 12.92 if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055


## CIE L*a*b* (D65) of an sRGB colour.
static func to_lab(c: Color) -> Vector3:
	var l := to_linear(c)
	var x := (0.4124 * l.x + 0.3576 * l.y + 0.1805 * l.z) / 0.95047
	var y := 0.2126 * l.x + 0.7152 * l.y + 0.0722 * l.z
	var z := (0.0193 * l.x + 0.1192 * l.y + 0.9505 * l.z) / 1.08883
	var fx := _lab_f(x)
	var fy := _lab_f(y)
	var fz := _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## How far apart two colours look (CIE76 delta E: about 2 is just noticeable, 100 black to white).
static func delta_e(a: Color, b: Color) -> float:
	return to_lab(a).distance_to(to_lab(b))


## How close a colour is to a target, 0..1 (1 is spot on; GOOD_MATCH and over is a match), less
## for the wrong effect when both are given.
static func match_of(have: Color, want: Color, have_effect := "", want_effect := "") -> float:
	var m := clampf(1.0 - delta_e(have, want) / 100.0, 0.0, 1.0)
	if have_effect != "" and want_effect != "" and _effect_family(have_effect) != _effect_family(want_effect):
		m = maxf(0.0, m - EFFECT_MISS)
	return m


static func _effect_family(e: String) -> String:
	return "solid" if e in ["solid", "lacquer"] else e


## "93.4%" for a match.
static func match_text(m: float) -> String:
	return "%.1f%%" % (m * 100.0)


# ---------------------------------------------------------------------------- tins

static func new_tin(base: String) -> Dictionary:
	return {"base": base if BASES.has(base) else "W", "base_g": TIN_GRAMS, "tints": {}, "stir": 1.0}


static func tint_grams(tin: Dictionary) -> float:
	var g := 0.0
	for k in tin.get("tints", {}):
		g += float(tin["tints"][k])
	return g


static func total_grams(tin: Dictionary) -> float:
	return float(tin.get("base_g", TIN_GRAMS)) + tint_grams(tin)


static func litres_of(tin: Dictionary) -> float:
	return total_grams(tin) / GRAMS_PER_LITRE


## Whether `code` can go in this tin: not a sixth tint, flattener only in lacquer (and lacquer
## takes nothing else), candy dyes only in a clear base. "" or why not.
static func pour_problem(tin: Dictionary, code: String) -> String:
	if not TINTS.has(code):
		return "There's no tint like that."
	var t: Dictionary = TINTS[code]
	var base := str(tin.get("base", "W"))
	var tints: Dictionary = tin.get("tints", {})
	if base == "L" and t["kind"] != "flattener":
		return "Clear lacquer only takes flattener."
	if base != "L" and t["kind"] == "flattener":
		return "Flattener goes in a tin of clear lacquer."
	if t["kind"] == "candy" and base != "C":
		return "Candy dye goes in a clear base."
	if not tints.has(code) and tints.size() >= MAX_TINTS:
		return "Five tints is the most a recipe takes."
	if total_grams(tin) >= MAX_TIN_GRAMS - 0.05:
		return "The tin's full."
	return ""


## The paint a tin makes: its spec (see the top of this file). `tin_name` names it.
static func spec(tin: Dictionary, tin_name := "") -> Dictionary:
	var base := str(tin.get("base", "W"))
	var b: Dictionary = BASES.get(base, BASES["W"])
	var base_g := maxf(float(tin.get("base_g", TIN_GRAMS)), 1.0)
	var tints: Dictionary = tin.get("tints", {})
	var out := {"name": tin_name, "code": code_of(tin), "effect": "solid", "metal": 0.0, "rough": 0.12, "pearl": 0.0,
		"pearl_tint": Color(1, 1, 1), "flake": 0.0, "flake_color": Color(0.85, 0.85, 0.88), "holo": false, "flip": 0.0,
		"flip_a": Color(0, 0, 0), "flip_b": Color(0, 0, 0), "dye": Color(1, 1, 1), "depth": 0.0, "flat": 0.0,
		"stir": clampf(float(tin.get("stir", 1.0)), 0.0, 1.0), "base": base}
	if base == "L":
		var fl := float(tints.get("FL", 0.0))
		out["effect"] = "lacquer"
		out["flat"] = clampf(fl / base_g, 0.0, 0.5)
		out["color"] = Color(0.9, 0.9, 0.9)
		out["need"] = 1
		return out
	# The colour: a weighted geometric mean of the reflectances, by weight times strength.
	var opaque: bool = b["opaque"]
	var wsum := 0.0
	var lsum := Vector3.ZERO
	if opaque:
		wsum = base_g
		lsum = _ln(to_linear(b["color"])) * base_g
	var metal := float(b["metal"])
	var pearl := 0.0
	var pearl_tint := Vector3.ZERO
	var flake := 0.0
	var flake_col := Vector3.ZERO
	var holo := false
	var flip := 0.0
	var flip_a := Vector3.ZERO
	var flip_b := Vector3.ZERO
	var sparkle := 0.0
	var dye_w := 0.0
	var dye_sum := Vector3.ZERO
	for code in tints:
		if not TINTS.has(code):
			continue
		var t: Dictionary = TINTS[code]
		var g := maxf(float(tints[code]), 0.0)
		if g <= 0.0:
			continue
		var share := g / base_g   # grams per gram of base
		var w := g * float(t["k"])
		match str(t["kind"]):
			"alu":
				metal = maxf(metal, clampf(share * 20.0, 0.0, 0.85))
			"sparkle":
				metal = maxf(metal, clampf(share * 12.0, 0.0, 0.7))
				sparkle += clampf(share * 15.0, 0.0, 1.0)
			"pearl":
				pearl += clampf(share * 18.0, 0.0, 1.0)
				pearl_tint += to_linear(t["pearl"]) * g
			"flake":
				flake += clampf(share * 22.0, 0.0, 1.0)
				flake_col += to_linear(t["color"]) * g
				holo = holo or t.get("holo", false)
			"chameleon":
				flip += clampf(share * 16.0, 0.0, 1.0)
				flip_a += to_linear(t["a"]) * g
				flip_b += to_linear(t["b"]) * g
		if not opaque:
			# In a clear base, the colour pigments are the candy's dye.
			if str(t["kind"]) in ["tint", "candy"]:
				dye_w += w
				dye_sum += _ln(to_linear(t["color"])) * w
			continue
		if w > 0.0:
			wsum += w
			lsum += _ln(to_linear(t["color"])) * w
	var lin := Vector3(exp(lsum.x / wsum), exp(lsum.y / wsum), exp(lsum.z / wsum)) if wsum > 0.0 else to_linear(b["color"])
	var col := to_srgb(lin)
	out["metal"] = metal
	if pearl > 0.0:
		out["pearl"] = clampf(pearl, 0.0, 1.0)
		out["pearl_tint"] = to_srgb(pearl_tint / maxf(_gsum(tints, "pearl"), 0.001))
	if flake > 0.0 or sparkle > 0.0:
		out["flake"] = clampf(flake + sparkle * 0.35, 0.0, 1.0)
		out["flake_color"] = to_srgb(flake_col / maxf(_gsum(tints, "flake"), 0.001)) if flake > 0.0 else Color(0.86, 0.87, 0.9)
		out["holo"] = holo
	if flip > 0.0:
		var fg := maxf(_gsum(tints, "chameleon"), 0.001)
		out["flip"] = clampf(flip, 0.0, 1.0)
		out["flip_a"] = to_srgb(flip_a / fg)
		out["flip_b"] = to_srgb(flip_b / fg)
	if not opaque:
		# A candy: the dye and how deep each coat of it is.
		if dye_w > 0.0:
			out["dye"] = to_srgb(Vector3(exp(dye_sum.x / dye_w), exp(dye_sum.y / dye_w), exp(dye_sum.z / dye_w)))
			out["depth"] = clampf(dye_w / base_g * 0.35, 0.02, 3.0)
		col = candy_color(Color(0.72, 0.73, 0.75), out, CANDY_BEST.x)
	out["color"] = col
	# Which effect it is, the showiest first.
	var effect := "solid"
	if metal >= 0.25:
		effect = "metallic"
	if out["pearl"] >= 0.2:
		effect = "pearl"
	if not opaque and float(out["depth"]) > 0.0:
		effect = "candy"
	if flake >= 0.25:
		effect = "flake"
	if flip >= 0.3:
		effect = "chameleon"
	out["effect"] = effect
	out["rough"] = 0.3 if effect == "metallic" else (0.18 if effect in ["flake", "pearl"] else 0.1)
	out["need"] = int(EFFECTS[effect]["need"])
	return out


static func _ln(v: Vector3) -> Vector3:
	return Vector3(log(maxf(v.x, 0.0015)), log(maxf(v.y, 0.0015)), log(maxf(v.z, 0.0015)))


static func _gsum(tints: Dictionary, kind: String) -> float:
	var g := 0.0
	for code in tints:
		if TINTS.has(code) and str(TINTS[code]["kind"]) == kind:
			g += float(tints[code])
	return g


## A candy over `under` after `coats` coats: each coat filters the light through the dye again,
## so it glows deeper and darker the more goes on.
static func candy_color(under: Color, s: Dictionary, coats: int) -> Color:
	var dye := to_linear(s.get("dye", Color(1, 1, 1)))
	var e := float(s.get("depth", 0.3)) * maxf(coats, 0)
	var u := to_linear(under)
	return to_srgb(Vector3(u.x * pow(maxf(dye.x, 0.0015), e), u.y * pow(maxf(dye.y, 0.0015), e), u.z * pow(maxf(dye.z, 0.0015), e)))


## What a part looks like after `coats` coats of `s` over `under`: a candy deepens with each,
## the rest cover more with each until they've had what they need (a first coat of two lets a
## bit of what was under it show through).
static func sprayed_color(s: Dictionary, coats: int, under: Color) -> Color:
	if str(s.get("effect", "")) == "candy":
		return candy_color(under, s, coats)
	var c: Color = s.get("color", Color.WHITE)
	var need := maxi(int(s.get("need", 2)), 1)
	var cover := clampf(0.65 + 0.35 * float(coats - 1) / maxf(need - 1, 1), 0.0, 1.0) if coats < need else 1.0
	return under.lerp(c, cover)


## How well the coats so far suit the paint, 0..1: short of what it needs is thin; a candy is
## best at 3 or 4 coats and too dark past that.
static func coats_factor(s: Dictionary, coats: int) -> float:
	var need := maxi(int(s.get("need", 2)), 1)
	if str(s.get("effect", "")) == "candy":
		if coats < CANDY_BEST.x:
			return 0.7 + 0.1 * coats
		return 1.0 if coats <= CANDY_BEST.y else maxf(0.75, 1.0 - 0.1 * (coats - CANDY_BEST.y))
	return 1.0 if coats >= need else 0.75 + 0.25 * float(coats) / need


## The finish word kept as the part's "finish" for a sprayed spec (older code reads it).
static func finish_of(s: Dictionary) -> String:
	var e := str(s.get("effect", "solid"))
	return "gloss" if e == "solid" else e


static func effect_name(e: String) -> String:
	return str(EFFECTS.get(e, {}).get("name", e.capitalize()))


## "Candy red over silver, pearl..." — a short description of a spec for info panels.
static func describe(s: Dictionary) -> String:
	var bits: Array[String] = [effect_name(str(s.get("effect", "solid")))]
	if float(s.get("stir", 1.0)) < 0.9:
		bits.append("badly stirred")
	return "%s (%s)" % [str(s.get("name", "")) if str(s.get("name", "")) != "" else "Mixed paint", ", ".join(bits).to_lower()]


## Sheen name of a flattener share.
static func sheen_name(flat: float) -> String:
	if flat >= 0.3:
		return "matt"
	if flat >= 0.08:
		return "satin"
	return "gloss"


# ---------------------------------------------------------------------------- codes

## A recipe as a short code: the base letter, each tint's code and grams, and the effect's
## letter: "W-PB40-LY12.5:M". Grams to a tenth.
static func code_of(tin: Dictionary) -> String:
	var parts: Array[String] = [str(tin.get("base", "W"))]
	var tints: Dictionary = tin.get("tints", {})
	var codes: Array = tints.keys()
	codes.sort_custom(func(a, b): return TINT_ORDER.find(str(a)) < TINT_ORDER.find(str(b)))
	for code in codes:
		var g := snappedf(float(tints[code]), 0.1)
		if g <= 0.0:
			continue
		parts.append("%s%s" % [code, _grams_text(g)])
	var base_g := float(tin.get("base_g", TIN_GRAMS))
	if absf(base_g - TIN_GRAMS) > 0.05:
		parts.insert(1, "+%s" % _grams_text(base_g - TIN_GRAMS))
	return "-".join(parts)


static func _grams_text(g: float) -> String:
	return str(int(g)) if is_equal_approx(g, roundf(g)) else "%.1f" % g


## Full code with the effect letter on the end.
static func full_code(tin: Dictionary) -> String:
	var s := spec(tin)
	return "%s:%s" % [code_of(tin), str(EFFECTS[str(s["effect"])]["letter"])]


## A tin from a code (the effect letter, if any, is ignored: it's worked out again). {} if
## the code doesn't read.
static func parse_code(code: String) -> Dictionary:
	var body := code.strip_edges().get_slice(":", 0)
	var parts := body.split("-", false)
	if parts.is_empty() or not BASES.has(parts[0]):
		return {}
	var tin := new_tin(parts[0])
	for i in range(1, parts.size()):
		var p := str(parts[i])
		if p.begins_with("+"):
			if not p.substr(1).is_valid_float():
				return {}
			tin["base_g"] = clampf(TIN_GRAMS + float(p.substr(1)), 1.0, MAX_TIN_GRAMS)
			continue
		var c := p.substr(0, 2)
		var g := p.substr(2)
		if not TINTS.has(c) or not g.is_valid_float() or float(g) <= 0.0:
			return {}
		tin["tints"][c] = float(g)
	if (tin["tints"] as Dictionary).size() > MAX_TINTS:
		return {}
	return tin


# ---------------------------------------------------------------------------- unlocks and kit

## The level a tin's recipe needs (its effect, its base and its tints).
static func level_needed(tin: Dictionary) -> int:
	var lv := int(BASES.get(str(tin.get("base", "W")), {}).get("level", 1))
	for code in tin.get("tints", {}):
		lv = maxi(lv, int(TINTS.get(code, {}).get("level", 1)))
	return maxi(lv, int(EFFECTS[str(spec(tin)["effect"])]["level"]))


## Whether a tint is on the rack: the stock rack always, the effects rack once bought.
static func on_rack(code: String, effects_rack: bool) -> bool:
	return TINTS.has(code) and (str(TINTS[code]["rack"]) == "base" or effects_rack)


## The scale's precision at a level (grams it reads to): 1 g, 0.5 g from level 6, 0.1 g with the
## fine scale or from level 20.
static func scale_step(level: int, fine_scale: bool) -> float:
	if fine_scale or level >= 20:
		return 0.1
	return 0.5 if level >= 6 else 1.0


static func read_scale(grams: float, step: float) -> String:
	var g := snappedf(grams, step)
	return ("%.1f g" % g) if step < 1.0 else ("%d g" % roundi(g))


## How much the pour wobbles at a level (a share of the rate): steadier as you level up, and on
## the stainless bench.
static func pour_wobble(level: int, stainless: bool) -> float:
	return 0.35 / (1.0 + level * 0.08) * (0.6 if stainless else 1.0)


## Grams a second out of a bottle tipped to `tilt` (0 upright .. 1 straight down): a drip when
## it's just tipped, a glug at full tilt.
static func pour_rate(tilt: float) -> float:
	var t := clampf(tilt, 0.0, 1.0)
	if t < 0.15:
		return 0.0
	return 0.25 + 30.0 * pow((t - 0.15) / 0.85, 3.0)


## How much a full turn of the stick stirs (a share of an even mix), quicker at higher levels.
static func stir_per_turn(level: int) -> float:
	return 0.12 * (1.0 + level * 0.04)


## How much pouring `grams` into `total` grams of paint un-mixes it.
static func unstir(stir: float, grams: float, total: float) -> float:
	return clampf(stir - grams / maxf(total, 1.0) * 12.0, 0.0, 1.0)


## How close the tints poured are to a recipe's, 0..1 (by weight, over the recipe's tints).
static func recipe_accuracy(tin: Dictionary, recipe: Dictionary) -> float:
	var want: Dictionary = recipe.get("tints", {})
	var have: Dictionary = tin.get("tints", {})
	var total := 0.0
	var off := 0.0
	for code in want:
		total += float(want[code])
		off += absf(float(have.get(code, 0.0)) - float(want[code]))
	for code in have:
		if not want.has(code):
			off += float(have[code])
	if total <= 0.0:
		return 1.0 if off <= 0.0 else 0.0
	return clampf(1.0 - off / total, 0.0, 1.0)


## Litres a coat takes on a part of `kind`.
static func litres_for(kind: String) -> float:
	return float(LITRES.get(kind, DEFAULT_LITRES))


# ---------------------------------------------------------------------------- the library

## The manufacturer colours: [{id, brand, name, rgb (Color), effect, finish, code}], read once.
static func library() -> Array:
	if not _library.is_empty():
		return _library
	var f := FileAccess.open("res://data/paint_colours.json", FileAccess.READ)
	if f == null:
		return _library
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Array):
		return _library
	for e in data:
		if not (e is Dictionary) or not (e.get("rgb") is Array):
			continue
		var c: Array = e["rgb"]
		_library.append({"id": str(e.get("id", "")), "brand": str(e.get("brand", "")), "name": str(e.get("name", "")),
			"rgb": Color(float(c[0]), float(c[1]), float(c[2])), "effect": str(e.get("effect", "solid")),
			"finish": str(e.get("finish", "gloss")), "code": str(e.get("code", ""))})
	return _library


static func library_entry(id: String) -> Dictionary:
	for e in library():
		if e["id"] == id:
			return e
	return {}


## "Kawasaki Lime Green".
static func library_name(e: Dictionary) -> String:
	return "%s %s" % [e.get("brand", ""), e.get("name", "")]


## The library colour nearest a colour (and effect): {entry, match}.
static func nearest_library(c: Color, effect := "") -> Dictionary:
	var best := {}
	var best_m := -1.0
	for e in library():
		var m := match_of(c, e["rgb"], effect, str(e["effect"]))
		if m > best_m:
			best_m = m
			best = e
	return {"entry": best, "match": maxf(best_m, 0.0)}


# ---------------------------------------------------------------------------- a recipe for a colour

## Works out a recipe for a colour and effect from the given tints (TINT_ORDER's solid ones by
## default): a base, then tints added a little at a time while each makes it closer, then
## trimmed. Used to write the library's recipe cards and by the colour meter. Returns a tin.
static func solve(target: Color, effect := "solid", allowed: Array = []) -> Dictionary:
	var solids: Array = allowed.duplicate() if not allowed.is_empty() else \
		TINT_ORDER.filter(func(c): return str(TINTS[c]["kind"]) == "tint")
	var bases := ["W", "B"]
	var extra := {}
	match effect:
		"metallic":
			bases = ["S"]
		"pearl":
			extra = {"PW": 40.0}
		"candy":
			bases = ["C"]
			solids = ["CR", "CB", "CG", "LY", "OR", "VI", "BK"]
		"flake":
			extra = {"FS": 40.0}
		"chameleon":
			bases = ["B"]
			extra = {"XP": 60.0}
	var best := {}
	var best_d := INF
	for base in bases:
		var tin := solve_from(target, str(base), solids, extra)
		var d := delta_e(spec(tin)["color"], target)
		if d < best_d:
			best_d = d
			best = tin
	return best


## The solver from one base (see solve): `extra` tints go in first and stay.
static func solve_from(target: Color, base: String, solids: Array, extra := {}) -> Dictionary:
	var best := new_tin(base)
	for k in extra:
		best["tints"][k] = extra[k]
	var best_d := delta_e(spec(best)["color"], target)
	for step in [64.0, 16.0, 4.0, 1.0, 0.25]:
		var improved := true
		var guard := 0
		while improved and guard < 60:
			improved = false
			guard += 1
			var pick := {}
			for code in solids:
				for sgn in [1.0, -1.0]:
					var t := best.duplicate(true)
					var g: float = float(t["tints"].get(code, 0.0)) + step * sgn
					if g < 0.0:
						continue
					if g == 0.0:
						t["tints"].erase(code)
					else:
						t["tints"][code] = g
					if (t["tints"] as Dictionary).size() > MAX_TINTS or tint_grams(t) > 300.0:
						continue
					var d := delta_e(spec(t)["color"], target)
					if d < best_d - 0.01:
						best_d = d
						pick = t
			if not pick.is_empty():
				best = pick
				improved = true
	return best


# ---------------------------------------------------------------------------- materials

const FX_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// The mesh's place in its bike model's space (rows of a 3x4 matrix), and the part's own
// box there: x = its middle across, y = the split height, z = its middle along, w = half its height.
instance uniform vec4 fx_r0 = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 fx_r1 = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 fx_r2 = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec4 fx_box = vec4(0.0, 0.0, 0.0, 0.1);

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float flip = 0.0;
uniform vec4 flip_a : source_color = vec4(0.0, 0.6, 0.3, 1.0);
uniform vec4 flip_b : source_color = vec4(0.1, 0.3, 0.8, 1.0);
uniform float pearl = 0.0;
uniform vec4 pearl_tint : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float flake = 0.0;
uniform float flake_size = 0.004;
uniform vec4 flake_color : source_color = vec4(0.85, 0.85, 0.9, 1.0);
uniform float holo = 0.0;
uniform float blotch = 0.0;
uniform vec4 blotch_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform int pattern = 0;
uniform vec4 mask_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float mask_metal = 0.0;
uniform float mask_rough = 0.15;
uniform float tape = 0.0;
uniform vec4 tape_color : source_color = vec4(0.18, 0.42, 0.85, 1.0);

varying vec3 mpos;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vn(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(h3(i + vec3(0.0, 1.0, 0.0)), h3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(h3(i + vec3(0.0, 0.0, 1.0)), h3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(h3(i + vec3(0.0, 1.0, 1.0)), h3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
	VERTEX += NORMAL * 0.0006;
	vec4 v = vec4(VERTEX, 1.0);
	mpos = vec3(dot(fx_r0, v), dot(fx_r1, v), dot(fx_r2, v));
}

// How much of the masked colour shows here (the pattern), 0..1.
float masked() {
	float x = abs(mpos.x - fx_box.x);
	float y = mpos.y - fx_box.y;
	float aa = 0.0015;
	if (pattern == 1) {
		return 1.0 - smoothstep(0.03 - aa, 0.03 + aa, x);
	} else if (pattern == 2) {
		return (1.0 - smoothstep(0.045 - aa, 0.045 + aa, x)) * smoothstep(0.022 - aa, 0.022 + aa, x);
	} else if (pattern == 3) {
		return 1.0 - smoothstep(0.004 - aa * 0.5, 0.004 + aa * 0.5, abs(y));
	} else if (pattern == 4) {
		return smoothstep(-aa, aa, y);
	} else if (pattern == 5) {
		float w = max(fx_box.w * 0.7, 0.03);
		return 1.0 - smoothstep(-w, w, y + (vn(mpos * 30.0) - 0.5) * w * 0.15);
	} else if (pattern == 6) {
		float w = max(fx_box.w * 0.9, 0.04);
		return 1.0 - smoothstep(-w, w, (mpos.z - fx_box.z) * -1.0 + (vn(mpos * 30.0) - 0.5) * w * 0.15);
	}
	return 0.0;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(abs(dot(n, normalize(VIEW))), 0.0, 1.0);
	float glance = 1.0 - facing;
	vec3 col = base_color.rgb;
	float alpha = 0.0;
	float metal = 0.0;
	float rough = 0.12;
	// A badly stirred mix sprays blotchy: streaks of the tints that never mixed in.
	if (blotch > 0.0) {
		float b = smoothstep(0.45, 0.8, vn(mpos * vec3(18.0, 40.0, 18.0)) * 0.7 + vn(mpos * 90.0) * 0.3) * blotch;
		col = mix(col, blotch_color.rgb, b);
		alpha = max(alpha, b);
	}
	// Chameleon: the colour slides through two or three colours as the angle changes.
	if (flip > 0.0) {
		vec3 c1 = mix(col, flip_a.rgb, smoothstep(0.15, 0.6, glance));
		vec3 c2 = mix(c1, flip_b.rgb, smoothstep(0.55, 0.95, glance));
		col = c2;
		alpha = max(alpha, flip * smoothstep(0.05, 0.4, glance));
		metal = 0.6;
		rough = 0.2;
	}
	// Pearl: a soft coloured sheen at glancing angles.
	if (pearl > 0.0) {
		float s = pearl * pow(glance, 1.6) * 0.8;
		col = mix(col, pearl_tint.rgb, s / max(alpha + s, 0.001));
		alpha = max(alpha, s);
		rough = 0.15;
	}
	// Flake: bits of metal in the clear, each catching the light at its own angle.
	if (flake > 0.0) {
		vec3 cell = floor(mpos / flake_size);
		float r = h3(cell);
		float on = step(1.0 - flake * 0.55, r);
		if (on > 0.0) {
			vec3 tilt = vec3(h3(cell + 3.1), h3(cell + 7.7), h3(cell + 1.3)) - 0.5;
			NORMAL = normalize(n + tilt * 1.6);
			vec3 fc = flake_color.rgb;
			if (holo > 0.5) {
				fc = 0.6 + 0.4 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + r * 3.0));
			}
			col = fc;
			alpha = max(alpha, on);
			metal = 1.0;
			rough = 0.12;
		}
	}
	// The masked colour, sharp-edged under tape or soft for a fade, and the tape still on it.
	float m = masked();
	if (m > 0.0) {
		col = mix(col, mask_color.rgb, m);
		metal = mix(metal, mask_metal, m);
		rough = mix(rough, mask_rough, m);
		alpha = max(alpha, m);
	}
	if (tape > 0.5 && pattern > 0 && pattern < 5) {
		float t = m;
		col = mix(col, tape_color.rgb, t);
		rough = mix(rough, 0.85, t);
		metal = mix(metal, 0.0, t);
		alpha = max(alpha, t);
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""

static var _fx_shader: Shader


static func fx_shader() -> Shader:
	if _fx_shader == null:
		_fx_shader = Shader.new()
		_fx_shader.code = FX_CODE
	return _fx_shader


## Sets up a part's paint material from its condition (see Shed.condition_of): the base
## material's colour, metal, roughness and clear coat from the spec (and the lacquer's
## flattener), plus a pass over it for the effects, a mask's second colour and tape. The pass
## (m.next_pass) carries meta "paint_fx"; its instance uniforms are set per mesh (see place_fx).
static func apply(m: StandardMaterial3D, cond: Dictionary) -> void:
	var s = cond.get("mix")
	var color: Color = cond.get("color", m.albedo_color)
	m.albedo_color = color
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	m.metallic = 0.05
	m.roughness = 0.12
	if s is Dictionary:
		var e := str(s.get("effect", "solid"))
		match e:
			"metallic":
				m.metallic = clampf(float(s.get("metal", 0.7)), 0.3, 0.9)
				m.roughness = 0.3
				m.clearcoat = 0.8
			"pearl":
				m.metallic = 0.15
				m.roughness = 0.15
			"candy":
				m.metallic = 0.75
				m.roughness = 0.18
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.01
			"flake":
				m.metallic = maxf(0.3, float(s.get("metal", 0.0)))
				m.roughness = 0.2
			"chameleon":
				m.metallic = 0.5
				m.roughness = 0.2
	var flat := float(cond.get("flat", 0.0))
	if flat > 0.0:
		# Flattener in the lacquer: satin, or matt that soaks up the light.
		m.roughness = lerpf(m.roughness, 0.92, clampf(flat / 0.4, 0.0, 1.0))
		m.clearcoat = maxf(0.0, m.clearcoat * (1.0 - flat * 2.4))
		m.clearcoat_enabled = m.clearcoat > 0.05
	var fx := fx_pass(cond)
	if fx != null:
		m.next_pass = fx
		m.set_meta("paint_fx", true)


## The effects pass for a painted part, or null when it doesn't need one.
static func fx_pass(cond: Dictionary) -> ShaderMaterial:
	var s = cond.get("mix")
	var mask = cond.get("mask")
	var tape = cond.get("tape")
	var spec_d: Dictionary = s if s is Dictionary else {}
	var stir := float(spec_d.get("stir", 1.0))
	var need_pass := (mask is Dictionary) or (tape is Dictionary) or stir < 0.9 \
		or float(spec_d.get("flip", 0.0)) > 0.0 or float(spec_d.get("pearl", 0.0)) > 0.0 or float(spec_d.get("flake", 0.0)) > 0.0
	if not need_pass:
		return null
	var p := ShaderMaterial.new()
	p.shader = fx_shader()
	p.render_priority = 1
	var color: Color = cond.get("color", Color(0.5, 0.5, 0.5))
	p.set_shader_parameter("base_color", color)
	p.set_shader_parameter("flip", float(spec_d.get("flip", 0.0)))
	p.set_shader_parameter("flip_a", spec_d.get("flip_a", Color(0, 0.6, 0.3)))
	p.set_shader_parameter("flip_b", spec_d.get("flip_b", Color(0.1, 0.3, 0.8)))
	p.set_shader_parameter("pearl", float(spec_d.get("pearl", 0.0)))
	p.set_shader_parameter("pearl_tint", spec_d.get("pearl_tint", Color(1, 1, 1)))
	var fl := float(spec_d.get("flake", 0.0))
	p.set_shader_parameter("flake", fl)
	# Big flake for a flake paint, a fine sparkle for a metallic with sparkle aluminium.
	p.set_shader_parameter("flake_size", 0.006 if str(spec_d.get("effect", "")) == "flake" else 0.0025)
	p.set_shader_parameter("flake_color", spec_d.get("flake_color", Color(0.86, 0.87, 0.9)))
	p.set_shader_parameter("holo", 1.0 if spec_d.get("holo", false) else 0.0)
	var blotch := clampf((0.9 - stir) / 0.9, 0.0, 1.0) * 0.8
	if str(spec_d.get("effect", "")) == "candy":
		blotch = maxf(blotch, clampf(1.0 - float(cond.get("paint_q", 1.0)), 0.0, 0.5))
	p.set_shader_parameter("blotch", blotch)
	p.set_shader_parameter("blotch_color", color.lightened(0.25) if str(spec_d.get("effect", "")) == "candy" else color.darkened(0.3).lerp(Color(0.9, 0.9, 0.9), 0.2))
	var pid := 0
	if mask is Dictionary:
		pid = int(PATTERN_IDS.get(str(mask.get("pattern", "")), 0))
		p.set_shader_parameter("mask_color", mask.get("color", Color.WHITE))
		var ms = mask.get("mix")
		p.set_shader_parameter("mask_metal", float(ms.get("metal", 0.0)) * 0.8 if ms is Dictionary else 0.05)
		p.set_shader_parameter("mask_rough", float(ms.get("rough", 0.15)) if ms is Dictionary else 0.15)
	if tape is Dictionary:
		if pid == 0:
			# Taped but not sprayed over yet: the tape shows where the stripe will be.
			pid = int(PATTERN_IDS.get(str(tape.get("pattern", "")), 0))
			p.set_shader_parameter("mask_color", color)
		p.set_shader_parameter("tape", 1.0)
		p.set_shader_parameter("tape_color", tape_color_on(color))
	p.set_shader_parameter("pattern", pid)
	return p


## The masking tape that shows up on paint `under`: blue, or cream on a blue part.
static func tape_color_on(under: Color) -> Color:
	var d := Vector3(under.r - TAPE_COLOR.r, under.g - TAPE_COLOR.g, under.b - TAPE_COLOR.b).length()
	return TAPE_CREAM if d < 0.4 else TAPE_COLOR


## Puts a mesh's place in its model's space (`xf`) and the part's box there onto the mesh, for
## its effects pass to find the stripes and the split.
static func place_fx(g: GeometryInstance3D, xf: Transform3D, box: AABB) -> void:
	var b := xf.basis
	g.set_instance_shader_parameter("fx_r0", Vector4(b.x.x, b.y.x, b.z.x, xf.origin.x))
	g.set_instance_shader_parameter("fx_r1", Vector4(b.x.y, b.y.y, b.z.y, xf.origin.y))
	g.set_instance_shader_parameter("fx_r2", Vector4(b.x.z, b.y.z, b.z.z, xf.origin.z))
	var c := box.get_center()
	g.set_instance_shader_parameter("fx_box", Vector4(c.x, c.y, c.z, box.size.y * 0.5))


## A material showing a spec on its own (a swatch card, a test panel, the paint in a tin): the
## spec over silver for a candy, otherwise just as sprayed. `flat`: the lacquer's flattener.
static func material(s: Dictionary, flat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var cond := {"color": s.get("color", Color.WHITE), "mix": s, "flat": flat}
	apply(m, cond)
	return m


## The value a bike's custom paint adds to its uniqueness (see Sales.uniqueness): rarer
## effects and masked schemes add more. `items`: the painted parts on it.
static func uniqueness_bonus(items: Array) -> Dictionary:
	var effects := {}
	var masked := false
	for it in items:
		var s = it.get("mix")
		if s is Dictionary:
			effects[str(s.get("effect", "solid"))] = true
		if it.get("mask") is Dictionary:
			masked = true
	var score := 0.0
	var names: Array[String] = []
	for e in effects:
		var v := float(EFFECTS.get(e, {}).get("value", 0.0))
		if v > 0.0:
			score += v
			names.append(effect_name(str(e)).to_lower())
	if masked:
		score += 0.04
		names.append("hand-masked stripes")
	return {"score": minf(score, 0.18), "names": names}
