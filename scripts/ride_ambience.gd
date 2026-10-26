class_name RideAmbience
extends Node
## The sound of the place you're riding through, made by Sfx while there's an adventure: the beds PlaceSound chooses
## from the place's profile (wind, its birds, cicadas, crickets and frogs in their season, a mountain stream, the surf,
## sheep, cowbells or goat bells, a market, horns, scooters, bicycle bells) eased in and out with the time of day and
## the rain, and the church bells, temple bell or call to prayer at their hours. How built up it is comes from the
## buildings near you on a real road (a village you ride through has its market and bells, the moor beyond has none),
## else from the profile. The season is this month's, so a ride in October sounds like October there.

## How often (s) it looks at the buildings round you, and how far (m) it looks.
const LOOK_EVERY := 1.0
## The place profiles' reader (T1's PlaceProfile), loaded by path so the ride's sound works before it's in the game.
const PROFILES := "res://scripts/place_profile.gd"
const LOOK_REACH := 300.0
## Buildings within LOOK_REACH for each density, sparsest first: fewer than the first is "rural", and so on up to "city".
const BUILT := [[6, "village"], [24, "town"], [70, "city"]]

## The adventure this ambience belongs to.
var world: AdventureWorld
## The place's profile (PlaceProfile's fields) and the sounds chosen for it, as built up as it is here.
var profile := {}
var chosen := {}
## The density the sounds were chosen for ("" until the first look round).
var density := ""
## Each bed's player, made the first time it plays.
var players := {}
var _rng := RandomNumberGenerator.new()
var _look := 0.0
var _hour := -1.0
var _month := 1


## Starts on `adventure` with the place's guessed profile, then takes the baked one when a worker has it.
func start(adventure: AdventureWorld) -> void:
	world = adventure
	setup(profile_of(adventure))
	var where := frame_of(adventure)
	if where != Vector2.INF and ResourceLoader.exists(PROFILES):
		var script: GDScript = load(PROFILES)
		WorkerThreadPool.add_task(func():
			var baked: Dictionary = script.at(where.x, where.y)
			_take_profile.call_deferred(baked))


func _take_profile(baked: Dictionary) -> void:
	if not is_inside_tree() or baked.is_empty() or bool(baked.get("guessed", true)):
		return
	var here := density
	setup(baked, _month)
	_rechoose(here)


func setup(place: Dictionary, month := 0) -> void:
	_rng.randomize()
	profile = place
	_month = month if month > 0 else int(Time.get_date_dict_from_system()["month"])
	density = str(place.get("density", "rural"))
	chosen = PlaceSound.choose(profile, _month)
	# Out on the road nothing is heard through walls: the outdoor bus is left open.
	var bus := AudioServer.get_bus_index("AmbOut")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, 0.0)
		var lp := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
		if lp:
			lp.cutoff_hz = 20000.0


func _exit_tree() -> void:
	for id in players:
		if is_instance_valid(players[id]):
			players[id].stop()


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("audio", pt)


func _process_body(delta: float) -> void:
	if chosen.is_empty():
		return
	_look -= delta
	if _look <= 0.0:
		_look = LOOK_EVERY
		_rechoose(local_density())
	var hour := Daylight.time_of_day()
	var rain := Weather.current.rain if Weather.current else 0.0
	var levels := PlaceSound.mix(chosen, Daylight.darkness(), hour, rain)
	for id in players:
		if not levels.has(id):
			levels[id] = 0.0
	for id in levels:
		_fade(str(id), float(levels[id]), delta)
	# The bells and the call to prayer, as their hour comes round (not all at once when the ride starts).
	if _hour >= 0.0 and hour != _hour:
		var to := hour if hour > _hour else hour + 24.0
		if to - _hour < 1.0:
			for d in PlaceSound.due(chosen, _hour, to):
				ring(str(d[0]), int(d[2]))
	_hour = hour


## Chooses the sounds again when how built up it is here has changed.
func _rechoose(here: String) -> void:
	if here == "" or here == density:
		return
	density = here
	var p := profile.duplicate()
	p["density"] = here
	chosen = PlaceSound.choose(p, _month)


