extends RefCounted
## Adventure destinations' checks (AdventureDest: the last pin, how long a ride takes, arriving, the photo on the shed
## wall and the album), run from tests/run_tests.gd: its _test_adv_dest_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _until(cond: Callable, seconds := 20.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


# ---------------------------------------------------------------------------- destinations

## How long a ride takes and whether it needs a night's stop; a destination's name (a place, or an old photo's
## made-up one); an adventure from before rides were planned isn't one.
func test_data() -> void:
	check(AdventureDest.minutes_for(100.0) == 90 and AdventureDest.minutes_for(150.0) == 120 and AdventureDest.minutes_for(220.0) == 180,
		"100 km about 90 minutes, 150 km 2 hours and 220 km 3 hours (%d, %d, %d)" % [AdventureDest.minutes_for(100.0),
		AdventureDest.minutes_for(150.0), AdventureDest.minutes_for(220.0)])
	check(AdventureDest.minutes_for(60.0) < AdventureDest.minutes_for(80.0) and AdventureDest.minutes_for(300.0) > 180,
		"the further, the longer")
	check(AdventureDest.time_text(28.0) == "about 25 min" and AdventureDest.time_text(150.0) == "about 2 h", "and it's said in words")
	check(AdventureDest.overnight(220.0) and not AdventureDest.overnight(150.0), "only a ride of 200 km and more needs a night's stop")
	check(AdventureDest.name_of("Hawes") == "Hawes" and AdventureDest.name_of("canyon") == "Red Rock Canyon",
		"a destination is the place itself (an old photo's made-up one keeps its name)")
	check(Adventure.sanitize({"id": 5, "seed": 9, "km": 30.0, "theme": "varied", "riders": {}}).is_empty(),
		"an adventure that isn't along a planned journey isn't one")


## The ride ends at the last pin: the finish banner there, the destination named after its place, the crew parked on
## the road just past it.
func test_build() -> void:
	var plan := Rides.plan(20.0)
	var info := AdventureJourney.start_info({"plan": plan})
	check(str(info["dest"]) == str(plan["names"][-1]) and str(info["dest"]) != "", "the destination is the last pin's place (%s)" % info["dest"])
	var w := AdventureWorld.new()
	w.setup(AdventurePlans.pack_for(plan), 77)
	var fin: Array = w.route.sites_of("finish")
	check(fin.size() == 1 and absf(float(fin[0]["s"]) - w.route.length) < 1.0 and absf(w.route.length - float(info["km"]) * 1000.0) < 100.0,
		"the finish is at the end of the planned road (%.1f km)" % (w.route.length / 1000.0))
	check(AdventureDest.dest_s(w) > w.route.length and AdventureDest.dest_s(w) < w.route.total, "the crew stops just past it, on the road's run-out")
	t.add_child(w)
	w.preload_range(AdventureDest.dest_s(w) - 40.0, AdventureDest.dest_s(w) + 40.0)
	var park := AdventureDest.park_xf(w, 0)
	var hit := w.locate_local(park.origin)
	check(not hit.is_empty() and absf(float(hit["s"]) - AdventureDest.dest_s(w)) < 20.0 and float(hit["lat"]) > 0.0,
		"the crew parks on the road there")
	w.queue_free()
	await _frames(2)


## Arriving: the photo (the crew's names), XP for everyone by the length, the photo hung on the
## shed wall, and nothing ends till the host rides everyone home.
func test_arrive() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_dest_test.json"
	DirAccess.remove_absolute(Progress.path)
	AdventureDest.album_path = ""
	Shed.start_new("Tester", 5)
	Progress.select("Tester")
	var xp0 := int(Progress.profile["xp"])
	var photos0 := Shed.furniture.values().filter(func(f): return str(f["model"]) == AdventureDest.PHOTO_MODEL).size()
	var plan := AdventurePlans.tour("dales")
	var km := AdventurePlans.pack_for(plan).max_km()
	var dest := str(plan["names"][-1])
	Shed.request({"a": "adventure_start", "plan": plan, "seed": 4101, "title": "Round the Dales"})
	check(Adventure.active() and str(Shed.adventure["dest"]) == dest and str(Shed.adventure["title"]) == "Round the Dales" and Shed.adventure["theme"] == "hills",
		"the adventure knows where it's going (%s) and what it's called" % dest)
	Shed.request({"a": "adventure_arrive"})
	var photo: Dictionary = Shed.adventure.get("photo", {})
	check(not photo.is_empty() and (photo["names"] as Array).has("Tester") and str(photo["dest"]) == dest and int(photo["km"]) == roundi(km)
		and str(photo["theme"]) == "hills", "arriving takes the crew's photo there (%s)" % str(photo))
	var gained := int(Progress.profile["xp"]) - xp0
	check(gained >= floori(3.0 * km) - 5, "and everyone gets XP for the ride (%d for %.0f km)" % [gained, km])
	var hung := AdventureDest.photo_on_wall(str(photo.get("key", "")))
	check(not hung.is_empty() and Equipment.is_wall(str(hung["model"])) and str(hung["kind"]) == "trinket",
		"the photo hangs in the shed, a wall trinket")
	var wall_z := Workshop.CENTER.z + Workshop.HALF.y
	check(not hung.is_empty() and absf((hung["xf"] as Transform3D).origin.z - wall_z) < 0.1, "on the shed's front wall")
	check(Shed.furniture_name(hung).contains(dest), "it says where (%s)" % Shed.furniture_name(hung))
	check(Adventure.active() and Adventure.menu_text()[0].begins_with("Ride home"), "the adventure stays on till the host rides everyone home")
	# A second arrival can't double anything.
	Shed.request({"a": "adventure_arrive"})
	check(int(Progress.profile["xp"]) - xp0 == gained, "arriving again gives nothing more")
	Shed.request({"a": "adventure_end"})
	check(not Adventure.active(), "Ride home ends it")
	# Ten more: each in its own spot, none on top of another.
	for k in 10:
		var p := AdventureDest.make_photo({"seed": k, "dest": "Hawes", "theme": "hills", "km": 100.0}, ["A"])
		p["key"] = "test-%d" % k
		AdventureDest.hang(p)
	var spots := []
	var overlap := false
	for f in Shed.furniture.values():
		if str(f["model"]) == AdventureDest.PHOTO_MODEL:
			for o in spots:
				if (o as Vector3).distance_to((f["xf"] as Transform3D).origin) < 0.6:
					overlap = true
			spots.append((f["xf"] as Transform3D).origin)
	check(spots.size() == photos0 + 11 and not overlap, "photo after photo goes up, none on top of another (%d)" % spots.size())
	# The photo's view: the frame, the picture of the crew and the plate.
	var view := Node3D.new()
	AdventureDest.build_photo(view, photo)
	var cap := view.find_child("Caption", true, false) as Label3D
	check(view.find_child("Picture", true, false) != null and cap != null and cap.text.contains("Tester") and cap.text.contains("%d km" % roundi(km)),
		"the framed photo shows the picture, and the plate says where, how far and who (%s)" % (cap.text if cap else ""))
	view.free()
	Shed.stop()
	Progress.path = real_path


