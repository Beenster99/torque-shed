class_name AdventurePhotos
extends Node
## This player's camera out on an adventure, and their side of the Adventure Diary (see
## AdventureDiary for the crew's highlights, DiaryBook for the book).
##
## It notices what this rider does (pulling in at a stop, onto a new surface, over the top of a
## climb) and tells the host, who keeps the crew's highlights; the host's game also
## watches the clock for sunrise and sunset. As each highlight comes in, it takes a photo of it if
## this rider was part of it (or it was the whole crew's), a few seconds' grace apart, through
## PhotoCapture, so nothing stutters; the arrival is snapped in the middle of the moment there.
##
## {photo} takes a photo whenever you like (held, it films a few seconds as a flipbook clip);
## on foot {photo_camera} holds the camera up to your eye: first person, {scroll} zooms, and
## anyone of the crew in the frame is picked out and named, and named in the caption. The photos
## are kept in the diary's folder, and shared with the crew (DiaryShare): theirs come into this
## machine's diary too, credited to them. {movie} films ten seconds (MovieClip); on an adventure
## the film's in the diary too, kept on this machine only.

## How often it looks round for highlights (s), and the least time between automatic photos.
const LOOK_EVERY := 0.25
const AUTO_GAP := 1.6
## A highlight's photo not taken by this long after it came in is let go.
const STALE := 25.0
## Stopped (slower than STOP_SPEED) this long within STOP_REACH of a stop along the road is a visit.
const STOP_SPEED := 1.5
const STOP_TIME := 3.0
const STOP_REACH := 80.0
## On a new surface this far before it counts (not a patch at a chunk's edge).
const SURFACE_AFTER := 40.0
## Held this long, {photo} films a clip instead.
const HOLD_CLIP := 0.4
## The camera held up: its zoom (times), the least and most.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0
## Someone further than this isn't in the shot, just in the distance.
const SHOT_REACH := 60.0
## The photo on the HUD once it's taken: how long it shows.
const TOAST_TIME := 3.2

var trip: AdventureTrip
var capture: PhotoCapture
## The diary on this machine for this adventure (Shed.adventure["diary"]) and its photos so far.
var diary_id := ""
var photos: Array = []
## The camera held up to your eye (on foot), and its zoom.
var camera_up := false
var zoom := 1.0
var _look := 0.0
var _auto_wait := 0.0
var _queue: Array = []         # [{key, kind, caption, who, s, at (ticks)}] waiting their turn
var _seen := {}                # log n -> true, the highlights already looked at
var _reported := {}            # keys told to the host from here
var _s := -1.0                 # how far along the road you are (m), as last looked
var _surf := ""
var _surf_from := -1.0
var _surf_told := ""
var _stop_t := 0.0
var _stop_key := ""
var _peaks: Array = []
var _peaks_found := false
var _hours := -1.0
var _press_t := -1.0           # how long {photo} has been held (-1: not)
var _filming := false
var _n := 0                    # files numbered
var _route := {}               # the route's summary for the book (made once, while it's loaded)
var _adv := {}                 # the adventure as last seen (it's gone from the shed by Ride home)
var _old := {}                 # the diary as this machine had it when the ride began
var _done := false             # put together at the destination
var _adv_sig := ""
var _ui: CanvasLayer
var _finder: Control           # the viewfinder, with the camera held up
var _toast: PanelContainer
var _toast_pic: TextureRect
var _toast_label: Label
var _toast_t := 0.0
var _shot_names: Array = []    # the crew in the viewfinder now, and where: [{name, at (screen)}]


