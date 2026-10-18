class_name WorldTown
extends Node3D
## The little town the shed stands in. The shed, the sales office and the cafe front onto the
## High Street over their forecourt; the Build Yard is behind them, up a lane either side.
## Along the street: terraces of shops (lit windows, fascia boards with their names, awnings)
## and houses either side and opposite, with a pub; raised pavements with kerbs, street lamps,
## trees, benches, bins, bollards, a post box and a phone box, a bus stop with its shelter, two
## zebra crossings with blinking beacons, cars parked along the kerbs, Station Road off to the
## loop behind the far side, and people walking about (TownPeople) with pigeons pecking round.
##
## Kept cheap to draw: the plan is fixed (plan(), the same for every seed and every player),
## every building goes into four merged meshes (walls, roofs, upper windows, shop glass), all
## the street furniture and parked cars are one more, the lamp heads another; the only real
## lights are three shadowless lamps by the shed that come on at night. Collision is one
## static body with its shapes added straight to the physics server.

## The High Street: the middle of the road, half its width, and the pavements either side.
const STREET_Z := 93.0
const ROAD_HW := 4.5
const PAVE_W := 2.5
const KERB := 0.1
## The building lines: fronts on the shed's side of the street, and opposite.
const NORTH_FRONT := STREET_Z - ROAD_HW - PAVE_W   # 86.0, where the shed's forecourt ends
const SOUTH_FRONT := STREET_Z + ROAD_HW + PAVE_W   # 100.0
## Where people walk: the middle of each pavement.
const NORTH_WALK := STREET_Z - ROAD_HW - PAVE_W * 0.5
const SOUTH_WALK := STREET_Z + ROAD_HW + PAVE_W * 0.5
## How far along the street the town runs (x), and the shed's frontage: its forecourt meets the
## road with a dropped kerb (no step), and has no buildings or posts in the way.
const X_RANGE := Vector2(-112.0, 108.0)
const FORECOURT_X := Vector2(-45.0, 45.0)
## Station Road leaves the High Street here (opposite the shed's side), and its half width.
const STATION_X := 60.0
const STATION_HW := 3.5
## The runs of buildings along each side (x), clear of the forecourt and Station Road.
const SOUTH_RUNS: Array[Vector2] = [Vector2(-112.0, 54.0), Vector2(66.0, 104.0)]
const NORTH_RUNS: Array[Vector2] = [Vector2(-112.0, -47.0), Vector2(47.0, 108.0)]
## The zebra crossings (x), and the bus stop (on the far pavement, where its people wait).
const CROSSINGS: Array[float] = [-62.0, 50.0]
const BUS_STOP := Vector3(18.0, 0.0, SOUTH_WALK)
const SHELTER_X := Vector2(16.0, 20.4)
## Where cars may park along each kerb (x): clear of the forecourt, the crossings, the bus stop
## and the line customers and cafe bikers ride in on.
const PARK_SOUTH: Array[Vector2] = [Vector2(-106.0, -68.0), Vector2(-56.0, -36.0), Vector2(78.0, 104.0)]
const PARK_NORTH: Array[Vector2] = [Vector2(-106.0, -78.0), Vector2(78.0, 104.0)]
## Where pigeons gather.
const FLOCKS: Array[Vector3] = [Vector3(-60.0, KERB, NORTH_WALK - 0.3), Vector3(21.0, KERB, SOUTH_WALK - 0.4),
	Vector3(72.0, KERB, SOUTH_WALK), Vector3(-20.0, 0.0, NORTH_WALK + 0.2)]
## Draw distances.
const BUILDING_RANGE := 1500.0
const WINDOW_RANGE := 700.0
const STREET_RANGE := 300.0
const SIGN_RANGE := 90.0

const SHOP_NAMES := ["Bakery", "Newsagent", "Chemist", "Fish & Chips", "Hardware", "Barber", "Florist",
	"Post Office", "Butcher", "Charity Shop", "Launderette", "Estate Agent", "Books", "Greengrocer",
	"Tea Rooms", "Kebab House", "Hair Studio", "Bike Spares", "Opticians", "Deli", "Pizza", "Antiques"]
const PUB_NAME := "THE RED LION"
const BRICKS := [Color(0.52, 0.27, 0.2), Color(0.58, 0.33, 0.24), Color(0.46, 0.24, 0.19), Color(0.62, 0.42, 0.3)]
const RENDERS := [Color(0.88, 0.85, 0.76), Color(0.86, 0.8, 0.66), Color(0.78, 0.82, 0.8), Color(0.9, 0.88, 0.84),
	Color(0.72, 0.66, 0.58)]
const ROOFS := [Color(0.24, 0.25, 0.28), Color(0.3, 0.3, 0.33), Color(0.5, 0.25, 0.18), Color(0.42, 0.24, 0.18)]
const TRIMS := [Color(0.1, 0.25, 0.16), Color(0.1, 0.14, 0.3), Color(0.42, 0.08, 0.1), Color(0.08, 0.08, 0.09),
	Color(0.05, 0.36, 0.38), Color(0.62, 0.45, 0.1), Color(0.35, 0.1, 0.35)]
const DOORS := [Color(0.5, 0.06, 0.06), Color(0.08, 0.14, 0.32), Color(0.08, 0.25, 0.12), Color(0.05, 0.05, 0.05),
	Color(0.85, 0.85, 0.82)]
const CARS := [Color(0.75, 0.75, 0.78), Color(0.1, 0.1, 0.12), Color(0.55, 0.06, 0.07), Color(0.12, 0.2, 0.42),
	Color(0.85, 0.85, 0.85), Color(0.3, 0.32, 0.34), Color(0.18, 0.32, 0.22), Color(0.7, 0.55, 0.2)]
const STONE := Color(0.72, 0.71, 0.67)
const PAVING := Color(0.56, 0.55, 0.52)

static var _plan := []

var people: TownPeople
var _world: World
var _shapes := []
var _body: StaticBody3D
var _beacon_mat: StandardMaterial3D
var _beacon_t := 0.0
var _mats := {}


# ---------------------------------------------------------------------------- the plan

