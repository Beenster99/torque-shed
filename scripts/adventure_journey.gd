class_name AdventureJourney
extends RefCounted
## The crew's planning board for a journey across a real region (Shed.journey): pins on the map (JourneyMap), put down
## by anyone in the crew, and the style of ride. When the host likes it, the board becomes a plan (AdventurePlans) and
## the adventure starts along it.
##
## Shed.journey: {} when nothing is pinned, else {region (a RealRegion id), pins: [{x, z, name, by, and lat, lon for a
## pin anywhere}], mode ("main", "scenic" or "tracks"), in: [peer, ...] (who has said "I'm in" to the journey as it
## stands: a pin moved or the style changed clears them)}. The planner takes each pin to the road nearest it, so the
## same pins plan the same road. The host's Start (start_reason) waits until everyone in the shed is in, or most of them
## (someone may have wandered off); on their own, a rider just starts.
##
## A journey anywhere in the world is on the cells it needs (cells_for: those along the line from pin to pin, and a cell
## either side), an area of listed cells (RealRegion.CELLS_PREFIX) worked out again, with each pin's x and z, whenever
## a pin goes down or comes off. A journey can also be on one of the regions bundled with the game, as before.
##
## Shed.route_tv: what the Route planner TVs show (RouteTv, WorldView), one view for every screen and every player, so
## the crew looks at the same thing: {lat, lon (the middle of the map), span (metres across it), tab ("plan" or "find"),
## q (what is typed in the search box), survey (the crew's survey, see Survey)}. A view without lat, lon and span looks
## at the crew's pins, else at the world.
## It changes only through the host, like the pins.
##
## Actions (Shed.request, from any player): adventure_pin {lat, lon, name, at (where in the list, default the end)} for a
## pin anywhere, or {region, x, z, at} on a region's own map; adventure_unpin {i}, adventure_mode {mode},
## adventure_in {in: true or false}, adventure_load {journey: a kept journey} (pins it all again: a past ride or a
## journey code), adventure_clear, adventure_view {view: the fields to change}, adventure_survey {cells} (see Survey).

const MAX_PINS := AdventurePlans.MAX_PINS
## A pin is put on the nearest junction within this (m); a place's name is taken from within NAME_REACH of it.
const SNAP_M := 800.0
const NAME_REACH := 350.0
## The TV's tabs, the most metres it can show across or the fewest, and the longest search.
const TV_TABS := ["plan", "find", "rides"]
const SPAN_MIN := 300.0
const SPAN_MAX := 40000000.0
const MAX_QUERY := 24
## How a journey code (code_of) starts.
const CODE_PREFIX := "TS1."


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
	var out := {"region": region_id, "pins": pins, "mode": mode if RoutePlanner.CLASS_COST.has(mode) else "main"}
	var who_in: Array = []
	if v.get("in") is Array:
		for peer in v["in"]:
			if (peer is int or peer is float) and not who_in.has(int(peer)) and who_in.size() < 16:
				who_in.append(int(peer))
	if not who_in.is_empty():
		out["in"] = who_in
	return out


## A journey kept (in a diary, or as a code to send a mate): {pins: [[lat, lon, name], ...], mode}, where on Earth
## its pins are and the style of ride, whatever map it was planned on. {} when it isn't one.
static func sanitize_kept(v: Variant) -> Dictionary:
	if not v is Dictionary or not v.get("pins") is Array:
		return {}
	var pins: Array = []
	for p in v["pins"]:
		if not p is Array or (p as Array).size() < 2 or pins.size() >= MAX_PINS:
			return {}
		var lat := float(p[0])
		var lon := float(p[1])
		if not is_finite(lat) or not is_finite(lon) or absf(lat) > 80.0 or absf(lon) > 180.0:
			return {}
		pins.append([snappedf(lat, 1e-5), snappedf(lon, 1e-5), str(p[2] if (p as Array).size() > 2 else "").left(AdventurePlans.MAX_NAME)])
	if pins.size() < 2:
		return {}
	var mode := str(v.get("mode", "main"))
	return {"pins": pins, "mode": mode if RoutePlanner.CLASS_COST.has(mode) else "main"}


## The journey kept of plan `plan` (see AdventurePlans: a started adventure's), or {}.
static func kept_of_plan(plan: Dictionary) -> Dictionary:
	var frame := RealRegion.frame_of(str(plan.get("region", "")))
	if frame == Vector2.INF:
		return {}
	var pins: Array = []
	var names: Array = plan.get("names", [])
	for i in (plan.get("pins", []) as Array).size():
		var xz: Array = plan["pins"][i]
		var g := RealRegion.from_frame(frame, float(xz[0]), float(xz[1]))
		pins.append([g.x, g.y, str(names[i]) if i < names.size() else ""])
	return sanitize_kept({"pins": pins, "mode": plan.get("mode", "main")})


## The journey kept of the crew's board `journey` (Shed.journey), or {}.
static func kept_of(journey: Dictionary) -> Dictionary:
	var pins: Array = []
	for i in (journey.get("pins", []) as Array).size():
		var g := pin_geo(journey, i)
		if g == Vector2.INF:
			return {}
		pins.append([g.x, g.y, str(journey["pins"][i].get("name", ""))])
	return sanitize_kept({"pins": pins, "mode": journey.get("mode", "main")})


## A journey kept, as a code to paste to a mate: "TS1." and the journey, short (base64 of its JSON).
static func code_of(kept: Dictionary) -> String:
	if kept.is_empty():
		return ""
	var flat: Array = []
	for p: Array in kept["pins"]:
		flat.append([int(round(float(p[0]) * 1e5)), int(round(float(p[1]) * 1e5)), p[2]])
	var text := JSON.stringify({"p": flat, "m": kept["mode"]})
	return CODE_PREFIX + Marshalls.utf8_to_base64(text).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")


