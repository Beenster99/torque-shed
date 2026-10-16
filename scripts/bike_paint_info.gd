class_name BikePaintInfo
extends RefCounted
## How a bike is painted, panel by panel, for the bike details pages (the sales office PC's
## showroom page, the shop's Sell aisle): each painted part on it (the tank, side panels,
## fairing, guards, tail and the rest, and any other part someone has sprayed) with its own
## colour (a palette colour, or a mixed paint by name and recipe code), finish and sheen, coats,
## lacquer, how well the job came out, and any masked stripe, fade or tape still on.
## Read straight off the Shed's items, so every player sees the same.

## The bodywork panels, in the order they're listed. They're shown whenever they're fitted;
## any other part shows only once it has been sprayed or lacquered.
const PANELS: Array[String] = ["tank", "side_panels", "fairing", "front_mudguard", "tail", "number_boards", "guards",
	"top_box", "panniers", "frame", "swingarm"]


## One entry per painted panel on `bike_id`: {slot, name (the panel), part (its part name),
## colour, code, finish, coats, lacquer, quality (0..1, or -1 for a factory finish), pattern,
## tape, color}. Panels first in PANELS order, then the other sprayed parts.
static func panels(bike_id: int) -> Array:
	var out := []
	if not Shed.bikes.has(bike_id):
		return out
	var slots: Array[String] = PANELS.duplicate()
	for slot in PartsDB.BIKE_SLOTS:
		if not slots.has(slot):
			slots.append(slot)
	for slot in slots:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or not Shed.items.has(id):
			continue
		var it: Dictionary = Shed.items[id]
		if not PANELS.has(slot) and not sprayed(it):
			continue
		out.append(entry(slot, it))
	return out


## Whether a part has had paint, primer or lacquer put on it in the shed.
static func sprayed(it: Dictionary) -> bool:
	return it.has("paint_quality") or it.get("mix") is Dictionary or it.get("primer_top", false) \
		or Shed.LACQUERS.has(str(it.get("coat", ""))) or float(it.get("flat", 0.0)) > 0.0


## The paint on one part, as panels() lists it.
static func entry(slot: String, it: Dictionary) -> Dictionary:
	var e := {"slot": slot, "name": PartsDB.slot_name(slot), "part": PartsDB.part_name(str(it["part"])),
		"colour": "", "code": "", "finish": "", "coats": 0, "lacquer": "", "quality": -1.0, "pattern": "", "tape": "",
		"color": it.get("color", Color.WHITE)}
	var mix = it.get("mix")
	if it.get("primer_top", false):
		e["colour"] = "Grey primer"
		e["finish"] = "primer"
	elif mix is Dictionary and not (mix as Dictionary).is_empty():
		var m: Dictionary = mix
		e["colour"] = str(m.get("name", "")) if str(m.get("name", "")) != "" else "Mixed paint"
		var effect := str(m.get("effect", "solid"))
		if str(m.get("code", "")) != "":
			e["code"] = "%s:%s" % [m["code"], str(PaintMix.EFFECTS.get(effect, {}).get("letter", "S"))]
		e["finish"] = "%s, %s" % [PaintMix.effect_name(effect).to_lower(), PaintMix.sheen_name(float(it.get("flat", 0.0)))]
		e["coats"] = int(it.get("mix_coats", 1))
	else:
		e["colour"] = Shed.paint_name(it.get("color", Color.WHITE)).capitalize()
		var f := str(it.get("finish", ""))
		e["finish"] = str(Shed.FINISH_NAMES.get(f, f.capitalize())).to_lower() if f != "" else "factory finish"
		if float(it.get("flat", 0.0)) > 0.0:
			e["finish"] += ", " + PaintMix.sheen_name(float(it["flat"]))
	if Shed.LACQUERS.has(str(it.get("coat", ""))):
		e["lacquer"] = "%s (%d%%)" % [Shed.coat_name(str(it["coat"])).to_lower(), roundi(float(it.get("coat_q", 1.0)) * 100.0)]
	if it.has("paint_quality"):
		e["quality"] = clampf(float(it["paint_quality"]), 0.0, 1.0)
	var mask = it.get("mask")
	if mask is Dictionary and not it.get("primer_top", false):
		var mk: Dictionary = mask
		var pat := str(mk.get("pattern", ""))
		var under := ""
		if mk.get("mix") is Dictionary and str((mk["mix"] as Dictionary).get("name", "")) != "":
			under = str(mk["mix"]["name"])
		elif mk.get("color") is Color:
			under = Shed.paint_name(mk["color"]).to_lower()
		var pat_name := str(PaintMix.PATTERNS.get(pat, {}).get("name", pat.capitalize()))
		e["pattern"] = ("%s in %s" % [pat_name, under]) if under != "" else pat_name
	var tape = it.get("tape")
	if tape is Dictionary:
		e["tape"] = str(PaintMix.PATTERNS.get(str(tape.get("pattern", "")), {}).get("name", "tape")).to_lower()
	return e


## One panel's paint as a line: "Midnight Blue W-PB40:M · metallic, gloss · 2 coats · clear
## lacquer (92%) · job 91% · Centre stripe in white".
static func line(e: Dictionary) -> String:
	var bits: Array[String] = [str(e["colour"]) + ("  " + str(e["code"]) if str(e["code"]) != "" else "")]
	if str(e["finish"]) != "":
		bits.append(str(e["finish"]))
	if int(e["coats"]) > 0:
		bits.append("%d coat%s" % [int(e["coats"]), "" if int(e["coats"]) == 1 else "s"])
	if str(e["lacquer"]) != "":
		bits.append(str(e["lacquer"]))
	if float(e["quality"]) >= 0.0:
		bits.append("job %d%%" % roundi(float(e["quality"]) * 100.0))
	if str(e["pattern"]) != "":
		bits.append(str(e["pattern"]))
	if str(e["tape"]) != "":
		bits.append("masking tape still on (%s)" % str(e["tape"]))
	return "  ·  ".join(bits)


## Every painted panel as "Tank: <line>" lines, for a plain text box.
static func text(bike_id: int) -> String:
	var lines: Array[String] = []
	for e in panels(bike_id):
		lines.append("%s: %s" % [e["name"], line(e)])
	return "\n".join(lines) if not lines.is_empty() else "No painted panels fitted."
