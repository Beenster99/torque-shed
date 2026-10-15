class_name Trinkets
extends RefCounted
## Trinkets: decorations for the shed bought with a player's own money in the Esc menu's Shop
## tab. Once bought one arrives outside the roller door like any other order and belongs to
## the shed: it's shed equipment of kind "trinket" (see Equipment.get_model), carried, placed,
## turned, snapped and scrapped the same way as posters and kit, and saved with the shed.
## Small ones go down on a bench or the floor wherever you hold them; "wall" ones hang up.
##
## Each model: name, price (pounds), size (width, height, depth in metres), desc, and `wall`
## for the ones that hang. build() draws them (+Z is the front; wall ones from the wall out).

const MODELS := {
	"trinket_bobblehead": {"kind": "trinket", "name": "Bobblehead racer", "price": 15, "size": Vector3(0.12, 0.22, 0.12),
		"desc": "A little racer with a big nodding helmet. Put it on the bench and it nods along while you work."},
	"trinket_gnome": {"kind": "trinket", "name": "Biker gnome", "price": 18, "size": Vector3(0.22, 0.4, 0.22),
		"desc": "A garden gnome in a leather jacket and an open-face lid. Guards the door."},
	"trinket_plant": {"kind": "trinket", "name": "Potted plant", "price": 25, "size": Vector3(0.45, 0.95, 0.45),
		"desc": "A big leafy plant in a terracotta pot. Somebody has to water it."},
	"trinket_photo": {"kind": "trinket", "name": "Framed photo", "price": 30, "size": Vector3(0.46, 0.36, 0.03), "wall": true,
		"desc": "A framed photo of a bike on a mountain road at sunset. Hangs on a wall."},
	"trinket_lava": {"kind": "trinket", "name": "Lava lamp", "price": 35, "size": Vector3(0.14, 0.42, 0.14),
		"desc": "Orange goo rising and falling in a glowing lamp. Very seventies."},
	"trinket_clock": {"kind": "trinket", "name": "Workshop wall clock", "price": 40, "size": Vector3(0.42, 0.42, 0.06), "wall": true,
		"desc": "A big station clock that keeps the shed's time. Hangs on a wall."},
	"trinket_trophy": {"kind": "trinket", "name": "Gold race trophy", "price": 60, "size": Vector3(0.2, 0.4, 0.2),
		"desc": "A gold cup on a wooden plinth. Nobody remembers what it was for."},
	"trinket_rug": {"kind": "trinket", "name": "Chequered flag rug", "price": 70, "size": Vector3(1.6, 0.012, 1.0),
		"desc": "A chequered flag rug for the floor. Lie on it to work under a bike."},
	"trinket_radio": {"kind": "trinket", "name": "Toolbox radio", "price": 85, "size": Vector3(0.4, 0.28, 0.2),
		"desc": "A yellow site radio in a roll cage, built to be dropped off a scaffold."},
	"trinket_bike_model": {"kind": "trinket", "name": "Mini bike model", "price": 120, "size": Vector3(0.36, 0.22, 0.12),
		"desc": "A die-cast model of a café racer on a little display stand."},
	"trinket_neon": {"kind": "trinket", "name": "Neon shed sign", "price": 180, "size": Vector3(0.9, 0.36, 0.06), "wall": true,
		"desc": "A pink neon sign that says TORQUE SHED. Glows in the dark. Hangs on a wall."},
}


## Every trinket, cheapest first.
static func all() -> Array:
	var out := MODELS.keys()
	out.sort_custom(func(a, b): return int(MODELS[a]["price"]) < int(MODELS[b]["price"]))
	return out


static func price(id: String) -> int:
	return int(MODELS.get(id, {}).get("price", 0))


