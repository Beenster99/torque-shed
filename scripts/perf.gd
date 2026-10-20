class_name Perf
extends RefCounted
## The in-game profiler's counters (F4 shows them: see PerfOverlay). The big per-frame systems
## time themselves with a pair of calls round their work:
##     var pt := Perf.t0()
##     ...
##     Perf.add("traffic", pt)
## Switched off (the usual), t0() hands back 0 and add() returns straight away, so the cost is
## two tiny calls. Switched on, each frame's microseconds per system are added up, and at the
## end of the frame (PerfOverlay calls end_frame) folded into the running averages and peaks
## the overlay shows, and into a recording when one is under way (see start_recording).

## Whether the systems are being timed (the overlay is up, or a recording runs).
static var on := false
## This frame's microseconds and calls so far, by system.
static var _frame := {}
static var _frame_calls := {}
## The last half second's: system -> [total usec, peak usec in a frame, calls, frames seen].
static var _window := {}
static var _window_frames := 0
## What the overlay shows: system -> [average ms a frame, peak ms in a frame, calls a frame].
static var shown := {}
## A recording: system -> [total usec, peak usec, calls], the frames in it, and per second.
static var recording := false
static var rec_sums := {}
static var rec_frames := 0
static var rec_seconds: Array = []   # one entry a second: {"t", "fps", "sys": {key: ms a frame}}
static var _sec_sums := {}
static var _sec_frames := 0
static var _sec_start := 0


## A timestamp to hand back to add(), or 0 while the profiler is off.
static func t0() -> int:
	return Time.get_ticks_usec() if on else 0


## Counts the time since `since` (from t0) against `key`.
static func add(key: String, since: int) -> void:
	if since == 0:
		return
	add_us(key, Time.get_ticks_usec() - since)


## Counts `us` microseconds measured some other way (a viewport's render time) against `key`.
static func add_us(key: String, us: int) -> void:
	if not on:
		return
	_frame[key] = int(_frame.get(key, 0)) + us
	_frame_calls[key] = int(_frame_calls.get(key, 0)) + 1


## Folds this frame's times into the window (and the recording) and starts the next frame.
## Every `window_s` seconds the shown averages are worked out afresh.
static func end_frame(window_s := 0.5) -> void:
	for key in _frame:
		var us: int = _frame[key]
		var w: Array = _window.get(key, [0, 0, 0])
		w[0] += us
		w[1] = maxi(w[1], us)
		w[2] += int(_frame_calls[key])
		_window[key] = w
		if recording:
			var r: Array = rec_sums.get(key, [0, 0, 0])
			r[0] += us
			r[1] = maxi(r[1], us)
			r[2] += int(_frame_calls[key])
			rec_sums[key] = r
			_sec_sums[key] = int(_sec_sums.get(key, 0)) + us
	_window_frames += 1
	if recording:
		rec_frames += 1
		_sec_frames += 1
		var now := Time.get_ticks_msec()
		if now - _sec_start >= 1000:
			var sys := {}
			for key in _sec_sums:
				sys[key] = snappedf(float(_sec_sums[key]) / 1000.0 / maxf(_sec_frames, 1), 0.001)
			rec_seconds.append({"t": rec_seconds.size() + 1, "fps": snappedf(_sec_frames * 1000.0 / float(now - _sec_start), 0.1), "sys": sys})
			_sec_sums = {}
			_sec_frames = 0
			_sec_start = now
	_frame.clear()
	_frame_calls.clear()
	if _window_frames >= maxi(1, int(Engine.get_frames_per_second() * window_s)):
		shown = {}
		for key in _window:
			var w: Array = _window[key]
			shown[key] = [float(w[0]) / 1000.0 / _window_frames, float(w[1]) / 1000.0, float(w[2]) / _window_frames]
		_window = {}
		_window_frames = 0


## The systems shown, slowest on average first: [[key, avg ms, peak ms, calls a frame], ...].
static func ranked() -> Array:
	var rows := []
	for key in shown:
		rows.append([key, shown[key][0], shown[key][1], shown[key][2]])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


static func start_recording() -> void:
	rec_sums = {}
	rec_frames = 0
	rec_seconds = []
	_sec_sums = {}
	_sec_frames = 0
	_sec_start = Time.get_ticks_msec()
	recording = true


static func stop_recording() -> void:
	recording = false


## The recording's systems: [[key, avg ms a frame, peak ms, calls a frame], ...], slowest first.
static func recorded() -> Array:
	var rows := []
	for key in rec_sums:
		var r: Array = rec_sums[key]
		rows.append([key, float(r[0]) / 1000.0 / maxf(rec_frames, 1), float(r[1]) / 1000.0, float(r[2]) / maxf(rec_frames, 1)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows
