class_name MappedRoadside
extends RefCounted
## Where the map has its own roadside (phase D, D9: interfaces/scenery.md), so a road block's generic roadside
## (RoadBlock._roadside: the place's marker posts and its fences, walls and hedges along farmland) stands back from it:
## no generic wall doubling a mapped wall, fence or hedge the scenery draws beside the road, and no marker post where
## a mapped lamp, bench, post box or gate stands. Only what a kit row draws counts (a kind still a stand-in leaves the
## generic roadside as it was). Built once a region, its features' hash keyed, safe from any thread.

## The mapped lines a generic fence, wall or hedge stands back from, and how near (m).
const BOUNDS := ["wall", "fence", "hedge", "retaining_wall", "city_wall"]
const BOUND_NEAR := 5.0
## The mapped points a marker post stands back from: any kind of these rounds a kit row draws, within this (m).
const POST_ROUNDS := ["D6", "D9"]
const POST_NEAR := 3.5
## The index's squares (m).
const CELL := 16.0

static var _made := {}
static var _lock := Mutex.new()

var _bounds := {}   # Vector2i -> PackedVector2Array (segments' ends in pairs)
var _posts := {}    # Vector2i -> PackedVector2Array


## The index of region `r`'s mapped roadside (an empty one where it has no features).
static func of(r: RealRegion) -> MappedRoadside:
	var key := "%d|%s|%d" % [r.get_instance_id(), r.features_hash, (r.features.get("points", []) as Array).size()]
	_lock.lock()
	var have = _made.get(key)
	_lock.unlock()
	if have != null:
		return have
	var m := MappedRoadside.new()
	m._build(r.features)
	_lock.lock()
	_made[key] = m
	_lock.unlock()
	return m


static func forget() -> void:
	_lock.lock()
	_made.clear()
	_lock.unlock()


## Whether nothing is mapped at all (the generic roadside is as it always was).
func is_empty() -> bool:
	return _bounds.is_empty() and _posts.is_empty()


## Whether a mapped wall, fence or hedge runs within BOUND_NEAR of region point (x, z).
func walled(x: float, z: float) -> bool:
	if _bounds.is_empty():
		return false
	var p := Vector2(x, z)
	var segs: PackedVector2Array = _bounds.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedVector2Array())
	for i in range(0, segs.size(), 2):
		if Geometry2D.get_closest_point_to_segment(p, segs[i], segs[i + 1]).distance_squared_to(p) < BOUND_NEAR * BOUND_NEAR:
			return true
	return false


## Whether a mapped thing stands within POST_NEAR of region point (x, z).
func taken(x: float, z: float) -> bool:
	if _posts.is_empty():
		return false
	var p := Vector2(x, z)
	var pts: PackedVector2Array = _posts.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedVector2Array())
	for q in pts:
		if q.distance_squared_to(p) < POST_NEAR * POST_NEAR:
			return true
	return false


func _build(features: Dictionary) -> void:
	var drawn := {}   # kind -> whether a kit row draws it
	var draws := func(kind: String) -> bool:
		if not drawn.has(kind):
			var model := str(SceneryStreamer.kit(kind).get("model", ""))
			drawn[kind] = model != "" and not model.begins_with("standin:") and not model.ends_with(":none")
		return drawn[kind]
	for row: Array in features.get("points", []):
		var kind := str(row[0])
		if not str(SceneryStreamer.kit(kind).get("round", "")) in POST_ROUNDS or not draws.call(kind):
			continue
		var p := Vector2(float(row[1]), float(row[2]))
		# (in every square the point's reach touches)
		for c in _cells(Rect2(p, Vector2.ZERO).grow(POST_NEAR)):
			var pts: PackedVector2Array = _posts.get(c, PackedVector2Array())
			pts.append(p)
			_posts[c] = pts   # (a packed array is a value: put back)
	for part: String in ["lines", "areas"]:
		for row: Array in features.get(part, []):
			var kind := str(row[0])
			if not kind in BOUNDS or not draws.call(kind):
				continue
			var line: PackedVector2Array = row[1]
			var n := line.size() if part == "lines" else line.size() + 1
			for i in range(1, n):
				var a := line[i - 1]
				var b := line[i % line.size()]
				for c in _cells(Rect2(a, Vector2.ZERO).expand(b).grow(BOUND_NEAR)):
					var segs: PackedVector2Array = _bounds.get(c, PackedVector2Array())
					segs.append(a)
					segs.append(b)
					_bounds[c] = segs


## The index squares rectangle `box` touches.
static func _cells(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			out.append(Vector2i(cx, cz))
	return out
