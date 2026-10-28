extends RefCounted
## The postcards' contact sheet: a row a place, its four views beside what it is and how it ran (postcards.gd's stats),
## drawn by the game's own UI in a viewport of its own and handed back as one image. A place drawn on the road network
## too has that row under its own, with what the network's lacks beside it (the gap: postcards.gd's measure), and the
## heading sums the gap up over every place.

const THUMB := Vector2i(400, 225)
const INFO_W := 340
const GAP := 10
const PAD := 18
const HEAD_H := 64
const GAP_H := 46
const CAPTION_H := 24
const BACK := Color(0.11, 0.115, 0.125)
const NET_BACK := Color(0.13, 0.145, 0.17)
const INK := Color(0.93, 0.93, 0.9)
const FAINT := Color(0.62, 0.64, 0.66)
const WARN := Color(1.0, 0.72, 0.3)
const BAD := Color(1.0, 0.42, 0.38)
## A view whose 95th percentile frame is slower than this (ms, on the machine that made the sheet) is marked.
const SLOW_P95 := 1.6
## The kinds of thing the network's row names as missing (those it has the fewest of, against the single road's).
const MISSING_SHOWN := 6
## Kinds of thing that are trees (by the last word of the kind's name): counted apart from the rest by the road, as the
## network plants its own (the tree bake's) where the single road scatters its theme's.
const TREES := ["tree", "oak", "pine", "acacia", "cedar", "olive", "palm", "birch", "fir", "spruce", "cypress",
	"eucalyptus", "kauri", "willow", "poplar", "beech", "larch"]


## The sheet for `stats` (postcards.gd), its pictures read from `dir`. Waits a couple of frames for it to draw.
static func make(host: Node, spec: Dictionary, stats: Dictionary, dir: String) -> Image:
	var views: Array = spec["views"]
	var places: Array = stats["places"]
	var row_h := THUMB.y + CAPTION_H + GAP
	var pairs := pairs_of(places)
	var head_h := HEAD_H + (GAP_H if not pairs.is_empty() else 0)
	var size := Vector2i(PAD * 2 + INFO_W + views.size() * (THUMB.x + GAP), head_h + places.size() * row_h + PAD)
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
		Time.get_date_string_from_system(), _count_places(places), float(stats.get("seconds", 0.0)),
		str(stats.get("preset", "")).capitalize(), str(stats.get("renderer", ""))], Vector2(PAD, 42), 14, FAINT)
	if not pairs.is_empty():
		_text(vp, gap_line(pairs), Vector2(PAD, HEAD_H), 15, WARN)
	var y := head_h
	var single := {}
	for p: Dictionary in places:
		var x := PAD
		var on_net := str(p.get("mode", "single")) == "network"
		if on_net:
			var band := ColorRect.new()
			band.color = NET_BACK
			band.position = Vector2(PAD * 0.5, y - GAP * 0.5)
			band.size = Vector2(size.x - PAD, row_h)
			vp.add_child(band)
		var info := "%s\n" % p.get("title", p["id"]) if not on_net else "The same, on the road network\n"
		if str(p.get("error", "")) != "":
			info += "Couldn't be laid out:\n%s" % p["error"]
		else:
			if not on_net:
				if str(p.get("profile", "")) != "":
					info += "%s\n" % p["profile"]
				info += "%s km ride, %s\n" % [p.get("km", 0), p.get("theme", "")]
			info += "laid out in %.1f s, %d nodes\nmemory %.0f MB, video %.0f MB" % [float(p.get("load_s", 0.0)),
				int(p.get("nodes", 0)), float(p.get("static_mb", 0.0)), float(p.get("video_mb", 0.0))]
			if p.has("gap"):
				var mine: Dictionary = (single.get(p["id"], {}) as Dictionary).get("gap", {}) if on_net else {}
				info += "\n" + gap_text(p["gap"], mine)
		if not on_net:
			single[p["id"]] = p
		var lab := _text(vp, info, Vector2(x, y + 4), 13, INK if str(p.get("error", "")) == "" else BAD)
		lab.size = Vector2(INFO_W - 12, THUMB.y)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		x += INFO_W
		for view: String in views:
			var path := dir.path_join("%s%s_%s.png" % [p["id"], "-net" if on_net else "", view])
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


## The places drawn both ways: [[single, network], ...], each laid out without error.
static func pairs_of(places: Array) -> Array:
	var single := {}
	var out := []
	for p: Dictionary in places:
		if str(p.get("error", "")) != "" or not p.has("gap"):
			continue
		if str(p.get("mode", "single")) == "network":
			if single.has(p["id"]):
				out.append([single[p["id"]], p])
		else:
			single[p["id"]] = p
	return out


