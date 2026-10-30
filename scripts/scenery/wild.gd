class_name Wild
extends RefCounted
## Mountains and wild ground (Ride Anywhere v2, phase D round 2, D4: docs/scenery.md): a named pass's summit sign where
## a road crosses its saddle (the name and height from the map, in its country's style: a French col sign, an Alpine
## Passhöhe board, a Scottish cairn, a Japanese tōge marker, a plain board anywhere else), with a cairn, a lay-by and a
## panorama board; the summit cross, trig pillar or cairn on a peak with its name; cliffs as rock faces standing along
## their line; scree, glaciers, dunes with marram grass, shingle and volcanic ash laid over the land; crater rims, rocky
## ridges, cave mouths with their sign, and reefs showing at low water. (The snow above the place's snow line, by
## height and its climate, is the land's own colour: AdventureChunk._land_color, RealRidges.)
##
## The streamer (SceneryStreamer) hands lay_out a block's rows whose kit names this script and draws the instanced
## pieces it gives back, one MultiMesh a model. What lies over the land (ice, scree, sand, shingle, ash, a
## lay-by's gravel) is a mesh a block for each skin, made by dress on the main thread from what lay_out worked out on
## its worker: a sheet on the land's own 8 m grid (RealLand's near cells, its diagonals the same way), its edge ragged
## by the skin's shader, drawn a little towards the camera so the land's coarser levels far off don't show through.
##
## Simon's first rule, as here: nothing lies on a road, its verge or a junction (a sheet's cell stays out of reach of
## a road's verge, a piece's footprint is checked against the roads), the land's heights are only read, never changed
## (a cliff stands on the land as it is, a dune or a glacier swells only above it, away from the roads), and nothing
## has collision. The second: every kind wherever the map has it, its look by region (and by country where a kit row
## says so) from the kit library, with a default for everywhere; nothing is keyed to a place.

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 1
## A cliff's face in pieces this long along its line (m), each the block's whose middle it is in.
const STEP := 8.0
## How far past a road's verge a piece's footprint must be (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## A road within this of a saddle (m) crosses it: the pass is dressed where the road is highest within PASS_ALONG of
## the point nearest the saddle.
const PASS_REACH := 220.0
const PASS_ALONG := 160.0
## An unnamed saddle this near a named one (m) is the same pass: it gets no sign of its own.
const SAME_PASS := 1200.0
## A pass's lay-by: this long (m), from just past the verge out this far.
const LAYBY_LONG := 30.0
const LAYBY_OUT := 6.0
## A cliff's face: at least this high (m), at most this (the land's smoothed heights show only some of it), and as
## thick into the high ground as this share of its height (between the two).
const CLIFF_LEAST := 3.0
const CLIFF_MOST := 140.0
const CLIFF_THICK := Vector2(3.0, 12.0)
## The land's near grid (RealLand: 8 m cells over a 512 m block), the sheets' grid.
const GRID := 8.0
const CELLS := 64
## A sheet's cell stays this far past a road's verge (m, at each corner), times its size in grid cells: far enough
## that no road can pass between its corners.
const SHEET_CLEAR := 6.0
## The big sheets' cells are this many of the grid's a side (16 m: a glacier or a field of dunes needs no finer, and a
## block of it is a quarter the work); the rest the grid's own.
const STRIDES := {"ice": 2, "scree": 2, "sand": 2}
## A dune or glacier swells only this far past a road's verge (m), eased in over SWELL_EASE.
const SWELL_FROM := 12.0
const SWELL_EASE := 16.0
## The sea's level (m: heights are above it).
const SEA := 0.0
## At most this many boulders, tufts and reef heads a block.
const BOULDERS_MOST := 300
const TUFTS_MOST := 500
const HEADS_MOST := 400
## Names and heights are drawn within this (m).
const LABEL_REACH := 260.0
## Countries whose signs give heights in feet.
const FEET := ["US", "LR", "MM"]
## A point of a kind that's an area elsewhere (a glacier, a dune...) is a patch this big round it (m).
const PATCH := {"glacier": 120.0, "scree": 30.0, "dune": 45.0, "shingle": 25.0, "crater": 40.0, "volcano": 140.0}

## The stones and finishes the pieces come in (vertex colours).
const STONES := {
	"granite": Color(0.5, 0.48, 0.47), "gritstone": Color(0.36, 0.33, 0.29), "limestone": Color(0.74, 0.72, 0.66),
	"sandstone": Color(0.6, 0.47, 0.34), "slate": Color(0.3, 0.31, 0.33), "basalt": Color(0.2, 0.2, 0.21),
	"schist": Color(0.42, 0.42, 0.38), "chalk": Color(0.88, 0.87, 0.82), "laterite": Color(0.6, 0.36, 0.24),
	"redrock": Color(0.62, 0.32, 0.2), "tuff": Color(0.55, 0.5, 0.42), "rock": Color(0.45, 0.44, 0.42),
	"reef": Color(0.33, 0.3, 0.24), "coral": Color(0.62, 0.55, 0.45),
	"timber": Color(0.33, 0.22, 0.13), "steel": Color(0.45, 0.47, 0.5), "white": Color(0.93, 0.93, 0.9),
	"black": Color(0.06, 0.06, 0.07), "brown": Color(0.36, 0.2, 0.1), "green": Color(0.05, 0.33, 0.18),
	"yellow": Color(0.95, 0.75, 0.1), "marram": Color(0.66, 0.66, 0.42), "straw": Color(0.74, 0.66, 0.42)}
## The skins laid over the land: two colours the grain mixes and the shader's pattern (0 plain, 1 ice's crevasses, 2
## stones, 3 ripples), how fine its grain is (a metre), how rough, and how far it's drawn (m).
const SKINS := {
	"ice": {"a": Color(0.8, 0.9, 0.97), "b": Color(0.52, 0.7, 0.84), "pattern": 1, "grain": 0.05, "rough": 0.3, "reach": 4000.0},
	"scree": {"a": Color(0.56, 0.54, 0.51), "b": Color(0.36, 0.35, 0.33), "pattern": 2, "grain": 1.1, "rough": 0.95, "reach": 3000.0},
	"sand": {"a": Color(0.87, 0.78, 0.58), "b": Color(0.76, 0.65, 0.46), "pattern": 3, "grain": 0.25, "rough": 0.9, "reach": 3000.0},
	"shingle": {"a": Color(0.62, 0.59, 0.54), "b": Color(0.43, 0.41, 0.37), "pattern": 2, "grain": 2.6, "rough": 0.8, "reach": 2500.0},
	"ash": {"a": Color(0.27, 0.25, 0.24), "b": Color(0.15, 0.14, 0.14), "pattern": 2, "grain": 0.7, "rough": 0.95, "reach": 3000.0},
	"gravel": {"a": Color(0.55, 0.52, 0.48), "b": Color(0.4, 0.38, 0.35), "pattern": 2, "grain": 3.0, "rough": 0.95, "reach": 900.0}}
## The sands a dune can be (a kit's "sand"): its two colours.
const SANDS := {"pale": [Color(0.87, 0.78, 0.58), Color(0.76, 0.65, 0.46)], "gold": [Color(0.86, 0.68, 0.42), Color(0.74, 0.55, 0.32)],
	"red": [Color(0.8, 0.5, 0.3), Color(0.66, 0.38, 0.22)], "white": [Color(0.94, 0.92, 0.86), Color(0.84, 0.82, 0.75)],
	"black": [Color(0.18, 0.17, 0.17), Color(0.1, 0.1, 0.1)]}
## A pass sign's styles: its board's size (m), how high its middle is, its colours (board, edge, words) and its posts.
const SIGNS := {
	"col": {"size": Vector2(2.3, 1.05), "mid": 2.2, "board": "white", "edge": "black", "words": Color(0.05, 0.05, 0.05), "posts": "steel", "height": "Altitude %d m"},
	"passhoehe": {"size": Vector2(2.2, 0.95), "mid": 2.0, "board": "brown", "edge": "white", "words": Color(0.97, 0.97, 0.95), "posts": "timber", "height": "%d m ü. M."},
	"passo": {"size": Vector2(2.3, 1.0), "mid": 2.2, "board": "brown", "edge": "white", "words": Color(0.97, 0.97, 0.95), "posts": "steel", "height": "%d m s.l.m."},
	"cairn": {"size": Vector2(0.75, 0.42), "mid": 1.3, "board": "slate", "edge": "slate", "words": Color(0.92, 0.9, 0.84), "posts": "", "height": "%d m"},
	"toge": {"size": Vector2(0.62, 1.5), "mid": 1.45, "board": "timber", "edge": "timber", "words": Color(0.06, 0.05, 0.04), "posts": "timber", "height": "%d m"},
	"board": {"size": Vector2(2.6, 1.15), "mid": 2.3, "board": "green", "edge": "white", "words": Color(0.97, 0.97, 0.95), "posts": "steel", "height": "Elevation %d m"}}
## The summit marks a peak can have (a kit's "summit").
const SUMMITS := ["cross", "trig", "cairn", "post", "none"]

