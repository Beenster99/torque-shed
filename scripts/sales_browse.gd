class_name SalesBrowse
extends RefCounted
## Buyers having a look round the showroom before they make an offer. An online buyer due to
## make one (see Sales.advance) comes in first: in through the front doors, round two or three
## of the bikes on show (stood looking it over, down on their haunches at the engine, sat on
## one), a word with the salesman if there is one, then the price card on the one they're after,
## and out again; their offer comes in as they leave.
##
## Shed state, kept small: each browser is a line in Shed.sales["browse"] ({id, bike, name, look,
## at (sales clock), end, stops}) written by the host and synced and saved with the rest of the
## sales. Where each one is and what they're doing at any moment is worked out the same on every
## game from that (pose()), so nothing moves over the network; SalesView draws them, as the
## same cheap figures as the staff (StaffFigure).

## The most browsing at once, and how long (game hours) a clock step can be and still send a
## buyer in for a look (a long jump, like a sleep or a test, has them offer straight away).
const MAX_BROWSE := 3
const BROWSE_STEP := 0.02
## Seconds (real) at each kind of stop: [least, most].
const STOP_SECS := {"look": Vector2(4.0, 8.0), "crouch": Vector2(4.0, 6.5), "sit": Vector2(5.0, 8.0), "card": Vector2(3.0, 5.0),
	"talk": Vector2(5.0, 8.0)}
## How far round a plinth a walk keeps (m past its edge).
const PLINTH_CLEAR := 0.45
## Where the salesman waits, and so where a buyer stands for a word with him.
const SALES_SPOT := Vector3(25.6, 0.0, 65.6)


static func browsers() -> Dictionary:
	var s := Sales._st()
	if not (s.get("browse") is Dictionary):
		s["browse"] = {}
	return s["browse"]


## Host: a buyer `who` ({name, look}) comes in for a look round before offering on `bike_id`.
## Returns their id.
static func spawn(bike_id: int, who: Dictionary, rng: RandomNumberGenerator) -> int:
	var s := Sales._st()
	var id := int(s["next"])
	s["next"] = id + 1
	var stops := plan(bike_id, rng)
	var secs := duration(stops)
	browsers()[id] = {"id": id, "bike": bike_id, "name": str(who.get("name", "Buyer")), "look": who.get("look", {}), "at": Sales.clock(),
		"end": Sales.clock() + secs * Contracts.hours_rate(), "stops": stops}
	Shed._mark_dirty()
	return id


## The stops on a look round ending at `bike_id`'s stand: [{p, yaw, act, secs}], the first and
## last just inside the doors. Other bikes on show first (one or two), then a word with the
## salesman if one's in, then theirs: looked over, maybe down at the engine or sat on, and
## last its price card.
static func plan(bike_id: int, rng: RandomNumberGenerator) -> Array:
	var stops := [{"p": SalesView.door_in(), "yaw": PI, "act": "", "secs": 0.0}]
	var target := Sales.stand_of(bike_id)
	var others := []
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		if i != target and Sales.bike_on_stand(i) != 0:
			others.append(i)
	others.shuffle()
	for i in others.slice(0, rng.randi_range(1, 2)):
		_at_bike(stops, int(i), rng, false)
	if _salesman_in():
		stops.append(_stop(SALES_SPOT + Vector3(-1.1, 0.0, 0.0), -PI * 0.5, "talk", rng))
	if target >= 0:
		_at_bike(stops, target, rng, true)
	stops.append({"p": SalesView.door_in(), "yaw": 0.0, "act": "", "secs": 0.0})
	stops.append({"p": SalesView.door_out() + Vector3(0.0, 0.0, 1.5), "yaw": 0.0, "act": "", "secs": 0.0})
	return stops


