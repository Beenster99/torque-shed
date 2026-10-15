class_name UpgradesPanel
extends Control
## The parts computer's Garage upgrades page: every upgrade the garage can buy (GarageUpgrades)
## with its price, what it needs first and whether it's built, and a Buy button that spends the
## garage's money. Anyone can buy; the host checks it and builds it for everyone.
## Finishes with choices (GarageUpgrades.OPTIONS: floor colours and effects, light colours, wall
## colours, neon, the showroom's styles) show swatches and a little preview room; picking one
## also tries it on the real shed, on this screen only, until the page closes. "See it in the
## shed" hides the page to look. A finish already built can be changed for a small fee.

var _list: VBoxContainer
var _title: Label
var _desc: Label
var _spec: Label
var _status: Label
var _money: Label
var _buy: Button
var _peek: Button
var _pick := ""
var _rows := {}      # upgrade id -> its Button in the list
var _sig := ""
var _shade: ColorRect
var _center: CenterContainer
var _opts_box: VBoxContainer
var _opts_scroll: ScrollContainer
var _thumb: LookPreview
var _thumb_box: VBoxContainer
var _peek_bar: PanelContainer
var _peek_label: Label
## The choices picked on this page: upgrade id -> {option: choice}. Starts at what's built.
var _drafts := {}
## The swatch buttons shown: option key -> {choice id: Button}, and each option's label.
var _swatches := {}
var _opt_labels := {}
var _shown_id := ""
## Whether the shed itself is showing the look being picked (WorkshopUpgrades.set_preview).
var previewing := false
## Whether the page is hidden to look at the shed.
var peeking := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.6)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 700)
	_center.add_child(panel)
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
	root.add_child(UITheme.label("Spend the garage's money on a bigger, better shed. Anyone in the crew can buy; it's built for everyone at once. Finishes come in colours and styles: pick before you buy.", 15, Color(1, 1, 1, 0.6)))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	cols.add_child(detail)
	_title = UITheme.title("", 24, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	_desc = UITheme.label("", 16)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_desc)
	_spec = UITheme.label("", 15, UITheme.ACCENT)
	_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_spec)
	# The choices (scrolling if there are many) beside the preview room.
	var looks_row := HBoxContainer.new()
	looks_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	looks_row.add_theme_constant_override("separation", 12)
	detail.add_child(looks_row)
	_opts_scroll = ScrollContainer.new()
	_opts_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_opts_scroll.follow_focus = true
	looks_row.add_child(_opts_scroll)
	_opts_box = VBoxContainer.new()
	_opts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opts_box.add_theme_constant_override("separation", 4)
	_opts_scroll.add_child(_opts_box)
	_thumb_box = VBoxContainer.new()
	_thumb_box.add_theme_constant_override("separation", 6)
	looks_row.add_child(_thumb_box)
	_thumb = LookPreview.new()
	_thumb_box.add_child(_thumb)
	_peek = Button.new()
	_peek.text = "See it in the shed"
	_peek.tooltip_text = "Hide this page and look at the shed with these choices (only you see them until it's bought)"
	_peek.pressed.connect(start_peek)
	_thumb_box.add_child(_peek)
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_status)
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(0, 48)
	_buy.pressed.connect(buy)
	detail.add_child(_buy)
	# Shown instead of the page while looking at the shed: a bar along the bottom, over the tool bar.
	var bottom := CenterContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -150.0
	bottom.offset_bottom = -70.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_peek_bar = PanelContainer.new()
	bottom.add_child(_peek_bar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	_peek_bar.add_child(bar)
	_peek_label = UITheme.label("", 17)
	_peek_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_peek_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_peek_label)
	var back_up := Button.new()
	back_up.text = "Back to the upgrades (Esc)"
	back_up.pressed.connect(stop_peek)
	bar.add_child(back_up)
	_peek_bar.visible = false
	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	Shed.changed.connect(func(): if visible: refresh())
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_end_preview())
	visible = false


func open() -> void:
	visible = true
	_status.text = ""
	_sig = ""
	_drafts.clear()
	_shown_id = ""
	refresh()
	if _rows.has(_pick):
		(_rows[_pick] as Button).grab_focus()


func close() -> void:
	visible = false
	_end_preview()


## Redraws the list when the garage's money, upgrades or their looks change.
func refresh() -> void:
	_money.text = "Garage: %s" % TvChannels.money_text(Shed.garage_money)
	var sig := "%d|%s|%s" % [Shed.garage_money, str(Shed.upgrades.keys()), str(Shed.looks)]
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
	elif GarageUpgrades.has_options(id):
		state = "pick colours"
	return "%s  ·  %s%s" % [GarageUpgrades.title(id), TvChannels.money_text(GarageUpgrades.price(id)), "  ·  " + state if state != "" else ""]


