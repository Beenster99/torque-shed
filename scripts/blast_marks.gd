class_name BlastMarks
extends Node
## Bare metal coming up on an engine in the sandblaster. The space round the engine is split
## into little cubes (VOXEL across), each holding how much blasting it has had; that's a 3D
## texture every part's material reads, so wherever the jet has been the old rusty, painted
## surface turns to satin metal (aluminium on the castings, bare steel on steel parts) with a
## sandblasted grain and a ragged edge, and goes dull grey and pitted where it's had too long.
## Missed bits stay rusty, so you can see them. Lives on the engine's BikeModel and turns with it.

const VOXEL := 0.02          # metres per cube of the mask
const MAX_DIM := 96
const ALUMINIUM := Color(0.8, 0.81, 0.83)
const STEEL := Color(0.6, 0.61, 0.63)
## Parts that come up as bare steel rather than aluminium.
const STEEL_SLOTS := ["oil_filter", "spark_plugs"]

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler3D mask : filter_linear, repeat_disable;
uniform mat4 to_model;
uniform vec3 mask_origin;
uniform vec3 mask_size;
uniform vec3 bare_color : source_color = vec3(0.8, 0.81, 0.83);
uniform float bare_rough = 0.42;
uniform float bare_metal = 0.9;
uniform float flash = 0.0;

