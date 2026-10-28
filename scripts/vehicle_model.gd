class_name VehicleModel
extends RefCounted
## The road traffic's cars, vans, lorries and coaches (see TrafficVehicle), built in code the way
## the recovery truck is (CarModel): side-view outlines pushed out across the body with bevelled
## edges and real wheel arch cut-outs, a ShapeKit loft for each car's glasshouse in see-through
## tinted glass with the roof, pillars and window surrounds laid over it, then the bumpers, lamps,
## grilles, mirrors, handles, shut lines, plates and an interior to see through the windows.
##
## Kept cheap for a dozen on screen: a kind's meshes are made once (per trim) and shared by every
## vehicle of that kind. Everything that doesn't move is merged into one mesh with a surface per
## material, and the materials are shared too: the black plastics, tyres and cabin are one
## vertex-coloured material, the chrome and alloys another, the glass, and every lamp lens one
## shader whose per-vehicle "instance uniforms" light the head, tail, brake, indicator and marker
## lamps (so lighting one vehicle's brake lamps doesn't need a material of its own). Only the paint
## is per vehicle, a cached material per colour set on the paint surfaces. A far mesh of each kind
## has the wheels baked in and no cabin or small details: a handful of draw calls.
##
## Vehicle axes: forward -Z, up +Y, right +X, origin on the ground under the middle (as Car).

const KINDS: Array[String] = ["hatchback", "saloon", "estate", "suv", "van", "lorry", "coach", "police", "supercar"]
## What each is, for the traffic: length, half width, height, wheel radius, the axles (z, the
## first steers), whether the back axle has twin tyres, and how many trims it comes in.
const SPECS := {
	"hatchback": {"len": 4.06, "w": 0.87, "h": 1.46, "r": 0.31, "tw": 0.195, "axles": [-1.3, 1.24], "dual": false, "trims": 3},
	"saloon": {"len": 4.74, "w": 0.9, "h": 1.46, "r": 0.32, "tw": 0.215, "axles": [-1.42, 1.4], "dual": false, "trims": 3},
	"estate": {"len": 4.74, "w": 0.9, "h": 1.47, "r": 0.32, "tw": 0.215, "axles": [-1.42, 1.4], "dual": false, "trims": 3},
	"suv": {"len": 4.64, "w": 0.94, "h": 1.72, "r": 0.37, "tw": 0.235, "axles": [-1.4, 1.38], "dual": false, "trims": 3},
	"van": {"len": 5.34, "w": 1.0, "h": 2.3, "r": 0.34, "tw": 0.215, "axles": [-1.78, 1.62], "dual": false, "trims": 3},
	"lorry": {"len": 8.6, "w": 1.25, "h": 3.8, "r": 0.5, "tw": 0.28, "axles": [-3.3, 2.2], "dual": true, "trims": 3},
	"coach": {"len": 12.1, "w": 1.27, "h": 3.45, "r": 0.5, "tw": 0.3, "axles": [-3.45, 3.0], "dual": false, "trims": 3},
	# The police's estate car (see _police): never in the ordinary traffic's mix.
	"police": {"len": 4.74, "w": 0.9, "h": 1.62, "r": 0.32, "tw": 0.215, "axles": [-1.42, 1.4], "dual": false, "trims": 1},
	# A low, wide mid-engined supercar on big wheels, out now and then on the open road (see
	# TrafficStream.SUPERCAR_CHANCE): never in the ordinary mix.
	"supercar": {"len": 4.6, "w": 0.99, "h": 1.14, "r": 0.34, "tw": 0.29, "axles": [-1.33, 1.37], "dual": false, "trims": 2},
}
## Paint colours each kind comes in (main, and a second colour for liveries and two-tone).
const CAR_PAINTS: Array[Color] = [Color(0.78, 0.79, 0.8), Color(0.08, 0.08, 0.09), Color(0.55, 0.05, 0.06),
	Color(0.1, 0.18, 0.4), Color(0.92, 0.92, 0.9), Color(0.32, 0.34, 0.36), Color(0.12, 0.3, 0.2),
	Color(0.62, 0.52, 0.34), Color(0.2, 0.42, 0.62), Color(0.85, 0.42, 0.08)]
const VAN_PAINTS: Array[Color] = [Color(0.94, 0.94, 0.92), Color(0.94, 0.94, 0.92), Color(0.12, 0.2, 0.42),
	Color(0.62, 0.62, 0.64), Color(0.1, 0.1, 0.11), Color(0.82, 0.12, 0.08)]
## A supercar's paint: racing red, yellow, orange, lime, white, black and a bright blue.
const SUPER_PAINTS: Array[Color] = [Color(0.72, 0.02, 0.02), Color(0.72, 0.02, 0.02), Color(0.98, 0.78, 0.02), Color(0.98, 0.42, 0.02),
	Color(0.5, 0.85, 0.08), Color(0.94, 0.94, 0.92), Color(0.03, 0.03, 0.035), Color(0.05, 0.3, 0.85)]
const LIVERIES: Array[Color] = [Color(0.85, 0.1, 0.08), Color(0.1, 0.25, 0.55), Color(0.1, 0.45, 0.25),
	Color(0.95, 0.65, 0.05), Color(0.45, 0.1, 0.4), Color(0.08, 0.08, 0.1)]

## Lamp channels, carried in each lens vertex's UV.x for LAMP_SHADER.
const CH_HEAD := 0.0
const CH_TAIL := 1.0
const CH_BRAKE := 2.0
const CH_LEFT := 3.0
const CH_RIGHT := 4.0
const CH_MARKER := 5.0      # side and roof markers, the bus's destination board, the dials
const CH_OFF := 6.0         # reversing lamps and reflectors: never lit here
const CH_BLUE_L := 7.0      # a police car's blue lights, the left-hand and right-hand banks
const CH_BLUE_R := 8.0

const LAMP_SHADER := """
shader_type spatial;
// One material for every traffic vehicle's lenses: each vehicle's mesh says which of its lamps
// are lit through these, and each lens says which lamp it is in UV.x (VehicleModel.CH_*).
instance uniform vec4 lamp_a = vec4(0.0);   // head, tail, brake, marker
instance uniform vec2 lamp_ind = vec2(0.0); // left and right indicators
instance uniform vec2 lamp_blue = vec2(0.0); // a police car's blue lights, left and right banks
varying flat float ch;

void vertex() {
	ch = UV.x;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float e = 0.0;
	if (ch < 0.5) { e = lamp_a.x; }
	else if (ch < 1.5) { e = lamp_a.y + lamp_a.z * 0.7; }
	else if (ch < 2.5) { e = lamp_a.z; }
	else if (ch < 3.5) { e = lamp_ind.x; }
	else if (ch < 4.5) { e = lamp_ind.y; }
	else if (ch < 5.5) { e = lamp_a.w; }
	else if (ch < 6.5) { e = 0.0; }
	else if (ch < 7.5) { e = lamp_blue.x; }
	else if (ch < 8.5) { e = lamp_blue.y; }
	ALBEDO = c * 0.5;
	ROUGHNESS = 0.12;
	METALLIC = 0.2;
	SPECULAR = 0.7;
	EMISSION = c * e;
}
"""

# Colours of the shared vertex-coloured materials' pieces.
const BLACK := Color(0.045, 0.045, 0.05)
const GLOSS := Color(0.02, 0.02, 0.025)
const CHROME := Color(0.7, 0.72, 0.75)
const SATIN := Color(0.32, 0.33, 0.35)
const TYRE := Color(0.035, 0.035, 0.035)
const RIM := Color(0.7, 0.72, 0.74)
const RIM_DARK := Color(0.16, 0.16, 0.17)
const UNDER := Color(0.03, 0.03, 0.03)
const TRIM_IN := Color(0.08, 0.08, 0.085)
const SEAT := Color(0.13, 0.13, 0.14)
const HEADLINER := Color(0.5, 0.49, 0.47)
const PLATE := Color(0.95, 0.95, 0.93)
const PLATE_REAR := Color(0.98, 0.8, 0.1)
const GREY := Color(0.42, 0.43, 0.45)
const LENS_WHITE := Color(0.95, 0.95, 0.92)
const LENS_RED := Color(0.85, 0.04, 0.03)
const LENS_AMBER := Color(1.0, 0.55, 0.08)
const LENS_BLUE := Color(0.12, 0.3, 1.0)
## A police car's battenberg checks: high-visibility yellow and blue.
const HIVIS := Color(0.86, 0.9, 0.06)
const POLICE_BLUE := Color(0.04, 0.13, 0.55)

## The shared materials, the paint materials by colour, and the built meshes by "kind:trim".
static var _mats := {}
static var _paints := {}
static var _cache := {}

var kind := ""
var trim := 0
var lo := false             # building the far mesh: no cabin, fewer segments, wheels baked in
var items := []             # [mesh, transform, material key, colour, lamp channel]
var s := {}                 # the kind's SPECS entry
# The glasshouse being built (see _car): [z, half width, height above the belt] rows.
var gl: Array = []
var belt := 1.0
var gn := 4.0
var roof_from := 0.0
var roof_to := 0.0
var a_foot := 0.3
var r_foot := 0.3
const ROOF_EDGE := 0.86


# ---------------------------------------------------------------------------- the public side

## The meshes for a kind in a trim, made the first time they're asked for and shared after:
## {near, far (ArrayMesh), wheel (one wheel, outer face +x), axle (both back wheels, about the
## axle's middle), paint / paint2 (the surface indices of each paint in near, far: [near, far])}.
static func parts(kind_name: String, trim_no: int) -> Dictionary:
	var key := "%s:%d" % [kind_name, trim_no]
	if _cache.has(key):
		return _cache[key]
	var out := {}
	for pass_lo in [false, true]:
		var vm := VehicleModel.new()
		vm.kind = kind_name
		vm.trim = trim_no
		vm.lo = pass_lo
		vm.s = SPECS[kind_name]
		vm._build()
		var merged := vm._merge(vm.items)
		out["far" if pass_lo else "near"] = merged["mesh"]
		out["keys_far" if pass_lo else "keys_near"] = merged["keys"]
		if not pass_lo:
			out["wheel"] = vm._merge(vm._wheel_items(false, false))["mesh"]
			out["axle"] = vm._merge(vm._axle_items(false))["mesh"]
	_cache[key] = out
	return out


## A vehicle's paint (gloss with a clear coat, as the recovery truck's), one material per colour.
static func paint_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _paints.has(key):
		return _paints[key]
	var p := StandardMaterial3D.new()
	p.albedo_color = c
	p.metallic = 0.5
	p.roughness = 0.32
	p.clearcoat_enabled = true
	p.clearcoat = 0.6
	p.clearcoat_roughness = 0.15
	_paints[key] = p
	return p


## The shared materials: "trim" (vertex colours, plastics and rubber), "metal" (vertex colours,
## chrome, alloys and gloss black), "glass" (see-through tint), "dark_glass" (the big vehicles'
## windows, which you can't see into), "lamps" (LAMP_SHADER) and "paint" / "paint2" (stand-ins
## the vehicle sets its own colours over).
static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"trim", "metal":
			var t := StandardMaterial3D.new()
			t.vertex_color_use_as_albedo = true
			t.vertex_color_is_srgb = true
			t.metallic = 0.85 if key == "metal" else 0.0
			t.roughness = 0.24 if key == "metal" else 0.75
			m = t
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.04, 0.05, 0.06, 0.5)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.metallic = 0.6
			g.roughness = 0.03
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"dark_glass":
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(0.05, 0.06, 0.075)
			d.metallic = 0.75
			d.roughness = 0.05
			m = d
		"lamps":
			var sm := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = LAMP_SHADER
			sm.shader = sh
			m = sm
		_:
			m = paint_material(Color(0.6, 0.6, 0.62))
	_mats[key] = m
	return m


