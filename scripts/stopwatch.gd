class_name Stopwatch
extends RefCounted
## The stopwatch tool, for timing laps, jumps and whatever events the crew make up. It keeps
## running in your pocket while you ride: P (or D-pad left) starts and stops it from the bike.

var running := false
var laps: Array[float] = []     # lap times, newest last
var max_laps := 5               # how many it keeps: more on an upgraded stopwatch
var _start_ms := 0
var _stopped_at := 0.0
var _lap_from := 0.0


func elapsed() -> float:
	if running:
		return (Time.get_ticks_msec() - _start_ms) / 1000.0
	return _stopped_at


## Start from zero, or stop and hold the time.
func start_stop() -> void:
	if running:
		_stopped_at = elapsed()
		running = false
	else:
		laps.clear()
		_lap_from = 0.0
		_start_ms = Time.get_ticks_msec()
		running = true


## While running, mark a lap; when stopped, clear it back to zero.
func lap_or_reset() -> void:
	if running:
		var now := elapsed()
		laps.append(now - _lap_from)
		_lap_from = now
		while laps.size() > max_laps:
			laps.pop_front()
	else:
		_stopped_at = 0.0
		laps.clear()


## Whether there's anything worth showing on the HUD.
func showing() -> bool:
	return running or _stopped_at > 0.0 or not laps.is_empty()


## "1:02.37", or "12.37" under a minute.
static func format(t: float) -> String:
	var mins := int(t / 60.0)
	var secs := t - mins * 60.0
	if mins > 0:
		return "%d:%05.2f" % [mins, secs]
	return "%.2f" % secs
