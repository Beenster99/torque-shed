class_name TownPeople
extends Node3D
## The people about the town (WorldTown): up to MAX_PEOPLE walking the pavements of the High
## Street (fewer at night and in the rain), keeping to the left of each other, stopping to look
## in a shop window, waiting at the bus stop, stopping for a chat when they meet, crossing at the
## zebra crossings, going into the shops and coming out of them; a few walk a dog. Pigeons peck
## about on the pavements and fly off when you come near. People stop for anyone walking at
## them and jump out of the way of a bike, a car or the recovery truck, so nothing goes through
## them.
##
## Cosmetic and local: each player sees their own townsfolk (nothing is shared). Kept cheap: all
## the people are one MultiMesh (one draw call; a shader swings their arms and legs and colours
## their clothes from per-instance data), and so are the dogs and the pigeons; nobody has a node
## or a collision shape of their own, nothing is allocated per frame, and when nobody is near
## the town it all stops and hides. Far off, they're moved less often.

const MAX_PEOPLE := 28
const NIGHT_PEOPLE := 6
const DOGS := 3
const PIGEONS := 16
## The town's people only walk while the camera is this near the High Street (m), and are drawn
## to this far.
const ACTIVE_RANGE := 330.0
const DRAW_RANGE := 170.0
## Past this the people are moved every third frame.
const NEAR_RANGE := 120.0
const WALK_SPEED := Vector2(1.0, 1.45)
## How far off the middle of the pavement people keep to its left (m).
const KEEP_LEFT := 0.45
## A bike or car heading to pass closer than this (m) within DODGE_AHEAD seconds makes them jump
## aside; someone on foot this close ahead makes them stop.
const DODGE_MISS := 1.8
const DODGE_AHEAD := 2.2
const DODGE_SPEED := 3.4
const STOP_FOR := 1.1

enum {WALK, STAND, CHAT, WAIT, CROSS, INSIDE, GONE}


## One townsperson.
class Person:
	var state := 6    # GONE
	var pos := Vector2.ZERO
	var y := 0.0
	var yaw := 0.0
	var face := 0.0
	var dir := 1
	var lane := 0.0
	var speed := 1.2
	var timer := 0.0
	var phase := 0.0
	var amount := 0.0
	var look := 0.0
	var look2 := 0.0
	var size := 1.0
	var target := Vector2.ZERO
	var dodge := Vector2.ZERO
	var dodge_t := 0.0
	var pause := 0.0
	var walked := 0.0
	var next_think := 3.0
	var partner := -1
	var wobble := 0.0
	var avoid := 0.0


var process_usec := 0          # what the last frame cost (for the perf checks)
var active := false
var people: Array[Person] = []
var _world: World
var _town: WorldTown
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh
var _dog_mm: MultiMesh
var _bird_mm: MultiMesh
var _holders: Array[MultiMeshInstance3D] = []
var _doors: Array[Vector3] = []
var _windows: Array = []       # [x0, x1, lane z, front z] per shop window
var _check := 0.0
var _spawn_in := 0.0
var _frame := 0
var _skipped := 0.0
## Things to keep out of the way of, refreshed ten times a second: position, velocity (x/z),
## radius, and whether it's a vehicle.
var _mover_pos := PackedVector2Array()
var _mover_vel := PackedVector2Array()
var _mover_r := PackedFloat32Array()
var _mover_car := PackedByteArray()
var _mover_count := 0
var _mover_last := {}          # instance id -> [Vector2, time]
var _mover_in := 0.0
var _dog_owner := PackedInt32Array()
var _dog_phase := PackedFloat32Array()
## Pigeons: where each is, its heading, flying velocity (zero on the ground), peck phase, and how
## long until it comes back once flown off (or 0 while it's here).
var _bird_pos := PackedVector3Array()
var _bird_yaw := PackedFloat32Array()
var _bird_vel := PackedVector3Array()
var _bird_phase := PackedFloat32Array()
var _bird_back := PackedFloat32Array()
var _bird_home := PackedInt32Array()


func _ready() -> void:
	add_to_group("town_people")


