class_name ContractTestRide
extends RefCounted
## Manufacturer test rides (the "test_ride" contract kind, see Contracts): a manufacturer's rep
## rides their new prototype in to the sales office car park and asks the shed to put it through
## a set test (so many kilometres, a top speed run, hard braking, a good lean, a dyno pull) and
## write it up: a rating out of five for handling, brakes, power, comfort and looks, and the
## issues the rider noticed. The prototype is a whole bike built from parts in the brand's style,
## with one to three real faults built into it that the physics shows (a weave at speed from
## yokes with too much offset, a weak front brake, a flat spot in the power, a soft rear shock,
## an engine that runs hot). A report that spots them and rates the bike fairly earns a bonus on
## top of the fee. The test is checked against the ride telemetry: the rider's logger sends its
## peaks with the ride stats, and the host keeps the best of each on the job (see note_ride), so
## a test not ridden doesn't count. The prototype isn't the shed's: it can't be worked on, sold
## or stripped (see guard), and when the report's in and it's back in the car park the rep
## collects it and rides it away.
##
## Goals: {t: "ride_km", min}, {t: "ride_top", min}, {t: "ride_brake", min (g)}, {t: "ride_lean",
## min (degrees)}, {t: "ride_lap", road, n} (laps of a named route), {t: "ride_dyno"}, {t: "report"}.
## The job keeps log {km, top, brake, lean, wobble, laps, dyno0}, truth (the fair ratings), quirks, report {ratings, issues, by, score}.

## The manufacturers (names only), with the styles they build, their engines, a factory colour
## from the paint library, model names for the prototypes and the rep's jacket.
const BRANDS := {
	"Ducati": {"styles": ["sport", "cafe", "supermoto"], "engines": ["vtwin_900", "vtwin_1100"], "paint": "ducati_rosso_corsa",
		"models": ["Veloce", "Strada", "Fulgore"], "jacket": Color(0.75, 0.06, 0.05)},
	"Triumph": {"styles": ["cafe", "scrambler", "sport"], "engines": ["triple_850", "parallel_1200"], "paint": "triumph_jet_black",
		"models": ["Meriden", "Arrow", "Cotswold"], "jacket": Color(0.08, 0.08, 0.09)},
	"KTM": {"styles": ["supermoto", "adventure", "mx"], "engines": ["single_450", "vtwin_1000"], "paint": "ktm_orange",
		"models": ["Apex", "Ridge", "Rally X"], "jacket": Color(0.95, 0.42, 0.02)},
	"Honda": {"styles": ["sport", "tourer", "adventure"], "engines": ["inline_1000", "parallel_750"], "paint": "honda_hrc_red",
		"models": ["Aero", "Crest", "Vista"], "jacket": Color(0.8, 0.08, 0.1)},
	"Yamaha": {"styles": ["sport", "scrambler", "mx"], "engines": ["triple_850", "inline_1000"], "paint": "yamaha_racing_blue",
		"models": ["Kodo", "Arc", "Tempest"], "jacket": Color(0.1, 0.2, 0.65)},
	"BMW Motorrad": {"styles": ["tourer", "adventure"], "engines": ["boxer_1200", "boxer_1100"], "paint": "bmw_racing_blue",
		"models": ["RX", "GT", "Terra"], "jacket": Color(0.12, 0.3, 0.7)},
	"Kawasaki": {"styles": ["sport", "cafe"], "engines": ["inline_1000", "parallel_750"], "paint": "kawasaki_lime_green",
		"models": ["Raiden", "Kaze", "Ronin"], "jacket": Color(0.3, 0.7, 0.1)},
	"Harley-Davidson": {"styles": ["cruiser", "bobber", "chopper"], "engines": ["vtwin_1200"], "paint": "harley_vivid_black",
		"models": ["Ironclad", "Prairie", "Night Run"], "jacket": Color(0.1, 0.09, 0.08)},
	"Royal Enfield": {"styles": ["cafe", "scrambler"], "engines": ["single_450", "parallel_750"], "paint": "royal_enfield_desert_sand",
		"models": ["Ghat", "Himal", "Madras"], "jacket": Color(0.3, 0.32, 0.2)},
	"Aprilia": {"styles": ["sport", "supermoto"], "engines": ["vtwin_1100", "parallel_600"], "paint": "aprilia_black_flake",
		"models": ["Saetta", "Fulmine", "Vento"], "jacket": Color(0.15, 0.15, 0.16)},
}
## The faults a prototype can have, and what a rider ticks for each on the report. DECOYS are on
## the report too, but no prototype has them.
const ISSUES := {"weave": "Weaves or shakes its head at speed", "weak_front": "Weak, wooden front brake",
	"flat_spot": "Flat spot in the mid-range power", "soft_rear": "Soft, wallowy rear shock", "hot": "Runs hot"}
