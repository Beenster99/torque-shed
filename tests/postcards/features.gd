extends RefCounted
## The postcards' features sheet (phase D, docs/scenery.md): for each place drawn on the road network, a map of the
## scenery the map gives round its road view (RealRegion.features, coloured by the round that models each kind) beside
## that view's scenery as the ride draws it (the round models, and the stand-ins of kinds no round has modelled yet),
## with how many there are of each. So a round's pull request shows what it places, place by place, and a place where
## the map gives little shows up as such.

const Standin := preload("res://scripts/scenery/standin.gd")
## The map: this far each way from the view's spot (m), drawn this many pixels a side.
const HALF := 1500.0
const MAP_PX := 450
const SHOT := Vector2i(800, 450)
const PAD := 18
const GAP := 10
const HEAD_H := 90
const CAPTION_H := 92
const BACK := Color(0.11, 0.115, 0.125)
const LAND := Color(0.16, 0.17, 0.165)
const ROAD := Color(0.97, 0.97, 0.94)
const INK := Color(0.93, 0.93, 0.9)
const FAINT := Color(0.62, 0.64, 0.66)
## How long the scenery round a view may take to come in before it's drawn as it is (ms).
const SETTLE_MS := 30000
## The kinds a place's caption names (its commonest).
const KINDS_SHOWN := 8


## What of `region`'s features is within `half` of region point `centre` (each way): {"total", "rounds": {round: n},
## "kinds": {kind: n}}. A line or area counts once when its box meets the square.
static func count(region: RealRegion, centre: Vector2, half := HALF) -> Dictionary:
	var box := Rect2(centre - Vector2.ONE * half, Vector2.ONE * half * 2.0)
	var out := {"total": 0, "rounds": {}, "kinds": {}}
	for part: String in ["points", "lines", "areas"]:
		for row: Array in region.features.get(part, []):
			var inside := false
			if part == "points":
				inside = box.has_point(Vector2(float(row[1]), float(row[2])))
			else:
				inside = box.intersects(_box(row[1]))
			if not inside:
				continue
			var kind := str(row[0])
			var r := str(SceneryStreamer.kit(kind).get("round", "?"))
			out["total"] += 1
			out["rounds"][r] = int(out["rounds"].get(r, 0)) + 1
			out["kinds"][kind] = int(out["kinds"].get(kind, 0)) + 1
	return out


## The map round region point `centre`: the roads grey, each feature in its round's colour (areas as outlines, lines,
## points as dots), north up, the view's spot a white ring.
static func map(region: RealRegion, centre: Vector2, half := HALF, px := MAP_PX) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(LAND)
	var to_px := func(p: Vector2) -> Vector2: return (p - centre + Vector2.ONE * half) / (half * 2.0) * float(px)
	var box := Rect2(centre - Vector2.ONE * half * 1.2, Vector2.ONE * half * 2.4)
	var colour := {}
	for part: String in ["areas", "lines", "points"]:
		for row: Array in region.features.get(part, []):
			var kind := str(row[0])
			if not colour.has(kind):
				colour[kind] = Standin.ROUND_COLOURS.get(str(SceneryStreamer.kit(kind).get("round", "")), Color(0.9, 0.9, 0.9))
			if part == "points":
				var q: Vector2 = to_px.call(Vector2(float(row[1]), float(row[2])))
				_dot(img, q, 2, colour[kind])
			elif box.intersects(_box(row[1])):
				_poly(img, row[1], to_px, colour[kind], part == "areas")
	# (the roads over the features, so they're found among the walls)
	for line: PackedVector2Array in region.edge_line:
		if not line.is_empty() and box.intersects(_box(line)):
			_poly(img, line, to_px, ROAD, false, 1)
	var mid := Vector2.ONE * float(px) * 0.5
	for a in 48:
		var t := TAU * a / 48.0
		_dot(img, mid + Vector2(cos(t), sin(t)) * 9.0, 1, Color.WHITE)
	return img


## Waits for `w`'s scenery round its riders to come in (every wanted block with something in it laid out and put in), up
## to SETTLE_MS: whether it all did.
static func settle(w: AdventureWorld, host: Node) -> bool:
	var s := w.scenery
	if s == null:
		return false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < SETTLE_MS:
		await host.get_tree().process_frame
		var at := s.riders()
		# (the near blocks: the far ones, of things seen from afar, keep coming in after)
		var want := RoadStreamer.wanted(at, SceneryStreamer.REACH * 0.5).filter(func(k): return s._filed.has(k))
		if want.all(func(k): return s.blocks.has(k)):
			return true
	return false


