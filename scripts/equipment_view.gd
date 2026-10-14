class_name EquipmentView
extends Node3D
## Draws one piece of shed equipment (see Equipment) where it stands: engine stands, shelving,
## parts washers, repair machines, workbenches, posters, seats and TVs. Each has a target to
## take hold of it by and, if it holds parts, a target for each place. +Z is its front.

var id := 0
var model := ""
var kind := ""
var washer_sound: AudioStreamPlayer3D
var tv: ShedTv
var _ws: Node   # the Workshop, for its materials and helpers


static func create(workshop: Node, furniture_id: int) -> EquipmentView:
	var v := EquipmentView.new()
	v._ws = workshop
	v.id = furniture_id
	v.model = str(Shed.furniture[furniture_id].get("model", ""))
	v.kind = Equipment.kind_of(v.model)
	v.name = "Equipment%d" % furniture_id
	workshop.add_child(v)
	v._build()
	return v


func _build() -> void:
	match kind:
		"stand":
			_build_stand()
		"shelf":
			_build_shelf()
		"washer":
			_build_washer()
		"repair":
			_build_repair()
		"bench":
			_build_bench()
		"booth":
			_build_booth()
		"changer":
			_build_changer()
		"poster":
			_build_poster()
		"seat":
			_build_seat()
		"tv":
			_build_tv()
		"whiteboard":
			# The crew whiteboard draws itself and takes the drawing (see Whiteboard).
			add_child(Whiteboard.new())
		"ramp", "obstacle", "barrier", "marker":
			_build_yard()


func _m() -> Dictionary:
	return Equipment.get_model(model)


func _size() -> Vector3:
	return _m().get("size", Vector3.ONE)


func _mat(key: String) -> Material:
	return _ws._mats[key]


func _deco(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	return _ws._deco(self, center, size, mat)


func _cyl(center: Vector3, radius: float, height: float, mat: Material, axis := Vector3.UP) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = mat
	mi.position = center
	if axis == Vector3.RIGHT:
		mi.rotation.z = PI * 0.5
	elif axis == Vector3.BACK:
		mi.rotation.x = PI * 0.5
	add_child(mi)
	return mi


## The body you take hold of to move it, a collision box so you can't walk through it, and a
## target over each place parts go.
func _body(blocker := true) -> void:
	var size := _size()
	if blocker:
		_ws._blocker(Vector3(0.0, size.y * 0.5, 0.0), size, self)
	# The cabinet below the working surface is what you take hold of; the top is for parts.
	var top := Equipment.work_height(model) - 0.08
	_ws._target(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z) + Vector3(0.04, 0.0, 0.04), {"furniture": id}, self)
	if Equipment.SURFACE_KINDS.has(kind):
		# Parts go down anywhere on top (see Shed.surface): one thin target over all of it, under
		# the parts on it, which each have their own (Workshop).
		var h := Equipment.work_height(model)
		_ws._target(Vector3(0.0, h + 0.015, 0.0), Vector3(size.x, 0.03, size.z), {"top": "f%d" % id, "furniture": id}, self)
		return
	for spot in Shed.furniture_spots(id):
		var at := Shed.local_spot_transform(spot).origin
		var w := size.x / maxf(1.0, Equipment.places(model)) if kind != "shelf" else size.x / float(_m()["cols"])
		var h := 0.42 if kind == "shelf" else 0.5
		_ws._target(at + Vector3(0.0, h * 0.5, 0.03), Vector3(w * 0.95, h, size.z * 0.95), {"spot": spot}, self)


