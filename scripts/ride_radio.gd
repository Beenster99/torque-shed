class_name RideRadio
extends Node
## The bike's radio on an adventure: the local stations of the country you're riding through (PlaceSound's
## radio list, the local language first). Each press of its key ({ride_radio}) tunes the next station, and after
## the last it goes off. Switched on again, it starts on the station you last left it on in that country. It plays
## from your bike, on the Radio bus (the radio volume setting), and hisses when a station can't be reached. RideAmbience makes it, so it lasts as long as the ride.

## The station each country was last left on, so the next ride there starts where you were.
static var last := {}

## The country whose stations it plays ("" when there are none), and the station playing (-1 when off).
var country := ""
var index := -1
## Tests turn this on so pressing doesn't go out to the internet.
var offline := false
var _speaker: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _stream: RadioStream


func _ready() -> void:
	_speaker = AudioStreamPlayer3D.new()
	_speaker.bus = "Radio"
	_speaker.unit_size = 10.0
	_speaker.max_distance = 60.0
	add_child(_speaker)
	_hiss = Sfx.make_loop_player(_speaker)
	_hiss.bus = "Radio"
	_hiss.volume_db = -20.0
	_stream = RadioStream.new()
	_stream.player = _speaker
	add_child(_stream)


func _exit_tree() -> void:
	if _stream:
		_stream.stop()


## The station after `i` of `count`: off (-1), the first, the next ... the last, then off again.
static func next_index(i: int, count: int) -> int:
	if count <= 0 or i + 1 >= count:
		return -1
	return i + 1


## How a station reads on the HUD: "NPO Radio 1 · News (Dutch)".
static func label(station: Dictionary) -> String:
	var text := str(station.get("name", "Radio"))
	if str(station.get("genre", "")) != "":
		text += "  ·  " + str(station["genre"])
	var lang := str(station.get("language", "")).get_slice(",", 0)
	if lang != "":
		text += " (%s)" % lang.capitalize()
	return text


func stations() -> Array:
	return PlaceSound.stations(country)


## Tunes the next station (or switches off), and says what's on for the HUD.
func press() -> String:
	var list := stations()
	if list.is_empty():
		return "No local radio here"
	if index < 0:
		index = clampi(int(last.get(country, 0)), 0, list.size() - 1)
	else:
		index = next_index(index, list.size())
	if index < 0:
		last.erase(country)
		_stream.stop()
		Sfx.set_loop(_hiss, "")
		return "Radio off"
	last[country] = index
	if not offline:
		_stream.tune(str(list[index]["url"]))
	return "Radio: %s  ·  {ride_radio} for the next station" % label(list[index])


## Changes country: a radio that was on goes to that country's stations (where you last left them there).
func set_country(cc: String) -> void:
	if cc == country:
		return
	var was_on := index >= 0
	country = cc
	index = -1
	_stream.stop()
	if was_on and not stations().is_empty():
		press()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ride_radio"):
		return
	var trip := AdventureTrip.current
	if trip == null or trip.main == null or trip.main.bike == null or trip.main.menu.visible:
		return
	get_viewport().set_input_as_handled()
	trip.main.hud.flash(press(), 2.5)


func _process(_delta: float) -> void:
	var trip := AdventureTrip.current
	if trip and trip.main and trip.main.bike and is_instance_valid(trip.main.bike):
		_speaker.global_position = trip.main.bike.global_position + Vector3.UP
	# No signal: the static through instead of silence.
	Sfx.set_loop(_hiss, "static" if index >= 0 and not offline and not _stream.is_live() else "")