func setup(world: World, town: WorldTown) -> void:
	_world = world
	_town = town
	_rng.randomize()
	for p: Dictionary in WorldTown.plan():
		if str(p["kind"]) == "shop" or str(p["kind"]) == "pub":
			_doors.append(WorldTown.door_spot(p))
			var lane := WorldTown.NORTH_WALK if int(p["side"]) == -1 else WorldTown.SOUTH_WALK
			_windows.append([float(p["x0"]) + 1.0, float(p["x1"]) - 1.0, lane, float(p["front"])])
	for i in MAX_PEOPLE:
		people.append(Person.new())
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_mm = _multimesh(_person_mesh(), MAX_PEOPLE, mat, "Pedestrians")
	_dog_mm = _multimesh(_dog_mesh(), DOGS, mat, "Dogs")
	_bird_mm = _multimesh(_pigeon_mesh(), PIGEONS, mat, "Pigeons")
	_dog_owner.resize(DOGS)
	_dog_owner.fill(-1)
	_dog_phase.resize(DOGS)
	_bird_yaw.resize(PIGEONS)
	_bird_phase.resize(PIGEONS)
	_bird_back.resize(PIGEONS)
	_bird_pos.resize(PIGEONS)
	_bird_vel.resize(PIGEONS)
	_bird_home.resize(PIGEONS)
	for i in PIGEONS:
		_bird_home[i] = i % WorldTown.FLOCKS.size()
		_bird_land(i)
		_bird_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _bird_yaw[i]), _bird_pos[i]))
	_hide_all()


