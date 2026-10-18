class_name Detail
extends RefCounted
## Detailing a bike in the wash bay, on the host's side: the state of its paintwork after the
## pressure washer's done (how glossy each painted panel is, region by region, any burn-through
## where a polisher was held too long, and the ceramic coat over it with any residue or smears),
## the rules for it, and what it does for the bike: a coated bike picks road dirt up slower and
## washes off quicker, it looks deeper and glossier (FinishLayer draws it), and a glossy, coated
## bike sells for a bit more. The coat (and the gloss under it, slower) wears off with the miles.
##
## Each panel's finish lives on its item as "shine" (synced and saved with it; parts from before
## detailing have none and count as BASE_GLOSS, a little swirled, no coat). It's laid out like
## its road dirt (Dirt): NX along by NY up for each of the six ways a surface faces, so the
## regions the mini game polishes (DetailJob) line up with the ones it washed. Channels, a byte a
## region each: "g" gloss (0 dull and swirled .. 1 deep gloss), "b" burnt through the clear coat,
## "c" ceramic coat, "r" coat residue still to buff off, "s" smears (residue that flashed before
## it was buffed: a high spot that needs polishing off), and "u" which regions have paint the pad
## can get to (none yet: all of them count).
##
## Steps: a detailing job is a simple list of steps (STEPS: "wash", "polish", "coat"), as a
## customer's detailing contract asks for (Contracts' "detail" kind keeps it on the job as
## "steps"). Anyone who isn't playing the mini game by hand (an AI detailer, say) works through
## them with work_step(bike, step, amount, skill) on the host, or the "shine_step" request; and
## step_progress / step_done / next_step / check_steps say where a bike's up to.
##
## Requests (Shed.request, host-checked here): "shine_cells" {bike, parts: {item: {g, b, c, r, s,
## u}}} (the mini game's regions, as it has them now), "shine_start" {bike} (a panel without a
## finish yet gets the default one, so it's drawn from the start), "shine_step" {bike, step,
## amount, skill}.

## The painted panels that get polished and coated.
const PANELS: Array[String] = ["tank", "fairing", "tail", "side_panels", "front_mudguard", "number_boards", "panniers", "top_box"]
const CHANNELS: Array[String] = ["g", "b", "c", "r", "s", "u"]
## A panel nobody's detailed: about how a used bike's paint is, a bit swirled and hazy.
const BASE_GLOSS := 0.5
## What counts as done, for a customer's detailing job (and the HUD's ticks): washed this clean,
## polished this glossy (every panel at least GLOSS_PANEL), coated this well.
const CLEAN_GOOD := 0.9
const GLOSS_GOOD := 0.8
const GLOSS_PANEL := 0.65
const COAT_GOOD := 0.75
## A region this burnt (or this smeared) counts as a burn (a smear).
const BURN_AT := 0.25
const SMEAR_AT := 0.3
## A full ceramic coat keeps this much of the road dirt off (as a protective coat does, see
## Dirt.accrue) and makes the pressure washer this much quicker on it (1.0: twice as quick).
const DIRT_SHED := 0.6
const WASH_BOOST := 1.0
## The miles a coat lasts (it wears thinner evenly), and the gloss under it, faded back towards
## BASE_GLOSS (slower under a coat).
const COAT_LIFE_KM := 4000.0
const GLOSS_LIFE_KM := 6000.0
## What a deep gloss and a full coat add to a bike's price (on top of being clean, see
## Money.clean_bonus), and what each burnt panel takes off.
const BONUS_GLOSS := 0.04
const BONUS_COAT := 0.04
const BURN_COST := 0.03
## The steps of a detailing job, in order, and what they're called.
const STEPS: Array[String] = ["wash", "polish", "coat"]
const STEP_NAMES := {"wash": "Wash", "polish": "Polish", "coat": "Ceramic coat"}
## A customer's detailing packages (Contracts' "detail" kind), smallest first.
const PACKAGES := [
	{"name": "Wash", "steps": ["wash"], "pay": Vector2i(45, 70), "days": 1},
	{"name": "Wash and polish", "steps": ["wash", "polish"], "pay": Vector2i(150, 220), "days": 2},
	{"name": "Full detail", "steps": ["wash", "polish", "coat"], "pay": Vector2i(320, 440), "days": 3},
]
## work_step: how much of a step `amount` 1.0 does at skill 0.5 (a fifth of the way, about), and
## how much worse a beginner's (skill 0) is, the burn and smear risk.
const STEP_RATE := 0.2
const RISK := 0.12
const NO_REACH := "Polishing and coating are done in the wash bay. Wheel it in there first."
const WASH_FIRST := "Wash it first: polishing over grit scratches the paint."


