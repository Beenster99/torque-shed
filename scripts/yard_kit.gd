class_name YardKit
extends RefCounted
## Draws the yard kit (Equipment's ramps, things to jump, walls and markers) and gives it the
## collision it's ridden on. Each piece is built once into one mesh, a surface per material
## (see YardLooks), and every copy of it shares that mesh: a yard full of kit costs a few draws
## a piece however many bolts, struts and window pillars it has.
##
## Ramps and the tabletop follow a `profile` (PROFILES): the deck is a smooth curve worked out
## from how its slope changes along it, so it leaves the ground level, never kinks, and ends at a
## clean lip. The drawn deck and the collision the tyres read are made from the same points, so
## a wheel rolls exactly where the deck is drawn.

## How a deck's slope changes from its toe (s = 0, on the ground at the front, +Z) to its far
## end (s = 1, -Z): [s, slope] keys, the slope as a share of its steepest, straight between keys.
## The heights follow from that and are scaled to the ramp's height.
##  - launch: curves up off the ground, then a straight face to the lip.
##  - kicker: curves all the way up, steepest at the lip.
##  - landing: a curved run-out at the toe, the long straight slope, then rounding over on to a
##    flat top at the high end (the end that faces the jump).
##  - table: up, a flat top, and down the far side, every change rounded.
const PROFILES := {
	"launch": [[0.0, 0.0], [0.3, 1.0], [1.0, 1.0]],
	"kicker": [[0.0, 0.0], [1.0, 1.0]],
	"landing": [[0.0, 0.0], [0.3, 1.0], [0.82, 1.0], [0.92, 0.0], [1.0, 0.0]],
	"table": [[0.0, 0.0], [0.08, 1.0], [0.28, 1.0], [0.36, 0.0], [0.64, 0.0], [0.72, -1.0], [0.92, -1.0], [1.0, 0.0]],
}
## A deck's pictures repeat every SHEET metres along it.
const SHEET := 1.2
## The steel toe plate and lip plate on a wooden ramp, metres along the deck.
const TOE_PLATE := 0.14
const LIP_PLATE := 0.1
## A tabletop's top is this much narrower than its base, each side: the banks.
const TABLE_BANK := 0.6
## An old single-decker: length (along its own x), width (z), and its roof's height.
const BUS_LENGTH := 10.0
const BUS_WIDTH := 2.5
const BUS_HEIGHT := 3.0
## Bus liveries: main colour and band colour.
const LIVERIES := [["8c1a12", "e8dcc0"], ["1f5a32", "e3d9b8"], ["1d3f7a", "dcdcd4"], ["d6c49a", "6a1c18"], ["b8561a", "ece4cc"]]

static var _meshes := {}     # model -> ArrayMesh
static var _profiles := {}   # model -> PackedVector2Array


## Draws `model` under `parent` (in its own space, +Z its front) and adds its collision.
static func build(parent: Node3D, model: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Kit"
	mi.mesh = mesh_of(model)
	parent.add_child(mi)
	_collide(parent, model)


## The one mesh every copy of `model` is drawn with.
static func mesh_of(model: String) -> ArrayMesh:
	if not _meshes.has(model):
		var k := Mesher.new()
		_draw(k, model)
		_meshes[model] = k.commit()
	return _meshes[model]


# ---------------------------------------------------------------------------- profiles

## The deck's line from the toe (z = +length/2, on the ground) to the far end (z = -length/2),
## as (z, height) points a few centimetres apart. Empty for kit without a profile.
static func profile(model: String) -> PackedVector2Array:
	if _profiles.has(model):
		return _profiles[model]
	var m := Equipment.get_model(model)
	var pts := PackedVector2Array()
	if not m.has("profile"):
		return pts
	var size: Vector3 = m["size"]
	var keys: Array = PROFILES[str(m["profile"])]
	var n := clampi(ceili(size.z / 0.06), 24, 240)
	var ys: Array[float] = [0.0]
	var acc := 0.0
	for i in n:
		var s0 := float(i) / n
		var s1 := float(i + 1) / n
		acc += (_shape(keys, s0) + 4.0 * _shape(keys, (s0 + s1) * 0.5) + _shape(keys, s1)) / 6.0 / n
		ys.append(acc)
	var top := 0.0
	for y in ys:
		top = maxf(top, y)
	for i in n + 1:
		pts.append(Vector2(size.z * 0.5 - size.z * float(i) / n, maxf(ys[i], 0.0) / top * size.y))
	_profiles[model] = pts
	return pts


static func _shape(keys: Array, s: float) -> float:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if s <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6))
	return float(keys[keys.size() - 1][1])


## How high the deck is at `z` along it (its own space); 0 off either end.
static func deck_height(model: String, z: float) -> float:
	var pts := profile(model)
	for i in pts.size() - 1:
		if z <= pts[i].x and z >= pts[i + 1].x:
			return lerpf(pts[i].y, pts[i + 1].y, (pts[i].x - z) / maxf(pts[i].x - pts[i + 1].x, 1e-6))
	return 0.0


## The steepest the deck gets, and how steep it is at the lip (its far end), in degrees.
static func lip_angle(model: String) -> float:
	var pts := profile(model)
	if pts.size() < 2:
		return 0.0
	var a := pts[pts.size() - 2]
	var b := pts[pts.size() - 1]
	return rad_to_deg(atan2(b.y - a.y, a.x - b.x))


## Half the deck's width: a tabletop's top is narrower than its base.
static func deck_half_width(model: String) -> float:
	var size: Vector3 = Equipment.get_model(model).get("size", Vector3.ONE)
	return size.x * 0.5 - (TABLE_BANK if str(Equipment.get_model(model).get("profile", "")) == "table" else 0.0)


# ---------------------------------------------------------------------------- collision

static func _collide(parent: Node3D, model: String) -> void:
	var m := Equipment.get_model(model)
	var size: Vector3 = m.get("size", Vector3.ONE)
	if not m.get("solid", false):
		return   # markers: ride straight through them
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.set_meta("surface", "dirt" if model in ["tabletop", "hay_bales", "log"] else "tarmac")
	parent.add_child(body)
	if m.has("profile"):
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(profile_faces(model))
		_shape_at(body, shape, Transform3D())
		return
	match model:
		"barrels":
			for i in 3:
				var c := CylinderShape3D.new()
				c.radius = 0.285
				c.height = 0.86
				_shape_at(body, c, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.62 + i * 0.62, 0.335, 0.0)))
		"log":
			var c := CylinderShape3D.new()
			c.radius = 0.22
			c.height = size.x
			_shape_at(body, c, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 0.22, 0.0)))
		"tyre_stack":
			var c := CylinderShape3D.new()
			c.radius = 0.37
			c.height = size.y
			_shape_at(body, c, Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)))
		"car_wreck":
			_box_at(body, Vector3(0.0, 0.44, 0.0), Vector3(size.x, 0.88, size.z))
			_box_at(body, Vector3(0.0, 1.1, -0.25), Vector3(1.5, 0.46, 2.3))
		"wall_concrete":
			var hull := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for p in _jersey():
				pts.append(Vector3(-size.x * 0.5, p.y, p.x))
				pts.append(Vector3(size.x * 0.5, p.y, p.x))
			hull.points = pts
			_shape_at(body, hull, Transform3D())
		_:
			# Buses, bales, walls and fences: solid boxes to their tops (a bus to its roof).
			_box_at(body, Vector3(0.0, size.y * 0.5, 0.0), size)


