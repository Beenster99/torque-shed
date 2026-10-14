class_name SkillTreeView
extends Control
## The skills tree drawn as branches: a row per branch (Mechanic, Finisher, Rider, Tuner, Crew),
## its skills in three tiers from left to right, with lines from each skill to the ones it opens.
## Owned skills are filled, ones you can buy now have a lit outline, the rest are greyed out.

signal hovered(id: String)
signal chosen(id: String)

const LABEL_W := 92.0
const NODE := Vector2(158, 34)
const TIER_W := 182.0
const ROW_H := 42.0
const BAND_GAP := 10.0

var _rects := {}      # skill id -> Rect2
var _hover := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	Progress.changed.connect(queue_redraw)


## Places every skill: its branch's band, its tier's column, stacked when a tier has two.
func _layout() -> void:
	_rects.clear()
	var y := 0.0
	for branch in Progress.BRANCHES:
		var rows := 1
		var used := {}
		for id in Progress.SKILLS:
			var s: Dictionary = Progress.SKILLS[id]
			if s["branch"] != branch:
				continue
			var tier := int(s["tier"])
			var sub := int(used.get(tier, 0))
			used[tier] = sub + 1
			rows = maxi(rows, sub + 1)
			_rects[id] = Rect2(Vector2(LABEL_W + tier * TIER_W, y + sub * ROW_H), NODE)
		y += rows * ROW_H + BAND_GAP
	custom_minimum_size = Vector2(LABEL_W + 3 * TIER_W, y)


func _band_top(branch: String) -> float:
	var top := INF
	for id in _rects:
		if Progress.SKILLS[id]["branch"] == branch:
			top = minf(top, (_rects[id] as Rect2).position.y)
	return top


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := _at((event as InputEventMouseMotion).position)
		if id != _hover:
			_hover = id
			hovered.emit(id)
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var id := _at((event as InputEventMouseButton).position)
		if id != "":
			chosen.emit(id)
			hovered.emit(id)
			accept_event()


func _at(p: Vector2) -> String:
	for id in _rects:
		if (_rects[id] as Rect2).has_point(p):
			return id
	return ""


func _draw() -> void:
	var font := get_theme_default_font()
	for branch in Progress.BRANCHES:
		draw_string(font, Vector2(0, _band_top(branch) + 22), Progress.BRANCH_NAMES[branch], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 6,
			15, UITheme.ACCENT)
	# Lines from each skill to the ones it opens.
	for id in _rects:
		var r: Rect2 = _rects[id]
		for need in Progress.SKILLS[id]["needs"]:
			if not _rects.has(need):
				continue
			var from: Rect2 = _rects[need]
			var lit := Progress.skill_rank(Shed.me(), str(need)) > 0
			var a := Vector2(from.end.x, from.get_center().y)
			var b := Vector2(r.position.x, r.get_center().y)
			var mid := (a.x + b.x) * 0.5
			var col := Color(UITheme.ACCENT, 0.8) if lit else Color(1, 1, 1, 0.18)
			draw_polyline(PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b]), col, 2.0, true)
	for id in _rects:
		var r: Rect2 = _rects[id]
		var s: Dictionary = Progress.SKILLS[id]
		var rank := Progress.skill_rank(Shed.me(), id)
		var ranks := int(s["ranks"])
		var can := Progress.skill_block(id) == ""
		var later := str(s.get("milestone", "")) != ""
		var fill := Color(0.12, 0.13, 0.16)
		if rank >= ranks:
			fill = Color(0.18, 0.42, 0.22)
		elif rank > 0:
			fill = Color(0.14, 0.3, 0.18)
		draw_rect(r, fill)
		var edge := Color(1, 1, 1, 0.12)
		if can:
			edge = UITheme.ACCENT
		elif rank > 0:
			edge = Color(0.5, 0.9, 0.5, 0.8)
		if id == _hover:
			edge = Color.WHITE
		draw_rect(r, edge, false, 2.0 if can or id == _hover else 1.0)
		var text_col := Color.WHITE if rank > 0 or can else Color(1, 1, 1, 0.45)
		draw_string(font, r.position + Vector2(8, 15), str(s["name"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14, 13, text_col)
		var pips := "●".repeat(rank) + "○".repeat(ranks - rank)
		draw_string(font, r.position + Vector2(8, 29), pips + ("   money: Milestone C" if later else ""), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 14, 11, Color(0.6, 0.95, 0.6) if rank > 0 else Color(1, 1, 1, 0.4))
