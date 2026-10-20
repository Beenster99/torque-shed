class_name MoneyTab
extends ScrollContainer
## The Esc menu's Money tab: your own cash and the business's account, sending money to a mate
## or to the business, taking money out of the business (the garage owner only), the garage's
## settings (the host only: the business's cut of wages, who owns it and how hard the running
## costs bite), the running costs (tonight's bill line by line, the last one, any overdraft),
## bank loans and the business's ledger, and graphs of both over in-game time (minutes up to years, see
## MoneyGraph). Everything goes through Money and the host.

var _box: VBoxContainer
var _summary: Label
var _status: Label
var _send_to: OptionButton
var _send_amount: SpinBox
var _send: Button
var _take_amount: SpinBox
var _take: Button
var _cut: SpinBox
var _owner: OptionButton
var _settings_note: Label
var _costs: OptionButton
var _bills: VBoxContainer
var _bills_shown := ""
var _bills_timer := 0.0
var _loans: VBoxContainer
var _ledger: VBoxContainer
var _mine: VBoxContainer
var _shown := ""
var _crew_shown := ""
var _filling := false
var _graph_buttons := {}     # range key -> its Button
var _graph_mine: MoneyGraph.View
var _graph_garage: MoneyGraph.View
var _graph_timer := 0.0


