class_name CarModel
extends RefCounted
## The recovery truck's looks (see Car): a modern double-cab pickup in the garage's green, with
## no maker's badges. The lower body is built from side-view outlines pushed out across the
## truck with bevelled edges (prism), so the wheel arches are real cut-outs with black arch trims
## and liners behind them; the cab's glasshouse is a ShapeKit loft (a rounded section swept fore
## and aft, raked at the windscreen) in tinted glass, with the roof, pillars and window frames
## laid over it. Then the grille, headlights, bumpers, mirrors, handles, shut lines, the load bed
## with its tailgate, the sports bar, tow bar and plates, and an interior to see from the cab:
## seats, dash, instruments, console and the steering wheel. Everything that doesn't move is
## merged into one mesh (a surface per material), so the whole truck is a handful of draw calls.
##
## Car axes: forward -Z, up +Y, right +X, origin on the ground under the middle.

const W := 0.93                 # half the body's width
const SKIN := 0.06              # the side panels' thickness
const BELT := 1.2               # the waist line: the bottom of the side windows, the bed rails
const ARCH_R := 0.5             # wheel arch radius, round the wheel's middle sat on its springs
const WHEEL_Y := 0.4
## The glasshouse: [z, half width, height above the belt], windscreen base to back window.
const GLASS := [[-1.13, 0.86, 0.015], [-1.0, 0.865, 0.12], [-0.85, 0.87, 0.25], [-0.7, 0.875, 0.37],
	[-0.55, 0.88, 0.47], [-0.45, 0.88, 0.53], [-0.36, 0.88, 0.565], [-0.25, 0.88, 0.58], [0.45, 0.88, 0.58],
	[0.62, 0.875, 0.57], [0.72, 0.87, 0.55], [0.75, 0.865, 0.53]]
const GLASS_N := 5.0            # its squareness (see ShapeKit)
const ROOF_FROM := -0.36        # where the windscreen meets the roof
const ROOF_EDGE := 0.86         # the roof's edge, as a share of the glasshouse's height
const A_FOOT := 0.3             # ...and the A pillar's foot, at the windscreen's base
## The bonnet's top line, front to the windscreen [z, y].
const BONNET := [[-2.62, 1.0], [-2.3, 1.06], [-1.8, 1.11], [-1.16, 1.15]]

var car: Car
var items := []                 # [mesh, transform, material] to merge into the body
var m := {}                     # the materials by name


func _init(c: Car) -> void:
	car = c


## Builds the truck under car.model and hands Car the parts it moves or lights.
func build() -> void:
	_materials()
	_lower_body()
	_glasshouse()
	_front_end()
	_rear_end()
	_bed()
	_details()
	_interior()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = merged(items)
	car.model.add_child(body)
	_wheels()
	_steering_wheel()
	_lights()
	_signs()


# ---------------------------------------------------------------------------- materials

static func mat(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = c
	s.metallic = metal
	s.roughness = rough
	return s


func _materials() -> void:
	var paint := mat(car._paint, 0.55, 0.32)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	paint.clearcoat_roughness = 0.15
	m["paint"] = paint
	m["black"] = mat(Color(0.045, 0.045, 0.05), 0.0, 0.78)          # textured plastic trim
	m["gloss"] = mat(Color(0.02, 0.02, 0.025), 0.2, 0.18)           # piano black: pillars, grille
	m["chrome"] = mat(Color(0.62, 0.64, 0.67), 1.0, 0.18)
	m["satin"] = mat(Color(0.32, 0.33, 0.35), 0.85, 0.35)           # dark grey metal
	var glass := mat(Color(0.04, 0.05, 0.06), 0.6, 0.03)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.5      # tinted, but you can see out of it from the cab
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["glass"] = glass
	var lamp := mat(Color(0.95, 0.95, 0.92), 0.2, 0.1)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.96, 0.85)
	lamp.emission_energy_multiplier = 0.0
	m["lamp"] = lamp
	car._lamp_mat = lamp
	m["bezel"] = mat(Color(0.12, 0.12, 0.13), 0.9, 0.25)
	var brake := mat(Color(0.45, 0.02, 0.02), 0.1, 0.2)
	brake.emission_enabled = true
	brake.emission = Color(1.0, 0.05, 0.02)
	brake.emission_energy_multiplier = 0.0
	m["brake"] = brake
	car._brake_mat = brake
	var reverse := mat(Color(0.85, 0.85, 0.85), 0.1, 0.15)
	reverse.emission_enabled = true
	reverse.emission = Color(1.0, 1.0, 0.95)
	reverse.emission_energy_multiplier = 0.0
	m["reverse"] = reverse
	car._reverse_mat = reverse
	m["amber"] = mat(Color(0.95, 0.5, 0.05), 0.1, 0.2)
	m["mirror"] = mat(Color(0.6, 0.65, 0.7), 1.0, 0.04)
	m["tyre"] = mat(Color(0.035, 0.035, 0.035), 0.0, 0.92)
	m["rim"] = mat(Color(0.68, 0.7, 0.72), 0.85, 0.28)
	m["rim_dark"] = mat(Color(0.18, 0.18, 0.19), 0.7, 0.4)
	m["disc"] = mat(Color(0.4, 0.4, 0.41), 0.9, 0.45)
	m["caliper"] = mat(Color(0.12, 0.12, 0.13), 0.4, 0.5)
	m["under"] = mat(Color(0.03, 0.03, 0.03), 0.0, 0.9)
	m["trim_in"] = mat(Color(0.08, 0.08, 0.085), 0.0, 0.85)       # dash and door cards
	m["seat"] = mat(Color(0.12, 0.12, 0.13), 0.0, 1.0)
	m["headliner"] = mat(Color(0.55, 0.54, 0.52), 0.0, 0.95)
	m["carpet"] = mat(Color(0.05, 0.05, 0.05), 0.0, 1.0)
	var dials := mat(Color(0.05, 0.06, 0.08), 0.0, 0.3)
	dials.emission_enabled = true
	dials.emission = Color(0.4, 0.75, 1.0)
	dials.emission_energy_multiplier = 0.0
	m["dials"] = dials
	car._dash_mat = dials
	m["plate"] = mat(Color(0.95, 0.95, 0.93), 0.0, 0.4)
	m["plate_rear"] = mat(Color(0.98, 0.8, 0.1), 0.0, 0.4)
	m["liner"] = mat(Color(0.03, 0.03, 0.035), 0.0, 0.97)


