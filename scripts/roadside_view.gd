class_name RoadsideView
extends Node3D
## The bikes left at the side of the road on an adventure, for everyone: each up on its stand
## where its rider got off (kept in the route's frame, see Roadside, so the floating origin
## never moves it), with click targets on its parts for the walker; with its toolbox open the
## kit is laid out on a cloth beside it, and the parts worked on show out there too. And the tow straps between bikes on a tow.
## A child of the AdventureWorld, so it goes when the adventure does.

var world: AdventureWorld
var _views := {}     # bike id -> {node, sig}
var _straps := {}    # towed bike id -> MeshInstance3D
var _strap_mesh: BoxMesh
var _cloth_mat: StandardMaterial3D
var _kit_mat: StandardMaterial3D
var _box_mat: StandardMaterial3D
var _chain_mat: StandardMaterial3D


func _ready() -> void:
	name = "RoadsideView"
	if world == null:
		world = get_parent() as AdventureWorld
	_cloth_mat = _mat(Color(0.12, 0.2, 0.45), 0.0, 0.95)
	_kit_mat = _mat(Color(0.75, 0.12, 0.1), 0.1, 0.6)
	_box_mat = _mat(Color(0.18, 0.18, 0.2), 0.4, 0.5)
	_chain_mat = _mat(Color(0.45, 0.45, 0.47), 0.9, 0.35)
	_strap_mesh = BoxMesh.new()
	_strap_mesh.size = Vector3(0.05, 0.012, 1.0)
	_strap_mesh.material = _mat(Color(0.95, 0.55, 0.05), 0.0, 0.8)
	Shed.changed.connect(sync)
	sync()


static func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Brings the parked bikes into line with the shed: new ones drawn, gone ones freed, any whose
## parts, stand, toolbox or laid-out kit changed drawn again.
func sync() -> void:
	if not is_inside_tree() or world == null:
		return
	for id in _views.keys():
		if not Roadside.parked(int(id)):
			(_views[id]["node"] as Node).queue_free()
			_views.erase(id)
	for id in Shed.bikes:
		if not Roadside.parked(int(id)):
			continue
		var r := Roadside.spot_of(int(id))
		var sig := "%s|%s|%s|%s|%s|%d" % [str(Shed.fitted_map(int(id))), str(Shed.bikes[id].get("stand", "")), str(r.get("open", false)),
			str(r.get("out", [])), str(Shed.bikes[id].get("paint", "")), ToolboxSpares.spares_of(Roadside.toolbox_of(int(id))).size()]
		if _views.has(id) and _views[id]["sig"] == sig:
			continue
		if _views.has(id):
			(_views[id]["node"] as Node).free()
		var node := _make_view(int(id), r)
		add_child(node)
		_views[id] = {"node": node, "sig": sig}
	_place()


func _process(_delta: float) -> void:
	var pt := Perf.t0()
	_place()
	_update_straps()
	Perf.add("roadside_view", pt)


## Every parked bike where its record says, in the local frame as it is now.
func _place() -> void:
	for id in _views:
		var r := Roadside.spot_of(int(id))
		if not r.is_empty():
			(_views[id]["node"] as Node3D).global_transform = Roadside.xf_in(world, r)


## The bike stood on its stand, its pickers, and the cloth with what's laid out on it.
func _make_view(id: int, r: Dictionary) -> Node3D:
	var bike: Dictionary = Shed.bikes[id]
	var view := Node3D.new()
	view.name = "Roadside%d" % id
	var build := Shed.build_of(id)
	var lean := Node3D.new()
	view.add_child(lean)
	var model := BikeModel.new()
	lean.add_child(model)
	var stand := str(bike.get("stand", ""))
	var lift := 0.0
	if stand == "centre":
		lift = build.centre_lift
	elif stand == "side":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(build.parts["side_stand"]).get("lean", 12.0))))
	elif stand == "down":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(74.0))
		lift = 0.12
	model.position.y = build.rear_radius + lift
	model.stand_pose = stand
	model.geometry = Shed.geometry_of(id)
	model.build_from(build, bike["paint"], Shed.fitted_map(id), build.condition, false)
	model.build_pickers({"bike": id})
	model.show_dirt(Dirt.of_bike(id))
	var out: Array = r.get("out", [])
	if r.get("open", false) or not out.is_empty():
		_lay_out(view, id, r)
	return view