func _multimesh(mesh: Mesh, count: int, mat: Material, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = AABB(Vector3(WorldTown.X_RANGE.x - 10.0, -1.0, WorldTown.NORTH_FRONT - 10.0),
		Vector3(WorldTown.X_RANGE.y - WorldTown.X_RANGE.x + 20.0, 12.0, WorldTown.SOUTH_FRONT - WorldTown.NORTH_FRONT + 20.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	if node_name == "Pigeons":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_world.ranged(mmi, 60.0 if node_name == "Pigeons" else DRAW_RANGE)
	_holders.append(mmi)
	return mm


func _hide_all() -> void:
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in MAX_PEOPLE:
		_mm.set_instance_transform(i, none)
		people[i].state = GONE
	for i in DOGS:
		_dog_mm.set_instance_transform(i, none)
		_dog_owner[i] = -1
	for h in _holders:
		h.visible = false


# ---------------------------------------------------------------------------- each frame

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var dist := _street_distance(eye)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var want := dist < ACTIVE_RANGE
		if want != active:
			active = want
			if active:
				for h in _holders:
					h.visible = true
				_populate()
			else:
				_hide_all()
	if not active:
		process_usec = 0
		return
	# Far off, move them every third frame (with the time saved up).
	_frame += 1
	_skipped += delta
	if dist > NEAR_RANGE and _frame % 3 != 0:
		process_usec = Time.get_ticks_usec() - t0
		return
	var dt := minf(_skipped, 0.1)
	_skipped = 0.0
	_mover_in -= dt
	if _mover_in <= 0.0:
		_mover_in = 0.1
		_gather_movers()
	_keep_numbers(dt)
	for i in MAX_PEOPLE:
		var p := people[i]
		if p.state == GONE:
			continue
		_step(i, p, dt)
	if _frame % 2 == 0:
		_meet()
	for i in MAX_PEOPLE:
		_draw(i)
	_dogs(dt)
	if dist < 70.0:
		_pigeons(dt, eye)
	process_usec = Time.get_ticks_usec() - t0


## How far `at` is from the High Street through the town.
static func _street_distance(at: Vector3) -> float:
	var x := clampf(at.x, WorldTown.X_RANGE.x, WorldTown.X_RANGE.y)
	return Vector2(at.x - x, at.z - WorldTown.STREET_Z).length()


## How many should be out now: fewer at night and in the rain.
func _target() -> int:
	var dark := Daylight.darkness()
	var rain := Weather.current.rain if Weather.current else 0.0
	return int(lerpf(MAX_PEOPLE, NIGHT_PEOPLE, dark) * (1.0 - 0.5 * rain))


## Fills the town at once (when it comes into reach): people all along the pavements.
func _populate() -> void:
	var n := _target()
	for i in mini(n, MAX_PEOPLE):
		var lane := WorldTown.NORTH_WALK if _rng.randf() < 0.5 else WorldTown.SOUTH_WALK
		_spawn(i, Vector2(_rng.randf_range(WorldTown.X_RANGE.x + 3.0, WorldTown.X_RANGE.y - 3.0), lane), lane)
	_spawn_in = 1.0


## People come out of the shops or walk into town from either end while there are fewer about
## than there should be.
func _keep_numbers(dt: float) -> void:
	_spawn_in -= dt
	if _spawn_in > 0.0:
		return
	_spawn_in = _rng.randf_range(0.8, 2.0)
	var out := 0
	var free := -1
	for i in MAX_PEOPLE:
		if people[i].state != GONE:
			out += 1
		elif free < 0:
			free = i
	if out >= _target() or free < 0:
		return
	if _rng.randf() < 0.6 and not _doors.is_empty():
		var d := _doors[_rng.randi() % _doors.size()]
		var lane := WorldTown.NORTH_WALK if d.z < WorldTown.STREET_Z else WorldTown.SOUTH_WALK
		_spawn(free, Vector2(d.x, d.z), lane)
	else:
		var lane := WorldTown.NORTH_WALK if _rng.randf() < 0.5 else WorldTown.SOUTH_WALK
		var west := _rng.randf() < 0.5
		_spawn(free, Vector2(WorldTown.X_RANGE.x + 0.5 if west else WorldTown.X_RANGE.y - 0.5, lane), lane)
		people[free].dir = 1 if west else -1


func _spawn(i: int, at: Vector2, lane: float) -> void:
	var p := people[i]
	p.state = WALK
	p.pos = at
	p.lane = lane
	p.dir = 1 if _rng.randf() < 0.5 else -1
	p.speed = _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y)
	p.phase = _rng.randf() * TAU
	p.amount = 1.0
	p.look = float(_rng.randi() % 12 + 16 * (_rng.randi() % 6))
	p.look2 = float(_rng.randi() % 4 + 8 * (_rng.randi() % 6))
	p.size = _rng.randf_range(0.9, 1.07)
	p.yaw = -PI * 0.5 * p.dir
	p.next_think = _rng.randf_range(2.0, 5.0)
	p.walked = 0.0
	p.partner = -1
	p.dodge_t = 0.0
	p.pause = 0.0
	p.wobble = _rng.randf_range(-0.15, 0.15)
	p.avoid = 0.0
	p.y = WorldTown.ground_y(at.x, at.y)
	# Now and then one has a dog with them.
	if _rng.randf() < 0.18:
		for d in DOGS:
			if _dog_owner[d] < 0 or people[_dog_owner[d]].state == GONE:
				_dog_owner[d] = i
				break


func _step(i: int, p: Person, dt: float) -> void:
	_avoid(p, dt)
	var moving := false
	match p.state:
		WALK:
			if p.pause > 0.0:
				p.pause -= dt
			else:
				var z := p.lane - KEEP_LEFT * p.dir + p.wobble + p.avoid
				var v := Vector2(p.dir * p.speed, clampf((z - p.pos.y) * 2.0, -0.8, 0.8))
				p.pos += v * dt
				p.walked += v.length() * dt
				moving = true
				if p.walked > p.next_think:
					p.walked = 0.0
					p.next_think = _rng.randf_range(2.0, 4.5)
					_think(i, p)
				if p.pos.x < WorldTown.X_RANGE.x or p.pos.x > WorldTown.X_RANGE.y:
					p.state = GONE   # walked out of town
		CROSS, INSIDE:
			var to := p.target - p.pos
			var step := p.speed * dt
			if to.length() <= step:
				p.pos = p.target
				if p.state == INSIDE:
					p.state = GONE
				else:
					p.lane = WorldTown.SOUTH_WALK if p.lane < WorldTown.STREET_Z else WorldTown.NORTH_WALK
					p.dir = 1 if _rng.randf() < 0.5 else -1
					p.state = WALK
			else:
				p.pos += to / to.length() * step
				moving = true
		STAND, WAIT, CHAT:
			p.timer -= dt
			if p.timer <= 0.0:
				p.state = WALK
				p.partner = -1
				if _rng.randf() < 0.35:
					p.dir = -p.dir
				p.pause = 0.0
	if p.dodge_t > 0.0:
		p.dodge_t -= dt
		p.pos += p.dodge * dt
		moving = true
	# Arms and legs: swinging with the pace while walking; a little talking with the hands in a chat.
	var want := 1.0 if moving else (0.14 if p.state == CHAT else 0.0)
	p.amount = move_toward(p.amount, want, dt * 4.0)
	var rate := 6.2 * p.speed / 1.25 if moving else (2.0 if p.state == CHAT else 0.0)
	p.phase = fmod(p.phase + rate * dt, TAU * 2.0)
	# Face where they're going, or what they're looking at.
	var face := p.yaw
	if moving:
		var v2 := (p.target - p.pos) if (p.state == CROSS or p.state == INSIDE) else Vector2(p.dir, 0.0)
		if p.dodge_t > 0.0:
			v2 = p.dodge
		face = atan2(-v2.x, -v2.y)
	elif p.state == STAND or p.state == WAIT or p.state == CHAT:
		face = p.face
	p.yaw = lerp_angle(p.yaw, face, minf(dt * 6.0, 1.0))
	p.y = WorldTown.ground_y(p.pos.x, p.pos.y)


## What someone walking along does next, now and then: cross the road at a zebra, wait for the
## bus, look in a shop window, or go into a shop.
func _think(i: int, p: Person) -> void:
	for cx in WorldTown.CROSSINGS:
		if absf(p.pos.x - cx) < 1.6 and _rng.randf() < 0.5:
			var other := WorldTown.SOUTH_WALK if p.lane < WorldTown.STREET_Z else WorldTown.NORTH_WALK
			p.pos.x = cx + _rng.randf_range(-0.8, 0.8)
			p.target = Vector2(p.pos.x, other)
			p.state = CROSS
			return
	if p.lane > WorldTown.STREET_Z and absf(p.pos.x - WorldTown.BUS_STOP.x) < 3.0 and _rng.randf() < 0.45:
		p.state = WAIT
		p.timer = _rng.randf_range(12.0, 40.0)
		p.face = 0.0   # facing the road (-Z)
		p.target = Vector2(_rng.randf_range(WorldTown.SHELTER_X.x, WorldTown.SHELTER_X.y), WorldTown.SOUTH_WALK - 0.25)
		p.pos = p.pos.lerp(p.target, 0.5)
		return
	for w: Array in _windows:
		if absf(float(w[2]) - p.lane) < 0.1 and p.pos.x > float(w[0]) and p.pos.x < float(w[1]):
			var r := _rng.randf()
			if r < 0.2:
				p.state = STAND
				p.timer = _rng.randf_range(3.5, 10.0)
				var front := float(w[3])
				p.face = 0.0 if front < WorldTown.STREET_Z else PI
				p.pos.y = front + (0.75 if front < WorldTown.STREET_Z else -0.75)
				return
			break
	for d: Vector3 in _doors:
		if absf(d.x - p.pos.x) < 1.2 and absf(d.z - p.lane) < 1.5 and _rng.randf() < 0.12:
			p.state = INSIDE
			p.target = Vector2(d.x, d.z + (-0.9 if d.z < WorldTown.STREET_Z else 0.9))
			return


## Two people meeting on the pavement: now and then they stop for a chat; otherwise they edge
## apart so they don't walk through each other.
func _meet() -> void:
	for a in MAX_PEOPLE:
		var pa := people[a]
		if pa.state == GONE or pa.state == INSIDE:
			continue
		for b in range(a + 1, MAX_PEOPLE):
			var pb := people[b]
			if pb.state == GONE or pb.state == INSIDE:
				continue
			var d := pb.pos - pa.pos
			var d2 := d.length_squared()
			if d2 > 2.6:
				continue
			if pa.state == WALK and pb.state == WALK and pa.dir != pb.dir and d2 < 2.2 and _rng.randf() < 0.12 \
					and absf(pa.lane - pb.lane) < 0.1:
				for pair: Array in [[pa, pb], [pb, pa]]:
					var p: Person = pair[0]
					var o: Person = pair[1]
					p.state = CHAT
					p.timer = _rng.randf_range(6.0, 16.0)
					var to := o.pos - p.pos
					p.face = atan2(-to.x, -to.y)
				pb.timer = pa.timer
				continue
			if d2 < 0.36 and d2 > 0.0001:
				var push := d / sqrt(d2) * 0.04
				pa.pos -= push
				pb.pos += push


## Keeps them out of the way of the players and of anything riding or driving by.
func _avoid(p: Person, dt: float) -> void:
	p.avoid = move_toward(p.avoid, 0.0, dt * 0.3)
	for k in _mover_count:
		var rel := p.pos - _mover_pos[k]
		var d2 := rel.length_squared()
		var v := _mover_vel[k]
		var sp := v.length()
		var reach := 2.5 + sp * DODGE_AHEAD
		if d2 > reach * reach:
			continue
		if _mover_car[k] == 1 and sp > 0.8:
			var t := clampf(rel.dot(v) / (sp * sp), 0.0, DODGE_AHEAD)
			var miss := rel - v * t
			if miss.length_squared() < DODGE_MISS * DODGE_MISS and rel.dot(v) > 0.0:
				var away := miss.normalized() if miss.length_squared() > 0.0004 else Vector2(-v.y, v.x) / sp
				p.dodge = away * DODGE_SPEED
				p.dodge_t = 0.35
				p.pause = 0.8
		elif d2 < STOP_FOR * STOP_FOR and p.state == WALK:
			# Someone on foot right in front: stop, and step to one side to get by.
			if rel.dot(Vector2(p.dir, 0.0)) < 0.0:
				p.pause = 0.5
				p.avoid = clampf(p.avoid + signf(rel.y if absf(rel.y) > 0.05 else 1.0) * dt * 1.5, -0.7, 0.7)
		# Never inside anyone or anything.
		var r := _mover_r[k] + 0.32
		if d2 < r * r:
			p.pos = _mover_pos[k] + (rel / sqrt(d2) if d2 > 0.0001 else Vector2(0.0, 1.0)) * r


## Finds the players, the bikes being ridden (by players, customers, cafe bikers, traffic) and the
## recovery truck, with how fast each is going.
func _gather_movers() -> void:
	_mover_count = 0
	var now := Time.get_ticks_msec() / 1000.0
	for group: String in ["local_walker", "remote_players", "ridden_bike", "road_traffic", "customers", "town_movers"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or not node.is_visible_in_tree():
				continue
			var at := node.global_position
			if group == "remote_players":
				var rp := n as RemotePlayer
				if rp.riding_bike != 0:
					continue
				at = rp.world_transform().origin
			if absf(at.z - WorldTown.STREET_Z) > 30.0 or at.x < WorldTown.X_RANGE.x - 30.0 or at.x > WorldTown.X_RANGE.y + 30.0:
				continue
			var p2 := Vector2(at.x, at.z)
			var id := node.get_instance_id()
			var vel := Vector2.ZERO
			if _mover_last.has(id):
				var last: Array = _mover_last[id]
				var span := now - float(last[1])
				if span > 0.01:
					vel = (p2 - (last[0] as Vector2)) / span
				last[0] = p2
				last[1] = now
			else:
				_mover_last[id] = [p2, now]
			var car := group in ["ridden_bike", "road_traffic", "town_movers"] or (group == "customers" and vel.length() > 2.5)
			_add_mover(p2, vel, 2.2 if group == "town_movers" else (0.9 if car else 0.32), car)
	if _mover_last.size() > 64:
		_mover_last.clear()


func _add_mover(at: Vector2, vel: Vector2, r: float, car: bool) -> void:
	if _mover_count >= _mover_pos.size():
		var n := _mover_count + 8
		_mover_pos.resize(n)
		_mover_vel.resize(n)
		_mover_r.resize(n)
		_mover_car.resize(n)
	_mover_pos[_mover_count] = at
	_mover_vel[_mover_count] = vel
	_mover_r[_mover_count] = r
	_mover_car[_mover_count] = 1 if car else 0
	_mover_count += 1


func _draw(i: int) -> void:
	var p := people[i]
	if p.state == GONE:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		return
	var bob := absf(cos(p.phase)) * 0.025 * p.amount
	_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.size), Vector3(p.pos.x, p.y + bob, p.pos.y)))
	_mm.set_instance_custom_data(i, Color(p.phase, p.amount, p.look, p.look2))


