class_name BikeModel
extends Node3D
## The visible bike and rider, built from primitive meshes to match the chosen parts.
## Every mesh belongs to one part slot, so a bike in the shed can show missing parts,
## rust and grime per part, highlight the part a player is looking at, and give each
## part its own click target. Shared by ridden, parked and other players' bikes.

const PICK_LAYER := 4

static var _rust_masks := {}     # rust level (1..10) -> NoiseTexture2D mask
static var _rust_albedo: NoiseTexture2D
static var _patina_albedo: NoiseTexture2D
static var _highlight_mat: StandardMaterial3D

var paint := Color(0.78, 0.09, 0.08)
var jacket := Color(0.1, 0.12, 0.16)
var present := {}                # slot -> bool; missing slots are not drawn
var condition := {}              # slot -> {rust, dirt, wear, color, finish}

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
var _cyls := []                  # {base, up} per cylinder barrel
var _arm_len := 0.6
var _grip_l := Vector3(-0.31, 0.12, 0.06)   # handlebar grips, in steering space
var _grip_r := Vector3(0.31, 0.12, 0.06)
var _highlighted := ""


## Builds the model. `fitted` maps slot -> bool (all fitted when empty); `part_condition`
## maps slot -> {rust, dirt, wear, color} and defaults to the build's own condition.
func build_from(build: BikeBuild, paint_color := paint, fitted := {}, part_condition = null, with_rider := true) -> void:
	_build = build
	paint = paint_color
	jacket = paint.darkened(0.45)
	present = fitted
	condition = build.condition if part_condition == null else part_condition
	_slot_meshes.clear()
	_highlighted = ""
	for slot in PartsDB.SLOTS:
		_slot_meshes[slot] = []
	for child in get_children():
		child.free()
	_rider = null

	var wb := build.wheelbase
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var rake := deg_to_rad(build.rake_deg)
	_steer_axis = Vector3(0.0, cos(rake), sin(rake))
	_head = Vector3(0.0, 0.0, zf) + _steer_axis * build.fork_length
	_head_bottom = _head - _steer_axis * 0.16
	_seat_y = build.seat_height - build.rear_radius
	_pivot = Vector3(0.0, 0.16, zr - 0.6)
	_seat_front = Vector3(0.0, _seat_y - 0.1, _pivot.z - 0.32)
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
		_draw_rim(wheel, rim_r, width)
		_current_slot = side + "_tyre"
		_draw_tyre(wheel, rim_r, build.front_radius if front else build.rear_radius, width)
		_draw_brake(side, wheel, hub, rim_r)
	_draw_rear_master()
	_draw_final_drive(zr)
	_draw_shock()

	_apply_visibility()
	_current_slot = ""
	if with_rider:
		_build_rider()
	update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


## Where each cylinder's barrel sits and which way it points, for the engine layout.
func _layout_cylinders(build: BikeBuild) -> void:
	_cyls.clear()
	var cyl := build.cylinders
	if build.layout == "vtwin":
		_block_w = 0.22
		for dir in [-1.0, 1.0]:
			var up := Vector3(0.0, cos(0.6), 0.6 * dir).normalized()
			_cyls.append({"base": _engine_c + Vector3(0.0, 0.13, 0.07 * dir) + up * 0.12, "up": up})
		return
	_block_w = 0.2 + 0.11 * (cyl - 1)
	var up := Vector3(0.0, 1.0, -0.25).normalized()
	for c in cyl:
		var cx := (c - (cyl - 1) * 0.5) * 0.12
		_cyls.append({"base": _engine_c + Vector3(cx, 0.14, -0.04) + up * 0.1, "up": up})


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
	_box(_tail + Vector3(0.0, -0.05, 0.2), Vector3(0.13, 0.015, 0.26), black)  # rear fender
	_box(Vector3(0.0, 0.06, lerpf(_engine_c.z, _pivot.z, 0.6)), Vector3(0.18, 0.14, 0.14), black)  # battery box
	var tail_light := _box(_tail + Vector3(0.0, -0.02, 0.2), Vector3(0.1, 0.04, 0.02), _glow(Color(1.0, 0.05, 0.02), 2.0))
	tail_light.name = "TailLight"
	for side in [-1.0, 1.0]:
		_box(Vector3(0.17 * side, 0.02, _pivot.z + 0.02), Vector3(0.1, 0.02, 0.04), black)  # footpegs
	_swingarm = Node3D.new()
	_swingarm.position = _pivot
	add_child(_swingarm)
	_arm_len = Vector3(0.0, 0.0, zr).distance_to(_pivot)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.11 * side, 0.0, _arm_len * 0.5), Vector3(0.035, 0.07, _arm_len), frame_mat, _swingarm)
	_box(Vector3(0.0, 0.0, 0.04), Vector3(0.24, 0.07, 0.05), frame_mat, _swingarm)


