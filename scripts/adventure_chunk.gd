class_name AdventureChunk
extends RefCounted
## One stretch of an adventure road (AdventureRoute.CHUNK_KNOTS knots, 128 m): its road, white
## lines, verges and land out to the skyline, the trees, rocks, fences, buildings and posts on it,
## and its collision. build() lays it all out as plain arrays from the route alone (so it runs on
## a worker thread, and every player gets the same chunk); commit() turns that into nodes on the
## main thread. Everything is relative to the chunk's first knot (its anchor), so the numbers
## stay small however far along the route it is.

## The land either side, metres out past the road's edge (the first few follow the road's half
## width; the rest are from the centre line). Out to column COLLIDE_COLS it's solid.
const LAND_OUT := [0.0, 0.9, 2.5, 6.0, 12.0, 20.0, 30.0, 46.0, 70.0, 110.0, 170.0, 260.0, 400.0]
const COLLIDE_COLS := 7
const CROWN := 0.04
## How far each kind of thing is drawn (m, times the draw distance setting).
const RANGES := {"pine": 650.0, "snow_pine": 650.0, "tree": 650.0, "bush": 260.0, "dry_bush": 260.0, "rock": 320.0,
	"post": 220.0, "snow_pole": 260.0, "km_post": 200.0, "buildings": 1100.0, "lines": 380.0}
## Scenery per chunk on each surface's land: kind -> how many.
const SCENERY := {
	"tarmac": {"tree": 16, "bush": 10, "pine": 3, "rock": 2},
	"gravel": {"pine": 28, "tree": 4, "bush": 5, "rock": 10},
	"sand": {"dry_bush": 14, "rock": 16},
	"snow": {"snow_pine": 24, "rock": 7},
}
const BUILDING_ODDS := {"tarmac": 0.2, "gravel": 0.07, "sand": 0.06, "snow": 0.05}
const FENCE_ODDS := {"tarmac": 0.55, "gravel": 0.3, "sand": 0.0, "snow": 0.0}


