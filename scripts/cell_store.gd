class_name CellStore
extends RefCounted
## The world's cells (see RealRegion.stitch) the game doesn't have yet, fetched from where they are baked and served:
## Beenster99/torque-shed-world, whose index.json names each cell's hash, size and download (a release asset), or
## that it has no roads. A cell is checked against its hash (RegionStore.hash_of_dir) and kept under user://cells, where
## RealRegion finds it; the index is kept there too, so a crew offline still has the cells it fetched before.
##
## Everything here blocks while it waits on the network, so it runs on a worker (AdventurePlans plans a journey on one,
## and fetches the area's cells first). Safe from any thread.

const INDEX_URL := "https://raw.githubusercontent.com/Beenster99/torque-shed-world/main/index.json"
## Where fetched cells (and the index) are kept; RealRegion.cell_dirs looks there.
static var dir := "user://cells"
const USER_AGENT := "TorqueShed (+https://github.com/Beenster99/torque-shed)"
const TIMEOUT_MS := 60000
const MAX_REDIRECTS := 4

## Where the index is read from (the tests serve their own), and no network at all.
static var index_url := INDEX_URL
static var offline := false

static var _lock := Mutex.new()
static var _index := {}
static var _index_at := 0
## One fetch at a time (the TV's view and a journey's plan may both want a cell).
static var _fetching := Mutex.new()


## The index: {format, release, cells: {"ROW_COLUMN": {hash, bytes, url} or {empty: true}}, areas: {name: {...}}}. Fetched
## (at most once a quarter of an hour) and kept on disk; the copy on disk when the network can't be had, else {}.
static func index(refresh := false) -> Dictionary:
	_lock.lock()
	var have := _index
	var fresh := Time.get_ticks_msec() - _index_at < 15 * 60 * 1000 and not have.is_empty()
	_lock.unlock()
	if fresh and not refresh:
		return have
	var got := {}
	if not offline:
		var res := http_get(index_url)
		if int(res["code"]) == 200:
			var v = JSON.parse_string((res["body"] as PackedByteArray).get_string_from_utf8())
			if v is Dictionary and v.get("cells") is Dictionary:
				got = v
				DirAccess.make_dir_recursive_absolute(dir)
				var f := FileAccess.open(dir.path_join("index.json"), FileAccess.WRITE)
				if f != null:
					f.store_string(JSON.stringify(got))
					f.close()
				_save_areas(got)
	if got.is_empty():
		got = saved_index()
	_lock.lock()
	_index = got
	_index_at = Time.get_ticks_msec()
	_lock.unlock()
	return got


## Forgets the index fetched (the tests change where it comes from).
static func forget_index() -> void:
	_lock.lock()
	_index = {}
	_index_at = 0
	_lock.unlock()


