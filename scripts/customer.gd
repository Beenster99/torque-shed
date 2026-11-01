class_name CustomerView
extends Node3D
## A customer: a simple low-poly person (the same primitive style as the crew). Most ride their
## own bike in along the road and across the yard, park it in the sales office car park, get
## off and walk in to reception, ring the bell, and wait to be talked to (F). Turned down (or
## tired of waiting) they walk back out, get on and ride away; with the job taken on they leave
## on foot and their bike stays with the shed. A customer collecting a finished job walks out of
## the sales office to their bike in the car park, gets on and rides it off. Drawn from Shed.contracts
## by ContractsView; nothing here is shared state.

signal arrived(view: CustomerView)

## How the line a rider takes is drawn (see ride_line): a point every LINE_STEP m, corners
## rounded off from up to CORNER_REACH m before them, or TIGHT_REACH within NEAR_ROOM m of a
## building.
const LINE_STEP := 0.5
const CORNER_REACH := 8.0
const TIGHT_REACH := 0.8
const NEAR_ROOM := 3.0
## The furthest a rider leans over (rad: a road rider's lean, see Bike.ROAD_LEAN), and how hard
## they brake for a corner or a bay (m/s^2).
const MAX_LEAN := Bike.ROAD_LEAN
const BRAKING := 2.5

var customer_id := 0
var customer_name := ""
## The walk in to the counter (the queue spot is its last point).
var path := PackedVector3Array()
var leaving := false
var at_counter := false
## On their bike and moving.
var riding := false
var _figure: StaticBody3D
var _label: Label3D
var _legs: Array[Node3D] = []
var _walk_phase := 0.0
var _face := Basis()
var _look := {}
## What's still to do: [{mode: "walk" or "ride", pts, then: "park", "counter", "mount" or "gone"}].
var _queue: Array = []
var _cur := {}
var _i := 0
var _speed := 0.0
var _yaw := 0.0
var _spin := 0.0
## The line they're riding this leg (see _start_ride): its points, how far along each is, which
## way it runs and how sharply it bends there, and the most they'll ride it at; how far along it
## they are (in its `_seg`th stretch), and how much of its start is paddled backwards (turning
## from `_back_yaw.x` to `.y` as they go).
var _line := PackedVector3Array()
var _line_s := PackedFloat32Array()
var _line_h := PackedFloat32Array()
var _line_k := PackedFloat32Array()
var _line_v := PackedFloat32Array()
var _at := 0.0
var _seg := 0
var _back := 0.0
var _back_yaw := Vector2.ZERO
## How far the bike leans over (rad, + to the right), and how fast that's changing.
var _roll := 0.0
var _roll_rate := 0.0
var _traits := {}
## Their bike, when they have one here: placed in the world by itself (top level), so it
## stays parked while they walk off.
var _bike: Node3D
var _lean: Node3D
var _model: BikeModel
var _build: BikeBuild
var _bike_paint := Color.WHITE
var _sound: EngineSound


## Builds the figure for customer `data` and starts it walking along `walk` (or standing at
## the end of it already, when `already_there`). With a `ride` and their `bike` ({parts, paint,
## cond}) they ride in along it first and park at its end.
func setup(data: Dictionary, walk: PackedVector3Array, face: Basis, already_there := false,
		ride := PackedVector3Array(), bike := {}) -> void:
	_make_figure(data)
	path = walk
	_face = face
	var has_ride := ride.size() >= 2 and not bike.is_empty()
	var there := already_there or path.size() < 2
	if has_ride:
		_make_bike(bike, Transform3D(Basis(), ride[ride.size() - 1]) if there else _look_along(ride[0], ride[1]), there)
	if there:
		position = path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
		_stand()
		return
	if has_ride:
		position = ride[0]
		_queue.append({"mode": "ride", "pts": ride, "then": "park"})
	else:
		position = path[0]
	_queue.append({"mode": "walk", "pts": path, "then": "counter"})


