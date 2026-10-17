class_name Trailer
extends RigidBody3D
## The recovery truck's motorbike trailer: a single-axle flatbed with two wheel channels, a
## fold-down ramp at the back (it stows upright as the tailgate), a hand winch on a post at the
## front with its cable, ratchet strap anchors either side of each channel, the dolly tray (a
## wheeled bike skate) hung on its side rail, and an A-frame drawbar to the coupler on the truck's
## tow ball, held there by a ball joint (PinJoint3D) so it follows the truck properly.
##
## Its two wheels are RayWheels like the truck's. Driven, it works out what the bikes on its bed
## feel (see _move_loads): an unstrapped bike surges into the front chock under hard braking and
## goes over the side, and tips off in a hard corner; a strapped one stays put.
##
## Local axes as the truck's: forward -Z, up +Y, origin on the ground under the middle of the bed.

signal load_moved(bike_id: int, z: float)
signal load_fell(bike_id: int, side: float, speed: float)

const G := 9.81
const MASS := 330.0
const AXLE_Z := 0.25
const HALF_TRACK := 0.92
const RADIUS := 0.28
const TRAVEL := 0.13
const SPRING := 32000.0
const MOUNT_Y := RADIUS + TRAVEL - 0.05
const BED_Y := 0.62
const BED_FRONT := -1.6
const BED_REAR := 1.45
const BED_HALF_W := 0.95
const COUPLER := Vector3(0.0, 0.5, -3.1)
## The two wheel channels, by x, and where a loaded bike's middle sits along them.
const SLOTS_X := [-0.47, 0.47]
const SLOT_Z := -0.15
const RAMP_LEN := 1.9
const RAMP_ANGLE := 0.33   # radians down from the bed when it's lowered onto the ground
const RAMP_W := 1.28       # across both channels and the walkway between them
const RAMP_TOP := 0.02     # the deck's top above the hinge line
const WINCH := Vector3(0.0, BED_Y + 0.5, -1.48)
## How far a loose bike can roll along its channel: forward into the chock, back to the tailgate.
const CHOCK_GAP := 0.25
const TAIL_GAP := 0.3
## Grip holding a bike on the bed against the trailer's acceleration (as a share of g): a bike
## loose in its channel rolls; one strap holds it a good deal better; the front pair hold it.
const HOLD_LOOSE := 0.12
const HOLD_ONE := 0.5
## Side-to-side g a bike takes before it goes over: loose, and with a single strap.
const TIP_LOOSE := 0.35
const TIP_ONE := 0.6
## Hitting the chock faster than this knocks a loose bike over the side.
const CHOCK_KNOCK := 1.2

var wheels: Array = []
var ramp_down := false
var car: Car
var joint: PinJoint3D
var model: Node3D
## Bikes on the bed being moved by the driving, bike id -> {z, v, straps}.
var load_sim := {}
var _ramp_pivot: Node3D
var _ramp_angle := -PI * 0.5
var _ramp_shape: CollisionShape3D
var _wheel_nodes: Array = []
var _v_prev := Vector3.INF
var _acc := Vector3.ZERO       # the bed's acceleration, its own axes, smoothed
var dolly_stowed: Node3D       # the dolly hung on the side rail (RecoveryView shows or hides it)
var winch_drum: Node3D


