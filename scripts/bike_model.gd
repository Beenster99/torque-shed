class_name BikeModel
extends Node3D
## The visible bike and rider, built from primitive meshes to match the chosen parts.
## Shared by the local bike and by other players' bikes.

var paint := Color(0.78, 0.09, 0.08)
var jacket := Color(0.1, 0.12, 0.16)

var _build: BikeBuild
var _steer_node: Node3D
var _front_hub: Node3D
var _front_wheel: Node3D
var _rear_hub: Node3D
var _rear_wheel: Node3D
var _swingarm: Node3D
var _rider: Node3D
var _steer_axis := Vector3.UP
var _head := Vector3.ZERO
var _pivot := Vector3.ZERO


func build_from(build: BikeBuild, paint_color := paint) -> void:
	_build = build
	paint = paint_color
	jacket = paint.darkened(0.45)
	for child in get_children():
		child.free()

	var wb := build.wheelbase
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var rake := deg_to_rad(build.rake_deg)
	_steer_axis = Vector3(0.0, cos(rake), sin(rake))
	_head = Vector3(0.0, 0.0, zf) + _steer_axis * build.fork_length
	var head_bottom := _head - _steer_axis * 0.16
	var seat_y := build.seat_height - build.rear_radius
	_pivot = Vector3(0.0, 0.16, zr - 0.6)
	var seat_front := Vector3(0.0, seat_y - 0.1, _pivot.z - 0.32)
	var tail := Vector3(0.0, seat_y - 0.02, zr - 0.12)
	var engine_c := Vector3(0.0, 0.1, lerpf(head_bottom.z, _pivot.z, 0.48))

	var frame_mat := _mat(build.frame_color, 0.7, 0.35)
	var paint_mat := _mat(paint, 0.25, 0.2, 0.6)
	var engine_mat := _mat(build.engine_color, 0.8, 0.4)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.7)
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.92)
	var leather := _mat(Color(0.08, 0.06, 0.05), 0.0, 0.6)

	# Frame
	var spar: bool = str(build.parts["frame"]).begins_with("alu")
	if spar:
		for side in [-1.0, 1.0]:
			_tube(head_bottom + Vector3(0.09 * side, 0.05, 0.0), _pivot + Vector3(0.12 * side, 0.1, 0.0), 0.045, frame_mat, Vector3(1.0, 1.0, 2.2))
			_tube(_pivot + Vector3(0.12 * side, 0.1, 0.0), _pivot + Vector3(0.12 * side, -0.12, 0.02), 0.04, frame_mat)
			_tube(seat_front + Vector3(0.08 * side, 0.0, 0.0), tail + Vector3(0.06 * side, 0.0, 0.0), 0.016, frame_mat)
			_tube(_pivot + Vector3(0.1 * side, 0.12, 0.0), tail + Vector3(0.06 * side, -0.02, -0.05), 0.014, frame_mat)
	else:
		_tube(_head, seat_front, 0.024, frame_mat)
		_tube(seat_front, tail, 0.018, frame_mat)
		_tube(seat_front, _pivot, 0.02, frame_mat)
		_tube(_pivot, tail, 0.016, frame_mat)
		var cradle_front := Vector3(0.0, engine_c.y - 0.2, engine_c.z - 0.2)
		var cradle_back := Vector3(0.0, engine_c.y - 0.2, _pivot.z)
		_tube(head_bottom, cradle_front, 0.024, frame_mat)
		_tube(cradle_front, cradle_back, 0.022, frame_mat)
		_tube(cradle_back, _pivot, 0.022, frame_mat)
	_tube(_head - _steer_axis * 0.02, head_bottom, 0.038, frame_mat)

	# Engine
	var cyl := build.cylinders
	var block_w := 0.2 + 0.13 * (cyl - 1)
	_box(engine_c, Vector3(block_w, 0.26, 0.34), engine_mat)
	_box(engine_c + Vector3(0.0, -0.06, 0.2), Vector3(block_w * 0.8, 0.18, 0.16), engine_mat)
	var barrel_c := engine_c + Vector3(0.0, 0.24, -0.06)
	for i in 5:
		_box(barrel_c + Vector3(0.0, -0.08 + i * 0.04, 0.0), Vector3(block_w + 0.04, 0.012, 0.24), engine_mat)
	_box(barrel_c + Vector3(0.0, 0.13, 0.0), Vector3(block_w * 0.95, 0.07, 0.2), chrome)
	# Exhaust
	var header_start := barrel_c + Vector3(0.0, 0.0, -0.14)
	var header_low := Vector3(0.1, -0.08, engine_c.z - 0.16)
	var header_back := Vector3(0.15, -0.04, _pivot.z + 0.05)
	_tube(header_start, header_low, 0.024, chrome)
	_tube(header_low, header_back, 0.026, chrome)
	_tube(header_back, Vector3(0.16, 0.2, zr - 0.08), 0.055, chrome)

	# Bodywork
	var tank_c := Vector3(0.0, lerpf(_head.y, seat_front.y, 0.5) + 0.06, lerpf(_head.z, seat_front.z, 0.55))
	var tank := _mesh_instance(_capsule(0.15, 0.56), paint_mat, tank_c)
	tank.rotation = Vector3(PI * 0.5 - 0.12, 0.0, 0.0)
	tank.scale = Vector3(1.05, 1.0, 0.75)
	_box(Vector3(0.0, seat_y, lerpf(seat_front.z, tail.z, 0.45)), Vector3(0.26, 0.08, 0.56), leather)
	_box(tail + Vector3(0.0, 0.0, 0.04), Vector3(0.2, 0.08, 0.2), paint_mat)
	_box(tail + Vector3(0.0, -0.03, 0.2), Vector3(0.13, 0.015, 0.26), black)  # rear fender
	_box(Vector3(0.0, 0.06, lerpf(engine_c.z, _pivot.z, 0.6)), Vector3(0.18, 0.14, 0.14), black)  # battery box
	var tail_light := _box(tail + Vector3(0.0, 0.0, 0.15), Vector3(0.1, 0.04, 0.02), _mat(Color(0.8, 0.02, 0.02), 0.0, 0.3))
	tail_light.material_override.emission_enabled = true
	tail_light.material_override.emission = Color(1.0, 0.05, 0.02)
	tail_light.material_override.emission_energy_multiplier = 2.0

	# Steering assembly
	_steer_node = Node3D.new()
	_steer_node.position = _head
	add_child(_steer_node)
	for side in [-1.0, 1.0]:
		_tube(Vector3(0.09 * side, 0.02, 0.0), Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (build.fork_length * 0.55), 0.024, chrome, Vector3.ONE, _steer_node)
	_box(Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.04, 0.08), frame_mat, _steer_node)  # top clamp
	_box(-_steer_axis * 0.16, Vector3(0.24, 0.04, 0.08), frame_mat, _steer_node)  # bottom clamp
	_tube(Vector3(-0.36, 0.12, 0.06), Vector3(0.36, 0.12, 0.06), 0.012, black, Vector3.ONE, _steer_node)
	_tube(Vector3(-0.36, 0.12, 0.06), Vector3(-0.27, 0.12, 0.06), 0.018, rubber, Vector3.ONE, _steer_node)
	_tube(Vector3(0.36, 0.12, 0.06), Vector3(0.27, 0.12, 0.06), 0.018, rubber, Vector3.ONE, _steer_node)
	_tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.12, 0.06), 0.014, black, Vector3.ONE, _steer_node)
	var lamp_mat := _mat(Color(1.0, 0.95, 0.8), 0.0, 0.1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.92, 0.75)
	lamp_mat.emission_energy_multiplier = 3.0
	var lamp := _mesh_instance(_sphere(0.075), lamp_mat, Vector3(0.0, -0.06, -0.12), _steer_node)
	lamp.scale = Vector3(1.0, 1.0, 0.6)
	if build.tyre_style == "offroad":
		_box(-_steer_axis * 0.2 + Vector3(0.0, -0.02, -0.12), Vector3(0.13, 0.015, 0.42), paint_mat, _steer_node)
		var plate := _box(Vector3(0.0, -0.08, -0.13), Vector3(0.22, 0.2, 0.02), paint_mat, _steer_node)
		plate.rotation.x = -0.35

	_front_hub = Node3D.new()
	_steer_node.add_child(_front_hub)
	for side in [-1.0, 1.0]:
		_tube(Vector3(0.09 * side, 0.0, 0.0), Vector3(0.09 * side, 0.0, 0.0) + _steer_axis * (build.fork_length * 0.5), 0.032, black, Vector3.ONE, _front_hub)
	if build.tyre_style != "offroad":
		_box(Vector3(0.0, build.front_radius + 0.04, 0.0), Vector3(0.12, 0.015, 0.36), paint_mat, _front_hub)
	_front_wheel = _make_wheel(build.front_radius, build.tyre_width * 0.85, build.tyre_style, rubber, chrome, black)
	_front_hub.add_child(_front_wheel)

	# Swingarm and rear wheel
	_swingarm = Node3D.new()
	_swingarm.position = _pivot
	add_child(_swingarm)
	var arm_len := Vector3(0.0, 0.0, zr).distance_to(_pivot)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.11 * side, 0.0, arm_len * 0.5), Vector3(0.035, 0.07, arm_len), frame_mat, _swingarm)
	_box(Vector3(0.0, 0.0, 0.04), Vector3(0.24, 0.07, 0.05), frame_mat, _swingarm)
	_rear_hub = Node3D.new()
	add_child(_rear_hub)
	_rear_wheel = _make_wheel(build.rear_radius, build.tyre_width, build.tyre_style, rubber, chrome, black)
	_rear_hub.add_child(_rear_wheel)
	# Shock(s)
	if build.parts["shock"] == "twin_shock":
		for side in [-1.0, 1.0]:
			_tube(Vector3(0.12 * side, 0.02, arm_len - 0.08), Vector3(0.12 * side, 0.3, arm_len - 0.2), 0.025, chrome, Vector3.ONE, _swingarm)
	else:
		var shock := _tube(_pivot + Vector3(0.0, 0.05, 0.08), Vector3(0.0, seat_y - 0.14, _pivot.z + 0.02), 0.035, _mat(Color(0.95, 0.75, 0.1), 0.3, 0.4))
		shock.name = "MonoShock"

	_build_rider(seat_y, seat_front, tail)


