class_name DebugTab
extends ScrollContainer
## The Esc menu's Debug tab, for trying things out: reset or max out your XP and money, reset
## everyone's XP (the host tells every player's game), empty the garage's account or give it
## a million pounds (host). Every reset asks first.

var _info: Label
var _all_xp: Button
var _garage: Button
var _grant: Button
var _confirm: ConfirmationDialog
var _pending := Callable()


func _ready() -> void:
	name = "Debug"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UITheme.title("Debug", 26))
	box.add_child(UITheme.label("Testing helpers. Resets can't be undone.", 15, Color(1, 1, 1, 0.6)))
	_info = UITheme.label("", 16, UITheme.ACCENT)
	box.add_child(_info)

	box.add_child(UITheme.label("XP", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Reset my XP", func(): _ask("Reset your XP?",
			"You go back to level 1 with no XP, tool upgrades, skills or goals.", "Reset my XP", reset_my_xp)),
		_button("Max my XP", max_my_xp),
	]))
	_all_xp = _button("Reset everyone's XP", func(): _ask("Reset everyone's XP?",
		"Every player in the shed goes back to level 1 with no XP, tool upgrades, skills or goals.",
		"Reset everyone", reset_all_xp))
	box.add_child(_row([_all_xp]))

	box.add_child(UITheme.label("Money", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Reset my money", func(): _ask("Reset your money?", "Your cash goes back to nothing.", "Reset my money",
			reset_my_money)),
		_button("Max my money", max_my_money),
	]))
	_garage = _button("Reset garage money", func(): _ask("Reset the garage money?",
		"The shed's own account goes back to nothing, for everyone.", "Reset garage money", reset_garage_money))
	_grant = _button("Give the garage £1,000,000", give_garage_million)
	box.add_child(_row([_garage, _grant]))

	box.add_child(UITheme.label("Contracts (host)", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Send a customer", func(): Shed.request({"a": "contract_spawn"})),
		_button("Send a bespoke customer", func(): Shed.request({"a": "contract_spawn", "kind": "bespoke"})),
		_button("Send a batch order", func(): Shed.request({"a": "contract_spawn", "kind": "batch"})),
		_button("Send a test ride", func(): Shed.request({"a": "contract_spawn", "kind": "test_ride"})),
		_button("Reputation +5", func(): Shed.request({"a": "contract_rep", "value": Contracts.reputation() + 5})),
	]))

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func():
		if _pending.is_valid():
			_pending.call()
		_pending = Callable())
	_confirm.canceled.connect(func(): _pending = Callable())
	add_child(_confirm)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var host := Shed.is_authority()
	_all_xp.disabled = not host
	_all_xp.tooltip_text = "" if host else "Only the host can reset everyone's XP."
	for b in [_garage, _grant]:
		b.disabled = not host
		b.tooltip_text = "" if host else "Only the host can change the garage's money."
	_info.text = "You: level %d, %d XP, %s     Garage: %s" % [Progress.level(), int(Progress.profile.get("xp", 0)),
		TvChannels.money_text(Progress.money()), TvChannels.money_text(Shed.garage_money)]


## Asks before doing `then`.
func _ask(title: String, text: String, ok: String, then: Callable) -> void:
	_pending = then
	_confirm.title = title
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok
	_confirm.popup_centered()


## Whether a reset is waiting on its confirm dialog (for tests).
func asking() -> bool:
	return _confirm.visible and _pending.is_valid()


## Answers the open confirm dialog, as its OK (true) or Cancel button would.
func answer(yes: bool) -> void:
	if yes:
		_confirm.confirmed.emit()
	else:
		_confirm.canceled.emit()
	_confirm.hide()


func reset_my_xp() -> void:
	Progress.debug_reset_xp()


func max_my_xp() -> void:
	Progress.debug_max_xp()


func reset_all_xp() -> void:
	Progress.debug_reset_all_xp()


func reset_my_money() -> void:
	Progress.spend(Progress.money(), "Debug: money reset")


func max_my_money() -> void:
	Progress.earn(Progress.MAX_MONEY - Progress.money(), "Debug: maxed out")


func reset_garage_money() -> void:
	Shed.request({"a": "garage_money", "value": 0})


## Host: a million pounds into the business's account (see Money.DEBUG_GRANT).
func give_garage_million() -> void:
	Shed.request({"a": "money_debug_grant"})


## Presses the button labelled `text` (for tests).
func press(text: String) -> void:
	for b in find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not _confirm.is_ancestor_of(b):
			(b as Button).pressed.emit()
			return


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for b in buttons:
		row.add_child(b)
	return row


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
