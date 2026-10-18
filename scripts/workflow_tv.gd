class_name WorkflowTv
extends RefCounted
## The Workflow channel: a bike's job card on a shed screen (see Workflow). A bay screen shows
## the bike in its bay (an empty bay's, a recovered bike waiting in the yard); a wall TV the
## first bike there is, and < > go through the rest. On it: what the job is, the assessed
## task list ticking itself off as the work's done, where each part stands (in stock, ordered,
## missing), who's on it, the time and money so far, what to do next, and the buttons that run
## it: assess the vehicle, buy / break / repair it for the insurer, order the missing parts,
## give a task to the staff, hand it back. The screens are touch screens (see ScreenTouch):
## every button is a Shed request, so the whole crew sees what's done.
##
## data() lays the page out, buttons and all ({r: Rect2, t, act, off, tone}: `off` is why it
## can't be pressed now), so the page is drawn and touched from the same rects; it's only
## redrawn when something on it changes.

const INK := Color(0.02, 0.07, 0.1)
const HEAD := Color(0.3, 0.75, 0.95, 0.95)
const ROWS := 9
const ROW_H := 36.0
const ROW_Y := 160.0
const RIGHT := 636.0
const PART_WORDS := {"fitted": "FITTED", "stock": "IN STOCK", "ordered": "ORDERED", "missing": "MISSING"}


static func _button(text: String, r: Rect2, act: Dictionary, tone := "") -> Dictionary:
	return {"r": r, "t": text, "act": act, "off": Shed.check(Shed.me(), act), "tone": tone}