## Every building along the street, the same every time: [{x0, x1, side (1 the far side, its
## front facing -Z; -1 the shed's side, facing +Z), front (z of its front wall), depth, floors,
## kind ("shop", "house" or "pub"), name, wall, roof, trim, door, flat, awning}]. Plots that
## would stand on the loop or Station Road behind are made shallower or left as gaps.
static func plan() -> Array:
	if not _plan.is_empty():
		return _plan
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var names: Array = SHOP_NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = names[i]
		names[i] = names[j]
		names[j] = t
	var lines := _road_lines()
	var out := []
	var pub_done := false
	for side: int in [1, -1]:
		for run: Vector2 in (SOUTH_RUNS if side == 1 else NORTH_RUNS):
			var x := run.x
			while run.y - x >= 5.0:
				var central := absf(x) < 80.0
				var kind := "shop" if rng.randf() < (0.8 if central else 0.25) else "house"
				if side == -1 and not pub_done and x < -56.0:
					kind = "pub"
					pub_done = true
				var w := rng.randf_range(7.0, 10.0) if kind == "shop" else rng.randf_range(5.8, 7.2)
				if kind == "pub":
					w = 13.0
				if run.y - x - w < 5.0:
					w = run.y - x
				var front := SOUTH_FRONT if side == 1 else NORTH_FRONT
				var depth := 10.0 if kind == "pub" else 9.0
				while depth >= 6.0 and not _clear(_rect_of(x, x + w, side, front, depth), lines):
					depth -= 1.5
				if depth >= 6.0:
					var brick := rng.randf() < 0.55
					var p := {"x0": x, "x1": x + w, "side": side, "front": front, "depth": depth,
						"floors": 3 if (kind == "shop" and rng.randf() < 0.3) else 2, "kind": kind, "name": "",
						"wall": (BRICKS[rng.randi() % BRICKS.size()] if brick else RENDERS[rng.randi() % RENDERS.size()]),
						"roof": ROOFS[rng.randi() % ROOFS.size()], "trim": TRIMS[rng.randi() % TRIMS.size()],
						"door": DOORS[rng.randi() % DOORS.size()], "flat": kind == "shop" and rng.randf() < 0.35,
						"awning": kind == "shop" and rng.randf() < 0.45}
					if kind == "shop":
						p["name"] = names.pop_front() if not names.is_empty() else "Shop"
					elif kind == "pub":
						p["name"] = PUB_NAME
					out.append(p)
				x += w
				if rng.randf() < 0.12 and run.y - x > 8.0:
					x += rng.randf_range(1.8, 3.0)   # an alley between two terraces
	_plan = out
	return out


## A plot's footprint as an x/z rectangle.
static func _rect_of(x0: float, x1: float, side: int, front: float, depth: float) -> Rect2:
	if side == 1:
		return Rect2(x0, front, x1 - x0, depth)
	return Rect2(x0, front - depth, x1 - x0, depth)


static func rect(p: Dictionary) -> Rect2:
	return _rect_of(float(p["x0"]), float(p["x1"]), int(p["side"]), float(p["front"]), float(p["depth"]))


## The centre lines of the roads behind the town (the loop and Station Road), with their half
## widths: [[PackedVector2Array, hw]].
static func _road_lines() -> Array:
	var out := []
	for def: Dictionary in WorldLayout.ROADS:
		if not str(def["name"]) in ["loop", "station"]:
			continue
		var pts := PackedVector2Array()
		for p in WorldRoads._spline(PackedVector2Array(def["pts"]), bool(def.get("closed", false))):
			if p.y > 60.0 and absf(p.x) < 160.0:
				pts.append(p)
		out.append([pts, float(def["hw"])])
	return out


static func _clear(r: Rect2, lines: Array) -> bool:
	for line: Array in lines:
		var grown := r.grow(float(line[1]) + 2.0)
		for p: Vector2 in (line[0] as PackedVector2Array):
			if grown.has_point(p):
				return false
	return true


## The building whose footprint `at` is in (grown by `margin`), or {}.
static func building_at(at: Vector3, margin := 0.0) -> Dictionary:
	for p: Dictionary in plan():
		if rect(p).grow(margin).has_point(Vector2(at.x, at.z)):
			return p
	return {}


## Where a shop's or house's front door opens onto the pavement (on the pavement just outside it).
static func door_spot(p: Dictionary) -> Vector3:
	var side := int(p["side"])
	var x := _door_x(p)
	return Vector3(x, KERB, float(p["front"]) - side * 0.6)


static func _door_x(p: Dictionary) -> float:
	var x0 := float(p["x0"])
	var x1 := float(p["x1"])
	if str(p["kind"]) == "pub":
		return (x0 + x1) * 0.5
	# Doors are at the left end seen from the street.
	return x0 + 1.2 if int(p["side"]) == -1 else x1 - 1.2


## The height of the pavement or road under (x, z) in the street, else 0 (the slab or grass).
static func ground_y(x: float, z: float) -> float:
	if z > STREET_Z - ROAD_HW and z < STREET_Z + ROAD_HW:
		return WorldRoads.YARD_LIFT
	if x < X_RANGE.x or x > X_RANGE.y:
		return 0.0
	if z >= NORTH_FRONT and z <= STREET_Z - ROAD_HW:
		return 0.0 if (x > FORECOURT_X.x and x < FORECOURT_X.y) else KERB
	if z >= STREET_Z + ROAD_HW and z <= SOUTH_FRONT:
		return WorldRoads.YARD_LIFT if absf(x - STATION_X) < STATION_HW else KERB
	return 0.0


## Where something saved before the town (bikes, yard kit, people) belongs now: the old yard in
## front of the shed (south of its forecourt) moved, as it was, to the yard behind; anything in
## a building moved out onto the pavement in front of it. Anything else stays where it is.
static func migrate_xf(xf: Transform3D) -> Transform3D:
	var o := xf.origin
	if o.x > -66.0 and o.x < 66.0 and o.z > NORTH_FRONT + 0.5 and o.z < 146.0:
		return Transform3D(xf.basis, o + Vector3(0.0, 0.0, -110.0))
	var b := building_at(o, 0.3)
	if not b.is_empty():
		var z := NORTH_WALK if int(b["side"]) == -1 else SOUTH_WALK
		return Transform3D(xf.basis, Vector3(o.x, ground_y(o.x, z), z))
	return xf


## migrate_xf on every transform anywhere in `data` (a saved shed, or the players), in place.
static func migrate(data) -> void:
	if data is Dictionary:
		for k in data.keys():
			var v = data[k]
			if v is Transform3D:
				data[k] = migrate_xf(v)
			elif v is Dictionary or v is Array:
				migrate(v)
	elif data is Array:
		for i in data.size():
			var v = data[i]
			if v is Transform3D:
				data[i] = migrate_xf(v)
			elif v is Dictionary or v is Array:
				migrate(v)


