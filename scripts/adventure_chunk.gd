class_name AdventureChunk
extends RefCounted
## One stretch of an adventure road (AdventureRoute.CHUNK_KNOTS knots, 128 m): its road, white
## lines, verges and land out to the skyline, the trees, rocks, fences, buildings and posts on it,
## and its collision. build() lays it all out as plain arrays from the route alone (so it runs on
## a worker thread, and every player gets the same chunk); commit() turns that into nodes on the
## main thread. Everything is relative to the chunk's first knot (its anchor), so the numbers
## stay small however far along the route it is.

## The land either side, metres out past the road's edge (the first few follow the road's half
## width; the rest are from the centre line). Out to column COLLIDE_COLS it's solid. Past the
## skyline ridge (400 m) it runs on and down over the far side, under the far ground, so the
## land has no edge to see past (it used to stop at 400 m, often up on a ridge 100 m or more
## above the far ground, and you could see through under it).
const LAND_OUT := [0.0, 0.9, 2.5, 6.0, 12.0, 20.0, 30.0, 46.0, 70.0, 110.0, 170.0, 260.0, 400.0, 640.0, 1000.0]
## Where the land's far side ends up: this far under the road's base height, below the far
## ground (AdventureWorld's FarGround, 70 m under it), or under the sea on a coastal ride; at
## least this far out past the column before it (m), and this far for each metre it goes down
## (as far out as down: steep, but not a wall).
const FAR_SIDE_DROP := 160.0
## The chunk's land runs out only this many of LAND_OUT's columns (to 110 m); the land beyond is RealLand's (the garage
## map's near, middle and far blocks), the last column here running on down under it.
const REAL_LAND_COLS := 10


## How many columns of land a chunk of `route` has each side of the road.
static func land_cols(_route: AdventureRoute) -> int:
	return REAL_LAND_COLS
const FAR_SIDE_RUN := 30.0
const FAR_SIDE_SLOPE := 1.0
const COLLIDE_COLS := 8
## From this column out (past the skyline ridge) the land needn't look for other stretches of
## the road along the way: route.land_reach keeps it well short of them.
const SHARED_COL := 13
const CROWN := 0.04
## A bridge's stone, its parapets' height over the deck (m), and how far apart its piers are at most (m).
const BRIDGE_STONE := Color(0.62, 0.58, 0.5)
const PARAPET := 0.95
const PIER_GAP := 14.0
## How far a chunk's road collision runs on past each end, under the next chunk's (m, see _overlapped).
const SEAM_OVERLAP := 0.05
## The most vertices of real buildings a chunk draws (a town's busiest stretch would be several times this).
const BUILDING_VERTS := 18000
## How far each kind of thing is drawn (m, times the draw distance setting).
const RANGES := {"pine": 650.0, "snow_pine": 650.0, "tree": 650.0, "bush": 260.0, "dry_bush": 260.0, "rock": 320.0,
	"post": 220.0, "snow_pole": 260.0, "km_post": 200.0, "buildings": 1100.0, "lines": 380.0,
	"cactus": 420.0, "red_rock": 320.0, "gorse": 260.0, "dune_grass": 200.0, "oak": 650.0, "sheep": 220.0,
	"mesa": 3400.0, "crag": 2400.0, "lighthouse": 2600.0, "walls": 420.0,
	"bridge": 1600.0, "birch": 650.0, "autumn_tree": 650.0, "olive": 500.0, "cypress": 650.0, "palm": 650.0,
	"acacia": 650.0, "jungle_tree": 650.0, "agave": 220.0, "tussock": 200.0}
## Small things that may stand close to the road's edge (the rest keep 6 m off it).
const NEAR_KINDS := ["rock", "bush", "dry_bush", "red_rock", "gorse", "dune_grass", "sheep", "agave", "tussock"]
## The far scenery (AdventureTheme "far"): how far out from the road it stands (m), and how
## clear of any road its middle must be.
const FAR_PLACE := {"mesa": [170.0, 380.0, 80.0], "crag": [70.0, 260.0, 40.0]}
## Scenery per chunk on each surface's land: kind -> how many (a theme may have its own: AdventureTheme "scenery").
const SCENERY := {
	"tarmac": {"tree": 16, "bush": 10, "pine": 3, "rock": 2},
	"gravel": {"pine": 28, "tree": 4, "bush": 5, "rock": 10},
	"sand": {"dry_bush": 14, "rock": 16},
	"snow": {"snow_pine": 24, "rock": 7},
}
const BUILDING_ODDS := {"tarmac": 0.2, "gravel": 0.07, "sand": 0.06, "snow": 0.05}
const FENCE_ODDS := {"tarmac": 0.55, "gravel": 0.3, "sand": 0.0, "snow": 0.0}
## A beach's sand, along a coastal sea.
const BEACH := Color(0.86, 0.8, 0.62)
## On a real road the land is tinted by what covers it (RealPack.COVER): colour and how far it takes over the theme's
## (under a river or a lake, its muddy bed: RealLand draws the water over it). A place's look has its own (PlaceLook).
const COVER_TINT := {
	"forest": [Color(0.09, 0.22, 0.1), 0.85], "crop": [Color(0.62, 0.66, 0.3), 0.7], "shrub": [Color(0.34, 0.4, 0.2), 0.55],
	"urban": [Color(0.52, 0.5, 0.46), 0.65], "sand": [BEACH, 0.8], "barren": [Color(0.5, 0.45, 0.38), 0.6],
	"rock": [Color(0.45, 0.43, 0.4), 0.8], "water": [Color(0.24, 0.25, 0.19), 0.8], "wetland": [Color(0.3, 0.4, 0.28), 0.6],
}
## How much of each thing's scenery a real road's cover takes (0 to 1), by what covers the ground: trees, bushes,
## rocks, and anything else (sheep and the like). A cover left out takes OTHER_ODDS of it.
const TREES := ["tree", "pine", "oak", "snow_pine", "birch", "autumn_tree", "olive", "cypress", "palm", "acacia", "jungle_tree"]
const BUSHES := ["bush", "dry_bush", "gorse", "agave", "tussock", "cactus"]
const ODDS := {
	"trees": {"forest": 1.0, "shrub": 0.35, "wetland": 0.3, "grass": 0.12, "urban": 0.15, "crop": 0.03, "barren": 0.05, "sand": 0.03, "rock": 0.0, "water": 0.0},
	"bushes": {"forest": 0.6, "shrub": 1.0, "wetland": 0.5, "grass": 0.5, "urban": 0.1, "crop": 0.1, "barren": 0.3, "sand": 0.3, "rock": 0.1, "water": 0.0},
	"rocks": {"rock": 1.0, "barren": 1.0, "shrub": 0.4, "sand": 0.3, "grass": 0.3, "forest": 0.2, "crop": 0.02, "urban": 0.0, "water": 0.0},
	"other": {"grass": 1.0, "crop": 0.6, "shrub": 0.4, "forest": 0.15, "urban": 0.05, "barren": 0.1, "water": 0.0},
}
const OTHER_ODDS := 0.3
## What a real road tries to scatter per chunk, then thinned to the cover (the theme's own counts are for made-up
## country): enough that forest is dense, and open country keeps only a few. A place's look has its own kit of them
## (PlaceLook "plants").
const REAL_TRIES := {"tree": 240, "pine": 70, "bush": 70, "rock": 24}
## How far out from a real road scenery is scattered (m): woods run well up the hillsides.
const REAL_REACH := 260.0
## On a real road whose cells have their trees (RealTerrain.trees_at, tools/tree_bake.py) the trees stand where the
## canopy map has them: a look every CANOPY_STEP m along the road and out from it to REAL_REACH, and as many trees
## planted round each look as the share of it under trees and the size of their crowns say (CANOPY_MOST at most),
## each as tall as the canopy there or a little under.
const CANOPY_STEP := 16.0
const CANOPY_MOST := 2
## The canopy's height step (m: tools/tree_bake.py HEIGHT_STEP).
const CANOPY_HEIGHT_STEP := 2.0
## Past this far out (m) only this share of the trees are planted: the far woods look as thick with fewer.
const CANOPY_THIN := [70.0, 0.4]
## Each tree's height and its crown's width (m) as AdventureProps draws it, to scale it to the real tree's.
const TREE_SIZE := {"tree": [6.6, 5.2], "oak": [8.1, 7.6], "pine": [8.0, 4.4], "snow_pine": [8.0, 4.4], "birch": [8.0, 3.2],
	"autumn_tree": [6.6, 5.2], "olive": [4.1, 4.4], "cypress": [8.8, 1.9], "palm": [9.0, 5.6], "acacia": [4.8, 6.8],
	"jungle_tree": [9.6, 7.2]}
