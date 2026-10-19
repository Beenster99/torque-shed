class_name KitModel
extends RefCounted
## The adventure kit drawn on a bike (see BikeModel.build_from): a tank bag on the tank, an
## auxiliary fuel tank, a toolbox and a sat nav on the bars with a live screen. Kept out of
## BikeModel's own file; every mesh still belongs to its slot, so the parts show, hide, get dirty
## and are picked like the rest. All on the left of the bike, clear of the exhaust.

## The sat nav's screen texture size, in pixels (see SatnavScreen).
const SCREEN_PX := Vector2i(320, 200)


## Draws whichever of the kit is in the build.
static func draw(m: BikeModel, build: BikeBuild, zr: float) -> void:
	_tank_bag(m)
	_aux_tank(m, build, zr)
	_toolbox(m, build, zr)
	_satnav(m)


## A tank bag on top of the tank, from just behind the steering head back: a low or tall soft
## bag (with a clear map pocket on top where it has one), straps down the tank's sides for a
## strap-on one, or a hard shell on a ring round the filler for a quick-lock one.
static func _tank_bag(m: BikeModel) -> void:
	m._current_slot = "tank_bag"
	var p := m._part()
	if p.is_empty():
		return
	var mat := m._mat(m._col(), 0.0, 0.85 if str(p.get("material", "")) == "fabric" else 0.45)
	if str(p.get("material", "")) == "fabric":
		mat = m._tex(mat, "crinkle", -1.0, 0.5)
	var dark := m._mat(Color(0.03, 0.03, 0.035), 0.0, 0.7)
	var style := str(p.get("style", "low"))
	var k := pow(float(p.get("litres", 10.0)) / 10.0, 0.33)
	var tall := style == "tall"
	var length := 0.26 * k
	var height := (0.15 if tall else 0.1) * k
	var z0 := m._tank_front() + 0.04
	var secs := []
	var n := 5
	for i in n + 1:
		var u := float(i) / n
		var z := z0 + length * u
		var top := m.tank_top_at(z)
		var w := minf(top.y * 0.82, 0.13 * k) * lerpf(0.8, 1.0, sin(u * PI))
		var h := height * lerpf(0.7, 1.0, sin(minf(u * 1.4, 1.0) * PI * 0.5))
		secs.append({"c": Vector3(0.0, top.x + h * 0.5, z), "w": w, "up": h * 0.5, "down": h * 0.5,
			"n": 2.2 if style == "ring" else 3.0})
	m._shell(secs, mat).name = "TankBag"
	var mid: Dictionary = secs[n / 2]
	var top_y := float((mid["c"] as Vector3).y) + float(mid["up"])
	if p.get("map", false):
		# A clear map pocket over the top, a paper map under it.
		var pocket := m._mat(Color(0.75, 0.85, 0.9), 0.1, 0.05)
		pocket.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pocket.albedo_color.a = 0.4
		var map_mat := m._mat(Color(0.86, 0.84, 0.72), 0.0, 0.9)
		var at := Vector3(0.0, top_y + 0.003, z0 + length * 0.5)
		m._box(at, Vector3(float(mid["w"]) * 1.3, 0.003, length * 0.6), map_mat)
		m._box(at + Vector3(0.0, 0.004, 0.0), Vector3(float(mid["w"]) * 1.4, 0.003, length * 0.66), pocket)
		# A road and a river on the map.
		m._box(at + Vector3(0.0, 0.002, 0.0), Vector3(0.008, 0.002, length * 0.55), m._mat(Color(0.8, 0.25, 0.15), 0.0, 0.9))
		m._box(at + Vector3(0.02, 0.002, 0.02), Vector3(float(mid["w"]) * 1.1, 0.002, 0.006), m._mat(Color(0.3, 0.5, 0.8), 0.0, 0.9))
	# A zip round it, a grab handle on top and an accent stripe if it has one.
	var zip := []
	for sec in secs:
		zip.append((sec["c"] as Vector3) + Vector3(0.0, float(sec["up"]) * 0.45, 0.0))
	for side in [-1.0, 1.0]:
		var line := []
		for sec in secs:
			line.append((sec["c"] as Vector3) + Vector3(float(sec["w"]) * 0.97 * side, float(sec["up"]) * 0.3, 0.0))
		m._bend(line, 0.004, dark)
	if p.has("accent"):
		var a: Array = p["accent"]
		for side in [-1.0, 1.0]:
			var line := []
			for sec in secs:
				line.append((sec["c"] as Vector3) + Vector3(float(sec["w"]) * 0.99 * side, -float(sec["down"]) * 0.2, 0.0))
			m._bend(line, 0.006, m._mat(Color(a[0], a[1], a[2]), 0.0, 0.6))
	var back: Dictionary = secs[n]
	m._bend([(back["c"] as Vector3) + Vector3(-0.04, float(back["up"]) * 0.9, -0.02), (back["c"] as Vector3) + Vector3(-0.02, float(back["up"]) + 0.02, -0.02),
		(back["c"] as Vector3) + Vector3(0.02, float(back["up"]) + 0.02, -0.02), (back["c"] as Vector3) + Vector3(0.04, float(back["up"]) * 0.9, -0.02)], 0.006, dark)
	match str(p.get("mount", "")):
		"strap":
			# Straps from the bag down the tank's sides, buckled underneath.
			for side in [-1.0, 1.0]:
				for u in [0.2, 0.8]:
					var z: float = z0 + length * u
					var t := m.tank_top_at(z)
					m._strip(Vector3(t.y * 0.75 * side, t.x + 0.02, z), Vector3((t.y + 0.012) * side, t.x - 0.07, z + 0.01), 0.02, 0.003, dark)
		"ring":
			var ring := m._mesh_instance(m._cylinder(0.07, 0.012, -1.0, 24), m._mat(Color(0.12, 0.12, 0.13), 0.6, 0.35),
				Vector3(0.0, m.tank_top_at(z0 + length * 0.6).x + 0.004, z0 + length * 0.6))
			ring.name = "TankRing"


