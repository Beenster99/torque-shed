class_name CustomerView
extends Node3D
## A customer: a simple low-poly person (the same primitive style as the crew). Most ride their
## own bike in along the road and across the yard, park it in the sales office car park, get
## off and walk in to reception, ring the bell, and wait to be talked to (F). Turned down (or
## tired of waiting) they walk back out, get on and ride away; with the job taken on they leave
## on foot and their bike stays with the shed. A customer collecting a finished job walks up to
## their bike wherever it was handed back, gets on and rides it off. Drawn from Shed.contracts
## by ContractsView; nothing here is shared state.

signal arrived(view: CustomerView)

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
## they walk up along `walk`, get on, and ride off along `ride`.
func setup_collect(data: Dictionary, walk: PackedVector3Array, bike: Dictionary, bike_xf: Transform3D,
		ride: PackedVector3Array) -> void:
	_make_figure(data)
	leaving = true
	_make_bike(bike, bike_xf, Shed.bay_at(bike_xf.origin) < 0)
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


## Rebuilds the bike parked on its stand (leaning on the side stand, nobody on it) or ridden.
func _set_parked(on_stand: bool) -> void:
	if _bike == null:
		return
	if _model:
		_model.free()
	_model = BikeModel.new()
	_model.rider_color = _look.get("top", Color(0, 0, 0, 0)) if _look.get("top") is Color else Color(0, 0, 0, 0)
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
	_model.stand_pose = stand
	_model.position.y = _build.rear_radius + lift
	_lean.add_child(_model)
	_model.build_from(_build, _bike_paint, {}, null, not on_stand)
	if not on_stand:
		_model.set_lights(true, true)
		if _sound == null:
			_sound = EngineSound.new()
			_sound.volume_db = -6.0
			_bike.add_child(_sound)
			_sound.setup(_build, _model)
			_sound.set_distant_filter(true)
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


## Where the bike is, or nowhere.
func bike_position() -> Vector3:
	return _bike.global_position if has_bike() else Vector3.INF


static func _look_along(from: Vector3, to: Vector3) -> Transform3D:
	var d := to - from
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), from)


# ---------------------------------------------------------------------------- walking about

## Shows "F: talk" under the name while someone looks at them.
func set_hint(on: bool) -> void:
	if _label == null:
		return
	var key := Settings.binding_text("interact", false)
	_label.text = customer_name + ("\n%s: talk" % (key if key != "" else "F") if on and at_counter and not leaving else "")


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
			_queue.append({"mode": "ride", "pts": Contracts.ride_out_path(_bike.global_transform), "then": "gone"})
		else:
			queue_free()
		return
	var back := PackedVector3Array([position])
	for i in range(path.size() - 2, -1, -1):
		back.append(path[i])
	if by_bike and has_bike():
		_queue.append({"mode": "walk", "pts": back, "then": "mount"})
		_queue.append({"mode": "ride", "pts": Contracts.ride_out_path(_bike.global_transform), "then": "gone"})
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
			if has_bike():
				position = _bike.global_position
				_yaw = _bike.global_basis.get_euler().y
				_set_parked(false)
		"gone":
			queue_free()


func _process(delta: float) -> void:
	if _cur.is_empty():
		if _queue.is_empty():
			return
		_cur = _queue.pop_front()
		_i = 1
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


## Riding along the leg: easing in to park at the end, paddling backwards out of a bay it
## faces into, and turning smoothly with a little lean.
func _ride(delta: float, pts: PackedVector3Array) -> void:
	var pos := _bike.global_position
	var target := pts[_i]
	var to := target - pos
	to.y = 0.0
	var left := to.length()
	for k in range(_i + 1, pts.size()):
		left += pts[k].distance_to(pts[k - 1])
	var facing := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var backwards := _i == 1 and to.length() > 0.01 and facing.dot(to.normalized()) < -0.5
	var want := Contracts.RIDE_SPEED
	if backwards:
		want = 1.0
	elif _cur["then"] == "park":
		want = clampf(1.0 + left * 0.8, 1.0, Contracts.RIDE_SPEED)
	_speed = move_toward(_speed, want, (6.0 if want < _speed else 3.0) * delta)
	var step := maxf(_speed, 0.6) * delta
	var turn := 0.0
	if to.length() > 0.01 and not backwards:
		var heading := atan2(-to.x, -to.z)
		var diff := wrapf(heading - _yaw, -PI, PI)
		turn = clampf(diff, -2.2 * delta, 2.2 * delta)
		_yaw += turn
	if to.length() <= step:
		pos = Vector3(target.x, 0.0, target.z)
		_i += 1
	else:
		pos += to.normalized() * step
	_bike.global_transform = Transform3D(Basis(Vector3.UP, _yaw), pos)
	_lean.basis = Basis(Vector3.BACK, clampf(-turn / maxf(delta, 0.0001) * _speed * 0.05, -0.45, 0.45))
	position = pos
	_spin += step / maxf(_build.rear_radius, 0.2) * (-1.0 if backwards else 1.0)
	if _model:
		_model.update_pose_from(0.0, _spin, _spin, 0.0, 0.0, 0.0, 0.0)
	if _sound:
		_sound.speed = _speed
		_sound.gear = clampi(1 + int(_speed / 3.0), 1, 4)
		_sound.throttle = 0.15 if backwards else clampf(0.25 + (want - _speed) * 0.2, 0.1, 0.8)
		_sound.rpm = lerpf(_build.idle_rpm, _build.redline * 0.5, clampf(fmod(_speed, 3.0) / 3.0 * 0.7 + 0.2, 0.0, 1.0)) \
			if _speed > 0.5 else _build.idle_rpm


static func walk_speed() -> float:
	return Contracts.WALK_SPEED
