class_name Workshop
extends Node3D
## The shed: a snug workshop with a roller door onto the Build Yard. Inside are four bike bays
## with paddock stands and a screen above each, a workbench, an engine stand, a parts computer
## with delivery pallets, a parts washer, a repair bench, a bin and the crew board. It also
## draws every parked bike and every loose part from the shared Shed state.

const CENTER := Vector3(0.0, 0.0, 65.0)
const HALF := Vector2(6.5, 5.5)           # interior half size in x and z
const HEIGHT := 4.5
const DOOR_HALF := 2.3
const DOOR_HEIGHT := 3.2
const BAY_COUNT := 4
const INTERACT_LAYER := 8
## The wash bay: a lean-to on the west wall, open to the yard, with a pressure washer whose
## hose reaches anywhere inside it and a little way out.
const WASH_CENTER := Vector3(-9.3, 0.0, 66.0)
const WASH_HALF := Vector2(2.4, 3.4)
const WASH_POS := Vector3(-11.3, 0.0, 63.2)
const WASH_REACH := 8.0

var bike_views := {}       # bike id -> Node3D holding a BikeModel
var _view_sigs := {}
var _spot_nodes := {}      # spot -> Node3D
var _spot_sigs := {}
var furniture_nodes := {} # furniture id -> Node3D (engine stands and shelving units)
var _furniture_sigs := {}
var _floor_nodes := {}     # item id -> Node3D for parts put down anywhere
var _floor_sigs := {}
var _bay_screens: Array[Dashboard] = []
var _crew_screen: Dashboard
var _dash_timer := 0.0
var _dash_dirty := true
var _mats := {}
var radio: ShedRadio
var _washer_sound: AudioStreamPlayer3D


static func bay_transform(bay: int) -> Transform3D:
	var x := -4.8 + 3.2 * clampi(bay, 0, BAY_COUNT - 1)
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.0, -3.5))


## Where each work spot puts a part, and which way it faces.
static func spot_transform(spot: String) -> Transform3D:
	if spot.begins_with("bench_"):
		var i := int(spot.trim_prefix("bench_"))
		return Transform3D(Basis(), CENTER + Vector3(-HALF.x + 0.5, 0.96, -1.2 + i * 1.2))
	if spot.begins_with("delivery_"):
		var i := int(spot.trim_prefix("delivery_"))
		return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(-5.6 + (i % 2) * 1.2, 0.16, 3.8 + (i / 2) * 1.1))
	match spot:
		"engine_stand":
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), CENTER + Vector3(HALF.x - 0.9, 0.72, -0.4))
		"washer":
			return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(HALF.x - 1.05, 0.86, HALF.y - 0.6))
		"repair":
			return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(3.4, 0.96, HALF.y - 0.6))
	return Transform3D(Basis(), CENTER)


## Where players appear on foot when they arrive.
static func walker_spawn(index: int) -> Transform3D:
	var x := -1.5 + (index % 4) * 1.0
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.1, 2.6 - (index / 4) * 1.0))


func build() -> void:
	name = "Workshop"
	add_to_group("workshop")
	_make_materials()
	_build_shell()
	_build_bays()
	_build_bench()
	_build_computer()
	_build_delivery_area()
	_build_washer()
	_build_repair_bench()
	_build_bin()
	_build_tool_wall()
	_build_radio()
	_build_wash_bay()
	_build_lights()
	_crew_screen = Dashboard.new("crew", 3.0)
	_crew_screen.position = CENTER + Vector3(-HALF.x + 0.1, 2.55, 0.6)
	_crew_screen.rotation.y = PI * 0.5
	add_child(_crew_screen)


# ---------------------------------------------------------------------------- state

## Redraws parked bikes, loose parts and screens to match the Shed state.
func sync_state() -> void:
	for id in bike_views.keys():
		if not Shed.bikes.has(id) or Shed.bikes[id]["rider"] != 0:
			bike_views[id].queue_free()
			bike_views.erase(id)
			_view_sigs.erase(id)
	for id in Shed.bikes:
		var bike: Dictionary = Shed.bikes[id]
		if bike["rider"] != 0:
			continue
		var sig := _bike_signature(id)
		if _view_sigs.get(id, "") != sig:
			_view_sigs[id] = sig
			if bike_views.has(id):
				bike_views[id].free()
			bike_views[id] = _make_bike_view(id)
		# Moving a bike only moves its view; the one you're wheeling follows you directly.
		if bike.get("pusher", 0) != Shed.me() or bike.get("pusher", 0) == 0:
			bike_views[id].transform = bike["xf"]
	_sync_furniture()
	var spots := Shed.all_spots()
	for spot in _spot_nodes.keys():
		if not spots.has(spot):
			_spot_nodes[spot].queue_free()
			_spot_nodes.erase(spot)
			_spot_sigs.erase(spot)
	for spot in spots:
		var item_id := Shed.item_at_spot(spot)
		var sig := "" if item_id == 0 else _item_signature(item_id)
		if _spot_sigs.get(spot, "") == sig:
			continue
		_spot_sigs[spot] = sig
		if _spot_nodes.has(spot):
			_spot_nodes[spot].free()
			_spot_nodes.erase(spot)
		if item_id != 0:
			var display := BikeModel.item_display(item_id)
			var f := Shed.furniture_of_spot(spot)
			if f.is_empty():
				display.transform = spot_transform(spot)
				add_child(display)
			else:
				# Parts on a stand or shelf ride along with it when it's moved.
				display.transform = Shed.local_spot_transform(spot)
				furniture_nodes[int(f["id"])].add_child(display)
			if Shed.is_stand_spot(spot) and Shed.is_engine(item_id) and not Shed.items[item_id].get("boxed", false):
				# Parts on the engine can be worked on right there; the block itself is picked up.
				var model: BikeModel = display.get_meta("model")
				model.build_pickers({"engine": item_id}, {"engine": {"spot": spot}})
			_spot_nodes[spot] = display
	_sync_floor()
	radio.sync()
	var washing := Shed.item_at_spot("washer")
	Sfx.set_loop(_washer_sound, "washer" if washing != 0 and float(Shed.items[washing]["dirt"]) > 0.0 else "")
	_dash_dirty = true