## An auxiliary fuel tank by its style: a flat steel can on a bracket, a slim alloy cell along the
## rail, a moulded tank behind the seat, a pair of rally tanks low either side of the engine, or a
## soft bladder strapped across the back. Each with its filler cap.
static func _aux_tank(m: BikeModel, build: BikeBuild, zr: float) -> void:
	m._current_slot = "aux_tank"
	var p := m._part()
	if p.is_empty():
		return
	var plastic := str(p.get("material", "")) == "plastic"
	var mat := m._skin(m._mat(m._col(), 0.8 if str(p.get("material", "")) == "metal" else 0.0, 0.35 if not plastic else 0.5))
	if plastic:
		mat.albedo_color.a = 0.92
	var cap_mat := m._mat(Color(0.05, 0.05, 0.055), 0.4, 0.4)
	var steel := m._mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	var w := build.rear_tyre_width * 0.5 + 0.12
	var k := pow(float(p.get("capacity", 8.0)) / 8.0, 0.33)
	match str(p.get("style", "can")):
		"can":
			var c := Vector3(-(w + 0.06), m._seat_y - 0.24, zr - 0.36)
			var size := Vector3(0.075, 0.26, 0.2) * k
			m._box(c, size, mat).name = "FuelCan"
			# The pressed X on its face, the handle on top and the spout.
			for s in [-1.0, 1.0]:
				var x := m._box(c + Vector3(-size.x * 0.5 - 0.002, 0.0, 0.0), Vector3(0.004, size.y * 0.9, 0.012), m._mat(m._col().darkened(0.2), 0.6, 0.4))
				x.rotation.x = 0.65 * s
			m._box(c + Vector3(0.0, size.y * 0.5 + 0.015, -size.z * 0.15), Vector3(0.025, 0.02, size.z * 0.5), mat)
			var spout := m._mesh_instance(m._cylinder(0.015, 0.03), cap_mat, c + Vector3(0.0, size.y * 0.5 + 0.015, size.z * 0.35))
			spout.rotation.x = -0.6
			# The bracket off the rail.
			m._tube(c + Vector3(0.03, size.y * 0.3, 0.0), Vector3(-w, m._seat_y - 0.04, c.z), 0.007, steel)
			m._tube(c + Vector3(0.03, -size.y * 0.45, 0.0), Vector3(-w + 0.02, c.y - size.y * 0.45, c.z + 0.1), 0.007, steel)
		"cell":
			var a := Vector3(-(w + 0.05), m._seat_y - 0.09, zr - 0.5)
			var b := Vector3(-(w + 0.05), m._seat_y - 0.09, zr - 0.02)
			var cell := m._tube(a, b, 0.055 * k, mat)
			cell.name = "FuelCell"
			m._mesh_instance(m._sphere(0.055 * k), mat, a)
			m._mesh_instance(m._sphere(0.055 * k), mat, b)
			m._mesh_instance(m._cylinder(0.018, 0.025), cap_mat, a.lerp(b, 0.3) + Vector3(0.0, 0.055 * k, 0.0))
			for u in [0.2, 0.8]:
				var at := a.lerp(b, u)
				m._tube(at + Vector3(0.04, 0.0, 0.0), Vector3(-w, m._seat_y - 0.04, at.z), 0.006, steel)
			m._bike_only(m._tube(a.lerp(b, 0.05) + Vector3(0.03, -0.04, 0.0), Vector3(-0.08, m.tank_top_at(m._tank_front() + 0.3).x - 0.12, m._pivot.z), 0.005, cap_mat))
		"rear":
			var c := Vector3(0.0, m._seat_y - 0.06, m._tail.z - 0.02)
			var secs := []
			for i in 5:
				var u := i / 4.0
				secs.append({"c": c + Vector3(0.0, 0.0, lerpf(-0.17, 0.15, u) * k), "w": 0.13 * k * lerpf(0.85, 1.0, sin(u * PI)),
					"up": 0.07 * k, "down": 0.09 * k * lerpf(0.7, 1.0, u), "n": 2.6})
			m._shell(secs, mat).name = "RearTank"
			m._mesh_instance(m._cylinder(0.022, 0.02), cap_mat, c + Vector3(0.09 * k, 0.07 * k + 0.01, 0.0))
		"twin":
			for side in [-1.0, 1.0]:
				var c := Vector3(side * (m._block_w * 0.5 + 0.11), m._engine_c.y + 0.06, m._engine_c.z - 0.14)
				var secs := []
				for i in 5:
					var u := i / 4.0
					secs.append({"c": c + Vector3(0.0, lerpf(-0.04, 0.06, u), lerpf(-0.1, 0.12, u) * k),
						"w": 0.05 * k * lerpf(0.7, 1.0, sin(u * PI)), "up": lerpf(0.12, 0.08, u) * k, "down": lerpf(0.06, 0.12, u) * k, "n": 2.4})
				m._shell(secs, mat).name = "SideTank"
				m._mesh_instance(m._cylinder(0.018, 0.02), cap_mat, c + Vector3(0.0, 0.18 * k, 0.04))
				m._bike_only(m._tube(c + Vector3(-side * 0.04, -0.06, 0.08), m._engine_c + Vector3(side * 0.06, 0.1, 0.0), 0.005, cap_mat))
		_:
			# A soft bladder strapped across the back of the seat.
			var c := Vector3(0.0, m._seat_y + 0.06, m._tail.z - 0.08)
			var body := m._mesh_instance(m._capsule(0.05 * k, 0.36 * k), mat, c)
			body.rotation.z = PI * 0.5
			body.scale = Vector3(1.0, 1.0, 1.6)
			body.name = "Bladder"
			m._mesh_instance(m._cylinder(0.016, 0.025), cap_mat, c + Vector3(0.12 * k, 0.05 * k, 0.0))
			for x in [-0.08, 0.08]:
				m._strip(c + Vector3(x, 0.055 * k, -0.06), c + Vector3(x, -0.06, -0.09), 0.02, 0.003, m._mat(Color(0.8, 0.35, 0.08), 0.0, 0.8))


