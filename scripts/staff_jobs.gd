class_name StaffJobs
extends RefCounted
## What each staff job is, step by step (see Staff for the runner). A job never holds a script
## worked out in advance: plan() looks at the shed as it is now and returns the next few steps
## (walk there, do this, carry that) ending in another look, so a job carries on from wherever
## it's got to: after something got in the way, after a save was opened, after a sick day.
## When there's nothing left to do it returns no steps and the job's done.
##
## Steps are plain data (they're synced and saved):
##   {do: "go", to: place}                       walk to a place (StaffNav)
##   {do: "push", bike, to: place, xf}           wheel a bike they've hold of there, let go at xf
##   {do: "work", act: request, secs, anim}      work at it for secs (quicker the better they
##                                               are), then make the request (Staff.act)
##   {do: "wait", secs, anim}, {do: "flag", k, v}, {do: "say", text}, {do: "plan"}
## A step's "what" is what they're doing, for the TV and the look panel.
##
## Detailing jobs are a list of steps (DETAIL_STEPS: wash, polish and ceramic coat via Detail.work_step;
## plug in as more entries, each a function name here that returns its next steps or [] when
## it's done).

## The parts a paint expert takes off and resprays.
const PAINT_SLOTS: Array[String] = ["tank", "fairing", "side_panels", "front_mudguard", "tail", "number_boards"]
## Consumables a service renews when they're worn (like for like).
const SERVICE_PARTS: Array[String] = ["front_pads", "rear_pads", "spark_plugs", "air_filter", "oil_filter"]
const WORN := 0.2
## What a detailing job can do, in order, each with the planner that does it ("" for a step the
## detailer has no kit for yet: skipped with a word).
const DETAIL_STEPS := {"wash": "_detail_wash", "polish": "_detail_polish", "ceramic": "_detail_ceramic"}
const SHINE_PASSES := 4   # polisher passes between looks at how it's coming on
const SHINE_ROUNDS := 8   # looks before they give up on a step that won't come right
const DETAIL_NAMES := {"wash": "pressure wash", "polish": "polish", "ceramic": "ceramic coat"}
const WASH_PASSES := 4
## The usual stock they order when there's none in the shed.
const DEFAULT_OIL := "semi_10w40"
const DEFAULT_LUBE := "road_lube"
const DEFAULT_BRAKE := "dot4"


# ---------------------------------------------------------------------------- steps

static func go(to: Dictionary, what: String) -> Dictionary:
	return {"do": "go", "to": to, "what": what}


static func work(action: Dictionary, secs: float, anim: String, what: String) -> Dictionary:
	return {"do": "work", "act": action, "secs": secs, "anim": anim, "what": what}


static func plan_step() -> Dictionary:
	return {"do": "plan"}


static func flag(k: String, v = true) -> Dictionary:
	return {"do": "flag", "k": k, "v": v}


static func _bike_name(b: int) -> String:
	return str(Shed.bikes.get(b, {}).get("name", "the bike"))


static func _slot(slot: String) -> String:
	return PartsDB.slot_name(slot).to_lower()


static func _part(item_id: int) -> String:
	return PartsDB.part_name(str(Shed.items.get(item_id, {}).get("part", ""))) if Shed.items.has(item_id) else "part"


## A job as the runner keeps it: what was asked, a label to show, and a first look to start.
static func new_job(w: Dictionary, j: Dictionary) -> Dictionary:
	var kind := str(j.get("kind", ""))
	var b := int(j.get("bike", 0))
	var job := {"kind": kind, "bike": b, "steps": [plan_step()], "i": 0, "on": false, "t": 0.0, "done": 0, "replans": 0, "fails": 0,
		"refit": [], "dropped": [], "started": Staff.clock(), "doing": "", "wid": int(w["id"])}
	match kind:
		"service":
			job["label"] = "Servicing the %s" % _bike_name(b)
			job["did"] = []
		"fit":
			job["slot"] = str(j["slot"])
			job["part"] = str(j["part"])
			# Like for like: the one on it now is the old one, coming off.
			var was := Shed.item_on(b, str(j["slot"]))
			if was != 0 and str(Shed.items[was]["part"]) == str(j["part"]):
				job["old"] = was
			job["label"] = "Fitting a %s to the %s" % [PartsDB.part_name(str(j["part"])), _bike_name(b)]
		"paint":
			job["slot"] = str(j.get("slot", "tank"))
			job["color"] = int(j.get("color", 0))
			job["finish"] = str(j.get("finish", "gloss")) if Shed.FINISHES.has(str(j.get("finish", "gloss"))) else "gloss"
			job["item"] = Shed.item_on(b, job["slot"])
			job["label"] = "Painting the %s's %s %s" % [_bike_name(b), _slot(job["slot"]), str(Shed.PAINT_NAMES[job["color"]])]
		"detail":
			var todo: Array = []
			for s in j.get("steps", ["wash"]):
				var st := "ceramic" if str(s) == "coat" else str(s)   # a Detailing job's list says "coat"
				if DETAIL_STEPS.has(st):
					todo.append(st)
			if todo.is_empty():
				todo = ["wash"]
			job["todo"] = todo
			job["step"] = 0
			var xf: Transform3D = Shed.bikes[b]["xf"]
			job["home_xf"] = xf
			job["home_bay"] = StaffNav.bay_of(xf.origin)
			job["label"] = "Washing the %s" % _bike_name(b) if todo == ["wash"] else "Detailing the %s" % _bike_name(b)
		"sell":
			job["ask"] = maxi(0, int(j.get("ask", 0)))
			job["label"] = "Selling the %s" % _bike_name(b)
		"tea":
			job["label"] = "Fetching teas from the cafe"
		"reception":
			job["label"] = "Running reception"
	return job