func show_upgrade(id: String) -> void:
	if not GarageUpgrades.exists(id):
		return
	if id != _shown_id:
		# A different upgrade: whatever was being tried on comes off the shed.
		_end_preview()
	_pick = id
	for key in _rows:
		(_rows[key] as Button).button_pressed = key == id
	var u: Dictionary = GarageUpgrades.CATALOGUE[id]
	_title.text = str(u["name"])
	_desc.text = str(u["desc"])
	var needs: Array = u["needs"]
	_spec.text = "Price: %s\nNeeds: %s" % [TvChannels.money_text(int(u["price"])),
		"nothing" if needs.is_empty() else ", ".join(needs.map(func(n): return GarageUpgrades.title(n) + (" (built)" if GarageUpgrades.owned(n) else "")))]
	if GarageUpgrades.has_options(id) and GarageUpgrades.owned(id):
		_spec.text += "\nNow: %s. Changing it costs %s." % [GarageUpgrades.looks_text(id, GarageUpgrades.looks_of(id, Shed.looks)),
			TvChannels.money_text(GarageUpgrades.restyle_fee(id))]
	if id != _shown_id:
		_shown_id = id
		_build_options(id)
	else:
		_mark_choices()
	_update_buy()


## The option groups for `id`: a row of colour swatches or named buttons for each.
func _build_options(id: String) -> void:
	for c in _opts_box.get_children():
		_opts_box.remove_child(c)
		c.queue_free()
	_swatches.clear()
	_opt_labels.clear()
	var has := GarageUpgrades.has_options(id)
	_thumb_box.visible = has
	_opts_scroll.visible = has
	if not has:
		return
	for g in GarageUpgrades.options(id):
		var key := str(g["key"])
		var head := UITheme.label("", 15, Color(1, 1, 1, 0.8))
		_opts_box.add_child(head)
		_opt_labels[key] = head
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 5)
		row.add_theme_constant_override("v_separation", 5)
		_opts_box.add_child(row)
		_swatches[key] = {}
		for c in g["choices"]:
			var b := Button.new()
			b.toggle_mode = true
			b.tooltip_text = str(c["name"])
			if str(g["kind"]) == "colour":
				_swatch_style(b, c.get("color", Color.WHITE))
				if (c.get("color", Color.WHITE) as Color).a <= 0.0:
					b.text = "none"
				if c.has("b") and c["b"] != c["color"]:
					# A two-colour chequer: its second colour on the lower right half.
					var half := ColorRect.new()
					half.color = c["b"]
					half.mouse_filter = Control.MOUSE_FILTER_IGNORE
					half.set_anchors_preset(Control.PRESET_FULL_RECT)
					half.anchor_left = 0.5
					half.anchor_top = 0.5
					half.offset_left = 0.0
					half.offset_top = 0.0
					half.offset_right = -4.0
					half.offset_bottom = -4.0
					b.add_child(half)
					var half2 := ColorRect.new()
					half2.color = c["b"]
					half2.mouse_filter = Control.MOUSE_FILTER_IGNORE
					half2.anchor_right = 0.5
					half2.anchor_bottom = 0.5
					half2.offset_left = 4.0
					half2.offset_top = 4.0
					b.add_child(half2)
			else:
				b.text = str(c["name"])
			b.pressed.connect(choose.bind(key, str(c["id"])))
			row.add_child(b)
			_swatches[key][str(c["id"])] = b
	_mark_choices()


## A square colour swatch, ringed when picked.
static func _swatch_style(b: Button, color: Color) -> void:
	b.custom_minimum_size = Vector2(34, 34)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color if color.a > 0.0 else Color(0.25, 0.25, 0.27)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 0, 0, 0.6)
		if state in ["pressed", "hover_pressed"]:
			sb.set_border_width_all(4)
			sb.border_color = UITheme.ACCENT
		elif state == "hover":
			sb.border_color = Color(1, 1, 1, 0.8)
		elif state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(1, 1, 1, 0.9)
		b.add_theme_stylebox_override(state, sb)


## The choices being picked for `id` (what's built, or the defaults).
func draft(id: String) -> Dictionary:
	if not _drafts.has(id):
		_drafts[id] = GarageUpgrades.looks_of(id, Shed.looks) if GarageUpgrades.owned(id) else GarageUpgrades.default_looks(id)
	return _drafts[id]


## Picks `choice` for option `key` of the upgrade shown, and tries it on.
func choose(key: String, choice: String) -> void:
	if not GarageUpgrades.has_options(_pick):
		return
	draft(_pick)[key] = choice
	_drafts[_pick] = GarageUpgrades.clean_looks(_pick, _drafts[_pick])
	_mark_choices()
	_start_preview()
	_update_buy()


