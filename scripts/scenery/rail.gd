extends RefCounted
## The railways (Ride Anywhere v2, phase D round 1, D2): track along the map's real lines (ballast, sleepers, rails, and
## the overhead wires where the line's region electrifies it), its bridges and viaducts, tunnel mouths, level crossings
## beside the road with barriers that come down for the train, stations and halts with a platform, canopy and name
## board, and a train on every line on a timetable set by the line alone (rail_train.gd), so the crew sees the same.
##
## A model of the scenery streamer's (docs/scenery.md): the kit library's rail rows name "rail:..." and the streamer
## calls lay_out on a worker for each 512 m block with any of them in it, then mesh for the instanced parts and dress on
## the main thread for the rest.
##
## Simon's two rules, as this file keeps them. Nothing here touches a road, the land under one or what a bike can touch
## (there's no collision at all): the track stops short of every carriageway and verge it meets on the level (a level
## crossing: the road's surface and paint are the road's), stands on the land as it is near a road, and only well away
## from one rides its own smooth line over the land, on a skirt of embankment where the land dips under it (the land is
## never cut). A bridge carries the line over a road at least a road bridge's headroom up, and no pier stands in a
## carriageway or its verge. And the whole world: every rail line the map has, wherever it is, laid out the same way,
## each region's rolling stock and bridges from the kit library with a default for every region.
##
## Everything is in the region frame (x east, z south) and comes from the region's features and the land alone, so it's
## the same on every machine: a line's pieces are joined into whole lines once a region (runs_of), and a block's share
## of a line is worked out from its own samples STEP apart along the whole line, PAD past the block, so two blocks agree
## where they meet.

## Part of the crew's builder hash (SceneryStreamer.script_versions): bump it when what a block lays out changes.
const VERSION := 1
const RailTrains := preload("res://scripts/scenery/rail_train.gd")
const Geo := preload("res://scripts/scenery/rail_geo.gd")
const Models := preload("res://scripts/scenery/rail_models.gd")

## The rail kinds laid as track, and their gauge (m; 0 for a monorail's beam).
const GAUGES := {"railway": 1.435, "narrow_gauge": 1.0, "light_rail": 1.435, "tram": 1.435, "funicular": 1.2,
	"monorail": 0.0, "subway": 1.435}
## The kinds a level crossing is built for where one meets a road on the level (a tram runs in the road itself).
const CROSSING_KINDS := ["railway", "narrow_gauge", "light_rail"]
## A line's flags (tools/feature_bake.py's): on a bridge, in a tunnel, disused or abandoned, being built.
const BRIDGE := 1
const TUNNEL := 2
const DISUSED := 4
const BUILDING := 8
## Samples along a line this far apart (m), from its start; a block works out its own PAD past its edges.
const STEP := 4.0
const PAD := 112.0  # (more than SMOOTH * PASSES samples)
## The line's height is the land's smoothed over SMOOTH samples either side, PASSES times over (a gentle ruling grade).
const SMOOTH := 6
const PASSES := 3
## Within NEAR_FROM (m) of a carriageway's edge the track sits on the land as it is, easing over to its own smoothed
## line by NEAR_TO.
const NEAR_FROM := 6.0
const NEAR_TO := 26.0
## The track stops this far (m) past a road's verge where it meets one on the level (or runs along one too close).
const CLEAR := 0.6
## A bridge over a road leaves a road bridge's headroom under its deck (RoadNet.HEADROOM) and its deck's depth; where it
## has to climb for it, it's level CROWN_FLAT m either side and ramps at RAMP.
const DECK_DEPTH := 1.2
const CROWN_FLAT := 15.0
const RAMP := 0.03
## The line eases onto a bridge's deck or a tunnel's mouth over at least EASE and at most EASE_MOST (m), as far as
## climbing at EASE_GRADE takes to make up the height between the deck's end and the land there.
const EASE := 48.0
const EASE_MOST := 300.0
const EASE_GRADE := 0.025
## A bridge's deck is worked out from the land over this far (m) before each end.
const END_LOOK := 40.0
## Ballast: its top's half width (m) and the shoulder's, and how deep under the land a skirt goes.
const BALLAST_W := 1.6
const SHOULDER := 0.6
const SHOULDER_DROP := 0.45
const SKIRT_SLOPE := 1.5
const BURY := 0.5
## Sleepers this far apart (m), and how far they're drawn.
const SLEEPER_GAP := 0.65
const SLEEPER_REACH := 450.0
## Sleeper top and rail top above the ballast (m).
const SLEEPER_TOP := 0.12
const RAIL_TOP := 0.27
## Overhead line: a mast every MAST_GAP m, the contact wire WIRE_H m over the rails.
const MAST_GAP := 54.0
const WIRE_H := 5.6
## A monorail's beam stands this high (m), a pillar every PILLAR_GAP.
const MONO_H := 6.0
const PILLAR_GAP := 24.0
## Bridges: piers this far apart by style (m), an arch's height under the deck and the deck's width.
const PIER_GAP := {"stone": 15.0, "concrete": 30.0, "steel": 24.0}
const DECK_W := 4.6
## A pier only where the deck is this far over the land (m); lower than that the line's on its embankment.
const PIER_FROM := 2.5
## A line shorter than this (m) has no train (a siding, a yard's track).
const TRAIN_FROM := 600.0
## Parallel lines (a double track mapped as two) are within this of each other (m): each runs trains one way.
const PAIR_M := 7.0
## A station's platform (m): long, wide, high over the rail top; a halt's shorter and narrower.
const PLATFORM := {"railway_station": [120.0, 4.5], "railway_halt": [50.0, 2.6]}
const PLATFORM_EDGE := 1.65
const PLATFORM_H := 0.9
## A station's point is matched to a line this near (m).
const STATION_NEAR := 70.0
## A level crossing's barriers: how far past the verge their posts stand (m), and the arm's height.
const POST_OUT := SceneryStreamer.CLEAR + 0.2
const ARM_H := 1.0
const TRACK_HALF := 3.0
## Where a crossing's barriers come down: a train within this of it along the line (m).
const CLOSE_M := 550.0
## How far the track (and what's beside it) is drawn (m), and the trains.
const REACH := 2000.0

## Colours (linear-ish albedo): ballast, the embankment's grass and earth, sleepers, rails, stone and concrete, the
## platform's edge.
const C_BALLAST := Color(0.40, 0.38, 0.35)
const C_GRASS := Color(0.30, 0.34, 0.20)
const C_EARTH := Color(0.33, 0.29, 0.22)
const C_STONE := Color(0.50, 0.47, 0.42)
const C_CONCRETE := Color(0.62, 0.61, 0.58)
const C_STEEL := Color(0.22, 0.26, 0.25)
const C_PLATFORM := Color(0.52, 0.50, 0.48)
const C_EDGE := Color(0.92, 0.85, 0.30)
const C_DARK := Color(0.04, 0.04, 0.05)
const C_WHITE := Color(0.92, 0.92, 0.90)
const C_RED := Color(0.75, 0.08, 0.06)
const C_POST := Color(0.12, 0.12, 0.13)

static var _runs := {}
static var _lock := Mutex.new()
## What the land and roads were found to be along each run, kept once the ground round them is final so the blocks a
## run passes through (overlapping by PAD) and the lay-outs again after it ask once: net's instance id -> {run id ->
## {sample's s in quarter metres -> [land, road], Vector2i(span's ends in quarter metres) -> its deck (_deck)}}.
static var _seen := {}
## How far round a section the ground must be final for what was found along it to be kept (m): past the roads' banks
## and the stretch of a road its height is faired over.
const SEEN_PAD := 300.0
static var _meshes := {}


# ---------------------------------------------------------------------------- whole lines

## The region's rail lines joined into whole lines (cached a region): {"runs": [run, ...], "filed": {Vector2i block ->
## [[run index, from s, to s], ...]}}. A run: {kind, id, name, pts: PackedVector2Array, cum: PackedFloat32Array (s at each
## point), flags: PackedInt32Array (a segment's), len, spans: [[s0, s1, flag, style], ...] (its bridges and tunnels),
## track: false for a viaduct the map has with no live line on it, kit (its region's row), timetable (rail_train.gd's)}.


