class_name BikeShopTab
extends VBoxContainer
## The Esc menu's Bike shop tab (the Profile panel): buy a whole bike with your own money, second
## hand from today's list or new from the configurator (see BikeShop). The bike turns on a
## turntable beside the list or the choices, in the same photo studio as the parts computer's
## (drag it, zoom in, stop it turning: the tips under it say how), with its price and a button
## to buy it. The configurator has a colour beside each part, and a badge for the tank: a logo
## and a brand name, each in a colour of its own (BikeBadge).

## The configurator's text: small, to fit a whole bike's worth of choices on the screen.
const FONT := 13
const HEAD := 12

var mode := "used"
## The second-hand bike picked (an index into listings), and today's list.
var picked := 0
var listings: Array = []
## The new bike being configured: its style, parts, colours (a slot, or a group of
## BikeShop.COLOUR_GROUPS -> Color; a part left out comes in the factory's colour, the tank and
## fairing in `paint`) and badge ({logo, logo_color, brand, brand_color}, see BikeBadge).
var style := "cafe"
var parts := {}
var colours := {}
var paint := Color.RED
var badge := {}
var _used_btn: Button
var _new_btn: Button
var _left: VBoxContainer
var _preview: PartPreview
var _view_hint: Label
var _about: Label
var _buy: Button
var _status: Label