## The pictures and the album: each theme's land painted its own, the crew in front; an album
## per player, kept once, and your photos go up in your own shed.
func test_photo() -> void:
	var seen := {}
	for theme in AdventureTheme.IDS:
		var img := AdventureDest.paint(theme, 0)
		seen[img.get_data().hex_encode().sha256_text()] = theme
		check(img.get_width() == AdventureDest.PIC_W and img.get_height() == AdventureDest.PIC_H, "the %s land is painted" % theme)
	check(seen.size() == AdventureTheme.IDS.size(), "every theme's picture is its own")
	var a := AdventureDest.paint("hills", 0)
	var b := AdventureDest.paint("hills", 3)
	check(a.get_data() != b.get_data(), "the photo has the crew stood in front")
	check(AdventureDest.picture("coastal", 2) == AdventureDest.picture("coastal", 2), "and it's painted once")
	check(AdventureDest.sanitize_photo({"key": "", "dest": "Hawes"}).is_empty() and AdventureDest.sanitize_photo({"key": "x", "dest": ""}).is_empty()
		and not AdventureDest.sanitize_photo({"key": "x", "dest": "Hawes", "names": ["A", 3]}).is_empty(), "a photo's record is checked")
	var old := AdventureDest.sanitize_photo({"key": "o", "dest": "canyon", "names": ["A"], "km": 100})
	check(str(old["theme"]) == "desert" and AdventureDest.caption(old).begins_with("Red Rock Canyon"),
		"a photo from before planned rides keeps its destination's name and land (%s)" % AdventureDest.caption(old))
	AdventureDest.album_path = ""
	AdventureDest._album_mem = {}
	var p1 := AdventureDest.sanitize_photo({"key": "k1", "dest": "Tonosho", "theme": "coastal", "names": ["Ann", "Bob"], "km": 150, "date": "2026-10-19"})
	var p2 := AdventureDest.sanitize_photo({"key": "k2", "dest": "Hawes", "theme": "hills", "names": ["Ann"], "km": 100, "date": "2026-10-19"})
	AdventureDest.album_add("Ann", p1)
	AdventureDest.album_add("Ann", p1)
	AdventureDest.album_add("Ann", p2)
	AdventureDest.album_add("Bob", p1)
	check(AdventureDest.album_of("Ann").size() == 2 and AdventureDest.album_of("Bob").size() == 1 and AdventureDest.album_of("Cy").is_empty(),
		"each player's album keeps their photos, once each")
	# The album on disk too.
	AdventureDest.album_path = "user://zz_album_test.json"
	DirAccess.remove_absolute(AdventureDest.album_path)
	AdventureDest.album_add("Ann", p2)
	check(AdventureDest.album_of("Ann").size() == 1 and str(AdventureDest.album_of("Ann")[0]["key"]) == "k2", "the album's kept in a file")
	DirAccess.remove_absolute(AdventureDest.album_path)
	AdventureDest.album_path = ""
	# Your own shed: what's in your album goes up on its walls, once.
	Shed.start_new("Ann", 5)
	var n := AdventureDest.hang_album("Ann")
	check(n == 2 and not AdventureDest.photo_on_wall("k1").is_empty() and not AdventureDest.photo_on_wall("k2").is_empty(),
		"your album's photos go up in your own shed")
	check(AdventureDest.hang_album("Ann") == 0, "and not twice")
	check(Adventure.check(Shed.me(), {"a": "adventure_photo", "photo": {"key": "", "dest": "x"}}) != "", "a bad photo isn't hung")
	# Saved and loaded with the shed.
	var snap: Dictionary = bytes_to_var(var_to_bytes(Shed._snapshot()))
	Shed.load_state(snap, "Ann")
	check(not AdventureDest.photo_on_wall("k1").is_empty() and str(AdventureDest.photo_on_wall("k1")["photo"]["dest"]) == "Tonosho",
		"the photos are kept with the shed")
	check(not Trinkets.all().has(AdventureDest.PHOTO_MODEL), "the adventure photo isn't for sale in the Shop")
	Shed.stop()
