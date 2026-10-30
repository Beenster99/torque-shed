class_name FerryCrossing
extends Node
## This player's side of crossing on a ferry on the network ride (Ride Anywhere v2, phase D round 3, D7): the crew's
## boat at the ramp of the ferry ahead, going aboard (ride slowly to the end of the road at the water: the bike's taken
## up the ramp to its place on the deck and held there), the crossing itself (about a minute, the camera pulled back
## to take in the boat, the water and the far shore, the place's name coming up as you near it, as at an arrival),
## and riding off on the other side. Simon's settled choice: a short real crossing, not a cut; on a long route the
## boat sails out of one harbour and into the other, the open water between passed over in a moment's dark.
##
## The sailing is the crew's (Shed.adventure "ferry", see AdventureCrew): the host lets it go when everyone's aboard,
## or after a wait once half are, as the ride's start waits; each game sails it from when it hears it's left, along
## the route's one fixed line (FerryLinks), so the crew sees the same boat in the same place. A mate left behind sees
## it go, and the next sailing's boat is at the ramp once it's across.
##
## Nothing here touches a road or adds collision: the boat and its ramp are to look at; the bike is held on the deck
## by this game while it's aboard (frozen, its velocity the boat's, so a mate's game draws it moving smoothly).

## Going aboard: ride this slowly (m/s) within this far (m) of the end of the road at a terminal, or of the boat.
const BOARD_SPEED := 4.5
const BOARD_R := 22.0
## The crew's boat is shown at the ramp of a ferry ahead once a rider's this near its terminal (m).
const SHOW_R := 2500.0
## The ramp going up and the horn before it sails, and tying up at the far side (s).
const PREP := 4.0
const DOCK := 4.0
## Easing the bike up the ramp to its place on the deck (s).
const BOARD_EASE := 1.5
## A long route's boat speeds up and slows down over this long (s), and the dark over its open water lasts this long
## either side of the middle (s).
const ACCEL := 8.0
const FADE := 1.6
## The bike's put on the road this far (m) inland of the far terminal, and held till there's ground under it, this
## long at most (s).
const LAND_IN := 9.0
const LAND_WAIT := 6.0
## Each rider after the first is put this much (m) further on up the road.
const LAND_GAP := 6.0
## A rider's put on the road this high (m) over the ferry's water at least, this much (m) further on at most.
const DRY := 0.6
const DRY_MOST := 120.0
## A rider landed at a terminal must ride this far (m) from it before its ramp takes them aboard again (one stopping
## just off the boat isn't asking to go back).
const OFF_CLEAR := 60.0
## The place's name is up over this stretch before the far side (s from the end of the sailing).
const NAME_FROM := 14.0
const NAME_TO := 3.0

var trip: AdventureTrip
var world: AdventureWorld
var links: FerryLinks
## What this player's doing: "" (not on a ferry), "asked" (gone onto the ramp, the host to say), "aboard" (on deck, at
## the ramp), "sailing", "landing" (put on the far side's road, waiting for its ground).
var phase := ""
## The sailing being shown (AdventureCrew.sanitize_ferry's), its link, and how far into it this game is (s from
## when it heard it left; -1 while it's at the ramp).
var sailing := {}
## The terminal this game's rider was last landed at (OFF_CLEAR).
var _off_node := -1
var link := -1
var t := -1.0
var _asked_at := 0
var _ease := 0.0
var _ease_from := Transform3D()
var _land_xf := Transform3D()
var _land_t := 0.0
var _tick_at := 0
var _boat: MeshInstance3D
var _boat_key := ""
var _cam: Camera3D
var _layer: CanvasLayer
var _dark: ColorRect
var _title: Label
var _sub: Label
var _place := ""
var _last_pose := Vector3.INF   # the boat's last (x, y, z), region frame, for its velocity


func setup(t_: AdventureTrip) -> void:
	trip = t_
	world = t_.world
	name = "FerryCrossing"
	links = FerryLinks.of(world.roads.net.region) if world != null and world.roads != null else FerryLinks.new(null)
	FerryScenery.crew_ids.clear()
	if world != null and world.route != null and world.route.real != null:
		for f: Dictionary in world.route.real.ferries:
			FerryScenery.crew_ids[str(f["id"])] = true
	_make_card()


func _exit_tree() -> void:
	FerryScenery.crew_ids.clear()
	_end_camera()


