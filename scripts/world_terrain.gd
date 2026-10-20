class_name WorldTerrain
extends RefCounted
## The land of the riding map: a height grid every SPACING metres over the whole map, shaped
## from noise (rolling farmland, mountains along the north edge, hills round the rim), kept
## flat round the shed's yard and under the villages and farms, and cut and filled to sit
## just under every road. It makes the ground's collision (one height map) and its look:
## chunks of mesh with a near and a far level of detail.

const HALF := 2048.0
const SPACING := 4.0
const SIZE := 1025                   # samples along each side
const CHUNK := 64                    # cells along each side of a mesh chunk
const COARSE := 4                    # the far mesh keeps every 4th sample
const SKIRT := 6.0                   # chunk edges hang down this far to hide seams
## The flat ground round the shed, its yard and the town it stands in, and the height of the
## grass on it (just under the yard's surface, so the slab's edge is no kerb).
const HOME := Rect2(-115.0, -62.0, 225.0, 212.0)
const HOME_LEVEL := -0.03
## How far under a road's surface the ground beneath it sits.
const ROAD_DROP := {"tarmac": 0.16, "dirt": 0.13}
## Past the road's edge the ground stays at road level for this far, then blends back into
## the land over the second distance (a tarmac road cuts wider banks than a track).
const ROAD_FLAT := 5.8
const ROAD_BLEND := {"tarmac": 28.0, "dirt": 11.0}

var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
## How much a road shaped each sample (0..1), its distance to that road's centre and its
## kind (0 none, 1 tarmac, 2 dirt).
var road_w := PackedFloat32Array()
var road_d := PackedFloat32Array()
var road_k := PackedByteArray()

var _hills := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var _sites := []   # [{at, r, h}] ground levelled for villages and farms
## The route whose heights are the land (see RoutePack), or null for the made-up land.
var _pack: RoutePack = WorldLayout.pack

## Lone hills on the low ground: centre, height and spread, in metres.
const HILLS := [[Vector2(10.0, -215.0), 35.0, 100.0], [Vector2(200.0, -90.0), -10.0, 80.0], [Vector2(-185.0, 60.0), 14.0, 70.0],
	[Vector2(100.0, -1290.0), -55.0, 280.0], [Vector2(-650.0, -250.0), 55.0, 200.0], [Vector2(700.0, -150.0), 45.0, 180.0],
	[Vector2(-300.0, 1080.0), 50.0, 220.0], [Vector2(1560.0, 620.0), 70.0, 260.0],
	[Vector2(-1520.0, 320.0), 60.0, 230.0], [Vector2(650.0, 900.0), 45.0, 200.0]]


func _init(seed_value := 1) -> void:
	for pair in [[_hills, 0.0013, 4], [_mid, 0.0045, 3], [_detail, 0.018, 2], [_ridge, 0.0011, 5], [_patch, 0.012, 3]]:
		var n: FastNoiseLite = pair[0]
		n.seed = seed_value + int(pair[1] * 100000.0)
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = pair[1]
		n.fractal_octaves = pair[2]
	for s in WorldLayout.sites():
		var at: Vector2 = s["at"]
		_sites.append({"at": at, "r": float(s["r"]), "h": _land(at.x, at.y)})


# ---------------------------------------------------------------------------- the land

## The shape of the land before roads: hills, mountains, the rim, levelled at the yard and
## under the villages and farms.
func natural(x: float, z: float) -> float:
	var h := _land(x, z)
	for s in _sites:
		var d := (s["at"] as Vector2).distance_to(Vector2(x, z))
		var r: float = s["r"]
		if d < r:
			h = lerpf(h, float(s["h"]), 1.0 - smoothstep(r * 0.55, r, d))
	return lerpf(HOME_LEVEL, h, home_mask(x, z))


## 0 on the flat ground round the shed, rising to 1 well clear of it.
static func home_mask(x: float, z: float) -> float:
	if not WorldLayout.has_shed():
		return 1.0
	var dx := maxf(maxf(HOME.position.x - x, x - HOME.end.x), 0.0)
	var dz := maxf(maxf(HOME.position.y - z, z - HOME.end.y), 0.0)
	return smoothstep(10.0, 95.0, Vector2(dx, dz).length())


## The land before sites and the yard: a route's own heights, or noise and hills.
func _land(x: float, z: float) -> float:
	if _pack != null:
		return _pack.height_at(x, z)
	return _raw(x, z) + _hills_at(x, z)