# ---------------------------------------------------------------------------- a part's finish

static func is_panel(slot: String) -> bool:
	return PANELS.has(slot)


## Whether an item has a finish of its own yet (else it's the default: BASE_GLOSS, no coat).
static func has(it: Dictionary) -> bool:
	return it.get("shine") is Dictionary


## An item's finish, channel by channel (see the top): its own, or the default for one without.
static func data(it: Dictionary) -> Dictionary:
	var s = it.get("shine")
	var out := {}
	for ch in CHANNELS:
		var v = s.get(ch) if s is Dictionary else null
		if v is PackedByteArray and (v as PackedByteArray).size() == Dirt.CELLS:
			out[ch] = v
		else:
			var fresh := PackedByteArray()
			fresh.resize(Dirt.CELLS)
			fresh.fill(roundi(BASE_GLOSS * 255.0) if ch == "g" else (1 if ch == "u" else 0))
			out[ch] = fresh
	return out


## Keeps a finish (channel -> PackedByteArray) on an item.
static func store(it: Dictionary, d: Dictionary) -> void:
	var keep := {}
	for ch in CHANNELS:
		var v = d.get(ch)
		if v is PackedByteArray and (v as PackedByteArray).size() == Dirt.CELLS:
			keep[ch] = (v as PackedByteArray).duplicate()
	it["shine"] = data({"shine": keep})


## A channel of a finish as levels 0..1.
static func levels(d: Dictionary, ch: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Dirt.CELLS)
	var v: PackedByteArray = d[ch]
	for i in Dirt.CELLS:
		out[i] = v[i] / 255.0
	return out


## How a part's finish is: {gloss, coat, residue (means over its regions with paint), burns,
## smears (regions)}.
static func part_stats(it: Dictionary) -> Dictionary:
	var d := data(it)
	var g: PackedByteArray = d["g"]
	var c: PackedByteArray = d["c"]
	var r: PackedByteArray = d["r"]
	var used: PackedByteArray = d["u"]
	var n := 0
	var sg := 0.0
	var sc := 0.0
	var sr := 0.0
	var burns := 0
	var smears := 0
	for i in Dirt.CELLS:
		if used[i] == 0:
			continue
		n += 1
		sg += g[i]
		sc += c[i]
		sr += r[i]
		if d["b"][i] >= roundi(BURN_AT * 255.0):
			burns += 1
		if d["s"][i] >= roundi(SMEAR_AT * 255.0):
			smears += 1
	if n == 0:
		return {"gloss": BASE_GLOSS, "coat": 0.0, "residue": 0.0, "burns": 0, "smears": 0}
	return {"gloss": sg / (255.0 * n), "coat": sc / (255.0 * n), "residue": sr / (255.0 * n), "burns": burns, "smears": smears}


## The ceramic coat on a part, 0..1 (what keeps the dirt off it).
static func coat_of(it: Dictionary) -> float:
	return float(part_stats(it)["coat"]) if has(it) else 0.0


## How much of the road dirt a part's coat keeps off (Dirt.accrue's `protect`).
static func dirt_protect(it: Dictionary) -> float:
	return clampf(DIRT_SHED / 0.6 * coat_of(it), 0.0, 1.0)


## How much quicker the pressure washer gets a part clean (1 with no coat).
static func wash_mult(it: Dictionary) -> float:
	return 1.0 + WASH_BOOST * coat_of(it)


## A ride of `km` wears a part's coat thinner and fades its gloss back towards BASE_GLOSS.
static func ride_wear(it: Dictionary, km: float) -> void:
	if not has(it) or km <= 0.0:
		return
	var d := data(it)
	var coat_k := km / COAT_LIFE_KM
	var g: PackedByteArray = d["g"]
	var c: PackedByteArray = d["c"]
	var changed := false
	for i in Dirt.CELLS:
		var cv := c[i] / 255.0
		var gv := g[i] / 255.0
		var ncv := maxf(0.0, cv - coat_k)
		var ngv := gv
		if gv > BASE_GLOSS:
			ngv = maxf(BASE_GLOSS, gv - km / GLOSS_LIFE_KM * (1.0 - 0.7 * cv))
		# Kept as fractions, not bytes, a short ride's wear isn't lost to rounding.
		var cb := _dither(ncv, it, i, 0)
		var gb := _dither(ngv, it, i, 1)
		if cb != c[i] or gb != g[i]:
			c[i] = cb
			g[i] = gb
			changed = true
	if changed:
		d["g"] = g
		d["c"] = c
		it["shine"] = d
	# What's not been stored yet carries over to the next ride.
	it["shine_km"] = fmod(float(it.get("shine_km", 0.0)) + km, 1000.0)


