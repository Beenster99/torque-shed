extends RefCounted
## Downloaded regions' checks (RegionStore: a zip fetched, its hash checked, put under user://regions where RealRegion
## finds it), run from tests/run_tests.gd. A tiny region of the test's own is served from a local web server.

const PORT := 8765

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A tiny region folder (no land, four junctions) at user://tmp/tiny, and its zip at user://tmp/tiny.zip.
static func make_tiny() -> String:
	var dir := "user://tmp/tiny"
	RegionStore._remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("tiles"))
	var meta := {"format": RealRegion.FORMAT, "kind": "region", "name": "tiny", "title": "Tiny", "frame": {"lat": 34.5, "lon": 134.3},
		"bounds": [-100, -100, 3000, 1000], "levels": [], "counts": {"nodes": 4, "edges": 4}, "sea": false, "theme": "hills", "region": "jp",
		"credits": ["nobody"]}
	var rows := {"classes": ["primary", "tertiary"], "surfaces": ["tarmac"], "names": [""],
		"nodes": [[0, 0], [1000, 0], [2000, 0], [1000, 800]],
		"edges": [{"a": 0, "b": 1, "c": 0, "s": 0, "l": 0, "n": 0, "o": 0, "p": []}, {"a": 1, "b": 2, "c": 0, "s": 0, "l": 0, "n": 0, "o": 0, "p": []},
			{"a": 1, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []}, {"a": 0, "b": 3, "c": 1, "s": 0, "l": 0, "n": 0, "o": 0, "p": []}], "bans": []}
	var f := FileAccess.open(dir.path_join("region.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	f = FileAccess.open(dir.path_join("roads.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	f = FileAccess.open(dir.path_join("tiles").path_join("0_0.u16z"), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()
	var packer := ZIPPacker.new()
	packer.open("user://tmp/tiny.zip")
	for name in ["region.json", "roads.json", "tiles/0_0.u16z"]:
		packer.start_file(name)
		packer.write_file(FileAccess.get_file_as_bytes(dir.path_join(name)))
		packer.close_file()
	packer.close()
	return dir


func test_hash() -> void:
	var r := RealRegion.get_region("shodoshima")
	check(RegionStore.hash_of_dir(RealRegion.dir_of("shodoshima")) == r.hash, "the game works out the same hash for a region as the baker wrote (%s)" % r.hash)
	var dir := make_tiny()
	var h := RegionStore.hash_of_dir(dir)
	var f := FileAccess.open(dir.path_join("region.json"), FileAccess.WRITE)
	f.store_string("{\"format\": 2, \"other\": true}")
	f.close()
	check(h.length() == 16 and RegionStore.hash_of_dir(dir) == h, "region.json isn't in the hash")
	f = FileAccess.open(dir.path_join("roads.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(RegionStore.hash_of_dir(dir) != h, "but the roads are")


func test_install() -> void:
	make_tiny()
	var h := RegionStore.hash_of_dir("user://tmp/tiny")
	RegionStore.remove("tiny")
	var why := RegionStore.install_zip("user://tmp/tiny.zip", "tiny", "0000000000000000")
	check(why != "" and not RegionStore.installed("tiny"), "a zip whose data isn't what the index says is turned away: \"%s\"" % why)
	why = RegionStore.install_zip("user://tmp/tiny.zip", "tiny", h)
	check(why == "" and RegionStore.installed("tiny") and RealRegion.list().has("tiny"), "the right one is put in place and listed")
	var r := RealRegion.get_region("tiny")
	check(r != null and r.node_count() == 4 and r.title == "Tiny" and r.hash == "", "and it loads from user://regions")
	RegionStore.remove("tiny")
	check(not RealRegion.list().has("tiny") and RealRegion.get_region("tiny") == null, "removed, it is gone")


## A download from a local web server (python3 -m http.server), end to end.
func test_download() -> void:
	make_tiny()
	var h := RegionStore.hash_of_dir("user://tmp/tiny")
	RegionStore.remove("tiny")
	var root := ProjectSettings.globalize_path("user://tmp")
	var pid := OS.create_process("python3", ["-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", root])
	if pid <= 0:
		check(false, "a local web server to download from (python3)")
		return
	var store := RegionStore.new()
	t.add_child(store)
	var got := [null, ""]
	store.finished.connect(func(ok, why): got[0] = ok; got[1] = why)
	# The server takes a moment to come up: try until it answers.
	var end := Time.get_ticks_msec() + 20000
	var attempt := 0
	while got[0] == null and Time.get_ticks_msec() < end:
		if attempt == 0 or (got[0] == null and store._http == null):
			pass
		attempt += 1
		store.download("tiny", "http://127.0.0.1:%d/tiny.zip" % PORT, h)
		var wait := Time.get_ticks_msec() + 4000
		while got[0] == null and Time.get_ticks_msec() < wait:
			await t.get_tree().process_frame
		if got[0] == false and str(got[1]).contains("no answer"):
			got[0] = null   # not up yet: again
			store._http.queue_free()
			await t.get_tree().process_frame
	check(got[0] == true and RegionStore.installed("tiny"), "the region downloads and is put in place (%s)" % str(got[1]))
	check(RealRegion.get_region("tiny") != null and RealRegion.get_region("tiny").node_count() == 4, "and loads")
	# A download whose hash is wrong is thrown away.
	RegionStore.remove("tiny")
	var bad := RegionStore.new()
	t.add_child(bad)
	var got2 := [null, ""]
	bad.finished.connect(func(ok, why): got2[0] = ok; got2[1] = why)
	bad.download("tiny", "http://127.0.0.1:%d/tiny.zip" % PORT, "0000000000000000")
	end = Time.get_ticks_msec() + 10000
	while got2[0] == null and Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
	check(got2[0] == false and not RegionStore.installed("tiny") and not FileAccess.file_exists("user://regions/tiny.zip"), "one whose data doesn't match is thrown away: \"%s\"" % str(got2[1]))
	OS.kill(pid)
	store.queue_free()
	bad.queue_free()
	RegionStore.remove("tiny")
