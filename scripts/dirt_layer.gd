class_name DirtLayer
extends Node
## The dirt on a bike (or a loose part) drawn on it: an extra pass on every mesh of each dirty
## part that lays the part's regional dirt (Dirt) over its finish, so you can see by eye where
## it's clean and where it isn't. How it looks depends on where it is: clots and splatter of mud
## low down and wherever a tyre throws it, drawn out the way it flew, standing up off the part,
## dark and wet where it's thick and dried pale at the edges; a soft film of dust up top, thickest
## on what faces up and streaked where rain ran down it; and dead flies on the forward faces up
## front, each a dark body in a smear of guts thrown out along the airflow, some with their wings,
## among lots of little midges. Each region's level (blended smoothly between regions) sets how
## much of it there is: light dirt is a few specks and a haze, heavy dirt covers it. Fine detail
## fades into its average further off, so it never shimmers, and rain (BikeShader.set_wet) wets
## the mud and dust dark and glossy.
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
uniform mat4 to_model = mat4(1.0);
// The wash mask: how much has been washed off, per facing (a = +x, -x, +y, -y; b = +z, -z).
uniform sampler3D wash_a : filter_linear, repeat_disable;
uniform sampler3D wash_b : filter_linear, repeat_disable;
uniform vec3 mask_origin;
uniform vec3 mask_size = vec3(1.0);
uniform float has_mask = 0.0;
uniform float wet = 0.0;
// How wet the weather has made the bikes (BikeShader.set_wet): mud and dust go dark and glossy.
uniform float rain = 0.0;
uniform vec4 srgb_probe : source_color = vec4(0.5, 0.5, 0.5, 1.0);
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

// A surface's facing, or straight up where it has none (a zero normal would make NaN, which
// the glow spreads into white blobs speckled black).
vec3 facing_of(vec3 v) {
	float l = length(v);
	return l > 1e-6 ? v / l : vec3(0.0, 1.0, 0.0);
}

// Whether a colour is a real one in range: false for NaN or infinite (comparisons with NaN fail).
bool sane(vec3 v, float top) {
	return all(greaterThanEqual(v, vec3(0.0))) && all(lessThanEqual(v, vec3(top)));
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

// A smoother noise in a few octaves, for shapes that don't look like a grid.
float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.07 + vec3(3.1, 1.7, 5.3)) * 0.3 + vnoise(p * 4.13 + vec3(7.7, 2.9, 0.4)) * 0.2;
}

// The normal (view space) tilted by a height field `h` (metres) worked out per pixel, so the
// muck stands up off the part and catches the light.
vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	vec3 o = abs(det) * n - g;
	float len = length(o);
	return len > 1e-12 ? o / len : n;
}

// A dead fly in a cell of `q` (cells on a forward face, across and up): [how much of it, body,
// smear, wing] for the one in this cell, if there is one (`chance`), smeared along `dir`.
vec4 splat(vec2 q, float chance, vec2 dir, float seed) {
	vec2 ci = floor(q);
	vec3 h = vec3(hash3(vec3(ci, seed)), hash3(vec3(ci, seed + 1.3)), hash3(vec3(ci, seed + 2.9)));
	if (h.x > chance) {
		return vec4(0.0);
	}
	vec2 l = fract(q) - 0.5 - (h.yz - 0.5) * 0.4;
	float a = (h.y - 0.5) * 1.2;
	vec2 d = normalize(dir + vec2(cos(a), sin(a)) * 0.35);
	vec2 u = vec2(dot(l, d), dot(l, vec2(-d.y, d.x)));   // along the smear, across it
	float size = 0.6 + 0.6 * h.z;
	u /= size;
	float body = 1.0 - smoothstep(0.045, 0.075, length(u * vec2(0.8, 1.25)));
	// The splat: guts thrown out along the airflow in a tapering streak, ragged at the edges,
	// with a few droplets beyond it.
	float rag = vnoise(vec3(u * 40.0, seed + h.x * 9.0));
	float tail = smoothstep(-0.05, 0.02, u.x) * (1.0 - smoothstep(0.15, 0.38 + 0.1 * rag, u.x));
	float width = mix(0.12, 0.03, clamp(u.x / 0.38, 0.0, 1.0)) * (0.7 + 0.6 * rag);
	float smear = max(tail * (1.0 - smoothstep(width * 0.6, width, abs(u.y))), 1.0 - smoothstep(0.07, 0.11 + 0.03 * rag, length(u)));
	vec2 dp = u - vec2(0.3 + 0.12 * h.y, (h.z - 0.5) * 0.12);
	smear = max(smear, 1.0 - smoothstep(0.012, 0.022, length(dp)));
	// Some keep their wings: two pale glassy flecks either side.
	float wing = step(0.55, h.z) * (1.0 - smoothstep(0.02, 0.035, length((vec2(u.x + 0.01, abs(u.y) - 0.065)) * vec2(0.6, 1.0))));
	return vec4(1.0, body, smear * 0.85, wing);
}