## The next steps of a job, from how things stand now ([] when it's done). Sets job["fail"]
## when it can't be done at all.
static func plan(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job.get("bike", 0))
	if str(job["kind"]) in ["service", "fit", "paint", "detail", "sell"]:
		if not Shed.bikes.has(b):
			job["fail"] = "The bike's gone, so that's that."
			return []
		if int(Shed.bikes[b].get("rider", 0)) != 0:
			return [{"do": "wait", "secs": 6.0, "anim": "think", "what": "waiting for the bike to come back"}, plan_step()]
	match str(job["kind"]):
		"service":
			return _service(w, job)
		"fit":
			var out := _fit(w, job, b, str(job["slot"]), str(job["part"]), false, int(job.get("old", 0)))
			if out.is_empty() and not job.has("fail"):
				job["report"] = "Fitted the %s to the %s and bolted it up.%s" % [PartsDB.part_name(str(job["part"])), _bike_name(b),
					" The old one's on the floor by the bike." if not (job["dropped"] as Array).is_empty() else ""]
			return out
		"paint":
			return _paint(w, job)
		"detail":
			return _detail(w, job)
		"sell":
			return _sell(w, job)
		"tea":
			return _tea(w, job)
	return []


## A work step's follow-up, by name.
static func after(_w: Dictionary, job: Dictionary, key: String) -> void:
	if key.begins_with("ordered:"):
		var part := key.substr(8)
		if not (job.get("orders") is Dictionary):
			job["orders"] = {}
		job["orders"][part] = int(job["orders"].get(part, 0)) + 1


# ---------------------------------------------------------------------------- parts

## Where a loose part is: on the floor where it was put down, or in its place on a bench or shelf.
static func item_at(id: int) -> Vector3:
	var it: Dictionary = Shed.items.get(id, {})
	if it.get("at", "") == "floor" and it.get("ref") is Transform3D:
		return (it["ref"] as Transform3D).origin
	if it.get("at", "") == "spot":
		return Shed.item_place(id).origin if it.get("place") is Transform3D else Shed.spot_transform(str(it["ref"])).origin
	return Workshop.CENTER


static func _held(w: Dictionary) -> int:
	return Shed.held_by(Staff.peer_of(int(w["id"])))


## A part fitted to the bike that has to come off before the part in `slot` can (bolted on it).
static func _blocking(bike: int, slot: String) -> String:
	for dep in PartsDB.dependents(slot):
		if Shed.item_on(bike, dep) != 0 and Shed.WHEEL_TYRE.get(slot, "") != dep:
			return dep
	var host := Shed.host_of(bike, slot)
	for other in host.get("slots", {}):
		var on := int(host["slots"][other])
		if on != 0 and Shed.items.has(on) and PartsDB.part_mounts(str(other), str(Shed.items[on]["part"])).has(slot) \
				and not PartsDB.MOUNTS.get(other, []).has(slot):
			return str(other)
	return ""


## What has to come off first to get at `slot`, following blockers down (the caliper before the
## disc before the wheel). "" when nothing's in the way.
static func _first_off(bike: int, slot: String) -> String:
	var dep := _blocking(bike, slot)
	for i in 6:
		var deeper := _blocking(bike, dep) if dep != "" else ""
		if deeper == "":
			break
		dep = deeper
	return dep


## A spare of `part` in the shed to use: loose (not on a bike, nobody holding it), as good as
## new, not one this job put down, nor one another worker's after. Unpacked ones first. With
## `fluid` above 0 it has to hold at least that much.
static func find_stock(part: String, job: Dictionary, fluid := 0.0, kind := "") -> int:
	var best := 0
	var best_score := INF
	var taken := []
	for id in Staff.workers():
		var other: Dictionary = Staff.workers()[id]["job"]
		if other != job and other.has("claim"):
			taken.append(int(other["claim"]))
	for id in Shed.items:
		var it: Dictionary = Shed.items[id]
		if kind != "":
			if PartsDB.kind_of(str(it["part"])) != kind or PartsDB.get_part(str(it["part"])).get("empty", false):
				continue
		elif str(it["part"]) != part:
			continue
		if not it["at"] in ["floor", "spot"] or (job["dropped"] as Array).has(int(id)) or taken.has(int(id)):
			continue
		if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) in ["booth", "blaster", "stand", "changer", "repair"]:
			continue
		if fluid > 0.0 and float(it.get("fluid", {}).get("litres", 0.0)) < fluid:
			continue
		if PartsDB.get_part(str(it["part"])).get("empty", false) \
				and float(it.get("fluid", {}).get("litres", 0.0)) > PartsDB.fluid_capacity(str(it["part"])) * 0.5:
			continue   # a drain pan or bleed bottle with old fluid still in it
		if fluid <= 0.0 and (float(it["wear"]) > 0.2 or float(it["rust"]) > 0.2):
			continue
		var score := (0.0 if not it.get("boxed", false) else 5.0) + item_at(int(id)).distance_to(Workshop.CENTER) * 0.05
		if score < best_score:
			best_score = score
			best = int(id)
	return best


