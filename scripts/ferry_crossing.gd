class_name FerryCrossing
extends Node
## This player's side of crossing on a ferry on the network ride (Ride Anywhere v2, phase D round 3, D7): the crew's
## boat at the ramp of the ferry ahead, riding aboard it, the crossing itself (about a minute, the place's name coming
## up as you near the far side, as at an arrival) and riding off on the other side. Simon's settled choice: a short
## real crossing, not a cut; on a long route the boat sails out of one harbour and into the other, the open water
## between passed over in a moment's dark.
##
## Riding on and off (Simon on v0.43.0: "riding on and off the ferry is great fun"): the boat and the terminals' ramps
## are solid. You ride up the ramp at the road's end, over the bridge out to the boat where it lies afloat, down its
## end ramp and onto the deck, and you're aboard; get off and walk about on deck if you like. The boat's drive-through
## (FerryScenery.BOATS): it lowers the ramp at the far end when it ties up there, and you ride off down it. While it
## sails, whatever's on its deck goes where it goes (your bike, you on foot, a bike left standing there): each tick it's
## moved on as the boat moved, so on the deck it all handles as on the ground, and the boat's rails and raised ramps
## keep it aboard (anyone who goes over the side all the same is put back on deck).
##
## The sailing is the crew's (Shed.adventure "ferry", see AdventureCrew): the host lets it go when everyone's aboard,
## or after a wait once half are, as the ride's start waits; each game sails it from when it hears it's left, along
## the route's one fixed line (FerryLinks), so the crew sees the same boat in the same place. A mate left behind sees
## it go, and the next sailing's boat is at the ramp once it's across. Off the deck again before it sails, you're off
## it (adventure_ferry_off); off it at the far side, you've landed (adventure_ferry_landed).
##
## The boat never turns round: its bow's always towards its route's b end (FerryLinks), so it sails one way bow first
## and back stern first, as a double-ended ferry does, and it lies at either terminal the same way round whether it's
## just come in or is waiting to go.

## The crew's boat is shown at the ramp of a ferry ahead once a rider's this near its terminal (m).
const SHOW_R := 2500.0
## The ramp going up and the horn before it sails, and tying up at the far side (s).
const PREP := 4.0
const DOCK := 4.0
## How long a boat's end ramp takes to go up or come down (s).
const RAMP_MOVE := 2.5
## A long route's boat speeds up and slows down over this long (s), and the dark over its open water lasts this long
## either side of the middle (s).
const ACCEL := 8.0
const FADE := 1.6
## Where a rider's put on the road off a terminal (landing_xf: LAND_IN m inland of it, and LAND_GAP more for each one
## after the first), this high (m) over the ferry's water at least, this much (m) further on at most.
const LAND_IN := 9.0
const LAND_GAP := 6.0
const DRY := 0.6
const DRY_MOST := 120.0
## The place's name is up over this stretch before the far side (s from the end of the sailing).
const NAME_FROM := 14.0
const NAME_TO := 3.0
## A ramp's rails are solid from this far (m) out from the road: a road that comes to it at an angle is ridden onto it.
const RAIL_FROM := 8.0
## How far short of the boat's ramp a bridge's rails stop (m): the boat's ramp is wider, and turned to it when it's lying
## at an angle; a bike ridden off it caught the rails' ends.
const RAIL_SHORT := 2.0
## How far up the road and down the ramp from its foot the joint between them is eased (m: see _build_quays).
const EASE := 2.5
## How near a rider on a ramp the land's ground is let through (m: see _cut).
const CUT_R := 4.0
## Anyone aboard this far (m) under the deck has gone over the side, and is put back on it.
const OVERBOARD := 2.5
## Somewhere this near (m) a terminal's ramp and bridge out to the boat is on the ferry, not lost off the road.
const QUAY_NEAR := 14.0
## The HUD says how to go aboard this near (m) a terminal.
const HINT_R := 80.0

## The crossing this game's showing (one at a time), for the crew's games to draw their mates aboard with it.
static var current: FerryCrossing

var trip: AdventureTrip
var world: AdventureWorld
var links: FerryLinks
## What this player's doing: "" (not on a ferry), "asked" (onto the deck, the host to say), "aboard" (on the boat, at
## the ramp), "sailing", "docked" (tied up at the far side: ride off).
var phase := ""
## The sailing being shown (AdventureCrew.sanitize_ferry's), its link, and how far into it this game is (s from
## when it heard it left; -1 while it's at the ramp).
var sailing := {}
var link := -1
var t := -1.0
## The boat's velocity (m/s, local) this tick: the crew's games draw their mates on its deck on by it (lead).
var velocity := Vector3.ZERO
## Where the boat waits when there's no sailing: the terminal it last tied up at, on that link ({node, link}).
var _rest := {}
var _asked_at := 0
var _off_at := -1      # the terminal this rider just rode off the boat at: no telling them how to go aboard there
var _was_on := false
var _boat: MeshInstance3D
var _boat_key := ""
var _body: StaticBody3D
var _gates := {}       # end (+1 the stern, -1 the bow) -> CollisionShape3D across the deck's end while its ramp's up
var _flaps := {}       # end -> Node3D, its ramp, hinged at the deck's end
var _quays: Node3D     # the terminals' ramps and bridges out to the boat, solid, in the region frame (see _build_quays)
var _quay_key := ""
var _quay_lines: Array = []   # [[a, b] (Vector3, region frame), ...]: each ramp and bridge, for carrying()
var _quay_ends := {}   # node -> {end (+1, -1), down (the boat's ramp's angle, down on the bridge's end)}
var _quay_gates := {}  # node -> CollisionShape3D across the bridge's end, there while the boat's not
var _quay_at := Vector3.ZERO   # the quays' own origin (region frame)
var _ramps: Array = []   # [[a, b] (Vector3, region frame), ...]: the terminals' ramps and bridges, cut into their banks (_cut)
var _cut_for: PhysicsBody3D = null   # the rider let through the bank's ground on a ramp, and the ground's bodies
var _cut_bodies: Array = []
var _tick_at := 0
var _xf := Transform3D()        # the boat now (local), when _shown
var _shown := false
var _pose_was := Vector4(INF, INF, INF, INF)   # the boat's last pose (region frame), to move what's aboard on from
var _sail_was := -1
var _layer: CanvasLayer
var _dark: ColorRect
var _title: Label
var _sub: Label
var _place := ""


