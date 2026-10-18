class_name SalesOffice
extends Node3D
## The sales office: a two-storey glass-fronted building east of the paint shop, on its own
## block-paved forecourt and car park. Downstairs is a double-height showroom with four lit
## display plinths for bikes, the reception desk, a viewing area of sofas looking at the
## showroom, and a kitchen. Stairs along the back wall climb to a mezzanine office that looks
## down over the showroom. The front doors slide open for anyone walking up to them, and a brass
## shop bell over them rings when someone comes in (Shed.ring_bell), with a chime in the shed so
## the crew hear it at work. Its lights are on their own switch ("sales"), and the sign, canopy
## and car park lights come on at dusk.
##
## Local layout (x from CENTER.x, z from CENTER.z; the glass front faces +z, onto the yard):
##   x -7.0..-1.5: under the mezzanine: kitchen at the back, reception desk, viewing sofas at the
##                 front; the office is on the mezzanine above (floor at MEZZ_Y).
##   x -1.5..7.0:  the double-height showroom; the stairs run up the back wall (z -6.0..-4.8)
##                 from x 4.5 on the floor to x -1.5 at the mezzanine.

const CENTER := Vector3(24.5, 0.0, 63.0)
const HALF := Vector2(7.0, 6.0)          # interior: x 17.5..31.5, z 57.0..69.0
const WALL := 0.25
const MEZZ_Y := 3.0                       # top of the mezzanine floor
const MEZZ_EDGE := -1.5                   # local x of the mezzanine's open edge
const UNDER_Y := 2.8                      # the ceiling under the mezzanine
const CEIL_Y := 6.4                       # the showroom ceiling (and the roof's underside)
const DOOR_HALF := 1.2
const DOOR_HEIGHT := 2.6
## The stairs: local x of the bottom and top steps, and the strip of the back wall they run along.
const STAIR_LOW_X := 4.5
const STAIR_Z := Vector2(-6.0, -4.8)
const STEPS := 16
const PLINTH_RADIUS := 1.15
const PLINTH_TOP := 0.07
## The forecourt and car park in front, as an x/z rectangle (block paving over the yard).
const FORECOURT := Rect2(16.5, 69.0, 17.5, 17.0)

## Where a customer stands at the reception desk, -Z facing the counter.
const RECEPTION := Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(-1.7, 0.0, 0.5))
## Where a player stands behind the desk to talk to them, -Z facing the customer.
const RECEPTION_DESK := Transform3D(Basis(Vector3.UP, -PI * 0.5), CENTER + Vector3(-3.4, 0.0, 0.5))
## Where customers arrive from: the far edge of the car park, facing the front doors. A straight
## walk from here to RECEPTION goes through the doors and clear of the plinths and sofas.
const CUSTOMER_ENTRY := Transform3D(Basis(Vector3.UP, 0.2996), Vector3(29.45, 0.0, 85.0))
## The middle of the front doors, on the floor.
const SALES_DOOR := CENTER + Vector3(0.0, 0.0, 6.0)
## The showroom's display plinths: where a bike stands on show (its front, -Z, angled to the glass).
const SHOWROOM_SPOTS: Array[Transform3D] = [
	Transform3D(Basis(Vector3.UP, PI + 0.6), CENTER + Vector3(2.4, PLINTH_TOP, 3.4)),
	Transform3D(Basis(Vector3.UP, PI - 0.6), CENTER + Vector3(5.5, PLINTH_TOP, 3.4)),
	Transform3D(Basis(Vector3.UP, PI + 0.6), CENTER + Vector3(2.4, PLINTH_TOP, -0.6)),
	Transform3D(Basis(Vector3.UP, PI - 0.6), CENTER + Vector3(5.5, PLINTH_TOP, -0.6)),
]
## The shop bell over the front doors, and its chime box high on the shed's front wall inside.
const BELL_POS := CENTER + Vector3(0.9, 2.78, 5.82)
const SHED_CHIME_POS := Vector3(3.9, 3.7, 70.42)
## Bikes let go of this close to a plinth go onto it.
const SPOT_SNAP := 0.9
## Anyone (or any node in this group) this close to the front doors opens them.
const VISITOR_GROUP := "sales_visitor"
const DOOR_REACH := 3.0

var _mats := {}
var _lights: Array[Light3D] = []
var _glow_mats: Array[StandardMaterial3D] = []
var _probe: ReflectionProbe
var _lights_shown = null
var _rockers: Array[Node3D] = []
var _leaves: Array[Node3D] = []        # the two sliding door leaves (with their collision)
var door_open_amount := 0.0
var _bell: Node3D
var _chime: Node3D
var _bell_t := -1.0
## The service bell on the reception counter: where it is, its plunger and its press.
var desk_bell_pos := Vector3.ZERO
var _desk_plunger: MeshInstance3D
var _desk_t := -1.0


## The building's floor as an x/z rectangle.
static func footprint() -> Rect2:
	return Rect2(CENTER.x - HALF.x, CENTER.z - HALF.y, HALF.x * 2.0, HALF.y * 2.0)


## The mezzanine office's floor as an x/z rectangle (upstairs, at MEZZ_Y).
static func office_rect() -> Rect2:
	return Rect2(CENTER.x - HALF.x, CENTER.z - HALF.y, HALF.x + MEZZ_EDGE, HALF.y * 2.0)


## Which showroom spot is within SPOT_SNAP of `at` (x/z), or -1.
static func spot_near(at: Vector3) -> int:
	for i in SHOWROOM_SPOTS.size():
		var o: Vector3 = SHOWROOM_SPOTS[i].origin
		if Vector2(o.x - at.x, o.z - at.z).length() < SPOT_SNAP:
			return i
	return -1


## The price card's text on stand `i` (SalesView writes on it), or null.
func stand_tag(i: int) -> Label3D:
	return find_child("StandTag%d" % i, true, false) as Label3D


## The office PC's screen text (SalesView keeps it up to date), or null.
func screen_text() -> Label3D:
	return get_node_or_null("OfficeScreenText") as Label3D


## The height of the stairs' walking surface at local x `lx` (0 at the bottom, MEZZ_Y at the top).
static func stair_height(lx: float) -> float:
	return clampf((STAIR_LOW_X - lx) / (STAIR_LOW_X - MEZZ_EDGE), 0.0, 1.0) * MEZZ_Y


func build() -> void:
	name = "SalesOffice"
	add_to_group("sales_office")
	_make_materials()
	_build_paving()
	_build_shell()
	_build_front()
	_build_mezzanine()
	_build_stairs()
	_build_showroom()
	_build_reception()
	_build_lounge()
	_build_kitchen()
	_build_office()
	_build_signs()
	_build_lights()
	_build_bell()
	_build_doors()
	set_lights(Shed.room_lit("sales"))


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("rooms", pt)


func _process_body(delta: float) -> void:
	if _lights_shown != Shed.room_lit("sales"):
		set_lights(Shed.room_lit("sales"))
	_update_doors(delta)
	_swing_bell(delta)
	if _desk_t >= 0.0 and _desk_plunger:
		_desk_t += delta
		_desk_plunger.position.y = desk_bell_pos.y + 0.03 - 0.012 * maxf(0.0, 1.0 - _desk_t / 0.15)
		if _desk_t > 0.15:
			_desk_t = -1.0


# ---------------------------------------------------------------------------- the bell and doors

## Swings the shop bell over the door and the chime box's striker (the sound is Sfx.bell).
func ring() -> void:
	_bell_t = 0.0


## The counter bell was dinged: its plunger dips and it goes "ding".
func _on_desk_bell() -> void:
	_desk_t = 0.0
	Sfx.play_at("desk_bell", to_global(desk_bell_pos), 0.0)


func _swing_bell(delta: float) -> void:
	if _bell_t < 0.0 or _bell == null:
		return
	_bell_t += delta
	var swing := sin(_bell_t * 17.0) * 0.55 * exp(-_bell_t * 2.2)
	_bell.rotation.x = swing
	if _chime:
		_chime.rotation.z = swing * 0.6
	if _bell_t > 3.0:
		_bell_t = -1.0
		_bell.rotation.x = 0.0
		if _chime:
			_chime.rotation.z = 0.0


## Whether anyone is close to the front doors: players, riders, and anything in VISITOR_GROUP.
func someone_at_door() -> bool:
	if not is_inside_tree():
		return false
	for group in ["local_walker", "remote_players", "ridden_bike", VISITOR_GROUP]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D and (n as Node3D).is_inside_tree():
				var p := (n as Node3D).global_position
				if Vector2(p.x - SALES_DOOR.x, p.z - SALES_DOOR.z).length() < DOOR_REACH and absf(p.y - SALES_DOOR.y) < 2.0:
					return true
	return false


