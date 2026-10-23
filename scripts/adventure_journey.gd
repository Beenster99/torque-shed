class_name AdventureJourney
extends RefCounted
## The crew's planning board for a journey across a real region (Shed.journey): pins on the map (JourneyMap), put down
## by anyone in the crew, and the style of ride. When the host likes it, the board becomes a plan (AdventurePlans) and
## the adventure starts along it.
##
## Shed.journey: {} when nothing is pinned, else {region (a RealRegion id), pins: [{x, z, name, by, and lat, lon for a
## pin anywhere}], mode ("main", "scenic" or "tracks")}. The planner takes each pin to the road nearest it, so the same
## pins plan the same road.
##
## A journey anywhere in the world is on the cells it needs (cells_for: those along the line from pin to pin, and a cell
## either side), an area of listed cells (RealRegion.CELLS_PREFIX) worked out again, with each pin's x and z, whenever
## a pin goes down or comes off. A journey can also be on one of the regions bundled with the game, as before.
##
## Shed.route_tv: what the Route planner TVs show (RouteTv, WorldView), one view for every screen and every player, so
## the crew looks at the same thing: {lat, lon (the middle of the map), span (metres across it), tab ("plan" or "find"),
## q (what is typed in the search box)}. A view without lat, lon and span looks at the crew's pins, else at the world.
## It changes only through the host, like the pins.
##
## Actions (Shed.request, from any player): adventure_pin {lat, lon, name, at (where in the list, default the end)} for a
## pin anywhere, or {region, x, z, at} on a region's own map; adventure_unpin {i}, adventure_mode {mode},
## adventure_clear, adventure_view {view: the fields to change}.

const MAX_PINS := AdventurePlans.MAX_PINS
## A pin is put on the nearest junction within this (m); a place's name is taken from within NAME_REACH of it.
const SNAP_M := 800.0
const NAME_REACH := 350.0
## The TV's tabs, the most metres it can show across or the fewest, and the longest search.
const TV_TABS := ["plan", "find"]
const SPAN_MIN := 300.0
const SPAN_MAX := 40000000.0
const MAX_QUERY := 24