func setup(t_: AdventureTrip) -> void:
	trip = t_
	world = t_.world
	name = "FerryCrossing"
	current = self
	links = FerryLinks.of(world.roads.net.region) if world != null and world.roads != null else FerryLinks.new(null)
	FerryScenery.crew_ids.clear()
	if world != null and world.route != null and world.route.real != null:
		for f: Dictionary in world.route.real.ferries:
			FerryScenery.crew_ids[str(f["id"])] = true
	_make_card()


func _exit_tree() -> void:
	FerryScenery.crew_ids.clear()
	_uncut()
	if current == self:
		current = null


## Whether this rider's on a ferry (aboard at the ramp, sailing or tied up at the far side).
func aboard() -> bool:
	return phase in ["aboard", "sailing", "docked"]


## Whether local point `p` is on the crew's boat or its terminals' ramps and bridges out to it: on the ferry, not lost
## off the road (AdventureTrip doesn't put a bike there back on it).
func carrying(p: Vector3) -> bool:
	if aboard() or on_deck(p):
		return true
	if _quay_lines.is_empty() or world == null:
		return false
	var xz := world.route_xz(p)
	var flat := Vector2(xz[0], xz[1])
	for ab: Array in _quay_lines:
		var a: Vector3 = ab[0]
		var b: Vector3 = ab[1]
		var near := Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if near.distance_to(flat) < QUAY_NEAR:
			return true
	return false


## Whether local point `p` is on the crew's boat's deck (inside its rails, `margin` m more all round).
func on_deck(p: Vector3, margin := 0.0) -> bool:
	return _shown and FerryScenery.on_deck(_size(), _xf.affine_inverse() * p, margin)


## The crew's boat for ferry route `id` (local; as it's drawn between physics ticks when `drawn`; where it last tied up
## when it's out of sight), or null when it's another's (a bike left on its deck: Roadside.xf_in).
func deck_xf(id: String, drawn := false):
	if _shown and link >= 0 and str(links.links[link]["id"]) == id:
		return _boat.get_global_transform_interpolated() if drawn and _boat.is_inside_tree() else _xf
	if not _rest.is_empty() and str(links.links[int(_rest["link"])]["id"]) == id:
		# (out of sight, lying where it last tied up)
		var at := boat_at(int(_rest["link"]), int(_rest["node"]), 0.0, str(links.links[int(_rest["link"])]["size"]))
		var water := FerryScenery.water_of(world.roads.net, links.links[int(_rest["link"])]["pts"])
		return _local_xf(Vector4(at.x, water, at.y, at.z))
	return null


## Where `xf` (local) is on the crew's boat's deck, for a bike left standing there (Roadside.deck_of), or null when it
## isn't on it.
func deck_spot(xf: Transform3D):
	if not on_deck(xf.origin, 0.5) or link < 0:
		return null
	var on := _xf.affine_inverse() * xf
	var fwd := -on.basis.z
	return {"id": str(links.links[link]["id"]), "x": on.origin.x, "y": maxf(on.origin.y, float(FerryScenery.BOATS[_size()]["deck"])),
		"z": on.origin.z, "yaw": atan2(-fwd.x, -fwd.z)}


## Marks the end of a network snapshot's place on the crew's ferry's deck (deck_tag).
const DECK_TAG := -77778.0


## What goes on the end of this game's network snapshot `state` (a walker's [0, x, y, z, ...] or a rider's [1, bike,
## x, y, z, ...]) while it's aboard: [x, y, z (on the deck, the boat's frame), the sailing, DECK_TAG]; else nothing.
func deck_tag(state: PackedFloat32Array) -> PackedFloat32Array:
	var at := _state_at(state)
	if at < 0 or not aboard() or sailing.is_empty():
		return PackedFloat32Array()
	var p := Vector3(state[at], state[at + 1], state[at + 2])
	if not on_deck(p, 0.5):
		return PackedFloat32Array()
	var d := _xf.affine_inverse() * p
	return PackedFloat32Array([d.x, d.y, d.z, float(int(sailing["sail"])), DECK_TAG])


## A mate's snapshot `state` (in this game's frame) at its place on the deck `deck` (deck_tag's) on this game's
## boat, when it's showing the same sailing: each game sails it from when it hears it's left, so the boats are a
## moment apart, and a mate's own place in the world would be off the end of this one. (`state` as it is otherwise.)
func put_on_deck(state: PackedFloat32Array, deck: PackedFloat32Array) -> PackedFloat32Array:
	var at := _state_at(state)
	if at < 0 or deck.size() < 4 or not _shown or int(sailing.get("sail", -1)) != int(deck[3]):
		return state
	var p := _xf * Vector3(deck[0], deck[1], deck[2])
	var out := state.duplicate()
	out[at] = p.x
	out[at + 1] = p.y
	out[at + 2] = p.z
	return out


