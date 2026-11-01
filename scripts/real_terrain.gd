class_name RealTerrain
extends RefCounted
## The land of a real road (see RealPack, tools/route_bake.py, tools/levels.py): ground heights in metres above sea
## level, and what covers the ground, at any point in the route's frame. It is held at three levels so the world
## feels as big as it is without the pack growing with it: fine (4 m samples, near the road), coarse (32 m, out
## to the hillsides the land mesh runs up) and ridge (128 m, out to the skyline, which RealRidges draws as a mesh of
## its own). height() answers from the finest level that has the point, so where a finer level ends the coarser
## one carries on (the baker eased the finer one's edge into it, so there is no step).
##
## Tiles are read from disk the first time they are needed and kept. Safe to ask from worker threads (the
## adventure's chunks are built on them): a tile is read under a lock and never changed afterwards.
##
## height() is bilinear between samples; it is NAN where no level has the point (beyond the ridge level's reach), and
## the road's own planner falls back to the lie of the land it has there.
##
## A region may instead have **live** heights ("heights": "live" in its region.json): no height tiles of its own, the
## ground read from Mapterhorn's map tiles (HeightTiles) at three zooms that match the levels (about 3 m, 22 m and 90 m
## a pixel), with the shaping the baker does done here instead: each level eased into the next where its tiles end,
## the sea given a floor (in HeightTiles), and the ground levelled under each building. Its cover is still baked. A
## ride's terrain is its own view (for_road): the tiles of each level it uses are those within a set reach of its road,
## fixed by the road alone, so every machine that plans the same road gets the same heights whatever else it has on disk.
## Round the riders it takes in more as they go (follow_riders): a ring round each, a strip ahead of it, fetched on a
## worker and let go again once every rider is well past, so the ground keeps coming off the planned road and memory
## stays flat. Readers ask by position only (interfaces/terrain.md in the project's ride-anywhere-v2 folder):
## height, ready, sea_at; ground_arrived says where new tiles have sharpened it.

## Tiles came in round the riders: the heights over route-frame `area` from live level `level` may have changed (they
## were the coarser level's). On the main thread.
signal ground_arrived(area: Rect2, level: int)

class Level:
	extends RefCounted
	var folder := ""
	var spacing := 4.0
	var cells := 128
	var h_min := -256.0
	var h_scale := 0.0625
	var has_cover := false
	var base := ""   # the folder its tiles are in, when not the terrain's own (a cell's: add_cover_cell)
	var tiles := {}    # Vector2i -> PackedFloat32Array (empty when there is no such tile)
	var covers := {}   # Vector2i -> PackedByteArray (empty when there is no such tile)

	func size_m() -> float:
		return spacing * cells

var dir := ""
var levels: Array[Level] = []
var _lock := Mutex.new()

## Live heights (HeightTiles) instead of baked ones; the frame they are read in (the region's: degrees at its middle).
var live := false
var lat0 := 0.0
var lon0 := 0.0
var _m := Vector2(111000.0, 111000.0)   # metres per degree of latitude, of longitude, at lat0
## The live levels' zooms, finest first (fine, mid, ridge), and the spacing (m) each stands in for.
var zooms := PackedInt32Array()
const LIVE_SPACING := [4.0, 32.0, 128.0]
## How far (m) from a ride's road each live level's tiles are used (for_road): the fine level under the road's chunks
## and the near land blocks (RealLand), the middle one out to the far blocks, the ridge one out to the skyline's reach.
const LIVE_REACH := [1000.0, 6000.0, 18000.0]
## Where a live level's tiles end, it is eased into the next over this many of its pixels (of 512).
const LIVE_EASE_PX := 48.0
## The tiles of each level a ride uses: [{Vector3i: true}, ...], or empty for any on disk (the map's own view). The
## planned road's (_base) and those taken in round the riders (_ring). Changed on the main thread under _lock, read
## under it anywhere.
var uses: Array = []
var _base: Array = []    # [{Vector3i: true}, ...] the road's, kept all ride
var _ring := {}          # Vector3i -> level, taken in round the riders
## The fetch rule round the riders (follow_riders), by level: a ring of LIVE_REACH round each, a strip AHEAD of it
## (AHEAD_WIDE either side) along its way once it's moving faster than MOVING, and a tile let go once every rider is
## further than KEEP from it (and from AHEAD down its way).
const AHEAD := [3000.0, 6000.0, 0.0]
const AHEAD_WIDE := [600.0, 3000.0, 0.0]
const AHEAD_STEP := 500.0
const KEEP := [1500.0, 9000.0, 27000.0]
const MOVING := 2.0
## follow_riders works again once a rider has moved this far (m) or turned this much (radians).
const MOVE_AGAIN := 64.0
const TURN_AGAIN := 0.5
## How far (m) from every rider a worked-out ridge tile (_ridge_tiles) is let go.
const RIDGE_KEEP := 40000.0
## Fetches the tiles round the riders (keys, progress): HeightTiles.fetch; the tests put in their own.
static var fetcher := Callable()
## Whether the fetching round the riders is on a worker (false: in follow_riders itself, the tests).
var threaded := true
var _riders_at: Array = []   # [Vector4] where the riders were when it last worked
var _job := -1               # the worker fetching round the riders, or -1
var _job_keys: Array[Vector3i] = []
var _job_moved := false      # the riders moved on while it fetched: work again once it's done
var _last_riders: Array = []
var _asked := {}             # Vector2i -> true: the cells whose profile has been read for their sea (know_sea_under)
## The buildings (RealRegion.buildings rows) whose ground the live heights level, filed in PAD_CELL squares.
const PAD_CELL := 64.0
const PAD_MARGIN := 2.5
const PAD_FEATHER := 5.0
var _pads: Array = []
var _pad_grid := {}            # Vector2i -> PackedInt32Array of building indices
var _pad_level := {}           # building index -> its ground, once worked out (under _lock; each ride its own)
var _ridge_tiles := {}         # Vector2i -> PackedFloat32Array: the live ridge level as RealRidges reads it
## A region stitched from cells (RealRegion.stitch) reads its cover from each cell's own tiles, in the cell's own frame:
## [{levels, lat, lon, m (metres per degree there), south, west, north, east}].
var _cover_cells: Array = []
## The trees of the cells it covers (tools/tree_bake.py, add_trees): [{south, west, north, east, rows, cols, trees, leaf}],
## the last two PackedByteArrays of rows x cols, from the north-west corner.
var _tree_cells: Array = []
## Rivers' and lakes' water (RealPack.WATER cover) lies flat across and eases down along a river (water_at): the heights
## under the cover are the map's, which run up the banks and wander a metre or two from one sample to the next, so the
## water drawn on them tilted and its bed broke through in patches. Its level is worked out on a lattice WATER_STEP (m)
## apart, fixed to the frame so every block and level agrees on it: at each point the lowest of the water's heights
## within WATER_LOW steps, then that eased over WATER_EASE steps either way. It's kept in tiles of WATER_TILE points a
## side, the last WATER_KEPT of them, each worked out the first time it's asked for and again when its heights change.
const WATER_STEP := 8.0
const WATER_TILE := 64
const WATER_LOW := 3
const WATER_EASE := 2
const WATER_KEPT := 192
## How far a bank's foot at the water's edge lies under the water where the map has it level with it (m: water_bed).
const WATER_LIP := 0.3
## Land by the water this little above its level is let down under it (water_shore), and the water drawn over it.
const WATER_FLAT := 0.5
var _water_tiles := {}                  # Vector2i -> [levels, nearness, edges] (PackedFloat32Arrays; empty: none)
var _water_order: Array[Vector2i] = []  # the tiles in the order they were worked out
var _water_lock := Mutex.new()          # (its own: water_at is asked as often as the heights are)


