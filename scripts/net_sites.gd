class_name NetSites
extends Node
## The planned ride's places on the network ride (Ride Anywhere v2, T7): the stops (AdventureStops), the fuel stations,
## the start and the destination, built beside the network's roads rather than the single line's chunks, so eating,
## drinking, sitting down together, a bed for the night and the destination's photo all work as they do there: by
## the nodes each place puts in its groups (see AdventureStops), wherever the riders came by road.
##
## Each site is placed once, at the ride's start (place_all), on the network road under the planned line where it was
## planned, nudged along it (by the same amount for a village's rows) to where the road runs straight and clear of
## junctions for the stop's length, the same on every machine. The site's distance along the route ("s") moves with
## it, so the sat nav and the crew agree where it is. Its ground is levelled beside the road (RoadNet.set_flats). It's
## built into its road block's node once that block is in the world (so it goes with the block, and is built again
## when the block is laid out afresh), a place a frame.
##
## The single line's own furniture (its side road crossings and speed limit signs) isn't built: the network has its
## own junctions, and the place's own markings (RoadMarkings).

## Bumped whenever where a site goes on the network changes: it's in hash.
const VERSION := 1
## Kinds of site not built on the network.
const SKIP: Array[String] = ["crossing", "limit"]
## Kinds built across the road (a banner), not beside it.
const ACROSS: Array[String] = ["start", "finish"]
## A site may be moved this far along the route either way (m) to find a good spot, in steps of NUDGE_STEP; well under
## half the stops' spacing (AdventureStops.CLEAR), so two never meet.
const NUDGE := 160.0
const NUDGE_STEP := 10.0
## A good spot: the road's line keeps within BOW m of straight for the place's length either way, and no junction of
## three or more roads is within its length and JUNCTION_CLEAR more.
const BOW := 1.5
const JUNCTION_CLEAR := 30.0
## The length either way (m) a village's high street needs (its rows: AdventureStops._add), and everything else.
const VILLAGE_ALONG := 75.0

var world: AdventureWorld
var net: RoadNet
## [{site, edge, s (m along the edge from its a end), dir (1 the ride goes a to b, -1 b to a), key (the block it's
## built in)}], one for each site that has a place on the network, in the route's order.
var places: Array[Dictionary] = []
## 12 hex of VERSION and every place: the same on every machine with the same plan and region.
var hash := ""
var _built := {}   # index into places -> the node built for it


## Places `w`'s route's sites on its network (w.roads), moving each one's "s" along the route to where it's placed and
## levelling the ground beside it.
func setup(w: AdventureWorld) -> void:
	name = "NetSites"
	world = w
	net = w.roads.net
	places = place_all(net, w.route)
	var flats := []
	var text := "%d" % VERSION
	for p in places:
		var site: Dictionary = p["site"]
		text += "|%s,%d,%.1f,%d" % [str(site["kind"]), int(p["edge"]), float(p["s"]), int(p["dir"])]
		if ACROSS.has(str(site["kind"])):
			continue
		flats.append({"edge": p["edge"], "s": p["s"], "side": int(site["side"]) * int(p["dir"]),
			"out": float(site.get("flat", 20.0)), "along": along_of(str(site["kind"]))})
	hash = text.sha1_text().substr(0, 12)
	net.set_flats(flats)


## The length either way (m) the place of a site of `kind` needs straight road and level ground.
static func along_of(kind: String) -> float:
	if kind == "village" or kind == AdventureStops.ROW:
		return VILLAGE_ALONG if kind == "village" else AdventureStops.GROUND_ALONG
	return AdventureStops.GROUND_ALONG


