class_name ContractBatch
extends RefCounted
## Batch prep orders (the "batch" contract kind, see Contracts): a trade customer wants a run of
## identical prepared parts, say ten 750 cc V-twins blasted back to bare metal and making 67 hp,
## or twenty tanks in Iridium Orange, lacquered. Most send their donor parts, crated up in the
## delivery area (as many crates as there's room for, the rest as room is made); some want you to
## find the parts yourself and pay more for it. Each finished part goes on the dispatch pallet by
## the delivery area: put it down there and it's checked against the spec there and then (an
## engine is run on the bench for its power: complete, with oil in it), taken if it's right
## (paid for, part by part, and counted: 7 of 10) and left where it is with what's wrong if not.
## All of them by the deadline earns the bonus; late parts pay less. The order closes when the
## last one is in, or when it's closed early from the Contracts card with what's been sent.
##
## The spec is a goal on the job ({t: "batch", item, ...}): for an engine {item: "engine",
## part, layout, finish, hp, tol[, ups]}; for paint {item: tank / front_mudguard / side_panels,
## lib, name, rgb, effect, sheen, lacquer, q, min}. The job keeps n, per (pay a part), bonus,
## sent, paid, owed (donors still to deliver) and donor (the donor part).

const TRADE := ["Midland Custom Cycles", "Northern Motorcycle Spares", "Cafe Racer Supply Co.", "Thames Valley Bikes",
	"Red Rose Classics", "Severn Speed Shop", "Pennine Motorcycle Works", "Old Bike Mart", "Fenland Choppers", "Black Country Bobbers"]
## The engines trade customers send as donors (and want back prepared).
const ENGINES: Array[String] = ["vtwin_750", "vtwin_900", "vtwin_1000", "parallel_750", "single_450", "triple_850", "boxer_800",
	"inline_600", "twin_500"]
## How an engine has to be finished: names, the level they're asked for from, and what each adds to a part's pay.
const FINISHES := {"bare": {"name": "in bare metal (blasted all over, no coat)", "level": 1, "pay": 20},
	"clear": {"name": "in bare metal under clear lacquer", "level": 1, "pay": 35},
	"enamel_black": {"name": "in crinkle black engine enamel", "level": 3, "pay": 45},
	"enamel_silver": {"name": "in silver engine enamel", "level": 3, "pay": 45}}
## A stage one engine: these ancillaries on, for more power (asked for from STAGE_LEVEL).
const STAGE_UPS := {"air_filter": "cotton_gauze", "spark_plugs": "racing_iridium"}
const STAGE_LEVEL := 6
const HP_TOL := 3.0
## Painted parts: the kinds and the donor parts that come for each.
const PAINT_KINDS := {"tank": "tanks", "front_mudguard": "front mudguards", "side_panels": "sets of side panels"}
const PAINT_DONORS := {"tank": ["peanut_9", "cafe_15", "sport_17", "teardrop_14", "enduro_12", "touring_23"],
	"front_mudguard": ["road_hugger", "bobbed_steel", "valanced_painted_guard", "mx_high_fender"],
	"side_panels": ["triangle_classic", "oval_number"]}
## The library colour Simon asked for by name: trade customers often want it.
const FAVOURITE := "custom_iridium_orange"
## The dispatch pallet (x/z), against the paint shop's front wall just behind the delivery area
## (under the high end of the lounge's outside stairs, once they're built): finished parts go
## down on it.
const DISPATCH := Rect2(7.7, 70.45, 2.4, 1.8)
const LATE_CUT := 0.15          # a part's pay lost for each day late (to half at most)
const BONUS_SHARE := 0.25       # the bonus for the lot on time, of what the parts pay


# ---------------------------------------------------------------------------- offers