static var _meshes := {}
static var _lock := Mutex.new()
static var _shader: Shader
static var _skin_mats := {}
static var _regions := {}   # RealRegion's instance id -> {"named": PackedVector2Array}


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of this script's rows (SceneryStreamer's: {"points": [[row, kit], ...], "lines": ...,
## "areas": ...}, in the region frame): {"items": {model: [Transform3D in the block's frame]}, "dress": {"sheets":
## {skin: mesh arrays}, "labels": [...]}}. Safe on a worker.
static func lay_out(n: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := _Block.new(n, key)
	var info := _region_info(n.region)
	for pair: Array in rows.get("points", []):
		var row: Array = pair[0]
		var p := Vector2(float(row[1]), float(row[2]))
		if not b.mine(p):
			continue
		var k := _local_kit(n, pair[1], p)
		var id := str(row[7])
		var name := str(row[6]) if row[6] != null else ""
		match str(row[0]):
			"saddle": _pass(b, p, row[4], name, k, id, info)
			"peak": _peak(b, p, name, k, id)
			"cave_entrance": _cave(b, p, name, k, id)
			"volcano": _crater(b, _ring(p, float(k.get("crater_r", PATCH["volcano"])), 24), k, id, true)
			"crater": _crater(b, _ring(p, float(k.get("crater_r", PATCH["crater"])), 16), k, id, false)
			"cliff": _cliff_at(b, p, k, id)
			"ridge": _outcrops(b, PackedVector2Array([p + Vector2(-30, 0), p + Vector2(30, 0)]), k, id)
			"caldera_rim": _rim(b, PackedVector2Array([p + Vector2(-40, 0), p + Vector2(40, 0)]), k, id)
			"glacier", "scree", "dune", "shingle":
				_area(b, str(row[0]), _ring(p, float(PATCH[str(row[0])]), 12), k, id)
			"reef": _reef(b, _ring(p, 30.0, 10), k, id)
	for pair: Array in rows.get("lines", []):
		var row: Array = pair[0]
		var line: PackedVector2Array = row[1]
		if line.size() < 2:
			continue
		var k := _local_kit(n, pair[1], line[0])
		var id := str(row[6])
		match str(row[0]):
			"cliff": _cliff(b, line, row[2], k, id)
			"ridge": _outcrops(b, line, k, id)
			"caldera_rim": _rim(b, line, k, id)
			"crater": _rim(b, line, k, id)
			"reef": _reef(b, _band(line, 15.0), k, id)
			"shingle", "scree", "dune": _area(b, str(row[0]), _band(line, 12.0), k, id)
	for pair: Array in rows.get("areas", []):
		var row: Array = pair[0]
		var ring: PackedVector2Array = row[1]
		if ring.size() < 3:
			continue
		var k := _local_kit(n, pair[1], ring[0])
		var id := str(row[5])
		match str(row[0]):
			"glacier", "scree", "dune", "shingle": _area(b, str(row[0]), ring, k, id)
			"reef": _reef(b, ring, k, id)
			"crater", "volcano": _crater(b, ring, k, id, str(row[0]) == "volcano")
			"caldera_rim": _rim(b, _closed(ring), k, id)
			"cliff": _cliff(b, _closed(ring), row[2], k, id)
			"ridge": _outcrops(b, _closed(ring), k, id)
			"saddle", "peak", "cave_entrance":
				var c := _centre(ring)
				if b.mine(c):
					match str(row[0]):
						"saddle": _pass(b, c, row[3], str(row[4]) if row[4] != null else "", k, id, info)
						"peak": _peak(b, c, str(row[4]) if row[4] != null else "", k, id)
						"cave_entrance": _cave(b, c, str(row[4]) if row[4] != null else "", k, id)
	return {"items": b.items, "dress": {"sheets": b.sheet_arrays(), "labels": b.labels}, "skipped": b.skipped}


## What isn't instanced in a block laid out (lay_out's "dress"): the sheets over the land and the words on the signs.
## Main thread, once the block is in the world.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	var sheets: Dictionary = data.get("sheets", {})
	for skin: String in sheets:
		var arrays: Array = sheets[skin]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, skin_material(skin))
		var mi := MeshInstance3D.new()
		mi.name = "Wild_" + skin.replace(":", "_")
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = float(SKINS[skin.get_slice(":", 0)]["reach"]) * scale
		mi.visibility_range_end_margin = 40.0
		node.add_child(mi)
	for l: Dictionary in data.get("labels", []):
		var label := Label3D.new()
		label.text = str(l["text"])
		label.font_size = 48
		label.pixel_size = float(l["pixel"])
		label.modulate = l["col"]
		label.outline_size = 0
		label.double_sided = false
		label.transform = l["xf"]
		label.visibility_range_end = LABEL_REACH * scale
		node.add_child(label)


## A block's laying out: where it is, the roads, the land's grid and the sheets on it, what it has made so far.
class _Block:
	var n: RoadNet
	var key: Vector2i
	var corner: Vector2
	var box: Rect2
	var items := {}
	var labels := []
	var skipped := 0
	var memo := {}
	var grids := {}     # Vector2i block -> _Grid
	var free := {}      # skin -> [verts, normals, colours, uvs, indices]: sheets not on the grid (a lay-by)
	var counts := {"boulders": 0, "tufts": 0, "heads": 0}

	func _init(net: RoadNet, k: Vector2i) -> void:
		n = net
		key = k
		corner = Vector2(k) * RoadBlock.SIZE
		box = Rect2(corner, Vector2.ONE * RoadBlock.SIZE)

	## Whether region-frame `p` is this block's (each piece is the block's its middle is in).
	func mine(p: Vector2) -> bool:
		return box.has_point(p)

	## Adds an instance of `model` at `xf` (block frame).
	func put(model: String, xf: Transform3D) -> void:
		if not items.has(model):
			items[model] = []
		(items[model] as Array).append(xf)

	## The bare land at region-frame `p` (NAN beyond the land held).
	func bare(p: Vector2) -> float:
		return float(n.height.call(p.x, p.y))

	## The land as drawn at `p`, the roads' banks cut in where a road's bank can reach (`past`: gap's answer there,
	## if known).
	func ground(p: Vector2, past := NAN) -> float:
		var h := bare(p)
		if is_nan(h):
			return h
		if is_nan(past):
			past = gap(p)
		if past >= BANKS:
			return h
		return n.ground_at(p.x, p.y, h, memo)

	## How far `p` is past the verge of the nearest road (m: negative on one; FAR where none is filed near it), from
	## the roads' lines and the net's own filing of them; a junction counts as a disc round its node.
	func gap(p: Vector2) -> float:
		var bk := RoadBlock.key_of(p.x, p.y)
		var any = _roads.get(bk)
		if any == null:
			any = not n.edges_in(bk).is_empty()
			_roads[bk] = any
		if not any:
			return FAR
		var near: Array = n._near_at(p.x, p.y)
		var cands: PackedInt32Array = near[0]
		var best := FAR
		for c in cands.size():
			var e := cands[c]
			var line := n.line_of(e)
			var half := n.width_of(e) * 0.5 + RoadNet.VERGE
			var segs: PackedInt32Array = near[1][c]
			for q in segs.size():
				var k := segs[q]
				var d := Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k]).distance_to(p) - half
				if d < best:
					best = d
			for nd: int in [n.region.edge_a[e], n.region.edge_b[e]]:
				if n.region.adjacent[nd].size() >= 3:
					best = minf(best, n.region.node_pos[nd].distance_to(p) - _mouth(nd))
		return best

	## Past where the net files a road near (m), as far as gap can tell.
	const FAR := 48.0
	## Past a verge further than this (m) the land is taken as bare: a road's bank or cutting reaches further only
	## where it's a big one (RoadNet.BANK_MAX), and RoadNet.ground_at is the costly part of a sheet.
	const BANKS := 20.0
	var _mouths := {}
	var _roads := {}   # Vector2i block -> whether any road is filed in it

	func _mouth(nd: int) -> float:
		var have = _mouths.get(nd)
		if have != null:
			return have
		var widest := 0.0
		for e in n.region.adjacent[nd]:
			widest = maxf(widest, n.width_of(e))
		var r := widest * 0.5 + RoadNet.VERGE + RoadNet.FILLET + 6.0
		_mouths[nd] = r
		return r

	## Whether a footprint round `p` of radius `r` (m) is clear of every road (past its verge and CLEAR more).
	func clear(p: Vector2, r := 0.0) -> bool:
		return gap(p) > CLEAR + r

	## Region-frame (x, y, z) into the block's frame.
	func local(p: Vector2, y: float) -> Vector3:
		return Vector3(p.x - corner.x, y, p.y - corner.y)

	## The block's grid.
	func grid() -> _Grid:
		var g = grids.get(key)
		if g == null:
			g = _Grid.new(self, key)
			grids[key] = g
		return g

	## Every sheet as mesh arrays: {skin: arrays}.
	func sheet_arrays() -> Dictionary:
		var built := {}   # skin -> [verts, normals, colours, uvs, indices]
		for gk: Vector2i in grids:
			(grids[gk] as _Grid).build(built)
		for skin: String in free:
			if not built.has(skin):
				built[skin] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedInt32Array()]
			var into: Array = built[skin]
			var from: Array = free[skin]
			var base: int = (into[0] as PackedVector3Array).size()
			into[0].append_array(from[0])
			into[1].append_array(from[1])
			into[2].append_array(from[2])
			into[3].append_array(from[3])
			for i: int in from[4]:
				into[4].append(base + i)
		var out := {}
		for skin: String in built:
			var a: Array = built[skin]
			if (a[4] as PackedInt32Array).is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = a[0]
			arrays[Mesh.ARRAY_NORMAL] = a[1]
			arrays[Mesh.ARRAY_COLOR] = a[2]
			arrays[Mesh.ARRAY_TEX_UV] = a[3]
			arrays[Mesh.ARRAY_INDEX] = a[4]
			out[skin] = arrays
		return out


