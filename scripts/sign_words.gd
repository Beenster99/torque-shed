class_name SignWords
extends RefCounted
## The words written on signs, painted on roads and put over shops (Ride Anywhere v2, T8), as flat triangles made by
## tools/sign_glyphs.py from Noto Sans (data/sign_glyphs.json): every script the game writes in, with no fonts shipped.
## Safe from any thread.

const GLYPHS := "res://data/sign_glyphs.json"

static var _lock := Mutex.new()
static var _words := {}
static var _loaded := false


## Word `text`'s shape: {w, top, bottom (em), tris: [x, y, ...] (em, y up from the baseline)}, or {} if it wasn't baked.
static func of(text: String) -> Dictionary:
	_load()
	return _words.get(text, {})


## Whether `text` was baked.
static func has(text: String) -> bool:
	return not of(text).is_empty()


## Draws `text` into AdventureProps arrays `a`, centred on `at`, reading along `across` with its top towards `up`
## (both unit vectors), `height` m from its lowest to its highest point (and no wider than `most` m), its front facing
## `facing`. Returns how wide it came out (m), 0 if it wasn't baked.
static func draw(a: Dictionary, text: String, at: Vector3, across: Vector3, up: Vector3, height: float, col: Color,
		facing: Vector3, most := INF) -> float:
	var g := of(text)
	if g.is_empty():
		return 0.0
	var w := float(g["w"])
	var top := float(g["top"])
	var bottom := float(g["bottom"])
	var k := height / maxf(top - bottom, 0.01)
	if w * k > most:
		k = most / maxf(w, 0.01)
	var mid := Vector2(w * 0.5, (top + bottom) * 0.5)
	var t: Array = g["tris"]
	for i in range(0, t.size(), 6):
		var p0 := at + across * ((float(t[i]) - mid.x) * k) + up * ((float(t[i + 1]) - mid.y) * k)
		var p1 := at + across * ((float(t[i + 2]) - mid.x) * k) + up * ((float(t[i + 3]) - mid.y) * k)
		var p2 := at + across * ((float(t[i + 4]) - mid.x) * k) + up * ((float(t[i + 5]) - mid.y) * k)
		if (p1 - p0).cross(p2 - p0).dot(facing) >= 0.0:
			AdventureProps._tri(a, p0, p1, p2, col)
		else:
			AdventureProps._tri(a, p0, p2, p1, col)
	return w * k


static func _load() -> void:
	_lock.lock()
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(GLYPHS, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_words = d.get("words", {})
	_lock.unlock()
