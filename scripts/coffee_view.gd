class_name CoffeeView
extends Node3D
## What goes on at the coffee shop, drawn from Shed.coffee (see CoffeeShop) on every player's
## game; nothing here is shared state.
##   - The bikers (CoffeeVisitor): riding in and parking, sitting over a coffee, wandering over to
##     the showroom, walking back to their bikes and riding off, or walking away from a bike
##     they've sold to the shed. Look at one, or at their parked bike, and the HUD's look panel
##     says who they are and what the bike is (like anything else you look at: see tooltip());
##     press F to talk to them about it and make an offer (CoffeePanel).
##   - The barista behind the counter while it's open. Look at the counter or them and press F
##     to order.
##   - Trays put down about the place, with whatever's still on them.
## Main makes one and puts it in the world (like SalesView).

signal talk_requested(visitor_id: int)
signal order_requested

const REACH := 3.5
## Real seconds a visitor's leaving is still drawn for someone who only just sees it (joining
## part-way through).
const LATE := 20.0

var main: Node                 # for the walker and whether a menu is open
var views := {}                # visitor id -> CoffeeVisitor
var trays := {}                # tray id -> its model, put down
var barista: CustomerView
var _states := {}              # visitor id -> the state last drawn
var _tray_sigs := {}
var _looked := {}
var _tip := ["", ""]           # the look panel's text and prompt last handed to the walker


func _ready() -> void:
	Shed.changed.connect(sync_state)


## Brings the bikers, the barista and the trays into line with Shed.coffee.
func sync_state() -> void:
	if not Shed.active:
		for id in views.keys():
			if is_instance_valid(views[id]):
				views[id].queue_free()
		views.clear()
		_states.clear()
		for id in trays.keys():
			if is_instance_valid(trays[id]):
				trays[id].queue_free()
		trays.clear()
		_tray_sigs.clear()
		if is_instance_valid(barista):
			barista.queue_free()
		barista = null
		return
	_sync_visitors()
	_sync_trays()
	_sync_barista()


## Real seconds since the cafe's clock read `at`.
static func _since(at: float) -> float:
	return (CoffeeShop.clock() - at) / maxf(Contracts.hours_rate(), 0.000001)


## A visitor's bike as CustomerView draws it.
static func bike_look(v: Dictionary) -> Dictionary:
	var b: Dictionary = v.get("bike", {})
	var paint: Color = Shed.PAINTS[int(b.get("paint", 0)) % Shed.PAINTS.size()]
	return SalesView._bike_look(b.get("parts", {}), paint, b.get("cond", {}))


# ---------------------------------------------------------------------------- the bikers

func _sync_visitors() -> void:
	var now := CoffeeShop.visitors()
	for id in views.keys():
		if now.has(id):
			continue
		var cv = views[id]
		views.erase(id)
		# Gone while still sitting about: the shed was reset. Ones leaving finish leaving.
		if is_instance_valid(cv) and str(_states.get(id, "")) in ["in", "browse"]:
			cv.queue_free()
		_states.erase(id)
	for id in _states.keys():
		if not now.has(id):
			_states.erase(id)
	for id in now:
		var v: Dictionary = now[id]
		var st := str(v["state"])
		if str(_states.get(id, "")) == st:
			continue
		var prev := str(_states.get(id, ""))
		_states[id] = st
		var cv: CoffeeVisitor = views.get(id) if is_instance_valid(views.get(id)) else null
		if cv == null:
			if prev == "":
				_spawn(v)
			continue
		_move_on(cv, v, prev)


