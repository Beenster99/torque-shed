class_name MeshJoin
## Quick helpers for folding many meshes into one (see BikeLookNew.bake and BikeModel.shape_mesh).
## They do with one engine call what a loop over every vertex would do, which matters because a
## bike is baked as it rides in (a customer's, the road traffic's): a vertex at a time it took a
## couple of hundred milliseconds, all in one frame.


## `v` moved by `xf`.
static func moved(v: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	return xf * v


## The normals `n` turned by `xf` (a mesh's own transform) and kept a unit long; straight up for
## each of `count` vertices where the mesh has none (or too few).
static func turned_normals(n, xf: Transform3D, count: int) -> PackedVector3Array:
	if not (n is PackedVector3Array) or (n as PackedVector3Array).size() < count:
		var up := PackedVector3Array()
		up.resize(count)
		up.fill(Vector3.UP)
		if n is PackedVector3Array:
			# As the loops this stands in for: the normals there are, then straight up.
			var nb := xf.basis.inverse().transposed()
			for i in (n as PackedVector3Array).size():
				up[i] = (nb * (n[i] as Vector3)).normalized()
		return up
	var normals := n as PackedVector3Array
	if normals.size() > count:
		normals = normals.slice(0, count)
	var nb := xf.basis.inverse().transposed()
	var out: PackedVector3Array = Transform3D(nb, Vector3.ZERO) * normals
	if nb.is_equal_approx(nb.orthonormalized()):
		return out   # a plain turn keeps every normal a unit long
	for i in out.size():
		out[i] = out[i].normalized()
	return out


## `four` (four floats) once for each of `count` vertices.
static func tiled(four: PackedFloat32Array, count: int) -> PackedFloat32Array:
	var out := four.duplicate()
	if count <= 0:
		return PackedFloat32Array()
	while out.size() < count * 4:
		out.append_array(out)
	out.resize(count * 4)
	return out


## The triangle list `idx` (or 0..count-1 where the mesh has none) with `base` added to each.
static func shifted_index(idx, base: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		var src := idx as PackedInt32Array
		if base == 0:
			return src.duplicate()
		out.resize(src.size())
		for i in src.size():
			out[i] = src[i] + base
		return out
	out.resize(count)
	for i in count:
		out[i] = base + i
	return out
