class_name SaveGame
extends Node
## Keeps the shed between sessions. The host (or a solo player) saves the whole shared Shed
## state, the clock and where everyone stood to user://saves/<slot>.save: every minute, when
## leaving for the title, when the window is closed and from the Esc menu. Co-op clients never
## save the shed; it belongs to the host.
##
## The file is a text Variant (var_to_str), so Transform3Ds, Colors and int-keyed dictionaries
## come back exactly. It is written to a .tmp file and then swapped in, keeping the previous save
## as .bak, so a crash mid-write can't lose the shed.

signal saved(ok: bool)

const VERSION := 1
const DIR := "user://saves/"
const SLOT := "shed"
## Slot used by the test scenes, so running the tests never touches a real save.
const TEST_SLOT := "test"
const AUTOSAVE_INTERVAL := 60.0
const NOTE_INTERVAL := 1.0
## Crew fields that belong to the moment rather than the player, so aren't carried over.
const TRANSIENT_CREW := ["name", "tool", "activity", "riding", "kmh", "slot", "blaster", "blast_rot", "blast_fire", "blast_at", "blast_base", "blast_scan"]

## Saves and loads go here instead of the default slot when set.
static var slot_override := ""
## Unix time of the last good save this run (0 before the first), and why the last one failed.
static var last_saved := 0
static var last_error := ""

## The Main scene node: its walker, bike, riding_id, remotes, world, hud and menu.
var main: Node
## player name -> {xf, riding, stats}: where each player last stood, the bike they were on
## and their crew numbers. Kept for players who have left, so their spot waits for them.
var _players := {}
var _placed := {}           # names already put back where they stood this session
var _loaded := false        # this session continued a save
var _notice := ""
var _autosave := 0.0
var _note_timer := 0.0


func _ready() -> void:
	Net.player_joined.connect(_on_player_joined)
	if main and main.menu:
		main.menu.save_requested.connect(func(): save_now(true))
		main.menu.quitting.connect(func(): save_now())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func _process(delta: float) -> void:
	if not can_save():
		_autosave = 0.0
		return
	_note_timer += delta
	if _note_timer >= NOTE_INTERVAL:
		_note_timer = 0.0
		_note_players()
	_autosave += delta
	if _autosave >= AUTOSAVE_INTERVAL:
		save_now()


# ---------------------------------------------------------------------------- slots and files

static func active_slot() -> String:
	if slot_override != "":
		return slot_override
	return TEST_SLOT if _in_tests() else SLOT


static func path_of(slot: String) -> String:
	return DIR + slot + ".save"


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot)) or FileAccess.file_exists(path_of(slot) + ".bak")


## Whether the title menu should continue a save. The test scenes always start a fresh shed
## unless a test picks a slot itself.
static func can_continue() -> bool:
	return has_save(active_slot()) and (slot_override != "" or not _in_tests())


static func _in_tests() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.current_scene != null and tree.current_scene.scene_file_path.begins_with("res://tests/")


## Writes `data` to the slot via a temp file, keeping the previous save as .bak.
static func write(slot: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_of(slot)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(var_to_str(data))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
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


## "3 bikes, 21:30 on the clock, saved 13 Oct 18:40" for the title menu.
static func describe(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var bikes: Dictionary = data["shed"].get("bikes", {})
	var hours: float = float(data.get("time", 12.0))
	return "%d bike%s, %s on the clock, saved %s" % [bikes.size(), "" if bikes.size() == 1 else "s",
		Daylight.clock_text(hours), _date_text(int(data.get("saved_at", 0)))]


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
func save_now(manual := false) -> bool:
	if not can_save():
		return false
	_autosave = 0.0
	var err := write(active_slot(), capture())
	last_error = "" if err == OK else error_string(err)
	if err == OK:
		last_saved = int(Time.get_unix_time_from_system())
	if manual and main.hud:
		main.hud.flash("Shed saved." if err == OK else "Couldn't save the shed (%s)." % last_error, 2.0, err != OK)
	saved.emit(err == OK)
	return err == OK


## Everything a save holds: the whole Shed snapshot (bikes being ridden are put where they are
## now), the clock and day/night settings, and where each player stood.
func capture() -> Dictionary:
	_note_players()
	var shed: Dictionary = Shed.save_snapshot().duplicate(true)
	var bikes: Dictionary = shed.get("bikes", {})
	for id in bikes:
		var rider: int = int(bikes[id].get("rider", 0))
		var live = _ridden_transform(rider)
		if rider != 0 and live != null:
			bikes[id]["xf"] = live
	return {"version": VERSION, "game": "Torque Shed", "saved_at": int(Time.get_unix_time_from_system()),
		"host": _local_name(), "shed": shed,
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


## Puts a saved game back: the shed, the clock, and everyone's crew numbers and places.
func restore(data: Dictionary) -> bool:
	var shed = data.get("shed")
	if not shed is Dictionary:
		return false
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
	var players = data.get("players", {})
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
