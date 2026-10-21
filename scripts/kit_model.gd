class_name KitModel
extends RefCounted
## The adventure kit drawn on a bike (see BikeModel.build_from): a tank bag on the tank, an
## auxiliary fuel tank, a toolbox and a sat nav on the bars with a live screen. Kept out of
## BikeModel's own file; every mesh still belongs to its slot, so the parts show, hide, get dirty
## and are picked like the rest. All on the left of the bike, clear of the exhaust.

## The sat nav's screen texture size, in pixels (see SatnavScreen).
const SCREEN_PX := Vector2i(320, 200)
## How bright the screen's glow on the bars is at night (OmniLight3D energy), and how far it reaches (m).
const GLOW_ENERGY := 0.35
const GLOW_RANGE := 0.45
## A phone sat nav: how far (m) the phone buzzes in its cradle with the engine, at most.
const BUZZ := 0.0009
## The slots whose parts a phone on the bars mustn't run into (with the bars themselves).
const PHONE_CLEAR: Array[String] = ["mirrors", "front_master", "dashboard", "fairing", "headlight", "fog_lights",
	"indicators", "steering_damper", "tank_bag"]

static var _idle_tex: ImageTexture
## Where a phone went on the bars for each set of parts (see _phone): a hash of them -> its fit.
static var _phone_fits := {}


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


## A sat nav on the bars: a phone in a clip on the bar itself (see _phone), a small unit on a
## ball mount, a road unit on a RAM arm, an adventure unit on a crossbar over the clocks, or a
## rally tablet up on a navigation bar. Its screen is lit with the live map while it's ridden
## (see BikeModel.set_satnav_texture), and glows after dark.
static func _satnav(m: BikeModel) -> void:
	m._current_slot = "satnav"
	var p := m._part()
	if p.is_empty():
		return
	var style := str(p.get("style", "road"))
	if style == "phone":
		_phone(m, p)
		return
	var housing := m._mat(m._col(), 0.2, 0.45)
	var dark := m._mat(Color(0.04, 0.04, 0.045), 0.4, 0.4)
	var size: Array = p.get("screen", [0.1, 0.065])
	var sw := float(size[0])
	var sh := float(size[1])
	var tilt := Basis(Vector3.RIGHT, 0.85)
	var lift := m._dash_raised
	var at := Vector3(0.0, 0.22 + lift, -0.03)
	var mount := Vector3(0.0, 0.12, 0.0)   # where its arm meets the bars or crossbar
	match style:
		"compact":
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
	_glow(m, m._steer_node, at + tilt.y * 0.05)