varying vec3 mpos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
	// A hair proud of the surface, so it draws over the part's own finish.
	VERTEX += NORMAL * 0.0007;
	mpos = (to_model * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 uvw = (mpos - mask_origin) / mask_size;
	vec2 m = texture(mask, uvw).rg;
	// A ragged, speckled edge where the blasting stops.
	float edge = vnoise(mpos * 140.0) * 0.6 + vnoise(mpos * 40.0) * 0.4;
	float a = smoothstep(0.3, 0.8, m.r + (edge - 0.5) * 0.3);
	float grain = hash3(floor(mpos * 2200.0));
	float grain2 = vnoise(mpos * 600.0);
	vec3 col = bare_color * (0.9 + grain * 0.1 + grain2 * 0.06);
	col = mix(col, bare_color * 0.5, m.g * (0.7 + 0.3 * grain2));
	ALBEDO = col + vec3(flash * 0.5);
	METALLIC = bare_metal;
	ROUGHNESS = clamp(bare_rough + grain * 0.12 + m.g * 0.35, 0.0, 1.0);
	EMISSION = vec3(0.55, 0.75, 1.0) * flash * 1.5;
	ALPHA = a;
}
"""

static var _shader: Shader

var model: BikeModel
var origin := Vector3.ZERO       # the mask's corner, in the model's space
var dims := Vector3i.ONE
var coats := PackedFloat32Array()  # blasting each cube has had (1 is bare metal)
var _over := 4.5
var _tex: ImageTexture3D
var _bytes := PackedByteArray()
var _dirty := false
var _since_upload := 0.0
var _mats := {}                  # slot -> ShaderMaterial
var _restore := []               # [mesh, its own material] to put back when it's done
var _flash := {}                 # slot -> seconds of flash left


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## Covers the parts in `slots` of `engine_model`, and turns their materials over to the mask.
func setup(engine_model: BikeModel, slots: Array, over_level: float) -> void:
	model = engine_model
	_over = over_level
	var box := AABB()
	var first := true
	for slot in slots:
		var b := model.slot_bounds(slot)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	box = box.grow(VOXEL * 2.0)
	origin = box.position
	dims = Vector3i(clampi(ceili(box.size.x / VOXEL), 2, MAX_DIM), clampi(ceili(box.size.y / VOXEL), 2, MAX_DIM),
		clampi(ceili(box.size.z / VOXEL), 2, MAX_DIM))
	coats.resize(dims.x * dims.y * dims.z)
	coats.fill(0.0)
	_bytes.resize(coats.size() * 2)
	_bytes.fill(0)
	_tex = ImageTexture3D.new()
	_tex.create(Image.FORMAT_RG8, dims.x, dims.y, dims.z, false, _images())
	for slot in slots:
		var m := ShaderMaterial.new()
		m.shader = shader()
		m.render_priority = 1
		m.set_shader_parameter("mask", _tex)
		m.set_shader_parameter("mask_origin", origin)
		m.set_shader_parameter("mask_size", Vector3(dims) * VOXEL)
		var steel := STEEL_SLOTS.has(slot)
		var c := STEEL if steel else ALUMINIUM
		m.set_shader_parameter("bare_color", Vector3(c.r, c.g, c.b))
		m.set_shader_parameter("bare_rough", 0.5 if steel else 0.42)
		m.set_shader_parameter("bare_metal", 0.85 if steel else 0.9)
		_mats[slot] = m
		for mi in model._slot_meshes.get(slot, []):
			var g := mi as GeometryInstance3D
			if g == null or not is_instance_valid(g):
				continue
			var own := g.material_override
			if own is BaseMaterial3D:
				var mine := (own as BaseMaterial3D).duplicate() as BaseMaterial3D
				mine.next_pass = m
				_restore.append([g, own])
				g.material_override = mine
	_update_transform()


func _images() -> Array[Image]:
	var out: Array[Image] = []
	var slice := dims.x * dims.y * 2
	for z in dims.z:
		out.append(Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RG8, _bytes.slice(z * slice, (z + 1) * slice)))
	return out


func index_of(p: Vector3) -> int:
	var v := Vector3i(((p - origin) / VOXEL).floor())
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= dims.x or v.y >= dims.y or v.z >= dims.z:
		return -1
	return v.x + dims.x * (v.y + dims.y * v.z)


## Blasts a patch: the jet along `along` (model space) landing at `at`, `reach` wide. Every cube
## in the jet, from just in front of the surface to a little way into it, gets `amount` of
## blasting, less towards the edge of the jet.
func paint(at: Vector3, along: Vector3, reach: float, amount: float) -> void:
	var a := along.normalized()
	var span := reach + 0.09
	var lo := Vector3i(((at - Vector3.ONE * span - origin) / VOXEL).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((at + Vector3.ONE * span - origin) / VOXEL).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := origin + (Vector3(x, y, z) + Vector3.ONE * 0.5) * VOXEL
				var v := p - at
				var depth := v.dot(a)
				if depth < -0.045 or depth > 0.085:
					continue
				var d := (v - a * depth).length()
				if d >= reach:
					continue
				var i := x + dims.x * (y + dims.y * z)
				var c := coats[i] + amount * (1.0 - 0.6 * d / reach)
				coats[i] = c
				_bytes[i * 2] = clampi(roundi(c * 255.0), 0, 255)
				_bytes[i * 2 + 1] = clampi(roundi((c - _over) / _over * 255.0), 0, 255)
	_dirty = true


## Lights a part up for a moment: it's just come back to bare metal.
func flash_part(slot: String) -> void:
	_flash[slot] = 0.6


func _update_transform() -> void:
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return
	var inv := model.global_transform.affine_inverse()
	for slot in _mats:
		(_mats[slot] as ShaderMaterial).set_shader_parameter("to_model", Projection(inv))


func _process(delta: float) -> void:
	_update_transform()
	_since_upload += delta
	if _dirty and _since_upload >= 1.0 / 30.0:
		_dirty = false
		_since_upload = 0.0
		_tex.update(_images())
	for slot in _flash.keys():
		var left := float(_flash[slot]) - delta
		if _mats.has(slot):
			(_mats[slot] as ShaderMaterial).set_shader_parameter("flash", clampf(left / 0.6, 0.0, 1.0))
		if left <= 0.0:
			_flash.erase(slot)
		else:
			_flash[slot] = left


## Puts the parts' own materials back (the job's done or abandoned).
func restore() -> void:
	for r in _restore:
		if is_instance_valid(r[0]):
			(r[0] as GeometryInstance3D).material_override = r[1]
	_restore.clear()


## The shader material on a part (for tests).
func material_for(slot: String) -> ShaderMaterial:
	return _mats.get(slot, null)


## How many cubes show any bare metal yet (for tests).
func bare_count() -> int:
	var n := 0
	for c in coats:
		if c > 0.5:
			n += 1
	return n


func patch_count() -> int:
	return coats.size()