## A vehicle's look from its seed: paint, second colour and trim. The same on every machine.
static func look_of(kind_name: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + 7
	if kind_name == "police":
		return {"paint": Color(0.94, 0.94, 0.92), "paint2": POLICE_BLUE, "trim": 0}
	var paints := CAR_PAINTS if kind_name in ["hatchback", "saloon", "estate", "suv"] else (SUPER_PAINTS if kind_name == "supercar" else VAN_PAINTS)
	var paint: Color = paints[rng.randi() % paints.size()]
	var second: Color = LIVERIES[rng.randi() % LIVERIES.size()]
	if kind_name == "coach" and rng.randf() < 0.5:
		paint = Color(0.94, 0.94, 0.92)
	if kind_name == "lorry":
		paint = LIVERIES[rng.randi() % LIVERIES.size()].lightened(0.1)
		second = Color(0.94, 0.94, 0.92) if rng.randf() < 0.6 else VAN_PAINTS[rng.randi() % VAN_PAINTS.size()]
	return {"paint": paint, "paint2": second, "trim": rng.randi() % int(SPECS[kind_name]["trims"])}


# ---------------------------------------------------------------------------- mesh helpers

func _add(mesh: Mesh, key: String, col := Color.WHITE, xf := Transform3D(), ch := CH_OFF) -> void:
	items.append([mesh, xf, key, col, ch])


func _box(size: Vector3, at: Vector3, key: String, col := Color.WHITE, rot := Vector3.ZERO, ch := CH_OFF) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(b, key, col, Transform3D(Basis.from_euler(rot), at), ch)


## A box both sides: `at` is the right-hand one.
func _boxes(size: Vector3, at: Vector3, key: String, col := Color.WHITE, rot := Vector3.ZERO, ch := CH_OFF, ch_left := -1.0) -> void:
	_box(size, at, key, col, rot, ch)
	_box(size, Vector3(-at.x, at.y, at.z), key, col, Vector3(rot.x, -rot.y, -rot.z), ch if ch_left < 0.0 else ch_left)


func _cyl(r: float, h: float, xf: Transform3D, key: String, col: Color, sides := 16) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	_add(c, key, col, xf)


func _prism(profile: PackedVector2Array, x0: float, x1: float, bevel: float, key: String, col := Color.WHITE, ch := CH_OFF) -> void:
	_add(CarModel.prism(profile, x0, x1, bevel), key, col, Transform3D(), ch)


## A prism both sides, x0..x1 on the right and mirrored on the left.
func _prisms(profile: PackedVector2Array, x0: float, x1: float, bevel: float, key: String, col := Color.WHITE, ch := CH_OFF, ch_left := -1.0) -> void:
	_add(CarModel.prism(profile, x0, x1, bevel), key, col, Transform3D(), ch)
	_add(CarModel.prism(profile, -x1, -x0, bevel), key, col, Transform3D(), ch if ch_left < 0.0 else ch_left)


## A flat slab through `pts` (see ShapeKit.plate), and its mirror on the left when `both`.
func _plate(pts: Array, thick: float, key: String, col := Color.WHITE, ch := CH_OFF, both := true, ch_left := -1.0) -> void:
	var p := PackedVector3Array(pts)
	_add(ShapeKit.plate(p, thick), key, col, Transform3D(), ch)
	if both:
		var q := PackedVector3Array()
		for v in pts:
			q.append(Vector3(-(v as Vector3).x, (v as Vector3).y, (v as Vector3).z))
		_add(ShapeKit.plate(q, thick), key, col, Transform3D(), ch if ch_left < 0.0 else ch_left)


## Points from an array of [z, y] pairs.
static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out


## Merges the items into one mesh, a surface per material key, each vertex carrying its item's
## colour and lamp channel. Returns {mesh, keys (the material key of each surface)}.
func _merge(list: Array) -> Dictionary:
	var groups := {}
	var order: Array[String] = []
	for it in list:
		var key: String = it[2]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		var mesh: Mesh = it[0]
		var xf: Transform3D = it[1]
		var col: Color = it[3]
		var uv := Vector2(float(it[4]) + 0.25, 0.0)
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		for si in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var vv := PackedVector3Array()
			var nn := PackedVector3Array()
			vv.resize(v.size())
			nn.resize(v.size())
			for k in v.size():
				vv[k] = xf * v[k]
				nn[k] = (nb * n[k]).normalized()
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ix.is_empty():
				ix.resize(v.size())
				for k in v.size():
					ix[k] = k
			if flip:
				for t in range(0, ix.size(), 3):
					var tmp := ix[t + 1]
					ix[t + 1] = ix[t + 2]
					ix[t + 2] = tmp
			(groups[key] as Array).append([vv, nn, ix, col, uv])
	var out := ArrayMesh.new()
	for key in order:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var idx := PackedInt32Array()
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for piece in groups[key]:
			var base := verts.size()
			verts.append_array(piece[0])
			normals.append_array(piece[1])
			var ix: PackedInt32Array = piece[2]
			var shifted := PackedInt32Array()
			shifted.resize(ix.size())
			for k in ix.size():
				shifted[k] = ix[k] + base
			idx.append_array(shifted)
			var c := PackedColorArray()
			c.resize((piece[0] as PackedVector3Array).size())
			c.fill(piece[3])
			cols.append_array(c)
			var u := PackedVector2Array()
			u.resize(c.size())
			u.fill(piece[4])
			uvs.append_array(u)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, material(key))
	return {"mesh": out, "keys": order}


# ---------------------------------------------------------------------------- the glasshouse

func _glass_at(z: float) -> Vector2:
	if z <= float(gl[0][0]):
		return Vector2(gl[0][1], gl[0][2])
	for i in range(1, gl.size()):
		if z <= float(gl[i][0]):
			var f := inverse_lerp(float(gl[i - 1][0]), float(gl[i][0]), z)
			return Vector2(lerpf(float(gl[i - 1][1]), float(gl[i][1]), f), lerpf(float(gl[i - 1][2]), float(gl[i][2]), f))
	return Vector2(gl[-1][1], gl[-1][2])


## A point on the glasshouse at `z`, `a` round it (0 at the right-hand belt line, PI/2 on top),
## `out` metres proud of it (see CarModel.glass_point).
func _gp(z: float, a: float, out := 0.0) -> Vector3:
	var g := _glass_at(z)
	var e := 2.0 / gn
	var ca := cos(a)
	var sa := maxf(sin(a), 0.0)
	return Vector3(signf(ca) * pow(absf(ca), e) * (g.x + out), belt + pow(sa, e) * (g.y + out), z)


## The angle round the glasshouse of the roof's edge: the A pillar's line down the windscreen,
## the roof's edge, and the line down the back of the rear window.
func _edge(z: float) -> float:
	var f := ROOF_EDGE
	if z < roof_from:
		f = lerpf(a_foot, ROOF_EDGE, clampf(inverse_lerp(float(gl[0][0]), roof_from, z), 0.0, 1.0))
	elif z > roof_to:
		f = lerpf(ROOF_EDGE, r_foot, clampf(inverse_lerp(roof_to, float(gl[-1][0]), z), 0.0, 1.0))
	return asin(clampf(pow(f, gn / 2.0), 0.0, 1.0))


## A band on the glasshouse from z0 to z1 between angles a0(z) and a1(z), `out` proud.
func _band(z0: float, z1: float, a0: Callable, a1: Callable, out: float, key: String, col: Color, steps := 8, across := 4) -> void:
	var rows := []
	for i in steps + 1:
		var z := lerpf(z0, z1, float(i) / steps)
		var row := PackedVector3Array()
		for j in across + 1:
			row.append(_gp(z, lerpf(float(a0.call(z)), float(a1.call(z)), float(j) / across), out))
		rows.append(row)
	_add(CarModel.sheet(rows), key, col)


## The glass, the roof over it, the headliner under it, the pillars and window surrounds, the
## windscreen's black edge, cowl and wipers. `pillars`: [[z0, z1, "gloss" or "paint"], ...] up
## the sides from the belt to the roof's edge.
func _glasshouse(pillars: Array, paint_from_c: float) -> void:
	var sections := []
	for g in gl:
		sections.append({"c": Vector3(0.0, belt, g[0]), "w": g[1], "up": g[2], "down": 0.0, "n": gn})
	_add(ShapeKit.loft(sections, 24 if lo else 44), "glass")
	var roof := []
	var liner := []
	for g in gl:
		if float(g[0]) >= roof_from - 0.001 and float(g[0]) <= roof_to + 0.001:
			roof.append({"c": Vector3(0.0, belt, g[0]), "w": float(g[1]) + 0.006, "up": float(g[2]) + 0.006, "down": 0.0, "n": gn})
			liner.append({"c": Vector3(0.0, belt, g[0]), "w": float(g[1]) - 0.03, "up": float(g[2]) - 0.035, "down": 0.0, "n": gn})
	var ea := _edge((roof_from + roof_to) * 0.5)
	if roof.size() >= 2:
		_add(ShapeKit.loft(roof, 24 if lo else 44, true, ea - 0.02, PI - ea + 0.02), "paint")
		if not lo:
			_add(ShapeKit.loft(liner, 28, true, ea - 0.06, PI - ea + 0.06), "trim", HEADLINER)
	var z0 := float(gl[0][0])
	var zb := float(gl[-1][0])
	var steps := 4 if lo else 10
	for side in [1.0, -1.0]:
		var a := func(z: float, da: float) -> float:
			var v: float = _edge(z) + da
			return v if side > 0.0 else PI - v
		var foot := func(_z: float) -> float: return 0.0 if side > 0.0 else PI
		# The A pillar, painted, along the windscreen's edge; the black surround under the roof's edge.
		_band(z0 + 0.01, roof_from + 0.02, a.bind(-0.07), a.bind(0.09), 0.007, "paint", Color.WHITE, steps, 3)
		_band(roof_from, minf(roof_to, paint_from_c), a.bind(-0.09), a.bind(0.0), 0.005, "metal", GLOSS, steps, 2)
		for p in pillars:
			_band(float(p[0]), float(p[1]), foot, a.bind(-0.02), 0.005, "metal" if p[2] == "gloss" else "paint", GLOSS if p[2] == "gloss" else Color.WHITE, 2, 6)
		# The C (or D) pillar, painted, from behind the last side window to the back.
		if paint_from_c < zb - 0.01:
			_band(paint_from_c, zb, foot, a.bind(0.02), 0.006, "paint", Color.WHITE, 6, 8)
	# The windscreen's black edge at its base, the cowl and the wipers.
	_band(z0 + 0.005, z0 + 0.08, func(z): return _edge(z), func(z): return PI - _edge(z), 0.003, "metal", GLOSS, 2, 12)
	if not lo:
		var cw := float(gl[0][1]) * 2.0 - 0.1
		_box(Vector3(cw, 0.03, 0.1), Vector3(0.0, belt - 0.005, z0 - 0.02), "trim", BLACK)
		for x in [-0.3, 0.32]:
			_box(Vector3(cw * 0.36, 0.012, 0.018), Vector3(x, belt + 0.035, z0 + 0.07), "trim", BLACK, Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(4.0)))


# ---------------------------------------------------------------------------- shared body parts

## Where the nose's (`front`) or the tail's face is at height `y`, from a car's `top` chain.
static func _face(top: Array, y: float, front: bool) -> float:
	var best := 0.0
	var found := false
	for i in top.size() - 1:
		var a: Array = top[i]
		var b: Array = top[i + 1]
		var ya := float(a[1])
		var yb := float(b[1])
		if (float(a[0]) < 0.0) != front or (float(b[0]) < 0.0) != front or absf(yb - ya) < 0.001:
			continue
		if y < minf(ya, yb) or y > maxf(ya, yb):
			continue
		var z := lerpf(float(a[0]), float(b[0]), (y - ya) / (yb - ya))
		if not found or (z < best if front else z > best):
			best = z
			found = true
	return best


## The angle round a wheel arch of radius `ar` about a wheel `r` up where it meets a sill `y` high.
static func _arch_foot(y: float, r: float, ar: float) -> float:
	return asin(clampf((y - r) / ar, -1.0, 1.0))


