class_name BikeBadge
extends RefCounted
## A bike's own badge, chosen in the Bike shop's configurator: a logo and a brand name, each in a
## colour of its own, stamped on both sides of the tank (and the logo, large and faint, on the
## backdrop behind the bike in the shop's preview). It belongs to the tank: the tank item carries
## it as "badge" with its colours (see PartColours), so it goes wherever the tank's look goes,
## saved, sent to the other player and drawn by BikeModel.
##
## A badge is {logo, logo_color, brand, brand_color}: "logo" one of LOGOS ("" for none) and
## "brand" free text up to BRAND_MAX letters ("" for none). Each can also be sized and moved:
## "logo_size"/"brand_size" times its usual size (SIZE_MIN..SIZE_MAX), and "logo_x"/"brand_x" along
## the tank (towards the seat) and "logo_y"/"brand_y" up it, as a share of the tank's length and
## height (-MOVE_MAX..MOVE_MAX). Left out, each is as it comes: size 1, not moved. "brand_font"
## is one of FONTS (left out for the plain one).

const BRAND_MAX := 16
## The brand name's lettering, in picker order: id -> [name, file in FONT_DIR ("" for the game's
## own), in capitals whatever's typed]. All free fonts (SIL Open Font License, see FONT_DIR/licences).
const FONTS := {
	"plain": ["Plain", "", true],
	"bebas": ["Bebas Neue", "BebasNeue-Regular.ttf", true],
	"racing": ["Racing Sans", "RacingSansOne-Regular.ttf", true],
	"russo": ["Russo One", "RussoOne-Regular.ttf", true],
	"audiowide": ["Audiowide", "Audiowide-Regular.ttf", true],
	"blackops": ["Black Ops", "BlackOpsOne-Regular.ttf", true],
	"graduate": ["Graduate", "Graduate-Regular.ttf", true],
	"righteous": ["Righteous", "Righteous-Regular.ttf", false],
	"playfair": ["Playfair", "PlayfairDisplay.ttf", false],
	"lobster": ["Lobster", "Lobster-Regular.ttf", false],
	"pacifico": ["Pacifico", "Pacifico-Regular.ttf", false],
	"kaushan": ["Kaushan Script", "KaushanScript-Regular.ttf", false],
}
const FONT_DIR := "res://assets/fonts/badge/"
## The logos to pick from, in picker order, and what each is called.
const LOGOS := {"wings": "Wings", "star": "Star", "shield": "Shield", "bolt": "Lightning bolt", "roundel": "Roundel",
	"diamond": "Diamond", "piston": "Piston", "flame": "Flame", "crown": "Crown", "spanners": "Crossed spanners"}
## How big the logo's picture is, in pixels (it's drawn at twice that and shrunk, for smooth edges).
const SIZE := 256
## How tall the brand name's letters are drawn, in pixels, and the clear border round them (a
## share of their height).
const TEXT_PX := 96
const BORDER := 0.15
const SIZE_MIN := 0.4
const SIZE_MAX := 2.5
const MOVE_MAX := 0.5

static var _textures := {}
static var _fonts := {}


## Lettering `id`'s font (cached; the game's own for "plain" or one it doesn't know).
static func font(id: String) -> Font:
	if not FONTS.has(id) or str(FONTS[id][1]) == "":
		return ThemeDB.fallback_font
	if not _fonts.has(id):
		var f: Font = load(FONT_DIR + str(FONTS[id][1]))
		if id == "playfair" and f:
			# A font of every weight in one: this one at its boldest.
			var v := FontVariation.new()
			v.base_font = f
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
			f = v
		_fonts[id] = f if f else ThemeDB.fallback_font
	return _fonts[id]


## Whether lettering `id` is in capitals whatever's typed.
static func caps(id: String) -> bool:
	return bool(FONTS.get(id, FONTS["plain"])[2])


## How a badge shows its brand name: as typed, or in capitals for a font that's set in them.
static func brand_text(b: Dictionary) -> String:
	var t := str(b.get("brand", ""))
	return t.to_upper() if caps(str(b.get("brand_font", "plain"))) else t


