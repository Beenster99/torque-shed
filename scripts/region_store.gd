class_name RegionStore
extends Node
## Regions the game didn't come with (see RealRegion): downloaded as a zip of the baked folder, checked against the
## hash the index gives for it, and kept under user://regions/<id>/ where RealRegion finds them beside the bundled
## ones. The index (data/regions/index.json) lists every region the game knows of: {id: {title, hash, bytes, url}}; a
## bundled one has no url. tools/region_zip.py makes the zip and the index entry from a baked folder.
##
## A download is a node: add one to the tree, call download(), and listen for `finished`.

signal finished(ok: bool, why: String)

const USER_DIR := "user://regions"
const INDEX := "res://data/regions/index.json"

var region_id := ""
var expect_hash := ""
var _http: HTTPRequest
var _zip := ""


## The index of regions: {id: {title, hash, bytes, url}}.
static func index() -> Dictionary:
	if not FileAccess.file_exists(INDEX):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	return v.get("regions", {}) if v is Dictionary else {}


## Whether region `id` is installed under user://regions.
static func installed(id: String) -> bool:
	return FileAccess.file_exists(USER_DIR.path_join(id).path_join("region.json"))


## The hash of a region folder, as tools/region_bake.py region_hash makes it: SHA-256 over every file but region.json,
## folders and files in name order, the first 16 hex digits.
static func hash_of_dir(path: String) -> String:
	var dirs: Array[String] = []
	_walk(path, "", dirs)
	dirs.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for rel in dirs:
		var d := DirAccess.open(path.path_join(rel) if rel != "" else path)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for fn in files:
			if fn == "region.json":
				continue
			var full := (path.path_join(rel) if rel != "" else path).path_join(fn)
			ctx.update(FileAccess.get_file_as_bytes(full))
	return ctx.finish().hex_encode().substr(0, 16)


static func _walk(root: String, rel: String, out: Array[String]) -> void:
	out.append(rel)
	var d := DirAccess.open(root.path_join(rel) if rel != "" else root)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(root, rel.path_join(sub) if rel != "" else sub, out)


## Puts the region in `zip_path` (the baked folder's files at the zip's top level) in place as region `id`, if its
## hash is `expect` ("" to take it as it is). Returns "" or why not; the zip is left as it was.
static func install_zip(zip_path: String, id: String, expect: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "The download isn't a region zip."
	var tmp := USER_DIR.path_join(id + ".part")
	_remove_tree(tmp)
	DirAccess.make_dir_recursive_absolute(tmp)
	var any := false
	for name in reader.get_files():
		if name.ends_with("/") or name.begins_with("/") or name.contains(".."):
			continue
		var dest := tmp.path_join(name)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			reader.close()
			_remove_tree(tmp)
			return "Couldn't write the region to %s." % dest
		f.store_buffer(reader.read_file(name))
		f.close()
		any = any or name == "region.json"
	reader.close()
	if not any:
		_remove_tree(tmp)
		return "The zip has no region.json in it."
	var got := hash_of_dir(tmp)
	if expect != "" and got != expect:
		_remove_tree(tmp)
		return "The download's data (%s) isn't the region the index names (%s): try again later." % [got, expect]
	var final := USER_DIR.path_join(id)
	_remove_tree(final)
	var err := DirAccess.rename_absolute(tmp, final)
	if err != OK:
		_remove_tree(tmp)
		return "Couldn't put the region in place (%s)." % error_string(err)
	RealRegion.forget(id)
	return ""


## Takes region `id` out of user://regions (a bundled one stays).
static func remove(id: String) -> void:
	_remove_tree(USER_DIR.path_join(id))
	RealRegion.forget(id)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	for fn in d.get_files():
		DirAccess.remove_absolute(path.path_join(fn))
	DirAccess.remove_absolute(path)


## Fetches the zip at `url` and installs it as region `id` with hash `expect`; `finished` says how it went.
func download(id: String, url: String, expect: String) -> void:
	region_id = id
	expect_hash = expect
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	_zip = USER_DIR.path_join(id + ".zip")
	_http = HTTPRequest.new()
	_http.download_file = _zip
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var err := _http.request(url)
	if err != OK:
		finished.emit(false, "Couldn't start the download (%s)." % error_string(err))


## How far along the download is (0 to 1; 0 before the size is known).
func progress() -> float:
	if _http == null or _http.get_body_size() <= 0:
		return 0.0
	return clampf(float(_http.get_downloaded_bytes()) / float(_http.get_body_size()), 0.0, 1.0)


func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(_zip)
		finished.emit(false, "The download failed (%s%s)." % ["HTTP %d" % code if code > 0 else "no answer", "" if result == HTTPRequest.RESULT_SUCCESS else ", result %d" % result])
		return
	var why := install_zip(_zip, region_id, expect_hash)
	DirAccess.remove_absolute(_zip)
	finished.emit(why == "", why)
