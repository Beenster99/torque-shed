class_name StaffPanel
extends Control
## Talking to one of the staff (F on them, or Assign on the Staff tab): what they say (a fresh
## line each time you chat: the job, how they feel, their trade, their back story), who they are
## (role, skill level and how far to the next, mood, wage), what they're doing now and how far
## through, and giving them a job to go and do: the jobs their role does, each with its choices
## (which bike; the slot and part for fitting; the part, colour and finish for paint; the
## detailing steps; the asking price for a sale), a tea run for anyone, stopping what they're on,
## and letting them go. Everything goes to the host as staff_* requests (see Staff).

signal closed

var worker_id := 0
## The job being set up (kept while the card refreshes): {kind, bike, slot, part, color,
## finish, steps, ask}.
var choice := {}
var _talk_n := 0
var _line := ""
var _firing := false
var _box: VBoxContainer
var _status: Label
var _bar: ProgressBar
var _said: Label
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("staff_panel")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	Shed.changed.connect(func(): if visible: _refresh())


## Talking to worker `id`.
func open_worker(id: int) -> void:
	if id != worker_id:
		choice = {}
		_firing = false
	worker_id = id
	var w := Staff.worker(id)
	_talk_n += 1
	_line = Staff.talk_line(w, _talk_n)
	if choice.is_empty():
		choice = default_choice(w)
	_sig = ""
	visible = true
	_refresh()


## A job to start from for `w`: their role's first job on the first bike that fits it.
static func default_choice(w: Dictionary) -> Dictionary:
	var c := {"kind": "", "bike": 0, "slot": "front_pads", "part": "", "color": 1, "finish": "gloss", "steps": ["wash"], "ask": 0, "his": true, "lib": "", "sheen": "gloss"}
	var kinds := kinds_for(w)
	c["kind"] = kinds[0] if not kinds.is_empty() else "tea"
	var bikes := bikes_for(str(c["kind"]))
	c["bike"] = int(bikes[0]) if not bikes.is_empty() else 0
	_fill_defaults(c)
	return c


## The jobs `w` can be given, their role's first.
static func kinds_for(w: Dictionary) -> Array:
	var out := []
	for k in Staff.JOBS:
		var roles: Array = Staff.JOBS[k]
		if roles.has(str(w.get("role", ""))):
			out.append(k)
	out.append("tea")
	return out


## The bikes a job of `kind` could be on (the shed's own only, for a sale), by id.
static func bikes_for(kind: String) -> Array:
	if not Staff.BIKE_JOBS.has(kind):
		return []
	var ids := []
	for id in Shed.bikes:
		if kind == "sell" and Sales.is_customer_bike(int(id)):
			continue
		ids.append(int(id))
	ids.sort()
	return ids


## The slots a part can be fitted to by staff.
static func fit_slots() -> Array:
	var out := []
	for slot in PartsDB.SLOTS:
		if slot in ["frame", "engine"] or (PartsDB.is_engine_slot(slot) and not PartsDB.SERVICE_SLOTS.has(slot)):
			continue
		out.append(slot)
	return out


## The colour book's paints worker `w` can mix and spray at their level.
static func mixable(w: Dictionary) -> Array:
	return PaintMix.library().filter(func(e): return StaffJobs.paint_why(w, StaffJobs.paint_spec({"lib": str(e["id"])})) == "")


## Fills in the choices that depend on the bike: the part on it now for a fitting, its recommended
## price for a sale.
static func _fill_defaults(c: Dictionary) -> void:
	var b := int(c.get("bike", 0))
	if str(c["kind"]) == "fit":
		var kind := str(PartsDB.SLOT_KIND.get(str(c["slot"]), ""))
		var opts: Array = PartsDB.by_kind.get(kind, [])
		var on := Shed.item_on(b, str(c["slot"])) if Shed.bikes.has(b) else 0
		if on != 0:
			c["part"] = str(Shed.items[on]["part"])
		elif not opts.has(str(c.get("part", ""))):
			c["part"] = str(opts[0]) if not opts.is_empty() else ""
	if str(c["kind"]) == "sell" and Shed.bikes.has(b):
		c["ask"] = int(Sales.appraise(b, Staff.margin()).get("recommended", 0))


