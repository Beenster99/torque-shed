class_name Recovery
extends RefCounted
## Recovery jobs: once the garage has bought the recovery rig (a pickup and a motorbike
## trailer, a garage upgrade from the parts computer at character level LEVEL), the phone rings
## with jobs to fetch bikes from round the map:
##   barn     a barn find: a bike left for years beside a farm's barn or under a tarp behind a
##            village house. Rusty, filthy, flat tyres, old fluids, often with its brakes seized
##            solid so it won't roll.
##   crash    a crash rescue: a bike gone off the road onto the verge, lying on its side with
##            parts smashed; the rider's insurer wants it recovered. A buckled wheel won't roll.
## Take one on (the Recovery list: the clipboard in the truck, or Esc, Recovery) and a marker
## and the HUD show where it is. Drive there, lower the ramp, stand the bike up and wheel it to
## the foot of the ramp, and winch it up (F at the winch post). One that won't roll goes on the
## dolly tray off the trailer's side rail first and is pushed up on that. Ratchet the straps
## tight at the anchors (the front pair hold it; a loose bike rolls into the chock and goes over
## the side under hard braking, or tips off in a hard corner). Drive it back to the yard and let
## it down the ramp: the call-out fee is paid. Then assess it (the part-by-part condition, what
## it would cost to put right and what it's worth fixed) and choose:
##   buy       pay the owner their price and it's the garage's own project bike;
##   salvage   pay less for it as spares: every part comes off into the delivery area and the
##             frame goes for scrap;
##   insurer   do the repair for the insurer: put the damaged parts right (to INSURER_HEALTH or
##             better), every part on and bolted up, then they collect it and pay.
##
## Host-authoritative shed state in Shed.recovery (saved with the shed), changed through
## Shed.request({"a": "recovery_..."}) which hands to check()/apply(). The truck itself is driven
## on the driver's own machine (RecoveryView) and its place sent to the host now and then.

const LEVEL := 8                       # character level the recovery rig can be bought at
const UPGRADE := "recovery_rig"
const KIND_NAMES := {"barn": "Barn find", "crash": "Crash rescue"}
const FIRST_OFFER := 0.5               # game hours after the rig is bought
const OFFER_HOURS := Vector2(3.0, 6.0)
const MAX_OFFERS := 2
const OFFER_LIFE := 8.0
const MAX_JOBS := 2
const MAX_DONE := 10
## Where the rig parks in the yard (west of the shed's front), the truck facing west.
const PARK := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-13.0, 0.0, 78.5))
const WINCH_SPEED := 0.45              # m/s, the winch pulling a bike up the ramp
const PUSH_SPEED := 0.35               # pushing one up on the dolly is slower
const REACH := 3.5                     # m: how near the ramp foot a bike has to stand to be winched
const DOLLY_REACH := 3.0
const DOLLY_CARRY := 30.0              # m: how far from the trailer you'll carry the dolly tray
const DOLLY_LIFT := 0.13               # how far the dolly raises a bike
## A part the insurer wants put right has to come back to at least this health.
const INSURER_HEALTH := 0.75
## Parts a crash damages, and the strap anchors (front left, front right, rear left, rear right).
const CRASH_PARTS: Array[String] = ["fork", "front_wheel", "handlebars", "mirrors", "front_mudguard", "headlight", "tank",
	"exhaust", "fairing", "indicators", "front_disc", "rearsets", "side_panels", "tail"]
const STRAPS := 4
const STRAP_NAMES := ["front left", "front right", "back left", "back right"]
const INSURERS := ["Hartley Mutual", "Northern Shield", "Brookside Insurance", "Ace Motorcycle Cover", "Kestrel Direct"]
const BARN_LINES := ["Grandad's old bike's been in the barn since the eighties. Come and take it away, and make me an offer.",
	"Found it under a tarp clearing out the yard. No idea if it runs. Yours if the price is right.",
	"It's been behind the barn longer than I've had the farm. Get it gone and we'll talk money.",
	"My late husband's. I can't bear to look at it any more, but I'd like it to go to someone who'll care."]
const CRASH_LINES := ["Our customer came off on the bend and the bike's still in the verge. Please recover it to your yard.",
	"Rider's fine, bike isn't. It's on its side by the road. We'll want a repair quote.",
	"Low-side on a wet road. Bring it in, assess it and tell us whether it's worth fixing."]


# ---------------------------------------------------------------------------- state

static func empty() -> Dictionary:
	return {"car": {"xf": PARK, "trailer_xf": trailer_park(PARK), "driver": 0, "ramp": false,
		"dolly": {"at": "trailer", "xf": Transform3D(), "bike": 0}, "winch": 0, "winch_dir": 1},
		"loads": {}, "offers": {}, "jobs": {}, "done": [], "next": 1, "next_at": -1.0, "earned": 0}


## Saved or synced recovery state made safe to use: anything missing gets its default.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
	var car: Dictionary = out["car"]
	var def: Dictionary = empty()["car"]
	for key in def:
		if not car.has(key) or typeof(car[key]) != typeof(def[key]):
			car[key] = def[key]
	return out


## A save being opened: nobody is driving, and anything mid-winch finishes where it was going.
static func after_load() -> void:
	var c := car()
	c["driver"] = 0
	var w := int(c["winch"])
	if w != 0 and loads().has(w):
		if int(c["winch_dir"]) > 0:
			loads()[w]["s"] = Trailer.s_end()
		else:
			_unloaded(w)
	c["winch"] = 0
	for id in loads().keys():
		if not Shed.bikes.has(int(id)):
			loads().erase(id)


## Tells the whole crew.
static func _tell_all(text: String, ok: bool) -> void:
	for p in Shed.crew:
		Shed._tell(int(p), text, ok)


static func _st() -> Dictionary:
	if not (Shed.recovery is Dictionary) or not Shed.recovery.has("car"):
		Shed.recovery = empty()
	return Shed.recovery


static func car() -> Dictionary:
	return _st()["car"]


static func loads() -> Dictionary:
	return _st()["loads"]


static func offers() -> Dictionary:
	return _st()["offers"]


static func jobs() -> Dictionary:
	return _st()["jobs"]