static func _state_at(state: PackedFloat32Array) -> int:
	if state.size() >= 4 and state[0] < 0.5:
		return 1
	if state.size() >= 5 and state[0] < 1.5:
		return 2
	return -1


## How far on (m) a mate's snapshot drawn `delay` s behind (NetTimeline, RemotePlayer) is to be drawn when it's at local
## `p` on the crew's boat's deck: the boat's moved on that far since (and they with it).
static func lead(p: Vector3, delay: float) -> Vector3:
	return deck_velocity(p) * delay


## How fast whatever's at local `p` is carried along by the crew's boat (m/s): its velocity on its deck, else nothing.
static func deck_velocity(p: Vector3) -> Vector3:
	if current == null or not current.on_deck(p, 1.0):
		return Vector3.ZERO
	return current.velocity


## The HUD's line while there's something to say about a ferry ("" for nothing).
func hud_text() -> String:
	match phase:
		"asked":
			return "Going aboard..."
		"aboard":
			var waiting := AdventureCrew.ferry_waiting(sailing, Shed.crew, Adventure.riders_out())
			if waiting.is_empty():
				return "Aboard %s: casting off." % links.title(link)
			return "Aboard %s, waiting for %s." % [links.title(link), " and ".join(waiting)]
		"sailing":
			return "Crossing on %s: %s." % [links.title(link), _place] if _place != "" else "Crossing on %s." % links.title(link)
		"docked":
			return "Tied up at %s: ride off down the ramp." % (_place if _place != "" else "the far side")
	if trip == null or trip.focus_points().is_empty():
		return ""
	var near := _terminal_near(trip.focus_points()[0], HINT_R)
	if near.is_empty() or int(near["node"]) != _off_at:
		_off_at = -1
	if not near.is_empty() and _off_at < 0:
		if int(near["link"]) == link and int(_docked().x) == int(near["node"]):
			return "%s: ride up the ramp and onto the deck to go aboard." % links.title(int(near["link"]))
		return "%s: the boat's away. It'll be back at the ramp shortly." % links.title(int(near["link"]))
	return ""


func _physics_process(delta: float) -> void:
	if world == null or world.roads == null or links.is_empty() or trip == null:
		return
	var now := Time.get_ticks_msec()
	var got := AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {}))
	if Shed.is_authority() and not got.is_empty() and now - _tick_at > 500:
		_tick_at = now
		Shed.request({"a": "adventure_ferry_tick"})
	_follow(got, delta)
	var pose := _pose()
	var was := _pose_was
	var key := "%s|%d" % [_size(), link]
	var same := key == _boat_key and (int(sailing.get("sail", -1)) == _sail_was)
	_tick_boat(pose, delta)
	if same and was.x != INF and _shown:
		_carry(was, delta, t >= 0.0)
	_sail_was = int(sailing.get("sail", -1))
	_tick_phase(got, now)
	_tick_card()
	_cut()


## The sailing to show (the crew's, else the crew's boat waiting at the ramp of the ferry ahead) and where its boat is.
func _follow(got: Dictionary, delta: float) -> void:
	if not got.is_empty():
		var same := int(got["sail"]) == int(sailing.get("sail", -1))
		if not same:
			t = -1.0
			_place = ""
		sailing = got
		link = links.find(str(got["id"]), int(got["from"]), int(got["to"]))
		if int(got["departs"]) != 0:
			t = 0.0 if t < 0.0 else t + delta
		else:
			t = -1.0
		if link < 0:
			sailing = {}
		elif t >= 0.0:
			# (where it'll lie once it's in, as long as it's the ferry ahead: it waits there for the next sailing)
			_rest = {"node": int(got["to"]), "link": link}
		return
	if not sailing.is_empty() and t >= 0.0:
		_rest = {"node": int(sailing["to"]), "link": link}
	sailing = {}
	t = -1.0
	link = _ferry_ahead()


## The link of the ferry ahead whose ramp the crew's boat waits at (-1 for none near): the one it last tied up at while
## that terminal's the nearest, else the route's next crossing, or the nearest terminal's.
func _ferry_ahead() -> int:
	var at: Vector3 = trip.focus_points()[0]
	var near := _terminal_near(at, SHOW_R)
	if near.is_empty():
		return -1
	if not _rest.is_empty() and int(_rest["node"]) == int(near["node"]):
		return int(_rest["link"])
	return int(near["link"])


## The terminal nearest local point `p` within `reach` (m): {node, link (the one to board there)}, {} for none. The
## link is the route's crossing from there where there is one, else the one whose far side is nearest the destination.
func _terminal_near(p: Vector3, reach: float) -> Dictionary:
	var xz := world.route_xz(p)
	var at := Vector2(xz[0], xz[1])
	var r := links.region
	var best := -1
	var best_d := reach
	for n: int in links.at:
		var d := r.node_pos[n].distance_to(at)
		if d < best_d:
			best_d = d
			best = n
	if best < 0:
		return {}
	var choice := -1
	var dest := Vector2.INF
	if world.route != null and world.route.real != null:
		var pins: PackedInt32Array = world.route.real.pin_nodes
		if not pins.is_empty():
			dest = r.node_pos[pins[pins.size() - 1]]
		for f: Dictionary in world.route.real.ferries:
			if int(f["from"]) == best:
				choice = links.find(str(f["id"]), best, int(f["to"]))
	if choice < 0:
		var best_far := INF
		for i in (links.at[best] as PackedInt32Array):
			var far := r.node_pos[links.other_end(i, best)].distance_to(dest) if dest != Vector2.INF else float(i)
			if far < best_far:
				best_far = far
				choice = i
	return {"node": best, "link": choice}


