class_name DirtLayer
extends Node
## The dirt on a bike (or a loose part) drawn on it: an extra pass on every mesh of each dirty
## part that lays the part's regional dirt (Dirt) over its finish, so you can see by eye where
## it's clean and where it isn't. How it looks depends on where it is: clumps and splatter of mud
## low down and wherever a tyre throws it, a dull film of dust up top, and dead flies with their
## smears on the forward faces up front. Each region's level (blended smoothly between regions)
## sets how much of it there is: light dirt is a few specks and a haze, heavy dirt covers it.
##
## While someone pressure washes it (WashJob, on their own screen) the layer also carries a wash
## mask: little cubes round the bike, each holding how much has been washed off the surfaces in it
## facing each way, so a clean stripe shows exactly where the jet went (crisper than the regions
## the shed keeps), and just washed surfaces stay glossy wet for a while. The scan (X) lights up
## what's still dirty in pulsing orange. Lives on the model and is rebuilt with it.

const VOXEL := 0.025          # metres per cube of the wash mask (bigger for a big bike, see make_mask)
const MAX_DIM := 96
const DIRS := 6
const WET_FADE := 0.05        # how fast just washed surfaces dry off, a second

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

const int NX = 6;
const int NY = 4;
uniform float cells[144];
uniform vec3 box_origin;
uniform vec3 box_size = vec3(1.0);
uniform mat4 to_model;
// The wash mask: how much has been washed off, per facing (a = +x, -x, +y, -y; b = +z, -z).
uniform sampler3D wash_a : filter_linear, repeat_disable;
uniform sampler3D wash_b : filter_linear, repeat_disable;
uniform vec3 mask_origin;
uniform vec3 mask_size = vec3(1.0);
uniform float has_mask = 0.0;
uniform float wet = 0.0;
uniform float scan = 0.0;
uniform float scan_t = 0.0;
uniform float clean_level = 0.04;

varying vec3 mpos;
varying vec3 mnorm;

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

// One facing's level at `g` (in cells along and up), blended between the four nearest.
float level_on(int d, vec2 g) {
	vec2 c = clamp(g - 0.5, vec2(0.0), vec2(float(NX - 1), float(NY - 1)));
	ivec2 i0 = ivec2(floor(c));
	ivec2 i1 = min(i0 + ivec2(1), ivec2(NX - 1, NY - 1));
	vec2 f = c - vec2(i0);
	float a = cells[(d * NY + i0.y) * NX + i0.x];
	float b = cells[(d * NY + i0.y) * NX + i1.x];
	float e = cells[(d * NY + i1.y) * NX + i0.x];
	float h = cells[(d * NY + i1.y) * NX + i1.x];
	return mix(mix(a, b, f.x), mix(e, h, f.x), f.y);
}

float level_at(vec3 p, vec3 n) {
	vec3 rel = (p - box_origin) / box_size;
	vec2 g = vec2(rel.z * float(NX), rel.y * float(NY));
	vec3 n2 = n * n;
	return n2.x * level_on(n.x > 0.0 ? 0 : 1, g) + n2.y * level_on(n.y > 0.0 ? 2 : 3, g) + n2.z * level_on(n.z > 0.0 ? 4 : 5, g);
}

float washed_at(vec3 uvw, vec3 n) {
	vec4 a = texture(wash_a, uvw);
	vec4 b = texture(wash_b, uvw);
	vec3 n2 = n * n;
	return n2.x * (n.x > 0.0 ? a.r : a.g) + n2.y * (n.y > 0.0 ? a.b : a.a) + n2.z * (n.z > 0.0 ? b.r : b.g);
}

void vertex() {
	VERTEX += NORMAL * 0.0012;
	mat4 m = to_model * MODEL_MATRIX;
	mpos = (m * vec4(VERTEX, 1.0)).xyz;
	mnorm = mat3(m) * NORMAL;
}