func _init(pack_dir := "", meta: Dictionary = {}) -> void:
	dir = pack_dir
	live = str(meta.get("heights", "baked")) == "live"
	var fr: Dictionary = meta.get("frame", {})
	lat0 = float(fr.get("lat", 0.0))
	lon0 = float(fr.get("lon", 0.0))
	_m = metres_per_degree(lat0)
	for sp: float in LIVE_SPACING:
		zooms.append(HeightTiles.zoom_for(lat0, sp))
	for lm: Dictionary in meta.get("levels", []):
		var lv := Level.new()
		lv.folder = str(lm["dir"])
		lv.spacing = float(lm["spacing"])
		lv.cells = int(lm["n"])
		lv.h_min = float(lm["min"])
		lv.h_scale = float(lm["scale"])
		lv.has_cover = bool(lm.get("cover", false))
		levels.append(lv)


## The ground's height at route-frame (x, z), metres above sea level, or NAN where no level has it.
func height(x: float, z: float) -> float:
	if live:
		return _live_height(x, z)
	for lv in levels:
		var h := _level_height(lv, x, z)
		if not is_nan(h):
			return h
	return NAN


## The finest level's height at (x, z) only (for tests and the baker's checks), or NAN.
func height_at_level(level: int, x: float, z: float) -> float:
	if live:
		return _live_level(level, lat0 - z / _m.x, lon0 + x / _m.y, false) if level >= 0 and level < zooms.size() else NAN
	return _level_height(levels[level], x, z) if level >= 0 and level < levels.size() else NAN


func _level_height(lv: Level, x: float, z: float) -> float:
	var fx := x / lv.spacing
	var fz := z / lv.spacing
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var a := _cell(lv, ix, iz)
	if is_nan(a):
		return NAN
	var b := _cell(lv, ix + 1, iz)
	var c := _cell(lv, ix, iz + 1)
	var d := _cell(lv, ix + 1, iz + 1)
	if is_nan(b) or is_nan(c) or is_nan(d):
		return NAN
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## The water's level at route-frame (x, z) (x), how near the water is (y: the share of the water's lattice points
## within WATER_EASE steps, 0 well away from it, 1 out on it) and how much it's the water's edge (z: 1 at a point of it
## with dry land next to it, 0 out in it or off it), from the lattice round (x, z) (see WATER_STEP). x is NAN more than
## (WATER_LOW + WATER_EASE) steps from any water. Any thread. With `view` (water_view) its tiles are read from there.
func water_at(x: float, z: float, view := {}) -> Vector3:
	var fx := x / WATER_STEP
	var fz := z / WATER_STEP
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var level := 0.0
	var weight := 0.0
	var near := 0.0
	var edge := 0.0
	var key := Vector2i(-2147483648, 0)   # (none yet)
	var got: Array = []
	for k in 4:
		var px := ix + (k & 1)
		var pz := iz + (k >> 1)
		var w := (tx if k & 1 else 1.0 - tx) * (tz if k >> 1 else 1.0 - tz)
		if w <= 0.0:
			continue   # (on the lattice's line: the next tile isn't asked for)
		var kk := Vector2i(floori(float(px) / WATER_TILE), floori(float(pz) / WATER_TILE))
		if kk != key:
			key = kk
			got = view[key] if view.has(key) else _water_tile(key)
		if got.is_empty():
			continue
		var at := posmod(pz, WATER_TILE) * WATER_TILE + posmod(px, WATER_TILE)
		near += float((got[1] as PackedFloat32Array)[at]) * w
		edge += float((got[2] as PackedFloat32Array)[at]) * w
		var h: float = (got[0] as PackedFloat32Array)[at]
		if h != INF:
			level += h * w
			weight += w
	return Vector3(level / weight if weight > 0.0 else NAN, near, edge)


## The water's level at (x, z) (water_at), NAN away from it.
func water_level(x: float, z: float, view := {}) -> float:
	return water_at(x, z, view).x


## The water tiles round route-frame `area`, for water_at (and the rest) to read many points of it from without asking
## for each tile each time.
func water_view(area: Rect2) -> Dictionary:
	var out := {}
	var size := WATER_STEP * WATER_TILE
	for tz in range(floori(area.position.y / size), floori(area.end.y / size) + 1):
		for tx in range(floori(area.position.x / size), floori(area.end.x / size) + 1):
			out[Vector2i(tx, tz)] = _water_tile(Vector2i(tx, tz))
	return out


## The ground at (x, z) off the water (not RealPack.WATER cover), where the map's height is `raw`: as it is, but where
## it lies within WATER_FLAT of the water's level by the water (the map's own flat water beside the mapped water, where
## the two disagree by a few metres, or a beach) let down to WATER_LIP under the level, so the water (RealLand) spreads
## over it rather than standing level with it.
func water_shore(x: float, z: float, raw: float, view := {}) -> float:
	return shore_of(water_at(x, z, view), raw)


## water_shore from water_at's answer `w` there.
static func shore_of(w: Vector3, raw: float) -> float:
	if is_nan(w.x) or w.y <= 0.0 or raw >= w.x + WATER_FLAT:
		return raw
	var drop := clampf((w.x + WATER_FLAT - raw) / WATER_FLAT, 0.0, 1.0) * smoothstep(0.0, 0.1, w.y)
	return lerpf(raw, minf(raw, w.x - WATER_LIP), drop)


## The bed under the water at (x, z), where the map's height is `raw`: WATER_DEPTH under the water's level (or under the
## map's height where that's lower) out in it, and at its edge half-way up from the water to the map's height (a bank
## the water laps, where the cover runs up it) rather than a step down from the dry land beside it.
func water_bed(x: float, z: float, raw: float, depth: float, view := {}) -> float:
	var w := water_at(x, z, view)
	if is_nan(w.x):
		return raw - depth
	var low := minf(raw, w.x)
	return lerpf(low - depth, low - WATER_LIP + maxf(0.0, raw - w.x) * 0.5, w.z)


