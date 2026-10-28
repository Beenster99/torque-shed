class_name RiderRagdoll
extends RigidBody3D
## The rider thrown from the bike in a crash, and only then: a body (this, with the head and
## helmet on it) with arms and legs of two pieces each, jointed at the shoulders, elbows, hips and
## knees so they flop as the rider tumbles. Made when the bike goes down (Bike.crash) and gone
## when the rider's picked up (respawn), so nothing of it costs a thing while riding: nine small
## bodies for the few seconds of a crash, asleep once they've come to rest.
##
## Laid out in the seated pose, facing -Z (the bike's forward): thighs forward, shins down, arms
## out to the bars. launch() puts it where the rider was and sets it flying.

## The limbs: name, from, to (m in the body's space, from its middle), radius, mass, the joint at
## `from` (the piece it hangs off, how far it swings and twists, degrees), and what it's dressed in.
const LIMBS := [
	["UpperArmL", Vector3(-0.22, 0.22, 0.0), Vector3(-0.26, 0.12, -0.28), 0.055, 2.5, ["", 80.0, 40.0], "jacket"],
	["ForearmL", Vector3(-0.26, 0.12, -0.28), Vector3(-0.26, 0.08, -0.56), 0.05, 2.0, ["UpperArmL", 70.0, 20.0], "jacket"],
	["UpperArmR", Vector3(0.22, 0.22, 0.0), Vector3(0.26, 0.12, -0.28), 0.055, 2.5, ["", 80.0, 40.0], "jacket"],
	["ForearmR", Vector3(0.26, 0.12, -0.28), Vector3(0.26, 0.08, -0.56), 0.05, 2.0, ["UpperArmR", 70.0, 20.0], "jacket"],
	["ThighL", Vector3(-0.1, -0.3, 0.0), Vector3(-0.12, -0.32, -0.42), 0.08, 9.0, ["", 60.0, 25.0], "trousers"],
	["ShinL", Vector3(-0.12, -0.32, -0.42), Vector3(-0.12, -0.72, -0.4), 0.06, 5.0, ["ThighL", 65.0, 10.0], "boots"],
	["ThighR", Vector3(0.1, -0.3, 0.0), Vector3(0.12, -0.32, -0.42), 0.08, 9.0, ["", 60.0, 25.0], "trousers"],
	["ShinR", Vector3(0.12, -0.32, -0.42), Vector3(0.12, -0.72, -0.4), 0.06, 5.0, ["ThighR", 65.0, 10.0], "boots"],
]

## How many numbers a pose takes in a snapshot (see pose()): each piece's place and turn.
const POSE_SIZE := (1 + 8) * 7

## The arms and legs (RigidBody3D, set apart from the body: see launch()), by name.
var limbs := {}
var _mats := {}


func _init() -> void:
	mass = 34.0
	collision_layer = 32
	collision_mask = 1
	physics_material_override = _grip()
	angular_damp = 0.8
	linear_damp = 0.1
	can_sleep = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.19
	shape.height = 0.74
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	var head := SphereShape3D.new()
	head.radius = 0.14
	var hs := CollisionShape3D.new()
	hs.shape = head
	hs.position.y = 0.5
	add_child(hs)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.1, 0.12, 0.16)
	body_mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18
	capsule.height = 0.72
	body.mesh = capsule
	body.material_override = body_mat
	body.name = "Body"
	add_child(body)
	var helmet_mat := StandardMaterial3D.new()
	helmet_mat.albedo_color = Color(0.85, 0.2, 0.15)
	helmet_mat.metallic = 0.4
	helmet_mat.roughness = 0.15
	var helmet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	helmet.mesh = sphere
	helmet.material_override = helmet_mat
	helmet.position.y = 0.5
	helmet.name = "Helmet"
	add_child(helmet)
	_mats = {"jacket": body_mat, "trousers": body_mat, "boots": body_mat}
	for l in LIMBS:
		var limb := RigidBody3D.new()
		limb.name = l[0]
		limb.top_level = true   # moved by the physics, not with the body
		limb.mass = l[4]
		limb.collision_layer = 32
		limb.collision_mask = 1
		limb.physics_material_override = physics_material_override
		limb.angular_damp = 2.0
		limb.linear_damp = 0.1
		var len := (l[2] as Vector3).distance_to(l[1])
		var cap := CapsuleShape3D.new()
		cap.radius = l[3]
		cap.height = len + l[3] * 2.0
		var lcs := CollisionShape3D.new()
		lcs.shape = cap
		limb.add_child(lcs)
		var mesh := CapsuleMesh.new()
		mesh.radius = l[3]
		mesh.height = cap.height
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.material_override = body_mat
		limb.add_child(mi)
		add_child(limb)
		limbs[l[0]] = limb


