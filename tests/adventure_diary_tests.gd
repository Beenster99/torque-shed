extends RefCounted
## The sat nav's trip computer and the Adventure Diary (v0.16.0, Simon: "add trip computer as
## part of satnav" and "At the end of an adventure pull together an Adventure Diary"): the trip
## computer's sums and its page, the crew's highlight log, taking photos without a stutter, and
## the diary put together, saved, read back and opened in its book. Run from tests/run_tests.gd:
## its _test_adv_diary_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

const ROOT := "user://zz_test_diaries"

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


func _until(cond: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


static func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)


## A picture to photograph headless (there's no screen): a gradient the size of a 1080p frame.
static func _frame_image() -> Image:
	var img := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	for y in range(0, 1080, 8):
		img.fill_rect(Rect2i(0, y, 1920, 8), Color(float(y) / 1080.0, 0.4, 1.0 - float(y) / 1080.0))
	return img


## The game with its session started and you on Old Faithful on an adventure, the photos going to
## the test's folder and taken of a made-up frame.
func _ride_out(km := 40.0, seed := 91) -> Node:
	AdventureTrip.instant = true
	AdventureDiary.root = ROOT
	_wipe(ROOT)
	var frame := _frame_image()
	PhotoCapture.fake_source = func(): return frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	main._left_bike = 0
	Rides.start(km, seed)
	await _ticks(10)
	return main


