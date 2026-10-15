class_name BikeModel
extends Node3D
## The visible bike and rider, built from primitive meshes to match the chosen parts.
## Every mesh belongs to one part slot, so a bike in the shed can show missing parts,
## rust and grime per part, highlight the part a player is looking at, and give each
## part its own click target. Shared by ridden, parked and other players' bikes.

const PICK_LAYER := 4
const SPRAY_LAYER := 16   # fitted shapes on loose parts, only for the spray to land on

static var _rust_masks := {}     # rust level (1..10) -> NoiseTexture2D mask
static var _rust_albedo: NoiseTexture2D
static var _patina_albedo: NoiseTexture2D
static var _part_sizes := {}      # part id -> bounding size, for sizing delivery boxes
static var _cardboard: StandardMaterial3D
static var _highlight_mat: StandardMaterial3D

var paint := Color(0.78, 0.09, 0.08)
var jacket := Color(0.1, 0.12, 0.16)
var rider_color := Color(0, 0, 0, 0)   # the rider's own colour; clear means dress to match the bike
## The rider's gear, slot -> RiderGear item id (see RiderFigure). With it or a rider colour the
## rider wears that gear (the free defaults where it's empty); with neither they match the bike.
var rider_gear := {}
var present := {}                # slot -> bool; missing slots are not drawn
var condition := {}              # slot -> {rust, dirt, wear, color, finish}
var stand_pose := ""             # "side" or "centre" draws that stand down on the ground; set before build_from
## The rider's helmet is on its own render layer so the first-person camera can leave it out.
const HELMET_LAYER := 2

var _build: BikeBuild
var _slot_meshes := {}           # slot -> Array of GeometryInstance3D
var _current_slot := "frame"
var _steer_node: Node3D
var _front_hub: Node3D
var _front_wheel: Node3D
var _rear_hub: Node3D
var _rear_wheel: Node3D
var _swingarm: Node3D
var _rider: Node3D
var _steer_axis := Vector3.UP
var _head := Vector3.ZERO
var _head_bottom := Vector3.ZERO
var _pivot := Vector3.ZERO
var _seat_y := 0.5
var _seat_front := Vector3.ZERO
var _tail := Vector3.ZERO
var _engine_c := Vector3.ZERO
var _block_w := 0.3
var _bore_r := 0.048             # cylinder barrel radius
var _eng_s := 1.0                # engine size relative to a 700 cc
var _cyls := []                  # {base, up} per cylinder barrel
var _arm_len := 0.6
var _struts: Array = []     # rear shocks: [{mi, top (model space), bottom (on the swingarm), rest}]
var _grip_l := Vector3(-0.31, 0.12, 0.06)   # handlebar grips, in steering space
var _grip_r := Vector3(0.31, 0.12, 0.06)
var _highlighted := ""
var _exhaust_tip := Vector3.ZERO
var _eye := Vector3.ZERO
var _grime: StandardMaterial3D
var _dash_label: Label3D
var _needles := []               # {node, what: "speed" or "rpm"} on dial clocks
var _leds := []                  # shift lights: {mat, color}
var _dash_screen := Transform3D()  # where the readout text sits on the clocks, in steering space
var _lamps: Array = []           # lit lenses and clocks: {mat, albedo, energy, group ("ign" or "head")}
var _lit := [true, true]         # [ignition, headlight] as last set
## This bike's own fit for each part, set in geometry mode: slot -> {p, r, s} (see GeoGizmo),
## about the part's middle in the model's axes. Set it before build_from, or change it any time
## with apply_geometry. Looks only: the physics never see it.
var geometry := {}
var _geo_nodes := {}             # slot -> [{node, parent, anchor}]: a node per slot per parent its meshes hang from
var _geo_pivots := {}            # slot -> the part's middle at rest, in model space
var _geo_anchors := {}           # node -> its rest transform in model space, for the nodes offsets ride on


## Builds the model. `fitted` maps slot -> bool (all fitted when empty); `part_condition`
## maps slot -> {rust, dirt, wear, color} and defaults to the build's own condition.
func build_from(build: BikeBuild, paint_color := paint, fitted := {}, part_condition = null, with_rider := true) -> void:
	_build = build
	paint = paint_color
	jacket = paint.darkened(0.45)
	present = fitted
	condition = build.condition if part_condition == null else part_condition
	_slot_meshes.clear()
	_lamps.clear()
	_lit = [true, true]
	_highlighted = ""
	for slot in PartsDB.SLOTS:
		_slot_meshes[slot] = []
	for child in get_children():
		child.free()
	_rider = null
	_geo_nodes.clear()
	_geo_pivots.clear()
	_geo_anchors.clear()

	var wb := build.wheelbase
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var rake := deg_to_rad(build.rake_deg)
	_steer_axis = Vector3(0.0, cos(rake), sin(rake))
	_head = Vector3(0.0, 0.0, zf) + _steer_axis * build.fork_length
	_head_bottom = _head - _steer_axis * 0.16
	_seat_y = build.seat_height - build.rear_radius
	_pivot = Vector3(0.0, 0.16, zr - 0.6)
	# The seat starts over the swingarm pivot, leaving the tank its own space behind the bars.
	_seat_front = Vector3(0.0, _seat_y - 0.1, _pivot.z + 0.02)
	_tail = Vector3(0.0, build.seat_height - build.rear_radius - 0.02, zr - 0.12)
	_engine_c = Vector3(0.0, 0.1, lerpf(_head_bottom.z, _pivot.z, 0.48))
	_layout_cylinders(build)

	_draw_frame(build, zr)
	_draw_tank()
	_draw_saddle()
	_draw_engine()
	_draw_head()
	_draw_spark_plugs()
	_draw_fuel()
	_draw_air_filter()
	_draw_oil_filter()
	_draw_cooling()
	_draw_gearbox()
	_draw_exhaust(zr)

	_steer_node = Node3D.new()
	_steer_node.position = _head
	add_child(_steer_node)
	_front_hub = Node3D.new()
	_steer_node.add_child(_front_hub)
	_draw_fork(build)
	_draw_handlebars()
	_draw_dashboard()
	_draw_front_master()
	_draw_headlight()

	_front_wheel = Node3D.new()
	_front_hub.add_child(_front_wheel)
	_rear_hub = Node3D.new()
	add_child(_rear_hub)
	_rear_wheel = Node3D.new()
	_rear_hub.add_child(_rear_wheel)
	for side in ["front", "rear"]:
		var front: bool = side == "front"
		var wheel := _front_wheel if front else _rear_wheel
		var hub := _front_hub if front else _rear_hub
		var rim_r := build.front_rim_radius if front else build.rear_rim_radius
		var width := build.front_tyre_width if front else build.rear_tyre_width
		_current_slot = side + "_wheel"
		var rim_w := rim_width_of(_part())
		_draw_rim(wheel, rim_r, rim_w)
		_current_slot = side + "_tyre"
		_draw_tyre(wheel, rim_r, build.front_radius if front else build.rear_radius, width, rim_w)
		_draw_brake(side, wheel, hub, rim_r, rim_w)
	_draw_rear_master()
	_draw_final_drive(zr)
	_draw_shock()
	_draw_side_stand(build)
	_draw_centre_stand(build)
	_draw_horn()
	_draw_ecu()
	_draw_panniers(build, zr)
	_draw_top_box()
	_draw_fog_lights()
	_draw_tail(build)
	_draw_fairing()
	_draw_mirrors()
	_draw_front_mudguard(build)

	_apply_visibility()
	_current_slot = ""
	if with_rider:
		_build_rider()
	update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	set_gauges(0.0, 0.0)
	# Parked, every lamp and the clocks are dark until the engine runs (see set_lights).
	set_lights(false, false)
	if not geometry.is_empty():
		apply_geometry(geometry)


## Where each cylinder's barrel sits and which way it points, for the engine layout. Barrels
## are sized from the bore, so a 50 cc twin looks tiny next to a 1200.
func _layout_cylinders(build: BikeBuild) -> void:
	_cyls.clear()
	var cyl := build.cylinders
	var block := PartsDB.get_part(str(build.parts.get("engine", "")))
	_bore_r = clampf(float(block.get("bore", 80.0)) * 0.0006, 0.022, 0.062)
	_eng_s = clampf(pow(build.displacement / 700.0, 0.3), 0.55, 1.2)
	var s := _eng_s
	match build.layout:
		"vtwin":
			_block_w = 0.22 * s
			for dir in [-1.0, 1.0]:
				var up := Vector3(0.0, cos(0.6), 0.6 * dir).normalized()
				_cyls.append({"base": _engine_c + Vector3(0.0, 0.13 * s, 0.07 * dir * s) + up * 0.12 * s, "up": up})
			return
		"boxer":
			# Flat twin: the barrels stick straight out either side, ahead of the rider's knees.
			_block_w = 0.24 * s
			for dir in [-1.0, 1.0]:
				var up := Vector3(dir, 0.08, -0.05).normalized()
				_cyls.append({"base": _engine_c + Vector3(0.1 * dir * s, 0.03, -0.06) + up * 0.1 * s, "up": up})
			return
	_block_w = (0.2 + 0.11 * (cyl - 1)) * s
	# A classic twin stands upright; two-strokes lean right forward; the rest lean a little.
	var lean := {"twin": 0.04, "2stroke": 0.4}.get(build.layout, 0.25) as float
	var up := Vector3(0.0, 1.0, -lean).normalized()
	for c in cyl:
		var cx := (c - (cyl - 1) * 0.5) * maxf(0.12 * s, _bore_r * 2.4)
		_cyls.append({"base": _engine_c + Vector3(cx, 0.14 * s, -0.04) + up * 0.1 * s, "up": up})


func _part_id() -> String:
	return str(_build.parts.get(_current_slot, ""))


func _part() -> Dictionary:
	return PartsDB.get_part(_part_id())


## The colour of the part being drawn: its own paint, or the catalogue colour.
func _col() -> Color:
	var cond: Dictionary = condition.get(_current_slot, {})
	if cond.has("color"):
		return cond["color"]
	return PartsDB.default_color(_part_id())


# ---------------------------------------------------------------------------- chassis

func _draw_frame(build: BikeBuild, zr: float) -> void:
	_current_slot = "frame"
	var style := str(_part().get("style", "cradle"))
	var carbon := _part_id() == "carbon_monocoque"
	var frame_mat := _mat(_col(), 0.2 if carbon else 0.7, 0.25 if carbon else 0.35, 0.8 if carbon else 0.0)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.7)
	var hb := _head_bottom
	match style:
		"spar":
			var thick := 1.6 if carbon else 1.0
			for side in [-1.0, 1.0]:
				_tube(hb + Vector3(0.09 * side, 0.05, 0.0), _pivot + Vector3(0.12 * side, 0.1, 0.0), 0.045, frame_mat, Vector3(thick, 1.0, 2.2))
				_tube(_pivot + Vector3(0.12 * side, 0.1, 0.0), _pivot + Vector3(0.12 * side, -0.12, 0.02), 0.04, frame_mat)
				_tube(_seat_front + Vector3(0.08 * side, 0.0, 0.0), _tail + Vector3(0.06 * side, 0.0, 0.0), 0.016, frame_mat)
				_tube(_pivot + Vector3(0.1 * side, 0.12, 0.0), _tail + Vector3(0.06 * side, -0.02, -0.05), 0.014, frame_mat)
		"trellis":
			for side in [-1.0, 1.0]:
				var top := []
				var bottom := []
				for i in 5:
					var f := i / 4.0
					top.append(hb.lerp(_pivot + Vector3(0.0, 0.18, 0.0), f) + Vector3(0.1 * side, 0.08, 0.0))
					bottom.append(hb.lerp(_pivot, f) + Vector3(0.11 * side, -0.12 * sin(f * PI), 0.0))
				for i in 4:
					_tube(top[i], top[i + 1], 0.012, frame_mat)
					_tube(bottom[i], bottom[i + 1], 0.012, frame_mat)
					_tube(top[i], bottom[i + 1], 0.01, frame_mat)
				_tube(top[4], bottom[4], 0.012, frame_mat)
				_tube(_seat_front + Vector3(0.07 * side, 0.0, 0.0), _tail + Vector3(0.06 * side, 0.0, 0.0), 0.012, frame_mat)
				_tube(top[3], _tail + Vector3(0.06 * side, -0.03, -0.05), 0.01, frame_mat)
		"backbone":
			_tube(_head, _pivot + Vector3(0.0, 0.22, 0.0), 0.045, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.22, 0.0), _pivot, 0.035, frame_mat)
			_tube(_seat_front, _tail, 0.018, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.2, 0.0), _tail + Vector3(0.0, -0.03, -0.05), 0.016, frame_mat)
		_:
			_tube(_head, _seat_front, 0.024, frame_mat)
			_tube(_seat_front, _tail, 0.018, frame_mat)
			_tube(_seat_front, _pivot, 0.02, frame_mat)
			_tube(_pivot, _tail, 0.016, frame_mat)
			var cradle_front := Vector3(0.0, _engine_c.y - 0.2, _engine_c.z - 0.2)
			var cradle_back := Vector3(0.0, _engine_c.y - 0.2, _pivot.z)
			_tube(hb, cradle_front, 0.024, frame_mat)
			_tube(cradle_front, cradle_back, 0.022, frame_mat)
			_tube(cradle_back, _pivot, 0.022, frame_mat)
	_tube(_head - _steer_axis * 0.02, hb, 0.038, frame_mat)
	_box(Vector3(0.0, 0.06, lerpf(_engine_c.z, _pivot.z, 0.6)), Vector3(0.18, 0.14, 0.14), black)  # battery box
	for side in [-1.0, 1.0]:
		_box(Vector3(0.17 * side, 0.02, _pivot.z + 0.02), Vector3(0.1, 0.02, 0.04), black)  # footpegs
	_swingarm = Node3D.new()
	_swingarm.position = _pivot
	add_child(_swingarm)
	_arm_len = Vector3(0.0, 0.0, zr).distance_to(_pivot)
	# The arms clear the back tyre and rim, however fat they are.
	var arm_x := maxf(0.11, maxf(build.rear_tyre_width, rim_width_of(PartsDB.get_part(str(build.parts.get("rear_wheel", ""))))) * 0.5 + 0.035)
	for side in [-1.0, 1.0]:
		_box(Vector3(arm_x * side, 0.0, _arm_len * 0.5), Vector3(0.035, 0.07, _arm_len), frame_mat, _swingarm)
	_box(Vector3(0.0, 0.0, 0.04), Vector3(arm_x * 2.0 + 0.02, 0.07, 0.05), frame_mat, _swingarm)


func _draw_tank() -> void:
	_current_slot = "tank"
	var p := _part()
	var mat := _mat(_col(), 0.25, 0.2, 0.6)
	var size := pow(float(p.get("capacity", 15.0)) / 15.0, 0.33)
	# The tank fills the gap between the bars and the front of the seat, and no further.
	var front := _head.z + 0.13
	var back := _seat_front.z + 0.03
	var root := Node3D.new()
	root.position = Vector3(0.0, lerpf(_head.y, _seat_front.y, 0.5) + 0.06, (front + back) * 0.5)
	root.scale = Vector3(1.0, 1.0, clampf((back - front) / (0.6 * size), 0.55, 1.25))
	add_child(root)
	var c := Vector3.ZERO
	match str(p.get("style", "cafe")):
		"sport":
			var main := _box(c + Vector3(0.0, -0.01, 0.02), Vector3(0.36, 0.2, 0.44) * size, mat, root)
			main.rotation.x = -0.12
			var nose := _box(c + Vector3(0.0, 0.04, -0.2 * size), Vector3(0.3, 0.14, 0.18) * size, mat, root)
			nose.rotation.x = 0.45
		"enduro":
			var t := _mesh_instance(_capsule(0.13, 0.46), mat, c + Vector3(0.0, -0.02, -0.03), root)
			t.rotation = Vector3(PI * 0.5 - 0.3, 0.0, 0.0)
			t.scale = Vector3(1.0, 1.0, 0.7)
			for side in [-1.0, 1.0]:
				var shroud := _box(c + Vector3(0.15 * side, -0.12, -0.12), Vector3(0.03, 0.22, 0.3), mat, root)
				shroud.rotation.x = -0.4
		"peanut":
			var t := _mesh_instance(_capsule(0.11, 0.36), mat, c + Vector3(0.0, 0.02, 0.0), root)
			t.rotation = Vector3(PI * 0.5 - 0.15, 0.0, 0.0)
			t.scale = Vector3(0.85, 1.0, 0.85)
		"touring":
			var t := _mesh_instance(_capsule(0.18, 0.6), mat, c + Vector3(0.0, 0.01, 0.0), root)
			t.rotation = Vector3(PI * 0.5 - 0.1, 0.0, 0.0)
			t.scale = Vector3(1.15, 1.0, 0.8)
		_:
			var t := _mesh_instance(_capsule(0.15 * size, 0.58 * size), mat, c, root)
			t.rotation = Vector3(PI * 0.5 - 0.12, 0.0, 0.0)
			t.scale = Vector3(1.0, 1.0, 0.72)
	_mesh_instance(_cylinder(0.035, 0.02), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15), c + Vector3(0.0, 0.13 * size, -0.03), root)


