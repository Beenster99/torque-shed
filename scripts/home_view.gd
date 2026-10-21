class_name HomesView
extends Node3D
## The crew's houses on the riding map (see HomePlots and Collection): for every player with a
## house in this shed, a big house in their style (Victorian brick, modern render, Georgian stone
## or a stone farmhouse) with a block of four garages, a low wall along the front with the gate,
## and a large pea shingle courtyard in front (gravel underfoot and under the tyres) with the
## player's collection on show in a ring in the middle of it (HomeDisplay).
##
## Kept cheap to draw: each house is a handful of merged, vertex-coloured meshes made once
## (walls, roofs, the windows that light up at night, the courtyard) drawn to HOUSE_RANGE, and
## one static body with its shapes added straight to the physics server. The bikes on show are
## only drawn as themselves (baked models, one at a time) when you're close (see HomeDisplay).

## A collection's stand was used ({interact}): main opens its card (HomePanel).
signal stand_used(cid: int)

const HOUSE_RANGE := 900.0
const WINDOW_RANGE := 600.0
const GRAVEL := Color(0.66, 0.61, 0.52)
const PAVING := Color(0.74, 0.72, 0.68)

## What each style is made of: walls, trim (sills, quoins, lintels), roof, front door, garage
## doors, the boundary wall.
const LOOKS := {
	"victorian": {"wall": Color(0.55, 0.27, 0.2), "trim": Color(0.92, 0.9, 0.84), "roof": Color(0.25, 0.26, 0.3),
		"door": Color(0.1, 0.25, 0.16), "garage": Color(0.1, 0.25, 0.16), "boundary": Color(0.5, 0.25, 0.19)},
	"modern": {"wall": Color(0.93, 0.93, 0.91), "trim": Color(0.55, 0.38, 0.22), "roof": Color(0.22, 0.23, 0.25),
		"door": Color(0.18, 0.19, 0.21), "garage": Color(0.2, 0.21, 0.23), "boundary": Color(0.85, 0.85, 0.83)},
	"georgian": {"wall": Color(0.8, 0.71, 0.55), "trim": Color(0.92, 0.89, 0.8), "roof": Color(0.3, 0.3, 0.33),
		"door": Color(0.06, 0.06, 0.07), "garage": Color(0.9, 0.9, 0.86), "boundary": Color(0.74, 0.66, 0.5)},
	"farmhouse": {"wall": Color(0.9, 0.88, 0.82), "trim": Color(0.42, 0.4, 0.36), "roof": Color(0.5, 0.28, 0.2),
		"door": Color(0.42, 0.28, 0.14), "garage": Color(0.4, 0.27, 0.14), "boundary": Color(0.55, 0.53, 0.48)},
}

var _world: World
## plot -> {node, sig, display}
var houses := {}
var _mats := {}


func build(world: World) -> void:
	_world = world
	Shed.homes_changed.connect(sync)
	sync()


## Puts up the house of everyone with one, and takes down any whose owner has moved out; the
## displays catch up with their collections.
func sync() -> void:
	var want := {}
	for who in Collection.players():
		var plot := Collection.plot_of(str(who))
		if plot >= 0 and plot < HomePlots.PLOTS.size():
			want[plot] = "%s|%s" % [str(who), Collection.style_of(str(who))]
	for plot in houses.keys():
		if not want.has(plot) or str(houses[plot]["sig"]) != str(want[plot]):
			(houses[plot]["node"] as Node).queue_free()
			houses.erase(plot)
	for plot in want:
		if not houses.has(plot):
			var parts := str(want[plot]).split("|")
			houses[plot] = _build_house(int(plot), parts[0], parts[1])
			houses[plot]["sig"] = want[plot]
	for plot in houses:
		(houses[plot]["display"] as HomeDisplay).sync()


## The display at plot `plot`'s house, or null.
func display(plot: int) -> HomeDisplay:
	return houses[plot]["display"] if houses.has(plot) else null


# ---------------------------------------------------------------------------- building a house

func _mat(key: String, rough := 0.85) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	_mats[key] = m
	return m