static func owned() -> bool:
	return Shed.upgrades.has(UPGRADE)


static func driver() -> int:
	return int(car()["driver"]) if owned() else 0


static func dolly() -> Dictionary:
	return car()["dolly"]


## Where the trailer stands hitched behind the truck at `car_xf`.
static func trailer_park(car_xf: Transform3D) -> Transform3D:
	return Transform3D(car_xf.basis, car_xf * Car.HITCH - car_xf.basis * Trailer.COUPLER)


static func trailer_xf() -> Transform3D:
	return car()["trailer_xf"]


## The job a bike is out for, or {}.
static func job_of(bike_id: int) -> Dictionary:
	var jid := int(Shed.bikes.get(bike_id, {}).get("recovery", 0))
	return jobs().get(jid, {})


static func is_loaded(bike_id: int) -> bool:
	return loads().has(bike_id)


## Fully up the ramp and on the bed (not on its way up or down).
static func on_bed(bike_id: int) -> bool:
	return loads().has(bike_id) and float(loads()[bike_id]["s"]) >= Trailer.s_end() - 0.01


## The front pair of straps are tight: it isn't going anywhere.
static func secure(bike_id: int) -> bool:
	var st: Array = loads().get(bike_id, {}).get("straps", [])
	return st.size() >= 2 and bool(st[0]) and bool(st[1])


static func straps_on(bike_id: int) -> int:
	var n := 0
	for s in loads().get(bike_id, {}).get("straps", []):
		if s:
			n += 1
	return n


## A recovery bike still out on its site that won't roll (seized brakes, a buckled wheel),
## unless it's on the dolly.
static func seized(bike_id: int) -> bool:
	var job := job_of(bike_id)
	if job.is_empty() or str(job.get("state", "")) != "collect" or bool(job.get("rolls", true)):
		return false
	return int(dolly()["bike"]) != bike_id


static func on_dolly(bike_id: int) -> bool:
	return str(dolly()["at"]) in ["bike", "load"] and int(dolly()["bike"]) == bike_id


static func clock() -> float:
	return Contracts.clock()


static func money(v: int) -> String:
	return TvChannels.money_text(v)


# ---------------------------------------------------------------------------- time passing

## Host: offers come and go once the rig is owned, the winch turns, and recovered bikes left in
## the yard count as delivered.
static func process(delta: float) -> void:
	if not owned():
		return
	var s := _st()
	var now := clock()
	var changed := false
	if float(s["next_at"]) < 0.0:
		s["next_at"] = now + FIRST_OFFER
	for id in offers().keys():
		if now >= float(offers()[id].get("expires", 0.0)):
			offers().erase(id)
			changed = true
	if now >= float(s["next_at"]):
		s["next_at"] = now + Shed._rng.randf_range(OFFER_HOURS.x, OFFER_HOURS.y)
		if offers().size() < MAX_OFFERS:
			spawn()
			changed = true
	changed = _turn_winch(delta) or changed
	for jid in jobs().keys():
		var job: Dictionary = jobs()[jid]
		var bike_id := int(job["bike"])
		if not Shed.bikes.has(bike_id):
			jobs().erase(jid)
			changed = true
			continue
		if str(job["state"]) == "collect" and _in_yard(bike_id):
			_delivered(job)
			changed = true
	if changed:
		Shed._mark_dirty()


## A bike off the trailer standing in the yard (or the shed).
static func _in_yard(bike_id: int) -> bool:
	if loads().has(bike_id):
		return false
	var b: Dictionary = Shed.bikes[bike_id]
	if int(b.get("rider", 0)) != 0 or int(b.get("pusher", 0)) != 0:
		return false
	return Shed.in_work_area((b["xf"] as Transform3D).origin)


static func _turn_winch(delta: float) -> bool:
	var c := car()
	var id := int(c["winch"])
	if id == 0:
		return false
	if not loads().has(id) or not Shed.bikes.has(id):
		c["winch"] = 0
		return true
	var l: Dictionary = loads()[id]
	var rate := PUSH_SPEED if bool(l.get("dolly", false)) and not bool(job_of(id).get("rolls", true)) else WINCH_SPEED
	l["s"] = clampf(float(l["s"]) + rate * delta * float(c["winch_dir"]), 0.0, Trailer.s_end())
	Shed.bikes[id]["xf"] = load_world(id)
	if int(c["winch_dir"]) > 0 and float(l["s"]) >= Trailer.s_end():
		c["winch"] = 0
		_tell_all("%s is on the trailer. Ratchet the straps tight at the yellow anchors before you drive off." % Shed.bikes[id]["name"], true)
	elif int(c["winch_dir"]) < 0 and float(l["s"]) <= 0.0:
		c["winch"] = 0
		_unloaded(id)
	return true


## Where a bike on the trailer is in the world (the parked trailer's place).
static func load_world(bike_id: int) -> Transform3D:
	var l: Dictionary = loads()[bike_id]
	var xf := trailer_xf() * Trailer.load_transform(int(l["slot"]), float(l["s"]), float(l.get("z", 0.0)),
		bool(l.get("tipped", false)), _wheelbase(bike_id))
	return xf


static func _wheelbase(bike_id: int) -> float:
	return float(Shed.bikes.get(bike_id, {}).get("wb", 1.4))


## Down off the ramp: it stands on the ground behind the trailer (on the dolly if it went up on it).
static func _unloaded(bike_id: int) -> void:
	var l: Dictionary = loads()[bike_id]
	loads().erase(bike_id)
	var xf := trailer_xf() * Trailer.load_transform(int(l["slot"]), 0.0, 0.0, false, _wheelbase(bike_id))
	Shed.bikes[bike_id]["xf"] = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
	if bool(l.get("dolly", false)) and int(dolly()["bike"]) == bike_id:
		dolly()["at"] = "bike"
		Shed.bikes[bike_id]["stand"] = ""
	else:
		Shed.bikes[bike_id]["stand"] = Shed._rest_stand(bike_id)
	var job := job_of(bike_id)
	if not job.is_empty() and str(job["state"]) == "collect" and _in_yard(bike_id):
		_delivered(job)


# ---------------------------------------------------------------------------- offers