## A level as a byte, rounded up or down by how far the miles have got through it so a lot of
## short rides wear it as one long one would (`k`: which channel, so they don't step together).
static func _dither(v: float, it: Dictionary, i: int, k: int) -> int:
	var raw := clampf(v, 0.0, 1.0) * 255.0
	var frac := raw - floorf(raw)
	var t := fposmod(float(it.get("shine_km", 0.0)) * 0.37 + i * 0.618 + k * 0.3, 1.0)
	return clampi(int(floorf(raw)) + (1 if frac > t else 0), 0, 255)


## Fresh paint (or primer) over a part: its old finish goes with it.
static func repainted(it: Dictionary) -> void:
	it.erase("shine")
	it.erase("shine_km")


## A line for the part's info: "Gloss 84%  ·  ceramic coat 90%  ·  1 burn-through", or "".
static func part_line(it: Dictionary, slot: String) -> String:
	if not is_panel(slot) or not has(it):
		return ""
	var st := part_stats(it)
	var bits := ["Gloss %d%%" % roundi(float(st["gloss"]) * 100.0)]
	if float(st["coat"]) > 0.02:
		bits.append("ceramic coat %d%%" % roundi(float(st["coat"]) * 100.0))
	if float(st["residue"]) > 0.02:
		bits.append("coat residue to buff off")
	if int(st["smears"]) > 0:
		bits.append("%d smear%s" % [int(st["smears"]), "" if int(st["smears"]) == 1 else "s"])
	if int(st["burns"]) > 0:
		bits.append("BURNT THROUGH in %d place%s" % [int(st["burns"]), "" if int(st["burns"]) == 1 else "s"])
	return "  ·  ".join(bits)


# ---------------------------------------------------------------------------- a bike's finish

## The panels on a bike: [item ids], in PANELS order.
static func panels_of(bike_id: int) -> Array[int]:
	var out: Array[int] = []
	for slot in PANELS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			out.append(id)
	return out


## How a bike's paintwork is: {clean (1 - its dirt), gloss, coat, residue (means over its
## panels), burns, smears (regions, all told), panels: [{slot, name, item, gloss, coat, burns,
## smears}], worst (the least glossy panel's gloss)}.
static func bike_stats(bike_id: int) -> Dictionary:
	var out := {"clean": 1.0 - Shed._bike_dirt(bike_id) if Shed.bikes.has(bike_id) else 0.0, "gloss": BASE_GLOSS, "coat": 0.0,
		"residue": 0.0, "burns": 0, "smears": 0, "panels": [], "worst": BASE_GLOSS}
	var ids := panels_of(bike_id)
	if ids.is_empty():
		return out
	var sg := 0.0
	var sc := 0.0
	var sr := 0.0
	var worst := 1.0
	for id in ids:
		var it: Dictionary = Shed.items[id]
		var st := part_stats(it)
		sg += float(st["gloss"])
		sc += float(st["coat"])
		sr += float(st["residue"])
		worst = minf(worst, float(st["gloss"]))
		out["burns"] = int(out["burns"]) + int(st["burns"])
		out["smears"] = int(out["smears"]) + int(st["smears"])
		var slot := _slot_on(bike_id, id)
		(out["panels"] as Array).append({"slot": slot, "name": PartsDB.slot_name(slot), "item": id, "gloss": float(st["gloss"]),
			"coat": float(st["coat"]), "burns": int(st["burns"]), "smears": int(st["smears"])})
	out["gloss"] = sg / ids.size()
	out["coat"] = sc / ids.size()
	out["residue"] = sr / ids.size()
	out["worst"] = worst
	return out


static func _slot_on(bike_id: int, id: int) -> String:
	for slot in PANELS:
		if Shed.item_on(bike_id, slot) == id:
			return slot
	return ""


