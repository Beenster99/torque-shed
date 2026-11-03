class_name RustLook
## Rust as the new bike look draws it (the Classic look keeps its flat patches, see
## BikeModel._mat): one recipe, in GLSL, shared by the bike shader that draws a ridden-past bike
## (BikeShader) and by the pass laid over a rusty part's own material in the shed (pass_for), so a
## part looks the same rusty wherever it is.
##
## Rust grows out of patches as the part's rust level rises (the same noise and the same levels
## as Classic's, so the patches sit where they always did) and each patch reads as real rust:
## bright orange at its ragged edge going to dark brown scale in the middle, grainy and pitted,
## rough and not a bit shiny, raised a little off the surface. Paint round a patch is blistered
## where the rust is lifting it, and on the sides rust runs down in streaks below the patches.
## Steel's chrome pits in brown specks rather than whole patches, aluminium (castings, alloy
## wheels, brushed alloy) grows a chalky white bloom instead, and rubber, leather, carbon and the
## plastic and fibreglass parts never rust at all. A heavily rusty part has a dull brown tarnish
## all over as well.

## Parts that never rust: rubber, fabric, leather and plastic.
const NO_RUST: Array[String] = ["saddle", "front_tyre", "rear_tyre", "tank_bag", "fairing", "number_boards"]
## Metal finishes darker than this (sRGB luminance) are steel, not aluminium (see finish_for).
const ALLOY_LUMINANCE := 0.6

## The recipe. Needs `uniform sampler2D rust_noise` (BikeShader.rust_noise) declared before it.
## rust_surface(level 1..10, finish (BikeLookNew.Finish), object position, triplanar weights)
## gives the rust's colour (sRGB, for rust_linear) and how much of the surface it covers (0..1),
## and sets how rough it is and how high it stands (about a millimetre at 1, for rust_bump).
const GLSL := "
float rust_n(vec3 p, vec3 w, float k) {
	vec3 q = p * k;
	return texture(rust_noise, q.xy).r * w.z + texture(rust_noise, q.xz).r * w.y + texture(rust_noise, q.zy).r * w.x;
}

vec4 rust_surface(float r_level, int f, vec3 p, vec3 w, out float r_rough, out float r_height) {
	r_rough = 0.9;
	r_height = 0.0;
	if (f == 6 || f == 7 || f == 8 || r_level <= 0.0) {
		return vec4(0.0);
	}
	float l = clamp(r_level / 10.0, 0.0, 1.0);
	float edge = 1.0 - l * 0.85;
	float n = rust_n(p, w, 3.0);
	float fine = rust_n(p, w, 37.0);
	float micro = rust_n(p, w, 151.0);
	// A ragged edge to each patch, and how far into it a point is.
	float nn = n + (fine - 0.5) * 0.07 + (micro - 0.5) * 0.025;
	float patch_ = smoothstep(edge - 0.025, edge + 0.015, nn);
	float deep = smoothstep(edge + 0.01, edge + 0.2, nn);
	float ring = smoothstep(edge - 0.1, edge - 0.025, nn) * (1.0 - patch_);
	// Rust that's run down the sides from the patches above, in streaks.
	float side = clamp(1.0 - w.y * 1.6, 0.0, 1.0);
	float above = max(smoothstep(edge - 0.01, edge + 0.06, rust_n(p + vec3(0.0, 0.03, 0.0), w, 3.0)),
		smoothstep(edge - 0.01, edge + 0.06, rust_n(p + vec3(0.0, 0.07, 0.0), w, 3.0)) * 0.55);
	float lines = texture(rust_noise, vec2((p.x + p.z) * 9.0, p.y * 0.6)).r;
	float streak = side * above * (1.0 - patch_) * smoothstep(0.5, 0.75, lines) * smoothstep(0.1, 0.5, l);
	vec3 fresh = vec3(0.62, 0.37, 0.2);
	vec3 mid = vec3(0.46, 0.28, 0.16);
	vec3 dark = vec3(0.25, 0.16, 0.1);
	vec3 col = mix(fresh, mid, smoothstep(0.0, 0.45, deep));
	col = mix(col, dark, smoothstep(0.4, 1.0, deep) * (0.4 + 0.6 * fine));
	col *= 0.82 + 0.36 * micro;
	float pit = smoothstep(0.7, 0.78, micro) * deep;
	col *= 1.0 - 0.6 * pit;
	float cover = patch_;
	r_rough = mix(0.82, 1.0, fine);
	r_height = patch_ * (0.35 + 0.5 * fine) + deep * micro * 0.5 - pit * 0.7;
	if (f == 3) {
		// Chrome: pitted in brown specks, the plating round them dulled.
		float soft = smoothstep(edge - 0.15, edge + 0.12, n);
		float specks = smoothstep(0.62 - soft * 0.1, 0.66 - soft * 0.1, micro * 0.75 + fine * 0.25) * soft;
		col = mix(mid, dark, micro) * 0.9;
		cover = max(specks * 0.95, soft * 0.12);
		ring = 0.0;
		r_height = specks * 0.6;
		streak *= 0.4;
	} else if (f == 4 || f == 5) {
		// Aluminium doesn't rust: it blooms with a chalky white oxide, pitting grey in the worst.
		float soft = smoothstep(edge - 0.15, edge + 0.12, n);
		float bloom = smoothstep(0.55, 0.68, micro * 0.6 + fine * 0.4) * soft;
		col = vec3(0.8, 0.79, 0.75) * (0.88 + 0.2 * micro);
		col = mix(col, vec3(0.38, 0.38, 0.37), pit);
		cover = max(bloom * 0.75, soft * 0.18);
		r_rough = 0.95;
		r_height = bloom * 0.4 - pit * 0.4;
		streak = 0.0;
		ring = 0.0;
	} else {
		// Paint lifted in blisters round the patch, rust staining through between them.
		float bub = smoothstep(0.5, 0.72, rust_n(p, w, 95.0));
		r_height += ring * bub * 1.1;
		cover = max(cover, ring * (0.15 + 0.45 * bub));
		col = mix(col, mix(vec3(0.52, 0.34, 0.21), vec3(0.37, 0.24, 0.15), bub), ring);
	}
	// Run-off below the patches, and a dull brown tarnish over a badly rusted part.
	col = mix(col, vec3(0.52, 0.33, 0.2) * (0.85 + 0.3 * micro), streak * (1.0 - cover));
	cover = max(cover, streak * 0.55);
	float tarnish = smoothstep(0.4, 1.0, l) * (f == 3 ? 0.18 : 0.12);
	if (cover < tarnish) {
		col = mix(vec3(0.42, 0.31, 0.22), col, cover / tarnish);
		cover = tarnish;
	}
	// (As sRGB colours, the way a material's own are picked: see rust_linear.)
	return vec4(clamp(col, 0.0, 1.0), clamp(cover, 0.0, 1.0));
}

