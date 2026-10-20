class_name DetailHud
extends Control
## The readout while you polish or ceramic coat a bike (DetailMode, DetailJob), like the
## pressure washer's (WashHud): across the top, how glossy (or how well coated) the whole bike is;
## under that, the panel the pad's on with its own figure, and a gauge: while polishing, how hot
## the paint is under the pad (keep it out of the red or it burns through); while coating, how long
## till the residue still on flashes into a smear. Then every panel with its gloss and coat, any
## burns and smears. A panel brought up to a deep gloss (or fully coated) dings and pops up its
## name; a burn-through or a smear flashes a warning.

const GOOD := Color(0.45, 0.95, 0.55)
const WARN := Color(1.0, 0.75, 0.3)
const BAD := Color(1.0, 0.32, 0.25)
const SHINE := Color(0.75, 0.85, 1.0)
const COAT := Color(0.55, 0.8, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const CUE_LIFE := 1.8
const LINGER := 1.0

var walker: Walker
var job: DetailJob
var mode: DetailMode
var cue := {}
var flash := 0.0
var _linger := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var w := walker if walker and is_instance_valid(walker) else null
	if w and w.detail.active():
		mode = w.detail
		job = w.detail.job
		_linger = LINGER
	else:
		_linger = maxf(0.0, _linger - delta)
		if _linger <= 0.0:
			mode = null
			job = null
	if w:
		while not w.detail.cues.is_empty():
			var c: Dictionary = w.detail.cues.pop_front()
			cue = {"kind": c["kind"], "name": c["name"], "age": 0.0}
			flash = 0.25 if str(c["kind"]) in ["burn", "smear"] else 0.08
	if not cue.is_empty():
		cue["age"] = float(cue["age"]) + delta
		if float(cue["age"]) > CUE_LIFE:
			cue = {}
	flash = maxf(0.0, flash - delta * 1.2)
	visible = mode != null or not cue.is_empty()
	if visible:
		queue_redraw()


## Whether the readout's taking over from the side panel.
func showing() -> bool:
	return mode != null


func _draw() -> void:
	var font := get_theme_default_font()
	if flash > 0.0:
		var bad := not cue.is_empty() and str(cue["kind"]) in ["burn", "smear"]
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.3, 0.2, flash * 0.4) if bad else Color(1, 1, 1, flash * 0.4))
	if mode != null:
		_draw_panel(font)
	_draw_cue(font)


func _draw_panel(font: Font) -> void:
	var polish := mode.mode == "polish"
	var accent := SHINE if polish else COAT
	var w := minf(660.0, size.x - 48.0)
	var top := Rect2((size.x - w) * 0.5, 96.0, w, 230.0)
	draw_rect(top, Color(0.03, 0.04, 0.06, 0.8))
	draw_rect(Rect2(top.position, Vector2(top.size.x, 3.0)), accent)
	var bike_name := str(Shed.bikes.get(mode.bike, {}).get("name", "the bike")).to_upper()
	draw_string(font, top.position + Vector2(16, 28), "%s  ·  %s" % ["POLISHING" if polish else "CERAMIC COATING", bike_name],
		HORIZONTAL_ALIGNMENT_LEFT, top.size.x * 0.62, 18, accent)
	var x := top.position.x + 16.0
	var inner := top.size.x - 32.0
	if job == null or not job.ready:
		draw_string(font, Vector2(x, top.position.y + 72.0), "Getting the %s ready..." % ("polisher" if polish else "coating kit"),
			HORIZONTAL_ALIGNMENT_LEFT, inner, 16, DIM)
		_draw_controls(font)
		return
	var st := job.stats()
	var v := float(st["gloss"] if polish else st["coat"])
	var good := Detail.GLOSS_GOOD if polish else Detail.COAT_GOOD
	draw_string(font, top.position + Vector2(16, 28), "%d%% %s" % [roundi(v * 100.0), "GLOSS" if polish else "COATED"], HORIZONTAL_ALIGNMENT_RIGHT,
		inner, 24, GOOD if v >= good else Color.WHITE)
	var bar := Rect2(top.position + Vector2(16, 38), Vector2(inner, 16))
	draw_rect(bar, Color(0.25, 0.25, 0.28, 0.7))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v, 0.0, 1.0), bar.size.y)), GOOD if v >= good else accent)
	var gx := bar.position.x + bar.size.x * good
	draw_line(Vector2(gx, bar.position.y - 3), Vector2(gx, bar.end.y + 3), Color.WHITE, 2.0)
	draw_rect(bar, Color(1, 1, 1, 0.25), false, 1.0)
	var y := top.position.y + 78.0
	if mode.settle > 0.0:
		draw_string(font, Vector2(x, y), "Getting set at the bike...", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, DIM)
	else:
		var si := int(job.pad.get("slot", -1))
		if si >= 0 and si < job.slots.size() and job.pad.get("contact", false):
			var p := job.panel(si)
			var pv := float(p["gloss"] if polish else p["coat"])
			var label := "%s  %d%% %s" % [PartsDB.slot_name(job.slots[si]), roundi(pv * 100.0), "gloss" if polish else "coated"]
			draw_string(font, Vector2(x, y), "▶ " + label, HORIZONTAL_ALIGNMENT_LEFT, inner * 0.6, 17, GOOD if pv >= good else Color.WHITE)
		elif job.pad.get("hit", false):
			draw_string(font, Vector2(x, y), "Closer: get the pad on the paint", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, WARN)
		else:
			draw_string(font, Vector2(x, y), "Aim at a painted panel", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, DIM)
	y += 14.0
	if polish:
		_draw_heat(font, Rect2(x, y, inner, 40.0))
	else:
		_draw_flash(font, Rect2(x, y, inner, 40.0))
	# Every panel: its gloss and coat, and what's gone wrong.
	var rows: Array = st["panels"]
	var cols := mini(4, maxi(1, rows.size()))
	var cw := inner / cols
	var ry := y + 64.0
	for i in mini(rows.size(), 8):
		var p: Dictionary = rows[i]
		var px := x + (i % cols) * cw
		var py := ry + (i / cols) * 20.0
		var pv := float(p["gloss"] if polish else p["coat"])
		var bits := "%s %d%%" % [str(p["name"]), roundi(pv * 100.0)]
		var c := GOOD if pv >= good else Color.WHITE
		if int(p["burns"]) > 0:
			bits += " BURNT"
			c = BAD
		elif int(p["smears"]) > 0:
			bits += " smeared"
			c = WARN
		draw_string(font, Vector2(px, py), bits, HORIZONTAL_ALIGNMENT_LEFT, cw - 6.0, 14, c)
	var note := ""
	var nc := DIM
	if int(st["burns"]) > 0:
		note = "Burnt through in %d place%s: only a respray fixes that" % [int(st["burns"]), "" if int(st["burns"]) == 1 else "s"]
		nc = BAD
	elif int(st["smears"]) > 0:
		note = "%d smear%s: polish %s off and coat again" % [int(st["smears"]), "" if int(st["smears"]) == 1 else "s",
			"it" if int(st["smears"]) == 1 else "them"]
		nc = WARN
	elif not polish and float(st["gloss"]) < Detail.GLOSS_GOOD:
		note = "Polish it first: a coat over swirls seals them in"
		nc = WARN
	elif v >= good:
		note = "Looking deep and glossy" if polish else "Coated: it'll shed the muck and wash off easy"
		nc = GOOD
	if note != "":
		draw_string(font, Vector2(x, top.end.y - 12.0), note, HORIZONTAL_ALIGNMENT_LEFT, inner, 14, nc)
	_draw_controls(font)