# ---------------------------------------------------------------------------- the crossing's timeline

## How long sailing `ferry` (AdventureCrew's) takes from the ramp going up to tying up (s).
static func total_of(ferry: Dictionary) -> float:
	return PREP + float(ferry.get("seconds", FerryLinks.CROSS_LEAST)) + DOCK


## Where a boat crossing a route `m` m long in `seconds` is, `tau` s after it left the ramp: {s (metres along the
## route), fade (how dark the screen is, 0 to 1: a long route's open water), moving}. A route the boat can sail in the
## time at about its speed is sailed all the way, easing out and in; a longer one is sailed out of one harbour and
## into the other at that speed, the open water between passed over in the dark.
static func timeline(m: float, seconds: float, tau: float) -> Dictionary:
	var u := clampf(tau - PREP, 0.0, seconds)
	if m <= FerryLinks.SPEED * seconds * 1.15:
		var k := u / seconds
		return {"s": m * k * k * k * (k * (k * 6.0 - 15.0) + 10.0), "fade": 0.0, "moving": tau > PREP and u < seconds}
	var half := seconds * 0.5
	var s := _out(u) if u < half else m - _out(seconds - u)
	return {"s": clampf(s, 0.0, m), "fade": clampf(1.0 - absf(u - half) / FADE, 0.0, 1.0), "moving": tau > PREP and u < seconds}


## How far a boat's gone `tau` s out from rest at FerryLinks.SPEED (speeding up over ACCEL).
static func _out(tau: float) -> float:
	var v := FerryLinks.SPEED
	if tau < ACCEL:
		return 0.5 * v / ACCEL * tau * tau
	return v * (tau - ACCEL * 0.5)


## Where the middle of a `size` boat crossing link `i` stands `s` m along it, as Vector3(x, z, heading) in the region
## frame: from its ramp end (its end at the end of the terminal's ramp, or on from there where it's afloat) to the
## other's, its bow towards the link's b end all the way (it never turns round).
func boat_at(i: int, from: int, s: float, size: String) -> Vector3:
	var line := links.line_from(i, from)
	var back := links.line_from(i, links.other_end(i, from))
	var m := float(links.links[i]["m"])
	var half := float((FerryScenery.BOATS[size] as Dictionary)["len"]) * 0.5
	var net: RoadNet = world.roads.net if world != null and world.roads != null else null
	var height: Callable = net.height if net != null else Callable()
	var level := FerryScenery.water_of(net, links.links[i]["pts"]) if net != null else 0.0
	var p := FerryScenery.along(line, FerryScenery.sailed(m, s, FerryScenery.lies(line, height, level) + half,
		FerryScenery.lies(back, height, level) + half))
	if from == int(links.links[i]["b"]):
		p.z += PI
	return p


## Which end of the boat (+1 its stern, -1 its bow) is towards terminal `node` of its link.
func end_at(node: int) -> float:
	return 1.0 if link >= 0 and node == int(links.links[link]["a"]) else -1.0


## Where the boat's tied up and how far its ramp there is down: Vector2(the terminal's node, 0 up .. 1 down), x -1 at sea.
func _docked() -> Vector2:
	if link < 0:
		return Vector2(-1, 0)
	if sailing.is_empty() or t < 0.0:
		return Vector2(_rest_from(), 1.0)
	var seconds := float(sailing.get("seconds", links.seconds(link)))
	if t < PREP:
		return Vector2(int(sailing["from"]), 1.0 - clampf(t / RAMP_MOVE, 0.0, 1.0))
	if t < PREP + seconds:
		return Vector2(-1, 0)
	return Vector2(int(sailing["to"]), clampf((t - PREP - seconds) / RAMP_MOVE, 0.0, 1.0))


## The terminal a boat with no sailing (or one not yet away) lies at: the sailing's own, else where it last tied up,
## else the end nearest this rider.
func _rest_from() -> int:
	if not sailing.is_empty():
		return int(sailing["from"])
	var l: Dictionary = links.links[link]
	if not _rest.is_empty() and int(_rest["link"]) == link:
		return int(_rest["node"])
	var xz := world.route_xz(trip.focus_points()[0])
	var me := Vector2(xz[0], xz[1])
	return int(l["a"]) if links.region.node_pos[int(l["a"])].distance_to(me) <= links.region.node_pos[int(l["b"])].distance_to(me) else int(l["b"])


# ---------------------------------------------------------------------------- the boat and what's aboard

func _size() -> String:
	return str(links.links[link]["size"]) if link >= 0 else "roro"


## The boat's pose now (region frame: x, y, z and heading in w), or Vector4(INF...) for no boat to show.
func _pose() -> Vector4:
	if link < 0:
		return Vector4(INF, INF, INF, INF)
	var from := int(sailing["from"]) if not sailing.is_empty() else _rest_from()
	var m := float(links.links[link]["m"])
	var s := 0.0
	if t >= 0.0:
		s = float(timeline(m, float(sailing.get("seconds", links.seconds(link))), t)["s"])
	var p := boat_at(link, from, s, _size())
	var water := FerryScenery.water_of(world.roads.net, links.links[link]["pts"])
	return Vector4(p.x, water, p.y, p.z)


func _local_xf(pose: Vector4) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -pose.w), world.to_local_pos(pose.x, pose.y, pose.z))


