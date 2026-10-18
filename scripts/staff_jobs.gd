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
		"project":
			# The list as it stands now, worked through in order (see _project).
			var tasks := project_tasks(b, j.get("tasks", []))
			job["tasks"] = tasks
			job["state"] = tasks.map(func(_t): return "todo")
			job["notes"] = tasks.map(func(_t): return "")
			job["looks"] = tasks.map(func(_t): return 0)
			job["ti"] = 0
			job["did"] = []
			job["label"] = "Working through the %s's job list" % _bike_name(b)
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
	if Staff.BIKE_JOBS.has(str(job["kind"])):
		if not Shed.bikes.has(b):
			job["fail"] = "The bike's gone, so that's that."
			return []
		if int(Shed.bikes[b].get("rider", 0)) != 0:
			return [{"do": "wait", "secs": 6.0, "anim": "think", "what": "waiting for the bike to come back"}, plan_step()]
	match str(job["kind"]):
		"service":
			return _service(w, job)
		"project":
			return _project(w, job)
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
	if key.begins_with("kit:"):
		# The part just ordered (the newest of it in the shed) is this job's.
		var part := key.substr(4)
		var newest := 0
		for id in Shed.items:
			if str(Shed.items[id]["part"]) == part and int(id) > newest and not (job.get("kit", []) as Array).has(int(id)):
				newest = int(id)
		if newest != 0:
			if not (job.get("kit") is Array):
				job["kit"] = []
			(job["kit"] as Array).append(newest)
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
		if other != job:
			taken.append_array(other.get("kit", []))
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
		# What they bought for this job first (on the trolley by now), then what's on the staff rack.
		if (job.get("kit", []) as Array).has(int(id)):
			score -= 20.0
		elif it["at"] == "spot" and Shed.furniture_of_spot(str(it["ref"])).get("model", "") == Shed.STAFF_RACK:
			score -= 2.0
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


# ---------------------------------------------------------------------------- the expert's kit

## How many spares of `part` there are in the shed for this job (as find_stock would take them).
static func _stock_count(part: String, job: Dictionary) -> int:
	var taken := []
	for id in Staff.workers():
		var other: Dictionary = Staff.workers()[id]["job"]
		if other != job:
			taken.append(int(other.get("claim", 0)))
			taken.append_array(other.get("kit", []))
	var n := 0
	for id in Shed.items:
		var it: Dictionary = Shed.items[id]
		if str(it["part"]) != part or not it["at"] in ["floor", "spot"] or taken.has(int(id)) or (job["dropped"] as Array).has(int(id)):
			continue
		if it["at"] == "spot" and Shed.spot_role(str(it["ref"])) in ["booth", "blaster", "stand", "changer", "repair"]:
			continue
		if float(it["wear"]) > 0.2 or float(it["rust"]) > 0.2:
			continue
		n += 1
	return n


