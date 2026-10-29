class_name RoadMarkings
extends RefCounted
## The network ride's road markings and signs, by country (Ride Anywhere v2, T8): the centre and edge lines in the
## country's colours and patterns, give-ways and stops across side roads' mouths, the give-ways at roundabouts, painted
## words and triangles, and the signs beside them (give way, stop with its local word, junction and roundabout
## warnings in the country's shapes). The country comes from the block's region kit (RegionKit): its facts
## (data/countries.json) name the colours, the side of the road, the stop word and the markings' style
## (data/road_marks.json).
##
## RoadBlock hands over itself and its kit and gets the paint and the signs back as AdventureProps arrays (see
## interfaces/road-block.md, "Markings"). Everything here is worked out from the block's own data, so every machine
## paints the same; safe from any thread.

const MARKS := "res://data/road_marks.json"
## Paint sits this far above the deck (m).
const LIFT := 0.015
## The road classes whose centre line is painted as the style's "major".
const MAJOR := ["motorway", "trunk", "primary", "secondary"]
## The classes with no centre line, however wide.
const UNLINED := ["service", "track", "path", "living_street"]
## A block with this many buildings is in town (or its place's profile says so): kerb paint, and town lines.
const TOWN_BUILDINGS := 25
const TOWN_DENSITY := ["town", "city"]
## The classes whose kerbs are painted in town.
const KERBED := ["primary", "secondary", "tertiary", "unclassified", "residential"]
## Bollards round a town junction's corners, by region: their colour and their band's.
const BOLLARDS := {
	"british_isles": [Color(0.08, 0.08, 0.09), Color(0.78, 0.62, 0.2)],
	"western_europe": [Color(0.42, 0.44, 0.46), Color(0.85, 0.1, 0.1)],
	"nordic": [Color(0.3, 0.32, 0.34), Color(0.92, 0.9, 0.86)],
	"eastern_europe": [Color(0.7, 0.69, 0.66), Color(0.12, 0.12, 0.12)],
	"mediterranean": [Color(0.72, 0.7, 0.66), Color(0.5, 0.48, 0.45)],
	"north_africa_middle_east": [Color(0.85, 0.82, 0.76), Color(0.72, 0.1, 0.08)],
	"sub_saharan_africa": [Color(0.75, 0.73, 0.68), Color(0.1, 0.1, 0.1)],
	"north_america": [Color(0.92, 0.75, 0.1), Color(0.92, 0.75, 0.1)],
	"latin_america": [Color(0.92, 0.78, 0.1), Color(0.1, 0.1, 0.1)],
	"south_asia": [Color(0.92, 0.9, 0.86), Color(0.1, 0.1, 0.1)],
	"east_asia": [Color(0.9, 0.9, 0.88), Color(0.75, 0.12, 0.1)],
	"south_east_asia": [Color(0.92, 0.9, 0.86), Color(0.75, 0.1, 0.1)],
	"australia_nz": [Color(0.94, 0.94, 0.92), Color(0.8, 0.1, 0.1)],
}
const BOLLARD_H := 0.95
const BOLLARD_W := 0.16
const BOLLARD_GAP := 1.6
## The road classes whose junctions are warned of ahead, and how far ahead (m).
const WARNED := ["motorway", "trunk", "primary", "secondary", "tertiary"]
const WARN_AHEAD := 70.0
const PAINT := {"white": Color(0.88, 0.88, 0.84), "yellow": Color(0.9, 0.68, 0.1)}
const RED := Color(0.72, 0.07, 0.07)
const WHITE := Color(0.93, 0.93, 0.9)
const YELLOW := Color(0.95, 0.75, 0.1)
const BLUE := Color(0.1, 0.3, 0.68)
const BLACK := Color(0.06, 0.06, 0.07)
const POLE := Color(0.55, 0.56, 0.57)
const BACK := Color(0.45, 0.46, 0.47)
## A sign's middle stands this high above the road (m), on a pole this thick, this far out past the road's edge.
const SIGN_H := 2.0
const POLE_W := 0.07
const SIGN_OUT := 0.9
## A sign's pole or a bollard stands at least CLEAR_OF m off any road's surface, moved out up to CLEAR_REACH m to be
## (clear_of_road).
const CLEAR_OF := 0.4
const CLEAR_REACH := 5.0
## A sign's plate stands this far in front of its pole.
const PLATE_OUT := 0.05

static var _lock := Mutex.new()
static var _styles := {}
static var _made := {}