## The journey in a code (code_of) found anywhere in `text`, or {}.
static func from_code(text: String) -> Dictionary:
	var m := RegEx.create_from_string("TS1\\.([A-Za-z0-9_-]+)").search(text)
	if m == null:
		return {}
	var b64 := m.get_string(1).replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var v = JSON.parse_string(Marshalls.base64_to_utf8(b64))
	if not v is Dictionary or not v.get("p") is Array:
		return {}
	var pins: Array = []
	for p in v["p"]:
		if not p is Array or (p as Array).size() < 3:
			return {}
		pins.append([float(p[0]) / 1e5, float(p[1]) / 1e5, str(p[2])])
	return sanitize_kept({"pins": pins, "mode": v.get("m", "main")})


## The riders in the shed who are in on `journey` (see Shed.journey), in the crew's order.
static func riders_in(journey: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var marked: Array = journey.get("in", [])
	for peer in Shed.crew:
		if marked.has(int(peer)):
			out.append(int(peer))
	return out


## Whether `journey` needs the crew's say-so before the host starts it: when there's more than one in the shed.
static func needs_crew() -> bool:
	return Shed.crew.size() > 1


## Who is in and who isn't yet, said short ("Sam and Jo are in; waiting for Kit."), or "" on your own.
static func crew_line(journey: Dictionary) -> String:
	if not needs_crew():
		return ""
	var yes := PackedStringArray()
	var not_yet := PackedStringArray()
	var marked := riders_in(journey)
	for peer in Shed.crew:
		var name := str(Shed.crew[peer].get("name", "Someone"))
		if marked.has(int(peer)):
			yes.append(name)
		else:
			not_yet.append(name)
	if not_yet.is_empty():
		return "Everyone's in."
	if yes.is_empty():
		return "Nobody's in yet: say I'm in when the ride suits you."
	return "%s %s in; waiting for %s." % [_and(yes), "is" if yes.size() == 1 else "are", _and(not_yet)]


static func _and(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


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
	var survey := Survey.sanitize(v.get("survey"))
	if not survey.is_empty():
		out["survey"] = survey
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
		"adventure_in":
			if (journey.get("pins", []) as Array).size() < 2:
				return "Pin a start and somewhere to get to first."
			if Adventure.active():
				return "There's an adventure on already."
		"adventure_load":
			if sanitize_kept(action.get("journey")).is_empty():
				return "That's not a journey the game can pin."
			if Adventure.active():
				return "There's an adventure on already."
		"adventure_clear":
			pass
		"adventure_view":
			if not action.get("view") is Dictionary:
				return "That's not a view of the map."
		"adventure_survey":
			if Survey.cells_of(action.get("cells")).is_empty():
				return "There's nothing there to survey."
	return ""


static func apply(peer: int, action: Dictionary, who: String) -> String:
	var before := _say_so_of(Shed.journey)
	var said := _apply(peer, action, who)
	# The journey changed under them: everyone's "I'm in" is for a journey that isn't there now.
	if not Shed.journey.is_empty() and _say_so_of(Shed.journey) != before:
		Shed.journey.erase("in")
	return said


## What a rider says they're in on: the pins and the style of ride.
static func _say_so_of(journey: Dictionary) -> String:
	return JSON.stringify([journey.get("region", ""), journey.get("pins", []), journey.get("mode", "")])


static func _apply(peer: int, action: Dictionary, who: String) -> String:
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
		"adventure_in":
			var marked: Array = Shed.journey.get("in", [])
			marked.erase(peer)
			if bool(action.get("in", true)):
				marked.append(peer)
			Shed.journey["in"] = marked
		"adventure_load":
			return _load(sanitize_kept(action["journey"]), who)
		"adventure_clear":
			Shed.journey = {}
		"adventure_view":
			var view: Dictionary = Shed.route_tv.duplicate()
			view.erase("survey")   # (the survey is the host's to change, see Survey)
			var asked: Dictionary = action["view"]
			for k in asked:
				if str(k) != "survey":
					view[k] = asked[k]
			view["survey"] = Shed.route_tv.get("survey", {})
			Shed.route_tv = sanitize_view(view)
		"adventure_survey":
			Survey.start(Survey.cells_of(action["cells"]))
	return ""


## Pins kept journey `kept` again (checked), in place of the board's: each pin as if put down, by `who`. What to tell
## the crew ("*..."), or why some of it couldn't go down.
static func _load(kept: Dictionary, who: String) -> String:
	Shed.journey = {}
	var missed := 0
	for p: Array in kept["pins"]:
		var pin := {"a": "adventure_pin", "lat": float(p[0]), "lon": float(p[1]), "name": str(p[2])}
		if _check_anywhere(pin) != "":
			missed += 1
			continue
		_pin_anywhere(pin, who)
	if not Shed.journey.is_empty():
		Shed.journey["mode"] = str(kept["mode"])
	if missed == (kept["pins"] as Array).size():
		return "None of that journey's pins could go down here: nobody has mapped its roads in this game."
	if missed > 0:
		return "*%s pinned a journey again, but %d of its pins couldn't go down (their roads aren't mapped here)." % [who, missed]
	return "*%s pinned a journey again: %d pins, %s." % [who, (kept["pins"] as Array).size(), str(JourneyMap.MODE_TEXT[kept["mode"]][0]).to_lower()]


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
		_apply(0, {"a": "adventure_pin", "region": r.id, "x": xz.x, "z": xz.y, "at": action.get("at", 99)}, who)
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
	if needs_crew():
		var n := riders_in(journey).size()
		if n * 2 <= Shed.crew.size():
			return "Waiting for the crew: %d of %d in." % [n, Shed.crew.size()]
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