// An sRGB colour as the renderer wants it: converted to linear just as it converts a material's
// own albedo colour, or not (`probe` is a source_color uniform set to 0.5 grey, see BikeShader).
vec3 rust_linear(vec3 c, vec4 probe) {
	if (probe.r > 0.4) {
		return c;
	}
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

// A surface's normal (view space) tilted by a height field `h` (metres) worked out per pixel:
// relief without a texture of its own.
vec3 rust_bump(vec3 n, vec3 pos, float h) {
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
"

## The pass drawn over a rusty part's own material in the shed (see pass_for).
const PASS_CODE := "
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D rust_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float level = 0.0;
uniform int finish = 0;
uniform vec4 srgb_probe : source_color = vec4(0.5, 0.5, 0.5, 1.0);

varying vec3 opos;
varying vec3 ow;
" + GLSL + "
bool sane(vec3 v, float top) {
	return all(greaterThanEqual(v, vec3(0.0))) && all(lessThanEqual(v, vec3(top)));
}

void vertex() {
	opos = VERTEX;
	ow = abs(NORMAL);
	ow /= max(dot(ow, vec3(1.0)), 1e-5);
	VERTEX += NORMAL * 0.0006;
}

void fragment() {
	float r;
	float h;
	vec4 c = rust_surface(level, finish, opos, ow, r, h);
	if (!(c.a > 0.004) || !sane(c.rgb, 1.0)) {
		discard;
	}
	ALBEDO = rust_linear(c.rgb, srgb_probe);
	ALPHA = clamp(c.a, 0.0, 1.0);
	ROUGHNESS = clamp(r, 0.08, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	NORMAL = rust_bump(NORMAL, VERTEX, h * 0.0008);
}
"

static var _shader: Shader
static var _passes := {}     # Vector2i(level, finish) -> ShaderMaterial


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PASS_CODE
	return _shader


## The rust level (1..10) Classic draws `rust` (0..1) at.
static func level_of(rust: float) -> int:
	return clampi(roundi(rust * 10.0), 1, 10)


## The shared pass drawing rust at `level` (1..10) on a surface of `finish` (BikeLookNew.Finish),
## or null where that finish never rusts.
static func pass_for(level: int, finish: int) -> ShaderMaterial:
	if finish in [BikeLookNew.Finish.RUBBER, BikeLookNew.Finish.LEATHER, BikeLookNew.Finish.CARBON]:
		return null
	var key := Vector2i(level, finish)
	if _passes.has(key):
		return _passes[key]
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.render_priority = 0   # under the blasting, paint and dirt passes
	m.set_shader_parameter("rust_noise", BikeShader.rust_noise())
	m.set_shader_parameter("level", float(level))
	m.set_shader_parameter("finish", finish)
	m.set_meta("rust_level", level)
	_passes[key] = m
	return m


## How rust takes to a surface of `finish` coloured `albedo`: dark "alloy" is steel (black
## or grey metal finishes), which rusts like any other; only light grey metal is aluminium.
static func finish_for(albedo: Color, finish: int) -> int:
	if finish in [BikeLookNew.Finish.ALLOY, BikeLookNew.Finish.BRUSHED] and albedo.get_luminance() < ALLOY_LUMINANCE:
		return BikeLookNew.Finish.PLAIN
	return finish


## The rust level a material's pass draws (see pass_for), or 0 if it isn't one.
static func level_in(mat: Material) -> int:
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader == _shader and _shader != null:
		return int(mat.get_meta("rust_level", 0))
	return 0
