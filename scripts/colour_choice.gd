class_name ColourChoice
extends Button
## A small swatch button that picks a colour, for the Bike shop's configurator: pressed, it opens
## a panel with the colour square, its hue strip and the hex box, the paint shop's colours
## (Shed.PAINTS) as swatches and the colours picked lately, all of them showing at once, the panel
## kept on the screen. Emits color_changed as the colour changes.

signal color_changed(color: Color)

## How many of the colours picked lately it keeps (shared by every ColourChoice).
const RECENT_MAX := 10
const SWATCH := Vector2(24, 24)

static var recent: Array[Color] = []

var color := Color.WHITE:
	set(c):
		color = c
		_paint_face()
var _popup: PopupPanel
var _picker: ColorPicker
var _recent_row: HBoxContainer
var _started := Color.WHITE


func _init() -> void:
	custom_minimum_size = Vector2(36, 22)
	focus_mode = Control.FOCUS_ALL
	pressed.connect(open)
	_paint_face()


## The button's face: the colour itself, with a thin edge so black shows on the dark menu.
func _paint_face() -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_corner_radius_all(3)
		box.border_color = Color(1, 1, 1, 0.55 if st in ["hover", "focus"] else 0.25)
		box.set_border_width_all(1)
		add_theme_stylebox_override(st, box)


## Opens the panel under (or over) the button.
func open() -> void:
	if _popup == null:
		_build()
	_started = color
	_picker.color = color
	_fill_recent()
	_popup.reset_size()
	var room := Rect2(get_viewport().get_visible_rect())
	var at := get_global_rect()
	var sz := Vector2(_popup.size)
	var pos := Vector2(at.position.x, at.end.y + 4.0)
	if pos.y + sz.y > room.end.y:
		pos.y = at.position.y - sz.y - 4.0
	pos.x = clampf(pos.x, room.position.x, maxf(room.position.x, room.end.x - sz.x))
	pos.y = clampf(pos.y, room.position.y, maxf(room.position.y, room.end.y - sz.y))
	_popup.popup(Rect2i(Vector2i(pos), Vector2i(sz)))


func _build() -> void:
	_popup = PopupPanel.new()
	_popup.name = "ColourPanel"
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.12, 0.14)
	bg.set_content_margin_all(10.0)
	bg.set_corner_radius_all(4)
	bg.border_color = Color(1, 1, 1, 0.14)
	bg.set_border_width_all(1)
	_popup.add_theme_stylebox_override("panel", bg)
	_popup.popup_hide.connect(_closed)
	add_child(_popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_popup.add_child(box)
	_picker = ColorPicker.new()
	_picker.name = "Picker"
	_picker.edit_alpha = false
	_picker.sliders_visible = false
	_picker.color_modes_visible = false
	_picker.sampler_visible = false
	_picker.presets_visible = false
	_picker.hex_visible = true
	_picker.color_changed.connect(_pick)
	box.add_child(_picker)
	box.add_child(_heading("Swatches"))
	var grid := GridContainer.new()
	grid.name = "Swatches"
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for c in Shed.PAINTS:
		grid.add_child(_swatch(c, Shed.paint_name(c).capitalize()))
	box.add_child(grid)
	box.add_child(_heading("Recent colours"))
	_recent_row = HBoxContainer.new()
	_recent_row.name = "Recent"
	_recent_row.add_theme_constant_override("separation", 4)
	_recent_row.custom_minimum_size.y = SWATCH.y
	box.add_child(_recent_row)


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l


func _swatch(c: Color, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SWATCH
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "focus"]:
		var face := StyleBoxFlat.new()
		face.bg_color = c
		face.set_corner_radius_all(3)
		face.border_color = Color(1, 1, 1, 0.7 if st in ["hover", "focus"] else 0.2)
		face.set_border_width_all(2 if st in ["hover", "focus"] else 1)
		b.add_theme_stylebox_override(st, face)
	b.pressed.connect(func(): _picker.color = c; _pick(c))
	return b


func _fill_recent() -> void:
	for c in _recent_row.get_children():
		c.free()
	for c in recent:
		_recent_row.add_child(_swatch(c, "#" + c.to_html(false)))
	if recent.is_empty():
		_recent_row.add_child(_heading("(none yet)"))


func _pick(c: Color) -> void:
	color = c
	color_changed.emit(c)


## Closed: a colour that changed goes to the front of the recent colours.
func _closed() -> void:
	if color.is_equal_approx(_started):
		return
	remember(color)


static func remember(c: Color) -> void:
	for i in range(recent.size() - 1, -1, -1):
		if recent[i].is_equal_approx(c):
			recent.remove_at(i)
	recent.push_front(c)
	if recent.size() > RECENT_MAX:
		recent.resize(RECENT_MAX)