static func _shape_at(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


static func _box_at(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_shape_at(body, b, Transform3D(Basis(), center))


## The triangles of a ramp's or tabletop's solid: its deck, its sides down to the ground and
## its far end. The same points the deck is drawn with.
static func profile_faces(model: String) -> PackedVector3Array:
	var size: Vector3 = Equipment.get_model(model)["size"]
	var pts := profile(model)
	var w := size.x * 0.5
	var top := deck_half_width(model)
	var f := PackedVector3Array()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		f.append_array([a, b, c, a, c, d])
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		quad.call(Vector3(-top, p.y, p.x), Vector3(top, p.y, p.x), Vector3(top, q.y, q.x), Vector3(-top, q.y, q.x))
		for s: float in [-1.0, 1.0]:
			quad.call(Vector3(s * top, p.y, p.x), Vector3(s * w, 0.0, p.x), Vector3(s * w, 0.0, q.x), Vector3(s * top, q.y, q.x))
	var end := pts[pts.size() - 1]
	if end.y > 0.001:
		quad.call(Vector3(-top, end.y, end.x), Vector3(top, end.y, end.x), Vector3(w, 0.0, end.x), Vector3(-w, 0.0, end.x))
	return f


# ---------------------------------------------------------------------------- drawing

static func _draw(k: Mesher, model: String) -> void:
	var m := Equipment.get_model(model)
	if model == "tabletop":
		_tabletop(k, model)
		return
	if m.has("profile"):
		_ramp(k, model)
		return
	var size: Vector3 = m.get("size", Vector3.ONE)
	match model:
		"barrels":
			_barrels(k)
		"log":
			_log(k, size)
		"tyre_stack":
			_tyre_stack(k)
		"hay_bales":
			_hay_bales(k)
		"car_wreck":
			_car(k)
		"bus":
			_bus(k, Transform3D(), 0)
		"bus_row":
			for i in 5:
				var flip := Basis(Vector3.UP, PI) if i % 2 == 1 else Basis()
				_bus(k, Transform3D(flip, Vector3(0.0, 0.0, (i - 2) * BUS_WIDTH)), i)
		"wall_concrete":
			_barrier(k, size)
		"wall_brick":
			_brick_wall(k, size)
		"fence_wood":
			_wood_fence(k, size)
		"fence_mesh":
			_mesh_fence(k, size)
		"cone":
			_cone(k)
		"post":
			_post(k)
		"flag_red", "flag_blue", "flag_chequered":
			_flag(k, model, size)


## A take-off or landing ramp: its deck along the profile, then a plywood box with battens or a
## braced steel frame under it.
static func _ramp(k: Mesher, model: String) -> void:
	var m := Equipment.get_model(model)
	var size: Vector3 = m["size"]
	var w := size.x * 0.5
	var pts := profile(model)
	var steel := str(m.get("deck", "wood")) == "steel"
	var n := pts.size()
	var arc: Array[float] = [0.0]
	for i in range(1, n):
		arc.append(arc[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = arc[n - 1]
	var normals := _deck_normals(pts)
	# The deck. A wooden one has a steel plate at its toe and its lip.
	for i in n - 1:
		var mid := (arc[i] + arc[i + 1]) * 0.5
		var key := "steel_deck" if steel else "ply_deck"
		if not steel and (mid < TOE_PLATE or total - mid < LIP_PLATE):
			key = "steel"
		var p := pts[i]
		var q := pts[i + 1]
		k.quad_n(key, [Vector3(-w, p.y, p.x), Vector3(w, p.y, p.x), Vector3(w, q.y, q.x), Vector3(-w, q.y, q.x)],
			[normals[i], normals[i], normals[i + 1], normals[i + 1]],
			[Vector2(0.0, arc[i] / SHEET), Vector2(1.0, arc[i] / SHEET), Vector2(1.0, arc[i + 1] / SHEET), Vector2(0.0, arc[i + 1] / SHEET)])
	if steel:
		_steel_frame(k, model, pts, arc)
	else:
		_wood_box(k, model, pts)


## The deck's smooth normals at each of its points.
static func _deck_normals(pts: PackedVector2Array) -> Array[Vector3]:
	var seg: Array[Vector3] = []
	for i in pts.size() - 1:
		var t := Vector3(0.0, pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
		seg.append(Vector3(0.0, -t.z, t.y).normalized())
	var out: Array[Vector3] = []
	for i in pts.size():
		var a: Vector3 = seg[maxi(i - 1, 0)]
		var b: Vector3 = seg[mini(i, seg.size() - 1)]
		out.append((a + b).normalized())
	return out


## The sides and far end of a wooden ramp: plywood panels (or painted ones), battens screwed on,
## and a band of hazard paint along the top edge.
static func _wood_box(k: Mesher, model: String, pts: PackedVector2Array) -> void:
	var m := Equipment.get_model(model)
	var size: Vector3 = m["size"]
	var w := size.x * 0.5
	var side := "paint@%s" % (m["color"] as Color).to_html(false) if m.has("color") else "ply_side"
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		for s: float in [-1.0, 1.0]:
			k.quad(side, Vector3(s * w, 0.0, p.x), Vector3(s * w, p.y, p.x), Vector3(s * w, q.y, q.x), Vector3(s * w, 0.0, q.x), Vector3(s, 0.0, 0.0))
			if p.y > 0.07 and q.y > 0.07:
				var o := s * (w + 0.003)
				k.quad("hazard", Vector3(o, p.y - 0.06, p.x), Vector3(o, p.y, p.x), Vector3(o, q.y, q.x), Vector3(o, q.y - 0.06, q.x), Vector3(s, 0.0, 0.0))
	var end := pts[pts.size() - 1]
	if end.y > 0.01:
		k.quad(side, Vector3(-w, 0.0, end.x), Vector3(w, 0.0, end.x), Vector3(w, end.y, end.x), Vector3(-w, end.y, end.x), Vector3.FORWARD)
		k.quad("hazard", Vector3(-w, end.y - 0.08, end.x - 0.003), Vector3(w, end.y - 0.08, end.x - 0.003), Vector3(w, end.y, end.x - 0.003),
			Vector3(-w, end.y, end.x - 0.003), Vector3.FORWARD)
		for x: float in [-w + 0.06, 0.0, w - 0.06]:
			k.box("timber", Transform3D(Basis(), Vector3(x, (end.y - 0.09) * 0.5, end.x - 0.025)), Vector3(0.07, end.y - 0.09, 0.045))
	# Battens down each side, two screws in each.
	var z := size.z * 0.5 - 0.35
	while z > -size.z * 0.5 + 0.1:
		var h := deck_height(model, z) - 0.07
		if h > 0.1:
			for s: float in [-1.0, 1.0]:
				k.box("timber", Transform3D(Basis(), Vector3(s * (w + 0.022), h * 0.5, z)), Vector3(0.04, h, 0.07))
				for t: float in [0.3, 0.75]:
					k.cyl("bolt", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * (w + 0.044), h * t, z)), 0.011, 0.006, 6)
		z -= 0.6


## A steel ramp's frame: channel stringers under the deck, legs on foot plates, ties and
## diagonal braces, base rails, an X-braced far end, and the lip's back face in hazard stripes.
static func _steel_frame(k: Mesher, model: String, pts: PackedVector2Array, arc: Array[float]) -> void:
	var m := Equipment.get_model(model)
	var size: Vector3 = m["size"]
	var w := size.x * 0.5
	var paint := "paint@%s" % (m.get("color", Color(0.4, 0.42, 0.45)) as Color).to_html(false)
	var plate := 0.012
	var deep := 0.16
	var total: float = arc[arc.size() - 1]
	# The deck plate's edges and underside.
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		for s: float in [-1.0, 1.0]:
			k.quad("steel", Vector3(s * w, maxf(p.y - plate, 0.0), p.x), Vector3(s * w, p.y, p.x), Vector3(s * w, q.y, q.x),
				Vector3(s * w, maxf(q.y - plate, 0.0), q.x), Vector3(s, 0.0, 0.0))
		if p.y > plate and q.y > plate:
			k.quad("steel", Vector3(-w, p.y - plate, p.x), Vector3(w, p.y - plate, p.x), Vector3(w, q.y - plate, q.x), Vector3(-w, q.y - plate, q.x), Vector3.DOWN)
	# Stringers: channels following the deck, the outer two striped near the lip.
	var xs := [-w + 0.05, w - 0.05]
	if size.x > 2.4:
		xs.append(0.0)
	for x: float in xs:
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var pt := p.y - plate
			var qt := q.y - plate
			if pt <= 0.0 or qt <= 0.0:
				continue
			var pb := maxf(pt - deep, 0.0)
			var qb := maxf(qt - deep, 0.0)
			var key := paint
			if absf(x) > 0.01 and total - (arc[i] + arc[i + 1]) * 0.5 < 1.2:
				key = "hazard"
			for s: float in [-1.0, 1.0]:
				var xo := x + s * 0.035
				k.quad(key if s * x > 0.0 else paint, Vector3(xo, pb, p.x), Vector3(xo, pt, p.x), Vector3(xo, qt, q.x), Vector3(xo, qb, q.x), Vector3(s, 0.0, 0.0))
			if pb > 0.0:
				k.quad(paint, Vector3(x - 0.035, pb, p.x), Vector3(x + 0.035, pb, p.x), Vector3(x + 0.035, qb, q.x), Vector3(x - 0.035, qb, q.x), Vector3.DOWN)
	# Legs every metre or so, wherever the deck's high enough, and at the far end.
	var legs: Array[float] = []
	var z := size.z * 0.5 - 1.0
	while z > -size.z * 0.5 + 0.6:
		if deck_height(model, z) > 0.45:
			legs.append(z)
		z -= 1.15
	legs.append(-size.z * 0.5 + 0.05)
	var lx := w - 0.05
	var tops: Array[float] = []
	for lz in legs:
		var top := deck_height(model, lz) - plate - deep
		tops.append(top)
		for s: float in [-1.0, 1.0]:
			k.box(paint, Transform3D(Basis(), Vector3(s * lx, top * 0.5, lz)), Vector3(0.07, top, 0.07))
			k.box("steel", Transform3D(Basis(), Vector3(s * lx, 0.006, lz)), Vector3(0.17, 0.012, 0.17))
			for c in [Vector2(-0.06, -0.06), Vector2(0.06, -0.06), Vector2(-0.06, 0.06), Vector2(0.06, 0.06)]:
				k.cyl("bolt", Transform3D(Basis(), Vector3(s * lx + c.x, 0.018, lz + c.y)), 0.012, 0.014, 6)
			for t: float in [-0.05, 0.05]:
				k.cyl("bolt", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * (lx + 0.04), top + deep * 0.5, lz + t)), 0.013, 0.012, 6)
		k.box(paint, Transform3D(Basis(), Vector3(0.0, top * 0.45, lz)), Vector3(lx * 2.0, 0.05, 0.05))
		k.box(paint, Transform3D(Basis(), Vector3(0.0, top - 0.03, lz)), Vector3(lx * 2.0, 0.06, 0.06))
	# Diagonals between the legs down each side, and base rails along the ground.
	for i in legs.size() - 1:
		for s: float in [-1.0, 1.0]:
			var a := Vector3(s * lx, 0.12, legs[i])
			var b := Vector3(s * lx, tops[i + 1] - 0.06, legs[i + 1])
			if i % 2 == 1:
				a = Vector3(s * lx, tops[i] - 0.06, legs[i])
				b = Vector3(s * lx, 0.12, legs[i + 1])
			k.beam(paint, a, b, Vector2(0.045, 0.045))
	var toe_z := size.z * 0.5 - 0.25
	var back_z := -size.z * 0.5 + 0.05
	for s: float in [-1.0, 1.0]:
		k.box(paint, Transform3D(Basis(), Vector3(s * lx, 0.03, (toe_z + back_z) * 0.5)), Vector3(0.08, 0.06, toe_z - back_z))
	# The far end: X-braced, the lip's face striped.
	var back_top: float = tops[tops.size() - 1]
	k.beam(paint, Vector3(-lx, 0.1, back_z), Vector3(lx, back_top - 0.08, back_z), Vector2(0.05, 0.05))
	k.beam(paint, Vector3(lx, 0.1, back_z), Vector3(-lx, back_top - 0.08, back_z), Vector2(0.05, 0.05))
	var end := pts[pts.size() - 1]
	# A plate on the far face, its top just under the deck's edge so nothing stands proud of the lip.
	k.box("hazard", Transform3D(Basis(), Vector3(0.0, end.y - 0.004 - deep * 0.5, end.x - 0.007)), Vector3(w * 2.0, deep, 0.012))


## The dirt tabletop: a packed, rutted top along its profile and banks down to the ground,
## with half-buried tyres at its corners and a few stones.
static func _tabletop(k: Mesher, model: String) -> void:
	var size: Vector3 = Equipment.get_model(model)["size"]
	var w := size.x * 0.5
	var top := deck_half_width(model)
	var pts := profile(model)
	var normals := _deck_normals(pts)
	var arc := 0.0
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var next := arc + p.distance_to(q)
		k.quad_n("dirt_deck", [Vector3(-top, p.y, p.x), Vector3(top, p.y, p.x), Vector3(top, q.y, q.x), Vector3(-top, q.y, q.x)],
			[normals[i], normals[i], normals[i + 1], normals[i + 1]],
			[Vector2(0.0, arc / SHEET), Vector2(1.0, arc / SHEET), Vector2(1.0, next / SHEET), Vector2(0.0, next / SHEET)])
		arc = next
		for s: float in [-1.0, 1.0]:
			k.quad("dirt", Vector3(s * top, p.y, p.x), Vector3(s * w, 0.0, p.x), Vector3(s * w, 0.0, q.x), Vector3(s * top, q.y, q.x),
				Vector3(s * p.y, TABLE_BANK, 0.0).normalized() if p.y > 0.01 else Vector3.UP)
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			k.torus("tread", Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.3 * e), Vector3(s * (w + 0.15), 0.12, e * (size.z * 0.5 - 0.6))), 0.26, 0.09, 12, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		var at := Vector3(rng.randf_range(-1.0, 1.0) * (w - 0.1), 0.03, rng.randf_range(-0.4, 0.4) * size.z)
		at.x = signf(at.x) * (w - rng.randf_range(0.02, 0.25))
		k.box("concrete", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf() * 0.5), at),
			Vector3(rng.randf_range(0.08, 0.18), rng.randf_range(0.06, 0.12), rng.randf_range(0.08, 0.16)), 0.02)