void fragment() {
	vec3 n = normalize(mnorm);
	vec3 cam = (to_model * INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (dot(n, cam - mpos) < 0.0) {
		n = -n;
	}
	float lvl = clamp(level_at(mpos, n), 0.0, 1.0);
	float washed = 0.0;
	if (has_mask > 0.5) {
		washed = clamp(washed_at((mpos - mask_origin) / mask_size, n), 0.0, 1.0);
	}
	// Washed right off by the mask (a crisp edge where the jet went), else the region's level.
	float s = lvl * (1.0 - smoothstep(0.55, 0.98, washed)) * (1.0 - 0.45 * washed);
	// Which kind of dirt: flies on the forward faces up front, mud low down and underneath,
	// dust everywhere else.
	float flyw = smoothstep(0.45, 0.8, -n.z) * smoothstep(0.12, 0.4, mpos.y);
	float mudw = clamp((1.0 - smoothstep(-0.12, 0.35, mpos.y)) + smoothstep(0.2, 0.9, -n.y) * 0.6, 0.0, 1.0) * (1.0 - flyw);
	float dustw = max(0.0, 1.0 - mudw - flyw);
	// Mud: clumps that join up as it gets thicker, splatter round them, a dirty haze between.
	float big = vnoise(mpos * 14.0) * 0.6 + vnoise(mpos * 37.0) * 0.4;
	float clump = smoothstep(big - 0.06, big + 0.06, s * 1.15 - 0.08);
	float speck = step(1.0 - s * 0.45, hash3(floor(mpos * 160.0)));
	float mud_a = max(max(clump * 0.95, speck * 0.85), smoothstep(0.03, 1.0, s) * 0.45);
	vec3 mud_c = mix(vec3(0.16, 0.11, 0.065), vec3(0.42, 0.33, 0.21), vnoise(mpos * 22.0 + vec3(3.1)));
	// Dust: a light dulling of the finish (a faint, slightly grainy grey film, a little thicker
	// in patches), only building to a real coat where it's heavy.
	float grain = vnoise(mpos * 95.0);
	float patchy = vnoise(mpos * 9.0);
	float dust_a = smoothstep(0.03, 1.0, s) * (0.3 + 0.15 * grain + 0.2 * patchy);
	vec3 dust_c = mix(vec3(0.47, 0.46, 0.43), vec3(0.56, 0.54, 0.5), grain);
	// Flies: dark squashed bugs, each in a yellowish smear, on a greasy haze.
	vec3 fp = mpos * 70.0;
	vec3 fi = floor(fp);
	float bug = step(1.0 - s * 0.5, hash3(fi));
	vec3 off = vec3(hash3(fi + vec3(1.7)), hash3(fi + vec3(4.3)), hash3(fi + vec3(7.9))) - 0.5;
	float r = length(fract(fp) - 0.5 - off * 0.4);
	float body = bug * (1.0 - smoothstep(0.12, 0.22, r));
	float smear = bug * (1.0 - smoothstep(0.18, 0.5, r * (0.8 + 0.4 * vnoise(mpos * 300.0))));
	float fly_a = max(max(body, smear * 0.6), s * 0.3);
	vec3 fly_c = mix(mix(vec3(0.44, 0.42, 0.36), vec3(0.62, 0.56, 0.26), smear), vec3(0.05, 0.04, 0.03), body);
	float alpha = mud_a * mudw + dust_a * dustw + fly_a * flyw;
	vec3 col = (mud_c * mud_a * mudw + dust_c * dust_a * dustw + fly_c * fly_a * flyw) / max(alpha, 0.001);
	alpha *= smoothstep(0.004, 0.03, s);
	float rough = 0.95;
	float spec = 0.25;
	// Just washed: glossy and dark with water, drying off.
	float sheen = wet * smoothstep(0.15, 0.7, washed) * (1.0 - alpha);
	col = mix(col, vec3(0.02, 0.025, 0.03), sheen);
	rough = mix(rough, 0.04, sheen);
	spec = mix(spec, 1.0, sheen);
	alpha = max(alpha, sheen * 0.3);
	vec3 emit = vec3(0.0);
	if (scan > 0.0) {
		float dirty = step(clean_level, s);
		vec3 sc = mix(vec3(0.2, 1.0, 0.5), vec3(1.0, 0.45, 0.05), dirty);
		float pulse = 0.5 + 0.5 * sin(scan_t * 6.0);
		col = mix(col, sc, scan * 0.6 * dirty);
		emit = sc * scan * (dirty * (0.8 + 1.2 * pulse) + (1.0 - dirty) * 0.06);
		alpha = max(alpha, scan * mix(0.12, 0.85, dirty));
	}
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec;
	EMISSION = emit;
}
"""

static var _shader: Shader
static var _blank: ImageTexture3D

var model: BikeModel
var _mats := {}               # slot -> ShaderMaterial
var _boxes := {}              # slot -> its bounds in the model, as the regions are laid over it
var _restore := []            # [mesh, its own material]
## Each part's regions as last set (slot -> Dirt levels), and how much of each region the wash
## mask has washed (slot -> share per cell, from WashJob), which the drawn level is evened out by.
var levels := {}
var washed_share := {}
## The wash mask (see the top): the cubes' corner, size and count, and what's been washed off
## the surfaces in each facing each way (cube i, facing d: washed[i * DIRS + d], 0..1).
var mask_origin := Vector3.ZERO
var voxel := VOXEL
var dims := Vector3i.ZERO
var washed := PackedFloat32Array()
var wet := 0.0
var _tex_a: ImageTexture3D
var _tex_b: ImageTexture3D
var _bytes_a := PackedByteArray()
var _bytes_b := PackedByteArray()
var _mask_dirty := false
var _since_upload := 0.0
var _scan := 0.0
var _scan_on := false
var _scan_t := 0.0
## Something else (a WashJob) is setting the levels drawn; the shed's own updates wait.
var held_by_job := false


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


static func _blank_tex() -> ImageTexture3D:
	if _blank == null:
		_blank = ImageTexture3D.new()
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_blank.create(Image.FORMAT_RGBA8, 1, 1, 1, false, [img])
	return _blank


## Puts the layer on `part_model` for the parts in `part_levels` (slot -> Dirt levels).
func setup(part_model: BikeModel, part_levels: Dictionary) -> void:
	model = part_model
	set_levels(part_levels)
	_update_transform()


## Sets the dirt drawn on each part (slot -> Dirt levels): parts that weren't dirty before get the
## pass now. A part that's got dirtier since it was washed loses the wash mask's detail.
func set_levels(part_levels: Dictionary) -> void:
	var dirtier := false
	for slot in part_levels:
		var l: PackedFloat32Array = part_levels[slot]
		var was: PackedFloat32Array = levels.get(slot, PackedFloat32Array())
		if was.size() == Dirt.CELLS:
			for i in Dirt.CELLS:
				if l[i] > was[i] + 0.03:
					dirtier = true
					break
		levels[slot] = l
		if not _mats.has(slot) and _any(l):
			_add_slot(str(slot))
	if dirtier and dims != Vector3i.ZERO:
		clear_mask()
	for slot in _mats:
		_push(str(slot))


static func _any(l: PackedFloat32Array) -> bool:
	for v in l:
		if v > 0.004:
			return true
	return false


## The levels drawn for a part: its regions, evened out by what the wash mask has already washed
## off (the mask shows the clean bits; the rest of each region shows as dirty as it really is).
func drawn(slot: String) -> PackedFloat32Array:
	var l: PackedFloat32Array = levels.get(slot, PackedFloat32Array())
	var share: PackedFloat32Array = washed_share.get(slot, PackedFloat32Array())
	if l.size() != Dirt.CELLS:
		l = PackedFloat32Array()
		l.resize(Dirt.CELLS)
		return l
	if share.size() != Dirt.CELLS:
		return l
	var out := l.duplicate()
	for i in Dirt.CELLS:
		out[i] = minf(1.0, l[i] / maxf(1.0 - share[i], 0.02)) if share[i] < 0.999 else 0.0
	return out


func _push(slot: String) -> void:
	var m: ShaderMaterial = _mats.get(slot)
	if m:
		m.set_shader_parameter("cells", drawn(slot))


func _add_slot(slot: String) -> void:
	if model == null or not is_instance_valid(model):
		return
	var box := model.slot_bounds(slot)
	if box.size == Vector3.ZERO:
		return
	_boxes[slot] = box
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.render_priority = 3
	m.set_shader_parameter("box_origin", box.position)
	m.set_shader_parameter("box_size", Vector3(maxf(box.size.x, 1e-3), maxf(box.size.y, 1e-3), maxf(box.size.z, 1e-3)))
	m.set_shader_parameter("clean_level", Dirt.CLEAN)
	_bind_mask(m)
	_mats[slot] = m
	for mi in model._slot_meshes.get(slot, []):
		var g := mi as GeometryInstance3D
		if g == null or not is_instance_valid(g) or g.material_override == null:
			continue
		var own := g.material_override
		var mine := own.duplicate() as Material
		# Over anything already drawn on top of it (bare metal, paint effects, tape), each pass
		# copied so the part's own stays as it was.
		var tail: Material = mine
		while tail.next_pass != null:
			tail.next_pass = tail.next_pass.duplicate()
			tail = tail.next_pass
		tail.next_pass = m
		_restore.append([g, own])
		g.material_override = mine
	_update_transform()


func _bind_mask(m: ShaderMaterial) -> void:
	var on := _tex_a != null
	m.set_shader_parameter("wash_a", _tex_a if on else _blank_tex())
	m.set_shader_parameter("wash_b", _tex_b if on else _blank_tex())
	m.set_shader_parameter("mask_origin", mask_origin)
	m.set_shader_parameter("mask_size", Vector3(dims) * voxel if on else Vector3.ONE)
	m.set_shader_parameter("has_mask", 1.0 if on else 0.0)


## The pass material on a part (for tests), or null.
func material_for(slot: String) -> ShaderMaterial:
	return _mats.get(slot, null)


## How many meshes carry the pass (for tests).
func mesh_count() -> int:
	return _restore.size()


## The part's bounds the regions are laid over (model space).
func box_of(slot: String) -> AABB:
	return _boxes.get(slot, model.slot_bounds(slot) if model != null and is_instance_valid(model) else AABB())


# ---------------------------------------------------------------------------- wash mask

## Lays out the wash mask over `box` (model space), if it isn't already.
func make_mask(box: AABB) -> void:
	if dims != Vector3i.ZERO:
		return
	voxel = maxf(VOXEL, maxf(box.size.x, maxf(box.size.y, box.size.z)) / float(MAX_DIM - 6))
	box = box.grow(voxel * 2.0)
	mask_origin = box.position
	dims = Vector3i(clampi(ceili(box.size.x / voxel), 2, MAX_DIM), clampi(ceili(box.size.y / voxel), 2, MAX_DIM),
		clampi(ceili(box.size.z / voxel), 2, MAX_DIM))
	var cubes := dims.x * dims.y * dims.z
	washed.resize(cubes * DIRS)
	washed.fill(0.0)
	_bytes_a.resize(cubes * 4)
	_bytes_a.fill(0)
	_bytes_b.resize(cubes * 4)
	_bytes_b.fill(0)
	_tex_a = ImageTexture3D.new()
	_tex_a.create(Image.FORMAT_RGBA8, dims.x, dims.y, dims.z, false, _images(_bytes_a))
	_tex_b = ImageTexture3D.new()
	_tex_b.create(Image.FORMAT_RGBA8, dims.x, dims.y, dims.z, false, _images(_bytes_b))
	for slot in _mats:
		_bind_mask(_mats[slot])


## Drops the wash mask's detail (the bike's got dirty again since).
func clear_mask() -> void:
	dims = Vector3i.ZERO
	washed = PackedFloat32Array()
	_tex_a = null
	_tex_b = null
	washed_share.clear()
	for slot in _mats:
		_bind_mask(_mats[slot])
		_push(str(slot))


func _images(bytes: PackedByteArray) -> Array[Image]:
	var out: Array[Image] = []
	var slice := dims.x * dims.y * 4
	for z in dims.z:
		out.append(Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RGBA8, bytes.slice(z * slice, (z + 1) * slice)))
	return out


## The cube a point (model space) is in, or -1 outside the mask.
func index_of(p: Vector3) -> int:
	if dims == Vector3i.ZERO:
		return -1
	var v := Vector3i(((p - mask_origin) / voxel).floor())
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= dims.x or v.y >= dims.y or v.z >= dims.z:
		return -1
	return v.x + dims.x * (v.y + dims.y * v.z)


## Washes a patch on the mask: the jet along `along` (model space) landing at `at`, `reach` wide.
## Every cube in it, from just in front of the surface to a little way in, has `amount` more
## washed off its surfaces facing back up the jet (less towards the edge, by `falloff`; none off
## a surface side on to it, see WashJob.take).
func wash(at: Vector3, along: Vector3, reach: float, amount: float, falloff := 0.5) -> void:
	if dims == Vector3i.ZERO or amount <= 0.0 or reach <= 0.0:
		return
	var a := along.normalized()
	var take := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	for axis in 3:
		var f := -a[axis]
		take[axis * 2 + (0 if f > 0.0 else 1)] = WashJob.take(absf(f))
	var span := reach + 0.1
	var lo := Vector3i(((at - Vector3.ONE * span - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((at + Vector3.ONE * span - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := mask_origin + (Vector3(x, y, z) + Vector3.ONE * 0.5) * voxel
				var v := p - at
				var depth := v.dot(a)
				if depth < -0.05 or depth > 0.1:
					continue
				var d := (v - a * depth).length()
				if d >= reach:
					continue
				var i := x + dims.x * (y + dims.y * z)
				var add := amount * (1.0 - falloff * d / reach)
				for k in DIRS:
					if take[k] > 0.0:
						washed[i * DIRS + k] = minf(1.0, washed[i * DIRS + k] + add * take[k])
				_store(i)
	_mask_dirty = true
	wet = 1.0


## Wipes the mask clean everywhere a part is (it's just been called clean: the last specks go).
func wash_all(box: AABB) -> void:
	if dims == Vector3i.ZERO:
		return
	var lo := Vector3i(((box.position - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((box.end - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := x + dims.x * (y + dims.y * z)
				for k in DIRS:
					washed[i * DIRS + k] = 1.0
				_store(i)
	_mask_dirty = true


## How much has been washed off a surface in cube `i` facing `n` (model space, outwards).
func washed_facing(i: int, n: Vector3) -> float:
	if i < 0 or washed.is_empty():
		return 0.0
	var k := i * DIRS
	return n.x * n.x * washed[k + (0 if n.x > 0.0 else 1)] + n.y * n.y * washed[k + (2 if n.y > 0.0 else 3)] \
		+ n.z * n.z * washed[k + (4 if n.z > 0.0 else 5)]


func _store(i: int) -> void:
	var k := i * DIRS
	for d in 4:
		_bytes_a[i * 4 + d] = clampi(roundi(washed[k + d] * 255.0), 0, 255)
	_bytes_b[i * 4] = clampi(roundi(washed[k + 4] * 255.0), 0, 255)
	_bytes_b[i * 4 + 1] = clampi(roundi(washed[k + 5] * 255.0), 0, 255)


## Pushes the mask to its textures now (for tests and screenshots).
func flush() -> void:
	_mask_dirty = false
	_since_upload = 0.0
	if _tex_a != null:
		_tex_a.update(_images(_bytes_a))
		_tex_b.update(_images(_bytes_b))


func set_scan(on: bool) -> void:
	_scan_on = on


func scanning() -> bool:
	return _scan_on


func _update_transform() -> void:
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return
	var inv := model.global_transform.affine_inverse()
	for slot in _mats:
		# A part moved by the bike's own fit (geometry mode) is read where it was drawn.
		var rest := Transform3D.IDENTITY
		if model._geo_nodes.has(slot) and model._geo_pivots.has(slot):
			rest = GeoGizmo.offset_xform(model.geometry.get(slot, {}), model._geo_pivots[slot]).affine_inverse()
		(_mats[slot] as ShaderMaterial).set_shader_parameter("to_model", Projection(rest * inv))


func _param(key: String, value) -> void:
	for slot in _mats:
		(_mats[slot] as ShaderMaterial).set_shader_parameter(key, value)


func _process(delta: float) -> void:
	_update_transform()
	var want := 1.0 if _scan_on else 0.0
	if _scan != want or _scan_on:
		_scan = move_toward(_scan, want, delta * 3.0)
		_scan_t += delta
		_param("scan", _scan)
		_param("scan_t", _scan_t)
	if wet > 0.0:
		wet = maxf(0.0, wet - delta * WET_FADE)
		_param("wet", wet)
	_since_upload += delta
	if _mask_dirty and _since_upload >= 1.0 / 20.0:
		flush()


## Puts the parts' own materials back.
func restore() -> void:
	for r in _restore:
		if is_instance_valid(r[0]) and (r[0] as GeometryInstance3D).material_override != r[1]:
			(r[0] as GeometryInstance3D).material_override = r[1]
	_restore.clear()
	_mats.clear()
