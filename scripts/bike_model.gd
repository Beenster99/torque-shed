class_name BikeModel
extends Node3D
## The visible bike and rider, built from primitive meshes to match the chosen parts.
## Every mesh belongs to one part slot, so a bike in the shed can show missing parts,
## rust and grime per part, highlight the part a player is looking at, and give each
## part its own click target. Shared by ridden, parked and other players' bikes.

const PICK_LAYER := 4

static var _rust_masks := {}     # rust level (1..10) -> NoiseTexture2D mask
static var _rust_albedo: NoiseTexture2D
static var _highlight_mat: StandardMaterial3D

var paint := Color(0.78, 0.09, 0.08)
var jacket := Color(0.1, 0.12, 0.16)
var present := {}                # slot -> bool; missing slots are not drawn
var condition := {}              # slot -> {rust, dirt, wear}

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
var _pivot := Vector3.ZERO
var _highlighted := ""


## Builds the model. `fitted` maps slot -> bool (all fitted when empty); `part_condition`
## maps slot -> {rust, dirt, wear} and defaults to the build's own condition.
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

	var p := build.parts
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
	var cyl := build.cylinders
	var block_w := 0.2 + 0.13 * (cyl - 1)
	var barrel_c := engine_c + Vector3(0.0, 0.24, -0.06)

	# ------------------------------------------------------------------ frame and bodywork
	_current_slot = "frame"
	var frame_style := str(PartsDB.get_part(p["frame"]).get("style", "cradle"))
	var frame_mat := _mat(build.frame_color, 0.7, 0.35)
	if p["frame"] == "carbon_monocoque":
		frame_mat = _mat(build.frame_color, 0.2, 0.25, 0.8)
	var paint_mat := _mat(paint, 0.25, 0.2, 0.6)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.7)
	var leather := _mat(Color(0.08, 0.06, 0.05), 0.0, 0.6)
	match frame_style:
		"spar":
			var thick := 1.6 if p["frame"] == "carbon_monocoque" else 1.0
			for side in [-1.0, 1.0]:
				_tube(head_bottom + Vector3(0.09 * side, 0.05, 0.0), _pivot + Vector3(0.12 * side, 0.1, 0.0), 0.045, frame_mat, Vector3(thick, 1.0, 2.2))
				_tube(_pivot + Vector3(0.12 * side, 0.1, 0.0), _pivot + Vector3(0.12 * side, -0.12, 0.02), 0.04, frame_mat)
				_tube(seat_front + Vector3(0.08 * side, 0.0, 0.0), tail + Vector3(0.06 * side, 0.0, 0.0), 0.016, frame_mat)
				_tube(_pivot + Vector3(0.1 * side, 0.12, 0.0), tail + Vector3(0.06 * side, -0.02, -0.05), 0.014, frame_mat)
		"trellis":
			for side in [-1.0, 1.0]:
				var top := []
				var bottom := []
				for i in 5:
					var f := i / 4.0
					top.append(head_bottom.lerp(_pivot + Vector3(0.0, 0.18, 0.0), f) + Vector3(0.1 * side, 0.08, 0.0))
					bottom.append(head_bottom.lerp(_pivot, f) + Vector3(0.11 * side, -0.12 * sin(f * PI), 0.0))
				for i in 4:
					_tube(top[i], top[i + 1], 0.012, frame_mat)
					_tube(bottom[i], bottom[i + 1], 0.012, frame_mat)
					_tube(top[i], bottom[i + 1], 0.01, frame_mat)
				_tube(top[4], bottom[4], 0.012, frame_mat)
				_tube(seat_front + Vector3(0.07 * side, 0.0, 0.0), tail + Vector3(0.06 * side, 0.0, 0.0), 0.012, frame_mat)
				_tube(top[3], tail + Vector3(0.06 * side, -0.03, -0.05), 0.01, frame_mat)
		"backbone":
			_tube(_head, _pivot + Vector3(0.0, 0.22, 0.0), 0.045, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.22, 0.0), _pivot, 0.035, frame_mat)
			_tube(seat_front, tail, 0.018, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.2, 0.0), tail + Vector3(0.0, -0.03, -0.05), 0.016, frame_mat)
		_:
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
	var tank_c := Vector3(0.0, lerpf(_head.y, seat_front.y, 0.5) + 0.06, lerpf(_head.z, seat_front.z, 0.55))
	var tank := _mesh_instance(_capsule(0.15, 0.56), paint_mat, tank_c)
	tank.rotation = Vector3(PI * 0.5 - 0.12, 0.0, 0.0)
	tank.scale = Vector3(1.05, 1.0, 0.75)
	_box(Vector3(0.0, seat_y, lerpf(seat_front.z, tail.z, 0.45)), Vector3(0.26, 0.08, 0.56), leather)
	_box(tail + Vector3(0.0, 0.0, 0.04), Vector3(0.2, 0.08, 0.2), paint_mat)
	_box(tail + Vector3(0.0, -0.03, 0.2), Vector3(0.13, 0.015, 0.26), black)  # rear fender
	_box(Vector3(0.0, 0.06, lerpf(engine_c.z, _pivot.z, 0.6)), Vector3(0.18, 0.14, 0.14), black)  # battery box
	var tail_light := _box(tail + Vector3(0.0, 0.0, 0.15), Vector3(0.1, 0.04, 0.02), _glow(Color(1.0, 0.05, 0.02), 2.0))
	tail_light.name = "TailLight"
	_swingarm = Node3D.new()
	_swingarm.position = _pivot
	add_child(_swingarm)
	var arm_len := Vector3(0.0, 0.0, zr).distance_to(_pivot)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.11 * side, 0.0, arm_len * 0.5), Vector3(0.035, 0.07, arm_len), frame_mat, _swingarm)
	_box(Vector3(0.0, 0.0, 0.04), Vector3(0.24, 0.07, 0.05), frame_mat, _swingarm)

	# ------------------------------------------------------------------ engine
	_current_slot = "engine"
	var engine_mat := _mat(build.engine_color, 0.8, 0.4)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	_box(engine_c, Vector3(block_w, 0.26, 0.34), engine_mat)
	for c in cyl:
		var cx := (c - (cyl - 1) * 0.5) * 0.13
		for i in 5:
			_box(barrel_c + Vector3(cx, -0.08 + i * 0.04, 0.0), Vector3(0.12, 0.012, 0.24), engine_mat)
		_tube(barrel_c + Vector3(cx, -0.1, 0.0), barrel_c + Vector3(cx, 0.1, 0.0), 0.045, engine_mat)
	_box(barrel_c + Vector3(0.0, 0.13, 0.0), Vector3(block_w * 0.95, 0.07, 0.2), chrome)

	# ------------------------------------------------------------------ gearbox
	_current_slot = "gearbox"
	var case_mat := _mat(build.engine_color.lightened(0.1), 0.75, 0.45)
	_box(engine_c + Vector3(0.0, -0.06, 0.2), Vector3(block_w * 0.8, 0.18, 0.16), case_mat)
	var clutch := _mesh_instance(_cylinder(0.1, 0.04), case_mat, engine_c + Vector3(block_w * 0.5 + 0.02, -0.02, 0.1))
	clutch.rotation.z = PI * 0.5
	_tube(engine_c + Vector3(-block_w * 0.5 - 0.06, -0.09, 0.2), engine_c + Vector3(-block_w * 0.5 - 0.14, -0.13, 0.12), 0.008, chrome)

	# ------------------------------------------------------------------ intake
	_current_slot = "intake"
	var intake_at := barrel_c + Vector3(0.0, 0.02, 0.17)
	var intake_id := str(p["intake"])
	match intake_id:
		"pod_filters", "velocity_stacks", "race_carbs":
			var carb_mat := _mat(Color(0.7, 0.71, 0.72), 0.85, 0.3)
			for c in cyl:
				var cx := (c - (cyl - 1) * 0.5) * 0.11
				_tube(intake_at + Vector3(cx, 0.0, 0.0), intake_at + Vector3(cx, 0.02, 0.07), 0.03, carb_mat)
				if intake_id == "race_carbs":
					_box(intake_at + Vector3(cx, 0.03, 0.05), Vector3(0.05, 0.06, 0.06), carb_mat)
				if intake_id == "pod_filters":
					var pod := _mesh_instance(_cylinder(0.04, 0.09), _mat(Color(0.75, 0.08, 0.08), 0.0, 0.8), intake_at + Vector3(cx, 0.04, 0.13))
					pod.rotation.x = PI * 0.5 - 0.3
				else:
					var stack := _mesh_instance(_cylinder(0.026, 0.06, 0.04), chrome, intake_at + Vector3(cx, 0.03, 0.12))
					stack.rotation.x = PI * 0.5 - 0.3
		"fuel_injection":
			for c in cyl:
				var cx := (c - (cyl - 1) * 0.5) * 0.11
				_tube(intake_at + Vector3(cx, 0.0, 0.0), intake_at + Vector3(cx, 0.04, 0.06), 0.028, _mat(Color(0.15, 0.15, 0.16), 0.8, 0.35))
			_box(intake_at + Vector3(0.0, 0.08, 0.1), Vector3(block_w * 0.9, 0.08, 0.12), _mat(Color(0.05, 0.05, 0.06), 0.2, 0.3, 0.6))
		_:
			_tube(intake_at, intake_at + Vector3(0.0, 0.03, 0.08), 0.035, black)
			_box(intake_at + Vector3(0.0, 0.08, 0.16), Vector3(0.22, 0.16, 0.16), black)

	# ------------------------------------------------------------------ exhaust
	_current_slot = "exhaust"
	var exhaust_id := str(p["exhaust"])
	var pipe_mat := chrome
	if exhaust_id == "titanium_race":
		pipe_mat = _mat(Color(0.55, 0.55, 0.75), 1.0, 0.18)
	elif exhaust_id == "full_system":
		pipe_mat = _mat(Color(0.75, 0.73, 0.68), 1.0, 0.22)
	else:
		pipe_mat = _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var header_back := Vector3(0.15, -0.04, _pivot.z + 0.05)
	for c in cyl:
		var cx := (c - (cyl - 1) * 0.5) * 0.13
		var header_start := barrel_c + Vector3(cx, 0.0, -0.14)
		var header_low := Vector3(0.1 + cx * 0.4, -0.08, engine_c.z - 0.16)
		_tube(header_start, header_low, 0.02, pipe_mat)
		_tube(header_low, header_back, 0.022, pipe_mat)
	var can_end := Vector3(0.16, 0.2, zr - 0.08)
	match exhaust_id:
		"straight_pipe":
			_tube(header_back, can_end + Vector3(0.0, -0.04, 0.12), 0.03, pipe_mat)
		"slip_on":
			_tube(header_back, header_back.lerp(can_end, 0.4), 0.03, pipe_mat)
			_tube(header_back.lerp(can_end, 0.4), can_end, 0.05, _mat(Color(0.06, 0.06, 0.07), 0.3, 0.3, 0.7))
		"titanium_race", "full_system":
			_tube(header_back, header_back.lerp(can_end, 0.5), 0.032, pipe_mat)
			_tube(header_back.lerp(can_end, 0.5), can_end, 0.048, pipe_mat, Vector3(1.0, 1.0, 0.8))
		_:
			_tube(header_back, can_end, 0.06, pipe_mat)

	# ------------------------------------------------------------------ fork, bars and lamp
	_steer_node = Node3D.new()
	_steer_node.position = _head
	add_child(_steer_node)
	_front_hub = Node3D.new()
	_steer_node.add_child(_front_hub)
	_current_slot = "fork"
	var fork_id := str(p["fork"])
	var usd := fork_id.contains("usd") or fork_id == "long_travel_mx"
	var upper_mat := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var lower_mat := _mat(Color(0.03, 0.03, 0.03), 0.3, 0.5)
	if usd:
		upper_mat = _mat(Color(0.75, 0.55, 0.15), 0.9, 0.25) if fork_id == "usd_sport" else _mat(Color(0.08, 0.08, 0.09), 0.7, 0.3)
		lower_mat = _mat(Color(0.8, 0.65, 0.2), 1.0, 0.15)
	var fl := build.fork_length
	for side in [-1.0, 1.0]:
		_tube(Vector3(0.09 * side, 0.02, 0.0), Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (fl * 0.55), 0.034 if usd else 0.024, upper_mat, Vector3.ONE, _steer_node)
		_tube(Vector3(0.09 * side, 0.0, 0.0), Vector3(0.09 * side, 0.0, 0.0) + _steer_axis * (fl * 0.5), 0.022 if usd else 0.032, lower_mat, Vector3.ONE, _front_hub)
	var clamp_mat := _mat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	_box(Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	_box(-_steer_axis * 0.16, Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	var bar_black := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.7)
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.92)
	_tube(Vector3(-0.36, 0.12, 0.06), Vector3(0.36, 0.12, 0.06), 0.012, bar_black, Vector3.ONE, _steer_node)
	_tube(Vector3(-0.36, 0.12, 0.06), Vector3(-0.27, 0.12, 0.06), 0.018, rubber, Vector3.ONE, _steer_node)
	_tube(Vector3(0.36, 0.12, 0.06), Vector3(0.27, 0.12, 0.06), 0.018, rubber, Vector3.ONE, _steer_node)
	_tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.12, 0.06), 0.014, bar_black, Vector3.ONE, _steer_node)
	var lamp := _mesh_instance(_sphere(0.075), _glow(Color(1.0, 0.92, 0.75), 3.0), Vector3(0.0, -0.06, -0.12), _steer_node)
	lamp.scale = Vector3(1.0, 1.0, 0.6)
	var fork_paint := _mat(paint, 0.25, 0.2, 0.6)
	if build.tyre_style == "offroad":
		_box(-_steer_axis * 0.2 + Vector3(0.0, -0.02, -0.12), Vector3(0.13, 0.015, 0.42), fork_paint, _steer_node)
		var plate := _box(Vector3(0.0, -0.08, -0.13), Vector3(0.22, 0.2, 0.02), fork_paint, _steer_node)
		plate.rotation.x = -0.35
	else:
		_box(Vector3(0.0, build.front_radius + 0.04, 0.0), Vector3(0.12, 0.015, 0.36), fork_paint, _front_hub)

	# ------------------------------------------------------------------ wheels
	_current_slot = "wheels"
	_front_wheel = _make_wheel(build.front_radius, build.tyre_width * 0.85, build.tyre_style)
	_front_hub.add_child(_front_wheel)
	_rear_hub = Node3D.new()
	add_child(_rear_hub)
	_rear_wheel = _make_wheel(build.rear_radius, build.tyre_width, build.tyre_style)
	_rear_hub.add_child(_rear_wheel)

	# ------------------------------------------------------------------ brakes
	_current_slot = "brakes"
	var brake_style := str(PartsDB.get_part(p["brakes"]).get("style", "disc"))
	_make_brake(_front_wheel, _front_hub, brake_style, true, build.front_radius)
	_make_brake(_rear_wheel, _rear_hub, brake_style, false, build.rear_radius)

	# ------------------------------------------------------------------ final drive
	_current_slot = "final_drive"
	var fd := PartsDB.get_part(p["final_drive"])
	var front_r := 0.0045 * float(fd.get("front", 15))
	var rear_r := 0.0042 * float(fd.get("rear", 45))
	var sprocket_mat := _mat(Color(0.55, 0.56, 0.6), 0.9, 0.35)
	var front_sp := _mesh_instance(_cylinder(front_r, 0.012), sprocket_mat, Vector3(-0.13, 0.0, 0.0), _swingarm)
	front_sp.rotation.z = PI * 0.5
	var rear_sp := _mesh_instance(_cylinder(rear_r, 0.008), sprocket_mat, Vector3(-0.12, 0.0, 0.0), _rear_wheel)
	rear_sp.rotation.z = PI * 0.5
	var chain_mat := _mat(Color(0.12, 0.12, 0.12), 0.8, 0.5)
	for side in [-1.0, 1.0]:
		_box(Vector3(-0.125, side * lerpf(front_r, rear_r, 0.5), arm_len * 0.5), Vector3(0.012, 0.012, arm_len), chain_mat, _swingarm)

	# ------------------------------------------------------------------ shock(s)
	_current_slot = "shock"
	var shock_part := PartsDB.get_part(p["shock"])
	if shock_part.get("layout", "mono") == "twin":
		var gas: bool = p["shock"] == "twin_shock_gas"
		var spring_mat := _mat(Color(0.85, 0.15, 0.1), 0.4, 0.4) if gas else _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
		for side in [-1.0, 1.0]:
			_tube(Vector3(0.12 * side, 0.02, arm_len - 0.08), Vector3(0.12 * side, 0.3, arm_len - 0.2), 0.025, spring_mat, Vector3.ONE, _swingarm)
			if gas:
				_tube(Vector3(0.155 * side, 0.22, arm_len - 0.17), Vector3(0.155 * side, 0.32, arm_len - 0.21), 0.016, _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2), Vector3.ONE, _swingarm)
	else:
		var colors := {"sport_mono": Color(0.85, 0.12, 0.1), "enduro_mono": Color(0.15, 0.35, 0.8)}
		var col: Color = colors.get(str(p["shock"]), Color(0.95, 0.75, 0.1))
		_tube(_pivot + Vector3(0.0, 0.05, 0.08), Vector3(0.0, seat_y - 0.14, _pivot.z + 0.02), 0.035, _mat(col, 0.3, 0.4))

	_apply_visibility()
	_current_slot = ""
	if with_rider:
		_build_rider(seat_y, seat_front, tail)
	update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


