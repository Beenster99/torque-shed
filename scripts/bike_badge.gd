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
	# Each shape filled a row at a time: the spans between its edges' crossings of the row.
	for sh in _shapes(id):
		var pts: PackedVector2Array = sh[1]
		var fill := Color.WHITE if sh[0] else Color(1, 1, 1, 0)
		for y in big:
			var py := (y + 0.5) / big * 2.0 - 1.0
			var xs: Array[float] = []
			for i in pts.size():
				var a := pts[i]
				var b := pts[(i + 1) % pts.size()]
				if (a.y <= py) != (b.y <= py):
					xs.append(a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			for k in range(0, xs.size() - 1, 2):
				var x0 := clampi(roundi((xs[k] + 1.0) * 0.5 * big), 0, big)
				var x1 := clampi(roundi((xs[k + 1] + 1.0) * 0.5 * big), 0, big)
				if x1 > x0:
					img.fill_rect(Rect2i(x0, y, x1 - x0, 1), fill)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[id] = tex
	return tex


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


## Stamps `badge` on both sides of a tank whose box (in the model's space) is `box`, under
## `parent`: the logo forward, the brand behind it, each just proud of the tank's side.
## Returns the stamps it made.
static func stamp(parent: Node3D, box: AABB, badge: Dictionary) -> Array:
	var b := clean(badge)
	var out := []
	if b.is_empty() or box.size.x <= 0.01 or box.size.z <= 0.05:
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
	var logo_at := Vector3(0.0, y + float(b.get("logo_y", 0.0)) * h, logo_z + float(b.get("logo_x", 0.0)) * length)
	var brand_dy := float(b.get("brand_y", 0.0)) * h
	var brand_dz := float(b.get("brand_x", 0.0)) * length
	var brand_room := length * (0.5 if has_logo else 0.8)
	for side in [1.0, -1.0]:
		var x: float = (box.end.x + 0.004) if side > 0.0 else (box.position.x - 0.004)
		# Facing out of that side (a sprite and a label face +z, so turned a quarter about y).
		var basis := Basis(Vector3.UP, side * PI / 2.0)
		if has_logo:
			var s := Sprite3D.new()
			s.name = "BadgeLogoR" if side > 0.0 else "BadgeLogoL"
			s.texture = texture(str(b["logo"]))
			s.modulate = b["logo_color"]
			s.pixel_size = logo_size * float(b.get("logo_size", 1.0)) / float(SIZE)
			s.double_sided = false
			s.shaded = true
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			s.transform = Transform3D(basis, Vector3(x, logo_at.y, logo_at.z))
			parent.add_child(s)
			out.append(s)
		if has_brand:
			var l := Label3D.new()
			l.name = "BadgeBrandR" if side > 0.0 else "BadgeBrandL"
			l.text = brand_text(b)
			l.font = font(str(b.get("brand_font", "plain")))
			l.modulate = b["brand_color"]
			l.outline_size = 0
			l.font_size = 64
			l.double_sided = false
			l.shaded = true
			l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			# The letters a fifth of the tank's height, smaller still if that's too long to fit.
			var px := h * 0.2 / 64.0
			var wide: float = l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
			if wide * px > brand_room:
				px = brand_room / maxf(wide, 1.0)
			# Its middle just behind where the logo comes (towards the seat: larger z), or the
			# tank's middle; sizing or moving the logo leaves it be.
			var bz := logo_z + logo_size * 0.5 + 0.012 + wide * px * 0.5 if has_logo else mid
			l.pixel_size = px * float(b.get("brand_size", 1.0))
			l.transform = Transform3D(basis, Vector3(x, y + brand_dy, bz + brand_dz))
			parent.add_child(l)
			out.append(l)
	return out