func _done(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	PhotoCapture.fake_source = Callable()
	Shed.stop()
	await t.get_tree().process_frame
	_wipe(ROOT)
	AdventureDiary.root = "user://diaries"


# ---------------------------------------------------------------------------- the trip computer

## The sums: distance and the clocks, the average on the move, the top speed, the petrol (a refill
## isn't petrol burnt), what it's averaging and the range, the climb and descent with the bumps
## left out, the arrival, and starting again.
func test_trip_maths() -> void:
	var tc := TripComputer.new()
	check(tc.average() == 0.0 and tc.economy() == 0.0 and tc.eta_seconds(1000.0) < 0.0 and tc.range_km(10.0) < 0.0,
		"nothing ridden: no average, no economy, no arrival, no range")
	check(absf(tc.range_km(10.0, 20.0) - 200.0) < 0.01, "before there's an average, the range is the bike's own figure (200 km on 10 L at 20 km/l)")
	# 100 s at 20 m/s burning 0.002 L a second, on the flat.
	var fuel := 10.0
	for i in 1000:
		tc.step(0.1, 20.0, 100.0, fuel, "tarmac")
		fuel -= 0.0002
	check(absf(tc.distance - 2000.0) < 0.5 and absf(tc.moving_time - 100.0) < 0.05, "100 s at 20 m/s: 2 km ridden in 100 s (%.1f m, %.1f s)" % [tc.distance, tc.moving_time])
	check(absf(tc.average() - 20.0) < 0.01 and absf(tc.top - 20.0) < 0.01, "average and top 20 m/s")
	check(absf(tc.fuel_used - 0.1998) < 0.002, "0.2 L burnt (%.4f)" % tc.fuel_used)
	check(absf(tc.economy() - 2.0 / tc.fuel_used) < 0.01, "averaging %.2f km/l" % tc.economy())
	check(absf(tc.range_km(5.0) - 5.0 * tc.economy()) < 0.01, "range: what's left at the average (%.1f km on 5 L)" % tc.range_km(5.0))
	# Stopped for a minute: the clock runs, the average's doesn't.
	for i in 600:
		tc.step(0.1, 0.0, 100.0, fuel, "tarmac")
	check(absf(tc.time - 160.0) < 0.1 and absf(tc.moving_time - 100.0) < 0.05 and absf(tc.average() - 20.0) < 0.01,
		"stopped a minute: %.0f s gone, still %.0f s on the move, the average still 20 m/s" % [tc.time, tc.moving_time])
	# A refill: the tank goes up, nothing burnt.
	var before := tc.fuel_used
	tc.step(0.1, 0.0, 100.0, 15.0, "tarmac")
	tc.step(0.1, 0.0, 100.0, 15.0, "tarmac")
	check(absf(tc.fuel_used - before) < 0.0001, "filling up isn't petrol burnt")
	# A faster burst.
	tc.step(0.1, 41.0, 100.0, 15.0, "gravel")
	check(absf(tc.top - 41.0) < 0.01 and tc.surface == "gravel", "the top speed is the fastest, and the ground's what's under the wheels now")
	# Up 200 m over 2 km with half a metre of bumps, then down 50.
	var hc := TripComputer.new()
	for i in 2001:
		hc.step(0.05, 20.0, 100.0 + i * 0.1 + (0.5 if i % 2 == 0 else -0.5), 10.0)
	for i in 501:
		hc.step(0.05, 20.0, 300.0 - i * 0.1 + (0.5 if i % 2 == 0 else -0.5), 10.0)
	check(hc.climb > 190.0 and hc.climb < 206.0, "climbed about 200 m, the bumps not counted (%.1f)" % hc.climb)
	check(hc.descent > 44.0 and hc.descent < 56.0, "and came down about 50 (%.1f)" % hc.descent)
	check(absf(hc.elevation - 250.0) < 1.0, "elevation now %.1f m" % hc.elevation)
	# The arrival: 10 km more at 20 m/s is 500 s; at a day an hour of real time, that's about 3.3 h on the clock.
	check(absf(tc.eta_seconds(10000.0) - 500.0) < 1.0, "10 km more at 20 m/s: 500 s (%.1f)" % tc.eta_seconds(10000.0))
	check(absf(tc.eta_clock(10000.0, 23.0, 24.0 / 3600.0) - wrapf(23.0 + 500.0 * 24.0 / 3600.0, 0.0, 24.0)) < 0.01, "and the clock time it'll be, past midnight")
	# Kept and put back, and starting again.
	var copy := TripComputer.new()
	copy.load_from(tc.save())
	check(absf(copy.distance - tc.distance) < 0.01 and absf(copy.average() - tc.average()) < 0.01 and absf(copy.fuel_used - tc.fuel_used) < 0.0001,
		"kept and put back the same")
	tc.reset()
	check(tc.distance == 0.0 and tc.top == 0.0 and tc.fuel_used == 0.0 and tc.climb == 0.0, "starting again from nothing")
	check(TripComputer.duration_text(3900.0) == "1 h 05 min" and TripComputer.duration_text(125.0) == "2 min", "times read %s and %s" % [
		TripComputer.duration_text(3900.0), TripComputer.duration_text(125.0)])
	var lines := copy.stats_lines(4.0, 20.0)
	check(lines.size() == 9 and str(lines[0][0]) == "Ridden", "the diary's stats: %d lines" % lines.size())


## The page on the sat nav: on an adventure, how far to go and the next fuel, food and bed along
## the way, the arrival time; {satnav_hud} goes round the map, the trip page and the HUD off; and
## in a real ride the adventure's trip computer runs for the whole ride (getting off and on again
## doesn't start it again), while in town each ride is a trip of its own.
func test_trip_page() -> void:
	var adv := AdventureWorld.new()
	adv.setup(Rides.pack(60.0), 42, 60.0)
	adv.focus = func(): return [adv.transform_at(20.0).origin]
	t.add_child(adv)
	var nav := Satnav.AdventureNav.new(adv)
	var s := 1500.0
	var at := adv.transform_at(s)
	var tc := TripComputer.new()
	for i in 600:
		tc.step(0.1, 25.0, at.origin.y, 10.0 - i * 0.0003, "tarmac")
	var v := Satnav.trip_view(tc, nav, at.origin, -at.basis.z, 9.8, 20.0)
	check(absf(float(v["to_go"]) - (adv.route.length - s)) < 30.0, "to go: %.0f m (the road's %.0f m from here)" % [float(v["to_go"]), adv.route.length - s])
	var want := {}
	for st in adv.route.sites:
		var k := str(AdventureStops.NAV.get(str(st["kind"]), ""))
		if k != "" and not want.has(k) and float(st["s"]) > s - 15.0 and float(st["s"]) <= adv.route.length:
			want[k] = float(st["s"]) - s
	for k in ["fuel", "food", "sleep"]:
		var got := float((v["next"] as Dictionary).get(k, -1.0))
		check((not want.has(k) and got < 0.0) or (want.has(k) and absf(got - maxf(float(want[k]), 0.0)) < 1.0),
			"the next %s: %.0f m (along the road it's %s)" % [k, got, str(want.get(k, "none"))])
	check(absf(float(v["average"]) - 25.0) < 0.01 and float(v["eta_s"]) > 0.0 and absf(float(v["eta_s"]) - float(v["to_go"]) / 25.0) < 1.0,
		"the arrival at the average so far: %.0f s" % float(v["eta_s"]))
	check(float(v["eta"]) >= 0.0 and float(v["eta"]) < 24.0 and str(v["surface"]) == "Tarmac", "a clock time to arrive, and on tarmac")
	# The screen draws it (on the unit's size and the HUD's) without falling over.
	var scr := SatnavScreen.new()
	scr.size = Vector2(KitModel.SCREEN_PX)
	t.add_child(scr)
	var view := Satnav.view_for(nav, at.origin, -at.basis.z, 25.0)
	view["page"] = "trip"
	view["trip"] = v
	scr.show_view(view)
	await _frames(2)
	check(scr.view.get("page") == "trip", "the screen's on its trip page")
	scr.queue_free()
	adv.queue_free()
	# The key goes round the pages.
	var was_hud := Settings.satnav_hud
	Settings.satnav_hud = true
	Satnav.page = "map"
	var said := [Satnav.next_page()]
	var p1 := Satnav.page
	said.append(Satnav.next_page())
	var off := not Settings.satnav_hud
	said.append(Satnav.next_page())
	check(p1 == "trip" and off and Settings.satnav_hud and Satnav.page == "map", "map, then the trip computer, then off the HUD, then the map again %s" % str(said))
	Settings.satnav_hud = was_hud
	# Riding: the adventure's trip computer, through getting off and on again.
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	check(main.satnav != null and main.satnav.computer() == trip.computer, "out on the adventure the sat nav reads the adventure's trip computer")
	main.bike.place(trip.world.transform_at(400.0).origin, trip.world.heading_at(400.0))
	main.bike.linear_velocity = -trip.world.transform_at(400.0).basis.z * 20.0
	await _ticks(240)
	var ridden := trip.computer.distance
	check(ridden > 15.0 and trip.computer.top > 5.0, "it counts as you ride (%.0f m, top %.1f m/s)" % [ridden, trip.computer.top])
	Satnav.page = "trip"
	main.satnav.refresh()
	check(main.satnav.screen.view.get("trip") is Dictionary and absf(float(main.satnav.screen.view["trip"]["ridden"]) - trip.computer.distance) < 30.0,
		"the trip page on the bars shows it")
	Satnav.page = "map"
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(120)
	main._get_off()
	await _ticks(20)
	main._left_bike = 0
	var id: int = t._bike_named("Old Faithful")
	Shed.request({"a": "mount", "bike": id})
	await _ticks(20)
	check(main.bike != null and trip.computer.distance >= ridden, "back on: the adventure's trip goes on (%.0f m)" % trip.computer.distance)
	await _done(main)


# ---------------------------------------------------------------------------- the highlight log

## The host's log of the crew's highlights: setting off, a stop (once, with everyone who stopped
## there), a new surface, a peak, a fine, a breakdown and its fix, a tow,
## sunrise and sunset; each with when, how far and who. Only highlights are taken; the oldest go
## past the cap.
func test_highlight_log() -> void:
	Shed.start_new("Tester", 9)
	Shed.crew[2] = {"name": "Dave"}
	Rides.start(30.0, 77)
	var adv := Shed.adventure
	var diary := str(adv.get("diary", ""))
	var first := AdventureDiary.log_entries()
	check(diary != "" and first.size() == 1 and str(first[0]["kind"]) == "start" and float(first[0]["s"]) == 0.0,
		"an adventure starts its diary (%s) with setting off: %s" % [diary, str(first[0].get("text", "")) if not first.is_empty() else ""])
	Shed.request({"a": "adventure_highlight", "kind": "stop", "key": "stop_5200", "s": 5210.0, "what": "the lay-by"})
	AdventureDiary.apply(2, {"kind": "stop", "key": "stop_5200", "s": 5230.0, "what": "the lay-by"})
	var stops := AdventureDiary.log_entries().filter(func(e): return str(e["kind"]) == "stop")
	check(stops.size() == 1 and (stops[0]["who"] as Array) == ["Tester", "Dave"] and str(stops[0]["text"]) == "Stopped at the lay-by",
		"a stop's one highlight, with both who stopped there: %s %s" % [str(stops[0].get("text", "")) if not stops.is_empty() else "", str(stops[0].get("who", "")) if not stops.is_empty() else ""])
	Shed.request({"a": "adventure_highlight", "kind": "surface", "key": "surf_40", "s": 5120.0, "what": "gravel"})
	Shed.request({"a": "adventure_highlight", "kind": "peak", "key": "peak_8000", "s": 8000.0, "h": 612.0})
	Shed.request({"a": "adventure_highlight", "kind": "breakdown", "s": 9000.0, "what": "Ran out of petrol"})
	Shed.request({"a": "adventure_highlight", "kind": "nonsense", "s": 9000.0})
	Shed.request({"a": "adventure_highlight", "kind": "sunset", "key": "sunset_0", "s": 9100.0})
	AdventureDiary.fined(2, 250, 42)
	AdventureDiary.fixed(1, "Slack chain")
	AdventureDiary.towed(2, 1)
	var by := {}
	for e in AdventureDiary.log_entries():
		by[str(e["kind"])] = e
	check(str(by.get("surface", {}).get("text", "")) == "Onto gravel", "onto a new surface: %s" % str(by.get("surface", {}).get("text", "")))
	check(str(by.get("peak", {}).get("text", "")).contains("612"), "a high point: %s" % str(by.get("peak", {}).get("text", "")))
	check(str(by.get("breakdown", {}).get("text", "")) == "Broke down: ran out of petrol", "a breakdown: %s" % str(by.get("breakdown", {}).get("text", "")))
	check(not by.has("nonsense"), "only highlights go in the log")
	check(str(by.get("fine", {}).get("text", "")).contains("£250") and (by.get("fine", {}).get("who", []) as Array) == ["Dave"], "a fine, Dave's")
	check(by.has("fix") and by.has("tow") and (by.get("tow", {}).get("who", []) as Array).size() == 2, "a roadside fix and a tow")
	check(by.has("sunset") and (by["sunset"]["who"] as Array).is_empty(), "sunset, everyone's")
	var e: Dictionary = by["fine"]
	check(e.has("hours") and e.has("day") and e.has("t") and e.has("s"), "each with the clock, the day, the time since setting off and the km")
	var when := AdventureDiary.when_text(by["stop"])
	check(when.contains("5.2 km in") and when.contains("Tester, Dave"), "said as: %s" % when)
	# Arriving.
	Shed.request({"a": "adventure_arrive"})
	check(not AdventureDiary.find("arrive").is_empty(), "arriving")
	# The sun.
	check(AdventureDiary.sun_crossed(5.9, 6.05) == "sunrise" and AdventureDiary.sun_crossed(17.95, 18.1) == "sunset"
		and AdventureDiary.sun_crossed(12.0, 12.1) == "" and AdventureDiary.sun_crossed(5.0, 19.0) == "" and AdventureDiary.sun_crossed(23.9, 0.1) == "",
		"sunrise and sunset as the clock goes past 6 and 18 (a jump of the clock isn't one)")
	# The log's a Dictionary by n: the crew are sent only what's new.
	check(Shed.adventure["log"] is Dictionary, "kept by number, so only new highlights go to the crew")
	for i in AdventureDiary.MAX_LOG + 10:
		AdventureDiary.note("breakdown", "", ["Tester"], 100.0 * i, "Broke down %d" % i)
	var all := AdventureDiary.log_entries()
	check(all.size() == AdventureDiary.MAX_LOG and int(all[-1]["n"]) > int(all[0]["n"]), "no more than %d kept, the oldest gone (%d)" % [AdventureDiary.MAX_LOG, all.size()])
	Shed.request({"a": "adventure_end"})
	Shed.stop()


## Out riding: stood still at a stop, onto a new surface and over the top of a climb make the
## rider's highlights, each with its photo in this machine's diary; and the start's photo.
func test_highlights_ride() -> void:
	var main: Node = await _ride_out(60.0, 4102)
	var trip: AdventureTrip = main.trip
	var r := trip.world.route
	var got_start := await _until(func(): return trip.photos.photos.any(func(p): return str(p["kind"]) == "start"), 8.0)
	check(got_start, "a photo of setting off")
	# A stop: stood still beside it for a few seconds.
	var site := {}
	for st in r.sites:
		if AdventureStops.NAV.has(str(st["kind"])) and float(st["s"]) > 600.0 and float(st["s"]) < r.length - 1000.0:
			site = st
			break
	check(not site.is_empty(), "a stop along the road (%s at %.0f m)" % [str(site.get("kind", "")), float(site.get("s", 0.0))])
	if not site.is_empty():
		trip.jump(float(site["s"]) - trip.world.distance_of(main.bike.global_position, "own"))
		main.bike.linear_velocity = Vector3.ZERO
		await _ticks(5)
		var key := "stop_%d" % int(float(site["s"]))
		var logged := await _until(func():
			main.bike.linear_velocity = Vector3.ZERO
			return not AdventureDiary.find(key).is_empty(), 10.0)
		var e := AdventureDiary.find(key)
		check(logged and (e.get("who", []) as Array).has("Tester") and absf(float(e["s"]) - float(site["s"])) < 120.0,
			"stopped there: %s (%s)" % [str(e.get("text", "")), AdventureDiary.when_text(e) if not e.is_empty() else ""])
		var photo := await _until(func(): return trip.photos.photos.any(func(p): return str(p["key"]) == key), 8.0)
		check(photo, "and its photo's in the diary")
	# A peak: ridden over the top (the hills' own, and one put where the test can reach it).
	var peaks := AdventureDiary.peaks(r)
	check(not peaks.is_empty(), "the hills have high points (%d, the highest %.0f m)" % [peaks.size(), peaks.map(func(p): return float(p["h"])).max() if not peaks.is_empty() else 0.0])
	var alps := Rides.tour_route("dales", 91)
	var alp_peaks := AdventureDiary.peaks(alps)
	check(alp_peaks.size() >= 2 and alp_peaks.size() <= AdventureDiary.PEAKS, "the Dales have their tops (%d), never more than %d" % [alp_peaks.size(), AdventureDiary.PEAKS])
	var tops_ok := true
	for p in alp_peaks:
		for k in range(-30, 31):
			var q := float(p["s"]) + k * AdventureDiary.SAMPLE
			if q >= 0.0 and q <= alps.length and alps.height_at_s(q) > float(p["h"]) + 0.01:
				tops_ok = false
	check(tops_ok, "each the top of its climb: nothing higher for %.1f km either side" % (AdventureDiary.PEAK_REACH / 1000.0))
	var ps := trip.world.distance_of(main.bike.global_position, "own") + 300.0
	trip.photos._peaks = [{"s": ps, "h": r.height_at_s(ps)}]
	trip.photos._peaks_found = true
	trip.jump(250.0)
	await _ticks(40)
	trip.jump(100.0)
	var over := await _until(func(): return not AdventureDiary.find("peak_%d" % int(ps)).is_empty(), 5.0)
	check(over, "over the top at %.0f m: %s" % [ps, str(AdventureDiary.find("peak_%d" % int(ps)).get("text", ""))])
	# A new surface, well onto it.
	var surf_s := -1.0
	var last := r.surface_at_s(0.0)
	var s := 0.0
	while s < r.length - 300.0:
		if r.surface_at_s(s) != last and s > 300.0 and r.surface_at_s(s + 100.0) == r.surface_at_s(s):
			surf_s = s
			break
		last = r.surface_at_s(s)
		s += 32.0
	if surf_s > 0.0:
		trip.jump(surf_s - 60.0 - trip.world.distance_of(main.bike.global_position, "own"))
		await _ticks(40)
		trip.jump(110.0)
		var onto := await _until(func(): return AdventureDiary.log_entries().any(func(x): return str(x["kind"]) == "surface"), 5.0)
		check(onto, "onto %s at %.0f m: logged" % [r.surface_at_s(surf_s), surf_s])
	await _done(main)


# ---------------------------------------------------------------------------- the photos

## Photos and a clip taken while riding cost the main thread next to nothing: the ask, the hand
## over and each frame's upkeep stay small, the shrinking and the JPEG on a worker; the HUD's back
## after the frame it was hidden for; the files are the photo's size, and the clip a sheet of its
## frames.
func test_capture_cost() -> void:
	_wipe(ROOT)
	var frame := _frame_image()
	PhotoCapture.fake_source = func(): return frame
	var cap := PhotoCapture.new()
	t.add_child(cap)
	await _frames(2)
	var saved := []
	cap.saved.connect(func(j): saved.append(j))
	var vp := t.get_viewport()
	var cull := vp.canvas_cull_mask
	var worst_tick := 0.0
	var worst_hand := 0.0
	var worst_ask := 0.0
	for i in 3:
		cap.snap({"path": ROOT.path_join("cost/p%d.jpg" % i), "kind": "photo"})
		worst_ask = maxf(worst_ask, cap.last_ask_ms)
		var hidden := vp.canvas_cull_mask == 0
		await _until(func(): return not cap._armed, 2.0)
		worst_hand = maxf(worst_hand, cap.last_hand_ms)
		check(hidden and vp.canvas_cull_mask == cull, "photo %d: the HUD out of the frame taken, and back after it" % i)
		for k in 6:
			await _frames(1)
			worst_tick = maxf(worst_tick, cap.last_tick_ms)
	cap.film({"path": ROOT.path_join("cost/clip.jpg"), "kind": "clip"})
	var done := await _until(func():
		worst_tick = maxf(worst_tick, cap.last_tick_ms)
		worst_hand = maxf(worst_hand, cap.last_hand_ms)
		return saved.size() >= 4 and not cap.busy(), 20.0)
	check(done, "three photos and a clip saved (%d)" % saved.size())
	# Doing the same work on the main thread, for comparison: what it would have stalled.
	var t0 := Time.get_ticks_usec()
	var inline := PhotoCapture.fit(frame.duplicate(), PhotoCapture.PHOTO_W, PhotoCapture.PHOTO_H)
	inline.save_jpg_to_buffer(PhotoCapture.JPEG_QUALITY)
	var inline_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(worst_ask < 2.0 and worst_hand < 3.0, "asking %.2f ms, handing over %.2f ms at most" % [worst_ask, worst_hand])
	check(worst_tick < 2.5, "each frame's upkeep %.2f ms at most (shrinking and saving one here takes %.1f ms: done on a worker)" % [worst_tick, inline_ms])
	var p0 := Image.load_from_file(ROOT.path_join("cost/p0.jpg"))
	check(p0 != null and p0.get_width() == PhotoCapture.PHOTO_W and p0.get_height() == PhotoCapture.PHOTO_H, "a photo's %dx%d" % [p0.get_width() if p0 else 0, p0.get_height() if p0 else 0])
	var clip := saved.filter(func(j): return bool(j.get("clip", false)))
	var sheet := Image.load_from_file(ROOT.path_join("cost/clip.jpg"))
	check(not clip.is_empty() and int(clip[0]["got"]) == PhotoCapture.CLIP_FRAMES and sheet != null
		and sheet.get_width() == PhotoCapture.CLIP_W * PhotoCapture.CLIP_COLS and sheet.get_height() == PhotoCapture.CLIP_H * 3,
		"the clip: %d frames on a %dx%d sheet" % [int(clip[0].get("got", 0)) if not clip.is_empty() else 0, sheet.get_width() if sheet else 0, sheet.get_height() if sheet else 0])
	# With nothing to take a picture of (headless, no screen), it says so and nothing waits.
	PhotoCapture.fake_source = Callable()
	var failed := []
	cap.saved.connect(func(j): if bool(j.get("failed", false)): failed.append(j))
	cap.snap({"path": ROOT.path_join("cost/none.jpg")})
	await _until(func(): return not failed.is_empty(), 3.0)
	check(failed.size() == 1 and not FileAccess.file_exists(ROOT.path_join("cost/none.jpg")), "no picture to take: nothing saved, and it's told")
	cap.queue_free()
	await _frames(1)
	_wipe(ROOT)


## In a ride: the frame times while photos and a clip are being taken stay level with those
## without (the work's on workers); taking one with a mate in shot names them.
func test_capture_ride() -> void:
	var main: Node = await _ride_out()
	var trip: AdventureTrip = main.trip
	await _ticks(60)
	var calm := []
	for i in 60:
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		calm.append((Time.get_ticks_usec() - t0) / 1000.0)
	var busy := []
	trip.photos.snap("photo", "")
	trip.photos.film()
	for i in 120:
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		busy.append((Time.get_ticks_usec() - t0) / 1000.0)
		if i % 30 == 10:
			trip.photos.snap("photo", "")
	calm.sort()
	busy.sort()
	var calm_hi: float = calm[int(calm.size() * 0.95)]
	var busy_hi: float = busy[int(busy.size() * 0.95)]
	check(busy_hi < calm_hi * 1.6 + 4.0, "frames while taking photos: 95%% under %.1f ms (%.1f without)" % [busy_hi, calm_hi])
	var got := await _until(func(): return trip.photos.photos.filter(func(p): return str(p["kind"]) in ["photo", "clip"]).size() >= 5, 10.0)
	check(got, "the photos and the clip are in the diary (%d)" % trip.photos.photos.size())
	var cap := trip.photos.photos.filter(func(p): return str(p["kind"]) == "photo")
	check(not cap.is_empty() and str(cap[0]["caption"]) != "", "a photo you take says where: %s" % (str(cap[0]["caption"]) if not cap.is_empty() else ""))
	# The camera up on foot: first person, zoomed, put away on the bike.
	main.bike.linear_velocity = Vector3.ZERO
	await _ticks(120)
	main._get_off()
	await _ticks(10)
	check(trip.photos.raise_camera() == "" and trip.photos.camera_up and main.walker.view.forced_reason() == "taking photos", "on foot the camera comes up to your eye (first person)")
	trip.photos.zoom = 3.0
	trip.photos._apply_zoom()
	check(main.walker.camera.fov < Settings.gfx_fov * 0.5, "zoomed in (%.0f degrees)" % main.walker.camera.fov)
	trip.photos.lower_camera()
	check(not trip.photos.camera_up and absf(main.walker.camera.fov - Settings.gfx_fov) < 0.01, "put away, the view's as it was")
	await _done(main)


# ---------------------------------------------------------------------------- the diary

## A diary saved and read back: the highlights, the photos, the stats and the route; on the
## shelf; found from the photo on the shed wall; and in the book, its pages: the cover, the stats
## and route strip, the photos two to a page (the clip playing), the log.
func test_diary_files() -> void:
	AdventureDiary.root = ROOT
	_wipe(ROOT)
	var id := "1700000000_77"
	DirAccess.make_dir_recursive_absolute(AdventureDiary.folder(id))
	var img := _frame_image()
	var small := PhotoCapture.fit(img.duplicate(), PhotoCapture.PHOTO_W, PhotoCapture.PHOTO_H)
	small.save_jpg(AdventureDiary.folder(id).path_join("p001.jpg"))
	var sheet := Image.create(PhotoCapture.CLIP_W * 4, PhotoCapture.CLIP_H * 3, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.3, 0.5, 0.2))
	sheet.save_jpg(AdventureDiary.folder(id).path_join("c002.jpg"))
	var r := Rides.route(30.0, 77)
	var tc := TripComputer.new()
	for i in 200:
		tc.step(1.0, 20.0, 100.0 + i, 10.0 - i * 0.01, "gravel")
	var d := {"id": id, "title": "Dales Rally Weekender", "dest": "Hawes", "theme": "hills", "km": 30.0, "date": "2026-10-19",
		"crew": ["Tester", "Dave"], "me": "Tester",
		"log": [{"n": 1, "kind": "start", "key": "start", "text": "Set off", "who": [], "s": 0.0, "hours": 9.0, "day": 0, "t": 0},
			{"n": 2, "kind": "stop", "key": "stop_5200", "text": "Stopped at the lay-by", "who": ["Tester", "Dave"], "s": 5210.0, "hours": 9.5, "day": 0, "t": 600},
			{"n": 3, "kind": "nonsense", "key": "", "text": "x", "who": [], "s": 0.0, "hours": 9.0, "day": 0, "t": 0},
			{"n": 4, "kind": "arrive", "key": "arrive", "text": "Arrived", "who": [], "s": 30000.0, "hours": 11.0, "day": 0, "t": 4000}],
		"photos": [{"file": "p001.jpg", "caption": "Dave, at the lay-by", "kind": "stop", "key": "stop_5200", "who": ["Dave"], "s": 5210.0, "hours": 9.5, "day": 0},
			{"file": "c002.jpg", "caption": "On film", "kind": "clip", "key": "", "clip": true, "frames": 12, "got": 12, "cols": 4, "rows": 3,
				"cell_w": PhotoCapture.CLIP_W, "cell_h": PhotoCapture.CLIP_H, "s": 9000.0, "hours": 10.0, "day": 0}],
		"stats": tc.save(), "route": AdventureDiary.route_summary(r), "photo": {"key": "77-dales_rally-1700000000", "dest": "dales_rally", "title": "Dales Rally Weekender",
			"names": ["Tester", "Dave"], "km": 30, "date": "2026-10-19"}, "done": true, "saved_at": 1700000000}
	check(AdventureDiary.save_diary(d), "saved")
	var back := AdventureDiary.load_diary(id)
	check(str(back["title"]) == "Dales Rally Weekender" and (back["crew"] as Array) == ["Tester", "Dave"], "read back: the title and the crew")
	check((back["log"] as Array).size() == 3, "the highlights (anything that isn't one left out): %d" % (back["log"] as Array).size())
	check((back["photos"] as Array).size() == 2 and bool(back["photos"][1]["clip"]), "the photos and the clip")
	check(absf(float(back["stats"]["distance"]) - tc.distance) < 0.1 and (back["route"]["h"] as Array).size() > 100, "the stats and the route")
	var shelf := AdventureDiary.list()
	check(shelf.size() == 1 and str(shelf[0]["id"]) == id and str(shelf[0]["cover"]).ends_with("p001.jpg"), "on the shelf, its first photo for a cover")
	check(AdventureDiary.find_by_photo("77-dales_rally-1700000000") == id and AdventureDiary.find_by_photo("nope") == "", "found from the photo on the shed wall")
	# The book.
	var book := DiaryBook.new()
	t.add_child(book)
	await _frames(1)
	check(book.open_diary(id), "opens in the book")
	var kinds := book.pages.map(func(p): return str(p["kind"]))
	check(kinds.slice(0, 4) == ["cover", "stats", "photos", "log"], "its pages: %s" % str(kinds))
	check(book.texture_of("p001.jpg") != null and book.texture_of("missing.jpg") == null, "the photos load as their page is shown")
	check(book.entry_of(back["photos"][0]).get("text", "") == "Stopped at the lay-by", "a photo's caption is its highlight's")
	book.turn(1)
	await _frames(2)
	var page: Dictionary = book._left.page
	check(str(page.get("kind", "")) == "photos" and book.spread == 1, "turned to the photos")
	var f0: int = book._left._frame
	await t.get_tree().create_timer(0.6).timeout
	check(book._left._frame != f0, "the clip plays (frame %d to %d)" % [f0, book._left._frame])
	book.turn(5)
	check(book.spread == (book.pages.size() - 1) / 2, "no turning past the back cover")
	book.open_shelf()
	check(book._shelf.visible and not book._book.visible and book._shelf_grid.get_child_count() == 1, "the shelf: one diary")
	book.queue_free()
	# The shed's diary shelf: the newest face out with the ride's snapshot on its cover.
	check(AdventureDiary.cover_photo(back) == "p001.jpg", "the cover's snapshot is the first still, not the clip")
	var case := DiaryShelf.new()
	t.add_child(case)
	await _frames(1)
	check(case.count() == 1 and case.find_child("FaceOut", true, false) != null and case.find_child("Snapshot", true, false) != null
		and case.use_text({}).contains("Dales Rally Weekender"), "on the shed's shelf, face out with its snapshot (%s)" % case.use_text({}))
	# Only the latest are kept.
	for i in AdventureDiary.MAX_DIARIES + 2:
		var e := d.duplicate(true)
		e["id"] = "x_%d" % i
		e["saved_at"] = 1700000001 + i
		e["photos"] = []
		AdventureDiary.save_diary(e)
	check(AdventureDiary.list().size() == AdventureDiary.MAX_DIARIES and AdventureDiary.load_diary(id).is_empty(), "no more than %d diaries kept, the oldest gone" % AdventureDiary.MAX_DIARIES)
	await _frames(1)
	var spines := case.find_children("Spine*", "", true, false).size()
	check(case.count() == AdventureDiary.MAX_DIARIES and spines == AdventureDiary.MAX_DIARIES - 1, "the shelf restocks itself: %d diaries, %d spines" % [case.count(), spines])
	case.queue_free()
	_wipe(ROOT)
	AdventureDiary.root = "user://diaries"


