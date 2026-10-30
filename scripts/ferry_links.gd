class_name FerryLinks
extends RefCounted
## The ferries a region's roads are joined by (Ride Anywhere v2, phase D round 3, D7): its features' ferry routes
## (tools/feature_bake.py "ferry", Overture's water segments) made into links between two road junctions, one at each
## terminal, where the road already meets the water. The planner may route over a link (RoutePlanner), the sat nav says
## "Take the ferry" (NetNav), and the crew crosses on it (FerryCrossing); the scenery's ferries sail them
## (scripts/scenery/ferry.gd).
##
## A link never changes a road: the roads, their junctions and RealRegion.hash are as they were. Links are worked out
## from the region alone (its features and its graph), so every machine with the same map has the same links in the
## same order; their hash goes into the crew's ride hash (AdventureCrew.ride_hash), never into the region's.
##
## A ferry route cut at a cell's edge comes in pieces that share the point they were cut at; pieces of one route (the
## same id) are joined end to end first. A route whose ends aren't both by a road (one leaving the map, a foot ferry to
## a beach) isn't a link. Plain data and pure functions: safe on a worker.

## Bumped whenever how links are made changes: it's in the builder hash (AdventureCrew.builds).
const VERSION := 1
## A route's end is joined to the road junction nearest it, this near at most (m).
const SNAP := 200.0
## Pieces of one route meet where their ends are this close (m: they share a point, so it's only rounding).
const JOIN := 0.5
## A route shorter than this (m) between its terminals isn't a crossing.
const SHORTEST := 60.0
## How fast the ferries sail (m/s, about 17 knots), and the shortest and longest crossing the crew sits through (s):
## Simon's "a short real crossing of about a minute". A long route is sailed at this speed out of one harbour and into
## the other, the open water between passed over (FerryCrossing).
const SPEED := 9.0
const CROSS_LEAST := 40.0
const CROSS_MOST := 75.0
## A route this short or shorter (m), or one named as one, is a chain ferry (a floating bridge); one this long or
## longer a big car ferry; the rest roll-on roll-off ferries.
const CHAIN_MOST := 300.0
const SHIP_FROM := 10000.0
const CHAIN_WORDS := ["chain", "floating bridge", "cable ferry", "pont", "fähre am seil"]
## What crossing on a ferry costs the planner, as metres of the cheapest road it would ride instead (a main road on a
## quick ride): getting aboard, and each metre of the crossing (a boat's slower than a bike on a main road).
const BOARD_COST := 2500.0
const COST_PER_M := 1.2
## Regions kept (the planner and the ride ask often; each region's are worked out once).
const KEPT := 6

static var _cache: Array = []   # [[weakref of the region, FerryLinks]], newest last
static var _lock := Mutex.new()

var region: RealRegion
## Each link: {a, b (the junctions at either end), pts (PackedVector2Array, a's junction to b's, the route between),
## m (its length), name, id, size ("chain", "roro" or "ship")}.
var links: Array = []
## The links at each junction: {node: PackedInt32Array}.
var at := {}
## The road pieces (RealRegion.component) joined by ferries: {component: its group (the lowest component in it)}.
var groups := {}
## 12 hex of VERSION and the links ("" for none): the same on every machine with the same map.
var hash := ""
## Every ferry route of the region, each route's pieces joined ({pts, name, id}): the links and those that leave the
## map or end away from a road (the scenery's ferries sail them all).
var routes: Array = []


## The links of region `r` (worked out once, then shared).
static func of(r: RealRegion) -> FerryLinks:
	if r == null:
		return FerryLinks.new(null)
	_lock.lock()
	for k in range(_cache.size() - 1, -1, -1):
		var got = (_cache[k][0] as WeakRef).get_ref()
		if got == null:
			_cache.remove_at(k)
		elif got == r:
			var links_of: FerryLinks = _cache[k][1]
			_lock.unlock()
			return links_of
	_lock.unlock()
	var made := FerryLinks.new(r)
	_lock.lock()
	_cache.append([weakref(r), made])
	while _cache.size() > KEPT:
		_cache.pop_front()
	_lock.unlock()
	return made


func _init(r: RealRegion) -> void:
	region = r
	if r == null or r.node_count() == 0:
		return
	routes = _routes(r.features.get("lines", []))
	var pairs := {}   # Vector2i(lower node, higher node) -> link index
	for route: Dictionary in routes:
		var pts: PackedVector2Array = route["pts"]
		var a := r.nearest_node(pts[0].x, pts[0].y, SNAP)
		var b := r.nearest_node(pts[pts.size() - 1].x, pts[pts.size() - 1].y, SNAP)
		if a < 0 or b < 0 or a == b:
			continue
		var line := PackedVector2Array([r.node_pos[a]])
		line.append_array(pts)
		line.append(r.node_pos[b])
		var m := _length(line)
		if r.node_pos[a].distance_to(r.node_pos[b]) < SHORTEST:
			continue
		var key := Vector2i(mini(a, b), maxi(a, b))
		if pairs.has(key):
			if m >= float(links[int(pairs[key])]["m"]):
				continue   # (two routes between the same terminals: the shorter's the one sailed)
			links[int(pairs[key])] = _link(a, b, line, m, route)
			continue
		pairs[key] = links.size()
		links.append(_link(a, b, line, m, route))
	var text := "%d" % VERSION
	var parent := {}
	for i in links.size():
		var l: Dictionary = links[i]
		for n: int in [int(l["a"]), int(l["b"])]:
			var list: PackedInt32Array = at.get(n, PackedInt32Array())
			list.append(i)
			at[n] = list
		_union(parent, r.component[int(l["a"])], r.component[int(l["b"])])
		text += "|%s:%d:%d" % [str(l["id"]), int(l["a"]), int(l["b"])]
	for c in parent:
		groups[c] = _find(parent, c)
	hash = text.sha1_text().substr(0, 12) if not links.is_empty() else ""