# ---------------------------------------------------------------------------- mesh helpers

func _add(mesh: Mesh, name: String, xf := Transform3D()) -> void:
	items.append([mesh, xf, m[name]])


func _box(size: Vector3, at: Vector3, name: String, rot := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(b, name, Transform3D(Basis.from_euler(rot), at))


## A box both sides of the truck: `at` is the right-hand one.
func _boxes(size: Vector3, at: Vector3, name: String, rot := Vector3.ZERO) -> void:
	_box(size, at, name, rot)
	_box(size, Vector3(-at.x, at.y, at.z), name, Vector3(rot.x, -rot.y, -rot.z))


func _cyl(r: float, h: float, xf: Transform3D, name: String, sides := 16) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	_add(c, name, xf)


## A prism both sides: from x0 to x1 on the right and mirrored on the left.
func _prisms(profile: PackedVector2Array, x0: float, x1: float, bevel: float, name: String) -> void:
	_add(prism(profile, x0, x1, bevel), name)
	_add(prism(profile, -x1, -x0, bevel), name)


## Merges [mesh, transform, material] items into one mesh, one surface per material.
static func merged(list: Array) -> ArrayMesh:
	var tools := {}
	var order := []
	for it in list:
		var material: Material = it[2]
		if not tools.has(material):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[material] = st
			order.append(material)
		var mesh: Mesh = it[0]
		for s in mesh.get_surface_count():
			(tools[material] as SurfaceTool).append_from(mesh, s, it[1])
	var out := ArrayMesh.new()
	for material in order:
		out = (tools[material] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## Merges the plain mesh children of `parent` (no children of their own, each with its
## material override) into one mesh instance: fewer draw calls for something built of boxes.
static func merge_children(parent: Node3D) -> void:
	var list := []
	for c in parent.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.get_child_count() > 0 or mi.mesh == null or mi.material_override == null or not mi.visible:
			continue
		list.append([mi.mesh, mi.transform, mi.material_override])
		parent.remove_child(mi)
		mi.queue_free()
	if list.is_empty():
		return
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = merged(list)
	parent.add_child(out)


## A solid from a side-view outline (Vector2(z, y) points, closed, either way round) pushed
## out across the truck from x0 to x1, its edges bevelled `bevel` deep and shaded round.
## Corners sharper than about 35 degrees stay crisp; gentler ones (an arch's curve) are smooth.
static func prism(profile: PackedVector2Array, x0: float, x1: float, bevel: float) -> ArrayMesh:
	var p := profile.duplicate()
	var area := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		p.reverse()
	var count := p.size()
	var pts := []       # one entry per outline point, two at a crisp corner: [p, inset, normal]
	var inset := PackedVector2Array()
	for i in count:
		var prev := p[(i - 1 + count) % count]
		var cur := p[i]
		var next := p[(i + 1) % count]
		var d1 := (cur - prev).normalized()
		var d2 := (next - cur).normalized()
		var n1 := Vector2(d1.y, -d1.x)
		var n2 := Vector2(d2.y, -d2.x)
		var bis := (n1 + n2).normalized() if (n1 + n2).length() > 0.001 else n1
		var q := cur - bis * (bevel / maxf(bis.dot(n1), 0.35))
		inset.append(q)
		if n1.angle_to(n2) > 0.6 or n1.angle_to(n2) < -0.6:
			pts.append([cur, q, n1])
			pts.append([cur, q, n2])
		else:
			pts.append([cur, q, bis])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var e := pts.size()
	# Four rings round the outline: the bevel's outer edge, the full outline either side, and
	# the other bevel. Shaded round from the side faces into the bevel.
	var layers := [[x0, 1, -1.0], [x0 + bevel, 0, -0.15], [x1 - bevel, 0, 0.15], [x1, 1, 1.0]]
	for layer in layers:
		for k in e:
			var pt: Vector2 = pts[k][layer[1]]
			var n: Vector2 = pts[k][2]
			var side: float = layer[2]
			verts.append(Vector3(layer[0], pt.y, pt.x))
			normals.append((Vector3(0.0, n.y, n.x) * (0.6 if absf(side) > 0.5 else 1.0) + Vector3.RIGHT * side).normalized())
	for l in 3:
		for k in e:
			var a := l * e + k
			var b := l * e + (k + 1) % e
			var c := (l + 1) * e + k
			var d := (l + 1) * e + (k + 1) % e
			if (verts[a] - verts[b]).length() < 1e-6:
				continue   # the zero-width strip at a crisp corner
			ShapeKit._tri(idx, verts, normals, a, c, b)
			ShapeKit._tri(idx, verts, normals, b, c, d)
	# Flat caps on the outsides.
	var tris := Geometry2D.triangulate_polygon(inset)
	for side in [-1.0, 1.0]:
		var base := verts.size()
		var x := x0 if side < 0.0 else x1
		for q in inset:
			verts.append(Vector3(x, q.y, q.x))
			normals.append(Vector3.RIGHT * side)
		for t in range(0, tris.size(), 3):
			ShapeKit._tri_facing(idx, verts, base + tris[t], base + tris[t + 1], base + tris[t + 2], Vector3.RIGHT * side)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	return ShapeKit._commit(verts, normals, uvs, idx)


## A solid of revolution round the X axis: `profile` is Vector2(radius, x) points in order, the
## outside on the left going along it. `mod` (angle step, point index) -> radius change, for a
## tread pattern.
static func lathe(profile: Array, sides: int, mod := Callable()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rows := profile.size()
	for i in rows:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, rows - 1)]
		var t := (b - a).normalized()
		var n2 := Vector2(t.y, -t.x)   # (radial, along x)
		for j in sides + 1:
			var ang := TAU * j / sides
			var r: float = (profile[i] as Vector2).x
			if mod.is_valid():
				r += float(mod.call(j % sides, i))
			var radial := Vector3(0.0, cos(ang), sin(ang))
			verts.append(Vector3((profile[i] as Vector2).y, 0.0, 0.0) + radial * r)
			normals.append((radial * n2.x + Vector3.RIGHT * n2.y).normalized())
			uvs.append(Vector2(float(j) / sides, float(i) / maxf(rows - 1, 1)))
	var ring := sides + 1
	for i in rows - 1:
		for j in sides:
			var a := i * ring + j
			ShapeKit._tri(idx, verts, normals, a, a + ring, a + 1)
			ShapeKit._tri(idx, verts, normals, a + 1, a + ring, a + ring + 1)
	return ShapeKit._commit(verts, normals, uvs, idx)


## A thin double-sided surface through a grid of points (rows of the same length).
static func sheet(rows: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var nr := rows.size()
	var nc: int = (rows[0] as PackedVector3Array).size()
	for i in nr:
		var row: PackedVector3Array = rows[i]
		for j in nc:
			var across: Vector3 = row[mini(j + 1, nc - 1)] - row[maxi(j - 1, 0)]
			var along: Vector3 = (rows[mini(i + 1, nr - 1)] as PackedVector3Array)[j] - (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			verts.append(row[j])
			normals.append(along.cross(across).normalized())
	for i in nr - 1:
		for j in nc - 1:
			var a := i * nc + j
			idx.append_array([a, a + nc, a + 1, a + 1, a + nc, a + nc + 1])
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	ShapeKit._inside_face(verts, normals, uvs, idx)
	return ShapeKit._commit(verts, normals, uvs, idx)


## Points round an arc in the side view (z, y) about `c`, from angle a0 to a1 (0 is forward of
## the wheel... +z, PI/2 straight up).
static func arc(c: Vector2, r: float, a0: float, a1: float, steps := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# ---------------------------------------------------------------------------- the body

## The angle round a wheel arch where it meets a sill `y` high.
static func _arch_foot(y: float, r := ARCH_R) -> float:
	return asin(clampf((y - WHEEL_Y) / r, -1.0, 1.0))


## The side panels (wings, doors, the bed sides) with both wheel arches cut out, the engine bay
## between them under the bonnet, arch liners and trims, and the bonnet's crowned panel.
func _lower_body() -> void:
	var fz := Car.FRONT_Z
	var rz := Car.REAR_Z
	var side := PackedVector2Array()
	for b in BONNET:
		side.append(Vector2(b[0], b[1]))
	side.append_array([Vector2(-1.12, 1.17), Vector2(-1.1, BELT), Vector2(2.74, BELT), Vector2(2.78, 1.17), Vector2(2.78, 0.6)])
	var ra := _arch_foot(0.6)
	side.append_array(arc(Vector2(rz, WHEEL_Y), ARCH_R, ra, PI - _arch_foot(0.54)))
	side.append(Vector2(1.08, 0.52))
	side.append(Vector2(-1.0, 0.52))
	var fa := _arch_foot(0.54)
	side.append_array(arc(Vector2(fz, WHEEL_Y), ARCH_R, fa, PI - fa))
	side.append_array([Vector2(-2.1, 0.62), Vector2(-2.62, 0.62)])
	_prisms(side, W - SKIN, W, 0.025, "paint")
	# The engine bay between the wings, to the windscreen.
	var bay := PackedVector2Array()
	for b in BONNET:
		bay.append(Vector2(b[0], b[1]))
	var back_y := WHEEL_Y + sqrt(ARCH_R * ARCH_R - pow(-1.12 - fz, 2.0))
	bay.append_array([Vector2(-1.12, 1.15), Vector2(-1.12, back_y)])
	bay.append_array(arc(Vector2(fz, WHEEL_Y), ARCH_R, acos((-1.12 - fz) / ARCH_R), PI - fa))
	bay.append_array([Vector2(-2.1, 0.62), Vector2(-2.62, 0.62)])
	_add(prism(bay, -(W - SKIN) - 0.002, W - SKIN + 0.002, 0.07), "paint")
	# Arch liners and the wheel tubs' inner walls, so you don't see through the arches.
	for z in [fz, rz]:
		var foot := _arch_foot(0.54 if z == fz else 0.6, ARCH_R + 0.02)
		var liner := arc(Vector2(z, WHEEL_Y), ARCH_R + 0.02, foot, PI - foot, 16)
		var inner := arc(Vector2(z, WHEEL_Y), ARCH_R - 0.005, PI - foot, foot, 16)
		var ring := liner.duplicate()
		ring.append_array(inner)
		_prisms(ring, 0.58, W - 0.01, 0.003, "liner")
		_prisms(liner, 0.56, 0.58, 0.003, "liner")
		# The arch trim: a black flare round the cut-out, standing proud of the panel.
		var flare := arc(Vector2(z, WHEEL_Y), ARCH_R + 0.075, foot - 0.1, PI - foot + 0.1, 18)
		flare.append_array(arc(Vector2(z, WHEEL_Y), ARCH_R - 0.005, PI - foot + 0.1, foot - 0.1, 18))
		_prisms(flare, W - 0.02, W + 0.035, 0.012, "black")
	# The bonnet: a crowned panel on top of the bay, its edges sunk in for the shut lines.
	var crown := []
	for i in 7:
		var z := lerpf(-2.6, -1.17, i / 6.0)
		crown.append({"c": Vector3(0.0, _bonnet_y(z) - 0.03, z), "w": 0.83, "up": 0.045, "down": 0.0, "n": 3.0})
	_add(ShapeKit.loft(crown, 32, true, 0.12, PI - 0.12), "paint")


## The bonnet's height at `z`.
static func _bonnet_y(z: float) -> float:
	for i in range(1, BONNET.size()):
		if z <= float(BONNET[i][0]):
			var f := inverse_lerp(float(BONNET[i - 1][0]), float(BONNET[i][0]), z)
			return lerpf(float(BONNET[i - 1][1]), float(BONNET[i][1]), clampf(f, 0.0, 1.0))
	return float(BONNET[-1][1])


## The glasshouse's [half width, height] at `z`, as the loft runs between its sections.
static func _glass_at(z: float) -> Vector2:
	if z <= float(GLASS[0][0]):
		return Vector2(GLASS[0][1], GLASS[0][2])
	for i in range(1, GLASS.size()):
		if z <= float(GLASS[i][0]):
			var f := inverse_lerp(float(GLASS[i - 1][0]), float(GLASS[i][0]), z)
			return Vector2(lerpf(float(GLASS[i - 1][1]), float(GLASS[i][1]), f), lerpf(float(GLASS[i - 1][2]), float(GLASS[i][2]), f))
	return Vector2(GLASS[-1][1], GLASS[-1][2])


## A point on the glasshouse at `z`, `a` round it (0 at the right-hand belt line, PI/2 on top,
## PI on the left), stood `out` metres proud of it.
static func glass_point(z: float, a: float, out := 0.0) -> Vector3:
	var g := _glass_at(z)
	var e := 2.0 / GLASS_N
	var ca := cos(a)
	var sa := maxf(sin(a), 0.0)
	return Vector3(signf(ca) * pow(absf(ca), e) * (g.x + out), BELT + pow(sa, e) * (g.y + out), z)


## The angle round the glasshouse of the roof's edge, or the A pillar's line at the windscreen.
static func edge_angle(z: float) -> float:
	var f := ROOF_EDGE if z >= ROOF_FROM else lerpf(A_FOOT, ROOF_EDGE, inverse_lerp(float(GLASS[0][0]), ROOF_FROM, z))
	return asin(clampf(pow(f, GLASS_N / 2.0), 0.0, 1.0))


## A band on the glasshouse from z0 to z1 between angles a0(z) and a1(z) (Callables), `out` proud.
func _band(z0: float, z1: float, a0: Callable, a1: Callable, out: float, name: String, steps := 10, across := 4) -> void:
	var rows := []
	for i in steps + 1:
		var z := lerpf(z0, z1, float(i) / steps)
		var row := PackedVector3Array()
		for j in across + 1:
			row.append(glass_point(z, lerpf(float(a0.call(z)), float(a1.call(z)), float(j) / across), out))
		rows.append(row)
	_add(sheet(rows), name)


## The cab's glass, the roof over it, the pillars (A in the paint, B in gloss black, C in the
## paint) and the black window surrounds, the windscreen's black edge, the cowl and wipers.
func _glasshouse() -> void:
	var sections := []
	for g in GLASS:
		sections.append({"c": Vector3(0.0, BELT, g[0]), "w": g[1], "up": g[2], "down": 0.0, "n": GLASS_N})
	_add(ShapeKit.loft(sections, 48), "glass")
	# The roof, a skin over the top of the glass from the windscreen's top back.
	var roof := []
	var headliner := []
	for g in GLASS:
		if float(g[0]) >= ROOF_FROM - 0.001:
			roof.append({"c": Vector3(0.0, BELT, g[0]), "w": float(g[1]) + 0.006, "up": float(g[2]) + 0.006, "down": 0.0, "n": GLASS_N})
			headliner.append({"c": Vector3(0.0, BELT, g[0]), "w": float(g[1]) - 0.03, "up": float(g[2]) - 0.035, "down": 0.0, "n": GLASS_N})
	var ea := edge_angle(0.0)
	_add(ShapeKit.loft(roof, 48, true, ea - 0.02, PI - ea + 0.02), "paint")
	_add(ShapeKit.loft(headliner, 48, true, ea - 0.06, PI - ea + 0.06), "headliner")
	var z0 := float(GLASS[0][0])
	var zb := float(GLASS[-1][0])
	for s in [1.0, -1.0]:
		var a := func(z: float, da: float) -> float:
			var v: float = edge_angle(z) + da
			return v if s > 0.0 else PI - v
		var belt := func(_z: float) -> float: return 0.0 if s > 0.0 else PI
		# A pillar, painted, along the windscreen's edge.
		_band(z0 + 0.01, ROOF_FROM + 0.02, a.bind(-0.07), a.bind(0.09), 0.007, "paint", 12, 3)
		# The black surround along the top of the side windows, under the roof's edge.
		_band(ROOF_FROM, 0.58, a.bind(-0.09), a.bind(0.0), 0.005, "gloss", 8, 2)
		# B pillar, gloss black, between the doors.
		_band(-0.1, 0.02, belt, a.bind(-0.02), 0.005, "gloss", 2, 6)
		# C pillar, painted, behind the back door's window to the back of the cab.
		_band(0.56, zb, belt, a.bind(0.02), 0.006, "paint", 4, 8)
	# The windscreen's black edge at its base, and the cowl and wipers below it.
	_band(z0 + 0.005, z0 + 0.09, func(z): return edge_angle(z), func(z): return PI - edge_angle(z), 0.003, "gloss", 2, 16)
	_box(Vector3(1.72, 0.03, 0.1), Vector3(0.0, BELT - 0.005, z0 - 0.02), "black")
	for x in [-0.32, 0.36]:
		_box(Vector3(0.62, 0.012, 0.018), Vector3(x, BELT + 0.04, z0 + 0.08), "black", Vector3(deg_to_rad(-36.0), 0.0, deg_to_rad(4.0)))
	# The belt line moulding along the top of the doors.
	_boxes(Vector3(0.065, 0.02, 1.86), Vector3(W - 0.03, BELT + 0.006, -0.19), "black")
	# The back window's black frame on the back of the cab.
	var frame := []
	for k in [0.0, 1.0]:
		var row := PackedVector3Array()
		for j in 25:
			var aa := PI * j / 24.0
			var p := glass_point(zb, aa, -0.06 * k)
			p.z += 0.002
			row.append(p)
		frame.append(row)
	_add(sheet(frame), "gloss")


## The grille, headlights and indicators, the front bumper with its valance, skid plate and
## fog lamps, and the front number plate.
func _front_end() -> void:
	# Bumper: body colour wrapping round the corners, black valance and a silver skid plate.
	var bumper := PackedVector2Array([Vector2(-2.76, 0.46), Vector2(-2.775, 0.66), Vector2(-2.71, 0.76),
		Vector2(-2.58, 0.8), Vector2(-2.42, 0.8), Vector2(-2.42, 0.46)])
	_add(prism(bumper, -0.8, 0.8, 0.06), "paint")
	# Its corners: the same section turned to run from the bumper's face back round to the wing
	# (front corner a to b, plan view (x, z)).
	for s in [-1.0, 1.0]:
		var a := Vector2(s * 0.78, -2.765)
		var b := Vector2(s * 0.935, -2.53)
		var d := (b - a) if s > 0.0 else (a - b)
		var phi := atan2(-d.y, d.x)
		var mid := (a + b) * 0.5 + Vector2(sin(phi), cos(phi)) * 0.175
		var xf := Transform3D(Basis(Vector3.UP, phi), Vector3(mid.x, 0.0, mid.y)) * Transform3D(Basis(), Vector3(0.0, 0.0, 2.6))
		_add(prism(bumper, -d.length() * 0.5, d.length() * 0.5, 0.05), "paint", xf)
	_add(prism(PackedVector2Array([Vector2(-2.72, 0.38), Vector2(-2.74, 0.48), Vector2(-2.45, 0.48), Vector2(-2.45, 0.38)]),
		-0.86, 0.86, 0.03), "black")
	_box(Vector3(0.9, 0.025, 0.3), Vector3(0.0, 0.385, -2.6), "satin", Vector3(deg_to_rad(-12.0), 0.0, 0.0))
	for s in [-1.0, 1.0]:
		_box(Vector3(0.22, 0.09, 0.03), Vector3(s * 0.66, 0.56, -2.775), "black")
		_cyl(0.035, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.66, 0.56, -2.79)), "lamp")
	_box(Vector3(0.52, 0.115, 0.012), Vector3(0.0, 0.6, -2.785), "plate")
	# The grille: gloss black with dark chrome bars and surround.
	var grille := PackedVector2Array([Vector2(-2.665, 0.77), Vector2(-2.655, 1.0), Vector2(-2.6, 1.0), Vector2(-2.6, 0.77)])
	_add(prism(grille, -0.52, 0.52, 0.018), "gloss")
	for i in 3:
		_box(Vector3(1.0, 0.022, 0.03), Vector3(0.0, 0.83 + i * 0.06, -2.668 + i * 0.003), "satin")
	_box(Vector3(1.08, 0.035, 0.05), Vector3(0.0, 1.0, -2.655), "satin")
	for s in [-1.0, 1.0]:
		_box(Vector3(0.04, 0.24, 0.05), Vector3(s * 0.53, 0.885, -2.66), "satin", Vector3(deg_to_rad(-3.0), 0.0, 0.0))
	# Headlights: a swept-back unit at each corner, its lens over a dark bezel, an LED strip
	# along the top and an amber indicator at the outer end.
	for s in [-1.0, 1.0]:
		var o := func(x: float, y: float, z: float) -> Vector3: return Vector3(s * x, y, z)
		_add(ShapeKit.plate(PackedVector3Array([o.call(0.55, 1.005, -2.648), o.call(0.82, 1.03, -2.6), o.call(0.925, 1.0, -2.5),
			o.call(0.93, 0.9, -2.47), o.call(0.82, 0.88, -2.58), o.call(0.56, 0.86, -2.65)]), 0.02), "bezel")
		_add(ShapeKit.plate(PackedVector3Array([o.call(0.6, 0.985, -2.66), o.call(0.8, 1.0, -2.62), o.call(0.8, 0.9, -2.6),
			o.call(0.6, 0.885, -2.665)]), 0.012), "lamp")
		_add(ShapeKit.plate(PackedVector3Array([o.call(0.57, 1.0, -2.664), o.call(0.86, 1.02, -2.6), o.call(0.86, 1.008, -2.598),
			o.call(0.57, 0.99, -2.662)]), 0.008), "lamp")
		_add(ShapeKit.plate(PackedVector3Array([o.call(0.86, 0.99, -2.57), o.call(0.928, 0.97, -2.49), o.call(0.93, 0.915, -2.475),
			o.call(0.86, 0.9, -2.56)]), 0.012), "amber")


## The tailgate, tail lights, the step bumper, the tow bar and ball, and the rear plate.
func _rear_end() -> void:
	_add(prism(PackedVector2Array([Vector2(2.7, 0.6), Vector2(2.7, BELT - 0.005), Vector2(2.78, BELT - 0.005), Vector2(2.79, 0.6)]),
		-(W - SKIN) + 0.004, W - SKIN - 0.004, 0.02), "paint")
	_box(Vector3(0.26, 0.05, 0.02), Vector3(0.0, 1.11, 2.792), "black")
	_box(Vector3(1.6, 0.006, 0.006), Vector3(0.0, 0.95, 2.788), "under")
	for s in [-1.0, 1.0]:
		var lamp := PackedVector2Array([Vector2(2.74, 0.84), Vector2(2.74, 1.16), Vector2(2.805, 1.15), Vector2(2.805, 0.84)])
		_add(prism(lamp, (W - 0.075) if s > 0.0 else -W - 0.012, W + 0.012 if s > 0.0 else -(W - 0.075), 0.01), "brake")
		var rev := PackedVector2Array([Vector2(2.75, 0.86), Vector2(2.75, 0.94), Vector2(2.81, 0.94), Vector2(2.81, 0.86)])
		_add(prism(rev, (W - 0.07) if s > 0.0 else -W - 0.014, W + 0.014 if s > 0.0 else -(W - 0.07), 0.006), "reverse")
	# Step bumper with a black tread on top.
	var bumper := PackedVector2Array([Vector2(2.74, 0.46), Vector2(2.74, 0.66), Vector2(2.9, 0.665), Vector2(2.93, 0.62), Vector2(2.93, 0.47)])
	_add(prism(bumper, -0.92, 0.92, 0.03), "satin")
	_box(Vector3(0.6, 0.012, 0.12), Vector3(0.0, 0.67, 2.85), "black")
	_box(Vector3(0.52, 0.115, 0.012), Vector3(0.0, 0.555, 2.937), "plate_rear")
	# Tow bar: the receiver under the bumper, the drop plate and the ball on its neck.
	_box(Vector3(0.07, 0.07, 0.4), Vector3(0.0, 0.43, 2.78), "under")
	_box(Vector3(0.09, 0.12, 0.04), Vector3(0.0, 0.46, Car.HITCH.z - 0.04), "under")
	_cyl(0.022, 0.06, Transform3D(Basis(), Car.HITCH + Vector3(0.0, -0.02, 0.0)), "chrome")
	var ball := SphereMesh.new()
	ball.radius = 0.042
	ball.height = 0.084
	_add(ball, "chrome", Transform3D(Basis(), Car.HITCH + Vector3(0.0, 0.035, 0.0)))
	_box(Vector3(0.06, 0.06, 0.05), Vector3(0.14, 0.47, 2.9), "black")   # the electrics socket


## The load bed: a black liner floor, sides and front wall, the wheel tubs, rail caps, tie-down
## hooks, and the sports bar over it.
func _bed() -> void:
	var inner := W - SKIN
	_box(Vector3(inner * 2.0, 0.04, 1.9), Vector3(0.0, 0.86, 1.75), "liner")
	_box(Vector3(inner * 2.0, BELT - 0.84, 0.06), Vector3(0.0, (BELT + 0.84) * 0.5, 0.81), "paint")
	_boxes(Vector3(0.012, BELT - 0.88, 1.88), Vector3(inner - 0.007, (BELT + 0.88) * 0.5, 1.75), "liner")
	_boxes(Vector3(0.22, 0.13, 0.95), Vector3(inner - 0.11, 0.94, Car.REAR_Z), "liner")
	_boxes(Vector3(0.09, 0.025, 1.96), Vector3(W - 0.035, BELT + 0.012, 1.77), "black")
	for z in [0.95, 2.6]:
		_boxes(Vector3(0.03, 0.05, 0.05), Vector3(inner - 0.03, 1.1, z), "satin")
	# The sports bar: a hoop behind the cab with braces back to the bed rails.
	var tube := 0.032
	var hoop := []
	for p in [[0.84, BELT + 0.01, 0.97], [0.82, 1.5, 0.99], [0.76, 1.68, 1.0], [0.6, 1.75, 1.01], [0.0, 1.75, 1.01]]:
		hoop.append(Vector3(p[0], p[1], p[2]))
	var full := hoop.duplicate()
	for i in range(hoop.size() - 2, -1, -1):
		var v: Vector3 = hoop[i]
		full.append(Vector3(-v.x, v.y, v.z))
	_add(ShapeKit.sweep(full, tube, 12), "satin")
	for s in [-1.0, 1.0]:
		_add(ShapeKit.sweep([Vector3(s * 0.8, 1.6, 1.0), Vector3(s * 0.82, 1.4, 1.25), Vector3(s * 0.84, BELT + 0.01, 1.55)], tube * 0.85, 10), "satin")
		_box(Vector3(0.09, 0.02, 0.12), Vector3(s * 0.84, BELT + 0.02, 0.97), "satin")
		_box(Vector3(0.09, 0.02, 0.12), Vector3(s * 0.84, BELT + 0.02, 1.55), "satin")


## Mirrors, door handles, shut lines, the fuel flap, side steps, mud flaps, the underbody and
## exhaust, and the roof aerial.
func _details() -> void:
	for s in [-1.0, 1.0]:
		# Door mirror: an arm off the door, the housing, the glass facing back, a repeater.
		var housing := PackedVector2Array([Vector2(-1.06, 1.24), Vector2(-1.07, 1.37), Vector2(-1.03, 1.41),
			Vector2(-0.94, 1.41), Vector2(-0.93, 1.24)])
		var x0 := W + 0.07 if s > 0.0 else -W - 0.29
		_add(prism(housing, x0, x0 + 0.22, 0.03), "gloss")
		_box(Vector3(0.12, 0.05, 0.08), Vector3(s * (W + 0.05), 1.27, -1.0), "gloss")
		_box(Vector3(0.19, 0.14, 0.006), Vector3(s * (W + 0.18), 1.325, -0.927), "mirror")
		_box(Vector3(0.12, 0.012, 0.03), Vector3(s * (W + 0.19), 1.245, -1.05), "amber")
	# Door handles (black, with a keyhole on the front ones) and the shut lines round the doors.
	for z in [-0.36, 0.42]:
		_boxes(Vector3(0.025, 0.035, 0.17), Vector3(W + 0.008, 1.09, z), "gloss")
		_boxes(Vector3(0.004, 0.05, 0.2), Vector3(W + 0.002, 1.09, z), "under")
	for z in [-1.1, -0.06, 0.69, 0.785]:
		_boxes(Vector3(0.004, 0.66, 0.005), Vector3(W + 0.0015, 0.87, z), "under")
	_boxes(Vector3(0.004, 0.005, 1.79), Vector3(W + 0.0015, 0.555, -0.205), "under")
	# The bonnet's shut line across the front and the fuel flap on the left of the bed.
	_box(Vector3(1.66, 0.005, 0.005), Vector3(0.0, 1.0, -2.6), "under")
	for e in [[Vector3(0.004, 0.16, 0.005), Vector3(-W - 0.0015, 1.0, 1.0)], [Vector3(0.004, 0.16, 0.005), Vector3(-W - 0.0015, 1.0, 1.16)],
			[Vector3(0.004, 0.005, 0.16), Vector3(-W - 0.0015, 1.08, 1.08)], [Vector3(0.004, 0.005, 0.16), Vector3(-W - 0.0015, 0.92, 1.08)]]:
		_box(e[0], e[1], "under")
	# Side steps under the doors, on brackets.
	_boxes(Vector3(0.2, 0.035, 2.0), Vector3(W - 0.04, 0.43, 0.04), "black")
	_boxes(Vector3(0.18, 0.006, 1.9), Vector3(W - 0.04, 0.45, 0.04), "satin")
	for z in [-0.7, 0.75]:
		_boxes(Vector3(0.2, 0.08, 0.04), Vector3(W - 0.14, 0.47, z), "under")
	# Mud flaps behind the wheels.
	for z in [Car.FRONT_Z + 0.52, Car.REAR_Z + 0.53]:
		_boxes(Vector3(0.24, 0.26, 0.012), Vector3(W - 0.14, 0.38, z), "black")
	# Underneath: the floor pan and chassis rails, the fuel tank, the exhaust out the back left.
	_box(Vector3(1.24, 0.2, 5.0), Vector3(0.0, 0.48, 0.1), "under")
	_boxes(Vector3(0.1, 0.14, 5.1), Vector3(0.45, 0.39, 0.15), "under")
	_box(Vector3(0.6, 0.24, 0.6), Vector3(-0.25, 0.4, 1.0), "under")
	_add(ShapeKit.sweep([Vector3(-0.35, 0.36, 0.4), Vector3(-0.42, 0.34, 1.6), Vector3(-0.5, 0.33, 2.4), Vector3(-0.55, 0.32, 2.78)], 0.032, 10), "satin")
	_cyl(0.04, 0.12, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.55, 0.32, 2.8)), "rim_dark")
	# A stubby aerial at the front of the roof.
	_add(ShapeKit.sweep([Vector3(0.0, 1.785, -0.25), Vector3(0.0, 1.87, -0.15), Vector3(0.0, 1.9, -0.05)], 0.008, 6), "black")


