class_name ContractPanel
extends Control
## The contract card: what a customer at reception wants (their bike, the goals or checks, the
## budget, the pay and the deadline) with Accept and Decline, and the shed's jobs under way:
## each goal ticked off as it's met, the MOT sheet with Run MOT test, and Hand back. The Esc
## menu's Contracts tab shows the same jobs list (see fill_jobs).

signal closed

var customer_id := 0
var _box: VBoxContainer
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("contract_panel")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	Shed.changed.connect(func(): if visible: _refresh())


## Talks to a customer at reception: their offer.
func open_offer(id: int) -> void:
	customer_id = id
	_sig = ""
	visible = true
	_refresh()


## The jobs under way.
func open_jobs() -> void:
	customer_id = 0
	_sig = ""
	visible = true
	_refresh()


## Presses the button labelled `text` (for tests).
func press(text: String) -> void:
	for b in _box.find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not b.is_queued_for_deletion():
			(b as Button).pressed.emit()
			return


func close_dialog() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	if customer_id != 0 and not Contracts.customers().has(customer_id):
		# They've gone (or the job was taken on): show the jobs instead.
		customer_id = 0
	var sig := str(customer_id) + ContractPanel.jobs_signature()
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	if customer_id != 0:
		_fill_offer(Contracts.customers()[customer_id])
	else:
		_box.add_child(UITheme.title("CONTRACTS", 24))
		ContractPanel.fill_jobs(_box)
		_box.add_child(ContractPanel.button("Close (Esc)", close_dialog))


