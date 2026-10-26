extends RefCounted
## The postcards' contact sheet: a row a place, its four views beside what it is and how it ran (postcards.gd's stats),
## drawn by the game's own UI in a viewport of its own and handed back as one image.

const THUMB := Vector2i(400, 225)
const INFO_W := 300
const GAP := 10
const PAD := 18
const HEAD_H := 64
const CAPTION_H := 24
const BACK := Color(0.11, 0.115, 0.125)
const INK := Color(0.93, 0.93, 0.9)
const FAINT := Color(0.62, 0.64, 0.66)
const WARN := Color(1.0, 0.72, 0.3)
const BAD := Color(1.0, 0.42, 0.38)
## A view whose 95th percentile frame is slower than this (ms, on the machine that made the sheet) is marked.
const SLOW_P95 := 1.6


## The sheet for `stats` (postcards.gd), its pictures read from `dir`. Waits a couple of frames for it to draw.
static func make(host: Node, spec: Dictionary, stats: Dictionary, dir: String) -> Image:
	var views: Array = spec["views"]
	var places: Array = stats["places"]
	var row_h := THUMB.y + CAPTION_H + GAP
	var size := Vector2i(PAD * 2 + INFO_W + views.size() * (THUMB.x + GAP), HEAD_H + places.size() * row_h + PAD)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var back := ColorRect.new()
	back.color = BACK
	back.size = size
	vp.add_child(back)
	var title := "Torque Shed postcards"
	if str(stats.get("version", "")) != "":
		title += "  v%s" % stats["version"]
	if str(stats.get("label", "")) != "":
		title += "  ·  %s" % stats["label"]
	_text(vp, title, Vector2(PAD, 12), 26, INK)
	var typical := _typical(places)
	_text(vp, "%s  ·  %d places in %.0f s  ·  %s graphics on %s  ·  frame times (mean, 95th percentile) are this machine's: compare them run to run, not with a player's PC" % [
		Time.get_date_string_from_system(), places.size(), float(stats.get("seconds", 0.0)), str(stats.get("preset", "")).capitalize(),
		str(stats.get("renderer", ""))], Vector2(PAD, 42), 14, FAINT)
	var y := HEAD_H
	for p: Dictionary in places:
		var x := PAD
		var info := "%s\n" % p.get("title", p["id"])
		if str(p.get("error", "")) != "":
			info += "Couldn't be laid out:\n%s" % p["error"]
		else:
			info += "%s km ride, %s\nlaid out in %.1f s\nmemory %.0f MB, video %.0f MB\n%d nodes" % [
				p.get("km", 0), p.get("theme", ""), float(p.get("load_s", 0.0)), float(p.get("static_mb", 0.0)),
				float(p.get("video_mb", 0.0)), int(p.get("nodes", 0))]
		var lab := _text(vp, info, Vector2(x, y + 4), 15, INK if str(p.get("error", "")) == "" else BAD)
		lab.size = Vector2(INFO_W - 12, THUMB.y)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		x += INFO_W
		for view: String in views:
			var path := dir.path_join("%s_%s.png" % [p["id"], view])
			var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if img != null:
				img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
				var tr := TextureRect.new()
				tr.texture = ImageTexture.create_from_image(img)
				tr.position = Vector2(x, y)
				tr.size = THUMB
				vp.add_child(tr)
			var v: Dictionary = (p.get("views", {}) as Dictionary).get(view, {})
			var cap := view
			var colour := FAINT
			if v.has("ms"):
				cap = "%s  ·  %.1f ms (95%%: %.1f)  ·  %d draws" % [view, float(v["ms"]), float(v["p95"]), int(v["draws"])]
				if float(v["p95"]) > typical * SLOW_P95 or not bool(v.get("settled", true)):
					colour = WARN
				if not bool(v.get("settled", true)):
					cap += "  ·  not all built"
			_text(vp, cap, Vector2(x, y + THUMB.y + 3), 13, colour)
			x += THUMB.x + GAP
		y += row_h
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var out := vp.get_texture().get_image()
	vp.queue_free()
	return out


## The median of every view's 95th percentile frame time, what a slow view is measured against.
static func _typical(places: Array) -> float:
	var all: Array[float] = []
	for p: Dictionary in places:
		for v: Dictionary in (p.get("views", {}) as Dictionary).values():
			if v.has("p95"):
				all.append(float(v["p95"]))
	if all.is_empty():
		return INF
	all.sort()
	return all[all.size() / 2]


static func _text(parent: Node, text: String, at: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l
