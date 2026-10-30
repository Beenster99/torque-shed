class_name NetNav
extends RefCounted
## The sat nav on the network ride (Ride Anywhere v2, T7): the route provider (see Satnav) that follows the crew's
## agreed route (NetRoute) on the road graph from wherever you are. On the route, it's the way on along it; off it, the
## way back to it ("Turn around", then "Back on route" once you're on it again), never rejoining past the next pin;
## once the crew have agreed to leave the route (Shed.adventure "route" mode "free", see Adventure), the shortest way by
## road to the destination, worked out again whenever you leave it. It says what to do at the junctions coming up from
## the network's own junctions (RoadNet.junction_of): which exit off a roundabout, left or right at a tee.
##
## A crossing by ferry on the route (NetRoute.ferry_at) ends the way ahead at its terminal: "Take the ferry" is what
## there is to say there, and the ferry's line over the water is drawn on from it. Once across (FerryCrossing tells it,
## landed), the way goes on from the far side.
##
## One per ride (of), for this machine's rider, shared by the sat nav's screens and the HUD's warnings. Where you are
## is worked out once a frame, however many of its questions are asked. A new way is found on a worker thread
## (NetRoute.search), the old one shown meanwhile.

## Metres between the points the map draws the way through.
const STEP := 8.0
## How far along the way the guide arrow points (m).
const GUIDE_AHEAD := 60.0
## How long (s) a "Back on route" (and the like) stays up.
const SAY_TIME := 4.0
## Facing within this of along the road (radians) is riding it that way; it's the same as AdventureNav's wrong way.
const WRONG_WAY := deg_to_rad(110.0)
## A route step this many before the one reached still counts as on the route (a junction's roads overlap).
const BEHIND_STEPS := 2

static var _current: NetNav

var world: AdventureWorld
var net: RoadNet
## The crew's agreed route, or null when the plan has no graph steps (then there's no way to show).
var route: NetRoute
## Off, a new way is found there and then (the tests).
var threaded := true
## What the rider's doing: "on_route", "back" (on the way back to the route), "free" (on the way to the destination:
## the crew left the route, or there's no way back to it), "finding" (off the way, a new one being found), "lost"
## (there's no way from here), "off" (off the roads), "" before the first fix.
var status := ""
## The route step reached.
var progress := 0
## Off the route: the way, each Vector2i(edge, the node it's entered from), the first the road the rider's on (the way
## they're to ride it), and which of them they're on now. Back to the route, its last is the route step it rejoins.
var way: Array[Vector2i] = []
var way_at := 0
## The route step the way rejoins it at, -1 when it goes to the destination itself.
var rejoin := -1
## Where the rider is on the roads (RoadNet.locate) and whether they're facing back the way to go.
var hit := {}
var wrong := false
## The crew's route mode as last seen ("route" or "free").
var mode := "route"
## What there is to say ("Back on route"), till when (msec).
var said := ""
var said_until := 0
## The last thing said that's not yet been taken (news).
var _news := ""
var _sites: Array = []      # [{site, m (along the route), at (region x z)}], the route's sites in order
var _memo := Vector3(-1, INF, INF)   # (frame, x, z) the fix was worked out for
var _task := -1
var _lock := Mutex.new()
var _found := {}            # a search's result, handed back from its worker
var _asked := {}            # what that search was for: {mode, progress}
var _want := false          # whether a way's still wanted (not once you're back on the route)


## The sat nav for `w` (a network ride: w.roads), made the first time.
static func of(w: AdventureWorld) -> NetNav:
	if _current != null and _current.world == w:
		return _current
	if _current != null:
		_current.stop()
	_current = NetNav.new(w)
	return _current


## Lets go of ride `w`'s sat nav (the ride's ending): waits for a search under way, and holds on to nothing of it.
static func forget(w: AdventureWorld) -> void:
	if _current != null and _current.world == w:
		_current.stop()
		_current = null


## The sat nav for ride `w`; with no ride (the tests), over `n` along `r`, in the region's own frame.
func _init(w: AdventureWorld, n: RoadNet = null, r: NetRoute = null) -> void:
	world = w
	net = n
	route = r
	if w == null:
		return
	net = w.roads.net if w.roads != null else null
	var plan = Shed.adventure.get("plan", {})
	var style := str((plan as Dictionary).get("mode", "main")) if plan is Dictionary else "main"
	if net != null and w.route != null:
		route = NetRoute.of_pack(w.route.real, net.region, style)
	_find_sites()