## A visitor seen for the first time: drawn wherever they've got to.
func _spawn(v: Dictionary) -> void:
	var st := str(v["state"])
	var id := int(v["id"])
	var park := int(v.get("park", 0))
	var seat := int(v.get("seat", 0))
	if st == "sold" or (st == "out" and _since(float(v.get("since", 0.0))) > LATE):
		return
	var ride := CoffeeShop.ride_in(park, id)
	var walk := CoffeeShop.walk_to_seat(park, seat)
	var ride_secs := SalesView._length(ride) / Contracts.RIDE_SPEED * 1.5 + 2.0
	var walk_secs := SalesView._length(walk) / Contracts.WALK_SPEED + 1.0
	var since := _since(float(v.get("arrived", 0.0)))
	var cv := CoffeeVisitor.new()
	add_child(cv)
	cv.setup_visitor(v, bike_look(v), st != "in" or since > ride_secs)
	views[id] = cv
	match st:
		"in":
			if since > ride_secs + walk_secs:
				cv.sit_now(seat)
			else:
				cv.walk_to_seat(park, seat)
		"browse":
			cv.look_now(int(v.get("stand", 0)), int(v.get("look_k", 0)))
		"out":
			cv.go(PackedVector3Array(), "mount", CoffeeShop.ride_out(park, int(v["id"])))


## A visitor drawn already does what they're doing now.
func _move_on(cv: CoffeeVisitor, v: Dictionary, prev: String) -> void:
	var park := int(v.get("park", 0))
	var seat := int(v.get("seat", 0))
	var stand := int(v.get("stand", -1))
	var k := int(v.get("look_k", 0))
	match str(v["state"]):
		"in":
			cv.go(CoffeeShop.walk_to_seat(park, seat), "sit_at:%d" % seat)
		"browse":
			cv.go(CoffeeShop.walk_to_showroom(seat, stand, k), "look", PackedVector3Array(), CoffeeShop.showroom_xf(stand, k).basis)
		"out":
			cv.leaving = true
			var back := CoffeeShop.walk_showroom_to_bike(stand, park, k) if prev == "browse" else CoffeeShop.walk_from_seat(seat, park)
			cv.go(back, "mount", CoffeeShop.ride_out(park, int(v["id"])))
		"sold":
			# Their bike's the shed's now (drawn by the shed): they walk off for a lift home.
			cv.leaving = true
			cv.set_hint(false)
			cv.drop_bike()
			cv.go(CoffeeShop.walk_off(seat, stand if prev == "browse" else -1, k), "gone")


# ---------------------------------------------------------------------------- the barista

func _sync_barista() -> void:
	var open := CoffeeShop.is_open()
	if open and not is_instance_valid(barista):
		barista = CustomerView.new()
		add_child(barista)
		barista.setup({"id": CoffeeShop.BARISTA_ID, "name": "Jo (barista)", "look": {"top": Color(0.1, 0.3, 0.22),
			"legs": Color(0.12, 0.1, 0.09), "skin": Color(0.78, 0.58, 0.44), "hair": Color(0.45, 0.2, 0.08)}},
			PackedVector3Array([CoffeeShop.BARISTA.origin]), CoffeeShop.BARISTA.basis, true)
		barista.name = "Barista"
	elif not open and is_instance_valid(barista):
		barista.queue_free()
		barista = null


# ---------------------------------------------------------------------------- trays

func _sync_trays() -> void:
	var all := CoffeeShop.trays()
	for id in trays.keys():
		if not all.has(id) or int(all[id]["holder"]) != 0:
			if is_instance_valid(trays[id]):
				trays[id].queue_free()
			trays.erase(id)
			_tray_sigs.erase(id)
	for id in all:
		var t: Dictionary = all[id]
		if int(t["holder"]) != 0:
			continue
		var sig := "%s|%s" % [str(t["items"]), str(t["xf"])]
		if _tray_sigs.get(id, "") == sig and is_instance_valid(trays.get(id)):
			continue
		if is_instance_valid(trays.get(id)):
			trays[id].queue_free()
		var model := tray_model(t["items"])
		model.name = "Tray%d" % int(id)
		var body := StaticBody3D.new()
		body.collision_layer = Workshop.INTERACT_LAYER
		body.collision_mask = 0
		body.set_meta("coffee_tray", int(id))
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.46, 0.16, 0.34)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.08
		body.add_child(cs)
		model.add_child(body)
		add_child(model)
		model.global_transform = t["xf"]
		trays[id] = model
		_tray_sigs[id] = sig


