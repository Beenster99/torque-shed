class_name RoadBlock
extends RefCounted
## The roads of one 512 m square of a ride's region (Ride Anywhere v2, T6): every stretch of road in it (a piece: one
## edge's run inside the square, trimmed back to the junctions' mouths) and every junction whose node is in it, with
## the buildings standing there, laid out as plain data from the RoadNet alone (so it runs on a worker thread, and every
## machine lays out the same block). What a block holds is the interface the other threads build on: see
## ride-anywhere-v2/interfaces/road-block.md, pinned by tests/road_block_tests.gd.

## Bump when what a block holds, or how it's laid out, changes: it's in every block's hash, so a crew on mixed versions
## finds out at the lobby.
const VERSION := 10
const SIZE := 512.0
## A piece cut by the block's edge runs on this far (m) into the next block, so the two decks overlap at the seam.
const SEAM := 0.05
## A building stands at least this far past a road's verge (m), or it's left out (_over_road).
const CLEAR := 1.0
## The deck's points across (edge, quarter, crown, quarter, edge), as the single-line road's.
const ACROSS := 5
## The verge's skirt: from the verge's outer edge it runs this far further out and down under the land (m).
const SKIRT_OUT := 1.6
const SKIRT_DOWN := 1.2
## The white lines: an edge line this far in from the edge (m), this wide, on roads at least EDGE_LINE_MIN wide; a
## centre line's dashes DASH on, GAP off (m), on two-lane roads; all LINE_LIFT above the deck.
const LINE_IN := 0.3
const LINE_W := 0.12
const EDGE_LINE_MIN := 4.5
const DASH := 3.0
const GAP := 6.0
const LINE_LIFT := 0.012
## A roundabout's island stands this high, its kerb this wide (m).
const ISLAND_H := 0.15
## A roundabout's island at least MOUND_FROM m across has a grassy mound MOUND_H m high in it, from MOUND_IN m inside its
## kerb, planted with SHRUBS shrubs, as the planned road's roundabouts have (AdventureJunctions._island).
const MOUND_FROM := 3.5
const MOUND_IN := 1.6
const MOUND_H := 0.75
const SHRUBS := 7
const SHRUB_COLOURS: Array[Color] = [Color(0.16, 0.34, 0.12), Color(0.3, 0.42, 0.14), Color(0.55, 0.3, 0.42)]
## A junction's surface is drawn in this many rings out from its middle (_drape).
const DRAPE_RINGS := 4
const ISLAND_KERB := 0.3
const ISLAND_GRASS := Color(0.3, 0.42, 0.2)
const KERB := Color(0.62, 0.62, 0.6)
## A bridge's parapets: as thick as this (m), and as tall and of the stone the single-line ride's are
## (AdventureChunk.PARAPET); a pier under it every PIER_GAP or so where the land is more than PIER_MIN below its deck.
const PARAPET_W := 0.45
const PIER_MIN := 1.5
## A road crossing over or under another this far (m) above or below it isn't on it (_on_other).
const OVER := 2.5

var key := Vector2i.ZERO
var rect := Rect2()
var hash := ""
var pieces: Array[Dictionary] = []
var junctions: Array[Dictionary] = []
var buildings: Array = []
## The trees and bushes standing in the block (RoadNet.dress): kind (AdventureProps.mesh) -> Array of Transform3D, from
## the block's corner (anchor).
var trees := {}
## The posts by the road (_roadside): kind ("kit_post_<style>", a region kit's marker posts, RegionKit.post_mesh; "post",
## a fence's, AdventureProps.mesh) -> Array of Transform3D from the block's corner. They stand on the verge.
var roadside := {}
## The mesh and collision arrays the streamer commits (T6's own business; their shape may change freely).
var arrays := {}
var ms := 0.0
var net: RoadNet
## Whether the place's markings (RoadMarkings, T8) paint its lines, rather than the plain white ones.
var _marked := false
## Set by the streamer when the ground under it sharpened while it was being laid out (it's laid out again).
var stale := false


## The key of the block (x, z) is in.
static func key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / SIZE), floori(z / SIZE))


## The hash of block `k` of a region whose hash is `region_hash`.
static func hash_of(region_hash: String, k: Vector2i) -> String:
	return ("%d|%s|%d,%d" % [VERSION, region_hash, k.x, k.y]).sha1_text().substr(0, 12)


## Lays out block `k` of `n`.
static func build(n: RoadNet, k: Vector2i) -> RoadBlock:
	var t0 := Time.get_ticks_usec()
	var b := RoadBlock.new()
	b.net = n
	b.key = k
	b.rect = Rect2(Vector2(k) * SIZE, Vector2(SIZE, SIZE))
	b.hash = hash_of(n.region.hash + n.flats_hash_of(k), k)
	var r := n.region
	var edges := n.edges_in(k)
	for ei in edges:
		b._add_pieces(ei)
	var seen := {}
	for node in n.nodes_in(k):
		var j := n.junction_of(node)
		if j.is_empty() or seen.has(int(j["node"])):
			continue
		# A roundabout is the block's that has its lowest node.
		if key_of(r.node_pos[int(j["node"])].x, r.node_pos[int(j["node"])].y) != k:
			continue
		seen[int(j["node"])] = true
		b.junctions.append(_public(j))
	b.junctions.sort_custom(func(p, q): return int(p["node"]) < int(q["node"]))
	for row: Array in n.buildings_in(k):
		if b._over_road(row) or n.in_flat(float(row[0]), float(row[1]), maxf(float(row[2]), float(row[3])) * 0.5):
			continue
		var out := row.duplicate()
		out.append(b._building_y(row))
		b.buildings.append(out)
	b._plant()
	b._lay_out()
	b.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return b


## A junction as the interface has it (the net's own working keys left off).
static func _public(j: Dictionary) -> Dictionary:
	var arms := []
	for a: Dictionary in j["arms"]:
		arms.append({"edge": a["edge"], "node": a["node"], "heading": a["heading"], "width": a["width"],
			"class": a["class"], "mouth": a["mouth"], "main": a["main"]})
	return {"node": j["node"], "nodes": j["nodes"], "kind": j["kind"], "pos": j["pos"], "radius": j["radius"],
		"arms": arms, "island": j["island"], "pair": j["pair"], "outline": j["outline"]}