## A side outline: `top` from the front bottom corner up, over and down to the back bottom corner
## (z, y pairs), closed along the sill with each axle's arch cut out of it.
func _outline(top: Array, sill: float, ar: float) -> PackedVector2Array:
	var out := _pts(top)
	var r := float(s["r"])
	var axles: Array = s["axles"]
	for i in range(axles.size() - 1, -1, -1):
		var z := float(axles[i])
		var foot := _arch_foot(sill, r, ar)
		out.append_array(CarModel.arc(Vector2(z, r), ar, foot, PI - foot, 8 if lo else 16))
	return out


## Black arch tubs (so you don't see through the car over a wheel), liners round the cut-out and,
## with `flare`, a black trim standing proud round it.
func _arches(sill: float, ar: float, w: float, flare: bool) -> void:
	var r := float(s["r"])
	for z in s["axles"]:
		var foot := _arch_foot(sill, r, ar)
		var tub := CarModel.arc(Vector2(z, r), ar - 0.004, foot, PI - foot, 8 if lo else 16)
		_prism(tub, -(w - 0.3), w - 0.3, 0.003, "trim", UNDER)
		var ring := CarModel.arc(Vector2(z, r), ar - 0.006, foot, PI - foot, 8 if lo else 16)
		ring.append_array(CarModel.arc(Vector2(z, r), ar - 0.03, PI - foot, foot, 8 if lo else 16))
		_prisms(ring, w - 0.31, w - 0.004, 0.003, "trim", UNDER)
		if flare:
			var f := CarModel.arc(Vector2(z, r), ar + 0.065, foot - 0.12, PI - foot + 0.12, 8 if lo else 18)
			f.append_array(CarModel.arc(Vector2(z, r), ar - 0.008, PI - foot + 0.12, foot - 0.12, 8 if lo else 18))
			_prisms(f, w - 0.02, w + 0.03, 0.012, "trim", BLACK)


## A number plate on the face at `z` (facing -Z at the front, +Z at the back), with its letters.
func _number_plate(z: float, y: float, front: bool, wide := 0.52) -> void:
	var dz := -1.0 if front else 1.0
	_box(Vector3(wide, 0.115, 0.012), Vector3(0.0, y, z), "trim", PLATE if front else PLATE_REAR)
	if lo:
		return
	for k in 7:
		if k == 4:
			continue
		var x := (k - 3.0) * wide * 0.12
		_box(Vector3(wide * 0.085, 0.075, 0.004), Vector3(x, y, z + dz * 0.007), "trim", UNDER)


## A door mirror at (z, y) on each side, with its arm, glass and indicator repeater.
func _mirrors(z: float, y: float, w: float, size := 1.0) -> void:
	var hw := 0.11 * size
	var hh := 0.075 * size
	for side in [1.0, -1.0]:
		var x0 := w + 0.05
		var housing := _pts([[z - 0.03, y - hh], [z - 0.045, y + hh * 0.7], [z - 0.01, y + hh], [z + 0.07, y + hh], [z + 0.075, y - hh]])
		if side > 0.0:
			_prism(housing, x0, x0 + hw * 2.0, 0.025, "paint")
		else:
			_prism(housing, -x0 - hw * 2.0, -x0, 0.025, "paint")
		_box(Vector3(0.1, 0.045, 0.07), Vector3(side * (w + 0.03), y - hh * 0.6, z), "trim", BLACK)
		if not lo:
			_box(Vector3(hw * 1.7, hh * 1.7, 0.006), Vector3(side * (x0 + hw), y, z + 0.078), "metal", CHROME)
			_box(Vector3(hw * 1.1, 0.012, 0.025), Vector3(side * (x0 + hw * 1.1), y - hh + 0.005, z - 0.03), "lamps", LENS_AMBER,
				Vector3.ZERO, CH_RIGHT if side > 0.0 else CH_LEFT)


## The cabin seen through the glass: dash and instruments, steering wheel (right-hand drive),
## front seats and the back bench, the cabin floor's dark top, the rear-view mirror.
func _cabin(z_ws: float, z_end: float, w: float, front_z: float, rear_z: float, tall := 1.0) -> void:
	var inner := w - 0.07
	_box(Vector3(inner * 2.0, 0.006, z_end - z_ws - 0.06), Vector3(0.0, belt + 0.003, (z_ws + z_end) * 0.5), "trim", TRIM_IN)
	if lo:
		# Just the seats' shapes, for the far mesh.
		_box(Vector3(inner * 1.7, 0.6 * tall, 0.16), Vector3(0.0, belt + 0.3 * tall, front_z + 0.1), "trim", SEAT)
		return
	# The dashboard and its instrument binnacle, the dials glowing with the lights on.
	var dash := _pts([[z_ws + 0.02, belt], [z_ws + 0.05, belt + 0.06], [z_ws + 0.22, belt + 0.1], [z_ws + 0.45, belt + 0.08],
		[z_ws + 0.5, belt - 0.05], [z_ws + 0.02, belt - 0.05]])
	_prism(dash, -inner, inner, 0.03, "trim", TRIM_IN)
	var ex := inner * 0.48
	_prism(_pts([[z_ws + 0.34, belt + 0.08], [z_ws + 0.36, belt + 0.15], [z_ws + 0.45, belt + 0.155], [z_ws + 0.48, belt + 0.08]]),
		ex - 0.16, ex + 0.16, 0.02, "trim", TRIM_IN)
	_box(Vector3(0.24, 0.07, 0.01), Vector3(ex, belt + 0.11, z_ws + 0.475), "lamps", Color(0.35, 0.6, 1.0), Vector3(deg_to_rad(-15.0), 0.0, 0.0), CH_MARKER)
	_box(Vector3(0.2, 0.12, 0.012), Vector3(0.0, belt + 0.07, z_ws + 0.45), "metal", GLOSS, Vector3(deg_to_rad(-20.0), 0.0, 0.0))
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.16
	wheel.outer_radius = 0.185
	wheel.rings = 20
	wheel.ring_segments = 6
	_add(wheel, "trim", BLACK, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(65.0)), Vector3(ex, belt + 0.14, z_ws + 0.62)))
	_cyl(0.05, 0.05, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(65.0)), Vector3(ex, belt + 0.14, z_ws + 0.62)), "trim", TRIM_IN, 10)
	# Front seats: cushion, back and headrest; the back bench. Their tops sit under the roof:
	# `tall` is the glasshouse's height over the belt.
	for x in [-ex, ex]:
		_box(Vector3(0.5, 0.14, 0.5), Vector3(x, belt - 0.2, front_z - 0.25), "trim", SEAT)
		var back := _pts([[front_z + 0.02, belt - 0.25], [front_z - 0.02, belt + 0.5 * tall], [front_z + 0.03, belt + 0.56 * tall],
			[front_z + 0.13, belt + 0.55 * tall], [front_z + 0.16, belt - 0.25]])
		_prism(back, x - 0.25, x + 0.25, 0.05, "trim", SEAT)
		_prism(_pts([[front_z + 0.04, belt + 0.6 * tall], [front_z + 0.035, belt + 0.75 * tall], [front_z + 0.12, belt + 0.76 * tall],
			[front_z + 0.13, belt + 0.6 * tall]]), x - 0.13, x + 0.13, 0.03, "trim", SEAT)
	if rear_z < z_end:
		var bench := _pts([[rear_z + 0.02, belt - 0.25], [rear_z - 0.02, belt + 0.45 * tall], [rear_z + 0.03, belt + 0.5 * tall],
			[rear_z + 0.12, belt + 0.5 * tall], [rear_z + 0.14, belt - 0.25]])
		_prism(bench, -inner + 0.05, inner - 0.05, 0.05, "trim", SEAT)
		for x in [-ex, ex]:
			_prism(_pts([[rear_z + 0.04, belt + 0.55 * tall], [rear_z + 0.035, belt + 0.68 * tall], [rear_z + 0.11, belt + 0.69 * tall],
				[rear_z + 0.12, belt + 0.55 * tall]]), x - 0.12, x + 0.12, 0.03, "trim", SEAT)
	var top := _gp(z_ws + 0.85, PI * 0.5).y
	_box(Vector3(0.22, 0.065, 0.02), Vector3(0.0, top - 0.1, z_ws + 0.8), "metal", GLOSS, Vector3(deg_to_rad(-10.0), 0.0, 0.0))


## Shut lines: a thin dark line down the body side at each z, from the sill to `y1`.
func _shut_lines(zs: Array, y0: float, y1: float, w: float) -> void:
	if lo:
		return
	for z in zs:
		_boxes(Vector3(0.004, y1 - y0, 0.005), Vector3(w + 0.0015, (y0 + y1) * 0.5, z), "trim", UNDER)


## Door handles at each z, `y` up.
func _handles(zs: Array, y: float, w: float, key := "metal", col := CHROME) -> void:
	if lo:
		return
	for z in zs:
		_boxes(Vector3(0.025, 0.03, 0.16), Vector3(w + 0.008, y, z), key, col)


## Roof rails along the roof's edges from z0 to z1.
func _roof_rails(z0: float, z1: float, key := "metal", col := SATIN) -> void:
	for side in [1.0, -1.0]:
		var path := []
		for k in 7:
			var z := lerpf(z0, z1, k / 6.0)
			var p := _gp(z, (_edge(z) + 0.1) if side > 0.0 else (PI - _edge(z) - 0.1), 0.045)
			path.append(p)
		_add(ShapeKit.sweep(path, 0.016, 6 if lo else 8), key, col)
		for z in [z0 + 0.05, z1 - 0.05]:
			var p := _gp(z, (_edge(z) + 0.1) if side > 0.0 else (PI - _edge(z) - 0.1), 0.02)
			_box(Vector3(0.04, 0.05, 0.08), p, "trim", BLACK)


# ---------------------------------------------------------------------------- building

func _build() -> void:
	match kind:
		"hatchback", "saloon", "estate", "suv", "supercar":
			_car()
		"van":
			_van()
		"lorry":
			_lorry()
		"coach":
			_coach()
		"police":
			# An estate car underneath (plain trim, no roof rails), in its livery and kit.
			kind = "estate"
			trim = 1
			_car()
			kind = "police"
			_police()
	_shape_body()
	if lo:
		items.append_array(_wheels_baked())


## Each kind's plan-view rounding: how far in its corners come at the nose and tail (a share of
## its width) and over how long, and how much the sides lean in towards the shoulder.
const SHAPING := {
	"hatchback": [0.13, 0.6, 0.09, 0.45, 0.045], "saloon": [0.13, 0.7, 0.08, 0.5, 0.045], "estate": [0.13, 0.7, 0.06, 0.45, 0.045],
	"suv": [0.1, 0.6, 0.06, 0.45, 0.04], "van": [0.1, 0.6, 0.025, 0.3, 0.02], "lorry": [0.035, 0.4, 0.0, 0.3, 0.0],
	"coach": [0.05, 0.6, 0.02, 0.4, 0.0], "police": [0.13, 0.7, 0.06, 0.45, 0.045], "supercar": [0.17, 0.85, 0.1, 0.55, 0.07],
}