# ---------------------------------------------------------------------------- furniture

## Draws engine stands and shelving units where they stand. One being pushed by this player
## follows them directly (see preview_furniture), so it doesn't lag behind.
func _sync_furniture() -> void:
	for id in furniture_nodes.keys():
		if not Shed.furniture.has(id):
			furniture_nodes[id].queue_free()
			furniture_nodes.erase(id)
			_furniture_sigs.erase(id)
	for id in Shed.furniture:
		var f: Dictionary = Shed.furniture[id]
		if not furniture_nodes.has(id):
			furniture_nodes[id] = _make_stand(id) if f["kind"] == "stand" else _make_shelf(id)
		var node: Node3D = furniture_nodes[id]
		if f["mover"] != Shed.me() or f["mover"] == 0:
			node.transform = f["xf"]
		var label: Label3D = node.get_node_or_null("Label")
		if label:
			label.text = str(f.get("label", ""))


func preview_bike(id: int, xf: Transform3D) -> void:
	if bike_views.has(id):
		bike_views[id].transform = xf


func preview_furniture(id: int, xf: Transform3D) -> void:
	if furniture_nodes.has(id):
		furniture_nodes[id].transform = xf


## A red engine stand on castors: a column with a turning head that the block bolts to.
func _make_stand(id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Stand%d" % id
	add_child(root)
	var red: Material = _mats["red"]
	_deco(root, Vector3(0.0, 0.05, 0.0), Vector3(0.7, 0.06, 0.08), red)
	_deco(root, Vector3(0.25, 0.05, 0.0), Vector3(0.08, 0.06, 0.8), red)
	_deco(root, Vector3(0.25, 0.32, 0.0), Vector3(0.09, 0.56, 0.09), red)
	_deco(root, Vector3(0.12, 0.58, 0.0), Vector3(0.26, 0.06, 0.06), _mats["steel"])
	_deco(root, Vector3(0.0, 0.58, 0.0), Vector3(0.04, 0.24, 0.24), _mats["steel"])
	_deco(root, Vector3(0.25, 0.75, 0.0), Vector3(0.04, 0.04, 0.5), _mats["steel"]).name = "Handle"
	for p in [Vector3(-0.32, 0.03, 0.0), Vector3(0.25, 0.03, -0.37), Vector3(0.25, 0.03, 0.37)]:
		_deco(root, p, Vector3(0.06, 0.06, 0.06), _mats["dark"]).name = "Caster"
	_blocker(Vector3(0.0, 0.3, 0.0), Vector3(0.7, 0.6, 0.8), root)
	_target(Vector3(0.25, 0.4, 0.0), Vector3(0.2, 0.8, 0.9), {"furniture": id}, root)
	_target(Vector3(0.0, 0.62 + 0.18, 0.0), Vector3(0.7, 0.35, 0.7), {"spot": "stand_%d" % id}, root)
	return root


## A steel shelving unit: three shelves, two places on each, and a label plate on top.
func _make_shelf(id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Shelf%d" % id
	add_child(root)
	var frame: Material = _material(Color(0.2, 0.32, 0.5), 0.6, 0.45)
	var board: Material = _material(Color(0.62, 0.6, 0.56), 0.5, 0.55)
	for x in [-0.58, 0.58]:
		for z in [-0.22, 0.22]:
			_deco(root, Vector3(x, 0.92, z), Vector3(0.04, 1.84, 0.04), frame)
	for level in 4:
		var y := 0.06 + level * 0.6
		_deco(root, Vector3(0.0, y, 0.0), Vector3(1.2, 0.03, 0.48), board)
	_blocker(Vector3(0.0, 0.92, 0.0), Vector3(1.2, 1.84, 0.48), root)
	for n in Shed.SHELF_SLOTS:
		var spot := "shelf_%d_%d" % [id, n]
		var at := Shed.local_spot_transform(spot).origin
		_target(at + Vector3(0.0, 0.26, 0.03), Vector3(0.56, 0.5, 0.5), {"spot": spot}, root)
	var plate := _deco(root, Vector3(0.0, 1.72, 0.25), Vector3(0.7, 0.14, 0.01), _material(Color(0.88, 0.86, 0.8), 0.0, 0.8))
	plate.name = "Plate"
	_target(Vector3(0.0, 1.72, 0.25), Vector3(0.74, 0.18, 0.06), {"label": id}, root)
	_target(Vector3(0.0, 1.9, 0.0), Vector3(1.24, 0.12, 0.52), {"furniture": id}, root)
	var label := Label3D.new()
	label.name = "Label"
	label.font_size = 36
	label.pixel_size = 0.002
	label.modulate = Color(0.12, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(0.0, 1.72, 0.257)
	root.add_child(label)
	return root


## Parts put down anywhere, each with a box around it to aim at and pick it up by.
func _sync_floor() -> void:
	var loose := Shed.floor_items()
	for id in _floor_nodes.keys():
		if not loose.has(id):
			_floor_nodes[id].queue_free()
			_floor_nodes.erase(id)
			_floor_sigs.erase(id)
	for id in loose:
		var xf: Transform3D = Shed.items[id]["ref"]
		var sig := _item_signature(id) + str(xf)
		if _floor_sigs.get(id, "") == sig:
			continue
		_floor_sigs[id] = sig
		if _floor_nodes.has(id):
			_floor_nodes[id].free()
		var display := BikeModel.item_display(id)
		display.transform = xf
		add_child(display)
		var size: Vector3 = display.get_meta("size", Vector3.ONE * 0.3)
		size = size.max(Vector3(0.12, 0.08, 0.12))
		var body := StaticBody3D.new()
		body.collision_layer = INTERACT_LAYER
		body.collision_mask = 0
		body.set_meta("item", id)
		body.position = Vector3(0.0, size.y * 0.5, 0.0)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		display.add_child(body)
		_floor_nodes[id] = display


## The model a part target is drawn on: a parked bike, or the engine on the stand.
func model_for(target: Dictionary) -> BikeModel:
	var engine := int(target.get("engine", 0))
	if engine != 0:
		var spot := str(Shed.items.get(engine, {}).get("ref", ""))
		if _spot_nodes.has(spot):
			return _spot_nodes[spot].get_meta("model", null)
		return null
	if bike_views.has(target.get("bike", 0)):
		return bike_model(int(target["bike"]))
	return null


## The model drawn for a parked bike (inside its lean pivot).
func bike_model(id: int) -> BikeModel:
	return bike_views[id].get_child(0).get_child(0) as BikeModel


## Every part within `radius` of a point: fitted to parked bikes, on the engine stand, on the
## work spots or put down anywhere. Used by the brush to scrub everything it touches.
func items_near(at: Vector3, radius: float) -> Array:
	var out := []
	for id in bike_views:
		var model: BikeModel = bike_model(id)
		for slot in PartsDB.SLOTS:
			var item := Shed.item_at_target({"bike": id, "slot": slot})
			if item != 0 and _near(model, model.slot_bounds(slot), at, radius):
				out.append(item)
	for spot in _spot_nodes:
		var node: Node3D = _spot_nodes[spot]
		var item := Shed.item_at_spot(spot)
		var model: BikeModel = node.get_meta("model", null)
		if Shed.is_engine(item) and model:
			for slot in PartsDB.ENGINE_SLOTS:
				var sub := Shed.engine_item(item, slot)
				if sub != 0 and _near(model, model.slot_bounds(slot), at, radius):
					out.append(sub)
			if _near(model, model.slot_bounds("engine"), at, radius):
				out.append(item)
		elif item != 0 and node.global_position.distance_to(at) < radius + 0.3:
			out.append(item)
	for id in _floor_nodes:
		var node: Node3D = _floor_nodes[id]
		var size: Vector3 = node.get_meta("size", Vector3.ONE * 0.3)
		if (node.global_position + Vector3.UP * size.y * 0.5).distance_to(at) < radius + size.length() * 0.5:
			out.append(id)
	return out


func _near(model: BikeModel, box: AABB, at: Vector3, radius: float) -> bool:
	if box.size == Vector3.ZERO:
		return false
	var local := model.global_transform.affine_inverse() * at
	var closest := local.clamp(box.position, box.end)
	return closest.distance_to(local) < radius


func _item_signature(item_id: int) -> String:
	var it: Dictionary = Shed.items[item_id]
	var sig := "%d:%s:%.1f:%.1f:%.1f:%s:%s:%s" % [item_id, it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", ""),
		"%.1f" % float(it["fluid"]["litres"]) if it.has("fluid") and PartsDB.is_fluid(it["part"]) else ""]
	if Shed.is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := Shed.engine_item(item_id, slot)
			sig += "|" + ("-" if sub == 0 else _item_signature(sub) + str(Shed.engine_bolted(item_id, slot)))
	return sig


func _bike_signature(id: int) -> String:
	var bike: Dictionary = Shed.bikes[id]
	var parts := []
	for slot in PartsDB.SLOTS:
		var item_id := Shed.item_on(id, slot)
		if item_id == 0:
			parts.append("-")
		else:
			var it: Dictionary = Shed.items[item_id]
			parts.append("%s:%.1f:%.1f:%.1f:%s:%s:%s" % [it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", ""), Shed.is_bolted(id, slot)])
	var pose := "paddock" if Shed.on_paddock(id) and bike.get("pusher", 0) == 0 else str(bike.get("stand", ""))
	return "%s|%s|%s" % [",".join(parts), pose, str(bike["paint"])]


func _make_bike_view(id: int) -> Node3D:
	var bike: Dictionary = Shed.bikes[id]
	var view := Node3D.new()
	view.name = "Bike%d" % id
	view.transform = bike["xf"]
	add_child(view)
	var build := Shed.build_of(id)
	var model := BikeModel.new()
	# Leaning on its side stand, or lying on its side, the bike tips over about the tyres' contact line.
	var lean := Node3D.new()
	view.add_child(lean)
	lean.add_child(model)
	var on_stand: bool = Shed.on_paddock(id) and bike.get("pusher", 0) == 0
	var stand := "" if on_stand else str(bike.get("stand", ""))
	var lift := 0.06 if on_stand else 0.0
	if stand == "centre":
		lift = build.centre_lift
	elif stand == "side":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(build.parts["side_stand"]).get("lean", 12.0))))
	elif stand == "down":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(74.0))
		lift = 0.12
	model.position.y = build.rear_radius + lift
	model.stand_pose = stand
	model.build_from(build, bike["paint"], Shed.fitted_map(id), build.condition, false)
	model.build_pickers({"bike": id})
	if on_stand:
		_paddock_stand(view, build)
	return view


func _paddock_stand(parent: Node3D, build: BikeBuild) -> void:
	var steel: Material = _mats["stand"]
	for z in [-build.wheelbase * 0.5 + 0.12, build.wheelbase * 0.5 - 0.15]:
		_deco(parent, Vector3(0.0, 0.03, z), Vector3(0.5, 0.06, 0.08), steel)
		for side in [-1.0, 1.0]:
			_deco(parent, Vector3(0.22 * side, build.rear_radius * 0.5, z), Vector3(0.04, build.rear_radius, 0.04), steel)
	_deco(parent, Vector3(0.0, build.rear_radius - 0.06, 0.0), Vector3(0.12, 0.12, build.wheelbase * 0.55), steel)


func _process(delta: float) -> void:
	_dash_timer -= delta
	if _dash_timer > 0.0:
		return
	_dash_timer = 0.5
	_refresh_dashboards()


func _refresh_dashboards() -> void:
	if not Shed.active:
		return
	if _dash_dirty:
		_dash_dirty = false
		for bay in BAY_COUNT:
			_bay_screens[bay].show_data(_bay_data(bay))
	var players := []
	var ids: Array = Shed.crew.keys()
	ids.sort()
	for peer in ids:
		var c: Dictionary = Shed.crew[peer]
		var doing := str(c.get("activity", ""))
		var riding := int(c.get("riding", 0))
		if riding != 0 and Shed.bikes.has(riding):
			doing = "Riding %s, %s" % [Shed.bikes[riding]["name"], Units.kmh(float(c.get("kmh", 0.0)))]
		elif Shed.held_by(peer) != 0:
			doing = "Carrying " + Shed.item_title(Shed.held_by(peer))
		elif doing == "":
			doing = "Holding the %s" % Walker.TOOL_NAMES.get(c.get("tool", "hands"), "hands").to_lower() if c.get("tool", "hands") != "hands" else "Looking around"
		var p := c.duplicate()
		p["doing"] = doing
		p["color"] = Shed.PAINTS[int(c.get("slot", 0)) % Shed.PAINTS.size()]
		players.append(p)
	_crew_screen.show_data({"players": players})


func _bay_data(bay: int) -> Dictionary:
	var bike_id := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["bay"] == bay:
			bike_id = id
			if Shed.bikes[id]["xf"].origin.distance_to(bay_transform(bay).origin) < 2.5:
				break
	if bike_id == 0:
		return {}
	var bike: Dictionary = Shed.bikes[bike_id]
	var build := Shed.build_of(bike_id)
	var missing := Shed.missing_slots(bike_id)
	var loose := Shed.loose_slots(bike_id)
	var status := "READY TO RIDE"
	if bike["rider"] != 0:
		status = "OUT RIDING: %s" % Shed.crew.get(bike["rider"], {}).get("name", "someone")
	elif not missing.is_empty():
		status = "%d PART%s MISSING" % [missing.size(), "" if missing.size() == 1 else "S"]
	elif not loose.is_empty():
		status = "%d PART%s LOOSE" % [loose.size(), "" if loose.size() == 1 else "S"]
	var parts := []
	var has_engine := Shed.item_on(bike_id, "engine") != 0
	for slot in PartsDB.SLOTS:
		if PartsDB.is_engine_slot(slot) and not has_engine:
			continue
		var item_id := Shed.item_on(bike_id, slot)
		if item_id == 0 and PartsDB.is_optional(slot):
			continue
		var name: String = PartsDB.slot_name(slot)
		if slot == "engine" and not has_engine:
			name = "Engine (out)"
		parts.append({"name": name, "fitted": item_id != 0, "bolted": Shed.is_bolted(bike_id, slot),
			"health": BikeBuild.part_health(Shed.condition_of(Shed.items[item_id])) if item_id != 0 else 0.0})
	var fluids := [
		["Fuel", build.fuel_litres / maxf(build.fuel_capacity, 0.1), build.fuel_age],
		["Oil", build.oil_litres / maxf(build.oil_capacity, 0.1) if has_engine else 0.0, build.oil_age],
		["Brake F", build.brake_fluid["front"], 0.0],
		["Brake R", build.brake_fluid["rear"], 0.0],
	]
	return {"name": bike["name"], "status": status, "now": build.summary(), "delivered": bike["delivered"], "parts": parts,
		"notes": build.notes, "fluids": fluids, "range_km": build.range_km()}


# ---------------------------------------------------------------------------- building

func _make_materials() -> void:
	_mats["floor"] = _material(Color(0.36, 0.37, 0.38), 0.0, 0.3, _noise(0.08, 0.92, 1.04), 6.0)
	_mats["wall_in"] = _material(Color(0.78, 0.76, 0.72), 0.0, 0.85, _noise(0.2, 0.9, 1.04), 2.0)
	_mats["wall_low"] = _material(Color(0.2, 0.24, 0.27), 0.0, 0.6)
	var cladding := _material(Color(0.3, 0.33, 0.36), 0.7, 0.45)
	cladding.normal_enabled = true
	cladding.normal_texture = _corrugation()
	cladding.normal_scale = 1.0
	cladding.uv1_triplanar = true
	cladding.uv1_scale = Vector3(2.5, 2.5, 2.5)
	_mats["cladding"] = cladding
	_mats["roof"] = _material(Color(0.25, 0.27, 0.29), 0.6, 0.5)
	_mats["steel"] = _material(Color(0.3, 0.32, 0.35), 0.85, 0.35)
	_mats["stand"] = _material(Color(0.85, 0.35, 0.05), 0.5, 0.4)
	_mats["wood"] = _material(Color(0.5, 0.36, 0.22), 0.0, 0.7, _noise(0.5, 0.85, 1.08), 3.0)
	_mats["yellow"] = _material(Color(0.95, 0.75, 0.05), 0.0, 0.5)
	_mats["dark"] = _material(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	_mats["box"] = _material(Color(0.62, 0.47, 0.3), 0.0, 0.9, _noise(0.6, 0.9, 1.05), 2.0)
	_mats["blue"] = _material(Color(0.1, 0.3, 0.65), 0.6, 0.35)
	_mats["red"] = _material(Color(0.7, 0.08, 0.06), 0.5, 0.35)
	_mats["chrome"] = _material(Color(0.85, 0.86, 0.88), 1.0, 0.15)


func _material(color: Color, metallic: float, roughness: float, tex: Texture2D = null, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv) * 0.25
	return m


func _noise(freq: float, dark: float, light: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.1
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color(light, light, light))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


## A normal map of vertical ridges, for corrugated steel cladding.
func _corrugation() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.5, 1.0))
	g.set_color(1, Color(0.5, 0.5, 1.0))
	g.add_point(0.25, Color(0.9, 0.5, 0.85))
	g.add_point(0.75, Color(0.1, 0.5, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.repeat = GradientTexture2D.REPEAT
	return tex


func _solid(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


func _deco(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


## Invisible collision, so players can't walk through furniture made of loose meshes.
func _blocker(center: Vector3, size: Vector3, parent: Node3D = self) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


## An invisible click target for the player's hands and tools.
func _target(center: Vector3, size: Vector3, meta: Dictionary, parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = INTERACT_LAYER
	body.collision_mask = 0
	body.position = center
	for key in meta:
		body.set_meta(key, meta[key])
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


## A small printed sign pinned to the wall behind a work area, instead of big floating letters.
func _poster(text: String, pos: Vector3, rot_y: float, size := Vector2(0.56, 0.2)) -> void:
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	paper.mesh = quad
	paper.material_override = _material(Color(0.86, 0.82, 0.7), 0.0, 0.9)
	paper.position = pos
	paper.rotation.y = rot_y
	add_child(paper)
	var ink := Label3D.new()
	ink.text = text
	ink.font_size = 40
	ink.pixel_size = 0.0018
	ink.modulate = Color(0.15, 0.12, 0.1)
	ink.outline_size = 0
	ink.position = Vector3(0.0, 0.0, 0.004)
	paper.add_child(ink)


func _label(text: String, pos: Vector3, rot_y: float, size := 32, color := Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 6
	add_child(l)
	return l


func _build_shell() -> void:
	var c := CENTER
	var hx := HALF.x
	var hz := HALF.y
	var t := 0.3
	# Floor: a polished epoxy slab sitting on the yard concrete, with bay markings.
	var floor_mi := _deco(self, c + Vector3(0.0, 0.004, 0.0), Vector3(hx * 2.0, 0.008, hz * 2.0), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Walls: back, sides, and the front wall either side of the roller door.
	var walls := [
		[c + Vector3(0.0, HEIGHT * 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, HEIGHT, t)],
		[c + Vector3(-hx - t * 0.5, HEIGHT * 0.5, 0.0), Vector3(t, HEIGHT, hz * 2.0)],
		[c + Vector3(hx + t * 0.5, HEIGHT * 0.5, 0.0), Vector3(t, HEIGHT, hz * 2.0)],
	]
	var side_w := hx - DOOR_HALF
	for side in [-1.0, 1.0]:
		walls.append([c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5, hz + t * 0.5), Vector3(side_w + t, HEIGHT, t)])
	walls.append([c + Vector3(0.0, (HEIGHT + DOOR_HEIGHT) * 0.5, hz + t * 0.5), Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_HEIGHT, t)])
	for w in walls:
		_solid(w[0], w[1], _mats["cladding"])
	# Inside faces: painted plaster upper, dark lower band.
	_deco(self, c + Vector3(0.0, HEIGHT * 0.5 + 0.6, -hz + 0.01), Vector3(hx * 2.0, HEIGHT - 1.2, 0.02), _mats["wall_in"])
	_deco(self, c + Vector3(0.0, 0.6, -hz + 0.01), Vector3(hx * 2.0, 1.2, 0.02), _mats["wall_low"])
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * (hx - 0.01), HEIGHT * 0.5 + 0.6, 0.0), Vector3(0.02, HEIGHT - 1.2, hz * 2.0), _mats["wall_in"])
		_deco(self, c + Vector3(side * (hx - 0.01), 0.6, 0.0), Vector3(0.02, 1.2, hz * 2.0), _mats["wall_low"])
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5 + 0.6, hz - 0.01), Vector3(side_w, HEIGHT - 1.2, 0.02), _mats["wall_in"])
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), 0.6, hz - 0.01), Vector3(side_w, 1.2, 0.02), _mats["wall_low"])
		# Hazard-yellow door posts.
		_deco(self, c + Vector3(side * (DOOR_HALF + 0.08), DOOR_HEIGHT * 0.5, hz + 0.02), Vector3(0.16, DOOR_HEIGHT, t + 0.08), _mats["yellow"])
	# Roof with steel trusses.
	_solid(c + Vector3(0.0, HEIGHT + 0.15, 0.0), Vector3(hx * 2.0 + 1.0, 0.3, hz * 2.0 + 1.0), _mats["roof"])
	for i in 5:
		var z := -hz + 0.8 + i * (hz * 2.0 - 1.6) / 4.0
		_deco(self, c + Vector3(0.0, HEIGHT - 0.2, z), Vector3(hx * 2.0, 0.18, 0.1), _mats["steel"])
	# The roller door, rolled up into its drum above the opening.
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = DOOR_HALF * 2.0 + 0.3
	drum.mesh = cyl
	drum.material_override = _mats["cladding"]
	drum.position = c + Vector3(0.0, DOOR_HEIGHT + 0.34, hz - 0.38)
	drum.rotation.z = PI * 0.5
	add_child(drum)
	_deco(self, c + Vector3(0.0, DOOR_HEIGHT + 0.02, hz - 0.08), Vector3(DOOR_HALF * 2.0, 0.08, 0.1), _mats["dark"])
	# Sign over the door.
	var sign := Label3D.new()
	sign.text = "TORQUE SHED"
	sign.font_size = 110
	sign.outline_size = 18
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.position = c + Vector3(0.0, DOOR_HEIGHT + 0.6, hz + t + 0.05)
	sign.pixel_size = 0.008
	add_child(sign)
	# Painted bay boxes and a walkway line.
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		for side in [-1.0, 1.0]:
			_deco(self, xf.origin + Vector3(side * 1.5, 0.01, 0.4), Vector3(0.06, 0.004, 3.1), _mats["yellow"])
		_label("BAY %d" % (bay + 1), xf.origin + Vector3(0.0, 0.012, 1.75), 0.0, 72, Color(0.95, 0.8, 0.2)).rotation.x = -PI * 0.5
	_deco(self, c + Vector3(0.0, 0.01, -1.4), Vector3(hx * 2.0 - 3.0, 0.004, 0.06), _mats["yellow"])