## A real tree's crown is this wide for its height (m per m, and m), a broadleaf's and a conifer's.
const CROWN_BROAD := [0.35, 3.0]
const CROWN_NEEDLE := [0.22, 2.0]
## Where the map doesn't say what leaves a wood has (RealPack.LEAVES 0), how likely it is a conifer's: as a rule, in
## the far north, a thick wood of tall trees (as often as not a plantation), high up and in the mountains, more so.
const NEEDLE_ODDS := {"base": 0.2, "north": 0.6, "north_lat": 58.0, "plantation": 0.4, "high": 0.2, "high_y": 350.0, "alpine": 0.4}
## The ground a guess holds over (m): a wood is one kind across, not tree by tree.
const NEEDLE_PATCH := 128.0


## Lays out chunk `c` of `route`. Safe to run on a worker thread: it only reads the route.
static func build(route: AdventureRoute, c: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var n := route.knot_count()
	var i0 := c * AdventureRoute.CHUNK_KNOTS
	var i1 := mini(i0 + AdventureRoute.CHUNK_KNOTS, n - 1)
	var ax := route.px[i0]
	var az := route.pz[i0]
	var surf := route.chunk_surface[clampi(c, 0, route.chunk_surface.size() - 1)]
	var out := {"c": c, "i0": i0, "i1": i1, "ax": ax, "az": az, "surface": surf,
		"land": AdventureSurface.LAND.get(surf, "grass")}
	var rows := i1 - i0 + 1
	# The road: five points across (edges, quarter lines, the crown).
	var road_v := PackedVector3Array()
	var road_uv := PackedVector2Array()
	var road_c := PackedColorArray()
	var rc: Color = route.look["road"][surf]
	for i in range(i0, i1 + 1):
		var h := route.hd[i]
		var rx := cos(h)
		var rz := sin(h)
		var e := route.width[i] * 0.5
		var cx := route.px[i] - ax
		var cz := route.pz[i] - az
		for k in 5:
			var f := (k - 2) / 2.0
			var lat := f * e
			var y := route.ph[i] + CROWN * (1.0 - f * f)
			road_v.append(Vector3(cx + rx * lat, y, cz + rz * lat))
			road_uv.append(Vector2(f * e / 3.0, i * AdventureRoute.STEP / 3.0))
			var wear := 1.0 - 0.06 * (1.0 - absf(absf(f) - 0.5) * 2.0) if surf == "tarmac" else 1.0
			road_c.append(rc * wear)
	out["road"] = _grid(road_v, rows, 5, road_uv, road_c)
	out["road_faces"] = _faces(_overlapped(road_v, rows, 5), rows, 5, 5)
	out["bridge"] = _bridge(route, i0, i1, ax, az)
	# The land either side, out to the skyline: left from its far edge in, right from the verge out.
	var cols := land_cols(route)
	var land := {}
	for side: int in [-1, 1]:
		var v := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		for i in range(i0, i1 + 1):
			var h := route.hd[i]
			var rx := cos(h)
			var rz := sin(h)
			var e := route.width[i] * 0.5
			var max_in := route.land_reach(i, side)
			var row_v := []
			var row_c := []
			var prev := e
			var prev_y := route.ph[i]
			var stopped := false   # past another stretch of the road: the rest of the row stays put
			var floor_y := AdventureTheme.SEA_Y - 10.0 if route.sea else route.base[i] - FAR_SIDE_DROP
			for k in cols:
				var out_k: float = LAND_OUT[k]
				var lat := (e + out_k) if k < 6 else maxf(out_k, e + out_k * 0.5)
				if k > 0:
					lat = maxf(lat, prev + 0.3)
				if k > 2:
					lat = minf(lat, maxf(max_in, prev + 0.05))
				if k >= 7 and k < SHARED_COL and not stopped:
					# Would the land out to here reach over a bend that doubles back? Look along the way.
					# (Further out, land_reach has already stopped it short of any other stretch.)
					var steps := maxi(1, int((lat - prev) / 40.0))
					for q in range(1, steps + 1):
						var at := lerpf(prev, lat, float(q) / steps)
						if route.other_road_near(i, route.px[i] + rx * at * side, route.pz[i] + rz * at * side, 30.0, at):
							stopped = true
							break
				if stopped:
					lat = prev + 0.05 * k
				var inner := prev   # the column before's reach
				var run := maxf(FAR_SIDE_RUN, (prev_y - floor_y) * FAR_SIDE_SLOPE)
				if k == cols - 1:
					# Out far enough to go down without a wall, but never on into the middle of a
					# bend, where the rows close in and would fold over each other.
					lat = maxf(lat, minf(prev + run, route.inside_reach(i, side) * 0.95))
				prev = lat
				var wx := route.px[i] + rx * lat * side
				var wz := route.pz[i] + rz * lat * side
				var y := route.land_height(i, lat * side, wx, wz)
				if k == cols - 1:
					# Down the far side, every row: a row cut short (by a bend doubling back,
					# another stretch of the road over the way) goes down from where it stops,
					# under the other stretch's land, rather than ending in the air beside rows
					# that ran on out and down. Those ragged ends, row by row, were long triangles
					# reaching up into the sky and down to the far ground ("lots of graphics
					# glitches on adventure - long triangles"), with the sky showing between.
					# (Where it closes in on a bend's middle, as far down as it got out; and never up,
					# where it's gone further out than it would have, onto a mountainside.)
					y = minf(y, prev_y)
					y = lerpf(y, minf(y, floor_y), clampf((lat - inner) / run, 0.0, 1.0))
				prev_y = y
				row_v.append(Vector3(wx - ax, y, wz - az))
				row_c.append(_land_color(route, i, k, lat, wx, wz, y))
			if side < 0:
				row_v.reverse()
				row_c.reverse()
			for k in cols:
				v.append(row_v[k])
				col.append(row_c[k])
				uv.append(Vector2(row_v[k].x, row_v[k].z) * 0.1)
		land[side] = {"v": v, "c": col}
		out["land_%d" % side] = _grid(v, rows, cols, uv, col)
		# Solid out to COLLIDE_COLS: the inner columns (the right's first, the left's last).
		out["land_faces_%d" % side] = _faces(v, rows, cols, COLLIDE_COLS + 1, side < 0)
	out["lines"] = _lines(route, i0, i1, ax, az, surf)
	# The side roads and the paint at the junctions, and any tunnel through here.
	AdventureJunctions.chunk_parts(route, i0, i1, ax, az, land, out)
	AdventureTunnels.build(route, i0, i1, ax, az, land, out)
	_scenery(route, c, i0, i1, ax, az, surf, out)
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## The land's colour at a vertex: its surface's (blended across a change of surface), patched
## by noise, the verge's beside the road (none over a tunnel), and greyer where it's steep.
static func _land_color(route: AdventureRoute, i: int, k: int, lat: float, x: float, z: float, y: float) -> Color:
	var s := i * AdventureRoute.STEP
	var here := route.surface_at_s(s)
	var lands: Dictionary = route.look["land"]
	var patches: Dictionary = route.look["patch"]
	var col: Color = lands[here]
	var patch: Color = patches[here]
	for d: float in [-64.0, 64.0]:
		var other := route.surface_at_s(s + d)
		if other != here:
			col = col.lerp(lands[other], 0.35)
			patch = patch.lerp(patches[other], 0.35)
	var n := route.patches.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	col = col.lerp(patch, smoothstep(0.35, 0.75, n))
	if route.in_tunnel(i):
		k = maxi(k, 3)   # (over a tunnel it's the hillside right in from the road's edge: no verge)
	if k <= 1:
		col = route.look["verge"][here]
	elif k == 2:
		col = col.lerp(route.look["verge"][here], 0.5)
	if k > 1:
		var tint: Array = (route.look.get("cover", COVER_TINT) as Dictionary).get(route.cover_at(x, z), [])
		if not tint.is_empty():
			col = col.lerp(tint[0] as Color, float(tint[1]) * (0.5 if k == 2 else 1.0))
		# Further out, the satellite's own colour of the ground (PlaceLook).
		var ground: Array = route.look.get("ground", [])
		if not ground.is_empty():
			var ll := RealRegion.from_frame(route.frame, x, z)
			var g := PlaceLook.ground_at(ground, ll.x, ll.y)
			if g.a > 0.0:
				col = col.lerp(Color(g.r, g.g, g.b), PlaceLook.ground_share(lat) * g.a)
	# Snow above the place's snow line (PlaceLook), on the gentler ground.
	if y > route.snow_line - 120.0 and route.look.has("snow_line"):
		col = col.lerp(PlaceLook.SNOW, smoothstep(route.snow_line - 120.0, route.snow_line + 80.0, y) * 0.85)
	# Steep ground away from the road shows rock (snow lies on the gentler slopes).
	var rise := absf(y - route.ph[i]) / maxf(lat, 1.0)
	if k > 3:
		col = col.lerp(Color(0.45, 0.43, 0.4), smoothstep(0.45, 0.9, rise) * 0.7)
		# By the sea: a beach along the water's edge, wet sand under it.
		if route.sea and y < AdventureTheme.SEA_Y + 5.0:
			col = col.lerp(BEACH, 1.0 - smoothstep(AdventureTheme.SEA_Y + 2.0, AdventureTheme.SEA_Y + 5.0, y))
			if y < AdventureTheme.SEA_Y - 0.2:
				col = BEACH.darkened(0.3)
	return col


## An indexed grid mesh's arrays from `rows` x `cols` vertices (row by row, each row left to
## right looking along the road), with normals worked out from its faces.
static func _grid(v: PackedVector3Array, rows: int, cols: int, uv: PackedVector2Array, col: PackedColorArray) -> Array:
	var idx := PackedInt32Array()
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	for r in rows - 1:
		for k in cols - 1:
			var bl := r * cols + k
			var br := bl + 1
			var tl := bl + cols
			var tr := tl + 1
			idx.append_array([bl, tl, tr, bl, tr, br])
			var n1 := (v[tr] - v[bl]).cross(v[tl] - v[bl])
			var n2 := (v[br] - v[bl]).cross(v[tr] - v[bl])
			for p in [bl, tl, tr]:
				nrm[p] += n1
			for p in [bl, tr, br]:
				nrm[p] += n2
	for p in nrm.size():
		nrm[p] = nrm[p].normalized() if nrm[p].length_squared() > 0.0 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Grid `v` (`rows` x `cols`) with its first and last rows run on SEAM_OVERLAP further along the road, in the
## surface's own slope, for the road's collision: the next chunk's road starts where this one ends, but each is placed
## at its own anchor, and a ray down at the very seam could slip between the two by a hair (the wheel losing the road
## for a tick). Overlapped, the two lie in one surface across the seam.
static func _overlapped(v: PackedVector3Array, rows: int, cols: int) -> PackedVector3Array:
	var out := v.duplicate()
	if rows < 2:
		return out
	for k in cols:
		var a := v[k]
		var b := v[cols + k]
		out[k] = a + (a - b).normalized() * SEAM_OVERLAP
		var y := v[(rows - 1) * cols + k]
		var z := v[(rows - 2) * cols + k]
		out[(rows - 1) * cols + k] = y + (y - z).normalized() * SEAM_OVERLAP
	return out


## Collision triangles for the first `upto` columns of a grid (the last `upto` with `from_end`).
static func _faces(v: PackedVector3Array, rows: int, cols: int, upto: int, from_end := false) -> PackedVector3Array:
	var f := PackedVector3Array()
	var k0 := cols - upto if from_end else 0
	var k1 := cols - 1 if from_end else upto - 1
	for r in rows - 1:
		for k in range(k0, k1):
			var bl := r * cols + k
			var br := bl + 1
			var tl := bl + cols
			var tr := tl + 1
			f.append_array([v[bl], v[tl], v[tr], v[bl], v[tr], v[br]])
	return f


## The white lines on tarmac: solid edge lines on anything but a single track, and a dashed
## centre line on a road wide enough for two.
static func _lines(route: AdventureRoute, i0: int, i1: int, ax: float, az: float, surf: String) -> Dictionary:
	var a := AdventureProps.new_arrays()
	if surf != "tarmac":
		return a
	var col := Color(0.88, 0.88, 0.84)
	var junctions := AdventureJunctions.near(route, i0, i1, 12)
	for i in range(i0, i1):
		var e0 := route.width[i] * 0.5
		var e1 := route.width[i + 1] * 0.5
		if e0 < 2.0:
			continue
		# No centre line through a junction (nor round a roundabout's island), and none along the
		# edge across a side road's mouth.
		var centre := e0 >= 2.7 and i % 3 == 0
		var offs := []
		for side: float in [-1.0, 1.0]:
			if not AdventureJunctions.mouth(route, i, side) and not AdventureJunctions.mouth(route, i + 1, side):
				offs.append([side * (e0 - 0.3), side * (e1 - 0.3), 0.12])
		for st in junctions:
			if absf(float(i - int(st["i"]))) * AdventureRoute.STEP < AdventureJunctions.zone(st):
				centre = false
		# Dashes: 3 m of line, 6 m gap (a knot is 4 m: every third knot's stretch, most of it).
		if centre:
			offs.append([0.0, 0.0, 0.1])
		for o in offs:
			var w: float = o[2] * 0.5
			var p := []
			for j: int in [i, i + 1]:
				var lat: float = o[0] if j == i else o[1]
				var h := route.hd[j]
				var f := lat / maxf(route.width[j] * 0.5, 0.1)
				var y := route.ph[j] + CROWN * (1.0 - f * f) + 0.012
				var cx := route.px[j] - ax
				var cz := route.pz[j] - az
				p.append(Vector3(cx + cos(h) * (lat - w), y, cz + sin(h) * (lat - w)))
				p.append(Vector3(cx + cos(h) * (lat + w), y, cz + sin(h) * (lat + w)))
			# p: [i left, i right, i+1 left, i+1 right]
			AdventureProps._quad(a, p[0], p[1], p[3], p[2], col)
	return a


## The trees, bushes, rocks, posts, fences and buildings of the chunk, and its km posts and sites.
static func _scenery(route: AdventureRoute, c: int, i0: int, i1: int, ax: float, az: float, surf: String, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "chunk", c])
	var mm := {}
	var theme := route.theme
	var counts: Dictionary = (AdventureTheme.get_value(theme, "scenery", {}) as Dictionary).get(surf, SCENERY.get(surf, {}))
	var real := route.real != null
	var canopy := real and _has_canopy(route, i0, i1)
	var tries: Dictionary = route.look.get("plants", REAL_TRIES)
	if real:
		counts = counts.duplicate()
		if route.look.has("plants"):
			counts = tries.duplicate()
			if surf == "snow":
				counts["snow_pine"] = int(counts.get("pine", 0)) + int(counts.get("snow_pine", 0))
				counts.erase("pine")
		for kind in REAL_TRIES:
			if not route.look.has("plants"):
				counts[kind] = REAL_TRIES[kind]
	if canopy:
		mm = _canopy_trees(route, c, i0, i1, ax, az, surf)
	for kind in counts:
		if canopy and kind in TREES:
			continue
		var list := []
		var many := int(tries.get(kind, counts[kind])) if real else int(counts[kind])
		for k in many:
			var i := rng.randi_range(i0, i1)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var near := 2.5 if kind in NEAR_KINDS else 6.0
			var lat := route.width[i] * 0.5 + near + pow(rng.randf(), 1.5) * (REAL_REACH if real else 120.0)
			var xf := _on_land(route, i, lat * side, ax, az, rng.randf() * TAU, rng.randf_range(0.7, 1.35))
			var roll := rng.randf()
			if xf != Transform3D() and (not real or roll < _cover_odds(route, kind, ax + xf.origin.x, az + xf.origin.z)):
				list.append(xf)
		mm[kind] = list
	# Fences along farmland, a post every 3 m or so, with two rails between; or in the hills and
	# by the sea dry-stone walls and hedges (a theme's "bounds").
	var buildings := AdventureProps.new_arrays()
	var walls := AdventureProps.new_arrays()
	var bounds: Array = route.look["bounds"] if route.look.has("bounds") else AdventureTheme.get_value(theme, "bounds", [])
	var bound_kind := "fence" if bounds.is_empty() else str(bounds[0])
	var bound_odds: Dictionary = FENCE_ODDS if bounds.is_empty() else bounds[1]
	var stretch := int(i0 * AdventureRoute.STEP / 600.0)
	var fence_roll := float(absi(hash([route.seed_value, "fence", stretch])) % 1000) / 1000.0
	if bound_kind == "wall_hedge":
		bound_kind = "wall" if absi(hash([route.seed_value, "hedge", stretch])) % 2 == 0 else "hedge"
	if real:
		# Fences and walls only where the land is farmed.
		fence_roll = 0.0 if _farmed(route, i0, i1) else 1.0
	if fence_roll < float(bound_odds.get(surf, 0.0)):
		var posts := []
		var rail := Color(0.45, 0.35, 0.24)
		for side: float in [-1.0, 1.0]:
			var prev := Vector3.INF
			for i in range(i0, i1 + 1):
				var lat := (route.width[i] * 0.5 + (4.0 if bound_kind == "fence" else 2.6)) * side
				# No fence across a site's forecourt or lay-by, nor a side road's mouth: they're
				# left open to ride in.
				var shut := route._site_flat(i, side, false) > 0.5 or AdventureJunctions.mouth(route, i, side, 4.0)
				var xf := Transform3D() if shut else _on_land(route, i, lat, ax, az, route.hd[i], 1.0, true)
				if xf == Transform3D():
					prev = Vector3.INF
					continue
				if bound_kind == "fence":
					posts.append(xf)
				if prev != Vector3.INF:
					match bound_kind:
						"fence":
							for y: float in [0.55, 0.95]:
								_rail(buildings, prev + Vector3.UP * y, xf.origin + Vector3.UP * y, rail)
						"wall":
							var shade := 0.8 + 0.35 * float(absi(hash([i, side])) % 100) / 100.0
							_wall(walls, prev, xf.origin, 0.95, 0.55, Color(0.42, 0.4, 0.35) * shade)
						"hedge":
							var shade := 0.88 + 0.2 * float(absi(hash([i, side])) % 100) / 100.0
							_wall(walls, prev, xf.origin, 1.55, 1.1, Color(0.17, 0.3, 0.11) * shade)
				prev = xf.origin
		if not posts.is_empty():
			mm["post"] = posts
	out["walls"] = walls
	# Marker poles along a snowy road, every 32 m or so either side.
	if surf == "snow":
		var poles := []
		for i in range(i0, i1 + 1, 8):
			for side: float in [-1.0, 1.0]:
				var xf := _on_land(route, i, (route.width[i] * 0.5 + 1.2) * side, ax, az, 0.0, 1.0, true)
				if xf != Transform3D():
					poles.append(xf)
		mm["snow_pole"] = poles
	# The buildings: the real ones beside a real road, else the odd one.
	if real:
		_real_buildings(route, c, i0, ax, az, buildings)
	elif rng.randf() < float(BUILDING_ODDS.get(surf, 0.0)) * float(AdventureTheme.get_value(theme, "buildings", 1.0)):
		var i := rng.randi_range(i0, i1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := route.width[i] * 0.5 + rng.randf_range(18.0, 50.0)
		# Facing the road: local +z towards it.
		var face := atan2(-cos(route.hd[i]) * side, -sin(route.hd[i]) * side)
		var xf := _on_land(route, i, lat * side, ax, az, face, 1.0, false, 9.0)
		if xf != Transform3D():
			xf.origin.y -= 0.4   # sunk in a little on a slope
			AdventureProps.building(buildings, xf, rng, surf, str(AdventureTheme.get_value(theme, "style", "mixed")))
	out["buildings"] = buildings
	_far(route, c, i0, i1, ax, az, mm)
	# Kilometre posts on the left verge, every kilometre.
	var kms := []
	var s0 := i0 * AdventureRoute.STEP
	var s1 := i1 * AdventureRoute.STEP
	var km := int(ceil(s0 / 1000.0))
	while km * 1000.0 < s1:
		if km > 0:
			var i := int(km * 1000.0 / AdventureRoute.STEP)
			var xf := _on_land(route, i, -(route.width[i] * 0.5 + 1.4), ax, az, -route.hd[i], 1.0, true)
			if xf != Transform3D():
				kms.append({"xf": xf, "km": km})
		km += 1
	out["km"] = kms
	mm["km_post"] = kms.map(func(k): return k["xf"])
	out["mm"] = mm
	out["mm_buf"] = _mm_buffers(mm)
	# Sites starting in this chunk, and where each stands: on the verge, x away from the road.
	var here := []
	for st in route.sites:
		var si: int = st["i"]
		if si >= i0 and si < i1 or (si == i1 and i1 == route.knot_count() - 1):
			var side := float(st["side"])
			var h := route.hd[si]
			var e := route.width[si] * 0.5
			var r := Vector3(cos(h), 0.0, sin(h))
			var fwd := Vector3(sin(h), 0.0, -cos(h))
			var across: bool = st["kind"] in ["start", "finish", AdventureJunctions.KIND]   # a banner over the road, a junction's middle
			var lat := 0.0 if across else (e + 0.9) * side
			var origin := Vector3(route.px[si] - ax + r.x * lat, route.ph[si], route.pz[si] - az + r.z * lat)
			var basis := Basis(r, Vector3.UP, -fwd) if across else Basis(r * side, Vector3.UP, -fwd * side)
			here.append({"site": st, "xf": Transform3D(basis, origin), "width": route.width[si]})
	out["sites"] = here


## Whether the trees of the cells under chunk i0..i1 are to hand (RealTerrain.trees_at), at its middle.
static func _has_canopy(route: AdventureRoute, i0: int, i1: int) -> bool:
	var t := route.real.terrain
	if t == null or not t.has_trees():
		return false
	var i := (i0 + i1) / 2
	return t.trees_at(route.px[i], route.pz[i]) >= 0


## The trees of chunk c (knots i0..i1) where the canopy map has them (see CANOPY_STEP): kind -> [Transform3D].
static func _canopy_trees(route: AdventureRoute, c: int, i0: int, i1: int, ax: float, az: float, surf: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "canopy", c])
	var t := route.real.terrain
	var out := {}
	var broad := "oak" if AdventureTheme.get_value(route.theme, "scenery", {}).get("tarmac", {}).has("oak") else "tree"
	var needle := "snow_pine" if surf == "snow" else str(route.look.get("needle", "pine"))
	broad = str(route.look.get("broad", broad))
	var autumn := float(route.look.get("autumn", 0.0))
	var along := int(CANOPY_STEP / AdventureRoute.STEP)
	for i in range(i0, i1, along):
		var h := route.hd[i]
		for side: float in [-1.0, 1.0]:
			var lat0 := route.width[i] * 0.5 + 6.0
			var lat := lat0 + CANOPY_STEP * 0.5
			while lat < lat0 + REAL_REACH:
				var wx := route.px[i] + cos(h) * lat * side
				var wz := route.pz[i] + sin(h) * lat * side
				var v := t.trees_at(wx, wz)
				lat += CANOPY_STEP
				var share := float((v >> 5) & 7) / 7.0 if v > 0 else 0.0
				if share <= 0.0:
					continue
				var tallest := float(v & 31) * CANOPY_HEIGHT_STEP
				var leaf := (v >> 8) & 3
				var conifer_odds := 1.0 if leaf == 2 else (0.0 if leaf == 1 else (0.5 if leaf == 3 else
					_needle_odds(route, t, wx, wz, share, tallest)))
				var conifer := float(absi(hash([floori(wx / NEEDLE_PATCH), floori(wz / NEEDLE_PATCH)])) % 1000) / 1000.0 < conifer_odds
				var crown: Array = CROWN_NEEDLE if conifer else CROWN_BROAD
				var wide := float(crown[0]) * tallest + float(crown[1])
				var many := minf(float(CANOPY_MOST), share * CANOPY_STEP * CANOPY_STEP / (wide * wide))
				if lat - CANOPY_STEP > float(CANOPY_THIN[0]):
					many *= float(CANOPY_THIN[1])
				var n := int(many + rng.randf())
				for k in n:
					var kind := needle if (conifer if leaf != 3 else rng.randf() < 0.5) else (broad if share < 0.5 or rng.randf() < 0.4 else "tree")
					if kind == "tree" and broad in ["jungle_tree", "acacia"]:
						kind = broad   # (no temperate trees in the tropics' woods)
					if kind in ["tree", "oak"] and autumn > 0.0 and rng.randf() < autumn:
						kind = "autumn_tree"
					var ii := clampi(i + rng.randi_range(-along / 2, along / 2), i0, i1)
					var lj := maxf(lat0, lat - CANOPY_STEP * 1.5 + rng.randf() * CANOPY_STEP)
					var xf := _on_land(route, ii, lj * side, ax, az, rng.randf() * TAU, 1.0)
					if xf == Transform3D():
						continue
					# Only on ground the map has trees on itself (round a bend the look's square is further off), and
					# as tall as they are there; and never in the water (the canopy hangs over a river: the tree
					# stands on its bank).
					var here := t.trees_at(ax + xf.origin.x, az + xf.origin.z)
					if (here >> 5) & 7 == 0 or _in_water(route, ax + xf.origin.x, az + xf.origin.z):
						continue
					var top := float(here & 31) * CANOPY_HEIGHT_STEP
					var tall := maxf(3.0, top * (rng.randf_range(0.85, 1.0) if n == 1 else rng.randf_range(0.65, 1.0)))
					var size: Array = TREE_SIZE[kind]
					var across := (float(crown[0]) * tall + float(crown[1])) / float(size[1])
					xf.basis = xf.basis.scaled(Vector3(across, tall / float(size[0]), across))
					if not out.has(kind):
						out[kind] = []
					(out[kind] as Array).append(xf)
	return out


