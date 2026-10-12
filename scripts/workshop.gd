class_name Workshop
extends Node3D
## The shed: a big workshop with a roller door onto the Build Yard. Inside are four bike bays
## with paddock stands and a screen above each, a long workbench, a parts washer, a repair
## bench, a rack of new parts, a bin, a tool wall and the crew board. It also draws every
## parked bike and every loose part from the shared Shed state.

const CENTER := Vector3(0.0, 0.0, 65.0)
const HALF := Vector2(11.5, 8.0)          # interior half size in x and z
const HEIGHT := 5.6
const DOOR_HALF := 3.6
const DOOR_HEIGHT := 4.3
const BAY_COUNT := 4
const INTERACT_LAYER := 8
const SHELF_LEVELS := [0.32, 0.82, 1.32, 1.82, 2.32]

var bike_views := {}       # bike id -> Node3D holding a BikeModel
var _view_sigs := {}
var _spot_nodes := {}      # spot -> Node3D
var _spot_sigs := {}
var _bay_screens: Array[Dashboard] = []
var _crew_screen: Dashboard
var _dash_timer := 0.0
var _dash_dirty := true
var _mats := {}


static func bay_transform(bay: int) -> Transform3D:
	var x := -6.75 + 4.5 * clampi(bay, 0, BAY_COUNT - 1)
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.0, -5.2))


## Where each work spot puts a part, and which way it faces.
static func spot_transform(spot: String) -> Transform3D:
	if spot.begins_with("bench_"):
		var i := int(spot.trim_prefix("bench_"))
		var z := -6.6 + i * 1.3 + (0.5 if i >= 3 else 0.0)
		return Transform3D(Basis(), CENTER + Vector3(-HALF.x + 0.5, 0.96, z))
	if spot == "washer":
		return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(HALF.x - 1.2, 0.86, HALF.y - 0.75))
	if spot == "repair":
		return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(HALF.x - 4.4, 0.96, HALF.y - 0.6))
	return Transform3D(Basis(), CENTER)


## Where players appear on foot when they arrive.
static func walker_spawn(index: int) -> Transform3D:
	var x := -3.0 + (index % 4) * 2.0
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.1, 5.5 - (index / 4) * 1.5))


func build() -> void:
	name = "Workshop"
	add_to_group("workshop")
	_make_materials()
	_build_shell()
	_build_bays()
	_build_bench()
	_build_washer()
	_build_repair_bench()
	_build_bin()
	_build_shelves()
	_build_tool_wall()
	_build_lights()
	_crew_screen = Dashboard.new("crew", 4.0)
	_crew_screen.position = CENTER + Vector3(-HALF.x + 0.12, 2.9, -3.0)
	_crew_screen.rotation.y = PI * 0.5
	add_child(_crew_screen)


# ---------------------------------------------------------------------------- state

## Redraws parked bikes, loose parts and screens to match the Shed state.
func sync_state() -> void:
	for id in bike_views.keys():
		if not Shed.bikes.has(id) or Shed.bikes[id]["rider"] != 0:
			bike_views[id].queue_free()
			bike_views.erase(id)
			_view_sigs.erase(id)
	for id in Shed.bikes:
		var bike: Dictionary = Shed.bikes[id]
		if bike["rider"] != 0:
			continue
		var sig := _bike_signature(id)
		if _view_sigs.get(id, "") == sig:
			continue
		_view_sigs[id] = sig
		if bike_views.has(id):
			bike_views[id].free()
		bike_views[id] = _make_bike_view(id)
	for spot in Shed.SPOTS:
		var item_id := Shed.item_at_spot(spot)
		var sig := ""
		if item_id != 0:
			var it: Dictionary = Shed.items[item_id]
			sig = "%d:%s:%.1f:%.1f:%.1f" % [item_id, it["part"], it["rust"], it["dirt"], it["wear"]]
		if _spot_sigs.get(spot, "") == sig:
			continue
		_spot_sigs[spot] = sig
		if _spot_nodes.has(spot):
			_spot_nodes[spot].free()
			_spot_nodes.erase(spot)
		if item_id != 0:
			var it: Dictionary = Shed.items[item_id]
			var display := BikeModel.part_display(it["part"], Shed.condition_of(it))
			display.transform = spot_transform(spot)
			add_child(display)
			_spot_nodes[spot] = display
	_dash_dirty = true