func _draw_saddle() -> void:
	_current_slot = "saddle"
	var p := _part()
	var mat := _mat(_col(), 0.0, 0.6)
	var y := _seat_y
	var z0 := _seat_front.z
	var z1 := _tail.z
	match str(p.get("style", "bench")):
		"cafe":
			_box(Vector3(0.0, y, lerpf(z0, z1, 0.3)), Vector3(0.24, 0.07, 0.36), mat)
			_box(Vector3(0.0, y + 0.05, lerpf(z0, z1, 0.78)), Vector3(0.22, 0.15, 0.2), mat)
		"enduro":
			var pad := _box(Vector3(0.0, y + 0.01, lerpf(z0, z1, 0.4) - 0.08), Vector3(0.18, 0.09, 0.78), mat)
			pad.rotation.x = 0.06
		"sport":
			_box(Vector3(0.0, y, lerpf(z0, z1, 0.28)), Vector3(0.24, 0.06, 0.3), mat)
			var cowl := _box(Vector3(0.0, y + 0.04, lerpf(z0, z1, 0.75)), Vector3(0.2, 0.12, 0.32), mat)
			cowl.rotation.x = -0.18
		"touring":
			_box(Vector3(0.0, y, lerpf(z0, z1, 0.25)), Vector3(0.34, 0.1, 0.34), mat)
			_box(Vector3(0.0, y + 0.05, lerpf(z0, z1, 0.72)), Vector3(0.32, 0.12, 0.28), mat)
			var back := _box(Vector3(0.0, y + 0.22, z1 + 0.04), Vector3(0.3, 0.26, 0.06), mat)
			back.rotation.x = 0.2
		_:
			_box(Vector3(0.0, y, lerpf(z0, z1, 0.5)), Vector3(0.26, 0.08, z1 - z0 + 0.04), mat)


# ---------------------------------------------------------------------------- engine

func _draw_engine() -> void:
	_current_slot = "engine"
	var mat := _mat(_col(), 0.8, 0.4)
	_box(_engine_c, Vector3(_block_w, 0.26 * _eng_s, 0.34 * _eng_s), mat)
	var fins := _build.layout in ["boxer", "twin", "2stroke"]
	for c in _cyls:
		_tube(c["base"] - c["up"] * 0.1, c["base"] + c["up"] * 0.09, _bore_r, mat)
		if fins:
			# Deep cooling fins round the barrel.
			for k in 4:
				var at: Vector3 = c["base"] + c["up"] * (-0.06 + k * 0.045)
				var fin := _mesh_instance(_cylinder(_bore_r * 1.45, 0.008), mat, at)
				fin.basis = _basis_up(c["up"])
	if _build.layout == "2stroke":
		# Expansion chamber bulge under the engine instead of a sump.
		_box(_engine_c + Vector3(0.0, -0.16 * _eng_s, 0.02), Vector3(_block_w * 0.7, 0.06, 0.24 * _eng_s), mat)


func _draw_head() -> void:
	_current_slot = "head"
	var mat := _mat(_col(), 0.85, 0.3)
	var gasket := _mat(Color(0.15, 0.15, 0.16), 0.5, 0.5)
	var valves := int(_part().get("valves", 4))
	for c in _cyls:
		var top: Vector3 = c["base"] + c["up"] * 0.13
		var h := _box(top, Vector3(0.12, 0.08, 0.15), gasket)
		h.basis = _basis_up(c["up"])
		var cover := _box(top + c["up"] * 0.06, Vector3(0.11, 0.05, 0.14 if valves > 2 else 0.1), mat)
		cover.basis = _basis_up(c["up"])


func _draw_spark_plugs() -> void:
	_current_slot = "spark_plugs"
	var ceramic := _mat(_col(), 0.0, 0.3)
	var cap := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.6)
	for c in _cyls:
		var at: Vector3 = c["base"] + c["up"] * 0.2 + Vector3(0.0, 0.0, 0.02)
		_tube(at, at + c["up"] * 0.05, 0.011, ceramic)
		_tube(at + c["up"] * 0.05, at + c["up"] * 0.08 + Vector3(0.0, 0.0, 0.03), 0.016, cap)


## Where the intake meets each cylinder, and where the fuel system hands over to the air filter.
func _intake_points() -> Array:
	var out := []
	if _build.layout == "vtwin":
		out.append({"port": _engine_c + Vector3(0.0, 0.42, 0.0), "dir": Vector3(0.0, 0.1, 1.0).normalized()})
		return out
	for c in _cyls:
		out.append({"port": c["base"] + c["up"] * 0.12 + Vector3(0.0, 0.0, 0.09), "dir": Vector3(0.0, 0.15, 1.0).normalized()})
	return out


func _draw_fuel() -> void:
	_current_slot = "fuel"
	var p := _part()
	var mat := _mat(_col(), 0.85, 0.3)
	var style := str(p.get("style", "carbs"))
	var points := _intake_points()
	if style == "carb" and points.size() > 1:
		var mid := Vector3.ZERO
		for pt in points:
			mid += pt["port"]
			_tube(pt["port"], pt["port"] + Vector3(0.0, 0.0, 0.05), 0.02, mat)
		mid /= points.size()
		_box(mid + Vector3(0.0, 0.0, 0.08), Vector3(0.07, 0.07, 0.07), mat)
		return
	for pt in points:
		var at: Vector3 = pt["port"]
		_tube(at, at + pt["dir"] * 0.07, 0.026 if style != "fi" else 0.03, mat)
		if style == "fi":
			_box(at + pt["dir"] * 0.04 + Vector3(0.0, 0.04, 0.0), Vector3(0.02, 0.04, 0.02), _mat(Color(0.05, 0.05, 0.05), 0.2, 0.5))
		else:
			_box(at + pt["dir"] * 0.05 + Vector3(0.0, -0.01, 0.0), Vector3(0.055, 0.07, 0.06), mat)


func _draw_air_filter() -> void:
	_current_slot = "air_filter"
	var mat := _mat(_col(), 0.0, 0.8)
	var points := _intake_points()
	match str(_part().get("style", "airbox")):
		"pods":
			for pt in points:
				var pod := _mesh_instance(_cylinder(0.04, 0.09), mat, pt["port"] + pt["dir"] * 0.13)
				pod.basis = _basis_up(pt["dir"])
		"stacks":
			var chrome := _mat(_col(), 1.0, 0.15)
			for pt in points:
				var stack := _mesh_instance(_cylinder(0.026, 0.05, 0.042), chrome, pt["port"] + pt["dir"] * 0.11)
				stack.basis = _basis_up(pt["dir"])
		"cone":
			var mid := Vector3.ZERO
			for pt in points:
				mid += pt["port"]
			mid /= points.size()
			var cone := _mesh_instance(_cylinder(0.065, 0.14, 0.04), mat, mid + Vector3(0.0, 0.02, 0.17))
			cone.rotation.x = PI * 0.5
		_:
			var mid := Vector3.ZERO
			for pt in points:
				mid += pt["port"]
			mid /= points.size()
			_box(mid + Vector3(0.0, 0.04, 0.16), Vector3(maxf(0.2, _block_w * 0.8), 0.15, 0.14), mat)


func _draw_oil_filter() -> void:
	_current_slot = "oil_filter"
	var f := _mesh_instance(_cylinder(0.035, 0.07), _mat(_col(), 0.5, 0.4), _engine_c + Vector3(_block_w * 0.25, -0.06, -0.205))
	f.rotation.x = PI * 0.5


func _draw_cooling() -> void:
	_current_slot = "cooling"
	var mat := _mat(_col(), 0.7, 0.45)
	var core := _mat(Color(0.08, 0.08, 0.08), 0.6, 0.6)
	var front_z := _engine_c.z - 0.3
	match str(_part().get("style", "fins")):
		"fins":
			for c in _cyls:
				for i in 5:
					var fin := _box(c["base"] + c["up"] * (-0.07 + i * 0.035), Vector3(0.14, 0.01, 0.15), mat)
					fin.basis = _basis_up(c["up"])
		"oil":
			_box(Vector3(0.0, _engine_c.y + 0.2, front_z + 0.04), Vector3(0.24, 0.1, 0.035), core)
			_box(Vector3(0.0, _engine_c.y + 0.2, front_z + 0.02), Vector3(0.26, 0.12, 0.01), mat)
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.1 * side, _engine_c.y + 0.15, front_z + 0.04), _engine_c + Vector3(0.08 * side, -0.05, -0.17), 0.007, mat)
		"radiator", "race":
			var big: bool = _part().get("style") == "race"
			var w := 0.42 if big else 0.3
			var rad := _box(Vector3(0.0, _engine_c.y + 0.25, front_z), Vector3(w, 0.34 if big else 0.28, 0.05), core)
			rad.rotation.x = -0.25
			var frame := _box(Vector3(0.0, _engine_c.y + 0.25, front_z - 0.03), Vector3(w + 0.03, 0.04, 0.02), mat)
			frame.rotation.x = -0.25
			_tube(Vector3(0.0, _engine_c.y + 0.12, front_z + 0.03), _engine_c + Vector3(0.0, -0.05, -0.17), 0.015, mat)
		"twin":
			for side in [-1.0, 1.0]:
				var rad := _box(Vector3(0.16 * side, _engine_c.y + 0.24, front_z + 0.08), Vector3(0.05, 0.28, 0.22), core)
				rad.rotation.y = 0.35 * side
				_box(Vector3(0.19 * side, _engine_c.y + 0.24, front_z + 0.08), Vector3(0.01, 0.3, 0.24), mat).rotation.y = 0.35 * side


func _draw_gearbox() -> void:
	_current_slot = "gearbox"
	var case_mat := _mat(_col(), 0.75, 0.45)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	_box(_engine_c + Vector3(0.0, -0.06, 0.22), Vector3(_block_w * 0.8, 0.18, 0.16), case_mat)
	var clutch := _mesh_instance(_cylinder(0.1, 0.04), case_mat, _engine_c + Vector3(_block_w * 0.5 + 0.02, -0.02, 0.1))
	clutch.rotation.z = PI * 0.5
	_tube(_engine_c + Vector3(-_block_w * 0.5 - 0.06, -0.09, 0.2), _engine_c + Vector3(-_block_w * 0.5 - 0.14, -0.13, 0.12), 0.008, chrome)


func _draw_exhaust(zr: float) -> void:
	_current_slot = "exhaust"
	var exhaust_id := _part_id()
	var pipe_mat := _mat(_col(), 1.0, 0.15)
	var header_back := Vector3(0.15, -0.04, _pivot.z + 0.05)
	for i in _cyls.size():
		var c: Dictionary = _cyls[i]
		var port: Vector3 = c["base"] + c["up"] * 0.11 + Vector3(0.0, 0.0, -0.08)
		if _build.layout == "vtwin" and i == 1:
			port = c["base"] + c["up"] * 0.1 + Vector3(0.07, 0.0, 0.0)
		var low := Vector3(0.1 + port.x * 0.4, -0.08, _engine_c.z - 0.16)
		if _build.layout == "vtwin" and i == 1:
			low = Vector3(0.14, 0.0, _engine_c.z + 0.12)
		_tube(port, low, 0.02, pipe_mat)
		_tube(low, header_back, 0.022, pipe_mat)
	var can_end := Vector3(0.16, 0.2, zr - 0.08)
	_exhaust_tip = can_end + Vector3(0.0, 0.0, 0.06)
	match exhaust_id:
		"straight_pipe":
			_tube(header_back, can_end + Vector3(0.0, -0.04, 0.12), 0.03, pipe_mat)
			_exhaust_tip = can_end + Vector3(0.0, -0.04, 0.14)
		"slip_on":
			_tube(header_back, header_back.lerp(can_end, 0.4), 0.03, _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12))
			_tube(header_back.lerp(can_end, 0.4), can_end, 0.05, _mat(_col(), 0.3, 0.3, 0.7))
		"titanium_race", "full_system":
			_tube(header_back, header_back.lerp(can_end, 0.5), 0.032, pipe_mat)
			_tube(header_back.lerp(can_end, 0.5), can_end, 0.048, pipe_mat, Vector3(1.0, 1.0, 0.8))
		_:
			_tube(header_back, can_end, 0.06, pipe_mat)


# ---------------------------------------------------------------------------- front end

func _draw_fork(build: BikeBuild) -> void:
	_current_slot = "fork"
	var style := str(_part().get("style", "conventional"))
	var main_mat := _mat(_col(), 0.9, 0.2)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.3, 0.5)
	var gold := _mat(Color(0.8, 0.65, 0.2), 1.0, 0.15)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var fl := build.fork_length
	match style:
		"girder":
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.09 * side, 0.02, -0.03), Vector3(0.09 * side, 0.0, -0.03) - _steer_axis * fl, 0.02, main_mat, Vector3(1.0, 1.0, 2.2), _steer_node)
				_box(Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (fl * 0.5), Vector3(0.025, 0.04, 0.12), main_mat, _steer_node)
			var spring := _tube(Vector3(0.0, 0.0, -0.06), Vector3(0.0, 0.0, -0.06) - _steer_axis * 0.18, 0.025, chrome, Vector3.ONE, _steer_node)
			spring.name = "Spring"
		"usd":
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.09 * side, 0.02, 0.0), Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (fl * 0.55), 0.034, main_mat, Vector3.ONE, _steer_node)
				_tube(Vector3(0.09 * side, 0.0, 0.0), Vector3(0.09 * side, 0.0, 0.0) + _steer_axis * (fl * 0.5), 0.022, gold, Vector3.ONE, _front_hub)
		_:
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.09 * side, 0.02, 0.0), Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (fl * 0.55), 0.024, main_mat, Vector3.ONE, _steer_node)
				_tube(Vector3(0.09 * side, 0.0, 0.0), Vector3(0.09 * side, 0.0, 0.0) + _steer_axis * (fl * 0.5), 0.032, black, Vector3.ONE, _front_hub)
	var clamp_mat := _mat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	_box(Vector3.ZERO, Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	_box(-_steer_axis * 0.16, Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	# The front mudguard is a part of its own now: see _draw_front_mudguard.


func _draw_handlebars() -> void:
	_current_slot = "handlebars"
	var p := _part()
	var mat := _mat(_col(), 0.6, 0.35)
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.92)
	var hw := float(p.get("width", 720)) / 2000.0
	var rise := float(p.get("rise", 0.08))
	var ends := []
	match str(p.get("style", "Flat")):
		"Clip-ons":
			for side in [-1.0, 1.0]:
				var a := Vector3(0.09 * side, -0.07, 0.0)
				var b := Vector3(hw * side, rise, 0.13)
				_tube(a, b, 0.013, mat, Vector3.ONE, _steer_node)
				ends.append(b)
		"Ape hanger":
			for side in [-1.0, 1.0]:
				var post_top := Vector3(0.12 * side, rise, 0.0)
				_tube(Vector3(0.05 * side, 0.02, 0.0), post_top, 0.012, mat, Vector3.ONE, _steer_node)
				var end := Vector3(hw * side, rise - 0.03, 0.14)
				_tube(post_top, end, 0.012, mat, Vector3.ONE, _steer_node)
				ends.append(end)
		"MX braced":
			for side in [-1.0, 1.0]:
				var mid := Vector3(0.14 * side, rise, 0.0)
				var end := Vector3(hw * side, rise + 0.03, 0.1)
				_tube(mid, end, 0.014, mat, Vector3.ONE, _steer_node)
				_tube(Vector3(0.04 * side, 0.02, 0.0), mid, 0.016, mat, Vector3.ONE, _steer_node)
				ends.append(end)
			_tube(Vector3(-0.14, rise, 0.0), Vector3(0.14, rise, 0.0), 0.014, mat, Vector3.ONE, _steer_node)
			_tube(Vector3(-0.12, rise + 0.07, 0.01), Vector3(0.12, rise + 0.07, 0.01), 0.01, mat, Vector3.ONE, _steer_node)
		_:
			_tube(Vector3(-hw, rise, 0.06), Vector3(hw, rise, 0.06), 0.012, mat, Vector3.ONE, _steer_node)
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.04 * side, 0.0, 0.0), Vector3(0.04 * side, rise, 0.06), 0.014, mat, Vector3.ONE, _steer_node)
				ends.append(Vector3(hw * side, rise, 0.06))
	for end in ends:
		var inward := Vector3(-signf(end.x) * 0.1, 0.0, 0.0)
		_tube(end, end + inward, 0.018, rubber, Vector3.ONE, _steer_node)
	_grip_l = ends[0] + Vector3(0.05, 0.0, 0.0)
	_grip_r = ends[1] + Vector3(-0.05, 0.0, 0.0)