## Fetching item `id` from where it is: over to it, unpacking it if it's boxed, picking it up.
static func _fetch(job: Dictionary, id: int) -> Array:
	var it: Dictionary = Shed.items[id]
	job["claim"] = id
	var out := [go(StaffNav.at_item(id), "fetching the %s" % _part(id))]
	if it.get("boxed", false):
		out.append(work({"a": "unpack", "item": id}, 3.0, "hands", "unpacking the %s" % _part(id)))
	out.append(work({"a": "take", "item": id} if it["at"] == "floor" else {"a": "take", "spot": str(it["ref"])}, 1.0, "hands",
		"picking up the %s" % _part(id)))
	return out


## Ordering a new `part` on the parts computer (it comes boxed, to the delivery area).
static func _order(job: Dictionary, part: String) -> Array:
	var orders: Dictionary = job.get("orders", {}) if job.get("orders") is Dictionary else {}
	if int(orders.get(part, 0)) >= 3:
		job["fail"] = "I've ordered the %s three times now and still haven't got one. Something's up." % PartsDB.part_name(part)
		return []
	var s := work({"a": "order_part", "part": part}, 4.0, "type", "ordering a %s" % PartsDB.part_name(part))
	s["after"] = "ordered:" + part
	return [go(StaffNav.computer(), "going to the parts computer"), s, plan_step()]


## Unbolting and taking off whatever's in `slot`.
static func _remove(bike: int, slot: String) -> Array:
	var out := [go(StaffNav.bike(bike), "going over to the %s" % _bike_name(bike))]
	if Shed.is_bolted(bike, slot):
		out.append(work({"a": "unbolt", "bike": bike, "slot": slot, "crouched": true}, 4.0, "wrench", "unbolting the %s" % _slot(slot)))
	out.append(work({"a": "remove", "bike": bike, "slot": slot, "crouched": true}, 2.5, "hands", "taking the %s off" % _slot(slot)))
	return out


## Fitting the part in their hands to `slot` and bolting it up.
static func _install(bike: int, slot: String, held: int) -> Array:
	return [go(StaffNav.bike(bike), "carrying the %s over" % _part(held)),
		work({"a": "install", "bike": bike, "slot": slot, "crouched": true}, 3.0, "hands", "fitting the %s" % _part(held)),
		work({"a": "bolt", "bike": bike, "slot": slot, "crouched": true}, 4.0, "wrench", "bolting up the %s" % _slot(slot)), plan_step()]


## Putting down what's in their hands: worn parts and empty bottles in the right bin (`bin_it`),
## old oil tipped away, fluids and stock on the workbench, parts taken off a bike on the floor
## beside it to go back on.
static func _stow(job: Dictionary, held: int, bike: int, bin_it: bool) -> Array:
	var it: Dictionary = Shed.items[held]
	var part := str(it["part"])
	var fluid_left := float(it.get("fluid", {}).get("litres", 0.0))
	if PartsDB.is_fluid(part):
		var empty_kind: bool = PartsDB.get_part(part).get("empty", false)
		if empty_kind and fluid_left > 0.001:
			return [go(_bin_place("general"), "taking the old %s to the bin" % PartsDB.KIND_NAMES.get(PartsDB.fluid_kind(part), "fluid").to_lower()),
				work({"a": "tip", "bin": "general"}, 2.5, "pour", "tipping the old stuff away"), plan_step()]
		if not empty_kind and fluid_left <= 0.001:
			var which := PartsDB.bin_for(part)
			return [go(_bin_place(which), "taking the empty to the bin"), work({"a": "bin", "bin": which}, 1.0, "hands", "recycling the empty"), plan_step()]
		return _to_bench(held) + [plan_step()]
	if bin_it and not _refitting(job, held):
		var which := PartsDB.bin_for(part)
		if Shed.bin_check(held, which) != "":
			which = "general"
		return [go(_bin_place(which), "taking the old %s to the bin" % _part(held)),
			work({"a": "bin", "bin": which}, 1.0, "hands", "binning the old %s" % _part(held)), plan_step()]
	var k := (job["dropped"] as Array).size()
	(job["dropped"] as Array).append(held)
	return [go(StaffNav.bike(bike), "putting the %s down" % _part(held)),
		work({"a": "drop", "xf": StaffNav.floor_by(bike, k)}, 1.0, "hands", "putting the %s down by the bike" % _part(held)), plan_step()]


static func _refitting(job: Dictionary, item: int) -> bool:
	for r in job.get("refit", []):
		if int(r["item"]) == item:
			return true
	return false


## On the workbench: the first free place on it, or the floor in front of it.
static func _to_bench(held: int) -> Array:
	var spot := Shed._free_spot()
	if Shed.item_at_spot(spot) == 0:
		return [go(StaffNav.at_spot(spot), "taking the %s to the bench" % _part(held)),
			work({"a": "place", "spot": spot}, 1.0, "hands", "putting the %s on the bench" % _part(held))]
	var at := Vector3(-5.0, 0.0, 62.9 + 0.4 * (held % 10))
	return [go(StaffNav.bench(0), "taking the %s to the bench" % _part(held)),
		work({"a": "drop", "xf": Transform3D(Basis(), at)}, 1.0, "hands", "putting the %s down by the bench" % _part(held))]


## Stood at a bin by the roller door.
static func _bin_place(which: String) -> Dictionary:
	var x := Workshop.CENTER.x + float(Workshop.BINS.get(which, Workshop.BINS["general"])[0])
	return StaffNav.place("shed_door", [Vector3(x, 0.0, 69.3)], PI)