## Everything a service or a project still needs buying, worked out all at once (an expert
## mechanic orders the lot in one go): new parts for whatever's to be renewed or fitted, and the
## oil, lube, brake fluid and drain pans it wants when there's none in the shed.
static func kit_list(w: Dictionary, job: Dictionary, b: int) -> Array:
	var parts := []
	var keys := []   # the service tasks, [] with "all" for a whole service
	var all := str(job["kind"]) == "service"
	if str(job["kind"]) == "project":
		var tasks: Array = job["tasks"]
		for i in range(int(job.get("ti", 0)), tasks.size()):
			var t: Dictionary = tasks[i]
			if str(job["state"][i]) in ["done", "skipped"] or task_why(w, b, t) != "" or task_done(b, t):
				continue
			if str(t["t"]) == "task" and SERVICE_TASKS.has(str(t["task"])):
				keys.append(str(t["task"]))
				continue
			for slot in task_slots(t):
				var on := Shed.item_on(b, str(slot))
				match str(t["t"]):
					"part":
						if on == 0 or str(Shed.items[on]["part"]) != str(t["part"]):
							parts.append(str(t["part"]))
					"fit":
						if on == 0:
							parts.append(part_for(b, str(slot)))
					_:
						if not _renewed(b, str(slot), float(t.get("health", 0.0))):
							parts.append(part_for(b, str(slot), str(t.get("part", ""))))
	var scope := func(k: String) -> bool: return all or keys.has(k)
	for slot in SERVICE_PARTS:
		var id := Shed.item_on(b, slot)
		if id == 0 or not (all or keys.any(func(k): return Contracts.TASK_PARTS.get(str(k), []).has(slot))):
			continue
		var it: Dictionary = Shed.items[id]
		if float(it["wear"]) > WORN or (slot.ends_with("filter") and float(it["dirt"]) > (0.6 if all else 0.2)):
			parts.append(str(it["part"]))
	var chain := Shed.item_on(b, "chain")
	if scope.call("chain") and chain != 0 and float(Shed.items[chain].get("lube", 0.0)) < 0.6 \
			and find_stock("", job, Shed.LUBE_USE, "chain_lube") == 0:
		parts.append(DEFAULT_LUBE)
	var fluids := []
	if scope.call("oil"):
		fluids.append(["engine", "oil", "drain_pan", DEFAULT_OIL])
	if scope.call("brake_fluid") and str(w["role"]) == "expert":
		fluids.append(["front_master", "brake_fluid", "bleed_bottle", DEFAULT_BRAKE])
	var drained := {}
	for f in fluids:
		var id := Shed.item_on(b, str(f[0]))
		if id == 0 or not Shed.items[id].has("fluid"):
			continue
		var fl: Dictionary = Shed.items[id]["fluid"]
		if float(fl.get("age", 0.0)) > 0.15 and not drained.has(f[2]) and find_stock(str(f[2]), job, 0.0) == 0:
			drained[f[2]] = true
			parts.append(str(f[2]))
		if (float(fl.get("age", 0.0)) > 0.15 or float(fl["litres"]) < PartsDB.fluid_capacity(str(Shed.items[id]["part"])) * 0.97) \
				and find_stock("", job, 0.05, str(f[1])) == 0:
			parts.append(str(f[3]))
	# What's in the shed already comes off the list.
	var out := []
	var counted := {}
	for p in parts:
		counted[p] = int(counted.get(p, 0)) + 1
	for p in counted:
		for k in maxi(0, int(counted[p]) - _stock_count(str(p), job)):
			out.append(str(p))
	return out


## An expert's first look at a service or project: everything it needs ordered at once, the
## staff trolley wheeled out to the deliveries, loaded and wheeled to the bike. [] once that's
## done (or there was nothing to buy, or the trolley's in use), for the job to carry on as usual.
static func _kit(w: Dictionary, job: Dictionary, b: int) -> Array:
	if str(w["role"]) != "expert" or str(job.get("kit_stage", "")) == "done":
		return []
	if str(job.get("kit_stage", "")) == "":
		if not (job.get("kit") is Array):
			job["kit"] = []
		var want := kit_list(w, job, b)
		if want.is_empty():
			job["kit_stage"] = "done" if (job["kit"] as Array).is_empty() else "load"
			return _kit(w, job, b)
		var out := [go(StaffNav.computer(), "going to order everything the job needs")]
		for p in want:
			var s := work({"a": "order_part", "part": p}, 2.0, "type", "ordering a %s" % PartsDB.part_name(str(p)))
			s["after"] = "kit:" + str(p)
			out.append(s)
		out.append({"do": "say", "text": "That's the lot ordered: %d part%s. I'll fetch them on the trolley." % [want.size(), "" if want.size() == 1 else "s"]})
		out.append(flag("kit_stage", "load"))
		out.append(plan_step())
		return out
	var cart := Shed.staff_trolley()
	var peer := Staff.peer_of(int(w["id"]))
	var kit: Array = (job["kit"] as Array).filter(func(id): return Shed.items.has(int(id)) and Shed.items[int(id)]["at"] in ["floor", "spot", "held"])
	job["kit"] = kit
	var held := _held(w)
	if cart == 0 or not int(Shed.furniture[cart].get("mover", 0)) in [0, peer] or kit.is_empty():
		job["kit_stage"] = "done"
		return []
	var deck := "f%d" % cart
	var cart_at: Vector3 = (Shed.furniture[cart]["xf"] as Transform3D).origin
	var at_deliveries := cart_at.distance_to(StaffNav.spot(StaffNav.cart_delivery())) < 1.0
	if held != 0:
		if kit.has(held) and at_deliveries:
			return [go(StaffNav.cart_handle(cart), "taking the %s to the trolley" % _part(held)),
				work({"a": "staff_cart_load"}, 1.0, "hands", "loading the %s onto the trolley" % _part(held)), plan_step()]
		return _stow(job, held, b, false)
	# What's still to load and fits on the deck (the rest is fetched by hand later).
	var to_load := kit.filter(func(id): return not _on_deck(int(id), deck) and Shed.find_room(deck, int(id), Vector2.ZERO) is Transform3D)
	if not to_load.is_empty():
		if not at_deliveries:
			return _cart_to(cart, StaffNav.cart_delivery(), "wheeling the trolley out to the deliveries") + [plan_step()]
		return _fetch(job, int(to_load[0])) + [plan_step()]
	if cart_at.distance_to(StaffNav.spot(StaffNav.cart_by_bike(b))) > 1.0:
		return _cart_to(cart, StaffNav.cart_by_bike(b), "wheeling the parts over to the %s" % _bike_name(b)) + [flag("kit_stage", "done"), plan_step()]
	job["kit_stage"] = "done"
	return []