## Three oil drums on their sides on two timbers: hooped, chimed, a bung in each lid.
static func _barrels(k: Mesher) -> void:
	for z: float in [-0.3, 0.3]:
		k.box("timber", Transform3D(Basis(), Vector3(0.0, 0.025, z)), Vector3(1.9, 0.05, 0.1), 0.008)
	var paints := ["drum_blue", "drum_red", "drum_green"]
	var r := 0.285
	for i in 3:
		var x := -0.62 + i * 0.62
		var along := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, i * 1.3)
		var c := Vector3(x, 0.335, 0.0)
		k.cyl(paints[i], Transform3D(along, c), r, 0.84, 20)
		for z: float in [-0.28, 0.28]:
			k.cyl(paints[i], Transform3D(along, c + Vector3(0.0, 0.0, z)), r + 0.008, 0.03, 20)
		for z: float in [-0.425, 0.425]:
			k.cyl("steel", Transform3D(along, c + Vector3(0.0, 0.0, z)), r + 0.004, 0.025, 20, -1.0, "", false)
		k.cyl("bolt", Transform3D(along, c + Vector3(0.12, 0.08, 0.44)), 0.03, 0.015, 8)
		k.cyl("bolt", Transform3D(along, c + Vector3(-0.15, -0.05, 0.44)), 0.016, 0.012, 8)


