class_name ContractsView
extends Node3D
## Draws the customers in Shed.contracts as people walking in to reception (see CustomerView),
## rings the bell as each one gets to the counter, and opens the offer card when a player on
## foot looks at one and presses F. Main makes one and puts it in the world.

signal talk_requested(customer_id: int)

const REACH := 3.5

var main: Node                 # for the walker and whether a menu is open
var views := {}                # customer id -> CustomerView
var collecting := {}           # finished job id -> the CustomerView riding its bike away (null once seen)
var _looked := 0


func _ready() -> void:
	Shed.changed.connect(sync_state)
	add_child(dispatch_pallet())


## The dispatch pallet by the delivery area, where batch orders' finished parts go down (see
## ContractBatch.DISPATCH): a wooden pallet on the ground against the shed wall.
static func dispatch_pallet() -> Node3D:
	var root := Node3D.new()
	root.name = "DispatchPallet"
	var r := ContractBatch.DISPATCH
	root.position = ContractBatch.pallet_at()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.47, 0.3)
	wood.roughness = 0.9
	var dark := wood.duplicate() as StandardMaterial3D
	dark.albedo_color = Color(0.45, 0.33, 0.2)
	var box := func(size: Vector3, at: Vector3, mat: Material) -> void:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		m.mesh = b
		m.material_override = mat
		m.position = at
		root.add_child(m)
	# Three bearers, then deck boards across them.
	for i in 3:
		box.call(Vector3(0.1, 0.09, r.size.y), Vector3(lerpf(-r.size.x * 0.5 + 0.06, r.size.x * 0.5 - 0.06, i / 2.0), 0.045, 0.0), dark)
	for i in 9:
		box.call(Vector3(r.size.x, 0.022, r.size.y / 9.0 - 0.04), Vector3(0.0, 0.1, lerpf(-r.size.y * 0.5, r.size.y * 0.5, (i + 0.5) / 9.0)), wood)
	# Solid, so parts put down on it sit on its boards.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x, 0.111, r.size.y)
	shape.shape = bs
	shape.position = Vector3(0.0, 0.0555, 0.0)
	body.add_child(shape)
	root.add_child(body)
	return root


## Brings the figures into line with the customers waiting now, and the ones collecting their
## bikes.
func sync_state() -> void:
	var waiting: Array = Contracts.customers().keys()
	waiting.sort_custom(func(a, b): return float(Contracts.customers()[a]["arrived"]) < float(Contracts.customers()[b]["arrived"]))
	for id in views.keys():
		if not is_instance_valid(views[id]):
			views.erase(id)
		elif not waiting.has(id):
			# Job taken on: they walk off and leave their bike. Otherwise they ride it away.
			(views[id] as CustomerView).leave(not Contracts.took_on(int(id)))
			views.erase(id)
	var face := Contracts.reception().basis
	for i in waiting.size():
		var id: int = waiting[i]
		var c: Dictionary = Contracts.customers()[id]
		var park := int(c.get("park", -1)) if Contracts.rides_in(c) else -1
		var walk := Contracts.path_in(i, park)
		if views.has(id):
			(views[id] as CustomerView).move_to(walk[walk.size() - 1])
			continue
		var ride := Contracts.ride_in_path(park, id) if park >= 0 else PackedVector3Array()
		var bike := {}
		if park >= 0:
			var o: Dictionary = c["offer"]
			var paint: Color = Shed.PAINTS[int(o.get("paint", 0)) % Shed.PAINTS.size()]
			if Color.html_is_valid(str(o.get("paint_rgb", ""))):
				paint = Color.html(str(o["paint_rgb"]))   # a manufacturer's prototype, in its factory colour
			bike = {"parts": o.get("parts", {}), "paint": paint}
		var secs := _length(walk) / Contracts.WALK_SPEED + _length(ride) / Contracts.RIDE_SPEED * 1.5 + 2.0
		var v := CustomerView.new()
		add_child(v)
		v.setup(c, walk, face, _since(float(c.get("arrived", 0.0))) > secs, ride, bike)
		v.arrived.connect(_on_arrived)
		views[id] = v
	_sync_leaving()


## Customers who've come for their finished bikes: each walks up to it, gets on and rides off.
## Seen once each, and only while it's still happening (not when joining long after).
func _sync_leaving() -> void:
	for d in Contracts._st().get("leaving", []):
		if not (d is Dictionary) or not (d.get("xf") is Transform3D):
			continue
		var id := int(d.get("id", 0))
		if collecting.has(id):
			continue
		var xf: Transform3D = d["xf"]
		var walk := Contracts.collect_path(xf)
		var ride := Contracts.ride_out_path(xf, id)
		var secs := _length(walk) / Contracts.WALK_SPEED + _length(ride) / Contracts.RIDE_SPEED * 1.5 + 2.0
		if _since(float(d.get("at", 0.0))) > secs:
			collecting[id] = null
			continue
		var v := CustomerView.new()
		add_child(v)
		v.setup_collect({"id": -id, "name": d.get("name", ""), "look": d.get("look", {})}, walk,
			{"parts": d.get("parts", {}), "paint": d.get("paint"), "cond": d.get("cond", {})}, xf, ride)
		collecting[id] = v


## Real seconds since the contracts clock read `at`.
static func _since(at: float) -> float:
	return (Contracts.clock() - at) / maxf(Contracts.hours_rate(), 0.000001)


static func _length(pts: PackedVector3Array) -> float:
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k].distance_to(pts[k - 1])
	return length


## The bell at the counter: the sales office's own when it has one.
func _on_arrived(v: CustomerView) -> void:
	ring_bell(v.global_position)


static func ring_bell(at: Vector3) -> void:
	if Sfx.has_method("bell"):
		Sfx.call("bell", at)
		return
	Sfx.play_at("ting", at + Vector3.UP, -2.0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(0.18).timeout.connect(func(): Sfx.play_at("ting", at + Vector3.UP, -5.0))


## The customer under the crosshair of the player on foot, or 0.
func looked_at() -> int:
	if main == null or main.walker == null or main.bike != null:
		return 0
	if Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0:
		return 0
	var cam: Camera3D = main.walker.camera
	if cam == null or not cam.is_inside_tree():
		return 0
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH, Workshop.INTERACT_LAYER | 1)
	q.exclude = [main.walker.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and (hit["collider"] as Object).has_meta("customer"):
		var id := int((hit["collider"] as Object).get_meta("customer"))
		if views.has(id) and is_instance_valid(views[id]) and (views[id] as CustomerView).at_counter:
			return id
	return 0


func _process(_delta: float) -> void:
	var id := looked_at() if main and main.walker and main.walker.controls_enabled else 0
	if id != _looked:
		if views.has(_looked) and is_instance_valid(views[_looked]):
			(views[_looked] as CustomerView).set_hint(false)
		if views.has(id):
			(views[id] as CustomerView).set_hint(true)
		_looked = id


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or main == null or main.walker == null or not main.walker.controls_enabled:
		return
	var id := looked_at()
	if id != 0 and Contracts.customers().has(id):
		get_viewport().set_input_as_handled()
		talk_requested.emit(id)