## A new recovery job on the phone (host only). `kind` forces barn or crash. Returns its id.
static func spawn(kind := "") -> int:
	var rng: RandomNumberGenerator = Shed._rng
	if not KIND_NAMES.has(kind):
		kind = "barn" if rng.randf() < 0.55 else "crash"
	var s := _st()
	var id := int(s["next"])
	s["next"] = id + 1
	var place := barn_spot(rng) if kind == "barn" else crash_spot(rng)
	var parts := Contracts.random_parts(rng, true)
	var person := "%s %s" % [Contracts.FIRST_NAMES[rng.randi() % Contracts.FIRST_NAMES.size()],
		Contracts.LAST_NAMES[rng.randi() % Contracts.LAST_NAMES.size()]]
	var insurer: String = INSURERS[rng.randi() % INSURERS.size()]
	var xf: Transform3D = place["xf"]
	var km := Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(PARK.origin.x, PARK.origin.z)) / 1000.0
	var model := Sales.model_text(parts)
	var o := {"id": id, "kind": kind, "site": str(place["site"]), "xf": xf, "parts": parts, "contact": person,
		"insurer": insurer, "fee": int(snappedi(roundi(90.0 + km * 70.0 + rng.randf_range(0.0, 40.0)), 5)),
		"rolls": rng.randf() < (0.45 if kind == "barn" else 0.6), "paint": rng.randi() % Shed.PAINTS.size(),
		"name": "%s %s" % [str(place["site"]), "barn find" if kind == "barn" else "crash"],
		"model": model, "km": km, "expires": clock() + OFFER_LIFE,
		"blurb": (BARN_LINES if kind == "barn" else CRASH_LINES)[rng.randi() % (BARN_LINES if kind == "barn" else CRASH_LINES).size()]}
	offers()[id] = o
	Shed._mark_dirty()
	return id


static func _world_data() -> Dictionary:
	for k in World._cache:
		return World._cache[k]
	return {}


## The ground's height at (x, z): the map's land when it's been made, else flat.
static func ground_y(x: float, z: float) -> float:
	var d := _world_data()
	if d.has("terrain"):
		return (d["terrain"] as WorldTerrain).height_at(x, z)
	return 0.0


## A barn find's spot: in front of a farm barn's doors, or beside a village house under a tarp.
static func barn_spot(rng: RandomNumberGenerator) -> Dictionary:
	var d := _world_data()
	var options := []
	if d.has("props"):
		for b in d["props"].get("buildings", []):
			if str(b.get("kind", "")) in ["barn", "shed"] or (str(b.get("kind", "")) == "house" and rng.randf() < 0.08):
				options.append(b)
	if options.is_empty():
		var farms := WorldLayout.SITES.filter(func(s): return s["kind"] == "farm")
		var site: Dictionary = farms[rng.randi() % farms.size()]
		var at: Vector2 = site["at"]
		var p := Vector3(at.x - 10.0, 0.0, at.y + 4.0)
		p.y = ground_y(p.x, p.z)
		return {"site": str(site["name"]), "xf": Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)}
	var b: Dictionary = options[rng.randi() % options.size()]
	var bxf: Transform3D = b["xf"]
	var size: Vector3 = b["size"]
	# Out in front of the doors (+Z), side on to them, a couple of metres clear of the wall.
	var p2 := bxf * Vector3(rng.randf_range(-size.x * 0.25, size.x * 0.25), 0.0, size.z * 0.5 + 2.4)
	p2.y = ground_y(p2.x, p2.z)
	var si := int(b.get("site", 0))
	var site_name := str(WorldLayout.SITES[clampi(si, 0, WorldLayout.SITES.size() - 1)]["name"])
	return {"site": site_name, "xf": Transform3D(bxf.basis * Basis(Vector3.UP, PI * 0.5), p2)}