func _make_wheel(radius: float, width: float, style: String) -> Node3D:
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.92)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
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
		_slot_meshes[_current_slot].append(mmi)
	else:
		var rim_mat := _mat(Color(0.03, 0.03, 0.03), 0.3, 0.5) if style == "road" else _mat(Color(0.75, 0.6, 0.15), 0.9, 0.25)
		var rim := _mesh_instance(_cylinder(rim_r, width * 0.5), rim_mat, Vector3.ZERO, wheel)
		rim.rotation.z = PI * 0.5
		for i in 5:
			var a := TAU * i / 5.0
			var spoke := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.5, Vector3(0.04, rim_r * 0.95, 0.028), chrome, wheel)
			spoke.rotation.x = -a
	var hub := _mesh_instance(_cylinder(0.05, 0.14), chrome, Vector3.ZERO, wheel)
	hub.rotation.z = PI * 0.5
	return wheel


func _make_brake(wheel: Node3D, hub: Node3D, style: String, front: bool, radius: float) -> void:
	var steel := _mat(Color(0.7, 0.71, 0.73), 1.0, 0.3)
	var caliper := _mat(Color(0.75, 0.1, 0.08) if style == "twin" else Color(0.15, 0.15, 0.16), 0.5, 0.35)
	if style == "drum":
		var drum := _mesh_instance(_cylinder(0.1, 0.09), _mat(Color(0.6, 0.6, 0.6), 0.9, 0.4), Vector3.ZERO, wheel)
		drum.rotation.z = PI * 0.5
		_box(Vector3(0.07, -0.05, 0.0), Vector3(0.02, 0.03, 0.12), caliper, hub)  # brake arm
		return
	var disc_r := minf(radius * 0.52, 0.16) if front else minf(radius * 0.4, 0.12)
	var sides := [1.0]
	if front and style == "twin":
		sides = [1.0, -1.0]
	for side in sides:
		var disc := _mesh_instance(_cylinder(disc_r, 0.006, -1.0, 10 if style == "wave" else 32), steel, Vector3(0.06 * side, 0.0, 0.0), wheel)
		disc.rotation.z = PI * 0.5
		_box(Vector3(0.075 * side, disc_r * 0.6, disc_r * 0.6), Vector3(0.04, 0.07, 0.1), caliper, hub)


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
## Each body carries metadata "slot", plus everything in `meta`.
func build_pickers(meta: Dictionary) -> void:
	clear_pickers()
	for slot in _slot_meshes:
		if not is_fitted(slot):
			continue
		var body := StaticBody3D.new()
		body.name = "Pick_" + slot
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		body.set_meta("slot", slot)
		for key in meta:
			body.set_meta(key, meta[key])
		for mi in _slot_meshes[slot]:
			if mi is MultiMeshInstance3D or str(mi.name).begins_with("Spoke"):
				continue
			var xf := _local_xform(mi)
			var aabb: AABB = (mi as VisualInstance3D).get_aabb()
			var shape := BoxShape3D.new()
			shape.size = (aabb.size * xf.basis.get_scale()).max(Vector3(0.03, 0.03, 0.03))
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = Transform3D(xf.basis.orthonormalized(), xf * aabb.get_center())
			body.add_child(cs)
		add_child(body)


## Frees every mesh that isn't part of `slot`, for showing one loose part on its own.
func strip_to(slot: String) -> void:
	for s in _slot_meshes:
		if s == slot:
			continue
		for mi in _slot_meshes[s]:
			mi.free()
		_slot_meshes[s] = []


## A single loose part, sitting with its base on the origin.
static func part_display(part_id: String, cond: Dictionary) -> Node3D:
	var slot := PartsDB.slot_of(part_id)
	var parts: Dictionary = PartsDB.DEFAULT_BUILD.duplicate()
	parts[slot] = part_id
	var model := BikeModel.new()
	model.build_from(BikeBuild.new(parts, {slot: cond}), Color(0.55, 0.56, 0.58), {slot: true}, {slot: cond}, false)
	model.strip_to(slot)
	var bounds := model.slot_bounds(slot)
	var root := Node3D.new()
	root.add_child(model)
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	root.set_meta("size", bounds.size)
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
