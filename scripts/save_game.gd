class_name SaveGame
extends Node
## Save games. Each one is a file under user://saves/<id>.save holding a whole game: the shared
## Shed state (the garage), the clock and where everyone stood, and the host's own character
## (XP, level, tool stages, skills, personal money, rider gear: Progress.profile), so different
## saves have different progress. The host (or a solo player) saves to the save in play every
## minute, when leaving for the title, when the window is closed and from the Esc menu.
##
## Co-op clients never save the shed; it belongs to the host. A client's own character stays
## in their profile.json as before (Progress.select); the host's save only keeps their crew
## numbers and where they stood, so their spot waits for them.
##
## Next to each save sit <id>.meta (name, when last played, play time, garage money, level:
## all the Load screen lists, without reading the whole shed) and <id>.png, a small picture of
## the game when it was saved. The save files are text Variants (var_to_str), so Transform3Ds,
## Colors and int-keyed dictionaries come back exactly. Each is written to a .tmp file and then
## swapped in, keeping the previous save as .bak, so a crash mid-write can't lose the shed.
##
## The one shed from before save games (saves/shed.save) and the character in profile.json are
## turned into the first save game by migrate().

signal saved(ok: bool)

## 2: the save's name, play time and the host's character were added (1 still loads).
const VERSION := 2
## The layout of the world round the shed the save was made in: 0 (none saved) the old yard in
## front of the shed, 1 the shed on the town's High Street with the yard behind (see WorldTown).
const TOWN_LAYOUT := 1
const DIR := "user://saves/"
## The single save from before there were save games; migrate() gives it a name and a character.
const SLOT := "shed"
## Slot used by the test scenes, so running the tests never touches a real save.
const TEST_SLOT := "test"
const AUTOSAVE_INTERVAL := 60.0
const NOTE_INTERVAL := 1.0
## The Load screen's picture of each game.
const THUMB_SIZE := Vector2i(240, 135)
## Play seconds between new pictures for the autosave: reading the screen back holds up a frame,
## so the minute's autosave keeps the last one unless it's this old (a save by hand, or on the
## way out, always takes a new one).
const THUMB_EVERY := 300.0
const NAME_LENGTH := 32
## Crew fields that belong to the moment rather than the player, so aren't carried over.
const TRANSIENT_CREW := ["name", "tool", "activity", "riding", "kmh", "slot", "blaster", "blast_rot", "blast_fire", "blast_at", "blast_base", "blast_scan"]

## Saves and loads go here instead of the save in play when set (the tests use it).
static var slot_override := ""
## Where the saves are kept; the tests point it somewhere else.
static var dir := DIR
## Unix time of the last good save this run (0 before the first), and why the last one failed.
static var last_saved := 0
static var last_error := ""

## The Main scene node: its walker, bike, riding_id, remotes, world, hud and menu.
var main: Node
## The game being played: its name, when it was started (unix) and seconds played in all.
var save_name := ""
var created_at := 0
var play_time := 0.0
## player name -> {xf, riding, stats}: where each player last stood, the bike they were on
## and their crew numbers. Kept for players who have left, so their spot waits for them.
var _players := {}
var _placed := {}           # names already put back where they stood this session
var _loaded := false        # this session continued a save
var _notice := ""
var _autosave := 0.0
var _note_timer := 0.0
var _thumb: Image           # the latest picture of the game, taken while no menu was up
var _thumb_at := -INF       # play_time when it was taken
## The autosave being written out in the background (a WorkerThreadPool task), or -1, and what
## came of it ({err}).
var _task := -1
var _task_job := {}


func _ready() -> void:
	Net.player_joined.connect(_on_player_joined)
	if main and main.menu:
		main.menu.save_requested.connect(func(): save_now(true))
		main.menu.quitting.connect(func(): save_now())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func _exit_tree() -> void:
	_finish_background()


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("save_game", pt)


