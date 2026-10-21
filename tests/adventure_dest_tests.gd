extends RefCounted
## Adventure destinations and the magazine's checks (AdventureDest: the ride lengths, the set
## pieces, arriving, the photo on the shed wall and the album; AdventureMag: the issues, the
## pages, the route's facts and starting one from the workbench), run from tests/run_tests.gd:
## its _test_adv_dest_* and _test_adv_magazine_* functions hand over to these.

const THEMES: Array[String] = ["desert", "alpine", "coastal", "hills", "varied"]

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


## Every MeshInstance3D under `n`, and how many triangles they hold between them.
static func _tris(n: Node) -> int:
	var out := 0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (c as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				out += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		elif mesh != null:
			out += 1
	return out


# ---------------------------------------------------------------------------- destinations

## The lengths and every theme's destinations: data that hangs together.
func test_data() -> void:
	check(AdventureDest.LENGTH_ORDER.size() == 3 and float(AdventureDest.LENGTHS["short"]["km"]) == 100.0
		and float(AdventureDest.LENGTHS["ride"]["km"]) == 150.0 and float(AdventureDest.LENGTHS["epic"]["km"]) == 220.0,
		"three lengths: short 100 km, ride 150 km, epic 220 km")
	check(AdventureDest.minutes_for(100.0) == 90 and AdventureDest.minutes_for(150.0) == 120 and AdventureDest.minutes_for(220.0) == 180,
		"about 90 minutes, 2 hours and 3 hours (%d, %d, %d)" % [AdventureDest.minutes_for(100.0), AdventureDest.minutes_for(150.0),
		AdventureDest.minutes_for(220.0)])
	check(AdventureDest.minutes_for(60.0) < AdventureDest.minutes_for(80.0) and AdventureDest.minutes_for(300.0) > 180,
		"free km in between and beyond take their share of time")
	check(AdventureDest.length_of(150.0) == "ride" and AdventureDest.length_of(123.0) == "free", "a preset's km is that preset, any other is free")
	check(AdventureDest.overnight(220.0) and not AdventureDest.overnight(150.0), "only the epic needs a night's stop")
	var kinds := {}
	for theme in THEMES:
		var list := AdventureDest.for_theme(theme)
		check(not list.is_empty(), "%s has a destination (%s)" % [theme, str(list)])
		check(list.has(AdventureDest.default_for(theme, 12345)), "a %s ride with none picked goes to one of %s's" % [theme, theme])
	for id in AdventureDest.DESTS:
		var d: Dictionary = AdventureDest.DESTS[id]
		kinds[d["kind"]] = true
		check(THEMES.has(str(d["theme"])) and str(d["name"]) != "" and str(d["what"]) != "" and str(d["line"]) != "",
			"%s has a theme, a name and its lines" % id)
	for k in ["canyon", "glacier", "lighthouse", "rally", "dirt_track", "race"]:
		check(kinds.has(k), "there's a %s to ride to" % k)
	check(float(AdventureDest.of("canyon")["hours"]) > 16.5 and float(AdventureDest.of("lighthouse")["hours"]) > 18.0,
		"the canyon's seen at sunset, the lighthouse at dusk")
	var site := AdventureDest.site("canyon", 100.0)
	check(str(site["kind"]) == "dest" and float(site["s"]) > 100000.0 and float(site["s"]) < 100000.0 + AdventureRoute.RUN_OUT - 150.0,
		"the set piece is just past the finish, in the road's run-out (%.0f m)" % float(site["s"]))
	# Old adventures (from before destinations) get one by their theme.
	var old := Adventure.sanitize({"id": 5, "seed": 9, "km": 30.0, "theme": "varied", "riders": {}})
	check(AdventureDest.exists(str(old["dest"])) and str(old["title"]) == "" and str(old["mag"]) == "", "an adventure without a destination gets one")


## Every set piece builds, with something to see and something solid; the race's bikes go round,
## and the road's planned with the land flat beside the set piece.
func test_build() -> void:
	for id in AdventureDest.DESTS:
		var d: Dictionary = AdventureDest.DESTS[id]
		var st := {"kind": "dest", "s": 20110.0, "side": 1, "name": AdventureDest.name_of(id)}
		var node := AdventureDest.build(id, str(d["theme"]), st, Transform3D())
		t.add_child(node)
		var tris := _tris(node)
		var bodies := node.find_children("*", "StaticBody3D", true, false).size()
		check(tris > 300 and bodies >= 1, "%s (%s) builds: %d triangles, %d solid bodies" % [id, d["kind"], tris, bodies])
		if str(d["kind"]) == "race":
			var racers := node.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.get_parent().get_class() == "Node3D" and m.get_parent() != node)
			var before: Array = racers.map(func(m): return (m as Node3D).global_position)
			await _frames(5)
			var moved := 0
			for i in racers.size():
				if (racers[i] as Node3D).global_position.distance_to(before[i]) > 0.05:
					moved += 1
			check(racers.size() >= 4 and moved == racers.size(), "the race's bikes go round (%d of %d moved)" % [moved, racers.size()])
		if str(d["kind"]) == "dirt_track":
			var track := node.find_child("Track", true, false)
			check(track != null and str(track.get_meta("surface", "")) == "gravel", "the dirt track rides as dirt")
		node.free()
	# The road with the destination planned in: its site, flat land beside it, and the world builds it.
	var w := AdventureWorld.new()
	w.setup(77, 20.0, "varied", "canyon")
	var sites := w.route.sites_of("dest")
	check(sites.size() == 1 and absf(float(sites[0]["s"]) - AdventureDest.dest_s(w)) < 1.0, "the route plans the destination's site")
	var i := int(AdventureDest.dest_s(w) / AdventureRoute.STEP)
	var e := w.route.width[i] * 0.5
	var flat := true
	for lat: float in [10.0, 30.0, 55.0]:
		var p := w.route.xz_at(AdventureDest.dest_s(w), e + lat)
		if absf(w.route.land_height(i, e + lat, p[0], p[1]) - (w.route.ph[i] - 0.12)) > 0.05:
			flat = false
	check(flat, "the land's flat beside it for the set piece")
	t.add_child(w)
	w.preload_range(AdventureDest.dest_s(w) - 40.0, AdventureDest.dest_s(w) + 40.0)
	var built := w.find_children("Destination", "Node3D", true, false)
	check(built.size() == 1 and str(built[0].get_meta("dest", "")) == "canyon", "and the world builds it when the road gets there")
	var park := AdventureDest.park_xf(w, 0)
	var hit := w.locate_local(park.origin)
	check(not hit.is_empty() and absf(float(hit["s"]) - AdventureDest.dest_s(w)) < 20.0 and float(hit["lat"]) > 0.0,
		"the crew parks on the road beside it")
	w.queue_free()
	await _frames(2)