## What the markings of `kit`'s country are: its style (data/road_marks.json) with the country's colours, side of the
## road, stop word, share of stops and sign shapes laid in. {} when the kit is.
static func style_of(kit: Dictionary) -> Dictionary:
	var f: Dictionary = kit.get("facts", {})
	if f.is_empty():
		return {}
	var code := str(kit.get("country", ""))
	_lock.lock()
	if _styles.is_empty():
		var file := FileAccess.open(MARKS, FileAccess.READ)
		var d = JSON.parse_string(file.get_as_text()) if file != null else null
		_styles = d.get("styles", {}) if d is Dictionary else {"eu": {}}
	var have = _made.get(code)
	_lock.unlock()
	if have is Dictionary:
		return have
	var st: Dictionary = (_styles.get(str(f.get("marks", "eu")), _styles.get("eu", {})) as Dictionary).duplicate(true)
	st["marks"] = str(f.get("marks", "eu"))
	st["centre_col"] = PAINT.get(str(f.get("centre", "white")), PAINT["white"])
	st["edge_on"] = str(f.get("edge", "white")) != "none"
	st["edge_col"] = PAINT.get(str(f.get("edge", "white")), PAINT["white"])
	st["left"] = str(f.get("drive", "right")) == "left"
	st["stop_word"] = str(f.get("stop", "STOP"))
	st["stop_share"] = float(f.get("stop_share", 0.2))
	st["warning"] = str(f.get("warning", "triangle"))
	st["warning_face"] = YELLOW if str(f.get("warning_face", "white")) == "yellow" else WHITE
	# Japan's stop sign is a red triangle point down, with its word in white.
	st["stop_shape"] = "triangle" if code == "JP" else "octagon"
	# Most of the world signs a roundabout with a blue disc at each entry; Britain and its old colonies don't.
	st["roundabout_sign"] = str(f.get("marks", "")) not in ["uk", "au"]
	_lock.lock()
	_made[code] = st
	_lock.unlock()
	return st


## Block `b`'s paint and signs in its place's style (`kit`, RegionKit.choose): {"lines": AdventureProps arrays (the
## paint, drawn with the block's lines), "signs": AdventureProps arrays (drawn with its buildings: signs and
## bollards), "faces": collision triangles laid on the tarmac (none at present), "labels": the words drawn as text, such as
## place names (RoadSigns.put_up)}, laid out from the block's anchor. {} when the
## kit is (the block then paints its plain lines).
static func paint(b: RoadBlock, kit: Dictionary) -> Dictionary:
	var st := style_of(kit)
	if st.is_empty():
		return {}
	var lines := AdventureProps.new_arrays()
	var signs := AdventureProps.new_arrays()
	var o := b.anchor()
	var town := str(kit.get("density", "")) in TOWN_DENSITY or b.buildings.size() >= TOWN_BUILDINGS
	var kerb: Array = RegionKit.KERB_PAINT.get(str(kit["facts"].get("kerb", "none")), []) if town else []
	var faces := PackedVector3Array()   # (none now: Simon took the speed bumps out, 2026-10-28)
	for p in b.pieces:
		if str(p["surface"]) == "tarmac":
			var q := _prep(p, o)
			_piece(lines, signs, b.net, p, q, st, town, kerb)
	for j in b.junctions:
		if j["kind"] == "mini" and bool(st.get("mini", false)):
			_disc(lines, j["pos"] - o + Vector3(0.0, LIFT, 0.0), minf(1.6, float(j["radius"]) * 0.3), PAINT["white"])
		if town and j["kind"] in ["tee", "cross", "staggered", "fork", "multi"]:
			_bollards(signs, b.net, b.net.junction_of(int(j["node"])), o, BOLLARDS.get(str(kit.get("region", "")), BOLLARDS["western_europe"]))
	var labels := RoadSigns.put_up(b, kit, st, signs)
	return {"lines": lines, "signs": signs, "faces": faces, "labels": labels}


# ---------------------------------------------------------------------------- a piece's paint

## A piece's points from the block's anchor, the way right at each, the distance along its edge of each, its half
## width, and the anchor.
static func _prep(p: Dictionary, o: Vector3) -> Dictionary:
	var src: PackedVector3Array = p["points"]
	var pts := PackedVector3Array()
	var rights := PackedVector3Array()
	var at := PackedFloat32Array()
	var s := float(p["s0"])
	for k in src.size():
		pts.append(src[k] - o)
		var h := RoadBlock._heading(src, k)
		rights.append(Vector3(cos(h), 0.0, sin(h)))
		if k > 0:
			s += Vector2(src[k].x - src[k - 1].x, src[k].z - src[k - 1].z).length()
		at.append(s)
	if p.has("at") and (p["at"] as PackedFloat32Array).size() == src.size():
		at = p["at"]
	return {"pts": pts, "rights": rights, "at": at, "e": float(p["width"]) * 0.5, "o": o}