func _process_body(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish_background()
	if not can_save():
		_autosave = 0.0
		return
	play_time += delta
	_note_timer += delta
	if _note_timer >= NOTE_INTERVAL:
		_note_timer = 0.0
		_note_players()
	_autosave += delta
	if _autosave >= AUTOSAVE_INTERVAL:
		save_now(false, true)


# ---------------------------------------------------------------------------- slots and files

## The save in play: the one picked on the title screen (Settings.current_save).
static func active_slot() -> String:
	if slot_override != "":
		return slot_override
	if _in_tests():
		return TEST_SLOT
	return Settings.current_save if Settings.current_save != "" else SLOT


## Makes `slot` the save in play (and remembers it for next time).
static func use_slot(slot: String) -> void:
	if slot_override != "" or _in_tests():
		slot_override = slot
		return
	Settings.current_save = slot
	Settings.save_settings()


## Whether characters live in the save games. The test scenes keep the old profile files unless
## a test picks a slot itself.
static func characters_in_saves() -> bool:
	return slot_override != "" or not _in_tests()


static func path_of(slot: String) -> String:
	return dir + slot + ".save"


static func meta_path(slot: String) -> String:
	return dir + slot + ".meta"


static func thumb_path(slot: String) -> String:
	return dir + slot + ".png"


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot)) or FileAccess.file_exists(path_of(slot) + ".bak")


## Whether the title menu should continue a save. The test scenes always start a fresh shed
## unless a test picks a slot itself.
static func can_continue() -> bool:
	return has_save(active_slot()) and (slot_override != "" or not _in_tests())


static func _in_tests() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.current_scene != null and tree.current_scene.scene_file_path.begins_with("res://tests/")


## Writes `data` to the slot via a temp file, keeping the previous save as .bak, and its
## Load screen line next to it.
static func write(slot: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var err := _write_text(path_of(slot), var_to_str(data), true)
	if err == OK:
		_write_text(meta_path(slot), var_to_str(meta_of(data)), false)
	return err


static func _write_text(path: String, text: String, keep_backup: bool) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	if FileAccess.file_exists(path):
		if keep_backup:
			if FileAccess.file_exists(path + ".bak"):
				DirAccess.remove_absolute(path + ".bak")
			DirAccess.rename_absolute(path, path + ".bak")
		else:
			DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## The saved game in the slot, falling back to the previous save if the newest is damaged.
## Empty when there's nothing readable.
static func read(slot: String) -> Dictionary:
	var data := _read_file(path_of(slot))
	if data.is_empty():
		data = _read_file(path_of(slot) + ".bak")
	return data


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {}
	var data = str_to_var(text)
	if not data is Dictionary or not data.get("shed") is Dictionary:
		return {}
	var version: int = int(data.get("version", 0))
	if version < 1 or version > VERSION:
		return {}
	return data


static func delete_slot(slot: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".broken"]:
		if FileAccess.file_exists(path_of(slot) + suffix):
			DirAccess.remove_absolute(path_of(slot) + suffix)
	for path in [meta_path(slot), meta_path(slot) + ".tmp", thumb_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## What the Load screen shows of a save: {name, saved_at, created_at, play_time, garage_money,
## bikes, level, money, player, fresh}.
static func meta_of(data: Dictionary) -> Dictionary:
	var shed: Dictionary = data["shed"] if data.get("shed") is Dictionary else {}
	var prof: Dictionary = data["profile"] if data.get("profile") is Dictionary else {}
	var bikes = shed.get("bikes", {})
	var fresh := bool(data.get("fresh", false))
	return {"name": str(data.get("name", "")), "saved_at": int(data.get("saved_at", 0)),
		"created_at": int(data.get("created_at", data.get("saved_at", 0))), "play_time": float(data.get("play_time", 0.0)),
		"garage_money": Money.START_FUNDS if fresh else int(shed.get("garage_money", 0)),
		"bikes": bikes.size() if bikes is Dictionary else 0,
		"level": Progress.level_for_xp(int(prof.get("xp", 0))), "money": int(prof.get("money", 0)),
		"player": str(prof.get("name", data.get("host", ""))), "fresh": fresh}


## Every save game, the most recently played first: its meta_of() plus "id".
static func list_saves() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var ids := {}
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".save"):
			ids[f.trim_suffix(".save")] = true
		elif f.ends_with(".save.bak"):
			ids[f.trim_suffix(".save.bak")] = true
	for id in ids:
		# Test slots left behind by an interrupted test run aren't games.
		if dir == DIR and str(id).begins_with(TEST_SLOT):
			continue
		var meta := read_meta(id)
		if meta.is_empty():
			continue
		meta["id"] = id
		out.append(meta)
	out.sort_custom(func(a, b): return int(a["saved_at"]) > int(b["saved_at"]))
	return out


## A save's Load screen line, from its .meta (made again from the save if that's missing).
## Empty when the save can't be read.
static func read_meta(slot: String) -> Dictionary:
	if FileAccess.file_exists(meta_path(slot)):
		var m = str_to_var(FileAccess.get_file_as_string(meta_path(slot)))
		if m is Dictionary and m.has("name"):
			return m
	var data := read(slot)
	if data.is_empty():
		return {}
	var meta := meta_of(data)
	if meta["name"] == "":
		meta["name"] = "Saved shed"
	_write_text(meta_path(slot), var_to_str(meta), false)
	return meta


## The save's picture, or null when there's none.
static func thumbnail(slot: String) -> Texture2D:
	if not FileAccess.file_exists(thumb_path(slot)):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(thumb_path(slot)))
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


