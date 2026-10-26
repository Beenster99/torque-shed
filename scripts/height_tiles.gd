class_name HeightTiles
extends RefCounted
## The world's ground heights as web-mercator map tiles (Terrarium: height = R * 256 + G + B / 256 - 32768 metres), from
## Mapterhorn (tiles.mapterhorn.com, 512 px webp), else AWS's Terrain Tiles (256 px png), the same sources
## tools/route_bake.py bakes from. A region whose heights are "live" (RealTerrain) reads them from here instead of from
## baked tiles of its own.
##
## Tiles are kept on disk under `disk` (and read from any folder in `dirs`, the tests' fixtures among them) and decoded
## into memory the first time they are sampled, a few at most per frame. fetch() fills the disk from the network and
## blocks while it does, so it is called on a worker (RoutePlanner, before the road's heights are worked out); the
## samplers never touch the network. Safe from any thread.

const MAPTERHORN := "https://tiles.mapterhorn.com/%d/%d/%d.webp"
const AWS := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const USER_AGENT := "TorqueShed (+https://github.com/Beenster99/torque-shed)"
## Where fetched tiles are kept (the tests keep theirs elsewhere).
static var disk := "user://heights"
## Decoded tiles kept in memory (a 512 px tile is 768 KB): a long ride's near tiles and their surroundings.
const MEMORY := 160
## Fetches at once.
const AT_ONCE := 6
const TIMEOUT_MS := 30000
## Ground at or under this (m) is sea (Mapterhorn holds 0 over the sea); a tile with fewer sea pixels than SEA_MIN
## has a pond or a harbour, not sea. The sea is given a floor that slopes down from the shore to SEA_DEPTH, as the
## baker does (route_bake.shape_sea). Only in a cell whose place profile has sea, though, once that's known
## (know_sea): land below sea level in a cell with none (a polder) is land at its own height.
const SEA_ABS := 0.4
const SEA_MIN := 400
const SEA_DEPTH := 35.0
## The sea mask is smoothed by shrinking the tile to this many cells a side and back (Godot does it natively).
const SEA_CELLS := 16

## Folders searched for a tile, after `disk`.
static var dirs: Array[String] = ["res://data/heights"]
## No network: tiles that aren't on disk stay missing (the tests).
static var offline := false
## At most this many fetched tiles are kept on disk (about 100 KB each: a long ride wants a thousand or so): past it, the
## ones fetched longest ago go (prune), never one this game has asked for since it started (its ride may want it).
static var keep := 10000
static var _used_now := {}   # Vector3i -> true

static var _lock := Mutex.new()
static var _mem := {}        # Vector3i(z, x, y) -> Tile
static var _missing := {}    # Vector3i -> true: not on disk when last looked (fetch() clears it)
static var _tick := 0
## Whether each cell (RealRegion.cell_of: Vector2i(row, col)) has sea, from its place profile (know_sea). A cell not in
## here is taken to have it, as before profiles: ground at or under SEA_ABS is sea.
static var _sea_cells := {}


class Tile:
	extends RefCounted
	var size := 512
	var rgb := PackedByteArray()    # size x size x 3
	var sea := PackedByteArray()    # size x size smoothed sea mask (0 to 255), empty when the tile has no sea
	var used := 0

	## The ground height (m) at pixel (i, j), the sea given its floor.
	func at(i: int, j: int) -> float:
		var o := (j * size + i) * 3
		var h := rgb[o] * 256.0 + rgb[o + 1] + rgb[o + 2] / 256.0 - 32768.0
		if h <= SEA_ABS and not sea.is_empty() and sea[j * size + i] > 0:
			h = -(2.0 + (SEA_DEPTH - 2.0) * clampf(sea[j * size + i] / 255.0 * 1.6, 0.0, 1.0))
		return h

	## Whether pixel (i, j) is open sea.
	func is_sea(i: int, j: int) -> bool:
		if sea.is_empty() or sea[j * size + i] == 0:
			return false
		var o := (j * size + i) * 3
		return rgb[o] * 256.0 + rgb[o + 1] + rgb[o + 2] / 256.0 - 32768.0 <= SEA_ABS


## The smallest zoom whose pixels are no coarser than `spacing` metres at latitude `lat` (route_bake.tile_zoom).
static func zoom_for(lat: float, spacing: float, size := 512) -> int:
	var c := 40075016.686 * cos(deg_to_rad(lat))
	return clampi(ceili(log(c / (size * spacing)) / log(2.0)), 0, 15)