## Arriving: the photo (the crew's names), XP for everyone by the length, the photo hung on the
## shed wall, the clock to sunset, and nothing ends till the host rides everyone home.
func test_arrive() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_dest_test.json"
	DirAccess.remove_absolute(Progress.path)
	AdventureDest.album_path = ""
	Shed.start_new("Tester", 5)
	Progress.select("Tester")
	var xp0 := int(Progress.profile["xp"])
	var photos0 := Shed.furniture.values().filter(func(f): return str(f["model"]) == AdventureDest.PHOTO_MODEL).size()
	Shed.request({"a": "adventure_start", "seed": 4101, "km": 150.0, "theme": "varied", "dest": "canyon", "title": "The Red Rock Run", "mag": "red_rock"})
	check(Adventure.active() and str(Shed.adventure["dest"]) == "canyon" and str(Shed.adventure["title"]) == "The Red Rock Run"
		and str(Shed.adventure["mag"]) == "red_rock", "the adventure knows where it's going and what it's called")
	Shed.request({"a": "adventure_arrive"})
	var photo: Dictionary = Shed.adventure.get("photo", {})
	check(not photo.is_empty() and (photo["names"] as Array).has("Tester") and str(photo["dest"]) == "canyon" and int(photo["km"]) == 150,
		"arriving takes the crew's photo there (%s)" % str(photo))
	var gained := int(Progress.profile["xp"]) - xp0
	check(gained >= 440, "and everyone gets XP for the ride (%d for 150 km)" % gained)
	var hung := AdventureDest.photo_on_wall(str(photo.get("key", "")))
	check(not hung.is_empty() and Equipment.is_wall(str(hung["model"])) and str(hung["kind"]) == "trinket",
		"the photo hangs in the shed, a wall trinket")
	var wall_z := Workshop.CENTER.z + Workshop.HALF.y
	check(not hung.is_empty() and absf((hung["xf"] as Transform3D).origin.z - wall_z) < 0.1, "on the shed's front wall")
	check(Shed.furniture_name(hung).contains("Red Rock Canyon"), "it says where (%s)" % Shed.furniture_name(hung))
	if Daylight.current:
		check(absf(Daylight.time_of_day() - 17.4) < 0.2, "the clock goes to sunset for the canyon (%.2f)" % Daylight.time_of_day())
	check(Adventure.active() and Adventure.menu_text()[0].begins_with("Ride home"), "the adventure stays on till the host rides everyone home")
	# A second arrival can't double anything.
	Shed.request({"a": "adventure_arrive"})
	check(int(Progress.profile["xp"]) - xp0 == gained, "arriving again gives nothing more")
	Shed.request({"a": "adventure_end"})
	check(not Adventure.active(), "Ride home ends it")
	# Ten more: each in its own spot, none on top of another.
	for k in 10:
		var p := AdventureDest.make_photo({"seed": k, "dest": "glacier", "km": 100.0}, ["A"])
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
	check(view.find_child("Picture", true, false) != null and cap != null and cap.text.contains("Tester") and cap.text.contains("150 km"),
		"the framed photo shows the picture, and the plate says where, how far and who (%s)" % (cap.text if cap else ""))
	view.free()
	Shed.stop()
	Progress.path = real_path