static func runs_of(region: RealRegion) -> Dictionary:
	var id := region.get_instance_id()
	_lock.lock()
	var have = _runs.get(id)
	_lock.unlock()
	if have != null:
		return have
	var built := build_runs(region.features.get("lines", []), region)
	_lock.lock()
	if _runs.size() > 6:
		_runs.clear()
	_runs[id] = built
	_lock.unlock()
	return built


## Forgets the joined lines (a region's features changed: the tests).
static func forget() -> void:
	_lock.lock()
	_runs.clear()
	_seen.clear()
	_lock.unlock()


static func _end_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))


## Joins `lines` (RealRegion.features' lines) into whole lines: pieces meeting end to end (the map cuts a line at every
## cell edge and change of flags) are one line, carried on through a junction along the straightest way on, the other
## ways their own lines. A disused or unbuilt line is left out; a viaduct the map has with no live line along it is a
## line of its own with no track (it still stands). `region` (or null) chooses each line's kit.
static func build_runs(lines: Array, region: RealRegion) -> Dictionary:
	var picks: Array[int] = []
	var viaducts: Array[int] = []
	for i in lines.size():
		var l: Array = lines[i]
		if (l[1] as PackedVector2Array).size() < 2:
			continue
		if GAUGES.has(l[0]) and int(l[4]) & (DISUSED | BUILDING) == 0:
			picks.append(i)
		elif l[0] == "viaduct":
			viaducts.append(i)
	var ends := {}   # end key -> [[line, at its last point], ...]
	for i in picks:
		var pts: PackedVector2Array = lines[i][1]
		for at_end in [false, true]:
			var k := _end_key(pts[pts.size() - 1] if at_end else pts[0])
			if not ends.has(k):
				ends[k] = []
			(ends[k] as Array).append([i, at_end])
	var used := {}
	var runs: Array = []
	for i in picks:
		if used.has(i):
			continue
		used[i] = true
		var pts: PackedVector2Array = (lines[i][1] as PackedVector2Array).duplicate()
		var flags := PackedInt32Array()
		flags.resize(pts.size() - 1)
		flags.fill(int(lines[i][4]))
		var ids: Array = [str(lines[i][6]) if lines[i][6] != null else ""]
		# (on forwards from its last point, then backwards from its first: the line reversed and carried on again)
		for way in 2:
			while true:
				var next := _next_piece(lines, ends, used, pts, str(lines[i][0]))
				if next.is_empty():
					break
				var j: int = next[0]
				used[j] = true
				var more: PackedVector2Array = lines[j][1]
				if bool(next[1]):
					more = _reversed(more)
				for k in range(1, more.size()):
					pts.append(more[k])
					flags.append(int(lines[j][4]))
				if lines[j][6] != null:
					ids.append(str(lines[j][6]))
			if way == 0:
				pts = _reversed(pts)
				flags.reverse()
		ids.sort()
		var run := _make_run(str(lines[i][0]), pts, flags, ",".join(ids).sha1_text().left(12), str(lines[i][5]))
		if run["len"] > 1.0:
			runs.append(run)
	_style_spans(runs, lines, viaducts)
	# A viaduct no live line is on still stands: a line of its own, all bridge, no track.
	for v in viaducts:
		if _on_a_run(runs, lines[v][1]):
			continue
		var pts: PackedVector2Array = lines[v][1]
		var flags := PackedInt32Array()
		flags.resize(pts.size() - 1)
		flags.fill(BRIDGE)
		var run := _make_run("viaduct", pts, flags, str(lines[v][6]) if lines[v][6] != null else str(v), str(lines[v][5]))
		run["track"] = false
		for sp: Array in run["spans"]:
			sp[3] = "stone"
		runs.append(run)
	_pair(runs)
	for r: Dictionary in runs:
		var mid := _point_on(r, float(r["len"]) * 0.5)
		var region_id := ""
		if region != null and (region.frame_lat != 0.0 or region.frame_lon != 0.0):
			region_id = str(RegionKit.at_frame(region.frame_lat, region.frame_lon, mid.x, mid.y).get("region", ""))
		r["region"] = region_id
		r["kit"] = _kit_of(str(r["kind"]), region_id)
		if str(r.get("bridge_style", "")) == "":
			for sp: Array in r["spans"]:
				if sp[3] == "":
					sp[3] = str(r["kit"].get("bridge", "concrete"))
		r["timetable"] = RailTrains.timetable_of(r)
	return {"runs": runs, "filed": _file(runs)}


## The kit library's rail row for `kind` in regional kit `region_id`, with the railway's laid under any kind's own.
static func _kit_of(kind: String, region_id: String) -> Dictionary:
	var base := SceneryStreamer.kit("railway", region_id)
	if kind != "railway":
		base.merge(SceneryStreamer.kit(kind, region_id), true)
	return base


static func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var out := p.duplicate()
	out.reverse()
	return out


## The piece that carries the line on from `pts`' last point: the only other piece there, or at a junction the
## straightest way on (within 35 degrees). [line, whether it's met at its own last point], or [].
static func _next_piece(lines: Array, ends: Dictionary, used: Dictionary, pts: PackedVector2Array, kind: String) -> Array:
	var at: Vector2 = pts[pts.size() - 1]
	var there: Array = ends.get(_end_key(at), [])
	var dir_in: Vector2 = (at - pts[pts.size() - 2]).normalized()
	var best: Array = []
	var best_turn := deg_to_rad(35.0)
	for e: Array in there:
		var j: int = e[0]
		if used.has(j) or str(lines[j][0]) != kind:
			continue
		var p: PackedVector2Array = lines[j][1]
		var dir_out: Vector2 = (p[p.size() - 2] - p[p.size() - 1]).normalized() if bool(e[1]) else (p[1] - p[0]).normalized()
		var turn := absf(dir_in.angle_to(dir_out))
		if turn < best_turn or (there.size() == 2 and best.is_empty() and turn < deg_to_rad(80.0)):
			best_turn = turn
			best = e
	return best


static func _make_run(kind: String, pts: PackedVector2Array, flags: PackedInt32Array, id: String, nm: String) -> Dictionary:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var d := 0.0
	for k in range(1, pts.size()):
		d += pts[k].distance_to(pts[k - 1])
		cum[k] = d
	var spans: Array = []
	var k := 0
	while k < flags.size():
		var f := flags[k] & (BRIDGE | TUNNEL)
		if f == 0:
			k += 1
			continue
		var k1 := k
		while k1 + 1 < flags.size() and flags[k1 + 1] & (BRIDGE | TUNNEL) == f:
			k1 += 1
		spans.append([cum[k], cum[k1 + 1], f, ""])
		k = k1 + 1
	return {"kind": kind, "id": id, "name": nm, "pts": pts, "cum": cum, "flags": flags, "len": d, "spans": spans,
		"track": true, "pair": 0}


## Where the map has a viaduct along a run's bridge, that bridge is stone arches (the viaduct's own); `viaducts` are
## the indices of the viaduct lines in `lines`.
static func _style_spans(runs: Array, lines: Array, viaducts: Array[int]) -> void:
	for r: Dictionary in runs:
		for sp: Array in r["spans"]:
			if int(sp[2]) != BRIDGE:
				continue
			var mid := _point_on(r, (float(sp[0]) + float(sp[1])) * 0.5)
			for v in viaducts:
				if _near_line(lines[v][1], mid, 14.0):
					sp[3] = "stone"
					break


## Whether line `pts` runs along any run's bridge (its middle within 14 m of one).
static func _on_a_run(runs: Array, pts: PackedVector2Array) -> bool:
	var mid := _line_mid(pts)
	for r: Dictionary in runs:
		for sp: Array in r["spans"]:
			if int(sp[2]) != BRIDGE:
				continue
			var a := float(sp[0])
			var b := float(sp[1])
			var s := a
			while s <= b + 0.01:
				if _point_on(r, s).distance_to(mid) < 14.0:
					return true
				s += 6.0
	return false


