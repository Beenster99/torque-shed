class_name WorldRoadMesh
extends RefCounted
## The meshes of a stretch of road (see WorldRoads): its running surface with sloping
## shoulders down to the grass, its collision faces, and its painted lines. Tarmac roads get
## edge lines and a dashed centre line; the loop gets red and white kerbs on the inside of its
## tighter corners instead of a centre line. Dirt tracks are crowned a little and fade to
## grassy edges.

const TARMAC := Color(0.16, 0.16, 0.17)
const VERGE := Color(0.38, 0.36, 0.31)
const DIRT := Color(0.52, 0.4, 0.27)
const DIRT_EDGE := Color(0.42, 0.4, 0.24)
const LINE := Color(0.92, 0.92, 0.88)
const KERB_RED := Color(0.78, 0.12, 0.1)
## Corners of the loop tighter than this radius get kerbs on the inside.
const KERB_RADIUS := 70.0
const PAINT_LIFT := 0.012


## The cross-section of `road`: [offsets from the centre line, heights relative to it,
## colours], left to right.
static func section(road: Dictionary) -> Array:
	var hw: float = road["hw"]
	if road["kind"] == "tarmac":
		return [[-hw - 1.3, -hw, hw, hw + 1.3], [-0.26, 0.0, 0.0, -0.26], [VERGE, TARMAC, TARMAC, VERGE]]
	return [[-hw - 0.9, -hw, 0.0, hw, hw + 0.9], [-0.24, 0.0, 0.03, 0.0, -0.24],
		[DIRT_EDGE, DIRT, DIRT.lightened(0.06), DIRT, DIRT_EDGE]]


## The running surface of samples `from`..`to` of `road`: [ArrayMesh, collision faces, centre],
## both about that centre.
static func surface(road: Dictionary, from: int, to: int) -> Array:
	var xz: PackedVector2Array = road["xz"]
	var hs: PackedFloat32Array = road["h"]
	var dirs: PackedVector2Array = road["dir"]
	var dist: PackedFloat32Array = road["dist"]
	var n := xz.size()
	var sec := section(road)
	var offs: Array = sec[0]
	var drops: Array = sec[1]
	var cols: Array = sec[2]
	var w := offs.size()
	var mid := ((from + to) / 2) % n
	var center := Vector3(xz[mid].x, hs[mid], xz[mid].y)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var length: float = road["length"]
	var mouths: Array = road.get("mouths", [])
	var first := 0           # the rows drawn: from the last lying wholly on the edge of a road it
	var last := to - from    # starts from, to the first lying wholly on the edge of one it ends on
	for k in range(from, to + 1):
		var i := k % n
		var p := Vector3(xz[i].x, hs[i], xz[i].y) - center
		var right := Vector3(-dirs[i].y, 0.0, dirs[i].x)
		var along: float = dist[i] if k < n else length
		var on_edge := 0
		var ends := ""
		for e in w:
			var v := p + right * float(offs[e]) + Vector3.UP * float(drops[e])
			for m: Dictionary in mouths:
				var at_start: bool = m["end"] == "start"
				if (i if at_start else n - 1 - i) > mouth_reach(m):
					continue
				var cut := to_edge(m, Vector2(v.x + center.x, v.z + center.z), dirs[i] * (1.0 if at_start else -1.0))
				if not cut.is_empty():
					v = Vector3(cut[0].x, cut[1], cut[0].y) - center
					on_edge += 1
					ends = m["end"]
			verts.append(v)
			colors.append(cols[e])
			uvs.append(Vector2(float(offs[e]) / 4.0, along / 4.0))
		if on_edge == w:
			if ends == "start":
				first = k - from
			elif last == to - from:
				last = k - from
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for r in range(first, last):
		for e in w - 1:
			var a := r * w + e
			var b := a + w
			# Clockwise seen from above: the top is the front face.
			for t in [a, b, a + 1, a + 1, b, b + 1]:
				idx.append(t)
				faces.append(verts[t])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts.size():
		st.set_color(colors[v])
		st.set_uv(uvs[v])
		st.add_vertex(verts[v])
	for t in idx:
		st.add_index(t)
	st.generate_normals()
	return [st.commit(), faces, center]


## How many samples in from its end a track can still reach over the road at mouth `m` (see
## WorldRoads._mouths): its own width and shoulders at a slant, past that road's half width.
static func mouth_reach(m: Dictionary) -> int:
	return ceili((float(m["hw"]) + 6.0) / WorldRoads.STEP) + 1