static func _log(k: Mesher, size: Vector3) -> void:
	var along := Basis(Vector3.BACK, PI * 0.5)
	k.cyl("bark", Transform3D(along, Vector3(0.0, 0.22, 0.0)), 0.22, size.x, 14, 0.2, "log_end")
	# A sawn-off branch and two chocks.
	k.cyl("bark", Transform3D(Basis(Vector3.BACK, -0.5) * Basis(Vector3.RIGHT, 0.3), Vector3(0.4, 0.42, 0.04)), 0.05, 0.22, 8, 0.04, "log_end")
	for x: float in [-0.8, 0.8]:
		for s: float in [-1.0, 1.0]:
			k.box("timber", Transform3D(Basis(Vector3.RIGHT, s * 0.6), Vector3(x, 0.04, s * 0.2)), Vector3(0.12, 0.07, 0.12), 0.01)


static func _tyre_stack(k: Mesher) -> void:
	for i in 5:
		var off := Vector3(sin(i * 2.1) * 0.025, 0.1 + i * 0.18, cos(i * 1.7) * 0.025)
		k.torus("tread", Transform3D(Basis(Vector3.UP, i * 0.7) * Basis(Vector3.RIGHT, sin(i * 3.0) * 0.03), off), 0.27, 0.095, 18, 8)
		k.cyl("rubber", Transform3D(Basis(), off), 0.2, 0.06, 14)


static func _hay_bales(k: Mesher) -> void:
	for x: float in [-0.55, 0.55]:
		k.box("hay", Transform3D(Basis(Vector3.UP, x * 0.05), Vector3(x, 0.25, 0.0)), Vector3(1.05, 0.5, 1.0), 0.06)
		for t: float in [-0.25, 0.25]:
			k.box("twine", Transform3D(Basis(Vector3.UP, x * 0.05), Vector3(x + t, 0.25, 0.0)), Vector3(0.015, 0.505, 1.004), 0.05)


## A rusting old saloon: body and cabin shaped from the side, wheel arches, flat tyres, glass,
## chrome and lamps.
static func _car(k: Mesher) -> void:
	var body := PackedVector2Array([Vector2(-2.0, 0.32), Vector2(1.98, 0.32), Vector2(2.0, 0.56), Vector2(1.95, 0.78),
		Vector2(1.1, 0.86), Vector2(-1.6, 0.89), Vector2(-1.98, 0.82), Vector2(-2.0, 0.56)])
	k.extrude("car_paint", Transform3D(), body, -0.85, 0.85)
	var cabin := PackedVector2Array([Vector2(0.95, 0.86), Vector2(0.32, 1.33), Vector2(-0.95, 1.33), Vector2(-1.45, 0.88)])
	k.extrude("car_paint", Transform3D(), cabin, -0.75, 0.75)
	var glass := PackedVector2Array([Vector2(0.8, 0.91), Vector2(0.3, 1.28), Vector2(-0.9, 1.28), Vector2(-1.33, 0.91)])
	for s: float in [-1.0, 1.0]:
		k.extrude("glass_dirty", Transform3D(), glass, s * 0.751, s * 0.757)
		k.box("car_paint", Transform3D(Basis(), Vector3(s * 0.755, 1.1, -0.28)), Vector3(0.012, 0.4, 0.09))
	# Windscreen and rear screen, just proud of the cabin's sloping ends.
	for e in [[Vector2(0.95, 0.86), Vector2(0.32, 1.33)], [Vector2(-0.95, 1.33), Vector2(-1.45, 0.88)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var d := (b - a).normalized()
		var n := _slope_normal(a, b, Vector3(0.0, 0.95, -0.3))
		var off := n * 0.004
		var a3 := Vector3(0.0, a.y, a.x) + Vector3(0.0, d.y, d.x) * 0.05 + off
		var b3 := Vector3(0.0, b.y, b.x) - Vector3(0.0, d.y, d.x) * 0.05 + off
		k.quad("glass", a3 + Vector3(-0.68, 0.0, 0.0), a3 + Vector3(0.68, 0.0, 0.0), b3 + Vector3(0.68, 0.0, 0.0), b3 + Vector3(-0.68, 0.0, 0.0), n)
	# Wheel arches, tyres gone flat on rusty rims.
	for z: float in [-1.3, 1.3]:
		var arch := PackedVector2Array()
		for i in 9:
			var a := PI * i / 8.0
			arch.append(Vector2(z + cos(a) * 0.36, 0.32 + sin(a) * 0.3))
		for s: float in [-1.0, 1.0]:
			k.extrude("black", Transform3D(), arch, s * 0.851, s * 0.856)
			var flat := 0.04 if z > 0.0 and s > 0.0 else 0.0
			var wheel := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.74, 0.3 - flat, z))
			k.torus("tread", wheel.scaled_local(Vector3(1.0, 1.0, 1.0 - flat * 3.0)), 0.21, 0.09, 16, 8)
			k.cyl("rust", wheel, 0.16, 0.12, 14)
			k.cyl("bolt", Transform3D(wheel.basis, wheel.origin + Vector3(s * 0.065, 0.0, 0.0)), 0.05, 0.02, 8)
	for e: float in [-1.0, 1.0]:
		k.box("chrome", Transform3D(Basis(), Vector3(0.0, 0.42, e * 2.03)), Vector3(1.74, 0.11, 0.08), 0.02)
		for s: float in [-1.0, 1.0]:
			if e > 0.0:
				k.cyl("chrome", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.62, 0.63, 1.99)), 0.1, 0.03, 12)
				k.cyl("lamp", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.62, 0.63, 2.006)), 0.08, 0.01, 12)
				k.box("amber", Transform3D(Basis(), Vector3(s * 0.75, 0.5, 2.0)), Vector3(0.12, 0.05, 0.02))
			else:
				k.box("tail", Transform3D(Basis(), Vector3(s * 0.68, 0.68, -2.0)), Vector3(0.24, 0.12, 0.02))
	k.box("black", Transform3D(Basis(), Vector3(0.0, 0.62, 2.0)), Vector3(0.9, 0.16, 0.02))
	for i in 6:
		k.box("chrome", Transform3D(Basis(), Vector3(0.0, 0.56 + i * 0.024, 2.008)), Vector3(0.86, 0.006, 0.006))
	# Rust holes along the sills and a dent in the boot.
	for p in [Vector3(0.852, 0.4, 0.55), Vector3(-0.852, 0.42, -0.7), Vector3(0.852, 0.45, -1.75), Vector3(-0.852, 0.4, 1.75)]:
		k.box("rust", Transform3D(Basis(), p), Vector3(0.008, 0.12, 0.35), 0.003)
	k.box("rust", Transform3D(Basis(), Vector3(0.3, 0.885, -1.75)), Vector3(0.5, 0.01, 0.3))