static func _link(a: int, b: int, line: PackedVector2Array, m: float, route: Dictionary) -> Dictionary:
	return {"a": a, "b": b, "pts": line, "m": m, "name": str(route["name"]), "id": str(route["id"]),
		"size": size_of(str(route["name"]), m)}


## The ferry routes of features `lines` (RealRegion.features' lines), the pieces of each joined end to end:
## [{pts, name, id}], in the order their first pieces come.
static func _routes(lines: Array) -> Array:
	var pieces: Array = []   # [pts, name, id]
	for row: Array in lines:
		if str(row[0]) == "ferry" and (row[1] as PackedVector2Array).size() >= 2:
			pieces.append([row[1], str(row[5]), str(row[6]) if row[6] != null else ""])
	var used := PackedByteArray()
	used.resize(pieces.size())
	var out: Array = []
	for i in pieces.size():
		if used[i] == 1:
			continue
		used[i] = 1
		var pts: PackedVector2Array = (pieces[i][0] as PackedVector2Array).duplicate()
		var id: String = pieces[i][2]
		var grew := id != ""
		while grew:
			grew = false
			for j in range(i + 1, pieces.size()):
				if used[j] == 1 or pieces[j][2] != id:
					continue
				var q: PackedVector2Array = pieces[j][0]
				var joined := _join(pts, q)
				if not joined.is_empty():
					pts = joined
					used[j] = 1
					grew = true
		out.append({"pts": pts, "name": pieces[i][1], "id": id})
	return out


## `p` and `q` joined where an end of one is an end of the other (either way round), or [] where they don't meet.
static func _join(p: PackedVector2Array, q: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p0 := p[0]
	var p1 := p[p.size() - 1]
	var q0 := q[0]
	var q1 := q[q.size() - 1]
	if p1.distance_to(q0) <= JOIN:
		out = p.duplicate()
		out.append_array(q.slice(1))
	elif p1.distance_to(q1) <= JOIN:
		out = p.duplicate()
		var r := q.duplicate()
		r.reverse()
		out.append_array(r.slice(1))
	elif q1.distance_to(p0) <= JOIN:
		out = q.duplicate()
		out.append_array(p.slice(1))
	elif q0.distance_to(p0) <= JOIN:
		out = q.duplicate()
		out.reverse()
		out.append_array(p.slice(1))
	return out


static func _length(pts: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(1, pts.size()):
		m += pts[i].distance_to(pts[i - 1])
	return m


static func _find(parent: Dictionary, c: int) -> int:
	while parent.has(c) and int(parent[c]) != c:
		c = int(parent[c])
	return c


static func _union(parent: Dictionary, a: int, b: int) -> void:
	for c in [a, b]:
		if not parent.has(c):
			parent[c] = c
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


## Which kind of ferry sails a route named `name` `m` metres long: "chain", "roro" or "ship".
static func size_of(name: String, m: float) -> String:
	var low := name.to_lower()
	for w in CHAIN_WORDS:
		if low.contains(w):
			return "chain"
	if m <= CHAIN_MOST:
		return "chain"
	return "ship" if m >= SHIP_FROM else "roro"


## How long (s) the crew sits through crossing link `i`.
func seconds(i: int) -> float:
	return seconds_of(float(links[i]["m"]))


static func seconds_of(m: float) -> float:
	return clampf(m / SPEED, CROSS_LEAST, CROSS_MOST)


## What crossing link `i` costs the planner, with `costs` the cost a metre of each road class.
func cost(i: int, costs: PackedFloat64Array) -> float:
	var cheapest := INF
	for c in costs:
		cheapest = minf(cheapest, c)
	return (BOARD_COST + float(links[i]["m"]) * COST_PER_M) * (cheapest if cheapest < INF else 1.0)


## Whether road pieces `c1` and `c2` (RealRegion.component) are joined, by road or by ferry.
func joined(c1: int, c2: int) -> bool:
	return c1 == c2 or (groups.has(c1) and groups.has(c2) and int(groups[c1]) == int(groups[c2]))


## The other end of link `i` from junction `node`.
func other_end(i: int, node: int) -> int:
	var l: Dictionary = links[i]
	return int(l["b"]) if int(l["a"]) == node else int(l["a"])


## Link `i`'s line from junction `from` to its other end.
func line_from(i: int, from: int) -> PackedVector2Array:
	var pts: PackedVector2Array = links[i]["pts"]
	if int(links[i]["a"]) == from:
		return pts
	var out := pts.duplicate()
	out.reverse()
	return out


## The index of the link with `id` between junctions `a` and `b` (either way), or -1.
func find(id: String, a: int, b: int) -> int:
	for i in (at.get(a, PackedInt32Array()) as PackedInt32Array):
		if str(links[i]["id"]) == id and other_end(i, a) == b:
			return i
	return -1


## The name the crew's told the crossing by: the route's own, else "the ferry".
func title(i: int) -> String:
	var n := str(links[i]["name"])
	return n if n != "" else "The ferry"


func is_empty() -> bool:
	return links.is_empty()