func _bike_signature(id: int) -> String:
	var bike: Dictionary = Shed.bikes[id]
	var parts := []
	for slot in PartsDB.SLOTS:
		var item_id := Shed.item_on(id, slot)
		if item_id == 0:
			parts.append("-")
		else:
			var it: Dictionary = Shed.items[item_id]
			parts.append("%s:%.2f:%.2f:%.2f:%s" % [it["part"], it["rust"], it["dirt"], it["wear"], Shed.is_bolted(id, slot)])
	return "%s|%s|%s" % [",".join(parts), str(bike["xf"]), str(bike["paint"])]


func _make_bike_view(id: int) -> Node3D:
	var bike: Dictionary = Shed.bikes[id]
	var view := Node3D.new()
	view.name = "Bike%d" % id
	view.transform = bike["xf"]
	add_child(view)
	var build := Shed.build_of(id)
	var model := BikeModel.new()
	view.add_child(model)
	var on_stand: bool = Shed.missing_slots(id).has("wheels") or bike["xf"].origin.distance_to(bay_transform(bike["bay"]).origin) < 0.5
	var lift := 0.06 if on_stand else 0.0
	model.position.y = build.rear_radius + lift
	model.build_from(build, bike["paint"], Shed.fitted_map(id), build.condition, false)
	model.build_pickers({"bike": id})
	if on_stand:
		_paddock_stand(view, build)
	return view


func _paddock_stand(parent: Node3D, build: BikeBuild) -> void:
	var steel: Material = _mats["stand"]
	for z in [-build.wheelbase * 0.5 + 0.12, build.wheelbase * 0.5 - 0.15]:
		_deco(parent, Vector3(0.0, 0.03, z), Vector3(0.5, 0.06, 0.08), steel)
		for side in [-1.0, 1.0]:
			_deco(parent, Vector3(0.22 * side, build.rear_radius * 0.5, z), Vector3(0.04, build.rear_radius, 0.04), steel)
	_deco(parent, Vector3(0.0, build.rear_radius - 0.06, 0.0), Vector3(0.12, 0.12, build.wheelbase * 0.55), steel)


func _process(delta: float) -> void:
	_dash_timer -= delta
	if _dash_timer > 0.0:
		return
	_dash_timer = 0.5
	_refresh_dashboards()


func _refresh_dashboards() -> void:
	if not Shed.active:
		return
	if _dash_dirty:
		_dash_dirty = false
		for bay in BAY_COUNT:
			_bay_screens[bay].show_data(_bay_data(bay))
	var players := []
	var ids: Array = Shed.crew.keys()
	ids.sort()
	for peer in ids:
		var c: Dictionary = Shed.crew[peer]
		var doing := str(c.get("activity", ""))
		var riding := int(c.get("riding", 0))
		if riding != 0 and Shed.bikes.has(riding):
			doing = "Riding %s, %d km/h" % [Shed.bikes[riding]["name"], roundi(float(c.get("kmh", 0.0)))]
		elif Shed.held_by(peer) != 0:
			doing = "Carrying " + Shed.item_title(Shed.held_by(peer))
		elif doing == "":
			doing = "Holding the %s" % str(c.get("tool", "hands")) if c.get("tool", "hands") != "hands" else "Looking around"
		var p := c.duplicate()
		p["doing"] = doing
		p["color"] = Shed.PAINTS[int(c.get("slot", 0)) % Shed.PAINTS.size()]
		players.append(p)
	_crew_screen.show_data({"players": players})