## The pea shingle: small rounded stones, a cellular noise in their sandy greys, with a little
## bump to it.
func _gravel_mat() -> StandardMaterial3D:
	if _mats.has("gravel"):
		return _mats["gravel"]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.09
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_ADD
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.42, 0.38, 0.32))
	ramp.set_color(1, Color(0.86, 0.82, 0.74))
	tex.color_ramp = ramp
	var bump := NoiseTexture2D.new()
	bump.width = 256
	bump.height = 256
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 6.0
	bump.noise = noise
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = GRAVEL.lightened(0.2)
	m.normal_enabled = true
	m.normal_texture = bump
	m.roughness = 0.95
	m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_mats["gravel"] = m
	return m


func _glow(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.18, 0.22)
	m.metallic = 0.3
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = Color(1.0, 0.76, 0.46)
	m.emission_energy_multiplier = 0.05
	_mats[key] = m
	return m


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _mesh(parent: Node3D, st: SurfaceTool, node_name: String, mat: Material, reach: float, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if _world:
		_world.ranged(mi, reach)
	else:
		mi.visibility_range_end = reach
	return mi


## A house, its garages, the wall and the courtyard on `plot`, for `who` in `style`.
func _build_house(plot: int, who: String, style: String) -> Dictionary:
	var node := Node3D.new()
	node.name = "House%d" % plot
	node.transform = HomePlots.frame(plot)
	add_child(node)
	var look: Dictionary = LOOKS.get(style, LOOKS["victorian"])
	var walls := _begin()
	var roofs := _begin()
	var windows := _begin()
	var ground := _begin()
	var shapes := []
	match style:
		"modern":
			_modern(walls, roofs, windows, look)
		"georgian":
			_georgian(walls, roofs, windows, look)
		"farmhouse":
			_farmhouse(walls, roofs, windows, look)
		_:
			_victorian(walls, roofs, windows, look)
	_garages(walls, roofs, windows, look, style)
	shapes.append([HomePlots.HOUSE, HomePlots.HOUSE_WALL])
	shapes.append([HomePlots.GARAGE, HomePlots.GARAGE_WALL])
	_boundary(walls, look, shapes)
	_courtyard(ground)
	_mesh(node, walls, "Walls", _mat("walls", 0.9), HOUSE_RANGE)
	_mesh(node, roofs, "Roofs", _mat("roofs", 0.8), HOUSE_RANGE)
	var win := _mesh(node, windows, "Windows", _glow("windows%d" % plot), WINDOW_RANGE, false)
	win.set_meta("night_emission", 0.45)
	win.add_to_group(Daylight.NIGHT_LIGHTS)
	_mesh(node, ground, "Paving", _mat("paving", 0.9), HOUSE_RANGE * 0.5, false)
	_gravel(node)
	# The solid parts: the house, the garages and the walls.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	for s in shapes:
		var r: Rect2 = s[0]
		var h: float = s[1]
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, h + 1.0, r.size.y)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = Vector3(r.get_center().x, h * 0.5 - 0.5, r.get_center().y)
		body.add_child(cs)
	# Their name on the gate pillar, facing the road.
	var sign := Label3D.new()
	sign.name = "NameBoard"
	sign.text = "%s\n%s" % [who.to_upper(), str(HomePlots.STYLE_NAMES.get(style, "House")).to_upper()]
	sign.font_size = 44
	sign.pixel_size = 0.006
	sign.outline_size = 8
	sign.modulate = Color(0.95, 0.92, 0.85)
	sign.outline_modulate = Color(0.05, 0.05, 0.06, 0.8)
	sign.position = Vector3(HomePlots.GATE_X.y + 0.9, 1.75, HomePlots.COURTYARD.end.y + 0.32)
	sign.visibility_range_end = 60.0
	node.add_child(sign)
	var disp := HomeDisplay.new()
	disp.name = "Display"
	disp.plot = plot
	disp.homes = self
	node.add_child(disp)
	return {"node": node, "display": disp, "plot": plot, "style": style, "owner": who}


