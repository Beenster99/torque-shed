class_name BikeRig
## The Rig built look's layout: where a bike's engine, backbone, tank, seat, tail and pegs go,
## worked out from the parts fitted and the eight lines of the style it's built as
## (data/bike_lines.json, measured from real bikes). The engine goes in first, with its gearbox's
## output shaft just ahead of the frame's swingarm pivot; the backbone runs over its heads; the
## tank sits on the backbone with its top no higher than the style allows over the top yoke; the
## seat, tail, rider and pegs follow the style's seat line and rider triangle.
##
## It only changes the picture. The wheelbase, rake, fork, swingarm pivot and seat height are the
## catalogue's (BikeBuild's), the same in both looks, so the bike rides as it always did and
## players on different looks ride together. It's worked out from the parts alone, so a co-op
## host and guest draw the same bike, and it's kept per build (solve) so a bike is solved once.
##
## The fit report (fit) says how the engine and frame go together: "bolts on", "fabricate" (with
## what the shed would have to make) or "won't fit".
## See /mnt/project-files/torque-shed/bike-look/lines-agreement.md for the keys solve returns.

const LINES_PATH := "res://data/bike_lines.json"
const TIER_BOLTS := "bolts on"
const TIER_FAB := "fabricate"
const TIER_NO := "won't fit"
## The backbone's radius, which the tank's tunnel straddles (m).
const SPINE_R := 0.03
## How far the barrels and head stand above the base of the barrel as drawn at full size (see
## BikeModel._place_cylinders: 0.1 of engine size up the barrel, then the head's 0.215 reach).
const BARREL_FOOT := 0.1
const HEAD_REACH := 0.215
## The case's top above the crank, at engine size 1 (BikeModel draws the case 0.13 up, the
## barrels from 0.14).
const DECK := 0.14
## The shortest the top end is drawn against its full size (the rest is real proportion).
const HEAD_K_MIN := 0.62
## How far over a style's tank line the tank may stand before it needs raised mounts made (m).
const TANK_HIGH := 0.12
## How short a tank may be drawn to sit on its style's lines, as a share of its own length.
const TANK_SQUEEZE := 0.75
## How far a full race fairing's belly pan hangs below the cases it's sized round (m).
const BELLY_PAN := 0.07
## The frames whose seat post runs from under the seat's nose down to the pivot, behind the
## engine (see BikeModel._draw_frame), and the room it takes behind the heads (m).
const POST_FAMILIES := ["cradle", "softail", "chopper", "cruiser"]
const POST_CLEAR := 0.07
## Where the gearbox's output shaft (the front sprocket) sits from the crank, at engine size 1:
## behind it, near the back of the cases, and a little up.
const OUTPUT_BACK := 0.17
const OUTPUT_UP := 0.03
const OUTPUT_BACK_VTWIN := 0.22
## The engines each frame family takes as it comes: layouts, and the biggest it's made for (cc).
## Outside that the shed has to make something (see fit); a boxer's barrels can't go through the
## loops of an MX frame or a perimeter's beams at all.
const FAMILY := {
	"cradle": {"layouts": ["single", "twin", "parallel", "triple", "inline", "boxer", "vtwin", "2stroke"], "cc": 1300.0},
	"backbone": {"layouts": ["single", "twin", "parallel", "triple", "boxer", "vtwin", "2stroke"], "cc": 1300.0},
	"trestle": {"layouts": ["single", "twin", "parallel", "triple", "inline", "vtwin"], "cc": 1300.0},
	"spar": {"layouts": ["twin", "parallel", "triple", "inline", "vtwin"], "cc": 1400.0},
	"perimeter": {"layouts": ["twin", "parallel", "triple", "inline", "vtwin"], "cc": 1300.0},
	"adv": {"layouts": ["single", "twin", "parallel", "triple", "inline", "boxer", "vtwin"], "cc": 1300.0},
	"mx": {"layouts": ["single", "2stroke"], "cc": 700.0},
	"softail": {"layouts": ["vtwin"], "cc": 2000.0},
	"chopper": {"layouts": ["vtwin"], "cc": 2000.0},
	"cruiser": {"layouts": ["vtwin", "boxer", "inline"], "cc": 2000.0},
}
const NO_FIT := {"mx": ["boxer", "inline", "triple"], "perimeter": ["boxer"], "spar": ["boxer"]}

