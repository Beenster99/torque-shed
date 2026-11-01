extends RefCounted
## Geometry for the railways (rail.gd, rail_train.gd) built up on a worker as plain arrays, a surface a material, and made
## a mesh on the main thread. Every face is vertex coloured and drawn from both sides.

## The surfaces, in the order a mesh holds them: matte (ballast, stone, platforms), steel (rails, wires, girders), glow
## (lamps: lit at night), window (a train's windows: lit at night), lamp_red (a crossing's lit lamps), tail (a train's
## red tail and marker lamps: always on, brighter at night).
const SURFACES := ["matte", "steel", "glow", "window", "lamp_red", "tail"]

static var _mats := {}

var surfs := {}   # name -> [PackedVector3Array verts, PackedVector3Array normals, PackedColorArray]


func _surf(name: String) -> Array:
	if not surfs.has(name):
		surfs[name] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	return surfs[name]


## A triangle a b c, one colour (`_flip` is kept for the callers' sake: both sides are drawn and lit).
func tri(name: String, a: Vector3, b: Vector3, c: Vector3, col: Color, _flip := false) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		return
	# (Godot's front face winds clockwise, its normal the other way to the corners' cross)
	nrm = -nrm.normalized()
	var s := _surf(name)
	# (called on the packed arrays where they are: a cast would copy them)
	s[0].append_array([a, b, c])
	s[1].append_array([nrm, nrm, nrm])
	s[2].append_array([col, col, col])


## A quad a b c d, its corners in order round it.
func quad(name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip := false) -> void:
	tri(name, a, b, c, col, flip)
	tri(name, a, c, d, col, flip)


## A box round `at`, `half` its half sizes on x, y and z, or along axes `ax`, `ay`, `az` (half lengths) when given.
func box(name: String, at: Vector3, half: Vector3, col: Color, ax := Vector3.ZERO, ay := Vector3.ZERO, az := Vector3.ZERO) -> void:
	if ax == Vector3.ZERO:
		ax = Vector3(half.x, 0.0, 0.0)
		ay = Vector3(0.0, half.y, 0.0)
		az = Vector3(0.0, 0.0, half.z)
	var c := [at - ax - ay - az, at + ax - ay - az, at + ax + ay - az, at - ax + ay - az,
		at - ax - ay + az, at + ax - ay + az, at + ax + ay + az, at - ax + ay + az]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		quad(name, c[f[0]], c[f[1]], c[f[2]], c[f[3]], col)


## How many vertices it holds.
func size() -> int:
	var n := 0
	for s: Array in surfs.values():
		n += (s[0] as PackedVector3Array).size()
	return n


func mesh() -> ArrayMesh:
	return mesh_of(surfs)


## An ArrayMesh of surfaces `s` (a Geo's surfs), a material each; null for nothing.
static func mesh_of(s: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	for name: String in SURFACES:
		if not s.has(name) or (s[name][0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s[name][0]
		arr[Mesh.ARRAY_NORMAL] = s[name][1]
		arr[Mesh.ARRAY_COLOR] = s[name][2]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, material(name))
	return m if m.get_surface_count() > 0 else null


## The material of surface `surf` (shared by every block: night() sets how brightly the lit ones glow).
static func material(surf: String) -> StandardMaterial3D:
	if _mats.has(surf):
		return _mats[surf]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match surf:
		"steel":
			m.metallic = 0.6
			m.roughness = 0.45
		"glow":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.86, 0.62)
			m.emission_energy_multiplier = 0.0
		"window":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.9, 0.7)
			m.emission_energy_multiplier = 0.0
			m.roughness = 0.2
		"lamp_red":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.12, 0.05)
			m.emission_energy_multiplier = 4.0
		"tail":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 0.6
	_mats[surf] = m
	return m


## Lights the lamps and the trains' windows by how dark it is (`lamps`, 0 by day to 1 at night: Daylight.lamps).
static func night(lamps: float) -> void:
	material("glow").emission_energy_multiplier = 0.15 + lamps * 3.0
	material("window").emission_energy_multiplier = lamps * 1.6
	material("tail").emission_energy_multiplier = 0.6 + lamps * 2.4


## A round bar (a wheel, an axle, a pipe) of radius `r` round `at`, `half` its half length along `axis` (x, y or z: a
## unit axis), `sides` faces round it, both ends capped.
func disc(name: String, at: Vector3, axis: Vector3, r: float, half: float, col: Color, sides := 8) -> void:
	var u := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	u = (u - axis * u.dot(axis)).normalized()
	var v := axis.cross(u)
	var a := at - axis * half
	var b := at + axis * half
	for k in sides:
		var t0 := TAU * k / sides
		var t1 := TAU * (k + 1) / sides
		var p0 := (u * cos(t0) + v * sin(t0)) * r
		var p1 := (u * cos(t1) + v * sin(t1)) * r
		quad(name, a + p0, a + p1, b + p1, b + p0, col)
		tri(name, a, a + p1, a + p0, col)
		tri(name, b, b + p0, b + p1, col)