## The pea shingle courtyard and the drive out to the road: a slab you walk and ride on (its
## surface "gravel": crunching underfoot, looser under the tyres).
func _gravel(node: Node3D) -> void:
	var c := HomePlots.COURTYARD
	var st := _begin()
	var drive := Rect2(HomePlots.GATE_X.x, c.end.y, HomePlots.GATE_X.y - HomePlots.GATE_X.x, HomePlots.DRIVE_TO - c.end.y)
	for r: Rect2 in [c, drive]:
		var y0 := 0.0
		var y1 := 0.0 if r == c else -HomePlots.GRAVEL_LIFT
		var pts := [Vector3(r.position.x, y0, r.position.y), Vector3(r.end.x, y0, r.position.y), Vector3(r.end.x, y1, r.end.y),
			Vector3(r.position.x, y1, r.end.y)]
		for v in [[0, 1, 2], [0, 2, 3]]:
			for k in v:
				var p: Vector3 = pts[k]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(p.x, p.z) * 0.45)
				st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.name = "Gravel"
	mi.mesh = st.commit()
	mi.material_override = _gravel_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if _world:
		_world.ranged(mi, HOUSE_RANGE * 0.5)
		_world.wet_surfaces.append({"mat": mi.material_override, "color": (mi.material_override as StandardMaterial3D).albedo_color,
			"rough": 0.95, "shine": 0.3})
	var body := StaticBody3D.new()
	body.name = "Gravel"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "gravel")
	node.add_child(body)
	for r: Rect2 in [c, drive]:
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 0.6, r.size.y)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = Vector3(r.get_center().x, -0.3 - (0.0 if r == c else HomePlots.GRAVEL_LIFT * 0.5), r.get_center().y)
		body.add_child(cs)


## The display ring's paving and the round bed in the middle of it.
func _courtyard(st: SurfaceTool) -> void:
	var n := 48
	var r0 := HomePlots.RING_R - HomePlots.STAND_IN - 0.9
	var r1 := HomePlots.RING_R + 1.4
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := func(a: float, r: float) -> Vector3: return Vector3(sin(a) * r, 0.015, cos(a) * r)
		WorldBuildings.face(st, [p.call(a0, r0), p.call(a1, r0), p.call(a1, r1), p.call(a0, r1)], Vector3.UP,
			PAVING if i % 2 == 0 else PAVING.darkened(0.04))
	# A kerb round the bed, the soil and a clipped bush.
	WorldBuildings.cylinder(st, Transform3D(Basis(), Vector3(0.0, -0.05, 0.0)), 1.7, 1.7, 0.4, 20, PAVING.darkened(0.15), true)
	WorldBuildings.cylinder(st, Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)), 1.5, 1.5, 0.06, 20, Color(0.25, 0.18, 0.12), true)
	WorldBuildings.cylinder(st, Transform3D(Basis(), Vector3(0.0, 0.33, 0.0)), 1.1, 0.0, 1.6, 10, Color(0.2, 0.35, 0.14), false)


## The low wall round the courtyard's front and sides, with the gate's pillars.
func _boundary(st: SurfaceTool, look: Dictionary, shapes: Array) -> void:
	var c := HomePlots.COURTYARD
	var col: Color = look["boundary"]
	var cap: Color = (look["trim"] as Color)
	var runs := [Rect2(c.position.x, c.end.y, HomePlots.GATE_X.x - c.position.x, 0.4),
		Rect2(HomePlots.GATE_X.y, c.end.y, c.end.x - HomePlots.GATE_X.y, 0.4),
		Rect2(c.position.x - 0.4, c.position.y, 0.4, c.size.y + 0.4), Rect2(c.end.x, c.position.y, 0.4, c.size.y + 0.4)]
	# Down well below the courtyard: where a road runs close by, the land at the edge drops away.
	for r: Rect2 in runs:
		WorldBuildings.box(st, Transform3D(), Vector3(r.get_center().x, -0.35, r.get_center().y), Vector3(r.size.x, 2.5, r.size.y), col)
		WorldBuildings.box(st, Transform3D(), Vector3(r.get_center().x, 0.93, r.get_center().y), Vector3(r.size.x + 0.08, 0.08, r.size.y + 0.12), cap)
		shapes.append([r, 0.9])
	for x: float in [HomePlots.GATE_X.x - 0.3, HomePlots.GATE_X.y + 0.3]:
		WorldBuildings.box(st, Transform3D(), Vector3(x, 0.0, c.end.y + 0.2), Vector3(0.6, 3.2, 0.6), col.darkened(0.08))
		WorldBuildings.box(st, Transform3D(), Vector3(x, 1.65, c.end.y + 0.2), Vector3(0.7, 0.12, 0.7), cap)
	# The name board on the pillar by the gate.
	WorldBuildings.box(st, Transform3D(), Vector3(HomePlots.GATE_X.y + 0.9, 1.75, c.end.y + 0.26), Vector3(1.6, 0.6, 0.06), Color(0.08, 0.1, 0.09))


