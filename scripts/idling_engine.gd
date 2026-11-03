class_name IdlingEngine
extends Node3D
## A parked bike that was got off with its engine running (Shed.idling): it ticks over where it
## was left, for the whole crew. Its idle is heard from its pipe (an EngineSound held at tickover,
## Simon's recorded idles where the engine has one), a wisp of exhaust drifts from the tail pipe
## and its dash and lamps stay lit as the switch was left. Hung on the parked bike's model by
## whatever draws it (Workshop in the shed and out on the road, RoadsideView on an adventure), and
## taken off again the moment the engine's switched off (anyone doing anything else with the bike
## switches it off: see Shed._engine_off_for).

const NODE_NAME := "Idling"
## How loud a parked bike's tickover is (dB), against a ridden one's: it's out of the helmet.
const VOLUME_DB := -4.0

var build: BikeBuild
var model: BikeModel
var beam := 0
var sound: EngineSound   # none on a headless run (nothing to hear, and the bake would only hold up the exit)
var _effects: BikeEffects


## Puts the tickover on `model` (a parked bike's, drawn from `build`) when `on`, or takes it off.
## Returns the IdlingEngine on it, or null. `beam` is its headlight switch (Shed.beam_of).
static func keep(model: BikeModel, build: BikeBuild, on: bool, beam := 0) -> IdlingEngine:
	if model == null or not is_instance_valid(model):
		return null
	var have := model.get_node_or_null(NODE_NAME) as IdlingEngine
	if not on:
		if have:
			have.free()
			model.set_lights(false, false)
		return null
	if have:
		have.beam = beam
		return have
	var idler := IdlingEngine.new()
	idler.name = NODE_NAME
	idler.build = build
	idler.model = model
	idler.beam = beam
	model.add_child(idler)
	return idler


## The tickover on a parked bike's model, or null when its engine's off.
static func of(model: BikeModel) -> IdlingEngine:
	if model == null or not is_instance_valid(model):
		return null
	return model.get_node_or_null(NODE_NAME) as IdlingEngine


func _ready() -> void:
	if build == null or model == null:
		return
	if DisplayServer.get_name() != "headless":
		sound = EngineSound.new()
		sound.volume_db = VOLUME_DB
		add_child(sound)
		sound.setup(build, model)
		sound.set_distant_filter(true)
		sound.running = true
		sound.rpm = build.idle_rpm
		sound.throttle = 0.0
	_effects = BikeEffects.new()
	add_child(_effects)
	_effects.setup(model.exhaust_tip(), Vector3(0.0, -build.rear_radius, build.wheelbase * 0.5), model.lamp_position(),
		build.headlight_lumens)


func _process(delta: float) -> void:
	if build == null or model == null:
		return
	if sound:
		# Tickover, with the small hunt an idle has to it.
		sound.rpm = build.idle_rpm * (1.0 + 0.015 * sin(Time.get_ticks_msec() * 0.0021))
		sound.throttle = 0.0
		sound.speed = 0.0
	model.set_lights(true, beam > 0, beam >= Bike.BEAM_FOG)
	_effects.update(delta, 0.0, 0.0, true, build.overall_health(), "", true, 0.0)