## A batch order for a garage at XP `level`: {kind, trade, goals [spec], n, per, bonus, supply,
## donor, pay (everything, bonus and all), days, blurb, bike_name, budget}.
static func make_offer(rng: RandomNumberGenerator, level: int) -> Dictionary:
	var o := {"kind": "batch", "budget": 0, "trade": str(TRADE[rng.randi() % TRADE.size()])}
	var spec := engine_spec(rng, level) if rng.randf() < 0.5 else paint_spec(rng, level)
	var engine := str(spec["item"]) == "engine"
	var n := clampi(rng.randi_range(2, 4) + level / 2, 3, 10) if engine else clampi(rng.randi_range(3, 6) + level, 5, 20)
	var donors := rng.randf() < 0.75
	var per := 0.0
	var donor := ""
	if engine:
		donor = str(spec["part"])
		per = 70.0 + float(spec["hp"]) * 0.5 + float(FINISHES[spec["finish"]]["pay"])
		for slot in spec.get("ups", {}):
			per += Contracts.est_cost(str(spec["ups"][slot]))
		if not donors:
			per += Contracts.est_cost(donor) * 0.8
	else:
		var options: Array = PAINT_DONORS[spec["item"]]
		donor = str(options[rng.randi() % options.size()])
		per = 30.0 + 400.0 * float(PaintMix.EFFECTS.get(str(spec["effect"]), {}).get("value", 0.0)) + (10.0 if spec["lacquer"] else 0.0)
		if not donors:
			per += Contracts.est_cost(donor) * 0.6
	per *= 1.0 + 0.03 * level
	o["goals"] = [spec]
	o["n"] = n
	o["per"] = int(snappedi(roundi(per), 5))
	o["bonus"] = int(snappedi(roundi(o["per"] * n * BONUS_SHARE), 10))
	o["pay"] = int(o["per"]) * n + int(o["bonus"])
	o["supply"] = "donors" if donors else "source"
	o["donor"] = donor
	o["days"] = 2 + ceili(n * (0.7 if engine else 0.25))
	o["parts"] = {}
	var what := short_name(spec, n)
	o["bike_name"] = "%d %s for %s" % [n, what, o["trade"]]
	o["blurb"] = ("We've a run of %s to get out. I'll send the donors over crated up: get them to spec and on the dispatch pallet." if donors
		else "We need %s, all the same, and we've no donors to send: find the parts yourself and get them to spec. We pay for the parts in the price.") % what
	return o


## An engine spec: a donor engine (its layout), the finish, and the power it has to make on the
## bench, as a fresh one with stock ancillaries makes (or, from STAGE_LEVEL, with STAGE_UPS on).
static func engine_spec(rng: RandomNumberGenerator, level: int) -> Dictionary:
	var part := str(ENGINES[rng.randi() % ENGINES.size()])
	var finishes: Array = FINISHES.keys().filter(func(f): return int(FINISHES[f]["level"]) <= level)
	var spec := {"t": "batch", "item": "engine", "part": part, "layout": str(PartsDB.get_part(part).get("layout", "")),
		"finish": str(finishes[rng.randi() % finishes.size()]), "tol": HP_TOL}
	var ups := {}
	if level >= STAGE_LEVEL and rng.randf() < 0.4:
		ups = STAGE_UPS.duplicate()
		spec["ups"] = ups
	spec["hp"] = float(roundi(stock_hp(part, ups)))
	return spec


## The power a fresh `part` engine makes on the bench with stock ancillaries (and `ups` on).
static func stock_hp(part: String, ups := {}) -> float:
	var b: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	b["engine"] = part
	b.merge(ups, true)
	return BikeBuild.new(b, {}).hp()


## A paint spec: a library colour the garage can mix at `level` (Iridium Orange often), in its
## factory sheen (satin or matt need a flattened lacquer over it), lacquered or not, to a finish.
static func paint_spec(rng: RandomNumberGenerator, level: int) -> Dictionary:
	var kinds: Array = ["tank", "tank", "tank", "front_mudguard", "side_panels"]
	var item := str(kinds[rng.randi() % kinds.size()])
	var can: Array = PaintMix.library().filter(func(e): return int(PaintMix.EFFECTS.get(str(e["effect"]), {}).get("level", 99)) <= level)
	var e: Dictionary = PaintMix.library_entry(FAVOURITE)
	if (e.is_empty() or rng.randf() > 0.3) and not can.is_empty():
		e = can[rng.randi() % can.size()]
	var c: Color = e.get("rgb", Color(0.91, 0.37, 0.1))
	var sheen := str(e.get("finish", "gloss"))
	return {"t": "batch", "item": item, "lib": str(e.get("id", "")), "name": PaintMix.library_name(e), "rgb": c.to_html(false),
		"effect": "solid" if str(e.get("effect", "solid")) == "lacquer" else str(e.get("effect", "solid")), "sheen": sheen,
		"lacquer": sheen != "gloss" or rng.randf() < 0.5, "q": [0.8, 0.85, 0.9][clampi(level / 5, 0, 2)], "min": Contracts.MATCH_MIN}