## A crash site: on the verge beside a tarmac road out in the country.
static func crash_spot(rng: RandomNumberGenerator) -> Dictionary:
	var d := _world_data()
	var home := Vector2(PARK.origin.x, PARK.origin.z)
	if d.has("roads"):
		var roads: WorldRoads = d["roads"]
		var terrain: WorldTerrain = d["terrain"]
		for attempt in 40:
			var ri := rng.randi() % roads.roads.size()
			var r: Dictionary = roads.roads[ri]
			if str(r["kind"]) != "tarmac" or str(r["name"]) == "loop":
				continue
			var xz: PackedVector2Array = r["xz"]
			var i := rng.randi() % xz.size()
			var dist := xz[i].distance_to(home)
			if dist < 250.0 or dist > 1700.0:
				continue
			var dir: Vector2 = (r["dir"] as PackedVector2Array)[i]
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var off := xz[i] + Vector2(-dir.y, dir.x) * side * (float(r["hw"]) + 3.2)
			if terrain.slope_at(off.x, off.y) > 0.22 or not roads.nearest(off.x, off.y, float(r["hw"]) + 1.5).is_empty():
				continue
			var p := Vector3(off.x, terrain.height_at(off.x, off.y), off.y)
			var yaw := atan2(-dir.x, -dir.y) + rng.randf_range(-0.8, 0.8)
			return {"site": World.place_near(p.x, p.z, 600.0) if World.place_near(p.x, p.z, 600.0) != "" else str(r["label"]),
				"xf": Transform3D(Basis(Vector3.UP, yaw), p), "road": str(r["label"])}
	var pts: Array = WorldLayout.ROADS[1]["pts"]
	var a: Vector2 = pts[3]
	var b: Vector2 = pts[4]
	var dir2 := (b - a).normalized()
	var off2 := a + Vector2(-dir2.y, dir2.x) * 6.5
	return {"site": str(WorldLayout.ROADS[1]["label"]), "xf": Transform3D(Basis(Vector3.UP, atan2(-dir2.x, -dir2.y)),
		Vector3(off2.x, ground_y(off2.x, off2.y), off2.y))}


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a recovery action, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var c := car()
	if a in ["recovery_spawn", "recovery_grant"]:
		return "" if peer == Shed.me() else "Only the host can do that."
	if not owned():
		return "The garage hasn't got a recovery truck yet."
	var bike_id := int(action.get("bike", 0))
	var parked := int(c["driver"]) == 0
	match a:
		"recovery_accept", "recovery_decline":
			if not offers().has(int(action.get("offer", 0))):
				return "That job's gone to someone else."
			if a == "recovery_accept" and jobs().values().filter(func(j): return str(j["state"]) == "collect").size() >= MAX_JOBS:
				return "You've already got %d recoveries to fetch. Bring one in first." % MAX_JOBS
		"recovery_enter":
			if not parked:
				return "Someone's driving it."
			if Shed.riding(peer) != 0:
				return "Get off the bike first."
			if Shed.held_by(peer) != 0:
				return "Put the part down first."
			if Shed.pushing_bike(peer) != 0 or Shed.moving(peer) != 0:
				return "Let go of what you're pushing first."
			if int(c["winch"]) != 0:
				return "Wait for the winch to finish."
			if bool(c["ramp"]):
				return "Raise the ramp first (F at the back of the trailer)."
		"recovery_exit", "recovery_move", "recovery_slide", "recovery_fall":
			if int(c["driver"]) != peer:
				return "You're not driving it."
			if a in ["recovery_slide", "recovery_fall"] and not loads().has(bike_id):
				return "It isn't on the trailer."
		"recovery_ramp":
			if not parked:
				return "Stop and get out first."
			if int(c["winch"]) != 0:
				return "Wait for the winch."
		"recovery_winch":
			if not parked:
				return "Stop and get out first."
			if not bool(c["ramp"]):
				return "Lower the ramp first (F at the back of the trailer)."
			if int(c["winch"]) != 0:
				return "The winch is already turning."
			return _winch_check(bike_id)
		"recovery_unload":
			if not parked:
				return "Stop and get out first."
			if not bool(c["ramp"]):
				return "Lower the ramp first."
			if int(c["winch"]) != 0:
				return "The winch is already turning."
			if not on_bed(bike_id):
				return "It isn't on the trailer."
			if straps_on(bike_id) > 0:
				return "Undo its straps first."
		"recovery_winch_stop":
			if int(c["winch"]) == 0:
				return "The winch isn't turning."
		"recovery_strap":
			if not on_bed(bike_id):
				return "There's no bike in that channel."
			var p := int(action.get("point", -1))
			if p < 0 or p >= STRAPS:
				return "There's no strap there."
			if not parked:
				return "Stop and get out first."
		"recovery_tarp":
			var job := job_of(bike_id)
			if job.is_empty() or not bool(job.get("tarp", false)):
				return "There's no tarp on it."
		"recovery_dolly_off":
			if str(dolly()["at"]) != "trailer":
				return "The dolly isn't on the trailer."
			if not parked:
				return "Stop and get out first."
			if bike_id != 0 and (not Shed.bikes.has(bike_id) or (Shed.bikes[bike_id]["xf"] as Transform3D).origin.distance_to(
					trailer_xf().origin) > DOLLY_CARRY):
				return "That's too far to carry it. Park the trailer nearer the bike."
		"recovery_dolly_stow":
			if str(dolly()["at"]) != "ground":
				return "Take the bike off the dolly first." if str(dolly()["at"]) == "bike" else "The dolly's already on the trailer."
			if (dolly()["xf"] as Transform3D).origin.distance_to(trailer_xf().origin) > DOLLY_CARRY:
				return "It's too far from the trailer to carry it back. Bring the truck over."
		"recovery_dolly_load":
			if str(dolly()["at"]) != "ground":
				return "Put the dolly down by the bike first: it's on the trailer's side rail."
			if not Shed.bikes.has(bike_id):
				return "That bike has gone."
			var b: Dictionary = Shed.bikes[bike_id]
			if int(b["rider"]) != 0 or int(b.get("pusher", 0)) != 0 or loads().has(bike_id):
				return "Let go of it first."
			if (b["xf"] as Transform3D).origin.distance_to((dolly()["xf"] as Transform3D).origin) > DOLLY_REACH:
				return "Wheel the dolly up to the bike first."
		"recovery_dolly_unload":
			if str(dolly()["at"]) != "bike":
				return "There's nothing on the dolly."
			var on := int(dolly()["bike"])
			if Shed.bikes.has(on) and int(Shed.bikes[on].get("pusher", 0)) != 0:
				return "Let go of it first."
		"recovery_buy", "recovery_salvage", "recovery_insurer":
			var job: Dictionary = jobs().get(int(action.get("job", 0)), {})
			if job.is_empty() or str(job["state"]) != "delivered":
				return "Bring it back to the yard first."
			if not Shed.bikes.has(int(job["bike"])) or loads().has(int(job["bike"])):
				return "Get it off the trailer first."
			var price := int(assess(int(job["bike"]), job)[{"recovery_buy": "buy", "recovery_salvage": "salvage"}.get(a, "buy")]) \
				if a != "recovery_insurer" else 0
			if price > Shed.garage_money:
				return "The garage can't afford %s." % money(price)
			if a == "recovery_salvage" and int(Shed.bikes[int(job["bike"])].get("pusher", 0)) != 0:
				return "Let go of it first."
		"recovery_collect":
			var job: Dictionary = jobs().get(int(action.get("job", 0)), {})
			if job.is_empty() or str(job["state"]) != "insurer":
				return "There's no insurer job like that."
			var b2: Dictionary = Shed.bikes.get(int(job["bike"]), {})
			if b2.is_empty():
				return "The bike has gone."
			if int(b2.get("rider", 0)) != 0 or int(b2.get("pusher", 0)) != 0 or loads().has(int(job["bike"])):
				return "Park it in the yard for them first."
			if not Shed.in_work_area((b2["xf"] as Transform3D).origin):
				return "Bring it back to the yard for them to collect."
			var left := insurer_left(job)
			if not left.is_empty():
				return "Not up to the insurer's spec yet: %s." % ", ".join(left)
		_:
			return "There's nothing like that to do."
	return ""


