class_name Workflow
extends RefCounted
## A bike's job card: how the work on it is run, on the Workflow channel of the shed's screens
## (see WorkflowTv) instead of a menu. "Assess vehicle" looks the bike over part by part (the
## same survey a recovered bike gets, Recovery.assess) and writes the result on the card for the
## whole crew: the damage list with what each fix costs, the repair estimate and, for a recovery
## job, the three prices (buy it, break it, repair it for the insurer). The repairs become the
## card's task list, which ticks itself off as the parts come right; a task can also be ticked
## (or unticked) by hand, given to one of the staff, and its missing parts ordered from the card.
##
## The card is shed state, kept on the bike (Shed.bikes[id]["card"]) so it's saved and synced
## with it; changed through Shed.request({"a": "card_..."}) which hands to check()/apply():
##   card_assess {bike}           look it over: the damage list, prices and task list
##   card_tick {bike, task, on}   tick a task off by hand (or untick it)
##   card_order {bike}            order every part the tasks still need and the shed hasn't got
##   card_assign {bike, task}     give a task to whichever of the staff can do it
##   card_project {bike}          give the whole list still to do to a mechanic, as a project
##   card_pick {screen, step}     a screen's Workflow channel moves on to the next bike (or back)

## A part counts as put right at this health or better (where the assessment stops asking for
## a restore; the insurer takes a little less, Recovery.INSURER_HEALTH).
const GOOD_HEALTH := 0.8
const WORN := 0.6
## Game hours someone who worked on a bike still shows as on it.
const RECENT := 0.5
## Fluid this old wants changing.
const OLD_FLUID := 0.5


# ---------------------------------------------------------------------------- the card

## The card for `bike_id`, or {} when it hasn't got one.
static func card(bike_id: int) -> Dictionary:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	return b["card"] if b.get("card") is Dictionary else {}


## Whether the bike has been assessed (its card has a damage list).
static func assessed(bike_id: int) -> bool:
	return card(bike_id).has("rows")


## The card for `bike_id`, made if it hasn't got one (host).
static func _card_of(bike_id: int) -> Dictionary:
	var b: Dictionary = Shed.bikes[bike_id]
	if not (b.get("card") is Dictionary):
		b["card"] = {"started": Contracts.clock(), "ticks": {}, "who": {}, "assign": {}}
	var c: Dictionary = b["card"]
	for key in ["ticks", "who", "assign"]:
		if not (c.get(key) is Dictionary):
			c[key] = {}
	return c


## The name of whoever `peer` is: a player, or one of the staff.
static func name_of(peer: int) -> String:
	if Staff.is_staff_peer(peer):
		return Staff.first_name(Staff.worker(Staff.id_of_peer(peer)))
	return str(Shed.crew.get(peer, {}).get("name", "Someone"))


## What the bike has cost the shed so far: what it was bought for, the parts fitted to it and
## the labour on them.
static func sunk(bike_id: int) -> int:
	var b: Dictionary = Shed.bikes.get(bike_id, {})
	var total := int(b.get("bought", 0)) + int(b.get("labour", 0))
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			total += int(Shed.items[id].get("paid", 0)) + int(Shed.items[id].get("labour", 0))
	return total


## Host: looks the bike over and writes it on its card: every part's condition and what putting
## it right costs, the totals, the prices for a recovery job, and the task list made from it
## (ticks and staff already on a task are kept for the tasks that are still there).
static func assess_bike(bike_id: int, peer: int) -> Dictionary:
	var c := _card_of(bike_id)
	var job := Recovery.job_of(bike_id)
	var a := Recovery.assess(bike_id, job)
	var rows := []
	for r in a["rows"]:
		rows.append({"slot": str(r["slot"]), "part": str(r["part"]), "name": str(r["name"]), "health": snappedf(float(r["health"]), 0.01),
			"fix": str(r["fix"]), "cost": int(r["cost"])})
	c["rows"] = rows
	c["repair"] = int(a["repair"])
	c["fixed"] = int(a["fixed"])
	c["now"] = int(a["now"])
	if not job.is_empty():
		c["prices"] = {"buy": int(a["buy"]), "salvage": int(a["salvage"]), "insurer": int(a["insurer"])}
	c["assessed"] = Contracts.clock()
	c["by"] = name_of(peer)
	c["sunk0"] = sunk(bike_id)
	c["tasks"] = _tasks_from(bike_id, rows)
	var keep := {}
	for t in c["tasks"]:
		keep[str(t["id"])] = true
	for key in ["ticks", "assign"]:
		for id in (c[key] as Dictionary).keys():
			if not keep.has(str(id)):
				c[key].erase(id)
	return c