static func _line_mid(pts: PackedVector2Array) -> Vector2:
	var total := 0.0
	for k in range(1, pts.size()):
		total += pts[k].distance_to(pts[k - 1])
	var d := 0.0
	for k in range(1, pts.size()):
		var seg := pts[k].distance_to(pts[k - 1])
		if d + seg >= total * 0.5:
			return pts[k - 1].lerp(pts[k], (total * 0.5 - d) / maxf(seg, 1e-6))
		d += seg
	return pts[0]


static func _near_line(pts: PackedVector2Array, p: Vector2, within: float) -> bool:
	for k in range(1, pts.size()):
		if Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k]).distance_to(p) < within:
			return true
	return false


## Marks each run that has another of its kind alongside most of the way (a double track mapped as two lines): "pair" is
## +1 or -1, the way its trains run (each on the left-hand line of the two, or the right where the kit says so), 0 alone.
static func _pair(runs: Array) -> void:
	var grid := {}   # 64 m cell -> [[run, segment], ...]
	for ri in runs.size():
		var r: Dictionary = runs[ri]
		var pts: PackedVector2Array = r["pts"]
		for k in range(1, pts.size()):
			# (in every cell along it)
			var cells := {}
			var seg := pts[k - 1].distance_to(pts[k])
			for j in int(seg / 32.0) + 2:
				cells[Vector2i((pts[k - 1].lerp(pts[k], minf(j * 32.0 / maxf(seg, 0.01), 1.0)) / 64.0).floor())] = true
			for c: Vector2i in cells:
				if not grid.has(c):
					grid[c] = []
				(grid[c] as Array).append([ri, k])
	for ri in runs.size():
		var r: Dictionary = runs[ri]
		if not r["track"] or float(r["len"]) < TRAIN_FROM:
			continue
		var sides := 0.0
		var found := 0
		for f: float in [0.25, 0.5, 0.75]:
			var s: float = float(r["len"]) * f
			var p := _point_on(r, s)
			var ahead := (_point_on(r, minf(s + 2.0, float(r["len"]))) - _point_on(r, maxf(s - 2.0, 0.0))).normalized()
			var best := PAIR_M
			var side := 0.0
			var c := Vector2i((p / 64.0).floor())
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for e: Array in grid.get(c + Vector2i(dx, dz), []):
						var o: Dictionary = runs[int(e[0])]
						if int(e[0]) == ri or o["kind"] != r["kind"]:
							continue
						var q := Geometry2D.get_closest_point_to_segment(p, o["pts"][int(e[1]) - 1], o["pts"][int(e[1])])
						var d := q.distance_to(p)
						if d < best and d > 0.5:
							best = d
							side = signf(ahead.cross(q - p))
			if side != 0.0:
				found += 1
				sides += side
		if found >= 2:
			# (the other line to its right (x east, z south: a positive cross is to the right) puts this one on the left)
			r["pair"] = 1 if sides > 0.0 else -1


## The point `s` m along run `r`.
static func _point_on(r: Dictionary, s: float) -> Vector2:
	var pts: PackedVector2Array = r["pts"]
	var cum: PackedFloat32Array = r["cum"]
	if s <= 0.0:
		return pts[0]
	if s >= cum[cum.size() - 1]:
		return pts[pts.size() - 1]
	var k := clampi(cum.bsearch(s, true), 1, cum.size() - 1)
	var seg := cum[k] - cum[k - 1]
	return pts[k - 1].lerp(pts[k], (s - cum[k - 1]) / seg if seg > 0.0 else 0.0)


## The flags of run `r` `s` m along.
static func _flags_at(r: Dictionary, s: float) -> int:
	var cum: PackedFloat32Array = r["cum"]
	var k := clampi(cum.bsearch(s, true), 1, cum.size() - 1)
	return (r["flags"] as PackedInt32Array)[k - 1]


## The span (bridge or tunnel) run `r` is in `s` m along, or [].
static func _span_at(r: Dictionary, s: float) -> Array:
	for sp: Array in r["spans"]:
		if s >= float(sp[0]) - 0.01 and s <= float(sp[1]) + 0.01:
			return sp
	return []


## The blocks each run's samples are needed in: every block a piece of it passes within PAD of, with the run's s from and
## to there (the piece clipped to the block grown by PAD, and PAD more along it either way).
static func _file(runs: Array) -> Dictionary:
	var out := {}
	for ri in runs.size():
		var r: Dictionary = runs[ri]
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum"]
		var got := {}   # block -> Vector2(from, to)
		for k in range(1, pts.size()):
			var a := pts[k - 1]
			var b := pts[k]
			var box := Rect2(a, Vector2.ZERO).expand(b).grow(PAD)
			var k0 := RoadBlock.key_of(box.position.x, box.position.y)
			var k1 := RoadBlock.key_of(box.end.x, box.end.y)
			var seg := cum[k] - cum[k - 1]
			for bx in range(k0.x, k1.x + 1):
				for bz in range(k0.y, k1.y + 1):
					var bk := Vector2i(bx, bz)
					var t := _clip(a, b, Rect2(Vector2(bk) * RoadBlock.SIZE, Vector2.ONE * RoadBlock.SIZE).grow(PAD))
					if t.x > t.y:
						continue
					var was: Vector2 = got.get(bk, Vector2(INF, -INF))
					got[bk] = Vector2(minf(was.x, cum[k - 1] + t.x * seg - PAD), maxf(was.y, cum[k - 1] + t.y * seg + PAD))
		for b: Vector2i in got:
			if not out.has(b):
				out[b] = []
			var v: Vector2 = got[b]
			(out[b] as Array).append([ri, maxf(v.x, 0.0), minf(v.y, float(r["len"]))])
	return out