## Why `bike_id` can't be winched onto the parked trailer from where it stands, or "".
static func _winch_check(bike_id: int) -> String:
	if not Shed.bikes.has(bike_id):
		return "Wheel a bike to the foot of the ramp first."
	var b: Dictionary = Shed.bikes[bike_id]
	if int(b["rider"]) != 0 or int(b.get("pusher", 0)) != 0:
		return "Let go of it first: the winch does the pulling."
	if loads().has(bike_id):
		return "It's already on."
	if str(b.get("stand", "")) == "down":
		return "Stand it up first (hold {interact} on it)."
	if seized(bike_id):
		return "It won't roll: the %s. Take the dolly tray off the trailer's side rail and get it on that." % (
			"brakes are seized solid" if str(job_of(bike_id).get("kind", "")) == "barn" else "front wheel's buckled")
	var at := trailer_xf().affine_inverse() * (b["xf"] as Transform3D).origin
	if at.z < Trailer.ramp_foot_z() - 0.3 or at.z > Trailer.start_z() + REACH or absf(at.x) > 1.6:
		return "Wheel it to the foot of the ramp first, facing up it."
	var fwd := (trailer_xf().basis.inverse() * (b["xf"] as Transform3D).basis * Vector3.FORWARD)
	if fwd.z > -0.6:
		return "Turn it round to face up the ramp."
	if free_slot(at.x) < 0:
		return "Both channels are full."
	return ""


## The free channel nearest `x` (trailer space), or -1.
static func free_slot(x := 0.0) -> int:
	var taken := {}
	for id in loads():
		taken[int(loads()[id]["slot"])] = true
	var best := -1
	for i in Trailer.SLOTS_X.size():
		if taken.has(i):
			continue
		if best < 0 or absf(float(Trailer.SLOTS_X[i]) - x) < absf(float(Trailer.SLOTS_X[best]) - x):
			best = i
	return best


## Does a recovery action (already checked) and returns what to tell the player.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var c := car()
	var bike_id := int(action.get("bike", 0))
	var text := ""
	match a:
		"recovery_grant":
			Shed.upgrades[UPGRADE] = true
			text = "The recovery truck and trailer are parked in the yard."
		"recovery_spawn":
			var id := spawn(str(action.get("kind", "")))
			text = "Recovery job: %s" % offers()[id]["name"]
		"recovery_accept":
			text = _accept(int(action["offer"]))
		"recovery_decline":
			offers().erase(int(action["offer"]))
			text = "Turned it down."
		"recovery_enter":
			c["driver"] = peer
			text = "In the truck. {ignition} starts it, {throttle} and {front_brake} to drive,\n{shift_down} when stopped for reverse (or hold {front_brake}), {headlight} the headlamps, {rear_brake} the handbrake, {interact} to get out."
		"recovery_exit", "recovery_move":
			if action.get("xf") is Transform3D:
				c["xf"] = action["xf"]
			if action.get("trailer_xf") is Transform3D:
				c["trailer_xf"] = action["trailer_xf"]
			for id in loads():
				if Shed.bikes.has(int(id)):
					Shed.bikes[int(id)]["xf"] = load_world(int(id))
			if a == "recovery_exit":
				c["driver"] = 0
		"recovery_ramp":
			c["ramp"] = bool(action.get("down", not bool(c["ramp"])))
			text = "Ramp %s" % ("down" if c["ramp"] else "up")
		"recovery_winch":
			var at := trailer_xf().affine_inverse() * (Shed.bikes[bike_id]["xf"] as Transform3D).origin
			var slot := free_slot(at.x)
			var dollied := on_dolly(bike_id)
			loads()[bike_id] = {"slot": slot, "s": clampf(Trailer.start_z() - at.z, 0.0, 0.5), "z": 0.0,
				"straps": [false, false, false, false], "dolly": dollied, "tipped": false}
			var build := Shed.build_of(bike_id)
			Shed.bikes[bike_id]["wb"] = build.wheelbase
			Shed.bikes[bike_id]["mass"] = build.bike_mass
			Shed.bikes[bike_id]["stand"] = ""
			if dollied:
				dolly()["at"] = "load"
			c["winch"] = bike_id
			c["winch_dir"] = 1
			text = ("Pushing %s up the ramp on the dolly..." if dollied else "Winching %s up the ramp...") % Shed.bikes[bike_id]["name"]
		"recovery_unload":
			c["winch"] = bike_id
			c["winch_dir"] = -1
			loads()[bike_id]["z"] = 0.0
			loads()[bike_id]["tipped"] = false
			text = "Letting %s down the ramp..." % Shed.bikes[bike_id]["name"]
		"recovery_winch_stop":
			var w := int(c["winch"])
			c["winch"] = 0
			if loads().has(w) and float(loads()[w]["s"]) <= 0.3 and int(c["winch_dir"]) > 0:
				_unloaded(w)
			text = "Winch stopped."
		"recovery_strap":
			var st: Array = loads()[bike_id]["straps"]
			var p := int(action["point"])
			st[p] = bool(action.get("on", not bool(st[p])))
			loads()[bike_id]["tipped"] = false
			text = "%s strap %s%s" % [str(STRAP_NAMES[p]).capitalize(), "ratcheted tight" if st[p] else "undone",
				". The front pair hold it." if secure(bike_id) and st[p] and straps_on(bike_id) == 2 else ""]
			Shed._xp(peer, "dyno_strap", 1.0, "bike:%d" % bike_id)
		"recovery_slide":
			loads()[bike_id]["z"] = clampf(float(action.get("z", 0.0)), -Trailer.CHOCK_GAP, Trailer.TAIL_GAP)
		"recovery_fall":
			text = _fall_off(bike_id, action.get("xf"))
		"recovery_tarp":
			job_of(bike_id)["tarp"] = false
			text = "Tarp off: there she is. %s" % ("Stand it up and wheel it to the ramp." if bool(job_of(bike_id).get("rolls", true))
				else "The brakes are seized solid, so it'll need the dolly tray.")
		"recovery_dolly_off":
			dolly()["at"] = "ground"
			if Shed.bikes.has(bike_id):
				# Carried over and put down alongside the bike.
				var bx: Transform3D = Shed.bikes[bike_id]["xf"]
				var dx := Transform3D(Basis(Vector3.UP, bx.basis.get_euler().y), bx.origin + bx.basis * Vector3(1.1, 0.0, 0.0))
				if _world_data().has("terrain"):
					dx.origin.y = ground_y(dx.origin.x, dx.origin.z)
				dolly()["xf"] = dx
				text = "Dolly tray down beside %s. {interact} on the dolly to get the bike up on it." % Shed.bikes[bike_id]["name"]
			else:
				dolly()["xf"] = trailer_xf() * Transform3D(Basis(), Vector3(1.6, 0.0, Trailer.start_z()))
				text = "Dolly tray down behind the trailer."
		"recovery_dolly_stow":
			dolly()["at"] = "trailer"
			dolly()["bike"] = 0
			text = "Dolly tray back on the side rail."
		"recovery_dolly_load":
			var dxf: Transform3D = dolly()["xf"]
			var b: Dictionary = Shed.bikes[bike_id]
			b["xf"] = Transform3D((b["xf"] as Transform3D).basis, dxf.origin)
			b["stand"] = ""
			dolly()["at"] = "bike"
			dolly()["bike"] = bike_id
			text = "%s is up on the dolly. Hold {interact} to push it to the foot of the ramp, then winch it up." % b["name"]
		"recovery_dolly_unload":
			var on := int(dolly()["bike"])
			dolly()["at"] = "ground"
			dolly()["bike"] = 0
			if Shed.bikes.has(on):
				var bx: Transform3D = Shed.bikes[on]["xf"]
				dolly()["xf"] = Transform3D(bx.basis, bx.origin + bx.basis * Vector3(1.2, 0.0, 0.0))
				Shed.bikes[on]["stand"] = Shed._rest_stand(on)
			text = "Bike off the dolly."
		"recovery_buy":
			text = _buy(peer, jobs()[int(action["job"])])
		"recovery_salvage":
			text = _salvage(peer, jobs()[int(action["job"])])
		"recovery_insurer":
			var job: Dictionary = jobs()[int(action["job"])]
			job["state"] = "insurer"
			job["spec"] = _insurer_spec(int(job["bike"]))
			job["pay"] = int(assess(int(job["bike"]), job)["insurer"])
			text = "%s will pay %s to put it right: %s. Every part on and bolted up, then they'll collect it from the yard." % [
				job["insurer"], money(int(job["pay"])), ", ".join(job["spec"].map(func(sl): return PartsDB.slot_name(str(sl)).to_lower())) if not job["spec"].is_empty() else "a once-over"]
		"recovery_collect":
			text = _collect(peer, jobs()[int(action["job"])])
	Shed._mark_dirty()
	return text