## The page for screen `key`.
static func data(key: String) -> Dictionary:
	var bike_id := Workflow.subject(key)
	var out := {"bike": bike_id, "screen": key, "buttons": []}
	var nav_y := Dashboard.PX.y - 52.0
	var count := Workflow.subjects().size()
	if count > (1 if bike_id != 0 else 0):
		out["buttons"].append(_button("< Bike", Rect2(24, nav_y, 110, 40), {"a": "card_pick", "screen": key, "step": -1}))
		out["buttons"].append(_button("Bike >", Rect2(144, nav_y, 110, 40), {"a": "card_pick", "screen": key, "step": 1}))
	if bike_id == 0:
		out["empty"] = "Bay %d" % (int(key.substr(3)) + 1) if key.begins_with("bay") else "the shed"
		return out
	var bike: Dictionary = Shed.bikes[bike_id]
	var c := Workflow.card(bike_id)
	var job := Recovery.job_of(bike_id)
	var contract := Contracts.job_for_bike(bike_id)
	var state := str(job.get("state", ""))
	out["name"] = str(bike["name"])
	var bay := int(bike.get("bay", -1))
	out["where"] = "BAY %d" % (bay + 1) if bay >= 0 and Shed.bike_in_bay(bay) == bike_id else "IN THE YARD"
	if not job.is_empty():
		out["kind"] = "%s for %s" % [Recovery.KIND_NAMES.get(str(job["kind"]), "Recovery"),
			job["contact"] if str(job["kind"]) == "barn" else job["insurer"]]
		if state == "insurer":
			out["kind"] += ": the insurer pays %s" % TvChannels.money_text(int(job.get("pay", 0)))
	elif not contract.is_empty():
		out["kind"] = "%s for %s" % [str(Contracts.KIND_NAMES.get(str(contract.get("kind", "")), "Job")), str(contract.get("customer", ""))]
	else:
		out["kind"] = "The shed's own project bike"
	# The tasks: a customer's list first, then the assessed repairs.
	var have := Workflow.stock()
	var tasks := []
	if not contract.is_empty():
		for r in Contracts.evaluate(contract):
			tasks.append({"text": str(r.get("text", "")), "done": bool(r.get("done", false)), "have": str(r.get("have", "")), "auto": true})
	var assign: Dictionary = c.get("assign", {})
	for t in c.get("tasks", []):
		var done := Workflow.is_done(bike_id, t)
		var row := {"text": str(t["text"]), "done": done, "auto": Workflow.auto_done(bike_id, t), "id": str(t["id"]),
			"part": Workflow.part_state(bike_id, t, have)}
		var wid := int(assign.get(str(t["id"]), 0))
		var w := Staff.worker(wid)
		if not w.is_empty() and int(w["job"].get("bike", 0)) == bike_id:
			row["who"] = Staff.first_name(w)
		tasks.append(row)
	var met := tasks.filter(func(r): return r["done"]).size()
	out["met"] = met
	out["total"] = tasks.size()
	# Show from just before the first one still to do, so the list scrolls on as it's done.
	var first := 0
	for i in tasks.size():
		if not tasks[i]["done"]:
			first = maxi(0, i - 1)
			break
	if tasks.size() - first < ROWS:
		first = maxi(0, tasks.size() - ROWS)
	out["first"] = first
	var shown := []
	for i in range(first, mini(tasks.size(), first + ROWS)):
		var r: Dictionary = tasks[i]
		var y := ROW_Y + shown.size() * ROW_H
		if r.has("id"):
			out["buttons"].append(_button("", Rect2(20, y - 26, 34, 34), {"a": "card_tick", "bike": bike_id, "task": r["id"], "on": not r["done"]}, "box"))
			if not r["done"] and not r.has("who"):
				var act := {"a": "card_assign", "bike": bike_id, "task": r["id"]}
				var b := _button("Assign", Rect2(520, y - 25, 96, 32), act, "small")
				if not Staff.workers().is_empty():
					out["buttons"].append(b)
		shown.append(r)
	out["rows"] = shown
	out["next"] = Workflow.next_step(bike_id)
	out["on"] = Workflow.on_it(bike_id).slice(0, 3)
	# Time and money.
	var started := float(c.get("assessed", c.get("started", Contracts.clock())))
	out["hours"] = maxf(0.0, Contracts.clock() - started) if not c.is_empty() else -1.0
	out["sunk"] = Workflow.sunk(bike_id)
	out["since"] = Workflow.sunk(bike_id) - int(c.get("sunk0", Workflow.sunk(bike_id)))
	out["repair"] = int(c.get("repair", -1))
	if state == "insurer":
		out["pays"] = int(job.get("pay", 0))
	elif not contract.is_empty():
		out["pays"] = int(Contracts.payout(contract)["total"])
	elif c.has("fixed"):
		out["worth"] = int(c["fixed"])
	out["by"] = "Assessed by %s, day %d" % [c["by"], Contracts.day_number(float(c["assessed"]))] if c.has("assessed") else ""
	# The buttons that run it, down the right.
	var bx := RIGHT + 8.0
	var by := 384.0
	var acts := []
	if state == "delivered" and c.get("prices") is Dictionary:
		var p: Dictionary = c["prices"]
		acts.append(["Buy it: %s" % TvChannels.money_text(int(p["buy"])), {"a": "recovery_buy", "job": int(job["id"])}, "go"])
		acts.append(["Break for parts: %s" % TvChannels.money_text(int(p["salvage"])), {"a": "recovery_salvage", "job": int(job["id"])}, ""])
		acts.append(["Insurer job: pays %s" % TvChannels.money_text(int(p["insurer"])), {"a": "recovery_insurer", "job": int(job["id"])}, "go"])
	else:
		if not Workflow.assessed(bike_id):
			acts.append(["Assess vehicle", {"a": "card_assess", "bike": bike_id}, "go"])
		var need := Workflow.missing_parts(bike_id)
		if not need.is_empty():
			var cost := 0
			for part in need:
				cost += Money.buy_price(str(part), Shed.me())
			acts.append(["Order %d missing: %s" % [need.size(), TvChannels.money_text(cost)], {"a": "card_order", "bike": bike_id}, "warn"])
		if state == "insurer":
			acts.append(["Insurer collects", {"a": "recovery_collect", "job": int(job["id"])}, "go"])
		elif not contract.is_empty():
			if str(contract.get("kind", "")) == "mot":
				acts.append(["Run the MOT test", {"a": "contract_mot_test", "job": int(contract["id"])}, ""])
			acts.append(["Hand it back", {"a": "contract_hand_in", "job": int(contract["id"])}, "go"])
		if Workflow.assessed(bike_id) and acts.size() < 3:
			acts.append(["Assess again", {"a": "card_assess", "bike": bike_id}, ""])
	for i in mini(acts.size(), 3):
		out["buttons"].append(_button(str(acts[i][0]), Rect2(bx, by + i * 46.0, 364, 40), acts[i][1], str(acts[i][2])))
	return out


