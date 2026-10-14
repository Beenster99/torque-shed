class_name PosterArt
## Wall poster art as flat 2D prints. Each poster model (Equipment.MODELS, kind "poster": title,
## sub, paper, ink, band, size) is drawn once into a SubViewport (aged paper, colour band, big
## title, a motorbike for tall posters, speed stripes and chequers for wide ones), baked into a
## mipmapped texture and shared by every poster of that model. Without a real renderer (headless
## tests) the poster is a plain sheet of its paper colour.

const PX_PER_M := 1300.0
const MAX_PX := 1600

static var _materials := {}   # model id -> StandardMaterial3D


## One flat sheet showing the poster, +Z out of the wall, 2 mm proud of the wall plane.
static func make(model_id: String, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "PosterArt"
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.y)
	mi.mesh = quad
	mi.material_override = material(model_id, size)
	mi.position = Vector3(0.0, 0.0, 0.002)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The shared material for a poster model; its texture arrives a few frames after first use.
## Printed a different shape (a banner, see Equipment.poster_size) it's laid out afresh for
## that shape; any size of the same shape shares the one print.
static func material(model_id: String, print_size := Vector3.ZERO) -> StandardMaterial3D:
	var m: Dictionary = Equipment.get_model(model_id)
	var size: Vector3 = m.get("size", Vector3(0.6, 0.85, 0.01))
	var key := model_id
	if print_size.x > 0.0 and print_size.y > 0.0 and absf(print_size.x / print_size.y - size.x / size.y) > 0.05:
		key = "%s|%.2f" % [model_id, print_size.x / print_size.y]
		size = print_size
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = m.get("paper", Color(0.9, 0.85, 0.7))
	mat.roughness = 0.82
	mat.metallic = 0.0
	mat.metallic_specular = 0.3
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = mat
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or DisplayServer.get_name() == "headless" or not m.has("title"):
		return mat   # no renderer to draw with: a plain sheet of paper
	var px := Vector2(size.x, size.y) * PX_PER_M
	px *= minf(1.0, MAX_PX / maxf(px.x, px.y))
	var vp := SubViewport.new()
	vp.name = "PosterArt_" + key.replace("|", "_").replace(".", "_")
	vp.size = Vector2i(px.round())
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Canvas.new()
	canvas.data = m
	canvas.seed_from = model_id
	canvas.target = mat
	canvas.size = Vector2(vp.size)
	vp.add_child(canvas)
	tree.root.add_child.call_deferred(vp)
	mat.albedo_texture = vp.get_texture()
	mat.albedo_color = Color.WHITE
	return mat