## A front door with its step, on the house's front (z = HOUSE.end.y) at `x`.
static func _door(st: SurfaceTool, x: float, door: Color, trim: Color, wide := 1.0) -> void:
	var fz := HomePlots.HOUSE.end.y
	WorldBuildings.box(st, Transform3D(), Vector3(x, 1.1, fz + 0.04), Vector3(wide, 2.2, 0.08), door)
	WorldBuildings.box(st, Transform3D(), Vector3(x, 2.3, fz + 0.06), Vector3(wide + 0.3, 0.14, 0.16), trim)
	WorldBuildings.box(st, Transform3D(), Vector3(x, 0.08, fz + 0.4), Vector3(wide + 0.6, 0.16, 0.7), trim.darkened(0.1))


## A window on the front (or the back, `back`) at x, y: the glass and its sill and head in `trim`.
static func _window(walls: SurfaceTool, windows: SurfaceTool, x: float, y: float, size: Vector2, trim: Color, back := false) -> void:
	var fz := HomePlots.HOUSE.end.y if not back else HomePlots.HOUSE.position.y
	var s := 1.0 if not back else -1.0
	WorldBuildings.box(windows, Transform3D(), Vector3(x, y, fz + 0.03 * s), Vector3(size.x, size.y, 0.06), Color.WHITE)
	WorldBuildings.box(walls, Transform3D(), Vector3(x, y - size.y * 0.5 - 0.06, fz + 0.07 * s), Vector3(size.x + 0.2, 0.1, 0.16), trim)
	WorldBuildings.box(walls, Transform3D(), Vector3(x, y + size.y * 0.5 + 0.06, fz + 0.05 * s), Vector3(size.x + 0.12, 0.12, 0.1), trim)


## The main block's walls (sunk a little into the ground), its middle and size.
static func _block(st: SurfaceTool, r: Rect2, h: float, col: Color) -> void:
	WorldBuildings.box(st, Transform3D(), Vector3(r.get_center().x, (h - 0.5) * 0.5, r.get_center().y), Vector3(r.size.x, h + 0.5, r.size.y), col)