## Fitting `part` to `slot` on `bike` (whatever's there coming off first, and what's bolted on
## that coming off and going back on after), until it's on and bolted. [] when it is. Old
## parts go in the bin with `bin_old` (a service), else on the floor by the bike.
static func _fit(w: Dictionary, job: Dictionary, bike: int, slot: String, part: String, bin_old: bool, old := 0) -> Array:
	var held := _held(w)
	var on := Shed.item_on(bike, slot)
	if PartsDB.SLOT_KIND.get(slot, "") == "tyre":
		return _fit_tyre(w, job, bike, slot, part, old)
	if on != 0 and str(Shed.items[on]["part"]) == part and on != old:
		if held != 0 and not _refitting(job, held):
			return _stow(job, held, bike, bin_old)
		if not Shed.is_bolted(bike, slot):
			return [go(StaffNav.bike(bike), "going back to the %s" % _bike_name(bike)),
				work({"a": "bolt", "bike": bike, "slot": slot, "crouched": true}, 4.0, "wrench", "bolting up the %s" % _slot(slot)), plan_step()]
		return _refit_next(w, job, bike, held)
	if held != 0:
		var it: Dictionary = Shed.items[held]
		if str(it["part"]) == part and on == 0 and not it.get("boxed", false) and held != old:
			return _install(bike, slot, held)
		return _stow(job, held, bike, bin_old)
	if on != 0:
		var dep := _first_off(bike, slot)
		if dep != "":
			if str(w["role"]) != "expert":
				job["fail"] = "The %s has to come off first. That's one for an expert mechanic." % _slot(dep)
				return []
			(job["refit"] as Array).append({"slot": dep, "item": Shed.item_on(bike, dep)})
			return _remove(bike, dep) + [plan_step()]
		return _remove(bike, slot) + [plan_step()]
	var stock := find_stock(part, job)
	if stock != 0:
		return _fetch(job, stock) + [plan_step()]
	return _order(job, part)


## The next part that came off to get at the job going back on (last off, first on). [] when
## they're all back.
static func _refit_next(_w: Dictionary, job: Dictionary, bike: int, held: int) -> Array:
	var refit: Array = job["refit"]
	for i in range(refit.size() - 1, -1, -1):
		var r: Dictionary = refit[i]
		var item := int(r["item"])
		var slot := str(r["slot"])
		if not Shed.items.has(item):
			refit.remove_at(i)
			continue
		if Shed.item_on(bike, slot) == item:
			if not Shed.is_bolted(bike, slot):
				return [go(StaffNav.bike(bike), "back at the %s" % _bike_name(bike)),
					work({"a": "bolt", "bike": bike, "slot": slot, "crouched": true}, 4.0, "wrench", "bolting the %s back up" % _slot(slot)), plan_step()]
			continue
		if held == item:
			return _install(bike, slot, held)
		if held != 0:
			return _stow(job, held, bike, false)
		return _fetch(job, item) + [plan_step()]
	if held != 0:
		return _stow(job, held, bike, false)
	return []


## A new tyre (expert mechanics): the wheel off (and what's on it), onto the tyre changer, the
## old tyre levered off and put by, the new one worked on, the wheel back on with it.
static func _fit_tyre(w: Dictionary, job: Dictionary, bike: int, slot: String, part: String, old := 0) -> Array:
	var wheel_slot := "front_wheel" if slot == "front_tyre" else "rear_wheel"
	var held := _held(w)
	var on := Shed.item_on(bike, slot)
	var changer := Shed.changer_spot()
	if on != 0 and str(Shed.items[on]["part"]) == part and on != old:
		if held != 0 and not _refitting(job, held) and held != int(job.get("wheel", 0)):
			return _stow(job, held, bike, false)
		return _refit_next(w, job, bike, held)
	var wheel := int(job.get("wheel", 0))
	if wheel == 0 or not Shed.items.has(wheel):
		wheel = Shed.item_on(bike, wheel_slot)
		if wheel == 0:
			job["fail"] = "There's no wheel on it for a tyre."
			return []
		job["wheel"] = wheel
	var wit: Dictionary = Shed.items[wheel]
	if wit["at"] == "bike":
		if held != 0:
			return _stow(job, held, bike, false)
		var dep := _first_off(bike, wheel_slot)
		if dep != "" and dep != slot:
			(job["refit"] as Array).append({"slot": dep, "item": Shed.item_on(bike, dep)})
			return _remove(bike, dep) + [plan_step()]
		# The wheel comes off with its tyre (Shed: "remove"), to go on the changer.
		return _remove(bike, wheel_slot) + [plan_step()]
	var on_changer: bool = wit["at"] == "spot" and str(wit["ref"]) == changer
	var tyre := Shed.tyre_on_wheel(wheel)
	if held == wheel:
		if tyre != 0 and str(Shed.items[tyre]["part"]) == part and tyre != old:
			# The new tyre's on: the wheel goes back on the bike.
			(job["refit"] as Array).push_front({"slot": wheel_slot, "item": wheel})
			return _install(bike, wheel_slot, held)
		if changer == "" or Shed.item_at_spot(changer) != 0:
			job["fail"] = "Somebody's using the tyre changer."
			return []
		return [go(StaffNav.at_spot(changer), "taking the wheel to the tyre changer"),
			work({"a": "place", "spot": changer}, 1.5, "hands", "clamping the wheel on the changer"), plan_step()]
	if on_changer:
		if tyre != 0 and (str(Shed.items[tyre]["part"]) != part or tyre == old):
			if held != 0:
				return _stow(job, held, bike, false)
			return [go(StaffNav.at_spot(changer), "at the tyre changer"),
				work({"a": "tyre_remove", "spot": changer}, 6.0, "wrench", "levering the old tyre off"), plan_step()]
		if tyre == 0:
			if held != 0 and str(Shed.items[held]["part"]) == part and not Shed.items[held].get("boxed", false) and held != old:
				return [go(StaffNav.at_spot(changer), "at the tyre changer"),
					work({"a": "tyre_fit", "spot": changer, "quality": "q"}, 8.0, "wrench", "working the new tyre on"), plan_step()]
			if held != 0:
				# The old tyre: on the floor by the bike, for the crew to bin or keep.
				var k := (job["dropped"] as Array).size()
				(job["dropped"] as Array).append(held)
				return [work({"a": "drop", "xf": StaffNav.floor_by(bike, k)}, 1.0, "hands", "putting the old tyre down"), plan_step()]
			var stock := find_stock(part, job)
			if stock != 0:
				return _fetch(job, stock) + [plan_step()]
			return _order(job, part)
		# The new tyre's on: the wheel comes off the changer.
		if held != 0:
			return _stow(job, held, bike, false)
		return [go(StaffNav.at_spot(changer), "at the tyre changer"),
			work({"a": "take", "spot": changer}, 1.5, "hands", "lifting the wheel off the changer"), plan_step()]
	# The wheel's somewhere else (put down, or after a save was opened): fetch it.
	if held != 0:
		return _stow(job, held, bike, false)
	return _fetch(job, wheel) + [plan_step()]