static func _accept(offer_id: int) -> String:
	var o: Dictionary = offers()[offer_id]
	offers().erase(offer_id)
	var rng: RandomNumberGenerator = Shed._rng
	var kind := str(o["kind"])
	var bike_id := Shed._new_bike(o["parts"], 0, str(o["model"]), 0.85 if kind == "barn" else 0.25, Shed.PAINTS[int(o["paint"]) % Shed.PAINTS.size()])
	var bike: Dictionary = Shed.bikes[bike_id]
	bike["bay"] = -1
	bike["xf"] = o["xf"]
	bike["wb"] = Shed.build_of(bike_id).wheelbase
	_wreck(bike_id, kind, bool(o["rolls"]), rng)
	bike["stand"] = "down" if kind == "crash" else ("side" if Shed.item_on(bike_id, "side_stand") != 0 else Shed._rest_stand(bike_id))
	var s := _st()
	var jid := int(s["next"])
	s["next"] = jid + 1
	var job := {"id": jid, "kind": kind, "bike": bike_id, "site": str(o["site"]), "at": (o["xf"] as Transform3D).origin,
		"state": "collect", "fee": int(o["fee"]), "contact": str(o["contact"]), "insurer": str(o["insurer"]),
		"rolls": bool(o["rolls"]), "tarp": kind == "barn" and rng.randf() < 0.6, "accepted": clock(), "name": str(o["name"])}
	jobs()[jid] = job
	bike["recovery"] = jid
	bike["name"] = str(o["name"]).capitalize()
	Contracts.refresh_delivered(bike_id)
	return "Recovery job taken on: %s. It's marked on the map, %.1f km away. Take the truck (F at the driver's door)." % [
		job["name"], float(o["km"])]


## A recovery bike as it's found. Barn finds: rust and muck on everything, flat tyres, stale
## fuel and oil, and maybe seized brakes. Crashes: smashed parts on the side it went down on,
## and maybe a buckled front wheel.
static func _wreck(bike_id: int, kind: String, rolls: bool, rng: RandomNumberGenerator) -> void:
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or PartsDB.is_fluid(str(Shed.items[id]["part"])):
			continue
		var it: Dictionary = Shed.items[id]
		if kind == "barn":
			it["dirt"] = clampf(rng.randf_range(0.75, 1.0), 0.0, 1.0)
			it["rust"] = clampf(float(it["rust"]) + rng.randf_range(0.1, 0.3), 0.0, 1.0)
		else:
			it["dirt"] = clampf(float(it["dirt"]) + rng.randf_range(0.2, 0.5), 0.0, 1.0)
	if kind == "barn":
		for slot in ["front_tyre", "rear_tyre"]:
			var t := Shed.item_on(bike_id, slot)
			if t != 0:
				Shed.items[t]["flat"] = 1.0
				Shed.items[t]["wear"] = maxf(float(Shed.items[t]["wear"]), 0.7)
		for slot in ["engine", "tank"]:
			var f := Shed.item_on(bike_id, slot)
			if f != 0 and Shed.items[f].get("fluid") is Dictionary:
				Shed.items[f]["fluid"]["age"] = 1.0
				Shed.items[f]["fluid"]["litres"] = snappedf(float(Shed.items[f]["fluid"].get("litres", 0.0)) * 0.3, 0.01)
		if not rolls:
			for slot in ["front_caliper", "rear_caliper"]:
				var cal := Shed.item_on(bike_id, slot)
				if cal != 0:
					Shed.items[cal]["wear"] = 0.95
					Shed.items[cal]["rust"] = maxf(float(Shed.items[cal]["rust"]), 0.8)
	else:
		var hit := CRASH_PARTS.duplicate()
		Contracts._shuffle(hit, rng)
		var n := rng.randi_range(3, 6)
		for slot in hit:
			if n <= 0:
				break
			var id := Shed.item_on(bike_id, slot)
			if id == 0:
				continue
			Shed.items[id]["wear"] = rng.randf_range(0.8, 1.0)
			Shed.items[id]["scuff"] = true
			n -= 1
		if not rolls:
			var fw := Shed.item_on(bike_id, "front_wheel")
			if fw != 0:
				Shed.items[fw]["wear"] = 0.98