## After an expert's job: what's left of the parts they bought off the trolley and onto their
## board of the rack, and the trolley wheeled back to its place. [] when it's all put away.
static func _kit_tidy(w: Dictionary, job: Dictionary, b: int) -> Array:
	if str(w["role"]) != "expert" or not job.has("kit_stage"):
		return []
	var cart := Shed.staff_trolley()
	var held := _held(w)
	if held != 0:
		if PartsDB.is_fluid(str(Shed.items[held]["part"])):
			return _stow(job, held, b, false)
		return _to_rack(w, held) + [plan_step()]
	if cart == 0:
		return []
	var deck := "f%d" % cart
	for id in job.get("kit", []):
		if Shed.items.has(int(id)) and _on_deck(int(id), deck):
			return _fetch(job, int(id)) + [plan_step()]
	var peer := Staff.peer_of(int(w["id"]))
	var home := StaffNav.spot(StaffNav.cart_park())
	if (Shed.furniture[cart]["xf"] as Transform3D).origin.distance_to(home) > 0.6 and int(Shed.furniture[cart].get("mover", 0)) in [0, peer]:
		return _cart_to(cart, StaffNav.cart_park(), "wheeling the trolley back") + [plan_step()]
	return []


static func _on_deck(id: int, deck: String) -> bool:
	var it: Dictionary = Shed.items.get(id, {})
	return it.get("at", "") == "spot" and Shed.surface_of_spot(str(it["ref"])) == deck


## Over to a trolley's handle, hold of it, and wheel it to place `to`.
static func _cart_to(cart: int, to: Dictionary, what: String) -> Array:
	return [go(StaffNav.cart_handle(cart), "going over to the trolley"),
		work({"a": "grab", "furniture": cart}, 1.0, "hands", "taking hold of the trolley"),
		{"do": "cart", "furniture": cart, "to": to, "what": what}]


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
		return _to_rack(Staff.worker(int(job.get("wid", 0))), held) + [plan_step()]
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


## Onto their own board of the staff parts rack (see rack_down), or the workbench if there's no
## rack.
static func _to_rack(w: Dictionary, held: int) -> Array:
	if Shed.staff_rack() == 0:
		return _to_bench(held)
	return [go(StaffNav.rack(), "taking the %s to the parts rack" % _part(held)),
		work({"a": "staff_rack_down"}, 1.2, "hands", "putting the %s on the %s board" % [_part(held), _bin_name(w)])]


static func _bin_name(w: Dictionary) -> String:
	return str(Staff.RACK_BINS[int(Staff.RACK_LEVEL.get(str(w.get("role", "")), 0))]).to_lower()


## The board of the staff rack worker `w` keeps parts on, and a place on it for `item` (in the
## board's frame, along from where theirs go), or [] when it's full: [surface key, place].
static func _rack_place(w: Dictionary, item: int) -> Array:
	var rack := Shed.staff_rack()
	if rack == 0:
		return []
	var mine := int(Staff.RACK_LEVEL.get(str(w.get("role", "")), 0))
	var levels := int(Equipment.get_model(Shed.STAFF_RACK).get("levels", 4))
	for k in levels:
		var key := "f%ds%d" % [rack, (mine + k) % levels]
		var rect: Rect2 = Shed.surface(key)["rect"]
		var place = Shed.find_room(key, item, Vector2(rect.position.x + 0.15, 0.0))
		if place is Transform3D:
			return [key, place]
	return []


## Puts what they're holding down on their board of the staff rack. "" or why not.
static func rack_down(w: Dictionary) -> String:
	var held := _held(w)
	if held == 0:
		return "I've nothing to put away."
	var at := _rack_place(w, held)
	if at.is_empty():
		return "The parts rack's full."
	return Staff.act(w, {"a": "set_down", "top": at[0], "xf": at[1]})