## "750 cc V-twins" or "tanks in Iridium Orange", for the order's name.
static func short_name(spec: Dictionary, n := 2) -> String:
	if str(spec.get("item", "")) == "engine":
		return "%s%s" % [PartsDB.part_name(str(spec.get("part", ""))), "s" if n != 1 else ""]
	return "%s in %s" % [PAINT_KINDS.get(str(spec.get("item", "")), "parts"), str(spec.get("name", "")).trim_prefix("Custom paint ")]


## What a spec asks for, in a line for the offer card.
static func spec_text(spec: Dictionary, n := 0) -> String:
	var count := "%d x " % n if n > 0 else ""
	if str(spec.get("item", "")) == "engine":
		var ups := ""
		if spec.get("ups") is Dictionary and not (spec["ups"] as Dictionary).is_empty():
			ups = ", stage one (%s)" % ", ".join((spec["ups"] as Dictionary).values().map(func(p): return PartsDB.part_name(str(p)).to_lower()))
		return "%s%s %s, complete with oil in, making %d hp (within %d hp on the bench)%s" % [count, PartsDB.part_name(str(spec["part"])),
			FINISHES.get(str(spec.get("finish", "bare")), {}).get("name", ""), roundi(float(spec["hp"])), roundi(float(spec.get("tol", HP_TOL))), ups]
	var sheen := str(spec.get("sheen", "gloss"))
	var fx := str(spec.get("effect", "solid"))
	return "%s%s in %s%s, %s%s, finished to %d%% or better" % [count, str(PAINT_KINDS.get(str(spec["item"]), "parts")).capitalize(),
		spec.get("name", ""), "" if fx == "solid" else " (%s)" % PaintMix.effect_name(fx).to_lower(), sheen,
		" under lacquer" if spec.get("lacquer", false) else "", roundi(float(spec.get("q", 0.85)) * 100.0)]


# ---------------------------------------------------------------------------- the job

## A batch job from an accepted offer (Contracts._accept fills in the rest).
static func start(job: Dictionary, offer: Dictionary) -> void:
	job["bike"] = 0
	job["n"] = int(offer.get("n", 1))
	job["per"] = int(offer.get("per", 0))
	job["bonus"] = int(offer.get("bonus", 0))
	job["trade"] = str(offer.get("trade", ""))
	job["donor"] = str(offer.get("donor", ""))
	job["supply"] = str(offer.get("supply", "donors"))
	job["sent"] = 0
	job["paid"] = 0
	job["owed"] = job["n"] if job["supply"] == "donors" else 0
	deliver(job)


## Delivers as many of the job's donor parts as there's room for in the delivery area, crated.
## Returns how many came.
static func deliver(job: Dictionary) -> int:
	var came := 0
	while int(job.get("owed", 0)) > 0:
		var id := _donor(job)
		if not Shed._deliver(id):
			Shed._erase_item(id)
			break
		job["owed"] = int(job["owed"]) - 1
		came += 1
	return came


## One donor part, in a crate: an engine with its stock ancillaries, grimy, rusty and tired and
## drained for the trip; a panel in tired old paint.
static func _donor(job: Dictionary) -> int:
	var rng: RandomNumberGenerator = Shed._rng
	var part := str(job.get("donor", ""))
	var id := 0
	if PartsDB.kind_of(part) == "engine":
		id = Shed._new_item(part, rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.9), rng.randf_range(0.25, 0.55))
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := Shed._new_item(str(PartsDB.DEFAULT_BUILD[slot]), rng.randf_range(0.2, 0.5), rng.randf_range(0.5, 0.9),
				rng.randf_range(0.3, 0.7))
			Shed._move(sub, "engine", id)
			Shed.items[id]["slots"][slot] = sub
			Shed.items[id]["bolted"][slot] = true
		if Shed.items[id].has("fluid"):
			Shed.items[id]["fluid"]["litres"] = 0.0
	else:
		var old: Color = Shed.PAINTS[rng.randi() % Shed.PAINTS.size()]
		id = Shed._new_item(part, rng.randf_range(0.0, 0.12), rng.randf_range(0.3, 0.6), rng.randf_range(0.05, 0.2), old.darkened(0.15))
	Shed.items[id]["batch"] = int(job["id"])
	Shed.items[id]["boxed"] = true
	return id


