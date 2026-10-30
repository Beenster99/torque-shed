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
var _paint_shown := ""

## The Sell aisle's two lists.
const SELL_KINDS := ["sell:bikes", "sell:parts"]
## The mixing bay's supplies (PaintBay), in the Shed aisle: tins of base, and bottles of tint.
const PAINT_KINDS := ["paint:bases", "paint:tints"]
## The Garage upgrades page (UpgradesPanel), opened from the button at the top.
var upgrades_panel: UpgradesPanel
## The project bike order, with its condition slider (opened by the order button).
var bike_card: ProjectOrderCard

## The shop's three aisles, so nobody scrolls through everything.
const SECTIONS := {"shed": "Shed", "bike": "Bike", "outdoors": "Outdoors", "sell": "Sell"}
## Within an aisle the kinds come under headings, in this order. A kind that isn't listed here
## (something new in the catalogue) goes under "Other" at the end of its aisle, so it's never lost.
const GROUPS := [
	["Engine and drivetrain", ["engine", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "cooling", "gearbox",
		"exhaust", "ecu", "final_drive", "chain"]],
	["Chassis", ["frame", "fork", "shock", "swingarm", "steering_damper", "handlebars", "lever_guards", "rearsets", "guards", "side_stand", "centre_stand"]],
	["Wheels and brakes", ["wheel", "tyre", "disc", "caliper", "pads", "master"]],
	["Body and lights", ["tank", "saddle", "front_mudguard", "tail", "fairing", "mirrors", "dashboard", "headlight",
		"fog_lights", "horn", "indicators", "side_panels", "number_boards"]],
	["Luggage and adventure kit", ["panniers", "top_box", "tank_bag", "aux_tank", "toolbox", "satnav"]],
	["Fluids", ["petrol", "oil", "brake_fluid", "chain_lube"]],
	["Tools and machines", ["eq:stand", "eq:washer", "eq:repair", "eq:blaster", "eq:booth", "eq:changer"]],
	["Storage and benches", ["eq:shelf", "eq:bench", "eq:trolley"]],
	["Comfort and decor", ["eq:seat", "eq:tv", "eq:poster"]],
	["Paint mixing bay", ["paint:bases", "paint:tints"]],
	["Jumps", ["eq:ramp", "eq:obstacle"]],
	["Course", ["eq:barrier", "eq:marker"]],
	["Sell to the dealer", ["sell:bikes", "sell:parts"]],
]
## How a list can be sorted: key -> what the picker says.
const SORTS := {"shop": "Shop order", "price_up": "Price: low to high", "price_down": "Price: high to low",
	"name": "Name: A to Z", "light": "Lightest first"}