func _name_plate(text: String, at: Vector3, size := 26, color := Color(1, 1, 1, 0.85)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0022
	l.modulate = color
	l.outline_size = 0
	l.position = at
	add_child(l)


# ---------------------------------------------------------------------------- floor equipment

## A red engine stand on castors: a column with a turning head that the block bolts to.
func _build_stand() -> void:
	var folding := model == "engine_stand_folding"
	var red: Material = _ws._material(Color(0.2, 0.35, 0.7), 0.5, 0.35) if folding else _mat("red")
	var reach := 0.25 if folding else 0.32
	_deco(Vector3(0.0, 0.05, 0.0), Vector3(reach * 2.0, 0.06, 0.08), red)
	_deco(Vector3(0.25, 0.05, 0.0), Vector3(0.08, 0.06, 0.6 if folding else 0.8), red)
	_deco(Vector3(0.25, 0.32, 0.0), Vector3(0.09, 0.56, 0.09), red)
	_deco(Vector3(0.12, 0.58, 0.0), Vector3(0.26, 0.06, 0.06), _mat("steel"))
	_deco(Vector3(0.0, 0.58, 0.0), Vector3(0.04, 0.24, 0.24), _mat("steel"))
	_deco(Vector3(0.25, 0.75, 0.0), Vector3(0.04, 0.04, 0.5), _mat("steel")).name = "Handle"
	for p in [Vector3(-reach, 0.03, 0.0), Vector3(0.25, 0.03, -0.27 if folding else -0.37), Vector3(0.25, 0.03, 0.27 if folding else 0.37)]:
		_deco(p, Vector3(0.06, 0.06, 0.06), _mat("dark")).name = "Caster"
	var size := _size()
	_ws._blocker(Vector3(0.0, 0.3, 0.0), Vector3(size.x, 0.6, size.z), self)
	_ws._target(Vector3(0.25, 0.4, 0.0), Vector3(0.2, 0.8, size.z + 0.1), {"furniture": id}, self)
	_ws._target(Vector3(0.0, 0.62 + 0.18, 0.0), Vector3(0.7, 0.35, 0.7), {"spot": "stand_%d" % id}, self)


## Steel shelving: boards on four posts, and a label plate on top.
func _build_shelf() -> void:
	var m := _m()
	var size := _size()
	var heavy := model == "shelf_racking"
	var frame: Material = _ws._material(Color(0.9, 0.45, 0.05), 0.5, 0.45) if heavy else _ws._material(Color(0.2, 0.32, 0.5), 0.6, 0.45)
	var board: Material = _ws._material(Color(0.62, 0.6, 0.56), 0.5, 0.55)
	var post := 0.06 if heavy else 0.04
	for x in [-size.x * 0.5 + post * 0.5, size.x * 0.5 - post * 0.5]:
		for z in [-size.z * 0.5 + post * 0.5, size.z * 0.5 - post * 0.5]:
			_deco(Vector3(x, size.y * 0.5, z), Vector3(post, size.y, post), frame)
	var levels := int(m["levels"])
	var pitch := (size.y - 0.15) / float(levels)
	for level in levels + 1:
		var y := minf(0.06 + level * pitch, size.y - 0.02)
		_deco(Vector3(0.0, y, 0.0), Vector3(size.x, 0.03, size.z), board)
		if heavy:
			_deco(Vector3(0.0, y - 0.04, size.z * 0.5 - 0.02), Vector3(size.x, 0.06, 0.04), frame)
	_ws._blocker(Vector3(0.0, size.y * 0.5, 0.0), size, self)
	_ws._target(Vector3(0.0, size.y + 0.05, 0.0), Vector3(size.x + 0.04, 0.12, size.z + 0.04), {"furniture": id}, self)
	for x in [-size.x * 0.5 - 0.02, size.x * 0.5 + 0.02]:
		_ws._target(Vector3(x, size.y * 0.5, 0.0), Vector3(0.06, size.y, size.z), {"furniture": id}, self)
	for spot in Shed.furniture_spots(id):
		var at := Shed.local_spot_transform(spot).origin
		var w := size.x / float(m["cols"])
		_ws._target(at + Vector3(0.0, pitch * 0.42, 0.03), Vector3(w * 0.96, pitch * 0.82, size.z * 0.95), {"spot": spot}, self)
	var plate_y := size.y - 0.12
	_deco(Vector3(0.0, plate_y, size.z * 0.5 + 0.005), Vector3(0.7, 0.14, 0.01), _ws._material(Color(0.88, 0.86, 0.8), 0.0, 0.8)).name = "Plate"
	_ws._target(Vector3(0.0, plate_y, size.z * 0.5), Vector3(0.74, 0.18, 0.06), {"label": id}, self)
	var label := Label3D.new()
	label.name = "Label"
	label.font_size = 36
	label.pixel_size = 0.002
	label.modulate = Color(0.12, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(0.0, plate_y, size.z * 0.5 + 0.012)
	add_child(label)


## A solvent tank on a cabinet with a splash back and a tap, or a cabinet washer with a door.
func _build_washer() -> void:
	var size := _size()
	var top := Equipment.work_height(model)
	var colors := {"washer_compact": Color(0.15, 0.45, 0.25), "washer_standard": Color(0.1, 0.3, 0.65),
		"washer_ultrasonic": Color(0.85, 0.85, 0.82), "washer_cabinet": Color(0.75, 0.12, 0.08), "washer_industrial": Color(0.25, 0.28, 0.3)}
	var body: Material = _ws._material(colors.get(model, Color(0.1, 0.3, 0.65)), 0.6, 0.35)
	if model == "washer_compact":
		# A small tank on four legs.
		for x in [-size.x * 0.4, size.x * 0.4]:
			for z in [-size.z * 0.4, size.z * 0.4]:
				_deco(Vector3(x, top * 0.4, z), Vector3(0.04, top * 0.8, 0.04), _mat("steel"))
		_deco(Vector3(0.0, top - 0.12, 0.0), Vector3(size.x, 0.24, size.z), body)
	else:
		_deco(Vector3(0.0, (top - 0.04) * 0.5, 0.0), Vector3(size.x, top - 0.04, size.z), body)
	_deco(Vector3(0.0, top - 0.02, 0.0), Vector3(size.x - 0.1, 0.04, size.z - 0.1), _mat("steel"))
	if model in ["washer_standard", "washer_industrial", "washer_cabinet"]:
		var back := minf(size.y - top, 1.1)
		_deco(Vector3(0.0, top + back * 0.5, -size.z * 0.5 + 0.03), Vector3(size.x, back, 0.06), body)
		_cyl(Vector3(size.x * 0.25, top + 0.3, -size.z * 0.5 + 0.2), 0.02, 0.5, _mat("chrome")).rotation.x = 0.6
	if model == "washer_cabinet":
		# Glass door hinged up at the back, and a turntable.
		_cyl(Vector3(0.0, top + 0.01, 0.0), size.z * 0.38, 0.02, _mat("steel"))
	if model == "washer_ultrasonic":
		_deco(Vector3(size.x * 0.35, top - 0.2, size.z * 0.5 + 0.005), Vector3(0.12, 0.08, 0.01), _ws._material(Color(0.1, 0.8, 0.4), 0.0, 0.3))
	_name_plate(str(_m()["name"]).to_upper(), Vector3(0.0, top - 0.25, size.z * 0.5 + 0.01), 22)
	_body(false)
	_ws._blocker(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z), self)
	washer_sound = Sfx.make_loop_player(self)
	washer_sound.position = Vector3(0.0, top, 0.0)
	washer_sound.volume_db = -8.0


## A steel bench with a vice and a grinder, a blast cabinet, or a full machine-shop bench.
func _build_repair() -> void:
	var size := _size()
	var top := Equipment.work_height(model)
	if model == "repair_compact":
		_cyl(Vector3(0.0, top * 0.45, 0.0), 0.06, top * 0.9, _mat("dark"))
		_deco(Vector3(0.0, 0.03, 0.0), Vector3(0.5, 0.06, 0.5), _mat("dark"))
		_deco(Vector3(0.0, top - 0.03, 0.0), Vector3(size.x, 0.06, size.z * 0.8), _mat("steel"))
	elif model == "repair_blaster":
		var cab: Material = _ws._material(Color(0.25, 0.45, 0.25), 0.5, 0.4)
		_deco(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z), cab)
		_deco(Vector3(0.0, top + 0.3, -size.z * 0.3), Vector3(size.x, 0.6, size.z * 0.4), cab)
		for x in [-0.2, 0.2]:
			_cyl(Vector3(x, top + 0.25, -size.z * 0.1), 0.07, 0.12, _mat("dark"), Vector3.BACK)
	else:
		_deco(Vector3(0.0, (top - 0.06) * 0.5, 0.0), Vector3(size.x, top - 0.06, size.z), _mat("steel"))
		_deco(Vector3(0.0, top - 0.03, 0.0), Vector3(size.x + 0.05, 0.06, size.z + 0.05), _mat("dark"))
		if model in ["repair_pro", "repair_workshop"]:
			# A pegboard of tools across the back, and drawers.
			_deco(Vector3(0.0, top + 0.5, -size.z * 0.5 + 0.03), Vector3(size.x, 0.8, 0.03), _ws._material(Color(0.55, 0.42, 0.28), 0.0, 0.8))
			for i in 4:
				_deco(Vector3(size.x * 0.5 - 0.25, 0.2 + i * 0.18, size.z * 0.5 + 0.01), Vector3(0.4, 0.14, 0.02), _mat("red"))
	# The vice and grinder every repair machine has, at the ends.
	var end := size.x * 0.5 - 0.12
	_deco(Vector3(-end, top + 0.08, size.z * 0.25), Vector3(0.16, 0.16, 0.24), _mat("blue"))
	_deco(Vector3(end, top + 0.1, -size.z * 0.2), Vector3(0.24, 0.2, 0.18), _mat("dark"))
	for side in [-1.0, 1.0]:
		_cyl(Vector3(end + side * 0.15, top + 0.12, -size.z * 0.2), 0.08, 0.03, _mat("steel"), Vector3.RIGHT)
	_name_plate(str(_m()["name"]).to_upper(), Vector3(0.0, top - 0.2, size.z * 0.5 + 0.03), 22)
	_body(false)
	_ws._blocker(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z), self)


