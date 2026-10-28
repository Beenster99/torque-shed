class_name AdventureDiary
extends RefCounted
## The Adventure Diary (Simon: "At the end of an adventure pull together an Adventure Diary,
## showing screen shots and highlights from the ride - like a photo journal and any pics we have
## taken of each other, movies for cameras").
##
## Two halves. The highlights are the crew's, kept by the host in the shared state
## (Shed.adventure["log"], so every player has the same list): setting off, each stop visited,
## onto a new surface, the high points (old diaries may also hold the ways taken at forks, police chases, fines and
## picnics), breakdowns and roadside fixes, sunrise and sunset, and arriving. Each has its time
## (the clock, and the day), how far along the road (km) and who. The photos are taken on each
## player's own machine (AdventurePhotos: automatically at the highlights they were part of, and
## whenever they take one) and shared with the whole crew (DiaryShare: everyone's diary has
## everyone's photos, each credited to who took it). Films (MovieClip) stay on the machine that
## took them.
##
## At the destination, and again at Ride home, each player's game puts its diary together: the
## shared highlights, the crew's photos with their captions, the route as a strip with the
## highlights marked, and the trip computer's final stats (TripComputer). It's kept in
## user://diaries/<id>/ (diary.json and the JPEGs beside it) and read in a book (DiaryBook),
## from the magazine on the workbench or the adventure's photo on the shed wall.
##
## Shed.adventure: "diary" (the adventure's diary id, the same on every game, kept through a
## night's stop), "log" {n: entry} (a Dictionary, so the crew are sent only what's new), "log_n".
## An entry: {n, kind, key (one entry per key: a stop, a peak... the next rider there is
## added to its who), text, who [names; [] is the whole crew], s (m along the road), hours (the
## clock), day (nights in), t (s since setting off)}.
## Action (Shed.request): adventure_highlight {kind, key, s, what?, peer?} for what a rider's own
## game notices (a stop, a surface, a peak, a puncture) or the host's (sunrise, sunset, a chase).

## Every kind of highlight: what it's called in the book, its mark on the route strip, its
## colour, and whether everyone's camera takes it (else only the riders it's about).
const KINDS := {
	"start": {"name": "Setting off", "mark": "S", "col": Color(0.25, 0.75, 1.0), "crew": true},
	"stop": {"name": "A stop", "mark": "P", "col": Color(0.4, 0.65, 1.0), "crew": false},
	"fork": {"name": "The way we went", "mark": "Y", "col": Color(1.0, 0.8, 0.25), "crew": true},
	"surface": {"name": "New ground", "mark": "~", "col": Color(0.75, 0.6, 0.4), "crew": false},
	"peak": {"name": "High point", "mark": "^", "col": Color(0.9, 0.95, 1.0), "crew": false},
	"chase": {"name": "Police chase", "mark": "!", "col": Color(0.3, 0.45, 1.0), "crew": false},
	"fine": {"name": "Fined", "mark": "£", "col": Color(0.85, 0.2, 0.15), "crew": false},
	"breakdown": {"name": "Broke down", "mark": "X", "col": Color(1.0, 0.45, 0.2), "crew": false},
	"fix": {"name": "Fixed at the roadside", "mark": "+", "col": Color(0.4, 0.9, 0.45), "crew": false},
	"tow": {"name": "On the tow strap", "mark": "T", "col": Color(1.0, 0.65, 0.2), "crew": false},
	"picnic": {"name": "Picnic", "mark": "E", "col": Color(1.0, 0.7, 0.2), "crew": false},
	"sunrise": {"name": "Sunrise", "mark": "o", "col": Color(1.0, 0.75, 0.35), "crew": true},
	"sunset": {"name": "Sunset", "mark": "o", "col": Color(1.0, 0.45, 0.3), "crew": true},
	"arrive": {"name": "We made it", "mark": "*", "col": Color(1.0, 0.45, 0.35), "crew": true},
}
## What a rider's game can report for itself; the host's own (chases, sunrise and sunset) too.
const REPORTED: Array[String] = ["stop", "surface", "peak", "breakdown"]
const HOST_REPORTED: Array[String] = ["chase", "sunrise", "sunset"]
## The most highlights kept (the oldest go).
const MAX_LOG := 160
## The clock times the sun comes up and goes down (see Daylight.sun_direction).
const SUNRISE := 6.0
const SUNSET := 18.0
## Diaries kept on this machine (the latest).
const MAX_DIARIES := 40