## Host: a part a worker had hold of goes back on their board of the rack (letting go of it, when
## they're let go, go off sick or a save's opened), else on the workbench.
static func put_on_rack(w: Dictionary, item: int) -> void:
	var at := _rack_place(w, item)
	if at.is_empty():
		Shed._put_on_bench(item)
		return
	Shed._move(item, "spot", Shed._free_surface_spot(at[0]))
	Shed.items[item]["place"] = at[1]


## Puts what they're holding on the trolley's deck. "" or why not.
static func cart_load(w: Dictionary) -> String:
	var held := _held(w)
	var cart := Shed.staff_trolley()
	if held == 0 or cart == 0:
		return "Nothing to load."
	var key := "f%d" % cart
	var place = Shed.find_room(key, held, Vector2.ZERO)
	if not (place is Transform3D):
		# No room after all: it goes down beside the trolley, to be fetched by hand.
		var xf: Transform3D = Shed.furniture[cart]["xf"]
		var at := xf.origin + xf.basis.x.normalized() * 0.7
		at.y = 0.0
		return Staff.act(w, {"a": "drop", "xf": Transform3D(Basis(), at)})
	return Staff.act(w, {"a": "set_down", "top": key, "xf": place})


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
	var kit := _kit(w, job, b)
	if not kit.is_empty():
		return kit
	var out := _service_core(w, job, b, [])
	if not out.is_empty() or job.has("fail"):
		return out
	var tidy := _kit_tidy(w, job, b)
	if not tidy.is_empty():
		return tidy
	var held := _held(w)
	if held != 0:
		return _stow(job, held, b, false)
	var did: Array = job["did"]
	job["report"] = "The %s's serviced: %s." % [_bike_name(b), ", ".join(did) if not did.is_empty() else "it didn't need anything"]
	return []


## The next steps of a service, or of just the service tasks in `only` (Contracts.TASKS keys:
## oil, chain, pads, filters, plugs, brake_fluid; [] for the lot). [] when there's nothing more
## to do for them (what's in their hands is left to the caller).
static func _service_core(w: Dictionary, job: Dictionary, b: int, only: Array) -> Array:
	var did: Array = job["did"]
	var sub = job.get("sub")
	if sub is Dictionary:
		var out := _fit(w, job, b, str(sub["slot"]), str(sub["part"]), bool(sub.get("bin", true)), int(sub.get("old", 0)))
		if not out.is_empty() or job.has("fail"):
			return out
		job.erase("sub")
		did.append(_slot(str(sub["slot"])))
	var held := _held(w)
	var need := _service_need(w, job, b, only)
	if need.is_empty():
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
static func _service_need(w: Dictionary, job: Dictionary, b: int, only: Array = []) -> Dictionary:
	var chain := Shed.item_on(b, "chain")
	var all := only.is_empty()
	if chain != 0 and not job.get("chain_done", false) and (all or only.has("chain")):
		var slack := float(Shed.items[chain].get("slack", Shed.CHAIN_SLACK_SET))
		if (slack < Shed.CHAIN_SLACK_GOOD.x or slack > Shed.CHAIN_SLACK_GOOD.y) and absf(slack - Shed.CHAIN_SLACK_SET) >= 3.0:
			return {"task": "chain"}
		if float(Shed.items[chain].get("lube", 0.0)) < 0.6 and int(job.get("lubed", 0)) < 2:
			return {"task": "lube", "item": chain, "tool": "chain_lube", "min": Shed.LUBE_USE, "order": DEFAULT_LUBE}
	for slot in SERVICE_PARTS:
		var id := Shed.item_on(b, slot)
		if id == 0 or (job["did"] as Array).has(_slot(slot)):
			continue
		if not all and not only.any(func(k): return Contracts.TASK_PARTS.get(str(k), []).has(slot)):
			continue
		var it: Dictionary = Shed.items[id]
		# Asked for by name (a job card's "air and oil filters renewed"), a dirty filter's renewed too.
		if float(it["wear"]) > WORN or (slot.ends_with("filter") and float(it["dirt"]) > (0.6 if all else 0.2)):
			return {"task": "part", "slot": slot, "part": str(it["part"]), "old": id}
	var fluids := []
	if all or only.has("oil"):
		fluids.append(["engine", "oil", "drain_pan", "oil", DEFAULT_OIL, "oil changed"])
	if str(w["role"]) == "expert" and (all or only.has("brake_fluid")):
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


# ---------------------------------------------------------------------------- projects