## An old single-decker in livery `n`, its length along x and its door on +z (flipped by `xf`).
static func _bus(k: Mesher, xf: Transform3D, n: int) -> void:
	var main := "bus@%s" % LIVERIES[n % LIVERIES.size()][0]
	var band := "bus@%s" % LIVERIES[n % LIVERIES.size()][1]
	var hl := BUS_LENGTH * 0.5
	var hw := BUS_WIDTH * 0.5 - 0.01
	# Upper body to the roof, lower panels between the wheel arches.
	_bb(k, xf, main, Vector3(0.0, 2.0, 0.0), Vector3(BUS_LENGTH, 1.76, hw * 2.0), 0.1)
	_bb(k, xf, "bus_roof", Vector3(0.0, BUS_HEIGHT - 0.06, 0.0), Vector3(BUS_LENGTH - 0.12, 0.12, hw * 2.0 - 0.1), 0.04)
	var front_axle := hl - 2.35
	var rear_axle := -hl + 2.7
	var arch := 0.66
	var spans := [[-hl, rear_axle - arch], [rear_axle + arch, front_axle - arch], [front_axle + arch, hl]]
	for sp: Array in spans:
		var a: float = sp[0]
		var b: float = sp[1]
		_bb(k, xf, main, Vector3((a + b) * 0.5, 0.78, 0.0), Vector3(b - a, 0.8, hw * 2.0), 0.03)
	for ax: float in [rear_axle, front_axle]:
		_bb(k, xf, main, Vector3(ax, 1.1, 0.0), Vector3(arch * 2.0, 0.16, hw * 2.0))
		_bb(k, xf, "black", Vector3(ax, 0.75, 0.0), Vector3(arch * 2.0, 0.7, hw * 2.0 - 0.7))
		for s: float in [-1.0, 1.0]:
			var wheel := xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(ax, 0.5, s * (hw - 0.17)))
			k.cyl("tread", wheel, 0.5, 0.3, 20)
			k.cyl("steel", Transform3D(wheel.basis, wheel.origin + xf.basis * Vector3(0.0, 0.0, s * 0.152)), 0.3, 0.01, 16)
			k.cyl("bolt", Transform3D(wheel.basis, wheel.origin + xf.basis * Vector3(0.0, 0.0, s * 0.165)), 0.09, 0.03, 8)
			# The arch's black trim.
			_bb(k, xf, "black", Vector3(ax, 1.03, s * (hw + 0.004)), Vector3(arch * 2.0 + 0.06, 0.05, 0.01))
			for e: float in [-1.0, 1.0]:
				_bb(k, xf, "black", Vector3(ax + e * (arch + 0.015), 0.69, s * (hw + 0.004)), Vector3(0.05, 0.68, 0.01))
	# Bands, rubbing strip and bumpers.
	_bb(k, xf, band, Vector3(0.0, 1.2, 0.0), Vector3(BUS_LENGTH + 0.01, 0.16, hw * 2.0 + 0.008))
	_bb(k, xf, band, Vector3(0.0, 2.36, 0.0), Vector3(BUS_LENGTH + 0.01, 0.1, hw * 2.0 + 0.008))
	_bb(k, xf, "black", Vector3(0.0, 0.42, 0.0), Vector3(BUS_LENGTH + 0.02, 0.08, hw * 2.0 + 0.02))
	for e: float in [-1.0, 1.0]:
		_bb(k, xf, "black", Vector3(e * (hl + 0.04), 0.5, 0.0), Vector3(0.1, 0.24, hw * 2.0 + 0.02), 0.02)
	# Windows down both sides with pillars, the door and the driver's window.
	var win_a := -hl + 0.5
	var win_b := hl - 1.95
	for s: float in [-1.0, 1.0]:
		_bb(k, xf, "glass", Vector3((win_a + win_b) * 0.5, 1.84, s * (hw + 0.003)), Vector3(win_b - win_a, 0.84, 0.008))
		var x := win_a
		while x <= win_b + 0.01:
			_bb(k, xf, main, Vector3(x, 1.84, s * (hw + 0.007)), Vector3(0.09, 0.88, 0.01))
			x += (win_b - win_a) / 8.0
		_bb(k, xf, "black", Vector3((win_a + win_b) * 0.5, 2.27, s * (hw + 0.009)), Vector3(win_b - win_a, 0.02, 0.01))
	_bb(k, xf, "glass", Vector3(hl - 1.1, 1.34, hw + 0.003), Vector3(1.4, 1.76, 0.008))
	_bb(k, xf, "black", Vector3(hl - 1.1, 1.34, hw + 0.008), Vector3(0.035, 1.76, 0.01))
	_bb(k, xf, "black", Vector3(hl - 1.1, 0.47, hw + 0.008), Vector3(1.45, 0.05, 0.01))
	_bb(k, xf, "glass", Vector3(hl - 1.1, 1.84, -hw - 0.003), Vector3(1.4, 0.84, 0.008))
	# Front: two-piece windscreen, destination blind, lamps. Back: window and engine grille.
	_bb(k, xf, "glass", Vector3(hl + 0.003, 1.78, 0.0), Vector3(0.008, 1.02, hw * 2.0 - 0.2))
	_bb(k, xf, main, Vector3(hl + 0.006, 1.78, 0.0), Vector3(0.01, 1.04, 0.07))
	_bb(k, xf, "black", Vector3(hl + 0.004, 2.55, 0.0), Vector3(0.01, 0.26, 1.5))
	_bb(k, xf, "lamp", Vector3(hl + 0.008, 2.55, 0.0), Vector3(0.01, 0.13, 1.1))
	_bb(k, xf, "glass", Vector3(-hl - 0.003, 2.0, 0.0), Vector3(0.008, 0.62, 1.7))
	_bb(k, xf, "black", Vector3(-hl - 0.004, 0.86, 0.0), Vector3(0.01, 0.46, 1.9))
	for i in 5:
		_bb(k, xf, main, Vector3(-hl - 0.008, 0.7 + i * 0.08, 0.0), Vector3(0.008, 0.02, 1.9))
	for s: float in [-1.0, 1.0]:
		var lamp := xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(hl + 0.01, 0.8, s * 0.9))
		k.cyl("chrome", lamp, 0.12, 0.03, 12)
		k.cyl("lamp", Transform3D(lamp.basis, lamp.origin + xf.basis * Vector3(0.016, 0.0, 0.0)), 0.095, 0.01, 12)
		_bb(k, xf, "amber", Vector3(hl + 0.01, 0.8, s * 0.65), Vector3(0.02, 0.08, 0.12))
		_bb(k, xf, "tail", Vector3(-hl - 0.01, 0.8, s * 0.95), Vector3(0.02, 0.22, 0.16))
		_bb(k, xf, "amber", Vector3(-hl - 0.01, 1.0, s * 0.95), Vector3(0.02, 0.1, 0.16))
		# Mirror on a stalk at each front corner.
		_bb(k, xf, "black", Vector3(hl + 0.12, 2.15, s * (hw - 0.05)), Vector3(0.24, 0.03, 0.03))
		_bb(k, xf, "black", Vector3(hl + 0.24, 1.95, s * (hw - 0.05)), Vector3(0.04, 0.32, 0.18), 0.01)
	# Rust coming through low down, different on every bus.
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + n
	for i in 7:
		var s := -1.0 if rng.randf() < 0.5 else 1.0
		var at := Vector3(rng.randf_range(-hl + 0.5, hl - 0.5), rng.randf_range(0.5, 1.0), s * (hw + 0.004))
		_bb(k, xf, "rust", at, Vector3(rng.randf_range(0.15, 0.6), rng.randf_range(0.06, 0.2), 0.008))