## Where this machine keeps its diaries; the tests point it elsewhere.
static var root := "user://diaries"
## Goes up whenever a diary on this machine is saved or deleted (the shed's diary shelf restocks then).
static var revision := 0


static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


# ---------------------------------------------------------------------------- the shared log

## The highlights so far, in order.
static func log_entries(adv: Dictionary = Shed.adventure) -> Array:
	var out := []
	var l = adv.get("log", {})
	if l is Dictionary:
		for n in l:
			if l[n] is Dictionary:
				out.append(l[n])
	out.sort_custom(func(a, b): return int(a.get("n", 0)) < int(b.get("n", 0)))
	return out


## The entry with `key` ({} when there's none yet).
static func find(key: String, adv: Dictionary = Shed.adventure) -> Dictionary:
	if key == "":
		return {}
	var l = adv.get("log", {})
	if l is Dictionary:
		for n in l:
			if str((l[n] as Dictionary).get("key", "")) == key:
				return l[n]
	return {}


static func check(peer: int, action: Dictionary) -> String:
	if not Adventure.active():
		return "There's no adventure on."
	var kind := str(action.get("kind", ""))
	if HOST_REPORTED.has(kind):
		return "" if _is_host(peer) else "The host notes that."
	if not REPORTED.has(kind):
		return "That's not a highlight."
	return ""


## Host: a highlight a rider's game (or the host's) noticed. Nothing to tell anyone.
static func apply(peer: int, action: Dictionary) -> String:
	var kind := str(action.get("kind", ""))
	var about := int(action.get("peer", peer)) if HOST_REPORTED.has(kind) else peer
	var who := _name(about)
	var s := clampf(float(action.get("s", 0.0)), 0.0, 1000000.0)
	var what := str(action.get("what", "")).left(40)
	var text := ""
	match kind:
		"stop":
			text = "Stopped at %s" % (what if what != "" else "the side of the road")
		"surface":
			text = "Onto %s" % (str(AdventureSurface.NAMES.get(what, "new ground")).to_lower() if what != "" else "new ground")
			if what == "tarmac":
				text = "Back on the tarmac"
		"peak":
			text = "High point of the road: %s up" % TripComputer.height_text(float(action.get("h", 0.0)))
		"breakdown":
			text = "Broke down: %s" % (what.to_lower() if what != "" else "something's gone")
		"chase":
			text = "The police gave chase: %d mph too fast" % clampi(int(action.get("mph", 30)), 0, 200)
		"sunrise":
			text = "Sunrise"
			who = ""
		"sunset":
			text = "Sunset"
			who = ""
	note(kind, str(action.get("key", "")).left(48), [who] if who != "" else [], s, text)
	return ""


## Host: adds a highlight (or, with a `key` already there, adds `names` to its who). Returns its n
## (0 for none: no adventure on).
static func note(kind: String, key: String, names: Array, s: float, text: String) -> int:
	if not Adventure.active() or not KINDS.has(kind):
		return 0
	if not (Shed.adventure.get("log") is Dictionary):
		Shed.adventure["log"] = {}
	var l: Dictionary = Shed.adventure["log"]
	var had := find(key)
	if not had.is_empty():
		var who: Array = had["who"]
		if who.is_empty():
			return int(had["n"])   # the whole crew already
		for nm in names:
			if not who.has(nm) and who.size() < 8:
				who.append(nm)
		return int(had["n"])
	var n := int(Shed.adventure.get("log_n", 0)) + 1
	Shed.adventure["log_n"] = n
	var started := float(Shed.adventure.get("started", Time.get_unix_time_from_system()))
	l[n] = {"n": n, "kind": kind, "key": key, "text": text.left(90), "who": names.map(func(x): return str(x).left(24)).slice(0, 8),
		"s": roundf(s), "hours": snappedf(Daylight.time_of_day(), 0.01), "day": int(Shed.adventure.get("nights", 0)),
		"t": roundi(maxf(0.0, Time.get_unix_time_from_system() - started))}
	while l.size() > MAX_LOG:
		var low := -1
		for k in l:
			if low < 0 or int(k) < low:
				low = int(k)
		l.erase(low)
	return n


## The rider `peer`'s name.
static func _name(peer: int) -> String:
	return str(Shed.crew.get(peer, {}).get("name", "Someone"))