## A customer come to collect their bike (`bike`: {parts, paint, cond}) standing at `bike_xf`:
## they walk up along `walk`, get on, and ride off along `ride`. The bike stands empty until
## they reach it: only then does the walking figure go and the rider appear on it.
func setup_collect(data: Dictionary, walk: PackedVector3Array, bike: Dictionary, bike_xf: Transform3D,
		ride: PackedVector3Array) -> void:
	_make_figure(data)
	leaving = true
	_make_bike(bike, bike_xf, true)
	position = walk[0] if walk.size() > 0 else bike_xf.origin
	if walk.size() >= 2:
		_queue.append({"mode": "walk", "pts": walk, "then": "mount"})
	else:
		_queue.append({"mode": "walk", "pts": PackedVector3Array([position, position]), "then": "mount"})
	_queue.append({"mode": "ride", "pts": ride, "then": "gone"})


func _make_figure(data: Dictionary) -> void:
	customer_id = int(data.get("id", 0))
	customer_name = str(data.get("name", "Customer"))
	name = "Customer%d" % customer_id
	add_to_group("sales_visitor")
	add_to_group("customers")
	var look: Dictionary = data.get("look", {})
	_look = look
	var top: Color = look.get("top", Color(0.2, 0.3, 0.6))
	var legs: Color = look.get("legs", Color(0.15, 0.15, 0.2))
	var skin: Color = look.get("skin", Color(0.85, 0.66, 0.52))
	var hair: Color = look.get("hair", Color(0.2, 0.12, 0.06))
	var tall: float = float(look.get("tall", 1.0))
	_figure = StaticBody3D.new()
	_figure.collision_layer = Workshop.INTERACT_LAYER
	_figure.collision_mask = 0
	_figure.set_meta("customer", customer_id)
	_figure.scale = Vector3.ONE * tall
	add_child(_figure)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	_figure.add_child(cs)
	var shirt := _mat(top)
	var trousers := _mat(legs)
	var shoes := _mat(Color(0.1, 0.08, 0.07))
	_part(_figure, CapsuleMesh.new(), Vector3(0.0, 1.15, 0.0), Vector3(0.6, 0.6, 0.42), shirt)
	for side in [-1.0, 1.0]:
		# Arms hang at the sides; legs swing as they walk.
		_part(_figure, CapsuleMesh.new(), Vector3(0.34 * side, 1.12, 0.0), Vector3(0.14, 0.55, 0.14), shirt)
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, 0.85, 0.0)
		_figure.add_child(hip)
		_part(hip, CapsuleMesh.new(), Vector3(0.0, -0.4, 0.0), Vector3(0.22, 0.85, 0.22), trousers)
		_part(hip, BoxMesh.new(), Vector3(0.0, -0.8, -0.05), Vector3(0.13, 0.1, 0.26), shoes)
		_legs.append(hip)
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.62, 0.0)
	_figure.add_child(head)
	_part(head, SphereMesh.new(), Vector3.ZERO, Vector3(0.24, 0.27, 0.25), _mat(skin))
	_part(head, SphereMesh.new(), Vector3(0.0, 0.06, 0.03), Vector3(0.26, 0.18, 0.26), _mat(hair))
	if look.get("hat", false):
		_part(head, CylinderMesh.new(), Vector3(0.0, 0.15, 0.0), Vector3(0.3, 0.1, 0.3), _mat(legs.darkened(0.2)))
	if look.get("vip", false):
		# The exclusive customer: a dark suit with a gold tie.
		_part(_figure, BoxMesh.new(), Vector3(0.0, 1.2, -0.215), Vector3(0.06, 0.3, 0.01), _mat(Color(0.9, 0.7, 0.2)))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.font_size = 44
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	_label.modulate = Color(1.0, 0.85, 0.5)
	_figure.add_child(_label)
	set_hint(false)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, size: Vector3, mat: Material) -> void:
	if mesh is CapsuleMesh:
		mesh.radius = 0.5
		mesh.height = 2.0
		size.y *= 0.5
	elif mesh is SphereMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	elif mesh is CylinderMesh:
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	Graphics.avatar_mesh(mi)
	parent.add_child(mi)


