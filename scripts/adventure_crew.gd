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
## (RoadBlock.VERSION, the planner's version, the place profiles' format, the regional kits and country facts), and
## what decides the scenery beside them (SceneryStreamer.VERSION, its kit library and its model scripts' versions),
## and the shape of the network messages (Net.PROTOCOL). Two games with different ones lay out different roads from
## the same map, or can't follow each other's riders, so they can't ride the network together.
static func builds() -> String:
	if _builds == "":
		_builds = builds_of([RoadBlock.VERSION, RoutePlanner.VERSION, PlaceProfile.FORMAT,
			FileAccess.get_md5(RegionKit.KITS), FileAccess.get_md5(RegionKit.COUNTRIES),
			SceneryStreamer.VERSION, FileAccess.get_md5(SceneryStreamer.KITS), SceneryStreamer.script_versions(), Net.PROTOCOL,
			"ferry%d" % FerryLinks.VERSION])
	return _builds


## The builder hash of `parts` (12 hex).
static func builds_of(parts: Array) -> String:
	return "|".join(parts.map(func(p): return str(p))).sha1_text().substr(0, 12)


## The ride hash for `region` with builder hash `with` (this game's by default): the builders, the region's cells
## (its hash is made of theirs), its place profile, its features (the scenery) and the ferries joining its roads. Every machine on a network ride must
## have the same one.
static func ride_hash(region: RealRegion, with := "") -> String:
	if region == null:
		return ""
	var profile := str(PlaceProfile.of_region(region).get("hash", ""))
	return ride_hash_of(with if with != "" else builds(), region.hash, profile, region.features_hash, FerryLinks.of(region).hash)


## (A region with no features has the ride hash it had before there were any, and one with no ferries the one it had
## before there were ferries.)
static func ride_hash_of(builders: String, region_hash: String, profile_hash: String, features_hash := "", ferries_hash := "") -> String:
	var parts := [builders, region_hash, profile_hash]
	if features_hash != "":
		parts.append(features_hash)
	if ferries_hash != "":
		parts.append("ferries:" + ferries_hash)
	return "|".join(parts).sha1_text().substr(0, 12)


## Why this game can't ride network adventure `info` ("" if it can): a different version (`mine`, this game's
## builder hash), or a different copy of the ride's part of the map (`ride`, this game's ride hash for it).
static func ride_mismatch(info: Dictionary, mine: String, ride: String) -> String:
	if str(info.get("builds", "")) != mine:
		return "Your game is a different version from the host's, so it builds the roads differently: update the game to ride the road network together."
	if ride == "":
		return "Your game doesn't have the part of the map this ride is on."
	if str(info.get("ride_hash", "")) != ride:
		return MAP_CHANGED
	return ""


## The host's map of a ride on area `region_id` of the world's cells, so every game on it rides the host's: {profiles:
## {"ROW_COL": the place profile the host has for it}, cells: {"ROW_COL": {meta (the hash in the host's copy's
## region.json), hash and url (where the host's index has it)}}}. Only what the host has without asking the network
## (it's worked out as the ride starts). {} for a bundled region.
static func host_map(region_id: String) -> Dictionary:
	var cells := RealRegion.area_cells(region_id)
	if cells.is_empty():
		return {}
	var idx := CellStore.index_now()
	var named: Dictionary = idx.get("cells", {}) if idx.get("cells") is Dictionary else {}
	var profiles := {}
	var out := {}
	for c in cells:
		var key := "%d_%d" % [c.x, c.y]
		var p := PlaceProfile.cached(c)
		if not p.is_empty():
			profiles[key] = p
		var d := RealRegion.cell_dir(c)
		if d == "":
			continue
		var meta = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("region.json")))
		var cell := {"meta": str(meta.get("hash", "")) if meta is Dictionary else ""}
		var e = named.get(key)
		if e is Dictionary and str(e.get("url", "")) != "" and str(e.get("hash", "")) != "":
			cell["hash"] = str(e["hash"])
			cell["url"] = str(e["url"])
		out[key] = cell
	return {"profiles": profiles, "cells": out}