## Rounds the body off: every piece so far is drawn in at the nose and tail corners (so they
## curve round in plan, the lamps and bumpers with them) and leans in a little above the waist.
func _shape_body() -> void:
	var sh: Array = SHAPING[kind]
	var half := float(s["len"]) * 0.5
	for it in items:
		var mesh: Mesh = it[0]
		var xf: Transform3D = it[1]
		var out := ArrayMesh.new()
		var nb := xf.basis.inverse().transposed()
		for si in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for k in v.size():
				var p := xf * v[k]
				var nn := (nb * n[k]).normalized()
				# x' = x f(z) g(y): the corner pinch along z, the shoulder's lean up y.
				var fz := 1.0
				var dfz := 0.0
				var tf := (-p.z - (half - float(sh[1]))) / float(sh[1])
				var tr := (p.z - (half - float(sh[3]))) / float(sh[3])
				if tf > 0.0:
					var c := minf(tf, 1.0)
					fz = 1.0 - float(sh[0]) * c * c
					dfz = 2.0 * float(sh[0]) * c / float(sh[1]) if tf < 1.0 else 0.0
				elif tr > 0.0:
					var c := minf(tr, 1.0)
					fz = 1.0 - float(sh[2]) * c * c
					dfz = -2.0 * float(sh[2]) * c / float(sh[3]) if tr < 1.0 else 0.0
				var u := clampf((p.y - (belt - 0.35)) / 0.35, 0.0, 1.0)
				var gy := 1.0 - float(sh[4]) * u * u
				var dgy := -2.0 * float(sh[4]) * u / 0.35 if u > 0.0 and u < 1.0 else 0.0
				var f := fz * gy
				v[k] = Vector3(p.x * f, p.y, p.z)
				n[k] = Vector3(nn.x / f, nn.y - p.x * dgy / gy * nn.x / f, nn.z - p.x * dfz / fz * nn.x / f).normalized()
			a[Mesh.ARRAY_VERTEX] = v
			a[Mesh.ARRAY_NORMAL] = n
			a[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		it[0] = out
		it[1] = Transform3D()


## The cars (and the supercar), from one recipe with each one's lines.
func _car() -> void:
	var w := float(s["w"])
	var r := float(s["r"])
	var sill := 0.3
	var ar := r + 0.06
	var top: Array
	var nz := 0.0
	var tz := 0.0
	var pillars: Array
	var c_from := 0.0
	var doors: Array
	var handles: Array
	var head_y := Vector2.ZERO      # bottom and top of the headlamps
	var tail_y := Vector2.ZERO
	var bump_f := 0.0               # the bumpers' top edges
	var bump_r := 0.0
	var rear_seat := 0.0
	match kind:
		"hatchback":
			belt = 0.95
			nz = -2.03
			tz = 2.03
			top = [[-2.0, sill], [-2.03, 0.42], [-2.035, 0.62], [-2.0, 0.73], [-1.9, 0.79], [-1.6, 0.845], [-1.25, 0.9], [-0.92, 0.945],
				[-0.9, belt], [1.86, belt], [1.97, 0.93], [2.02, 0.8], [2.035, 0.55], [2.0, sill]]
			gl = [[-0.9, 0.79, 0.015], [-0.75, 0.785, 0.13], [-0.55, 0.78, 0.27], [-0.35, 0.775, 0.39], [-0.15, 0.77, 0.47], [0.0, 0.765, 0.5],
				[0.6, 0.76, 0.51], [1.2, 0.75, 0.5], [1.45, 0.74, 0.46], [1.65, 0.73, 0.36], [1.8, 0.72, 0.2], [1.86, 0.715, 0.06]]
			gn = 4.0
			roof_from = -0.15
			roof_to = 1.42
			r_foot = 0.4
			pillars = [[0.17, 0.27, "gloss"]]
			c_from = 1.08
			doors = [-0.88, 0.22, 1.1]
			handles = [-0.02, 0.98]
			head_y = Vector2(0.6, 0.74)
			tail_y = Vector2(0.72, 0.92)
			bump_f = 0.54
			bump_r = 0.55
			rear_seat = 1.05
		"saloon", "estate":
			belt = 0.98
			nz = -2.37
			tz = 2.37
			gn = 4.0
			roof_from = -0.2
			a_foot = 0.3
			if kind == "saloon":
				top = [[-2.33, sill], [-2.37, 0.45], [-2.375, 0.64], [-2.33, 0.75], [-2.2, 0.81], [-1.8, 0.88], [-1.4, 0.94], [-1.05, 0.975],
					[-1.02, belt], [1.52, belt], [1.6, 1.0], [2.1, 1.035], [2.3, 1.03], [2.36, 0.96], [2.375, 0.6], [2.33, sill]]
				gl = [[-1.02, 0.81, 0.015], [-0.85, 0.805, 0.13], [-0.62, 0.8, 0.27], [-0.4, 0.795, 0.39], [-0.2, 0.79, 0.46], [0.0, 0.785, 0.48],
					[0.7, 0.78, 0.48], [0.95, 0.775, 0.44], [1.15, 0.77, 0.35], [1.35, 0.765, 0.19], [1.52, 0.76, 0.04]]
				roof_to = 0.8
				r_foot = 0.3
				pillars = [[0.07, 0.17, "gloss"]]
				c_from = 0.86
				tail_y = Vector2(0.84, 1.0)
			else:
				top = [[-2.33, sill], [-2.37, 0.45], [-2.375, 0.64], [-2.33, 0.75], [-2.2, 0.81], [-1.8, 0.88], [-1.4, 0.94], [-1.05, 0.975],
					[-1.02, belt], [2.22, belt], [2.33, 0.96], [2.365, 0.8], [2.375, 0.6], [2.33, sill]]
				gl = [[-1.02, 0.81, 0.015], [-0.85, 0.805, 0.13], [-0.62, 0.8, 0.27], [-0.4, 0.795, 0.39], [-0.2, 0.79, 0.46], [0.0, 0.785, 0.49],
					[1.0, 0.78, 0.49], [1.7, 0.77, 0.48], [1.95, 0.765, 0.45], [2.1, 0.755, 0.37], [2.18, 0.75, 0.22], [2.22, 0.745, 0.05]]
				roof_to = 1.95
				r_foot = 0.45
				pillars = [[0.07, 0.17, "gloss"], [1.05, 1.13, "gloss"]]
				c_from = 1.82
				tail_y = Vector2(0.72, 1.1)
			doors = [-1.0, 0.12, 1.12]
			handles = [-0.12, 0.98]
			head_y = Vector2(0.62, 0.75)
			bump_f = 0.56
			bump_r = 0.58
			rear_seat = 1.0
		"suv":
			sill = 0.44
			ar = r + 0.08
			belt = 1.12
			nz = -2.32
			tz = 2.32
			top = [[-2.28, 0.42], [-2.32, 0.55], [-2.325, 0.86], [-2.27, 0.96], [-2.1, 1.01], [-1.7, 1.06], [-1.3, 1.1], [-1.0, 1.115],
				[-0.98, belt], [2.13, belt], [2.25, 1.1], [2.31, 0.96], [2.325, 0.62], [2.28, 0.42]]
			gl = [[-0.98, 0.85, 0.015], [-0.82, 0.845, 0.14], [-0.62, 0.84, 0.29], [-0.42, 0.835, 0.42], [-0.22, 0.83, 0.52], [0.0, 0.825, 0.56],
				[1.5, 0.81, 0.57], [1.85, 0.8, 0.53], [2.0, 0.79, 0.43], [2.1, 0.785, 0.27], [2.13, 0.78, 0.06]]
			gn = 5.0
			roof_from = -0.22
			roof_to = 1.8
			r_foot = 0.5
			pillars = [[0.1, 0.2, "gloss"], [1.02, 1.1, "gloss"]]
			c_from = 1.62
			doors = [-0.96, 0.15, 1.14]
			handles = [-0.08, 1.0]
			head_y = Vector2(0.8, 0.94)
			tail_y = Vector2(0.9, 1.1)
			bump_f = 0.74
			bump_r = 0.72
			rear_seat = 1.05
		"supercar":
			# Low and wide: a long sloping nose, the cabin well forward, a short raked glasshouse
			# running back into the engine cover, two seats and nothing behind them.
			sill = 0.17
			ar = r + 0.035
			belt = 0.78
			nz = -2.3
			tz = 2.3
			top = [[-2.26, sill], [-2.3, 0.28], [-2.3, 0.38], [-2.24, 0.45], [-2.05, 0.52], [-1.7, 0.6], [-1.3, 0.67], [-0.95, 0.73], [-0.8, 0.76],
				[-0.78, belt], [1.62, belt], [1.9, 0.82], [2.15, 0.83], [2.27, 0.78], [2.3, 0.66], [2.3, 0.36], [2.26, sill]]
			gl = [[-0.78, 0.76, 0.015], [-0.6, 0.75, 0.1], [-0.38, 0.74, 0.19], [-0.15, 0.73, 0.27], [0.08, 0.72, 0.32], [0.35, 0.71, 0.34],
				[0.62, 0.7, 0.32], [0.88, 0.68, 0.26], [1.15, 0.65, 0.17], [1.4, 0.62, 0.08], [1.62, 0.58, 0.02]]
			gn = 3.2
			roof_from = 0.08
			roof_to = 0.62
			a_foot = 0.25
			r_foot = 0.55
			pillars = []
			c_from = 0.72
			doors = [-0.76, 0.62]
			handles = []
			head_y = Vector2(0.5, 0.58)
			tail_y = Vector2(0.6, 0.74)
			bump_f = 0.42
			bump_r = 0.5
			rear_seat = 3.0
	var z_ws := float(gl[0][0])
	var zb := float(gl[-1][0])
	# The body: one solid with the arches cut through it, rounded off at its edges.
	_prism(_outline(top, sill, ar), -w, w, 0.07, "paint")
	_arches(sill, ar, w, kind == "suv" or trim == 2)
	_glasshouse(pillars, c_from)
	_cabin(z_ws, zb, w, z_ws + 1.0, z_ws + 0.9 + rear_seat, _glass_at(0.3).y)
	# Bumpers: body colour, wrapping round, standing a little proud, with black lower parts.
	var bf := _pts([[nz - 0.025, sill + 0.03], [nz - 0.03, bump_f - 0.05], [nz + 0.01, bump_f], [nz + 0.36, bump_f], [nz + 0.36, sill + 0.03]])
	_prism(bf, -w - 0.012, w + 0.012, 0.1, "paint")
	_prism(_pts([[nz - 0.015, sill - 0.02], [nz - 0.02, sill + 0.09], [nz + 0.3, sill + 0.09], [nz + 0.3, sill - 0.02]]), -w + 0.06, w - 0.06, 0.03, "trim", BLACK)
	var br := _pts([[tz + 0.025, sill + 0.03], [tz + 0.03, bump_r - 0.05], [tz - 0.01, bump_r], [tz - 0.36, bump_r], [tz - 0.36, sill + 0.03]])
	_prism(br, -w - 0.012, w + 0.012, 0.1, "paint")
	_prism(_pts([[tz + 0.015, sill - 0.02], [tz + 0.022, sill + 0.1], [tz - 0.3, sill + 0.1], [tz - 0.3, sill - 0.02]]), -w + 0.06, w - 0.06, 0.03, "trim", BLACK)
	# The grille between the headlamps, the lower intake in the bumper, fog lamps.
	var f0 := _face(top, head_y.x, true)
	var f1 := _face(top, head_y.y, true)
	var tilt := Vector3(atan2(f1 - f0, head_y.y - head_y.x), 0.0, 0.0)
	var gy := (head_y.x + head_y.y) * 0.5
	var grille_w := w * (0.62 if kind == "suv" else (0.4 if kind == "supercar" else 0.5))
	_box(Vector3(grille_w * 2.0, head_y.y - head_y.x + 0.02, 0.03), Vector3(0.0, gy, (f0 + f1) * 0.5), "metal", GLOSS, tilt)
	if not lo:
		for i in 3:
			var yy := head_y.x + 0.03 + i * (head_y.y - head_y.x - 0.06) / 2.0
			_box(Vector3(grille_w * 2.0 - 0.04, 0.012, 0.012), Vector3(0.0, yy, _face(top, yy, true) - 0.017), "metal", CHROME if trim == 0 else SATIN, tilt)
	_box(Vector3(w * 1.1, bump_f - sill - 0.16, 0.03), Vector3(0.0, (bump_f + sill) * 0.5 + 0.02, nz - 0.032), "metal", GLOSS)
	_boxes(Vector3(0.16, 0.05, 0.025), Vector3(w - 0.2, sill + 0.13, nz - 0.03), "lamps", LENS_WHITE, Vector3.ZERO, CH_OFF)
	_number_plate(nz - 0.05, (bump_f + sill) * 0.5 + 0.02, true)
	# Headlamps: a dark bezel, the lens and an LED strip along the top, the indicator at the
	# outer end and wrapping round onto the wing; all lying on the nose's slope.
	for side in [1.0, -1.0]:
		var x0 := grille_w + 0.02
		var x1 := w - 0.03
		var y0 := head_y.x
		var y1 := head_y.y
		var at := func(x: float, y: float, out: float) -> Vector3: return Vector3(side * x, y, _face(top, y, true) - out)
		_plate([at.call(x0, y0, 0.005), at.call(x0, y1, 0.005), at.call(x1, y1, 0.005), at.call(x1, y0 + 0.02, 0.005)], 0.012, "metal",
			SATIN.darkened(0.5), CH_OFF, false)
		_plate([at.call(x0 + 0.02, y0 + 0.02, 0.013), at.call(x0 + 0.02, y1 - 0.03, 0.013), at.call(x1 - 0.09, y1 - 0.03, 0.013),
			at.call(x1 - 0.09, y0 + 0.025, 0.013)], 0.006, "lamps", LENS_WHITE, CH_HEAD, false)
		_plate([at.call(x0 + 0.02, y1 - 0.02, 0.014), at.call(x0 + 0.02, y1 - 0.006, 0.014), at.call(x1 - 0.02, y1 - 0.006, 0.014),
			at.call(x1 - 0.02, y1 - 0.02, 0.014)], 0.006, "lamps", LENS_WHITE, CH_HEAD, false)
		var ind := CH_RIGHT if side > 0.0 else CH_LEFT
		_plate([at.call(x1 - 0.08, y0 + 0.025, 0.014), at.call(x1 - 0.08, y1 - 0.03, 0.014), at.call(x1 - 0.01, y1 - 0.03, 0.014),
			at.call(x1 - 0.01, y0 + 0.025, 0.014)], 0.006, "lamps", LENS_AMBER, ind, false)
		_box(Vector3(0.008, y1 - y0 - 0.04, 0.16), Vector3(side * (w + 0.003), (y0 + y1) * 0.5, _face(top, y1, true) + 0.13), "lamps", LENS_AMBER, Vector3.ZERO, ind)
	# Tail lamps: a cluster at each corner wrapping round the side, the indicator and the
	# reversing lamp in it.
	var t0 := _face(top, tail_y.x, false)
	var t1 := _face(top, tail_y.y, false)
	var ttilt := Vector3(atan2(t1 - t0, tail_y.y - tail_y.x), 0.0, 0.0)
	for side in [1.0, -1.0]:
		var x1 := w + 0.006
		var x0 := w - (0.4 if kind in ["saloon", "supercar"] else 0.3)
		var tl := _pts([[t0 - 0.12, tail_y.x], [t1 - 0.12, tail_y.y], [t1 + 0.012, tail_y.y], [t0 + 0.012, tail_y.x]])
		if side > 0.0:
			_prism(tl, x0, x1, 0.012, "lamps", LENS_RED, CH_TAIL)
		else:
			_prism(tl, -x1, -x0, 0.012, "lamps", LENS_RED, CH_TAIL)
		var iy := tail_y.y - (tail_y.y - tail_y.x) * 0.2
		_box(Vector3(0.1, (tail_y.y - tail_y.x) * 0.22, 0.01), Vector3(side * (w - 0.17), iy, _face(top, iy, false) + 0.016),
			"lamps", LENS_AMBER, ttilt, CH_RIGHT if side > 0.0 else CH_LEFT)
		var ry := tail_y.x + (tail_y.y - tail_y.x) * 0.25
		_box(Vector3(0.1, (tail_y.y - tail_y.x) * 0.2, 0.01), Vector3(side * (w - 0.17), ry, _face(top, ry, false) + 0.016), "lamps", LENS_WHITE, ttilt, CH_OFF)
	# The high brake lamp: atop the rear window (on the spoiler) or on the boot lid.
	if kind == "saloon":
		_box(Vector3(0.5, 0.025, 0.02), Vector3(0.0, 1.045, 2.25), "lamps", LENS_RED, Vector3.ZERO, CH_BRAKE)
		if not lo:
			_box(Vector3(w * 1.7, 0.004, 0.005), Vector3(0.0, 1.0, 1.62), "trim", UNDER)   # the boot lid's shut line
	else:
		var hy := _gp(roof_to, PI * 0.5).y
		var spoiler := _pts([[roof_to - 0.05, hy - 0.005], [roof_to - 0.03, hy + 0.025], [roof_to + 0.17, hy + 0.005], [roof_to + 0.19, hy - 0.03],
			[roof_to + 0.06, hy - 0.05]])
		if kind == "hatchback":
			_prism(spoiler, -_glass_at(roof_to).x + 0.04, _glass_at(roof_to).x - 0.04, 0.02, "paint")
		_box(Vector3(0.36, 0.025, 0.02), Vector3(0.0, hy - 0.04, roof_to + (0.12 if kind == "hatchback" else (zb - roof_to) * 0.15 + 0.04)), "lamps", LENS_RED,
			Vector3.ZERO, CH_BRAKE)
		var hdy := belt - 0.12
		_box(Vector3(0.26, 0.05, 0.02), Vector3(0.0, hdy, _face(top, hdy, false) + 0.01), "metal", CHROME if trim == 0 else GLOSS, ttilt)   # the tailgate's handle bar
	_number_plate(tz + 0.05, (bump_r + sill) * 0.5 + 0.03, false)
	if kind == "supercar":
		_supercar_kit(w, tz)
	# Mirrors, handles, shut lines, a black sill and the belt moulding.
	_mirrors(z_ws + 0.12, belt + 0.07, w)
	_handles(handles, belt - 0.11, w, "metal" if trim == 0 else "paint", CHROME)
	_shut_lines(doors, sill + 0.05, belt, w)
	if not lo:
		_boxes(Vector3(0.004, 0.005, doors[-1] - doors[0]), Vector3(w + 0.0015, sill + 0.05, (doors[0] + doors[-1]) * 0.5), "trim", UNDER)
		# The fuel flap on the left behind the back door.
		_box(Vector3(0.006, 0.14, 0.14), Vector3(-w - 0.001, belt - 0.15, (doors[-1] + float(s["axles"][1])) * 0.5 + 0.15), "paint")
	_boxes(Vector3(0.02, 0.02, c_from - doors[0]), Vector3(w - 0.01, belt + 0.004, (doors[0] + c_from) * 0.5), "trim", BLACK)
	if kind == "suv":
		_boxes(Vector3(0.04, 0.14, (float(s["axles"][1]) - float(s["axles"][0])) - ar * 2.0 - 0.05), Vector3(w + 0.012, sill + 0.06,
			(float(s["axles"][0]) + float(s["axles"][1])) * 0.5), "trim", BLACK)
		_box(Vector3(0.9, 0.04, 0.3), Vector3(0.0, sill - 0.01, nz + 0.14), "metal", SATIN, Vector3(deg_to_rad(-12.0), 0.0, 0.0))
	if kind == "suv" or (kind == "estate" and trim != 1):
		_roof_rails(roof_from + 0.12, roof_to - 0.05, "metal" if trim == 0 else "trim", SATIN if trim == 0 else BLACK)
	# Underneath: the floor pan, the exhaust out the back left, a shark-fin aerial.
	_box(Vector3(w * 2.0 - 0.3, 0.12, tz - nz - 0.9), Vector3(0.0, sill - 0.02, 0.0), "trim", UNDER)
	_cyl(0.032, 0.14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-w + 0.3, sill + 0.03, tz - 0.02)), "metal", CHROME if trim == 0 else SATIN, 10)
	if not lo:
		var fin := _pts([[roof_to - 0.25, 0.0], [roof_to - 0.08, 0.06], [roof_to - 0.02, 0.06], [roof_to, 0.0]])
		var ry := _gp(roof_to - 0.1, PI * 0.5, 0.006).y
		_add(CarModel.prism(fin, -0.025, 0.025, 0.01), "paint", Color.WHITE, Transform3D(Basis(), Vector3(0.0, ry - 0.005, 0.0)))