func _make_wheel(radius: float, width: float, style: String, rubber: Material, chrome: Material, black: Material) -> Node3D:
	var wheel := Node3D.new()
	var tyre_h := 0.075 if style == "offroad" else 0.065
	var tyre := TorusMesh.new()
	tyre.inner_radius = radius - tyre_h
	tyre.outer_radius = radius
	tyre.rings = 48
	tyre.ring_segments = 14
	var tyre_mi := _mesh_instance(tyre, rubber, Vector3.ZERO, wheel)
	tyre_mi.rotation.z = PI * 0.5
	tyre_mi.scale = Vector3(1.0, width / tyre_h * 0.55, 1.0)
	var rim_r := radius - tyre_h + 0.01
	if style == "offroad":
		var ring := TorusMesh.new()
		ring.inner_radius = rim_r - 0.022
		ring.outer_radius = rim_r
		_mesh_instance(ring, chrome, Vector3.ZERO, wheel).rotation.z = PI * 0.5
		for i in 18:
			var a := TAU * i / 18.0
			var spoke := _tube(Vector3(0.025 * (1 if i % 2 == 0 else -1), 0.0, 0.0),
				Vector3(0.0, cos(a), sin(a)) * (rim_r - 0.02), 0.003, chrome, Vector3.ONE, wheel)
			spoke.name = "Spoke%d" % i
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
	else:
		var rim := CylinderMesh.new()
		rim.top_radius = rim_r
		rim.bottom_radius = rim_r
		rim.height = width * 0.5
		rim.radial_segments = 40
		var rim_mi := _mesh_instance(rim, black, Vector3.ZERO, wheel)
		rim_mi.rotation.z = PI * 0.5
		for i in 5:
			var a := TAU * i / 5.0
			var spoke := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.5, Vector3(0.04, rim_r * 0.95, 0.028), chrome, wheel)
			spoke.rotation.x = -a
	var disc := CylinderMesh.new()
	disc.top_radius = 0.14 if style != "offroad" else 0.12
	disc.bottom_radius = disc.top_radius
	disc.height = 0.006
	disc.radial_segments = 32
	_mesh_instance(disc, chrome, Vector3(0.06, 0.0, 0.0), wheel).rotation.z = PI * 0.5
	var hub := CylinderMesh.new()
	hub.top_radius = 0.05
	hub.bottom_radius = 0.05
	hub.height = 0.14
	_mesh_instance(hub, chrome, Vector3.ZERO, wheel).rotation.z = PI * 0.5
	return wheel


