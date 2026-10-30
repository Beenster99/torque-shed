class_name AdventureProps
extends RefCounted
## The things along an adventure road: low-poly trees, bushes and rocks (one mesh each, drawn
## many times over by a chunk's MultiMeshes), fence and marker posts, the odd house or barn
## (merged into one mesh per chunk), the kilometre posts, the start and finish banners and the
## fuel stations, whose pumps are in group "fuel_pump" for the kit's refuelling.
##
## Meshes are built from plain arrays ({v, n, c}: vertices, normals, colours) so a chunk's
## buildings can be laid out on a worker thread and only turned into a mesh on the main one.

const PUMP_GROUP := "fuel_pump"

static var _meshes := {}
static var _vc_mat: StandardMaterial3D


## How far a real building's walls go down under the ground (m).
const SKIRT := 1.5


# ---------------------------------------------------------------------------- array kit

static func new_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}


## A triangle given counter-clockwise as seen from its front (stored clockwise, as Godot's
## front faces are).
static func _tri(a: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	var nrm := (p1 - p0).cross(p2 - p0).normalized()
	a["v"].append_array([p0, p2, p1])
	a["n"].append_array([nrm, nrm, nrm])
	a["c"].append_array([col, col, col])


static func _quad(a: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	_tri(a, p0, p1, p2, col)
	_tri(a, p0, p2, p3, col)


## A box of `size` at `xf` (its middle at the bottom face: it stands on xf's origin).
static func box(a: Dictionary, xf: Transform3D, size: Vector3, col: Color, top := true) -> void:
	var h := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var y := size.y
	var c := [xf * Vector3(-h.x, 0, -h.z), xf * Vector3(h.x, 0, -h.z), xf * Vector3(h.x, 0, h.z), xf * Vector3(-h.x, 0, h.z),
		xf * Vector3(-h.x, y, -h.z), xf * Vector3(h.x, y, -h.z), xf * Vector3(h.x, y, h.z), xf * Vector3(-h.x, y, h.z)]
	_quad(a, c[3], c[2], c[6], c[7], col)          # front (+z)
	_quad(a, c[1], c[0], c[4], c[5], col)          # back
	_quad(a, c[2], c[1], c[5], c[6], col.darkened(0.08))   # right
	_quad(a, c[0], c[3], c[7], c[4], col.darkened(0.08))   # left
	if top:
		_quad(a, c[7], c[6], c[5], c[4], col.lightened(0.05))


## A gable roof over a `w` x `d` box `wall` high, ridge `rise` above the eaves, along z.
static func gable(a: Dictionary, xf: Transform3D, w: float, d: float, wall: float, rise: float, col: Color, gable_col: Color) -> void:
	var hw := w * 0.5 + 0.3
	var hd := d * 0.5 + 0.3
	var e0 := xf * Vector3(-hw, wall, -hd)
	var e1 := xf * Vector3(hw, wall, -hd)
	var e2 := xf * Vector3(hw, wall, hd)
	var e3 := xf * Vector3(-hw, wall, hd)
	var r0 := xf * Vector3(0, wall + rise, -hd)
	var r1 := xf * Vector3(0, wall + rise, hd)
	_quad(a, e3, r1, r0, e0, col)
	_quad(a, e1, r0, r1, e2, col)
	var g0 := xf * Vector3(-w * 0.5, wall, -d * 0.5)
	var g1 := xf * Vector3(w * 0.5, wall, -d * 0.5)
	var g2 := xf * Vector3(w * 0.5, wall, d * 0.5)
	var g3 := xf * Vector3(-w * 0.5, wall, d * 0.5)
	_tri(a, g1, g0, xf * Vector3(0, wall + rise, -d * 0.5), gable_col)
	_tri(a, g3, g2, xf * Vector3(0, wall + rise, d * 0.5), gable_col)


## A cone (or a frustum with `top_r`), `sides` round, from `y0` to `y1` along the local y axis.
static func cone(a: Dictionary, xf: Transform3D, r: float, y0: float, y1: float, col: Color, sides := 7, top_r := 0.0) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var b0 := xf * Vector3(cos(a0) * r, y0, sin(a0) * r)
		var b1 := xf * Vector3(cos(a1) * r, y0, sin(a1) * r)
		if top_r <= 0.0:
			_tri(a, b1, b0, xf * Vector3(0, y1, 0), col)
		else:
			var t0 := xf * Vector3(cos(a0) * top_r, y1, sin(a0) * top_r)
			var t1 := xf * Vector3(cos(a1) * top_r, y1, sin(a1) * top_r)
			_quad(a, b1, b0, t0, t1, col)


## A lumpy ball of radii `r` at `c`, each vertex nudged in or out a little.
static func blob(a: Dictionary, c: Vector3, r: Vector3, col: Color, seed_value := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rings := 4
	var segs := 7
	var pts := []
	for i in rings + 1:
		var row := []
		var phi := PI * i / rings
		for j in segs:
			var th := TAU * j / segs + (0.4 if i % 2 == 1 else 0.0)
			var k := 1.0 + rng.randf_range(-0.12, 0.12) if i > 0 and i < rings else 1.0
			row.append(c + Vector3(sin(phi) * cos(th) * r.x * k, cos(phi) * r.y * k, sin(phi) * sin(th) * r.z * k))
		pts.append(row)
	for i in rings:
		for j in segs:
			var j1 := (j + 1) % segs
			var shade := col.darkened(0.12 * float(i) / rings)
			_quad(a, pts[i][j], pts[i][j1], pts[i + 1][j1], pts[i + 1][j], shade)


## The arrays as a mesh (vertex coloured).
static func to_mesh(a: Dictionary, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if (a["v"] as PackedVector3Array).is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["v"]
	arr[Mesh.ARRAY_NORMAL] = a["n"]
	arr[Mesh.ARRAY_COLOR] = a["c"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, vc_material())
	return mesh


static func vc_material() -> StandardMaterial3D:
	if _vc_mat:
		return _vc_mat
	_vc_mat = StandardMaterial3D.new()
	_vc_mat.vertex_color_use_as_albedo = true
	_vc_mat.vertex_color_is_srgb = true
	_vc_mat.roughness = 0.9
	return _vc_mat


# ---------------------------------------------------------------------------- scenery meshes

## One shared mesh per kind: "pine", "snow_pine", "tree", "bush", "dry_bush", "rock", "post",
## "snow_pole", "km_post", and the themes' (AdventureTheme): "cactus", "red_rock", "mesa" (desert),
## "crag" (alpine), "gorse", "dune_grass", "lighthouse" (coastal), "oak", "sheep" (hills), and the place's vegetation
## kits' (PlaceLook.plant).
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var a := new_arrays()
	var trunk := Color(0.32, 0.22, 0.14)
	match kind:
		"pine", "snow_pine":
			cone(a, Transform3D(), 0.22, 0.0, 1.6, trunk, 5, 0.15)
			var green := Color(0.13, 0.27, 0.15)
			for k in 3:
				var y0 := 1.2 + k * 1.9
				cone(a, Transform3D(), 2.2 - k * 0.55, y0, y0 + 3.0, green.lightened(0.04 * k), 8)
				if kind == "snow_pine":
					cone(a, Transform3D(), (2.2 - k * 0.55) * 0.6, y0 + 1.2, y0 + 3.05, Color(0.92, 0.94, 0.98), 8)
		"tree":
			cone(a, Transform3D(), 0.28, 0.0, 2.6, trunk, 6, 0.18)
			blob(a, Vector3(0, 4.2, 0), Vector3(2.6, 2.3, 2.6), Color(0.24, 0.38, 0.14), 3)
			blob(a, Vector3(0.9, 5.4, 0.4), Vector3(1.6, 1.4, 1.6), Color(0.28, 0.42, 0.16), 5)
		"bush":
			blob(a, Vector3(0, 0.55, 0), Vector3(1.1, 0.75, 1.1), Color(0.22, 0.34, 0.12), 7)
		"dry_bush":
			blob(a, Vector3(0, 0.4, 0), Vector3(0.9, 0.5, 0.9), Color(0.52, 0.46, 0.27), 9)
		"rock":
			blob(a, Vector3(0, 0.25, 0), Vector3(1.0, 0.7, 0.85), Color(0.46, 0.45, 0.43), 11)
		"post":
			box(a, Transform3D(), Vector3(0.12, 1.15, 0.12), Color(0.42, 0.32, 0.22))
		"snow_pole":
			for k in 5:
				box(a, Transform3D(Basis(), Vector3(0, k * 0.4, 0)), Vector3(0.07, 0.4, 0.07),
					Color(0.95, 0.42, 0.08) if k % 2 == 0 else Color(0.08, 0.08, 0.08), k == 4)
		"km_post":
			box(a, Transform3D(), Vector3(0.18, 1.0, 0.1), Color(0.94, 0.94, 0.92))
			box(a, Transform3D(Basis(), Vector3(0, 0.82, 0)), Vector3(0.19, 0.12, 0.11), Color(0.85, 0.15, 0.1))
		"cactus":
			var green := Color(0.25, 0.42, 0.2)
			cone(a, Transform3D(), 0.3, 0.0, 4.0, green, 6, 0.26)
			cone(a, Transform3D(), 0.26, 4.0, 4.35, green, 6)
			for arm: Array in [[-1.0, 1.6, 1.1], [1.0, 2.2, 0.9]]:
				var sx: float = arm[0]
				box(a, Transform3D(Basis(), Vector3(sx * 0.55, arm[1], 0)), Vector3(0.75, 0.36, 0.36), green)
				cone(a, Transform3D(Basis(), Vector3(sx * 0.85, 0, 0)), 0.2, arm[1], arm[1] + arm[2] + 0.6, green, 5, 0.17)
		"red_rock":
			blob(a, Vector3(0, 0.3, 0), Vector3(1.3, 0.9, 1.0), Color(0.62, 0.37, 0.25), 13)
		"mesa":
			# A butte: layered red rock with a flat top, bands of a paler stone.
			cone(a, Transform3D(), 40.0, -6.0, 6.0, Color(0.6, 0.36, 0.24), 9, 34.0)
			cone(a, Transform3D(), 34.0, 6.0, 26.0, Color(0.68, 0.4, 0.26), 9, 31.0)
			cone(a, Transform3D(), 31.0, 26.0, 30.0, Color(0.78, 0.56, 0.4), 9, 30.0)
			cone(a, Transform3D(), 30.0, 30.0, 44.0, Color(0.64, 0.36, 0.23), 9, 28.0)
			cone(a, Transform3D(), 28.0, 44.0, 44.05, Color(0.7, 0.5, 0.34), 9)
		"crag":
			var stone := Color(0.5, 0.49, 0.47)
			blob(a, Vector3(0, 6.0, 0), Vector3(16.0, 13.0, 11.0), stone, 17)
			blob(a, Vector3(5.0, 15.0, 2.0), Vector3(8.0, 11.0, 7.0), stone.darkened(0.08), 19)
			blob(a, Vector3(5.5, 24.0, 2.0), Vector3(4.2, 2.6, 3.8), Color(0.9, 0.92, 0.95), 23)
		"gorse":
			blob(a, Vector3(0, 0.55, 0), Vector3(1.1, 0.75, 1.0), Color(0.2, 0.31, 0.12), 29)
			blob(a, Vector3(0.25, 1.05, 0.15), Vector3(0.6, 0.28, 0.55), Color(0.92, 0.78, 0.14), 31)
		"dune_grass":
			for t: Vector3 in [Vector3(0, 0, 0), Vector3(0.5, 0, 0.3), Vector3(-0.35, 0, 0.45)]:
				cone(a, Transform3D(Basis(), t), 0.32, 0.0, 0.95, Color(0.6, 0.6, 0.36), 5)
		"oak":
			cone(a, Transform3D(), 0.5, 0.0, 3.0, trunk, 6, 0.32)
			blob(a, Vector3(0, 5.2, 0), Vector3(3.8, 2.7, 3.8), Color(0.2, 0.33, 0.12), 37)
			blob(a, Vector3(1.6, 6.4, 0.8), Vector3(2.2, 1.7, 2.2), Color(0.24, 0.38, 0.14), 41)
			blob(a, Vector3(-1.5, 6.0, -1.0), Vector3(2.0, 1.6, 2.0), Color(0.22, 0.35, 0.13), 43)
		"sheep":
			var dark := Color(0.12, 0.11, 0.1)
			for leg: Vector3 in [Vector3(-0.2, 0, -0.35), Vector3(0.2, 0, -0.35), Vector3(-0.2, 0, 0.35), Vector3(0.2, 0, 0.35)]:
				box(a, Transform3D(Basis(), leg), Vector3(0.08, 0.5, 0.08), dark, false)
			blob(a, Vector3(0, 0.78, 0), Vector3(0.42, 0.36, 0.62), Color(0.9, 0.89, 0.84), 47)
			blob(a, Vector3(0, 0.9, -0.72), Vector3(0.15, 0.18, 0.22), dark, 53)
		"lighthouse":
			# White with red bands, the gallery and lantern on top, the keeper's cottage beside it.
			for k in 4:
				var y0 := k * 4.5
				cone(a, Transform3D(), 2.6 - k * 0.25, y0, y0 + 4.5, Color(0.95, 0.95, 0.93) if k % 2 == 0 else Color(0.78, 0.12, 0.1), 10, 2.35 - k * 0.25)
			cone(a, Transform3D(), 2.2, 18.0, 18.3, Color(0.15, 0.15, 0.16), 10, 2.2)
			cone(a, Transform3D(), 2.2, 18.3, 18.31, Color(0.15, 0.15, 0.16), 10)
			cone(a, Transform3D(), 1.1, 18.3, 20.3, Color(0.98, 0.92, 0.6), 8, 1.1)
			cone(a, Transform3D(), 1.4, 20.3, 21.6, Color(0.7, 0.12, 0.1), 8)
			var cottage := Transform3D(Basis(), Vector3(0, 0, 6.5))
			box(a, cottage, Vector3(7.0, 3.0, 4.5), Color(0.95, 0.95, 0.93), false)
			gable(a, cottage * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), 4.5, 7.0, 3.0, 1.8, Color(0.28, 0.3, 0.35), Color(0.95, 0.95, 0.93))
		_:
			PlaceLook.plant(a, kind)   # (the place's vegetation kits' own: birch, olive, palm and the rest)
	var m := to_mesh(a)
	_meshes[kind] = m
	return m


## The odd house, cottage or barn by the road, into `a` at `xf` (its front facing local +z), in
## the theme's building style (`style_name`, see AdventureTheme.STYLES: adobe ones are flat-roofed).
static func building(a: Dictionary, xf: Transform3D, rng: RandomNumberGenerator, surf: String, style_name := "mixed") -> void:
	var kind := rng.randi_range(0, 2)
	var walls := [Color(0.86, 0.82, 0.72), Color(0.72, 0.62, 0.5), Color(0.6, 0.3, 0.22), Color(0.9, 0.9, 0.88)]
	var roofs := [Color(0.25, 0.22, 0.22), Color(0.45, 0.2, 0.15), Color(0.32, 0.34, 0.36)]
	if surf == "sand":
		walls = [Color(0.86, 0.74, 0.55), Color(0.92, 0.85, 0.7)]
	if style_name != "mixed" and AdventureTheme.STYLES.has(style_name):
		var st: Dictionary = AdventureTheme.STYLES[style_name]
		walls = st["walls"]
		roofs = st["roofs"]
		if bool(st["flat"]):
			kind = 2
	var wall: Color = walls[rng.randi_range(0, walls.size() - 1)]
	var roof: Color = roofs[rng.randi_range(0, roofs.size() - 1)]
	if surf == "snow":
		roof = Color(0.92, 0.93, 0.96)
	match kind:
		0:   # a cottage
			var w := rng.randf_range(6.0, 9.0)
			var d := rng.randf_range(5.0, 7.0)
			box(a, xf, Vector3(w, 3.0, d), wall, false)
			gable(a, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), d, w, 3.0, 2.2, roof, wall)
			box(a, xf * Transform3D(Basis(), Vector3(0, 0, d * 0.5)), Vector3(1.0, 2.0, 0.08), Color(0.25, 0.14, 0.08))
			for sx: float in [-1.0, 1.0]:
				box(a, xf * Transform3D(Basis(), Vector3(sx * w * 0.3, 1.2, d * 0.5)), Vector3(1.0, 0.9, 0.06), Color(0.15, 0.2, 0.28))
		1:   # a barn
			var w2 := rng.randf_range(9.0, 14.0)
			var d2 := rng.randf_range(7.0, 10.0)
			var barn := [Color(0.5, 0.18, 0.12), Color(0.36, 0.34, 0.3), Color(0.3, 0.38, 0.3)][rng.randi_range(0, 2)] as Color
			box(a, xf, Vector3(w2, 4.5, d2), barn, false)
			gable(a, xf, w2, d2, 4.5, 2.6, roof, barn)
			box(a, xf * Transform3D(Basis(), Vector3(0, 0, d2 * 0.5)), Vector3(3.2, 3.4, 0.08), barn.darkened(0.35))
		_:   # a flat-roofed shed or a desert house
			var w3 := rng.randf_range(5.0, 8.0)
			var d3 := rng.randf_range(4.0, 6.0)
			box(a, xf, Vector3(w3, 2.8, d3), wall)
			box(a, xf * Transform3D(Basis(), Vector3(0, 2.8, 0)), Vector3(w3 + 0.3, 0.18, d3 + 0.3), roof)
			box(a, xf * Transform3D(Basis(), Vector3(-w3 * 0.25, 0, d3 * 0.5)), Vector3(0.9, 2.0, 0.08), Color(0.3, 0.2, 0.12))


## A real building (see RealPack: a footprint's box, its kind and height) into `a`: its middle on the ground at
## `pos`, turned `yaw` about up, `w` along local x and `d` along local z, `h` tall, in the theme's building
## style. Walls go on 1.5 m under the ground so a slope never leaves a gap.
static func real_building(a: Dictionary, pos: Vector3, w: float, d: float, yaw: float, h: float, kind: String,
		style_name := "mixed") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([roundi(pos.x * 10.0), roundi(pos.z * 10.0)])
	var walls := [Color(0.86, 0.82, 0.72), Color(0.72, 0.62, 0.5), Color(0.6, 0.32, 0.24), Color(0.9, 0.9, 0.88), Color(0.68, 0.7, 0.66)]
	var roofs := [Color(0.25, 0.22, 0.22), Color(0.45, 0.2, 0.15), Color(0.32, 0.34, 0.36)]
	var flat_style := false
	if style_name != "mixed" and AdventureTheme.STYLES.has(style_name):
		var st: Dictionary = AdventureTheme.STYLES[style_name]
		walls = st["walls"]
		roofs = st["roofs"]
		flat_style = bool(st["flat"])
	var wall: Color = walls[rng.randi_range(0, walls.size() - 1)]
	var roof: Color = roofs[rng.randi_range(0, roofs.size() - 1)]
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, -SKIRT, 0.0))
	var door := Color(0.25, 0.14, 0.08)
	var glass := Color(0.15, 0.2, 0.28)
	match kind:
		"shed":
			box(a, xf, Vector3(w, h + SKIRT, d), wall.darkened(0.12), false)
			box(a, xf * Transform3D(Basis(), Vector3(0, h + SKIRT, 0)), Vector3(w + 0.3, 0.16, d + 0.3), roof)
		"barn":
			var c := wall.darkened(0.25)
			box(a, xf, Vector3(w, h * 0.62 + SKIRT, d), c, false)
			_roof(a, xf, w, d, h * 0.62 + SKIRT, h * 0.38, roof, c)
			box(a, xf * Transform3D(Basis(), Vector3(0, SKIRT, d * 0.5)), Vector3(minf(3.2, w * 0.5), minf(3.2, h * 0.5), 0.08), c.darkened(0.35))
		"block", "shop", "civic":
			box(a, xf, Vector3(w, h + SKIRT, d), wall, false)
			box(a, xf * Transform3D(Basis(), Vector3(0, h + SKIRT, 0)), Vector3(w + 0.4, 0.22, d + 0.4), roof.lightened(0.1))
			var floors := maxi(1, int(h / 3.2))
			var bays := clampi(int(w / 3.0), 1, 8)
			for f in floors:
				for b in bays:
					var wx := (float(b) + 0.5) / bays * w - w * 0.5
					if kind == "shop" and f == 0:
						continue
					var wat := xf * Vector3(wx, SKIRT + 1.0 + f * 3.0, d * 0.5)
					box(a, xf * Transform3D(Basis(), Vector3(wx, SKIRT + 1.0 + f * 3.0, d * 0.5)), Vector3(minf(1.3, w / bays * 0.6), 1.2, 0.06),
						WindowLights.mark(glass, wat))
			if kind == "shop":
				box(a, xf * Transform3D(Basis(), Vector3(0, SKIRT + 0.3, d * 0.5)), Vector3(w * 0.8, 2.0, 0.07), WindowLights.mark(glass.lightened(0.15), xf.origin))
		"industrial":
			var c := Color(0.62, 0.64, 0.62).lerp(wall, 0.25)
			box(a, xf, Vector3(w, h + SKIRT, d), c, false)
			_roof(a, xf, w, d, h + SKIRT, minf(2.0, h * 0.3), Color(0.5, 0.52, 0.54), c)
			box(a, xf * Transform3D(Basis(), Vector3(0, SKIRT, d * 0.5)), Vector3(minf(4.0, w * 0.5), minf(3.6, h * 0.8), 0.08), c.darkened(0.3))
		"worship":
			var c := Color(0.8, 0.74, 0.62)
			box(a, xf, Vector3(w, h * 0.55 + SKIRT, d), c, false)
			_roof(a, xf, w, d, h * 0.55 + SKIRT, h * 0.45, Color(0.22, 0.24, 0.27), c)
			box(a, xf * Transform3D(Basis(), Vector3(0, SKIRT, d * 0.5)), Vector3(1.6, 2.4, 0.08), Color(0.45, 0.14, 0.1))
		_:   # a house
			box(a, xf, Vector3(w, minf(h, 3.2 * maxf(1.0, floorf(h / 3.2))) + SKIRT, d), wall, false)
			var eaves := minf(h, 3.2 * maxf(1.0, floorf(h / 3.2))) + SKIRT
			if flat_style:
				box(a, xf * Transform3D(Basis(), Vector3(0, eaves, 0)), Vector3(w + 0.3, 0.18, d + 0.3), roof)
			else:
				_roof(a, xf, w, d, eaves, clampf(minf(w, d) * 0.3, 1.2, 3.0), roof, wall)
			box(a, xf * Transform3D(Basis(), Vector3(-w * 0.25, SKIRT, d * 0.5)), Vector3(0.9, 2.0, 0.08), door)
			for sx: float in [-1.0, 1.0]:
				if w > 5.0:
					box(a, xf * Transform3D(Basis(), Vector3(sx * w * 0.3 + w * 0.1, SKIRT + 1.1, d * 0.5)), Vector3(1.0, 0.9, 0.06),
						WindowLights.mark(glass, xf * Vector3(sx, 1.1, 0.0)))