## The tyre changer: a pedestal with a clamping turntable the wheel lies flat on, a column at the
## back with a swing arm and a mount head that rides on the rim, a bead breaker on the side and
## foot pedals. The turntable ("Turntable") and the head ("Head") move while a tyre is worked
## on (see Workshop.spin_changers); a wheel put on it lies on the turntable.
func _build_changer() -> void:
	var size := _size()
	var top := Equipment.work_height(model)
	var body: Material = _ws._material(Color(0.12, 0.35, 0.62), 0.5, 0.35)
	_deco(Vector3(0.0, (top - 0.06) * 0.5, 0.0), Vector3(size.x - 0.1, top - 0.06, size.z - 0.2), body)
	_deco(Vector3(0.0, 0.025, 0.0), Vector3(size.x, 0.05, size.z), _mat("dark"))
	var place := Equipment.local_place(model, 0).origin
	var table := Node3D.new()
	table.name = "Turntable"
	table.position = place
	add_child(table)
	var disc := _cyl(Vector3(0.0, -0.025, 0.0), 0.3, 0.05, _mat("steel"))
	disc.reparent(table, false)
	for i in 4:
		var a := TAU * i / 4.0
		var jaw := _deco(Vector3(cos(a) * 0.17, 0.005, sin(a) * 0.17), Vector3(0.07, 0.03, 0.035), _mat("red"))
		jaw.rotation.y = -a
		jaw.reparent(table, false)
	var post := _cyl(Vector3(0.0, 0.08, 0.0), 0.018, 0.16, _mat("chrome"))
	post.reparent(table, false)
	# Column, swing arm and the mount head that rides on the rim's edge.
	var back := -size.z * 0.5 + 0.08
	_deco(Vector3(0.0, top + 0.42, back), Vector3(0.1, 0.84 + top * 0.0, 0.1), body)
	_deco(Vector3(0.0, top + 0.8, back + 0.2), Vector3(0.08, 0.08, 0.48), body)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, top + 0.8, place.z - 0.24)
	add_child(head)
	var bar := _cyl(Vector3(0.0, -0.3, 0.0), 0.022, 0.6, _mat("chrome"))
	bar.reparent(head, false)
	var foot := _deco(Vector3(0.0, -0.62, 0.0), Vector3(0.05, 0.06, 0.09), _mat("dark"))
	foot.reparent(head, false)
	# Bead breaker arm and its pad on the side, and the tyre lever hung on the column.
	_deco(Vector3(size.x * 0.5 - 0.04, top * 0.55, 0.0), Vector3(0.05, top * 0.6, 0.05), body)
	_deco(Vector3(size.x * 0.5 + 0.02, top * 0.55, 0.12), Vector3(0.04, 0.04, 0.3), _mat("steel")).rotation.x = -0.4
	_deco(Vector3(0.06, top + 0.5, back + 0.06), Vector3(0.02, 0.45, 0.02), _mat("red")).rotation.z = 0.15
	# Foot pedals at the front: turntable, clamps and bead breaker.
	for i in 3:
		_deco(Vector3(-0.18 + i * 0.18, 0.08, size.z * 0.5 - 0.05), Vector3(0.1, 0.03, 0.14), _mat("dark"))
	_name_plate("TYRE CHANGER", Vector3(0.0, top - 0.2, size.z * 0.5 - 0.09), 22)
	_body(false)
	_ws._blocker(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z), self)