## The list's sort (a key of SORTS), the bike parts must fit (0 for any), and whether only parts
## the business can pay for are shown. Kept while the computer is closed.
var sort_key := "shop"
var fits_bike := 0
var affordable_only := false
## Only parts tagged with this style (see PartsDB.STYLES), or "" for any. Kinds with no
## styles at all (engines, brake pads) aren't filtered.
var style_filter := ""
var _style_pick: OptionButton
var _sort_pick: OptionButton
var _bike_pick: OptionButton
var _afford_box: CheckBox
var _bike_ids: Array = []    # bike id for each entry in the bike picker after "Any bike"
## The 3D turntable over the part picked (see PartPreview).
var preview: PartPreview
## The style of project bike to order ("" for any old project bike), and its picker.
var bike_style := ""
var _bike_style_pick: OptionButton


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
	panel.custom_minimum_size = Vector2(1080, 760)
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
	# One line: wrapped in this row it was squeezed to a word per line, which made the header
	# hundreds of pixels tall and pushed the bottom of every list off the screen.
	_bank.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_bank)
	# A project bike: any old one, or one built in a style ("make me a cruiser").
	_bike_style_pick = OptionButton.new()
	_bike_style_pick.tooltip_text = "Pick a style to have a project bike of that style found for you"
	_bike_style_pick.add_item("Any style")
	for st in PartsDB.STYLES:
		_bike_style_pick.add_item(PartsDB.style_name(st))
	_bike_style_pick.item_selected.connect(func(i): set_bike_style("" if i == 0 else PartsDB.STYLES[i - 1]))
	head.add_child(_bike_style_pick)
	_bike_btn = Button.new()
	_bike_btn.text = "Order a project bike"
	_bike_btn.pressed.connect(open_bike_order)
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
	Controls.bind_text(close, "Close ({back})")
	close.pressed.connect(close_computer)
	head.add_child(close)
	root.add_child(head)
	root.add_child(UITheme.label("Pick a kind of part, then a model. Sort and filter the list below. Orders arrive in boxes outside the roller door.", 15, Color(1, 1, 1, 0.6)))

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

	# Sorting and filters for the list of models.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.add_child(_cell("Sort:", 15, Color(1, 1, 1, 0.7), false))
	_sort_pick = OptionButton.new()
	for key in SORTS:
		_sort_pick.add_item(SORTS[key])
	_sort_pick.custom_minimum_size = Vector2(200, 0)
	_sort_pick.item_selected.connect(func(i): set_sort(SORTS.keys()[i]))
	tools.add_child(_sort_pick)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(16, 0)
	tools.add_child(gap2)
	tools.add_child(_cell("Fits:", 15, Color(1, 1, 1, 0.7), false))
	_bike_pick = OptionButton.new()
	_bike_pick.custom_minimum_size = Vector2(240, 0)
	_bike_pick.tooltip_text = "Only show parts that go on this bike as it is now"
	_bike_pick.item_selected.connect(func(i): set_fits_bike(0 if i == 0 else int(_bike_ids[i - 1])))
	tools.add_child(_bike_pick)
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(16, 0)
	tools.add_child(gap3)
	_afford_box = CheckBox.new()
	_afford_box.text = "Within budget"
	_afford_box.tooltip_text = "Only show parts the business's account can pay for now"
	_afford_box.toggled.connect(func(on): set_affordable_only(on))
	tools.add_child(_afford_box)
	var gap4 := Control.new()
	gap4.custom_minimum_size = Vector2(16, 0)
	tools.add_child(gap4)
	tools.add_child(_cell("Style:", 15, Color(1, 1, 1, 0.7), false))
	_style_pick = OptionButton.new()
	_style_pick.custom_minimum_size = Vector2(170, 0)
	_style_pick.tooltip_text = "Only show parts that suit this style of bike"
	_style_pick.add_item("Any style")
	for st in PartsDB.STYLES:
		_style_pick.add_item(PartsDB.style_name(st))
	_style_pick.item_selected.connect(func(i): set_style_filter("" if i == 0 else PartsDB.STYLES[i - 1]))
	tools.add_child(_style_pick)
	root.add_child(tools)
	_fill_bike_pick()

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	_kinds = _column(cols, 220)
	_variants = _column(cols, 360)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	cols.add_child(detail)
	_title = UITheme.title("", 24, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	# The part picked, turning in 3D (drag it to turn it yourself).
	preview = PartPreview.new()
	detail.add_child(preview)
	# The words under it scroll, so a long description never pushes the page off the screen.
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(info_scroll)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 10)
	info_scroll.add_child(info)
	_desc = UITheme.label("", 17)
	info.add_child(_desc)
	_spec = UITheme.label("", 16, UITheme.ACCENT)
	info.add_child(_spec)
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
		elif _kind.begins_with("paint:"):
			Shed.request({"a": "paint_buy", "code": _part, "n": 1})
		elif design_of(_part) != 0:
			Shed.request({"a": "order_furniture", "model": Equipment.BOARD_POSTER, "design": design_of(_part), "psize": poster_size})
		elif Equipment.kind_of(_part) == "poster":
			Shed.request({"a": "order_furniture", "model": _part, "psize": poster_size})
		elif _kind.begins_with("eq:"):
			Shed.request({"a": "order_furniture", "model": _part})
		else:
			Shed.request({"a": "order_part", "part": _part}))
	detail.add_child(_order)

	Shed.feedback.connect(func(text, _ok): if visible: _status.text = Controls.hint(text))
	# A poster made at the whiteboard while the list is up joins it.
	Shed.changed.connect(func():
		if not visible:
			return
		_refresh_bank()
		if _kind == "eq:poster" and _posters_shown != Shed.posters.size() and (_search == null or _search.text == ""):
			_show_kind(_kind)
		elif _kind.begins_with("paint:") and str(PaintBay.stock()) != _paint_shown:
			_show_kind(_kind)
		elif _kind.begins_with("sell:") and _sell_signature(_kind) != _sell_shown:
			_show_kind(_kind)
		elif fits_bike != 0 and not Shed.bikes.has(fits_bike):
			# The bike the list was filtered for has gone (sold, or delivered back).
			_fill_bike_pick()
			set_fits_bike(0))
	_show_section(_section)
	upgrades_panel = UpgradesPanel.new()
	add_child(upgrades_panel)
	bike_card = ProjectOrderCard.new()
	add_child(bike_card)