## The stops at one bike: looked over, then (by chance, and always something more on the one
## they're after) down at the engine or sat on it; the price card last on theirs.
static func _at_bike(stops: Array, stand: int, rng: RandomNumberGenerator, theirs: bool) -> void:
	var xf: Transform3D = SalesOffice.SHOWROOM_SPOTS[stand]
	var v := SalesView.viewing_xf(stand)
	stops.append(_stop(v.origin, v.basis.get_euler().y, "look", rng))
	var roll := rng.randf()
	if roll < (0.55 if theirs else 0.35):
		var side := xf.origin + xf.basis.x * (0.62 if rng.randf() < 0.5 else -0.62)
		side.y = 0.0
		stops.append(_stop(side, _yaw_to(side, xf.origin), "crouch", rng))
	elif roll < (0.9 if theirs else 0.5):
		var side2 := xf.origin + xf.basis.x * 0.75
		side2.y = 0.0
		stops.append({"p": side2, "yaw": _yaw_to(side2, xf.origin), "act": "", "secs": 0.0})
		# Sat astride it, facing the way it points, just back of the middle on the seat.
		var seat := xf.origin + xf.basis.z * 0.2
		stops.append(_stop(seat, xf.basis.get_euler().y, "sit", rng))
		stops.append({"p": side2, "yaw": _yaw_to(side2, xf.origin), "act": "", "secs": 0.0})
	if theirs:
		var card := card_spot(stand)
		stops.append(_stop(card.origin, card.basis.get_euler().y, "card", rng))


static func _stop(p: Vector3, yaw: float, act: String, rng: RandomNumberGenerator) -> Dictionary:
	var r: Vector2 = STOP_SECS.get(act, Vector2(3.0, 5.0))
	return {"p": p, "yaw": yaw, "act": act, "secs": snappedf(rng.randf_range(r.x, r.y), 0.1)}


## Where to stand to read stand `i`'s price card (at the front of its plinth), facing it.
static func card_spot(i: int) -> Transform3D:
	var xf: Transform3D = SalesOffice.SHOWROOM_SPOTS[i]
	var out := xf.basis * Vector3(0.0, 0.0, -1.0)
	out.y = 0.0
	var front: Vector3 = xf.origin + out.normalized() * (SalesOffice.PLINTH_RADIUS + 0.35)
	var at := front + out.normalized() * 0.55
	at.y = 0.0
	return Transform3D(Basis(Vector3.UP, _yaw_to(at, front)), at)


## The yaw that faces from `from` to `to` (-Z forward, like the figures).
static func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


static func _salesman_in() -> bool:
	for id in Staff.workers():
		var w: Dictionary = Staff.workers()[id]
		if str(w["role"]) == "sales" and not w.get("sick", false):
			return true
	return false


