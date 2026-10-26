extends Node
## Shed sounds, mostly made from scratch (SfxSynth has the synthesis): tools, machines,
## footsteps by floor, parts landing by material, the building's ambience. A few are recordings
## (RECORDED: the ratchet, sandblaster, dyno fan, roller door, door chime, phone, light switches,
## gear levers, horns and bikes' starter motors, healthy and struggling), which play in place of the made ones when their files are there.
## Sets up the buses the Esc menu's volume sliders control, each straight into Master:
##   SFX:     every sound effect: tools, the washer, impacts, footsteps, machines, UI dings,
##            horns, tyres, the weather and the ambience.
##   Engines: every engine (your bike, other riders', the traffic, the truck, the dyno).
##   Radio:   the shed radio.
## and the buses under SFX that give each room its acoustics (Engines has its own pair,
## EngineRoom and EngineFar, that follow the same room):
##   Room: sounds in the room you're in, through that room's reverb (the shed's hard concrete,
##         the small tiled paint booth, the cluttered store, the showroom's glass, outside's
##         open air with a slap back off the shed wall).
##   Far:  sounds from another room or from outside: muffled through the wall, quieter.
##   AmbOut: the outdoor ambience, muffled while you're indoors.
## The sounds are synthesised on a worker thread at start-up and kept in a cache file in
## user://, so later starts just load them; anything asked for before it's ready is made there
## and then.

const RATE := SfxSynth.RATE
const LOOPS: Array[String] = SfxSynth.LOOP_SOUNDS
## Ear defenders on (the dyno room): every sound effect comes through dull and quieter.
const MUFFLE_CUTOFF := 520.0
const MUFFLE_DB := -12.0
## Which loop each kind of work makes while you hold the button.
const WORK_LOOPS := {"unbolt": "ratchet", "bolt": "ratchet", "clean": "scrub", "clean_many": "scrub", "repair": "grinder", "paint": "spray",
	"pour": "pour", "drain": "pour", "tip": "pour", "wash": "jet", "repair_many": "grinder", "adjust_chain": "ratchet", "lube": "spray",
	"tyre_fit": "changer", "tyre_remove": "changer", "inflate": "compressor"}
## Which loop a tool makes in someone else's hands while they work.
const TOOL_LOOPS := {"wrench": "ratchet", "brush": "scrub", "repair": "grinder", "spray": "spray", "lance": "jet", "gun": "spray_gun",
	"polisher": "polisher"}
## The one-shot when a job is done (putting a part down plays an impact instead, see job_done).
const DONE_SOUNDS := {"unbolt": "clink", "bolt": "clink", "remove": "pickup", "install": "clunk", "take": "pickup",
	"place": "clunk", "drop": "clunk", "set_down": "clunk", "bin": "scrap", "order_part": "clunk", "set_stand": "clunk", "adjust_chain": "clink",
	"tyre_remove": "bead_pop", "coffee_tray_take": "pickup", "coffee_tray_down": "clunk"}
## The sounds a machine makes starting up and stopping, either side of its loop.
const LOOP_TAILS := {"grinder": ["grinder_up", "grinder_down"], "jet": ["jet_on", "jet_off"], "spray_gun": ["gun_on", "gun_off"],
	"door": ["door_start", "door_stop"], "washer": ["pump_on", "pump_off"], "blast": ["blast_on", "blast_off"],
	"compressor": ["comp_on", "comp_off"]}
## How long a loop takes to fade in, for machines that spin up (their start sound covers it).
const LOOP_FADE_IN := {"shaker": 0.5, "grinder": 0.45, "jet": 0.15, "spray_gun": 0.12, "compressor": 0.6, "blast": 0.1, "fan": 1.4}
## Loops that get a small random pitch each time they start (the same tool never quite the same).
const LOOP_DETUNE := ["ratchet", "scrub", "grinder", "polisher", "spray", "spray_gun", "jet", "washer", "blast", "changer", "pour"]
## The acoustics of each kind of room: AudioEffectReverb settings (room size, damping, wet,
## pre-delay in ms, high-pass) and how loud the outdoor ambience comes through.
const ROOM_PRESETS := {
	"shed": {"size": 0.55, "damp": 0.35, "wet": 0.2, "pre": 18.0, "hp": 0.1, "spread": 0.8},
	"paint": {"size": 0.22, "damp": 0.12, "wet": 0.26, "pre": 5.0, "hp": 0.15, "spread": 0.6},
	"storage": {"size": 0.32, "damp": 0.7, "wet": 0.12, "pre": 8.0, "hp": 0.1, "spread": 0.7},
	"dyno": {"size": 0.38, "damp": 0.25, "wet": 0.22, "pre": 10.0, "hp": 0.1, "spread": 0.7},
	"sales": {"size": 0.62, "damp": 0.18, "wet": 0.22, "pre": 24.0, "hp": 0.15, "spread": 1.0},
	"office": {"size": 0.28, "damp": 0.75, "wet": 0.1, "pre": 6.0, "hp": 0.1, "spread": 0.6},
	"outside": {"size": 0.15, "damp": 0.85, "wet": 0.035, "pre": 0.0, "hp": 0.2, "spread": 1.0},
}
## Which acoustics each room (Workshop.room_at) has.
const ROOM_KIND := {"shed": "shed", "wing": "shed", "paint": "paint", "storage": "storage", "annex": "storage", "dyno": "dyno",
	"sales": "sales", "sales_office": "office", "cafe": "sales", "": "outside"}