## The fractional position across the world's grid of tiles at `zoom` of longitude `lon` (the tile is its floor). In
## doubles: a Vector2's floats are a pixel out at zoom 14.
static func mercator_x(lon: float, zoom: int) -> float:
	return (lon + 180.0) / 360.0 * float(1 << zoom)


## The fractional position down the world's grid of tiles at `zoom` of latitude `lat`.
static func mercator_y(lat: float, zoom: int) -> float:
	var s := sin(deg_to_rad(clampf(lat, -85.05, 85.05)))
	return (0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI)) * float(1 << zoom)


## A decoded tile, read from disk the first time; null when there is none on disk.
static func tile(key: Vector3i) -> Tile:
	_lock.lock()
	var t: Tile = _mem.get(key)
	if t != null:
		_tick += 1
		t.used = _tick
		_lock.unlock()
		return t
	if _missing.has(key):
		_lock.unlock()
		return null
	_lock.unlock()
	var bytes := _read(key)
	t = decode(bytes, key) if not bytes.is_empty() else null
	_lock.lock()
	if t == null:
		_missing[key] = true
	elif _mem.has(key):
		t = _mem[key]   # (another thread got there first)
	else:
		_tick += 1
		t.used = _tick
		_mem[key] = t
		if _mem.size() > MEMORY:
			_forget_oldest()
	_lock.unlock()
	return t


## Whether tile `key` is on disk or in memory (without decoding it).
static func has(key: Vector3i) -> bool:
	_lock.lock()
	var known := _mem.has(key)
	var gone := _missing.has(key)
	_lock.unlock()
	if known:
		return true
	if gone:
		return false
	if _path_of(key) != "":
		return true
	_lock.lock()
	_missing[key] = true   # (until fetch() brings it)
	_lock.unlock()
	return false


## A tile from its file's bytes (webp or png): null when they are no good. `key` places it, for which cells have sea.
static func decode(bytes: PackedByteArray, key := Vector3i(-1, -1, -1)) -> Tile:
	var img := Image.new()
	var err := img.load_webp_from_buffer(bytes) if bytes.slice(8, 12).get_string_from_ascii() == "WEBP" else img.load_png_from_buffer(bytes)
	if err != OK or img.get_width() != img.get_height() or img.get_width() < 2:
		return null
	img.convert(Image.FORMAT_RGB8)
	var t := Tile.new()
	t.size = img.get_width()
	t.rgb = img.get_data()
	t.sea = _sea_mask(t, key)
	return t


## The tile's sea, smoothed so the floor slopes down from the shore: empty when it has none (or only a pond). Ground at
## or under SEA_ABS is sea only in a cell that has sea (know_sea); a pixel in one that hasn't is 0 (land), and one of
## the sea at least 1.
static func _sea_mask(t: Tile, key := Vector3i(-1, -1, -1)) -> PackedByteArray:
	var n := t.size * t.size
	var allowed := _sea_allowed(t.size, key)   # (empty: everywhere)
	if allowed.size() == 1:
		return PackedByteArray()   # (no cell under it has sea)
	var mask := PackedByteArray()
	mask.resize(n)
	var count := 0
	var limit := int((SEA_ABS + 32768.0) * 256.0)
	for p in n:
		var o := p * 3
		if t.rgb[o] * 65536 + t.rgb[o + 1] * 256 + t.rgb[o + 2] <= limit and (allowed.is_empty() or allowed[p] != 0):
			mask[p] = 255
			count += 1
	if count <= SEA_MIN * t.size * t.size / (512 * 512):
		return PackedByteArray()
	var img := Image.create_from_data(t.size, t.size, false, Image.FORMAT_L8, mask)
	img.resize(SEA_CELLS, SEA_CELLS, Image.INTERPOLATE_BILINEAR)
	img.resize(t.size, t.size, Image.INTERPOLATE_CUBIC)
	var out := img.get_data()
	for p in n:
		if mask[p] != 0:
			out[p] = maxi(out[p], 1)
		elif not allowed.is_empty() and allowed[p] == 0:
			out[p] = 0   # (the smoothing reaches over the cell's edge: none of it on the land)
	return out