## The index as last fetched, from disk (no network): {} if it never was.
static func saved_index() -> Dictionary:
	var path := dir.path_join("index.json")
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## The index's named areas, put where RealRegion.areas() reads them (areas.json beside the cells).
static func _save_areas(idx: Dictionary) -> void:
	var areas = idx.get("areas", {})
	if not areas is Dictionary or (areas as Dictionary).is_empty():
		return
	var f := FileAccess.open(dir.path_join("areas.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(areas))
		f.close()


## Where 5 degree block `block`'s sketch of the main roads is ("R_C": see tools/sketch_bake.py), beside the index.
static func sketch_url(block: String) -> String:
	return index_url.get_base_dir().path_join("sketch/b%s.json" % block)


## The sketch of 5 degree block `block` ("R_C"): {cells: {"ROW_COL": its main roads, [[class, [lat, lon, dlat, dlon,
## ...]], ...]}, land: {"ROW_COL": its coast (tools/coast_bake.py)}} (see tools/sketch_bake.py), from the copy kept on
## disk if it is the one index `idx` names, else fetched (and kept). {} when the index has none for it, or it can't be
## had. Blocks while it fetches: a worker's job.
static func sketch(block: String, idx: Dictionary) -> Dictionary:
	var want := str((idx.get("sketches", {}) as Dictionary).get(block, ""))
	if want == "":
		return {}
	var path := dir.path_join("sketch").path_join("b%s.json" % block)
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if text.trim_suffix("\n").sha1_text().left(12) != want:
		if offline:
			return {}
		var res := http_get(sketch_url(block))
		if int(res["code"]) != 200:
			return {}
		text = (res["body"] as PackedByteArray).get_string_from_utf8()
		if text.trim_suffix("\n").sha1_text().left(12) != want:
			return {}   # (not the one the index names: it may have changed since; next time)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	var v = JSON.parse_string(text)
	if not v is Dictionary or not v.get("cells") is Dictionary:
		return {}
	return {"cells": v["cells"], "land": v["land"] if v.get("land") is Dictionary else {}}


## The cells of a box (degrees) the game hasn't got but the index has baked (empty ones, the sea, aren't wanted).
static func missing(south: float, west: float, north: float, east: float, idx: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells: Dictionary = idx.get("cells", {})
	var a := RealRegion.cell_of(south, west)
	var b := RealRegion.cell_of(north - 1e-9, east - 1e-9)
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			var e = cells.get("%d_%d" % [i, j])
			if e is Dictionary and not bool(e.get("empty", false)) and RealRegion.cell_dir(Vector2i(i, j)) == "":
				out.append(Vector2i(i, j))
	return out


## Fetches the cells of a box the game hasn't got, one by one, each checked against its hash. Returns "" or why not.
## `progress(done, total)` is called as each comes. Never call it on the main thread.
static func fetch_box(south: float, west: float, north: float, east: float, progress := Callable()) -> String:
	var a := RealRegion.cell_of(south, west)
	var b := RealRegion.cell_of(north - 1e-9, east - 1e-9)
	var cells: Array[Vector2i] = []
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			cells.append(Vector2i(i, j))
	return fetch_cells(cells, progress)


## What the game knows of cell `c`: "here" (it has it), "baked" (the index has it, to fetch), "sea" (no roads), or
## "unknown" (nobody has baked it yet) from index `idx`.
static func state_of(c: Vector2i, idx: Dictionary) -> String:
	if RealRegion.cell_dir(c) != "":
		return "here"
	var e = (idx.get("cells", {}) as Dictionary).get("%d_%d" % [c.x, c.y])
	if not e is Dictionary:
		return "unknown"
	return "sea" if bool(e.get("empty", false)) else "baked"


## Fetches those of `cells` the game hasn't got and the index has baked, one by one, each checked against its hash.
## Returns "" or why not. `progress(done, total)` is called as each comes. Never call it on the main thread.
static func fetch_cells(cells: Array[Vector2i], progress := Callable()) -> String:
	_fetching.lock()
	var why := _fetch_cells(cells, progress)
	_fetching.unlock()
	return why


static func _fetch_cells(cells: Array[Vector2i], progress: Callable) -> String:
	var idx := index()
	var want: Array[Vector2i] = []
	for c in cells:
		if state_of(c, idx) == "baked":
			want.append(c)
	if want.is_empty():
		return ""
	if offline:
		return "This game doesn't have that part of the world, and it's offline."
	DirAccess.make_dir_recursive_absolute(dir)
	var done := 0
	for c in want:
		var e: Dictionary = idx["cells"]["%d_%d" % [c.x, c.y]]
		var res := http_get(str(e["url"]))
		if int(res["code"]) != 200:
			return "Couldn't fetch that part of the world (HTTP %d): are you online?" % int(res["code"])
		var name := "c%d_%d" % [c.x, c.y]
		var zip := dir.path_join(name + ".zip")
		var f := FileAccess.open(zip, FileAccess.WRITE)
		if f == null:
			return "Couldn't save that part of the world to %s." % zip
		f.store_buffer(res["body"])
		f.close()
		var why := RegionStore.install_zip(zip, name, str(e["hash"]), dir)
		DirAccess.remove_absolute(zip)
		if why != "":
			return why
		done += 1
		if progress.is_valid():
			progress.call(done, want.size())
	RealRegion.forget_areas()
	return ""


## GETs `url` (https or http), following redirects: {code, body}. Code 0 when there was no answer. Blocks.
static func http_get(url: String) -> Dictionary:
	return http(url)


## Asks `url` (https or http) with `method`, sending `json` (a body, as JSON) if there is one, following redirects (as a
## GET): {code, body, urls (every address asked, the last where the answer came from)}. Code 0 when there was no
## answer. Blocks.
static func http(url: String, method := HTTPClient.METHOD_GET, json := "") -> Dictionary:
	var urls: Array[String] = []
	for hop in MAX_REDIRECTS + 1:
		urls.append(url)
		var tls := url.begins_with("https://")
		var rest := url.substr(8 if tls else 7)
		var slash := rest.find("/")
		var host := rest.substr(0, slash) if slash >= 0 else rest
		var path := rest.substr(slash) if slash >= 0 else "/"
		var port := 443 if tls else 80
		if host.contains(":"):
			port = int(host.get_slice(":", 1))
			host = host.get_slice(":", 0)
		var client := HTTPClient.new()
		if client.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
			return {"code": 0, "body": PackedByteArray(), "urls": urls}
		var since := Time.get_ticks_msec()
		var sent := false
		var body := PackedByteArray()
		while Time.get_ticks_msec() - since < TIMEOUT_MS:
			client.poll()
			var st := client.get_status()
			if st == HTTPClient.STATUS_CONNECTED and not sent:
				sent = true
				var send := ["User-Agent: " + USER_AGENT]
				if json != "":
					send.append("Content-Type: application/json")
				if client.request(method, path, send, json) != OK:
					return {"code": 0, "body": PackedByteArray(), "urls": urls}
			elif st == HTTPClient.STATUS_BODY:
				body.append_array(client.read_response_body_chunk())
			elif st == HTTPClient.STATUS_CONNECTED and sent:
				break
			elif sent and client.has_response() and (st == HTTPClient.STATUS_DISCONNECTED or st == HTTPClient.STATUS_CONNECTION_ERROR):
				# The server closed the connection once it had answered: whole, if it said how long and it's all here.
				var want := client.get_response_body_length()
				if want >= 0 and body.size() != want:
					return {"code": 0, "body": PackedByteArray(), "urls": urls}
				break
			elif st != HTTPClient.STATUS_RESOLVING and st != HTTPClient.STATUS_CONNECTING and st != HTTPClient.STATUS_REQUESTING:
				return {"code": 0, "body": PackedByteArray(), "urls": urls}
			OS.delay_msec(2)
		var code := client.get_response_code()
		if code in [301, 302, 303, 307, 308]:
			var headers := client.get_response_headers_as_dictionary()
			var to := str(headers.get("Location", headers.get("location", "")))
			if to == "":
				return {"code": code, "body": body, "urls": urls}
			url = to if to.begins_with("http") else "%s://%s%s" % ["https" if tls else "http", host, to]
			method = HTTPClient.METHOD_GET
			json = ""
			continue
		return {"code": code, "body": body, "urls": urls}
	return {"code": 0, "body": PackedByteArray(), "urls": urls}