## Opens the Garage upgrades page over the shop.
func open_upgrades() -> void:
	upgrades_panel.open()


## Which aisle a kind is sold in.
static func section_of(k: String) -> String:
	if k.begins_with("sell:"):
		return "sell"
	if k.begins_with("paint:"):
		return "shed"
	if k.begins_with("eq:"):
		return "outdoors" if Equipment.YARD_KINDS.has(k.trim_prefix("eq:")) else "shed"
	return "bike"


## Every kind the shop sells, in shop order.
static func all_kinds() -> Array:
	var kinds: Array = []
	for k in Equipment.KINDS:
		if not Equipment.FIXED_KINDS.has(k):
			kinds.append("eq:" + k)
	kinds.append_array(PAINT_KINDS)
	kinds.append_array(PartsDB.FLUID_KINDS)
	kinds.append_array(PartsDB.KINDS)
	return kinds


## An aisle's kinds under their headings: [[heading, [kinds...]], ...], in the order they're
## listed. Kinds the headings don't name go under "Other" at the end.
static func groups_of(sec: String) -> Array:
	var sold: Array = (all_kinds() + SELL_KINDS).filter(func(k): return section_of(str(k)) == sec)
	var out := []
	var placed := []
	for g in GROUPS:
		var ks: Array = (g[1] as Array).filter(func(k): return sold.has(k))
		if not ks.is_empty():
			out.append([str(g[0]), ks])
			placed.append_array(ks)
	var rest: Array = sold.filter(func(k): return not placed.has(k))
	if not rest.is_empty():
		out.append(["Other", rest])
	return out


## The heading a kind is listed under.
static func group_of(k: String) -> String:
	for g in groups_of(section_of(k)):
		if (g[1] as Array).has(k):
			return str(g[0])
	return ""


static func kind_title(k: String) -> String:
	if k == "sell:bikes":
		return "Whole bikes"
	if k == "sell:parts":
		return "Loose parts"
	if k == "paint:bases":
		return "Paint bases"
	if k == "paint:tints":
		return "Tints and effects"
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
	for g in groups_of(sec):
		var head := UITheme.label(str(g[0]).to_upper(), 13, UITheme.ACCENT)
		if _kinds.get_child_count() > 0:
			head.custom_minimum_size = Vector2(0, 26)
			head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_kinds.add_child(head)
		for k in g[1]:
			if first == "":
				first = k
			var b := Button.new()
			# Fluids sit under their own heading, so they don't need "Fluids:" in front.
			b.text = kind_title(k).trim_prefix("Fluids: ")
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
		var k := str(hit["kind"])
		var id := str(hit["id"])
		var b := _row(id, str(hit["name"]), price_text(k, id), "%s  ·  %s" % [kind_title(k).trim_prefix("Fluids: "), key_spec(k, id)])
		b.pressed.connect(func(): _pick_found(k, id); _order.grab_focus())
		_variants.add_child(b)
	if not found.is_empty():
		_pick_found(found[0]["kind"], found[0]["id"])


func _pick_found(k: String, id: String) -> void:
	_kind = k
	for b in _kinds.get_children():
		if b is Button:
			b.button_pressed = b.get_meta("kind", "") == k
	_show_part(id)


