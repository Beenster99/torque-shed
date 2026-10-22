class_name DiaryBook
extends Control
## The Adventure Diary as a book (see AdventureDiary): a cover with the destination's picture,
## the crew and a little map of the road; a page of the trip computer's final stats under the
## route strip (the road's height all the way, coloured by its surface, the highlights marked
## along it); then the photos, two to a page like a photo journal, taped in at a tilt with their
## captions (the highlight, when, how far in, who, and who took it), clips playing as flipbooks,
## films (MovieClip) with a button to play them; and the log of
## every highlight at the back. Two pages open at a time, turned with the buttons or the arrow
## keys. Opened on a shelf of this machine's diaries (the magazine's "Adventure diaries"), or at
## one (the end of a ride, the photo on the shed wall).

signal closed

const PAPER := Color(0.96, 0.94, 0.89)
const PAPER_EDGE := Color(0.86, 0.83, 0.76)
const INK := Color(0.14, 0.12, 0.11)
const FADED := Color(0.38, 0.34, 0.3)
const RED := Color(0.72, 0.14, 0.09)
const TAPE := Color(0.95, 0.9, 0.7, 0.75)
const PAGE := Vector2(560, 680)
## Photos on a page, highlights in a page of the log.
const PER_PAGE := 2
const LOG_PER_PAGE := 14
## A clip's frames a second, played back.
const CLIP_FPS := 4.0

## The diary open ({} on the shelf), its pages and the spread open (pages 2n and 2n+1).
var diary := {}
var pages: Array = []
var spread := 0
var _left: _Page
var _right: _Page
var _shelf: ScrollContainer
var _shelf_grid: GridContainer
var _book: Control
var _prev: Button
var _next: Button
var _to_shelf: Button
var _where: Label
var _tex := {}                  # file -> Texture2D, loaded as the pages are turned to


func _ready() -> void:
	name = "DiaryBook"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var title := UITheme.label("THE ADVENTURE DIARY", 22, Color(1.0, 0.85, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(center)
	_book = Control.new()
	_book.custom_minimum_size = Vector2(PAGE.x * 2.0 + 24.0, PAGE.y + 16.0)
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.draw.connect(_draw_book)
	center.add_child(_book)
	_left = _Page.new()
	_left.book = self
	_left.position = Vector2(12, 8)
	_left.size = PAGE
	_book.add_child(_left)
	_right = _Page.new()
	_right.book = self
	_right.position = Vector2(12 + PAGE.x, 8)
	_right.size = PAGE
	_book.add_child(_right)
	_shelf = ScrollContainer.new()
	_shelf.custom_minimum_size = Vector2(PAGE.x * 2.0, PAGE.y)
	_shelf.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(_shelf)
	_shelf_grid = GridContainer.new()
	_shelf_grid.columns = 3
	_shelf_grid.add_theme_constant_override("h_separation", 18)
	_shelf_grid.add_theme_constant_override("v_separation", 18)
	_shelf.add_child(_shelf_grid)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	col.add_child(nav)
	_prev = Button.new()
	_prev.text = "< Turn back"
	_prev.pressed.connect(func(): turn(-1))
	nav.add_child(_prev)
	_where = UITheme.label("", 15, Color(1, 1, 1, 0.7))
	_where.custom_minimum_size = Vector2(160, 0)
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_where)
	_next = Button.new()
	_next.text = "Turn the page >"
	_next.pressed.connect(func(): turn(1))
	nav.add_child(_next)
	_to_shelf = Button.new()
	_to_shelf.text = "All the diaries"
	_to_shelf.pressed.connect(open_shelf)
	nav.add_child(_to_shelf)
	var close := Button.new()
	Controls.bind_text(close, "Close the book ({menu})")
	close.pressed.connect(func(): closed.emit())
	nav.add_child(close)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event is InputEventKey and event.pressed and not event.echo and not diary.is_empty():
		if (event as InputEventKey).keycode in [KEY_RIGHT, KEY_D]:
			turn(1)
			get_viewport().set_input_as_handled()
		elif (event as InputEventKey).keycode in [KEY_LEFT, KEY_A]:
			turn(-1)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible and not diary.is_empty():
		_left.tick(delta)
		_right.tick(delta)


# ---------------------------------------------------------------------------- opening it

## The shelf: every diary on this machine, newest first, each a cover to open.
func open_shelf() -> void:
	visible = true
	diary = {}
	pages = []
	_book.visible = false
	_shelf.visible = true
	_prev.visible = false
	_next.visible = false
	_to_shelf.visible = false
	for c in _shelf_grid.get_children():
		c.queue_free()
	var all := AdventureDiary.list()
	_where.text = "%d %s on this machine" % [all.size(), "diary" if all.size() == 1 else "diaries"]
	if all.is_empty():
		var l := UITheme.label("No diaries yet. Every adventure ride makes one: the photos and the highlights, put together at the end.", 18, Color(1, 1, 1, 0.8))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PAGE.x * 1.6, 0)
		_shelf_grid.add_child(l)
		return
	for d in all:
		var b := Button.new()
		b.custom_minimum_size = Vector2(340, 250)
		b.icon = _cover_icon(d)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = "%s\n%s  ·  %s  ·  %s" % [str(d["title"]), str(d["date"]), count(int(d["photos"]), "photo"), count(int(d["highlights"]), "highlight")]
		b.pressed.connect(open_diary.bind(str(d["id"])))
		_shelf_grid.add_child(b)