## The power an engine makes on the bench (hp): the engine and the ancillaries fitted to it, as
## they are, in a standard rolling chassis. 0 if it isn't a whole engine with everything bolted up.
static func bench_hp(engine_id: int) -> float:
	if not Shed.is_engine(engine_id) or not bench_ready(engine_id):
		return 0.0
	var b: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	var cond := {}
	b["engine"] = str(Shed.items[engine_id]["part"])
	cond["engine"] = Shed.condition_of(Shed.items[engine_id])
	for slot in PartsDB.ENGINE_SLOTS:
		var sub := Shed.engine_item(engine_id, slot)
		b[slot] = str(Shed.items[sub]["part"])
		cond[slot] = Shed.condition_of(Shed.items[sub])
	return BikeBuild.new(b, cond).hp()


## Whether an engine is whole: every ancillary on and bolted.
static func bench_ready(engine_id: int) -> bool:
	return Shed.engine_missing(engine_id).is_empty() and PartsDB.ENGINE_SLOTS.all(func(s): return Shed.engine_bolted(engine_id, s))


## How a part measures up to a spec: {ok, have (what it is, in a few words), why (what's wrong)}.
static func check_item(spec: Dictionary, item_id: int) -> Dictionary:
	if not Shed.items.has(item_id):
		return {"ok": false, "have": "gone", "why": ["it's gone"]}
	var it: Dictionary = Shed.items[item_id]
	var why: Array[String] = []
	if it.get("boxed", false):
		return {"ok": false, "have": "still in its crate", "why": ["unpack it and do the work first"]}
	if str(spec.get("item", "")) == "engine":
		if not Shed.is_engine(item_id):
			return {"ok": false, "have": PartsDB.part_name(str(it["part"])), "why": ["it's not an engine"]}
		var part := str(it["part"])
		if str(PartsDB.get_part(part).get("layout", "")) != str(spec.get("layout", "")) or (spec.has("part") and part != str(spec["part"])):
			why.append("the wrong engine (%s)" % PartsDB.part_name(part))
		var hp := bench_hp(item_id)
		var finish := _engine_finish(item_id)
		if not bench_ready(item_id):
			why.append("not complete: every ancillary on and bolted")
		elif absf(hp - float(spec.get("hp", 0.0))) > float(spec.get("tol", HP_TOL)) + 0.05:
			why.append("%d hp on the bench, %d wanted" % [roundi(hp), roundi(float(spec["hp"]))])
		for slot in spec.get("ups", {}):
			var sub := Shed.engine_item(item_id, str(slot))
			if sub == 0 or str(Shed.items[sub]["part"]) != str(spec["ups"][slot]):
				why.append("needs %s" % PartsDB.part_name(str(spec["ups"][slot])).to_lower())
		if finish != str(spec.get("finish", "bare")):
			why.append("%s, not %s" % [_finish_word(finish), _finish_word(str(spec.get("finish", "bare")))])
		return {"ok": why.is_empty(), "have": "%d hp, %s" % [roundi(hp), _finish_word(finish)], "why": why}
	if PartsDB.kind_of(str(it["part"])) != str(spec.get("item", "")):
		return {"ok": false, "have": PartsDB.part_name(str(it["part"])), "why": ["not one of the %s" % PAINT_KINDS.get(str(spec.get("item", "")), "parts")]}
	if it.get("primer_top", false):
		return {"ok": false, "have": "grey primer", "why": ["only in primer"]}
	var m := Contracts.tank_match(it, spec)
	var q := float(it.get("paint_quality", 0.0)) if it.has("paint_quality") else 0.0
	var sheen := PaintMix.sheen_name(float(it.get("flat", 0.0)))
	var lacquered := it.has("flat") or Shed.LACQUERS.has(str(it.get("coat", "")))
	if m < float(spec.get("min", Contracts.MATCH_MIN)) - 0.0001:
		why.append("%s match to %s" % [PaintMix.match_text(m), spec.get("name", "the colour")])
	if q < float(spec.get("q", 0.85)) - 0.0001:
		why.append("a %d%% finish, %d%% wanted" % [roundi(q * 100.0), roundi(float(spec.get("q", 0.85)) * 100.0)])
	if sheen != str(spec.get("sheen", "gloss")):
		why.append("%s, not %s" % [sheen, spec.get("sheen", "gloss")])
	if spec.get("lacquer", false) and not lacquered:
		why.append("no lacquer over it")
	return {"ok": why.is_empty(), "have": "%s match, %d%% finish, %s%s" % [PaintMix.match_text(m), roundi(q * 100.0), sheen,
		", lacquered" if lacquered else ""], "why": why}