## Buys trinket `id` with the player's own money and has it delivered to the shed (the order
## goes to the host like any other). "" when bought, else why not; nothing is paid when the
## shed can't take the order.
static func buy(id: String) -> String:
	if not MODELS.has(id):
		return "That isn't in the shop."
	var order := {"a": "order_furniture", "model": id}
	var why := Shed.check(Shed.me(), order)
	if why != "":
		return why
	var cost := price(id)
	if not RiderGear.pay(cost, "Trinket: %s" % MODELS[id]["name"]):
		return "You can't afford the %s (%s, you have %s)." % [str(MODELS[id]["name"]).to_lower(), TvChannels.money_text(cost),
			TvChannels.money_text(Progress.money())]
	Shed.request(order)
	return ""


# ---------------------------------------------------------------------------- drawing

static func _mat(c: Color, metallic := 0.0, roughness := 0.6, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


static func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	return RiderFigure.box(parent, center, size, mat)


static func _ball(parent: Node3D, center: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	return RiderFigure.mesh(parent, RiderFigure.sphere(radius), mat, center)


static func _cyl(parent: Node3D, center: Vector3, top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 20
	return RiderFigure.mesh(parent, c, mat, center)


## Draws trinket `id` into `parent`: on the floor (or a bench) from y = 0 up, or for a wall one
## from the wall (z = 0) out towards +Z.
static func build(parent: Node3D, id: String) -> void:
	var m: Dictionary = MODELS.get(id, {})
	var size: Vector3 = m.get("size", Vector3.ONE * 0.2)
	match id:
		"trinket_bobblehead":
			_cyl(parent, Vector3(0.0, 0.01, 0.0), 0.05, 0.055, 0.02, _mat(Color(0.1, 0.1, 0.12)))
			var body := Node3D.new()
			parent.add_child(body)
			RiderFigure.limb(body, Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.1, 0.0), 0.025, RiderFigure.material("jacket_kestrel", Color.RED))
			var bob := Bobble.new()
			bob.position = Vector3(0.0, 0.13, 0.0)
			parent.add_child(bob)
			RiderFigure.helmet(bob, Vector3(0.0, 0.035, 0.0), 0.045, "helmet_sprint", Color.RED, 1, true)
		"trinket_gnome":
			_cyl(parent, Vector3(0.0, 0.1, 0.0), 0.08, 0.1, 0.2, RiderFigure.material("jacket_ironside", Color.BLACK))
			_ball(parent, Vector3(0.0, 0.24, 0.0), 0.065, _mat(RiderFigure.SKIN))
			_cyl(parent, Vector3(0.0, 0.2, -0.05), 0.03, 0.06, 0.1, _mat(Color(0.95, 0.95, 0.95)))   # the beard
			RiderFigure.helmet(parent, Vector3(0.0, 0.27, 0.0), 0.075, "helmet_open_cream", Color.WHITE, 1, false)
			for side in [-1.0, 1.0]:
				_box(parent, Vector3(0.05 * side, 0.015, -0.02), Vector3(0.06, 0.03, 0.1), _mat(Color(0.08, 0.06, 0.05)))
		"trinket_plant":
			_cyl(parent, Vector3(0.0, 0.16, 0.0), 0.18, 0.13, 0.32, _mat(Color(0.72, 0.36, 0.2), 0.0, 0.85))
			_cyl(parent, Vector3(0.0, 0.31, 0.0), 0.16, 0.16, 0.02, _mat(Color(0.2, 0.13, 0.08), 0.0, 1.0))
			_cyl(parent, Vector3(0.0, 0.45, 0.0), 0.015, 0.02, 0.3, _mat(Color(0.3, 0.22, 0.1)))
			var leaf := _mat(Color(0.16, 0.45, 0.14), 0.0, 0.55)
			var dark := _mat(Color(0.1, 0.32, 0.1), 0.0, 0.55)
			for i in 9:
				var a := i * TAU / 9.0
				var r := 0.12 + 0.05 * float(i % 2)
				var l := _ball(parent, Vector3(cos(a) * r, 0.62 + 0.08 * float(i % 3), sin(a) * r), 0.13, leaf if i % 2 == 0 else dark)
				l.scale = Vector3(1.0, 0.55, 1.0)
			_ball(parent, Vector3(0.0, 0.8, 0.0), 0.14, leaf)
		"trinket_photo":
			var frame := _mat(Color(0.28, 0.18, 0.1), 0.0, 0.5)
			_box(parent, Vector3(0.0, 0.0, 0.012), Vector3(size.x, size.y, 0.024), frame)
			var pic := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(size.x - 0.07, size.y - 0.07)
			pic.mesh = q
			var pm := StandardMaterial3D.new()
			pm.albedo_texture = photo_texture()
			pm.roughness = 0.2
			pic.material_override = pm
			pic.position = Vector3(0.0, 0.0, 0.026)
			parent.add_child(pic)
		"trinket_lava":
			var metal := _mat(Color(0.6, 0.62, 0.66), 0.9, 0.25)
			_cyl(parent, Vector3(0.0, 0.05, 0.0), 0.035, 0.065, 0.1, metal)
			var glass := _mat(Color(0.95, 0.5, 0.15, 0.55), 0.0, 0.1, 0.6)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_cyl(parent, Vector3(0.0, 0.22, 0.0), 0.028, 0.048, 0.24, glass)
			_cyl(parent, Vector3(0.0, 0.37, 0.0), 0.018, 0.03, 0.06, metal)
			var lava := Lava.new()
			parent.add_child(lava)
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.55, 0.2)
			glow.light_energy = 0.4
			glow.omni_range = 1.2
			glow.position = Vector3(0.0, 0.22, 0.0)
			parent.add_child(glow)
		"trinket_clock":
			var face := _mat(Color(0.95, 0.94, 0.9), 0.0, 0.4)
			var rim := _mat(Color(0.08, 0.08, 0.09), 0.6, 0.3)
			var disc := _cyl(parent, Vector3(0.0, 0.0, 0.02), size.x * 0.5, size.x * 0.5, 0.04, rim)
			disc.rotation.x = PI * 0.5
			var inner := _cyl(parent, Vector3(0.0, 0.0, 0.042), size.x * 0.44, size.x * 0.44, 0.004, face)
			inner.rotation.x = PI * 0.5
			for h in 12:
				var a := h * TAU / 12.0
				var tick := _box(parent, Vector3(sin(a), cos(a), 0.0) * size.x * 0.38 + Vector3(0.0, 0.0, 0.046),
					Vector3(0.012, 0.035 if h % 3 == 0 else 0.02, 0.003), rim)
				tick.rotation.z = -a
			var hands := Clock.new()
			hands.position = Vector3(0.0, 0.0, 0.05)
			hands.radius = size.x * 0.44
			parent.add_child(hands)
		"trinket_trophy":
			var gold := _mat(Color(0.95, 0.7, 0.2), 1.0, 0.2)
			_box(parent, Vector3(0.0, 0.04, 0.0), Vector3(0.14, 0.08, 0.14), _mat(Color(0.3, 0.18, 0.08), 0.0, 0.4))
			_box(parent, Vector3(0.0, 0.05, 0.071), Vector3(0.08, 0.03, 0.002), gold)
			_cyl(parent, Vector3(0.0, 0.13, 0.0), 0.015, 0.04, 0.1, gold)
			_cyl(parent, Vector3(0.0, 0.28, 0.0), 0.085, 0.035, 0.2, gold)
			for side in [-1.0, 1.0]:
				var handle := MeshInstance3D.new()
				var t := TorusMesh.new()
				t.inner_radius = 0.035
				t.outer_radius = 0.048
				handle.mesh = t
				handle.material_override = gold
				handle.position = Vector3(0.085 * side, 0.29, 0.0)
				handle.rotation.x = PI * 0.5
				parent.add_child(handle)
		"trinket_rug":
			var rug := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(size.x, size.z)
			rug.mesh = q
			rug.rotation.x = -PI * 0.5
			rug.position.y = 0.006
			var rm := StandardMaterial3D.new()
			rm.albedo_texture = RiderFigure.pattern_texture("check", Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.06), Color.BLACK)
			rm.uv1_scale = Vector3(1.0, 1.25, 1.0)
			rm.roughness = 1.0
			rug.material_override = rm
			parent.add_child(rug)
		"trinket_radio":
			var yellow := _mat(Color(0.95, 0.72, 0.05), 0.1, 0.5)
			var black := _mat(Color(0.07, 0.07, 0.08), 0.2, 0.6)
			_box(parent, Vector3(0.0, 0.13, 0.0), Vector3(0.32, 0.2, 0.14), yellow)
			var grille := _cyl(parent, Vector3(-0.07, 0.13, 0.071), 0.06, 0.06, 0.004, black)
			grille.rotation.x = PI * 0.5
			_box(parent, Vector3(0.08, 0.16, 0.071), Vector3(0.1, 0.05, 0.004), _mat(Color(0.35, 0.8, 0.95), 0.0, 0.2, 0.8))
			for x in [-0.17, 0.17]:
				for z in [-0.08, 0.08]:
					RiderFigure.tube(parent, Vector3(x, 0.0, z), Vector3(x, 0.26, z), 0.012, black)
			for z in [-0.08, 0.08]:
				RiderFigure.tube(parent, Vector3(-0.17, 0.26, z), Vector3(0.17, 0.26, z), 0.012, black)
			RiderFigure.tube(parent, Vector3(0.13, 0.25, -0.05), Vector3(0.13, 0.42, -0.05), 0.004, _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2))
		"trinket_bike_model":
			_box(parent, Vector3(0.0, 0.01, 0.0), Vector3(0.36, 0.02, 0.12), _mat(Color(0.05, 0.05, 0.06), 0.3, 0.3))
			var paint := _mat(Color(0.7, 0.08, 0.06), 0.4, 0.2)
			var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15)
			var tyre := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.8)
			for x in [-0.12, 0.12]:
				var w := MeshInstance3D.new()
				var t := TorusMesh.new()
				t.inner_radius = 0.042
				t.outer_radius = 0.055
				w.mesh = t
				w.material_override = tyre
				w.position = Vector3(x, 0.075, 0.0)
				w.rotation.x = PI * 0.5
				parent.add_child(w)
			RiderFigure.tube(parent, Vector3(-0.12, 0.075, 0.0), Vector3(-0.07, 0.17, 0.0), 0.006, chrome)    # forks
			RiderFigure.tube(parent, Vector3(0.12, 0.075, 0.0), Vector3(0.0, 0.1, 0.0), 0.006, chrome)        # swingarm
			RiderFigure.tube(parent, Vector3(-0.07, 0.16, 0.0), Vector3(0.08, 0.14, 0.0), 0.008, paint)       # frame
			var tank := _ball(parent, Vector3(-0.02, 0.165, 0.0), 0.045, paint)
			tank.scale = Vector3(1.4, 0.6, 0.7)
			_box(parent, Vector3(0.07, 0.15, 0.0), Vector3(0.08, 0.015, 0.035), _mat(Color(0.1, 0.07, 0.05)))
			_box(parent, Vector3(0.0, 0.1, 0.0), Vector3(0.06, 0.05, 0.04), chrome)                           # engine
			RiderFigure.tube(parent, Vector3(-0.08, 0.18, -0.03), Vector3(-0.08, 0.18, 0.03), 0.004, chrome)  # bars
		"trinket_neon":
			var board := _mat(Color(0.05, 0.05, 0.06, 0.7), 0.0, 0.2)
			board.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_box(parent, Vector3(0.0, 0.0, 0.01), Vector3(size.x, size.y, 0.02), board)
			for i in 2:
				var l := Label3D.new()
				l.text = ["TORQUE", "SHED"][i]
				l.font_size = 64 if i == 0 else 44
				l.pixel_size = 0.0035
				l.modulate = Color(1.0, 0.35, 0.75) if i == 0 else Color(0.4, 0.9, 1.0)
				l.outline_modulate = Color(1.0, 0.2, 0.6, 0.6) if i == 0 else Color(0.2, 0.7, 1.0, 0.6)
				l.outline_size = 14
				l.shaded = false
				l.double_sided = false
				l.position = Vector3(0.0, 0.06 if i == 0 else -0.1, 0.04)
				parent.add_child(l)
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.4, 0.75)
			glow.light_energy = 0.8
			glow.omni_range = 2.5
			glow.position = Vector3(0.0, 0.0, 0.3)
			parent.add_child(glow)