const DECOYS := {"clutch": "Clutch slips under power", "gearbox": "Gearbox misses shifts", "buzz": "Buzzes through the bars"}
const ISSUE_ORDER: Array[String] = ["weave", "weak_front", "flat_spot", "soft_rear", "hot", "clutch", "gearbox", "buzz"]
const RATINGS: Array[String] = ["handling", "brakes", "power", "comfort", "looks"]
const RATING_NAMES := {"handling": "Handling", "brakes": "Brakes", "power": "Power", "comfort": "Comfort", "looks": "Looks"}
## How much the report's score is the issues spotted (the rest is the ratings).
const ISSUE_WEIGHT := 0.6
const WEAVE_TRAIL := 0.045        # m: what the prototype's yokes bring its trail down to
const FLAT_DIP := 0.3
const FAST := 100.0               # km/h: a shake counts as a weave at speed from here
## The named route a test lap is ridden round (a closed road in WorldLayout.ROADS), and how many
## stretches of it the logger has to see the bike on for a lap to count.
const LAP_ROAD := "loop"
const LAP_SECTORS := 16
## Actions that change a bike: none of them on a prototype.
const NO_TOUCH: Array[String] = ["unbolt", "bolt", "remove", "install", "adjust_chain", "lighten", "paint", "prime", "coat", "scrap",
	"repair", "repair_many", "tune", "geo_save", "geo_blueprint", "rename_bike", "money_sell_bike", "sale_list", "drain", "lube",
	"blast", "blast_use", "start_build"]


# ---------------------------------------------------------------------------- offers

## A test ride offer for a garage at XP `level`: the brand's prototype (its parts, colour and
## faults), the tests, the fee and the report bonus.
static func make_offer(rng: RandomNumberGenerator, level: int) -> Dictionary:
	var brand := str(BRANDS.keys()[rng.randi() % BRANDS.size()])
	var b: Dictionary = BRANDS[brand]
	var style := str(b["styles"][rng.randi() % b["styles"].size()])
	var engine := str(b["engines"][rng.randi() % b["engines"].size()])
	var parts := Contracts.style_build(style)
	parts["engine"] = engine
	parts = _fed(parts)
	var quirks := _pick_quirks(parts, rng, clampi(1 + level / 6, 1, 3))
	parts = _quirk_parts(parts, quirks)
	var lib := PaintMix.library_entry(str(b["paint"]))
	var paint: Color = lib.get("rgb", Color(0.7, 0.1, 0.1))
	var cc := snappedi(roundi(float(PartsDB.get_part(engine).get("displacement", 0.0))), 50)
	var model := "%s %s %d" % [brand, str(b["models"][rng.randi() % b["models"].size()]), cc]
	var build := BikeBuild.new(PartsDB.sanitize_build(parts.duplicate()), {})
	var top := float(build.summary()["top_kmh"])
	var goals := [{"t": "ride_km", "min": float(clampi(8 + level, 8, 30))}]
	var extra := [{"t": "ride_top", "min": snappedf(minf(top * 0.8, 200.0), 5.0)},
		{"t": "ride_brake", "min": 0.55 if quirks.has("weak_front") else 0.75},
		{"t": "ride_lean", "min": 25.0 if style in ["cruiser", "bobber", "chopper"] else 35.0}, {"t": "ride_dyno"},
		{"t": "ride_lap", "road": LAP_ROAD, "n": 1 if level < 10 else 2}]
	Contracts._shuffle(extra, rng)
	goals.append_array(extra.slice(0, clampi(2 + level / 5, 2, 4)))
	goals.append({"t": "report"})
	var fee := 120.0 + 30.0 * (goals.size() - 2) + 6.0 * level
	return {"kind": "test_ride", "budget": 0, "brand": brand, "model": model, "style": style, "parts": parts,
		"paint_rgb": paint.to_html(false), "quirks": quirks, "goals": goals, "pay": int(snappedi(roundi(fee), 10)),
		"bonus": int(snappedi(roundi(fee * 0.8), 10)), "days": 2 + rng.randi_range(0, 1),
		"bike_name": "%s prototype" % model,
		"blurb": "It's our new %s, not out yet. Ride it, put it through the test, and tell us honestly what you think of it. A sharp report earns a bonus." % model}