void fragment() {
	vec3 n = facing_of(mnorm);
	vec3 cam = (to_model * INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (dot(n, cam - mpos) < 0.0) {
		n = -n;
	}
	float lvl = level_at(mpos, n);
	if (!(lvl > 0.0)) {
		lvl = 0.0;   // none, or not a number
	}
	lvl = min(lvl, 1.0);
	float washed = 0.0;
	if (has_mask > 0.5) {
		washed = clamp(washed_at((mpos - mask_origin) / mask_size, n), 0.0, 1.0);
	}
	// Washed right off by the mask (a crisp edge where the jet went), else the region's level.
	float s = lvl * (1.0 - smoothstep(0.55, 0.98, washed)) * (1.0 - 0.45 * washed);
	// Nothing to draw here (clean, not just washed, no scan): skip the rest of it. Each kind of
	// dirt below is only worked out where it shows, as most surfaces carry just the one.
	if (s <= 0.004 && scan <= 0.0 && (wet <= 0.0 || washed <= 0.15)) {
		discard;
	}
	// Which kind of dirt: flies on the forward faces up front, mud low down and underneath,
	// dust everywhere else.
	float flyw = smoothstep(0.45, 0.8, -n.z) * smoothstep(0.12, 0.4, mpos.y);
	float mudw = clamp((1.0 - smoothstep(-0.12, 0.35, mpos.y)) + smoothstep(0.2, 0.9, -n.y) * 0.6, 0.0, 1.0) * (1.0 - flyw);
	float dustw = max(0.0, 1.0 - mudw - flyw);
	float alpha = 0.0;
	vec3 col = vec3(0.0);
	float rough = 0.0;
	float height = 0.0;
	// How big a pixel is here, in metres: fine detail fades into its average before it shimmers.
	float px = length(fwidth(mpos));
	float soak = clamp(rain, 0.0, 1.0);
	if (mudw > 0.0) {
		// Mud: thrown off the tyres in clots drawn out along the bike (the way it flew), joining
		// into a crust as it builds up, with splatter round the clots and a dirty film between.
		// Thick mud stays dark and wet; thin mud and the clots' edges dry out pale and dusty.
		vec3 mp = mpos * vec3(1.0, 1.0, 0.42);
		float shape = fbm(mp * 13.0) * 0.75 + vnoise(mp * 46.0) * 0.25;
		float thr = 1.0 - s * 1.1;
		float clot = smoothstep(thr - 0.03, thr + 0.03, shape);
		float thick = smoothstep(thr, thr + 0.22, shape);
		vec3 sp = mpos * vec3(110.0, 110.0, 55.0);
		vec3 si = floor(sp);
		float near = smoothstep(thr - 0.3, thr - 0.02, shape);
		float drop = step(1.0 - s * (0.12 + 0.5 * near), hash3(si + vec3(5.0)));
		float dr = length(fract(sp) - 0.5 - (vec3(hash3(si), hash3(si + vec3(2.1)), hash3(si + vec3(4.7))) - 0.5) * 0.5);
		float speck = drop * (1.0 - smoothstep(0.16, 0.26, dr)) * (1.0 - smoothstep(0.003, 0.012, px));
		speck = max(speck, drop * 0.25 * smoothstep(0.003, 0.012, px));
		float film = smoothstep(0.03, 1.0, s) * (0.25 + 0.2 * vnoise(mpos * 8.0));
		float mud_a = max(max(clot * 0.97, speck * 0.9), film);
		float grit = vnoise(mpos * 260.0);
		float dry = clamp((1.0 - thick) * 0.7 + (1.0 - clot) * 0.5 - speck * 0.6 - soak * 0.8, 0.0, 1.0);
		vec3 wet_c = mix(vec3(0.16, 0.115, 0.075), vec3(0.26, 0.19, 0.12), vnoise(mpos * 5.0));
		vec3 dry_c = mix(vec3(0.5, 0.43, 0.34), vec3(0.6, 0.53, 0.42), grit);
		vec3 mud_c = mix(wet_c, dry_c, dry) * (0.88 + 0.24 * vnoise(mpos * 60.0));
		// Clay or peat, a little warmer or greyer from place to place.
		mud_c *= mix(vec3(1.06, 0.98, 0.9), vec3(0.95, 0.98, 1.04), vnoise(mpos * 2.0 + vec3(9.0)));
		alpha += mud_a * mudw;
		col += mud_c * mud_a * mudw;
		rough += mix(0.32, 0.95, dry) * mud_a * mudw;
		height += (thick * (0.9 + 0.5 * grit) + clot * 0.5 + speck * 0.6) * mudw;
	}
	if (dustw > 0.0) {
		// Dust: a soft pale film dulling the finish, thicker on what faces up and in patches,
		// a fine grain to it close up, and on the sides streaked where rain has run down it.
		float grain = vnoise(mpos * 95.0);
		float patchy = fbm(mpos * 7.0);
		float lie = mix(0.6, 1.3, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
		float runs = smoothstep(0.55, 0.85, vnoise(mpos * vec3(70.0, 3.0, 70.0))) * (1.0 - abs(n.y));
		float dust_a = smoothstep(0.03, 1.0, s) * (0.28 + 0.14 * grain + 0.3 * patchy) * lie * (1.0 - 0.6 * runs);
		dust_a = clamp(dust_a, 0.0, 0.92);
		vec3 dust_c = mix(vec3(0.62, 0.6, 0.56), vec3(0.72, 0.69, 0.63), grain) * mix(1.0, 0.82, soak);
		alpha += dust_a * dustw;
		col += dust_c * dust_a * dustw;
		rough += mix(1.0, 0.6, soak) * dust_a * dustw;
		height += (grain - 0.5) * 0.15 * dust_a * dustw;
	}
	if (flyw > 0.0) {
		// Flies: splats where they hit, a dark body in a smear of yellow-green and amber thrown
		// out along the airflow over the part, a few with their wings still on, and lots of
		// little midges; all on a faint greasy film that catches the light.
		vec2 q = mpos.xy;
		vec2 flow = n.xy;
		flow = dot(flow, flow) > 0.02 ? normalize(flow) : vec2(0.0, 1.0);
		vec4 big = splat(q * 26.0, s * 0.45, flow, 1.0);
		vec4 small = splat(q * 105.0 + vec2(0.37, 0.71), s * 0.65, flow, 7.0);
		float fine = smoothstep(0.008, 0.025, px);    // too small to make out from here
		float gut_t = hash3(vec3(floor(q * 26.0), 3.0));
		vec3 gut = mix(mix(vec3(0.66, 0.62, 0.3), vec3(0.62, 0.46, 0.2), gut_t), vec3(0.5, 0.16, 0.1), step(0.85, gut_t));
		float body = max(big.y, small.y * 0.9);
		float smear = max(big.z, small.z * 0.7);
		float wing = big.w;
		float haze = s * 0.16;
		float fly_a = max(max(body, smear * 0.8), max(wing * 0.5, haze));
		fly_a = mix(fly_a, max(s * 0.22, haze), fine);
		vec3 fly_c = mix(vec3(0.6, 0.57, 0.46), gut, smear);
		fly_c = mix(fly_c, vec3(0.85, 0.87, 0.9), wing * (1.0 - body));
		fly_c = mix(fly_c, vec3(0.1, 0.08, 0.06), body);
		fly_c = mix(fly_c, vec3(0.55, 0.5, 0.38), fine);
		alpha += fly_a * flyw;
		col += fly_c * fly_a * flyw;
		rough += mix(0.35, 0.55, body) * fly_a * flyw;
		height += (body * 1.4 + smear * 0.35) * (1.0 - fine) * flyw;
	}
	col /= max(alpha, 0.001);
	// (Picked as sRGB colours: converted to linear the way the renderer converts a material's own.)
	col = clamp(col, 0.0, 1.0);
	if (srgb_probe.r < 0.4) {
		col = mix(pow((col + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), col * (1.0 / 12.92), lessThan(col, vec3(0.04045)));
	}
	rough /= max(alpha, 0.001);
	alpha *= smoothstep(0.004, 0.03, s);
	float spec = 0.3;
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
	if (!sane(col, 1.0) || !sane(emit, 4.0) || !(alpha >= 0.0 && alpha <= 1.0)) {
		discard;   // never a NaN or a blinding value to the screen
	}
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = clamp(rough, 0.08, 1.0);   // no smoother than BikeModel.MIN_ROUGHNESS
	METALLIC = 0.0;
	SPECULAR = clamp(spec, 0.0, 1.0);
	EMISSION = emit;
	NORMAL = bump(NORMAL, VERTEX, height * 0.003 * (1.0 - sheen));
}
"""

static var _shader: Shader
static var _blank: ImageTexture3D

var model: BikeModel
var _mats := {}               # slot -> ShaderMaterial
var _boxes := {}              # slot -> its bounds in the model, as the regions are laid over it
var _restore := []            # [mesh, its own material]
var _covered := {}            # instance id -> true for each mesh carrying the pass
## On a baked model (one being ridden), the pass drawn over the merged pieces hanging from the
## same node as one mesh: [mesh, how many pieces it covers].
var _overlays := []
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
## Where the model was (and its fit) when the passes were last told: a parked bike's passes
## aren't touched again till it moves, so they aren't re-sent to the GPU every frame.
var _shown_xf := Transform3D()
var _shown_geo := 0
var _xf_stale := true
## Past this far from the camera the dirt isn't drawn (each dirty part costs a second draw, and
## you can't make out muck that far off); it comes back a little closer in, so it doesn't flicker.
const FAR := 30.0
const NEAR := 26.0
var _far := false
var _far_check := 0.0
var _rain := -1.0     # the weather's wetness last told to the passes


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
	m.set_shader_parameter("rain", maxf(_rain, 0.0))
	_bind_mask(m)
	_mats[slot] = m
	# Meshes of the part that share a material share its copy too (one material each, not one
	# per mesh, so the renderer has far fewer to switch between).
	var copies := {}
	var merged := {}   # node -> a baked model's merged pieces hanging from it
	for mi in model._slot_meshes.get(slot, []):
		var g := mi as GeometryInstance3D
		if g == null or not is_instance_valid(g) or g.material_override == null:
			continue
		var own := g.material_override
		if _covered.has(g.get_instance_id()):
			continue   # a mesh listed under two parts carries the first one's pass only
		_covered[g.get_instance_id()] = true
		if model.baked_piece(g) and g.get_parent() != null:
			if not merged.has(g.get_parent()):
				merged[g.get_parent()] = []
			merged[g.get_parent()].append(g)
			continue
		var mine: Material = copies.get(own)
		if mine == null:
			mine = own.duplicate() as Material
			# Over anything already drawn on top of it (bare metal, paint effects, tape), each pass
			# copied so the part's own stays as it was.
			var tail: Material = mine
			while tail.next_pass != null:
				tail.next_pass = tail.next_pass.duplicate()
				tail = tail.next_pass
			tail.next_pass = m
			copies[own] = mine
		_restore.append([g, own, mine])
		g.material_override = own if _far else mine
	# A baked model's pieces on the same node, whatever they're painted: the pass over all of
	# them is one more draw, not one each. Up close (the crew's bike riding beside you, or your
	# own) that was a draw for nearly every piece of the bike.
	var shapes := {}   # node -> the part's own shapes in the new look's meshes it shares with others
	for shape in model._slot_shapes.get(slot, []):
		if not shapes.has(shape[0]):
			shapes[shape[0]] = []
		shapes[shape[0]].append(shape[1])
	for parent in shapes:
		if not merged.has(parent):
			merged[parent] = []
	for parent in merged:
		var over := MeshInstance3D.new()
		over.name = "Dirt_" + slot
		over.mesh = BikeModel.shape_mesh(merged[parent]) if shapes.get(parent, []).is_empty() \
			else BikeLookNew.join_shapes(BikeModel.shape_mesh(merged[parent]) if not (merged[parent] as Array).is_empty() else null, shapes[parent])
		over.material_override = m
		over.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		over.visible = not _far
		(parent as Node).add_child(over)
		model.add_slot_extra(slot, over)
		_overlays.append([over, (merged[parent] as Array).size() + shapes.get(parent, []).size()])
	_xf_stale = true
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
	var n := _restore.size()
	for o in _overlays:
		n += int(o[1])
	return n


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
	# Only the cubes round the slab of jet that can be in it: a disc `reach` wide from a little
	# in front of the surface to a little way in (its corners rounded up to whole cubes).
	var lo_f := Vector3.ZERO
	var hi_f := Vector3.ZERO
	for axis in 3:
		var w := reach * sqrt(maxf(0.0, 1.0 - a[axis] * a[axis])) + voxel
		var e0 := at[axis] - a[axis] * 0.05
		var e1 := at[axis] + a[axis] * 0.1
		lo_f[axis] = minf(e0, e1) - w
		hi_f[axis] = maxf(e0, e1) + w
	var lo := Vector3i(((lo_f - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((hi_f - mask_origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
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
	var xf := model.global_transform
	var geo := model.geometry.hash()
	if not _xf_stale and xf == _shown_xf and geo == _shown_geo:
		return
	_xf_stale = false
	_shown_xf = xf
	_shown_geo = geo
	if not xf.is_finite() or is_zero_approx(xf.basis.determinant()):
		return   # a bike squashed flat or lost somewhere: keep the last good one, never NaN
	var inv := xf.affine_inverse()
	for slot in _mats:
		# A part moved by the bike's own fit (geometry mode) is read where it was drawn.
		var rest := Transform3D.IDENTITY
		if model._geo_nodes.has(slot) and model._geo_pivots.has(slot):
			rest = GeoGizmo.offset_xform(model.geometry.get(slot, {}), model._geo_pivots[slot]).affine_inverse()
		var to_model := rest * inv
		if to_model.is_finite():
			(_mats[slot] as ShaderMaterial).set_shader_parameter("to_model", Projection(to_model))


func _param(key: String, value) -> void:
	for slot in _mats:
		(_mats[slot] as ShaderMaterial).set_shader_parameter(key, value)


## Draws the dirt only when the camera is near enough to see it.
func _check_far(delta: float) -> void:
	_far_check -= delta
	if _far_check > 0.0 or model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return
	_far_check = 0.25
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(model.global_position)
	var far := d > (NEAR if _far else FAR)
	if far == _far:
		return
	_far = far
	for r in _restore:
		if not is_instance_valid(r[0]):   # a part model freed under us: check before the cast
			continue
		var g := r[0] as GeometryInstance3D
		if g:
			g.material_override = r[1] if _far else r[2]
	for o in _overlays:
		if is_instance_valid(o[0]):
			(o[0] as Node3D).visible = not _far


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("dirt_layers", pt)


func _process_body(delta: float) -> void:
	_check_far(delta)
	_update_transform()
	if absf(BikeShader._wet - _rain) > 0.01:
		_rain = BikeShader._wet
		_param("rain", _rain)
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
	for o in _overlays:
		if is_instance_valid(o[0]):
			(o[0] as Node).queue_free()
	_overlays.clear()
	_covered.clear()
	_mats.clear()
