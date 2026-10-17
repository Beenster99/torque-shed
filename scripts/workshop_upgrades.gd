class_name WorkshopUpgrades
extends Node3D
## Draws the garage upgrades the crew has bought (GarageUpgrades, Shed.upgrades) onto the
## Workshop: the extension wing behind the paint shop with bays 5 to 7 and their bike lifts, the
## storage annex behind the storage room with its mezzanine, the crew lounge upstairs on top of
## the shed, and the luxury finishes (floor, walls, lights, signs). Everything it builds sits in one node that is thrown away and built
## again whenever the upgrades change, so every player sees a purchase straight away.

const T := 0.2      # wall thickness of the new buildings
const LIFT_ARM := 2.0   # length of a bike lift's scissor arms
## The lounge's windows: size, the height of their middle above its floor, and where they are.
const LOFT_WIN_W := 1.8
const LOFT_WIN_H := 1.1
const LOFT_WIN_Y := 1.5
const LOFT_FRONT_WINDOWS := [-4.4, -1.6, 1.2]
const LOFT_SIDE_WINDOWS := [62.4, 67.6]
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
var _lifts := {}       # bay -> {body, arms, motor}: the extension bays' lifts as built
var _lift_h := {}      # bay -> how high its lift's platform is right now
## The looks the finishes are drawn with (GarageUpgrades.OPTIONS): upgrade id -> {option: choice}.
var _looks := {}
## Animated looks: [kind ("strip", "neon"), effect, thing, its colour, its light, the light's energy].
var _fx: Array = []
## A look being tried on from the Garage upgrades page, on this screen only: the upgrade (built
## for the preview if it isn't yet) and its choices. "" = none.
static var preview_id := ""
static var preview_looks := {}


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
	add_to_group("workshop_upgrades")
	sync()


static func _mat_state(m: StandardMaterial3D) -> Dictionary:
	return {"albedo_color": m.albedo_color, "albedo_texture": m.albedo_texture, "roughness": m.roughness,
		"metallic": m.metallic, "uv1_scale": m.uv1_scale, "emission": m.emission, "uv1_triplanar": m.uv1_triplanar,
		"texture_filter": m.texture_filter}


## Rebuilds if the upgrades (or their looks, or a look being previewed) have changed since the
## last time.
func sync() -> void:
	var have := _have()
	var ids: Array = have.keys()
	ids.sort()
	var sig := ",".join(ids)
	var looks := {}
	for id in ids:
		if GarageUpgrades.has_options(id):
			looks[id] = GarageUpgrades.clean_looks(id, preview_looks if id == preview_id else Shed.looks.get(id, {}))
	if sig == _sig and looks == _looks:
		return
	_sig = sig
	_looks = looks
	_rebuild(have)


## The upgrades to draw: the shed's, plus one being previewed.
func _have() -> Dictionary:
	if preview_id == "" or not GarageUpgrades.has_options(preview_id):
		return Shed.upgrades
	var have := Shed.upgrades.duplicate()
	have[preview_id] = true
	return have


## Tries a look on the shed, on this screen only (`id` "" puts it back as it is). Everyone else
## keeps seeing the shed as it is until it's bought.
static func set_preview(tree: SceneTree, id: String, chosen: Dictionary) -> void:
	preview_id = id
	preview_looks = chosen.duplicate()
	if tree:
		tree.call_group("workshop_upgrades", "sync")


## The looks the finishes are drawn with right now (for tests).
func looks_shown() -> Dictionary:
	return _looks


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
	_ride_lifts()
	if not _fx.is_empty():
		_animate(Time.get_ticks_msec() / 1000.0)


# ---------------------------------------------------------------------------- rebuilding

func _undo() -> void:
	_probes.clear()
	_fx.clear()
	_arcade_text = null
	_lifts.clear()
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
	# The wash bay's lift is there from the start (it isn't an upgrade), but lives with the rest.
	_build_lift(Wash.LIFT, Wash.lift_xf())
	if have.has("lounge"):
		_build_loft()
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
	_lounge_looks()
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


