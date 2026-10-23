class_name HomeMakeOffer
extends Control
## Making a friend an offer for a bike in their collection, opened from the bike's card
## (HomePanel): the bike turning on a turntable, what it's worth and what you have, how much to
## offer (drag the slider or type it in; it starts at what the bike's worth, or all you have if
## that's less), and one clear Make offer button beside Cancel. Arrow keys move the slider, Enter
## makes the offer and {back} cancels. The money's taken now and held till they answer (see
## Collection.make_offer); once it's gone this window says so, with no message along the top.

signal cancelled
signal done

## The slider moves in tens of pounds (type an amount for anything in between).
const STEP := 10

var cid := 0
## The offer's gone: the window shows it made, with OK to close.
var sent := false
var _form: VBoxContainer
var _made: VBoxContainer
var _sub: Label
var _preview: PartPreview
var _worth: Label
var _have: Label
var _slider: HSlider
var _spin: SpinBox
var _note: Label
var _status: Label
var _make: Button
var _cancel: Button
var _made_text: Label
var _ok: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var both := VBoxContainer.new()
	panel.add_child(both)
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	both.add_child(_form)
	_form.add_child(UITheme.title("MAKE AN OFFER", 26))
	_sub = UITheme.label("", 16, Color(1, 1, 1, 0.75))
	_form.add_child(_sub)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	_form.add_child(top)
	_preview = PartPreview.new()
	_preview.custom_minimum_size = Vector2(300, 190)
	top.add_child(_preview)
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	facts.add_theme_constant_override("separation", 2)
	top.add_child(facts)
	facts.add_child(UITheme.label("WORTH ABOUT", 14, UITheme.ACCENT))
	_worth = UITheme.label("", 26)
	facts.add_child(_worth)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	facts.add_child(gap)
	facts.add_child(UITheme.label("YOUR MONEY", 14, UITheme.ACCENT))
	_have = UITheme.label("", 20)
	facts.add_child(_have)
	_form.add_child(HSeparator.new())
	_form.add_child(UITheme.label("YOUR OFFER", 15, UITheme.ACCENT))
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 12)
	_form.add_child(amount_row)
	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.step = STEP
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(0, 28)
	_slider.focus_mode = Control.FOCUS_ALL
	_slider.value_changed.connect(func(v: float):
		_spin.set_value_no_signal(v)
		_refresh())
	amount_row.add_child(_slider)
	_spin = SpinBox.new()
	_spin.name = "Amount"
	_spin.prefix = "£"
	_spin.step = 1
	_spin.custom_arrow_step = 50
	_spin.min_value = Collection.MIN_OFFER
	_spin.custom_minimum_size.x = 170
	_spin.select_all_on_focus = true
	_spin.value_changed.connect(func(v: float):
		_slider.set_value_no_signal(v)
		_refresh())
	amount_row.add_child(_spin)
	_note = UITheme.label("", 14, Color(1, 1, 1, 0.6))
	_form.add_child(_note)
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_form.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_form.add_child(row)
	_make = Button.new()
	_make.name = "MakeOffer"
	_make.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make.pressed.connect(make_offer)
	primary(_make)
	row.add_child(_make)
	_cancel = ContractPanel.button("Cancel ({back})", cancel)
	_cancel.custom_minimum_size.x = 160
	row.add_child(_cancel)
	_slider.focus_neighbor_bottom = _slider.get_path_to(_make)
	_make.focus_neighbor_top = _make.get_path_to(_slider)
	_cancel.focus_neighbor_top = _cancel.get_path_to(_slider)
	# Once it's gone: what was offered, and OK.
	_made = VBoxContainer.new()
	_made.add_theme_constant_override("separation", 12)
	_made.visible = false
	both.add_child(_made)
	_made.add_child(UITheme.title("OFFER MADE", 26))
	_made_text = UITheme.label("", 17)
	_made.add_child(_made_text)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.pressed.connect(func(): done.emit())
	primary(_ok)
	_made.add_child(_ok)
	Shed.homes_changed.connect(func(): if visible and not sent: _check_still())
	Progress.changed.connect(func(): if visible and not sent: _open_range())