## Whether this game's holding the bike (aboard, sailing or just landed): no keeping it on the road meanwhile, and its
## controls held (AdventureTrip.crew_hold).
func holding() -> bool:
	return phase in ["aboard", "sailing", "landing"]


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
		"landing":
			return "Tying up..."
	var near := _terminal_near(trip.focus_points()[0] if trip != null else Vector3.ZERO, 60.0)
	if not near.is_empty():
		return "%s: ride slowly up to the ramp to go aboard." % links.title(int(near["link"]))
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
	var bike: Bike = trip.main.bike if trip.main != null else null
	match phase:
		"":
			if bike != null and absf(bike.speed) < BOARD_SPEED and not trip.crew_hold():
				var near := _terminal_near(bike.global_position, BOARD_R)
				if _off_node >= 0:
					var xz := world.route_xz(bike.global_position)
					if links.region.node_pos[_off_node].distance_to(Vector2(xz[0], xz[1])) > OFF_CLEAR:
						_off_node = -1
					elif not near.is_empty() and int(near["node"]) == _off_node:
						near = {}
				if not near.is_empty():
					var i := int(near["link"])
					var from := int(near["node"])
					var why := AdventureCrew.board_check(got, Shed.me(), str(links.links[i]["id"]), from, Adventure.riders_out())
					if why == "":
						phase = "asked"
						_asked_at = now
						Shed.request({"a": "adventure_ferry_board", "id": str(links.links[i]["id"]), "from": from,
							"to": links.other_end(i, from), "seconds": snappedf(links.seconds(i), 0.1)})
		"asked":
			if not got.is_empty() and (got["aboard"] as Dictionary).has(Shed.me()):
				phase = "aboard"
				_ease = 0.0
				if bike != null:
					_ease_from = bike.global_transform
			elif now - _asked_at > 3000:
				phase = ""   # (the host said no: the crew's on another ferry, or it's just left)
		"aboard", "sailing":
			if got.is_empty() or int(got["sail"]) != int(sailing.get("sail", -1)) or not (got["aboard"] as Dictionary).has(Shed.me()):
				_let_go(bike)   # (the sailing's gone: the ride ended, or the host cleared it)
			elif phase == "aboard" and t >= 0.0:
				phase = "sailing"
			if holding() and bike != null:
				_ease = minf(_ease + delta / BOARD_EASE, 1.0)
				_hold(bike, delta)
			if phase == "sailing" and t >= total_of(sailing) - DOCK * 0.5:
				_land(bike)
		"landing":
			_land_t += delta
			if bike != null:
				_put(bike, _land_xf, Vector3.ZERO)
				if _land_t >= LAND_WAIT or _ground_under(_land_xf.origin):
					_release(bike)
	_tick_view(delta)


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
		return
	if phase in ["sailing", "landing"]:
		t += delta   # (the host's cleared it a moment before this game's landed its rider: sail on)
		return
	sailing = {}
	t = -1.0
	link = _ferry_ahead()


## The link of the ferry ahead whose ramp the crew's boat waits at (-1 for none near): the route's next crossing, or
## the nearest terminal's.
func _ferry_ahead() -> int:
	var at: Vector3 = trip.focus_points()[0]
	var near := _terminal_near(at, SHOW_R)
	return int(near["link"]) if not near.is_empty() else -1


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
## frame: from its ramp end (its stern at the end of the terminal's ramp) to the other's.
func boat_at(i: int, from: int, s: float, size: String) -> Vector3:
	var line := links.line_from(i, from)
	var back := links.line_from(i, links.other_end(i, from))
	var m := float(links.links[i]["m"])
	var half := float((FerryScenery.BOATS[size] as Dictionary)["len"]) * 0.5
	return FerryScenery.along(line, FerryScenery.sailed(m, s, FerryScenery.berth(line) + half, FerryScenery.berth(back) + half))


# ---------------------------------------------------------------------------- the boat, the bike on it, the camera

func _size() -> String:
	return str(links.links[link]["size"]) if link >= 0 else "roro"


## The boat's pose now (region frame: x, y, z and heading in w), or Vector4(INF...) for no boat to show.
func _pose() -> Vector4:
	if link < 0:
		return Vector4(INF, INF, INF, INF)
	var from := int(sailing["from"]) if not sailing.is_empty() else -1
	if from < 0:
		# (waiting at the ramp of the ferry ahead: the end nearest the rider)
		var l: Dictionary = links.links[link]
		var xz := world.route_xz(trip.focus_points()[0])
		var me := Vector2(xz[0], xz[1])
		from = int(l["a"]) if links.region.node_pos[int(l["a"])].distance_to(me) <= links.region.node_pos[int(l["b"])].distance_to(me) else int(l["b"])
	var m := float(links.links[link]["m"])
	var s := 0.0
	if t >= 0.0:
		s = float(timeline(m, float(sailing.get("seconds", links.seconds(link))), t)["s"])
	var p := boat_at(link, from, s, _size())
	var water := FerryScenery.water_of(world.roads.net, links.links[link]["pts"])
	return Vector4(p.x, water, p.y, p.z)


func _tick_view(delta: float) -> void:
	var pose := _pose()
	if pose.x == INF:
		if _boat != null:
			_boat.visible = false
		_end_camera()
		_last_pose = Vector3.INF
		return
	var key := "%s|%d" % [_size(), link]
	if _boat == null or _boat_key != key:
		if _boat == null:
			_boat = MeshInstance3D.new()
			_boat.name = "CrewFerry"
			world.add_child(_boat)
		var region_id := str(RegionKit.at_frame(links.region.frame_lat, links.region.frame_lon, pose.x, pose.z).get("region", ""))
		_boat.mesh = FerryScenery.boat_mesh(_size(), SceneryStreamer.kit("ferry", region_id))
		_boat_key = key
	_boat.visible = true
	_boat.global_transform = Transform3D(Basis(Vector3.UP, -pose.w), world.to_local_pos(pose.x, pose.y, pose.z))
	_last_pose = Vector3(pose.x, pose.y, pose.z)
	if phase == "sailing" and t >= 0.0:
		_tick_camera(delta)
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
		_end_camera()