func _bay_data(bay: int) -> Dictionary:
	var bike_id := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["bay"] == bay:
			bike_id = id
			if Shed.bikes[id]["xf"].origin.distance_to(bay_transform(bay).origin) < 2.5:
				break
	if bike_id == 0:
		return {}
	var bike: Dictionary = Shed.bikes[bike_id]
	var build := Shed.build_of(bike_id)
	var missing := Shed.missing_slots(bike_id)
	var loose := Shed.loose_slots(bike_id)
	var status := "READY TO RIDE"
	if bike["rider"] != 0:
		status = "OUT RIDING: %s" % Shed.crew.get(bike["rider"], {}).get("name", "someone")
	elif not missing.is_empty():
		status = "%d PART%s MISSING" % [missing.size(), "" if missing.size() == 1 else "S"]
	elif not loose.is_empty():
		status = "%d PART%s LOOSE" % [loose.size(), "" if loose.size() == 1 else "S"]
	var parts := []
	for slot in PartsDB.SLOTS:
		var item_id := Shed.item_on(bike_id, slot)
		parts.append({"name": PartsDB.SLOT_NAMES[slot], "fitted": item_id != 0, "bolted": Shed.is_bolted(bike_id, slot),
			"health": BikeBuild.part_health(Shed.condition_of(Shed.items[item_id])) if item_id != 0 else 0.0})
	return {"name": bike["name"], "status": status, "now": build.summary(), "delivered": bike["delivered"], "parts": parts}


# ---------------------------------------------------------------------------- building