func _raw(x: float, z: float) -> float:
	var h := _hills.get_noise_2d(x, z) * 26.0 + _mid.get_noise_2d(x, z) * 7.0 + _detail.get_noise_2d(x, z) * 1.4
	# The mountains rise along the north edge, craggiest furthest north.
	var north := smoothstep(-700.0, -1250.0, z)
	if north > 0.0:
		var rn := 1.0 - absf(_ridge.get_noise_2d(x, z))
		var high := smoothstep(-1000.0, -1650.0, z)
		h += north * (150.0 + _mid.get_noise_2d(x * 0.5, z * 0.5) * 40.0) + high * rn * rn * 240.0
	# Hills round the rim of the map.
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(1650.0, 2040.0, edge) * (75.0 + _hills.get_noise_2d(z, x) * 40.0)
	return h


func _hills_at(x: float, z: float) -> float:
	var h := 0.0
	for hill in HILLS:
		var d2 := (hill[0] as Vector2).distance_squared_to(Vector2(x, z))
		var r: float = hill[2]
		if d2 < 9.0 * r * r:
			h += float(hill[1]) * exp(-d2 / (r * r))
	return h


## Woodland density at (x, z): above 0 is woods, the higher the thicker.
func forest(x: float, z: float) -> float:
	return _hills.get_noise_2d(x * 3.1 + 900.0, z * 3.1 - 400.0) + _patch.get_noise_2d(x, z) * 0.25


## The grid sample index nearest (x, z), clamped onto the map.
static func index_of(x: float, z: float) -> int:
	var gx := clampi(roundi((x + HALF) / SPACING), 0, SIZE - 1)
	var gz := clampi(roundi((z + HALF) / SPACING), 0, SIZE - 1)
	return gz * SIZE + gx


## The ground height at (x, z), read off the grid the way the mesh draws it.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / SPACING, 0.0, SIZE - 1.001)
	var fz := clampf((z + HALF) / SPACING, 0.0, SIZE - 1.001)
	var gx := int(fx)
	var gz := int(fz)
	var tx := fx - gx
	var tz := fz - gz
	var i := gz * SIZE + gx
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + SIZE]
	var h11 := heights[i + SIZE + 1]
	# Each cell is two triangles split corner (0,0) .. (1,1).
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


## The ground's slope at (x, z): 0 flat .. 1 a cliff.
func slope_at(x: float, z: float) -> float:
	return 1.0 - normals[index_of(x, z)].y


# ---------------------------------------------------------------------------- building the grid

