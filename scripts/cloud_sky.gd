class_name CloudSky
extends RefCounted
## The sky shader: the day-night gradient, sun and moon discs, stars, and the clouds. With the
## cloud setting (Settings.gfx_clouds) on "low" to "ultra" the clouds are raymarched through a
## real layer of sky 1.5 to 3.3 km up: lit by the sun (or the moon) with bright silver edges
## towards it and dark, heavy bases, thicker and lower in rain, drifting with the wind. "off"
## (and "low" on the compatibility renderer) keeps the old flat painted cloud layer, which is
## also what the reflections and ambient light always use (it's far cheaper there).
##
## The shader is built from one source with #defines for the quality (Daylight swaps it when the
## setting changes): Forward+ raymarches at quarter resolution ("low", 14 steps; "medium", 20 and
## drifting) or half resolution ("high", 28 steps; "ultra", 44 with finer shading towards the
## sun) and blends the result over the full-resolution sky.

static var _detail: NoiseTexture3D


## What a cloud setting turns into on this renderer: {volumetric, steps, light_steps, res
## ("half", "quarter" or "full"), wind (whether the clouds drift)}.
static func quality(setting: String, forward_plus: bool) -> Dictionary:
	if setting == "off" or (setting == "low" and not forward_plus):
		return {"volumetric": false, "steps": 0, "light_steps": 0, "res": "full", "wind": false}
	if not forward_plus:
		# The compatibility renderer has no low-resolution sky passes: fewer steps at full size.
		return {"volumetric": true, "steps": 16, "light_steps": 3, "res": "full", "wind": true}
	match setting:
		"low":
			return {"volumetric": true, "steps": 14, "light_steps": 2, "res": "quarter", "wind": false}
		"medium":
			return {"volumetric": true, "steps": 20, "light_steps": 3, "res": "quarter", "wind": true}
		"ultra":
			return {"volumetric": true, "steps": 44, "light_steps": 6, "res": "half", "wind": true}
	return {"volumetric": true, "steps": 28, "light_steps": 4, "res": "half", "wind": true}


## The shader source for `q` (from quality()).
static func shader_code(q: Dictionary) -> String:
	var head := ""
	if bool(q.get("volumetric", false)):
		head += "#define VOLUMETRIC\n#define CLOUD_STEPS %d\n#define LIGHT_STEPS %d\n" % [int(q["steps"]), int(q["light_steps"])]
		match str(q.get("res", "full")):
			"half":
				head += "#define LOWRES\n#define HALF_RES\n"
			"quarter":
				head += "#define LOWRES\n#define QUARTER_RES\n"
		if bool(q.get("wind", false)):
			head += "#define WIND\n"
	return SKY_SHADER.replace("//DEFINES", head)


static func make_shader(q: Dictionary) -> Shader:
	var sh := Shader.new()
	sh.code = shader_code(q)
	return sh


## Billowy 3D noise that breaks the clouds' edges into puffs (made once, shared).
static func detail_texture() -> NoiseTexture3D:
	if _detail == null:
		_detail = NoiseTexture3D.new()
		_detail.width = 48
		_detail.height = 48
		_detail.depth = 48
		_detail.seamless = true
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.frequency = 0.09
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		n.seed = 23
		_detail.noise = n
		_detail.invert = true
	return _detail


## Which way the wind blows the clouds, in metres a second (faster in rain).
static func wind_for(rain: float) -> Vector2:
	return Vector2(11.0, 4.5) * (1.0 + 0.8 * rain)


