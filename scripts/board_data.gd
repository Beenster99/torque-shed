class_name BoardData
extends RefCounted
## What's on the shed whiteboard. It lives in Shed.board so it's shared, synced to late
## joiners and saved with the rest of the shed: {marks: [...]}, drawn in order over the white
## board, each one a pen stroke, a rub of the eraser (a stroke in the board's own white) or a
## line of typed text. Every mark remembers who made it. Positions are board pixels (PX).
##   stroke: {id, peer, by, c (colour index, ERASER for the eraser), w (width), pts}
##   text:   {id, peer, by, c, s (font size), at (top left), text}
##   image:  {id, peer, by, img (its Shed.blobs id), at (top left), sz (size on the board)}
## Players send ops through Shed.board_request(): board_draw adds points to a stroke (pts
## replace the stroke's points from index `from` on, so a resend does no harm), board_text,
## board_undo and board_clear, board_image puts a picture up (its bytes go first, see
## Shed.share_blob) and board_move moves or sizes one. The host passes on what it accepts, and
## board_remove for marks it tidies away.

const PX := Vector2(1200.0, 600.0)
const BG := Color(0.95, 0.96, 0.965)
const COLORS := [Color(0.08, 0.08, 0.1), Color(0.08, 0.24, 0.78), Color(0.82, 0.1, 0.1), Color(0.05, 0.55, 0.2),
	Color(0.96, 0.5, 0.04), Color(0.5, 0.14, 0.66)]
const COLOR_NAMES := ["Black", "Blue", "Red", "Green", "Orange", "Purple"]
const WIDTHS := [3.0, 6.0, 11.0, 20.0]
const WIDTH_NAMES := ["Fine", "Medium", "Thick", "Marker"]
const TEXT_SIZES := [26, 38, 54, 76]
const ERASER := -1
const ERASER_WIDTH := 50.0
const MAX_MARKS := 500
const MAX_POINTS := 20000       # across the whole board: past it the oldest marks are wiped
const MAX_STROKE_POINTS := 256  # a longer line carries on as a new stroke (see Whiteboard.SPLIT_AT)
const MAX_TEXT := 60
## Pictures from players' PCs: at most this many on the board, each stored at most IMAGE_PX
## on its longest side (see Shed.blobs), shown at least IMAGE_MIN board pixels across.
const MAX_IMAGES := 12
const IMAGE_PX := 512
const IMAGE_MIN := 24.0
const IMAGE := -2    # what ink_at() gives over a picture


static func empty() -> Dictionary:
	return {"marks": []}


static func is_eraser(m: Dictionary) -> bool:
	return int(m.get("c", 0)) == ERASER and not m.has("text")


static func color_of(m: Dictionary) -> Color:
	var c := int(m.get("c", 0))
	return BG if c == ERASER else COLORS[clampi(c, 0, COLORS.size() - 1)]


static func find(board: Dictionary, id: int) -> int:
	var marks: Array = board.get("marks", [])
	for i in range(marks.size() - 1, -1, -1):
		if int(marks[i]["id"]) == id:
			return i
	return -1


## A player's request, checked and tidied into the op everyone applies, or {} to ignore it.
static func clean(op: Dictionary, peer: int, author: String) -> Dictionary:
	var a := str(op.get("a", ""))
	var id := int(op.get("id", 0))
	match a:
		"board_draw":
			var raw = op.get("pts", null)
			var pts := PackedVector2Array()
			if raw is PackedVector2Array:
				pts = raw
			elif raw is Array:
				for p in raw:
					if p is Vector2:
						pts.append(p)
			if id <= 0 or pts.is_empty() or pts.size() > MAX_STROKE_POINTS:
				return {}
			for i in pts.size():
				pts[i] = pts[i].clamp(Vector2.ZERO, PX)
			var c := clampi(int(op.get("c", 0)), ERASER, COLORS.size() - 1)
			var w := ERASER_WIDTH if c == ERASER else clampf(float(op.get("w", WIDTHS[1])), 1.0, 40.0)
			return {"a": a, "id": id, "peer": peer, "by": author, "c": c, "w": w,
				"from": clampi(int(op.get("from", 0)), 0, MAX_STROKE_POINTS), "pts": pts, "done": bool(op.get("done", false))}
		"board_text":
			var text := str(op.get("text", "")).strip_edges().left(MAX_TEXT)
			var at = op.get("at", null)
			if id <= 0 or text == "" or not at is Vector2:
				return {}
			return {"a": a, "id": id, "peer": peer, "by": author, "c": clampi(int(op.get("c", 0)), 0, COLORS.size() - 1),
				"s": clampi(int(op.get("s", TEXT_SIZES[1])), 12, 120), "at": (at as Vector2).clamp(Vector2.ZERO, PX), "text": text}
		"board_image", "board_move":
			var at = op.get("at", null)
			var sz = op.get("sz", null)
			if id <= 0 or not at is Vector2 or not sz is Vector2:
				return {}
			var size := (sz as Vector2).clamp(Vector2(IMAGE_MIN, IMAGE_MIN), PX)
			var out := {"a": a, "id": id, "peer": peer, "by": author, "sz": size,
				"at": (at as Vector2).clamp(Vector2.ZERO, PX - size)}
			if a == "board_image":
				out["img"] = int(op.get("img", 0))
				if int(out["img"]) <= 0:
					return {}
			return out
		"board_undo", "board_clear", "board_poster":
			return {"a": a, "peer": peer, "by": author}
	return {}


