extends RefCounted
## Side roads and dirt tracks start at the edge of the road they join and never reach over it
## (Simon: "Dirt tracks that join the side of the road should start at the edge and not cross
## over"), run from tests/run_tests.gd (its _test_tracks_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

## How close to the road's edge (m) a side road's mouth must come, and how far onto the road
## anything of it may lie (just the rounding of a float).
const MOUTH_GAP := 0.12
const OVER := 0.03


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## Whether 2D point `p` lies inside the triangle a, b, c (either winding).
static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	return not ((d1 < 0.0 or d2 < 0.0 or d3 < 0.0) and (d1 > 0.0 or d2 > 0.0 or d3 > 0.0))


## Whether any triangle of `faces` (offset by `off` in x, z) covers `p`.
static func _covered(faces: PackedVector3Array, off: Vector2, p: Vector2) -> bool:
	for k in range(0, faces.size(), 3):
		var a := Vector2(faces[k].x, faces[k].z) + off
		var b := Vector2(faces[k + 1].x, faces[k + 1].z) + off
		var c := Vector2(faces[k + 2].x, faces[k + 2].z) + off
		if p.x < minf(a.x, minf(b.x, c.x)) or p.x > maxf(a.x, maxf(b.x, c.x)) \
				or p.y < minf(a.y, minf(b.y, c.y)) or p.y > maxf(a.y, maxf(b.y, c.y)):
			continue
		if _in_tri(p, a, b, c):
			return true
	return false


## An adventure route's junctions: for each (up to `most`), its chunk built as the game builds it,
## then its side roads' meshes and collision checked against the main road under them, and the
## surface the game says is under a wheel there. Returns [junctions looked at, arms looked at,
## faults (strings), dirt lanes off tarmac among the arms].
static func _junction_faults(route: AdventureRoute, most: int) -> Array:
	var w := AdventureWorld.new()   # (not in the tree: only its surface lookup, with the route's own frame)
	w.route = route
	var seen := 0
	var arms_seen := 0
	var lanes := 0
	var faults: Array[String] = []
	var done := {}
	for st: Dictionary in route.sites_of(AdventureJunctions.KIND):
		if seen >= most or not st.has("arm_geo"):
			continue
		var si: int = st["i"]
		var c := si / AdventureRoute.CHUNK_KNOTS
		if done.has(c):
			continue
		done[c] = true
		seen += 1
		var data := AdventureChunk.build(route, c)
		var ax := float(data["ax"])
		var az := float(data["az"])
		var off := Vector2(ax, az)
		var faces := PackedVector3Array()
		for surf in data["arm_faces"]:
			faces.append_array(data["arm_faces"][surf])
		var verts := PackedVector3Array()
		for surf in data["arms"]:
			verts.append_array(data["arms"][surf]["v"])
		var name := "%s at %.0f m" % [st["type"], float(st["s"])]
		# Nothing of a side road (drawn or felt) lies on the tarmac: every corner of it is at or past the edge.
		var worst := 0.0
		for v in faces:
			var hit := route.locate(v.x + ax, v.z + az, si)
			if hit.is_empty():
				continue
			var e := AdventureJunctions.edge_at_s(route, float(hit["s"]))
			worst = maxf(worst, e - absf(float(hit["lat"])))
		if worst > OVER:
			faults.append("%s: a side road reaches %.2f m onto the tarmac" % [name, worst])
		# Points all over the road through the junction: none under a side road's mesh.
		var s0 := float(st["s"])
		for ds in range(-30, 31, 1):
			var s := s0 + float(ds)
			var e := AdventureJunctions.edge_at_s(route, s)
			for f in [-0.97, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 0.97]:
				var xz := route.xz_at(s, e * float(f))
				if _covered(faces, off, Vector2(float(xz[0]), float(xz[1]))):
					faults.append("%s: a side road covers the road %.0f m along, %.1f m across" % [name, ds, e * float(f)])
					break
				var felt := w.surface_local(Vector3(float(xz[0]), 0.0, float(xz[1])))
				if felt != route.surface_at_s(s) and route.surface_at_s(s - 0.5) == route.surface_at_s(s + 0.5):   # (not right on a change of surface)
					faults.append("%s: the road %.0f m along, %.1f m across feels like %s" % [name, ds, e * float(f), felt])
					break
		# Each arm's mouth comes right up to the edge: some of its drawn strip within MOUTH_GAP of it, by its centre line.
		for k in (st["arms"] as Array).size():
			arms_seen += 1
			if str(st["arms"][k]["surf"]) != "tarmac" and route.surface_at_s(float(st["s"])) == "tarmac":
				lanes += 1
			var pts: PackedVector3Array = st["arm_geo"][k]
			var mouth := Vector2(route.px[si] + pts[0].x, route.pz[si] + pts[0].z)
			var hit0 := route.locate(mouth.x, mouth.y, si)
			var e0 := AdventureJunctions.edge_at_s(route, float(hit0["s"]))
			if absf(absf(float(hit0["lat"])) - e0) > MOUTH_GAP:
				faults.append("%s: arm %d's centre line starts %.2f m from the edge" % [name, k, absf(float(hit0["lat"])) - e0])
			var near := INF
			for v in verts:
				var q := Vector2(v.x + ax, v.z + az)
				if q.distance_to(mouth) > float(st["arms"][k]["w"]):
					continue
				var hv := route.locate(q.x, q.y, si)
				near = minf(near, absf(absf(float(hv["lat"])) - AdventureJunctions.edge_at_s(route, float(hv["s"]))))
			if near > MOUTH_GAP:
				faults.append("%s: arm %d's mouth stops %.2f m short of the edge" % [name, k, near])
			# Off the edge, a couple of metres down it, it's the side road's own surface.
			var in2 := pts[0].lerp(pts[1], 0.7)
			var felt := w.surface_local(Vector3(route.px[si] + in2.x, 0.0, route.pz[si] + in2.z))
			if felt != str(st["arms"][k]["surf"]):
				faults.append("%s: arm %d feels like %s just off the edge, not %s" % [name, k, felt, st["arms"][k]["surf"]])
	w.free()
	return [seen, arms_seen, faults, lanes]