## Which pixels of tile `key` (`size` a side) lie in a cell that may have sea: empty when they all may (or the tile isn't
## placed), a single 0 when none may, else size x size of 0 or 1.
static func _sea_allowed(size: int, key: Vector3i) -> PackedByteArray:
	if key.x < 0:
		return PackedByteArray()
	_lock.lock()
	var known := _sea_cells.duplicate()
	_lock.unlock()
	if known.is_empty():
		return PackedByteArray()
	var scale := float(1 << key.x)
	var rows := PackedInt32Array()
	var cols := PackedInt32Array()
	rows.resize(size)
	cols.resize(size)
	for j in size:
		rows[j] = floori((lat_of(key.z + (j + 0.5) / size, key.x) + 90.0) / RealRegion.CELL_DEG)
	for i in size:
		cols[i] = floori(((key.y + (i + 0.5) / size) / scale * 360.0) / RealRegion.CELL_DEG)
	var seen := {}
	for r in range(rows[size - 1], rows[0] + 1):
		for c in range(cols[0], cols[size - 1] + 1):
			seen[known.get(Vector2i(r, c), true)] = true
	if not seen.has(false):
		return PackedByteArray()
	if not seen.has(true):
		return PackedByteArray([0])
	var out := PackedByteArray()
	out.resize(size * size)
	for j in size:
		for i in size:
			out[j * size + i] = 1 if known.get(Vector2i(rows[j], cols[i]), true) else 0
	return out


## Says whether cell `cell` (RealRegion.cell_of) has sea, from its place profile (sea > 0, or a coast). Tiles over it
## that were read before are read again, so their sea follows. Any thread; call it before the cell's tiles are sampled.
static func know_sea(cell: Vector2i, has_sea: bool) -> void:
	_lock.lock()
	var was = _sea_cells.get(cell)
	_sea_cells[cell] = has_sea
	if (was != null and bool(was) == has_sea) or (was == null and has_sea):
		_lock.unlock()
		return   # (no tile read so far is any different)
	for k: Vector3i in _mem.keys():
		var b := geo_box(k)   # (south, west, north, east)
		var s := RealRegion.CELL_DEG
		if b.z > cell.x * s - 90.0 and b.x < (cell.x + 1) * s - 90.0 and b.w > cell.y * s - 180.0 and b.y < (cell.y + 1) * s - 180.0:
			_mem.erase(k)
	_lock.unlock()


## Whether cell `cell` has sea: 1 yes, 0 no, -1 not known yet (taken as yes).
static func sea_in(cell: Vector2i) -> int:
	_lock.lock()
	var v = _sea_cells.get(cell)
	_lock.unlock()
	return -1 if v == null else (1 if v else 0)


## The latitude of the top of row `y` (fractional) of the grid of tiles at `zoom` (mercator_y's inverse).
static func lat_of(y: float, zoom: int) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y / float(1 << zoom)))))


## Tile `key`'s box in degrees: Vector4(south, west, north, east).
static func geo_box(key: Vector3i) -> Vector4:
	var scale := float(1 << key.x)
	return Vector4(lat_of(key.z + 1, key.x), key.y / scale * 360.0 - 180.0, lat_of(key.z, key.x), (key.y + 1) / scale * 360.0 - 180.0)


static func _forget_oldest() -> void:
	var oldest := Vector3i.ZERO
	var at := INF
	for k: Vector3i in _mem:
		var t: Tile = _mem[k]
		if t.used < at:
			at = t.used
			oldest = k
	_mem.erase(oldest)


static func _rel(key: Vector3i) -> String:
	return "%d/%d/%d" % [key.x, key.y, key.z]


## The file holding tile `key` (webp or png) in `disk` or `dirs`, or "".
static func _path_of(key: Vector3i) -> String:
	for root in [disk] + Array(dirs):
		for ext in [".webp", ".png"]:
			var p: String = str(root).path_join(_rel(key) + ext)
			if FileAccess.file_exists(p):
				return p
	return ""


static func _read(key: Vector3i) -> PackedByteArray:
	var p := _path_of(key)
	return FileAccess.get_file_as_bytes(p) if p != "" else PackedByteArray()


## The tiles at `zoom` within `reach` metres of any of `points` (route-frame x, z of a frame at (lat0, lon0)).
static func keys_near(points: PackedVector2Array, reach: float, zoom: int, lat0: float, lon0: float) -> Array[Vector3i]:
	var m := RealTerrain.metres_per_degree(lat0)
	var found := {}
	for p in points:
		var x0 := floori(mercator_x(lon0 + (p.x - reach) / m.y, zoom))
		var x1 := floori(mercator_x(lon0 + (p.x + reach) / m.y, zoom))
		var y0 := floori(mercator_y(lat0 - (p.y - reach) / m.x, zoom))
		var y1 := floori(mercator_y(lat0 - (p.y + reach) / m.x, zoom))
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				found[Vector3i(zoom, tx, ty)] = true
	var out: Array[Vector3i] = []
	for k: Vector3i in found:
		out.append(k)
	out.sort()
	return out


