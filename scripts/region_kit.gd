class_name RegionKit
extends RefCounted
## The regional kits (Ride Anywhere v2, T8): what a place's buildings and roadside are made of, chosen from its place
## profile (PlaceProfile) and nothing else. A cell's profile names its country; the country facts table
## (data/countries.json, made by tools/country_facts.py) names the country's region and the facts that differ inside
## one (the side of the road, units, road paint, sign shapes, language and script, places of worship, roadside posts,
## kerb paint, speed bumps); the region's kit (data/region_kits.json) says how its buildings look, with variants for
## the profile's altitude, climate zone, density and coast. Nobody picks a country or a kit by hand.
##
## A kit is a plain Dictionary: the region kit's fields with its matching variants laid over, colours made Colors,
## plus "region", "country" and "facts". {} where the country isn't known (open sea, a made-up ride): the ride then
## dresses as it always has. Safe from any thread.

const COUNTRIES := "res://data/countries.json"
const KITS := "res://data/region_kits.json"
## The roadside post styles (data/countries.json "posts"), each drawn by post_mesh, and how far apart they stand (m).
const POST_STYLES := ["uk", "leitpfosten", "balise", "nl", "nordic", "striped", "us", "delineator", "guide"]
const POST_GAP := 50.0
## Kerb and verge-stone paint (data/countries.json "kerb"): its two colours, in blocks a metre long.
const KERB_PAINT := {
	"red_white": [Color(0.72, 0.1, 0.08), Color(0.93, 0.92, 0.88)],
	"black_white": [Color(0.08, 0.08, 0.09), Color(0.93, 0.92, 0.88)],
	"black_yellow": [Color(0.08, 0.08, 0.09), Color(0.9, 0.72, 0.1)],
	"yellow": [Color(0.9, 0.74, 0.12), Color(0.9, 0.74, 0.12)],
}
## Fields of a kit that hold colours (one, or a list of them), and the shop's.
const COLOUR_FIELDS := ["walls", "roofs", "trim", "door", "glass", "shutters", "timber", "plinth", "barn"]

static var _lock := Mutex.new()
static var _countries := {}
static var _kits := {}
## Kits already made, by what they were made from (country and the profile's bands), and the kit of each cell asked
## for on a ride ("ROW_COL" -> kit).
static var _made := {}
static var _cells := {}
static var _meshes := {}


## The facts of country `code` (ISO 3166-1 alpha-2, as a profile's "country"), or {} if the table hasn't it.
static func facts(code: String) -> Dictionary:
	_load()
	return _countries.get(code.to_upper(), {})


## The region kit country `code` takes ("" when unknown).
static func region_of(code: String) -> String:
	return str(facts(code).get("region", ""))


## Every region kit's id, in the plan's order.
static func regions() -> Array:
	_load()
	return (_kits.get("regions", {}) as Dictionary).keys()


## The kit for place profile `p` (PlaceProfile's shape): its country's region kit, with the variants its altitude,
## climate zone, density and coast match. {} when the profile's country isn't in the table.
static func choose(p: Dictionary) -> Dictionary:
	var code := str(p.get("country", "")).to_upper()
	var f := facts(code)
	if f.is_empty():
		return {}
	var koppen := str(p.get("koppen", ""))
	var key := "%s|%s|%s|%s|%s" % [code, str(p.get("altitude_band", "")), koppen, str(p.get("density", "")), str(p.get("coast", false))]
	_lock.lock()
	var have = _made.get(key)
	_lock.unlock()
	if have is Dictionary:
		return have
	var region := str(f["region"])
	var raw: Dictionary = (_kits["default"] as Dictionary).duplicate(true)
	var reg: Dictionary = _kits["regions"].get(region, {})
	for k in reg:
		if k != "variants":
			raw[k] = reg[k]
	for v: Dictionary in reg.get("variants", []):
		if matches(v.get("when", {}), p):
			for k in v.get("set", {}):
				raw[k] = v["set"][k]
	var kit := {}
	for k in raw:
		if k == "variants":
			continue
		kit[k] = _colours(raw[k]) if k in COLOUR_FIELDS else raw[k]
	var shop: Dictionary = raw.get("shop", {})
	kit["shop"] = {"fascia": _colours(shop.get("fascia", [])), "awning": _colours(shop.get("awning", []))}
	kit["region"] = region
	kit["country"] = code
	kit["facts"] = f
	_lock.lock()
	_made[key] = kit
	_lock.unlock()
	return kit