## A workbench: a top on a frame, with drawers, castors or folding legs to suit.
func _build_bench() -> void:
	var size := _size()
	var top := Equipment.work_height(model) - 0.01
	var top_mat: Material = _mat("chrome") if model == "bench_pro" else _mat("wood")
	_deco(Vector3(0.0, top - 0.03, 0.0), Vector3(size.x, 0.06, size.z), top_mat)
	match model:
		"bench_compact":
			for x in [-size.x * 0.4, size.x * 0.4]:
				var leg := _deco(Vector3(x, (top - 0.06) * 0.5, 0.0), Vector3(0.04, top, 0.04), _mat("steel"))
				leg.rotation.z = 0.0
				_deco(Vector3(x, 0.03, 0.0), Vector3(0.05, 0.04, size.z * 0.9), _mat("steel"))
		"bench_mobile":
			_deco(Vector3(0.0, (top - 0.06) * 0.5 + 0.06, 0.0), Vector3(size.x - 0.04, top - 0.12, size.z - 0.04), _mat("red"))
			for i in 4:
				_deco(Vector3(0.0, 0.2 + i * 0.18, size.z * 0.5 - 0.01), Vector3(size.x - 0.12, 0.02, 0.02), _mat("chrome"))
			for x in [-size.x * 0.42, size.x * 0.42]:
				for z in [-size.z * 0.4, size.z * 0.4]:
					_cyl(Vector3(x, 0.04, z), 0.04, 0.03, _mat("dark"), Vector3.RIGHT)
		_:
			for x in [-size.x * 0.5 + 0.04, size.x * 0.5 - 0.04]:
				for z in [-size.z * 0.5 + 0.04, size.z * 0.5 - 0.04]:
					_deco(Vector3(x, (top - 0.06) * 0.5, z), Vector3(0.05, top - 0.06, 0.05), _mat("steel"))
			_deco(Vector3(0.0, 0.18, 0.0), Vector3(size.x - 0.1, 0.03, size.z - 0.1), _mat("steel"))
			if model == "bench_pro":
				_deco(Vector3(size.x * 0.25, top * 0.5, 0.0), Vector3(size.x * 0.45, top - 0.1, size.z - 0.06), _ws._material(Color(0.1, 0.1, 0.12), 0.6, 0.35))
				for i in 5:
					_deco(Vector3(size.x * 0.25, 0.15 + i * 0.15, size.z * 0.5 - 0.02), Vector3(size.x * 0.4, 0.02, 0.02), _mat("chrome"))
				_deco(Vector3(0.0, top + 0.5, -size.z * 0.5 + 0.02), Vector3(size.x, 0.85, 0.03), _ws._material(Color(0.3, 0.32, 0.35), 0.4, 0.5))
	_body(false)
	_ws._blocker(Vector3(0.0, top * 0.5, 0.0), Vector3(size.x, top, size.z), self)