## The pictures and the album: each destination painted its own, the crew in front; an album
## per player, kept once, and your photos go up in your own shed.
func test_photo() -> void:
	var seen := {}
	for id in AdventureDest.DESTS:
		var img := AdventureDest.paint(id, 0)
		seen[img.get_data().hex_encode().sha256_text()] = id
		check(img.get_width() == AdventureDest.PIC_W and img.get_height() == AdventureDest.PIC_H, "%s's picture is painted" % id)
	check(seen.size() == AdventureDest.DESTS.size(), "every destination's picture is its own")
	var a := AdventureDest.paint("canyon", 0)
	var b := AdventureDest.paint("canyon", 3)
	check(a.get_data() != b.get_data(), "the photo has the crew stood in front")
	check(AdventureDest.picture("glacier", 2) == AdventureDest.picture("glacier", 2), "and it's painted once")
	check(AdventureDest.sanitize_photo({"key": "", "dest": "canyon"}).is_empty() and AdventureDest.sanitize_photo({"key": "x", "dest": "nowhere"}).is_empty()
		and not AdventureDest.sanitize_photo({"key": "x", "dest": "canyon", "names": ["A", 3]}).is_empty(), "a photo's record is checked")
	AdventureDest.album_path = ""
	AdventureDest._album_mem = {}
	var p1 := AdventureDest.sanitize_photo({"key": "k1", "dest": "lighthouse", "names": ["Ann", "Bob"], "km": 150, "date": "2026-10-19"})
	var p2 := AdventureDest.sanitize_photo({"key": "k2", "dest": "big_rally", "names": ["Ann"], "km": 100, "date": "2026-10-19"})
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
	check(not AdventureDest.photo_on_wall("k1").is_empty() and str(AdventureDest.photo_on_wall("k1")["photo"]["dest"]) == "lighthouse",
		"the photos are kept with the shed")
	check(not Trinkets.all().has(AdventureDest.PHOTO_MODEL), "the adventure photo isn't for sale in the Shop")
	Shed.stop()