## Whether profile `p` meets a variant's `when`: every condition given holds (altitude bands, Köppen zones by their
## first letters, densities, coast).
static func matches(when: Dictionary, p: Dictionary) -> bool:
	if when.has("altitude") and not (when["altitude"] as Array).has(str(p.get("altitude_band", ""))):
		return false
	if when.has("density") and not (when["density"] as Array).has(str(p.get("density", ""))):
		return false
	if when.has("coast") and bool(when["coast"]) != bool(p.get("coast", false)):
		return false
	if when.has("koppen"):
		var z := str(p.get("koppen", ""))
		var any := false
		for pre: String in when["koppen"]:
			any = any or z.begins_with(pre)
		if not any:
			return false
	return true


## The kit of the place beside knot `i` of a ride on a real road (its cell's profile), or {} off one. Blocks the first
## time a cell is asked for (its profile may be fetched): a chunk's builder runs on a worker.
static func for_route(route: AdventureRoute, i: int) -> Dictionary:
	if route == null or route.real == null or route.real.terrain == null:
		return {}
	var t: RealTerrain = route.real.terrain
	var k := clampi(i, 0, route.knot_count() - 1)
	var m := RealTerrain.metres_per_degree(t.lat0)
	var lat := t.lat0 - route.pz[k] / m.x
	var lon := t.lon0 + route.px[k] / m.y
	var cell := RealRegion.cell_of(lat, lon)
	var key := "%d_%d" % [cell.x, cell.y]
	_lock.lock()
	var have = _cells.get(key)
	_lock.unlock()
	if have is Dictionary:
		return have
	var kit := choose(PlaceProfile.of_cell(cell))
	_lock.lock()
	_cells[key] = kit
	_lock.unlock()
	return kit


## Forgets the kits of the cells asked for (the tests change where profiles come from).
static func forget() -> void:
	_lock.lock()
	_cells = {}
	_lock.unlock()


## One of `list` (of colours or anything), by `rng`.
static func pick(rng: RandomNumberGenerator, list: Array, fallback: Variant = Color.WHITE) -> Variant:
	return fallback if list.is_empty() else list[rng.randi_range(0, list.size() - 1)]


## The kind of place of worship a kit's country builds, for `roll` (0..1): by the facts table's shares.
static func worship_kind(kit: Dictionary, roll: float) -> String:
	var shares: Dictionary = kit.get("facts", {}).get("worship", {"church": 1.0})
	var total := 0.0
	for k in shares:
		total += float(shares[k])
	var at := roll * total
	var last := "church"
	for k in shares:
		last = str(k)
		at -= float(shares[k])
		if at <= 0.0:
			return last
	return last


