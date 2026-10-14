class_name MoneyTab
extends ScrollContainer
## The Esc menu's Money tab: your own cash and the business's account, sending money to a mate
## or to the business, taking money out of the business (the garage owner only), the garage's
## settings (the host only: the business's cut of wages and who owns it), bank loans and the
## business's ledger. Everything goes through Money and the host.

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
var _loans: VBoxContainer
var _ledger: VBoxContainer
var _mine: VBoxContainer
var _shown := ""
var _crew_shown := ""
var _filling := false


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
	cut_row.add_child(UITheme.label("The business's cut of every wage", 15))
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
	owner_row.add_child(UITheme.label("Garage owner", 15))
	_owner = OptionButton.new()
	_owner.custom_minimum_size.x = 220.0
	_owner.item_selected.connect(func(i):
		if not _filling:
			Shed.request({"a": "money_settings", "owner": _owner.get_item_text(i)}))
	owner_row.add_child(_owner)

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


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var crew_names := _crew_signature()
	if crew_names != _crew_shown:
		_crew_shown = crew_names
		_fill_choices()
	var sig := "%d|%d|%s|%s|%d|%s" % [Progress.money(), Shed.garage_money, var_to_str(Shed.bank.get("loans", [])),
		str(Shed.bank.get("ledger", []).size()) + str(Shed.bank.get("ledger", []).back() if not Shed.bank.get("ledger", []).is_empty() else ""),
		int(Shed.bank.get("cut", 0)), str(Shed.bank.get("owner", "")) + str(Progress.profile.get("cash_log", []).size())]
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
	_summary.text = "You: %s     The business: %s     It takes %d%% of wages; %s owns it.     Day %d" % [
		TvChannels.money_text(Progress.money()), TvChannels.money_text(Shed.garage_money), int(bank["cut"]), owner, int(bank["day"])]
	_take.disabled = not is_owner
	_take.tooltip_text = "" if is_owner else "Only the garage owner (%s) can take money out." % owner
	_filling = true
	_cut.value = int(bank["cut"])
	_filling = false
	_cut.editable = host
	_owner.disabled = not host
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
		row.add_child(UITheme.label("%s borrowed: %s still owed, %s a day%s" % [TvChannels.money_text(int(loan["amount"])),
			TvChannels.money_text(int(loan["owed"])), TvChannels.money_text(int(loan["daily"])),
			("  (%d missed)" % missed) if missed > 0 else ""], 15, Color(1, 0.55, 0.45) if missed > 0 else Color(0.85, 0.87, 0.9)))
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
		b.tooltip_text = why
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


func take_loan(offer: int) -> void:
	Shed.request({"a": "money_loan", "offer": offer})


func repay(loan_id: int, amount: int) -> void:
	Shed.request({"a": "money_repay", "loan": loan_id, "amount": amount})


func _row(parent: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	(parent if parent else _box).add_child(row)
	return row


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