## How built up it is round the listener on a real road, from the buildings within LOOK_REACH: "rural" to "city";
## "" off a real road (the profile's own density stands).
func local_density() -> String:
	if world == null or world.route == null or world.route.real == null or not world.is_inside_tree():
		return ""
	var pos := world.to_local(Sfx.listener_pos)
	var hit := world.locate_local(pos, "ambience")
	if hit.is_empty():
		return ""
	var xz := world.route_xz(pos)
	var c := int(float(hit["s"]) / AdventureRoute.CHUNK_LEN)
	return density_of(world.route.real, c, xz[0], xz[1])


## The density round route-frame (x, z) in chunk `c` of `pack`, by how many of its buildings are within LOOK_REACH.
static func density_of(pack: RealPack, c: int, x: float, z: float) -> String:
	var n := 0
	var reach := int(ceil(LOOK_REACH / AdventureRoute.CHUNK_LEN)) + 1
	for k in range(c - reach, c + reach + 1):
		for b: Array in pack.buildings_in(k):
			if Vector2(float(b[0]) - x, float(b[1]) - z).length() <= LOOK_REACH:
				n += 1
	var out := "rural"
	for step: Array in BUILT:
		if n >= int(step[0]):
			out = str(step[1])
	return out


## Plays a timed sound once: the bells, the temple bell or the call to prayer.
func ring(id: String, _strokes := 1) -> void:
	var s := _stream(PlaceSound.sound_of(id), false)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "AmbOut"
	p.volume_db = PlaceSound.db_of(id) + linear_to_db(maxf(float(chosen["events"].get(id, 1.0)), 0.01))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Eases bed `id` toward `target` (0..1) at its full level, starting it at a random point so two beds of one
## recording never line up.
func _fade(id: String, target: float, delta: float) -> void:
	var p: AudioStreamPlayer = players.get(id)
	if p == null:
		if target <= 0.01:
			return
		var s := _stream(PlaceSound.sound_of(id), true)
		if s == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = s
		p.bus = "AmbOut"
		p.volume_db = -80.0
		p.set_meta("level", 0.0)
		add_child(p)
		players[id] = p
	var level: float = p.get_meta("level", 0.0)
	level = move_toward(level, target, delta * 0.3)
	p.set_meta("level", level)
	if level > 0.01:
		p.volume_db = linear_to_db(level) + PlaceSound.db_of(id)
		if not p.playing:
			p.play(_rng.randf() * p.stream.get_length())
	elif p.playing:
		p.stop()


## A recording from audio/place (looping for a bed), or the synth's sound for "synth:<name>"; null if it's missing.
static func _stream(sound: String, loop: bool) -> AudioStream:
	if sound.begins_with("synth:"):
		return Sfx.stream(sound.trim_prefix("synth:"))
	var path := PlaceSound.DIR + sound + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStreamOggVorbis
	if s and loop:
		s.loop = true
	return s


## The profile of the place an adventure is in: PlaceProfile's (once the place profiles are in the game) at the middle of
## its real region, else {} (PlaceSound's defaults: wind and birds). Doesn't wait on the network.
static func profile_of(adventure: AdventureWorld) -> Dictionary:
	var frame := frame_of(adventure)
	if frame == Vector2.INF or not ResourceLoader.exists(PROFILES):
		return {}
	return load(PROFILES).guess(frame.x, frame.y)


## The (lat, lon) middle of an adventure's real region, or Vector2.INF when it isn't on real roads.
static func frame_of(adventure: AdventureWorld) -> Vector2:
	if adventure == null or adventure.route == null or adventure.route.real == null:
		return Vector2.INF
	return RealRegion.frame_of(adventure.route.real.region)


## A Vorbis file's channel count, from its identification header (the tests keep the beds mono).
static func channels(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var head := f.get_buffer(64)
	for at in range(0, head.size() - 12):
		if head[at] == 0x01 and head.slice(at + 1, at + 7).get_string_from_ascii() == "vorbis":
			return head[at + 11]
	return 0