## A paint booth: back and side walls, a filter wall at the back, light panels in the roof and
## a rail of hooks the parts hang from. The front is open to walk in and spray.
func _build_booth() -> void:
	var size := _size()
	var panel: Material = _ws._material(Color(0.88, 0.89, 0.9), 0.1, 0.55)
	var frame: Material = _mat("steel")
	var t := 0.05
	_deco(Vector3(0.0, size.y * 0.5, -size.z * 0.5 + t * 0.5), Vector3(size.x, size.y, t), panel)
	for side in [-1.0, 1.0]:
		_deco(Vector3(side * (size.x * 0.5 - t * 0.5), size.y * 0.5, 0.0), Vector3(t, size.y, size.z), panel)
		_deco(Vector3(side * (size.x * 0.5 - t * 0.5), size.y * 0.5, size.z * 0.5), Vector3(t + 0.04, size.y, 0.06), frame)
		_ws._blocker(Vector3(side * (size.x * 0.5 - t * 0.5), size.y * 0.5, 0.0), Vector3(t, size.y, size.z), self)
	_ws._blocker(Vector3(0.0, size.y * 0.5, -size.z * 0.5 + t * 0.5), Vector3(size.x, size.y, t), self)
	# Roof with light panels.
	_deco(Vector3(0.0, size.y - t * 0.5, 0.0), Vector3(size.x, t, size.z), panel)
	var glow: StandardMaterial3D = _ws._material(Color(1.0, 0.98, 0.94), 0.0, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.97, 0.92)
	glow.emission_energy_multiplier = 2.5
	for i in 2:
		_deco(Vector3((i - 0.5) * size.x * 0.45, size.y - t - 0.01, 0.0), Vector3(size.x * 0.35, 0.02, size.z * 0.5), glow)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, size.y - 0.35, 0.2)
	lamp.omni_range = maxf(size.x, size.z) * 1.1
	lamp.light_energy = 0.9
	lamp.light_color = Color(1.0, 0.98, 0.95)
	add_child(lamp)
	# Filter wall at the back, with an extractor grille.
	var filter: Material = _ws._material(Color(0.95, 0.6, 0.35), 0.0, 0.95)
	_deco(Vector3(0.0, size.y * 0.45, -size.z * 0.5 + t + 0.02), Vector3(size.x * 0.8, size.y * 0.6, 0.03), filter)
	for i in 6:
		_deco(Vector3(0.0, size.y * 0.2 + i * size.y * 0.1, -size.z * 0.5 + t + 0.04), Vector3(size.x * 0.8, 0.012, 0.01), frame)
	if model == "booth_pro":
		# Downdraft: a grated floor.
		_deco(Vector3(0.0, 0.02, 0.0), Vector3(size.x - 0.1, 0.04, size.z - 0.1), _ws._material(Color(0.2, 0.21, 0.23), 0.8, 0.4))
		for i in 12:
			_deco(Vector3(0.0, 0.045, -size.z * 0.45 + i * size.z * 0.9 / 11.0), Vector3(size.x - 0.2, 0.01, 0.015), frame)
	# The hook rail and a hook for each place.
	var rail_y := size.y - 0.35
	_deco(Vector3(0.0, rail_y, -0.1), Vector3(size.x - 0.2, 0.04, 0.04), _mat("chrome"))
	for spot in Shed.furniture_spots(id):
		var at := Shed.local_spot_transform(spot).origin
		var wire := _cyl(Vector3(at.x, (rail_y + at.y + 0.55) * 0.5, at.z), 0.004, rail_y - at.y - 0.55, _mat("chrome"))
		wire.name = "HookWire"
		var hook := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.02
		tor.outer_radius = 0.028
		hook.mesh = tor
		hook.material_override = _mat("chrome")
		hook.position = Vector3(at.x, at.y + 0.55, at.z)
		hook.rotation.z = PI * 0.5
		add_child(hook)
		_ws._target(at + Vector3(0.0, 0.3, 0.0), Vector3((size.x - 0.5) / maxf(1.0, Equipment.places(model)) * 0.9, 0.6, 0.5), {"spot": spot}, self)
	_name_plate(str(_m()["name"]).to_upper(), Vector3(0.0, size.y - 0.12, size.z * 0.5 + 0.01), 22)
	# Take hold of it by the side panels.
	for side in [-1.0, 1.0]:
		_ws._target(Vector3(side * (size.x * 0.5 - t * 0.5), 1.0, 0.0), Vector3(t + 0.04, 2.0, size.z), {"furniture": id}, self)


