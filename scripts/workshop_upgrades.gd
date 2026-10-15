class_name WorkshopUpgrades
extends Node3D
## Draws the garage upgrades the crew has bought (GarageUpgrades, Shed.upgrades) onto the
## Workshop: the extension wing behind the paint shop with bays 5 to 7, the storage annex
## behind the storage room with its mezzanine, the crew lounge, and the luxury finishes (floor,
## walls, lights, signs). Everything it builds sits in one node that is thrown away and built
## again whenever the upgrades change, so every player sees a purchase straight away.

const T := 0.2      # wall thickness of the new buildings
## The lit sign box over the roller door (width, height), and the clear margin its letters keep
## inside the neon frame.
const SIGN_BOX := Vector2(5.6, 1.15)
const SIGN_MARGIN := 0.25

var ws: Workshop
var _sig := "?"
var _root: Node3D
## What the shed looked like before any finish: material -> {property: value}, light -> [energy, colour].
var _base_mats := {}
var _base_lights := {}
var _bay4_y := 0.0
var _front_sign_base := []   # the TORQUE SHED letters' own [pixel size, position], put back on undo
var _wing_strips: Array[MeshInstance3D] = []   # the extension's strip light fittings
var _added_lights: Array[Light3D] = []
var _added_mats: Array[StandardMaterial3D] = []
var _room_added: Array = []        # [list, thing] pairs added to the workshop's storage room lists
var _probes: Array = []             # [probe, room ("" = the shed's switch), energy]
var _arcade_text: Label3D
var _mats := {}


func setup(workshop: Workshop) -> void:
	ws = workshop
	name = "Upgrades"
	for key in ["floor", "wall_in", "wall_low"]:
		var m: StandardMaterial3D = ws._mats[key]
		_base_mats[m] = _mat_state(m)
	for m in ws._fixture_mats:
		_base_mats[m] = _mat_state(m)
	for l in ws._shed_lights:
		_base_lights[l] = [l.light_energy, l.light_color]
	if ws._bay_screens.size() > 3:
		_bay4_y = ws._bay_screens[3].position.y
	if ws.front_sign:
		_front_sign_base = [ws.front_sign.pixel_size, ws.front_sign.position]
	_make_materials()
	sync()


static func _mat_state(m: StandardMaterial3D) -> Dictionary:
	return {"albedo_color": m.albedo_color, "albedo_texture": m.albedo_texture, "roughness": m.roughness,
		"metallic": m.metallic, "uv1_scale": m.uv1_scale, "emission": m.emission, "uv1_triplanar": m.uv1_triplanar,
		"texture_filter": m.texture_filter}


## Rebuilds if the upgrades have changed since the last time.
func sync() -> void:
	var ids: Array = Shed.upgrades.keys()
	ids.sort()
	var sig := ",".join(ids)
	if sig == _sig:
		return
	_sig = sig
	_rebuild(Shed.upgrades)


## The upgrades built right now, by id (for tests).
func built() -> String:
	return _sig


func _process(_delta: float) -> void:
	for p in _probes:
		var probe: ReflectionProbe = p[0]
		var on := Shed.room_lit(str(p[1]))
		probe.ambient_color_energy = float(p[2]) if on else 0.0
		probe.intensity = 1.0 if on else 0.15
	if _arcade_text:
		_arcade_text.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.8


# ---------------------------------------------------------------------------- rebuilding

func _undo() -> void:
	_probes.clear()
	_arcade_text = null
	ws._bay_screens.resize(mini(ws._bay_screens.size(), Workshop.BAY_COUNT))
	for key in ws._screen_shown.keys():
		if str(key).begins_with("bay") and int(str(key).substr(3)) >= Workshop.BAY_COUNT:
			ws._screen_shown.erase(key)
	for l in _added_lights:
		ws._shed_lights.erase(l)
	_added_lights.clear()
	for m in _added_mats:
		ws._fixture_mats.erase(m)
	_added_mats.clear()
	for pair in _room_added:
		(pair[0] as Array).erase(pair[1])
	_room_added.clear()
	# Only now the lists no longer hold them: everything built goes.
	if _root:
		_root.free()
		_root = null
	for room in ws.knock:
		for n in ws.knock[room]:
			_knock_out(n, false)
	for m in _base_mats:
		for prop in _base_mats[m]:
			(m as StandardMaterial3D).set(prop, _base_mats[m][prop])
	for l in _base_lights:
		(l as Light3D).light_energy = _base_lights[l][0]
		(l as Light3D).light_color = _base_lights[l][1]
	if ws._bay_screens.size() > 3:
		ws._bay_screens[3].position.y = _bay4_y
	if ws.front_sign and not _front_sign_base.is_empty():
		ws.front_sign.pixel_size = float(_front_sign_base[0])
		ws.front_sign.position = _front_sign_base[1]
	for strip in ws.ceiling_strips:
		strip.visible = true
	_wing_strips.clear()


func _rebuild(have: Dictionary) -> void:
	_undo()
	_root = Node3D.new()
	_root.name = "Built"
	add_child(_root)
	if have.has("wing"):
		_build_wing()
		var bays := GarageUpgrades.extra_bays(have)
		for i in bays:
			_build_wing_bay(Workshop.BAY_COUNT + i)
		if have.has("lounge"):
			_build_lounge()
	if have.has("annex"):
		_build_annex()
		if have.has("mezzanine"):
			_build_mezzanine()
	if have.has("epoxy"):
		_epoxy_floor()
	if have.has("cladding"):
		_wall_cladding(have.has("wing"))
	if have.has("led"):
		_led_lighting(have.has("wing"))
	if have.has("signage"):
		_signage()
	if have.has("showroom"):
		_showroom(have.has("wing"))
	ws.set_lights(Shed.lights_on)
	ws.set_room_lights("storage", Shed.room_lit("storage"))
	ws._dash_dirty = true
	var world := ws.get_parent()
	var weather = world.get("weather") if world else null
	if weather is Weather:
		(weather as Weather).refresh_shelters()