func _draw_dashboard() -> void:
	_current_slot = "dashboard"
	_needles.clear()
	_leds.clear()
	_dash_screen = Transform3D()
	var p := _part()
	var housing := _mat(_col(), 0.6, 0.35)
	var at := Vector3(0.0, 0.1, -0.06)
	# The clocks lean back towards the rider, so their faces look up and back at the eyes.
	var tilt := Basis(Vector3.RIGHT, 0.9)
	var face_mat := _lamp(Color(0.95, 0.9, 0.75), 1.2, "ign")
	var needle_mat := _lamp(Color(1.0, 0.25, 0.1), 2.5, "ign")
	match str(p.get("style", "analog")):
		"analog", "twin":
			var twin: bool = p.get("style") == "twin"
			var dials := [{"x": -0.06, "what": "speed"}, {"x": 0.06, "what": "rpm"}] if twin else [{"x": 0.0, "what": "speed"}]
			for d in dials:
				var c: Vector3 = at + Vector3(d["x"], 0.0, 0.0)
				var dial := _mesh_instance(_cylinder(0.05, 0.05), housing, c, _steer_node)
				dial.basis = tilt
				var face := _mesh_instance(_cylinder(0.043, 0.004), face_mat, c + tilt.y * 0.026, _steer_node)
				face.basis = tilt
				# Tick marks round the dial.
				for i in 9:
					var a := lerpf(-2.35, 2.35, i / 8.0)
					var tick := _box(c + tilt.y * 0.029 + tilt * Vector3(sin(a) * 0.036, 0.0, -cos(a) * 0.036), Vector3(0.003, 0.002, 0.008), _mat(Color(0.05, 0.05, 0.05), 0.0, 0.8), _steer_node)
					tick.basis = tilt * Basis(Vector3.UP, -a)
				var pivot := Node3D.new()
				pivot.position = c + tilt.y * 0.031
				pivot.basis = tilt
				_steer_node.add_child(pivot)
				_box(Vector3(0.0, 0.0, -0.016), Vector3(0.004, 0.003, 0.034), needle_mat, pivot)
				_needles.append({"node": pivot, "what": d["what"]})
			# The little window under the needle (or between the two dials) for gear and fuel.
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.032 + tilt * Vector3(0.0, 0.0, 0.046 if twin else 0.022))
		"lcd", "tft":
			var tft: bool = p.get("style") == "tft"
			var size := Vector3(0.2, 0.03, 0.12) if tft else Vector3(0.16, 0.03, 0.09)
			var body := _box(at, size, housing, _steer_node)
			body.basis = tilt
			var screen := _box(at + tilt.y * 0.016, Vector3(size.x - 0.02, 0.004, size.z - 0.02),
				_lamp(Color(0.05, 0.12, 0.25) if tft else Color(0.42, 0.55, 0.42), 1.0, "ign"), _steer_node)
			screen.basis = tilt
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.019)
			if tft:
				_add_leds(at + tilt.y * 0.017 + tilt * Vector3(0.0, 0.0, -size.z * 0.5 - 0.008), tilt, 0.14)
		_:
			var body := _box(at, Vector3(0.22, 0.03, 0.09), housing, _steer_node)
			body.basis = tilt
			var screen := _box(at + tilt.y * 0.016 + tilt * Vector3(0.0, 0.0, 0.012), Vector3(0.18, 0.004, 0.05),
				_lamp(Color(0.03, 0.03, 0.04), 0.6, "ign"), _steer_node)
			screen.basis = tilt
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.019 + tilt * Vector3(0.0, 0.0, 0.012))
			_add_leds(at + tilt.y * 0.017 + tilt * Vector3(0.0, 0.0, -0.028), tilt, 0.18)


## A row of shift lights across the top of the clocks, green to amber to red.
func _add_leds(center: Vector3, tilt: Basis, width: float) -> void:
	var colors := [Color(0.1, 1.0, 0.2), Color(0.1, 1.0, 0.2), Color(1.0, 0.85, 0.1), Color(1.0, 0.85, 0.1), Color(1.0, 0.1, 0.05), Color(1.0, 0.1, 0.05)]
	for i in 6:
		var mat := _glow(colors[i], 0.0)
		var led := _box(center + tilt.x * (-width * 0.5 + width * (i + 0.5) / 6.0), Vector3(0.016, 0.004, 0.01), mat, _steer_node)
		led.basis = tilt
		_leds.append({"mat": mat, "color": colors[i]})


## Moves the needles and shift lights: `speed_frac` and `rpm_frac` are 0..1 of full scale.
func set_gauges(speed_frac: float, rpm_frac: float) -> void:
	for n in _needles:
		var f: float = speed_frac if n["what"] == "speed" else rpm_frac
		(n["node"] as Node3D).basis = _dash_screen.basis * Basis(Vector3.UP, lerpf(2.35, -2.35, clampf(f, 0.0, 1.0)))
	for i in _leds.size():
		var lit := rpm_frac > 0.55 + i * 0.07
		var m: StandardMaterial3D = _leds[i]["mat"]
		m.emission_energy_multiplier = 3.0 if lit else 0.0
		m.albedo_color = _leds[i]["color"] if lit else Color(0.08, 0.08, 0.08)
	if not geometry.is_empty() and not _needles.is_empty():
		_update_geometry()


func _draw_front_master() -> void:
	_current_slot = "front_master"
	var mat := _mat(_col(), 0.6, 0.35)
	var radial := str(_part().get("type", "")).begins_with("Radial")
	var at := _grip_r + Vector3(-0.08, 0.0, 0.0)
	_box(at, Vector3(0.04, 0.04, 0.05) if radial else Vector3(0.035, 0.035, 0.035), mat, _steer_node)
	_mesh_instance(_cylinder(0.022 if radial else 0.018, 0.03), mat, at + Vector3(0.0, 0.04, 0.0), _steer_node)
	_tube(at + Vector3(0.0, 0.0, -0.03), _grip_r + Vector3(0.08, 0.0, -0.05), 0.006, _mat(Color(0.7, 0.71, 0.73), 1.0, 0.3), Vector3.ONE, _steer_node)


func _draw_rear_master() -> void:
	_current_slot = "rear_master"
	var mat := _mat(_col(), 0.6, 0.35)
	var at := Vector3(0.15, 0.06, _pivot.z - 0.04)
	_tube(at, at + Vector3(0.0, 0.1, 0.03), 0.014, mat)
	_mesh_instance(_cylinder(0.02, 0.04), mat, at + Vector3(0.0, 0.16, 0.08))


## The headlight on the fork: round, a café bucket, twin lamps, an enduro plate or an LED projector.
func _draw_headlight() -> void:
	_current_slot = "headlight"
	var p := _part()
	if p.is_empty():
		return
	var at := Vector3(0.0, -0.08, -0.13)
	var size := float(p.get("size", 0.08))
	var shell := _mat(_col(), 0.7, 0.3)
	var lens := _lamp(Color(1.0, 0.95, 0.82) if float(p.get("lumens", 0)) < 2000 else Color(0.9, 0.95, 1.0), 2.5, "head")
	match str(p.get("style", "round")):
		"bucket":
			var bucket := _mesh_instance(_cylinder(size, size * 1.1, size * 0.75), shell, at + Vector3(0.0, 0.0, 0.03), _steer_node)
			bucket.rotation.x = -PI * 0.5
			var face := _mesh_instance(_cylinder(size * 0.92, 0.01), lens, at + Vector3(0.0, 0.0, -0.03), _steer_node)
			face.rotation.x = PI * 0.5
		"twin":
			for x in [-0.07, 0.07]:
				var lamp := _mesh_instance(_sphere(size), shell, at + Vector3(x, 0.0, 0.01), _steer_node)
				lamp.scale = Vector3(1.0, 1.0, 0.7)
				var face := _mesh_instance(_cylinder(size * 0.85, 0.01), lens, at + Vector3(x, 0.0, -size * 0.6), _steer_node)
				face.rotation.x = PI * 0.5
		"plate":
			var plate := _box(at + Vector3(0.0, -0.02, -0.02), Vector3(0.22, 0.27, 0.02), shell, _steer_node)
			plate.rotation.x = 0.25
			var face := _box(at + Vector3(0.0, 0.0, -0.035), Vector3(0.1, 0.07, 0.01), lens, _steer_node)
			face.rotation.x = 0.25
		"projector":
			_box(at + Vector3(0.0, 0.0, 0.0), Vector3(0.17, 0.09, 0.09), shell, _steer_node)
			for x in [-0.04, 0.04]:
				var face := _mesh_instance(_cylinder(0.025, 0.01), lens, at + Vector3(x, 0.0, -0.05), _steer_node)
				face.rotation.x = PI * 0.5
			_box(at + Vector3(0.0, -0.035, -0.047), Vector3(0.15, 0.008, 0.004), _lamp(Color(0.85, 0.92, 1.0), 3.0, "head"), _steer_node)
		_:
			var lamp := _mesh_instance(_sphere(size), shell, at, _steer_node)
			lamp.scale = Vector3(1.0, 1.0, 0.75)
			var face := _mesh_instance(_cylinder(size * 0.9, 0.012), lens, at + Vector3(0.0, 0.0, -size * 0.7), _steer_node)
			face.rotation.x = PI * 0.5


## The horn under the headstock: a disc, a pair of snail or air trumpets, a klaxon or a bulb.
func _draw_horn() -> void:
	_current_slot = "horn"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.8, 0.25)
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	var at := _head_bottom + Vector3(0.0, -0.1, 0.07)
	match str(p.get("style", "disc")):
		"snail":
			for x in [-0.045, 0.045]:
				var shell := _mesh_instance(_sphere(0.035), mat, at + Vector3(x, 0.0, 0.0))
				shell.scale = Vector3(0.6, 1.0, 1.0)
				var bell := _mesh_instance(_cylinder(0.012, 0.04, 0.025), mat, at + Vector3(x, 0.0, -0.04))
				bell.rotation.x = -PI * 0.5
		"air":
			var n := int(p.get("tones", [1, 1]).size())
			for i in n:
				var x := (i - (n - 1) * 0.5) * 0.04
				var length := 0.12 + 0.03 * i
				var horn := _mesh_instance(_cylinder(0.009, length, 0.03), mat, at + Vector3(x, 0.0, -length * 0.3))
				horn.rotation.x = -PI * 0.5
			_box(at + Vector3(0.0, -0.03, 0.04), Vector3(0.07, 0.05, 0.06), dark)
		"klaxon":
			var tube := _mesh_instance(_cylinder(0.018, 0.12, 0.05), mat, at + Vector3(0.0, 0.0, -0.04))
			tube.rotation.x = -PI * 0.5
			_mesh_instance(_sphere(0.04), mat, at + Vector3(0.0, 0.0, 0.05))
		"bulb":
			var tube := _mesh_instance(_cylinder(0.01, 0.1, 0.03), _mat(Color(0.78, 0.6, 0.25), 0.9, 0.2), at + Vector3(0.0, 0.0, -0.03))
			tube.rotation.x = -PI * 0.5
			_mesh_instance(_sphere(0.035), mat, at + Vector3(0.0, 0.0, 0.05))
		"melody":
			for i in 5:
				var horn := _mesh_instance(_cylinder(0.007, 0.08 + 0.02 * i, 0.022), mat, at + Vector3((i - 2) * 0.026, 0.0, -0.03))
				horn.rotation.x = -PI * 0.5
		_:
			var disc := _mesh_instance(_cylinder(0.04, 0.03), mat, at)
			disc.rotation.x = PI * 0.5
			var grille := _mesh_instance(_cylinder(0.03, 0.006), dark, at + Vector3(0.0, 0.0, -0.017))
			grille.rotation.x = PI * 0.5


## The ECU: a small box tucked under the side panel, below the front of the seat.
func _draw_ecu() -> void:
	_current_slot = "ecu"
	var p := _part()
	if p.is_empty():
		return
	var at := Vector3(0.12, _seat_y - 0.17, lerpf(_seat_front.z, _tail.z, 0.3))
	_box(at, Vector3(0.035, 0.08, 0.13), _mat(_col(), 0.5, 0.35))
	_box(at + Vector3(0.019, 0.0, 0.0), Vector3(0.004, 0.05, 0.09), _mat(Color(0.75, 0.76, 0.78), 0.9, 0.3))
	_tube(at + Vector3(0.0, 0.04, -0.06), at + Vector3(-0.08, 0.1, -0.16), 0.006, _mat(Color(0.05, 0.05, 0.05), 0.0, 0.7))


## Panniers either side of the back wheel, hung off a rack: soft bags or hard boxes.
func _draw_panniers(build: BikeBuild, zr: float) -> void:
	_current_slot = "panniers"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.9 if p.get("style", "") == "alloy" else 0.0, 0.35 if p.get("style", "") in ["alloy", "hard"] else 0.8)
	var rack := _mat(Color(0.1, 0.1, 0.11), 0.6, 0.4)
	var litres := float(p.get("litres", 40.0))
	var k := pow(litres / 60.0, 0.33)
	var top := _seat_y - 0.04
	var w := build.rear_tyre_width * 0.5 + 0.12
	for side in [-1.0, 1.0]:
		var depth := 0.15 * k
		var c := Vector3(side * (w + depth * 0.5), top - 0.17 * k, zr - 0.08)
		match str(p.get("style", "hard")):
			"soft", "roll":
				var bag := _mesh_instance(_capsule(0.12 * k, 0.42 * k), mat, c)
				bag.rotation.x = PI * 0.5
				bag.scale = Vector3(depth / (0.24 * k), 1.25, 1.0)
				if p.get("style", "") == "roll":
					var roll := _mesh_instance(_cylinder(0.035, 0.3 * k), mat, c + Vector3(0.0, 0.17 * k, 0.0))
					roll.rotation.x = PI * 0.5
			"leather":
				_box(c, Vector3(depth, 0.3 * k, 0.4 * k), mat)
				var flap := _box(c + Vector3(side * 0.01, 0.1 * k, 0.0), Vector3(depth + 0.02, 0.12 * k, 0.42 * k), mat)
				flap.rotation.z = -side * 0.05
				for z in [-0.1, 0.1]:
					_box(c + Vector3(side * (depth * 0.5 + 0.012), 0.04 * k, z * k), Vector3(0.006, 0.12 * k, 0.02),
						_mat(Color(0.8, 0.7, 0.4), 0.9, 0.3))
			_:
				_box(c, Vector3(depth, 0.34 * k, 0.46 * k), mat)
				_box(c + Vector3(0.0, 0.17 * k + 0.012, 0.0), Vector3(depth + 0.01, 0.025, 0.47 * k), _mat(_col().darkened(0.3), 0.5, 0.4))
				_box(c + Vector3(side * (depth * 0.5 + 0.004), 0.08 * k, 0.0), Vector3(0.006, 0.02, 0.1), rack)
		_tube(Vector3(side * w, top, _pivot.z + 0.1), Vector3(side * w, top, zr + 0.16), 0.008, rack)
		_tube(Vector3(side * w, top, zr + 0.16), Vector3(side * w, top - 0.3 * k, zr + 0.12), 0.008, rack)