# ---------------------------------------------------------------------------- building it

func build(world: World) -> void:
	_world = world
	_body = StaticBody3D.new()
	_body.name = "TownSolids"
	_body.set_meta("surface", "tarmac")
	_body.collision_layer = 1
	add_child(_body)
	_build_buildings()
	_build_pavements()
	_build_markings()
	_build_furniture()
	_build_lights()
	people = TownPeople.new()
	people.name = "People"
	add_child(people)
	people.setup(world, self)


func _process(delta: float) -> void:
	# The crossings' beacons blink, a little under once a second.
	_beacon_t += delta
	if _beacon_mat and _beacon_t >= 0.55:
		_beacon_t = 0.0
		_beacon_mat.emission_energy_multiplier = 0.15 if _beacon_mat.emission_energy_multiplier > 1.0 else 3.5


func _mat(key: String, color: Color, rough := 0.85, tinted := true) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.vertex_color_use_as_albedo = tinted
	_mats[key] = m
	return m


func _glow_mat(key: String, albedo: Color, emission: Color, night: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = 0.05
	_mats[key] = m
	return m


## A mesh from `st` under the town, drawn to `reach` m (times the draw distance), lit at night
## to `night` (when > 0: it joins Daylight's night lights).
func _mesh(st: SurfaceTool, node_name: String, mat: Material, reach: float, shadows := true, night := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_world.ranged(mi, reach)
	if night > 0.0:
		mi.set_meta("night_emission", night)
		mi.add_to_group(Daylight.NIGHT_LIGHTS)
	return mi


func _box_shape(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var box := BoxShape3D.new()
	box.size = size
	PhysicsServer3D.body_add_shape(_body.get_rid(), box.get_rid(), Transform3D(Basis(Vector3.UP, yaw), center))
	_shapes.append(box)


func _post_shape(at: Vector3, radius: float, height: float) -> void:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	PhysicsServer3D.body_add_shape(_body.get_rid(), c.get_rid(), Transform3D(Basis(), at + Vector3.UP * height * 0.5))
	_shapes.append(c)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# ---------------------------------------------------------------------------- buildings

func _build_buildings() -> void:
	var walls := _begin()
	var roofs := _begin()
	var windows := _begin()
	var glass := _begin()
	for p: Dictionary in plan():
		_add_building(p, walls, roofs, windows, glass)
	_mesh(walls, "Walls", _mat("walls", Color.WHITE, 0.9), BUILDING_RANGE)
	_mesh(roofs, "Roofs", _mat("roofs", Color.WHITE, 0.8), BUILDING_RANGE)
	var win := _glow_mat("windows", Color(0.16, 0.19, 0.23), Color(1.0, 0.78, 0.48), 0.9)
	win.metallic = 0.3
	_mesh(windows, "Windows", win, WINDOW_RANGE, false, 0.9)
	var shop := _glow_mat("shop_glass", Color(0.2, 0.24, 0.27), Color(1.0, 0.82, 0.56), 1.1)
	shop.metallic = 0.35
	shop.roughness = 0.08
	_mesh(glass, "ShopGlass", shop, WINDOW_RANGE, false, 1.1)


## One building of the plan into the merged meshes, with its collision and its sign.
func _add_building(p: Dictionary, walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, glass: SurfaceTool) -> void:
	var side := int(p["side"])
	var w := float(p["x1"]) - float(p["x0"])
	var d := float(p["depth"])
	var floors := int(p["floors"])
	var h := floors * 2.9 + 0.4
	var kind := str(p["kind"])
	var wall: Color = p["wall"]
	var trim: Color = p["trim"]
	var mid := Vector3((float(p["x0"]) + float(p["x1"])) * 0.5, 0.0, float(p["front"]) + side * d * 0.5)
	# The front (local +Z) faces the street.
	var xf := Transform3D(Basis(Vector3.UP, PI if side == 1 else 0.0), mid)
	var fz := d * 0.5
	WorldBuildings.box(walls, xf, Vector3(0.0, (h - 0.5) * 0.5, 0.0), Vector3(w, h + 0.5, d), wall)
	_box_shape(mid + Vector3.UP * h * 0.5, Vector3(w, h, d))
	if bool(p["flat"]):
		WorldBuildings.box(roofs, xf, Vector3(0.0, h + 0.05, 0.0), Vector3(w - 0.1, 0.1, d - 0.1), Color(0.3, 0.3, 0.31))
		WorldBuildings.box(walls, xf, Vector3(0.0, h + 0.35, fz - 0.12), Vector3(w, 0.7, 0.24), wall.darkened(0.08))
		WorldBuildings.box(walls, xf, Vector3(0.0, h + 0.72, fz - 0.12), Vector3(w + 0.04, 0.06, 0.32), STONE)
	else:
		var rise := d * 0.36
		WorldBuildings.prism(roofs, walls, xf, Vector3(0.0, h, 0.0), w * 0.5 + 0.02, d * 0.5 + 0.35, rise, false, p["roof"], wall)
		WorldBuildings.box(walls, xf, Vector3(w * 0.5 - 0.6, h + rise * 0.5, -0.4), Vector3(0.7, rise + 1.0, 0.8), WorldBuildings.BRICK)
	# Upper windows, front and back, with stone sills.
	var n := maxi(1, int(w / 2.6))
	for f in range(1, floors):
		var y := 1.55 + f * 2.9
		for k in n:
			var x := -w * 0.5 + w * (k + 0.5) / n
			WorldBuildings.box(windows, xf, Vector3(x, y, fz + 0.03), Vector3(1.0, 1.3, 0.06), Color.WHITE)
			WorldBuildings.box(walls, xf, Vector3(x, y - 0.72, fz + 0.06), Vector3(1.2, 0.1, 0.14), STONE)
			if k % 2 == 0:
				WorldBuildings.box(windows, xf, Vector3(x, y, -fz - 0.03), Vector3(0.9, 1.2, 0.06), Color.WHITE)
	var dx := _door_x(p) - mid.x
	# Seen from the street the door is at local x = dx with the front's own x axis.
	var lx := dx * (-1.0 if side == 1 else 1.0)
	match kind:
		"shop", "pub":
			_shop_front(p, xf, w, fz, lx, walls, windows, glass)
		_:
			WorldBuildings.box(walls, xf, Vector3(lx, 1.1, fz + 0.04), Vector3(0.95, 2.2, 0.08), p["door"])
			WorldBuildings.box(walls, xf, Vector3(lx, 2.3, fz + 0.06), Vector3(1.2, 0.12, 0.16), STONE)
			WorldBuildings.box(walls, xf, Vector3(lx, 0.05, fz + 0.3), Vector3(1.2, 0.1, 0.5), STONE)
			var wx := lx + (1.8 if lx < 0.0 else -1.8)
			WorldBuildings.box(windows, xf, Vector3(wx, 1.5, fz + 0.03), Vector3(1.5, 1.3, 0.06), Color.WHITE)
			WorldBuildings.box(walls, xf, Vector3(wx, 0.78, fz + 0.06), Vector3(1.7, 0.1, 0.14), STONE)


func _shop_front(p: Dictionary, xf: Transform3D, w: float, fz: float, lx: float, walls: SurfaceTool, windows: SurfaceTool,
		glass: SurfaceTool) -> void:
	var trim: Color = p["trim"]
	var pub := str(p["kind"]) == "pub"
	# The door, then the shop window across the rest of the front on a low riser.
	WorldBuildings.box(walls, xf, Vector3(lx, 1.15, fz + 0.04), Vector3(1.0, 2.3, 0.08), trim.darkened(0.3))
	WorldBuildings.box(glass, xf, Vector3(lx, 1.4, fz + 0.09), Vector3(0.6, 1.1, 0.02), Color.WHITE)
	var spans := []
	if pub:
		spans = [[-w * 0.5 + 0.5, lx - 0.7], [lx + 0.7, w * 0.5 - 0.5]]
	elif lx < 0.0:
		spans = [[lx + 0.7, w * 0.5 - 0.35]]
	else:
		spans = [[-w * 0.5 + 0.35, lx - 0.7]]
	for s: Array in spans:
		var a: float = s[0]
		var b: float = s[1]
		if b - a < 0.8:
			continue
		var cx := (a + b) * 0.5
		WorldBuildings.box(glass, xf, Vector3(cx, 1.45, fz + 0.03), Vector3(b - a, 1.9, 0.06), Color.WHITE)
		WorldBuildings.box(walls, xf, Vector3(cx, 0.25, fz + 0.06), Vector3(b - a + 0.1, 0.5, 0.12), trim)
		WorldBuildings.box(walls, xf, Vector3(cx, 2.45, fz + 0.06), Vector3(b - a + 0.1, 0.1, 0.12), trim)
		if bool(p["awning"]):
			# A striped awning, sloping out over the window.
			var aw := Transform3D(xf.basis * Basis(Vector3.RIGHT, 0.38), xf * Vector3(cx, 2.62, fz + 0.62))
			var strips := maxi(3, int((b - a) / 0.5))
			for k in strips:
				var c := trim if k % 2 == 0 else Color(0.92, 0.9, 0.85)
				var sx := (b - a + 0.3) / strips
				WorldBuildings.box(walls, aw, Vector3(-(b - a + 0.3) * 0.5 + sx * (k + 0.5), 0.0, 0.0), Vector3(sx, 0.04, 1.3), c)
	# The fascia board with the name on, and a lit strip under it.
	WorldBuildings.box(walls, xf, Vector3(0.0, 2.98, fz + 0.07), Vector3(w - 0.3, 0.66, 0.14), trim)
	WorldBuildings.box(glass, xf, Vector3(0.0, 2.62, fz + 0.12), Vector3(w - 0.7, 0.05, 0.05), Color.WHITE)
	var label := Label3D.new()
	label.text = str(p["name"]).to_upper() if not pub else str(p["name"])
	label.font_size = 64
	label.pixel_size = 0.0065
	label.modulate = Color(1.0, 0.92, 0.7) if trim.get_luminance() < 0.45 else Color(0.08, 0.08, 0.08)
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.width = (w - 0.6) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.transform = Transform3D(xf.basis, xf * Vector3(0.0, 2.98, fz + 0.15))
	label.visibility_range_end = SIGN_RANGE
	add_child(label)
	if pub:
		# The hanging sign by the door.
		var sign_at := Vector3(lx + 1.5, 3.9, fz + 0.75)
		WorldBuildings.box(walls, xf, Vector3(lx + 1.5, 4.45, fz + 0.4), Vector3(0.06, 0.06, 0.8), Color(0.08, 0.08, 0.08))
		WorldBuildings.box(walls, xf, sign_at, Vector3(1.1, 0.9, 0.06), Color(0.42, 0.08, 0.06))


# ---------------------------------------------------------------------------- pavements

func _build_pavements() -> void:
	var st := _begin()
	var y0 := -0.3
	var runs := []   # [x0, x1, z0, z1, top]
	# The shed's side: raised either side of the forecourt, flush (a dropped kerb) along it.
	var nz0 := NORTH_FRONT
	var nz1 := STREET_Z - ROAD_HW
	runs.append([X_RANGE.x, FORECOURT_X.x, nz0, nz1, KERB])
	runs.append([FORECOURT_X.y, X_RANGE.y, nz0, nz1, KERB])
	# The far side, either side of Station Road's mouth.
	var sz0 := STREET_Z + ROAD_HW
	var sz1 := SOUTH_FRONT
	runs.append([X_RANGE.x, STATION_X - STATION_HW - 1.0, sz0, sz1, KERB])
	runs.append([STATION_X + STATION_HW + 1.0, X_RANGE.y, sz0, sz1, KERB])
	for r: Array in runs:
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var top: float = r[4]
		var c := Vector3((x0 + x1) * 0.5, (top + y0) * 0.5, (z0 + z1) * 0.5)
		var size := Vector3(x1 - x0, top - y0, z1 - z0)
		WorldBuildings.box(st, Transform3D(), c, size, PAVING)
		# The kerb stones along the road edge.
		var kz := z1 - 0.12 if z1 <= STREET_Z else z0 + 0.12
		WorldBuildings.box(st, Transform3D(), Vector3(c.x, top + 0.004, kz), Vector3(x1 - x0, 0.01, 0.24), STONE)
		_box_shape(c, size)
	# The paving across the front of the forecourt, flush with it, and Station Road's verges.
	WorldBuildings.box(st, Transform3D(), Vector3(0.0, 0.004, (nz0 + nz1) * 0.5), Vector3(FORECOURT_X.y - FORECOURT_X.x, 0.008, nz1 - nz0), PAVING)
	WorldBuildings.box(st, Transform3D(), Vector3(0.0, 0.009, nz1 - 0.12), Vector3(FORECOURT_X.y - FORECOURT_X.x, 0.006, 0.24), STONE)
	# Flagstone joints: a darker line across the pavements every 1.2 m.
	for r: Array in runs:
		var x: float = r[0] + 0.6
		while x < float(r[1]):
			WorldBuildings.box(st, Transform3D(), Vector3(x, float(r[4]) + 0.003, (float(r[2]) + float(r[3])) * 0.5),
				Vector3(0.03, 0.006, float(r[3]) - float(r[2]) - 0.3), PAVING.darkened(0.18))
			x += 1.2
	var mat := _mat("paving", Color.WHITE, 0.9)
	_world._wet(mat, 0.5)
	_mesh(st, "Pavements", mat, STREET_RANGE * 2.0)


# ---------------------------------------------------------------------------- road markings

func _build_markings() -> void:
	var st := _begin()
	var y := WorldRoads.YARD_LIFT + 0.016
	var white := Color(0.93, 0.93, 0.9)
	var yellow := Color(0.95, 0.78, 0.12)
	var hw := ROAD_HW
	# Zebra crossings: stripes along the road, and give-way dashes either side.
	for cx in CROSSINGS:
		var z := STREET_Z - hw + 0.25
		while z < STREET_Z + hw - 0.2:
			WorldBuildings.box(st, Transform3D(), Vector3(cx, y, z + 0.25), Vector3(3.0, 0.004, 0.5), white)
			z += 1.0
		for side: float in [-1.0, 1.0]:
			var dz := STREET_Z - hw + 0.3
			while dz < STREET_Z + hw:
				WorldBuildings.box(st, Transform3D(), Vector3(cx + side * 2.2, y, dz + 0.2), Vector3(0.15, 0.004, 0.4), white)
				dz += 0.8
	# Double yellow lines along both kerbs where there's no parking.
	for kerb_side: float in [-1.0, 1.0]:
		var bays := PARK_NORTH if kerb_side < 0.0 else PARK_SOUTH
		var x := X_RANGE.x
		while x < X_RANGE.y:
			var x1 := minf(x + 2.0, X_RANGE.y)
			var m := (x + x1) * 0.5
			var free := true
			for b: Vector2 in bays:
				free = free and not (m > b.x and m < b.y)
			for cx in CROSSINGS:
				free = free and absf(m - cx) > 1.5
			if kerb_side > 0.0 and absf(m - STATION_X) < STATION_HW + 1.0:
				free = false
			if free:
				for k in 2:
					var z := STREET_Z + kerb_side * (hw - 0.2 - k * 0.2)
					WorldBuildings.box(st, Transform3D(), Vector3(m, y, z), Vector3(x1 - x, 0.004, 0.1), yellow)
			x = x1
	# Parking bays: a white tick between each.
	for kerb_side: float in [-1.0, 1.0]:
		for b: Vector2 in (PARK_NORTH if kerb_side < 0.0 else PARK_SOUTH):
			var x := b.x
			while x <= b.y:
				WorldBuildings.box(st, Transform3D(), Vector3(x, y, STREET_Z + kerb_side * (hw - 1.0)), Vector3(0.1, 0.004, 2.0), white)
				x += 6.0
	# The bus stop's box on the road, and Station Road's give-way lines at the mouth.
	var bx0 := BUS_STOP.x - 9.0
	var bx1 := BUS_STOP.x + 9.0
	var bz0 := STREET_Z + hw - 2.6
	var bz1 := STREET_Z + hw - 0.1
	WorldBuildings.box(st, Transform3D(), Vector3(BUS_STOP.x, y, bz0), Vector3(bx1 - bx0, 0.004, 0.15), yellow)
	WorldBuildings.box(st, Transform3D(), Vector3(bx0, y, (bz0 + bz1) * 0.5), Vector3(0.15, 0.004, bz1 - bz0), yellow)
	WorldBuildings.box(st, Transform3D(), Vector3(bx1, y, (bz0 + bz1) * 0.5), Vector3(0.15, 0.004, bz1 - bz0), yellow)
	var bus := Label3D.new()
	bus.text = "BUS STOP"
	bus.font_size = 140
	bus.pixel_size = 0.01
	bus.modulate = yellow
	bus.outline_size = 0
	bus.double_sided = false
	bus.position = Vector3(BUS_STOP.x, y + 0.006, (bz0 + bz1) * 0.5)
	bus.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	bus.visibility_range_end = SIGN_RANGE
	add_child(bus)
	var gx := STATION_X - STATION_HW + 0.3
	while gx < STATION_X + STATION_HW - 0.2:
		WorldBuildings.box(st, Transform3D(), Vector3(gx + 0.3, y, STREET_Z + hw + 1.2), Vector3(0.6, 0.004, 0.25), white)
		gx += 1.0
	var mat := _mat("town_paint", Color.WHITE, 0.6)
	_world._wet(mat, 0.6)
	_mesh(st, "Markings", mat, STREET_RANGE, false)


# ---------------------------------------------------------------------------- street furniture

## Lamp posts, trees, benches, bins, bollards, beacons, the post box and phone box, the bus
## shelter, the yard signs and gate posts, and the parked cars: one merged mesh, plus the lamp
## heads and lit panels in another (they glow at night), and the beacons' globes (they blink).
func _build_furniture() -> void:
	var st := _begin()
	var glow := _begin()
	var beacons := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var pole := Color(0.18, 0.2, 0.22)
	# Street lamps every 26 m, on alternate sides, at the kerb, their arms out over the road.
	var x := X_RANGE.x + 6.0
	var k := 0
	while x < X_RANGE.y - 2.0:
		var side := -1.0 if k % 2 == 0 else 1.0
		var ok := not (side < 0.0 and x > FORECOURT_X.x - 1.0 and x < FORECOURT_X.y + 1.0)
		ok = ok and not (side > 0.0 and absf(x - STATION_X) < STATION_HW + 2.0)
		for cx in CROSSINGS:
			ok = ok and absf(x - cx) > 2.5
		ok = ok and not (side > 0.0 and x > SHELTER_X.x - 1.5 and x < SHELTER_X.y + 1.5)
		if ok:
			var at := Vector3(x, KERB, STREET_Z + side * (ROAD_HW + 0.45))
			_lamp(st, glow, at, -side)
		x += 13.0
		k += 1
	# Street trees on the kerb between the lamps, in iron grilles.
	x = X_RANGE.x + 12.5
	k = 0
	while x < X_RANGE.y - 4.0:
		var side := 1.0 if k % 2 == 0 else -1.0
		var ok := not (side < 0.0 and x > FORECOURT_X.x - 2.0 and x < FORECOURT_X.y + 2.0)
		ok = ok and not (side > 0.0 and absf(x - STATION_X) < STATION_HW + 3.0)
		for cx in CROSSINGS:
			ok = ok and absf(x - cx) > 3.5
		ok = ok and not (side > 0.0 and x > SHELTER_X.x - 4.0 and x < SHELTER_X.y + 4.0)
		if ok:
			_tree(st, Vector3(x, KERB, STREET_Z + side * (ROAD_HW + 0.7)), rng.randi(), rng.randf_range(0.75, 0.95))
		x += 26.0
		k += 1
	# Bigger trees in the gardens behind the far side, and behind the houses on the shed's side.
	for i in 14:
		var gx := rng.randf_range(X_RANGE.x + 5.0, X_RANGE.y - 5.0)
		var gz := rng.randf_range(SOUTH_FRONT + 11.0, SOUTH_FRONT + 22.0) if i % 3 != 0 else rng.randf_range(62.0, 74.0)
		if i % 3 == 0 and gx > FORECOURT_X.x - 4.0 and gx < FORECOURT_X.y + 4.0:
			continue
		var at := Vector3(gx, 0.0, gz)
		if not building_at(at, 2.5).is_empty() or _near_road(at, 6.0):
			continue
		_tree(st, at, rng.randi(), rng.randf_range(1.1, 1.5))
	# The crossings: belisha beacons either side, on black and white poles.
	for cx in CROSSINGS:
		for side: float in [-1.0, 1.0]:
			var at := Vector3(cx - 1.9, KERB, STREET_Z + side * (ROAD_HW + 0.4))
			for s in 6:
				WorldBuildings.cylinder(st, Transform3D(Basis(), at + Vector3.UP * (s * 0.42)), 0.055, 0.055, 0.42, 8,
					Color(0.05, 0.05, 0.05) if s % 2 == 0 else Color(0.92, 0.92, 0.9), s == 5)
			WorldBuildings.blob(beacons, at + Vector3.UP * 2.75, Vector3.ONE * 0.2, 3, 0.02)
			_post_shape(at, 0.08, 2.6)
	# Benches and bins.
	for b: Array in [[Vector3(-68.0, KERB, NORTH_FRONT + 0.55), 0.0], [Vector3(46.5, KERB, SOUTH_FRONT - 0.55), PI],
			[Vector3(-90.0, KERB, SOUTH_FRONT - 0.55), PI], [Vector3(84.0, KERB, NORTH_FRONT + 0.55), 0.0]]:
		_bench(st, b[0], b[1])
	for at: Vector3 in [Vector3(-65.5, KERB, NORTH_FRONT + 0.45), Vector3(48.8, KERB, SOUTH_FRONT - 0.45),
			Vector3(SHELTER_X.y + 0.8, KERB, SOUTH_FRONT - 0.45), Vector3(-30.0, KERB, SOUTH_FRONT - 0.45),
			Vector3(81.5, KERB, NORTH_FRONT + 0.45), Vector3(-92.5, KERB, SOUTH_FRONT - 0.45), Vector3(-100.0, KERB, NORTH_FRONT + 0.45)]:
		_bin(st, at)
	# Bollards guarding the crossings' kerbs.
	for cx in CROSSINGS:
		for side: float in [-1.0, 1.0]:
			for dx: float in [1.9, 2.9]:
				var at := Vector3(cx + dx, KERB, STREET_Z + side * (ROAD_HW + 0.35))
				WorldBuildings.cylinder(st, Transform3D(Basis(), at), 0.1, 0.09, 0.9, 8, Color(0.08, 0.08, 0.09), true)
				WorldBuildings.box(st, Transform3D(), at + Vector3.UP * 0.75, Vector3(0.2, 0.06, 0.2), Color(0.85, 0.7, 0.2))
				_post_shape(at, 0.1, 0.9)
	# A post box and a phone box.
	var post := Vector3(-74.0, KERB, NORTH_FRONT + 0.5)
	WorldBuildings.cylinder(st, Transform3D(Basis(), post), 0.3, 0.3, 1.45, 12, Color(0.75, 0.06, 0.05), false)
	WorldBuildings.cylinder(st, Transform3D(Basis(), post + Vector3.UP * 1.45), 0.33, 0.12, 0.16, 12, Color(0.75, 0.06, 0.05), true)
	WorldBuildings.box(st, Transform3D(), post + Vector3(0.0, 1.15, 0.29), Vector3(0.3, 0.05, 0.04), Color(0.05, 0.05, 0.05))
	_post_shape(post, 0.32, 1.6)
	var phone := Vector3(90.0, KERB, SOUTH_FRONT - 0.65)
	var red := Color(0.72, 0.06, 0.05)
	WorldBuildings.box(st, Transform3D(), phone + Vector3(0.0, 1.25, 0.0), Vector3(0.95, 2.5, 0.95), red)
	WorldBuildings.box(st, Transform3D(), phone + Vector3(0.0, 2.6, 0.0), Vector3(1.05, 0.2, 1.05), red)
	for f: Vector3 in [Vector3(0.0, 0.0, -0.49), Vector3(0.49, 0.0, 0.0), Vector3(-0.49, 0.0, 0.0)]:
		var size := Vector3(0.7, 1.6, 0.02) if f.z != 0.0 else Vector3(0.02, 1.6, 0.7)
		WorldBuildings.box(glow, Transform3D(), phone + Vector3(0.0, 1.35, 0.0) + f, size, Color.WHITE)
	_box_shape(phone + Vector3.UP * 1.3, Vector3(1.0, 2.6, 1.0))
	_bus_shelter(st, glow)
	_yard_way(st)
	_parked_cars(st, rng)
	var mat := _mat("street", Color.WHITE, 0.7)
	_mesh(st, "StreetFurniture", mat, STREET_RANGE)
	_mesh(glow, "LampHeads", _glow_mat("lamp_heads", Color(0.9, 0.88, 0.8), Color(1.0, 0.82, 0.55), 5.0), WINDOW_RANGE, false, 5.0)
	_beacon_mat = _glow_mat("beacons", Color(1.0, 0.6, 0.1), Color(1.0, 0.55, 0.1), 0.0)
	_beacon_mat.emission_energy_multiplier = 3.5
	_mesh(beacons, "Beacons", _beacon_mat, STREET_RANGE, false)


func _near_road(at: Vector3, gap: float) -> bool:
	var near := _world.roads.nearest(at.x, at.z, 20.0 + gap)
	return not near.is_empty() and float(near["d"]) < float(_world.roads.roads[int(near["road"])]["hw"]) + gap


## A lamp post at `at` with its arm reaching `toward` the road (+1 toward +Z).
func _lamp(st: SurfaceTool, glow: SurfaceTool, at: Vector3, toward: float) -> void:
	var pole := Color(0.18, 0.2, 0.22)
	WorldBuildings.cylinder(st, Transform3D(Basis(), at), 0.09, 0.06, 6.4, 8, pole, true)
	WorldBuildings.cylinder(st, Transform3D(Basis(), at), 0.14, 0.12, 0.6, 8, pole, false)
	WorldBuildings.box(st, Transform3D(), at + Vector3(0.0, 6.3, toward * 0.6), Vector3(0.08, 0.08, 1.3), pole)
	WorldBuildings.box(st, Transform3D(), at + Vector3(0.0, 6.28, toward * 1.25), Vector3(0.32, 0.14, 0.6), pole)
	WorldBuildings.box(glow, Transform3D(), at + Vector3(0.0, 6.19, toward * 1.25), Vector3(0.26, 0.04, 0.5), Color.WHITE)
	_post_shape(at, 0.12, 6.4)


func _tree(st: SurfaceTool, at: Vector3, seed_value: int, scale: float) -> void:
	WorldBuildings.box(st, Transform3D(), at + Vector3.UP * 0.006, Vector3(1.1, 0.012, 1.1), Color(0.12, 0.12, 0.12))
	WorldBuildings.cylinder(st, Transform3D(Basis(), at), 0.16 * scale, 0.11 * scale, 3.4 * scale, 7, Color(0.33, 0.25, 0.18), false)
	var green := Color(0.24, 0.38, 0.14).lerp(Color(0.34, 0.45, 0.17), float(seed_value % 100) / 100.0)
	var crown := _begin()
	WorldBuildings.blob(crown, at + Vector3(0.0, 4.4, 0.0) * scale, Vector3(1.9, 1.7, 1.9) * scale, seed_value % 50)
	WorldBuildings.blob(crown, at + Vector3(0.6, 5.3, 0.3) * scale, Vector3(1.3, 1.2, 1.3) * scale, seed_value % 50 + 1)
	# The blobs are white; tint them into the shared mesh.
	var arrays := crown.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		st.set_color(green.darkened(0.15 * (1.0 - norms[i].y)))
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
	_post_shape(at, 0.2 * scale, 3.0)


## A bench at `at` (its seat's front facing local +Z turned by `yaw`).
func _bench(st: SurfaceTool, at: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var wood := Color(0.42, 0.28, 0.16)
	var iron := Color(0.1, 0.1, 0.11)
	for sx: float in [-0.75, 0.75]:
		WorldBuildings.box(st, xf, Vector3(sx, 0.22, 0.0), Vector3(0.06, 0.44, 0.5), iron)
		WorldBuildings.box(st, xf, Vector3(sx, 0.62, -0.22), Vector3(0.06, 0.45, 0.06), iron)
	WorldBuildings.box(st, xf, Vector3(0.0, 0.45, 0.02), Vector3(1.7, 0.05, 0.45), wood)
	WorldBuildings.box(st, xf, Vector3(0.0, 0.72, -0.22), Vector3(1.7, 0.22, 0.04), wood)
	_box_shape(at + Vector3.UP * 0.4, Vector3(1.7, 0.8, 0.5), yaw)


func _bin(st: SurfaceTool, at: Vector3) -> void:
	WorldBuildings.cylinder(st, Transform3D(Basis(), at), 0.24, 0.27, 0.9, 10, Color(0.08, 0.08, 0.08), true)
	WorldBuildings.cylinder(st, Transform3D(Basis(), at + Vector3.UP * 0.7), 0.275, 0.275, 0.06, 10, Color(0.75, 0.6, 0.2), false)
	_post_shape(at, 0.27, 0.95)


func _bus_shelter(st: SurfaceTool, glow: SurfaceTool) -> void:
	var z1 := SOUTH_FRONT - 0.15
	var z0 := SOUTH_FRONT - 1.05
	var frame := Color(0.15, 0.2, 0.26)
	var y := KERB
	for x: float in [SHELTER_X.x, SHELTER_X.y]:
		for z: float in [z0 + 0.05, z1 - 0.05]:
			WorldBuildings.box(st, Transform3D(), Vector3(x, y + 1.25, z), Vector3(0.07, 2.5, 0.07), frame)
	WorldBuildings.box(st, Transform3D(), Vector3((SHELTER_X.x + SHELTER_X.y) * 0.5, y + 2.52, (z0 + z1) * 0.5),
		Vector3(SHELTER_X.y - SHELTER_X.x + 0.3, 0.08, z1 - z0 + 0.3), frame)
	WorldBuildings.box(st, Transform3D(), Vector3((SHELTER_X.x + SHELTER_X.y) * 0.5, y + 0.48, z1 - 0.25),
		Vector3(SHELTER_X.y - SHELTER_X.x - 0.6, 0.05, 0.3), Color(0.5, 0.52, 0.55))
	# The lit advert panel at one end, and the stop's flag on its pole by the kerb.
	WorldBuildings.box(glow, Transform3D(), Vector3(SHELTER_X.x + 0.02, y + 1.35, (z0 + z1) * 0.5), Vector3(0.05, 1.6, z1 - z0 - 0.15), Color.WHITE)
	_box_shape(Vector3((SHELTER_X.x + SHELTER_X.y) * 0.5, y + 1.3, (z0 + z1) * 0.5), Vector3(SHELTER_X.y - SHELTER_X.x, 2.6, z1 - z0))
	var flag := Vector3(SHELTER_X.y + 2.2, y, STREET_Z + ROAD_HW + 0.4)
	WorldBuildings.cylinder(st, Transform3D(Basis(), flag), 0.05, 0.05, 2.9, 8, Color(0.6, 0.6, 0.6), true)
	WorldBuildings.cylinder(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), flag + Vector3(0.0, 2.75, -0.03)), 0.3, 0.3, 0.04, 16,
		Color(0.85, 0.1, 0.08), true)
	WorldBuildings.box(st, Transform3D(), flag + Vector3(0.0, 2.75, 0.0), Vector3(0.5, 0.12, 0.07), Color(0.95, 0.95, 0.95))
	_post_shape(flag, 0.06, 2.9)
	var l := Label3D.new()
	l.text = "Kettle Bridge\nAshby"
	l.font_size = 32
	l.pixel_size = 0.005
	l.modulate = Color(0.08, 0.08, 0.1)
	l.outline_size = 0
	l.position = flag + Vector3(0.0, 2.3, -0.05)
	l.rotation.y = PI
	l.visibility_range_end = SIGN_RANGE * 0.5
	add_child(l)


## Brick gate posts at the lanes up to the yard, a sign at each, and the street name on walls.
func _yard_way(st: SurfaceTool) -> void:
	for lane: Rect2 in WorldYard.LANES:
		for x: float in [lane.position.x + 0.3, lane.end.x - 0.3]:
			var at := Vector3(x, 0.0, lane.end.y)
			WorldBuildings.box(st, Transform3D(), at + Vector3.UP * 0.9, Vector3(0.5, 1.8, 0.5), WorldBuildings.BRICK)
			WorldBuildings.box(st, Transform3D(), at + Vector3.UP * 1.84, Vector3(0.6, 0.08, 0.6), STONE)
			_box_shape(at + Vector3.UP * 0.9, Vector3(0.5, 1.8, 0.5))
		var sx := lane.position.x + 0.3 if lane.position.x > 0.0 else lane.end.x - 0.3
		var sign_at := Vector3(sx, 2.25, lane.end.y + 0.27)
		WorldBuildings.box(st, Transform3D(), sign_at, Vector3(1.6, 0.6, 0.04), Color(0.1, 0.24, 0.16))
		WorldBuildings.box(st, Transform3D(), Vector3(sx, 2.0, lane.end.y), Vector3(0.06, 0.4, 0.06), Color(0.15, 0.15, 0.15))
		var l := Label3D.new()
		l.text = "YARD & TEST AREA"
		l.font_size = 30
		l.pixel_size = 0.006
		l.modulate = Color(0.95, 0.92, 0.8)
		l.outline_size = 0
		l.position = sign_at + Vector3(0.0, 0.0, 0.03)
		l.visibility_range_end = SIGN_RANGE
		add_child(l)
	for at: Vector3 in [Vector3(-46.0, 3.2, NORTH_FRONT + 0.02), Vector3(66.5, 3.2, SOUTH_FRONT - 0.02)]:
		var plate := Label3D.new()
		plate.text = "HIGH STREET"
		plate.font_size = 34
		plate.pixel_size = 0.006
		plate.modulate = Color(0.05, 0.05, 0.05)
		plate.outline_modulate = Color(0.95, 0.95, 0.95)
		plate.outline_size = 14
		plate.position = at
		plate.rotation.y = 0.0 if at.z < STREET_Z else PI
		plate.visibility_range_end = SIGN_RANGE * 0.6
		add_child(plate)


## Cars parked along the kerbs in the bays, nose to the way traffic goes on that side.
func _parked_cars(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for kerb_side: float in [-1.0, 1.0]:
		for b: Vector2 in (PARK_NORTH if kerb_side < 0.0 else PARK_SOUTH):
			var x := b.x + 3.0
			while x < b.y - 1.0:
				if rng.randf() < 0.6:
					var at := Vector3(x + rng.randf_range(-0.3, 0.3), WorldRoads.YARD_LIFT, STREET_Z + kerb_side * (ROAD_HW - 1.0))
					# On the far side they face -X (the way that side's traffic goes), here +X.
					var yaw := PI * 0.5 if kerb_side > 0.0 else -PI * 0.5
					_car(st, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.03, 0.03)), at), CARS[rng.randi() % CARS.size()],
						rng.randf() < 0.3)
				x += 6.0