## What you see from the driver's seat: the dash with its instrument binnacle and screen, the
## console and gear lever, front seats and the back bench, door cards, the mirror and visors.
func _interior() -> void:
	var inner := W - SKIN
	_box(Vector3(inner * 2.0, 0.06, 1.85), Vector3(0.0, 0.62, -0.19), "carpet")
	_boxes(Vector3(0.025, BELT - 0.66, 1.84), Vector3(inner - 0.012, (BELT + 0.66) * 0.5, -0.19), "trim_in")
	_boxes(Vector3(0.07, 0.04, 0.5), Vector3(inner - 0.045, 0.98, -0.45), "trim_in")
	_boxes(Vector3(0.07, 0.04, 0.42), Vector3(inner - 0.045, 0.98, 0.38), "trim_in")
	_box(Vector3(inner * 2.0, BELT - 0.6, 0.04), Vector3(0.0, (BELT + 0.6) * 0.5, 0.72), "trim_in")
	# The dashboard.
	var dash := PackedVector2Array([Vector2(-1.13, 0.78), Vector2(-1.13, BELT + 0.01), Vector2(-1.0, 1.255),
		Vector2(-0.86, 1.235), Vector2(-0.76, 1.12), Vector2(-0.78, 0.96), Vector2(-0.9, 0.8)])
	_add(prism(dash, -inner + 0.02, inner - 0.02, 0.035), "trim_in")
	var ex := Car.EYE.x
	var hood := PackedVector2Array([Vector2(-0.98, 1.22), Vector2(-0.96, 1.31), Vector2(-0.86, 1.32), Vector2(-0.82, 1.24)])
	_add(prism(hood, ex - 0.17, ex + 0.17, 0.02), "trim_in")
	for dx in [-0.075, 0.075]:
		_cyl(0.052, 0.01, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(70.0)), Vector3(ex + dx, 1.255, -0.865)), "dials", 20)
	_box(Vector3(0.24, 0.14, 0.012), Vector3(0.0, 1.17, -0.8), "dials", Vector3(deg_to_rad(-20.0), 0.0, 0.0))
	for x in [-0.6, -0.2, 0.2, 0.62]:
		_box(Vector3(0.12, 0.05, 0.02), Vector3(x, 1.2, -0.78 if absf(x) < 0.5 else -0.84), "gloss")
	# The centre console, gear lever and handbrake.
	_box(Vector3(0.24, 0.26, 1.0), Vector3(0.0, 0.78, -0.35), "trim_in")
	_cyl(0.008, 0.18, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.99, -0.55)), "satin", 8)
	var knob := SphereMesh.new()
	knob.radius = 0.03
	knob.height = 0.06
	_add(knob, "gloss", Transform3D(Basis(), Vector3(0.0, 1.08, -0.57)))
	_box(Vector3(0.04, 0.03, 0.22), Vector3(0.06, 0.93, -0.1), "gloss", Vector3(deg_to_rad(10.0), 0.0, 0.0))
	# Front seats: cushion, back and headrest.
	for x in [-0.4, ex]:
		var cushion := PackedVector2Array([Vector2(-0.52, 0.8), Vector2(-0.5, 0.9), Vector2(-0.1, 0.92), Vector2(0.06, 0.88),
			Vector2(0.06, 0.7), Vector2(-0.48, 0.7)])
		_add(prism(cushion, x - 0.25, x + 0.25, 0.05), "seat")
		var back := PackedVector2Array([Vector2(0.02, 0.88), Vector2(-0.02, 1.45), Vector2(0.03, 1.52), Vector2(0.13, 1.51),
			Vector2(0.17, 0.92), Vector2(0.1, 0.86)])
		_add(prism(back, x - 0.25, x + 0.25, 0.06), "seat")
		var rest := PackedVector2Array([Vector2(0.04, 1.57), Vector2(0.035, 1.71), Vector2(0.12, 1.72), Vector2(0.13, 1.57)])
		_add(prism(rest, x - 0.13, x + 0.13, 0.03), "seat")
		for dx in [-0.07, 0.07]:
			_cyl(0.007, 0.07, Transform3D(Basis(), Vector3(x + dx, 1.54, 0.085)), "satin", 6)
	# The back bench.
	var bench := PackedVector2Array([Vector2(0.24, 0.8), Vector2(0.26, 0.9), Vector2(0.62, 0.9), Vector2(0.62, 0.66), Vector2(0.28, 0.66)])
	_add(prism(bench, -inner + 0.06, inner - 0.06, 0.05), "seat")
	var bench_back := PackedVector2Array([Vector2(0.6, 0.88), Vector2(0.56, 1.4), Vector2(0.6, 1.45), Vector2(0.69, 1.45), Vector2(0.7, 0.88)])
	_add(prism(bench_back, -inner + 0.06, inner - 0.06, 0.05), "seat")
	# The rear-view mirror and the sun visors.
	_box(Vector3(0.24, 0.07, 0.02), Vector3(0.0, 1.66, -0.42), "gloss", Vector3(deg_to_rad(-10.0), 0.0, 0.0))
	_box(Vector3(0.02, 0.05, 0.02), Vector3(0.0, 1.71, -0.4), "gloss")
	for x in [-0.4, 0.4]:
		_box(Vector3(0.36, 0.012, 0.16), Vector3(x, 1.725, -0.36), "headliner", Vector3(deg_to_rad(-8.0), 0.0, 0.0))


