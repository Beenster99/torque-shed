class_name FinishLayer
extends Node
## A bike's paintwork as detailing leaves it (see Detail), drawn on its painted panels: an extra
## pass over each painted surface of a detailed panel, region by region like its road dirt. Dull,
## swirled paint has a pale haze over it with fine swirl scratches catching the light; polished
## paint goes deep and wet-looking, with a mirror-sharp clear layer that a ceramic coat makes
## sharper still; burnt-through clear coat is a dull, chalky patch; coat residue still to buff off
## shimmers like an oil film, and a smear (residue left to flash) is a streaky grey high spot. The
## scan (X) lights up dull (amber), burnt (red) and smeared (purple) paint, the rest green.
##
## The pass goes on when the bike's drawn (BikeModel._show_shine): onto each painted material of a
## panel with a finish of its own, ahead of the dirt (DirtLayer copies it into its own copies of
## those materials, and the copies share this layer's data texture, so they all keep up). Each
## mesh carrying it is told where it sits in the bike (instance uniforms) so its regions line up.
## While someone's polishing it on their own screen (DetailJob) the job sets the regions drawn;
## the shed's own updates wait.

const NX := Dirt.NX
const NY := Dirt.NY
const W := NX * NY          # texels a facing: x = ix + iy * NX, y = the facing (and +6 for the marks)

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

const int NX = 6;
const int NY = 4;
// Per region (x = ix + iy * NX, y = facing): r gloss, g burnt, b coat, a has paint; and six rows
// down, r coat residue and g smears.
uniform sampler2D data : filter_nearest, repeat_disable;
// The scan, per mesh like the rest (DirtLayer's copies of this pass have their own uniforms).
instance uniform float scan = 0.0;
instance uniform float scan_t = 0.0;
// Where the mesh sits in the bike (rows of its transform) and its part's bounds, in the bike.
instance uniform vec4 m2m_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 m2m_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 m2m_z = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec3 box_origin = vec3(0.0);
instance uniform vec3 box_size = vec3(0.0);

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

vec4 texel(int ix, int iy, int d) {
	return texelFetch(data, ivec2(ix + iy * NX, d), 0);
}

// One facing's regions at `g` (in cells along and up), blended between the four nearest.
vec4 on_face(int d, vec2 g) {
	vec2 c = clamp(g - 0.5, vec2(0.0), vec2(float(NX - 1), float(NY - 1)));
	ivec2 i0 = ivec2(floor(c));
	ivec2 i1 = min(i0 + ivec2(1), ivec2(NX - 1, NY - 1));
	vec2 f = c - vec2(i0);
	return mix(mix(texel(i0.x, i0.y, d), texel(i1.x, i0.y, d), f.x), mix(texel(i0.x, i1.y, d), texel(i1.x, i1.y, d), f.x), f.y);
}

vec4 region(vec3 p, vec3 n, int row) {
	vec3 rel = (p - box_origin) / max(box_size, vec3(1e-4));
	vec2 g = vec2(rel.z * float(NX), rel.y * float(NY));
	vec3 n2 = n * n;
	return n2.x * on_face((n.x > 0.0 ? 0 : 1) + row, g) + n2.y * on_face((n.y > 0.0 ? 2 : 3) + row, g)
		+ n2.z * on_face((n.z > 0.0 ? 4 : 5) + row, g);
}

void vertex() {
	vec4 v = vec4(VERTEX, 1.0);
	mpos = vec3(dot(m2m_x, v), dot(m2m_y, v), dot(m2m_z, v));
	mnorm = vec3(dot(m2m_x.xyz, NORMAL), dot(m2m_y.xyz, NORMAL), dot(m2m_z.xyz, NORMAL));
	VERTEX += NORMAL * 0.0008;
}