func _make_materials() -> void:
	_mats["floor"] = _material(Color(0.36, 0.37, 0.38), 0.0, 0.3, _noise(0.08, 0.92, 1.04), 6.0)
	_mats["wall_in"] = _material(Color(0.78, 0.76, 0.72), 0.0, 0.85, _noise(0.2, 0.9, 1.04), 2.0)
	_mats["wall_low"] = _material(Color(0.2, 0.24, 0.27), 0.0, 0.6)
	var cladding := _material(Color(0.3, 0.33, 0.36), 0.7, 0.45)
	cladding.normal_enabled = true
	cladding.normal_texture = _corrugation()
	cladding.normal_scale = 1.0
	cladding.uv1_triplanar = true
	cladding.uv1_scale = Vector3(2.5, 2.5, 2.5)
	_mats["cladding"] = cladding
	_mats["roof"] = _material(Color(0.25, 0.27, 0.29), 0.6, 0.5)
	_mats["steel"] = _material(Color(0.3, 0.32, 0.35), 0.85, 0.35)
	_mats["stand"] = _material(Color(0.85, 0.35, 0.05), 0.5, 0.4)
	_mats["wood"] = _material(Color(0.5, 0.36, 0.22), 0.0, 0.7, _noise(0.5, 0.85, 1.08), 3.0)
	_mats["yellow"] = _material(Color(0.95, 0.75, 0.05), 0.0, 0.5)
	_mats["dark"] = _material(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	_mats["box"] = _material(Color(0.62, 0.47, 0.3), 0.0, 0.9, _noise(0.6, 0.9, 1.05), 2.0)
	_mats["blue"] = _material(Color(0.1, 0.3, 0.65), 0.6, 0.35)
	_mats["red"] = _material(Color(0.7, 0.08, 0.06), 0.5, 0.35)
	_mats["chrome"] = _material(Color(0.85, 0.86, 0.88), 1.0, 0.15)


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


func _noise(freq: float, dark: float, light: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.1
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color(light, light, light))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


## A normal map of vertical ridges, for corrugated steel cladding.
func _corrugation() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.5, 1.0))
	g.set_color(1, Color(0.5, 0.5, 1.0))
	g.add_point(0.25, Color(0.9, 0.5, 0.85))
	g.add_point(0.75, Color(0.1, 0.5, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.repeat = GradientTexture2D.REPEAT
	return tex


func _solid(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> StaticBody3D:
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
	body.add_child(mi)
	parent.add_child(body)
	return body


func _deco(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


## Invisible collision, so players can't walk through furniture made of loose meshes.
func _blocker(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## An invisible click target for the player's hands and tools.
func _target(center: Vector3, size: Vector3, meta: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = INTERACT_LAYER
	body.collision_mask = 0
	body.position = center
	for key in meta:
		body.set_meta(key, meta[key])
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _label(text: String, pos: Vector3, rot_y: float, size := 32, color := Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 6
	add_child(l)
	return l


func _build_shell() -> void:
	var c := CENTER
	var hx := HALF.x
	var hz := HALF.y
	var t := 0.3
	# Floor: a polished epoxy slab sitting on the yard concrete, with bay markings.
	var floor_mi := _deco(self, c + Vector3(0.0, 0.004, 0.0), Vector3(hx * 2.0, 0.008, hz * 2.0), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Walls: back, sides, and the front wall either side of the roller door.
	var walls := [
		[c + Vector3(0.0, HEIGHT * 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, HEIGHT, t)],
		[c + Vector3(-hx - t * 0.5, HEIGHT * 0.5, 0.0), Vector3(t, HEIGHT, hz * 2.0)],
		[c + Vector3(hx + t * 0.5, HEIGHT * 0.5, 0.0), Vector3(t, HEIGHT, hz * 2.0)],
	]
	var side_w := hx - DOOR_HALF
	for side in [-1.0, 1.0]:
		walls.append([c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5, hz + t * 0.5), Vector3(side_w + t, HEIGHT, t)])
	walls.append([c + Vector3(0.0, (HEIGHT + DOOR_HEIGHT) * 0.5, hz + t * 0.5), Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_HEIGHT, t)])
	for w in walls:
		_solid(w[0], w[1], _mats["cladding"])
	# Inside faces: painted plaster upper, dark lower band.
	_deco(self, c + Vector3(0.0, HEIGHT * 0.5 + 0.6, -hz + 0.01), Vector3(hx * 2.0, HEIGHT - 1.2, 0.02), _mats["wall_in"])
	_deco(self, c + Vector3(0.0, 0.6, -hz + 0.01), Vector3(hx * 2.0, 1.2, 0.02), _mats["wall_low"])
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * (hx - 0.01), HEIGHT * 0.5 + 0.6, 0.0), Vector3(0.02, HEIGHT - 1.2, hz * 2.0), _mats["wall_in"])
		_deco(self, c + Vector3(side * (hx - 0.01), 0.6, 0.0), Vector3(0.02, 1.2, hz * 2.0), _mats["wall_low"])
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5 + 0.6, hz - 0.01), Vector3(side_w, HEIGHT - 1.2, 0.02), _mats["wall_in"])
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), 0.6, hz - 0.01), Vector3(side_w, 1.2, 0.02), _mats["wall_low"])
		# Hazard-yellow door posts.
		_deco(self, c + Vector3(side * (DOOR_HALF + 0.08), DOOR_HEIGHT * 0.5, hz + 0.02), Vector3(0.16, DOOR_HEIGHT, t + 0.08), _mats["yellow"])
	# Roof with steel trusses.
	_solid(c + Vector3(0.0, HEIGHT + 0.15, 0.0), Vector3(hx * 2.0 + 1.0, 0.3, hz * 2.0 + 1.0), _mats["roof"])
	for i in 7:
		var z := -hz + 1.0 + i * (hz * 2.0 - 2.0) / 6.0
		_deco(self, c + Vector3(0.0, HEIGHT - 0.25, z), Vector3(hx * 2.0, 0.22, 0.12), _mats["steel"])
	# The roller door, rolled up into its drum above the opening.
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.38
	cyl.bottom_radius = 0.38
	cyl.height = DOOR_HALF * 2.0 + 0.3
	drum.mesh = cyl
	drum.material_override = _mats["cladding"]
	drum.position = c + Vector3(0.0, DOOR_HEIGHT + 0.42, hz - 0.45)
	drum.rotation.z = PI * 0.5
	add_child(drum)
	_deco(self, c + Vector3(0.0, DOOR_HEIGHT + 0.02, hz - 0.08), Vector3(DOOR_HALF * 2.0, 0.08, 0.1), _mats["dark"])
	# Sign over the door.
	var sign := Label3D.new()
	sign.text = "TORQUE SHED"
	sign.font_size = 150
	sign.outline_size = 22
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.position = c + Vector3(0.0, DOOR_HEIGHT + 0.75, hz + t + 0.05)
	sign.pixel_size = 0.009
	add_child(sign)
	# Painted bay boxes and a walkway line.
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		for side in [-1.0, 1.0]:
			_deco(self, xf.origin + Vector3(side * 1.6, 0.01, 0.6), Vector3(0.08, 0.004, 4.6), _mats["yellow"])
		_label("BAY %d" % (bay + 1), xf.origin + Vector3(0.0, 0.012, 2.6), 0.0, 96, Color(0.95, 0.8, 0.2)).rotation.x = -PI * 0.5
	_deco(self, c + Vector3(0.0, 0.01, -1.6), Vector3(hx * 2.0 - 4.0, 0.004, 0.08), _mats["yellow"])