## A tray with `items` on it: a cup of coffee or tea, a slice of cake or a sandwich on a plate in
## each corner. Its middle is at its foot.
static func tray_model(items: Array) -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(0.0, 0.01, 0.0), Vector3(0.44, 0.02, 0.32), Color(0.55, 0.12, 0.08), 0.4))
	for side in [-1.0, 1.0]:
		root.add_child(_box(Vector3(0.21 * side, 0.025, 0.0), Vector3(0.02, 0.03, 0.32), Color(0.5, 0.1, 0.07), 0.4))
		root.add_child(_box(Vector3(0.0, 0.025, 0.15 * side), Vector3(0.44, 0.03, 0.02), Color(0.5, 0.1, 0.07), 0.4))
	var spots := [Vector3(-0.1, 0.02, -0.07), Vector3(0.1, 0.02, -0.07), Vector3(-0.1, 0.02, 0.07), Vector3(0.1, 0.02, 0.07)]
	for i in mini(items.size(), spots.size()):
		var at: Vector3 = spots[i]
		match str(items[i]):
			"coffee", "tea":
				root.add_child(_cyl(at + Vector3(0.0, 0.005, 0.0), 0.06, 0.01, Color(0.95, 0.94, 0.9)))
				root.add_child(_cyl(at + Vector3(0.0, 0.05, 0.0), 0.038, 0.08, Color(0.95, 0.94, 0.9)))
				var drink := Color(0.25, 0.14, 0.07) if str(items[i]) == "coffee" else Color(0.55, 0.33, 0.16)
				root.add_child(_cyl(at + Vector3(0.0, 0.088, 0.0), 0.033, 0.004, drink))
			"cake":
				root.add_child(_cyl(at + Vector3(0.0, 0.005, 0.0), 0.075, 0.01, Color(0.95, 0.94, 0.9)))
				root.add_child(_box(at + Vector3(0.0, 0.035, 0.0), Vector3(0.07, 0.05, 0.09), Color(0.95, 0.82, 0.6), 0.7))
				root.add_child(_box(at + Vector3(0.0, 0.063, 0.0), Vector3(0.072, 0.008, 0.092), Color(0.96, 0.6, 0.7), 0.5))
			"sandwich":
				root.add_child(_cyl(at + Vector3(0.0, 0.005, 0.0), 0.075, 0.01, Color(0.95, 0.94, 0.9)))
				for j in 2:
					var piece := _box(at + Vector3(-0.02 + 0.04 * j, 0.03, 0.0), Vector3(0.035, 0.04, 0.09), Color(0.86, 0.7, 0.46), 0.8)
					piece.rotation.y = 0.3 - 0.6 * j
					root.add_child(piece)
	root.set_meta("items", items.size())
	return root