# ---------------------------------------------------------------------------- service

## A service: the chain set and lubed, worn pads, plugs and filters renewed, old oil out and
## fresh in (and brake fluid, for an expert), one thing at a time.
static func _service(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	var did: Array = job["did"]
	var sub = job.get("sub")
	if sub is Dictionary:
		var out := _fit(w, job, b, str(sub["slot"]), str(sub["part"]), true, int(sub.get("old", 0)))
		if not out.is_empty() or job.has("fail"):
			return out
		job.erase("sub")
		did.append(_slot(str(sub["slot"])))
	var held := _held(w)
	var need := _service_need(w, job, b)
	if need.is_empty():
		if held != 0:
			return _stow(job, held, b, false)
		job["report"] = "The %s's serviced: %s." % [_bike_name(b), ", ".join(did) if not did.is_empty() else "it didn't need anything"]
		return []
	var tool_kind := str(need.get("tool", ""))
	if held != 0 and (tool_kind == "" or not _is_tool(held, need)):
		return _stow(job, held, b, false)
	if tool_kind != "" and held == 0:
		var stock := find_stock("", job, float(need.get("min", 0.02)), tool_kind) if tool_kind != "drain_pan" and tool_kind != "bleed_bottle" \
			else find_stock(tool_kind, job, 0.0)
		if stock != 0:
			return _fetch(job, stock) + [plan_step()]
		return _order(job, str(need["order"]))
	match str(need["task"]):
		"chain":
			did.append("chain adjusted")
			return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
				work({"a": "adjust_chain", "bike": b, "crouched": true}, 6.0, "wrench", "setting the chain tension"), plan_step()]
		"lube":
			did.append("chain lubed")
			job["lubed"] = int(job.get("lubed", 0)) + 1
			return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
				work({"a": "lube", "item": int(need["item"]), "quality": "q", "waste": "w", "crouched": true}, 6.0, "spray", "lubing the chain"), plan_step()]
		"part":
			job["sub"] = {"slot": str(need["slot"]), "part": str(need["part"]), "old": int(need["old"])}
			return _fit(w, job, b, str(need["slot"]), str(need["part"]), true, int(need["old"]))
		"drain":
			job["drained_" + str(need["slot"])] = true
			return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
				work({"a": "drain", "item": int(need["item"]), "crouched": true}, 6.0, "pour", "draining the old %s" % str(need["what"])), plan_step()]
		"fill":
			if not did.has(str(need["done"])):
				did.append(str(need["done"]))
			job["filled_" + str(need["slot"])] = int(job.get("filled_" + str(need["slot"]), 0)) + 1
			return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
				work({"a": "pour", "item": int(need["item"])}, 5.0, "pour", "topping up the %s" % str(need["what"])), plan_step()]
	return []


static func _is_tool(held: int, need: Dictionary) -> bool:
	var part := str(Shed.items[held]["part"])
	var k := str(need.get("tool", ""))
	if k == "drain_pan" or k == "bleed_bottle":
		return part == k
	return PartsDB.kind_of(part) == k and not PartsDB.get_part(part).get("empty", false) \
		and float(Shed.items[held].get("fluid", {}).get("litres", 0.0)) >= float(need.get("min", 0.02))


