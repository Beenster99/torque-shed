class_name SprayHud
extends Control
## The readout while you spray a coat on by hand (SprayJob), like the sandblaster's (BlastHud):
## across the top, how much of the part is covered (with the mark where the coat counts as on),
## how even it's going on and how much has run, gone on dry or is still thin; under that, gauges
## for how far off you're holding it (the sweet spot in green) and how fast you're sweeping; then
## how much of each side of it is covered (the side facing you, the far side, the top and
## underneath: paint only lands on what faces the gun, so you have to go round it); then the
## part's coats in order (primer, colour, lacquer) with the one going on now. Runs, dry spray,
## the coat being on and the coat done pop up in the middle of the screen. It's up for as long as
## the spray controls are (F on a part with the can or gun): first a moment to get set, then the
## trigger works; a breath bar shows how long you can hold your hand steady.

const GOOD := Color(0.45, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.35)
const WARN := Color(1.0, 0.75, 0.3)
const COOL := Color(0.45, 0.7, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const CUE_LIFE := 1.8
const LINGER := 2.2

var walker: Walker
var job: SprayJob
var cue := {}             # {kind, text, age}
var flash := 0.0
var _linger := 0.0        # seconds the readout stays up after a coat's done


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var w := walker if walker and is_instance_valid(walker) else null
	var live: SprayJob = w.spray if w and w.spray != null and (w.spray.live or not w.spray_mode.is_empty()) else null
	if live != null:
		job = live
		_linger = LINGER
	else:
		_linger = maxf(0.0, _linger - delta)
		if _linger <= 0.0:
			job = null
	if w:
		while not w.spray_cues.is_empty():
			var c: Dictionary = w.spray_cues.pop_front()
			cue = {"kind": c["kind"], "text": c["text"], "age": 0.0}
			if str(c["kind"]) in ["done", "ready"]:
				flash = 0.25 if str(c["kind"]) == "done" else 0.12
	if not cue.is_empty():
		cue["age"] = float(cue["age"]) + delta
		if float(cue["age"]) > CUE_LIFE:
			cue = {}
	flash = maxf(0.0, flash - delta * 1.4)
	visible = job != null or not cue.is_empty()
	if visible:
		queue_redraw()


## Whether the readout's taking over from the side panel.
func showing() -> bool:
	return job != null


func _draw() -> void:
	var font := get_theme_default_font()
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 0.96, flash * 0.5))
	if job != null:
		_draw_panel(font)
	_draw_cue(font)