## A top box on a rack behind the seat: plastic, alloy, a wooden crate or a leather trunk.
func _draw_top_box() -> void:
	_current_slot = "top_box"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "small"))
	var mat := _mat(_col(), 0.9 if style == "alloy" else 0.0, 0.35 if style in ["alloy", "small", "large"] else 0.85)
	var rack := _mat(Color(0.75, 0.76, 0.78) if style == "trunk" else Color(0.1, 0.1, 0.11), 0.8, 0.3)
	var k := pow(float(p.get("litres", 35.0)) / 35.0, 0.33)
	var base := Vector3(0.0, _seat_y + 0.04, _tail.z + 0.1)
	_box(base, Vector3(0.24, 0.015, 0.3), rack)
	var size := Vector3(0.36, 0.26, 0.34) * k
	var c := base + Vector3(0.0, size.y * 0.5 + 0.01, 0.0)
	match style:
		"crate":
			for i in 4:
				_box(c + Vector3(0.0, -size.y * 0.5 + (i + 0.5) * size.y / 4.0, 0.0), Vector3(size.x, size.y / 4.0 - 0.012, size.z), mat)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_box(c + Vector3(x * size.x * 0.48, 0.0, z * size.z * 0.48), Vector3(0.02, size.y, 0.02), _mat(_col().darkened(0.25), 0.0, 0.9))
		"trunk":
			_box(c, size, mat)
			_box(c + Vector3(0.0, size.y * 0.3, 0.0), Vector3(size.x + 0.01, 0.02, size.z + 0.01), _mat(_col().darkened(0.35), 0.0, 0.8))
			_box(c + Vector3(0.0, 0.03, -size.z * 0.5 - 0.004), Vector3(0.04, 0.05, 0.006), _mat(Color(0.8, 0.7, 0.4), 0.9, 0.3))
		_:
			var shell := _mesh_instance(_capsule(size.y * 0.5, size.x), mat, c)
			shell.rotation.z = PI * 0.5
			shell.scale = Vector3(1.0, 1.0, size.z / size.y)
			if style == "large":
				var pad := _box(c + Vector3(0.0, 0.0, -size.z * 0.5 - 0.01), Vector3(0.22, 0.12, 0.03), _mat(Color(0.08, 0.08, 0.08), 0.0, 0.8))
				pad.rotation.x = 0.15
			_box(c + Vector3(0.0, size.y * 0.05, size.z * 0.5), Vector3(0.12, 0.04, 0.01), _lamp(Color(0.9, 0.1, 0.05), 0.6, "ign"))


## Fog or spot lamps on the fork legs, or an LED bar across the fork.
func _draw_fog_lights() -> void:
	_current_slot = "fog_lights"
	var p := _part()
	if p.is_empty():
		return
	var shell := _mat(_col(), 0.8, 0.25)
	var b: Array = p.get("beam", [1.0, 0.9, 0.8])
	var lens := _lamp(Color(b[0], b[1], b[2]), 2.0, "ign")
	var style := str(p.get("style", "round"))
	if style == "bar":
		var mid := -_steer_axis * 0.2 + Vector3(0.0, 0.0, -0.1)
		_box(mid, Vector3(0.34, 0.045, 0.05), shell, _steer_node)
		_box(mid + Vector3(0.0, 0.0, -0.026), Vector3(0.31, 0.03, 0.004), lens, _steer_node)
		return
	for x in [-1.0, 1.0]:
		var at := -_steer_axis * 0.34 + Vector3(0.15 * x, 0.0, -0.06)
		match style:
			"cube":
				_box(at, Vector3(0.06, 0.06, 0.06), shell, _steer_node)
				_box(at + Vector3(0.0, 0.0, -0.031), Vector3(0.048, 0.048, 0.004), lens, _steer_node)
			"rally":
				var can := _mesh_instance(_cylinder(0.06, 0.06), shell, at, _steer_node)
				can.rotation.x = PI * 0.5
				var face := _mesh_instance(_cylinder(0.055, 0.006), lens, at + Vector3(0.0, 0.0, -0.032), _steer_node)
				face.rotation.x = PI * 0.5
				for i in 3:
					_box(at + Vector3(0.0, (i - 1) * 0.03, -0.04), Vector3(0.11, 0.006, 0.006), shell, _steer_node)
			_:
				var can := _mesh_instance(_sphere(0.04), shell, at, _steer_node)
				can.scale = Vector3(1.0, 1.0, 0.8)
				var face := _mesh_instance(_cylinder(0.035, 0.006), lens, at + Vector3(0.0, 0.0, -0.03), _steer_node)
				face.rotation.x = PI * 0.5


## Where the fog lamps sit, in the bike's own space (straight ahead), or [] with none fitted.
func fog_positions() -> Array:
	var p := PartsDB.get_part(str(_build.parts.get("fog_lights", "none"))) if _build else {}
	if p.is_empty():
		return []
	if str(p.get("style", "")) == "bar":
		return [_head - _steer_axis * 0.2 + Vector3(0.0, 0.0, -0.13)]
	return [_head - _steer_axis * 0.34 + Vector3(-0.15, 0.0, -0.09), _head - _steer_axis * 0.34 + Vector3(0.15, 0.0, -0.09)]


## The tail unit behind the seat: the rear light, the mudguard (or hugger) and the number plate,
## as a long classic guard, a café hump, a scrambler loop, a sports tail tidy, a bobbed fender
## or a high enduro fender. The lamp sits where the part says (see tail_light_position).
func _draw_tail(build: BikeBuild) -> void:
	_current_slot = "tail"
	var p := _part()
	if p.is_empty():
		return
	var metal := str(p.get("material", "")) == "metal"
	var mat := _mat(_col(), 0.85 if metal else 0.1, 0.25 if metal else 0.45, 0.0 if metal else 0.4)
	var black := _mat(Color(0.04, 0.04, 0.045), 0.3, 0.6)
	var plate := _mat(Color(0.95, 0.82, 0.16), 0.0, 0.5)
	var lamp := tail_light_position()
	var axle := Vector3(0.0, 0.0, build.wheelbase * 0.5)
	var r := build.rear_radius
	var w := build.rear_tyre_width + 0.05
	match str(p.get("style", "classic")):
		"cafe":
			var cowl := _box(_tail + Vector3(0.0, 0.0, 0.14), Vector3(0.24, 0.12, 0.3), mat)
			cowl.rotation.x = -0.08
			var hump := _box(_tail + Vector3(0.0, 0.08, 0.1), Vector3(0.2, 0.07, 0.24), mat)
			hump.rotation.x = 0.22
			_guard(axle, r + 0.03, w, -0.25, 0.75, black, 5)
			_tube(_tail + Vector3(0.0, -0.05, 0.24), _tail + Vector3(0.0, -0.15, 0.31), 0.008, black)
			_number_plate(_tail + Vector3(0.0, -0.2, 0.32), Vector2(0.18, 0.12), -0.2, plate)
		"loop":
			for side in [-1.0, 1.0]:
				_tube(_tail + Vector3(0.07 * side, 0.0, -0.08), _tail + Vector3(0.07 * side, 0.01, 0.2), 0.012, mat)
				_tube(_tail + Vector3(0.07 * side, 0.01, 0.2), _tail + Vector3(0.04 * side, 0.04, 0.25), 0.012, mat)
			_tube(_tail + Vector3(-0.04, 0.04, 0.25), _tail + Vector3(0.04, 0.04, 0.25), 0.012, mat)
			_guard(axle, r + 0.04, w, -0.3, 0.8, mat, 5)
			_tube(_tail + Vector3(0.0, 0.01, 0.2), lamp, 0.008, black)
			_number_plate(lamp + Vector3(0.0, -0.09, 0.0), Vector2(0.16, 0.11), -0.1, plate)
		"tidy":
			var tray := _box(_tail + Vector3(0.0, -0.05, 0.1), Vector3(0.18, 0.025, 0.28), mat)
			tray.rotation.x = -0.15
			_box(lamp - Vector3(0.0, 0.0, 0.012), Vector3(0.16, 0.035, 0.02), mat)
			_tube(_tail + Vector3(0.0, -0.06, 0.2), _tail + Vector3(0.0, -0.15, 0.33), 0.01, black)
			_number_plate(_tail + Vector3(0.0, -0.2, 0.34), Vector2(0.17, 0.11), -0.35, plate)
		"bobber":
			_guard(axle, r + 0.035, w, -0.55, 1.05, mat, 6)
			var plate_at := axle + Vector3(-(w * 0.5 + 0.06), 0.14, 0.04)
			_tube(axle + Vector3(-(w * 0.5 + 0.02), 0.04, 0.0), plate_at, 0.008, black)
			var side_plate := _number_plate(plate_at, Vector2(0.17, 0.12), 0.0, plate)
			side_plate.rotation.y = PI * 0.5
		"enduro":
			var a := _tail + Vector3(0.0, -0.05, -0.12)
			var b := _tail + Vector3(0.0, -0.02, 0.2)
			var c := _tail + Vector3(0.0, 0.06, 0.46)
			_plank(a, b, w + 0.02, 0.012, mat)
			_plank(b, c, w, 0.012, mat)
			_number_plate(lamp + Vector3(0.0, -0.07, -0.01), Vector2(0.13, 0.08), -0.3, plate)
		_:
			_guard(axle, r + 0.05, w + 0.02, -0.45, 2.0, mat, 10)
			# The lamp on a bracket off the guard, the plate below it.
			var a := atan2(lamp.z - axle.z, lamp.y - axle.y)
			_tube(lamp, axle + Vector3(0.0, cos(a), sin(a)) * (r + 0.05), 0.01, mat)
			var below := a + 0.4
			_number_plate(axle + Vector3(0.0, cos(below), sin(below)) * (r + 0.08), Vector2(0.2, 0.13), -0.25, plate)
	# The rear light, lit with the ignition.
	var lens := _lamp(Color(1.0, 0.05, 0.02), 2.0, "ign")
	var face: MeshInstance3D
	match str(p.get("light", "round")):
		"lucas":
			_box(lamp, Vector3(0.12, 0.07, 0.07), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15))
			face = _box(lamp + Vector3(0.0, 0.0, 0.037), Vector3(0.1, 0.05, 0.008), lens)
		"strip":
			face = _box(lamp, Vector3(0.14, 0.022, 0.01), lens)
		"bullet":
			var shell := _mesh_instance(_sphere(0.03), black, lamp)
			shell.scale = Vector3(1.0, 1.0, 1.5)
			face = _mesh_instance(_cylinder(0.025, 0.006), lens, lamp + Vector3(0.0, 0.0, 0.043))
			face.rotation.x = PI * 0.5
		"led":
			_box(lamp - Vector3(0.0, 0.0, 0.01), Vector3(0.07, 0.035, 0.03), black)
			face = _box(lamp + Vector3(0.0, 0.0, 0.006), Vector3(0.06, 0.025, 0.006), lens)
		_:
			var can := _mesh_instance(_cylinder(0.036, 0.04), black, lamp)
			can.rotation.x = PI * 0.5
			face = _mesh_instance(_cylinder(0.032, 0.006), lens, lamp + Vector3(0.0, 0.0, 0.022))
			face.rotation.x = PI * 0.5
	face.name = "TailLight"


## Where the rear light sits, in the bike's own space: the tail unit's "light_at" (up and back
## from the end of the subframe). Vector3.ZERO with no tail unit.
func tail_light_position() -> Vector3:
	var p := PartsDB.get_part(str(_build.parts.get("tail", "none"))) if _build else {}
	if p.is_empty():
		return Vector3.ZERO
	var at: Array = p.get("light_at", [0.0, 0.25])
	return _tail + Vector3(0.0, float(at[0]), float(at[1]))


## A mudguard following a wheel: plates round an arc of `radius` about `c`, from angle `a0` to
## `a1` (radians from straight up, positive towards the back).
func _guard(c: Vector3, radius: float, width: float, a0: float, a1: float, mat: Material, segs := 8, parent: Node3D = self) -> void:
	var step := (a1 - a0) / segs
	for i in segs:
		var a := a0 + step * (i + 0.5)
		var seg := _box(c + Vector3(0.0, cos(a), sin(a)) * radius, Vector3(width, 0.012, radius * step * 1.1), mat, parent)
		seg.rotation.x = a