## The task list for a damage list: each part to restore or replace, old fuel and oil changed,
## and last every part on and bolted up.
static func _tasks_from(bike_id: int, rows: Array) -> Array:
	var out := []
	for r in rows:
		if str(r["fix"]) == "ok":
			continue
		var verb := "Replace" if str(r["fix"]) == "replace" else "Restore"
		out.append({"id": str(r["slot"]), "text": "%s the %s" % [verb, PartsDB.slot_name(str(r["slot"])).to_lower()],
			"slot": str(r["slot"]), "part": str(r["part"]), "fix": str(r["fix"])})
	if _old_fluids(bike_id):
		out.append({"id": "fluids", "text": "Fresh petrol and oil", "fix": "fluids"})
	out.append({"id": "bolted", "text": "Every part on and bolted up", "fix": "bolted"})
	return out


## Whether the engine oil or the petrol in the tank is old.
static func _old_fluids(bike_id: int) -> bool:
	for slot in ["engine", "tank"]:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items[id].get("fluid") is Dictionary and float(Shed.items[id]["fluid"].get("age", 0.0)) > OLD_FLUID:
			return true
	return false


## Whether a task is done by the state of the bike (a ticked-off-by-hand task aside).
static func auto_done(bike_id: int, task: Dictionary) -> bool:
	match str(task.get("fix", "")):
		"bolted":
			return Shed.is_complete(bike_id)
		"fluids":
			return not _old_fluids(bike_id)
	var id := Shed.item_on(bike_id, str(task.get("slot", "")))
	if id == 0 or not Shed.is_bolted(bike_id, str(task["slot"])):
		return false
	var it: Dictionary = Shed.items[id]
	return BikeBuild.part_health(Shed.condition_of(it)) >= GOOD_HEALTH and float(it.get("wear", 0.0)) <= WORN


## Whether a task is done: by the state of the bike, or ticked off by hand.
static func is_done(bike_id: int, task: Dictionary) -> bool:
	return bool(card(bike_id).get("ticks", {}).get(str(task["id"]), false)) or auto_done(bike_id, task)


static func task_of(bike_id: int, task_id: String) -> Dictionary:
	for t in card(bike_id).get("tasks", []):
		if str(t["id"]) == task_id:
			return t
	return {}


## The shed's spare parts by part id: {part: {"stock": loose and good, "boxed": still in its box}}.
static func stock() -> Dictionary:
	var out := {}
	for id in Shed.items:
		var it: Dictionary = Shed.items[id]
		var at := str(it["at"])
		if at in ["bike", "engine", "held"]:
			continue
		var part := str(it["part"])
		if not out.has(part):
			out[part] = {"stock": 0, "boxed": 0}
		if it.get("boxed", false):
			out[part]["boxed"] += 1
		elif BikeBuild.part_health(Shed.condition_of(it)) >= 0.8:
			out[part]["stock"] += 1
	return out


## Where a replace task's part stands: "fitted" (the task's done), "stock" (a good one in the
## shed), "ordered" (boxed up from the delivery), "missing" (none: order one), or "" for a task
## that needs no new part.
static func part_state(bike_id: int, task: Dictionary, have: Dictionary) -> String:
	if str(task.get("fix", "")) != "replace":
		return ""
	if auto_done(bike_id, task):
		return "fitted"
	var s: Dictionary = have.get(str(task["part"]), {})
	if int(s.get("stock", 0)) > 0:
		return "stock"
	if int(s.get("boxed", 0)) > 0:
		return "ordered"
	return "missing"


## The parts the tasks still need that the shed hasn't got, by part id.
static func missing_parts(bike_id: int) -> Array:
	var have := stock()
	var out := []
	for t in card(bike_id).get("tasks", []):
		if not is_done(bike_id, t) and part_state(bike_id, t, have) == "missing":
			out.append(str(t["part"]))
	return out