func _build_bays() -> void:
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		var screen := Dashboard.new("bike", 2.6)
		screen.position = Vector3(xf.origin.x, 2.45, CENTER.z - HALF.y + 0.1)
		add_child(screen)
		_bay_screens.append(screen)


func _build_bench() -> void:
	var x := CENTER.x - HALF.x + 0.5
	var z_from := spot_transform("bench_0").origin.z - 0.6
	var z_to := spot_transform("bench_3").origin.z + 0.6
	var mid := (z_from + z_to) * 0.5
	var length := z_to - z_from
	_solid(Vector3(x, 0.45, mid), Vector3(0.9, 0.9, length), _mats["steel"])
	_deco(self, Vector3(x, 0.92, mid), Vector3(0.95, 0.06, length + 0.05), _mats["wood"])
	for i in 3:
		_deco(self, Vector3(x + 0.46, 0.25 + i * 0.25, mid), Vector3(0.02, 0.2, length - 0.2), _mats["red"])
	for i in 4:
		var spot := "bench_%d" % i
		var xf := spot_transform(spot)
		_target(xf.origin + Vector3(0.0, 0.25, 0.0), Vector3(0.95, 0.5, 1.15), {"spot": spot})
	_poster("WORKBENCH", Vector3(CENTER.x - HALF.x + 0.012, 1.32, spot_transform("bench_3").origin.z + 0.2), PI * 0.5)