## A whole ride: to the destination, the arrival's photo in the moment, the diary put together
## there; Ride home puts it together again and opens it at the shed; the route planner opens it again.
func test_diary_ride() -> void:
	var main: Node = await _ride_out(8.0, 4101)
	var trip: AdventureTrip = main.trip
	await _until(func(): return trip.photos.photos.size() >= 1, 6.0)
	var id := trip.photos.diary_id
	check(id != "" and id == str(Shed.adventure.get("diary", "")), "this machine's diary is the adventure's (%s)" % id)
	trip.photos.snap("photo", "")
	trip.jump(trip.world.route.length - trip.world.distance_of(main.bike.global_position, "own") - 4.0)
	await _until(func():
		if main.bike and int(Shed.adventure.get("arrived", 0)) == 0:
			main.bike.throttle = 0.4
		return int(Shed.adventure.get("arrived", 0)) != 0, 15.0)
	var through := await _until(func(): return trip.moment_done and trip.moment_t < 0.0, 20.0)
	check(through, "arrived, and the moment's played")
	var d := AdventureDiary.load_diary(id)
	check(not d.is_empty() and bool(d["done"]), "the diary's put together at the destination")
	check((d.get("photos", []) as Array).any(func(p): return str(p["kind"]) == "arrive"), "with the crew's photo at the destination")
	var kinds := (d.get("log", []) as Array).map(func(e): return str(e["kind"]))
	check(kinds.has("start") and kinds.has("arrive"), "the highlights from setting off to arriving: %s" % str(kinds))
	check(not (d.get("route", {}) as Dictionary).is_empty() and float(d["stats"].get("distance", 0.0)) > 0.0, "the route strip and the trip's stats")
	var wall := str((d.get("photo", {}) as Dictionary).get("key", ""))
	check(wall != "" and wall == str(Shed.adventure.get("photo", {}).get("key", "")), "it keeps the arrival's photo")
	# Ride home: back at the shed, the book's open at it.
	Adventure.menu_action()
	var home := await _until(func(): return not trip.on_trip() and trip.diary_open(), 15.0)
	check(home and trip.diary.diary.get("id", "") == id, "Ride home: back at the shed the diary's open")
	trip.close_diary()
	# Never left in the black: a trip there or back that stopped part way (a script error, say) lifts it.
	await main._fade_to(1.0)
	trip._busy = true
	trip._watch_black(AdventureTrip.STUCK_BLACK - 1.0)
	var held: bool = main._fade.color.a > 0.9
	trip._watch_black(1.5)
	await _until(func(): return main._fade.color.a < 0.01, 5.0)
	check(held and main._fade.color.a < 0.01 and not trip._busy and not trip.on_trip(),
		"a screen stuck black going home lifts after %.0f s" % AdventureTrip.STUCK_BLACK)
	check(AdventureDest.photo_on_wall(wall).is_empty(), "and nothing goes up on the shed wall: the diary's on the bookshelf")
	# A shed TV's planner opens the same planner full screen; the full-screen one has no such button.
	var wall_tv := RouteTv.new()
	wall_tv.on_wall = true
	main.add_child(wall_tv)
	check(wall_tv._full.visible, "a shed TV's route planner has a Full screen button")
	wall_tv.full_screen()
	await main.get_tree().process_frame
	check(trip.journey_open() and not trip.journey_map.planner._full.visible, "which opens the route planner full screen (and that one has none)")
	wall_tv.queue_free()
	trip.close_journey()
	# From the route planner: the shelf.
	trip.open_journey()
	trip.open_diary()
	check(trip.diary_open() and trip.diary._shelf.visible and not trip.journey_open(), "the route planner's Adventure diaries: the shelf")
	trip.close_diary()
	await _done(main)