## Another save already has this name (ignoring case); `except` is the one being renamed.
static func name_taken(wanted: String, except := "") -> bool:
	for m in list_saves():
		if m["id"] != except and str(m["name"]).strip_edges().to_lower() == wanted.strip_edges().to_lower():
			return true
	return false


## Why `wanted` can't name a save, or "" when it can.
static func name_problem(wanted: String, except := "") -> String:
	var n := wanted.strip_edges()
	if n == "":
		return "Give the save a name."
	if name_taken(n, except):
		return "There's already a save called %s." % n
	return ""


## "Simon's shed", or "Simon's shed 2" and so on when that's taken.
static func unique_name(base: String) -> String:
	var n := base
	var i := 2
	while name_taken(n):
		n = "%s %d" % [base, i]
		i += 1
	return n


## A new file name for a save called `wanted`: save_<letters of the name>, not yet used.
static func new_id(wanted: String) -> String:
	var slug := ""
	for ch in wanted.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			slug += ch
		elif slug != "" and not slug.ends_with("_"):
			slug += "_"
	slug = slug.trim_suffix("_").left(32)
	var base := "save_" + (slug if slug != "" else "game")
	var id := base
	var i := 2
	while has_save(id) or FileAccess.file_exists(meta_path(id)):
		id = "%s_%d" % [base, i]
		i += 1
	return id


## Gives a save a new name. False when it can't be read or written.
static func rename_slot(slot: String, new_name: String) -> bool:
	var data := read(slot)
	if data.is_empty() or new_name.strip_edges() == "":
		return false
	data["name"] = new_name.strip_edges().left(NAME_LENGTH)
	return write(slot, data) == OK


## The saves from before save games become save games, so nothing is lost: the one saved shed
## (saves/shed.save) gets a name and the character from profile.json; with no shed saved but a
## character in profile.json, that character gets a save of its own with a new shed waiting.
## profile.json itself is kept, for joining other people's sheds. Returns the save made, or "".
static func migrate(player_name: String) -> String:
	if dir == DIR and _in_tests():
		return ""
	if has_save(SLOT):
		var data := read(SLOT)
		if data.is_empty() or data.has("name"):
			return ""
		var host := str(data.get("host", player_name))
		var prof := Progress.stored_profile(host)
		if prof.is_empty():
			prof = Progress.stored_profile(player_name)
		data["name"] = unique_name("%s's shed" % (host if host != "" else player_name))
		data["profile"] = Progress._clean_profile(prof, player_name)
		data["play_time"] = 0.0
		data["created_at"] = int(data.get("saved_at", 0))
		data["version"] = VERSION
		if write(SLOT, data) != OK:
			return ""
		if active_slot() == SLOT or not has_save(active_slot()):
			use_slot(SLOT)
		return SLOT
	if not list_saves().is_empty():
		return ""
	var prof := Progress.stored_profile(player_name)
	if prof.is_empty() or (int(prof.get("xp", 0)) == 0 and int(prof.get("money", 0)) == 0):
		return ""
	var now := int(Time.get_unix_time_from_system())
	var called := unique_name("%s's shed" % player_name)
	var id := new_id(called)
	var fresh := {"version": VERSION, "game": "Torque Shed", "name": called, "fresh": true, "shed": {},
		"saved_at": now, "created_at": now, "play_time": 0.0, "host": player_name,
		"profile": Progress._clean_profile(prof, player_name)}
	if write(id, fresh) != OK:
		return ""
	use_slot(id)
	return id


