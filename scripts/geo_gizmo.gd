class_name GeoGizmo
extends Node3D
## The handles of geometry mode, drawn over the selected part the way Blender, Unreal or 3ds Max
## draw them: three arrows to move it along X, Y and Z, three rings to turn it about them, and
## three boxes on stalks to stretch it along its own axes, with a box in the middle to size it
## all over. Also the maths behind dragging them, kept static so it can be tested on its own.
##
## A part's fit is an offset: {p: Vector3 metres, r: Vector3 Euler degrees, s: Vector3 scale},
## applied about the part's middle in the bike model's own axes (X right, Y up, Z back).

enum Mode { MOVE, ROTATE, SCALE }
const MODE_NAMES := ["Move", "Rotate", "Scale"]
const AXIS_NAMES := ["X", "Y", "Z"]
const AXIS_COLORS := [Color(0.95, 0.25, 0.25), Color(0.35, 0.9, 0.3), Color(0.3, 0.55, 1.0)]
const HOVER_COLOR := Color(1.0, 0.85, 0.2)
const UNIFORM := 3            # the middle box in scale mode: every axis at once
const SNAP_MOVE := 0.01       # Ctrl held: 1 cm steps
const SNAP_ROT := 5.0         # 5 degree steps
const SNAP_SCALE := 0.05      # 5% steps
const MAX_MOVE := 1.5         # metres a part may be moved from where it was drawn
const MIN_SCALE := 0.1
const MAX_SCALE := 4.0
const ARM := 1.0              # handle length, before the gizmo is sized to the camera distance
const RING := 0.8
const PICK_PX := 12.0         # how close the mouse must be to a handle, in pixels
const SCREEN_SIZE := 0.16     # the gizmo's size as a fraction of its distance from the camera

var mode := Mode.MOVE
var hover := -1                 # the handle under the mouse (0..2 axes, 3 the middle box), or -1
var part_basis := Basis()       # the part's own turned axes, for the scale handles
var _roots := []                # per mode: Node3D holding its handles
var _mats := []                 # per handle index: its material, re-coloured on hover


func _init() -> void:
	name = "GeoGizmo"
	for i in 4:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.render_priority = 100
		m.albedo_color = AXIS_COLORS[i] if i < 3 else Color(0.92, 0.92, 0.95)
		_mats.append(m)
	for md in 3:
		var root := Node3D.new()
		root.name = MODE_NAMES[md]
		add_child(root)
		_roots.append(root)
	for axis in 3:
		var turn := axis_basis(axis)
		# Move: an arrow along the axis.
		_mesh(_roots[Mode.MOVE], _cyl(0.025, ARM * 0.8), turn, turn * Vector3.UP * ARM * 0.4, axis)
		_mesh(_roots[Mode.MOVE], _cyl(0.07, ARM * 0.22, 0.0), turn, turn * Vector3.UP * ARM * 0.89, axis)
		# Rotate: a ring round the axis.
		var torus := TorusMesh.new()
		torus.inner_radius = RING - 0.02
		torus.outer_radius = RING + 0.02
		torus.rings = 48
		torus.ring_segments = 6
		_mesh(_roots[Mode.ROTATE], torus, turn, Vector3.ZERO, axis)
		# Scale: a stalk with a box on its end.
		_mesh(_roots[Mode.SCALE], _cyl(0.02, ARM * 0.85), turn, turn * Vector3.UP * ARM * 0.425, axis)
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.13
		_mesh(_roots[Mode.SCALE], cube, turn, turn * Vector3.UP * ARM * 0.9, axis)
	var mid := BoxMesh.new()
	mid.size = Vector3.ONE * 0.16
	_mesh(_roots[Mode.SCALE], mid, Basis(), Vector3.ZERO, UNIFORM)
	set_mode(Mode.MOVE)


func set_mode(m: int) -> void:
	mode = m
	for i in 3:
		(_roots[i] as Node3D).visible = i == m
	set_hover(-1)


func set_hover(h: int) -> void:
	hover = h
	for i in 4:
		var c: Color = AXIS_COLORS[i] if i < 3 else Color(0.92, 0.92, 0.95)
		(_mats[i] as StandardMaterial3D).albedo_color = HOVER_COLOR if i == h else c


