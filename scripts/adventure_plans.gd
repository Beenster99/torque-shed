class_name AdventurePlans
extends RefCounted
## Journeys the crew plan across a real region (RealRegion) on the shed's map (JourneyMap), turned into the roads they
## ride (RoutePlanner). A plan is {region, region_hash, pins: [[x, z]], names: [String], mode}; every machine plans
## the same plan itself, on a worker thread as the pins go down so it is ready by the time the host starts the ride,
## and the road's hash says everyone got the same one (AdventureTrip.real_mismatch). Plans are kept by their key, so
## asking again costs nothing.

const MAX_PINS := 8
const MAX_NAME := 32
## How far past the region's edge a pin may be (the nearest road is found from it).
const MARGIN := 1000.0

## key -> {ok, error, pack}: planned plans.
static var _done := {}
## key -> worker task id: plans being worked out.
static var _tasks := {}
static var _lock := Mutex.new()
## key -> what a worker planning it is doing ("the map: 3 of 9 parts of the world"), while it does (progress_of).
static var _progress := {}
## key -> [stage (STAGES), done, out of], while a worker plans it (stage_of).
static var _stages := {}
## The steps of planning a road, in order (stage_of): fetching the map of that part of the world, reading its roads,
## rivers and trees, planning the road along them, and shaping the land along it.
const STAGES: Array[String] = ["map", "roads", "route", "land"]
## The index of the world's cells is fetched afresh before planning when it's older than this (ms), so a plan takes in
## cells and profiles baked minutes ago.
const INDEX_FRESH_MS := 60000
## A plan that couldn't be made only for now (the map there still being finished) is planned again once it's this old
## (ms), instead of being kept.
const RETRY_MS := 30000
## Why a plan can't be made while the map is still being finished.
const FINISHING := "The map of this part of the world is still being finished (its place profiles are on their way): try again in a minute or two."