## The point on piece `q` (_prep) `s` along its edge and `lat` right of its centre line, on the crowned deck, `lift`
## above it.
static func _point(q: Dictionary, s: float, lat: float, lift := LIFT) -> Vector3:
	var at: PackedFloat32Array = q["at"]
	var pts: PackedVector3Array = q["pts"]
	var rights: PackedVector3Array = q["rights"]
	var n := at.size()
	var k := clampi(at.bsearch(s) - 1, 0, n - 2)
	var t := clampf((s - at[k]) / maxf(at[k + 1] - at[k], 0.001), 0.0, 1.0)
	var c := pts[k].lerp(pts[k + 1], t)
	var r := rights[k].lerp(rights[k + 1], t).normalized()
	var f := clampf(lat / maxf(float(q["e"]), 0.1), -1.0, 1.0)
	return c + r * lat + Vector3(0.0, RoadNet.CROWN * (1.0 - f * f) + lift, 0.0)


## The way along piece `q` at `s` (a unit vector, a to b).
static func _along(q: Dictionary, s: float) -> Vector3:
	var at: PackedFloat32Array = q["at"]
	var rights: PackedVector3Array = q["rights"]
	var k := clampi(at.bsearch(s) - 1, 0, at.size() - 2)
	var r := rights[k].lerp(rights[k + 1], 0.5).normalized()
	return Vector3(r.z, 0.0, -r.x)


## A strip of paint from `s0` to `s1` along piece `q`, between `lat0` and `lat1` across it, bending with the road.
static func _band(a: Dictionary, q: Dictionary, s0: float, s1: float, lat0: float, lat1: float, col: Color) -> void:
	if s1 < s0:
		var t := s0
		s0 = s1
		s1 = t
	var at: PackedFloat32Array = q["at"]
	s0 = maxf(s0, at[0])
	s1 = minf(s1, at[at.size() - 1])
	if s1 - s0 < 0.01:
		return
	var cuts := PackedFloat32Array([s0])
	for k in range(maxi(at.bsearch(s0), 0), at.size()):
		if at[k] >= s1:
			break
		if at[k] > s0 + 0.01:
			cuts.append(at[k])
	cuts.append(s1)
	for k in cuts.size() - 1:
		RoadBlock._up(a, _point(q, cuts[k], lat0), _point(q, cuts[k + 1], lat0), _point(q, cuts[k + 1], lat1), col)
		RoadBlock._up(a, _point(q, cuts[k], lat0), _point(q, cuts[k + 1], lat1), _point(q, cuts[k], lat1), col)


## A line `w` wide centred `lat` across piece `q` from `s0` to `s1`: solid, or dashes `dash` on and `gap` off counted
## from the edge's start (so they carry on across a block's seam).
static func _line(a: Dictionary, q: Dictionary, lat: float, w: float, dash: float, gap: float, s0: float, s1: float,
		col: Color) -> void:
	if dash <= 0.0:
		_band(a, q, s0, s1, lat - w * 0.5, lat + w * 0.5, col)
		return
	var period := dash + gap
	var n := floorf(s0 / period)
	while n * period < s1:
		var d0 := maxf(n * period, s0)
		var d1 := minf(n * period + dash, s1)
		if d1 > d0:
			_band(a, q, d0, d1, lat - w * 0.5, lat + w * 0.5, col)
		n += 1.0


## A centre line in `line`'s way (the style's centre, major or near: solid, dashed, or double).
static func _centre(a: Dictionary, q: Dictionary, line: Dictionary, s0: float, s1: float, col: Color) -> void:
	var w := float(line.get("w", 0.1))
	if bool(line.get("double", false)):
		for side: float in [-1.0, 1.0]:
			_line(a, q, side * (w * 0.5 + 0.06), w, 0.0, 0.0, s0, s1, col)
	else:
		_line(a, q, 0.0, w, float(line.get("dash", 3.0)), float(line.get("gap", 9.0)), s0, s1, col)