## The job request for the choices made now.
func job() -> Dictionary:
	var kind := str(choice.get("kind", ""))
	var j := {"kind": kind}
	match kind:
		"service", "project":
			j["bike"] = int(choice["bike"])
		"fit":
			j.merge({"bike": int(choice["bike"]), "slot": str(choice["slot"]), "part": str(choice["part"])})
		"paint":
			j.merge({"bike": int(choice["bike"]), "slot": str(choice["slot"]) if StaffJobs.PAINT_SLOTS.has(str(choice["slot"])) else "tank",
				"color": int(choice["color"]), "finish": str(choice["finish"])})
			if str(choice.get("lib", "")) != "":
				j.merge({"lib": str(choice["lib"]), "sheen": str(choice.get("sheen", "gloss"))})
		"detail":
			j.merge({"bike": int(choice["bike"]), "steps": (choice["steps"] as Array).duplicate()})
		"sell":
			# 0: he prices it himself, from what it cost and what it's worth at the target margin.
			j.merge({"bike": int(choice["bike"]), "ask": 0 if choice.get("his", true) else int(choice["ask"])})
	return j


## Changes one of the job's choices (the controls, and tests).
func set_choice(key: String, value) -> void:
	choice[key] = value
	if key == "kind":
		var bikes := bikes_for(str(value))
		if not bikes.has(int(choice.get("bike", 0))) and not bikes.is_empty():
			choice["bike"] = int(bikes[0])
		if str(value) == "paint" and not StaffJobs.PAINT_SLOTS.has(str(choice.get("slot", ""))):
			choice["slot"] = "tank"
		elif str(value) == "fit" and not fit_slots().has(str(choice.get("slot", ""))):
			choice["slot"] = "front_pads"
	if key in ["kind", "bike", "slot"]:
		_fill_defaults(choice)
	_sig = ""
	_refresh()


## Sends the job off.
func assign() -> void:
	Shed.request({"a": "staff_assign", "worker": worker_id, "job": job()})
	_sig = ""


## Presses the button labelled `text` (for tests).
func press(text: String) -> void:
	for b in _box.find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not b.is_queued_for_deletion():
			(b as Button).pressed.emit()
			return


## The buttons showing now (tests).
func buttons() -> Array[String]:
	var out: Array[String] = []
	for b in _box.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion() and not (b is OptionButton):
			out.append((b as Button).text)
	return out


## Everything the card says now (tests).
func text() -> String:
	var lines := []
	for l in _box.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			lines.append((l as Label).text)
	return "\n".join(lines)


func close_dialog() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	var w := Staff.worker(worker_id)
	if w.is_empty():
		close_dialog()   # let go (or the shed was reset)
		return
	var sig := "%d|%s|%s|%d|%d|%s|%s|%s|%d|%s|%d|%.2f" % [worker_id, str(choice), _line, Staff.level(w), int(w["wage"]), str(w["sick"]),
		str((w["job"] as Dictionary).is_empty()), str(_firing), Shed.bikes.size(), Staff.mood_word(w), Shed.garage_money / 100, Staff.margin()]
	if sig != _sig:
		_sig = sig
		for c in _box.get_children():
			c.queue_free()
		_fill(w)
	_status.text = Staff.status_text(w)
	_bar.visible = not (w["job"] as Dictionary).is_empty()
	_bar.value = Staff.progress(w) * 100.0
	var said := Staff.saying(w)
	_said.text = "\"%s\"" % (said if said != "" else _line)


func _fill(w: Dictionary) -> void:
	var first := Staff.first_name(w)
	_box.add_child(UITheme.title(str(w["name"]).to_upper(), 26))
	_box.add_child(UITheme.label("%s  ·  level %d  ·  %s  ·  %s a day" % [Staff.role_name(str(w["role"])), Staff.level(w), Staff.mood_word(w),
		Staff.money(int(w["wage"]))], 16, UITheme.ACCENT))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(0, 8)
	xp.show_percentage = false
	xp.value = Staff.level_frac(w) * 100.0
	xp.tooltip_text = "Skill: %d XP. Each level makes them quicker, slip up less and do a better job." % int(w["xp"])
	_box.add_child(xp)
	_said = UITheme.label("", 17, Color(1, 1, 1, 0.85))
	_box.add_child(_said)
	_status = UITheme.label("", 15)
	_box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_box.add_child(_bar)
	_box.add_child(UITheme.label(Staff.story_text(w), 14, Color(1, 1, 1, 0.55)))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(ContractPanel.button("Chat", func():
		_talk_n += 1
		_line = Staff.talk_line(Staff.worker(worker_id), _talk_n)
		_refresh()))
	if not (w["job"] as Dictionary).is_empty():
		top.add_child(ContractPanel.button("Stop that job", func():
			Shed.request({"a": "staff_cancel", "worker": worker_id})
			_sig = ""))
	_box.add_child(top)
	if str(w["role"]) == "sales":
		_fill_margin(w)
	if w["sick"]:
		_box.add_child(UITheme.label("%s's off sick today. Back tomorrow, hopefully." % first, 16, Color(1, 0.55, 0.45)))
	else:
		_fill_job(w)
	_box.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	if _firing:
		bottom.add_child(UITheme.label("Let %s go?" % first, 16, Color(1, 0.6, 0.5)))
		bottom.add_child(ContractPanel.button("Yes, let them go", func():
			Shed.request({"a": "staff_fire", "worker": worker_id})
			_firing = false))
		bottom.add_child(ContractPanel.button("No", func():
			_firing = false
			_sig = ""
			_refresh()))
	else:
		bottom.add_child(ContractPanel.button("Let %s go" % first, func():
			_firing = true
			_sig = ""
			_refresh()))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(spacer)
		bottom.add_child(ContractPanel.button("Done ({back})", close_dialog))
	_box.add_child(bottom)


