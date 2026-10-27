class_name AdventureCrew
extends RefCounted
## The crew's side of a ride on the road network (Ride Anywhere v2, T9), as plain functions: whether two games build
## the same roads (the builder and ride hashes, checked when a player joins the shed and again when they join a
## ride), where each rider is in the region's frame (from the tagged network snapshots, see AdventureWorld.tag_state),
## where a player joining a ride in progress is put, and the crew's "leave the route?" call.
##
## The route call lives in Shed.adventure["route"]: {mode: "route" (the crew rides the route it agreed before
## setting off) or "free" (it's left it: the sat nav takes each rider from wherever they are), version (one more each
## time the crew changes its mind), call: {} or {id, by (peer), kind: "leave" or "rejoin", votes {peer: bool}, ends
## (the host's msec)}, next (the next call's id)}. Any rider calls it, every rider on the trip answers yes or no;
## a majority of them decides, a tie keeps things as they are, and once CALL_SECONDS are up silence counts as no.
## The caller's own answer is yes. A crew of one has no call: the change happens at once. See Adventure for the
## actions (adventure_route_call, adventure_route_vote) and the sat nav (T7) for what each mode means on the road.

## How long the crew has to answer a call (s).
const CALL_SECONDS := 30.0
const KINDS := ["leave", "rejoin"]
## What each kind of call asks, and the mode it brings in when the crew says yes.
const ASKS := {"leave": "leave the agreed route", "rejoin": "get back on the agreed route"}
const MODE_AFTER := {"leave": "free", "rejoin": "route"}
## On the network ride a mate further than this (m) from you is left to their own game: yours doesn't stream the
## roads and land round them (see AdventureTrip.focus_points).
const NEAR := 900.0
## A player joining a ride in progress is put this far (m) behind the mate they join, on the same road.
const JOIN_BEHIND := 12.0
## A ride counts as in progress once a mate is this far (m) from the start: a player joining then is put by them.
const UNDER_WAY := 300.0

static var _builds := ""   # (builds(), worked out once)


# ---------------------------------------------------------------------------- the same roads on every machine

## This game's builder hash: everything that decides what a road block holds and how the agreed route is planned
## (RoadBlock.VERSION, the planner's version, the place profiles' format, the regional kits and country facts).
## Two games with different ones lay out different roads from the same map, so they can't ride the network together.
static func builds() -> String:
	if _builds == "":
		_builds = builds_of([RoadBlock.VERSION, RoutePlanner.VERSION, PlaceProfile.FORMAT,
			FileAccess.get_md5(RegionKit.KITS), FileAccess.get_md5(RegionKit.COUNTRIES)])
	return _builds


## The builder hash of `parts` (12 hex).
static func builds_of(parts: Array) -> String:
	return "|".join(parts.map(func(p): return str(p))).sha1_text().substr(0, 12)


## The ride hash for `region` with builder hash `with` (this game's by default): the builders, the region's cells
## (its hash is made of theirs) and its place profile. Every machine on a network ride must have the same one.
static func ride_hash(region: RealRegion, with := "") -> String:
	if region == null:
		return ""
	var profile := str(PlaceProfile.of_region(region).get("hash", ""))
	return ride_hash_of(with if with != "" else builds(), region.hash, profile)


static func ride_hash_of(builders: String, region_hash: String, profile_hash: String) -> String:
	return ("%s|%s|%s" % [builders, region_hash, profile_hash]).sha1_text().substr(0, 12)


## Why this game can't ride network adventure `info` ("" if it can): a different version (`mine`, this game's
## builder hash), or a different copy of the ride's part of the map (`ride`, this game's ride hash for it).
static func ride_mismatch(info: Dictionary, mine: String, ride: String) -> String:
	if str(info.get("builds", "")) != mine:
		return "Your game is a different version from the host's, so it builds the roads differently: update the game to ride the road network together."
	if ride == "":
		return "Your game doesn't have the part of the map this ride is on."
	if str(info.get("ride_hash", "")) != ride:
		return "Your game's map of this area differs from the host's (its map cells or place profiles): update the game to join."
	return ""


## The names of the crew whose game builds differently from `mine` ({peer: {name, builds}}, as Shed.crew). A player
## who hasn't said yet isn't counted.
static func odd_ones(crew: Dictionary, mine: String) -> Array[String]:
	var out: Array[String] = []
	var ids := crew.keys()
	ids.sort()
	for p in ids:
		var b := str(crew[p].get("builds", ""))
		if b != "" and b != mine:
			out.append(str(crew[p].get("name", "a mate")))
	return out


# ---------------------------------------------------------------------------- where everyone is

## The region-frame (x, z) of a tagged network snapshot (AdventureWorld.tag_state: a walker's [0, x, y, z, ...] or a
## rider's [1, bike, x, y, z, ...], then its sender's origin): the position plus the origin, so the same map point on
## every machine whatever their own origin. null for an untagged one (a player in the shed).
static func region_xz(state: PackedFloat32Array):
	var n := state.size()
	if n < 7 or state[n - 1] != AdventureWorld.NET_TAG:
		return null
	var at := 1 if state[0] < 0.5 else 2
	return Vector2(float(state[at]) + float(state[n - 3]), float(state[at + 2]) + float(state[n - 2]))