## A gable roof over a `w` x `d` box, the ridge along its long side.
static func _roof(a: Dictionary, xf: Transform3D, w: float, d: float, eaves: float, rise: float, col: Color, gable_col: Color) -> void:
	if w > d:
		gable(a, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), d, w, eaves, rise, col, gable_col)
	else:
		gable(a, xf, w, d, eaves, rise, col, gable_col)


## A speed-limit sign on the verge (site `site`'s "kmh" shown in mph on a UK road, `mph`): a white disc with a red ring on a
## post, facing back along the road at the riders coming. `xf` has its origin at the post's foot and +z towards them.
static func limit_sign(kmh: float, mph: bool, xf: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "LimitSign"
	root.transform = xf
	var a := new_arrays()
	box(a, Transform3D(Basis(), Vector3.ZERO), Vector3(0.1, 2.5, 0.1), Color(0.45, 0.46, 0.48))
	var sides := 24
	var centre := Vector3(0.0, 2.55, 0.06)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		_tri(a, centre, centre + Vector3(cos(a0), sin(a0), 0.0) * 0.52, centre + Vector3(cos(a1), sin(a1), 0.0) * 0.52, Color(0.8, 0.08, 0.06))
		_tri(a, centre + Vector3(0, 0, 0.012), centre + Vector3(cos(a0), sin(a0), 0.012) * 0.38,
			centre + Vector3(cos(a1), sin(a1), 0.012) * 0.38, Color(0.97, 0.97, 0.95))
	var mi := MeshInstance3D.new()
	mi.mesh = to_mesh(a)
	root.add_child(mi)
	var label := Label3D.new()
	label.text = str(roundi(kmh / 1.609344)) if mph else str(roundi(kmh))
	label.font_size = 96
	label.pixel_size = 0.006
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = Vector3(0.0, 2.55, 0.03)
	root.add_child(label)
	return root


# ---------------------------------------------------------------------------- sites

## A fuel station by the road: a forecourt beside the road at `xf` (its origin on the road's
## edge, local +x away from the road and -z along it), a canopy over two islands of pumps (each
## pump a node in group "fuel_pump"), and the kiosk behind. `site` is the route's site record.
static func fuel_station(site: Dictionary, xf: Transform3D, surf: String) -> Node3D:
	var root := Node3D.new()
	root.name = "FuelStation"
	root.transform = xf
	root.set_meta("site", site)
	var a := new_arrays()
	var len := 44.0
	var depth := 24.0
	# The forecourt: a concrete slab level with the road, with its own collision.
	var slab := Color(0.55, 0.55, 0.53)
	_quad(a, Vector3(0.6, 0.03, len * 0.5), Vector3(depth, 0.03, len * 0.5), Vector3(depth, 0.03, -len * 0.5),
		Vector3(0.6, 0.03, -len * 0.5), slab)
	box(a, Transform3D(Basis(), Vector3(depth * 0.5 + 0.3, -0.6, 0)), Vector3(depth - 0.6, 0.62, len), slab.darkened(0.2), false)
	# The canopy on four posts, its fascia in the station's colours.
	var cx := 9.5
	var canopy_y := 5.2
	for px: float in [cx - 4.5, cx + 4.5]:
		for pz: float in [-7.0, 7.0]:
			box(a, Transform3D(Basis(), Vector3(px, 0.03, pz)), Vector3(0.35, canopy_y, 0.35), Color(0.85, 0.85, 0.85))
	box(a, Transform3D(Basis(), Vector3(cx, canopy_y, 0)), Vector3(11.0, 0.9, 18.0), Color(0.92, 0.92, 0.9))
	box(a, Transform3D(Basis(), Vector3(cx, canopy_y + 0.2, 0)), Vector3(11.1, 0.42, 18.1), Color(0.1, 0.45, 0.25))
	# The kiosk at the back, with a window and a door.
	box(a, Transform3D(Basis(), Vector3(depth - 4.5, 0.03, 0)), Vector3(7.0, 3.4, 12.0), Color(0.88, 0.87, 0.82))
	box(a, Transform3D(Basis(), Vector3(depth - 4.5, 3.43, 0)), Vector3(7.4, 0.3, 12.4), Color(0.1, 0.45, 0.25))
	box(a, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(depth - 8.02, 0.9, -1.5)), Vector3(6.0, 1.6, 0.06), Color(0.18, 0.25, 0.32))
	box(a, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(depth - 8.02, 0.03, 3.0)), Vector3(1.2, 2.2, 0.06), Color(0.2, 0.3, 0.36))
	# A sign on a pole by the road.
	box(a, Transform3D(Basis(), Vector3(2.0, 0.03, -len * 0.5 + 2.0)), Vector3(0.25, 6.0, 0.25), Color(0.7, 0.7, 0.7))
	box(a, Transform3D(Basis(), Vector3(2.0, 5.0, -len * 0.5 + 2.0)), Vector3(0.4, 2.2, 2.2), Color(0.1, 0.45, 0.25))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = to_mesh(a)
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Forecourt"
	body.collision_layer = 1
	body.set_meta("surface", "tarmac")
	var slab_shape := BoxShape3D.new()
	slab_shape.size = Vector3(depth - 0.6, 0.6, len)
	var cs := CollisionShape3D.new()
	cs.shape = slab_shape
	cs.position = Vector3(depth * 0.5 + 0.3, -0.27, 0)
	body.add_child(cs)
	var kiosk := BoxShape3D.new()
	kiosk.size = Vector3(7.0, 3.4, 12.0)
	var ks := CollisionShape3D.new()
	ks.shape = kiosk
	ks.position = Vector3(depth - 4.5, 1.73, 0)
	body.add_child(ks)
	for px: float in [cx - 4.5, cx + 4.5]:
		for pz: float in [-7.0, 7.0]:
			var post := BoxShape3D.new()
			post.size = Vector3(0.35, canopy_y, 0.35)
			var ps := CollisionShape3D.new()
			ps.shape = post
			ps.position = Vector3(px, canopy_y * 0.5, pz)
			body.add_child(ps)
	root.add_child(body)
	# The pumps: two islands of two, along the forecourt under the canopy.
	var n := 0
	for island_z: float in [-3.6, 3.6]:
		var island := new_arrays()
		box(island, Transform3D(Basis(), Vector3(cx, 0.03, island_z)), Vector3(1.4, 0.16, 6.0), Color(0.75, 0.74, 0.7))
		var im := MeshInstance3D.new()
		im.mesh = to_mesh(island)
		root.add_child(im)
		for side: float in [-1.0, 1.0]:
			root.add_child(_pump(Vector3(cx, 0.19, island_z + side * 1.6), n, site))
			n += 1
	var label := Label3D.new()
	label.text = "FUEL"
	label.font_size = 96
	label.pixel_size = 0.012
	label.outline_size = 12
	label.modulate = Color(1, 1, 1)
	label.position = Vector3(cx - 5.6, canopy_y + 0.45, 0)
	label.rotation = Vector3(0, -PI * 0.5, 0)
	root.add_child(label)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, canopy_y - 0.4, 0)
	lamp.omni_range = 16.0
	lamp.light_energy = 0.0
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.add_to_group(Daylight.NIGHT_LIGHTS)
	lamp.set_meta("night_energy", 2.2)
	root.add_child(lamp)
	return root


