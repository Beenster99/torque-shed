class_name BlastHud
extends Control
## The sandblaster's readout, while your hands are in the gloves: a big bar across the top for
## the whole engine, and down the left each part with how much of it is bare metal and its rust,
## muck, wear and condition as they change. When a part comes up bare the screen flashes and
## "Bare metal!" pops up; when the whole engine is done it says so, big. With the scan on, a panel
## down the right shows what's still to blast: over the whole engine, part by part and side by side.

const GOOD := Color(0.45, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.35)
const RUST := Color(0.85, 0.45, 0.2)
const METAL := Color(0.78, 0.86, 0.95)
const CUE_LIFE := 1.8
const ENGINE_CUE_LIFE := 3.2
const SCAN := Color(0.35, 1.0, 0.55)

var walker: Walker
var game: BlastGame
## The celebration on screen: {kind, name, age}; and how bright the screen flash is.
var cue := {}
var flash := 0.0
var _row_flash := {}     # part name -> seconds of glow left on its row
## The latest scan readout (BlastGame.scan), refreshed a few times a second while it's on.
var scan_view := {}
var _scan_age := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	game = walker.blast if walker and is_instance_valid(walker) else null
	visible = game != null
	if game == null:
		cue = {}
		flash = 0.0
		_row_flash.clear()
		scan_view = {}
		return
	if game.scanning:
		_scan_age -= delta
		if _scan_age <= 0.0 or scan_view.is_empty():
			_scan_age = 0.25
			scan_view = game.scan()
	else:
		scan_view = {}
	while not walker.blast_cues.is_empty():
		var c: Dictionary = walker.blast_cues.pop_front()
		# The whole engine trumps a part finishing at the same moment.
		if cue.is_empty() or str(c["kind"]) == "engine" or str(cue.get("kind", "")) != "engine":
			cue = {"kind": c["kind"], "name": c["name"], "age": 0.0}
		flash = 0.55 if str(c["kind"]) == "engine" else 0.3
		_row_flash[str(c["name"])] = 1.2
	if not cue.is_empty():
		cue["age"] = float(cue["age"]) + delta
		if float(cue["age"]) > (ENGINE_CUE_LIFE if str(cue["kind"]) == "engine" else CUE_LIFE):
			cue = {}
	flash = maxf(0.0, flash - delta * 1.4)
	for k in _row_flash.keys():
		_row_flash[k] = float(_row_flash[k]) - delta
		if float(_row_flash[k]) <= 0.0:
			_row_flash.erase(k)
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var font := get_theme_default_font()
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 0.96, flash * 0.5))
	var lines := game.lines()
	var done := 0
	for l in lines:
		if l["done"]:
			done += 1
	# The whole engine, across the top.
	var total := game.total()
	var w := minf(620.0, size.x - 48.0)
	var top := Rect2((size.x - w) * 0.5, 66.0, w, 78.0)
	draw_rect(top, Color(0.03, 0.04, 0.06, 0.78))
	draw_rect(Rect2(top.position, Vector2(top.size.x, 3.0)), UITheme.ACCENT)
	draw_string(font, top.position + Vector2(16, 30), "SANDBLASTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.ACCENT)
	draw_string(font, top.position + Vector2(16, 30), "%d%% BARE METAL" % roundi(total * 100.0), HORIZONTAL_ALIGNMENT_RIGHT,
		top.size.x - 32.0, 26, GOOD if game.all_done() else Color.WHITE)
	var bar := Rect2(top.position + Vector2(16, 42), Vector2(top.size.x - 32.0, 18))
	_bar(bar, total, GOOD if game.all_done() else METAL, game.all_done())
	draw_string(font, top.position + Vector2(16, 74), "%d of %d parts done" % [done, lines.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.7))
	# Each part, down the left.
	var row_h := 70.0
	var y := 160.0
	var rw := 420.0
	for l in lines:
		var r := Rect2(24.0, y, rw, row_h - 8.0)
		var is_done: bool = l["done"]
		var glow := clampf(float(_row_flash.get(str(l["name"]), 0.0)), 0.0, 1.0)
		draw_rect(r, Color(0.03, 0.04, 0.06, 0.74).lerp(Color(0.2, 0.5, 0.25, 0.85), glow))
		draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), GOOD if is_done else (BAD if float(l["over"]) > 0.05 else UITheme.ACCENT))
		draw_string(font, r.position + Vector2(14, 22), str(l["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		var tag := ""
		if float(l["over"]) > 0.05:
			tag = "PITTED!"
		elif is_done:
			tag = "BARE METAL"
		if tag != "":
			draw_string(font, r.position + Vector2(170, 22), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BAD if tag == "PITTED!" else GOOD)
		draw_string(font, r.position + Vector2(0, 26), "%d%%" % roundi(float(l["covered"]) * 100.0), HORIZONTAL_ALIGNMENT_RIGHT,
			r.size.x - 14.0, 26, GOOD if is_done else Color.WHITE)
		_bar(Rect2(r.position + Vector2(14, 32), Vector2(r.size.x - 28.0, 8)), float(l["covered"]), GOOD if is_done else METAL, is_done)
		var cond := "Rust %d%%   Dirt %d%%   Wear %d%%   Condition %d%%" % [roundi(float(l["rust"]) * 100.0),
			roundi(float(l["dirt"]) * 100.0), roundi(float(l["wear"]) * 100.0), roundi(float(l["health"]) * 100.0)]
		draw_string(font, r.position + Vector2(14, 56), cond, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 13,
			RUST.lerp(GOOD, 1.0 - clampf(float(l["rust"]) * 2.0, 0.0, 1.0)))
		y += row_h
	# How to work it, along the bottom.
	draw_string(font, Vector2(0, size.y - 120.0), walker.blast_controls(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.8))
	_draw_scan(font)
	_draw_cue(font)


## The scan's readout down the right: how much is still to blast, and where.
func _draw_scan(font: Font) -> void:
	if scan_view.is_empty():
		return
	var parts: Array = scan_view["parts"]
	var sides: Array = scan_view["sides"]
	var w := 340.0
	var h := 96.0 + parts.size() * 26.0 + 30.0 + sides.size() * 26.0
	var r := Rect2(size.x - w - 24.0, 160.0, w, h)
	draw_rect(r, Color(0.02, 0.06, 0.04, 0.8))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), SCAN)
	var left := float(scan_view["left"])
	draw_string(font, r.position + Vector2(14, 28), "SCAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SCAN)
	draw_string(font, r.position + Vector2(14, 28), "%d%% STILL TO BLAST" % roundi(left * 100.0) if left > 0.0005 else "ALL BARE",
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28.0, 18, Color.WHITE)
	draw_string(font, r.position + Vector2(14, 50), "Red on the engine: rust still to blast · purple: pitted", HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 28.0, 12, Color(1, 1, 1, 0.65))
	var y := r.position.y + 78.0
	for p in parts:
		_scan_row(font, r.position.x + 14.0, y, r.size.x - 28.0, str(p["name"]), float(p["left"]))
		y += 26.0
	draw_string(font, Vector2(r.position.x + 14.0, y + 10.0), "BY SIDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SCAN)
	y += 30.0
	for s in sides:
		_scan_row(font, r.position.x + 14.0, y, r.size.x - 28.0, str(s["name"]), float(s["left"]))
		y += 26.0


## One line of the scan: a name, a bar of how much is still rusty, and its percentage.
func _scan_row(font: Font, x: float, y: float, w: float, label: String, left: float) -> void:
	var c := GOOD.lerp(BAD, clampf(left * 4.0, 0.0, 1.0)) if left > 0.0005 else GOOD
	draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 14, Color.WHITE)
	var bar := Rect2(x + 136.0, y - 11.0, w - 196.0, 10.0)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(left, 0.0, 1.0), bar.size.y)), BAD)
	draw_string(font, Vector2(x, y), "%d%% left" % roundi(left * 100.0) if left > 0.0005 else "bare", HORIZONTAL_ALIGNMENT_RIGHT, w, 14, c)


## A progress bar, with a mark where a part counts as done.
func _bar(r: Rect2, frac: float, c: Color, full: bool) -> void:
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac / BlastGame.DONE if not full else 1.0, 0.0, 1.0), r.size.y)), c)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


func _draw_cue(font: Font) -> void:
	if cue.is_empty():
		return
	var engine := str(cue["kind"]) == "engine"
	var life := ENGINE_CUE_LIFE if engine else CUE_LIFE
	var age := float(cue["age"])
	var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - age * 5.0)
	var a := clampf((life - age) / 0.5, 0.0, 1.0)
	var big := (64.0 if engine else 52.0) * pop
	var c := (Color(1.0, 0.85, 0.3) if engine else GOOD)
	c.a = a
	var mid := size.y * 0.36
	var text := "ENGINE DONE!" if engine else "Bare metal!"
	var sub := "Every part back to bare metal" if engine else str(cue["name"])
	draw_string_outline(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(big), 10, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(big), c)
	draw_string_outline(font, Vector2(0, mid + 40.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 6, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(0, mid + 40.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, a))