## The pieces of edge `ei` inside this block: its plain road (between its mouths) cut where it crosses the block's
## edges, each run on SEAM past a cut.
func _add_pieces(ei: int) -> void:
	var r := net.region
	var len := net.length_of(ei)
	var s0 := net.mouth(ei, r.edge_a[ei])
	var s1 := len - net.mouth(ei, r.edge_b[ei])
	if s1 - s0 < 0.01:
		return
	# Every STEP along it, and where it crosses in and out of the block.
	var ss := PackedFloat32Array([s0])
	var s := (floorf(s0 / RoadNet.STEP) + 1.0) * RoadNet.STEP
	while s < s1 - 0.01:
		ss.append(s)
		s += RoadNet.STEP
	ss.append(s1)
	var runs := []
	var start := -1.0
	var prev_in := false
	for k in ss.size():
		var p := net.point_at(ei, ss[k])
		var inside := rect.has_point(p)
		if k > 0 and inside != prev_in:
			var cut := _crossing(ei, ss[k - 1], ss[k], prev_in)
			if inside:
				start = maxf(cut - SEAM, s0)
			else:
				runs.append(Vector2(start, minf(cut + SEAM, s1)))
				start = -1.0
		elif k == 0 and inside:
			start = s0
		prev_in = inside
	if prev_in and start >= 0.0:
		runs.append(Vector2(start, s1))
	for run: Vector2 in runs:
		if run.y - run.x < 0.01:
			continue
		var pts := PackedVector3Array()
		var at := PackedFloat32Array([run.x])
		var q := (floorf(run.x / RoadNet.STEP) + 1.0) * RoadNet.STEP
		while q < run.y - 0.01:
			at.append(q)
			q += RoadNet.STEP
		at.append(run.y)
		for a in at:
			var p := net.point_at(ei, a)
			pts.append(Vector3(p.x, net.road_y(ei, a), p.y))
		pieces.append({"edge": ei, "s0": run.x, "s1": run.y, "points": pts, "width": net.width_of(ei),
			"lanes": net.lanes_of(ei), "class": r.class_of(ei), "surface": r.surface_of(ei), "name": r.name_of(ei),
			"oneway": r.edge_oneway[ei], "a": r.edge_a[ei], "b": r.edge_b[ei], "ring": net.on_ring(ei), "at": at})


## Where (s) edge `ei` crosses the block's edge between `sa` (inside if `a_in`) and `sb`.
func _crossing(ei: int, sa: float, sb: float, a_in: bool) -> float:
	var lo := sa
	var hi := sb
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if rect.has_point(net.point_at(ei, mid)) == a_in:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## The ground a building stands on: the lowest of the land (roads cut in) under its middle and corners.
func _building_y(row: Array) -> float:
	var bx := float(row[0])
	var bz := float(row[1])
	var w := float(row[2])
	var d := float(row[3])
	var yaw := float(row[4])
	var y := INF
	for cx: float in [0.0, -0.5, 0.5]:
		for cz: float in [0.0, -0.5, 0.5]:
			if (cx == 0.0) != (cz == 0.0):
				continue
			var px := bx + (cx * w) * cos(yaw) + (cz * d) * sin(yaw)
			var pz := bz - (cx * w) * sin(yaw) + (cz * d) * cos(yaw)
			y = minf(y, net.ground_at(px, pz, float(net.height.call(px, pz))))
	return y