## A supercar's extras: a rear wing on two struts over the engine cover, the side intakes ahead of
## the back wheels, a black diffuser under the tail with the twin pipes in the middle of it, and
## the engine cover's louvres.
func _supercar_kit(w: float, tz: float) -> void:
	var axles: Array = s["axles"]
	var wing := _pts([[1.92, 1.0], [1.95, 1.025], [2.18, 1.03], [2.24, 1.01], [2.2, 0.995]])
	_prism(wing, -w + 0.06, w - 0.06, 0.008, "metal" if trim == 1 else "paint", GLOSS)
	for x in [-0.55, 0.55]:
		_box(Vector3(0.03, 0.2, 0.12), Vector3(x, 0.91, 2.1), "metal", GLOSS, Vector3(deg_to_rad(-12.0), 0.0, 0.0))
	for side in [1.0, -1.0]:
		var intake := _pts([[float(axles[1]) - 0.95, 0.46], [float(axles[1]) - 0.85, 0.68], [float(axles[1]) - 0.42, 0.7], [float(axles[1]) - 0.45, 0.44]])
		if side > 0.0:
			_prism(intake, w - 0.02, w + 0.004, 0.006, "trim", UNDER)
		else:
			_prism(intake, -w - 0.004, -w + 0.02, 0.006, "trim", UNDER)
	_box(Vector3(w * 1.6, 0.1, 0.35), Vector3(0.0, 0.2, tz - 0.14), "trim", BLACK, Vector3(deg_to_rad(10.0), 0.0, 0.0))
	for x in [-0.09, 0.09]:
		_cyl(0.045, 0.12, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.3, tz - 0.01)), "metal", CHROME if trim == 0 else SATIN, 12)
	if not lo:
		for k in 5:
			_box(Vector3(0.7, 0.008, 0.03), Vector3(0.0, 0.825, 1.7 + k * 0.08), "trim", UNDER)


## A police estate's livery and kit over the estate car: battenberg checks of hi-vis yellow and
## blue down both sides (two rows between the wheel arches, one fore and aft of them), a band of
## them across the tailgate, the light bar on the roof (blue lamps either end, the left and right
## banks flashing in turn, see TrafficVehicle.set_blues) and blue lamps in the grille and tailgate.
func _police() -> void:
	var w := float(s["w"])
	var axles: Array = s["axles"]
	var ar := float(s["r"]) + 0.06
	var cell := 0.42
	var low := Vector2(0.44, 0.68)
	var high := Vector2(0.69, belt - 0.05)
	var n := 0
	var z := -2.02
	while z + cell <= 2.14:
		var zc := z + cell * 0.5
		var between := zc - cell * 0.5 > float(axles[0]) + ar and zc + cell * 0.5 < float(axles[1]) - ar
		for row in [high, low]:
			if row == low and not between:
				continue
			var yellow := (n + (1 if row == low else 0)) % 2 == 0
			_boxes(Vector3(0.006, row.y - row.x, cell), Vector3(w + 0.004, (row.x + row.y) * 0.5, zc), "trim", HIVIS if yellow else POLICE_BLUE)
		n += 1
		z += cell
	# Across the tailgate under the rear window, between the tail lamps.
	var tw := w - 0.32
	var cols := 6
	for k in cols:
		var x0 := -tw + 2.0 * tw * k / cols
		var x1 := x0 + 2.0 * tw / cols
		var y := 0.62
		_box(Vector3(x1 - x0, 0.12, 0.006), Vector3((x0 + x1) * 0.5, y, _face_z(y) + 0.008), "trim", HIVIS if k % 2 == 0 else POLICE_BLUE)
	# The light bar, over the front seats, on two feet.
	var bz := roof_from + 0.55
	var top := _gp(bz, PI * 0.5).y
	_box(Vector3(1.24, 0.05, 0.3), Vector3(0.0, top + 0.045, bz), "trim", BLACK)
	_boxes(Vector3(0.05, 0.04, 0.2), Vector3(0.5, top + 0.01, bz), "trim", BLACK)
	_box(Vector3(0.5, 0.08, 0.27), Vector3(0.36, top + 0.11, bz), "lamps", LENS_BLUE, Vector3.ZERO, CH_BLUE_R)
	_box(Vector3(0.5, 0.08, 0.27), Vector3(-0.36, top + 0.11, bz), "lamps", LENS_BLUE, Vector3.ZERO, CH_BLUE_L)
	_box(Vector3(0.2, 0.065, 0.25), Vector3(0.0, top + 0.1, bz), "lamps", LENS_WHITE, Vector3.ZERO, CH_OFF)
	# Blue lamps in the grille and at the top of the tailgate.
	_boxes(Vector3(0.13, 0.035, 0.02), Vector3(0.18, 0.69, -2.378), "lamps", LENS_BLUE, Vector3.ZERO, CH_BLUE_R, CH_BLUE_L)
	_boxes(Vector3(0.12, 0.03, 0.02), Vector3(0.42, belt - 0.03, _face_z(belt - 0.03) + 0.012), "lamps", LENS_BLUE, Vector3.ZERO, CH_BLUE_R, CH_BLUE_L)