# ---------------------------------------------------------------------------- films and sharing (v0.19.0)

const CLIPS := "user://zz_test_clips"


## The film's file (Simon: "can you make movie clip for 10 seconds"): an AVI of JPEG frames that
## reads back with the header's size, rate and frame count, every frame in the "movi" list and the
## index pointing at each, and the frames the same pictures; an odd-length frame padded.
func test_movie_avi() -> void:
	var cols := [Color(0.9, 0.2, 0.1), Color(0.1, 0.8, 0.2), Color(0.1, 0.2, 0.9), Color(0.9, 0.9, 0.1), Color(0.6, 0.1, 0.7)]
	var frames := []
	for c in cols:
		var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
		img.fill(c)
		frames.append(img.save_jpg_to_buffer(0.9))
	if (frames[2] as PackedByteArray).size() % 2 == 0:
		var odd: PackedByteArray = frames[2]
		odd.append(0)   # (bytes after a JPEG's end are let be)
		frames[2] = odd
	var avi := MjpegAvi.build(frames, 64, 36, 24)
	check(avi.slice(0, 4).get_string_from_ascii() == "RIFF" and avi.slice(8, 12).get_string_from_ascii() == "AVI "
		and int(avi.decode_u32(4)) + 8 == avi.size(), "a RIFF AVI, its length right (%d bytes)" % avi.size())
	var back := MjpegAvi.parse(avi)
	check(bool(back["ok"]) and int(back["w"]) == 64 and int(back["h"]) == 36 and int(back["fps"]) == 24 and str(back["handler"]) == "MJPG",
		"its header: %dx%d at %d fps, %s" % [int(back["w"]), int(back["h"]), int(back["fps"]), str(back["handler"])])
	check(int(back["frames"]) == 5 and (back["jpegs"] as Array).size() == 5 and int(back["index"]) == 5 and bool(back["index_ok"]),
		"5 frames in the header, the movi list and the index (%d, %d, %d), the index pointing at each" % [int(back["frames"]), (back["jpegs"] as Array).size(), int(back["index"])])
	var same := true
	for i in 5:
		var img := Image.new()
		if (back["jpegs"][i] as PackedByteArray) != (frames[i] as PackedByteArray) or img.load_jpg_from_buffer(back["jpegs"][i]) != OK:
			same = false
			continue
		var c := img.get_pixel(32, 18)
		same = same and absf(c.r - cols[i].r) < 0.08 and absf(c.g - cols[i].g) < 0.08 and absf(c.b - cols[i].b) < 0.08
	check(same, "each frame's bytes as they went in, and the picture they were")
	check(not bool(MjpegAvi.parse(PackedByteArray([1, 2, 3, 4]))["ok"]) and not bool(MjpegAvi.parse(avi.slice(0, 200))["ok"]), "rubbish (or a cut-off file) isn't read as one")