func _ready() -> void:
	name = "AdventurePhotos"
	capture = PhotoCapture.new()
	add_child(capture)
	capture.saved.connect(_on_saved)
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	_finder = _Finder.new()
	_finder.photos = self
	_finder.visible = false
	_ui.add_child(_finder)
	_toast = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.96, 0.93)
	st.set_content_margin_all(6)
	st.content_margin_bottom = 4
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 8
	_toast.add_theme_stylebox_override("panel", st)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_ui.add_child(_toast)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(v)
	_toast_pic = TextureRect.new()
	_toast_pic.custom_minimum_size = Vector2(192, 108)
	_toast_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_toast_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_toast_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_toast_pic)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.add_theme_color_override("font_color", Color(0.15, 0.13, 0.12))
	_toast_label.custom_minimum_size = Vector2(192, 0)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_toast_label)


# ---------------------------------------------------------------------------- the ride

## Out on the adventure in Shed.adventure: its diary picked up where this machine left it (a ride
## carried on after a night), the trip computer's numbers with it.
func begin() -> void:
	diary_id = str(Shed.adventure.get("diary", ""))
	photos = []
	_queue = []
	_seen = {}
	_reported = {}
	_s = -1.0
	_surf = ""
	_surf_told = ""
	_hours = Daylight.time_of_day()
	_peaks_found = false
	_route = {}
	_n = 0
	_keep_adventure()
	var had := AdventureDiary.load_diary(diary_id)
	_old = had
	_done = false
	if not had.is_empty():
		photos = had["photos"]
		_n = photos.size()
	# The crew's photos that came in before this machine got going (joining part-way).
	for rec in DiaryShare.take_pending(diary_id):
		if not photos.any(func(p): return str(p.get("uid", "")) == str(rec.get("uid", ""))):
			AdventureDiary.insert_photo(photos, rec)
		if trip and trip.computer and had["stats"] is Dictionary:
			trip.computer.load_from(had["stats"])
	# Highlights from before this machine got here (a night's sleep ago) aren't photographed again.
	for e in AdventureDiary.log_entries():
		if int(e.get("t", 0)) > 30 or not had.is_empty():
			_seen[int(e["n"])] = true


## Back home (or the session's over): the camera put away.
func end() -> void:
	lower_camera()
	_queue.clear()
	_filming = false
	_press_t = -1.0
	_toast.visible = false


func _process(delta: float) -> void:
	if trip == null or not trip.on_trip():
		if _toast.visible:
			_toast_t -= delta
			_toast.visible = _toast_t > 0.0
		return
	var pt := Perf.t0()
	_tick(delta)
	Perf.add("photos", pt)


func _tick(delta: float) -> void:
	if _press_t >= 0.0 and not _filming:
		_press_t += delta
		if _press_t >= HOLD_CLIP:
			film()
	if _filming and not capture.filming():
		_filming = false
	_auto_wait -= delta
	_look -= delta
	if _look <= 0.0:
		_look = LOOK_EVERY
		_watch(LOOK_EVERY)
		_new_highlights()
	_take_queued()
	if camera_up:
		_aim()
		var me = trip.main.walker if trip.main else null
		if trip.main == null or trip.main.bike != null or me == null or trip.map_open() or trip.main.menu.visible:
			lower_camera()
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0


