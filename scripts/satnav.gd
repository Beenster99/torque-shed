class_name Satnav
extends Node
## The live sat nav while riding a bike with one fitted: a heading-up moving map of the roads
## round you with the way ahead picked out, the road you're on, and how far to the next fuel and
## the destination when the route knows them. It's drawn (SatnavScreen) into a little
## SubViewport about ten times a second and lit onto the unit's own screen on the bars (see
## KitModel, BikeModel.set_satnav_texture), and the same view can sit on the HUD (Settings
## satnav_hud, {satnav_hud} toggles it).
##
## Where the roads come from is a route provider. In town it's TownRoute, over the riding map's
## WorldRoads; on an adventure (AdventureWorld.current) it's AdventureNav, over its road. Anything
## else sets `Satnav.route_provider` to an object with
## any of these methods (all positions are world x z as Vector2, distances in metres):
##   satnav_roads(pos: Vector2, radius: float) -> Array of {pts: PackedVector2Array, kind, hw}
##       the roads near `pos` to draw
##   satnav_route(pos: Vector2, fwd: Vector2, metres: float) -> PackedVector2Array
##       the road ahead from `pos` going `fwd`, about `metres` of it
##   satnav_road_name(pos: Vector2) -> String     the road you're on ("" off road)
##   satnav_points(pos: Vector2, fwd: Vector2) -> Array of {kind ("fuel", "destination" or
##       "fork"), name, distance (m, along the route), at (Vector2, or null when it's off the map)}
##   satnav_choice(pos: Vector2, fwd: Vector2) -> Dictionary    the ways at a fork coming up
##       (AdventureForks.choice), {} when there's none
##   satnav_stops(pos: Vector2, fwd: Vector2, count: int) -> Array of the next `count` places to
##       stop ahead, nearest first: {kind (AdventureStops.NAV: "food", "rest", "sleep", "fuel"),
##       site (the site's kind), name, label (for the list: "Lay-by", or a cafe's name), distance, at}
##   satnav_guide(pos: Vector2, fwd: Vector2) -> {wrong_way: bool (facing back the way you came),
##       turn: where the way on is, relative to your heading (radians, + to the right)}, {} off it
##   satnav_friends(pos: Vector2) -> Array of the other riders: {name, ahead (m along the road,
##       negative behind), at (Vector2)}
##   satnav_junction(pos: Vector2, fwd: Vector2) -> the next junction on the way where there's
##       something to say, within JUNCTION_AHEAD: {text ("At the roundabout, take the 2nd exit"),
##       type (AdventureJunctions.TYPES), exit (a roundabout's, else 0), distance}, {} for none
##   satnav_next(pos: Vector2, fwd: Vector2) -> {fuel, food, sleep}: how far along the way to the
##       next of each (m), -1 when there's none (the trip computer's page)
## and clears it (null) when it's done.
##
## It has two pages, the map and the trip computer (TripComputer: how far, how long, the speeds,
## the petrol, the climbing, the stops coming up), and {satnav_hud} goes round them: the map, the
## trip page, then the HUD's copy off (Satnav.page; the unit on the bars shows the same page).

## Times a second the screen is redrawn.
const RATE := 10.0
## Metres round the bike the map covers, and of the road ahead picked out.
const RADIUS := 320.0
const AHEAD := 600.0
## How many of the stops ahead the list shows.
const STOPS := 3
## How far ahead (m) a junction's instruction comes up.
const JUNCTION_AHEAD := 400.0

## The route provider (see the top): null for the town's own.
static var route_provider: Object = null
## The page showing: "map" or "trip" (the trip computer), on the unit and the HUD alike.
const PAGES: Array[String] = ["map", "trip"]
static var page := "map"

var bike: Bike
var world: World
var viewport: SubViewport
var screen: SatnavScreen         # in the viewport, for the unit on the bars
var hud_screen: SatnavScreen     # the HUD overlay (made by HUD, or null)
var town: TownRoute
var adventure: AdventureNav      # the adventure road's provider, made when one is on
## The trip meter for this ride, from getting on (an adventure keeps its own, see computer()).
var trip := TripComputer.new()
var _timer := 0.0
var _model: BikeModel            # the model the texture went on