func _text(text: String, pos: Vector3, rot_y: float, size := 32, color := Color(1, 1, 1), outline := 6, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = outline
	(parent if parent else _root).add_child(l)
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
## from `a` to `b`, the face at `at` (z for an x wall, x for a z wall), `h` high from a floor
## at `y0`.
func _faces(along_x: bool, a: float, b: float, at: float, h: float, y0 := 0.0) -> void:
	var mid := (a + b) * 0.5
	var len := absf(b - a)
	var c := Vector3(mid, y0, at) if along_x else Vector3(at, y0, mid)
	var size := Vector3(len, 0.0, 0.02) if along_x else Vector3(0.02, 0.0, len)
	_box(c + Vector3(0.0, h * 0.5 + 0.6, 0.0), size + Vector3(0.0, h - 1.2, 0.0), ws._mats["wall_in"])
	_box(c + Vector3(0.0, 0.6, 0.0), size + Vector3(0.0, 1.2, 0.0), ws._mats["wall_low"])


## A hazard-yellow frame round a doorway in a wall running along x, the wall's middle at `z`,
## on a floor at `y0`. It stands a centimetre proud into the opening so its faces don't sit in
## the same plane as the wall's edges and flicker against them.
func _door_frame(x: float, half: float, h: float, z: float, depth: float, y0 := 0.0) -> void:
	for end in [-1.0, 1.0]:
		_box(Vector3(x + end * (half + 0.045), y0 + (h - 0.01) * 0.5, z), Vector3(0.11, h - 0.01, depth + 0.06), _mats["hazard"])
	_box(Vector3(x, y0 + h + 0.045, z), Vector3(half * 2.0 + 0.2, 0.11, depth + 0.06), _mats["hazard"])


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


## One of the extension's bays: painted box and number, a bike lift (a chequer plate platform
## on scissor arms, raised and lowered from the button post beside it), a bay light and its
## own screen on the back wall.
func _build_wing_bay(bay: int) -> void:
	var xf := Workshop.bay_transform(bay)
	var o := xf.origin
	for side in [-1.0, 1.0]:
		_box(o + Vector3(side * 1.5, 0.01, 0.4), Vector3(0.06, 0.004, 3.1), ws._mats["yellow"])
	var num := _text("BAY %d" % (bay + 1), o + Vector3(0.0, 0.012, 1.75), 0.0, 72, Color(0.95, 0.8, 0.2))
	num.rotation.x = -PI * 0.5
	_build_lift(bay, xf)
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


## A bay's bike lift: a pit frame flush in the floor, the platform (which moves, carrying the
## bike on its paddock stand and anyone standing on it), scissor arms under it, and a post with
## up and down buttons. Look at the post and press F to raise or lower it (Shed "lift"). The wash
## bay's (Wash.LIFT) is a narrow grated runway instead, so the jet gets through to underneath.
func _build_lift(bay: int, xf: Transform3D) -> void:
	var washing := bay == Wash.LIFT
	var base := Node3D.new()
	base.name = "WashLiftBase" if washing else "LiftBase%d" % bay
	base.transform = xf
	_root.add_child(base)
	var plate := Vector3(0.3, 0.03, 2.3) if washing else Vector3(0.9, 0.024, 2.5)
	ws._deco(base, Vector3(0.0, 0.003, 0.0), Vector3(plate.x + 0.16, 0.006, plate.z + 0.16), ws._mats["dark"])
	var body := AnimatableBody3D.new()
	body.name = "WashLift" if washing else "Lift%d" % bay
	body.set_meta("surface", "metal")
	var shape := BoxShape3D.new()
	shape.size = Vector3(plate.x, 0.06, plate.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.03     # its top is the platform's height
	body.add_child(cs)
	base.add_child(body)
	if washing:
		# A grating: cross bars between the side rails, open between them.
		for i in 24:
			ws._deco(body, Vector3(0.0, plate.y * 0.5, -plate.z * 0.5 + 0.05 + i * (plate.z - 0.1) / 23.0), Vector3(plate.x, plate.y, 0.02), _mats["grate"])
	else:
		ws._deco(body, Vector3(0.0, plate.y * 0.5, 0.0), plate, _mats["plate"])
	for side in [-1.0, 1.0]:
		ws._deco(body, Vector3(side * (plate.x * 0.5 + 0.02), plate.y * 0.5 + 0.002, 0.0), Vector3(0.05, plate.y + 0.004, plate.z + 0.05), _mats["hazard"])
	# A wheel chock at the front of the platform.
	ws._deco(body, Vector3(0.0, 0.07, -plate.z * 0.5 + 0.08), Vector3(0.24, 0.12, 0.1), _mats["hazard"])
	# Scissor arms: a crossed pair each side, opening as the platform goes up.
	var arms := []
	for side in [-1.0, 1.0]:
		for lean in [-1.0, 1.0]:
			var arm := ws._deco(base, Vector3(side * (0.12 if washing else 0.3), 0.0, 0.0), Vector3(0.05, 0.04, LIFT_ARM), ws._mats["steel"])
			arm.set_meta("lean", lean)
			arms.append(arm)
	# The control post beside the bay, with its buttons: F on it raises or lowers the lift.
	var post := Vector3(-1.25, 0.0, 1.6)
	ws._solid(post + Vector3(0.0, 0.55, 0.0), Vector3(0.18, 1.1, 0.14), _mats["hazard"], base)
	ws._deco(base, post + Vector3(0.0, 1.0, -0.075), Vector3(0.06, 0.06, 0.02), ws._material(Color(0.1, 0.6, 0.15), 0.0, 0.4))
	ws._deco(base, post + Vector3(0.0, 0.88, -0.075), Vector3(0.06, 0.06, 0.02), ws._mats["red"])
	var tag := _text("LIFT\n▲ ▼", post + Vector3(0.0, 0.72, -0.075), PI, 22, Color(0.08, 0.08, 0.08), 0, base)
	tag.pixel_size = 0.003
	ws._target(post + Vector3(0.0, 0.8, 0.0), Vector3(0.4, 0.8, 0.4), {"lift": bay}, base)
	var motor := Sfx.make_loop_player(base)
	motor.position = Vector3(0.0, 0.3, 0.0)
	_lifts[bay] = {"body": body, "arms": arms, "motor": motor, "xf": xf, "top": Wash.LIFT_TOP if washing else GarageUpgrades.LIFT_TOP}
	if not _lift_h.has(bay):
		_lift_h[bay] = float(_lifts[bay]["top"]) if Shed.lifts.has(bay) else 0.0
	_pose_lift(bay, float(_lift_h[bay]))


## Puts a lift's platform and arms at height `h`.
func _pose_lift(bay: int, h: float) -> void:
	var l: Dictionary = _lifts[bay]
	(l["body"] as Node3D).position.y = h
	var a := asin(clampf(h / LIFT_ARM, 0.0, 1.0))
	for arm in l["arms"]:
		var mi := arm as MeshInstance3D
		mi.position.y = h * 0.5
		mi.rotation.x = a * float(mi.get_meta("lean"))


## How far up the lift a bike at `at` is standing on is right now (0 off a lift, or with it down).
func lift_height_at(at: Vector3) -> float:
	for bay in _lifts:
		var o: Vector3 = (_lifts[bay]["xf"] as Transform3D).origin
		if Vector2(at.x - o.x, at.z - o.z).length() < 0.5:
			return float(_lift_h.get(bay, 0.0))
	return 0.0


## The lifts run here on every player's machine from Shed.lifts (which bays are up), so they
## go up and down smoothly for everyone.
func _physics_process(delta: float) -> void:
	for bay in _lifts:
		var want := float(_lifts[bay]["top"]) if Shed.lifts.has(bay) else 0.0
		var was := float(_lift_h.get(bay, 0.0))
		var h := move_toward(was, want, GarageUpgrades.LIFT_SPEED * delta)
		_lift_h[bay] = h
		if h != was:
			_pose_lift(bay, h)
		var motor: AudioStreamPlayer3D = _lifts[bay]["motor"]
		Sfx.set_loop(motor, "door" if h != was else "")


## Bikes (and holograms) standing on a lift ride up and down with it.
func _ride_lifts() -> void:
	if _lifts.is_empty():
		return
	for id in ws.bike_views:
		if not Shed.bikes.has(id) or Shed.bikes[id].get("pusher", 0) != 0:
			continue
		var at: Vector3 = (Shed.bikes[id]["xf"] as Transform3D).origin
		(ws.bike_views[id] as Node3D).position = at + Vector3.UP * lift_height_at(at)
	for bay in ws._holo_views:
		var at := Workshop.bay_transform(int(bay)).origin
		(ws._holo_views[bay] as Node3D).position = at + Vector3.UP * lift_height_at(at)


# ---------------------------------------------------------------------------- the crew lounge

## The crew lounge: a room of its own upstairs on top of the shed (the shed's roof is its
## floor), with windows, its own lights, and a steel staircase up the front of the paint shop to
## a landing at its door. Inside: leather sofa, coffee table, rug, drinks fridge, arcade
## machine, pool table, a floor lamp and a neon sign.
func _build_loft() -> void:
	var r := GarageUpgrades.LOFT
	var y0 := GarageUpgrades.LOFT_FLOOR
	var h := GarageUpgrades.LOFT_HEIGHT
	var mid := r.get_center()
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var boards := ws._material(Color(0.42, 0.28, 0.17), 0.0, 0.5, ws._noise(0.7, 0.8, 1.12), 3.0)
	var loft_floor := _box(Vector3(mid.x, y0 + 0.004, mid.y), Vector3(r.size.x, 0.008, r.size.y), boards)
	loft_floor.name = "LoftFloor"
	loft_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Walls on the edge of the shed's roof, and a roof of its own.
	_wall(Vector3(mid.x, y0 + h * 0.5, z0 - T * 0.5), Vector3(r.size.x + T * 2.0, h, T)).name = "LoftBackWall"
	var dx := GarageUpgrades.LOFT_DOOR_X
	var dh := GarageUpgrades.LOFT_DOOR_HALF
	var door_h := GarageUpgrades.LOFT_DOOR_HEIGHT
	# The front and side walls have real openings for the windows (and the door), so you can see
	# out of the lounge and into it.
	var sill := LOFT_WIN_Y - LOFT_WIN_H * 0.5
	var head := LOFT_WIN_Y + LOFT_WIN_H * 0.5
	var front_holes := [[dx, dh, 0.0, door_h]]
	for wx in LOFT_FRONT_WINDOWS:
		front_holes.append([wx, LOFT_WIN_W * 0.5, sill, head])
	var side_holes := []
	for wz in LOFT_SIDE_WINDOWS:
		side_holes.append([wz, LOFT_WIN_W * 0.5, sill, head])
	_holed_wall(true, x0 - T, x1 + T, z1 + T * 0.5, y0, h, front_holes, "LoftFrontWall")
	for side in [-1.0, 1.0]:
		_holed_wall(false, z0, z1, mid.x + side * (r.size.x * 0.5 + T * 0.5), y0, h, side_holes, "LoftSideWall")
	_wall(Vector3(mid.x, y0 + h + 0.1, mid.y), Vector3(r.size.x + T * 2.0 + 0.4, 0.2, r.size.y + T * 2.0 + 0.4), ws._mats["roof"]).name = "LoftRoof"
	_faces(true, x0, x1, z0 + 0.01, h, y0)
	_holed_faces(false, z0, z1, x0 + 0.01, y0, h, side_holes)
	_holed_faces(false, z0, z1, x1 - 0.01, y0, h, side_holes)
	_holed_faces(true, x0, x1, z1 - 0.01, y0, h, front_holes)
	_door_frame(dx, dh, door_h, z1 + T * 0.5, T, y0)
	var ceiling := ws._material(Color(0.86, 0.85, 0.82), 0.0, 0.8)
	_box(Vector3(mid.x, y0 + h - 0.01, mid.y), Vector3(r.size.x, 0.02, r.size.y), ceiling)
	# Windows: clear glazing in the openings, with frames inside and out.
	var glaze := ws._material(Color(0.7, 0.82, 0.9, 0.18), 0.1, 0.03)
	glaze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glaze.cull_mode = BaseMaterial3D.CULL_DISABLED
	for wx in LOFT_FRONT_WINDOWS:
		_window(Vector3(wx, y0 + LOFT_WIN_Y, z1), true, glaze)
	for side in [-1.0, 1.0]:
		for wz in LOFT_SIDE_WINDOWS:
			_window(Vector3(mid.x + side * (r.size.x * 0.5), y0 + LOFT_WIN_Y, wz), false, glaze)
	# Lights on the shed's switch: a pendant over the pool table, ceiling panels, the lamp.
	var fixture := _shed_fixture()
	for at in [Vector3(-3.6, 0.0, 62.6), Vector3(-3.6, 0.0, 67.4)]:
		_box(Vector3(at.x, y0 + h - 0.04, at.z), Vector3(0.6, 0.04, 0.6), fixture)
		var omni := OmniLight3D.new()
		omni.position = Vector3(at.x, y0 + h - 0.4, at.z)
		omni.omni_range = 6.0
		omni.light_energy = 0.9
		omni.light_color = Color(1.0, 0.9, 0.78)
		omni.shadow_enabled = at.z < 65.0
		_shed_light(omni)
	_build_lounge_kit(y0)
	# The room's own light probe, upstairs.
	var probe := ReflectionProbe.new()
	probe.position = Vector3(mid.x, y0 + h * 0.5, mid.y)
	probe.size = Vector3(r.size.x + 0.1, h, r.size.y + 0.1)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.6, 0.5, 0.42)
	probe.ambient_color_energy = 0.5
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_root.add_child(probe)
	_probes.append([probe, "", 0.5])
	_build_loft_stairs()


## A window in a wall of the lounge: `at` is the middle of the wall's inside face line (z for the
## front wall `along_x`, x for a side wall), glazed with a frame on both faces.
func _window(at: Vector3, along_x: bool, glaze: Material) -> void:
	var w := LOFT_WIN_W
	var wh := LOFT_WIN_H
	var mid_wall := at + (Vector3(0.0, 0.0, T * 0.5) if along_x else Vector3(signf(at.x - GarageUpgrades.LOFT.get_center().x) * T * 0.5, 0.0, 0.0))
	var pane := _box(mid_wall, Vector3(w, wh, 0.01) if along_x else Vector3(0.01, wh, w), glaze)
	pane.name = "LoftWindowGlass"
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for face in [-1.0, 1.0]:
		var off: float = face * (T * 0.5 + 0.012)
		var c := at + (Vector3(0.0, 0.0, T * 0.5 + off) if along_x else Vector3(signf(at.x - GarageUpgrades.LOFT.get_center().x) * T * 0.5 + off, 0.0, 0.0))
		var bar := Vector3(w + 0.1, 0.06, 0.03) if along_x else Vector3(0.03, 0.06, w + 0.1)
		var post := Vector3(0.06, wh, 0.03) if along_x else Vector3(0.03, wh, 0.06)
		for s in [-1.0, 1.0]:
			_box(c + Vector3(0.0, s * wh * 0.5, 0.0), bar, ws._mats["dark"])
			_box(c + (Vector3(s * w * 0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, s * w * 0.5)), post, ws._mats["dark"])
		_box(c, post, ws._mats["dark"])


## A wall along x (`along_x`, at z = `at`) or along z (at x = `at`) from `a` to `b`, `h` high on a
## floor at `y0`, with openings `holes`: [middle, half width, bottom, top] above the floor.
func _holed_wall(along_x: bool, a: float, b: float, at: float, y0: float, h: float, holes: Array, label := "") -> void:
	for piece in _wall_pieces(a, b, h, holes):
		var mid := (float(piece[0]) + float(piece[1])) * 0.5
		var len := float(piece[1]) - float(piece[0])
		var y := y0 + (float(piece[2]) + float(piece[3])) * 0.5
		var tall := float(piece[3]) - float(piece[2])
		var w := _wall(Vector3(mid, y, at) if along_x else Vector3(at, y, mid), Vector3(len, tall, T) if along_x else Vector3(T, tall, len))
		if label != "":
			w.name = label


## The inside lining of a holed wall: the darker band low down and the paint above it.
func _holed_faces(along_x: bool, a: float, b: float, at: float, y0: float, h: float, holes: Array) -> void:
	for piece in _wall_pieces(a, b, h, holes):
		var mid := (float(piece[0]) + float(piece[1])) * 0.5
		var len := float(piece[1]) - float(piece[0])
		for band in [[0.0, 1.2, "wall_low"], [1.2, h, "wall_in"]]:
			var lo := maxf(float(piece[2]), float(band[0]))
			var hi := minf(float(piece[3]), float(band[1]))
			if hi - lo < 0.005:
				continue
			var y := y0 + (lo + hi) * 0.5
			_box(Vector3(mid, y, at) if along_x else Vector3(at, y, mid),
				Vector3(len, hi - lo, 0.02) if along_x else Vector3(0.02, hi - lo, len), ws._mats[str(band[2])])


## The solid pieces of a wall from `a` to `b` and 0 to `h` high round its openings, as
## [from, to, bottom, top]: full height between openings, and a sill and a head over each.
static func _wall_pieces(a: float, b: float, h: float, holes: Array) -> Array:
	var cuts := holes.filter(func(o): return float(o[0]) + float(o[1]) > a and float(o[0]) - float(o[1]) < b)
	cuts.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var out := []
	var x := a
	for o in cuts:
		var lo := maxf(float(o[0]) - float(o[1]), a)
		var hi := minf(float(o[0]) + float(o[1]), b)
		if lo > x + 0.001:
			out.append([x, lo, 0.0, h])
		if float(o[2]) > 0.001:
			out.append([lo, hi, 0.0, float(o[2])])
		if float(o[3]) < h - 0.001:
			out.append([lo, hi, float(o[3]), h])
		x = hi
	if b > x + 0.001:
		out.append([x, b, 0.0, h])
	return out


## The lounge's furniture, on its floor at `y0`.
func _build_lounge_kit(y0: float) -> void:
	var r := GarageUpgrades.LOFT
	var west := r.position.x
	var sz := r.get_center().y
	_box(Vector3(west + 1.9, y0 + 0.012, sz), Vector3(3.0, 0.01, 3.4), _mats["rug"]).name = "LoungeRug"
	# The sofa against the west wall, facing into the room.
	var sx := west + 0.5
	var sofa := ws._solid(Vector3(sx, y0 + 0.22, sz), Vector3(0.85, 0.44, 2.1), _mats["leather"], _root)
	sofa.name = "LoungeSofa"
	_box(Vector3(sx, y0 + 0.5, sz), Vector3(0.8, 0.14, 1.95), _mats["leather"])
	_box(Vector3(west + 0.12, y0 + 0.72, sz), Vector3(0.22, 0.6, 2.1), _mats["leather"])
	for end in [-1.0, 1.0]:
		_box(Vector3(sx, y0 + 0.6, sz + end * 1.0), Vector3(0.85, 0.3, 0.2), _mats["leather"])
	# Coffee table: glass on chrome legs, with a couple of cans on it.
	var tx := sx + 1.15
	_box(Vector3(tx, y0 + 0.42, sz), Vector3(0.6, 0.03, 1.0), _mats["glass"])
	for i in 4:
		_box(Vector3(tx + (0.25 if i % 2 == 0 else -0.25), y0 + 0.21, sz + (0.42 if i < 2 else -0.42)), Vector3(0.04, 0.42, 0.04), ws._mats["chrome"])
	ws._blocker(Vector3(tx, y0 + 0.22, sz), Vector3(0.6, 0.44, 1.0), _root)
	for i in 2:
		_cylinder(Vector3(tx - 0.1 + i * 0.18, y0 + 0.5, sz + 0.2 - i * 0.12), 0.033, 0.033, 0.12, ws._mats["red"] if i == 0 else ws._mats["blue"])
	# The drinks fridge and the arcade machine against the back wall, facing into the room.
	var unit := Node3D.new()
	unit.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-1.9, y0, r.position.y + 0.4))
	_root.add_child(unit)
	ws._solid(Vector3(0.0, 0.93, 0.0), Vector3(0.7, 1.86, 0.66), _mats["white"], unit).name = "LoungeFridge"
	ws._deco(unit, Vector3(0.0, 0.95, -0.335), Vector3(0.58, 1.6, 0.012), _glow(Color(0.75, 0.9, 1.0), 1.2))
	ws._deco(unit, Vector3(0.0, 0.95, -0.345), Vector3(0.6, 1.62, 0.01), _mats["glass"])
	for shelf in 4:
		for b in 5:
			var bottle := _cylinder(Vector3(-0.22 + b * 0.11, 0.38 + shelf * 0.38, -0.36), 0.018, 0.03, 0.24,
				[ws._mats["red"], ws._mats["blue"], _mats["hazard"], ws._mats["chrome"]][(shelf + b) % 4], unit)
			bottle.name = "Bottle"
	_text("COLD ONES", Vector3(0.0, 1.78, -0.352), PI, 26, Color(0.2, 0.5, 0.9), 0, unit)
	var ax := -1.0      # beside it (to the east in the room)
	ws._solid(Vector3(ax, 0.9, 0.0), Vector3(0.72, 1.8, 0.7), _mats["cabinet"], unit).name = "LoungeArcade"
	var screen := ws._deco(unit, Vector3(ax, 1.32, -0.33), Vector3(0.56, 0.44, 0.04), _glow(Color(0.2, 0.9, 0.6), 2.5))
	screen.rotation.x = -0.2
	ws._deco(unit, Vector3(ax, 0.98, -0.42), Vector3(0.66, 0.06, 0.24), ws._mats["dark"])
	for i in 4:
		var btn := ws._deco(unit, Vector3(ax - 0.18 + i * 0.12, 1.02, -0.45), Vector3(0.05, 0.03, 0.05), _glow([Color(1, 0.2, 0.2), Color(0.2, 0.5, 1), Color(1, 0.85, 0.1), Color(0.2, 1, 0.3)][i], 2.0))
		btn.name = "ArcadeButton%d" % i
	ws._deco(unit, Vector3(ax, 1.7, -0.34), Vector3(0.7, 0.16, 0.02), _glow(Color(1.0, 0.3, 0.8), 3.0))
	var marquee := _text("TORQUE RACER", Vector3(ax, 1.7, -0.36), PI, 30, Color(1, 1, 1), 4, unit)
	marquee.pixel_size = 0.0028
	_arcade_text = _text("INSERT COIN", Vector3(ax, 1.3, -0.37), PI, 24, Color(1.0, 0.95, 0.4), 4, unit)
	_arcade_text.pixel_size = 0.0025
	# A pool table in the middle of the room, with the balls racked and a cue on it.
	var pool := Vector3(1.6, y0, sz)
	var felt := ws._material(Color(0.05, 0.4, 0.18), 0.0, 0.9)
	ws._solid(pool + Vector3(0.0, 0.42, 0.0), Vector3(1.3, 0.84, 2.4), ws._mats["wood"], _root).name = "LoungePoolTable"
	_box(pool + Vector3(0.0, 0.845, 0.0), Vector3(1.12, 0.01, 2.22), felt)
	for s in [-1.0, 1.0]:
		_box(pool + Vector3(s * 0.6, 0.88, 0.0), Vector3(0.1, 0.07, 2.4), ws._mats["wood"])
		_box(pool + Vector3(0.0, 0.88, s * 1.15), Vector3(1.3, 0.07, 0.1), ws._mats["wood"])
	var colors := [Color(0.95, 0.8, 0.1), Color(0.1, 0.2, 0.8), Color(0.85, 0.1, 0.1), Color(0.4, 0.1, 0.5), Color(0.95, 0.45, 0.05),
		Color(0.05, 0.45, 0.15), Color(0.5, 0.1, 0.1), Color(0.05, 0.05, 0.05)]
	var n := 0
	for row in 4:
		for k in row + 1:
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.028
			sphere.height = 0.056
			ball.mesh = sphere
			ball.material_override = _glow(colors[n % colors.size()], 0.05)
			ball.position = pool + Vector3((k - row * 0.5) * 0.058, 0.878, -0.5 - row * 0.05)
			_root.add_child(ball)
			n += 1
	var cue := _box(pool + Vector3(0.25, 0.88, 0.45), Vector3(0.025, 0.025, 1.4), ws._mats["wood"])
	cue.rotation.y = 0.3
	var shade := _glow(Color(0.2, 0.6, 0.3), 0.8)
	for dz in [-0.6, 0.6]:
		_box(pool + Vector3(0.0, GarageUpgrades.LOFT_HEIGHT - 0.6, dz), Vector3(0.36, 0.14, 0.36), shade)
		_box(pool + Vector3(0.0, GarageUpgrades.LOFT_HEIGHT - 0.3, dz), Vector3(0.02, 0.6, 0.02), ws._mats["dark"])
	var over := OmniLight3D.new()
	over.position = pool + Vector3(0.0, GarageUpgrades.LOFT_HEIGHT - 0.8, 0.0)
	over.omni_range = 3.5
	over.light_energy = 0.9
	over.light_color = Color(1.0, 0.9, 0.7)
	_shed_light(over)
	# A floor lamp in the corner and a neon sign over the sofa.
	var lamp := Vector3(west + 0.35, y0, r.position.y + 0.35)
	_box(lamp + Vector3(0.0, 0.8, 0.0), Vector3(0.04, 1.6, 0.04), ws._mats["chrome"])
	_box(lamp + Vector3(0.0, 1.62, 0.0), Vector3(0.36, 0.26, 0.36), _glow(Color(1.0, 0.8, 0.55), 1.5))
	var warm := OmniLight3D.new()
	warm.position = lamp + Vector3(0.0, 1.5, 0.0)
	warm.omni_range = 3.5
	warm.light_energy = 0.8
	warm.light_color = Color(1.0, 0.78, 0.5)
	_shed_light(warm)
	var neon := _text("CREW LOUNGE", Vector3(west + 0.03, y0 + 1.95, sz), PI * 0.5, 64, Color(3.0, 0.5, 2.2), 10)
	neon.name = "LoungeNeon"
	neon.shaded = false
	neon.outline_modulate = Color(0.8, 0.1, 0.6)
	var pink := OmniLight3D.new()
	pink.position = Vector3(west + 0.4, y0 + 1.9, sz)
	pink.omni_range = 2.5
	pink.light_energy = 0.6
	pink.light_color = Color(1.0, 0.35, 0.8)
	_shed_light(pink)


