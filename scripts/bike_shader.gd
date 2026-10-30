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
## in, minus 5 for patina multiplied in, 0 for none.

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

varying vec3 tri_w;
varying vec3 tri_pos;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

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
	float layer = c2.x;
	if (layer >= 0.0) {
		albedo *= tri(kit_albedo, layer).rgb;
		rough *= tri(kit_rough, layer).r;
		NORMAL_MAP = tri(kit_normal, layer).rgb;
		NORMAL_MAP_DEPTH = c1.w;
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
	ALBEDO = albedo;
	METALLIC = c0.a;
	SPECULAR = 0.5;
	ROUGHNESS = max(rough, min_roughness);
	CLEARCOAT = c1.y;
	CLEARCOAT_ROUGHNESS = max(c1.z, min_clearcoat_roughness);
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
	return _material


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