## The dogs trot along just ahead of their owners on their leads.
func _dogs(dt: float) -> void:
	for d in DOGS:
		var o := _dog_owner[d]
		if o < 0 or people[o].state == GONE or people[o].state == INSIDE:
			_dog_owner[d] = -1
			_dog_mm.set_instance_transform(d, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var p := people[o]
		var fwd := Vector2(-sin(p.yaw), -cos(p.yaw))
		var at := p.pos + fwd * 1.1 + Vector2(fwd.y, -fwd.x) * 0.35
		_dog_phase[d] = fmod(_dog_phase[d] + dt * 11.0 * p.amount, TAU * 2.0)
		_dog_mm.set_instance_transform(d, Transform3D(Basis(Vector3.UP, p.yaw), Vector3(at.x, WorldTown.ground_y(at.x, at.y), at.y)))
		_dog_mm.set_instance_custom_data(d, Color(_dog_phase[d], p.amount, 0.0, float(8 * ((d + 2) % 6))))


# ---------------------------------------------------------------------------- pigeons

func _bird_land(i: int) -> void:
	var c := WorldTown.FLOCKS[_bird_home[i]]
	_bird_pos[i] = c + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-0.5, 0.5))
	_bird_yaw[i] = _rng.randf() * TAU
	_bird_vel[i] = Vector3.ZERO
	_bird_phase[i] = _rng.randf() * TAU
	_bird_back[i] = 0.0