## Puts the gizmo on a part: `xf` is where its middle is (world space, with the model's axes),
## `turned` the part's own rotation (for the scale handles), sized to stay the same on screen.
func place(xf: Transform3D, turned: Basis, cam: Camera3D) -> void:
	part_basis = turned
	var dist := maxf(0.3, cam.global_position.distance_to(xf.origin)) if cam else 2.0
	global_transform = Transform3D(xf.basis.orthonormalized().scaled(Vector3.ONE * dist * SCREEN_SIZE), xf.origin)
	(_roots[Mode.SCALE] as Node3D).basis = turned.orthonormalized()


## Which handle is under the mouse at `mouse` (screen pixels), or -1.
func pick(cam: Camera3D, mouse: Vector2) -> int:
	if cam == null or not visible:
		return -1
	var best := -1
	var best_d := PICK_PX
	var o := global_position
	var size := global_basis.get_scale().x
	for axis in 3:
		var dir := axis_dir(axis)
		var d := INF
		match mode:
			Mode.MOVE:
				d = _seg_px(cam, mouse, o, o + dir * ARM * size)
			Mode.ROTATE:
				var a := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
				var b := dir.cross(a)
				var prev := o + a * RING * size
				for i in range(1, 49):
					var t := TAU * i / 48.0
					var pt := o + (a * cos(t) + b * sin(t)) * RING * size
					d = minf(d, _seg_px(cam, mouse, prev, pt))
					prev = pt
			Mode.SCALE:
				var sdir := (global_basis.orthonormalized() * part_basis.orthonormalized()) * unit(axis)
				d = _seg_px(cam, mouse, o + sdir * ARM * size * 0.2, o + sdir * ARM * size * 0.95)
		if d < best_d:
			best_d = d
			best = axis
	if mode == Mode.SCALE and not cam.is_position_behind(o) and cam.unproject_position(o).distance_to(mouse) < PICK_PX * 1.4:
		best = UNIFORM
	return best


## A handle's direction in world space (move and rotate handles follow the model's axes).
func axis_dir(axis: int) -> Vector3:
	return (global_basis.orthonormalized() * unit(axis)).normalized()


## The model axis `axis` (0 X, 1 Y, 2 Z) as a unit vector.
static func unit(axis: int) -> Vector3:
	var v := Vector3.ZERO
	v[axis] = 1.0
	return v


static func _seg_px(cam: Camera3D, mouse: Vector2, a: Vector3, b: Vector3) -> float:
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return INF
	var pa := cam.unproject_position(a)
	var pb := cam.unproject_position(b)
	return Geometry2D.get_closest_point_to_segment(mouse, pa, pb).distance_to(mouse)


## Turns a mesh made along Y to lie along `axis`.
static func axis_basis(axis: int) -> Basis:
	match axis:
		0:
			return Basis(Vector3.BACK, -PI * 0.5)
		2:
			return Basis(Vector3.RIGHT, PI * 0.5)
	return Basis()


func _mesh(parent: Node3D, mesh: Mesh, b: Basis, at: Vector3, handle: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[handle]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, at)
	parent.add_child(mi)