## A box on a bus: `c` and `s` in the bus's own space, which `xf` puts in the kit's.
static func _bb(k: Mesher, xf: Transform3D, key: String, c: Vector3, s: Vector3, bevel := 0.0) -> void:
	k.box(key, xf * Transform3D(Basis(), c), s, bevel)


## The face of a sloping edge from `a` to `b` ((z, y) points), facing away from `inside`.
static func _slope_normal(a: Vector2, b: Vector2, inside: Vector3) -> Vector3:
	var t := Vector3(0.0, b.y - a.y, b.x - a.x).normalized()
	var n := Vector3.RIGHT.cross(t).normalized()
	return n if n.dot(Vector3(0.0, a.y, a.x) - inside) > 0.0 else -n


## The Jersey barrier's cross-section (z, y), the same for its drawing and its collision.
static func _jersey() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.08), Vector2(0.17, 0.26), Vector2(0.085, 0.76),
		Vector2(0.05, 0.8), Vector2(-0.05, 0.8), Vector2(-0.085, 0.76), Vector2(-0.17, 0.26), Vector2(-0.3, 0.08)])


static func _barrier(k: Mesher, size: Vector3) -> void:
	var hx := size.x * 0.5 - 0.005
	k.extrude("concrete", Transform3D(), _jersey(), -hx, hx)
	# A red and white reflective band on both faces, fork slots at the foot, lifting eyes on top.
	for s: float in [-1.0, 1.0]:
		var a := Vector2(s * 0.17, 0.26)
		var b := Vector2(s * 0.085, 0.76)
		var n := _slope_normal(a, b, Vector3(0.0, 0.4, 0.0))
		var p0 := a.lerp(b, 0.56)
		var p1 := a.lerp(b, 0.74)
		var o := n * 0.003
		k.quad("reflect_red", Vector3(-hx + 0.08, p0.y, p0.x) + o, Vector3(hx - 0.08, p0.y, p0.x) + o, Vector3(hx - 0.08, p1.y, p1.x) + o,
			Vector3(-hx + 0.08, p1.y, p1.x) + o, n)
		for x: float in [-0.55, 0.55]:
			k.quad("black", Vector3(x - 0.16, 0.0, s * 0.302), Vector3(x + 0.16, 0.0, s * 0.302), Vector3(x + 0.16, 0.07, s * 0.302),
				Vector3(x - 0.16, 0.07, s * 0.302), Vector3(0.0, 0.0, s))
	for x: float in [-0.6, 0.6]:
		k.torus("steel", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.8, 0.0)), 0.035, 0.009, 10, 5)


static func _brick_wall(k: Mesher, size: Vector3) -> void:
	var frame := "paint@%s" % Color(0.22, 0.24, 0.26).to_html(false)
	k.box(frame, Transform3D(Basis(), Vector3(0.0, 0.05, 0.0)), Vector3(size.x, 0.1, size.z + 0.04), 0.01)
	for x: float in [-size.x * 0.5 + 0.12, size.x * 0.5 - 0.12]:
		k.box(frame, Transform3D(Basis(), Vector3(x, 0.03, 0.0)), Vector3(0.1, 0.06, 0.75), 0.01)
		for z: float in [-0.3, 0.3]:
			k.cyl("bolt", Transform3D(Basis(), Vector3(x, 0.065, z)), 0.014, 0.012, 6)
	k.box("brick", Transform3D(Basis(), Vector3(0.0, 0.1 + 0.51, 0.0)), Vector3(size.x - 0.04, 1.02, size.z - 0.07))
	k.box("concrete", Transform3D(Basis(), Vector3(0.0, size.y - 0.04, 0.0)), Vector3(size.x, 0.08, size.z), 0.012)