## The land's grid over one block (RealLand's near cells: GRID m, CELLS a side), its heights and the roads' reach worked
## out only where a sheet needs them, and each skin's share at every corner (0 to 1).
class _Grid:
	var b: _Block
	var key: Vector2i
	var origin: Vector2
	var h := PackedFloat32Array()      # the land, NAN till asked
	var gaps := PackedFloat32Array()   # past the roads' verges, NAN till asked
	var skins := {}                    # skin -> PackedFloat32Array share
	var swell := {}                    # skin -> m the sheet swells above the land at its middle (dunes, glaciers)
	var smooths := {}                  # skin -> PackedFloat32Array: inner's
	const N := CELLS + 1

	func _init(block: _Block, k: Vector2i) -> void:
		b = block
		key = k
		origin = Vector2(k) * RoadBlock.SIZE
		h.resize(N * N)
		h.fill(NAN)
		gaps.resize(N * N)
		gaps.fill(NAN)

	func at(i: int, j: int) -> Vector2:
		return origin + Vector2(i, j) * GRID

	func height(i: int, j: int) -> float:
		var g := j * N + i
		if is_nan(h[g]):
			h[g] = b.ground(at(i, j), gap(i, j))
		return h[g]

	func gap(i: int, j: int) -> float:
		var g := j * N + i
		if is_nan(gaps[g]):
			gaps[g] = b.gap(at(i, j))
		return gaps[g]

	func share(skin: String) -> PackedFloat32Array:
		if not skins.has(skin):
			var s := PackedFloat32Array()
			s.resize(N * N)
			skins[skin] = s
		return skins[skin]

	## Sets skin `skin` to 1 at the corners inside `ring` (region frame); returns how many. Each of the ring's sides
	## is looked at once, for the grid's rows it crosses.
	func fill(skin: String, ring: PackedVector2Array) -> int:
		var box := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			box = box.expand(p)
		if not box.intersects(Rect2(origin, Vector2.ONE * CELLS * GRID), true):
			return 0
		var rows := {}   # j -> PackedFloat32Array of x where the ring crosses row j
		var count := 0
		for i in ring.size():
			var a := ring[i]
			var c := ring[(i + 1) % ring.size()]
			if a.y == c.y:
				continue
			# (the rows z = origin.y + j * GRID with a.y <= z < c.y or the other way)
			var lo := minf(a.y, c.y)
			var hi := maxf(a.y, c.y)
			var j0 := maxi(ceili((lo - origin.y) / GRID), 0)
			var j1 := mini(ceili((hi - origin.y) / GRID) - 1, N - 1)
			for j in range(j0, j1 + 1):
				var z := origin.y + j * GRID
				if z < lo or z >= hi:
					continue
				var xs: PackedFloat32Array = rows.get(j, PackedFloat32Array())
				xs.append(a.x + (z - a.y) / (c.y - a.y) * (c.x - a.x))
				rows[j] = xs
		var s := share(skin)
		for j: int in rows:
			var xs: PackedFloat32Array = rows[j]
			xs.sort()
			for q in range(0, xs.size() - 1, 2):
				var i0 := maxi(ceili((xs[q] - origin.x) / GRID), 0)
				var i1 := mini(floori((xs[q + 1] - origin.x) / GRID), N - 1)
				for i in range(i0, i1 + 1):
					if s[j * N + i] < 1.0:
						s[j * N + i] = 1.0
						count += 1
		skins[skin] = s
		return count

	## The sheets of this grid into `built` ({skin: [verts, normals, colours, uvs, indices]}): the cells (of the skin's
	## stride) with some of a skin at a corner, every corner's land known and clear of the roads.
	func build(built: Dictionary) -> void:
		for skin: String in skins:
			var s: PackedFloat32Array = skins[skin]
			var st := stride(skin)
			var lift := float(swell.get(skin, 0.0))
			var smooth := inner(skin) if lift > 0.0 else PackedFloat32Array()
			if not built.has(skin):
				built[skin] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedInt32Array()]
			var into: Array = built[skin]
			var index := {}   # grid corner -> vertex
			var need := SHEET_CLEAR * st
			for j in range(0, CELLS, st):
				for i in range(0, CELLS, st):
					var c := [j * N + i, j * N + i + st, (j + st) * N + i + st, (j + st) * N + i]
					if s[c[0]] <= 0.0 and s[c[1]] <= 0.0 and s[c[2]] <= 0.0 and s[c[3]] <= 0.0:
						continue
					var ok := true
					for q: int in c:
						var ci: int = q % N
						var cj: int = q / N
						if gap(ci, cj) < need or is_nan(height(ci, cj)):
							ok = false
							break
					if not ok:
						continue
					var v := []
					for q: int in c:
						if not index.has(q):
							index[q] = _vertex(into, q, s, smooth, lift, st, skin)
						v.append(index[q])
					into[4].append_array([v[0], v[1], v[2], v[0], v[2], v[3]])

	## How many grid cells a side a cell of `skin`'s sheet is (STRIDES).
	static func stride(skin: String) -> int:
		return int(STRIDES.get(skin.get_slice(":", 0), 1))

	## Each corner's share of `skin` averaged over the corners round it (two of its cells each way, a box blur one way
	## then the other): how far in from the sheet's edge it is, for a swell that eases from nothing there. Past the grid
	## a corner counts as the edge's own, so blocks meet.
	func inner(skin: String) -> PackedFloat32Array:
		if smooths.has(skin):
			return smooths[skin]
		var s: PackedFloat32Array = skins[skin]
		var st := stride(skin)
		var across := PackedFloat32Array()
		across.resize(N * N)
		var out := PackedFloat32Array()
		out.resize(N * N)
		for j in range(0, N, st):
			for i in range(0, N, st):
				var sum := 0.0
				for d in range(-2, 3):
					sum += s[j * N + clampi(i + d * st, 0, CELLS)]
				across[j * N + i] = sum / 5.0
		for j in range(0, N, st):
			for i in range(0, N, st):
				if s[j * N + i] <= 0.0:
					continue
				var sum := 0.0
				for d in range(-2, 3):
					sum += across[clampi(j + d * st, 0, CELLS) * N + i]
				out[j * N + i] = sum / 5.0
		smooths[skin] = out
		return out

	func _lifted(q: int, smooth: PackedFloat32Array, lift: float, skin: String) -> float:
		var i := q % N
		var j := q / N
		var y := height(i, j)
		if lift <= 0.0:
			return y
		var p := at(i, j)
		var away := smoothstep(SWELL_FROM, SWELL_FROM + SWELL_EASE, gap(i, j))
		var shape := 1.0
		if skin.begins_with("sand"):
			# (dunes: ridges across the wind, wandering)
			var t := p.x * 0.11 + p.y * 0.05 + sin(p.y * 0.021 + p.x * 0.006) * 2.2
			shape = 0.35 + 0.65 * (0.5 + 0.5 * sin(t))
		return y + lift * smooth[q] * smooth[q] * away * shape

	func _vertex(into: Array, q: int, s: PackedFloat32Array, smooth: PackedFloat32Array, lift: float, st: int, skin: String) -> int:
		var i := q % N
		var j := q / N
		var y := _lifted(q, smooth, lift, skin)
		# (the normal from the corners st either way, as lifted)
		var il := maxi(i - st, 0)
		var ir := mini(i + st, N - 1)
		var ju := maxi(j - st, 0)
		var jd := mini(j + st, N - 1)
		var yl := _lifted(j * N + il, smooth, lift, skin)
		var yr := _lifted(j * N + ir, smooth, lift, skin)
		var yu := _lifted(ju * N + i, smooth, lift, skin)
		var yd := _lifted(jd * N + i, smooth, lift, skin)
		var dx := (yr - yl) / maxf((ir - il) * GRID, 1.0)
		var dz := (yd - yu) / maxf((jd - ju) * GRID, 1.0)
		if is_nan(dx):
			dx = 0.0
		if is_nan(dz):
			dz = 0.0
		var p := at(i, j)
		var k: int = (into[0] as PackedVector3Array).size()
		into[0].append(b.local(p, y))
		into[1].append(Vector3(-dx, 1.0, -dz).normalized())
		into[2].append(Color(1, 1, 1, clampf(s[q], 0.0, 1.0)))
		into[3].append(Vector2(fposmod(p.x, 8192.0), fposmod(p.y, 8192.0)))
		return k