static var _photo: ImageTexture

## The framed photo: a bike on a mountain road at sunset, painted pixel by pixel.
static func photo_texture() -> ImageTexture:
	if _photo:
		return _photo
	var w := 96
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := float(y) / h
			var c := Color(0.95, 0.55, 0.25).lerp(Color(0.35, 0.25, 0.55), clampf(1.0 - v * 1.8, 0.0, 1.0))
			var hill := 0.5 + 0.08 * sin(x * 0.11) + 0.05 * sin(x * 0.31 + 1.0)
			if v > hill:
				c = Color(0.18, 0.2, 0.28).lerp(Color(0.1, 0.16, 0.12), (v - hill) * 3.0)
			# The road, winding off into the hills.
			var road_x := 0.5 + (v - 0.6) * 0.6 * sin(v * 9.0)
			var half := 0.02 + (v - 0.55) * 0.5
			if v > 0.6 and absf(float(x) / w - road_x) < half:
				c = Color(0.22, 0.22, 0.24)
			if absf(float(x) / w - 0.75) < 0.07 and absf(v - 0.25) < 0.09 and Vector2(float(x) / w - 0.75, v - 0.25).length() < 0.07:
				c = Color(1.0, 0.85, 0.5)   # the sun
			img.set_pixel(x, y, c)
	# The bike and rider, black against the road.
	for p in [[44, 58, 5], [56, 58, 5], [50, 53, 4], [52, 49, 3]]:
		for dy in range(-p[2], p[2] + 1):
			for dx in range(-p[2], p[2] + 1):
				if dx * dx + dy * dy <= p[2] * p[2]:
					img.set_pixel(clampi(p[0] + dx, 0, w - 1), clampi(p[1] + dy, 0, h - 1), Color(0.03, 0.03, 0.04))
	_photo = ImageTexture.create_from_image(img)
	return _photo