## The mesh of a roadside post style (POST_STYLES), shared by every chunk: posts are drawn many times over by a
## chunk's MultiMesh, as "kit_post_<style>".
static func post_mesh(style: String) -> ArrayMesh:
	_lock.lock()
	var have: ArrayMesh = _meshes.get(style)
	_lock.unlock()
	if have:
		return have
	var a := AdventureProps.new_arrays()
	var white := Color(0.94, 0.94, 0.92)
	var black := Color(0.07, 0.07, 0.08)
	var red := Color(0.85, 0.08, 0.06)
	var amber := Color(0.95, 0.6, 0.08)
	var o := Transform3D()
	match style:
		"uk":   # a white post with a red reflector
			AdventureProps.box(a, o, Vector3(0.1, 1.0, 0.1), white)
			AdventureProps.box(a, o.translated(Vector3(0, 0.78, 0)), Vector3(0.105, 0.14, 0.105), red)
		"leitpfosten":   # Germany's: white, a black band near the top round an amber reflector
			AdventureProps.box(a, o, Vector3(0.12, 1.0, 0.1), white)
			AdventureProps.box(a, o.translated(Vector3(0, 0.62, 0)), Vector3(0.125, 0.26, 0.105), black)
			AdventureProps.box(a, o.translated(Vector3(0, 0.7, 0)), Vector3(0.13, 0.08, 0.06), amber)
		"balise":   # France's and the south's: round, white, a black band with a red reflector
			AdventureProps.cone(a, o, 0.07, 0.0, 1.0, white, 8, 0.07)
			AdventureProps.cone(a, o, 0.072, 0.72, 0.92, black, 8, 0.072)
			AdventureProps.box(a, o.translated(Vector3(0, 0.78, 0)), Vector3(0.05, 0.1, 0.15), red)
		"nl":   # the Netherlands': white with a red and white reflector panel
			AdventureProps.box(a, o, Vector3(0.12, 1.0, 0.1), white)
			AdventureProps.box(a, o.translated(Vector3(0, 0.7, 0)), Vector3(0.125, 0.18, 0.105), red)
		"nordic":   # tall black-topped snow posts
			AdventureProps.box(a, o, Vector3(0.08, 1.5, 0.08), white)
			AdventureProps.box(a, o.translated(Vector3(0, 1.2, 0)), Vector3(0.085, 0.3, 0.085), black)
		"striped":   # black and white bands
			for k in 4:
				AdventureProps.box(a, o.translated(Vector3(0, k * 0.25, 0)), Vector3(0.12, 0.25, 0.12), white if k % 2 == 0 else black, k == 3)
		"us":   # a slim white flexible post with a white reflector
			AdventureProps.box(a, o, Vector3(0.08, 1.2, 0.04), white)
			AdventureProps.box(a, o.translated(Vector3(0, 1.0, 0)), Vector3(0.085, 0.12, 0.045), Color(0.98, 0.98, 0.98))
		"delineator":   # East Asia's: a grey pole with a round amber reflector on top
			AdventureProps.cone(a, o, 0.035, 0.0, 1.1, Color(0.6, 0.62, 0.64), 6, 0.035)
			AdventureProps.cone(a, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.2, -0.02)), 0.1, 0.0, 0.04, amber, 10, 0.1)
		"guide":   # Australia's and New Zealand's: white, flat, with a red reflector on top
			AdventureProps.box(a, o, Vector3(0.14, 1.0, 0.04), white)
			AdventureProps.box(a, o.translated(Vector3(0, 0.85, 0)), Vector3(0.1, 0.1, 0.045), red)
		_:
			AdventureProps.box(a, o, Vector3(0.12, 1.0, 0.12), white)
	var mesh := AdventureProps.to_mesh(a)
	_lock.lock()
	_meshes[style] = mesh
	_lock.unlock()
	return mesh


## The place's roadside along knots i0..i1 of a real road (AdventureChunk's scenery): its posts on the open road
## either side, every POST_GAP metres, as "kit_post_<style>" in `mm` (none through a town, nor where the snow poles
## stand), and its kerb paint into `paint`: painted kerb stones along the road's edges through a town and round the
## outside of a tight bend.
static func roadside(route: AdventureRoute, kit: Dictionary, i0: int, i1: int, ax: float, az: float, surf: String,
		mm: Dictionary, paint: Dictionary) -> void:
	if kit.is_empty():
		return
	var f: Dictionary = kit["facts"]
	var style := str(f.get("posts", "none"))
	var gap := maxi(1, roundi(POST_GAP / AdventureRoute.STEP))
	if style in POST_STYLES and surf != "snow":
		var posts := []
		for i in range(i0 - i0 % gap + gap, i1, gap):
			if built_up(route, i) or route.in_tunnel(i):
				continue
			for side: float in [-1.0, 1.0]:
				if AdventureJunctions.mouth(route, i, side, 6.0) or route._site_flat(i, side, false) > 0.0:
					continue
				var xf := AdventureChunk._on_land(route, i, (route.width[i] * 0.5 + 1.0) * side, ax, az, -route.hd[i], 1.0, true)
				if xf != Transform3D():
					posts.append(xf)
		if not posts.is_empty():
			mm["kit_post_" + style] = posts
	var colours: Array = KERB_PAINT.get(str(f.get("kerb", "none")), [])
	if colours.is_empty() or surf != "tarmac":
		return
	for i in range(i0, i1):
		var town := built_up(route, i)
		var bend := bend_side(route, i)
		if not town and bend == 0:
			continue
		for side: float in [-1.0, 1.0]:
			if not town and side != float(bend):
				continue
			if AdventureJunctions.mouth(route, i, side, 4.0) or route._site_flat(i, side, false) > 0.0 or route.in_tunnel(i):
				continue
			_kerb(route, i, side, ax, az, colours, paint)