# ---------------------------------------------------------------------------- moving parts

## A wheel: an all-terrain tyre with a chunky tread, a six-spoke alloy with its centre cap and
## wheel nuts, and the brake disc behind (outer face +x).
func _wheel_mesh() -> ArrayMesh:
	var r := Car.RADIUS
	var tyre := [Vector2(0.225, -0.112), Vector2(0.27, -0.128), Vector2(0.33, -0.13), Vector2(0.365, -0.124), Vector2(r - 0.008, -0.11),
		Vector2(r, -0.094), Vector2(r, -0.04), Vector2(r - 0.012, -0.028), Vector2(r - 0.012, -0.016), Vector2(r, -0.006),
		Vector2(r, 0.006), Vector2(r - 0.012, 0.016), Vector2(r - 0.012, 0.028), Vector2(r, 0.04), Vector2(r, 0.094),
		Vector2(r - 0.008, 0.11), Vector2(0.365, 0.124), Vector2(0.33, 0.13), Vector2(0.27, 0.128), Vector2(0.225, 0.112)]
	# Tread blocks: the shoulders stepped in and out round the tyre, staggered side to side.
	var lugs := func(j: int, i: int) -> float:
		if i in [4, 5, 6] and j % 2 == 0:
			return -0.009
		if i in [13, 14, 15] and j % 2 == 1:
			return -0.009
		if i in [9, 10] and j % 4 < 2:
			return -0.006
		return 0.0
	var list := [[lathe(tyre, 48, lugs), Transform3D(), m["tyre"]]]
	# The rim: barrel and dish, dark inside, polished face.
	var barrel := [Vector2(0.226, 0.105), Vector2(0.226, -0.1), Vector2(0.2, -0.105), Vector2(0.19, 0.0), Vector2(0.17, 0.05),
		Vector2(0.07, 0.06)]
	list.append([lathe(barrel, 32), Transform3D(), m["rim_dark"]])
	var lip := [Vector2(0.232, 0.1), Vector2(0.232, 0.116), Vector2(0.205, 0.112), Vector2(0.2, 0.1)]
	list.append([lathe(lip, 32), Transform3D(), m["rim"]])
	for k in 6:
		var a := TAU * k / 6.0
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.03, 0.15, 0.045)
		var b := Basis(Vector3.RIGHT, a)
		list.append([spoke, Transform3D(b, Vector3(0.088, 0.0, 0.0) + b * Vector3(0.0, 0.135, 0.0)) * Transform3D(Basis(Vector3.FORWARD, 0.08), Vector3.ZERO), m["rim"]])
		var nut := CylinderMesh.new()
		nut.top_radius = 0.011
		nut.bottom_radius = 0.011
		nut.height = 0.02
		nut.radial_segments = 6
		list.append([nut, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), b * Vector3(0.0, 0.05, 0.0) + Vector3(0.1, 0.0, 0.0)), m["chrome"]])
	var cap := [Vector2(0.065, 0.085), Vector2(0.06, 0.1), Vector2(0.035, 0.108), Vector2(0.0, 0.11)]
	list.append([lathe(cap, 24), Transform3D(), m["rim"]])
	var hub := [Vector2(0.07, 0.07), Vector2(0.07, 0.09)]
	list.append([lathe(hub, 24), Transform3D(), m["rim_dark"]])
	var disc := [Vector2(0.17, -0.025), Vector2(0.17, 0.0), Vector2(0.08, 0.0), Vector2(0.08, -0.025)]
	list.append([lathe(disc, 32), Transform3D(), m["disc"]])
	return merged(list)