## Whether world (x, z) is in a river, a lake or a beck (RealPack.WATER cover, RealPack.stream_at).
static func _in_water(route: AdventureRoute, x: float, z: float) -> bool:
	if route.real.terrain.cover(x, z) == RealPack.WATER:
		return true
	var st := route.real.stream_at(x, z)
	return st.x < st.y + 1.0


## How likely trees the map doesn't give the leaves of are a conifer's (NEEDLE_ODDS), at world (x, z).
static func _needle_odds(route: AdventureRoute, t: RealTerrain, x: float, z: float, share: float, tallest: float) -> float:
	var p := float(NEEDLE_ODDS["north"]) if absf(t.lat0) > float(NEEDLE_ODDS["north_lat"]) else float(NEEDLE_ODDS["base"])
	if share >= 0.85 and tallest >= 14.0:
		p += float(NEEDLE_ODDS["plantation"])
	var y := t.height(x, z)
	if not is_nan(y) and y > float(NEEDLE_ODDS["high_y"]):
		p += float(NEEDLE_ODDS["high"])
	if route.theme == "alpine" or str(route.look.get("kit", "")) in ["alpine", "boreal"]:
		p += float(NEEDLE_ODDS["alpine"])
	return p


## How much of `kind`'s scenery the cover at world (x, z) takes on a real road (see ODDS), 0 to 1.
static func _cover_odds(route: AdventureRoute, kind: String, x: float, z: float) -> float:
	var cover := route.cover_at(x, z)
	var table: Dictionary = ODDS["trees"] if kind in TREES else (ODDS["bushes"] if kind in BUSHES else (ODDS["rocks"] if kind == "rock" else ODDS["other"]))
	return float(table.get(cover, OTHER_ODDS)) if cover != "" else OTHER_ODDS


