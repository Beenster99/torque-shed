class_name HomePanel
extends Control
## A collection bike's card, opened with {interact} at its information stand (see HomeDisplay):
## the bike turning on a turntable and a breakdown of its numbers (power, torque, top speed,
## 0-60, weight, economy, condition, what it's worth) with the parts worth a look and whose it is.
## Its owner can ride it out from here, or sell it to the garage; anyone else can make the owner
## an offer for it out of their own money (or take an offer back). All of it goes through the
## host (see Collection).

signal closed

var cid := 0
var _box: VBoxContainer
var _preview: PartPreview
var _head: Label
var _sub: Label
var _grid: GridContainer
var _high: Label
var _slots: Label
var _status: Label
var _ride: Button
var _sell: Button
var _amount: SpinBox
var _offer: Button
var _withdraw: Button
var _offer_row: HBoxContainer
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("bike_order_panel")   # wide like the bike's card: the look-at panel stays out of its way
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	_head = UITheme.title("", 26)
	_box.add_child(_head)
	_sub = UITheme.label("", 16, Color(1, 1, 1, 0.75))
	_box.add_child(_sub)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	_box.add_child(cols)
	_preview = PartPreview.new()
	_preview.custom_minimum_size = Vector2(360, 300)
	cols.add_child(_preview)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(UITheme.label("THE NUMBERS", 15, UITheme.ACCENT))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	right.add_child(_grid)
	right.add_child(UITheme.label("WORTH A LOOK", 15, UITheme.ACCENT))
	_high = UITheme.label("", 14)
	_high.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_high)
	_slots = UITheme.label("", 15)
	_slots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_slots)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_ride = Button.new()
	_ride.text = "Ride it out"
	_ride.pressed.connect(_press_ride)
	row.add_child(_ride)
	_sell = Button.new()
	_sell.pressed.connect(_press_sell)
	row.add_child(_sell)
	_offer_row = HBoxContainer.new()
	_offer_row.add_theme_constant_override("separation", 8)
	row.add_child(_offer_row)
	_offer_row.add_child(UITheme.label("Offer £", 16))
	_amount = SpinBox.new()
	_amount.min_value = Collection.MIN_OFFER
	_amount.max_value = Progress.MAX_MONEY
	_amount.step = 1
	_amount.custom_arrow_step = 50
	_amount.custom_minimum_size.x = 140
	_amount.value_changed.connect(func(_v): _refresh())
	_offer_row.add_child(_amount)
	_offer = Button.new()
	_offer.pressed.connect(_press_offer)
	_offer_row.add_child(_offer)
	_withdraw = Button.new()
	_withdraw.pressed.connect(_press_withdraw)
	_offer_row.add_child(_withdraw)
	row.add_child(ContractPanel.button("Close ({back})", close_dialog))
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	Shed.homes_changed.connect(func(): if visible: _refresh())
	Progress.changed.connect(func(): if visible: _refresh())


## Opens the card for collection bike `id`.
func open_bike(id: int) -> void:
	cid = id
	_sig = ""
	_status.text = ""
	var e := Collection.entry(cid)
	if e.is_empty():
		return
	_amount.set_value_no_signal(maxf(Collection.MIN_OFFER, float(e.get("value", 0))))
	visible = true
	_refresh()
	var l := Collection.look(e.get("pack", {}))
	_preview.show_bike("home|%d|%s" % [cid, str(hash(e.get("pack", {}).get("bike", {}).get("slots", {})))], l["parts"], l["paint"], l["cond"])


func close_dialog() -> void:
	visible = false
	closed.emit()


func _mine() -> bool:
	return str(Collection.entry(cid).get("owner", "")) == Collection.name_of(Shed.me())


func amount() -> int:
	return roundi(_amount.value)


func set_amount(v: int) -> void:
	_amount.value = v