func _fill_offer(c: Dictionary) -> void:
	var o: Dictionary = c["offer"]
	var kind := str(o["kind"])
	_box.add_child(UITheme.title(str(c["name"]).to_upper(), 26))
	_box.add_child(UITheme.label("%s job  ·  Reputation %d" % [Contracts.KIND_NAMES[kind], Contracts.reputation()], 16, UITheme.ACCENT))
	_box.add_child(UITheme.label("\"%s\"" % o.get("blurb", ""), 16, Color(1, 1, 1, 0.75)))
	_box.add_child(UITheme.label(ContractPanel.bike_text(o), 16))
	_box.add_child(UITheme.label("WHAT THEY WANT", 15, UITheme.ACCENT))
	for g in o.get("goals", []):
		_box.add_child(UITheme.label("•  " + Contracts.goal_text(g), 16))
	if kind == "mot":
		_box.add_child(UITheme.label("Run the test from the job list (Esc > Contracts, or here once taken on): it checks tyre tread "
			+ "(legal minimum %.0f mm) and condition, wheels, discs, pads, calipers, master cylinders and fluid, fork and shock leaks, "
			% MotTest.TREAD_LEGAL + "steering, chain and sprockets, tension, lights, horn, dash, mirrors, exhaust, frame rust, oil "
			+ "and the number plate. Fix every fail and test it again for the certificate.", 14, Color(1, 1, 1, 0.6)))
	var money := "Pays %s" % Contracts.money(int(o["pay"]))
	if int(o.get("budget", 0)) > 0:
		money += "  +  parts up to a %s budget (spending more comes off the pay)" % Contracts.money(int(o["budget"]))
	_box.add_child(UITheme.label(money, 18, Color(0.5, 0.95, 0.55)))
	_box.add_child(UITheme.label("Deadline: %d days (day %d). Late jobs pay less and cost reputation." % [int(o["days"]),
		Contracts.day_number(Contracts.clock() + float(o["days"]) * Contracts.DAY)], 16))
	var why := Shed.check(Shed.me(), {"a": "contract_accept", "customer": customer_id})
	if why != "":
		_box.add_child(UITheme.label(why, 15, Color(1, 0.5, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var accept := ContractPanel.button("Accept", func():
		Shed.request({"a": "contract_accept", "customer": customer_id})
		close_dialog())
	accept.disabled = why != ""
	row.add_child(accept)
	row.add_child(ContractPanel.button("Decline", func():
		Shed.request({"a": "contract_decline", "customer": customer_id})
		close_dialog()))
	row.add_child(ContractPanel.button("Jobs list", open_jobs))
	row.add_child(ContractPanel.button("Later (Esc)", close_dialog))
	_box.add_child(row)


# ---------------------------------------------------------------------------- shared with the Esc tab

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


## The customer's bike in a line.
static func bike_text(o: Dictionary) -> String:
	var parts: Dictionary = o.get("parts", {})
	if str(o.get("kind", "")) == "bespoke":
		return "Starts as a bare %s on a bay, built up from nothing." % PartsDB.part_name(str(parts.get("frame", ""))).to_lower()
	var text := "Their bike: %s, a %s with a %s." % [o.get("bike_name", ""), PartsDB.part_name(str(parts.get("engine", ""))),
		PartsDB.part_name(str(parts.get("frame", ""))).to_lower()]
	if o.has("paint"):
		text += " It's parked in the car park: take the job on and they leave you the keys to bring it in."
	return text


## Where a job's bike is: in a bay, in the car park (where the customer left it, and where it
## goes back to be handed back), or out.
static func where_text(bike: Dictionary) -> String:
	if not (bike.get("xf") is Transform3D):
		return "gone"
	var at: Vector3 = (bike["xf"] as Transform3D).origin
	var bay := Shed.bay_at(at)
	if bay >= 0:
		return "bay %d" % (bay + 1)
	if Contracts.in_car_park(at):
		return "in the car park: work on it in a bay, hand it back from here"
	return "out of its bay"


## Changes to anything the jobs list shows, so it's only rebuilt when they happen.
static func jobs_signature() -> String:
	var bits := [Contracts.reputation(), Contracts.customers().keys(), str(Contracts._st()["done"].size())]
	for id in Contracts.jobs():
		var j: Dictionary = Contracts.jobs()[id]
		bits.append([id, Contracts.evaluate(j).map(func(r): return r["have"]), Contracts.due_text(float(j["due"])),
			j.get("mot", {}).get("tests", 0), j.get("mot", {}).get("stale", false), Contracts.payout(j)["total"],
			Shed.check(Shed.me(), {"a": "contract_hand_in", "job": id})])
	return str(bits)


## Fills `box` with the jobs under way and the last few done.
static func fill_jobs(box: VBoxContainer) -> void:
	box.add_child(UITheme.label("Reputation %d  ·  Day %d  ·  %d customer%s at reception" % [Contracts.reputation(),
		Contracts.day_number(), Contracts.customers().size(), "" if Contracts.customers().size() == 1 else "s"], 16, UITheme.ACCENT))
	var next_up := []
	for k in Contracts.KINDS:
		if Contracts.reputation() < int(Contracts.UNLOCK[k]):
			next_up.append("%s at %d" % [Contracts.KIND_NAMES[k], int(Contracts.UNLOCK[k])])
	if not next_up.is_empty():
		box.add_child(UITheme.label("Harder jobs unlock with reputation: " + ", ".join(next_up) + ".", 14, Color(1, 1, 1, 0.6)))
	if Contracts.jobs().is_empty():
		box.add_child(UITheme.label("No jobs under way. Customers come to the sales office reception: a bell rings when one "
			+ "arrives. Look at them and press F to hear what they want.", 15, Color(1, 1, 1, 0.7)))
	for id in Contracts.jobs():
		_fill_job(box, Contracts.jobs()[id])
	var done: Array = Contracts._st()["done"]
	if not done.is_empty():
		box.add_child(UITheme.title("Done", 20))
		for d in done.slice(0, 6):
			var line := "Day %d  %s  ·  paid %s  ·  %s" % [int(d.get("day", 1)), str(d.get("title", "")),
				Contracts.money(int(d.get("paid", 0))), str(d.get("note", ""))]
			box.add_child(UITheme.label(line, 14, Color(1, 1, 1, 0.75)))
			var cert: Dictionary = d.get("cert", {})
			if not cert.is_empty():
				box.add_child(_certificate(cert))


static func _fill_job(box: VBoxContainer, job: Dictionary) -> void:
	var id := int(job["id"])
	var late := Contracts.clock() > float(job["due"])
	box.add_child(UITheme.title(str(job["title"]), 20))
	var bike: Dictionary = Shed.bikes.get(int(job["bike"]), {})
	var where := ContractPanel.where_text(bike)
	box.add_child(UITheme.label("For %s  ·  %s  ·  %s" % [job["customer"], where, Contracts.due_text(float(job["due"]))], 15,
		Color(1, 0.5, 0.4) if late else Color(1, 1, 1, 0.75)))
	for r in Contracts.evaluate(job):
		box.add_child(UITheme.label("%s  %s   (%s)" % ["[x]" if r["done"] else "[  ]", r["text"], r["have"]], 15,
			Color(0.5, 0.95, 0.55) if r["done"] else Color(0.9, 0.9, 0.9)))
	var pay := Contracts.payout(job)
	if int(job.get("budget", 0)) > 0:
		box.add_child(UITheme.label("Parts spent %s of a %s budget" % [Contracts.money(int(pay["spent"])), Contracts.money(int(job["budget"]))],
			15, Color(1, 0.5, 0.4) if int(pay["over"]) > 0 else Color(1, 1, 1, 0.75)))
	var m: Dictionary = job.get("mot", {})
	if m.get("tested", false):
		var sheet: Array = m.get("sheet", [])
		var fails := MotTest.fails(sheet)
		box.add_child(UITheme.label("MOT test %d: %s%s" % [int(m.get("tests", 1)), "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(),
			"  ·  worked on since: test again" if m.get("stale", false) else ""], 16,
			Color(0.5, 0.95, 0.55) if fails.is_empty() else Color(1, 0.5, 0.4)))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		for r in fails + sheet.filter(func(x): return x["pass"]):
			grid.add_child(UITheme.label("PASS" if r["pass"] else "FAIL", 13, Color(0.5, 0.95, 0.55) if r["pass"] else Color(1, 0.45, 0.35)))
			grid.add_child(UITheme.label(str(r["name"]), 13))
			grid.add_child(UITheme.label(str(r["value"]) + ("" if r["pass"] else "  ·  " + str(r["fix"])), 13, Color(1, 1, 1, 0.7)))
		box.add_child(grid)
	box.add_child(UITheme.label("Hand back now: %s  ·  %s" % [Contracts.money(int(pay["total"])), pay["note"]], 15, UITheme.ACCENT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if str(job["kind"]) == "mot":
		row.add_child(button("Run MOT test", func(): Shed.request({"a": "contract_mot_test", "job": id})))
	var why := Shed.check(Shed.me(), {"a": "contract_hand_in", "job": id})
	var hand := button("Hand back", func(): Shed.request({"a": "contract_hand_in", "job": id}))
	hand.disabled = why != ""
	hand.tooltip_text = why
	row.add_child(hand)
	box.add_child(row)
	if why != "":
		box.add_child(UITheme.label(why, 13, Color(1, 1, 1, 0.55)))
	box.add_child(HSeparator.new())


## An MOT certificate, as a little card.
static func _certificate(cert: Dictionary) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.92, 0.94, 0.88)
	s.border_color = Color(0.1, 0.45, 0.2)
	s.set_border_width_all(3)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", s)
	var col := VBoxContainer.new()
	p.add_child(col)
	col.add_child(UITheme.label("MOT TEST CERTIFICATE  ·  PASS", 16, Color(0.1, 0.4, 0.15)))
	col.add_child(UITheme.label("No. %s   Vehicle: %s   Keeper: %s" % [cert.get("number", ""), cert.get("bike", ""), cert.get("owner", "")],
		14, Color(0.1, 0.1, 0.1)))
	col.add_child(UITheme.label("Issued day %d by Torque Shed  ·  valid until day %d" % [int(cert.get("day", 1)), int(cert.get("expires", 1))],
		13, Color(0.2, 0.2, 0.2)))
	return p
