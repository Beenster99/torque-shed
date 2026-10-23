class_name HelmetModel
extends RefCounted
## The rider's helmets as proper models, made here from meshes of their own (RiderGear has the
## helmets on sale, and the shell colours and visors a rider can pick). Five kinds, plus the
## motocross lid:
##   open_classic  a round three-quarter shell, a leather lining, chrome snaps, a chin strap and,
##                 if worn, round goggles on an elastic strap round the back
##   open_touring  a bigger, squarer open face with a drop-down half visor or a bubble visor, and
##                 for some a peak on snaps
##   full_classic  a round full face with a round eyeport, a flip-up shield and chrome side snaps
##   full_modern   an angular full face: a wide eyeport, a jutting chin bar, vents on top, in the
##                 chin and at the back, a small spoiler and visor pivot plates
##   race          longer and sharper still: a big eyeport, an aero spoiler on fins, brow, top and
##                 chin vents, and tear-off posts and a lock tab on the visor
##
## A helmet is built at unit size round its centre, facing -Z, and scaled to the head. The shell
## is a stretched, squared-off sphere swept as columns round it (a, the angle round from the
## front, positive to the rider's right) and rows down it (p, the angle down from the crown). Each
## column runs between its own top and bottom, so the face opening and the eyeport are cut out
## with clean, rounded edges. Inside is the liner, and every cut edge has a rubber (or leather)
## bead. The visor or goggles hang on a HelmetVisor pivot so they can flick up and down.
## Meshes are kept and shared: only the materials change between riders.

const MODELS: Array[String] = ["open_classic", "open_touring", "full_classic", "full_modern", "race"]
const MODEL_NAMES := {"open_classic": "Classic open face", "open_touring": "Touring open face",
	"full_classic": "Classic full face", "full_modern": "Modern full face", "race": "Race", "mx": "Motocross"}

const COLS := 96
const ROWS := 12

## Each model's shell, sizes as fractions of the helmet's radius and angles in degrees:
## rx, ry, rz (front) and rzb (back) stretch the sphere; n squares it off (2 round, more squarer);
## back, side and front are how far down the bottom edge comes at the back, over the ears and
## under the chin; open is the face opening (brow: its top edge, w: half its width round, k: how
## square its corners are); port is the eyeport (c: its middle, h: half its height, w: half its
## width, k: corners); chin is how far the chin bar juts out; thick the shell and liner together.
const SPECS := {
	"open_classic": {"rx": 1.0, "ry": 1.0, "rz": 1.04, "rzb": 1.06, "n": 2.0, "back": 112.0, "side": 124.0, "front": 124.0,
		"open": {"brow": 66.0, "w": 84.0, "k": 3.0}, "thick": 0.15},
	"open_touring": {"rx": 1.03, "ry": 1.0, "rz": 1.07, "rzb": 1.1, "n": 2.3, "back": 114.0, "side": 130.0, "front": 130.0,
		"open": {"brow": 63.0, "w": 86.0, "k": 4.0}, "thick": 0.16},
	"full_classic": {"rx": 1.0, "ry": 1.02, "rz": 1.05, "rzb": 1.06, "n": 2.0, "back": 116.0, "side": 126.0, "front": 134.0,
		"port": {"c": 88.0, "h": 19.0, "w": 47.0, "k": 2.0}, "chin": 0.1, "thick": 0.16},
	"full_modern": {"rx": 1.0, "ry": 1.0, "rz": 1.1, "rzb": 1.1, "n": 2.6, "back": 114.0, "side": 126.0, "front": 136.0,
		"port": {"c": 86.0, "h": 16.0, "w": 58.0, "k": 4.0}, "chin": 0.2, "thick": 0.16},
	"race": {"rx": 0.98, "ry": 1.0, "rz": 1.12, "rzb": 1.2, "n": 2.8, "back": 112.0, "side": 126.0, "front": 138.0,
		"port": {"c": 85.0, "h": 18.0, "w": 64.0, "k": 4.0}, "chin": 0.26, "thick": 0.16},
}
## How far the visor (or goggles) turns up on its pivot, in radians, and how far it sits off the shell.
const VISOR_UP := {"open_classic": 0.85, "open_touring": 0.75, "full_classic": 0.66, "full_modern": 0.62, "race": 0.6}
const VISOR_GAP := 0.045
## Where the head sits in a helmet (its centre, unit size) and its half-sizes.
const HEAD_AT := Vector3(0.0, -0.18, 0.0)
const HEAD_SIZE := Vector3(0.73, 0.82, 0.76)

static var _meshes := {}   # "model|piece" -> Mesh
static var _mats := {}


# ---------------------------------------------------------------------------- building one