## Piece `p`'s paint (its edge and centre lines, and its give-way or stop where it meets a junction as a side road),
## and the signs beside it.
static func _piece(lines: Dictionary, signs: Dictionary, net: RoadNet, p: Dictionary, q: Dictionary, st: Dictionary,
		town := false, kerb := []) -> void:
	var at: PackedFloat32Array = q["at"]
	var s0 := at[0]
	var s1 := at[at.size() - 1]
	var e := float(q["e"])
	var ei := int(p["edge"])
	var cls := str(p["class"])
	var len := net.length_of(ei)
	# Which of its ends meet a junction here (the piece runs right up to its mouth).
	var ends := {}
	for end: int in [0, 1]:
		var node := int(p["b"] if end == 1 else p["a"])
		var j := net.junction_of(node)
		if j.is_empty() or j["kind"] == "end":
			continue
		var m := net.mouth(ei, node)
		var s_mouth := len - m if end == 1 else m
		ends[end] = {"node": node, "j": j, "s": s_mouth, "here": absf((s1 if end == 1 else s0) - s_mouth) < 0.5}
	# Edge lines, or in town what the country runs along its kerbs instead, and its kerb paint.
	var edge: Dictionary = st.get("edge", {})
	var in_town := town and cls in KERBED and not bool(p["ring"])
	if in_town and kerb.size() == 2:
		var n := floorf(s0)
		while n < s1:
			for side: float in [-1.0, 1.0]:
				_band(lines, q, n, n + 1.0, side * (e - 0.22), side * e, kerb[int(n) % 2])
			n += 1.0
	if in_town and str(st.get("town_lines", "")) == "double_yellow":
		for side: float in [-1.0, 1.0]:
			for lat: float in [e - 0.35, e - 0.55]:
				_line(lines, q, side * lat, 0.1, 0.0, 0.0, s0, s1, PAINT["yellow"])
	elif bool(st["edge_on"]) and e * 2.0 >= float(edge.get("min", 5.0)):
		var w := float(edge.get("w", 0.1))
		for side: float in [-1.0, 1.0]:
			_line(lines, q, side * (e - RoadBlock.LINE_IN - w * 0.5), w, float(edge.get("dash", 0.0)), float(edge.get("gap", 0.0)), s0, s1, st["edge_col"])
	# The centre line: two-way two-lane roads in the country's colour, lanes the same way in white; solid or as "near"
	# says over its last stretch into a junction.
	if int(p["lanes"]) == 2 and not bool(p["ring"]) and cls not in UNLINED:
		var col: Color = st["centre_col"] if int(p["oneway"]) == 0 else PAINT["white"]
		var line: Dictionary = st["major"] if cls in MAJOR else st["centre"]
		var near: Dictionary = st.get("near", {})
		var nl := float(near.get("len", 0.0))
		var lo := s0
		var hi := s1
		if ends.has(0) and nl > 0.0:
			lo = clampf(float(ends[0]["s"]) + nl, s0, s1)
			_centre(lines, q, near, s0, lo, col)
		if ends.has(1) and nl > 0.0:
			hi = clampf(float(ends[1]["s"]) - nl, lo, s1)
			_centre(lines, q, near, hi, s1, col)
		_centre(lines, q, line, lo, hi, col)
	for end: int in ends:
		var info: Dictionary = ends[end]
		var j: Dictionary = info["j"]
		var dir := 1.0 if end == 1 else -1.0
		# (a one-way road only ever leaves a junction at one of its ends)
		var oneway := int(p["oneway"])
		if (oneway == 1 and end == 0) or (oneway == -1 and end == 1):
			continue
		var arm := {}
		for a: Dictionary in j["arms"]:
			if int(a["edge"]) == ei and int(a["node"]) == int(info["node"]):
				arm = a
		if arm.is_empty():
			continue
		var round: bool = j["kind"] in ["roundabout", "mini"]
		if bool(p["ring"]):
			continue
		if not round and bool(arm["main"]):
			_warning(signs, net, q, p, j, info, dir, st)
			continue
		if round:
			_warning(signs, net, q, p, j, info, dir, st)
		if bool(info["here"]):
			_approach(lines, signs, net, q, p, info, dir, round, st)