## Whether a good part of the land either side of knots i0..i1 of a real road is cropland.
static func _farmed(route: AdventureRoute, i0: int, i1: int) -> bool:
	var crop := 0
	var total := 0
	for i in range(i0, i1 + 1, 8):
		for side: float in [-1.0, 1.0]:
			var e := route.width[i] * 0.5 + 12.0
			var c := route.cover_at(route.px[i] + cos(route.hd[i]) * e * side, route.pz[i] + sin(route.hd[i]) * e * side)
			total += 1
			if c == "crop":
				crop += 1
	return total > 0 and float(crop) / total > 0.25


## The real buildings beside the road in chunk `c` of the path on a real road, into `buildings`: each on the ground the
## land's mesh has there, none by a site (a fuel station, a stop) or over the road's verge. The pack files them by the
## main road's chunk, so on the other way of a fork there are none (they aren't baked there), and past one the path's
## chunk is mapped back to the main road's (`eq`).
static func _real_buildings(route: AdventureRoute, c: int, i0: int, ax: float, az: float, buildings: Dictionary) -> void:
	var style := str(AdventureTheme.get_value(route.theme, "style", "mixed"))
	var piece := route._piece_at(float(i0) * AdventureRoute.STEP)
	if int(piece["fork"]) >= 0 and int(piece["way"]) > 0:
		return
	var dk0 := route.eq[mini(i0, route.eq.size() - 1)] if not route.eq.is_empty() else i0
	var dc := dk0 / AdventureRoute.CHUNK_KNOTS
	# Nearest the road first: in the middle of a town the ones furthest back are left out (BUILDING_VERTS).
	var todo := []
	for b: Array in route.real.buildings_in(dc):
		var k := clampi(i0 + int(b[7]) - dc * AdventureRoute.CHUNK_KNOTS, 0, route.knot_count() - 1)
		var lat := (float(b[0]) - route.px[k]) * cos(route.hd[k]) + (float(b[1]) - route.pz[k]) * sin(route.hd[k])
		todo.append([absf(lat), lat, k, b])
	todo.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	for item: Array in todo:
		if (buildings["v"] as PackedVector3Array).size() >= BUILDING_VERTS:
			break
		var b: Array = item[3]
		var k: int = item[2]
		var lat: float = item[1]
		var bx := float(b[0])
		var bz := float(b[1])
		if route._site_flat(k, signf(lat), false) > 0.5 or absf(lat) < route.width[k] * 0.5 + 3.0:
			continue
		var w := float(b[2])
		var d := float(b[3])
		var yaw := float(b[4])
		# On the lowest ground under its middle and corners: the land's mesh is coarser than the baked heights.
		var y := route.land_height(k, lat, bx, bz)
		for cx: float in [-0.5, 0.5]:
			for cz: float in [-0.5, 0.5]:
				var px := bx + (cx * w) * cos(yaw) + (cz * d) * sin(yaw)
				var pz := bz - (cx * w) * sin(yaw) + (cz * d) * cos(yaw)
				y = minf(y, route.land_height(k, (px - route.px[k]) * cos(route.hd[k]) + (pz - route.pz[k]) * sin(route.hd[k]), px, pz))
		AdventureProps.real_building(buildings, Vector3(bx - ax, y, bz - az), w, d, yaw, float(b[5]), RealPack.BUILDING_KINDS[clampi(int(b[6]), 0, RealPack.BUILDING_KINDS.size() - 1)], style)


