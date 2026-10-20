class_name ToolModels
## Hand tool models built from primitive meshes, held in one hand: the first-person tool view
## (Walker) and other players' avatars (RemotePlayer). Forward is -Z, up is +Y, nothing casts
## shadows. Tools: "wrench" (combination spanner), "brush" (wire brush), "repair" (angle
## grinder), "spray" (aerosol can, tinted can_color), "lance" (pressure washer gun and lance,
## nozzle at (0, 0, -0.6)), "gun" (HVLP paint gun, cup tinted can_color, nozzle near
## (0, 0.02, -0.12)), "polisher" (a dual-action polisher, its foam pad facing forward at
## (0, 0, -0.17)), "applicator" (a ceramic coating applicator block in your fingers) and
## "stopwatch" (turn its hand with set_hand_angle / set_hand_seconds).
## Tools with a nozzle carry it as the "nozzle" meta (a local Vector3).
## `stage` (0..5, the tool's upgrade stage, see Progress) dresses it up: bare steel, polished,
## chrome, anodised, carbon, then gold trim.

static var _mats := {}
static var _staged := {}


static func make(which: String, can_color := Color(0.9, 0.75, 0.1), stage := 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_" + which
	match which:
		"wrench":
			_spanner(root)
		"brush":
			_brush(root)
		"repair":
			_grinder(root)
		"spray":
			_spray_can(root, can_color)
		"lance":
			_lance(root)
		"gun":
			_paint_gun(root, can_color)
		"polisher":
			_polisher(root)
		"applicator":
			_applicator(root)
		"stopwatch":
			_stopwatch(root)
		_:
			pass  # bare hands: nothing to draw
	if stage > 0:
		apply_stage(root, stage)
	root.set_meta("stage", stage)
	return root


## Gives every part of a tool model the finish of an upgrade stage: metal gets polished, then
## chromed, then gold; coloured bodies go glossy, then anodised, then carbon. The paint colour
## of a can or cup, glass, rubber and wood grips keep their look (wood gets lacquered).
static func apply_stage(root: Node, stage: int) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			var mi := c as MeshInstance3D
			mi.material_override = _stage_mat(mi.material_override as StandardMaterial3D, stage)
		apply_stage(c, stage)


static func _stage_mat(m: StandardMaterial3D, stage: int) -> StandardMaterial3D:
	var key := "%d:%d" % [m.get_instance_id(), stage]
	if _staged.has(key):
		return _staged[key]
	var out := m
	var c := m.albedo_color
	var lum := c.get_luminance()
	if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not m.has_meta("tint"):
		out = m.duplicate() as StandardMaterial3D
		var brass := c.r > 0.75 and c.g > 0.55 and c.b < 0.4 and m.metallic > 0.5
		var wood := m.metallic < 0.1 and c.r > c.b * 1.6 and c.r < 0.6 and lum < 0.45
		if m.metallic >= 0.5:
			# Steel and aluminium: polished, then chrome, then gold.
			if stage >= 5 or (brass and stage >= 4):
				_pbr(out, Color(0.96, 0.76, 0.32), 1.0, 0.14)
			elif stage >= 2:
				_pbr(out, Color(0.92, 0.93, 0.96), 1.0, 0.07)
			else:
				out.roughness = m.roughness * 0.5
		elif wood:
			if stage >= 3:
				_pbr(out, c.darkened(0.25), 0.0, 0.18)
				out.clearcoat_enabled = true
		elif lum > 0.2:
			# A coloured body (the grinder, the pressure washer): glossy, anodised, then carbon.
			if stage >= 4:
				_pbr(out, Color(0.07, 0.07, 0.08), 0.35, 0.16)
				out.clearcoat_enabled = true
			elif stage >= 3:
				_pbr(out, Color.from_hsv(c.h, minf(1.0, c.s * 1.2 + 0.1), maxf(0.45, c.v * 0.9)), 0.75, 0.22)
			else:
				out.roughness = m.roughness * (0.7 if stage == 1 else 0.45)
		elif stage >= 4 and m.roughness > 0.4 and m.roughness < 0.6:
			# Black plastic housings turn to carbon.
			_pbr(out, Color(0.06, 0.06, 0.07), 0.35, 0.18)
			out.clearcoat_enabled = true
	_staged[key] = out
	return out


## Turns a stopwatch's hand: radians clockwise from twelve o'clock.
static func set_hand_angle(stopwatch: Node3D, radians: float) -> void:
	var hand := stopwatch.get_node_or_null("Hand") as Node3D
	if hand:
		hand.rotation.z = -radians


## Shows a time on a stopwatch: the big hand sweeps once a minute, the small one once an hour.
static func set_hand_seconds(stopwatch: Node3D, seconds: float) -> void:
	set_hand_angle(stopwatch, fposmod(seconds, 60.0) / 60.0 * TAU)
	var minutes := stopwatch.get_node_or_null("MinuteHand") as Node3D
	if minutes:
		minutes.rotation.z = -fposmod(seconds / 60.0, 30.0) / 30.0 * TAU


# ---------------------------------------------------------------------------- materials

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"chrome":
			_pbr(m, Color(0.88, 0.89, 0.92), 0.72, 0.18)
		"steel":
			_pbr(m, Color(0.66, 0.67, 0.7), 0.65, 0.38)
		"alu":
			_pbr(m, Color(0.7, 0.71, 0.72), 0.7, 0.45)
		"dark_steel":
			_pbr(m, Color(0.2, 0.2, 0.22), 0.7, 0.45)
		"rubber":
			_pbr(m, Color(0.06, 0.06, 0.065), 0.0, 0.8)
		"plastic_black":
			_pbr(m, Color(0.08, 0.08, 0.09), 0.0, 0.45)
		"wood":
			_pbr(m, Color(0.5, 0.31, 0.15), 0.0, 0.62)
		"wood_dark":
			_pbr(m, Color(0.3, 0.17, 0.08), 0.0, 0.7)
		"wire":
			_pbr(m, Color(0.75, 0.73, 0.68), 0.8, 0.5)
		"brass":
			_pbr(m, Color(0.85, 0.66, 0.3), 0.9, 0.3)
		"grinder_body":
			_pbr(m, Color(0.08, 0.36, 0.62), 0.0, 0.35)
		"red":
			_pbr(m, Color(0.78, 0.1, 0.07), 0.0, 0.4)
		"orange":
			_pbr(m, Color(0.95, 0.42, 0.05), 0.0, 0.4)
		"yellow":
			_pbr(m, Color(0.97, 0.76, 0.06), 0.0, 0.35)
		"white":
			_pbr(m, Color(0.94, 0.94, 0.92), 0.0, 0.3)
		"abrasive":
			_pbr(m, Color(0.22, 0.21, 0.2), 0.1, 0.95)
		"face":
			_pbr(m, Color(0.97, 0.96, 0.92), 0.0, 0.25)
		"ink":
			_pbr(m, Color(0.06, 0.06, 0.07), 0.0, 0.5)
		"glass":
			_pbr(m, Color(0.9, 0.95, 1.0, 0.12), 0.0, 0.05)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"hole":
			_pbr(m, Color(0.02, 0.02, 0.02), 0.0, 1.0)
		_:
			_pbr(m, Color.MAGENTA, 0.0, 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func _tint(color: Color, metallic: float, roughness: float, alpha := 1.0) -> StandardMaterial3D:
	var key := "tint_%s_%.2f_%.2f_%.2f" % [color.to_html(false), metallic, roughness, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_pbr(m, Color(color, alpha), metallic, roughness)
	m.set_meta("tint", true)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func _pbr(m: StandardMaterial3D, c: Color, metallic: float, roughness: float) -> void:
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	m.metallic_specular = 0.6


# ---------------------------------------------------------------------------- mesh helpers

static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A cylinder along Y (rotate x by PI/2 to point it along Z, z by PI/2 for X).
static func _cyl(top: float, bottom: float, height: float, segments := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _sphere(radius: float, height: float, hemisphere := false, segments := 20) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	s.is_hemisphere = hemisphere
	s.radial_segments = segments
	s.rings = 10
	return s


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 4
	return c


## A torus lying in the XZ plane (axis Y).
static func _torus(inner: float, outer: float, rings := 24) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = 8
	return t


## A flat solid ring segment in the XY plane, thickness along Z: from angle a0 to a1 (radians,
## 0 = +X, counterclockwise seen from +Z). A full turn makes a washer; less makes a C or a jaw.
static func _ring_solid(r_in: float, r_out: float, thick: float, a0: float, a1: float, seg := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := thick * 0.5
	var full := absf(a1 - a0) >= TAU - 0.001
	for i in seg:
		var t0 := a0 + (a1 - a0) * float(i) / seg
		var t1 := a0 + (a1 - a0) * float(i + 1) / seg
		var d0 := Vector3(cos(t0), sin(t0), 0.0)
		var d1 := Vector3(cos(t1), sin(t1), 0.0)
		var i0 := d0 * r_in
		var o0 := d0 * r_out
		var i1 := d1 * r_in
		var o1 := d1 * r_out
		var f := Vector3(0, 0, hz)
		var b := Vector3(0, 0, -hz)
		_quad(st, i0 + f, o0 + f, o1 + f, i1 + f)       # front
		_quad(st, i1 + b, o1 + b, o0 + b, i0 + b)       # back
		_quad(st, o0 + f, o0 + b, o1 + b, o1 + f)       # outer wall
		_quad(st, i1 + f, i1 + b, i0 + b, i0 + f)       # inner wall
	if not full:
		var e0 := Vector3(cos(a0), sin(a0), 0.0)
		var e1 := Vector3(cos(a1), sin(a1), 0.0)
		_quad(st, e0 * r_in + Vector3(0, 0, -hz), e0 * r_out + Vector3(0, 0, -hz), e0 * r_out + Vector3(0, 0, hz), e0 * r_in + Vector3(0, 0, hz))
		_quad(st, e1 * r_in + Vector3(0, 0, hz), e1 * r_out + Vector3(0, 0, hz), e1 * r_out + Vector3(0, 0, -hz), e1 * r_in + Vector3(0, 0, -hz))
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot's front faces wind clockwise.
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	st.add_vertex(a)
	st.add_vertex(d)
	st.add_vertex(c)


# ---------------------------------------------------------------------------- the tools

## A chrome combination spanner, long axis Y: open jaw at the top, ring at the bottom.
static func _spanner(root: Node3D) -> void:
	var chrome := _mat("chrome")
	var steel := _mat("steel")
	# The shaft: a thin web with raised edges, like a forged I-section.
	_add(root, _box(Vector3(0.013, 0.15, 0.005)), steel, Vector3(0, 0.0, 0))
	for x in [-0.0072, 0.0072]:
		_add(root, _box(Vector3(0.0035, 0.152, 0.0085)), chrome, Vector3(x, 0.0, 0))
	# Necks flaring into each end.
	_add(root, _cyl(0.0105, 0.0085, 0.03, 4), chrome, Vector3(0, 0.08, 0), Vector3(0, PI * 0.25, 0), Vector3(1.0, 1.0, 0.42))
	_add(root, _cyl(0.0085, 0.0115, 0.026, 4), chrome, Vector3(0, -0.082, 0), Vector3(0, PI * 0.25, 0), Vector3(1.0, 1.0, 0.42))
	# Open end, angled 15 degrees off the shaft, jaws opening upward.
	var open := Node3D.new()
	open.position = Vector3(0, 0.106, 0)
	open.rotation.z = deg_to_rad(15.0)
	root.add_child(open)
	var gap := deg_to_rad(64.0)
	_add(open, _ring_solid(0.0095, 0.0215, 0.0085, PI * 0.5 + gap * 0.5, PI * 2.5 - gap * 0.5, 28), chrome, Vector3.ZERO)
	# The flats inside the jaw, so it reads as an open-ended spanner.
	for s in [-1.0, 1.0]:
		_add(open, _box(Vector3(0.006, 0.016, 0.0085)), chrome, Vector3(s * 0.0128, 0.012, 0), Vector3(0, 0, -s * 0.12))
	# Ring end: a 12-point ring, slightly offset (cranked) like a real one.
	var ring := Node3D.new()
	ring.position = Vector3(0, -0.105, 0.0015)
	ring.rotation.x = deg_to_rad(-10.0)
	root.add_child(ring)
	_add(ring, _ring_solid(0.0085, 0.0185, 0.0095, 0.0, TAU, 32), chrome, Vector3.ZERO)
	_add(ring, _ring_solid(0.0078, 0.0088, 0.0085, 0.0, TAU, 12), _mat("dark_steel"), Vector3.ZERO)
	# A stamped size panel in the web.
	_add(root, _box(Vector3(0.008, 0.03, 0.0056)), _mat("dark_steel"), Vector3(0, -0.035, 0))


## A wire brush: a long varnished wooden stock with rows of steel wire tufts facing forward.
static func _brush(root: Node3D) -> void:
	var wood := _mat("wood")
	var dark := _mat("wood_dark")
	# Handle: an oval, slightly swelled grip with a hanging hole at the end.
	_add(root, _capsule(0.0125, 0.15), wood, Vector3(0, -0.075, 0.004), Vector3.ZERO, Vector3(1.25, 1.0, 0.75))
	_add(root, _cyl(0.0045, 0.0045, 0.022, 12), _mat("hole"), Vector3(0, -0.135, 0.004), Vector3(PI * 0.5, 0, 0))
	# The head stock the wires are set into.
	_add(root, _box(Vector3(0.04, 0.12, 0.02)), wood, Vector3(0, 0.055, 0))
	_add(root, _cyl(0.02, 0.02, 0.02, 20), wood, Vector3(0, 0.115, 0), Vector3(PI * 0.5, 0, 0))
	_add(root, _box(Vector3(0.036, 0.13, 0.004)), dark, Vector3(0, 0.06, -0.0095))
	# Wire tufts: 4 staggered rows of 12, flaring slightly at the tips.
	var tuft := _cyl(0.0036, 0.0022, 0.028, 6)
	var wire := _mat("wire")
	for row in 4:
		for col in 12:
			var x := (row - 1.5) * 0.0095
			var y := 0.008 + col * 0.0098 + (0.0049 if row % 2 == 1 else 0.0)
			_add(root, tuft, wire, Vector3(x, y, -0.025), Vector3(PI * 0.5, 0, 0))
	# A steel ferrule band where the handle meets the head.
	_add(root, _box(Vector3(0.042, 0.008, 0.022)), _mat("steel"), Vector3(0, -0.004, 0))


## An angle grinder: motor body along Y, gear head on top, disc and guard to the front (-Z),
## side handle out to +X.
static func _grinder(root: Node3D) -> void:
	var body := _mat("grinder_body")
	var rubber := _mat("rubber")
	var alu := _mat("alu")
	# Motor housing with a rubber grip band and a rounded tail cap.
	_add(root, _cyl(0.028, 0.026, 0.18, 24), body, Vector3(0, -0.05, 0))
	_add(root, _cyl(0.0285, 0.0272, 0.075, 24), rubber, Vector3(0, -0.095, 0))
	_add(root, _sphere(0.026, 0.03, false, 20), body, Vector3(0, -0.14, 0))
	# Cord with its strain relief.
	_add(root, _cyl(0.0065, 0.0045, 0.04, 10), rubber, Vector3(0, -0.168, 0))
	_add(root, _cyl(0.0035, 0.0035, 0.04, 8), rubber, Vector3(0, -0.205, 0))
	# Cooling vents near the head, front and back.
	for z in [-1.0, 1.0]:
		for i in 4:
			_add(root, _box(Vector3(0.004, 0.018, 0.004)), _mat("hole"), Vector3(-0.0135 + i * 0.009, 0.015, z * 0.0262))
	# Slide switch on the top (+Z faces the user).
	_add(root, _box(Vector3(0.012, 0.03, 0.006)), _mat("plastic_black"), Vector3(0, -0.02, 0.0275))
	_add(root, _box(Vector3(0.009, 0.01, 0.005)), _mat("red"), Vector3(0, -0.012, 0.031))
	# Gear head: cast aluminium.
	_add(root, _box(Vector3(0.05, 0.04, 0.05)), alu, Vector3(0, 0.055, -0.004))
	_add(root, _cyl(0.026, 0.026, 0.05, 24), alu, Vector3(0, 0.068, -0.01), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.008, 0.008, 0.006, 12), _mat("dark_steel"), Vector3(0, 0.068, 0.017), Vector3(PI * 0.5, 0, 0))   # spindle lock
	# Side handle, out to +X, with grip rings.
	_add(root, _cyl(0.006, 0.006, 0.02, 10), _mat("steel"), Vector3(0.033, 0.068, -0.01), Vector3(0, 0, PI * 0.5))
	_add(root, _cyl(0.011, 0.012, 0.085, 16), rubber, Vector3(0.083, 0.068, -0.01), Vector3(0, 0, PI * 0.5))
	for i in 4:
		_add(root, _torus(0.0105, 0.0135, 16), rubber, Vector3(0.055 + i * 0.018, 0.068, -0.01), Vector3(0, 0, PI * 0.5))
	# Spindle, guard and disc in front.
	var c := Vector3(0, 0.068, 0)
	_add(root, _cyl(0.006, 0.006, 0.012, 12), _mat("steel"), c + Vector3(0, 0, -0.04), Vector3(PI * 0.5, 0, 0))
	var guard := _mat("steel")
	_add(root, _ring_solid(0.015, 0.064, 0.0016, PI * 0.85, PI * 2.15, 28), guard, c + Vector3(0, 0, -0.04))
	_add(root, _ring_solid(0.062, 0.0645, 0.013, PI * 0.85, PI * 2.15, 28), guard, c + Vector3(0, 0, -0.0465))
	_add(root, _cyl(0.058, 0.058, 0.003, 36), _mat("abrasive"), c + Vector3(0, 0, -0.049), Vector3(PI * 0.5, 0, 0))
	for z in [-0.0471, -0.0509]:
		_add(root, _cyl(0.022, 0.022, 0.0006, 24), _mat("red"), c + Vector3(0, 0, z), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.011, 0.011, 0.005, 6), _mat("chrome"), c + Vector3(0, 0, -0.053), Vector3(PI * 0.5, 0, 0))


## A dual-action polisher: a grey motor body along the line of the tool with a rubber nose grip,
## the D handle over it with its trigger, and the backing plate and orange foam pad facing
## forward (-Z), its middle the "nozzle".
static func _polisher(root: Node3D) -> void:
	var body := _tint(Color(0.32, 0.34, 0.37), 0.1, 0.45)
	var rubber := _mat("rubber")
	# The motor body, back to front, with a cord out of the tail.
	_add(root, _cyl(0.032, 0.036, 0.15, 24), body, Vector3(0, 0, 0.02), Vector3(PI * 0.5, 0, 0))
	_add(root, _sphere(0.032, 0.05, false, 20), body, Vector3(0, 0, 0.095))
	_add(root, _cyl(0.0375, 0.037, 0.05, 24), rubber, Vector3(0, 0, -0.055), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.004, 0.004, 0.05, 8), rubber, Vector3(0, -0.005, 0.135), Vector3(PI * 0.5, 0, 0))
	for i in 5:
		_add(root, _box(Vector3(0.022, 0.003, 0.004)), _mat("hole"), Vector3(0, 0.032, 0.045 + i * 0.008))
	# The D handle on top, its trigger, and the speed wheel.
	_add(root, _box(Vector3(0.022, 0.05, 0.02)), body, Vector3(0, 0.05, 0.075))
	_add(root, _box(Vector3(0.022, 0.05, 0.02)), body, Vector3(0, 0.05, -0.015))
	_add(root, _cyl(0.012, 0.012, 0.11, 14), rubber, Vector3(0, 0.08, 0.03), Vector3(PI * 0.5, 0, 0))
	_add(root, _box(Vector3(0.01, 0.018, 0.026)), _mat("red"), Vector3(0, 0.062, 0.03))
	_add(root, _cyl(0.012, 0.012, 0.008, 14), _mat("yellow"), Vector3(0.0, 0.0, 0.105), Vector3(0, 0, PI * 0.5))
	# The backing plate and the foam pad on the front.
	_add(root, _cyl(0.03, 0.03, 0.02, 18), _mat("dark_steel"), Vector3(0, 0, -0.09), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.066, 0.064, 0.012, 32), _mat("plastic_black"), Vector3(0, 0, -0.106), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.075, 0.07, 0.035, 36), _tint(Color(0.95, 0.45, 0.08), 0.0, 0.95), Vector3(0, 0, -0.13), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.03, 0.03, 0.002, 18), _tint(Color(0.8, 0.35, 0.06), 0.0, 0.95), Vector3(0, 0, -0.148), Vector3(PI * 0.5, 0, 0))
	root.set_meta("nozzle", Vector3(0, 0, -0.17))