## A line for the bike's info: "Paintwork: gloss 84%  ·  ceramic coat 90%", or "" for a bike
## nobody's detailed.
static func bike_line(bike_id: int) -> String:
	var ids := panels_of(bike_id)
	if not ids.any(func(id): return has(Shed.items[id])):
		return ""
	var st := bike_stats(bike_id)
	var bits := ["Paintwork: gloss %d%%" % roundi(float(st["gloss"]) * 100.0)]
	if float(st["coat"]) > 0.02:
		bits.append("ceramic coat %d%%" % roundi(float(st["coat"]) * 100.0))
	if int(st["smears"]) > 0:
		bits.append("%d smear%s" % [int(st["smears"]), "" if int(st["smears"]) == 1 else "s"])
	if int(st["burns"]) > 0:
		bits.append("burnt through in %d place%s" % [int(st["burns"]), "" if int(st["burns"]) == 1 else "s"])
	return "  ·  ".join(bits)


## What a bike's paintwork adds to its price, as a share (see Money.clean_bonus): up to
## BONUS_GLOSS for a deep gloss and BONUS_COAT for a full coat, less BURN_COST a burnt panel.
static func shine_bonus(bike_id: int) -> float:
	var ids := panels_of(bike_id)
	if not ids.any(func(id): return has(Shed.items[id])):
		return 0.0
	var st := bike_stats(bike_id)
	var burnt := 0
	for p in st["panels"]:
		if int(p["burns"]) > 0:
			burnt += 1
	var gloss := clampf((float(st["gloss"]) - BASE_GLOSS) / (1.0 - BASE_GLOSS), 0.0, 1.0)
	var smear_k := 1.0 if int(st["smears"]) == 0 else 0.5
	return BONUS_GLOSS * gloss + BONUS_COAT * clampf(float(st["coat"]), 0.0, 1.0) * smear_k - BURN_COST * burnt


## A short signature of a bike's finish, to know when to redraw it.
static func sig_of_bike(bike_id: int) -> String:
	var parts := PackedStringArray()
	for id in panels_of(bike_id):
		var it: Dictionary = Shed.items[id]
		if has(it):
			parts.append("%d:%d" % [id, hash(it["shine"])])
	return ",".join(parts)


## Every detailed panel's finish on a bike: slot -> its finish (see data).
static func of_bike(bike_id: int) -> Dictionary:
	var out := {}
	for slot in PANELS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id) and has(Shed.items[id]):
			out[slot] = data(Shed.items[id])
	return out


## Whether a bike's panels are clean enough to polish.
static func clean_enough(bike_id: int) -> bool:
	for id in panels_of(bike_id):
		if float(Shed.items[id].get("dirt", 0.0)) > 0.08:
			return false
	return true


# ---------------------------------------------------------------------------- steps

## How far along a step a bike is, 0..1: "wash" its cleanliness up to CLEAN_GOOD, "polish" its
## gloss from dull up to GLOSS_GOOD (nothing while any of it's burnt through), "coat" its coat up
## to COAT_GOOD (and buffed off: residue and smears hold it back).
static func step_progress(bike_id: int, step: String) -> float:
	if not Shed.bikes.has(bike_id):
		return 0.0
	var st := bike_stats(bike_id)
	match step:
		"wash":
			return clampf((float(st["clean"]) - 0.4) / (CLEAN_GOOD - 0.4), 0.0, 1.0)
		"polish":
			if int(st["burns"]) > 0:
				return 0.0
			var p := clampf((float(st["gloss"]) - 0.3) / (GLOSS_GOOD - 0.3), 0.0, 1.0)
			return p if float(st["worst"]) >= GLOSS_PANEL else minf(p, 0.95)
		"coat":
			var p := clampf(float(st["coat"]) / COAT_GOOD, 0.0, 1.0)
			return p if int(st["smears"]) == 0 and float(st["residue"]) < 0.02 else minf(p, 0.9)
	return 0.0


static func step_done(bike_id: int, step: String) -> bool:
	return step_progress(bike_id, step) >= 0.999


## The first step on a list a bike still needs (in order), or "" when it's all done.
static func next_step(bike_id: int, steps: Array) -> String:
	for s in steps:
		if not step_done(bike_id, str(s)):
			return str(s)
	return ""


