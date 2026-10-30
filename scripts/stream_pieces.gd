class_name StreamPieces
extends RefCounted
## The ride's ground and roads put in a piece at a time (Simon, 30 Oct: "lag spikes while riding"). A block's collision
## as one shape of twenty thousand triangles took Jolt 50 to 100 ms to take in when its body went into the world, and a
## town block's houses 20 ms more to make into meshes, all in one frame. Its collision is cut into PIECES x PIECES
## squares (on a worker, see split), and the bodies and the heavier meshes go in a few a frame within BUDGET_US (pump),
## each a millisecond or two.

## How many squares a side a block's collision is cut into.
const PIECES := 6
## How long a frame may spend putting bodies in (microseconds): at least one goes in each frame.
const BUDGET_US := 2500

## [[parent, node, or a Callable that makes the node]] waiting to go in, oldest first.
var waiting: Array = []


## `faces` (a triangle soup, local to a square block `size` m a side from its corner) cut into PIECES x PIECES squares
## by where each triangle's middle is: the soups that have any triangles in them. Any thread.
static func split(faces: PackedVector3Array, size: float) -> Array[PackedVector3Array]:
	var parts: Array[PackedVector3Array] = []
	parts.resize(PIECES * PIECES)
	var n := size / PIECES
	for t in range(0, faces.size() - 2, 3):
		var m := (faces[t] + faces[t + 1] + faces[t + 2]) / 3.0
		var k := clampi(int(m.z / n), 0, PIECES - 1) * PIECES + clampi(int(m.x / n), 0, PIECES - 1)
		parts[k].append_array([faces[t], faces[t + 1], faces[t + 2]])
	var out: Array[PackedVector3Array] = []
	for p in parts:
		if not p.is_empty():
			out.append(p)
	return out


## A shape for each of `parts` (split's), any thread.
static func shapes(parts: Array[PackedVector3Array]) -> Array[ConcavePolygonShape3D]:
	var out: Array[ConcavePolygonShape3D] = []
	for p in parts:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(p)
		out.append(shape)
	return out


## `node` (a body, say), or the node Callable `make` makes then, to go into `parent` when pump gets to it.
func add(parent: Node, node_or_make: Variant) -> void:
	waiting.append([parent, node_or_make])


## Puts waiting bodies in, oldest first, for up to BUDGET_US (at least one). Ones whose parent has gone are dropped.
func pump() -> void:
	var t0 := Time.get_ticks_usec()
	while not waiting.is_empty():
		var w: Array = waiting.pop_front()
		if not is_instance_valid(w[0]) or (w[0] as Node).is_queued_for_deletion():
			_drop(w[1])
			continue
		(w[0] as Node).add_child(_made(w[1]))
		if Time.get_ticks_usec() - t0 > BUDGET_US:
			return


## Drops everything waiting (the ride's over).
func clear() -> void:
	for w in waiting:
		_drop(w[1])
	waiting.clear()


## Whether anything is still waiting to go into `parent`.
func has(parent: Node) -> bool:
	return waiting.any(func(w): return w[0] == parent)


static func _made(v: Variant) -> Node:
	return (v as Callable).call() if v is Callable else v


static func _drop(v: Variant) -> void:
	if v is Node:
		(v as Node).free()