## A flat plate from `a` to `b` (both on the centre line), `width` across and `thick` deep.
func _plank(a: Vector3, b: Vector3, width: float, thick: float, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var d := b - a
	var plank := _box((a + b) * 0.5, Vector3(width, thick, d.length()), mat, parent)
	plank.rotation.x = atan2(-d.y, d.z)
	return plank


## The front mudguard. Low ones follow the tyre on the fork legs, so they ride up and down with
## the wheel: a short hugger, a carbon sport hugger, a slim cafe blade, a bobbed blade or a long
## valanced classic on stays. High ones (MX and enduro) bolt under the bottom yoke and stay put
## while the wheel moves under them. Painted ones take the part's own colour like the tank.
func _draw_front_mudguard(build: BikeBuild) -> void:
	_current_slot = "front_mudguard"
	var p := _part()
	if p.is_empty():
		return
	var material := str(p.get("material", "plastic"))
	var col := _col()
	var mat: StandardMaterial3D
	match material:
		"metal":
			mat = _mat(col, 0.25 if p.get("paint_match", false) else 0.9, 0.2 if p.get("paint_match", false) else 0.15, 0.6 if p.get("paint_match", false) else 0.0)
		"carbon":
			mat = _mat(col, 0.2, 0.25, 0.8)
		_:
			mat = _mat(col, 0.1, 0.4, 0.5)
	var stay := _mat(Color(0.82, 0.83, 0.85), 0.95, 0.2)
	var black := _mat(Color(0.04, 0.04, 0.045), 0.3, 0.6)
	var r := build.front_radius
	var w := build.front_tyre_width + 0.03
	var style := str(p.get("style", "hugger"))
	if style in ["high", "enduro"]:
		# Under the bottom yoke, sweeping forward and up into a beak; the enduro one is longer
		# at the back and has a lip at the front.
		# A hand's width above the tyre at rest (in steering space), held up off the yoke on stays.
		var axle := Vector3(0.0, 0.0, -build.wheelbase * 0.5) - _head
		var top := axle + Vector3(0.0, r + 0.1, 0.0)
		var yoke := -_steer_axis * 0.16
		var base := Vector3(0.0, minf(top.y, yoke.y - 0.03), lerpf(top.z, yoke.z, 0.5))
		var long := style == "enduro"
		var back := base + Vector3(0.0, -0.04, 0.14 if long else 0.08)
		var mid := base + Vector3(0.0, 0.0, -0.08)
		var nose := base + Vector3(0.0, 0.06, -0.3 if long else -0.34)
		_plank(back, base, w + 0.02, 0.012, mat, _steer_node)
		_plank(base, mid, w + 0.01, 0.012, mat, _steer_node)
		_plank(mid, nose, w, 0.012, mat, _steer_node)
		if long:
			_plank(nose, nose + Vector3(0.0, -0.05, -0.03), w * 0.8, 0.012, mat, _steer_node)
		for side in [-1.0, 1.0]:
			_tube(base + Vector3(0.05 * side, 0.0, 0.0), yoke + Vector3(0.05 * side, -0.02, 0.0), 0.008, black, Vector3.ONE, _steer_node)
		return
	var gap := 0.03
	var a0 := -0.5
	var a1 := 0.75
	match style:
		"sport":
			gap = 0.02
			a0 = -0.35
			a1 = 0.65
			w -= 0.01
		"cafe":
			gap = 0.035
			a0 = -0.75
			a1 = 0.95
			w -= 0.02
		"bobbed":
			gap = 0.03
			a0 = -0.3
			a1 = 0.45
		"classic":
			gap = 0.045
			a0 = -1.0
			a1 = 1.3
			w += 0.03
	var radius := r + gap
	_guard(Vector3.ZERO, radius, w, a0, a1, mat, 10 if style == "classic" else 6, _front_hub)
	if style == "classic":
		# Deep valances down each side of the tyre.
		for side in [-1.0, 1.0]:
			var step := (a1 - a0) / 8.0
			for i in 8:
				var a := a0 + step * (i + 0.5)
				var seg := _box(Vector3(w * 0.5 * side, 0.0, 0.0) + Vector3(0.0, cos(a), sin(a)) * (radius - 0.025),
					Vector3(0.008, 0.05, radius * step * 1.1), mat, _front_hub)
				seg.rotation.x = a
	# Bolted to the fork legs either side, just above the tyre.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.09 * side, radius * 0.92, 0.0), Vector3(0.03, 0.02, 0.05), black, _front_hub)
	if style in ["classic", "cafe", "bobbed"]:
		# Wire stays from the axle out to the guard, front and back.
		var ends := [a0 + 0.2, a1 - 0.2] if style != "bobbed" else [a1 - 0.1]
		for side in [-1.0, 1.0]:
			var x: float = (w * 0.5 + 0.01) * side
			for a: float in ends:
				_tube(Vector3(x, 0.0, 0.0), Vector3(x, 0.0, 0.0) + Vector3(0.0, cos(a), sin(a)) * radius, 0.005, stay, Vector3.ONE, _front_hub)


## A number plate facing backwards, its top leaning back by `tilt` (radians).
func _number_plate(at: Vector3, size: Vector2, tilt: float, mat: Material) -> MeshInstance3D:
	var plate := _box(at, Vector3(size.x, size.y, 0.005), mat)
	plate.rotation.x = tilt
	return plate


## The fairing round the headlight: a flyscreen or bikini fairing on the forks (they turn with
## the bars), or a half, touring or full race fairing on the frame, each with its screen. The
## nose is open in the middle, so the headlight shines through.
func _draw_fairing() -> void:
	_current_slot = "fairing"
	var p := _part()
	if p.is_empty():
		return
	var carbon := str(p.get("material", "")) == "carbon"
	var mat := _mat(_col(), 0.2 if carbon else 0.15, 0.25 if carbon else 0.2, 0.8 if carbon else 0.6)
	var glass := _mat(Color(0.5, 0.58, 0.66), 0.2, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.35
	var screen := float(p.get("screen", 0.15))
	var style := str(p.get("style", "half"))
	if style in ["flyscreen", "bikini"]:
		var lamp := Vector3(0.0, -0.08, -0.13)   # the headlight, in steering space (see _draw_headlight)
		var big := style == "bikini"
		if big:
			for side in [-1.0, 1.0]:
				var cheek := _box(lamp + Vector3(0.14 * side, 0.0, 0.03), Vector3(0.03, 0.2, 0.16), mat, _steer_node)
				cheek.rotation.y = 0.3 * side
			_box(lamp + Vector3(0.0, -0.1, 0.03), Vector3(0.26, 0.03, 0.14), mat, _steer_node)
		var cowl := _box(lamp + Vector3(0.0, 0.09 if big else 0.08, 0.02), Vector3(0.3 if big else 0.22, 0.04, 0.16 if big else 0.13), mat, _steer_node)
		cowl.rotation.x = 0.22
		var tilt := 0.45
		var base := lamp + Vector3(0.0, 0.1, 0.06)
		var glass_mi := _box(base + Vector3(0.0, cos(tilt), sin(tilt)) * screen * 0.5, Vector3(0.28 if big else 0.2, screen, 0.006), glass, _steer_node)
		glass_mi.rotation.x = tilt
		return
	var touring := style == "touring"
	var wide := 0.27 if touring else 0.2
	var tall := 1.25 if touring else 1.0
	var h := lamp_position()
	var brow := _box(h + Vector3(0.0, 0.11 * tall, -0.05), Vector3(wide * 2.0, 0.1, 0.05), mat)
	brow.rotation.x = 0.35
	_box(h + Vector3(0.0, -0.12 * tall, -0.03), Vector3(wide * 1.8, 0.08, 0.05), mat)
	for side in [-1.0, 1.0]:
		var cheek := _box(h + Vector3((wide - 0.02) * side, -0.01, 0.0), Vector3(0.03, 0.3 * tall, 0.26), mat)
		cheek.rotation.y = 0.3 * side
		if touring:
			# Knee wings to keep the rain off the rider's legs.
			_box(h + Vector3((wide + 0.02) * side, -0.27, 0.16), Vector3(0.03, 0.18, 0.2), mat)
	var top := _box(h + Vector3(0.0, 0.16 * tall, 0.05), Vector3(wide * 1.9, 0.03, 0.2), mat)
	top.rotation.x = 0.35
	var tilt := {"race": 0.85, "touring": 0.3}.get(style, 0.55) as float
	var base := h + Vector3(0.0, 0.17 * tall, 0.1)
	var glass_mi := _box(base + Vector3(0.0, cos(tilt), sin(tilt)) * screen * 0.5, Vector3(wide * 1.7, screen, 0.006), glass)
	glass_mi.rotation.x = tilt
	if style == "race":
		# Side panels down past the engine and a belly pan under it.
		var side_x := maxf(wide, _block_w * 0.5 + 0.07)
		var z0 := h.z + 0.08
		var z1 := _engine_c.z + 0.12
		for side in [-1.0, 1.0]:
			var panel := _box(Vector3(side_x * side, _engine_c.y + 0.06, (z0 + z1) * 0.5), Vector3(0.03, 0.36, z1 - z0), mat)
			panel.rotation.y = 0.06 * side
		_box(Vector3(0.0, _engine_c.y - 0.18, _engine_c.z + 0.02), Vector3(side_x * 1.8, 0.03, 0.4), mat)


## Mirrors: round or sport ones on stalks from the bars, round ones off the bar ends, tall
## touring ones, or pods on the fairing. The glass is a mirror finish, so from the saddle it
## catches the sky and the road round you.
func _draw_mirrors() -> void:
	_current_slot = "mirrors"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.8, 0.25)
	var glass := _mat(Color(0.9, 0.92, 0.95), 1.0, 0.02)
	var style := str(p.get("style", "round"))
	var fairing := PartsDB.get_part(str(_build.parts.get("fairing", "none")))
	if style == "fairing" and fairing.is_empty():
		style = "sport"   # nothing to bolt to (a loose part on its own): shown as stalks
	for side in [-1.0, 1.0]:
		var grip: Vector3 = _grip_r if side > 0.0 else _grip_l
		var base := Vector3(grip.x * 0.55, grip.y + 0.01, grip.z - 0.02)
		match style:
			"bar_end":
				var end := grip + Vector3(0.06 * side, 0.0, 0.0)
				var head := end + Vector3(0.07 * side, -0.04, -0.01)
				_tube(end, head, 0.008, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.045, 0.0), mat, glass, _steer_node)
			"sport":
				var head := base + Vector3(0.13 * side, 0.1, -0.08)
				_tube(base, head, 0.007, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.13, 0.06), mat, glass, _steer_node)
			"rect":
				var head := base + Vector3(0.14 * side, 0.28, -0.02)
				_tube(base, head, 0.008, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.13, 0.09), mat, glass, _steer_node)
			"fairing":
				if fairing.get("frame_mount", false):
					var wide := 0.27 if str(fairing.get("style", "")) == "touring" else 0.2
					var h := lamp_position()
					var head := h + Vector3((wide + 0.05) * side, 0.1, 0.06)
					_tube(h + Vector3((wide - 0.01) * side, 0.08, 0.04), head, 0.01, mat)
					_mirror_head(head, Vector2(0.11, 0.055), mat, glass, self)
				else:
					var lamp := Vector3(0.0, -0.08, -0.13)
					var head := lamp + Vector3(0.2 * side, 0.08, 0.05)
					_tube(lamp + Vector3(0.12 * side, 0.06, 0.03), head, 0.009, mat, Vector3.ONE, _steer_node)
					_mirror_head(head, Vector2(0.1, 0.05), mat, glass, _steer_node)
			_:
				var head := base + Vector3(0.08 * side, 0.2, -0.03)
				_tube(base, head, 0.007, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.05, 0.0), mat, glass, _steer_node)


## One mirror facing the rider: round (`size.x` its radius, `size.y` 0) or a rectangle `size`.
func _mirror_head(at: Vector3, size: Vector2, mat: Material, glass: Material, parent: Node3D) -> void:
	if size.y <= 0.0:
		var shell := _mesh_instance(_cylinder(size.x, 0.02), mat, at, parent)
		shell.rotation.x = PI * 0.5
		var face := _mesh_instance(_cylinder(size.x * 0.88, 0.002), glass, at + Vector3(0.0, 0.0, 0.011), parent)
		face.rotation.x = PI * 0.5
		face.name = "MirrorGlass"
		return
	_box(at, Vector3(size.x, size.y, 0.02), mat, parent)
	var pane := _box(at + Vector3(0.0, 0.0, 0.011), Vector3(size.x - 0.01, size.y - 0.01, 0.002), glass, parent)
	pane.name = "MirrorGlass"


## The side stand on the left, under the footpeg: tucked up along the frame, or down on the
## ground with the bike leaning over onto it.
func _draw_side_stand(build: BikeBuild) -> void:
	_current_slot = "side_stand"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.6, 0.4)
	var pivot := Vector3(-0.12, -0.04, _pivot.z - 0.16)
	var length := float(p.get("length", 0.3))
	var foot: Vector3
	if stand_pose == "side":
		# Swing the leg out until it reaches the ground with the bike leaned over by the stand's lean.
		var lean := deg_to_rad(float(p.get("lean", 12.0)))
		var height := pivot.y + build.rear_radius
		var best := 0.0
		var best_err := INF
		for i in 90:
			var a := deg_to_rad(float(i))
			var fx := pivot.x - length * sin(a)
			var fy := height - length * cos(a)
			var err := absf(fy * cos(lean) + fx * sin(lean))
			if err < best_err:
				best_err = err
				best = a
		foot = pivot + Vector3(-length * sin(best), -length * cos(best), -0.06)
	else:
		foot = pivot + Vector3(-0.03, -0.04, length * 0.95)
	_tube(pivot, foot, 0.012, mat)
	var pad := _box(foot, Vector3(0.05, 0.012, 0.07), mat)
	pad.name = "StandFoot"
	_box(pivot, Vector3(0.03, 0.04, 0.04), mat)


## The centre stand under the engine: two legs and a foot lever, swung down to lift the
## back wheel off the ground, or folded up behind.
func _draw_centre_stand(build: BikeBuild) -> void:
	_current_slot = "centre_stand"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.6, 0.4)
	var z := _pivot.z - 0.08
	var reach := build.rear_radius - 0.06 + float(p.get("lift", 0.04))
	for side in [-1.0, 1.0]:
		var top := Vector3(0.1 * side, -0.06, z)
		var foot := top + (Vector3(0.02 * side, -reach, -0.02) if stand_pose == "centre" else Vector3(0.0, -0.08, reach * 0.9))
		_tube(top, foot, 0.013, mat)
		_box(foot, Vector3(0.05, 0.012, 0.06), mat)
	var bar_z := z - 0.02 if stand_pose == "centre" else z + reach * 0.9
	var bar_y := -0.06 - reach if stand_pose == "centre" else -0.14
	_tube(Vector3(-0.1, bar_y + 0.04, bar_z), Vector3(0.1, bar_y + 0.04, bar_z), 0.01, mat)
	_tube(Vector3(-0.1, bar_y + 0.04, bar_z), Vector3(-0.2, bar_y + 0.08, bar_z + 0.05), 0.01, mat)


# ---------------------------------------------------------------------------- wheels and brakes

## A rim's width across its bead seats, in metres, from the wheel part's rim width in inches.
static func rim_width_of(wheel: Dictionary) -> float:
	return float(wheel.get("rim_width", 3.5)) * 0.0254


## The rim: a barrel `rim_w` wide between two flanges the tyre's beads sit inside, and the spokes.
func _draw_rim(wheel: Node3D, rim_r: float, rim_w: float) -> void:
	var p := _part()
	var style := str(p.get("style", "cast"))
	var rim_mat := _mat(_col(), 0.9 if style != "carbon" else 0.2, 0.25, 0.8 if style == "carbon" else 0.0)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	# The barrel is open at the sides, so it's drawn from both faces.
	var barrel_mat := rim_mat.duplicate() as StandardMaterial3D
	barrel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrel := _mesh_instance(_cylinder(rim_r - 0.004, rim_w, -1.0, 40), barrel_mat, Vector3.ZERO, wheel)
	(barrel.mesh as CylinderMesh).cap_top = false
	(barrel.mesh as CylinderMesh).cap_bottom = false
	barrel.rotation.z = PI * 0.5
	barrel.set_meta("hoop", Vector3(rim_r - 0.03, rim_r, rim_w))
	for side in [-1.0, 1.0]:
		var flange := TorusMesh.new()
		flange.inner_radius = rim_r - 0.012
		flange.outer_radius = rim_r + 0.009
		flange.rings = 40
		flange.ring_segments = 8
		var f := _mesh_instance(flange, rim_mat, Vector3(side * rim_w * 0.5, 0.0, 0.0), wheel)
		f.rotation.z = PI * 0.5
		f.scale = Vector3(1.0, 0.4, 1.0)
	if style == "spoked" or style == "wire":
		var count := int(p.get("spokes", 36 if style == "wire" else 18))
		for i in count:
			var a := TAU * i / count
			var spoke := _tube(Vector3(0.025 * (1 if i % 2 == 0 else -1), 0.0, 0.0),
				Vector3(0.0, cos(a), sin(a)) * (rim_r - 0.02), 0.003 if style == "spoked" else 0.0022, chrome, Vector3.ONE, wheel)
			spoke.name = "Spoke%d" % i
	else:
		var spokes := int(p.get("spokes", 3 if style == "carbon" else 5))
		# Fewer spokes are chunkier; a "y" wheel splits each spoke in two near the rim.
		var thick := clampf(0.12 / spokes, 0.016, 0.04)
		var depth := clampf(rim_w * 0.45, 0.03, 0.05)
		for i in spokes:
			var a := TAU * i / spokes
			if style == "y":
				_box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.3, Vector3(depth * 0.65, rim_r * 0.55, 0.022), rim_mat, wheel).rotation.x = -a
				for split in [-0.2, 0.2]:
					var b: float = a + split
					var arm := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.55 + Vector3(0.0, cos(b), sin(b)) * rim_r * 0.2,
						Vector3(depth * 0.5, rim_r * 0.45, 0.016), rim_mat, wheel)
					arm.rotation.x = -(a + split * 0.5)
			else:
				var spoke := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.5, Vector3(depth, rim_r * 0.95, thick), rim_mat, wheel)
				spoke.rotation.x = -a
	var hub := _mesh_instance(_cylinder(0.05, 0.14), chrome, Vector3.ZERO, wheel)
	hub.rotation.z = PI * 0.5


## The tyre, drawn to its size: `width` is its section width and its height off the rim
## (radius - rim_r) comes from its profile, so a 180/55 is 180 mm wide and 99 mm tall. Its
## beads sit inside the rim's flanges, `rim_w` apart.
func _draw_tyre(wheel: Node3D, rim_r: float, radius: float, width: float, rim_w: float) -> void:
	var style := str(_part().get("style", "road"))
	var rubber := _mat(_col(), 0.0, 0.92)
	rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tyre_mi := _mesh_instance(tyre_mesh(rim_r, radius, width, rim_w, style), rubber, Vector3.ZERO, wheel)
	tyre_mi.rotation.z = PI * 0.5
	tyre_mi.set_meta("hoop", Vector3(rim_r, radius, width))
	if style != "offroad":
		return
	var knobs := MultiMesh.new()
	knobs.transform_format = MultiMesh.TRANSFORM_3D
	var knob := BoxMesh.new()
	knob.size = Vector3(width * 0.36, 0.022, 0.03)
	knobs.mesh = knob
	knobs.instance_count = 80
	for i in 80:
		var a := TAU * (i / 2) / 40.0 + (PI / 40.0 if i % 2 else 0.0)
		var t := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0.0, cos(a), sin(a)) * (radius - 0.008))
		t = t.translated_local(Vector3((width * 0.19 if i % 2 == 0 else -width * 0.19), 0.0, 0.0))
		knobs.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = knobs
	mmi.material_override = rubber
	wheel.add_child(mmi)
	_slot_meshes[_current_slot].append(mmi)