## Draws one poster, then bakes it into an ImageTexture and frees its viewport.
class Canvas extends Control:
	var data: Dictionary
	var seed_from := ""
	var target: StandardMaterial3D
	var _frames := 0
	var _font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.9
		fv.variation_transform = Transform2D(Vector2(0.86, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
		fv.spacing_glyph = 1
		_font = fv

	func _process(_delta: float) -> void:
		_frames += 1
		if _frames < 4:
			return
		set_process(false)
		var vp := get_viewport() as SubViewport
		var img := vp.get_texture().get_image()
		if img and not img.is_empty():
			img.generate_mipmaps()
			target.albedo_texture = ImageTexture.create_from_image(img)
			vp.queue_free()
		# If the read back failed, the live viewport texture stays (and so does the viewport).

	func _draw() -> void:
		var paper: Color = data.get("paper", Color(0.9, 0.85, 0.7))
		var ink: Color = data.get("ink", Color.BLACK)
		var band: Color = data.get("band", Color.RED)
		var title := str(data.get("title", ""))
		var sub := str(data.get("sub", ""))
		var w := size.x
		var h := size.y
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_from)
		var dark_paper := paper.get_luminance() < 0.35
		draw_rect(Rect2(Vector2.ZERO, size), paper)
		# Mottled, uneven paper.
		for i in 70:
			var c: Color = paper.lightened(0.06) if dark_paper else paper.darkened(0.1)
			c.a = rng.randf_range(0.04, 0.1)
			draw_circle(Vector2(rng.randf() * w, rng.randf() * h), rng.randf_range(0.03, 0.14) * w, c)
		if w > h:
			_draw_wide(w, h, paper, ink, band, title, sub)
		else:
			_draw_tall(w, h, paper, ink, band, title, sub)
		# Worn ink: specks where the print has rubbed off.
		for i in 900:
			var c := paper.lightened(0.05)
			c.a = rng.randf_range(0.25, 0.6)
			draw_circle(Vector2(rng.randf() * w, rng.randf() * h), rng.randf_range(0.6, 2.2), c)
		# Fold creases, quartered.
		for v: bool in [false, true]:
			var a: Vector2 = Vector2(w * 0.5, 0) if v else Vector2(0, h * 0.5)
			var b: Vector2 = Vector2(w * 0.5, h) if v else Vector2(w, h * 0.5)
			var off: Vector2 = Vector2(2, 0) if v else Vector2(0, 2)
			draw_line(a, b, Color(0, 0, 0, 0.1), 2.0)
			draw_line(a + off, b + off, Color(1, 1, 1, 0.08), 2.0)
		# Edges and corners browned with age.
		var steps := 28
		var edge := minf(w, h) * 0.09
		for i in steps:
			var t := float(i) / steps
			var inset := edge * t
			var c := Color(0.25, 0.15, 0.05, 0.075 * (1.0 - t))
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), c, false, edge / steps + 1.0)
		# Yellowed tape holding up the top corners.
		var tape := Color(0.93, 0.88, 0.7, 0.55)
		var tw := minf(w, h) * 0.16
		for corner: Vector2 in [Vector2(0, 0), Vector2(w, 0)]:
			var ang: float = 0.75 if corner.x == 0 else -0.75
			draw_set_transform(corner, ang, Vector2.ONE)
			draw_rect(Rect2(Vector2(-tw * 0.5, -tw * 0.14), Vector2(tw, tw * 0.28)), tape)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_tall(w: float, h: float, paper: Color, ink: Color, band: Color, title: String, sub: String) -> void:
		var m := w * 0.05
		draw_rect(Rect2(Vector2(m, m), Vector2(w, h) - Vector2(m, m) * 2.0), ink, false, w * 0.008)
		draw_rect(Rect2(Vector2(m, m) * 1.35, Vector2(w, h) - Vector2(m, m) * 2.7), ink, false, w * 0.003)
		_title(title, Vector2(w * 0.5, h * 0.165), w * 0.8, h * 0.12, ink, band)
		# The art: a sun disc, speed lines and a racing bike.
		var sun := band.lerp(paper, 0.55)
		draw_circle(Vector2(w * 0.6, h * 0.44), w * 0.27, sun)
		draw_arc(Vector2(w * 0.6, h * 0.44), w * 0.3, 0.0, TAU, 72, sun, w * 0.008, true)
		var ground := h * 0.6
		for i in 6:
			var y := h * (0.36 + 0.035 * i)
			var x0 := w * (0.1 + 0.03 * (i % 3))
			draw_line(Vector2(x0, y), Vector2(x0 + w * (0.18 + 0.05 * ((i * 7) % 3)), y), Color(ink, 0.75), h * 0.006, true)
		draw_line(Vector2(w * 0.1, ground), Vector2(w * 0.9, ground), ink, h * 0.004, true)
		_bike(Vector2(w * 0.52, ground - w * 0.2), w * 0.72, ink, band, paper)
		# Colour band with the sub line knocked out of it in paper colour.
		var by := h * 0.68
		var bh := h * 0.1
		draw_rect(Rect2(Vector2(m * 1.35, by), Vector2(w - m * 2.7, bh)), band)
		_text(sub, Vector2(w * 0.5, by + bh * 0.5), w * 0.8, bh * 0.55, _on(band, paper, ink))
		# Small print and ornaments below.
		for i in 3:
			var c := Vector2(w * (0.38 + 0.12 * i), h * 0.86)
			var r := w * 0.018
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), ink)
		draw_line(Vector2(w * 0.2, h * 0.86), Vector2(w * 0.32, h * 0.86), ink, h * 0.003, true)
		draw_line(Vector2(w * 0.68, h * 0.86), Vector2(w * 0.8, h * 0.86), ink, h * 0.003, true)
		_text(str(data.get("name", "")).to_upper(), Vector2(w * 0.5, h * 0.905), w * 0.6, h * 0.018, Color(ink, 0.8))

	func _draw_wide(w: float, h: float, paper: Color, ink: Color, band: Color, title: String, sub: String) -> void:
		var m := h * 0.06
		draw_rect(Rect2(Vector2(m, m), Vector2(w, h) - Vector2(m, m) * 2.0), ink, false, h * 0.012)
		var banner := w / h > 2.2
		var inner_l := m * 1.6
		var top := m * 1.6
		var bottom := h - m * 1.6
		if banner:
			# A long banner: chequered flags down both ends.
			var sq := h * 0.075
			var rows := int((h - m * 3.0) / sq)
			var y0 := (h - rows * sq) * 0.5
			for end in [0, 1]:
				var x0: float = m * 1.6 if end == 0 else w - m * 1.6 - sq * 3.0
				for r in rows:
					for col in 3:
						if (r + col) % 2 == 0:
							draw_rect(Rect2(Vector2(x0 + col * sq, y0 + r * sq), Vector2(sq, sq)), ink)
			inner_l = m * 1.6 + sq * 3.0 + m
		else:
			# A sign: chequered strips along the top and bottom.
			var sq := h * 0.045
			var cols := int((w - m * 3.2) / sq)
			var x0 := (w - cols * sq) * 0.5
			for strip in [0, 1]:
				var y0: float = m * 1.6 if strip == 0 else h - m * 1.6 - sq * 2.0
				for r in 2:
					for col in cols:
						if (r + col) % 2 == 0:
							draw_rect(Rect2(Vector2(x0 + col * sq, y0 + r * sq), Vector2(sq, sq)), ink)
			top = m * 1.6 + sq * 2.0
			bottom = h - top
			inner_l = m * 1.8
		var inner_r := w - inner_l
		var inner_w := inner_r - inner_l
		var span := bottom - top
		var title_y := top + span * (0.32 if banner else 0.36)
		# Slanted speed stripes sweeping in from both sides behind the title.
		for i in 4:
			var y := top + span * (0.1 + 0.075 * i)
			var x := inner_l + inner_w * (0.02 + 0.03 * i)
			var sw := inner_w * (0.3 - 0.05 * i)
			var t := span * 0.045
			var sl := t * 1.2
			var c: Color = band if i % 2 == 0 else band.lerp(paper, 0.45)
			draw_colored_polygon(PackedVector2Array([Vector2(x + sl, y), Vector2(x + sw + sl, y), Vector2(x + sw, y + t), Vector2(x, y + t)]), c)
			var xr := inner_r - (x - inner_l) - sw
			draw_colored_polygon(PackedVector2Array([Vector2(xr, y), Vector2(xr + sw, y), Vector2(xr + sw - sl, y + t), Vector2(xr - sl, y + t)]), c)
		_title(title, Vector2(w * 0.5, title_y), inner_w * 0.9, span * (0.36 if banner else 0.4), ink, band)
		# The band with the sub line in it, and a thin rule above and below.
		var by := top + span * (0.64 if banner else 0.66)
		var bh := span * 0.2
		draw_rect(Rect2(Vector2(inner_l, by), Vector2(inner_w, bh)), band)
		draw_line(Vector2(inner_l, by - span * 0.03), Vector2(inner_r, by - span * 0.03), ink, h * 0.008)
		draw_line(Vector2(inner_l, by + bh + span * 0.03), Vector2(inner_r, by + bh + span * 0.03), ink, h * 0.008)
		_text(sub, Vector2(w * 0.5, by + bh * 0.5), inner_w * 0.9, bh * 0.62, _on(band, paper, ink))

	## Whichever of two colours reads better printed on the background.
	func _on(bg: Color, a: Color, b: Color) -> Color:
		return a if absf(a.get_luminance() - bg.get_luminance()) >= absf(b.get_luminance() - bg.get_luminance()) else b

	## The big title, with a slightly misregistered shadow print in the band colour.
	func _title(text: String, center: Vector2, max_w: float, max_h: float, ink: Color, band: Color) -> void:
		var fs := _fit(text, max_w, max_h)
		var off := Vector2(fs * 0.05, fs * 0.05)
		_line(text, center + off, fs, band)
		_line(text, center, fs, ink)

	func _text(text: String, center: Vector2, max_w: float, max_h: float, color: Color) -> void:
		_line(text, center, _fit(text, max_w, max_h), color)

	func _fit(text: String, max_w: float, max_h: float) -> int:
		var fs := int(max_h)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > max_w:
			fs = int(fs * max_w / tw)
		return maxi(fs, 6)

	func _line(text: String, center: Vector2, fs: int, color: Color) -> void:
		var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var asc := _font.get_ascent(fs)
		var desc := _font.get_descent(fs)
		var pos := Vector2(center.x - sz.x * 0.5, center.y + (asc - desc) * 0.5)
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	## A side-on racing bike with a crouched rider, facing right, centred on c, s pixels long.
	func _bike(c: Vector2, s: float, ink: Color, band: Color, paper: Color) -> void:
		_bc = c
		_bs = s
		var rear := Vector2(-0.34, 0.2)
		var front := Vector2(0.35, 0.2)
		var r := 0.17
		for hub in [rear, front]:
			_arc(hub, r - 0.018, 0.0, TAU, 48, ink, 0.036, true)       # tyre
			_arc(hub, r - 0.045, 0.0, TAU, 48, ink, 0.008, true)       # rim
			for k in 14:
				var a := TAU * k / 14.0
				_ln(hub + Vector2(cos(a), sin(a)) * 0.022, hub + Vector2(cos(a + 0.35), sin(a + 0.35)) * (r - 0.045), ink, 0.0035, true)
			_dot(hub, 0.03, ink)
			_dot(hub, 0.012, paper)
		# Mudguards.
		_arc(rear, r + 0.025, PI * 1.05, PI * 1.55, 16, ink, 0.016, true)
		_arc(front, r + 0.022, PI * 1.2, PI * 1.85, 16, ink, 0.016, true)
		# Swing arm, rear shock and frame rails.
		_ln(rear, Vector2(-0.07, 0.11), ink, 0.028, true)
		_ln(Vector2(-0.3, 0.17), Vector2(-0.24, -0.02), ink, 0.024, true)
		_ln(Vector2(-0.3, -0.02), Vector2(0.2, -0.1), ink, 0.024, true)
		_ln(Vector2(0.2, -0.1), Vector2(0.1, 0.12), ink, 0.028, true)
		_ln(Vector2(-0.12, -0.03), Vector2(-0.07, 0.12), ink, 0.024, true)
		# Engine: crankcase and a finned cylinder.
		_poly(PackedVector2Array([Vector2(-0.09, 0.03), Vector2(0.1, 0.0), Vector2(0.14, 0.09),
			Vector2(0.09, 0.16), Vector2(-0.06, 0.16), Vector2(-0.11, 0.1)]), ink)
		_poly(PackedVector2Array([Vector2(0.0, 0.02), Vector2(0.1, 0.0), Vector2(0.13, -0.08), Vector2(0.03, -0.08)]), ink)
		for k in 4:
			var y := -0.065 + k * 0.022
			_ln(Vector2(0.025 + k * 0.004, y), Vector2(0.135 - k * 0.006, y), paper, 0.006, true)
		_dot(Vector2(0.02, 0.1), 0.035, band.lerp(paper, 0.3))
		_dot(Vector2(0.02, 0.1), 0.02, ink)
		# Exhaust sweeping back to a megaphone.
		_pl(PackedVector2Array([Vector2(0.12, -0.02), Vector2(0.16, 0.08), Vector2(0.08, 0.18), Vector2(-0.2, 0.16)]), ink, 0.022, true)
		_poly(PackedVector2Array([Vector2(-0.2, 0.148), Vector2(-0.44, 0.1), Vector2(-0.45, 0.16), Vector2(-0.2, 0.172)]), ink)
		# Tank, seat and tail.
		_poly(PackedVector2Array([Vector2(-0.06, -0.08), Vector2(0.0, -0.17), Vector2(0.14, -0.19),
			Vector2(0.23, -0.15), Vector2(0.21, -0.08), Vector2(0.05, -0.06)]), ink)
		_pl(PackedVector2Array([Vector2(0.0, -0.13), Vector2(0.12, -0.155), Vector2(0.2, -0.13)]), band, 0.016, true)
		_poly(PackedVector2Array([Vector2(-0.34, -0.06), Vector2(-0.28, -0.1), Vector2(-0.06, -0.1),
			Vector2(-0.06, -0.06), Vector2(-0.3, -0.02)]), ink)
		# Race number on the tail.
		_dot(Vector2(-0.26, -0.035), 0.035, paper)
		_line("7", _p(Vector2(-0.26, -0.035)), int(0.05 * _bs), ink)
		# Forks, fairing and clip-ons.
		_ln(Vector2(0.24, -0.17), front, ink, 0.028, true)
		_poly(PackedVector2Array([Vector2(0.2, -0.17), Vector2(0.3, -0.27), Vector2(0.34, -0.2),
			Vector2(0.33, -0.08), Vector2(0.24, -0.06)]), ink)
		_dot(Vector2(0.31, -0.15), 0.035, band.lerp(paper, 0.3))
		_ln(Vector2(0.21, -0.2), Vector2(0.16, -0.22), ink, 0.016, true)
		# The rider, tucked in behind the screen.
		_ln(Vector2(-0.16, -0.12), Vector2(0.02, -0.04), ink, 0.07, true)      # thigh
		_ln(Vector2(0.02, -0.04), Vector2(-0.07, 0.06), ink, 0.055, true)      # shin
		_ln(Vector2(-0.07, 0.06), Vector2(-0.02, 0.07), ink, 0.03, true)       # boot
		_poly(PackedVector2Array([Vector2(-0.22, -0.13), Vector2(-0.1, -0.24), Vector2(0.12, -0.3),
			Vector2(0.17, -0.25), Vector2(0.04, -0.2), Vector2(-0.12, -0.09)]), ink)  # back and torso
		_ln(Vector2(0.1, -0.27), Vector2(0.16, -0.22), ink, 0.04, true)        # arm to the bars
		_dot(Vector2(0.18, -0.31), 0.055, ink)                                # helmet
		_ln(Vector2(0.19, -0.33), Vector2(0.235, -0.315), band.lerp(paper, 0.4), 0.018, true)   # visor

	# Drawing in bike units: a point v lands at _bc + v * _bs, widths scale by _bs, so the
	# antialiasing feather stays one pixel wide.
	var _bc := Vector2.ZERO
	var _bs := 1.0

	func _p(v: Vector2) -> Vector2:
		return _bc + v * _bs

	func _ln(a: Vector2, b: Vector2, col: Color, wid: float, _aa := true) -> void:
		draw_line(_p(a), _p(b), col, wid * _bs, true)

	func _arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, wid: float, _aa := true) -> void:
		draw_arc(_p(c), r * _bs, a0, a1, n, col, wid * _bs, true)

	func _dot(c: Vector2, r: float, col: Color) -> void:
		draw_circle(_p(c), r * _bs, col, true, -1.0, true)

	func _poly(pts: PackedVector2Array, col: Color) -> void:
		var out := PackedVector2Array()
		for v in pts:
			out.append(_p(v))
		draw_colored_polygon(out, col)

	func _pl(pts: PackedVector2Array, col: Color, wid: float, _aa := true) -> void:
		var out := PackedVector2Array()
		for v in pts:
			out.append(_p(v))
		draw_polyline(out, col, wid * _bs, true)