## Puts the boat where `pose` says (hiding it for none), its ramps up or down, and the terminals' ramps under it.
func _tick_boat(pose: Vector4, delta: float) -> void:
	if pose.x == INF:
		if _boat != null:
			_boat.visible = false
			_body.process_mode = Node.PROCESS_MODE_DISABLED
		if _quays != null:
			_quays.visible = false
			_quays.process_mode = Node.PROCESS_MODE_DISABLED
		if _quay_gates.size() > 0:
			for g: CollisionShape3D in _quay_gates.values():
				g.disabled = false
		_shown = false
		_pose_was = Vector4(INF, INF, INF, INF)
		velocity = Vector3.ZERO
		return
	var key := "%s|%d" % [_size(), link]
	if _boat == null or _boat_key != key:
		_make_boat(pose)
		_boat_key = key
	var was := _xf if _shown else Transform3D()
	var fresh := not _shown
	_xf = _local_xf(pose)
	_boat.visible = true
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	_boat.global_transform = _xf
	if fresh or was.origin.distance_to(_xf.origin) > 20.0:
		_boat.reset_physics_interpolation()   # (shown again, or the world's origin moved: there at once)
	velocity = Vector3.ZERO
	if not fresh and _pose_was.x != INF and delta > 0.0:
		var before := _local_xf(_pose_was)
		var step := _xf.origin - before.origin
		velocity = step / delta if step.length() < 40.0 else Vector3.ZERO
	_pose_was = pose
	_shown = true
	# The ramps: the one at the terminal it's tied up at down (on the bridge out to it), the others up as its gates.
	var dock := _docked()
	for end: float in [1.0, -1.0]:
		var open := dock.y if dock.x >= 0 and end_at(int(dock.x)) == end else 0.0
		var down := float((_quay_ends.get(int(dock.x), {}) as Dictionary).get("down", -0.15)) if dock.x >= 0 else -0.15
		var flap: Node3D = _flaps[end]
		flap.basis = Basis(Vector3.UP, PI if end > 0.0 else 0.0) * Basis(Vector3.RIGHT, lerpf(FerryScenery.FLAP_UP, down, smoothstep(0.0, 1.0, open)))
		(_gates[end] as CollisionShape3D).disabled = open > 0.5
	_tick_quays()
	for node: int in _quay_gates:
		# (the bridge's end barred while the boat's not tied up there with its ramp down)
		(_quay_gates[node] as CollisionShape3D).disabled = int(dock.x) == node and dock.y > 0.5


## The crew's boat for this link: its model (its own ramps, to raise and lower), solid where it's solid.
func _make_boat(pose: Vector4) -> void:
	if _boat != null:
		_boat.queue_free()
	_boat = MeshInstance3D.new()
	_boat.name = "CrewFerry"
	# (moved each physics tick, with the bikes aboard: drawn eased between them, as they are, see Bike._ready)
	_boat.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var region_id := str(RegionKit.at_frame(links.region.frame_lat, links.region.frame_lon, pose.x, pose.z).get("region", ""))
	var kit := SceneryStreamer.kit("ferry", region_id)
	_boat.mesh = FerryScenery.boat_mesh(_size(), kit, false)
	world.add_child(_boat)
	_body = StaticBody3D.new()
	_body.name = "Deck"
	_body.set_meta("surface", "tarmac")
	_boat.add_child(_body)
	for part: Array in FerryScenery.solids(_size()):
		_add_box(_body, Transform3D(Basis.IDENTITY, part[0]), part[1])
	var b: Dictionary = FerryScenery.BOATS[_size()]
	var lane: Vector2 = b["lane"]
	_flaps = {}
	_gates = {}
	for end: float in [1.0, -1.0]:
		var hinge := FerryScenery.hinge(_size(), end)
		var flap := MeshInstance3D.new()
		flap.mesh = FerryScenery.flap_mesh(_size(), kit)
		flap.position = hinge
		_boat.add_child(flap)
		_flaps[end] = flap
		# (its gate: the raised ramp across the deck's end)
		_gates[end] = _add_box(_body, Transform3D(Basis.IDENTITY, hinge + Vector3(0, 1.0, end * 0.6)),
			Vector3(lane.y - lane.x + 0.2, 2.0, 0.6))
	_quay_key = ""