static func _box(at: Vector3, size: Vector3, c: Color, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = at
	mi.material_override = _flat_mat(c, rough)
	return mi


static func _cyl(at: Vector3, r: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r * 0.85
	m.height = h
	m.radial_segments = 12
	mi.mesh = m
	mi.position = at
	mi.material_override = _flat_mat(c, 0.3)
	return mi


static func _flat_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# ---------------------------------------------------------------------------- looking and talking

## What the player on foot is looking at here: {"visitor": id} (a biker or their bike, with
## "bike": true for the bike), {"counter": true}, or {}.
func looked_at() -> Dictionary:
	if main == null or main.walker == null or main.bike != null:
		return {}
	if Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0:
		return {}
	var cam: Camera3D = main.walker.camera
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH, Workshop.INTERACT_LAYER | 1)
	q.exclude = [main.walker.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit:
		return {}
	var c: Object = hit["collider"]
	if c.has_meta("coffee_counter"):
		return {"counter": true}
	if c.has_meta("coffee_bike"):
		var bid := int(c.get_meta("coffee_bike"))
		return {"visitor": bid, "bike": true} if _talkable(bid) else {}
	if c.has_meta("customer"):
		var id := int(c.get_meta("customer"))
		if id == CoffeeShop.BARISTA_ID:
			return {"counter": true}
		id -= CoffeeShop.ID_BASE
		return {"visitor": id} if _talkable(id) else {}
	return {}


## Whether visitor `id` is drawn here and can be talked to.
func _talkable(id: int) -> bool:
	var v: Dictionary = CoffeeShop.visitors().get(id, {})
	return views.has(id) and is_instance_valid(views[id]) and CoffeeShop.here(v) and not (views[id] as CoffeeVisitor).leaving


func _process(_delta: float) -> void:
	var now := looked_at() if main and main.walker and main.walker.controls_enabled else {}
	if now != _looked:
		_show_hint(_looked, false)
		_show_hint(now, true)
		_looked = now
	# What they're looking at goes in the HUD's look panel, the same as everything else.
	var tip := tooltip(now)
	if tip != _tip and main and main.walker:
		_tip = tip
		main.walker.look_info = tip[0]
		main.walker.look_prompt = tip[1]


func _show_hint(at: Dictionary, on: bool) -> void:
	var id := int(at.get("visitor", 0))
	if not views.has(id) or not is_instance_valid(views[id]):
		return
	var cv: CoffeeVisitor = views[id]
	if at.get("bike", false):
		cv.set_bike_hint(on)
	else:
		cv.set_hint(on)


## The look panel for what's under the crosshair here (see looked_at): [title and lines, the
## key prompt], or two empty strings for nothing of ours.
static func tooltip(at: Dictionary) -> Array:
	var key := Settings.binding_text("interact", false)
	key = key if key != "" else "F"
	if at.get("counter", false):
		if not CoffeeShop.is_open():
			return ["Pit Stop Cafe\n%s" % CoffeeShop.hours_text(), ""]
		var menu := []
		for item in CoffeeShop.MENU_ORDER:
			menu.append("%s %s" % [CoffeeShop.item_name(item), CoffeeShop.money(CoffeeShop.price(item))])
		return ["Pit Stop Cafe\n%s\n%s" % [CoffeeShop.hours_text(), "  ·  ".join(menu)], "%s: order" % key]
	if not at.has("visitor"):
		return ["", ""]
	var v: Dictionary = CoffeeShop.visitors().get(int(at["visitor"]), {})
	var who := CoffeeShop.first_name(v)
	var b: Dictionary = v.get("bike", {})
	var lines := []
	if at.get("bike", false):
		lines.append("%s's bike" % who)
	else:
		lines.append(str(v.get("name", who)))
		lines.append("Looking round the showroom" if str(v.get("state", "")) == "browse" else "Stopped for a coffee, on their own bike")
	lines.append("%s  ·  %s" % [str(b.get("style_text", "A bike")), str(b.get("model", ""))])
	lines.append("%d hp  ·  %d%% condition  ·  worth about %s" % [int(b.get("hp", 0)), roundi(float(b.get("condition", 0.0)) * 100.0),
		CoffeeShop.money(CoffeeShop.rough_value(v))])
	return ["\n".join(lines), "%s: talk to %s about the bike (make an offer)" % [key, who]]


## The hint showing now (tests): "counter", "bike:<id>", "visitor:<id>" or "".
func hint_text() -> String:
	if _looked.get("counter", false):
		return "counter"
	if _looked.has("visitor"):
		return "%s:%d" % ["bike" if _looked.get("bike", false) else "visitor", int(_looked["visitor"])]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or main == null or main.walker == null or not main.walker.controls_enabled:
		return
	var at := looked_at()
	if at.get("counter", false):
		get_viewport().set_input_as_handled()
		order_requested.emit()
	elif at.has("visitor"):
		get_viewport().set_input_as_handled()
		talk_requested.emit(int(at["visitor"]))