## Water tile `key` (water_at): [levels, nearness, edges], WATER_TILE squared each, or empty where there's no water
## near it.
func _water_tile(key: Vector2i) -> Array:
	_water_lock.lock()
	var got = _water_tiles.get(key)
	_water_lock.unlock()
	if got != null:
		return got
	var out := _work_water_tile(key)
	_water_lock.lock()
	if not _water_tiles.has(key):
		_water_order.append(key)
		while _water_order.size() > WATER_KEPT:
			_water_tiles.erase(_water_order.pop_front())
	_water_tiles[key] = out
	_water_lock.unlock()
	return out


func _work_water_tile(key: Vector2i) -> Array:
	var r := WATER_LOW + WATER_EASE
	var g := WATER_TILE + 2 * r
	var i0 := key.x * WATER_TILE - r
	var j0 := key.y * WATER_TILE - r
	# (none where every other point is dry: a tile of land with no water near it, the most of them, is told quickly)
	var covers := _cover_grid(i0 * WATER_STEP, j0 * WATER_STEP, WATER_STEP, g, 2)
	if not covers.has(RealPack.WATER):
		return []
	covers = _cover_grid(i0 * WATER_STEP, j0 * WATER_STEP, WATER_STEP, g)
	# The water's heights round the tile (INF where it's dry)...
	var raw := PackedFloat32Array()
	raw.resize(g * g)
	raw.fill(INF)
	var any := false
	for j in g:
		for i in g:
			var x := (i0 + i) * WATER_STEP
			var z := (j0 + j) * WATER_STEP
			if covers[j * g + i] != RealPack.WATER:
				continue
			var h := height(x, z)
			if not is_nan(h):
				raw[j * g + i] = h
				any = true
	if not any:
		return []
	# ...the lowest within WATER_LOW steps (along the rows, then down the columns)...
	var low := _low_pass(raw, g, WATER_LOW, true)
	low = _low_pass(low, g, WATER_LOW, false)
	# ...and that eased (the mean of those within WATER_EASE that have water near), with how much water is about.
	var sums := PackedFloat32Array()
	var counts := PackedFloat32Array()
	var wets := PackedFloat32Array()
	sums.resize(g * g)
	counts.resize(g * g)
	wets.resize(g * g)
	for j in g:
		if low.slice(j * g, j * g + g).count(INF) == g and raw.slice(j * g, j * g + g).count(INF) == g:
			continue   # (no water near this row: its sums and counts stay 0)
		for i in g:
			var e := WATER_EASE
			var s := 0.0
			var c := 0.0
			var wv := 0.0
			for d in range(-e, e + 1):
				if i + d < 0 or i + d >= g:
					continue
				var v := low[j * g + i + d]
				if v != INF:
					s += v
					c += 1.0
				if raw[j * g + i + d] != INF:
					wv += 1.0
			sums[j * g + i] = s
			counts[j * g + i] = c
			wets[j * g + i] = wv
	var levels := PackedFloat32Array()
	var nears := PackedFloat32Array()
	var edges := PackedFloat32Array()
	levels.resize(WATER_TILE * WATER_TILE)
	nears.resize(WATER_TILE * WATER_TILE)
	edges.resize(WATER_TILE * WATER_TILE)
	var span := float((2 * WATER_EASE + 1) * (2 * WATER_EASE + 1))
	for j in WATER_TILE:
		for i in WATER_TILE:
			var s := 0.0
			var c := 0.0
			var wv := 0.0
			for d in range(-WATER_EASE, WATER_EASE + 1):
				var at := (j + r + d) * g + i + r
				s += sums[at]
				c += counts[at]
				wv += wets[at]
			levels[j * WATER_TILE + i] = s / c if c > 0.0 else INF
			nears[j * WATER_TILE + i] = wv / span
			var at := (j + r) * g + i + r
			if raw[at] != INF:
				for d: int in [-g - 1, -g, -g + 1, -1, 1, g - 1, g, g + 1]:
					if raw[at + d] == INF:
						edges[j * WATER_TILE + i] = 1.0
						break
	return [levels, nears, edges]