## Where each of `route`'s sites goes on `net` (see places), moving the sites' "s" (and a village's rows with it).
static func place_all(n: RoadNet, route: AdventureRoute) -> Array[Dictionary]:
	var moved := {}   # a village's planned s -> how far it moved
	var out: Array[Dictionary] = []
	for site: Dictionary in route.sites:
		var kind := str(site["kind"])
		if SKIP.has(kind) or kind == AdventureStops.ROW:
			continue
		var s0 := float(site["s"])
		var p := place(n, route, s0, kind)
		if p.is_empty():
			continue
		if kind == "village":
			moved[s0] = float(p["route_s"]) - s0
		site["s"] = float(p["route_s"])
		p["site"] = site
		out.append(p)
	# The rows of each village go with it, wherever their own bit of road is.
	for site: Dictionary in route.sites:
		if str(site["kind"]) != AdventureStops.ROW:
			continue
		var main_s := float(site.get("main_s", -1.0))
		if not moved.has(main_s):
			continue
		var d: float = moved[main_s]
		site["s"] = float(site["s"]) + d
		site["main_s"] = main_s + d
		var p := _spot(n, route, float(site["s"]), 0.0)
		if p.is_empty():
			continue
		p["site"] = site
		out.append(p)
	route._index_sites()
	out.sort_custom(func(a, b): return float(a["site"]["s"]) < float(b["site"]["s"]))
	return out


## Where a site of `kind` planned `s` m along `route` goes on `n`: the nearest good spot (see BOW) within NUDGE, else the
## straightest clear of junctions, else where it was planned if that's on a road; {} if it isn't. {edge, s, dir, key,
## route_s (where it now is along the route)}.
static func place(n: RoadNet, route: AdventureRoute, s: float, kind: String) -> Dictionary:
	if ACROSS.has(kind):
		return _spot(n, route, s, -1.0)
	var along := along_of(kind)
	var best := {}
	var k := 0
	while k * NUDGE_STEP <= NUDGE:
		for sign: float in ([1.0] if k == 0 else [1.0, -1.0]):
			var at := s + sign * k * NUDGE_STEP
			if at < 20.0 or at > route.length - 20.0:
				continue
			var p := _spot(n, route, at, along)
			if p.is_empty():
				continue
			if float(p["bow"]) <= BOW:
				return p
			if best.is_empty() or float(p["bow"]) < float(best["bow"]):
				best = p
		k += 1
	if not best.is_empty():
		return best
	return _spot(n, route, s, -1.0)


## The network road under `route`'s line `s` m along it: {edge, s, dir, key, route_s, bow (how far its line strays from
## straight over `along` m either way)}, or {} off the network, in a junction, or (`along` 0 or more) with a junction
## of three or more roads within `along` and JUNCTION_CLEAR.
static func _spot(n: RoadNet, route: AdventureRoute, s: float, along: float) -> Dictionary:
	var xz := route.xz_at(s)
	var on := n.locate(xz[0], xz[1], -1, false)
	if on.is_empty() or int(on["node"]) >= 0 or absf(float(on["lat"])) > float(on["width"]) * 0.5:
		return {}
	var e := int(on["edge"])
	var es := float(on["s"])
	var len := n.length_of(e)
	var r := n.region
	if along >= 0.0:
		if n.on_ring(e):
			return {}
		var reach := along + JUNCTION_CLEAR
		if (r.adjacent[r.edge_a[e]].size() >= 3 and es < reach) or (r.adjacent[r.edge_b[e]].size() >= 3 and len - es < reach):
			return {}
	var h := n.heading_at(e, es)
	var dir := 1 if absf(angle_difference(h, route.heading_at_s(s))) < PI * 0.5 else -1
	var c := n.point_at(e, es)
	var right := Vector2(cos(h), sin(h))
	var bow := 0.0
	if along > 0.0:
		var t := -along
		while t <= along:
			bow = maxf(bow, absf((n.point_at(e, clampf(es + t, 0.0, len)) - c).dot(right)))
			t += 10.0
		# Past the edge's end the road goes on through a plain join: how far it would stray is unknown, so count it.
		if es - along < 0.0 or es + along > len:
			bow = maxf(bow, BOW * 0.5)
	return {"edge": e, "s": es, "dir": dir, "key": RoadBlock.key_of(c.x, c.y), "route_s": s, "bow": bow}