## The cloth on the ground on the bike's right (away from the side stand) and what's on it.
func _lay_out(view: Node3D, id: int, r: Dictionary) -> void:
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.9, 0.01, 1.3)
	cm.material = _cloth_mat
	cloth.mesh = cm
	cloth.position = Vector3(0.85, 0.005, 0.0)
	view.add_child(cloth)
	var at := Vector3(0.85, 0.01, -0.45)
	var kit := Roadside.kit_of(id)
	if r.get("open", false):
		# The toolbox's lid up, beside it on the cloth: what's still in it, laid out.
		for what in kit:
			var piece := _kit_piece(str(what))
			piece.position = at
			view.add_child(piece)
			at += Vector3(0.0, 0.0, 0.22)
			if at.z > 0.55:
				at = Vector3(1.15, 0.01, -0.45)
		# And the spare parts packed in it (see ToolboxSpares), each in its own little bag.
		for i in ToolboxSpares.spares_of(Roadside.toolbox_of(id)).size():
			var bag := _box(Vector3(0.12, 0.05, 0.09), _box_mat)
			bag.position = Vector3(1.2, 0.035, -0.45 + 0.16 * float(i))
			view.add_child(bag)
	for what in r.get("out", []):
		var piece := _out_piece(str(what))
		if piece == null:
			continue
		piece.position = Vector3(0.55, 0.01, 0.35 - 0.3 * float((r.get("out", []) as Array).find(what)))
		view.add_child(piece)


## One thing from the toolbox, as it lies on the cloth.
func _kit_piece(what: String) -> Node3D:
	match what:
		"tools":
			var roll := _box(Vector3(0.32, 0.03, 0.16), _kit_mat)
			var spanner := Walker.make_tool_mesh("wrench")
			spanner.rotation = Vector3(-PI * 0.5, 0.4, 0.0)
			spanner.scale = Vector3.ONE * 0.8
			spanner.position = Vector3(0.05, 0.03, 0.0)
			roll.add_child(spanner)
			return roll
		"oil", "brake_fluid", "chain_lube":
			var bottle := _cylinder(0.045, 0.2, _mat({"oil": Color(0.85, 0.65, 0.1), "brake_fluid": Color(0.9, 0.9, 0.85),
				"chain_lube": Color(0.2, 0.3, 0.75)}[what], 0.2, 0.4))
			bottle.position.y = 0.1
			var n := Node3D.new()
			n.add_child(bottle)
			return n
	# Anything else (packed in an older save): a small box.
	return _box(Vector3(0.14, 0.04, 0.1), _mat(Color(0.5, 0.5, 0.5), 0.2, 0.5))


## What's been taken off or used, on the cloth: the tool roll, a part off the bike.
func _out_piece(what: String) -> Node3D:
	match what:
		"chain":
			return _coil()
		"tools":
			return _kit_piece("tools")
	return null


func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	mi.mesh = b
	mi.position.y = size.y * 0.5
	return mi


func _cylinder(r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.material = m
	mi.mesh = c
	return mi


## A coiled chain lying flat.
func _coil() -> Node3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.1
	t.outer_radius = 0.13
	t.material = _chain_mat
	mi.mesh = t
	mi.position.y = 0.015
	mi.scale = Vector3(1.0, 0.35, 1.0)
	return mi


# ---------------------------------------------------------------------------- tow straps

## Where a ridden bike is right now in this game: yours, or the one a remote player rides.
func _ridden_node(bike_id: int) -> Node3D:
	var trip := AdventureTrip.current
	if trip == null or trip.main == null:
		return null
	if trip.main.bike != null and int(trip.main.riding_id) == bike_id:
		return trip.main.bike
	for peer in trip.main.remotes:
		var rp = trip.main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null and int(rp.riding_bike) == bike_id:
			return rp.bike
	return null


## A strap from each towing bike's back to the towed bike's front.
func _update_straps() -> void:
	var live := {}
	for id in Shed.bikes:
		var by := int(Shed.bikes[id].get("tow", 0))
		if by == 0:
			continue
		var towed := _ridden_node(int(id))
		var tower := _ridden_node(Shed.riding(by))
		if towed == null or tower == null:
			continue
		live[id] = true
		var a := tower.global_transform * Vector3(0.0, 0.45, 1.0)
		var b := towed.global_transform * Vector3(0.0, 0.6, -0.9)
		var strap: MeshInstance3D = _straps.get(id)
		if strap == null:
			strap = MeshInstance3D.new()
			strap.mesh = _strap_mesh
			add_child(strap)
			_straps[id] = strap
		var len := maxf(a.distance_to(b), 0.05)
		var mid := (a + b) * 0.5 + Vector3.DOWN * clampf(Roadside.STRAP - len, 0.0, 1.5) * 0.3   # it sags when slack
		strap.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, len)), mid)
	for id in _straps.keys():
		if not live.has(id):
			(_straps[id] as Node).queue_free()
			_straps.erase(id)


## The strap's ends for a tow (for the tests): [tower end, towed end], or [].
func strap_of(bike_id: int) -> Array:
	var s: MeshInstance3D = _straps.get(bike_id)
	return [] if s == null else [s.global_position]
