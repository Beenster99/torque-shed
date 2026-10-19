class_name BikeCopyView
extends Node
## Which bike the player on foot is looking at, for "Order one of these" and "Copy its blueprint"
## (see BikeCopy): one ray from the eyes each frame. Any of these counts:
##   - one of the shed's bikes, wherever it is (meta "bike": a bay, the yard, parked at the
##     roadside on an adventure), and a crew mate's while they ride it (RemoteBike, "shed_bike"),
##   - a customer's or a part-exchange buyer's bike (CustomerView, "bike_view") and a cafe
##     biker's parked bike ("coffee_bike"),
##   - a rider going past on the roads ("traffic_seed", seen from further off: they don't stop),
##   - a bike parked out front of an adventure's bike cafe (ParkedBike, "parked_bike").
## It puts the key in the HUD's prompts (Walker.bike_prompt, and what the bike is in
## Walker.bike_info when nothing else says) and {order_bike} asks Main to open its card.
## Local only: nothing here is shared.

signal order_requested(src: Dictionary, title: String)

const REACH := 4.5
## The riders on the roads go by: they can be picked out from this far.
const TRAFFIC_REACH := 30.0

var main: Node
## What's looked at now: {src (as BikeCopy takes it), title, info}, or {}.
var looked := {}
var _cache_key := ""
var _cache := {}


func _process(_delta: float) -> void:
	var pt := Perf.t0()
	var now := _looked_at()
	looked = now
	var w: Walker = main.walker if main else null
	if w:
		w.bike_info = str(now.get("info", ""))
		w.bike_prompt = "{order_bike}: order one of these, or copy its blueprint" if not now.is_empty() else ""
	Perf.add("bike_copy", pt)


func _looked_at() -> Dictionary:
	if main == null or main.walker == null or main.bike != null or not main.in_session:
		return {}
	var w: Walker = main.walker
	if not w.controls_enabled or not w.can_process() or not w.is_inside_tree():
		return {}
	if Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0 or Shed.held_by(Shed.me()) != 0:
		return {}
	var cam: Camera3D = w.camera
	if cam == null or not cam.is_inside_tree() or not cam.current:
		return {}
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * TRAFFIC_REACH, 1 | 2 | 4 | Workshop.INTERACT_LAYER)
	q.exclude = [w.get_rid()]
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit:
		return {}
	var c: Object = hit["collider"]
	var near := from.distance_to(hit["position"]) <= REACH
	# Working out a bike's style takes a moment: the same thing looked at keeps its answer a while.
	var key := "%d|%s|%d" % [c.get_instance_id(), near, Engine.get_process_frames() / 30]
	if key != _cache_key:
		_cache_key = key
		_cache = _resolve(c, near)
	return _cache


func _resolve(c: Object, near: bool) -> Dictionary:
	if c.has_meta("traffic_seed"):
		var look := RoadTraffic.look_of(int(c.get_meta("traffic_seed")))
		var n := BikeCopy.default_name(look["parts"])
		return {"src": BikeCopy.build_src(n, look["parts"], look["paint"], {}, false), "title": n, "info": "A rider going by on a %s" % n}
	if not near:
		return {}
	if c.has_meta("bike") and Shed.bikes.has(int(c.get_meta("bike"))):
		var id := int(c.get_meta("bike"))
		return {"src": {"bike": id}, "title": str(Shed.bikes[id]["name"]), "info": str(Shed.bikes[id]["name"])}
	if c.has_meta("shed_bike") and Shed.bikes.has(int(c.get_meta("shed_bike"))):
		var id := int(c.get_meta("shed_bike"))
		var who := str(Shed.crew.get(int(Shed.bikes[id]["rider"]), {}).get("name", "A crew mate"))
		return {"src": {"bike": id}, "title": str(Shed.bikes[id]["name"]), "info": "%s on %s" % [who, Shed.bikes[id]["name"]]}
	if c.has_meta("coffee_bike") and main.get("coffee_view") != null:
		var cv = main.coffee_view.views.get(int(c.get_meta("coffee_bike")))
		return _view_look(cv)
	if c.has_meta("bike_view"):
		return _view_look(c.get_meta("bike_view"))
	if c.has_meta("parked_bike"):
		var pb = c.get_meta("parked_bike")
		if pb is ParkedBike and is_instance_valid(pb):
			var n: String = (pb as ParkedBike).bike_name()
			return {"src": (pb as ParkedBike).bike_src(), "title": n, "info": "Parked up: %s" % n}
	return {}


## A customer's or cafe biker's bike (CustomerView).
func _view_look(cv) -> Dictionary:
	if not (cv is CustomerView) or not is_instance_valid(cv):
		return {}
	var src: Dictionary = (cv as CustomerView).bike_src()
	if src.is_empty():
		return {}
	var n := str(src["build"]["name"])
	return {"src": src, "title": n, "info": n}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("order_bike") or looked.is_empty():
		return
	get_viewport().set_input_as_handled()
	order_requested.emit(looked["src"], str(looked["title"]))
