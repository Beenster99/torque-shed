class_name SfxAmbience
extends Node
## The shed's background sound, made by Sfx while there's a shed: the room tone of wherever
## you are (the building's low rumble, the showroom's air conditioning), the ceiling lights
## humming (fluorescents with a buzz, or the LED upgrade's faint whine) and ticking on when
## switched on, the air compressor in the back corner cycling on and off (sooner while the
## spray gun or the sandblaster is drawing air), the roof creaking now and then, the sales
## office's sliding doors and its phone ringing as a customer calls ahead, and outside the
## wind, distant traffic, birds by day (now and then, in short bursts, quietest at midday) and
## crickets at night, heard muffled from indoors.

## The compressor's spot: the shed's back left corner, low down.
const COMPRESSOR_POS := Workshop.CENTER + Vector3(-Workshop.HALF.x + 0.6, 0.5, -Workshop.HALF.y + 0.6)
## Seconds the compressor rests between runs, and runs for.
const COMP_REST := Vector2(50.0, 120.0)
const COMP_RUN := Vector2(10.0, 20.0)
## How much faster the tank empties (so the compressor comes on sooner) while air tools run.
const AIR_DRAIN := 8.0
## Birdsong comes in bursts this many seconds long, with gaps this long between them (longer
## round midday, when birds are quietest), at this level (dB).
const BIRD_BURST := Vector2(4.0, 10.0)
const BIRD_GAP := Vector2(25.0, 70.0)
const BIRD_DB := -16.0

## The shed this ambience belongs to.
var workshop: Node3D
var _tone: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _comp: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
## The compressor: running or resting, and how long until it changes.
var compressor_on := false
var comp_timer := 60.0
var _creak_timer := 20.0
var _lit := {}
var _door_amount := -1.0
var _door_dir := 0
## Birds: singing a burst now or not, and how long until that changes.
var birds_singing := false
var bird_timer := 0.0
## Customers already known about, so only a new one rings the phone.
var _customers_seen := {}
var _customers_primed := false
var _customer_check := 0.0


func setup(shed: Node3D) -> void:
	workshop = shed
	_rng.randomize()
	bird_timer = _rng.randf_range(5.0, 25.0)
	_tone = _player("tone_shed", "SFX")
	_hum = _player("hum_fluoro", "SFX")
	_wind = _player("amb_out", "AmbOut")
	_birds = _player("birds", "AmbOut")
	_crickets = _player("crickets", "AmbOut")
	_comp = Sfx.make_loop_player(shed)
	_comp.position = COMPRESSOR_POS
	_comp.volume_db = -9.0
	_comp.unit_size = 3.0
	comp_timer = _rng.randf_range(15.0, 45.0)
	_creak_timer = _rng.randf_range(10.0, 30.0)


func _exit_tree() -> void:
	if is_instance_valid(_comp) and _comp.playing:
		_comp.stop()
	for p in [_tone, _hum, _wind, _birds, _crickets]:
		if is_instance_valid(p):
			p.stop()