## The parts computer, Car Dealer Simulator style: order anything, it arrives on a pallet.
func _build_computer() -> void:
	var pos := CENTER + Vector3(HALF.x - 0.45, 0.0, 1.9)
	_solid(pos + Vector3(0.0, 0.37, 0.0), Vector3(0.75, 0.74, 1.3), _mats["wood"])
	_deco(self, pos + Vector3(0.0, 0.76, 0.0), Vector3(0.8, 0.04, 1.35), _mats["dark"])
	var monitor := _deco(self, pos + Vector3(0.12, 1.1, 0.0), Vector3(0.05, 0.42, 0.68), _mats["dark"])
	monitor.name = "Monitor"
	var screen_mat := _material(Color(0.1, 0.3, 0.5), 0.0, 0.3)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.25, 0.6, 1.0)
	screen_mat.emission_energy_multiplier = 1.4
	_deco(self, pos + Vector3(0.09, 1.1, 0.0), Vector3(0.01, 0.36, 0.62), screen_mat)
	_deco(self, pos + Vector3(0.16, 0.86, 0.0), Vector3(0.06, 0.18, 0.06), _mats["dark"])
	_deco(self, pos + Vector3(-0.15, 0.79, 0.0), Vector3(0.18, 0.02, 0.45), _mats["dark"])  # keyboard
	var title := _label("PARTS", pos + Vector3(0.08, 1.22, 0.0), -PI * 0.5, 40, Color(0.7, 0.9, 1.0))
	title.outline_size = 0
	_label("Order anything", pos + Vector3(0.08, 1.08, 0.0), -PI * 0.5, 20, Color(0.7, 0.9, 1.0)).outline_size = 0
	_target(pos + Vector3(0.0, 1.0, 0.0), Vector3(0.8, 0.6, 1.3), {"pc": true})