## The real lighthouses of a real road that stand by knots i0..i1, into `mm`.
static func _real_landmarks(route: AdventureRoute, i0: int, i1: int, ax: float, az: float, mm: Dictionary) -> void:
	var list := []
	for m: Dictionary in route.real.landmarks:
		if str(m["kind"]) != "lighthouse":
			continue
		var hit := route.locate(float(m["x"]), float(m["z"]))
		if hit.is_empty() or int(hit["i"]) < i0 or int(hit["i"]) >= i1:
			continue
		var y := route.real.terrain.height(float(m["x"]), float(m["z"]))
		if is_nan(y):
			continue
		list.append(Transform3D(Basis(Vector3.UP, hash([m["x"], m["z"]]) % 628 / 100.0), Vector3(float(m["x"]) - ax, y, float(m["z"]) - az)))
	if not list.is_empty():
		mm["lighthouse"] = list


## The theme's far scenery in chunk `c` (AdventureTheme "far"): the odd mesa off in the desert,
## a crag of bare rock in the mountains, a lighthouse on a cliff top by the sea. On its own rng,
## so the rest of the chunk is laid out the same with or without it.
static func _far(route: AdventureRoute, c: int, i0: int, i1: int, ax: float, az: float, mm: Dictionary) -> void:
	if route.real != null:
		_real_landmarks(route, i0, i1, ax, az, mm)
		return
	var far: Array = AdventureTheme.get_value(route.theme, "far", [])
	if far.is_empty():
		return
	var kind := str(far[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "far", c])
	var list := []
	for k in int(far[2]):
		if rng.randf() >= float(far[1]):
			continue
		var i := rng.randi_range(i0, i1)
		if kind == "lighthouse":
			# On the first cliff top along the chunk from there (none where it's all beach).
			for j in range(0, i1 - i0, 4):
				var xf := _cliff_top(route, i0 + (i - i0 + j) % (i1 - i0), ax, az)
				if xf != Transform3D():
					list.append(xf)
					break
			continue
		var place: Array = FAR_PLACE[kind]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		if route.sea:
			side = 1.0
		var lat := rng.randf_range(place[0], place[1]) * side
		var xf := _on_land(route, i, lat, ax, az, rng.randf() * TAU, rng.randf_range(0.7, 1.5), false, place[2])
		if xf != Transform3D():
			xf.origin.y -= 2.0   # bedded in on a slope
			list.append(xf)
	if not list.is_empty():
		mm[kind] = list


