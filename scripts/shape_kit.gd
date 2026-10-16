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


## A faceted shell: flat panels with crisp creases between them, for angular bodywork (a sports
## bike's fairing) where a loft would come out round. `rows` holds one PackedVector3Array per
## section, nose to tail (Z increasing): the profile's points in order, each crease a point. With
## `mirror` each row is the right half, from its free edge in to the centre line, and the left half
## is mirrored to match (left edge, centre, right edge). The panels are smooth along the length and
## sharp across each crease; both faces are drawn. `flip` turns the outside round for a profile
## that runs the other way (a belly pan, edge down to keel).
static func facets(rows: Array, mirror := true, flip := false) -> ArrayMesh:
	var full := []
	for r in rows:
		var pts: PackedVector3Array = r
		var row := PackedVector3Array()
		if mirror:
			for k in pts.size() - 1:
				row.append(Vector3(-pts[k].x, pts[k].y, pts[k].z))
			row.append(pts[pts.size() - 1])
			for k in range(pts.size() - 2, -1, -1):
				row.append(pts[k])
		else:
			row = pts
		full.append(row)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var count := full.size()
	if count < 2:
		return ArrayMesh.new()
	var width: int = (full[0] as PackedVector3Array).size()
	for k in width - 1:
		var base := verts.size()
		for i in count:
			var row: PackedVector3Array = full[i]
			var prev: PackedVector3Array = full[maxi(i - 1, 0)]
			var next: PackedVector3Array = full[mini(i + 1, count - 1)]
			var along := (next[k] + next[k + 1]) - (prev[k] + prev[k + 1])
			if along.length() < 0.0001:
				along = Vector3.BACK   # where a patch's slanted end pinches its rows together
			var nrm := along.cross(row[k + 1] - row[k]).normalized() * (-1.0 if flip else 1.0)
			for p in [row[k], row[k + 1]]:
				verts.append(p)
				normals.append(nrm)
				uvs.append(Vector2(float(k) / maxf(width - 1, 1), float(i) / (count - 1)))
		for i in count - 1:
			var a := base + i * 2
			_tri(idx, verts, normals, a, a + 2, a + 1)
			_tri(idx, verts, normals, a + 1, a + 2, a + 3)
	_inside_face(verts, normals, uvs, idx)
	return _commit(verts, normals, uvs, idx)


## A flat polygon (a nose cap or a mouth), fanned from its middle, facing `out`; both faces drawn.
static func fan(points: PackedVector3Array, out: Vector3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var mid := Vector3.ZERO
	for p in points:
		mid += p
	mid /= maxf(points.size(), 1)
	verts.append(mid)
	for p in points:
		verts.append(p)
	for k in verts.size():
		normals.append(out.normalized())
		uvs.append(Vector2.ZERO)
	for j in points.size() - 1:
		_tri_facing(idx, verts, 0, 1 + j, 2 + j, out)
	_inside_face(verts, normals, uvs, idx)
	return _commit(verts, normals, uvs, idx)


## A thin flat slab with sharp edges: the polygon `outline` (roughly flat, convex) thickened by
## `thick` either side of its plane. Winglets, endplates, lamp slits, vents.
static func plate(outline: PackedVector3Array, thick: float) -> ArrayMesh:
	var n := Vector3.ZERO
	var mid := Vector3.ZERO
	var count := outline.size()
	for k in count:
		var a := outline[k]
		var b := outline[(k + 1) % count]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		mid += a
	n = n.normalized() if n.length() > 0.000001 else Vector3.UP
	mid /= maxf(count, 1)
	var off := n * thick * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for face in [1.0, -1.0]:
		var base := verts.size()
		verts.append(mid + off * face)
		normals.append(n * face)
		for p in outline:
			verts.append(p + off * face)
			normals.append(n * face)
		for k in count:
			_tri_facing(idx, verts, base, base + 1 + k, base + 1 + (k + 1) % count, n * face)
	for k in count:
		var a := outline[k]
		var b := outline[(k + 1) % count]
		var side := (b - a).cross(n).normalized()
		if side.dot((a + b) * 0.5 - mid) < 0.0:
			side = -side
		var base := verts.size()
		for p in [a + off, b + off, a - off, b - off]:
			verts.append(p)
			normals.append(side)
		_tri_facing(idx, verts, base, base + 1, base + 2, side)
		_tri_facing(idx, verts, base + 1, base + 3, base + 2, side)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	return _commit(verts, normals, uvs, idx)


## Adds the inside face of an open surface: the same triangles wound the other way, normals in.
static func _inside_face(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
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