## A toolbox by its style: a leather roll strapped under the headlight, a screw-capped tube
## along the left of the back wheel, an alloy box low ahead of the rear axle, a big case there, or
## a box built into the bash plate under the engine.
static func _toolbox(m: BikeModel, build: BikeBuild, zr: float) -> void:
	m._current_slot = "toolbox"
	var p := m._part()
	if p.is_empty():
		return
	var mat := m._skin(m._mat(m._col(), 0.85 if str(p.get("material", "")) == "metal" else 0.0, 0.35))
	var dark := m._mat(Color(0.04, 0.04, 0.045), 0.3, 0.5)
	var steel := m._mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	var w := build.rear_tyre_width * 0.5 + 0.12
	match str(p.get("style", "box")):
		"roll":
			var roll := m._mesh_instance(m._cylinder(0.035, 0.22, -1.0, 16), m._tex(mat, "grain"), Vector3(0.0, -0.22, -0.1), m._steer_node)
			roll.rotation.z = PI * 0.5
			roll.name = "ToolRoll"
			for x in [-0.07, 0.07]:
				var band := m._mesh_instance(m._cylinder(0.037, 0.015, -1.0, 16), dark, Vector3(x, -0.22, -0.1), m._steer_node)
				band.rotation.z = PI * 0.5
		"tube":
			var a := Vector3(-(w + 0.03), -0.03, zr - 0.42)
			var b := Vector3(-(w + 0.03), -0.03, zr - 0.08)
			m._tube(a, b, 0.045, mat).name = "ToolTube"
			var cap := m._tube(b, b + Vector3(0.0, 0.0, 0.03), 0.05, dark)
			cap.name = "TubeCap"
			for u in [0.25, 0.75]:
				var at := a.lerp(b, u)
				m._tube(at + Vector3(0.04, 0.0, 0.0), Vector3(-w + 0.02, at.y + 0.08, at.z), 0.006, steel)
		"bash":
			var c := Vector3(0.0, m._engine_c.y - 0.22 * m._eng_s - 0.04, m._engine_c.z + 0.02)
			var size := Vector3(0.16, 0.06, 0.28)
			m._box(c, size, mat).name = "BashBox"
			m._box(c + Vector3(0.0, -size.y * 0.5 - 0.002, 0.0), Vector3(size.x + 0.04, 0.006, size.z + 0.04), mat)
			for s in [-1.0, 1.0]:
				m._box(c + Vector3(s * (size.x * 0.5 + 0.003), 0.0, 0.0), Vector3(0.006, 0.02, 0.05), dark)
		_:
			var big := str(p.get("style", "")) == "case"
			var size := Vector3(0.1, 0.15, 0.26) if big else Vector3(0.08, 0.12, 0.22)
			var c := Vector3(-(w + size.x * 0.5 + 0.01), -0.06, zr - 0.36)
			m._box(c, size, mat).name = "Toolbox"
			m._box(c + Vector3(0.0, size.y * 0.5 + 0.006, 0.0), Vector3(size.x + 0.008, 0.012, size.z + 0.008), mat)
			# A latch and lock on the face, ribs and the bracket to the rail.
			m._box(c + Vector3(-size.x * 0.5 - 0.004, size.y * 0.3, 0.0), Vector3(0.008, 0.03, 0.04), dark)
			var lock := m._mesh_instance(m._cylinder(0.007, 0.006), steel, c + Vector3(-size.x * 0.5 - 0.009, size.y * 0.3, 0.0))
			lock.rotation.z = PI * 0.5
			for z in [-0.06, 0.06]:
				m._box(c + Vector3(-size.x * 0.5 - 0.002, -0.01, z), Vector3(0.004, size.y * 0.7, 0.01), mat)
			m._tube(c + Vector3(size.x * 0.5, size.y * 0.4, 0.0), Vector3(-w + 0.02, m._seat_y - 0.1, c.z + 0.05), 0.007, steel)