func _player(sound: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.stream(sound)
	p.bus = bus
	p.volume_db = -80.0
	p.set_meta("level", 0.0)
	add_child(p)
	return p


func _process(delta: float) -> void:
	var room := Sfx.listener_room
	var indoors := room != ""
	var kind: String = Sfx.ROOM_KIND.get(room, "outside")
	# Room tone.
	var tone := "tone_sales" if kind in ["sales", "office"] else "tone_shed"
	_set_stream(_tone, tone)
	_fade(_tone, 1.0 if indoors else 0.0, delta, -12.0)
	# The lights' hum, in a lit room.
	var led := kind in ["sales", "office"] or (Shed.upgrades.has("led") and kind in ["shed", "storage"])
	_set_stream(_hum, "hum_led" if led else "hum_fluoro")
	_fade(_hum, 1.0 if indoors and lit(room) else 0.0, delta, -10.0 if not led else -14.0)
	_watch_lights(room)
	# Outside: wind and traffic always; birds by day, crickets at night, both hushed by rain.
	var dark := Daylight.darkness()
	var rain := Weather.current.rain if Weather.current else 0.0
	_fade(_wind, 1.0, delta, -8.0)
	_fade(_birds, (1.0 - dark) * (1.0 - rain * 0.85) * _bird_burst(delta), delta, BIRD_DB)
	_fade(_crickets, dark * (1.0 - rain * 0.7), delta, -14.0)
	_muffle_outdoors(indoors, room, delta)
	_compressor(delta)
	_creaks(delta, room, kind)
	_sliding_doors()
	_watch_customers(delta)


## How much the birds are singing now (0..1): an occasional burst, then a long quiet gap that
## stretches round midday, when they sing less and more softly than at dawn and dusk.
func _bird_burst(delta: float, hour := -1.0) -> float:
	var h := Daylight.time_of_day() if hour < 0.0 else hour
	var midday := clampf(1.0 - absf(h - 13.0) / 4.0, 0.0, 1.0)
	bird_timer -= delta
	if bird_timer <= 0.0:
		birds_singing = not birds_singing
		if birds_singing:
			bird_timer = _rng.randf_range(BIRD_BURST.x, BIRD_BURST.y) * (1.0 - 0.3 * midday)
		else:
			bird_timer = _rng.randf_range(BIRD_GAP.x, BIRD_GAP.y) * (1.0 + 1.0 * midday)
	return (1.0 - 0.4 * midday) if birds_singing else 0.0


## A new customer rings the sales office phone as they set off to come in (one already there
## when the shed loads doesn't).
func _watch_customers(delta: float) -> void:
	_customer_check -= delta
	if _customer_check > 0.0:
		return
	_customer_check = 0.5
	var now := Contracts.customers()
	var fresh := false
	for id in now:
		if _customers_seen.has(id) or not _customers_primed:
			continue
		var c: Dictionary = now[id]
		var since := (Contracts.clock() - float(c.get("arrived", Contracts.clock()))) / maxf(Contracts.hours_rate(), 0.000001)
		fresh = fresh or since < 10.0
	_customers_seen = {}
	for id in now:
		_customers_seen[id] = true
	_customers_primed = true
	if fresh:
		Sfx.ring_phone(Contracts.reception().origin + Vector3.UP * 1.1)


## Whether `room`'s lights are on.
static func lit(room: String) -> bool:
	match room:
		"shed", "wing", "annex":
			return Shed.lights_on
		"paint", "storage", "sales":
			return Shed.room_lit(room)
		"sales_office":
			return Shed.room_lit("sales")
		"dyno":
			return bool(Shed.dyno.get("lights", true))
	return false


func _set_stream(p: AudioStreamPlayer, sound: String) -> void:
	var s := Sfx.stream(sound)
	if p.stream != s:
		p.stream = s
		if p.playing:
			p.play(_rng.randf() * s.get_length())


## Eases `p` toward `target` (0..1) at `db` full level.
func _fade(p: AudioStreamPlayer, target: float, delta: float, db: float) -> void:
	var level: float = p.get_meta("level", 0.0)
	level = move_toward(level, target, delta * 0.8)
	p.set_meta("level", level)
	if level > 0.01:
		p.volume_db = linear_to_db(level) + db
		if not p.playing:
			p.play(_rng.randf() * p.stream.get_length())
	elif p.playing:
		p.stop()


## Indoors the outdoor sounds come through the walls: dull and quiet, less so with the
## roller door up.
func _muffle_outdoors(indoors: bool, room: String, delta: float) -> void:
	var bus := AudioServer.get_bus_index("AmbOut")
	if bus < 0:
		return
	var open := room == "shed" and Shed.door_open
	var cutoff := 20000.0 if not indoors else (2500.0 if open else 700.0)
	var vol := 0.0 if not indoors else (-6.0 if open else -12.0)
	var lp := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	if lp:
		lp.cutoff_hz = lerpf(lp.cutoff_hz, cutoff, minf(delta * 3.0, 1.0))
	AudioServer.set_bus_volume_db(bus, lerpf(AudioServer.get_bus_volume_db(bus), vol, minf(delta * 3.0, 1.0)))


## Whether the spray gun or the sandblaster is drawing air anywhere.
static func air_in_use() -> bool:
	for w in Sfx._loops:
		var p := (w as WeakRef).get_ref() as AudioStreamPlayer3D
		if p and p.playing and str(p.get_meta("loop", "")) in ["spray_gun", "blast"]:
			return true
	return false


func _compressor(delta: float) -> void:
	if not is_instance_valid(_comp):
		return
	comp_timer -= delta * (AIR_DRAIN if not compressor_on and air_in_use() else 1.0)
	if comp_timer <= 0.0:
		compressor_on = not compressor_on
		comp_timer = _rng.randf_range(COMP_RUN.x, COMP_RUN.y) if compressor_on else _rng.randf_range(COMP_REST.x, COMP_REST.y)
		Sfx.set_loop(_comp, "compressor" if compressor_on else "")


## Starts the compressor now (tests).
func kick_compressor() -> void:
	compressor_on = false
	comp_timer = 0.0
	_compressor(0.0)


func _creaks(delta: float, room: String, kind: String) -> void:
	_creak_timer -= delta
	if _creak_timer > 0.0:
		return
	_creak_timer = _rng.randf_range(15.0, 45.0)
	if not (kind in ["shed", "storage", "dyno"]):
		return
	var r: Rect2 = Workshop.rooms().get(room, Rect2())
	if r.size == Vector2.ZERO:
		return
	var at := Vector3(_rng.randf_range(r.position.x, r.end.x), Workshop.HEIGHT - 0.2, _rng.randf_range(r.position.y, r.end.y))
	Sfx.play_at("creak", at, -16.0)


## A fluorescent ticking on when a room's lights are switched on while you're in it.
func _watch_lights(room: String) -> void:
	var now := lit(room)
	if _lit.has(room) and now and not bool(_lit[room]):
		var led: bool = str(Sfx.ROOM_KIND.get(room, "")) in ["sales", "office"] or Shed.upgrades.has("led")
		if not led:
			Sfx.play_at("tube_start", Sfx.listener_pos + Vector3.UP * 1.5, -10.0)
	_lit[room] = now


## The sales office's front doors: the operator whirring them open or shut, and the seals
## meeting as they close.
func _sliding_doors() -> void:
	var office := get_tree().get_first_node_in_group("sales_office")
	if office == null or not ("door_open_amount" in office):
		return
	var amount := float(office.door_open_amount)
	if _door_amount < 0.0:
		_door_amount = amount
		return
	var dir := signi(int(signf(amount - _door_amount)))
	var at := SalesOffice.SALES_DOOR + Vector3.UP * 2.4
	if dir != 0 and dir != _door_dir:
		Sfx.play_at("slide_open" if dir > 0 else "slide_close", at, -6.0)
	if dir == 0 and _door_dir < 0 and amount <= 0.001:
		Sfx.play_at("slide_shut", SalesOffice.SALES_DOOR + Vector3.UP * 1.2, -6.0)
	_door_dir = dir
	_door_amount = amount