## A Victorian villa: red brick, a steep slate roof, a two-storey bay under its own gable on the
## left, white sills and heads, tall chimneys.
func _victorian(walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, look: Dictionary) -> void:
	var r := HomePlots.HOUSE
	var h := HomePlots.HOUSE_WALL
	var wall: Color = look["wall"]
	var trim: Color = look["trim"]
	_block(walls, r, h, wall)
	WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(r.get_center().x, h, r.get_center().y), r.size.x * 0.5 + 0.3,
		r.size.y * 0.5 + 0.4, 4.4, false, look["roof"], wall)
	# The bay: out from the front on the left, with its own steep gable.
	var bay := Rect2(r.position.x + 1.0, r.end.y - 0.2, 5.0, 1.6)
	_block(walls, bay, h - 0.3, wall)
	WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(bay.get_center().x, h - 0.3, r.end.y - 1.0), 2.8, 2.4, 2.6, true, look["roof"], wall)
	for y: float in [1.6, 4.4]:
		WorldBuildings.box(windows, Transform3D(), Vector3(bay.get_center().x, y, bay.end.y + 0.03), Vector3(2.6, 1.6, 0.06), Color.WHITE)
		WorldBuildings.box(walls, Transform3D(), Vector3(bay.get_center().x, y - 0.88, bay.end.y + 0.08), Vector3(3.0, 0.12, 0.18), trim)
	for x: float in [r.position.x + 9.0, r.position.x + 12.5, r.position.x + 16.0]:
		_window(walls, windows, x, 4.4, Vector2(1.1, 1.6), trim)
	_window(walls, windows, r.position.x + 15.5, 1.6, Vector2(1.3, 1.6), trim)
	_door(walls, r.position.x + 11.0, look["door"], trim)
	for x: float in [r.position.x + 4.0, r.position.x + 9.0, r.position.x + 14.0]:
		_window(walls, windows, x, 4.4, Vector2(1.0, 1.4), trim, true)
	# A string course of white brick between the floors, and the chimneys with their pots.
	WorldBuildings.box(walls, Transform3D(), Vector3(r.get_center().x, 3.05, r.end.y + 0.03), Vector3(r.size.x, 0.18, 0.08), trim)
	for x: float in [r.position.x + 2.5, r.end.x - 2.5]:
		WorldBuildings.box(walls, Transform3D(), Vector3(x, h + 3.2, r.get_center().y), Vector3(1.0, 3.4, 1.2), wall.darkened(0.08))
		for k: float in [-0.25, 0.25]:
			WorldBuildings.cylinder(walls, Transform3D(Basis(), Vector3(x + k, h + 4.9, r.get_center().y)), 0.14, 0.12, 0.5, 8, Color(0.62, 0.35, 0.22), false)


## A modern house: white render with a band of timber cladding, a flat roof behind a thin
## parapet, wide glazing downstairs, a canopy over the door.
func _modern(walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, look: Dictionary) -> void:
	var r := HomePlots.HOUSE
	var h := HomePlots.HOUSE_WALL
	var wall: Color = look["wall"]
	var timber: Color = look["trim"]
	_block(walls, r, h, wall)
	WorldBuildings.box(roofs, Transform3D(), Vector3(r.get_center().x, h + 0.05, r.get_center().y), Vector3(r.size.x - 0.2, 0.1, r.size.y - 0.2), look["roof"])
	WorldBuildings.box(walls, Transform3D(), Vector3(r.get_center().x, h + 0.25, r.end.y - 0.1), Vector3(r.size.x, 0.5, 0.2), Color(0.25, 0.26, 0.28))
	# The timber-clad upper half of the left end, standing a little proud.
	var clad := Rect2(r.position.x - 0.15, r.position.y - 0.15, 8.0, r.size.y + 0.3)
	WorldBuildings.box(walls, Transform3D(), Vector3(clad.get_center().x, h * 0.75, clad.get_center().y), Vector3(clad.size.x, h * 0.5, clad.size.y), timber)
	# Floor to ceiling glass downstairs, a long strip upstairs.
	WorldBuildings.box(windows, Transform3D(), Vector3(r.position.x + 9.5, 1.35, r.end.y + 0.03), Vector3(7.0, 2.5, 0.06), Color.WHITE)
	WorldBuildings.box(windows, Transform3D(), Vector3(r.position.x + 4.0, 4.6, r.end.y + 0.18), Vector3(6.0, 1.2, 0.06), Color.WHITE)
	WorldBuildings.box(windows, Transform3D(), Vector3(r.position.x + 13.0, 4.6, r.end.y + 0.03), Vector3(5.0, 1.2, 0.06), Color.WHITE)
	for x: float in [r.position.x + 6.0, r.position.x + 9.5, r.position.x + 13.0]:
		WorldBuildings.box(walls, Transform3D(), Vector3(x, 1.35, r.end.y + 0.07), Vector3(0.08, 2.5, 0.06), Color(0.15, 0.15, 0.16))
	WorldBuildings.box(windows, Transform3D(), Vector3(r.get_center().x, 4.6, r.position.y - 0.03), Vector3(10.0, 1.2, 0.06), Color.WHITE)
	_door(walls, r.end.x - 2.6, look["door"], Color(0.3, 0.31, 0.33), 1.2)
	# The canopy over the door.
	WorldBuildings.box(walls, Transform3D(), Vector3(r.end.x - 2.6, 2.75, r.end.y + 0.9), Vector3(3.0, 0.14, 1.8), Color(0.3, 0.31, 0.33))