# ---------------------------------------------------------------------------- wall equipment

## A printed poster: coloured paper, a band of colour, a big title and a line under it.
func _build_poster() -> void:
	var size := _size()
	add_child(PosterArt.make(model, size))   # flat printed art, see PosterArt
	_ws._target(Vector3(0.0, 0.0, 0.02), Vector3(size.x, size.y, 0.06), {"furniture": id}, self)


## A flat screen on a wall bracket.
func _build_tv() -> void:
	var size := _size()
	tv = ShedTv.new(size.x, size.y)
	tv.position = Vector3(0.0, 0.0, size.z * 0.5)
	add_child(tv)
	_ws._target(Vector3(0.0, 0.0, size.z * 0.5), Vector3(size.x + 0.04, size.y + 0.04, size.z + 0.04), {"furniture": id}, self)


# ---------------------------------------------------------------------------- seats

## Somewhere to sit: a stool, a creeper, a camp chair, a slat bench or an old sofa.
func _build_seat() -> void:
	var m := _m()
	var size := _size()
	var sit := float(m["sit"])
	var cover: Material = _ws._material(m["color"], 0.0, 0.55)
	match str(m["style"]):
		"stool":
			_cyl(Vector3(0.0, sit - 0.04, 0.0), 0.2, 0.08, cover)
			_cyl(Vector3(0.0, sit * 0.5, 0.0), 0.025, sit, _mat("chrome"))
			_cyl(Vector3(0.0, 0.03, 0.0), 0.2, 0.04, _mat("dark"))
		"creeper":
			_deco(Vector3(0.0, sit - 0.05, 0.0), Vector3(0.38, 0.1, 0.38), cover)
			_deco(Vector3(0.0, 0.18, 0.0), Vector3(0.45, 0.03, 0.55), _mat("red"))
			for x in [-0.2, 0.2]:
				for z in [-0.24, 0.24]:
					_cyl(Vector3(x, 0.035, z), 0.035, 0.03, _mat("dark"), Vector3.RIGHT)
				_deco(Vector3(x, 0.1, 0.0), Vector3(0.03, 0.14, 0.03), _mat("chrome"))
		"chair":
			_deco(Vector3(0.0, sit, 0.02), Vector3(0.48, 0.03, 0.42), cover)
			_deco(Vector3(0.0, sit + 0.25, -0.2), Vector3(0.48, 0.45, 0.03), cover)
			for x in [-0.22, 0.22]:
				_deco(Vector3(x, sit * 0.5, 0.0), Vector3(0.025, sit, 0.4), _mat("steel")).rotation.x = 0.35
				_deco(Vector3(x, sit + 0.12, 0.02), Vector3(0.03, 0.03, 0.42), _mat("steel"))
		"bench":
			for i in 3:
				_deco(Vector3(0.0, sit, -0.15 + i * 0.15), Vector3(size.x, 0.04, 0.12), cover)
			for x in [-size.x * 0.4, size.x * 0.4]:
				_deco(Vector3(x, sit * 0.5, 0.0), Vector3(0.06, sit, 0.4), _mat("steel"))
		"sofa":
			_deco(Vector3(0.0, sit - 0.12, 0.05), Vector3(size.x - 0.3, 0.24, size.z - 0.25), cover)
			_deco(Vector3(0.0, 0.18, 0.0), Vector3(size.x, 0.2, size.z), cover)
			_deco(Vector3(0.0, sit + 0.2, -size.z * 0.5 + 0.12), Vector3(size.x, 0.5, 0.24), cover)
			for x in [-size.x * 0.5 + 0.12, size.x * 0.5 - 0.12]:
				_deco(Vector3(x, sit + 0.02, 0.0), Vector3(0.24, 0.3, size.z), cover)
	_ws._blocker(Vector3(0.0, sit * 0.5, 0.0), Vector3(size.x, sit, size.z) * 0.9, self)
	_ws._target(Vector3(0.0, size.y * 0.5, 0.0), size + Vector3(0.04, 0.04, 0.04), {"furniture": id}, self)


