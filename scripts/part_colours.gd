class_name PartColours
extends RefCounted
## The colours a bike part is ordered in. A part with a look of its own colour (a tank, a seat,
## a tail, a set of bars...) is bought in a colour picked from the paint shop's palette
## (Shed.PAINTS) and a finish (Shed.FINISHES), as if the factory had sprayed it so: the spray
## booth paints over it, it rusts and wears, and the model draws it, like any other paint. Parts
## with a second colour take one too: a seat's piping, a stripe along a tank, a fairing or a tail,
## a mudguard's rib, the pad on a braced bar or a pannier's trim; an exhaust takes a finish for
## its headers instead (chrome, black, heat wrap...).
##
## A part's look is a dictionary, as items carry it: {color, finish, color2, trim}. "color" and
## "finish" are the paint the item has always had ("" finish: as the factory left it), "color2"
## the second colour (none: the factory's own, or no stripe) and "trim" the headers' finish.

## Kinds of part bought in a colour of your choice, and what each one's second colour is: "" for
## none, "stripe" (left off unless picked, where the part has none of its own), "piping", "rib",
## "pad", "trim" or "header" (a finish for an exhaust's headers, not a colour). Some kinds only
## have the second colour on some shapes (see second_of).
const KINDS := {
	"tank": "stripe", "fairing": "stripe", "tail": "stripe", "front_mudguard": "stripe", "saddle": "piping",
	"handlebars": "pad", "panniers": "trim", "exhaust": "header", "side_panels": "", "number_boards": "",
	"headlight": "", "mirrors": "", "top_box": "", "frame": "", "swingarm": "",
}
const SECOND_NAMES := {"stripe": "Stripe", "piping": "Piping", "rib": "Rib", "pad": "Bar pad", "trim": "Trim",
	"header": "Headers"}
## The finishes an exhaust's headers can come in (BikeModel._look_finish), in picker order.
const HEADERS: Array[String] = ["chrome", "polished", "brushed", "black", "titanium", "wrap", "wrap_black"]
const HEADER_NAMES := {"chrome": "Chrome", "polished": "Polished", "brushed": "Brushed stainless", "black": "Black",
	"titanium": "Blued titanium", "wrap": "Heat wrap", "wrap_black": "Black heat wrap"}
## The tail cowls that carry a stripe (BikeModel._tail_cowl); fenders and loops don't.
const STRIPED_COWLS: Array[String] = ["ducktail", "hump", "solo", "tracker", "sport", "racing"]
## The pannier shapes with a trim to colour (studs, a lid strip).
const TRIMMED_BAGS: Array[String] = ["saddlebag", "hard_top", "hard"]

## Each style's colours (indices into Shed.PAINTS), for the parts on a bike that's found or built
## for you (see random_look): the look it's known for.
const STYLE_COLOURS := {
	"classic": [6, 14, 12, 8, 3], "cafe": [6, 8, 0, 14, 3], "bobber": [6, 15, 12, 13, 8],
	"chopper": [6, 4, 0, 9, 7], "cruiser": [6, 12, 14, 7, 8], "scrambler": [15, 13, 14, 2, 6],
	"adventure": [5, 15, 2, 8, 6], "roader": [6, 8, 0, 1], "tourer": [8, 1, 12, 6],
	"sport": [0, 1, 5, 10, 6], "race": [5, 0, 1, 10], "naked": [6, 2, 8, 7],
	"supermoto": [5, 2, 10, 0, 6], "mx": [2, 10, 1, 0, 5],
}
## The kinds a found or built bike's parts come in other colours of (see random_look).
const RANDOM_MAIN: Array[String] = ["saddle", "tail", "front_mudguard", "side_panels", "number_boards", "frame",
	"swingarm", "fairing", "panniers", "top_box"]
const STYLE_HEADERS := {
	"bobber": ["black", "wrap_black", "chrome"], "chopper": ["chrome", "black", "wrap_black"],
	"cruiser": ["chrome", "black"], "cafe": ["wrap", "brushed", "black"], "scrambler": ["wrap", "brushed", "black"],
	"classic": ["chrome", "polished"], "sport": ["titanium", "brushed"], "race": ["titanium", "black"],
	"mx": ["brushed", "titanium"], "supermoto": ["brushed", "titanium", "black"], "adventure": ["brushed", "titanium", "black"],
}


## Whether a part is bought in a colour of your choice.
static func pickable(part_id: String) -> bool:
	return KINDS.has(PartsDB.kind_of(part_id))


## What a part's second colour is ("stripe", "piping", "rib", "pad", "trim", "header"), or "".
static func second_of(part_id: String) -> String:
	var k := PartsDB.kind_of(part_id)
	var p := PartsDB.get_part(part_id)
	var lk: Dictionary = p.get("look", {})
	match k:
		"tail":
			return "stripe" if STRIPED_COWLS.has(str(lk.get("cowl", ""))) else ""
		"front_mudguard":
			return "rib" if lk.get("rib", false) else "stripe"
		"handlebars":
			return "pad" if lk.get("pad", false) else ""
		"panniers":
			return "trim" if TRIMMED_BAGS.has(str(lk.get("shape", ""))) else ""
	return str(KINDS.get(k, ""))


## Whether the second colour is picked as a finish (an exhaust's headers) rather than a colour.
static func second_is_finish(part_id: String) -> bool:
	return second_of(part_id) == "header"


## The second colour the part comes in from the factory, or null where it has none (a stripe
## that's only there if you pick one).
static func factory_second(part_id: String):
	var a = PartsDB.get_part(part_id).get("look", {}).get("accent")
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else null


