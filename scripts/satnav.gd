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
## WorldRoads. Anything else (the adventure world) sets `Satnav.route_provider` to an object with
## any of these methods (all positions are world x z as Vector2, distances in metres):
##   satnav_roads(pos: Vector2, radius: float) -> Array of {pts: PackedVector2Array, kind, hw}
##       the roads near `pos` to draw
##   satnav_route(pos: Vector2, fwd: Vector2, metres: float) -> PackedVector2Array
##       the road ahead from `pos` going `fwd`, about `metres` of it
##   satnav_road_name(pos: Vector2) -> String     the road you're on ("" off road)
##   satnav_points(pos: Vector2, fwd: Vector2) -> Array of {kind ("fuel" or "destination"),
##       name, distance (m, along the route), at (Vector2, or null when it's off the map)}
## and clears it (null) when it's done.

## Times a second the screen is redrawn.
const RATE := 10.0
## Metres round the bike the map covers, and of the road ahead picked out.
const RADIUS := 320.0
const AHEAD := 600.0

## The route provider (see the top): null for the town's own.
static var route_provider: Object = null

var bike: Bike
var world: World
var viewport: SubViewport
var screen: SatnavScreen         # in the viewport, for the unit on the bars
var hud_screen: SatnavScreen     # the HUD overlay (made by HUD, or null)
var town: TownRoute
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


## The provider in use: the one set, else the town's.
func provider() -> Object:
	if route_provider != null and is_instance_valid(route_provider):
		return route_provider
	return town


func _process(delta: float) -> void:
	var pt := Perf.t0()
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
	var v := {"pos": p, "fwd": fwd, "speed": speed, "roads": [], "route": PackedVector2Array(), "road": "", "points": []}
	if source == null:
		return v
	if source.has_method("satnav_roads"):
		v["roads"] = source.satnav_roads(p, RADIUS)
	if source.has_method("satnav_route"):
		v["route"] = source.satnav_route(p, fwd, AHEAD)
	if source.has_method("satnav_road_name"):
		v["road"] = str(source.satnav_road_name(p))
	if source.has_method("satnav_points"):
		var pts: Array = source.satnav_points(p, fwd)
		pts.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
		# The nearest of each kind.
		var seen := {}
		for q in pts:
			if not seen.has(str(q["kind"])):
				seen[str(q["kind"])] = true
				v["points"].append(q)
	return v


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
