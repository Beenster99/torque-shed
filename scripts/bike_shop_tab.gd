class_name BikeShopTab
extends VBoxContainer
## The Esc menu's Bike shop tab (the Profile panel): buy a whole bike with your own money, second
## hand from today's list or new from the configurator (see BikeShop). The bike turns on a
## turntable beside the list or the choices, with its price and a button to buy it.

var mode := "used"
## The second-hand bike picked (an index into listings), and today's list.
var picked := 0
var listings: Array = []
## The new bike being configured: its style, parts and colours ({paint, frame, wheels} -> Color).
var style := "cafe"
var parts := {}
var colours := {}
var _used_btn: Button
var _new_btn: Button
var _left: VBoxContainer
var _preview: PartPreview
var _about: Label
var _buy: Button
var _status: Label


func _ready() -> void:
	name = "Bike shop"
	add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	var group := ButtonGroup.new()
	_used_btn = Button.new()
	_used_btn.text = "Second hand"
	_used_btn.toggle_mode = true
	_used_btn.button_group = group
	_used_btn.pressed.connect(func(): show_mode("used"))
	tabs.add_child(_used_btn)
	_new_btn = Button.new()
	_new_btn.text = "New: configure your own"
	_new_btn.toggle_mode = true
	_new_btn.button_group = group
	_new_btn.pressed.connect(func(): show_mode("new"))
	tabs.add_child(_new_btn)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 4)
	scroll.add_child(_left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	_preview = PartPreview.new()
	_preview.custom_minimum_size = Vector2(360, 260)
	right.add_child(_preview)
	_about = UITheme.label("", 15)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_about)
	_buy = Button.new()
	_buy.pressed.connect(_press_buy)
	right.add_child(_buy)
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	_new_style("cafe")
	visibility_changed.connect(func(): if is_visible_in_tree(): show_mode(mode))
	Progress.changed.connect(func(): if is_visible_in_tree(): _refresh())


## Shows the second-hand list ("used") or the configurator ("new").
func show_mode(m: String) -> void:
	mode = m
	_used_btn.set_pressed_no_signal(m == "used")
	_new_btn.set_pressed_no_signal(m == "new")
	_status.text = ""
	for c in _left.get_children():
		c.free()
	if m == "used":
		listings = BikeShop.for_sale().filter(func(l): return not BikeShop.sold.has(str(l["key"])))
		if listings.is_empty():
			_left.add_child(UITheme.label("Sold out for today: more tomorrow.", 15))
			_buy.disabled = true
			return
		picked = clampi(picked, 0, listings.size() - 1)
		_left.add_child(UITheme.label("FOR SALE TODAY", 14, UITheme.ACCENT))
		for i in listings.size():
			var l: Dictionary = listings[i]
			var b := Button.new()
			b.name = "Listing%d" % i
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "%s  ·  %s\n%s miles  ·  %s" % [str(l["title"]), TvChannels.money_text(_price_of(l)),
				_miles(int(l["miles"])), str(l["seller"])]
			b.pressed.connect(func(): pick(i))
			_left.add_child(b)
	else:
		_left.add_child(UITheme.label("STYLE", 14, UITheme.ACCENT))
		var st := OptionButton.new()
		st.name = "Style"
		for s in PartsDB.STYLES:
			st.add_item(PartsDB.style_name(s))
		st.select(PartsDB.STYLES.find(style))
		st.item_selected.connect(func(i): _new_style(PartsDB.STYLES[i]); show_mode("new"))
		_left.add_child(st)
		_left.add_child(UITheme.label("PARTS", 14, UITheme.ACCENT))
		for slot in BikeShop.CONFIG_SLOTS:
			var row := HBoxContainer.new()
			var l := UITheme.label(PartsDB.slot_name(slot), 14, Color(1, 1, 1, 0.6))
			l.custom_minimum_size.x = 110.0
			row.add_child(l)
			var ob := OptionButton.new()
			ob.name = "Slot_" + slot
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.clip_text = true
			var opts := BikeShop.options(slot, style, parts)
			for id in opts:
				ob.add_item("None" if id == "none" else PartsDB.part_name(str(id)))
			ob.select(maxi(0, opts.find(str(parts.get(slot, "none")))))
			ob.item_selected.connect(func(i): set_part(slot, str(opts[i])))
			row.add_child(ob)
			_left.add_child(row)
		_left.add_child(UITheme.label("COLOURS", 14, UITheme.ACCENT))
		for key in BikeShop.COLOUR_PARTS:
			var row := HBoxContainer.new()
			var l := UITheme.label(str(BikeShop.COLOUR_PARTS[key]), 14, Color(1, 1, 1, 0.6))
			l.custom_minimum_size.x = 180.0
			row.add_child(l)
			var cp := ColorPickerButton.new()
			cp.name = "Colour_" + key
			cp.custom_minimum_size = Vector2(80, 28)
			cp.edit_alpha = false
			cp.color = colours[key]
			cp.color_changed.connect(func(c): set_colour(key, c))
			row.add_child(cp)
			_left.add_child(row)
	_refresh()