## Styles `b` as a window's main button: filled in the accent colour, dark text, so it's the
## one the eye goes to.
static func primary(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.ACCENT
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UITheme.ACCENT.lightened(0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = UITheme.ACCENT.darkened(0.25)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = UITheme.ACCENT.lightened(0.15)
	focus.border_color = Color(1, 1, 1, 0.9)
	focus.set_border_width_all(2)
	var off := normal.duplicate() as StyleBoxFlat
	off.bg_color = Color(0.25, 0.24, 0.23)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", off)
	var ink := Color(0.08, 0.07, 0.06)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.add_theme_font_size_override("font_size", 20)


## Opens the window for collection bike `id`, the amount at what it's worth (or all you have).
func open(id: int) -> void:
	cid = id
	sent = false
	_form.visible = true
	_made.visible = false
	_status.text = ""
	var e := Collection.entry(cid)
	if e.is_empty():
		return
	var s := Collection.stats(cid)
	_sub.text = "%s's %s  ·  %s" % [str(e["owner"]), str(e.get("name", "bike")), str(s.get("style", ""))]
	_note.text = "The money's taken now and held till %s answers. If they say no it comes straight back, " % str(e["owner"]) \
		+ "and you can take it back yourself from the bike's card."
	_open_range()
	set_amount(default_amount(int(e.get("value", 0)), Progress.money()))
	visible = true
	var l := Collection.look(e.get("pack", {}))
	_preview.show_bike("offer|%d|%s" % [cid, str(hash(e.get("pack", {}).get("bike", {}).get("slots", {})))], l["parts"], l["paint"], l["cond"])
	_slider.grab_focus.call_deferred()


## What an offer starts at: what the bike's worth, in tens of pounds, or all you have if that's
## less (never under the least you can offer).
static func default_amount(worth: int, have: int) -> int:
	var v := mini(worth, have)
	if v >= STEP:
		v = floori(v / float(STEP)) * STEP
	return maxi(Collection.MIN_OFFER, v)


## The slider runs up to twice what it's worth (or worth plus £1,000
## on a cheap bike), never past what you have; typed in, it goes up to all you have.
func _open_range() -> void:
	var worth := int(Collection.entry(cid).get("value", 0))
	var have := maxi(Collection.MIN_OFFER, Progress.money())
	_slider.min_value = 0   # (from nought, so it stops on round tens; the amount itself never goes under MIN_OFFER)
	_slider.max_value = maxi(Collection.MIN_OFFER + STEP, mini(have, maxi(worth * 2, worth + 1000)))
	_spin.max_value = maxi(have, Collection.MIN_OFFER + 1)
	_refresh()


func amount() -> int:
	return roundi(_spin.value)


func set_amount(v: int) -> void:
	_spin.value = v   # (moves the slider with it)
	_slider.set_value_no_signal(v)
	_refresh()


func _why() -> String:
	var why := Shed.check(Shed.me(), {"a": "home_offer", "bike": cid, "amount": amount(), "paid": amount()})
	if why == "" and Progress.money() < amount():
		why = "You only have %s." % Collection.money(Progress.money())
	return why


func _refresh() -> void:
	if cid == 0 or sent:
		return
	var e := Collection.entry(cid)
	_worth.text = Collection.money(int(e.get("value", 0)))
	_have.text = Collection.money(Progress.money())
	var why := _why()
	_make.text = "Make offer: %s" % Collection.money(amount())
	_make.disabled = why != ""
	_status.text = Controls.hint(why)
	_status.visible = why != ""


## The bike's been sold on, or come out of its ring, or is yours now: nothing to offer for.
func _check_still() -> void:
	var e := Collection.entry(cid)
	if e.is_empty() or str(e["owner"]) == Collection.name_of(Shed.me()) or int(e.get("out", 0)) != 0:
		cancel()
		return
	_refresh()


## Takes the money and makes the offer; the window then says it's made.
func make_offer() -> void:
	if sent:
		done.emit()
		return
	var e := Collection.entry(cid)
	var said := _why()
	if said == "":
		said = Collection.make_offer(cid, amount())
	if said != "":
		_status.text = Controls.hint(said)
		_status.visible = true
		return
	sent = true
	_made_text.text = "You've offered %s %s for their %s.\n\nThe money's held till they answer: they'll see your offer as soon as they're on foot. You can take it back from the bike's card." \
		% [str(e.get("owner", "")), Collection.money(amount()), str(e.get("name", "bike"))]
	_form.visible = false
	_made.visible = true
	_preview.clear()
	_ok.grab_focus.call_deferred()


func cancel() -> void:
	visible = false
	_preview.clear()
	cancelled.emit()


## Enter makes the offer from the slider or the amount box ({back} is the card's: see HomePanel).
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_accept") or event.is_echo():
		return
	var f := get_viewport().gui_get_focus_owner()
	if f is Button:
		return   # the button presses itself
	if f == _spin.get_line_edit():
		var typed := _spin.get_line_edit().text.replace("£", "").replace(",", "").strip_edges()
		if typed.is_valid_float():
			set_amount(roundi(float(typed)))
	get_viewport().set_input_as_handled()
	make_offer()