## Plants the block's trees (trees) from the net's dress: where the canopy map has woods, as many as its share of the
## ground under trees and their crowns' size say, as tall as it has them (as AdventureChunk does along the planned road);
## where there's no canopy map, by what covers the ground. None on a road or its verge, by a building, or in water.
func _plant() -> void:
	if net.dress.is_empty():
		return
	var t: RealTerrain = net.dress["terrain"]
	var look: Dictionary = net.dress.get("look", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([net.region.hash, "trees", key])
	var broad := str(look.get("broad", "tree"))
	var needle := str(look.get("needle", "pine"))
	var autumn := float(look.get("autumn", 0.0))
	var bush := "bush"
	for kind: String in (look.get("plants", {}) as Dictionary):
		if kind in AdventureChunk.BUSHES:
			bush = kind
			break
	var o := anchor()
	var step := AdventureChunk.CANOPY_STEP
	var north := absf(t.lat0) > float(AdventureChunk.NEEDLE_ODDS["north_lat"])
	var looks := int(SIZE / step)
	for j in looks:
		for i in looks:
			var cx := rect.position.x + (i + 0.5) * step
			var cz := rect.position.y + (j + 0.5) * step
			var v := t.trees_at(cx, cz)
			var share := 0.0
			var tallest := 0.0
			var leaf := 0
			if v >= 0:
				share = float((v >> 5) & 7) / 7.0
				tallest = float(v & 31) * AdventureChunk.CANOPY_HEIGHT_STEP
				leaf = (v >> 8) & 3
			else:
				# No canopy map here: what covers the ground says how wooded it is, the trees of a middling height.
				var c := t.cover(cx, cz)
				var cover := RealPack.COVER[c] if c >= 0 and c < RealPack.COVER.size() else ""
				share = float((AdventureChunk.ODDS["trees"] as Dictionary).get(cover, 0.05)) * 0.6
				tallest = rng.randf_range(9.0, 16.0)
				if rng.randf() < float((AdventureChunk.ODDS["bushes"] as Dictionary).get(cover, 0.1)) * 0.35:
					_stand(t, bush, cx + rng.randf_range(-7.0, 7.0), cz + rng.randf_range(-7.0, 7.0), 2.5, o, rng)
			if share <= 0.0:
				continue
			var p_needle := 1.0 if leaf == 2 else (0.0 if leaf == 1 else (0.5 if leaf == 3 else
				float(AdventureChunk.NEEDLE_ODDS["north" if north else "base"])))
			if v < 0 and not north:
				p_needle *= 0.5   # (odd trees in open country are mostly broadleaves)
			var conifer := float(absi(hash([floori(cx / AdventureChunk.NEEDLE_PATCH), floori(cz / AdventureChunk.NEEDLE_PATCH)])) % 1000) / 1000.0 < p_needle
			var crown: Array = AdventureChunk.CROWN_NEEDLE if conifer else AdventureChunk.CROWN_BROAD
			var wide := float(crown[0]) * tallest + float(crown[1])
			var many := minf(float(AdventureChunk.CANOPY_MOST), share * step * step / (wide * wide))
			var n := int(many + rng.randf())
			for k in n:
				var kind := needle if (conifer if leaf != 3 else rng.randf() < 0.5) else (broad if share < 0.5 or rng.randf() < 0.4 else "tree")
				if kind == "tree" and broad in ["jungle_tree", "acacia"]:
					kind = broad
				if kind in ["tree", "oak"] and autumn > 0.0 and rng.randf() < autumn:
					kind = "autumn_tree"
				var tall := maxf(3.0, tallest * rng.randf_range(0.65, 1.0))
				var size: Array = AdventureChunk.TREE_SIZE.get(kind, [6.6, 5.2])
				var across := (float(crown[0]) * tall + float(crown[1])) / float(size[1])
				var x := cx + rng.randf_range(-0.5, 0.5) * step
				var z := cz + rng.randf_range(-0.5, 0.5) * step
				_stand(t, kind, x, z, 6.0, o, rng, Vector3(across, tall / float(size[0]), across))


## Stands one `kind` at region-frame (x, z) on the land (RoadNet.ground_at), at least `clear` m past any road's verge,
## off the buildings and out of the water; `scale` its size.
func _stand(t: RealTerrain, kind: String, x: float, z: float, clear: float, o: Vector3, rng: RandomNumberGenerator,
		scale := Vector3.ONE) -> void:
	if t.cover(x, z) == RealPack.WATER or net.in_flat(x, z, 3.0):
		return
	if not net._near(x, z).is_empty():
		var on := net.locate(x, z, -1, false)
		if not on.is_empty() and (int(on["node"]) >= 0 or absf(float(on["lat"])) < float(on["width"]) * 0.5 + RoadNet.VERGE + clear):
			return
	for row: Array in buildings:
		if Vector2(float(row[0]) - x, float(row[1]) - z).length() < maxf(float(row[2]), float(row[3])) * 0.75 + 2.0:
			return
	var bare := float(net.height.call(x, z))
	if is_nan(bare):
		return
	var y := net.ground_at(x, z, bare) - 0.3   # (a little in: the land's mesh is coarser than the heights)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(scale), Vector3(x, y, z) - o)
	if not trees.has(kind):
		trees[kind] = []
	(trees[kind] as Array).append(xf)


## The roadside of the block's pieces, as the planned road's (AdventureChunk._scenery, RegionKit.roadside): the place's
## marker posts either side every RegionKit.POST_GAP m (none in town, on a bridge or by a junction), rocks and bushes
## out from the verge as the ground's cover has them (into trees), and along farmland a fence, wall or hedge (its posts
## into roadside, its rails and stones into arrays["walls"]). Only on a dressed net (net.dress).
func _roadside(kit: Dictionary) -> void:
	arrays["walls"] = AdventureProps.new_arrays()
	if net.dress.is_empty():
		return
	var t: RealTerrain = net.dress["terrain"]
	var look: Dictionary = net.dress.get("look", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([net.region.hash, "roadside", key])
	var o := anchor()
	var style := str((kit.get("facts", {}) as Dictionary).get("posts", "none"))
	var bounds: Array = look.get("bounds", [])
	var bound_kind := "fence" if bounds.is_empty() else str(bounds[0])
	var tries: Dictionary = look.get("plants", AdventureChunk.REAL_TRIES)
	var bush := "bush"
	for kind: String in tries:
		if kind in AdventureChunk.BUSHES:
			bush = kind
			break
	for p in pieces:
		var pts: PackedVector3Array = p["points"]
		var at: PackedFloat32Array = p["at"]
		var ei := int(p["edge"])
		var e := float(p["width"]) * 0.5
		if pts.size() < 2:
			continue
		# Each point's way along (dir) and to its right (x east, z south: right of (dx, dz) is (-dz, dx)).
		var dirs: Array[Vector2] = []
		for k in pts.size():
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, pts.size() - 1)]
			dirs.append(Vector2(b.x - a.x, b.z - a.z).normalized())
		# Marker posts.
		if style in RegionKit.POST_STYLES:
			for k in range(1, pts.size()):
				if floorf(at[k] / RegionKit.POST_GAP) == floorf(at[k - 1] / RegionKit.POST_GAP) or _town(pts[k], dirs[k], e):
					continue
				var d := dirs[k]
				for side: float in [-1.0, 1.0]:
					var xf := _verge_spot(ei, at[k], pts[k], d, (e + 1.0) * side, atan2(-d.x, -d.y), o)
					if xf != Transform3D():
						_put(roadside, "kit_post_" + style, xf)
		# Rocks and bushes out from the verge, as many to the metre as the planned road has to a chunk.
		var len := at[at.size() - 1] - at[0]
		for kind: String in ["rock", bush]:
			var many := float(tries.get(kind, AdventureChunk.REAL_TRIES.get(kind, 0))) * len / AdventureRoute.CHUNK_LEN
			for n in int(many + rng.randf()):
				var k := rng.randi_range(0, pts.size() - 1)
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var lat := (e + RoadNet.VERGE + 1.0 + pow(rng.randf(), 1.5) * AdventureChunk.REAL_REACH) * side
				var x := pts[k].x - dirs[k].y * lat
				var z := pts[k].z + dirs[k].x * lat
				var c := t.cover(x, z)
				var cover := RealPack.COVER[c] if c >= 0 and c < RealPack.COVER.size() else ""
				var odds: Dictionary = AdventureChunk.ODDS["rocks" if kind == "rock" else "bushes"]
				if rng.randf() < float(odds.get(cover, AdventureChunk.OTHER_ODDS)):
					var size := rng.randf_range(0.7, 1.35)
					_stand(t, kind, x, z, 1.0, o, rng, Vector3.ONE * size)
		_bounds(p, dirs, e, bound_kind, t, o)


## Whether the road at `p` (way `d`, half `e` wide) runs through a built-up place, as RegionKit.built_up has it.
func _town(p: Vector3, d: Vector2, e: float) -> bool:
	var t: RealTerrain = net.dress["terrain"]
	for side: float in [-1.0, 1.0]:
		var c := t.cover(p.x - d.y * (e + 10.0) * side, p.z + d.x * (e + 10.0) * side)
		if c >= 0 and c < RealPack.COVER.size() and RealPack.COVER[c] == "urban":
			return true
	return false


## A post's transform `lat` m to the right of edge `ei`'s point `p` (`s` m along it, way `d`), turned `angle`, on the
## land there, from `o`; an empty one on a bridge, a stop's flat, in a junction or nearer another road.
func _verge_spot(ei: int, s: float, p: Vector3, d: Vector2, lat: float, angle: float, o: Vector3) -> Transform3D:
	if net.bridge_at(ei, s) > 0.0:
		return Transform3D()
	var x := p.x - d.y * lat
	var z := p.z + d.x * lat
	if net.in_flat(x, z, 1.0):
		return Transform3D()
	var on := net.locate(x, z, -1, false)
	if on.is_empty() or int(on["node"]) >= 0 or int(on["edge"]) != ei:
		return Transform3D()
	var bare := float(net.height.call(x, z))
	if is_nan(bare):
		return Transform3D()
	return Transform3D(Basis(Vector3.UP, angle), Vector3(x, net.ground_at(x, z, bare) - 0.05, z) - o)