## The film's countdown and filming: {movie} counts 3, 2, 1, films LENGTH seconds at FPS with REC
## and the seconds left, the REC layer kept out of the frames, and saves an AVI that reads back
## with every frame, its poster frame in the diary's folder; called off in the countdown nothing's
## saved; stopped early, it's as long as it went on. Asking for frames costs the frame nothing.
func test_movie_states() -> void:
	_wipe(CLIPS)
	MovieClip.root = CLIPS
	var frame := _frame_image()
	MovieClip.fake_source = func(): return frame
	var clip := MovieClip.new()
	t.add_child(clip)
	clip.set_process(false)   # (moved on by hand, a frame at a time)
	await _frames(1)
	var got := []
	clip.saved.connect(func(info): got.append(info))
	var vp := t.get_viewport()
	var step := 1.0 / MovieClip.FPS
	# Called off.
	check(clip.start({}) == "" and clip.state == MovieClip.State.COUNTDOWN and clip.count() == 3 and clip._overlay.visible, "{movie}: the countdown starts at 3")
	check(clip.start({}) != "", "only one at a time")
	clip.tick(1.2)
	check(clip.count() == 2, "then 2")
	clip.press()
	check(clip.state == MovieClip.State.IDLE and not clip._overlay.visible and not DirAccess.dir_exists_absolute(CLIPS), "again in the countdown calls it off: nothing filmed")
	# The whole film.
	var poster := ROOT.path_join("film/m001.jpg")
	clip.start({"poster_path": poster, "caption": "On film"})
	var counts := []
	while clip.state == MovieClip.State.COUNTDOWN:
		if not counts.has(clip.count()):
			counts.append(clip.count())
		clip.tick(0.25)
	check(counts == [3, 2, 1] and clip.state == MovieClip.State.FILMING, "3, 2, 1, then it films (%s)" % str(counts))
	check(absf(clip.seconds_left() - MovieClip.LENGTH) < 0.3, "%.1f seconds left as it starts" % clip.seconds_left())
	var hidden := 0
	var asked := 0
	var running := 0
	var last_arm := -1
	var left_mid := -1.0
	var ticks := []
	var grabs := []
	var began := Time.get_ticks_msec()
	while clip.state == MovieClip.State.FILMING:
		# (On the clock, as the game would be: the workers keep up.)
		while Time.get_ticks_msec() - began < clip.asked * 1000.0 / MovieClip.FPS:
			await _frames(1)
		var t0 := Time.get_ticks_usec()
		clip.tick(step)
		ticks.append((Time.get_ticks_usec() - t0) / 1000.0)
		if clip._armed:
			asked += 1
			if vp.canvas_cull_mask & MovieClip.LAYER == 0:
				hidden += 1
			if last_arm >= 0 and clip._armed_at != last_arm and clip._armed_at - last_arm < 2:
				running += 1
			last_arm = clip._armed_at
		if clip.asked == MovieClip.FPS * 5:
			left_mid = clip.seconds_left()
		await _frames(1)
		grabs.append(clip.last_grab_ms)
	await _until(func():
		clip.tick(0.0)
		return not clip._armed, 2.0)
	check(asked > 200 and hidden == asked and vp.canvas_cull_mask & MovieClip.LAYER != 0, "REC's kept out of each frame filmed (%d of %d), and back on the screen after" % [hidden, asked])
	check(running == 0, "never two frames running filmed: REC stays on the screen in between")
	check(absf(left_mid - 5.0) < 0.2, "half way: %.1f seconds left" % left_mid)
	check(clip.asked == roundi(MovieClip.LENGTH * MovieClip.FPS) and clip.state == MovieClip.State.SAVING, "%d frames asked for (%d s at %d fps), then saving" % [clip.asked, roundi(MovieClip.LENGTH), MovieClip.FPS])
	# (Middling times: the busy workers can hold the main thread up now and then on a loaded machine.)
	ticks.sort()
	grabs.sort()
	var tick_mid: float = ticks[ticks.size() / 2]
	var grab_mid: float = grabs[grabs.size() / 2]
	check(tick_mid < 0.5 and grab_mid < 0.5, "on the main thread each frame's upkeep %.2f ms and asking for its picture %.2f ms (middling; the worst %.1f ms)" % [tick_mid, grab_mid, ticks.back()])
	var saved := await _until(func():
		clip.tick(step)
		return not got.is_empty(), 60.0)
	var info: Dictionary = got[0] if saved else {}
	var file := FileAccess.get_file_as_bytes(str(info.get("path", "")))
	var avi := MjpegAvi.parse(file)
	var size := MovieClip.size_for(Vector2i(vp.get_visible_rect().size))
	check(saved and str(info.get("path", "")).begins_with(CLIPS) and str(info["path"]).ends_with(".avi") and str(info.get("file", "")) == ProjectSettings.globalize_path(str(info["path"])),
		"saved in the clips folder: %s" % str(info.get("file", "")))
	check(bool(avi["ok"]) and int(avi["frames"]) == 240 and (avi["jpegs"] as Array).size() == 240 and bool(avi["index_ok"]) and int(avi["fps"]) == MovieClip.FPS
		and int(avi["w"]) == size.x and int(avi["h"]) == size.y and size.x <= MovieClip.MAX_W and size.y <= MovieClip.MAX_H,
		"it reads back: %d frames at %d fps, %dx%d, %.1f MB" % [int(avi["frames"]), int(avi["fps"]), int(avi["w"]), int(avi["h"]), file.size() / 1048576.0])
	var f0 := Image.new()
	check(not (avi["jpegs"] as Array).is_empty() and f0.load_jpg_from_buffer(avi["jpegs"][120]) == OK and f0.get_width() == size.x and int(info.get("got", 0)) > 200,
		"its frames are pictures of the game (%d of them filmed, none waited for)" % int(info.get("got", 0)))
	var pic := Image.load_from_file(poster) if FileAccess.file_exists(poster) else null
	check(pic != null and pic.get_width() == PhotoCapture.PHOTO_W and info.get("poster") is Image and str((info["job"] as Dictionary).get("caption", "")) == "On film",
		"its poster frame's in the diary's folder, and the job kept with it")
	check(MovieClip.size_for(Vector2i(1920, 1080)) == Vector2i(1280, 720) and MovieClip.size_for(Vector2i(2560, 1080)) == Vector2i(1280, 540)
		and MovieClip.size_for(Vector2i(1024, 768)) == Vector2i(960, 720), "the film's size: the window's shape, at most 1280x720")
	# Stopped early.
	got.clear()
	clip.start({})
	clip.tick(MovieClip.COUNTDOWN + 0.01)
	for i in 30:
		clip.tick(step)
		await _frames(1)
	clip.press()
	var early := await _until(func():
		clip.tick(step)
		return not got.is_empty(), 30.0)
	var short := MjpegAvi.parse(FileAccess.get_file_as_bytes(str(got[0].get("path", "")))) if early else {}
	check(early and int(short.get("frames", 0)) == clip.total and clip.total >= 30 and clip.total < 40, "stopped early: a %d-frame film" % int(short.get("frames", 0)))
	clip.queue_free()
	await _frames(1)
	MovieClip.fake_source = Callable()
	MovieClip.root = "user://clips"
	_wipe(CLIPS)
	_wipe(ROOT)