static func _add_box(body: Node3D, xf: Transform3D, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xf
	body.add_child(cs)
	return cs


## The terminals' ramps (the scenery draws them: these make them solid) and, where the boat lies further out than the
## ramp reaches, a bridge on out to it at its deck's height, at both ends of the boat's link: made once a link (again
## while the ground there's still coming in), kept in the region frame as the world's origin moves.
func _tick_quays() -> void:
	if _quays == null:
		_quays = Node3D.new()
		_quays.name = "FerryQuays"
		world.add_child(_quays)
	var key := "%s|%d" % [_size(), link]
	if _quay_key != key:
		_build_quays()
		if _quay_lines.size() >= 2:
			_quay_key = key
	_quays.visible = true
	_quays.process_mode = Node.PROCESS_MODE_INHERIT
	_quays.global_position = world.to_local_pos(_quay_at.x, 0.0, _quay_at.z)


func _build_quays() -> void:
	for c in _quays.get_children():
		c.queue_free()
	_quay_lines.clear()
	_ramps.clear()
	_quay_ends.clear()
	_quay_gates.clear()
	var l0: Dictionary = links.links[link]
	var a0 := links.region.node_pos[int(l0["a"])]
	_quay_at = Vector3(a0.x, 0.0, a0.y)
	var body := StaticBody3D.new()
	body.set_meta("surface", "tarmac")
	_quays.add_child(body)
	var net := world.roads.net
	var b: Dictionary = FerryScenery.BOATS[_size()]
	var lane: Vector2 = b["lane"]
	var lane_w := lane.y - lane.x
	var l: Dictionary = links.links[link]
	for node: int in [int(l["a"]), int(l["b"])]:
		var ramp := FerryScenery.ramp_of(net, links, link, node)
		if ramp.is_empty():
			continue
		var foot: Vector3 = ramp["foot"]
		var tip: Vector3 = ramp["tip"]
		_solid_span(body, foot, tip, FerryScenery.RAMP_W, false, RAIL_FROM)
		_quay_lines.append([foot, tip])
		_ramps.append([foot, tip])
		_quay_lines.append([ramp["road"], foot])   # (over the shore to it, where it starts out from the bank)
		# (eased onto the road: a slipway's road climbs away steeply from where the ramp's met it, and the crease
		# between them beached a bike on its belly, its back tyre spinning; a chord over it, half the bend either side)
		var inland := foot - tip
		inland.y = 0.0
		var up_road := foot + inland.normalized() * EASE
		var on := net.locate(up_road.x, up_road.z)
		up_road.y = (float(on["y"]) if not on.is_empty() and bool(on.get("on_road", false)) else float(net.height.call(up_road.x, up_road.z))) + 0.02
		if not is_nan(up_road.y):
			_solid_span(body, up_road, foot.lerp(tip, EASE / maxf(foot.distance_to(tip), EASE)), FerryScenery.RAMP_W, false, INF)
		# Out to the boat where it lies there: to the hinge of its ramp at that end.
		var at := boat_at(link, node, 0.0, _size())
		var water := FerryScenery.water_of(net, l["pts"])
		var berth := Transform3D(Basis(Vector3.UP, -at.z), Vector3(at.x, water, at.y))
		var end := end_at(node)
		var hinge := berth * FerryScenery.hinge(_size(), end)
		var reach := berth * (FerryScenery.hinge(_size(), end) + Vector3(0, 0, end * FerryScenery.FLAP_LEN))
		if tip.distance_to(hinge) > FerryScenery.FLAP_LEN + 1.0:
			_solid_span(body, tip, reach, minf(FerryScenery.RAMP_W, lane_w + 1.0), true, 0.0, RAIL_SHORT)
			_quay_lines.append([tip, reach])
			_ramps.append([tip, reach])
		# (the boat's own ramp, down flat from its hinge, the bridge's end on it, room to turn on; barred while the
		# boat's away)
		_solid_span(body, reach, hinge, lane_w + 2.0)
		_ramps.append([reach, hinge])
		var out_way := (reach - hinge).normalized()
		var gate_xf := Transform3D(Basis.looking_at(out_way, Vector3.UP), reach + out_way * -0.4 + Vector3.UP * 1.0)
		_quay_gates[node] = _add_box(body, Transform3D(gate_xf.basis, gate_xf.origin - _quay_at), Vector3(lane_w + 1.5, 2.0, 0.5))
		_quay_ends[node] = {"end": end, "down": 0.0}


## Lets this rider (on the bike, or on foot) through the land's ground while on a terminal's ramp: the real heights
## by the shore are coarse, and stand up over a ramp running down into the bank in places (a bike ridden onto it
## stopped dead); the ramp's cut through it, as a real one is. Let back once off it.
func _cut() -> void:
	var me: PhysicsBody3D = null
	if trip.main.bike != null:
		me = trip.main.bike
	elif trip.main.walker != null:
		me = trip.main.walker
	if me != _cut_for or me == null or not _on_ramp(me.global_position):
		_uncut()
		if me == null or not _on_ramp(me.global_position):
			return
	_cut_for = me
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = CUT_R
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, me.global_position)
	q.exclude = [me.get_rid()]
	for h: Dictionary in me.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = h["collider"]
		if c is PhysicsBody3D and world.land != null and world.land.is_ancestor_of(c) and not _cut_bodies.has(c):
			me.add_collision_exception_with(c)
			_cut_bodies.append(c)
			if me is Bike:
				(me as Bike).let_through.append((c as PhysicsBody3D).get_rid())


func _uncut() -> void:
	if is_instance_valid(_cut_for):
		for c: Object in _cut_bodies:
			if is_instance_valid(c):
				_cut_for.remove_collision_exception_with(c)
		if _cut_for is Bike:
			(_cut_for as Bike).let_through.clear()
	_cut_for = null
	_cut_bodies.clear()


## Whether local `p` is over one of the terminals' ramps or bridges (in its width, end to end).
func _on_ramp(p: Vector3) -> bool:
	if _ramps.is_empty():
		return false
	var xz := world.route_xz(p)
	var at := Vector2(xz[0], xz[1])
	for ab: Array in _ramps:
		var a := Vector2((ab[0] as Vector3).x, (ab[0] as Vector3).z)
		var b := Vector2((ab[1] as Vector3).x, (ab[1] as Vector3).z)
		var along := b - a
		var f := (at - a).dot(along) / maxf(along.length_squared(), 0.01)
		if f > -0.02 and f < 1.02 and Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < FerryScenery.RAMP_W * 0.5:
			return true
	return false