## The kinds of task on a project's list (plain data, like a job card's goals):
##   {t: "task", task}          a Contracts.TASKS job (oil, chain, pads, a new tyre...)
##   {t: "part", slot, part}    that part fitted in that slot
##   {t: "fit", slot}           something fitted in an empty slot (the bike's own part)
##   {t: "renew", slot, part}   the part in that slot renewed like for like (or fitted if gone);
##                              with "health", the part on has to be at least that good too
##   {t: "bolt"}                everything on it bolted up
##   {t: "other", why}          on the list, but not a mechanic's work (skipped, with why)
## Each has "text", what the list says.
const TASK_TYPES: Array[String] = ["task", "part", "fit", "renew", "bolt", "other"]
## Service tasks done the way a service does them, the rest by renewing the parts they cover.
const SERVICE_TASKS: Array[String] = ["oil", "chain", "pads", "filters", "plugs", "brake_fluid"]
## Looks at one task before they give it up as not coming right.
const MAX_TASK_LOOKS := 60


## The work listed for bike `bike_id`, in order: `given` (a list handed over with the job, such
## as the bay's workflow screen's), else its customer's job card (MOT fails worked out from a
## fresh inspection), an insurer's repair list, or for the shed's own bikes the assessment's
## parts to replace and anything missing. [] when nothing's listed.
static func project_tasks(bike_id: int, given = []) -> Array:
	if not Shed.bikes.has(bike_id):
		return []
	var out := []
	if given is Array and not (given as Array).is_empty():
		for t in given:
			if t is Dictionary and TASK_TYPES.has(str(t.get("t", ""))):
				_add_task(out, (t as Dictionary).duplicate(true))
		return out
	var cj := Contracts.job_for_bike(bike_id)
	if not cj.is_empty() and str(cj.get("kind", "")) != "batch":
		for g in cj.get("goals", []):
			match str(g.get("t", "")):
				"task":
					_add_task(out, {"t": "task", "task": str(g["task"])})
				"part":
					_add_task(out, {"t": "part", "slot": str(g["slot"]), "part": str(g["part"])})
				"fit":
					_add_task(out, {"t": "fit", "slot": str(g["slot"])})
				"pipes":
					var from := str(g.get("from", ""))
					_add_task(out, {"t": "part", "slot": "exhaust", "part": "full_system" if from != "full_system" else "titanium_race",
						"text": Contracts.goal_text(g)})
				"mot":
					for t in mot_tasks(bike_id):
						_add_task(out, t)
				_:
					_add_task(out, {"t": "other", "text": Contracts.goal_text(g), "why": "That one's not spanner work: it's for the crew."})
		return out
	var rj := Recovery.job_of(bike_id)
	if not rj.is_empty() and rj.get("spec") is Array and not (rj["spec"] as Array).is_empty():
		for slot in rj["spec"]:
			_add_task(out, {"t": "renew", "slot": str(slot)})
		return out
	for r in Recovery.assess(bike_id)["rows"]:
		if str(r["fix"]) == "replace":
			_add_task(out, {"t": "renew", "slot": str(r["slot"]), "part": str(r["part"])})
	for slot in Shed.missing_slots(bike_id):
		_add_task(out, {"t": "fit", "slot": str(slot)})
	return out


## Adds a task to a list once (with its text).
static func _add_task(out: Array, t: Dictionary) -> void:
	if not t.has("text"):
		t["text"] = task_text(t)
	var key := _task_key(t)
	for o in out:
		if _task_key(o) == key:
			return
	out.append(t)


static func _task_key(t: Dictionary) -> String:
	return "%s|%s|%s|%s" % [str(t.get("t", "")), str(t.get("task", "")), str(t.get("slot", "")), str(t["text"]) if str(t.get("t", "")) == "other" else ""]


## What a task says on the list.
static func task_text(t: Dictionary) -> String:
	var slot := str(t.get("slot", ""))
	match str(t.get("t", "")):
		"task":
			return str(Contracts.TASKS.get(str(t.get("task", "")), str(t.get("task", ""))))
		"part":
			return "%s: %s" % [PartsDB.slot_name(slot), PartsDB.part_name(str(t.get("part", "")))]
		"fit":
			return "%s fitted" % PartsDB.slot_name(slot)
		"renew":
			return "New %s" % PartsDB.slot_name(slot).to_lower()
		"bolt":
			return "Everything bolted up"
	return str(t.get("why", "Something else"))