## The staff job that does a task: fitting the part (a new one for a replace, like for like),
## a service for the fluids; {} for one only the crew can do.
static func staff_job(bike_id: int, task: Dictionary) -> Dictionary:
	match str(task.get("fix", "")):
		"replace", "restore":
			var slot := str(task.get("slot", ""))
			if Staff.JOBS.has("fit") and not slot in ["frame", "engine"]:
				return {"kind": "fit", "bike": bike_id, "slot": slot, "part": str(task["part"])}
		"fluids":
			if Staff.JOBS.has("service"):
				return {"kind": "service", "bike": bike_id}
	return {}


## The staff "project" job for the card: every task still to do, in the card's order, as the
## project's list (see StaffJobs.project_tasks). Replacing or restoring a part is renewing it
## until it comes up to GOOD_HEALTH, old fluids are an oil change and the last task's bolting it
## all up; pumping up tyres stays on the list for the crew (the mechanic says so and goes on).
## {} when there's nothing left to do.
static func project_job(bike_id: int) -> Dictionary:
	var tasks := []
	# A customer's own list comes first (as the card shows it).
	if not Contracts.job_for_bike(bike_id).is_empty():
		for t in StaffJobs.project_tasks(bike_id):
			if not StaffJobs.task_done(bike_id, t):
				tasks.append(t)
	for t in card(bike_id).get("tasks", []):
		if is_done(bike_id, t):
			continue
		var text := str(t["text"])
		match str(t.get("fix", "")):
			"replace", "restore":
				tasks.append({"t": "renew", "slot": str(t["slot"]), "part": str(t.get("part", "")), "health": GOOD_HEALTH, "text": text})
			"fluids":
				tasks.append({"t": "task", "task": "oil", "text": text})
			"bolted":
				tasks.append({"t": "bolt", "text": text})
			_:
				tasks.append({"t": "other", "text": text, "why": "That's one for the crew."})
	if tasks.is_empty():
		return {}
	return {"kind": "project", "bike": bike_id, "tasks": tasks}


## Whether a task on the card can go to one of the staff now (someone can do it).
static func can_assign(bike_id: int, task: Dictionary) -> bool:
	var job := staff_job(bike_id, task)
	return not job.is_empty() and not pick_worker(job).is_empty()


## The worker who'd take a task on: an idle one who can do it first, else anyone who can. {} for none.
static func pick_worker(job: Dictionary) -> Dictionary:
	var best := {}
	var ids: Array = Staff.workers().keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = Staff.workers()[id]
		if Staff.job_check(w, job) != "" or w.get("sick", false):
			continue
		if (w["job"] as Dictionary).is_empty():
			return w
		if best.is_empty():
			best = w
	return best


## Who's on the bike now: staff with a job on it, players doing something to it, and anyone who
## worked on it in the last RECENT hours. ["Name: what", ...]
static func on_it(bike_id: int) -> Array:
	var out := []
	var named := {}
	for id in Staff.workers():
		var w: Dictionary = Staff.workers()[id]
		if int(w["job"].get("bike", 0)) == bike_id:
			out.append("%s (%s): %s" % [Staff.first_name(w), Staff.role_name(str(w["role"])).to_lower(), str(w["job"].get("doing", "on it"))])
			named[Staff.first_name(w)] = true
	var bike_name := str(Shed.bikes.get(bike_id, {}).get("name", ""))
	for peer in Shed.crew:
		var act := str(Shed.crew[peer].get("activity", ""))
		if bike_name != "" and act.contains(bike_name):
			var who := str(Shed.crew[peer]["name"])
			out.append("%s: %s" % [who, act.left(1).to_lower() + act.substr(1)])
			named[who] = true
	var who_all: Dictionary = card(bike_id).get("who", {})
	for n in who_all:
		if not named.has(n) and Contracts.clock() - float(who_all[n]) < RECENT:
			out.append("%s, a little while ago" % n)
	return out