## Waits for a search under way (the ride's ending).
func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The crew's route mode (Shed.adventure "route", see Adventure): "route" until they agree to leave it.
static func crew_mode() -> String:
	var r = Shed.adventure.get("route", {})
	return str((r as Dictionary).get("mode", "route")) if r is Dictionary else "route"


## The route's fuel stations and stops (AdventureRoute.sites), each with how far along the route it is.
func _find_sites() -> void:
	_sites.clear()
	if route == null or world.route == null:
		return
	var scale := route.at_m[route.dest_step] / maxf(world.route.length, 1.0)
	for st in world.route.sites:
		var xz := world.route.xz_at(float(st["s"]))
		var on := net.locate(xz[0], xz[1], -1, false)
		var m := route.metres_on(int(on["edge"]), float(on["s"]), float(st["s"]) * scale) if not on.is_empty() else -1.0
		if m < 0.0:
			m = float(st["s"]) * scale
		_sites.append({"site": st, "m": m, "at": Vector2(xz[0], xz[1])})


# ---------------------------------------------------------------------------- where you are

## Works out where the rider at local `pos` facing `fwd` is and the way on (once a frame).
func update(pos: Vector2, fwd: Vector2) -> void:
	var memo := Vector3(Engine.get_process_frames(), pos.x, pos.y)
	if memo == _memo or net == null:
		return
	_memo = memo
	_take_found()
	var xz := _region(pos)
	hit = net.locate(xz.x, xz.y, int(hit.get("edge", -1)), false)
	var m := crew_mode()
	if m != mode:
		mode = m
		_lose_way()
		if mode == "route" and route != null:
			progress = _nearest_step(xz)
	if hit.is_empty() or route == null:
		status = "off" if hit.is_empty() else "lost"
		return
	var e := int(hit["edge"])
	var r := net.region
	var head := atan2(fwd.x, -fwd.y)
	var ahead := absf(wrapf(head - float(hit["heading"]), -PI, PI)) <= PI * 0.5
	var from := r.edge_a[e] if ahead else r.edge_b[e]
	var back := r.other_end(e, from)
	if mode == "route":
		var lo := maxi(progress - BEHIND_STEPS, 0)
		var hi := route.leg_end[mini(progress, route.size() - 1)]
		var i := route.step_in(e, from, lo, hi)
		var turned := i < 0
		if turned:
			i = route.step_in(e, back, lo, hi)
		if i >= 0:
			if status == "back" and not turned:
				_say("Back on route")
			progress = maxi(progress, i)
			status = "on_route"
			_lose_way()
			wrong = turned
			_want = false
			return
	if not way.is_empty():
		for k in range(way_at, way.size()):
			if way[k] == Vector2i(e, from):
				way_at = k
				wrong = false
				return
		if way_at == 0 and way[0] == Vector2i(e, back):
			wrong = true   # (still to turn round)
			return
	if int(hit["node"]) >= 0 and status != "":
		return   # (in a junction: which road you're on settles once you're through it)
	_find_way(e, float(hit["s"]), ahead)


## Forgets the way off the route.
func _lose_way() -> void:
	way.clear()
	way_at = 0
	rejoin = -1
	wrong = false


## The route step nearest region-frame `xz` at or past the one reached (where a crew back on the route carry on from).
func _nearest_step(xz: Vector2) -> int:
	var best := progress
	var best_d := INF
	for i in range(progress, route.dest_step):
		var d := net.region.node_pos[route.froms[i]].distance_squared_to(xz)
		if d < best_d:
			best_d = d
			best = i
	return best


## Looks for the way from `s` along edge `e` (riding it a to b when `ahead`): back to the route's leg, or (the crew
## having left it, or with no way back) to the destination.
func _find_way(e: int, s: float, ahead: bool) -> void:
	if status != "finding":
		status = "finding"
		_lose_way()
	_want = true
	if _task >= 0:
		return
	var enter := route.rejoin_goals(progress) if mode == "route" else {}
	var arrive := {} if mode == "route" else {route.dest_node: 0.0}
	var r := net.region
	var costs := route.costs
	var asked := {"mode": mode, "progress": progress}
	var job := func() -> void:
		var res := NetRoute.search(r, costs, e, s, ahead, enter, arrive)
		if not res["ok"] and not enter.is_empty():
			res = NetRoute.search(r, costs, e, s, ahead, {}, {route.dest_node: 0.0}, INF)
		_lock.lock()
		_found = res
		_asked = asked
		_lock.unlock()
	if threaded:
		_task = WorkerThreadPool.add_task(job, false, "Sat nav way")
	else:
		job.call()
		_take_found()