## A cylinder (a can, a bottle) standing at `at`.
func _cylinder(at: Vector3, top: float, bottom: float, height: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top
	cyl.bottom_radius = bottom
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = at
	(parent if parent else _root).add_child(mi)
	return mi


## The steel staircase up the front of the paint shop to the lounge: treads you see, a smooth
## slope under them you walk up, a landing at the door, and handrails both sides.
func _build_loft_stairs() -> void:
	var top := GarageUpgrades.LOFT_FLOOR
	var sx := GarageUpgrades.LOFT_STAIR_X
	var sz := GarageUpgrades.LOFT_STAIR_Z
	var zc := (sz.x + sz.y) * 0.5
	var width := sz.y - sz.x
	var run := sx.x - sx.y
	var steps := 26
	for i in steps:
		var y := top * (i + 1) / steps
		var x := sx.x - run * (i + 0.5) / steps
		_box(Vector3(x, y - 0.03, zc), Vector3(run / steps + 0.02, 0.06, width), _mats["grate"])
		_box(Vector3(x + run / steps * 0.5, y - 0.1, zc), Vector3(0.02, 0.14, width), _mats["hazard"])
	var angle := atan2(top, run)
	var slope := StaticBody3D.new()
	slope.name = "LoftStairs"
	slope.set_meta("surface", "metal")
	var shape := BoxShape3D.new()
	shape.size = Vector3(sqrt(run * run + top * top), 0.1, width)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	slope.add_child(cs)
	slope.rotation.z = -angle
	var normal := Vector3(sin(angle), cos(angle), 0.0)
	slope.position = Vector3((sx.x + sx.y) * 0.5, top * 0.5, zc) - normal * 0.05
	_root.add_child(slope)
	# Stringers along both sides, and legs down to the yard.
	for z in [sz.x + 0.03, sz.y - 0.03]:
		var stringer := _box(Vector3((sx.x + sx.y) * 0.5, top * 0.5 - 0.15, z), Vector3(sqrt(run * run + top * top), 0.25, 0.04), _mats["hazard"])
		stringer.rotation.z = -angle
	# The landing in front of the door, on legs.
	var front := Workshop.CENTER.z + Workshop.HALF.y + 0.3
	# It meets the top of the slope exactly, so there's no lip to catch your feet on.
	var land := _wall(Vector3((GarageUpgrades.LOFT_LANDING_X + sx.y) * 0.5, top - 0.08, (front + sz.y) * 0.5),
		Vector3(sx.y - GarageUpgrades.LOFT_LANDING_X, 0.16, sz.y - front), _mats["grate"])
	land.name = "LoftLanding"
	land.set_meta("surface", "metal")
	for leg in [Vector3(GarageUpgrades.LOFT_LANDING_X + 0.1, 0.0, sz.y - 0.1), Vector3(sx.y, 0.0, sz.y - 0.1),
			Vector3(sx.y + run * 0.5, 0.0, sz.y - 0.1), Vector3(sx.y + run * 0.5, 0.0, sz.x + 0.1)]:
		var foot: Vector3 = leg
		var high := top - 0.16 if foot.x <= sx.y + 0.01 else GarageUpgrades.loft_stair_height(foot.x) - 0.3
		ws._solid(foot + Vector3(0.0, high * 0.5, 0.0), Vector3(0.1, high, 0.1), _mats["hazard"], _root)
	# Handrails: up both sides of the flight, along the landing's open edge and its end.
	for z in [sz.x + 0.03, sz.y - 0.03]:
		_rail(Vector3(sx.x, 0.0, z), Vector3(sx.y, top, z))
	_rail(Vector3(sx.y, top, sz.y - 0.03), Vector3(GarageUpgrades.LOFT_LANDING_X, top, sz.y - 0.03))
	_rail(Vector3(GarageUpgrades.LOFT_LANDING_X + 0.03, top, sz.y), Vector3(GarageUpgrades.LOFT_LANDING_X + 0.03, top, front))
	# The name over the door, on a board fixed flat to the lounge's front wall (not out over the landing).
	var wall_face := GarageUpgrades.LOFT.end.y + T
	var sign_y := top + GarageUpgrades.LOFT_DOOR_HEIGHT + 0.3
	_box(Vector3(GarageUpgrades.LOFT_DOOR_X, sign_y, wall_face + 0.01), Vector3(1.5, 0.32, 0.02), _mats["hazard"]).name = "LoungeSignBoard"
	_text("CREW LOUNGE", Vector3(GarageUpgrades.LOFT_DOOR_X, sign_y, wall_face + 0.025), 0.0, 44, Color(0.08, 0.08, 0.08), 0).name = "LoungeSign"
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(GarageUpgrades.LOFT_DOOR_X, top + GarageUpgrades.LOFT_DOOR_HEIGHT + 0.2, front + 0.5)
	lamp.omni_range = 4.0
	lamp.light_energy = 0.7
	lamp.light_color = Color(1.0, 0.85, 0.6)
	_shed_light(lamp)


## A handrail from `a` to `b` (on the walking surface): a rail at hand height, a mid rail, posts,
## and solid enough not to step through.
func _rail(a: Vector3, b: Vector3) -> void:
	var up := Vector3.UP
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var flat := Vector3(along.x, 0.0, along.z).normalized()
	var pitch := asin(clampf(along.y, -1.0, 1.0))
	var yaw := atan2(-flat.z, flat.x)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	for y in [1.0, 0.5]:
		var bar := _box((a + b) * 0.5 + up * y, Vector3(length, 0.05, 0.05), _mats["hazard"])
		bar.basis = basis
	var posts := maxi(1, ceili(length / 1.2))
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		_box(p + up * 0.5, Vector3(0.05, 1.0, 0.05), _mats["hazard"])
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 1.1, 0.06)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(basis, (a + b) * 0.5 + up * 0.55)
	_root.add_child(body)