func _init() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.5, AXLE_Z - 0.15)
	inertia = Vector3(420.0, 450.0, 160.0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.3
	can_sleep = false
	collision_layer = 2
	collision_mask = 1 | 2
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var tyre := RayWheel.car_tyre(165.0, 1.0)
	for x in [-HALF_TRACK, HALF_TRACK]:
		var w := RayWheel.make(Vector3(x, MOUNT_Y, AXLE_Z), RADIUS, TRAVEL, SPRING, 1500.0, 2300.0, 0.8, tyre)
		wheels.append(w)
	var bed := BoxShape3D.new()
	bed.size = Vector3(BED_HALF_W * 2.0, 0.14, BED_REAR - BED_FRONT)
	var cs := CollisionShape3D.new()
	cs.shape = bed
	cs.position = Vector3(0.0, BED_Y - 0.07, (BED_REAR + BED_FRONT) * 0.5)
	add_child(cs)
	var bar := BoxShape3D.new()
	bar.size = Vector3(0.3, 0.12, 1.3)
	var cs2 := CollisionShape3D.new()
	cs2.shape = bar
	cs2.position = Vector3(0.0, 0.52, -2.35)
	add_child(cs2)
	# The front board, so you don't walk off the front of the bed onto the drawbar.
	var board := BoxShape3D.new()
	board.size = Vector3(BED_HALF_W * 2.0, 0.5, 0.06)
	var cs3 := CollisionShape3D.new()
	cs3.shape = board
	cs3.position = Vector3(0.0, BED_Y + 0.25, BED_FRONT - 0.02)
	add_child(cs3)
	# The lowered ramp, to walk up onto the bed: a slab whose top is the ramp's deck, running
	# from the hinge to just past its foot (so it meets the ground without a lip). Only there
	# while the ramp is down.
	var ramp := BoxShape3D.new()
	var len := RAMP_LEN + 0.12
	ramp.size = Vector3(RAMP_W, 0.06, len)
	_ramp_shape = CollisionShape3D.new()
	_ramp_shape.name = "RampShape"
	_ramp_shape.shape = ramp
	var along := Vector3(0.0, -sin(RAMP_ANGLE), cos(RAMP_ANGLE))
	var up := Vector3(0.0, cos(RAMP_ANGLE), sin(RAMP_ANGLE))
	_ramp_shape.transform = Transform3D(Basis(Vector3.RIGHT, RAMP_ANGLE),
		Vector3(0.0, BED_Y, BED_REAR) + along * len * 0.5 + up * (RAMP_TOP - 0.03))
	_ramp_shape.disabled = true
	add_child(_ramp_shape)
	_build_model()


## Couples the trailer to `to`: lined up behind it with the coupler on the tow ball and a ball
## joint between them.
func hitch_to(to: Car) -> void:
	unhitch()
	car = to
	var b := to.global_basis
	var at := to.hitch_point() - b * COUPLER
	place(Transform3D(b, at))
	attach()


## The ball joint on the tow ball, wherever the two stand now.
func attach() -> void:
	if car == null:
		return
	if joint:
		joint.free()
	add_collision_exception_with(car)
	joint = PinJoint3D.new()
	joint.name = "Hitch"
	car.get_parent().add_child(joint)
	joint.global_position = car.hitch_point()
	joint.node_a = joint.get_path_to(car)
	joint.node_b = joint.get_path_to(self)


func unhitch() -> void:
	if joint:
		joint.queue_free()
		joint = null


## Whether the ramp is down and can be walked up.
func ramp_walkable() -> bool:
	return not _ramp_shape.disabled


## Whether `p` (a world point: someone's feet) is up on the bed or the ramp.
func carries(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < BED_HALF_W + 0.15 and l.z > BED_FRONT - 0.3 and l.z < ramp_foot_z() - 0.4 \
		and l.y > _surface_at(l.z) - 0.1 and l.y < BED_Y + 2.5 and l.y > 0.15


func place(xf: Transform3D) -> void:
	global_transform = xf
	if is_inside_tree():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_v_prev = Vector3.INF
	for w in wheels:
		w["omega"] = 0.0


## The bikes on the bed weigh it down: `masses` is [[mass, local position]...].
func set_loads(masses: Array) -> void:
	var m := MASS
	var moment := Vector3(0.0, 0.5, AXLE_Z - 0.15) * MASS
	for e in masses:
		m += float(e[0])
		moment += (e[1] as Vector3) * float(e[0])
	mass = m
	center_of_mass = moment / m


## Where a bike's view stands on the trailer (its own space) in channel `slot`, `s` metres of
## the way from the foot of the ramp up onto its place on the bed (s_end() is there), slid
## `slide` metres along the bed (+ towards the back), and tipped over on its side when `tipped`.
## A bike's view stands on the ground under its middle; `wb` is its wheelbase.
static func load_transform(slot: int, s: float, slide := 0.0, tipped := false, wb := 1.4) -> Transform3D:
	var x: float = SLOTS_X[clampi(slot, 0, SLOTS_X.size() - 1)]
	var z := start_z() - clampf(s, 0.0, s_end()) + slide
	var front := _surface_at(z - wb * 0.5)
	var rear := _surface_at(z + wb * 0.5)
	var pitch := atan2(front - rear, wb)
	var basis := Basis(Vector3.RIGHT, pitch)
	if tipped:
		basis = basis * Basis(Vector3.BACK, deg_to_rad(68.0) * signf(x))
	return Transform3D(basis, Vector3(x, (front + rear) * 0.5, z))


## Where a bike's middle stands to be winched on: on the ground behind the lowered ramp, its
## front wheel at the foot (trailer space, z).
static func start_z() -> float:
	return ramp_foot_z() + 0.8


static func ramp_foot_z() -> float:
	return BED_REAR + RAMP_LEN * cos(RAMP_ANGLE)


## How far a bike travels from the ramp foot to its place on the bed.
static func s_end() -> float:
	return start_z() - SLOT_Z


## The height of what a wheel rolls on at `z` along the trailer: the bed, the ramp, the ground.
static func _surface_at(z: float) -> float:
	if z <= BED_REAR:
		return BED_Y
	var foot := ramp_foot_z()
	if z >= foot:
		return 0.0
	return BED_Y * (foot - z) / (foot - BED_REAR)


func _physics_process(delta: float) -> void:
	_ramp_angle = move_toward(_ramp_angle, RAMP_ANGLE if ramp_down else -PI * 0.5, delta * 2.5)
	var walkable := ramp_down and absf(_ramp_angle - RAMP_ANGLE) < 0.02
	if _ramp_shape.disabled == walkable:
		_ramp_shape.set_deferred("disabled", not walkable)
	if freeze:
		_update_model()
		return
	var space := get_world_3d().direct_space_state
	for w in wheels:
		RayWheel.step(self, w, delta, space, mass * 0.4, MASS * G * 0.4)
	var v := linear_velocity
	apply_central_force(-0.5 * 1.225 * 0.6 * v.length() * v)
	_move_loads(delta)
	_update_model()


## What the bikes on the bed feel as it's towed: the bed's acceleration (its own axes, smoothed
## a touch) against the grip holding each bike there. Along the bed a loose bike rolls into the
## chock or back to the tailgate; hit the chock hard and it goes over the side, as it does when
## the bed corners harder than it can stand up to.
func _move_loads(delta: float) -> void:
	var v := linear_velocity
	if _v_prev == Vector3.INF:
		_v_prev = v
	var acc := global_basis.inverse() * ((v - _v_prev) / delta)
	_v_prev = v
	_acc = _acc.lerp(acc, 1.0 - exp(-delta / 0.06))
	for id in load_sim.keys():
		var l: Dictionary = load_sim[id]
		var straps := int(l.get("straps", 0))
		var secure := bool(l.get("secure", false))
		if secure:
			l["v"] = 0.0
			continue
		var hold := (HOLD_ONE if straps > 0 else HOLD_LOOSE) * G
		var tip := (TIP_ONE if straps > 0 else TIP_LOOSE) * G
		if absf(_acc.x) > tip:
			load_sim.erase(id)
			load_fell.emit(int(id), -signf(_acc.x), linear_velocity.length())
			continue
		# The bed accelerates under the bike; the bike carries on as it was, less what holds it.
		var push := -_acc.z
		var vel := float(l["v"])
		if absf(push) > hold:
			vel += (push - signf(push) * hold) * delta
		else:
			vel = move_toward(vel, 0.0, (hold - absf(push)) * delta)
		var z := float(l["z"]) + vel * delta
		if z < -CHOCK_GAP:
			if vel < -CHOCK_KNOCK:
				load_sim.erase(id)
				load_fell.emit(int(id), 1.0 if fmod(float(id), 2.0) == 0.0 else -1.0, linear_velocity.length())
				continue
			z = -CHOCK_GAP
			vel = 0.0
		elif z > TAIL_GAP:
			z = TAIL_GAP
			vel = -vel * 0.2
		l["v"] = vel
		if absf(z - float(l.get("sent", 0.0))) > 0.04:
			l["sent"] = z
			load_moved.emit(int(id), z)
		l["z"] = z


## The bed's acceleration (its own axes): + z is the bed slowing down when going forwards.
func bed_accel() -> Vector3:
	return _acc


func get_net_state() -> PackedFloat32Array:
	var q := global_basis.get_rotation_quaternion()
	var p := global_position
	return PackedFloat32Array([p.x, p.y, p.z, q.x, q.y, q.z, q.w, wheels[0]["spin"], wheels[1]["spin"],
		wheels[0]["compression"], wheels[1]["compression"]])


const NET_SIZE := 11


func set_net_state(s: PackedFloat32Array, at := 0) -> void:
	if s.size() < at + NET_SIZE:
		return
	global_transform = Transform3D(Basis(Quaternion(s[at + 3], s[at + 4], s[at + 5], s[at + 6]).normalized()),
		Vector3(s[at], s[at + 1], s[at + 2]))
	wheels[0]["spin"] = s[at + 7]
	wheels[1]["spin"] = s[at + 8]
	wheels[0]["compression"] = s[at + 9]
	wheels[1]["compression"] = s[at + 10]


# ---------------------------------------------------------------------------- model

static func _mat(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A galvanised flatbed: chequer-plate deck, two wheel channels with chocks, side rails with the
## strap anchors, mudguards, an A-frame drawbar with a jockey wheel, the winch post, and the ramp.
func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var galv := _mat(Color(0.62, 0.64, 0.66), 0.7, 0.45)
	var deck := _mat(Color(0.5, 0.52, 0.54), 0.8, 0.35)
	var dark := _mat(Color(0.07, 0.07, 0.075), 0.0, 0.8)
	var yellow := _mat(Color(0.9, 0.7, 0.1), 0.2, 0.5)
	var red := _mat(Color(0.8, 0.05, 0.03), 0.0, 0.3)
	var len := BED_REAR - BED_FRONT
	var mid := (BED_REAR + BED_FRONT) * 0.5
	_box(model, Vector3(BED_HALF_W * 2.0, 0.06, len), Vector3(0.0, BED_Y - 0.03, mid), deck)
	_box(model, Vector3(BED_HALF_W * 2.0, 0.1, 0.08), Vector3(0.0, BED_Y - 0.09, BED_FRONT), galv)
	for x in [-BED_HALF_W, BED_HALF_W]:
		_box(model, Vector3(0.06, 0.16, len), Vector3(x, BED_Y + 0.05, mid), galv)
		# Mudguards over the wheels.
		_box(model, Vector3(0.3, 0.04, 0.8), Vector3(x * 0.97, BED_Y + 0.02, AXLE_Z), dark)
	for sx in SLOTS_X:
		# A channel either side of each wheel line and a chock at the front.
		for dx in [-0.07, 0.07]:
			_box(model, Vector3(0.025, 0.06, len - 0.3), Vector3(float(sx) + dx, BED_Y + 0.03, mid + 0.15), galv)
		_box(model, Vector3(0.18, 0.32, 0.06), Vector3(float(sx), BED_Y + 0.16, SLOT_Z - 1.3),
			galv, Vector3(deg_to_rad(-25.0), 0.0, 0.0))
		for dz in [-0.95, 0.85]:
			for dx2 in [-0.42, 0.42]:
				_box(model, Vector3(0.06, 0.06, 0.06), Vector3(float(sx) + dx2, BED_Y + 0.03, SLOT_Z + dz), yellow)
	# The front board and the A-frame drawbar to the coupler, with a jockey wheel.
	_box(model, Vector3(BED_HALF_W * 2.0, 0.5, 0.05), Vector3(0.0, BED_Y + 0.25, BED_FRONT - 0.02), galv)
	for side: float in [-1.0, 1.0]:
		var from := Vector3(side * 0.7, 0.52, BED_FRONT)
		var to := COUPLER + Vector3(side * 0.06, 0.0, 0.1)
		var d := to - from
		var bar := _box(model, Vector3(0.08, 0.08, d.length()), (from + to) * 0.5, galv)
		bar.rotation.y = atan2(-d.x, -d.z) + PI
	_box(model, Vector3(0.12, 0.12, 0.3), COUPLER + Vector3(0.0, 0.0, 0.1), dark)
	_box(model, Vector3(0.05, 0.4, 0.05), Vector3(0.2, 0.3, -2.6), dark)
	# The winch post and drum.
	_box(model, Vector3(0.1, 0.55, 0.1), Vector3(0.0, BED_Y + 0.27, WINCH.z), galv)
	winch_drum = Node3D.new()
	winch_drum.position = WINCH
	model.add_child(winch_drum)
	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.2
	drum.mesh = cm
	drum.material_override = red
	drum.rotation.z = PI * 0.5
	winch_drum.add_child(drum)
	_box(winch_drum, Vector3(0.03, 0.03, 0.25), Vector3(0.14, 0.0, 0.1), dark)
	# Rear lamps.
	for x in [-0.8, 0.8]:
		_box(model, Vector3(0.18, 0.08, 0.05), Vector3(x, BED_Y - 0.1, BED_REAR + 0.02), red)
	# The ramp, hinged at the back of the bed.
	_ramp_pivot = Node3D.new()
	_ramp_pivot.position = Vector3(0.0, BED_Y, BED_REAR)
	model.add_child(_ramp_pivot)
	# A channel ramp for each wheel channel, with grip bars, joined by a cross bar at the top: it
	# stows upright as the tailgate and you can still see past it.
	for x in SLOTS_X:
		_box(_ramp_pivot, Vector3(0.34, 0.04, RAMP_LEN), Vector3(float(x), 0.0, RAMP_LEN * 0.5), deck)
		for side in [-1.0, 1.0]:
			_box(_ramp_pivot, Vector3(0.025, 0.06, RAMP_LEN), Vector3(float(x) + side * 0.17, 0.03, RAMP_LEN * 0.5), galv)
		for i in 8:
			_box(_ramp_pivot, Vector3(0.32, 0.02, 0.03), Vector3(float(x), 0.03, 0.15 + i * 0.22), galv)
	_box(_ramp_pivot, Vector3(1.3, 0.04, 0.05), Vector3(0.0, 0.0, 0.05), galv)
	# The dolly tray, hung on the left-hand rail.
	dolly_stowed = Node3D.new()
	dolly_stowed.position = Vector3(-BED_HALF_W - 0.06, BED_Y - 0.05, -0.1)
	dolly_stowed.rotation.z = PI * 0.5
	model.add_child(dolly_stowed)
	Trailer.build_dolly(dolly_stowed)
	# The wheels.
	var tyre_mat := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	for w in wheels:
		var holder := Node3D.new()
		model.add_child(holder)
		var spin := Node3D.new()
		holder.add_child(spin)
		var tyre := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = RADIUS
		tm.bottom_radius = RADIUS
		tm.height = 0.17
		tm.radial_segments = 20
		tyre.mesh = tm
		tyre.material_override = tyre_mat
		tyre.rotation.z = PI * 0.5
		spin.add_child(tyre)
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = RADIUS * 0.55
		hm.bottom_radius = RADIUS * 0.55
		hm.height = 0.18
		hm.radial_segments = 5
		hub.mesh = hm
		hub.material_override = galv
		hub.rotation.z = PI * 0.5
		spin.add_child(hub)
		_wheel_nodes.append([holder, spin])
	_update_model()


## The dolly tray: a long steel channel a bike stands in, on four swivel casters (its own space:
## along -Z, on the ground at y 0).
static func build_dolly(parent: Node3D) -> void:
	var steel := _mat(Color(0.85, 0.42, 0.06), 0.3, 0.5)
	var dark := _mat(Color(0.08, 0.08, 0.08), 0.0, 0.8)
	_box(parent, Vector3(0.3, 0.05, 2.1), Vector3(0.0, 0.11, 0.0), steel)
	for dx in [-0.13, 0.13]:
		_box(parent, Vector3(0.03, 0.08, 2.1), Vector3(dx, 0.16, 0.0), steel)
	for z in [-0.95, 0.95]:
		for x in [-0.12, 0.12]:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 0.04
			c.mesh = cm
			c.material_override = dark
			c.rotation.z = PI * 0.5
			c.position = Vector3(x, 0.045, z)
			parent.add_child(c)


func _update_model() -> void:
	if _ramp_pivot:
		_ramp_pivot.rotation.x = _ramp_angle
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var m: Vector3 = w["mount"]
		(_wheel_nodes[i][0] as Node3D).position = Vector3(m.x, m.y - (TRAVEL - float(w["compression"])), m.z)
		(_wheel_nodes[i][1] as Node3D).rotation.x = -float(w["spin"])