const SKY_SHADER := """
shader_type sky;
//DEFINES
#ifdef HALF_RES
render_mode use_half_res_pass;
#endif
#ifdef QUARTER_RES
render_mode use_quarter_res_pass;
#endif

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.76, 0.86);
uniform vec3 ground_color : source_color = vec3(0.25, 0.27, 0.25);
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.8);
uniform float sun_strength = 1.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.16);
uniform float glow_strength = 0.0;
uniform vec3 moon_dir = vec3(0.0, 0.7, -0.7);
uniform float moon_strength = 0.0;
uniform float star_strength = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.68, 0.78);
uniform float cloud_cover = 0.2;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
// The raymarched clouds: lit from the sun by day and the moon by night, heavier in rain.
uniform vec3 cloud_light_dir = vec3(0.0, 0.7, 0.7);
uniform float cloud_rain = 0.0;
uniform vec2 wind = vec2(11.0, 4.5);
uniform sampler3D cloud_detail : repeat_enable, filter_linear;

const float CLOUD_BASE = 1500.0;
const float CLOUD_TOP = 3300.0;
const float CLOUD_FAR = 30000.0;
const float SIGMA = 0.0075;

float cloud_n(vec2 uv) {
	return texture(cloud_noise, uv).r * 0.65 + texture(cloud_noise, uv * 2.9 + 0.37).r * 0.35;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 star_layer(vec3 d, float scale, float density, float seed) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c + seed);
	if (h < 1.0 - density) {
		return vec3(0.0);
	}
	vec3 jitter = vec3(hash13(c + 3.1 + seed), hash13(c + 7.7 + seed), hash13(c + 1.3 + seed)) - 0.5;
	float dist = length(fract(p) - 0.5 - jitter * 0.5);
	float bright = pow(hash13(c + 11.0 + seed), 4.0);
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.86, 0.7), hash13(c + 5.0 + seed));
	return tint * (1.0 - smoothstep(0.0, 0.32, dist)) * (0.25 + 3.0 * bright);
}

// The sky behind the clouds: gradient, dusk glow, stars, moon and sun. `flat_clouds` adds the
// painted cloud layer (the cubemap for reflections, and the "off" setting).
vec3 background(vec3 d, bool cubemap, bool flat_clouds) {
	float up = d.y;
	float sd = dot(d, normalize(sun_dir));
	vec3 col;
	if (up >= 0.0) {
		col = mix(top_color, horizon_color, exp(-up * 5.0));
	} else {
		col = mix(horizon_color * 0.85, ground_color, smoothstep(0.0, 0.12, -up));
	}
	// Dusk: a warm glow around the sun hugging the horizon, a wider haze across the sky.
	float horizon_hug = exp(-abs(up) * 7.0);
	col += glow_color * glow_strength * (pow(max(sd, 0.0), 6.0) * horizon_hug * 1.2 + pow(max(sd, 0.0), 2.0) * horizon_hug * 0.25);
	// Daytime halo around the sun.
	col += sun_color * pow(max(sd, 0.0), 120.0) * 0.6 * sun_strength;
	if (up > -0.02) {
		// Stars, fading out toward the horizon haze (not baked into reflections).
		if (!cubemap && star_strength > 0.0) {
			vec3 stars = star_layer(d, 230.0, 0.035, 0.0) + star_layer(d, 520.0, 0.03, 17.0) * 0.5;
			// A faint band of extra stars across the sky, like the milky way.
			float band = exp(-pow(dot(d, normalize(vec3(0.45, 0.25, 0.86))) * 3.5, 2.0));
			stars += star_layer(d, 700.0, 0.08 * band, 33.0) * 0.4;
			col += stars * star_strength * smoothstep(0.0, 0.25, up);
			col += vec3(0.03, 0.035, 0.06) * band * star_strength * smoothstep(0.0, 0.3, up);
		}
		// Moon: a pale disc with soft mottling, and a halo.
		vec3 md = normalize(moon_dir);
		float mcos = dot(d, md);
		if (moon_strength > 0.0) {
			float mdisc = smoothstep(0.99985, 0.99992, mcos);
			vec3 tangent = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
			vec3 bitangent = cross(tangent, md);
			vec2 muv = vec2(dot(d, tangent), dot(d, bitangent)) * 80.0;
			float mottle = texture(cloud_noise, muv + 0.5).r;
			col += vec3(0.85, 0.88, 0.95) * mdisc * (1.6 + mottle * 1.2) * moon_strength;
			col += vec3(0.25, 0.3, 0.45) * pow(max(mcos, 0.0), 400.0) * 0.5 * moon_strength;
			col += vec3(0.05, 0.06, 0.1) * pow(max(mcos, 0.0), 12.0) * moon_strength;
		}
		// Sun disc.
		float disc = smoothstep(0.99990, 0.99996, sd);
		col += sun_color * disc * 30.0 * sun_strength;
		// Flat clouds: two octaves of noise projected onto a layer overhead.
		if (flat_clouds && up > 0.0) {
			vec2 uv = d.xz / (up + 0.12) * 0.11;
			float n = cloud_n(uv);
			// More cover: the noise's lower values turn to cloud too, until it's one grey deck.
			float lo = mix(0.6, 0.12, cloud_cover);
			float dens = smoothstep(lo, lo + 0.26, n) * smoothstep(0.0, 0.18, up);
			float lit = cloud_n(uv + normalize(sun_dir.xz + vec2(0.001)) * 0.02);
			vec3 c = mix(cloud_color, cloud_shadow, clamp((lit - n) * 6.0 + 0.45, 0.0, 1.0));
			c += glow_color * glow_strength * pow(max(sd, 0.0), 4.0) * 0.8;
			c += sun_color * pow(max(sd, 0.0), 30.0) * 0.5 * sun_strength;
			col = mix(col, c, dens * 0.9);
		}
	}
	return col;
}

#ifdef VOLUMETRIC
// Henyey-Greenstein phase, scaled so even scattering is 1.
float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 0.0001), 1.5);
}

// Interleaved gradient noise: a fixed per-pixel start offset that hides the march's banding.
float ign(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// How much cloud there is at p (0..1) before the detail: the weather map's coverage times a
// height profile with rounded bases and tapering tops. Overcast turns it into a flatter deck.
float cloud_shape(vec3 p, vec2 dr, out float hfrac) {
	float h = clamp((p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE), 0.0, 1.0);
	hfrac = h;
	vec2 wp = (p.xz + dr) / 26000.0;
	float wm = texture(cloud_noise, wp).r * 0.7 + texture(cloud_noise, wp * 3.1 + vec2(0.37, 0.71)).r * 0.3;
	// A few clouds when it's clear, a broken sky when cloudy, one heavy deck in the rain.
	float lo = mix(mix(0.56, 0.4, smoothstep(0.0, 0.8, cloud_cover)), 0.06, smoothstep(0.8, 1.0, cloud_cover));
	float cov = smoothstep(lo, lo + 0.2, wm);
	float top = mix(0.35, 1.0, cov) * mix(1.0, 0.7, cloud_cover * cloud_cover);
	float prof = smoothstep(0.0, 0.07, h) * (1.0 - smoothstep(top * 0.55, top, h));
	return cov * prof;
}

float cloud_density(vec3 p, vec2 dr, bool detail, out float hfrac) {
	float d = cloud_shape(p, dr, hfrac);
	if (d <= 0.001) {
		return 0.0;
	}
	if (detail) {
		vec3 q = (p + vec3(dr.x, 0.0, dr.y) * 0.25) / 2200.0;
		float n = texture(cloud_detail, q).r;
		// Eat the edges into puffs (more so near the tops), leaving the cores solid.
		float e = (1.0 - n) * mix(0.35, 0.6, hfrac);
		d = clamp((d - e) / (1.0 - e), 0.0, 1.0);
	}
	return d * mix(1.0, 1.8, cloud_rain);
}

// March through the cloud layer: scattered light (rgb) and how much it hides behind it (a).
// `dr`: how far the wind has blown the clouds (TIME is only read in sky(): the compatibility
// renderer has no TIME in other functions).
vec4 clouds(vec3 d, vec3 cam, float jitter, vec2 dr) {
	if (d.y < 0.01) {
		return vec4(0.0);
	}
	float t0 = max(CLOUD_BASE - cam.y, 0.0) / d.y;
	if (t0 > CLOUD_FAR) {
		return vec4(0.0);
	}
	float t1 = min(max(CLOUD_TOP - cam.y, 0.0) / d.y, t0 + 9000.0);
	float dt = (t1 - t0) / float(CLOUD_STEPS);
	vec3 L = normalize(cloud_light_dir);
	float c = dot(d, L);
	// Bright silver edges looking towards the light, a little back-scatter away from it.
	float phase = mix(hg(c, 0.5), hg(c, -0.15), 0.4);
	// Dark heavy bases, a paler sky-lit top.
	vec3 amb_base = cloud_shadow * mix(0.5, 0.3, cloud_rain);
	vec3 amb_top = mix(cloud_shadow, cloud_color, 0.35) * 0.95;
	vec3 lit = cloud_color * mix(1.0, 0.45, cloud_rain);
	float T = 1.0;
	vec3 scat = vec3(0.0);
	float t = t0 + dt * jitter;
	for (int i = 0; i < CLOUD_STEPS; i++) {
		vec3 p = cam + d * t;
		float h;
		float dens = cloud_density(p, dr, true, h);
		if (dens > 0.002) {
			// Towards the sun or moon: how much cloud the light comes through to get here.
			float od = 0.0;
			float ls = 90.0;
			vec3 lp = p;
			for (int j = 0; j < LIGHT_STEPS; j++) {
				lp += L * ls;
				float hh;
				od += cloud_density(lp, dr, j < 2, hh) * ls;
				ls *= 1.8;
			}
			float beer = exp(-od * SIGMA);
			// Light bounced about inside the cloud: a softer term so the shade isn't black.
			float ms = exp(-od * SIGMA * 0.25) * 0.3;
			float powder = mix(1.0, 1.0 - exp(-od * SIGMA * 2.0), 0.5 - 0.5 * c);
			vec3 S = lit * (beer * phase + ms) * powder + mix(amb_base, amb_top, h);
			float st = exp(-dens * SIGMA * dt);
			scat += T * S * (1.0 - st);
			T *= st;
			if (T < 0.02) {
				break;
			}
		}
		t += dt;
	}
	// Far away the clouds melt into the horizon haze, and right on the horizon they go.
	float far = smoothstep(0.0, CLOUD_FAR, t0);
	scat = mix(scat, horizon_color * (1.0 - T), far * 0.7);
	float fade = (1.0 - smoothstep(CLOUD_FAR * 0.45, CLOUD_FAR, t0)) * smoothstep(0.01, 0.06, d.y);
	return vec4(scat * fade, (1.0 - T) * fade);
}
#endif

void sky() {
	vec3 d = EYEDIR;
#ifdef VOLUMETRIC
#ifdef WIND
	vec2 dr = wind * TIME;
#else
	vec2 dr = vec2(0.0);
#endif
	if (AT_CUBEMAP_PASS) {
		COLOR = background(d, true, true);
	} else {
#ifdef LOWRES
		if (AT_HALF_RES_PASS || AT_QUARTER_RES_PASS) {
			vec4 c = clouds(d, POSITION, ign(FRAGCOORD.xy), dr);
			COLOR = c.rgb;
			ALPHA = c.a;
		} else {
#ifdef HALF_RES
			vec4 c = HALF_RES_COLOR;
#else
			vec4 c = QUARTER_RES_COLOR;
#endif
			COLOR = background(d, false, false) * (1.0 - c.a) + c.rgb;
		}
#else
		vec4 c = clouds(d, POSITION, ign(FRAGCOORD.xy), dr);
		COLOR = background(d, false, false) * (1.0 - c.a) + c.rgb;
#endif
	}
#else
	COLOR = background(d, AT_CUBEMAP_PASS, true);
#endif
}
"""