func _ready() -> void:
	name = "Money"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	_box.add_child(UITheme.title("Money", 26))
	_summary = UITheme.label("", 16, UITheme.ACCENT)
	_box.add_child(_summary)
	_status = UITheme.label("", 15, Color(1, 0.85, 0.7))
	_box.add_child(_status)
	Shed.feedback.connect(func(text: String, _ok: bool):
		if is_visible_in_tree():
			_status.text = text)

	_box.add_child(UITheme.title("Money over time", 20))
	var range_row := _row()
	range_row.add_child(_row_label("Show it by"))
	var group := ButtonGroup.new()
	for key in MoneyGraph.ORDER:
		var k: String = key
		var b := _button(str(MoneyGraph.RANGES[k]["name"]), func(): set_graph_range(k))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == Settings.money_graph_range
		_graph_buttons[k] = b
		range_row.add_child(b)
	# The two graphs one above the other, each the full width of the tab.
	var graphs := VBoxContainer.new()
	graphs.add_theme_constant_override("separation", 8)
	_box.add_child(graphs)
	_graph_mine = MoneyGraph.View.new()
	graphs.add_child(_graph_mine)
	_graph_garage = MoneyGraph.View.new()
	graphs.add_child(_graph_garage)
	_box.add_child(UITheme.label("In-game time: a day lasts as long as the day and night cycle makes it. The money TV channels use the same choice.", 13,
		Color(1, 1, 1, 0.55)))

	_box.add_child(UITheme.title("Send money", 20))
	_box.add_child(UITheme.label("From your own cash, to a mate or to the business. Anyone can pay the business.", 14,
		Color(1, 1, 1, 0.6)))
	var send_row := _row()
	_send_to = OptionButton.new()
	_send_to.custom_minimum_size.x = 220.0
	send_row.add_child(_send_to)
	_send_amount = _amount_box()
	send_row.add_child(_send_amount)
	_send = _button("Send", func(): send_money(_send_target(), int(_send_amount.value)))
	send_row.add_child(_send)

	_box.add_child(UITheme.title("Take money out of the business", 20))
	_box.add_child(UITheme.label("Only the garage owner can take money out, into their own cash.", 14, Color(1, 1, 1, 0.6)))
	var take_row := _row()
	_take_amount = _amount_box()
	take_row.add_child(_take_amount)
	_take = _button("Take out", func(): withdraw(int(_take_amount.value)))
	take_row.add_child(_take)

	_box.add_child(UITheme.title("Garage settings", 20))
	_settings_note = UITheme.label("", 14, Color(1, 1, 1, 0.6))
	_box.add_child(_settings_note)
	var cut_row := _row()
	cut_row.add_child(_row_label("The business's cut of every wage"))
	_cut = SpinBox.new()
	_cut.min_value = 0
	_cut.max_value = 100
	_cut.step = 1
	_cut.suffix = "%"
	_cut.value_changed.connect(func(v):
		if not _filling:
			Shed.request({"a": "money_settings", "cut": int(v)}))
	cut_row.add_child(_cut)
	var owner_row := _row()
	owner_row.add_child(_row_label("Garage owner"))
	_owner = OptionButton.new()
	_owner.custom_minimum_size.x = 220.0
	_owner.item_selected.connect(func(i):
		if not _filling:
			Shed.request({"a": "money_settings", "owner": _owner.get_item_text(i)}))
	owner_row.add_child(_owner)
	var costs_row := _row()
	costs_row.add_child(_row_label("Running costs"))
	_costs = OptionButton.new()
	_costs.custom_minimum_size.x = 160.0
	for mode in Money.COSTS_MODES:
		_costs.add_item(str(Money.COSTS_NAMES[mode]))
	_costs.item_selected.connect(func(i):
		if not _filling:
			set_costs(Money.COSTS_MODES[i]))
	costs_row.add_child(_costs)

	_box.add_child(UITheme.title("Running costs", 20))
	_box.add_child(UITheme.label("Every in-game midnight the business pays its bills: rent and business rates (more for every extension), insurance (more for more bikes and stock), power and water (the lights and machines used that day) and workshop consumables (rags, gloves, cleaner: a little for every job done). A bill it can't cover puts it overdrawn: income pays that back first, and it costs %.1f%% a day until then." % (Money.OVERDRAFT_RATE * 100.0), 14, Color(1, 1, 1, 0.6)))
	_bills = VBoxContainer.new()
	_bills.add_theme_constant_override("separation", 4)
	_box.add_child(_bills)

	_box.add_child(UITheme.title("Bank loans", 20))
	_box.add_child(UITheme.label("The bank takes a repayment from the business every in-game day (at midnight), with interest on what's owed. Pay more off any time. Miss one and there's a fee, and no new loans until that one is paid off.", 14, Color(1, 1, 1, 0.6)))
	_loans = VBoxContainer.new()
	_loans.add_theme_constant_override("separation", 6)
	_box.add_child(_loans)

	_box.add_child(UITheme.title("The business's ledger", 20))
	_ledger = VBoxContainer.new()
	_box.add_child(_ledger)
	_box.add_child(UITheme.title("Your own money", 20))
	_mine = VBoxContainer.new()
	_box.add_child(_mine)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_graph_timer -= delta
	if _graph_timer <= 0.0:
		_graph_timer = 0.5
		refresh_graphs()
	_bills_timer -= delta
	if _bills_timer <= 0.0:
		_bills_timer = 1.0
		refresh_bills()
	var crew_names := _crew_signature()
	if crew_names != _crew_shown:
		_crew_shown = crew_names
		_fill_choices()
	var sig := "%d|%d|%s|%s|%d|%s" % [Progress.money(), Shed.garage_money, var_to_str(Shed.bank.get("loans", [])),
		str(Shed.bank.get("ledger", []).size()) + str(Shed.bank.get("ledger", []).back() if not Shed.bank.get("ledger", []).is_empty() else ""),
		int(Shed.bank.get("cut", 0)), str(Shed.bank.get("owner", "")) + str(Progress.profile.get("cash_log", []).size())
		+ str(Shed.bank.get("costs", "")) + str(Shed.bank.get("overdraft", 0))]
	if sig != _shown:
		_shown = sig
		refresh()


func _crew_signature() -> String:
	var parts := []
	for peer in Shed.crew:
		parts.append("%d:%s" % [int(peer), str(Shed.crew[peer]["name"])])
	parts.sort()
	return ",".join(parts) + "|" + str(Shed.is_authority())


## The send list (the business, then everyone else here) and the owner list (everyone here).
func _fill_choices() -> void:
	_filling = true
	var was := _send_target()
	_send_to.clear()
	_send_to.add_item("The business")
	_send_to.set_item_metadata(0, 0)
	var peers: Array = Shed.crew.keys()
	peers.sort()
	for peer in peers:
		if int(peer) == Shed.me():
			continue
		_send_to.add_item(str(Shed.crew[peer]["name"]))
		_send_to.set_item_metadata(_send_to.item_count - 1, int(peer))
	for i in _send_to.item_count:
		if int(_send_to.get_item_metadata(i)) == was:
			_send_to.select(i)
	_owner.clear()
	for peer in peers:
		_owner.add_item(str(Shed.crew[peer]["name"]))
	var owner := Money.owner_name()
	var found := false
	for i in _owner.item_count:
		if _owner.get_item_text(i) == owner:
			_owner.select(i)
			found = true
	if not found:
		# The owner isn't here right now: they keep it, shown at the end.
		_owner.add_item(owner)
		_owner.select(_owner.item_count - 1)
	_filling = false