## Takes a stretch of the shed's own wall out (or puts it back) for a doorway knocked through it.
func _knock_out(n: Node3D, out: bool) -> void:
	n.visible = not out
	if n is CollisionObject3D:
		var body := n as CollisionObject3D
		if not body.has_meta("layer"):
			body.set_meta("layer", body.collision_layer)
		body.collision_layer = 0 if out else int(body.get_meta("layer"))


# ---------------------------------------------------------------------------- helpers

func _make_materials() -> void:
	_mats["grate"] = ws._material(Color(0.32, 0.34, 0.36), 0.8, 0.4, ws._noise(2.5, 0.75, 1.1), 10.0)
	_mats["plate"] = ws._material(Color(0.55, 0.57, 0.6), 0.9, 0.3, ws._noise(3.0, 0.8, 1.1), 12.0)
	_mats["leather"] = ws._material(Color(0.32, 0.09, 0.06), 0.0, 0.45, ws._noise(1.0, 0.85, 1.05), 2.0)
	_mats["rug"] = ws._material(Color(0.55, 0.12, 0.1), 0.0, 0.95, ws._noise(0.8, 0.8, 1.1), 3.0)
	_mats["white"] = ws._material(Color(0.92, 0.93, 0.94), 0.1, 0.25)
	_mats["glass"] = ws._material(Color(0.6, 0.8, 0.9, 0.35), 0.2, 0.05)
	(_mats["glass"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["cabinet"] = ws._material(Color(0.08, 0.06, 0.18), 0.2, 0.4)
	_mats["hazard"] = ws._material(Color(0.95, 0.75, 0.05), 0.0, 0.5)
	# The new buildings' slabs: plain concrete, whatever finish goes on the floor inside.
	_mats["slab"] = ws._material(Color(0.5, 0.5, 0.49), 0.0, 0.9, ws._noise(0.3, 0.85, 1.05), 4.0)


func _glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := ws._material(color, 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	return ws._deco(_root, center, size, mat)


func _wall(center: Vector3, size: Vector3, mat: Material = null) -> StaticBody3D:
	return ws._solid(center, size, mat if mat else ws._mats["cladding"], _root)


func _text(text: String, pos: Vector3, rot_y: float, size := 32, color := Color(1, 1, 1), outline := 6) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = outline
	_root.add_child(l)
	return l


## A light the shed's own switch works, added to the workshop's list.
func _shed_light(l: Light3D) -> Light3D:
	_root.add_child(l)
	ws._shed_lights.append(l)
	_added_lights.append(l)
	return l


func _shed_fixture() -> StandardMaterial3D:
	var m := _glow(Color(1.0, 0.95, 0.85), 4.0)
	m.albedo_color = Color(1.0, 0.97, 0.9)
	ws._fixture_mats.append(m)
	_added_mats.append(m)
	return m


func _probe(rect: Rect2, h: float, room: String, color: Color, energy: float) -> void:
	var probe := ReflectionProbe.new()
	probe.position = Vector3(rect.get_center().x, h * 0.5, rect.get_center().y)
	probe.size = Vector3(rect.size.x + 0.1, h, rect.size.y + 0.1)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = color
	probe.ambient_color_energy = energy
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_root.add_child(probe)
	_probes.append([probe, room, energy])


## Painted plaster over a dark band on the inside of a wall running along x (`along_x`) or z,
## from `a` to `b`, the face at `at` (z for an x wall, x for a z wall), `h` high.
func _faces(along_x: bool, a: float, b: float, at: float, h: float) -> void:
	var mid := (a + b) * 0.5
	var len := absf(b - a)
	var c := Vector3(mid, 0.0, at) if along_x else Vector3(at, 0.0, mid)
	var size := Vector3(len, 0.0, 0.02) if along_x else Vector3(0.02, 0.0, len)
	_box(c + Vector3(0.0, h * 0.5 + 0.6, 0.0), size + Vector3(0.0, h - 1.2, 0.0), ws._mats["wall_in"])
	_box(c + Vector3(0.0, 0.6, 0.0), size + Vector3(0.0, 1.2, 0.0), ws._mats["wall_low"])


## A hazard-yellow frame round a doorway in a wall running along x, the wall's middle at `z`.
func _door_frame(x: float, half: float, h: float, z: float, depth: float) -> void:
	for end in [-1.0, 1.0]:
		_box(Vector3(x + end * (half + 0.05), h * 0.5, z), Vector3(0.1, h, depth + 0.06), _mats["hazard"])
	_box(Vector3(x, h + 0.05, z), Vector3(half * 2.0 + 0.2, 0.1, depth + 0.06), _mats["hazard"])


# ---------------------------------------------------------------------------- the extension

## The wing behind the paint shop: a slab, walls, roof and lights, and the doorway knocked
## through the shed's back wall behind bay 4.
func _build_wing() -> void:
	var r := GarageUpgrades.WING
	var h := GarageUpgrades.WING_HEIGHT
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var mid := r.get_center()
	var slab := _wall(Vector3(mid.x, -0.25, mid.y), Vector3(r.size.x + T * 2.0, 0.5, r.size.y + T * 2.0), _mats["slab"])
	slab.name = "WingFloor"
	var floor_mi := _box(Vector3(mid.x, 0.004, mid.y), Vector3(r.size.x, 0.008, r.size.y), ws._mats["floor"])
	floor_mi.name = "WingFloorFinish"
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Back, east and west walls; the front is the shed's back wall then a new stretch past it.
	var shed_back := Workshop.CENTER.z - Workshop.HALF.y      # 59.5, the shed's inside face
	var shed_east := Workshop.CENTER.x + Workshop.HALF.x + 0.3
	_wall(Vector3(mid.x, h * 0.5, z0 - T * 0.5), Vector3(r.size.x + T * 2.0, h, T)).name = "WingBackWall"
	_wall(Vector3(x1 + T * 0.5, h * 0.5, mid.y), Vector3(T, h, r.size.y + T * 2.0))
	_wall(Vector3(x0 - T * 0.5, h * 0.5, mid.y), Vector3(T, h, r.size.y))
	_wall(Vector3((shed_east + x1 + T) * 0.5, h * 0.5, z1 + T * 0.5), Vector3(x1 + T - shed_east, h, T))
	_wall(Vector3(mid.x, h + 0.08, mid.y - 0.05), Vector3(r.size.x + T * 2.0 + 0.2, 0.12, r.size.y + T * 2.0 - 0.1), ws._mats["roof"]).name = "WingRoof"
	_faces(true, x0, x1, z0 + 0.01, h)
	_faces(false, z0, z1, x1 - 0.01, h)
	_faces(false, z0, z1, x0 + 0.01, h)
	var dx := GarageUpgrades.WING_DOOR_X
	var dh := GarageUpgrades.WING_DOOR_HALF
	var door_h := GarageUpgrades.WING_DOOR_HEIGHT
	for seg in Workshop._wall_runs(x0, x1, dx, dh):
		_faces(true, float(seg[0]) - float(seg[1]) * 0.5, float(seg[0]) + float(seg[1]) * 0.5, z1 - 0.01, h)
	_box(Vector3(dx, (h + door_h) * 0.5, z1 - 0.01), Vector3(dh * 2.0, h - door_h, 0.02), ws._mats["wall_in"])
	# The doorway through the shed's back wall: its east stretch comes out and goes back in two
	# pieces with a lintel over the gap.
	for n in ws.knock["wing"]:
		_knock_out(n, true)
	var wall_z := shed_back - 0.15
	var from := DynoRoom.DOOR_HALF
	var hh := Workshop.HEIGHT
	_wall(Vector3((from + dx - dh) * 0.5, hh * 0.5, wall_z), Vector3(dx - dh - from, hh, 0.3)).name = "ShedBackWallWest"
	_wall(Vector3((dx + dh + shed_east) * 0.5, hh * 0.5, wall_z), Vector3(shed_east - dx - dh, hh, 0.3)).name = "ShedBackWallEast"
	_wall(Vector3(dx, (hh + door_h) * 0.5, wall_z), Vector3(dh * 2.0, hh - door_h, 0.3)).name = "WingLintel"
	var inner_end := Workshop.CENTER.x + Workshop.HALF.x
	_faces(true, from, dx - dh, shed_back + 0.01, hh)
	_faces(true, dx + dh, inner_end, shed_back + 0.01, hh)
	_box(Vector3(dx, (hh + door_h) * 0.5, shed_back + 0.01), Vector3(dh * 2.0, hh - door_h, 0.02), ws._mats["wall_in"])
	_door_frame(dx, dh, door_h, wall_z, 0.3)
	_text("WORKSHOP", Vector3(dx, door_h + 0.3, z1 - 0.03), PI, 40, Color(0.08, 0.08, 0.08), 0)
	# Bay 4's screen goes up over the new doorway.
	if ws._bay_screens.size() > 3:
		ws._bay_screens[3].position.y = door_h + 0.2 + Workshop.BAY_SCREEN_OUTER * Dashboard.PX.y / Dashboard.PX.x * 0.5
	# Strip lights down the walkway, on the shed's switch.
	var fixture := _shed_fixture()
	for x in [7.2, 10.4]:
		_wing_strips.append(_box(Vector3(x, h - 0.06, 57.0), Vector3(1.3, 0.05, 0.2), fixture))
		var omni := OmniLight3D.new()
		omni.position = Vector3(x, h - 0.4, 57.0)
		omni.omni_range = 6.5
		omni.light_energy = 1.1
		omni.light_color = Color(1.0, 0.93, 0.82)
		omni.shadow_enabled = x < 8.0
		_shed_light(omni)
	_probe(r, h, "", Color(0.55, 0.5, 0.45), 0.45)


## One of the extension's bays: painted box and number, a flush lift plate, a bay light and
## its own screen on the back wall.
func _build_wing_bay(bay: int) -> void:
	var xf := Workshop.bay_transform(bay)
	var o := xf.origin
	for side in [-1.0, 1.0]:
		_box(o + Vector3(side * 1.5, 0.01, 0.4), Vector3(0.06, 0.004, 3.1), ws._mats["yellow"])
	var num := _text("BAY %d" % (bay + 1), o + Vector3(0.0, 0.012, 1.75), 0.0, 72, Color(0.95, 0.8, 0.2))
	num.rotation.x = -PI * 0.5
	# The lift: a chequer plate set flush in the floor with hazard edges and a control post.
	_box(o + Vector3(0.0, 0.012, 0.0), Vector3(0.9, 0.012, 2.5), _mats["plate"])
	for side in [-1.0, 1.0]:
		_box(o + Vector3(side * 0.47, 0.014, 0.0), Vector3(0.05, 0.012, 2.55), _mats["hazard"])
	var post := o + Vector3(1.25, 0.0, -1.6)
	ws._solid(post + Vector3(0.0, 0.55, 0.0), Vector3(0.18, 1.1, 0.14), _mats["hazard"], _root)
	_box(post + Vector3(0.0, 1.0, 0.075), Vector3(0.06, 0.06, 0.02), ws._mats["red"])
	_box(post + Vector3(0.0, 0.88, 0.075), Vector3(0.06, 0.06, 0.02), ws._material(Color(0.1, 0.6, 0.15), 0.0, 0.4))
	var screen := Dashboard.new("bike", Workshop.BAY_SCREEN_INNER)
	screen.name = "BayScreen%d" % bay
	screen.position = Vector3(o.x, 2.45, GarageUpgrades.WING.position.y + 0.1)
	_root.add_child(screen)
	ws._bay_screens.append(screen)   # bays are built in order, so its index is its bay
	ws._screen_target(screen, "bay%d" % bay)
	var fixture := _shed_fixture()
	var h := GarageUpgrades.WING_HEIGHT
	_wing_strips.append(_box(Vector3(o.x, h - 0.08, o.z), Vector3(0.2, 0.05, 1.3), fixture))
	var spot := SpotLight3D.new()
	spot.position = Vector3(o.x, h - 0.2, o.z + 0.4)
	spot.rotation.x = -PI * 0.5
	spot.spot_angle = 55.0
	spot.spot_range = 5.5
	spot.light_energy = 2.4
	spot.light_color = Color(1.0, 0.95, 0.88)
	spot.shadow_enabled = true
	_shed_light(spot)


## The crew lounge at the east end of the extension: rug, leather sofa, coffee table, drinks
## fridge, arcade machine, a floor lamp and a neon sign.
func _build_lounge() -> void:
	var r := GarageUpgrades.LOUNGE
	var east := GarageUpgrades.WING.end.x
	var front := GarageUpgrades.WING.end.y
	_box(Vector3(r.get_center().x + 0.1, 0.012, r.get_center().y), Vector3(2.8, 0.01, 3.0), _mats["rug"]).name = "LoungeRug"
	# The sofa against the east wall, facing into the room.
	var sx := east - 0.5
	var sz := r.get_center().y - 0.1
	var sofa := ws._solid(Vector3(sx, 0.22, sz), Vector3(0.85, 0.44, 2.1), _mats["leather"], _root)
	sofa.name = "LoungeSofa"
	_box(Vector3(sx, 0.5, sz), Vector3(0.8, 0.14, 1.95), _mats["leather"])
	_box(Vector3(east - 0.12, 0.72, sz), Vector3(0.22, 0.6, 2.1), _mats["leather"])
	for end in [-1.0, 1.0]:
		_box(Vector3(sx, 0.6, sz + end * 1.0), Vector3(0.85, 0.3, 0.2), _mats["leather"])
	# Coffee table: glass on chrome legs, with a couple of cans on it.
	var tx := sx - 1.15
	_box(Vector3(tx, 0.42, sz), Vector3(0.6, 0.03, 1.0), _mats["glass"])
	for i in 4:
		_box(Vector3(tx + (0.25 if i % 2 == 0 else -0.25), 0.21, sz + (0.42 if i < 2 else -0.42)), Vector3(0.04, 0.42, 0.04), ws._mats["chrome"])
	ws._blocker(Vector3(tx, 0.22, sz), Vector3(0.6, 0.44, 1.0), _root)
	for i in 2:
		var can := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.033
		cyl.bottom_radius = 0.033
		cyl.height = 0.12
		can.mesh = cyl
		can.material_override = ws._mats["red"] if i == 0 else ws._mats["blue"]
		can.position = Vector3(tx + 0.1 - i * 0.18, 0.5, sz + 0.2 - i * 0.12)
		_root.add_child(can)
	# The drinks fridge against the front wall: glass door, lit inside, rows of bottles.
	var fz := front - 0.4
	var fx := r.position.x + 0.45
	ws._solid(Vector3(fx, 0.93, fz), Vector3(0.7, 1.86, 0.66), _mats["white"], _root).name = "LoungeFridge"
	_box(Vector3(fx, 0.95, fz - 0.335), Vector3(0.58, 1.6, 0.012), _glow(Color(0.75, 0.9, 1.0), 1.2))
	_box(Vector3(fx, 0.95, fz - 0.345), Vector3(0.6, 1.62, 0.01), _mats["glass"])
	for shelf in 4:
		for b in 5:
			var bottle := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.018
			cyl.bottom_radius = 0.03
			cyl.height = 0.24
			bottle.mesh = cyl
			bottle.material_override = [ws._mats["red"], ws._mats["blue"], _mats["hazard"], ws._mats["chrome"]][(shelf + b) % 4]
			bottle.position = Vector3(fx - 0.22 + b * 0.11, 0.38 + shelf * 0.38, fz - 0.36)
			_root.add_child(bottle)
	_text("COLD ONES", Vector3(fx, 1.78, fz - 0.352), PI, 26, Color(0.2, 0.5, 0.9), 0)
	# The arcade machine beside it.
	var ax := fx + 1.0
	ws._solid(Vector3(ax, 0.9, fz), Vector3(0.72, 1.8, 0.7), _mats["cabinet"], _root).name = "LoungeArcade"
	var screen := _box(Vector3(ax, 1.32, fz - 0.33), Vector3(0.56, 0.44, 0.04), _glow(Color(0.2, 0.9, 0.6), 2.5))
	screen.rotation.x = -0.2
	_box(Vector3(ax, 0.98, fz - 0.42), Vector3(0.66, 0.06, 0.24), ws._mats["dark"])
	for i in 4:
		var btn := _box(Vector3(ax - 0.18 + i * 0.12, 1.02, fz - 0.45), Vector3(0.05, 0.03, 0.05), _glow([Color(1, 0.2, 0.2), Color(0.2, 0.5, 1), Color(1, 0.85, 0.1), Color(0.2, 1, 0.3)][i], 2.0))
		btn.name = "ArcadeButton%d" % i
	_box(Vector3(ax, 1.7, fz - 0.34), Vector3(0.7, 0.16, 0.02), _glow(Color(1.0, 0.3, 0.8), 3.0))
	var marquee := _text("TORQUE RACER", Vector3(ax, 1.7, fz - 0.36), PI, 30, Color(1, 1, 1), 4)
	marquee.pixel_size = 0.0028
	_arcade_text = _text("INSERT COIN", Vector3(ax, 1.3, fz - 0.37), PI, 24, Color(1.0, 0.95, 0.4), 4)
	_arcade_text.pixel_size = 0.0025
	# A floor lamp in the corner and a neon sign over the sofa.
	var lamp := Vector3(east - 0.35, 0.0, r.position.y + 0.35)
	_box(lamp + Vector3(0.0, 0.8, 0.0), Vector3(0.04, 1.6, 0.04), ws._mats["chrome"])
	_box(lamp + Vector3(0.0, 1.62, 0.0), Vector3(0.36, 0.26, 0.36), _glow(Color(1.0, 0.8, 0.55), 1.5))
	var warm := OmniLight3D.new()
	warm.position = lamp + Vector3(0.0, 1.5, 0.0)
	warm.omni_range = 3.5
	warm.light_energy = 0.8
	warm.light_color = Color(1.0, 0.78, 0.5)
	_shed_light(warm)
	var neon := _text("CREW LOUNGE", Vector3(east - 0.03, 2.25, sz), -PI * 0.5, 64, Color(3.0, 0.5, 2.2), 10)
	neon.name = "LoungeNeon"
	neon.shaded = false
	neon.outline_modulate = Color(0.8, 0.1, 0.6)
	var pink := OmniLight3D.new()
	pink.position = Vector3(east - 0.4, 2.2, sz)
	pink.omni_range = 2.5
	pink.light_energy = 0.6
	pink.light_color = Color(1.0, 0.35, 0.8)
	_shed_light(pink)


# ---------------------------------------------------------------------------- storage

## The storage annex behind the storage room: a tall shed of its own with a wide doorway
## through the storage room's back wall, lit from the storage room's switch.
func _build_annex() -> void:
	var r := GarageUpgrades.ANNEX
	var h := GarageUpgrades.ANNEX_HEIGHT
	var mid := r.get_center()
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var slab := _wall(Vector3(mid.x, -0.25, (z0 - T + z1) * 0.5), Vector3(r.size.x + T * 2.0, 0.5, r.size.y + T), _mats["slab"])
	slab.name = "AnnexFloor"
	var floor_mat := ws._material(Color(0.4, 0.41, 0.42), 0.0, 0.6, ws._noise(0.3, 0.85, 1.05), 4.0)
	_box(Vector3(mid.x, 0.004, mid.y), Vector3(r.size.x, 0.008, r.size.y), floor_mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall(Vector3(mid.x, h * 0.5, z0 - T * 0.5), Vector3(r.size.x + T * 2.0, h, T)).name = "AnnexBackWall"
	for side in [-1.0, 1.0]:
		_wall(Vector3(mid.x + side * (r.size.x * 0.5 + T * 0.5), h * 0.5, mid.y), Vector3(T, h, r.size.y))
	# The storage room's back wall is the annex's front, up to the storage room roof; above that
	# the taller annex has its own gable.
	var room_h := Workshop.ROOM_HEIGHT
	_wall(Vector3(mid.x, (room_h + h) * 0.5, z1 - T * 0.5), Vector3(r.size.x + T * 2.0, h - room_h, T))
	_wall(Vector3(mid.x, h + 0.08, mid.y - 0.05), Vector3(r.size.x + T * 2.0 + 0.2, 0.12, r.size.y + T + 0.1), ws._mats["roof"]).name = "AnnexRoof"
	_faces(true, x0, x1, z0 + 0.01, h)
	_faces(false, z0, z1, x0 + 0.01, h)
	_faces(false, z0, z1, x1 - 0.01, h)
	var dx := GarageUpgrades.ANNEX_DOOR_X
	var dh := GarageUpgrades.ANNEX_DOOR_HALF
	var door_h := GarageUpgrades.ANNEX_DOOR_HEIGHT
	for seg in Workshop._wall_runs(x0, x1, dx, dh):
		_faces(true, float(seg[0]) - float(seg[1]) * 0.5, float(seg[0]) + float(seg[1]) * 0.5, z1 - 0.01, h)
	_box(Vector3(dx, (h + door_h) * 0.5, z1 - 0.01), Vector3(dh * 2.0, h - door_h, 0.02), ws._mats["wall_in"])
	# The doorway through the storage room's back wall.
	for n in ws.knock["annex"]:
		_knock_out(n, true)
	var wall_z := z1 + 0.1
	var sx0 := x0 - T
	var sx1 := x1 + T
	_wall(Vector3((sx0 + dx - dh) * 0.5, room_h * 0.5, wall_z), Vector3(dx - dh - sx0, room_h, 0.2)).name = "StoreBackWallWest"
	_wall(Vector3((dx + dh + sx1) * 0.5, room_h * 0.5, wall_z), Vector3(sx1 - dx - dh, room_h, 0.2)).name = "StoreBackWallEast"
	_wall(Vector3(dx, (room_h + door_h) * 0.5, wall_z), Vector3(dh * 2.0, room_h - door_h, 0.2))
	_faces(true, x0, dx - dh, z1 + 0.21, room_h)
	_faces(true, dx + dh, x1, z1 + 0.21, room_h)
	_box(Vector3(dx, (room_h + door_h) * 0.5, z1 + 0.21), Vector3(dh * 2.0, room_h - door_h, 0.02), ws._mats["wall_in"])
	_door_frame(dx, dh, door_h, wall_z, 0.2)
	_text("ANNEX", Vector3(dx, door_h + 0.32, z1 + 0.23), 0.0, 44, Color(0.08, 0.08, 0.08), 0).name = "AnnexSign"
	# High bay lights on the storage room's switch.
	var fixture := _glow(Color(1.0, 0.95, 0.85), 4.0)
	ws._room_mats["storage"].append(fixture)
	_room_added.append([ws._room_mats["storage"], fixture])
	for x in [mid.x - 2.0, mid.x + 2.0]:
		_box(Vector3(x, h - 0.08, mid.y + 1.2), Vector3(0.5, 0.08, 0.5), fixture)
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, h - 0.2, mid.y + 1.2)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 75.0
		spot.spot_range = 7.0
		spot.light_energy = 1.8
		spot.light_color = Color(1.0, 0.95, 0.88)
		spot.shadow_enabled = true
		_storage_light(spot)
	_probe(r, h, "storage", Color(0.55, 0.5, 0.45), 0.4)


func _storage_light(l: Light3D) -> void:
	_root.add_child(l)
	ws._room_lights["storage"].append(l)
	_room_added.append([ws._room_lights["storage"], l])


## The mezzanine across the back of the annex: a steel deck on posts, stairs up the east side,
## a railing, and the deck stacked with boxed stock and pallets.
func _build_mezzanine() -> void:
	var r := GarageUpgrades.ANNEX
	var top := GarageUpgrades.MEZZ_TOP
	var depth := GarageUpgrades.MEZZ_DEPTH
	var z0 := r.position.y
	var edge := z0 + depth
	var deck := _wall(Vector3(r.get_center().x, top - 0.06, z0 + depth * 0.5), Vector3(r.size.x, 0.12, depth), _mats["grate"])
	deck.name = "MezzanineDeck"
	deck.set_meta("surface", "metal")
	_box(Vector3(r.get_center().x, top - 0.14, edge - 0.05), Vector3(r.size.x, 0.22, 0.1), _mats["hazard"])
	# Posts along the front edge, clear of the top of the stairs.
	for i in 3:
		var x := r.position.x + 0.15 + i * (GarageUpgrades.STAIR_X.x - r.position.x - 0.3) * 0.5
		_wall(Vector3(x, (top - 0.12) * 0.5, edge - 0.12), Vector3(0.14, top - 0.12, 0.14), _mats["hazard"])
	# The stairs: steps to see and a smooth ramp under them to walk up.
	var sx := GarageUpgrades.STAIR_X
	var sz := GarageUpgrades.STAIR_Z
	var run := sz.x - sz.y
	var steps := 12
	for i in steps:
		var y := top * (i + 1) / steps
		var z := sz.x - run * (i + 0.5) / steps
		_box(Vector3((sx.x + sx.y) * 0.5, y - 0.03, z), Vector3(sx.y - sx.x, 0.06, run / steps + 0.02), _mats["grate"])
		_box(Vector3((sx.x + sx.y) * 0.5, y - 0.1, z + run / steps * 0.5), Vector3(sx.y - sx.x, 0.14, 0.02), _mats["hazard"])
	var angle := atan2(top, run)
	var ramp := StaticBody3D.new()
	ramp.name = "MezzanineStairs"
	ramp.set_meta("surface", "metal")
	var shape := BoxShape3D.new()
	shape.size = Vector3(sx.y - sx.x, 0.1, sqrt(run * run + top * top))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ramp.add_child(cs)
	ramp.rotation.x = angle
	var normal := Vector3(0.0, cos(angle), sin(angle))
	ramp.position = Vector3((sx.x + sx.y) * 0.5, top * 0.5, (sz.x + sz.y) * 0.5) - normal * 0.05
	_root.add_child(ramp)
	# Handrail down the open side of the stairs, and along the deck's edge to the stairs.
	var rail_from := Vector3(sx.x, 1.0, sz.x)
	var rail_to := Vector3(sx.x, top + 1.0, sz.y)
	var rail := _box((rail_from + rail_to) * 0.5, Vector3(0.05, 0.05, rail_from.distance_to(rail_to)), _mats["hazard"])
	rail.rotation.x = angle
	var deck_rail := sx.x - r.position.x
	_box(Vector3(r.position.x + deck_rail * 0.5, top + 1.0, edge - 0.03), Vector3(deck_rail, 0.05, 0.05), _mats["hazard"])
	_box(Vector3(r.position.x + deck_rail * 0.5, top + 0.5, edge - 0.03), Vector3(deck_rail, 0.04, 0.03), _mats["hazard"])
	for i in 7:
		_box(Vector3(r.position.x + 0.1 + i * (deck_rail - 0.2) / 6.0, top + 0.5, edge - 0.03), Vector3(0.05, 1.0, 0.05), _mats["hazard"])
	ws._blocker(Vector3(r.position.x + deck_rail * 0.5, top + 0.55, edge - 0.03), Vector3(deck_rail, 1.1, 0.06), _root)
	# Stock on the deck: pallets of boxes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5:
		var px := r.position.x + 0.8 + i * 1.35
		_box(Vector3(px, top + 0.07, z0 + 0.8), Vector3(1.1, 0.14, 1.1), ws._mats["wood"])
		var stack := rng.randi_range(1, 3)
		for j in stack:
			var size := Vector3(rng.randf_range(0.45, 0.6), rng.randf_range(0.3, 0.5), rng.randf_range(0.45, 0.6))
			var at := Vector3(px + rng.randf_range(-0.2, 0.2), top + 0.14 + size.y * 0.5 + j * 0.5, z0 + 0.8 + rng.randf_range(-0.2, 0.2))
			_box(at, size, ws._mats["box"])
		ws._blocker(Vector3(px, top + 0.75, z0 + 0.8), Vector3(1.1, 1.3, 1.1), _root)
	_text("MEZZANINE  ·  STOCK", Vector3(r.get_center().x - 1.0, top - 0.14, edge + 0.01), 0.0, 36, Color(0.08, 0.08, 0.08), 0)
	# A light under the deck so the racking underneath isn't in the dark.
	var under := OmniLight3D.new()
	under.position = Vector3(r.get_center().x, top - 0.4, z0 + depth * 0.5)
	under.omni_range = 5.0
	under.light_energy = 0.9
	under.light_color = Color(1.0, 0.95, 0.88)
	_storage_light(under)


# ---------------------------------------------------------------------------- finishes

func _epoxy_floor() -> void:
	var m: StandardMaterial3D = ws._mats["floor"]
	m.albedo_color = Color(0.2, 0.22, 0.25)
	m.albedo_texture = ws._noise(4.0, 0.7, 1.35)   # a fine speckled flake
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.5, 1.5, 1.5)
	m.roughness = 0.12
	m.metallic = 0.15


func _wall_cladding(wing: bool) -> void:
	var upper: StandardMaterial3D = ws._mats["wall_in"]
	upper.albedo_color = Color(0.94, 0.94, 0.95)
	upper.albedo_texture = null
	upper.roughness = 0.3
	var lower: StandardMaterial3D = ws._mats["wall_low"]
	lower.albedo_color = Color(0.72, 0.74, 0.77)
	lower.albedo_texture = ws._noise(6.0, 0.75, 1.15)
	lower.uv1_triplanar = true
	lower.uv1_scale = Vector3(3.0, 3.0, 3.0)
	lower.metallic = 0.9
	lower.roughness = 0.32
	# A red pinstripe round the shed along the top of the chequer plate.
	for run in _shed_wall_runs(wing):
		_stripe(run, 1.23, ws._mats["red"], 0.05)


## The inside of the shed's walls as runs of [from, to] (Vector3 at floor level, 1 cm in from
## the face), round every doorway.
func _shed_wall_runs(wing: bool) -> Array:
	var c := Workshop.CENTER
	var hx := Workshop.HALF.x - 0.02
	var hz := Workshop.HALF.y - 0.02
	var out := []
	# Back wall, round the dyno doorway (and the extension's).
	var back := [[-hx, -DynoRoom.DOOR_HALF]]
	if wing:
		var dx := GarageUpgrades.WING_DOOR_X - c.x
		back.append_array([[DynoRoom.DOOR_HALF, dx - GarageUpgrades.WING_DOOR_HALF], [dx + GarageUpgrades.WING_DOOR_HALF, hx]])
	else:
		back.append([DynoRoom.DOOR_HALF, hx])
	for b in back:
		out.append([c + Vector3(float(b[0]), 0.0, -hz), c + Vector3(float(b[1]), 0.0, -hz)])
	for side in [-1.0, 1.0]:
		var door_z: float = Workshop.STORE_DOOR_Z if side < 0.0 else Workshop.PAINT_DOOR_Z
		out.append([Vector3(c.x + side * hx, 0.0, c.z - hz), Vector3(c.x + side * hx, 0.0, door_z - Workshop.SIDE_DOOR_HALF)])
		out.append([Vector3(c.x + side * hx, 0.0, door_z + Workshop.SIDE_DOOR_HALF), Vector3(c.x + side * hx, 0.0, c.z + hz)])
		out.append([c + Vector3(side * hx, 0.0, hz), c + Vector3(side * Workshop.DOOR_HALF, 0.0, hz)])
	return out


func _stripe(run: Array, y: float, mat: Material, thick: float) -> void:
	var a: Vector3 = run[0]
	var b: Vector3 = run[1]
	var along_x := absf(a.x - b.x) > absf(a.z - b.z)
	var size := Vector3(absf(a.x - b.x), thick, 0.012) if along_x else Vector3(0.012, thick, absf(a.z - b.z))
	_box((a + b) * 0.5 + Vector3(0.0, y, 0.0), size, mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _led_lighting(wing: bool) -> void:
	var cool := Color(0.92, 0.96, 1.0)
	for m in ws._fixture_mats:
		(m as StandardMaterial3D).emission = cool
		(m as StandardMaterial3D).albedo_color = Color(0.95, 0.97, 1.0)
	for l in ws._shed_lights:
		if _base_lights.has(l) or l is SpotLight3D:
			l.light_energy *= 1.35
			l.light_color = cool
	# An LED strip round the top of the shed's walls (and the extension's), on the light switch.
	var strip := _glow(cool, 4.0)
	ws._fixture_mats.append(strip)
	_added_mats.append(strip)
	for run in _shed_wall_runs(wing):
		_stripe(run, Workshop.HEIGHT - 0.5, strip, 0.04)
	if wing:
		var r := GarageUpgrades.WING
		var y := GarageUpgrades.WING_HEIGHT - 0.3
		for run in [[Vector3(r.position.x + 0.02, 0, r.position.y + 0.02), Vector3(r.end.x - 0.02, 0, r.position.y + 0.02)],
				[Vector3(r.end.x - 0.02, 0, r.position.y + 0.02), Vector3(r.end.x - 0.02, 0, r.end.y - 0.02)],
				[Vector3(r.position.x + 0.02, 0, r.position.y + 0.02), Vector3(r.position.x + 0.02, 0, r.end.y - 0.02)]]:
			_stripe(run, y, strip, 0.04)


func _signage() -> void:
	var c := Workshop.CENTER
	var front := c.z + Workshop.HALF.y + 0.3
	var y := Workshop.DOOR_HEIGHT + 0.6
	# A light box behind the TORQUE SHED letters over the roller door, edged in orange neon.
	var box := SIGN_BOX
	_box(Vector3(c.x, y, front + 0.02), Vector3(box.x, box.y, 0.03), ws._material(Color(0.05, 0.05, 0.06), 0.3, 0.4)).name = "SignBox"
	var edge := _glow(Color(1.0, 0.55, 0.1), 5.0)
	for s in [-1.0, 1.0]:
		_box(Vector3(c.x, y + s * (box.y * 0.5 + 0.005), front + 0.04), Vector3(box.x + 0.1, 0.05, 0.03), edge)
		_box(Vector3(c.x + s * (box.x * 0.5 + 0.03), y, front + 0.04), Vector3(0.05, box.y + 0.05, 0.03), edge)
	var sub := _text("MOTORCYCLE RESTORATION  ·  EST. 2026", Vector3(c.x, y - 0.4, front + 0.07), 0.0, 40, Color(2.2, 1.7, 1.0), 4)
	sub.name = "SignSub"
	sub.shaded = false
	# The shed's own TORQUE SHED letters shrink to sit inside the frame with a margin all round,
	# above the strapline.
	_fit_front_sign(Vector2(c.x, y), front)
	for s in [-1.0, 1.0]:
		var wash := SpotLight3D.new()
		wash.position = Vector3(c.x + s * 1.8, y + 1.0, front + 0.6)
		wash.rotation.x = -PI * 0.42
		wash.spot_angle = 40.0
		wash.spot_range = 3.0
		wash.light_energy = 1.4
		wash.light_color = Color(1.0, 0.8, 0.55)
		_root.add_child(wash)
	# A neon sign inside on the east wall, between the bay and the parts computer.
	var neon := _text("TORQUE SHED", Vector3(c.x + Workshop.HALF.x - 0.03, 3.4, c.z - 2.0), -PI * 0.5, 120, Color(0.6, 1.6, 3.0), 14)
	neon.name = "ShedNeon"
	neon.shaded = false
	neon.outline_modulate = Color(0.1, 0.35, 0.9)
	var blue := OmniLight3D.new()
	blue.position = Vector3(c.x + Workshop.HALF.x - 0.5, 3.4, c.z - 2.0)
	blue.omni_range = 3.0
	blue.light_energy = 0.6
	blue.light_color = Color(0.4, 0.6, 1.0)
	_shed_light(blue)


## Fits the TORQUE SHED letters over the roller door inside the sign box centred at `mid`
## (x, height): no wider than the box less SIGN_MARGIN each side, and in the band above the
## strapline, in front of the box.
func _fit_front_sign(mid: Vector2, front: float) -> void:
	var l := ws.front_sign
	if l == null or _front_sign_base.is_empty():
		return
	l.pixel_size = float(_front_sign_base[0])
	l.position = Vector3(mid.x, mid.y, front + 0.06)
	var ext := front_sign_extent()
	var room := Vector2(SIGN_BOX.x - SIGN_MARGIN * 2.0, SIGN_BOX.y * 0.56)
	var w := float(ext["x"][1]) - float(ext["x"][0])
	var h := float(ext["y"][1]) - float(ext["y"][0])
	l.pixel_size *= minf(1.0, minf(room.x / w, room.y / h))
	# The capitals' middle a little above the box's, clear of the strapline under them.
	ext = front_sign_extent()
	var cap_mid := (float(ext["y"][0]) + float(ext["y"][1])) * 0.5
	l.position.y += mid.y + SIGN_BOX.y * 0.14 - cap_mid


## The TORQUE SHED letters' extent on the sign box's face ({x: [left, right], y: [bottom, top]}
## in world metres), worked out from the font: for tests and to check it fits.
func front_sign_extent() -> Dictionary:
	var l := ws.front_sign
	var size := Workshop.label_size(l)
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var line := (font.get_ascent(l.font_size) + font.get_descent(l.font_size)) * l.pixel_size
	# Capitals sit on the baseline and reach about 0.72 of the font size up.
	var base := l.position.y + line * 0.5 - font.get_ascent(l.font_size) * l.pixel_size
	var pad := l.outline_size * l.pixel_size
	return {"x": [l.position.x - size.x * 0.5, l.position.x + size.x * 0.5],
		"y": [base - pad, base + l.font_size * 0.72 * l.pixel_size + pad]}


func _showroom(wing: bool) -> void:
	# A gloss black and white chequered floor, through the shed and the extension.
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.92, 0.92, 0.92))
	img.set_pixel(1, 1, Color(0.92, 0.92, 0.92))
	img.set_pixel(1, 0, Color(0.05, 0.05, 0.06))
	img.set_pixel(0, 1, Color(0.05, 0.05, 0.06))
	var m: StandardMaterial3D = ws._mats["floor"]
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = Color.WHITE
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.83, 0.83, 0.83)   # 0.6 m tiles
	m.roughness = 0.06
	m.metallic = 0.0
	# Honeycomb LED ceilings, on the shed's light switch. They take the place of the strip light
	# fittings, which would hang right through the tubes (the lamps themselves stay).
	for strip in ws.ceiling_strips:
		strip.visible = false
	for strip in _wing_strips:
		strip.visible = false
	var c := Workshop.CENTER
	var areas := [[Rect2(c.x - Workshop.HALF.x + 0.4, c.z - Workshop.HALF.y + 0.4, Workshop.HALF.x * 2.0 - 0.8, Workshop.HALF.y * 2.0 - 0.8), Workshop.HEIGHT - 0.32]]
	if wing:
		var r := GarageUpgrades.WING
		areas.append([r.grow(-0.4), GarageUpgrades.WING_HEIGHT - 0.04])
	for a in areas:
		var glow := ws._hex_ceiling(a[0], float(a[1]), 0.7)
		var mmi := ws.get_child(ws.get_child_count() - 1)
		mmi.reparent(_root)
		ws._fixture_mats.append(glow)
		_added_mats.append(glow)
	# Chrome skirting round the shed.
	for run in _shed_wall_runs(wing):
		_stripe(run, 0.06, ws._mats["chrome"], 0.12)
