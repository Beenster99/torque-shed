class_name AdventureTraffic
extends Node3D
## The traffic on an adventure's road (Simon's point 12): cars, vans, lorries and coaches both
## ways (a TrafficStream along the route), thin on the open road and busier through the villages
## and round the cafes, fuel stations and inns, each driver at a pace of their own under the
## road's limit (30 mph through a village, 40 to 60 out of it by how wide the road is, less on
## gravel, sand or snow), lorries and coaches crawling up the steep hills, and service buses
## pulling in at the villages' bus stops (one's often stood at the stop as you ride in). The
## riders are in the lanes too: traffic slows behind a bike and waits for one stopped in its lane.
## Ride into any of it and you come off (as in town: RoadTraffic._on_bike_hit).
##
## Everything is placed by distance along the route (s), never by position, so it's untouched
## by the floating origin (each frame it's put where its s is in the local frame) and it only
## ever drives the way chosen at each fork: nothing goes past a fork that isn't decided yet,
## where the road isn't built (TrafficStream.s_max). With riders far apart, each group has
## traffic of its own (TrafficStream.foci).
##
## At the junctions (AdventureJunctions) it stops for the lights and gives way at roundabouts,
## and turns off down the side roads and comes out of them (see TrafficStream.junctions). The
## lights all run off one clock (AdventureJunctions.clock), the host's.
##
## Co-op: the host drives it and sends it to the crew a few times a second (Net.send_adv_traffic,
## TrafficStream.pack: distances along the road, so each machine puts it in its own frame), with
## the lights' clock on the end ([..., clock, CLOCK_TAG]).
##
## For the police (and anything else that drives in the traffic): AdventureTraffic.current.stream
## is the TrafficStream; see its spawn_at / slot / take / release / remove_id.
##
## Other bikers ride the road too, and with the crew if you keep their pace (AdventureBikers, its
## `bikers`): they're sent on the end of the same snapshot ([..., bikers..., n, AdventureBikers.TAG,
## clock, CLOCK_TAG]).

static var current: AdventureTraffic

## The tables of how busy the road is and its limit, every BIN metres.
const BIN := 16.0
## A village is town within VILLAGE_REACH of its middle, fading to open road over VILLAGE_FADE.
const VILLAGE_REACH := 130.0
const VILLAGE_FADE := 280.0
## How busy the road is round the other stops (and the start and the destination), within
## STOP_REACH and fading over STOP_FADE.
const STOP_BUSY := {"cafe": 0.45, "fuel": 0.45, "inn": 0.4, "campsite": 0.25, "rest_area": 0.2, "viewpoint": 0.2,
	"layby": 0.1, "start": 0.3, "finish": 0.6}
const STOP_REACH := 70.0
const STOP_FADE := 200.0
## Speed limits (m/s): 30 mph in a village; out of it by the road's width (two lanes 60 mph, a
## road 50, a narrow road 40, single track 30), times AdventureRoute.PACE_SURF off the tarmac.
const TOWN_LIMIT := 13.4
const WIDTH_LIMITS := [[7.0, 26.8], [5.5, 22.4], [4.0, 17.9], [0.0, 13.4]]
## Where vehicles turn up and go (m from the nearest rider): out of sight on the open road.
const SPAWN_NEAR := 460.0
const SPAWN_FAR := 820.0
const DESPAWN := 950.0
## Riders this close along the road count as one group.
const GROUP := 600.0
## A bus waiting at a village's stop as you come in: the share of villages that have one, and
## how far ahead of the riders the stop is when it's put there (m).
const BUS_CHANCE := 0.7
const BUS_AHEAD := [260.0, 760.0]
## A parked car pulling out in a village: how far from the riders at least, and how long it
## waits at the kerb first (s).
const PULL_OUT_NEAR := 170.0
const PULL_OUT_WAIT := [1.5, 4.5]
const SEND_EVERY := 0.2
## A bike hitting a vehicle faster than this comes off.
const CRASH_SPEED := 4.0
## Marks the lights' clock on the end of a traffic snapshot.
const CLOCK_TAG := -55555.0