func _update_doors(delta: float) -> void:
	var want := 1.0 if someone_at_door() else 0.0
	door_open_amount = move_toward(door_open_amount, want, delta / 0.7)
	var k := smoothstep(0.0, 1.0, door_open_amount)
	for i in _leaves.size():
		var side := -1.0 if i == 0 else 1.0
		_leaves[i].position = CENTER + Vector3(side * (DOOR_HALF * 0.5 + k * DOOR_HALF * 0.98), DOOR_HEIGHT * 0.5, HALF.y - 0.12)


# ---------------------------------------------------------------------------- lights

## The sales office's lights on or off (its switches inside, by the stairs and at the top).
func set_lights(on: bool) -> void:
	_lights_shown = on
	for l in _lights:
		l.visible = on
	for m in _glow_mats:
		m.emission_energy_multiplier = float(m.get_meta("on", 3.0)) if on else 0.0
	if _probe:
		_probe.ambient_color_energy = 0.5 if on else 0.03
		_probe.intensity = 1.0 if on else 0.2
	for r in _rockers:
		r.rotation.x = 0.0 if on else 0.5


func lights_shown() -> bool:
	return _lights_shown == true


# ---------------------------------------------------------------------------- materials

func _make_materials() -> void:
	_mats["render"] = _material(Color(0.9, 0.9, 0.88), 0.0, 0.8, _noise(0.3, 0.94, 1.03), 2.0)
	_mats["anthracite"] = _material(Color(0.11, 0.12, 0.13), 0.55, 0.4)
	_mats["alu"] = _material(Color(0.16, 0.17, 0.18), 0.8, 0.3)
	_mats["steel"] = _material(Color(0.75, 0.76, 0.78), 1.0, 0.2)
	_mats["chrome"] = _material(Color(0.9, 0.9, 0.92), 1.0, 0.08)
	_mats["brass"] = _material(Color(0.85, 0.65, 0.25), 1.0, 0.25)
	_mats["orange"] = _material(Color(0.95, 0.42, 0.05), 0.2, 0.35)
	_mats["oak"] = _material(Color(0.62, 0.45, 0.28), 0.0, 0.5, _noise(0.9, 0.85, 1.1), 3.0)
	_mats["white_gloss"] = _material(Color(0.95, 0.95, 0.95), 0.0, 0.15)
	_mats["quartz"] = _material(Color(0.93, 0.92, 0.9), 0.0, 0.1, _noise(1.5, 0.92, 1.02), 2.0)
	_mats["stone_dark"] = _material(Color(0.1, 0.1, 0.11), 0.1, 0.12, _noise(1.2, 0.8, 1.15), 2.0)
	_mats["fabric"] = _material(Color(0.2, 0.28, 0.33), 0.0, 0.95, _noise(3.0, 0.9, 1.06), 4.0)
	_mats["fabric_warm"] = _material(Color(0.55, 0.42, 0.3), 0.0, 0.95, _noise(3.0, 0.9, 1.06), 4.0)
	_mats["leather"] = _material(Color(0.08, 0.08, 0.08), 0.0, 0.45)
	_mats["rug"] = _material(Color(0.42, 0.4, 0.37), 0.0, 1.0, _noise(2.5, 0.85, 1.1), 3.0)
	_mats["plant"] = _material(Color(0.16, 0.36, 0.14), 0.0, 0.8, _noise(4.0, 0.7, 1.2), 3.0)
	_mats["pot"] = _material(Color(0.2, 0.2, 0.2), 0.0, 0.6)
	_mats["screen"] = _material(Color(0.02, 0.03, 0.05), 0.3, 0.1)
	_mats["ceiling"] = _material(Color(0.95, 0.95, 0.94), 0.0, 0.9)
	_mats["ceiling_dark"] = _material(Color(0.07, 0.07, 0.08), 0.2, 0.7)
	_mats["show_floor"] = _material(Color(0.24, 0.24, 0.25), 0.0, 0.1, _tiles(Color(1, 1, 1), Color(0.6, 0.6, 0.6)), 1.0)
	(_mats["show_floor"] as StandardMaterial3D).uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.9
	_mats["kitchen_floor"] = _material(Color(0.7, 0.68, 0.64), 0.0, 0.3, _tiles(Color(1, 1, 1), Color(0.75, 0.75, 0.75)), 1.0)
	(_mats["kitchen_floor"] as StandardMaterial3D).uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.45
	_mats["oak_floor"] = _material(Color(0.55, 0.4, 0.26), 0.0, 0.35, _noise(0.7, 0.85, 1.12), 6.0)
	var pave := _material(Color(0.5, 0.47, 0.44), 0.0, 0.9, _tiles(Color(1, 1, 1), Color(0.7, 0.7, 0.7), 4), 1.0)
	pave.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.4
	_mats["paving"] = pave
	_mats["tarmac"] = _material(Color(0.12, 0.12, 0.13), 0.0, 0.85, _noise(0.6, 0.85, 1.1), 3.0)
	_mats["line"] = _material(Color(0.92, 0.92, 0.88), 0.0, 0.6)
	_mats["kerb"] = _material(Color(0.62, 0.61, 0.58), 0.0, 0.85)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.76, 0.8, 0.16)
	glass.metallic = 0.3
	glass.metallic_specular = 0.9
	glass.roughness = 0.03
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = glass
	var balustrade: StandardMaterial3D = glass.duplicate()
	balustrade.albedo_color = Color(0.7, 0.85, 0.85, 0.12)
	_mats["glass_rail"] = balustrade
	# Glowing bits that follow the light switch: LED strips, downlights, the plinths' rings.
	_mats["led"] = _glow(Color(1.0, 0.96, 0.9), 3.0)
	_mats["led_orange"] = _glow(Color(1.0, 0.45, 0.08), 2.5)
	_mats["monitor"] = _glow(Color(0.05, 0.12, 0.28), 1.0)
	# And the outside ones that come on at dusk.
	_mats["night_white"] = _night_glow(Color(1.0, 0.95, 0.85))
	_mats["night_orange"] = _night_glow(Color(1.0, 0.45, 0.08))


func _material(color: Color, metallic: float, roughness: float, tex: Texture2D = null, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv) * 0.25
	return m