## The next thing a service needs doing ({} when it's all done): {task, tool (a kind of can or
## container to have in hand), order (what to buy if there's none), ...}.
static func _service_need(w: Dictionary, job: Dictionary, b: int) -> Dictionary:
	var chain := Shed.item_on(b, "chain")
	if chain != 0 and not job.get("chain_done", false):
		var slack := float(Shed.items[chain].get("slack", Shed.CHAIN_SLACK_SET))
		if (slack < Shed.CHAIN_SLACK_GOOD.x or slack > Shed.CHAIN_SLACK_GOOD.y) and absf(slack - Shed.CHAIN_SLACK_SET) >= 3.0:
			return {"task": "chain"}
		if float(Shed.items[chain].get("lube", 0.0)) < 0.6 and int(job.get("lubed", 0)) < 2:
			return {"task": "lube", "item": chain, "tool": "chain_lube", "min": Shed.LUBE_USE, "order": DEFAULT_LUBE}
	for slot in SERVICE_PARTS:
		var id := Shed.item_on(b, slot)
		if id == 0 or (job["did"] as Array).has(_slot(slot)):
			continue
		var it: Dictionary = Shed.items[id]
		if float(it["wear"]) > WORN or (slot.ends_with("filter") and float(it["dirt"]) > 0.6):
			return {"task": "part", "slot": slot, "part": str(it["part"]), "old": id}
	var fluids := [["engine", "oil", "drain_pan", "oil", DEFAULT_OIL, "oil changed"]]
	if str(w["role"]) == "expert":
		fluids.append(["front_master", "brake_fluid", "bleed_bottle", "brake fluid", DEFAULT_BRAKE, "brake fluid renewed"])
		fluids.append(["rear_master", "brake_fluid", "bleed_bottle", "brake fluid", DEFAULT_BRAKE, "brake fluid renewed"])
	for f in fluids:
		var id := Shed.item_on(b, str(f[0]))
		if id == 0 or not Shed.items[id].has("fluid"):
			continue
		var fl: Dictionary = Shed.items[id]["fluid"]
		var cap := PartsDB.fluid_capacity(str(Shed.items[id]["part"]))
		var key := str(f[0])
		if float(fl.get("age", 0.0)) > 0.15 and float(fl["litres"]) > 0.02 and not job.get("drained_" + key, false):
			return {"task": "drain", "slot": key, "item": id, "tool": str(f[2]), "order": str(f[2]), "what": str(f[3])}
		if float(fl["litres"]) < cap * 0.97 and int(job.get("filled_" + key, 0)) < 4:
			return {"task": "fill", "slot": key, "item": id, "tool": str(f[1]), "min": 0.05, "order": str(f[4]), "what": str(f[3]),
				"done": str(f[5])}
	return {}


# ---------------------------------------------------------------------------- paint

## A respray: the part off the bike (ground back on the repair machine first if it's rusty), hung
## in the booth, the colour mixed at the bench, primed (after a repair) and sprayed, left to
## flash off, and back on the bike bolted up.
static func _paint(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	var slot := str(job["slot"])
	var id := int(job.get("item", 0))
	if id == 0 or not Shed.items.has(id):
		job["fail"] = "The %s has gone." % _slot(slot)
		return []
	var it: Dictionary = Shed.items[id]
	var held := _held(w)
	if held != 0 and held != id:
		return _stow(job, held, b, false)
	if job.get("painted", false):
		if it["at"] == "bike":
			if not Shed.is_bolted(b, slot):
				return [go(StaffNav.bike(b), "back at the %s" % _bike_name(b)),
					work({"a": "bolt", "bike": b, "slot": slot, "crouched": true}, 4.0, "wrench", "bolting the %s back on" % _slot(slot)), plan_step()]
			job["report"] = "The %s's %s is %s now: %s." % [_bike_name(b), _slot(slot), Shed.paint_text(it).to_lower(),
				Shed.finish_text(it).to_lower() if Shed.finish_text(it) != "" else "lovely"]
			return []
		if held == id:
			return _install(b, slot, id)
		if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) == "booth":
			return [go(StaffNav.at_spot(str(it["ref"])), "at the booth"),
				work({"a": "take", "spot": str(it["ref"])}, 1.5, "hands", "unhooking the %s" % _slot(slot)), plan_step()]
		return _fetch(job, id) + [plan_step()]
	if it["at"] == "bike":
		var dep := _blocking(b, slot)
		if dep != "":
			job["fail"] = "The %s has to come off first. Get a mechanic on it." % _slot(dep)
			return []
		return _remove(b, slot) + [plan_step()]
	if held == id:
		if float(it["rust"]) > Shed.MAX_PAINT_RUST:
			var rspot := _free_spot_of("repair")
			if rspot == "":
				job["fail"] = "It's too rusty to paint and the repair machines are full."
				return []
			return [go(StaffNav.at_spot(rspot), "taking the %s to the repair machine" % _slot(slot)),
				work({"a": "place", "spot": rspot}, 1.5, "hands", "putting the %s on the repair machine" % _slot(slot)), plan_step()]
		var bspot := _free_booth_spot()
		if bspot == "":
			job["fail"] = "Every hook in the booth's taken."
			return []
		return [go(StaffNav.at_spot(bspot), "taking the %s to the paint booth" % _slot(slot)),
			work({"a": "place", "spot": bspot}, 2.0, "hands", "hanging the %s in the booth" % _slot(slot)), plan_step()]
	if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) == "repair":
		if float(it["rust"]) >= 0.02 or float(it["wear"]) >= 0.02:
			job["repaired"] = true
			return [go(StaffNav.at_spot(str(it["ref"])), "at the repair machine"),
				work({"a": "repair", "item": id}, 10.0, "grind", "grinding the rust off the %s" % _slot(slot)), plan_step()]
		return [go(StaffNav.at_spot(str(it["ref"])), "at the repair machine"),
			work({"a": "take", "spot": str(it["ref"])}, 1.0, "hands", "picking up the %s" % _slot(slot)), plan_step()]
	if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) == "booth":
		if not job.get("mixed", false):
			return [go(StaffNav.mix_bench(), "going to the mixing bench"),
				{"do": "work", "act": {}, "secs": 10.0, "anim": "mix", "what": "mixing up the %s" % str(Shed.PAINT_NAMES[int(job["color"])])},
				flag("mixed"), plan_step()]
		var spot := str(it["ref"])
		var out := [go(StaffNav.at_spot(spot), "taking the paint to the booth")]
		if job.get("repaired", false) and not job.get("primed", false):
			out.append(work({"a": "prime", "item": id, "gun": true, "quality": "q", "waste": "w"}, 8.0, "spray", "spraying primer on the %s" % _slot(slot)))
			out.append(flag("primed"))
		out.append(work({"a": "paint", "item": id, "gun": true, "color": int(job["color"]), "finish": str(job["finish"]), "quality": "q",
			"waste": "w"}, 12.0, "spray", "spraying the %s %s" % [_slot(slot), str(Shed.PAINT_NAMES[int(job["color"])])]))
		out.append({"do": "wait", "secs": 6.0, "anim": "think", "what": "letting it flash off"})
		out.append(flag("painted"))
		out.append(plan_step())
		return out
	return _fetch(job, id) + [plan_step()]


