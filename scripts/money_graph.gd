class_name MoneyGraph
extends RefCounted
## Money over in-game time, for the graphs of your own cash and the business's account (the Esc
## menu's Money tab and the money TV channels), by the minute, hour, day, week, month or year.
##
## A series is {range key: [[bucket, balance], ...]}, oldest first: for each range, the balance
## at the end of each bucket (bucket = game hours / the range's unit, rounded down) where it
## changed. Buckets with no entry kept the balance of the one before, so a series only grows
## when money moves. The business's lives in Shed.bank["series"] (saved with the shed), your own
## in your Progress profile's "series" (kept with your character).

## Each range: its unit in game hours, how many buckets the graph shows (now included), its
## name for the buttons and charts, and the short suffix for the axis ("-5m").
const RANGES := {
	"minute": {"unit": 1.0 / 60.0, "count": 60, "name": "Minutes", "span": "last hour", "suffix": "m"},
	"hour": {"unit": 1.0, "count": 24, "name": "Hours", "span": "last 24 hours", "suffix": "h"},
	"day": {"unit": 24.0, "count": 7, "name": "Days", "span": "last week", "suffix": "d"},
	"week": {"unit": 24.0 * 7.0, "count": 12, "name": "Weeks", "span": "last 12 weeks", "suffix": "w"},
	"month": {"unit": 24.0 * 30.0, "count": 12, "name": "Months", "span": "last 12 months", "suffix": "mo"},
	"year": {"unit": 24.0 * 365.0, "count": 5, "name": "Years", "span": "last 5 years", "suffix": "y"},
}
const ORDER: Array[String] = ["minute", "hour", "day", "week", "month", "year"]
const DEFAULT_RANGE := "day"


## The shed's in-game clock in hours since it opened: whole days (the bank's day count, which
## moves on at midnight) plus the time of day.
static func now_hours() -> float:
	var bank = Shed.get("bank")
	var day := int(bank.get("day", 0)) if bank is Dictionary else 0
	return day * 24.0 + Daylight.time_of_day()


static func bucket_of(range_key: String, t: float) -> int:
	return int(floor(t / float(RANGES[range_key]["unit"]) + 1e-6))


## Notes `balance` at game time `t` (hours) in `series`, for every range. True when anything
## changed (the balance moved since the last note). Time never runs backwards in a series: a
## note from just before a midnight the bank hasn't counted yet goes in the newest bucket.
static func record(series: Dictionary, t: float, balance: int) -> bool:
	var changed := false
	for key in ORDER:
		if not (series.get(key) is Array):
			series[key] = []
		var rows: Array = series[key]
		var b := bucket_of(key, t)
		if rows.is_empty():
			# The first note is the balance it opened with, put in the bucket before: money
			# moving later in this bucket then shows as a step up to now, not a flat line.
			rows.append([b - 1, balance])
			changed = true
			continue
		b = maxi(b, int(rows[-1][0]))
		if int(rows[-1][1]) == balance:
			continue
		if int(rows[-1][0]) == b:
			rows[-1][1] = balance
			changed = true
			continue
		rows.append([b, balance])
		changed = true
		# Keep the window, plus the one before it for the balance it opened with.
		var first := b - int(RANGES[key]["count"])
		while rows.size() > 1 and int(rows[1][0]) <= first:
			rows.pop_front()
	return changed


## The balance at the end of each of the range's buckets, oldest first; the last is now
## (`now_balance`). Before the series begins the graph is flat at its first balance.
static func points(series: Dictionary, range_key: String, t: float, now_balance: int) -> Array:
	var key := range_key if RANGES.has(range_key) else DEFAULT_RANGE
	var count := int(RANGES[key]["count"])
	var rows: Array = series.get(key, []) if series.get(key) is Array else []
	var now_b := bucket_of(key, t)
	if not rows.is_empty():
		now_b = maxi(now_b, int(rows[-1][0]))
	var out := []
	var i := 0
	var bal := int(rows[0][1]) if not rows.is_empty() else now_balance
	for n in range(count - 1, 0, -1):
		var b := now_b - n
		while i < rows.size() and int(rows[i][0]) <= b:
			bal = int(rows[i][1])
			i += 1
		out.append(bal)
	out.append(now_balance)
	return out


## The axis label under point `i` of `count`: "now", "-5m", "-3d".
static func tick_text(range_key: String, i: int, count: int) -> String:
	if i == count - 1:
		return "now"
	return "-%d%s" % [count - 1 - i, str(RANGES.get(range_key, RANGES[DEFAULT_RANGE])["suffix"])]


## "last week" for a chart's title.
static func span_text(range_key: String) -> String:
	return str(RANGES.get(range_key, RANGES[DEFAULT_RANGE])["span"])


## A saved or synced series with every range present and sane (older saves have none).
static func sanitize(s) -> Dictionary:
	var out := {}
	for key in ORDER:
		out[key] = []
		var rows = s.get(key, []) if s is Dictionary else []
		if not (rows is Array):
			continue
		var last: int = -(1 << 40)
		for r in rows.slice(-(int(RANGES[key]["count"]) + 2)):
			if (r is Array) and r.size() >= 2 and int(r[0]) > last:
				out[key].append([int(r[0]), int(r[1])])
				last = int(r[0])
	return out


## A money chart for a menu: TvChannels' chart drawn to fit the control.
class View extends Control:
	var values: Array = []
	var title := ""
	var range_key := DEFAULT_RANGE

	func _init() -> void:
		custom_minimum_size = Vector2(420, 260)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func show_values(v: Array, label: String, key: String) -> void:
		values = v
		title = label
		range_key = key
		queue_redraw()

	func _draw() -> void:
		TvChannels.chart(self, get_theme_default_font(), Rect2(Vector2.ZERO, size), values, title, range_key)
