class_name YardLooks
extends RefCounted
## The materials the yard kit is drawn in (see YardKit): plywood and steel tread-plate decks with
## painted edges and tyre marks worn into them, painted and rusting steel, weathered timber,
## concrete, brick, straw, rubber, bus and car paint, glass, flags. Each is made once, the first
## time something needs it, and shared by every piece of kit, so a yard full of it draws in a
## handful of materials. The pictures are small and drawn here, not loaded.

static var _mats := {}
static var _grime: NoiseTexture2D


## The shared material called `key`.
static func mat(key: String) -> Material:
	if not _mats.has(key):
		_mats[key] = _make(key)
	return _mats[key]


## A material that takes its colour from the mesh (YardKit's "name@rrggbb" keys): one for every
## colour of paint.
static func _tinted(m: StandardMaterial3D) -> StandardMaterial3D:
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


static func _plain(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Triplanar, in the kit's own space, a texture every `metres`.
static func _tiled(tex: Texture2D, metres: float, color := Color.WHITE, metallic := 0.0, roughness := 0.85) -> StandardMaterial3D:
	var m := _plain(color, metallic, roughness)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	return m


## Dirt and weathering laid over a material: a soft noise multiplied in, `amount` deep.
static func _add_grime(m: StandardMaterial3D, amount: float, metres := 1.6) -> void:
	if _grime == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.035
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.52, 0.48))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		_grime = NoiseTexture2D.new()
		_grime.width = 128
		_grime.height = 128
		_grime.seamless = true
		_grime.noise = noise
		_grime.color_ramp = ramp
	m.detail_enabled = true
	m.detail_albedo = _grime
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	if not m.uv1_triplanar:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / metres
	# A mask of the grime's own picture, so how much shows varies with `amount`.
	var mask := GradientTexture2D.new()
	mask.width = 4
	mask.height = 4
	var g := Gradient.new()
	g.set_color(0, Color(amount, amount, amount))
	g.set_color(1, Color(amount, amount, amount))
	mask.gradient = g
	m.detail_mask = mask