## Made-up adventure roads (a few seeds and themes): every junction's side roads start at the edge.
func test_adventure() -> void:
	var junctions := 0
	var arms := 0
	var faults: Array[String] = []
	var lanes := 0
	for run in [[42, "varied"], [7, "alpine"], [1234, "desert"], [99, "coastal"], [5, "hills"]]:
		var r := AdventureRoute.new()
		r.plan(int(run[0]), 60.0, str(run[1]))
		var got := _junction_faults(r, 14)
		lanes += int(got[3])
		junctions += int(got[0])
		arms += int(got[1])
		faults.append_array(got[2])
	check(junctions >= 12 and arms >= 14, "made-up roads: %d junctions with %d side roads looked at (%d dirt lanes off tarmac)" % [junctions, arms, lanes])
	check(lanes >= 2, "and among them dirt lanes joining a tarmac road")
	check(faults.is_empty(), "made-up roads: every side road starts at the road's edge, none of it on the tarmac%s"
		% ("" if faults.is_empty() else " (%d faults: %s)" % [faults.size(), "; ".join(faults.slice(0, 4))]))


## A real road (the bundled pack): its junctions' side roads start at the edge too.
func test_real() -> void:
	var r := AdventureRoute.new()
	r.plan_real(RealPack.get_pack("shodoshima"), 7, 1000.0)
	var got := _junction_faults(r, 10)
	var faults: Array = got[2]
	check(int(got[0]) >= 3, "real road: %d junctions with %d side roads looked at" % [got[0], got[1]])
	check(faults.is_empty(), "real road: every side road starts at the road's edge, none of it on the tarmac%s"
		% ("" if faults.is_empty() else " (%d faults: %s)" % [faults.size(), "; ".join(faults.slice(0, 4))]))