## Builds helmet `item_id` (see RiderGear) centred at `c` under `parent`, `r` its radius, facing
## -Z, in the rider's colour `tint` and the choices in `worn` (shell colour, visor, goggles, and
## "peer" for whose visor it follows). Returns the helmet's root node ("Helmet").
static func build(parent: Node3D, c: Vector3, r: float, item_id: String, tint: Color, layers := 1, worn := {}) -> Node3D:
	var model := RiderGear.helmet_model(item_id)
	var on := worn.duplicate()
	on["helmet"] = item_id
	var root := Node3D.new()
	root.name = "Helmet"
	root.position = c
	root.scale = Vector3.ONE * r
	root.set_meta("model", model)
	parent.add_child(root)
	var shell := RiderFigure.material(item_id, tint, "", RiderGear.shell_color(on, tint))
	var trim := RiderFigure.material(item_id, tint, "trim")
	var lens := visor_material(RiderGear.visor_of(on))
	var plain := RiderFigure.material(item_id, tint, "base", RiderGear.shell_color(on, tint))
	if model == "mx":
		_build_mx(root, shell, trim, lens, layers)
		return root
	var m := shell_meshes(model)
	_add(root, m["shell"], shell, Vector3.ZERO, layers).set_name("Shell")
	_add(root, m["liner"], _liner(model), Vector3.ZERO, layers).set_name("Liner")
	_add(root, m["rim"], _mat("leather" if model == "open_classic" else "rubber"), Vector3.ZERO, layers).set_name("Rim")
	var flips := RiderGear.can_flip_item(item_id, on)
	var pivot: HelmetVisor = null
	if flips:
		pivot = HelmetVisor.new()
		pivot.name = "Visor"
		pivot.angle = float(VISOR_UP[model])
		pivot.peer = int(worn.get("peer", -1))
		pivot.up = bool(worn.get("visor_up", false))
		root.add_child(pivot)
	match model:
		"open_classic":
			_dress_open_classic(root, pivot, lens, layers)
		"open_touring":
			_dress_open_touring(root, pivot, item_id, plain, lens, layers)
		_:
			_dress_full(root, pivot, model, shell, trim, lens, layers)
	return root


## The head in a helmet: the face, eyes, brows and nose, centred at `at`, `unit` the helmet's
## radius it was made for. `head` adds the head itself and a neck (a body without one: on a bike).
static func face(parent: Node3D, at: Vector3, unit: float, layers := 1, head := false) -> Node3D:
	var f := Node3D.new()
	f.name = "Face"
	f.position = at
	f.scale = Vector3.ONE * unit
	parent.add_child(f)
	var skin := _mat("skin")
	if head:
		var h := RiderFigure.mesh(f, RiderFigure.sphere(0.5), skin, Vector3.ZERO, layers)
		h.scale = HEAD_SIZE * 2.0
		RiderFigure.limb(f, Vector3(0.0, -0.55, 0.12), Vector3(0.0, -1.15, 0.2), 0.36, skin, layers)
	for side in [-1.0, 1.0]:
		RiderFigure.mesh(f, RiderFigure.sphere(0.06), _mat("eye"), Vector3(0.26 * side, 0.17, -0.67), layers)
		var brow := RiderFigure.box(f, Vector3(0.26 * side, 0.29, -0.66), Vector3(0.2, 0.035, 0.05), _mat("brow"), layers)
		brow.rotation.z = -0.12 * side
	var nose := RiderFigure.mesh(f, RiderFigure.sphere(0.09), skin, Vector3(0.0, 0.02, -0.76), layers)
	nose.scale = Vector3(0.8, 1.3, 1.0)
	RiderFigure.box(f, Vector3(0.0, -0.22, -0.7), Vector3(0.22, 0.03, 0.04), _mat("lip"), layers)
	return f


# ---------------------------------------------------------------------------- the shell's shape

## A point on `model`'s shell at round angle `a` and down angle `p` (radians), unit size.
static func point(s: Dictionary, a: float, p: float) -> Vector3:
	var d := Vector3(sin(p) * sin(a), cos(p), -sin(p) * cos(a))
	var n := float(s["n"])
	if n != 2.0:
		d /= pow(pow(absf(d.x), n) + pow(absf(d.y), n) + pow(absf(d.z), n), 1.0 / n)
	var v := Vector3(d.x * float(s["rx"]), d.y * float(s["ry"]), d.z * float(s["rz"] if d.z < 0.0 else s["rzb"]))
	var chin := float(s.get("chin", 0.0))
	if chin > 0.0:
		# The chin bar juts forward and down under the face.
		var f := smoothstep(deg_to_rad(92.0), deg_to_rad(138.0), p) * pow(maxf(cos(a), 0.0), 1.5)
		v.z -= chin * f
		v.y -= chin * 0.35 * f
	return v


## The outward normal of the shell at (a, p).
static func normal(s: Dictionary, a: float, p: float, out := 1.0) -> Vector3:
	return _normal(func(aa: float, pp: float) -> Vector3: return point(s, aa, pp) * out, a, p)