# ---------------------------------------------------------------------------- the magazine

## The issues: every article to a real destination on a theme, its own seed; more issues as the
## host levels up; a theme the game doesn't have yet is ridden on varied roads.
func test_magazine_issues() -> void:
	var all := AdventureMag.all_articles()
	var seeds := {}
	var ids := {}
	var themes := {}
	for a in all:
		check(THEMES.has(str(a["theme"])) and AdventureDest.LENGTHS.has(str(a["len"])) and AdventureDest.exists(str(a["dest"]))
			and str(a["title"]) != "" and str(a["blurb"]) != "", "%s is a whole article" % a["id"])
		seeds[a["seed"]] = true
		ids[a["id"]] = true
		themes[a["theme"]] = true
	check(seeds.size() == all.size() and ids.size() == all.size(), "every article is its own road (%d)" % all.size())
	check(themes.size() == THEMES.size(), "every theme's in the magazine")
	var lens := {}
	for a in all:
		lens[a["len"]] = true
	check(lens.size() == 3, "short, ride and epic adventures")
	var out_at := func(level: int) -> int: return all.filter(func(a): return AdventureMag.unlocked(a, level)).size()
	check(out_at.call(1) == 5 and out_at.call(3) == 9 and out_at.call(6) == 12 and out_at.call(50) == all.size(),
		"new issues come out with level (%d, %d, %d of %d)" % [out_at.call(1), out_at.call(3), out_at.call(6), all.size()])
	check(AdventureMag.next_issue(1)["n"] == 2 and AdventureMag.next_issue(50).is_empty(), "the next issue's known")
	check(AdventureMag.road_theme("varied") == "varied" and AdventureMag.road_theme("nowhere") == "varied", "a theme the game lacks rides varied")
	for th in THEMES:
		check(Adventure.THEMES.has(AdventureMag.road_theme(th)), "a %s article starts on a road the game has" % th)
	# Starting one: a locked issue can't be.
	var real_path := Progress.path
	Progress.path = "user://profile_dest_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Tester", 5)
	Progress.select("Tester")
	Progress.profile["xp"] = 0
	var locked := AdventureMag.find("coast_canyon")
	var why := Adventure.check(Shed.me(), {"a": "adventure_start", "seed": 1, "km": 220.0, "theme": "varied", "dest": "canyon", "mag": "coast_canyon"})
	check(not AdventureMag.unlocked(locked, AdventureMag.level_now()) and why.contains("isn't out"), "a later issue's adventure waits for the level (%s)" % why)
	AdventureMag.start_article(AdventureMag.find("red_rock"), 100.0)
	check(Adventure.active() and str(Shed.adventure["dest"]) == "canyon" and float(Shed.adventure["km"]) == 100.0
		and Adventure.THEMES.has(str(Shed.adventure["theme"])), "the first issue's starts for the crew")
	Shed.request({"a": "adventure_end"})
	Shed.stop()
	Progress.path = real_path


## A page's facts: the route planned on a worker thread and counted (surfaces adding up, fuel and
## food on the way), the same as the road ridden.
func test_magazine_facts() -> void:
	var f := AdventureMag.route_facts(4101, 100.0, "varied", "canyon")
	var total := 0.0
	for s in f["surfaces"]:
		total += float(f["surfaces"][s])
	check(absf(total - 1.0) < 0.01 and int(f["fuel"]) >= 2 and int(f["food"]) >= 2, "a short ride's facts: %s" % str(f))
	var epic := AdventureMag.route_facts(4101, 220.0, "varied", "canyon")
	check(int(epic["sleep"]) >= 1 and int(epic["fuel"]) > int(f["fuel"]), "an epic has somewhere to sleep and more fuel stops")
	AdventureMag._facts_cache.clear()
	var first := AdventureMag.facts(4102, 100.0, "varied", "dales_rally")
	check(first.is_empty(), "worked out off the main thread: nothing at first")
	var got := await _until(func(): return not AdventureMag.facts(4102, 100.0, "varied", "dales_rally").is_empty(), 30.0)
	check(got and AdventureMag.facts(4102, 100.0, "varied", "dales_rally") == AdventureMag.route_facts(4102, 100.0, "varied", "dales_rally"),
		"then the same facts as planning it here")


