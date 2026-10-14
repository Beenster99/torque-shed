class_name ExhaustFlame
extends Node3D
## A backfire's flame: a short orange-blue tongue out of the tail pipe and a flash of light.
## EngineSound flashes it in step with the bang.

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _mat: StandardMaterial3D
var _t := 0.0
var _len := 0.0
var _strength := 0.0


func _ready() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.3
	cone.radial_segments = 10
	cone.rings = 1
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.0)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cone
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Point the tongue out backwards (+Z is the back of the bike), base at the pipe.
	_mesh.rotation.x = PI * 0.5
	_mesh.position = Vector3(0.0, 0.0, 0.15)
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 2.5
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.0, 0.15)
	add_child(_light)
	visible = false


## Flames for a moment; `strength` 0.4 a lick, 1 a full backfire.
func flash(strength: float) -> void:
	_strength = clampf(strength, 0.2, 1.2)
	_len = 0.05 + 0.07 * _strength
	_t = _len
	visible = true
	scale = Vector3.ONE * (0.6 + 0.6 * _strength) * Vector3(1.0, 1.0, 1.0)


func is_lit() -> bool:
	return _t > 0.0


func _process(delta: float) -> void:
	if _t <= 0.0:
		return
	_t -= delta
	var f := clampf(_t / maxf(_len, 0.001), 0.0, 1.0)
	if _mat:
		_mat.albedo_color = Color(1.0, lerpf(0.4, 0.75, f), lerpf(0.2, 0.5, f * f), f * 0.9)
	if _light:
		_light.light_energy = 3.0 * _strength * f
	if _t <= 0.0:
		visible = false
