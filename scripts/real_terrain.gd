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

class Level:
	extends RefCounted
	var folder := ""
	var spacing := 4.0
	var cells := 128
	var h_min := -256.0
	var h_scale := 0.0625
	var has_cover := false
	var tiles := {}    # Vector2i -> PackedFloat32Array (empty when there is no such tile)
	var covers := {}   # Vector2i -> PackedByteArray (empty when there is no such tile)

	func size_m() -> float:
		return spacing * cells

var dir := ""
var levels: Array[Level] = []
var _lock := Mutex.new()


func _init(pack_dir := "", meta: Dictionary = {}) -> void:
	dir = pack_dir
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
	for lv in levels:
		var h := _level_height(lv, x, z)
		if not is_nan(h):
			return h
	return NAN


## The finest level's height at (x, z) only (for tests and the baker's checks), or NAN.
func height_at_level(level: int, x: float, z: float) -> float:
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


## What covers the ground at route-frame (x, z): an id into the pack's "cover" list (RealPack.COVER), or -1 where no
## level with cover has it. The sample nearest to (x, z), from the finest level that has it.
func cover(x: float, z: float) -> int:
	for lv in levels:
		if not lv.has_cover:
			continue
		var ix := roundi(x / lv.spacing)
		var iz := roundi(z / lv.spacing)
		var t: PackedByteArray = _cover_tile(lv, Vector2i(floori(float(ix) / lv.cells), floori(float(iz) / lv.cells)))
		if not t.is_empty():
			return t[posmod(iz, lv.cells) * lv.cells + posmod(ix, lv.cells)]
	return -1


## Whether a fine tile is under route-frame (x, z).
func has_tile_at(x: float, z: float) -> bool:
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
	var path := dir.path_join(lv.folder).path_join("%d_%d.covz" % [key.x, key.y])
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
	return _tile(levels[-1], key) if not levels.is_empty() else PackedFloat32Array()


func ridge_spacing() -> float:
	return levels[-1].spacing if not levels.is_empty() else 128.0


func ridge_cells() -> int:
	return levels[-1].cells if not levels.is_empty() else 256


## How many fine tiles are held (for tests).
func loaded_count() -> int:
	if levels.is_empty():
		return 0
	_lock.lock()
	var n := levels[0].tiles.size()
	_lock.unlock()
	return n