## The riding map round the shed: each dirt track that leaves a tarmac road starts at its edge,
## with tarmac under the tyres right up to it (rays down onto the built map, as a wheel's).
func test_world() -> void:
	var world := World.new()
	t.add_child(world)
	world.generate(1234)
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var roads := world.roads
	var chunks: Array = World._data_for(1234)["road_chunks"]
	var space := world.get_world_3d().direct_space_state
	var mouths := 0
	var faults: Array[String] = []
	var not_tarmac: Array[String] = []
	var rays := 0
	for ri in roads.roads.size():
		var road: Dictionary = roads.roads[ri]
		for m: Dictionary in road.get("mouths", []):
			mouths += 1
			var j: Dictionary = road[str(m["end"]) + "_join"]
			var parent: Dictionary = roads.roads[int(j["road"])]
			var hw := float(parent["hw"])
			var pxz: PackedVector2Array = parent["xz"]
			var dirs: PackedVector2Array = parent["dir"]
			var n := pxz.size()
			var faces := PackedVector3Array()
			for ch in chunks:
				if int(ch["road"]) != ri:
					continue
				var c: Vector3 = ch["center"]
				for v in (ch["faces"] as PackedVector3Array):
					faces.append(v + c)
			# How far in on the tarmac each corner of the track is (from its sides, and its end where it
			# stops there): none in on it, and the nearest right at the edge.
			var nearest := INF
			var worst := -INF
			var join := pxz[int(j["i"])]
			for v in faces:
				var q := Vector2(v.x, v.z)
				if q.distance_to(join) > hw + 15.0:
					continue
				var depth := WorldRoadMesh.mouth_depth(m, q)
				nearest = minf(nearest, absf(depth))
				worst = maxf(worst, depth)
			var name := "%s at %s's %s" % [road["label"], parent["label"], m["end"]]
			if worst > OVER:
				faults.append("%s reaches %.2f m onto the tarmac" % [name, worst])
			if nearest > MOUTH_GAP:
				faults.append("%s starts %.2f m from the edge" % [name, nearest])
			# The tarmac round the join, a ray down at each point (between the rows of its mesh, where
			# a ray can't slip down the seam between two triangles): tarmac, and no track mesh over it.
			for k in range(-6, 6):
				var i := int(j["i"]) + k
				var i2 := i + 1
				if parent["closed"]:
					i = posmod(i, n)
					i2 = posmod(i2, n)
				elif i < 0 or i2 >= n:
					continue
				var right := Vector2(-dirs[i].y, dirs[i].x)
				var hs: PackedFloat32Array = parent["h"]
				for f in [-0.95, -0.6, -0.2, 0.2, 0.6, 0.95]:
					var p := pxz[i].lerp(pxz[i2], 0.37) + right * hw * float(f)
					if _covered(faces, Vector2.ZERO, p):
						faults.append("%s covers the tarmac %.1f m across" % [name, hw * float(f)])
					var y := lerpf(hs[i], hs[i2], 0.37)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 2.0, p.y), Vector3(p.x, y - 2.0, p.y)))
					rays += 1
					var felt := "nothing" if hit.is_empty() else str((hit["collider"] as Object).get_meta("surface", "?"))
					if felt != "tarmac":
						not_tarmac.append("%s %.1f m across: %s" % [name, hw * float(f), felt])
	world.queue_free()
	check(mouths >= 8, "the riding map has %d places a dirt track meets a tarmac road" % mouths)
	check(faults.is_empty(), "each starts at the road's edge, none of it on the tarmac%s"
		% ("" if faults.is_empty() else " (%d faults: %s)" % [faults.size(), "; ".join(faults.slice(0, 4))]))
	check(not_tarmac.is_empty() and rays > 300, "the tyres feel tarmac right up to the edge where each joins (%d of %d rays down find it%s)"
		% [rays - not_tarmac.size(), rays, "" if not_tarmac.is_empty() else "; not: " + "; ".join(not_tarmac.slice(0, 4))])
