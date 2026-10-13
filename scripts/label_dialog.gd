class_name LabelDialog
extends Control
## A small box for writing on a shelving unit's label plate, or naming a bike.

signal closed

var furniture_id := 0
var bike_id := 0
var _edit: LineEdit
var _title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_title = UITheme.title("SHELF LABEL", 24)
	col.add_child(_title)
	_edit = LineEdit.new()
	_edit.max_length = 24
	_edit.placeholder_text = "Brakes, engine spares, Barn Find..."
	_edit.text_submitted.connect(func(_t): _save())
	col.add_child(_edit)
	var row := HBoxContainer.new()
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	row.add_child(save)
	var cancel := Button.new()
	cancel.text = "Cancel (Esc)"
	cancel.pressed.connect(close_dialog)
	row.add_child(cancel)
	col.add_child(row)


func open(id: int) -> void:
	furniture_id = id
	bike_id = 0
	_title.text = "SHELF LABEL"
	_edit.max_length = 24
	_edit.placeholder_text = "Brakes, engine spares, Barn Find..."
	_edit.text = str(Shed.furniture.get(id, {}).get("label", ""))
	_show()


## Name a bike: it shows on the bay screen, the wall dashboards and the crew board.
func open_bike(id: int) -> void:
	bike_id = id
	furniture_id = 0
	_title.text = "NAME THIS BIKE"
	_edit.max_length = 28
	_edit.placeholder_text = "Old Faithful, The Beast, Project X..."
	_edit.text = str(Shed.bikes.get(id, {}).get("name", ""))
	_show()


func _show() -> void:
	visible = true
	_edit.grab_focus()
	_edit.select_all()


func close_dialog() -> void:
	visible = false
	closed.emit()


func _save() -> void:
	if bike_id != 0:
		Shed.request({"a": "rename_bike", "bike": bike_id, "name": _edit.text})
	else:
		Shed.request({"a": "label", "furniture": furniture_id, "text": _edit.text})
	close_dialog()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		close_dialog()
		get_viewport().set_input_as_handled()