## Along farmland either side of piece `p` (a good part of the land beside it cropland), a fence (a post every
## RoadNet.STEP with two rails between), a dry-stone wall or a hedge (`kind`, the place's look's "bounds"), as the
## planned road's (AdventureChunk._scenery); broken where a post can't stand (_verge_spot).
func _bounds(p: Dictionary, dirs: Array[Vector2], e: float, kind: String, t: RealTerrain, o: Vector3) -> void:
	var pts: PackedVector3Array = p["points"]
	var at: PackedFloat32Array = p["at"]
	var ei := int(p["edge"])
	var crop := 0
	var total := 0
	for k in range(0, pts.size(), 8):
		for side: float in [-1.0, 1.0]:
			var c := t.cover(pts[k].x - dirs[k].y * (e + 12.0) * side, pts[k].z + dirs[k].x * (e + 12.0) * side)
			total += 1
			if c >= 0 and c < RealPack.COVER.size() and RealPack.COVER[c] == "crop":
				crop += 1
	if total == 0 or float(crop) / total <= 0.25:
		return
	if kind == "wall_hedge":
		kind = "wall" if absi(hash([net.region.hash, "hedge", ei])) % 2 == 0 else "hedge"
	var walls: Dictionary = arrays["walls"]
	var rail := Color(0.45, 0.35, 0.24)
	for side: float in [-1.0, 1.0]:
		var prev := Vector3.INF
		for k in pts.size():
			var d := dirs[k]
			var xf := _verge_spot(ei, at[k], pts[k], d, (e + (4.0 if kind == "fence" else 2.6)) * side, atan2(d.x, d.y), o)
			if xf == Transform3D():
				prev = Vector3.INF
				continue
			if kind == "fence":
				_put(roadside, "post", xf)
			if prev != Vector3.INF:
				match kind:
					"fence":
						for y: float in [0.55, 0.95]:
							AdventureChunk._rail(walls, prev + Vector3.UP * y, xf.origin + Vector3.UP * y, rail)
					"wall":
						var shade := 0.8 + 0.35 * float(absi(hash([ei, k, side])) % 100) / 100.0
						AdventureChunk._wall(walls, prev, xf.origin, 0.95, 0.55, Color(0.42, 0.4, 0.35) * shade)
					"hedge":
						var shade := 0.88 + 0.2 * float(absi(hash([ei, k, side])) % 100) / 100.0
						AdventureChunk._wall(walls, prev, xf.origin, 1.55, 1.1, Color(0.17, 0.3, 0.11) * shade)
			prev = xf.origin


static func _put(d: Dictionary, kind: String, xf: Transform3D) -> void:
	if not d.has(kind):
		d[kind] = []
	(d[kind] as Array).append(xf)


## The region kit (T8's RegionKit) of the place the block's middle is in: how its buildings are built.
func kit_of() -> Dictionary:
	var r := net.region
	var mid := rect.get_center()
	var ll := RealRegion.from_frame(Vector2(r.frame_lat, r.frame_lon), mid.x, mid.y)
	return RegionKit.choose(PlaceProfile.of_cell(RealRegion.cell_of(ll.x, ll.y)))


## Whether building `row` stands on a road or its verge, or in a junction (the map's buildings and its roads are each
## drawn a little off, and a road's own line wins).
func _over_road(row: Array) -> bool:
	var bx := float(row[0])
	var bz := float(row[1])
	var w := float(row[2])
	var d := float(row[3])
	var yaw := float(row[4])
	for c: Vector2 in [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var px := bx + (c.x * w) * cos(yaw) + (c.y * d) * sin(yaw)
		var pz := bz - (c.x * w) * sin(yaw) + (c.y * d) * cos(yaw)
		var on := net.locate(px, pz, -1, false)
		if not on.is_empty() and (int(on["node"]) >= 0 or absf(float(on["lat"])) < float(on["width"]) * 0.5 + RoadNet.VERGE + CLEAR):
			return true
	return false


## Which road (x, z) is on (RoadNet.locate).
func locate(x: float, z: float) -> Dictionary:
	return net.locate(x, z)


# ---------------------------------------------------------------------------- the meshes

## The block's corner in the region frame: its meshes are laid out from here (small numbers however far out it is).
func anchor() -> Vector3:
	return Vector3(rect.position.x, 0.0, rect.position.y)


## Lays the block's meshes and collision out into `arrays`: {deck: {surface: grid arrays}, verge, lines, island,
## buildings (AdventureProps arrays, in the place's region kit), faces: {surface:
## collision triangles}}. The land under them is RealLand's (RoadNet.ground_at).
func _lay_out() -> void:
	arrays = {"deck": {}, "verge": AdventureProps.new_arrays(), "lines": AdventureProps.new_arrays(),
		"island": AdventureProps.new_arrays(), "bridge": AdventureProps.new_arrays(), "faces": {}}
	# The place's region kit (RegionKit, T8): how its buildings are built and its roads marked and signed.
	var mid := rect.get_center()
	var kit := RegionKit.at_frame(net.region.frame_lat, net.region.frame_lon, mid.x, mid.y) if net.region != null else {}
	var marks := RoadMarkings.paint(self, kit)
	_marked = not marks.is_empty()
	for p in pieces:
		_piece_mesh(p)
	for j in junctions:
		_junction_mesh(j)
	_join_caps()
	arrays["signals"] = _signals(kit)
	_roadside(kit)
	var houses := AdventureProps.new_arrays()
	var o := anchor()
	if _marked:
		for k: String in ["v", "n", "c"]:
			arrays["lines"][k].append_array(marks["lines"][k])
			houses[k].append_array(marks["signs"][k])
		# (anything the paint lays on the road is ridden over)
		if not (marks["faces"] as PackedVector3Array).is_empty():
			_faces_of("tarmac")
			arrays["faces"]["tarmac"].append_array(marks["faces"])
		# (place names and the like, stood up as text by the streamer)
		arrays["labels"] = marks.get("labels", [])
	# In the place's region kit, else as the single-line ride's plain buildings.
	for row: Array in buildings:
		var at := Vector3(float(row[0]), float(row[row.size() - 1]), float(row[1])) - o
		var kind := RealPack.BUILDING_KINDS[clampi(int(row[6]), 0, RealPack.BUILDING_KINDS.size() - 1)]
		if kit.is_empty():
			AdventureProps.real_building(houses, at, float(row[2]), float(row[3]), float(row[4]), float(row[5]), kind)
		else:
			RegionBuildings.real_building(houses, at, float(row[2]), float(row[3]), float(row[4]), float(row[5]), kind, kit)
	arrays["buildings"] = houses
	for surf in arrays["deck"]:
		_finish_grid(arrays["deck"][surf])


## An empty indexed mesh's arrays.
static func _grid_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(),
		"i": PackedInt32Array()}