## The lowest of `v` (g x g) within `reach` along each row (`rows`) or down each column.
static func _low_pass(v: PackedFloat32Array, g: int, reach: int, rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(g * g)
	out.fill(INF)
	for a in g:
		var dry := true   # (a line with no water on it stays INF: most of them, most tiles)
		for b in g:
			if (v[a * g + b] if rows else v[b * g + a]) != INF:
				dry = false
				break
		if dry:
			continue
		for b in g:
			var m := INF
			for d in range(maxi(0, b - reach), mini(g, b + reach + 1)):
				m = minf(m, v[a * g + d] if rows else v[d * g + a])
			out[a * g + b if rows else b * g + a] = m
	return out


## Lets go of the water tiles over `area` (their heights have changed: water_at works them out again).
func _forget_water(area: Rect2) -> void:
	var size := WATER_STEP * WATER_TILE
	var grown := area.grow(WATER_STEP * (WATER_LOW + WATER_EASE + 1))
	_water_lock.lock()
	for key: Vector2i in _water_tiles.keys():
		if Rect2(key.x * size, key.y * size, size, size).intersects(grown):
			_water_tiles.erase(key)
			_water_order.erase(key)
	_water_lock.unlock()


## What covers the ground at route-frame (x, z): an id into the pack's "cover" list (RealPack.COVER), or -1 where no
## level with cover has it. The sample nearest to (x, z), from the finest level that has it.
func cover(x: float, z: float) -> int:
	if not _cover_cells.is_empty():
		var lat := lat0 - z / _m.x
		var lon := lon0 + x / _m.y
		for c: Dictionary in _cover_cells:
			if lat >= float(c["south"]) and lat < float(c["north"]) and lon >= float(c["west"]) and lon < float(c["east"]):
				var m: Vector2 = c["m"]
				return _cover_from(c["levels"], (lon - float(c["lon"])) * m.y, -(lat - float(c["lat"])) * m.x)
		return -1
	return _cover_from(levels, x, z)


func _cover_from(lvls: Array, x: float, z: float) -> int:
	for lv: Level in lvls:
		if not lv.has_cover:
			continue
		var ix := roundi(x / lv.spacing)
		var iz := roundi(z / lv.spacing)
		var t: PackedByteArray = _cover_tile(lv, Vector2i(floori(float(ix) / lv.cells), floori(float(iz) / lv.cells)))
		if not t.is_empty():
			return t[posmod(iz, lv.cells) * lv.cells + posmod(ix, lv.cells)]
	return -1


## cover() at g x g points from (x0, z0), `step` apart (every `stride`th of them; the rest -1): the same answers, each
## cover tile looked up once (not under the lock for every point, which the heights the ride asks for wait on).
func _cover_grid(x0: float, z0: float, step: float, g: int, stride := 1) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(g * g)
	out.fill(-1)
	var memo := {}
	for j in range(0, g, stride):
		for i in range(0, g, stride):
			var x := x0 + i * step
			var z := z0 + j * step
			if _cover_cells.is_empty():
				out[j * g + i] = _cover_memo(levels, x, z, memo)
				continue
			var lat := lat0 - z / _m.x
			var lon := lon0 + x / _m.y
			for c: Dictionary in _cover_cells:
				if lat >= float(c["south"]) and lat < float(c["north"]) and lon >= float(c["west"]) and lon < float(c["east"]):
					var m: Vector2 = c["m"]
					out[j * g + i] = _cover_memo(c["levels"], (lon - float(c["lon"])) * m.y, -(lat - float(c["lat"])) * m.x, memo)
					break
	return out


## _cover_from, with the tiles it has looked up in `memo`.
func _cover_memo(lvls: Array, x: float, z: float, memo: Dictionary) -> int:
	for lv: Level in lvls:
		if not lv.has_cover:
			continue
		var ix := roundi(x / lv.spacing)
		var iz := roundi(z / lv.spacing)
		var key := Vector2i(floori(float(ix) / lv.cells), floori(float(iz) / lv.cells))
		var mine: Dictionary = memo.get(lv, {})
		if mine.is_empty():
			memo[lv] = mine
		var t: PackedByteArray
		if mine.has(key):
			t = mine[key]
		else:
			t = _cover_tile(lv, key)
			mine[key] = t
		if not t.is_empty():
			return t[posmod(iz, lv.cells) * lv.cells + posmod(ix, lv.cells)]
	return -1


## Whether a fine tile is under route-frame (x, z).
func has_tile_at(x: float, z: float) -> bool:
	if live:
		return _live_key(0, lat0 - z / _m.x, lon0 + x / _m.y) != Vector3i(-1, -1, -1)
	if levels.is_empty():
		return false
	var lv := levels[0]
	var s := lv.size_m()
	return not _tile(lv, Vector2i(int(floor(x / s)), int(floor(z / s)))).is_empty()


## The sample at grid index (ix, iz) of `lv` over the whole route frame: NAN where there is no tile.
func _cell(lv: Level, ix: int, iz: int) -> float:
	var per := lv.cells
	var t: PackedFloat32Array = _tile(lv, Vector2i(floori(float(ix) / per), floori(float(iz) / per)))
	if t.is_empty():
		return NAN
	return t[posmod(iz, per) * per + posmod(ix, per)]


## A tile of `lv` (its n x n heights), read the first time: empty when the pack has none there.
func _tile(lv: Level, key: Vector2i) -> PackedFloat32Array:
	_lock.lock()
	if lv.tiles.has(key):
		var got: PackedFloat32Array = lv.tiles[key]
		_lock.unlock()
		return got
	var out := PackedFloat32Array()
	var path := dir.path_join(lv.folder).path_join("%d_%d.u16z" % [key.x, key.y])
	if FileAccess.file_exists(path):
		out = decode_heights(FileAccess.get_file_as_bytes(path), lv.cells, lv.h_min, lv.h_scale)
	lv.tiles[key] = out
	_lock.unlock()
	return out


func _cover_tile(lv: Level, key: Vector2i) -> PackedByteArray:
	_lock.lock()
	if lv.covers.has(key):
		var got: PackedByteArray = lv.covers[key]
		_lock.unlock()
		return got
	var out := PackedByteArray()
	var path := (lv.base if lv.base != "" else dir).path_join(lv.folder).path_join("%d_%d.covz" % [key.x, key.y])
	if FileAccess.file_exists(path):
		var raw := FileAccess.get_file_as_bytes(path).decompress(lv.cells * lv.cells, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == lv.cells * lv.cells:
			out = raw
	lv.covers[key] = out
	_lock.unlock()
	return out


## A tile's heights from its file's bytes (tools/levels.py encode_heights): zlib, then differences along x then z
## (wrapping at 65536) as uint16s, back to metres. Empty when the bytes are no good.
static func decode_heights(bytes: PackedByteArray, cells: int, h_min: float, h_scale: float) -> PackedFloat32Array:
	var raw := bytes.decompress(cells * cells * 2, FileAccess.COMPRESSION_DEFLATE)
	var out := PackedFloat32Array()
	if raw.size() != cells * cells * 2:
		return out
	var v := PackedInt32Array()
	v.resize(cells * cells)
	for i in cells * cells:
		v[i] = raw.decode_u16(i * 2)
	for z in range(1, cells):
		for x in cells:
			v[z * cells + x] = (v[z * cells + x] + v[(z - 1) * cells + x]) & 0xFFFF
	out.resize(cells * cells)
	for z in cells:
		var run := 0
		for x in cells:
			run = (run + v[z * cells + x]) & 0xFFFF
			out[z * cells + x] = h_min + run * h_scale
	return out


## The ridge level's tile (its heights), or empty: for RealRidges. Index of the ridge level is the last.
func ridge_tile(key: Vector2i) -> PackedFloat32Array:
	if live:
		return _live_ridge_tile(key)
	return _tile(levels[-1], key) if not levels.is_empty() else PackedFloat32Array()


func ridge_spacing() -> float:
	return LIVE_SPACING[2] if live else (levels[-1].spacing if not levels.is_empty() else 128.0)


func ridge_cells() -> int:
	return 256 if live or levels.is_empty() else levels[-1].cells


## Where the ridge level is sea it lies just under the water (route_bake.RIDGE_SEA_M).
const RIDGE_SEA := -3.0


## Whether the ridge level is baked pushed down near the road (RealRidges pushes a live one down itself).
func ridge_lowered() -> bool:
	return not live


## How many fine tiles are held (for tests).
func loaded_count() -> int:
	if live:
		return held()["uses"][0] if not uses.is_empty() else 0
	if levels.is_empty():
		return 0
	_lock.lock()
	var n := levels[0].tiles.size()
	_lock.unlock()
	return n


# ---------------------------------------------------------------------------- live heights

## (metres per degree of latitude, of longitude) at `lat` degrees, from the WGS84 series (route_bake.metres_per_degree).
static func metres_per_degree(lat: float) -> Vector2:
	var p := deg_to_rad(lat)
	return Vector2(111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p),
		111412.84 * cos(p) - 93.5 * cos(3.0 * p) + 0.118 * cos(5.0 * p))


## The terrain of a ride along `road` (route-frame points along it, a few tens of metres apart): the same land, its
## live levels' tiles those within LIVE_REACH of the road. Baked terrain is the same for every road: itself.
func for_road(road: PackedVector2Array) -> RealTerrain:
	if not live:
		return self
	var t := RealTerrain.new()
	t.dir = dir
	t.levels = levels   # (cover is still read from them; their tiles are shared, under their own lock)
	t._lock = _lock
	t.live = true
	t.lat0 = lat0
	t.lon0 = lon0
	t._m = _m
	t.zooms = zooms
	t._pads = _pads
	t._pad_grid = _pad_grid
	t._cover_cells = _cover_cells
	t._tree_cells = _tree_cells
	t._asked = _asked
	for li in zooms.size():
		var set := {}
		for k in HeightTiles.keys_near(road, LIVE_REACH[li], zooms[li], lat0, lon0):
			set[k] = true
		t._base.append(set)
		t.uses.append(set.duplicate())
	return t


## Every tile this ride uses, finest first (for HeightTiles.fetch).
func used_keys() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	_lock.lock()
	for set: Dictionary in uses:
		for k: Vector3i in set:
			out.append(k)
	_lock.unlock()
	return out


## Fetches the tiles this ride uses that aren't on disk yet (blocks: a worker's job), and first the place profiles of the
## cells under its fine and middle levels, so their sea is known before a tile is read (know_sea). Returns how many
## tiles it couldn't get.
func fetch(progress := Callable()) -> int:
	if not live:
		return 0
	var keys := used_keys()
	know_sea_under(keys)
	return HeightTiles.fetch(keys, progress)


## Reads the place profile of each cell under the fine and middle levels' tiles of `keys` and tells HeightTiles whether
## it has sea (HeightTiles.know_sea). Blocks on the network the first time for a cell: a worker's job.
func know_sea_under(keys: Array[Vector3i]) -> void:
	var cells := {}
	for k in keys:
		if zooms.size() > 1 and k.x != zooms[0] and k.x != zooms[1]:
			continue
		for c in cells_under(k):
			cells[c] = true
	for c: Vector2i in cells:
		_lock.lock()
		var asked := _asked.has(c)
		_asked[c] = true
		_lock.unlock()
		if asked:
			continue
		# (a guessed profile only knows the sea where the game has the cell: none of it is taken, the sea stays as it was)
		var p := PlaceProfile.of_cell(c)
		if not bool(p.get("guessed", true)):
			HeightTiles.know_sea(c, float(p.get("sea", 0.0)) > 0.0 or bool(p.get("coast", false)))


func _was_asked(c: Vector2i) -> bool:
	_lock.lock()
	var yes := _asked.has(c)
	_lock.unlock()
	return yes


## The cells (RealRegion.cell_of) tile `key` lies over.
static func cells_under(key: Vector3i) -> Array[Vector2i]:
	var b := HeightTiles.geo_box(key)
	var lo := RealRegion.cell_of(b.x, b.y)
	var hi := RealRegion.cell_of(b.z - 1e-9, b.w - 1e-9)
	var out: Array[Vector2i] = []
	for r in range(lo.x, hi.x + 1):
		for c in range(lo.y, hi.y + 1):
			out.append(Vector2i(r, c))
	return out


## Whether the sea may be anywhere along the ride: false once the place profiles of every cell under its road's fine
## tiles are known and none has any (a polder below sea level is no reason to draw the sea). A baked region: true.
func has_sea() -> bool:
	if not live or _base.is_empty():
		return true
	var any := false
	for k: Vector3i in _base[0]:
		for c in cells_under(k):
			any = true
			if HeightTiles.sea_in(c) != 0:
				return true
	return not any


# ---------------------------------------------------------------------------- asked by position

## [lat, lon] in degrees of route-frame (x, z) (doubles: a Vector2's floats are half a metre out).
func to_geo(x: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([lat0 - z / _m.x, lon0 + x / _m.y])


## Route-frame (x, z) of (lat, lon).
func from_geo(lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * _m.y, -(lat - lat0) * _m.x)


## Whether the heights over route-frame `area` are final at live level `level` (0 fine, 1 middle, 2 ridge): every tile of
## it there is in. Always for baked land.
func ready(area: Rect2, level := 0) -> bool:
	if not live:
		return true
	if level < 0 or level >= zooms.size():
		return false
	var zm := zooms[level]
	var a := to_geo(area.position.x, area.position.y)
	var b := to_geo(area.end.x, area.end.y)
	for ty in range(floori(HeightTiles.mercator_y(a[0], zm)), floori(HeightTiles.mercator_y(b[0], zm)) + 1):
		for tx in range(floori(HeightTiles.mercator_x(a[1], zm)), floori(HeightTiles.mercator_x(b[1], zm)) + 1):
			var key := Vector3i(zm, tx, ty)
			if not _uses(level, key) or not HeightTiles.has(key):
				return false
	return true


## Whether route-frame (x, z) is open sea: under the shore in a cell whose profile has sea (HeightTiles.know_sea).
## Baked land: at or under the sea's level there.
func sea_at(x: float, z: float) -> bool:
	if not live:
		var h := height(x, z)
		return not is_nan(h) and h <= 0.0 and cover(x, z) != RealPack.WATER
	var g := to_geo(x, z)
	for li in zooms.size():
		var zm := zooms[li]
		var mx := HeightTiles.mercator_x(g[1], zm)
		var my := HeightTiles.mercator_y(g[0], zm)
		var key := Vector3i(zm, floori(mx), floori(my))
		var t: HeightTiles.Tile = HeightTiles.tile(key) if _uses(li, key) else null
		if t != null:
			return t.is_sea(clampi(int((mx - key.y) * t.size), 0, t.size - 1), clampi(int((my - key.z) * t.size), 0, t.size - 1))
	return false


## Route-frame box of tile `key`.
func key_box(key: Vector3i) -> Rect2:
	var b := HeightTiles.geo_box(key)
	var nw := from_geo(b.z, b.y)
	var se := from_geo(b.x, b.w)
	return Rect2(nw, se - nw)


# ---------------------------------------------------------------------------- round the riders

## The tiles wanted round `riders` ([Vector4(x, z, vx, vz)], route frame) at each of `zooms`: per level, the ring of
## `reach[li]` round each rider, then the strip `ahead[li]` long (`wide[li]` either side) down the way of each that is
## moving, nearest first. Pure: the fetch rule.
static func ring_keys(riders: Array, zms: PackedInt32Array, lat: float, lon: float, reach: Array, ahead: Array, wide: Array) -> Array:
	var out: Array = []
	var m := metres_per_degree(lat)
	for li in zms.size():
		var ring := PackedVector2Array()
		var strip := PackedVector2Array()
		for r: Vector4 in riders:
			ring.append(Vector2(r.x, r.y))
			var v := Vector2(r.z, r.w)
			if v.length() > MOVING and float(ahead[li]) > 0.0:
				var d := AHEAD_STEP
				while d <= float(ahead[li]) + 1.0:
					strip.append(Vector2(r.x, r.y) + v.normalized() * d)
					d += AHEAD_STEP
		var found := {}
		var list: Array[Vector3i] = []
		for k in HeightTiles.keys_near(ring, float(reach[li]), zms[li], lat, lon):
			found[k] = true
			list.append(k)
		var more: Array[Vector3i] = []
		if not strip.is_empty():
			for k in HeightTiles.keys_near(strip, float(wide[li]), zms[li], lat, lon):
				if not found.has(k):
					found[k] = true
					more.append(k)
		var near := func(a: Vector3i, b: Vector3i) -> bool:
			return _nearest_rider(riders, a, zms[li], lat, lon, m) < _nearest_rider(riders, b, zms[li], lat, lon, m)
		list.sort_custom(near)
		more.sort_custom(near)
		list.append_array(more)
		out.append(list)
	return out


## How far (m) the middle of tile `key` is from the nearest of `riders`.
static func _nearest_rider(riders: Array, key: Vector3i, zm: int, lat: float, lon: float, m: Vector2) -> float:
	var b := HeightTiles.geo_box(key)
	var mid := Vector2(((b.y + b.w) * 0.5 - lon) * m.y, -((b.x + b.z) * 0.5 - lat) * m.x)
	var best := INF
	for r: Vector4 in riders:
		best = minf(best, mid.distance_to(Vector2(r.x, r.y)))
	return best


## Keeps the ground coming round `riders` ([Vector4(x, z, vx, vz)], route frame, m and m/s; your own first): takes in
## the tiles of the ring and strip round them (ring_keys) that are on disk, has the rest fetched on a worker, and lets go
## those every rider is past KEEP of. Emits ground_arrived for each tile taken in. Main thread; cheap to call every frame.
func follow_riders(riders: Array) -> void:
	if not live or uses.is_empty() or riders.is_empty():
		return
	_last_riders = riders
	if _job >= 0:
		if not WorkerThreadPool.is_task_completed(_job):
			_job_moved = _job_moved or _moved(riders)
			return
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		_take(_job_keys, riders)
		if not _job_moved and not _moved(riders):
			return
	elif not _moved(riders):
		return
	_job_moved = false
	_riders_at = riders.duplicate()
	var want := ring_keys(riders, zooms, lat0, lon0, LIVE_REACH, AHEAD, AHEAD_WIDE)
	var keep := ring_keys(riders, zooms, lat0, lon0, KEEP, AHEAD, AHEAD_WIDE)
	# Let go of what every rider is past.
	var keep_set := {}
	for li in keep.size():
		for k: Vector3i in keep[li]:
			keep_set[k] = true
	var gone: Array[Vector3i] = []
	for k: Vector3i in _ring:
		if not keep_set.has(k):
			gone.append(k)
	if not gone.is_empty():
		_lock.lock()
		for k in gone:
			var li: int = _ring[k]
			_ring.erase(k)
			if not (_base[li] as Dictionary).has(k):
				(uses[li] as Dictionary).erase(k)
		_lock.unlock()
	_forget_far_ridges(riders)
	# Take in what's to hand; fetch the rest, nearest first.
	var to_hand: Array[Vector3i] = []
	var fetch: Array[Vector3i] = []
	for li in want.size():
		for k: Vector3i in want[li]:
			if _uses(li, k):
				continue
			if HeightTiles.has(k) and (li == 2 or cells_under(k).all(_was_asked)):
				to_hand.append(k)
			else:
				fetch.append(k)
	_take(to_hand, riders)
	if fetch.is_empty():
		return
	_job_keys = fetch
	if not threaded:
		_fetch_job(fetch)
		_take(fetch, riders)
		return
	_job = WorkerThreadPool.add_task(_fetch_job.bind(fetch), false, "Terrain round the riders")


## The worker's part: the profiles of the cells under the tiles first (their sea), then the tiles, nearest first.
func _fetch_job(keys: Array[Vector3i]) -> void:
	know_sea_under(keys)
	var order: Array[Vector3i] = keys.duplicate()
	order.reverse()   # (HeightTiles.fetch starts from the end)
	if fetcher.is_valid():
		fetcher.call(order, Callable())
	else:
		HeightTiles.fetch(order)


## Takes in those of `keys` that are on disk now and still wanted (within KEEP of a rider), and says where.
func _take(keys: Array[Vector3i], riders: Array) -> void:
	var m := _m
	var got: Array[Vector3i] = []
	_lock.lock()
	for k in keys:
		var li := zooms.find(k.x)
		if li < 0 or (uses[li] as Dictionary).has(k) or not HeightTiles.has(k):
			continue
		if _nearest_rider(riders, k, k.x, lat0, lon0, m) > float(KEEP[li]) + float(AHEAD[li]) + key_box(k).size.length():
			continue
		_ring[k] = li
		(uses[li] as Dictionary)[k] = true
		got.append(k)
	_lock.unlock()
	for k in got:
		var li := zooms.find(k.x)
		var box := key_box(k)
		var grow := box.size.x * LIVE_EASE_PX / 512.0
		if li == 2:
			_forget_ridges(box.grow(grow))
		_forget_water(box.grow(grow))
		ground_arrived.emit(box.grow(grow), li)


## Whether any rider has moved MOVE_AGAIN or turned TURN_AGAIN since follow_riders last worked (or the crew changed).
func _moved(riders: Array) -> bool:
	if riders.size() != _riders_at.size():
		return true
	for i in riders.size():
		var a: Vector4 = riders[i]
		var b: Vector4 = _riders_at[i]
		if Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) > MOVE_AGAIN:
			return true
		var va := Vector2(a.z, a.w)
		var vb := Vector2(b.z, b.w)
		if (va.length() > MOVING) != (vb.length() > MOVING):
			return true
		if va.length() > MOVING and absf(angle_difference(va.angle(), vb.angle())) > TURN_AGAIN:
			return true
	return false


## Lets go of the worked-out ridge tiles over `area`, so they are worked out again from the new tiles.
func _forget_ridges(area: Rect2) -> void:
	var size := ridge_cells() * ridge_spacing()
	_lock.lock()
	for key: Vector2i in _ridge_tiles.keys():
		if Rect2(key.x * size, key.y * size, size, size).intersects(area):
			_ridge_tiles.erase(key)
	_lock.unlock()


## Lets go of the worked-out ridge tiles every rider is RIDGE_KEEP from.
func _forget_far_ridges(riders: Array) -> void:
	var size := ridge_cells() * ridge_spacing()
	_lock.lock()
	for key: Vector2i in _ridge_tiles.keys():
		var mid := Vector2((key.x + 0.5) * size, (key.y + 0.5) * size)
		if riders.all(func(r: Vector4): return mid.distance_to(Vector2(r.x, r.y)) > RIDGE_KEEP):
			_ridge_tiles.erase(key)
	_lock.unlock()


## How many tiles of each level the ride holds now, and how many it took in round the riders (for tests and the debug
## overlay): {uses: [fine, middle, ridge], ring: n}.
func held() -> Dictionary:
	_lock.lock()
	var out := {"uses": uses.map(func(d: Dictionary): return d.size()), "ring": _ring.size()}
	_lock.unlock()
	return out


## Waits for the worker fetching round the riders (the tests, and before the ride is let go).
func settle() -> void:
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		_take(_job_keys, _last_riders)


## Fetches the middle and ridge levels' tiles over route-frame `area` (the map's picture of a live region). Blocks.
func fetch_area(area: Rect2) -> int:
	if not live:
		return 0
	var pts := PackedVector2Array()
	var x := area.position.x
	while x <= area.end.x + 2000.0:
		var z := area.position.y
		while z <= area.end.y + 2000.0:
			pts.append(Vector2(x, z))
			z += 2000.0
		x += 2000.0
	var keys: Array[Vector3i] = []
	for li in [1, 2]:
		keys.append_array(HeightTiles.keys_near(pts, 1000.0, zooms[li], lat0, lon0))
	return HeightTiles.fetch(keys)


## Reads cover from cell `cell_dir` too, wherever its box is (its region.json `meta`: frame, geo box, levels).
func add_cover_cell(cell_dir: String, meta: Dictionary) -> void:
	var lvls: Array = []
	for lm: Dictionary in meta.get("levels", []):
		if not bool(lm.get("cover", false)):
			continue
		var lv := Level.new()
		lv.folder = str(lm["dir"])
		lv.spacing = float(lm["spacing"])
		lv.cells = int(lm["n"])
		lv.has_cover = true
		lv.base = cell_dir
		lvls.append(lv)
	lvls.sort_custom(func(a: Level, b: Level): return a.spacing < b.spacing)   # (the finest that has a point answers)
	var geo: Dictionary = meta["geo"]
	var lat := float(meta["frame"]["lat"])
	_cover_cells.append({"levels": lvls, "lat": lat, "lon": float(meta["frame"]["lon"]), "m": metres_per_degree(lat),
		"south": float(geo["south"]), "west": float(geo["west"]), "north": float(geo["north"]), "east": float(geo["east"])})


## Takes in a cell's trees (tools/tree_bake.py: {cell: "ROW_COL", rows, cols, trees, leaf}, the last two base64 of
## zlib'd bytes). One that won't read is left out.
func add_trees(row: Dictionary) -> void:
	var name := str(row.get("cell", "")).split("_")
	var rows := int(row.get("rows", 0))
	var cols := int(row.get("cols", 0))
	if name.size() != 2 or rows <= 0 or cols <= 0:
		return
	var trees := Marshalls.base64_to_raw(str(row.get("trees", ""))).decompress(rows * cols, FileAccess.COMPRESSION_DEFLATE)
	var leaf := Marshalls.base64_to_raw(str(row.get("leaf", ""))).decompress(rows * cols, FileAccess.COMPRESSION_DEFLATE)
	if trees.size() != rows * cols:
		return
	if leaf.size() != rows * cols:
		leaf = PackedByteArray()
	var south := int(name[0]) * RealRegion.CELL_DEG - 90.0
	var west := int(name[1]) * RealRegion.CELL_DEG - 180.0
	_tree_cells.append({"south": south, "west": west, "north": south + RealRegion.CELL_DEG, "east": west + RealRegion.CELL_DEG,
		"rows": rows, "cols": cols, "trees": trees, "leaf": leaf})


## Whether it has any cell's trees (add_trees).
func has_trees() -> bool:
	return not _tree_cells.is_empty()


## The trees at route-frame (x, z) (tools/tree_bake.py): the trees byte (its low 5 bits the canopy's height in
## tree_bake's HEIGHT_STEP, its top 3 how much of the square is under trees in eighths) with the leaf's id over it
## (times 256: RealPack.LEAVES), or -1 where no cell's trees have the point.
func trees_at(x: float, z: float) -> int:
	if _tree_cells.is_empty():
		return -1
	var lat := lat0 - z / _m.x
	var lon := lon0 + x / _m.y
	for c: Dictionary in _tree_cells:
		var s: float = c["south"]
		var w: float = c["west"]
		if lat >= s and lat < float(c["north"]) and lon >= w and lon < float(c["east"]):
			var rows: int = c["rows"]
			var cols: int = c["cols"]
			var r := clampi(int((float(c["north"]) - lat) / RealRegion.CELL_DEG * rows), 0, rows - 1)
			var k := r * cols + clampi(int((lon - w) / RealRegion.CELL_DEG * cols), 0, cols - 1)
			var leaf: PackedByteArray = c["leaf"]
			return int((c["trees"] as PackedByteArray)[k]) + (int(leaf[k]) * 256 if not leaf.is_empty() else 0)
	return -1


## The buildings whose ground the live heights level (RealRegion.buildings rows: [x, z, w, d, yaw, ...]).
func set_buildings(rows: Array) -> void:
	_pads = rows
	_pad_grid = {}
	_pad_level = {}
	for i in rows.size():
		var b: Array = rows[i]
		var r := Vector2(float(b[2]), float(b[3])).length() * 0.5 + PAD_MARGIN + PAD_FEATHER
		for gz in range(floori((float(b[1]) - r) / PAD_CELL), floori((float(b[1]) + r) / PAD_CELL) + 1):
			for gx in range(floori((float(b[0]) - r) / PAD_CELL), floori((float(b[0]) + r) / PAD_CELL) + 1):
				var key := Vector2i(gx, gz)
				if not _pad_grid.has(key):
					_pad_grid[key] = PackedInt32Array()
				var list: PackedInt32Array = _pad_grid[key]
				list.append(i)
				_pad_grid[key] = list


## The tile of live level `li` under (lat, lon) that the ride uses, or (-1, -1, -1).
func _live_key(li: int, lat: float, lon: float) -> Vector3i:
	var key := Vector3i(zooms[li], floori(HeightTiles.mercator_x(lon, zooms[li])), floori(HeightTiles.mercator_y(lat, zooms[li])))
	if not uses.is_empty() and not _uses(li, key):
		return Vector3i(-1, -1, -1)
	return key


func _uses(li: int, key: Vector3i) -> bool:
	if uses.is_empty():
		return HeightTiles.has(key)
	_lock.lock()
	var yes := (uses[li] as Dictionary).has(key)
	_lock.unlock()
	return yes


func _live_height(x: float, z: float) -> float:
	var lat := lat0 - z / _m.x
	var lon := lon0 + x / _m.y
	var h := _live_level(0, lat, lon, true)
	if is_nan(h):
		return NAN
	return _on_pads(x, z, h) if not _pad_grid.is_empty() else h


## Level `li`'s height at (lat, lon), eased into the next level's where its tiles end (when `ease`), else the next's.
func _live_level(li: int, lat: float, lon: float, ease: bool) -> float:
	if li >= zooms.size():
		return NAN
	var zm := zooms[li]
	var mx := HeightTiles.mercator_x(lon, zm)
	var my := HeightTiles.mercator_y(lat, zm)
	var key := Vector3i(zm, floori(mx), floori(my))
	var t: HeightTiles.Tile = HeightTiles.tile(key) if _uses(li, key) else null
	if t == null:
		return _live_level(li + 1, lat, lon, ease)
	var u := (mx - key.y) * t.size
	var v := (my - key.z) * t.size
	var h := _bilinear(key, t, u - 0.5, v - 0.5)
	if not ease or li + 1 >= zooms.size():
		return h
	var w := _edge_weight(li, key, u, v, t.size)
	if w <= 0.0:
		return h
	var below := _live_level(li + 1, lat, lon, true)
	return h if is_nan(below) else lerpf(h, below, w)


## Bilinear between the pixels round (fx, fy) of tile `t`, reaching into the next tile past its edge (or holding the edge
## pixel where there is none).
func _bilinear(key: Vector3i, t: HeightTiles.Tile, fx: float, fy: float) -> float:
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	if ix >= 0 and iy >= 0 and ix + 1 < t.size and iy + 1 < t.size:
		return lerpf(lerpf(t.at(ix, iy), t.at(ix + 1, iy), tx), lerpf(t.at(ix, iy + 1), t.at(ix + 1, iy + 1), tx), ty)
	return lerpf(lerpf(_pixel(key, t, ix, iy), _pixel(key, t, ix + 1, iy), tx), lerpf(_pixel(key, t, ix, iy + 1), _pixel(key, t, ix + 1, iy + 1), tx), ty)


func _pixel(key: Vector3i, t: HeightTiles.Tile, i: int, j: int) -> float:
	var dx := floori(float(i) / t.size)
	var dy := floori(float(j) / t.size)
	if dx == 0 and dy == 0:
		return t.at(i, j)
	var other := HeightTiles.tile(Vector3i(key.x, key.y + dx, key.z + dy))
	if other == null or other.size != t.size:
		return t.at(clampi(i, 0, t.size - 1), clampi(j, 0, t.size - 1))
	return other.at(posmod(i, t.size), posmod(j, t.size))


## How much of the next level a sample at pixel (u, v) of tile `key` takes: 0 inside the ride's tiles, rising to 1 at
## an edge (or a corner) with no tile of the ride's beyond it, or one there is none of (HeightTiles.is_none: no fine
## survey there), so a fine tile next to a gap meets the coarser level there with no step (tools/route_bake.py
## blend_edges).
func _edge_weight(li: int, key: Vector3i, u: float, v: float, size: int) -> float:
	var f := LIVE_EASE_PX * size / 512.0
	var w := 0.0
	var near_w := u < f
	var near_e := size - u < f
	var near_n := v < f
	var near_s := size - v < f
	if not (near_w or near_e or near_n or near_s):
		return 0.0
	if near_w and not _has_ground(li, key + Vector3i(0, -1, 0)):
		w = maxf(w, 1.0 - smoothstep(0.0, f, u))
	if near_e and not _has_ground(li, key + Vector3i(0, 1, 0)):
		w = maxf(w, 1.0 - smoothstep(0.0, f, size - u))
	if near_n and not _has_ground(li, key + Vector3i(0, 0, -1)):
		w = maxf(w, 1.0 - smoothstep(0.0, f, v))
	if near_s and not _has_ground(li, key + Vector3i(0, 0, 1)):
		w = maxf(w, 1.0 - smoothstep(0.0, f, size - v))
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var cu := u if d.x < 0 else size - u
		var cv := v if d.y < 0 else size - v
		if cu < f and cv < f and not _has_ground(li, key + Vector3i(0, d.x, d.y)):
			w = maxf(w, 1.0 - smoothstep(0.0, f, maxf(cu, cv)))
	return w


## Whether the ride uses tile `key` of level `li` and it has ground (not one there is none of).
func _has_ground(li: int, key: Vector3i) -> bool:
	return _uses(li, key) and not HeightTiles.is_none(key)


## `h` at route-frame (x, z) levelled under any building there, feathered into the land round it
## (tools/land_bake.py level_ground).
func _on_pads(x: float, z: float, h: float) -> float:
	var list: PackedInt32Array = _pad_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
	for i in list:
		var b: Array = _pads[i]
		var c := cos(float(b[4]))
		var s := sin(float(b[4]))
		var px := x - float(b[0])
		var pz := z - float(b[1])
		var lx := px * c - pz * s
		var lz := px * s + pz * c
		var dist := Vector2(maxf(absf(lx) - float(b[2]) * 0.5 - PAD_MARGIN, 0.0), maxf(absf(lz) - float(b[3]) * 0.5 - PAD_MARGIN, 0.0)).length()
		if dist >= PAD_FEATHER:
			continue
		var level := _pad_ground(i)
		if is_nan(level):
			continue
		var t := 1.0 - dist / PAD_FEATHER
		h += (level - h) * t * t * (3.0 - 2.0 * t)
	return h


## Building `i`'s ground: the mean of the bare land over its footprint (and margin), every 4 m, worked out once.
func _pad_ground(i: int) -> float:
	_lock.lock()
	var known: float = _pad_level.get(i, NAN)
	_lock.unlock()
	if not is_nan(known):
		return known
	var b: Array = _pads[i]
	var c := cos(float(b[4]))
	var s := sin(float(b[4]))
	var hw := float(b[2]) * 0.5 + PAD_MARGIN
	var hd := float(b[3]) * 0.5 + PAD_MARGIN
	var total := 0.0
	var n := 0
	var lx := -hw
	while lx <= hw:
		var lz := -hd
		while lz <= hd:
			# (local to the building, back to the frame: the inverse of _on_pads' turn)
			var h := _live_level(0, lat0 - (float(b[1]) - lx * s + lz * c) / _m.x, lon0 + (float(b[0]) + lx * c + lz * s) / _m.y, true)
			if not is_nan(h):
				total += h
				n += 1
			lz += 4.0
		lx += 4.0
	var level := total / n if n > 0 else NAN
	_lock.lock()
	_pad_level[i] = level   # (two threads may both work it out: they get the same answer)
	_lock.unlock()
	return level


## The live ridge level's tile `key` (ridge_cells() x ridge_cells() samples, ridge_spacing() apart), sampled from the
## ridge zoom, the sea just under the water as the baker has it. Worked out once per ride.
func _live_ridge_tile(key: Vector2i) -> PackedFloat32Array:
	_lock.lock()
	if _ridge_tiles.has(key):
		var got: PackedFloat32Array = _ridge_tiles[key]
		_lock.unlock()
		return got
	_lock.unlock()
	var n := ridge_cells()
	var sp := ridge_spacing()
	var out := PackedFloat32Array()
	out.resize(n * n)
	var any := false
	for j in n:
		var lat := lat0 - (key.y * n + j) * sp / _m.x
		for i in n:
			var h := _live_level(2, lat, lon0 + (key.x * n + i) * sp / _m.y, false)
			if not is_nan(h):
				any = true
				if h <= 0.0:
					h = minf(h, RIDGE_SEA)
			out[j * n + i] = h
	if not any:
		out = PackedFloat32Array()
	_lock.lock()
	_ridge_tiles[key] = out
	_lock.unlock()
	return out