func _wheels() -> void:
	var mesh := _wheel_mesh()
	for w in car.wheels:
		var holder := Node3D.new()
		car.model.add_child(holder)
		var spin := Node3D.new()
		holder.add_child(spin)
		var right: bool = (w["mount"] as Vector3).x > 0.0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if not right:
			mi.rotation.y = PI
		spin.add_child(mi)
		# The brake caliper, on the hub behind the spokes (it doesn't turn with the wheel).
		var cal := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.05, 0.12, 0.08)
		cal.mesh = cb
		cal.material_override = m["caliper"]
		cal.position = Vector3(0.0 if right else 0.0, 0.11, 0.1 if w["front"] else -0.1)
		holder.add_child(cal)
		car._wheel_nodes.append([holder, spin])


## The steering wheel: three spokes and a leather rim, on its column from the dash, turned in
## Car._update_model (about its own axis, by the rack's ratio).
func _steering_wheel() -> void:
	var at := Vector3(Car.EYE.x, 1.24, -0.66)
	var col := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(62.0)), at)   # its axis up and back at the driver
	var holder := Node3D.new()
	holder.transform = col
	car.model.add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.165
	rim.outer_radius = 0.193
	rim.rings = 32
	rim.ring_segments = 10
	var list := [[rim, Transform3D(), m["gloss"]]]
	var hub := CylinderMesh.new()
	hub.top_radius = 0.06
	hub.bottom_radius = 0.065
	hub.height = 0.05
	list.append([hub, Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)), m["trim_in"]])
	for a in [PI * 0.5, -PI * 0.5, PI]:
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.12, 0.018, 0.04)
		var b := Basis(Vector3.UP, a)
		list.append([spoke, Transform3D(b, b * Vector3(0.11, 0.0, 0.0)), m["trim_in"]])
	var mi := MeshInstance3D.new()
	mi.mesh = merged(list)
	spin.add_child(mi)
	var column := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.045
	cm.height = 0.26
	column.mesh = cm
	column.material_override = m["trim_in"]
	column.position = Vector3(0.0, -0.15, 0.0)
	holder.add_child(column)
	car._steering_wheel = spin