## Takes up the way a search found, if it's done and still wanted.
func _take_found() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_lock.lock()
	var res := _found
	var asked := _asked
	_found = {}
	_lock.unlock()
	if res.is_empty() or not _want or str(asked.get("mode", "")) != mode:
		return
	_want = false
	if not res["ok"]:
		status = "lost"
		_lose_way()
		return
	way.assign(res["steps"])
	way_at = 0
	wrong = bool(res["turn"])
	rejoin = -1
	if not bool(res["node_goal"]):
		var last := way[way.size() - 1]
		rejoin = route.step_in(last.x, last.y, int(asked["progress"]), route.size())
	status = "back" if rejoin >= 0 else "free"
	if wrong:
		_say("Turn around")


func _say(text: String) -> void:
	said = text
	said_until = Time.get_ticks_msec() + int(SAY_TIME * 1000.0)
	_news = text


## What's been said since it was last asked ("" for nothing): the HUD flashes it.
func news() -> String:
	var out := _news
	_news = ""
	return out


## Region-frame x z of local `p`.
func _region(p: Vector2) -> Vector2:
	return Vector2(p.x + world.origin.x, p.y + world.origin.z) if world != null else p


## Local x z of region-frame `p`.
func _local(p: Vector2) -> Vector2:
	if world == null:
		return p
	var l := world.to_local_pos(p.x, 0.0, p.y)
	return Vector2(l.x, l.z)


# ---------------------------------------------------------------------------- the way ahead

## The steps from here on, each Vector2i(edge, from): the one being ridden (the way it's to be ridden) first, then on
## along the way and the route, `count` at most.
func steps_ahead(count := 64) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if hit.is_empty() or route == null or status in ["off", "lost", "finding", ""]:
		return out
	if status == "on_route":
		for i in range(progress, mini(_ferry_stop(progress), progress + count)):
			out.append(Vector2i(route.edges[i], route.froms[i]))
		return out
	for k in range(way_at, way.size()):
		out.append(way[k])
	if rejoin >= 0:
		for i in range(rejoin + 1, mini(_ferry_stop(rejoin + 1), rejoin + count)):
			out.append(Vector2i(route.edges[i], route.froms[i]))
	return out.slice(0, count)


## Where the way ahead from step `i` stops: the next crossing past it (the steps after are over the water), else the
## route's end.
func _ferry_stop(i: int) -> int:
	var f := route.next_ferry(i + 1)
	return f if f >= 0 else route.size()


## The crossing the way ahead ends at (RealPack.ferries' row, with "step"), {} for none.
func ferry_ahead() -> Dictionary:
	if route == null or status in ["off", "lost", "finding", ""]:
		return {}
	var from := progress if status == "on_route" else (rejoin + 1 if rejoin >= 0 else -1)
	if from < 0:
		return {}
	var f := route.next_ferry(from + 1)
	return route.ferry_before(f) if f >= 0 else {}


## Across the water: the rider's landed at the far terminal of the crossing before step `step` (FerryCrossing).
func landed(step: int) -> void:
	if route == null or step < 0 or step >= route.size():
		return
	progress = step
	status = "on_route"
	_lose_way()
	_want = false
	hit = {}


## How far along the first of steps_ahead the rider is, the way it's to be ridden (m).
func along() -> float:
	if hit.is_empty():
		return 0.0
	var steps := steps_ahead(1)
	if steps.is_empty():
		return 0.0
	var e := steps[0].x
	return float(hit["s"]) if steps[0].y == net.region.edge_a[e] else net.region.edge_len[e] - float(hit["s"])