var world: AdventureWorld
var stream: TrafficStream
## The other bikers on the road (see AdventureBikers).
var bikers: AdventureBikers
## Where each rider is along the road this tick, for the bikers: [s, lat] for each of the world's
## focus spots (yours first), [] for one off the road.
var rider_spots: Array = []
## Whether this machine drives the traffic (the host, or a solo game).
var host := true
## The share of villages with a bus waiting as you come in (BUS_CHANCE; the tests set it).
var bus_chance := BUS_CHANCE
var _busy := PackedFloat32Array()
var _limit := PackedFloat32Array()
var _villages: Array = []     # [s of the middle, s of its bus stop, the way its buses go]
var _sites_ref: Array = []    # the route's sites the tables were made from
var _buses_done := {}         # village s -> true once its waiting bus has been decided on
var _send_timer := 0.0
var _town_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "AdventureTraffic"
	current = self
	if world == null:
		world = get_parent() as AdventureWorld
	host = not Net.is_online() or Net.is_host()
	# Every vehicle's meshes made now, behind the fade into the adventure, not as each first
	# turns up (a few tens of ms each: a hitch on the road).
	for kind in VehicleModel.KINDS:
		for trim in int(VehicleModel.SPECS[kind]["trims"]):
			VehicleModel.parts(kind, trim)
	_rng.seed = hash([world.route.seed_value, "adventure_traffic", Time.get_ticks_usec()])
	stream = TrafficStream.new()
	stream.name = "Stream"
	stream.rng.seed = _rng.randi()
	stream.host = host
	stream.sample = sample
	stream.curve = curve
	stream.signal_state = func(jn: Dictionary) -> Vector2i: return AdventureJunctions.light_state(jn["site"], AdventureJunctions.clock)
	stream.arm_at = arm_at
	stream.spawn_near = SPAWN_NEAR
	stream.spawn_far = SPAWN_FAR
	stream.despawn = DESPAWN
	stream.reach = SPAWN_FAR + 50.0
	stream.weigh_busy = true
	add_child(stream)
	stream.set_physics_process(false)   # stepped from here, after the riders are found
	_tables()
	bikers = AdventureBikers.new()
	bikers.traffic = self
	add_child(bikers)
	Net.adv_traffic_received.connect(_on_net)


func _exit_tree() -> void:
	if current == self:
		current = null
	if Net.adv_traffic_received.is_connected(_on_net):
		Net.adv_traffic_received.disconnect(_on_net)


# ---------------------------------------------------------------------------- the road

## The road at `s` for the stream: {pos (local), fwd, hw, busy, limit, grade}.
func sample(s: float) -> Dictionary:
	# As AdventureRoute's xz_at, heading_at_s, height_at_s and grade_at_s, in one go (it's asked
	# a few times a frame for every vehicle).
	var r := world.route
	var f := clampf(s / AdventureRoute.STEP, 0.0, float(r.px.size() - 1))
	var i := mini(int(f), r.px.size() - 2)
	var u := f - i
	var h := lerpf(r.hd[i], r.hd[i + 1], u)
	var b := clampi(int(s / BIN), 0, _busy.size() - 1)
	return {"pos": world.to_local_pos(lerpf(r.px[i], r.px[i + 1], u), lerpf(r.ph[i], r.ph[i + 1], u) + AdventureChunk.CROWN * 0.75,
			lerpf(r.pz[i], r.pz[i + 1], u)),
		"fwd": Vector3(sin(h), 0.0, -cos(h)), "hw": r.width[clampi(int(round(f)), 0, r.width.size() - 1)] * 0.5,
		"busy": _busy[b], "limit": _limit[b], "grade": (r.ph[i + 1] - r.ph[i]) / AdventureRoute.STEP}


## The road's bend at `s` (1/m, + to the right), over a few knots either way: a real road's curvature from one knot to
## the next is noisy, and the traffic slowed for kinks that aren't bends.
func curve(s: float) -> float:
	var r := world.route
	return r.smooth_curv(clampi(int(round(s / AdventureRoute.STEP)), 0, r.curv.size() - 1), 3)


## Where junction `jn`'s side road `k` is `t` m out from its mouth (for the stream): {pos (local,
## on its surface), fwd (unit, out along it)}.
func arm_at(jn: Dictionary, k: int, t: float) -> Dictionary:
	var r := world.route
	var st: Dictionary = jn["site"]
	var pts: PackedVector3Array = st["arm_geo"][k]
	var si: int = st["i"]
	var f := clampf(t / AdventureJunctions.ARM_STEP, 0.0, float(pts.size() - 1))
	var i := mini(int(f), pts.size() - 2)
	var p := pts[i].lerp(pts[i + 1], f - i)
	var fwd := pts[i + 1] - pts[i]
	fwd.y = 0.0
	return {"pos": world.to_local_pos(r.px[si] + p.x, r.ph[si] + p.y + 0.06, r.pz[si] + p.z), "fwd": fwd.normalized()}