# ---------------------------------------------------------------------------- their bike

## Their bike as it looks now: {parts, paint, cond}, standing at `xf`.
func _make_bike(bike: Dictionary, xf: Transform3D, on_stand: bool) -> void:
	var parts: Dictionary = bike.get("parts", {})
	var cond: Dictionary = bike.get("cond", {}) if bike.get("cond") is Dictionary else {}
	_build = BikeBuild.new(PartsDB.sanitize_build(parts.duplicate()), cond)
	_bike_paint = bike.get("paint", Color.WHITE) if bike.get("paint") is Color else Color.WHITE
	_bike = Node3D.new()
	_bike.name = "CustomerBike"
	_bike.top_level = true
	add_child(_bike)
	_bike.global_transform = xf
	_lean = Node3D.new()
	_bike.add_child(_lean)
	_yaw = xf.basis.get_euler().y
	_set_parked(on_stand)
	if not (self is CoffeeVisitor):
		# Something to look at, for ordering one like it or copying its blueprint (BikeCopyView);
		# a cafe biker's parked bike has its own (CoffeeVisitor._add_bike_body). Not solid.
		var body := StaticBody3D.new()
		body.name = "LookBody"
		body.collision_layer = Workshop.INTERACT_LAYER
		body.collision_mask = 0
		body.set_meta("bike_view", self)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.75, 1.1, 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.55
		body.add_child(cs)
		_bike.add_child(body)


## Their bike as a request for ordering one or copying its blueprint carries it (see BikeCopy),
## or {} with no bike here.
func bike_src() -> Dictionary:
	if not has_bike() or _build == null:
		return {}
	var style := str(PartsDB.detect_style(_build.parts).get("style", ""))
	var who := customer_name.get_slice(" ", 0) if customer_name != "" else "A customer"
	return BikeCopy.build_src("%s's %s" % [who, PartsDB.style_name(style) if style != "" else "bike"], _build.parts, _bike_paint,
		_build.condition, false)


## Rebuilds the bike parked on its stand (leaning on the side stand, nobody on it) or ridden.
func _set_parked(on_stand: bool) -> void:
	if _bike == null:
		return
	_lean.basis = Basis()
	var lift := 0.0
	var stand := ""
	if on_stand:
		if str(_build.parts.get("side_stand", "none")) != "none":
			stand = "side"
			_lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(str(_build.parts["side_stand"])).get("lean", 12.0))))
		elif str(_build.parts.get("centre_stand", "none")) != "none":
			stand = "centre"
			lift = _build.centre_lift
	# The bike is drawn once, rider and all: parking it or getting back on only swings the stand
	# and shows or hides the rider (see BikeModel.set_stand). Drawing it afresh each time was a
	# stutter every time a customer parked up or rode off.
	if _model == null or not is_instance_valid(_model) or not _model.set_stand(stand):
		if _model and is_instance_valid(_model):
			_model.free()
		_model = BikeModel.new()
		_model.baked = true   # ridden in and out, not worked on: far fewer draw calls (see BikeModel._bake_static)
		_model.loose_stands = true
		_model.rider_color = _look.get("top", Color(0, 0, 0, 0)) if _look.get("top") is Color else Color(0, 0, 0, 0)
		_model.stand_pose = stand
		_lean.add_child(_model)
		_model.build_from(_build, _bike_paint, {}, null, true)
	_model.position.y = _build.rear_radius + lift
	_model.set_rider_visible(not on_stand)
	_model.set_lights(not on_stand, not on_stand)
	if not on_stand:
		# Its engine is heard (the sound bakes in the background); not on a headless run, which
		# would only wait on the bake at exit.
		if _sound == null and DisplayServer.get_name() != "headless":
			_sound = EngineSound.new()
			_sound.volume_db = -6.0
			_bike.add_child(_sound)
			_sound.setup(_build, _model)
			_sound.set_distant_filter(true)
		if _sound:
			_sound.running = true
	elif _sound:
		_sound.running = false