## How much quieter a sound is through a wall than in the room (dB), and muffled to this cutoff.
const WALL_DB := -7.0
const DOORWAY_DB := -3.5
const FAR_CUTOFF := 1100.0
## Recorded sounds (res://audio/sfx/<file>.ogg, mono) that play in place of the synthesised
## ones: each file is a variant, picked without repeats like the made ones. A sound with no
## recording (or whose files are missing) is synthesised as before.
const RECORDINGS_DIR := "res://audio/sfx/"
const RIDE_AMBIENCE := "res://scripts/ride_ambience.gd"
const RECORDED := {
	"ratchet": ["wrench1", "wrench2", "wrench3", "wrench4"],
	"blast": ["sandblaster1", "sandblaster2", "sandblaster3", "sandblaster4"],
	"fan": ["dynofan1", "dynofan2", "dynofan3"],
	"fan_build": ["dynofanbuild1", "dynofanbuild2", "dynofanbuild3"],
	"door": ["rollerdoor"],
	"bell_chime": ["doorbellchime"],
	"phone_ring": ["telephone1", "telephone2", "telephone3"],
	"light_switch": ["lightswitch1a", "lightswitch1b", "lightswitch2", "lightswitch3"],
	# Simon's four gear clunks, and lighter, quicker takes made from them for a click and a slick box.
	"shift_slick": ["gearslick1", "gearslick2", "gearslick3", "gearslick4"],
	"shift_click": ["gearclick1", "gearclick2", "gearclick3", "gearclick4"],
	"shift_clunk": ["gearclunk1", "gearclunk2", "gearclunk3", "gearclunk4", "gearclunk5", "gearclunk6", "gearclunk7", "gearclunk8"],
	"starter": ["starter1", "starter2", "starter3", "starter4"],
	"starter_struggle": ["starterstruggle1", "starterstruggle2", "starterstruggle3", "starterstruggle4"],
	"horn_disc": ["horn2", "horn4", "horn7"],
	"horn_low": ["horn1"],
	"horn_snail": ["horn3", "horn5"],
	"horn_high": ["horn6"],
	"horn_pip": ["horn8"],
	"horn_air": ["airhorn10", "airhorn12"],
	"horn_truck": ["airhorn9"],
	"horn_train": ["airhorn11"],
	"horn_police": ["policehorn17", "policehorn18", "policehorn19", "policehorn20"],
	"horn_ship": ["shiphorn13", "shiphorn15", "shiphorn16"],
	"horn_tug": ["shiphorn14"],
}
## Sounds that are only ever recordings: without their files they borrow a synthesised one
## ("" for silence).
const STAND_INS := {"light_switch": "switch", "phone_ring": "bell_chime", "fan_build": "", "shift_slick": "", "shift_click": "",
	"shift_clunk": "", "starter_struggle": ""}
## The phone: how many times it rings, and the seconds from one ring to the next.
const PHONE_RINGS := 3
const PHONE_GAP := 2.2
## Bump to throw away the sound cache (the synthesis source's hash is checked too).
const CACHE_VERSION := "shed-sound-1"
const CACHE_PATH := "user://sfx_cache.bin"
## One-shots (play_at, play_on, play_ui, the bells) are in this group while they sound, and go
## after this many seconds at the most whatever they're playing.
const ONESHOT_GROUP := "sfx_oneshot"
const ONESHOT_MAX := 8.0

var muffled := false
## Times the sales office phone has rung (tests).
var phone_calls := 0
## The room the listener is in now ("" outside), and the acoustics shown for it.
var listener_room := ""
var listener_pos := Vector3.ZERO
## How long the synthesis took on the worker thread (ms), and whether it's finished.
var synth_ms := 0.0
var synth_done := false
var loaded_from_cache := false
## Main-thread time spent setting up in _ready (ms), for the start-up budget.
var ready_ms := 0.0