func _refresh() -> void:
	var e := Collection.entry(cid)
	if e.is_empty() or int(e.get("out", 0)) != 0 and not _mine():
		close_dialog()   # sold on, or out on the road
		return
	var me := Collection.name_of(Shed.me())
	var mine := _mine()
	var mine_offer := Collection.offer_from(me, cid)
	var ride_why := Shed.check(Shed.me(), {"a": "home_take", "bike": cid}) if mine else ""
	var sell_why := Shed.check(Shed.me(), {"a": "home_sell", "bike": cid}) if mine else ""
	var offer_why := ""
	if not mine:
		offer_why = Shed.check(Shed.me(), {"a": "home_offer", "bike": cid, "amount": amount(), "paid": amount()})
		if offer_why == "" and Progress.money() < amount():
			offer_why = "You have %s." % Collection.money(Progress.money())
	var sig := "%s|%s|%s|%s|%s|%d|%s|%d" % [str(e), ride_why, sell_why, offer_why, str(mine_offer), Progress.money(), str(Collection.level_of(Shed.me())), amount()]
	if sig == _sig:
		return
	_sig = sig
	var s := Collection.stats(cid)
	if mine:
		_head.text = "YOUR %s" % str(s["name"]).to_upper()
	else:
		_head.text = "%s'S %s" % [str(e["owner"]).to_upper(), str(s["name"]).to_upper()]
	_sub.text = "%s  ·  %s's collection" % [str(s["style"]), str(e["owner"])]
	for c in _grid.get_children():
		c.queue_free()
	for line in s["lines"]:
		var k := UITheme.label(str(line[0]), 15, Color(1, 1, 1, 0.55))
		var v := UITheme.label(str(line[1]), 15)
		_grid.add_child(k)
		_grid.add_child(v)
	_high.text = "\n".join(s["highlights"]) if not (s["highlights"] as Array).is_empty() else "A stock build."
	if mine:
		var have := Collection.count_of(me)
		var room := Collection.slots_of(Shed.me())
		_slots.text = "Your collection: %d of %d. %s" % [have, room, Collection._next_slot_text(Shed.me())]
	else:
		_slots.text = "Offer %s your own money for it: they say yes or no, and the money's held till they do." % str(e["owner"]) \
			if mine_offer.is_empty() else "You've offered %s %s for it. Waiting for an answer." % [str(e["owner"]), Collection.money(int(mine_offer["amount"]))]
	_ride.visible = mine
	_sell.visible = mine
	_offer_row.visible = not mine
	_ride.disabled = ride_why != ""
	_ride.tooltip_text = Controls.hint(ride_why)
	_sell.text = "Sell it to the garage for %s" % Collection.money(Collection.sell_price(cid))
	_sell.disabled = sell_why != ""
	_sell.tooltip_text = Controls.hint(sell_why if sell_why != "" else "%d%% of what it's worth, paid into your own money; the shed sells it on." % roundi(Collection.SELL_BACK * 100.0))
	_offer.text = "Offer %s" % Collection.money(amount())
	_offer.visible = mine_offer.is_empty()
	_offer.disabled = offer_why != ""
	_amount.editable = mine_offer.is_empty()
	_withdraw.visible = not mine_offer.is_empty()
	_withdraw.text = "Take my offer back" if not mine_offer.is_empty() else ""
	var why := ride_why if mine else offer_why
	_status.text = Controls.hint(why if mine_offer.is_empty() else "")


func _press_ride() -> void:
	Shed.request({"a": "home_take", "bike": cid})
	close_dialog()


func _press_sell() -> void:
	Shed.request({"a": "home_sell", "bike": cid})
	close_dialog()


func _press_offer() -> void:
	var said := Collection.make_offer(cid, amount())
	if said != "":
		_status.text = Controls.hint(said)
		return
	close_dialog()


func _press_withdraw() -> void:
	var o := Collection.offer_from(Collection.name_of(Shed.me()), cid)
	if not o.is_empty():
		Shed.request({"a": "home_withdraw", "offer": int(o["id"])})
	close_dialog()


## Presses the button whose text starts with `text` (for tests).
func press(text: String) -> void:
	for b in [_ride, _sell, _offer, _withdraw]:
		if (b as Button).visible and (b as Button).text.begins_with(text) and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return


## Everything the card says now (tests).
func text() -> String:
	var out := []
	for l in _box.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion() and (l as Label).is_visible_in_tree():
			out.append((l as Label).text)
	for b in [_ride, _sell, _offer, _withdraw]:
		if (b as Button).is_visible_in_tree():
			out.append("[%s]" % (b as Button).text)
	return "\n".join(out)