## Which of `mates` ({peer: region-frame Vector2}) a player joining is put by: the lowest peer (the host when they're
## out) of those more than UNDER_WAY from `start`, the region-frame start of the ride. -1 when the ride hasn't got
## going (everyone's still near the start, or nobody's out): the joiner starts on the grid like everyone else.
static func join_by(mates: Dictionary, start: Vector2) -> int:
	var ids := mates.keys()
	ids.sort()
	if ids.is_empty() or ids.any(func(p): return (mates[p] as Vector2).distance_to(start) <= UNDER_WAY):
		return -1
	return int(ids[0])


## Whether a mate at `them` is near enough `me` (both region-frame) for this game to keep the road round them too.
static func near(me: Vector2, them: Vector2) -> bool:
	return me.distance_to(them) <= NEAR


# ---------------------------------------------------------------------------- the "leave the route?" call

## The route state as received or loaded: {mode, version, call, next}, a call kept only when it's whole.
static func sanitize_route(v) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var out := {"mode": "free" if str(d.get("mode", "")) == "free" else "route", "version": maxi(0, int(d.get("version", 0))),
		"call": {}, "next": maxi(1, int(d.get("next", 1)))}
	var c = d.get("call")
	if c is Dictionary and int(c.get("id", 0)) > 0 and KINDS.has(str(c.get("kind", ""))):
		var votes := {}
		if c.get("votes") is Dictionary:
			for p in c["votes"]:
				votes[int(p)] = bool(c["votes"][p])
		out["call"] = {"id": int(c["id"]), "by": int(c.get("by", 0)), "kind": str(c["kind"]), "votes": votes, "ends": int(c.get("ends", 0))}
	return out


## Why `peer` can't call `kind` now ("" if they can), with the route state `route` and the riders on the trip.
static func call_check(route: Dictionary, peer: int, kind: String, riders: Array) -> String:
	if not KINDS.has(kind):
		return "That's not a call the crew can make."
	if not riders.has(peer):
		return "You're not out on the ride."
	if not (route.get("call", {}) as Dictionary).is_empty():
		return "The crew's already deciding."
	if str(route.get("mode", "route")) == MODE_AFTER[kind]:
		return "The crew's on the agreed route already." if kind == "rejoin" else "The crew's left the route already."
	return ""


## Why `peer` can't answer call `id` ("" if they can).
static func vote_check(route: Dictionary, peer: int, id: int, riders: Array) -> String:
	var c: Dictionary = route.get("call", {})
	if c.is_empty() or int(c.get("id", 0)) != id:
		return "That call's over."
	if not riders.has(peer):
		return "You're not out on the ride."
	return ""


## A new call by `by` (their own answer yes), ending CALL_SECONDS after `now` (msec). Changes `route`.
static func open_call(route: Dictionary, by: int, kind: String, now: int) -> Dictionary:
	var id := int(route.get("next", 1))
	route["next"] = id + 1
	route["call"] = {"id": id, "by": by, "kind": kind, "votes": {by: true}, "ends": now + int(CALL_SECONDS * 1000.0)}
	return route["call"]


## What the crew's answers to `call` come to: "yes", "no", or "" while it could still go either way. `riders` are the
## peers on the trip; `now` (msec) past its end counts everyone who hasn't answered as no.
static func outcome(call: Dictionary, riders: Array, now: int) -> String:
	var n := riders.size()
	if n <= 1:
		return "yes"
	var yes := 0
	var no := 0
	var votes: Dictionary = call.get("votes", {})
	for p in riders:
		if votes.has(p):
			if bool(votes[p]):
				yes += 1
			else:
				no += 1
	if yes * 2 > n:
		return "yes"
	if (n - no) * 2 <= n or now >= int(call.get("ends", 0)):
		return "no"
	return ""


## Settles the call in `route` as `result` ("yes" or "no"): on yes the mode changes and the version goes up. What to
## tell the crew.
static func settle(route: Dictionary, result: String) -> String:
	var c: Dictionary = route.get("call", {})
	if c.is_empty() or result == "":
		return ""
	route["call"] = {}
	var kind := str(c["kind"])
	if result != "yes":
		return "The crew's staying on the agreed route." if kind == "leave" else "The crew's riding on off the route."
	route["mode"] = MODE_AFTER[kind]
	route["version"] = int(route.get("version", 0)) + 1
	return "The crew's leaving the agreed route: the sat nav takes each of you on from wherever you are." if kind == "leave" \
		else "The crew's back on the agreed route."


## How many seconds a call has left `since` msec after this game first saw it (the host's clock isn't ours, so a
## client counts down from when the call came in).
static func seconds_left(since: int) -> int:
	return maxi(0, ceili(CALL_SECONDS - since / 1000.0))