## A solid deck from `a` to `b` (region frame, on its surface) `w` wide, with rails along both sides (from `rails_from` m
## on from `a`, to `rails_short` m short of `b`); drawn too when
## `drawn` (a bridge: the scenery draws the ramps), on piles down into the water.
func _solid_span(body: StaticBody3D, a: Vector3, b: Vector3, w: float, drawn := false, rails_from := 0.0, rails_short := 0.0) -> void:
	var along := b - a
	var long := along.length()
	if long < 0.05:
		return
	var z := -along / long
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	var basis := Basis(x, y, z)
	a -= _quay_at
	b -= _quay_at
	var mid := (a + b) * 0.5
	_add_box(body, Transform3D(basis, mid - y * 0.3), Vector3(w, 0.6, long + 0.2))
	if long > rails_from + rails_short + 0.5:
		var rail_mid := a.lerp(b, (rails_from + long - rails_short) * 0.5 / long)
		for side: float in [-1.0, 1.0]:
			_add_box(body, Transform3D(basis, rail_mid + x * side * (w * 0.5 - 0.06) + y * 0.5), Vector3(0.12, 1.0, long - rails_from - rails_short))
	if not drawn:
		return
	var deck := MeshInstance3D.new()
	deck.mesh = FerryScenery.mesh("ramp")
	deck.transform = Transform3D(basis * Basis.from_scale(Vector3(w / FerryScenery.RAMP_W, 1.0, long / FerryScenery.RAMP_LEN)), a)
	_quays.add_child(deck)
	var piles := maxi(2, int(long / 9.0) + 1)
	var pile := BoxMesh.new()
	pile.size = Vector3(0.5, 6.0, 0.5)
	for k in piles:
		var at := a.lerp(b, (k + 0.5) / piles)
		for side: float in [-1.0, 1.0]:
			var p := MeshInstance3D.new()
			p.mesh = pile
			p.position = at + x * side * (w * 0.5 - 0.3) - Vector3.UP * 3.4
			_quays.add_child(p)


## Moves on whatever's on the boat's deck as the boat moved since its pose `was` (this rider: on the bike, or on foot);
## anyone aboard who's gone over the side is put back on deck. A jump with no sailing under way (a boat put at another
## terminal) carries nothing.
func _carry(was: Vector4, delta: float, under_way: bool) -> void:
	var before := _local_xf(was)
	var d := _xf * before.affine_inverse()
	var moved := d.origin.length() > 0.0005 or absf(was.w - _pose_was.w) > 0.00001
	if not moved:
		return
	if not under_way and d.origin.length() > 1.0:
		return
	var main := trip.main
	if main == null:
		return
	var size := _size()
	var big := d.origin.length() > 20.0
	if main.bike != null:
		var bike: Bike = main.bike
		if FerryScenery.on_deck(size, before.affine_inverse() * bike.global_position):
			var xf := d * bike.global_transform
			bike.global_transform = xf
			PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
			bike.linear_velocity = d.basis * bike.linear_velocity
			if big:
				bike.reset_physics_interpolation()
				main.camera.snap()
	elif main.walker != null:
		var w: Walker = main.walker
		if FerryScenery.on_deck(size, before.affine_inverse() * w.global_position):
			w.global_position = d * w.global_position
			w.rotation.y -= wrapf(_pose_was.w - was.w, -PI, PI)
			w.velocity = d.basis * w.velocity


## Going aboard, waiting at the ramp, sailing, tied up, and off: this rider's side of the crew's sailing.
func _tick_phase(got: Dictionary, now: int) -> void:
	var me := _me()
	var on := me != null and on_deck(me.global_position)
	var dock := _docked()
	match phase:
		"":
			if on and not _was_on and dock.x >= 0 and dock.y > 0.5 and not trip.crew_hold():
				var from := int(dock.x)
				var why := AdventureCrew.board_check(got, Shed.me(), str(links.links[link]["id"]), from, Adventure.riders_out())
				if why == "":
					phase = "asked"
					_asked_at = now
					Shed.request({"a": "adventure_ferry_board", "id": str(links.links[link]["id"]), "from": from,
						"to": links.other_end(link, from), "seconds": snappedf(links.seconds(link), 0.1)})
				else:
					trip.main.hud.flash(why, 2.5, true)
		"asked":
			if not got.is_empty() and (got["aboard"] as Dictionary).has(Shed.me()):
				phase = "aboard"
			elif now - _asked_at > 3000:
				phase = ""   # (the host said no: the crew's on another ferry, or it's just left)
		"aboard", "sailing", "docked":
			if got.is_empty() or int(got["sail"]) != int(sailing.get("sail", -1)) or not (got["aboard"] as Dictionary).has(Shed.me()):
				phase = ""   # (the sailing's gone: the ride ended, or the host cleared it)
			elif phase == "aboard" and t >= 0.0:
				phase = "sailing"
			elif phase == "aboard" and not on:
				phase = ""   # (off again before it sails)
				Shed.request({"a": "adventure_ferry_off", "sail": int(sailing["sail"])})
			elif phase == "sailing" and int(dock.x) == int(sailing["to"]):
				phase = "docked"
			elif phase == "docked" and not on and dock.y > 0.5:
				phase = ""   # (ridden off on the far side)
				_landed()
			if phase in ["aboard", "sailing", "docked"] and not on and me != null:
				_overboard(me)
				on = on_deck(me.global_position)
	_was_on = on


## This rider's bike, or them on foot.
func _me() -> Node3D:
	if trip.main == null:
		return null
	return trip.main.bike if trip.main.bike != null else trip.main.walker


## Off on the far side: the host's told (it clears the sailing once all are), the sat nav on from there.
func _landed() -> void:
	if sailing.is_empty():
		return
	Shed.request({"a": "adventure_ferry_landed", "sail": int(sailing["sail"])})
	_off_at = int(sailing["to"])
	var nav := NetNav.of(world)
	var to := int(sailing["to"])
	if world.route != null and world.route.real != null:
		for f: Dictionary in world.route.real.ferries:
			if str(f["id"]) == str(sailing["id"]) and int(f["to"]) == to:
				nav.landed(int(f["step"]))


