class_name BikeShader
## The one shader the new bike look (see BikeLook) draws a bike's parts with, in place of a
## material per surface. Everything a part's surface was drawn with (its colour, metal,
## roughness and clear coat, the code-made surface texture from TextureKit, rust or faded
## patina) rides on the mesh's own vertices, so all of a bike's ordinary parts hanging from the
## same node go into one mesh and one draw (see BikeLookNew.bake). It draws each surface just
## as the StandardMaterial3D it replaces did: the same sums as Godot's own, triplanar textures
## and all.
##
## Per vertex: CUSTOM0 = albedo (sRGB) and metallic; CUSTOM1 = roughness, clear coat, clear
## coat roughness and the surface texture's depth; CUSTOM2 = the surface texture (a layer of
## the kit arrays, or -1), its repeats per metre, and the rust: its level 1..10 for rust mixed
## in, minus 5 for patina multiplied in, 0 for none; CUSTOM3 = the finish (BikeLookNew.Finish)
## and how hot an exhaust header runs there, 0..1, how worn the part is, 0..1, and the brake dust
## on it, 0..1.
##
## Each finish gets the close-up detail its StandardMaterial3D never had: the orange peel in a
## clear coat, the flakes glinting under a metallic one, chrome's faint polishing waves, a cast
## or polished alloy's grain, rubber's and leather's uneven sheen, and the straw-to-blue heat
## colours where an exhaust leaves the head. It's all small next to the part's own colour, so a
## bike reads the same from across the road.
##
## Wear and weather (M2): a worn part shows it in its own way (chipped paint down to the primer
## and the steel, dulled and pitted chrome and alloy, faded rubber, scuffed leather), brake dust
## browns the wheels by worn pads, and rain wets every bike at once (the `wet` uniform, from
## Weather): darker, glossier surfaces, most on the tops.

const SHADER := "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray kit_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray kit_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray kit_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D patina_albedo : source_color, filter_linear_mipmap, repeat_enable;
// Converted to linear the way this renderer converts a material's own albedo colour, or not:
// the vertices' sRGB colours follow suit (see to_linear).
uniform vec4 srgb_probe : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float min_roughness = 0.08;
uniform float min_clearcoat_roughness = 0.1;
uniform float grain_layer = -1.0;
uniform float wet = 0.0;

varying vec3 tri_w;
varying vec3 tri_pos;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;
varying flat float finish;
varying vec3 obj_pos;
varying float heat;
varying flat float wear;
varying flat float dust;
varying float up;