## Holds the bike in its place on the deck (eased there from where it went aboard).
func _hold(bike: Bike, delta: float) -> void:
	var pose := _pose()
	if pose.x == INF:
		return
	var aboard: Array = (sailing.get("aboard", {}) as Dictionary).keys()
	aboard.sort()
	var slot := maxi(0, aboard.find(Shed.me()))
	var deck := Transform3D(Basis(Vector3.UP, -pose.w), world.to_local_pos(pose.x, pose.y, pose.z))
	var spot := deck * Transform3D(Basis.IDENTITY, FerryScenery.slot_at(_size(), slot) + Vector3.UP * bike.build.rear_radius)
	var k := smoothstep(0.0, 1.0, _ease)
	var xf := Transform3D(_ease_from.basis.slerp(spot.basis, k), _ease_from.origin.lerp(spot.origin, k))
	var v := Vector3.ZERO
	if _last_pose != Vector3.INF and delta > 0.0:
		var before := world.to_local_pos(_last_pose.x, _last_pose.y, _last_pose.z)
		v = (deck.origin - before) / delta if (deck.origin - before).length() < 40.0 else Vector3.ZERO
	_put(bike, xf, v)


## Puts the bike at `xf`, frozen, its velocity `v` (the boat's: a mate's game draws it moving on).
func _put(bike: Bike, xf: Transform3D, v: Vector3) -> void:
	bike.freeze = true
	bike.global_transform = xf
	PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	bike.linear_velocity = v
	bike.angular_velocity = Vector3.ZERO


## Across: the bike on the far side's road, facing on inland, held till its ground's in.
func _land(bike: Bike) -> void:
	phase = "landing"
	_land_t = 0.0
	var to := int(sailing["to"])
	var aboard: Array = (sailing.get("aboard", {}) as Dictionary).keys()
	aboard.sort()
	_land_xf = landing_xf(to, maxi(0, aboard.find(Shed.me())) * LAND_GAP)   # (the crew one behind another)
	if bike != null:
		_put(bike, _land_xf, Vector3.ZERO)
		trip.main.camera.snap()
	_end_camera()
	_dark.color.a = 0.0
	var nav := NetNav.of(world)
	if world.route != null and world.route.real != null:
		for f: Dictionary in world.route.real.ferries:
			if str(f["id"]) == str(sailing["id"]) and int(f["to"]) == to:
				nav.landed(int(f["step"]))


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


func _ground_under(p: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state if world.is_inside_tree() else null
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0)
	if trip.main != null and trip.main.bike != null:
		q.exclude = [trip.main.bike.get_rid()]
	return not space.intersect_ray(q).is_empty()


## Off the boat: the bike's own again, the camera back on it.
func _release(bike: Bike) -> void:
	phase = ""
	if not sailing.is_empty():
		_off_node = int(sailing["to"])
		Shed.request({"a": "adventure_ferry_landed", "sail": int(sailing["sail"])})   # (the host clears it once all are)
	_land_t = 0.0
	if bike != null:
		bike.freeze = false
		bike.linear_velocity = Vector3.ZERO
		trip.main.camera.snap()
	_end_camera()


## The sailing went without this rider (or the ride's ending): let go of the bike where it is.
func _let_go(bike: Bike) -> void:
	if phase == "sailing" and bike != null:
		_land(bike)
		return
	phase = ""
	if bike != null:
		bike.freeze = false
	_end_camera()


func _tick_camera(_delta: float) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "FerryCamera"
		_cam.fov = 60.0
		_cam.far = 8000.0
		world.add_child(_cam)
	_cam.current = true
	var b: Dictionary = FerryScenery.BOATS[_size()]
	var k := float(b["len"]) / 58.0
	var basis := _boat.global_transform.basis
	var fwd := -basis.z
	var side := basis.x
	# (behind the crew's bikes on the deck and to one side, above them, swinging slowly round to look on over the bow
	# to the far shore)
	var swing := clampf(t / maxf(total_of(sailing), 1.0), 0.0, 1.0)
	var bike: Bike = trip.main.bike if trip.main != null else null
	var at := bike.global_position if bike != null else _boat.global_position
	var from := at - fwd * 14.0 + side * 10.0 * (1.0 - swing) + Vector3.UP * (6.0 + 3.0 * k)
	var look := at + fwd * (30.0 * k + 60.0 * swing) + Vector3.UP * 1.0
	_cam.global_position = from
	if from.distance_to(look) > 0.1:
		_cam.look_at(look, Vector3.UP)


func _end_camera() -> void:
	if _layer != null:
		_layer.visible = false
	if _cam == null:
		return
	_cam.queue_free()
	_cam = null
	if trip != null and trip.main != null:
		if trip.main.bike:
			trip.main.camera.current = true
		elif trip.main.walker:
			trip.main.walker.camera.current = true


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
