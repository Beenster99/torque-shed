extends RefCounted
## Taking an adventure's photo down off the shed wall and deleting its diary (Simon: "We need to
## be able to delete wall mounted diaries"), run from tests/run_tests.gd (its _test_diary_delete_*
## functions hand over to these). The two-machine half is in tests/mp_diary.gd.

var t: Node   # the test runner: check()

const ROOT := "user://zz_test_diary_delete"


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)


## A photo of a ride to `dest` with `names` on it, its key `key`.
static func _photo(key: String, dest: String, names: Array) -> Dictionary:
	var p := AdventureDest.make_photo({"seed": 1, "dest": dest, "theme": "hills", "km": 120.0}, names)
	p["key"] = key
	return p


## A diary `id` saved on this machine for the ride the photo was taken on, with a picture beside it.
static func _diary(id: String, photo: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(AdventureDiary.folder(id))
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.save_jpg(AdventureDiary.folder(id).path_join("p1.jpg"))
	AdventureDiary.save_diary({"id": id, "title": "To " + str(photo["dest"]), "dest": photo["dest"], "photo": photo, "done": true,
		"saved_at": 100, "photos": [{"file": "p1.jpg", "kind": "photo", "caption": ""}]})


## On your own: the scrap key on the photo takes it down instead (with a warning first that it
## can't be undone); it goes from the shed, its diary from this machine (photos and all), and the
## album forgets it so it isn't hung again; another ride's photo and diary are left as they were.
func test_take_down() -> void:
	var root_was := AdventureDiary.root
	var album_was := AdventureDest.album_path
	AdventureDiary.root = ROOT
	_wipe(ROOT)
	AdventureDest.album_path = ""
	Shed.start_new("Tester", 5)
	if not Shed.crew.has(Shed.me()):
		Shed.crew[Shed.me()] = {}
	Shed.crew[Shed.me()]["name"] = "Tester"
	var p1 := _photo("del-1", "Hawes", ["Tester", "Pal"])
	var p2 := _photo("del-2", "Malham", ["Tester"])
	for p in [p1, p2]:
		AdventureDest.album_add("Tester", p)
	var f1 := AdventureDest.hang(p1)
	var f2 := AdventureDest.hang(p2)
	_diary("d1", p1)
	_diary("d2", p2)
	check(f1 != 0 and f2 != 0 and AdventureDiary.find_by_photo("del-1") == "d1", "two rides' photos on the wall, each with its diary here")
	# The scrap key's way in: the walker turns it into taking the photo down.
	var w := Walker.new()
	var target := w._scrap_furniture(f1)
	var action := w._scrap_action(target)
	check(target.get("diary", false) and str(target["name"]).contains("Hawes") and action == {"a": "diary_delete", "furniture": f1},
		"holding the scrap key on the photo asks to take it down and delete its diary (%s)" % str(action))
	check(w._scrap_line(f1).contains("take it down and delete its diary"), "the HUD says so (%s)" % w._scrap_line(f1))
	w.free()
	check(Shed.check(Shed.me(), {"a": "scrap", "furniture": f1}) != "", "it can't be scrapped like a bench, past its diary")
	check(Shed.check(Shed.me(), {"a": "diary_delete", "furniture": f1}) == "", "playing alone, you may take it down")
	check(Shed.check(Shed.me(), {"a": "diary_delete", "furniture": 999999}) != "", "not a photo that isn't there")
	# Not while that adventure's on.
	var adv_was := Shed.adventure
	Shed.adventure = {"id": 7, "photo": p1}
	check(Shed.check(Shed.me(), {"a": "diary_delete", "furniture": f1}).contains("ride home"), "not while that adventure is still on")
	Shed.adventure = adv_was
	# Co-op: the host, and anyone who was on that ride; nobody else.
	Shed.crew[2] = {"name": "Pal"}
	Shed.crew[3] = {"name": "Stranger"}
	check(AdventureDest.delete_check(1, {"furniture": f1}, true) == "", "in co-op the host may take it down")
	check(AdventureDest.delete_check(2, {"furniture": f1}, true) == "", "and so may a rider named on it")
	check(AdventureDest.delete_check(3, {"furniture": f1}, true).begins_with("Only the host"), "but not someone who wasn't on that ride")
	Shed.crew.erase(2)
	Shed.crew.erase(3)
	# Taken down.
	var told := []
	var hear := func(text: String, _ok: bool): told.append(text)
	Shed.feedback.connect(hear)
	Shed.request({"a": "diary_delete", "furniture": f1})
	Shed.feedback.disconnect(hear)
	check(not Shed.furniture.has(f1) and AdventureDest.photo_on_wall("del-1").is_empty(), "the photo's gone from the wall")
	check(AdventureDiary.load_diary("d1").is_empty() and not DirAccess.dir_exists_absolute(AdventureDiary.folder("d1")),
		"its diary's deleted, photos and all")
	check(told.any(func(s): return str(s).contains("deleted its Adventure Diary")), "you're told (%s)" % str(told))
	check(AdventureDest.album_of("Tester").all(func(p): return str(p["key"]) != "del-1") and AdventureDest.hang_album("Tester") == 0,
		"the album's forgotten it, so it isn't hung again")
	check(Shed.furniture.has(f2) and not AdventureDiary.load_diary("d2").is_empty() and AdventureDiary.list().size() == 1,
		"the other ride's photo and diary are as they were")
	Shed.stop()
	_wipe(ROOT)
	AdventureDiary.root = root_was
	AdventureDest.album_path = album_was