## Metres left to the destination along the way.
func to_go() -> float:
	if route == null or status in ["off", "lost", "finding", ""]:
		return -1.0
	var r := net.region
	if status == "on_route":
		return maxf(route.at_m[route.dest_step] - route.metres_at(progress, float(hit["s"])), 0.0)
	var m := r.edge_len[way[way_at].x] - along()
	for k in range(way_at + 1, way.size()):
		m += r.edge_len[way[k].x]
	if rejoin >= 0:
		m += maxf(route.at_m[route.dest_step] - route.at_m[rejoin + 1], 0.0)
	return m


## Where the rider is in metres along the route, as near as the way says (to go to the route's places).
func route_metres() -> float:
	var left := to_go()
	return route.at_m[route.dest_step] - left if left >= 0.0 else -1.0


## The way ahead from the rider as region-frame points, about `metres` of it.
func line_ahead(metres: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := steps_ahead()
	if steps.is_empty():
		return out
	var r := net.region
	var gone := 0.0
	var first := true
	for st in steps:
		var len := r.edge_len[st.x]
		var fwd := st.y == r.edge_a[st.x]
		var d := along() if first else 0.0
		if first:
			out.append(net.point_at(st.x, float(hit["s"])))
		first = false
		while d < len and gone < metres:
			d = minf(d + STEP, len)
			var p := net.point_at(st.x, d if fwd else len - d)
			gone += p.distance_to(out[out.size() - 1])
			out.append(p)
		if gone >= metres:
			break
	# (the way ends at a crossing: on over the water along the ferry's line)
	var f := ferry_ahead()
	if not f.is_empty() and gone < metres and out.size() > 0:
		var links := FerryLinks.of(r)
		var i := links.find(str(f["id"]), int(f["from"]), int(f["to"]))
		if i >= 0:
			var water := links.line_from(i, int(f["from"]))
			for k in range(1, water.size()):
				gone += water[k].distance_to(out[out.size() - 1])
				out.append(water[k])
				if gone >= metres:
					break
	return out


## What to do at the next junction on the way with something to say, within `reach` m: {text, type (the junction's
## kind), exit (a roundabout's), turn (radians, + right), distance}, {} for none.
func next_junction(reach: float) -> Dictionary:
	var steps := steps_ahead()
	if steps.is_empty() or (steps.size() < 2 and ferry_ahead().is_empty()):
		return {}
	var r := net.region
	var d := r.edge_len[steps[0].x] - along()
	for k in range(steps.size() - 1):
		if d > reach:
			break
		var said_here := instruction(net, steps, k)
		if not said_here.is_empty():
			said_here["distance"] = maxf(d, 0.0)
			return said_here
		d += r.edge_len[steps[k + 1].x]
	# (nothing to say on the way to a crossing: take the ferry at the end of the road)
	var f := ferry_ahead()
	if not f.is_empty():
		var to := r.edge_len[steps[0].x] - along()
		for k in range(1, steps.size()):
			to += r.edge_len[steps[k].x]
		if to <= reach:
			return {"text": "Take the ferry: %s" % str(f["name"]) if str(f["name"]) != "The ferry" else "Take the ferry",
				"type": "ferry", "exit": 0, "turn": 0.0, "distance": maxf(to, 0.0)}
	return {}


## What to say riding from steps[k] onto steps[k + 1] (each Vector2i(edge, from)) through the node between: {text,
## type, exit, turn}, {} where there's nothing to say (a plain join, on along the main road, round a roundabout's ring).
static func instruction(n: RoadNet, steps: Array[Vector2i], k: int) -> Dictionary:
	var r := n.region
	var cur := steps[k]
	var nxt := steps[k + 1]
	var node := nxt.y
	var j := n.junction_of(node)
	if j.is_empty():
		return {}
	var kind := str(j["kind"])
	if kind in ["roundabout", "mini"]:
		if n.on_ring(nxt.x) and not n.on_ring(cur.x):
			var exit := exit_number(n, steps, k)
			if exit <= 0:
				return {}
			var text := "At the %s, take the %s exit" % ["mini roundabout" if kind == "mini" else "roundabout", AdventureJunctions.ordinal(exit)]
			return {"text": text + _onto(r, cur.x, _exit_edge(n, steps, k)), "type": "roundabout" if kind == "roundabout" else "mini",
				"exit": exit, "turn": 0.0}
		return {}
	var arm_in := _arm(j, cur.x, node)
	var arm_out := _arm(j, nxt.x, node)
	if not arm_in.is_empty() and arm_out.is_empty() and (j["nodes"] as PackedInt32Array).size() > 1:
		# (junctions drawn as one, a divided road's crossing: the way out is the first road on that's one of its arms)
		for i in range(k + 2, steps.size()):
			if not (j["nodes"] as PackedInt32Array).has(steps[i].y):
				break
			arm_out = _arm(j, steps[i].x, steps[i].y)
			if not arm_out.is_empty():
				nxt = steps[i]
				break
	if arm_in.is_empty() or arm_out.is_empty():
		return {}
	var turn := wrapf(float(arm_out["heading"]) - (float(arm_in["heading"]) + PI), -PI, PI)
	if cur.x == nxt.x:
		turn = PI
	elif bool(arm_in["main"]) and bool(arm_out["main"]):
		return {}   # (on along the main road)
	var a := absf(turn)
	var side := "right" if turn > 0.0 else "left"
	var text := ""
	if a > deg_to_rad(150.0):
		text = "Make a U-turn"
	elif a > deg_to_rad(60.0):
		text = "Turn %s" % side
	elif a > deg_to_rad(25.0):
		text = "Keep %s" % side if kind == "fork" else "Bear %s" % side
	elif kind == "fork":
		text = "Keep %s" % side
	elif kind == "cross":
		text = "Straight on at the crossroads"
	else:
		text = "Straight on"
	return {"text": text + _onto(r, cur.x, nxt.x), "type": kind, "exit": 0, "turn": turn}


## " onto the A684" when road `to` has a name of its own that `from` hasn't, else "".
static func _onto(r: RealRegion, from: int, to: int) -> String:
	if to < 0:
		return ""
	var name := str(r.names[r.edge_name[to]])
	if name == "" or name == str(r.names[r.edge_name[from]]):
		return ""
	return " onto %s" % name


## Junction `j`'s arm along `edge` out of `node`, {} for none.
static func _arm(j: Dictionary, edge: int, node: int) -> Dictionary:
	for a in j["arms"]:
		if int(a["edge"]) == edge and int(a["node"]) == node:
			return a
	for a in j["arms"]:
		if int(a["edge"]) == edge:
			return a
	return {}


## Which exit of the roundabout steps[k + 1] rides onto (1 the first): every road you could leave by, counted round the
## ring from where you came on; 0 when the way doesn't leave it.
static func exit_number(n: RoadNet, steps: Array[Vector2i], k: int) -> int:
	var r := n.region
	var j := n.junction_of(steps[k + 1].y)
	var count := 0
	for i in range(k + 1, steps.size()):
		var st := steps[i]
		if not n.on_ring(st.x):
			return count + 1
		var at := r.other_end(st.x, st.y)
		for a in j["arms"]:
			if int(a["node"]) == at and r.passable(int(a["edge"]), at) and int(a["edge"]) != steps[k].x:
				if i + 1 < steps.size() and int(a["edge"]) == steps[i + 1].x:
					return count + 1
				count += 1
	return 0


## The road the way leaves the roundabout by, -1 when it doesn't.
static func _exit_edge(n: RoadNet, steps: Array[Vector2i], k: int) -> int:
	for i in range(k + 1, steps.size()):
		if not n.on_ring(steps[i].x):
			return steps[i].x
	return -1


# ---------------------------------------------------------------------------- the sat nav's questions (see Satnav)

func satnav_guide(pos: Vector2, fwd: Vector2) -> Dictionary:
	update(pos, fwd)
	if status in ["off", ""]:
		return {}
	var out := {"wrong_way": wrong, "turn": 0.0, "status": status, "say": said if Time.get_ticks_msec() < said_until else ""}
	var line := line_ahead(GUIDE_AHEAD)
	if line.size() >= 2:
		var to := _local(line[line.size() - 1]) - pos
		if to.length() < 2.0:
			to = _local(line[1]) - _local(line[0])
		out["turn"] = fwd.angle_to(to)
	return out


func satnav_route(pos: Vector2, fwd: Vector2, metres: float) -> PackedVector2Array:
	update(pos, fwd)
	var out := PackedVector2Array()
	for p in line_ahead(metres):
		out.append(_local(p))
	if not out.is_empty():
		out[0] = pos
	return out


func satnav_junction(pos: Vector2, fwd: Vector2) -> Dictionary:
	update(pos, fwd)
	if wrong:
		return {}
	return next_junction(Satnav.JUNCTION_AHEAD)


func satnav_road_name(pos: Vector2) -> String:
	var xz := _region(pos)
	var on := net.locate(xz.x, xz.y, int(hit.get("edge", -1))) if net != null else {}
	if on.is_empty() or absf(float(on["lat"])) > float(on["width"]) * 0.5 + 12.0:
		return ""
	return net.region.name_of(int(on["edge"]))


## The roads round `pos` (every one the network has there), in the local frame.
func satnav_roads(pos: Vector2, radius: float) -> Array:
	var out := []
	if net == null:
		return out
	var c := _region(pos)
	var view := Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var seen := {}
	var k0 := RoadBlock.key_of(view.position.x, view.position.y)
	var k1 := RoadBlock.key_of(view.end.x, view.end.y)
	var r := net.region
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			for e in net.edges_in(Vector2i(bx, bz)):
				if seen.has(e):
					continue
				seen[e] = true
				var line := r.edge_line[e]
				var kind := "road" if r.surface_of(e) == "tarmac" else "dirt"
				var hw := net.width_of(e) * 0.5
				var run := PackedVector2Array()
				for i in line.size():
					if view.has_point(line[i]):
						if run.is_empty() and i > 0:
							run.append(_local(line[i - 1]))
						run.append(_local(line[i]))
					elif not run.is_empty():
						run.append(_local(line[i]))
						out.append({"pts": run, "kind": kind, "hw": hw})
						run = PackedVector2Array()
				if run.size() > 1:
					out.append({"pts": run, "kind": kind, "hw": hw})
	return out


## The rest of the crew (see AdventureTrip.friends).
func satnav_friends(_pos: Vector2) -> Array:
	var trip := AdventureTrip.current
	if trip == null or trip.world != world:
		return []
	var out := []
	for f in trip.friends():
		var at: Vector3 = f["at"]
		out.append({"name": f["name"], "ahead": f["ahead"], "at": Vector2(at.x, at.z), "off": bool(f.get("off", false))})
	return out


## The fuel along the way, and the destination.
func satnav_points(pos: Vector2, fwd: Vector2) -> Array:
	update(pos, fwd)
	var out := []
	var me := route_metres()
	if me < 0.0:
		return out
	for st in _sites:
		var d := float(st["m"]) - me
		if str(st["site"]["kind"]) == "fuel" and d > -10.0 and float(st["m"]) <= route.at_m[route.dest_step]:
			out.append({"kind": "fuel", "name": "Fuel", "distance": maxf(d, 0.0), "at": _local(st["at"])})
	out.append({"kind": "destination", "name": "Destination", "distance": to_go(), "at": _local(net.region.node_pos[route.dest_node])})
	return out


## How far along the way to the next fuel, food and bed (m; -1 when there's none ahead).
func satnav_next(pos: Vector2, fwd: Vector2) -> Dictionary:
	update(pos, fwd)
	var out := {"fuel": -1.0, "food": -1.0, "sleep": -1.0}
	var me := route_metres()
	if me < 0.0:
		return out
	for st in _sites:
		var kind := str(AdventureStops.NAV.get(str(st["site"]["kind"]), ""))
		var d := float(st["m"]) - me
		if out.has(kind) and float(out[kind]) < 0.0 and d >= -15.0 and float(st["m"]) <= route.at_m[route.dest_step]:
			out[kind] = maxf(d, 0.0)
	return out


## The next `count` stops on the way, nearest first.
func satnav_stops(pos: Vector2, fwd: Vector2, count: int) -> Array:
	update(pos, fwd)
	var out := []
	var me := route_metres()
	if me < 0.0:
		return out
	for st in _sites:
		var site: Dictionary = st["site"]
		var kind := str(site["kind"])
		var d := float(st["m"]) - me
		if not AdventureStops.NAV.has(kind) or d < -15.0:
			continue
		var label := str(site["name"]) if kind in ["village", "cafe", "inn"] else str(AdventureStops.LABELS.get(kind, kind))
		out.append({"kind": AdventureStops.NAV[kind], "site": kind, "name": str(site["name"]), "label": label,
			"distance": maxf(d, 0.0), "at": _local(st["at"])})
		if out.size() >= count:
			break
	return out
