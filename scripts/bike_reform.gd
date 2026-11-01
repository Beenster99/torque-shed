class_name BikeReform
extends RefCounted
## Rig built look: the frame re-forming round a new engine. When a bike's engine (or anything
## else that moves the rig's lines) changes in the configurator or the shed, the model is drawn
## afresh round the new rig (see BikeRig), and then shown morphing there from where the old rig
## had everything over LENGTH seconds: each of the model's meshes gets a blend shape from its old
## shape to its new one, and BikeModel turns it up. Once it's there the plain meshes go back.
##
## The old shape is worked out from the two rigs, not drawn again: each of the rig's datums (the
## crank and the engine's corners, the tank's nose and tail, the seat, the tail, the pegs) has
## moved by so much, the head stock, the pivot and the wheels not at all, and every point in
## between moves by a blend of the nearest ones' moves (all of the engine by the crank's) (laid out once on a grid down the bike's
## side, so it's cheap however many points the meshes have). It only changes the picture.

const LENGTH := 0.5
## Less than this far (m) and nothing's worth showing move.
const MIN_MOVE := 0.004
## The grid the moves are laid out on: its cell (m), and how far it reaches round the wheels.
const CELL := 0.04
const REACH := 0.6
## How far round the engine its move fades into its neighbours' (m).
const ENGINE_EDGE := 0.06


## The morph from `old_rig` to `model`'s own rig, started (as [{"mi", "src"}] to hand to step
## and finish), or [] when there's nothing to show: no old rig, another frame, or no move.
static func start(model: BikeModel, old_rig: Dictionary) -> Array:
	var rig := model.rig
	if rig.is_empty() or old_rig.is_empty() or str(old_rig.get("frame", "")) != str(rig.get("frame", "")):
		return []
	var pts := _datums(model, old_rig)
	var most := 0.0
	for p in pts:
		most = maxf(most, (p[1] as Vector3).length())
	if most < MIN_MOVE:
		return []
	var grid := _grid(model, pts, model.rig["engine_box"], pts[0][1])
	var out := []
	for c in model.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var morphed := _morphed(mi.mesh, mi.transform, grid)
		if morphed == null:
			continue
		out.append({"mi": mi, "src": mi.mesh})
		mi.mesh = morphed
		mi.set_blend_shape_value(0, 0.0)
	return out


## Shows the morph `t` seconds in.
static func step(morph: Array, t: float) -> void:
	var f := smoothstep(0.0, 1.0, clampf(t / LENGTH, 0.0, 1.0))
	for m in morph:
		var mi: MeshInstance3D = m["mi"]
		if is_instance_valid(mi):
			mi.set_blend_shape_value(0, f)


## Puts each mesh back as it was drawn.
static func finish(morph: Array) -> void:
	for m in morph:
		var mi: MeshInstance3D = m["mi"]
		if is_instance_valid(mi):
			mi.mesh = m["src"]


## The datums as [where now, how far it's come], the fixed ones too.
static func _datums(model: BikeModel, old_rig: Dictionary) -> Array:
	var rig := model.rig
	var out := []
	var crank: Vector3 = rig["crank"]
	var moved: Vector3 = crank - (old_rig["crank"] as Vector3)
	var hard: Dictionary = rig["hard"]
	# The engine moves as one: its crank, its corners and its heads.
	out.append([crank, moved])
	for key in ["head_front", "head_rear", "sump", "case_front", "case_rear", "output"]:
		out.append([crank + (hard[key] as Vector3), moved])
	var box: AABB = rig["engine_box"]
	for fy in [0.0, 0.5, 1.0]:
		for fz in [0.0, 0.5, 1.0]:
			out.append([box.position + box.size * Vector3(0.5, fy, fz), moved])
	for key in ["tank_nose", "tank_rear", "seat_front", "tail", "hip", "peg", "knee_r"]:
		if rig.has(key) and old_rig.has(key):
			out.append([rig[key], (rig[key] as Vector3) - (old_rig[key] as Vector3)])
	var spine: PackedVector3Array = rig["spine"]
	var was: PackedVector3Array = old_rig["spine"]
	if spine.size() > 0 and was.size() > 0:
		out.append([spine[spine.size() - 1], spine[spine.size() - 1] - was[was.size() - 1]])
	# The frame's own points, which the rig doesn't move.
	var b := model._build
	for p: Vector3 in [model._head, model._head_bottom, model._pivot, Vector3(0.0, 0.0, b.wheelbase * 0.5),
			Vector3(0.0, b.front_radius - b.rear_radius, -b.wheelbase * 0.5)]:
		out.append([p, Vector3.ZERO])
	return out


## The moves laid out on a grid down the bike's side (y and z; they're much the same across it).
static func _grid(model: BikeModel, pts: Array, engine: AABB, moved: Vector3) -> Dictionary:
	var b := model._build
	var z0 := -b.wheelbase * 0.5 - b.front_radius - REACH
	var y0 := -b.rear_radius - 0.1
	var nz := ceili((b.wheelbase + b.front_radius + b.rear_radius + REACH * 2.0) / CELL) + 1
	var ny := ceili((1.6 + 0.1) / CELL) + 1
	var cells := PackedVector3Array()
	cells.resize(nz * ny)
	for j in ny:
		for i in nz:
			var p := Vector2(z0 + i * CELL, y0 + j * CELL)
			var sum := Vector3.ZERO
			var w := 0.0
			for d in pts:
				var at: Vector3 = d[0]
				var dd := p.distance_squared_to(Vector2(at.z, at.y)) + 0.002
				var k := 1.0 / (dd * dd)
				sum += (d[1] as Vector3) * k
				w += k
			# (Over the engine itself, it all moves as one.)
			var out := maxf(maxf(engine.position.z - p.x, p.x - engine.end.z), maxf(engine.position.y - p.y, p.y - engine.end.y))
			cells[j * nz + i] = (sum / w).lerp(moved, 1.0 - smoothstep(0.0, ENGINE_EDGE, out))
	return {"cells": cells, "z0": z0, "y0": y0, "nz": nz, "ny": ny}


## `mesh` with one blend shape, "reform", its base the old shape and the shape the mesh as drawn
## (`xf` places it in the model), or null when it can't be done (a mesh with nothing to move).
static func _morphed(mesh: Mesh, xf: Transform3D, grid: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	am.add_blend_shape("reform")
	var to_mesh := xf.basis.inverse()
	var cells: PackedVector3Array = grid["cells"]
	var z0: float = grid["z0"]
	var y0: float = grid["y0"]
	var nz: int = grid["nz"]
	var ny: int = grid["ny"]
	var custom := 0
	for i in 4:
		custom |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + i * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var am_src := mesh as ArrayMesh
		if verts.is_empty() or (am_src != null and am_src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES):
			return null
		var old := verts.duplicate()
		for v in verts.size():
			var p := xf * verts[v]
			var fz := clampf((p.z - z0) / CELL, 0.0, nz - 1.001)
			var fy := clampf((p.y - y0) / CELL, 0.0, ny - 1.001)
			var iz := int(fz)
			var iy := int(fy)
			fz -= iz
			fy -= iy
			var at := iy * nz + iz
			var d := cells[at].lerp(cells[at + 1], fz).lerp(cells[at + nz].lerp(cells[at + nz + 1], fz), fy)
			old[v] = verts[v] - to_mesh * d
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = verts
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		arrays[Mesh.ARRAY_VERTEX] = old
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape], {}, (am_src.surface_get_format(s) & custom) if am_src != null else 0)
		am.surface_set_material(s, mesh.surface_get_material(s))
	return am