## `badge` made safe to keep: a known logo or none, the brand trimmed to BRAND_MAX, colours that
## are colours. {} when there's nothing on it.
static func clean(badge) -> Dictionary:
	if not (badge is Dictionary):
		return {}
	var out := {}
	var logo := str(badge.get("logo", ""))
	if LOGOS.has(logo):
		out["logo"] = logo
		out["logo_color"] = badge["logo_color"] if badge.get("logo_color") is Color else Color(0.92, 0.92, 0.9)
	var brand := str(badge.get("brand", "")).replace("\n", " ").strip_edges().left(BRAND_MAX).strip_edges()
	if brand != "":
		out["brand"] = brand
		out["brand_color"] = badge["brand_color"] if badge.get("brand_color") is Color else Color(0.92, 0.92, 0.9)
		var f := str(badge.get("brand_font", ""))
		if FONTS.has(f) and f != "plain":
			out["brand_font"] = f
	for what in ["logo", "brand"]:
		if not out.has(what):
			continue
		var size = badge.get(what + "_size")
		if (size is float or size is int) and not is_equal_approx(float(size), 1.0):
			out[what + "_size"] = clampf(float(size), SIZE_MIN, SIZE_MAX)
		for axis in ["_x", "_y"]:
			var v = badge.get(what + axis)
			if (v is float or v is int) and absf(float(v)) > 0.001:
				out[what + axis] = clampf(float(v), -MOVE_MAX, MOVE_MAX)
	return out


## Logo `id`'s picture: white on clear, to be tinted (cached).
static func texture(id: String) -> Texture2D:
	if not LOGOS.has(id):
		return null
	if _textures.has(id):
		return _textures[id]
	var big := SIZE * 2
	var img := Image.create(big, big, false, Image.FORMAT_RGBA8)
	for sh in _shapes(id):
		var px := PackedVector2Array()
		for p in sh[1]:
			px.append((p + Vector2.ONE) * 0.5 * big)
		_fill(img, [px], Color.WHITE if sh[0] else Color(1, 1, 1, 0))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[id] = tex
	return tex


## Fills the inside of `polys` (in pixels, y down) on `img` with `fill`, a row at a time: the
## spans between the crossings of the row by all of their edges, so a hole (an inner loop, like
## the middle of an O) stays out.
static func _fill(img: Image, polys: Array, fill: Color) -> void:
	var lo := INF
	var hi := -INF
	for pts in polys:
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	if lo > hi:
		return
	for y in range(maxi(0, floori(lo)), mini(img.get_height(), ceili(hi) + 1)):
		var py := y + 0.5
		var xs: Array[float] = []
		for pts in polys:
			var n: int = pts.size()
			for i in n:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % n]
				if (a.y <= py) != (b.y <= py):
					xs.append(a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := clampi(roundi(xs[k]), 0, img.get_width())
			var x1 := clampi(roundi(xs[k + 1]), 0, img.get_width())
			if x1 > x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0, 1), fill)