## The point `out` times as far from the centre as the shell, at (a, p) in degrees.
static func on_shell(model: String, a_deg: float, p_deg: float, out := 1.0) -> Vector3:
	return point(SPECS[model], deg_to_rad(a_deg), deg_to_rad(p_deg)) * out


## How far down the bottom edge comes at round angle `a`: over the ears at the sides, blending
## to the back and the chin.
static func bottom(s: Dictionary, a: float) -> float:
	var c := cos(a)
	var side := deg_to_rad(float(s["side"]))
	return lerpf(side, deg_to_rad(float(s["front"] if c >= 0.0 else s["back"])), c * c)


## How far an opening reaches at `x` (0 its middle, 1 its edge): 1 down to 0, rounder for small `k`.
static func _round(x: float, k: float) -> float:
	return pow(maxf(0.0, 1.0 - pow(minf(x, 1.0), k)), 1.0 / k)


## The shell's pieces and cut edges: {pieces: [{a, p0, p1}], rims: [{pts: [[a, p]], dir}]}.
## An open face is one piece running down to the face opening at the front. A full face is two:
## the crown and sides down to the top of the eyeport, and the chin bar from the bottom of the
## eyeport down; they meet where the eyeport closes at its sides.
static func layout(s: Dictionary) -> Dictionary:
	var da := TAU / COLS
	var mid := COLS / 2
	var cols := []
	var low := []
	for i in COLS + 1:
		cols.append(-PI + da * i)
		low.append(bottom(s, cols[i]))
	var top := []
	top.resize(COLS + 1)
	top.fill(0.0)
	var pieces := []
	var rims := []
	if s.has("open"):
		var o: Dictionary = s["open"]
		var wi := roundi(deg_to_rad(float(o["w"])) / da)
		var brow := deg_to_rad(float(o["brow"]))
		var p1 := []
		for i in COLS + 1:
			var x := absf(i - mid) / float(wi)
			p1.append(low[i] if x >= 1.0 else lerpf(brow, low[i], 1.0 - _round(x, float(o["k"]))))
		pieces.append({"a": cols, "p0": top, "p1": p1})
		rims.append({"pts": _pts(cols, p1, range(COLS + 1)), "dir": 1.0})
		return {"pieces": pieces, "rims": rims}
	var port: Dictionary = s["port"]
	var wi := roundi(deg_to_rad(float(port["w"])) / da)
	var pc := deg_to_rad(float(port["c"]))
	var ph := deg_to_rad(float(port["h"]))
	var up1 := []
	var lo0 := []
	for i in COLS + 1:
		var x := absf(i - mid) / float(wi)
		if x <= 1.0:
			var hw := _round(x, float(port["k"]))
			up1.append(pc - ph * hw)
			lo0.append(pc + ph * hw)
		else:
			up1.append(low[i])
			lo0.append(low[i])
	pieces.append({"a": cols, "p0": top, "p1": up1})
	var chin := range(mid - wi - 1, mid + wi + 2)
	pieces.append({"a": _pick(cols, chin), "p0": _pick(lo0, chin), "p1": _pick(low, chin)})
	var port_cols := range(mid - wi, mid + wi + 1)
	rims.append({"pts": _pts(cols, up1, port_cols), "dir": 1.0})
	rims.append({"pts": _pts(cols, lo0, port_cols), "dir": -1.0})
	rims.append({"pts": _pts(cols, low, chin), "dir": 1.0})
	var back := range(mid + wi + 1, COLS + 1) + range(1, mid - wi)
	rims.append({"pts": _pts(cols, low, back), "dir": 1.0})
	return {"pieces": pieces, "rims": rims}


static func _pick(arr: Array, idx: Array) -> Array:
	return idx.map(func(i): return arr[i])


static func _pts(cols: Array, ps: Array, idx: Array) -> Array:
	return idx.map(func(i): return [cols[i], ps[i]])


## The shell, liner and edge meshes of `model`, made once and kept: {shell, liner, rim}.
static func shell_meshes(model: String) -> Dictionary:
	if _meshes.has(model):
		return _meshes[model]
	var s: Dictionary = SPECS[model]
	var th := float(s["thick"])
	var lay := layout(s)
	var outer := _new_data()
	var inner := _new_data()
	var f_out := func(a: float, p: float) -> Vector3: return point(s, a, p)
	var f_in := func(a: float, p: float) -> Vector3: return point(s, a, p) * (1.0 - th)
	for piece in lay["pieces"]:
		_sweep(outer, f_out, piece["a"], piece["p0"], piece["p1"], ROWS, false)
		_sweep(inner, f_in, piece["a"], piece["p0"], piece["p1"], ROWS, true)
	var rim := _new_data()
	for edge in lay["rims"]:
		_bead(rim, s, edge["pts"], float(edge["dir"]), th)
	_meshes[model] = {"shell": _finish(outer), "liner": _finish(inner), "rim": _finish(rim), "layout": lay}
	return _meshes[model]


# ---------------------------------------------------------------------------- mesh making