## One pump: a cabinet with a hose, a node in group "fuel_pump" (meta "station": its site's name).
static func _pump(at: Vector3, index: int, site: Dictionary) -> Node3D:
	var pump := StaticBody3D.new()
	pump.name = "Pump%d" % index
	pump.position = at
	pump.collision_layer = 1
	pump.add_to_group(PUMP_GROUP)
	pump.set_meta("station", str(site.get("name", "Fuel")))
	pump.set_meta("s", float(site.get("s", 0.0)))
	var a := new_arrays()
	box(a, Transform3D(), Vector3(0.9, 1.8, 0.6), Color(0.9, 0.9, 0.88))
	box(a, Transform3D(Basis(), Vector3(0, 1.8, 0)), Vector3(0.95, 0.3, 0.65), Color(0.1, 0.45, 0.25))
	box(a, Transform3D(Basis(), Vector3(0.0, 1.1, 0.31)), Vector3(0.5, 0.35, 0.02), Color(0.08, 0.1, 0.12))
	box(a, Transform3D(Basis(), Vector3(0.38, 0.6, 0.0)), Vector3(0.06, 0.8, 0.06), Color(0.1, 0.1, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = to_mesh(a)
	pump.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.8, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	pump.add_child(cs)
	return pump


## A banner across the road at `xf` (on the centre line, facing along it), `width` wide: the
## start or the destination.
static func banner(text: String, xf: Transform3D, width: float, col: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Banner"
	root.transform = xf
	var a := new_arrays()
	var hw := width * 0.5 + 1.2
	for sx: float in [-hw, hw]:
		box(a, Transform3D(Basis(), Vector3(sx, -0.2, 0)), Vector3(0.3, 5.6, 0.3), Color(0.25, 0.25, 0.27))
	box(a, Transform3D(Basis(), Vector3(0, 4.2, 0)), Vector3(hw * 2.0, 1.2, 0.12), col)
	var mi := MeshInstance3D.new()
	mi.mesh = to_mesh(a)
	root.add_child(mi)
	for face: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = 96
		label.pixel_size = 0.01
		label.outline_size = 8
		label.position = Vector3(0, 4.8, 0.08 * face)
		label.rotation = Vector3(0, 0.0 if face > 0 else PI, 0)
		root.add_child(label)
	return root