## How an engine is finished all over: "bare", "clear" (bare under clear lacquer), an enamel's
## key, or "" (not blasted all over, or a mix).
static func _engine_finish(engine_id: int) -> String:
	var parts := Shed._blast_parts(engine_id)
	var coat := str(Shed.items[engine_id].get("coat", ""))
	if Shed.COATS.has(coat) and not Shed.LACQUERS.has(coat):
		# An enamel paints it: what's under it doesn't show.
		return coat if parts.all(func(id): return str(Shed.items[id].get("coat", "")) == coat) else ""
	if not parts.all(func(id): return Shed.blast_full(Shed.items[id])):
		return ""
	if coat == "":
		return "bare" if parts.all(func(id): return str(Shed.items[id].get("coat", "")) == "") else ""
	return "clear" if parts.all(func(id): return Shed.LACQUERS.has(str(Shed.items[id].get("coat", "")))) else ""


static func _finish_word(f: String) -> String:
	return {"bare": "bare metal", "clear": "lacquered bare metal", "enamel_black": "black enamel", "enamel_silver": "silver enamel"}.get(f,
		"not blasted all over")


## Where the dispatch pallet is (its middle on the ground).
static func pallet_at() -> Vector3:
	return Vector3(DISPATCH.get_center().x, 0.0, DISPATCH.get_center().y)


## Whether a loose part on the ground is on the dispatch pallet.
static func on_pallet(item_id: int) -> bool:
	var it: Dictionary = Shed.items.get(item_id, {})
	if str(it.get("at", "")) != "floor" or not (it.get("ref") is Transform3D):
		return false
	var o: Vector3 = (it["ref"] as Transform3D).origin
	return DISPATCH.grow(0.15).has_point(Vector2(o.x, o.z))


## The parts on the dispatch pallet now.
static func pallet_items() -> Array:
	return Shed.floor_items().filter(func(id): return on_pallet(int(id)))


## The parts a batch job's card shows the checks for: those on the pallet and, for an engine
## order, the engines on the stands (where they're built up and checked before they go).
static func checkable(job: Dictionary) -> Array:
	var out := pallet_items()
	var spec: Dictionary = (job.get("goals", [{}]) as Array)[0] if not (job.get("goals", []) as Array).is_empty() else {}
	if str(spec.get("item", "")) == "engine":
		for id in Shed.items:
			var it: Dictionary = Shed.items[id]
			if str(it["at"]) == "spot" and Shed.is_stand_spot(str(it["ref"])) and Shed.is_engine(int(id)):
				out.append(int(id))
	return out


## What a part dispatched now pays: less for each day late, to half at most.
static func part_pay(job: Dictionary) -> int:
	var late := maxi(0, ceili((Contracts.clock() - float(job.get("due", 0.0))) / Contracts.DAY))
	return roundi(float(job.get("per", 0)) * maxf(0.5, 1.0 - LATE_CUT * late))


## Host: takes every part on the pallet that's to spec for `job`, paying for each. Returns what
## to tell the player ("" if nothing was there to look at).
static func dispatch(peer: int, job: Dictionary, only := 0) -> String:
	var spec: Dictionary = job["goals"][0]
	var took := 0
	var paid := 0
	var wrong: Array[String] = []
	for id in pallet_items():
		if only != 0 and int(id) != only:
			continue
		if int(job.get("sent", 0)) >= int(job.get("n", 0)):
			break
		var r := check_item(spec, int(id))
		if not r["ok"]:
			if only != 0 or not wrong.size() > 2:
				wrong.append("%s: %s" % [Shed.item_title(int(id)), ", ".join(r["why"])])
			continue
		var pay := part_pay(job)
		_pay_part(peer, job, pay)
		Shed._erase_item(int(id))
		job["sent"] = int(job["sent"]) + 1
		job["paid"] = int(job.get("paid", 0)) + pay
		Shed._xp(peer, "contract_batch_part", 1.0, "item:%d" % int(id))
		took += 1
		paid += pay
	var text := ""
	if took > 0:
		text = "Dispatched to %s: %d of %d done (%s)." % [job.get("trade", job.get("customer", "")), int(job["sent"]), int(job["n"]),
			Contracts.money(paid)]
	if not wrong.is_empty():
		text += (" " if text != "" else "") + "Not to spec: " + "; ".join(wrong) + "."
	if int(job["sent"]) >= int(job["n"]):
		text += " " + finish(job)
	return text.strip_edges()