## In the shed: the magazine on the workbench, read with {interact}, a page per adventure, the
## length picked, started for the crew from its page; the Esc menu's button opens it too.
func test_magazine_ui() -> void:
	AdventureTrip.instant = true
	AdventureDest.album_path = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	Progress.profile["xp"] = Progress.xp_for_level(7)
	await _ticks(2)
	var prop := main.workshop.find_child("AdventureMagazine", true, false) as Node3D
	var bench := Shed.surface("bench")
	var local: Vector3 = (bench["xf"] as Transform3D).affine_inverse() * prop.global_position if prop else Vector3.ZERO
	var rect: Rect2 = bench["rect"]
	check(prop != null and rect.grow(0.05).has_point(Vector2(local.x, local.z)) and absf(prop.global_position.y - float(bench["top"])) < 0.05,
		"the magazine lies on the workbench (%s)" % str(local))
	var body := prop.find_children("*", "StaticBody3D", true, false)[0] if prop else null
	check(body != null and body.get_meta("use_node") == prop and str(prop.use_text({})).contains("{interact}"), "with {interact} to read it")
	# Look at it and press interact.
	main.walker.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), prop.global_position + Vector3(0.9, -0.6, 0.0)))
	prop.use({})
	var mag: AdventureMag = main.trip.magazine
	check(mag != null and main.trip.magazine_open(), "it opens")
	check(mag.pages().size() == 13 and str(mag.pages()[12].get("id", "x")) == "", "level 7: three issues out, then the next one's coming (%d pages)" % mag.pages().size())
	mag.open("red_rock")
	check(mag._title.text == "The Red Rock Run" and mag._pic.texture != null and mag._kit.text.contains("tank"), "a page: title, picture, kit")
	await _until(func():
		mag.refresh()
		return mag._facts.text.contains("Surfaces"), 30.0)
	check(mag._facts.text.contains("100 km") and mag._facts.text.contains("Surfaces") and mag._facts.text.contains("fuel"),
		"its route: %s" % mag._facts.text.replace("\n", " / "))
	mag.turn(1)
	check(mag._title.text == "Dales Rally Weekender", "the next page's the next adventure")
	mag.turn(-1)
	mag.pick("epic")
	check(mag.km_of(mag.article()) == 220.0 and mag._facts.text.contains("night") and mag._kit.text.contains("night away"), "epic: 220 km and a night away")
	mag.pick(123.0)
	check(mag.km_of(mag.article()) == 123.0 and mag._km.visible, "or any km")
	mag.pick("short")
	check(not mag._start.disabled, "the host can start it")
	mag.start()
	await _ticks(10)
	check(not main.trip.magazine_open() and Adventure.active() and main.trip.on_trip() and str(Shed.adventure["mag"]) == "red_rock"
		and float(Shed.adventure["km"]) == 100.0 and str(Shed.adventure["title"]) == "The Red Rock Run", "Start puts the crew on it")
	Shed.request({"a": "adventure_end"})
	await _ticks(10)
	# The Esc menu's button opens the magazine.
	main.menu.show_pause()
	check(main.menu._adventure.text.contains("magazine") and not main.menu._adventure.disabled, "the Esc menu points to the magazine")
	main.menu._adventure.pressed.emit()
	await _frames(3)
	check(main.trip.magazine_open() and not main.menu.visible, "and opens it")
	main.trip.close_magazine()
	check(not main.trip.magazine_open(), "put it down again")
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