## How busy the road is at `s` (0 open road .. 1 a village) and its limit there (m/s).
func busy_at(s: float) -> float:
	return _busy[clampi(int(s / BIN), 0, _busy.size() - 1)]


func limit_at(s: float) -> float:
	return _limit[clampi(int(s / BIN), 0, _limit.size() - 1)]


## Works out how busy the road is and its limits all along it, and where the bus stops are
## (again whenever a fork's choice moves the road's sites).
func _tables() -> void:
	var r := world.route
	_sites_ref = r.sites
	var n := int(ceil(r.total / BIN)) + 1
	_busy.resize(n)
	_busy.fill(0.0)
	_limit.resize(n)
	_villages = []
	for st in r.sites:
		var kind := str(st["kind"])
		var level := 1.0 if kind == "village" else float(STOP_BUSY.get(kind, 0.0))
		if level <= 0.0:
			continue
		var reach := VILLAGE_REACH if kind == "village" else STOP_REACH
		var fade := VILLAGE_FADE if kind == "village" else STOP_FADE
		var s := float(st["s"])
		for b in range(maxi(0, int((s - reach - fade) / BIN)), mini(n, int((s + reach + fade) / BIN) + 1)):
			var d := absf(b * BIN - s)
			var v := level * clampf(1.0 - (d - reach) / fade, 0.0, 1.0)
			_busy[b] = maxf(_busy[b], v)
		if kind == "village":
			# The bus stop: 20 m along from the pub on the village's side (see
			# AdventureStops._village), served by the buses in the lane on that side.
			var side := int(st["side"])
			_villages.append([s, s + 20.0 * side, -side])
	for b in n:
		var s := b * BIN
		var w := r.width_at_s(s)
		var open := 13.4
		for wl in WIDTH_LIMITS:
			if w >= float(wl[0]):
				open = float(wl[1])
				break
		open *= float(AdventureRoute.PACE_SURF.get(r.surface_at_s(s), 1.0))
		_limit[b] = lerpf(open, minf(open, TOWN_LIMIT), clampf(_busy[b] * 1.6, 0.0, 1.0))
		if r.limit_kmh_at(s) > 0.0:
			_limit[b] = minf(_limit[b], r.limit_kmh_at(s) / 3.6)   # the real road's own limit
	stream.bus_stops = _villages.map(func(v): return {"s": v[1], "dir": v[2]})
	# The junctions, for stopping, giving way and turning (anything down a side road of the old
	# list goes: its place in it is gone).
	var js := []
	for st in r.sites_of(AdventureJunctions.KIND):
		if not st.has("arm_geo"):
			continue
		var jn := {"s": float(st["s"]), "stop": AdventureJunctions.stop_line(st), "lights": bool(st["lights"]),
			"village": float(st.get("village", -1.0)) >= 0.0, "site": st,
			"arms": (st["arms"] as Array).map(func(a): return {"side": int(a["side"]), "len": float(a["len"]), "w": float(a["w"])})}
		if st.has("ro"):
			jn["ro"] = float(st["ro"])
			jn["rc"] = float(st["rc"])
		js.append(jn)
	for i in range(stream.vehicles.size() - 1, -1, -1):
		if stream.vehicles[i].has("arm"):
			stream._remove(i)
	if bikers:
		bikers.drop_arms()
	stream.junctions = js


# ---------------------------------------------------------------------------- each tick

func _physics_process(delta: float) -> void:
	if world == null or world.route == null or not world.focus.is_valid():
		return
	var pt := Perf.t0()
	if not is_same(world.route.sites, _sites_ref):
		_tables()
	_find_riders()
	stream.s_min = 2.0
	stream.s_max = minf(world.route.total, world.route.stream_end()) - 2.0
	_watch_bikes()
	if host:
		_waiting_buses()
		_town_timer -= delta
		if _town_timer <= 0.0:
			_town_timer = 1.3
			_pull_out()
	AdventureJunctions.clock += delta
	var bt := Perf.t0()
	bikers.step(delta)
	Perf.add("adv_bikers", bt)
	var st := Perf.t0()
	stream.step(delta)
	Perf.add("traffic", st)   # the driving and drawing, inside adv_traffic
	if host:
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_EVERY
			var pack := stream.pack()
			pack.append_array(bikers.pack())
			pack.append_array([AdventureJunctions.clock, CLOCK_TAG])
			Net.send_adv_traffic(pack)
	Perf.add("adv_traffic", pt)