## Whether the road at knot `i` runs through a built-up place (urban cover a little way out either side).
static func built_up(route: AdventureRoute, i: int) -> bool:
	var e := route.width[i] * 0.5 + 10.0
	var h := route.hd[i]
	for side: float in [-1.0, 1.0]:
		if route.cover_at(route.px[i] + cos(h) * e * side, route.pz[i] + sin(h) * e * side) == "urban":
			return true
	return false


## The outside of a tight bend at knot `i` (1 the right, -1 the left), or 0 on a gentle one: the heading turns more
## than about 25 degrees over the 32 m round it.
static func bend_side(route: AdventureRoute, i: int) -> int:
	var a := clampi(i - 4, 0, route.knot_count() - 1)
	var b := clampi(i + 4, 0, route.knot_count() - 1)
	var turn := wrapf(route.hd[b] - route.hd[a], -PI, PI)
	if absf(turn) < 0.44:
		return 0
	# (the heading grows turning right: the outside is then the left)
	return -1 if turn > 0.0 else 1


## Kerb stones a metre long, painted in turn, along the road's edge on `side` from knot `i` to the next.
static func _kerb(route: AdventureRoute, i: int, side: float, ax: float, az: float, colours: Array, paint: Dictionary) -> void:
	var j := mini(i + 1, route.knot_count() - 1)
	var n := maxi(1, roundi(AdventureRoute.STEP))
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var p0 := _edge(route, i, j, t0, side, ax, az)
		var p1 := _edge(route, i, j, t1, side, ax, az)
		var col: Color = colours[(i * n + k) % 2]
		var out := Vector3(cos(lerp_angle(route.hd[i], route.hd[j], 0.5)), 0, sin(lerp_angle(route.hd[i], route.hd[j], 0.5))) * side * 0.25
		var up := Vector3.UP * 0.16
		var down := Vector3.DOWN * 0.1
		# Its top, the face to the road, and the face away from it.
		RegionBuildings._face(paint, [p0 + up, p1 + up, p1 + up + out, p0 + up + out], Vector3.UP, col)
		RegionBuildings._face(paint, [p0 + down, p1 + down, p1 + up, p0 + up], -out, col.darkened(0.08))
		RegionBuildings._face(paint, [p0 + down + out, p1 + down + out, p1 + up + out, p0 + up + out], out, col.darkened(0.2))


## The road's edge on `side`, `t` of the way from knot i to knot j, relative to the chunk's anchor.
static func _edge(route: AdventureRoute, i: int, j: int, t: float, side: float, ax: float, az: float) -> Vector3:
	var h := lerp_angle(route.hd[i], route.hd[j], t)
	var e := lerpf(route.width[i], route.width[j], t) * 0.5 + 0.05
	var x := lerpf(route.px[i], route.px[j], t) + cos(h) * e * side
	var z := lerpf(route.pz[i], route.pz[j], t) + sin(h) * e * side
	return Vector3(x - ax, lerpf(route.ph[i], route.ph[j], t), z - az)


static func _colours(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).map(func(c): return Color.html(str(c)))
	if str(v) == "":
		return null
	return Color.html(str(v))


static func _load() -> void:
	_lock.lock()
	if _countries.is_empty():
		var c = JSON.parse_string(FileAccess.get_file_as_string(COUNTRIES))
		_countries = c.get("countries", {}) if c is Dictionary else {}
		var k = JSON.parse_string(FileAccess.get_file_as_string(KITS))
		_kits = k if k is Dictionary else {"default": {}, "regions": {}}
	_lock.unlock()
