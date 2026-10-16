class_name Contracts
extends RefCounted
## Contracts: customers walk up to the sales office reception (a bell rings as they get there)
## with a job for the garage. Talk to one (F) to see the offer, then take it on or turn it down.
## Four kinds, unlocked by the garage's reputation:
##   maint    easy: a quick job, a service or the works (oil, chain, pads, filters, plugs, brake
##            fluid, a wash, new tyres, a chain and sprockets, a brake disc, a fork service)
##   mot      the yearly test: inspect it (see MotTest), fix what fails, re-test, hand it back;
##            anything from a couple of faults to a bike off the road for years, sometimes with
##            a job or two to do while it's in
##   mod      modifications to a budget: 2-5 goals (speed, power, weight, a style, luggage,
##            brakes, pipes, paint)
##   bespoke  a ground-up build on a bare frame, to an exclusive customer's targets (a style,
##            and some of: performance, weight, signature parts, paint, a finish standard)
## Each job's pay, parts budget and deadline are worked out from what it asks for.
## Customers ride their own bike in along the road, park it in the sales office car park and
## walk in to reception. Taking the job on leaves their bike (and its keys) in the car park for
## the crew to ride or wheel into a bay; a bespoke build's bare frame goes straight onto a bay.
## When it's done, ride or wheel it out to the customer car park in front of the sales office and
## hand it back from the Contracts panel: the goals are checked, the garage and the crew who
## worked on it are paid, the reputation moves, and the customer walks out of the sales office
## to it, gets on and rides it away.
##
## All of it is host-authoritative shed state in Shed.contracts (saved with the shed). Players
## ask for changes with Shed.request({"a": "contract_..."}), which Shed hands to check()/apply().
## Everything here is static, working on the Shed autoload.

const KINDS: Array[String] = ["maint", "mot", "mod", "bespoke"]
const KIND_NAMES := {"maint": "Maintenance", "mot": "MOT", "mod": "Modifications", "bespoke": "Bespoke build"}
## Reputation the garage needs before customers bring each kind of job.
const UNLOCK := {"maint": 0, "mot": 2, "mod": 5, "bespoke": 10}
## How the kind's job counts in the player's XP (see Progress.XP).
const XP_KEYS := {"maint": "contract_maint", "mot": "contract_mot", "mod": "contract_mod", "bespoke": "contract_bespoke"}
## Reputation earned by a job done to the letter.
const REP_GAIN := {"maint": 1, "mot": 2, "mod": 3, "bespoke": 5}
const FIRST_CUSTOMER := 0.4          # game hours into a new shed before the first customer
const SPAWN_HOURS := Vector2(2.0, 5.0)
const MAX_WAITING := 2               # customers at reception at once
const PATIENCE_HOURS := 3.0          # how long one waits before giving up
const MAX_ACTIVE := 4                # jobs in the shed at once (one per bay)
const MAX_DONE := 12
const WORKER_SHARE := 0.5            # of the labour and tip, split among the crew who did the work
const WALK_SPEED := 1.4              # m/s, for the customer figures
const RIDE_SPEED := 9.0              # m/s, a customer riding in or away along the yard
## The car park's marked bays (see SalesOffice._build_paving): how many, how far apart, and
## where the first one's middle is from the forecourt's corner. Bikes park nose-in to the office.
const PARK_SLOTS := 6
const PARK_STEP := 2.6
const PARK_FROM := Vector2(3.3, 11.6)
## Where the road runs past the yard, by x: customers ride along it between these.
const ROAD_FAR_X := 72.0
const ROAD_TURN_X := 24.0
## The loop's line past the west of the yard (see _west_road), worked out once.
static var _west := PackedVector2Array()
## How long a finished job's ride away is kept (game hours), for players arriving to see it.
const LEAVING_HOURS := 2.0
const MAX_LEAVING := 6
const DAY := 24.0
## Actions that are not work on a bike, so they don't count someone as having worked on it.
const NOT_WORK: Array[String] = ["mount", "grab_bike", "release_bike", "ride", "status", "ping", "tv_channel", "tune"]
## Maintenance tasks: what the customer asked for.
const TASKS := {"oil": "Oil change (fresh oil, topped up)", "chain": "Chain lubed and tensioned",
	"pads": "New brake pads front and rear", "filters": "Air and oil filters renewed", "plugs": "New spark plugs",
	"brake_fluid": "Brake fluid renewed and topped up", "wash": "A good wash", "front_tyre": "New front tyre",
	"rear_tyre": "New rear tyre", "chain_kit": "New chain and sprockets", "discs": "New front brake disc",
	"fork": "Front fork serviced (seals and oil)"}
## What each task pays in labour: a service's fee is these added up, give or take.
const TASK_PAY := {"oil": 45, "chain": 35, "pads": 50, "filters": 40, "plugs": 35, "brake_fluid": 50, "wash": 25,
	"front_tyre": 45, "rear_tyre": 50, "chain_kit": 60, "discs": 55, "fork": 80}
## The parts a task renews (slots): what they cost goes into the job's parts budget, and a bike
## without one can't have that task.
const TASK_PARTS := {"pads": ["front_pads", "rear_pads"], "filters": ["air_filter", "oil_filter"], "plugs": ["spark_plugs"],
	"front_tyre": ["front_tyre"], "rear_tyre": ["rear_tyre"], "chain_kit": ["chain", "final_drive"], "discs": ["front_disc"],
	"fork": ["fork"]}
## The sizes of service customers ask for: how many tasks, how long they give you, what they say.
const SERVICES := [
	{"n": Vector2i(1, 2), "days": Vector2i(2, 2), "blurb": "Just a couple of things need doing, nothing else. Quick as you can."},
	{"n": Vector2i(3, 4), "days": Vector2i(2, 3), "blurb": "It's due a service. Nothing fancy, just look after it."},
	{"n": Vector2i(5, 6), "days": Vector2i(3, 4), "blurb": "Give it the works: a full service and whatever's worn out."},
]
## Tasks an MOT customer sometimes adds while the bike's in.
const MOT_EXTRAS: Array[String] = ["oil", "chain", "wash", "plugs", "filters", "brake_fluid", "pads"]
## What each kind of modification goal pays in labour.
const MOD_PAY := {"top_kmh": 220, "hp": 200, "mass": 240, "style": 320, "fit": 120, "pipes": 140, "paint": 110, "part": 130}
const STYLES := {"cafe": "Cafe racer", "scrambler": "Scrambler", "tourer": "Tourer", "sport": "Sports bike", "bobber": "Bobber",
	"chopper": "Chopper", "cruiser": "Cruiser", "adventure": "Adventure bike", "mx": "MX bike", "supermoto": "Supermoto"}
## For the styles without hand-picked marks: the four slots whose parts have to suit the style
## (by their tags, see PartsDB.styles_of).
const STYLE_KEYS := {"chopper": ["frame", "fork", "handlebars", "tail"], "cruiser": ["frame", "exhaust", "handlebars", "saddle"],
	"adventure": ["frame", "tank", "fairing", "panniers"], "mx": ["frame", "fork", "tank", "number_boards"],
	"supermoto": ["front_wheel", "rear_wheel", "front_mudguard", "handlebars"]}
## Exhausts that count as proper pipes.
const PIPES: Array[String] = ["full_system", "titanium_race", "straight_pipe"]
const FIT_SLOTS := {"panniers": "Panniers", "top_box": "A top box", "fairing": "A fairing", "fog_lights": "Fog lights",
	"front_mudguard": "A front mudguard"}
## A rough price by kind, for setting budgets when the parts computer has no price yet.
const EST_COST := {"frame": 900, "fork": 450, "shock": 300, "wheel": 280, "tyre": 110, "disc": 90, "caliper": 120,
	"pads": 35, "master": 70, "tank": 260, "saddle": 120, "handlebars": 80, "dashboard": 150, "engine": 1600,
	"head": 400, "fuel": 260, "air_filter": 40, "oil_filter": 15, "spark_plugs": 20, "cooling": 180, "gearbox": 500,
	"exhaust": 380, "final_drive": 90, "chain": 70, "side_stand": 40, "centre_stand": 70, "headlight": 90,
	"horn": 25, "ecu": 350, "panniers": 220, "top_box": 120, "fog_lights": 110, "tail": 140, "fairing": 420, "mirrors": 45,
	"front_mudguard": 90, "indicators": 60, "side_panels": 90, "rearsets": 160, "guards": 180, "number_boards": 70}
const FIRST_NAMES := ["Dave", "Sue", "Raj", "Kim", "Gary", "Priya", "Tom", "Jo", "Mick", "Aisha", "Steve", "Lena",
	"Barry", "Chloe", "Nigel", "Fatima", "Pete", "Grace", "Wayne", "Mei", "Colin", "Zara", "Ian", "Bev"]
const LAST_NAMES := ["Smith", "Patel", "Jones", "O'Brien", "Taylor", "Khan", "Walsh", "Brown", "Nguyen", "Evans",
	"Hughes", "Okafor", "Clarke", "Murphy", "Reid", "Kowalski"]
const VIP_TITLES := ["Lord", "Lady", "Sir", "Dame", "Count", "Baroness"]
const CLOTHES := [Color(0.15, 0.25, 0.55), Color(0.55, 0.12, 0.12), Color(0.2, 0.45, 0.25), Color(0.85, 0.75, 0.2),
	Color(0.35, 0.35, 0.38), Color(0.6, 0.35, 0.15), Color(0.5, 0.2, 0.5), Color(0.9, 0.9, 0.88), Color(0.1, 0.1, 0.12),
	Color(0.2, 0.55, 0.65)]
const SKINS := [Color(0.95, 0.8, 0.68), Color(0.85, 0.66, 0.52), Color(0.68, 0.48, 0.34), Color(0.45, 0.3, 0.2),
	Color(0.3, 0.2, 0.14)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.35, 0.2, 0.1), Color(0.75, 0.6, 0.3), Color(0.6, 0.6, 0.6), Color(0.55, 0.2, 0.08)]


# ---------------------------------------------------------------------------- state

## A new shed's contracts: nobody waiting yet, no reputation.
static func empty() -> Dictionary:
	return {"clock": 0.0, "next_at": FIRST_CUSTOMER, "reputation": 0, "customers": {}, "jobs": {}, "done": [],
		"next": 1, "certs": 0, "earned": 0, "leaving": []}


## Saved or synced contracts made safe to use: anything missing (sheds from before contracts)
## gets its default.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
		elif s.has(key) and key in ["clock", "next_at"] and (s[key] is int or s[key] is float):
			out[key] = float(s[key])
	return out


static func _st() -> Dictionary:
	if not (Shed.contracts is Dictionary) or not Shed.contracts.has("jobs"):
		Shed.contracts = empty()
	return Shed.contracts


static func clock() -> float:
	return float(_st()["clock"])


static func reputation() -> int:
	return int(_st()["reputation"])