## A tyre as a solid of revolution round local Y, like a TorusMesh: its cross-section rises
## from the beads (inside the rim flanges, `rim_w` apart) and bulges out to the full section
## `width` low on the sidewall, then rounds over the tread to `radius`. Road and race tyres
## have a round crown to lean on; knobblies and tourers are squarer.
static func tyre_mesh(rim_r: float, radius: float, width: float, rim_w: float, style := "road", segments := 48) -> ArrayMesh:
	var h := maxf(radius - rim_r, 0.02)
	var half := width * 0.5
	var bead := minf(rim_w * 0.5 - 0.004, half * 0.9)
	var bulge_r := rim_r + h * 0.4
	var p := 2.0 if style in ["slick", "road"] else 2.8
	var prof: Array[Vector2] = []    # (radial, axial) from the right-hand bead over the crown
	var n := 6
	for i in n:
		var t := float(i) / n
		prof.append(Vector2(lerpf(rim_r - 0.006, bulge_r, 1.0 - cos(t * PI * 0.5)), lerpf(bead, half, sin(t * PI * 0.5))))
	var m := 10
	for i in m + 1:
		var th := float(i) / m * PI * 0.5
		var c := pow(cos(th), 2.0 / p)
		var sn := pow(sin(th), 2.0 / p)
		prof.append(Vector2(bulge_r + (rim_r + h - bulge_r) * sn, half * c))
	for i in range(prof.size() - 2, -1, -1):
		prof.append(Vector2(prof[i].x, -prof[i].y))
	var normals: Array[Vector2] = []
	for j in prof.size():
		var tangent := prof[mini(j + 1, prof.size() - 1)] - prof[maxi(j - 1, 0)]
		normals.append(Vector2(-tangent.y, tangent.x).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments + 1:
		var a := TAU * i / segments
		var ca := cos(a)
		var sa := sin(a)
		for j in prof.size():
			st.set_uv(Vector2(float(i) / segments, float(j) / (prof.size() - 1)))
			st.set_normal(Vector3(ca * normals[j].x, normals[j].y, sa * normals[j].x))
			st.add_vertex(Vector3(ca * prof[j].x, prof[j].y, sa * prof[j].x))
	var rows := prof.size()
	for i in segments:
		for j in rows - 1:
			var a0 := i * rows + j
			var b0 := (i + 1) * rows + j
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	return st.commit()


func _draw_brake(side: String, wheel: Node3D, hub: Node3D, rim_r: float, rim_w := 0.09) -> void:
	var front := side == "front"
	# The disc bolts on just outside the rim.
	var x := maxf(0.068 if front else 0.07, rim_w * 0.5 + 0.012)
	_current_slot = side + "_disc"
	var disc := _part()
	var disc_r := minf(float(disc.get("diameter", 280)) / 2000.0, rim_r - 0.03)
	var steel := _mat(_col(), 1.0, 0.3)
	var style := str(disc.get("style", "round"))
	var d := _mesh_instance(_cylinder(disc_r, 0.006, -1.0, 10 if style == "wave" else 32), steel, Vector3(x, 0.0, 0.0), wheel)
	d.rotation.z = PI * 0.5
	if style == "floating":
		var carrier := _mesh_instance(_cylinder(disc_r * 0.62, 0.008), _mat(Color(0.8, 0.62, 0.2), 0.9, 0.3), Vector3(x + 0.002, 0.0, 0.0), wheel)
		carrier.rotation.z = PI * 0.5
	elif style == "drilled":
		var ring := _mesh_instance(_cylinder(disc_r * 0.55, 0.008), _mat(Color(0.2, 0.2, 0.22), 0.8, 0.4), Vector3(x + 0.002, 0.0, 0.0), wheel)
		ring.rotation.z = PI * 0.5
	_current_slot = side + "_caliper"
	var pistons := int(_part().get("pistons", 2))
	var cal_size := Vector3(0.045, 0.06 + 0.008 * pistons, 0.07 + 0.01 * pistons)
	var cal_at := Vector3(x + 0.012, disc_r * 0.62, disc_r * 0.62 if front else -disc_r * 0.62)
	var cal := _box(cal_at, cal_size, _mat(_col(), 0.5, 0.35), hub)
	cal.rotation.x = -PI * 0.25 if front else PI * 0.25
	_current_slot = side + "_pads"
	var pad := _box(cal_at + Vector3(0.0, 0.0, 0.0) + cal.basis.y * (cal_size.y * 0.5 + 0.012), Vector3(0.035, 0.024, 0.05), _mat(_col(), 0.4, 0.6), hub)
	pad.basis = cal.basis


func _draw_final_drive(zr: float) -> void:
	_current_slot = "final_drive"
	var fd := _part()
	var front_r := 0.0045 * float(fd.get("front", 15))
	var rear_r := 0.0042 * float(fd.get("rear", 45))
	var sprocket_mat := _mat(_col(), 0.9, 0.35)
	var front_sp := _mesh_instance(_cylinder(front_r, 0.012), sprocket_mat, Vector3(-0.13, 0.0, 0.0), _swingarm)
	front_sp.rotation.z = PI * 0.5
	var rear_sp := _mesh_instance(_cylinder(rear_r, 0.008), sprocket_mat, Vector3(-0.12, 0.0, 0.0), _rear_wheel)
	rear_sp.rotation.z = PI * 0.5
	_current_slot = "chain"
	if _part_id() == "" or _part_id() == "none":
		return
	# The bottom run sags with the chain's slack; a dry chain goes rusty brown.
	var lube := float(condition.get("chain", {}).get("lube", 1.0))
	var slack := float(condition.get("chain", {}).get("slack", 30.0))
	var chain_mat := _mat(_col().lerp(Color(0.4, 0.22, 0.1), clampf(0.7 - lube, 0.0, 0.7)), 0.8, lerpf(0.75, 0.4, lube))
	var mid_r := lerpf(front_r, rear_r, 0.5)
	_box(Vector3(-0.125, mid_r, _arm_len * 0.5), Vector3(0.012, 0.012, _arm_len), chain_mat, _swingarm)
	var sag := clampf((slack - 20.0) / 1000.0, 0.0, 0.07)
	var a := Vector3(-0.125, -front_r, 0.0)
	var b := Vector3(-0.125, -rear_r, _arm_len)
	var low := (a + b) * 0.5 + Vector3(0.0, -sag, 0.0)
	_tube(a, low, 0.006, chain_mat, Vector3.ONE, _swingarm)
	_tube(low, b, 0.006, chain_mat, Vector3.ONE, _swingarm)


func _draw_shock() -> void:
	_current_slot = "shock"
	var shock := _part()
	var col := _col()
	var chrome := _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2)
	_struts.clear()
	if shock.get("layout", "mono") == "twin":
		var gas: bool = _part_id() == "twin_shock_gas"
		var spring_mat := _mat(col, 0.6, 0.3)
		for side in [-1.0, 1.0]:
			# Each shock runs from the swingarm up to the frame, and works as the arm swings.
			var top := _pivot + Vector3(0.12 * side, 0.3, _arm_len - 0.2)
			var bottom := Vector3(0.12 * side, 0.02, _arm_len - 0.08)
			_strut(top, bottom, 0.012, chrome)
			_strut(top + (_pivot + bottom - top) * 0.08, bottom + (top - _pivot - bottom) * 0.25, 0.028, spring_mat)
			if gas:
				_tube(Vector3(0.155 * side, 0.22, _arm_len - 0.17), Vector3(0.155 * side, 0.32, _arm_len - 0.21), 0.016, chrome, Vector3.ONE, _swingarm)
	else:
		var top := Vector3(0.0, _seat_y - 0.14, _pivot.z + 0.02)
		var bottom := Vector3(0.0, 0.07, 0.14)
		_strut(top, bottom, 0.016, chrome)
		_strut(top + (_pivot + bottom - top) * 0.1, bottom + (top - _pivot - bottom) * 0.3, 0.038, _mat(col, 0.3, 0.4))


## A shock absorber part between a point on the frame (`top`, model space) and one on the
## swingarm (`bottom`, in the arm's space), stretched to fit as the arm moves.
func _strut(top: Vector3, bottom: Vector3, radius: float, mat: Material) -> void:
	var low := _pivot + bottom
	var mi := _tube(top, low, radius, mat)
	_struts.append({"mi": mi, "top": top, "bottom": bottom, "rest": top.distance_to(low)})


func _update_struts() -> void:
	for s in _struts:
		var mi: MeshInstance3D = s["mi"]
		if not is_instance_valid(mi):
			continue
		var top: Vector3 = s["top"]
		var low: Vector3 = _swingarm.transform * (s["bottom"] as Vector3)
		var dir := low - top
		var length := dir.length()
		mi.position = (top + low) * 0.5
		mi.basis = _basis_up(dir / maxf(length, 0.001)) * Basis.from_scale(Vector3(1.0, length / float(s["rest"]), 1.0))


func _build_rider() -> void:
	_rider = Node3D.new()
	add_child(_rider)
	if rider_color.a > 0.0 or not rider_gear.is_empty():
		_build_dressed_rider()
		return
	var seat_y := _seat_y
	# The rider wears their own colours, the same as on foot: overalls in a darker shade, lid in the colour.
	var mine := rider_color.a > 0.0
	var suit := _mat(rider_color.darkened(0.35) if mine else jacket, 0.0, 0.55)
	var pants := _mat(Color(0.06, 0.06, 0.07), 0.0, 0.7)
	var helmet := _mat(rider_color if mine else paint.lightened(0.15), 0.4, 0.15)
	var visor := _mat(Color(0.02, 0.02, 0.03), 0.9, 0.05)
	var gloves := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.6)
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	var torso := _tube(hips, shoulders, 0.15, suit, Vector3(1.25, 1.0, 0.8), _rider)
	var lid := _mesh_instance(_sphere(0.15), helmet, shoulders + Vector3(0.0, 0.2, -0.08), _rider)
	var v := _mesh_instance(_sphere(0.1), visor, shoulders + Vector3(0.0, 0.2, -0.17), _rider)
	v.scale = Vector3(1.1, 0.6, 0.5)
	var grip_l := _head + _grip_l
	var grip_r := _head + _grip_r
	# The first-person eye is the rider's own, inside the helmet, looking down the road over the
	# bars; the torso, helmet and upper arms, which would be in the way, are hidden from it.
	for mi in [torso, lid, v]:
		(mi as GeometryInstance3D).layers = 1 << (HELMET_LAYER - 1)
	_eye = shoulders + Vector3(0.0, 0.28, 0.28)
	for side in [-1.0, 1.0]:
		var sh := shoulders + Vector3(0.19 * side, -0.04, 0.0)
		var grip := grip_r if side > 0 else grip_l
		var elbow := sh.lerp(grip, 0.5) + Vector3(0.08 * side, -0.06, 0.04)
		var upper := _tube(sh, elbow, 0.05, suit, Vector3.ONE, _rider)
		upper.layers = 1 << (HELMET_LAYER - 1)
		_tube(elbow, grip, 0.045, suit, Vector3.ONE, _rider)
		_mesh_instance(_sphere(0.045), gloves, grip, _rider)
		var hip := hips + Vector3(0.12 * side, -0.02, 0.0)
		var knee := Vector3(0.19 * side, seat_y - 0.02, hips.z - 0.36)
		var peg := Vector3(0.17 * side, 0.02, _pivot.z + 0.02)
		_tube(hip, knee, 0.075, pants, Vector3.ONE, _rider)
		_tube(knee, peg, 0.06, pants, Vector3.ONE, _rider)
		_box(peg + Vector3(0.0, -0.02, -0.06), Vector3(0.09, 0.08, 0.22), gloves, _rider)


## The rider in their own gear (see RiderGear and RiderFigure), sat the same way as the plain
## one in _build_rider: helmet, jacket on the torso and arms, gloves on the grips, trousers on the
## legs and boots on the pegs.
func _build_dressed_rider() -> void:
	var worn := RiderGear.clean_worn(rider_gear)
	var tint := rider_color if rider_color.a > 0.0 else paint.lightened(0.15)
	var jacket := str(worn["jacket"])
	var trousers := str(worn["trousers"])
	var jm := RiderFigure.material(jacket, tint)
	var tm := RiderFigure.material(trousers, tint)
	var jx: Array = RiderGear.get_item(jacket).get("extras", [])
	var tx: Array = RiderGear.get_item(trousers).get("extras", [])
	var hidden := 1 << (HELMET_LAYER - 1)   # kept out of the first-person eye, as in _build_rider
	var seat_y := _seat_y
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	var torso := RiderFigure.limb(_rider, hips, shoulders, 0.15, jm, hidden)
	torso.basis = torso.basis * Basis.from_scale(Vector3(1.25, 1.0, 0.8))
	RiderFigure.helmet(_rider, shoulders + Vector3(0.0, 0.2, -0.08), 0.15, str(worn["helmet"]), tint, hidden, true)
	var back := (shoulders - hips).normalized().cross(Vector3.RIGHT)
	if jx.has("hump"):
		var hump := RiderFigure.mesh(_rider, RiderFigure.sphere(0.5), jm, shoulders.lerp(hips, 0.15) - back * 0.13, hidden)
		hump.scale = Vector3(0.24, 0.18, 0.14)
	if jx.has("collar"):
		RiderFigure.tube(_rider, shoulders + Vector3(0.0, 0.04, -0.02), shoulders + Vector3(0.0, 0.09, -0.04), 0.08,
			RiderFigure.material(jacket, tint, "trim"), hidden)
	_eye = shoulders + Vector3(0.0, 0.28, 0.28)
	var grip_l := _head + _grip_l
	var grip_r := _head + _grip_r
	for side in [-1.0, 1.0]:
		var sh := shoulders + Vector3(0.19 * side, -0.04, 0.0)
		var grip := grip_r if side > 0 else grip_l
		var elbow := sh.lerp(grip, 0.5) + Vector3(0.08 * side, -0.06, 0.04)
		RiderFigure.limb(_rider, sh, elbow, 0.05, jm, hidden)
		RiderFigure.limb(_rider, elbow, grip, 0.045, jm)
		RiderFigure.glove(_rider, grip, elbow, 0.045, str(worn["gloves"]), tint)
		var hip := hips + Vector3(0.12 * side, -0.02, 0.0)
		var knee := Vector3(0.19 * side, seat_y - 0.02, hips.z - 0.36)
		var peg := Vector3(0.17 * side, 0.02, _pivot.z + 0.02)
		RiderFigure.limb(_rider, hip, knee, 0.075, tm)
		RiderFigure.limb(_rider, knee, peg, 0.06, tm)
		if tx.has("knees"):
			RiderFigure.knee_guard(_rider, knee, hip, peg, 0.065, trousers, tint)
		RiderFigure.boot(_rider, peg + Vector3(0.0, -0.06, 0.0), knee, Vector3.FORWARD, str(worn["boots"]), tint)


## Dresses the rider again in `gear` (when its rider changes their gear mid-ride).
func redress(gear: Dictionary) -> void:
	rider_gear = gear
	if _rider == null:
		return
	var xf := _rider.transform
	var shown := _rider.visible
	_rider.free()
	_build_rider()
	_rider.transform = xf
	_rider.visible = shown


## A basis whose Y axis points along `up`.
func _basis_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))


## Moves wheels, suspension, steering and rider to match the simulation.
func update_pose(bike: Bike) -> void:
	update_pose_from(bike.steer, bike.wheels[0]["spin"], bike.wheels[1]["spin"],
		bike.wheels[0]["compression"], bike.wheels[1]["compression"], bike.body_shift, bike.lean_input)


func update_pose_from(steer: float, spin_f: float, spin_r: float, comp_f: float, comp_r: float,
		body_shift: float, lean_in: float) -> void:
	if _build == null:
		return
	var wb := _build.wheelbase
	_steer_node.basis = Basis(_steer_axis, -steer)
	var front_axle := Vector3(0.0, comp_f, -wb * 0.5)
	_front_hub.position = _steer_node.transform.affine_inverse() * front_axle
	_front_wheel.rotation.x = -spin_f
	var rear_axle := Vector3(0.0, comp_r, wb * 0.5)
	_rear_hub.position = rear_axle
	_rear_wheel.rotation.x = -spin_r
	var to_axle := rear_axle - _pivot
	_swingarm.rotation.x = -atan2(to_axle.y, to_axle.z)
	_update_struts()
	if _rider:
		_rider.position = Vector3(lean_in * 0.05, 0.0, -body_shift * 0.1)
		_rider.rotation = Vector3(-body_shift * 0.12, 0.0, -lean_in * 0.12)
	if not geometry.is_empty():
		_update_geometry()


## Where the rider's eyes are, looking down over the bars at the clocks, in the model's space.
func eye_transform() -> Transform3D:
	var at := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-21.0)), _eye)
	return (_rider.transform * at) if _rider else at


func exhaust_tip() -> Vector3:
	return _exhaust_tip


func lamp_position() -> Vector3:
	return _head + Vector3(0.0, -0.08, -0.13)


## Road muck over the whole bike while it's ridden, 0 (none) .. 1 (plastered).
func set_grime(level: float) -> void:
	if level < 0.02:
		if _grime:
			for slot in _slot_meshes:
				for mi in _slot_meshes[slot]:
					(mi as GeometryInstance3D).material_overlay = null
			_grime = null
		return
	if _grime == null:
		_grime = StandardMaterial3D.new()
		_grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grime.albedo_color = Color(0.3, 0.22, 0.13, 0.0)
		_grime.albedo_texture = _splatter()
		_grime.uv1_triplanar = true
		_grime.uv1_scale = Vector3(4.0, 4.0, 4.0)
		_grime.roughness = 1.0
		for slot in _slot_meshes:
			for mi in _slot_meshes[slot]:
				(mi as GeometryInstance3D).material_overlay = _grime
	_grime.albedo_color.a = clampf(level, 0.0, 0.9)


static var _splatter_tex: NoiseTexture2D


## Blotchy alpha for mud: big clumps with gaps between.
static func _splatter() -> NoiseTexture2D:
	if _splatter_tex:
		return _splatter_tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 1.0))
	ramp.add_point(0.45, Color(1, 1, 1, 0.0))
	ramp.add_point(0.6, Color(1, 1, 1, 0.9))
	_splatter_tex = NoiseTexture2D.new()
	_splatter_tex.width = 256
	_splatter_tex.height = 256
	_splatter_tex.seamless = true
	_splatter_tex.noise = noise
	_splatter_tex.color_ramp = ramp
	return _splatter_tex