## Pigeons peck about and shuffle round; anyone (or anything) coming within a few metres puts them
## up, and they fly off over the roofs and come back a while later when it's quiet.
func _pigeons(dt: float, eye: Vector3) -> void:
	for i in PIGEONS:
		if _bird_back[i] > 0.0:
			_bird_back[i] -= dt
			if _bird_back[i] <= 0.0:
				var home := WorldTown.FLOCKS[_bird_home[i]]
				if eye.distance_to(home) > 18.0:
					_bird_land(i)
				else:
					_bird_back[i] = 5.0
			continue
		var at := _bird_pos[i]
		if _bird_vel[i] == Vector3.ZERO:
			for k in _mover_count:
				if Vector2(at.x, at.z).distance_squared_to(_mover_pos[k]) < 12.0:
					var away := (Vector2(at.x, at.z) - _mover_pos[k]).normalized()
					_bird_vel[i] = Vector3(away.x * 3.0 + _rng.randf_range(-1.0, 1.0), _rng.randf_range(2.5, 3.5), away.y * 3.0)
					_bird_yaw[i] = atan2(-_bird_vel[i].x, -_bird_vel[i].z)
					break
			if _bird_vel[i] == Vector3.ZERO:
				_bird_phase[i] = fmod(_bird_phase[i] + dt * _rng.randf_range(2.0, 7.0), TAU * 2.0)
				if _rng.randf() < dt * 0.4:
					_bird_yaw[i] += _rng.randf_range(-1.2, 1.2)
		if _bird_vel[i] != Vector3.ZERO:
			_bird_pos[i] += _bird_vel[i] * dt
			_bird_vel[i].y += dt * 0.6
			_bird_phase[i] = fmod(_bird_phase[i] + dt * 28.0, TAU * 2.0)
			if _bird_pos[i].y > 14.0:
				_bird_back[i] = _rng.randf_range(20.0, 45.0)
				_bird_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
				continue
		var flying := 1.0 if _bird_vel[i] != Vector3.ZERO else 0.0
		_bird_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _bird_yaw[i]), _bird_pos[i]))
		_bird_mm.set_instance_custom_data(i, Color(_bird_phase[i], flying, 0.0, 0.0))