# ---------------------------------------------------------------------------- building

func _process(_delta: float) -> void:
	if world == null or world.roads == null:
		return
	build_some(1)


## Builds up to `most` places whose block is in the world and which aren't built in it yet. How many it built.
func build_some(most: int) -> int:
	var made := 0
	for i in places.size():
		var p := places[i]
		var block: Node3D = world.roads.blocks.get(p["key"])
		if block == null:
			continue
		var had = _built.get(i)
		if had != null and is_instance_valid(had) and (had as Node).get_parent() == block:
			continue
		var node := build(i, block)
		if node != null:
			made += 1
			if made >= most:
				break
	return made


## Builds place `i` into `block` (its road block's node), or null when its road's heights aren't in yet.
func build(i: int, block: Node3D) -> Node3D:
	var p := places[i]
	var site: Dictionary = p["site"]
	var kind := str(site["kind"])
	var builder: Callable = world.site_builders.get(kind, Callable())
	if not builder.is_valid():
		return null
	var corner := Vector2(p["key"] as Vector2i) * RoadBlock.SIZE
	var e := int(p["edge"])
	var es := float(p["s"])
	var y := net.road_y(e, es)
	if is_nan(y):
		return null
	var w := net.width_of(e)
	var info := {"width": w, "net": true}
	var xf := frame_of(net, p, corner)
	if not ACROSS.has(kind):
		info["sign"] = verge_xf(net, p, corner, -AdventureStops.SIGN_BEFORE, -(w * 0.5 + 1.8), xf.origin.y)
		info["name_sign"] = verge_xf(net, p, corner, -95.0, -(w * 0.5 + 1.6), xf.origin.y)
	var made = builder.call(site, xf, info)
	if not made is Node3D:
		return null
	block.add_child(made)
	_built[i] = made
	return made


## The frame place `p` is built in (as AdventureChunk gives a site: on the verge on its side, local +x away from the
## road; or across it, for a banner), from `corner` (its block's corner, region frame).
static func frame_of(n: RoadNet, p: Dictionary, corner: Vector2) -> Transform3D:
	var site: Dictionary = p["site"]
	var e := int(p["edge"])
	var es := float(p["s"])
	var h := n.heading_at(e, es) + (0.0 if int(p["dir"]) > 0 else PI)
	var r := Vector3(cos(h), 0.0, sin(h))
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var across := ACROSS.has(str(site["kind"]))
	var side := float(site["side"])
	var lat := 0.0 if across else (n.width_of(e) * 0.5 + 0.9) * side
	var c := n.point_at(e, es)
	var origin := Vector3(c.x - corner.x + r.x * lat, n.road_y(e, es), c.y - corner.y + r.z * lat)
	return Transform3D(Basis(r, Vector3.UP, -fwd) if across else Basis(r * side, Vector3.UP, -fwd * side), origin)


## A frame on the verge `lat` m right of the road (looking the way the ride goes), `ahead` m on from place `p` along its
## edge (as far as the edge goes), facing the way the ride goes, from `corner`; `y` where the road's height isn't in.
static func verge_xf(n: RoadNet, p: Dictionary, corner: Vector2, ahead: float, lat: float, y: float) -> Transform3D:
	var e := int(p["edge"])
	var dir := int(p["dir"])
	var len := n.length_of(e)
	var es := clampf(float(p["s"]) + ahead * dir, minf(10.0, len * 0.5), maxf(len - 10.0, len * 0.5))
	var h := n.heading_at(e, es) + (0.0 if dir > 0 else PI)
	var r := Vector3(cos(h), 0.0, sin(h))
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var c := n.point_at(e, es)
	var ry := n.road_y(e, es)
	return Transform3D(Basis(r, Vector3.UP, -fwd), Vector3(c.x - corner.x + r.x * lat, (y if is_nan(ry) else ry) - 0.05,
		c.y - corner.y + r.z * lat))
