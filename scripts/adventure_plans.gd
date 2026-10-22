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


## `v` as a plan this game can plan, or {} when it is not one (no such region, too few or too many pins, a pin off the map).
static func clean(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var region := RealRegion.get_region(str(v.get("region", "")))
	if region == null:
		return {}
	var pins: Array = []
	var raw = v.get("pins")
	if not raw is Array or (raw as Array).size() < 2 or (raw as Array).size() > MAX_PINS:
		return {}
	var box := region.bounds.grow(MARGIN)
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
	return {"region": region.id, "region_hash": str(v.get("region_hash", region.hash)), "pins": pins, "names": names, "mode": mode}


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
	var region := RealRegion.get_region(str(plan["region"]))
	if region == null:
		return {"ok": false, "error": "This game doesn't have that part of the world.", "pack": null}
	if str(plan.get("region_hash", region.hash)) != region.hash:
		return {"ok": false, "error": "Your copy of the %s map isn't the host's: update the game to join." % region.title, "pack": null}
	var res := RoutePlanner.plan(region, _request(plan))
	if bool(res["ok"]):
		RealPack.register(res["pack"])
	return res


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
		return result(plan, true)
	if wait:
		var res := _run(plan)
		_lock.lock()
		_done[k] = res
		_lock.unlock()
		return res
	_lock.lock()
	_tasks[k] = WorkerThreadPool.add_task(func():
		var res := _run(plan)
		_lock.lock()
		_done[k] = res
		_lock.unlock())
	_lock.unlock()
	return {}


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
## Shodoshima, and across the Dales and back.
const TOURS := {
	"shodoshima": [[-5881, 1526], [-306, 1293], [4560, 2074], [7721, -3202], [1792, -4787], [-174, -3502], [-5951, 1062]],
	"dales": [[-10180, 3993], [-8223, -7330], [7187, -4599], [15264, 4188], [12595, 7398], [2813, 5382], [-11640, 3115]],
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
		var node := region.nearest_connected(want.x, want.y, AdventureJourney.SNAP_M)
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