## Where you are along the road now, and what that makes: a stop visited, a new surface, the top
## of a climb; and on the host the sun coming up or going down.
func _watch(dt: float) -> void:
	var w := trip.world
	var r := w.route
	var me: Vector3 = trip.focus_points()[0]
	var s := w.distance_of(me, "photos")
	if s < 0.0:
		return
	var was := _s
	_s = s
	if Shed.is_authority():
		var h := Daylight.time_of_day()
		var sun := AdventureDiary.sun_crossed(_hours, h) if _hours >= 0.0 else ""
		_hours = h
		if sun != "" and int(Shed.adventure.get("arrived", 0)) == 0:
			report(sun, "%s_%d" % [sun, int(Shed.adventure.get("nights", 0))])
	if int(Shed.adventure.get("arrived", 0)) != 0:
		return
	# A stop: stood still beside one along the road.
	var speed := absf(trip.main.bike.speed) if trip.main and trip.main.bike else 0.0
	var site := _site_near(r, s)
	if speed < STOP_SPEED and not site.is_empty():
		var key := "stop_%d" % int(float(site["s"]))
		if key != _stop_key:
			_stop_key = key
			_stop_t = 0.0
		_stop_t += dt
		if _stop_t >= STOP_TIME:
			var label := str(site["name"]) if str(site["kind"]) in ["village", "cafe", "inn"] and str(site.get("name", "")) != "" \
				else "the %s" % str(AdventureStops.LABELS.get(str(site["kind"]), "stop")).to_lower()
			report("stop", key, {"what": label})
	else:
		_stop_t = 0.0
		_stop_key = ""
	# A new surface, once you're well onto it.
	var here := r.surface_at_s(s)
	if here != _surf:
		if _surf != "":
			# Where this surface began (a chunk's edge): the same key whoever rides onto it, wherever noticed.
			var c := AdventureRoute.chunk_of(s)
			var back := 0
			while c > 0 and back < 20 and r.surface_at_s((c - 1) * AdventureRoute.CHUNK_LEN + 1.0) == here:
				c -= 1
				back += 1
			_surf_from = c * AdventureRoute.CHUNK_LEN
		_surf = here
		if _surf_told == "":
			_surf_told = here   # what you set off on isn't new
	if here != _surf_told and _surf_from >= 0.0 and s - _surf_from >= SURFACE_AFTER:
		_surf_told = here
		report("surface", "surf_%d" % AdventureRoute.chunk_of(_surf_from), {"what": here})
	# The top of a climb, ridden over.
	if not _peaks_found:
		_peaks_found = true
		_peaks = AdventureDiary.peaks(r)
	if was >= 0.0 and s > was and s - was < 200.0:
		for p in _peaks:
			if was < float(p["s"]) and s >= float(p["s"]):
				report("peak", "peak_%d" % int(float(p["s"])), {"h": float(p["h"])})


## The stop along the road within STOP_REACH of `s` ({} for none).
func _site_near(r: AdventureRoute, s: float) -> Dictionary:
	for st in r.sites:
		var d := float(st["s"]) - s
		if d > STOP_REACH:
			break
		if d > -STOP_REACH and (AdventureStops.NAV.has(str(st["kind"])) or str(st["kind"]) == "village"):
			return st
	return {}


## Tells the host about highlight `kind` (`key`: once each, from here). On the host it goes
## straight in.
func report(kind: String, key: String, extra := {}) -> void:
	if key != "" and _reported.has(key):
		return
	if key != "":
		_reported[key] = true
	var a := {"a": "adventure_highlight", "kind": kind, "key": key, "s": maxf(_s, 0.0)}
	a.merge(extra, true)
	Shed.request(a)


## A copy of the adventure kept whenever its highlights or photo change, for the diary at the end.
func _keep_adventure() -> void:
	if not Adventure.active():
		return
	var sig := "%d|%d|%d|%d" % [int(Shed.adventure.get("id", 0)), int(Shed.adventure.get("log_n", 0)), int(Shed.adventure.get("arrived", 0)),
		(Shed.adventure.get("photo", {}) as Dictionary).size() if Shed.adventure.get("photo") is Dictionary else 0]
	if sig != _adv_sig:
		_adv_sig = sig
		_adv = Shed.adventure.duplicate(true)


## The highlights new in the shared log: a photo of each this rider was part of (or the crew's).
func _new_highlights() -> void:
	_keep_adventure()
	var me := _me()
	for e in AdventureDiary.log_entries():
		var n := int(e["n"])
		if _seen.has(n):
			continue
		_seen[n] = true
		var kind := str(e["kind"])
		var who: Array = e.get("who", [])
		var mine := who.is_empty() or who.has(me) or bool(AdventureDiary.KINDS.get(kind, {}).get("crew", false))
		if not mine or kind in ["fork", "arrive"]:
			continue   # (a fork, in a ride from before they were taken out), the arrival's taken in the moment there
		_want(str(e.get("key", "")) if str(e.get("key", "")) != "" else "log_%d" % n, kind, str(e["text"]), who, float(e.get("s", _s)),
			2.5 if kind == "start" else 0.0)