## Fills the height grid from the land, then cuts and fills it to every road in `roads`.
func build(roads: WorldRoads) -> void:
	var n := SIZE * SIZE
	heights.resize(n)
	road_w.resize(n)
	road_w.fill(0.0)
	road_d.resize(n)
	road_d.fill(999.0)
	road_k.resize(n)
	road_k.fill(0)
	# The same land as natural(), a box at a time: the raw shape everywhere, then the sites
	# and the yard levelled within reach of them.
	if _pack != null:
		heights = _pack.heights.duplicate()
	else:
		for gz in SIZE:
			var z := gz * SPACING - HALF
			var row := gz * SIZE
			for gx in SIZE:
				heights[row + gx] = _raw(gx * SPACING - HALF, z)
	var hills: Array = HILLS if _pack == null else []
	for hill in hills:
		var c: Vector2 = hill[0]
		var r: float = hill[2]
		var box := _grid_box(Rect2(c - Vector2(r, r) * 3.0, Vector2(r, r) * 6.0))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var d2 := c.distance_squared_to(Vector2(gx * SPACING - HALF, gz * SPACING - HALF))
				if d2 < 9.0 * r * r:
					heights[gz * SIZE + gx] += float(hill[1]) * exp(-d2 / (r * r))
	for site in _sites:
		var at: Vector2 = site["at"]
		var r: float = site["r"]
		var sh: float = site["h"]
		var box := _grid_box(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var d := at.distance_to(Vector2(gx * SPACING - HALF, gz * SPACING - HALF))
				if d < r:
					var i := gz * SIZE + gx
					heights[i] = lerpf(heights[i], sh, 1.0 - smoothstep(r * 0.55, r, d))
	if WorldLayout.has_shed():
		var home := _grid_box(HOME.grow(95.0))
		for gz in range(home.position.y, home.end.y):
			for gx in range(home.position.x, home.end.x):
				var i := gz * SIZE + gx
				heights[i] = lerpf(HOME_LEVEL, heights[i], home_mask(gx * SPACING - HALF, gz * SPACING - HALF))
	var road_h := PackedFloat32Array()
	road_h.resize(n)
	for r in roads.roads:
		_stamp(r, road_h)
	for i in n:
		var w := road_w[i]
		if w > 0.0:
			heights[i] = lerpf(heights[i], road_h[i], w)
	_build_normals()
	_build_colors()


## Marks the ground road `r` shapes: road height (less the drop) where it is nearest, and how
## strongly (1 up to ROAD_FLAT past its edge, fading out over ROAD_BLEND).
func _stamp(r: Dictionary, road_h: PackedFloat32Array) -> void:
	var kind: String = r["kind"]
	var code := 1 if kind == "tarmac" else 2
	var flat: float = float(r["hw"]) + ROAD_FLAT
	var blend: float = ROAD_BLEND[kind]
	var reach := flat + blend
	var xz: PackedVector2Array = r["xz"]
	var hs: PackedFloat32Array = r["h"]
	var n := xz.size()
	var segs := n if r["closed"] else n - 1
	var stride := 2
	var k := 0
	while k < segs:
		var k2 := mini(k + stride, n if r["closed"] else n - 1)
		var a := xz[k]
		var b := xz[k2 % n]
		var ha := hs[k]
		var hb := hs[k2 % n]
		var mid := (a + b) * 0.5
		var drop := lerpf(-HOME_LEVEL, float(ROAD_DROP[kind]), smoothstep(0.0, 40.0, _home_dist(mid.x, mid.y)))
		var seg := b - a
		var len2 := maxf(seg.length_squared(), 0.0001)
		var gx0 := maxi(0, floori((minf(a.x, b.x) - reach + HALF) / SPACING))
		var gx1 := mini(SIZE - 1, ceili((maxf(a.x, b.x) + reach + HALF) / SPACING))
		var gz0 := maxi(0, floori((minf(a.y, b.y) - reach + HALF) / SPACING))
		var gz1 := mini(SIZE - 1, ceili((maxf(a.y, b.y) + reach + HALF) / SPACING))
		for gz in range(gz0, gz1 + 1):
			var pz := gz * SPACING - HALF
			var row := gz * SIZE
			for gx in range(gx0, gx1 + 1):
				var px := gx * SPACING - HALF
				var u := clampf(((px - a.x) * seg.x + (pz - a.y) * seg.y) / len2, 0.0, 1.0)
				var dx := px - (a.x + seg.x * u)
				var dz := pz - (a.y + seg.y * u)
				var d := sqrt(dx * dx + dz * dz)
				if d >= reach:
					continue
				var w := 1.0 if d <= flat else 1.0 - smoothstep(flat, reach, d)
				var i := row + gx
				if w > road_w[i] + 0.0001 or (w > road_w[i] - 0.0001 and d < road_d[i]):
					road_w[i] = w
					road_d[i] = d
					road_k[i] = code
					road_h[i] = lerpf(ha, hb, u) - drop
		k = k2


## The grid samples covering `rect` (x, z in metres) as a range of indices.
static func _grid_box(rect: Rect2) -> Rect2i:
	var x0 := clampi(floori((rect.position.x + HALF) / SPACING), 0, SIZE)
	var z0 := clampi(floori((rect.position.y + HALF) / SPACING), 0, SIZE)
	var x1 := clampi(ceili((rect.end.x + HALF) / SPACING) + 1, 0, SIZE)
	var z1 := clampi(ceili((rect.end.y + HALF) / SPACING) + 1, 0, SIZE)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


func _home_dist(x: float, z: float) -> float:
	var dx := maxf(maxf(HOME.position.x - x, x - HOME.end.x), 0.0)
	var dz := maxf(maxf(HOME.position.y - z, z - HOME.end.y), 0.0)
	return Vector2(dx, dz).length()


func _build_normals() -> void:
	normals.resize(SIZE * SIZE)
	for gz in SIZE:
		for gx in SIZE:
			var i := gz * SIZE + gx
			var l := heights[i - 1] if gx > 0 else heights[i]
			var r := heights[i + 1] if gx < SIZE - 1 else heights[i]
			var u := heights[i - SIZE] if gz > 0 else heights[i]
			var d := heights[i + SIZE] if gz < SIZE - 1 else heights[i]
			normals[i] = Vector3(l - r, 2.0 * SPACING, u - d).normalized()


## Grass of two greens, darker under woods, crops in the fields round the farms, rock on
## steep slopes, scree and snow up high, gravel along the tarmac and bare earth by the tracks.
func _build_colors() -> void:
	colors.resize(SIZE * SIZE)
	var grass_a := Color(0.25, 0.37, 0.13)
	var grass_b := Color(0.37, 0.43, 0.19)
	var woods := Color(0.2, 0.27, 0.11)
	var moor := Color(0.42, 0.38, 0.24)
	var rock := Color(0.36, 0.34, 0.31)
	var snow := Color(0.86, 0.88, 0.92)
	var earth := Color(0.4, 0.3, 0.2)
	var gravel := Color(0.42, 0.4, 0.36)
	var sand := Color(0.78, 0.7, 0.5)
	var crops := [Color(0.62, 0.55, 0.24), Color(0.33, 0.47, 0.16), Color(0.38, 0.29, 0.19), Color(0.5, 0.52, 0.22)]
	var farms := []
	for site in WorldLayout.sites():
		if site["kind"] == "farm":
			farms.append(site["at"])
	for gz in SIZE:
		var z := gz * SPACING - HALF
		for gx in SIZE:
			var x := gx * SPACING - HALF
			var i := gz * SIZE + gx
			var c := grass_a.lerp(grass_b, clampf(_patch.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0))
			var f := forest(x, z)
			if f > -0.05:
				c = c.lerp(woods, smoothstep(-0.05, 0.15, f) * 0.8)
			var h := heights[i]
			var slope := 1.0 - normals[i].y
			if _pack == null:
				c = c.lerp(moor, smoothstep(150.0, 240.0, h) * 0.7)
				c = c.lerp(rock, smoothstep(0.18, 0.4, slope))
				if h > 250.0:
					c = c.lerp(snow, smoothstep(250.0, 320.0, h + _detail.get_noise_2d(x, z) * 30.0) * (1.0 - smoothstep(0.25, 0.45, slope)))
			else:
				# Real land: the height is over the start, so the real height is h + base_elev. Moorland and
				# bare rock only up high, snow only on real mountains.
				var e := h + _pack.base_elev
				c = c.lerp(moor, smoothstep(450.0, 900.0, e) * 0.6)
				c = c.lerp(rock, smoothstep(0.22, 0.5, slope))
				if e > 1800.0:
					c = c.lerp(snow, smoothstep(1800.0, 2300.0, e) * (1.0 - smoothstep(0.25, 0.45, slope)))
				if not is_nan(_pack.sea_level):
					# Sand and wet shingle at the water's edge, the sea floor dark under it.
					var above := h - _pack.sea_level
					c = c.lerp(sand, 1.0 - smoothstep(1.4, 3.6, above))
					if above < 0.0:
						c = sand.darkened(0.25).lerp(Color(0.1, 0.24, 0.3), clampf(-above / 9.0, 0.0, 1.0))
			var k := road_k[i]
			if k == 1:
				c = c.lerp(gravel, (1.0 - smoothstep(4.0, 9.0, road_d[i])) * 0.8)
			elif k == 2:
				c = c.lerp(earth, (1.0 - smoothstep(2.5, 6.5, road_d[i])) * 0.85)
			colors[i] = c
	# Fields round the farms, and worn gravel round the yard's edges fading into the grass.
	for at: Vector2 in farms:
		var box := _grid_box(Rect2(at - Vector2(330.0, 330.0), Vector2(660.0, 660.0)))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var i := gz * SIZE + gx
				var fc := field_at(gx * SPACING - HALF, gz * SPACING - HALF, at)
				if fc >= 0 and road_w[i] < 0.5 and 1.0 - normals[i].y < 0.2:
					colors[i] = colors[i].lerp(crops[fc], 0.85)
	# Farmyards: trodden earth and gravel round the buildings.
	for at: Vector2 in farms:
		var box := _grid_box(Rect2(at - Vector2(40.0, 40.0), Vector2(80.0, 80.0)))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var d := at.distance_to(Vector2(gx * SPACING - HALF, gz * SPACING - HALF))
				if d < 40.0:
					var i := gz * SIZE + gx
					colors[i] = colors[i].lerp(earth.lerp(gravel, 0.5), (1.0 - smoothstep(22.0, 40.0, d)) * 0.85)
	for rect: Rect2 in WorldYard.GROUND:
		var box := _grid_box(rect.grow(14.0))
		for gz in range(box.position.y, box.end.y):
			for gx in range(box.position.x, box.end.x):
				var p := Vector2(gx * SPACING - HALF, gz * SPACING - HALF)
				var hd := Vector2(maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0),
					maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)).length()
				if hd < 14.0:
					var i := gz * SIZE + gx
					colors[i] = colors[i].lerp(gravel, (1.0 - smoothstep(0.0, 14.0, hd)) * 0.7)