## Where a lighthouse stands beside knot `i`: the last high ground before the land drops to the
## sea (on the left of a coastal road), or an empty Transform3D where it's a beach, not a cliff.
static func _cliff_top(route: AdventureRoute, i: int, ax: float, az: float) -> Transform3D:
	var h := route.hd[i]
	var e := route.width[i] * 0.5
	var prev := Vector3.INF
	var a := e + 30.0
	while a < e + 260.0:
		if a > route.land_reach(i, -1) * 0.95:
			return Transform3D()
		var wx := route.px[i] - cos(h) * a
		var wz := route.pz[i] - sin(h) * a
		var y := route.land_height(i, -a, wx, wz)
		if prev != Vector3.INF and prev.y > AdventureTheme.SEA_Y + 14.0 and y < AdventureTheme.SEA_Y + 2.0:
			if route.clearance(prev.x, prev.z) < 30.0:
				return Transform3D()
			return Transform3D(Basis(), Vector3(prev.x - ax, prev.y - 0.3, prev.z - az))
		prev = Vector3(wx, y, wz)
		a += 12.0
	return Transform3D()


## The bridges between knots i0 and i1 (AdventureRoute.deck): a stone parapet each side of the deck, the deck's sides
## and underside BRIDGE_DEPTH down, and a pier every PIER_GAP metres or so where the ground is well below. Relative to
## the anchor (ax, az).
static func _bridge(route: AdventureRoute, i0: int, i1: int, ax: float, az: float) -> Dictionary:
	var arr := AdventureProps.new_arrays()
	if route.deck.is_empty():
		return arr
	var stone: Color = BRIDGE_STONE
	var depth := AdventureRoute.BRIDGE_DEPTH
	var at := func(i: int, lat: float, y: float) -> Vector3:
		var h := route.hd[i]
		return Vector3(route.px[i] + cos(h) * lat - ax, y, route.pz[i] + sin(h) * lat - az)
	var since := 999
	for i in range(i0, mini(i1, route.deck.size() - 1)):
		if route.deck[i] <= 0.0 or route.deck[i + 1] <= 0.0:
			since = 999
			continue
		var e0 := route.width[i] * 0.5
		var e1 := route.width[i + 1] * 0.5
		var y0 := route.ph[i]
		var y1 := route.ph[i + 1]
		for side: int in [-1, 1]:
			var s := float(side)
			# The parapet: its inside, top and outside, then the deck's side on down.
			var in0: Vector3 = at.call(i, s * (e0 + 0.15), y0 - 0.05)
			var in1: Vector3 = at.call(i + 1, s * (e1 + 0.15), y1 - 0.05)
			var out0: Vector3 = at.call(i, s * (e0 + 0.6), y0 - depth)
			var out1: Vector3 = at.call(i + 1, s * (e1 + 0.6), y1 - depth)
			var top := Vector3.UP * (PARAPET + 0.05)
			var outer0: Vector3 = at.call(i, s * (e0 + 0.6), y0)
			var outer1: Vector3 = at.call(i + 1, s * (e1 + 0.6), y1)
			if side < 0:
				AdventureProps._quad(arr, in1, in0, in0 + top, in1 + top, stone.darkened(0.06))
				AdventureProps._quad(arr, in1 + top, in0 + top, outer0 + top, outer1 + top, stone.lightened(0.08))
				AdventureProps._quad(arr, outer0 + top, outer1 + top, out1, out0, stone)
			else:
				AdventureProps._quad(arr, in0, in1, in1 + top, in0 + top, stone.darkened(0.06))
				AdventureProps._quad(arr, in0 + top, in1 + top, outer1 + top, outer0 + top, stone.lightened(0.08))
				AdventureProps._quad(arr, outer1 + top, outer0 + top, out0, out1, stone)
		# The underside, seen from the river.
		var ul0: Vector3 = at.call(i, -(e0 + 0.6), y0 - depth)
		var ur0: Vector3 = at.call(i, e0 + 0.6, y0 - depth)
		var ul1: Vector3 = at.call(i + 1, -(e1 + 0.6), y1 - depth)
		var ur1: Vector3 = at.call(i + 1, e1 + 0.6, y1 - depth)
		AdventureProps._quad(arr, ul0, ur0, ur1, ul1, stone.darkened(0.25))
		# A pier where the ground is well below and the last is far enough back.
		since += 1
		var mid: Vector3 = at.call(i, 0.0, y0 - depth)
		var ground := route.natural_height(i, mid.x + ax, mid.z + az)
		if since * AdventureRoute.STEP >= PIER_GAP and route.deck[i] >= 1.0 and y0 - depth - ground > 1.5:
			since = 0
			var xf := Transform3D(Basis(Vector3.UP, -route.hd[i]), Vector3(mid.x, ground - 0.5, mid.z))
			AdventureProps.box(arr, xf, Vector3(e0 * 2.0 + 0.8, y0 - depth - ground + 0.5, 1.6), stone.darkened(0.12), false)
	return arr


