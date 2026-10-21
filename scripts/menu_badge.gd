class_name MenuBadge
extends Button
## A corner badge on the Esc menu: a little picture with two lines of text beside it, which opens
## a panel when clicked. "garage" (top left) draws the shed with its roller door, for the
## garage's name and account; "profile" (top right) draws your rider in the colours you wear
## (helmet, jacket and your own colour), for your name, level and cash.

const PIC := 44.0
const PAD := 8.0
const SKIN := Color(0.86, 0.68, 0.54)

## "garage" or "profile".
var kind := "garage"
## The rider's colours for the profile picture: {"helmet", "jacket", "back"} (see set_rider).
var rider := {"helmet": UITheme.ACCENT, "jacket": Color(0.25, 0.27, 0.3), "back": Color(0.3, 0.32, 0.36)}


func _init(badge_kind := "garage") -> void:
	kind = badge_kind
	custom_minimum_size = Vector2(250, PIC + PAD * 2.0)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	# Room on the left for the picture: the text starts after it.
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := get_theme_stylebox(st).duplicate() as StyleBox
		if box == null:
			continue
		box.content_margin_left = PIC + PAD * 2.5
		box.content_margin_right = PAD * 2.0
		add_theme_stylebox_override(st, box)


## Sets the badge's two lines of text (a name, then the detail under it).
func set_lines(title: String, detail: String) -> void:
	var t := "%s\n%s" % [title, detail]
	if text != t:
		text = t


## The rider's colours for the profile picture.
func set_rider(helmet: Color, jacket: Color, back: Color) -> void:
	var r := {"helmet": helmet, "jacket": jacket, "back": back}
	if r != rider:
		rider = r
		queue_redraw()


func _draw() -> void:
	var at := Vector2(PAD, (size.y - PIC) * 0.5)
	if kind == "profile":
		_draw_rider(at)
	else:
		_draw_garage(at)


## The shed: a pitched roof over a wide roller door, slats across it.
func _draw_garage(at: Vector2) -> void:
	var w := PIC
	draw_rect(Rect2(at, Vector2(w, w)), Color(0.12, 0.13, 0.15), true)
	var roof := PackedVector2Array([at + Vector2(2, w * 0.42), at + Vector2(w * 0.5, 4), at + Vector2(w - 2, w * 0.42)])
	draw_colored_polygon(roof, UITheme.ACCENT)
	var wall := Rect2(at + Vector2(6, w * 0.42), Vector2(w - 12, w * 0.52))
	draw_rect(wall, Color(0.55, 0.57, 0.6), true)
	var door := Rect2(wall.position + Vector2(5, 6), Vector2(wall.size.x - 10, wall.size.y - 6))
	draw_rect(door, Color(0.28, 0.3, 0.33), true)
	var y := door.position.y + 3.0
	while y < door.end.y:
		draw_line(Vector2(door.position.x, y), Vector2(door.end.x, y), Color(0.45, 0.47, 0.5), 1.0)
		y += 3.5


## The rider: a round portrait, head and shoulders in their helmet and jacket.
func _draw_rider(at: Vector2) -> void:
	var r := PIC * 0.5
	var c := at + Vector2(r, r)
	draw_circle(c, r, rider["back"])
	# Shoulders: the jacket, a broad dome along the bottom of the circle.
	var sh := PackedVector2Array()
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		sh.append(c + Vector2(cos(a) * r * 0.82, r * 0.98 + sin(a) * r * 0.5))
	draw_colored_polygon(sh, rider["jacket"])
	draw_circle(c + Vector2(0, -r * 0.08), r * 0.36, SKIN)
	# The helmet: over the top of the head, with a dark visor line.
	var hel := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		hel.append(c + Vector2(cos(a) * r * 0.42, -r * 0.1 + sin(a) * r * 0.42))
	draw_colored_polygon(hel, rider["helmet"])
	draw_line(c + Vector2(-r * 0.4, -r * 0.1), c + Vector2(r * 0.4, -r * 0.1), Color(0.05, 0.05, 0.06), 2.0)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, UITheme.ACCENT, 2.0, true)
