class_name MotTest
extends RefCounted
## The MOT: a full roadworthiness inspection of a bike, read straight off its parts (their
## wear, rust, dirt, fluids, chain and tyre beads). inspect() gives the pass/fail sheet, one row
## per check: {area, name, value, pass, fix}. A bike passes with no fails; anything worked on
## after a test needs testing again (see Contracts).

const TREAD_LEGAL := 1.0          # mm: the legal minimum tread depth
## Tread depth on a new tyre, mm, by tyre style.
const TREAD_NEW := {"road": 6.0, "offroad": 9.0, "slick": 0.0}
const PAD_NEW := 9.0              # mm of brake pad friction material, new
const PAD_MIN := 1.5
const DISC_NEW := 5.0             # mm disc thickness, new
const DISC_MIN := 4.0
const DISC_WEAR := 1.5            # mm a fully worn disc has lost
const OIL_MIN := 0.4              # engine oil level, of capacity
const BRAKE_FLUID_MIN := 0.5
const BRAKE_FLUID_OLD := 0.8      # fluid this old has taken on water and fails


## Tread left on a tyre in mm, from how worn it is.
static func tread_mm(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var style := str(PartsDB.get_part(str(item["part"])).get("style", "road"))
	return float(TREAD_NEW.get(style, 6.0)) * (1.0 - clampf(float(item.get("wear", 0.0)), 0.0, 1.0))


static func pad_mm(item: Dictionary) -> float:
	return PAD_NEW * (1.0 - clampf(float(item.get("wear", 0.0)), 0.0, 1.0))


static func disc_mm(item: Dictionary) -> float:
	return DISC_NEW - DISC_WEAR * clampf(float(item.get("wear", 0.0)), 0.0, 1.0)


static func _row(area: String, check_name: String, value: String, ok: bool, fix: String) -> Dictionary:
	return {"area": area, "name": check_name, "value": value, "pass": ok, "fix": "" if ok else fix}


static func _item(bike_id: int, slot: String) -> Dictionary:
	var id := Shed.item_on(bike_id, slot)
	return Shed.items.get(id, {})


static func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


## The whole inspection of a bike, in the order a tester goes round it.
static func inspect(bike_id: int) -> Array:
	var rows := []
	if not Shed.bikes.has(bike_id):
		return rows
	# Tyres: tread depth, condition, road legal, seated.
	for side in ["front", "rear"]:
		var side_name: String = side.capitalize()
		var t := _item(bike_id, side + "_tyre")
		if t.is_empty():
			rows.append(_row("Tyres", "%s tyre tread depth" % side_name, "no tyre", false, "Fit a %s tyre." % side))
			continue
		var style := str(PartsDB.get_part(str(t["part"])).get("style", "road"))
		if style == "slick":
			rows.append(_row("Tyres", "%s tyre road legal" % side_name, "race slick", false, "Fit a road tyre: slicks aren't road legal."))
		else:
			var mm := tread_mm(t)
			rows.append(_row("Tyres", "%s tyre tread depth" % side_name, "%.1f mm (min %.0f mm)" % [mm, TREAD_LEGAL], mm >= TREAD_LEGAL,
				"Below the legal limit: fit a new %s tyre." % side))
		var perished := float(t["rust"]) > 0.6 or float(t["wear"]) > 0.95
		rows.append(_row("Tyres", "%s tyre condition (cracks, cuts, bulges)" % side_name,
			"perished sidewalls" if perished else "sound", not perished, "Cracked and perished: replace the %s tyre." % side))
		if t.has("bead"):
			var seated := float(t["bead"]) >= BikeBuild.BEAD_OK
			rows.append(_row("Tyres", "%s tyre bead seated" % side_name, _pct(float(t["bead"])), seated,
				"Re-seat the %s tyre on the tyre changer." % side))
	# Wheels.
	for side in ["front", "rear"]:
		var w := _item(bike_id, side + "_wheel")
		var ok := not w.is_empty() and float(w["wear"]) <= 0.65 and float(w["rust"]) <= 0.7
		rows.append(_row("Wheels", "%s wheel and rim (buckles, corrosion)" % side.capitalize(),
			"missing" if w.is_empty() else "wear %s, rust %s" % [_pct(float(w["wear"])), _pct(float(w["rust"]))], ok,
			"Restore or replace the %s wheel." % side))
	# Brakes: discs, pads, calipers, master cylinders and their fluid.
	for side in ["front", "rear"]:
		var cap_side: String = side.capitalize()
		var d := _item(bike_id, side + "_disc")
		var dmm := disc_mm(d) if not d.is_empty() else 0.0
		rows.append(_row("Brakes", "%s disc thickness" % cap_side, "missing" if d.is_empty() else "%.1f mm (min %.1f mm)" % [dmm, DISC_MIN],
			not d.is_empty() and dmm >= DISC_MIN - 0.001 and float(d["rust"]) <= 0.75, "Worn or scored: restore or replace the %s disc." % side))
		var p := _item(bike_id, side + "_pads")
		var pmm := pad_mm(p) if not p.is_empty() else 0.0
		rows.append(_row("Brakes", "%s pads" % cap_side, "missing" if p.is_empty() else "%.1f mm (min %.1f mm)" % [pmm, PAD_MIN],
			not p.is_empty() and pmm >= PAD_MIN, "Fit new %s brake pads." % side))
		var c := _item(bike_id, side + "_caliper")
		rows.append(_row("Brakes", "%s caliper (seized pistons, leaks)" % cap_side,
			"missing" if c.is_empty() else "wear %s, rust %s" % [_pct(float(c["wear"])), _pct(float(c["rust"]))],
			not c.is_empty() and float(c["wear"]) <= 0.7 and float(c["rust"]) <= 0.6, "Rebuild or replace the %s caliper." % side))
		var m := _item(bike_id, side + "_master")
		var level := 0.0
		var age := 1.0
		if not m.is_empty() and m.has("fluid"):
			level = float(m["fluid"]["litres"]) / maxf(0.001, PartsDB.fluid_capacity(str(m["part"])))
			age = float(m["fluid"].get("age", 0.0))
		rows.append(_row("Brakes", "%s master cylinder" % cap_side, "missing" if m.is_empty() else "wear %s" % _pct(float(m["wear"])),
			not m.is_empty() and float(m["wear"]) <= 0.75, "Rebuild or replace the %s master cylinder." % side))
		rows.append(_row("Brakes", "%s brake fluid level and condition" % cap_side, "level %s, %s" % [_pct(level), "old" if age > BRAKE_FLUID_OLD else "fine"],
			level >= BRAKE_FLUID_MIN and age <= BRAKE_FLUID_OLD, "Drain and refill the %s brake fluid." % side))
	# Suspension and steering.
	var fork := _item(bike_id, "fork")
	rows.append(_row("Suspension", "Front fork (seal leaks, pitted stanchions)", "missing" if fork.is_empty() else "wear %s, rust %s" % [
		_pct(float(fork["wear"])), _pct(float(fork["rust"]))], not fork.is_empty() and float(fork["wear"]) <= 0.65 and float(fork["rust"]) <= 0.7,
		"Leaking: restore or replace the fork."))
	var shock := _item(bike_id, "shock")
	rows.append(_row("Suspension", "Rear suspension (leaks, damping)", "missing" if shock.is_empty() else "wear %s" % _pct(float(shock["wear"])),
		not shock.is_empty() and float(shock["wear"]) <= 0.7, "Restore or replace the rear shock."))
	var bars := _item(bike_id, "handlebars")
	rows.append(_row("Steering", "Handlebars and steering", "missing" if bars.is_empty() else "wear %s, rust %s" % [
		_pct(float(bars["wear"])), _pct(float(bars["rust"]))], not bars.is_empty() and float(bars["wear"]) <= 0.75 and float(bars["rust"]) <= 0.75,
		"Restore or replace the handlebars."))
	# Drive.
	var chain := _item(bike_id, "chain")
	var sprockets := _item(bike_id, "final_drive")
	rows.append(_row("Drive", "Chain and sprocket wear", "missing" if chain.is_empty() or sprockets.is_empty() else "chain %s, sprockets %s worn" % [
		_pct(float(chain["wear"])), _pct(float(sprockets["wear"]))],
		not chain.is_empty() and not sprockets.is_empty() and float(chain["wear"]) <= 0.7 and float(sprockets["wear"]) <= 0.7,
		"Fit a new chain and sprockets."))
	var slack := float(chain.get("slack", Shed.CHAIN_SLACK_SET)) if not chain.is_empty() else 0.0
	rows.append(_row("Drive", "Chain tension", "missing" if chain.is_empty() else "%d mm slack (%d-%d)" % [roundi(slack),
		roundi(Shed.CHAIN_SLACK_GOOD.x), roundi(Shed.CHAIN_SLACK_GOOD.y)],
		not chain.is_empty() and slack >= Shed.CHAIN_SLACK_GOOD.x and slack <= Shed.CHAIN_SLACK_GOOD.y, "Adjust the chain tension."))
	# Lights, horn, dash.
	var head := _item(bike_id, "headlight")
	rows.append(_row("Lights", "Headlight working", "none fitted" if head.is_empty() else ("dead" if float(head["wear"]) > 0.85 else "working"),
		not head.is_empty() and float(head["wear"]) <= 0.85, "Fit or restore a headlight."))
	var tail := _item(bike_id, "tail")
	rows.append(_row("Lights", "Rear light working", "no tail unit" if tail.is_empty() else ("dead" if float(tail["wear"]) > 0.85 else "working"),
		not tail.is_empty() and float(tail["wear"]) <= 0.85, "Fit or restore the tail unit's rear light."))
	rows.append(_row("Lights", "Number plate fitted (tail unit)", "missing" if tail.is_empty() else "fitted", not tail.is_empty(),
		"Fit a tail unit to carry the number plate."))
	var horn := _item(bike_id, "horn")
	rows.append(_row("Controls", "Horn", "none fitted" if horn.is_empty() else ("silent" if float(horn["wear"]) > 0.85 else "works"),
		not horn.is_empty() and float(horn["wear"]) <= 0.85, "Fit or restore a horn."))
	var dash := _item(bike_id, "dashboard")
	rows.append(_row("Controls", "Speedometer and dash", "missing" if dash.is_empty() else ("dead" if float(dash["wear"]) > 0.85 else "working"),
		not dash.is_empty() and float(dash["wear"]) <= 0.85, "Fit or restore the dashboard."))
	var mirrors := _item(bike_id, "mirrors")
	rows.append(_row("Controls", "Mirrors fitted", "none" if mirrors.is_empty() else PartsDB.part_name(str(mirrors["part"])),
		not mirrors.is_empty(), "Fit mirrors (order a pair from the parts computer)."))
	# Exhaust: blowing and noise.
	var ex := _item(bike_id, "exhaust")
	rows.append(_row("Exhaust", "Exhaust condition (holes, blowing)", "missing" if ex.is_empty() else "rust %s, wear %s" % [
		_pct(float(ex["rust"])), _pct(float(ex["wear"]))], not ex.is_empty() and float(ex["rust"]) <= 0.65 and float(ex["wear"]) <= 0.7,
		"Blowing: restore or replace the exhaust."))
	var loud := not ex.is_empty() and str(ex["part"]) == "straight_pipe"
	rows.append(_row("Exhaust", "Exhaust noise", "too loud" if loud else "within limits", not ex.is_empty() and not loud,
		"A straight pipe is too loud for the road: fit a silencer."))
	# Structure, tank, seat and fluids.
	var frame := _item(bike_id, "frame")
	rows.append(_row("Structure", "Frame corrosion and damage", "missing" if frame.is_empty() else "rust %s, wear %s" % [
		_pct(float(frame["rust"])), _pct(float(frame["wear"]))], not frame.is_empty() and float(frame["rust"]) <= 0.5 and float(frame["wear"]) <= 0.7,
		"Structural rust: blast and restore the frame."))
	var tank := _item(bike_id, "tank")
	rows.append(_row("Structure", "Fuel tank (leaks)", "missing" if tank.is_empty() else "rust %s" % _pct(float(tank["rust"])),
		not tank.is_empty() and float(tank["rust"]) <= 0.7, "Restore or replace the tank."))
	var seat := _item(bike_id, "saddle")
	rows.append(_row("Structure", "Seat secure", "missing" if seat.is_empty() else "fitted", not seat.is_empty(), "Fit a saddle."))
	var engine := _item(bike_id, "engine")
	var oil := 0.0
	if not engine.is_empty() and engine.has("fluid"):
		oil = float(engine["fluid"]["litres"]) / maxf(0.001, PartsDB.fluid_capacity(str(engine["part"])))
	rows.append(_row("Fluids", "Engine oil level (no leaks)", "missing engine" if engine.is_empty() else _pct(oil), oil >= OIL_MIN,
		"Top up the engine oil."))
	var bolted := Shed.loose_slots(bike_id).is_empty() and Shed.missing_slots(bike_id).filter(func(s): return not PartsDB.is_optional(str(s))).is_empty()
	rows.append(_row("Structure", "Everything fitted and bolted up", "all secure" if bolted else "loose or missing parts", bolted,
		"Fit and bolt up every part."))
	return rows


## Just the failing rows.
static func fails(sheet: Array) -> Array:
	return sheet.filter(func(r): return not r["pass"])