## Why `look` can't be what `part_id` is ordered in, or "" when it can.
static func check(part_id: String, look) -> String:
	if not (look is Dictionary):
		return "That's not a colour."
	if (look as Dictionary).is_empty():
		return ""
	if not pickable(part_id):
		return "That part only comes one way."
	if look.has("color") and not (look["color"] is Color):
		return "That's not a colour."
	if look.has("finish") and not (look["finish"] is String and (str(look["finish"]) == "" or Shed.FINISHES.has(str(look["finish"])))):
		return "That finish isn't on offer."
	var second := second_of(part_id)
	if look.has("color2") and not (look["color2"] is Color and second != "" and second != "header"):
		return "That part has no second colour."
	if look.has("trim") and not (second == "header" and HEADERS.has(str(look["trim"]))):
		return "Those headers don't come like that."
	return ""


## Just the colour fields of `look` that are the right type ({color, finish, color2, trim}), for
## a look that came from a save, a plan or another player.
static func clean(look) -> Dictionary:
	var out := {}
	if not (look is Dictionary):
		return out
	if look.get("color") is Color:
		out["color"] = look["color"]
	if look.has("finish"):
		out["finish"] = str(look["finish"]).left(16)
	if look.get("color2") is Color:
		out["color2"] = look["color2"]
	if HEADERS.has(str(look.get("trim", ""))):
		out["trim"] = str(look["trim"])
	return out


## Puts `look` on an item: its colour, finish, second colour and headers. With `all` the item
## takes the look as a whole, losing a second colour or trim the look doesn't have.
static func apply(item: Dictionary, look, all := false) -> void:
	var l := clean(look)
	if l.has("color"):
		item["color"] = l["color"]
	if l.has("finish"):
		item["finish"] = l["finish"]
	for key in ["color2", "trim"]:
		if l.has(key):
			item[key] = l[key]
		elif all:
			item.erase(key)


## An item's look, as a plan or a blueprint keeps it.
static func look_of(item: Dictionary) -> Dictionary:
	var out := {"color": item.get("color", Color.WHITE), "finish": str(item.get("finish", ""))}
	for key in ["color2", "trim"]:
		if item.has(key):
			out[key] = item[key]
	return out


## "Red, white piping" for the line under a part: its colours by the paint shop's names.
static func text(look: Dictionary, part_id: String) -> String:
	var bits: Array[String] = []
	if look.get("color") is Color:
		var f := str(look.get("finish", ""))
		var n := Shed.paint_name(look["color"])
		bits.append(n.capitalize() if f == "" else "%s %s" % [str(Shed.FINISH_NAMES.get(f, f.capitalize())), n])
	var second := second_of(part_id)
	if look.get("color2") is Color and second != "":
		bits.append("%s %s" % [Shed.paint_name(look["color2"]), str(SECOND_NAMES[second]).to_lower()])
	if look.has("trim"):
		bits.append("%s headers" % str(HEADER_NAMES.get(str(look["trim"]), "")).to_lower())
	return ", ".join(bits)


## A look for a part on a bike that's found or built for someone (a project bike, a customer's,
## a contract's): leaning to the bike's `style` and its `paint`, so no two come out the same.
## With `painted` the part keeps the bike's paint (a tank, a fairing) and only its second colour
## is picked. `key` makes it the same every time for the same bike and slot. {} leaves it as the
## factory made it.
static func random_look(part_id: String, style: String, paint: Color, painted: bool, key: int) -> Dictionary:
	if not pickable(part_id):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	var palette: Array = STYLE_COLOURS.get(style, [6, 8, 5])
	var look := {}
	var main: Color = PartsDB.default_color(part_id)
	# The bodywork and the seat take another colour; pipes, lamps, mirrors and bars, and anything
	# carbon, stay as they come (a red exhaust or a painted carbon frame is for a player to pick).
	var r := rng.randf()
	if not painted and RANDOM_MAIN.has(PartsDB.kind_of(part_id)) and PartsDB.material(part_id) != "carbon" and not part_id.contains("carbon"):
		if r < 0.3:
			main = paint
			look["color"] = paint
		elif r < 0.55:
			main = Shed.PAINTS[int(palette[rng.randi() % palette.size()])]
			look["color"] = main
	match second_of(part_id):
		"stripe":
			# A stripe now and then, in a colour that stands out from the part's.
			if rng.randf() < 0.35:
				look["color2"] = _contrast(main, palette, rng)
		"piping", "pad", "trim", "rib":
			if rng.randf() < 0.45:
				look["color2"] = _contrast(main, palette, rng)
		"header":
			var headers: Array = STYLE_HEADERS.get(style, ["chrome", "brushed", "black"])
			if rng.randf() < 0.4:
				look["trim"] = str(headers[rng.randi() % headers.size()])
	return look


## A colour from `palette` (or white, black or gold) that isn't too like `c`.
static func _contrast(c: Color, palette: Array, rng: RandomNumberGenerator) -> Color:
	var options: Array = palette.duplicate()
	for i in [5, 6, 9]:
		if not options.has(i):
			options.append(i)
	for _try in 6:
		var pick: Color = Shed.PAINTS[int(options[rng.randi() % options.size()])]
		if Vector3(pick.r - c.r, pick.g - c.g, pick.b - c.b).length() > 0.35:
			return pick
	return Shed.PAINTS[5] if c.get_luminance() < 0.5 else Shed.PAINTS[6]