## The estate's tailgate face at height `y` (its own outline, as _car draws it).
func _face_z(y: float) -> float:
	return _face([[-2.33, 0.3], [2.22, belt], [2.33, 0.96], [2.365, 0.8], [2.375, 0.6], [2.33, 0.3]], y, false)


## The panel van: a car-like nose and cab glass, then the tall load box, sliding side door, twin
## back doors, ribs pressed in the sides; with a roof rack and ladder, or a livery stripe.
func _van() -> void:
	var w := float(s["w"])
	var r := float(s["r"])
	var sill := 0.4
	var ar := r + 0.08
	belt = 1.15
	var nz := -2.67
	var tz := 2.67
	var roof := 2.3
	var box_z := -0.82
	var top := [[-2.62, sill], [-2.67, 0.55], [-2.68, 0.8], [-2.62, 0.95], [-2.45, 1.0], [-2.1, 1.06], [-1.82, 1.12], [-1.78, belt],
		[box_z, belt], [box_z, roof - 0.06], [box_z + 0.06, roof], [tz - 0.08, roof], [tz, roof - 0.08], [tz + 0.01, 0.6], [tz - 0.04, sill]]
	_prism(_outline(top, sill, ar), -w, w, 0.06, "paint")
	_arches(sill, ar, w, trim == 1)
	gl = [[-1.78, 0.93, 0.015], [-1.62, 0.93, 0.3], [-1.46, 0.935, 0.58], [-1.3, 0.94, 0.82], [-1.15, 0.94, 0.98], [-1.0, 0.94, 1.05],
		[box_z, 0.94, 1.07]]
	gn = 7.0
	roof_from = -1.08
	roof_to = box_z
	a_foot = 0.25
	r_foot = ROOF_EDGE
	_glasshouse([], box_z)
	_cabin(-1.78, box_z, w, -0.95, 99.0, 0.75)
	if not lo:
		_box(Vector3(w * 2.0 - 0.1, roof - belt - 0.1, 0.02), Vector3(0.0, (roof + belt) * 0.5, box_z - 0.01), "trim", TRIM_IN)   # the bulkhead
		# Ribs pressed along the load box's sides, and its shut lines: sliding door and back doors.
		for y in [1.45, 1.9]:
			_boxes(Vector3(0.01, 0.05, tz - box_z - 0.4), Vector3(w + 0.002, y, (box_z + tz) * 0.5 + 0.05), "paint")
		_shut_lines([-1.76, -0.84], sill + 0.05, belt, w)
		_shut_lines([-0.1, 1.0], sill + 0.05, roof - 0.12, w)
		_boxes(Vector3(0.004, 0.005, 1.1), Vector3(w + 0.0015, roof - 0.12, 0.45), "trim", UNDER)
		_box(Vector3(0.005, roof - sill - 0.2, 0.004), Vector3(0.0, (roof + sill) * 0.5 - 0.05, tz + 0.012), "trim", UNDER)
		_handles([-1.1, -0.05], belt - 0.12, w, "trim", BLACK)
		for x in [-0.08, 0.08]:
			_box(Vector3(0.12, 0.035, 0.03), Vector3(x, 1.15, tz + 0.02), "trim", BLACK)
		# The sliding door's rail along the back of the box.
		_boxes(Vector3(0.02, 0.025, 1.2), Vector3(w + 0.01, belt + 0.05, 1.65), "trim", BLACK)
	if trim == 2:
		_boxes(Vector3(0.01, 0.22, tz - box_z - 0.3), Vector3(w + 0.006, 1.22, (box_z + tz) * 0.5), "paint2")
	# Bumpers (black plastic on a working van), grille, headlamps, plates.
	_prism(_pts([[nz - 0.03, sill], [nz - 0.035, 0.66], [nz + 0.32, 0.66], [nz + 0.32, sill]]), -w - 0.015, w + 0.015, 0.09,
		"trim", BLACK if trim != 1 else GREY)
	_prism(_pts([[tz + 0.04, sill], [tz + 0.045, 0.62], [tz - 0.25, 0.62], [tz - 0.25, sill]]), -w - 0.015, w + 0.015, 0.08, "trim", BLACK)
	_box(Vector3(w * 1.1, 0.24, 0.03), Vector3(0.0, 0.82, nz - 0.0), "metal", GLOSS)
	if not lo:
		for i in 3:
			_box(Vector3(w * 1.06, 0.02, 0.012), Vector3(0.0, 0.74 + i * 0.075, nz - 0.017), "metal", SATIN)
	for side in [1.0, -1.0]:
		var x0 := w * 0.58
		var x1 := w - 0.04
		_plate([Vector3(side * x0, 0.72, nz - 0.005), Vector3(side * x0, 0.94, nz + 0.0), Vector3(side * x1, 0.95, nz + 0.05),
			Vector3(side * x1, 0.72, nz + 0.03)], 0.012, "metal", SATIN.darkened(0.5), CH_OFF, false)
		_plate([Vector3(side * (x0 + 0.02), 0.75, nz - 0.013), Vector3(side * (x0 + 0.02), 0.92, nz - 0.008), Vector3(side * (x1 - 0.09), 0.925, nz + 0.03),
			Vector3(side * (x1 - 0.09), 0.75, nz + 0.012)], 0.006, "lamps", LENS_WHITE, CH_HEAD, false)
		var ind := CH_RIGHT if side > 0.0 else CH_LEFT
		_box(Vector3(0.07, 0.17, 0.008), Vector3(side * (x1 - 0.045), 0.835, nz + 0.025), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.008, 0.06, 0.12), Vector3(side * (w + 0.003), 0.95, -1.95), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		# Tall tail lamps up the back corners.
		var tl := _pts([[tz - 0.08, 0.72], [tz - 0.08, 1.3], [tz + 0.012, 1.3], [tz + 0.012, 0.72]])
		if side > 0.0:
			_prism(tl, w - 0.16, w + 0.006, 0.01, "lamps", LENS_RED, CH_TAIL)
		else:
			_prism(tl, -w - 0.006, -w + 0.16, 0.01, "lamps", LENS_RED, CH_TAIL)
		_box(Vector3(0.13, 0.12, 0.01), Vector3(side * (w - 0.08), 1.2, tz + 0.016), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.13, 0.1, 0.01), Vector3(side * (w - 0.08), 0.85, tz + 0.016), "lamps", LENS_WHITE, Vector3.ZERO, CH_OFF)
		# Side marker lamps along the box.
		for z in [0.2, 1.9]:
			_box(Vector3(0.008, 0.035, 0.07), Vector3(side * (w + 0.004), 0.55, z), "lamps", LENS_AMBER, Vector3.ZERO, CH_MARKER)
	_box(Vector3(0.4, 0.04, 0.02), Vector3(0.0, roof - 0.04, tz + 0.01), "lamps", LENS_RED, Vector3.ZERO, CH_BRAKE)
	_number_plate(nz - 0.045, 0.5, true)
	_number_plate(tz + 0.055, 0.5, false)
	_mirrors(-1.6, belt + 0.12, w, 1.35)
	_box(Vector3(w * 2.0 - 0.3, 0.14, tz - nz - 1.0), Vector3(0.0, sill - 0.02, 0.0), "trim", UNDER)
	_cyl(0.035, 0.14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-w + 0.3, sill, tz - 0.06)), "metal", SATIN, 10)
	if trim == 0:
		# A roof rack with a ladder on it.
		for z in [-0.4, 0.6, 1.6, 2.4]:
			_box(Vector3(w * 2.0 - 0.1, 0.04, 0.05), Vector3(0.0, roof + 0.07, z), "metal", SATIN)
		_boxes(Vector3(0.04, 0.05, 3.0), Vector3(w - 0.07, roof + 0.1, 1.0), "metal", SATIN)
		_boxes(Vector3(0.03, 0.03, 2.6), Vector3(0.22, roof + 0.13, 1.0), "metal", CHROME)
		if not lo:
			for k in 9:
				_box(Vector3(0.44, 0.02, 0.025), Vector3(0.0, roof + 0.13, -0.2 + k * 0.3), "metal", CHROME)