## The share of the segment from `a` to `b` inside `rect`: Vector2(from, to) as fractions along it (from > to for none).
static func _clip(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(d[axis]) < 1e-9:
			if a[axis] < lo or a[axis] > hi:
				return Vector2(1.0, 0.0)
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


# ---------------------------------------------------------------------------- a block

## What block `key` holds of the region's railways (the scenery streamer's model hook, on a worker): {"items": {}, "dress":
## {multis: {piece: [Transform3D]} (rail_models.gd's pieces), meshes (what's drawn once: tunnel mouths, crossings,
## boards), portions and gates (the trains' and barriers', rail_train.gd's), boards}, "ms"}. Every transform in the
## block's frame (its corner at key * 512). `rows` is the streamer's: the rail rows in this block (points, lines, areas)
## and their kits; the lines are read whole from the region (runs_of), the stations from its points.
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var runs := runs_of(net.region)
	var o := Vector2(key) * RoadBlock.SIZE
	var own := Rect2(o, Vector2.ONE * RoadBlock.SIZE)
	var memo := {}
	var geo := Geo.new()
	var multis := {}
	var portions: Array = []
	var crossings: Array = []
	var boards: Array = []
	var sections := {}   # run index -> its section here (for the stations)
	for f: Array in runs["filed"].get(key, []):
		var r: Dictionary = runs["runs"][int(f[0])]
		var sec := section(net, r, float(f[1]), float(f[2]), memo)
		if sec.is_empty():
			continue
		sections[int(f[0])] = sec
		_lay_track(multis, r, sec, own, o)
		_lay_spans(geo, multis, net, r, sec, own, o, memo)
		if r["track"] and str(r["kind"]) in CROSSING_KINDS:
			crossings.append_array(_crossings(net, r, int(f[0]), sec, own))
		if r["track"] and r["timetable"].get("mode", "") != "":
			portions.append(_portion(int(f[0]), r, sec, own, o))
	crossings = _merge_crossings(crossings)
	var gates: Array = []
	for c: Dictionary in crossings:
		gates.append(_lay_crossing(geo, net, c, o))
	for pr: Array in rows.get("points", []):
		var row: Array = pr[0]
		if PLATFORM.has(row[0]):
			var b := _lay_station(geo, multis, net, runs, sections, row, o)
			if not b.is_empty():
				boards.append(b)
	var out := {"items": {}, "dress": {"multis": multis, "meshes": geo.surfs, "portions": portions, "gates": gates,
		"boards": boards, "reach": REACH}}
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


static func _add(multis: Dictionary, model: String, xf: Transform3D) -> void:
	if not multis.has(model):
		multis[model] = []
	(multis[model] as Array).append(xf)


## What lays a piece (rail_models.gd's: a unit long along its -z) from `a` to `b`: x level across the line to its right,
## scaled by `wide`, y square to the line, scaled by `tall`.
static func _piece(a: Vector3, b: Vector3, wide := 1.0, tall := 1.0) -> Transform3D:
	var d := b - a
	var r := Vector3(-d.z, 0.0, d.x).normalized()
	var up := r.cross(d.normalized())
	return Transform3D(Basis(r * wide, up * tall, -d), a)


## A run's samples from `s0` to `s1` (m along it), STEP apart from its start, and the line's height at each: {"s":
## PackedFloat32Array, "p": PackedVector2Array, "land", "y" (the rail bed's top), "flags": PackedInt32Array, "cut":
## PackedByteArray (no track: on or by a road, or in a tunnel), "road": [[edge, s, lat, width, y] or [] a sample]}.
## {} where the land isn't there yet.
static func section(net: RoadNet, r: Dictionary, s0: float, s1: float, memo: Dictionary) -> Dictionary:
	var length := float(r["len"])
	var k0 := floori(s0 / STEP)
	var k1 := ceili(s1 / STEP)
	var ss := PackedFloat32Array()
	for k in range(k0, k1 + 1):
		var s := minf(k * STEP, length)
		if ss.is_empty() or s > ss[ss.size() - 1] + 0.01:
			ss.append(s)
	if s1 >= length - 0.01 and ss[ss.size() - 1] < length - 0.01:
		ss.append(length)
	var n := ss.size()
	if n < 2:
		return {}
	var ps := PackedVector2Array()
	var land := PackedFloat32Array()
	var flags := PackedInt32Array()
	var road: Array = []
	ps.resize(n)
	land.resize(n)
	flags.resize(n)
	road.resize(n)
	var asked := PackedByteArray()   # (the land and roads are asked after every other sample, and between where needed)
	asked.resize(n)
	var seen := _seen_of(net, str(r["id"]))
	_lock.lock()
	for i in n:
		ps[i] = _point_on(r, ss[i])
		flags[i] = _flags_at(r, ss[i])
		var had = seen.get(roundi(ss[i] * 4.0))
		if had != null:
			land[i] = float(had[0])
			road[i] = had[1]
			asked[i] = 2
	_lock.unlock()
	for i in n:
		if not asked[i] and (roundi(ss[i] / STEP) % 2 == 0 or i == 0 or i == n - 1):
			if not _ask(net, ps[i], i, land, road, memo):
				return {}
			asked[i] = 1
	for i in n:
		if asked[i]:
			continue
		var a := i - 1
		var b := i + 1
		# (near a road, or where the land between bends, it's asked after too)
		if not (road[a] as Array).is_empty() or not (road[b] as Array).is_empty() or absf(land[a] - land[b]) > 3.0:
			if not _ask(net, ps[i], i, land, road, memo):
				return {}
		else:
			land[i] = (land[a] + land[b]) * 0.5
			road[i] = []
	# (kept for the next block to ask, where the ground round the whole section is final)
	var box := Rect2(ps[0], Vector2.ZERO)
	for p in ps:
		box = box.expand(p)
	if net._final(box.get_center(), maxf(box.size.x, box.size.y) * 0.5 + SEEN_PAD):
		_lock.lock()
		for i in n:
			if asked[i] != 2:
				seen[roundi(ss[i] * 4.0)] = [land[i], road[i]]
		_lock.unlock()
	var y := _heights(net, r, ss, land, flags, road, memo)
	var cut := PackedByteArray()
	cut.resize(n)
	for i in n:
		var c := 0
		if flags[i] & TUNNEL:
			c = 1
		elif not (road[i] as Array).is_empty():
			var rd: Array = road[i]
			var clear := float(rd[2])
			if flags[i] & BRIDGE:
				c = 1 if y[i] < float(rd[4]) + RoadNet.HEADROOM + DECK_DEPTH - 0.3 and clear < RoadNet.VERGE + CLEAR else 0
			else:
				c = 1 if clear < RoadNet.VERGE + CLEAR else 0
		cut[i] = c
	return {"s": ss, "p": ps, "land": land, "y": y, "flags": flags, "cut": cut, "road": road}


## What's been found along run `id` on `net` (kept in _seen).
static func _seen_of(net: RoadNet, id: String) -> Dictionary:
	_lock.lock()
	var by_net: Dictionary = _seen.get(net.get_instance_id(), {})
	if by_net.is_empty():
		if _seen.size() > 3:
			_seen.clear()
		_seen[net.get_instance_id()] = by_net
	var got: Dictionary = by_net.get(id, {})
	if got.is_empty():
		by_net[id] = got
	_lock.unlock()
	return got


## Sample `i` at `p`: its land and the road near it into `land` and `road`; false where the land isn't there yet.
static func _ask(net: RoadNet, p: Vector2, i: int, land: PackedFloat32Array, road: Array, memo: Dictionary) -> bool:
	var bare := float(net.height.call(p.x, p.y))
	if is_nan(bare):
		return false
	land[i] = net.ground_at(p.x, p.y, bare, memo)
	road[i] = _road_at(net, p, memo)
	return true


## The road nearest `p` if one is within NEAR_TO of it: [edge, s, clearance from its carriageway's edge (m, < 0 on it;
## -1 in a junction), width, its height there (NAN unless `heights` or it's within its verge and CLEAR), lat]; [] for
## none. (A road's height is worked out only where it's wanted: it's most of the cost.)
static func _road_at(net: RoadNet, p: Vector2, memo: Dictionary, heights := false) -> Array:
	# (RoadNet.locate's choice, from the block's grid and lines kept in `memo`, and its junctions looked at only for a
	# road near enough to matter)
	var near := net._near_memo(p.x, p.y, memo)
	var cands: PackedInt32Array = near[0]
	var best := -1
	var best_key := INF
	var best_proj := []
	for c in cands.size():
		var ei := cands[c]
		var v := net._edge_memo(ei, memo)
		var pr := RoadNet._project_on(v[0], v[1], p, near[1][c])
		var off := float(pr[2]) - net.width_of(ei) * 0.5
		if off > RoadNet.REACH:
			continue
		var key := maxf(off, 0.0) * 1000.0 + float(pr[2])
		if key < best_key or (key == best_key and ei < best):
			best_key = key
			best = ei
			best_proj = pr
	if best < 0:
		return []
	var w := net.width_of(best)
	var clear := absf(float(best_proj[1])) - w * 0.5
	if clear > NEAR_TO:
		return []
	for n: int in [net.region.edge_a[best], net.region.edge_b[best]]:
		var j := net.junction_of(n, false)
		if j.is_empty() or j["kind"] == "end":
			continue
		if Geometry2D.is_point_in_polygon(p, j["outline"]) or Vector2(j["pos"].x, j["pos"].z).distance_to(p) <= RoadNet._inner(j):
			clear = -1.0
			break
	var y := NAN
	if heights or clear < RoadNet.VERGE + CLEAR:
		y = net.road_y(best, float(best_proj[0]))
	return [best, float(best_proj[0]), clear, w, y, float(best_proj[1])]


## The rail bed's height at each of a section's samples: the land smoothed (a railway climbs gently), never under the land
## (no cutting), on the land as it is near a road, straight across a bridge from the land at its ends (lifted to clear a
## road under it), and eased onto each bridge's and tunnel's ends.
static func _heights(net: RoadNet, r: Dictionary, ss: PackedFloat32Array, land: PackedFloat32Array, flags: PackedInt32Array,
		road: Array, memo: Dictionary) -> PackedFloat32Array:
	var n := ss.size()
	var kind := str(r["kind"])
	# Every bridge and tunnel whose deck (or its ease) reaches the samples: the same ones whichever block asks.
	var decks: Array = []   # [span, _deck's]
	for sp: Array in r["spans"]:
		if float(sp[1]) + EASE_MOST >= ss[0] and float(sp[0]) - EASE_MOST <= ss[n - 1]:
			decks.append([sp, _deck(net, r, sp, memo)])
	var base := land.duplicate()
	var pinned := PackedByteArray()
	pinned.resize(n)
	for i in n:
		if not flags[i] & (BRIDGE | TUNNEL):
			continue
		for dk: Array in decks:
			var sp: Array = dk[0]
			if ss[i] >= float(sp[0]) - 0.01 and ss[i] <= float(sp[1]) + 0.01:
				base[i] = _deck_y(dk[1], ss[i])
				pinned[i] = 1
				break
	var y := base
	if kind != "funicular":
		for _pass in PASSES:
			# (a running sum over the window)
			var sm := y.duplicate()
			var acc := 0.0
			var lo := 0
			var hi := -1
			for i in n:
				while hi < mini(i + SMOOTH, n - 1):
					hi += 1
					acc += y[hi]
				while lo < i - SMOOTH:
					acc -= y[lo]
					lo += 1
				if not pinned[i]:
					sm[i] = acc / (hi - lo + 1)
			y = sm
	# (eased onto the nearest bridge's deck or tunnel's mouth, over as far as a gentle grade takes to make it up: each end
	# as [s, its deck's height, how far])
	var ends := PackedVector3Array()
	for dk: Array in decks:
		var d: Array = dk[1]
		for e in 2:
			var at_s := float(d[e * 2])
			var at_end := _deck_y(d, at_s)
			ends.append(Vector3(at_s, at_end, clampf(absf(at_end - float(d[e * 2 + 1])) / EASE_GRADE, EASE, EASE_MOST)))
	for i in n:
		if pinned[i]:
			continue
		var h := maxf(y[i], land[i] - 0.15)
		for e in ends:
			var away := absf(ss[i] - e.x)
			if away < e.z:
				var t := 1.0 - away / e.z
				h = lerpf(h, e.y, t * t * (3.0 - 2.0 * t))
		var rd: Array = road[i]
		if not rd.is_empty():
			var t := 1.0 - smoothstep(NEAR_FROM, NEAR_TO, float(rd[2]))
			h = lerpf(h, land[i], t)
		y[i] = h
	if kind == "monorail":
		for i in n:
			y[i] += MONO_H
	return y


## Span `sp` of run `r`'s heights: [s0, y0, s1, y1, lifts], straight from the land at its ends (a tunnel's too), a bridge
## lifted over each road under it to the headroom (lifts: [[s, y needed], ...]).
static func _deck(net: RoadNet, r: Dictionary, sp: Array, memo: Dictionary) -> Array:
	var s0 := float(sp[0])
	var s1 := float(sp[1])
	var seen := _seen_of(net, str(r["id"]))
	var key := Vector2i(roundi(s0 * 4.0), roundi(s1 * 4.0))
	_lock.lock()
	var had = seen.get(key)
	_lock.unlock()
	if had != null:
		return had
	var out := _deck_of(net, r, s0, s1, int(sp[2]), memo)
	var a := _point_on(r, s0)
	if net._final((a + _point_on(r, s1)) * 0.5, a.distance_to(_point_on(r, s1)) * 0.5 + SEEN_PAD):
		_lock.lock()
		seen[key] = out
		_lock.unlock()
	return out


static func _deck_of(net: RoadNet, r: Dictionary, s0: float, s1: float, flag: int, memo: Dictionary) -> Array:
	var y0 := _end_y(net, r, s0, -1.0, memo)
	var y1 := _end_y(net, r, s1, 1.0, memo)
	var lifts: Array = []
	if flag == BRIDGE:
		var s := s0
		while s <= s1:
			var p := _point_on(r, s)
			var rd := _road_at(net, p, memo)
			if not rd.is_empty() and float(rd[2]) < RoadNet.VERGE + CLEAR:
				lifts.append([s, float(rd[4]) + RoadNet.HEADROOM + RoadNet.HEADROOM_PAD + DECK_DEPTH])
			s += STEP
	return [s0, y0, s1, y1, lifts]


static func _deck_y(d: Array, s: float) -> float:
	var t := clampf((s - float(d[0])) / maxf(float(d[2]) - float(d[0]), 0.01), 0.0, 1.0)
	var y := lerpf(float(d[1]), float(d[3]), t)
	for l: Array in d[4]:
		y = maxf(y, float(l[1]) - RAMP * maxf(absf(s - float(l[0])) - CROWN_FLAT, 0.0))
	return y


## The land's height at a span's end `s`, the mean of END_LOOK m of it on the far side from the span (`side` -1 before
## it, +1 past it): the same whichever block asks.
static func _end_y(net: RoadNet, r: Dictionary, s: float, side: float, memo: Dictionary) -> float:
	var sum := 0.0
	var w := 0
	var d := 0.0
	while d <= END_LOOK:
		var at := clampf(s + side * d, 0.0, float(r["len"]))
		var p := _point_on(r, at)
		var bare := float(net.height.call(p.x, p.y))
		if not is_nan(bare):
			sum += net.ground_at(p.x, p.y, bare, memo)
			w += 1
		d += STEP * 2.0
	return sum / w if w > 0 else 0.0


## The block's own stretch of a section: the pieces with either end in it (so two blocks overlap a piece at their seam).
static func _owned(sec: Dictionary, own: Rect2, i: int) -> bool:
	var ps: PackedVector2Array = sec["p"]
	return own.has_point(ps[i]) or (i + 1 < ps.size() and own.has_point(ps[i + 1]))


## Right of the line at sample `i` (x east, z south), level.
static func _right(sec: Dictionary, i: int) -> Vector2:
	var ps: PackedVector2Array = sec["p"]
	var a := ps[maxi(i - 1, 0)]
	var b := ps[mini(i + 1, ps.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


## The track along a section's own pieces: a piece of track a sample (its sleepers near, its plain bed far), the
## embankment's skirt down to the land each side (off a bridge), and the overhead line where it's electrified; a
## monorail's beam on its pillars.
static func _lay_track(multis: Dictionary, r: Dictionary, sec: Dictionary, own: Rect2, o: Vector2) -> void:
	if not r["track"]:
		return
	var ps: PackedVector2Array = sec["p"]
	var ys: PackedFloat32Array = sec["y"]
	var land: PackedFloat32Array = sec["land"]
	var cut: PackedByteArray = sec["cut"]
	var flags: PackedInt32Array = sec["flags"]
	var ss: PackedFloat32Array = sec["s"]
	var kind := str(r["kind"])
	var model := "beam" if kind == "monorail" else ("track_narrow" if float(GAUGES.get(kind, 1.435)) < 1.3 else "track")
	var kit: Dictionary = r["kit"]
	var wired := bool(kit.get("electrified", false)) or kind in ["light_rail", "tram"]
	for i in ps.size() - 1:
		if not _owned(sec, own, i) or cut[i] or cut[i + 1]:
			continue
		var a := Vector3(ps[i].x - o.x, ys[i], ps[i].y - o.y)
		var b := Vector3(ps[i + 1].x - o.x, ys[i + 1], ps[i + 1].y - o.y)
		var xf := _piece(a, b)
		var rgt := xf.basis.x
		_add(multis, model, xf)
		if model == "beam":
			if fmod(ss[i], PILLAR_GAP) < STEP and own.has_point(ps[i]) and (sec["road"][i] as Array).is_empty():
				var top := a.y - 1.4
				_add(multis, "pillar", Transform3D(Basis(Vector3.RIGHT, Vector3.UP * maxf(top - land[i] + BURY, 0.1), Vector3.BACK),
					Vector3(a.x, top, a.z)))
			continue
		_add(multis, "track_far", xf)
		if not ((flags[i] & BRIDGE) and (flags[i + 1] & BRIDGE)):
			var depth := maxf(maxf(a.y - land[i], b.y - land[i + 1]) - SHOULDER_DROP, 0.0) + BURY
			for sg: float in [-1.0, 1.0]:
				_add(multis, "skirt_l" if sg < 0.0 else "skirt_r", Transform3D(Basis(rgt * depth, Vector3.UP * depth, -(b - a)),
					a + rgt * (BALLAST_W + SHOULDER) * sg + Vector3.DOWN * SHOULDER_DROP))
		if wired:
			_add(multis, "wire", xf)
			var m0 := ceilf(ss[i] / MAST_GAP) * MAST_GAP
			if m0 < ss[i + 1] and own.has_point(ps[i]):
				var p := a.lerp(b, (m0 - ss[i]) / maxf(ss[i + 1] - ss[i], 0.001))
				# (the mast's arms reach back over the track, along its -x)
				_add(multis, "mast", Transform3D(Basis(rgt, Vector3.UP, rgt.cross(Vector3.UP)), p + rgt * (BALLAST_W + 0.9)))


## Bridges along a section: the deck a sample, piers down to the land where it's high enough (none in a road or its
## verge), stone arches between them on a viaduct, the abutments at its ends; and a tunnel's mouths.
static func _lay_spans(geo: Geo, multis: Dictionary, net: RoadNet, r: Dictionary, sec: Dictionary, own: Rect2, o: Vector2,
		memo: Dictionary) -> void:
	var ps: PackedVector2Array = sec["p"]
	var ys: PackedFloat32Array = sec["y"]
	var flags: PackedInt32Array = sec["flags"]
	var ss: PackedFloat32Array = sec["s"]
	var mono := str(r["kind"]) == "monorail"
	for i in ps.size() - 1:
		if mono or not _owned(sec, own, i) or not (flags[i] & BRIDGE) or not (flags[i + 1] & BRIDGE):
			continue
		var sp := _span_at(r, (ss[i] + ss[i + 1]) * 0.5)
		var style := str(sp[3]) if not sp.is_empty() and str(sp[3]) != "" else "concrete"
		_add(multis, "deck_" + style, _piece(Vector3(ps[i].x - o.x, ys[i], ps[i].y - o.y),
			Vector3(ps[i + 1].x - o.x, ys[i + 1], ps[i + 1].y - o.y)))
	# Piers and arches, at the same s whichever block lays them (from the span's start).
	for sp: Array in r["spans"]:
		var s0 := float(sp[0])
		var s1 := float(sp[1])
		if s1 < ss[0] or s0 > ss[ss.size() - 1]:
			continue
		if int(sp[2]) == TUNNEL:
			if r["track"]:
				for end: Array in [[s0, -1.0], [s1, 1.0]]:
					_portal(geo, r, sec, float(end[0]), float(end[1]), own, o)
			continue
		if mono:
			continue
		var style := str(sp[3]) if str(sp[3]) != "" else "concrete"
		var gap := float(PIER_GAP.get(style, 30.0))
		var count := maxi(roundi((s1 - s0) / gap), 1)
		var step := (s1 - s0) / count
		var piers: Array = []   # [s, top, bottom, thickness] or [] where none stands
		for j in count + 1:
			var s := s0 + j * step
			var p := _point_on(r, s)
			var y := _sec_y(sec, s)
			if is_nan(y):
				piers.append([])
				continue
			var bare := float(net.height.call(p.x, p.y))
			var g := net.ground_at(p.x, p.y, bare, memo) if not is_nan(bare) else y
			var rd := _road_at(net, p, memo)
			if y - DECK_DEPTH - g < PIER_FROM or (not rd.is_empty() and float(rd[2]) < RoadNet.VERGE + CLEAR + 1.5):
				piers.append([])
				continue
			# (an end's pier is the abutment, a little thicker)
			var thick := 3.0 if j == 0 or j == count else (2.4 if style == "stone" else 1.8)
			piers.append([s, y - DECK_DEPTH, g - BURY, thick])
		for j in piers.size():
			var pr: Array = piers[j]
			if pr.is_empty():
				continue
			var s := float(pr[0])
			var p := _point_on(r, s)
			if not own.has_point(p):
				continue
			var rr := _right_at(r, s)
			var r3 := Vector3(rr.x, 0.0, rr.y)
			var top := float(pr[1])
			_add(multis, "pier_" + style, Transform3D(Basis(r3, Vector3.UP * (top - float(pr[2])), r3.cross(Vector3.UP) * float(pr[3])),
				Vector3(p.x - o.x, top, p.y - o.y)))
			if style != "stone" or j + 1 >= piers.size() or (piers[j + 1] as Array).is_empty():
				continue
			var nx: Array = piers[j + 1]
			var s_in := s + float(pr[3]) * 0.5
			var s_out := float(nx[0]) - float(nx[3]) * 0.5
			var span := s_out - s_in
			if span < 2.0 or minf(top - float(pr[2]), float(nx[1]) - float(nx[2])) < span * 0.65 + BURY + 1.0:
				continue
			var pa := _point_on(r, s_in)
			var pb := _point_on(r, s_out)
			var flat := Vector3(pb.x - pa.x, 0.0, pb.y - pa.y)
			var ra := Vector3(-flat.z, 0.0, flat.x).normalized()
			var ya := _sec_y(sec, s_in) - DECK_DEPTH
			_add(multis, "arch_stone", Transform3D(Basis(ra, Vector3.UP * span, -flat), Vector3(pa.x - o.x, ya, pa.y - o.y)))


## A pier: a box from `top` (its middle at `at`) down to `bottom`, `half_w` across the line (along `right`) and `half_t`
## along it, a little wider at its foot.
static func _pier(geo: Geo, at: Vector3, bottom: float, right: Vector3, half_w: float, half_t: float, c: Color) -> void:
	var fwd := Vector3(-right.z, 0.0, right.x) * -1.0
	var spread := clampf((at.y - bottom) * 0.025, 0.0, 1.2)
	var corners := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
	for k in 4:
		var c0: Array = corners[k]
		var c1: Array = corners[(k + 1) % 4]
		var t0 := at + right * half_w * float(c0[0]) + fwd * half_t * float(c0[1])
		var t1 := at + right * half_w * float(c1[0]) + fwd * half_t * float(c1[1])
		var b0 := Vector3(at.x, bottom, at.z) + right * (half_w + spread) * float(c0[0]) + fwd * (half_t + spread) * float(c0[1])
		var b1 := Vector3(at.x, bottom, at.z) + right * (half_w + spread) * float(c1[0]) + fwd * (half_t + spread) * float(c1[1])
		geo.quad("matte", t0, t1, b1, b0, c)


static func _right_at(r: Dictionary, s: float) -> Vector2:
	var t := (_point_on(r, minf(s + 2.0, float(r["len"]))) - _point_on(r, maxf(s - 2.0, 0.0))).normalized()
	return Vector2(-t.y, t.x)


## The rail bed's height `s` m along a section's run (NAN outside it).
static func _sec_y(sec: Dictionary, s: float) -> float:
	var ss: PackedFloat32Array = sec["s"]
	if s < ss[0] - 0.01 or s > ss[ss.size() - 1] + 0.01:
		return NAN
	var k := clampi(ss.bsearch(s, true), 1, ss.size() - 1)
	var t := clampf((s - ss[k - 1]) / maxf(ss[k] - ss[k - 1], 0.001), 0.0, 1.0)
	return lerpf(sec["y"][k - 1], sec["y"][k], t)


## A tunnel's mouth at `s` along run `r`, facing out of it (`out` -1 back along the line, +1 on along it): a stone face
## round a dark arch.
static func _portal(geo: Geo, r: Dictionary, sec: Dictionary, s: float, out: float, own: Rect2, o: Vector2) -> void:
	var p := _point_on(r, s)
	if not own.has_point(p):
		return
	var y := _sec_y(sec, s)
	if is_nan(y):
		return
	var rr := _right_at(r, s)
	var r3 := Vector3(rr.x, 0.0, rr.y)
	var fwd := Vector3(-r3.z, 0.0, r3.x) * -1.0 * out   # (out of the tunnel)
	var at := Vector3(p.x - o.x, y, p.y - o.y)
	var w := 5.0
	var h := 7.5
	var bottom := y - 2.0
	# The face, with the dark mouth in front of it.
	geo.quad("matte", at - r3 * w + Vector3(0, bottom - y, 0), at + r3 * w + Vector3(0, bottom - y, 0),
		at + r3 * w + Vector3.UP * h, at - r3 * w + Vector3.UP * h, C_STONE, out > 0.0)
	var mouth := at + fwd * 0.15
	var hole_w := 2.6
	var hole_h := 5.2
	var steps := 6
	for k in steps:
		var a0 := PI * k / steps
		var a1 := PI * (k + 1) / steps
		var spring := hole_h - hole_w
		var q0 := mouth + r3 * cos(a0) * hole_w + Vector3.UP * (spring + sin(a0) * hole_w)
		var q1 := mouth + r3 * cos(a1) * hole_w + Vector3.UP * (spring + sin(a1) * hole_w)
		geo.tri("matte", mouth + Vector3.UP * spring, q0, q1, C_DARK, out < 0.0)
	geo.quad("matte", mouth - r3 * hole_w, mouth + r3 * hole_w, mouth + r3 * hole_w + Vector3.UP * (hole_h - hole_w),
		mouth - r3 * hole_w + Vector3.UP * (hole_h - hole_w), C_DARK, out > 0.0)


# ---------------------------------------------------------------------------- level crossings

## Where a run meets a road on the level in this block: {run, s (along the run), edge, road_s, at: Vector2 (the road's
## middle), road_y, width, along: Vector2 (the road's way), cross_angle}. A stretch the track stops for that crosses the
## road's middle is one.
static func _crossings(net: RoadNet, r: Dictionary, ri: int, sec: Dictionary, own: Rect2) -> Array:
	var out: Array = []
	var cut: PackedByteArray = sec["cut"]
	var flags: PackedInt32Array = sec["flags"]
	var road: Array = sec["road"]
	var i := 0
	var n := cut.size()
	while i < n:
		if not cut[i] or flags[i] & (BRIDGE | TUNNEL) or (road[i] as Array).is_empty():
			i += 1
			continue
		var j := i
		while j + 1 < n and cut[j + 1] and not (flags[j + 1] & (BRIDGE | TUNNEL)):
			j += 1
		# (its middle: where it crosses the road's middle line, the lat changing sign)
		var best := -1
		for k in range(i, j):
			var a: Array = road[k]
			var b: Array = road[k + 1]
			if a.is_empty() or b.is_empty() or int(a[0]) != int(b[0]):
				continue
			if signf(float(a[5])) != signf(float(b[5])):
				best = k
				break
		if best >= 0 and i > 0 and j < n - 1:
			var a: Array = road[best]
			var b: Array = road[best + 1]
			var t := absf(float(a[5])) / maxf(absf(float(a[5])) + absf(float(b[5])), 0.001)
			var s := lerpf(sec["s"][best], sec["s"][best + 1], t)
			var e := int(a[0])
			var rs := lerpf(float(a[1]), float(b[1]), t)
			var at := net.point_at(e, rs)
			var ry := lerpf(float(a[4]), float(b[4]), t)
			# (at grade: the line's own bed here is near the road's height, and the road isn't on a bridge)
			if own.has_point(at) and net.bridge_at(e, rs) <= 0.0 and absf(_sec_y(sec, s) - ry) < 3.0:
				var ahead := (net.point_at(e, minf(rs + 2.0, net.length_of(e))) - net.point_at(e, maxf(rs - 2.0, 0.0))).normalized()
				var rail := (_point_on(r, minf(s + 2.0, float(r["len"]))) - _point_on(r, maxf(s - 2.0, 0.0))).normalized()
				out.append({"runs": [ri], "s": [s], "edge": e, "road_s": rs, "at": at, "road_y": ry, "width": float(a[3]),
					"along": ahead, "sin": maxf(absf(ahead.cross(rail)), 0.3)})
		i = j + 1
	return out


## Crossings of the same road within 18 m of each other (a double track) are one, closed for a train on either line.
static func _merge_crossings(list: Array) -> Array:
	var out: Array = []
	for c: Dictionary in list:
		var into := -1
		for k in out.size():
			var d: Dictionary = out[k]
			if int(d["edge"]) == int(c["edge"]) and absf(float(d["road_s"]) - float(c["road_s"])) < 18.0:
				into = k
				break
		if into < 0:
			c["spread"] = 0.0
			out.append(c)
		else:
			var d: Dictionary = out[into]
			d["spread"] = maxf(float(d.get("spread", 0.0)), absf(float(d["road_s"]) - float(c["road_s"])))
			(d["runs"] as Array).append_array(c["runs"])
			(d["s"] as Array).append_array(c["s"])
	return out


## A level crossing's posts, lamps and signs beside the road (the barrier arms that move are rail_train.gd's): one each
## side of the road on each side of the line, past the verge. Returns what the trains' node needs: {runs, s, arms:
## [Transform3D: the arm's pivot, its +x across the road], length, lamps: [Transform3D]}.
static func _lay_crossing(geo: Geo, net: RoadNet, c: Dictionary, o: Vector2) -> Dictionary:
	var along: Vector2 = c["along"]
	var across := Vector2(-along.y, along.x)
	var w := float(c["width"])
	var out_m := w * 0.5 + RoadNet.VERGE + POST_OUT
	var back := TRACK_HALF / float(c["sin"]) + float(c.get("spread", 0.0)) * 0.5 + 1.5
	var arms: Array = []
	var lamps: Array = []
	var at: Vector2 = c["at"]
	for way: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var p: Vector2 = at + along * back * way + across * out_m * side
			# (never in another road's carriageway or verge)
			if SceneryStreamer.off_road(net, p) != p:
				continue
			var bare := float(net.height.call(p.x, p.y))
			if is_nan(bare):
				continue
			var y := net.ground_at(p.x, p.y, bare)
			var base := Vector3(p.x - o.x, y, p.y - o.y)
			var in3 := Vector3(-across.x * side, 0.0, -across.y * side)   # (towards the road's middle)
			_pier(geo, base + Vector3.UP * 1.2, y - 0.3, in3, 0.15, 0.15, C_WHITE)
			# The lamp post: two red lamps on a black board, a white cross above.
			var lp := base + Vector3(along.x, 0.0, along.y) * way * 0.8
			_pier(geo, lp + Vector3.UP * 3.0, y - 0.3, in3, 0.07, 0.07, C_POST)
			var face := Vector3(along.x, 0.0, along.y) * way   # (the lamps face the traffic coming)
			var rgt := face.cross(Vector3.UP).normalized()
			geo.quad("matte", lp + face * 0.1 + rgt * 0.55 + Vector3.UP * 1.9, lp + face * 0.1 - rgt * 0.55 + Vector3.UP * 1.9,
				lp + face * 0.1 - rgt * 0.55 + Vector3.UP * 2.5, lp + face * 0.1 + rgt * 0.55 + Vector3.UP * 2.5, C_DARK)
			for x: float in [-0.32, 0.32]:
				lamps.append(Transform3D(Basis(rgt, Vector3.UP, face), lp + face * 0.14 + rgt * x + Vector3.UP * 2.2))
			for d: float in [-1.0, 1.0]:
				var q := lp + face * 0.12 + Vector3.UP * 2.95
				var u := (rgt * d + Vector3.UP).normalized() * 0.55
				var v: Vector3 = face.cross(u).normalized() * 0.06
				geo.quad("matte", q - u - v, q - u + v, q + u + v, q + u - v, C_WHITE)
			var pivot := Transform3D(Basis(in3, Vector3.UP, in3.cross(Vector3.UP)), base + Vector3.UP * ARM_H)
			arms.append(pivot)
	return {"runs": c["runs"], "s": c["s"], "arms": arms, "length": out_m - 0.2, "lamps": lamps}


# ---------------------------------------------------------------------------- stations

## A station or halt at map point `row` beside the line nearest it: a platform along the track (its edge PLATFORM_EDGE
## from the line's middle, on the side the point is), a canopy and lamps on a station's, a name board at each end.
## Returns its boards for the dress ({text, at: [Transform3D]}) or {} where no line is near.
static func _lay_station(geo: Geo, multis: Dictionary, net: RoadNet, runs: Dictionary, sections: Dictionary, row: Array, o: Vector2) -> Dictionary:
	var p := Vector2(float(row[1]), float(row[2]))
	var best := -1
	var best_d := STATION_NEAR
	var best_s := 0.0
	for ri: int in sections:
		var r: Dictionary = runs["runs"][ri]
		if not r["track"]:
			continue
		var sec: Dictionary = sections[ri]
		var ps: PackedVector2Array = sec["p"]
		for i in ps.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, ps[i], ps[i + 1])
			var d := q.distance_to(p)
			if d < best_d:
				best_d = d
				best = ri
				best_s = lerpf(sec["s"][i], sec["s"][i + 1], q.distance_to(ps[i]) / maxf(ps[i].distance_to(ps[i + 1]), 0.001))
	if best < 0:
		return {}
	var r: Dictionary = runs["runs"][best]
	var sec: Dictionary = sections[best]
	var size: Array = PLATFORM[row[0]]
	var half_l := float(size[0]) * 0.5
	var width := float(size[1])
	var c := _point_on(r, best_s)
	var rr := _right_at(r, best_s)
	var side := 1.0 if rr.dot(p - c) >= 0.0 else -1.0
	var ss: PackedFloat32Array = sec["s"]
	var from := maxf(best_s - half_l, ss[0])
	var to := minf(best_s + half_l, ss[ss.size() - 1])
	var station: bool = row[0] == "railway_station"
	var prev: Array = []   # [the platform's edge at its top, how deep its faces go] at the sample before
	var s := from
	while s <= to + 0.01:
		var q := _point_on(r, s)
		var qr := _right_at(r, s) * side
		var y := _sec_y(sec, s)
		var edge := q + qr * PLATFORM_EDGE
		var back := q + qr * (PLATFORM_EDGE + width)
		var ok := not is_nan(y) and not (_flags_at(r, s) & (BRIDGE | TUNNEL)) \
			and SceneryStreamer.off_road(net, edge) == edge and SceneryStreamer.off_road(net, back) == back
		if not ok:
			prev = []
			s += STEP
			continue
		var top := y + RAIL_TOP + PLATFORM_H
		var e3 := Vector3(edge.x - o.x, top, edge.y - o.y)
		var bare := float(net.height.call(back.x, back.y))
		var low := minf(y, net.ground_at(back.x, back.y, bare) if not is_nan(bare) else y) - BURY
		var q3 := Vector3(qr.x, 0.0, qr.y)
		if not prev.is_empty():
			var pe: Vector3 = prev[0]
			var along := e3 - pe
			var out := Vector3(-along.z, 0.0, along.x).normalized() * side   # (from its edge to its back)
			_add(multis, "platform", Transform3D(Basis(out * width, Vector3.UP * maxf(float(prev[1]), top - low), -along), pe))
			if station and absf(s - best_s) <= 22.0:
				_add(multis, "canopy", Transform3D(Basis(out * width, Vector3.UP, -along), pe))
		prev = [e3, top - low]
		# Lamps along its back, a canopy's posts down its middle.
		if fmod(s - from, 12.0) < STEP * 0.5:
			_add(multis, "lamp_post", Transform3D(Basis(-q3, Vector3.UP, -q3.cross(Vector3.UP)), e3 + q3 * (width - 0.3)))
		if station and absf(s - best_s) <= 20.0 and fmod(s - from, 8.0) < STEP * 0.5:
			_add(multis, "canopy_post", Transform3D(Basis.IDENTITY, e3 + q3 * (width * 0.55)))
		s += STEP
	var kit: Dictionary = r["kit"]
	# Its name boards, at either end of the canopy.
	var title := str(row[6])
	if title == "":
		return {}
	var boards: Array = []
	for at_s in [best_s - 26.0, best_s + 26.0]:
		var bs := clampf(at_s, from, to)
		var q := _point_on(r, bs)
		var qr := _right_at(r, bs) * side
		var y := _sec_y(sec, bs)
		if is_nan(y):
			continue
		var top := y + RAIL_TOP + PLATFORM_H
		var spot := q + qr * (PLATFORM_EDGE + width - 0.5)
		if SceneryStreamer.off_road(net, spot) != spot:
			continue
		var s3 := Vector3(spot.x - o.x, top, spot.y - o.y)
		var q3 := Vector3(qr.x, 0.0, qr.y)
		var along := q3.cross(Vector3.UP).normalized()
		var board_c := Color.from_string(str(kit.get("board", "#1d2f5a")), Color(0.11, 0.18, 0.35))
		for d: float in [-1.2, 1.2]:
			_pier(geo, s3 + along * d + Vector3.UP * 2.6, top, q3, 0.05, 0.05, C_POST)
		geo.box("matte", s3 + Vector3.UP * 2.3, Vector3(0.0, 0.0, 0.0), board_c, along * 1.6, Vector3.UP * 0.35, q3 * 0.04)
		# (the words face the track, and the other way too: a Label3D reads from its +z)
		for f: float in [-1.0, 1.0]:
			var z: Vector3 = q3 * f
			boards.append(Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), s3 + Vector3.UP * 2.3 + z * 0.05))
	return {"text": title, "at": boards, "colour": str(kit.get("board_text", "#ffffff"))}