## How each step of a list stands on a bike, plus the no-burn-through check when it's polished:
## [{step, text, done, have}] (what a detailing contract's handover checks).
static func check_steps(bike_id: int, steps: Array) -> Array:
	var rows := []
	for s in steps:
		rows.append(eval_step(bike_id, str(s)))
	if steps.has("polish"):
		rows.append(eval_step(bike_id, "no_burn"))
	return rows


## One step's line: {step, text, done, have}.
static func eval_step(bike_id: int, step: String) -> Dictionary:
	var st := bike_stats(bike_id)
	var row := {"step": step, "text": step_text(step), "done": false, "have": ""}
	match step:
		"wash":
			row["done"] = float(st["clean"]) >= CLEAN_GOOD - 0.0001
			row["have"] = "%d%% clean" % floori(float(st["clean"]) * 100.0)
		"polish":
			row["done"] = float(st["gloss"]) >= GLOSS_GOOD - 0.0001 and float(st["worst"]) >= GLOSS_PANEL - 0.0001
			row["have"] = "gloss %d%%" % floori(float(st["gloss"]) * 100.0)
			if float(st["worst"]) < GLOSS_PANEL:
				row["have"] += ", a panel still dull"
		"coat":
			row["done"] = float(st["coat"]) >= COAT_GOOD - 0.0001 and int(st["smears"]) == 0 and float(st["residue"]) < 0.02
			row["have"] = "coat %d%%" % floori(float(st["coat"]) * 100.0)
			if float(st["residue"]) >= 0.02:
				row["have"] += ", residue to buff off"
			if int(st["smears"]) > 0:
				row["have"] += ", %d smear%s" % [int(st["smears"]), "" if int(st["smears"]) == 1 else "s"]
		"no_burn":
			row["done"] = int(st["burns"]) == 0
			row["have"] = "none" if int(st["burns"]) == 0 else "burnt through in %d place%s" % [int(st["burns"]),
				"" if int(st["burns"]) == 1 else "s"]
	return row


## What a step asks for, for a contract's checklist.
static func step_text(step: String) -> String:
	match step:
		"wash":
			return "Washed clean (at least %d%%)" % roundi(CLEAN_GOOD * 100.0)
		"polish":
			return "Paintwork polished to a deep gloss (at least %d%%, every panel)" % roundi(GLOSS_GOOD * 100.0)
		"coat":
			return "Ceramic coated (at least %d%%), buffed off with no smears" % roundi(COAT_GOOD * 100.0)
		"no_burn":
			return "No burn-through on the paint"
	return step


## The AI's (or anyone's) way through a step without the mini game, on the host: does `amount`
## (1.0 is a few minutes' work) of `step` on a bike, as well as `skill` (0 a beginner .. 1 an
## expert) does it: "wash" takes the dirt off every part, "polish" brings every panel's gloss up
## (a beginner sometimes burns through), "coat" lays the ceramic coat on and buffs it off (a
## beginner sometimes leaves a smear). Returns the step's progress after it (step_progress).
static func work_step(bike_id: int, step: String, amount: float, skill := 0.5) -> float:
	if not Shed.bikes.has(bike_id) or amount <= 0.0:
		return step_progress(bike_id, step)
	skill = clampf(skill, 0.0, 1.0)
	var rate := clampf(amount * STEP_RATE * (0.5 + skill), 0.0, 1.0)
	var rng: RandomNumberGenerator = Shed._rng
	match step:
		"wash":
			for slot in PartsDB.SLOTS:
				var id := Shed.item_on(bike_id, slot)
				if id == 0 or not Shed.items.has(id):
					continue
				var it: Dictionary = Shed.items[id]
				var lv := Dirt.cells(it, slot)
				var k := 1.0 - minf(1.0, rate * 1.6 * wash_mult(it))
				for i in Dirt.CELLS:
					lv[i] = 0.0 if lv[i] * k < Dirt.CLEAN * 0.5 else lv[i] * k
				Dirt.store(it, lv)
		"polish":
			for id in panels_of(bike_id):
				var it: Dictionary = Shed.items[id]
				var d := data(it)
				var g: PackedByteArray = d["g"]
				var c: PackedByteArray = d["c"]
				var sm: PackedByteArray = d["s"]
				var r: PackedByteArray = d["r"]
				var b: PackedByteArray = d["b"]
				var cut := 1.0 - minf(1.0, rate * 2.0)
				for i in Dirt.CELLS:
					var gv := g[i] / 255.0
					g[i] = clampi(roundi((gv + (1.0 - gv) * rate * 1.5) * 255.0), 0, 255)
					# Polishing cuts off any coat and smear there.
					c[i] = roundi(c[i] * cut)
					sm[i] = roundi(sm[i] * cut)
					r[i] = 0
				if rng.randf() < RISK * (1.0 - skill) * amount:
					var at := rng.randi() % Dirt.CELLS
					b[at] = 255
					g[at] = 0
				it["shine"] = {"g": g, "b": b, "c": c, "r": r, "s": sm, "u": d["u"]}
		"coat":
			for id in panels_of(bike_id):
				var it: Dictionary = Shed.items[id]
				var d := data(it)
				var c: PackedByteArray = d["c"]
				var r: PackedByteArray = d["r"]
				var sm: PackedByteArray = d["s"]
				for i in Dirt.CELLS:
					var cv := c[i] / 255.0
					c[i] = clampi(roundi((cv + (1.0 - cv) * rate * 1.5) * 255.0), 0, 255)
					r[i] = 0
				if rng.randf() < RISK * (1.0 - skill) * amount:
					sm[rng.randi() % Dirt.CELLS] = 200
				it["shine"] = {"g": d["g"], "b": d["b"], "c": c, "r": r, "s": sm, "u": d["u"]}
	Shed._mark_dirty()
	return step_progress(bike_id, step)