## An MOT's failures as tasks, from a fresh inspection of the bike.
static func mot_tasks(bike_id: int) -> Array:
	var out := []
	for r in MotTest.fails(MotTest.inspect(bike_id)):
		var n := str(r["name"]).to_lower()
		var side := "front" if n.begins_with("front") else "rear"
		var t := {}
		if n.contains("tyre bead"):
			t = {"t": "other", "why": "Re-seating a tyre's bead is one for the crew."}
		elif n.contains("tyre"):
			t = {"t": "task", "task": side + "_tyre"}
		elif n.contains("wheel and rim"):
			t = {"t": "renew", "slot": side + "_wheel"}
		elif n.contains("disc thickness"):
			t = {"t": "renew", "slot": side + "_disc"}
		elif n.contains("brake fluid"):
			t = {"t": "task", "task": "brake_fluid"}
		elif n.contains("pads"):
			t = {"t": "renew", "slot": side + "_pads"}
		elif n.contains("caliper"):
			t = {"t": "renew", "slot": side + "_caliper"}
		elif n.contains("master cylinder"):
			t = {"t": "renew", "slot": side + "_master"}
		elif n.contains("front fork"):
			t = {"t": "renew", "slot": "fork"}
		elif n.contains("rear suspension"):
			t = {"t": "renew", "slot": "shock"}
		elif n.contains("handlebars"):
			t = {"t": "renew", "slot": "handlebars"}
		elif n.contains("sprocket"):
			t = {"t": "task", "task": "chain_kit"}
		elif n.contains("chain tension"):
			t = {"t": "task", "task": "chain"}
		elif n.contains("headlight"):
			t = {"t": "renew", "slot": "headlight"}
		elif n.contains("rear light") or n.contains("number plate"):
			t = {"t": "renew", "slot": "tail"}
		elif n.contains("horn"):
			t = {"t": "renew", "slot": "horn"}
		elif n.contains("speedometer"):
			t = {"t": "renew", "slot": "dashboard"}
		elif n.contains("mirrors"):
			t = {"t": "fit", "slot": "mirrors"}
		elif n.contains("exhaust noise"):
			t = {"t": "part", "slot": "exhaust", "part": _road_exhaust(bike_id)}
		elif n.contains("exhaust"):
			t = {"t": "renew", "slot": "exhaust"}
		elif n.contains("fuel tank"):
			t = {"t": "renew", "slot": "tank"}
		elif n.contains("seat"):
			t = {"t": "fit", "slot": "saddle"}
		elif n.contains("engine oil"):
			t = {"t": "task", "task": "oil"}
		elif n.contains("bolted up"):
			t = {"t": "bolt"}
		else:
			t = {"t": "other", "why": "%s: one for the crew." % str(r["name"])}
		t["text"] = "MOT: %s" % str(r["fix"]) if str(r.get("fix", "")) != "" else "MOT: %s" % str(r["name"])
		out.append(t)
	return out


## A road-legal exhaust for the bike: the one it came with, or the plainest there is.
static func _road_exhaust(bike_id: int) -> String:
	var orig := str(Shed.bikes.get(bike_id, {}).get("original", {}).get("exhaust", ""))
	if orig != "" and orig != "straight_pipe" and not PartsDB.get_part(orig).is_empty():
		return orig
	for p in PartsDB.by_kind.get("exhaust", []):
		if str(p) != "straight_pipe":
			return str(p)
	return "full_system"


## The part a slot gets when the list just says "fitted" or "new": what's on it now, else the
## part the bike came with, else the cheapest that goes there.
static func part_for(bike_id: int, slot: String, want := "") -> String:
	var kind := str(PartsDB.SLOT_KIND.get(slot, ""))
	if want != "" and PartsDB.kind_of(want) == kind:
		return want
	var on := Shed.item_on(bike_id, slot)
	if on != 0:
		return str(Shed.items[on]["part"])
	var orig := str(Shed.bikes.get(bike_id, {}).get("original", {}).get(slot, ""))
	if orig != "" and orig != "none" and PartsDB.kind_of(orig) == kind:
		return orig
	var best := ""
	var price := INF
	for p in PartsDB.by_kind.get(kind, []):
		var c := float(PartsDB.get_part(str(p)).get("price", 0))
		if c < price:
			price = c
			best = str(p)
	return best


## The slots a task works on.
static func task_slots(t: Dictionary) -> Array:
	match str(t.get("t", "")):
		"task":
			return Contracts.TASK_PARTS.get(str(t.get("task", "")), [])
		"part", "fit", "renew":
			return [str(t.get("slot", ""))]
	return []