## Host: notes who did something to a bike, for its card's "on it" list.
static func note_action(peer: int, action: Dictionary) -> void:
	var a := str(action.get("a", ""))
	if a.begins_with("card_") or a in Contracts.NOT_WORK or a in ["status", "release_bike", "grab_bike"]:
		return
	var bike_id := int(action.get("bike", 0))
	if bike_id == 0 and int(action.get("engine", 0)) != 0:
		bike_id = Shed._bike_of(int(action["engine"]))
	if bike_id == 0 and int(action.get("item", 0)) != 0:
		bike_id = Shed._bike_of(int(action["item"]))
	if bike_id == 0 or not Shed.bikes.has(bike_id):
		return
	var who: Dictionary = _card_of(bike_id)["who"]
	who[name_of(peer)] = Contracts.clock()
	if who.size() > 6:
		var oldest := ""
		for n in who:
			if oldest == "" or float(who[n]) < float(who[oldest]):
				oldest = n
		who.erase(oldest)


## What to do next on the bike, in a line.
static func next_step(bike_id: int) -> String:
	var job := Recovery.job_of(bike_id)
	var state := str(job.get("state", ""))
	if state == "collect":
		return "Bring it back to the yard on the trailer first."
	if not assessed(bike_id):
		return "Assess it: touch Assess vehicle and the damage list and its jobs go up here for the whole crew."
	if state == "delivered":
		return "Decide: buy it, break it for parts, or put it right for %s." % job.get("insurer", "the insurer")
	var contract := Contracts.job_for_bike(bike_id)
	for t in card(bike_id).get("tasks", []):
		if not is_done(bike_id, t):
			var why := str(t["text"])
			var have := part_state(bike_id, t, stock())
			if have == "missing":
				why += ": no %s in the shed, order one" % PartsDB.part_name(str(t["part"])).to_lower()
			elif have == "ordered":
				why += ": the new one's boxed in the delivery area"
			return "Next: %s." % why
	if state == "insurer":
		return "Up to spec. Park it in the yard and touch Insurer collects."
	if not contract.is_empty():
		return "The card's done: finish the customer's list and hand it back."
	return "All done. Ride it, or put it up for sale in the showroom."


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a "card_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if a == "card_pick":
		if not TvChannels.screen_exists(str(action.get("screen", ""))):
			return "That screen has gone."
		return "" if int(action.get("step", 0)) in [-1, 1] else "Next or previous?"
	var bike_id := int(action.get("bike", 0))
	if not Shed.bikes.has(bike_id):
		return "That bike has gone."
	match a:
		"card_assess":
			if int(Shed.bikes[bike_id].get("rider", 0)) != 0:
				return "Someone's out riding it."
			if Recovery.is_loaded(bike_id):
				return "Get it off the trailer first."
			if str(Recovery.job_of(bike_id).get("state", "")) == "collect":
				return "Bring it back to the yard first."
		"card_tick":
			var t := task_of(bike_id, str(action.get("task", "")))
			if t.is_empty():
				return "That job's not on the card."
			if not bool(action.get("on", true)) and auto_done(bike_id, t):
				return "It's done: the bike says so."
		"card_order":
			var need := missing_parts(bike_id)
			if need.is_empty():
				return "Nothing to order: the shed has every part the card needs."
			var cost := 0
			for p in need:
				cost += Money.buy_price(str(p), peer)
			if cost > Shed.garage_money:
				return "The business can't afford them: %s." % TvChannels.money_text(cost)
		"card_assign":
			var t2 := task_of(bike_id, str(action.get("task", "")))
			if t2.is_empty():
				return "That job's not on the card."
			if is_done(bike_id, t2):
				return "That's done already."
			var job := staff_job(bike_id, t2)
			if job.is_empty():
				return "That's one for the crew."
			if Staff.workers().is_empty():
				return "No staff yet: hire them on the Staff tab ({menu})."
			if pick_worker(job).is_empty():
				for id in Staff.workers():
					var why := Staff.job_check(Staff.workers()[id], job)
					if why != "":
						return why
				return "Nobody free who can do it."
		"card_project":
			var pj := project_job(bike_id)
			if pj.is_empty():
				return "Nothing left on the card to do."
			if Staff.workers().is_empty():
				return "No staff yet: hire them on the Staff tab ({menu})."
			if pick_worker(pj).is_empty():
				for id in Staff.workers():
					var why2 := Staff.job_check(Staff.workers()[id], pj)
					if why2 != "":
						return why2
				return "Nobody free who can do it."
		_:
			return "There's nothing like that to do."
	return ""


