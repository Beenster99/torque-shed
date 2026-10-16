class_name CoffeeVisitor
extends CustomerView
## A biker at the coffee shop (see CoffeeShop): rides in along the road and up the yard, parks in
## their bay in the cafe car park, walks to their chair and sits down with a cup. Now and then
## one gets up and wanders over to the sales office to look at a bike on show. When it's time to
## go they walk back to their bike, get on and ride off; with it sold to the shed they walk off
## down the yard to get a lift home. Their parked bike can be looked at (its basics show over it)
## and they or their bike can be talked to (F). Drawn by CoffeeView from Shed.coffee; nothing here
## is shared state.

var visitor_id := 0
## Sitting at their table, standing looking at a bike in the showroom.
var seated := false
var looking := false
var _park_xf := Transform3D()
var _bike_body: StaticBody3D
var _bike_label: Label3D
var _cup: Node3D
var _hint_on := false


## Builds the figure for visitor `v` with their bike (`bike`: {parts, paint, cond}). Standing
## parked in their bay already when `parked`, else at the start of the ride in.
func setup_visitor(v: Dictionary, bike: Dictionary, parked: bool) -> void:
	visitor_id = int(v.get("id", 0))
	_make_figure({"id": CoffeeShop.ID_BASE + visitor_id, "name": v.get("name", "Biker"), "look": v.get("look", {})})
	name = "CafeVisitor%d" % visitor_id
	_park_xf = CoffeeShop.park_xf(int(v.get("park", 0)))
	var ride := CoffeeShop.ride_in(int(v.get("park", 0)), visitor_id)
	if parked:
		_make_bike(bike, _park_xf, true)
		_add_bike_body()
		position = CoffeeShop.park_side(int(v.get("park", 0)))
	else:
		_make_bike(bike, _look_along(ride[0], ride[1]), false)
		position = ride[0]
		_queue.append({"mode": "ride", "pts": ride, "then": "park"})


## Their bike stands in its bay and they're off it (straight away, wherever they've got to on
## the way in).
func park_now() -> void:
	if not has_bike() or _bike_body != null:
		return
	riding = false
	_speed = 0.0
	_bike.global_transform = _park_xf
	_set_parked(true)
	_add_bike_body()
	_figure.visible = true
	_figure.collision_layer = Workshop.INTERACT_LAYER


## Drops whatever they were doing and sets off along `pts` (from where they are now), then
## `then` ("sit", "look", "mount" or "gone"). A leg straight after a ride ("mount": the ride out)
## can follow with `ride`. At the end they turn to `face`.
func go(pts: PackedVector3Array, then: String, ride := PackedVector3Array(), face := Basis()) -> void:
	_face = face
	_queue.clear()
	_cur = {}
	park_now()
	unsit()
	looking = false
	var walk := PackedVector3Array([position])
	walk.append_array(pts)
	_queue.append({"mode": "walk", "pts": walk, "then": then})
	if ride.size() >= 2:
		_queue.append({"mode": "ride", "pts": ride, "then": "gone"})


## Puts them in their chair `seat` now (joining a cafe that's been going a while).
func sit_now(seat: int) -> void:
	_queue.clear()
	_cur = {}
	park_now()
	position = CoffeeShop.seat_xf(seat).origin
	_leg_done("sit_at:%d" % seat)


## Stands them by the bike on `stand` in the showroom now.
func look_now(stand: int, k: int) -> void:
	_queue.clear()
	_cur = {}
	park_now()
	unsit()
	var xf := CoffeeShop.showroom_xf(stand, k)
	position = xf.origin
	basis = xf.basis
	looking = true


## The walk to their chair, from their bike.
func walk_to_seat(park: int, seat: int) -> void:
	_queue.append({"mode": "walk", "pts": CoffeeShop.walk_to_seat(park, seat), "then": "sit_at:%d" % seat})


## Up off the chair, legs straight, the cup left behind.
func unsit() -> void:
	if not seated:
		return
	seated = false
	_figure.position.y = 0.0
	for leg in _legs:
		leg.rotation.x = 0.0
	if is_instance_valid(_cup):
		_cup.queue_free()
	_cup = null


func _leg_done(then: String) -> void:
	if then.begins_with("sit_at:"):
		# Sat down at the table, facing it, with a cup in front of them.
		var xf := CoffeeShop.seat_xf(int(then.get_slice(":", 1)))
		position = xf.origin
		basis = xf.basis
		seated = true
		_figure.position.y = -0.4
		for leg in _legs:
			leg.rotation.x = 1.35
		if _cup == null:
			_cup = Node3D.new()
			_cup.name = "Cup"
			_cup.position = Vector3(0.0, CoffeeShop.TABLE_SIZE.y, -0.45)
			add_child(_cup)
			_part(_cup, CylinderMesh.new(), Vector3(0.0, 0.05, 0.0), Vector3(0.08, 0.1, 0.08), _mat(Color(0.95, 0.94, 0.9)))
			_part(_cup, CylinderMesh.new(), Vector3(0.0, 0.003, 0.0), Vector3(0.16, 0.006, 0.16), _mat(Color(0.95, 0.94, 0.9)))
		return
	match then:
		"park":
			super._leg_done(then)
			_bike.global_transform = _park_xf
			_add_bike_body()
		"look":
			looking = true
			basis = _face
		"mount":
			_remove_bike_body()
			super._leg_done(then)
		_:
			super._leg_done(then)


## The parked bike's body, so it can be looked at and talked about (it isn't solid).
func _add_bike_body() -> void:
	if _bike_body != null or not has_bike():
		return
	_bike_body = StaticBody3D.new()
	_bike_body.name = "BikeBody"
	_bike_body.collision_layer = Workshop.INTERACT_LAYER
	_bike_body.collision_mask = 0
	_bike_body.set_meta("coffee_bike", visitor_id)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.75, 1.1, 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.55
	_bike_body.add_child(cs)
	_bike.add_child(_bike_body)
	_bike_label = Label3D.new()
	_bike_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bike_label.position = Vector3(0.0, 1.5, 0.0)
	_bike_label.font_size = 36
	_bike_label.outline_size = 10
	_bike_label.pixel_size = 0.0024
	_bike_label.no_depth_test = true
	_bike_label.modulate = Color(1.0, 0.92, 0.7)
	_bike_label.visible = false
	_bike.add_child(_bike_label)


func _remove_bike_body() -> void:
	if is_instance_valid(_bike_body):
		_bike_body.queue_free()
	if is_instance_valid(_bike_label):
		_bike_label.queue_free()
	_bike_body = null
	_bike_label = null


## Whether their bike stands parked in its bay, with its body to look at.
func bike_parked() -> bool:
	return is_instance_valid(_bike_body)


## The bike is the shed's now: theirs goes (the shed's own is drawn in its place).
func drop_bike() -> void:
	_remove_bike_body()
	super.drop_bike()


## Shows "F: talk" under their name while someone looks at them.
func set_hint(on: bool) -> void:
	_hint_on = on
	if _label == null:
		return
	var key := Settings.binding_text("interact", false)
	_label.text = customer_name + ("\n%s: talk about the bike" % (key if key != "" else "F") if on else "")


## Shows the bike's basics over it while someone looks at it.
func set_bike_hint(on: bool, text := "") -> void:
	if is_instance_valid(_bike_label):
		_bike_label.visible = on
		_bike_label.text = text


func bike_hint_shown() -> bool:
	return is_instance_valid(_bike_label) and _bike_label.visible


func hint_shown() -> bool:
	return _hint_on