## A photo wanted of `kind` (once per `key`), `after` seconds from now.
func _want(key: String, kind: String, caption: String, who: Array, s: float, after := 0.0) -> void:
	for q in _queue:
		if str(q["key"]) == key:
			return
	for p in photos:
		if str(p.get("key", "")) == key and not bool(p.get("shared", false)):
			return   # (a crew mate's photo of it is theirs: this rider's is taken too)
	_queue.append({"key": key, "kind": kind, "caption": caption, "who": who, "s": s,
		"at": Time.get_ticks_msec() + int(after * 1000.0), "asked": Time.get_ticks_msec()})


func _take_queued() -> void:
	if _queue.is_empty() or _auto_wait > 0.0 or _filming or trip.main == null or trip.main.menu.visible or trip.map_open() \
			or trip.diary_open() or trip.moment_t >= 0.0:
		return
	var now := Time.get_ticks_msec()
	while not _queue.is_empty() and now - int(_queue[0]["asked"]) > int(STALE * 1000.0):
		_queue.pop_front()
	if _queue.is_empty() or now < int(_queue[0]["at"]):
		return
	var q: Dictionary = _queue.pop_front()
	snap(str(q["kind"]), str(q["caption"]), str(q["key"]), q["who"])
	_auto_wait = AUTO_GAP


# ---------------------------------------------------------------------------- taking them

## Takes a photo now, of `kind` (a highlight's, or "photo" for one you took), captioned
## `caption` (with whoever's in the shot), for highlight `key`.
func snap(kind: String, caption: String, key := "", who: Array = []) -> void:
	if diary_id == "":
		return
	_n += 1
	var in_shot := in_frame()
	var job := _job(kind, caption, key, who, in_shot)
	job["file"] = "p%03d.jpg" % _n
	job["path"] = AdventureDiary.folder(diary_id).path_join(job["file"])
	job["share"] = Net.is_online()
	capture.snap(job)
	if kind in ["photo", "arrive"]:
		Sfx.play_ui("switch", -6.0)


## Films a clip (a flipbook of a few seconds) from now.
func film() -> void:
	if diary_id == "" or _filming:
		return
	_filming = true
	_n += 1
	var job := _job("clip", "", "", [], in_frame())
	job["file"] = "c%03d.jpg" % _n
	job["path"] = AdventureDiary.folder(diary_id).path_join(job["file"])
	job["share"] = Net.is_online()
	capture.film(job)
	Sfx.play_ui("beep", -8.0)


## The diary's side of a film (MovieClip) started now on the adventure: its record, with the
## poster frame's file in the diary's folder ({} off an adventure).
func movie_job() -> Dictionary:
	if diary_id == "" or trip == null or not trip.on_trip():
		return {}
	_n += 1
	var job := _job("movie", "", "", [], in_frame())
	job["file"] = "m%03d.jpg" % _n
	job["poster_path"] = AdventureDiary.folder(diary_id).path_join(job["file"])
	job["diary"] = diary_id
	return job


## A film's saved (`info` as MovieClip.saved gives it): into the diary it was started for, on this
## machine (the film itself stays in the clips folder).
func add_movie(info: Dictionary) -> void:
	var job: Dictionary = info.get("job", {})
	var diary := str(job.get("diary", ""))
	if diary == "" or not FileAccess.file_exists(str(job.get("poster_path", ""))):
		return
	var rec := job.duplicate()
	rec.erase("poster_path")
	rec.erase("diary")
	rec["movie"] = true
	rec["video"] = str(info.get("path", ""))
	rec["secs"] = float(info.get("secs", 0.0))
	rec["w"] = int(info.get("w", 0))
	rec["h"] = int(info.get("h", 0))
	if diary == diary_id:
		photos.append(rec)
		save_draft()
		_show_toast(info.get("poster"), "Film: " + str(rec.get("caption", "")))
	else:
		AdventureDiary.add_photo(diary, rec)