## The features sheet of `stats` (postcards.gd's, its places' "features"), the pictures read from `dir`; null when no
## place has any.
static func sheet(host: Node, stats: Dictionary, dir: String) -> Image:
	var places: Array = stats["places"].filter(func(p): return (p as Dictionary).has("features"))
	if places.is_empty():
		return null
	var row_h := SHOT.y + CAPTION_H + GAP
	var size := Vector2i(PAD * 2 + MAP_PX + GAP + SHOT.x, HEAD_H + places.size() * row_h + PAD)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var back := ColorRect.new()
	back.color = BACK
	back.size = size
	vp.add_child(back)
	var title := "Torque Shed postcards: scenery from the map"
	if str(stats.get("label", "")) != "":
		title += "  ·  %s" % stats["label"]
	_text(vp, title, Vector2(PAD, 12), 26, INK)
	_text(vp, "The %.0f km square round each place's road view: the map (north up, roads white), and the road from above with the scenery drawn (stand-in posts for the kinds no round has modelled yet)." % [
		HALF * 2.0 / 1000.0], Vector2(PAD, 42), 14, FAINT)
	_text(vp, "Rounds:", Vector2(PAD, 64), 14, FAINT)
	var x_key := PAD + 64
	for r: String in Standin.ROUND_COLOURS:
		var sw := ColorRect.new()
		sw.color = Standin.ROUND_COLOURS[r]
		sw.position = Vector2(x_key, 68)
		sw.size = Vector2(12, 12)
		vp.add_child(sw)
		_text(vp, r, Vector2(x_key + 15, 64), 14, FAINT)
		x_key += 52
	var y := HEAD_H
	for p: Dictionary in places:
		for i in 2:
			var path := dir.path_join("%s-net_%s.png" % [p["id"], "features" if i == 0 else "scenery"])
			var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if img == null:
				continue
			var at := Vector2(PAD, y) if i == 0 else Vector2(PAD + MAP_PX + GAP, y)
			var want := Vector2i(MAP_PX, MAP_PX) if i == 0 else SHOT
			img.resize(want.x, want.y, Image.INTERPOLATE_LANCZOS)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = at
			tr.size = want
			vp.add_child(tr)
		var f: Dictionary = p["features"]
		var cap := _text(vp, caption(p, f), Vector2(PAD, y + MAP_PX + 4), 13, INK)
		cap.size = Vector2(size.x - PAD * 2, CAPTION_H)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		y += row_h
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var out := vp.get_texture().get_image()
	vp.queue_free()
	return out


## Place `p`'s caption from its features count `f`: what it is, how many by round, its commonest kinds.
static func caption(p: Dictionary, f: Dictionary) -> String:
	var rounds: Dictionary = f.get("rounds", {})
	var by_round := PackedStringArray()
	var names := rounds.keys()
	names.sort()
	for r in names:
		by_round.append("%s %d" % [r, int(rounds[r])])
	var kinds: Array = (f.get("kinds", {}) as Dictionary).keys()
	kinds.sort_custom(func(a, b): return int(f["kinds"][a]) > int(f["kinds"][b]) if int(f["kinds"][a]) != int(f["kinds"][b]) else str(a) < str(b))
	var top := PackedStringArray()
	for k in kinds.slice(0, KINDS_SHOWN):
		top.append("%s %d" % [str(k).replace("_", " "), int(f["kinds"][k])])
	var t := "%s: %d things from the map (%s)" % [p.get("title", p["id"]), int(f.get("total", 0)), ", ".join(by_round) if not by_round.is_empty() else "none"]
	if not top.is_empty():
		t += "\ncommonest: " + ", ".join(top)
	t += "\nscenery drawn round the view: %d things in %d blocks%s" % [int(f.get("drawn", 0)), int(f.get("blocks", 0)),
		"" if bool(f.get("settled", true)) else " (not all in)"]
	return t


static func _box(line: PackedVector2Array) -> Rect2:
	var r := Rect2(line[0], Vector2.ZERO)
	for p in line:
		r = r.expand(p)
	return r


static func _poly(img: Image, line: PackedVector2Array, to_px: Callable, c: Color, closed: bool, r := 0) -> void:
	var n := line.size()
	for i in (n if closed else n - 1):
		_line(img, to_px.call(line[i]), to_px.call(line[(i + 1) % n]), c, r)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, r := 0) -> void:
	var steps := int(ceilf(maxf(absf(b.x - a.x), absf(b.y - a.y))))
	if steps > 4 * img.get_width():
		return   # (far off the map: not worth walking)
	for i in steps + 1:
		var q := a.lerp(b, float(i) / maxf(1.0, float(steps)))
		_dot(img, q, r, c)


static func _dot(img: Image, q: Vector2, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := int(q.x) + dx
			var y := int(q.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


static func _text(parent: Node, text: String, at: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l