## The way between two stops: straight, or bent round any plinth in the way (getting on or off
## a bike, the last bit's over the plinth's edge).
static func way(a: Vector3, b: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array([a])
	var at := a
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		var c: Vector3 = SalesOffice.SHOWROOM_SPOTS[i].origin
		c.y = 0.0
		var r := SalesOffice.PLINTH_RADIUS + PLINTH_CLEAR
		# Not round the one they're stepping onto or off.
		if Vector2(b.x - c.x, b.z - c.z).length() < r or Vector2(at.x - c.x, at.z - c.z).length() < r:
			continue
		var seg := b - at
		var t := clampf((c - at).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var near := at + seg * t
		var off := Vector3(near.x - c.x, 0.0, near.z - c.z)
		if off.length() >= r or t <= 0.0 or t >= 1.0:
			continue
		if off.length() < 0.01:
			off = Vector3(-seg.z, 0.0, seg.x)
		var bend := c + off.normalized() * (r + 0.05)
		pts.append(bend)
		at = bend
	pts.append(b)
	return pts


## Seconds the whole look round takes.
static func duration(stops: Array) -> float:
	var t := 0.0
	for i in stops.size():
		if i > 0:
			t += _length(way(stops[i - 1]["p"], stops[i]["p"])) / Contracts.WALK_SPEED
		t += float(stops[i]["secs"])
	return t


static func _length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for k in range(1, pts.size()):
		l += pts[k].distance_to(pts[k - 1])
	return l


## Where browser `b` is `t` seconds into their look round and what they're doing:
## {pos, yaw, walking, act, gone}.
static func pose(b: Dictionary, t: float) -> Dictionary:
	var stops: Array = b.get("stops", [])
	if stops.is_empty():
		return {"pos": Vector3.ZERO, "yaw": 0.0, "walking": false, "act": "", "gone": true}
	var clock := 0.0
	for i in stops.size():
		var s: Dictionary = stops[i]
		if i > 0:
			var pts := way(stops[i - 1]["p"], s["p"])
			var walk := _length(pts) / Contracts.WALK_SPEED
			if t < clock + walk:
				var d := (t - clock) * Contracts.WALK_SPEED
				return {"pos": _along(pts, d), "yaw": _heading(pts, d), "walking": true, "act": "", "gone": false}
			clock += walk
		if t < clock + float(s["secs"]):
			return {"pos": s["p"], "yaw": float(s["yaw"]), "walking": false, "act": str(s["act"]), "gone": false}
		clock += float(s["secs"])
	var last: Dictionary = stops[-1]
	return {"pos": last["p"], "yaw": float(last["yaw"]), "walking": false, "act": "", "gone": true}


static func _along(pts: PackedVector3Array, d: float) -> Vector3:
	for k in range(1, pts.size()):
		var seg := pts[k].distance_to(pts[k - 1])
		if d <= seg:
			return pts[k - 1].lerp(pts[k], d / maxf(seg, 0.0001))
		d -= seg
	return pts[-1]


static func _heading(pts: PackedVector3Array, d: float) -> float:
	for k in range(1, pts.size()):
		var seg := pts[k].distance_to(pts[k - 1])
		if d <= seg or k == pts.size() - 1:
			return _yaw_to(pts[k - 1], pts[k])
		d -= seg
	return 0.0


## What a browser's doing, for the look panel and the Sales page: "Sat on the Old Faithful".
static func doing(b: Dictionary, t: float) -> String:
	var p := pose(b, t)
	var stand := Sales.stand_of(int(b.get("bike", 0)))
	var near := _nearest_stand(p["pos"])
	var bike := Sales.bike_on_stand(near)
	var nm := str(Shed.bikes.get(bike, {}).get("name", "a bike"))
	match str(p["act"]):
		"look":
			return "Looking over the %s" % nm
		"crouch":
			return "Down at the %s's engine" % nm
		"sit":
			return "Sat on the %s" % nm
		"card":
			return "Reading the price on the %s" % str(Shed.bikes.get(Sales.bike_on_stand(stand), {}).get("name", "bike"))
		"talk":
			return "Talking to the salesman"
	return "Having a look round"


static func _nearest_stand(p: Vector3) -> int:
	var best := 0
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		if p.distance_to(SalesOffice.SHOWROOM_SPOTS[i].origin) < p.distance_to(SalesOffice.SHOWROOM_SPOTS[best].origin):
			best = i
	return best


## Host, as the sales clock moves on: those done looking round make their offer (on a bike
## still for sale) and go. True when anything changed.
static func advance(now: float) -> bool:
	var changed := false
	for id in browsers().keys():
		var b: Dictionary = browsers()[id]
		var bike := int(b.get("bike", 0))
		if now < float(b.get("end", 0.0)) and Sales.active(bike):
			continue
		browsers().erase(id)
		changed = true
		if Sales.active(bike) and Sales.offers().size() < Sales.MAX_OFFERS:
			Sales.make_offer(bike, {"name": b["name"], "look": b["look"]})
	return changed


## Browsers looking round with an eye on `bike_id`.
static func on(bike_id: int) -> int:
	return browsers().values().filter(func(b): return int(b.get("bike", 0)) == bike_id).size()