## Where a side road (or a roundabout's entry) meets its junction: the give-way or stop across the lanes coming in,
## anything painted before it, and its sign.
static func _approach(lines: Dictionary, signs: Dictionary, net: RoadNet, q: Dictionary, p: Dictionary, info: Dictionary,
		dir: float, round: bool, st: Dictionary) -> void:
	var e := float(q["e"])
	var white: Color = PAINT["white"]
	# The lanes coming in: all of a one-lane or one-way road, else the half on the country's side.
	var lat0 := -e + 0.2
	var lat1 := e - 0.2
	var side := dir * (-1.0 if bool(st["left"]) else 1.0)
	if int(p["lanes"]) == 2 and int(p["oneway"]) == 0:
		lat0 = 0.15 if side > 0.0 else -e + 0.2
		lat1 = e - 0.2 if side > 0.0 else -0.15
	var s_line := float(info["s"]) - dir * 0.3
	var roll := float(posmod(("%d:%d" % [int(info["node"]), int(p["edge"])]).hash(), 1000)) / 1000.0
	var stop := not round and roll < float(st["stop_share"])
	var pole_lat := side * (e + SIGN_OUT)
	var pole_s := s_line - dir * 1.2
	var facing := -_along(q, pole_s) * dir
	var foot := _point(q, pole_s, pole_lat, -0.3)
	foot = clear_of_road(net, foot, q["o"], foot - _point(q, pole_s, 0.0, -0.3))
	var standing := foot.is_finite()
	if stop:
		var sl: Dictionary = st.get("stop", {})
		var w := float(sl.get("w", 0.3))
		_band(lines, q, s_line - dir * w, s_line, lat0, lat1, white)
		if bool(sl.get("word", false)):
			var word := str(st["stop_word"])
			var lane := lat1 - lat0
			var mid_s := s_line - dir * (w + 3.0)
			# Painted long and narrow, as road words are, reading from the driver's seat.
			_road_word(lines, q, word, mid_s, (lat0 + lat1) * 0.5, minf(lane - 0.6, 2.6), 2.4, dir, white)
		if standing:
			_stop_sign(signs, foot, facing, st)
		return
	var gw: Dictionary = st["roundabout"] if round else st["give_way"]
	_give_way_line(lines, q, gw, s_line, lat0, lat1, dir, white)
	if bool(st.get("triangle", false)) and not round:
		_road_triangle(lines, q, s_line - dir * 12.0, (lat0 + lat1) * 0.5, dir, white)
	if not standing:
		return
	var h := SIGN_H + (0.45 if round and bool(st["roundabout_sign"]) else 0.0)
	_give_way_sign(signs, foot, facing, h, st)
	if round and bool(st["roundabout_sign"]):
		_roundabout_sign(signs, foot, facing, SIGN_H - 0.3)


## A give-way line across lanes `lat0` to `lat1`, its junction side at `s_line`, coming in the way `dir`.
static func _give_way_line(a: Dictionary, q: Dictionary, gw: Dictionary, s_line: float, lat0: float, lat1: float,
		dir: float, col: Color) -> void:
	var kind := str(gw.get("kind", "dash"))
	var w := float(gw.get("w", 0.3))
	var dash := float(gw.get("dash", 0.5))
	var gap := float(gw.get("gap", 0.3))
	var rows := []
	match kind:
		"none":
			return
		"double":
			rows = [0.0, w + 0.3]
		"dash":
			rows = [0.0]
		"teeth":
			var l := lat0
			while l + dash <= lat1 + 0.01:
				# Each tooth's base on the line, its point towards the driver.
				var p0 := _point(q, s_line, l)
				var p1 := _point(q, s_line, l + dash)
				var p2 := _point(q, s_line - dir * w, l + dash * 0.5)
				RoadBlock._up(a, p0, p1, p2, col)
				l += dash + gap
			return
	for back: float in rows:
		var l := lat0
		while l < lat1 - 0.05:
			_band(a, q, s_line - dir * back, s_line - dir * (back + w), l, minf(l + dash, lat1), col)
			l += dash + gap


## The give-way triangle painted in the lane before the line (Britain's): an outline, long down the road, its point
## towards the driver.
static func _road_triangle(a: Dictionary, q: Dictionary, s: float, lat: float, dir: float, col: Color) -> void:
	var half := 0.75
	var long := 3.75
	var w := 0.2
	var base0 := Vector2(s, lat - half)
	var base1 := Vector2(s, lat + half)
	var tip := Vector2(s - dir * long, lat)
	for pair: Array in [[base0, base1], [base1, tip], [tip, base0]]:
		var u: Vector2 = pair[0]
		var v: Vector2 = pair[1]
		var n := Vector2(-(v.y - u.y), v.x - u.x).normalized() * (w * 0.5)
		# (in s and lat: a thin quad along the side)
		RoadBlock._up(a, _point(q, u.x - n.x, u.y - n.y), _point(q, v.x - n.x, v.y - n.y), _point(q, v.x + n.x, v.y + n.y), col)
		RoadBlock._up(a, _point(q, u.x - n.x, u.y - n.y), _point(q, v.x + n.x, v.y + n.y), _point(q, u.x + n.x, u.y + n.y), col)