## The rigid box lorry: a flat-fronted tilt cab over the front axle with its roof deflector,
## then the chassis, fuel tank, side guards, twin back wheels, and the box body with its corner
## posts and roller shutter, a livery band along its side.
func _lorry() -> void:
	var w := float(s["w"])
	var r := float(s["r"])
	var ar := r + 0.08
	var nz := -4.3
	var cab_back := -2.45
	var cab_low := 0.6
	var cab_top := 3.05
	var fa := float(s["axles"][0])
	var foot := _arch_foot(cab_low, r, ar)
	var cab := _pts([[nz + 0.05, cab_low], [nz, 1.3], [nz, 1.95], [nz + 0.13, cab_top - 0.12], [nz + 0.3, cab_top], [cab_back, cab_top], [cab_back, cab_low]])
	cab.append_array(CarModel.arc(Vector2(fa, r), ar, foot, PI - foot, 8 if lo else 16))
	_prism(cab, -w, w, 0.08, "paint")
	var tub := CarModel.arc(Vector2(fa, r), ar - 0.004, foot, PI - foot, 8 if lo else 16)
	_prism(tub, -(w - 0.35), w - 0.35, 0.003, "trim", UNDER)
	# The windscreen up the raked front, the side windows, door shut lines and handles.
	var ws0 := Vector2(nz + 0.005, 1.98)
	var ws1 := Vector2(nz + 0.115, cab_top - 0.16)
	_plate([Vector3(-w + 0.08, ws0.y, ws0.x - 0.012), Vector3(w - 0.08, ws0.y, ws0.x - 0.012), Vector3(w - 0.1, ws1.y, ws1.x - 0.012),
		Vector3(-w + 0.1, ws1.y, ws1.x - 0.012)], 0.01, "dark_glass", Color.WHITE, CH_OFF, false)
	_plate([Vector3(-w + 0.04, ws0.y - 0.04, ws0.x - 0.006), Vector3(w - 0.04, ws0.y - 0.04, ws0.x - 0.006), Vector3(w - 0.06, ws1.y + 0.05, ws1.x - 0.006),
		Vector3(-w + 0.06, ws1.y + 0.05, ws1.x - 0.006)], 0.008, "metal", GLOSS, CH_OFF, false)
	_plate([Vector3(w + 0.004, 1.95, nz + 0.25), Vector3(w + 0.004, 2.75, nz + 0.3), Vector3(w + 0.004, 2.75, -3.15), Vector3(w + 0.004, 1.95, -3.15)],
		0.008, "dark_glass")
	_shut_lines([nz + 0.2, -3.05], 1.2, 2.85, w)
	_handles([-3.2], 1.75, w, "trim", BLACK)
	# Sun visor, roof deflector, roof marker lamps.
	_box(Vector3(w * 2.0 - 0.05, 0.03, 0.3), Vector3(0.0, cab_top - 0.1, nz + 0.05), "trim", BLACK, Vector3(deg_to_rad(-8.0), 0.0, 0.0))
	var defl := _pts([[nz + 0.5, cab_top], [nz + 0.75, cab_top + 0.45], [cab_back - 0.1, cab_top + 0.62], [cab_back, cab_top + 0.62], [cab_back, cab_top]])
	_prism(defl, -w + 0.12, w - 0.12, 0.08, "paint")
	for x in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		_box(Vector3(0.1, 0.04, 0.04), Vector3(x, cab_top - 0.02, nz + 0.17), "lamps", LENS_AMBER, Vector3.ZERO, CH_MARKER)
	# The grille, the bumper with the headlamps in its corners, a step under each door.
	_box(Vector3(w * 1.3, 0.55, 0.03), Vector3(0.0, 1.55, nz - 0.01), "metal", GLOSS)
	if not lo:
		for i in 5:
			_box(Vector3(w * 1.26, 0.035, 0.015), Vector3(0.0, 1.33 + i * 0.11, nz - 0.026), "metal", SATIN if trim != 0 else CHROME)
	_prism(_pts([[nz - 0.05, 0.55], [nz - 0.06, 1.22], [nz + 0.3, 1.22], [nz + 0.3, 0.55]]), -w - 0.01, w + 0.01, 0.06, "trim", GREY.darkened(0.4))
	for side in [1.0, -1.0]:
		_box(Vector3(0.36, 0.16, 0.02), Vector3(side * (w - 0.27), 1.0, nz - 0.066), "metal", SATIN.darkened(0.5))
		_box(Vector3(0.24, 0.12, 0.012), Vector3(side * (w - 0.31), 1.0, nz - 0.078), "lamps", LENS_WHITE, Vector3.ZERO, CH_HEAD)
		var ind := CH_RIGHT if side > 0.0 else CH_LEFT
		_box(Vector3(0.08, 0.12, 0.012), Vector3(side * (w - 0.09), 1.0, nz - 0.078), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.012, 0.1, 0.18), Vector3(side * (w + 0.004), 1.3, nz + 0.4), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.12, 0.08, 0.012), Vector3(side * (w - 0.4), 0.72, nz - 0.07), "lamps", LENS_WHITE, Vector3.ZERO, CH_OFF)
		for y in [0.75, 0.42]:
			_box(Vector3(0.18, 0.03, 0.22), Vector3(side * (w - 0.1), y, -2.58), "metal", SATIN)
		# Big mirrors on arms off the cab's front corners.
		_box(Vector3(0.3, 0.03, 0.03), Vector3(side * (w + 0.12), 2.6, nz + 0.25), "trim", BLACK)
		_box(Vector3(0.04, 0.42, 0.16), Vector3(side * (w + 0.27), 2.35, nz + 0.25), "trim", BLACK)
		if not lo:
			_box(Vector3(0.006, 0.38, 0.13), Vector3(side * (w + 0.25), 2.35, nz + 0.335), "metal", CHROME, Vector3(0.0, side * 1.2, 0.0))
	_number_plate(nz - 0.07, 0.72, true)
	# The chassis: rails, fuel tank, air tanks, side guards between the axles, mudguards over the back wheels.
	var ra := float(s["axles"][1])
	_boxes(Vector3(0.1, 0.28, 4.3 - cab_back - 0.1), Vector3(0.45, 0.98, (cab_back + 4.3) * 0.5), "trim", UNDER)
	_cyl(0.28, 0.9, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-w + 0.35, 0.82, -1.7)), "metal", CHROME if trim == 0 else SATIN, 18)
	_cyl(0.13, 0.6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(w - 0.3, 0.85, -1.7)), "trim", GREY, 12)
	for y in [0.62, 0.9]:
		_boxes(Vector3(0.03, 0.09, ra - 0.9 - (-1.1)), Vector3(w - 0.04, y, (-1.1 + ra - 0.9) * 0.5), "metal", SATIN.lightened(0.2))
	var guard := CarModel.arc(Vector2(ra, r), r + 0.12, 0.0, PI, 8 if lo else 14)
	guard.append_array(CarModel.arc(Vector2(ra, r), r + 0.08, PI, 0.0, 8 if lo else 14))
	_prisms(guard, w - 0.6, w - 0.01, 0.01, "trim", BLACK)
	# The rear under-run bar with the tail lamps, and the box body over it all.
	_box(Vector3(w * 2.0 - 0.1, 0.14, 0.12), Vector3(0.0, 0.62, 4.2), "metal", SATIN)
	for side in [1.0, -1.0]:
		var ind := CH_RIGHT if side > 0.0 else CH_LEFT
		_box(Vector3(0.3, 0.14, 0.04), Vector3(side * (w - 0.3), 0.9, 4.27), "trim", BLACK)
		_box(Vector3(0.1, 0.11, 0.012), Vector3(side * (w - 0.4), 0.9, 4.292), "lamps", LENS_RED, Vector3.ZERO, CH_TAIL)
		_box(Vector3(0.08, 0.11, 0.012), Vector3(side * (w - 0.3), 0.9, 4.292), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.08, 0.11, 0.012), Vector3(side * (w - 0.2), 0.9, 4.292), "lamps", LENS_RED, Vector3.ZERO, CH_BRAKE)
		# Marker lamps at the box's top corners, front and back, and along its sides.
		_box(Vector3(0.06, 0.06, 0.02), Vector3(side * (w - 0.05), 3.72, 4.32), "lamps", LENS_RED, Vector3.ZERO, CH_TAIL)
		_box(Vector3(0.06, 0.06, 0.02), Vector3(side * (w - 0.05), 3.72, -2.32), "lamps", LENS_WHITE, Vector3.ZERO, CH_MARKER)
		for z in [-1.2, 0.4, 2.0, 3.6]:
			_box(Vector3(0.01, 0.04, 0.08), Vector3(side * (w + 0.06), 1.12, z), "lamps", LENS_AMBER, Vector3.ZERO, CH_MARKER)
	_number_plate(4.3, 0.62, false)
	var box := _pts([[-2.3, 1.18], [-2.3, 3.8], [4.3, 3.8], [4.3, 1.18]])
	_prism(box, -w - 0.05, w + 0.05, 0.03, "paint2")
	_box(Vector3(w * 2.0 + 0.1, 0.14, 6.6), Vector3(0.0, 1.11, 1.0), "trim", UNDER)
	if not lo:
		for z in [-2.3, 4.3]:
			_boxes(Vector3(0.06, 2.64, 0.06), Vector3(w + 0.035, 2.49, z), "metal", SATIN.lightened(0.3))
		_boxes(Vector3(0.05, 0.06, 6.6), Vector3(w + 0.035, 3.78, 1.0), "metal", SATIN.lightened(0.3))
		_boxes(Vector3(0.05, 0.08, 6.6), Vector3(w + 0.035, 1.22, 1.0), "metal", SATIN.lightened(0.3))
		for k in 12:
			_box(Vector3(w * 2.0 - 0.05, 0.008, 0.008), Vector3(0.0, 1.35 + k * 0.2, 4.305), "trim", GREY)
		_box(Vector3(0.3, 0.04, 0.03), Vector3(0.0, 1.32, 4.32), "metal", CHROME)
	# The livery: a band along the box in the cab's colour (or the trim's own colour).
	if trim != 1:
		_boxes(Vector3(0.01, 0.7, 5.6), Vector3(w + 0.056, 2.65 if trim == 0 else 1.75, 1.0), "paint")
	else:
		_boxes(Vector3(0.01, 2.2, 1.1), Vector3(w + 0.056, 2.5, -1.4), "paint")
	_cyl(0.05, 0.6, Transform3D(Basis(), Vector3(-w + 0.08, cab_top + 0.0, cab_back - 0.1)), "metal", CHROME if trim == 0 else SATIN, 10)