## "3 bikes, 21:30 on the clock, saved 13 Oct 18:40" for the title menu.
static func describe(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var bikes: Dictionary = data["shed"].get("bikes", {})
	var hours: float = float(data.get("time", 12.0))
	return "%d bike%s, %s on the clock, saved %s" % [bikes.size(), "" if bikes.size() == 1 else "s",
		Daylight.clock_text(hours), _date_text(int(data.get("saved_at", 0)))]


## "Level 7, garage £12,300, 3 h 12 min played, last played 16 Oct 21:40": a save's details.
static func summary_text(meta: Dictionary) -> String:
	if meta.is_empty():
		return ""
	return "Level %d, garage %s, %s played, last played %s" % [int(meta.get("level", 1)),
		TvChannels.money_text(int(meta.get("garage_money", 0))), play_time_text(float(meta.get("play_time", 0.0))),
		_date_text(int(meta.get("saved_at", 0)))]


## "3 h 12 min", "12 min" or "under a minute".
static func play_time_text(seconds: float) -> String:
	var mins := int(seconds / 60.0)
	if mins < 1:
		return "under a minute"
	if mins < 60:
		return "%d min" % mins
	return "%d h %02d min" % [mins / 60, mins % 60]


static func _date_text(unix: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %02d:%02d" % [d["day"], months[clampi(int(d["month"]) - 1, 0, 11)], d["hour"], d["minute"]]


## A line for the Esc menu saying when the shed last saved.
static func status_text() -> String:
	if Net.is_online() and not Net.is_host():
		return "The host saves the shed."
	if last_error != "":
		return "Couldn't save: %s" % last_error
	if last_saved == 0:
		return "Not saved yet this session. It saves itself every minute."
	var ago := int(Time.get_unix_time_from_system()) - last_saved
	if ago < 60:
		return "Saved just now (%s)." % _date_text(last_saved).get_slice(" ", 2)
	return "Last saved %d minute%s ago." % [ago / 60, "" if ago < 120 else "s"]


# ---------------------------------------------------------------------------- saving

func can_save() -> bool:
	return main != null and main.in_session and Shed.active and Shed.is_authority()


## Saves the session to the active slot. Does nothing on a co-op client. `manual` says so on screen.
## `background` (the autosave): the game's taken as it is now, but written out to the file on
## another thread so the game doesn't stop for it, and it keeps the last picture unless that's
## THUMB_EVERY old; true once it's under way.
func save_now(manual := false, background := false) -> bool:
	if not can_save():
		return false
	_finish_background()
	_autosave = 0.0
	if not (main.menu and main.menu.visible) and (not background or _thumb == null or play_time - _thumb_at >= THUMB_EVERY):
		grab_thumbnail()
	var slot := active_slot()
	var data := capture()
	if background:
		_task_job = {"err": OK}
		_task = WorkerThreadPool.add_task(SaveGame._write_with_thumb.bind(slot, data, _thumb.duplicate() if _thumb else null, _task_job),
			false, "Autosave")
		return true
	var err := write(slot, data)
	if err == OK and _thumb:
		_thumb.save_png(thumb_path(slot))
	return _saved(err, manual)


## The save file and its picture written out (on the autosave's thread): what came of it in `job`.
static func _write_with_thumb(slot: String, data: Dictionary, thumb: Image, job: Dictionary) -> void:
	var err := write(slot, data)
	if err == OK and thumb:
		thumb.save_png(thumb_path(slot))
	job["err"] = err


## Waits for the autosave being written in the background, if there is one, and tells of it.
func _finish_background() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if is_inside_tree():
		_saved(int(_task_job.get("err", FAILED)), false)


func _saved(err: Error, manual: bool) -> bool:
	last_error = "" if err == OK else error_string(err)
	if err == OK:
		last_saved = int(Time.get_unix_time_from_system())
	if manual and main.hud:
		main.hud.flash(("Saved %s." % save_name if save_name != "" else "Shed saved.") if err == OK
			else "Couldn't save the shed (%s)." % last_error, 2.0, err != OK)
	saved.emit(err == OK)
	return err == OK


## Saves in a few seconds, once the shed is on screen for the picture.
func save_soon() -> void:
	_autosave = maxf(_autosave, AUTOSAVE_INTERVAL - 3.0)


## Saves the game as a new save called `new_name` and plays on in that one; the save it came
## from stays as it was last saved. False when it can't (a co-op client, or the name is taken).
func save_as(new_name: String) -> bool:
	if not can_save() or name_problem(new_name) != "":
		return false
	var was_slot := active_slot()
	var was_name := save_name
	var was_created := created_at
	use_slot(new_id(new_name))
	save_name = new_name.strip_edges().left(NAME_LENGTH)
	created_at = int(Time.get_unix_time_from_system())
	if save_now(true):
		return true
	use_slot(was_slot)
	save_name = was_name
	created_at = was_created
	return false


## Keeps a small picture of what's on screen now for the Load screen. Called before the Esc
## menu opens, so a save from the menu shows the shed rather than the menu.
func grab_thumbnail() -> void:
	if DisplayServer.get_name() == "headless" or main == null or not main.is_inside_tree():
		return
	var img := main.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var aspect := float(THUMB_SIZE.x) / float(THUMB_SIZE.y)
	var w := mini(img.get_width(), roundi(img.get_height() * aspect))
	var h := mini(img.get_height(), roundi(w / aspect))
	img = img.get_region(Rect2i((img.get_width() - w) / 2, (img.get_height() - h) / 2, w, h))
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
	_thumb = img
	_thumb_at = play_time


## Everything a save holds: the whole Shed snapshot (bikes being ridden are put where they are
## now), the clock and day/night settings, where each player stood, the save's name and play
## time, and this player's own character.
func capture() -> Dictionary:
	_note_players()
	var shed: Dictionary = Shed.save_snapshot().duplicate(true)
	var bikes: Dictionary = shed.get("bikes", {})
	for id in bikes:
		var rider: int = int(bikes[id].get("rider", 0))
		var live = _ridden_transform(rider)
		if rider != 0 and live != null:
			bikes[id]["xf"] = live
	var now := int(Time.get_unix_time_from_system())
	return {"version": VERSION, "game": "Torque Shed", "saved_at": now, "town": TOWN_LAYOUT,
		"name": save_name if save_name != "" else "%s's shed" % _local_name(),
		"created_at": created_at if created_at > 0 else now, "play_time": play_time,
		"host": _local_name(), "shed": shed, "profile": Progress.save_copy(),
		"time": Daylight.time_of_day() if Daylight.current else Settings.time_of_day,
		"day_night_cycle": Settings.day_night_cycle, "day_length": Settings.day_length,
		"weather_mode": Settings.weather,
		"weather": Weather.current.save_data() if Weather.current else {"state": Settings.weather_now, "wet": 0.0},
		"players": _players.duplicate(true)}


func _local_name() -> String:
	return str(Shed.crew.get(Shed.me(), {}).get("name", Settings.player_name))


## Brings _players up to date with everyone here now.
func _note_players() -> void:
	if main == null or not Shed.active:
		return
	if AdventureTrip.current and AdventureTrip.current.on_trip():
		# Out on an adventure: a save keeps everyone back at the shed, off their bikes.
		_note(Shed.me(), _local_name(), Workshop.walker_spawn(Net.local_slot()), 0)
		for peer in main.remotes:
			_note(peer, main.remotes[peer].player_name, Workshop.walker_spawn(0), 0)
		return
	if main.walker:
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, main.walker.yaw()), main.walker.global_position)
		if main.bike:
			xf = _beside(_upright(main.bike.global_transform))
		_note(Shed.me(), _local_name(), xf, int(main.riding_id))
	for peer in main.remotes:
		var rp: RemotePlayer = main.remotes[peer]
		var xf := rp.world_transform()
		if rp.riding_bike != 0:
			xf = _beside(_upright(xf))
		else:
			xf = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
		_note(peer, rp.player_name, xf, rp.riding_bike)


