class_name BlastDetail
extends RefCounted
## The close-up engine in the sandblaster: the shed draws an engine as a few simple blocks, which
## is fine across the room but plain with your nose to the glass. This adds the castings you'd
## see on a real one, on each part in its own material (so they rust, blast and count with it):
## round side covers ringed with bolt heads, the crankcase seam and sump ribs, extra cooling fins
## on the barrels and head, rocker-cover bolts and ribs, exhaust port stubs, float bowls and caps
## on the carbs, a bolted clutch cover and ribs on the gearbox, and grip ribs on the oil filter.
## Round parts get smoother too.

const FINNED := ["boxer", "twin", "2stroke", "single", "mono"]
const ROUND_SEGMENTS := 36


## Adds the detail to an engine model (a BikeModel drawn by BikeModel.assembly_display). Returns
## how many pieces were added.
static func add_to(model: BikeModel) -> int:
	if model == null or model.has_meta("blast_detail"):
		return 0
	model.set_meta("blast_detail", true)
	var before := _count(model)
	_smooth(model)
	var s := model._eng_s
	var c := model._engine_c
	var bw := model._block_w
	var layout := str(model._build.layout) if model._build else ""
	if _has(model, "engine"):
		var mat := _main_mat(model, "engine")
		var side := 0.13 * s
		# Round covers on each side, a raised boss in the middle, ringed with bolts.
		for d in [1.0, -1.0]:
			var r := (0.07 if d > 0.0 else 0.062) * s
			var at: Vector3 = c + Vector3(d * (bw * 0.5 + 0.011), -0.035 * s, -0.08 * s)
			var axis := Vector3(d, 0.0, 0.0)
			_disc(model, "engine", mat, at, axis, r, 0.022)
			_disc(model, "engine", mat, at + axis * 0.015, axis, r * 0.42, 0.01)
			_bolt_ring(model, "engine", mat, at + axis * 0.012, axis, r * 0.85, 8 if d > 0.0 else 6)
			# Case bolts along the top and bottom of each half.
			for k in 5:
				var z := lerpf(-0.15, 0.15, k / 4.0) * s
				for y in [0.105 * s, -0.105 * s]:
					_bolt(model, "engine", mat, c + Vector3(d * (bw * 0.5 + 0.002), y, z), axis, 0.0055)
		# The crankcase seam and the ribs under the sump.
		_box(model, "engine", mat, c + Vector3(0.0, 0.02 * s, 0.0), Vector3(bw + 0.008, 0.008, 0.34 * s + 0.008))
		if layout != "2stroke":
			for k in 6:
				var z := lerpf(-0.13, 0.13, k / 5.0) * s
				_box(model, "engine", mat, c + Vector3(0.0, -side - 0.008, z), Vector3(bw * 0.78, 0.018, 0.007))
		# Mounting lugs front and back.
		for d in [1.0, -1.0]:
			_box(model, "engine", mat, c + Vector3(0.0, 0.1 * s, d * (0.17 * s + 0.015)), Vector3(bw * 0.5, 0.035, 0.03))
		for cy in model._cyls:
			var base: Vector3 = cy["base"]
			var up: Vector3 = cy["up"]
			var br := model._bore_r
			# A flange where the barrel meets the case, with its base nuts.
			_disc(model, "engine", mat, base - up * 0.094, up, br * 1.32, 0.012)
			_bolt_ring(model, "engine", mat, base - up * 0.086, up, br * 1.2, 4)
			if layout in FINNED:
				# Finer fins between the deep ones.
				for k in 4:
					_disc(model, "engine", mat, base + up * (-0.0825 + k * 0.045), up, br * 1.36, 0.005)
	if _has(model, "head"):
		var mat := _main_mat(model, "head")
		for cy in model._cyls:
			var up: Vector3 = cy["up"]
			var top: Vector3 = cy["base"] + up * 0.13
			var b := _basis_up(up)
			# Fins round the head casting on an air-cooled engine.
			if layout in FINNED:
				for k in 3:
					_box(model, "head", mat, top + up * (-0.028 + k * 0.026), Vector3(0.145, 0.005, 0.172), b)
			# Rocker cover bolts at the corners, ribs across the top.
			var lid := top + up * 0.086
			for x in [-0.044, 0.044]:
				for z in [-0.05, 0.05]:
					_bolt(model, "head", mat, lid + b * Vector3(x, 0.0, z), up, 0.006)
			for k in 3:
				_box(model, "head", mat, lid + b * Vector3(0.0, 0.002, -0.03 + k * 0.03), Vector3(0.09, 0.006, 0.008), b)
			# Exhaust port stubs out the front with their flange.
			var port := top + b * Vector3(0.0, -0.012, -0.082)
			var fwd := (b * Vector3.FORWARD).normalized()
			_disc(model, "head", mat, port, fwd, 0.022, 0.03, 20)
			_disc(model, "head", mat, port + fwd * 0.016, fwd, 0.03, 0.006, 20)
	if _has(model, "fuel"):
		var mat := _main_mat(model, "fuel")
		var style := str(PartsDB.get_part(str(model._build.parts.get("fuel", ""))).get("style", "carbs"))
		if style != "fi" and style != "carb":
			for pt in model._intake_points():
				var at: Vector3 = pt["port"] + (pt["dir"] as Vector3) * 0.05 + Vector3(0.0, -0.01, 0.0)
				# Float bowl underneath with its screws, and the slide cap on top.
				_disc(model, "fuel", mat, at + Vector3(0.0, -0.05, 0.0), Vector3.UP, 0.025, 0.026, 24)
				for x in [-0.016, 0.016]:
					_bolt(model, "fuel", mat, at + Vector3(x, -0.064, 0.0), Vector3.DOWN, 0.004)
				_disc(model, "fuel", mat, at + Vector3(0.0, 0.041, 0.0), Vector3.UP, 0.021, 0.012, 24)
				_bolt(model, "fuel", mat, at + Vector3(0.0, 0.049, 0.0), Vector3.UP, 0.006)
	if _has(model, "gearbox"):
		var mat := _main_mat(model, "gearbox")
		var face := c + Vector3(bw * 0.5 + 0.04, -0.02, 0.1)
		_disc(model, "gearbox", mat, face + Vector3(0.004, 0.0, 0.0), Vector3.RIGHT, 0.036, 0.012)
		_bolt_ring(model, "gearbox", mat, face, Vector3.RIGHT, 0.086, 10)
		for k in 4:
			_box(model, "gearbox", mat, c + Vector3(lerpf(-0.3, 0.3, k / 3.0) * bw, -0.06, 0.302), Vector3(0.007, 0.15, 0.01))
	if _has(model, "oil_filter"):
		var mat := _main_mat(model, "oil_filter")
		var at := c + Vector3(bw * 0.25, -0.06, -0.205)
		for k in 3:
			_disc(model, "oil_filter", mat, at + Vector3(0.0, 0.0, -0.022 + k * 0.022), Vector3.FORWARD, 0.0375, 0.005)
		_bolt(model, "oil_filter", mat, at + Vector3(0.0, 0.0, -0.038), Vector3.FORWARD, 0.012)
	return _count(model) - before