## Aboard, but not on the deck: gone over the side (well under it, by the boat) and put back on it.
func _overboard(me: Node3D) -> void:
	var local := _xf.affine_inverse() * me.global_position
	var b: Dictionary = FerryScenery.BOATS[_size()]
	if local.y > float(b["deck"]) - OVERBOARD or absf(local.x) > float(b["beam"]) + 30.0 or absf(local.z) > float(b["half"]) + 30.0:
		return
	var aboard: Array = (sailing.get("aboard", {}) as Dictionary).keys()
	aboard.sort()
	var spot := _xf * Transform3D(Basis.IDENTITY, FerryScenery.slot_at(_size(), maxi(0, aboard.find(Shed.me()))))
	if me is Bike:
		(me as Bike).place(spot.origin, spot.basis.get_euler().y)
		trip.main.camera.snap()
	elif me is Walker:
		(me as Walker).place(spot)
	trip.main.hud.flash("Back aboard.", 2.0, true)


## Where a bike's put off at terminal junction `node` (local): on the road leading inland from it, LAND_IN m (and
## `back` more) along, facing along it; on further up it while the road's still under the water there (`dry`).
func landing_xf(node: int, back := 0.0, dry := true) -> Transform3D:
	var net := world.roads.net
	var r := net.region
	var water := Vector2.ZERO
	for i in (links.at.get(node, PackedInt32Array()) as PackedInt32Array):
		var line := links.line_from(i, node)
		water += (line[mini(2, line.size() - 1)] - r.node_pos[node]).normalized()
	var best := -1
	var best_dot := INF
	for e in r.adjacent[node]:
		var line := r.line_from(e, node)
		var d := (line[mini(1, line.size() - 1)] - line[0]).normalized()
		if d.dot(water) < best_dot:
			best_dot = d.dot(water)
			best = e
	if best < 0:
		var p := r.node_pos[node]
		return Transform3D(Basis.IDENTITY, world.to_local_pos(p.x, float(net.height.call(p.x, p.y)), p.y))
	var len := r.edge_len[best]
	var level := 0.0
	for i in (links.at.get(node, PackedInt32Array()) as PackedInt32Array):
		level = maxf(level, FerryScenery.water_of(net, links.links[i]["pts"]))
	# (on up the road till it's clear of the water: a slipway runs on down under it)
	var s := minf(LAND_IN + back, len * 0.8)
	var p := Vector2.ZERO
	var h := 0.0
	var y := NAN
	while true:
		var along := s if r.edge_a[best] == node else len - s
		p = net.point_at(best, along)
		h = net.heading_at(best, along) + (0.0 if r.edge_a[best] == node else PI)
		var on := net.locate(p.x, p.y, best)
		y = float(on["y"]) if not on.is_empty() else float(net.height.call(p.x, p.y))
		if not dry or (not is_nan(y) and y >= level + DRY) or s + 4.0 > minf(len * 0.9, LAND_IN + back + DRY_MOST):
			break
		s += 4.0
	if is_nan(y):
		y = 2.0
	var lift: float = (trip.main.bike.build.rear_radius + 0.05) if trip.main != null and trip.main.bike != null else 0.4
	return Transform3D(Basis(Vector3.UP, -h), world.to_local_pos(p.x, y + lift, p.y))


# ---------------------------------------------------------------------------- the far side's name, the open water's dark

func _tick_card() -> void:
	if phase in ["sailing", "docked"] and t >= 0.0 and link >= 0:
		var left := total_of(sailing) - DOCK - t
		var tl := timeline(float(links.links[link]["m"]), float(sailing.get("seconds", 60.0)), t)
		_dark.color.a = float(tl["fade"])
		if _place == "":
			_place = _far_name()
		var show := clampf(minf((NAME_FROM - left) / 1.0, (left - NAME_TO) / 1.0), 0.0, 1.0)
		_title.text = _place
		_sub.text = "%s  ·  %s" % [links.title(link), _length_text(float(links.links[link]["m"]))]
		_title.get_parent().modulate.a = show
		_layer.visible = true
	else:
		_layer.visible = false
		_dark.color.a = 0.0


## The far side's name: the nearest named place to the terminal the sailing lands at, else the route's own.
func _far_name() -> String:
	var r := links.region
	var to := int(sailing.get("to", -1))
	if to < 0:
		return ""
	var at := r.node_pos[to]
	var best := ""
	var best_d := 4000.0
	for pl: Dictionary in r.places:
		var d := Vector2(float(pl["x"]), float(pl["z"])).distance_to(at)
		if d < best_d:
			best_d = d
			best = str(pl["name"])
	return best if best != "" else links.title(link)


static func _length_text(m: float) -> String:
	if Units.imperial():
		var mi := m / 1609.344
		return "%.1f miles across" % mi if mi >= 0.95 else "%d yards across" % (roundi(m * 1.0936 / 10.0) * 10)
	return "%.1f km across" % (m / 1000.0) if m >= 950.0 else "%d m across" % (roundi(m / 10.0) * 10)


## The route panel's line for one of a pack's crossings (RealPack.ferries' row).
static func panel_line(f: Dictionary) -> String:
	var mins := maxi(1, roundi(float(f.get("seconds", 60.0)) / 60.0))
	return "By ferry: %s, %s (%s aboard)." % [str(f.get("name", "the ferry")), _length_text(float(f.get("m", 0.0))),
		"about a minute" if mins <= 1 else "%d minutes" % mins]


func _make_card() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	_dark = ColorRect.new()
	_dark.color = Color(0, 0, 0, 0)
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_dark)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-300, 80)
	box.size = Vector2(600, 120)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	_layer.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 46)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	box.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 20)
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	box.add_child(_sub)