func has_bike() -> bool:
	return _bike != null and is_instance_valid(_bike)


## Their bike is the shed's now (the job was taken on): this one goes.
func drop_bike() -> void:
	if has_bike():
		_bike.queue_free()
	_bike = null
	_model = null
	_sound = null


## Whether someone is drawn sitting on their bike (the customer once they've got on it).
func rider_on_bike() -> bool:
	return _model != null and is_instance_valid(_model) and _model._rider != null and is_instance_valid(_model._rider) \
			and _model._rider.visible


## Whether the customer is drawn on foot.
func on_foot() -> bool:
	return _figure != null and _figure.visible


## Where the bike is, or nowhere.
func bike_position() -> Vector3:
	return _bike.global_position if has_bike() else Vector3.INF


static func _look_along(from: Vector3, to: Vector3) -> Transform3D:
	var d := to - from
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), from)


# ---------------------------------------------------------------------------- walking about

## Shows "F: talk" (or "Y: talk" on a pad) under the name while someone looks at them.
func set_hint(on: bool) -> void:
	if _label == null:
		return
	Controls.bind_text(_label, customer_name + ("\n{interact}: talk" if on and at_counter and not leaving else ""))


## Walks to a new place in the queue.
func move_to(spot: Vector3) -> void:
	if leaving or path.is_empty():
		return
	if path[path.size() - 1].distance_to(spot) < 0.05:
		return
	path[path.size() - 1] = spot
	# Still on the way in: the walk ends at the new spot instead.
	if not _cur.is_empty() and _cur["then"] == "counter":
		var pts: PackedVector3Array = _cur["pts"]
		pts[pts.size() - 1] = spot
		_cur["pts"] = pts
		return
	for leg in _queue:
		if leg["then"] == "counter":
			var pts: PackedVector3Array = leg["pts"]
			pts[pts.size() - 1] = spot
			leg["pts"] = pts
			return
	if at_counter:
		at_counter = false
		_queue.append({"mode": "walk", "pts": PackedVector3Array([position, spot]), "then": "counter"})


## Turns round and walks back out, then is gone: back to their bike and away on it when
## `by_bike`, else on foot to the car park edge (their bike, if they came on one, stays).
func leave(by_bike := false) -> void:
	if leaving:
		return
	leaving = true
	at_counter = false
	set_hint(false)
	_queue.clear()
	var was_riding := riding
	_cur = {}
	if was_riding:
		# Still riding in: they just carry on and go.
		if by_bike and has_bike():
			_figure.visible = false
			_queue.append({"mode": "ride", "pts": Contracts.ride_out_path(_bike.global_transform, absi(customer_id)), "then": "gone"})
		else:
			queue_free()
		return
	var back := PackedVector3Array([position])
	for i in range(path.size() - 2, -1, -1):
		back.append(path[i])
	if by_bike and has_bike():
		_queue.append({"mode": "walk", "pts": back, "then": "mount"})
		_queue.append({"mode": "ride", "pts": Contracts.ride_out_path(_bike.global_transform, absi(customer_id)), "then": "gone"})
		return
	drop_bike()
	back.append(Contracts.entry().origin)
	_queue.append({"mode": "walk", "pts": back, "then": "gone"})


func _stand() -> void:
	at_counter = true
	basis = _face
	for leg in _legs:
		leg.rotation.x = 0.0


## The end of a leg of the way.
func _leg_done(then: String) -> void:
	match then:
		"park":
			riding = false
			_speed = 0.0
			_roll = 0.0
			var pts: PackedVector3Array = _cur["pts"]
			_bike.global_transform = Transform3D(Basis(), pts[pts.size() - 1])
			_set_parked(true)
			_figure.visible = true
			_figure.collision_layer = Workshop.INTERACT_LAYER
			if not _queue.is_empty():
				var walk: PackedVector3Array = _queue[0]["pts"]
				position = walk[0]
		"counter":
			_stand()
			arrived.emit(self)
		"mount":
			_figure.visible = false
			_figure.collision_layer = 0
			_speed = 0.0
			_roll = 0.0
			if has_bike():
				position = _bike.global_position
				_yaw = _bike.global_basis.get_euler().y
				_set_parked(false)
		"gone":
			queue_free()


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("customers", pt)