func _draw_tank() -> void:
	_current_slot = "tank"
	var p := _part()
	var mat := _mat(_col(), 0.25, 0.2, 0.6)
	var size := pow(float(p.get("capacity", 15.0)) / 15.0, 0.33)
	var c := Vector3(0.0, lerpf(_head.y, _seat_front.y, 0.5) + 0.06, lerpf(_head.z, _seat_front.z, 0.55))
	match str(p.get("style", "cafe")):
		"sport":
			var main := _box(c + Vector3(0.0, -0.01, 0.02), Vector3(0.36, 0.2, 0.44) * size, mat)
			main.rotation.x = -0.12
			var nose := _box(c + Vector3(0.0, 0.04, -0.2 * size), Vector3(0.3, 0.14, 0.18) * size, mat)
			nose.rotation.x = 0.45
		"enduro":
			var t := _mesh_instance(_capsule(0.13, 0.46), mat, c + Vector3(0.0, -0.02, -0.03))
			t.rotation = Vector3(PI * 0.5 - 0.3, 0.0, 0.0)
			t.scale = Vector3(1.0, 1.0, 0.7)
			for side in [-1.0, 1.0]:
				var shroud := _box(c + Vector3(0.15 * side, -0.12, -0.12), Vector3(0.03, 0.22, 0.3), mat)
				shroud.rotation.x = -0.4
		"peanut":
			var t := _mesh_instance(_capsule(0.11, 0.36), mat, c + Vector3(0.0, 0.02, 0.0))
			t.rotation = Vector3(PI * 0.5 - 0.15, 0.0, 0.0)
			t.scale = Vector3(0.85, 1.0, 0.85)
		"touring":
			var t := _mesh_instance(_capsule(0.18, 0.6), mat, c + Vector3(0.0, 0.01, 0.0))
			t.rotation = Vector3(PI * 0.5 - 0.1, 0.0, 0.0)
			t.scale = Vector3(1.15, 1.0, 0.8)
		_:
			var t := _mesh_instance(_capsule(0.15 * size, 0.58 * size), mat, c)
			t.rotation = Vector3(PI * 0.5 - 0.12, 0.0, 0.0)
			t.scale = Vector3(1.0, 1.0, 0.72)
	_mesh_instance(_cylinder(0.035, 0.02), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15), c + Vector3(0.0, 0.13 * size, -0.03))


func _draw_saddle() -> void:
	_current_slot = "saddle"
	var p := _part()
	var mat := _mat(_col(), 0.0, 0.6)
	var y := _seat_y
	var z0 := _seat_front.z
	var z1 := _tail.z
	var mid := lerpf(z0, z1, 0.45)
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
			_box(Vector3(0.0, y, mid), Vector3(0.26, 0.08, 0.6), mat)


# ---------------------------------------------------------------------------- engine