static func _wood_fence(k: Mesher, size: Vector3) -> void:
	for x: float in [-size.x * 0.5 + 0.05, 0.0, size.x * 0.5 - 0.05]:
		k.box("fence_wood", Transform3D(Basis(), Vector3(x, 0.5, 0.0)), Vector3(0.1, 1.0, 0.1), 0.008)
		k.cyl("fence_wood", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(x, 1.04, 0.0)), 0.072, 0.08, 4, 0.0)
		k.box("timber", Transform3D(Basis(), Vector3(x, 0.03, 0.0)), Vector3(0.09, 0.06, 0.6), 0.008)
		for y: float in [0.3, 0.62, 0.94]:
			for t: float in [-0.025, 0.025]:
				k.cyl("bolt", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x + t, y, 0.091)), 0.008, 0.006, 6)
	for y: float in [0.3, 0.62, 0.94]:
		k.box("fence_wood", Transform3D(Basis(Vector3.BACK, 0.004 * y), Vector3(0.0, y, 0.0625)), Vector3(size.x, 0.09, 0.025), 0.005)


static func _mesh_fence(k: Mesher, size: Vector3) -> void:
	var hx := size.x * 0.5 - 0.03
	for x: float in [-hx, hx]:
		k.cyl("galv", Transform3D(Basis(), Vector3(x, 1.06, 0.0)), 0.02, 1.9, 8)
	for y: float in [0.12, 2.0]:
		k.cyl("galv", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, y, 0.0)), 0.02, hx * 2.0, 8)
	k.cyl("galv", Transform3D(Basis(), Vector3(0.0, 1.06, 0.0)), 0.012, 1.88, 6)
	k.box("mesh_fence", Transform3D(Basis(), Vector3(0.0, 1.06, 0.0)), Vector3(hx * 2.0, 1.88, 0.004))
	for x: float in [-size.x * 0.5 + 0.05, size.x * 0.5 - 0.05]:
		k.box("concrete", Transform3D(Basis(), Vector3(x, 0.07, 0.0)), Vector3(0.22, 0.14, 0.62), 0.03)
		k.box("galv", Transform3D(Basis(), Vector3(x, 1.9, 0.0)), Vector3(0.1, 0.06, 0.06), 0.01)


static func _cone(k: Mesher) -> void:
	k.box("black", Transform3D(Basis(), Vector3(0.0, 0.017, 0.0)), Vector3(0.36, 0.035, 0.36), 0.012)
	var r := func(y: float) -> float: return lerpf(0.155, 0.028, (y - 0.035) / 0.45)
	k.cyl("cone", Transform3D(Basis(), Vector3(0.0, 0.035 + 0.225, 0.0)), 0.155, 0.45, 18, 0.028)
	for band in [[0.19, 0.25], [0.31, 0.36]]:
		var a: float = band[0]
		var b: float = band[1]
		k.cyl("reflect_white", Transform3D(Basis(), Vector3(0.0, (a + b) * 0.5, 0.0)), r.call(a) + 0.002, b - a, 18, r.call(b) + 0.002, "", false)


static func _post(k: Mesher) -> void:
	k.cyl("rubber", Transform3D(Basis(), Vector3(0.0, 0.015, 0.0)), 0.12, 0.03, 14)
	for i in 3:
		var a := TAU * i / 3.0
		k.cyl("bolt", Transform3D(Basis(), Vector3(cos(a) * 0.09, 0.034, sin(a) * 0.09)), 0.012, 0.012, 6)
	k.cyl("black", Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), 0.06, 0.94, 14)
	k.cyl("black", Transform3D(Basis(), Vector3(0.0, 0.985, 0.0)), 0.06, 0.03, 14, 0.035)
	for y: float in [0.68, 0.86]:
		k.cyl("yellow", Transform3D(Basis(), Vector3(0.0, y, 0.0)), 0.063, 0.08, 14, -1.0, "", false)


static func _flag(k: Mesher, model: String, size: Vector3) -> void:
	k.box("black", Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)), Vector3(0.5, 0.04, 0.06), 0.008)
	k.box("black", Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)), Vector3(0.06, 0.04, 0.5), 0.008)
	k.cyl("black", Transform3D(Basis(), Vector3(0.0, 0.1, 0.0)), 0.03, 0.12, 10)
	k.cyl("galv", Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)), 0.016, size.y - 0.04, 8)
	k.cyl("galv", Transform3D(Basis(), Vector3(0.0, size.y - 0.01, 0.0)), 0.024, 0.03, 8)
	var cloth := "cloth_check" if model == "flag_chequered" else "cloth@%s" % (Equipment.get_model(model)["color"] as Color).to_html(false)
	k.cyl(cloth, Transform3D(Basis(), Vector3(0.0, size.y - 0.3, 0.0)), 0.022, 0.48, 8)
	k.wave(cloth, Vector3(0.02, size.y - 0.54, 0.0), 0.52, 0.48, 0.035)


# ---------------------------------------------------------------------------- the mesh builder