## The parts with a fuel system that keeps up with the engine (the style's own if it does, else
## the first of the catalogue's that does): a prototype's faults are the ones it's meant to have.
static func _fed(parts: Dictionary) -> Dictionary:
	if not _starved(parts):
		return parts
	var options: Array = (PartsDB.by_kind.get("fuel", []) as Array).duplicate()
	options.sort_custom(func(a, b): return float(PartsDB.get_part(str(a)).get("flow", 0.0)) < float(PartsDB.get_part(str(b)).get("flow", 0.0)))
	for f in options:
		var p := parts.duplicate()
		p["fuel"] = str(f)
		if not _starved(p):
			return p
	return parts


static func _starved(parts: Dictionary) -> bool:
	return BikeBuild.new(PartsDB.sanitize_build(parts.duplicate()), {}).notes.any(func(n): return str(n).begins_with("Fuel starved"))


## One to `most` faults for a prototype built from `parts`, of those it can have (a hot engine
## only where a smaller cooler would actually overheat it).
static func _pick_quirks(parts: Dictionary, rng: RandomNumberGenerator, most: int) -> Array:
	var pool: Array = ["weave", "weak_front", "flat_spot", "soft_rear"]
	if _hot_cooler(parts) != "":
		pool.append("hot")
	Contracts._shuffle(pool, rng)
	return pool.slice(0, rng.randi_range(1, most))


## The cooler that would make this engine run hot, or "" when even the smallest copes.
static func _hot_cooler(parts: Dictionary) -> String:
	for c in ["air_fins", "oil_cooler", "single_radiator"]:
		var p := parts.duplicate()
		p["cooling"] = c
		var b := BikeBuild.new(PartsDB.sanitize_build(p), {})
		if b.engine_heat > b.cooling_capacity * 1.1:
			return c
	return ""


## The parts a prototype's faults change before it's built: a single-piston front caliper on
## organic pads for a weak front brake, a cooler too small for a hot one, no steering damper for a weave.
static func _quirk_parts(parts: Dictionary, quirks: Array) -> Dictionary:
	var p := parts.duplicate()
	if quirks.has("weak_front"):
		p["front_caliper"] = "single_piston"
		p["front_pads"] = "organic"
	if quirks.has("hot"):
		var c := _hot_cooler(p)
		if c != "":
			p["cooling"] = c
	if quirks.has("weave"):
		p["steering_damper"] = "none"
	return p


# ---------------------------------------------------------------------------- the job

## Fills in a test ride job from its offer once the prototype `bike_id` is in the shed.
static func start(job: Dictionary, offer: Dictionary, bike_id: int) -> void:
	job["brand"] = str(offer.get("brand", ""))
	job["model"] = str(offer.get("model", ""))
	job["style"] = str(offer.get("style", ""))
	job["quirks"] = (offer.get("quirks", []) as Array).duplicate()
	job["bonus"] = int(offer.get("bonus", 0))
	var dyno: Dictionary = Shed.bikes[bike_id].get("dyno", {})
	job["log"] = {"km": 0.0, "top": 0.0, "brake": 0.0, "lean": 0.0, "wobble": 0.0, "laps": 0, "dyno0": int(dyno.get("n", 0))}
	job["truth"] = truth(bike_id, job)


