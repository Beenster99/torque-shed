class_name PartsComputer
extends Control
## The shed's parts computer: browse every part by kind, read its spec and order it, or order
## equipment for the shed. Deliveries are left outside the roller door. Free until money arrives.

signal closed

var _kinds: VBoxContainer
var _variants: VBoxContainer
var _title: Label
var _spec: Label
var _desc: Label
var _status: Label
var _order: Button
var _kind := "frame"
var _part := ""
var _section := "bike"
var _search: LineEdit
var _section_btns := {}
var _posters_shown := -1

## The shop's three aisles, so nobody scrolls through everything.
const SECTIONS := {"shed": "Shed", "bike": "Bike", "outdoors": "Outdoors"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080, 620)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_child(UITheme.title("PARTS COMPUTER"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var bike_btn := Button.new()
	bike_btn.text = "Order a project bike"
	bike_btn.pressed.connect(func(): Shed.request({"a": "order"}))
	head.add_child(bike_btn)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_computer)
	head.add_child(close)
	root.add_child(head)
	root.add_child(UITheme.label("Pick a kind of part, then a model. Orders arrive in boxes outside the roller door.", 15, Color(1, 1, 1, 0.6)))

	var aisles := HBoxContainer.new()
	aisles.add_theme_constant_override("separation", 8)
	for sec in SECTIONS:
		var sb := Button.new()
		sb.text = SECTIONS[sec]
		sb.toggle_mode = true
		sb.custom_minimum_size = Vector2(130, 40)
		sb.pressed.connect(_show_section.bind(sec))
		aisles.add_child(sb)
		_section_btns[sec] = sb
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aisles.add_child(gap)
	_search = LineEdit.new()
	_search.placeholder_text = "Search the shop..."
	_search.custom_minimum_size = Vector2(360, 40)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	aisles.add_child(_search)
	root.add_child(aisles)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	_kinds = _column(cols, 220)
	_variants = _column(cols, 300)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	cols.add_child(detail)
	_title = UITheme.title("", 24, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	_desc = UITheme.label("", 17)
	detail.add_child(_desc)
	_spec = UITheme.label("", 16, UITheme.ACCENT)
	detail.add_child(_spec)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(fill)
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	detail.add_child(_status)
	_order = Button.new()
	_order.text = "Order it (free for now)"
	_order.custom_minimum_size = Vector2(0, 48)
	_order.pressed.connect(func():
		if design_of(_part) != 0:
			Shed.request({"a": "order_furniture", "model": Equipment.BOARD_POSTER, "design": design_of(_part)})
		elif _kind.begins_with("eq:"):
			Shed.request({"a": "order_furniture", "model": _part})
		else:
			Shed.request({"a": "order_part", "part": _part}))
	detail.add_child(_order)

	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	# A poster made at the whiteboard while the list is up joins it.
	Shed.changed.connect(func():
		if visible and _kind == "eq:poster" and _posters_shown != Shed.posters.size() and (_search == null or _search.text == ""):
			_show_kind(_kind))
	_show_section(_section)


## Which aisle a kind is sold in.
static func section_of(k: String) -> String:
	if k.begins_with("eq:"):
		return "outdoors" if Equipment.YARD_KINDS.has(k.trim_prefix("eq:")) else "shed"
	return "bike"


## Every kind the shop sells, in shop order.
static func all_kinds() -> Array:
	var kinds: Array = []
	for k in Equipment.KINDS:
		if not Equipment.FIXED_KINDS.has(k):
			kinds.append("eq:" + k)
	kinds.append_array(PartsDB.FLUID_KINDS)
	kinds.append_array(PartsDB.KINDS)
	return kinds


static func kind_title(k: String) -> String:
	if k.begins_with("eq:"):
		return Equipment.KIND_NAMES[k.trim_prefix("eq:")]
	return ("Fluids: " if PartsDB.FLUID_KINDS.has(k) else "") + str(PartsDB.KIND_NAMES[k])


func _show_section(sec: String) -> void:
	_section = sec
	for key in _section_btns:
		_section_btns[key].button_pressed = key == sec
	for c in _kinds.get_children():
		c.queue_free()
	var first := ""
	for k in all_kinds():
		if section_of(k) != sec:
			continue
		if first == "":
			first = k
		var b := Button.new()
		b.text = kind_title(k)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(_pick_kind.bind(k))
		b.set_meta("kind", k)
		_kinds.add_child(b)
	if _search:
		_search.text = ""
	_show_kind(_kind if section_of(_kind) == sec else first)


func _refresh_list() -> void:
	var q := _search.text.strip_edges().to_lower()
	if q == "":
		_show_kind(_kind)
		return
	for c in _variants.get_children():
		c.queue_free()
	var found := search(q)
	_variants.add_child(UITheme.label("%d FOUND" % found.size(), 14, UITheme.ACCENT))
	for hit in found.slice(0, 80):
		var b := Button.new()
		b.text = "%s  ·  %s" % [hit["name"], kind_title(hit["kind"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_meta("part", hit["id"])
		b.pressed.connect(func(): _pick_found(hit["kind"], hit["id"]); _order.grab_focus())
		_variants.add_child(b)
	if not found.is_empty():
		_pick_found(found[0]["kind"], found[0]["id"])


func _pick_found(k: String, id: String) -> void:
	_kind = k
	for b in _kinds.get_children():
		b.button_pressed = b.get_meta("kind") == k
	_show_part(id)


## Everything in the shop whose name, kind or description matches every word typed.
static func search(q: String) -> Array:
	var words := q.to_lower().split(" ", false)
	var out: Array = []
	for k in all_kinds():
		var ids: Array = Equipment.by_kind(k.trim_prefix("eq:")) if k.begins_with("eq:") else PartsDB.by_kind[k]
		for id in ids:
			var name := ""
			var text := ""
			if k.begins_with("eq:"):
				var m := Equipment.get_model(id)
				name = str(m["name"])
				text = str(m.get("desc", ""))
			else:
				var p := PartsDB.get_part(id)
				name = PartsDB.part_name(id)
				text = str(p.get("description", "")) + " " + str(p.get("type", ""))
			var hay := (name + " " + kind_title(k) + " " + text + " " + str(id)).to_lower()
			var all_in := true
			for w in words:
				if not hay.contains(w):
					all_in = false
					break
			if all_in:
				out.append({"kind": k, "id": id, "name": name, "title": name.to_lower().contains(words[0]) if words.size() > 0 else false})
	out.sort_custom(func(a, b): return a["title"] and not b["title"])
	return out


func _column(parent: Control, width: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true   # the list scrolls along as the pad moves down it
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	return box


func open() -> void:
	visible = true
	_status.text = "Room in the delivery area: %s" % ("no, bring some boxes in first" if Shed.free_delivery_xf() == null else "yes")
	if _kind == "eq:poster":
		_show_kind(_kind)   # whiteboard prints made since it was last open
	_focus_kind()


## Puts the pad's focus on the kind being shown (or the first one), so A works straight away.
func _focus_kind() -> void:
	var first: Control = null
	for b in _kinds.get_children():
		if b.is_queued_for_deletion():
			continue
		if first == null:
			first = b
		if b.get_meta("kind") == _kind:
			b.grab_focus()
			return
	if first:
		first.grab_focus()


## The button in the parts list for the part being shown.
func _focus_part() -> void:
	for b in _variants.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.get_meta("part", "") == _part:
			b.grab_focus()
			return
	_focus_kind()


func close_computer() -> void:
	visible = false
	closed.emit()


func _show_kind(k: String) -> void:
	_kind = k
	if _search and _search.text != "":
		_search.text = ""
	for b in _kinds.get_children():
		b.button_pressed = b.get_meta("kind") == k
	for c in _variants.get_children():
		c.queue_free()
	var ids: Array = Equipment.by_kind(k.trim_prefix("eq:")) if k.begins_with("eq:") else PartsDB.by_kind[k]
	var group := ""
	if k == "engine":
		ids = ids.duplicate()
		var order := ["Single", "Twin", "Parallel twin", "V-twin", "Boxer twin", "Inline triple", "Inline four", "Two-stroke"]
		ids.sort_custom(func(a, b):
			var pa := PartsDB.get_part(a)
			var pb := PartsDB.get_part(b)
			var ta := order.find(str(pa.get("type", "")))
			var tb := order.find(str(pb.get("type", "")))
			return ta < tb if ta != tb else float(pa["displacement"]) < float(pb["displacement"]))
	for id in ids:
		if k == "engine" and str(PartsDB.get_part(id).get("type", "")) != group:
			# Engines come in families: a heading over each layout's sizes.
			group = str(PartsDB.get_part(id).get("type", ""))
			_variants.add_child(UITheme.label(group.to_upper(), 14, UITheme.ACCENT))
		var b := Button.new()
		if k.begins_with("eq:"):
			b.text = str(Equipment.get_model(id)["name"]) + ("  (compact)" if Equipment.get_model(id).get("compact", false) else "")
		else:
			b.text = PartsDB.part_name(id) + ("  (light)" if PartsDB.is_lightweight(id) else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_meta("part", id)
		b.pressed.connect(_pick_part.bind(id))
		b.focus_entered.connect(_show_part.bind(id))
		_variants.add_child(b)
	_posters_shown = Shed.posters.size()
	if k == "eq:poster":
		# The crew's own whiteboard drawings, saved as posters at the board.
		_variants.add_child(UITheme.label("FROM THE WHITEBOARD", 14, UITheme.ACCENT))
		if Shed.posters.is_empty():
			var none := UITheme.label("None yet: press K at the whiteboard to make one.", 14, Color(1, 1, 1, 0.5))
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_variants.add_child(none)
		for d in Shed.posters:
			var key := "design:%d" % int(d)
			var b := Button.new()
			b.text = str(Shed.posters[d]["name"])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.set_meta("part", key)
			b.pressed.connect(_pick_part.bind(key))
			b.focus_entered.connect(_show_part.bind(key))
			_variants.add_child(b)
	_show_part(ids[0])


## The whiteboard poster design a "design:<id>" entry in the poster list is, or 0.
static func design_of(part: String) -> int:
	return int(part.trim_prefix("design:")) if part.begins_with("design:") else 0


func _show_part(id: String) -> void:
	_part = id
	for b in _variants.get_children():
		if b.has_meta("part"):
			b.button_pressed = b.get_meta("part") == id
	if design_of(id) != 0:
		var d: Dictionary = Shed.posters.get(design_of(id), {})
		var m := Equipment.get_model(Equipment.BOARD_POSTER)
		_title.text = str(d.get("name", "Whiteboard poster"))
		_desc.text = "%s Saved from the whiteboard by %s." % [m["desc"], str(d.get("by", "the crew"))]
		_spec.text = Equipment.spec_line(Equipment.BOARD_POSTER).replace("  ·  ", "\n") \
			+ "\n\nArrives outside the roller door. Press F on it to carry it in, look at a wall and press F to hang it."
		return
	if _kind.begins_with("eq:"):
		var m := Equipment.get_model(id)
		_title.text = str(m["name"])
		_desc.text = str(m["desc"])
		var how := "Left in the yard by the drag strip. Press F on it to push it, F again to put it down." if Equipment.is_yard(id) else \
			"Arrives outside the roller door. Press F on it to carry it in, look at a wall and press F to hang it." \
			if Equipment.is_wall(id) else ("Arrives outside the roller door. Hold F on it to move it." if m["kind"] == "seat"
			else "Arrives outside the roller door. Press F on it to push it in and F again to put it down.")
		_spec.text = Equipment.spec_line(id).replace("  ·  ", "\n") + "\n\n" + how
		return
	var p := PartsDB.get_part(id)
	_title.text = str(p["name"])
	_desc.text = str(p.get("description", ""))
	if _kind == "chain_lube":
		_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\nHold it, crouch by a bike's chain and hold left mouse to lube it." \
			+ " A dry chain wastes power and wears out.\nDelivered outside, no box to unpack."
		return
	if PartsDB.FLUID_KINDS.has(_kind):
		var into: String = {"petrol": "the fuel tank", "oil": "the engine", "brake_fluid": "the front and rear brake master cylinders"}[_kind]
		var how := "Hold it and aim at %s: left mouse pours it in, right mouse drains into it." % into
		if p.get("empty", false):
			how = "Hold it and aim at %s, then hold right mouse to drain into it. Tip it out in the scrap bin." % into
		_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\n" + how + "\nDelivered outside, no box to unpack."
		return
	var fits := PartsDB.slots_for_kind(_kind).map(func(s): return PartsDB.slot_name(s).to_lower())
	_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\nFits: " + ", ".join(fits)
	if _kind == "chain":
		_spec.text += "\n\nCrouch by the bike with the wrench and hold right mouse to set the tension. Lube it with chain lube."


## A kind picked (A on a pad, or a click): its parts list, with the pad's focus on the first.
func _pick_kind(k: String) -> void:
	_show_kind(k)
	_focus_part()


## A part picked: the focus goes to the Order button, so a second A orders it.
func _pick_part(id: String) -> void:
	_show_part(id)
	_order.grab_focus()


## B on a pad steps back: Order button to the parts list, parts list to the kinds, then closes.
func back() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == _order:
		_focus_part()
	elif f != null and (_variants.is_ancestor_of(f) or f == _search):
		_focus_kind()
	else:
		close_computer()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		close_computer()
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		back()
	elif event is InputEventJoypadButton and (event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev")):
		# LB / RB: the aisle to the left or right.
		var keys := SECTIONS.keys()
		var step := 1 if event.is_action_pressed("tool_next") else -1
		_show_section(keys[posmod(keys.find(_section) + step, keys.size())])
		_focus_kind()
	else:
		return
	get_viewport().set_input_as_handled()