static func customers() -> Dictionary:
	return _st()["customers"]


static func jobs() -> Dictionary:
	return _st()["jobs"]


## The game day number (day 1 is the shed's first) for menus and certificates.
static func day_number(at := -1.0) -> int:
	return int(floor((clock() if at < 0.0 else at) / DAY)) + 1


## "2 days 5 h", "3 h", "overdue 1 day" for a deadline.
static func due_text(due: float) -> String:
	var left := due - clock()
	if left < 0.0:
		var late := ceili(-left / DAY)
		return "overdue %d day%s" % [late, "" if late == 1 else "s"]
	var d := int(left / DAY)
	var h := int(fmod(left, DAY))
	if d == 0:
		return "%d h left" % maxi(h, 1)
	return "%d day%s %d h left" % [d, "" if d == 1 else "s", h]


static func money(v: int) -> String:
	return TvChannels.money_text(v)


## Game hours that pass each real second: the day/night cycle's, or with the cycle off the
## same rate the day length setting gives, so deadlines still come round.
static func hours_rate() -> float:
	var r := Daylight.local_rate()
	if r <= 0.0:
		r = 24.0 / (maxf(float(Settings.day_length), 1.0) * 60.0)
	return r


## Which kinds of job customers bring at this reputation.
static func unlocked(rep := -1) -> Array:
	var r := reputation() if rep < 0 else rep
	return KINDS.filter(func(k): return r >= int(UNLOCK[k]))


# ---------------------------------------------------------------------------- places

static func _const(key: String):
	var m: Dictionary = load("res://scripts/workshop.gd").get_script_constant_map()
	return m.get(key)


static func _point(v) -> Transform3D:
	if v is Transform3D:
		return v
	if v is Vector3:
		return Transform3D(Basis(), v)
	return Transform3D()


## Where a customer stands to talk: the sales office reception when there is one, else just
## outside the roller door. -Z faces the counter.
static func reception() -> Transform3D:
	var r = _const("RECEPTION")
	if r is Transform3D or r is Vector3:
		return _point(r)
	return Transform3D(Basis(), door_front())


## Just outside the shed's roller door, beside the drive (where bikes can always be handed back).
static func door_front() -> Vector3:
	return Workshop.CENTER + Vector3(-3.4, 0.0, Workshop.HALF.y + 1.6)


## Where customers turn up from.
static func entry() -> Transform3D:
	var e = _const("CUSTOMER_ENTRY")
	if e is Transform3D or e is Vector3:
		return _point(e)
	return Transform3D(Basis(Vector3.UP, PI), Workshop.CENTER + Vector3(-4.5, 0.0, Workshop.HALF.y + 14.0))


## The way a customer walks in: from the entry (or from beside their bike in car park bay
## `park`, along the walkway), through the sales doors if there are any, to the counter. A
## queue forms behind the first one.
static func path_in(place: int, park := -1) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var door = _const("SALES_DOOR")
	if park >= 0:
		var side := park_xf(park).origin + Vector3(0.75, 0.0, 0.3)
		var kerb := SalesOffice.FORECOURT.position.y + 8.2
		pts.append(side)
		pts.append(Vector3(side.x, 0.0, kerb))
		if door is Vector3:
			pts.append(Vector3(door.x, 0.0, kerb))
	else:
		pts.append(entry().origin)
	if door is Vector3:
		pts.append(door)
	var at := reception()
	pts.append(at.origin + at.basis.z * (1.0 * place) + at.basis.x * (0.3 * place))
	return pts


## Car park bay `i`: where a customer's bike stands, nose-in towards the sales office (-Z).
static func park_xf(i: int) -> Transform3D:
	var f := SalesOffice.FORECOURT
	var k := clampi(i, 0, PARK_SLOTS - 1)
	return Transform3D(Basis(), Vector3(f.position.x + PARK_FROM.x + PARK_STEP * k, 0.0, f.position.y + PARK_FROM.y))


## The customer car park in front of the sales office (the tarmac strip with the marked bays),
## as an x/z rectangle: finished jobs are handed back from here.
static func car_park() -> Rect2:
	var f := SalesOffice.FORECOURT
	return Rect2(f.position.x, f.position.y + 9.0, f.size.x, f.size.y - 9.0)


## Whether a point is in the customer car park.
static func in_car_park(at: Vector3) -> bool:
	return car_park().grow(0.3).has_point(Vector2(at.x, at.z)) and Workshop.room_at(at) == ""


## A car park bay nobody's customer has taken and no bike stands in, or -1.
static func free_park() -> int:
	var taken := {}
	for id in customers():
		taken[int(customers()[id].get("park", -1))] = true
	for i in PARK_SLOTS:
		if taken.has(i):
			continue
		var at := park_xf(i).origin
		var clear := true
		for b in Shed.bikes.values():
			var o: Vector3 = (b["xf"] as Transform3D).origin
			if Vector2(o.x - at.x, o.z - at.z).length() < 1.4:
				clear = false
		if clear:
			return i
	return -1


## The point on the ring road where it passes the yard at `x` (the road is flat there). East of
## the shed that's the loop's own curve; west of it, the line World lays the loop along.
static func road_at(x: float) -> Vector3:
	if x < 0.0:
		var west := _west_road()
		for i in range(1, west.size()):
			if west[i].x >= x or i == west.size() - 1:
				var f := clampf(inverse_lerp(west[i - 1].x, west[i].x, x), 0.0, 1.0)
				return Vector3(x, 0.0, lerpf(west[i - 1].y, west[i].y, f))
	var lo := 0.0
	var hi := 0.8
	for i in 32:
		var mid := (lo + hi) * 0.5
		if _loop(mid).x < x:
			lo = mid
		else:
			hi = mid
	var p := _loop((lo + hi) * 0.5)
	return Vector3(p.x, 0.0, p.z)


## The ring road's centre line by angle (the same loop World lays the road along east of the shed).
static func _loop(theta: float) -> Vector3:
	var f := 1.0 + 0.1 * sin(3.0 * theta + 0.5) + 0.05 * sin(5.0 * theta + 2.0)
	return Vector3(185.0 * f * sin(theta), 0.0, 126.0 * f * cos(theta))


## The loop's line past the west half of the yard (x -90..0), west to east: its smooth curve
## through WorldLayout's points, as World lays it.
static func _west_road() -> PackedVector2Array:
	if _west.is_empty():
		var pts := []
		for r: Dictionary in WorldLayout.ROADS:
			if r["name"] == "loop":
				for p in WorldRoads._spline(PackedVector2Array(r["pts"]), true):
					if p.x > -90.0 and p.x < 1.0 and p.y > 110.0:
						pts.append(p)
		pts.sort_custom(func(a, b): return a.x < b.x)
		_west = PackedVector2Array(pts)
	return _west


## A rider's own dice for their way in or out (`salt` tells the two apart): seeded from
## `rider`, an id every machine has, so all the players see them take the same way.
static func route_rng(rider: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (rider * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	return rng


## Which end of the road past the yard a rider comes from (or goes off to) and how they come off
## it: {east: that end, turn: the x they come off the road at, lane: how far left of the middle
## of the road they keep (it's a left-hand road), mid: a nudge to their line across the yard,
## swing: they sweep in from that side of the car park}. From `rng`, or with none the classic
## way: from the east along the middle of the road and straight up the yard.
static func _route(rng: RandomNumberGenerator) -> Dictionary:
	if rng == null:
		return {"east": true, "turn": ROAD_TURN_X, "lane": 0.0, "mid": Vector2.ZERO, "swing": 0.0}
	var east := rng.randf() < 0.55
	# From the west they come off short of the tabletop's corner of the yard.
	var turn := rng.randf_range(22.0, 32.0) if east else rng.randf_range(12.0, 22.0)
	var swing := 0.0
	if rng.randf() < 0.25:
		swing = 7.0 if rng.randf() < 0.5 else -7.0
	return {"east": east, "turn": turn, "lane": rng.randf_range(1.4, 2.4),
		"mid": Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 6.0)), "swing": swing}


