class_name JobPool
extends RefCounted
## Worker threads of the game's own for the ride's streaming work (the land, the road blocks and the far ridges round
## the riders). Godot's WorkerThreadPool ran tasks added one at a time on a single one of its workers, so the land round
## a rider was laid out a block at a time behind everything else: here every worker takes the nearest job waiting.

## How many workers: two cores are left, one for the game itself and one for the ride's chunks of road, or the frames
## stutter on a four-core machine.
static var size := clampi(OS.get_processor_count() - 2, 1, 6)

static var _lock := Mutex.new()
static var _wake := Semaphore.new()
static var _threads: Array[Thread] = []
static var _queue: Array = []     # [{id, job, rank}], waiting
static var _running := {}         # id -> true, being run
static var _next := 1
static var _quit := false


## Queues `job` and returns its id. Lower `rank` (metres from the rider, say) is taken first.
static func add(job: Callable, rank := 0.0) -> int:
	_lock.lock()
	if _threads.is_empty():
		_quit = false
		for i in size:
			var t := Thread.new()
			t.start(_worker, Thread.PRIORITY_LOW)
			_threads.append(t)
	var id := _next
	_next += 1
	var at := _queue.size()
	for i in _queue.size():
		if float(_queue[i]["rank"]) > rank:
			at = i
			break
	_queue.insert(at, {"id": id, "job": job, "rank": rank})
	_lock.unlock()
	_wake.post()
	return id


## Whether job `id` has been run (or was never queued).
static func done(id: int) -> bool:
	_lock.lock()
	var out := not _running.has(id) and _queue.all(func(q): return int(q["id"]) != id)
	_lock.unlock()
	return out


## Waits for job `id`: one not started yet is run here and now.
static func wait(id: int) -> void:
	_lock.lock()
	for i in _queue.size():
		if int(_queue[i]["id"]) == id:
			var job: Callable = _queue[i]["job"]
			_queue.remove_at(i)
			_lock.unlock()
			job.call()
			return
	_lock.unlock()
	while not done(id):
		OS.delay_usec(200)


## Lets job `id` go: one not started yet never runs; one running is waited for.
static func drop(id: int) -> void:
	_lock.lock()
	for i in _queue.size():
		if int(_queue[i]["id"]) == id:
			_queue.remove_at(i)
			break
	_lock.unlock()
	while not done(id):
		OS.delay_usec(200)


## Stops the workers (as the game quits), once the jobs they're running are done; those still waiting are dropped.
static func stop() -> void:
	_lock.lock()
	_quit = true
	_queue.clear()
	var threads := _threads.duplicate()
	_threads.clear()
	_lock.unlock()
	for t in threads:
		_wake.post()
	for t: Thread in threads:
		t.wait_to_finish()


static func _worker() -> void:
	while true:
		_wake.wait()
		_lock.lock()
		if _quit:
			_lock.unlock()
			return
		if _queue.is_empty():
			_lock.unlock()
			continue
		var item: Dictionary = _queue.pop_front()
		_running[item["id"]] = true
		_lock.unlock()
		(item["job"] as Callable).call()
		_lock.lock()
		_running.erase(item["id"])
		_lock.unlock()