static func _free_spot_of(role: String) -> String:
	for spot in Shed.all_spots():
		if Shed.spot_role(spot) == role and Shed.item_at_spot(spot) == 0:
			return spot
	return ""


## A free hook in the booth, the front rail (by the walkway) first.
static func _free_booth_spot() -> String:
	var best := ""
	var best_x := INF
	for spot in Shed.all_spots():
		if Shed.spot_role(spot) == "booth" and Shed.item_at_spot(spot) == 0:
			var x := Shed.spot_transform(spot).origin.x
			if x < best_x - 0.01:
				best_x = x
				best = spot
	return best


# ---------------------------------------------------------------------------- detailing

## A detailing job: the bike wheeled into the wash bay, each step of its list done in turn
## (DETAIL_STEPS), and wheeled back to its bay (or where it was).
static func _detail(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	var held := _held(w)
	if held != 0:
		return _stow(job, held, b, false)
	var todo: Array = job["todo"]
	var at: Vector3 = (Shed.bikes[b]["xf"] as Transform3D).origin
	while int(job["step"]) < todo.size():
		var step := str(todo[int(job["step"])])
		var fn := str(DETAIL_STEPS.get(step, ""))
		if fn == "":
			job["step"] = int(job["step"]) + 1
			return [{"do": "say", "text": "I've no kit to %s yet, so I'll skip that." % str(DETAIL_NAMES.get(step, step))}, plan_step()]
		if not Wash.reaches(at):
			if step == "wash" and Shed._bike_dirt(b, true) < 0.02:
				job["step"] = int(job["step"]) + 1
				continue
			return _wheel(b, StaffNav.wash_in(), Wash.lift_xf(), "the wash bay") + [plan_step()]
		var out := _detail_step(fn, w, job)
		if not out.is_empty():
			return out
		job["step"] = int(job["step"]) + 1
	# All done: back where it came from.
	var home: Transform3D = job["home_xf"]
	if at.distance_to(home.origin) > 0.4 and Wash.reaches(at):
		var bay := int(job.get("home_bay", -1))
		if bay >= 0 and Shed.bike_in_bay(bay) != 0 and Shed.bike_in_bay(bay) != b:
			job["report"] = "The %s's clean. Its bay's taken, so it's on the wash bay lift." % _bike_name(b)
			return []
		if bay >= 0:
			return _wheel(b, StaffNav.bay_in(bay), Workshop.bay_transform(bay), "its bay") + [plan_step()]
		return _wheel(b, StaffNav.place(StaffNav.nearest_node(home.origin), [home.origin]), home, "where it was") + [plan_step()]
	job["report"] = "The %s's clean as a whistle%s.%s" % [_bike_name(b), "" if job["todo"] == ["wash"] else ", all done", str(job.get("note", ""))]
	return []


## One detailing step's next steps by its planner's name (DETAIL_STEPS), [] when it's done.
static func _detail_step(fn: String, w: Dictionary, job: Dictionary) -> Array:
	match fn:
		"_detail_wash":
			return _detail_wash(w, job)
		"_detail_polish":
			return _detail_shine(w, job, "polish", "polishing")
		"_detail_ceramic":
			return _detail_shine(w, job, "coat", "ceramic coating")
	return []


## Polishing or ceramic coating (Detail step `step`) with the polisher, a few passes at a time,
## as well as their level lets them (a beginner sometimes burns through or leaves a smear).
static func _detail_shine(w: Dictionary, job: Dictionary, step: String, doing: String) -> Array:
	var b := int(job["bike"])
	if Detail.step_done(b, step):
		return []
	if step == "polish" and int(Detail.bike_stats(b)["burns"]) > 0:
		job["note"] = " I burnt through the lacquer in a spot, though. That wants a respray."
		return []
	var rounds := "%s_rounds" % step
	job[rounds] = int(job.get(rounds, 0)) + 1
	if int(job[rounds]) > SHINE_ROUNDS:
		# A burn-through only a respray fixes, or a coat that won't come right: leave it there.
		job["note"] = " I couldn't get the %s right, though. It wants looking at." % str(DETAIL_NAMES.get("ceramic" if step == "coat" else step, step))
		return []
	# A detailer by trade starts part way up the scale; levels take them the rest of the way.
	var skill := lerpf(0.4, 1.0, clampf(float(Staff.level(w) - 1) / float(Staff.MAX_LEVEL - 1), 0.0, 1.0))
	var out := [go(StaffNav.wash(), "getting the polisher")]
	for i in SHINE_PASSES:
		out.append(work({"a": "shine_step", "bike": b, "step": step, "amount": 0.3, "skill": skill}, 2.5, "detail",
			"%s the %s" % [doing, _bike_name(b)]))
	out.append(plan_step())
	return out


## A wash with the pressure washer: a few passes over the whole bike at a time.
static func _detail_wash(_w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	if Shed._bike_dirt(b, true) < 0.02:
		return []
	var ids := []
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(b, slot)
		if id != 0:
			ids.append(id)
	var at: Vector3 = (Shed.bikes[b]["xf"] as Transform3D).origin + Vector3(0.0, 0.5, 0.0)
	var out := [go(StaffNav.wash(), "getting the pressure washer")]
	for i in WASH_PASSES:
		out.append(work({"a": "wash", "items": ids, "at": at}, 2.2, "lance", "pressure washing the %s" % _bike_name(b)))
	out.append(plan_step())
	return out


## Wheeling bike `b` to place `to` (let go of at `xf`): over to it, hold of it, push.
static func _wheel(b: int, to: Dictionary, xf: Transform3D, where: String) -> Array:
	return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
		work({"a": "grab_bike", "bike": b}, 1.2, "hands", "getting hold of the %s" % _bike_name(b)),
		{"do": "push", "bike": b, "to": to, "xf": xf, "from": StaffNav.bike_out(b), "what": "wheeling it to %s" % where}]


# ---------------------------------------------------------------------------- selling

## Selling a bike: onto a free showroom plinth, priced (the PC's recommended price unless asked
## for another), and then the salesman's duty handles the offers (Staff._sales_duty).
static func _sell(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	var held := _held(w)
	if held != 0:
		return _stow(job, held, b, false)
	var stand := Sales.stand_of(b)
	if stand >= 0 and Sales.listings().has(b):
		job["report"] = "The %s's up on stand %d at %s. I'll deal with the buyers." % [_bike_name(b), stand + 1,
			Staff.money(int(Sales.listings()[b]["ask"]))]
		return []
	if stand >= 0:
		return [go(StaffNav.show_side(stand), "going to the %s" % _bike_name(b)),
			work({"a": "staff_sell_list"}, 5.0, "talk", "pricing up the %s" % _bike_name(b)), plan_step()]
	var free := -1
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		if Sales.bike_on_stand(i) == 0:
			free = i
			break
	if free < 0:
		job["fail"] = "The showroom's full. Clear a plinth and I'll put it on."
		return []
	return _wheel(b, StaffNav.show_in(free), SalesOffice.SHOWROOM_SPOTS[free], "the showroom") + [plan_step()]


## Puts the bike up for sale at the asking price.
static func list_bike(w: Dictionary, job: Dictionary) -> String:
	var b := int(job["bike"])
	var ask := int(job.get("ask", 0))
	if ask <= 0:
		ask = int(Sales.appraise(b).get("recommended", 0))
	return Staff.act(w, {"a": "sale_list", "bike": b, "ask": maxi(ask, 10)})


# ---------------------------------------------------------------------------- teas

## A tea run: over to the cafe, a round on a tray (paid for by the business), back to the shed
## and down on the end of the workbench for everyone.
static func _tea(w: Dictionary, job: Dictionary) -> Array:
	var peer := Staff.peer_of(int(w["id"]))
	if job.get("down", false):
		for id in Staff.workers():
			var o: Dictionary = Staff.workers()[id]
			o["mood"] = minf(1.0, float(o["mood"]) + 0.12)
		job["report"] = "Tea's up! On the end of the workbench."
		return []
	var tray := CoffeeShop.tray_of(peer)
	if not tray.is_empty() and not (tray["items"] as Array).is_empty():
		return [go(StaffNav.tea_spot(), "bringing the teas back"),
			work({"a": "coffee_tray_down", "xf": StaffNav.tea_xf()}, 1.5, "hands", "putting the tray down"), flag("down"), plan_step()]
	if not CoffeeShop.is_open():
		job["fail"] = "The cafe's shut till %s. No teas, sorry." % Daylight.clock_text(CoffeeShop.OPEN_HOUR)
		return []
	return [go(StaffNav.cafe_counter(), "walking over to the cafe"),
		work({"a": "staff_tea_round"}, 6.0, "talk", "ordering a round"), plan_step()]


## Orders the round at the counter: a tea or coffee for everyone in (up to a tray's worth), paid
## from the business's account. "" or why not.
static func buy_round(w: Dictionary, _job: Dictionary) -> String:
	var n := clampi(Shed.crew.size() + Staff.workers().size(), 2, CoffeeShop.TRAY_MAX)
	var round := []
	for i in n:
		round.append("tea" if i % 2 == 0 else "coffee")
	if n >= 3:
		round[n - 1] = "cake"
	var total := 0
	for item in round:
		total += CoffeeShop.price(item)
	if not CoffeeShop.is_open():
		return "The cafe's just shut."
	if not Shed.charge_garage(total, "Teas for the crew"):
		return "The business can't even stand a round of teas."
	for item in round:
		var why := Staff.act(w, {"a": "coffee_buy", "item": item, "paid": CoffeeShop.price(item)})
		if why != "":
			return why
	return ""