static func _cyl(radius: float, height: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	return c


# ---------------------------------------------------------------------------- offsets

static func identity() -> Dictionary:
	return {"p": Vector3.ZERO, "r": Vector3.ZERO, "s": Vector3.ONE}


## One slot's offset from a bike's geometry, filled out to all three parts.
static func offset_of(geo: Dictionary, slot: String) -> Dictionary:
	var out := identity()
	var o = geo.get(slot, {})
	if o is Dictionary:
		for k in ["p", "r", "s"]:
			if o.get(k) is Vector3:
				out[k] = o[k]
	return out


static func is_identity(off: Dictionary) -> bool:
	var o := offset_of({"x": off}, "x")
	return (o["p"] as Vector3).is_zero_approx() and (o["r"] as Vector3).is_zero_approx() \
		and (o["s"] as Vector3).is_equal_approx(Vector3.ONE)


static func rotation_of(off: Dictionary) -> Basis:
	var r: Vector3 = offset_of({"x": off}, "x")["r"]
	return Basis.from_euler(r * (PI / 180.0))


## The whole offset as a transform in the model's space, about `pivot` (the part's middle).
static func offset_xform(off: Dictionary, pivot: Vector3) -> Transform3D:
	var o := offset_of({"x": off}, "x")
	var b := rotation_of(o) * Basis.from_scale(o["s"])
	return Transform3D(b, pivot + (o["p"] as Vector3)) * Transform3D(Basis(), -pivot)


## Dragging a move arrow `amount` metres along `axis` from `start`. Only that axis changes.
static func moved(start: Dictionary, axis: int, amount: float, snap: bool) -> Dictionary:
	var o := offset_of({"x": start}, "x")
	var p: Vector3 = o["p"]
	var v := p[axis] + amount
	if snap:
		v = snappedf(v, SNAP_MOVE)
	p[axis] = clampf(v, -MAX_MOVE, MAX_MOVE)
	o["p"] = p
	return o


## Dragging a ring `degrees` about the model's `axis`, on top of how the part was turned.
static func rotated(start: Dictionary, axis: int, degrees: float, snap: bool) -> Dictionary:
	var o := offset_of({"x": start}, "x")
	if snap:
		degrees = snappedf(degrees, SNAP_ROT)
	var turn := Basis(unit(axis), deg_to_rad(degrees)) * rotation_of(o)
	var e := turn.get_euler() * (180.0 / PI)
	# Tidy rounding noise so an untouched axis reads exactly 0.
	for i in 3:
		e[i] = snappedf(e[i], 0.001)
		if absf(e[i]) < 0.001:
			e[i] = 0.0
	o["r"] = e
	return o


## Dragging a scale box: `factor` times the size along the part's own `axis` (UNIFORM: all three).
static func scaled(start: Dictionary, axis: int, factor: float, snap: bool) -> Dictionary:
	var o := offset_of({"x": start}, "x")
	var s: Vector3 = o["s"]
	for i in 3:
		if axis == UNIFORM or axis == i:
			var v := s[i] * factor
			if snap:
				v = snappedf(v, SNAP_SCALE)
			s[i] = clampf(v, MIN_SCALE, MAX_SCALE)
	o["s"] = s
	return o


## A bike's geometry made safe to keep: known slots only, sizes and moves in range, and parts
## left as they were dropped.
static func sanitize(geo) -> Dictionary:
	var out := {}
	if not (geo is Dictionary):
		return out
	for slot in geo:
		if not (slot is String) or not PartsDB.SLOTS.has(slot) or not (geo[slot] is Dictionary):
			continue
		var o := offset_of(geo, slot)
		var p: Vector3 = o["p"]
		var r: Vector3 = o["r"]
		var s: Vector3 = o["s"]
		if not (p.is_finite() and r.is_finite() and s.is_finite()):
			continue
		p = p.clamp(Vector3.ONE * -MAX_MOVE, Vector3.ONE * MAX_MOVE)
		for i in 3:
			r[i] = wrapf(r[i], -180.0, 180.0)
		s = s.clamp(Vector3.ONE * MIN_SCALE, Vector3.ONE * MAX_SCALE)
		var clean := {"p": p, "r": r, "s": s}
		if not is_identity(clean):
			out[slot] = clean
	return out


# ---------------------------------------------------------------------------- dragging

## How far along the line `origin + t * dir` the mouse ray (`ray_o`, `ray_d`) passes closest.
static func line_param(origin: Vector3, dir: Vector3, ray_o: Vector3, ray_d: Vector3) -> float:
	var d := dir.normalized()
	var r := ray_d.normalized()
	var w := origin - ray_o
	var b := d.dot(r)
	var denom := 1.0 - b * b
	if denom < 1e-6:
		return 0.0   # looking straight down the axis: no sensible drag
	return (b * r.dot(w) - d.dot(w)) / denom


## Where the mouse ray meets the plane through `center` square to `axis`, or null.
static func plane_point(center: Vector3, axis: Vector3, ray_o: Vector3, ray_d: Vector3):
	return Plane(axis.normalized(), center).intersects_ray(ray_o, ray_d)


## The angle in degrees from `a` to `b`, turning about `axis`.
static func angle_about(a: Vector3, b: Vector3, axis: Vector3) -> float:
	return rad_to_deg(a.signed_angle_to(b, axis.normalized()))