func _send_target() -> int:
	if _send_to == null or _send_to.selected < 0:
		return 0
	return int(_send_to.get_item_metadata(_send_to.selected))


## Everything that shows numbers: the summary, who may do what, the loans and the ledgers.
func refresh() -> void:
	var bank: Dictionary = Shed.bank
	var owner := Money.owner_name()
	var is_owner := Money.is_owner(Shed.me())
	var host := Shed.is_authority() and Shed.me() == 1
	var od := int(bank.get("overdraft", 0))
	_summary.text = "You: %s     The business: %s%s     It takes %d%% of wages; %s owns it.     Day %d" % [
		TvChannels.money_text(Progress.money()), TvChannels.money_text(Shed.garage_money),
		("  (OVERDRAWN by %s)" % TvChannels.money_text(od)) if od > 0 else "", int(bank["cut"]), owner, int(bank["day"])]
	_take.disabled = not is_owner
	_take.tooltip_text = "" if is_owner else "Only the garage owner (%s) can take money out." % owner
	_filling = true
	_cut.value = int(bank["cut"])
	_costs.select(maxi(0, Money.COSTS_MODES.find(str(bank.get("costs", "normal")))))
	_filling = false
	_cut.editable = host
	_owner.disabled = not host
	_costs.disabled = not host
	_costs.tooltip_text = "" if host else "Only the host can change the running costs."
	_bills_shown = ""
	refresh_bills()
	_settings_note.text = "The host sets these; they're saved with the shed." if host else "Only the host can change these."
	if not _owner.disabled:
		_fill_choices()
	for c in _loans.get_children():
		c.queue_free()
	if bank["loans"].is_empty():
		_loans.add_child(UITheme.label("No loans. The business owes the bank nothing.", 15))
	for loan in bank["loans"]:
		var row := _row(_loans)
		var missed := int(loan["missed"])
		var loan_text := UITheme.label("%s borrowed: %s still owed, %s a day%s" % [TvChannels.money_text(int(loan["amount"])),
			TvChannels.money_text(int(loan["owed"])), TvChannels.money_text(int(loan["daily"])),
			("  (%d missed)" % missed) if missed > 0 else ""], 15, Color(1, 0.55, 0.45) if missed > 0 else Color(0.85, 0.87, 0.9))
		loan_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # wraps across the row, not into a column
		row.add_child(loan_text)
		var id := int(loan["id"])
		var part := mini(1000, int(loan["owed"]))
		var pay := _button("Pay %s" % TvChannels.money_text(part), func(): repay(id, part))
		var clear := _button("Clear it", func(): repay(id, int(loan["owed"])))
		for b in [pay, clear]:
			b.disabled = not is_owner
			b.tooltip_text = "" if is_owner else "Only the garage owner can pay loans off."
			row.add_child(b)
	if bool(bank["blocked"]):
		_loans.add_child(UITheme.label("A repayment was missed: the bank won't lend more until that loan is paid off.", 15,
			Color(1, 0.55, 0.45)))
	for i in Money.LOANS.size():
		var offer := i
		var b := _button(Money.offer_text(i), func(): take_loan(offer))
		var why := Money.check(Shed.me(), {"a": "money_loan", "offer": i})
		b.disabled = why != ""
		b.tooltip_text = Controls.hint(why)
		_loans.add_child(b)
	for c in _ledger.get_children():
		c.queue_free()
	var ledger: Array = bank["ledger"]
	if ledger.is_empty():
		_ledger.add_child(UITheme.label("Nothing yet.", 15))
	var recent := ledger.slice(-25)
	recent.reverse()
	for e in recent:
		_ledger.add_child(_line(int(e["day"]), int(e["amt"]), str(e["why"]), TvChannels.money_text(int(e["bal"]))))
	for c in _mine.get_children():
		c.queue_free()
	var mine: Array = Progress.profile.get("cash_log", []).slice(-12)
	mine.reverse()
	if mine.is_empty():
		_mine.add_child(UITheme.label("Nothing yet: jobs in the shed pay wages.", 15))
	for e in mine:
		_mine.add_child(_line(int(e["day"]), int(e["amt"]), str(e["why"]), ""))