## The job choices for their role, and the button to send them off.
func _fill_job(w: Dictionary) -> void:
	_box.add_child(UITheme.label("GIVE %s A JOB" % Staff.first_name(w).to_upper(), 15, UITheme.ACCENT))
	var kinds := kinds_for(w)
	var kind := str(choice.get("kind", ""))
	if not kinds.has(kind):
		kind = str(kinds[0])
		choice["kind"] = kind
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_box.add_child(grid)
	var names := []
	for k in kinds:
		names.append(str(Staff.JOB_NAMES.get(k, k)))
	_option(grid, "Job", names, kinds.find(kind), func(i): set_choice("kind", kinds[i]))
	var bikes := bikes_for(kind)
	if Staff.BIKE_JOBS.has(kind):
		var bike_names := []
		for b in bikes:
			bike_names.append("%s%s" % [str(Shed.bikes[b]["name"]), " (customer's)" if Sales.is_customer_bike(int(b)) else ""])
		_option(grid, "Bike", bike_names, bikes.find(int(choice.get("bike", 0))), func(i): set_choice("bike", int(bikes[i])))
	match kind:
		"project":
			# The list they'll work through, as it stands, with what they'd have to leave.
			var tasks := StaffJobs.project_tasks(int(choice.get("bike", 0)))
			var lines := []
			for t in tasks.slice(0, 10):
				var why := StaffJobs.task_why(w, int(choice.get("bike", 0)), t)
				var done := StaffJobs.task_done(int(choice.get("bike", 0)), t)
				lines.append("%s %s%s" % ["✓" if done else ("–" if why != "" else "•"), str(t["text"]), "  (%s)" % why if why != "" and not done else ""])
			if tasks.size() > 10:
				lines.append("... and %d more" % (tasks.size() - 10))
			grid.add_child(_grid_label("List"))
			var l := UITheme.label("\n".join(lines) if not lines.is_empty() else "Nothing listed.", 14, Color(1, 1, 1, 0.8))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(l)
		"fit":
			var slots := fit_slots()
			_option(grid, "Slot", slots.map(func(s): return PartsDB.slot_name(s)), slots.find(str(choice["slot"])),
				func(i): set_choice("slot", slots[i]))
			var parts: Array = PartsDB.by_kind.get(str(PartsDB.SLOT_KIND.get(str(choice["slot"]), "")), [])
			_option(grid, "Part", parts.map(func(p): return "%s  ·  %s" % [PartsDB.part_name(p), Staff.money(int(PartsDB.get_part(p).get("price", 0)))]),
				parts.find(str(choice["part"])), func(i): set_choice("part", parts[i]))
		"paint":
			var slots: Array = StaffJobs.PAINT_SLOTS
			_option(grid, "Part", slots.map(func(s): return PartsDB.slot_name(s)), slots.find(str(choice["slot"])),
				func(i): set_choice("slot", slots[i]))
			# Plain spray-can colours, or a mixed paint from the colour book that they're up to.
			var libs := mixable(w)
			var paints := ["Spray can (plain colours)"]
			for e in libs:
				paints.append("%s  ·  %s" % [PaintMix.library_name(e), PaintMix.effect_name(str(e["effect"])).to_lower()])
			var at := 0
			for i in libs.size():
				if str(libs[i]["id"]) == str(choice.get("lib", "")):
					at = i + 1
			_option(grid, "Paint", paints, at, func(i): set_choice("lib", "" if i == 0 else str(libs[i - 1]["id"])))
			if str(choice.get("lib", "")) == "":
				_option(grid, "Colour", Shed.PAINT_NAMES.map(func(n): return str(n).capitalize()), int(choice["color"]),
					func(i): set_choice("color", i))
				var fins: Array = Array(Shed.FINISHES)
				_option(grid, "Finish", fins.map(func(f): return str(f).capitalize()), fins.find(str(choice["finish"])),
					func(i): set_choice("finish", fins[i]))
			else:
				var sheens: Array = PaintMix.SHEENS.keys()
				_option(grid, "Sheen", sheens.map(func(s): return str(s).capitalize()), sheens.find(str(choice.get("sheen", "gloss"))),
					func(i): set_choice("sheen", sheens[i]))
			var locked := PaintMix.library().size() - libs.size()
			if locked > 0:
				grid.add_child(_grid_label(""))
				grid.add_child(UITheme.label("%d more in the book as %s gets better (pearl at level 3, candy 5, flake 6, chrome 8, chameleon 9)."
					% [locked, Staff.first_name(w)], 13, Color(1, 1, 1, 0.55)))
		"detail":
			grid.add_child(_grid_label("Steps"))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			for step in StaffJobs.DETAIL_STEPS:
				var st: String = step
				var cb := CheckBox.new()
				cb.text = str(StaffJobs.DETAIL_NAMES.get(st, st)).capitalize() + ("" if str(StaffJobs.DETAIL_STEPS[st]) != "" else " (no kit yet)")
				cb.button_pressed = (choice["steps"] as Array).has(st)
				cb.toggled.connect(func(on: bool):
					var steps: Array = (choice["steps"] as Array).duplicate()
					if on and not steps.has(st):
						steps.append(st)
					elif not on:
						steps.erase(st)
					set_choice("steps", steps))
				row.add_child(cb)
			grid.add_child(row)
		"sell":
			grid.add_child(_grid_label("Price"))
			var his := CheckBox.new()
			his.text = "His price: cost and value at the %d%% target margin" % roundi(Staff.margin() * 100.0)
			his.button_pressed = bool(choice.get("his", true))
			his.toggled.connect(func(on: bool): set_choice("his", on))
			grid.add_child(his)
			grid.add_child(_grid_label("Asking"))
			var ask := SpinBox.new()
			ask.min_value = 0
			ask.max_value = 1000000
			ask.step = 50
			ask.prefix = TvChannels.CURRENCY
			ask.value = int(choice.get("ask", 0))
			ask.editable = not bool(choice.get("his", true))
			ask.custom_minimum_size = Vector2(170, 0)
			ask.value_changed.connect(func(v): choice["ask"] = int(v))
			grid.add_child(ask)
	var j := job()
	var why := Shed.check(Shed.me(), {"a": "staff_assign", "worker": worker_id, "job": j})
	var go := ContractPanel.button("Get on with it" if kind != "tea" else "Off you go", assign)
	go.disabled = why != ""
	go.tooltip_text = Controls.hint(why)
	_box.add_child(go)
	if why != "":
		_box.add_child(UITheme.label(why, 15, Color(1, 0.5, 0.4)))