## Word `word` painted on the road at `s` along and `lat` across, `wide` across and `long` down the road, reading
## for a driver coming the way `dir`.
static func _road_word(a: Dictionary, q: Dictionary, word: String, s: float, lat: float, wide: float, long: float,
		dir: float, col: Color) -> void:
	var g := SignWords.of(word)
	if g.is_empty() or wide <= 0.5:
		return
	var w := float(g["w"])
	var top := float(g["top"])
	var bottom := float(g["bottom"])
	var t: Array = g["tris"]
	var kx := wide / maxf(w, 0.01)
	var ky := long / maxf(top - bottom, 0.01)
	var mid := Vector2(w * 0.5, (top + bottom) * 0.5)
	# The word's x runs to the driver's right, its y up the road away from them.
	for i in range(0, t.size(), 6):
		var c := []
		for k in 3:
			var x := (float(t[i + k * 2]) - mid.x) * kx
			var y := (float(t[i + k * 2 + 1]) - mid.y) * ky
			c.append(_point(q, s + dir * y, lat + dir * x))
		RoadBlock._up(a, c[0], c[1], c[2], col)


## A painted disc (a mini roundabout's middle).
static func _disc(a: Dictionary, c: Vector3, r: float, col: Color) -> void:
	for k in 16:
		var t0 := TAU * k / 16.0
		var t1 := TAU * (k + 1) / 16.0
		RoadBlock._up(a, c, c + Vector3(sin(t0), 0.0, -cos(t0)) * r, c + Vector3(sin(t1), 0.0, -cos(t1)) * r, col)


## Bollards round town junction `j`'s corners (RoadNet.junction_of: its outline, where it runs along a kerb), just
## back from the kerb, in the region's colours.
static func _bollards(a: Dictionary, net: RoadNet, j: Dictionary, o: Vector3, cols: Array) -> void:
	if not j.has("kerb"):
		return
	var outline: PackedVector2Array = j["outline"]
	var heights: PackedFloat32Array = j["outline_y"]
	var kerb: PackedByteArray = j["kerb"]
	var mid := Vector2(float(j["pos"].x), float(j["pos"].z))
	var n := outline.size()
	for k in n:
		if kerb[k] != 1:
			continue
		var u := outline[k]
		var v := outline[(k + 1) % n]
		var along := (v - u).length()
		if along < BOLLARD_GAP:
			continue
		var out := (u + v) * 0.5 - mid
		out = out.normalized() if out.length_squared() > 0.0 else Vector2.UP
		var count := clampi(int(along / BOLLARD_GAP), 1, 3)
		for i in count:
			var t := (float(i) + 0.5) / count * 0.6 + 0.2
			var at := u.lerp(v, t) + out * (RoadNet.VERGE * 0.5)
			var y := lerpf(heights[k], heights[(k + 1) % n], t)
			var foot := clear_of_road(net, Vector3(at.x, y - 0.1, at.y) - o, o, Vector3(out.x, 0.0, out.y))
			if not foot.is_finite():
				continue
			AdventureProps.box(a, Transform3D(Basis(), foot), Vector3(BOLLARD_W, BOLLARD_H, BOLLARD_W), cols[0])
			AdventureProps.box(a, Transform3D(Basis(), foot + Vector3(0.0, BOLLARD_H - 0.22, 0.0)), Vector3(BOLLARD_W + 0.01, 0.1, BOLLARD_W + 0.01), cols[1], false)


# ---------------------------------------------------------------------------- signs

## A warning of the junction ahead on a main road into it (or a road into a roundabout), WARN_AHEAD before its mouth,
## on roads of a WARNED class, where that's still on this piece and clear of the junction at the road's other end.
static func _warning(signs: Dictionary, net: RoadNet, q: Dictionary, p: Dictionary, j: Dictionary, info: Dictionary,
		dir: float, st: Dictionary) -> void:
	if str(p["class"]) not in WARNED:
		return
	var at: PackedFloat32Array = q["at"]
	var ei := int(p["edge"])
	var len := net.length_of(ei)
	var s := float(info["s"]) - dir * WARN_AHEAD
	var far := net.mouth(ei, int(p["a"] if dir > 0.0 else p["b"]))
	if dir > 0.0 and s < far + 20.0 or dir < 0.0 and s > len - far - 20.0:
		return
	if s < at[0] or s > at[at.size() - 1]:
		return
	var e := float(q["e"])
	var side := dir * (-1.0 if bool(st["left"]) else 1.0)
	var foot := clear_of_road(net, _point(q, s, side * (e + SIGN_OUT), -0.3), q["o"],
		_point(q, s, side, -0.3) - _point(q, s, 0.0, -0.3))
	if not foot.is_finite():
		return
	var facing := -_along(q, s) * dir
	var symbol := "cross"
	match str(j["kind"]):
		"roundabout", "mini":
			symbol = "roundabout"
		"tee", "fork":
			symbol = "tee"
	_warning_sign(signs, foot, facing, symbol, st)