func _process_body(delta: float) -> void:
	if _cur.is_empty():
		if _queue.is_empty():
			return
		_cur = _queue.pop_front()
		_i = 1
		_line = PackedVector3Array()
		riding = _cur["mode"] == "ride" and has_bike()
		if riding:
			_figure.visible = false
			_figure.collision_layer = 0
		elif _cur["mode"] == "ride":
			# No bike to ride (it was dropped): nothing to see, they're gone.
			_cur = {}
			queue_free()
			return
	var pts: PackedVector3Array = _cur["pts"]
	if _i >= pts.size():
		var then := str(_cur["then"])
		_leg_done(then)
		_cur = {}
		return
	if riding:
		_ride(delta, pts)
	else:
		_walk(delta, pts)


func _walk(delta: float, pts: PackedVector3Array) -> void:
	var target := pts[_i]
	var to := target - position
	to.y = 0.0
	var step := CustomerView.walk_speed() * delta
	if to.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		_i += 1
		return
	position += to.normalized() * step
	basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	_walk_phase += delta * 7.0
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk_phase + PI * i) * 0.45


## Riding along the leg: on the rider's own line round its corners (see ride_line), at their own
## pace, slowing for the tight ones and easing in to park at the end; paddling backwards out of
## a bay it faces into, swinging the tail round towards the way on when there's room; leaning
## into the turns as a real bike does (and the rider on it with it).
func _ride(delta: float, pts: PackedVector3Array) -> void:
	if _line.size() < 2:
		_start_ride(pts)
	var t := _rider()
	var last := _line.size() - 1
	var total := _line_s[last]
	var backwards := _at < _back
	var want := 0.0
	var err := 0.0
	if backwards:
		want = clampf(0.4 + (_back - _at) * 0.8, 0.4, 1.0)
	else:
		want = _along(_line_v, _at)
		err = wrapf(_heading_at(_at) - _yaw, -PI, PI)
		if absf(err) > 0.3:
			# Still facing well off the way on (just off the stand, or paddled back): round on the spot first.
			want = minf(want, maxf(0.6, 3.0 * (1.0 - absf(err) / PI)))
	_speed = move_toward(_speed, want, (4.0 if want < _speed else float(t["accel"])) * delta)
	var step := maxf(_speed, 0.5) * delta
	_at = minf(_at + step, total)
	while _seg < last - 1 and _line_s[_seg + 1] < _at:
		_seg += 1
	var f := clampf(inverse_lerp(_line_s[_seg], _line_s[_seg + 1], _at), 0.0, 1.0) if _line_s[_seg + 1] > _line_s[_seg] else 0.0
	var pos := _line[_seg].lerp(_line[_seg + 1], f)
	backwards = _at < _back
	if backwards:
		_yaw = lerp_angle(_back_yaw.x, _back_yaw.y, _at / _back)
	else:
		err = wrapf(_heading_at(_at) - _yaw, -PI, PI)
		var turn := clampf(err, -2.5 * delta, 2.5 * delta)
		_yaw += turn
		err -= turn
	# The lean the turn just ahead needs at this speed, atan(v^2 k / g), eased in and out. Not
	# when crawling, feet down, or paddling backwards.
	var k_now := _along(_line_k, _at)
	var want_lean := 0.0
	if not backwards:
		var k := _along(_line_k, _at + maxf(_speed * 0.3, 0.5))
		want_lean = clampf(-atan(_speed * _speed * k / Bike.G), -MAX_LEAN, MAX_LEAN) * smoothstep(0.8, 3.5, _speed)
	var before := _roll
	_roll = move_toward(_roll, lerpf(_roll, want_lean, 1.0 - exp(-6.0 * delta)), 1.5 * delta)
	_roll_rate = (_roll - before) / maxf(delta, 0.0001)
	_bike.global_transform = Transform3D(Basis(Vector3.UP, _yaw), pos)
	_lean.basis = Basis(Vector3.FORWARD, _roll)   # + leans right
	position = pos
	_spin += step / maxf(_build.rear_radius, 0.2) * (-1.0 if backwards else 1.0)
	if _model:
		# The bars point along the curve, with a flick the other way as a lean starts (counter-steer).
		var steer := 0.0
		if not backwards:
			steer = clampf(-atan(_build.wheelbase * k_now) - 0.12 * _roll_rate * smoothstep(2.0, 5.0, _speed) - err * 0.5, -0.6, 0.6)
		_model.update_pose_from(steer, _spin, _spin, 0.0, 0.0, 0.0, clampf(_roll / MAX_LEAN, -1.0, 1.0) * 0.6)
	if _sound:
		_sound.speed = _speed
		_sound.gear = EngineSound.gear_for_speed(_sound.gear, _speed, 3.0, 4)
		_sound.throttle = 0.15 if backwards else clampf(0.25 + (want - _speed) * 0.2, 0.1, 0.8)
		_sound.rpm = lerpf(_build.idle_rpm, _build.redline * 0.5, clampf(fmod(_speed, 3.0) / 3.0 * 0.7 + 0.2, 0.0, 1.0)) \
			if _speed > 0.5 else _build.idle_rpm
	if _at >= total:
		_bike.global_position = _line[last]
		position = _line[last]
		_i = pts.size()