static func _delivered(job: Dictionary) -> void:
	job["state"] = "delivered"
	job["delivered"] = clock()
	var fee := int(job["fee"])
	Shed.credit_garage(fee, "Recovery: %s" % job["name"])
	_st()["earned"] = int(_st()["earned"]) + fee
	var crew: Array = Shed.crew.keys()
	for p in crew:
		Shed._xp(int(p), "recovery_delivered", 1.0, "recovery:%d" % int(job["id"]))
	_tell_all("%s delivered to the yard: %s call-out paid. Assess it from the Recovery list ({menu}, Recovery)." % [
		str(job["name"]).capitalize(), money(fee)], true)


## The bike comes off the trailer (it's slid off the side): on its side on the ground there,
## with the damage of the fall.
static func _fall_off(bike_id: int, xf) -> String:
	loads().erase(bike_id)
	if int(car()["winch"]) == bike_id:
		car()["winch"] = 0
	if on_dolly(bike_id):
		dolly()["at"] = "ground"
		dolly()["bike"] = 0
	var b: Dictionary = Shed.bikes[bike_id]
	if xf is Transform3D:
		b["xf"] = xf
		if str(dolly()["at"]) == "ground" and (dolly()["xf"] as Transform3D) == Transform3D():
			dolly()["xf"] = xf
	b["stand"] = "down"
	var rng: RandomNumberGenerator = Shed._rng
	for slot in ["handlebars", "mirrors", "front_mudguard", "tank", "exhaust", "indicators", "rearsets", "side_panels"]:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and rng.randf() < 0.6:
			Shed.items[id]["wear"] = clampf(float(Shed.items[id]["wear"]) + rng.randf_range(0.15, 0.4), 0.0, 1.0)
			Shed.items[id]["scuff"] = true
	return "%s came off the trailer! It wasn't strapped down. Stop, stand it up and winch it back on." % b["name"]


# ---------------------------------------------------------------------------- assessment

## A recovered bike looked over: every part with its condition and what putting it right
## costs (restore it, or replace it when it's past saving), the total, what it'd be worth put
## right, and the three prices: the owner's asking price to buy it, the spares price to break
## it, and what the insurer pays to repair it.
static func assess(bike_id: int, job := {}) -> Dictionary:
	var rows := []
	var repair := 0
	var worth_fixed := 0.0
	var worth_now := 0.0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0 or not Shed.items.has(id):
			continue
		var it: Dictionary = Shed.items[id]
		var part := str(it["part"])
		if PartsDB.is_fluid(part):
			continue
		var h := BikeBuild.part_health(Shed.condition_of(it))
		var price := Money.part_price(part)
		var fix := "ok"
		var cost := 0
		if h < 0.4 or float(it.get("wear", 0.0)) > 0.85:
			fix = "replace"
			cost = price
		elif h < 0.8:
			fix = "restore"
			cost = roundi(price * (1.0 - h) * 0.45 + 15.0)
		repair += cost
		worth_fixed += price * Money.SELL_RATE
		worth_now += Money.item_worth(it)
		rows.append({"slot": slot, "part": part, "name": PartsDB.part_name(part), "health": h, "fix": fix, "cost": cost,
			"text": Shed.condition_text(it), "item": id})
	if Shed.is_complete(bike_id):
		worth_fixed *= 1.0 + Money.BONUS_COMPLETE + Money.BONUS_RIDEABLE
	var fixed := roundi(worth_fixed)
	var kind := str(job.get("kind", "barn"))
	# The owner knows roughly what it's worth: a barn find goes cheap, a crashed bike's owner
	# wants what the insurer would give them for it.
	var ask := maxi(80, roundi(maxf(fixed - repair, worth_now * 0.5) * (0.35 if kind == "barn" else 0.45)))
	ask = int(snappedi(ask, 10))
	return {"rows": rows, "repair": repair, "fixed": fixed, "now": roundi(worth_now), "buy": ask,
		"salvage": int(snappedi(maxi(40, roundi(ask * 0.55)), 10)), "insurer": int(snappedi(roundi(repair * 1.35 + 140.0), 5)),
		"strip": roundi(worth_now)}


## The parts the insurer wants put right: anything the assessment says to restore or replace.
static func _insurer_spec(bike_id: int) -> Array:
	var out := []
	for r in assess(bike_id)["rows"]:
		if str(r["fix"]) != "ok":
			out.append(str(r["slot"]))
	return out


## What's still to do on an insurer job: parts not up to INSURER_HEALTH, missing or loose.
static func insurer_left(job: Dictionary) -> Array:
	var bike_id := int(job["bike"])
	var out := []
	for slot in job.get("spec", []):
		var id := Shed.item_on(bike_id, str(slot))
		if id == 0:
			out.append("%s missing" % PartsDB.part_name(str(Shed.bikes[bike_id]["original"].get(slot, slot))).to_lower())
		elif BikeBuild.part_health(Shed.condition_of(Shed.items[id])) < INSURER_HEALTH or float(Shed.items[id]["wear"]) > 0.6:
			out.append(PartsDB.part_name(str(Shed.items[id]["part"])).to_lower())
	if not Shed.missing_slots(bike_id).is_empty() and out.is_empty():
		out.append("parts missing")
	if not Shed.loose_slots(bike_id).is_empty():
		out.append("not bolted up")
	return out


static func _pay_garage(amount: int, reason: String) -> bool:
	return amount <= 0 or Shed.charge_garage(amount, reason)