# ---------------------------------------------------------------------------- meshes

## A vertex for the townsfolk shader: UV is (part, colour slot), UV2 the joint it swings about
## (y, z). Parts: 0 still, 1/2 left/right leg, 3/4 left/right arm, 5 a pigeon's head, 6/7 its
## wings. Slots: 0 the vertex colour, 1 skin, 2 top, 3 trousers, 4 hair (or a dog's coat).
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, part: int, slot: int, color: Color, pivot := Vector2.ZERO) -> void:
	var h := size * 0.5
	var corners := []
	for k in 8:
		corners.append(c + Vector3(h.x * (1 if k & 1 else -1), h.y * (1 if k & 2 else -1), h.z * (1 if k & 4 else -1)))
	for q: Array in [[0, 2, 3, 1, Vector3.FORWARD], [4, 5, 7, 6, Vector3.BACK], [0, 1, 5, 4, Vector3.DOWN], [2, 6, 7, 3, Vector3.UP],
			[0, 4, 6, 2, Vector3.LEFT], [1, 3, 7, 5, Vector3.RIGHT]]:
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(q[4])
			st.set_uv(Vector2(part, slot))
			st.set_uv2(pivot)
			st.add_vertex(corners[q[idx]])


static func _ball(st: SurfaceTool, c: Vector3, r: Vector3, part: int, slot: int, color: Color, pivot := Vector2.ZERO) -> void:
	var rings := 5
	var segs := 8
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var pts := [Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)), Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
				Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)), Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))]
			for idx in [0, 2, 1, 0, 3, 2]:
				var n: Vector3 = pts[idx]
				st.set_color(color)
				st.set_normal(n)
				st.set_uv(Vector2(part, slot))
				st.set_uv2(pivot)
				st.add_vertex(c + n * r)