func _draw_panel(font: Font) -> void:
	var st: Dictionary = job.last if not job.last.is_empty() else job.stats()
	var covered := float(st["covered"])
	var ready := covered >= SprayJob.DONE
	var a: Dictionary = job.plan.get("action", {})
	var what: String = {"primer": "PRIMER", "clear": "LACQUER"}.get(job.layer, "COLOUR")
	var load_name := walker.spray_text().to_upper() if walker else ""
	var w := minf(660.0, size.x - 48.0)
	var top := Rect2((size.x - w) * 0.5, 96.0, w, 220.0)
	draw_rect(top, Color(0.03, 0.04, 0.06, 0.8))
	draw_rect(Rect2(top.position, Vector2(top.size.x, 3.0)), UITheme.ACCENT)
	var title := "SPRAYING %s  ·  %s" % [what, load_name] if job.layer != "paint" or str(a.get("a", "")) == "coat" else "SPRAYING  ·  %s" % load_name
	draw_string(font, top.position + Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, top.size.x * 0.62, 18, UITheme.ACCENT)
	draw_string(font, top.position + Vector2(16, 28), "%d%% COVERED" % roundi(covered * 100.0), HORIZONTAL_ALIGNMENT_RIGHT,
		top.size.x - 32.0, 24, GOOD if ready else Color.WHITE)
	var bar := Rect2(top.position + Vector2(16, 38), Vector2(top.size.x - 32.0, 16))
	draw_rect(bar, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(covered, 0.0, 1.0), bar.size.y)), GOOD if ready else Color(0.78, 0.86, 0.95))
	var mark := bar.position.x + bar.size.x * SprayJob.DONE
	draw_line(Vector2(mark, bar.position.y - 3), Vector2(mark, bar.end.y + 3), Color.WHITE, 2.0)
	draw_rect(bar, Color(1, 1, 1, 0.25), false, 1.0)
	var part := Shed.item_title(job.item)
	draw_string(font, top.position + Vector2(16, 72), part, HORIZONTAL_ALIGNMENT_LEFT, top.size.x * 0.45, 14, DIM)
	draw_string(font, top.position + Vector2(16, 72), "Let go to finish the coat" if ready else "On at %d%%" % roundi(SprayJob.DONE * 100.0),
		HORIZONTAL_ALIGNMENT_RIGHT, top.size.x - 32.0, 14, GOOD if ready else DIM)
	# Evenness, and what's spoiling it.
	var even := float(st["even"])
	var y := top.position.y + 92.0
	var x := top.position.x + 16.0
	var inner := top.size.x - 32.0
	draw_string(font, Vector2(x, y + 11), "EVENNESS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	var eb := Rect2(x + 86.0, y, inner * 0.42, 12.0)
	draw_rect(eb, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(eb.position, Vector2(eb.size.x * clampf(even, 0.0, 1.0), eb.size.y)), BAD.lerp(GOOD, clampf((even - 0.5) * 2.0, 0.0, 1.0)))
	draw_rect(eb, Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(font, Vector2(eb.end.x + 8.0, y + 11), "%d%%" % roundi(even * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var faults := "Runs %d%%   Dry %d%%   Thin %d%%" % [roundi(float(st["runs"]) * 100.0), roundi(float(st["dry"]) * 100.0),
		roundi(float(st["thin"]) * 100.0)]
	var fc := BAD if float(st["runs"]) > 0.02 else (COOL if float(st["dry"]) > 0.03 else DIM)
	draw_string(font, Vector2(x, y + 11), faults, HORIZONTAL_ALIGNMENT_RIGHT, inner, 14, fc)
	# How far off you're holding it, and how fast you're sweeping.
	y += 30.0
	var half := (inner - 20.0) * 0.5
	_draw_distance(font, Rect2(x, y, half, 54.0))
	_draw_pace(font, Rect2(x + half + 20.0, y, half, 54.0))
	_draw_sides(font, Rect2(x, top.end.y - 26.0, inner, 18.0), st.get("sides", {}))
	# The coats in order, under the panel.
	_draw_steps(font, Rect2(top.position.x, top.end.y + 8.0, top.size.x, 34.0))
	draw_string(font, Vector2(0, size.y - 120.0), walker.spray_controls() if walker else "", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15,
		Color(1, 1, 1, 0.8))
	if walker and not walker.spray_mode.is_empty():
		_draw_getting_set(font)


## Getting set before the trigger works, then how long you can hold your hand steady.
func _draw_getting_set(font: Font) -> void:
	var m: Dictionary = walker.spray_mode
	var mid := Vector2(size.x * 0.5, size.y * 0.5 + 70.0)
	if walker.spray_settling():
		var f := 1.0 - float(m["settle"]) / Walker.SPRAY_SETTLE
		draw_string_outline(font, Vector2(0, mid.y), "Get set...", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 6, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0, mid.y), "Get set...", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color.WHITE)
		var bar := Rect2(mid.x - 90.0, mid.y + 10.0, 180.0, 6.0)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), UITheme.ACCENT)
		return
	if job != null and not job.live:
		draw_string_outline(font, Vector2(0, mid.y), "Ready: hold to spray", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 5, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, mid.y), "Ready: hold to spray", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, GOOD)
	var breath := float(m.get("breath", 1.0))
	var steady := bool(m.get("steady", false))
	var b := Rect2(mid.x - 60.0, mid.y + 14.0, 120.0, 5.0)
	draw_rect(b, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(b.position, Vector2(b.size.x * breath, b.size.y)), (GOOD if steady else COOL) if breath > 0.2 else WARN)
	draw_string(font, Vector2(0, b.end.y + 14.0), "steady" if steady else "breath", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, DIM)