## The coach (trims 0 and 2) or a service bus (trim 1): one long body, a big raked windscreen,
## a band of dark glass down each side (deeper on the bus, with its doors), luggage lockers or
## a destination board, the engine grille at the back, livery stripes, a roof air-con pod.
func _coach() -> void:
	var w := float(s["w"])
	var r := float(s["r"])
	var ar := r + 0.08
	var sill := 0.42 if trim != 1 else 0.3
	var nz := -6.05
	var tz := 6.05
	var roof := 3.45 if trim != 1 else 3.1
	var bus := trim == 1
	var top := [[nz + 0.05, sill], [nz, 1.1], [nz + 0.1, roof - 0.25], [nz + 0.3, roof], [tz - 0.15, roof], [tz, roof - 0.15], [tz + 0.02, sill]]
	_prism(_outline(top, sill, ar), -w, w, 0.08, "paint")
	_arches(sill, ar, w, false)
	var win0 := 1.75 if not bus else 1.2
	var win1 := roof - 0.4
	# Side glass: one band each side with black pillars across it, the windscreen and back window.
	var zf := nz + 0.55
	var zr := tz - 0.35
	_plate([Vector3(w + 0.004, win0, zf), Vector3(w + 0.004, win1, zf + 0.08), Vector3(w + 0.004, win1, zr), Vector3(w + 0.004, win0, zr)], 0.008, "dark_glass")
	if not lo:
		var bays := int((zr - zf) / 1.35)
		for k in range(1, bays):
			_boxes(Vector3(0.012, win1 - win0, 0.07), Vector3(w + 0.008, (win0 + win1) * 0.5, zf + k * (zr - zf) / bays), "metal", GLOSS)
	_boxes(Vector3(0.012, 0.05, zr - zf), Vector3(w + 0.007, win0, (zf + zr) * 0.5), "metal", GLOSS)
	var a0 := Vector2(nz + 0.005, 1.15)
	var a1 := Vector2(nz + 0.12, roof - 0.28)
	_plate([Vector3(-w + 0.06, a0.y, a0.x - 0.012), Vector3(w - 0.06, a0.y, a0.x - 0.012), Vector3(w - 0.08, a1.y, a1.x - 0.012),
		Vector3(-w + 0.08, a1.y, a1.x - 0.012)], 0.01, "dark_glass", Color.WHITE, CH_OFF, false)
	_plate([Vector3(-w + 0.12, roof - 0.55, tz + 0.012), Vector3(w - 0.12, roof - 0.55, tz + 0.012), Vector3(w - 0.12, roof - 0.25, tz + 0.012),
		Vector3(-w + 0.12, roof - 0.25, tz + 0.012)], 0.01, "dark_glass", Color.WHITE, CH_OFF, false)
	if bus:
		# The doors: glass from the floor up, front and middle, and the destination board.
		for z in [nz + 0.25, -0.2]:
			_plate([Vector3(-w - 0.006, 0.38, z), Vector3(-w - 0.006, win1, z), Vector3(-w - 0.006, win1, z + 1.1), Vector3(-w - 0.006, 0.38, z + 1.1)],
				0.01, "dark_glass", Color.WHITE, CH_OFF, false)
			if not lo:
				_box(Vector3(0.016, win1 - 0.38, 0.03), Vector3(-w - 0.008, (win1 + 0.38) * 0.5, z + 0.55), "metal", SATIN)
		_box(Vector3(w * 1.5, 0.22, 0.02), Vector3(0.0, roof - 0.15, nz + 0.25), "metal", GLOSS)
		_box(Vector3(w * 1.4, 0.15, 0.01), Vector3(0.0, roof - 0.15, nz + 0.237), "lamps", Color(1.0, 0.62, 0.1), Vector3.ZERO, CH_MARKER)
	else:
		# Luggage locker doors below the windows, the coach line's name band.
		_shut_lines([-3.0 + ar, -1.5, 0.0, 1.5, 3.0 - ar - 0.6], sill + 0.1, 1.55, w)
		if not lo:
			_boxes(Vector3(0.004, 0.005, 5.4), Vector3(w + 0.0015, 1.55, -0.05), "trim", UNDER)
			_handles([-2.25, -0.75, 0.75], 1.0, w, "metal", SATIN)
		_plate([Vector3(w + 0.004, 0.42, nz + 0.25), Vector3(w + 0.004, win0 - 0.05, nz + 0.25), Vector3(w + 0.004, win0 - 0.05, nz + 1.05),
			Vector3(w + 0.004, 0.42, nz + 1.05)], 0.008, "dark_glass", Color.WHITE, CH_OFF, false)
		_plate([Vector3(-w - 0.004, 0.42, nz + 0.25), Vector3(-w - 0.004, win0 - 0.05, nz + 0.25), Vector3(-w - 0.004, win0 - 0.05, nz + 1.05),
			Vector3(-w - 0.004, 0.42, nz + 1.05)], 0.008, "dark_glass", Color.WHITE, CH_OFF, false)
	# Livery stripes under the windows (and a sweep up the back on the coach).
	_boxes(Vector3(0.01, 0.16, tz - nz - 1.0), Vector3(w + 0.006, win0 - 0.16, 0.2), "paint2")
	_boxes(Vector3(0.01, 0.06, tz - nz - 1.0), Vector3(w + 0.006, win0 - 0.32, 0.2), "paint2")
	if not bus:
		_plate([Vector3(w + 0.007, win0 - 0.4, 3.0), Vector3(w + 0.007, win0 - 0.08, 3.0), Vector3(w + 0.007, roof - 0.1, 5.2), Vector3(w + 0.007, roof - 0.42, 5.2)],
			0.006, "paint2", Color.WHITE)
	# The front: bumper and grille, headlamp clusters, wipers; rabbit-ear mirrors.
	_prism(_pts([[nz - 0.04, sill], [nz - 0.045, 0.85], [nz + 0.3, 0.85], [nz + 0.3, sill]]), -w - 0.01, w + 0.01, 0.08, "trim", GREY.darkened(0.45))
	_box(Vector3(w * 1.0, 0.18, 0.03), Vector3(0.0, 0.62, nz - 0.055), "metal", GLOSS)
	for side in [1.0, -1.0]:
		var ind := CH_RIGHT if side > 0.0 else CH_LEFT
		_box(Vector3(0.5, 0.18, 0.02), Vector3(side * (w - 0.32), 0.98, nz - 0.01), "metal", SATIN.darkened(0.5))
		_box(Vector3(0.3, 0.13, 0.012), Vector3(side * (w - 0.4), 0.98, nz - 0.022), "lamps", LENS_WHITE, Vector3.ZERO, CH_HEAD)
		_box(Vector3(0.1, 0.13, 0.012), Vector3(side * (w - 0.14), 0.98, nz - 0.022), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.012, 0.06, 0.18), Vector3(side * (w + 0.004), 1.0, nz + 0.6), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.05, 0.05, 0.6), Vector3(side * (w - 0.05), roof - 0.1, nz - 0.2), "trim", BLACK, Vector3(deg_to_rad(10.0), 0.0, 0.0))
		_box(Vector3(0.05, 0.42, 0.18), Vector3(side * (w - 0.08), roof - 0.45, nz - 0.48), "trim", BLACK)
		if not lo:
			_box(Vector3(0.04, 0.38, 0.006), Vector3(side * (w - 0.08), roof - 0.45, nz - 0.39), "metal", CHROME)
		# The back: tall lamp clusters, the engine grille, side markers.
		_box(Vector3(0.16, 0.7, 0.02), Vector3(side * (w - 0.12), 1.1, tz + 0.012), "metal", GLOSS)
		_box(Vector3(0.12, 0.2, 0.012), Vector3(side * (w - 0.12), 1.3, tz + 0.024), "lamps", LENS_RED, Vector3.ZERO, CH_TAIL)
		_box(Vector3(0.12, 0.15, 0.012), Vector3(side * (w - 0.12), 1.1, tz + 0.024), "lamps", LENS_RED, Vector3.ZERO, CH_BRAKE)
		_box(Vector3(0.12, 0.13, 0.012), Vector3(side * (w - 0.12), 0.92, tz + 0.024), "lamps", LENS_AMBER, Vector3.ZERO, ind)
		_box(Vector3(0.12, 0.1, 0.012), Vector3(side * (w - 0.12), 0.8, tz + 0.024), "lamps", LENS_WHITE, Vector3.ZERO, CH_OFF)
		for z in [-4.0, -1.0, 2.0, 4.6]:
			_box(Vector3(0.008, 0.035, 0.08), Vector3(side * (w + 0.004), sill + 0.15, z), "lamps", LENS_AMBER, Vector3.ZERO, CH_MARKER)
		_box(Vector3(0.05, 0.05, 0.02), Vector3(side * (w - 0.1), roof - 0.06, tz + 0.01), "lamps", LENS_RED, Vector3.ZERO, CH_TAIL)
		_box(Vector3(0.05, 0.05, 0.02), Vector3(side * (w - 0.1), roof - 0.06, nz + 0.24), "lamps", LENS_AMBER, Vector3.ZERO, CH_MARKER)
	_box(Vector3(w * 1.3, 0.75, 0.02), Vector3(0.0, 1.45, tz + 0.012), "metal", GLOSS)
	if not lo:
		for k in 8:
			_box(Vector3(w * 1.26, 0.02, 0.01), Vector3(0.0, 1.14 + k * 0.088, tz + 0.025), "metal", SATIN)
		for x in [-0.35, 0.35]:
			_box(Vector3(0.7, 0.012, 0.02), Vector3(x, 1.25, nz - 0.01), "trim", BLACK, Vector3(0.0, 0.0, deg_to_rad(8.0 if x < 0.0 else -8.0)))
	_box(Vector3(0.5, 0.035, 0.02), Vector3(0.0, roof - 0.12, tz + 0.012), "lamps", LENS_RED, Vector3.ZERO, CH_BRAKE)
	_prism(_pts([[tz + 0.05, sill], [tz + 0.055, 0.72], [tz - 0.25, 0.72], [tz - 0.25, sill]]), -w - 0.01, w + 0.01, 0.08, "trim", GREY.darkened(0.45))
	_number_plate(nz - 0.06, 0.55, true)
	_number_plate(tz + 0.065, 0.5, false)
	# Roof air-con pod, and the floor pan.
	_prism(_pts([[-2.4, roof - 0.02], [-2.3, roof + 0.18], [1.2, roof + 0.18], [1.3, roof - 0.02]]), -w + 0.25, w - 0.25, 0.08, "trim", GREY.lightened(0.3))
	_box(Vector3(w * 2.0 - 0.3, 0.2, tz - nz - 1.2), Vector3(0.0, sill, 0.0), "trim", UNDER)


# ---------------------------------------------------------------------------- wheels

## One wheel at the origin, its outer face +x: the tyre and the kind's (and trim's) wheel.
## `twin`: a second tyre and rim inside it, for a lorry's back axle.
func _wheel_items(low: bool, twin: bool) -> Array:
	var r := float(s["r"])
	var tw := float(s["tw"]) * 0.5
	var big := kind in ["lorry", "coach"]
	var sides := 12 if low else 36
	var out := []
	var rim := 0.8 if kind == "supercar" else 0.66   # low-profile tyres on big rims
	var wall := lerpf(rim, 1.0, 0.6)
	var tyre := [Vector2(r * rim, -tw), Vector2(r * wall, -tw * 1.08), Vector2(r - 0.012, -tw * 0.98), Vector2(r, -tw * 0.82),
		Vector2(r, tw * 0.82), Vector2(r - 0.012, tw * 0.98), Vector2(r * wall, tw * 1.08), Vector2(r * rim, tw)]
	var rim_r := r * rim
	var style := "steel" if kind == "van" and trim != 1 else ("dark" if trim == 2 else "alloy")
	if big:
		style = "truck"
	var rim_col := RIM if style == "alloy" else (RIM_DARK if style == "dark" else (SATIN.lightened(0.25) if style == "steel" else Color(0.75, 0.75, 0.73)))
	var offsets := [0.0]
	if twin:
		offsets.append(-tw * 2.0 - 0.03)
	for o in offsets:
		var xf := Transform3D(Basis(), Vector3(o, 0.0, 0.0))
		out.append([CarModel.lathe(tyre, sides), xf, "trim", TYRE, CH_OFF])
		var barrel := [Vector2(rim_r + 0.006, tw * 0.95), Vector2(rim_r + 0.006, -tw * 0.9), Vector2(rim_r * 0.92, -tw), Vector2(rim_r * 0.88, 0.0),
			Vector2(rim_r * 0.3, tw * 0.2)]
		out.append([CarModel.lathe(barrel, maxi(sides - 8, 10)), xf, "metal", RIM_DARK, CH_OFF])
	var face := tw * 0.85
	if style == "alloy" or style == "dark":
		var lip := [Vector2(rim_r + 0.008, face), Vector2(rim_r + 0.008, face + 0.012), Vector2(rim_r * 0.92, face + 0.01)]
		out.append([CarModel.lathe(lip, maxi(sides - 8, 10)), Transform3D(), "metal", rim_col, CH_OFF])
		if not low:
			for k in 5:
				var b := Basis(Vector3.RIGHT, TAU * k / 5.0)
				for d in [-0.11, 0.11]:
					var spoke := BoxMesh.new()
					spoke.size = Vector3(0.025, rim_r * 0.78, rim_r * 0.14)
					out.append([spoke, Transform3D(b * Basis(Vector3.RIGHT, d), b * Vector3(face - 0.01, rim_r * 0.5, 0.0)), "metal", rim_col, CH_OFF])
	elif style == "steel":
		var disc := [Vector2(rim_r + 0.004, face - 0.005), Vector2(rim_r * 0.9, face + 0.01), Vector2(rim_r * 0.55, face + 0.02), Vector2(rim_r * 0.35, face + 0.005),
			Vector2(0.0, face + 0.012)]
		out.append([CarModel.lathe(disc, maxi(sides - 8, 10)), Transform3D(), "metal", rim_col, CH_OFF])
	else:
		# A lorry or coach's steel wheel: the dished disc, its hand holes and ten studs.
		var disc := [Vector2(rim_r + 0.004, face - 0.02), Vector2(rim_r * 0.85, face - 0.01), Vector2(rim_r * 0.55, face + 0.02), Vector2(rim_r * 0.4, face + 0.06),
			Vector2(0.0, face + 0.07)]
		out.append([CarModel.lathe(disc, maxi(sides - 8, 10)), Transform3D(), "metal", rim_col, CH_OFF])
		if not low:
			for k in 10:
				var b := Basis(Vector3.RIGHT, TAU * k / 10.0)
				var stud := CylinderMesh.new()
				stud.top_radius = 0.014
				stud.bottom_radius = 0.014
				stud.height = 0.03
				stud.radial_segments = 6
				stud.rings = 1
				out.append([stud, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), b * Vector3(face + 0.075, rim_r * 0.33, 0.0)), "metal", CHROME, CH_OFF])
			for k in 6:
				var b := Basis(Vector3.RIGHT, TAU * (k + 0.5) / 6.0)
				var hole := BoxMesh.new()
				hole.size = Vector3(0.01, 0.06, 0.08)
				out.append([hole, Transform3D(b, b * Vector3(face + 0.03, rim_r * 0.68, 0.0)), "trim", UNDER, CH_OFF])
	var cap := [Vector2(rim_r * 0.22, face + 0.005), Vector2(rim_r * 0.18, face + 0.025), Vector2(0.0, face + 0.03)]
	out.append([CarModel.lathe(cap, 12), Transform3D(), "metal", CHROME if trim == 0 else rim_col, CH_OFF])
	return out


## Where each wheel sits: [[x, z, front], ...] (x of its outer face's middle line).
func wheel_spots() -> Array:
	var out := []
	var w := float(s["w"])
	var tw := float(s["tw"])
	var axles: Array = s["axles"]
	for i in axles.size():
		for side in [1.0, -1.0]:
			out.append([side * (w - tw * 0.5 - 0.04), float(axles[i]), i == 0])
	return out


static func _place(items_in: Array, xf: Transform3D) -> Array:
	var out := []
	for it in items_in:
		out.append([it[0], xf * (it[1] as Transform3D), it[2], it[3], it[4]])
	return out


## Both back wheels as one piece about the back axle's middle (the axle turns them together).
func _axle_items(low: bool) -> Array:
	var out := []
	var one := _wheel_items(low, bool(s["dual"]))
	for spot in wheel_spots():
		if spot[2]:
			continue
		var xf := Transform3D(Basis() if spot[0] > 0.0 else Basis(Vector3.UP, PI), Vector3(spot[0], 0.0, 0.0))
		out.append_array(_place(one, xf))
	return out


## The far mesh's wheels, baked in where they sit.
func _wheels_baked() -> Array:
	var out := []
	var r := float(s["r"])
	var one := _wheel_items(true, false)
	var twin := _wheel_items(true, bool(s["dual"]))
	for spot in wheel_spots():
		var xf := Transform3D(Basis() if spot[0] > 0.0 else Basis(Vector3.UP, PI), Vector3(spot[0], r, spot[1]))
		out.append_array(_place(twin if not spot[2] else one, xf))
	return out
