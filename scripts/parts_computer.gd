class_name PartsComputer
extends Control
## The shed's parts computer: browse every part by kind, read its spec and order it, or order
## equipment for the shed. Deliveries are left outside the roller door. Parts and project bikes
## are paid for from the business's account (see Money); the Sell aisle sells loose parts and
## whole bikes, the money going into the business.

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
## Posters come printed in several sizes (Equipment.POSTER_SIZES): the one picked, and its buttons.
var poster_size := Equipment.POSTER_SIZE_DEFAULT
var _sizes: HBoxContainer
var _size_btns := {}
var _bank: Label
var _bike_btn: Button
var _sell_shown := ""

## The Sell aisle's two lists.
const SELL_KINDS := ["sell:bikes", "sell:parts"]
## The Garage upgrades page (UpgradesPanel), opened from the button at the top.
var upgrades_panel: UpgradesPanel

## The shop's three aisles, so nobody scrolls through everything.
const SECTIONS := {"shed": "Shed", "bike": "Bike", "outdoors": "Outdoors", "sell": "Sell"}


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
	_bank = UITheme.label("", 17, Color(0.55, 0.95, 0.55))
	head.add_child(_bank)
	_bike_btn = Button.new()
	_bike_btn.text = "Order a project bike"
	_bike_btn.pressed.connect(func(): Shed.request({"a": "order"}))
	head.add_child(_bike_btn)
	# Blueprint builds under way (Esc, Blueprints): order whatever their holograms still show.
	var bp_btn := Button.new()
	bp_btn.text = "Order blueprint parts"
	bp_btn.tooltip_text = "Orders every part a blueprint build still needs, paid for by the business"
	bp_btn.pressed.connect(func(): Shed.request({"a": "bp_order"}))
	head.add_child(bp_btn)
	var up_btn := Button.new()
	up_btn.text = "Garage upgrades"
	up_btn.tooltip_text = "Spend the garage's money on more bays, storage and a smarter shed"
	up_btn.pressed.connect(open_upgrades)
	head.add_child(up_btn)
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
	_sizes = HBoxContainer.new()
	_sizes.add_theme_constant_override("separation", 6)
	_sizes.add_child(UITheme.label("Size:", 16))
	for key in Equipment.POSTER_SIZE_ORDER:
		var sb := Button.new()
		sb.text = str(Equipment.POSTER_SIZES[key]["name"])
		sb.toggle_mode = true
		sb.button_pressed = key == poster_size
		sb.pressed.connect(pick_poster_size.bind(key))
		_sizes.add_child(sb)
		_size_btns[key] = sb
	_sizes.visible = false
	detail.add_child(_sizes)
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	detail.add_child(_status)
	_order = Button.new()
	_order.text = "Order it"
	_order.custom_minimum_size = Vector2(0, 48)
	_order.pressed.connect(func():
		if _kind.begins_with("sell:"):
			sell(_part)
		elif design_of(_part) != 0:
			Shed.request({"a": "order_furniture", "model": Equipment.BOARD_POSTER, "design": design_of(_part), "psize": poster_size})
		elif Equipment.kind_of(_part) == "poster":
			Shed.request({"a": "order_furniture", "model": _part, "psize": poster_size})
		elif _kind.begins_with("eq:"):
			Shed.request({"a": "order_furniture", "model": _part})
		else:
			Shed.request({"a": "order_part", "part": _part}))
	detail.add_child(_order)

	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	# A poster made at the whiteboard while the list is up joins it.
	Shed.changed.connect(func():
		if not visible:
			return
		_refresh_bank()
		if _kind == "eq:poster" and _posters_shown != Shed.posters.size() and (_search == null or _search.text == ""):
			_show_kind(_kind)
		elif _kind.begins_with("sell:") and _sell_signature(_kind) != _sell_shown:
			_show_kind(_kind))
	_show_section(_section)
	upgrades_panel = UpgradesPanel.new()
	add_child(upgrades_panel)


## Opens the Garage upgrades page over the shop.
func open_upgrades() -> void:
	upgrades_panel.open()


## Which aisle a kind is sold in.
static func section_of(k: String) -> String:
	if k.begins_with("sell:"):
		return "sell"
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
	if k == "sell:bikes":
		return "Whole bikes"
	if k == "sell:parts":
		return "Loose parts"
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
	for k in all_kinds() + SELL_KINDS:
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
	_refresh_bank()
	if upgrades_panel:
		upgrades_panel.close()
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
	if k.begins_with("sell:"):
		_show_sellables(k)
		return
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


## Picks the size posters are printed in (a key of Equipment.POSTER_SIZES).
func pick_poster_size(key: String) -> void:
	poster_size = key
	for k in _size_btns:
		_size_btns[k].button_pressed = k == key
	if _part != "":
		_show_part(_part)


## "Size: A1, 0.60 x 0.84 m. Turn it with , and . before you hang it." for the poster being shown.
func _size_text(model: String) -> String:
	var art := Equipment.poster_size(model, poster_size)
	var keys := Walker._keys("rotate_left", "rotate_right")
	return "\n\nSize: %s, %.2f x %.2f m. Carrying it, %s turns it portrait or landscape before you hang it." % [
		str(Equipment.POSTER_SIZES[poster_size]["name"]), art.x, art.y, keys]


