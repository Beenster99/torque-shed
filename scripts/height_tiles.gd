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
## baker does (route_bake.shape_sea).
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
		if h <= SEA_ABS and not sea.is_empty():
			h = -(2.0 + (SEA_DEPTH - 2.0) * clampf(sea[j * size + i] / 255.0 * 1.6, 0.0, 1.0))
		return h


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
	t = decode(bytes) if not bytes.is_empty() else null
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


## A tile from its file's bytes (webp or png): null when they are no good.
static func decode(bytes: PackedByteArray) -> Tile:
	var img := Image.new()
	var err := img.load_webp_from_buffer(bytes) if bytes.slice(8, 12).get_string_from_ascii() == "WEBP" else img.load_png_from_buffer(bytes)
	if err != OK or img.get_width() != img.get_height() or img.get_width() < 2:
		return null
	img.convert(Image.FORMAT_RGB8)
	var t := Tile.new()
	t.size = img.get_width()
	t.rgb = img.get_data()
	t.sea = _sea_mask(t)
	return t


## The tile's sea, smoothed so the floor slopes down from the shore: empty when it has none (or only a pond).
static func _sea_mask(t: Tile) -> PackedByteArray:
	var n := t.size * t.size
	var mask := PackedByteArray()
	mask.resize(n)
	var count := 0
	var limit := int((SEA_ABS + 32768.0) * 256.0)
	for p in n:
		var o := p * 3
		if t.rgb[o] * 65536 + t.rgb[o + 1] * 256 + t.rgb[o + 2] <= limit:
			mask[p] = 255
			count += 1
	if count <= SEA_MIN * t.size * t.size / (512 * 512):
		return PackedByteArray()
	var img := Image.create_from_data(t.size, t.size, false, Image.FORMAT_L8, mask)
	img.resize(SEA_CELLS, SEA_CELLS, Image.INTERPOLATE_BILINEAR)
	img.resize(t.size, t.size, Image.INTERPOLATE_CUBIC)
	return img.get_data()


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


## Forgets every decoded tile and what was missing (the tests, after changing `dirs`).
static func reset() -> void:
	_lock.lock()
	_mem.clear()
	_missing.clear()
	_lock.unlock()