## Fetches the tiles of `keys` that aren't on disk yet, AT_ONCE at a time, and waits for them. Returns how many it
## couldn't get. Never call it on the main thread. `progress(done, total)` is called as they come.
static func fetch(keys: Array[Vector3i], progress := Callable()) -> int:
	var todo: Array[Vector3i] = []
	_lock.lock()
	for k in keys:
		_used_now[k] = true
	_lock.unlock()
	for k in keys:
		if not has(k):
			todo.append(k)
	if todo.is_empty() or offline:
		return todo.size() if offline else 0
	var failed := _fetch(todo, progress)
	prune()
	return failed


## Deletes the tiles in `disk` past `keep`, those fetched longest ago first; never one asked for this run. Returns
## how many went.
static func prune() -> int:
	var files: Array = []   # [when, path, key]
	var root := DirAccess.open(disk)
	if root == null:
		return 0
	for z in root.get_directories():
		var dz := DirAccess.open(disk.path_join(z))
		for x in dz.get_directories():
			var dx := DirAccess.open(disk.path_join(z).path_join(x))
			for fn in dx.get_files():
				var path := disk.path_join(z).path_join(x).path_join(fn)
				files.append([FileAccess.get_modified_time(path), path, Vector3i(int(z), int(x), int(fn.get_basename()))])
	if files.size() <= keep:
		return 0
	files.sort()
	var gone := 0
	_lock.lock()
	for f in files:
		if files.size() - gone <= keep:
			break
		if _used_now.has(f[2]) or _mem.has(f[2]):
			continue
		DirAccess.remove_absolute(f[1])
		_missing[f[2]] = true
		gone += 1
	_lock.unlock()
	return gone


static func _fetch(todo: Array[Vector3i], progress: Callable) -> int:
	var total := todo.size()
	var failed := 0
	var done := 0
	var clients: Array[Dictionary] = []
	while not todo.is_empty() or not clients.is_empty():
		while clients.size() < AT_ONCE and not todo.is_empty():
			clients.append(_start(todo.pop_back(), false))
		for c: Dictionary in clients.duplicate():
			var state := _poll(c)
			if state == 0:
				continue
			clients.erase(c)
			if state < 0 and not bool(c["aws"]):
				clients.append(_start(c["key"], true))   # Mapterhorn didn't have it: AWS's
				continue
			if state < 0:
				failed += 1
			done += 1
			if progress.is_valid():
				progress.call(done, total)
		OS.delay_msec(2)
	return failed


static func _start(key: Vector3i, aws: bool) -> Dictionary:
	var url := (AWS if aws else MAPTERHORN) % [key.x, key.y, key.z]
	var host := url.get_slice("/", 2)
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, 443, TLSOptions.client())
	return {"key": key, "aws": aws, "http": http, "path": url.substr(url.find("/", 8)), "sent": false, "body": PackedByteArray(),
		"err": err, "since": Time.get_ticks_msec()}


## Moves one fetch on: 0 while it runs, 1 when the tile is on disk, -1 when it failed.
static func _poll(c: Dictionary) -> int:
	var http: HTTPClient = c["http"]
	if int(c["err"]) != OK or Time.get_ticks_msec() - int(c["since"]) > TIMEOUT_MS:
		return -1
	http.poll()
	var st := http.get_status()
	if st == HTTPClient.STATUS_RESOLVING or st == HTTPClient.STATUS_CONNECTING or st == HTTPClient.STATUS_REQUESTING:
		return 0
	if st == HTTPClient.STATUS_CONNECTED and not bool(c["sent"]):
		c["sent"] = true
		c["err"] = http.request(HTTPClient.METHOD_GET, str(c["path"]), ["User-Agent: " + USER_AGENT])
		return 0
	if st == HTTPClient.STATUS_BODY:
		var body: PackedByteArray = c["body"]
		body.append_array(http.read_response_body_chunk())
		c["body"] = body   # (a packed array is a value: put back)
		return 0
	if st == HTTPClient.STATUS_CONNECTED and bool(c["sent"]):
		if http.get_response_code() != 200:
			return -1
		var body: PackedByteArray = c["body"]
		if decode(body) == null:
			return -1
		var key: Vector3i = c["key"]
		var path := disk.path_join(_rel(key) + (".png" if bool(c["aws"]) else ".webp"))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return -1
		f.store_buffer(body)
		f.close()
		_lock.lock()
		_missing.erase(key)
		_lock.unlock()
		return 1
	return -1   # (disconnected, or a connection or TLS error)


## Forgets every decoded tile, what was missing and which cells have sea (the tests, after changing `dirs`).
static func reset() -> void:
	_lock.lock()
	_mem.clear()
	_missing.clear()
	_sea_cells.clear()
	_lock.unlock()