## The distance gauge: too close (red), the sweet spot (green), too far (blue, dry), out of reach.
func _draw_distance(font: Font, r: Rect2) -> void:
	var sweet := job.sweet()
	var span := sweet.y + SprayJob.OUT + 0.3
	var dist := float(job.jet.get("dist", 0.0)) if job.jet.get("hit", false) else span
	var zone := str(job.jet.get("zone", "out")) if job.jet.get("hit", false) else "out"
	var label: String = {"good": "GOOD", "close": "TOO CLOSE: it'll run", "far": "TOO FAR: it'll go on dry", "out": "OUT OF REACH"}.get(zone, "")
	if not job.jet.get("hit", false):
		label = "OFF THE PART"
	var c: Color = {"good": GOOD, "close": BAD, "far": COOL, "out": DIM}.get(zone, DIM)
	draw_string(font, r.position + Vector2(0, 12), "DISTANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	draw_string(font, r.position + Vector2(0, 12), "%.2f m  %s" % [dist, label] if zone != "out" else label, HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x, 13, c)
	var g := Rect2(r.position + Vector2(0, 22), Vector2(r.size.x, 12))
	var px := func(m: float) -> float: return g.position.x + g.size.x * clampf(m / span, 0.0, 1.0)
	draw_rect(Rect2(g.position, Vector2(px.call(sweet.x) - g.position.x, g.size.y)), Color(BAD, 0.7))
	draw_rect(Rect2(Vector2(px.call(sweet.x), g.position.y), Vector2(px.call(sweet.y) - px.call(sweet.x), g.size.y)), Color(GOOD, 0.8))
	draw_rect(Rect2(Vector2(px.call(sweet.y), g.position.y), Vector2(px.call(sweet.y + SprayJob.OUT) - px.call(sweet.y), g.size.y)), Color(COOL, 0.6))
	draw_rect(Rect2(Vector2(px.call(sweet.y + SprayJob.OUT), g.position.y), Vector2(g.end.x - px.call(sweet.y + SprayJob.OUT), g.size.y)),
		Color(0.3, 0.3, 0.3, 0.6))
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)
	_marker(px.call(dist), g)
	draw_string(font, Vector2(g.position.x, g.end.y + 14), "close", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(font, Vector2(g.position.x, g.end.y + 14), "far", HORIZONTAL_ALIGNMENT_RIGHT, g.size.x, 11, DIM)


## The pace gauge: lingering (amber, it piles on), steady (green), too fast (blue, it goes on thin).
func _draw_pace(font: Font, r: Rect2) -> void:
	var span := SprayJob.FAST * 1.6
	var speed := float(job.jet.get("speed", 0.0))
	var pace := str(job.jet.get("pace", "good"))
	var label: String = {"good": "STEADY", "slow": "LINGERING: it'll run", "fast": "TOO FAST: it'll go on thin"}.get(pace, "")
	var c: Color = {"good": GOOD, "slow": WARN, "fast": COOL}.get(pace, DIM)
	draw_string(font, r.position + Vector2(0, 12), "PACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	if not job.jet.get("hit", false):
		label = ""
		c = DIM
	draw_string(font, r.position + Vector2(0, 12), "%.1f m/s  %s" % [speed, label] if label != "" else "-", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 13, c)
	var g := Rect2(r.position + Vector2(0, 22), Vector2(r.size.x, 12))
	var px := func(v: float) -> float: return g.position.x + g.size.x * clampf(v / span, 0.0, 1.0)
	draw_rect(Rect2(g.position, Vector2(px.call(SprayJob.SLOW) - g.position.x, g.size.y)), Color(WARN, 0.7))
	draw_rect(Rect2(Vector2(px.call(SprayJob.SLOW), g.position.y), Vector2(px.call(SprayJob.FAST) - px.call(SprayJob.SLOW), g.size.y)), Color(GOOD, 0.8))
	draw_rect(Rect2(Vector2(px.call(SprayJob.FAST), g.position.y), Vector2(g.end.x - px.call(SprayJob.FAST), g.size.y)), Color(COOL, 0.6))
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)
	_marker(px.call(speed), g)
	draw_string(font, Vector2(g.position.x, g.end.y + 14), "slow", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(font, Vector2(g.position.x, g.end.y + 14), "fast", HORIZONTAL_ALIGNMENT_RIGHT, g.size.x, 11, DIM)


## How much of each side of the part is covered: the side facing you, the far side, the top and
## underneath (a side with none of the part on it is left out). The worst still to do is lit.
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
		var c := GOOD if v >= SprayJob.DONE else (WARN if shown[i][0] == worst else Color.WHITE)
		draw_string(font, Vector2(r.position.x + i * w, r.end.y), "%s %d%%" % [shown[i][0], roundi(v * 100.0)],
			HORIZONTAL_ALIGNMENT_CENTER if shown.size() > 1 else HORIZONTAL_ALIGNMENT_LEFT, w, 14, c)


func _marker(at_x: float, g: Rect2) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(at_x - 6, g.position.y - 7), Vector2(at_x + 6, g.position.y - 7), Vector2(at_x, g.position.y + 1)]), Color.WHITE)
	draw_line(Vector2(at_x, g.position.y), Vector2(at_x, g.end.y), Color.WHITE, 2.0)