## A guest takes the host's map of ride `info` (host_map): the host's place profiles in place of any this game had or
## guessed (the kits made from the old ones forgotten), and the host's copies of the cells this game hasn't got or has a
## different copy of returned ({"ROW_COL": {hash, url}}), to fetch (CellStore.fetch_entries) before it plans the ride.
static func use_host_map(info: Dictionary) -> Dictionary:
	var map: Dictionary = info.get("map", {}) if info.get("map") is Dictionary else {}
	var changed := false
	var profiles: Dictionary = map.get("profiles", {}) if map.get("profiles") is Dictionary else {}
	for key in profiles:
		if profiles[key] is Dictionary and PlaceProfile.pin(str(key), profiles[key]):
			changed = true
	if changed:
		RegionKit.forget()
	var fetch := {}
	var cells: Dictionary = map.get("cells", {}) if map.get("cells") is Dictionary else {}
	for key in cells:
		var want = cells[key]
		var rc := str(key).split("_")
		if not want is Dictionary or rc.size() != 2 or not from_store(str(want.get("url", ""))):
			continue
		var d := RealRegion.cell_dir(Vector2i(int(rc[0]), int(rc[1])))
		if d.begins_with("res://"):
			continue   # (the game's own copy: it can't be swapped)
		var meta = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("region.json"))) if d != "" else null
		var mine := str(meta.get("hash", "")) if meta is Dictionary else ""
		if mine != str(want.get("meta", "")):
			fetch[str(key)] = {"hash": str(want["hash"]), "url": str(want["url"])}
	return fetch


## How long (s) message `text` stays on the screen: a player turned away from a ride, or told why a mate was, long
## enough to read what to do (up to 12 s, or till the next message); any other the usual `usual`.
static func read_time(text: String, usual: float) -> float:
	var long := text == MAP_CHANGED or text == AdventurePlans.FINISHING or text.ends_with(MAP_CHANGED_CREW.trim_prefix("%s")) \
		or text.begins_with("Your copy of the ") or text.begins_with("Your game planned a different road")
	return clampf(text.length() / 16.0, usual, 12.0) if long else usual


## Whether `url` is one of the world's store's (a cell's release asset, or beside the index): the only place a host's
## map may send a guest's game for a cell.
static func from_store(url: String) -> bool:
	return url.begins_with(STORE_RELEASES) or (url != "" and url.begins_with(CellStore.index_url.get_base_dir() + "/"))


## Where the world's store keeps its cells.
const STORE_RELEASES := "https://github.com/Beenster99/torque-shed-world/releases/download/"


## Why a guest whose game is the host's version still can't join: their copies of the map differ. The world's store
## changed part way (cells baked, or their place profiles made, while the route was planned), so planning again fixes it.
const MAP_CHANGED := "Your game's map of this area isn't the same as the host's: the map changed while the route was planned. Ask the host to end the ride and start it again."
## What the crew's told when a guest can't join for that (the guest's name first).
const MAP_CHANGED_CREW := "%s couldn't join the ride: their map of this area isn't the same as the host's (the map changed while the route was planned). Host, end the ride and start it again to bring them along."


## Whether a guest turned away from ride `info` with plan result `res` (AdventurePlans.result) may have only an older
## copy of the map, which fetching the latest could put right: their game is the host's version, and either the plan
## failed over the map itself or it was planned and came out different.
static func map_may_catch_up(info: Dictionary, res: Dictionary) -> bool:
	if str(info.get("builds", "")) != builds():
		return false
	if not bool(res.get("ok", false)):
		return bool(res.get("map", false))
	return true


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


# ---------------------------------------------------------------------------- crossing on a ferry together

## The crew crosses on a ferry together (D7, see FerryCrossing). The sailing lives in Shed.adventure["ferry"]:
## {} when there's none, else {sail (one more each sailing), id (the route's), from, to (the terminals' junctions),
## seconds (how long the crossing is: FerryLinks.seconds), aboard {peer: true}, landed {peer: true} (off
## on the far side), since (the host's msec the first went aboard), departs (the host's msec it left, 0 while it's
## at the ramp)}. A rider rides onto the ramp to go aboard (adventure_ferry_board); the host lets it go once everyone
## out on the ride is aboard, or after FERRY_WAIT once half of them are or more (adventure_ferry_tick), as the ride's
## start waits for the crew; once everyone aboard has landed (adventure_ferry_landed) the host clears it, and the next sailing's boat is at
## the ramp.

## How long the ferry waits at the ramp for the rest of the crew once someone's aboard (s), and how soon it leaves
## once all are (s).
const FERRY_WAIT := 60.0
const FERRY_ALL_IN := 2.0
## A sailing whose riders haven't all said they've landed is cleared anyway this many times its length on, and two
## minutes (a game stuck mid-crossing: one that drops out of the crew is let go of at once).
const FERRY_LATE := 4.0