## Deliveries are left outside, to the side of the roller door: a painted bay on the yard.
func _build_delivery_area() -> void:
	var paint := _material(Color(0.85, 0.7, 0.2), 0.0, 0.8)
	var c := CENTER + Vector3(3.2 + 1.5 * 0.85, 0.0, HALF.y + 1.3 + 0.9)
	var w := 4.0 * 0.85 + 0.4
	var d := 3.0 * 0.9 + 0.4
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * w * 0.5, 0.005, 0.0), Vector3(0.08, 0.01, d), paint)
		_deco(self, c + Vector3(0.0, 0.005, side * d * 0.5), Vector3(w, 0.01, 0.08), paint)
	var mark := _label("DELIVERIES", c + Vector3(0.0, 0.012, d * 0.5 + 0.35), 0.0, 48, Color(0.85, 0.7, 0.2, 0.8))
	mark.rotation = Vector3(-PI * 0.5, PI, 0.0)
	mark.outline_size = 0


func _build_washer() -> void:
	var xf := spot_transform("washer")
	var base := xf.origin - Vector3(0.0, 0.86, 0.0)
	_solid(base + Vector3(0.0, 0.4, 0.0), Vector3(1.3, 0.8, 0.9), _mats["blue"])
	_deco(self, base + Vector3(0.0, 0.82, 0.0), Vector3(1.2, 0.04, 0.8), _mats["steel"])
	_deco(self, base + Vector3(0.0, 1.35, 0.42), Vector3(1.3, 1.1, 0.06), _mats["blue"])
	var tap := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.02
	tube.bottom_radius = 0.02
	tube.height = 0.5
	tap.mesh = tube
	tap.material_override = _mats["chrome"]
	tap.position = base + Vector3(0.3, 1.15, 0.3)
	tap.rotation.x = -0.6
	add_child(tap)
	_target(xf.origin + Vector3(0.0, 0.2, 0.0), Vector3(1.3, 0.6, 0.9), {"spot": "washer"})
	_poster("PARTS WASHER", base + Vector3(0.0, 1.6, 0.385), PI)
	_washer_sound = Sfx.make_loop_player(self)
	_washer_sound.position = base + Vector3(0.0, 0.8, 0.0)
	_washer_sound.volume_db = -8.0