func _deck_of(surf: String) -> Dictionary:
	var d: Dictionary = arrays["deck"]
	if not d.has(surf):
		d[surf] = _grid_arrays()
	return d[surf]


func _faces_of(surf: String) -> PackedVector3Array:
	var f: Dictionary = arrays["faces"]
	if not f.has(surf):
		f[surf] = PackedVector3Array()
	return f[surf]


## Adds triangle (p0, p1, p2) facing up to collision `surf`.
func _face(surf: String, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	_faces_of(surf)
	arrays["faces"][surf].append_array([p0, p1, p2])


## Adds triangle (p0, p1, p2) to AdventureProps arrays `a`, facing up whichever way round it's given.
static func _up(a: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).y >= 0.0:
		AdventureProps._tri(a, p0, p1, p2, col)
	else:
		AdventureProps._tri(a, p0, p2, p1, col)


## Adds triangle (i0, i1, i2) of grid `g` (its vertices `v`, which may not be in it yet) facing up.
static func _grid_tri(g: Dictionary, v: PackedVector3Array, i0: int, i1: int, i2: int) -> void:
	if (v[i1] - v[i0]).cross(v[i2] - v[i0]).y < 0.0:
		var t := i1
		i1 = i2
		i2 = t
	# (Godot's front faces are clockwise: stored the other way round from how the normal is worked out)
	g["i"].append_array([i0, i2, i1])


## Grid `g`'s normals, from its faces.
static func _finish_grid(g: Dictionary) -> void:
	var v: PackedVector3Array = g["v"]
	var idx: PackedInt32Array = g["i"]
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	for k in range(0, idx.size(), 3):
		var n := (v[idx[k + 2]] - v[idx[k]]).cross(v[idx[k + 1]] - v[idx[k]])
		nrm[idx[k]] += n
		nrm[idx[k + 1]] += n
		nrm[idx[k + 2]] += n
	for k in nrm.size():
		nrm[k] = nrm[k].normalized() if nrm[k].length_squared() > 0.0 else Vector3.UP
	g["n"] = nrm


## The way along a piece's points at point `k` (radians clockwise from north).
static func _heading(pts: PackedVector3Array, k: int) -> float:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	return RoadNet._bearing(Vector2(b.x - a.x, b.z - a.z))


## A piece's deck (ACROSS points across, crowned), its verges and skirts, its lines, and their collision.
func _piece_mesh(p: Dictionary) -> void:
	var pts: PackedVector3Array = p["points"]
	var rows := pts.size()
	if rows < 2:
		return
	var surf := str(p["surface"])
	var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
	var verge_col := _verge_colour(surf)
	var e := float(p["width"]) * 0.5
	var o := anchor()
	var g := _deck_of(surf)
	var base := (g["v"] as PackedVector3Array).size()
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var cols := PackedColorArray()
	var s0 := float(p["s0"])
	var s := s0
	var rights := []
	for k in rows:
		if k > 0:
			s += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
		var h := _heading(pts, k)
		var right := Vector3(cos(h), 0.0, sin(h))
		rights.append(right)
		var c := pts[k] - o
		for q in ACROSS:
			var f := float(q) / float(ACROSS - 1) * 2.0 - 1.0
			v.append(c + right * (f * e) + Vector3(0.0, RoadNet.CROWN * (1.0 - f * f), 0.0))
			uv.append(Vector2(f * e / 3.0, s / 3.0))
			cols.append(col)
	var faces := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in rows - 1:
		for q in ACROSS - 1:
			var bl := k * ACROSS + q
			for tri: Array in [[bl, bl + ACROSS, bl + ACROSS + 1], [bl, bl + ACROSS + 1, bl + 1]]:
				var i0: int = tri[0]
				var i1: int = tri[1]
				var i2: int = tri[2]
				if (v[i1] - v[i0]).cross(v[i2] - v[i0]).y < 0.0:
					var t := i1
					i1 = i2
					i2 = t
				idx.append_array([base + i0, base + i2, base + i1])
				faces.append_array([v[i0], v[i1], v[i2]])
	g["v"].append_array(v)
	g["uv"].append_array(uv)
	g["c"].append_array(cols)
	g["i"].append_array(idx)
	_faces_of(surf)
	arrays["faces"][surf].append_array(faces)
	# The verges, level with the road's edge, then the skirt down under the land: none where they'd lie on another road,
	# nor out on a bridge (its parapets instead).
	var ei := int(p["edge"])
	var ws := PackedFloat32Array()
	for a: float in p["at"]:
		ws.append(net.bridge_at(ei, a))
	var keep := []
	for k in rows:
		var row := []
		for side: float in [-1.0, 1.0]:
			row.append(not _on_other(pts[k] + rights[k] * side * (e + RoadNet.VERGE), ei))
		keep.append(row)
	for k in rows - 1:
		for q in 2:
			if not keep[k][q] or not keep[k + 1][q] or (ws[k] > 0.0 and ws[k + 1] > 0.0):
				continue
			var side := -1.0 if q == 0 else 1.0
			_verge_strip(pts[k] - o + rights[k] * side * e, pts[k + 1] - o + rights[k + 1] * side * e, rights[k] * side,
				rights[k + 1] * side, verge_col)
	_bridge_sides(pts, rights, e, ws, surf)
	if surf == "tarmac" and not _marked:
		_piece_lines(p, pts, rights, e, s0)


## A piece's bridges, where it's out on one (`ws`, RoadNet.bridge_at at each of its points `pts`): a stone parapet
## each side, its outside on down to the deck's underside BRIDGE_DEPTH under the road, the underside, and a pier every
## PIER_GAP or so where the land is well below. The parapets' insides are walls (collision `surf`, the road's).
func _bridge_sides(pts: PackedVector3Array, rights: Array, e: float, ws: PackedFloat32Array, surf: String) -> void:
	var arr: Dictionary = arrays["bridge"]
	var o := anchor()
	var stone: Color = AdventureChunk.BRIDGE_STONE
	var top := Vector3.UP * AdventureChunk.PARAPET
	var dn := Vector3.DOWN * RoadNet.BRIDGE_DEPTH
	var since := 0.0
	for k in pts.size() - 1:
		if ws[k] <= 0.0 or ws[k + 1] <= 0.0:
			since = 0.0
			continue
		var c0 := pts[k] - o
		var c1 := pts[k + 1] - o
		var r0: Vector3 = rights[k]
		var r1: Vector3 = rights[k + 1]
		for side: float in [-1.0, 1.0]:
			var in0 := c0 + r0 * side * e
			var in1 := c1 + r1 * side * e
			var out0 := c0 + r0 * side * (e + PARAPET_W)
			var out1 := c1 + r1 * side * (e + PARAPET_W)
			AdventureProps._quad(arr, in0, in1, in1 + top, in0 + top, stone.darkened(0.06))
			AdventureProps._quad(arr, in0 + top, in1 + top, out1 + top, out0 + top, stone.lightened(0.08))
			AdventureProps._quad(arr, out0 + top, out1 + top, out1 + dn, out0 + dn, stone)
			_face(surf, in0, in1, in1 + top)
			_face(surf, in0, in1 + top, in0 + top)
		AdventureProps._quad(arr, c0 - r0 * (e + PARAPET_W) + dn, c0 + r0 * (e + PARAPET_W) + dn,
			c1 + r1 * (e + PARAPET_W) + dn, c1 - r1 * (e + PARAPET_W) + dn, stone.darkened(0.25))
		since += Vector2(c1.x - c0.x, c1.z - c0.z).length()
		if since < AdventureChunk.PIER_GAP or ws[k] < 1.0:
			continue
		var ground := float(net.height.call(pts[k].x, pts[k].z))
		var bottom := pts[k].y + dn.y
		if bottom - ground > PIER_MIN:
			since = 0.0
			var xf := Transform3D(Basis(Vector3.UP, -_heading(pts, k)), Vector3(c0.x, ground - o.y - 0.5, c0.z))
			AdventureProps.box(arr, xf, Vector3(e * 2.0 + 0.8, bottom - ground + 0.5, 1.6), stone.darkened(0.12), false)


## The verge's colour beside a road of surface `surf`: the place's own, as the land beside it is.
func _verge_colour(surf: String) -> Color:
	var col: Color = AdventureSurface.VERGE_COLOR.get(surf, AdventureSurface.VERGE_COLOR["tarmac"])
	var look: Dictionary = net.dress.get("look", {})
	if look.has("verge"):
		col = (look["verge"] as Dictionary).get(surf, col)
	return col


## A stretch of verge out from the road's edge a to b (block space), out along `ra` and `rb`, level with the edge, then
## its skirt down under the land; and its collision.
func _verge_strip(a0: Vector3, b0: Vector3, ra: Vector3, rb: Vector3, col: Color) -> void:
	var verge: Dictionary = arrays["verge"]
	var a1 := a0 + ra * RoadNet.VERGE + Vector3(0.0, -0.03, 0.0)
	var b1 := b0 + rb * RoadNet.VERGE + Vector3(0.0, -0.03, 0.0)
	var a2 := a0 + ra * (RoadNet.VERGE + SKIRT_OUT) + Vector3(0.0, -SKIRT_DOWN, 0.0)
	var b2 := b0 + rb * (RoadNet.VERGE + SKIRT_OUT) + Vector3(0.0, -SKIRT_DOWN, 0.0)
	_up(verge, a0, b0, b1, col)
	_up(verge, a0, b1, a1, col)
	_up(verge, a1, b1, b2, col.darkened(0.1))
	_up(verge, a1, b2, a2, col.darkened(0.1))
	_face("grass", a0, b0, b1)
	_face("grass", a0, b1, a1)


## Whether `p` (region frame) is on a road other than edge `ei` (any, for -1): its carriageway or a junction's surface,
## where no verge is laid. Not one that crosses over or under it (OVER or more above or below).
func _on_other(p: Vector3, ei: int) -> bool:
	var on := net.locate(p.x, p.z, ei)
	return not on.is_empty() and bool(on["on_road"]) and (int(on["edge"]) != ei or int(on["node"]) >= 0) \
		and absf(float(on["y"]) - p.y) < OVER


## A tarmac piece's edge lines and centre dashes.
func _piece_lines(p: Dictionary, pts: PackedVector3Array, rights: Array, e: float, s0: float) -> void:
	var lines: Dictionary = arrays["lines"]
	var o := anchor()
	var white := Color(0.88, 0.88, 0.84)
	var lift := Vector3(0.0, LINE_LIFT, 0.0)
	var offs := []
	if e * 2.0 >= EDGE_LINE_MIN:
		offs.append(-(e - LINE_IN))
		offs.append(e - LINE_IN)
	var s := s0
	for k in pts.size() - 1:
		var step := Vector2(pts[k + 1].x - pts[k].x, pts[k + 1].z - pts[k].z).length()
		var a := pts[k] - o + lift
		var b := pts[k + 1] - o + lift
		var ra: Vector3 = rights[k]
		var rb: Vector3 = rights[k + 1]
		for lat: float in offs:
			var f := lat / maxf(e, 0.1)
			var crown := Vector3(0.0, RoadNet.CROWN * (1.0 - f * f), 0.0)
			_up(lines, a + ra * (lat - LINE_W * 0.5) + crown, b + rb * (lat - LINE_W * 0.5) + crown, b + rb * (lat + LINE_W * 0.5) + crown, white)
			_up(lines, a + ra * (lat - LINE_W * 0.5) + crown, b + rb * (lat + LINE_W * 0.5) + crown, a + ra * (lat + LINE_W * 0.5) + crown, white)
		if int(p["lanes"]) == 2:
			# Dashes by distance along the edge, so they carry on across a block's seam.
			var d0 := fposmod(s, DASH + GAP)
			if d0 < DASH:
				var len := minf(DASH - d0, step)
				var t := len / maxf(step, 0.01)
				var bb := a.lerp(b, t)
				var rr: Vector3 = ra.lerp(rb, t)
				var c := Vector3(0.0, RoadNet.CROWN, 0.0)
				_up(lines, a - ra * LINE_W * 0.5 + c, bb - rr * LINE_W * 0.5 + c, bb + rr * LINE_W * 0.5 + c, white)
				_up(lines, a - ra * LINE_W * 0.5 + c, bb + rr * LINE_W * 0.5 + c, a + ra * LINE_W * 0.5 + c, white)
		s += step


## A junction's surface: a fan from its middle over its outline (a roundabout: its island, and the mouths of the roads
## onto its ring), at the heights of the roads meeting it.
func _junction_mesh(j: Dictionary) -> void:
	var o := anchor()
	var arms: Array = j["arms"]
	var surf := "tarmac"
	for a in arms:
		if net.region.surface_of(int(a["edge"])) != "tarmac":
			surf = net.region.surface_of(int(a["edge"]))
		else:
			surf = "tarmac"
			break
	var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
	var g := _deck_of(surf)
	var centre: Vector3 = j["pos"]
	if j["kind"] in ["roundabout", "mini"]:
		for a in arms:
			var node := int(a["node"])
			var np := net.region.node_pos[node]
			var at := Vector3(np.x, net.node_y(node), np.y)
			var m: Vector3 = a["mouth"]
			var out := RoadNet._bearing(Vector2(m.x - at.x, m.z - at.z))
			var right := Vector3(cos(out), 0.0, sin(out)) * float(a["width"]) * 0.5
			# (from the ring's middle line, where the arm's own node is: no further in, or it pokes into the island)
			_fan(g, surf, col, at - o, [at - right * 1.6 - o, m - right - o, m + right - o, at + right * 1.6 - o])
		_island(j)
		return
	var full := net.junction_of(int(j["node"]))
	var outline: PackedVector2Array = full["outline"]
	var heights: PackedFloat32Array = full["outline_y"]
	var kerb: PackedByteArray = full["kerb"]
	var pts := []
	for k in outline.size():
		pts.append(Vector3(outline[k].x, heights[k], outline[k].y) - o)
	var closed: bool = j["kind"] != "end"
	_drape(g, surf, col, j, centre - o, pts, closed)
	# Its verges, round the kerbs between the arms (the arms' own run on from their mouths).
	var verge_col := _verge_colour(surf)
	var count := pts.size() if closed else pts.size() - 1
	var mid := centre - o
	# Each kerb's way out, and each point's (between the kerbs either side of it), so the verge bends round unbroken.
	var outs := []
	for k in count:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % pts.size()]
		var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized()
		if side.dot((a + b) * 0.5 - mid) < 0.0:
			side = -side
		outs.append(side)
	var at := []
	var keep := []
	for k in pts.size():
		var n := Vector3.ZERO
		for q: int in [k - 1, k]:
			var w := posmod(q, pts.size())
			if (closed or (q >= 0 and q < count)) and w < count and kerb[w] == 1:
				n += outs[w]
		n = n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO
		if not closed:
			n = Vector3(pts[k].x - mid.x, 0.0, pts[k].z - mid.z).normalized()   # (a dead end's: round its half circle)
		at.append(n)
		keep.append(n != Vector3.ZERO and not _on_other(pts[k] + o + n * RoadNet.VERGE, -1))
	for k in count:
		var k1 := (k + 1) % pts.size()
		if kerb[k] == 0 or not keep[k] or not keep[k1]:
			continue
		_verge_strip(pts[k], pts[k1], at[k], at[k1], verge_col)