## Where someone sitting on seat place `n` sits, in the seat's own space.
static func sit_point(model_id: String, n := 0) -> Vector3:
	var m := Equipment.get_model(model_id)
	var size: Vector3 = m.get("size", Vector3.ONE)
	var seats := maxi(1, roundi(size.x / 0.6)) if m.get("style", "") in ["bench", "sofa"] else 1
	var x := -size.x * 0.5 + size.x * (0.5 + clampi(n, 0, seats - 1)) / float(seats)
	return Vector3(x, float(m.get("sit", 0.5)), 0.05)


# ---------------------------------------------------------------------------- yard kit

func _build_yard() -> void:
	var size := _size()
	var wood: Material = _mat("wood")
	var steel: Material = _mat("steel")
	match model:
		"ramp_small", "ramp_medium", "ramp_large", "ramp_landing":
			var deck: Material = wood if model != "ramp_large" else _ws._material(Color(0.45, 0.47, 0.5), 0.8, 0.45)
			_wedge(Vector3(0.0, 0.0, 0.0), size, deck, true)
			# Side rails show the shape and which end is the lip.
			for x in [-size.x * 0.5, size.x * 0.5]:
				var rail := _deco(Vector3(x, size.y * 0.5, 0.0), Vector3(0.06, 0.06, Vector2(size.y, size.z).length()), _mat("yellow"))
				rail.rotation.x = atan2(size.y, size.z)
		"tabletop":
			var dirt: Material = _ws._material(Color(0.42, 0.3, 0.19), 0.0, 1.0, _ws._noise(0.4, 0.8, 1.1), 2.0)
			var face := 3.0
			_wedge(Vector3(0.0, 0.0, size.z * 0.5 - face * 0.5), Vector3(size.x, size.y, face), dirt, true)
			_wedge(Vector3(0.0, 0.0, -size.z * 0.5 + face * 0.5), Vector3(size.x, size.y, face), dirt, false)
			var top := size.z - face * 2.0
			_deco(Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x, size.y, top), dirt)
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x, size.y, top), "dirt")
		"barrels":
			var drum: StandardMaterial3D = _ws._material(Color(0.12, 0.3, 0.55), 0.6, 0.45)
			for i in 3:
				_cyl(Vector3(-0.62 + i * 0.62, 0.3, 0.0), 0.29, 0.88, drum, Vector3.BACK)
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"log":
			_cyl(Vector3(0.0, 0.22, 0.0), 0.22, size.x, _ws._material(Color(0.36, 0.25, 0.15), 0.0, 0.95, _ws._noise(0.8, 0.7, 1.1), 3.0), Vector3.RIGHT)
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "dirt")
		"tyre_stack":
			for i in 5:
				var t := _cyl(Vector3(0.0, 0.09 + i * 0.18, 0.0), 0.36, 0.17, _mat("dark"))
				t.rotation.y = i * 0.4
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"hay_bales":
			var hay: StandardMaterial3D = _ws._material(Color(0.82, 0.68, 0.35), 0.0, 1.0, _ws._noise(1.5, 0.75, 1.1), 3.0)
			for x in [-0.55, 0.55]:
				_deco(Vector3(x, 0.25, 0.0), Vector3(1.05, 0.5, 1.0), hay)
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "dirt")
		"car_wreck":
			var rust: StandardMaterial3D = _ws._material(Color(0.45, 0.22, 0.1), 0.4, 0.85, _ws._noise(1.2, 0.6, 1.1), 2.0)
			_deco(Vector3(0.0, 0.5, 0.0), Vector3(size.x, 0.55, size.z), rust)
			_deco(Vector3(0.0, 1.05, 0.15), Vector3(size.x - 0.15, 0.55, 2.0), rust)
			_deco(Vector3(0.0, 1.05, 0.15), Vector3(size.x - 0.12, 0.42, 1.85), _ws._material(Color(0.1, 0.12, 0.13), 0.9, 0.1))
			for x in [-size.x * 0.5, size.x * 0.5]:
				for z in [-1.3, 1.3]:
					_cyl(Vector3(x * 0.9, 0.3, z), 0.3, 0.2, _mat("dark"), Vector3.RIGHT)
			_solid_box(Vector3(0.0, 0.66, 0.0), Vector3(size.x, 1.32, size.z), "tarmac")
		"wall_concrete":
			var conc: StandardMaterial3D = _ws._material(Color(0.7, 0.7, 0.68), 0.0, 0.95, _ws._noise(0.6, 0.85, 1.05), 2.0)
			_deco(Vector3(0.0, 0.15, 0.0), Vector3(size.x, 0.3, size.z), conc)
			_deco(Vector3(0.0, 0.55, 0.0), Vector3(size.x, 0.5, size.z * 0.4), conc)
			_deco(Vector3(0.0, 0.6, size.z * 0.21), Vector3(size.x, 0.12, 0.01), _ws._material(Color(0.9, 0.1, 0.05), 0.0, 0.6))
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"wall_brick":
			var brick: StandardMaterial3D = _ws._material(Color(0.55, 0.2, 0.12), 0.0, 0.95, _ws._noise(2.5, 0.75, 1.1), 4.0)
			_deco(Vector3(0.0, size.y * 0.5, 0.0), size, brick)
			_deco(Vector3(0.0, size.y + 0.03, 0.0), Vector3(size.x + 0.04, 0.06, size.z + 0.06), _ws._material(Color(0.6, 0.6, 0.58), 0.0, 0.9))
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"fence_wood":
			for x in [-size.x * 0.5 + 0.05, 0.0, size.x * 0.5 - 0.05]:
				_deco(Vector3(x, size.y * 0.5, 0.0), Vector3(0.1, size.y, 0.1), wood)
			for y in [0.35, 0.75, 1.0]:
				_deco(Vector3(0.0, y, 0.04), Vector3(size.x, 0.1, 0.03), wood)
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"fence_mesh":
			var mesh: StandardMaterial3D = _ws._material(Color(0.7, 0.72, 0.75, 0.55), 0.7, 0.4)
			mesh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_deco(Vector3(0.0, size.y * 0.5 + 0.1, 0.0), Vector3(size.x - 0.06, size.y - 0.2, 0.02), mesh)
			for x in [-size.x * 0.5, size.x * 0.5]:
				_deco(Vector3(x, size.y * 0.5 + 0.1, 0.0), Vector3(0.04, size.y - 0.2, 0.04), steel)
				_deco(Vector3(x, 0.06, 0.0), Vector3(0.25, 0.12, 0.6), _ws._material(Color(0.55, 0.55, 0.53), 0.0, 0.95))
			_solid_box(Vector3(0.0, size.y * 0.5, 0.0), size, "tarmac")
		"cone":
			var orange: StandardMaterial3D = _ws._material(Color(1.0, 0.38, 0.05), 0.0, 0.6)
			var c := _cyl(Vector3(0.0, 0.26, 0.0), 0.16, 0.46, orange)
			(c.mesh as CylinderMesh).top_radius = 0.025
			_deco(Vector3(0.0, 0.02, 0.0), Vector3(0.36, 0.04, 0.36), orange)
			_cyl(Vector3(0.0, 0.3, 0.0), 0.095, 0.07, _ws._material(Color(0.95, 0.95, 0.95), 0.0, 0.4))
		"post":
			_cyl(Vector3(0.0, 0.5, 0.0), 0.07, 1.0, _mat("dark"))
			for y in [0.65, 0.85]:
				_cyl(Vector3(0.0, y, 0.0), 0.072, 0.09, _mat("yellow"))
		"flag_red", "flag_blue", "flag_chequered":
			_cyl(Vector3(0.0, size.y * 0.5, 0.0), 0.02, size.y, _mat("chrome"))
			var cloth: Material = _ws._material(_m()["color"], 0.0, 0.8)
			if model == "flag_chequered":
				cloth = _checker_cloth()
			var flag := _deco(Vector3(0.28, size.y - 0.22, 0.0), Vector3(0.52, 0.38, 0.01), cloth)
			flag.rotation.y = 0.15
	# The whole footprint is what you take hold of to move it.
	_ws._target(Vector3(0.0, size.y * 0.5, 0.0), size + Vector3(0.06, 0.06, 0.06), {"furniture": id}, self)