## A part's pay: the garage's, with WORKER_SHARE of it to whoever dispatched it.
static func _pay_part(peer: int, job: Dictionary, pay: int) -> void:
	var to_crew := roundi(pay * Contracts.WORKER_SHARE) if Shed.crew.has(peer) and Shed.has_method("pay_worker") else 0
	Contracts.credit_garage(pay - to_crew, "Batch order: %s" % job.get("title", ""))
	if to_crew > 0:
		Shed.call("pay_worker", peer, to_crew, "Batch order: %s" % job.get("title", ""))
	var w: Dictionary = job.get("workers", {})
	w[peer] = int(w.get(peer, 0)) + 1
	job["workers"] = w
	Contracts._st()["earned"] = int(Contracts._st()["earned"]) + pay


## What closing the order now would come to: {sent, n, paid, bonus, rep, sat, late, note}.
static func payout(job: Dictionary) -> Dictionary:
	var n := maxi(1, int(job.get("n", 1)))
	var sent := int(job.get("sent", 0))
	var late := maxi(0, ceili((Contracts.clock() - float(job.get("due", 0.0))) / Contracts.DAY))
	var all_in := sent >= n
	var bonus := int(job.get("bonus", 0)) if all_in and late == 0 else 0
	var sat := float(sent) / n
	var rep := int(Contracts.REP_GAIN.get("batch", 2)) if all_in else (0 if sat >= 0.5 else -1)
	if late > 0:
		rep -= 1
	var note := "All %d sent%s." % [n, ", on time: %s bonus" % Contracts.money(bonus) if bonus > 0 else ""] if all_in \
		else "%d of %d sent." % [sent, n]
	if late > 0:
		note += " %d day%s late." % [late, "" if late == 1 else "s"]
	return {"sent": sent, "n": n, "paid": int(job.get("paid", 0)), "bonus": bonus, "rep": rep, "sat": sat, "late": late,
		"total": int(job.get("paid", 0)) + bonus, "note": note, "labour": int(job.get("paid", 0)) + bonus, "parts": 0, "tip": 0,
		"over": 0, "spent": 0, "match_bonus": 0}


## Host: closes the order (every part in, or closed early): the bonus, the reputation and XP, and
## the donors that weren't used go back. Returns what to tell the crew.
static func finish(job: Dictionary) -> String:
	var pay := payout(job)
	if int(pay["bonus"]) > 0:
		Contracts.credit_garage(int(pay["bonus"]), "Batch order bonus: %s" % job.get("title", ""))
		Contracts._st()["earned"] = int(Contracts._st()["earned"]) + int(pay["bonus"])
	var crew_ids: Array = (job.get("workers", {}) as Dictionary).keys().filter(func(p): return Shed.crew.has(int(p)))
	if crew_ids.is_empty():
		crew_ids = [Shed.me()]
	for p in crew_ids:
		Shed._xp(int(p), "contract_batch", 0.3 + 0.7 * float(pay["sat"]), "job:%d" % int(job["id"]))
	# What's left of their donors goes back to them (not what's been built into a bike here).
	for id in Shed.items.keys():
		if Shed.items.has(id) and int(Shed.items[id].get("batch", 0)) == int(job["id"]) and str(Shed.items[id]["at"]) in ["floor", "spot", "held"]:
			Shed._erase_item(int(id))
	Contracts._finish(job, {"paid": int(pay["total"]), "sat": float(pay["sat"]), "late": int(pay["late"]), "rep": int(pay["rep"]),
		"note": str(pay["note"])})
	var text := "Order closed for %s: %s." % [job.get("trade", job.get("customer", "")), pay["note"]]
	if int(pay["bonus"]) > 0:
		text = "Order complete for %s: all %d in on time, %s bonus." % [job.get("trade", ""), int(pay["n"]), Contracts.money(int(pay["bonus"]))]
	return text


## The job's checklist row: {text, done, have}.
static func rows(job: Dictionary) -> Array:
	var spec: Dictionary = job["goals"][0] if not (job.get("goals", []) as Array).is_empty() else {}
	var sent := int(job.get("sent", 0))
	var n := int(job.get("n", 1))
	return [{"text": spec_text(spec, n), "done": sent >= n, "have": "%d/%d sent" % [sent, n]}]