## The running costs section: tonight's bill so far line by line, the last bill, and any
## overdraft. Rebuilt only when something in it changed.
func refresh_bills() -> void:
	if _bills == null:
		return
	var bank: Dictionary = Shed.bank
	var lines := Money.bill_lines(bank)
	var od := int(bank.get("overdraft", 0))
	var sig := var_to_str([lines, od, bank.get("last_bill", []), bank.get("last_bill_day", -1), bank.get("costs", "")])
	if sig == _bills_shown:
		return
	_bills_shown = sig
	for c in _bills.get_children():
		c.queue_free()
	var mode := str(bank.get("costs", "normal"))
	if lines.is_empty():
		_bills.add_child(UITheme.label("Running costs are off: the business pays no bills.", 15))
	else:
		_bills.add_child(UITheme.label("Tonight's bill so far (%s): %s" % [str(Money.COSTS_NAMES.get(mode, mode)).to_lower(),
			TvChannels.money_text(Money.bill_total(lines))], 16, UITheme.ACCENT))
		for l in lines:
			_bills.add_child(UITheme.label("      %s    %s" % [str(l["why"]), TvChannels.money_text(int(l["amt"]))], 15,
				Color(0.85, 0.87, 0.9)))
	var last: Array = bank.get("last_bill", [])
	if not last.is_empty():
		_bills.add_child(UITheme.label("Last bill, day %d: %s" % [int(bank.get("last_bill_day", 0)), TvChannels.money_text(Money.bill_total(last))],
			14, Color(1, 1, 1, 0.6)))
	if od > 0:
		_bills.add_child(UITheme.label("The business is overdrawn by %s. Income pays it back first; until then it costs %.1f%% a day." % [
			TvChannels.money_text(od), Money.OVERDRAFT_RATE * 100.0], 15, Color(1, 0.55, 0.45)))


## Shows the money graphs by the minute, hour, day, week, month or year (kept in the settings;
## the money TV channels follow it too).
func set_graph_range(range_key: String) -> void:
	if not MoneyGraph.RANGES.has(range_key):
		return
	Settings.money_graph_range = range_key
	Settings.save_settings()
	if _graph_buttons.has(range_key) and not (_graph_buttons[range_key] as Button).button_pressed:
		(_graph_buttons[range_key] as Button).set_pressed_no_signal(true)
	refresh_graphs()


## Redraws both graphs for the chosen range, up to now.
func refresh_graphs() -> void:
	if _graph_mine == null:
		return
	var key := Settings.money_graph_range
	var span := MoneyGraph.span_text(key)
	_graph_mine.show_values(Progress.cash_graph(key), "Your money, %s" % span, key)
	_graph_garage.show_values(Money.graph(key), "The business, %s" % span, key)


func _line(day: int, amt: int, why: String, bal: String) -> Label:
	var col := Color(0.55, 0.95, 0.55) if amt > 0 else (Color(1, 0.55, 0.45) if amt < 0 else Color(1, 1, 1, 0.6))
	var l := UITheme.label("Day %d    %s%s    %s%s" % [day, "+" if amt > 0 else "", TvChannels.money_text(amt), why,
		("    (%s)" % bal) if bal != "" else ""], 14, col)
	return l


# ---------------------------------------------------------------------------- what the buttons do (tests call these)

## Sends your own cash to a mate (their peer) or the business (0).
func send_money(to: int, amount: int) -> void:
	var why := Money.send(to, amount)
	if why != "":
		_status.text = why


## The owner takes money out of the business into their own cash.
func withdraw(amount: int) -> void:
	Shed.request({"a": "money_withdraw", "amount": amount})


## Host: how hard the running costs bite ("off", "normal" or "hard").
func set_costs(mode: String) -> void:
	Shed.request({"a": "money_settings", "costs": mode})


func take_loan(offer: int) -> void:
	Shed.request({"a": "money_loan", "offer": offer})


func repay(loan_id: int, amount: int) -> void:
	Shed.request({"a": "money_repay", "loan": loan_id, "amount": amount})


func _row(parent: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	(parent if parent else _box).add_child(row)
	return row


## A label for the start of a row: one line, never squeezed into a column of letters.
func _row_label(text: String) -> Label:
	var l := UITheme.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _amount_box() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = Progress.MAX_MONEY
	sb.step = 1
	sb.value = 100
	sb.prefix = TvChannels.CURRENCY
	sb.custom_minimum_size.x = 160.0
	return sb


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
