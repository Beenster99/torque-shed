class_name WindowLights
extends RefCounted
## Lights in the windows of a ride's houses, flats and shops after dark. A window's glass is marked in the buildings'
## vertex colours (mark: its alpha in LOW..HIGH, a roll of its own from where it is), and the buildings' material
## (material) lights the windows whose roll is under the share lit, so a street has its own pattern. The share follows the
## clock (share): none by day, coming on as dusk falls, most at their brightest through the evening, then going off
## until only the odd one is left on deep in the night, and a few again before dawn. Daylight sets it as time passes.

## The alphas a window's glass is marked with, in the mesh's 8-bit colours (nothing else is drawn see-through in them).
const LOW := 100
const HIGH := 150
## The share of windows lit through the evening, deep in the night, and early in the morning before it's light.
const EVENING := 0.6
const NIGHT := 0.07
const EARLY := 0.2

static var _mat: ShaderMaterial
static var _share := 0.0

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform float share = 0.0;

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ROUGHNESS = 0.9;
	float a = COLOR.a * 255.0;
	if (share > 0.0 && a > %d.5 - 1.0 && a < %d.5) {
		float roll = (a - %d.0) / %d.0;
		if (roll < share) {
			float tone = fract(roll * 37.7);
			vec3 warm = mix(vec3(1.0, 0.68, 0.34), vec3(1.0, 0.84, 0.58), tone);
			vec3 col = tone > 0.86 ? vec3(0.6, 0.7, 1.0) : warm;   // (the odd one lit by a television)
			ALBEDO *= 0.3;
			EMISSION = col * mix(1.3, 2.4, fract(roll * 91.3));
		}
	}
}
"""


## `glass` marked as a window that lights up after dark, its roll (whether it's lit) from where it is, `at`.
static func mark(glass: Color, at: Vector3) -> Color:
	var k := hash(Vector3i(roundi(at.x * 10.0), roundi(at.y * 10.0), roundi(at.z * 10.0)))
	return Color(glass.r, glass.g, glass.b, float(LOW + posmod(k, HIGH - LOW + 1)) / 255.0)


## A marked window's roll, 0..1 (lit while it's under the share), or -1 when `c` isn't a window.
static func roll(c: Color) -> float:
	var a := roundi(c.a * 255.0)
	return float(a - LOW) / float(HIGH - LOW) if a >= LOW and a <= HIGH else -1.0


## The share of windows lit at `hours` (0..24) with lamps `lamps` (Daylight.lamps: 0 by day, 1 once it's dark): none
## by day, the evening's share as dusk falls, going off from late evening to the night's few, a few more before dawn.
static func share(hours: float, lamps: float) -> float:
	if lamps <= 0.0:
		return 0.0
	var h := fposmod(hours, 24.0)
	var s: float
	if h >= 12.0:
		s = lerpf(EVENING, NIGHT, smoothstep(22.0, 24.0, h))
	else:
		s = lerpf(NIGHT, EARLY, smoothstep(4.5, 6.5, h))
	return s * lamps


## The buildings' material: vertex coloured, with the lit windows.
static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER % [LOW, HIGH, LOW, HIGH - LOW]
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("share", _share)
	return _mat


## Sets the share of windows lit (Daylight, as the clock moves).
static func set_share(s: float) -> void:
	if absf(s - _share) < 0.002:
		return
	_share = s
	if _mat:
		_mat.set_shader_parameter("share", s)


static func current_share() -> float:
	return _share