func _build_repair_bench() -> void:
	var xf := spot_transform("repair")
	var base := xf.origin - Vector3(0.0, 0.96, 0.0)
	_solid(base + Vector3(0.0, 0.45, 0.0), Vector3(1.8, 0.9, 0.9), _mats["steel"])
	_deco(self, base + Vector3(0.0, 0.92, 0.0), Vector3(1.85, 0.06, 0.95), _mats["dark"])
	# Vice and bench grinder.
	_deco(self, base + Vector3(-0.7, 1.03, 0.2), Vector3(0.2, 0.16, 0.3), _mats["blue"])
	_deco(self, base + Vector3(0.7, 1.05, 0.0), Vector3(0.3, 0.2, 0.2), _mats["dark"])
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var w := CylinderMesh.new()
		w.top_radius = 0.09
		w.bottom_radius = 0.09
		w.height = 0.03
		wheel.mesh = w
		wheel.material_override = _mats["steel"]
		wheel.position = base + Vector3(0.7 + side * 0.18, 1.07, 0.0)
		wheel.rotation.z = PI * 0.5
		add_child(wheel)
	_target(xf.origin + Vector3(0.0, 0.25, 0.0), Vector3(1.8, 0.5, 0.9), {"spot": "repair"})
	_poster("REPAIR BENCH", Vector3(base.x, 1.4, CENTER.z + HALF.y - 0.012), PI)