## Where the road at mouth `m` (a track meets it there) runs, nearest `q`: [distance from its
## centre line, the point on it, its height there].
static func mouth_nearest(m: Dictionary, q: Vector2) -> Array:
	var xz: PackedVector2Array = m["xz"]
	var hs: PackedFloat32Array = m["h"]
	var best := [INF, q, 0.0]
	for i in xz.size() - 1:
		var seg := xz[i + 1] - xz[i]
		var u := clampf((q - xz[i]).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var c := xz[i] + seg * u
		var d := q.distance_to(c)
		if d < float(best[0]):
			best = [d, c, lerpf(hs[i], hs[i + 1], u)]
	return best


## How far `q` (world x, z) lies in on the road at mouth `m` (a track meets it there): from its
## sides, and from its end where the road stops there; 0 or less off it.
static func mouth_depth(m: Dictionary, q: Vector2) -> float:
	var xz: PackedVector2Array = m["xz"]
	var depth := float(m["hw"]) - float(mouth_nearest(m, q)[0])
	var last := xz.size() - 1
	if m.get("open_start", false):
		depth = minf(depth, (q - xz[0]).dot((xz[1] - xz[0]).normalized()))
	if m.get("open_end", false):
		depth = minf(depth, (q - xz[last]).dot((xz[last - 1] - xz[last]).normalized()))
	return depth


## A track's point `q` (world x, z) slid on along `out` (the way the track runs off the road at
## mouth `m`) to that road's edge, where it lies on the road: [the point, its height (the road's edge
## there, lifted JOIN_LIFT)], or [] where it's off the road already. So no track
## reaches over the tarmac it joins (Simon: "Dirt tracks that join the side of the road should
## start at the edge and not cross over"), and the tyres feel tarmac right up to the edge.
static func to_edge(m: Dictionary, q: Vector2, out: Vector2) -> Array:
	if mouth_depth(m, q) <= 0.0:
		return []
	# Out along the track half a metre at a time till it's off the road, then halved down to the edge.
	var lo := 0.0
	var hi := 0.5
	while hi < 20.0 and mouth_depth(m, q + out * hi) > 0.0:
		lo = hi
		hi += 0.5
	for k in 10:
		var t := (lo + hi) * 0.5
		if mouth_depth(m, q + out * t) > 0.0:
			lo = t
		else:
			hi = t
	q += out * hi
	return [q, float(mouth_nearest(m, q)[2]) + WorldRoads.JOIN_LIFT]


## The painted lines on samples `from`..`to` of a tarmac road, about `center`, or null for a
## dirt track. Lines stop short where a branch meets the road it leaves.
static func markings(road: Dictionary, from: int, to: int, center: Vector3):
	if road["kind"] != "tarmac":
		return null
	var xz: PackedVector2Array = road["xz"]
	var hs: PackedFloat32Array = road["h"]
	var dirs: PackedVector2Array = road["dir"]
	var dist: PackedFloat32Array = road["dist"]
	var n := xz.size()
	var hw: float = road["hw"]
	var loop: bool = road["closed"]
	var skip_start: float = road.get("start_skip", 0.0)
	var skip_end: float = road.get("end_skip", 0.0)
	var length: float = road["length"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for k in range(from, to):
		var i := k % n
		var j := (k + 1) % n
		var d0: float = dist[i]
		if d0 < skip_start or (not loop and d0 > length - skip_end - WorldRoads.STEP):
			continue
		var p0 := Vector3(xz[i].x, hs[i] + PAINT_LIFT, xz[i].y) - center
		var p1 := Vector3(xz[j].x, hs[j] + PAINT_LIFT, xz[j].y) - center
		var r0 := Vector3(-dirs[i].y, 0.0, dirs[i].x)
		var r1 := Vector3(-dirs[j].y, 0.0, dirs[j].x)
		var turn := 0.0
		if loop or (k > 0 and k < n - 1):
			var before := dirs[posmod(i - 1, n)]
			var after := dirs[j]
			turn = (before.x * after.y - before.y * after.x) / (2.0 * WorldRoads.STEP)   # 1 / radius, + to the right
		var kerb_side := 0.0
		if loop and absf(turn) > 1.0 / KERB_RADIUS:
			kerb_side = signf(turn)
		for side: float in [-1.0, 1.0]:
			if side == kerb_side:
				var c := KERB_RED if k % 2 == 0 else LINE
				_strip(st, p0, p1, r0, r1, side * (hw - 0.5), 0.9, c, 0.004)
			else:
				_strip(st, p0, p1, r0, r1, side * (hw - 0.3), 0.13, LINE)
		# The centre line: 3 m dashes with 6 m gaps (none on the loop, which is one way round).
		if not loop and fmod(d0, 9.0) < 3.0:
			_strip(st, p0, p1, r0, r1, 0.0, 0.12, LINE)
		any = true
	if not any:
		return null
	st.generate_normals()
	return st.commit()


## A painted strip from p0 to p1, `width` wide, its middle `offset` to the right.
static func _strip(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: Vector3, r1: Vector3, offset: float, width: float,
		color: Color, lift := 0.0) -> void:
	var a := p0 + r0 * (offset - width * 0.5)
	var b := p0 + r0 * (offset + width * 0.5)
	var c := p1 + r1 * (offset - width * 0.5)
	var d := p1 + r1 * (offset + width * 0.5)
	var up := Vector3.UP * lift
	st.set_color(color)
	for v in [a, c, b, b, c, d]:
		st.add_vertex(v + up)