## A Georgian house: dressed stone, symmetrical, five windows across on both floors, a hipped
## slate roof, the door in the middle under a pillared porch with a pediment.
func _georgian(walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, look: Dictionary) -> void:
	var r := HomePlots.HOUSE
	var h := HomePlots.HOUSE_WALL + 0.6
	var wall: Color = look["wall"]
	var trim: Color = look["trim"]
	_block(walls, r, h, wall)
	_hip(roofs, r.grow(0.35), h, 3.4, look["roof"])
	# Quoins up the corners, a cornice under the eaves.
	for x: float in [r.position.x + 0.15, r.end.x - 0.15]:
		for k in 8:
			WorldBuildings.box(walls, Transform3D(), Vector3(x, 0.4 + k * 0.85, r.end.y + 0.03), Vector3(0.5 if k % 2 == 0 else 0.34, 0.4, 0.08), trim)
	WorldBuildings.box(walls, Transform3D(), Vector3(r.get_center().x, h - 0.12, r.end.y + 0.08), Vector3(r.size.x + 0.2, 0.24, 0.16), trim)
	var mid := r.get_center().x
	for k in 5:
		var x := mid + (k - 2) * 3.4
		_window(walls, windows, x, 4.6, Vector2(1.1, 1.8), trim)
		_window(walls, windows, x, 4.6, Vector2(1.1, 1.8), trim, true)
		if k != 2:
			_window(walls, windows, x, 1.7, Vector2(1.1, 1.9), trim)
	_door(walls, mid, look["door"], trim, 1.2)
	# The porch: two columns and a pediment over the door.
	for x: float in [mid - 1.2, mid + 1.2]:
		WorldBuildings.cylinder(walls, Transform3D(Basis(), Vector3(x, 0.15, r.end.y + 1.1)), 0.16, 0.14, 2.6, 10, trim, true)
	WorldBuildings.box(walls, Transform3D(), Vector3(mid, 2.85, r.end.y + 0.7), Vector3(3.0, 0.22, 1.5), trim)
	WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(mid, 2.96, r.end.y + 0.7), 1.6, 0.8, 0.7, false, look["roof"], trim)
	for x: float in [r.position.x + 1.6, r.end.x - 1.6]:
		WorldBuildings.box(walls, Transform3D(), Vector3(x, h + 2.6, r.get_center().y), Vector3(1.4, 2.4, 0.9), wall.darkened(0.06))


## A hipped roof over rectangle `r` from height `h`, rising `rise` to a ridge along its length.
static func _hip(st: SurfaceTool, r: Rect2, h: float, rise: float, col: Color) -> void:
	var hz := r.size.y * 0.5
	var c := r.get_center()
	var ridge := maxf(0.0, r.size.x * 0.5 - hz)
	var fl := Vector3(r.position.x, h, r.end.y)
	var fr := Vector3(r.end.x, h, r.end.y)
	var bl := Vector3(r.position.x, h, r.position.y)
	var br := Vector3(r.end.x, h, r.position.y)
	var rl := Vector3(c.x - ridge, h + rise, c.y)
	var rr := Vector3(c.x + ridge, h + rise, c.y)
	var mid := Vector3(c.x, h + rise * 0.3, c.y)
	WorldBuildings.face(st, [fl, fr, rr, rl], (fl + rr) * 0.5 - mid, col)
	WorldBuildings.face(st, [bl, br, rr, rl], (bl + rr) * 0.5 - mid, col)
	WorldBuildings.face(st, [fl, bl, rl], (fl + bl) * 0.5 - mid, col.darkened(0.05))
	WorldBuildings.face(st, [fr, br, rr], (fr + br) * 0.5 - mid, col.darkened(0.05))
	WorldBuildings.face(st, [fl, bl, br, fr], Vector3.DOWN, col.darkened(0.3))