func _build_bays() -> void:
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		var screen := Dashboard.new("bike", 3.2)
		screen.position = Vector3(xf.origin.x, 2.75, CENTER.z - HALF.y + 0.12)
		add_child(screen)
		_bay_screens.append(screen)


func _build_bench() -> void:
	var x := CENTER.x - HALF.x + 0.5
	for block in 2:
		var z_from := spot_transform("bench_%d" % (block * 3)).origin.z - 0.62
		var z_to := spot_transform("bench_%d" % (block * 3 + 2)).origin.z + 0.62
		var mid := (z_from + z_to) * 0.5
		var length := z_to - z_from
		_solid(Vector3(x, 0.45, mid), Vector3(0.9, 0.9, length), _mats["steel"])
		_deco(self, Vector3(x, 0.92, mid), Vector3(0.95, 0.06, length + 0.05), _mats["wood"])
		for i in 3:
			_deco(self, Vector3(x + 0.46, 0.25 + i * 0.25, mid), Vector3(0.02, 0.2, length - 0.2), _mats["red"])
	for i in 6:
		var spot := "bench_%d" % i
		var xf := spot_transform(spot)
		_target(xf.origin + Vector3(0.0, 0.25, 0.0), Vector3(0.95, 0.5, 1.25), {"spot": spot})
	_label("WORKBENCH", Vector3(x + 0.47, 1.3, CENTER.z - 3.6), PI * 0.5, 40, Color(1, 0.8, 0.5))


func _build_washer() -> void:
	var xf := spot_transform("washer")
	var base := xf.origin - Vector3(0.0, 0.86, 0.0)
	_solid(base + Vector3(0.0, 0.4, 0.0), Vector3(1.4, 0.8, 0.9), _mats["blue"])
	_deco(self, base + Vector3(0.0, 0.82, 0.0), Vector3(1.3, 0.04, 0.8), _mats["steel"])
	_deco(self, base + Vector3(0.0, 1.35, 0.42), Vector3(1.4, 1.1, 0.06), _mats["blue"])
	var tap := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.02
	tube.bottom_radius = 0.02
	tube.height = 0.5
	tap.mesh = tube
	tap.material_override = _mats["chrome"]
	tap.position = base + Vector3(0.3, 1.15, 0.3)
	tap.rotation.x = -0.6
	add_child(tap)
	_target(xf.origin + Vector3(0.0, 0.2, 0.0), Vector3(1.4, 0.6, 0.9), {"spot": "washer"})
	_label("PARTS WASHER", base + Vector3(0.0, 1.7, 0.38), PI, 40, Color(0.7, 0.9, 1.0))