## A ceramic coating applicator: a little blue foam block wrapped in white suede, held face out.
static func _applicator(root: Node3D) -> void:
	_add(root, _box(Vector3(0.06, 0.03, 0.09)), _tint(Color(0.15, 0.35, 0.8), 0.0, 0.9), Vector3(0, 0, -0.02))
	_add(root, _box(Vector3(0.062, 0.006, 0.092)), _tint(Color(0.92, 0.92, 0.9), 0.0, 1.0), Vector3(0, -0.018, -0.02))
	root.set_meta("nozzle", Vector3(0, -0.02, -0.02))


## An aerosol can: steel body with a coloured label band, rolled rims, domed top, valve cup and
## an actuator whose nozzle points forward (-Z).
static func _spray_can(root: Node3D, can_color: Color) -> void:
	var chrome := _mat("chrome")
	var body := _tint(can_color.darkened(0.15), 0.55, 0.3)
	var band := _tint(can_color, 0.15, 0.35)
	var r := 0.032
	_add(root, _cyl(r, r, 0.15, 28), body, Vector3(0, -0.02, 0))
	_add(root, _cyl(r + 0.0006, r + 0.0006, 0.085, 28), band, Vector3(0, -0.02, 0))
	for y in [-0.0625, 0.0225]:
		_add(root, _cyl(r + 0.0008, r + 0.0008, 0.005, 28), _mat("white"), Vector3(0, y, 0))
	_add(root, _cyl(r + 0.0009, r + 0.0009, 0.016, 28), _mat("ink"), Vector3(0, -0.02, 0))   # the label's name stripe
	# Rolled rims top and bottom.
	_add(root, _torus(r - 0.003, r + 0.0015, 28), chrome, Vector3(0, -0.095, 0))
	_add(root, _torus(r - 0.003, r + 0.0015, 28), chrome, Vector3(0, 0.055, 0))
	# The domed shoulder and valve cup.
	_add(root, _sphere(r - 0.001, r - 0.001, true, 28), chrome, Vector3(0, 0.055, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	_add(root, _torus(0.008, 0.0115, 20), chrome, Vector3(0, 0.072, 0))
	_add(root, _cyl(0.0085, 0.0085, 0.004, 16), _mat("steel"), Vector3(0, 0.073, 0))
	# Actuator button with its forward-facing nozzle.
	_add(root, _cyl(0.0075, 0.0085, 0.014, 16), _mat("plastic_black"), Vector3(0, 0.081, 0))
	_add(root, _sphere(0.0075, 0.006, false, 16), _mat("plastic_black"), Vector3(0, 0.088, 0))
	_add(root, _cyl(0.0022, 0.0022, 0.004, 10), _mat("hole"), Vector3(0, 0.083, -0.0076), Vector3(PI * 0.5, 0, 0))
	root.set_meta("nozzle", Vector3(0, 0.083, -0.009))


## A pressure washer trigger gun with its lance: grip near the origin, hose stub out the bottom,
## nozzle at (0, 0, -0.6) where the water jet goes.
static func _lance(root: Node3D) -> void:
	var yellow := _mat("yellow")
	var black := _mat("plastic_black")
	var rubber := _mat("rubber")
	# Gun housing.
	_add(root, _box(Vector3(0.034, 0.045, 0.12)), yellow, Vector3(0, 0.0, -0.02))
	_add(root, _cyl(0.0225, 0.0225, 0.034, 20), yellow, Vector3(0, 0.0, 0.04), Vector3(0, 0, PI * 0.5))
	_add(root, _box(Vector3(0.036, 0.01, 0.1)), black, Vector3(0, 0.024, -0.025))
	# Pistol grip, raked back.
	_add(root, _capsule(0.017, 0.12), black, Vector3(0, -0.07, 0.055), Vector3(deg_to_rad(-18.0), 0, 0), Vector3(0.9, 1.0, 1.15))
	# Trigger and its guard.
	_add(root, _box(Vector3(0.012, 0.075, 0.012)), yellow, Vector3(0, -0.052, 0.012), Vector3(deg_to_rad(-14.0), 0, 0))
	_add(root, _ring_solid(0.05, 0.057, 0.008, PI * 1.05, PI * 1.5, 12), black, Vector3(0, -0.012, 0.05), Vector3(0, PI * 0.5, 0))
	# Hose: brass swivel out of the bottom of the grip, then a stub of black hose.
	_add(root, _cyl(0.009, 0.009, 0.02, 12), _mat("brass"), Vector3(0, -0.135, 0.077), Vector3(deg_to_rad(-18.0), 0, 0))
	_add(root, _cyl(0.0085, 0.0085, 0.07, 14), rubber, Vector3(0, -0.17, 0.1), Vector3(deg_to_rad(-40.0), 0, 0))
	# The lance tube with a foam hand grip and a brass coupling.
	_add(root, _cyl(0.011, 0.011, 0.02, 14), _mat("brass"), Vector3(0, 0.0, -0.088), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0065, 0.0065, 0.47, 12), _mat("chrome"), Vector3(0, 0.0, -0.33), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0135, 0.0135, 0.11, 16), rubber, Vector3(0, 0.0, -0.22), Vector3(PI * 0.5, 0, 0))
	for z in [-0.165, -0.275]:
		_add(root, _cyl(0.015, 0.0135, 0.006, 16), rubber, Vector3(0, 0.0, z), Vector3(PI * 0.5, 0, 0))
	# Nozzle: black body, coloured tip, brass orifice right at -0.6.
	_add(root, _cyl(0.0105, 0.013, 0.04, 16), black, Vector3(0, 0.0, -0.572), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0085, 0.0105, 0.012, 16), _mat("orange"), Vector3(0, 0.0, -0.592), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.003, 0.003, 0.004, 8), _mat("brass"), Vector3(0, 0.0, -0.598), Vector3(PI * 0.5, 0, 0))
	root.set_meta("nozzle", Vector3(0, 0, -0.6))


