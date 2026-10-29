class_name RoadSigns
extends RefCounted
## The network ride's roadside signs that the single road has (Ride Anywhere v2, T8, the network parity gate): speed
## limits where the limit changes (at a junction, a join, and where a road comes into a village or town and leaves
## it), the place's name board where the road comes in (and in continental Europe its end board going out),
## fingerposts down side roads naming the place each goes to and how far, and the chevron boards on a roundabout's
## island facing each way in. Each in its country's way (RegionKit facts and RoadMarkings' style).
##
## RoadMarkings.paint calls put_up with the block, its kit and style and its sign arrays: the signs' plates and poles
## go into those arrays, and the words that aren't baked (place names) come back as labels for the streamer to stand
## up (see interfaces/road-block.md, "Markings"). Everything is worked out from the region's own data, so every
## machine signs the same; safe from any thread.

## A place's houses: they reach out from its point, PLACE_STEP m at a time, until a ring PLACE_RING m wide beyond
## holds fewer than PLACE_DENSE buildings to the square metre (the scattered farms round a village are well under
## it); then PLACE_PAD further, between PLACE_MIN and PLACE_MAX m. Its buildings are looked for within PLACE_MAX of
## its point.
const PLACE_STEP := 20.0
const PLACE_RING := 60.0
const PLACE_DENSE := 1.0 / 6000.0
const PLACE_PAD := 30.0
const PLACE_MIN := 90.0
const PLACE_MAX := 900.0
## A place of at least BUILT_UP buildings is built up (its limit is the country's built-up one); one of at least
## BOARDED gets a name board.
const BUILT_UP := 12
const BOARDED := 4
## The classes that get limit signs and name boards where they come into a place, and fingerposts down them.
const SIGNED := ["trunk", "primary", "secondary", "tertiary", "unclassified"]
## Where a limit changes at a junction or a join, its sign stands this far past the mouth (m); none on a road with less
## than LIMIT_ROOM between its mouths, nor nearer a mouth than PLACE_CLEAR where a road comes into a place.
const LIMIT_AFTER := 12.0
const LIMIT_ROOM := 40.0
const PLACE_CLEAR := 25.0
## The name board stands this far further in than the limit sign.
const BOARD_IN := 6.0
## A fingerpost names a place within FINGER_REACH m whose bearing is within FINGER_ANGLE of the side road's, at least
## FINGER_MIN m off; a road's distance is about ROAD_FACTOR times the straight line.
const FINGER_REACH := 20000.0
const FINGER_ANGLE := 0.7
const FINGER_MIN := 400.0
const ROAD_FACTOR := 1.25
## A roundabout's chevron board stands this far in from its island's kerb; none on an island smaller than CHEVRON_MIN.
const CHEVRON_IN := 0.8
const CHEVRON_MIN := 2.5
## The speed limit tables' (RoutePlanner.LIMITS) country for each facts code.
const LIMIT_TABLE := {"GB": "uk", "IM": "uk", "JE": "uk", "GG": "uk", "JP": "jp"}
## Name boards by country: [plate, border, ink]; others white with a black border. Continental Europe's regions also
## stand an end board going out, its name struck through in red.
const BOARDS := {
	"DE": [Color(0.95, 0.78, 0.1), Color(0.06, 0.06, 0.07), Color(0.06, 0.06, 0.07)],
	"LU": [Color(0.95, 0.78, 0.1), Color(0.06, 0.06, 0.07), Color(0.06, 0.06, 0.07)],
	"FR": [Color(0.93, 0.93, 0.9), Color(0.72, 0.07, 0.07), Color(0.06, 0.06, 0.07)],
	"NL": [Color(0.1, 0.3, 0.68), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"CH": [Color(0.1, 0.3, 0.68), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"SE": [Color(0.1, 0.3, 0.68), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"JP": [Color(0.1, 0.3, 0.68), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"US": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"CA": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"AU": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
	"NZ": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9), Color(0.93, 0.93, 0.9)],
}
const END_BOARDS := ["western_europe", "eastern_europe", "nordic", "mediterranean"]
## Fingerposts by region (and a few countries): [arm, ink]; others white with black words.
const FINGERS := {
	"north_america": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9)],
	"australia_nz": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9)],
	"latin_america": [Color(0.0, 0.42, 0.25), Color(0.93, 0.93, 0.9)],
	"east_asia": [Color(0.1, 0.3, 0.68), Color(0.93, 0.93, 0.9)],
	"DE": [Color(0.95, 0.78, 0.1), Color(0.06, 0.06, 0.07)],
}