## A readout on the clocks for the rider: speed, gear and fuel, printed on the screen (or under
## the needle on dial clocks). Only the ridden bike has one.
func dash_readout() -> Label3D:
	if _dash_label == null:
		_dash_label = Label3D.new()
		var dials := not _needles.is_empty()
		_dash_label.font_size = 28 if dials else 40
		_dash_label.pixel_size = 0.0004
		_dash_label.outline_size = 0
		_dash_label.modulate = Color(0.1, 0.1, 0.1) if dials else Color(0.75, 1.0, 0.85)
		# Label3D faces +Z; lay it flat on the face, which looks along the tilted Y.
		_dash_label.transform = Transform3D(_dash_screen.basis * Basis(Vector3.RIGHT, -PI * 0.5), _dash_screen.origin)
		_dash_label.line_spacing = -4.0
		_dash_label.shaded = false
		_dash_label.double_sided = false
		# With the clocks moved in geometry mode, the readout goes with them.
		var host: Node3D = _steer_node
		for e in _geo_nodes.get("dashboard", []):
			if e["parent"] == _steer_node:
				host = e["node"]
		host.add_child(_dash_label)
	return _dash_label


func has_dials() -> bool:
	return not _needles.is_empty()


func set_rider_visible(v: bool) -> void:
	if _rider:
		_rider.visible = v


func is_fitted(slot: String) -> bool:
	return present.is_empty() or bool(present.get(slot, false))


func _apply_visibility() -> void:
	for slot in _slot_meshes:
		for mi in _slot_meshes[slot]:
			mi.visible = is_fitted(slot)


## Draws a glow over one part (or none with "").
func highlight(slot: String) -> void:
	if slot == _highlighted:
		return
	if _highlight_mat == null:
		_highlight_mat = StandardMaterial3D.new()
		_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.3)
		_highlight_mat.grow = true
		_highlight_mat.grow_amount = 0.004
	for s in _slot_meshes:
		for mi in _slot_meshes[s]:
			(mi as GeometryInstance3D).material_overlay = _highlight_mat if s == slot else null
	_highlighted = slot


# ---------------------------------------------------------------------------- geometry (per-bike fit)

## Moves, turns and sizes each part by this bike's own fit (see `geometry`). The first time,
## every slot's meshes are hung from a node of their own under whatever they were drawn on
## (the frame, the steering, a hub, a wheel, the swingarm), so this works for any slot, new
## ones included. Wheels and needles still spin under their offset rather than wobbling.
func apply_geometry(geo: Dictionary) -> void:
	geometry = geo
	if _build == null:
		return
	if _geo_pivots.is_empty():
		if geo.is_empty():
			return
		_wrap_slots()
	_update_geometry()


## The middle of a part as it was drawn, before its fit, in this model's space.
func geo_pivot(slot: String) -> Vector3:
	if _geo_pivots.has(slot):
		return _geo_pivots[slot]
	return slot_bounds(slot).get_center()


## Where a part's middle is now and how it's turned, in this model's space (for the gizmo).
func geo_xform(slot: String) -> Transform3D:
	var off := GeoGizmo.offset_of(geometry, slot)
	return Transform3D(GeoGizmo.rotation_of(off), geo_pivot(slot) + (off["p"] as Vector3))


func _wrap_slots() -> void:
	var anchors: Array = [self]
	for n in [_steer_node, _front_hub, _rear_hub, _swingarm]:
		if n != null and is_instance_valid(n):
			anchors.append(n)
	for a in anchors:
		_geo_anchors[a] = Transform3D.IDENTITY if a == self else _local_xform(a)
	for slot in _slot_meshes:
		var meshes: Array = _slot_meshes[slot].filter(func(m): return is_instance_valid(m))
		if meshes.is_empty():
			continue
		_geo_pivots[slot] = slot_bounds(slot).get_center()
		var by_parent := {}
		var nodes := []
		for mi in meshes:
			var parent: Node = (mi as Node).get_parent()
			if parent == null:
				continue
			if not by_parent.has(parent):
				var g := Node3D.new()
				g.name = "Geo_" + slot
				parent.add_child(g)
				by_parent[parent] = g
				var anchor: Node = parent
				while anchor != null and not _geo_anchors.has(anchor):
					anchor = anchor.get_parent()
				nodes.append({"node": g, "parent": parent, "anchor": anchor if anchor != null else self})
			(mi as Node).reparent(by_parent[parent], false)
		_geo_nodes[slot] = nodes


## Sets every slot node from `geometry`: the offset is in model space at rest, carried into
## the frame of what it rides on (so moved bars still steer) and undone through anything that
## spins between (so a moved wheel still turns about its own middle).
func _update_geometry() -> void:
	for slot in _geo_nodes:
		var o := GeoGizmo.offset_xform(geometry.get(slot, {}), _geo_pivots[slot])
		for e in _geo_nodes[slot]:
			var g: Node3D = e["node"]
			if not is_instance_valid(g):
				continue
			var a0: Transform3D = _geo_anchors.get(e["anchor"], Transform3D.IDENTITY)
			var oa := a0.affine_inverse() * o * a0
			var q := Transform3D.IDENTITY
			var n: Node = e["parent"]
			while n != null and n != e["anchor"] and n is Node3D:
				q = (n as Node3D).transform * q
				n = n.get_parent()
			g.transform = q.affine_inverse() * oa * q


## Turns the whole model into a see-through glowing hologram (for blueprint builds).
func make_ghost(mat: Material) -> void:
	for slot in _slot_meshes:
		for mi in _slot_meshes[slot]:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).material_override = mat
				(mi as GeometryInstance3D).material_overlay = null
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _dash_label:
		_dash_label.visible = false


## Local-space bounding box of a part's meshes.
func slot_bounds(slot: String) -> AABB:
	var box := AABB()
	var first := true
	for mi in _slot_meshes.get(slot, []):
		var aabb: AABB = _local_xform(mi) * (mi as VisualInstance3D).get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	return box


## Points spread evenly over a part's surfaces, about `cell` apart, in this model's space, with
## the outward surface normal at each: [points, normals]. For the sandblaster's coverage map.
func surface_points(slot: String, cell: float) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot)
	for mi in _slot_meshes.get(slot, []):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null or not is_instance_valid(mi):
			continue
		var xf := _local_xform(mi)
		var faces := (mi as MeshInstance3D).mesh.get_faces()
		for f in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[f]
			var b: Vector3 = xf * faces[f + 1]
			var c: Vector3 = xf * faces[f + 2]
			# Godot's front faces wind clockwise, so this cross product points out of the surface.
			var n := (c - a).cross(b - a)
			var area := n.length() * 0.5
			if area < 1e-7:
				continue
			n = n.normalized()
			var count := ceili(area / (cell * cell) * 1.5)
			for k in count:
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := a + (b - a) * u + (c - a) * v
				var key := Vector3i((p / cell).floor())
				if seen.has(key):
					continue
				seen[key] = true
				points.append(p)
				normals.append(n)
	return [points, normals]


## Adds a static click target per fitted part, with box shapes fitted to its meshes.
## Each body carries metadata "slot", plus everything in `meta`; `slot_meta` replaces `meta`
## for particular slots. Rings (tyres, spoked rims) get a hoop of boxes so the ray can still
## reach the disc and caliper inside them.
func build_pickers(meta: Dictionary, slot_meta := {}, layer := PICK_LAYER) -> void:
	clear_pickers()
	for slot in _slot_meshes:
		if not is_fitted(slot) or _slot_meshes[slot].is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "Pick_" + slot
		body.collision_layer = layer
		body.collision_mask = 0
		body.set_meta("slot", slot)
		var m: Dictionary = slot_meta.get(slot, meta)
		for key in m:
			body.set_meta(key, m[key])
		for mi in _slot_meshes[slot]:
			if mi is MultiMeshInstance3D or str(mi.name).begins_with("Spoke"):
				continue
			var xf := _local_xform(mi)
			if mi.has_meta("hoop"):
				# A ring (the tyre, a rim barrel): boxes round it, with the middle left open.
				var hoop: Vector3 = mi.get_meta("hoop")
				var mid_r := (hoop.x + hoop.y) * 0.5
				var deep := hoop.y - hoop.x
				for i in 16:
					var a := TAU * i / 16.0
					var piece := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.0, sin(a)) * mid_r)
					_add_box(body, xf * piece, Vector3(deep, hoop.z, TAU * mid_r / 16.0))
				continue
			if (mi as MeshInstance3D).mesh is TorusMesh:
				var torus: TorusMesh = mi.mesh
				var mid := (torus.inner_radius + torus.outer_radius) * 0.5
				var depth := torus.outer_radius - torus.inner_radius
				for i in 12:
					var a := TAU * i / 12.0
					var piece := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.0, sin(a)) * mid)
					_add_box(body, xf * piece, Vector3(depth, depth, TAU * mid / 12.0))
				continue
			var aabb: AABB = (mi as VisualInstance3D).get_aabb()
			var size := aabb.size
			if slot == "chain":
				# A chain is thin; make it easy to aim at from the side, standing out past the frame.
				size = size.max(Vector3(0.14, 0.07, 0.07))
			_add_box(body, xf * Transform3D(Basis(), aabb.get_center() + (Vector3(-0.06, 0.0, 0.0) if slot == "chain" else Vector3.ZERO)), size)
		add_child(body)


func _add_box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = (size * xf.basis.get_scale()).max(Vector3(0.03, 0.03, 0.03))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.add_child(cs)


## Frees every mesh that isn't part of `keep`, for showing loose parts on their own.
func strip_to(keep: Array) -> void:
	for s in _slot_meshes:
		if keep.has(s):
			continue
		for mi in _slot_meshes[s]:
			mi.free()
		_slot_meshes[s] = []


## Loose parts on their own, sitting with their base on the origin. `parts` maps slot ->
## part id for each part to show; `cond` maps slot -> condition. The node's "size" meta is
## the bounding size and its "model" meta is the BikeModel inside.
static func assembly_display(parts: Dictionary, cond: Dictionary, unseen := {}) -> Node3D:
	var build := PartsDB.DEFAULT_BUILD.duplicate()
	build.merge(unseen, true)
	var fitted := {}
	for slot in parts:
		build[slot] = parts[slot]
		fitted[slot] = true
	var model := BikeModel.new()
	model.build_from(BikeBuild.new(build, cond), Color(0.55, 0.56, 0.58), fitted, cond, false)
	model.strip_to(parts.keys())
	var bounds := AABB()
	var first := true
	for slot in parts:
		var b := model.slot_bounds(slot)
		if b.size == Vector3.ZERO:
			continue
		bounds = b if first else bounds.merge(b)
		first = false
	var root := Node3D.new()
	root.add_child(model)
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	root.set_meta("size", bounds.size)
	root.set_meta("model", model)
	return root


## One loose part from the catalogue.
static func part_display(part_id: String, cond: Dictionary) -> Node3D:
	if PartsDB.is_fluid(part_id):
		return fluid_display(part_id, 0.0 if PartsDB.get_part(part_id).get("empty", false) else 1.0)
	var slot: String = PartsDB.slots_for_kind(PartsDB.kind_of(part_id))[0]
	if slot == "front_tyre":
		# A loose tyre keeps the size it is on a wheel it's made for (`unseen` sizes it, and isn't drawn).
		var fits: Array = PartsDB.wheels_for(part_id)
		if not fits.is_empty():
			return assembly_display({slot: part_id}, {slot: cond}, {"front_wheel": fits[0]})
	return assembly_display({slot: part_id}, {slot: cond})


## A loose item from the shed, drawn with whatever is fitted to it (an engine with its head,
## carbs and so on).
static func item_display(item_id: int) -> Node3D:
	var it: Dictionary = Shed.items[item_id]
	if it.get("boxed", false):
		return box_display(str(it["part"]), item_id)
	if PartsDB.is_fluid(str(it["part"])):
		var f: Dictionary = it.get("fluid", {})
		return fluid_display(str(it["part"]), float(f.get("litres", 0.0)) / maxf(PartsDB.fluid_capacity(str(it["part"])), 0.01))
	if Shed.is_engine(item_id):
		var asm := Shed.engine_assembly(item_id)
		var shown := {}
		for slot in asm["fitted"]:
			if asm["fitted"][slot]:
				shown[slot] = asm["parts"][slot]
		return assembly_display(shown, asm["cond"])
	var tyre := Shed.tyre_on_wheel(item_id)
	if tyre != 0:
		# A wheel off the bike with its tyre still on.
		return assembly_display({"front_wheel": it["part"], "front_tyre": Shed.items[tyre]["part"]},
			{"front_wheel": Shed.condition_of(it), "front_tyre": Shed.condition_of(Shed.items[tyre])})
	return part_display(it["part"], Shed.condition_of(it))


## A can, bottle or pan of fluid, sitting on its base. `full` 0..1 shows how much is in it
## where you can see in (the drain pan and the bleed bottle).
static func fluid_display(part_id: String, full: float) -> Node3D:
	var p := PartsDB.get_part(part_id)
	var c: Array = p.get("color", [0.5, 0.5, 0.5])
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(c[0], c[1], c[2])
	body.roughness = 0.45
	body.metallic = 0.3 if PartsDB.kind_of(part_id) == "petrol" else 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	dark.roughness = 0.6
	var l: Array = p.get("liquid", [0.5, 0.4, 0.2])
	var liquid := StandardMaterial3D.new()
	liquid.albedo_color = Color(l[0], l[1], l[2])
	liquid.roughness = 0.1
	liquid.metallic = 0.2
	# Containers are translucent plastic (or have a sight strip), so you can see how much is left.
	var see := body.duplicate() as StandardMaterial3D
	see.albedo_color.a = 0.42
	see.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	see.metallic = 0.0
	see.roughness = 0.25
	see.cull_mode = BaseMaterial3D.CULL_DISABLED
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(0.9, 0.92, 0.95, 0.3)
	strip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	strip.roughness = 0.05
	var level := clampf(full, 0.0, 1.0)
	var root := Node3D.new()
	var size := Vector3.ONE * 0.2
	var pieces := []   # [mesh, material, position]
	match str(p.get("container", "")):
		"Jerry can":
			var big := float(p["litres"]) > 6.0
			size = Vector3(0.14 if big else 0.11, 0.38 if big else 0.3, 0.3 if big else 0.24)
			pieces = [[_box_mesh(size), see, Vector3(0.0, size.y * 0.5, 0.0)],
				[_box_mesh(Vector3(0.03, 0.04, size.z * 0.6)), body, Vector3(0.0, size.y + 0.02, 0.0)],
				[_cyl_mesh(0.022, 0.05), dark, Vector3(0.0, size.y + 0.01, size.z * 0.38)]]
			if level > 0.01:
				var inner := size - Vector3(0.012, 0.012, 0.012)
				pieces.append([_box_mesh(Vector3(inner.x, inner.y * level, inner.z)), liquid, Vector3(0.0, 0.006 + inner.y * level * 0.5, 0.0)])
		"Aerosol":
			# A spray can of chain lube with a red straw nozzle and a clear level strip down the side.
			size = Vector3(0.066, 0.22, 0.066)
			var straw := StandardMaterial3D.new()
			straw.albedo_color = Color(0.8, 0.1, 0.08)
			pieces = [[_cyl_mesh(0.033, 0.19), body, Vector3(0.0, 0.095, 0.0)],
				[_cyl_mesh(0.026, 0.03, 0.033), dark, Vector3(0.0, 0.205, 0.0)],
				[_box_mesh(Vector3(0.004, 0.004, 0.09)), straw, Vector3(0.0, 0.215, -0.05)],
				[_box_mesh(Vector3(0.014, 0.16, 0.004)), strip, Vector3(0.0, 0.095, 0.0335)]]
			if level > 0.01:
				pieces.append([_box_mesh(Vector3(0.01, 0.155 * level, 0.004)), liquid, Vector3(0.0, 0.018 + 0.0775 * level, 0.034)])
		"Race fuel drum":
			size = Vector3(0.2, 0.3, 0.2)
			pieces = [[_cyl_mesh(0.1, 0.3), see, Vector3(0.0, 0.15, 0.0)], [_cyl_mesh(0.02, 0.03), dark, Vector3(0.05, 0.315, 0.0)]]
			if level > 0.01:
				pieces.append([_cyl_mesh(0.094, 0.29 * level), liquid, Vector3(0.0, 0.005 + 0.145 * level, 0.0)])
		"Oil bottle":
			size = Vector3(0.11, 0.3, 0.17)
			pieces = [[_box_mesh(Vector3(0.11, 0.26, 0.17)), see, Vector3(0.0, 0.13, 0.0)],
				[_cyl_mesh(0.025, 0.04), dark, Vector3(0.0, 0.28, -0.04)],
				[_box_mesh(Vector3(0.112, 0.08, 0.1)), dark, Vector3(0.0, 0.12, 0.02)]]
			if level > 0.01:
				pieces.append([_box_mesh(Vector3(0.1, 0.25 * level, 0.16)), liquid, Vector3(0.0, 0.005 + 0.125 * level, 0.0)])
		"Drain pan":
			size = Vector3(0.46, 0.08, 0.46)
			pieces = [[_cyl_mesh(0.23, 0.08, 0.2), body, Vector3(0.0, 0.04, 0.0)]]
			if full > 0.01:
				pieces.append([_cyl_mesh(0.2, 0.006), liquid, Vector3(0.0, 0.01 + 0.06 * full, 0.0)])
		"Bleed bottle":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.85, 0.9, 0.95, 0.35)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			size = Vector3(0.09, 0.2, 0.09)
			pieces = [[_cyl_mesh(0.045, 0.16), glass, Vector3(0.0, 0.08, 0.0)], [_cyl_mesh(0.004, 0.25), dark, Vector3(0.0, 0.2, 0.0)]]
			if full > 0.01:
				pieces.append([_cyl_mesh(0.04, 0.15 * full), liquid, Vector3(0.0, 0.075 * full, 0.0)])
		_:
			size = Vector3(0.08, 0.17, 0.08)
			pieces = [[_cyl_mesh(0.04, 0.14), see, Vector3(0.0, 0.07, 0.0)], [_cyl_mesh(0.022, 0.03), dark, Vector3(0.0, 0.155, 0.0)]]
			if level > 0.01:
				pieces.append([_cyl_mesh(0.036, 0.134 * level), liquid, Vector3(0.0, 0.003 + 0.067 * level, 0.0)])
	for piece in pieces:
		var mi := MeshInstance3D.new()
		mi.mesh = piece[0]
		mi.material_override = piece[1]
		mi.position = piece[2]
		root.add_child(mi)
	root.set_meta("size", size)
	return root