static func _make(key: String) -> Material:
	match key:
		"ply_deck":
			return _deck_mat(_ply_deck_image(), 0.0, 0.8)
		"steel_deck":
			return _deck_mat(_tread_image(), 0.55, 0.5)
		"dirt_deck":
			return _deck_mat(_dirt_deck_image(), 0.0, 1.0)
		"ply_side":
			var m := _tiled(_tex(_grain_image(Color(0.62, 0.47, 0.3), 3, 9.0)), 1.2)
			_add_grime(m, 0.6)
			return m
		"timber":
			var m := _tiled(_tex(_grain_image(Color(0.5, 0.39, 0.27), 7, 14.0)), 0.8)
			_add_grime(m, 0.7)
			return m
		"fence_wood":
			var m := _tiled(_tex(_grain_image(Color(0.55, 0.5, 0.42), 11, 18.0)), 0.9)
			_add_grime(m, 0.8)
			return m
		"hazard":
			return _tiled(_tex(_stripes_image(Color(0.95, 0.75, 0.05), Color(0.06, 0.06, 0.06))), 0.3, Color.WHITE, 0.0, 0.6)
		"reflect_red":
			return _tiled(_tex(_stripes_image(Color(0.85, 0.08, 0.06), Color(0.95, 0.95, 0.95))), 0.5, Color.WHITE, 0.0, 0.35)
		"steel":
			var m := _plain(Color(0.42, 0.44, 0.46), 0.8, 0.45)
			_add_grime(m, 0.5)
			return m
		"galv":
			var m := _plain(Color(0.66, 0.68, 0.7), 0.85, 0.42)
			_add_grime(m, 0.35)
			return m
		"bolt":
			return _plain(Color(0.55, 0.56, 0.57), 0.9, 0.35)
		"rust":
			var m := _tiled(_tex(_speckle_image(Color(0.42, 0.2, 0.09), Color(0.24, 0.12, 0.06), 21)), 0.5, Color.WHITE, 0.3, 0.9)
			return m
		"rubber":
			return _plain(Color(0.05, 0.05, 0.05), 0.0, 0.85)
		"tread":
			return _tiled(_tex(_tread_rubber_image()), 0.25, Color.WHITE, 0.0, 0.9)
		"black":
			return _plain(Color(0.04, 0.04, 0.045), 0.2, 0.6)
		"dirt":
			var m := _tiled(_tex(_speckle_image(Color(0.44, 0.31, 0.19), Color(0.3, 0.2, 0.12), 5)), 1.5, Color.WHITE, 0.0, 1.0)
			_add_grime(m, 0.4, 3.0)
			return m
		"grass":
			return _tiled(_tex(_speckle_image(Color(0.3, 0.42, 0.16), Color(0.2, 0.3, 0.1), 31)), 0.6, Color.WHITE, 0.0, 1.0)
		"concrete":
			var m := _tiled(_tex(_speckle_image(Color(0.7, 0.7, 0.67), Color(0.58, 0.58, 0.56), 13)), 0.8, Color.WHITE, 0.0, 0.95)
			_add_grime(m, 0.55)
			return m
		"brick":
			var m := _tiled(_tex(_brick_image()), 0.45, Color.WHITE, 0.0, 0.92)
			_add_grime(m, 0.4)
			return m
		"hay":
			return _tiled(_tex(_straw_image()), 0.5, Color.WHITE, 0.0, 1.0)
		"twine":
			return _plain(Color(0.85, 0.42, 0.1), 0.0, 0.8)
		"bark":
			var m := _tiled(_tex(_bark_image()), 0.5, Color.WHITE, 0.0, 0.95)
			return m
		"log_end":
			var m := _plain(Color.WHITE, 0.0, 0.9)
			m.albedo_texture = _tex(_rings_image())
			return m
		"drum_blue", "drum_red", "drum_green":
			var c := {"drum_blue": Color(0.1, 0.28, 0.55), "drum_red": Color(0.6, 0.1, 0.07), "drum_green": Color(0.12, 0.36, 0.18)}[key] as Color
			var m := _plain(c, 0.55, 0.5)
			_add_grime(m, 0.75, 0.8)
			return m
		"car_paint":
			var m := _tiled(_tex(_rusty_paint_image(Color(0.42, 0.12, 0.1), 3)), 1.2, Color.WHITE, 0.25, 0.75)
			return m
		"glass":
			return _plain(Color(0.08, 0.1, 0.11), 0.6, 0.08)
		"glass_dirty":
			return _plain(Color(0.16, 0.18, 0.17), 0.3, 0.3)
		"chrome":
			var m := _plain(Color(0.7, 0.71, 0.72), 0.95, 0.25)
			_add_grime(m, 0.5, 0.6)
			return m
		"lamp":
			return _plain(Color(0.92, 0.9, 0.8), 0.2, 0.15)
		"amber":
			return _plain(Color(0.95, 0.5, 0.05), 0.1, 0.25)
		"tail":
			return _plain(Color(0.6, 0.04, 0.03), 0.1, 0.25)
		"interior":
			return _plain(Color(0.12, 0.11, 0.1), 0.0, 0.9)
		"bus_roof":
			var m := _plain(Color(0.72, 0.72, 0.68), 0.2, 0.7)
			_add_grime(m, 0.7, 2.0)
			return m
		"mesh_fence":
			var m := _tiled(_tex(_mesh_image(), true), 0.2, Color(0.75, 0.77, 0.8), 0.8, 0.4)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"cone":
			var m := _plain(Color(1.0, 0.36, 0.04), 0.0, 0.55)
			_add_grime(m, 0.3, 0.5)
			return m
		"reflect_white":
			return _plain(Color(0.95, 0.95, 0.95), 0.3, 0.25)
		"yellow":
			return _plain(Color(0.95, 0.72, 0.04), 0.0, 0.45)
		"cloth_check":
			var m := _plain(Color.WHITE, 0.0, 0.85)
			m.albedo_texture = _tex(_check_image())
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"paint":
			# Painted steel frames, chipped and dirty.
			var m := _tinted(_plain(Color.WHITE, 0.35, 0.55))
			_add_grime(m, 0.55)
			return m
		"bus":
			# Bus liveries: faded paint, streaked and dirty.
			return _tinted(_tiled(_tex(_faded_image()), 2.4, Color.WHITE, 0.2, 0.55))
		"cloth":
			var m := _tinted(_plain(Color.WHITE, 0.0, 0.85))
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
	return _plain(Color.MAGENTA, 0.0, 1.0)