## A kit row with its country's fields laid over it (a kit's "countries": {CODE: {fields}}), for the place at `p`.
static func _local_kit(n: RoadNet, k: Dictionary, p: Vector2) -> Dictionary:
	if not k.has("countries"):
		return k
	var code := str(RegionKit.at_frame(n.region.frame_lat, n.region.frame_lon, p.x, p.y).get("country", ""))
	var over = (k["countries"] as Dictionary).get(code)
	var out := k.duplicate()
	out["country"] = code
	if over is Dictionary:
		out.merge(over, true)
	return out


## What this script keeps of a region, worked out once: its named saddles (so an unnamed one beside one is the same
## pass).
static func _region_info(r: RealRegion) -> Dictionary:
	var id := r.get_instance_id()
	_lock.lock()
	var have = _regions.get(id)
	_lock.unlock()
	if have is Dictionary:
		return have
	var named := PackedVector2Array()
	for row: Array in r.features.get("points", []):
		if str(row[0]) == "saddle" and row[6] != null and str(row[6]) != "":
			named.append(Vector2(float(row[1]), float(row[2])))
	var out := {"named": named}
	_lock.lock()
	_regions[id] = out
	_lock.unlock()
	return out


## Forgets what's kept of the regions (the tests change their features).
static func forget() -> void:
	_lock.lock()
	_regions = {}
	_lock.unlock()


# ---------------------------------------------------------------------------- passes

## A saddle: where a road crosses it (within PASS_REACH, at the road's highest near there) its summit sign with the
## name and height (the map's elevation, else the road's own there) in the country's style, a cairn, a lay-by of gravel
## and a panorama board facing out over the drop; away from every road, a cairn on the saddle.
static func _pass(b: _Block, p: Vector2, elevation, name: String, k: Dictionary, id: String, info: Dictionary) -> void:
	var cross := _crossing(b, p)
	var stone := _stone(k, "cairn", "granite")
	if cross.is_empty():
		var at := SceneryStreamer.stand(b.n, p, b.memo)
		if not is_nan(at.y) and b.clear(Vector2(at.x, at.z), 1.5):
			b.put("cairn:" + stone, Transform3D(Basis().rotated(Vector3.UP, _roll(id + "c") * TAU), b.local(Vector2(at.x, at.z), at.y)))
		return
	if name == "":
		for q: Vector2 in info["named"]:
			if q.distance_to(p) < SAME_PASS:
				return
	var e: int = cross["edge"]
	var s: float = cross["s"]
	var f: Vector2 = cross["dir"]
	var side: float = cross["side"]
	var out := Vector2(-f.y, f.x) * side   # (away from the road, the lay-by's side)
	var half := b.n.width_of(e) * 0.5 + RoadNet.VERGE
	var style := str(k.get("sign", "board"))
	if not SIGNS.has(style):
		style = "board"
	# The lay-by: gravel from just past the verge, along the road either side of the top.
	_layby(b, e, s, side, half)
	# The sign at the lay-by's near end, facing the traffic both ways.
	var y_road := float(cross["y"])
	var metres := float(elevation) if elevation != null else y_road
	var feet := str(k.get("country", "")) in FEET
	var sign_at := b.n.point_at(e, clampf(s - LAYBY_LONG * 0.5 - 3.0, 0.0, b.n.length_of(e))) + out * (half + CLEAR + 1.0)
	if name != "" and b.clear(sign_at, 0.4):
		var y := b.ground(sign_at)
		if not is_nan(y):
			# (its local z along the road: the board faces up and down it)
			var xf := Transform3D(Basis(Vector3(f.y, 0, -f.x), Vector3.UP, Vector3(f.x, 0, f.y)), b.local(sign_at, y - 0.05))
			b.put("sign:" + style + (":" + stone if style == "cairn" else ""), xf)
			var height_text := (("Elevation %s ft" % _thousands(roundi(metres * 3.2808))) if feet else str(SIGNS[style]["height"]) % roundi(metres))
			_sign_words(b, xf, style, name, height_text)
	# The cairn just beyond the lay-by's middle, the panorama board at its far end facing out.
	var cairn_at := b.n.point_at(e, s) + out * (half + LAYBY_OUT + 2.5)
	if style != "cairn" and b.clear(cairn_at, 1.2):
		var y := b.ground(cairn_at)
		if not is_nan(y):
			b.put("cairn:" + stone, Transform3D(Basis().rotated(Vector3.UP, _roll(id + "c") * TAU), b.local(cairn_at, y - 0.1)))
	var board_at := b.n.point_at(e, clampf(s + LAYBY_LONG * 0.5 - 4.0, 0.0, b.n.length_of(e))) + out * (half + LAYBY_OUT - 0.8)
	if b.clear(board_at, 0.6):
		var y := b.ground(board_at)
		if not is_nan(y):
			var o3 := Vector3(out.x, 0, out.y)
			b.put("panorama", Transform3D(Basis(Vector3.UP.cross(o3), Vector3.UP, o3), b.local(board_at, y - 0.05)))


## Where a road crosses near saddle `p`: {edge, s, dir (its way there), side (1 the right of it, -1 the left: the
## flatter for the lay-by), y (the road's height)}, or {} where no road comes within PASS_REACH.
static func _crossing(b: _Block, p: Vector2) -> Dictionary:
	var n := b.n
	var best := -1
	var best_d := PASS_REACH
	var best_s := 0.0
	var seen := {}
	var k0 := RoadBlock.key_of(p.x - PASS_REACH, p.y - PASS_REACH)
	var k1 := RoadBlock.key_of(p.x + PASS_REACH, p.y + PASS_REACH)
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			for e in n.edges_in(Vector2i(bx, bz)):
				if seen.has(e):
					continue
				seen[e] = true
				var pr: Array = n._project(e, p)
				if float(pr[2]) < best_d:
					best_d = float(pr[2])
					best = e
					best_s = float(pr[0])
	if best < 0:
		return {}
	# (the top: the highest of the road within PASS_ALONG either way)
	var l := n.length_of(best)
	var top := best_s
	var top_y := -INF
	var step := 10.0
	var t := maxf(0.0, best_s - PASS_ALONG)
	while t <= minf(l, best_s + PASS_ALONG):
		var y := n.road_y(best, t)
		if not is_nan(y) and y > top_y:
			top_y = y
			top = t
		t += step
	if top_y == -INF:
		return {}
	var hd := n.heading_at(best, top)
	var f := Vector2(sin(hd), -cos(hd))
	var c := n.point_at(best, top)
	var right := Vector2(-f.y, f.x)
	var half := n.width_of(best) * 0.5 + RoadNet.VERGE
	var drop := {}
	for sd: float in [1.0, -1.0]:
		var q := c + right * sd * (half + LAYBY_OUT * 0.6)
		var g := b.bare(q)
		drop[sd] = absf(g - top_y) if not is_nan(g) else INF
		# (a lay-by can't be where another road is)
		if b.gap(q) < CLEAR:
			drop[sd] = INF
	var side := 1.0 if float(drop[1.0]) <= float(drop[-1.0]) else -1.0
	return {"edge": best, "s": top, "dir": f, "side": side, "y": top_y}


## A lay-by on the `side` of edge `e` round `s`: gravel over the land from just past the verge out LAYBY_OUT, its ends
## eased in, every 3 m along and 2 m across.
static func _layby(b: _Block, e: int, s: float, side: float, half: float) -> void:
	var n := b.n
	var l := n.length_of(e)
	var rows := []
	var cols := 4
	var t := -LAYBY_LONG * 0.5
	while t <= LAYBY_LONG * 0.5 + 0.01:
		var ss := clampf(s + t, 0.0, l)
		var c := n.point_at(e, ss)
		var a := n.point_at(e, minf(ss + 1.0, l)) - n.point_at(e, maxf(ss - 1.0, 0.0))
		var f := a.normalized() if a.length() > 1e-4 else Vector2(0, 1)
		var right := Vector2(-f.y, f.x) * side
		var ease := 1.0 - smoothstep(LAYBY_LONG * 0.3, LAYBY_LONG * 0.5, absf(t))
		var row := []
		for q in cols:
			var o := 0.25 + (LAYBY_OUT - 0.25) * q / (cols - 1.0) * (0.35 + 0.65 * ease)
			var p := c + right * (half + o)
			var y := b.ground(p)
			if is_nan(y) or b.gap(p) < 0.1:
				return
			row.append([p, y + 0.04, 1.0 if q < cols - 1 else 0.0])
		rows.append(row)
		t += 3.0
	var arrays: Array = b.free.get("gravel", [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedInt32Array()])
	var base: int = (arrays[0] as PackedVector3Array).size()
	for row: Array in rows:
		for v: Array in row:
			var p: Vector2 = v[0]
			arrays[0].append(b.local(p, float(v[1])))
			arrays[1].append(Vector3.UP)
			arrays[2].append(Color(1, 1, 1, float(v[2])))
			arrays[3].append(Vector2(fposmod(p.x, 8192.0), fposmod(p.y, 8192.0)))
	for r in rows.size() - 1:
		for q in cols - 1:
			var v00 := base + r * cols + q
			var v01 := v00 + 1
			var v10 := v00 + cols
			var v11 := v10 + 1
			# (wound to face up whichever side of the road it's on)
			if side > 0.0:
				arrays[4].append_array([v00, v11, v01, v00, v10, v11])
			else:
				arrays[4].append_array([v00, v01, v11, v00, v11, v10])
	b.free["gravel"] = arrays


