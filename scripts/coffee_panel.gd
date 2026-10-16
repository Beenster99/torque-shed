class_name CoffeePanel
extends Control
## The coffee shop's two cards (see CoffeeShop):
##   - The counter's menu: coffee, tea, cake and sandwiches, each bought from your own money onto
##     the tray you carry (what's on it so far is shown).
##   - Talking to a biker about their bike: a line of chat, the bike's basics, and a price to
##     offer for it from the business's account. They almost always say no.

signal closed

var visitor_id := 0
## What the offer box says (kept while the card refreshes).
var offer_amount := 0
var _box: VBoxContainer
var _sig := ""
var _amount_box: SpinBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("coffee_panel")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	Shed.changed.connect(func(): if visible: _refresh())
	Progress.changed.connect(func(): if visible: _refresh())


## The counter's menu.
func open_menu() -> void:
	visitor_id = 0
	_sig = ""
	visible = true
	_refresh()


## Talking to visitor `id` about their bike.
func open_visitor(id: int) -> void:
	if visitor_id != id:
		offer_amount = CoffeeShop.rough_value(CoffeeShop.visitors().get(id, {}))
	visitor_id = id
	_sig = ""
	visible = true
	_refresh()


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
		if not b.is_queued_for_deletion():
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
	var v: Dictionary = CoffeeShop.visitors().get(visitor_id, {})
	if visitor_id != 0 and not CoffeeShop.here(v) and str(v.get("state", "")) != "sold":
		close_dialog()   # they've gone
		return
	var tray := CoffeeShop.tray_of(Shed.me())
	var sig := "%d|%s|%s|%s|%s|%d|%s|%d" % [visitor_id, str(v.get("said", "")), str(v.get("state", "")), str(v.get("offers", 0)),
		str(tray.get("items", [])), Progress.money(), str(CoffeeShop.is_open()), Shed.garage_money]
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	if visitor_id != 0:
		_fill_visitor(v)
	else:
		_fill_menu(tray)


func _fill_menu(tray: Dictionary) -> void:
	_box.add_child(UITheme.title("PIT STOP CAFE", 26))
	_box.add_child(UITheme.label("%s  ·  You have %s" % [CoffeeShop.hours_text(), CoffeeShop.money(Progress.money())], 16, UITheme.ACCENT))
	for item in CoffeeShop.MENU_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := UITheme.label("%s  ·  %s" % [CoffeeShop.item_name(item), CoffeeShop.money(CoffeeShop.price(item))], 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var why := Shed.check(Shed.me(), {"a": "coffee_buy", "item": item, "paid": CoffeeShop.price(item)})
		if why == "" and Progress.money() < CoffeeShop.price(item):
			why = "Not enough money."
		var b := ContractPanel.button("Buy %s" % CoffeeShop.item_name(item).to_lower(), func():
			var said := CoffeeShop.buy(item)
			if said != "":
				Shed.feedback.emit(said, false)
			else:
				Sfx.play_at("pickup", CoffeeShop.ORDER_SPOT + Vector3.UP, -6.0)
			_sig = "")
		b.disabled = why != ""
		b.tooltip_text = why
		row.add_child(b)
		_box.add_child(row)
	var blocked := Shed.check(Shed.me(), {"a": "coffee_buy", "item": "tea", "paid": CoffeeShop.price("tea")})
	if blocked != "" and not blocked.begins_with("Your tray"):
		_box.add_child(UITheme.label(blocked, 15, Color(1, 0.5, 0.4)))
	var items: Array = tray.get("items", [])
	if tray.is_empty():
		_box.add_child(UITheme.label("It comes on a tray: carry it back to the shed, put it down on anything flat (left mouse) "
			+ "and have it with the right mouse button.", 14, Color(1, 1, 1, 0.6)))
	else:
		_box.add_child(UITheme.label("On your tray: %s (%d of %d)" % [CoffeeShop.items_text(items), items.size(), CoffeeShop.TRAY_MAX], 16))
	_box.add_child(ContractPanel.button("Done (Esc)", close_dialog))


func _fill_visitor(v: Dictionary) -> void:
	_box.add_child(UITheme.title(str(v.get("name", "")).to_upper(), 26))
	var said := str(v.get("said", ""))
	_box.add_child(UITheme.label("\"%s\"" % (said if said != "" else str(v.get("chat", ""))), 16, Color(1, 1, 1, 0.75)))
	_box.add_child(UITheme.label("THEIR BIKE", 15, UITheme.ACCENT))
	_box.add_child(UITheme.label(CoffeeShop.bike_line(v), 16))
	var b: Dictionary = v.get("bike", {})
	_box.add_child(UITheme.label("%s km on it." % CoffeeShop.money(int(b.get("km", 0))).trim_prefix(TvChannels.CURRENCY), 14,
		Color(1, 1, 1, 0.6)))
	if str(v.get("state", "")) == "sold":
		_box.add_child(UITheme.label("It's the shed's now, parked outside the cafe.", 16, Color(0.5, 0.95, 0.55)))
		_box.add_child(ContractPanel.button("Done (Esc)", close_dialog))
		return
	_box.add_child(UITheme.label("MAKE AN OFFER", 15, UITheme.ACCENT))
	_box.add_child(UITheme.label("From the business account (%s). Bikers hardly ever sell: offering over the odds helps a "
		% CoffeeShop.money(Shed.garage_money) + "little, never a lot. They'll hear you out %d times at most." % CoffeeShop.MAX_OFFERS,
		14, Color(1, 1, 1, 0.6)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_amount_box = SpinBox.new()
	_amount_box.min_value = 0
	_amount_box.max_value = CoffeeShop.MAX_OFFER
	_amount_box.step = 50
	_amount_box.rounded = true
	_amount_box.prefix = TvChannels.CURRENCY
	_amount_box.custom_minimum_size = Vector2(170, 0)
	_amount_box.select_all_on_focus = true
	_amount_box.value = offer_amount
	_amount_box.value_changed.connect(func(x): offer_amount = int(x))
	row.add_child(_amount_box)
	var why := Shed.check(Shed.me(), {"a": "coffee_offer", "visitor": visitor_id, "amount": maxi(offer_amount, 1)})
	var offer := ContractPanel.button("Offer", func():
		Shed.request({"a": "coffee_offer", "visitor": visitor_id, "amount": offer_amount})
		_sig = "")
	offer.disabled = why != "" or offer_amount <= 0
	row.add_child(offer)
	row.add_child(ContractPanel.button("Leave it (Esc)", close_dialog))
	_box.add_child(row)
	if why != "":
		_box.add_child(UITheme.label(why, 15, Color(1, 0.5, 0.4)))