# ---------------------------------------------------------------------------- storage

## The storage annex behind the storage room: a big, tall shed of its own (wider than the
## storage room and deep) with a wide doorway through the storage room's back wall, lit from the
## storage room's switch.
func _build_annex() -> void:
	var r := GarageUpgrades.ANNEX
	var h := GarageUpgrades.ANNEX_HEIGHT
	var mid := r.get_center()
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	# A deep slab: the ground falls away behind the yard.
	var slab := _wall(Vector3(mid.x, -0.6, (z0 - T + z1) * 0.5), Vector3(r.size.x + T * 2.0, 1.2, r.size.y + T), _mats["slab"])
	slab.name = "AnnexFloor"
	var floor_mat := ws._material(Color(0.4, 0.41, 0.42), 0.0, 0.6, ws._noise(0.3, 0.85, 1.05), 4.0)
	_box(Vector3(mid.x, 0.004, mid.y), Vector3(r.size.x, 0.008, r.size.y), floor_mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall(Vector3(mid.x, h * 0.5 - 0.3, z0 - T * 0.5), Vector3(r.size.x + T * 2.0, h + 0.6, T)).name = "AnnexBackWall"
	for side in [-1.0, 1.0]:
		_wall(Vector3(mid.x + side * (r.size.x * 0.5 + T * 0.5), h * 0.5 - 0.3, mid.y), Vector3(T, h + 0.6, r.size.y))
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
	# Its face inside the storage room, which is narrower than the annex.
	var in0 := Workshop.STORE_CENTER.x - Workshop.STORE_HALF.x
	var in1 := Workshop.STORE_CENTER.x + Workshop.STORE_HALF.x
	_faces(true, in0, dx - dh, z1 + 0.21, room_h)
	_faces(true, dx + dh, in1, z1 + 0.21, room_h)
	_box(Vector3(dx, (room_h + door_h) * 0.5, z1 + 0.21), Vector3(dh * 2.0, room_h - door_h, 0.02), ws._mats["wall_in"])
	_door_frame(dx, dh, door_h, wall_z, 0.2)
	_text("ANNEX", Vector3(dx, door_h + 0.28, z1 + 0.23), 0.0, 44, Color(0.08, 0.08, 0.08), 0).name = "AnnexSign"
	# High bay lights on the storage room's switch, in two rows down the building.
	var fixture := _glow(Color(1.0, 0.95, 0.85), 4.0)
	ws._room_mats["storage"].append(fixture)
	_room_added.append([ws._room_mats["storage"], fixture])
	var i := 0
	for z in [z0 + r.size.y * 0.3, z0 + r.size.y * 0.72]:
		for x in [mid.x - 2.8, mid.x + 2.8]:
			_box(Vector3(x, h - 0.08, z), Vector3(0.5, 0.08, 0.5), fixture)
			var spot := SpotLight3D.new()
			spot.position = Vector3(x, h - 0.2, z)
			spot.rotation.x = -PI * 0.5
			spot.spot_angle = 75.0
			spot.spot_range = 9.0
			spot.light_energy = 2.0
			spot.light_color = Color(1.0, 0.95, 0.88)
			spot.shadow_enabled = i % 2 == 0
			_storage_light(spot)
			i += 1
	_probe(r, h, "storage", Color(0.55, 0.5, 0.45), 0.4)


func _storage_light(l: Light3D) -> void:
	_root.add_child(l)
	ws._room_lights["storage"].append(l)
	_room_added.append([ws._room_lights["storage"], l])


## The mezzanine across the back of the annex: a steel deck on posts, stairs up the east wall
## from a clear landing in front of them, a railing, and the deck stacked with boxed stock.
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
	var sx := GarageUpgrades.STAIR_X
	var sz := GarageUpgrades.STAIR_Z
	# Posts along the front edge, clear of the stairs.
	var span := sx.x - 0.15 - (r.position.x + 0.15)
	for i in 5:
		var x := r.position.x + 0.15 + i * span / 4.0
		_wall(Vector3(x, (top - 0.12) * 0.5, edge - 0.12), Vector3(0.14, top - 0.12, 0.14), _mats["hazard"])
	# The stairs: steps to see and a smooth slope under them to walk up.
	var run := sz.x - sz.y
	var steps := 16
	var w := sx.y - sx.x
	for i in steps:
		var y := top * (i + 1) / steps
		var z := sz.x - run * (i + 0.5) / steps
		_box(Vector3((sx.x + sx.y) * 0.5, y - 0.03, z), Vector3(w, 0.06, run / steps + 0.02), _mats["grate"])
		_box(Vector3((sx.x + sx.y) * 0.5, y - 0.1, z + run / steps * 0.5), Vector3(w, 0.14, 0.02), _mats["hazard"])
	var angle := atan2(top, run)
	var ramp := StaticBody3D.new()
	ramp.name = "MezzanineStairs"
	ramp.set_meta("surface", "metal")
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, 0.1, sqrt(run * run + top * top))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ramp.add_child(cs)
	ramp.rotation.x = angle
	var normal := Vector3(0.0, cos(angle), sin(angle))
	ramp.position = Vector3((sx.x + sx.y) * 0.5, top * 0.5, (sz.x + sz.y) * 0.5) - normal * 0.05
	_root.add_child(ramp)
	var stringer := _box(Vector3(sx.x + 0.02, top * 0.5 - 0.15, (sz.x + sz.y) * 0.5), Vector3(0.04, 0.25, sqrt(run * run + top * top)), _mats["hazard"])
	stringer.rotation.x = angle
	# Handrail up the open side of the stairs, and along the deck's edge to the stairs.
	_rail(Vector3(sx.x + 0.02, 0.0, sz.x), Vector3(sx.x + 0.02, top, sz.y))
	_rail(Vector3(r.position.x, top, edge - 0.03), Vector3(sx.x, top, edge - 0.03))
	_text("MEZZANINE  ·  STOCK", Vector3(r.get_center().x - 1.5, top - 0.14, edge + 0.01), 0.0, 36, Color(0.08, 0.08, 0.08), 0)
	var up := _text("UP TO THE\nMEZZANINE", Vector3(sx.x - 0.02, 1.4, sz.x - 0.4), -PI * 0.5, 26, Color(0.95, 0.8, 0.2), 4)
	up.name = "MezzanineSign"
	# Stock on the deck: pallets of boxes along the back wall.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var px := r.position.x + 0.8 + i * 1.4
		_box(Vector3(px, top + 0.07, z0 + 0.8), Vector3(1.1, 0.14, 1.1), ws._mats["wood"])
		var stack := rng.randi_range(1, 3)
		for j in stack:
			var size := Vector3(rng.randf_range(0.45, 0.6), rng.randf_range(0.3, 0.5), rng.randf_range(0.45, 0.6))
			var at := Vector3(px + rng.randf_range(-0.2, 0.2), top + 0.14 + size.y * 0.5 + j * 0.5, z0 + 0.8 + rng.randf_range(-0.2, 0.2))
			_box(at, size, ws._mats["box"])
		ws._blocker(Vector3(px, top + 0.75, z0 + 0.8), Vector3(1.1, 1.3, 1.1), _root)
	# Lights under the deck so the racking underneath isn't in the dark.
	for x in [r.position.x + r.size.x * 0.3, r.position.x + r.size.x * 0.7]:
		var under := OmniLight3D.new()
		under.position = Vector3(x, top - 0.4, z0 + depth * 0.5)
		under.omni_range = 5.0
		under.light_energy = 0.9
		under.light_color = Color(1.0, 0.95, 0.88)
		_storage_light(under)


