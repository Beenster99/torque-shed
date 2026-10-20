class_name TripComputer
extends RefCounted
## The sat nav's trip computer (Simon: "add trip computer as part of satnav (to tell you
## information about the journey)"): how far you've ridden and how long for, your average and
## top speed, the petrol burnt, what it's averaging and how far what's left will take you, the
## height you're at now and how much you've climbed and come down. Out on an adventure it runs
## for the whole ride (AdventureTrip keeps it, through every stop and getting off); anywhere else
## it's a trip meter that starts again each time you get on (Satnav keeps it).
##
## It's fed a tick at a time (step) with what the bike is doing, and works the rest out from that,
## so it's the same sums on the bars, on the HUD and in the Adventure Diary's stats at the end.

## Slower than this (m/s) is stood still: the clock for the average speed doesn't run.
const MOVING := 1.0
## Height changes smaller than this (m) are the bumps in the road, not a climb or a descent: the
## climb is counted once the road's gone this far past the last turning point.
const CLIMB_STEP := 3.0
## A tank's worth less than this (litres) dropping in one tick is a refill or a spill, not riding.
const MAX_BURN := 0.25
## Less ridden than this (m), or less petrol burnt (litres), and there's no average to give yet.
const MIN_DIST := 200.0
const MIN_FUEL := 0.02

var distance := 0.0      # m ridden
var moving_time := 0.0   # s on the move (the average speed's clock)
var time := 0.0          # s since it started, stopped or not
var top := 0.0           # m/s, the fastest
var fuel_used := 0.0     # litres burnt
var climb := 0.0         # m gone up and down, the bumps left out
var descent := 0.0
var elevation := 0.0     # m, now
var surface := ""        # the ground under the wheels now ("tarmac", "gravel"...)
var _ref_h := NAN        # the height the climb's counted from (the last turning point)
var _last_fuel := NAN


## Starts again from nothing.
func reset() -> void:
	distance = 0.0
	moving_time = 0.0
	time = 0.0
	top = 0.0
	fuel_used = 0.0
	climb = 0.0
	descent = 0.0
	elevation = 0.0
	surface = ""
	_ref_h = NAN
	_last_fuel = NAN


## A tick of `delta` seconds at `speed` (m/s), at height `height` (m), with `fuel_left` litres in
## the tank, on `ground`. A tank that's gone up (filled) is counted from its new level.
func step(delta: float, speed: float, height: float, fuel_left: float, ground := "") -> void:
	var v := absf(speed)
	time += delta
	distance += v * delta
	if v > MOVING:
		moving_time += delta
	top = maxf(top, v)
	if not is_nan(_last_fuel):
		var burnt := _last_fuel - fuel_left
		if burnt > 0.0 and burnt < MAX_BURN:
			fuel_used += burnt
	_last_fuel = fuel_left
	elevation = height
	if is_nan(_ref_h):
		_ref_h = height
	elif height - _ref_h >= CLIMB_STEP:
		climb += height - _ref_h
		_ref_h = height
	elif _ref_h - height >= CLIMB_STEP:
		descent += _ref_h - height
		_ref_h = height
	if ground != "":
		surface = ground


## The average speed on the move (m/s), 0 till it's been going a little while.
func average() -> float:
	return distance / moving_time if moving_time > 1.0 and distance > 1.0 else 0.0


## What the petrol's averaging (km a litre), 0 till there's enough ridden to say.
func economy() -> float:
	return distance / 1000.0 / fuel_used if distance >= MIN_DIST and fuel_used >= MIN_FUEL else 0.0


## How far `fuel_left` litres goes (km) at the average so far, or at `book` km a litre (the bike's
## own figure) before there is one. -1 when neither knows.
func range_km(fuel_left: float, book := 0.0) -> float:
	var e := economy()
	if e <= 0.0:
		e = book
	return fuel_left * e if e > 0.0 else -1.0


## Seconds to ride `metres` more at the average so far (-1 till there is one).
func eta_seconds(metres: float) -> float:
	var v := average()
	return metres / v if v > 0.5 else -1.0


## The clock time you'd get there (hours) riding `metres` more, with the clock at `now` running
## `rate` hours a real second; -1 when there's no average yet.
func eta_clock(metres: float, now: float, rate: float) -> float:
	var s := eta_seconds(metres)
	return wrapf(now + s * rate, 0.0, 24.0) if s >= 0.0 else -1.0


## Everything it knows, to keep (the Adventure Diary's stats, a night's stop) and to put back.
func save() -> Dictionary:
	return {"distance": distance, "moving_time": moving_time, "time": time, "top": top, "fuel_used": fuel_used,
		"climb": climb, "descent": descent, "elevation": elevation}


func load_from(d: Dictionary) -> void:
	reset()
	distance = maxf(0.0, float(d.get("distance", 0.0)))
	moving_time = maxf(0.0, float(d.get("moving_time", 0.0)))
	time = maxf(0.0, float(d.get("time", 0.0)))
	top = maxf(0.0, float(d.get("top", 0.0)))
	fuel_used = maxf(0.0, float(d.get("fuel_used", 0.0)))
	climb = maxf(0.0, float(d.get("climb", 0.0)))
	descent = maxf(0.0, float(d.get("descent", 0.0)))
	elevation = float(d.get("elevation", 0.0))


# ---------------------------------------------------------------------------- words

## "1 h 05 min", "12 min", "45 s".
static func duration_text(seconds: float) -> String:
	if seconds < 0.0:
		return "--"
	var m := int(seconds / 60.0)
	if m >= 60:
		return "%d h %02d min" % [m / 60, m % 60]
	return "%d min" % m if m >= 1 else "%d s" % int(seconds)


## A distance in metres in the player's units: "12.4 km", "350 m", "7.7 mi".
static func distance_text(metres: float) -> String:
	if metres < 0.0:
		return "--"
	if not Units.imperial() and metres < 1000.0:
		return "%d m" % (roundi(metres / 10.0) * 10)
	return "%.1f %s" % [Units.distance_value(metres / 1000.0), Units.distance_unit()]


## A height: "412 m" or "1352 ft".
static func height_text(metres: float) -> String:
	return "%d ft" % roundi(metres * 3.28084) if Units.imperial() else "%d m" % roundi(metres)


## The lines of the final stats (the diary's page): [label, value].
func stats_lines(fuel_left := -1.0, book := 0.0) -> Array:
	var out := [["Ridden", distance_text(distance)], ["Riding time", duration_text(moving_time)],
		["Average", "%d %s" % [Units.speed_value(average()), Units.speed_unit()] if average() > 0.0 else "--"],
		["Top speed", "%d %s" % [Units.speed_value(top), Units.speed_unit()]],
		["Petrol", "%.1f L" % fuel_used], ["Averaging", Units.economy(economy()) if economy() > 0.0 else "-- " + Units.economy_unit()],
		["Climbed", height_text(climb)], ["Came down", height_text(descent)]]
	if fuel_left >= 0.0:
		var r := range_km(fuel_left, book)
		out.append(["Range left", distance_text(r * 1000.0) if r >= 0.0 else "--"])
	return out