## The sailing as received ({} for none or junk).
static func sanitize_ferry(v) -> Dictionary:
	if not v is Dictionary or int(v.get("sail", 0)) <= 0 or str(v.get("id", "")) == "":
		return {}
	var aboard := {}
	if v.get("aboard") is Dictionary:
		for p in v["aboard"]:
			aboard[int(p)] = true
	var landed := {}
	if v.get("landed") is Dictionary:
		for p in v["landed"]:
			landed[int(p)] = true
	return {"sail": int(v["sail"]), "id": str(v["id"]), "from": int(v.get("from", -1)), "to": int(v.get("to", -1)),
		"seconds": clampf(float(v.get("seconds", FerryLinks.CROSS_LEAST)), FerryLinks.CROSS_LEAST, FerryLinks.CROSS_MOST), "aboard": aboard,
		"landed": landed, "since": int(v.get("since", 0)), "departs": int(v.get("departs", 0))}


## Why `peer` can't go aboard the ferry on route `id` from terminal `from` now ("" if they can).
static func board_check(ferry: Dictionary, peer: int, id: String, from: int, riders: Array) -> String:
	if not riders.has(peer):
		return "You're not out on the ride."
	if id == "" or from < 0:
		return "There's no ferry there."
	if ferry.is_empty():
		return ""
	if (ferry["aboard"] as Dictionary).has(peer):
		return "You're aboard already."
	if int(ferry["departs"]) != 0:
		return "The ferry's just left: the next one's in a minute or so."
	if str(ferry["id"]) != id or int(ferry["from"]) != from:
		return "The crew's boarding another ferry."
	return ""


## `ferry` with `peer` aboard (a new sailing, number `sail`, from `from` to `to` on route `id`, `seconds` long, when
## there's none), at the host's `now` (msec).
static func board(ferry: Dictionary, peer: int, id: String, from: int, to: int, seconds: float, sail: int, now: int) -> Dictionary:
	var out := ferry.duplicate(true)
	if out.is_empty():
		out = {"sail": sail, "id": id, "from": from, "to": to, "aboard": {}, "landed": {}, "since": now, "departs": 0,
			"seconds": clampf(seconds, FerryLinks.CROSS_LEAST, FerryLinks.CROSS_MOST)}
	(out["aboard"] as Dictionary)[peer] = true
	return out


## `ferry` with `peer` off it again before it's left (sailing number `sail`): {} once nobody's aboard, so the next to
## ride on starts a new sailing (from either end).
static func got_off(ferry: Dictionary, peer: int, sail: int) -> Dictionary:
	if ferry.is_empty() or int(ferry["sail"]) != sail or int(ferry["departs"]) != 0:
		return ferry
	var out := ferry.duplicate(true)
	(out["aboard"] as Dictionary).erase(peer)
	return {} if (out["aboard"] as Dictionary).is_empty() else out


## Whether the ferry should leave at the host's `now` (msec), with `riders` the peers out on the ride.
static func should_sail(ferry: Dictionary, riders: Array, now: int) -> bool:
	if ferry.is_empty() or int(ferry["departs"]) != 0:
		return false
	var aboard: Dictionary = ferry["aboard"]
	var on := 0
	for p in riders:
		if aboard.has(p):
			on += 1
	if on == 0:
		return false
	if on >= riders.size():
		return now - int(ferry["since"]) >= int(FERRY_ALL_IN * 1000.0) or riders.size() == 1
	return now - int(ferry["since"]) >= int(FERRY_WAIT * 1000.0) and on * 2 >= riders.size()


## Whether sailing `ferry` (`total` s long, FerryCrossing.total_of) is over at the host's `now` (msec): everyone aboard
## who's still out on the ride (`riders`) has landed, or it's long past.
static func sailing_over(ferry: Dictionary, riders: Array, now: int, total: float) -> bool:
	if ferry.is_empty() or int(ferry["departs"]) == 0:
		return false
	var landed: Dictionary = ferry["landed"]
	var all := true
	for p in ferry["aboard"]:
		if riders.has(p) and not landed.has(p):
			all = false
	return all or now - int(ferry["departs"]) > int((total * FERRY_LATE + 120.0) * 1000.0)


## The names of the crew still to come aboard ({peer: {name}} as Shed.crew; `riders` those out on the ride).
static func ferry_waiting(ferry: Dictionary, crew: Dictionary, riders: Array) -> Array[String]:
	var out: Array[String] = []
	if ferry.is_empty():
		return out
	for p in riders:
		if not (ferry["aboard"] as Dictionary).has(p):
			out.append(str((crew.get(p, {}) as Dictionary).get("name", "a mate")))
	return out