## A sat nav on the bars: a phone in a clamp on the right of the bars, a small unit on a ball
## mount, a road unit on a RAM arm, an adventure unit on a crossbar over the clocks, or a rally
## tablet up on a navigation bar. Its screen is lit with the live map while it's ridden (see
## BikeModel.set_satnav_texture).
static func _satnav(m: BikeModel) -> void:
	m._current_slot = "satnav"
	var p := m._part()
	if p.is_empty():
		return
	var housing := m._mat(m._col(), 0.2, 0.45)
	var dark := m._mat(Color(0.04, 0.04, 0.045), 0.4, 0.4)
	var size: Array = p.get("screen", [0.1, 0.065])
	var sw := float(size[0])
	var sh := float(size[1])
	var style := str(p.get("style", "road"))
	var tilt := Basis(Vector3.RIGHT, 0.85)
	var lift := m._dash_raised
	var at := Vector3(0.0, 0.22 + lift, -0.03)
	var mount := Vector3(0.0, 0.12, 0.0)   # where its arm meets the bars or crossbar
	match style:
		"phone", "compact":
			at = Vector3(0.13, 0.2 + lift * 0.5, 0.02)
			mount = Vector3(0.12, 0.12, 0.05)
		"road":
			at = Vector3(0.1, 0.22 + lift, -0.02)
			mount = Vector3(0.07, 0.13, 0.03)
		"tablet":
			at = Vector3(0.0, 0.25 + lift, -0.08)
			mount = Vector3(0.0, 0.16 + lift, -0.08)
	if style in ["adventure", "tablet"]:
		# A crossbar over the clocks, on two stays from the top yoke.
		var bar_y := at.y - sh * 0.5 - 0.03
		m._tube(Vector3(-0.1, bar_y, at.z + 0.02), Vector3(0.1, bar_y, at.z + 0.02), 0.009, dark, Vector3.ONE, m._steer_node)
		for x in [-0.08, 0.08]:
			m._tube(Vector3(x, 0.05, 0.03), Vector3(x, bar_y, at.z + 0.02), 0.007, dark, Vector3.ONE, m._steer_node)
		mount = Vector3(0.0, bar_y, at.z + 0.02)
	# The arm from the mount up to the back of the unit.
	m._tube(mount, at - tilt.y * 0.02, 0.008, dark, Vector3.ONE, m._steer_node)
	m._mesh_instance(m._sphere(0.014), dark, mount, m._steer_node)
	var body := m._box(at, Vector3(sw + 0.022, 0.026, sh + 0.022), housing, m._steer_node)
	body.basis = tilt
	body.name = "SatnavBody"
	if p.has("accent"):
		var a: Array = p["accent"]
		var trim := m._box(at - tilt.y * 0.004, Vector3(sw + 0.03, 0.012, sh + 0.03), m._mat(Color(a[0], a[1], a[2]), 0.1, 0.5), m._steer_node)
		trim.basis = tilt
	# A sun visor over the top edge on the bigger units.
	if style in ["adventure", "tablet", "road"]:
		var visor := m._box(at + tilt * Vector3(0.0, 0.03, -sh * 0.5 - 0.008), Vector3(sw + 0.024, 0.004, 0.035), housing, m._steer_node)
		visor.basis = tilt * Basis(Vector3.RIGHT, -0.5)
	# The screen: a quad laid on the face, looking along the face's normal (the tilted Y).
	var quad := QuadMesh.new()
	quad.size = Vector2(sw, sh)
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_color = Color(0.02, 0.03, 0.04)
	var screen := m._mesh_instance(quad, screen_mat, at + tilt.y * 0.0135, m._steer_node)
	screen.basis = tilt * Basis(Vector3.RIGHT, -PI * 0.5)
	screen.name = "SatnavScreen"
	# Kept out of the merged meshes: its texture changes as you ride.
	screen.set_meta("satnav_screen", true)
	m._satnav_screen = screen