func _init(ridden: Bike = null, on: World = null) -> void:
	bike = ridden
	world = on
	name = "Satnav"


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = KitModel.SCREEN_PX
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	screen = SatnavScreen.new()
	screen.size = Vector2(KitModel.SCREEN_PX)
	viewport.add_child(screen)
	if world != null and world.roads != null:
		town = TownRoute.new(world.roads)


func _exit_tree() -> void:
	if _model != null and is_instance_valid(_model):
		_model.set_satnav_texture(null)


## Whether the bike has a sat nav to show anything on.
func fitted() -> bool:
	return bike != null and is_instance_valid(bike) and bike.build != null and bike.build.has_part("satnav")


## The provider in use: the one set, else the adventure road's while one is on, else the town's.
func provider() -> Object:
	if route_provider != null and is_instance_valid(route_provider):
		return route_provider
	var adv := AdventureWorld.current
	if adv != null and adv.route != null:
		if adventure == null or adventure.world != adv:
			adventure = AdventureNav.new(adv)
		return adventure
	return town


## The trip computer in use: the adventure's (the whole ride, see AdventureTrip.computer) while
## you're out on one, else this ride's own trip meter.
func computer() -> TripComputer:
	var at := AdventureTrip.current
	if at != null and at.on_trip() and at.computer != null:
		return at.computer
	return trip


func _process(delta: float) -> void:
	var pt := Perf.t0()
	if bike != null and is_instance_valid(bike) and computer() == trip:
		trip.step(delta, bike.speed, bike.global_position.y, bike.fuel_litres, bike.surface)
	_tick(delta)
	Perf.add("satnav", pt)


func _tick(delta: float) -> void:
	var on := fitted() and bike.engine_on
	if bike != null and is_instance_valid(bike) and bike.model != _model:
		if _model != null and is_instance_valid(_model):
			_model.set_satnav_texture(null)
		_model = bike.model
		if _model != null and fitted():
			_model.set_satnav_texture(viewport.get_texture() if on else null)
	_timer -= delta
	if _timer > 0.0 or not fitted():
		return
	_timer = 1.0 / RATE
	if _model != null and is_instance_valid(_model):
		_model.set_satnav_texture(viewport.get_texture() if on else null)
	if not on:
		return
	refresh()


## Works out the view now and redraws the screen (and the HUD's).
func refresh() -> void:
	var fwd3 := -bike.global_transform.basis.z
	var v := view_for(provider(), bike.global_position, fwd3, absf(bike.speed))
	v["page"] = page
	if page == "trip":
		v["trip"] = trip_view(computer(), provider(), bike.global_position, fwd3, bike.fuel_litres, bike.build.cruise_economy())
	screen.features = bike.build.satnav_features
	screen.show_view(v)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if hud_screen != null and is_instance_valid(hud_screen) and hud_screen.is_visible_in_tree():
		hud_screen.features = bike.build.satnav_features
		hud_screen.show_view(v)


