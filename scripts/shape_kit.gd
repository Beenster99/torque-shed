class_name ShapeKit
## Curved shapes for bike parts, built as meshes in code: lofts (a rounded cross-section swept
## fore and aft along the bike, for tanks, seats, fairing shells, cowls and fenders) and sweeps
## (a round tube bent along a smooth path, for exhaust headers and curved frame tubes).
##
## A loft section is a Dictionary:
##   c     Vector3  where the section's middle is (model space; the bike runs along Z)
##   w     float    half its width
##   up    float    how far it rises above c
##   down  float    how far it drops below c
##   n     float    squareness: 2 is an ellipse, 3-4 a rounded box, 6+ nearly square (default 2.4)
##   bw    float    the width of the lower half as a share of w, for a tank narrowing to its tunnel (default 1)
## Sections are joined in order, and each lies square to the path between its neighbours, so a
## seat cowl can sweep up at the back. An open loft draws only the arc from `a0` to `a1`
## (radians, 0 at the right side, PI/2 at the top), from both faces: a fairing shell or a fender.

const RING := 28


## A closed (capped) or open loft through `sections`.
static func loft(sections: Array, ring := RING, open := false, a0 := 0.0, a1 := TAU) -> ArrayMesh:
	var rows := []          # Array of PackedVector3Array, one ring of points per section
	var centres := []
	var tangents := []
	var count := sections.size()
	var span := (a1 - a0) if open else TAU
	var steps := ring if not open else maxi(4, roundi(ring * span / TAU))
	for i in count:
		var s: Dictionary = sections[i]
		var c: Vector3 = s["c"]
		var prev: Vector3 = (sections[maxi(i - 1, 0)] as Dictionary)["c"]
		var next: Vector3 = (sections[mini(i + 1, count - 1)] as Dictionary)["c"]
		var t := next - prev
		t.x = 0.0
		t = t.normalized() if t.length() > 0.0001 else Vector3.BACK
		var up := t.cross(Vector3.RIGHT).normalized()
		var w := float(s.get("w", 0.1))
		var hu := float(s.get("up", 0.1))
		var hd := float(s.get("down", hu))
		var e := 2.0 / float(s.get("n", 2.4))
		var bw := float(s.get("bw", 1.0))
		var pts := PackedVector3Array()
		var n_pts := steps + (1 if open else 0)
		for j in n_pts:
			var a := a0 + span * j / steps if open else -PI * 0.5 + TAU * j / steps
			var ca := cos(a)
			var sa := sin(a)
			var x := signf(ca) * pow(absf(ca), e) * w * (bw if sa < 0.0 else 1.0)
			var y := signf(sa) * pow(absf(sa), e) * (hu if sa > 0.0 else hd)
			pts.append(c + Vector3.RIGHT * x + up * y)
		rows.append(pts)
		centres.append(c)
		tangents.append(t)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var width: int = (rows[0] as PackedVector3Array).size()
	# The skin: a grid of rings, with smooth normals from the neighbouring points.
	for i in count:
		var row: PackedVector3Array = rows[i]
		for j in width:
			var jp := (j + 1) % width if not open else mini(j + 1, width - 1)
			var jm := (j - 1 + width) % width if not open else maxi(j - 1, 0)
			var across: Vector3 = row[jp] - row[jm]
			var along: Vector3 = (rows[mini(i + 1, count - 1)] as PackedVector3Array)[j] - (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var nrm := across.cross(along).normalized()
			if nrm.dot(row[j] - (centres[i] as Vector3)) < 0.0:
				nrm = -nrm
			verts.append(row[j])
			normals.append(nrm)
			uvs.append(Vector2(float(j) / maxf(width - 1, 1), float(i) / maxf(count - 1, 1)))
	for i in count - 1:
		for j in (width - 1 if open else width):
			var a := i * width + j
			var b := i * width + (j + 1) % width
			var c2 := (i + 1) * width + j
			var d := (i + 1) * width + (j + 1) % width
			_tri(idx, verts, normals, a, c2, b)
			_tri(idx, verts, normals, b, c2, d)
	if open:
		# The inside face of an open shell, wound the other way with its normals turned in.
		var base := verts.size()
		for k in base:
			verts.append(verts[k])
			normals.append(-normals[k])
			uvs.append(uvs[k])
		var n_idx := idx.size()
		for k in range(0, n_idx, 3):
			idx.append(idx[k] + base)
			idx.append(idx[k + 2] + base)
			idx.append(idx[k + 1] + base)
	else:
		# Flat caps at both ends.
		for end in [0, count - 1]:
			var row: PackedVector3Array = rows[end]
			var out: Vector3 = (tangents[end] as Vector3) * (-1.0 if end == 0 else 1.0)
			var mid := verts.size()
			verts.append(centres[end])
			normals.append(out)
			uvs.append(Vector2(0.5, 0.5))
			for j in width:
				verts.append(row[j])
				normals.append(out)
				uvs.append(Vector2(0.5 + 0.5 * cos(TAU * j / width), 0.5 + 0.5 * sin(TAU * j / width)))
			for j in width:
				_tri_facing(idx, verts, mid, mid + 1 + j, mid + 1 + (j + 1) % width, out)
	return _commit(verts, normals, uvs, idx)


## A round tube along `path` (smoothed into a curve), `radius` thick (a float, or one per
## path point to taper it), capped at both ends unless `caps` is false.
static func sweep(path: Array, radius, sides := 12, caps := true, per_seg := 6) -> ArrayMesh:
	var pts := smooth(path, per_seg)
	var radii := []
	if radius is Array:
		var smooth_r := smooth_floats(radius, per_seg)
		radii = smooth_r
	else:
		for k in pts.size():
			radii.append(float(radius))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var count := pts.size()
	if count < 2:
		return ArrayMesh.new()
	# Parallel-transport frames, so the tube doesn't twist round the bends.
	var t0: Vector3 = (pts[1] - pts[0]).normalized()
	var side := t0.cross(Vector3.UP)
	if side.length() < 0.01:
		side = t0.cross(Vector3.RIGHT)
	side = side.normalized()
	var tangents := []
	for i in count:
		var t: Vector3 = (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i > 0:
			var prev_t: Vector3 = tangents[i - 1]
			var axis := prev_t.cross(t)
			if axis.length() > 0.00001:
				side = side.rotated(axis.normalized(), prev_t.angle_to(t))
		side = (side - t * side.dot(t)).normalized()
		tangents.append(t)
		var up := t.cross(side).normalized()
		for j in sides + 1:
			var a := TAU * j / sides
			var nrm := side * cos(a) + up * sin(a)
			verts.append(pts[i] + nrm * float(radii[mini(i, radii.size() - 1)]))
			normals.append(nrm)
			uvs.append(Vector2(float(j) / sides, float(i) / (count - 1)))
	var ring := sides + 1
	for i in count - 1:
		for j in sides:
			var a := i * ring + j
			_tri(idx, verts, normals, a, a + ring, a + 1)
			_tri(idx, verts, normals, a + 1, a + ring, a + ring + 1)
	if caps:
		for end in [0, count - 1]:
			var out: Vector3 = (tangents[end] as Vector3) * (-1.0 if end == 0 else 1.0)
			var mid := verts.size()
			verts.append(pts[end])
			normals.append(out)
			uvs.append(Vector2(0.5, 0.5))
			for j in sides:
				verts.append(verts[end * ring + j])
				normals.append(out)
				uvs.append(Vector2(0.5, 0.5))
			for j in sides:
				_tri_facing(idx, verts, mid, mid + 1 + j, mid + 1 + (j + 1) % sides, out)
	return _commit(verts, normals, uvs, idx)


## A Catmull-Rom curve through `points`, `per_seg` steps between each pair.
static func smooth(points: Array, per_seg := 6) -> Array:
	if points.size() < 3:
		return points.duplicate()
	var out := []
	for i in points.size() - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, points.size() - 1)]
		for k in per_seg:
			var t := float(k) / per_seg
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(points[points.size() - 1])
	return out


## The same curve for a list of numbers (radii along a tube).
static func smooth_floats(values: Array, per_seg := 6) -> Array:
	if values.size() < 2:
		return values.duplicate()
	var out := []
	for i in values.size() - 1:
		for k in per_seg:
			out.append(lerpf(float(values[i]), float(values[i + 1]), float(k) / per_seg))
	out.append(float(values[values.size() - 1]))
	return out


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## A triangle wound so its face points along its vertices' normals (Godot's front faces wind
## clockwise, so (c - a) x (b - a) points out of the surface).
static func _tri(idx: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	_tri_facing(idx, verts, a, b, c, normals[a] + normals[b] + normals[c])


static func _tri_facing(idx: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, out: Vector3) -> void:
	var face := (verts[c] - verts[a]).cross(verts[b] - verts[a])
	if face.dot(out) >= 0.0:
		idx.append_array([a, b, c])
	else:
		idx.append_array([a, c, b])


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