## Works out the line for a new leg along `pts` from where the bike is: the stretch paddled
## backwards first (when the way starts behind it), then the rider's line on, with how fast they
## can take each bit of it.
func _start_ride(pts: PackedVector3Array) -> void:
	var t := _rider()
	var way := PackedVector3Array()
	for p in pts:
		way.append(Vector3(p.x, 0.0, p.z))
	way[0] = Vector3(_bike.global_position.x, 0.0, _bike.global_position.z)
	_back = 0.0
	_back_yaw = Vector2(_yaw, _yaw)
	var facing := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var to := way[1] - way[0] if way.size() >= 2 else Vector3.ZERO
	if to.length() > 0.01 and facing.dot(to.normalized()) < -0.5:
		_back = to.length()
		var rest := way.slice(1)
		if way.size() >= 3 and Workshop.room_at(way[1]) == "":
			# Out in the open: swing the tail round while paddling back, nose towards the way on.
			var on := way[2] - way[1]
			var diff := wrapf(atan2(-on.x, -on.z) - _yaw, -PI, PI)
			if absf(diff) > PI * 0.85:
				diff = PI * (1.0 if posmod(customer_id, 2) == 0 else -1.0)
			var swing := clampf(diff, -1.2, 1.2)
			var dir := Vector3(-sin(_yaw + swing), 0.0, -cos(_yaw + swing))
			if Workshop.room_at(way[1] + dir * 2.0) == "" and Workshop.room_at(way[1] + dir * 3.0) == "":
				_back_yaw.y = _yaw + swing
				rest.insert(1, way[1] + dir * 2.0)
		_line = PackedVector3Array([way[0]])
		_line.append_array(ride_line(rest, customer_id))
	else:
		_line = ride_line(way, customer_id)
	if _line.size() < 2:
		_line.append(_line[0])   # nowhere to go: done straight away
	var n := _line.size()
	_line_s = PackedFloat32Array()
	_line_s.resize(n)
	var heads := PackedFloat32Array()
	heads.resize(maxi(n - 1, 1))
	for i in range(1, n):
		_line_s[i] = _line_s[i - 1] + _line[i].distance_to(_line[i - 1])
		var d := _line[i] - _line[i - 1]
		heads[i - 1] = atan2(-d.x, -d.z) if d.length() > 0.0001 else (heads[i - 2] if i > 1 else _yaw)
	# Each point's heading, and how sharply the line bends there (1/m, + to the left).
	_line_h = PackedFloat32Array()
	_line_h.resize(n)
	var bend := PackedFloat32Array()
	bend.resize(n)
	var first := 1 if _back > 0.0 else 0
	for i in n:
		if i == 0 or i <= first:
			_line_h[i] = heads[mini(i, n - 2)]
		elif i == n - 1:
			_line_h[i] = heads[n - 2]
		else:
			var turn := wrapf(heads[i] - heads[i - 1], -PI, PI)
			_line_h[i] = heads[i - 1] + turn * 0.5
			bend[i] = turn / maxf((_line_s[i + 1] - _line_s[i - 1]) * 0.5, 0.05)
	for _k in 2:
		var was := bend.duplicate()
		for i in range(1, n - 1):
			bend[i] = was[i - 1] * 0.25 + was[i] * 0.5 + was[i + 1] * 0.25
	_line_k = bend
	# The most they'll ride each bit at: their own cruising speed, slow enough for the corner
	# (the sideways pull they're happy with), and braking in time for what's ahead.
	_line_v = PackedFloat32Array()
	_line_v.resize(n)
	for i in n:
		_line_v[i] = minf(float(t["cruise"]), sqrt(float(t["grip"]) / maxf(absf(bend[i]), 0.001)))
	if str(_cur.get("then", "")) == "park":
		_line_v[n - 1] = 0.8
	for i in range(n - 2, -1, -1):
		_line_v[i] = maxf(minf(_line_v[i], sqrt(_line_v[i + 1] * _line_v[i + 1] + 2.0 * BRAKING * (_line_s[i + 1] - _line_s[i]))), 0.6)
	_at = 0.0
	_seg = 0
	if _speed <= 0.0 and str(_cur.get("then", "")) == "park":
		_speed = _line_v[0]   # arriving along the road at their pace