## The salesman's target margin: what he prices bikes to make and haggles for (he gives a little
## of it away to get a sale, less the better he is), and what his last sale made.
func _fill_margin(w: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	var names := []
	var at := 0
	for i in Sales.MARGINS.size():
		names.append("%d%% of the price" % roundi(Sales.MARGINS[i] * 100.0))
		if absf(Sales.MARGINS[i] - Staff.margin()) < 0.001:
			at = i
	var ob := _option(grid, "Target margin", names, at, func(i: int):
		Shed.request({"a": "staff_margin", "margin": Sales.MARGINS[i]})
		_sig = "")
	ob.tooltip_text = "He prices bikes from what they've cost and what they're worth to make this, and won't sell under %d%%." % roundi(Staff.floor_margin(w) * 100.0)
	_box.add_child(grid)
	var sold: Dictionary = w.get("sold", {})
	if not sold.is_empty():
		_box.add_child(UITheme.label("Last sale: the %s for %s, a %d%% margin (target %d%%)." % [str(sold["bike"]), Staff.money(int(sold["amount"])),
			roundi(float(sold["margin"]) * 100.0), roundi(float(sold["target"]) * 100.0)], 14, UITheme.ACCENT))


func _option(grid: GridContainer, label: String, items: Array, selected: int, on_pick: Callable) -> OptionButton:
	grid.add_child(_grid_label(label))
	var ob := OptionButton.new()
	ob.name = label
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		ob.add_item(str(it))
	if selected >= 0 and selected < items.size():
		ob.select(selected)
	ob.item_selected.connect(on_pick)
	grid.add_child(ob)
	return ob


## A label for the start of a row: one line, never squeezed into a column of letters.
static func _grid_label(text: String) -> Label:
	var l := UITheme.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