## How far along the road `peer` is (m): you from your own game, the rest as the host sees them.
static func s_of(peer: int) -> float:
	var trip := AdventureTrip.current
	if trip == null or not trip.on_trip() or trip.main == null:
		return 0.0
	if peer == Shed.me():
		return maxf(0.0, trip.world.distance_of(trip.focus_points()[0], "diary"))
	var rp = trip.main.remotes.get(peer)
	if rp != null and is_instance_valid(rp):
		return maxf(0.0, trip.world.distance_of(rp.world_position(), "diary_%d" % peer))
	return 0.0


# ---------------------------------------------------------------------------- the host's own hooks

## An adventure's just started (or carried on after a night): its diary id, and setting off.
static func started(fresh: bool) -> void:
	if fresh or str(Shed.adventure.get("diary", "")) == "":
		Shed.adventure["diary"] = "%d_%d" % [int(Time.get_unix_time_from_system()), int(Shed.adventure.get("seed", 0))]
		Shed.adventure["log"] = {}
		Shed.adventure["log_n"] = 0
	Shed.adventure["started"] = Time.get_unix_time_from_system()
	if fresh:
		note("start", "start", [], 0.0, "Set off: %d km to %s" % [roundi(float(Shed.adventure.get("km", 0.0))),
			AdventureDest.name_of(str(Shed.adventure.get("dest", "")))])
	else:
		note("start", "resume_%d" % int(Shed.adventure.get("nights", 0)), [], AdventureNeeds.save_s({"at": Shed.adventure.get("resume", {})}) if Shed.adventure.get("resume") is Dictionary else 0.0,
			"Back on the road after a night's sleep")


## `peer` is fined `amount` for going `mph` too fast.
static func fined(peer: int, amount: int, mph: int) -> void:
	note("fine", "", [_name(peer)], s_of(peer), "Fined £%d by the police, %d mph too fast" % [amount, mph])


## `peer`'s bike breaks down with `what` (Roadside.name_of), or is fixed of it at the roadside.
static func broke(peer: int, what: String) -> void:
	note("breakdown", "", [_name(peer)], s_of(peer), "Broke down: %s" % what.to_lower())


static func fixed(peer: int, what: String) -> void:
	note("fix", "", [_name(peer)], s_of(peer), "Fixed it at the roadside: %s" % what.to_lower())


static func towed(peer: int, by: int) -> void:
	note("tow", "", [_name(peer), _name(by)], s_of(peer), "On a tow strap behind %s's bike" % _name(by))


## The first there: arrived.
static func arrived(peer: int) -> void:
	note("arrive", "arrive", [], float(Shed.adventure.get("km", 0.0)) * 1000.0,
		"Arrived at %s" % AdventureDest.name_of(str(Shed.adventure.get("dest", ""))))


## The clock went from `h0` to `h1` hours: which of sunrise and sunset that passed ("" for none;
## a jump of the clock, as at the destination, doesn't count).
static func sun_crossed(h0: float, h1: float) -> String:
	var step := wrapf(h1 - h0, -12.0, 12.0)
	if step <= 0.0 or step > 0.5:
		return ""
	for e in [[SUNRISE, "sunrise"], [SUNSET, "sunset"]]:
		var to := wrapf(float(e[0]) - h0, 0.0, 24.0)
		if to > 0.0 and to <= step:
			return str(e[1])
	return ""


# ---------------------------------------------------------------------------- the diaries on this machine

static func folder(id: String) -> String:
	return root.path_join(id.validate_filename())


static func path_of(id: String) -> String:
	return folder(id).path_join("diary.json")


## A diary as saved (and the photos' files beside it), or {} when there isn't one.
static func load_diary(id: String) -> Dictionary:
	var p := path_of(id)
	if id == "" or not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return sanitize(v, id) if v is Dictionary else {}


