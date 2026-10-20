class_name RealTerrain
extends RefCounted
## The land of a real road (see RealPack, tools/route_bake.py): ground heights in metres above sea level at
## any point in the route's frame, from 512 m tiles of 128 x 128 samples baked down the corridor either side of
## the road. Tiles are read from disk the first time they are needed and kept. Safe to ask from worker threads
## (the adventure's chunks are built on them): a tile is read under a lock and never changed afterwards.
##
## height() is bilinear between samples; it is NAN where there is no tile (beyond the corridor), and the road's
## own planner falls back to the lie of the land it has there.

var dir := ""
var tile_m := 512.0
var cells := 128
var spacing := 4.0
var h_min := -256.0
var h_scale := 0.0625
var _tiles := {}          # Vector2i -> PackedFloat32Array (empty when there is no such tile)
var _covers := {}         # Vector2i -> PackedByteArray (empty when there is no such tile)
var _lock := Mutex.new()


func _init(tiles_dir := "", meta: Dictionary = {}) -> void:
	dir = tiles_dir
	if not meta.is_empty():
		tile_m = float(meta["tile"]["size_m"])
		cells = int(meta["tile"]["n"])
		spacing = float(meta["tile"]["spacing"])
		h_min = float(meta["height"]["min"])
		h_scale = float(meta["height"]["scale"])


## The ground's height at route-frame (x, z), metres above sea level, or NAN with no tile there.
func height(x: float, z: float) -> float:
	var fx := x / spacing
	var fz := z / spacing
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var a := _cell(ix, iz)
	var b := _cell(ix + 1, iz)
	var c := _cell(ix, iz + 1)
	var d := _cell(ix + 1, iz + 1)
	if is_nan(a) or is_nan(b) or is_nan(c) or is_nan(d):
		# On a tile's edge next to a missing one: use what is there.
		var known := [a, b, c, d].filter(func(v): return not is_nan(v))
		if known.is_empty():
			return NAN
		var sum := 0.0
		for v: float in known:
			sum += v
		return sum / known.size()
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## What covers the ground at route-frame (x, z): an id into the pack's "cover" list (RealPack.COVER), or -1 with
## no tile there. The sample nearest to (x, z).
func cover(x: float, z: float) -> int:
	var ix := roundi(x / spacing)
	var iz := roundi(z / spacing)
	var key := Vector2i(floori(float(ix) / cells), floori(float(iz) / cells))
	var t: PackedByteArray = _cover_tile(key)
	if t.is_empty():
		return -1
	return t[posmod(iz, cells) * cells + posmod(ix, cells)]


func _cover_tile(key: Vector2i) -> PackedByteArray:
	_lock.lock()
	if _covers.has(key):
		var got: PackedByteArray = _covers[key]
		_lock.unlock()
		return got
	var path := dir.path_join("%d_%d.cov" % [key.x, key.y])
	var out := PackedByteArray()
	if FileAccess.file_exists(path):
		var raw := FileAccess.get_file_as_bytes(path)
		if raw.size() == cells * cells:
			out = raw
	_covers[key] = out
	_lock.unlock()
	return out


## Whether the tile under route-frame (x, z) exists.
func has_tile_at(x: float, z: float) -> bool:
	return _tile(Vector2i(int(floor(x / tile_m)), int(floor(z / tile_m)))) != null


## The sample at grid index (ix, iz) over the whole route frame: NAN where there is no tile.
func _cell(ix: int, iz: int) -> float:
	var per := cells
	var key := Vector2i(floori(float(ix) / per), floori(float(iz) / per))
	var t: PackedFloat32Array = _tile(key)
	if t.is_empty():
		return NAN
	return t[posmod(iz, per) * per + posmod(ix, per)]


func _tile(key: Vector2i) -> PackedFloat32Array:
	_lock.lock()
	if _tiles.has(key):
		var got: PackedFloat32Array = _tiles[key]
		_lock.unlock()
		return got
	var path := dir.path_join("%d_%d.u16" % [key.x, key.y])
	var out := PackedFloat32Array()
	if FileAccess.file_exists(path):
		var raw := FileAccess.get_file_as_bytes(path)
		if raw.size() == cells * cells * 2:
			out.resize(cells * cells)
			for i in cells * cells:
				out[i] = h_min + raw.decode_u16(i * 2) * h_scale
	_tiles[key] = out
	_lock.unlock()
	return out


## How many tiles are held (for tests).
func loaded_count() -> int:
	_lock.lock()
	var n := _tiles.size()
	_lock.unlock()
	return n