## The words on a pass sign: its name and height, on both faces of the board (a label each way).
static func _sign_words(b: _Block, xf: Transform3D, style: String, name: String, height_text: String) -> void:
	var st: Dictionary = SIGNS[style]
	var size: Vector2 = st["size"]
	var mid := float(st["mid"])
	var vertical := size.y > size.x
	for face: float in [1.0, -1.0]:
		var z := xf.basis.z * face
		var x := Vector3.UP.cross(z).normalized()
		var front := xf.origin + Vector3.UP * mid + z * (0.06 if style != "cairn" else 0.0)
		if style == "cairn":
			# (the plaque leans on the cairn's face: one side only)
			if face < 0.0:
				continue
			front = xf.origin + Vector3.UP * mid + xf.basis.z * 0.98
		var line1 := size.y * (0.3 if not vertical else 0.12)
		var px1 := minf(line1 / 48.0, size.x * 0.9 / maxf(1.0, name.length() * 0.55 * 48.0))
		var px2 := minf(size.y * 0.18 / 48.0, size.x * 0.9 / maxf(1.0, height_text.length() * 0.55 * 48.0))
		var up1 := size.y * (0.14 if not vertical else 0.25)
		var up2 := -size.y * (0.22 if not vertical else 0.3)
		b.labels.append({"text": name, "xf": Transform3D(Basis(x, Vector3.UP, z), front + Vector3.UP * up1), "pixel": px1,
			"col": st["words"]})
		b.labels.append({"text": height_text, "xf": Transform3D(Basis(x, Vector3.UP, z), front + Vector3.UP * up2), "pixel": px2,
			"col": st["words"]})


static func _thousands(v: int) -> String:
	var s := str(v)
	return s if s.length() <= 3 else s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)


# ---------------------------------------------------------------------------- peaks and caves

## A peak's summit mark (the kit's "summit": a cross, a trig pillar, a cairn, a post or none) on the top, and its name
## on a plate.
static func _peak(b: _Block, p: Vector2, name: String, k: Dictionary, id: String) -> void:
	var summit := str(k.get("summit", "cairn"))
	if summit == "none" or not summit in SUMMITS:
		return
	var at := SceneryStreamer.stand(b.n, p, b.memo)
	if is_nan(at.y) or not b.clear(Vector2(at.x, at.z), 1.5):
		return
	var stone := _stone(k, "stone", "granite")
	var turn := _roll(id + "p") * TAU
	var xf := Transform3D(Basis().rotated(Vector3.UP, turn), b.local(Vector2(at.x, at.z), at.y))
	match summit:
		"cross": b.put("cross", xf)
		"trig": b.put("trig", xf)
		"post": b.put("post", xf)
		_: b.put("cairn:" + stone, xf)
	if name == "":
		return
	# (a plate on its south and north faces)
	var plate := {"cross": Vector3(0, 1.7, 0.1), "trig": Vector3(0, 0.75, 0.27), "post": Vector3(0, 1.55, 0.1), "cairn": Vector3(0, 0.8, 0.85)}
	var off: Vector3 = plate.get(summit, plate["cairn"])
	for face: float in [1.0, -1.0]:
		var z := xf.basis.z * face
		var x := Vector3.UP.cross(z).normalized()
		var px := minf(0.11 / 48.0, 0.9 / maxf(1.0, name.length() * 0.55 * 48.0))
		b.labels.append({"text": name, "xf": Transform3D(Basis(x, Vector3.UP, z), xf.origin + Vector3.UP * off.y + z * off.z),
			"pixel": px, "col": Color(0.96, 0.95, 0.9) if summit != "trig" else Color(0.1, 0.1, 0.1)})


## A cave's mouth: a hump of the kit's rock with the dark opening facing downhill, and a sign beside it with its name.
static func _cave(b: _Block, p: Vector2, name: String, k: Dictionary, id: String) -> void:
	var at := SceneryStreamer.stand(b.n, p, b.memo)
	if is_nan(at.y):
		return
	var q := Vector2(at.x, at.z)
	if not b.clear(q, 4.5):
		b.skipped += 1
		return
	var down := _downhill(b, q)
	var stone := _stone(k, "stone", "limestone")
	var size := 0.8 + _roll(id + "s") * 0.6
	var face := Vector3(down.x, 0, down.y)
	var xf := Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face).scaled(Vector3.ONE * size), b.local(q, at.y - 0.4))
	b.put("cave:" + stone, xf)
	if name == "":
		return
	var side := Vector2(-down.y, down.x)
	var post := q + down * 4.5 * size + side * 3.0 * size
	if not b.clear(post, 0.5):
		return
	var y := b.ground(post)
	if is_nan(y):
		return
	var pxf := Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face), b.local(post, y - 0.05))
	b.put("post", pxf)
	var px := minf(0.11 / 48.0, 0.9 / maxf(1.0, name.length() * 0.55 * 48.0))
	b.labels.append({"text": name, "xf": Transform3D(pxf.basis, pxf.origin + Vector3.UP * 1.55 + face * 0.1), "pixel": px,
		"col": Color(0.96, 0.95, 0.9)})


## The way downhill from `q` (a unit direction on the ground; south where the land is level).
static func _downhill(b: _Block, q: Vector2) -> Vector2:
	var dx := b.bare(q + Vector2(6, 0)) - b.bare(q - Vector2(6, 0))
	var dz := b.bare(q + Vector2(0, 6)) - b.bare(q - Vector2(0, 6))
	var d := Vector2(-dx, -dz)
	if is_nan(d.x) or is_nan(d.y) or d.length() < 0.05:
		return Vector2(0, 1)
	return d.normalized()


# ---------------------------------------------------------------------------- cliffs, ridges and rims

## A cliff along `line`: its face (the map's way has the drop on its right) in pieces of rock standing on the low
## ground and up past the top, as thick into the high ground as its height asks.
static func _cliff(b: _Block, line: PackedVector2Array, _mapped, k: Dictionary, id: String) -> void:
	var stone := _stone(k, "stone", "granite")
	var i := 0
	for piece: Array in _steps(b, line, STEP):
		i += 1
		var a: Vector2 = piece[0]
		var c: Vector2 = piece[1]
		var m := (a + c) * 0.5
		var f := (c - a).normalized()
		var right := Vector2(-f.y, f.x)
		var hi := b.bare(m - right * 7.0)
		var lo := b.bare(m + right * 7.0)
		if is_nan(hi) or is_nan(lo):
			continue
		if hi < lo:
			var swap := hi
			hi = lo
			lo = swap
		lo = maxf(lo, SEA - 1.5)
		var base := lo - 1.0
		var top := maxf(hi + 0.5, base + CLIFF_LEAST)
		top = minf(top, base + CLIFF_MOST)
		var tall := top - base
		var thick := clampf(tall * 0.4, CLIFF_THICK.x, CLIFF_THICK.y)
		var left := -right
		# (one look at the roads does where none is near: the footprint is within `thick` of its middle)
		var past := b.gap(m + left * thick * 0.5)
		if past < CLEAR + thick * 0.5 + 1.0 and not (b.clear(m, 1.0) and past > CLEAR + thick * 0.5 and b.clear(m + left * thick, 0.5)):
			b.skipped += 1
			continue
		var r := _roll(id + str(i))
		var len := a.distance_to(c) * (1.12 + r * 0.15)
		var lean := Vector3(right.x, 0, right.y) * (r - 0.5) * 0.06 * tall   # (a little out of true, piece to piece)
		var xf := Transform3D(Basis(Vector3(left.x, 0, left.y) * thick, Vector3.UP * tall + lean, Vector3(f.x, 0, f.y) * len),
			b.local(m, base))
		b.put("crag:%s:%d" % [stone, int(r * 3.0) % 3], xf)


## A cliff the map has as a point: a short face across the slope.
static func _cliff_at(b: _Block, p: Vector2, k: Dictionary, id: String) -> void:
	var down := _downhill(b, p)
	var along := Vector2(down.y, -down.x)   # (the drop on its right)
	_cliff(b, PackedVector2Array([p - along * 9.0, p + along * 9.0]), null, k, id)