## A fan of triangles from `c` round `pts` (closed if `closed`), into grid `g` and collision `surf`.
func _fan(g: Dictionary, surf: String, col: Color, c: Vector3, pts: Array, closed := false) -> void:
	var base := (g["v"] as PackedVector3Array).size()
	var v := PackedVector3Array([c])
	for p: Vector3 in pts:
		v.append(p)
	for k in v.size():
		g["uv"].append(Vector2(v[k].x, v[k].z) / 3.0)
		g["c"].append(col)
	var count := pts.size() if closed else pts.size() - 1
	for k in count:
		var i1 := 1 + k
		var i2 := 1 + (k + 1) % pts.size()
		if (v[i1] - v[0]).cross(v[i2] - v[0]).y < 0.0:
			var t := i1
			i1 = i2
			i2 = t
		g["i"].append_array([base, base + i2, base + i1])
		_face(surf, v[0], v[i1], v[i2])
	g["v"].append_array(v)


## A junction's surface: rings out from its middle `c` to its outline `pts` (block space), each point on its through road's
## height across from it (RoadNet.surface_y), easing to the outline's own heights (the arms' mouths) at its edge, so the
## through road rides on through it as it does either side and a side road comes into it without a kink.
func _drape(g: Dictionary, surf: String, col: Color, j: Dictionary, c: Vector3, pts: Array, closed := false) -> void:
	var o := anchor()
	var node := int(j["node"])
	var base := (g["v"] as PackedVector3Array).size()
	var v := PackedVector3Array([c])
	var rim := []   # each outline point's height less its through road's there
	for p: Vector3 in pts:
		rim.append(p.y - net.surface_y(node, Vector2(p.x + o.x, p.z + o.z)))
	for r in range(1, DRAPE_RINGS + 1):
		var f := float(r) / DRAPE_RINGS
		for k in pts.size():
			var q: Vector3 = c.lerp(pts[k], f)
			q.y = net.surface_y(node, Vector2(q.x + o.x, q.z + o.z)) + float(rim[k]) * f
			v.append(q)
	for k in v.size():
		g["uv"].append(Vector2(v[k].x, v[k].z) / 3.0)
		g["c"].append(col)
	var n := pts.size()
	var count := n if closed else n - 1
	var tri := func(i0: int, i1: int, i2: int) -> void:
		if (v[i1] - v[i0]).cross(v[i2] - v[i0]).y < 0.0:
			var t := i1
			i1 = i2
			i2 = t
		g["i"].append_array([base + i0, base + i2, base + i1])
		_face(surf, v[i0], v[i1], v[i2])
	for k in count:
		var k1 := (k + 1) % n
		tri.call(0, 1 + k, 1 + k1)
		for r in range(1, DRAPE_RINGS):
			var a := 1 + (r - 1) * n
			var b := 1 + r * n
			tri.call(a + k, b + k, b + k1)
			tri.call(a + k, b + k1, a + k1)
	g["v"].append_array(v)