static var _lock := Mutex.new()
static var _extents := {}


## Puts up block `b`'s signs in `kit`'s country (`st`: RoadMarkings.style_of) into AdventureProps arrays `signs`, from
## the block's anchor. Returns the labels for the words drawn as text: [{text, xf (Transform3D from the anchor, the
## text facing its +z), font (size), pixel, col, reach (m)}].
static func put_up(b: RoadBlock, kit: Dictionary, st: Dictionary, signs: Dictionary) -> Array:
	var labels := []
	var net := b.net
	var f: Dictionary = kit["facts"]
	var ctx := {"places": places_near(net, b.rect.grow(PLACE_MAX + 100.0)), "table": LIMIT_TABLE.get(str(kit["country"]), "world"),
		"mph": str(f.get("speed", "kmh")) == "mph", "nsl": str(f.get("marks", "")) == "uk",
		"rect": str(f.get("limit", "ring")) == "rect", "canada": str(kit["country"]) == "CA",
		"miles": str(f.get("distance", "km")) == "mi", "board": BOARDS.get(str(kit["country"]), [RoadMarkings.WHITE, RoadMarkings.BLACK, RoadMarkings.BLACK]),
		"end_board": str(kit.get("region", "")) in END_BOARDS,
		"finger": FINGERS.get(str(kit["country"]), FINGERS.get(str(kit.get("region", "")), [RoadMarkings.WHITE, RoadMarkings.BLACK]))}
	var o := b.anchor()
	for p in b.pieces:
		if str(p["surface"]) != "tarmac" or bool(p["ring"]) or str(p["class"]) in RoadMarkings.UNLINED:
			continue
		var q := RoadMarkings._prep(p, o)
		_limits_at_ends(signs, net, p, q, st, ctx)
		if str(p["class"]) in SIGNED:
			_places_crossed(signs, labels, net, p, q, st, ctx, o)
	for j in b.junctions:
		if j["kind"] == "roundabout":
			_chevrons(signs, net, j, o, st)
		elif j["kind"] in ["tee", "cross", "staggered", "fork", "multi"]:
			_fingerposts(signs, labels, net, j, o, st, ctx)
	return labels


# ---------------------------------------------------------------------------- places and limits

## The places within `rect` with their houses' reach: [{name, at (Vector2), r, n (buildings)}], those with at least
## BOARDED buildings, in the region's order.
static func places_near(net: RoadNet, rect: Rect2) -> Array:
	var out := []
	var r := net.region
	for i in r.places.size():
		var pl: Dictionary = r.places[i]
		var at := Vector2(float(pl["x"]), float(pl["z"]))
		if not rect.has_point(at):
			continue
		var ex := extent_of(net, i)
		if int(ex["n"]) >= BOARDED:
			out.append(ex)
	return out


## Place `i`'s houses' reach (see PLACE_STEP): {name, at, r, n}, worked out once per region.
static func extent_of(net: RoadNet, i: int) -> Dictionary:
	var r := net.region
	var key := "%s:%d" % [r.hash, i]
	_lock.lock()
	var have = _extents.get(key)
	_lock.unlock()
	if have is Dictionary:
		return have
	var pl: Dictionary = r.places[i]
	var at := Vector2(float(pl["x"]), float(pl["z"]))
	var ds := PackedFloat32Array()
	var k0 := RoadBlock.key_of(at.x - PLACE_MAX, at.y - PLACE_MAX)
	var k1 := RoadBlock.key_of(at.x + PLACE_MAX, at.y + PLACE_MAX)
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			for row: Array in net.buildings_in(Vector2i(kx, kz)):
				var d := at.distance_to(Vector2(float(row[0]), float(row[1])))
				if d < PLACE_MAX:
					ds.append(d)
	ds.sort()
	var reach := PLACE_STEP
	while reach < PLACE_MAX - PLACE_PAD:
		var ring := ds.bsearch(reach + PLACE_RING) - ds.bsearch(reach)
		if ring < PLACE_DENSE * PI * (pow(reach + PLACE_RING, 2.0) - reach * reach):
			break
		reach += PLACE_STEP
	var n := ds.bsearch(reach + PLACE_PAD)
	var ex := {"name": str(pl["name"]), "at": at, "r": clampf(reach + PLACE_PAD, PLACE_MIN, PLACE_MAX), "n": n}
	_lock.lock()
	_extents[key] = ex
	_lock.unlock()
	return ex