## Shows which swatches are picked, names them, and redraws the preview room.
func _mark_choices() -> void:
	if not GarageUpgrades.has_options(_pick):
		return
	var chosen := draft(_pick)
	for g in GarageUpgrades.options(_pick):
		var key := str(g["key"])
		if not _swatches.has(key):
			continue
		for cid in _swatches[key]:
			(_swatches[key][cid] as Button).set_pressed_no_signal(str(chosen.get(key, "")) == cid)
		(_opt_labels[key] as Label).text = "%s: %s" % [g["name"], GarageUpgrades.choice(_pick, key, chosen).get("name", "")]
	var have := Shed.upgrades.duplicate()
	have[_pick] = true
	var looks := {}
	for id in have:
		looks[id] = chosen if id == _pick else GarageUpgrades.looks_of(str(id), Shed.looks)
	_thumb.show_looks(have, looks)
	if previewing:
		_start_preview()


func _update_buy() -> void:
	var id := _pick
	if GarageUpgrades.owned(id):
		if GarageUpgrades.has_options(id) and draft(id) != GarageUpgrades.looks_of(id, Shed.looks):
			var why := Shed.check(Shed.me(), {"a": "restyle_upgrade", "id": id, "looks": draft(id)})
			_buy.text = "Change it for %s" % TvChannels.money_text(GarageUpgrades.restyle_fee(id))
			_buy.disabled = why != ""
			_buy.tooltip_text = why
			if why != "":
				_status.text = why
		else:
			_buy.text = "Built" + ("  (pick new colours above to change it)" if GarageUpgrades.has_options(id) else "")
			_buy.disabled = true
			_buy.tooltip_text = ""
		return
	var why := Shed.check(Shed.me(), {"a": "buy_upgrade", "id": id})
	_buy.text = "Buy for %s" % TvChannels.money_text(GarageUpgrades.price(id))
	if GarageUpgrades.has_options(id):
		_buy.text += "  ·  " + GarageUpgrades.looks_text(id, draft(id))
	_buy.disabled = why != ""
	_buy.tooltip_text = why
	if why != "":
		_status.text = why


func pick(id: String) -> void:
	show_upgrade(id)
	_buy.grab_focus()


## Buys the upgrade being shown with the garage's money, in the looks picked, or changes the
## looks of one already built (the host checks it).
func buy() -> void:
	if _pick == "":
		return
	if GarageUpgrades.owned(_pick):
		if GarageUpgrades.has_options(_pick):
			Shed.request({"a": "restyle_upgrade", "id": _pick, "looks": draft(_pick).duplicate()})
	elif GarageUpgrades.has_options(_pick):
		Shed.request({"a": "buy_upgrade", "id": _pick, "looks": draft(_pick).duplicate()})
	else:
		Shed.request({"a": "buy_upgrade", "id": _pick})


## Tries the picked look on the real shed (this screen only).
func _start_preview() -> void:
	if not GarageUpgrades.has_options(_pick):
		return
	previewing = true
	WorkshopUpgrades.set_preview(get_tree(), _pick, draft(_pick))


## Puts the shed back as it is.
func _end_preview() -> void:
	if peeking:
		stop_peek()
	if previewing or WorkshopUpgrades.preview_id != "":
		previewing = false
		WorkshopUpgrades.set_preview(get_tree() if is_inside_tree() else null, "", {})


## Hides the page (and the parts computer behind it) to look at the shed with the picked look.
func start_peek() -> void:
	if not GarageUpgrades.has_options(_pick):
		return
	_start_preview()
	peeking = true
	_set_page_shown(false)
	_peek_label.text = "Trying out the %s: %s" % [GarageUpgrades.title(_pick).to_lower(), GarageUpgrades.looks_text(_pick, draft(_pick)).to_lower()]
	_peek_bar.visible = true
	(_peek_bar.get_child(0).get_child(1) as Button).grab_focus()


func stop_peek() -> void:
	peeking = false
	_peek_bar.visible = false
	_set_page_shown(true)
	if is_visible_in_tree():
		_peek.grab_focus()


func _set_page_shown(on: bool) -> void:
	_shade.visible = on
	_center.visible = on
	# The parts computer underneath: its shade and window.
	var pc := get_parent()
	if pc is Control and pc != get_tree().root:
		for i in mini(2, pc.get_child_count()):
			var c := pc.get_child(i)
			if c != self and c is CanvasItem:
				(c as CanvasItem).visible = on


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		if peeking:
			stop_peek()
		else:
			close()
		get_viewport().set_input_as_handled()