## A rocky ridge: outcrops along its crest, every 40 m or so (some left out), each on the land.
static func _outcrops(b: _Block, line: PackedVector2Array, k: Dictionary, id: String) -> void:
	var stone := _stone(k, "stone", "granite")
	var i := 0
	for piece: Array in _steps(b, line, 40.0):
		i += 1
		var r := _roll(id + "o" + str(i))
		if r < 0.35:
			continue
		var m: Vector2 = (piece[0] + piece[1]) * 0.5
		var y := b.bare(m)
		if is_nan(y) or not b.clear(m, 4.0):
			continue
		var f: Vector2 = ((piece[1] as Vector2) - (piece[0] as Vector2)).normalized()
		var s := 2.0 + r * 4.0
		var turn := Basis(Vector3(f.y, 0, -f.x) * s * 1.3, Vector3.UP * s * 0.8, Vector3(f.x, 0, f.y) * s * 2.0)
		b.put("boulder:%s:%d" % [stone, int(r * 30.0) % 3], Transform3D(turn, b.local(m, y - s * 0.25)))


## A crater's or caldera's rim along `line`: low walls of dark rock on the land.
static func _rim(b: _Block, line: PackedVector2Array, k: Dictionary, id: String) -> void:
	var stone := _stone(k, "rim", "basalt")
	var i := 0
	for piece: Array in _steps(b, line, 9.0):
		i += 1
		var a: Vector2 = piece[0]
		var c: Vector2 = piece[1]
		var m := (a + c) * 0.5
		var y := b.bare(m)
		if is_nan(y) or not b.clear(m, 3.0):
			continue
		var f := (c - a).normalized()
		var r := _roll(id + "r" + str(i))
		var tall := 1.6 + r * 2.4
		b.put("boulder:%s:%d" % [stone, i % 3], Transform3D(Basis(Vector3(f.y, 0, -f.x) * 5.0, Vector3.UP * tall,
			Vector3(f.x, 0, f.y) * a.distance_to(c) * 1.4), b.local(m, y - tall * 0.3)))


## A volcano's or crater's ring: its rim, and ash over the floor inside.
static func _crater(b: _Block, ring: PackedVector2Array, k: Dictionary, id: String, volcano: bool) -> void:
	_rim(b, _closed(ring), k, id)
	var g := b.grid()
	if volcano or bool(k.get("ash", true)):
		g.fill("ash", ring)


# ---------------------------------------------------------------------------- areas over the land

## Glacier, scree, dune or shingle over `ring`: its skin on the land's grid (a glacier swelling up from its edges, a
## dune rolling), boulders on scree, marram grass on dunes.
static func _area(b: _Block, kind: String, ring: PackedVector2Array, k: Dictionary, id: String) -> void:
	var g := b.grid()
	var skin := ""
	match kind:
		"glacier":
			skin = "ice"
			g.swell[skin] = float(k.get("swell", 6.0))
		"scree":
			skin = "scree:" + _stone(k, "stone", "granite")
		"dune":
			var sand := str(k.get("sand", "pale"))
			skin = "sand:" + (sand if SANDS.has(sand) else "pale")
			g.swell[skin] = float(k.get("swell", 4.0))
		"shingle":
			skin = "shingle"
	if g.fill(skin, ring) == 0:
		return
	if kind == "scree":
		_scatter(b, g, skin, "boulder:" + _stone(k, "stone", "granite"), "boulders", BOULDERS_MOST, 0.25, Vector2(0.4, 1.8), id)
	elif kind == "dune" and bool(k.get("marram", true)):
		_scatter(b, g, skin, "marram", "tufts", TUFTS_MOST, 0.5, Vector2(0.7, 1.3), id)


## Things strewn over a skin's sheet (each of its corners well inside it has `per` chances at `odds`, nudged about its
## cell and stood on the land there, as swollen as the corner): boulders on scree, tufts on dunes.
static func _scatter(b: _Block, g: _Grid, skin: String, model: String, count: String, most: int, odds: float, size: Vector2, id: String) -> void:
	var s: PackedFloat32Array = g.skins[skin]
	var lift := float(g.swell.get(skin, 0.0))
	var smooth := g.inner(skin) if lift > 0.0 else PackedFloat32Array()
	var st := _Grid.stride(skin)
	var cell := GRID * st
	var boulder := model.begins_with("boulder")
	for j in range(st, CELLS, st):
		for i in range(st, CELLS, st):
			var q := j * _Grid.N + i
			if s[q] < 1.0:
				continue
			if int(b.counts[count]) >= most:
				return
			if g.gap(i, j) < SHEET_CLEAR * st + 2.0:
				continue
			var over := g._lifted(q, smooth, lift, skin) - g.height(i, j)
			if is_nan(over):
				continue
			for k in st * st:
				var r := _roll("%s%d_%d" % [id, q, k])
				if r > odds:
					continue
				var r2 := _roll("%s%d_%d+" % [id, q, k])
				var p := g.at(i, j) + (Vector2(r2, fmod(r2 * 7.31, 1.0)) - Vector2(0.5, 0.5)) * cell
				var y := b.bare(p)
				if is_nan(y):
					continue
				var sc := lerpf(size.x, size.y, fmod(r2 * 37.0, 1.0))
				var full := model + (":%d" % (int(r2 * 97.0) % 3) if boulder else "")
				b.put(full, Transform3D(Basis().rotated(Vector3.UP, r2 * 40.0).scaled(Vector3(sc, sc * (0.6 if boulder else 1.0), sc)),
					b.local(p, y + over - (sc * 0.15 if boulder else 0.05))))
				b.counts[count] = int(b.counts[count]) + 1


## A reef: rock heads at low water over `ring` where it's sea (on the land where it isn't).
static func _reef(b: _Block, ring: PackedVector2Array, k: Dictionary, id: String) -> void:
	var stone := _stone(k, "stone", "reef")
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	box = box.intersection(b.box)
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	var step := 10.0
	var z := ceilf(box.position.y / step) * step
	while z < box.end.y:
		var x := ceilf(box.position.x / step) * step
		while x < box.end.x:
			var r := _roll("%s%d_%d" % [id, int(x), int(z)])
			if r < 0.45 and int(b.counts["heads"]) < HEADS_MOST:
				var p := Vector2(x + r * 9.0 - 2.0, z + fmod(r * 53.0, 1.0) * 8.0 - 4.0)
				if Geometry2D.is_point_in_polygon(p, ring) and b.clear(p, 3.0):
					var g := b.bare(p)
					var y := SEA - 0.35 if is_nan(g) or g < SEA + 0.5 else g - 0.3
					var sc := 1.5 + fmod(r * 31.0, 1.0) * 3.0
					b.put("boulder:%s:%d" % [stone, int(r * 61.0) % 3], Transform3D(Basis().rotated(Vector3.UP, r * 20.0).scaled(Vector3(sc, 0.5, sc * 0.8)), b.local(p, y)))
					b.counts["heads"] = int(b.counts["heads"]) + 1
			x += step
		z += step


# ---------------------------------------------------------------------------- small helpers

## The pieces of `line` (region frame) every `step` from its first point: [[a, b], ...], each the block's whose middle
## it is in.
static func _steps(b: _Block, line: PackedVector2Array, step: float) -> Array:
	var out := []
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var l := p.distance_to(q)
		if l < 0.05:
			continue
		var count := maxi(1, int(ceil(l / step)))
		for j in count:
			var a := p.lerp(q, float(j) / count)
			var c := p.lerp(q, float(j + 1) / count)
			if b.mine((a + c) * 0.5):
				out.append([a, c])
	return out