## A ramp's deck: its pictures run across the deck (u, 0 at one edge, 1 at the other) and along
## it (v, a metre and a bit a sheet), so the painted edges, the tyre marks down the middle and
## the joins line up whatever its width.
static func _deck_mat(img: Image, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := _plain(Color.WHITE, metallic, roughness)
	m.albedo_texture = _tex(img)
	return m


static func _tex(img: Image, alpha := false) -> ImageTexture:
	if not alpha:
		img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A cheap repeatable noise, 0..1, smooth between whole-number points every `cell` pixels.
static func _vnoise(x: float, y: float, cell: float, seed_n: int, wrap_x: int, wrap_y: int) -> float:
	var gx := x / cell
	var gy := y / cell
	var ix := floori(gx)
	var iy := floori(gy)
	var fx := gx - ix
	var fy := gy - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var wx := maxi(1, roundi(wrap_x / cell))
	var wy := maxi(1, roundi(wrap_y / cell))
	var a := _hash(posmod(ix, wx), posmod(iy, wy), seed_n)
	var b := _hash(posmod(ix + 1, wx), posmod(iy, wy), seed_n)
	var c := _hash(posmod(ix, wx), posmod(iy + 1, wy), seed_n)
	var d := _hash(posmod(ix + 1, wx), posmod(iy + 1, wy), seed_n)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _hash(x: int, y: int, seed_n: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_n * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Two octaves of it.
static func _fbm(x: float, y: float, w: int, h: int, seed_n: int, cell := 16.0) -> float:
	return _vnoise(x, y, cell, seed_n, w, h) * 0.65 + _vnoise(x, y, cell * 0.25, seed_n + 1, w, h) * 0.35


## Plywood sheets with yellow painted edges, a screw line at each join and rubber worn into the
## middle where the tyres run. 128 across, 128 along (a 1.2 m sheet).
static func _ply_deck_image() -> Image:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var wood := Color(0.66, 0.5, 0.32)
	for y in h:
		for x in w:
			var grain := _vnoise(x * 0.25, y * 3.0, 4.0, 3, w, h * 12)
			var c := wood * (0.82 + 0.25 * grain)
			c = c.lerp(Color(0.35, 0.3, 0.25), 0.25 * _fbm(x, y, w, h, 4, 32.0))
			var u := float(x) / w
			# Rubber down the middle, heaviest at the centre.
			var mid := 1.0 - clampf(absf(u - 0.5) / 0.22, 0.0, 1.0)
			c = c.lerp(Color(0.12, 0.11, 0.1), mid * mid * (0.35 + 0.3 * _vnoise(x, y, 8.0, 5, w, h)))
			# Painted edges, scuffed through here and there.
			if u < 0.06 or u > 0.94:
				var scuff := _vnoise(x, y, 6.0, 6, w, h)
				c = Color(0.95, 0.74, 0.06) * (0.85 + 0.15 * scuff) if scuff > 0.28 else c
			# The join between two sheets, and its screws.
			if y < 2:
				c = c * 0.45
			elif y > 3 and y < 7 and x % 8 == 4:
				c = Color(0.25, 0.25, 0.26)
			img.set_pixel(x, y, c)
	return img


## Steel tread plate: raised diagonal lozenges, yellow and black hazard edges, worn bright and
## blackened by tyres down the middle. 128 across, 128 along.
static func _tread_image() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var c := Color(0.46, 0.47, 0.48) * (0.88 + 0.18 * _fbm(x, y, w, h, 7, 32.0))
			# Lozenges every 8 pixels, alternate ones turned the other way.
			var cx := x % 8
			var cy := y % 8
			var flip := ((x / 8) + (y / 8)) % 2 == 0
			var d := absf((cx - 3.5) + ((cy - 3.5) if flip else -(cy - 3.5)))
			var e := absf((cx - 3.5) - ((cy - 3.5) if flip else -(cy - 3.5)))
			if d < 1.2 and e < 4.5:
				c = c * 1.28
			elif d < 2.0 and e < 5.0:
				c = c * 0.7
			var mid := 1.0 - clampf(absf(u - 0.5) / 0.25, 0.0, 1.0)
			c = c.lerp(Color(0.08, 0.08, 0.08), mid * (0.3 + 0.35 * _vnoise(x, y, 8.0, 8, w, h)))
			if u < 0.07 or u > 0.93:
				var band := int(floorf((x + y) / 10.0)) % 2 == 0
				c = (Color(0.95, 0.74, 0.05) if band else Color(0.07, 0.07, 0.07)) * (0.8 + 0.2 * _vnoise(x, y, 5.0, 9, w, h))
			if y < 2:
				c = c * 0.5
			img.set_pixel(x, y, c)
	return img


## A tabletop's packed top: dirt with two tyre ruts down it and the odd stone.
static func _dirt_deck_image() -> Image:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var n := _fbm(x, y, w, h, 12, 24.0)
			var c := Color(0.46, 0.33, 0.2).lerp(Color(0.32, 0.22, 0.13), n)
			for rut in [0.42, 0.58]:
				var r := 1.0 - clampf(absf(u - rut) / 0.05, 0.0, 1.0)
				c = c.lerp(Color(0.25, 0.17, 0.1), r * 0.6)
			if _hash(x, y, 13) > 0.985:
				c = Color(0.62, 0.6, 0.55)
			img.set_pixel(x, y, c)
	return img


## Wood grain: long wavy streaks of `color` with darker lines and a knot or two.
static func _grain_image(color: Color, seed_n: int, streak: float) -> Image:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var wav := x + 3.0 * sin(y * 0.07 + seed_n)
			var line := 0.5 + 0.5 * sin(wav * TAU / streak + 2.5 * _vnoise(x, y, 16.0, seed_n, w, h))
			var c := color * (0.78 + 0.22 * line + 0.1 * _vnoise(x, y, 4.0, seed_n + 3, w, h))
			img.set_pixel(x, y, c)
	return img


## Diagonal stripes of two colours, for hazard paint and the reflective bands.
static func _stripes_image(a: Color, b: Color) -> Image:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := a if ((x + y) / 8) % 2 == 0 else b
			img.set_pixel(x, y, c * (0.9 + 0.1 * _hash(x, y, 41)))
	return img


## Speckled colour from `a` to `b`: concrete, dirt, grass, rust.
static func _speckle_image(a: Color, b: Color, seed_n: int) -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var t := _fbm(x, y, n, n, seed_n, 16.0) * 0.75 + _hash(x, y, seed_n) * 0.25
			img.set_pixel(x, y, a.lerp(b, t))
	return img


## Stretcher-bond brick: two courses of 215 x 65 mm bricks in 10 mm of mortar (0.45 m square).
static func _brick_image() -> Image:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var course := n / 6   # six courses a tile: 75 mm each
	for y in n:
		for x in n:
			var row := y / course
			var off := (n / 4) if row % 2 == 1 else 0
			var bx := (x + off) % (n / 2)
			var by := y % course
			var brick := (x + off) / (n / 2) + row * 7
			var c: Color
			if by < 2 or bx < 2:
				c = Color(0.62, 0.6, 0.56) * (0.9 + 0.1 * _hash(x, y, 51))
			else:
				var tone := _hash(brick, row, 52)
				c = Color(0.56, 0.22, 0.13).lerp(Color(0.42, 0.17, 0.1), tone)
				c = c.lerp(Color(0.6, 0.35, 0.25), 0.25 * _vnoise(x, y, 6.0, 53, n, n))
			img.set_pixel(x, y, c)
	return img


## Straw: fine lengthwise streaks in golden and pale strands.
static func _straw_image() -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var s := _vnoise(x * 6.0, y * 0.4, 4.0, 61, n * 6, n)
			var c := Color(0.86, 0.72, 0.4).lerp(Color(0.6, 0.48, 0.24), s)
			img.set_pixel(x, y, c * (0.85 + 0.25 * _hash(x, y, 62)))
	return img


## Bark: deep vertical fissures.
static func _bark_image() -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var f := _vnoise(x * 4.0, y * 0.5, 8.0, 71, n * 4, n)
			var c := Color(0.36, 0.26, 0.17).lerp(Color(0.14, 0.1, 0.07), smoothstep(0.45, 0.75, f))
			img.set_pixel(x, y, c * (0.9 + 0.2 * _hash(x, y, 72)))
	return img


## A sawn log end: growth rings round the middle and a dark bark edge.
static func _rings_image() -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var ring := 0.5 + 0.5 * sin(r * 70.0 + 3.0 * _vnoise(x, y, 8.0, 81, n, n))
			var c := Color(0.78, 0.62, 0.42) * (0.8 + 0.2 * ring)
			if r > 0.9:
				c = Color(0.25, 0.18, 0.12)
			img.set_pixel(x, y, c)
	return img


## A tyre's tread: blocks round it.
static func _tread_rubber_image() -> Image:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var groove := (x % 8 < 2) or (y % 16 < 2)
			img.set_pixel(x, y, Color(0.02, 0.02, 0.02) if groove else Color(0.07, 0.07, 0.07) * (0.9 + 0.2 * _hash(x, y, 91)))
	return img


## Faded `color` paint with rust coming through in patches, heaviest low down (v increases
## downwards, and triplanar maps the side faces' height to it).
static func _rusty_paint_image(color: Color, seed_n: int) -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := color * (0.86 + 0.14 * _fbm(x, y, n, n, seed_n, 32.0))
			var r := _fbm(x, y, n, n, seed_n + 2, 12.0)
			if r > 0.72:
				c = Color(0.4, 0.19, 0.08).lerp(Color(0.25, 0.12, 0.05), _hash(x, y, seed_n))
			elif r > 0.66:
				c = c.lerp(Color(0.45, 0.25, 0.12), 0.5)
			img.set_pixel(x, y, c)
	return img


## Faded, streaky paint in shades of white (tinted by the mesh): streaks run down (v), with
## dirt gathered in patches.
static func _faded_image() -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var streak := _vnoise(x * 3.0, y * 0.3, 8.0, 101, n * 3, n)
			var v := 0.82 + 0.14 * streak + 0.06 * _hash(x, y, 102)
			v -= 0.18 * smoothstep(0.6, 0.85, _fbm(x, y, n, n, 103, 24.0))
			img.set_pixel(x, y, Color(v, v, v * 0.97))
	return img


## Weld mesh: a square grid of wires, the rest see-through.
static func _mesh_image() -> Image:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var wire := x % 16 < 2 or y % 8 < 1
			img.set_pixel(x, y, Color(1, 1, 1, 1) if wire else Color(1, 1, 1, 0))
	return img


static func _check_image() -> Image:
	var img := Image.create(8, 6, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 6:
			img.set_pixel(x, y, Color(0.95, 0.95, 0.95) if (x + y) % 2 == 0 else Color(0.03, 0.03, 0.03))
	return img