## Whether a task's done on the bike now.
static func task_done(bike_id: int, t: Dictionary) -> bool:
	if not Shed.bikes.has(bike_id):
		return false
	var slot := str(t.get("slot", ""))
	var on := Shed.item_on(bike_id, slot) if slot != "" else 0
	match str(t.get("t", "")):
		"task":
			return bool(Contracts._eval_task(bike_id, str(t.get("task", "")))["done"])
		"part":
			return on != 0 and str(Shed.items[on]["part"]) == str(t.get("part", "")) and Shed.is_bolted(bike_id, slot)
		"fit":
			return on != 0 and Shed.is_bolted(bike_id, slot)
		"renew":
			return _renewed(bike_id, slot, float(t.get("health", 0.0))) and Shed.is_bolted(bike_id, slot)
		"bolt":
			return Shed.loose_slots(bike_id).is_empty()
	return false


## Why worker `w` can't do task `t` on the bike ("" if they can): it isn't spanner work, or it
## needs an expert (tyres, brake fluid, anything with other parts in the way).
static func task_why(w: Dictionary, bike_id: int, t: Dictionary) -> String:
	var expert := str(w.get("role", "")) == "expert"
	match str(t.get("t", "")):
		"other":
			return str(t.get("why", "That's not one for a mechanic."))
		"task":
			match str(t.get("task", "")):
				"wash":
					return "Washing's the detailer's job."
				"brake_fluid":
					if not expert:
						return "Bleeding the brakes is one for an expert mechanic."
	for slot in task_slots(t):
		if slot in ["frame", "engine"] or (PartsDB.is_engine_slot(slot) and not PartsDB.SERVICE_SLOTS.has(slot)):
			return "The %s is a job for the crew." % _slot(slot)
		if expert:
			continue
		if PartsDB.SLOT_KIND.get(slot, "") == "tyre":
			return "Tyres need the tyre changer: one for an expert mechanic."
		if Shed.item_on(bike_id, slot) != 0:
			var dep := _first_off(bike_id, slot)
			if dep != "":
				return "The %s has to come off first: one for an expert mechanic." % _slot(dep)
	return ""


## A project: the bike's listed work done in order, exactly that and nothing more. Each task's
## looked at in turn: done already, it's ticked; one they can't do (not spanner work, or for an
## expert) they say so and skip; otherwise they work at it until it's done.
static func _project(w: Dictionary, job: Dictionary) -> Array:
	var b := int(job["bike"])
	var tasks: Array = job["tasks"]
	var state: Array = job["state"]
	var kit := _kit(w, job, b)
	if not kit.is_empty():
		return kit
	while int(job["ti"]) < tasks.size():
		var i := int(job["ti"])
		var t: Dictionary = tasks[i]
		if str(state[i]) == "todo":
			var why := task_why(w, b, t)
			if why != "":
				return _skip_task(w, job, i, why)
			if task_done(b, t):
				_tick_task(w, job, i, "done", "")
				continue
			state[i] = "doing"
			Staff.log_line(w, "Started: %s" % str(t["text"]))
		job["looks"][i] = int(job["looks"][i]) + 1
		if int(job["looks"][i]) > MAX_TASK_LOOKS:
			job.erase("sub")
			return _skip_task(w, job, i, "I can't get \"%s\" right. I'll leave it for the crew." % str(t["text"]))
		var out := _task_steps(w, job, b, t)
		if job.has("fail"):
			# Something in the way of this one: say so and get on with the rest.
			var why := str(job["fail"])
			job.erase("fail")
			job.erase("sub")
			return _skip_task(w, job, i, why)
		if not out.is_empty():
			job["doing_task"] = i
			return out
		_tick_task(w, job, i, "done" if task_done(b, t) else "skipped", "" if task_done(b, t) else "Did what I could.")
	var tidy := _kit_tidy(w, job, b)
	if not tidy.is_empty():
		return tidy
	var held := _held(w)
	if held != 0:
		return _stow(job, held, b, false)
	var done := 0
	var skipped := []
	for i in tasks.size():
		if str(state[i]) == "done":
			done += 1
		elif str(state[i]) == "skipped":
			skipped.append(str(tasks[i]["text"]).to_lower())
	job["report"] = "The %s's list is done: %d of %d ticked off.%s" % [_bike_name(b), done, tasks.size(),
		" I left %s." % ", ".join(skipped) if not skipped.is_empty() else ""]
	return []