## Which crop (0..3) the field at (x, z) round the farm at `farm` grows, or -1 for none:
## a patchwork of fields 70 by 45 m within 330 m of the farmyard.
static func field_at(x: float, z: float, farm: Vector2) -> int:
	var dx := x - farm.x
	var dz := z - farm.y
	var d2 := dx * dx + dz * dz
	if d2 > 330.0 * 330.0 or d2 < 70.0 * 70.0:
		return -1
	var cx := floori(dx / 70.0)
	var cz := floori(dz / 45.0)
	var hash := absi((cx * 73856093) ^ (cz * 19349663) ^ int(farm.x * 7.0))
	var crop := hash % 7
	return crop if crop < 4 else -1


# ---------------------------------------------------------------------------- meshes and collision

## The terrain's collision: one height map over the whole map, tagged "grass".
func make_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = SIZE
	shape.map_depth = SIZE
	# The shape is scaled up by SPACING (uniformly), so its heights are scaled down to match.
	var data := heights.duplicate()
	for i in data.size():
		data[i] /= SPACING
	shape.map_data = data
	return shape


## The mesh of chunk (cx, cz) with every `step`th sample, in coordinates about its centre.
func chunk_mesh(cx: int, cz: int, step: int) -> ArrayMesh:
	var per := CHUNK / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var center := chunk_center(cx, cz)
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for j in per:
		for k in per:
			var gx := x0 + k * step
			var gz := z0 + j * step
			var i := gz * SIZE + gx
			var wx := gx * SPACING - HALF
			var wz := gz * SPACING - HALF
			verts.append(Vector3(wx - center.x, heights[i], wz - center.y))
			norms.append(normals[i])
			cols.append(colors[i])
			uvs.append(Vector2(wx, wz) / 6.0)
	var idx := PackedInt32Array()
	for j in per - 1:
		for k in per - 1:
			var a := j * per + k
			idx.append_array([a, a + 1, a + per + 1, a, a + per + 1, a + per])
	# Skirts: each edge copied lower and stitched on, so a near chunk next to a far one shows no
	# gap where their edges differ. In the mountains the far mesh's edge can sit well above the
	# near one's between its samples, more than SKIRT, which let the sky show through slits in
	# the distant hills: each edge hangs down as far as the two ever part along it, and more.
	var edges := [[0, 1, 0], [per - 1, 1, 0], [0, 0, 1], [per - 1, 0, 1]]
	for e in edges:
		var base := verts.size()
		var drop := SKIRT + _edge_gap(cx, cz, e)
		for t in per:
			var j: int = e[0] if e[2] == 0 else t
			var k: int = t if e[2] == 0 else e[0]
			var src := j * per + k
			verts.append(verts[src] + Vector3.DOWN * drop)
			norms.append(norms[src])
			cols.append(cols[src])
			uvs.append(uvs[src])
		for t in per - 1:
			var j1: int = e[0] if e[2] == 0 else t
			var k1: int = t if e[2] == 0 else e[0]
			var j2: int = e[0] if e[2] == 0 else t + 1
			var k2: int = t + 1 if e[2] == 0 else e[0]
			var a := j1 * per + k1
			var b := j2 * per + k2
			idx.append_array([a, b, base + t + 1, a, base + t + 1, base + t])
			idx.append_array([a, base + t + 1, b, a, base + t, base + t + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## How far apart (m) the near and far meshes' edges ever get along one edge of chunk (cx, cz):
## the full-detail heights against the far mesh's straight lines between every COARSE-th sample.
## `e` is the edge as chunk_mesh lists them ([index along, 1 for a row / 0 for a column, ...]).
func _edge_gap(cx: int, cz: int, e: Array) -> float:
	var gap := 0.0
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var fixed: int = (CHUNK if int(e[0]) > 0 else 0)
	for c in range(0, CHUNK, COARSE):
		var h := PackedFloat32Array()
		for q in COARSE + 1:
			var gx: int = x0 + (c + q if int(e[2]) == 0 else fixed)
			var gz: int = z0 + (fixed if int(e[2]) == 0 else c + q)
			h.append(heights[mini(gz, SIZE - 1) * SIZE + mini(gx, SIZE - 1)])
		for q in range(1, COARSE):
			gap = maxf(gap, absf(h[q] - lerpf(h[0], h[COARSE], float(q) / COARSE)))
	return gap


## The middle of chunk (cx, cz) on the ground plane.
static func chunk_center(cx: int, cz: int) -> Vector2:
	return Vector2((cx + 0.5) * CHUNK * SPACING - HALF, (cz + 0.5) * CHUNK * SPACING - HALF)


## How many chunks along each side.
static func chunk_count() -> int:
	return (SIZE - 1) / CHUNK


## Land beyond the map's edge, to the horizon: low-detail hills with no collision, so the
## view off the mountains doesn't end in a cliff.
func horizon_mesh() -> ArrayMesh:
	# Grid lines: every 16 m (the far terrain's own spacing) close to the map, wider further out,
	# so the land right at the edge carries on exactly and the far hills cost little.
	var axis := PackedFloat32Array()
	var far := 9216.0
	var x := -far
	while x < 0.0:
		axis.append(x)
		var out := -x - HALF
		x += 256.0 if out > 768.0 else (64.0 if out > 192.0 else 16.0)
	var n := axis.size()
	axis.append(0.0)
	for i in range(n - 1, -1, -1):
		axis.append(-axis[i])
	n = axis.size()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var haze := Color(0.3, 0.38, 0.22)
	for j in n:
		for k in n:
			var px := axis[k]
			var pz := axis[j]
			if absf(px) < HALF and absf(pz) < HALF:
				verts.append(Vector3.ZERO)   # inside the map: never drawn
				cols.append(haze)
				continue
			var h := _horizon_height(px, pz)
			verts.append(Vector3(px, h, pz))
			var edge := maxf(absf(px), absf(pz))
			var land := colors[index_of(clampf(px, -HALF, HALF), clampf(pz, -HALF, HALF))]
			var far_col := haze.lerp(Color(0.42, 0.45, 0.4), smoothstep(150.0, 400.0, h))
			cols.append(land.lerp(far_col, smoothstep(HALF, HALF + 1500.0, edge)))
	var idx := PackedInt32Array()
	for j in n - 1:
		for k in n - 1:
			var mx := (axis[k] + axis[k + 1]) * 0.5
			var mz := (axis[j] + axis[j + 1]) * 0.5
			if absf(mx) < HALF and absf(mz) < HALF:
				continue
			var a := j * n + k
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.set_color(cols[i])
		st.add_vertex(verts[i])
	st.index()
	st.generate_normals()
	return st.commit()


func _horizon_height(x: float, z: float) -> float:
	var edge := maxf(absf(x), absf(z))
	if edge <= HALF + 1.0:
		return height_at(clampf(x, -HALF, HALF), clampf(z, -HALF, HALF)) - 0.3
	var out := smoothstep(HALF, HALF + 1400.0, edge)
	if _pack != null:
		# A real place carries on the way its edge does, not into made-up hills.
		out = 0.0
	var hills := 90.0 + _hills.get_noise_2d(x * 0.4, z * 0.4) * 160.0 + (220.0 if z < 0.0 else 0.0) * smoothstep(-HALF, -HALF - 2000.0, z)
	# The map's edge carried outwards, blurred along the edge the further out it goes, so its
	# ridges soften into the far hills instead of streaking.
	var c := Vector2(clampf(x, -HALF, HALF), clampf(z, -HALF, HALF))
	var along := Vector2(0.0, 1.0) if absf(x) > absf(z) else Vector2(1.0, 0.0)
	var spread := (edge - HALF) * 0.5
	var rim := 0.0
	for k: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var q := c + along * spread * k
		rim += height_at(clampf(q.x, -HALF, HALF), clampf(q.y, -HALF, HALF)) * 0.2
	return lerpf(rim, hills, out)