static func _count(model: BikeModel) -> int:
	var n := 0
	for slot in model._slot_meshes:
		n += (model._slot_meshes[slot] as Array).size()
	return n


static func _has(model: BikeModel, slot: String) -> bool:
	return model.is_fitted(slot) and not (model._slot_meshes.get(slot, []) as Array).is_empty()


## The material most of a part's meshes are drawn in (its casting, not the gasket or caps).
static func _main_mat(model: BikeModel, slot: String) -> Material:
	var counts := {}
	var best: Material = null
	var most := 0
	for mi in model._slot_meshes.get(slot, []):
		var m: Material = (mi as GeometryInstance3D).material_override
		if m == null:
			continue
		counts[m] = int(counts.get(m, 0)) + 1
		if int(counts[m]) > most:
			most = int(counts[m])
			best = m
	return best


## Rounder cylinders on the close-up: the shed draws tubes with 12 sides.
static func _smooth(model: BikeModel) -> void:
	for slot in ["engine"] + Array(PartsDB.ENGINE_SLOTS):
		for mi in model._slot_meshes.get(slot, []):
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh is CylinderMesh:
				var cm := (mi as MeshInstance3D).mesh as CylinderMesh
				cm.radial_segments = maxi(cm.radial_segments, ROUND_SEGMENTS)


## Turns +y onto `up` the shortest way (as the shed's own engine drawing does).
static func _basis_up(up: Vector3) -> Basis:
	var u := up.normalized()
	var axis := Vector3.UP.cross(u)
	if axis.length() < 0.0001:
		return Basis() if u.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(u))


## Adds a mesh to a part, placed by `xf` in the model's space, hung from the same node as the
## part's other meshes so it moves with them.
static func _add(model: BikeModel, slot: String, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var list: Array = model._slot_meshes[slot]
	var parent: Node3D = model
	if not list.is_empty() and (list[0] as Node).get_parent() is Node3D:
		parent = (list[0] as Node).get_parent()
	var parent_xf := Transform3D() if parent == model else model._local_xform(parent)
	var mi := MeshInstance3D.new()
	mi.name = "Detail"
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = parent_xf.affine_inverse() * xf
	parent.add_child(mi)
	list.append(mi)
	return mi


static func _disc(model: BikeModel, slot: String, mat: Material, at: Vector3, axis: Vector3, radius: float,
		thick: float, segments := ROUND_SEGMENTS) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = thick
	cm.radial_segments = segments
	cm.rings = 1
	return _add(model, slot, cm, mat, Transform3D(_basis_up(axis), at))


## A hex bolt head standing out of a face along `axis`.
static func _bolt(model: BikeModel, slot: String, mat: Material, at: Vector3, axis: Vector3, radius := 0.006) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = radius
	cm.radial_segments = 6
	cm.rings = 1
	return _add(model, slot, cm, mat, Transform3D(_basis_up(axis), at + axis.normalized() * radius * 0.5))


static func _bolt_ring(model: BikeModel, slot: String, mat: Material, center: Vector3, axis: Vector3, radius: float, n: int) -> void:
	var b := _basis_up(axis)
	for k in n:
		var t := TAU * k / float(n)
		_bolt(model, slot, mat, center + b * Vector3(cos(t) * radius, 0.0, sin(t) * radius), axis, 0.0055)


static func _box(model: BikeModel, slot: String, mat: Material, at: Vector3, size: Vector3, b := Basis()) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(model, slot, bm, mat, Transform3D(b, at))
