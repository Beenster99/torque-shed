class_name ProjectOrderCard
extends Control
## The parts computer's project bike order (Simon: "when i order a bike from the shop pc i should
## be presented with the condition slider"): the style picked beside the order button, the same
## quality slider as the "order one of these" card (QualitySlider) set to the condition it comes
## in, from worn to new, and what one goes for at that condition (Money.typical_project_price,
## typical_style_price), paid for by the business. "Order it" sends the host an "order" request
## with that "quality" (see PartsComputer.bike_order); the host finds the bike, prices it itself
## and leaves it in a free bay, with at least half a tank of fuel. A new one comes ready to ride.

## Where the slider starts: about as worn as a project bike that just turns up.
const START_QUALITY := 0.3

var style := ""
var _title: Label
var _price: Label
var _status: Label
var _go: Button
var quality_slider: QualitySlider
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = UITheme.title("ORDER A PROJECT BIKE", 26)
	box.add_child(_title)
	var sub := UITheme.label("Found for you and delivered to a free bay, paid for from the business's account. "
		+ "Pick the condition it comes in: slide it to new and it comes ready to ride.", 15, Color(1, 1, 1, 0.7))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	quality_slider = QualitySlider.new("CONDITION", START_QUALITY)
	quality_slider.describe = func(q: float) -> String: return condition_text(q)
	quality_slider.quality_changed.connect(func(_q): _refresh())
	box.add_child(quality_slider)
	_price = UITheme.label("", 16)
	_price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_price)
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_go = Button.new()
	_go.text = "Order it"
	_go.pressed.connect(order)
	row.add_child(_go)
	row.add_child(ContractPanel.button("Cancel ({back})", close))
	Shed.changed.connect(func(): if visible: _refresh())
	Shed.feedback.connect(func(text, ok): if visible and not ok: _status.text = Controls.hint(text))


## Opens the card for a project bike of `bike_style` ("" for any old one).
func open(bike_style: String) -> void:
	style = bike_style if PartsDB.STYLES.has(bike_style) else ""
	_sig = ""
	_status.text = ""
	visible = true
	_refresh()
	quality_slider.slider.grab_focus()


func close() -> void:
	visible = false


## The condition the slider's at (0 worn .. 1 new).
func quality() -> float:
	return quality_slider.quality()


## Moves the slider (tests).
func set_quality(q: float) -> void:
	quality_slider.set_quality(q)


## Around what one costs at `q`, as the parts computer guesses it before it's found.
func price_at(q: float) -> int:
	return Money.typical_project_price(q) if style == "" else Money.typical_style_price(style, q)


## The slider's line for a project bike: "Well used: about 81% condition" or, new, ready to ride.
static func condition_text(q: float) -> String:
	if BikeCopy.is_new(q):
		return "New: built and ready to ride, every fluid in"
	return "%s: about %d%% condition" % [BikeCopy.quality_name(q), roundi(BikeBuild.part_health(Money.aged_cond(Money.project_age(q))) * 100.0)]


func _refresh() -> void:
	var q := quality()
	var cost := price_at(q)
	var why := Shed.check(Shed.me(), PartsComputer.bike_order(style, q))
	if why == "" and Shed.garage_money < cost:
		why = "The business has %s: a bike like this is around %s." % [TvChannels.money_text(Shed.garage_money), TvChannels.money_text(cost)]
	var sig := "%s|%.2f|%d|%d|%s" % [style, q, cost, Shed.garage_money, why]
	if sig == _sig:
		return
	_sig = sig
	if BikeCopy.is_new(q):
		_title.text = "ORDER A NEW %s" % ("BIKE" if style == "" else PartsDB.style_noun(style).to_upper())
	else:
		_title.text = "ORDER %s" % ("A PROJECT BIKE" if style == "" else PartsDB.style_phrase(style).to_upper())
	quality_slider.refresh()
	_price.text = "Around %s from the business's account (it has %s). The exact price is what the bike that's found is worth, as it comes.\nIt comes with at least half a tank of fuel." % [
		TvChannels.money_text(cost), TvChannels.money_text(Shed.garage_money)]
	_go.text = "Order it for around %s" % TvChannels.money_text(cost)
	_go.disabled = why != ""
	_go.tooltip_text = Controls.hint(why)
	_status.text = Controls.hint(why)


## Sends the order and closes the card. Returns why not, or "".
func order() -> String:
	var action := PartsComputer.bike_order(style, quality())
	var why := Shed.check(Shed.me(), action)
	if why != "":
		_status.text = Controls.hint(why)
		return why
	Shed.request(action)
	close()
	return ""


## Everything the card says now (tests).
func text() -> String:
	var out := []
	for l in find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			out.append((l as Label).text)
	return "\n".join(out)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