var _streams := {}      # sound -> Array[AudioStreamWAV], variant order
var _recorded := {}     # sound -> Array[AudioStream], its recordings
var _pcm := {}          # "sound#v" -> PackedByteArray (16-bit), filled by the worker
var _mutex := Mutex.new()
var _thread: Thread
var _abort := false
var _rng := RandomNumberGenerator.new()
var _last_pick := {}    # sound -> the variant played last
var _loops: Array = []  # loop players made here, to keep routed as the listener moves
var _once_of := {}      # a looping stream's instance id -> its play-once copy (once)
var _route_timer := 0.0
var _preset := {}       # the reverb settings shown now, easing toward the room's
var _ambience: Node
## The ride's ambience while out on an adventure (RideAmbience, loaded only then), else null.
var _ride_ambience: Node
var _amb_timer := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_rng.randomize()
	for bus in ["SFX", "Engines", "Radio"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_make_room_buses()
	apply_volumes()
	_preset = (ROOM_PRESETS["shed"] as Dictionary).duplicate()
	_apply_preset(_preset)
	_thread = Thread.new()
	_thread.start(_synth_all, Thread.PRIORITY_LOW)
	ready_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _exit_tree() -> void:
	_abort = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## The volume sliders (and the ear defenders) onto the buses.
func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001))
		+ (MUFFLE_DB if muffled else 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Engines"), linear_to_db(maxf(Settings.engine_volume, 0.0001))
		+ (MUFFLE_DB if muffled else 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Radio"), linear_to_db(maxf(Settings.radio_volume, 0.0001)))


## The first synthesised variant of `sound` (a loop has only the one).
func stream(sound: String) -> AudioStreamWAV:
	return variants(sound)[0]


## The recordings of `sound` (RECORDED), loaded once; empty if it has none.
func recordings(sound: String) -> Array:
	if not _recorded.has(sound):
		var list := []
		for file in RECORDED.get(sound, []):
			var path := RECORDINGS_DIR + str(file) + ".ogg"
			if not ResourceLoader.exists(path):
				continue
			var s := load(path) as AudioStream
			if s == null:
				continue
			if LOOPS.has(sound) and s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			list.append(s)
		_recorded[sound] = list
	return _recorded[sound]


## What `sound` plays: its recordings if it has any, else its synthesised variants (or what
## stands in for it, STAND_INS). Empty for a sound with nothing to play.
func sounds(sound: String) -> Array:
	var rec := recordings(sound)
	if not rec.is_empty():
		return rec
	if STAND_INS.has(sound):
		return [] if str(STAND_INS[sound]) == "" else sounds(str(STAND_INS[sound]))
	return variants(sound)


## Every synthesised variant of `sound`.
func variants(sound: String) -> Array:
	if not _streams.has(sound):
		var list := []
		for v in SfxSynth.variant_count(sound):
			list.append(_wav(sound, v))
		_streams[sound] = list
	return _streams[sound]


## A variant of `sound` (a recording if it has them) picked at random, never the same one twice
## running. Null for a sound with nothing to play.
func pick(sound: String) -> AudioStream:
	var list := sounds(sound)
	if list.is_empty():
		return null
	if list.size() == 1:
		return list[0]
	var last := int(_last_pick.get(sound, -1))
	var v := _rng.randi_range(0, list.size() - 2)
	if v >= last and last >= 0:
		v += 1
	_last_pick[sound] = v
	return list[v]


## Ear defenders on or off: a low-pass filter on the sound effects (engines, the dyno, tools,
## footsteps) and the level brought down. The radio isn't affected.
func set_muffled(on: bool) -> void:
	if on == muffled:
		return
	muffled = on
	for name in ["SFX", "Engines"]:
		var bus := AudioServer.get_bus_index(name)
		if bus < 0:
			continue
		var at := -1
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
				at = i
		if at < 0 and on:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = MUFFLE_CUTOFF
			lp.resonance = 0.4
			AudioServer.add_bus_effect(bus, lp)
			at = AudioServer.get_bus_effect_count(bus) - 1
		if at >= 0:
			AudioServer.set_bus_effect_enabled(bus, at, on)
	apply_volumes()


## Whether the sound effects are coming through muffled right now.
func is_muffled() -> bool:
	var bus := AudioServer.get_bus_index("SFX")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(bus, i):
			return true
	return false


## Plays a one-shot at a point in the world: a different variant each time (never the same
## twice running) with a touch of pitch and level, through the acoustics of where it is.
## Never loops (see once) and always goes (see _free_when_done); `seconds` cuts a long take short.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, parent: Node = null, seconds := 0.0) -> AudioStreamPlayer3D:
	var host: Node = parent if parent else get_tree().current_scene
	if host == null:
		return null
	var s := pick(sound)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.set_meta("sound", sound)
	p.stream = once(s)
	p.volume_db = volume_db + _rng.randf_range(-1.2, 1.2) + occlusion_db(pos)
	p.pitch_scale = _rng.randf_range(0.95, 1.05)
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.bus = bus_for(pos)
	host.add_child(p)
	p.global_position = pos
	_free_when_done(p, seconds)
	p.play()
	return p


## A one-shot riding along on `source` (a truck, a trailer, someone's hand): it plays from
## `offset` in the source's own space, moves with it, goes when the source does, and never
## loops. `seconds` cuts a long take short (0: the whole of it).
func play_on(sound: String, source: Node3D, offset := Vector3.ZERO, volume_db := 0.0, seconds := 0.0) -> AudioStreamPlayer3D:
	if source == null or not source.is_inside_tree():
		return null
	var p := play_at(sound, source.global_transform * offset, volume_db, source, seconds)
	if p:
		p.position = offset
	return p


## `s` to play once: a looping take (the work loops' recordings and synthesised loops are set
## to loop) comes back as a copy that plays through once and finishes, so a one-shot made from
## it can't ring on for ever where it was played. Made once per stream.
func once(s: AudioStream) -> AudioStream:
	if s == null:
		return null
	var looped := (s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED) \
		or (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop) \
		or (s is AudioStreamMP3 and (s as AudioStreamMP3).loop)
	if not looped:
		return s
	var key := s.get_instance_id()
	if _once_of.has(key):
		return _once_of[key]
	var c: AudioStream = s.duplicate()
	if c is AudioStreamWAV:
		(c as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif c is AudioStreamOggVorbis:
		(c as AudioStreamOggVorbis).loop = false
	elif c is AudioStreamMP3:
		(c as AudioStreamMP3).loop = false
	_once_of[key] = c
	return c


## A one-shot player goes when it's finished, and in any case once its stream's had time to
## play through (ONESHOT_MAX at most, or `seconds`), so nothing's left sounding in the world.
func _free_when_done(p: Node, seconds := 0.0) -> void:
	p.add_to_group(ONESHOT_GROUP)
	p.finished.connect(p.queue_free)
	var st: AudioStream = p.get("stream")
	var life := ONESHOT_MAX
	if st and st.get_length() > 0.0:
		life = minf(st.get_length() / maxf(float(p.get("pitch_scale")), 0.1) + 0.25, ONESHOT_MAX)
	if seconds > 0.0:
		life = minf(life, seconds)
	var ref: WeakRef = weakref(p)
	get_tree().create_timer(life, false).timeout.connect(func():
		var n := ref.get_ref() as Node
		if n:
			n.queue_free())


## How many one-shots are sounding (or waiting to go) right now (tests).
func oneshots_alive() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group(ONESHOT_GROUP):
		if not p.is_queued_for_deletion():
			n += 1
	return n


## A part or kit landing: `material` is what it's made of (a PartsDB material, or "metal",
## "plastic", "rubber", "soft", "cardboard"), `surface` what it lands on ("concrete", "wood"
## for the bench, "steel" for shelves and machines, "ground" outside), `strength` 0..1 how hard.
func impact(material: String, surface: String, strength: float, at: Vector3) -> AudioStreamPlayer3D:
	var m := impact_material(material)
	var s := surface if SfxSynth.SURFACES.has(surface) else "concrete"
	var k := clampf(strength, 0.0, 1.0)
	var p := play_at("impact_%s_%s" % [m, s], at, lerpf(-18.0, -1.0, k))
	if p:
		p.pitch_scale *= lerpf(0.97, 1.02, k)
	return p


## What a PartsDB material sounds like when it lands.
static func impact_material(material: String) -> String:
	match material:
		"metal", "plastic", "rubber", "soft", "cardboard":
			return material
		"electronics", "carbon", "mixed", "wood":
			return "plastic"
		"fabric", "leather":
			return "soft"
	return "metal"


## The sound of a job finished, for the one doing it: putting a part down (`held` was in
## their hands) lands it with an impact by its material and what it's put on; anything else
## plays its DONE_SOUNDS one-shot.
func job_done(action_name: String, action: Dictionary, held: int, pos: Vector3) -> void:
	if action_name in ["drop", "place", "set_down"] and held != 0 and Shed.items.has(held):
		var it: Dictionary = Shed.items[held]
		var mat := "cardboard" if it.get("boxed", false) else PartsDB.material(str(it.get("part", "")))
		var at := pos
		if action.get("xf") is Transform3D:
			at = (action["xf"] as Transform3D).origin
		impact(mat, put_down_surface(action, at), 0.85 if action_name == "drop" else 0.5, at)
		return
	var done: String = DONE_SOUNDS.get(action_name, "")
	if done != "":
		play_at(done, pos, -4.0)


## What a part put down with `action` lands on.
func put_down_surface(action: Dictionary, at: Vector3) -> String:
	match str(action.get("a", "")):
		"place":
			var spot := str(action.get("spot", ""))
			if spot.begins_with("bench"):
				return "wood"
			return "steel"
		"set_down":
			var s: Dictionary = Shed.surface(str(action.get("top", "")))
			return "wood" if str(s.get("kind", "")) == "bench" else "steel"
	if Workshop.room_at(at) != "":
		return "concrete"
	return "ground" if ground_at(at) in ["grass", "dirt"] else "concrete"


## A footstep at `pos` (someone's feet), sounding like the floor there.
func footstep(pos: Vector3, running := false, volume_db := -14.0) -> AudioStreamPlayer3D:
	return play_at("step_" + step_surface(pos), pos, volume_db + (3.0 if running else 0.0))


## Which floor is under `pos`, for footsteps (SfxSynth.STEP_SURFACES).
func step_surface(pos: Vector3) -> String:
	var room := Workshop.room_at(pos)
	var epoxy := Shed.upgrades.has("epoxy")
	match room:
		"shed", "wing", "storage", "dyno":
			return "epoxy" if epoxy else "concrete"
		"annex":
			return "metal" if pos.y > 0.3 else ("epoxy" if epoxy else "concrete")
		"paint", "mixing":
			return "tile"
		"sales":
			return "wood" if pos.y > 0.25 else "tile"
		"sales_office", "lounge":
			return "carpet"
	var ground := ground_at(pos)
	var wet := Weather.current.wet if Weather.current else 0.0
	if wet > 0.4 and ground != "grass" and _rng.randf() < wet * 0.5:
		return "puddle"
	match ground:
		"grass":
			return "grass"
		"dirt", "gravel":
			return "gravel"
	return "tarmac"


## The "surface" a ray straight down from `pos` meets ("tarmac", "dirt", "grass"), or "".
func ground_at(pos: Vector3) -> String:
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return ""
	var space := vp.world_3d.direct_space_state
	if space == null:
		return ""
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit["collider"] == null:
		return ""
	var c: Object = hit["collider"]
	return str(c.get_meta("surface", "")) if c.has_meta("surface") else ""


## A looping player for work sounds, parked on `parent`. Set its stream to start a loop.
func make_loop_player(parent: Node3D) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Room"
	p.unit_size = 4.0
	p.max_distance = 40.0
	parent.add_child(p)
	_loops.append(weakref(p))
	return p


## The sales office's door bell: the brass shop bell rings at `at` (loud close by, carrying
## across the yard), and the chime box on the shed's wall goes ding-dong so the crew hear it at
## work. Only plays here: Shed.ring_bell rings it for everyone.
func bell(at: Vector3) -> void:
	var host: Node = get_tree().current_scene if get_tree() else null
	if host == null:
		return
	var pairs := [["bell", at, 2.0, 9.0, 140.0], ["bell_chime", SalesOffice.SHED_CHIME_POS, -2.0, 5.0, 60.0]]
	if not recordings("bell_chime").is_empty():
		# The recorded door chime is the arrival bell; the brass bell just tinkles along.
		pairs = [["bell_chime", at, 0.0, 9.0, 140.0], ["bell", at, -8.0, 6.0, 60.0], ["bell_chime", SalesOffice.SHED_CHIME_POS, -2.0, 5.0, 60.0]]
	for p in pairs:
		var player := AudioStreamPlayer3D.new()
		player.stream = once(pick(str(p[0])))
		player.bus = bus_for(p[1])
		player.volume_db = float(p[2]) + occlusion_db(p[1]) * 0.5
		player.unit_size = float(p[3])
		player.max_distance = float(p[4])
		player.attenuation_filter_cutoff_hz = 12000.0
		host.add_child(player)
		player.global_position = p[1]
		_free_when_done(player)
		player.play()
	# The shop bell over the doors and the chime's striker swing.
	var office := get_tree().get_first_node_in_group("sales_office")
	if office and office.has_method("ring"):
		office.ring()


## The sales office phone ringing at `at`: a few rings a couple of seconds apart, a different
## take each time, with the extension bell on the shed's wall (by the door chime) ringing along
## so the crew hear it at work. Only plays here: SfxAmbience rings it on every player's PC
## when a new customer calls ahead. Out on the High Street it isn't heard at all: its bell
## carrying out of the office was a shop bell going off along the street (see indoors()).
func ring_phone(at: Vector3, rings := PHONE_RINGS) -> void:
	var tree := get_tree()
	if tree == null:
		return
	phone_calls += 1
	if not indoors():
		return
	for i in rings:
		tree.create_timer(i * PHONE_GAP).timeout.connect(func():
			play_at("phone_ring", at, -3.0)
			play_at("phone_ring", SalesOffice.SHED_CHIME_POS, -12.0))


## Plays a one-shot that isn't anywhere in the world: menu and HUD sounds.
func play_ui(sound: String, volume_db := 0.0) -> void:
	var host: Node = get_tree().current_scene if get_tree() else null
	if host == null:
		return
	var st := pick(sound)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.set_meta("sound", sound)
	p.stream = once(st)
	p.bus = "SFX"
	p.volume_db = volume_db
	host.add_child(p)
	_free_when_done(p)
	p.play()


## Starts `sound` looping on `p`, or stops it for "". Machines play their start-up and
## run-down sounds either side (LOOP_TAILS), and every start picks up the loop at a random
## point with a touch of pitch, so the same tool never sounds quite the same twice.
func set_loop(p: AudioStreamPlayer3D, sound: String) -> void:
	var was := str(p.get_meta("loop", ""))
	if sound == "":
		if p.playing:
			p.stop()
			_tail(p, was, 1)
		return
	if p.playing and was == sound:
		return
	var s := pick(sound)
	if s == null:
		return
	if not p.has_meta("base_db"):
		p.set_meta("base_db", p.volume_db)
		p.set_meta("base_pitch", p.pitch_scale)
	var starting := not p.playing
	p.stream = s
	p.set_meta("loop", sound)
	if LOOP_DETUNE.has(sound):
		p.pitch_scale = float(p.get_meta("base_pitch", 1.0)) * _rng.randf_range(0.97, 1.03)
	p.set_meta("fade", 0.0 if starting and LOOP_FADE_IN.has(sound) else 1.0)
	_route(p)
	p.play(_rng.randf() * s.get_length() * 0.9)
	if starting:
		_tail(p, sound, 0)


func _tail(p: AudioStreamPlayer3D, sound: String, which: int) -> void:
	if not LOOP_TAILS.has(sound) or not p.is_inside_tree():
		return
	play_at(str(LOOP_TAILS[sound][which]), p.global_position, float(p.get_meta("base_db", p.volume_db)))


## Which bus a sound at `pos` goes through: "Room" if it's in the listener's room (or both
## are outside), "Far" through a wall. An `engine`'s are the Engines bus's pair (EngineRoom,
## EngineFar), so the engines slider has them.
func bus_for(pos: Vector3, engine := false) -> String:
	var bus := "Room" if Workshop.room_at(pos) == listener_room else "Far"
	return "Engine" + bus if engine else bus


## How much quieter a sound at `pos` is for the listener (dB): nothing in the same room, a
## little through an open doorway (the side rooms, the roller door up), more through a wall.
func occlusion_db(pos: Vector3) -> float:
	var room := Workshop.room_at(pos)
	if room == listener_room:
		return 0.0
	var pair := [room, listener_room]
	if pair.has("shed") and (pair.has("paint") or pair.has("storage") or pair.has("dyno")):
		return DOORWAY_DB
	if pair.has("shed") and pair.has("") and Shed.door_open:
		return DOORWAY_DB
	if pair.has("sales") and pair.has("sales_office"):
		return DOORWAY_DB
	if pair.has("cafe") and pair.has(""):
		return DOORWAY_DB   # the coffee shop's door stands open
	return WALL_DB


func _route(p: AudioStreamPlayer3D) -> void:
	if not p.is_inside_tree() or not (p.bus in ["SFX", "Room", "Far"]):
		return
	var pos := p.global_position
	p.bus = bus_for(pos)
	if p.has_meta("base_db"):
		var fade: float = p.get_meta("fade", 1.0)
		p.volume_db = float(p.get_meta("base_db")) + occlusion_db(pos) + linear_to_db(maxf(fade, 0.03))


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("audio", pt)


func _process_body(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		listener_pos = cam.global_position
		var room := Workshop.room_at(listener_pos) if Shed.active else listener_room
		if room != listener_room:
			listener_room = room
			_route_timer = 0.0
	# Ease the reverb toward this room's.
	var target: Dictionary = ROOM_PRESETS[ROOM_KIND.get(listener_room, "shed")]
	var moved := false
	for key in target:
		var v: float = _preset[key]
		var nv := move_toward(v, float(target[key]), delta * (30.0 if key == "pre" else 0.6))
		if not is_equal_approx(nv, v):
			_preset[key] = nv
			moved = true
	if moved:
		_apply_preset(_preset)
	_slapback()
	# Fades and routing for the loops.
	for w in _loops:
		var p := (w as WeakRef).get_ref() as AudioStreamPlayer3D
		if p and p.playing and float(p.get_meta("fade", 1.0)) < 1.0:
			var sound := str(p.get_meta("loop", ""))
			p.set_meta("fade", minf(float(p.get_meta("fade", 1.0)) + delta / float(LOOP_FADE_IN.get(sound, 0.1)), 1.0))
			_route(p)
	_route_timer -= delta
	if _route_timer <= 0.0:
		_route_timer = 0.15
		var alive := []
		for w in _loops:
			var p := (w as WeakRef).get_ref() as AudioStreamPlayer3D
			if p:
				alive.append(w)
				if p.playing:
					_route(p)
		_loops = alive
	_amb_timer -= delta
	if _amb_timer <= 0.0:
		_amb_timer = 0.5
		_keep_ambience()


## Shows the reverb settings in `pr` on the Room bus (and the engines' EngineRoom).
func _apply_preset(pr: Dictionary) -> void:
	for name in ["Room", "EngineRoom"]:
		var bus := AudioServer.get_bus_index(name)
		if bus < 0:
			continue
		var rv := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
		if rv != null:
			_set_reverb(rv, pr)


func _set_reverb(rv: AudioEffectReverb, pr: Dictionary) -> void:
	rv.room_size = float(pr["size"])
	rv.damping = float(pr["damp"])
	rv.wet = float(pr["wet"])
	rv.dry = 1.0
	rv.predelay_msec = float(pr["pre"])
	rv.hipass = float(pr["hp"])
	rv.spread = float(pr["spread"])


## Outside, a sound comes back off the shed's wall a moment later: a single quiet echo, its
## delay the walk there and back at the speed of sound.
func _slapback() -> void:
	var on := listener_room == "" and Shed.active
	var dist := 0.0
	if on:
		var shed: Rect2 = Workshop.rooms()["shed"]
		var p := Vector2(listener_pos.x, listener_pos.z)
		var dx := maxf(maxf(shed.position.x - p.x, p.x - shed.end.x), 0.0)
		var dz := maxf(maxf(shed.position.y - p.y, p.y - shed.end.y), 0.0)
		dist = Vector2(dx, dz).length()
		on = dist > 2.0 and dist < 45.0
	for name in ["Room", "EngineRoom"]:
		var bus := AudioServer.get_bus_index(name)
		if bus < 0 or AudioServer.get_bus_effect_count(bus) < 2:
			continue
		if on:
			var dl := AudioServer.get_bus_effect(bus, 1) as AudioEffectDelay
			dl.tap1_delay_ms = clampf(dist * 2.0 / 343.0 * 1000.0, 15.0, 260.0)
			dl.tap1_level_db = -13.0 - dist * 0.3
		if AudioServer.is_bus_effect_enabled(bus, 1) != on:
			AudioServer.set_bus_effect_enabled(bus, 1, on)


## The reverb settings showing on the Room bus now.
func room_reverb() -> AudioEffectReverb:
	return AudioServer.get_bus_effect(AudioServer.get_bus_index("Room"), 0) as AudioEffectReverb


## Moves the listener's room at once (tests, and teleports): the reverb jumps straight there.
func set_listener_room(room: String) -> void:
	listener_room = room
	_preset = (ROOM_PRESETS[ROOM_KIND.get(room, "shed")] as Dictionary).duplicate()
	_apply_preset(_preset)


func _make_room_buses() -> void:
	var specs := [["Room", "SFX"], ["Far", "SFX"], ["AmbOut", "SFX"], ["EngineRoom", "Engines"], ["EngineFar", "Engines"]]
	for sp in specs:
		if AudioServer.get_bus_index(str(sp[0])) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, str(sp[0]))
		AudioServer.set_bus_send(i, str(sp[1]))
		match str(sp[0]):
			"Room", "EngineRoom":
				AudioServer.add_bus_effect(i, AudioEffectReverb.new())
				var dl := AudioEffectDelay.new()
				dl.dry = 1.0
				dl.tap1_active = true
				dl.tap1_delay_ms = 120.0
				dl.tap1_level_db = -16.0
				dl.tap2_active = false
				dl.feedback_active = false
				AudioServer.add_bus_effect(i, dl)
				AudioServer.set_bus_effect_enabled(i, 1, false)
			"Far", "EngineFar":
				var lp := AudioEffectLowPassFilter.new()
				lp.cutoff_hz = FAR_CUTOFF
				AudioServer.add_bus_effect(i, lp)
				var rv := AudioEffectReverb.new()
				rv.room_size = 0.5
				rv.damping = 0.5
				rv.wet = 0.3
				rv.dry = 0.85
				AudioServer.add_bus_effect(i, rv)
			"AmbOut":
				var lp2 := AudioEffectLowPassFilter.new()
				lp2.cutoff_hz = 20000.0
				AudioServer.add_bus_effect(i, lp2)


func _keep_ambience() -> void:
	var workshop := get_tree().get_first_node_in_group("workshop") if Shed.active else null
	# A new shed (left to the title and back): the old ambience goes with the old shed.
	if _ambience and (workshop == null or _ambience.workshop != workshop):
		_ambience.queue_free()
		_ambience = null
	# Waits for the worker to have made the sounds, so building it doesn't stall a frame.
	if workshop and _ambience == null and synth_done:
		_ambience = SfxAmbience.new()
		_ambience.name = "Ambience"
		add_child(_ambience)
		_ambience.setup(workshop)
	# Out on an adventure: the sound of the place being ridden through, made afresh for each ride. Its script is loaded
	# only on a ride, so the adventure's classes aren't pulled in with Sfx when the game starts.
	var world: Node = null
	if int(Shed.adventure.get("id", 0)) != 0:
		world = load(RIDE_AMBIENCE).current_world()
	if _ride_ambience and (world == null or _ride_ambience.world != world or not world.is_inside_tree()):
		_ride_ambience.queue_free()
		_ride_ambience = null
	if world and world.is_inside_tree() and _ride_ambience == null and synth_done:
		_ride_ambience = load(RIDE_AMBIENCE).new()
		_ride_ambience.name = "RideAmbience"
		add_child(_ride_ambience)
		_ride_ambience.start(world)


## Whether the ride's ambience is playing (out on an adventure): the shed's outdoor sounds stay quiet meanwhile.
func riding() -> bool:
	return _ride_ambience != null


## The shed's ambience node while there's a shed (SfxAmbience), else null.
func ambience() -> Node:
	if _ambience and is_instance_valid(_ambience.workshop) and _ambience.workshop == get_tree().get_first_node_in_group("workshop"):
		return _ambience
	return null


# ---------------------------------------------------------------------------- making and caching

func _wav(sound: String, v: int) -> AudioStreamWAV:
	var key := "%s#%d" % [sound, v]
	_mutex.lock()
	var bytes: PackedByteArray = _pcm.get(key, PackedByteArray())
	_mutex.unlock()
	if bytes.is_empty():
		bytes = to_pcm16(SfxSynth.make(sound, v))
		_mutex.lock()
		_pcm[key] = bytes
		_mutex.unlock()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if LOOPS.has(sound):
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = bytes.size() / 2
	return wav


## Samples (-1..1) as 16-bit PCM bytes.
static func to_pcm16(data: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(roundi(data[i] * 32767.0), -32768, 32767))
	return bytes


## The cache's key: the version, and the synthesis source when it can be read (so editing it
## throws the cache away).
static func cache_key() -> String:
	var src := FileAccess.get_file_as_string("res://scripts/sfx_synth.gd")
	return "%s:%d:%d" % [CACHE_VERSION, RATE, src.hash()]


## The worker: loads the cache, or makes every sound (the shed's own first) and saves it.
func _synth_all() -> void:
	var t0 := Time.get_ticks_usec()
	var key := cache_key()
	var cached := _load_cache(key)
	if not cached.is_empty():
		_mutex.lock()
		for k2 in cached:
			if not _pcm.has(k2):
				_pcm[k2] = cached[k2]
		_mutex.unlock()
		loaded_from_cache = true
	var made := 0
	for sound in SfxSynth.all_sounds():
		for v in SfxSynth.variant_count(sound):
			if _abort:
				return
			var k3 := "%s#%d" % [sound, v]
			_mutex.lock()
			var have := _pcm.has(k3)
			_mutex.unlock()
			if have:
				continue
			var bytes := to_pcm16(SfxSynth.make(sound, v))
			_mutex.lock()
			if not _pcm.has(k3):
				_pcm[k3] = bytes
			_mutex.unlock()
			made += 1
	synth_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if made > 0 and not _abort:
		_mutex.lock()
		var all := _pcm.duplicate()
		_mutex.unlock()
		_save_cache(key, all)
	synth_done = true


func _load_cache(key: String) -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var f := FileAccess.open_compressed(CACHE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data = f.get_var()
	if not (data is Dictionary) or str(data.get("key", "")) != key or not (data.get("pcm") is Dictionary):
		return {}
	return data["pcm"]


func _save_cache(key: String, pcm: Dictionary) -> void:
	var f := FileAccess.open_compressed(CACHE_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f:
		f.store_var({"key": key, "pcm": pcm})


## Whether the listener is inside the shed or the sales office (any of Workshop's rooms), not
## out on the forecourt or the High Street. The office's bells (the phone, the till) ring
## only for those inside.
func indoors() -> bool:
	return Workshop.room_at(listener_pos) != ""