func _draw_engine() -> void:
	_current_slot = "engine"
	var mat := _mat(_col(), 0.8, 0.4)
	_box(_engine_c, Vector3(_block_w, 0.26, 0.34), mat)
	for c in _cyls:
		_tube(c["base"] - c["up"] * 0.1, c["base"] + c["up"] * 0.09, 0.048, mat)


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
	match exhaust_id:
		"straight_pipe":
			_tube(header_back, can_end + Vector3(0.0, -0.04, 0.12), 0.03, pipe_mat)
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
	var lamp := _mesh_instance(_sphere(0.075), _glow(Color(1.0, 0.92, 0.75), 3.0), Vector3(0.0, -0.08, -0.13), _steer_node)
	lamp.scale = Vector3(1.0, 1.0, 0.6)
	var fender := _mat(paint, 0.25, 0.2, 0.6)
	if build.tyre_style == "offroad":
		_box(-_steer_axis * 0.2 + Vector3(0.0, -0.02, -0.12), Vector3(0.13, 0.015, 0.42), fender, _steer_node)
	else:
		_box(Vector3(0.0, build.front_radius + 0.04, 0.0), Vector3(0.12, 0.015, 0.36), fender, _front_hub)


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
	var p := _part()
	var housing := _mat(_col(), 0.6, 0.35)
	var at := Vector3(0.0, 0.1, -0.06)
	var tilt := Basis(Vector3.RIGHT, -0.9)
	match str(p.get("style", "analog")):
		"analog", "twin":
			var xs := [0.0] if p.get("style") == "analog" else [-0.07, 0.07]
			for x in xs:
				var dial := _mesh_instance(_cylinder(0.05, 0.05), housing, at + Vector3(x, 0.0, 0.0), _steer_node)
				dial.basis = tilt
				var face := _mesh_instance(_cylinder(0.043, 0.004), _glow(Color(0.95, 0.9, 0.75), 1.2), at + Vector3(x, 0.0, 0.0) + tilt.y * 0.026, _steer_node)
				face.basis = tilt
		"lcd", "tft":
			var tft: bool = p.get("style") == "tft"
			var size := Vector3(0.2, 0.03, 0.12) if tft else Vector3(0.16, 0.03, 0.09)
			var body := _box(at, size, housing, _steer_node)
			body.basis = tilt
			var screen := _box(at + tilt.y * 0.016, Vector3(size.x - 0.02, 0.004, size.z - 0.02),
				_glow(Color(0.3, 0.6, 1.0) if tft else Color(0.55, 0.75, 0.55), 1.5), _steer_node)
			screen.basis = tilt
		_:
			var body := _box(at, Vector3(0.22, 0.03, 0.07), housing, _steer_node)
			body.basis = tilt
			var colors := [Color(0.1, 1.0, 0.2), Color(0.1, 1.0, 0.2), Color(1.0, 0.85, 0.1), Color(1.0, 0.85, 0.1), Color(1.0, 0.1, 0.05), Color(1.0, 0.1, 0.05)]
			for i in 6:
				var led := _box(at + tilt.y * 0.017 + tilt.x * (-0.075 + i * 0.03) + tilt.z * 0.018, Vector3(0.018, 0.004, 0.014), _glow(colors[i], 2.0), _steer_node)
				led.basis = tilt


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


# ---------------------------------------------------------------------------- wheels and brakes

func _draw_rim(wheel: Node3D, rim_r: float, width: float) -> void:
	var p := _part()
	var style := str(p.get("style", "cast"))
	var rim_mat := _mat(_col(), 0.9 if style != "carbon" else 0.2, 0.25, 0.8 if style == "carbon" else 0.0)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	if style == "spoked" or style == "wire":
		var ring := TorusMesh.new()
		ring.inner_radius = rim_r - 0.022
		ring.outer_radius = rim_r
		var rim := _mesh_instance(ring, rim_mat, Vector3.ZERO, wheel)
		rim.rotation.z = PI * 0.5
		rim.scale = Vector3(1.0, maxf(1.0, width / 0.03), 1.0)
		var count := 36 if style == "wire" else 18
		for i in count:
			var a := TAU * i / count
			var spoke := _tube(Vector3(0.025 * (1 if i % 2 == 0 else -1), 0.0, 0.0),
				Vector3(0.0, cos(a), sin(a)) * (rim_r - 0.02), 0.003 if style == "spoked" else 0.0022, chrome, Vector3.ONE, wheel)
			spoke.name = "Spoke%d" % i
	else:
		var rim := _mesh_instance(_cylinder(rim_r, width * 0.5), rim_mat, Vector3.ZERO, wheel)
		rim.rotation.z = PI * 0.5
		var spokes := 3 if style == "carbon" else 5
		for i in spokes:
			var a := TAU * i / spokes
			var spoke := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.5, Vector3(0.04, rim_r * 0.95, 0.04 if style == "carbon" else 0.028), rim_mat, wheel)
			spoke.rotation.x = -a
	var hub := _mesh_instance(_cylinder(0.05, 0.14), chrome, Vector3.ZERO, wheel)
	hub.rotation.z = PI * 0.5