static func is_image(m: Dictionary) -> bool:
	return m.has("img")


static func image_count(board: Dictionary) -> int:
	return board.get("marks", []).filter(func(m): return is_image(m)).size()


## The picture mark under `p` (board pixels), topmost first, or 0.
static func image_at(board: Dictionary, p: Vector2) -> int:
	var marks: Array = board.get("marks", [])
	for i in range(marks.size() - 1, -1, -1):
		if is_image(marks[i]) and bounds(marks[i]).has_point(p):
			return int(marks[i]["id"])
	return 0


## The Shed.blobs ids the marks show.
static func images_in(marks: Array) -> Array:
	var out := []
	for m in marks:
		if m is Dictionary and m.has("img") and not out.has(int(m["img"])):
			out.append(int(m["img"]))
	return out


## Applies a cleaned op to the board. True when something changed.
static func apply(board: Dictionary, op: Dictionary) -> bool:
	if not board.has("marks"):
		board["marks"] = []
	var marks: Array = board["marks"]
	match str(op.get("a", "")):
		"board_draw":
			var i := find(board, int(op["id"]))
			var pts: PackedVector2Array = op["pts"]
			if i < 0:
				# A stroke cleared away mid-line just starts again from here.
				marks.append({"id": int(op["id"]), "peer": int(op["peer"]), "by": str(op["by"]), "c": int(op["c"]),
					"w": float(op["w"]), "pts": pts})
				return true
			var m: Dictionary = marks[i]
			if m.has("text") or m.has("img") or int(m.get("peer", 0)) != int(op["peer"]):
				return false
			var old: PackedVector2Array = m["pts"]
			var merged := old.slice(0, mini(int(op["from"]), old.size()))
			merged.append_array(pts)
			if merged.size() > MAX_STROKE_POINTS:
				return false
			m["pts"] = merged
			return true
		"board_text":
			if find(board, int(op["id"])) >= 0:
				return false
			marks.append({"id": int(op["id"]), "peer": int(op["peer"]), "by": str(op["by"]), "c": int(op["c"]),
				"s": int(op["s"]), "at": op["at"], "text": str(op["text"])})
			return true
		"board_image":
			if find(board, int(op["id"])) >= 0:
				return false
			marks.append({"id": int(op["id"]), "peer": int(op["peer"]), "by": str(op["by"]), "img": int(op["img"]),
				"at": op["at"], "sz": op["sz"]})
			return true
		"board_move":
			var k := find(board, int(op["id"]))
			if k < 0 or not is_image(marks[k]):
				return false
			if marks[k]["at"] == op["at"] and marks[k]["sz"] == op["sz"]:
				return false
			marks[k]["at"] = op["at"]
			marks[k]["sz"] = op["sz"]
			return true
		"board_remove":
			var ids: Array = op.get("ids", [])
			var before := marks.size()
			for i in range(marks.size() - 1, -1, -1):
				if ids.has(int(marks[i]["id"])):
					marks.remove_at(i)
			return marks.size() != before
		"board_clear":
			var had := not marks.is_empty()
			marks.clear()
			return had
	return false


## The newest mark `peer` made, for undo, or 0.
static func last_of(board: Dictionary, peer: int) -> int:
	var marks: Array = board.get("marks", [])
	for i in range(marks.size() - 1, -1, -1):
		if int(marks[i].get("peer", 0)) == peer:
			return int(marks[i]["id"])
	return 0