vec3 to_linear(vec3 c) {
	if (srgb_probe.r > 0.4) {
		return c;
	}
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec4 tri(sampler2DArray s, float layer) {
	vec4 o = vec4(0.0);
	o += texture(s, vec3(tri_pos.xy, layer)) * tri_w.z;
	o += texture(s, vec3(tri_pos.xz, layer)) * tri_w.y;
	o += texture(s, vec3(tri_pos.zy * vec2(-1.0, 1.0), layer)) * tri_w.x;
	return o;
}

vec4 tri2(sampler2D s) {
	vec4 o = vec4(0.0);
	o += texture(s, tri_pos.xy) * tri_w.z;
	o += texture(s, tri_pos.xz) * tri_w.y;
	o += texture(s, tri_pos.zy * vec2(-1.0, 1.0)) * tri_w.x;
	return o;
}

// The rust noise, as a smooth 0..1 pattern over the part, with `k` repeats a metre (about five
// blotches in each).
float noise(float k) {
	float n = texture(rust_noise, obj_pos.xy * k).r * tri_w.z;
	n += texture(rust_noise, obj_pos.xz * k).r * tri_w.y;
	n += texture(rust_noise, obj_pos.zy * k).r * tri_w.x;
	return n;
}

vec4 tri_at(sampler2DArray s, float layer, float k) {
	vec3 p = obj_pos * k * vec3(1.0, -1.0, 1.0);
	vec4 o = vec4(0.0);
	o += texture(s, vec3(p.xy, layer)) * tri_w.z;
	o += texture(s, vec3(p.xz, layer)) * tri_w.y;
	o += texture(s, vec3(p.zy * vec2(-1.0, 1.0), layer)) * tri_w.x;
	return o;
}

vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Steel's temper colours as it runs hotter: straw, bronze, purple, blue, then a dull grey-blue.
vec3 heat_tint(float t) {
	vec3 c = mix(vec3(0.85, 0.66, 0.32), vec3(0.62, 0.34, 0.12), smoothstep(0.25, 0.45, t));
	c = mix(c, vec3(0.38, 0.16, 0.4), smoothstep(0.45, 0.6, t));
	c = mix(c, vec3(0.12, 0.22, 0.6), smoothstep(0.6, 0.78, t));
	return mix(c, vec3(0.4, 0.42, 0.5), smoothstep(0.85, 1.0, t));
}

// BikeModel._rust_mask's ramp over the noise, in each of the three projections before they're
// blended, as the ramped texture is.
float ramp(float n, float lo, float hi) {
	return clamp((n - lo) / max(hi - lo, 0.001), 0.0, 1.0);
}

float rust_mask(float edge) {
	float lo = clamp(edge - 0.06, 0.01, 0.98);
	float hi = clamp(edge + 0.04, 0.02, 0.99);
	float m = ramp(texture(rust_noise, tri_pos.xy).r, lo, hi) * tri_w.z;
	m += ramp(texture(rust_noise, tri_pos.xz).r, lo, hi) * tri_w.y;
	m += ramp(texture(rust_noise, tri_pos.zy * vec2(-1.0, 1.0)).r, lo, hi) * tri_w.x;
	return m;
}

void vertex() {
	c0 = CUSTOM0;
	c1 = CUSTOM1;
	c2 = CUSTOM2;
	finish = CUSTOM3.x;
	heat = CUSTOM3.y;
	wear = CUSTOM3.z;
	dust = CUSTOM3.w;
	up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	obj_pos = VERTEX;
	// As Godot's own triplanar material: the texture's axes from the face's facing.
	TANGENT = normalize(vec3(0.0, 0.0, -1.0) * abs(NORMAL.x) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.y) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.z));
	BINORMAL = normalize(vec3(0.0, 1.0, 0.0) * abs(NORMAL.x) + vec3(0.0, 0.0, -1.0) * abs(NORMAL.y) + vec3(0.0, 1.0, 0.0) * abs(NORMAL.z));
	tri_w = abs(NORMAL);
	tri_w /= dot(tri_w, vec3(1.0));
	tri_pos = VERTEX * CUSTOM2.y * vec3(1.0, -1.0, 1.0);
}

