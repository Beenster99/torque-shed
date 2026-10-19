class_name AdventureSurface
extends RefCounted
## The road surfaces of an adventure ride: "tarmac", "gravel", "sand" and "snow". Each road
## chunk's collision body carries its surface as meta "surface" (as the town's roads do), so a
## tyre's ray finds it; AdventureWorld.surface_at(pos) answers the same for anything else.
## Also here: how each looks (the road's material and the land beside it), the dust or spray a
## tyre throws up on it. How each tyre grips on them is TyreGrip's (data/tyre_grip.json).

const IDS: Array[String] = ["tarmac", "gravel", "sand", "snow"]
const NAMES := {"tarmac": "Tarmac", "gravel": "Gravel", "sand": "Sand", "snow": "Snow"}
## The land beside each road surface (the collision meta of the terrain there).
const LAND := {"tarmac": "grass", "gravel": "grass", "sand": "sand", "snow": "snow"}
## The road's own colour, and the land's base colour beside it.
const ROAD_COLOR := {"tarmac": Color(0.17, 0.17, 0.18), "gravel": Color(0.5, 0.45, 0.38),
	"sand": Color(0.7, 0.58, 0.4), "snow": Color(0.76, 0.78, 0.83)}
const LAND_COLOR := {"tarmac": Color(0.3, 0.42, 0.18), "gravel": Color(0.36, 0.4, 0.22),
	"sand": Color(0.82, 0.7, 0.48), "snow": Color(0.9, 0.92, 0.96)}
## Second land colour, mixed in by noise for patches (heather, dune shadow, bare rock in snow).
const LAND_PATCH := {"tarmac": Color(0.42, 0.48, 0.2), "gravel": Color(0.42, 0.33, 0.28),
	"sand": Color(0.72, 0.58, 0.38), "snow": Color(0.62, 0.64, 0.66)}
const VERGE_COLOR := {"tarmac": Color(0.34, 0.38, 0.2), "gravel": Color(0.46, 0.42, 0.33),
	"sand": Color(0.74, 0.63, 0.44), "snow": Color(0.8, 0.82, 0.86)}
## How much dust (or snow spray) a tyre kicks up, relative to a dirt track, and its colour.
const DUST := {"gravel": 0.8, "sand": 1.15, "snow": 0.7}
const DUST_COLOR := {"gravel": Color(0.6, 0.55, 0.47), "sand": Color(0.8, 0.7, 0.5), "snow": Color(0.95, 0.96, 1.0)}
## Muck a kilometre of each throws up onto the bike (see Main.SURFACE_DIRT), and bumpiness (m).
const MUCK := {"gravel": 0.6, "sand": 0.45, "snow": 0.3}
const BUMP := {"gravel": 0.03, "sand": 0.02, "snow": 0.012}

static var _road_mats := {}
static var _land_mat: StandardMaterial3D
static var _line_mat: StandardMaterial3D


static func is_surface(id: String) -> bool:
	return IDS.has(id)


## The road's material for a surface: a noise-grained albedo in its colour, rougher off the tarmac.
static func road_material(surf: String) -> StandardMaterial3D:
	if _road_mats.has(surf):
		return _road_mats[surf]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var fine := {"tarmac": 0.6, "gravel": 0.28, "sand": 0.1, "snow": 0.08}
	var spread := {"tarmac": [0.75, 1.2], "gravel": [0.62, 1.35], "sand": [0.86, 1.1], "snow": [0.9, 1.06]}
	var s: Array = spread.get(surf, [0.8, 1.2])
	m.albedo_texture = noise_texture(float(fine.get(surf, 0.3)), float(s[0]), float(s[1]), hash(surf) & 0xffff)
	m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	m.roughness = {"tarmac": 0.82, "gravel": 0.95, "sand": 0.98, "snow": 0.55}.get(surf, 0.9)
	if surf == "snow":
		m.metallic_specular = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_road_mats[surf] = m
	return m


## The land's material: vertex coloured (the chunk colours it by surface, patches and slope),
## with a fine noise over it.
static func land_material() -> StandardMaterial3D:
	if _land_mat:
		return _land_mat
	_land_mat = StandardMaterial3D.new()
	_land_mat.vertex_color_use_as_albedo = true
	_land_mat.vertex_color_is_srgb = true
	_land_mat.roughness = 0.96
	_land_mat.albedo_texture = noise_texture(0.05, 0.78, 1.12, 77)
	_land_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	_land_mat.uv1_triplanar = true
	return _land_mat


## The white lines' material.
static func line_material() -> StandardMaterial3D:
	if _line_mat:
		return _line_mat
	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color(0.86, 0.86, 0.82)
	_line_mat.roughness = 0.7
	return _line_mat


## A tiling greyscale noise texture from `lo` to `hi` brightness, scaled so the brightest is
## white (the vertex colour is then the lightest the surface gets).
static func noise_texture(freq: float, lo: float, hi: float, seed_value := 1) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = freq
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(lo, lo, lo) / maxf(hi, 1.0))
	ramp.set_color(1, Color(hi, hi, hi) / maxf(hi, 1.0))
	tex.color_ramp = ramp
	tex.generate_mipmaps = true
	return tex