## The speed limit (km/h) on edge `ei` at `s`: the map's, or the country's for its class, built up inside a place of
## BUILT_UP buildings.
static func limit_at(net: RoadNet, ei: int, s: float, ctx: Dictionary) -> int:
	var r := net.region
	if ei < r.edge_limit.size() and r.edge_limit[ei] > 0:
		return r.edge_limit[ei]
	var p := net.point_at(ei, s)
	var built := false
	for pl: Dictionary in ctx["places"]:
		if int(pl["n"]) >= BUILT_UP and p.distance_to(pl["at"]) < float(pl["r"]):
			built = true
			break
	return RoutePlanner.default_limit(r.class_of(ei), str(ctx["table"]), built)


## Where piece `p` leaves a junction or a join, the limit sign for the traffic leaving onto it, if its limit isn't the
## one it came from: a side road's against the main road's, a main road's against the main road across, a join's
## against the road joined.
static func _limits_at_ends(signs: Dictionary, net: RoadNet, p: Dictionary, q: Dictionary, st: Dictionary, ctx: Dictionary) -> void:
	var r := net.region
	var ei := int(p["edge"])
	var len := net.length_of(ei)
	var at: PackedFloat32Array = q["at"]
	var ma := net.mouth(ei, int(p["a"]))
	var mb := net.mouth(ei, int(p["b"]))
	if len - ma - mb < LIMIT_ROOM:
		return
	for end: int in [0, 1]:
		var node := int(p["b"] if end == 1 else p["a"])
		var dir := 1.0 if end == 0 else -1.0
		var oneway := int(p["oneway"])
		if (oneway == 1 and dir < 0.0) or (oneway == -1 and dir > 0.0):
			continue
		var s := ma + LIMIT_AFTER if end == 0 else len - mb - LIMIT_AFTER
		if s < at[0] or s > at[at.size() - 1]:
			continue
		var others := []   # [edge, its s near the node]
		var j := net.junction_of(node)
		if j.is_empty():
			if r.adjacent[node].size() != 2:
				continue
			for oe in r.adjacent[node]:
				if oe != ei:
					others.append(oe)
		elif j["kind"] in ["roundabout", "end"]:
			continue
		else:
			var mine := {}
			for a: Dictionary in j["arms"]:
				if int(a["edge"]) == ei and int(a["node"]) == node:
					mine = a
			if mine.is_empty():
				continue
			for a: Dictionary in j["arms"]:
				if a == mine or not bool(a["main"]):
					continue
				others.append(int(a["edge"]))
		if others.is_empty():
			continue
		var here := limit_at(net, ei, s, ctx)
		var differs := false
		for oe: int in others:
			var ol := net.length_of(oe)
			var os := minf(LIMIT_AFTER, ol * 0.5)
			if limit_at(net, oe, os if r.edge_a[oe] == node else ol - os, ctx) != here:
				differs = true
		if differs:
			var side := dir * (-1.0 if bool(st["left"]) else 1.0)
			var e := float(q["e"])
			_limit_sign(signs, RoadMarkings._point(q, s, side * (e + RoadMarkings.SIGN_OUT), -0.3),
				-RoadMarkings._along(q, s) * dir, here, str(r.class_of(ei)), ctx)