## Buy it: the owner is paid and it's the garage's own project bike.
static func _buy(peer: int, job: Dictionary) -> String:
	var bike_id := int(job["bike"])
	var price := int(assess(bike_id, job)["buy"])
	if not _pay_garage(price, "Bought: %s" % job["name"]):
		return "The garage can't afford it."
	Shed.bikes[bike_id]["bought"] = price
	_finish(job, "Bought for %s" % money(price), -price)
	Shed._xp(peer, "recovery_delivered", 0.5, "bought:%d" % bike_id)
	return "Bought %s from %s for %s. It's yours: wheel it into a bay." % [Shed.bikes[bike_id]["name"], job["contact"], money(price)]


## Break it for parts: paid for as spares, every part comes off into the delivery area (or the
## ground beside it when that's full) and the frame goes for scrap.
static func _salvage(peer: int, job: Dictionary) -> String:
	var bike_id := int(job["bike"])
	var price := int(assess(bike_id, job)["salvage"])
	if not _pay_garage(price, "Salvage: %s" % job["name"]):
		return "The garage can't afford it."
	var b: Dictionary = Shed.bikes[bike_id]
	var at: Transform3D = b["xf"]
	var n := 0
	for slot in PartsDB.BIKE_SLOTS:
		if slot == "frame" or Shed.item_on(bike_id, slot) == 0:
			continue
		# Into the delivery area, or laid out on the ground beside the bike when that's full.
		var id := Shed._detach(bike_id, slot, "floor", Transform3D(Basis(), at.origin + Vector3(0.6 * (n % 6) - 1.5, 0.0, 1.2 + 0.6 * (n / 6))))
		Shed._deliver(id)
		n += 1
	var frame := Shed.item_on(bike_id, "frame")
	var scrap := 0
	if frame != 0:
		scrap = maxi(10, roundi(Money.part_price(str(Shed.items[frame]["part"])) * 0.05))
		Shed._erase_item(frame)
	Shed.bikes.erase(bike_id)
	if int(dolly()["bike"]) == bike_id:
		dolly()["at"] = "ground"
		dolly()["xf"] = at
		dolly()["bike"] = 0
	Shed.credit_garage(scrap, "Scrap frame: %s" % job["name"])
	_finish(job, "Broken for parts (%s)" % money(price), scrap - price)
	Shed._xp(peer, "recycle_metal", 2.0)
	return "Paid %s for it as spares: %d parts stripped off into the delivery area, the frame scrapped for %s." % [money(price), n, money(scrap)]


## The insurer collects a repaired bike: paid, and it's gone.
static func _collect(peer: int, job: Dictionary) -> String:
	var pay := int(job.get("pay", 0))
	Shed.credit_garage(pay, "Insurer repair: %s" % job["name"])
	var bike_id := int(job["bike"])
	if int(dolly()["bike"]) == bike_id:
		dolly()["at"] = "ground"
		dolly()["xf"] = Shed.bikes[bike_id]["xf"]
		dolly()["bike"] = 0
	Contracts._remove_bike(bike_id)
	_finish(job, "Repaired for %s (%s)" % [job["insurer"], money(pay)], pay)
	for p in Shed.crew:
		Shed._xp(int(p), "recovery_insurer", 1.0 if int(p) == peer else 0.6, "recovery:%d" % int(job["id"]))
	return "%s's truck has collected it and paid %s." % [job["insurer"], money(pay)]


static func _finish(job: Dictionary, outcome: String, money_in: int) -> void:
	var s := _st()
	var done: Array = s["done"]
	done.push_front({"name": str(job["name"]), "kind": str(job["kind"]), "outcome": outcome, "fee": int(job["fee"]),
		"net": money_in + int(job["fee"]), "day": Contracts.day_number()})
	while done.size() > MAX_DONE:
		done.pop_back()
	jobs().erase(int(job["id"]))
	if Shed.bikes.has(int(job["bike"])):
		Shed.bikes[int(job["bike"])].erase("recovery")


# ---------------------------------------------------------------------------- blocks on other actions

## Why an ordinary bike action can't be done to a bike in the middle of a recovery, or "".
static func block(_peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var bike_id := int(action.get("bike", 0))
	if bike_id == 0 or not Shed.bikes.has(bike_id):
		return ""
	if loads().has(bike_id) and a in ["mount", "grab_bike", "set_stand", "move_bike", "release_bike"]:
		return "It's on the trailer. Undo the straps and let it down the ramp (F at the winch post) first."
	var job := job_of(bike_id)
	if job.is_empty():
		return ""
	if a == "mount" and str(job["state"]) in ["collect", "delivered"]:
		return "It's not roadworthy. Winch it onto the trailer and take it back to the yard." if str(job["state"]) == "collect" \
			else "Assess it first ({menu}, Recovery): buy it, break it or fix it for the insurer."
	if a == "grab_bike" and seized(bike_id):
		return "It won't roll: the %s. Get it on the dolly tray (it hangs on the trailer's side rail)." % (
			"brakes are seized solid" if str(job["kind"]) == "barn" else "front wheel's buckled")
	if a == "grab_bike" and bool(job.get("tarp", false)):
		return "Pull the tarp off it first ({interact})."
	return ""


# ---------------------------------------------------------------------------- screens

## Where the nearest job still to fetch is, for the HUD: {name, at} or {}.
static func next_site(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for jid in jobs():
		var j: Dictionary = jobs()[jid]
		if str(j["state"]) != "collect":
			continue
		var at: Vector3 = j["at"]
		var b: Dictionary = Shed.bikes.get(int(j["bike"]), {})
		if loads().has(int(j["bike"])):
			at = PARK.origin
			var d0 := from.distance_to(at)
			if d0 < best_d:
				best_d = d0
				best = {"name": "%s: back to the yard" % str(j["name"]).capitalize(), "at": at, "home": true}
			continue
		if not b.is_empty():
			at = (b["xf"] as Transform3D).origin
		var d := from.distance_to(at)
		if d < best_d:
			best_d = d
			best = {"name": str(j["name"]).capitalize(), "at": at, "home": false}
	return best


## "1.4 km NE" from `from` to `to`.
static func distance_text(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var ang := atan2(d.x, -d.y)
	var k := wrapi(roundi(ang / (PI / 4.0)), 0, 8)
	var m := d.length()
	return ("%d m" % roundi(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)) + " " + str(dirs[k])
