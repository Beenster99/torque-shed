class_name UpgradesPanel
extends Control
## The parts computer's Garage upgrades page: every upgrade the garage can buy (GarageUpgrades)
## with its price, what it needs first and whether it's built, and a Buy button that spends the
## garage's money. Anyone can buy; the host checks it and builds it for everyone.

var _list: VBoxContainer
var _title: Label
var _desc: Label
var _spec: Label
var _status: Label
var _money: Label
var _buy: Button
var _pick := ""
var _rows := {}      # upgrade id -> its Button in the list
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
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
	head.add_child(UITheme.title("GARAGE UPGRADES"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_money = UITheme.title("", 24, Color(0.5, 0.95, 0.55))
	head.add_child(_money)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	head.add_child(gap)
	var back := Button.new()
	back.text = "Back to parts (Esc)"
	back.pressed.connect(close)
	head.add_child(back)
	root.add_child(head)
	root.add_child(UITheme.label("Spend the garage's money on a bigger, better shed. Anyone in the crew can buy; it's built for everyone at once.", 15, Color(1, 1, 1, 0.6)))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	cols.add_child(detail)
	_title = UITheme.title("", 24, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	_desc = UITheme.label("", 17)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_desc)
	_spec = UITheme.label("", 16, UITheme.ACCENT)
	_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_spec)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(fill)
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_status)
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(0, 48)
	_buy.pressed.connect(buy)
	detail.add_child(_buy)
	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	Shed.changed.connect(func(): if visible: refresh())
	visible = false


func open() -> void:
	visible = true
	_status.text = ""
	_sig = ""
	refresh()
	if _rows.has(_pick):
		(_rows[_pick] as Button).grab_focus()


func close() -> void:
	visible = false


## Redraws the list when the garage's money or upgrades change.
func refresh() -> void:
	_money.text = "Garage: %s" % TvChannels.money_text(Shed.garage_money)
	var sig := "%d|%s" % [Shed.garage_money, str(Shed.upgrades.keys())]
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for cat in GarageUpgrades.CATEGORIES:
		_list.add_child(UITheme.label(str(GarageUpgrades.CATEGORIES[cat]).to_upper(), 14, UITheme.ACCENT))
		for id in GarageUpgrades.CATALOGUE:
			if GarageUpgrades.CATALOGUE[id]["cat"] != cat:
				continue
			var b := Button.new()
			b.text = row_text(id)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.pressed.connect(pick.bind(id))
			b.focus_entered.connect(show_upgrade.bind(id))
			_list.add_child(b)
			_rows[id] = b
			if _pick == "":
				_pick = id
	show_upgrade(_pick)


## A row of the list: name, price and where it stands.
static func row_text(id: String) -> String:
	var state := ""
	if GarageUpgrades.owned(id):
		state = "BUILT"
	elif not GarageUpgrades.missing_needs(id, Shed.upgrades).is_empty():
		state = "needs " + ", ".join(GarageUpgrades.missing_needs(id, Shed.upgrades).map(func(n): return GarageUpgrades.title(n)))
	return "%s  ·  %s%s" % [GarageUpgrades.title(id), TvChannels.money_text(GarageUpgrades.price(id)), "  ·  " + state if state != "" else ""]


func show_upgrade(id: String) -> void:
	if not GarageUpgrades.exists(id):
		return
	_pick = id
	for key in _rows:
		(_rows[key] as Button).button_pressed = key == id
	var u: Dictionary = GarageUpgrades.CATALOGUE[id]
	_title.text = str(u["name"])
	_desc.text = str(u["desc"])
	var needs: Array = u["needs"]
	_spec.text = "Price: %s\nNeeds: %s" % [TvChannels.money_text(int(u["price"])),
		"nothing" if needs.is_empty() else ", ".join(needs.map(func(n): return GarageUpgrades.title(n) + (" (built)" if GarageUpgrades.owned(n) else "")))]
	var why := Shed.check(Shed.me(), {"a": "buy_upgrade", "id": id})
	if GarageUpgrades.owned(id):
		_buy.text = "Built"
	else:
		_buy.text = "Buy for %s" % TvChannels.money_text(int(u["price"]))
	_buy.disabled = why != ""
	_buy.tooltip_text = why
	if why != "" and not GarageUpgrades.owned(id):
		_status.text = why


func pick(id: String) -> void:
	show_upgrade(id)
	_buy.grab_focus()


## Buys the upgrade being shown with the garage's money (the host checks it).
func buy() -> void:
	if _pick != "":
		Shed.request({"a": "buy_upgrade", "id": _pick})


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
