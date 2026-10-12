class_name TestGround
extends StaticBody3D
## A large flat surface for physics tests.

func _init(size := 4000.0, surf := "tarmac") -> void:
	set_meta("surface", surf)
	collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 1.0, size)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.5
	add_child(cs)