func _show_part(id: String) -> void:
	_part = id
	for b in _variants.get_children():
		if b.has_meta("part"):
			b.button_pressed = b.get_meta("part") == id
	_order.disabled = false
	if _kind.begins_with("sell:"):
		_sizes.visible = false
		_show_sale(id)
		return
	_order.text = "Order it"
	_sizes.visible = design_of(id) != 0 or Equipment.kind_of(id) == "poster"
	if design_of(id) != 0:
		var d: Dictionary = Shed.posters.get(design_of(id), {})
		var m := Equipment.get_model(Equipment.BOARD_POSTER)
		_title.text = str(d.get("name", "Whiteboard poster"))
		_desc.text = "%s Saved from the whiteboard by %s." % [m["desc"], str(d.get("by", "the crew"))]
		_spec.text = "Hangs on a wall." + _size_text(Equipment.BOARD_POSTER) \
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
		if m["kind"] == "poster":
			_spec.text = how + _size_text(id)
		return
	var p := PartsDB.get_part(id)
	_title.text = str(p["name"])
	_desc.text = str(p.get("description", ""))
	var cost := Money.buy_price(id, Shed.me())
	_order.text = "Order it: %s" % TvChannels.money_text(cost)
	_desc.text += "\n\n%s from the business's account%s." % [TvChannels.money_text(cost),
		" (Haggler discount)" if cost < Money.part_price(id) else ""]
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


# ---------------------------------------------------------------------------- money

## The business's balance in the header, and what a project bike goes for.
func _refresh_bank() -> void:
	if _bank == null:
		return
	_bank.text = "Business: %s  " % TvChannels.money_text(Shed.garage_money)
	_bike_btn.tooltip_text = "Around %s, paid by the business" % TvChannels.money_text(Money.typical_project_price())


## What the Sell aisle can sell now: "bike:<id>" for every bike nobody is riding, "item:<id>"
## for every loose part (on the floor, a bench or shelf, or in your hands).
static func sellables(k: String) -> Array:
	var out := []
	if k == "sell:bikes":
		for id in Shed.bikes:
			if int(Shed.bikes[id]["rider"]) == 0:
				out.append("bike:%d" % int(id))
	else:
		for id in Shed.items:
			var it: Dictionary = Shed.items[id]
			if it["at"] in ["spot", "floor"] or (it["at"] == "held" and int(it["ref"]) == Shed.me()):
				out.append("item:%d" % int(id))
	return out


func _sell_signature(k: String) -> String:
	return ",".join(sellables(k))


func _show_sellables(k: String) -> void:
	var keys := sellables(k)
	_sell_shown = ",".join(keys)
	_variants.add_child(UITheme.label("%d TO SELL" % keys.size(), 14, UITheme.ACCENT))
	if keys.is_empty():
		var none := UITheme.label("Nothing to sell here." if k == "sell:bikes" else
			"No loose parts. Take parts off a bike, or put them down in the shed, to sell them.", 14, Color(1, 1, 1, 0.5))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_variants.add_child(none)
		_title.text = kind_title(k)
		_desc.text = ""
		_spec.text = ""
		_order.text = "Sell it"
		_order.disabled = true
		_part = ""
		return
	for key in keys:
		var b := Button.new()
		b.text = "%s  ·  %s" % [_sale_name(key), TvChannels.money_text(sale_price(key))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_meta("part", key)
		b.pressed.connect(_pick_part.bind(key))
		b.focus_entered.connect(_show_part.bind(key))
		_variants.add_child(b)
	_show_part(keys[0])


static func _sale_name(key: String) -> String:
	var id := int(key.get_slice(":", 1))
	if key.begins_with("bike:"):
		return str(Shed.bikes.get(id, {}).get("name", "Bike"))
	return Shed.item_title(id) if Shed.items.has(id) else "Part"


## What a "bike:<id>" or "item:<id>" fetches if this player sells it.
static func sale_price(key: String) -> int:
	var id := int(key.get_slice(":", 1))
	return Money.bike_sale(id, Shed.me()) if key.begins_with("bike:") else Money.part_sale(id, Shed.me())


func _show_sale(key: String) -> void:
	var id := int(key.get_slice(":", 1))
	_title.text = _sale_name(key)
	var price := sale_price(key)
	_order.text = "Sell it: %s" % TvChannels.money_text(price)
	_order.disabled = price <= 0 and not key.begins_with("bike:")
	if key.begins_with("bike:"):
		var missing := Shed.missing_slots(id).size()
		var loose := Shed.loose_slots(id).size()
		var state := "Complete, fuelled and ready to ride: it fetches %d%% more." % roundi((Money.BONUS_COMPLETE + Money.BONUS_RIDEABLE) * 100.0) \
			if Money.rideable(id) else ("Complete, but needs petrol and oil to fetch the best price." if Shed.is_complete(id)
			else "%d part%s missing and %d loose: a complete bike fetches more." % [missing, "" if missing == 1 else "s", loose])
		_desc.text = "Sells the whole bike and every part on it. %s" % state
		_spec.text = "The money goes into the business's account. Bikes sold: XP for whoever sells it."
		return
	var it: Dictionary = Shed.items.get(id, {})
	var health := BikeBuild.part_health(Shed.condition_of(it)) if not it.is_empty() else 0.0
	_desc.text = "Condition %d%%. New, it costs %s; a dealer pays %d%% of what it's worth now, and worn parts are worth far less." % [
		roundi(health * 100.0), TvChannels.money_text(Money.part_price(str(it.get("part", "")))), roundi(Money.SELL_RATE * 100.0)]
	_spec.text = "The money goes into the business's account." + (" Whatever is fitted to it goes too." if Shed.is_engine(id) or Shed.tyre_on_wheel(id) != 0 else "")


## Sells a "bike:<id>" or "item:<id>" to the dealer, through the host.
func sell(key: String) -> void:
	if key == "":
		return
	var id := int(key.get_slice(":", 1))
	if key.begins_with("bike:"):
		Shed.request({"a": "money_sell_bike", "bike": id})
	else:
		Shed.request({"a": "money_sell_part", "item": id})