## A townsperson about 1.75 m tall, facing -Z: shoes, legs, a top with sleeves, hands, head and hair.
static func _person_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hip := Vector2(0.92, 0.0)
	var shoulder := Vector2(1.45, 0.0)
	var shoe := Color(0.08, 0.07, 0.07)
	for s in 2:
		var x := -0.1 if s == 0 else 0.1
		var leg := 1 + s
		_box(st, Vector3(x, 0.045, -0.04), Vector3(0.12, 0.09, 0.27), leg, 0, shoe, hip)
		_box(st, Vector3(x, 0.5, 0.0), Vector3(0.15, 0.82, 0.17), leg, 3, Color.WHITE, hip)
		var arm := 3 + s
		var ax := -0.26 if s == 0 else 0.26
		_box(st, Vector3(ax, 1.2, 0.0), Vector3(0.1, 0.52, 0.12), arm, 2, Color.WHITE, shoulder)
		_box(st, Vector3(ax, 0.88, 0.0), Vector3(0.085, 0.13, 0.1), arm, 1, Color.WHITE, shoulder)
	_box(st, Vector3(0.0, 0.95, 0.0), Vector3(0.36, 0.16, 0.2), 0, 3, Color.WHITE)
	_box(st, Vector3(0.0, 1.22, 0.0), Vector3(0.42, 0.52, 0.23), 0, 2, Color.WHITE)
	_box(st, Vector3(0.0, 1.5, 0.0), Vector3(0.44, 0.08, 0.2), 0, 2, Color.WHITE)
	_box(st, Vector3(0.0, 1.56, 0.0), Vector3(0.1, 0.08, 0.1), 0, 1, Color.WHITE)
	_ball(st, Vector3(0.0, 1.67, 0.0), Vector3(0.11, 0.125, 0.115), 0, 1, Color.WHITE)
	_ball(st, Vector3(0.0, 1.715, 0.02), Vector3(0.12, 0.1, 0.12), 0, 4, Color.WHITE)
	return st.commit()


## A dog (a mid-sized one) facing -Z, its legs swinging in diagonal pairs at a trot.
static func _dog_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.42, 0.0), Vector3(0.22, 0.2, 0.6), 0, 4, Color.WHITE)
	_box(st, Vector3(0.0, 0.55, -0.36), Vector3(0.16, 0.16, 0.2), 0, 4, Color.WHITE)
	_box(st, Vector3(0.0, 0.51, -0.5), Vector3(0.09, 0.08, 0.1), 0, 4, Color.WHITE)
	_box(st, Vector3(-0.06, 0.65, -0.33), Vector3(0.04, 0.08, 0.04), 0, 0, Color(0.1, 0.08, 0.06))
	_box(st, Vector3(0.06, 0.65, -0.33), Vector3(0.04, 0.08, 0.04), 0, 0, Color(0.1, 0.08, 0.06))
	_box(st, Vector3(0.0, 0.5, 0.36), Vector3(0.04, 0.04, 0.18), 0, 4, Color.WHITE)
	for leg: Array in [[-0.07, -0.22, 1], [0.07, 0.22, 1], [0.07, -0.22, 2], [-0.07, 0.22, 2]]:
		_box(st, Vector3(leg[0], 0.17, leg[1]), Vector3(0.06, 0.34, 0.06), leg[2], 4, Color.WHITE, Vector2(0.33, leg[1]))
	return st.commit()


## A pigeon facing -Z: grey body, darker head that pecks, wings that flap when it flies.
static func _pigeon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.48, 0.5, 0.55)
	_box(st, Vector3(0.0, 0.12, 0.0), Vector3(0.11, 0.1, 0.22), 0, 0, grey)
	_box(st, Vector3(0.0, 0.11, 0.15), Vector3(0.08, 0.03, 0.12), 0, 0, grey.darkened(0.3))
	_box(st, Vector3(0.0, 0.19, -0.11), Vector3(0.065, 0.065, 0.07), 5, 0, Color(0.33, 0.36, 0.42), Vector2(0.16, -0.08))
	_box(st, Vector3(0.0, 0.18, -0.155), Vector3(0.02, 0.015, 0.03), 5, 0, Color(0.85, 0.6, 0.3), Vector2(0.16, -0.08))
	_box(st, Vector3(-0.1, 0.16, 0.0), Vector3(0.12, 0.015, 0.14), 6, 0, grey.darkened(0.15), Vector2(0.16, 0.0))
	_box(st, Vector3(0.1, 0.16, 0.0), Vector3(0.12, 0.015, 0.14), 7, 0, grey.darkened(0.15), Vector2(0.16, 0.0))
	for x: float in [-0.03, 0.03]:
		_box(st, Vector3(x, 0.035, 0.0), Vector3(0.015, 0.07, 0.015), 0, 0, Color(0.75, 0.35, 0.35))
	return st.commit()