func _draw_tyre(wheel: Node3D, rim_r: float, radius: float, width: float) -> void:
	var style := str(_part().get("style", "road"))
	var rubber := _mat(_col(), 0.0, 0.92)
	var tyre := TorusMesh.new()
	tyre.inner_radius = rim_r - 0.005
	tyre.outer_radius = radius
	tyre.rings = 48
	tyre.ring_segments = 14
	var tyre_mi := _mesh_instance(tyre, rubber, Vector3.ZERO, wheel)
	tyre_mi.rotation.z = PI * 0.5
	tyre_mi.scale = Vector3(1.0, width / maxf(radius - rim_r, 0.02) * 0.55, 1.0)
	if style != "offroad":
		return
	var knobs := MultiMesh.new()
	knobs.transform_format = MultiMesh.TRANSFORM_3D
	var knob := BoxMesh.new()
	knob.size = Vector3(width * 0.9, 0.022, 0.03)
	knobs.mesh = knob
	knobs.instance_count = 40
	for i in 40:
		var a := TAU * i / 40.0
		var t := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0.0, cos(a), sin(a)) * (radius - 0.006))
		t = t.translated_local(Vector3((0.02 if i % 2 == 0 else -0.02), 0.0, 0.0))
		knobs.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = knobs
	mmi.material_override = rubber
	wheel.add_child(mmi)
	_slot_meshes[_current_slot].append(mmi)


func _draw_brake(side: String, wheel: Node3D, hub: Node3D, rim_r: float) -> void:
	var front := side == "front"
	var x := 0.068 if front else 0.07
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
	var chain_mat := _mat(Color(0.12, 0.12, 0.12), 0.8, 0.5)
	for s in [-1.0, 1.0]:
		_box(Vector3(-0.125, s * lerpf(front_r, rear_r, 0.5), _arm_len * 0.5), Vector3(0.012, 0.012, _arm_len), chain_mat, _swingarm)


func _draw_shock() -> void:
	_current_slot = "shock"
	var shock := _part()
	var col := _col()
	if shock.get("layout", "mono") == "twin":
		var gas: bool = _part_id() == "twin_shock_gas"
		var spring_mat := _mat(col, 0.6, 0.3)
		for side in [-1.0, 1.0]:
			_tube(Vector3(0.12 * side, 0.02, _arm_len - 0.08), Vector3(0.12 * side, 0.3, _arm_len - 0.2), 0.025, spring_mat, Vector3.ONE, _swingarm)
			if gas:
				_tube(Vector3(0.155 * side, 0.22, _arm_len - 0.17), Vector3(0.155 * side, 0.32, _arm_len - 0.21), 0.016, _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2), Vector3.ONE, _swingarm)
	else:
		_tube(_pivot + Vector3(0.0, 0.05, 0.08), Vector3(0.0, _seat_y - 0.14, _pivot.z + 0.02), 0.035, _mat(col, 0.3, 0.4))