## `v` as a plan this game can plan, or {} when it is not one (no such region, too few or too many pins, a pin off the map).
static func clean(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	# (an area of cells is checked against its box: its cells may not be here yet, they come with the plan: _run)
	var region_id := str(v.get("region", ""))
	var extent := RealRegion.extent_of(region_id)
	if extent.size == Vector2.ZERO:
		return {}
	var pins: Array = []
	var raw = v.get("pins")
	if not raw is Array or (raw as Array).size() < 2 or (raw as Array).size() > MAX_PINS:
		return {}
	var box := extent.grow(MARGIN)
	for p in raw:
		if not p is Array or (p as Array).size() < 2:
			return {}
		var pin := Vector2(float(p[0]), float(p[1]))
		if not box.has_point(pin):
			return {}
		pins.append([snappedf(pin.x, 0.1), snappedf(pin.y, 0.1)])
	var names: Array = []
	var raw_names = v.get("names", [])
	if raw_names is Array:
		for n in raw_names:
			names.append(str(n).left(MAX_NAME))
	var mode := str(v.get("mode", "main"))
	if not RoutePlanner.CLASS_COST.has(mode):
		mode = "main"
	var region_hash := str(v.get("region_hash", ""))
	if not v.has("region_hash") and not region_id.begins_with(RealRegion.AREA_PREFIX):
		region_hash = RealRegion.get_region(region_id).hash
	return {"region": region_id, "region_hash": region_hash, "pins": pins, "names": names, "mode": mode}


## What identifies a plan: the same plans have the same key.
static func key(plan: Dictionary) -> String:
	return JSON.stringify({"r": plan.get("region"), "h": plan.get("region_hash"), "p": plan.get("pins"), "m": plan.get("mode")}, "", true)


## The request RoutePlanner.plan takes.
static func _request(plan: Dictionary) -> Dictionary:
	var pins: Array = []
	for p: Array in plan["pins"]:
		pins.append(Vector2(float(p[0]), float(p[1])))
	return {"pins": pins, "mode": plan["mode"], "names": plan.get("names", []), "seed": 0}


static func _run(plan: Dictionary) -> Dictionary:
	var k := key(plan)
	if str(plan["region"]).begins_with(RealRegion.AREA_PREFIX):
		# An area of the world's cells: those the game hasn't got are fetched first (on this worker), from an index
		# no more than a minute old.
		_say(k, "the map", 0)
		var refreshed := CellStore.index_age() > INDEX_FRESH_MS
		CellStore.index(refreshed)
		var why := RealRegion.fetch_area(str(plan["region"]), func(done: int, total: int):
			_say(k, "the map, %d of %d parts of the world" % [done, total], 0, done, total))
		if why != "":
			_say(k, "")
			return {"ok": false, "error": why, "pack": null}
		# Cells whose place profiles are still being made: asked again once, then it's too soon.
		var cells := RealRegion.area_cells(str(plan["region"]))
		if not CellStore.finishing(cells, CellStore.index()).is_empty() and not refreshed:
			CellStore.index(true)
		if not CellStore.finishing(cells, CellStore.index()).is_empty():
			_say(k, "")
			return {"ok": false, "error": FINISHING, "pack": null, "map": true, "retry": true}
	_say(k, "the roads, the rivers and the trees", 1)
	var region := RealRegion.get_region(str(plan["region"]))
	if region == null:
		return {"ok": false, "error": "This game doesn't have that part of the world.", "pack": null}
	if str(plan.get("region_hash", "")) != "" and str(plan["region_hash"]) != region.hash:
		return {"ok": false, "error": "Your copy of the %s map isn't the host's: update the game to join." % region.title, "pack": null,
			"map": region.id.begins_with(RealRegion.AREA_PREFIX)}
	_say(k, "the road", 2)
	var res := RoutePlanner.plan(region, _request(plan), func(done: int, total: int):
		_say(k, "the lie of the land, %d of %d map tiles" % [done, total], 3, done, total))
	_say(k, "")
	if bool(res["ok"]):
		RealPack.register(res["pack"])
		PlaceLook.warm(res["pack"])   # (the place's profiles, for its look: fetched here, off the main thread)
	return res


static func _say(k: String, what: String, stage := -1, done := 0, total := 0) -> void:
	_lock.lock()
	if what == "":
		_progress.erase(k)
		_stages.erase(k)
	else:
		_progress[k] = what
		if stage >= 0:
			_stages[k] = [stage, done, total]
	_lock.unlock()


## Where a worker planning `plan` has got to: [stage (its place in STAGES), done, out of (0 when it isn't counted)],
## or [] when none is.
static func stage_of(plan: Dictionary) -> Array:
	_lock.lock()
	var at: Array = (_stages.get(key(plan), []) as Array).duplicate()
	_lock.unlock()
	return at


## What a worker planning `plan` is doing now ("the lie of the land, 40 of 120 map tiles"), or "" when none is.
static func progress_of(plan: Dictionary) -> String:
	_lock.lock()
	var what := str(_progress.get(key(plan), ""))
	_lock.unlock()
	return what


## The road for `plan`, planned now if it is not ready (waits for it if a worker is on it); null with `why` unsaid
## when it can't be planned. Use `error` for the reason.
static func pack_for(plan: Dictionary) -> RealPack:
	var res := result(plan, true)
	return res["pack"] if res.has("pack") else null


## {ok, error, pack} for `plan`: planned now when `wait`, else {} until a worker has done it (and one is started).
static func result(plan: Dictionary, wait := false) -> Dictionary:
	if plan.is_empty():
		return {"ok": false, "error": "Pin a start and somewhere to get to.", "pack": null}
	var k := key(plan)
	_lock.lock()
	if _done.has(k) and bool((_done[k] as Dictionary).get("retry", false)) \
			and Time.get_ticks_msec() - int(_done[k].get("at", 0)) > RETRY_MS:
		_done.erase(k)   # (too soon then: planned again now)
	if _done.has(k):
		var got: Dictionary = _done[k]
		_lock.unlock()
		return got
	var task: int = _tasks.get(k, -1)
	_lock.unlock()
	if task >= 0:
		if not wait:
			return {}
		WorkerThreadPool.wait_for_task_completion(task)
		_lock.lock()
		_tasks.erase(k)   # (waited for here: poll must not wait for it again)
		_lock.unlock()
		return result(plan, true)
	if wait:
		var res := _run(plan)
		res["at"] = Time.get_ticks_msec()
		_lock.lock()
		_done[k] = res
		_lock.unlock()
		return res
	_lock.lock()
	_tasks[k] = WorkerThreadPool.add_task(func():
		var res := _run(plan)
		res["at"] = Time.get_ticks_msec()
		_lock.lock()
		_done[k] = res
		_lock.unlock())
	_lock.unlock()
	return {}


## Forgets `plan`'s road, so the next ask plans it afresh (once a worker planning it now has finished).
static func forget(plan: Dictionary) -> void:
	_lock.lock()
	_done.erase(key(plan))
	_lock.unlock()


## After this game's map of `plan`'s area turned out not to be the host's: the world's index fetched afresh, the
## cells baked again since this game fetched them fetched again, every place profile and kit forgotten (fetched again
## as they're asked for: a guessed one may now have come), and the plan forgotten, so the next ask plans it from
## scratch. Blocks: a worker's job, and never while this game is out on a ride (its roads would change under it).
static func refresh(plan: Dictionary) -> void:
	var region_id := str(plan.get("region", ""))
	var idx := CellStore.index(true)
	if region_id.begins_with(RealRegion.AREA_PREFIX):
		CellStore.refetch_stale(RealRegion.area_cells(region_id), idx)
	PlaceProfile.forget()
	RegionKit.forget()
	RealRegion.forget_areas()
	forget(plan)


## Collects the plans the workers have finished (call now and then from the main thread).
static func poll() -> void:
	_lock.lock()
	for k in _tasks.keys():
		if _done.has(k) and WorkerThreadPool.is_task_completed(_tasks[k]):
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.erase(k)
	_lock.unlock()


## Waits for every plan being worked out (before the game closes, or a test ends).
static func wait_all() -> void:
	_lock.lock()
	var ids: Array = _tasks.values()
	_tasks.clear()
	_lock.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)