## A pole from `foot` up to `top` m.
static func _pole(a: Dictionary, foot: Vector3, top: float) -> void:
	AdventureProps.box(a, Transform3D(Basis(), foot), Vector3(POLE_W, top, POLE_W), POLE, false)


## A sign's or bollard's foot (block space, the block's anchor `o`) clear of every road and junction's surface: where
## it is, if nothing's within CLEAR_OF of it, else moved on `away` (level, out from the road it's beside) till it is
## (a junction's kerb curving out, a roundabout's mouth widening, another road alongside), or Vector3.INF if it can't
## be within CLEAR_REACH (then it isn't put up).
static func clear_of_road(net: RoadNet, foot: Vector3, o: Vector3, away: Vector3) -> Vector3:
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0 else Vector3.RIGHT
	var side := Vector3(-away.z, 0.0, away.x)
	var moved := 0.0
	while moved <= CLEAR_REACH:
		var p := foot + away * moved + o
		var clear := true
		for d: Vector3 in [Vector3.ZERO, away * CLEAR_OF, -away * CLEAR_OF, side * CLEAR_OF, -side * CLEAR_OF]:
			var on := net.locate(p.x + d.x, p.z + d.z, -1, false)
			if not on.is_empty() and bool(on["on_road"]):
				clear = false
				break
		if clear:
			return foot + away * moved
		moved += 0.5
	return Vector3.INF


## A flat shape (`pts`, x right and y up as the driver sees it, m) on a sign at `c` facing `facing`, `depth` in front of
## the sign's plate, filled from its middle.
static func _shape(a: Dictionary, c: Vector3, facing: Vector3, pts: Array, col: Color, depth: float) -> void:
	var across := Vector3.UP.cross(facing).normalized()
	var o := c + facing * depth
	var n := pts.size()
	var mid := Vector2.ZERO
	for p: Vector2 in pts:
		mid += p / n
	var m := o + across * mid.x + Vector3.UP * mid.y
	for k in n:
		var u: Vector2 = pts[k]
		var v: Vector2 = pts[(k + 1) % n]
		var p0 := o + across * u.x + Vector3.UP * u.y
		var p1 := o + across * v.x + Vector3.UP * v.y
		if (p0 - m).cross(p1 - m).dot(facing) >= 0.0:
			AdventureProps._tri(a, m, p0, p1, col)
		else:
			AdventureProps._tri(a, m, p1, p0, col)


## A regular polygon's points: `n` sides, `r` to its corners, turned `turn` (radians, 0: a corner straight up).
static func _ngon(n: int, r: float, turn := 0.0) -> Array:
	var out := []
	for k in n:
		var t := turn + TAU * k / n
		out.append(Vector2(sin(t), cos(t)) * r)
	return out


## A bar from `u` to `v`, `w` wide, as a shape's points.
static func _bar(u: Vector2, v: Vector2, w: float) -> Array:
	var n := (v - u).orthogonal().normalized() * (w * 0.5)
	return [u - n, v - n, v + n, u + n]


## A sign plate: `pts` in `col` facing the driver, its back in grey.
static func _plate(a: Dictionary, c: Vector3, facing: Vector3, pts: Array, col: Color) -> void:
	_shape(a, c, facing, pts, col, 0.0)
	_shape(a, c, -facing, pts, BACK, 0.012)


