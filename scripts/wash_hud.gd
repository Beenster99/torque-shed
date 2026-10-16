class_name WashHud
extends Control
## The readout while you pressure wash a bike (WashJob), like the spray gun's and the
## sandblaster's: across the top, how clean the whole bike is; under that, the part the jet's on
## with how clean it is, a gauge for how far off you're holding the lance, how clean each side of
## the bike is (the side facing you, the far side, the top and underneath: the water only takes the
## dirt off what faces it), and the dirtiest parts still to do. A part coming clean dings and pops
## up its name in the middle of the screen; the whole bike clean is a bigger moment. It's up for
## as long as the wash controls are (F with the pressure washer on a bike).

const GOOD := Color(0.45, 0.95, 0.55)
const WARN := Color(1.0, 0.75, 0.3)
const COOL := Color(0.45, 0.7, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const MUD := Color(0.62, 0.47, 0.3)
const CUE_LIFE := 1.6
const BIG_LIFE := 3.2
const LINGER := 1.5

var walker: Walker
var job: WashJob
var cue := {}             # {kind, name, age}
var flash := 0.0
var _linger := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var w := walker if walker and is_instance_valid(walker) else null
	if w and w.wash != null and not w.wash_mode.is_empty():
		job = w.wash
		_linger = LINGER
	else:
		_linger = maxf(0.0, _linger - delta)
		if _linger <= 0.0:
			job = null
	if w:
		while not w.wash_cues.is_empty():
			var c: Dictionary = w.wash_cues.pop_front()
			# A whole bike clean isn't knocked off the screen by its last part.
			if not cue.is_empty() and str(cue["kind"]) == "bike" and str(c["kind"]) != "bike":
				continue
			cue = {"kind": c["kind"], "name": c["name"], "age": 0.0}
			flash = 0.35 if str(c["kind"]) == "bike" else 0.1
	if not cue.is_empty():
		cue["age"] = float(cue["age"]) + delta
		if float(cue["age"]) > (BIG_LIFE if str(cue["kind"]) == "bike" else CUE_LIFE):
			cue = {}
	flash = maxf(0.0, flash - delta * 1.2)
	visible = job != null or not cue.is_empty()
	if visible:
		queue_redraw()


## Whether the readout's taking over from the side panel.
func showing() -> bool:
	return job != null


func _draw() -> void:
	var font := get_theme_default_font()
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.97, 1.0, flash * 0.5))
	if job != null:
		_draw_panel(font)
	_draw_cue(font)


func _draw_panel(font: Font) -> void:
	var w := minf(660.0, size.x - 48.0)
	var top := Rect2((size.x - w) * 0.5, 96.0, w, 214.0)
	draw_rect(top, Color(0.03, 0.04, 0.06, 0.8))
	draw_rect(Rect2(top.position, Vector2(top.size.x, 3.0)), COOL)
	var bike_name := str(Shed.bikes.get(job.bike, {}).get("name", "the bike")).to_upper()
	draw_string(font, top.position + Vector2(16, 28), "PRESSURE WASHING  ·  %s" % bike_name, HORIZONTAL_ALIGNMENT_LEFT, top.size.x * 0.62, 18, COOL)
	var x := top.position.x + 16.0
	var inner := top.size.x - 32.0
	if not job.ready:
		draw_string(font, Vector2(x, top.position.y + 72.0), "Getting the lance ready...", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, DIM)
		_draw_controls(font)
		return
	var st := job.stats()
	var clean := float(st["clean"])
	var all_done := job.bike_done
	draw_string(font, top.position + Vector2(16, 28), "%d%% CLEAN" % _pct(clean, all_done), HORIZONTAL_ALIGNMENT_RIGHT, inner, 24,
		GOOD if all_done else Color.WHITE)
	var bar := Rect2(top.position + Vector2(16, 38), Vector2(inner, 16))
	draw_rect(bar, Color(MUD, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(clean, 0.0, 1.0), bar.size.y)), GOOD if all_done else Color(0.78, 0.9, 1.0))
	draw_rect(bar, Color(1, 1, 1, 0.25), false, 1.0)
	# The part the jet's on.
	var y := top.position.y + 76.0
	var si := int(job.jet.get("slot", -1))
	if si >= 0 and si < job.slots.size():
		var pc := job.clean_of(si)
		var done: bool = job.done.get(si, false)
		var label := "%s  %d%% clean" % [PartsDB.slot_name(job.slots[si]), _pct(pc, done)]
		draw_string(font, Vector2(x, y), ("✓ " if done else "▶ ") + label, HORIZONTAL_ALIGNMENT_LEFT, inner * 0.6, 17, GOOD if done else Color.WHITE)
		var pb := Rect2(x + inner * 0.62, y - 12.0, inner * 0.38, 12.0)
		draw_rect(pb, Color(MUD, 0.55))
		draw_rect(Rect2(pb.position, Vector2(pb.size.x * clampf(pc, 0.0, 1.0), pb.size.y)), GOOD if done else Color(0.78, 0.9, 1.0))
		draw_rect(pb, Color(1, 1, 1, 0.25), false, 1.0)
	else:
		draw_string(font, Vector2(x, y), "Aim the lance at the bike", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, DIM)
	y += 14.0
	_draw_distance(font, Rect2(x, y, inner, 40.0))
	_draw_sides(font, Rect2(x, y + 50.0, inner, 18.0), st.get("sides", {}))
	# The dirtiest parts still to do.
	var todo := []
	for p in st["parts"]:
		if float(p["clean"]) < WashJob.PART_DONE and todo.size() < 4:
			todo.append("%s %d%%" % [p["name"], _pct(float(p["clean"]), false)])
	var left := "Still dirty: " + "  ·  ".join(todo) if not todo.is_empty() else "Every part's clean!"
	draw_string(font, Vector2(x, top.end.y - 14.0), left, HORIZONTAL_ALIGNMENT_LEFT, inner, 14, WARN if not todo.is_empty() else GOOD)
	_draw_controls(font)


