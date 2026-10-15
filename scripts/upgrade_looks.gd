class_name UpgradeLooks
extends RefCounted
## How the garage's finishes look with the options the crew chose (GarageUpgrades.OPTIONS):
## the floor, walls, lights, neon and showroom. WorkshopUpgrades puts them on the real shed
## and LookPreview on the little room on the Garage upgrades page, so both match. Every
## default is the look the finish always had.

static var _noise_cache := {}


## A seamless speckle texture (the same as Workshop._noise), kept for reuse.
static func noise(freq: float, dark: float, light: float) -> NoiseTexture2D:
	var key := "%s|%s|%s" % [freq, dark, light]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.frequency = freq * 0.1
	n.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color(light, light, light))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	tex.color_ramp = ramp
	_noise_cache[key] = tex
	return tex


static func _color(id: String, key: String, chosen: Dictionary) -> Color:
	return GarageUpgrades.choice(id, key, chosen).get("color", Color.WHITE)


## The painted epoxy floor on `m`: its colour, and the effect (flake, metallic swirl, plain gloss
## or satin) as a texture and how shiny it is.
static func epoxy_floor(m: StandardMaterial3D, chosen: Dictionary) -> void:
	var fx := GarageUpgrades.choice("epoxy", "effect", chosen)
	m.albedo_color = _color("epoxy", "colour", chosen)
	match str(fx.get("id", "flake")):
		"metallic":
			m.albedo_texture = noise(0.7, 0.72, 1.4)    # broad swirls of metal pigment
		"gloss":
			m.albedo_texture = noise(0.08, 0.96, 1.03)
		"satin":
			m.albedo_texture = noise(4.0, 0.9, 1.1)
		_:
			m.albedo_texture = noise(4.0, 0.7, 1.35)    # a fine speckled flake
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.5, 1.5, 1.5)
	m.roughness = float(fx.get("rough", 0.12))
	m.metallic = float(fx.get("metal", 0.15))


## Wall cladding: the panels on `upper`, the chequer plate on `lower`. Returns the pinstripe's
## colour (alpha 0: no stripe).
static func cladding(upper: StandardMaterial3D, lower: StandardMaterial3D, chosen: Dictionary) -> Color:
	upper.albedo_color = _color("cladding", "upper", chosen)
	upper.albedo_texture = null
	upper.roughness = 0.3
	var plate := GarageUpgrades.choice("cladding", "lower", chosen)
	lower.albedo_color = plate.get("color", Color(0.72, 0.74, 0.77))
	lower.albedo_texture = noise(6.0, 0.75, 1.15)
	lower.uv1_triplanar = true
	lower.uv1_scale = Vector3(3.0, 3.0, 3.0)
	lower.metallic = float(plate.get("metal", 0.9))
	lower.roughness = float(plate.get("rough", 0.32))
	return _color("cladding", "stripe", chosen)


## A plain material in `color` (the pinstripe, trim).
static func paint(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## The LED lighting's colour temperature.
static func led_tone(chosen: Dictionary) -> Color:
	return _color("led", "tone", chosen)


## The LED strip round the walls: its own colour, or the lights' ("Same as the lights").
static func led_strip(chosen: Dictionary) -> Color:
	if str(GarageUpgrades.choice("led", "strip", chosen).get("id", "")) == "match":
		return led_tone(chosen)
	return _color("led", "strip", chosen)


## A neon choice's glowing letters, their outline and the light it casts.
static func neon_text(c: Dictionary) -> Color:
	var col: Color = c.get("color", Color.WHITE)
	return c.get("text", Color(col.r * 3.0, col.g * 3.0, col.b * 3.0))


static func neon_edge(c: Dictionary) -> Color:
	var col: Color = c.get("color", Color.WHITE)
	return c.get("edge", col.darkened(0.25))


## A neon Label3D (and the light it throws) in a neon choice's colour.
static func neon(label: Label3D, light: Light3D, c: Dictionary) -> void:
	if label:
		label.modulate = neon_text(c)
		label.outline_modulate = neon_edge(c)
	if light:
		light.light_color = c.get("color", Color.WHITE)


## The showroom's tiled floor on `m`: two colours in a chequer (or one, for a plain gloss floor),
## at the chosen tile size.
static func showroom_floor(m: StandardMaterial3D, chosen: Dictionary) -> void:
	var tile := GarageUpgrades.choice("showroom", "floor", chosen)
	var a: Color = tile.get("color", Color(0.92, 0.92, 0.92))
	var b: Color = tile.get("b", Color(0.05, 0.05, 0.06))
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = Color.WHITE
	m.uv1_triplanar = true
	var uv := float(GarageUpgrades.choice("showroom", "tiles", chosen).get("uv", 0.83))
	m.uv1_scale = Vector3(uv, uv, uv)
	m.roughness = 0.06
	m.metallic = 0.0


## The showroom's trim (skirting) material.
static func showroom_trim(chosen: Dictionary) -> StandardMaterial3D:
	var t := GarageUpgrades.choice("showroom", "trim", chosen)
	return paint(t.get("color", Color(0.85, 0.86, 0.88)), float(t.get("metal", 1.0)), float(t.get("rough", 0.15)))


## How bright an animated effect is at time `t` (seconds), 1.0 being steady: "pulse" breathes
## slowly, "flicker" is an old neon tube that drops out now and then.
static func fx_level(fx: String, t: float, seed_value := 0.0) -> float:
	match fx:
		"pulse":
			return 0.55 + 0.45 * sin(t * 1.6 + seed_value)
		"flicker":
			var cycle := fmod(t + seed_value, 6.5)
			if cycle > 5.6 and fmod(t * 11.0, 1.0) < 0.55:
				return 0.15
			return 1.0
	return 1.0


## The colour a "rainbow" effect shows at time `t`.
static func fx_colour(t: float) -> Color:
	return Color.from_hsv(fmod(t * 0.08, 1.0), 0.85, 1.0)