# ---------------------------------------------------------------------------- the trains' share of a block

## What rail_train.gd needs of a run in this block: its samples (s, and the rail top in the block's frame, tunnels
## hidden), the stretches of s this block draws a train's cars on, and the run's timetable and stock.
static func _portion(ri: int, r: Dictionary, sec: Dictionary, own: Rect2, o: Vector2) -> Dictionary:
	var ps: PackedVector2Array = sec["p"]
	var pos := PackedVector3Array()
	pos.resize(ps.size())
	var hide := PackedByteArray()
	hide.resize(ps.size())
	var mine: Array = []
	var start := -1.0
	for i in ps.size():
		pos[i] = Vector3(ps[i].x - o.x, float(sec["y"][i]) + RAIL_TOP, ps[i].y - o.y)
		hide[i] = 1 if (sec["flags"][i] & TUNNEL) else 0
		var inside := own.has_point(ps[i])
		if inside and start < 0.0:
			start = sec["s"][i] if i == 0 else (sec["s"][i - 1] + sec["s"][i]) * 0.5
		elif not inside and start >= 0.0:
			mine.append([start, (sec["s"][i - 1] + sec["s"][i]) * 0.5])
			start = -1.0
	if start >= 0.0:
		mine.append([start, sec["s"][ps.size() - 1] + 0.01])
	return {"run": ri, "len": float(r["len"]), "s": sec["s"], "pos": pos, "hide": hide, "mine": mine,
		"timetable": r["timetable"], "kind": str(r["kind"]), "stock": r["kit"]}