## One model in the list: its name and price on top, a line of what matters about it below.
## The button carries the model's id as its "part" meta.
func _row(id: String, title: String, price: String, sub: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.set_meta("part", id)
	b.tooltip_text = title
	b.custom_minimum_size = Vector2(0, 50)
	b.clip_contents = true
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 4
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_l := _cell(title, 16, Color.WHITE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	if price != "":
		top.add_child(_cell(price, 16, Color(0.55, 0.95, 0.55), false))
	box.add_child(_cell(sub, 13, Color(1, 1, 1, 0.55)))
	return b


## A one-line label: never wrapped (in a row it would be squeezed to a letter per line). With
## `trim` it can be cut short with "..." to fit; without, it always shows in full.
func _cell(text: String, font_size: int, color: Color, trim := true) -> Label:
	var l := UITheme.label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if trim:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## What a model costs this player, for its row ("" for shed kit, which comes free).
static func price_text(k: String, id: String) -> String:
	if k.begins_with("eq:") or design_of(id) != 0:
		return ""
	return TvChannels.money_text(Money.buy_price(id, Shed.me()))


## The first couple of things that matter about a model, for its row.
static func key_spec(k: String, id: String) -> String:
	var line := Equipment.spec_line(id) if k.begins_with("eq:") else PartsDB.spec_line(id)
	var bits := line.split("  ·  ", false)
	var out: Array = Array(bits).slice(0, 2)
	if not k.begins_with("eq:") and PartsDB.is_lightweight(id):
		out.append("light")
	elif k.begins_with("eq:") and Equipment.get_model(id).get("compact", false):
		out.append("compact")
	var have := owned(id)
	if have > 0:
		out.append("%d in the shed" % have)
	return "  ·  ".join(out)


## How many of a part the shed has loose (on a bench, shelf, the floor, still boxed...), not
## fitted to anything.
static func owned(id: String) -> int:
	var n := 0
	for it in Shed.items.values():
		if str(it.get("part", "")) == id and not str(it.get("at", "")) in ["bike", "engine", "wheel"]:
			n += 1
	return n


## Whether a part goes on a bike as it is now: "" if it does, else why not. Tyres have to suit
## one of its wheels, wheels one of its tyres, a fairing needs a headlight and fairing mirrors a
## fairing; everything else bolts on any bike.
static func fit_problem(id: String, bike_id: int) -> String:
	if not Shed.bikes.has(bike_id) or PartsDB.get_part(id).is_empty():
		return ""
	var on := func(slot: String) -> String:
		var item := Shed.item_on(bike_id, slot)
		return str(Shed.items[item]["part"]) if item != 0 and Shed.items.has(item) else "none"
	match PartsDB.kind_of(id):
		"tyre":
			var wheels: Array = ["front_wheel", "rear_wheel"].map(func(s): return on.call(s)).filter(func(w): return w != "none")
			if wheels.is_empty() or wheels.any(func(w): return PartsDB.tyre_fit(id, w) == 0):
				return ""
			return PartsDB.tyre_fit_reason(id, wheels[0])
		"wheel":
			var tyres: Array = ["front_tyre", "rear_tyre"].map(func(s): return on.call(s)).filter(func(t): return t != "none")
			if tyres.is_empty() or tyres.any(func(t): return PartsDB.tyre_fit(t, id) == 0):
				return ""
			return "Neither of its tyres goes on this wheel: it would need new rubber too."
	# Mounts every bike ends up with (frame, fork, bars...) don't count, only the extras a bike
	# may never have: the headlight under a fairing, the fairing under fairing mirrors.
	for slot in PartsDB.slots_for_kind(PartsDB.kind_of(id)):
		for m in PartsDB.part_mounts(slot, id):
			if not PartsDB.is_optional(str(m)):
				continue
			if on.call(str(m)) == "none":
				return "It needs a %s on the bike first." % PartsDB.slot_name(str(m)).to_lower()
		break
	return ""


## Everything in the shop whose name, kind or description matches every word typed.
static func search(q: String) -> Array:
	var words := q.to_lower().split(" ", false)
	var out: Array = []
	for k in all_kinds():
		if str(k).begins_with("paint:"):
			continue   # the mixing bay's supplies aren't parts
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
	if bike_card:
		bike_card.close()
	_status.text = "Room in the delivery area: %s" % ("no, bring some boxes in first" if Shed.delivery_place(Vector3(0.25, 0.15, 0.25)).is_empty() else "yes")
	_fill_bike_pick()
	if not Shed.bikes.has(fits_bike):
		fits_bike = 0
	if _kind == "eq:poster" or fits_bike != 0 or affordable_only:
		_show_kind(_kind)   # whiteboard prints made since it was last open, or what the filters let through now
	_focus_kind()


## Puts the pad's focus on the kind being shown (or the first one), so A works straight away.
func _focus_kind() -> void:
	var first: Control = null
	for b in _kinds.get_children():
		if b.is_queued_for_deletion() or not b is Button:
			continue
		if first == null:
			first = b
		if b.get_meta("kind", "") == _kind:
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
		if b is Button:
			b.button_pressed = b.get_meta("kind", "") == k
			if b.button_pressed and not b.is_queued_for_deletion():
				# Under its heading, the kind picked (by a search, say) may be scrolled out of view.
				var scroll := _kinds.get_parent() as ScrollContainer
				(func():
					if is_instance_valid(b) and b.is_inside_tree() and not b.is_queued_for_deletion():
						scroll.ensure_control_visible(b)).call_deferred()
	for c in _variants.get_children():
		c.queue_free()
	if k.begins_with("sell:"):
		_show_sellables(k)
		return
	if k.begins_with("paint:"):
		_show_paint_supplies(k)
		return
	var all_ids: Array = Equipment.by_kind(k.trim_prefix("eq:")) if k.begins_with("eq:") else PartsDB.by_kind[k]
	var ids := listed(k)
	var group := ""
	var head := "%d MODELS" % all_ids.size()
	if ids.size() < all_ids.size():
		head = "%d OF %d SHOWN" % [ids.size(), all_ids.size()]
	var filters := []
	if fits_bike != 0 and Shed.bikes.has(fits_bike) and not k.begins_with("eq:"):
		filters.append("fit %s" % str(Shed.bikes[fits_bike]["name"]))
	if affordable_only and not k.begins_with("eq:"):
		filters.append("within budget")
	if style_filter != "" and styled_kind(k):
		filters.append("suit %s" % PartsDB.style_phrase(style_filter))
	if not filters.is_empty():
		head += ": " + " and ".join(filters).to_upper()
	var count := UITheme.label(head, 13, Color(1, 1, 1, 0.55))
	_variants.add_child(count)
	for id in ids:
		if k == "engine" and sort_key == "shop" and str(PartsDB.get_part(id).get("type", "")) != group:
			# Engines come in families: a heading over each layout's sizes.
			group = str(PartsDB.get_part(id).get("type", ""))
			_variants.add_child(UITheme.label(group.to_upper(), 14, UITheme.ACCENT))
		if k == "wheel" and sort_key == "shop" and wheel_group(id) != group:
			# Wheels by rim size, smallest first: a heading over each diameter.
			group = wheel_group(id)
			_variants.add_child(UITheme.label(group, 14, UITheme.ACCENT))
		var title := str(Equipment.get_model(id)["name"]) if k.begins_with("eq:") else PartsDB.part_name(id)
		var b := _row(id, title, price_text(k, id), key_spec(k, id))
		b.pressed.connect(_pick_part.bind(id))
		b.focus_entered.connect(_show_part.bind(id))
		_variants.add_child(b)
	if ids.is_empty():
		var none := UITheme.label("Nothing here %s. Change the filters above to see the rest." % " and ".join(filters), 14, Color(1, 1, 1, 0.5))
		_variants.add_child(none)
	_posters_shown = Shed.posters.size()
	if k == "eq:poster":
		# The crew's own whiteboard drawings, saved as posters at the board.
		_variants.add_child(UITheme.label("FROM THE WHITEBOARD", 14, UITheme.ACCENT))
		if Shed.posters.is_empty():
			var none := UITheme.label("None yet: press {board_poster} at the whiteboard to make one.", 14, Color(1, 1, 1, 0.5))
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
	if ids.is_empty():
		_show_nothing(kind_title(k))
	else:
		_show_part(ids[0] if not ids.has(_part) else _part)


## The heading wheel `id` is listed under in shop order: its rim size, as "17\" WHEELS".
static func wheel_group(id: String) -> String:
	return "%s WHEELS" % PartsDB.inch_text(float(PartsDB.get_part(id).get("diameter", 17.0)))


## The models of a kind the list shows, filtered and in the order picked (see sort_key,
## fits_bike and affordable_only). Shed kit is only sorted.
func listed(k: String) -> Array:
	var ids: Array = (Equipment.by_kind(k.trim_prefix("eq:")) if k.begins_with("eq:") else PartsDB.by_kind[k]).duplicate()
	var eq := k.begins_with("eq:")
	if not eq:
		if fits_bike != 0 and Shed.bikes.has(fits_bike):
			ids = ids.filter(func(id): return fit_problem(str(id), fits_bike) == "")
		if affordable_only:
			ids = ids.filter(func(id): return Money.buy_price(str(id), Shed.me()) <= Shed.garage_money)
		if style_filter != "" and styled_kind(k):
			ids = ids.filter(func(id): return PartsDB.styles_of(str(id)).has(style_filter))
	var name_of := func(id) -> String:
		return str(Equipment.get_model(str(id))["name"]) if eq else PartsDB.part_name(str(id))
	match sort_key:
		"name":
			ids.sort_custom(func(a, b): return name_of.call(a).naturalnocasecmp_to(name_of.call(b)) < 0)
		"price_up", "price_down":
			if not eq:
				var up := sort_key == "price_up"
				ids.sort_custom(func(a, b):
					var pa := Money.part_price(str(a))
					var pb := Money.part_price(str(b))
					if pa == pb:
						return name_of.call(a).naturalnocasecmp_to(name_of.call(b)) < 0
					return pa < pb if up else pa > pb)
		"light":
			if not eq:
				ids.sort_custom(func(a, b):
					return float(PartsDB.get_part(str(a)).get("mass", 0.0)) < float(PartsDB.get_part(str(b)).get("mass", 0.0)))
		_:
			if k == "engine":
				var order := ["Single", "Twin", "Parallel twin", "V-twin", "Boxer twin", "Inline triple", "Inline four", "Two-stroke"]
				ids.sort_custom(func(a, b):
					var pa := PartsDB.get_part(a)
					var pb := PartsDB.get_part(b)
					var ta := order.find(str(pa.get("type", "")))
					var tb := order.find(str(pb.get("type", "")))
					return ta < tb if ta != tb else float(pa["displacement"]) < float(pb["displacement"]))
	return ids


## Sorts every list by a key of SORTS.
func set_sort(key: String) -> void:
	if not SORTS.has(key):
		return
	sort_key = key
	if _sort_pick and _sort_pick.selected != SORTS.keys().find(key):
		_sort_pick.select(SORTS.keys().find(key))
	_relist()


## Shows only parts that go on this bike (0 for any bike).
func set_fits_bike(bike_id: int) -> void:
	fits_bike = bike_id if Shed.bikes.has(bike_id) else 0
	if _bike_pick:
		var i := 0 if fits_bike == 0 else _bike_ids.find(fits_bike) + 1
		if _bike_pick.selected != i and i < _bike_pick.item_count:
			_bike_pick.select(i)
	_relist()


## Shows only parts that suit a style of bike ("" for any).
func set_style_filter(style: String) -> void:
	style_filter = style if PartsDB.STYLES.has(style) else ""
	if _style_pick:
		var i := 0 if style_filter == "" else PartsDB.STYLES.find(style_filter) + 1
		if _style_pick.selected != i:
			_style_pick.select(i)
	_relist()


## Whether a kind's parts are tagged with styles, so the style filter means something for it.
static func styled_kind(k: String) -> bool:
	return not k.begins_with("eq:") and not k.begins_with("sell:") and PartsDB.by_kind.get(k, []).any(func(id): return not PartsDB.styles_of(str(id)).is_empty())


## Shows only parts the business can pay for now.
func set_affordable_only(on: bool) -> void:
	affordable_only = on
	if _afford_box and _afford_box.button_pressed != on:
		_afford_box.set_pressed_no_signal(on)
	_relist()


## The bikes in the shed in the Fits picker, after "Any bike".
func _fill_bike_pick() -> void:
	if _bike_pick == null:
		return
	_bike_pick.clear()
	_bike_pick.add_item("Any bike")
	_bike_ids = Shed.bikes.keys()
	_bike_ids.sort()
	for id in _bike_ids:
		_bike_pick.add_item(str(Shed.bikes[id]["name"]))
	_bike_pick.select(0 if fits_bike == 0 or not _bike_ids.has(fits_bike) else _bike_ids.find(fits_bike) + 1)


## Shows the list again after a sort or filter change, keeping the search if there is one.
func _relist() -> void:
	if _variants == null or _kind.begins_with("sell:") or _kind.begins_with("paint:"):
		return
	if _search and _search.text.strip_edges() != "":
		_refresh_list()
	else:
		_show_kind(_kind)


## An empty detail pane, for a list with nothing in it.
func _show_nothing(title: String) -> void:
	_part = ""
	_title.text = title
	_desc.text = ""
	_spec.text = ""
	_sizes.visible = false
	if preview:
		preview.clear()
	_order.text = "Order it"
	_order.disabled = true


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
	var keys := "{rotate_left|rotate_right}"   # read as keys when shown (see _show_part)
	return "\n\nSize: %s, %.2f x %.2f m. Carrying it, %s turns it portrait or landscape before you hang it." % [
		str(Equipment.POSTER_SIZES[poster_size]["name"]), art.x, art.y, keys]


## Shows a part's details; their key hints follow the device in use (see Controls.bind_text).
func _show_part(id: String) -> void:
	_fill_part(id)
	Controls.bind_text(_desc, _desc.text)
	Controls.bind_text(_spec, _spec.text)


func _fill_part(id: String) -> void:
	_part = id
	for b in _variants.get_children():
		if b.has_meta("part"):
			b.button_pressed = b.get_meta("part") == id
	_order.disabled = false
	if _kind.begins_with("sell:"):
		_sizes.visible = false
		_show_sale(id)
		return
	if _kind.begins_with("paint:"):
		_sizes.visible = false
		_show_supply(id)
		return
	if preview:
		if _kind.begins_with("eq:") or design_of(id) != 0:
			preview.clear()
		else:
			preview.show_part(id)
	_order.text = "Order it"
	_sizes.visible = design_of(id) != 0 or Equipment.kind_of(id) == "poster"
	if design_of(id) != 0:
		var d: Dictionary = Shed.posters.get(design_of(id), {})
		var m := Equipment.get_model(Equipment.BOARD_POSTER)
		_title.text = str(d.get("name", "Whiteboard poster"))
		_desc.text = "%s Saved from the whiteboard by %s." % [m["desc"], str(d.get("by", "the crew"))]
		_spec.text = "Hangs on a wall." + _size_text(Equipment.BOARD_POSTER) \
			+ "\n\nArrives outside the roller door. Press {interact} on it to carry it in, look at a wall and press {interact} to hang it."
		return
	if _kind.begins_with("eq:"):
		var m := Equipment.get_model(id)
		_title.text = str(m["name"])
		_desc.text = str(m["desc"])
		var how := "Left in the yard by the drag strip. Press {interact} on it to push it, {interact} again to put it down." if Equipment.is_yard(id) else \
			"Arrives outside the roller door. Press {interact} on it to carry it in, look at a wall and press {interact} to hang it." \
			if Equipment.is_wall(id) else ("Arrives outside the roller door. Hold {interact} on it to move it." if m["kind"] == "seat"
			else "Arrives outside the roller door. Press {interact} on it to push it in and {interact} again to put it down.")
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
		_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\nHold it, crouch by a bike's chain and hold {work} to lube it." \
			+ " A dry chain wastes power and wears out.\nDelivered outside, no box to unpack."
		return
	if PartsDB.FLUID_KINDS.has(_kind):
		var into: String = {"petrol": "the fuel tank", "oil": "the engine", "brake_fluid": "the front and rear brake master cylinders"}[_kind]
		var how := "Hold it and aim at %s: {work} pours it in, {work2} drains into it." % into
		if p.get("empty", false):
			how = "Hold it and aim at %s, then hold {work2} to drain into it. Tip it out in the scrap bin." % into
		_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\n" + how + "\nDelivered outside, no box to unpack."
		return
	var fits := PartsDB.slots_for_kind(_kind).map(func(s): return PartsDB.slot_name(s).to_lower())
	_spec.text = PartsDB.spec_line(id).replace("  ·  ", "\n") + "\n\nFits: " + ", ".join(fits)
	if fits_bike != 0 and Shed.bikes.has(fits_bike):
		var why := fit_problem(id, fits_bike)
		_spec.text += "\n%s: %s" % [str(Shed.bikes[fits_bike]["name"]), "goes on it as it is" if why == "" else why]
		var slots := PartsDB.slots_for_kind(_kind)
		if not PartsDB.styles_of(id).is_empty() and not slots.is_empty():
			var now := Contracts.current_parts(fits_bike)
			var with := now.duplicate()
			with[slots[0]] = id
			_spec.text += "\nIts style now: %s. With this on: %s." % [PartsDB.style_text(now), PartsDB.style_text(with)]
	if owned(id) > 0:
		_desc.text += " The shed has %d already, not fitted to anything." % owned(id)
	if _kind == "chain":
		_spec.text += "\n\nCrouch by the bike with the wrench and hold {work2} to set the tension. Lube it with chain lube."


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
	if bike_style == "":
		_bike_btn.text = "Order a project bike"
		_bike_btn.tooltip_text = "Around %s as they come, paid by the business: pick the condition, worn to new" % TvChannels.money_text(Money.typical_project_price())
	else:
		_bike_btn.text = "Order %s" % PartsDB.style_phrase(bike_style)
		_bike_btn.tooltip_text = "A project bike built as %s, found to order: around %s as they come, paid by the business: pick the condition, worn to new" % [
			PartsDB.style_phrase(bike_style), TvChannels.money_text(Money.typical_style_price(bike_style))]


## Picks the style of project bike the order button gets ("" for any project bike).
func set_bike_style(style: String) -> void:
	bike_style = style if PartsDB.STYLES.has(style) else ""
	if _bike_style_pick:
		var i := 0 if bike_style == "" else PartsDB.STYLES.find(bike_style) + 1
		if _bike_style_pick.selected != i:
			_bike_style_pick.select(i)
	_refresh_bank()


## Opens the project bike order (ProjectOrderCard) for the style picked: its condition slider and
## what one goes for.
func open_bike_order() -> void:
	bike_card.open(bike_style)


## Orders a project bike, in the style picked if there is one, at `quality` (0 worn .. 1 new; as
## they come when it's below 0). It turns up in a free bay.
func order_bike(quality := -1.0) -> void:
	Shed.request(bike_order(bike_style, quality))


## The host request for a project bike of `style` ("" for any) at `quality` (below 0: as they come).
static func bike_order(style: String, quality := -1.0) -> Dictionary:
	var action := {"a": "order"}
	if style != "":
		action["style"] = style
	if quality >= 0.0:
		action["quality"] = quality
	return action


## The mixing bay's supplies of a kind: "paint:bases" or "paint:tints" (PaintBay.supplies).
static func paint_supplies(k: String) -> Array:
	return PaintBay.supplies().filter(func(c): return PaintMix.BASES.has(str(c)) == (k == "paint:bases"))


func _show_paint_supplies(k: String) -> void:
	var codes := paint_supplies(k)
	_paint_shown = str(PaintBay.stock())
	_variants.add_child(UITheme.label("FOR THE MIXING BAY, FROM THE GARAGE'S MONEY", 13, Color(1, 1, 1, 0.55)))
	for code in codes:
		var c := str(code)
		var lock := PaintBay.locked(Shed.me(), c)
		var sub := "In the bay: %s%s" % [PaintBay.stock_text(c), "  ·  needs %s" % lock.to_lower() if lock != "" else ""]
		var b := _row(c, PaintBay.item_name(c), TvChannels.money_text(PaintBay.price(c)), sub)
		b.pressed.connect(_pick_part.bind(c))
		b.focus_entered.connect(_show_part.bind(c))
		_variants.add_child(b)
	_show_part(codes[0] if not codes.has(_part) else _part)


## One of the mixing bay's supplies in the detail pane.
func _show_supply(code: String) -> void:
	if preview:
		preview.clear()
	_title.text = PaintBay.item_name(code)
	var base := PaintMix.BASES.has(code)
	var what := "A 1 litre tin of %s, for the mixing bench." % PaintBay.item_name(code).to_lower() if base else \
		"A %d g bottle of %s for the tint rack over the mixing bench." % [roundi(PaintMix.BOTTLE_G), PaintBay.item_name(code).to_lower()]
	var lock := PaintBay.locked(Shed.me(), code)
	_desc.text = "%s\n\n%s from the business's account. It goes straight onto the bay's shelves." % [what, TvChannels.money_text(PaintBay.price(code))]
	_spec.text = "In the bay now: %s%s" % [PaintBay.stock_text(code), "\nYou can't use it yet: it needs %s." % lock.to_lower() if lock != "" else ""]
	_order.text = "Order it: %s" % TvChannels.money_text(PaintBay.price(code))
	_order.disabled = false


## What the Sell aisle can sell now: "bike:<id>" for every bike standing on a showroom display
## stand (bikes are only sold from there: see Sales), "item:<id>" for every loose part (on the
## floor, a bench or shelf, or in your hands).
static func sellables(k: String) -> Array:
	var out := []
	if k == "sell:bikes":
		for id in Shed.bikes:
			if int(Shed.bikes[id]["rider"]) == 0 and Shed.showroom_spot_of(int(id)) >= 0 and not Sales.is_customer_bike(int(id)):
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
		var none := UITheme.label("Bikes are sold from the showroom: stand one on a display stand in the sales office. "
			+ "The office PC upstairs prices it for buyers; it can be sold to the trade from here." if k == "sell:bikes" else
			"No loose parts. Take parts off a bike, or put them down in the shed, to sell them.", 14, Color(1, 1, 1, 0.5))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_variants.add_child(none)
		_title.text = kind_title(k)
		_desc.text = ""
		_spec.text = ""
		_order.text = "Sell it"
		_order.disabled = true
		_part = ""
		if preview:
			preview.clear()
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
	if preview:
		if key.begins_with("item:"):
			preview.show_item(id)
		else:
			preview.clear()
	if key.begins_with("bike:"):
		var missing := Shed.missing_slots(id).size()
		var loose := Shed.loose_slots(id).size()
		var state := "Complete, fuelled and ready to ride: it fetches %d%% more." % roundi((Money.BONUS_COMPLETE + Money.BONUS_RIDEABLE) * 100.0) \
			if Money.rideable(id) else ("Complete, but needs petrol and oil to fetch the best price." if Shed.is_complete(id)
			else "%d part%s missing and %d loose: a complete bike fetches more." % [missing, "" if missing == 1 else "s", loose])
		_desc.text = "Sells the whole bike to the trade, off its display stand, with every part on it. %s" % state
		_spec.text = "The money goes into the business's account. Private buyers pay more: price it at the sales office PC. Bikes sold: XP for whoever sells it." \
			+ "\n\nPaint, panel by panel:\n" + BikePaintInfo.text(id)
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