func _build_rider(seat_y: float, seat_front: Vector3, tail: Vector3) -> void:
	_rider = Node3D.new()
	add_child(_rider)
	var suit := _mat(jacket, 0.0, 0.55)
	var pants := _mat(Color(0.06, 0.06, 0.07), 0.0, 0.7)
	var helmet := _mat(paint.lightened(0.15), 0.4, 0.15)
	var visor := _mat(Color(0.02, 0.02, 0.03), 0.9, 0.05)
	var gloves := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.6)
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(seat_front.z, tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	_tube(hips, shoulders, 0.15, suit, Vector3(1.25, 1.0, 0.8), _rider)
	_mesh_instance(_sphere(0.15), helmet, shoulders + Vector3(0.0, 0.2, -0.08), _rider)
	var v := _mesh_instance(_sphere(0.1), visor, shoulders + Vector3(0.0, 0.2, -0.17), _rider)
	v.scale = Vector3(1.1, 0.6, 0.5)
	var grip_l := _head + Vector3(-0.31, 0.12, 0.06)
	var grip_r := _head + Vector3(0.31, 0.12, 0.06)
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


func set_paint(color: Color) -> void:
	if _build:
		build_from(_build, color)


# ---------------------------------------------------------------------------- mesh helpers

func _mat(color: Color, metallic: float, roughness: float, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.1
	return m


func _mesh_instance(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
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