# ---------------------------------------------------------------------------- meshes

## The instanced pieces' meshes (the streamer's hook; rail.gd draws its own pieces in dress).
static func mesh(model: String) -> Mesh:
	return Models.mesh(model)


## Puts a block's railway into the world (the streamer's hook, on the main thread, after its instanced parts): its track,
## bridges, crossings and stations as one mesh of a surface each, its stations' names, and its trains and barriers
## (rail_train.gd).
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	var d: Dictionary = data
	var reach := float(d.get("reach", REACH))
	var mesh := Geo.mesh_of(d.get("meshes", {}))
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.name = "Railway"
		mi.mesh = mesh
		AdventureChunk._range(mi, reach)
		node.add_child(mi)
	var multis: Dictionary = d.get("multis", {})
	for model: String in multis:
		var list: Array = multis[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.mesh(model)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model
		mmi.multimesh = mm
		var rg: Array = Models.RANGES.get(model, [0.0, reach])
		AdventureChunk._range(mmi, float(rg[1]))
		if float(rg[0]) > 0.0:
			mmi.visibility_range_begin = float(rg[0])
			mmi.visibility_range_begin_margin = 30.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if model.begins_with("deck") or model.begins_with("pier") \
			or model.begins_with("arch") or model in ["platform", "canopy", "beam", "pillar"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	for b: Dictionary in d.get("boards", []):
		for xf: Transform3D in b["at"]:
			var l := Label3D.new()
			l.text = str(b["text"])
			l.pixel_size = 0.004
			l.font_size = 56
			l.outline_size = 0
			l.modulate = Color.from_string(str(b.get("colour", "#ffffff")), Color.WHITE)
			l.double_sided = false
			l.transform = xf
			l.width = 780.0
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			AdventureChunk._range(l, 250.0)
			node.add_child(l)
	if not (d.get("portions", []) as Array).is_empty() or not (d.get("gates", []) as Array).is_empty():
		var trains: Node3D = RailTrains.new()
		trains.name = "Trains"
		trains.setup(d.get("portions", []), d.get("gates", []), reach)
		node.add_child(trains)