## A crew mate's photo come in (DiaryShare, its file already beside the diary): in its place.
func add_shared(rec: Dictionary) -> void:
	AdventureDiary.insert_photo(photos, rec)
	save_draft()


func _job(kind: String, caption: String, key: String, who: Array, in_shot: Array) -> Dictionary:
	var names := in_shot.map(func(x): return str(x["name"]))
	if caption == "":
		caption = _caption(kind, names)
	var people := who.duplicate()
	for nm in names:
		if not people.has(nm):
			people.append(nm)
	# (Its uid is the same on every machine it's shared to; "at" puts the crew's photos in order.)
	return {"kind": kind, "caption": caption, "key": key, "who": people, "by": _me(), "s": roundf(maxf(_s, 0.0)),
		"hours": snappedf(Daylight.time_of_day(), 0.01), "day": int(Shed.adventure.get("nights", 0)), "in_shot": names,
		"uid": "%x%08x" % [int(Time.get_unix_time_from_system()), randi()], "at": int(Time.get_unix_time_from_system())}


## A photo you took's caption: who's in it, and where.
func _caption(kind: String, names: Array) -> String:
	var where := _where()
	if not names.is_empty():
		return ("%s, %s" % [AdventureNeeds._and_list(names), where]).left(110)
	return ("On film, %s" % where if kind in ["clip", "movie"] else where.left(1).to_upper() + where.substr(1)).left(110)


## Where you are, in words: "at the Lay-by", "in Little Hayton", "on the gravel".
func _where() -> String:
	var r := trip.world.route
	var site := _site_near(r, maxf(_s, 0.0))
	if not site.is_empty():
		var kind := str(site["kind"])
		if kind in ["village", "cafe", "inn"] and str(site.get("name", "")) != "":
			return ("in %s" if kind == "village" else "at %s") % str(site["name"])
		return "at the %s" % str(AdventureStops.LABELS.get(kind, "stop")).to_lower()
	return "on the %s, %s" % [str(AdventureSurface.NAMES.get(r.surface_at_s(maxf(_s, 0.0)), "road")).to_lower(), TripComputer.distance_text(maxf(_s, 0.0)) + " in"]


## The crew in the shot now: [{name, at (screen point), d (m)}], nearest first (only those in the
## frame, near enough and not behind a hill).
func in_frame() -> Array:
	var out := []
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or trip.main == null:
		return out
	var space := cam.get_world_3d().direct_space_state if cam.get_world_3d() else null
	var vr := get_viewport().get_visible_rect()
	for peer in trip.main.remotes:
		var rp = trip.main.remotes[peer]
		if not is_instance_valid(rp):
			continue
		var at: Vector3 = rp.world_position() + Vector3.UP * 1.2
		var d := cam.global_position.distance_to(at)
		if d > SHOT_REACH * zoom or cam.is_position_behind(at) or not cam.is_position_in_frustum(at):
			continue
		var sp := cam.unproject_position(at)
		if not vr.grow(-8.0).has_point(sp):
			continue
		if space:
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, at, 1)
			var hit := space.intersect_ray(q)
			if hit and (hit["position"] as Vector3).distance_to(at) > 2.5:
				continue
		out.append({"name": str(Shed.crew.get(peer, {}).get("name", rp.player_name)), "at": sp, "d": d})
	out.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	return out