## The brand name `text` in lettering `font_id`, white on clear, to be tinted (cached): drawn
## from the font's own outlines, so it needs nothing on screen. Its height is TEXT_PX plus a clear
## border all round (BORDER of it), so its edge shows nothing where it's stretched over the tank.
static func text_texture(text: String, font_id: String) -> Texture2D:
	var key := font_id + "|" + text
	if _textures.has(key):
		return _textures[key]
	var f := font(font_id)
	var ts := TextServerManager.get_primary_interface()
	var size := TEXT_PX * 2   # drawn at twice the size and shrunk, for smooth edges
	var shaped := ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, f.get_rids(), size)
	var glyphs := ts.shaped_text_get_glyphs(shaped)
	var ascent := ts.shaped_text_get_ascent(shaped)
	var descent := ts.shaped_text_get_descent(shaped)
	var wide := ts.shaped_text_get_width(shaped)
	var pad := ceili((ascent + descent) * BORDER)
	var img := Image.create(maxi(4, ceili(wide) + pad * 2), maxi(4, ceili(ascent + descent) + pad * 2), false, Image.FORMAT_RGBA8)
	var polys := []
	var pen := 0.0
	for g in glyphs:
		var at := Vector2(pad + pen, pad + ascent) + (g.get("offset", Vector2.ZERO) as Vector2)
		var rid: RID = g.get("font_rid", RID())
		if rid.is_valid() and int(g.get("index", 0)) != 0:
			var c: Dictionary = ts.font_get_glyph_contours(rid, int(g.get("font_size", size)), int(g["index"]))
			if not c.is_empty():
				polys.append_array(_outlines(c, at))
		pen += float(g.get("advance", 0.0)) * int(g.get("repeat", 1))
	ts.free_rid(shaped)
	_fill(img, polys, Color.WHITE)
	img.resize(maxi(2, img.get_width() / 2), maxi(2, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## A glyph's outlines (TextServer.font_get_glyph_contours) as closed polygons in pixels, its
## origin at `at`: curves flattened to short straight runs.
static func _outlines(c: Dictionary, at: Vector2) -> Array:
	var pts: PackedVector3Array = c.get("points", PackedVector3Array())
	var ends: PackedInt32Array = c.get("contours", PackedInt32Array())
	var out := []
	var first := 0
	for e in ends:
		var ring := []
		for i in range(first, e + 1):
			ring.append(pts[i])
		first = e + 1
		if ring.size() < 2:
			continue
		# Start on a point on the curve (or between two that aren't).
		var k := -1
		for i in ring.size():
			if int(ring[i].z) == TextServer.CONTOUR_CURVE_TAG_ON:
				k = i
				break
		var seq := []
		if k < 0:
			var m: Vector3 = (ring[0] + ring[1]) * 0.5
			m.z = TextServer.CONTOUR_CURVE_TAG_ON
			seq = [m] + ring + [m]
		else:
			seq = ring.slice(k) + ring.slice(0, k) + [ring[k]]
		var poly := PackedVector2Array()
		var prev := Vector2(seq[0].x, seq[0].y)
		poly.append(prev + at)
		var j := 1
		while j < seq.size():
			var p: Vector3 = seq[j]
			var tag := int(p.z)
			if tag == TextServer.CONTOUR_CURVE_TAG_ON:
				prev = Vector2(p.x, p.y)
				poly.append(prev + at)
				j += 1
			elif tag == TextServer.CONTOUR_CURVE_TAG_OFF_CUBIC and j + 2 < seq.size():
				var c1 := Vector2(p.x, p.y)
				var c2 := Vector2(seq[j + 1].x, seq[j + 1].y)
				var to := Vector2(seq[j + 2].x, seq[j + 2].y)
				for s in range(1, 9):
					var t := s / 8.0
					var u := 1.0 - t
					poly.append(prev * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + to * t * t * t + at)
				prev = to
				j += 3
			else:
				var ctrl := Vector2(p.x, p.y)
				var nxt: Vector3 = seq[j + 1] if j + 1 < seq.size() else seq[0]
				var to := Vector2(nxt.x, nxt.y)
				var on_next := int(nxt.z) == TextServer.CONTOUR_CURVE_TAG_ON
				if not on_next:
					to = (ctrl + to) * 0.5
				for s in range(1, 7):
					var t := s / 6.0
					poly.append(prev.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t) + at)
				prev = to
				j += 2 if on_next else 1
		out.append(poly)
	return out


## Logo `id` as polygons in a -1..1 square (y down): [[on, points], ...], drawn in order, a later
## one cutting out of (on false) or adding to (on true) what's under it.
static func _shapes(id: String) -> Array:
	match id:
		"star":
			return [[true, _star(5, 0.95, 0.4, -PI / 2.0)]]
		"shield":
			var outer := PackedVector2Array([Vector2(-0.8, -0.85), Vector2(0.8, -0.85), Vector2(0.8, 0.0),
				Vector2(0.45, 0.6), Vector2(0.0, 0.95), Vector2(-0.45, 0.6), Vector2(-0.8, 0.0)])
			var inner := PackedVector2Array()
			for v in outer:
				inner.append(v * 0.78 + Vector2(0.0, -0.02))
			var chevron := PackedVector2Array([Vector2(-0.55, -0.35), Vector2(0.0, 0.05), Vector2(0.55, -0.35),
				Vector2(0.55, -0.1), Vector2(0.0, 0.3), Vector2(-0.55, -0.1)])
			return [[true, outer], [false, inner], [true, chevron]]
		"bolt":
			return [[true, PackedVector2Array([Vector2(0.25, -0.95), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12),
				Vector2(-0.3, 0.95), Vector2(0.6, -0.2), Vector2(0.08, -0.2), Vector2(0.38, -0.95)])]]
		"roundel":
			return [[true, _circle(0.95)], [false, _circle(0.75)], [true, _circle(0.5)],
				[true, PackedVector2Array([Vector2(-0.98, -0.16), Vector2(0.98, -0.16), Vector2(0.98, 0.16), Vector2(-0.98, 0.16)])]]
		"diamond":
			var d := func(r: float) -> PackedVector2Array: return PackedVector2Array([Vector2(0, -r), Vector2(r * 0.8, 0), Vector2(0, r), Vector2(-r * 0.8, 0)])
			return [[true, d.call(0.97)], [false, d.call(0.72)], [true, d.call(0.45)]]
		"piston":
			return [[true, _rect(-0.6, -0.9, 0.6, -0.15)], [false, _rect(-0.6, -0.72, 0.6, -0.65)],
				[false, _rect(-0.6, -0.55, 0.6, -0.48)], [true, _rect(-0.14, -0.2, 0.14, 0.75)], [true, _circle(0.26, Vector2(0.0, 0.72))],
				[false, _circle(0.12, Vector2(0.0, 0.72))]]
		"flame":
			# A flame of three tongues, licked out of its middle.
			return [[true, PackedVector2Array([Vector2(0.0, -0.95), Vector2(0.16, -0.5), Vector2(0.4, -0.72),
				Vector2(0.44, -0.28), Vector2(0.66, -0.42), Vector2(0.62, 0.12), Vector2(0.5, 0.55), Vector2(0.25, 0.86),
				Vector2(0.0, 0.95), Vector2(-0.25, 0.86), Vector2(-0.5, 0.55), Vector2(-0.62, 0.12), Vector2(-0.66, -0.42),
				Vector2(-0.44, -0.28), Vector2(-0.4, -0.72), Vector2(-0.16, -0.5)])],
				[false, PackedVector2Array([Vector2(0.0, -0.15), Vector2(0.18, 0.25), Vector2(0.16, 0.55), Vector2(0.0, 0.68),
				Vector2(-0.16, 0.55), Vector2(-0.18, 0.25)])]]
		"crown":
			return [[true, PackedVector2Array([Vector2(-0.85, 0.65), Vector2(-0.95, -0.55), Vector2(-0.45, -0.05),
				Vector2(0.0, -0.8), Vector2(0.45, -0.05), Vector2(0.95, -0.55), Vector2(0.85, 0.65)])],
				[true, _rect(-0.85, 0.72, 0.85, 0.88)]]
		"spanners":
			var out := []
			for a in [PI / 4.0, -PI / 4.0]:
				out.append([true, _turned(_rect(-0.11, -0.7, 0.11, 0.7), a)])
				for end in [-0.72, 0.72]:
					out.append([true, _turned(_circle(0.24, Vector2(0.0, end)), a)])
					# The jaw: a slot cut out of the ring's far side.
					var y0: float = end - 0.3 if end < 0.0 else end - 0.05
					out.append([false, _turned(_rect(-0.09, y0, 0.09, y0 + 0.35), a)])
			return out
	# "wings": a round boss with a swept wing either side, feathered underneath.
	var wing := PackedVector2Array([Vector2(0.15, -0.2), Vector2(0.98, -0.42), Vector2(0.92, -0.22),
		Vector2(0.78, -0.18), Vector2(0.72, -0.02), Vector2(0.56, 0.0), Vector2(0.5, 0.14), Vector2(0.34, 0.14), Vector2(0.15, 0.22)])
	var left := PackedVector2Array()
	for v in wing:
		left.append(Vector2(-v.x, v.y))
	return [[true, wing], [true, left], [true, _circle(0.3)], [false, _circle(0.18)]]