func _note(peer: int, player_name: String, xf: Transform3D, riding: int) -> void:
	var stats := {}
	var c: Dictionary = Shed.crew.get(peer, {})
	for key in c:
		if not key in TRANSIENT_CREW:
			stats[key] = c[key]
	_players[player_name] = {"xf": xf, "riding": riding, "stats": stats}


## Where the bike `rider` is on stands right now, upright on the ground; null if not known.
func _ridden_transform(rider: int):
	if rider == 0 or main == null:
		return null
	if rider == Shed.me() and main.bike:
		return _upright(main.bike.global_transform)
	if main.remotes.has(rider) and main.remotes[rider].bike:
		return _upright(main.remotes[rider].bike.global_transform)
	return null


## A bike's transform stood upright on the ground below it, facing the same way.
func _upright(xf: Transform3D) -> Transform3D:
	var fwd := -xf.basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	var at := xf.origin
	if main.world and main.world.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 3.0, 1)
		var hit: Dictionary = main.world.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			at = hit["position"]
	return Transform3D(Basis(Vector3.UP, heading), at)


## Standing just left of a bike, as you are when you get off it.
func _beside(bike_xf: Transform3D) -> Transform3D:
	return Transform3D(bike_xf.basis, bike_xf.origin - bike_xf.basis * Vector3.RIGHT * 0.9)