## A stone farmhouse: whitewashed walls on a dark stone plinth, a long clay pantile roof with a
## chimney at each gable end, small windows, a little gabled porch.
func _farmhouse(walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, look: Dictionary) -> void:
	var r := HomePlots.HOUSE
	var h := HomePlots.HOUSE_WALL - 0.6
	var wall: Color = look["wall"]
	var trim: Color = look["trim"]
	_block(walls, r, h, wall)
	WorldBuildings.box(walls, Transform3D(), Vector3(r.get_center().x, 0.3, r.get_center().y), Vector3(r.size.x + 0.1, 0.8, r.size.y + 0.1), trim)
	WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(r.get_center().x, h, r.get_center().y), r.size.x * 0.5 + 0.5,
		r.size.y * 0.5 + 0.6, 3.6, false, look["roof"], wall)
	for x: float in [r.position.x + 0.5, r.end.x - 0.5]:
		WorldBuildings.box(walls, Transform3D(), Vector3(x, h + 2.6, r.get_center().y), Vector3(1.0, 4.4, 1.1), trim)
	for x: float in [r.position.x + 3.0, r.position.x + 7.0, r.position.x + 12.5, r.position.x + 16.0]:
		_window(walls, windows, x, 4.0, Vector2(0.9, 1.0), trim)
		_window(walls, windows, x, 1.5, Vector2(1.0, 1.1), trim)
		_window(walls, windows, x, 4.0, Vector2(0.9, 1.0), trim, true)
	var dx := r.position.x + 9.7
	_door(walls, dx, look["door"], trim)
	# The porch over the door.
	WorldBuildings.box(walls, Transform3D(), Vector3(dx - 1.0, 1.2, r.end.y + 0.8), Vector3(0.25, 2.4, 1.4), wall)
	WorldBuildings.box(walls, Transform3D(), Vector3(dx + 1.0, 1.2, r.end.y + 0.8), Vector3(0.25, 2.4, 1.4), wall)
	WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(dx, 2.4, r.end.y + 0.8), 1.4, 0.9, 1.0, true, look["roof"], wall)


## The garage block of four doors to the right of the house, in the house's own style.
func _garages(walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool, look: Dictionary, style: String) -> void:
	var g := HomePlots.GARAGE
	var h := HomePlots.GARAGE_WALL
	var wall: Color = look["wall"] if style != "farmhouse" else Color(0.3, 0.22, 0.15)
	_block(walls, g, h, wall)
	match style:
		"modern":
			WorldBuildings.box(roofs, Transform3D(), Vector3(g.get_center().x, h + 0.08, g.get_center().y), Vector3(g.size.x + 0.4, 0.16, g.size.y + 0.6), look["roof"])
		"georgian":
			_hip(roofs, g.grow(0.3), h, 2.2, look["roof"])
			# A clock in the middle of the coach house's front.
			WorldBuildings.cylinder(walls, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(g.get_center().x, h - 0.45, g.end.y + 0.02)), 0.34, 0.34, 0.06, 16, Color(0.95, 0.95, 0.9), true)
		_:
			WorldBuildings.prism(roofs, walls, Transform3D(), Vector3(g.get_center().x, h, g.get_center().y), g.size.x * 0.5 + 0.3,
				g.size.y * 0.5 + 0.4, 2.2 if style == "victorian" else 2.6, false, look["roof"], wall)
	var trim: Color = look["trim"]
	for x: float in HomePlots.DOOR_X:
		var size := HomePlots.DOOR_SIZE
		WorldBuildings.box(walls, Transform3D(), Vector3(x, size.y * 0.5, g.end.y + 0.04), Vector3(size.x, size.y, 0.08), look["garage"])
		# Panels across the door, and the lintel over it.
		for k in 4:
			WorldBuildings.box(walls, Transform3D(), Vector3(x, 0.3 + k * 0.58, g.end.y + 0.09), Vector3(size.x - 0.2, 0.05, 0.03), (look["garage"] as Color).darkened(0.25))
		WorldBuildings.box(walls, Transform3D(), Vector3(x, size.y + 0.1, g.end.y + 0.06), Vector3(size.x + 0.3, 0.2, 0.12), trim)
	# A small window in the side wall.
	WorldBuildings.box(windows, Transform3D(), Vector3(g.end.x + 0.03, 1.8, g.get_center().y), Vector3(0.06, 0.8, 1.2), Color.WHITE)