func _draw_controls(font: Font) -> void:
	draw_string(font, Vector2(0, size.y - 120.0), walker.wash_controls() if walker else "", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15,
		Color(1, 1, 1, 0.8))


## A percentage that only shows 100 once it's really done (99 until then).
static func _pct(v: float, done: bool) -> int:
	return 100 if done else mini(99, roundi(v * 100.0))


## How far off you're holding the lance: too close (a tiny spot), the sweet spot, losing its bite,
## out of reach.
func _draw_distance(font: Font, r: Rect2) -> void:
	var span := WashJob.OUT + 0.4
	var hit: bool = job.jet.get("hit", false)
	var dist := float(job.jet.get("dist", span)) if hit else span
	var zone := str(job.jet.get("zone", "out")) if hit else "out"
	var label: String = {"good": "GOOD", "close": "VERY CLOSE: a tiny spot", "far": "TOO FAR: losing its bite", "out": "OUT OF REACH"}.get(zone, "")
	var c: Color = {"good": GOOD, "close": WARN, "far": COOL, "out": DIM}.get(zone, DIM)
	draw_string(font, r.position + Vector2(0, 12), "DISTANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	draw_string(font, r.position + Vector2(0, 12), "%.2f m  %s" % [dist, label] if zone != "out" else label, HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x, 13, c)
	var g := Rect2(r.position + Vector2(0, 20), Vector2(r.size.x, 10))
	var px := func(m: float) -> float: return g.position.x + g.size.x * clampf(m / span, 0.0, 1.0)
	draw_rect(Rect2(g.position, Vector2(px.call(WashJob.NEAR) - g.position.x, g.size.y)), Color(WARN, 0.6))
	draw_rect(Rect2(Vector2(px.call(WashJob.NEAR), g.position.y), Vector2(px.call(WashJob.FAR) - px.call(WashJob.NEAR), g.size.y)), Color(GOOD, 0.8))
	draw_rect(Rect2(Vector2(px.call(WashJob.FAR), g.position.y), Vector2(px.call(WashJob.OUT) - px.call(WashJob.FAR), g.size.y)), Color(COOL, 0.6))
	draw_rect(Rect2(Vector2(px.call(WashJob.OUT), g.position.y), Vector2(g.end.x - px.call(WashJob.OUT), g.size.y)), Color(0.3, 0.3, 0.3, 0.6))
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)
	var mx: float = px.call(dist)
	draw_colored_polygon(PackedVector2Array([Vector2(mx - 6, g.position.y - 7), Vector2(mx + 6, g.position.y - 7), Vector2(mx, g.position.y + 1)]), Color.WHITE)
	draw_line(Vector2(mx, g.position.y), Vector2(mx, g.end.y), Color.WHITE, 2.0)


## How clean each side of the bike is: the side facing you, the far side, the top and underneath.
## The worst still to do is lit.
func _draw_sides(font: Font, r: Rect2, sides: Dictionary) -> void:
	var names := [["near", "THIS SIDE"], ["far", "FAR SIDE"], ["top", "TOP"], ["under", "UNDERNEATH"]]
	var shown := []
	var worst := ""
	var low := 2.0
	for n in names:
		var v := float(sides.get(n[0], -1.0))
		if v < 0.0:
			continue
		shown.append([n[1], v])
		if v < low:
			low = v
			worst = n[1]
	if shown.is_empty():
		return
	var w := r.size.x / shown.size()
	for i in shown.size():
		var v: float = shown[i][1]
		var c := GOOD if v >= WashJob.PART_DONE else (WARN if shown[i][0] == worst else Color.WHITE)
		draw_string(font, Vector2(r.position.x + i * w, r.end.y), "%s %d%%" % [shown[i][0], _pct(v, v >= 0.9995)],
			HORIZONTAL_ALIGNMENT_CENTER, w, 14, c)


func _draw_cue(font: Font) -> void:
	if cue.is_empty():
		return
	var age := float(cue["age"])
	var big := str(cue["kind"]) == "bike"
	var life := BIG_LIFE if big else CUE_LIFE
	var pop := 1.0 + (0.45 if big else 0.3) * maxf(0.0, 1.0 - age * 5.0)
	var a := clampf((life - age) / 0.5, 0.0, 1.0)
	var c := Color(1.0, 0.88, 0.35, a) if big else Color(GOOD, a)
	var text := "SPOTLESS!" if big else "%s CLEAN!" % str(cue["name"]).to_upper()
	var px := int((64.0 if big else 38.0) * pop)
	var mid := maxf(size.y * 0.45, 380.0)
	draw_string_outline(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, 8, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, c)
	if big:
		var sub := "%s is clean as a whistle" % str(cue["name"])
		draw_string_outline(font, Vector2(0, mid + 40.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 6, Color(0, 0, 0, a * 0.7))
		draw_string(font, Vector2(0, mid + 40.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, a))