## Picks second-hand bike `i`.
func pick(i: int) -> void:
	picked = clampi(i, 0, listings.size() - 1)
	_status.text = ""
	_refresh()


## Starts a new bike of `s`: its stock build, in a colour of its own.
func _new_style(s: String) -> void:
	style = s
	parts = PartsDB.sanitize_build(Contracts.style_build(s).duplicate())
	var paint: Color = Shed.PAINTS[absi(hash(s)) % Shed.PAINTS.size()]
	colours = {"paint": paint, "frame": Color(0.08, 0.08, 0.09), "wheels": Color(0.1, 0.1, 0.11)}


## Puts part `id` in `slot` on the new bike (and sorts out the rest to fit).
func set_part(slot: String, id: String) -> void:
	parts[slot] = id
	parts = PartsDB.sanitize_build(parts)
	show_mode("new")


func set_colour(key: String, c: Color) -> void:
	colours[key] = c
	_refresh()


func _price_of(l: Dictionary) -> int:
	return BikeShop.price(BikeShop.src_of(str(l["title"]), l["parts"], l["paint"]), float(l["quality"]))


## The bike on show, as BikeCopy takes it.
func _src() -> Dictionary:
	if mode == "used":
		var l: Dictionary = listings[picked]
		return BikeShop.src_of(str(l["title"]), l["parts"], l["paint"])
	return BikeShop.src_of(PartsDB.style_name(style), parts, colours["paint"], colours)


func _quality() -> float:
	return float(listings[picked]["quality"]) if mode == "used" else 1.0


static func _miles(m: int) -> String:
	var s := str(m)
	return s.left(s.length() - 3) + "," + s.right(3) if m >= 1000 else s


func _refresh() -> void:
	if mode == "used" and listings.is_empty():
		return
	var src := _src()
	var q := _quality()
	var cost := BikeShop.price(src, q)
	var b: Dictionary = src["build"]
	var cond := {}
	for slot in b["colors"]:
		cond[slot] = {"color": b["colors"][slot]["color"]}
	_preview.show_bike("shop|%s|%s|%s" % [mode, str(b["parts"].hash()), str(b["colors"].hash())], b["parts"], b["paint"], cond)
	var hp := roundi(BikeBuild.new(b["parts"], {}).hp())
	var lines := []
	if mode == "used":
		var l: Dictionary = listings[picked]
		lines = ["%s, %s miles" % [str(l["title"]), _miles(int(l["miles"]))], "Sold by %s." % str(l["seller"]),
			"%s  ·  %d hp" % [BikeCopy.quality_text(q), hp], "Comes built and ready to ride, as it is.",
			"%s from your own money (you have %s)." % [TvChannels.money_text(cost), TvChannels.money_text(Progress.money())]]
		_buy.text = "Buy it for %s" % TvChannels.money_text(cost)
	else:
		lines = ["A new %s  ·  %s  ·  %d hp" % [PartsDB.style_name(style).to_lower(), Sales.model_text(b["parts"]), hp],
			"Built new in your colours and ready to ride.",
			"%s from your own money (you have %s)." % [TvChannels.money_text(cost), TvChannels.money_text(Progress.money())]]
		_buy.text = "Order it for %s" % TvChannels.money_text(cost)
	_about.text = "\n".join(lines)
	var why := Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": cost, "quality": q, "built": true})
	if why == "" and Progress.money() < cost:
		why = "You have %s: %s short." % [TvChannels.money_text(Progress.money()), TvChannels.money_text(cost - Progress.money())]
	_buy.disabled = why != ""
	_buy.tooltip_text = Controls.hint(why)


func _press_buy() -> void:
	var why := BikeShop.buy_used(listings[picked]) if mode == "used" else BikeShop.buy_new(PartsDB.style_name(style), parts, colours["paint"], colours)
	_status.text = Controls.hint(why)
	if why == "" and mode == "used":
		BikeShop.sold[str(listings[picked]["key"])] = true   # (gone from the list)
		show_mode("used")