void fragment() {
	if (box_size.x <= 0.0) {
		discard;
	}
	float l = length(mnorm);
	vec3 n = l > 1e-6 ? mnorm / l : vec3(0.0, 1.0, 0.0);
	vec4 s = region(mpos, n, 0);
	vec4 mk = region(mpos, n, 6);
	float gloss = s.r;
	float coat = s.b;
	float burn = s.g;
	vec3 v = normalize(VIEW);
	float facing = clamp(dot(NORMAL, v), 0.0, 1.0);
	// Dull and swirled: a milky haze that flattens the colour, and fine swirl marks (little
	// arcs going round, from years of washing with a dirty sponge) that catch the light most at a
	// glancing angle.
	float haze = 1.0 - smoothstep(0.3, 0.85, gloss);
	vec3 q = mpos * 24.0;
	vec3 cellp = floor(q);
	vec3 off = vec3(hash3(cellp), hash3(cellp + 3.1), hash3(cellp + 7.7));
	float ring = length(fract(q) - off);
	float arcs = smoothstep(0.9, 1.0, abs(sin(ring * 26.0 + hash3(cellp + 1.3) * 6.0))) * step(0.6, vnoise(mpos * 90.0 + 2.0));
	float scratch = smoothstep(0.86, 0.97, vnoise(vec3(mpos.x * 40.0 + mpos.y * 120.0, mpos.y * 420.0, mpos.z * 40.0 - mpos.x * 160.0)));
	float glance = 0.35 + 0.65 * pow(1.0 - facing, 2.0);
	float swirl = max(arcs * 0.7, scratch * 0.5) * glance;
	float dull_a = haze * (0.3 + 0.3 * swirl);
	// Polished: a deep, wet clear layer, sharper under a coat.
	float deep = smoothstep(0.5, 0.95, gloss);
	float clear_a = deep * (0.22 + 0.25 * pow(1.0 - facing, 3.0)) + coat * 0.12;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float rough = 0.5;
	float spec = 0.5;
	float tot = dull_a + clear_a;
	if (tot > 0.0) {
		float t = dull_a / tot;
		col = mix(vec3(0.004, 0.005, 0.007), mix(vec3(0.66, 0.66, 0.64), vec3(0.85, 0.85, 0.83), swirl), t);
		rough = mix(mix(0.03, 0.015, coat), 0.78, t);
		spec = mix(1.0, 0.2, t);
		alpha = max(dull_a, clear_a);
	}
	// Burnt through: the clear coat gone, a chalky dull patch with a ragged edge.
	float b = smoothstep(0.15, 0.45, burn * (0.55 + 0.9 * vnoise(mpos * 36.0)));
	col = mix(col, mix(vec3(0.6, 0.59, 0.56), vec3(0.72, 0.7, 0.66), vnoise(mpos * 140.0)), b);
	rough = mix(rough, 1.0, b);
	spec = mix(spec, 0.08, b);
	alpha = mix(alpha, 0.88, b);
	// Coat residue still to buff off: an oily rainbow shimmer.
	float res = mk.r;
	if (res > 0.01) {
		float ang = facing * 2.5 + vnoise(mpos * 25.0) * 1.5;
		vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + ang));
		float ra = res * (0.3 + 0.25 * vnoise(mpos * 50.0));
		col = mix(col, rainbow * 0.7, ra / max(alpha + ra, 0.001));
		rough = mix(rough, 0.12, ra);
		alpha = max(alpha, ra);
	}
	// A smear: residue that flashed, hard grey-white streaks the way it was wiped.
	float sm = mk.g;
	if (sm > 0.01) {
		float streak = vnoise(vec3(mpos.x * 14.0 + mpos.y * 30.0, mpos.y * 6.0, mpos.z * 70.0));
		float blotch = vnoise(mpos * 18.0 + 5.0);
		float sa = sm * (0.55 + 0.4 * smoothstep(0.35, 0.75, streak) * (0.5 + 0.5 * blotch));
		col = mix(col, vec3(0.78, 0.78, 0.8), sa / max(alpha + sa, 0.001));
		rough = mix(rough, 0.65, sa);
		spec = mix(spec, 0.3, sa);
		alpha = max(alpha, sa);
	}
	vec3 emit = vec3(0.0);
	if (scan > 0.0) {
		float pulse = 0.5 + 0.5 * sin(scan_t * 6.0);
		vec3 sc = vec3(0.2, 1.0, 0.5);
		float bad = 0.0;
		if (burn > 0.2) {
			sc = vec3(1.0, 0.15, 0.1);
			bad = 1.0;
		} else if (sm > 0.2 || res > 0.2) {
			sc = vec3(0.75, 0.3, 1.0);
			bad = 1.0;
		} else if (gloss < 0.8) {
			sc = vec3(1.0, 0.6, 0.1);
			bad = 1.0 - smoothstep(0.6, 0.8, gloss);
		}
		col = mix(col, sc, scan * 0.6);
		emit = sc * scan * (bad * (0.6 + 1.0 * pulse) + (1.0 - bad) * 0.08);
		alpha = max(alpha, scan * mix(0.15, 0.8, bad));
	}
	if (s.a < 0.5 && scan <= 0.0) {
		alpha *= 0.0;
	}
	if (alpha <= 0.003) {
		discard;
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.08, 1.0);   // no smoother than BikeModel.MIN_ROUGHNESS
	METALLIC = 0.0;
	SPECULAR = clamp(spec, 0.0, 1.0);
	EMISSION = emit;
}
"""

static var _shader: Shader

var model: BikeModel
var _mats := {}       # slot -> ShaderMaterial
var _images := {}     # slot -> Image (W x 12)
var _texes := {}      # slot -> ImageTexture
var _meshes := {}     # slot -> [GeometryInstance3D carrying its pass]
## Something else (a DetailJob) is setting the regions drawn; the shed's own updates wait.
var held_by_job := false
var _scan := 0.0
var _scan_on := false
var _scan_t := 0.0


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## Puts the pass on `part_model`'s detailed panels (slot -> its finish, see Detail.data).
func setup(part_model: BikeModel, finishes: Dictionary) -> void:
	model = part_model
	for slot in finishes:
		_add_slot(str(slot))
		set_finish(str(slot), finishes[slot])


## The slots carrying the pass.
func slots() -> Array:
	return _mats.keys()


## How many meshes carry the pass (for tests).
func mesh_count() -> int:
	var n := 0
	for slot in _meshes:
		n += (_meshes[slot] as Array).size()
	return n


func material_for(slot: String) -> ShaderMaterial:
	return _mats.get(slot, null)


func _add_slot(slot: String) -> void:
	if _mats.has(slot) or model == null or not is_instance_valid(model):
		return
	var box := model.slot_bounds(slot)
	if box.size == Vector3.ZERO:
		return
	var img := Image.create(W, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(Detail.BASE_GLOSS, 0, 0, 1))
	var tex := ImageTexture.create_from_image(img)
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.render_priority = 2
	m.set_shader_parameter("data", tex)
	var list := []
	var done := {}
	for mi in model._slot_meshes.get(slot, []):
		var g := mi as GeometryInstance3D
		if g == null or not is_instance_valid(g) or not (g.material_override is BaseMaterial3D):
			continue
		var own := g.material_override as BaseMaterial3D
		if not own.get_meta("paint_surface", false):
			continue
		if not done.has(own):
			done[own] = true
			# Onto the end of whatever's on the paint already (its effects, tape), unless another
			# panel sharing this material has put its own on.
			var tail: Material = own
			var mine := true
			while tail.next_pass != null:
				if tail.next_pass is ShaderMaterial and (tail.next_pass as ShaderMaterial).shader == shader():
					mine = false
					break
				tail = tail.next_pass
			if mine:
				tail.next_pass = m
		var xf := model._local_xform(g)
		g.set_instance_shader_parameter("m2m_x", Vector4(xf.basis.x.x, xf.basis.y.x, xf.basis.z.x, xf.origin.x))
		g.set_instance_shader_parameter("m2m_y", Vector4(xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y))
		g.set_instance_shader_parameter("m2m_z", Vector4(xf.basis.x.z, xf.basis.y.z, xf.basis.z.z, xf.origin.z))
		g.set_instance_shader_parameter("box_origin", box.position)
		g.set_instance_shader_parameter("box_size", Vector3(maxf(box.size.x, 1e-3), maxf(box.size.y, 1e-3), maxf(box.size.z, 1e-3)))
		list.append(g)
	if list.is_empty():
		return
	_mats[slot] = m
	_images[slot] = img
	_texes[slot] = tex
	_meshes[slot] = list


## Draws a panel's finish (channel -> PackedByteArray of Dirt.CELLS, see Detail.data).
func set_finish(slot: String, d: Dictionary) -> void:
	var img: Image = _images.get(slot)
	if img == null:
		return
	var g: PackedByteArray = d["g"]
	var b: PackedByteArray = d["b"]
	var c: PackedByteArray = d["c"]
	var r: PackedByteArray = d["r"]
	var s: PackedByteArray = d["s"]
	var u: PackedByteArray = d["u"]
	var bytes := PackedByteArray()
	bytes.resize(W * 12 * 4)
	for dd in Dirt.DIRS:
		for iy in NY:
			for ix in NX:
				var i := Dirt.index(dd, ix, iy)
				var k := (dd * W + ix + iy * NX) * 4
				bytes[k] = g[i]
				bytes[k + 1] = b[i]
				bytes[k + 2] = c[i]
				bytes[k + 3] = 255 if u[i] != 0 else 0
				var k2 := ((dd + 6) * W + ix + iy * NX) * 4
				bytes[k2] = r[i]
				bytes[k2 + 1] = s[i]
				bytes[k2 + 3] = 255
	img.set_data(W, 12, false, Image.FORMAT_RGBA8, bytes)
	(_texes[slot] as ImageTexture).update(img)


## Shows each panel's finish as the shed has it (slot -> finish); not while someone's polishing it
## here (their DetailJob draws it as it goes).
func show(finishes: Dictionary) -> void:
	if held_by_job:
		return
	for slot in finishes:
		set_finish(str(slot), finishes[slot])


## The scan: lights up what's still dull, burnt or smeared.
func set_scan(on: bool) -> void:
	_scan_on = on


func scanning() -> bool:
	return _scan_on


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("finish_layers", pt)


func _process_body(delta: float) -> void:
	var want := 1.0 if _scan_on else 0.0
	if _scan != want or _scan_on:
		_scan = move_toward(_scan, want, delta * 3.0)
		_scan_t += delta
		for slot in _meshes:
			for g in _meshes[slot]:
				if is_instance_valid(g):
					(g as GeometryInstance3D).set_instance_shader_parameter("scan", _scan)
					(g as GeometryInstance3D).set_instance_shader_parameter("scan_t", _scan_t)