## Off lays the Rig built look out as Classic does (for the checks that compare the two looks'
## drawing, part for part).
static var on := true
static var _lines := {}
static var _cache := {}


## The eight lines of every style (data/bike_lines.json's "styles").
static func lines() -> Dictionary:
	if _lines.is_empty():
		var f := FileAccess.open(LINES_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_lines = d.get("styles", {}) if d is Dictionary else {}
	return _lines


## The style whose lines a bike is laid out to: what its parts add up to, as long as its frame
## suits that style, else the frame's own first style.
static func style_for(parts: Dictionary) -> String:
	var frame := PartsDB.get_part(str(parts.get("frame", "")))
	var own: Array = frame.get("styles", [])
	var best := str(PartsDB.detect_style(parts).get("style", ""))
	if best != "" and (own.is_empty() or own.has(best)) and lines().has(best):
		return best
	for st in own:
		if lines().has(str(st)):
			return str(st)
	return "classic"


## Engine size relative to a 700 cc, as BikeModel draws it.
static func engine_scale(displacement: float) -> float:
	return clampf(pow(displacement / 700.0, 0.3), 0.55, 1.2)


## How tall a real engine's top end stands above its crank, along the barrel (m): half the stroke,
## a rod of about 1.7 strokes, the piston's crown and a head of about 1.45 bores.
static func real_top(bore_mm: float, stroke_mm: float) -> float:
	var b := bore_mm / 1000.0
	var s := stroke_mm / 1000.0
	return s * 0.5 + 1.7 * s + 0.45 * b + 1.45 * b


## How long the barrels and heads are drawn (BikeModel's _head_k) so the top end stands its real
## height above the crank. A boxer's lie flat and keep their size; a two-stroke's short head is
## drawn as it is.
static func head_k(engine: Dictionary) -> float:
	var layout := str(engine.get("layout", "parallel"))
	if layout in ["boxer", "2stroke"]:
		return 1.0
	var s := engine_scale(float(engine.get("displacement", 700.0)))
	var want := real_top(float(engine.get("bore", 80.0)), float(engine.get("stroke", 70.0)))
	return clampf((want - DECK * s) / (BARREL_FOOT * s + HEAD_REACH), HEAD_K_MIN, 1.0)


## The engine's hard points, in its own space (metres, the crank at the origin, -Z forward, as the
## model), as BikeModel draws it in the Rig built look. Named in the lines agreement.
static func hard_points(engine: Dictionary) -> Dictionary:
	var layout := str(engine.get("layout", "parallel"))
	var cyl := int(engine.get("cylinders", 2))
	var s := engine_scale(float(engine.get("displacement", 700.0)))
	var k := head_k(engine)
	var bore_r := clampf(float(engine.get("bore", 80.0)) * 0.0006, 0.022, 0.062)
	var block_w := (0.2 + 0.11 * (cyl - 1)) * s
	var tops := []
	var ups := []
	match layout:
		"vtwin":
			block_w = 0.22 * s
			var v := float(engine.get("v_angle", 0.0))
			var half := deg_to_rad(v) * 0.5 if v > 0.0 and v < 90.0 else PI / 8.0
			for dir in [-1.0, 1.0]:
				var up := Vector3(0.0, cos(half), sin(half) * dir) * k
				var base := Vector3(0.0, 0.13 * s, 0.07 * dir * s) + up * 0.12 * s
				ups.append(up)
				tops.append(base + up * HEAD_REACH)
		"boxer":
			block_w = 0.24 * s
			for dir in [-1.0, 1.0]:
				var up := Vector3(dir, 0.08, -0.05).normalized()
				var base := Vector3(0.1 * dir * s, 0.03, -0.06) + up * 0.1 * s
				ups.append(up)
				tops.append(base + up * 0.235)
		_:
			var lean := {"twin": 0.04, "2stroke": 0.4}.get(layout, 0.25) as float
			var up := Vector3(0.0, 1.0, -lean).normalized() * k
			var reach := 0.145 if layout == "2stroke" else HEAD_REACH
			for c in cyl:
				var cx := (c - (cyl - 1) * 0.5) * maxf(0.12 * s, bore_r * 2.4)
				var base := Vector3(cx, DECK * s, -0.04) + up * BARREL_FOOT * s
				ups.append(up)
				tops.append(base + up * reach)
	var head_y := DECK * s
	var front := -0.17 * s
	var back := 0.17 * s
	var head_w := block_w * 0.5
	for t: Vector3 in tops:
		head_y = maxf(head_y, t.y)
		front = minf(front, t.z - 0.08)
		head_w = maxf(head_w, absf(t.x) + (0.03 if layout == "boxer" else 0.07))
	var out := {
		"crank": Vector3.ZERO,
		# (A big V-twin's gearbox is a separate case behind the engine, so its output sits further back.)
		"output": Vector3(-0.125, OUTPUT_UP * s, (OUTPUT_BACK_VTWIN if layout == "vtwin" else OUTPUT_BACK) * s),
		"head_top": tops,
		"head_front": Vector3(0.0, head_y, front),
		"head_rear": Vector3(0.0, head_y, maxf(back, tops.map(func(t): return (t as Vector3).z + 0.08).max() if not tops.is_empty() else back)),
		"case_front": Vector3(0.0, 0.0, -0.17 * s),
		"case_rear": Vector3(0.0, 0.0, 0.17 * s),
		"sump": Vector3(0.0, -0.13 * s - 0.059, -0.01),
		"case_half_w": block_w * 0.5,
		"head_half_w": head_w,
		"intake": [],
		"exhaust": [],
		"mount_fu": Vector3(0.0, 0.1 * s, -0.15 * s),
		"mount_fl": Vector3(0.0, -0.1 * s, -0.15 * s),
		"mount_ru": Vector3(0.0, 0.1 * s, 0.16 * s),
		"mount_rl": Vector3(0.0, -0.1 * s, 0.16 * s),
		"head_steady": Vector3(0.0, head_y + 0.01, 0.0),
		"airbox_top": Vector3(0.0, head_y + 0.02, 0.06),
		"top_y": head_y,
		"k": k,
		"scale": s,
	}
	for i in tops.size():
		var t: Vector3 = tops[i]
		var up: Vector3 = (ups[i] as Vector3).normalized()
		out["intake"].append({"at": t - up * 0.05 + Vector3(0.0, 0.0, 0.06), "dir": Vector3(0.0, 0.3, 1.0).normalized()})
		out["exhaust"].append({"at": t - up * 0.06 + Vector3(0.0, 0.0, -0.06), "dir": Vector3(0.0, -0.3, -1.0).normalized()})
	return out


## The bike laid out in the Rig built look: datums in the model's space (see the lines agreement
## for each key). Worked out once per set of parts and kept.
static func solve(build: BikeBuild) -> Dictionary:
	var key := JSON.stringify(build.parts) + "|%.4f|%.4f|%.4f|%.4f|%.4f" % [build.wheelbase, build.rake_deg, build.fork_length, build.seat_height, build.rear_radius]
	if _cache.has(key):
		return _cache[key]
	var r := _solve(build)
	if _cache.size() > 256:
		_cache.clear()
	_cache[key] = r
	return r


static func _solve(build: BikeBuild) -> Dictionary:
	var parts := build.parts
	var style := style_for(parts)
	var l: Dictionary = lines()[style]["lines"]
	var frame := PartsDB.get_part(str(parts.get("frame", "")))
	var geo: Dictionary = frame.get("geo", {})
	var family := str(frame.get("style", "cradle"))
	var engine := PartsDB.get_part(str(parts.get("engine", "")))
	var wb := build.wheelbase
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var ground := -build.rear_radius
	var at_u := func(u: float) -> float: return zf + u * wb
	var rake := deg_to_rad(build.rake_deg)
	var axis := Vector3(0.0, cos(rake), sin(rake))
	var head := Vector3(0.0, 0.0, zf) + axis * build.fork_length
	var head_bottom := head - axis * 0.16
	var pivot := Vector3(0.0, float(geo.get("pivot_y", 0.16)), zr - float(geo.get("arm", 0.6)))
	var seat_y := build.seat_height - build.rear_radius
	var notes := []

	# 6: the engine, its output shaft just ahead of the pivot; 8: its sump at the style's ground
	# clearance (which sets its height: the pivot then sits over the output shaft as the frame
	# has it), but never so low the output shaft drops far under the pivot's line.
	var hp := hard_points(engine)
	var s := float(hp["scale"])
	var drive: Dictionary = l["6_drive"]
	var out_z := pivot.z - float(drive["countershaft_ahead_mm"]) / 1000.0
	var crank := Vector3(0.0, 0.0, out_z - (hp["output"] as Vector3).z)
	var clear := float(l["8_ground"]["clear_mm"]) / 1000.0
	var clear_min := clear - float(l["8_ground"]["tol_mm"]) / 1000.0
	# (A little over the line: the exhaust's collector and the stand hang below the sump.)
	crank.y = ground + clear + 0.02 - (hp["sump"] as Vector3).y
	crank.y = maxf(crank.y, pivot.y - 0.15 - (hp["output"] as Vector3).y)
	# A full race fairing's belly pan hangs under the cases (until the fairings are fitted to the
	# belly line, H4): the engine sits that much higher so the pan, not the sump, is at the line.
	var fairing := PartsDB.get_part(str(parts.get("fairing", "none")))
	if str(fairing.get("style", "")) == "race" and str((fairing.get("look", {}) as Dictionary).get("shape", "race")) != "seeley":
		crank.y += BELLY_PAN
	# 7: the cases and heads clear of the front tyre, the fork fully compressed.
	var front_clear := float(l["7_front"]["clear_mm"]) / 1000.0
	var travel := 0.1
	var wheel := Vector3(0.0, build.front_radius - build.rear_radius, zf) + axis * travel
	var nearest := INF
	for p: Vector3 in [hp["case_front"], hp["sump"]]:
		nearest = minf(nearest, (crank + p - wheel).length() - build.front_radius)
	var heads_y := crank.y + float(hp["top_y"])
	var heads_z := crank.z
	for t: Vector3 in hp["head_top"]:
		if crank.y + t.y >= heads_y - 0.001:
			heads_z = crank.z + t.z
	# What the backbone (or a spar frame's airbox lid) has to pass over: each head, front and back.
	# (A bay frame's single backbone is a tube, whatever the style's own backbone is.)
	var tube := str(l["1_backbone"].get("kind", "tube")) == "tube" or family in POST_FAMILIES
	var spine_r := SPINE_R if tube else 0.0
	var clear_over := float(l["1_backbone"]["clear_mm"]) / 1000.0 + spine_r * 2.0
	var over_heads := []
	for t: Vector3 in hp["head_top"]:
		over_heads.append(Vector3(0.0, crank.y + t.y + clear_over, crank.z + t.z))
	if over_heads.is_empty():
		over_heads.append(Vector3(0.0, heads_y + clear_over, heads_z))

	# 1: the backbone over the heads, at the style's clearance; 2: the tank on it, its top no
	# higher than the style allows over the top yoke; 3: its tail meeting the seat's nose.
	var t2: Dictionary = l["2_tank"]
	var t3: Dictionary = l["3_tank_seat"]
	var t4: Dictionary = l["4_seat"]
	var spine_over := heads_y + float(l["1_backbone"]["clear_mm"]) / 1000.0 + spine_r
	var tank := PartsDB.get_part(str(parts.get("tank", "")))
	var tank_look: Dictionary = tank.get("look", {})
	var shape: Dictionary = BikeModel.TANK_SHAPES.get(str(tank_look.get("shape", tank.get("style", "cafe"))), BikeModel.TANK_SHAPES["cafe"])
	var size := pow(float(tank.get("capacity", 15.0)) / 15.0, 0.33)
	var sc_z := 1.0
	if tank_look.get("scale") is Array and (tank_look["scale"] as Array).size() >= 3:
		sc_z = float(tank_look["scale"][2])
	var tall := 0.0
	var keys: Array = shape["keys"]
	for k in keys:
		tall = maxf(tall, (float(k[2]) + float(k[3])) * size * sc_z)
	var end_k: Array = keys[keys.size() - 1]
	var end_h := (float(end_k[2]) + float(end_k[3])) * size * sc_z
	var top_max := head.y + float(t2["top_over_yoke_mm"]) / 1000.0
	var nose := head + Vector3(0.0, -0.03, float(t2["nose_behind_axis_mm"]) / 1000.0)
	var seat_front_z: float = at_u.call(float(t4["front_u"]))
	var rear_z: float = at_u.call(float(t3["tank_rear_u"]))
	var overlap := bool(t3.get("seat_overlap", false))
	if not overlap:
		rear_z = minf(rear_z, seat_front_z + 0.015)
	# A tank keeps most of its own length (it can be drawn down to TANK_SQUEEZE of it): where the
	# style's line would cut it shorter (a long tank, a head stock far back on a raked front), it
	# runs on back and the seat starts behind it, never further back than the swingarm pivot.
	var sc_x := 1.0
	if tank_look.get("scale") is Array and (tank_look["scale"] as Array).size() >= 1:
		sc_x = float(tank_look["scale"][0])
	var want_len := float(shape["len"]) * lerpf(0.85, 1.0, size) * sc_x * TANK_SQUEEZE
	# (Where the seat runs up over the tank's tail, an MX bike's, the tank stops at the line.)
	if not overlap:
		rear_z = clampf(nose.z + 0.03 + want_len - 0.03, rear_z, maxf(rear_z, pivot.z + 0.02))
	if not overlap:
		seat_front_z = maxf(seat_front_z, rear_z - 0.015)
	# Where the frame's seat post comes up to the seat (a cradle's, a softail's), it passes
	# behind the back of the top end, so the seat starts no further forward than that.
	if family in POST_FAMILIES:
		var back_of_heads := -INF
		for t: Vector3 in hp["head_top"]:
			back_of_heads = maxf(back_of_heads, crank.z + t.z + 0.09)
		var post := back_of_heads + POST_CLEAR
		if post > seat_front_z:
			seat_front_z = post
			if not overlap:
				rear_z = maxf(rear_z, seat_front_z - 0.015)
	# The floor's tail from the seat's nose; its nose as high as lets the tank's top just reach
	# the style's line (the tank laid along it as BikeModel._draw_tank lays it); then lifted, all
	# along, wherever it would run into the heads.
	var seat_nose_y := seat_y - (float(t4["rider_u"]) - float(t4["front_u"])) * wb * tan(deg_to_rad(float(t4["rail_deg"])))
	var b := Vector3(0.0, seat_nose_y - end_h - (0.03 if overlap else 0.0), rear_z)
	var a := Vector3(0.0, top_max - tall, nose.z)
	var back := b.z + 0.03
	var room := back - (a.z + 0.03)
	var length := minf(clampf(float(shape["len"]) * lerpf(0.85, 1.0, size) * sc_x, 0.25, maxf(room, 0.25)), room)
	var best := INF
	for i in 15:
		var u := i / 14.0
		var z := lerpf(back - length, back, u)
		var k := BikeModel._key_at(keys, u)
		var h := (float(k[1]) + float(k[2])) * size * sc_z
		var fz := clampf((z - a.z) / maxf(b.z - a.z, 0.01), 0.0, 1.0)
		if fz < 0.98:
			best = minf(best, (top_max - h - b.y * fz) / (1.0 - fz))
	if best < INF:
		a.y = best
	# (Nor nose-down any steeper than nose-up may be: on a short run, an MX tank's under its
	# seat, the solve above can't be trusted that far.)
	var max_rise := tan(deg_to_rad(float(geo.get("tank_slope", 13.0)))) * maxf(b.z - a.z, 0.01)
	a.y = clampf(a.y, b.y - max_rise, b.y + max_rise)
	# Over the heads: first the tail comes up (the tank lies flatter, and the backbone drops from
	# under it to the seat, as a softail's does), as far as level with the nose; then both.
	var lifted := false
	for need: Vector3 in over_heads:
		var f := clampf((need.z - a.z) / maxf(b.z - a.z, 0.01), 0.0, 1.0)
		var short := need.y - lerpf(a.y, b.y, f)
		if short <= 0.0:
			continue
		lifted = true
		if f > 0.05:
			var nb := minf(b.y + short / f, maxf(a.y, b.y))
			short -= (nb - b.y) * f
			b.y = nb
		if short > 0.0:
			a.y += short
			b.y += short
	# Nor may it sit higher than the head stock lets the backbone in.
	a.y = minf(a.y, head.y - 0.02)
	# A real tank lies nearly level along its frame: no steeper nose-up than the frame allows. The
	# nose comes down first, as far as the heads let it; then the tail comes up.
	if a.y - b.y > max_rise:
		var floor_a := -INF
		for need: Vector3 in over_heads:
			var f := clampf((need.z - a.z) / maxf(b.z - a.z, 0.01), 0.0, 0.95)
			floor_a = maxf(floor_a, (need.y - b.y * f) / (1.0 - f))
		a.y = maxf(b.y + max_rise, floor_a)
		if a.y - b.y > max_rise:
			b.y = a.y - max_rise
	var top := -INF
	for i in 15:
		var u := i / 14.0
		var z := lerpf(back - length, back, u)
		var k := BikeModel._key_at(keys, u)
		var fz := clampf((z - a.z) / maxf(b.z - a.z, 0.01), 0.0, 1.0)
		top = maxf(top, lerpf(a.y, b.y, fz) + (float(k[1]) + float(k[2])) * size * sc_z)
	# A tank the heads push well over the style's line needs raised mounts made for it. (One
	# that stands tall on its own, a fat cruiser tank, is the tank's shape, not the engine's.)
	if lifted and top - top_max > TANK_HIGH:
		notes.append({"what": "raised tank mounts", "why": "the tank stands %d mm over this style's line" % roundi((top - top_max) * 1000.0), "fab": true})

	# 4: the seat line and the tail; 5: the rider and the pegs.
	var rail := deg_to_rad(float(t4["rail_deg"]))
	var drop := float(geo.get("seat_drop", 0.1))
	var seat_front := Vector3(0.0, seat_nose_y - drop, seat_front_z)
	var hip := Vector3(0.0, seat_y, at_u.call(float(t4["rider_u"])))
	hip.z = maxf(hip.z, seat_front_z + 0.14)
	var tail_z: float = at_u.call(float(t4["tail_u"]))
	var tail := Vector3(0.0, seat_y - 0.02 + maxf(0.0, (tail_z - hip.z) * tan(rail)), tail_z)
	var t5: Dictionary = l["5_rider"]
	var peg := Vector3(0.17, seat_y - float(t5["peg_mm"][1]) / 1000.0, hip.z - float(t5["peg_mm"][0]) / 1000.0)
	# (The lines are the stock bike's, on the controls it comes with (a tourer's floorboards, say).
	# A set of rearsets or forward controls moves the feet by as much as it moves those.)
	var sets := PartsDB.get_part(str(parts.get("rearsets", "none")))
	if sets.get("peg") is Array:
		var own: Array = geo.get("peg", [0.02, 0.02])
		var stock := PartsDB.get_part(str(Contracts.style_build(style).get("rearsets", "none")))
		if stock.get("peg") is Array:
			own = stock["peg"]
		peg += Vector3(0.0, float(sets["peg"][0]) - float(own[0]), float(sets["peg"][1]) - float(own[1]))
	peg.y = maxf(peg.y, ground + clear_min + 0.02)
	# Forward controls reach no further than just ahead of the downtubes, which carry them.
	peg.z = maxf(peg.z, crank.z - 0.17 * s - 0.2)
	var grip := Vector3(0.31, seat_y + float(t5["grip_mm"][1]) / 1000.0, hip.z - float(t5["grip_mm"][0]) / 1000.0)
	var knee := _knee(hip + Vector3(0.0, 0.1, 0.0), peg)

	# The backbone: from the neck along under the tank's floor, then (where the tank stands higher
	# than the seat) down to the seat behind the engine in one smooth bend, as a softail's drops.
	var neck := head + Vector3(0.0, -0.01, 0.02)
	var seat_end := seat_front + Vector3(0.0, -0.04, 0.0)
	var under_a := a + Vector3(0.0, -SPINE_R, 0.0)
	var under_b := b + Vector3(0.0, -SPINE_R, 0.0)
	var path := [neck, under_a.lerp(under_b, 0.33), under_a.lerp(under_b, 0.75), under_b]
	if under_b.y - seat_end.y > 0.03:
		path.append(under_b.lerp(seat_end, 0.5) + Vector3(0.0, 0.0, -0.02))
	path.append(seat_end)
	var spine := PackedVector3Array(ShapeKit.smooth(path, 3))
	var floor := PackedVector3Array()
	for i in 9:
		floor.append(a.lerp(b, i / 8.0))

	var cooling := str(PartsDB.get_part(str(parts.get("cooling", ""))).get("style", ""))
	var box := AABB(crank + Vector3(-float(hp["head_half_w"]), (hp["sump"] as Vector3).y, -0.17 * s), Vector3.ZERO)
	box = box.expand(crank + Vector3(float(hp["head_half_w"]), float(hp["top_y"]), 0.17 * s))
	for t: Vector3 in hp["head_top"]:
		box = box.expand(crank + t + Vector3(0.0, 0.0, -0.08)).expand(crank + t + Vector3(0.0, 0.0, 0.08))

	var r := {
		"style": style, "family": family, "hard": hp, "head_k": float(hp["k"]), "eng_s": s,
		"crank": crank, "output": crank + Vector3(0.0, (hp["output"] as Vector3).y, (hp["output"] as Vector3).z),
		"spine": spine, "tank_floor": floor, "tank_nose": a, "tank_rear": b, "tank_top_max": top_max,
		"tunnel_half_w": SPINE_R + 0.01, "knee_l": Vector3(-0.17, knee.y, knee.z), "knee_r": Vector3(0.17, knee.y, knee.z),
		"seat_front": seat_front, "seat_rails": [seat_front, tail], "rail_half_w": 0.075, "seat_surface": hip, "hip": hip,
		"tail": tail, "tail_top": tail.y + float(t4["tail_rise_mm"]) / 1000.0, "seat_overlap": overlap, "peg": peg, "grip_r": grip,
		"stay_head": head + Vector3(0.0, 0.0, -0.05), "screen_base": head + Vector3(0.0, 0.04, -0.12),
		"spar_line": PackedVector3Array([head_bottom + Vector3(0.065, 0.05, 0.0), pivot + Vector3(0.12, 0.1, 0.0)]),
		"belly_y": ground + float(l["8_ground"]["clear_mm"]) / 1000.0, "radiator_z": crank.z - 0.17 * s - 0.06 if cooling == "radiator" else NAN,
		"engine_box": box, "front_clear": nearest, "notes": notes,
	}
	r["fit"] = _fit(r, engine, family, front_clear)
	return r


## The knee, between the hip and the peg, a thigh and a shin of 0.45 m each, bent forward.
static func _knee(hip: Vector3, peg: Vector3) -> Vector3:
	var d := peg - hip
	var n := d.length()
	var leg := 0.45
	var half := minf(n * 0.5, leg - 0.001)
	var rise := sqrt(maxf(leg * leg - half * half, 0.0))
	var mid := hip + d * 0.5
	var fwd := Vector3(0.0, d.z, -d.y).normalized()   # square to the leg, forward (-Z) and up
	if fwd.z > 0.0:
		fwd = -fwd
	return mid + fwd * rise


## How the engine and frame go together: {tier, work: [what the shed makes], reason}.
static func _fit(r: Dictionary, engine: Dictionary, family: String, front_clear: float) -> Dictionary:
	var layout := str(engine.get("layout", "parallel"))
	var cc := float(engine.get("displacement", 700.0))
	var fam: Dictionary = FAMILY.get(family, FAMILY["cradle"])
	if (NO_FIT.get(family, []) as Array).has(layout):
		return {"tier": TIER_NO, "work": [], "reason": "a %s's cylinders can't pass through a %s frame" % [layout, family]}
	if float(r["front_clear"]) < 0.0:
		return {"tier": TIER_NO, "work": [], "reason": "the front tyre would hit the engine on full bump"}
	var work := []
	if not (fam["layouts"] as Array).has(layout):
		work.append("engine mounts and cradle made for a %s" % layout)
	if cc > float(fam["cc"]) + 0.5:
		work.append("cradle widened and backbone stretched for %d cc" % roundi(cc))
	if float(r["front_clear"]) < front_clear:
		work.append("downtubes reshaped to clear the front tyre")
	for n in r["notes"]:
		if n.get("fab", false):
			work.append(str(n["what"]))
	if work.is_empty():
		return {"tier": TIER_BOLTS, "work": [], "reason": ""}
	return {"tier": TIER_FAB, "work": work, "reason": ", ".join(work)}


## The fit report for a set of parts (see _fit).
static func fit(build: BikeBuild) -> Dictionary:
	return solve(build)["fit"]