## An HVLP gravity-feed paint gun: cup on top (tinted can_color), body along Z, trigger and handle
## below, air fitting under the handle, nozzle at (0, 0.02, -0.12).
static func _paint_gun(root: Node3D, can_color: Color) -> void:
	var alu := _mat("alu")
	var chrome := _mat("chrome")
	var by := 0.02
	# Forged body along Z.
	_add(root, _cyl(0.0135, 0.0155, 0.1, 20), alu, Vector3(0, by, -0.045), Vector3(PI * 0.5, 0, 0))
	_add(root, _box(Vector3(0.024, 0.03, 0.05)), alu, Vector3(0, by - 0.006, 0.01))
	# Air cap and fluid tip at the front, with the two horns of the fan cap.
	_add(root, _cyl(0.0125, 0.0145, 0.012, 20), chrome, Vector3(0, by, -0.1), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0095, 0.012, 0.008, 20), chrome, Vector3(0, by, -0.11), Vector3(PI * 0.5, 0, 0))
	for s in [-1.0, 1.0]:
		_add(root, _box(Vector3(0.006, 0.006, 0.014)), chrome, Vector3(s * 0.0125, by, -0.109))
	_add(root, _cyl(0.003, 0.004, 0.008, 10), _mat("brass"), Vector3(0, by, -0.117), Vector3(PI * 0.5, 0, 0))
	# Gravity cup: neck, tinted translucent cup, chrome lid with a vent.
	_add(root, _cyl(0.0065, 0.0065, 0.022, 14), chrome, Vector3(0, by + 0.022, -0.055))
	_add(root, _cyl(0.028, 0.02, 0.016, 24), _tint(can_color, 0.0, 0.25, 0.85), Vector3(0, by + 0.04, -0.055))
	_add(root, _cyl(0.029, 0.028, 0.055, 24), _tint(can_color, 0.0, 0.2, 0.7), Vector3(0, by + 0.0755, -0.055))
	_add(root, _cyl(0.0305, 0.0305, 0.008, 24), _mat("steel"), Vector3(0, by + 0.106, -0.055))
	_add(root, _torus(0.027, 0.0315, 24), _mat("steel"), Vector3(0, by + 0.103, -0.055))
	_add(root, _cyl(0.003, 0.003, 0.012, 8), _mat("plastic_black"), Vector3(0.012, by + 0.114, -0.055))
	# Handle, raked back, with a rubber grip.
	_add(root, _box(Vector3(0.02, 0.1, 0.028)), alu, Vector3(0, by - 0.06, 0.03), Vector3(deg_to_rad(-15.0), 0, 0))
	_add(root, _box(Vector3(0.023, 0.07, 0.03)), _mat("rubber"), Vector3(0, by - 0.07, 0.034), Vector3(deg_to_rad(-15.0), 0, 0))
	# Trigger: a curved finger lever hung from the front of the body.
	_add(root, _box(Vector3(0.016, 0.058, 0.004)), chrome, Vector3(0, by - 0.035, -0.018), Vector3(deg_to_rad(10.0), 0, 0))
	_add(root, _box(Vector3(0.016, 0.004, 0.012)), chrome, Vector3(0, by - 0.0015, -0.02))
	# Air inlet fitting and a stub of air hose under the handle.
	_add(root, _cyl(0.0075, 0.0075, 0.014, 6), _mat("brass"), Vector3(0, by - 0.117, 0.046), Vector3(deg_to_rad(-15.0), 0, 0))
	_add(root, _cyl(0.005, 0.005, 0.016, 12), _mat("brass"), Vector3(0, by - 0.13, 0.05), Vector3(deg_to_rad(-15.0), 0, 0))
	_add(root, _cyl(0.0065, 0.0065, 0.05, 12), _tint(Color(0.15, 0.3, 0.7), 0.0, 0.5), Vector3(0, by - 0.16, 0.058), Vector3(deg_to_rad(-15.0), 0, 0))
	# Adjuster knobs at the back: fluid (centre) and fan (top).
	_add(root, _cyl(0.0035, 0.0035, 0.02, 10), chrome, Vector3(0, by, 0.04), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0085, 0.0085, 0.012, 14), _mat("plastic_black"), Vector3(0, by, 0.054), Vector3(PI * 0.5, 0, 0))
	_add(root, _cyl(0.0065, 0.0065, 0.01, 12), _mat("plastic_black"), Vector3(0, by + 0.018, 0.03), Vector3(PI * 0.5, 0, 0))
	root.set_meta("nozzle", Vector3(0, by, -0.12))