## The light a lit sat nav screen throws round it after dark (BikeModel._show_satnav sets it).
static func _glow(m: BikeModel, parent: Node3D, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "SatnavGlow"
	light.light_color = Color(0.7, 0.85, 1.0)
	light.omni_range = GLOW_RANGE
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.light_specular = 0.2
	light.visible = false
	light.position = pos
	parent.add_child(light)
	m._satnav_glow = light


## A phone in a handlebar clip, the cheap way to a sat nav: the phone in a cradle with sprung
## jaws gripping its ends and two hooks under it, on a ball joint and a short arm down to a
## clamp round the bar tube itself. It goes on the bar's own line (BikeModel.bar_point, for
## whatever bars the bike has), turned to face the rider's eye. Of the places it could go (along
## the right of the bar inboard of the lever, a little up and ahead of it, then up over the
## clocks from the middle of the bar), the first where it hides none of the clocks from the eye,
## runs into nothing (the bars and what's on them, the mirrors' stalks, the brake lever, a
## fairing) and can be seen from the eye wins (see BikeModel.satnav_fit).
static func _phone(m: BikeModel, p: Dictionary) -> void:
	var size: Array = p.get("screen", [0.12, 0.075])
	var sw := float(size[0])
	var sh := float(size[1])
	var half := Vector3(sw * 0.5 + 0.008, sh * 0.5 + 0.006, 0.0045)   # the phone, half of each way
	var keep := half + Vector3(0.012, 0.006, 0.012)                    # with its cradle round it
	var eye := m._eye - m._head
	# The same parts always give the same place: worked out once (it takes a few ms).
	var key := hash(var_to_str([m._build.parts, m.present]))
	var best: Dictionary = _phone_fits.get(key, {})
	if best.is_empty():
		best = _phone_place(m, keep, eye)
		if _phone_fits.size() > 256:
			_phone_fits.clear()
		_phone_fits[key] = best
	var at: Vector3 = best["centre"]
	var clamp: Vector3 = best["clamp"]
	var basis := _facing(at, eye)
	m.satnav_fit = best.duplicate()
	var case_mat := m._mat(m._col(), 0.1, 0.55)
	var phone_mat := m._mat(Color(0.03, 0.03, 0.035), 0.5, 0.25)
	var rubber := m._mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	var alloy := m._mat(Color(0.55, 0.56, 0.6), 0.9, 0.35)
	# The cradle: it and everything in it buzz together (see BikeModel._buzz_satnav).
	var cradle := Node3D.new()
	cradle.name = "PhoneCradle"
	cradle.transform = Transform3D(basis, at)
	m._steer_node.add_child(cradle)
	m._satnav_cradle = cradle
	m._satnav_rest = at
	m._box(Vector3.ZERO, half * 2.0, phone_mat, cradle).name = "Phone"
	# The camera bump on its back, and the buttons along the top edge.
	m._box(Vector3(half.x * 0.55, half.y * 0.45, -half.z - 0.0015), Vector3(0.022, 0.022, 0.003), phone_mat, cradle)
	m._box(Vector3(half.x * 0.3, half.y + 0.0008, 0.0), Vector3(0.018, 0.0016, 0.003), phone_mat, cradle)
	# The back plate, the jaws gripping each end with a lip over the glass, and the hooks under it.
	m._box(Vector3(0.0, 0.0, -half.z - 0.004), Vector3(half.x * 1.2, half.y * 1.4, 0.006), case_mat, cradle).name = "CradlePlate"
	for side in [-1.0, 1.0]:
		var jaw := m._box(Vector3(side * (half.x + 0.004), 0.0, -0.002), Vector3(0.008, half.y * 1.2, half.z * 2.0 + 0.01), case_mat, cradle)
		jaw.name = "CradleJaw"
		m._box(Vector3(side * (half.x - 0.0015), 0.0, half.z + 0.0012), Vector3(0.005, half.y * 0.9, 0.0024), rubber, cradle)
		m._box(Vector3(side * half.x * 0.45, -half.y - 0.004, -0.002), Vector3(0.016, 0.008, half.z * 2.0 + 0.008), case_mat, cradle).name = "CradleHook"
		m._box(Vector3(side * half.x * 0.45, -half.y - 0.002, half.z + 0.0012), Vector3(0.016, 0.004, 0.0024), rubber, cradle)
	# The ball joint on the back of the plate.
	var ball_local := Vector3(0.0, 0.0, -half.z - 0.016)
	m._mesh_instance(m._sphere(0.011), alloy, ball_local, cradle)
	var collar := m._mesh_instance(m._cylinder(0.009, 0.008), case_mat, Vector3(0.0, 0.0, -half.z - 0.009), cradle)
	collar.rotation.x = PI * 0.5
	# The arm down to the clamp round the bar, with a thumb wheel to lock it.
	var ball := at + basis * ball_local
	var bar_dir: Vector3 = m.bar_point(_back_of(m, clamp))[1]
	var out := ball - clamp
	out = (out - bar_dir * out.dot(bar_dir)).normalized()
	var clamp_top := clamp + out * 0.02
	m._tube(clamp_top, ball, 0.006, alloy, Vector3.ONE, m._steer_node).name = "PhoneArm"
	var wheel := m._mesh_instance(m._cylinder(0.013, 0.007), case_mat, clamp_top.lerp(ball, 0.45), m._steer_node)
	wheel.basis = m._basis_up((ball - clamp_top).normalized())
	var ring := m._mesh_instance(m._cylinder(0.019, 0.03), case_mat, clamp, m._steer_node)
	ring.basis = m._basis_up(bar_dir)
	ring.name = "PhoneClamp"
	m._mesh_instance(m._cylinder(0.006, 0.014), alloy, clamp - out * 0.02, m._steer_node).basis = m._basis_up(-out)
	# The screen: a quad on the glass, looking out of it at the rider.
	var quad := QuadMesh.new()
	quad.size = Vector2(sw, sh)
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_color = Color(0.02, 0.03, 0.04)
	var screen := m._mesh_instance(quad, screen_mat, Vector3(0.0, 0.0, half.z + 0.0005), cradle)
	screen.name = "SatnavScreen"
	# Kept out of the merged meshes: its texture changes as you ride.
	screen.set_meta("satnav_screen", true)
	m._satnav_screen = screen
	_glow(m, cradle, Vector3(0.0, 0.0, 0.05))


## Where a phone `keep` (half its size with the cradle) goes on `m`'s bars for `eye` (see _phone):
## the best of the places tried, as _phone_fit gives it, with "spot" (which place it was).
static func _phone_place(m: BikeModel, keep: Vector3, eye: Vector3) -> Dictionary:
	var bars := m._bars_mesh()
	var others := _near_bars(m)
	var spots := []   # [clamp on the bar, the phone's middle]
	for back in [0.19, 0.22, 0.16, 0.25, 0.28]:
		var c: Vector3 = m.bar_point(back)[0]
		if c.x < 0.05:
			continue
		for fwd in [-0.035, -0.07]:
			for up in [0.07, 0.09, 0.05, 0.11]:
				for dx in [0.0, -0.03, 0.03]:
					spots.append([c, c + Vector3(dx, up, fwd)])
	var mid: Vector3 = m.bar_point(maxf(m.bar_length() - 0.05, 0.0))[0]
	for up in [0.12, 0.15, 0.18, 0.21]:
		for fwd in [-0.08, -0.12, -0.04]:
			spots.append([mid, Vector3(0.0, mid.y + up, mid.z + fwd)])
	var best := {}
	for i in spots.size():
		var o: Vector3 = spots[i][1]
		var fit := _phone_fit(m, o, _facing(o, eye), keep, spots[i][0], eye, bars, others)
		fit["spot"] = i
		if best.is_empty() or int(fit["score"]) < int(best["score"]):
			best = fit
		if int(fit["score"]) == 0:
			break
	m._bars_tm = null   # as build_from leaves it: the fit checks make it afresh
	return best


## A sat nav's face turned to look at `eye` from `at`: X along the phone (to the rider's right),
## Y up its face, Z out of the glass.
static func _facing(at: Vector3, eye: Vector3) -> Basis:
	var n := (eye - at).normalized()
	var r := (Vector3.RIGHT - n * n.x).normalized()
	return Basis(r, n.cross(r), n)


## How far in from the bar's end (m, along it) the point of the bar nearest `p` is.
static func _back_of(m: BikeModel, p: Vector3) -> float:
	var line := m.bar_line()
	var back := 0.0
	var best := INF
	var at := 0.0
	for i in range(line.size() - 1, 0, -1):
		var a := line[i]
		var b := line[i - 1]
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		if c.distance_to(p) < best:
			best = c.distance_to(p)
			at = back + a.distance_to(c)
		back += a.distance_to(b)
	return at


## The parts round the bars a phone has to keep clear of (PHONE_CLEAR), as triangles in steering
## space, or null with none there.
static func _near_bars(m: BikeModel) -> TriangleMesh:
	var room := AABB(Vector3(-0.6, -0.3, -0.5), Vector3(1.2, 0.9, 0.9))
	var to_steer := m._steer_node.transform.affine_inverse()
	var faces := PackedVector3Array()
	for slot in PHONE_CLEAR:
		for mi in m._slot_meshes.get(slot, []):
			if not (mi is MeshInstance3D) or not is_instance_valid(mi) or (mi as MeshInstance3D).mesh == null:
				continue
			var xf := to_steer * m._local_xform(mi)
			if not (xf * (mi as MeshInstance3D).get_aabb()).intersects(room):
				continue
			faces.append_array(xf * (mi as MeshInstance3D).mesh.get_faces())
	if faces.is_empty():
		return null
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces)
	return tm