static func sanitize(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var region_id := str(v.get("region", ""))
	if RealRegion.extent_of(region_id).size == Vector2.ZERO:
		return {}   # (an area is known by its box: its cells needn't be here yet)
	var pins: Array = []
	var raw = v.get("pins")
	if raw is Array:
		for p in raw:
			if p is Dictionary and pins.size() < MAX_PINS:
				var pin := {"x": snappedf(float(p.get("x", 0.0)), 0.1), "z": snappedf(float(p.get("z", 0.0)), 0.1),
					"name": str(p.get("name", "")).left(AdventurePlans.MAX_NAME), "by": str(p.get("by", "")).left(24)}
				if p.has("lat") and p.has("lon"):
					pin["lat"] = snappedf(float(p["lat"]), 1e-6)
					pin["lon"] = snappedf(float(p["lon"]), 1e-6)
				pins.append(pin)
	var mode := str(v.get("mode", "main"))
	return {"region": region_id, "pins": pins, "mode": mode if RoutePlanner.CLASS_COST.has(mode) else "main"}


## A Route planner TV view (see Shed.route_tv) made safe: {} when it is no good.
static func sanitize_view(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var out := {}
	if v.has("lat") and v.has("lon") and v.has("span"):
		var lat := float(v["lat"])
		var lon := float(v["lon"])
		var span := float(v["span"])
		if is_finite(lat) and is_finite(lon) and is_finite(span):
			out["lat"] = snappedf(clampf(lat, -80.0, 80.0), 1e-6)
			out["lon"] = snappedf(wrapf(lon, -180.0, 180.0), 1e-6)
			out["span"] = snappedf(clampf(span, SPAN_MIN, SPAN_MAX), 0.1)
	var tab := str(v.get("tab", "plan"))
	out["tab"] = tab if TV_TABS.has(tab) else "plan"
	out["q"] = WorldMap.fold(str(v.get("q", ""))).left(MAX_QUERY)
	return out


## Where pin `i` of `journey` is, (lat, lon); Vector2.INF when its map isn't known.
static func pin_geo(journey: Dictionary, i: int) -> Vector2:
	var p: Dictionary = journey["pins"][i]
	if p.has("lat") and p.has("lon"):
		return Vector2(float(p["lat"]), float(p["lon"]))
	var frame := RealRegion.frame_of(str(journey["region"]))
	return RealRegion.from_frame(frame, float(p["x"]), float(p["z"])) if frame != Vector2.INF else Vector2.INF


## Whether `journey` is a journey anywhere (on listed cells), not on one of the bundled regions.
static func anywhere(journey: Dictionary) -> bool:
	return str(journey.get("region", "")).begins_with(RealRegion.CELLS_PREFIX)


## The cells a journey through `geo` (pins' (lat, lon), in order) needs: the cells the straight line from each pin to the
## next runs through and those round them, the first pin's cell first (the journey's frame is there). [] when too many.
static func cells_for(geo: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if geo.is_empty():
		return out
	var seen := {}
	var add := func(c: Vector2i) -> void:
		for k in [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1),
				Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
			var n: Vector2i = c + k
			if not seen.has(n):
				seen[n] = true
				out.append(n)
	add.call(RealRegion.cell_of(geo[0].x, geo[0].y))
	for i in range(1, geo.size()):
		var a: Vector2 = geo[i - 1]
		var b: Vector2 = geo[i]
		var steps := maxi(1, ceili(a.distance_to(b) / (RealRegion.CELL_DEG * 0.25)))
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			add.call(RealRegion.cell_of(p.x, p.y))
	if out.size() > RealRegion.MAX_AREA_CELLS:
		return [] as Array[Vector2i]
	return out


## Whether the game has, or can fetch, the roads at (lat, lon) (from the index it fetched last: no network here).
static func mapped_at(lat: float, lon: float) -> bool:
	var st := CellStore.state_of(RealRegion.cell_of(lat, lon), CellStore.saved_index())
	return st == "here" or st == "baked"


## The bundled region with (lat, lon) on its map, or "".
static func bundled_at(lat: float, lon: float) -> String:
	for id in RealRegion.list():
		if id.begins_with(RealRegion.AREA_PREFIX):
			continue
		var r := RealRegion.get_region(id)
		if r != null and r.bounds.has_point(r.geo_to_xz(lat, lon)):
			return id
	return ""


## Puts the journey anywhere on the cells its pins (`pins`, each with lat and lon) need, each pin's x and z in that
## area's frame; {} when there are none.
static func _anywhere(pins: Array, mode: String) -> Dictionary:
	if pins.is_empty():
		return {}
	var geo: Array = []
	for p: Dictionary in pins:
		geo.append(Vector2(float(p["lat"]), float(p["lon"])))
	var cells := cells_for(geo)
	var frame := RealRegion.cell_middle(cells[0])
	for p: Dictionary in pins:
		var xz := RealRegion.to_frame(frame, float(p["lat"]), float(p["lon"]))
		p["x"] = snappedf(xz.x, 0.1)
		p["z"] = snappedf(xz.y, 0.1)
	return {"region": RealRegion.cells_area_id(cells), "pins": pins, "mode": mode}


## The plan the board makes ({} until it has two pins).
static func plan_of(journey: Dictionary) -> Dictionary:
	if journey.is_empty() or (journey["pins"] as Array).size() < 2:
		return {}
	var region_id := str(journey["region"])
	var region_hash := ""
	if not region_id.begins_with(RealRegion.AREA_PREFIX):
		# (an area is stitched from its cells on the planner's worker, never here: it is known by its box)
		var region := RealRegion.get_region(region_id)
		if region == null:
			return {}
		region_hash = region.hash
	var pins: Array = []
	var names: Array = []
	for p: Dictionary in journey["pins"]:
		pins.append([float(p["x"]), float(p["z"])])
		names.append(str(p["name"]))
	return AdventurePlans.clean({"region": region_id, "region_hash": region_hash, "pins": pins, "names": names, "mode": journey["mode"]})


static func check(peer: int, action: Dictionary) -> String:
	var journey: Dictionary = Shed.journey
	match str(action.get("a", "")):
		"adventure_pin":
			if action.has("lat") and action.has("lon"):
				return _check_anywhere(action)
			var region := RealRegion.get_region(str(action.get("region", "")))
			if region == null:
				return "This game doesn't have that map."
			if not journey.is_empty() and str(journey["region"]) == region.id and (journey["pins"] as Array).size() >= MAX_PINS:
				return "That's as many pins as the map holds (%d)." % MAX_PINS
			var n := region.nearest_connected(float(action.get("x", 0.0)), float(action.get("z", 0.0)), SNAP_M)
			if n < 0:
				return "There's no road near there."
			if not journey.is_empty() and str(journey["region"]) == region.id:
				var pins: Array = journey["pins"]
				var at := clampi(int(action.get("at", pins.size())), 0, pins.size())
				var at_node := region.node_pos[n]
				if at > 0 and Vector2(float(pins[at - 1]["x"]), float(pins[at - 1]["z"])).is_equal_approx(at_node):
					return "There's a pin there already."
			if Adventure.active():
				return "There's an adventure on already."
		"adventure_unpin":
			if journey.is_empty() or int(action.get("i", -1)) < 0 or int(action.get("i", -1)) >= (journey["pins"] as Array).size():
				return "There's no such pin."
		"adventure_mode":
			if not RoutePlanner.CLASS_COST.has(str(action.get("mode", ""))):
				return "There's no style of ride like that."
		"adventure_clear":
			pass
		"adventure_view":
			if not action.get("view") is Dictionary:
				return "That's not a view of the map."
	return ""


static func apply(peer: int, action: Dictionary, who: String) -> String:
	match str(action.get("a", "")):
		"adventure_pin":
			if action.has("lat") and action.has("lon"):
				_pin_anywhere(action, who)
				return ""
			var region := RealRegion.get_region(str(action["region"]))
			if Shed.journey.is_empty() or str(Shed.journey["region"]) != region.id:
				Shed.journey = {"region": region.id, "pins": [], "mode": "main"}
			var n := region.nearest_connected(float(action.get("x", 0.0)), float(action.get("z", 0.0)), SNAP_M)
			var pos := region.node_pos[n]
			var pins: Array = Shed.journey["pins"]
			var at := clampi(int(action.get("at", pins.size())), 0, pins.size())
			pins.insert(at, {"x": snappedf(pos.x, 0.1), "z": snappedf(pos.y, 0.1), "name": place_name(region, n), "by": who})
		"adventure_unpin":
			(Shed.journey["pins"] as Array).remove_at(int(action["i"]))
			if anywhere(Shed.journey):
				Shed.journey = _anywhere(Shed.journey["pins"], str(Shed.journey["mode"]))
		"adventure_mode":
			if not Shed.journey.is_empty():
				Shed.journey["mode"] = str(action["mode"])
		"adventure_clear":
			Shed.journey = {}
		"adventure_view":
			var view: Dictionary = Shed.route_tv.duplicate()
			view.merge(action["view"], true)
			Shed.route_tv = sanitize_view(view)
	return ""


## Puts down a pin anywhere ({lat, lon, name, at}, checked): on the bundled region the journey is on (or the one there,
## for a first pin where the game has no cells), else on the cells the pins need.
static func _pin_anywhere(action: Dictionary, who: String) -> void:
	var lat := float(action["lat"])
	var lon := float(action["lon"])
	var name := str(action.get("name", "")).left(AdventurePlans.MAX_NAME)
	var journey: Dictionary = Shed.journey
	var bundled := "" if not journey.is_empty() else ("" if mapped_at(lat, lon) else bundled_at(lat, lon))
	if (not journey.is_empty() and not anywhere(journey)) or bundled != "":
		var r := RealRegion.get_region(bundled if bundled != "" else str(journey["region"]))
		var xz := r.geo_to_xz(lat, lon)
		apply(0, {"a": "adventure_pin", "region": r.id, "x": xz.x, "z": xz.y, "at": action.get("at", 99)}, who)
		return
	var pins: Array = (journey.get("pins", []) as Array).duplicate(true)
	var at := clampi(int(action.get("at", pins.size())), 0, pins.size())
	pins.insert(at, {"lat": snappedf(lat, 1e-6), "lon": snappedf(lon, 1e-6), "name": name, "by": who})
	Shed.journey = _anywhere(pins, str(journey.get("mode", "main")))


## A name for the place at junction `n`: the nearest named place (shop, village, peak...) within NAME_REACH, else the
## road, else "".
static func place_name(region: RealRegion, n: int) -> String:
	var here := region.node_pos[n]
	var best := ""
	var best_d := NAME_REACH
	for q: Dictionary in region.pois:
		if str(q.get("name", "")) == "":
			continue
		var d := Vector2(float(q["x"]), float(q["z"])).distance_to(here)
		if d < best_d:
			best_d = d
			best = str(q["name"])
	for m: Dictionary in region.landmarks:
		if str(m.get("name", "")) == "":
			continue
		var d := Vector2(float(m["x"]), float(m["z"])).distance_to(here)
		if d < best_d:
			best_d = d
			best = str(m["name"])
	if best != "":
		return best
	for ei in region.adjacent[n]:
		var raw := str(region.names[region.edge_name[ei]])
		if raw != "":
			return raw
	return ""


## Checks a pin put down anywhere ({lat, lon, name, at}): "" if it can go down.
static func _check_anywhere(action: Dictionary) -> String:
	var lat := float(action.get("lat", NAN))
	var lon := float(action.get("lon", NAN))
	if not is_finite(lat) or not is_finite(lon) or absf(lat) > 80.0 or absf(lon) > 180.0:
		return "That's off the map."
	if Adventure.active():
		return "There's an adventure on already."
	var journey: Dictionary = Shed.journey
	if not journey.is_empty() and (journey["pins"] as Array).size() >= MAX_PINS:
		return "That's as many pins as the map holds (%d)." % MAX_PINS
	var bundled := ""
	if not journey.is_empty() and not anywhere(journey):
		bundled = str(journey["region"])
	elif journey.is_empty() and not mapped_at(lat, lon):
		bundled = bundled_at(lat, lon)
	if bundled != "":
		# On a bundled region's map: the pin must be on it, near a road.
		var r := RealRegion.get_region(bundled)
		var xz := r.geo_to_xz(lat, lon) if r != null else Vector2.INF
		if r == null or not r.bounds.has_point(xz):
			return "That's off the %s map you're pinning on: clear the pins to go somewhere else." % (r.title if r else "")
		if r.nearest_connected(xz.x, xz.y, SNAP_M) < 0:
			return "There's no road near there."
		return ""
	if not mapped_at(lat, lon):
		return "Nobody has mapped the roads there yet."
	var geo: Array = []
	for i in (journey.get("pins", []) as Array).size():
		geo.append(pin_geo(journey, i))
	geo.insert(clampi(int(action.get("at", geo.size())), 0, geo.size()), Vector2(lat, lon))
	if cells_for(geo).is_empty():
		return "That's too far for one ride's map: keep the pins nearer together."
	return ""


## Why the host can't start the board's journey ("" if they can).
static func start_reason(journey: Dictionary) -> String:
	if not Shed.is_authority():
		return "The host starts the ride."
	if Adventure.active():
		return "There's an adventure on already."
	if (journey.get("pins", []) as Array).size() < 2:
		return "Pin a start and somewhere to get to."
	return ""


## Checks an adventure_start that carries a plan ("" if all is well).
static func start_check(action: Dictionary) -> String:
	var plan := AdventurePlans.clean(action.get("plan"))
	if plan.is_empty():
		return "That journey can't be planned."
	var res := AdventurePlans.result(plan, true)
	if not bool(res["ok"]):
		return str(res["error"])
	if (res["pack"] as RealPack).max_km() < Adventure.MIN_KM:
		return "That's a short hop: pin somewhere at least %d km away." % int(Adventure.MIN_KM)
	if (res["pack"] as RealPack).max_km() > Adventure.MAX_KM:
		return "That's a long way: keep it under %d km." % int(Adventure.MAX_KM)
	return ""


## What a started adventure along `action`'s plan holds: {plan, real, real_hash, km, theme, dest (the last pin's place)}.
static func start_info(action: Dictionary) -> Dictionary:
	var plan := AdventurePlans.clean(action.get("plan"))
	var pack := AdventurePlans.pack_for(plan)
	var names: Array = plan.get("names", [])
	var dest := str(names[names.size() - 1]) if not names.is_empty() else ""
	if dest == "":
		var region := RealRegion.get_region(str(plan["region"]))
		dest = "the end of the road" if region == null else region.title
	return {"plan": plan, "real": pack.id, "real_hash": pack.hash, "km": floorf(pack.max_km() * 10.0) / 10.0, "theme": pack.theme, "dest": dest}