## A chrome stopwatch, face toward +Z, crown at the top. Its sweep hand is the "Hand" child
## (rotate about Z; set_hand_angle / set_hand_seconds do it), the small one "MinuteHand".
static func _stopwatch(root: Node3D) -> void:
	var chrome := _mat("chrome")
	var r := 0.034
	var tz := 0.012
	_add(root, _cyl(r, r, tz, 40), chrome, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_add(root, _torus(r - 0.005, r + 0.001, 40), chrome, Vector3(0, 0, tz * 0.5), Vector3(PI * 0.5, 0, 0), Vector3(1, 0.7, 1))
	_add(root, _sphere(r - 0.002, 0.008, false, 32), chrome, Vector3(0, 0, -tz * 0.5), Vector3(PI * 0.5, 0, 0))
	var fz := tz * 0.5 + 0.0003
	_add(root, _cyl(r - 0.004, r - 0.004, 0.001, 40), _mat("face"), Vector3(0, 0, fz), Vector3(PI * 0.5, 0, 0))
	# Tick marks: twelve bold, the rest fine.
	var tick_mm := MultiMesh.new()
	tick_mm.transform_format = MultiMesh.TRANSFORM_3D
	tick_mm.mesh = _box(Vector3(1, 1, 1))
	tick_mm.instance_count = 60
	for i in 60:
		var a := TAU * i / 60.0
		var big := i % 5 == 0
		var tl := 0.005 if big else 0.0025
		var w := 0.0013 if big else 0.0006
		var rr := r - 0.0055 - tl * 0.5
		var tb := Basis(Vector3.BACK, -a) * Basis.from_scale(Vector3(w, tl, 0.0006))
		tick_mm.set_instance_transform(i, Transform3D(tb, Vector3(sin(a) * rr, cos(a) * rr, 0.0)))
	var ticks := MultiMeshInstance3D.new()
	ticks.multimesh = tick_mm
	ticks.material_override = _mat("ink")
	ticks.position = Vector3(0, 0, fz + 0.0007)
	ticks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ticks)
	# Small thirty-minute subdial.
	var sub_c := Vector3(0, -0.011, fz + 0.0006)
	_add(root, _torus(0.0068, 0.0078, 24), _mat("ink"), sub_c, Vector3(PI * 0.5, 0, 0), Vector3(1, 0.1, 1))
	var minute := Node3D.new()
	minute.name = "MinuteHand"
	minute.position = sub_c + Vector3(0, 0, 0.0004)
	root.add_child(minute)
	_add(minute, _box(Vector3(0.0009, 0.0065, 0.0004)), _mat("ink"), Vector3(0, 0.0028, 0))
	# The sweep hand, pointing at twelve when its rotation is zero.
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0, 0, fz + 0.0016)
	root.add_child(hand)
	_add(hand, _box(Vector3(0.0011, 0.03, 0.0005)), _mat("red"), Vector3(0, 0.0105, 0))
	_add(hand, _cyl(0.0022, 0.0022, 0.0012, 12), _mat("red"), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	# Glass.
	_add(root, _cyl(r - 0.004, r - 0.004, 0.0008, 40), _mat("glass"), Vector3(0, 0, fz + 0.0032), Vector3(PI * 0.5, 0, 0))
	# Crown: stem, knurled button, and the bow ring above it.
	_add(root, _cyl(0.0035, 0.0035, 0.008, 12), chrome, Vector3(0, r + 0.003, 0))
	_add(root, _cyl(0.0065, 0.0065, 0.006, 18), chrome, Vector3(0, r + 0.009, 0))
	_add(root, _cyl(0.0068, 0.0068, 0.002, 18), _mat("steel"), Vector3(0, r + 0.009, 0))
	_add(root, _torus(0.0075, 0.0105, 24), chrome, Vector3(0, r + 0.021, 0), Vector3(PI * 0.5, 0, 0))
	# Side pusher (reset) at ten past.
	var a2 := deg_to_rad(45.0)
	_add(root, _cyl(0.0035, 0.0035, 0.007, 12), chrome, Vector3(sin(a2) * (r + 0.002), cos(a2) * (r + 0.002), 0), Vector3(0, 0, -a2))
	set_hand_angle(root, 0.0)