## How well a phone fits with its middle at `o` turned `b` (`keep`: half its size with the
## cradle), on an arm to `clamp`: {score (0 is a clean fit), centre, clamp, dash_hidden (points
## of the clocks it hides from the eye), hits (what it runs into), blocked (sight lines from the
## eye to the screen cut)}.
static func _phone_fit(m: BikeModel, o: Vector3, b: Basis, keep: Vector3, clamp: Vector3, eye: Vector3,
		bars: TriangleMesh, others: TriangleMesh) -> Dictionary:
	var hidden := 0
	for q in m._dash_face:
		if _seg_box(q, eye, o, b, keep + Vector3(0.004, 0.004, 0.004)):
			hidden += 1
	var hits := 0
	# Lines across the front and back of it and through it: a stalk through it crosses one.
	var segs := []
	for z in [-keep.z, keep.z]:
		for k in 6:
			var y := lerpf(-keep.y, keep.y, k / 5.0)
			segs.append([Vector3(-keep.x, y, z), Vector3(keep.x, y, z)])
		for k in 10:
			var x := lerpf(-keep.x, keep.x, k / 9.0)
			segs.append([Vector3(x, -keep.y, z), Vector3(x, keep.y, z)])
	for i in 4:
		for j in 3:
			segs.append([Vector3(lerpf(-keep.x, keep.x, i / 3.0), lerpf(-keep.y, keep.y, j / 2.0), -keep.z),
				Vector3(lerpf(-keep.x, keep.x, i / 3.0), lerpf(-keep.y, keep.y, j / 2.0), keep.z)])
	for s in segs:
		var a: Vector3 = o + b * (s[0] as Vector3)
		var e: Vector3 = o + b * (s[1] as Vector3)
		if (bars != null and not bars.intersect_segment(a, e).is_empty()) or (others != null and not others.intersect_segment(a, e).is_empty()):
			hits += 1
	# The arm, from just off the bar to the back of the cradle.
	var ball := o + b * Vector3(0.0, 0.0, -keep.z - 0.006)
	var off := clamp + (ball - clamp).normalized() * 0.03
	if others != null and not others.intersect_segment(off, ball).is_empty():
		hits += 1
	# Seen from the eye: the middle and the corners of the screen.
	var blocked := 0
	for c in [Vector3.ZERO, Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0)]:
		var pt: Vector3 = o + b * ((c as Vector3) * (keep - Vector3(0.02, 0.012, 0.0)) + Vector3(0.0, 0.0, keep.z + 0.002))
		var from := pt + (eye - pt).normalized() * 0.004
		if (bars != null and not bars.intersect_segment(from, eye).is_empty()) or (others != null and not others.intersect_segment(from, eye).is_empty()):
			blocked += 1
	return {"score": hidden * 3 + hits * 2 + blocked, "centre": o, "clamp": clamp, "dash_hidden": hidden, "hits": hits, "blocked": blocked}


