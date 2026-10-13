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
		if _kind.begins_with("eq:"):
			Shed.request({"a": "order_furniture", "model": _part})
		else:
			Shed.request({"a": "order_part", "part": _part}))
	detail.add_child(_order)

	var kinds: Array = []
	for k in Equipment.KINDS:
		kinds.append("eq:" + k)
	kinds.append_array(PartsDB.FLUID_KINDS)
	kinds.append_array(PartsDB.KINDS)
	for k in kinds:
		var b := Button.new()
		if k.begins_with("eq:"):
			var ek: String = k.trim_prefix("eq:")
			b.text = ("Yard: " if Equipment.YARD_KINDS.has(ek) else ("Decor: " if ek in ["poster", "seat", "tv"] else "Shed: ")) + Equipment.KIND_NAMES[ek]
		else:
			b.text = PartsDB.KIND_NAMES[k]
		if PartsDB.FLUID_KINDS.has(k):
			b.text = "Fluids: " + b.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(_show_kind.bind(k))
		b.set_meta("kind", k)
		_kinds.add_child(b)
	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	_show_kind(_kind)


func _column(parent: Control, width: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	return box


func open() -> void:
	visible = true
	_status.text = "Room in the delivery area: %s" % ("no, bring some boxes in first" if Shed.free_delivery_xf() == null else "yes")
	for b in _kinds.get_children():
		if b.get_meta("kind") == _kind:
			b.grab_focus()


func close_computer() -> void:
	visible = false
	closed.emit()


func _show_kind(k: String) -> void:
	_kind = k
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
		b.pressed.connect(_show_part.bind(id))
		b.focus_entered.connect(_show_part.bind(id))
		_variants.add_child(b)
	_show_part(ids[0])


func _show_part(id: String) -> void:
	_part = id
	for b in _variants.get_children():
		if b.has_meta("part"):
			b.button_pressed = b.get_meta("part") == id
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


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		close_computer()
		get_viewport().set_input_as_handled()