# ---------------------------------------------------------------------------- sample rides

## A tour of each bundled region, pin by pin (region x, z), for the Debug tab's quick start and the tests: round
## Shodoshima, and a loop of the Dales (Hawes, over to Swaledale, Reeth, Leyburn, and back up Wensleydale).
const TOURS := {
	"shodoshima": [[-5881, 1526], [-306, 1293], [4560, 2074], [7721, -3202], [1792, -4787], [-174, -3502], [-5951, 1062]],
	"dales": [[-10180, 3993], [-2422, -4363], [7187, -4599], [13686, 3361], [2813, 5382], [-4096, 3608], [-11640, 3115]],
}


## The plan of the first `pins` pins (2 or more) of `region`'s tour, each pin named after the town or village it's in.
static func tour(region_id := "shodoshima", pins := 0) -> Dictionary:
	var region := RealRegion.get_region(region_id)
	if region == null or not TOURS.has(region_id):
		return {}
	var all: Array = TOURS[region_id]
	var n := clampi(pins if pins > 0 else all.size(), 2, all.size())
	var at: Array = []
	var names: Array = []
	for p: Array in all.slice(0, n):
		var want := Vector2(float(p[0]), float(p[1]))
		var node := through_node(region, want)
		var pos := region.node_pos[node] if node >= 0 else want
		at.append([pos.x, pos.y])
		var town := ""
		var best := 2000.0
		for q: Dictionary in region.places:
			var d := Vector2(float(q["x"]), float(q["z"])).distance_to(want)
			if d < best:
				best = d
				town = str(q["name"])
		names.append(town)
	return clean({"region": region.id, "region_hash": region.hash, "pins": at, "names": names, "mode": "main"})


## The junction near `want` (within 1.2 km) on the biggest road that runs through it, so a ride pinned there carries
## on through instead of turning round at it; the nearest node on the network when there's none.
static func through_node(region: RealRegion, want: Vector2) -> int:
	var best := -1
	var best_key := Vector2(INF, INF)
	for n in region.node_count():
		var d := region.node_pos[n].distance_to(want)
		if d > 1200.0 or region.adjacent[n].size() < 3 or region.component_size[region.component[n]] < 200:
			continue
		# The road through it: the best class that has at least two of its roads here, open both ways.
		var through := RoutePlanner.ORDER.size()
		for k in RoutePlanner.ORDER.size():
			var both := 0
			for ei in region.adjacent[n]:
				if region.class_of(ei) == RoutePlanner.ORDER[k] and region.edge_oneway[ei] == 0:
					both += 1
			if both >= 2:
				through = k
				break
		var key := Vector2(through, d)
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = n
	return best if best >= 0 else region.nearest_connected(want.x, want.y, AdventureJourney.SNAP_M)


## The shortest tour of a bundled region (Shodoshima's first, then the Dales') whose road is at least `km` long, or the
## longest there is. Planned now (and kept), so it waits the first time.
static func sample(km: float) -> Dictionary:
	var best := {}
	for region_id in TOURS:
		for n in range(2, (TOURS[region_id] as Array).size() + 1):
			var plan := tour(region_id, n)
			var pack := pack_for(plan)
			if pack == null:
				continue
			if best.is_empty() or pack.max_km() > pack_for(best).max_km():
				best = plan
			if pack.max_km() >= km:
				return plan
	return best