## Where the riders (and anyone on foot) are along the road: the stream's foci, one for each
## group, and blockers in the lanes they're in.
func _find_riders() -> void:
	var spots: Array = world.focus.call()
	var foci := []
	var blockers := []
	rider_spots = []
	for k in spots.size():
		var hit := world.locate_local(spots[k], "traffic%d" % k)
		if hit.is_empty() or absf(float(hit["lat"])) > 60.0:
			rider_spots.append([])
			continue
		var s := float(hit["s"])
		var lat := float(hit["lat"])
		rider_spots.append([s, lat])
		if foci.all(func(f): return absf(float(f) - s) > GROUP):
			foci.append(s)
		var hw := world.route.width_at_s(s) * 0.5
		if absf(lat) < hw + 0.4:
			# In the left lane they hold up the traffic going their way, in the right lane
			# what's coming, astride the middle both.
			blockers.append([s, 1 if lat < -0.7 else (-1 if lat > 0.7 else 0), 1.2])
	if not foci.is_empty():
		stream.foci = foci
		stream.focus_s = float(foci[0])
	stream.blockers = blockers


## Coming up to a village, now and then its bus is already stood at the stop.
func _waiting_buses() -> void:
	for v in _villages:
		var stop_s := float(v[1])
		if _buses_done.has(stop_s):
			continue
		for f in stream.spots():
			var ahead := stop_s - float(f)
			if ahead < BUS_AHEAD[0] or ahead > BUS_AHEAD[1]:
				continue
			_buses_done[stop_s] = true
			if _rng.randf() < bus_chance:
				var dir := int(v[2])
				var centre := stop_s + dir * (2.5 - TrafficVehicle.half_length_of("coach"))
				# Long enough for riders to arrive while it's there, and a little more.
				stream.spawn_at("coach", centre, dir, 0.0, {"bus": true, "kerb": true, "served": stop_s,
					"dwell": ahead / 14.0 + _rng.randf_range(6.0, 14.0)})
			break


## In a village, a parked car now and then pulls out from the kerb ahead, so the high street
## has life in it as you ride through (not too near anyone, and only into a clear lane).
func _pull_out() -> void:
	if stream.vehicles.size() >= stream.wanted():
		return
	for v in _villages:
		var mid := float(v[0])
		for f in stream.spots():
			if absf(mid - float(f)) > 600.0:
				continue
			var s := mid + _rng.randf_range(-VILLAGE_REACH, VILLAGE_REACH)
			var dir := 1 if _rng.randf() < 0.5 else -1
			if stream.from_focus(s) < PULL_OUT_NEAR or not stream.clear_at(s, dir, 45.0):
				return
			var kind: String = ["hatchback", "hatchback", "saloon", "estate", "suv", "van"][_rng.randi() % 6]
			stream.spawn_at(kind, s, dir, 0.0, {"kerb": true, "dwell": _rng.randf_range(PULL_OUT_WAIT[0], PULL_OUT_WAIT[1])})
			return


## Your bike running into one of them at more than CRASH_SPEED: you come off (as in town).
func _watch_bikes() -> void:
	for b in get_tree().get_nodes_in_group("ridden_bike"):
		if not b is Bike:
			continue
		if int(b.get_meta("adv_traffic_watch", 0)) != get_instance_id():   # each adventure's own
			b.set_meta("adv_traffic_watch", get_instance_id())
			(b as Bike).body_entered.connect(_on_bike_hit.bind(b))
		b.set_meta("traffic_speed", (b as Bike).linear_velocity.length())


func _on_bike_hit(body: Node, b: Bike) -> void:
	if is_instance_valid(b) and is_inside_tree() and body.is_in_group("road_traffic") and (body.get_parent() == stream or body.get_parent() == bikers) \
			and float(b.get_meta("traffic_speed", 0.0)) > CRASH_SPEED and not b.is_crashed:
		b.crash()


func _on_net(state: PackedFloat32Array) -> void:
	if host:
		return
	if state.size() >= 2 and state[state.size() - 1] == CLOCK_TAG:
		# The host's lights clock: taken as it is when it's well out, else eased onto.
		var theirs := state[state.size() - 2]
		var off := theirs - AdventureJunctions.clock
		AdventureJunctions.clock += off if absf(off) > 1.0 else off * 0.3
		state = state.slice(0, state.size() - 2)
	stream.unpack(bikers.unpack_tail(state))