func _build_repair_bench() -> void:
	var xf := spot_transform("repair")
	var base := xf.origin - Vector3(0.0, 0.96, 0.0)
	_solid(base + Vector3(0.0, 0.45, 0.0), Vector3(2.0, 0.9, 0.9), _mats["steel"])
	_deco(self, base + Vector3(0.0, 0.92, 0.0), Vector3(2.05, 0.06, 0.95), _mats["dark"])
	# Vice and bench grinder.
	_deco(self, base + Vector3(-0.75, 1.03, 0.2), Vector3(0.2, 0.16, 0.3), _mats["blue"])
	_deco(self, base + Vector3(0.75, 1.05, 0.0), Vector3(0.3, 0.2, 0.2), _mats["dark"])
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var w := CylinderMesh.new()
		w.top_radius = 0.09
		w.bottom_radius = 0.09
		w.height = 0.03
		wheel.mesh = w
		wheel.material_override = _mats["steel"]
		wheel.position = base + Vector3(0.75 + side * 0.18, 1.07, 0.0)
		wheel.rotation.z = PI * 0.5
		add_child(wheel)
	_target(xf.origin + Vector3(0.0, 0.25, 0.0), Vector3(2.0, 0.5, 0.9), {"spot": "repair"})
	_label("REPAIR BENCH", base + Vector3(0.0, 1.35, 0.4), PI, 40, Color(1, 0.8, 0.5))


func _build_bin() -> void:
	var pos := CENTER + Vector3(-HALF.x + 3.0, 0.0, HALF.y - 0.7)
	_solid(pos + Vector3(0.0, 0.5, 0.0), Vector3(1.2, 1.0, 0.9), _mats["dark"])
	_deco(self, pos + Vector3(0.0, 1.01, 0.0), Vector3(1.1, 0.02, 0.8), _material(Color(0.12, 0.1, 0.08), 0.4, 0.8))
	_target(pos + Vector3(0.0, 0.8, 0.0), Vector3(1.3, 0.8, 1.0), {"bin": true})
	_label("SCRAP", pos + Vector3(0.0, 0.7, -0.46), PI, 48, Color(1, 0.6, 0.4))


## A tall rack of new parts in boxes: one column per slot, one shelf per variant.
func _build_shelves() -> void:
	var x := CENTER.x + HALF.x - 0.45
	var z0 := CENTER.z - HALF.y + 0.9
	var col_w := 0.92
	for i in PartsDB.SLOTS.size():
		var slot: String = PartsDB.SLOTS[i]
		var z := z0 + i * col_w
		var head := _label(PartsDB.SLOT_NAMES[slot].to_upper(), Vector3(x - 0.42, 2.85, z), -PI * 0.5, 24, Color(1, 0.8, 0.5))
		head.width = 200.0
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ids: Array = PartsDB.by_slot[slot]
		for level in ids.size():
			var part_id: String = ids[level]
			var y: float = SHELF_LEVELS[level]
			var box_size := Vector3(0.55, 0.32, 0.7)
			_deco(self, Vector3(x, y + box_size.y * 0.5 + 0.03, z), box_size, _mats["box"])
			var label := _label(PartsDB.part_name(part_id), Vector3(x - 0.285, y + 0.2, z), -PI * 0.5, 18, Color(0.1, 0.08, 0.05))
			label.outline_size = 0
			label.width = 170.0
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_target(Vector3(x, y + 0.2, z), Vector3(0.6, 0.4, 0.8), {"shelf": part_id})
	# Uprights and shelf boards.
	var length := PartsDB.SLOTS.size() * col_w
	for level in SHELF_LEVELS.size():
		_deco(self, Vector3(x, SHELF_LEVELS[level], z0 - col_w * 0.5 + length * 0.5), Vector3(0.75, 0.03, length), _mats["steel"])
	for i in PartsDB.SLOTS.size() + 1:
		_deco(self, Vector3(x - 0.36, 1.4, z0 - col_w * 0.5 + i * col_w), Vector3(0.05, 2.8, 0.05), _mats["stand"])
		_deco(self, Vector3(x + 0.36, 1.4, z0 - col_w * 0.5 + i * col_w), Vector3(0.05, 2.8, 0.05), _mats["stand"])
	_blocker(Vector3(x, 1.4, z0 - col_w * 0.5 + length * 0.5), Vector3(0.75, 2.8, length))
	_label("NEW PARTS", Vector3(x - 0.42, 3.25, z0 + length * 0.5 - col_w * 0.5), -PI * 0.5, 64, Color(1, 0.85, 0.35))