# ---------------------------------------------------------------------------- loading

## Opens the saved shed for a solo or hosted session. False when there's no readable save,
## and the caller starts a new shed instead.
func continue_shed() -> bool:
	var slot := active_slot()
	_loaded = false
	_notice = ""
	if not can_continue():
		return false
	var data := read(slot)
	if data.is_empty():
		var broken := path_of(slot) + ".broken"
		DirAccess.copy_absolute(path_of(slot), broken)
		_notice = "The saved shed couldn't be read (kept as %s), so this is a new one." % broken.get_file()
		return false
	return restore(data)


## Starts a new game called `called` (when the save in play couldn't be read, it keeps that
## save's name): a new shed's numbers and, playing solo or hosting, a new character.
func begin_new(called := "") -> void:
	_players.clear()
	_placed.clear()
	_loaded = false
	save_name = called.strip_edges().left(NAME_LENGTH)
	if save_name == "":
		save_name = str(read_meta(active_slot()).get("name", ""))
	if save_name == "":
		save_name = unique_name("%s's shed" % Settings.player_name)
	created_at = int(Time.get_unix_time_from_system())
	play_time = 0.0
	last_saved = 0
	_thumb = null
	if characters_in_saves():
		Progress.use_profile({}, Settings.player_name)


## Puts a saved game back: the shed, the clock, the save's own character, and everyone's crew
## numbers and places.
func restore(data: Dictionary) -> bool:
	var shed = data.get("shed")
	if not shed is Dictionary:
		return false
	save_name = str(data.get("name", ""))
	if save_name == "":
		save_name = unique_name("%s's shed" % str(data.get("host", Settings.player_name)))
	created_at = int(data.get("created_at", data.get("saved_at", 0)))
	play_time = float(data.get("play_time", 0.0))
	_thumb = null
	if characters_in_saves():
		var prof = data.get("profile")
		if not prof is Dictionary:
			# A save from before save games: the character from profile.json comes with it.
			prof = Progress.stored_profile(str(data.get("host", "")))
			if prof.is_empty():
				prof = Progress.stored_profile(Settings.player_name)
		Progress.use_profile(prof, Settings.player_name)
	if bool(data.get("fresh", false)):
		# Made from a character with no shed saved (see migrate): its shed opens new.
		Shed.start_new(Settings.player_name)
		_players.clear()
		_placed.clear()
		last_saved = 0
		return true
	var players = data.get("players", {})
	if int(data.get("town", 0)) < TOWN_LAYOUT:
		# Saved before the shed stood in the town with its yard behind it: what was out in the old
		# yard in front goes to the same place in the yard behind, nothing is left in a building.
		WorldTown.migrate(shed)
		WorldTown.migrate(players)
	Shed.load_state(shed, Settings.player_name)
	Settings.day_night_cycle = bool(data.get("day_night_cycle", Settings.day_night_cycle))
	Settings.day_length = int(data.get("day_length", Settings.day_length))
	var hours: float = float(data.get("time", Settings.time_of_day))
	if Daylight.current:
		Daylight.current.set_time(hours)
	else:
		Settings.time_of_day = wrapf(hours, 0.0, 24.0)
	# Saves from before the weather carry on with whatever it is now.
	Settings.weather = str(data.get("weather_mode", Settings.weather))
	var weather = data.get("weather", {})
	if weather is Dictionary and not weather.is_empty():
		Settings.weather_now = str(weather.get("state", Settings.weather_now))
		if Weather.current:
			Weather.current.restore(weather)
	_players = players.duplicate(true) if players is Dictionary else {}
	# Renamed since the last save: you're still the host who saved it.
	var host := str(data.get("host", ""))
	if not _players.has(Settings.player_name) and _players.has(host):
		_players[Settings.player_name] = _players[host]
		_players.erase(host)
	_placed.clear()
	_restore_stats(Shed.me(), Settings.player_name)
	for peer in Net.players:
		_restore_stats(peer, str(Net.players[peer].get("name", "")))
	_loaded = true
	last_saved = int(data.get("saved_at", 0))
	return true