## A film on an adventure: {movie} counts down and films; it's in the diary, its poster on the
## page with a Play button; and the photo sharing's own pieces: a photo's smaller copy for the
## crew, a crew mate's photo kept in this diary in its place by time (once), and one for a diary
## this machine hasn't begun kept for when it does.
func test_movie_ride() -> void:
	_wipe(CLIPS)
	MovieClip.root = CLIPS
	var frame := _frame_image()
	MovieClip.fake_source = func(): return frame
	var main: Node = await _ride_out(8.0, 4103)
	var trip: AdventureTrip = main.trip
	await _ticks(30)
	var ev := InputEventAction.new()
	ev.action = "movie"
	ev.pressed = true
	main.movie._unhandled_input(ev)
	check(main.movie.state == MovieClip.State.COUNTDOWN and str(main.movie.job.get("diary", "")) == trip.photos.diary_id, "{movie} on an adventure: counting down, for its diary")
	main.movie.t = MovieClip.COUNTDOWN - 0.01
	await _until(func(): return main.movie.state == MovieClip.State.FILMING, 3.0)
	await _until(func(): return main.movie.asked >= 20, 10.0)
	main.movie.stop()
	var done := await _until(func(): return main.movie.state == MovieClip.State.IDLE, 30.0)
	var films := trip.photos.photos.filter(func(p): return bool(p.get("movie", false)))
	check(done and films.size() == 1 and FileAccess.file_exists(str(films[0].get("video", ""))) and str(films[0]["video"]).begins_with(CLIPS)
		and FileAccess.file_exists(AdventureDiary.folder(trip.photos.diary_id).path_join(str(films[0]["file"]))), "in the diary: its poster beside it, the film in the clips folder")
	check(main.hud._flash_raw.contains(ProjectSettings.globalize_path(CLIPS)), "and where it's saved said on the screen: %s" % main.hud._flash_raw)
	trip.photos.save_draft()
	var book := DiaryBook.new()
	t.add_child(book)
	await _frames(1)
	book.open_diary(trip.photos.diary_id)
	var at := -1
	for i in book.pages.size():
		if str(book.pages[i]["kind"]) == "photos" and (book.pages[i]["photos"] as Array).any(func(p): return bool(p.get("movie", false))):
			at = i
	book.spread = maxi(0, at) / 2
	book._show()
	await _frames(1)
	var pg: Control = book._left if at % 2 == 0 else book._right
	var buttons := pg.get_children().filter(func(c): return c is Button and not c.disabled)
	check(at >= 0 and buttons.size() == 1 and str(buttons[0].text) == "Play the film", "in the book: the film with a Play button")
	book.queue_free()
	# A photo's smaller copy for the crew.
	var shared := []
	trip.photos.capture.saved.connect(func(j): shared.append(j))
	trip.photos.capture.snap({"path": AdventureDiary.folder(trip.photos.diary_id).path_join("zz.jpg"), "share": true})
	await _until(func(): return not shared.is_empty(), 5.0)
	var sb: PackedByteArray = shared[0].get("share_bytes", PackedByteArray()) if not shared.is_empty() else PackedByteArray()
	var small := Image.new()
	check(not sb.is_empty() and small.load_jpg_from_buffer(sb) == OK and small.get_width() == DiaryShare.SHARE_W and sb.size() < DiaryShare.MAX_PHOTO,
		"a photo's copy for the crew: %dx%d, %d KB" % [small.get_width(), small.get_height(), sb.size() / 1024])
	# A crew mate's photo, kept here once, in its place.
	var ds: DiaryShare = Shed.diary_share
	var first_at := int(trip.photos.photos[0].get("at", 0))
	var rec := DiaryShare.clean({"kind": "photo", "caption": "Dave's", "uid": "../evil/1a2b", "at": first_at - 5, "who": [], "file": "/etc/passwd", "by": "Dave"})
	check(str(rec["uid"]) == "evil1a2b" and not rec.has("file") and not rec.has("by"), "a record from the crew: only its fields, its id a safe name")
	rec["by"] = "Dave"
	var n0 := trip.photos.photos.size()
	check(ds.keep(trip.photos.diary_id, rec, sb) and not ds.keep(trip.photos.diary_id, rec, sb), "a crew mate's photo kept, and only once")
	check(trip.photos.photos.size() == n0 + 1 and str(trip.photos.photos[0].get("uid", "")) == "evil1a2b" and bool(trip.photos.photos[0]["shared"])
		and FileAccess.file_exists(AdventureDiary.folder(trip.photos.diary_id).path_join("x_evil1a2b.jpg")), "in this diary, first by when it was taken, its file beside it")
	var saved_d := AdventureDiary.load_diary(trip.photos.diary_id)
	check((saved_d["photos"] as Array).any(func(p): return str(p.get("by", "")) == "Dave"), "and in the diary saved, credited to Dave")
	# One for a diary not begun here yet.
	var later := rec.duplicate()
	later["uid"] = "later1"
	check(ds.keep("1700000099_5", later, sb) and DiaryShare.has_photo("1700000099_5", "later1") and DiaryShare.take_pending("1700000099_5").size() == 1
		and DiaryShare.pending.is_empty(), "one for a diary not begun here: kept for when it is")
	# A rider joining part-way (as the host sees it): sent every photo so far, the films left out.
	ds._on_joined(77, {})
	var queued := ds._out.filter(func(o): return int(o["to"]) == 77).size()
	var want := trip.photos.photos.filter(func(p): return str(p.get("uid", "")) != "" and not bool(p.get("movie", false))).size()
	check(queued > 0 and queued == want, "a rider joining part-way is sent the %d photos so far (%d queued), not the film" % [want, queued])
	ds._on_joined(77, {})
	check(ds._out.filter(func(o): return int(o["to"]) == 77).size() == queued, "and only once")
	ds._on_left(77)
	check(ds._out.is_empty(), "gone again: nothing more sent them")
	await _done(main)
	MovieClip.fake_source = Callable()
	MovieClip.root = "user://clips"
	_wipe(CLIPS)