static var _bridge_mat: BaseMaterial3D


## The props' vertex-colour material, seen from both sides (a bridge is looked at from the road and from the river).
static func _bridge_material() -> BaseMaterial3D:
	if _bridge_mat == null:
		_bridge_mat = (AdventureProps.vc_material() as BaseMaterial3D).duplicate()
		_bridge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _bridge_mat


## A dry-stone wall or a hedge from `a` to `b` (on the ground), `h` high and `t` thick: its
## two sides and its top.
static func _wall(arr: Dictionary, a: Vector3, b: Vector3, h: float, t: float, col: Color) -> void:
	var along := b - a
	along.y = 0.0
	if along.length() < 0.01:
		return
	var across := Vector3(-along.z, 0.0, along.x).normalized() * t * 0.5
	var up := Vector3.UP * h
	var top := 0.82   # a little narrower over the top
	var dn := Vector3.DOWN * 0.25   # down into the ground on a slope
	AdventureProps._quad(arr, a + across + dn, b + across + dn, b + across * top + up, a + across * top + up, col)
	AdventureProps._quad(arr, b - across + dn, a - across + dn, a - across * top + up, b - across * top + up, col.darkened(0.08))
	AdventureProps._quad(arr, a + across * top + up, b + across * top + up, b - across * top + up, a - across * top + up, col.lightened(0.06))


## A transform standing on the land `lat` metres off the road at knot `i` (relative to the
## anchor), turned `angle` about the vertical (local +z then points along (sin, cos)) and
## scaled `scale`; an empty Transform3D where it would be on a road,
## a site's forecourt, or past the land the chunk draws on the inside of a bend. `keep_clear`
## is how far from any road's edge it must be (fence posts and markers sit closer).
static func _on_land(route: AdventureRoute, i: int, lat: float, ax: float, az: float, angle: float, scale: float,
		close := false, keep_clear := 2.0) -> Transform3D:
	var h := route.hd[i]
	if absf(lat) > route.land_reach(i, int(signf(lat))) * 0.95:
		return Transform3D()
	if absf(lat) < route.width[i] * 0.5 + 14.0 and route.in_tunnel(i):
		return Transform3D()   # nothing by the road in a tunnel, nor on the rock just over it
	var wx := route.px[i] + cos(h) * lat
	var wz := route.pz[i] + sin(h) * lat
	if not close and route.clearance(wx, wz) < keep_clear:
		return Transform3D()
	if route._site_flat(i, signf(lat), false) > 0.0 and not close:
		return Transform3D()
	if not close and AdventureJunctions.in_the_way(route, i, lat, wx, wz, keep_clear):
		return Transform3D()   # on a side road, or the corners of a junction
	var y := route.land_height(i, lat, wx, wz)
	if route.sea and y < AdventureTheme.SEA_Y + 0.8 and not close:
		return Transform3D()   # in the sea, or on the wet sand
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale), Vector3(wx - ax, y - 0.05, wz - az))


## A fence rail from `a` to `b`: a thin plank, seen from both sides.
static func _rail(arr: Dictionary, a: Vector3, b: Vector3, col: Color) -> void:
	var up := Vector3.UP * 0.07
	AdventureProps._quad(arr, a - up, b - up, b + up, a + up, col)
	AdventureProps._quad(arr, b - up, a - up, a + up, b + up, col)


# ---------------------------------------------------------------------------- nodes

## Makes chunk `data` (from build) into a node under `world`, placed at its anchor in the
## world's local frame, all at once. Returns it (its meta "c" is the chunk index).
static func commit(data: Dictionary, world: AdventureWorld) -> Node3D:
	var job := begin(data, world)
	while not step(job):
		pass
	return job["node"]


## The job of putting chunk `data` into `world` a piece at a time (see step): AdventureWorld does
## a few milliseconds of it a frame. All at once a chunk could take 10 ms and more on the main
## thread (its meshes, its collision, its scenery, a fuel station or a cafe on it), a stutter.
static func begin(data: Dictionary, world: AdventureWorld) -> Dictionary:
	var node := Node3D.new()
	var c: int = data["c"]
	node.name = "Chunk%d" % c
	node.set_meta("c", c)
	node.set_meta("ax", data["ax"])
	node.set_meta("az", data["az"])
	return {"data": data, "world": world, "node": node, "c": c, "step": 0, "site": 0}


