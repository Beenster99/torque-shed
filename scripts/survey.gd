class_name Survey
extends RefCounted
## The Route planner TV's Survey button: the cells in view nobody has baked yet, sent by the host to the survey worker
## (a Cloudflare Worker, Beenster99/torque-shed-world's worker/), which sets the world's bake workflow on them. They come
## into the world's index ten minutes or so later; until then the TVs say the roads are being surveyed and look at the
## index now and then (WorldView), and when the cells are in it they fetch and draw their roads.
##
## The crew's survey is in the TV's shared view: Shed.route_tv["survey"] = {cells: ["ROW_COL", ...] being baked, since
## (unix seconds), said (what the surveyors said)}. Action (Shed.request, from any player): adventure_survey {cells}.

const URL := "https://torque-shed-survey.simonbennett3.workers.dev/survey"
const MAX_CELLS := 16
## About how long a survey takes (s), for the map's bar: the bake, and the index taking it in.
const TAKES := 600.0
## How long a survey shows as going (s): longer than a bake takes, so a slow one isn't forgotten.
const LASTS := 1800.0

## Where the survey worker is (the tests run their own), and how often (s) a TV looks at the index while a survey is on.
static var url := URL
static var look_every := 60.0

static var _task := -1
static var _answer := {}
static var _lock := Mutex.new()


## `v` as a list of cells to survey ("ROW_COL", at most MAX_CELLS, each once), [] when it isn't one.
static func cells_of(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if not v is Array or (v as Array).is_empty() or (v as Array).size() > MAX_CELLS:
		return out
	for c in v:
		var rc := str(c).split("_")
		if rc.size() != 2 or not rc[0].is_valid_int() or not rc[1].is_valid_int():
			return [] as Array[String]
		var row := int(rc[0])
		var col := int(rc[1])
		if row < 0 or row >= int(180.0 / RealRegion.CELL_DEG) or col < 0 or col >= int(360.0 / RealRegion.CELL_DEG):
			return [] as Array[String]
		var key := "%d_%d" % [row, col]
		if not out.has(key):
			out.append(key)
	return out


## The crew's survey made safe (see Shed.route_tv), or {}.
static func sanitize(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var cells: Array[String] = cells_of(v.get("cells", []))
	return {"cells": cells, "since": float(v.get("since", 0.0)), "said": str(v.get("said", "")).left(120)}


## The cells the crew's survey is baking now (none once it is LASTS old).
static func going() -> Array[String]:
	var s: Dictionary = Shed.route_tv.get("survey", {})
	if s.is_empty() or Time.get_unix_time_from_system() - float(s.get("since", 0.0)) > LASTS:
		return [] as Array[String]
	return cells_of(s.get("cells", []))


## Host: asks the survey worker to bake `cells` (on a worker thread; poll() takes in the answer). One at a time.
static func start(cells: Array[String]) -> void:
	_lock.lock()
	var busy := _task >= 0
	_lock.unlock()
	if busy:
		return
	_tell_crew({"cells": [], "since": Time.get_unix_time_from_system(), "said": "Asking the surveyors..."})
	_lock.lock()
	_answer = {}
	_task = WorkerThreadPool.add_task(func():
		var got := ask(cells)
		_lock.lock()
		_answer = got
		_lock.unlock())
	_lock.unlock()


## Host: takes in the survey worker's answer once it has come (call it every frame or so).
static func poll() -> void:
	_lock.lock()
	var task := _task
	_lock.unlock()
	if task < 0 or not WorkerThreadPool.is_task_completed(task):
		return
	WorkerThreadPool.wait_for_task_completion(task)
	_lock.lock()
	_task = -1
	var got := _answer
	_lock.unlock()
	_tell_crew({"cells": got.get("cells", []), "since": Time.get_unix_time_from_system(), "said": str(got.get("message", ""))})


## Asks the survey worker to bake `cells`: {status ("baking", "mapped", "busy" or "error"), cells, message}. Blocks.
static func ask(cells: Array[String]) -> Dictionary:
	if CellStore.offline:
		return {"status": "error", "cells": [], "message": "This game is offline: the surveyors can't be asked."}
	var res := CellStore.http(url, HTTPClient.METHOD_POST, JSON.stringify({"cells": cells}))
	var v = JSON.parse_string((res["body"] as PackedByteArray).get_string_from_utf8()) if int(res["code"]) != 0 else null
	if not v is Dictionary:
		return {"status": "error", "cells": [], "message": "Couldn't reach the surveyors: are you online?"}
	var out: Dictionary = v
	out["cells"] = cells_of(out.get("cells", [])) if str(out.get("status", "")) == "baking" else []
	return out


static func _tell_crew(survey: Dictionary) -> void:
	var view: Dictionary = Shed.route_tv.duplicate()
	view["survey"] = survey
	Shed.route_tv = AdventureJourney.sanitize_view(view)
	Shed._mark_dirty()
	Shed.changed.emit()
