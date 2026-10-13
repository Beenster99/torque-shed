class_name PartsComputer
extends Control
## The shed's parts computer: browse every part by kind, read its spec and order it, or order
## equipment for the shed. Deliveries are left outside the roller door. Free until money arrives.

signal closed

const EQUIPMENT := {
	"stand": {"name": "Engine stand", "desc": "A wheeled stand to strip and build an engine on. Get more than one and you can build engines while the bikes are being worked on.", "spec": "Holds one engine  ·  push it anywhere with F"},
	"shelf": {"name": "Shelving unit", "desc": "Steel shelving for parts and boxed stock, with a label plate on top so everyone knows what goes where.", "spec": "Three shelves, six places  ·  push it anywhere with F"},
}

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
		if _kind == "equipment":
			Shed.request({"a": "order_furniture", "kind": _part})
		else:
			Shed.request({"a": "order_part", "part": _part}))
	detail.add_child(_order)

	var kinds: Array = ["equipment"]
	kinds.append_array(PartsDB.FLUID_KINDS)
	kinds.append_array(PartsDB.KINDS)
	for k in kinds:
		var b := Button.new()
		b.text = "Shed equipment" if k == "equipment" else PartsDB.KIND_NAMES[k]
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
	var ids: Array = EQUIPMENT.keys() if k == "equipment" else PartsDB.by_kind[k]
	for id in ids:
		var b := Button.new()
		b.text = EQUIPMENT[id]["name"] if k == "equipment" else PartsDB.part_name(id)
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
	if _kind == "equipment":
		_title.text = EQUIPMENT[id]["name"]
		_desc.text = EQUIPMENT[id]["desc"]
		_spec.text = EQUIPMENT[id]["spec"]
		return
	var p := PartsDB.get_part(id)
	_title.text = str(p["name"])
	_desc.text = str(p.get("description", ""))
	if PartsDB.FLUID_KINDS.has(_kind):
		var into: String = {"petrol": "the fuel tank", "oil": "the engine", "brake_fluid": "the front and rear brake master cylinders"}[_kind]
		var how := "Hold it and aim at %s: left mouse pours it in, right mouse drains into it." % into
		if p.get("empty", false):
			how = "Hold it and aim at %s, then hold right mouse to drain into it. Tip it out in the scrap bin." % into
		_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\n" + how + "\nDelivered outside, no box to unpack."
		return
	var fits := PartsDB.slots_for_kind(_kind).map(func(s): return PartsDB.slot_name(s).to_lower())
	_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\nFits: " + ", ".join(fits)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		close_computer()
		get_viewport().set_input_as_handled()