static func _grip() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6   # leathers sliding down the road
	pm.bounce = 0.2
	return pm


## Puts the rider's gear on (slot -> RiderGear item id, `tint` their colour): the jacket on the
## body and arms, the trousers and boots on the legs, and their helmet in place of the plain one.
## Empty gear leaves them as they are.
func dress(gear: Dictionary, tint: Color) -> void:
	if gear.is_empty():
		return
	var worn := RiderGear.clean_worn(gear)
	if tint.a <= 0.0:
		tint = Color(0.85, 0.2, 0.15)
	for slot in ["jacket", "trousers", "boots"]:
		_mats[slot] = RiderFigure.material(str(worn[slot]), tint)
	(get_node("Body") as MeshInstance3D).material_override = _mats["jacket"]
	for l in LIMBS:
		((limbs[l[0]] as Node).get_node("Mesh") as MeshInstance3D).material_override = _mats[l[6]]
	var plain := get_node("Helmet") as MeshInstance3D
	plain.visible = false
	RiderFigure.helmet(self, plain.position, 0.15, str(worn["helmet"]), tint, 1, true, worn)


## Sets the rider off from `xf` (the body's middle, facing the bike's way) at `velocity`, spinning
## at `spin`: the arms and legs go where they'd be on the bike, moving with it, and are jointed on.
func launch(xf: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	global_transform = xf
	linear_velocity = velocity
	angular_velocity = spin
	for l in LIMBS:
		var limb: RigidBody3D = limbs[l[0]]
		var a: Vector3 = l[1]
		var b: Vector3 = l[2]
		var mid := (a + b) * 0.5
		limb.global_transform = xf * Transform3D(_along(b - a), mid)
		var off := xf.basis * mid
		limb.linear_velocity = velocity + spin.cross(off)
		limb.angular_velocity = spin
	for l in LIMBS:
		var j := ConeTwistJoint3D.new()
		j.name = "Joint" + str(l[0])
		j.top_level = true
		add_child(j)
		j.global_transform = Transform3D(xf.basis, xf * (l[1] as Vector3))
		var parent: Node = self if l[5][0] == "" else limbs[l[5][0]]
		j.node_a = j.get_path_to(parent)
		j.node_b = j.get_path_to(limbs[l[0]])
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(l[5][1]))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(l[5][2]))
		j.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)


## Moves the whole rider by -`d` (the world's origin moved on, see Bike).
func shift(d: Vector3) -> void:
	global_position -= d
	for n in limbs.values():
		(n as Node3D).global_position -= d


## Where every piece is, for the other players (Bike.get_net_state): its place from `from` (the
## bike's, so the snapshot's origin doesn't matter) and its turn, seven numbers a piece.
func pose(from: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Node3D in pieces():
		var o := p.global_position - from
		var q := p.global_basis.get_rotation_quaternion()
		out.append_array([o.x, o.y, o.z, q.x, q.y, q.z, q.w])
	return out


## Another player's rider thrown off, as their snapshots have it (RemoteBike): the same pieces,
## not simulated here and solid to nothing, put where show_pose() says.
static func puppet() -> RiderRagdoll:
	var r := RiderRagdoll.new()
	r.top_level = true
	for p: RigidBody3D in r.pieces():
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
	return r


## Puts a puppet's pieces in the pose between snapshots `a` and `b` (their poses from index `at`),
## `f` of the way from one to the other, about the bike's place `from` between them.
func show_pose(a: PackedFloat32Array, b: PackedFloat32Array, at: int, f: float, from: Vector3) -> void:
	var k := at
	for p: Node3D in pieces():
		var o := Vector3(a[k], a[k + 1], a[k + 2]).lerp(Vector3(b[k], b[k + 1], b[k + 2]), f)
		var q := Quaternion(a[k + 3], a[k + 4], a[k + 5], a[k + 6]).normalized().slerp(
			Quaternion(b[k + 3], b[k + 4], b[k + 5], b[k + 6]).normalized(), f)
		p.global_transform = Transform3D(Basis(q), from + o)
		k += 7


## Every piece of the rider: the body and its limbs.
func pieces() -> Array:
	return [self] + limbs.values()


## A basis with Y (a capsule's length) along `dir`.
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))