## Marks task `i` done or skipped and moves on to the next.
static func _tick_task(w: Dictionary, job: Dictionary, i: int, how: String, note: String) -> void:
	job["state"][i] = how
	job["notes"][i] = note
	job["ti"] = i + 1
	job.erase("doing_task")
	Staff.log_line(w, "%s: %s%s" % ["Done" if how == "done" else "Skipped", str(job["tasks"][i]["text"]), " (%s)" % note if note != "" else ""])


## Skipping task `i`, saying why.
static func _skip_task(w: Dictionary, job: Dictionary, i: int, why: String) -> Array:
	_tick_task(w, job, i, "skipped", why)
	return [{"do": "say", "text": "Skipping \"%s\": %s" % [str(job["tasks"][i]["text"]), why]}, plan_step()]


## The next steps of one task ([] when there's nothing more to do on it).
static func _task_steps(w: Dictionary, job: Dictionary, b: int, t: Dictionary) -> Array:
	var sub = job.get("sub")
	if sub is Dictionary:
		var out := _fit(w, job, b, str(sub["slot"]), str(sub["part"]), bool(sub.get("bin", true)), int(sub.get("old", 0)))
		if not out.is_empty() or job.has("fail"):
			return out
		job.erase("sub")
		(job["did"] as Array).append(_slot(str(sub["slot"])))
	match str(t.get("t", "")):
		"task":
			var k := str(t.get("task", ""))
			if SERVICE_TASKS.has(k):
				return _service_core(w, job, b, [k])
			for slot in Contracts.TASK_PARTS.get(k, []):
				var out := _renew(w, job, b, str(slot), "")
				if not out.is_empty() or job.has("fail"):
					return out
			return []
		"renew":
			return _renew(w, job, b, str(t["slot"]), str(t.get("part", "")), float(t.get("health", 0.0)))
		"part", "fit":
			var slot := str(t["slot"])
			if task_done(b, t):
				return []
			var part := str(t["part"]) if str(t["t"]) == "part" else part_for(b, slot)
			if part == "":
				job["fail"] = "There's no part that goes on the %s." % _slot(slot)
				return []
			job["sub"] = {"slot": slot, "part": part, "old": 0, "bin": false}
			return _fit(w, job, b, slot, part, false, 0)
		"bolt":
			for slot in Shed.loose_slots(b):
				return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
					work({"a": "bolt", "bike": b, "slot": str(slot), "crouched": true}, 4.0, "wrench", "bolting up the %s" % _slot(str(slot))), plan_step()]
	return []


## Renewing the part in `slot` like for like (fitting one if it's gone), unless it's as good as
## new already. The old one goes in the bin.
static func _renew(w: Dictionary, job: Dictionary, b: int, slot: String, want: String, health := 0.0) -> Array:
	var on := Shed.item_on(b, slot)
	if _renewed(b, slot, health):
		if not Shed.is_bolted(b, slot):
			return [go(StaffNav.bike(b), "going over to the %s" % _bike_name(b)),
				work({"a": "bolt", "bike": b, "slot": slot, "crouched": true}, 4.0, "wrench", "bolting up the %s" % _slot(slot)), plan_step()]
		return []
	var part := part_for(b, slot, want)
	if part == "":
		job["fail"] = "There's no part that goes on the %s." % _slot(slot)
		return []
	job["sub"] = {"slot": slot, "part": part, "old": on, "bin": true}
	return _fit(w, job, b, slot, part, true, on)


## Whether the part in `slot` is fresh: hardly worn or rusty, and at least `health` good.
static func _renewed(b: int, slot: String, health := 0.0) -> bool:
	var on := Shed.item_on(b, slot)
	if on == 0:
		return false
	var it: Dictionary = Shed.items[on]
	if float(it["wear"]) > 0.2 or float(it["rust"]) > 0.2:
		return false
	return health <= 0.0 or BikeBuild.part_health(Shed.condition_of(it)) >= health


## A project's list with how each task stands, for the TV, the panel and the bay's workflow
## screen: [{text, state ("todo", "doing", "done", "skipped"), note}].
static func project_rows(job: Dictionary) -> Array:
	var out := []
	var tasks: Array = job.get("tasks", [])
	for i in tasks.size():
		var st := str((job.get("state", []) as Array)[i]) if i < (job.get("state", []) as Array).size() else "todo"
		var note := str((job.get("notes", []) as Array)[i]) if i < (job.get("notes", []) as Array).size() else ""
		out.append({"text": str(tasks[i].get("text", "")), "state": st, "note": note})
	return out


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
