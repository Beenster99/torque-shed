class_name ContractsView
extends Node3D
## Draws the customers in Shed.contracts as people walking in to reception (see CustomerView),
## rings the bell as each one gets to the counter, and opens the offer card when a player on
## foot looks at one and presses F. Main makes one and puts it in the world.

signal talk_requested(customer_id: int)

const REACH := 3.5

var main: Node                 # for the walker and whether a menu is open
var views := {}                # customer id -> CustomerView
var _looked := 0


func _ready() -> void:
	Shed.changed.connect(sync_state)


## Brings the figures into line with the customers waiting now.
func sync_state() -> void:
	var waiting: Array = Contracts.customers().keys()
	waiting.sort_custom(func(a, b): return float(Contracts.customers()[a]["arrived"]) < float(Contracts.customers()[b]["arrived"]))
	for id in views.keys():
		if not is_instance_valid(views[id]):
			views.erase(id)
		elif not waiting.has(id):
			(views[id] as CustomerView).leave()
			views.erase(id)
	var face := Contracts.reception().basis
	for i in waiting.size():
		var id: int = waiting[i]
		var walk := Contracts.path_in(i)
		if views.has(id):
			(views[id] as CustomerView).move_to(walk[walk.size() - 1])
			continue
		var c: Dictionary = Contracts.customers()[id]
		var length := 0.0
		for k in range(1, walk.size()):
			length += walk[k].distance_to(walk[k - 1])
		var rate := Contracts.hours_rate()
		var since := (Contracts.clock() - float(c.get("arrived", 0.0))) / maxf(rate, 0.000001)
		var v := CustomerView.new()
		add_child(v)
		v.setup(c, walk, face, since > length / Contracts.WALK_SPEED + 1.0)
		v.arrived.connect(_on_arrived)
		views[id] = v


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