## The bobblehead's head: nods on its spring.
class Bobble extends Node3D:
	var _t := randf() * 10.0

	func _process(delta: float) -> void:
		_t += delta
		rotation = Vector3(sin(_t * 5.0) * 0.18, 0.0, sin(_t * 3.1) * 0.1)


## The wall clock's hands, showing the shed's time of day (Daylight).
class Clock extends Node3D:
	var radius := 0.2
	var _hour: Node3D
	var _minute: Node3D

	func _ready() -> void:
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.05, 0.05, 0.06)
		_hour = _hand(radius * 0.55, 0.02, black)
		_minute = _hand(radius * 0.85, 0.012, black)

	func _hand(length: float, width: float, mat: Material) -> Node3D:
		var pivot := Node3D.new()
		add_child(pivot)
		RiderFigure.box(pivot, Vector3(0.0, length * 0.4, 0.0), Vector3(width, length, 0.004), mat)
		return pivot

	func _process(_delta: float) -> void:
		var hours := 9.0
		if Daylight.current:
			hours = Daylight.current.hours
		_hour.rotation.z = -fmod(hours, 12.0) / 12.0 * TAU
		_minute.rotation.z = -fmod(hours, 1.0) * TAU


## The lava lamp's blobs, rising and falling.
class Lava extends Node3D:
	var _blobs: Array = []
	var _t := randf() * 20.0

	func _ready() -> void:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.3, 0.05)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.05)
		m.emission_energy_multiplier = 1.5
		for i in 4:
			_blobs.append(RiderFigure.mesh(self, RiderFigure.sphere(0.014 + 0.004 * i), m, Vector3.ZERO))

	func _process(delta: float) -> void:
		_t += delta
		for i in _blobs.size():
			var phase := _t * (0.25 + 0.07 * i) + i * 1.7
			var y := 0.12 + 0.18 * (0.5 + 0.5 * sin(phase))
			(_blobs[i] as Node3D).position = Vector3(0.008 * sin(phase * 2.3), y, 0.008 * cos(phase * 1.7))
