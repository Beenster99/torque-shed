class_name WorldMap
extends RefCounted
## The map of the whole world the Route planner TV shows between the globe and the roads (see WorldView): land, lakes,
## rivers and the borders between countries, and the world's towns and cities to search for, from Natural Earth
## (public domain) by tools/world_bake.py into data/world. The map is Web Mercator: a point is (x, y) from (0, 0) at
## 180 W by 85 N to (1, 1) at 180 E by 85 S, the way the world's map tiles are cut.
##
## Read once, on a worker the first time it is wanted (load_world): the land comes as triangles, ready to draw.

const PATH := "res://data/world/world.tsw"
const PLACES_PATH := "res://data/world/places.json"
## Metres round the equator (the WGS84 ellipsoid's).
const EARTH := 40075016.686
const MAX_LAT := 85.05112878

static var _lock := Mutex.new()
static var _loaded := false
static var _meshes := {}       # layer name -> ArrayMesh of its triangles, in mercator units
static var _lines := {}        # layer name -> Array of PackedVector2Array, in mercator units
static var _boxes := {}        # layer name -> PackedFloat32Array of each line's [x0, y0, x1, y1]
static var _places: Array = [] # [name, lat, lon, population, country], the most important first
static var _keys := PackedStringArray()   # each place's name, folded for searching


## The mercator point of (lat, lon).
static func mercator(lat: float, lon: float) -> Vector2:
	var s := sin(deg_to_rad(clampf(lat, -MAX_LAT, MAX_LAT)))
	return Vector2((lon + 180.0) / 360.0, 0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI))


## (lat, lon) of mercator point `m`.
static func geo_of(m: Vector2) -> Vector2:
	return Vector2(rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * m.y)))), m.x * 360.0 - 180.0)


## Metres on the ground across one mercator unit, at latitude `lat`.
static func metres_per_unit(lat: float) -> float:
	return EARTH * cos(deg_to_rad(clampf(lat, -MAX_LAT, MAX_LAT)))


## Reads the map if it hasn't been (blocks for half a second or so: call it from a worker). False when it can't be read.
static func load_world() -> bool:
	_lock.lock()
	if _loaded:
		_lock.unlock()
		return true
	var ok := _read()
	_loaded = ok
	_lock.unlock()
	return ok


static func loaded() -> bool:
	_lock.lock()
	var v := _loaded
	_lock.unlock()
	return v


static func _read() -> bool:
	var bytes := FileAccess.get_file_as_bytes(PATH)
	if bytes.size() < 8 or bytes.slice(0, 4).get_string_from_ascii() != "TSW2":
		push_error("WorldMap: no readable map at %s" % PATH)
		return false
	var at := 4
	var count := bytes.decode_u32(at)
	at += 4
	for _l in count:
		var name_len := bytes[at]
		var name := bytes.slice(at + 1, at + 1 + name_len).get_string_from_ascii()
		at += 1 + name_len
		var kind := bytes[at]
		at += 1
		if kind == 0:
			var n := bytes.decode_u32(at)
			var pts := _points(bytes.slice(at + 4, at + 4 + n * 8).to_int32_array())
			at += 4 + n * 8
			var c := bytes.decode_u32(at)
			var corners := bytes.slice(at + 4, at + 4 + c * 4).to_int32_array()
			at += 4 + c * 4
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = pts
			arrays[Mesh.ARRAY_INDEX] = corners
			var mesh := ArrayMesh.new()
			if not pts.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_meshes[name] = mesh
		else:
			var lines: Array[PackedVector2Array] = []
			var boxes := PackedFloat32Array()
			var n_lines := bytes.decode_u32(at)
			at += 4
			for _i in n_lines:
				var n := bytes.decode_u32(at)
				var pts := _points(bytes.slice(at + 4, at + 4 + n * 8).to_int32_array())
				at += 4 + n * 8
				lines.append(pts)
				var lo := pts[0]
				var hi := pts[0]
				for p in pts:
					lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
					hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
				boxes.append_array([lo.x, lo.y, hi.x, hi.y])
			_lines[name] = lines
			_boxes[name] = boxes
	var v = JSON.parse_string(FileAccess.get_file_as_string(PLACES_PATH))
	_places = v if v is Array else []
	_keys.clear()
	for p in _places:
		_keys.append(fold(str(p[0])))
	return true


## Points (1e-5 degrees, longitude then latitude) as mercator points.
static func _points(raw: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(raw.size() / 2)
	for i in out.size():
		out[i] = mercator(raw[i * 2 + 1] * 1e-5, raw[i * 2] * 1e-5)
	return out


## The triangles of an area layer ("land_low", "land", "lakes"), or null before the map is read.
static func mesh(layer: String) -> ArrayMesh:
	return _meshes.get(layer) if loaded() else null


## The lines of a line layer ("rivers", "borders") and their boxes ([x0, y0, x1, y1] each).
static func lines(layer: String) -> Array:
	return _lines.get(layer, []) if loaded() else []


static func line_boxes(layer: String) -> PackedFloat32Array:
	return _boxes.get(layer, PackedFloat32Array()) if loaded() else PackedFloat32Array()


## The world's towns and cities: [name, lat, lon, population, country], the most important first (capitals and great
## cities, then the rest, biggest first).
static func places() -> Array:
	return _places if loaded() else []


## A name made easy to match: lower case, without accents or anything but letters, numbers and spaces.
static func fold(s: String) -> String:
	var t := s.to_lower()
	const FROM := "àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿśšźżžłđ"
	const TO := "aaaaaaaccceeeeeeiiiiinnooooooouuuuuyysszzzld"
	var out := ""
	for ch in t:
		var k := FROM.find(ch)
		if k >= 0:
			out += TO[k]
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == " ":
			out += ch
	return out


## The places whose name starts with `query` (folded), then those with a word that does, the most important first: at
## most `limit`.
static func search(query: String, limit := 8) -> Array:
	var q := fold(query).strip_edges()
	if q == "" or not loaded():
		return []
	var first: Array = []
	var then: Array = []
	for i in _keys.size():
		var k := _keys[i]
		if k.begins_with(q):
			first.append(_places[i])
		elif k.contains(" " + q):
			then.append(_places[i])
		if first.size() >= limit:
			break
	return (first + then).slice(0, limit)


## The name of the most important place within `reach` metres of (lat, lon), else the nearest, else "".
static func nearest_place(lat: float, lon: float, reach := 30000.0) -> String:
	var best := ""
	var best_d := INF
	for p in places():
		var d := _ground_metres(lat, lon, float(p[1]), float(p[2]))
		if d < reach:
			return str(p[0])   # (the list is the most important first)
		if d < best_d:
			best_d = d
			best = str(p[0])
	return best


## Metres between two points on the ground (near enough: an equirectangular sum, good for a few hundred km).
static func _ground_metres(lat0: float, lon0: float, lat1: float, lon1: float) -> float:
	var k := EARTH / 360.0
	var dx := (lon1 - lon0) * k * cos(deg_to_rad((lat0 + lat1) * 0.5))
	var dy := (lat1 - lat0) * k
	return sqrt(dx * dx + dy * dy)