## Marks the host wipes once mark `id` is finished: anything it rubbed out completely, erasers
## left with no ink under them, and the oldest marks once the board holds too much.
static func tidy(board: Dictionary, id: int) -> Array:
	var marks: Array = board.get("marks", [])
	var gone := {}
	var boxes := []
	for m in marks:
		boxes.append(bounds(m))
	var i := find(board, id)
	if i >= 0 and is_eraser(marks[i]):
		for j in i:
			if not is_eraser(marks[j]) and _rubbed_out(marks[j], boxes[j], marks[i], boxes[i]):
				gone[int(marks[j]["id"])] = true
		# Erasers over what was just wiped (and this one) may have nothing left to cover.
		for k in range(i, -1, -1):
			if not is_eraser(marks[k]) or gone.has(int(marks[k]["id"])):
				continue
			if k != i and not (boxes[k] as Rect2).intersects(boxes[i]):
				continue
			var under := false
			for j in k:
				if not is_eraser(marks[j]) and not gone.has(int(marks[j]["id"])) and (boxes[j] as Rect2).intersects(boxes[k]):
					under = true
					break
			if not under:
				gone[int(marks[k]["id"])] = true
	var count := marks.size() - gone.size()
	var points := 0
	for m in marks:
		if not gone.has(int(m["id"])):
			points += _weight(m)
	for m in marks:
		if count <= MAX_MARKS and points <= MAX_POINTS:
			break
		if gone.has(int(m["id"])):
			continue
		gone[int(m["id"])] = true
		count -= 1
		points -= _weight(m)
	return gone.keys()


static func _weight(m: Dictionary) -> int:
	return 4 if m.has("text") or m.has("img") else (m["pts"] as PackedVector2Array).size()


## The area a mark covers, ink and all.
static func bounds(m: Dictionary) -> Rect2:
	if m.has("img"):
		return Rect2(m["at"], m["sz"])
	if m.has("text"):
		return Rect2(m["at"], text_size(str(m["text"]), int(m["s"])))
	var pts: PackedVector2Array = m["pts"]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(float(m["w"]) * 0.5)


static func text_size(text: String, font_size: int) -> Vector2:
	var font := ThemeDB.fallback_font
	return Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font_size * 1.2)


## Whether `mark` sits entirely under the eraser stroke `rub`.
static func _rubbed_out(mark: Dictionary, box: Rect2, rub: Dictionary, rub_box: Rect2) -> bool:
	if not rub_box.encloses(box):
		return false
	var reach := float(rub["w"]) * 0.5 + 1.0
	var samples := PackedVector2Array()
	if mark.has("text") or mark.has("img"):
		var step := 24.0 if mark.has("img") else maxf(4.0, box.size.y / 3.0)
		var x := box.position.x
		while x <= box.end.x + 0.01:
			var y := box.position.y
			while y <= box.end.y + 0.01:
				samples.append(Vector2(x, y))
				y += step
			x += step
	else:
		reach -= float(mark["w"]) * 0.5
		var pts: PackedVector2Array = mark["pts"]
		samples.append(pts[0])
		for k in range(1, pts.size()):
			var n := ceili(pts[k - 1].distance_to(pts[k]) / 4.0)
			for s in range(1, n + 1):
				samples.append(pts[k - 1].lerp(pts[k], float(s) / n))
	if reach <= 0.0:
		return false
	for p in samples:
		if _distance(rub["pts"], p) > reach:
			return false
	return true


static func _distance(pts: PackedVector2Array, p: Vector2) -> float:
	var best := pts[0].distance_to(p)
	for k in range(1, pts.size()):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k]).distance_to(p))
	return best


## The colour showing at `p`: a COLORS index, -1 for bare board or IMAGE over a picture.
static func ink_at(board: Dictionary, p: Vector2) -> int:
	var marks: Array = board.get("marks", [])
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		var hit := bounds(m).has_point(p) if m.has("text") or m.has("img") else _distance(m["pts"], p) <= float(m["w"]) * 0.5
		if hit:
			return IMAGE if is_image(m) else (-1 if is_eraser(m) else int(m["c"]))
	return -1


## Fewer points along the same line (Ramer-Douglas-Peucker), so the board stays small.
static func simplify(pts: PackedVector2Array, tolerance := 0.7) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep.fill(0)
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack := [Vector2i(0, pts.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1.0
		var at := -1
		for k in range(span.x + 1, span.y):
			var d := Geometry2D.get_closest_point_to_segment(pts[k], pts[span.x], pts[span.y]).distance_to(pts[k])
			if d > worst:
				worst = d
				at = k
		if at >= 0 and worst > tolerance:
			keep[at] = 1
			stack.append(Vector2i(span.x, at))
			stack.append(Vector2i(at, span.y))
	var out := PackedVector2Array()
	for k in pts.size():
		if keep[k] == 1:
			out.append(pts[k])
	return out