## The value of `arr` (one per line point) at `s` metres along the line.
func _along(arr: PackedFloat32Array, s: float) -> float:
	var last := _line.size() - 1
	s = clampf(s, 0.0, _line_s[last])
	var i := _seg
	while i > 0 and _line_s[i] > s:
		i -= 1
	while i < last - 1 and _line_s[i + 1] < s:
		i += 1
	var f := clampf(inverse_lerp(_line_s[i], _line_s[i + 1], s), 0.0, 1.0) if _line_s[i + 1] > _line_s[i] else 0.0
	return lerpf(arr[i], arr[i + 1], f)


## Which way the line runs at `s` metres along it.
func _heading_at(s: float) -> float:
	var i := _seg
	var f := clampf(inverse_lerp(_line_s[i], _line_s[i + 1], s), 0.0, 1.0) if _line_s[i + 1] > _line_s[i] else 0.0
	return lerp_angle(_line_h[i], _line_h[i + 1], f)


## How this one rides (see rider_traits).
func _rider() -> Dictionary:
	if _traits.is_empty():
		_traits = rider_traits(customer_id)
	return _traits


## How rider `id` rides, the same on every machine: {cruise: their pace (m/s), grip: the sideways
## pull they're happy to corner at (m/s^2), accel (m/s^2), lane: how far off the middle of their
## way they keep (m, + left), sway and wave: how far and how slowly they wander about it (m),
## phase}.
static func rider_traits(id: int) -> Dictionary:
	var rng := Contracts.route_rng(id, 7)
	return {"cruise": Contracts.RIDE_SPEED * rng.randf_range(0.75, 1.2), "grip": rng.randf_range(2.2, 4.2),
		"accel": rng.randf_range(1.8, 3.4), "lane": rng.randf_range(-0.35, 0.35), "sway": rng.randf_range(0.05, 0.2),
		"wave": rng.randf_range(40.0, 90.0), "phase": rng.randf_range(0.0, TAU)}