func _cover_icon(d: Dictionary) -> Texture2D:
	var cover := str(d.get("cover", ""))
	if cover != "" and FileAccess.file_exists(cover):
		var img := Image.load_from_file(cover)
		if img and not img.is_empty():
			img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
			return ImageTexture.create_from_image(img)
	return AdventureDest.picture(AdventureDest.theme_of(d), 0) if str(d.get("dest", "")) != "" else null


## The diary `id` open at its cover. False when there's no such diary here.
func open_diary(id: String) -> bool:
	var d := AdventureDiary.load_diary(id)
	if d.is_empty():
		return false
	show_diary(d)
	return true


## Opens diary `d` (as AdventureDiary.load_diary gives it) at its cover.
func show_diary(d: Dictionary) -> void:
	visible = true
	diary = d
	_tex = {}
	pages = make_pages(d)
	spread = 0
	_book.visible = true
	_shelf.visible = false
	_prev.visible = true
	_next.visible = true
	_to_shelf.visible = true
	_show()


## `n` of `word`, said right ("1 photo", "3 photos").
static func count(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]


## The pages of diary `d`: the cover, the stats and route, the photos two to a page, the log.
static func make_pages(d: Dictionary) -> Array:
	var out := [{"kind": "cover"}, {"kind": "stats"}]
	var photos: Array = d.get("photos", [])
	for i in range(0, photos.size(), PER_PAGE):
		out.append({"kind": "photos", "photos": photos.slice(i, i + PER_PAGE), "first": i})
	var log_list: Array = d.get("log", [])
	for i in range(0, log_list.size(), LOG_PER_PAGE):
		out.append({"kind": "log", "entries": log_list.slice(i, i + LOG_PER_PAGE), "first": i})
	if out.size() % 2 == 1:
		out.append({"kind": "end"})
	return out


func turn(d: int) -> void:
	if diary.is_empty():
		return
	spread = clampi(spread + d, 0, maxi(0, (pages.size() - 1) / 2))
	_show()


func _show() -> void:
	_left.page = pages[spread * 2] if spread * 2 < pages.size() else {}
	_right.page = pages[spread * 2 + 1] if spread * 2 + 1 < pages.size() else {}
	_left.number = spread * 2 + 1
	_right.number = spread * 2 + 2
	_left.reset()
	_right.reset()
	_prev.disabled = spread <= 0
	_next.disabled = spread >= (pages.size() - 1) / 2
	_where.text = "Pages %d-%d of %d" % [spread * 2 + 1, mini(spread * 2 + 2, pages.size()), pages.size()]
	_book.queue_redraw()


## A photo's picture (loaded the first time it's shown), or null.
func texture_of(file: String) -> Texture2D:
	if _tex.has(file):
		return _tex[file]
	var path := AdventureDiary.folder(str(diary.get("id", ""))).path_join(file)
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_tex[file] = tex
	return tex


## Where the `i`th photo of a page goes (two a page, with their captions clear of each other and
## of the page number).
static func photo_box(i: int) -> Rect2:
	return Rect2(64 + (i % 2) * 16.0, 34 + i * 318.0, 416, 234)