## A ring of `count` points `r` round `c`.
static func _ring(c: Vector2, r: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		out.append(c + Vector2.from_angle(TAU * i / count) * r)
	return out


## A band `w` either side of `line` (an outline round it).
static func _band(line: PackedVector2Array, w: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in line.size():
		var a := line[maxi(i - 1, 0)]
		var c := line[mini(i + 1, line.size() - 1)]
		var f := (c - a).normalized() if a.distance_to(c) > 1e-4 else Vector2(1, 0)
		var s := Vector2(-f.y, f.x) * w
		right.append(line[i] + s)
		left.append(line[i] - s)
	left.reverse()
	right.append_array(left)
	return right


static func _centre(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	return c / maxf(1.0, ring.size())


static func _closed(ring: PackedVector2Array) -> PackedVector2Array:
	var out := ring.duplicate()
	out.append(ring[0])
	return out


## A number from 0 to 1 for `what`, the same on every machine (its hash stirred, so names a letter apart are far
## apart).
static func _roll(what: String) -> float:
	var h := hash(what) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0xffffff)


## The kit's stone (a STONES name) for `field`, or `fallback`.
static func _stone(k: Dictionary, field: String, fallback: String) -> String:
	var s := str(k.get(field, fallback))
	return s if STONES.has(s) else fallback


# ---------------------------------------------------------------------------- meshes

## The mesh of `model` (lay_out's names: "crag:STONE:V", "boulder:STONE:V", "cairn:STONE", "cave:STONE", "cross",
## "trig", "post", "panorama", "marram", "sign:STYLE[:STONE]"), made once. "wild:" in front is taken off; a kit row's own
## model (as "wild:pass") is a marker no block draws.
static func mesh(model: String) -> Mesh:
	if model.begins_with("wild:"):
		model = model.substr(5)
	_lock.lock()
	var have = _meshes.get(model)
	_lock.unlock()
	if have is Mesh:
		return have
	var out := _make(model)
	_lock.lock()
	_meshes[model] = out
	_lock.unlock()
	return out


static func _make(model: String) -> Mesh:
	var kind := model.get_slice(":", 0)
	var arg := model.get_slice(":", 1) if model.contains(":") else ""
	var v := int(model.get_slice(":", 2)) if model.count(":") >= 2 else 0
	var col: Color = STONES.get(arg, STONES["rock"])
	var a := AdventureProps.new_arrays()
	match kind:
		"crag":
			_crag(a, col, v)
		"boulder":
			_boulder(a, col, v, Vector3(0.5, 0.75, 0.5))
		"cairn":
			_cairn(a, col)
		"cave":
			_cave_mesh(a, col)
		"cross":
			var wood: Color = STONES["timber"]
			AdventureProps.box(a, Transform3D(), Vector3(0.16, 4.2, 0.16), wood)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 2.9, 0)), Vector3(1.7, 0.16, 0.16), wood)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.55, 0)), Vector3(0.5, 0.32, 0.18), STONES["slate"])
			_cairn(a, STONES["granite"].darkened(0.1), 0.55)
		"trig":
			AdventureProps.cone(a, Transform3D(Basis().rotated(Vector3.UP, PI / 4.0)), 0.42, 0.0, 1.25, STONES["white"], 4, 0.3)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.25, 0)), Vector3(0.18, 0.05, 0.18), STONES["black"])
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 0.75, 0.24)), Vector3(0.36, 0.22, 0.04), STONES["green"])
		"post":
			AdventureProps.box(a, Transform3D(), Vector3(0.12, 1.75, 0.12), STONES["timber"])
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, 1.42, 0.04)), Vector3(0.95, 0.3, 0.05), STONES["brown"])
		"panorama":
			_panorama(a)
		"marram":
			_marram(a)
		"sign":
			_sign(a, arg, model.get_slice(":", 2) if model.count(":") >= 2 else "granite")
		_:
			AdventureProps.box(a, Transform3D(), Vector3.ONE, col)
	return AdventureProps.to_mesh(a)


## A deterministic wobble (-1 to 1) for corner (i, j) of variant `v`.
static func _jit(i: int, j: int, v: int) -> float:
	return float(hash(Vector3i(i, j, v)) & 0xffff) / 32767.5 - 1.0


## A unit crag: a slab of rock from its face at x 0 (facing -x, the drop) back to x 1, y 0 to 1, z -0.5 to 0.5, its face
## ribbed and broken (a grid of corners pushed in and out) and its top edge ragged.
static func _crag(a: Dictionary, col: Color, v: int) -> void:
	var nu := 5   # along
	var nv := 7   # up
	var face := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			var z := -0.5 + float(i) / nu
			var y := float(j) / nv
			var x := 0.0
			if i > 0 and i < nu:
				x = 0.06 + _jit(i, j, v) * 0.07 + (0.06 * sin(z * 9.0 + v * 2.0))
			else:
				x = 0.03 + _jit(i, j, v) * 0.02
			if j == nv:
				y = 1.0 - absf(_jit(i, j + 7, v)) * 0.08
				x += 0.12
			row.append(Vector3(x, y, z))
		face.append(row)
	for j in nv:
		for i in nu:
			var p0: Vector3 = face[j][i]
			var p1: Vector3 = face[j][i + 1]
			var p2: Vector3 = face[j + 1][i + 1]
			var p3: Vector3 = face[j + 1][i]
			var shade := col.darkened(0.12 * absf(_jit(i, j, v + 11))).lightened(0.06 * float(j) / nv)
			# (the face looks -x: wound so its front is out there)
			AdventureProps._quad(a, p0, p3, p2, p1, shade)
			if (i + j + v) % 4 == 0:
				# (a darker crack)
				AdventureProps._tri(a, p0 + Vector3(-0.004, 0, 0), p3 + Vector3(-0.004, 0, 0), p1 + Vector3(-0.004, 0, 0), shade.darkened(0.25))
	# The top, the back and the ends.
	for i in nu:
		var p0: Vector3 = face[nv][i]
		var p1: Vector3 = face[nv][i + 1]
		AdventureProps._quad(a, p0, p1, Vector3(1, p1.y, p1.z), Vector3(1, p0.y, p0.z), col.lightened(0.05))
	AdventureProps._quad(a, Vector3(1, 0, -0.5), Vector3(1, 1, -0.5), Vector3(1, 1, 0.5), Vector3(1, 0, 0.5), col.darkened(0.1))
	for e: int in [0, nu]:
		var zs := -0.5 if e == 0 else 0.5
		for j in nv:
			var p0: Vector3 = face[j][e]
			var p1: Vector3 = face[j + 1][e]
			if e == 0:
				AdventureProps._quad(a, p0, Vector3(1, p0.y, zs), Vector3(1, p1.y, zs), p1, col.darkened(0.08))
			else:
				AdventureProps._quad(a, p0, p1, Vector3(1, p1.y, zs), Vector3(1, p0.y, zs), col.darkened(0.08))


## A boulder: a lumpy ball `r` (x, y, z half sizes) round (0, r.y, 0) of variant `v`, flat-ish underneath.
static func _boulder(a: Dictionary, col: Color, v: int, r: Vector3, at := Vector3.ZERO) -> void:
	var nl := 7
	var nr := 4
	var pts := []
	for j in nr + 1:
		var row := []
		var t := PI * float(j) / nr
		for i in nl:
			var u := TAU * float(i) / nl
			var k := 1.0 + _jit(i, j, v + 3) * 0.18
			if j == 0 or j == nr:
				k = 1.0
			var y := cos(t)
			if y < -0.3:
				y = -0.3
			row.append(at + Vector3(sin(t) * cos(u) * r.x * k, (y + 0.3) / 1.3 * r.y * 2.0, sin(t) * sin(u) * r.z * k))
		pts.append(row)
	for j in nr:
		for i in nl:
			var p0: Vector3 = pts[j][i]
			var p1: Vector3 = pts[j][(i + 1) % nl]
			var p2: Vector3 = pts[j + 1][(i + 1) % nl]
			var p3: Vector3 = pts[j + 1][i]
			var shade := col.darkened(0.15 * float(j) / nr + 0.06 * absf(_jit(i, j, v)))
			AdventureProps._quad(a, p0, p3, p2, p1, shade)


## A cairn: a pile of stones `scale` times a summit's (1.7 m).
static func _cairn(a: Dictionary, col: Color, scale := 1.0) -> void:
	var layers := [[0.9, 0.0, 0.45], [0.72, 0.38, 0.42], [0.52, 0.75, 0.38], [0.34, 1.08, 0.34], [0.18, 1.38, 0.3]]
	var k := 0
	for l: Array in layers:
		var r := float(l[0]) * scale
		var y := float(l[1]) * scale
		var h := float(l[2]) * scale
		var count := maxi(1, int(r * 7.0))
		for i in count:
			var u := TAU * (i + 0.5 * k) / count
			var at := Vector3(cos(u) * r * 0.55, y, sin(u) * r * 0.55)
			_boulder(a, col.darkened(0.08 * (k % 3)), k * 7 + i, Vector3(r * 0.42, h * 0.55, r * 0.36), at)
		k += 1


## A cave's mouth: a hump of rock 8 wide, 4.5 high and 6 deep (z from -3 to 3, its mouth facing +z), the opening a dark
## arch on its front.
static func _cave_mesh(a: Dictionary, col: Color) -> void:
	var r := Vector3(4.0, 4.5, 3.0)
	_boulder(a, col, 5, Vector3(r.x, r.y * 0.5, r.z))
	# The opening: a fan on the hump's front, out a little from its surface.
	var dark := Color(0.02, 0.02, 0.02)
	var n := 10
	var w := 1.4
	var h := 2.3
	var surface := func(x: float, y: float) -> Vector3:
		var t := clampf(1.0 - (x / r.x) * (x / r.x) - ((y / r.y) - 0.0) * ((y / r.y) - 0.0), 0.02, 1.0)
		return Vector3(x, y, r.z * sqrt(t) * 0.92 + 0.12)
	var base := surface.call(0.0, 0.0) as Vector3
	for i in n:
		var u0 := PI * float(i) / n
		var u1 := PI * float(i + 1) / n
		var p0: Vector3 = surface.call(cos(u0) * w, sin(u0) * h)
		var p1: Vector3 = surface.call(cos(u1) * w, sin(u1) * h)
		AdventureProps._tri(a, base, p0, p1, dark)
	# (the cave's floor going in)
	AdventureProps._quad(a, base + Vector3(-w, 0.02, 0), base + Vector3(w, 0.02, 0), base + Vector3(w * 0.6, 0.02, -1.5), base + Vector3(-w * 0.6, 0.02, -1.5), dark.lightened(0.05))