## A small low-poly car (forward -Z): body, cabin and glass, wheels, lights. `hatch` for a short one.
func _car(st: SurfaceTool, xf: Transform3D, body: Color, hatch: bool) -> void:
	var l := 3.9 if hatch else 4.4
	var glass := Color(0.1, 0.13, 0.16)
	WorldBuildings.box(st, xf, Vector3(0.0, 0.62, 0.0), Vector3(1.74, 0.62, l), body)
	var cab_l := l * (0.55 if hatch else 0.48)
	var cab_z := 0.25 if hatch else 0.2
	WorldBuildings.box(st, xf, Vector3(0.0, 1.17, cab_z), Vector3(1.56, 0.5, cab_l), body)
	WorldBuildings.box(st, xf, Vector3(0.0, 1.17, cab_z), Vector3(1.6, 0.36, cab_l - 0.3), glass)
	WorldBuildings.box(st, xf, Vector3(0.0, 1.15, cab_z - cab_l * 0.5 - 0.01), Vector3(1.4, 0.36, 0.04), glass)
	WorldBuildings.box(st, xf, Vector3(0.0, 1.15, cab_z + cab_l * 0.5 + 0.01), Vector3(1.4, 0.32, 0.04), glass)
	for z: float in [-l * 0.5 + 0.02, l * 0.5 - 0.02]:
		WorldBuildings.box(st, xf, Vector3(0.0, 0.4, z), Vector3(1.76, 0.18, 0.06), Color(0.12, 0.12, 0.12))
		for sx: float in [-0.62, 0.62]:
			WorldBuildings.box(st, xf, Vector3(sx, 0.75, z), Vector3(0.32, 0.14, 0.04),
				Color(0.95, 0.95, 0.9) if z < 0.0 else Color(0.7, 0.05, 0.05))
	for wz: float in [-l * 0.5 + 0.8, l * 0.5 - 0.75]:
		for sx: float in [-0.8, 0.8]:
			var wxf := xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx - 0.1, 0.32, wz))
			WorldBuildings.cylinder(st, wxf, 0.32, 0.32, 0.2, 10, Color(0.06, 0.06, 0.06), true)
	_box_shape(xf.origin + Vector3.UP * 0.75, Vector3(1.8, 1.5, l), xf.basis.get_euler().y)


# ---------------------------------------------------------------------------- lights

## Three real lamps along the street by the shed (shadowless, at night only); every other lamp
## just glows.
func _build_lights() -> void:
	for x: float in [-32.0, 6.0, 44.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 6.0, STREET_Z)
		light.omni_range = 17.0
		light.omni_attenuation = 1.2
		light.light_color = Color(1.0, 0.82, 0.58)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 140.0
		light.distance_fade_length = 40.0
		light.visible = false
		light.set_meta("night_energy", 1.8)
		light.add_to_group(Daylight.NIGHT_LIGHTS)
		add_child(light)