## Where piece `p` crosses into a place's houses (and out): the limit sign each way where it changes, the name board
## coming in, and going out the end board where the country stands one.
static func _places_crossed(signs: Dictionary, labels: Array, net: RoadNet, p: Dictionary, q: Dictionary, st: Dictionary,
		ctx: Dictionary, o: Vector3) -> void:
	var pts: PackedVector3Array = q["pts"]
	var at: PackedFloat32Array = q["at"]
	var ei := int(p["edge"])
	var len := net.length_of(ei)
	var lo := net.mouth(ei, int(p["a"])) + PLACE_CLEAR
	var hi := len - net.mouth(ei, int(p["b"])) - PLACE_CLEAR
	var e := float(q["e"])
	var oneway := int(p["oneway"])
	for pl: Dictionary in ctx["places"]:
		var c: Vector2 = pl["at"] - Vector2(o.x, o.z)
		var rad := float(pl["r"])
		for k in pts.size() - 1:
			var d0 := Vector2(pts[k].x, pts[k].z).distance_to(c)
			var d1 := Vector2(pts[k + 1].x, pts[k + 1].z).distance_to(c)
			if (d0 - rad) * (d1 - rad) >= 0.0:
				continue
			var sc := at[k] + (rad - d0) / (d1 - d0) * (at[k + 1] - at[k])
			# (a crossing on the seam's overlap is the block's that has it before the seam)
			if sc < lo or sc > hi or (k == pts.size() - 2 and sc > at[k + 1] - RoadBlock.SEAM * 2.0):
				continue
			var din := 1.0 if d1 < rad else -1.0   # the way into the place
			var inside := limit_at(net, ei, sc + din * 2.0, ctx)
			var outside := limit_at(net, ei, sc - din * 2.0, ctx)
			for dir: float in [din, -din]:
				if (oneway == 1 and dir < 0.0) or (oneway == -1 and dir > 0.0):
					continue
				var coming_in := dir == din
				var side := dir * (-1.0 if bool(st["left"]) else 1.0)
				var facing := -RoadMarkings._along(q, sc) * dir
				if inside != outside:
					_limit_sign(signs, RoadMarkings._point(q, sc, side * (e + RoadMarkings.SIGN_OUT), -0.3), facing,
						inside if coming_in else outside, str(p["class"]), ctx)
				if coming_in or bool(ctx["end_board"]):
					var bs := sc + din * BOARD_IN
					var foot := RoadMarkings._point(q, bs, side * (e + RoadMarkings.SIGN_OUT + 0.5), -0.3)
					_name_board(signs, labels, foot, -RoadMarkings._along(q, bs) * dir, str(pl["name"]), not coming_in, ctx)


# ---------------------------------------------------------------------------- the signs

## A speed limit sign for `kmh` on a pole at `foot` facing `facing`: the red ring with the limit in black (km/h, or
## mph where the country uses them), Britain's national limit disc where it's the open road's, or America's and
## Canada's white rectangle.
static func _limit_sign(a: Dictionary, foot: Vector3, facing: Vector3, kmh: int, cls: String, ctx: Dictionary) -> void:
	var shown := roundi(kmh / 1.609344 / 5.0) * 5 if bool(ctx["mph"]) else roundi(kmh / 5.0) * 5
	shown = clampi(shown, 5, 130)
	var h := RoadMarkings.SIGN_H + 0.3
	RoadMarkings._pole(a, foot, h)
	var c := foot + Vector3(0.0, h, 0.0) + facing * RoadMarkings.PLATE_OUT
	var across := Vector3.UP.cross(facing).normalized()
	var black := RoadMarkings.BLACK
	var white := RoadMarkings.WHITE
	if bool(ctx["rect"]):
		RoadMarkings._plate(a, c, facing, _rect(0.62, 0.78), black)
		RoadMarkings._shape(a, c, facing, _rect(0.57, 0.73), white, 0.006)
		if bool(ctx["canada"]):
			SignWords.draw(a, "MAXIMUM", c + Vector3(0.0, 0.24, 0.0) + facing * 0.012, across, Vector3.UP, 0.08, black, facing, 0.48)
		else:
			SignWords.draw(a, "SPEED", c + Vector3(0.0, 0.26, 0.0) + facing * 0.012, across, Vector3.UP, 0.08, black, facing, 0.48)
			SignWords.draw(a, "LIMIT", c + Vector3(0.0, 0.13, 0.0) + facing * 0.012, across, Vector3.UP, 0.08, black, facing, 0.48)
		SignWords.draw(a, str(shown), c + Vector3(0.0, -0.13, 0.0) + facing * 0.012, across, Vector3.UP, 0.28, black, facing, 0.5)
		return
	if bool(ctx["nsl"]) and kmh >= 96:
		# The national limit: a white disc struck through from bottom left to top right.
		RoadMarkings._plate(a, c, facing, RoadMarkings._ngon(24, 0.38), black)
		RoadMarkings._shape(a, c, facing, RoadMarkings._ngon(24, 0.355), white, 0.006)
		RoadMarkings._shape(a, c, facing, RoadMarkings._bar(Vector2(-0.24, -0.24), Vector2(0.24, 0.24), 0.13), black, 0.012)
		return
	RoadMarkings._plate(a, c, facing, RoadMarkings._ngon(24, 0.38), RoadMarkings.RED)
	RoadMarkings._shape(a, c, facing, RoadMarkings._ngon(24, 0.29), white, 0.006)
	SignWords.draw(a, str(shown), c + facing * 0.012, across, Vector3.UP, 0.22, black, facing, 0.44)


