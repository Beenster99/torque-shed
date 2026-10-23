class_name RiderRagdoll
extends RigidBody3D
## The rider thrown from the bike in a crash: a tumbling body with a helmet.

func _init() -> void:
	mass = 75.0
	collision_layer = 32
	collision_mask = 1
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.15
	physics_material_override = pm
	angular_damp = 0.8
	linear_damp = 0.1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.1, 0.12, 0.16)
	body_mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 1.25
	body.mesh = capsule
	body.material_override = body_mat
	body.name = "Body"
	body.position.y = -0.15
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
	helmet.position.y = 0.62
	helmet.name = "Helmet"
	add_child(helmet)


## Puts the rider's gear on (slot -> RiderGear item id, `tint` their colour): the jacket on the
## body and their helmet in place of the plain one. Empty gear leaves them as they are.
func dress(gear: Dictionary, tint: Color) -> void:
	if gear.is_empty():
		return
	var worn := RiderGear.clean_worn(gear)
	if tint.a <= 0.0:
		tint = Color(0.85, 0.2, 0.15)
	(get_node("Body") as MeshInstance3D).material_override = RiderFigure.material(str(worn["jacket"]), tint)
	var plain := get_node("Helmet") as MeshInstance3D
	plain.visible = false
	RiderFigure.helmet(self, plain.position, 0.15, str(worn["helmet"]), tint, 1, true, worn)