## A panorama board: a slanted table on two legs, facing +z, the hills drawn on it.
static func _panorama(a: Dictionary) -> void:
	var legs: Color = STONES["steel"].darkened(0.3)
	AdventureProps.box(a, Transform3D(Basis(), Vector3(-0.45, 0, -0.1)), Vector3(0.08, 0.95, 0.08), legs)
	AdventureProps.box(a, Transform3D(Basis(), Vector3(0.45, 0, -0.1)), Vector3(0.08, 0.95, 0.08), legs)
	var tilt := Basis(Vector3.RIGHT, -0.6)
	var c := Vector3(0, 1.0, 0)
	var w := 1.2
	var d := 0.7
	var corner := func(x: float, z: float) -> Vector3:
		return c + tilt * Vector3(x, 0.0, z)
	AdventureProps._quad(a, corner.call(-w / 2, -d / 2), corner.call(-w / 2, d / 2), corner.call(w / 2, d / 2), corner.call(w / 2, -d / 2), Color(0.85, 0.85, 0.8))
	# (the sky, and the hills' outline across it)
	var sky := Color(0.55, 0.7, 0.85)
	var hill := Color(0.35, 0.4, 0.38)
	var up := tilt * Vector3.UP * 0.004
	AdventureProps._quad(a, corner.call(-w / 2 + 0.05, -d / 2 + 0.05) + up, corner.call(-w / 2 + 0.05, 0.0) + up, corner.call(w / 2 - 0.05, 0.0) + up, corner.call(w / 2 - 0.05, -d / 2 + 0.05) + up, sky)
	var peaks := [0.0, 0.12, 0.05, 0.2, 0.08, 0.16, 0.02]
	for i in peaks.size() - 1:
		var x0 := -w / 2 + 0.05 + (w - 0.1) * i / (peaks.size() - 1.0)
		var x1 := -w / 2 + 0.05 + (w - 0.1) * (i + 1) / (peaks.size() - 1.0)
		AdventureProps._quad(a, corner.call(x0, 0.0) + up * 2.0, corner.call(x0, -float(peaks[i])) + up * 2.0, corner.call(x1, -float(peaks[i + 1])) + up * 2.0, corner.call(x1, 0.0) + up * 2.0, hill)
	AdventureProps._quad(a, corner.call(-w / 2, d / 2), corner.call(-w / 2, -d / 2), corner.call(-w / 2, -d / 2) - Vector3(0, 0.05, 0), corner.call(-w / 2, d / 2) - Vector3(0, 0.05, 0), legs)


## A tuft of marram grass: blades leaning out round its middle, under a metre.
static func _marram(a: Dictionary) -> void:
	var col: Color = STONES["marram"]
	for i in 9:
		var u := TAU * i / 9.0 + _jit(i, 0, 1) * 0.3
		var lean := Vector3(cos(u), 0, sin(u)) * (0.25 + 0.15 * _jit(i, 1, 1))
		var h := 0.6 + 0.3 * absf(_jit(i, 2, 1))
		var side := Vector3(-sin(u), 0, cos(u)) * 0.025
		var tip := lean + Vector3.UP * h
		var shade := col.darkened(0.1 * absf(_jit(i, 3, 1))).lerp(STONES["straw"], 0.3 * absf(_jit(i, 4, 1)))
		AdventureProps._tri(a, -side, side, tip, shade)
		AdventureProps._tri(a, side, -side, tip, shade)


## A pass sign of `style` (SIGNS): its board on posts at the height its words are (dress puts them on), the board's face
## across local x, looking along local z both ways; the "cairn" style a big cairn with a slate plaque on its +z face.
static func _sign(a: Dictionary, style: String, stone: String) -> void:
	var st: Dictionary = SIGNS.get(style, SIGNS["board"])
	var size: Vector2 = st["size"]
	var mid := float(st["mid"])
	var board: Color = STONES.get(str(st["board"]), STONES["white"])
	var edge: Color = STONES.get(str(st["edge"]), STONES["black"])
	match style:
		"cairn":
			_cairn(a, STONES.get(stone, STONES["granite"]), 1.35)
			AdventureProps.box(a, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, mid - size.y * 0.5, 0.92)), Vector3(size.x, size.y, 0.05), board)
		"toge":
			AdventureProps.box(a, Transform3D(), Vector3(0.2, mid + size.y * 0.5 + 0.1, 0.2), STONES["timber"])
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, mid - size.y * 0.5, 0)), Vector3(size.x, size.y, 0.1), board.lightened(0.15))
			AdventureProps.cone(a, Transform3D(Basis().rotated(Vector3.UP, PI / 4.0), Vector3(0, mid + size.y * 0.5 + 0.1, 0)), 0.55, 0.0, 0.3, STONES["slate"], 4, 0.0)
		_:
			var post: Color = STONES.get(str(st["posts"]), STONES["steel"])
			for x: float in [-size.x * 0.36, size.x * 0.36]:
				AdventureProps.box(a, Transform3D(Basis(), Vector3(x, 0, 0)), Vector3(0.09, mid + size.y * 0.5, 0.09), post)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, mid - size.y * 0.5 - 0.04, 0)), Vector3(size.x + 0.08, size.y + 0.08, 0.07), edge)
			AdventureProps.box(a, Transform3D(Basis(), Vector3(0, mid - size.y * 0.5, 0)), Vector3(size.x, size.y, 0.1), board)


# ---------------------------------------------------------------------------- the sheets' look

## The material of sheet skin `skin` ("scree:STONE", "sand:SAND", "shingle", "ash", "gravel").
static func skin_material(skin: String) -> ShaderMaterial:
	_lock.lock()
	var have = _skin_mats.get(skin)
	_lock.unlock()
	if have is ShaderMaterial:
		return have
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHEET_SHADER
	var base := skin.get_slice(":", 0)
	var arg := skin.get_slice(":", 1) if skin.contains(":") else ""
	var s: Dictionary = SKINS.get(base, SKINS["gravel"])
	var ca: Color = s["a"]
	var cb: Color = s["b"]
	if base == "scree" and STONES.has(arg):
		ca = (STONES[arg] as Color).darkened(0.05)
		cb = (STONES[arg] as Color).darkened(0.4)
	elif base == "sand" and SANDS.has(arg):
		ca = SANDS[arg][0]
		cb = SANDS[arg][1]
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint_a", ca)
	m.set_shader_parameter("tint_b", cb)
	m.set_shader_parameter("pattern", int(s["pattern"]))
	m.set_shader_parameter("grain", float(s["grain"]))
	m.set_shader_parameter("rough", float(s["rough"]))
	_lock.lock()
	_skin_mats[skin] = m
	_lock.unlock()
	return m


## The sheets' shader: two colours mixed by a grain in the region's own metres (the UVs), a pattern over them, its edge
## ragged where its share (the colour's alpha) runs out, and drawn a little towards the camera (more the further it
## is) so the land's coarser levels don't show through it.
const SHEET_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec3 tint_a : source_color = vec3(0.9);
uniform vec3 tint_b : source_color = vec3(0.7);
uniform int pattern = 0;
uniform float grain = 1.0;
uniform float rough = 0.9;
uniform float pull = 0.004;
varying vec2 wp;
varying float share;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wp = UV;
	share = COLOR.a;
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 d = cam - VERTEX;
	float l = length(d);
	VERTEX += d / max(l, 0.001) * min(0.12 + l * pull, l * 0.3);
}

void fragment() {
	// (each grain fades to its mean where it's finer than the pixels, so far off there's no sparkle)
	float fw = length(fwidth(wp));
	float edge = noise(wp * 0.11) * 0.55 + mix(0.5, noise(wp * 0.7), 1.0 - smoothstep(0.3, 1.0, fw * 0.7)) * 0.45;
	if (share < 0.18 + edge * 0.64) {
		discard;
	}
	float k1 = 1.0 - smoothstep(0.3, 1.0, fw * grain);
	float k2 = 1.0 - smoothstep(0.3, 1.0, fw * grain * 3.7);
	float g = mix(0.5, noise(wp * grain), k1) * 0.6 + mix(0.5, noise(wp * grain * 3.7), k2) * 0.4;
	vec3 c = mix(tint_a, tint_b, g);
	if (pattern == 1) {
		float s = noise(vec2(wp.x * 0.04 + wp.y * 0.01, wp.y * 0.5));
		float crack = smoothstep(0.46, 0.5, s) * (1.0 - smoothstep(0.5, 0.54, s));
		c = mix(c, tint_b * 0.55, crack * (1.0 - smoothstep(0.3, 1.0, fw * 0.5)));
	} else if (pattern == 2) {
		float k3 = 1.0 - smoothstep(0.3, 1.0, fw * grain * 2.3);
		float st = mix(0.5, noise(wp * grain * 2.3 + 7.0), k3);
		c *= 0.72 + 0.5 * smoothstep(0.25, 0.75, st);
	} else if (pattern == 3) {
		float r = sin(wp.x * 1.4 + wp.y * 0.55 + noise(wp * 0.15) * 6.0);
		c *= 0.93 + 0.07 * r * (1.0 - smoothstep(0.3, 1.0, fw * 0.5));
	}
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
"""
