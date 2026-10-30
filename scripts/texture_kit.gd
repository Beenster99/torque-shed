class_name TextureKit
## Small surface textures made in code, for the close-up detail on bike parts: knurled grips,
## quilted and grained seat covers, carbon fibre weave, brushed alloy, crinkle-finish engine
## cases and a radiator core. Each is a tiling normal map (some with an albedo or roughness map
## to go with it), made once and shared. They're meant for triplanar materials, so they work on
## any mesh, boxes included.

const SIZE := 128
## Every kind of texture set apply() makes.
const KINDS: Array[String] = ["knurl", "quilt", "grain", "carbon", "brushed", "crinkle", "core"]

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


## A tangent-space normal map from a height function of (u, v) in 0..1, `bump` its steepness,
## `sx` by `sy` pixels (SIZE square unless given). Height is sampled on a wrapped grid, so the
## map tiles.
static func _normal(height: Callable, bump: float, sx := SIZE, sy := SIZE) -> ImageTexture:
	var h := PackedFloat32Array()
	h.resize(sx * sy)
	for y in sy:
		for x in sx:
			h[y * sx + x] = float(height.call(float(x) / sx, float(y) / sy))
	var data := PackedByteArray()
	data.resize(sx * sy * 3)
	for y in sy:
		for x in sx:
			var dx := h[y * sx + (x + 1) % sx] - h[y * sx + (x - 1 + sx) % sx]
			var dy := h[((y + 1) % sy) * sx + x] - h[((y - 1 + sy) % sy) * sx + x]
			var n := Vector3(-dx * bump, -dy * bump, 1.0).normalized()
			var i := (y * sx + x) * 3
			data[i] = int((n.x * 0.5 + 0.5) * 255.0)
			data[i + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			data[i + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(sx, sy, false, Image.FORMAT_RGB8, data)
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


# ---------------------------------------------------------------------------- tyre tread

## Tread patterns cut into a road tyre's crown (see BikeModel._draw_tyre), as textures on the
## tyre's own UVs (u round the tyre, v across it from bead to bead, the crown in the middle):
## a pattern -> [how many times it repeats round the tyre, what it is].
const TREADS := {
	"sport": [8, "a few long sweeping grooves, staggered side to side"],
	"touring": [14, "angled grooves with fine sipes off them, to clear water"],
	"trail": [16, "chunky staggered blocks"],
	"rib": [24, "zig-zag ribs running round the tyre"],
	"cruiser": [18, "a solid centre rib between rows of slanted blocks"],
}
## How far either side of the middle of the crown the tread reaches (in v).
const TREAD_BAND := 0.24


## Cuts tread pattern `kind` (a key of TREADS) into a tyre's material `m`: a normal map for the
## grooves' edges and a darker albedo down in them, both made once per pattern and shared by
## every tyre. The tyre's mesh needs tangents (see BikeModel.tyre_mesh).
static func apply_tread(m: StandardMaterial3D, kind: String) -> void:
	if not TREADS.has(kind):
		return
	var tex := _tread_set(kind)
	m.normal_enabled = true
	m.normal_texture = tex["normal"]
	m.normal_scale = 1.4
	m.albedo_texture = tex["albedo"]
	m.uv1_triplanar = false
	m.uv1_scale = Vector3(float(TREADS[kind][0]), 1.0, 1.0)
	m.set_meta("tread", kind)


## The normal map and albedo for tread pattern `kind`, made the first time it's asked for.
static func _tread_set(kind: String) -> Dictionary:
	var key := "tread:" + kind
	if _cache.has(key):
		return _cache[key]
	var height := func(u: float, v: float) -> float: return tread_height(kind, u, v)
	# Twice as many pixels across the tyre as round one repeat: the tread is only the middle of v.
	var w := SIZE
	var h := SIZE * 2
	var data := PackedByteArray()
	data.resize(w * h * 3)
	for y in h:
		for x in w:
			var c := int(lerpf(0.3, 1.0, tread_height(kind, float(x) / w, float(y) / h)) * 255.0)
			var i := (y * w + x) * 3
			data[i] = c
			data[i + 1] = c
			data[i + 2] = c
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	var tex := {"normal": _normal(height, 6.0, w, h), "albedo": ImageTexture.create_from_image(img)}
	_cache[key] = tex
	return tex


## The rubber's height at (u, v) on one repeat of tread pattern `kind`: 1 on the surface, 0 at
## the bottom of a groove. Outside the crown (more than TREAD_BAND from the middle) it's all
## surface, so the sidewalls stay smooth.
static func tread_height(kind: String, u: float, v: float) -> float:
	var y := v - 0.5          # across the crown, 0 in the middle
	var ay := absf(y)
	if ay > TREAD_BAND:
		return 1.0
	var side := 1.0 if y >= 0.0 else -1.0
	var d := INF              # how far outside the nearest groove (less than 0 in it)
	match kind:
		"sport":
			# One long groove each side per repeat, sweeping out from near the middle to the
			# shoulder, the right side half a repeat behind the left.
			var u0 := 0.0 if side > 0.0 else 0.5
			d = _seg_dist(u, ay, u0, 0.05, u0 + 0.42, 0.22) - 0.012
		"touring":
			var u0 := 0.0 if side > 0.0 else 0.5
			d = _seg_dist(u, ay, u0, 0.03, u0 + 0.5, 0.21) - 0.011
			# Fine sipes between the grooves.
			d = minf(d, _seg_dist(u, ay, u0 + 0.5, 0.13, u0 + 0.7, 0.2) - 0.005)
			d = minf(d, _seg_dist(u, ay, u0 + 0.3, 0.09, u0 + 0.42, 0.13) - 0.004)
		"trail":
			# Blocks in three rows: a centre row broken twice a repeat, and staggered side rows.
			d = absf(ay - 0.075) - 0.012
			if ay < 0.075:
				d = minf(d, minf(_wrap_dist(u, 0.0), _wrap_dist(u, 0.5)) * 0.3 - 0.012)
			else:
				var at := 0.25 if side > 0.0 else 0.75
				d = minf(d, _seg_dist(u, ay, at, 0.075, at + 0.06, 0.24) - 0.014)
				d = minf(d, _seg_dist(u, ay, at + 0.5, 0.075, at + 0.56, 0.24) - 0.014)
				if _wrap_dist(u, at + 0.25) < 0.22:
					d = minf(d, absf(ay - 0.16) - 0.008)
		"rib":
			# Zig-zag grooves round the tyre, two either side of the middle.
			var zig := absf(fposmod(u * 2.0, 2.0) - 1.0) * 0.016 - 0.008
			d = minf(absf(ay - 0.055 - zig), absf(ay - 0.15 + zig)) - 0.01
		"cruiser":
			# A plain centre rib, a groove each side of it, then blocks cut by slanted grooves.
			d = absf(ay - 0.055) - 0.011
			if ay > 0.055:
				var u0 := 0.0 if side > 0.0 else 0.5
				d = minf(d, _seg_dist(u, ay, u0, 0.055, u0 + 0.12, 0.24) - 0.011)
				d = minf(d, _seg_dist(u, ay, u0 + 0.5, 0.055, u0 + 0.62, 0.24) - 0.011)
	return smoothstep(0.0, 0.01, d)


## How far (u, v) is from the segment (u0, v0)-(u1, v1), u wrapping round a repeat.
static func _seg_dist(u: float, v: float, u0: float, v0: float, u1: float, v1: float) -> float:
	var best := INF
	var a := Vector2(u0, v0)
	var b := Vector2(u1, v1)
	for shift in [-2.0, -1.0, 0.0, 1.0]:
		var p := Vector2(u + shift, v)
		var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best


## How far round a repeat `u` is from `at`, either way.
static func _wrap_dist(u: float, at: float) -> float:
	var d := fposmod(u - at, 1.0)
	return minf(d, 1.0 - d)