## Lays out chunk `c` of `route`. Safe to run on a worker thread: it only reads the route.
static func build(route: AdventureRoute, c: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var n := route.knot_count()
	var i0 := c * AdventureRoute.CHUNK_KNOTS
	var i1 := mini(i0 + AdventureRoute.CHUNK_KNOTS, n - 1)
	var ax := route.px[i0]
	var az := route.pz[i0]
	var surf := route.chunk_surface[clampi(c, 0, route.chunk_surface.size() - 1)]
	var out := {"c": c, "i0": i0, "i1": i1, "ax": ax, "az": az, "surface": surf,
		"land": AdventureSurface.LAND.get(surf, "grass")}
	var rows := i1 - i0 + 1
	# The road: five points across (edges, quarter lines, the crown).
	var road_v := PackedVector3Array()
	var road_uv := PackedVector2Array()
	var road_c := PackedColorArray()
	var rc: Color = AdventureSurface.ROAD_COLOR[surf]
	for i in range(i0, i1 + 1):
		var h := route.hd[i]
		var rx := cos(h)
		var rz := sin(h)
		var e := route.width[i] * 0.5
		var cx := route.px[i] - ax
		var cz := route.pz[i] - az
		for k in 5:
			var f := (k - 2) / 2.0
			var lat := f * e
			var y := route.ph[i] + CROWN * (1.0 - f * f)
			road_v.append(Vector3(cx + rx * lat, y, cz + rz * lat))
			road_uv.append(Vector2(f * e / 3.0, i * AdventureRoute.STEP / 3.0))
			var wear := 1.0 - 0.06 * (1.0 - absf(absf(f) - 0.5) * 2.0) if surf == "tarmac" else 1.0
			road_c.append(rc * wear)
	out["road"] = _grid(road_v, rows, 5, road_uv, road_c)
	out["road_faces"] = _faces(road_v, rows, 5, 5)
	# The land either side, out to the skyline: left from its far edge in, right from the verge out.
	var cols := LAND_OUT.size()
	var land := {}
	for side: int in [-1, 1]:
		var v := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		for i in range(i0, i1 + 1):
			var h := route.hd[i]
			var rx := cos(h)
			var rz := sin(h)
			var e := route.width[i] * 0.5
			var max_in := route.inside_reach(i, side)
			var row_v := []
			var row_c := []
			var prev := e
			var stopped := false   # past another stretch of the road: the rest of the row stays put
			for k in cols:
				var out_k: float = LAND_OUT[k]
				var lat := (e + out_k) if k < 6 else maxf(out_k, e + out_k * 0.5)
				if k > 0:
					lat = maxf(lat, prev + 0.3)
				if k > 2:
					lat = minf(lat, maxf(max_in, prev + 0.05))
				if k >= 7 and not stopped:
					# Would the land out to here reach over a bend that doubles back? Look along the way.
					var steps := maxi(1, int((lat - prev) / 40.0))
					for q in range(1, steps + 1):
						var at := lerpf(prev, lat, float(q) / steps)
						if route.other_road_near(i, route.px[i] + rx * at * side, route.pz[i] + rz * at * side, 30.0):
							stopped = true
							break
				if stopped:
					lat = prev + 0.05 * k
				prev = lat
				var wx := route.px[i] + rx * lat * side
				var wz := route.pz[i] + rz * lat * side
				var y := route.land_height(i, lat * side, wx, wz)
				row_v.append(Vector3(wx - ax, y, wz - az))
				row_c.append(_land_color(route, i, k, lat, wx, wz, y))
			if side < 0:
				row_v.reverse()
				row_c.reverse()
			for k in cols:
				v.append(row_v[k])
				col.append(row_c[k])
				uv.append(Vector2(row_v[k].x, row_v[k].z) * 0.1)
		land[side] = {"v": v, "c": col}
		out["land_%d" % side] = _grid(v, rows, cols, uv, col)
		# Solid out to COLLIDE_COLS: the inner columns (the right's first, the left's last).
		out["land_faces_%d" % side] = _faces(v, rows, cols, COLLIDE_COLS + 1, side < 0)
	out["lines"] = _lines(route, i0, i1, ax, az, surf)
	_scenery(route, c, i0, i1, ax, az, surf, out)
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## The land's colour at a vertex: its surface's (blended across a change of surface), patched
## by noise, the verge's beside the road, and greyer where it's steep.
static func _land_color(route: AdventureRoute, i: int, k: int, lat: float, x: float, z: float, y: float) -> Color:
	var s := i * AdventureRoute.STEP
	var here := route.surface_at_s(s)
	var col: Color = AdventureSurface.LAND_COLOR[here]
	var patch: Color = AdventureSurface.LAND_PATCH[here]
	for d: float in [-64.0, 64.0]:
		var other := route.surface_at_s(s + d)
		if other != here:
			col = col.lerp(AdventureSurface.LAND_COLOR[other], 0.35)
			patch = patch.lerp(AdventureSurface.LAND_PATCH[other], 0.35)
	var n := route._noise_fine.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	col = col.lerp(patch, smoothstep(0.35, 0.75, n))
	if k <= 1:
		col = AdventureSurface.VERGE_COLOR[here]
	elif k == 2:
		col = col.lerp(AdventureSurface.VERGE_COLOR[here], 0.5)
	# Steep ground away from the road shows rock (snow lies on the gentler slopes).
	var rise := absf(y - route.ph[i]) / maxf(lat, 1.0)
	if k > 3:
		col = col.lerp(Color(0.45, 0.43, 0.4), smoothstep(0.45, 0.9, rise) * 0.7)
	return col


## An indexed grid mesh's arrays from `rows` x `cols` vertices (row by row, each row left to
## right looking along the road), with normals worked out from its faces.
static func _grid(v: PackedVector3Array, rows: int, cols: int, uv: PackedVector2Array, col: PackedColorArray) -> Array:
	var idx := PackedInt32Array()
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	for r in rows - 1:
		for k in cols - 1:
			var bl := r * cols + k
			var br := bl + 1
			var tl := bl + cols
			var tr := tl + 1
			idx.append_array([bl, tl, tr, bl, tr, br])
			var n1 := (v[tr] - v[bl]).cross(v[tl] - v[bl])
			var n2 := (v[br] - v[bl]).cross(v[tr] - v[bl])
			for p in [bl, tl, tr]:
				nrm[p] += n1
			for p in [bl, tr, br]:
				nrm[p] += n2
	for p in nrm.size():
		nrm[p] = nrm[p].normalized() if nrm[p].length_squared() > 0.0 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Collision triangles for the first `upto` columns of a grid (the last `upto` with `from_end`).
static func _faces(v: PackedVector3Array, rows: int, cols: int, upto: int, from_end := false) -> PackedVector3Array:
	var f := PackedVector3Array()
	var k0 := cols - upto if from_end else 0
	var k1 := cols - 1 if from_end else upto - 1
	for r in rows - 1:
		for k in range(k0, k1):
			var bl := r * cols + k
			var br := bl + 1
			var tl := bl + cols
			var tr := tl + 1
			f.append_array([v[bl], v[tl], v[tr], v[bl], v[tr], v[br]])
	return f


## The white lines on tarmac: solid edge lines on anything but a single track, and a dashed
## centre line on a road wide enough for two.
static func _lines(route: AdventureRoute, i0: int, i1: int, ax: float, az: float, surf: String) -> Dictionary:
	var a := AdventureProps.new_arrays()
	if surf != "tarmac":
		return a
	var col := Color(0.88, 0.88, 0.84)
	for i in range(i0, i1):
		var e0 := route.width[i] * 0.5
		var e1 := route.width[i + 1] * 0.5
		if e0 < 2.0:
			continue
		var offs := [[-e0 + 0.3, -e1 + 0.3, 0.12], [e0 - 0.3, e1 - 0.3, 0.12]]
		# Dashes: 3 m of line, 6 m gap (a knot is 4 m: every third knot's stretch, most of it).
		if e0 >= 2.7 and i % 3 == 0:
			offs.append([0.0, 0.0, 0.1])
		for o in offs:
			var w: float = o[2] * 0.5
			var p := []
			for j: int in [i, i + 1]:
				var lat: float = o[0] if j == i else o[1]
				var h := route.hd[j]
				var f := lat / maxf(route.width[j] * 0.5, 0.1)
				var y := route.ph[j] + CROWN * (1.0 - f * f) + 0.012
				var cx := route.px[j] - ax
				var cz := route.pz[j] - az
				p.append(Vector3(cx + cos(h) * (lat - w), y, cz + sin(h) * (lat - w)))
				p.append(Vector3(cx + cos(h) * (lat + w), y, cz + sin(h) * (lat + w)))
			# p: [i left, i right, i+1 left, i+1 right]
			AdventureProps._quad(a, p[0], p[1], p[3], p[2], col)
	return a


## The trees, bushes, rocks, posts, fences and buildings of the chunk, and its km posts and sites.
static func _scenery(route: AdventureRoute, c: int, i0: int, i1: int, ax: float, az: float, surf: String, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "chunk", c])
	var mm := {}
	var counts: Dictionary = SCENERY.get(surf, {})
	for kind in counts:
		var list := []
		for k in int(counts[kind]):
			var i := rng.randi_range(i0, i1)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var near := 2.5 if kind in ["rock", "bush", "dry_bush"] else 6.0
			var lat := route.width[i] * 0.5 + near + pow(rng.randf(), 1.5) * 120.0
			var xf := _on_land(route, i, lat * side, ax, az, rng.randf() * TAU, rng.randf_range(0.7, 1.35))
			if xf != Transform3D():
				list.append(xf)
		mm[kind] = list
	# Fences along farmland, a post every 3 m or so, with two rails between.
	var buildings := AdventureProps.new_arrays()
	var fence_roll := float(absi(hash([route.seed_value, "fence", int(i0 * AdventureRoute.STEP / 600.0)])) % 1000) / 1000.0
	if fence_roll < float(FENCE_ODDS.get(surf, 0.0)):
		var posts := []
		var rail := Color(0.45, 0.35, 0.24)
		for side: float in [-1.0, 1.0]:
			var prev := Vector3.INF
			for i in range(i0, i1 + 1):
				var lat := (route.width[i] * 0.5 + 4.0) * side
				var xf := _on_land(route, i, lat, ax, az, route.hd[i], 1.0, true)
				if xf == Transform3D():
					prev = Vector3.INF
					continue
				posts.append(xf)
				if prev != Vector3.INF:
					for y: float in [0.55, 0.95]:
						_rail(buildings, prev + Vector3.UP * y, xf.origin + Vector3.UP * y, rail)
				prev = xf.origin
		mm["post"] = posts
	# Marker poles along a snowy road, every 32 m or so either side.
	if surf == "snow":
		var poles := []
		for i in range(i0, i1 + 1, 8):
			for side: float in [-1.0, 1.0]:
				var xf := _on_land(route, i, (route.width[i] * 0.5 + 1.2) * side, ax, az, 0.0, 1.0, true)
				if xf != Transform3D():
					poles.append(xf)
		mm["snow_pole"] = poles
	# The odd building.
	if rng.randf() < float(BUILDING_ODDS.get(surf, 0.0)):
		var i := rng.randi_range(i0, i1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := route.width[i] * 0.5 + rng.randf_range(18.0, 50.0)
		# Facing the road: local +z towards it.
		var face := atan2(-cos(route.hd[i]) * side, -sin(route.hd[i]) * side)
		var xf := _on_land(route, i, lat * side, ax, az, face, 1.0, false, 9.0)
		if xf != Transform3D():
			xf.origin.y -= 0.4   # sunk in a little on a slope
			AdventureProps.building(buildings, xf, rng, surf)
	out["buildings"] = buildings
	# Kilometre posts on the left verge, every kilometre.
	var kms := []
	var s0 := i0 * AdventureRoute.STEP
	var s1 := i1 * AdventureRoute.STEP
	var km := int(ceil(s0 / 1000.0))
	while km * 1000.0 < s1:
		if km > 0:
			var i := int(km * 1000.0 / AdventureRoute.STEP)
			var xf := _on_land(route, i, -(route.width[i] * 0.5 + 1.4), ax, az, -route.hd[i], 1.0, true)
			if xf != Transform3D():
				kms.append({"xf": xf, "km": km})
		km += 1
	out["km"] = kms
	mm["km_post"] = kms.map(func(k): return k["xf"])
	out["mm"] = mm
	# Sites starting in this chunk, and where each stands: on the verge, x away from the road.
	var here := []
	for st in route.sites:
		var si: int = st["i"]
		if si >= i0 and si < i1 or (si == i1 and i1 == route.knot_count() - 1):
			var side := float(st["side"])
			var h := route.hd[si]
			var e := route.width[si] * 0.5
			var r := Vector3(cos(h), 0.0, sin(h))
			var fwd := Vector3(sin(h), 0.0, -cos(h))
			var across: bool = st["kind"] in ["start", "finish"]   # a banner over the road
			var lat := 0.0 if across else (e + 0.9) * side
			var origin := Vector3(route.px[si] - ax + r.x * lat, route.ph[si], route.pz[si] - az + r.z * lat)
			var basis := Basis(r, Vector3.UP, -fwd) if across else Basis(r * side, Vector3.UP, -fwd * side)
			here.append({"site": st, "xf": Transform3D(basis, origin), "width": route.width[si]})
	out["sites"] = here


## A transform standing on the land `lat` metres off the road at knot `i` (relative to the
## anchor), turned `angle` about the vertical (local +z then points along (sin, cos)) and
## scaled `scale`; an empty Transform3D where it would be on a road,
## a site's forecourt, or past the land the chunk draws on the inside of a bend. `keep_clear`
## is how far from any road's edge it must be (fence posts and markers sit closer).
static func _on_land(route: AdventureRoute, i: int, lat: float, ax: float, az: float, angle: float, scale: float,
		close := false, keep_clear := 2.0) -> Transform3D:
	var h := route.hd[i]
	if absf(lat) > route.inside_reach(i, int(signf(lat))) * 0.95:
		return Transform3D()
	var wx := route.px[i] + cos(h) * lat
	var wz := route.pz[i] + sin(h) * lat
	if not close and route.clearance(wx, wz) < keep_clear:
		return Transform3D()
	if route._site_flat(i, signf(lat)) > 0.0 and not close:
		return Transform3D()
	var y := route.land_height(i, lat, wx, wz)
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale), Vector3(wx - ax, y - 0.05, wz - az))