func _build_tool_wall() -> void:
	var z := CENTER.z + HALF.y - 0.04
	var x0 := CENTER.x + DOOR_HALF + 0.6
	_deco(self, Vector3(x0 + 3.3, 2.3, z), Vector3(6.4, 1.4, 0.03), _material(Color(0.55, 0.42, 0.28), 0.0, 0.8, _noise(1.5, 0.75, 1.0), 6.0))
	var steel: Material = _mats["chrome"]
	for i in 12:
		if x0 + 0.6 + i * 0.5 > CENTER.x + HALF.x - 0.3:
			break
		var len := 0.22 + (i % 4) * 0.06
		var tool := _deco(self, Vector3(x0 + 0.6 + i * 0.5, 2.5 - len * 0.5, z - 0.04), Vector3(0.035, len, 0.015), steel)
		tool.rotation.z = 0.08 * (i % 3 - 1)
		_deco(self, Vector3(x0 + 0.6 + i * 0.5, 2.52, z - 0.04), Vector3(0.07, 0.05, 0.02), steel)
	for i in 6:
		var handle := _deco(self, Vector3(x0 + 0.8 + i * 0.9, 1.95, z - 0.05), Vector3(0.05, 0.3, 0.05), _mats["red"] if i % 2 else _mats["yellow"])
		handle.rotation.z = 0.1
		_deco(self, Vector3(x0 + 0.8 + i * 0.9, 1.75, z - 0.05), Vector3(0.025, 0.12, 0.025), steel)


func _build_lights() -> void:
	var fixture := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		_deco(self, Vector3(xf.origin.x, HEIGHT - 0.4, xf.origin.z), Vector3(0.25, 0.05, 1.6), fixture)
		var spot := SpotLight3D.new()
		spot.position = Vector3(xf.origin.x, HEIGHT - 0.5, xf.origin.z + 0.5)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 55.0
		spot.spot_range = 8.0
		spot.light_energy = 3.0
		spot.light_color = Color(1.0, 0.95, 0.88)
		spot.shadow_enabled = true
		add_child(spot)
	for p in [Vector3(-8.0, 0.0, 1.0), Vector3(0.0, 0.0, 4.0), Vector3(8.0, 0.0, 1.0), Vector3(-8.0, 0.0, 5.5), Vector3(8.0, 0.0, 5.5)]:
		_deco(self, CENTER + p + Vector3(0.0, HEIGHT - 0.4, 0.0), Vector3(0.25, 0.05, 1.6), fixture)
		var omni := OmniLight3D.new()
		omni.position = CENTER + p + Vector3(0.0, HEIGHT - 0.7, 0.0)
		omni.omni_range = 9.0
		omni.light_energy = 1.4
		omni.light_color = Color(1.0, 0.93, 0.82)
		omni.shadow_enabled = p.z > 3.0 and p.x == 0.0
		add_child(omni)
	# Indoors the sky shouldn't light everything blue: a probe gives the shed warm ambient light.
	var probe := ReflectionProbe.new()
	probe.position = CENTER + Vector3(0.0, HEIGHT * 0.5, 0.0)
	probe.size = Vector3(HALF.x * 2.0 + 0.2, HEIGHT, HALF.y * 2.0 + 0.2)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.55, 0.5, 0.45)
	probe.ambient_color_energy = 0.45
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