void fragment() {
	vec3 albedo = to_linear(c0.rgb);
	float rough = c1.x;
	float metal = c0.a;
	float layer = c2.x;
	if (layer >= 0.0) {
		albedo *= tri(kit_albedo, layer).rgb;
		rough *= tri(kit_rough, layer).r;
		NORMAL_MAP = tri(kit_normal, layer).rgb;
		NORMAL_MAP_DEPTH = c1.w;
	}
	int f = int(round(finish));
	if (f == 1 && layer < 0.0 && grain_layer >= 0.0) {
		// Paint under a clear coat: a faint orange peel.
		NORMAL_MAP = tri_at(kit_normal, grain_layer, 25.0).rgb;
		NORMAL_MAP_DEPTH = 0.08;
	} else if (f == 2 && layer < 0.0) {
		// Metallic paint: some of the flakes are shinier than the paint round them, so they
		// glint in the light, fading out where they're smaller than a pixel.
		vec3 fp = obj_pos * 1100.0;
		vec3 r = hash3(floor(fp));
		float flake = step(0.8, r.z) * (1.0 - smoothstep(0.3, 0.8, length(fwidth(fp))));
		rough *= mix(1.0, 0.25 + r.x * 0.3, flake);
		metal = mix(metal, 1.0, flake * 0.6);
		albedo *= 1.0 + flake * (0.15 + r.y * 0.3);
	} else if (f == 3) {
		// Chrome: long faint waves left by the polishing.
		rough *= mix(0.8, 1.2, noise(1.5));
	} else if (f == 4) {
		// Cast or polished alloy: a fine uneven grain, a little patchy.
		rough *= mix(0.75, 1.3, noise(30.0));
		albedo *= mix(0.93, 1.05, noise(4.0));
	} else if (f == 5) {
		rough *= mix(0.9, 1.1, noise(2.0));
	} else if (f == 6) {
		// Rubber: blotchy, with a fine grain where it's been moulded.
		albedo *= mix(0.72, 1.2, noise(6.0));
		rough = mix(rough, 1.0, noise(20.0) * 0.5);
		if (grain_layer >= 0.0) {
			NORMAL_MAP = tri_at(kit_normal, grain_layer, 40.0).rgb;
			NORMAL_MAP_DEPTH = 0.25;
		}
	} else if (f == 7) {
		// Leather and vinyl: darker in the creases, shinier where it's been sat on.
		albedo *= mix(0.66, 1.1, noise(3.0));
		rough *= mix(0.7, 1.1, noise(9.0));
	}
	float coat = c1.y;
	float coat_rough = c1.z;
	if (wear > 0.01) {
		if (f == 1 || f == 2) {
			// Chipped paint: small flakes gone down to grey primer, the biggest to bare steel;
			// the clear coat round them scuffed dull.
			float n = noise(45.0) * 0.5 + noise(2.5) * 0.5;
			float chip = smoothstep(0.8 - wear * 0.2, 0.82 - wear * 0.2, n);
			float bare = smoothstep(0.87 - wear * 0.17, 0.89 - wear * 0.17, n);
			albedo = mix(albedo, mix(vec3(0.42, 0.42, 0.4), vec3(0.55, 0.55, 0.56), bare), chip);
			metal = mix(metal, bare, chip);
			rough = mix(rough + wear * 0.15 * noise(7.0), 0.55, chip);
			coat *= 1.0 - chip;
			coat_rough = mix(coat_rough, 0.6, wear * noise(5.0));
		} else if (f == 3 || f == 4 || f == 5) {
			// Dulled and pitted metal.
			float n = noise(25.0);
			rough = mix(rough, rough + 0.35, wear * n);
			albedo *= 1.0 - wear * 0.2 * smoothstep(0.6, 0.8, noise(60.0));
		} else if (f == 6) {
			// Rubber fades grey and goes dry.
			albedo = mix(albedo, vec3(0.1, 0.1, 0.1), wear * 0.6);
			rough = mix(rough, 1.0, wear * 0.5);
		} else if (f == 7) {
			// Leather and vinyl scuffed pale where it's rubbed.
			float rub = smoothstep(0.45, 0.75, noise(5.0)) * wear;
			albedo = mix(albedo, albedo * 1.45 + 0.03, rub);
			rough = mix(rough, 0.9, rub);
		}
	}
	if (dust > 0.01) {
		// Brake dust: a brown-grey film, thickest in patches.
		float k = dust * (0.35 + 0.45 * noise(6.0));
		albedo = mix(albedo, vec3(0.16, 0.13, 0.1), k);
		rough = mix(rough, 0.85, k);
		metal *= 1.0 - k * 0.7;
	}
	if (heat > 0.001) {
		// The temper colours where an exhaust leaves the head, blotchy at the edges.
		float t = clamp(heat + (noise(12.0) - 0.5) * 0.25, 0.0, 1.0);
		float k = smoothstep(0.05, 0.25, t);
		albedo = mix(albedo, heat_tint(t) * max(max(albedo.r, albedo.g), albedo.b), k * 0.85);
		rough = mix(rough, rough + 0.12, k);
	}
	if (c2.z != 0.0) {
		// Rust creeping in as patches (BikeModel._rust_mask's ramp over the same noise), or
		// faded patina multiplied over the paint.
		float level = abs(c2.z);
		float edge = 1.0 - level / 10.0 * 0.85;
		float mask = rust_mask(edge);
		if (c2.z > 0.0) {
			vec4 d = tri2(rust_albedo);
			albedo = mix(albedo, mix(albedo, d.rgb, d.a), mask);
		} else {
			vec4 d = tri2(patina_albedo);
			albedo = mix(albedo, mix(albedo, albedo * d.rgb, d.a), mask);
		}
	}
	if (wet > 0.01) {
		// Rain: everything glossier, porous rubber, leather and fabric darker, most on the tops
		// where it settles.
		float w = wet * mix(0.45, 1.0, clamp(up * 0.5 + 0.5, 0.0, 1.0));
		bool porous = (f == 0 && metal < 0.3) || f == 6 || f == 7;
		albedo *= porous ? 1.0 - 0.4 * w : 1.0;
		rough = mix(rough, rough * (porous ? 0.5 : 0.75), w);
		coat = max(coat, 0.6 * w);
		coat_rough = mix(coat_rough, 0.05, w);
	}
	ALBEDO = albedo;
	METALLIC = metal;
	SPECULAR = 0.5;
	ROUGHNESS = max(rough, min_roughness);
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = max(coat_rough, min_clearcoat_roughness);
}
"

