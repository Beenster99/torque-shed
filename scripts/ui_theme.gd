class_name UITheme
extends RefCounted
## Shared look for menus and panels.

const ACCENT := Color(1.0, 0.62, 0.2)
const PANEL_BG := Color(0.07, 0.08, 0.1, 0.9)


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(18)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.16, 0.17, 0.2)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(10)
	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color(0.24, 0.25, 0.3)
	var btn_pressed := btn.duplicate()
	btn_pressed.bg_color = ACCENT.darkened(0.3)
	for kind in ["Button", "OptionButton"]:
		t.set_stylebox("normal", kind, btn)
		t.set_stylebox("hover", kind, btn_hover)
		t.set_stylebox("pressed", kind, btn_pressed)
		t.set_stylebox("focus", kind, btn_hover)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", empty)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.03, 0.03, 0.04)
	edit.set_corner_radius_all(6)
	edit.set_content_margin_all(8)
	t.set_stylebox("normal", "LineEdit", edit)
	return t


static func title(text: String, font_size := 28, color := ACCENT) -> Label:
	var l := Label.new()
	Controls.bind_text(l, text)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func label(text: String, font_size := 16, color := Color(0.85, 0.87, 0.9)) -> Label:
	var l := Label.new()
	Controls.bind_text(l, text)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