# ---------------------------------------------------------------------------- finishes

## The look chosen for `id` (its defaults when nothing was).
func _look(id: String) -> Dictionary:
	return _looks.get(id, GarageUpgrades.default_looks(id))


## The epoxy floor in the colour and effect chosen (charcoal with a speckled flake as standard).
func _epoxy_floor() -> void:
	UpgradeLooks.epoxy_floor(ws._mats["floor"], _look("epoxy"))


func _wall_cladding(wing: bool) -> void:
	var stripe := UpgradeLooks.cladding(ws._mats["wall_in"], ws._mats["wall_low"], _look("cladding"))
	# A pinstripe round the shed along the top of the chequer plate (red unless chosen otherwise).
	if stripe.a > 0.0:
		var paint := UpgradeLooks.paint(stripe, 0.5, 0.35)
		for run in _shed_wall_runs(wing):
			_stripe(run, 1.23, paint, 0.05)


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
	var look := _look("led")
	var cool := UpgradeLooks.led_tone(look)
	for m in ws._fixture_mats:
		(m as StandardMaterial3D).emission = cool
		(m as StandardMaterial3D).albedo_color = cool.lerp(Color.WHITE, 0.4)
	for l in ws._shed_lights:
		if _base_lights.has(l) or l is SpotLight3D:
			l.light_energy *= 1.35
			l.light_color = cool
	# An LED strip round the top of the shed's walls (and the extension's), on the light switch,
	# in the lights' colour or its own, steady, pulsing or cycling through colours.
	var strip := _glow(UpgradeLooks.led_strip(look), 4.0)
	strip.resource_name = "LedStrip"
	ws._fixture_mats.append(strip)
	_added_mats.append(strip)
	var fx := str(GarageUpgrades.choice("led", "fx", look).get("id", "steady"))
	if fx != "steady":
		_fx.append(["strip", fx, strip, strip.emission, null, 0.0])
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
	var look := _look("signage")
	var edge := _glow(GarageUpgrades.choice("signage", "box", look).get("color", Color(1.0, 0.55, 0.1)), 5.0)
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
	# Its colour and effect, as chosen.
	UpgradeLooks.neon(neon, blue, GarageUpgrades.choice("signage", "neon", look))
	var fx := str(GarageUpgrades.choice("signage", "fx", look).get("id", "steady"))
	if fx != "steady":
		_fx.append(["neon", fx, neon, neon.modulate, blue, blue.light_energy])


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
	# (Or the floor, tile size, ceiling, light colour and trim chosen for it.)
	var look := _look("showroom")
	UpgradeLooks.showroom_floor(ws._mats["floor"], look)
	var cell := float(GarageUpgrades.choice("showroom", "ceiling", look).get("r", 0.7))
	var glow_colour: Color = GarageUpgrades.choice("showroom", "glow", look).get("color", Color(0.97, 0.99, 1.0))
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
		var glow := ws._hex_ceiling(a[0], float(a[1]), cell)
		glow.emission = glow_colour
		var mmi := ws.get_child(ws.get_child_count() - 1)
		mmi.reparent(_root)
		ws._fixture_mats.append(glow)
		_added_mats.append(glow)
	# Chrome skirting round the shed (or the trim chosen).
	var trim := UpgradeLooks.showroom_trim(look)
	for run in _shed_wall_runs(wing):
		_stripe(run, 0.06, trim, 0.12)