## The prototype as it's delivered: brand new, fresh fluids, and its faults built in (see the
## class notes): the yokes' offset, the flat spot in the engine, worn pads and old brake fluid
## on the weak front brake, a tired shock.
static func prepare_bike(bike_id: int, quirks: Array) -> void:
	var bike: Dictionary = Shed.bikes[bike_id]
	bike["proto"] = true
	for slot in ["tank", "engine", "front_master", "rear_master"]:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items[id].has("fluid"):
			var cap := PartsDB.fluid_capacity(str(Shed.items[id]["part"]))
			Shed.items[id]["fluid"] = {"type": {"tank": "unleaded_95", "engine": "semi_10w40"}.get(slot, "dot4"),
				"litres": snappedf(cap * (0.7 if slot == "tank" else 1.0), 0.01), "age": 0.0}
	var chain := Shed.item_on(bike_id, "chain")
	if chain != 0:
		Shed.items[chain]["slack"] = Shed.CHAIN_SLACK_SET
		Shed.items[chain]["lube"] = 1.0
	if quirks.has("weave"):
		var fork := Shed.item_on(bike_id, "fork")
		var t := Shed.build_of(bike_id).trail
		if fork != 0 and t > WEAVE_TRAIL:
			# Trail falls about as fast as the offset grows (a little faster, the more raked it is).
			Shed.items[fork]["proto"] = {"offset": snappedf((t - WEAVE_TRAIL) * 0.92, 0.001)}
	if quirks.has("flat_spot"):
		var engine := Shed.item_on(bike_id, "engine")
		if engine != 0:
			Shed.items[engine]["proto"] = {"dip": FLAT_DIP}
	if quirks.has("weak_front"):
		var pads := Shed.item_on(bike_id, "front_pads")
		if pads != 0:
			Shed.items[pads]["wear"] = 0.7
		var master := Shed.item_on(bike_id, "front_master")
		if master != 0:
			Shed.items[master]["fluid"]["age"] = 0.8
	if quirks.has("soft_rear"):
		var shock := Shed.item_on(bike_id, "shock")
		if shock != 0:
			Shed.items[shock]["wear"] = 0.92
	Contracts.refresh_delivered(bike_id)


## The fair ratings for the prototype (1..5 each), from what it is: power for its weight, the
## brakes' bite for its weight, the handling (less for a weave or a soft shock, or a lot of
## bike), the seat's comfort (less for an engine that cooks your legs), and its looks.
static func truth(bike_id: int, job: Dictionary) -> Dictionary:
	var b := Shed.build_of(bike_id)
	var s := b.summary()
	var quirks: Array = job.get("quirks", [])
	var mass := float(s["mass"]) + 80.0
	var hpt := float(s["hp"]) / mass * 1000.0
	var power := 1
	for edge in [220.0, 280.0, 360.0, 460.0]:
		if hpt >= edge:
			power += 1
	var brakes := clampi(roundi(float(s["brake"]) / mass - 2.0), 1, 5)
	var handling := 4 - (2 if quirks.has("weave") else 0) - (1 if quirks.has("soft_rear") else 0) - (1 if float(s["mass"]) > 255.0 else 0)
	var comfort := 1 + roundi(float(PartsDB.get_part(str(b.parts.get("saddle", ""))).get("comfort", 0.6)) * 4.0) - (1 if quirks.has("hot") else 0)
	var d := PartsDB.detect_style(b.parts)
	var looks := 5 if str(d.get("style", "")) == str(job.get("style", "")) and d.get("proper", false) else 4
	return {"handling": clampi(handling, 1, 5), "brakes": brakes, "power": clampi(power - (1 if quirks.has("flat_spot") else 0), 1, 5),
		"comfort": clampi(comfort, 1, 5), "looks": looks}