## The highlight photo `p` was taken for ({} for one you just took).
func entry_of(p: Dictionary) -> Dictionary:
	var key := str(p.get("key", ""))
	if key == "":
		return {}
	for e in diary.get("log", []):
		if str(e.get("key", "")) == key or "log_%d" % int(e.get("n", 0)) == key:
			return e
	return {}


## The book's covers and spine behind the pages.
func _draw_book() -> void:
	var r := Rect2(Vector2.ZERO, _book.size)
	_book.draw_rect(Rect2(r.position + Vector2(6, 10), r.size), Color(0, 0, 0, 0.35))
	_book.draw_rect(r, Color(0.32, 0.17, 0.1))
	_book.draw_rect(r.grow(-3.0), Color(0.42, 0.24, 0.14), false, 2.0)
	# A few pages' edges under the open ones.
	for k in 3:
		_book.draw_rect(Rect2(Vector2(12 - k * 2, 8 + k * 2), Vector2(PAGE.x * 2.0 + k * 4, PAGE.y)), PAPER_EDGE.darkened(0.05 * k))


# ---------------------------------------------------------------------------- a page

class _Page extends Control:
	var book: DiaryBook
	var page := {}
	var number := 1
	var _t := 0.0
	var _frame := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func reset() -> void:
		_t = 0.0
		_frame = 0
		_film_buttons()
		queue_redraw()

	## A Play button on each film on the page (it opens in the computer's own video player).
	func _film_buttons() -> void:
		for c in get_children():
			c.queue_free()
		if str(page.get("kind", "")) != "photos":
			return
		var list: Array = page.get("photos", [])
		for i in list.size():
			var p: Dictionary = list[i]
			if not bool(p.get("movie", false)):
				continue
			var box := DiaryBook.photo_box(i)
			var video := str(p.get("video", ""))
			var b := Button.new()
			var here := video != "" and FileAccess.file_exists(video)
			b.text = "Play the film" if here else "(the film's not on this computer)"
			b.disabled = not here
			b.position = box.position + Vector2(box.size.x - 190.0, box.size.y - 46.0)
			b.size = Vector2(176, 34)
			b.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(video)))
			add_child(b)

	## Clips on the page play on.
	func tick(delta: float) -> void:
		if str(page.get("kind", "")) != "photos":
			return
		var any := false
		for p in page.get("photos", []):
			any = any or bool(p.get("clip", false))
		if not any:
			return
		_t += delta
		var f := int(_t * CLIP_FPS)
		if f != _frame:
			_frame = f
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var left := number % 2 == 1
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		# The fold's shadow on the inside edge, and faint ruled lines.
		var fold := size.x if left else 0.0
		for k in 14:
			var a := 0.16 * (1.0 - k / 14.0)
			var x := fold - (k + 1) * 2.0 if left else fold + k * 2.0
			draw_rect(Rect2(x, 0, 2, size.y), Color(0.3, 0.22, 0.12, a))
		draw_string(font, Vector2(0, size.y - 14.0), str(number), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, FADED)
		if page.is_empty():
			return
		match str(page.get("kind", "")):
			"cover":
				_cover(font)
			"stats":
				_stats(font)
			"photos":
				_photos(font)
			"log":
				_log(font)
			"end":
				draw_string(font, Vector2(0, size.y * 0.45), "The end of the road.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, INK)
				draw_string(font, Vector2(0, size.y * 0.45 + 34.0), "Till the next one.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, FADED)

	func _cover(font: Font) -> void:
		var d := book.diary
		draw_string(font, Vector2(36, 70), "ADVENTURE DIARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED)
		draw_multiline_string(font, Vector2(36, 112), str(d.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 72.0, 34, 2, INK)
		var dest := str(d.get("dest", ""))
		draw_string(font, Vector2(36, 196), "To %s  ·  %d km  ·  %s" % [AdventureDest.name_of(dest), roundi(float(d.get("km", 0.0))), str(d.get("date", ""))],
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 72.0, 17, FADED)
		# The destination's picture, as on the shed wall, taped in.
		if dest != "":
			var crew: Array = d.get("crew", [])
			var tex := AdventureDest.picture(AdventureDest.theme_of(d), maxi(1, crew.size()))
			_polaroid(Rect2(70, 226, 420, 280), tex, -2.0, "", font, Rect2())
		var crew_t := ", ".join((d.get("crew", []) as Array).map(func(x): return str(x)))
		draw_multiline_string(font, Vector2(36, 560), "The crew: %s" % crew_t, HORIZONTAL_ALIGNMENT_LEFT, size.x - 72.0, 17, 2, INK)
		draw_string(font, Vector2(36, 612), "Kept by %s" % str(d.get("me", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 72.0, 14, FADED)

	func _stats(font: Font) -> void:
		var d := book.diary
		draw_string(font, Vector2(36, 60), "THE ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED)
		_strip(Rect2(36, 76, size.x - 72.0, 170), font)
		_map(Rect2(36, 268, 200, 200))
		draw_string(font, Vector2(258, 282), "THE TRIP COMPUTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED)
		var tc := TripComputer.new()
		var st: Dictionary = d.get("stats", {})
		tc.load_from(st)
		var lines := tc.stats_lines(float(st.get("fuel_left", -1.0)), float(st.get("book", 0.0)))
		var y := 310.0
		for l in lines:
			draw_string(font, Vector2(258, y), str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, 130, 15, FADED)
			draw_string(font, Vector2(388, y), str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 400.0, 16, INK)
			y += 24.0
		var photos: Array = d.get("photos", [])
		var clips := photos.filter(func(p): return bool(p.get("clip", false))).size()
		var films := photos.filter(func(p): return bool(p.get("movie", false))).size()
		draw_string(font, Vector2(36, 520), "%s, %s%s%s." % [DiaryBook.count((d.get("log", []) as Array).size(), "highlight"), DiaryBook.count(photos.size() - clips - films, "photo"),
			(", " + DiaryBook.count(clips, "clip")) if clips > 0 else "", (", " + DiaryBook.count(films, "film")) if films > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, size.x - 72.0, 17, INK)
		# The key to the marks on the strip.
		var kinds := {}
		for e in d.get("log", []):
			kinds[str(e.get("kind", ""))] = true
		var x := 36.0
		var ky := 556.0
		for k in AdventureDiary.KINDS:
			if not kinds.has(k):
				continue
			var info: Dictionary = AdventureDiary.KINDS[k]
			var w := 26.0 + font.get_string_size(str(info["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
			if x + w > size.x - 30.0:
				x = 36.0
				ky += 24.0
			_mark(Vector2(x + 9.0, ky - 5.0), k, font)
			draw_string(font, Vector2(x + 22.0, ky), str(info["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FADED)
			x += w

	## The road's height all the way, coloured by its surface, the highlights marked along it.
	func _strip(r: Rect2, font: Font) -> void:
		var route: Dictionary = book.diary.get("route", {})
		var hs: Array = route.get("h", [])
		draw_rect(r, Color(1, 1, 1, 0.35))
		if hs.size() < 2:
			draw_string(font, r.position + Vector2(0, r.size.y * 0.5), "No route kept", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, FADED)
			return
		var lo := INF
		var hi := -INF
		for h in hs:
			lo = minf(lo, float(h))
			hi = maxf(hi, float(h))
		hi = maxf(hi, lo + 50.0)
		var length := maxf(float(route.get("length", 1.0)), 1.0)
		var base := r.end.y - 18.0
		var top := r.position.y + 26.0
		var pt := func(i: int) -> Vector2:
			return Vector2(r.position.x + r.size.x * float(i) / float(hs.size() - 1), lerpf(base, top, (float(hs[i]) - lo) / (hi - lo)))
		# Filled under the line, a column per sample in its surface's colour.
		var surfs: Array = route.get("surfaces", [])
		for i in hs.size() - 1:
			var s := length * (i + 0.5) / float(hs.size() - 1)
			var surf := "tarmac"
			for seg in surfs:
				if s >= float(seg[0]) and s <= float(seg[1]):
					surf = str(seg[2])
					break
			var a: Vector2 = pt.call(i)
			var b: Vector2 = pt.call(i + 1)
			draw_colored_polygon(PackedVector2Array([a, b, Vector2(b.x, base), Vector2(a.x, base)]), _surf_col(surf))
		var line := PackedVector2Array()
		for i in hs.size():
			line.append(pt.call(i))
		draw_polyline(line, INK, 2.0, true)
		draw_line(Vector2(r.position.x, base), Vector2(r.end.x, base), FADED, 1.0)
		draw_string(font, Vector2(r.position.x, r.end.y - 3.0), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FADED)
		draw_string(font, Vector2(r.position.x, r.end.y - 3.0), "%s" % TripComputer.distance_text(length), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 12, FADED)
		draw_string(font, Vector2(r.position.x, r.end.y - 3.0), "Highest %s" % TripComputer.height_text(hi), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, FADED)   # (along the bottom: the marks fly above)
		# The highlights: a mark on a stalk above the road where each was.
		var placed: Array[float] = []
		for e in book.diary.get("log", []):
			var x := r.position.x + r.size.x * clampf(float(e.get("s", 0.0)) / length, 0.0, 1.0)
			var lift := 0
			for px in placed:
				if absf(px - x) < 14.0:
					lift += 1
			placed.append(x)
			var i := clampi(roundi(clampf(float(e.get("s", 0.0)) / length, 0.0, 1.0) * (hs.size() - 1)), 0, hs.size() - 1)
			var ground: Vector2 = pt.call(i)
			var at := Vector2(x, maxf(r.position.y + 10.0, ground.y - 16.0 - lift * 15.0))
			draw_line(Vector2(x, ground.y), at, Color(INK, 0.5), 1.0)
			_mark(at, str(e.get("kind", "")), font)

	func _surf_col(surf: String) -> Color:
		return {"tarmac": Color(0.55, 0.6, 0.55, 0.55), "gravel": Color(0.75, 0.62, 0.42, 0.65), "sand": Color(0.92, 0.78, 0.5, 0.7),
			"snow": Color(0.85, 0.9, 0.97, 0.9)}.get(surf, Color(0.6, 0.6, 0.6, 0.5))

	## A highlight's mark: a disc in its colour with its letter.
	func _mark(at: Vector2, kind: String, font: Font) -> void:
		var info: Dictionary = AdventureDiary.KINDS.get(kind, {"mark": "?", "col": Color.GRAY})
		draw_circle(at, 8.0, info["col"])
		draw_arc(at, 8.0, 0.0, TAU, 16, INK, 1.0, true)
		draw_string(font, at + Vector2(-8, 4.5), str(info["mark"]), HORIZONTAL_ALIGNMENT_CENTER, 16, 11, INK)

	## The road from above, in a box: the start and the end marked.
	func _map(r: Rect2) -> void:
		var pts: Array = book.diary.get("route", {}).get("pts", [])
		draw_rect(r, Color(1, 1, 1, 0.35))
		draw_rect(r, Color(INK, 0.4), false, 1.0)
		if pts.size() < 2:
			return
		var box := Rect2(Vector2(float(pts[0][0]), float(pts[0][1])), Vector2.ZERO)
		for p in pts:
			box = box.expand(Vector2(float(p[0]), float(p[1])))
		var k := minf((r.size.x - 24.0) / maxf(box.size.x, 1.0), (r.size.y - 24.0) / maxf(box.size.y, 1.0))
		var off := r.get_center() - box.get_center() * k
		var line := PackedVector2Array()
		for p in pts:
			line.append(off + Vector2(float(p[0]), float(p[1])) * k)
		draw_polyline(line, Color(RED, 0.85), 2.5, true)
		draw_circle(line[0], 5.0, Color(0.2, 0.6, 0.3))
		draw_circle(line[line.size() - 1], 5.0, RED)

	func _photos(font: Font) -> void:
		var list: Array = page.get("photos", [])
		for i in list.size():
			var p: Dictionary = list[i]
			var tilt: float = [-2.5, 2.0, 1.5, -1.8][(int(page.get("first", 0)) + i) % 4]
			var box := DiaryBook.photo_box(i)
			var tex := book.texture_of(str(p.get("file", "")))
			var region := Rect2()
			if bool(p.get("clip", false)) and tex != null:
				var cols := maxi(1, int(p.get("cols", PhotoCapture.CLIP_COLS)))
				var frames := maxi(1, int(p.get("got", p.get("frames", PhotoCapture.CLIP_FRAMES))))
				var f := _frame % frames
				var cw := float(p.get("cell_w", PhotoCapture.CLIP_W))
				var chh := float(p.get("cell_h", PhotoCapture.CLIP_H))
				region = Rect2((f % cols) * cw, (f / cols) * chh, cw, chh)
			var e := book.entry_of(p)
			var cap := str(e.get("text", p.get("caption", ""))) if not e.is_empty() else str(p.get("caption", ""))
			var when := AdventureDiary.when_text(p if e.is_empty() else e)
			var by := str(p.get("by", ""))
			if by != "" and by != str(book.diary.get("me", "")):
				when += "  ·  taken by %s" % by
			_polaroid(box, tex, tilt, cap, font, region, when, bool(p.get("clip", false)),
				roundi(float(p.get("secs", 0.0))) if bool(p.get("movie", false)) else -1)

	## A photo taped in at `deg`: the picture (a clip's `region` of it), with its caption written
	## under it and the when, where and who smaller below.
	func _polaroid(box: Rect2, tex: Texture2D, deg: float, caption: String, font: Font, region: Rect2, when := "", clip := false, film := -1) -> void:
		var c := box.get_center()
		draw_set_transform(c, deg_to_rad(deg), Vector2.ONE)
		var r := Rect2(-box.size * 0.5, box.size)
		var frame := Rect2(r.position - Vector2(10, 10), r.size + Vector2(20, 20 + (46.0 if caption != "" else 0.0)))
		draw_rect(Rect2(frame.position + Vector2(4, 6), frame.size), Color(0, 0, 0, 0.22))
		draw_rect(frame, Color(1, 1, 1))
		if tex != null:
			if region.has_area():
				draw_texture_rect_region(tex, r, region)
			else:
				draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color(0.2, 0.2, 0.22))
			draw_string(font, r.position + Vector2(0, r.size.y * 0.5), "(no picture)", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(1, 1, 1, 0.5))
		if clip:
			draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(58, 22)), Color(0, 0, 0, 0.6))
			draw_colored_polygon(PackedVector2Array([r.position + Vector2(15, 12), r.position + Vector2(15, 26), r.position + Vector2(27, 19)]), Color(1, 0.3, 0.25))
			draw_string(font, r.position + Vector2(31, 25), "CLIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if film >= 0:
			draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(92, 22)), Color(0, 0, 0, 0.6))
			draw_colored_polygon(PackedVector2Array([r.position + Vector2(15, 12), r.position + Vector2(15, 26), r.position + Vector2(27, 19)]), Color(1, 0.3, 0.25))
			draw_string(font, r.position + Vector2(31, 25), "FILM %d s" % film, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if caption != "":
			draw_string(font, Vector2(r.position.x, r.end.y + 26.0), caption, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 19, INK)
			draw_string(font, Vector2(r.position.x, r.end.y + 48.0), when, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, FADED)
		# Tape across two corners.
		draw_set_transform(c + (r.position + Vector2(8, -2)).rotated(deg_to_rad(deg)), deg_to_rad(deg - 35.0), Vector2.ONE)
		draw_rect(Rect2(-36, -11, 72, 22), TAPE)
		draw_set_transform(c + (Vector2(r.end.x - 8, r.position.y - 2)).rotated(deg_to_rad(deg)), deg_to_rad(deg + 35.0), Vector2.ONE)
		draw_rect(Rect2(-36, -11, 72, 22), TAPE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _log(font: Font) -> void:
		draw_string(font, Vector2(36, 60), "THE LOG" if int(page.get("first", 0)) == 0 else "THE LOG, GO ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED)
		var y := 96.0
		var entries: Array = page.get("entries", [])
		for i in entries.size():
			var e: Dictionary = entries[i]
			_mark(Vector2(48, y - 5.0), str(e.get("kind", "")), font)
			if i < entries.size() - 1:
				draw_line(Vector2(48, y + 4.0), Vector2(48, y + 33.0), Color(INK, 0.3), 1.0)
			draw_string(font, Vector2(66, y), str(e.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 100.0, 17, INK)
			draw_string(font, Vector2(66, y + 17.0), AdventureDiary.when_text(e), HORIZONTAL_ALIGNMENT_LEFT, size.x - 100.0, 12, FADED)
			y += 40.0