## A rectangle `w` by `h` about its middle, as a shape's points.
static func _rect(w: float, h: float) -> Array:
	return [Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)]


## A place's name board on two posts at `foot` facing `facing`, in the country's colours (going out, its end board:
## the name struck through in red), the name a label.
static func _name_board(a: Dictionary, labels: Array, foot: Vector3, facing: Vector3, name: String, end: bool, ctx: Dictionary) -> void:
	var cols: Array = ctx["board"]
	var w := clampf(0.5 + name.length() * 0.2, 1.2, 4.0)
	var h := 0.62
	var y := 1.5
	var across := Vector3.UP.cross(facing).normalized()
	for sx: float in [-w * 0.38, w * 0.38]:
		RoadMarkings._pole(a, foot + across * sx, y + h * 0.5)
	var c := foot + Vector3(0.0, y, 0.0) + facing * RoadMarkings.PLATE_OUT
	RoadMarkings._plate(a, c, facing, _rect(w, h), cols[1])
	RoadMarkings._shape(a, c, facing, _rect(w - 0.08, h - 0.08), cols[0], 0.006)
	if end:
		RoadMarkings._shape(a, c, facing, RoadMarkings._bar(Vector2(-w * 0.42, -h * 0.3), Vector2(w * 0.42, h * 0.3), 0.07),
			RoadMarkings.RED, 0.03)
	labels.append({"text": name, "xf": Transform3D(Basis(across, Vector3.UP, facing), c + facing * 0.02), "font": 48,
		"pixel": 0.007, "col": cols[2], "reach": 160.0})


## Fingerposts at junction `j`'s side roads of a SIGNED class: on the corner of each, an arm pointing down it naming
## the place it goes to and how far.
static func _fingerposts(a: Dictionary, labels: Array, net: RoadNet, j: Dictionary, o: Vector3, st: Dictionary, ctx: Dictionary) -> void:
	var r := net.region
	var mid := Vector2(float(j["pos"].x), float(j["pos"].z))
	for arm: Dictionary in j["arms"]:
		if bool(arm["main"]) or str(arm["class"]) not in SIGNED:
			continue
		var ei := int(arm["edge"])
		var node := int(arm["node"])
		var len := net.length_of(ei)
		var m := net.mouth(ei, node)
		if len < m + 10.0:
			continue
		var s := m + 2.0 if r.edge_a[ei] == node else len - m - 2.0
		var h := net.heading_at(ei, s) + (0.0 if r.edge_a[ei] == node else PI)
		var to := _destination(net, mid, h)
		if to.is_empty():
			continue
		var out := Vector3(sin(h), 0.0, -cos(h))
		var right := Vector3(cos(h), 0.0, sin(h))
		var p := net.point_at(ei, s)
		var side := -1.0 if bool(st["left"]) else 1.0
		var foot := Vector3(p.x, net.road_y(ei, s) - 0.3, p.y) + right * side * (float(arm["width"]) * 0.5 + 1.6) - o
		var far := float(to["d"]) * ROAD_FACTOR / (1609.344 if bool(ctx["miles"]) else 1000.0)
		var text := "%s  %d" % [to["name"], roundi(far)]
		if far < 0.875:
			# (under a mile Britain's fingerposts count in quarters; under a kilometre, no distance)
			text = "%s  %s" % [to["name"], ["¼", "¼", "½", "¾"][roundi(far * 4.0)]] if bool(ctx["miles"]) else str(to["name"])
		_fingerpost(a, labels, foot, out, text, ctx["finger"])


## The place a road leaving `from` on bearing `h` most likely goes to: the nearest one with houses within
## FINGER_ANGLE of its way (nearer ones, and those more in line, first). {name, d} or {}.
static func _destination(net: RoadNet, from: Vector2, h: float) -> Dictionary:
	var best := {}
	var best_score := INF
	var r := net.region
	for i in r.places.size():
		var pl: Dictionary = r.places[i]
		var at := Vector2(float(pl["x"]), float(pl["z"]))
		var d := from.distance_to(at)
		if d < FINGER_MIN or d > FINGER_REACH:
			continue
		var off := absf(angle_difference(h, RoadNet._bearing(at - from)))
		if off > FINGER_ANGLE:
			continue
		var score := d * (1.0 + off * 2.0)
		if score < best_score:
			var ex := extent_of(net, i)
			if int(ex["n"]) < BOARDED or d < float(ex["r"]):
				continue
			best_score = score
			best = {"name": str(pl["name"]), "d": d}
	return best


