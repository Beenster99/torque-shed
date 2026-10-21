class_name HomeOfferPanel
extends Control
## Someone has offered you money for a bike in your collection (see Collection): who, how much,
## what the bike is worth, and Accept, Decline or Later. It comes up on its own while you're on
## foot with nothing else open (main.gd asks with due()); Later puts that offer aside till the
## next one comes in. The answer goes to the host (home_answer), which moves the money and the bike.

signal closed

var offer_id := 0
## Offers put aside with Later (offer id -> true), not shown again this session.
var later := {}
var _head: Label
var _body: Label
var _status: Label
var _yes: Button
var _no: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("bike_order_panel")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_head = UITheme.title("AN OFFER FOR YOUR BIKE", 24)
	box.add_child(_head)
	_body = UITheme.label("", 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_yes = Button.new()
	_yes.pressed.connect(func(): answer(true))
	row.add_child(_yes)
	_no = Button.new()
	_no.text = "Decline"
	_no.pressed.connect(func(): answer(false))
	row.add_child(_no)
	row.add_child(ContractPanel.button("Later ({back})", close_dialog))
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	Shed.homes_changed.connect(func(): if visible: _refresh())


## The next offer waiting for you that hasn't been put aside, or {}.
func due() -> Dictionary:
	for o in Collection.offers_to(Collection.name_of(Shed.me())):
		if not later.has(int(o["id"])):
			return o
	return {}


## Shows offer `id`.
func open_offer(id: int) -> void:
	offer_id = id
	_status.text = ""
	visible = true
	_refresh()


func close_dialog() -> void:
	if offer_id != 0:
		later[offer_id] = true
	visible = false
	closed.emit()


func answer(yes: bool) -> void:
	var why := Shed.check(Shed.me(), {"a": "home_answer", "offer": offer_id, "yes": yes})
	if why != "":
		_status.text = why
		return
	Shed.request({"a": "home_answer", "offer": offer_id, "yes": yes})
	offer_id = 0
	visible = false
	closed.emit()


func _refresh() -> void:
	var o: Dictionary = Collection.offers().get(offer_id, {})
	if o.is_empty():
		offer_id = 0
		visible = false
		closed.emit()
		return
	var e := Collection.entry(int(o["bike"]))
	var amount := int(o["amount"])
	var worth := int(e.get("value", 0))
	var paid := int(e.get("paid", 0))
	var lines := ["%s offers you %s for your %s." % [str(o["from"]), Collection.money(amount), str(e.get("name", "bike"))],
		"It's worth about %s%s." % [Collection.money(worth), "; you paid %s" % Collection.money(paid) if paid > 0 else ""]]
	if int(e.get("out", 0)) != 0:
		lines.append("It's out on the road: bring it home to your courtyard before you accept.")
	_body.text = "\n".join(lines)
	_yes.text = "Accept %s" % Collection.money(amount)
	var why := Shed.check(Shed.me(), {"a": "home_answer", "offer": offer_id, "yes": true})
	_yes.disabled = why != ""
	_yes.tooltip_text = why