func _on_saved(job: Dictionary) -> void:
	if bool(job.get("failed", false)):
		return
	var rec := job.duplicate()
	rec.erase("image")
	rec.erase("path")
	rec.erase("hud")
	rec.erase("share")
	rec.erase("share_bytes")
	rec["clip"] = bool(job.get("clip", false))
	photos.append(rec)
	if Net.is_online() and Shed.diary_share and job.get("share_bytes") is PackedByteArray:
		Shed.diary_share.share(diary_id, rec, job["share_bytes"])
	_show_toast(job.get("image"), ("Clip: " if rec["clip"] else "") + str(rec.get("caption", "")))
	save_draft()


## The picture just taken on the HUD for a moment, with its caption.
func _show_toast(img, text: String) -> void:
	if img is Image and is_inside_tree():
		_toast_pic.texture = ImageTexture.create_from_image(img)
		_toast_label.text = text
		_toast.visible = true
		_toast_t = TOAST_TIME
		_toast.reset_size()
		_toast.position = Vector2(get_viewport().get_visible_rect().size.x - _toast.size.x - 24.0, get_viewport().get_visible_rect().size.y - _toast.size.y - 250.0)


# ---------------------------------------------------------------------------- the camera held up

func raise_camera() -> String:
	if trip == null or not trip.on_trip():
		return "The camera's for adventure rides."
	if trip.main.bike != null:
		return "Get off to hold the camera up."
	camera_up = true
	zoom = 1.0
	_finder.visible = true
	_apply_zoom()
	Sfx.play_ui("switch", -10.0)
	return ""


func lower_camera() -> void:
	if not camera_up:
		return
	camera_up = false
	_finder.visible = false
	zoom = 1.0
	if trip and trip.main and trip.main.walker:
		trip.main.walker.camera.fov = Settings.gfx_fov


func _apply_zoom() -> void:
	if trip.main and trip.main.walker:
		trip.main.walker.camera.fov = clampf(2.0 * rad_to_deg(atan(tan(deg_to_rad(Settings.gfx_fov) * 0.5) / zoom)), 8.0, 120.0)


func _aim() -> void:
	_shot_names = in_frame()
	_finder.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if trip == null or not trip.on_trip() or trip.main == null or trip.main.menu.visible or trip.diary_open() or trip.map_open():
		return
	if event.is_action_pressed("photo"):
		get_viewport().set_input_as_handled()
		_press_t = 0.0
	elif event.is_action_released("photo") and _press_t >= 0.0:
		get_viewport().set_input_as_handled()
		if not _filming and _press_t < HOLD_CLIP:
			snap("photo", "")
		_press_t = -1.0
	elif event.is_action_pressed("photo_camera"):
		get_viewport().set_input_as_handled()
		if camera_up:
			lower_camera()
		else:
			var why := raise_camera()
			if why != "":
				trip.main.hud.flash(why, 1.5, true)
			else:
				trip.main.hud.flash("Camera up: {photo} to take one, hold {photo} to film, {scroll} to zoom, {photo_camera} to put it away", 4.0)


func _input(event: InputEvent) -> void:
	if not camera_up:
		return
	# Held up, the mouse wheel (or the shoulder buttons) zooms instead of changing tools.
	if event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev"):
		zoom = clampf(zoom * (0.85 if event.is_action_pressed("tool_next") else 1.0 / 0.85), ZOOM_MIN, ZOOM_MAX)
		_apply_zoom()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		lower_camera()
		get_viewport().set_input_as_handled()