## A fingerpost at `foot` with its arm pointing `out` (level), `text` on both faces.
static func _fingerpost(a: Dictionary, labels: Array, foot: Vector3, out: Vector3, text: String, cols: Array) -> void:
	var top := 2.3
	AdventureProps.box(a, Transform3D(Basis(), foot), Vector3(0.11, top, 0.11), cols[0] if cols[0] != RoadMarkings.WHITE else Color(0.9, 0.9, 0.88), false)
	var len := clampf(0.5 + text.length() * 0.105, 1.2, 3.2)
	var hh := 0.16
	var c := foot + Vector3(0.0, top - 0.4, 0.0) + out * (len * 0.5 + 0.05)
	# Its board, pointed at the end it points to: x along `out` as seen from each face.
	var pts := [Vector2(-len * 0.5, -hh), Vector2(len * 0.5 - 0.18, -hh), Vector2(len * 0.5, 0.0), Vector2(len * 0.5 - 0.18, hh), Vector2(-len * 0.5, hh)]
	var right := Vector3.UP.cross(out).normalized()   # (a face looking this way sees `out` to its left)
	for face: float in [1.0, -1.0]:
		var facing := right * face
		var shown := []
		for v: Vector2 in pts:
			shown.append(Vector2(-v.x * face, v.y))
		RoadMarkings._shape(a, c, facing, shown, cols[0], 0.03)
		var x := Vector3.UP.cross(facing).normalized()
		labels.append({"text": text, "xf": Transform3D(Basis(x, Vector3.UP, facing), c + facing * 0.045 - out * 0.06),
			"font": 40, "pixel": 0.005, "col": cols[1], "reach": 90.0})


## The chevron boards on roundabout `j`'s island, one facing each road in, pointing the way the traffic goes round
## (right where the country drives on the right, left where it drives on the left).
static func _chevrons(a: Dictionary, net: RoadNet, j: Dictionary, o: Vector3, st: Dictionary) -> void:
	var island := float(j["island"])
	if island < CHEVRON_MIN:
		return
	var r := net.region
	var point := -1.0 if bool(st["left"]) else 1.0
	var board := RoadMarkings.BLACK
	var ink := RoadMarkings.WHITE
	match str(st.get("marks", "")):
		"us", "latam", "jp", "asia":
			board = RoadMarkings.YELLOW
			ink = RoadMarkings.BLACK
		"uk", "au":
			pass
		_:
			board = RoadMarkings.WHITE
			ink = RoadMarkings.RED
	for arm: Dictionary in j["arms"]:
		var ei := int(arm["edge"])
		var node := int(arm["node"])
		var oneway := r.edge_oneway[ei]
		# (no board for a road that only leaves the ring)
		if (oneway == 1 and r.edge_a[ei] == node) or (oneway == -1 and r.edge_b[ei] == node):
			continue
		var h := float(arm["heading"])
		var out := Vector3(sin(h), 0.0, -cos(h))
		# (on the island's rim as it's laid, tilted with the ring: RoadBlock._island)
		var full := net.junction_of(int(j["node"]))
		var foot: Vector3 = j["pos"] - o + out * (net.island_r(full, h) - CHEVRON_IN)
		foot.y = net.ring_y(full, Vector2(foot.x + o.x, foot.z + o.z)) - o.y + RoadBlock.ISLAND_H
		var across := Vector3.UP.cross(out).normalized()
		var w := minf(2.4, island * 0.9)
		for sx: float in [-w * 0.4, w * 0.4]:
			RoadMarkings._pole(a, foot + across * sx, 1.15)
		var c := foot + Vector3(0.0, 0.85, 0.0) + out * RoadMarkings.PLATE_OUT
		RoadMarkings._plate(a, c, out, _rect(w, 0.55), board)
		var n := 3 if w > 1.6 else 2
		for k in n:
			var cx := (float(k) - (n - 1) * 0.5) * (w / n)
			RoadMarkings._shape(a, c, out, RoadMarkings._bar(Vector2(cx - point * 0.12, 0.2), Vector2(cx + point * 0.1, 0.0), 0.11), ink, 0.006)
			RoadMarkings._shape(a, c, out, RoadMarkings._bar(Vector2(cx + point * 0.1, 0.0), Vector2(cx - point * 0.12, -0.2), 0.11), ink, 0.006)