## Primer (optional), colour, lacquer (optional): done, going on now, or still to do.
func _draw_steps(font: Font, r: Rect2) -> void:
	var steps := job.steps()
	var gap := 10.0
	var w := (r.size.x - gap * (steps.size() - 1)) / steps.size()
	for i in steps.size():
		var s: Dictionary = steps[i]
		var box := Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		var state := str(s["state"])
		var bg := Color(0.03, 0.04, 0.06, 0.75)
		var edge := Color(1, 1, 1, 0.2)
		var text := str(s["name"]).to_upper()
		var sub := "optional" if s["optional"] else ""
		var col := DIM
		match state:
			"now":
				edge = UITheme.ACCENT
				col = Color.WHITE
				var st: Dictionary = job.last if not job.last.is_empty() else job.stats()
				sub = "now: %d%%" % roundi(float(st["covered"]) * 100.0)
			"done":
				edge = GOOD
				col = GOOD
				sub = "done %d%%" % roundi(float(s["q"]) * 100.0)
			"skip":
				sub = "skipped"
		draw_rect(box, bg)
		draw_rect(box, edge, false, 2.0 if state == "now" else 1.0)
		draw_string(font, box.position + Vector2(10, 22), ("✓ " if state == "done" else ("▶ " if state == "now" else "")) + text,
			HORIZONTAL_ALIGNMENT_LEFT, w * 0.55, 15, col)
		draw_string(font, box.position + Vector2(0, 22), sub, HORIZONTAL_ALIGNMENT_RIGHT, w - 10.0, 13, col if state != "todo" else DIM)
		if i < steps.size() - 1:
			draw_string(font, Vector2(box.end.x + 1.0, box.position.y + 23), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM)


func _draw_cue(font: Font) -> void:
	if cue.is_empty():
		return
	var age := float(cue["age"])
	var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - age * 5.0)
	var a := clampf((CUE_LIFE - age) / 0.5, 0.0, 1.0)
	var kind := str(cue["kind"])
	var c: Color = {"runs": BAD, "dry": COOL, "ready": GOOD, "done": Color(1.0, 0.85, 0.3)}.get(kind, Color.WHITE)
	c.a = a
	var big := (46.0 if kind == "done" else 36.0) * pop
	var mid := maxf(size.y * 0.45, 390.0)   # under the panel and its coat steps
	draw_string_outline(font, Vector2(0, mid), str(cue["text"]), HORIZONTAL_ALIGNMENT_CENTER, size.x, int(big), 8, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(0, mid), str(cue["text"]), HORIZONTAL_ALIGNMENT_CENTER, size.x, int(big), c)