## The line rider `rider` actually takes along the way `pts`: a little off its middle (by their
## own amount), its corners rounded off into curves, wandering a touch about it, sampled every
## LINE_STEP m. It starts and ends exactly at the way's ends, keeps to the way's first and last
## legs (backing out of a bay, the last straight in to one), and keeps tight to the way near
## buildings, so it goes through their doors and not their walls.
static func ride_line(pts: PackedVector3Array, rider: int) -> PackedVector3Array:
	var t := rider_traits(rider)
	var rects: Array = Workshop.rooms().values()
	var way := PackedVector3Array()
	for p in pts:
		var q := Vector3(p.x, 0.0, p.z)
		if way.is_empty() or q.distance_to(way[way.size() - 1]) > 0.01:
			way.append(q)
	if way.size() < 2:
		return way
	var n := way.size()
	# Their lane: each corner of the way moved off to their side (not the first two or last two).
	var moved := way.duplicate()
	for i in range(2, n - 2):
		var din := (way[i] - way[i - 1]).normalized()
		var dout := (way[i + 1] - way[i]).normalized()
		var side := (Vector3.UP.cross(din) + Vector3.UP.cross(dout))
		var miter := side.length() * 0.5
		if miter < 0.3:
			continue
		var w := smoothstep(NEAR_ROOM, NEAR_ROOM * 2.0, _room_gap(way[i], rects))
		moved[i] = way[i] + side.normalized() * (float(t["lane"]) / miter) * w
	# The corners rounded off: an arc from up to CORNER_REACH before each to as far after it.
	var curved := PackedVector3Array([moved[0]])
	for i in range(1, n - 1):
		var a := moved[i - 1]
		var p := moved[i]
		var b := moved[i + 1]
		var reach := minf(CORNER_REACH, 0.45 * minf(a.distance_to(p), p.distance_to(b)))
		if _room_gap(way[i], rects) < NEAR_ROOM:
			reach = minf(reach, TIGHT_REACH)
		var din := (p - a).normalized()
		var dout := (b - p).normalized()
		var turn := din.signed_angle_to(dout, Vector3.UP)   # + to the left
		var c0 := p - din * reach
		if absf(turn) < 0.02:
			curved.append(p)
			continue
		var r := reach / tan(absf(turn) * 0.5)
		var centre := c0 + Vector3.UP.cross(din) * signf(turn) * r
		var steps := maxi(2, ceili(r * absf(turn) / LINE_STEP))
		for k in steps + 1:
			curved.append(centre + (c0 - centre).rotated(Vector3.UP, turn * k / steps))
	curved.append(moved[n - 1])
	var line := _resample(curved, LINE_STEP)
	# A slow wander about it out in the open, none at the ends.
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	var out := PackedVector3Array()
	var s := 0.0
	for i in line.size():
		if i > 0:
			s += line[i].distance_to(line[i - 1])
		var d := line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]
		var w := smoothstep(0.0, 8.0, s) * smoothstep(3.0, 12.0, total - s) * smoothstep(NEAR_ROOM, NEAR_ROOM * 2.0, _room_gap(line[i], rects))
		out.append(line[i] + Vector3.UP.cross(d.normalized()) * float(t["sway"]) * sin(TAU * s / float(t["wave"]) + float(t["phase"])) * w)
	out[0] = way[0]
	out[out.size() - 1] = way[n - 1]
	return out


## Points every `step` m along the line through `pts`, its ends included.
static func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	var gone := 0.0   # from the last point out to the start of this stretch
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var seg := a.distance_to(pts[i])
		if seg < 0.0001:
			continue
		var d := step - gone
		while d < seg:
			out.append(a.lerp(pts[i], d / seg))
			d += step
		gone = seg - (d - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.25:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


## How far `p` is from the nearest building (0 inside one).
static func _room_gap(p: Vector3, rects: Array) -> float:
	var best := INF
	for r: Rect2 in rects:
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


static func walk_speed() -> float:
	return Contracts.WALK_SPEED