## A place's gap (postcards.gd's measure) in words; on the network, against `single`'s (the same place's single road).
static func gap_text(gap: Dictionary, single: Dictionary) -> String:
	var things: Dictionary = gap.get("things", {})
	var t := "road %d points, bumps %.1f cm (worst %.1f), kink %.1f°" % [int(gap.get("road_pts", 0)),
		float(gap.get("bumps_cm", 0.0)), float(gap.get("bump_max_cm", 0.0)), float(gap.get("kink_deg", 0.0))]
	if float(gap.get("found", 1.0)) < 1.0:
		t += ", under %d%% of the plan" % roundi(float(gap["found"]) * 100.0)
	var mine := _split(things)
	t += "\nby the road: %d trees, %d other things" % mine
	if single.is_empty():
		return t
	var theirs := _split(single.get("things", {}))
	t += " (%s, %s)" % [_signed(mine[0] - theirs[0]), _signed(mine[1] - theirs[1])]
	var missing := missing_of(things, single.get("things", {})).filter(func(m): return not is_tree(m[0]))
	if not missing.is_empty():
		var shown: Array = missing.slice(0, MISSING_SHOWN).map(func(m): return "%s %s" % [m[0], _signed(-int(m[1]))])
		var lines: Array[String] = []
		for i in range(0, shown.size(), 3):
			lines.append(", ".join(shown.slice(i, i + 3)))
		t += "\nfewer: " + ",\n".join(lines)
	return t


## Whether things of kind `kind` (postcards.gd's measure) are trees.
static func is_tree(kind: String) -> bool:
	return TREES.has(kind.get_slice(" ", kind.get_slice_count(" ") - 1))


## How many of `things` are trees, and how many aren't: [trees, others].
static func _split(things: Dictionary) -> Array:
	var out := [0, 0]
	for k: String in things:
		out[0 if is_tree(k) else 1] += int(things[k])
	return out


## The kinds of thing there are fewer of in `things` than in `single`: [[kind, how many fewer], ...], most first.
static func missing_of(things: Dictionary, single: Dictionary) -> Array:
	var out := []
	for k: String in single:
		var short := int(single[k]) - int(things.get(k, 0))
		if short > 0:
			out.append([k, short])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]) if int(a[1]) != int(b[1]) else str(a[0]) < str(b[0]))
	return out


## The heading's line on the gap between the network and the single road over every place drawn both ways.
static func gap_line(pairs: Array) -> String:
	var trees := [0, 0]
	var others := [0, 0]
	var bumps := [0.0, 0.0]
	var worst := [0.0, 0.0]
	var load := [0.0, 0.0]
	var gone := {}
	for pair: Array in pairs:
		for i in 2:
			var g: Dictionary = pair[i]["gap"]
			var split := _split(g.get("things", {}))
			trees[i] += split[0]
			others[i] += split[1]
			bumps[i] += float(g.get("bumps_cm", 0.0))
			worst[i] = maxf(worst[i], float(g.get("bump_max_cm", 0.0)))
			load[i] += float(pair[i].get("load_s", 0.0))
		for m: Array in missing_of(pair[1]["gap"].get("things", {}), pair[0]["gap"].get("things", {})):
			if int(pair[1]["gap"]["things"].get(m[0], 0)) == 0 and not is_tree(m[0]):
				gone[m[0]] = true
	var n := float(pairs.size())
	var line := "The road network against the single road, %d places: %d%% of the roadside things and %d%% of the trees, bumps %.1f cm against %.1f (worst %.1f against %.1f), laid out in %.0f s against %.0f" % [
		pairs.size(), roundi(100.0 * others[1] / maxf(1.0, others[0])), roundi(100.0 * trees[1] / maxf(1.0, trees[0])),
		bumps[1] / n, bumps[0] / n, worst[1], worst[0], load[1] / n, load[0] / n]
	if not gone.is_empty():
		var kinds := gone.keys()
		kinds.sort()
		line += "\nNone at all on the network of: " + ", ".join(kinds)
	return line


static func _signed(n: int) -> String:
	return ("+%d" if n > 0 else "%d") % n


## How many places there are among `places`, a place drawn both ways counted once.
static func _count_places(places: Array) -> int:
	var ids := {}
	for p: Dictionary in places:
		ids[p["id"]] = true
	return ids.size()


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