func _build_rider() -> void:
	_rider = Node3D.new()
	add_child(_rider)
	var seat_y := _seat_y
	var suit := _mat(jacket, 0.0, 0.55)
	var pants := _mat(Color(0.06, 0.06, 0.07), 0.0, 0.7)
	var helmet := _mat(paint.lightened(0.15), 0.4, 0.15)
	var visor := _mat(Color(0.02, 0.02, 0.03), 0.9, 0.05)
	var gloves := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.6)
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	_tube(hips, shoulders, 0.15, suit, Vector3(1.25, 1.0, 0.8), _rider)
	_mesh_instance(_sphere(0.15), helmet, shoulders + Vector3(0.0, 0.2, -0.08), _rider)
	var v := _mesh_instance(_sphere(0.1), visor, shoulders + Vector3(0.0, 0.2, -0.17), _rider)
	v.scale = Vector3(1.1, 0.6, 0.5)
	var grip_l := _head + _grip_l
	var grip_r := _head + _grip_r
	for side in [-1.0, 1.0]:
		var sh := shoulders + Vector3(0.19 * side, -0.04, 0.0)
		var grip := grip_r if side > 0 else grip_l
		var elbow := sh.lerp(grip, 0.5) + Vector3(0.08 * side, -0.06, 0.04)
		_tube(sh, elbow, 0.05, suit, Vector3.ONE, _rider)
		_tube(elbow, grip, 0.045, suit, Vector3.ONE, _rider)
		_mesh_instance(_sphere(0.045), gloves, grip, _rider)
		var hip := hips + Vector3(0.12 * side, -0.02, 0.0)
		var knee := Vector3(0.19 * side, seat_y - 0.02, hips.z - 0.36)
		var peg := Vector3(0.17 * side, 0.02, _pivot.z + 0.02)
		_tube(hip, knee, 0.075, pants, Vector3.ONE, _rider)
		_tube(knee, peg, 0.06, pants, Vector3.ONE, _rider)
		_box(peg + Vector3(0.0, -0.02, -0.06), Vector3(0.09, 0.08, 0.22), gloves, _rider)


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
	if _rider:
		_rider.position = Vector3(lean_in * 0.05, 0.0, -body_shift * 0.1)
		_rider.rotation = Vector3(-body_shift * 0.12, 0.0, -lean_in * 0.12)


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


## Local-space bounding box of a part's meshes.
func slot_bounds(slot: String) -> AABB:
	var box := AABB()
	var first := true
	for mi in _slot_meshes.get(slot, []):
		var aabb: AABB = _local_xform(mi) * (mi as VisualInstance3D).get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	return box


## Adds a static click target per fitted part, with box shapes fitted to its meshes.
## Each body carries metadata "slot", plus everything in `meta`; `slot_meta` replaces `meta`
## for particular slots. Rings (tyres, spoked rims) get a hoop of boxes so the ray can still
## reach the disc and caliper inside them.
func build_pickers(meta: Dictionary, slot_meta := {}) -> void:
	clear_pickers()
	for slot in _slot_meshes:
		if not is_fitted(slot) or _slot_meshes[slot].is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "Pick_" + slot
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		body.set_meta("slot", slot)
		var m: Dictionary = slot_meta.get(slot, meta)
		for key in m:
			body.set_meta(key, m[key])
		for mi in _slot_meshes[slot]:
			if mi is MultiMeshInstance3D or str(mi.name).begins_with("Spoke"):
				continue
			var xf := _local_xform(mi)
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
			_add_box(body, xf * Transform3D(Basis(), aabb.get_center()), aabb.size)
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
static func assembly_display(parts: Dictionary, cond: Dictionary) -> Node3D:
	var build := PartsDB.DEFAULT_BUILD.duplicate()
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
	var slot: String = PartsDB.slots_for_kind(PartsDB.kind_of(part_id))[0]
	return assembly_display({slot: part_id}, {slot: cond})


## A loose item from the shed, drawn with whatever is fitted to it (an engine with its head,
## carbs and so on).
static func item_display(item_id: int) -> Node3D:
	var it: Dictionary = Shed.items[item_id]
	if Shed.is_engine(item_id):
		var asm := Shed.engine_assembly(item_id)
		var shown := {}
		for slot in asm["fitted"]:
			if asm["fitted"][slot]:
				shown[slot] = asm["parts"][slot]
		return assembly_display(shown, asm["cond"])
	return part_display(it["part"], Shed.condition_of(it))


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