static func _circle(r: float, at := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 48:
		out.append(at + Vector2.from_angle(TAU * i / 48.0) * r)
	return out


static func _star(n: int, r_out: float, r_in: float, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n * 2:
		out.append(Vector2.from_angle(turn + PI * i / n) * (r_out if i % 2 == 0 else r_in))
	return out


static func _turned(pts: PackedVector2Array, a: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(v.rotated(a))
	return out


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Stamps badge `badge` on both sides of the tank as decals: for the logo and the brand name, a
## thin skin cut from the tank's own surface (`faces`: its triangles in `parent`'s space, three
## points each, from before the bike is baked; `box` their bounds) and lifted a hair off it, the
## picture mapped across it, so it follows every curve of the tank. Returns the nodes added (none
## without a badge or a tank). Each is named BadgeLogoR/L or BadgeBrandR/L, and carries its
## picture's place on the tank as meta "rect" (Rect2 in z and y) and the brand's text as "text".
static func stamp(parent: Node3D, box: AABB, badge: Dictionary, faces := PackedVector3Array()) -> Array:
	var b := clean(badge)
	var out := []
	if b.is_empty() or box.size.x <= 0.01 or box.size.z <= 0.05 or faces.size() < 3:
		return out
	var h := box.size.y
	var length := box.size.z
	var y := box.get_center().y + h * 0.08
	var has_logo := b.has("logo")
	var has_brand := b.has("brand")
	var logo_size := minf(h * 0.55, length * 0.32)
	# Along the tank (z, its nose at the smaller z): the logo ahead of the brand, or either alone
	# in the middle, then each sized and moved as asked.
	var mid := box.get_center().z
	var logo_z := mid - (length * 0.2 if has_brand else 0.0)
	var pics := []   # [name, texture, colour, rect in (z, y)]
	if has_logo:
		var ls := logo_size * float(b.get("logo_size", 1.0))
		var at := Vector2(logo_z + float(b.get("logo_x", 0.0)) * length, y + float(b.get("logo_y", 0.0)) * h)
		pics.append(["BadgeLogo", texture(str(b["logo"])), b["logo_color"], Rect2(at - Vector2(ls, ls) * 0.5, Vector2(ls, ls)), ""])
	if has_brand:
		var text := brand_text(b)
		var tex := text_texture(text, str(b.get("brand_font", "plain")))
		var aspect := float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
		# The letters a fifth of the tank's height, smaller still if that's too long to fit.
		var tall := h * 0.2 * (1.0 + BORDER * 2.0)
		var room := length * (0.5 if has_logo else 0.8) * (1.0 + BORDER * 2.0 / aspect)
		if tall * aspect > room:
			tall = room / aspect
		tall *= float(b.get("brand_size", 1.0))
		var wide := tall * aspect
		# Its middle just behind where the logo comes (towards the seat: larger z), or the tank's
		# middle; sizing or moving the logo leaves it be.
		var bz := logo_z + logo_size * 0.5 + wide * 0.5 if has_logo else mid
		var at := Vector2(bz + float(b.get("brand_x", 0.0)) * length, y + float(b.get("brand_y", 0.0)) * h)
		pics.append(["BadgeBrand", tex, b["brand_color"], Rect2(at - Vector2(wide, tall) * 0.5, Vector2(wide, tall)), text])
	for side in [1.0, -1.0]:
		for pic in pics:
			var mesh := _decal_mesh(faces, side, box.get_center().x, pic[3])
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = str(pic[0]) + ("R" if side > 0.0 else "L")
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.albedo_texture = pic[1]
			m.albedo_color = pic[2]
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.texture_repeat = false
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.roughness = 0.3
			m.render_priority = 1
			mi.material_override = m
			mi.set_meta("rect", pic[3])
			if pic[4] != "":
				mi.set_meta("text", pic[4])
			parent.add_child(mi)
			out.append(mi)
	return out


## How far a decal sits off the tank's paint.
const LIFT := 0.0015


## The skin for one decal on side `side` (+1 the right, the larger x): every triangle of `faces`
## on that side of `mid_x`, facing out that way, that reaches into `rect` (in z and y) and is the
## outermost there (not the tank's tunnel or inner wall behind it), lifted LIFT off along its
## smoothed normal, with the picture laid flat across `rect` as seen from that side. Null if no
## surface reaches it.
static func _decal_mesh(faces: PackedVector3Array, side: float, mid_x: float, rect: Rect2) -> ArrayMesh:
	var picked := []   # [a, b, c, outward normal]
	const CELLS := 16
	var depth := PackedFloat32Array()
	depth.resize(CELLS * CELLS)
	depth.fill(-INF)
	var cell := rect.size / CELLS
	for f in range(0, faces.size() - 2, 3):
		var a := faces[f]
		var b := faces[f + 1]
		var c := faces[f + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		if absf(n.x) < 0.2 or ((a.x + b.x + c.x) / 3.0 - mid_x) * side <= 0.0:
			continue
		var lo := Vector2(minf(a.z, minf(b.z, c.z)), minf(a.y, minf(b.y, c.y)))
		var hi := Vector2(maxf(a.z, maxf(b.z, c.z)), maxf(a.y, maxf(b.y, c.y)))
		if hi.x < rect.position.x or lo.x > rect.end.x or hi.y < rect.position.y or lo.y > rect.end.y:
			continue
		var out_n := n * (signf(n.x) * side)
		picked.append([a, b, c, out_n])
		# How far out the surface comes over each cell it spans, to keep only the outer skin.
		var far := maxf(a.x * side, maxf(b.x * side, c.x * side))
		var i0 := clampi(floori((lo.x - rect.position.x) / cell.x), 0, CELLS - 1)
		var i1 := clampi(floori((hi.x - rect.position.x) / cell.x), 0, CELLS - 1)
		var j0 := clampi(floori((lo.y - rect.position.y) / cell.y), 0, CELLS - 1)
		var j1 := clampi(floori((hi.y - rect.position.y) / cell.y), 0, CELLS - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				depth[j * CELLS + i] = maxf(depth[j * CELLS + i], far)
	if picked.is_empty():
		return null
	var keep := []
	var normals := {}   # a point (rounded) -> its summed normal, for smooth shading
	for t in picked:
		var mid_t: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		var i := clampi(floori((mid_t.z - rect.position.x) / cell.x), 0, CELLS - 1)
		var j := clampi(floori((mid_t.y - rect.position.y) / cell.y), 0, CELLS - 1)
		var near := maxf(t[0].x * side, maxf(t[1].x * side, t[2].x * side))
		if near < depth[j * CELLS + i] - 0.02:
			continue   # something further out covers it
		keep.append(t)
		for k in 3:
			var key: Vector3i = Vector3i((t[k] as Vector3) * 2000.0)
			normals[key] = normals.get(key, Vector3.ZERO) + t[3]
	if keep.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in keep:
		# Wound so its front faces out of the tank, whichever way the tank's own triangles go.
		var order := [0, 1, 2] if ((t[1] - t[0]).cross(t[2] - t[0]) as Vector3).dot(t[3]) < 0.0 else [0, 2, 1]
		for k in order:
			var p: Vector3 = t[k]
			var n: Vector3 = normals[Vector3i(p * 2000.0)].normalized()
			# The picture as seen from this side: left to right is towards the nose on the right
			# side (the smaller z) and towards the seat on the left.
			var u := (p.z - rect.position.x) / rect.size.x
			if side > 0.0:
				u = 1.0 - u
			st.set_normal(n)
			st.set_uv(Vector2(u, (rect.end.y - p.y) / rect.size.y))
			st.add_vertex(p + n * LIFT)
	return st.commit()