## The viewfinder: the frame's corners, a focus mark, the zoom, the crew in the shot picked out by
## name, and while filming a blinking REC (the frames taken are clear of all of it).
class _Finder extends Control:
	var photos: AdventurePhotos

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-40.0)
		var c := Color(1, 1, 1, 0.8)
		var l := 46.0
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), c, 3.0)
			draw_line(corner, corner + Vector2(0, l * sy), c, 3.0)
		var mid := size * 0.5
		draw_arc(mid, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
		draw_line(mid - Vector2(8, 0), mid + Vector2(8, 0), Color(1, 1, 1, 0.6), 1.5)
		draw_line(mid - Vector2(0, 8), mid + Vector2(0, 8), Color(1, 1, 1, 0.6), 1.5)
		var font := get_theme_default_font()
		draw_string(font, Vector2(r.position.x + 8.0, r.end.y - 12.0), "%.1fx" % photos.zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)
		draw_string(font, Vector2(r.position.x, r.end.y + 26.0), Controls.hint("{photo}: take it   hold {photo}: film a clip   {scroll}: zoom   {photo_camera}: put it away"),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(1, 1, 1, 0.7))
		if photos._filming and int(Time.get_ticks_msec() / 400) % 2 == 0:
			draw_circle(Vector2(r.end.x - 70.0, r.position.y + 24.0), 8.0, Color(1, 0.15, 0.1))
			draw_string(font, Vector2(r.end.x - 56.0, r.position.y + 31.0), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.3, 0.25))
		for f in photos._shot_names:
			var at: Vector2 = f["at"]
			var b := Rect2(at - Vector2(34, 44), Vector2(68, 88))
			var fc := SatnavScreen.FRIEND
			for corner in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
				var sx := 1.0 if corner.x < at.x else -1.0
				var sy := 1.0 if corner.y < at.y else -1.0
				draw_line(corner, corner + Vector2(14 * sx, 0), fc, 2.0)
				draw_line(corner, corner + Vector2(0, 14 * sy), fc, 2.0)
			draw_string(font, Vector2(b.position.x - 40.0, b.position.y - 8.0), str(f["name"]), HORIZONTAL_ALIGNMENT_CENTER, b.size.x + 80.0, 16, fc)


# ---------------------------------------------------------------------------- the diary

func _me() -> String:
	return str(Shed.crew.get(Shed.me(), {}).get("name", Settings.player_name))


## The diary as it stands, put together: the crew's highlights, this machine's photos, the
## route strip and the trip computer's stats. `done` once the ride's over.
func compile(done := false) -> Dictionary:
	if trip and trip.world and _route.is_empty():
		_route = AdventureDiary.route_summary(trip.world.route)
	_keep_adventure()
	var adv := _adv
	var crew := []
	var ids := Shed.crew.keys()
	ids.sort()
	for p in ids:
		crew.append(str(Shed.crew[p].get("name", "Rider")))
	var stats := trip.computer.save() if trip and trip.computer else {}
	if trip and trip.main and trip.main.bike:
		stats["fuel_left"] = trip.main.bike.fuel_litres
		stats["book"] = trip.main.bike.build.cruise_economy()
	var old := _old
	return {"id": diary_id, "title": str(adv.get("title", old.get("title", "Adventure"))), "dest": str(adv.get("dest", old.get("dest", ""))),
		"theme": str(adv.get("theme", "varied")), "km": float(adv.get("km", 0.0)),
		"date": str(old.get("date", "")) if str(old.get("date", "")) != "" else Time.get_date_string_from_system(),
		"crew": crew, "me": _me(), "log": AdventureDiary.log_entries(adv), "photos": photos.duplicate(true), "stats": stats,
		"route": _route if not _route.is_empty() else old.get("route", {}),
		"journey": AdventureJourney.kept_of_plan(adv.get("plan", {})) if adv.get("plan") is Dictionary else old.get("journey", {}),
		"photo": adv.get("photo", old.get("photo", {})), "done": done or _done or bool(old.get("done", false)),
		"saved_at": int(Time.get_unix_time_from_system())}


## Writes the diary as it stands (each photo, and at the end).
func save_draft(done := false) -> bool:
	if diary_id == "" or _adv.is_empty():
		return false
	return AdventureDiary.save_diary(compile(done))


## At the destination, after the moment, and at Ride home: the diary put together and kept.
func finish() -> bool:
	capture.wait_all()
	capture._tick(0.0)   # anything the workers just finished
	_done = save_draft(true) or _done
	return _done