## The view SatnavScreen draws, at `pos` heading along `fwd3`, from `source` (a route provider).
static func view_for(source: Object, pos: Vector3, fwd3: Vector3, speed := 0.0) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var fwd := Vector2(fwd3.x, fwd3.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2(0, -1)
	var v := {"pos": p, "fwd": fwd, "speed": speed, "roads": [], "route": PackedVector2Array(), "road": "", "points": [], "stops": []}
	if source == null:
		return v
	if source.has_method("satnav_roads"):
		v["roads"] = source.satnav_roads(p, RADIUS)
	if source.has_method("satnav_route"):
		v["route"] = source.satnav_route(p, fwd, AHEAD)
	if source.has_method("satnav_road_name"):
		v["road"] = str(source.satnav_road_name(p))
	if source.has_method("satnav_choice"):
		v["choice"] = source.satnav_choice(p, fwd)
	if source.has_method("satnav_points"):
		var pts: Array = source.satnav_points(p, fwd)
		pts.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
		# The nearest of each kind.
		var seen := {}
		for q in pts:
			if not seen.has(str(q["kind"])):
				seen[str(q["kind"])] = true
				v["points"].append(q)
	if source.has_method("satnav_stops"):
		v["stops"] = source.satnav_stops(p, fwd, STOPS)
	if source.has_method("satnav_guide"):
		v["guide"] = source.satnav_guide(p, fwd)
	if source.has_method("satnav_friends"):
		v["friends"] = source.satnav_friends(p)
	if source.has_method("satnav_junction"):
		v["junction"] = source.satnav_junction(p, fwd)
	return v


## The trip computer's page from `tc`, riding at `pos` along `fwd3` with `fuel_left` litres in the
## tank (`book`: the bike's own km a litre, for the range before there's an average): {ridden,
## to_go (m to the destination, -1 for none), time (s on the move), eta (clock hours, -1 unknown),
## eta_s, average, top (m/s), fuel (litres burnt), economy (km/l), range (km, -1 unknown), next
## {fuel, food, sleep} (m, -1 for none), elevation, climb, descent (m), surface (its name)}.
static func trip_view(tc: TripComputer, source: Object, pos: Vector3, fwd3: Vector3, fuel_left: float, book := 0.0) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var fwd := Vector2(fwd3.x, fwd3.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2(0, -1)
	var to_go := -1.0
	if source != null and source.has_method("satnav_points"):
		for q in source.satnav_points(p, fwd):
			if str(q["kind"]) == "destination":
				to_go = float(q["distance"])
	var next := {"fuel": -1.0, "food": -1.0, "sleep": -1.0}
	if source != null and source.has_method("satnav_next"):
		next.merge(source.satnav_next(p, fwd), true)
	var eta_s := tc.eta_seconds(to_go) if to_go >= 0.0 else -1.0
	return {"ridden": tc.distance, "to_go": to_go, "time": tc.moving_time, "eta_s": eta_s,
		"eta": tc.eta_clock(to_go, Daylight.time_of_day(), Daylight.local_rate()) if eta_s >= 0.0 else -1.0,
		"average": tc.average(), "top": tc.top, "fuel": tc.fuel_used, "economy": tc.economy(), "range": tc.range_km(fuel_left, book),
		"next": next, "elevation": tc.elevation, "climb": tc.climb, "descent": tc.descent,
		"surface": str(AdventureSurface.NAMES.get(tc.surface, tc.surface.capitalize())) if tc.surface != "" else "--"}


## {satnav_hud}: on to the next page, and after the last the HUD's copy goes off (and the next
## press brings it back on the map). What to say about it.
static func next_page() -> String:
	if not Settings.satnav_hud:
		Settings.satnav_hud = true
		page = "map"
		return "Sat nav on the HUD: map"
	var i := PAGES.find(page) + 1
	if i >= PAGES.size():
		Settings.satnav_hud = false
		page = "map"
		return "Sat nav on the HUD off"
	page = PAGES[i]
	return "Sat nav: trip computer" if page == "trip" else "Sat nav: map"


## The town's route provider: the riding map's roads (WorldRoads), the road ahead along the one
## you're on, and the fuel pumps (FuelPump) as the crow flies.
class TownRoute:
	extends RefCounted
	var roads: WorldRoads
	var boxes: Array[Rect2] = []
	var tree: SceneTree

	func _init(r: WorldRoads) -> void:
		roads = r
		for road in roads.roads:
			var xz: PackedVector2Array = road["xz"]
			var box := Rect2(xz[0], Vector2.ZERO)
			for q in xz:
				box = box.expand(q)
			boxes.append(box.grow(float(road["hw"])))
		tree = Engine.get_main_loop() as SceneTree

	func satnav_roads(pos: Vector2, radius: float) -> Array:
		var out := []
		var view := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		for ri in roads.roads.size():
			if not boxes[ri].intersects(view):
				continue
			var road: Dictionary = roads.roads[ri]
			var xz: PackedVector2Array = road["xz"]
			var run := PackedVector2Array()
			# Every other sample (4 m apart) is plenty for a little screen.
			for i in range(0, xz.size(), 2):
				if view.has_point(xz[i]):
					run.append(xz[i])
				elif run.size() > 0:
					run.append(xz[i])
					out.append({"pts": run, "kind": road["kind"], "hw": road["hw"]})
					run = PackedVector2Array()
			if bool(road["closed"]) and run.size() > 0:
				run.append(xz[0])
			if run.size() > 1:
				out.append({"pts": run, "kind": road["kind"], "hw": road["hw"]})
		return out

	func satnav_route(pos: Vector2, fwd: Vector2, metres: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var near := roads.nearest(pos.x, pos.y, 25.0)
		if near.is_empty():
			return out
		var road: Dictionary = roads.roads[int(near["road"])]
		var xz: PackedVector2Array = road["xz"]
		var dirs: PackedVector2Array = road["dir"]
		var n := xz.size()
		var i := int(near["i"])
		var step := 1 if dirs[i].dot(fwd) >= 0.0 else -1
		out.append(pos)
		var gone := 0.0
		var at := i + (1 if step > 0 else 0)
		while gone < metres:
			if at < 0 or at >= n:
				if not bool(road["closed"]):
					break
				at = posmod(at, n)
			var q := xz[at]
			gone += out[out.size() - 1].distance_to(q)
			out.append(q)
			at += step
		return out

	func satnav_road_name(pos: Vector2) -> String:
		var near := roads.nearest(pos.x, pos.y, 25.0)
		return "" if near.is_empty() else str(roads.roads[int(near["road"])]["label"])

	func satnav_points(pos: Vector2, _fwd: Vector2) -> Array:
		var out := []
		if tree == null:
			return out
		for n in tree.get_nodes_in_group(FuelPump.GROUP):
			var p := n as Node3D
			if p == null or not p.is_inside_tree():
				continue
			var at := Vector2(p.global_position.x, p.global_position.z)
			out.append({"kind": "fuel", "name": "Fuel", "distance": pos.distance_to(at), "at": at})
		return out

	## In town there's only fuel to stop for: the nearest pump, as the crow flies.
	func satnav_next(pos: Vector2, fwd: Vector2) -> Dictionary:
		var best := -1.0
		for q in satnav_points(pos, fwd):
			if best < 0.0 or float(q["distance"]) < best:
				best = float(q["distance"])
		return {"fuel": best}


## The adventure road's route provider: the road round you from AdventureRoute (in the world's
## floating frame) with its side roads and roundabouts, the way on to the destination whichever
## way you're facing (with a warning when that's behind you; round each roundabout's island, and
## what to do at it coming up), its fuel stations, the destination and the rest of the crew.
class AdventureNav:
	extends RefCounted
	## Metres between the points the map draws the road through.
	const STEP := 8.0
	## Facing further round than this from the way on (radians) is the wrong way.
	const WRONG_WAY := deg_to_rad(110.0)
	## How far along the way on the guide arrow points (m).
	const GUIDE_AHEAD := 60.0
	var world: AdventureWorld

	func _init(w: AdventureWorld) -> void:
		world = w

	func _at(s: float) -> Vector2:
		var xz := world.route.xz_at(s)
		var p := world.to_local_pos(xz[0], 0.0, xz[1])
		return Vector2(p.x, p.z)

	func _where(pos: Vector2) -> Dictionary:
		return world.locate_local(Vector3(pos.x, 0.0, pos.y), "satnav")

	## Which way along the road `fwd` is: 1 on towards the destination, -1 back (the wrong way).
	func _way(s: float, fwd: Vector2) -> int:
		return -1 if absf((_at(s + STEP) - _at(s)).angle_to(fwd)) > WRONG_WAY else 1

	## The way to go from `pos` facing `fwd`: whether you're facing the wrong way, and where the
	## road on towards the destination is relative to your heading (behind you, a turn right round).
	func satnav_guide(pos: Vector2, fwd: Vector2) -> Dictionary:
		var hit := _where(pos)
		if hit.is_empty():
			return {}
		var s := float(hit["s"])
		var end := minf(world.route.length, world.route.stream_end())
		var to := _at(minf(s + GUIDE_AHEAD, end)) - pos
		if to.length() < 2.0:
			to = _at(minf(s + STEP, end)) - _at(maxf(s - STEP, 0.0))
		return {"wrong_way": _way(s, fwd) < 0, "turn": fwd.angle_to(to)}

	## The rest of the crew along the road (see AdventureTrip.friends).
	func satnav_friends(_pos: Vector2) -> Array:
		var trip := AdventureTrip.current
		if trip == null or trip.world != world:
			return []
		var out := []
		for f in trip.friends():
			var at: Vector3 = f["at"]
			out.append({"name": f["name"], "ahead": f["ahead"], "at": Vector2(at.x, at.z)})
		return out

	func satnav_roads(pos: Vector2, radius: float) -> Array:
		var hit := _where(pos)
		if hit.is_empty():
			return []
		var r := world.route
		var s0 := maxf(float(hit["s"]) - radius * 1.5, 0.0)
		var s1 := minf(float(hit["s"]) + radius * 1.5, r.total)
		var out := []
		var run := PackedVector2Array()
		var surf := r.surface_at_s(s0)
		var s := s0
		while s <= s1:
			var here := r.surface_at_s(s)
			if here != surf and run.size() > 1:
				run.append(_at(s))
				out.append({"pts": run, "kind": "road" if surf == "tarmac" else "dirt", "hw": r.width_at_s(s) * 0.5})
				run = PackedVector2Array()
				surf = here
			run.append(_at(s))
			s += STEP
		if run.size() > 1:
			out.append({"pts": run, "kind": "road" if surf == "tarmac" else "dirt", "hw": r.width_at_s(s1) * 0.5})
		# The other ways at a fork, off the way being taken, drawn fainter.
		var me := world.route_xz(Vector3(pos.x, 0.0, pos.y))
		for way in r.ways_near(me[0], me[1], radius * 1.5):
			var xs: PackedFloat64Array = way["xs"]
			var zs: PackedFloat64Array = way["zs"]
			var pts := PackedVector2Array()
			for k in xs.size():
				var q := world.to_local_pos(xs[k], 0.0, zs[k])
				pts.append(Vector2(q.x, q.z))
			out.append({"pts": pts, "kind": "other", "hw": 2.0})
		# The junctions' side roads, and round each roundabout's island its ring.
		var i0 := int(s0 / AdventureRoute.STEP)
		for st in AdventureJunctions.near(r, i0, int(s1 / AdventureRoute.STEP)):
			if not st.has("arm_geo"):
				continue
			var si: int = st["i"]
			for k in (st["arms"] as Array).size():
				var arm: Dictionary = st["arms"][k]
				var pts := PackedVector2Array()
				for q in st["arm_geo"][k]:
					var lp := world.to_local_pos(r.px[si] + q.x, 0.0, r.pz[si] + q.z)
					pts.append(Vector2(lp.x, lp.z))
				out.append({"pts": pts, "kind": "road" if arm["surf"] == "tarmac" else "dirt", "hw": float(arm["w"]) * 0.5})
			if st.has("rc"):
				var c := world.to_local_pos(r.px[si], 0.0, r.pz[si])
				var ring := PackedVector2Array()
				var rr := float(st["rc"])
				for k in 25:
					ring.append(Vector2(c.x, c.z) + Vector2(cos(TAU * k / 24.0), sin(TAU * k / 24.0)) * rr)
				out.append({"pts": ring, "kind": "road", "hw": float(st["ro"]) - rr})
		return out

	func satnav_route(pos: Vector2, fwd: Vector2, metres: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var hit := _where(pos)
		if hit.is_empty():
			return out
		# Always on towards the destination, whichever way you're facing: turned round, it runs
		# back behind you. Not past a fork till the way's decided: which way to go isn't known yet.
		var s := float(hit["s"])
		var end := clampf(s + metres, 0.0, minf(world.route.total, world.route.stream_end()))
		out.append(pos)
		var rounds := AdventureJunctions.near(world.route, int(s / AdventureRoute.STEP), int(end / AdventureRoute.STEP) + 8, 8) \
			.filter(func(st): return st.has("rc"))
		var at := s
		while at < end:
			at = minf(at + STEP * (0.25 if _round_near(rounds, at) else 1.0), end)
			out.append(_on_way(at, rounds))
		return out

	func _round_near(rounds: Array, at: float) -> bool:
		for st in rounds:
			if absf(at - float(st["s"])) < float(st["rc"]) + 10.0:
				return true
		return false

	## The way on at `s`: on the road's centre line, but round the left of a roundabout's island.
	func _on_way(s: float, rounds: Array) -> Vector2:
		var lat := 0.0
		for st in rounds:
			lat = minf(lat, -AdventureJunctions.swing(st, s - float(st["s"]), 0.0))
		if lat == 0.0:
			return _at(s)
		var xz := world.route.xz_at(s, lat)
		var p := world.to_local_pos(xz[0], 0.0, xz[1])
		return Vector2(p.x, p.z)

	## The next junction on the way with something to say (see AdventureJunctions.instruction),
	## within JUNCTION_AHEAD, heading on; {} for none.
	func satnav_junction(pos: Vector2, fwd: Vector2) -> Dictionary:
		var hit := _where(pos)
		if hit.is_empty() or _way(float(hit["s"]), fwd) < 0:
			return {}
		var s := float(hit["s"])
		var i := int(s / AdventureRoute.STEP)
		for st in AdventureJunctions.near(world.route, i, i + int(JUNCTION_AHEAD / AdventureRoute.STEP)):
			var d := float(st["s"]) - s
			var text := AdventureJunctions.instruction(st, 1)
			if d < -2.0 or d > JUNCTION_AHEAD or text == "":
				continue
			return {"text": text, "type": str(st["type"]), "distance": maxf(d, 0.0),
				"exit": AdventureJunctions.exit_number(st, 1) if str(st["type"]) == "roundabout" else 0}
		return {}

	func satnav_road_name(pos: Vector2) -> String:
		var hit := _where(pos)
		if hit.is_empty() or absf(float(hit["lat"])) > world.route.width_at_s(float(hit["s"])) * 0.5 + 12.0:
			return ""
		var s := float(hit["s"])
		var surf := world.route.surface_at_s(s)
		return "%s road, %s" % [str(AdventureSurface.NAMES.get(surf, surf)), str(AdventureRoute.KIND_NAMES.get(world.route.kind_at_s(s), "")).to_lower()]

	## What's on along the way to the destination, whichever way you're facing.
	func satnav_points(pos: Vector2, _fwd: Vector2) -> Array:
		var hit := _where(pos)
		if hit.is_empty():
			return []
		var s := float(hit["s"])
		var out := []
		for st in world.route.sites_of("fuel"):
			var d := float(st["s"]) - s
			if d > -10.0:
				out.append({"kind": "fuel", "name": "Fuel", "distance": maxf(d, 0.0), "at": _at(float(st["s"]))})
		var left := world.route.length - s
		if left > 0.0:
			out.append({"kind": "destination", "name": "Destination", "distance": left, "at": _at(world.route.length)})
		var f := world.route.next_fork(s)
		if f >= 0:
			out.append({"kind": "fork", "name": "Fork", "distance": maxf(world.route.fork_s(f) - s, 0.0), "at": _at(world.route.fork_s(f))})
		return out

	## How far along the way to the next fuel, food and bed (m; -1 when there's none ahead).
	func satnav_next(pos: Vector2, _fwd: Vector2) -> Dictionary:
		var out := {"fuel": -1.0, "food": -1.0, "sleep": -1.0}
		var hit := _where(pos)
		if hit.is_empty():
			return out
		var s := float(hit["s"])
		var left := 3
		for st in world.route.sites:
			var kind := str(AdventureStops.NAV.get(str(st["kind"]), ""))
			var d := float(st["s"]) - s
			if not out.has(kind) or float(out[kind]) >= 0.0 or d < -15.0 or float(st["s"]) > world.route.length:
				continue
			out[kind] = maxf(d, 0.0)
			left -= 1
			if left == 0:
				break
		return out

	## The choice coming up at a fork, heading on (see AdventureForks.choice), or {}.
	func satnav_choice(pos: Vector2, fwd: Vector2) -> Dictionary:
		var hit := _where(pos)
		if hit.is_empty() or _way(float(hit["s"]), fwd) < 0:
			return {}
		return AdventureForks.choice(world.route, float(hit["s"]))

	## The next `count` stops on the way (AdventureStops' places and the fuel stations), nearest
	## first, whichever way you're facing.
	func satnav_stops(pos: Vector2, _fwd: Vector2, count: int) -> Array:
		var hit := _where(pos)
		if hit.is_empty():
			return []
		var s := float(hit["s"])
		var out := []
		var sites: Array = world.route.sites
		var k := 0
		while k < sites.size() and out.size() < count:
			var st: Dictionary = sites[k]
			k += 1
			var kind := str(st["kind"])
			if not AdventureStops.NAV.has(kind):
				continue
			var d := float(st["s"]) - s
			if d < -15.0:
				continue
			# The list says what it is, or a village's, cafe's or inn's own name.
			var label := str(st["name"]) if kind in ["village", "cafe", "inn"] else str(AdventureStops.LABELS.get(kind, kind))
			out.append({"kind": AdventureStops.NAV[kind], "site": kind, "name": str(st["name"]), "label": label,
				"distance": maxf(d, 0.0), "at": _at(float(st["s"]))})
		return out