## A roundabout's island: a kerbed disc of grass a little above the ring.
func _island(j: Dictionary) -> void:
	var r := float(j["island"])
	if r <= 0.5:
		return
	var a: Dictionary = arrays["island"]
	var c: Vector3 = j["pos"] - anchor()
	var n := 24
	for k in n:
		var t0 := TAU * k / n
		var t1 := TAU * (k + 1) / n
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		var top := Vector3(0.0, ISLAND_H, 0.0)
		var low := Vector3(0.0, -0.1, 0.0)
		# Grass in from the kerb, then (on an island big enough) a mound rising gently to its middle, as the planned
		# road's roundabouts have (the ring just inside the kerb is kept flat: the chevron boards stand on it).
		var flat := r - MOUND_IN if r > MOUND_FROM else 0.0
		_up(a, c + d0 * flat + top, c + d0 * (r - ISLAND_KERB) + top, c + d1 * (r - ISLAND_KERB) + top, ISLAND_GRASS)
		_up(a, c + d0 * flat + top, c + d1 * (r - ISLAND_KERB) + top, c + d1 * flat + top, ISLAND_GRASS)
		for ring in 3:
			var r0 := flat * (1.0 - ring / 3.0)
			var r1 := flat * (1.0 - (ring + 1) / 3.0)
			var y0 := Vector3.UP * (ISLAND_H + MOUND_H * (ring / 3.0))
			var y1 := Vector3.UP * (ISLAND_H + MOUND_H * ((ring + 1) / 3.0))
			_up(a, c + d0 * r0 + y0, c + d1 * r0 + y0, c + d1 * r1 + y1, ISLAND_GRASS.darkened(0.06 * ring))
			if ring < 2:
				_up(a, c + d0 * r0 + y0, c + d1 * r1 + y1, c + d0 * r1 + y1, ISLAND_GRASS.darkened(0.06 * ring))
		_up(a, c + d0 * (r - ISLAND_KERB) + top, c + d0 * r + top, c + d1 * r + top, KERB)
		_up(a, c + d0 * (r - ISLAND_KERB) + top, c + d1 * r + top, c + d1 * (r - ISLAND_KERB) + top, KERB)
		# The kerb's face, out towards the ring.
		AdventureProps._quad(a, c + d0 * r + low, c + d1 * r + low, c + d1 * r + top, c + d0 * r + top, KERB)
		_face("grass", c + top, c + d0 * r + top, c + d1 * r + top)
	# Shrubs on the mound.
	if r > MOUND_FROM:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["island", int(j["node"])])
		for k in SHRUBS:
			var ang := rng.randf() * TAU
			var at := rng.randf_range(0.3, r - MOUND_IN - 0.8)
			var rise := ISLAND_H + MOUND_H * (1.0 - at / (r - MOUND_IN)) - 0.1
			AdventureProps.blob(a, c + Vector3(sin(ang) * at, rise, -cos(ang) * at), Vector3(1.0, 0.8, 1.0) * rng.randf_range(0.6, 1.1),
				SHRUB_COLOURS[k % SHRUB_COLOURS.size()], rng.randi())


