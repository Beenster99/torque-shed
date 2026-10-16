class_name TextureKit
## Small surface textures made in code, for the close-up detail on bike parts: knurled grips,
## quilted and grained seat covers, carbon fibre weave, brushed alloy, crinkle-finish engine
## cases and a radiator core. Each is a tiling normal map (some with an albedo or roughness map
## to go with it), made once and shared. They're meant for triplanar materials, so they work on
## any mesh, boxes included.

const SIZE := 128

static var _cache := {}


## Puts a texture set on `m`: "knurl", "quilt", "grain", "carbon", "brushed", "crinkle" or
## "core". `scale` is how many times it repeats per metre (larger is finer).
static func apply(m: StandardMaterial3D, kind: String, scale := -1.0, strength := 1.0) -> void:
	var tex: Dictionary = _texture_set(kind)
	# Rust or patina already patterns the surface through UV1 (its mask follows UV1's scale),
	# and the corrosion hides the fine finish anyway, so a rusty part keeps just its rust.
	if tex.is_empty() or m.detail_enabled:
		return
	m.normal_enabled = true
	m.normal_texture = tex["normal"]
	m.normal_scale = float(tex.get("depth", 1.0)) * strength
	if tex.has("albedo"):
		# The weave carries its own colour, so the tint only shades it a little.
		m.albedo_texture = tex["albedo"]
		m.albedo_color = Color.WHITE.lerp(m.albedo_color, 0.15)
	if tex.has("rough"):
		m.roughness_texture = tex["rough"]
	m.uv1_triplanar = true
	var s: float = scale if scale > 0.0 else float(tex.get("scale", 20.0))
	m.uv1_scale = Vector3(s, s, s)


## The texture set for `kind`, made the first time it's asked for.
static func _texture_set(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var tex := {}
	match kind:
		"knurl":
			# Fine diamond knurling: two sets of grooves crossing at 45 degrees.
			tex = {"normal": _normal(func(u, v): return minf(_tri(u + v, 8.0), _tri(u - v, 8.0)), 3.0), "scale": 60.0, "depth": 1.2}
		"quilt":
			# Diamond quilting: puffy cushions between stitched seams.
			tex = {"normal": _normal(func(u, v): return pow(minf(_tri(u + v, 2.0), _tri(u - v, 2.0)), 0.5), 2.5), "scale": 9.0, "depth": 1.0}
		"grain":
			# Leather grain: soft fine bumps.
			tex = {"normal": _normal(func(u, v): return _noise(u, v, 24.0, 24.0), 1.2), "scale": 8.0, "depth": 0.3}
		"carbon":
			# A 2x2 twill weave: tows over two, under two, stepped one along each row.
			var weave := func(u: float, v: float) -> float:
				var n := 8.0
				var cu := floori(u * n)
				var cv := floori(v * n)
				var over := posmod(cu + cv, 4) < 2
				var fu := fposmod(u * n, 1.0)
				var fv := fposmod(v * n, 1.0)
				return sin(PI * (fv if over else fu)) * (1.0 if over else 0.8)
			tex = {"normal": _normal(weave, 2.0), "albedo": _carbon_albedo(), "scale": 32.0, "depth": 0.35}
		"brushed":
			# Brushed alloy: long fine scratches all one way.
			tex = {"normal": _normal(func(u, v): return _noise(u, v, 2.0, 90.0), 0.8), "rough": _brushed_rough(), "scale": 5.0, "depth": 0.5}
		"crinkle":
			# Crinkle (wrinkle) finish paint: a tight random wrinkle.
			tex = {"normal": _normal(func(u, v): return absf(_noise(u, v, 30.0, 30.0) - 0.5) * 2.0, 2.0), "scale": 30.0, "depth": 0.55}
		"core":
			# A radiator core: fine vertical fins with horizontal tubes.
			tex = {"normal": _normal(func(u, v): return maxf(_tri(u, 24.0), 1.0 - _tri(v, 6.0) * 0.3), 2.5), "scale": 12.0, "depth": 1.4}
	_cache[kind] = tex
	return tex


## A triangle wave: 1 on the lines `count` times across, 0 between.
static func _tri(x: float, count: float) -> float:
	return absf(fposmod(x * count, 1.0) - 0.5) * 2.0


## Smooth value noise in 0..1 at (u, v) in 0..1, with `fx` by `fy` cells across, so it tiles.
static func _noise(u: float, v: float, fx := 24.0, fy := 24.0) -> float:
	return _value(u * fx, v * fy, int(fx), int(fy))


static func _value(x: float, y: float, px: int, py: int) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(x0, px), posmod(y0, py))
	var b := _hash(posmod(x0 + 1, px), posmod(y0, py))
	var c := _hash(posmod(x0, px), posmod(y0 + 1, py))
	var d := _hash(posmod(x0 + 1, px), posmod(y0 + 1, py))
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## A tangent-space normal map from a height function of (u, v) in 0..1, `bump` its steepness.
## Height is sampled on a wrapped grid, so the map tiles.
static func _normal(height: Callable, bump: float) -> ImageTexture:
	var h := PackedFloat32Array()
	h.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			h[y * SIZE + x] = float(height.call(float(x) / SIZE, float(y) / SIZE))
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 3)
	for y in SIZE:
		for x in SIZE:
			var dx := h[y * SIZE + (x + 1) % SIZE] - h[y * SIZE + (x - 1 + SIZE) % SIZE]
			var dy := h[((y + 1) % SIZE) * SIZE + x] - h[((y - 1 + SIZE) % SIZE) * SIZE + x]
			var n := Vector3(-dx * bump, -dy * bump, 1.0).normalized()
			var i := (y * SIZE + x) * 3
			data[i] = int((n.x * 0.5 + 0.5) * 255.0)
			data[i + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			data[i + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The carbon weave's colour: tows alternating dark and a touch lighter, so the twill shows.
static func _carbon_albedo() -> ImageTexture:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 3)
	for y in SIZE:
		for x in SIZE:
			var n := 8.0
			var over := posmod(floori(float(x) / SIZE * n) + floori(float(y) / SIZE * n), 4) < 2
			var v := 52 if over else 34
			var i := (y * SIZE + x) * 3
			data[i] = v
			data[i + 1] = v
			data[i + 2] = v + 4
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Brushed alloy's roughness: streaks of slightly rougher and smoother metal.
static func _brushed_rough() -> ImageTexture:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			data[y * SIZE + x] = int(lerpf(70.0, 140.0, _value(float(x) / SIZE * 2.0, float(y) / SIZE * 90.0, 2, 90)))
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