func _restore_stats(peer: int, player_name: String) -> void:
	if not _players.has(player_name) or not Shed.crew.has(peer):
		return
	var stats: Dictionary = _players[player_name].get("stats", {})
	for key in stats:
		if not key in TRANSIENT_CREW:
			Shed.crew[peer][key] = stats[key]


## Called once the walker is in the world: puts you back where you stood and on the bike you
## were riding, or tells you why the save couldn't be used.
func session_started() -> void:
	if not _loaded:
		if not (Net.is_online() and not Net.is_host()):
			_players.clear()
			_placed.clear()
		if _notice != "" and main.hud:
			main.hud.flash(_notice, 6.0, true)
		_notice = ""
		return
	_loaded = false
	var entry: Dictionary = _players.get(Settings.player_name, {})
	_placed[Settings.player_name] = true
	if entry.has("xf") and main.walker:
		main.walker.place(entry["xf"])
	var bike_id: int = int(entry.get("riding", 0))
	if bike_id != 0 and Shed.bikes.has(bike_id) and Shed.check(Shed.me(), {"a": "mount", "bike": bike_id}) == "":
		Shed.request({"a": "mount", "bike": bike_id})
	for peer in Net.players:
		_place_remote(peer, str(Net.players[peer].get("name", "")))
	if main.hud:
		main.hud.flash("Welcome back. The shed is as you left it.", 4.0)


func _on_player_joined(id: int, info: Dictionary) -> void:
	if main == null or not main.in_session or not Shed.active or not Shed.is_authority():
		return
	var player_name := str(info.get("name", ""))
	_restore_stats(id, player_name)
	Shed._mark_dirty()
	_place_remote(id, player_name)


## Sends a returning player back to where they stood, once a session.
func _place_remote(peer: int, player_name: String) -> void:
	if _placed.has(player_name) or not _players.has(player_name) or not _players[player_name].has("xf"):
		return
	_placed[player_name] = true
	_place_walker.rpc_id(peer, _players[player_name]["xf"])


@rpc("authority", "call_remote", "reliable")
func _place_walker(xf: Transform3D) -> void:
	if main and main.walker and main.bike == null:
		main.walker.place(xf)