func _build_bin() -> void:
	var pos := CENTER + Vector3(-2.9, 0.0, HALF.y - 0.6)
	_solid(pos + Vector3(0.0, 0.45, 0.0), Vector3(0.9, 0.9, 0.8), _mats["dark"])
	_deco(self, pos + Vector3(0.0, 0.91, 0.0), Vector3(0.8, 0.02, 0.7), _material(Color(0.12, 0.1, 0.08), 0.4, 0.8))
	_target(pos + Vector3(0.0, 0.75, 0.0), Vector3(1.0, 0.7, 0.9), {"bin": true})
	_poster("SCRAP", Vector3(pos.x, 1.3, CENTER.z + HALF.y - 0.012), PI, Vector2(0.36, 0.2))


## A pegboard of hand tools above the engine stand.
func _build_tool_wall() -> void:
	var x := CENTER.x + HALF.x - 0.04
	var z0 := CENTER.z - 1.8
	_deco(self, Vector3(x, 2.2, z0 + 1.4), Vector3(0.03, 1.2, 2.8), _material(Color(0.55, 0.42, 0.28), 0.0, 0.8, _noise(1.5, 0.75, 1.0), 6.0))
	var steel: Material = _mats["chrome"]
	for i in 10:
		var len := 0.22 + (i % 4) * 0.06
		var tool := _deco(self, Vector3(x - 0.04, 2.45 - len * 0.5, z0 + 0.3 + i * 0.25), Vector3(0.015, len, 0.035), steel)
		tool.rotation.x = 0.08 * (i % 3 - 1)
		_deco(self, Vector3(x - 0.04, 2.47, z0 + 0.3 + i * 0.25), Vector3(0.02, 0.05, 0.07), steel)
	for i in 5:
		var handle := _deco(self, Vector3(x - 0.05, 1.9, z0 + 0.4 + i * 0.5), Vector3(0.05, 0.3, 0.05), _mats["red"] if i % 2 else _mats["yellow"])
		handle.rotation.x = 0.1
		_deco(self, Vector3(x - 0.05, 1.7, z0 + 0.4 + i * 0.5), Vector3(0.025, 0.12, 0.025), steel)


## A wall shelf over the back end of the workbench with the shed radio on it.
func _build_radio() -> void:
	var x := CENTER.x - HALF.x
	var z := spot_transform("bench_0").origin.z - 0.25
	_deco(self, Vector3(x + 0.17, 1.6, z), Vector3(0.34, 0.03, 0.6), _mats["wood"])
	for dz in [-0.22, 0.22]:
		_deco(self, Vector3(x + 0.04, 1.52, z + dz), Vector3(0.03, 0.14, 0.03), _mats["steel"])
	radio = ShedRadio.new()
	radio.position = Vector3(x + 0.19, 1.615, z)
	radio.rotation.y = PI * 0.5
	add_child(radio)