# ---------------------------------------------------------------------------- requests

static func check(_peer: int, action: Dictionary) -> String:
	var bike := int(action.get("bike", 0))
	if not Shed.bikes.has(bike):
		return "That bike has gone."
	if int(Shed.bikes[bike].get("rider", 0)) != 0:
		return "Someone is riding that bike."
	match str(action.get("a", "")):
		"shine_cells", "shine_start":
			if not Wash.reaches((Shed.bikes[bike]["xf"] as Transform3D).origin):
				return NO_REACH
			if not (action.get("parts", {}) is Dictionary) or (action.get("parts", {}) as Dictionary).size() > PANELS.size():
				return "Nothing was polished."
		"shine_step":
			if not STEPS.has(str(action.get("step", ""))):
				return "There's no step like that."
		_:
			return "There's nothing like that to do."
	return ""


static func apply(peer: int, action: Dictionary) -> String:
	var bike := int(action["bike"])
	match str(action.get("a", "")):
		"shine_start":
			for id in panels_of(bike):
				if not has(Shed.items[id]):
					store(Shed.items[id], data(Shed.items[id]))
			return ""
		"shine_cells":
			return _cells(peer, bike, action["parts"])
		"shine_step":
			work_step(bike, str(action["step"]), clampf(float(action.get("amount", 1.0)), 0.0, 5.0), float(action.get("skill", 0.5)))
	return ""


## The mini game's regions in from `peer`: kept on each panel, with XP for a panel brought to a
## deep gloss or fully coated (once each), and a word when the clear coat's burnt through.
static func _cells(peer: int, bike: int, parts: Dictionary) -> String:
	var said := ""
	for key in parts:
		var id := int(key)
		if not Shed.items.has(id) or Shed._bike_of(id) != bike or not (parts[key] is Dictionary):
			continue
		var it: Dictionary = Shed.items[id]
		var slot := _slot_on(bike, id)
		if slot == "":
			continue
		var before := part_stats(it)
		var d := data(it)
		for ch in CHANNELS:
			var v = parts[key].get(ch)
			if v is PackedByteArray and (v as PackedByteArray).size() == Dirt.CELLS:
				d[ch] = (v as PackedByteArray).duplicate()
		it["shine"] = d
		var after := part_stats(it)
		if float(after["gloss"]) >= GLOSS_GOOD and float(before["gloss"]) < GLOSS_GOOD and int(after["burns"]) == 0:
			Shed._xp(peer, "polish_panel", 1.0, "item:%d" % id)
		if float(after["coat"]) >= COAT_GOOD and float(before["coat"]) < COAT_GOOD and int(after["smears"]) == 0:
			Shed._xp(peer, "ceramic_panel", 1.0, "item:%d" % id)
		if int(after["burns"]) > int(before["burns"]):
			said = "Burnt through the clear coat on the %s! That patch needs a respray." % PartsDB.slot_name(slot).to_lower()
	return said