## A material that glows while the office lights are on (set_lights).
func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _material(color, 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.set_meta("on", energy)
	_glow_mats.append(m)
	return m


## A material for the outside lights; Daylight brightens it at dusk (its NIGHT_LIGHTS group,
## through the meshes using it: see _night).
func _night_glow(color: Color) -> StandardMaterial3D:
	var m := _material(color, 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.05
	return m


func _night(mi: GeometryInstance3D, energy: float) -> void:
	mi.set_meta("night_emission", energy)
	mi.add_to_group(Daylight.NIGHT_LIGHTS)


func _noise(freq: float, dark: float, light: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.1
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color(light, light, light))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


## A square tile with grout lines round it (or `bricks` rows of offset block paving), one tile a
## texture repeat.
func _tiles(tile: Color, grout: Color, bricks := 0) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in n:
		for x in n:
			var c := tile * rng.randf_range(0.94, 1.03)
			var edge := x < 2 or y < 2
			if bricks > 0:
				var row := y * bricks / n
				var shift := (n / 2) if row % 2 == 1 else 0
				edge = (y % (n / bricks)) < 2 or ((x + shift) % n) < 2
			if edge:
				c = grout
			c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------- pieces

func _solid(center: Vector3, size: Vector3, mat: Material, shadow := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)
	return body


func _deco(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


func _flat(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := _deco(center, size, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _cyl(center: Vector3, radius: float, height: float, mat: Material, top := -1.0, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top < 0.0 else top
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 32
	mi.mesh = cm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


func _ball(center: Vector3, radius: float, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


## Invisible collision, for furniture made of loose meshes.
func _blocker(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _label(text: String, pos: Vector3, rot_y: float, font_size: int, color: Color, pixel := 0.004, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = outline
	add_child(l)
	return l


## A point at local x/z from the centre, at height y.
static func at(x: float, y: float, z: float) -> Vector3:
	return CENTER + Vector3(x, y, z)


# ---------------------------------------------------------------------------- outside

## Block paving in front, a strip of tarmac car park with marked bays, kerbs, planters either
## side of the doors and bollards that light up at dusk, and a sign pylon by the car park.
func _build_paving() -> void:
	var f := FORECOURT
	# Block paving round the building and the forecourt; the yard concrete is the ground under it.
	_flat(Vector3(f.get_center().x, 0.006, f.position.y + 4.5), Vector3(f.size.x, 0.012, 9.0), _mats["paving"])
	var round_bldg := footprint().grow(1.0)
	_flat(Vector3(round_bldg.get_center().x, 0.005, round_bldg.get_center().y), Vector3(round_bldg.size.x, 0.01, round_bldg.size.y), _mats["paving"])
	# The car park: tarmac with five bays nose-in towards the building.
	var park := Rect2(f.position.x, f.position.y + 9.0, f.size.x, f.size.y - 9.0)
	_flat(Vector3(park.get_center().x, 0.007, park.get_center().y), Vector3(park.size.x, 0.014, park.size.y), _mats["tarmac"])
	_flat(Vector3(park.get_center().x, 0.03, park.position.y), Vector3(park.size.x, 0.06, 0.18), _mats["kerb"])
	for i in 7:
		var x := f.position.x + 2.0 + i * 2.6
		_flat(Vector3(x, 0.016, park.position.y + 2.6), Vector3(0.1, 0.004, 4.8), _mats["line"])
	_flat(Vector3(park.get_center().x, 0.016, park.position.y + 5.0), Vector3(2.6 * 6.0, 0.004, 0.1), _mats["line"])
	# A walkway from the car park edge to the doors, in lighter paving.
	var walk := _material(Color(0.66, 0.63, 0.58), 0.0, 0.85, _tiles(Color(1, 1, 1), Color(0.75, 0.75, 0.75)), 1.0)
	walk.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.6
	_flat(Vector3(CENTER.x, 0.014, f.position.y + 4.5), Vector3(3.0, 0.004, 9.0), walk)
	# Planters with clipped hedges either side of the walkway, and bollards that glow at night.
	for side in [-1.0, 1.0]:
		var px: float = CENTER.x + side * 4.6
		_solid(Vector3(px, 0.25, HALF.y + CENTER.z + 1.4), Vector3(4.0, 0.5, 1.0), _mats["anthracite"])
		_deco(Vector3(px, 0.72, HALF.y + CENTER.z + 1.4), Vector3(3.8, 0.45, 0.8), _mats["plant"])
		for k in 3:
			var bx: float = CENTER.x + side * 1.9
			var bz: float = CENTER.z + HALF.y + 3.0 + k * 2.2
			_cyl(Vector3(bx, 0.45, bz), 0.09, 0.9, _mats["anthracite"])
			var cap := _cyl(Vector3(bx, 0.8, bz), 0.095, 0.12, _mats["night_white"])
			_night(cap, 4.0)
	# The sign pylon at the car park's corner, lit at night.
	var py := Vector3(f.end.x - 1.0, 0.0, f.position.y + 8.6)
	_solid(py + Vector3(0.0, 2.0, 0.0), Vector3(1.1, 4.0, 0.35), _mats["anthracite"])
	var strip := _deco(py + Vector3(-0.47, 2.0, 0.18), Vector3(0.06, 3.8, 0.02), _mats["night_orange"])
	_night(strip, 3.0)
	_label("TORQUE\nSHED", py + Vector3(0.0, 3.2, 0.19), 0.0, 64, Color(1.0, 0.85, 0.35), 0.004)
	_label("SALES", py + Vector3(0.0, 2.3, 0.19), 0.0, 48, Color(1, 1, 1), 0.004)
	_label("OPEN", py + Vector3(0.0, 1.0, 0.19), 0.0, 40, Color(0.5, 1.0, 0.6), 0.004)
	# Car park lamps: two slim poles with down-lights.
	for x in [f.position.x + 2.0, f.end.x - 1.5]:
		var base := Vector3(x, 0.0, f.end.y - 0.6)
		_cyl(base + Vector3(0.0, 2.5, 0.0), 0.06, 5.0, _mats["alu"])
		_deco(base + Vector3(0.0, 5.0, -0.4), Vector3(0.25, 0.08, 0.9), _mats["alu"])
		var lens := _deco(base + Vector3(0.0, 4.955, -0.5), Vector3(0.2, 0.01, 0.6), _mats["night_white"])
		_night(lens, 5.0)
		var spot := SpotLight3D.new()
		spot.position = base + Vector3(0.0, 4.9, -0.5)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 60.0
		spot.spot_range = 9.0
		spot.light_color = Color(1.0, 0.92, 0.8)
		spot.light_energy = 0.0
		spot.visible = false
		spot.set_meta("night_energy", 4.0)
		spot.add_to_group(Daylight.NIGHT_LIGHTS)
		add_child(spot)


# ---------------------------------------------------------------------------- the building

func _build_shell() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var t := WALL
	var h := CEIL_Y
	# Floors: polished tiles in the showroom and reception, oak boards in the lounge, kitchen tiles.
	_flat(at(MEZZ_EDGE * 0.5 + hx * 0.5, 0.012, 0.0), Vector3(hx - MEZZ_EDGE, 0.006, hz * 2.0), _mats["show_floor"])
	_flat(at(-hx * 0.5 + MEZZ_EDGE * 0.5, 0.012, 0.15), Vector3(hx + MEZZ_EDGE, 0.006, 3.1), _mats["show_floor"])
	_flat(at(-hx * 0.5 + MEZZ_EDGE * 0.5, 0.012, 3.85), Vector3(hx + MEZZ_EDGE, 0.006, 4.3), _mats["oak_floor"])
	_flat(at(-hx * 0.5 + MEZZ_EDGE * 0.5, 0.012, -3.7), Vector3(hx + MEZZ_EDGE, 0.006, 4.6), _mats["kitchen_floor"])
	# A floor slab under it all (the yard concrete is there too; this keeps the edges tidy).
	_solid(at(0.0, -0.1, 0.0), Vector3(hx * 2.0 + t * 2.0, 0.2, hz * 2.0 + t * 2.0), _mats["kerb"])
	# Back and west walls solid, white render; the east wall solid at the back half, glass at the front.
	_solid(at(0.0, h * 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, h, t), _mats["render"])
	_solid(at(-hx - t * 0.5, h * 0.5, 0.0), Vector3(t, h, hz * 2.0), _mats["render"])
	var east_solid := 6.5   # local z -6.0..0.5
	_solid(at(hx + t * 0.5, h * 0.5, -hz + east_solid * 0.5), Vector3(t, h, east_solid), _mats["render"])
	var glass_len := hz * 2.0 - east_solid
	var gz := -hz + east_solid + glass_len * 0.5
	_solid(at(hx + t * 0.5, h * 0.5, gz), Vector3(0.04, h, glass_len), _mats["glass"], false)
	for k in 4:
		var z := -hz + east_solid + k * glass_len / 3.0
		_deco(at(hx + t * 0.5, h * 0.5, z), Vector3(0.12, h, 0.08), _mats["alu"])
	_deco(at(hx + t * 0.5, MEZZ_Y, gz), Vector3(0.14, 0.18, glass_len), _mats["alu"])
	# Dark cladding accents outside: a band round the base and a panel up the west end.
	_deco(at(-hx - t - 0.01, 0.3, 0.0), Vector3(0.02, 0.6, hz * 2.0 + t * 2.0), _mats["anthracite"])
	_deco(at(0.0, 0.3, -hz - t - 0.01), Vector3(hx * 2.0 + t * 2.0, 0.6, 0.02), _mats["anthracite"])
	_deco(at(hx + t + 0.01, 0.3, -hz + east_solid * 0.5), Vector3(0.02, 0.6, east_solid), _mats["anthracite"])
	_deco(at(-hx - t - 0.015, h * 0.5 + 0.4, hz - 1.5), Vector3(0.02, h + 0.8, 3.0), _mats["anthracite"])
	_deco(at(hx + t + 0.015, h * 0.5 + 0.4, -hz + 1.5), Vector3(0.02, h + 0.8, 3.0), _mats["anthracite"])
	# Flat roof with a parapet; the dark fascia carries the sign over the glass.
	_solid(at(0.0, h + 0.15, 0.0), Vector3(hx * 2.0 + t * 2.0, 0.3, hz * 2.0 + t * 2.0), _mats["render"])
	for side in [-1.0, 1.0]:
		_deco(at(side * (hx + t * 0.5), h + 0.6, 0.0), Vector3(t, 0.6, hz * 2.0 + t * 2.0), _mats["render"])
	_deco(at(0.0, h + 0.6, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, 0.6, t), _mats["render"])
	_deco(at(0.0, h + 0.45, hz + 0.2), Vector3(hx * 2.0 + t * 2.0 + 0.3, 0.9, 0.4), _mats["anthracite"])
	var under_strip := _deco(at(0.0, h - 0.02, hz + 0.35), Vector3(hx * 2.0 + t * 2.0, 0.03, 0.06), _mats["night_orange"])
	_night(under_strip, 3.0)
	# Ceilings: dark over the double-height showroom with lines of LED strip, white under the
	# mezzanine (its own underside) with round downlights.
	var ceil := _flat(at(MEZZ_EDGE * 0.5 + hx * 0.5, h - 0.01, 0.0), Vector3(hx - MEZZ_EDGE, 0.02, hz * 2.0), _mats["ceiling_dark"])
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 5:
		var z := -hz + 1.2 + k * (hz * 2.0 - 2.4) / 4.0
		_flat(at(MEZZ_EDGE * 0.5 + hx * 0.5, h - 0.03, z), Vector3(hx - MEZZ_EDGE - 1.0, 0.025, 0.05), _mats["led"])
	_flat(at(-hx * 0.5 + MEZZ_EDGE * 0.5, h - 0.01, 0.0), Vector3(hx + MEZZ_EDGE, 0.02, hz * 2.0), _mats["ceiling"])


## The glass front: two storeys of glazing in dark aluminium frames, the mezzanine's floor line
## across it, a canopy over the sliding doors.
func _build_front() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var h := CEIL_Y
	var z := hz + WALL * 0.5
	var low := MEZZ_Y - 0.06
	# Lower panes either side of the doors, the panes over them, and one tall upper pane.
	var side_w := hx - DOOR_HALF
	for side in [-1.0, 1.0]:
		_solid(at(side * (DOOR_HALF + side_w * 0.5 + WALL * 0.5), low * 0.5, z), Vector3(side_w + WALL, low, 0.04), _mats["glass"], false)
	_solid(at(0.0, (DOOR_HEIGHT + 0.15 + low) * 0.5, z), Vector3(DOOR_HALF * 2.0, low - DOOR_HEIGHT - 0.15, 0.04), _mats["glass"], false)
	_solid(at(0.0, (MEZZ_Y + 0.12 + h) * 0.5, z), Vector3(hx * 2.0 + WALL * 2.0, h - MEZZ_Y - 0.12, 0.04), _mats["glass"], false)
	# Mullions, the transom at the mezzanine's floor line, and the door head.
	for x in [-hx - WALL * 0.5, -hx * 0.75, -hx * 0.5, MEZZ_EDGE, -DOOR_HALF, DOOR_HALF, 3.4, 5.2, hx + WALL * 0.5]:
		var w := WALL if absf(x) > hx else 0.08
		var mullion_h := h if absf(x) != DOOR_HALF else h - DOOR_HEIGHT
		var mullion_y := h * 0.5 if absf(x) != DOOR_HALF else (h + DOOR_HEIGHT) * 0.5
		_deco(at(float(x), mullion_y, z), Vector3(w, mullion_h, 0.12), _mats["alu"])
	_deco(at(0.0, MEZZ_Y + 0.03, z), Vector3(hx * 2.0, 0.18, 0.14), _mats["alu"])
	_deco(at(0.0, DOOR_HEIGHT + 0.075, z - 0.05), Vector3(DOOR_HALF * 2.0 + 0.3, 0.15, 0.24), _mats["alu"])
	for side in [-1.0, 1.0]:
		_deco(at(side * DOOR_HALF, DOOR_HEIGHT * 0.5, z), Vector3(0.1, DOOR_HEIGHT, 0.14), _mats["alu"])
	# The canopy over the doors, with downlights that come on at dusk.
	_solid(at(0.0, 3.45, hz + 1.1), Vector3(5.2, 0.16, 2.0), _mats["anthracite"])
	_deco(at(0.0, 3.36, hz + 2.08), Vector3(5.2, 0.04, 0.05), _mats["night_orange"]).name = "CanopyEdge"
	_night(get_node("CanopyEdge"), 3.0)
	for x in [-1.6, 1.6]:
		var lamp := _cyl(at(x, 3.365, hz + 1.2), 0.09, 0.01, _mats["night_white"])
		_night(lamp, 6.0)
		var spot := SpotLight3D.new()
		spot.position = at(x, 3.34, hz + 1.2)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 55.0
		spot.spot_range = 5.0
		spot.light_color = Color(1.0, 0.9, 0.75)
		spot.light_energy = 0.0
		spot.visible = false
		spot.set_meta("night_energy", 3.0)
		spot.add_to_group(Daylight.NIGHT_LIGHTS)
		add_child(spot)
	# Door mat inside.
	_flat(at(0.0, 0.016, hz - 0.8), Vector3(2.2, 0.012, 1.2), _mats["leather"])


## The mezzanine: a slab over the west end at MEZZ_Y, its open edge on the showroom behind a
## glass balustrade with a steel handrail; the stairs arrive at its back corner.
func _build_mezzanine() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var w := hx + MEZZ_EDGE
	var mid := (-hx + MEZZ_EDGE) * 0.5
	var slab := _solid(at(mid, (UNDER_Y + MEZZ_Y) * 0.5, 0.0), Vector3(w, MEZZ_Y - UNDER_Y, hz * 2.0), _mats["render"])
	slab.name = "Mezzanine"
	_flat(at(mid, MEZZ_Y + 0.004, 0.0), Vector3(w, 0.008, hz * 2.0), _mats["oak_floor"])
	_deco(at(MEZZ_EDGE + 0.01, (UNDER_Y + MEZZ_Y) * 0.5, 0.0), Vector3(0.03, MEZZ_Y - UNDER_Y + 0.02, hz * 2.0), _mats["anthracite"])
	# Glass balustrade along the open edge (not across the top of the stairs).
	var from := STAIR_Z.y
	var len := hz - from
	var rail_z := from + len * 0.5
	var rail := _solid(at(MEZZ_EDGE - 0.06, MEZZ_Y + 0.55, rail_z), Vector3(0.03, 1.1, len), _mats["glass_rail"], false)
	rail.name = "MezzanineRail"
	var bar := _deco(at(MEZZ_EDGE - 0.06, MEZZ_Y + 1.12, rail_z), Vector3(0.06, 0.05, len), _mats["steel"])
	bar.name = "Handrail"
	for k in 8:
		_deco(at(MEZZ_EDGE - 0.06, MEZZ_Y + 0.55, from + k * len / 7.0), Vector3(0.05, 1.1, 0.05), _mats["steel"])
	# Under the slab: the kitchen's walls (its east side and the partition with its doorway).
	var kz := -1.4
	var kitchen_len := kz - (-hz)
	_solid(at(MEZZ_EDGE - 0.06, UNDER_Y * 0.5, -hz + kitchen_len * 0.5), Vector3(0.12, UNDER_Y, kitchen_len), _mats["render"])
	var door_lo := -2.6
	var door_hi := -1.7
	_solid(at((-hx + door_lo) * 0.5, UNDER_Y * 0.5, kz), Vector3(door_lo + hx, UNDER_Y, 0.12), _mats["render"])
	_solid(at((door_hi + MEZZ_EDGE) * 0.5, UNDER_Y * 0.5, kz), Vector3(MEZZ_EDGE - door_hi, UNDER_Y, 0.12), _mats["render"])
	_solid(at((door_lo + door_hi) * 0.5, (2.2 + UNDER_Y) * 0.5, kz), Vector3(door_hi - door_lo, UNDER_Y - 2.2, 0.12), _mats["render"])
	_label("KITCHEN", at((door_lo + door_hi) * 0.5, 2.45, kz + 0.07), 0.0, 28, Color(0.15, 0.15, 0.16), 0.003)
	# Round downlights in the ceiling under the mezzanine.
	for p in [Vector2(-5.5, 3.0), Vector2(-3.5, 3.0), Vector2(-5.5, 5.0), Vector2(-3.5, 5.0), Vector2(-2.5, -0.3), Vector2(-2.5, 1.3),
			Vector2(-5.5, 0.4), Vector2(-5.5, -3.0), Vector2(-3.5, -3.0), Vector2(-5.5, -5.0), Vector2(-3.5, -5.0)]:
		_cyl(at(p.x, UNDER_Y - 0.005, p.y), 0.08, 0.01, _mats["led"])


## The stairs up the back wall: solid white-rendered flights with oak treads and a glass
## balustrade with a steel handrail on the open side. Each step is drawn, but what you walk on
## is a smooth ramp under the treads, so the walker climbs them without catching an edge.
func _build_stairs() -> void:
	var run := STAIR_LOW_X - MEZZ_EDGE
	var rise := MEZZ_Y / STEPS
	var going := run / STEPS
	var z0 := STAIR_Z.x
	var z1 := STAIR_Z.y
	var zm := (z0 + z1) * 0.5
	var width := z1 - z0
	for i in STEPS:
		var top := (i + 1) * rise
		var x := STAIR_LOW_X - (i + 0.5) * going
		_deco(at(x, top * 0.5, zm), Vector3(going + 0.002, top - 0.03, width), _mats["render"])
		_deco(at(x - 0.01, top - 0.02, zm), Vector3(going + 0.03, 0.04, width), _mats["oak"])
		_deco(at(x + going * 0.5 - 0.01, top - 0.045, zm), Vector3(0.012, 0.012, width - 0.1), _mats["led"])
	# The ramp the walker actually climbs: a thin box along the line of the step noses.
	var length := sqrt(run * run + MEZZ_Y * MEZZ_Y)
	var angle := atan2(MEZZ_Y, run)
	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.set_meta("surface", "tarmac")
	var shape := BoxShape3D.new()
	shape.size = Vector3(length + 0.1, 0.1, width)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ramp.add_child(cs)
	var mid := Vector3((STAIR_LOW_X + MEZZ_EDGE) * 0.5, MEZZ_Y * 0.5, zm)
	var normal := Vector3(sin(angle), cos(angle), 0.0)
	ramp.position = CENTER + mid - normal * 0.05
	ramp.rotation.z = -angle
	add_child(ramp)
	# The balustrade up the open side: glass panels following the pitch, and a handrail.
	var side_z := z1 + 0.04
	var glass := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 1.0, 0.02)
	glass.mesh = bm
	glass.material_override = _mats["glass_rail"]
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = CENTER + Vector3(mid.x, mid.y + 0.55, side_z)
	glass.rotation.z = -angle
	add_child(glass)
	var rail := _deco(Vector3.ZERO, Vector3(length + 0.2, 0.05, 0.06), _mats["steel"])
	rail.position = CENTER + Vector3(mid.x, mid.y + 1.07, side_z)
	rail.rotation.z = -angle
	# Its collision: a wall the full height of the flight, so nobody steps off the side or walks
	# under the top of the stairs from the showroom.
	_blocker(at(mid.x, (MEZZ_Y + 1.1) * 0.5, side_z), Vector3(run, MEZZ_Y + 1.1, 0.06))
	# A low wall round the stair's foot so the first tread isn't a trip from the side.
	_deco(at(STAIR_LOW_X + 0.15, 0.5, z1 + 0.04), Vector3(0.06, 1.0, 0.06), _mats["steel"])


# ---------------------------------------------------------------------------- inside

## The showroom: four round display plinths with chrome rims and glowing orange rings under the
## bikes, spotlit from the ceiling, and a big lit logo wall over the stairs.
func _build_showroom() -> void:
	for i in SHOWROOM_SPOTS.size():
		var o: Vector3 = SHOWROOM_SPOTS[i].origin
		var base := Vector3(o.x, 0.0, o.z)
		var plinth := StaticBody3D.new()
		plinth.name = "Plinth%d" % i
		plinth.set_meta("surface", "tarmac")
		plinth.position = base + Vector3(0.0, PLINTH_TOP * 0.5, 0.0)
		var shape := CylinderShape3D.new()
		shape.radius = PLINTH_RADIUS
		shape.height = PLINTH_TOP
		var cs := CollisionShape3D.new()
		cs.shape = shape
		plinth.add_child(cs)
		add_child(plinth)
		_cyl(base + Vector3(0.0, PLINTH_TOP * 0.5, 0.0), PLINTH_RADIUS, PLINTH_TOP, _mats["stone_dark"])
		_cyl(base + Vector3(0.0, PLINTH_TOP * 0.5, 0.0), PLINTH_RADIUS + 0.025, PLINTH_TOP - 0.02, _mats["chrome"])
		var ring := _cyl(base + Vector3(0.0, 0.012, 0.0), PLINTH_RADIUS + 0.06, 0.01, _mats["led_orange"])
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A little price stand at the front of each plinth.
		var front: Vector3 = base + (SHOWROOM_SPOTS[i].basis * Vector3(0.0, 0.0, -1.0)) * (PLINTH_RADIUS + 0.35)
		_cyl(front + Vector3(0.0, 0.45, 0.0), 0.02, 0.9, _mats["steel"])
		var card := _deco(front + Vector3(0.0, 0.95, 0.0), Vector3(0.32, 0.22, 0.015), _mats["white_gloss"])
		card.rotation.y = SHOWROOM_SPOTS[i].basis.get_euler().y + PI
		card.rotation.x = -0.35
		var tag := Label3D.new()
		tag.name = "StandTag%d" % i   # SalesView writes the bike and its price on it
		tag.text = "ON SHOW\n%d" % (i + 1)
		tag.font_size = 22
		tag.pixel_size = 0.0025
		tag.modulate = Color(0.1, 0.1, 0.1)
		tag.position = Vector3(0.0, 0.0, 0.009)
		card.add_child(tag)
	# The logo wall over the stairs: a dark panel with a lit sign and an orange stripe.
	var hx := HALF.x
	var hz := HALF.y
	_deco(at(2.6, 4.6, -hz + 0.02), Vector3(8.0, 2.6, 0.03), _mats["anthracite"])
	_deco(at(2.6, 3.45, -hz + 0.04), Vector3(8.0, 0.06, 0.02), _mats["led_orange"])
	_label("TORQUE SHED", at(2.6, 5.05, -hz + 0.05), 0.0, 120, Color(1.0, 0.85, 0.35), 0.006)
	_label("RESTORED  ·  RIDDEN  ·  RELOVED", at(2.6, 4.25, -hz + 0.05), 0.0, 40, Color(0.9, 0.9, 0.9), 0.006)
	# A tall plant either end of the front glass, and a slim bench to sit and look.
	for p in [at(hx - 0.5, 0.0, hz - 0.5), at(MEZZ_EDGE + 0.4, 0.0, -hz + 1.6 + 0.0)]:
		_plant(p, 1.6)
	_deco(at(hx - 0.35, 0.22, 1.8), Vector3(0.4, 0.06, 2.0), _mats["oak"])
	for z in [1.0, 2.6]:
		_deco(at(hx - 0.35, 0.1, z), Vector3(0.36, 0.2, 0.06), _mats["anthracite"])
	_blocker(at(hx - 0.35, 0.13, 1.8), Vector3(0.4, 0.26, 2.0))


func _plant(base: Vector3, height: float) -> void:
	_cyl(base + Vector3(0.0, 0.25, 0.0), 0.22, 0.5, _mats["pot"], 0.26)
	_cyl(base + Vector3(0.0, 0.5 + height * 0.25, 0.0), 0.025, height * 0.5, _mats["oak"])
	var leaves := _ball(base + Vector3(0.0, 0.5 + height * 0.55, 0.0), 0.38, _mats["plant"])
	leaves.scale = Vector3(1.0, height * 0.75, 1.0)
	_blocker(base + Vector3(0.0, 0.5, 0.0), Vector3(0.5, 1.0, 0.5))


## The reception desk facing the doors: an oak front with a lit orange stripe under a white
## quartz counter, a lower worktop with a screen behind it, a chrome service bell, and a wall of
## helmets on shelves behind the staff side.
func _build_reception() -> void:
	var c := RECEPTION_DESK.origin
	var desk_x := -2.55
	var z0 := -0.6
	var z1 := 1.6
	var zl := z1 - z0
	var zm := (z0 + z1) * 0.5
	_solid(at(desk_x, 0.52, zm), Vector3(0.55, 1.04, zl), _mats["oak"])
	_deco(at(desk_x + 0.05, 1.08, zm), Vector3(0.75, 0.05, zl + 0.1), _mats["quartz"])
	_deco(at(desk_x + 0.285, 0.12, zm), Vector3(0.02, 0.04, zl - 0.1), _mats["led_orange"])
	_label("RECEPTION", at(desk_x + 0.285, 0.7, zm), PI * 0.5, 40, Color(1.0, 0.85, 0.35), 0.004)
	# The staff side: a lower worktop and a monitor turned to face the player.
	_deco(at(desk_x - 0.45, 0.74, zm), Vector3(0.4, 0.04, zl), _mats["white_gloss"])
	var mon := _deco(at(desk_x - 0.42, 1.0, zm + 0.4), Vector3(0.03, 0.32, 0.52), _mats["alu"])
	mon.rotation.y = 0.0
	_deco(at(desk_x - 0.44, 1.0, zm + 0.4), Vector3(0.005, 0.28, 0.48), _mats["monitor"])
	_deco(at(desk_x - 0.4, 0.8, zm + 0.4), Vector3(0.12, 0.08, 0.12), _mats["alu"])
	# The service bell on the counter.
	var bell := Vector3(c.x + 0.85, 1.105, c.z - 0.6)
	_cyl(bell + Vector3(0.0, 0.005, 0.0), 0.06, 0.01, _mats["anthracite"])
	var dome := _ball(bell + Vector3(0.0, 0.02, 0.0), 0.05, _mats["chrome"])
	dome.scale = Vector3(1.0, 0.8, 1.0)
	_desk_plunger = _cyl(bell + Vector3(0.0, 0.07, 0.0), 0.008, 0.02, _mats["chrome"])
	desk_bell_pos = bell + Vector3(0.0, 0.04, 0.0)
	# Click it (F) to ding it.
	var body := StaticBody3D.new()
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.set_meta("desk_bell", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.12, 0.16)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = bell + Vector3(0.0, 0.04, 0.0)
	add_child(body)
	if not Shed.desk_bell_rang.is_connected(_on_desk_bell):
		Shed.desk_bell_rang.connect(_on_desk_bell)
	# Helmets on shelves along the west wall behind the desk.
	var hx := HALF.x
	var colors := [Color(0.85, 0.1, 0.08), Color(0.05, 0.05, 0.06), Color(0.95, 0.95, 0.95), Color(0.95, 0.45, 0.05),
		Color(0.1, 0.3, 0.7), Color(0.8, 0.75, 0.2), Color(0.2, 0.5, 0.25), Color(0.6, 0.6, 0.62)]
	var n := 0
	for row in 3:
		var y := 0.9 + row * 0.55
		_deco(at(-hx + 0.2, y, 0.3), Vector3(0.36, 0.03, 2.8), _mats["oak"])
		_deco(at(-hx + 0.2, y - 0.03, 0.3), Vector3(0.3, 0.01, 2.6), _mats["led"])
		for k in 4:
			var col: Color = colors[n % colors.size()]
			n += 1
			var paint := _material(col, 0.5, 0.15)
			var pos := at(-hx + 0.2, y + 0.16, -0.75 + k * 0.7)
			var shell := _ball(pos, 0.15, paint)
			shell.scale = Vector3(1.0, 0.92, 1.1)
			var visor := _ball(pos + Vector3(0.06, 0.0, 0.0), 0.12, _mats["screen"])
			visor.scale = Vector3(0.9, 0.45, 0.95)
	_blocker(at(-hx + 0.2, 1.1, 0.3), Vector3(0.4, 2.2, 2.8))
	_label("HELMETS · KIT", at(-hx + 0.02, 2.5, 0.3), PI * 0.5, 36, Color(0.2, 0.2, 0.2), 0.004)


## The viewing area at the front: a long sofa against the west wall and a second one angled in,
## both looking out over the showroom, on a rug round a low oak table, with a floor lamp.
func _build_lounge() -> void:
	var hx := HALF.x
	# Sofa A along the west wall, facing the showroom (+x).
	_sofa(Transform3D(Basis(Vector3.UP, -PI * 0.5), at(-hx + 0.5, 0.0, 4.2)), 2.4, _mats["fabric"])
	# Sofa B angled in across the back of the area, also facing the showroom.
	_sofa(Transform3D(Basis(Vector3.UP, -PI * 0.5 - 0.7), at(-4.2, 0.0, 2.75)), 1.8, _mats["fabric_warm"])
	_flat(at(-4.4, 0.022, 4.3), Vector3(3.2, 0.01, 2.6), _mats["rug"])
	_deco(at(-4.4, 0.38, 4.3), Vector3(1.2, 0.06, 0.7), _mats["oak"])
	for dx in [-0.5, 0.5]:
		for dz in [-0.28, 0.28]:
			_deco(at(-4.4 + dx, 0.18, 4.3 + dz), Vector3(0.04, 0.36, 0.04), _mats["anthracite"])
	_blocker(at(-4.4, 0.2, 4.3), Vector3(1.2, 0.4, 0.7))
	# Bike magazines and a coffee cup on the table.
	var mag := _deco(at(-4.6, 0.42, 4.25), Vector3(0.3, 0.012, 0.22), _mats["orange"])
	mag.rotation.y = 0.3
	_cyl(at(-4.1, 0.46, 4.4), 0.04, 0.09, _mats["white_gloss"])
	# Floor lamp in the corner.
	var lamp_at := at(-hx + 0.4, 0.0, hz_front() - 0.4)
	_cyl(lamp_at + Vector3(0.0, 0.02, 0.0), 0.18, 0.04, _mats["anthracite"])
	_cyl(lamp_at + Vector3(0.0, 0.8, 0.0), 0.015, 1.6, _mats["steel"])
	_cyl(lamp_at + Vector3(0.0, 1.6, 0.0), 0.12, 0.25, _mats["led"], 0.2)
	_plant(at(-hx + 0.45, 0.0, 2.3), 1.0)


static func hz_front() -> float:
	return HALF.y


## A modern sofa: seat, back, arms and short feet. `xf` is its front middle on the floor, -Z
## pointing the way you face sitting on it.
func _sofa(xf: Transform3D, width: float, mat: Material) -> void:
	var root := Node3D.new()
	root.transform = xf
	add_child(root)
	var depth := 0.9
	_deco(Vector3(0.0, 0.27, 0.0), Vector3(width, 0.24, depth), mat, root)
	_deco(Vector3(0.0, 0.43, 0.06), Vector3(width - 0.3, 0.1, depth - 0.2), mat, root)
	_deco(Vector3(0.0, 0.6, depth * 0.5 - 0.1), Vector3(width, 0.5, 0.2), mat, root)
	for side in [-1.0, 1.0]:
		_deco(Vector3(side * (width * 0.5 - 0.1), 0.45, 0.0), Vector3(0.2, 0.3, depth), mat, root)
		for fz in [-0.35, 0.35]:
			_deco(Vector3(side * (width * 0.5 - 0.12), 0.07, fz), Vector3(0.05, 0.14, 0.05), _mats["anthracite"], root)
	# Cushions.
	for k in int(width / 0.8):
		var cx := -width * 0.5 + 0.45 + k * 0.8
		var cushion := _deco(Vector3(cx, 0.62, depth * 0.5 - 0.25), Vector3(0.45, 0.4, 0.12), _mats["fabric_warm"] if mat == _mats["fabric"] else _mats["fabric"], root)
		cushion.rotation.x = 0.2
	var body := StaticBody3D.new()
	body.transform = xf
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.85, depth)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.425, 0.0)
	body.add_child(cs)
	add_child(body)


## The kitchen behind the reception: a run of white units with a dark stone worktop, sink and
## tap, kettle, toaster and microwave, wall cupboards over, a tall steel fridge, and a round table
## with chairs under a pendant lamp.
func _build_kitchen() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var x0 := -6.2
	var x1 := -1.6
	var len := x1 - x0
	var xm := (x0 + x1) * 0.5
	var zb := -hz + 0.3
	_solid(at(xm, 0.44, zb), Vector3(len, 0.88, 0.6), _mats["white_gloss"])
	_deco(at(xm, 0.9, zb + 0.01), Vector3(len + 0.02, 0.04, 0.64), _mats["stone_dark"])
	for k in int(len / 0.6):
		_deco(at(x0 + 0.3 + k * 0.6, 0.78, zb + 0.305), Vector3(0.3, 0.02, 0.015), _mats["steel"])
	_deco(at(xm, 0.05, zb + 0.28), Vector3(len, 0.1, 0.02), _mats["anthracite"])
	# Splashback, wall cupboards and an LED strip under them.
	_deco(at(xm, 1.2, -hz + 0.01), Vector3(len, 0.56, 0.02), _mats["quartz"])
	_deco(at(xm, 1.85, -hz + 0.18), Vector3(len, 0.7, 0.35), _mats["white_gloss"])
	_deco(at(xm, 1.49, -hz + 0.3), Vector3(len - 0.1, 0.015, 0.03), _mats["led"])
	# Sink and tap.
	var sink := at(-2.6, 0.0, zb)
	_deco(sink + Vector3(0.0, 0.905, 0.02), Vector3(0.5, 0.012, 0.38), _mats["steel"])
	_cyl(sink + Vector3(0.0, 1.06, -0.2), 0.015, 0.3, _mats["chrome"])
	_deco(sink + Vector3(0.0, 1.2, -0.1), Vector3(0.025, 0.025, 0.2), _mats["chrome"])
	# Kettle: a steel jug with a black handle on its base.
	var kettle := at(-4.0, 0.92, zb + 0.05)
	_cyl(kettle + Vector3(0.0, 0.01, 0.0), 0.09, 0.02, _mats["anthracite"])
	_cyl(kettle + Vector3(0.0, 0.13, 0.0), 0.085, 0.22, _mats["chrome"], 0.07)
	_deco(kettle + Vector3(-0.1, 0.14, 0.0), Vector3(0.03, 0.16, 0.03), _mats["leather"])
	_deco(kettle + Vector3(-0.08, 0.22, 0.0), Vector3(0.06, 0.03, 0.03), _mats["leather"])
	_deco(kettle + Vector3(0.09, 0.2, 0.0), Vector3(0.05, 0.03, 0.025), _mats["chrome"])
	# Mugs, a toaster and a microwave.
	for k in 3:
		_cyl(at(-3.55 + k * 0.13, 0.97, zb + 0.15), 0.04, 0.1, _mats["orange"] if k == 1 else _mats["white_gloss"])
	_deco(at(-4.7, 1.01, zb), Vector3(0.28, 0.18, 0.16), _mats["chrome"])
	_deco(at(-5.5, 1.07, zb - 0.02), Vector3(0.5, 0.3, 0.36), _mats["anthracite"])
	_deco(at(-5.42, 1.07, zb + 0.165), Vector3(0.3, 0.2, 0.01), _mats["screen"])
	# The fridge at the end of the run.
	var fridge := at(-hx + 0.38, 0.0, -hz + 0.38)
	_solid(fridge + Vector3(0.0, 0.92, 0.0), Vector3(0.7, 1.84, 0.7), _mats["steel"])
	_deco(fridge + Vector3(0.0, 1.25, 0.36), Vector3(0.66, 0.012, 0.01), _mats["anthracite"])
	_deco(fridge + Vector3(0.28, 0.9, 0.38), Vector3(0.03, 0.6, 0.03), _mats["chrome"])
	# The table, chairs and the lamp over them.
	var table := at(-4.3, 0.0, -3.3)
	_cyl(table + Vector3(0.0, 0.74, 0.0), 0.5, 0.04, _mats["oak"])
	_cyl(table + Vector3(0.0, 0.37, 0.0), 0.04, 0.72, _mats["anthracite"])
	_cyl(table + Vector3(0.0, 0.015, 0.0), 0.25, 0.03, _mats["anthracite"])
	_blocker(table + Vector3(0.0, 0.38, 0.0), Vector3(0.9, 0.76, 0.9))
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		_chair(Transform3D(Basis(Vector3.UP, a + PI), table + Vector3(sin(a), 0.0, cos(a)) * 0.75), _mats["orange"] if k == 0 else _mats["anthracite"])
	_cyl(table + Vector3(0.0, UNDER_Y - 0.5, 0.0), 0.006, 1.0, _mats["anthracite"])
	_cyl(table + Vector3(0.0, UNDER_Y - 1.05, 0.0), 0.2, 0.18, _mats["anthracite"], 0.05)
	_cyl(table + Vector3(0.0, UNDER_Y - 1.14, 0.0), 0.16, 0.01, _mats["led"])
	_label("KETTLE'S ON", at(-3.0, 1.75, -hz + 0.37), 0.0, 24, Color(0.25, 0.25, 0.25), 0.003)


## A simple chair, -Z the way you face sitting on it.
func _chair(xf: Transform3D, mat: Material) -> void:
	var root := Node3D.new()
	root.transform = xf
	add_child(root)
	_deco(Vector3(0.0, 0.45, 0.0), Vector3(0.42, 0.04, 0.42), mat, root)
	_deco(Vector3(0.0, 0.72, 0.2), Vector3(0.42, 0.42, 0.03), mat, root)
	for dx in [-0.18, 0.18]:
		for dz in [-0.18, 0.18]:
			_deco(Vector3(dx, 0.22, dz), Vector3(0.025, 0.45, 0.025), _mats["steel"], root)


## The office on the mezzanine: a desk turned to look out over the showroom with a computer and
## a chair, a pendant over it, bookshelves and filing cabinets along the west wall, a small round
## meeting table by the front glass, and plants.
func _build_office() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var y := MEZZ_Y
	var desk := at(-2.9, y, 1.0)
	_deco(desk + Vector3(0.0, 0.74, 0.0), Vector3(0.8, 0.04, 1.8), _mats["oak"])
	for dz in [-0.85, 0.85]:
		_deco(desk + Vector3(0.0, 0.36, dz), Vector3(0.7, 0.72, 0.04), _mats["white_gloss"])
	_deco(desk + Vector3(0.1, 0.45, 0.0), Vector3(0.3, 0.55, 0.4), _mats["white_gloss"])
	_blocker(desk + Vector3(0.0, 0.38, 0.0), Vector3(0.8, 0.76, 1.8))
	# The sales PC: a big widescreen monitor facing the chair (towards -x), keyboard and mouse.
	# What it shows (SalesView) and using it (F: the Sales page, SalesComputer).
	var mon := desk + Vector3(0.24, 1.17, 0.0)
	_deco(mon, Vector3(0.04, 0.66, 1.34), _mats["alu"])
	var face := _deco(mon + Vector3(-0.022, 0.0, 0.0), Vector3(0.004, 0.6, 1.28), _mats["monitor"])
	face.name = "OfficeScreen"
	var text := _label("TORQUE SHED SALES", mon + Vector3(-0.027, 0.0, 0.0), -PI * 0.5, 26, Color(0.85, 0.95, 1.0), 0.0016)
	text.name = "OfficeScreenText"
	text.width = 760.0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deco(desk + Vector3(0.24, 0.8, 0.0), Vector3(0.16, 0.08, 0.22), _mats["alu"])
	_deco(desk + Vector3(0.26, 0.9, 0.0), Vector3(0.04, 0.2, 0.06), _mats["alu"])
	var pc := StaticBody3D.new()
	pc.name = "SalesPC"
	pc.collision_layer = Workshop.INTERACT_LAYER
	pc.collision_mask = 0
	pc.set_meta("sales_pc", true)
	var pc_shape := BoxShape3D.new()
	pc_shape.size = Vector3(0.3, 1.0, 1.4)   # up to eye height, so a level look finds it
	var pc_cs := CollisionShape3D.new()
	pc_cs.shape = pc_shape
	pc.add_child(pc_cs)
	pc.position = mon + Vector3(0.0, 0.15, 0.0)
	add_child(pc)
	_deco(desk + Vector3(-0.15, 0.765, 0.0), Vector3(0.16, 0.015, 0.45), _mats["anthracite"])
	_deco(desk + Vector3(-0.15, 0.765, 0.35), Vector3(0.1, 0.02, 0.06), _mats["anthracite"])
	# A coffee mug and a stack of papers.
	_cyl(desk + Vector3(-0.1, 0.81, -0.6), 0.04, 0.1, _mats["orange"])
	_deco(desk + Vector3(0.05, 0.78, 0.6), Vector3(0.22, 0.03, 0.3), _mats["white_gloss"])
	# The office chair, facing the desk.
	var chair := desk + Vector3(-0.75, 0.0, 0.0)
	var root := Node3D.new()
	root.position = chair
	root.rotation.y = -PI * 0.5
	add_child(root)
	_deco(Vector3(0.0, 0.48, 0.0), Vector3(0.5, 0.08, 0.5), _mats["leather"], root)
	_deco(Vector3(0.0, 0.9, 0.24), Vector3(0.48, 0.7, 0.07), _mats["leather"], root)
	_cyl(Vector3(0.0, 0.25, 0.0), 0.03, 0.45, _mats["chrome"], -1.0, root)
	for k in 5:
		var a := TAU * k / 5.0
		var leg := _deco(Vector3(sin(a) * 0.17, 0.05, cos(a) * 0.17), Vector3(0.04, 0.03, 0.34), _mats["chrome"], root)
		leg.rotation.y = a
	_blocker(chair + Vector3(0.0, 0.55, 0.0), Vector3(0.55, 1.1, 0.55))
	# A pendant over the desk.
	_cyl(desk + Vector3(0.0, CEIL_Y - y - 0.6, 0.0), 0.006, 1.2, _mats["anthracite"])
	_cyl(desk + Vector3(0.0, CEIL_Y - y - 1.25, 0.0), 0.3, 0.1, _mats["anthracite"], 0.1)
	_cyl(desk + Vector3(0.0, CEIL_Y - y - 1.3, 0.0), 0.27, 0.01, _mats["led"])
	# Shelves of binders and filing cabinets along the west wall.
	_deco(at(-hx + 0.2, y + 1.1, -0.5), Vector3(0.4, 2.2, 2.4), _mats["oak"])
	for row in 4:
		var sy := y + 0.35 + row * 0.5
		for k in 7:
			var bc: Material = [_mats["orange"], _mats["anthracite"], _mats["white_gloss"]][(k + row) % 3]
			_deco(at(-hx + 0.25, sy, -1.4 + k * 0.3), Vector3(0.3, 0.32, 0.07), bc)
	_blocker(at(-hx + 0.2, y + 1.1, -0.5), Vector3(0.4, 2.2, 2.4))
	for k in 2:
		_solid(at(-hx + 0.3, y + 0.5, 1.4 + k * 0.55), Vector3(0.6, 1.0, 0.5), _mats["alu"])
	# The meeting table by the glass.
	var mt := at(-4.6, y, 4.3)
	_cyl(mt + Vector3(0.0, 0.74, 0.0), 0.6, 0.04, _mats["white_gloss"])
	_cyl(mt + Vector3(0.0, 0.37, 0.0), 0.05, 0.72, _mats["chrome"])
	_blocker(mt + Vector3(0.0, 0.38, 0.0), Vector3(1.1, 0.76, 1.1))
	for k in 3:
		var a := TAU * k / 3.0
		_chair(Transform3D(Basis(Vector3.UP, a + PI), mt + Vector3(sin(a), 0.0, cos(a)) * 0.9), _mats["anthracite"])
	_plant(at(-hx + 0.45, y, hz - 0.45), 1.3)
	_plant(at(-1.95, y, hz - 0.45), 0.9)
	# A sign on the wall at the top of the stairs.
	_label("OFFICE", at(-3.6, y + 2.1, -hz + 0.02), 0.0, 60, Color(0.15, 0.15, 0.16), 0.004)
	_switch(at(-2.2, y + 1.35, -hz + 0.02), 0.0)
	_switch(at(MEZZ_EDGE + 0.02, 1.35, -2.0), PI * 0.5)


## A light switch for the office lights on a wall (`rot_y` turns its face from +z).
func _switch(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_deco(Vector3(0.0, 0.0, 0.015), Vector3(0.1, 0.14, 0.03), _material(Color(0.92, 0.92, 0.9), 0.0, 0.5), root)
	var rocker := _deco(Vector3(0.0, 0.0, 0.035), Vector3(0.04, 0.07, 0.015), _material(Color(0.85, 0.85, 0.82), 0.0, 0.5), root)
	_rockers.append(rocker)
	var l := Label3D.new()
	l.text = "LIGHTS"
	l.font_size = 24
	l.pixel_size = 0.0018
	l.modulate = Color(0.2, 0.2, 0.2)
	l.position = Vector3(0.0, 0.12, 0.031)
	root.add_child(l)
	var body := StaticBody3D.new()
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.set_meta("light_switch", "sales")
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.2, 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0.0, 0.0, 0.03)
	root.add_child(body)


## The name over the glass, on the dark fascia.
func _build_signs() -> void:
	var hz := HALF.y
	var sign := _label("TORQUE SHED", at(-2.2, CEIL_Y + 0.5, hz + 0.41), 0.0, 150, Color(1.0, 0.85, 0.35), 0.006, 12)
	sign.name = "FasciaSign"
	_label("MOTORCYCLE SALES", at(4.0, CEIL_Y + 0.48, hz + 0.41), 0.0, 70, Color(0.95, 0.95, 0.95), 0.006)
	# Opening hours on the glass by the door.
	_label("SALES · SERVICE · RESTORATION\nOPEN 7 DAYS", at(-DOOR_HALF - 0.8, 1.55, hz + WALL * 0.5 + 0.03), 0.0, 22, Color(0.95, 0.95, 0.95), 0.003)


## The office's own lights (the "sales" switch): spots on each plinth and a fill over the
## showroom, warm light under the mezzanine and in the kitchen, the office upstairs, and an
## ambient probe so it's bright indoors and dark with them off.
func _build_lights() -> void:
	var hz := HALF.y
	for i in SHOWROOM_SPOTS.size():
		var o: Vector3 = SHOWROOM_SPOTS[i].origin
		# A track head on the ceiling, and its beam.
		_cyl(Vector3(o.x, CEIL_Y - 0.12, o.z + 0.8), 0.06, 0.18, _mats["alu"])
		var spot := SpotLight3D.new()
		spot.position = Vector3(o.x, CEIL_Y - 0.25, o.z + 0.8)
		spot.basis = Basis.looking_at(o + Vector3(0.0, 0.5, 0.0) - spot.position, Vector3.FORWARD)
		spot.spot_angle = 28.0
		spot.spot_range = 9.0
		spot.spot_attenuation = 0.6
		spot.light_energy = 5.0
		spot.light_color = Color(1.0, 0.96, 0.9)
		spot.shadow_enabled = i < 2
		add_child(spot)
		_lights.append(spot)
	var fills := [[at(3.0, 5.2, 1.0), 10.0, 1.1, true], [at(-4.3, 2.45, 3.5), 5.0, 0.9, false],
		[at(-4.3, 2.45, -3.4), 4.5, 0.8, false], [at(-4.2, 5.4, 0.0), 7.0, 1.0, true], [at(-2.5, 2.45, 0.4), 3.5, 0.6, false]]
	for f in fills:
		var omni := OmniLight3D.new()
		omni.position = f[0]
		omni.omni_range = f[1]
		omni.light_energy = f[2]
		omni.light_color = Color(1.0, 0.93, 0.84)
		omni.shadow_enabled = f[3]
		add_child(omni)
		_lights.append(omni)
	_probe = ReflectionProbe.new()
	_probe.position = at(0.0, CEIL_Y * 0.5, 0.0)
	_probe.size = Vector3(HALF.x * 2.0 + 0.2, CEIL_Y, hz * 2.0 + 0.2)
	_probe.interior = true
	_probe.box_projection = true
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color(0.62, 0.58, 0.54)
	_probe.ambient_color_energy = 0.5
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)


## The brass shop bell on a curled bracket inside the doors, and the chime box in the shed.
func _build_bell() -> void:
	var p := BELL_POS
	_deco(p + Vector3(0.0, 0.12, 0.05), Vector3(0.02, 0.02, 0.2), _mats["brass"])
	_deco(p + Vector3(0.0, 0.08, 0.15), Vector3(0.03, 0.12, 0.02), _mats["brass"])
	_bell = Node3D.new()
	_bell.name = "ShopBell"
	_bell.position = p + Vector3(0.0, 0.12, -0.05)
	add_child(_bell)
	_cyl(Vector3(0.0, -0.025, 0.0), 0.006, 0.05, _mats["brass"], -1.0, _bell)
	_cyl(Vector3(0.0, -0.09, 0.0), 0.065, 0.09, _mats["brass"], 0.03, _bell)
	_ball(Vector3(0.0, -0.14, 0.0), 0.014, _mats["brass"], _bell)
	# The chime box: a little white box with a brass bar, on the shed's front wall inside.
	var c := SHED_CHIME_POS
	_deco(c, Vector3(0.3, 0.2, 0.06), _mats["white_gloss"])
	_deco(c + Vector3(0.0, 0.1, -0.035), Vector3(0.24, 0.015, 0.015), _mats["brass"])
	_chime = Node3D.new()
	_chime.name = "ShedChime"
	_chime.position = c + Vector3(0.0, 0.0, -0.045)
	add_child(_chime)
	_cyl(Vector3(0.0, -0.05, 0.0), 0.025, 0.04, _mats["brass"], -1.0, _chime)
	var tag := _label("SALES OFFICE", c + Vector3(0.0, -0.16, -0.032), PI, 20, Color(0.15, 0.15, 0.15), 0.0025)
	tag.name = "ChimeLabel"


## The sliding doors: two frameless glass leaves on a track behind the door head, each with its
## own collision, sliding apart as people come up to them.
func _build_doors() -> void:
	for i in 2:
		var leaf := StaticBody3D.new()
		leaf.name = "DoorLeaf%d" % i
		var shape := BoxShape3D.new()
		shape.size = Vector3(DOOR_HALF, DOOR_HEIGHT, 0.04)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		leaf.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = shape.size
		mi.mesh = bm
		mi.material_override = _mats["glass"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.add_child(mi)
		# A slim steel edge and a pull bar.
		var edge := 1.0 if i == 0 else -1.0
		_deco(Vector3(edge * (DOOR_HALF * 0.5 - 0.02), 0.0, 0.0), Vector3(0.04, DOOR_HEIGHT, 0.05), _mats["steel"], leaf)
		_deco(Vector3(0.0, -DOOR_HEIGHT * 0.5 + 0.05, 0.0), Vector3(DOOR_HALF, 0.1, 0.05), _mats["steel"], leaf)
		_deco(Vector3(edge * (DOOR_HALF * 0.5 - 0.15), 0.0, 0.05), Vector3(0.03, 0.9, 0.03), _mats["chrome"], leaf)
		add_child(leaf)
		_leaves.append(leaf)
	_update_doors(0.0)