## Does the next piece of putting a chunk into the world (`job` from begin): its road and land,
## their collision, the side roads and any tunnel, the scenery, then each site on it; and last
## the node goes into the world, whole. True once it has.
static func step(job: Dictionary) -> bool:
	var data: Dictionary = job["data"]
	var node: Node3D = job["node"]
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	match int(job["step"]):
		0:
			_commit_ground(data, node, scale)
		1:
			_commit_bodies(data, node)
		2:
			_commit_junctions(data, node, scale)
		3:
			_commit_scenery(data, node, scale)
		4:
			var sites: Array = data["sites"]
			var k: int = job["site"]
			if k < sites.size():
				var st: Dictionary = sites[k]
				var site: Dictionary = st["site"]
				var world: AdventureWorld = job["world"]
				var builder: Callable = world.site_builders.get(str(site["kind"]), Callable())
				if builder.is_valid():
					var made = builder.call(site, st["xf"], st)
					if made is Node3D:
						node.add_child(made)
				job["site"] = k + 1
				if k + 1 < sites.size():
					return false   # the next site next time
		_:
			(job["world"] as AdventureWorld).place_chunk(node)
			return true
	job["step"] = int(job["step"]) + 1
	return false


## The road (its lines), and the land either side in one mesh.
static func _commit_ground(data: Dictionary, node: Node3D, scale: float) -> void:
	var surf: String = data["surface"]
	# Road
	var road := ArrayMesh.new()
	road.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["road"])
	var rmi := MeshInstance3D.new()
	rmi.name = "Road"
	rmi.mesh = road
	rmi.material_override = AdventureSurface.road_material(surf)
	node.add_child(rmi)
	var lines: Dictionary = data["lines"]
	if not (lines["v"] as PackedVector3Array).is_empty():
		var lmi := MeshInstance3D.new()
		lmi.name = "Lines"
		lmi.mesh = AdventureProps.to_mesh(lines)
		lmi.material_override = AdventureSurface.line_material()
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(lmi, RANGES["lines"] * scale)
		node.add_child(lmi)
	# Land, both sides in one mesh
	var land := ArrayMesh.new()
	land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["land_-1"])
	land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["land_1"])
	var lmesh := MeshInstance3D.new()
	lmesh.name = "Land"
	lmesh.mesh = land
	lmesh.material_override = AdventureSurface.land_material()
	node.add_child(lmesh)
	var bridge: Dictionary = data.get("bridge", {})
	if not bridge.is_empty() and not (bridge["v"] as PackedVector3Array).is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Bridge"
		bmi.mesh = AdventureProps.to_mesh(bridge)
		bmi.material_override = _bridge_material()
		_range(bmi, RANGES["bridge"] * scale)
		node.add_child(bmi)


## The collision: the road (its surface for the tyres) and the land near it.
static func _commit_bodies(data: Dictionary, node: Node3D) -> void:
	var surf: String = data["surface"]
	var rb := StaticBody3D.new()
	rb.name = "RoadBody"
	rb.collision_layer = 1
	rb.set_meta("surface", surf)
	var rshape := ConcavePolygonShape3D.new()
	rshape.backface_collision = true
	rshape.set_faces(data["road_faces"])
	var rcs := CollisionShape3D.new()
	rcs.shape = rshape
	rb.add_child(rcs)
	node.add_child(rb)
	var lb := StaticBody3D.new()
	lb.name = "LandBody"
	lb.collision_layer = 1
	lb.set_meta("surface", data["land"])
	for side: int in [-1, 1]:
		var lshape := ConcavePolygonShape3D.new()
		lshape.backface_collision = true
		lshape.set_faces(data["land_faces_%d" % side])
		var lcs := CollisionShape3D.new()
		lcs.shape = lshape
		lb.add_child(lcs)
	node.add_child(lb)


## Each kind's transforms in `mm` as a MultiMesh's buffer (twelve floats each, the basis's rows
## each with the origin's part on the end), made here on the worker thread so that the commit only
## hands it over, instead of setting each transform in turn on the main thread.
static func _mm_buffers(mm: Dictionary) -> Dictionary:
	var out := {}
	for kind in mm:
		var list: Array = mm[kind]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 12)
		var j := 0
		for xf: Transform3D in list:
			var b := xf.basis
			var o := xf.origin
			buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
			buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y
			buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
			j += 12
		out[kind] = buf
	return out


## The trees, rocks, posts and the rest, the walls and hedges, the buildings and the km posts.
static func _commit_scenery(data: Dictionary, node: Node3D, scale: float) -> void:
	var mm: Dictionary = data["mm"]
	var bufs: Dictionary = data.get("mm_buf", {})
	for kind in mm:
		var list: Array = mm[kind]
		if list.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = AdventureProps.mesh(kind)
		multi.instance_count = list.size()
		var buf: PackedFloat32Array = bufs.get(kind, PackedFloat32Array())
		if buf.size() == list.size() * 12:
			multi.buffer = buf
		else:
			for k in list.size():
				multi.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + kind
		mmi.multimesh = multi
		if kind in ["post", "snow_pole", "km_post", "bush", "dry_bush", "gorse", "dune_grass", "sheep", "red_rock", "agave", "tussock"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(mmi, float(RANGES.get(kind, 400.0)) * scale)
		node.add_child(mmi)
	var walls: Dictionary = data.get("walls", {})
	if not walls.is_empty() and not (walls["v"] as PackedVector3Array).is_empty():
		var wmi := MeshInstance3D.new()
		wmi.name = "Walls"
		wmi.mesh = AdventureProps.to_mesh(walls)
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(wmi, RANGES["walls"] * scale)
		node.add_child(wmi)
	var bld: Dictionary = data["buildings"]
	if not (bld["v"] as PackedVector3Array).is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Buildings"
		bmi.mesh = AdventureProps.to_mesh(bld)
		_range(bmi, RANGES["buildings"] * scale)
		node.add_child(bmi)
	for k in data["km"]:
		var label := Label3D.new()
		label.text = "%d" % int(k["km"])
		label.font_size = 40
		label.pixel_size = 0.006
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		var xf: Transform3D = k["xf"]
		label.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.62 + xf.basis.z.normalized() * 0.06)
		label.visibility_range_end = 120.0
		node.add_child(label)


## The side roads (each surface its own mesh and collision, for the tyres) and the junctions' paint.
static func _commit_junctions(data: Dictionary, node: Node3D, scale: float) -> void:
	var arms: Dictionary = data.get("arms", {})
	for surf in arms:
		var a: Dictionary = arms[surf]
		if (a["v"] as PackedVector3Array).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "SideRoads_" + str(surf)
		mi.mesh = AdventureJunctions.stub_mesh(a)
		mi.material_override = AdventureSurface.road_material(str(surf))
		node.add_child(mi)
		var body := StaticBody3D.new()
		body.name = "SideRoadBody_" + str(surf)
		body.collision_layer = 1
		body.set_meta("surface", surf)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(data["arm_faces"][surf])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		node.add_child(body)
	var paint: Dictionary = data.get("paint", {})
	if not paint.is_empty() and not (paint["v"] as PackedVector3Array).is_empty():
		var pm := MeshInstance3D.new()
		pm.name = "JunctionPaint"
		pm.mesh = AdventureProps.to_mesh(paint)
		pm.material_override = AdventureSurface.line_material()
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(pm, RANGES["lines"] * scale)
		node.add_child(pm)
	AdventureTunnels.commit(data, node)


static func _range(gi: GeometryInstance3D, end: float) -> void:
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = 30.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