## Host: the ride stats `action` from the rider's machine (see Main._send_ride_stats) for a ride
## on `bike_id`: kept on its test ride job, the best of each.
static func note_ride(job: Dictionary, action: Dictionary) -> void:
	var lg: Dictionary = job.get("log", {})
	lg["km"] = float(lg.get("km", 0.0)) + clampf(float(action.get("km", 0.0)), 0.0, 5.0)
	lg["top"] = maxf(float(lg.get("top", 0.0)), clampf(float(action.get("top_kmh", 0.0)), 0.0, 400.0))
	lg["brake"] = maxf(float(lg.get("brake", 0.0)), clampf(float(action.get("brake_g", 0.0)), 0.0, 2.0))
	lg["lean"] = maxf(float(lg.get("lean", 0.0)), clampf(float(action.get("lean", 0.0)), 0.0, 70.0))
	lg["wobble"] = maxf(float(lg.get("wobble", 0.0)), clampf(float(action.get("wobble", 0.0)), 0.0, 30.0))
	lg["laps"] = int(lg.get("laps", 0)) + clampi(int(action.get("laps", 0)), 0, 2)
	job["log"] = lg


## Whether a goal is met and what the logger shows: {done, have}.
static func eval_goal(job: Dictionary, g: Dictionary) -> Dictionary:
	var lg: Dictionary = job.get("log", {})
	match str(g.get("t", "")):
		"ride_km":
			return {"done": float(lg.get("km", 0.0)) >= float(g["min"]) - 0.01, "have": "%.1f km logged" % float(lg.get("km", 0.0))}
		"ride_top":
			return {"done": float(lg.get("top", 0.0)) >= float(g["min"]) - 0.5, "have": "%d km/h logged" % roundi(float(lg.get("top", 0.0)))}
		"ride_brake":
			return {"done": float(lg.get("brake", 0.0)) >= float(g["min"]) - 0.005, "have": "%.2f g logged" % float(lg.get("brake", 0.0))}
		"ride_lean":
			return {"done": float(lg.get("lean", 0.0)) >= float(g["min"]) - 0.25, "have": "%d° logged" % roundi(float(lg.get("lean", 0.0)))}
		"ride_lap":
			var laps := int(lg.get("laps", 0))
			return {"done": laps >= int(g.get("n", 1)), "have": "%d lap%s logged" % [laps, "" if laps == 1 else "s"]}
		"ride_dyno":
			var n := int(Shed.bikes.get(int(job.get("bike", 0)), {}).get("dyno", {}).get("n", 0)) - int(lg.get("dyno0", 0))
			return {"done": n > 0, "have": "%d run%s" % [n, "" if n == 1 else "s"]}
		"report":
			var r = job.get("report")
			return {"done": r is Dictionary, "have": "sent" if r is Dictionary else "not written yet"}
	return {"done": false, "have": ""}


static func goal_text(g: Dictionary) -> String:
	match str(g.get("t", "")):
		"ride_km":
			return "Ride at least %d km on it" % roundi(float(g["min"]))
		"ride_top":
			return "A top speed run: at least %d km/h" % roundi(float(g["min"]))
		"ride_brake":
			return "A hard stop: braking at %.2f g or more" % float(g["min"])
		"ride_lean":
			return "Corner it hard: %d° of lean or more" % roundi(float(g["min"]))
		"ride_lap":
			var n := int(g.get("n", 1))
			return "%s of %s, all the way round" % ["A lap" if n == 1 else "%d laps" % n, route_name(str(g.get("road", LAP_ROAD)))]
		"ride_dyno":
			return "A dyno pull in the dyno room"
		"report":
			return "Fill in the test report (handling, brakes, power, comfort, looks, issues)"
	return ""


## A named route's name on the map ("The Loop").
static func route_name(road: String) -> String:
	for def in WorldLayout.ROADS:
		if str(def["name"]) == road:
			return str(def.get("label", road))
	return road


## The ride logger's lap counter: `seen` is a flag per stretch of the route, `sector` the one the
## bike is on now. True when that completes a lap (every stretch seen, either way round), and
## `seen` starts again.
static func lap_step(seen: Array, sector: int) -> bool:
	if seen.size() != LAP_SECTORS:
		seen.resize(LAP_SECTORS)
		seen.fill(false)
	var k := clampi(sector, 0, LAP_SECTORS - 1)
	seen[k] = true
	if seen.has(false):
		return false
	seen.fill(false)
	seen[k] = true
	return true