## The crew lounge's sofa leather, rug and neon sign in the colours chosen (after it's built).
func _lounge_looks() -> void:
	var look := _look("lounge")
	(_mats["leather"] as StandardMaterial3D).albedo_color = GarageUpgrades.choice("lounge", "sofa", look).get("color", Color(0.32, 0.09, 0.06))
	(_mats["rug"] as StandardMaterial3D).albedo_color = GarageUpgrades.choice("lounge", "rug", look).get("color", Color(0.55, 0.12, 0.1))
	var neon: Label3D = _root.find_child("LoungeNeon", true, false) as Label3D if _root else null
	if neon == null:
		return
	# The sign's own light is the pink one just in front of it.
	var light: Light3D = null
	for l in _added_lights:
		if l is OmniLight3D and l.light_color.is_equal_approx(Color(1.0, 0.35, 0.8)) and l.position.distance_to(neon.position) < 1.5:
			light = l
	UpgradeLooks.neon(neon, light, GarageUpgrades.choice("lounge", "neon", look))


## Runs the animated looks: a pulsing or colour-cycling LED strip, a flickering or pulsing neon.
func _animate(t: float) -> void:
	for i in _fx.size():
		var f: Array = _fx[i]
		var fx := str(f[1])
		if str(f[0]) == "strip":
			var m := f[2] as StandardMaterial3D
			if fx == "rainbow":
				m.emission = UpgradeLooks.fx_colour(t)
			elif ws._lights_shown:
				m.emission_energy_multiplier = 4.0 * UpgradeLooks.fx_level(fx, t)
		else:
			var level := UpgradeLooks.fx_level(fx, t, i * 1.7)
			var base: Color = f[3]
			(f[2] as Label3D).modulate = Color(base.r * level, base.g * level, base.b * level, base.a)
			if f[4]:
				(f[4] as Light3D).light_energy = float(f[5]) * level