## Whether the segment from `a` to `b` passes through the box with its middle at `o`, turned
## `basis` (orthonormal) and `half` of its size each way.
static func _seg_box(a: Vector3, b: Vector3, o: Vector3, basis: Basis, half: Vector3) -> bool:
	var inv := basis.transposed()
	var la := inv * (a - o)
	var d := inv * (b - a)
	var t0 := 0.0
	var t1 := 1.0
	for k in 3:
		if absf(d[k]) < 0.000001:
			if absf(la[k]) > half[k]:
				return false
			continue
		var u := (-half[k] - la[k]) / d[k]
		var v := (half[k] - la[k]) / d[k]
		t0 = maxf(t0, minf(u, v))
		t1 = minf(t1, maxf(u, v))
		if t0 > t1:
			return false
	return true


## The still map a lit sat nav screen shows on a bike whose rider's own sat nav isn't drawing
## it (everyone else's in co-op): a road with the way picked out up it and the arrow low down,
## in SatnavScreen's colours. Made once and shared.
static func idle_screen() -> ImageTexture:
	if _idle_tex != null:
		return _idle_tex
	var w := 80
	var h := 50
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(SatnavScreen.LAND)
	var dot := func(c: Vector2, r: float, col: Color) -> void:
		for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, h)):
			for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, w)):
				if Vector2(x, y).distance_to(c) <= r:
					img.set_pixel(x, y, col)
	# A side road across, and the road ahead bending away up the screen with the way on it.
	for i in 41:
		dot.call(Vector2(i / 40.0 * w, 30.0 - 10.0 * i / 40.0), 1.6, SatnavScreen.ROAD)
	for pass_ in [[2.2, SatnavScreen.ROAD], [1.3, SatnavScreen.ROUTE]]:
		for i in 41:
			var t := i / 40.0
			dot.call(Vector2(40.0 + 14.0 * t * t, 37.0 - 34.0 * t), float(pass_[0]), pass_[1])
	# The bike's arrow, and the strip along the top.
	for y in range(34, 42):
		var aw := (y - 34) * 0.5
		for x in range(int(40.0 - aw), int(40.0 + aw) + 1):
			img.set_pixel(x, y, Color.WHITE)
	img.fill_rect(Rect2i(0, 0, w, 7), SatnavScreen.BACK)
	img.fill_rect(Rect2i(3, 2, 18, 3), SatnavScreen.ROUTE)
	img.fill_rect(Rect2i(w - 16, 2, 13, 3), Color(1, 1, 1, 0.8))
	_idle_tex = ImageTexture.create_from_image(img)
	return _idle_tex
