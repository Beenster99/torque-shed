class_name WashMist
extends Node3D
## The wash bay filling up with mist while anyone's pressure washing in it: a soft haze hangs in
## the air, building up slowly the longer the jet's going (whoever's holding it, from the shed's
## "wash_aim", so the whole crew sees the same), then thinning away once the washing stops. Big
## faint puffs drifting about the bay, and on Forward+ with volumetric fog a fog volume as thick
## as the haze.

const FILL_TIME := 25.0       # seconds of washing for the haze to build right up
const CLEAR_TIME := 40.0      # seconds it takes to clear away after
const PUFFS := 150            # haze puffs alive at once at its thickest
const PUFF_ALPHA := 0.16      # how opaque a puff is at its thickest
const FOG_DENSITY := 0.07     # the fog volume's density at its thickest

## How thick the haze is, 0..1.
var level := 0.0
var _haze: GPUParticles3D
var _haze_mat: StandardMaterial3D
var _fog: FogVolume


func _ready() -> void:
	var c := Workshop.WASH_CENTER
	var half := Workshop.WASH_HALF
	_haze = WaterSpray.make_mist(PUFFS, 8.0, Vector2(0.7, 1.3), 1.6, 0.0)
	_haze.name = "Haze"
	_haze.position = c + Vector3(0.0, 1.35, 0.0)
	var pm := _haze.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half.x - 0.5, 1.0, half.y - 0.5)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0.0, 0.01, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	_haze_mat = (_haze.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	_haze_mat.proximity_fade_distance = 0.8
	add_child(_haze)
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return   # fog volumes need Forward+; the haze puffs carry it on the simpler renderer
	_fog = FogVolume.new()
	_fog.name = "WashFog"
	_fog.size = Vector3(half.x * 2.0, 2.9, half.y * 2.0)
	_fog.position = c + Vector3(0.0, 1.45, 0.0)
	var fm := FogMaterial.new()
	fm.density = 0.0
	fm.albedo = Color(0.88, 0.92, 0.95)
	fm.edge_fade = 0.4
	_fog.material = fm
	_fog.visible = false
	add_child(_fog)


## One frame: `washing` is whether anyone's jet is going in the bay.
func update(delta: float, washing: bool) -> void:
	if washing:
		level = minf(1.0, level + delta / FILL_TIME)
	else:
		level = maxf(0.0, level - delta / CLEAR_TIME)
	# The puffs already in the air thin with it, so it fades smoothly rather than popping.
	_haze.emitting = level > 0.02
	_haze_mat.albedo_color.a = PUFF_ALPHA * smoothstep(0.0, 1.0, level)
	if _fog:
		_fog.visible = level > 0.02
		(_fog.material as FogMaterial).density = FOG_DENSITY * level


## Whether the haze is showing at all.
func showing() -> bool:
	return level > 0.02


## Whether anyone's pressure washer jet is going in the wash bay (from the shed's state).
static func anyone_washing() -> bool:
	for j in Wash.jets():
		if Wash.reaches(j["at"]):
			return true
	return false