## The road past the yard at each x of `xs` in turn, kept `lane` metres left of its middle going
## that way.
static func road_line(xs: Array, lane: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for x in xs:
		pts.append(road_at(float(x)))
	if lane != 0.0 and pts.size() >= 2:
		var mid := pts.duplicate()
		for i in pts.size():
			var d := mid[mini(i + 1, pts.size() - 1)] - mid[maxi(i - 1, 0)]
			pts[i] += Vector3.UP.cross(d.normalized()) * lane
	return pts


## The road leg of route `r`'s way in, ending where they come off it.
static func _road_in(r: Dictionary) -> PackedVector3Array:
	if r["east"]:
		return road_line([ROAD_FAR_X, 56.0, 40.0, r["turn"]], r["lane"])
	return road_line([-ROAD_FAR_X, -45.0, -20.0, 0.0, r["turn"]], r["lane"])


## The road leg of route `r`'s way off, from where they join it.
static func _road_out(r: Dictionary) -> PackedVector3Array:
	if r["east"]:
		return road_line([r["turn"], 40.0, 56.0, ROAD_FAR_X], r["lane"])
	return road_line([r["turn"], 0.0, -20.0, -45.0, -ROAD_FAR_X], r["lane"])


## Where route `r`'s way across the yard meets the road.
static func _yard_gate(r: Dictionary) -> Vector3:
	return Vector3(float(r["turn"]) + (-3.0 if r["east"] else 3.0), 0.0, 116.0)


## The ride in: along the road past the yard, up across it and into car park bay `park`. With a
## `rider` (an id every machine has, >= 0) it's their own way: from either end of the road, off
## it at their own spot and on their own line across the yard. Without, the classic way.
static func ride_in_path(park: int, rider := -1) -> PackedVector3Array:
	return ride_in_to(park_xf(park).origin, rider)


## The ride in to `spot` (see ride_in_path), ending with a straight 6 m nose-in (-Z) to it.
static func ride_in_to(spot: Vector3, rider := -1) -> PackedVector3Array:
	var r := _route(route_rng(rider, 1) if rider >= 0 else null)
	var pts := _road_in(r)
	pts.append(_yard_gate(r))
	var mid: Vector2 = r["mid"]
	var swing := float(r["swing"])
	if swing != 0.0:
		# Up the yard off to one side of the bay, then sweeping round into it.
		pts.append(Vector3(clampf(spot.x + swing + mid.x * 0.3, 14.0, 39.0), 0.0, 96.0 + mid.y))
		pts.append(Vector3(spot.x + swing * 0.45, 0.0, spot.z + 9.5))
	else:
		pts.append(Vector3(clampf(spot.x + mid.x, 14.0, 39.0), 0.0, 94.0 + mid.y))
	pts.append(Vector3(spot.x, 0.0, spot.z + 6.0))
	pts.append(spot)
	return pts


## The ride away from where a bike stands: out of its bay and the roller door (through the
## extension's doorway from its bays), across the yard to the road and off along it. With a
## `rider` (>= 0) they go their own way, off either way along the road (see ride_in_path).
static func ride_out_path(from: Transform3D, rider := -1) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var at := Vector3(from.origin.x, 0.0, from.origin.z)
	pts.append(at)
	var c := Workshop.CENTER
	var door_z := c.z + Workshop.HALF.y
	var room := Workshop.room_at(at)
	if room == "wing":
		pts.append(Vector3(at.x, 0.0, GarageUpgrades.WING.end.y - 2.6))
		pts.append(Vector3(GarageUpgrades.WING_DOOR_X, 0.0, GarageUpgrades.WING.end.y - 2.6))
		pts.append(Vector3(GarageUpgrades.WING_DOOR_X, 0.0, c.z - Workshop.HALF.y + 1.2))
		pts.append(Vector3(c.x + 1.2, 0.0, door_z - 2.0))
	elif room == "shed":
		pts.append(Vector3(at.x, 0.0, maxf(at.z + 2.0, c.z + 1.0)))
		pts.append(Vector3(clampf(at.x, c.x - 1.2, c.x + 1.2), 0.0, door_z - 1.2))
	if room in ["wing", "shed"]:
		pts.append(Vector3(c.x, 0.0, door_z + 2.5))
	elif at.z < SalesOffice.FORECOURT.end.y and at.x > SalesOffice.FORECOURT.position.x - 1.0:
		# From the car park or the forecourt: back out of the bay first.
		pts.append(Vector3(at.x, 0.0, at.z + 2.0))
		pts.append(Vector3(at.x, 0.0, SalesOffice.FORECOURT.end.y + 4.0))
	var r := _route(route_rng(rider, 2) if rider >= 0 else null)
	pts.append(_yard_gate(r))
	pts.append_array(_road_out(r))
	return pts


## The walk a customer collecting their bike makes to it: from the sales office counter out
## through its doors to the car park, where finished jobs are left for them. (A ride away kept
## in a save from before then can start from a bay: in from just outside the roller door.)
static func collect_path(bike_xf: Transform3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var at := bike_xf.origin
	var side := at + bike_xf.basis.x * 0.75 + bike_xf.basis.z * 0.3
	side.y = 0.0
	var door = _const("SALES_DOOR")
	if in_car_park(at) and door is Vector3:
		var kerb := SalesOffice.FORECOURT.position.y + 8.2
		pts.append(reception().origin)
		pts.append(door)
		pts.append(Vector3(door.x, 0.0, kerb))
		pts.append(Vector3(side.x, 0.0, kerb))
		pts.append(side)
		return pts
	var room := Workshop.room_at(at)
	var c := Workshop.CENTER
	if room in ["wing", "shed"]:
		pts.append(c + Vector3(1.5, 0.0, Workshop.HALF.y + 5.0))
		pts.append(c + Vector3(0.6, 0.0, Workshop.HALF.y - 0.8))
		if room == "wing":
			pts.append(Vector3(GarageUpgrades.WING_DOOR_X, 0.0, c.z - Workshop.HALF.y + 1.2))
			pts.append(Vector3(GarageUpgrades.WING_DOOR_X, 0.0, GarageUpgrades.WING.end.y - 2.0))
		else:
			pts.append(Vector3(side.x, 0.0, maxf(side.z + 2.0, c.z + 1.0)))
	else:
		pts.append(entry().origin)
	pts.append(side)
	return pts


# ---------------------------------------------------------------------------- time passing

## The host's clock moves on and customers come and go. `delta` is real seconds.
static func process(delta: float) -> void:
	advance(delta * hours_rate())


## Moves the contracts clock on `hours` game hours (host only): customers who've waited too
## long leave, and a new one comes when it's time.
static func advance(hours: float) -> void:
	var s := _st()
	var before := float(s["clock"])
	s["clock"] = before + maxf(hours, 0.0)
	var now := float(s["clock"])
	var changed := false
	for id in customers().keys():
		if now >= float(customers()[id].get("leave_at", 0.0)):
			customers().erase(id)
			changed = true
	for id in jobs():
		var job: Dictionary = jobs()[id]
		if not Shed.bikes.has(int(job.get("bike", 0))) and str(job.get("state", "")) == "active":
			job["state"] = "lost"
			changed = true
	for id in jobs().keys():
		if str(jobs()[id].get("state", "")) == "lost":
			_finish(jobs()[id], {"paid": 0, "sat": 0.0, "late": 0, "rep": -2, "note": "The bike went missing."})
			changed = true
	var leaving: Array = s["leaving"]
	for d in leaving.duplicate():
		if not (d is Dictionary) or now - float(d.get("at", 0.0)) > LEAVING_HOURS:
			leaving.erase(d)
			changed = true
	if now >= float(s["next_at"]):
		s["next_at"] = now + Shed._rng.randf_range(SPAWN_HOURS.x, SPAWN_HOURS.y)
		if customers().size() < MAX_WAITING:
			spawn()
			changed = true
	# Clients' deadlines tick over at least every game hour.
	if changed or floor(before) != floor(now):
		Shed._mark_dirty()
	if changed:
		Shed.changed.emit()


## A new customer comes in with an offer (host only). `kind` forces the job; "" picks one the
## reputation allows. Returns the customer's id.
static func spawn(kind := "") -> int:
	var s := _st()
	var rng: RandomNumberGenerator = Shed._rng
	if kind == "" or not KINDS.has(kind):
		var open := unlocked()
		# Harder jobs come less often than easy ones.
		var weights := {"maint": 4.0, "mot": 3.0, "mod": 2.0, "bespoke": 1.0}
		var total := 0.0
		for k in open:
			total += float(weights[k])
		var pick := rng.randf() * total
		kind = str(open[0])
		for k in open:
			pick -= float(weights[k])
			if pick <= 0.0:
				kind = str(k)
				break
	var id := int(s["next"])
	s["next"] = id + 1
	var vip := kind == "bespoke"
	var person_name := "%s %s" % [VIP_TITLES[rng.randi() % VIP_TITLES.size()] if vip else FIRST_NAMES[rng.randi() % FIRST_NAMES.size()],
		LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	var look := {"top": CLOTHES[rng.randi() % CLOTHES.size()], "legs": CLOTHES[rng.randi() % CLOTHES.size()].darkened(0.3),
		"skin": SKINS[rng.randi() % SKINS.size()], "hair": HAIR[rng.randi() % HAIR.size()], "hat": rng.randf() < 0.3,
		"tall": rng.randf_range(0.92, 1.06), "vip": vip}
	var now := clock()
	var offer := make_offer(kind, person_name)
	# Everyone but the exclusive customer rides their own bike in and parks it in the car park.
	var park := free_park() if kind != "bespoke" else -1
	if park >= 0:
		var parts: Dictionary = offer["parts"]
		if str(parts.get("side_stand", "none")) == "none" and str(parts.get("centre_stand", "none")) == "none":
			parts["side_stand"] = PartsDB.DEFAULT_BUILD["side_stand"]
		offer["paint"] = rng.randi() % Shed.PAINTS.size()
	customers()[id] = {"id": id, "name": person_name, "look": look, "arrived": now, "leave_at": now + PATIENCE_HOURS,
		"offer": offer, "park": park}
	Shed._mark_dirty()
	return id


# ---------------------------------------------------------------------------- offers

## A job for a customer: {kind, title, bike_name, parts (the bike they bring, or the frame for a
## bespoke build), goals [...], budget, pay, days, blurb}.
static func make_offer(kind: String, person_name: String) -> Dictionary:
	var rng: RandomNumberGenerator = Shed._rng
	var first := person_name.get_slice(" ", 1) if kind == "bespoke" else person_name.get_slice(" ", 0)
	var offer := {"kind": kind, "budget": 0, "goals": []}
	match kind:
		"maint":
			var parts := random_parts(rng)
			var size: Dictionary = SERVICES[rng.randi() % SERVICES.size()]
			var keys: Array = TASKS.keys().filter(func(k): return task_fits(str(k), parts))
			_shuffle(keys, rng)
			var range_n: Vector2i = size["n"]
			var n := mini(rng.randi_range(range_n.x, range_n.y), keys.size())
			var picked: Array = keys.slice(0, n)
			for k in picked:
				offer["goals"].append({"t": "task", "task": str(k)})
			offer["parts"] = parts
			offer["pay"] = int(snappedi(30 + roundi(_tasks_pay(picked) * rng.randf_range(0.95, 1.3)), 5))
			offer["budget"] = _tasks_budget(picked, parts, rng)
			var range_d: Vector2i = size["days"]
			offer["days"] = rng.randi_range(range_d.x, range_d.y)
			offer["blurb"] = size["blurb"]
		"mot":
			var parts := random_parts(rng, true)
			offer["parts"] = parts
			offer["goals"] = [{"t": "mot"}]
			# How far gone it is: a couple of faults to a bike that's been off the road for years.
			var faults := rng.randi_range(2, 7)
			offer["faults"] = faults
			var extras: Array = MOT_EXTRAS.filter(func(k): return task_fits(str(k), parts))
			_shuffle(extras, rng)
			var extra: Array = extras.slice(0, 0 if rng.randf() < 0.5 else rng.randi_range(1, 2))
			for k in extra:
				offer["goals"].append({"t": "task", "task": str(k)})
			offer["pay"] = int(snappedi(120 + faults * rng.randi_range(22, 35) + roundi(_tasks_pay(extra) * rng.randf_range(0.95, 1.2)), 5))
			offer["budget"] = _tasks_budget(extra, parts, rng)
			offer["days"] = 2 + faults / 3 + rng.randi_range(0, 1)
			offer["blurb"] = "Its MOT's run out. Test it, fix whatever fails, and get me the certificate."
			if faults <= 3:
				offer["blurb"] = "MOT time. It's always been reliable, so it should be a quick one."
			elif faults >= 6:
				offer["blurb"] = "It's been off the road a while and the MOT's long run out. Test it, fix what fails, and get me the certificate."
			if not extra.is_empty():
				offer["blurb"] += " And while it's in: %s." % ", ".join(extra.map(func(k): return str(TASKS[k]).to_lower()))
		"mod":
			var parts := random_parts(rng, true)
			offer["parts"] = parts
			offer["goals"] = _mod_goals(parts, rng)
			var cost := 0
			var labour := 0
			for g in offer["goals"]:
				cost += _goal_cost(g, parts)
				labour += int(MOD_PAY.get(str(g["t"]), 150))
			offer["budget"] = int(snappedi(maxi(300, roundi(cost * rng.randf_range(1.15, 1.6))), 50))
			offer["pay"] = int(snappedi(150 + roundi(labour * rng.randf_range(0.9, 1.3)), 10))
			offer["days"] = 3 + offer["goals"].size() + rng.randi_range(0, 2)
			offer["blurb"] = ["I want it to be more me. Here's what I'm after, and what I can spend on parts.",
				"A few changes I've been dreaming about. Here's the list and the money for parts.",
				"Make it mine. Here's what I want and what I can put towards parts."][rng.randi() % 3]
		"bespoke":
			var style: String = STYLES.keys()[rng.randi() % STYLES.size()]
			var ref := style_build(style)
			offer["parts"] = {"frame": ref["frame"]}
			offer["goals"] = _bespoke_goals(style, ref, rng)
			var cost := 0
			for slot in PartsDB.SLOTS:
				if str(ref.get(slot, "none")) != "none" and slot != "frame":
					cost += est_cost(str(ref[slot]))
			offer["budget"] = int(snappedi(roundi(cost * rng.randf_range(1.2, 1.6)), 100))
			offer["pay"] = int(snappedi(1500 + offer["goals"].size() * rng.randi_range(400, 650), 100))
			offer["days"] = 8 + offer["goals"].size() + rng.randi_range(0, 2)
			offer["blurb"] = "Something nobody else has. Start from a bare frame and build me exactly this."
	var bike_name: String = "%s's %s" % [first, Shed.BIKE_NAMES[rng.randi() % Shed.BIKE_NAMES.size()]]
	if kind == "bespoke":
		bike_name = "%s's %s special" % [first, str(STYLES[offer["goals"][0]["style"]]).to_lower()]
	offer["bike_name"] = bike_name
	offer["title"] = "%s: %s" % [KIND_NAMES[kind], bike_name]
	return offer


## Whether a bike with `parts` can have a maintenance task done: it has the parts it renews.
static func task_fits(task: String, parts: Dictionary) -> bool:
	for slot in TASK_PARTS.get(task, []):
		if str(parts.get(slot, "none")) == "none":
			return false
	return true


## The labour for a list of tasks.
static func _tasks_pay(tasks: Array) -> int:
	var total := 0
	for k in tasks:
		total += int(TASK_PAY.get(str(k), 40))
	return total


## A parts budget for a list of tasks on a bike with `parts`: what the parts they renew cost,
## with a bit over (0 when none need parts).
static func _tasks_budget(tasks: Array, parts: Dictionary, rng: RandomNumberGenerator) -> int:
	var cost := 0
	for k in tasks:
		for slot in TASK_PARTS.get(str(k), []):
			var part := str(parts.get(slot, "none"))
			if part != "none":
				cost += est_cost(part)
	if cost <= 0:
		return 0
	return int(snappedi(roundi(cost * rng.randf_range(1.1, 1.4)), 10))


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## The share of customers' bikes built mostly in one style.
const LEAN_CHANCE := 0.7


## A believable random road bike's parts, like a project bike's. `road` keeps it road legal
## (no race slicks).
static func random_parts(rng: RandomNumberGenerator, road := false) -> Dictionary:
	var parts := {}
	var pick := {}
	# Most bikes lean towards one style: where a kind has parts made for it, those are picked.
	var lean: String = PartsDB.STYLES[rng.randi() % PartsDB.STYLES.size()] if rng.randf() < LEAN_CHANCE else ""
	for slot in PartsDB.SLOTS:
		var k: String = PartsDB.SLOT_KIND[slot]
		if slot == "front_mudguard" or PartsDB.FILLER_SLOTS.has(slot):
			continue   # the ones that suit the rest of it (sanitize_build and dress_fillers pick them)
		var key: String = k if k == "tyre" else slot
		if not pick.has(key):
			var options: Array = PartsDB.by_kind[k].duplicate()
			if road and k == "tyre":
				options = options.filter(func(t): return str(PartsDB.get_part(str(t)).get("style", "")) != "slick")
			if lean != "" and k != "tyre":
				var suits: Array = options.filter(func(id): return PartsDB.styles_of(str(id)).has(lean))
				if not suits.is_empty():
					options = suits
			if PartsDB.is_optional(slot):
				options.append("none")
			pick[key] = options[rng.randi() % options.size()]
		parts[slot] = pick[key]
	for ws in Shed.WHEEL_TYRE:
		var ts: String = Shed.WHEEL_TYRE[ws]
		var wheel := str(parts[ws])
		var picked := str(parts[ts])
		if PartsDB.tyre_fit(picked, wheel) == 0:
			continue
		var fits: Array = PartsDB.tyres_for(wheel)
		if road:
			fits = fits.filter(func(t): return str(PartsDB.get_part(str(t)).get("style", "")) != "slick")
		if fits.is_empty():
			continue
		var family := picked.get_slice("_", 0)
		var same: Array = fits.filter(func(t): return str(t).begins_with(family))
		var from: Array = same if not same.is_empty() else fits
		parts[ts] = from[rng.randi() % from.size()]
	if parts["headlight"] == "none":
		parts["fairing"] = "none"
	if parts["mirrors"] != "none" and not PartsDB.part_mounts("mirrors", parts["mirrors"]).all(func(m): return parts.get(m, "none") != "none"):
		parts["mirrors"] = "round_mirrors"
	return PartsDB.dress_fillers(PartsDB.sanitize_build(parts), int(rng.state % 97))


## What a part costs: the parts computer's price once parts have one, else a rough guess.
static func est_cost(part: String) -> int:
	var p := price(part)
	return p if p > 0 else int(EST_COST.get(PartsDB.kind_of(part), 100))


## The parts computer's price for a part (0 while parts are free).
static func price(part: String) -> int:
	if part == "" or part == "none":
		return 0
	return int(Shed.part_price(part))


## Parts for a bike in a style: the reference a bespoke build's targets are worked out from.
static func style_build(style: String) -> Dictionary:
	var b: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	match style:
		"cafe":
			b.merge({"frame": "steel_cradle", "tank": "alloy_cafe_14", "saddle": "cafe_hump", "handlebars": "alloy_clip_ons",
				"tail": "cafe_tail", "engine": "twin_750", "exhaust": "full_system", "headlight": "bates_cafe",
				"front_wheel": "wire_19_chrome", "rear_wheel": "spoked_18", "front_tyre": "vintage_ribbed_100",
				"rear_tyre": "vintage_ribbed", "mirrors": "bar_end_mirrors", "front_mudguard": "alloy_cafe_blade"}, true)
		"scrambler":
			b.merge({"frame": "steel_backbone", "tank": "peanut_9", "saddle": "flat_bench", "handlebars": "mx_tall",
				"tail": "scrambler_loop", "engine": "twin_500", "exhaust": "scrambler_high_twin", "front_wheel": "spoked_19_adventure",
				"rear_wheel": "spoked_18", "front_tyre": "dual_sport_90", "rear_tyre": "dual_sport", "fork": "enduro_usd",
				"mirrors": "round_mirrors", "front_mudguard": "enduro_front_fender"}, true)
		"tourer":
			b.merge({"frame": "alu_twin_spar", "tank": "touring_23", "saddle": "touring_comfort", "handlebars": "flat_bar",
				"tail": "classic_mudguard", "engine": "boxer_1100", "panniers": "aluminium_boxes", "top_box": "alloy_top_box",
				"fairing": "touring_fairing", "mirrors": "fairing_mirrors", "headlight": "led_projector",
				"rear_tyre": "touring_road", "front_tyre": "touring_road_120", "front_mudguard": "chrome_classic"}, true)
		"sport":
			b.merge({"frame": "sport_perimeter_red", "tank": "sport_17", "saddle": "sport_solo", "handlebars": "clip_ons",
				"tail": "sport_pointed_tail", "engine": "inline_1000", "exhaust": "race_underseat_ti", "fairing": "sport_red_fairing",
				"fork": "usd_sport", "shock": "sport_mono", "ecu": "sport_ecu", "mirrors": "fairing_mirrors",
				"headlight": "led_projector", "front_mudguard": "carbon_hugger"}, true)
		"race":
			b.merge({"frame": "race_alu_perimeter", "tank": "race_white_red", "saddle": "race_foam_seat", "handlebars": "race_black_clips",
				"tail": "race_hump", "engine": "inline_1000", "exhaust": "race_hex_carbon", "fairing": "race_white_fairing",
				"fork": "race_works_usd", "shock": "sport_mono", "ecu": "sport_ecu", "mirrors": "none", "front_wheel": "race_mag_gold",
				"rear_wheel": "race_mag_gold", "headlight": "led_projector", "front_mudguard": "race_white_hugger"}, true)
		"bobber":
			b.merge({"frame": "softail_hardtail", "tank": "peanut_9", "saddle": "flat_bench", "handlebars": "drag_bar",
				"tail": "bobber_fender", "engine": "vtwin_1000", "exhaust": "straight_pipe", "front_wheel": "wire_16_bobber",
				"rear_wheel": "wire_16_bobber", "mirrors": "bar_end_mirrors", "front_mudguard": "bobbed_steel"}, true)
		"chopper":
			b.merge({"frame": "chopper_raked", "fork": "springer_long", "tank": "peanut_9", "saddle": "flat_bench",
				"handlebars": "ape_hangers", "tail": "bobber_fender", "engine": "vtwin_1200", "exhaust": "shotgun_duals",
				"front_wheel": "wire_19_chrome", "rear_wheel": "wire_16_bobber", "headlight": "bates_cafe", "mirrors": "bar_end_mirrors",
				"front_mudguard": "none"}, true)
		"cruiser":
			b.merge({"frame": "cruiser_cradle", "tank": "peanut_9", "saddle": "touring_comfort", "handlebars": "drag_bar",
				"tail": "classic_mudguard", "engine": "vtwin_1100", "exhaust": "shotgun_duals", "front_wheel": "cast_19_six",
				"rear_wheel": "wire_16_bobber", "panniers": "leather_saddlebags", "mirrors": "round_mirrors", "front_mudguard": "chrome_classic"}, true)
		"adventure":
			b.merge({"frame": "adv_trellis", "fork": "enduro_usd", "shock": "enduro_mono", "tank": "adv_big_tank", "saddle": "adv_comfort_seat",
				"handlebars": "mx_tall", "tail": "enduro_fender", "engine": "boxer_1100", "exhaust": "mx_upswept", "front_wheel": "spoked_19_adventure",
				"rear_wheel": "spoked_18", "front_tyre": "dual_sport_90", "rear_tyre": "dual_sport", "panniers": "aluminium_boxes",
				"fairing": "adv_beak_red", "headlight": "led_projector", "mirrors": "touring_mirrors", "front_mudguard": "enduro_front_fender"}, true)
		"mx":
			b.merge({"frame": "mx_twin_loop", "fork": "long_travel_mx", "shock": "mono_shock_mx", "tank": "enduro_12", "saddle": "enduro_seat",
				"handlebars": "mx_tall", "tail": "enduro_fender", "engine": "single_450", "exhaust": "mx_upswept", "front_wheel": "excel_21_black",
				"rear_wheel": "spoked_18", "front_tyre": "knobbly_mx_80", "rear_tyre": "knobbly_mx", "front_mudguard": "mx_high_fender",
				"headlight": "rect_enduro", "number_boards": "mx_side_boards"}, true)
		"supermoto":
			b.merge({"frame": "mx_twin_loop", "fork": "long_travel_mx", "shock": "mono_shock_mx", "tank": "sm_orange_tank", "saddle": "sm_flat_seat",
				"handlebars": "mx_tall", "tail": "enduro_fender", "engine": "single_450", "exhaust": "mx_upswept", "front_wheel": "supermoto_17",
				"rear_wheel": "supermoto_17", "front_tyre": "sport_road_120", "rear_tyre": "sport_road_160", "front_mudguard": "mx_high_fender",
				"headlight": "rect_enduro", "mirrors": "sport_mirrors"}, true)
	b = PartsDB.sanitize_build(b)
	# Finished off with the bolt-on bits that suit it, where the reference doesn't name its own.
	var dressed := PartsDB.dress_fillers(b)
	for slot in PartsDB.FILLER_SLOTS:
		if str(b[slot]) == "none":
			b[slot] = dressed[slot]
	for ws in Shed.WHEEL_TYRE:
		var ts: String = Shed.WHEEL_TYRE[ws]
		if PartsDB.tyre_fit(str(b[ts]), str(b[ws])) != 0:
			var fits: Array = PartsDB.tyres_for(str(b[ws])).filter(func(t): return str(PartsDB.get_part(str(t)).get("style", "")) != "slick")
			if not fits.is_empty():
				b[ts] = fits[0]
	return b


## How well a build matches a style: [markers it has, markers needed]. A style counts with
## three of its four marks.
static func style_marks(style: String, parts: Dictionary) -> Array:
	var p := func(slot: String) -> String: return str(parts.get(slot, "none"))
	var st := func(slot: String) -> String: return str(PartsDB.get_part(p.call(slot)).get("style", ""))
	var marks := []
	match style:
		"cafe":
			marks = [st.call("tank") == "cafe", st.call("saddle") == "cafe", p.call("handlebars") in ["clip_ons", "alloy_clip_ons"],
				p.call("tail") == "cafe_tail"]
		"scrambler":
			marks = [st.call("rear_tyre") == "offroad", p.call("handlebars") in ["flat_bar", "mx_tall", "titanium_flat"],
				p.call("tail") == "scrambler_loop", st.call("tank") in ["peanut", "enduro"]]
		"tourer":
			marks = [p.call("panniers") != "none", p.call("top_box") != "none", st.call("saddle") == "touring",
				st.call("tank") == "touring" or st.call("fairing") in ["touring", "half"]]
		"sport":
			marks = [st.call("fairing") == "race", st.call("saddle") == "sport", p.call("handlebars") in ["clip_ons", "alloy_clip_ons"],
				st.call("tank") == "sport"]
		"bobber":
			marks = [p.call("tail") == "bobber_fender", p.call("handlebars") in ["drag_bar", "ape_hangers"],
				st.call("saddle") == "bench", p.call("exhaust") == "straight_pipe" or st.call("tank") == "peanut"]
		_:
			for slot in STYLE_KEYS.get(style, []):
				marks.append(PartsDB.styles_of(p.call(slot)).has(style))
	var have := marks.count(true)
	# A bike that's a proper one of the style all over (see PartsDB.detect_style) counts too,
	# whichever marks it picked to get there.
	var d := PartsDB.detect_style(parts)
	if str(d["style"]) == style and d["proper"]:
		have = maxi(have, 3)
	return [have, 3]


## What a style's parts look like, for the offer card.
static func style_hint(style: String) -> String:
	return {"cafe": "cafe tank and seat, clip-ons, tail hump", "scrambler": "off-road tyres, flat or MX bars, scrambler loop, small tank",
		"tourer": "panniers, top box, touring seat, big tank or fairing", "sport": "race fairing, sport seat and tank, clip-ons",
		"bobber": "bobbed fender, drag bars or apes, bench seat, straight pipe or peanut tank",
		"chopper": "raked chopper frame, long springer fork, ape hangers, bobbed fender",
		"cruiser": "long low cruiser frame, shotgun pipes, drag bars, comfy seat",
		"adventure": "tall adventure frame, big tank, touring screen, panniers",
		"mx": "MX frame, long-travel fork, small tank, number boards",
		"supermoto": "supermoto wheels, high front fender, MX bars"}.get(style, "")


static func _summary(parts: Dictionary) -> Dictionary:
	return BikeBuild.new(PartsDB.sanitize_build(parts.duplicate()), {}).summary()


static func _mod_goals(parts: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool := []
	var now := _summary(parts)
	# Faster: what a race exhaust, a remap and taller gearing would give, most of the way.
	var fast := parts.duplicate()
	fast["exhaust"] = "titanium_race"
	fast["ecu"] = "race_ecu"
	fast["air_filter"] = "velocity_stacks"
	fast["final_drive"] = "top_speed_16_40"
	var ref := _summary(fast)
	if float(ref["top_kmh"]) - float(now["top_kmh"]) >= 8.0:
		pool.append({"t": "top_kmh", "min": snappedf(float(now["top_kmh"]) + (float(ref["top_kmh"]) - float(now["top_kmh"])) * 0.55, 1.0)})
	# More power: the same kit would give it, half of the gain is asked for.
	if float(ref["hp"]) - float(now["hp"]) >= 6.0 and rng.randf() < 0.6:
		pool.append({"t": "hp", "min": snappedf(float(now["hp"]) + (float(ref["hp"]) - float(now["hp"])) * 0.5, 1.0)})
	# Lighter: a carbon frame wheel and bodywork would give this, half of it is asked for.
	var light := parts.duplicate()
	for slot in ["front_wheel", "rear_wheel"]:
		light[slot] = "forged_17_mag"
	light["tank"] = "carbon_sport_16"
	light["saddle"] = "carbon_race_seat"
	light["exhaust"] = "titanium_race"
	light["handlebars"] = "titanium_flat"
	var lref := _summary(light)
	if float(now["mass"]) - float(lref["mass"]) >= 6.0:
		pool.append({"t": "mass", "max": snappedf(float(now["mass"]) - (float(now["mass"]) - float(lref["mass"])) * 0.4, 1.0)})
	var styles: Array = STYLES.keys().filter(func(s): return style_marks(str(s), parts)[0] < 3)
	if not styles.is_empty():
		pool.append({"t": "style", "style": styles[rng.randi() % styles.size()]})
	var empty_slots: Array = FIT_SLOTS.keys().filter(func(s): return str(parts.get(s, "none")) == "none")
	_shuffle(empty_slots, rng)
	# Something fitted, or now and then two things.
	for slot in empty_slots.slice(0, 1 if rng.randf() < 0.7 else 2):
		pool.append({"t": "fit", "slot": slot})
	# Better brakes: radial four-pots up front.
	if str(parts.get("front_caliper", "")) != "four_piston_radial" and rng.randf() < 0.5:
		pool.append({"t": "part", "slot": "front_caliper", "part": "four_piston_radial"})
	if not str(parts.get("exhaust", "")) in PIPES:
		pool.append({"t": "pipes", "from": str(parts.get("exhaust", ""))})
	pool.append({"t": "paint", "color": rng.randi() % Shed.PAINTS.size()})
	_shuffle(pool, rng)
	# A tourer and a fairing goal, or a lighter bike and luggage, can fight each other: keep it simple.
	var goals := pool.slice(0, rng.randi_range(2, mini(5, pool.size())))
	var has_style := goals.any(func(g): return g["t"] == "style")
	if has_style:
		goals = goals.filter(func(g): return g["t"] != "mass")
	if goals.size() < 2:
		goals.append({"t": "paint", "color": rng.randi() % Shed.PAINTS.size()})
	return goals


static func _goal_cost(g: Dictionary, parts: Dictionary) -> int:
	match str(g["t"]):
		"top_kmh":
			return est_cost("titanium_race") + est_cost("race_ecu") + est_cost("top_speed_16_40")
		"mass":
			return est_cost("forged_17_mag") * 2 + est_cost("carbon_sport_16")
		"style":
			return est_cost("cafe_15") + est_cost("cafe_hump") + est_cost("clip_ons") + est_cost("cafe_tail")
		"fit":
			return int(EST_COST.get(str(g["slot"]), 150))
		"hp":
			return est_cost("race_ecu") + est_cost("velocity_stacks")
		"part":
			return est_cost(str(g["part"]))
		"pipes":
			return est_cost("full_system")
		"paint":
			return 60
	return 0


## A bespoke build's targets: the style always, then some of: performance (speed, power or
## both), a weight limit, one or two signature parts, a tank colour, and a finish standard.
static func _bespoke_goals(style: String, ref: Dictionary, rng: RandomNumberGenerator) -> Array:
	var s := _summary(ref)
	var goals := [{"t": "style", "style": style}]
	var perf := rng.randf()
	if perf < 0.4:
		goals.append({"t": "top_kmh", "min": snappedf(float(s["top_kmh"]) * 0.92, 5.0)})
	elif perf < 0.8:
		goals.append({"t": "hp", "min": snappedf(float(s["hp"]) * 0.9, 1.0)})
	elif perf < 0.9:
		goals.append({"t": "top_kmh", "min": snappedf(float(s["top_kmh"]) * 0.92, 5.0)})
		goals.append({"t": "hp", "min": snappedf(float(s["hp"]) * 0.9, 1.0)})
	if rng.randf() < 0.7:
		goals.append({"t": "mass", "max": snappedf(float(s["mass"]) * 1.08, 1.0)})
	var signature: Array = ["engine", "exhaust", "tank", "front_wheel", "saddle", "handlebars"]
	signature = signature.filter(func(slot): return str(ref.get(slot, "none")) != "none")
	_shuffle(signature, rng)
	for slot in signature.slice(0, 1 if rng.randf() < 0.6 else 2):
		goals.append({"t": "part", "slot": slot, "part": str(ref[slot])})
	if rng.randf() < 0.8:
		goals.append({"t": "paint", "color": rng.randi() % Shed.PAINTS.size()})
	goals.append({"t": "health", "min": [0.9, 0.95, 0.98][rng.randi() % 3]})
	return goals


# ---------------------------------------------------------------------------- goals

## What a goal asks for, in a line for the offer card.
static func goal_text(g: Dictionary) -> String:
	match str(g.get("t", "")):
		"task":
			return str(TASKS.get(str(g["task"]), g["task"]))
		"mot":
			return "Pass the MOT (full inspection: tyres, brakes, suspension, lights, chain, exhaust, frame, mirrors...)"
		"top_kmh":
			return "Top speed at least %d km/h" % roundi(float(g["min"]))
		"hp":
			return "At least %d hp" % roundi(float(g["min"]))
		"mass":
			return "Weighs no more than %d kg" % roundi(float(g["max"]))
		"style":
			return "%s style (%s)" % [STYLES.get(str(g["style"]), g["style"]), style_hint(str(g["style"]))]
		"fit":
			return "%s fitted" % FIT_SLOTS.get(str(g["slot"]), PartsDB.slot_name(str(g["slot"])))
		"pipes":
			return "New pipes: a full system, race system or straight pipe"
		"paint":
			return "Tank painted %s" % Shed.PAINT_NAMES[clampi(int(g["color"]), 0, Shed.PAINT_NAMES.size() - 1)]
		"part":
			return "%s: %s" % [PartsDB.slot_name(str(g["slot"])), PartsDB.part_name(str(g["part"]))]
		"health":
			return "Condition at least %d%%" % roundi(float(g["min"]) * 100.0)
	return str(g)


static func _item(bike_id: int, slot: String) -> Dictionary:
	var id := Shed.item_on(bike_id, slot)
	return Shed.items.get(id, {})


static func _fluid_ok(it: Dictionary, fresh: float, full: float) -> bool:
	if it.is_empty() or not it.has("fluid"):
		return false
	var cap := PartsDB.fluid_capacity(str(it["part"]))
	return float(it["fluid"].get("age", 1.0)) <= fresh and float(it["fluid"]["litres"]) >= cap * full - 0.001


static func _fresh(it: Dictionary, wear := 0.25, dirt := 1.0) -> bool:
	return not it.is_empty() and float(it["wear"]) <= wear and float(it["dirt"]) <= dirt


## Whether a goal is met on a bike now, and what it reads: {done, have}.
static func eval_goal(job: Dictionary, g: Dictionary) -> Dictionary:
	var bike_id := int(job.get("bike", 0))
	if not Shed.bikes.has(bike_id):
		return {"done": false, "have": "no bike"}
	var parts := current_parts(bike_id)
	match str(g.get("t", "")):
		"task":
			return _eval_task(bike_id, str(g["task"]))
		"mot":
			var m: Dictionary = job.get("mot", {})
			if not m.get("tested", false):
				return {"done": false, "have": "not tested yet"}
			if m.get("stale", false):
				return {"done": false, "have": "worked on since the test: re-test it"}
			var fails := int(m.get("fails", 0))
			return {"done": fails == 0, "have": "passed" if fails == 0 else "%d fail%s" % [fails, "" if fails == 1 else "s"]}
		"top_kmh", "hp", "mass", "health":
			var sm := Shed.build_of(bike_id).summary()
			match str(g["t"]):
				"top_kmh":
					return {"done": float(sm["top_kmh"]) >= float(g["min"]) - 0.01, "have": "%d km/h" % roundi(float(sm["top_kmh"]))}
				"hp":
					return {"done": float(sm["hp"]) >= float(g["min"]) - 0.01, "have": "%d hp" % roundi(float(sm["hp"]))}
				"mass":
					return {"done": float(sm["mass"]) <= float(g["max"]) + 0.01, "have": "%d kg" % roundi(float(sm["mass"]))}
				"health":
					var h := bike_health(bike_id)
					return {"done": h >= float(g["min"]) - 0.0001, "have": "%d%%" % floori(h * 100.0)}
		"style":
			var m := style_marks(str(g["style"]), parts)
			return {"done": int(m[0]) >= int(m[1]), "have": "%d of 4 marks" % int(m[0])}
		"fit":
			var on := str(parts.get(str(g["slot"]), "none")) != "none"
			return {"done": on, "have": PartsDB.part_name(str(parts[g["slot"]])) if on else "none"}
		"pipes":
			var ex := str(parts.get("exhaust", "none"))
			return {"done": ex in PIPES and ex != str(g.get("from", "")), "have": PartsDB.part_name(ex) if ex != "none" else "none"}
		"paint":
			var tank := _item(bike_id, "tank")
			if tank.is_empty():
				return {"done": false, "have": "no tank"}
			if tank.get("primer_top", false):
				return {"done": false, "have": "grey primer"}
			var idx := Shed.paint_index(tank["color"])
			return {"done": idx == int(g["color"]), "have": str(Shed.PAINT_NAMES[idx])}
		"part":
			var p := str(parts.get(str(g["slot"]), "none"))
			return {"done": p == str(g["part"]), "have": PartsDB.part_name(p) if p != "none" else "none"}
	return {"done": false, "have": ""}


static func _eval_task(bike_id: int, task: String) -> Dictionary:
	match task:
		"oil":
			var e := _item(bike_id, "engine")
			var ok := _fluid_ok(e, 0.15, 0.8)
			return {"done": ok, "have": "fresh and full" if ok else "old or low"}
		"chain":
			var c := _item(bike_id, "chain")
			if c.is_empty():
				return {"done": false, "have": "no chain"}
			var slack := float(c.get("slack", Shed.CHAIN_SLACK_SET))
			var ok := float(c.get("lube", 0.0)) >= 0.6 and slack >= Shed.CHAIN_SLACK_GOOD.x and slack <= Shed.CHAIN_SLACK_GOOD.y
			return {"done": ok, "have": "%d mm, lube %d%%" % [roundi(slack), roundi(float(c.get("lube", 0.0)) * 100.0)]}
		"pads":
			var f := _item(bike_id, "front_pads")
			var r := _item(bike_id, "rear_pads")
			var ok := _fresh(f, 0.2) and _fresh(r, 0.2)
			return {"done": ok, "have": "good" if ok else "worn"}
		"filters":
			var ok := _fresh(_item(bike_id, "air_filter"), 0.2, 0.2) and _fresh(_item(bike_id, "oil_filter"), 0.2, 0.2)
			return {"done": ok, "have": "clean" if ok else "clogged"}
		"plugs":
			var ok := _fresh(_item(bike_id, "spark_plugs"), 0.2)
			return {"done": ok, "have": "good" if ok else "worn"}
		"brake_fluid":
			var ok := _fluid_ok(_item(bike_id, "front_master"), 0.2, 0.8) and _fluid_ok(_item(bike_id, "rear_master"), 0.2, 0.8)
			return {"done": ok, "have": "fresh" if ok else "old or low"}
		"wash":
			var d := Shed._bike_dirt(bike_id)
			return {"done": d <= 0.15, "have": "%d%% dirty" % roundi(d * 100.0)}
		"front_tyre", "rear_tyre", "chain_kit", "discs", "fork":
			# Renewed: every part the task covers as good as new (or near enough).
			var ok := true
			var worst := 0.0
			for slot in TASK_PARTS[task]:
				var it := _item(bike_id, slot)
				ok = ok and _fresh(it, 0.2)
				worst = maxf(worst, float(it.get("wear", 1.0)))
			return {"done": ok, "have": "good" if ok else "%d%% worn" % roundi(worst * 100.0)}
	return {"done": false, "have": ""}


## The parts on a bike now ("none" where a slot is empty).
static func current_parts(bike_id: int) -> Dictionary:
	var parts := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		parts[slot] = str(Shed.items[id]["part"]) if id != 0 and Shed.items.has(id) else "none"
	return parts


## A bike's average part condition, 0..1, over every part on it.
static func bike_health(bike_id: int) -> float:
	var total := 0.0
	var n := 0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or not Shed.items.has(id):
			continue
		total += BikeBuild.part_health(Shed.condition_of(Shed.items[id]))
		n += 1
	return total / n if n > 0 else 0.0


## Every goal of a job with how it stands: [{text, done, have}].
static func evaluate(job: Dictionary) -> Array:
	var rows := []
	for g in job.get("goals", []):
		var e := eval_goal(job, g)
		rows.append({"text": goal_text(g), "done": bool(e["done"]), "have": str(e["have"])})
	return rows


## How far along a job is, 0..1.
static func progress(job: Dictionary) -> float:
	var rows := evaluate(job)
	if rows.is_empty():
		return 0.0
	return float(rows.filter(func(r): return r["done"]).size()) / rows.size()


## What's been spent on parts for the job: the price of each part on the bike now that it
## didn't come in with.
static func spent(job: Dictionary) -> int:
	var bike_id := int(job.get("bike", 0))
	if not Shed.bikes.has(bike_id):
		return 0
	var start: Dictionary = job.get("start_parts", {})
	var now := current_parts(bike_id)
	var total := 0
	for slot in now:
		if str(now[slot]) != "none" and str(now[slot]) != str(start.get(slot, "none")):
			total += price(str(now[slot]))
	return total


## Whether an MOT job's test goal is met (`rows` from evaluate).
static func _mot_passed(job: Dictionary, rows: Array) -> bool:
	var goals: Array = job.get("goals", [])
	for i in mini(goals.size(), rows.size()):
		if str(goals[i].get("t", "")) == "mot":
			return bool(rows[i]["done"])
	return false


## What handing the job back now would pay: {labour, parts, tip, over, late, sat, total, rep, note}.
static func payout(job: Dictionary, spend_override := -1) -> Dictionary:
	var rows := evaluate(job)
	var met := rows.filter(func(r): return r["done"]).size()
	var sat := float(met) / maxf(1.0, rows.size())
	var fee := int(job.get("pay", 0))
	var late := maxi(0, ceili((clock() - float(job.get("due", 0.0))) / DAY))
	var labour := float(fee) * (1.0 if sat >= 1.0 else 0.35 + 0.65 * sat)
	var note := "Every goal met." if sat >= 1.0 else "%d of %d goals met." % [met, rows.size()]
	if str(job.get("kind", "")) == "mot" and not _mot_passed(job, rows):
		labour = fee * 0.25
		note = "No MOT pass: they only pay for the test."
	labour *= maxf(0.5, 1.0 - 0.15 * late)
	var spend := spent(job) if spend_override < 0 else spend_override
	var budget := int(job.get("budget", 0))
	var parts := mini(spend, budget)
	var over := maxi(0, spend - budget) if budget > 0 else 0
	labour = maxf(0.0, labour - over)
	var tip := 0
	if sat >= 1.0 and late == 0:
		var shine := bike_health(int(job.get("bike", 0)))
		tip = roundi(fee * (0.05 + 0.2 * clampf((shine - 0.6) / 0.4, 0.0, 1.0)))
	var rep := int(REP_GAIN.get(str(job.get("kind", "")), 1)) if sat >= 1.0 else (0 if sat >= 0.5 else -1)
	if late > 0:
		rep -= 1
		note += " %d day%s late." % [late, "" if late == 1 else "s"]
	if over > 0:
		note += " %s over budget." % money(over)
	return {"labour": roundi(labour), "parts": parts, "tip": tip, "over": over, "late": late, "sat": sat,
		"total": roundi(labour) + parts + tip, "rep": rep, "note": note, "spent": spend}


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a contract action, or "". Actions: contract_accept {customer},
## contract_decline {customer}, contract_mot_test {job}, contract_hand_in {job},
## contract_spawn {kind} (the Debug tab), contract_rep {value} (the Debug tab).
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	match a:
		"contract_accept", "contract_decline":
			var cid := int(action.get("customer", 0))
			if not customers().has(cid):
				return "They've gone."
			if a == "contract_accept":
				if active_count() >= MAX_ACTIVE:
					return "The shed has as many jobs as it can take. Finish one first."
				if not rides_in(customers()[cid]) and Shed.free_bay(Workshop.bay_count()) < 0:
					return "Every bay is full. Clear one for the customer's bike first."
		"contract_mot_test", "contract_hand_in":
			var job: Dictionary = jobs().get(int(action.get("job", 0)), {})
			if job.is_empty():
				return "That job's finished."
			var bike_id := int(job.get("bike", 0))
			if not Shed.bikes.has(bike_id):
				return "The bike has gone."
			var bike: Dictionary = Shed.bikes[bike_id]
			if int(bike.get("rider", 0)) != 0 or int(bike.get("pusher", 0)) != 0:
				return "Park it first: someone is riding or wheeling it."
			if a == "contract_mot_test" and str(job.get("kind", "")) != "mot":
				return "Only an MOT job gets tested."
			if a == "contract_hand_in":
				if not Shed.is_complete(bike_id):
					return "It isn't finished: every part has to be on and bolted up."
				if not near_handback(bike_id):
					return "Leave it in the car park outside the sales office to hand it back."
		"contract_spawn", "contract_rep":
			# Debug tab helpers, for the host.
			if peer != Shed.me():
				return "Only the host can do that."
			if a == "contract_spawn" and customers().size() >= MAX_WAITING + 2:
				return "There's a queue already."

		_:
			return "There's nothing like that to do."
	return ""


static func active_count() -> int:
	return jobs().values().filter(func(j): return str(j.get("state", "")) == "active").size()


## Whether a customer came on their own bike (parked in the car park), so taking the job on
## leaves it there rather than delivering it to a bay. Customers from sheds saved before they
## rode in, and the exclusive customer, didn't.
static func rides_in(cust: Dictionary) -> bool:
	return int(cust.get("park", -1)) >= 0 and str(cust.get("offer", {}).get("kind", "")) != "bespoke"


## The job a bike is in the shed for, or {}.
static func job_for_bike(bike_id: int) -> Dictionary:
	for id in jobs():
		if int(jobs()[id].get("bike", 0)) == bike_id:
			return jobs()[id]
	return {}


## Whether a customer who was at reception took their job on: they leave on foot, and their
## bike stays with the shed.
static func took_on(customer_id: int) -> bool:
	for id in jobs():
		if int(jobs()[id].get("cid", 0)) == customer_id:
			return true
	return false


## Whether a bike stands where it can be handed back: in the customer car park outside the
## sales office, where the customer comes out to collect it.
static func near_handback(bike_id: int) -> bool:
	var xf = Shed.bikes[bike_id].get("xf")
	if not (xf is Transform3D):
		return false
	return in_car_park((xf as Transform3D).origin)


## Does a contract action (already checked) and returns what to tell the player.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var text := ""
	match a:
		"contract_accept":
			text = _accept(peer, int(action["customer"]))
		"contract_decline":
			var who := str(customers()[int(action["customer"])]["name"])
			customers().erase(int(action["customer"]))
			text = "%s nods and heads off." % who
		"contract_mot_test":
			text = _mot_test(peer, jobs()[int(action["job"])])
		"contract_hand_in":
			text = _hand_in(jobs()[int(action["job"])])
		"contract_spawn":
			var cid := spawn(str(action.get("kind", "")))
			text = "%s is on the way to reception." % customers()[cid]["name"]
		"contract_rep":
			_st()["reputation"] = clampi(int(action.get("value", 0)), 0, 999)
			text = "Reputation set to %d" % reputation()
	Shed._mark_dirty()
	return text


## A player has done something to a bike: if it's a contract bike they count as having worked
## on it, and an MOT tested before needs testing again.
static func note_action(peer: int, action: Dictionary) -> void:
	var a := str(action.get("a", ""))
	if a.begins_with("contract_") or a in NOT_WORK:
		return
	var bike_id := int(action.get("bike", 0))
	if bike_id == 0 and int(action.get("engine", 0)) != 0:
		bike_id = Shed._bike_of(int(action["engine"]))
	if bike_id == 0 and int(action.get("item", 0)) != 0:
		bike_id = Shed._bike_of(int(action["item"]))
	if bike_id == 0:
		return
	for id in jobs():
		var job: Dictionary = jobs()[id]
		if int(job.get("bike", 0)) != bike_id:
			continue
		var w: Dictionary = job.get("workers", {})
		w[peer] = int(w.get(peer, 0)) + 1
		job["workers"] = w
		if job.get("mot") is Dictionary and job["mot"].get("tested", false):
			job["mot"]["stale"] = true


static func _accept(_peer: int, cid: int) -> String:
	var cust: Dictionary = customers()[cid]
	var offer: Dictionary = cust["offer"]
	var kind := str(offer["kind"])
	var parked := rides_in(cust)
	var bay := Shed.free_bay(Workshop.bay_count())
	var bike_id := 0
	if kind == "bespoke":
		var frame := Shed._new_item(str(offer["parts"].get("frame", "steel_cradle")), 0.0, 0.0, 0.0)
		bike_id = Shed._empty_bike(frame, bay)
	else:
		var age: float = {"maint": 0.15, "mot": 0.28, "mod": 0.12}.get(kind, 0.2)
		var paint = Shed.PAINTS[int(offer["paint"]) % Shed.PAINTS.size()] if offer.has("paint") else null
		bike_id = Shed._new_bike(offer["parts"], maxi(bay, 0), str(offer["bike_name"]), age, paint)
		if parked:
			# Left in the car park bay they rode into, on its stand, keys with the crew.
			Shed.bikes[bike_id]["bay"] = -1
			Shed.bikes[bike_id]["xf"] = park_xf(int(cust["park"]))
			Shed.bikes[bike_id]["stand"] = Shed._rest_stand(bike_id)
		prepare_bike(bike_id, kind, offer.get("goals", []), Shed._rng, int(offer.get("faults", -1)))
	Shed.bikes[bike_id]["name"] = str(offer["bike_name"])
	Shed.bikes[bike_id]["contract"] = true
	var s := _st()
	var jid := int(s["next"])
	s["next"] = jid + 1
	var job := {"id": jid, "cid": cid, "kind": kind, "title": str(offer["title"]), "customer": str(cust["name"]), "look": cust["look"],
		"bike": bike_id, "goals": offer["goals"].duplicate(true), "pay": int(offer["pay"]), "budget": int(offer.get("budget", 0)),
		"accepted": clock(), "due": clock() + float(offer["days"]) * DAY, "start_parts": current_parts(bike_id),
		"workers": {}, "state": "active"}
	if kind == "mot":
		job["mot"] = {"tested": false, "stale": false, "fails": 0, "sheet": [], "tests": 0}
	jobs()[jid] = job
	customers().erase(cid)
	if parked:
		return ("Job taken on: %s, due in %d days. They've left it in the car park with the keys: ride it or wheel it (F) into a bay. "
			+ "When it's done, leave it back in the car park and hand it back.") % [offer["bike_name"], int(offer["days"])]
	var where := "a bare %s on bay %d" % [PartsDB.part_name(str(offer["parts"]["frame"])).to_lower(), bay + 1] if kind == "bespoke" \
		else "bay %d" % (bay + 1)
	return "Job taken on: %s. It's on %s, due in %d days. When it's done, leave it in the car park outside the sales office and hand it back." % [
		offer["bike_name"], where, int(offer["days"])]


## A customer's bike brought in for a job: generally looked after, but with whatever the job
## is about in a bad way (a service due, MOT faults to find).
static func prepare_bike(bike_id: int, kind: String, goals: Array, rng: RandomNumberGenerator, faults := -1) -> void:
	var set_part := func(slot: String, key: String, v: float) -> void:
		var id := Shed.item_on(bike_id, slot)
		if id != 0:
			Shed.items[id][key] = v
	# Start from a bike that's been kept on the road: fluids in and the chain about right.
	var engine := Shed.item_on(bike_id, "engine")
	for slot in ["engine", "front_master", "rear_master", "tank"]:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items[id].has("fluid"):
			var f: Dictionary = Shed.items[id]["fluid"]
			var cap := PartsDB.fluid_capacity(str(Shed.items[id]["part"]))
			f["litres"] = snappedf(cap * (0.4 if slot == "tank" else 0.9), 0.01)
			f["age"] = 0.3 if slot != "tank" else 0.1
			if str(f.get("type", "")) == "":
				f["type"] = {"engine": "semi_10w40", "tank": "unleaded_95"}.get(slot, "dot4")
	var chain := Shed.item_on(bike_id, "chain")
	if chain != 0:
		Shed.items[chain]["slack"] = Shed.CHAIN_SLACK_SET + rng.randf_range(-4.0, 6.0)
		Shed.items[chain]["lube"] = 0.65
	# Whatever the customer asked to have done needs doing (a service, or jobs while it's in for its MOT).
	for g in goals:
		if str(g.get("t", "")) != "task":
			continue
		match str(g.get("task", "")):
			"oil":
				if engine != 0:
					Shed.items[engine]["fluid"]["age"] = 0.9
					Shed.items[engine]["fluid"]["litres"] = snappedf(PartsDB.fluid_capacity(str(Shed.items[engine]["part"])) * 0.55, 0.01)
			"chain":
				if chain != 0:
					Shed.items[chain]["slack"] = 58.0
					Shed.items[chain]["lube"] = 0.05
			"pads":
				set_part.call("front_pads", "wear", 0.85)
				set_part.call("rear_pads", "wear", 0.8)
			"filters":
				for slot in ["air_filter", "oil_filter"]:
					set_part.call(slot, "wear", 0.7)
					set_part.call(slot, "dirt", 0.85)
			"plugs":
				set_part.call("spark_plugs", "wear", 0.8)
			"brake_fluid":
				for slot in ["front_master", "rear_master"]:
					var id := Shed.item_on(bike_id, slot)
					if id != 0:
						Shed.items[id]["fluid"]["age"] = 0.9
						Shed.items[id]["fluid"]["litres"] = snappedf(PartsDB.fluid_capacity(str(Shed.items[id]["part"])) * 0.45, 0.01)
			"wash":
				for slot in PartsDB.SLOTS:
					var id := Shed.item_on(bike_id, slot)
					if id != 0:
						Shed.items[id]["dirt"] = clampf(float(Shed.items[id]["dirt"]) + 0.55, 0.0, 1.0)
			"front_tyre", "rear_tyre":
				set_part.call(str(g["task"]), "wear", rng.randf_range(0.8, 0.9))
			"chain_kit":
				set_part.call("chain", "wear", 0.8)
				set_part.call("final_drive", "wear", 0.75)
			"discs":
				set_part.call("front_disc", "wear", 0.8)
			"fork":
				set_part.call("fork", "wear", 0.7)
	match kind:
		"mot":
			# A few faults for the test to find.
			var fault_list := ["front_tyre", "rear_tyre", "pads", "disc", "mirrors", "horn", "headlight", "chain", "fork", "frame",
				"exhaust", "oil", "shock"]
			_shuffle(fault_list, rng)
			var count := clampi(faults, 1, 8) if faults > 0 else rng.randi_range(3, 6)
			for f in fault_list.slice(0, count):
				match str(f):
					"front_tyre", "rear_tyre":
						set_part.call(str(f), "wear", rng.randf_range(0.84, 0.95))
					"pads":
						set_part.call("front_pads" if rng.randf() < 0.5 else "rear_pads", "wear", 0.9)
					"disc":
						set_part.call("front_disc", "wear", 0.8)
					"mirrors":
						var m := Shed.item_on(bike_id, "mirrors")
						if m != 0:
							Shed._erase_item(m)
							Shed.bikes[bike_id]["slots"]["mirrors"] = 0
							Shed.bikes[bike_id]["bolted"]["mirrors"] = false
					"horn", "headlight":
						set_part.call(str(f), "wear", 0.92)
					"chain":
						if chain != 0:
							Shed.items[chain]["slack"] = 62.0
							Shed.items[chain]["wear"] = 0.78
					"fork":
						set_part.call("fork", "wear", 0.75)
					"shock":
						set_part.call("shock", "wear", 0.78)
					"frame":
						set_part.call("frame", "rust", 0.62)
					"exhaust":
						set_part.call("exhaust", "rust", 0.8)
					"oil":
						if engine != 0:
							Shed.items[engine]["fluid"]["litres"] = snappedf(PartsDB.fluid_capacity(str(Shed.items[engine]["part"])) * 0.2, 0.01)
	refresh_delivered(bike_id)


## After changing a bike's parts by hand: what it was delivered as, for the bay screen.
static func refresh_delivered(bike_id: int) -> void:
	var bike: Dictionary = Shed.bikes[bike_id]
	var cond := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0:
			cond[slot] = Shed.condition_of(Shed.items[id])
	bike["original_cond"] = cond
	bike["delivered"] = BikeBuild.new(bike["original"], cond).summary()


static func _mot_test(peer: int, job: Dictionary) -> String:
	var sheet := MotTest.inspect(int(job["bike"]))
	var fails := sheet.filter(func(r): return not r["pass"]).size()
	var m: Dictionary = job.get("mot", {})
	m["tested"] = true
	m["stale"] = false
	m["fails"] = fails
	m["sheet"] = sheet
	m["tests"] = int(m.get("tests", 0)) + 1
	m["at"] = clock()
	job["mot"] = m
	Shed._xp(peer, "mot_test", 1.0)
	if fails == 0:
		return "MOT test: PASS. Every check is fine. Hand it back for the certificate."
	return "MOT test: FAIL on %d item%s. See the sheet, fix them and test it again." % [fails, "" if fails == 1 else "s"]


static func _hand_in(job: Dictionary) -> String:
	var pay := payout(job)
	var cert := {}
	if str(job.get("kind", "")) == "mot" and float(pay["sat"]) >= 1.0:
		_st()["certs"] = int(_st()["certs"]) + 1
		var bike: Dictionary = Shed.bikes[int(job["bike"])]
		cert = {"number": "TS-%05d" % (1000 + int(_st()["certs"])), "bike": str(bike["name"]), "owner": str(job["customer"]),
			"day": day_number(), "expires": day_number() + 365}
	_pay(job, pay)
	_ride_away(job)
	_remove_bike(int(job["bike"]))
	_finish(job, {"paid": int(pay["total"]), "sat": float(pay["sat"]), "late": int(pay["late"]), "rep": int(pay["rep"]),
		"note": str(pay["note"]), "cert": cert})
	var text := "%s collected %s and paid %s" % [job["customer"], job["title"].get_slice(": ", 1), money(int(pay["total"]))]
	if int(pay["tip"]) > 0:
		text += " (with a %s tip)" % money(int(pay["tip"]))
	if not cert.is_empty():
		text += ". MOT certificate %s issued" % cert["number"]
	return text + "."


## Pays out a finished job: the parts back and half the labour and tip to the garage, the
## other half to the crew who worked on it (in proportion to how much each did), and XP.
static func _pay(job: Dictionary, pay: Dictionary) -> void:
	var labour := int(pay["labour"]) + int(pay["tip"])
	var workers: Dictionary = job.get("workers", {})
	var crew_ids: Array = workers.keys().filter(func(p): return Shed.crew.has(int(p)))
	var can_pay := Shed.has_method("pay_worker") and not crew_ids.is_empty()
	var to_crew := roundi(labour * WORKER_SHARE) if can_pay else 0
	credit_garage(int(pay["parts"]) + labour - to_crew, "Contract: %s" % job["title"])
	if can_pay and to_crew > 0:
		var total_work := 0
		for p in crew_ids:
			total_work += int(workers[p])
		var left := to_crew
		for i in crew_ids.size():
			var p := int(crew_ids[i])
			var share := left if i == crew_ids.size() - 1 else roundi(to_crew * float(workers[p]) / maxf(1.0, total_work))
			left -= share
			if share > 0:
				Shed.call("pay_worker", p, share, "Contract: %s" % job["title"])
	var key := str(XP_KEYS.get(str(job["kind"]), "contract_maint"))
	var mult := 0.4 + 0.6 * float(pay["sat"])
	if crew_ids.is_empty():
		crew_ids = [Shed.me()]
	for p in crew_ids:
		Shed._xp(int(p), key, mult, "job:%d" % int(job["id"]))
	_st()["earned"] = int(_st()["earned"]) + int(pay["total"])


## Income to the garage's account (money-core's credit_garage when it's there).
static func credit_garage(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	if Shed.has_method("credit_garage"):
		Shed.call("credit_garage", amount, reason)
	else:
		Shed.garage_money = clampi(Shed.garage_money + amount, 0, Shed.MAX_GARAGE_MONEY)


## The customer comes for their bike: kept a while in "leaving" so everyone sees them walk up
## to it, get on and ride it off from where it stands (see ContractsView).
static func _ride_away(job: Dictionary) -> void:
	var bike_id := int(job["bike"])
	var bike: Dictionary = Shed.bikes[bike_id]
	var leaving: Array = _st()["leaving"]
	leaving.append({"id": int(job["id"]), "name": str(job.get("customer", "")), "look": job.get("look", {}),
		"parts": current_parts(bike_id), "paint": bike["paint"], "cond": Shed.build_of(bike_id).condition.duplicate(true),
		"xf": bike["xf"], "at": clock()})
	while leaving.size() > MAX_LEAVING:
		leaving.pop_front()


## The customer rides their bike away: it and every part on it leave the shed.
static func _remove_bike(bike_id: int) -> void:
	var gone := []
	for id in Shed.items:
		if str(Shed.items[id]["at"]) == "bike" and int(Shed.items[id]["ref"]) == bike_id:
			gone.append(id)
	for id in gone:
		if Shed.items.has(id):
			Shed._erase_item(id)
	Shed.bikes.erase(bike_id)


## A job leaves the list: into the done list, with the reputation it earned or lost.
static func _finish(job: Dictionary, result: Dictionary) -> void:
	var s := _st()
	s["reputation"] = maxi(0, int(s["reputation"]) + int(result.get("rep", 0)))
	var done: Array = s["done"]
	var entry := {"title": str(job.get("title", "")), "kind": str(job.get("kind", "")), "customer": str(job.get("customer", "")),
		"day": day_number()}
	entry.merge(result, true)
	done.push_front(entry)
	while done.size() > MAX_DONE:
		done.pop_back()
	jobs().erase(int(job["id"]))
	if Shed.bikes.has(int(job.get("bike", 0))):
		Shed.bikes[int(job["bike"])].erase("contract")


# ---------------------------------------------------------------------------- screens

## The Contracts TV channel's page (see TvChannels.contracts_data).
static func tv_data() -> Dictionary:
	var offered := []
	for id in customers():
		var o: Dictionary = customers()[id]["offer"]
		offered.append({"title": "%s %s" % [KIND_NAMES[o["kind"]], money(int(o["pay"]))], "sub": str(customers()[id]["name"])})
	var active := []
	for id in jobs():
		var j: Dictionary = jobs()[id]
		active.append({"title": str(j["title"]).get_slice(": ", 1), "sub": "%s · %s" % [KIND_NAMES[j["kind"]], due_text(float(j["due"]))],
			"progress": progress(j), "late": clock() > float(j["due"])})
	var done := []
	for d in _st()["done"]:
		done.append({"title": str(d.get("title", "")).get_slice(": ", 1), "sub": "%s · paid %s" % [KIND_NAMES.get(d.get("kind", ""), ""),
			money(int(d.get("paid", 0)))]})
	return {"placeholder": false, "offered": offered, "active": active, "done": done, "reputation": reputation(),
		"day": day_number()}


## What a contract bike's bay screen shows: the job's checklist, ticked off as the work gets
## done (with an MOT's fails still to fix), the deadline, what's been spent on parts against the
## budget, and what handing it back now would pay and make once the parts are paid for.
static func screen_data(job: Dictionary) -> Dictionary:
	var rows := evaluate(job)
	var met := rows.filter(func(r): return r["done"]).size()
	var fixes := []
	var mot_line := ""
	var m: Dictionary = job["mot"] if job.get("mot") is Dictionary else {}
	if str(job.get("kind", "")) == "mot":
		if not m.get("tested", false):
			mot_line = "Not tested yet: run the MOT test from Esc, Contracts."
		else:
			var f: Array = MotTest.fails(m.get("sheet", []))
			mot_line = "MOT test %d: %s%s" % [int(m.get("tests", 1)), "PASS" if f.is_empty() else "FAIL on %d" % f.size(),
				", worked on since: test it again" if m.get("stale", false) else ""]
			for r in f:
				fixes.append({"text": str(r.get("name", "")), "fix": str(r.get("fix", ""))})
	var pay := payout(job)
	var spend := int(pay["spent"])
	var why := Shed.check(Shed.me(), {"a": "contract_hand_in", "job": int(job.get("id", 0))})
	return {"title": str(job.get("title", "")).get_slice(": ", 1), "kind": str(KIND_NAMES.get(str(job.get("kind", "")), "")),
		"customer": str(job.get("customer", "")), "rows": rows, "met": met, "mot": mot_line, "fixes": fixes,
		"due": due_text(float(job.get("due", 0.0))), "due_day": day_number(float(job.get("due", 0.0))),
		"late": clock() > float(job.get("due", 0.0)), "fee": int(job.get("pay", 0)), "budget": int(job.get("budget", 0)),
		"spent": spend, "over": int(pay["over"]), "payout": int(pay["total"]), "profit": int(pay["total"]) - spend,
		"note": str(pay["note"]), "ready": why == "", "why": why}