## A stop sign on its pole at `foot`, facing `facing`: a red octagon with the country's word in white (Japan's: a red
## triangle point down).
static func _stop_sign(a: Dictionary, foot: Vector3, facing: Vector3, st: Dictionary) -> void:
	_pole(a, foot, SIGN_H + 0.3)
	var c := foot + Vector3(0.0, SIGN_H + 0.3, 0.0) + facing * PLATE_OUT
	var across := Vector3.UP.cross(facing).normalized()
	if str(st["stop_shape"]) == "triangle":
		_plate(a, c, facing, _ngon(3, 0.55, PI), WHITE)
		_shape(a, c, facing, _ngon(3, 0.47, PI), RED, 0.006)
		SignWords.draw(a, str(st["stop_word"]), c + Vector3(0.0, 0.1, 0.0) + facing * 0.012, across, Vector3.UP, 0.15,
			WHITE, facing, 0.42)
		return
	_plate(a, c, facing, _ngon(8, 0.45, PI / 8.0), WHITE)
	_shape(a, c, facing, _ngon(8, 0.41, PI / 8.0), RED, 0.006)
	SignWords.draw(a, str(st["stop_word"]), c + facing * 0.012, across, Vector3.UP, 0.2, WHITE, facing, 0.6)


## A give-way sign: a triangle point down, red-bordered (its face the country's warning face), its middle `h` m up.
static func _give_way_sign(a: Dictionary, foot: Vector3, facing: Vector3, h: float, st: Dictionary) -> void:
	_pole(a, foot, h + 0.3)
	var c := foot + Vector3(0.0, h + 0.3, 0.0) + facing * PLATE_OUT
	_plate(a, c, facing, _ngon(3, 0.52, PI), RED)
	_shape(a, c, facing, _ngon(3, 0.32, PI), st["warning_face"], 0.006)


## A roundabout's blue disc with its white ring of arrows (most of the world's), its middle `h` m up the pole at `foot`.
static func _roundabout_sign(a: Dictionary, foot: Vector3, facing: Vector3, h: float) -> void:
	var c := foot + Vector3(0.0, h + 0.3, 0.0) + facing * PLATE_OUT
	_plate(a, c, facing, _ngon(20, 0.35), BLUE)
	for k in 3:
		var t := TAU * k / 3.0
		var pts := []
		for i in 6:
			var u := t + 0.25 + i * 0.25
			pts.append(Vector2(sin(u), cos(u)))
		# A curved arrow: a thick arc, and its head.
		for i in 5:
			var p0: Vector2 = pts[i] * 0.2
			var p1: Vector2 = pts[i + 1] * 0.2
			_shape(a, c, facing, _bar(p0, p1, 0.07), WHITE, 0.006)
		var tip: Vector2 = pts[5] * 0.2
		var way: Vector2 = (pts[5] - pts[4]).normalized()
		_shape(a, c, facing, [tip + way * 0.08, tip + way.orthogonal() * 0.07, tip - way.orthogonal() * 0.07], WHITE, 0.006)


## A warning of a junction ahead: the country's triangle (red border, its face white or yellow) or yellow diamond,
## with the junction's symbol in black.
static func _warning_sign(a: Dictionary, foot: Vector3, facing: Vector3, symbol: String, st: Dictionary) -> void:
	_pole(a, foot, SIGN_H + 0.3)
	var c := foot + Vector3(0.0, SIGN_H + 0.3, 0.0) + facing * PLATE_OUT
	var k := 1.0
	if str(st["warning"]) == "diamond":
		_plate(a, c, facing, _ngon(4, 0.5), BLACK)
		_shape(a, c, facing, _ngon(4, 0.46), YELLOW, 0.006)
	else:
		_plate(a, c, facing, _ngon(3, 0.55), RED)
		_shape(a, c, facing, _ngon(3, 0.36), st["warning_face"], 0.006)
		c += Vector3(0.0, -0.05, 0.0)
		k = 0.7
	var w := 0.06 * k
	match symbol:
		"cross":
			_shape(a, c, facing, _bar(Vector2(0.0, -0.22 * k), Vector2(0.0, 0.22 * k), w), BLACK, 0.012)
			_shape(a, c, facing, _bar(Vector2(-0.16 * k, 0.02 * k), Vector2(0.16 * k, 0.02 * k), w), BLACK, 0.012)
		"tee":
			_shape(a, c, facing, _bar(Vector2(0.0, -0.22 * k), Vector2(0.0, 0.12 * k), w), BLACK, 0.012)
			_shape(a, c, facing, _bar(Vector2(-0.18 * k, 0.12 * k), Vector2(0.18 * k, 0.12 * k), w), BLACK, 0.012)
		"roundabout":
			var ring := _ngon(10, 0.14 * k)
			for i in ring.size():
				_shape(a, c, facing, _bar(ring[i], ring[(i + 1) % ring.size()], w * 0.8), BLACK, 0.012)