func _ready() -> void:
	name = "Bike shop"
	add_theme_constant_override("separation", 6)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	var group := ButtonGroup.new()
	_used_btn = _button("Second hand")
	_used_btn.toggle_mode = true
	_used_btn.button_group = group
	_used_btn.pressed.connect(func(): show_mode("used"))
	tabs.add_child(_used_btn)
	_new_btn = _button("New: configure your own")
	_new_btn.toggle_mode = true
	_new_btn.button_group = group
	_new_btn.pressed.connect(func(): show_mode("new"))
	tabs.add_child(_new_btn)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 2)
	scroll.add_child(_left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	_preview = PartPreview.new()
	_preview.use_studio()
	_preview.pad_view = true
	_preview.custom_minimum_size = Vector2(420, 320)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)
	_view_hint = UITheme.label("", 12, Color(1, 1, 1, 0.5))
	_view_hint.name = "ViewHint"
	_view_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_view_hint)
	_about = UITheme.label("", FONT)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_about)
	_buy = _button("")
	_buy.pressed.connect(_press_buy)
	right.add_child(_buy)
	_status = UITheme.label("", FONT, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	_new_style("cafe")
	visibility_changed.connect(func(): if is_visible_in_tree(): show_mode(mode))
	Progress.changed.connect(func(): if is_visible_in_tree(): _refresh())
	_show_view_hint()


func _process(_delta: float) -> void:
	# (The tips follow the device in use: the mouse's, or the controller's.)
	if is_visible_in_tree() and _view_hint.get_meta("pad", null) != Controls.using_pad:
		_show_view_hint()


## The tips under the turntable, for the mouse or the controller in use.
func _show_view_hint() -> void:
	_view_hint.set_meta("pad", Controls.using_pad)
	if Controls.using_pad:
		_view_hint.text = "Right stick: turn and tilt  ·  Triggers: zoom  ·  Click the right stick: stop or start turning"   # hint-ok: the controller on the turntable itself, not a binding
	else:
		_view_hint.text = "Drag: turn  ·  Scroll: zoom  ·  Right-click: stop or start turning  ·  Right-drag: look about  ·  Double-click: see it all"   # hint-ok: the mouse on the turntable itself, not a binding


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", FONT)
	return b


func _row_label(t: String, width := 118.0) -> Label:
	var l := UITheme.label(t, HEAD, Color(1, 1, 1, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = width
	return l


func _heading(t: String) -> Label:
	var l := UITheme.label(t, HEAD, UITheme.ACCENT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _option() -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.clip_text = true
	ob.add_theme_font_size_override("font_size", FONT)
	ob.get_popup().add_theme_font_size_override("font_size", FONT)
	return ob


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
			_left.add_child(UITheme.label("Sold out for today: more tomorrow.", FONT))
			_buy.disabled = true
			return
		picked = clampi(picked, 0, listings.size() - 1)
		_left.add_child(_heading("FOR SALE TODAY"))
		for i in listings.size():
			var l: Dictionary = listings[i]
			var b := _button("%s  ·  %s\n%s miles  ·  %s" % [str(l["title"]), TvChannels.money_text(_price_of(l)),
				_miles(int(l["miles"])), str(l["seller"])])
			b.name = "Listing%d" % i
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): pick(i))
			_left.add_child(b)
	else:
		_left.add_child(_heading("STYLE"))
		var st := _option()
		st.name = "Style"
		for s in PartsDB.STYLES:
			st.add_item(PartsDB.style_name(s))
		st.select(PartsDB.STYLES.find(style))
		# Deferred: rebuilding the list frees this very button, which mustn't happen while it is still
		# sending the signal (that crashed the game, v0.42.0).
		st.item_selected.connect(func(i): _new_style(PartsDB.STYLES[i]); show_mode("new"), CONNECT_DEFERRED)
		_left.add_child(st)
		_left.add_child(_heading("PARTS AND COLOURS"))
		for slot in BikeShop.CONFIG_SLOTS:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.add_child(_row_label(BikeShop.slot_label(slot)))
			var ob := _option()
			ob.name = "Slot_" + slot
			var opts := BikeShop.options(slot, style, parts)
			for id in opts:
				# How it goes on this bike (BikeRig.part_fit): the ones that won't fit greyed out
				# with why, the ones that need fabrication marked.
				var f := BikeRig.part_fit(parts, slot, str(id))
				var label := "None" if id == "none" else PartsDB.part_name(str(id))
				if str(f["tier"]) == BikeRig.TIER_FAB:
					label += "  (needs fabrication)"
				elif str(f["tier"]) == BikeRig.TIER_NO:
					label += "  (won't fit)"
				ob.add_item(label)
				var at := ob.item_count - 1
				ob.set_item_disabled(at, str(f["tier"]) == BikeRig.TIER_NO and str(id) != str(parts.get(slot, "none")))
				ob.set_item_tooltip(at, str(f["reason"]))
			ob.select(maxi(0, opts.find(str(parts.get(slot, "none")))))
			ob.item_selected.connect(func(i): set_part(slot, str(opts[i])), CONNECT_DEFERRED)   # (deferred, as Style)
			row.add_child(ob)
			_colour_cell(row, slot)
			_left.add_child(row)
		_badge_rows()
	_refresh()


## The colour beside part `slot` in `row`: its picker (none for an empty slot), and Reset once
## it's been changed from the factory's.
func _colour_cell(row: HBoxContainer, slot: String) -> void:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size.x = 84.0
	cell.add_theme_constant_override("separation", 2)
	row.add_child(cell)
	if BikeShop.colour_slots(slot, parts).is_empty():
		return
	var cp := ColourChoice.new()
	cp.name = "Colour_" + slot
	cp.tooltip_text = "The %s's colour" % BikeShop.slot_label(slot).to_lower()
	cp.color = colour_of(slot)
	cp.color_changed.connect(func(c): set_colour(slot, c))
	cell.add_child(cp)
	var reset := _button("Reset")
	reset.name = "Reset_" + slot
	reset.add_theme_font_size_override("font_size", 11)
	reset.tooltip_text = "Back to the colour it comes in"
	reset.visible = _changed(slot)
	reset.pressed.connect(func(): reset_colour(slot), CONNECT_DEFERRED)
	cell.add_child(reset)


## The badge: a logo and a brand name for the tank, each in a colour of its own.
func _badge_rows() -> void:
	_left.add_child(_heading("BADGE ON THE TANK"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_row_label("Logo"))
	var ob := _option()
	ob.name = "Logo"
	ob.add_theme_constant_override("icon_max_width", 18)
	ob.get_popup().add_theme_constant_override("icon_max_width", 22)
	ob.add_item("None")
	var ids: Array = [""]
	for id in BikeBadge.LOGOS:
		ob.add_icon_item(BikeBadge.texture(str(id)), str(BikeBadge.LOGOS[id]))
		ids.append(str(id))
	ob.select(maxi(0, ids.find(str(badge.get("logo", "")))))
	ob.item_selected.connect(func(i): set_logo(str(ids[i])))
	row.add_child(ob)
	var lc := ColourChoice.new()
	lc.name = "Colour_logo"
	lc.tooltip_text = "The logo's colour"
	lc.color = badge.get("logo_color", Color(0.92, 0.92, 0.9))
	lc.color_changed.connect(func(c): badge["logo_color"] = c; _refresh())
	var lcell := HBoxContainer.new()
	lcell.custom_minimum_size.x = 84.0
	lcell.add_child(lc)
	row.add_child(lcell)
	_left.add_child(row)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 4)
	brow.add_child(_row_label("Brand name"))
	var le := LineEdit.new()
	le.name = "Brand"
	le.max_length = BikeBadge.BRAND_MAX
	le.placeholder_text = "Your own make"
	le.text = str(badge.get("brand", ""))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", FONT)
	le.text_changed.connect(set_brand)
	brow.add_child(le)
	var bc := ColourChoice.new()
	bc.name = "Colour_brand"
	bc.tooltip_text = "The brand name's colour"
	bc.color = badge.get("brand_color", Color(0.92, 0.92, 0.9))
	bc.color_changed.connect(func(c): badge["brand_color"] = c; _refresh())
	var bcell := HBoxContainer.new()
	bcell.custom_minimum_size.x = 84.0
	bcell.add_child(bc)
	brow.add_child(bcell)
	_left.add_child(brow)


## Picks second-hand bike `i`.
func pick(i: int) -> void:
	picked = clampi(i, 0, listings.size() - 1)
	_status.text = ""
	_refresh()


## Starts a new bike of `s`: its stock build, in a colour of its own (its badge stays).
func _new_style(s: String) -> void:
	style = s
	parts = PartsDB.sanitize_build(Contracts.style_build(s).duplicate())
	paint = Shed.PAINTS[absi(hash(s)) % Shed.PAINTS.size()]
	colours = {}
	if _preview:
		_preview.reset_view()


## Puts part `id` in `slot` on the new bike (and sorts out the rest to fit).
func set_part(slot: String, id: String) -> void:
	parts[slot] = id
	parts = PartsDB.sanitize_build(parts)
	show_mode("new")


## The colour `slot` is in now: picked, or as it comes.
func colour_of(slot: String) -> Color:
	if colours.get(slot) is Color:
		return colours[slot]
	for g in BikeShop.COLOUR_GROUPS:
		if colours.get(g) is Color and BikeShop.colour_slots(g, parts).has(slot):
			return colours[g]
	return BikeShop.factory_colour(slot, parts, paint)


func _changed(slot: String) -> bool:
	return not colour_of(slot).is_equal_approx(BikeShop.factory_colour(slot, parts, paint))


## Colours `key` (a slot, or a group of BikeShop.COLOUR_GROUPS) `c`.
func set_colour(key: String, c: Color) -> void:
	if key == "tank":
		paint = c   # (the tank's colour is the bike's paint, the fairing's too unless it has its own)
	colours[key] = c
	if BikeShop.COLOUR_GROUPS.has(key):
		for slot in BikeShop.colour_slots(key, parts):
			colours.erase(slot)
	var cp := _left.find_child("Colour_" + key, true, false) as ColourChoice
	if cp and not cp.color.is_equal_approx(c):
		cp.color = c
	var reset := _left.find_child("Reset_" + key, true, false) as Button
	if reset:
		reset.visible = _changed(key)
	_refresh()


## Puts `slot` back in the colour it comes in.
func reset_colour(slot: String) -> void:
	colours.erase(slot)
	for g in BikeShop.COLOUR_GROUPS:
		if BikeShop.colour_slots(g, parts).has(slot):
			colours.erase(g)
	if slot == "tank":
		paint = Shed.PAINTS[absi(hash(style)) % Shed.PAINTS.size()]
	show_mode("new")


func set_logo(id: String) -> void:
	if id == "":
		badge.erase("logo")
	else:
		badge["logo"] = id
		if not (badge.get("logo_color") is Color):
			badge["logo_color"] = Color(0.92, 0.92, 0.9)
	_refresh()


func set_brand(t: String) -> void:
	badge["brand"] = t
	if not (badge.get("brand_color") is Color):
		badge["brand_color"] = Color(0.92, 0.92, 0.9)
	_refresh()


## Everything picked as the order takes it: each slot's colour, the tank's being the paint.
func _order_colours() -> Dictionary:
	var out := {}
	for key in colours:
		out[key] = colours[key]
	out["tank"] = paint
	return out


func _price_of(l: Dictionary) -> int:
	return BikeShop.price(BikeShop.src_of(str(l["title"]), l["parts"], l["paint"]), float(l["quality"]))


## The bike on show, as BikeCopy takes it.
func _src() -> Dictionary:
	if mode == "used":
		var l: Dictionary = listings[picked]
		return BikeShop.src_of(str(l["title"]), l["parts"], l["paint"])
	return BikeShop.src_of(PartsDB.style_name(style), parts, paint, _order_colours(), badge)


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
		cond[slot] = PartColours.clean(b["colors"][slot])
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
			"Built new in your colours and ready to ride. %s" % BikeRig.brief_text(b["parts"]),
			BikeShop.fab_text(b["parts"], style),
			"%s from your own money (you have %s)." % [TvChannels.money_text(cost), TvChannels.money_text(Progress.money())]]
		_buy.text = "Order it for %s" % TvChannels.money_text(cost)
	_about.text = "\n".join(lines.filter(func(t): return str(t) != ""))
	var why := Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": cost, "quality": q, "built": true})
	if why == "" and Progress.money() < cost:
		why = "You have %s: %s short." % [TvChannels.money_text(Progress.money()), TvChannels.money_text(cost - Progress.money())]
	_buy.disabled = why != ""
	_buy.tooltip_text = Controls.hint(why)


func _press_buy() -> void:
	var why := BikeShop.buy_used(listings[picked]) if mode == "used" else \
		BikeShop.buy_new(PartsDB.style_name(style), parts, paint, _order_colours(), badge)
	_status.text = Controls.hint(why)
	if why == "" and mode == "used":
		BikeShop.sold[str(listings[picked]["key"])] = true   # (gone from the list)
		show_mode("used")