## A fence rail from `a` to `b`: a thin plank, seen from both sides.
static func _rail(arr: Dictionary, a: Vector3, b: Vector3, col: Color) -> void:
	var up := Vector3.UP * 0.07
	AdventureProps._quad(arr, a - up, b - up, b + up, a + up, col)
	AdventureProps._quad(arr, b - up, a - up, a + up, b + up, col)


# ---------------------------------------------------------------------------- nodes

## Makes chunk `data` (from build) into a node under `world`, placed at its anchor in the
## world's local frame. Returns it (its meta "c" is the chunk index).
static func commit(data: Dictionary, world: AdventureWorld) -> Node3D:
	var node := Node3D.new()
	var c: int = data["c"]
	node.name = "Chunk%d" % c
	node.set_meta("c", c)
	node.set_meta("ax", data["ax"])
	node.set_meta("az", data["az"])
	var surf: String = data["surface"]
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	# Road
	var road := ArrayMesh.new()
	road.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["road"])
	var rmi := MeshInstance3D.new()
	rmi.name = "Road"
	rmi.mesh = road
	rmi.material_override = AdventureSurface.road_material(surf)
	node.add_child(rmi)
	var lines: Dictionary = data["lines"]
	if not (lines["v"] as PackedVector3Array).is_empty():
		var lmi := MeshInstance3D.new()
		lmi.name = "Lines"
		lmi.mesh = AdventureProps.to_mesh(lines)
		lmi.material_override = AdventureSurface.line_material()
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(lmi, RANGES["lines"] * scale)
		node.add_child(lmi)
	# Land, both sides in one mesh
	var land := ArrayMesh.new()
	land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["land_-1"])
	land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["land_1"])
	var lmesh := MeshInstance3D.new()
	lmesh.name = "Land"
	lmesh.mesh = land
	lmesh.material_override = AdventureSurface.land_material()
	node.add_child(lmesh)
	# Collision: the road (its surface for the tyres) and the land near it.
	var rb := StaticBody3D.new()
	rb.name = "RoadBody"
	rb.collision_layer = 1
	rb.set_meta("surface", surf)
	var rshape := ConcavePolygonShape3D.new()
	rshape.backface_collision = true
	rshape.set_faces(data["road_faces"])
	var rcs := CollisionShape3D.new()
	rcs.shape = rshape
	rb.add_child(rcs)
	node.add_child(rb)
	var lb := StaticBody3D.new()
	lb.name = "LandBody"
	lb.collision_layer = 1
	lb.set_meta("surface", data["land"])
	for side: int in [-1, 1]:
		var lshape := ConcavePolygonShape3D.new()
		lshape.backface_collision = true
		lshape.set_faces(data["land_faces_%d" % side])
		var lcs := CollisionShape3D.new()
		lcs.shape = lshape
		lb.add_child(lcs)
	node.add_child(lb)
	# Scenery
	var mm: Dictionary = data["mm"]
	for kind in mm:
		var list: Array = mm[kind]
		if list.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = AdventureProps.mesh(kind)
		multi.instance_count = list.size()
		for k in list.size():
			multi.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + kind
		mmi.multimesh = multi
		if kind in ["post", "snow_pole", "km_post", "bush", "dry_bush"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range(mmi, float(RANGES.get(kind, 400.0)) * scale)
		node.add_child(mmi)
	var bld: Dictionary = data["buildings"]
	if not (bld["v"] as PackedVector3Array).is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Buildings"
		bmi.mesh = AdventureProps.to_mesh(bld)
		_range(bmi, RANGES["buildings"] * scale)
		node.add_child(bmi)
	for k in data["km"]:
		var label := Label3D.new()
		label.text = "%d" % int(k["km"])
		label.font_size = 40
		label.pixel_size = 0.006
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		var xf: Transform3D = k["xf"]
		label.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.62 + xf.basis.z.normalized() * 0.06)
		label.visibility_range_end = 120.0
		node.add_child(label)
	for st in data["sites"]:
		var site: Dictionary = st["site"]
		var builder: Callable = world.site_builders.get(str(site["kind"]), Callable())
		if builder.is_valid():
			var made = builder.call(site, st["xf"], st)
			if made is Node3D:
				node.add_child(made)
	world.place_chunk(node)
	return node


static func _range(gi: GeometryInstance3D, end: float) -> void:
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = 30.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