static func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl_mesh(radius: float, height: float, top := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = 24
	return m


## Made-up delivery firms whose shipping labels go on the boxes (no real companies): name, the
## colour of their band, the ink on it and the little mark beside the name.
const COURIERS := [
	{"name": "HEDGEHOG PARCELS", "bg": Color(0.98, 0.78, 0.12), "ink": Color(0.12, 0.1, 0.08), "mark": "disc"},
	{"name": "RAPID ROOSTER", "bg": Color(0.82, 0.12, 0.1), "ink": Color(1.0, 0.95, 0.85), "mark": "chevron"},
	{"name": "SPANNER EXPRESS", "bg": Color(0.12, 0.3, 0.72), "ink": Color(1.0, 1.0, 1.0), "mark": "stripes"},
	{"name": "KWIKKRATE", "bg": Color(0.1, 0.55, 0.3), "ink": Color(1.0, 1.0, 1.0), "mark": "diamond"},
	{"name": "OTTERPOST", "bg": Color(0.42, 0.2, 0.62), "ink": Color(1.0, 0.9, 0.3), "mark": "disc"},
	{"name": "MUDGUARD MAIL", "bg": Color(0.2, 0.2, 0.22), "ink": Color(0.98, 0.6, 0.1), "mark": "stripes"},
	{"name": "PISTON PARCEL CO", "bg": Color(0.95, 0.45, 0.08), "ink": Color(0.1, 0.1, 0.1), "mark": "diamond"},
	{"name": "BOLT & BARREL", "bg": Color(0.0, 0.55, 0.6), "ink": Color(1.0, 1.0, 1.0), "mark": "chevron"},
]
static var _sticker_mats := {}    # colour -> material for shipping labels


## Which delivery firm brought a box: an index into COURIERS, always the same for one box.
static func courier_for(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("courier:%d" % seed_value)
	return rng.randi_range(0, COURIERS.size() - 1)


## The tracking number printed on a box's label, from the same seed.
static func tracking_for(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tracking:%d" % seed_value)
	return "TS %03d %04d %03d" % [rng.randi_range(0, 999), rng.randi_range(0, 9999), rng.randi_range(0, 999)]


## The size a loose part is drawn at (width, height, depth), as it sits on a bench.
static func part_size(part_id: String) -> Vector3:
	if not _part_sizes.has(part_id):
		var probe := part_display(part_id, {})
		_part_sizes[part_id] = probe.get_meta("size", Vector3.ONE * 0.3)
		probe.free()
	return _part_sizes[part_id]


## The size of the cardboard box a part comes in.
static func box_size(part_id: String) -> Vector3:
	return part_size(part_id).max(Vector3(0.15, 0.1, 0.15)) + Vector3(0.06, 0.05, 0.06)


## How much room a part takes up where it's put down (width, height, depth): its box if it's
## still boxed. Used to fit parts onto benches, washers and repair machines.
static func footprint(part_id: String, boxed := false) -> Vector3:
	if boxed:
		return box_size(part_id)
	return part_size(part_id)


static func _sticker_mat(c: Color) -> StandardMaterial3D:
	if not _sticker_mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.65
		_sticker_mats[c] = m
	return _sticker_mats[c]


static func _quad(parent: Node3D, size: Vector2, at: Vector3, c: Color, roll := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = _sticker_mat(c)
	mi.position = at
	mi.rotation.z = roll
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _sticker_text(parent: Node3D, text: String, at: Vector3, fit: Vector2, c: Color, font := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.outline_size = 0
	l.modulate = c
	# Big enough to read, small enough to fit: about 0.7 of the font size a letter.
	l.pixel_size = maxf(0.00012, minf(fit.x / (maxf(1.0, text.length()) * 0.7 * font), fit.y / font))
	l.position = at
	parent.add_child(l)


## A shipping label facing +Z, `w` by `h` metres: the courier's band with its mark and name,
## what's in the box, and the tracking number.
static func _box_sticker(w: float, h: float, part_id: String, seed_value: int) -> Node3D:
	var c: Dictionary = COURIERS[courier_for(seed_value)]
	var root := Node3D.new()
	root.name = "Label"
	_quad(root, Vector2(w, h), Vector3.ZERO, Color(0.95, 0.94, 0.9))
	var band := h * 0.36
	var by := h * 0.5 - band * 0.5
	_quad(root, Vector2(w, band), Vector3(0.0, by, 0.0006), c["bg"])
	# The firm's mark beside its name.
	var m := band * 0.62
	var mx := -w * 0.5 + m * 0.75
	var ink: Color = c["ink"]
	match str(c["mark"]):
		"disc":
			_quad(root, Vector2(m, m) * 0.72, Vector3(mx, by, 0.0012), ink, PI * 0.25)
			_quad(root, Vector2(m, m) * 0.72, Vector3(mx, by, 0.0012), ink)
		"diamond":
			_quad(root, Vector2(m, m) * 0.68, Vector3(mx, by, 0.0012), ink, PI * 0.25)
		"chevron":
			for side in [-1.0, 1.0]:
				_quad(root, Vector2(m * 0.75, m * 0.2), Vector3(mx, by + side * m * 0.2, 0.0012), ink, -side * 0.65)
		_:
			for i in 3:
				_quad(root, Vector2(m * (1.0 - i * 0.25), m * 0.16), Vector3(mx + i * m * 0.12, by + (1 - i) * m * 0.3, 0.0012), ink)
	var name_w := w - m * 1.7
	_sticker_text(root, str(c["name"]), Vector3(mx + m * 0.6 + name_w * 0.5, by, 0.0016), Vector2(name_w * 0.95, band * 0.62), ink)
	_sticker_text(root, PartsDB.part_name(part_id), Vector3(0.0, -h * 0.06, 0.0016), Vector2(w * 0.92, h * 0.24), Color(0.1, 0.09, 0.08))
	_sticker_text(root, tracking_for(seed_value), Vector3(0.0, -h * 0.36, 0.0016), Vector2(w * 0.7, h * 0.12), Color(0.25, 0.25, 0.25), 32)
	return root


## A new part still in its cardboard box, sized to fit it, with a delivery firm's shipping
## label on the lid and the front saying what's inside. `seed_value` (the item id) picks the
## firm and the tracking number, so a box always looks the same.
static func box_display(part_id: String, seed_value := 0) -> Node3D:
	if seed_value == 0:
		seed_value = hash(part_id)
	var size := box_size(part_id)
	if _cardboard == null:
		_cardboard = StandardMaterial3D.new()
		_cardboard.albedo_color = Color(0.66, 0.5, 0.32)
		_cardboard.roughness = 0.95
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _cardboard
	box.position.y = size.y * 0.5
	root.add_child(box)
	var tape := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(0.06, 0.004, size.z + 0.004)
	tape.mesh = strip
	var tape_mat := StandardMaterial3D.new()
	tape_mat.albedo_color = Color(0.8, 0.72, 0.5)
	tape_mat.roughness = 0.4
	tape.material_override = tape_mat
	tape.position.y = size.y + 0.001
	root.add_child(tape)
	# On the lid, lying face up and reading along the box's longer side, from the front when
	# it's wider than deep and from its right-hand side when it's deeper.
	var long_z := size.z > size.x * 1.15
	var across := size.z if long_z else size.x
	var along := size.x if long_z else size.z
	var lw := minf(across * 0.82, 0.32)
	var lh := minf(along * 0.7, lw * 0.62)
	var lid := _box_sticker(lw, lh, part_id, seed_value)
	lid.rotation = Vector3(-PI * 0.5, PI * 0.5 if long_z else 0.0, 0.0)
	lid.rotation_order = EULER_ORDER_YXZ
	lid.position = Vector3(0.0, size.y + 0.0045, 0.0)   # over the tape
	root.add_child(lid)
	# And upright on the front, for a box on a shelf.
	var fw := minf(size.x * 0.8, 0.3)
	var fh := minf(size.y * 0.75, fw * 0.62)
	var front := _box_sticker(fw, fh, part_id, seed_value)
	front.name = "FrontLabel"
	front.position = Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.002)
	root.add_child(front)
	root.set_meta("size", size)
	root.set_meta("courier", courier_for(seed_value))
	return root


func clear_pickers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.free()


func _local_xform(node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != self and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# ---------------------------------------------------------------------------- materials

## A material for the part being built, weathered by that part's rust and dirt.
func _mat(color: Color, metallic: float, roughness: float, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.1
	var cond: Dictionary = condition.get(_current_slot, {}) if _current_slot != "" else {}
	# A sprayed finish only goes on the painted surfaces, not the rubber or chrome bits.
	var finish := str(cond.get("finish", ""))
	if finish != "" and cond.has("color") and color == cond["color"]:
		_apply_finish(m, color, finish)
		metallic = m.metallic
		roughness = m.roughness
	var rust := float(cond.get("rust", 0.0))
	var dirt := float(cond.get("dirt", 0.0))
	if rust > 0.05:
		# Rust creeps in as patches: a blotchy mask that grows with the rust level.
		m.detail_enabled = true
		m.detail_mask = _rust_mask(rust)
		m.detail_albedo = _rust_texture()
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		m.metallic = metallic * (1.0 - rust * 0.7)
		m.roughness = lerpf(roughness, 0.95, rust)
		m.clearcoat_enabled = m.clearcoat_enabled and rust < 0.4
	if dirt > 0.05:
		m.albedo_color = m.albedo_color.lerp(Color(0.16, 0.13, 0.09), dirt * 0.65)
		m.roughness = lerpf(m.roughness, 1.0, dirt * 0.8)
		m.metallic *= 1.0 - dirt * 0.5
	return m


## Gloss is wet-look clear coat, matte soaks up the light, metallic has flake under the lacquer,
## chrome is a tinted mirror and patina is faded, mottled old paint.
static func _apply_finish(m: StandardMaterial3D, color: Color, finish: String) -> void:
	m.clearcoat_enabled = false
	match finish:
		"gloss":
			m.metallic = 0.05
			m.roughness = 0.12
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
		"matte":
			m.metallic = 0.0
			m.roughness = 0.9
			m.albedo_color = color.darkened(0.08)
		"metallic":
			m.metallic = 0.8
			m.roughness = 0.32
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.05
			m.albedo_color = color.lightened(0.08)
		"chrome":
			m.metallic = 1.0
			m.roughness = 0.1
			m.albedo_color = color.lerp(Color(0.97, 0.97, 0.99), 0.7)
		"patina":
			m.metallic = 0.15
			m.roughness = 0.78
			var faded := Color.from_hsv(color.h, color.s * 0.55, color.v * 0.8)
			m.albedo_color = faded
			m.detail_enabled = true
			m.detail_mask = _rust_mask(0.45)
			m.detail_albedo = _patina_texture()
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)


static func _patina_texture() -> NoiseTexture2D:
	if _patina_albedo:
		return _patina_albedo
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.58, 0.5))
	ramp.set_color(1, Color(0.95, 0.93, 0.88))
	_patina_albedo = NoiseTexture2D.new()
	_patina_albedo.width = 256
	_patina_albedo.height = 256
	_patina_albedo.seamless = true
	_patina_albedo.noise = noise
	_patina_albedo.color_ramp = ramp
	return _patina_albedo


## A lens or lit face that only glows with the ignition on ("ign": tail light, fog lamps,
## clocks) or the headlight switched on too ("head").
func _lamp(color: Color, energy: float, group: String) -> StandardMaterial3D:
	var m := _glow(color, energy)
	_lamps.append({"mat": m, "albedo": m.albedo_color, "energy": energy, "group": group})
	return m


## Lights the lenses and clocks: `ignition` for the engine running, `headlight` for the
## headlight switched on as well. Unlit, the lenses are dull glass.
func set_lights(ignition: bool, headlight: bool) -> void:
	headlight = headlight and ignition
	if _lit[0] == ignition and _lit[1] == headlight:
		return
	_lit = [ignition, headlight]
	for l in _lamps:
		var on: bool = headlight if l["group"] == "head" else ignition
		var m: StandardMaterial3D = l["mat"]
		var c: Color = l["albedo"]
		m.emission_enabled = on
		m.emission_energy_multiplier = float(l["energy"]) if on else 0.0
		m.albedo_color = c if on else c.darkened(0.6)


## Whether any lens or clock is glowing.
func lights_lit() -> bool:
	return _lit[0] or _lit[1]


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.0, 0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _rust_mask(rust: float) -> NoiseTexture2D:
	var level := clampi(roundi(rust * 10.0), 1, 10)
	if _rust_masks.has(level):
		return _rust_masks[level]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var edge := 1.0 - level / 10.0 * 0.85
	var ramp := Gradient.new()
	ramp.set_color(0, Color.BLACK)
	ramp.set_color(1, Color.WHITE)
	ramp.add_point(clampf(edge - 0.06, 0.01, 0.98), Color.BLACK)
	ramp.add_point(clampf(edge + 0.04, 0.02, 0.99), Color.WHITE)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	_rust_masks[level] = tex
	return tex


static func _rust_texture() -> NoiseTexture2D:
	if _rust_albedo:
		return _rust_albedo
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.09, 0.04))
	ramp.set_color(1, Color(0.48, 0.24, 0.1))
	_rust_albedo = NoiseTexture2D.new()
	_rust_albedo.width = 256
	_rust_albedo.height = 256
	_rust_albedo.seamless = true
	_rust_albedo.noise = noise
	_rust_albedo.color_ramp = ramp
	return _rust_albedo


# ---------------------------------------------------------------------------- mesh helpers

func _mesh_instance(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if _current_slot != "":
		_slot_meshes[_current_slot].append(mi)
	return mi


func _box(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(mesh, mat, center, parent)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


## A cylinder along local Y. A negative top radius means the same as the bottom.
func _cylinder(radius: float, height: float, top := -1.0, segments := 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = segments
	return c


## A cylinder from a to b. `stretch` scales its cross-section (x, z) and length (y).
func _tube(a: Vector3, b: Vector3, radius: float, mat: Material, stretch := Vector3.ONE, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(a.distance_to(b), 0.001)
	mesh.radial_segments = 12
	mesh.rings = 1
	var mi := _mesh_instance(mesh, mat, (a + b) * 0.5, parent)
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	var rot := Basis()
	if axis.length() > 0.0001:
		rot = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	elif dir.y < 0.0:
		rot = Basis(Vector3.RIGHT, PI)
	mi.basis = rot * Basis.from_scale(stretch)
	return mi