## The traffic lights at the block's crossroads in town (where the ground's built up, as the planned road's crossroads
## have them: AdventureJunctions.plan_real): [{node, green: [the through road's green, the side roads'] (s), phase (s),
## heads: [[Transform3D (block space, +z towards the traffic it stops), role ("main" or "side")], ...]}]: a head at each
## road's mouth on the kerb its traffic keeps to (the place's side of the road, `kit`). The streamer stands them up
## (AdventureJunctions.Signals, lit by the host's clock).
func _signals(kit: Dictionary) -> Array:
	var out := []
	var t: RealTerrain = net.dress.get("terrain")
	if t == null:
		return out
	var urban := RealPack.COVER.find("urban")
	var left := str((kit.get("facts", {}) as Dictionary).get("drive", "right")) == "left"
	var o := anchor()
	for j in junctions:
		if j["kind"] != "cross":
			continue
		var pos: Vector3 = j["pos"]
		if t.cover(pos.x, pos.z) != urban:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["lights", int(j["node"])])
		var heads := []
		for arm: Dictionary in j["arms"]:
			var m: Vector3 = arm["mouth"]
			var u := Vector3(m.x - pos.x, 0.0, m.z - pos.z).normalized()
			# (the way in runs back along -u; its kerb side is right of that, or left where the place drives on the left)
			var right_in := Vector3(u.z, 0.0, -u.x)
			var at := m + right_in * (float(arm["width"]) * 0.5 + 0.7) * (-1.0 if left else 1.0) - o
			heads.append([Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), at), "main" if bool(arm["main"]) else "side"])
		out.append({"node": int(j["node"]), "heads": heads, "phase": rng.randf() * 60.0,
			"green": [rng.randf_range(AdventureJunctions.MAIN_GREEN[0], AdventureJunctions.MAIN_GREEN[1]),
				rng.randf_range(AdventureJunctions.SIDE_GREEN[0], AdventureJunctions.SIDE_GREEN[1])]})
	return out


## Where two roads join end to end (no junction) at an angle or with different widths, a disc of road at the node
## fills the wedge between their ends.
func _join_caps() -> void:
	var r := net.region
	var o := anchor()
	for node in net.nodes_in(key):
		if r.adjacent[node].size() != 2 or not net.junction_of(node).is_empty():
			continue
		var e0 := r.adjacent[node][0]
		var e1 := r.adjacent[node][1]
		var w := maxf(net.width_of(e0), net.width_of(e1))
		var h0 := net.heading_at(e0, 0.0 if r.edge_a[e0] == node else net.length_of(e0))
		var h1 := net.heading_at(e1, 0.0 if r.edge_a[e1] == node else net.length_of(e1))
		var turn := absf(PI - RoadNet._angle_between(h0, h1)) if (r.edge_a[e0] == node) != (r.edge_a[e1] == node) else RoadNet._angle_between(h0, h1)
		if turn < deg_to_rad(4.0) and is_equal_approx(net.width_of(e0), net.width_of(e1)):
			continue
		var surf := r.surface_of(e0)
		var col: Color = AdventureSurface.ROAD_COLOR.get(surf, AdventureSurface.ROAD_COLOR["tarmac"])
		var at := net.point_at(e0, 0.0 if r.edge_a[e0] == node else net.length_of(e0))   # (the join, on the smoothed line)
		var c := Vector3(at.x, net.node_y(node), at.y)
		var ring := []
		for k in 12:
			var t := TAU * k / 12.0
			ring.append(c + Vector3(sin(t), 0.0, -cos(t)) * w * 0.5 - o)
		_fan(_deck_of(surf), surf, col, c - o, ring, true)