## The headlamps' beams (on with the engine).
func _lights() -> void:
	for x in [-0.72, 0.72]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(x, 0.94, -2.72)
		sl.spot_range = 45.0
		sl.spot_angle = 32.0
		sl.light_energy = 3.0
		sl.rotation.x = deg_to_rad(-6.0)
		sl.shadow_enabled = false
		car.model.add_child(sl)
		car._head_lights.append(sl)


## The garage's name on the front doors and the number plates.
func _signs() -> void:
	for side: float in [-1.0, 1.0]:
		var sign := Label3D.new()
		sign.text = "TORQUE SHED\nRECOVERY"
		sign.font_size = 40
		sign.pixel_size = 0.0022
		sign.modulate = Color(0.95, 0.85, 0.35)
		sign.outline_size = 0
		sign.position = Vector3(side * (W + 0.004), 0.86, -0.6)
		sign.rotation.y = side * PI * 0.5
		car.model.add_child(sign)
	for e in [[Vector3(0.0, 0.6, -2.792), PI], [Vector3(0.0, 0.555, 2.944), 0.0]]:
		var plate := Label3D.new()
		plate.text = "TQ19 RCV"
		plate.font_size = 64
		plate.pixel_size = 0.0011
		plate.modulate = Color(0.02, 0.02, 0.02)
		plate.outline_size = 0
		plate.position = e[0]
		plate.rotation.y = e[1]
		car.model.add_child(plate)