func _draw_controls(font: Font) -> void:
	draw_string(font, Vector2(0, size.y - 120.0), mode.controls() if mode else "", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15,
		Color(1, 1, 1, 0.8))


## How hot the paint is under the pad: cool, warm, and the red where it burns through.
func _draw_heat(font: Font, r: Rect2) -> void:
	var h := clampf(float(job.pad.get("heat", 0.0)) / DetailJob.BURN, 0.0, 1.0)
	var label := "COOL" if h < 0.45 else ("WARM: keep it moving" if h < 0.75 else "HOT! MOVE THE PAD")
	var c := GOOD if h < 0.45 else (WARN if h < 0.75 else BAD)
	draw_string(font, r.position + Vector2(0, 12), "PAINT HEAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	draw_string(font, r.position + Vector2(0, 12), label + ("  ·  leaning on it" if mode.pressing and mode.working else ""),
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 13, c)
	var g := Rect2(r.position + Vector2(0, 20), Vector2(r.size.x, 10))
	draw_rect(Rect2(g.position, Vector2(g.size.x * 0.45, g.size.y)), Color(GOOD, 0.5))
	draw_rect(Rect2(g.position + Vector2(g.size.x * 0.45, 0), Vector2(g.size.x * 0.3, g.size.y)), Color(WARN, 0.5))
	draw_rect(Rect2(g.position + Vector2(g.size.x * 0.75, 0), Vector2(g.size.x * 0.25, g.size.y)), Color(BAD, 0.6))
	draw_rect(Rect2(g.position, Vector2(g.size.x * h, g.size.y)), Color(c, 0.95))
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)


## How long till the soonest residue still on flashes into a smear.
func _draw_flash(font: Font, r: Rect2) -> void:
	var f := job.flash_left()
	var left := float(f["left"])
	draw_string(font, r.position + Vector2(0, 12), "RESIDUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	if left == INF:
		draw_string(font, r.position + Vector2(0, 12), "none on: wipe the coat on, then buff it off", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 13, DIM)
		return
	var where := PartsDB.slot_name(job.slots[int(f["slot"])]) if int(f["slot"]) >= 0 else ""
	var c := GOOD if left > DetailJob.FLASH_WARN else BAD
	draw_string(font, r.position + Vector2(0, 12), "%s flashes in %d s: buff it off" % [where, maxi(0, ceili(left))], HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x, 13, c)
	var g := Rect2(r.position + Vector2(0, 20), Vector2(r.size.x, 10))
	draw_rect(g, Color(0.25, 0.25, 0.28, 0.7))
	draw_rect(Rect2(g.position, Vector2(g.size.x * clampf(left / DetailJob.FLASH, 0.0, 1.0), g.size.y)), Color(c, 0.9))
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)


func _draw_cue(font: Font) -> void:
	if cue.is_empty():
		return
	var age := float(cue["age"])
	var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - age * 5.0)
	var a := clampf((CUE_LIFE - age) / 0.5, 0.0, 1.0)
	var name := str(cue["name"]).to_upper()
	var text := ""
	var c := Color(GOOD, a)
	match str(cue["kind"]):
		"gloss":
			text = "%s GLOSSY!" % name
		"coat":
			text = "%s COATED!" % name
		"burn":
			text = "BURNT THROUGH!"
			c = Color(BAD, a)
		"smear":
			text = "SMEAR ON THE %s!" % name
			c = Color(WARN, a)
	var px := int(38.0 * pop)
	var mid := maxf(size.y * 0.45, 380.0)
	draw_string_outline(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, 8, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(0, mid), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, c)