# ---------------------------------------------------------------------------- drawing

static func _text(c: Control, font: Font, pos: Vector2, text: String, size: int, color := Color.WHITE, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	c.draw_string(font, pos, Controls.hint(text), align, width, size, color)


static func draw(c: Control, font: Font, d: Dictionary) -> void:
	var px := Vector2(Dashboard.PX)
	c.draw_rect(Rect2(0, 0, px.x, 70), HEAD)
	if int(d.get("bike", 0)) == 0:
		_text(c, font, Vector2(24, 50), "WORKFLOW", 40, INK)
		_text(c, font, Vector2(24, 150), "Nothing to work on in %s" % d.get("empty", "the bay"), 40)
		_text(c, font, Vector2(24, 200), "Wheel a bike in, or bring a recovery job back to the yard.", 22, Dashboard.DIM)
		_text(c, font, Vector2(24, 232), "Touch the screen ({act}) to use it: its buttons work for the whole crew.", 20, Dashboard.DIM)
		draw_buttons(c, font, d.get("buttons", []))
		return
	_text(c, font, Vector2(24, 50), ("WORKFLOW: " + str(d["name"])).to_upper().left(30), 36, INK)
	# Clear of the channel buttons that show in the corner while someone's touching the screen.
	_text(c, font, Vector2(600, 48), str(d.get("where", "")), 22, INK, 260, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, font, Vector2(24, 100), str(d.get("kind", "")), 20, Color(0.6, 0.9, 1.0), 600)
	var total := int(d.get("total", 0))
	var met := int(d.get("met", 0))
	if total > 0:
		TvChannels._bar(c, Rect2(24, 112, 480, 12), float(met) / float(total), Dashboard.GOOD if met == total else TvChannels.AMBER)
		_text(c, font, Vector2(516, 125), "%d of %d done" % [met, total], 15, Dashboard.DIM)
	else:
		_text(c, font, Vector2(24, 140), "No task list yet: assess it to get one.", 22, Dashboard.DIM)
	var rows: Array = d.get("rows", [])
	if int(d.get("first", 0)) > 0:
		_text(c, font, Vector2(470, 142), "%d done above" % int(d["first"]), 13, Dashboard.DIM, 140, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := ROW_Y + i * ROW_H
		var done := bool(r["done"])
		var box := Rect2(24, y - 22, 26, 26)
		c.draw_rect(box, Dashboard.GOOD if done else Color(1, 1, 1, 0.08))
		c.draw_rect(box, Dashboard.GOOD if done else Color(1, 1, 1, 0.5), false, 2.0)
		if done:
			c.draw_polyline(PackedVector2Array([Vector2(29, y - 10), Vector2(35, y - 3), Vector2(45, y - 18)]), Dashboard.BG, 3.5)
		_text(c, font, Vector2(62, y), str(r["text"]).left(34), 19, Color(0.75, 0.95, 0.8) if done else Color.WHITE, 330)
		var part := str(r.get("part", ""))
		if part != "":
			var pc := Dashboard.GOOD if part in ["fitted", "stock"] else (TvChannels.AMBER if part == "ordered" else Dashboard.BAD)
			_text(c, font, Vector2(398, y), str(PART_WORDS.get(part, "")), 13, pc, 112, HORIZONTAL_ALIGNMENT_RIGHT)
		elif str(r.get("have", "")) != "":
			_text(c, font, Vector2(398, y), str(r["have"]).left(18), 13, Dashboard.GOOD if done else Dashboard.DIM, 112, HORIZONTAL_ALIGNMENT_RIGHT)
		if r.has("who"):
			_text(c, font, Vector2(520, y), str(r["who"]).left(10), 16, TvChannels.ORANGE, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	# The right-hand panel: next step, who's on it, time and money.
	c.draw_rect(Rect2(RIGHT, 84, px.x - RIGHT - 12, 290), TvChannels.PANEL)
	_text(c, font, Vector2(RIGHT + 14, 108), "NEXT STEP", 15, TvChannels.ORANGE)
	c.draw_multiline_string(font, Vector2(RIGHT + 14, 132), Controls.hint(str(d.get("next", ""))), HORIZONTAL_ALIGNMENT_LEFT,
		px.x - RIGHT - 40, 18, 3, Color.WHITE)
	_text(c, font, Vector2(RIGHT + 14, 210), "ON IT", 15, TvChannels.ORANGE)
	var on: Array = d.get("on", [])
	if on.is_empty():
		_text(c, font, Vector2(RIGHT + 14, 234), "Nobody right now", 16, Dashboard.DIM)
	var oy := 230.0
	for line in on:
		if oy > 290.0:
			break
		c.draw_multiline_string(font, Vector2(RIGHT + 14, oy), str(line), HORIZONTAL_ALIGNMENT_LEFT, px.x - RIGHT - 40, 15, 2, Color.WHITE)
		oy += 18.0 * mini(2, ceili(font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x / (px.x - RIGHT - 40))) + 4.0
	var hours := float(d.get("hours", -1.0))
	var money_y := 318.0
	_text(c, font, Vector2(RIGHT + 14, money_y), "TIME", 13, Dashboard.DIM)
	_text(c, font, Vector2(RIGHT + 14, money_y + 26), _hours_text(hours) if hours >= 0.0 else "-", 20)
	_text(c, font, Vector2(RIGHT + 110, money_y), "SPENT", 13, Dashboard.DIM)
	_text(c, font, Vector2(RIGHT + 110, money_y + 26), TvChannels.money_text(int(d.get("sunk", 0))), 20)
	if int(d.get("since", 0)) > 0:
		_text(c, font, Vector2(RIGHT + 110, money_y + 44), "+%s on the card" % TvChannels.money_text(int(d["since"])), 12, Dashboard.DIM)
	var third := ["", 0]
	if d.has("pays"):
		third = ["PAYS", int(d["pays"])]
	elif int(d.get("repair", -1)) >= 0:
		third = ["REPAIR EST.", int(d["repair"])]
	if str(third[0]) != "":
		_text(c, font, Vector2(RIGHT + 236, money_y), str(third[0]), 13, Dashboard.DIM)
		_text(c, font, Vector2(RIGHT + 236, money_y + 26), TvChannels.money_text(int(third[1])), 20, Color(0.6, 1.0, 0.8))
	if str(d.get("by", "")) != "":
		_text(c, font, Vector2(270, Dashboard.PX.y - 26), str(d["by"]), 14, Dashboard.DIM, 360)
	draw_buttons(c, font, d.get("buttons", []))


static func _hours_text(h: float) -> String:
	if h < 1.0:
		return "%d min" % roundi(h * 60.0)
	if h < 24.0:
		return "%.1f h" % h
	return "%d d %d h" % [int(h / 24.0), int(fmod(h, 24.0))]


## Draws the touch buttons (a tick box is drawn by its row, so only its outline shows here).
static func draw_buttons(c: Control, font: Font, buttons: Array) -> void:
	for b in buttons:
		var r: Rect2 = b["r"]
		var tone := str(b.get("tone", ""))
		if tone == "box":
			continue
		var off := str(b.get("off", "")) != ""
		var fill := Color(1, 1, 1, 0.1)
		if tone == "go":
			fill = Color(Dashboard.GOOD, 0.25)
		elif tone == "warn":
			fill = Color(TvChannels.AMBER, 0.22)
		if off:
			fill = Color(1, 1, 1, 0.05)
		c.draw_rect(r, fill)
		c.draw_rect(r, Color(1, 1, 1, 0.25 if off else 0.6), false, 2.0)
		var size := 15 if tone == "small" else 19
		_text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.36), str(b["t"]), size,
			Color(1, 1, 1, 0.35) if off else Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