## A ramp: a solid wedge whose deck rises from the front (+Z, ground level) to the lip at the
## back, or the other way round with `rising` false. Bikes ride up it and the wheels read
## its surface.
func _wedge(center: Vector3, size: Vector3, mat: Material, rising: bool) -> void:
	var w := size.x * 0.5
	var l := size.z * 0.5
	var lo := l if rising else -l
	var hi := -l if rising else l
	var pts := PackedVector3Array([
		Vector3(-w, 0.0, lo), Vector3(w, 0.0, lo), Vector3(-w, 0.0, hi), Vector3(w, 0.0, hi),
		Vector3(-w, size.y, hi), Vector3(w, size.y, hi),
	])
	for i in pts.size():
		pts[i] += center
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt" if model == "tabletop" else "tarmac")
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [[0, 1, 5], [0, 5, 4], [2, 4, 5], [2, 5, 3], [0, 4, 2], [1, 3, 5], [0, 2, 3], [0, 3, 1]]
	for t in tris:
		for idx in t:
			st.add_vertex(pts[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_triplanar = true
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


## A solid box that stops bikes and people, with a surface for the tyres.
func _solid_box(center: Vector3, size: Vector3, surface: String) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", surface)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _checker_cloth() -> StandardMaterial3D:
	var img := Image.create(8, 6, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 6:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return m