## Host: scores a report against the prototype, 0..1: the issues spotted (each fault found
## counts, each one ticked that isn't there takes half of one back) and the ratings (spot on,
## or one out for part of it).
static func score(job: Dictionary, ratings: Dictionary, issues: Array) -> Dictionary:
	var quirks: Array = job.get("quirks", [])
	var hits := issues.filter(func(k): return quirks.has(k)).size()
	var wrong := issues.filter(func(k): return not quirks.has(k)).size()
	var issue_score := clampf((hits - 0.5 * wrong) / maxf(1.0, quirks.size()), 0.0, 1.0)
	var truth_r: Dictionary = job.get("truth", {})
	var total := 0.0
	for k in RATINGS:
		var off := absi(int(ratings.get(k, 0)) - int(truth_r.get(k, 3)))
		total += 1.0 if off == 0 else (0.6 if off == 1 else 0.0)
	var rating_score := total / RATINGS.size()
	return {"score": ISSUE_WEIGHT * issue_score + (1.0 - ISSUE_WEIGHT) * rating_score, "issues": issue_score, "ratings": rating_score,
		"hits": hits, "wrong": wrong, "missed": quirks.size() - hits}


## How many of the riding tests the logger shows done, and how many there are.
static func tests_done(job: Dictionary) -> Vector2i:
	var done := 0
	var n := 0
	for g in job.get("goals", []):
		if str(g.get("t", "")) == "report":
			continue
		n += 1
		if eval_goal(job, g)["done"]:
			done += 1
	return Vector2i(done, n)


## What the rep collecting it now would pay (as Contracts.payout): the fee for the tests done
## (the report's needed for any of it), the bonus for how good the report is, less for being late.
static func payout(job: Dictionary) -> Dictionary:
	var t := tests_done(job)
	var tf := float(t.x) / maxf(1.0, t.y)
	var fee := float(job.get("pay", 0))
	var r = job.get("report")
	var has_report := r is Dictionary
	var sc := float(r.get("score", 0.0)) if has_report else 0.0
	var late := maxi(0, ceili((Contracts.clock() - float(job.get("due", 0.0))) / Contracts.DAY))
	var labour := fee * (0.3 + 0.7 * tf) if has_report else fee * 0.1
	var bonus := roundi(float(job.get("bonus", 0)) * sc * tf) if has_report else 0
	labour = (labour + bonus) * maxf(0.5, 1.0 - 0.15 * late)
	var sat := (tf + (1.0 if has_report else 0.0)) / 2.0
	var note := "%d of %d tests on the logger." % [t.x, t.y] if t.x < t.y else "Every test on the logger."
	if has_report:
		note += " Report %d%%: %s bonus." % [roundi(sc * 100.0), Contracts.money(bonus)]
	else:
		note += " No report yet."
	var rep := int(Contracts.REP_GAIN.get("test_ride", 3)) if tf >= 1.0 and sc >= 0.5 else (0 if tf >= 0.5 and has_report else -1)
	if late > 0:
		rep -= 1
		note += " %d day%s late." % [late, "" if late == 1 else "s"]
	return {"labour": roundi(labour), "parts": 0, "tip": 0, "over": 0, "late": late, "sat": sat, "total": roundi(labour), "rep": rep,
		"note": note, "spent": 0, "match_bonus": 0, "bonus": bonus}


## Why an action can't touch the prototype it's on, or "" (it's theirs: ride it, wheel it about,
## fuel it, put it on the dyno, wash it).
static func guard(action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if not NO_TOUCH.has(a):
		return ""
	var bike_id := int(action.get("bike", 0))
	if bike_id == 0 and int(action.get("engine", 0)) != 0:
		bike_id = Shed._bike_of(int(action["engine"]))
	if bike_id == 0 and int(action.get("item", 0)) != 0:
		bike_id = Shed._bike_of(int(action["item"]))
	if bike_id != 0 and Shed.bikes.has(bike_id) and Shed.bikes[bike_id].get("proto", false):
		return "It's the manufacturer's prototype: ride it and report back, no spanners on it."
	return ""


## The faults a report form lists, in order: {key, text}.
static func report_options() -> Array:
	var out := []
	for k in ISSUE_ORDER:
		out.append({"key": k, "text": str(ISSUES.get(k, DECOYS.get(k, k)))})
	return out