## A lean-to wash bay on the west side of the shed, open to the yard: a concrete pad with a
## drain, a pressure washer on the back wall and a strip light. Ride or wheel a muddy bike in
## and blast it clean with the pressure washer (tool 6).
func _build_wash_bay() -> void:
	var c := WASH_CENTER
	var hx := WASH_HALF.x
	var hz := WASH_HALF.y
	var h := 3.0
	var pad := _material(Color(0.42, 0.44, 0.45), 0.0, 0.25, _noise(0.3, 0.85, 1.05), 4.0)
	var floor_mi := _deco(self, c + Vector3(0.0, 0.006, 0.0), Vector3(hx * 2.0, 0.012, hz * 2.0), pad)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_deco(self, c + Vector3(0.0, 0.014, 0.6), Vector3(1.6, 0.006, 0.2), _mats["dark"]).name = "Drain"
	# Back and outer walls (the shed wall is the inner side); open to the yard at the front.
	_solid(c + Vector3(0.0, h * 0.5, -hz - 0.1), Vector3(hx * 2.0 + 0.2, h, 0.2), _mats["cladding"])
	_solid(c + Vector3(-hx - 0.1, h * 0.5, 0.0), Vector3(0.2, h, hz * 2.0 + 0.2), _mats["cladding"])
	var tiles := _material(Color(0.82, 0.86, 0.88), 0.0, 0.2)
	_deco(self, c + Vector3(0.0, 1.0, -hz + 0.005), Vector3(hx * 2.0, 2.0, 0.01), tiles)
	_deco(self, c + Vector3(-hx + 0.005, 1.0, 0.0), Vector3(0.01, 2.0, hz * 2.0), tiles)
	_solid(c + Vector3(0.0, h + 0.08, 0.0), Vector3(hx * 2.0 + 0.4, 0.12, hz * 2.0 + 0.4), _mats["roof"])
	_deco(self, c + Vector3(-hx + 0.1, h * 0.5, hz - 0.1), Vector3(0.12, h, 0.12), _mats["yellow"])
	_deco(self, c + Vector3(0.0, h - 0.1, hz - 0.05), Vector3(hx * 2.0, 0.2, 0.1), _mats["yellow"])
	var sign := _label("WASH BAY", c + Vector3(0.0, h - 0.1, hz + 0.02), 0.0, 64, Color(0.08, 0.08, 0.08))
	sign.outline_size = 0
	# The pressure washer: a yellow trolley unit with a hose reel, against the back wall.
	var unit := WASH_POS
	_solid(unit + Vector3(0.0, 0.45, 0.0), Vector3(0.5, 0.9, 0.4), _mats["yellow"])
	_deco(self, unit + Vector3(0.0, 0.92, 0.0), Vector3(0.52, 0.04, 0.42), _mats["dark"])
	var reel := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = 0.22
	drum.bottom_radius = 0.22
	drum.height = 0.12
	reel.mesh = drum
	reel.material_override = _mats["dark"]
	reel.position = unit + Vector3(0.45, 1.4, -0.1)
	reel.rotation.x = PI * 0.5
	add_child(reel)
	_poster("PRESSURE WASHER: TOOL 6", unit + Vector3(-0.1, 1.75, -0.19), 0.0, Vector2(0.9, 0.2))
	var lamp := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.95, 0.85)
	lamp.emission_energy_multiplier = 3.0
	_deco(self, c + Vector3(0.0, h - 0.06, 0.0), Vector3(0.15, 0.04, 1.6), lamp)
	var light := OmniLight3D.new()
	light.position = c + Vector3(0.0, h - 0.4, 0.0)
	light.omni_range = 5.5
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.95, 0.88)
	add_child(light)


func _build_lights() -> void:
	var fixture := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		_deco(self, Vector3(xf.origin.x, HEIGHT - 0.35, xf.origin.z), Vector3(0.2, 0.05, 1.3), fixture)
		var spot := SpotLight3D.new()
		spot.position = Vector3(xf.origin.x, HEIGHT - 0.45, xf.origin.z + 0.4)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 50.0
		spot.spot_range = 6.5
		spot.light_energy = 2.6
		spot.light_color = Color(1.0, 0.95, 0.88)
		spot.shadow_enabled = true
		add_child(spot)
	for p in [Vector3(-4.2, 0.0, 1.5), Vector3(4.2, 0.0, 1.5), Vector3(0.0, 0.0, 3.5)]:
		_deco(self, CENTER + p + Vector3(0.0, HEIGHT - 0.35, 0.0), Vector3(0.2, 0.05, 1.3), fixture)
		var omni := OmniLight3D.new()
		omni.position = CENTER + p + Vector3(0.0, HEIGHT - 0.6, 0.0)
		omni.omni_range = 7.0
		omni.light_energy = 1.2
		omni.light_color = Color(1.0, 0.93, 0.82)
		omni.shadow_enabled = p.x == 0.0
		add_child(omni)
	# Indoors the sky shouldn't light everything blue: a probe gives the shed warm ambient light.
	var probe := ReflectionProbe.new()
	probe.position = CENTER + Vector3(0.0, HEIGHT * 0.5, 0.0)
	probe.size = Vector3(HALF.x * 2.0 + 0.2, HEIGHT, HALF.y * 2.0 + 0.2)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.55, 0.5, 0.45)
	probe.ambient_color_energy = 0.45
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
