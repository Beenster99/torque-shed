class_name MapLink
extends RefCounted
## A map link pasted on the Route planner (its Find tab's Paste a map link): where it points, from the link alone.
## Google Maps (the "@lat,lon" of a map's view, the "!3d lat !4d lon" of a place, "?q=lat,lon"), Apple Maps ("ll=",
## "q="), OpenStreetMap ("#map=zoom/lat/lon", "mlat=..&mlon=.."), and plain "lat, lon" text. A short link (such as
## maps.app.goo.gl/...) is followed through its redirects, and each address on the way is looked at. Only the place is
## taken from a link, never the road: the game plans its own.

const _PATTERNS := [
	"!3d(-?\\d+(?:\\.\\d+)?)!4d(-?\\d+(?:\\.\\d+)?)",
	"@(-?\\d+(?:\\.\\d+)?),(-?\\d+(?:\\.\\d+)?)",
	"[?&](?:q|ll|sll|query|center|daddr|destination)=(-?\\d+(?:\\.\\d+)?)(?:,|%2C)\\s*(-?\\d+(?:\\.\\d+)?)",
	"#map=\\d+(?:\\.\\d+)?/(-?\\d+(?:\\.\\d+)?)/(-?\\d+(?:\\.\\d+)?)",
	"mlat=(-?\\d+(?:\\.\\d+)?)&mlon=(-?\\d+(?:\\.\\d+)?)",
	"(?:^|[^\\d.])(-?\\d{1,2}\\.\\d+)\\s*,\\s*(-?\\d{1,3}\\.\\d+)",
]


## (lat, lon) in `text` (a link or "lat, lon"), or Vector2.INF when there's none. Not `loose`, only a link's own ways
## of saying where count (for a page fetched, whose numbers may be anything).
static func parse(text: String, loose := true) -> Vector2:
	var t := text.strip_edges().uri_decode()
	for pattern in (_PATTERNS if loose else _PATTERNS.slice(0, _PATTERNS.size() - 1)):
		var m := RegEx.create_from_string(pattern).search(t)
		if m == null:
			continue
		var lat := float(m.get_string(1))
		var lon := float(m.get_string(2))
		if absf(lat) <= 85.0 and absf(lon) <= 180.0 and not (lat == 0.0 and lon == 0.0):
			return Vector2(lat, lon)
	return Vector2.INF


## Whether `text` is a link that needs following to see where it points (a short link with no place in it).
static func needs_following(text: String) -> bool:
	var t := text.strip_edges()
	return (t.begins_with("https://") or t.begins_with("http://")) and parse(t) == Vector2.INF and not t.contains(" ")


## Where `text` points: parse(), else (a short link) each address its redirects pass through. Vector2.INF when none
## of them names a place. Blocks while it follows a link: a worker's job.
static func resolve(text: String) -> Vector2:
	var at := parse(text)
	if at != Vector2.INF or not needs_following(text) or CellStore.offline:
		return at
	var res := CellStore.http(text.strip_edges())
	for url: String in res.get("urls", []):
		at = parse(url)
		if at != Vector2.INF:
			return at
	return parse((res.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8().left(200000), false)