static var _material: ShaderMaterial
static var _kits: Array[String] = []    # the TextureKit kinds, in the arrays' layer order


## The one material every new-look bike shares.
static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	var normals: Array[Image] = []
	var albedos: Array[Image] = []
	var roughs: Array[Image] = []
	_kits.clear()
	for kind in TextureKit.KINDS:
		var tex: Dictionary = TextureKit._texture_set(kind)
		if tex.is_empty():
			continue
		_kits.append(kind)
		normals.append(_layer(tex["normal"], Color(0.5, 0.5, 1.0)))
		albedos.append(_layer(tex.get("albedo"), Color.WHITE))
		roughs.append(_layer(tex.get("rough"), Color.WHITE))
	for pair in [["kit_normal", normals], ["kit_albedo", albedos], ["kit_rough", roughs]]:
		var arr := Texture2DArray.new()
		arr.create_from_images(pair[1])
		_material.set_shader_parameter(pair[0], arr)
	_material.set_shader_parameter("rust_noise", rust_noise())
	_material.set_shader_parameter("rust_albedo", BikeModel._rust_texture())
	_material.set_shader_parameter("patina_albedo", BikeModel._patina_texture())
	_material.set_shader_parameter("min_roughness", BikeModel.MIN_ROUGHNESS)
	_material.set_shader_parameter("min_clearcoat_roughness", BikeModel.MIN_CLEARCOAT_ROUGHNESS)
	_material.set_shader_parameter("grain_layer", float(_kits.find("grain")))
	return _material


static var _wet := 0.0

## How wet the rain has made every bike, 0..1 (see Weather).
static func set_wet(amount: float) -> void:
	if absf(amount - _wet) < 0.005:
		return
	_wet = amount
	material().set_shader_parameter("wet", amount)


## The layer of the kit arrays a TextureKit kind's textures are in, or -1.
static func kit_layer(kind: String) -> int:
	material()
	return _kits.find(kind)


## A kit texture as one layer of the arrays: RGBA8, TextureKit.SIZE square, with mipmaps;
## plain `fill` where a kind has no texture of that sort.
static func _layer(tex, fill: Color) -> Image:
	var img: Image = (tex as Texture2D).get_image() if tex is Texture2D else null
	if img != null:
		img = img.duplicate()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != TextureKit.SIZE or img.get_height() != TextureKit.SIZE:
			img.resize(TextureKit.SIZE, TextureKit.SIZE)
	else:
		img = Image.create(TextureKit.SIZE, TextureKit.SIZE, false, Image.FORMAT_RGBA8)
		img.fill(fill)
	img.generate_mipmaps()
	return img


static var _rust_noise: NoiseTexture2D

## The noise BikeModel._rust_mask ramps into its rust patches, unramped, so the shader can
## ramp it to any level itself.
static func rust_noise() -> NoiseTexture2D:
	if _rust_noise != null:
		return _rust_noise
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	_rust_noise = NoiseTexture2D.new()
	_rust_noise.width = 256
	_rust_noise.height = 256
	_rust_noise.seamless = true
	_rust_noise.noise = noise
	return _rust_noise