static func _new_data() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}


static func _finish(d: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["v"]
	arrays[Mesh.ARRAY_NORMAL] = d["n"]
	arrays[Mesh.ARRAY_TEX_UV] = d["uv"]
	arrays[Mesh.ARRAY_INDEX] = d["i"]
	var m := ArrayMesh.new()
	if not (d["i"] as PackedInt32Array).is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The normal of surface `f` (a function of a and p) at (a, p), pointing away from the centre.
static func _normal(f: Callable, a: float, p: float) -> Vector3:
	var e := 0.002
	var pa: Vector3 = f.call(a + e, p) - f.call(a - e, p)
	var pp: Vector3 = f.call(a, minf(p + e, PI)) - f.call(a, maxf(p - e, 0.0))
	var n := pa.cross(pp)
	var at: Vector3 = f.call(a, p)
	if n.length() < 1e-7:
		return at.normalized() if at.length() > 1e-6 else Vector3.UP
	n = n.normalized()
	return -n if n.dot(at) < 0.0 else n


## A triangle facing along `want` (Godot draws clockwise faces as the front).
static func _tri(d: Dictionary, i0: int, i1: int, i2: int, want: Vector3) -> void:
	var v: PackedVector3Array = d["v"]
	var g := (v[i1] - v[i0]).cross(v[i2] - v[i0])
	if g.dot(want) > 0.0:
		d["i"].append_array([i0, i2, i1])
	else:
		d["i"].append_array([i0, i1, i2])


## Sweeps surface `f` over columns `cols` (round angles), each from p0 to p1, in `rows` rows,
## into `d`. `inward` turns it to face the centre (the liner).
static func _sweep(d: Dictionary, f: Callable, cols: Array, p0: Array, p1: Array, rows: int, inward: bool) -> void:
	var start: int = (d["v"] as PackedVector3Array).size()
	var nc := cols.size()
	for i in nc:
		var a: float = cols[i]
		for j in rows + 1:
			var p := lerpf(float(p0[i]), float(p1[i]), float(j) / rows)
			var n := _normal(f, a, p)
			d["v"].append(f.call(a, p))
			d["n"].append(-n if inward else n)
			d["uv"].append(Vector2((a + PI) / TAU, p / PI))
	for i in nc - 1:
		for j in rows:
			var a0 := start + i * (rows + 1) + j
			var b0 := a0 + rows + 1
			var want: Vector3 = d["n"][a0] + d["n"][b0 + 1]
			_tri(d, a0, b0, b0 + 1, want)
			_tri(d, a0, b0 + 1, a0 + 1, want)


## The bead round a cut edge: from the outside of the shell, rolled over, to the liner.
static func _bead(d: Dictionary, s: Dictionary, pts: Array, dir: float, th: float) -> void:
	var start: int = (d["v"] as PackedVector3Array).size()
	for pt in pts:
		var a: float = pt[0]
		var p: float = pt[1]
		var o := point(s, a, p)
		var n := normal(s, a, p)
		var t := (point(s, a, clampf(p + dir * 0.01, 0.0, PI)) - o).normalized()
		var lip := o + n * 0.012
		var mid := o * (1.0 - th * 0.5) + t * th * 0.42
		var inner := o * (1.0 - th)
		for row in [[lip, (n + t * 0.3).normalized()], [o + t * th * 0.25, (n + t).normalized()], [mid, t],
				[inner + t * th * 0.12, (t - n).normalized()], [inner, -n]]:
			d["v"].append(row[0])
			d["n"].append(row[1])
			d["uv"].append(Vector2((a + PI) / TAU, p / PI))
	for k in pts.size() - 1:
		for j in 4:
			var a0 := start + k * 5 + j
			var b0 := a0 + 5
			var want: Vector3 = d["n"][a0] + d["n"][b0 + 1]
			_tri(d, a0, b0, b0 + 1, want)
			_tri(d, a0, b0 + 1, a0 + 1, want)


## A visor, shield or band: surface `f` over round angles `cols` (radians), each column from
## p0 to p1, made once as `key` and kept.
static func _patch(key: String, f: Callable, cols: Array, p0: Array, p1: Array, rows := 10, flip := false) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var d := _new_data()
	_sweep(d, f, cols, p0, p1, rows, flip)
	_meshes[key] = _finish(d)
	return _meshes[key]


static func _span(from_deg: float, to_deg: float, step_deg := 2.5) -> Array:
	var out := []
	var n := maxi(1, ceili((to_deg - from_deg) / step_deg))
	for i in n + 1:
		out.append(deg_to_rad(lerpf(from_deg, to_deg, float(i) / n)))
	return out


# ---------------------------------------------------------------------------- the bits on each kind

## A mesh under `parent` at `pos`.
static func _add(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, layers: int) -> MeshInstance3D:
	return RiderFigure.mesh(parent, m, mat, pos, layers)


## A box sat on the shell at (a, p) in degrees: `size` across, out of and down the shell, its
## base sunk a touch into it, turned `tilt` radians about its across axis.
static func _stud(parent: Node3D, model: String, a_deg: float, p_deg: float, size: Vector3, mat: Material, layers: int,
		out := 0.0, tilt := 0.0, prism := false) -> MeshInstance3D:
	var s: Dictionary = SPECS[model]
	var a := deg_to_rad(a_deg)
	var p := deg_to_rad(p_deg)
	var at := point(s, a, p)
	var n := normal(s, a, p)
	var down := (point(s, a, p + 0.01) - at).normalized()
	var across := n.cross(down).normalized()
	down = across.cross(n).normalized()
	var m: Mesh
	if prism:
		var pr := PrismMesh.new()
		pr.left_to_right = 1.0
		pr.size = Vector3(size.z, size.y, size.x)
		m = pr
	else:
		var b := BoxMesh.new()
		b.size = size
		m = b
	var mi := _add(parent, m, mat, at + n * (size.y * 0.5 - 0.01 + out), layers)
	var basis := Basis(across, n, down) * Basis(Vector3.RIGHT, tilt)
	if prism:
		basis = basis * Basis(Vector3.UP, PI * 0.5)
	mi.basis = basis
	return mi


## A round stud (a snap, pivot or tear-off post): a short cylinder standing out of the shell.
static func _post(parent: Node3D, at: Vector3, out_dir: Vector3, radius: float, length: float, mat: Material, layers: int) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 16
	c.rings = 1
	var mi := _add(parent, c, mat, at + out_dir.normalized() * length * 0.5, layers)
	mi.basis = RiderFigure.basis_along(out_dir)
	return mi


## A chrome dome (a press stud) on the shell at (a, p) in degrees.
static func _snap(parent: Node3D, model: String, a_deg: float, p_deg: float, radius: float, layers: int) -> void:
	var at := on_shell(model, a_deg, p_deg)
	var n := normal(SPECS[model], deg_to_rad(a_deg), deg_to_rad(p_deg))
	var dome := _add(parent, RiderFigure.sphere(radius), _mat("chrome"), at + n * radius * 0.2, layers)
	dome.basis = RiderFigure.basis_along(n) * Basis.from_scale(Vector3(1.0, 0.45, 1.0))


## Classic open face: snaps over the brow, a chin strap and, if worn, goggles that push up onto
## the shell.
static func _dress_open_classic(root: Node3D, pivot: HelmetVisor, lens: Material, layers: int) -> void:
	var model := "open_classic"
	var brow := float(SPECS[model]["open"]["brow"])
	for a in [-38.0, 0.0, 38.0]:
		_snap(root, model, a, brow - 9.0, 0.045, layers)
	# The chin strap: from inside the shell over each jaw, round under the chin, a D-ring on one side.
	var strap := _mat("strap")
	var under := HEAD_AT + Vector3(0.0, -0.86, -0.3)
	for side in [-1.0, 1.0]:
		var from := on_shell(model, 96.0 * side, 116.0, 0.86)
		var jaw := HEAD_AT + Vector3(0.62 * side, -0.62, -0.1)
		RiderFigure.tube(root, from, jaw, 0.03, strap, layers)
		RiderFigure.tube(root, jaw, under, 0.03, strap, layers)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.055
	var d := _add(root, ring, _mat("chrome"), HEAD_AT + Vector3(0.45, -0.8, -0.24), layers)
	d.rotation = Vector3(0.0, 0.0, PI * 0.5)
	if pivot == null:
		return
	# Goggles: the elastic strap round the back stays put; the frames and lenses push up.
	var s: Dictionary = SPECS[model]
	var band := _patch("goggle_band", func(a: float, p: float) -> Vector3: return point(s, a, p) * 1.025,
		_span(88.0, 272.0, 4.0), _fill(47, deg_to_rad(84.0)), _fill(47, deg_to_rad(95.0)), 2)
	_add(root, band, _mat("strap"), Vector3.ZERO, layers).set_name("GoggleBand")
	pivot.lift = Vector3(0.0, 0.15, -0.13)
	var frame := _mat("chrome")
	for side in [-1.0, 1.0]:
		var at := Vector3(0.3 * side, -0.01, -0.9)
		var rim := TorusMesh.new()
		rim.inner_radius = 0.17
		rim.outer_radius = 0.23
		rim.rings = 24
		var r := _add(pivot, rim, frame, at, layers)
		r.rotation.x = PI * 0.5
		var cup := CylinderMesh.new()
		cup.top_radius = 0.2
		cup.bottom_radius = 0.17
		cup.height = 0.12
		var cmi := _add(pivot, cup, _mat("leather"), at + Vector3(0.0, 0.0, 0.07), layers)
		cmi.rotation.x = PI * 0.5
		var glass := CylinderMesh.new()
		glass.top_radius = 0.18
		glass.bottom_radius = 0.18
		glass.height = 0.012
		var g := _add(pivot, glass, lens, at + Vector3(0.0, 0.0, -0.01), layers)
		g.rotation.x = PI * 0.5
		g.name = "Lens"
		# The strap from the frame back to the band over the ear.
		RiderFigure.tube(pivot, at + Vector3(0.21 * side, 0.0, 0.02), on_shell(model, 88.0 * side, 89.5, 1.03), 0.035, _mat("strap"), layers)
	RiderFigure.tube(pivot, Vector3(-0.1, 0.0, -0.95), Vector3(0.1, 0.0, -0.95), 0.03, frame, layers)


## Touring open face: a half visor or a bubble on pivots by the temples, and a peak on snaps for some.
static func _dress_open_touring(root: Node3D, pivot: HelmetVisor, item_id: String, plain: Material, lens: Material,
		layers: int) -> void:
	var model := "open_touring"
	var s: Dictionary = SPECS[model]
	var item := RiderGear.get_item(item_id)
	var bubble := str(item.get("touring_visor", "half")) == "bubble"
	var brow := float(s["open"]["brow"])
	var pin := 82.0   # the pivots, down from the crown, over the temples
	var pin_at := point(s, PI * 0.5, deg_to_rad(pin))
	for side in [-1.0, 1.0]:
		var at := on_shell(model, 90.0 * side, pin, 1.0)
		_post(root, at, Vector3(side, 0.0, 0.0), 0.12, 0.035, _mat("rubber"), layers)
		_post(root, at, Vector3(side, 0.0, 0.0), 0.05, 0.07, _mat("chrome"), layers)
	if bool(item.get("peak", false)):
		# The peak stands off the shell on three snaps, so the visor slides up under it: a thin
		# slab, its top and underside.
		var cols := _span(-52.0, 52.0, 4.0)
		var root_p := deg_to_rad(brow - 8.0)
		var peak_top := func(a: float, t: float) -> Vector3:
			var fwd := Vector3(sin(a), -0.3, -cos(a)).normalized()
			var reach := 0.04 + 0.36 * sqrt(maxf(0.0, 1.0 - pow(a / deg_to_rad(54.0), 2.0)))
			return point(s, a, root_p) * 1.085 + fwd * reach * t
		var peak_low := func(a: float, t: float) -> Vector3: return peak_top.call(a, t) + Vector3(0.0, -0.035, 0.0)
		var pm := (plain as StandardMaterial3D).duplicate() as StandardMaterial3D
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var zeros := _fill(cols.size(), 0.0)
		var ones := _fill(cols.size(), 1.0)
		_add(root, _patch("touring_peak_top", peak_top, cols, zeros, ones, 3), pm, Vector3.ZERO, layers).set_name("Peak")
		_add(root, _patch("touring_peak_low", peak_low, cols, zeros, ones, 3, true), pm, Vector3.ZERO, layers).set_name("Peak")
		for a in [-34.0, 0.0, 34.0]:
			var at := on_shell(model, a, brow - 8.0, 0.99)
			_post(root, at, normal(s, deg_to_rad(a), root_p), 0.03, 0.1, _mat("chrome"), layers)
	if pivot == null:
		return
	pivot.place(Vector3(0.0, pin_at.y, pin_at.z))
	var low := 122.0 if bubble else 104.0
	var wide := 66.0
	var cols := _span(-92.0, 92.0)
	var p0 := []
	var p1 := []
	for a in cols:
		var t := smoothstep(deg_to_rad(wide), deg_to_rad(86.0), absf(a))
		p0.append(deg_to_rad(lerpf(brow - 4.0, pin - 7.0, t)))
		p1.append(deg_to_rad(lerpf(low, pin + 7.0, t)))
	var off := Vector3(0.0, pin_at.y, pin_at.z)
	var f := func(a: float, p: float) -> Vector3:
		var bulge := 0.0
		if bubble:
			# Rounder and further out the lower it goes, to clear the nose and chin.
			bulge = 0.2 * smoothstep(deg_to_rad(brow), deg_to_rad(low), p) * pow(maxf(cos(a), 0.0), 1.5)
		return point(s, a, p) * (1.0 + VISOR_GAP + bulge) - off
	var v := _add(pivot, _patch("touring_visor_" + ("bubble" if bubble else "half"), f, cols, p0, p1, 14), lens, Vector3.ZERO, layers)
	v.name = "Lens"
	for side in [-1.0, 1.0]:
		_post(pivot, Vector3(1.07 * side * float(s["rx"]), 0.0, 0.0), Vector3(side, 0.0, 0.0), 0.075, 0.03, _mat("rubber"), layers)
	if bubble:
		pivot.angle = 0.85
	# A tab to lift it by.
	var tab := RiderFigure.box(pivot, f.call(deg_to_rad(-22.0), deg_to_rad(low - 1.0)) + Vector3(0.0, -0.02, -0.03), Vector3(0.14, 0.05, 0.03), _mat("rubber"), layers)
	tab.rotation.x = -0.4


## The full faces: the visor on its pivots, then each kind's vents, spoilers and posts.
static func _dress_full(root: Node3D, pivot: HelmetVisor, model: String, shell: Material, trim: Material, lens: Material, layers: int) -> void:
	var s: Dictionary = SPECS[model]
	var port: Dictionary = s["port"]
	var pc := float(port["c"])
	var ph := float(port["h"])
	var pw := float(port["w"])
	var pin_at := point(s, PI * 0.5, deg_to_rad(pc))
	var dark := _mat("rubber")
	var vent := _mat("vent")
	# The pivot plates on the shell, either side.
	for side in [-1.0, 1.0]:
		var at := on_shell(model, 90.0 * side, pc)
		if model == "full_classic":
			_snap(root, model, 90.0 * side, pc, 0.07, layers)
		else:
			_post(root, at, Vector3(side, 0.0, 0.0), 0.16, 0.03, trim if model == "race" else dark, layers)
	if pivot:
		var off := Vector3(0.0, pin_at.y, pin_at.z)
		pivot.place(off)
		var top := pc - ph - 6.0
		var low := pc + ph + (6.0 if model == "full_classic" else 9.0)
		var cols := _span(-92.0, 92.0)
		var p0 := []
		var p1 := []
		for a in cols:
			var t := smoothstep(deg_to_rad(pw + 6.0), deg_to_rad(pw + 22.0), absf(a))
			p0.append(deg_to_rad(lerpf(top, pc - 8.0, t)))
			p1.append(deg_to_rad(lerpf(low, pc + 8.0, t)))
		var f := func(a: float, p: float) -> Vector3: return point(s, a, p) * (1.0 + VISOR_GAP) - off
		var v := _add(pivot, _patch(model + "_visor", f, cols, p0, p1, 12), lens, Vector3.ZERO, layers)
		v.name = "Lens"
		# The visor's own pivot caps, and a tab at the bottom to lift it by.
		for side in [-1.0, 1.0]:
			var cap: Vector3 = f.call(PI * 0.5 * side, deg_to_rad(pc))
			if model == "full_classic":
				var dome := _add(pivot, RiderFigure.sphere(0.07), _mat("chrome"), cap, layers)
				dome.basis = Basis.from_scale(Vector3(0.45, 1.0, 1.0))
			else:
				_post(pivot, cap, Vector3(side, 0.0, 0.0), 0.1, 0.03, dark, layers)
		var tab_at: Vector3 = f.call(deg_to_rad(0.0 if model == "race" else -24.0), deg_to_rad(low - 1.5))
		var tab := RiderFigure.box(pivot, tab_at + Vector3(0.0, -0.025, -0.02), Vector3(0.18 if model == "race" else 0.13, 0.05, 0.035),
			trim if model == "race" else dark, layers)
		tab.rotation.x = -0.5
		tab.name = "Tab"
		if model == "race":
			# Tear-off posts either side of the eyeport, on the visor.
			for side in [-1.0, 1.0]:
				var a := deg_to_rad((pw + 4.0) * side)
				var post_at: Vector3 = f.call(a, deg_to_rad(pc))
				_post(pivot, post_at, normal(s, a, deg_to_rad(pc)), 0.03, 0.06, _mat("chrome"), layers).set_name("TearOff")
	match model:
		"full_classic":
			# A small breath vent low on the chin and a chrome stripe of rivets along the brow.
			_stud(root, model, 0.0, 120.0, Vector3(0.16, 0.035, 0.08), vent, layers)
			for a in [-20.0, 20.0]:
				_snap(root, model, a, 126.0, 0.03, layers)
		"full_modern":
			# Two scoops on top, a chin vent, an exhaust and a small spoiler at the back.
			for side in [-1.0, 1.0]:
				_stud(root, model, 16.0 * side, 30.0, Vector3(0.13, 0.06, 0.24), trim, layers, 0.0, -0.08, true).set_name("Vent")
				_stud(root, model, 16.0 * side, 38.0, Vector3(0.09, 0.025, 0.03), vent, layers, 0.03)
			_stud(root, model, 0.0, 118.0, Vector3(0.24, 0.05, 0.12), vent, layers).set_name("Vent")
			_stud(root, model, 180.0, 96.0, Vector3(0.42, 0.04, 0.08), vent, layers).set_name("Vent")
			_stud(root, model, 180.0, 58.0, Vector3(0.5, 0.07, 0.2), trim, layers, 0.0, 0.25, true).set_name("Spoiler")
		"race":
			# Brow vents over the eyeport, three scoops on top, the chin vent, twin exhausts and
			# the aero spoiler on two fins.
			for side in [-1.0, 1.0]:
				_stud(root, model, 22.0 * side, pc - ph - 13.0, Vector3(0.14, 0.04, 0.07), vent, layers).set_name("Vent")
				_stud(root, model, 180.0 + 22.0 * side, 100.0, Vector3(0.16, 0.04, 0.07), vent, layers).set_name("Vent")
			for a in [-20.0, 0.0, 20.0]:
				_stud(root, model, a, 28.0 if a != 0.0 else 22.0, Vector3(0.1, 0.07, 0.22), trim, layers, 0.0, -0.06, true).set_name("Vent")
			_stud(root, model, 0.0, 122.0, Vector3(0.28, 0.05, 0.14), vent, layers).set_name("Vent")
			for k in 3:
				_stud(root, model, 0.0, 118.0 + k * 4.0, Vector3(0.22, 0.012, 0.012), trim, layers, 0.05)
			# The aero spoiler: a wing in the shell's colour on two fins, its trailing edge up.
			var wing_at := on_shell(model, 180.0, 46.0) + Vector3(0.0, 0.09, 0.12)
			var wing := RiderFigure.box(root, wing_at, Vector3(0.66, 0.06, 0.34), shell, layers)
			wing.rotation.x = -0.22
			wing.name = "Spoiler"
			for side in [-1.0, 1.0]:
				var foot := on_shell(model, 180.0 - 13.0 * side, 54.0, 0.97)
				var top := wing_at + Vector3(0.2 * side, -0.01, -0.02)
				var fin := RiderFigure.box(root, (foot + top) * 0.5, Vector3(0.04, foot.distance_to(top) + 0.06, 0.28), trim, layers)
				fin.basis = RiderFigure.basis_along(top - foot)
				fin.name = "Fin"


## The motocross lid: a long peak, a pointed chin bar and goggles over the eyeport.
static func _build_mx(root: Node3D, shell: Material, trim: Material, lens: Material, layers: int) -> void:
	var s := RiderFigure.mesh(root, RiderFigure.sphere(1.0), shell, Vector3.ZERO, layers)
	s.scale = Vector3(1.0, 1.0, 1.08)
	var peak := RiderFigure.box(root, Vector3(0.0, 0.62, -0.85), Vector3(1.2, 0.07, 0.9), shell, layers)
	peak.rotation.x = -0.32
	RiderFigure.box(root, Vector3(0.0, -0.55, -0.82), Vector3(0.75, 0.38, 0.55), trim, layers)
	RiderFigure.box(root, Vector3(0.0, 0.12, -0.95), Vector3(1.05, 0.32, 0.18), lens, layers)
	RiderFigure.tube(root, Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.18, 0.0), 1.03, trim, layers)