static func save_diary(d: Dictionary) -> bool:
	var id := str(d.get("id", ""))
	if id == "":
		return false
	var fresh := not FileAccess.file_exists(path_of(id))
	DirAccess.make_dir_recursive_absolute(folder(id))
	var f := FileAccess.open(path_of(id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	if fresh:
		_trim()   # a new one on the shelf: the oldest off the end
	revision += 1
	return true


## Adds photo `rec` (its file already beside the diary) to the diary `id` saved here, in its
## place by when it was taken. False when there's no such diary.
static func add_photo(id: String, rec: Dictionary) -> bool:
	var d := load_diary(id)
	if d.is_empty():
		return false
	insert_photo(d["photos"], rec)
	return save_diary(d)


## Puts `rec` into `photos` in its place by when it was taken ("at"), the end without one.
static func insert_photo(photos: Array, rec: Dictionary) -> void:
	var at := int(rec.get("at", 0))
	if at > 0:
		for i in photos.size():
			if int(photos[i].get("at", 0)) > at:
				photos.insert(i, rec)
				return
	photos.append(rec)


## A diary as read back: every field there and the right type.
static func sanitize(v: Dictionary, id: String) -> Dictionary:
	var out := {"id": id, "title": str(v.get("title", "Adventure")).left(64), "dest": str(v.get("dest", "")),
		"theme": str(v.get("theme", "varied")), "km": float(v.get("km", 0.0)), "date": str(v.get("date", "")).left(16),
		"crew": [], "me": str(v.get("me", "")).left(24), "log": [], "photos": [], "stats": {}, "route": {},
		"photo": AdventureDest.sanitize_photo(v.get("photo")), "done": bool(v.get("done", false)), "saved_at": int(v.get("saved_at", 0))}
	if v.get("crew") is Array:
		out["crew"] = (v["crew"] as Array).slice(0, 8).map(func(x): return str(x).left(24))
	if v.get("log") is Array:
		for e in (v["log"] as Array).slice(0, MAX_LOG):
			if e is Dictionary and KINDS.has(str(e.get("kind", ""))):
				out["log"].append({"n": int(e.get("n", 0)), "kind": str(e["kind"]), "key": str(e.get("key", "")), "text": str(e.get("text", "")).left(90),
					"who": (e.get("who", []) as Array).map(func(x): return str(x)) if e.get("who") is Array else [],
					"s": float(e.get("s", 0.0)), "hours": float(e.get("hours", 12.0)), "day": int(e.get("day", 0)), "t": int(e.get("t", 0))})
	if v.get("photos") is Array:
		for p in v["photos"]:
			if p is Dictionary and str(p.get("file", "")).get_file() != "":
				var q := (p as Dictionary).duplicate()
				q["file"] = str(p["file"]).get_file()   # beside the diary, whatever path it was saved with
				q["caption"] = str(p.get("caption", "")).left(120)
				q["who"] = (p.get("who", []) as Array).map(func(x): return str(x)) if p.get("who") is Array else []
				out["photos"].append(q)
	if v.get("stats") is Dictionary:
		out["stats"] = v["stats"]
	if v.get("route") is Dictionary:
		out["route"] = v["route"]
	out["journey"] = AdventureJourney.sanitize_kept(v.get("journey"))
	return out


## This machine's diaries, newest first: [{id, title, dest, date, done, photo (key), cover (a
## photo's file path, or ""), journey (the ride's pins and style, to ride again: see AdventureJourney.sanitize_kept)}]
## (just enough for the shelf and the Route planner's past rides).
static func list() -> Array:
	var out := []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for sub in dir.get_directories():
		var d := load_diary(sub)
		if d.is_empty():
			continue
		var still := cover_photo(d)
		var cover := folder(sub).path_join(still) if still != "" else ""
		out.append({"id": sub, "title": d["title"], "dest": d["dest"], "date": d["date"], "done": d["done"], "km": d["km"],
			"photo": str((d["photo"] as Dictionary).get("key", "")), "cover": cover, "photos": (d["photos"] as Array).size(),
			"highlights": (d["log"] as Array).size(), "saved_at": int(d["saved_at"]), "journey": d["journey"]})
	out.sort_custom(func(a, b): return int(a["saved_at"]) > int(b["saved_at"]))
	return out


## The snapshot on diary `d`'s cover: its first photo that's a still (not a clip or a film), as
## its file in the diary's folder; "" when it has none.
static func cover_photo(d: Dictionary) -> String:
	for p in d.get("photos", []):
		if p is Dictionary and not bool(p.get("clip", false)) and not bool(p.get("movie", false)) and str(p.get("file", "")) != "":
			return str(p["file"])
	return ""


## The diary of the adventure the shed-wall photo `key` was taken on ("" when this machine hasn't one).
static func find_by_photo(key: String) -> String:
	if key == "":
		return ""
	for d in list():
		if str(d["photo"]) == key:
			return str(d["id"])
	return ""


## Only the latest MAX_DIARIES are kept.
static func _trim() -> void:
	var all := list()
	for i in range(MAX_DIARIES, all.size()):
		delete(str(all[i]["id"]))


## Deletes the diary `id` on this machine for good: its diary.json and the photos beside it.
## Whether it was here.
static func delete(id: String) -> bool:
	if id == "" or not FileAccess.file_exists(path_of(id)):
		return false
	var dir := folder(id)
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)
	revision += 1
	return true


## The route as the diary draws it: about `n` points of the road's plan (x, z in metres from the
## start) and its height, the surfaces along it, and its length.
static func route_summary(r: AdventureRoute, n := 240) -> Dictionary:
	var length := r.length
	var pts := []
	var hs := []
	var x0 := r.xz_at(0.0)
	for i in n + 1:
		var s := length * float(i) / float(n)
		var xz := r.xz_at(s)
		pts.append([snappedf(xz[0] - x0[0], 0.1), snappedf(xz[1] - x0[1], 0.1)])
		hs.append(snappedf(r.height_at_s(s), 0.1))
	var surfs := []
	var s := 0.0
	var cur := r.surface_at_s(0.0)
	var from := 0.0
	var step := maxf(AdventureRoute.CHUNK_LEN, length / 400.0)
	while s < length:
		s = minf(s + step, length)
		var here := r.surface_at_s(s)
		if here != cur or s >= length:
			surfs.append([roundf(from), roundf(s), cur])
			from = s
			cur = here
	return {"pts": pts, "h": hs, "surfaces": surfs, "length": length}


## The high points along `r` worth a photo: the tops of the climbs (heights every SAMPLE m; a top
## the highest within PEAK_REACH either side, and at least PEAK_RISE above the lowest of the road
## within RISE_REACH on both sides: a pass, not a bump on the way up), the highest PEAKS of them
## at most, in order along the road: [{s, h}].
const SAMPLE := 40.0
const PEAK_REACH := 1500.0
const RISE_REACH := 4000.0
const PEAK_RISE := 80.0
const PEAKS := 8
static func peaks(r: AdventureRoute) -> Array:
	var hs := PackedFloat32Array()
	var s := 0.0
	while s <= r.length:
		hs.append(r.height_at_s(s))
		s += SAMPLE
	var reach := int(PEAK_REACH / SAMPLE)
	var far := int(RISE_REACH / SAMPLE)
	var out := []
	for i in range(1, hs.size() - 1):
		var h := hs[i]
		if h < hs[i - 1] or h < hs[i + 1]:
			continue
		var top := true
		for k in range(maxi(0, i - reach), mini(hs.size(), i + reach + 1)):
			if hs[k] > h or (hs[k] == h and k < i):
				top = false
				break
		if not top:
			continue
		var lo_a := h
		var lo_b := h
		for k in range(maxi(0, i - far), i):
			lo_a = minf(lo_a, hs[k])
		for k in range(i + 1, mini(hs.size(), i + far + 1)):
			lo_b = minf(lo_b, hs[k])
		if h - maxf(lo_a, lo_b) >= PEAK_RISE:
			out.append({"s": i * SAMPLE, "h": h})
	out.sort_custom(func(x, y): return float(x["h"]) > float(y["h"]))
	out = out.slice(0, PEAKS)
	out.sort_custom(func(x, y): return float(x["s"]) < float(y["s"]))
	return out


# ---------------------------------------------------------------------------- words

## "Day 2, 14:05 · km 23.4 · Dave, Sam": when, where and who of `e` (an entry or a photo).
static func when_text(e: Dictionary) -> String:
	var bits := PackedStringArray()
	var day := int(e.get("day", 0))
	bits.append(("Day %d, " % (day + 1) if day > 0 else "") + Daylight.clock_text(float(e.get("hours", 12.0))))
	bits.append(TripComputer.distance_text(float(e.get("s", 0.0))).replace(" km", " km in").replace(" mi", " mi in") if float(e.get("s", 0.0)) >= 1000.0
		else "at the start" if float(e.get("s", 0.0)) < 50.0 else TripComputer.distance_text(float(e.get("s", 0.0))) + " in")
	var who: Array = e.get("who", [])
	bits.append("the whole crew" if who.is_empty() else ", ".join(who.map(func(x): return str(x))))
	return "  ·  ".join(bits)