## Swings the parts about their joints by the instance's phase and amount (INSTANCE_CUSTOM x, y),
## and colours the clothes, skin and hair from its look (z: top + 16 x trousers; w: skin + 8 x
## hair), so the whole crowd is one draw call.
const SHADER := """
shader_type spatial;
render_mode cull_back;

const vec3 TOPS[12] = {vec3(0.62, 0.1, 0.1), vec3(0.1, 0.2, 0.5), vec3(0.2, 0.42, 0.25), vec3(0.85, 0.75, 0.3),
	vec3(0.85, 0.85, 0.82), vec3(0.15, 0.15, 0.17), vec3(0.45, 0.25, 0.5), vec3(0.9, 0.45, 0.2),
	vec3(0.35, 0.55, 0.75), vec3(0.55, 0.42, 0.3), vec3(0.75, 0.3, 0.45), vec3(0.3, 0.32, 0.36)};
const vec3 TROUSERS[6] = {vec3(0.12, 0.15, 0.28), vec3(0.08, 0.08, 0.09), vec3(0.4, 0.34, 0.25), vec3(0.3, 0.3, 0.32),
	vec3(0.2, 0.28, 0.42), vec3(0.45, 0.2, 0.15)};
const vec3 SKINS[4] = {vec3(0.92, 0.72, 0.58), vec3(0.78, 0.55, 0.4), vec3(0.55, 0.36, 0.24), vec3(0.36, 0.24, 0.16)};
const vec3 HAIRS[6] = {vec3(0.12, 0.08, 0.05), vec3(0.35, 0.22, 0.12), vec3(0.72, 0.58, 0.32), vec3(0.06, 0.05, 0.05),
	vec3(0.6, 0.6, 0.6), vec3(0.5, 0.25, 0.1)};

varying vec3 v_col;

void vertex() {
	float part = UV.x;
	float slot = UV.y;
	float phase = INSTANCE_CUSTOM.x;
	float amt = INSTANCE_CUSTOM.y;
	float s = sin(phase);
	float ang = 0.0;
	float roll = 0.0;
	if (part > 0.5 && part < 1.5) {
		ang = s * 0.55 * amt;
	} else if (part > 1.5 && part < 2.5) {
		ang = -s * 0.55 * amt;
	} else if (part > 2.5 && part < 3.5) {
		ang = -s * 0.42 * amt;
	} else if (part > 3.5 && part < 4.5) {
		ang = s * 0.42 * amt;
	} else if (part > 4.5 && part < 5.5) {
		ang = max(sin(phase * 0.5), 0.0) * 0.9 * (1.0 - amt);
	} else if (part > 5.5 && part < 6.5) {
		roll = s * 1.1 * amt;
	} else if (part > 6.5) {
		roll = -s * 1.1 * amt;
	}
	vec3 piv = vec3(0.0, UV2.x, UV2.y);
	if (ang != 0.0) {
		vec3 p = VERTEX - piv;
		float c = cos(ang);
		float sn = sin(ang);
		VERTEX = vec3(p.x, p.y * c - p.z * sn, p.y * sn + p.z * c) + piv;
		NORMAL = vec3(NORMAL.x, NORMAL.y * c - NORMAL.z * sn, NORMAL.y * sn + NORMAL.z * c);
	}
	if (roll != 0.0) {
		vec3 p = VERTEX - piv;
		float c = cos(roll);
		float sn = sin(roll);
		VERTEX = vec3(p.x * c - p.y * sn, p.x * sn + p.y * c, p.z) + piv;
		NORMAL = vec3(NORMAL.x * c - NORMAL.y * sn, NORMAL.x * sn + NORMAL.y * c, NORMAL.z);
	}
	int look = int(INSTANCE_CUSTOM.z + 0.5);
	int look2 = int(INSTANCE_CUSTOM.w + 0.5);
	vec3 col = COLOR.rgb;
	if (slot > 0.5 && slot < 1.5) {
		col = SKINS[look2 % 4];
	} else if (slot > 1.5 && slot < 2.5) {
		col = TOPS[look % 12];
	} else if (slot > 2.5 && slot < 3.5) {
		col = TROUSERS[(look / 16) % 6];
	} else if (slot > 3.5) {
		col = HAIRS[(look2 / 8) % 6];
	}
	v_col = col;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.85;
}
"""