static func _fill(n: int, v: float) -> Array:
	var a := []
	a.resize(n)
	a.fill(v)
	return a


# ---------------------------------------------------------------------------- materials

## The material of visor (or goggle lens) `id` (see RiderGear.VISORS): tinted see-through
## plastic, or a mirror-finish iridium coat that reflects the world in its colour.
static func visor_material(id: String) -> StandardMaterial3D:
	var key := "visor|" + id
	if _mats.has(key):
		return _mats[key]
	var v: Dictionary = RiderGear.VISORS.get(id, RiderGear.VISORS["light"])
	var c: Color = v["color"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c, float(v["alpha"]))
	if bool(v.get("mirror", false)):
		m.metallic = 1.0
		m.metallic_specular = 1.0
		m.roughness = 0.04
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.9
	else:
		m.metallic = 0.2
		m.metallic_specular = 0.9
		m.roughness = 0.03
	m.set_meta("visor", id)
	_mats[key] = m
	return m


## The liner inside: tan leather in the classic open face, black cloth in the rest.
static func _liner(model: String) -> StandardMaterial3D:
	return _mat("leather" if model == "open_classic" else "liner")


static func _mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.75
		"vent":
			m.albedo_color = Color(0.02, 0.02, 0.025)
			m.roughness = 0.6
			m.metallic = 0.3
		"liner":
			m.albedo_color = Color(0.12, 0.12, 0.13)
			m.roughness = 0.95
		"leather":
			m.albedo_color = Color(0.4, 0.24, 0.12)
			m.roughness = 0.5
			m.clearcoat_enabled = true
			m.clearcoat = 0.2
		"strap":
			m.albedo_color = Color(0.08, 0.07, 0.065)
			m.roughness = 0.7
		"chrome":
			m.albedo_color = Color(0.85, 0.86, 0.88)
			m.metallic = 1.0
			m.roughness = 0.12
		"skin":
			m.albedo_color = RiderFigure.SKIN
			m.roughness = 0.6
		"eye":
			m.albedo_color = Color(0.08, 0.06, 0.05)
			m.roughness = 0.2
		"brow":
			m.albedo_color = Color(0.25, 0.16, 0.1)
			m.roughness = 0.9
		"lip":
			m.albedo_color = Color(0.6, 0.35, 0.32)
			m.roughness = 0.6
	_mats[kind] = m
	return m