## Gathers triangles a material at a time and makes them one mesh with a surface for each.
class Mesher:
	var _st := {}

	## A key "name@rrggbb" is drawn in material "name" tinted that colour (by vertex colour), so
	## every colour of paint shares one material.
	func _tool(key: String) -> SurfaceTool:
		var surf := key.get_slice("@", 0)
		if not _st.has(surf):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[surf] = st
		return _st[surf]

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _st:
			(_st[key] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, YardLooks.mat(key))
		return mesh

	## A triangle facing `n` (its winding is put right for that), flat shaded unless `ns` gives
	## a normal for each corner.
	func tri(key: String, v: Array, n: Vector3, ns: Array = [], uv: Array = []) -> void:
		var st := _tool(key)
		var tint := Color.html(key.get_slice("@", 1)) if key.contains("@") else Color.WHITE
		n = n.normalized()
		var order := [0, 1, 2]
		# Godot's front faces wind clockwise.
		if ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3)).dot(n) > 0.0:
			order = [0, 2, 1]
		for i in order:
			st.set_color(tint)
			st.set_normal(ns[i] if not ns.is_empty() else n)
			st.set_uv(uv[i] if not uv.is_empty() else Vector2.ZERO)
			st.add_vertex(v[i])

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		tri(key, [a, b, c], n)
		tri(key, [a, c, d], n)

	## A quad with a normal and a picture point at each corner (a deck strip).
	func quad_n(key: String, v: Array, ns: Array, uv: Array) -> void:
		var n: Vector3 = (ns[0] as Vector3) + (ns[1] as Vector3) + (ns[2] as Vector3) + (ns[3] as Vector3)
		tri(key, [v[0], v[1], v[2]], n, [ns[0], ns[1], ns[2]], [uv[0], uv[1], uv[2]])
		tri(key, [v[0], v[2], v[3]], n, [ns[0], ns[2], ns[3]], [uv[0], uv[2], uv[3]])

	## A box of `size` at `xf`, its edges chamfered by `bevel`.
	func box(key: String, xf: Transform3D, size: Vector3, bevel := 0.0) -> void:
		var h := size * 0.5
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
		var inner := h - Vector3(b, b, b)
		var put := func(pts: Array, n: Vector3) -> void:
			var w: Array = pts.map(func(p): return xf * (p as Vector3))
			var nn := (xf.basis * n).normalized()
			tri(key, [w[0], w[1], w[2]], nn)
			if w.size() == 4:
				tri(key, [w[0], w[2], w[3]], nn)
		for axis in 3:
			var j := (axis + 1) % 3
			var l := (axis + 2) % 3
			for s: float in [-1.0, 1.0]:
				var corners := []
				for c in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
					var p := Vector3()
					p[axis] = s * h[axis]
					p[j] = c[0] * inner[j]
					p[l] = c[1] * inner[l]
					corners.append(p)
				var n := Vector3()
				n[axis] = s
				put.call(corners, n)
		if b <= 0.0:
			return
		for axis in 3:
			# The edges running along `axis`.
			var j := (axis + 1) % 3
			var l := (axis + 2) % 3
			for sj: float in [-1.0, 1.0]:
				for sl: float in [-1.0, 1.0]:
					var pts := []
					for e in [[-1.0, true], [1.0, true], [1.0, false], [-1.0, false]]:
						var p := Vector3()
						p[axis] = float(e[0]) * inner[axis]
						p[j] = sj * (h[j] if e[1] else inner[j])
						p[l] = sl * (inner[l] if e[1] else h[l])
						pts.append(p)
					var n := Vector3()
					n[j] = sj
					n[l] = sl
					put.call(pts, n.normalized())
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					put.call([Vector3(sx * h.x, sy * inner.y, sz * inner.z), Vector3(sx * inner.x, sy * h.y, sz * inner.z),
						Vector3(sx * inner.x, sy * inner.y, sz * h.z)], Vector3(sx, sy, sz).normalized())

	## A square bar from `a` to `b`, `thick` across.
	func beam(key: String, a: Vector3, b: Vector3, thick: Vector2) -> void:
		var z := (b - a).normalized()
		var x := Vector3.UP.cross(z)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := z.cross(x)
		box(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick.x, thick.y, a.distance_to(b)))

	## A cylinder along `xf`'s y, `r` at the bottom and `r2` at the top (a cone or frustum when
	## they differ), `segs` round. Its ends in `cap_key` if given (mapped to a disc picture).
	func cyl(key: String, xf: Transform3D, r: float, h: float, segs := 12, r2 := -1.0, cap_key := "", caps := true) -> void:
		var top := r if r2 < 0.0 else r2
		var hy := h * 0.5
		var slope := (r - top) / maxf(h, 1e-6)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var n0 := (xf.basis * (d0 + Vector3.UP * slope).normalized()).normalized()
			var n1 := (xf.basis * (d1 + Vector3.UP * slope).normalized()).normalized()
			var b0 := xf * (d0 * r + Vector3.DOWN * hy)
			var b1 := xf * (d1 * r + Vector3.DOWN * hy)
			var t0 := xf * (d0 * top + Vector3.UP * hy)
			var t1 := xf * (d1 * top + Vector3.UP * hy)
			tri(key, [b0, b1, t1], n0 + n1, [n0, n1, n1])
			if top > 0.0:
				tri(key, [b0, t1, t0], n0 + n1, [n0, n1, n0])
			if caps:
				var ck := cap_key if cap_key != "" else key
				var up := (xf.basis * Vector3.UP).normalized()
				var uv0 := Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5)
				var uv1 := Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)
				if top > 0.0:
					tri(ck, [xf * (Vector3.UP * hy), t0, t1], up, [], [Vector2(0.5, 0.5), uv0, uv1])
				tri(ck, [xf * (Vector3.DOWN * hy), b0, b1], -up, [], [Vector2(0.5, 0.5), uv0, uv1])

	## A ring round `xf`'s y: `big` from the middle to the tube's centre, the tube `small` thick.
	func torus(key: String, xf: Transform3D, big: float, small: float, segs := 16, rings := 8) -> void:
		var pt := func(i: int, j: int) -> Array:
			var a := TAU * i / segs
			var b := TAU * j / rings
			var d := Vector3(cos(a), 0.0, sin(a))
			var n := d * cos(b) + Vector3.UP * sin(b)
			return [xf * (d * big + n * small), (xf.basis * n).normalized()]
		for i in segs:
			for j in rings:
				var p00: Array = pt.call(i, j)
				var p10: Array = pt.call(i + 1, j)
				var p11: Array = pt.call(i + 1, j + 1)
				var p01: Array = pt.call(i, j + 1)
				var n: Vector3 = p00[1] + p10[1] + p11[1] + p01[1]
				tri(key, [p00[0], p10[0], p11[0]], n, [p00[1], p10[1], p11[1]])
				tri(key, [p00[0], p11[0], p01[0]], n, [p00[1], p11[1], p01[1]])

	## A side shape `poly` ((z, y) points round it) pushed out across x from `x0` to `x1`.
	func extrude(key: String, xf: Transform3D, poly: PackedVector2Array, x0: float, x1: float) -> void:
		var area := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			area += p.x * q.y - q.x * p.y
		var at := func(p: Vector2, x: float) -> Vector3: return xf * Vector3(x, p.y, p.x)
		var tris := Geometry2D.triangulate_polygon(poly)
		var side := (xf.basis * Vector3.RIGHT).normalized() * signf(x1 - x0)
		for t in range(0, tris.size(), 3):
			tri(key, [at.call(poly[tris[t]], x1), at.call(poly[tris[t + 1]], x1), at.call(poly[tris[t + 2]], x1)], side)
			tri(key, [at.call(poly[tris[t]], x0), at.call(poly[tris[t + 1]], x0), at.call(poly[tris[t + 2]], x0)], -side)
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			var d := q - p
			var out2 := Vector2(d.y, -d.x) * signf(area)
			var n := (xf.basis * Vector3(0.0, out2.y, out2.x)).normalized()
			quad(key, at.call(p, x0), at.call(q, x0), at.call(q, x1), at.call(p, x1), n)

	## A cloth hanging from a pole at `from` (its top-left), `w` out and `h` down, rippling.
	func wave(key: String, from: Vector3, w: float, h: float, ripple: float) -> void:
		var nx := 8
		var ny := 3
		var p := func(i: int, j: int) -> Vector3:
			var u := float(i) / nx
			return from + Vector3(u * w, h - float(j) / ny * h, sin(u * 7.0) * ripple * u)
		for i in nx:
			for j in ny:
				var a: Vector3 = p.call(i, j)
				var b: Vector3 = p.call(i + 1, j)
				var c: Vector3 = p.call(i + 1, j + 1)
				var d: Vector3 = p.call(i, j + 1)
				var n := (b - a).cross(d - a).normalized()
				n = n if n.z >= 0.0 else -n
				var uv := [Vector2(float(i) / nx, float(j) / ny), Vector2(float(i + 1) / nx, float(j) / ny),
					Vector2(float(i + 1) / nx, float(j + 1) / ny), Vector2(float(i) / nx, float(j + 1) / ny)]
				tri(key, [a, b, c], n, [n, n, n], [uv[0], uv[1], uv[2]])
				tri(key, [a, c, d], n, [n, n, n], [uv[0], uv[2], uv[3]])