## Host: does a checked "card_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	if a == "card_pick":
		var key := str(action["screen"])
		var list := subjects()
		var st: Dictionary = Shed.screens.get(key, {}).duplicate() if Shed.screens.get(key) is Dictionary else {}
		st["ch"] = "workflow"
		if list.is_empty():
			st["bike"] = 0
		else:
			var at := list.find(subject(key))
			st["bike"] = int(list[posmod(at + int(action["step"]), list.size())])
		Shed.screens[key] = st
		return ""
	var bike_id := int(action["bike"])
	var name := str(Shed.bikes[bike_id]["name"])
	match a:
		"card_assess":
			var c := assess_bike(bike_id, peer)
			var jobs := (c["tasks"] as Array).size() - 1
			var line := "%s assessed %s: %d job%s, about %s to put right. It's on the Workflow channel of the bay screens." % [
				name_of(peer), name, jobs, "" if jobs == 1 else "s", TvChannels.money_text(int(c["repair"]))]
			for p in Shed.crew:
				if int(p) != peer:
					Shed._tell(int(p), line, true)
			return line
		"card_tick":
			var c2 := _card_of(bike_id)
			var on := bool(action.get("on", true))
			var tid := str(action["task"])
			if on:
				c2["ticks"][tid] = true
			else:
				c2["ticks"].erase(tid)
			return "%s: %s %s." % [name, str(task_of(bike_id, tid)["text"]), "ticked off" if on else "back on the list"]
		"card_order":
			var n := 0
			for p in missing_parts(bike_id):
				var order := {"a": "order_part", "part": str(p)}
				if Shed.check(peer, order) == "":
					Shed._apply(peer, order)
					n += 1
			return "Ordered %d part%s for %s: boxed in the delivery area outside." % [n, "" if n == 1 else "s", name]
		"card_assign":
			var t := task_of(bike_id, str(action["task"]))
			var job := staff_job(bike_id, t)
			var w := pick_worker(job)
			_card_of(bike_id)["assign"][str(t["id"])] = int(w["id"])
			return Staff.assign(w, job)
		"card_project":
			var pj := project_job(bike_id)
			var pw := pick_worker(pj)
			for ct in card(bike_id).get("tasks", []):
				if not is_done(bike_id, ct):
					_card_of(bike_id)["assign"][str(ct["id"])] = int(pw["id"])
			return Staff.assign(pw, pj)
	return ""


# ---------------------------------------------------------------------------- which bike a screen shows

## The bikes the Workflow channel goes through: those in the bays, in bay order, then recovered
## bikes out in the yard waiting on a decision or the insurer.
static func subjects() -> Array:
	var out := []
	for bay in Workshop.bay_count():
		var b := Shed.bike_in_bay(bay)
		if b != 0:
			out.append(b)
	for jid in Recovery.jobs():
		var j: Dictionary = Recovery.jobs()[jid]
		var b2 := int(j["bike"])
		if str(j["state"]) in ["delivered", "insurer"] and Shed.bikes.has(b2) and not out.has(b2):
			out.append(b2)
	return out


## The bike a screen's Workflow channel shows: the one picked on it, else a bay screen's own
## bay's bike, else the first waiting. 0 for none.
static func subject(key: String) -> int:
	var st = Shed.screens.get(key, null)
	var picked := int(st.get("bike", 0)) if st is Dictionary and str(st.get("ch", "")) == "workflow" else 0
	if picked != 0 and Shed.bikes.has(picked):
		return picked
	if key.begins_with("bay") and key.substr(3).is_valid_int():
		var b := Shed.bike_in_bay(int(key.substr(3)))
		if b != 0:
			return b
	var list := subjects()
	if key.begins_with("bay"):
		# An empty bay's screen shows a recovered bike waiting in the yard, not another bay's.
		for b2 in list:
			if int(Shed.bikes[int(b2)].get("bay", -1)) < 0:
				return int(b2)
		return 0
	return int(list[0]) if not list.is_empty() else 0
