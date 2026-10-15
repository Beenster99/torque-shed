class_name LookPreview
extends SubViewportContainer
## A little corner of the shed on the Garage upgrades page, drawn with the finishes the garage
## has plus the one being looked at, in the colours and effects picked (UpgradeLooks): floor,
## wall panels and chequer plate, the lights, the neon sign, the showroom ceiling and trim, and
## the lounge sofa and rug when those are on show.

var _vp: SubViewport
var _room: Node3D
var _fx: Array = []    # [effect, what glows (material or label), its colour, its light, energy]
## What's drawn, for tests: upgrade id -> its looks.
var shown := {}


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 190)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(300, 190)
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.025)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.48, 0.45)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	_vp.add_child(env)
	var cam := Camera3D.new()
	var eye := Vector3(2.3, 1.55, 2.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(-0.2, 1.2, -0.6) - eye, Vector3.UP), eye)
	cam.fov = 62.0
	_vp.add_child(cam)


func _process(_delta: float) -> void:
	if _fx.is_empty() or not is_visible_in_tree():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for f in _fx:
		var fx := str(f[0])
		if f[1] is StandardMaterial3D:
			var m := f[1] as StandardMaterial3D
			if fx == "rainbow":
				m.emission = UpgradeLooks.fx_colour(t)
			else:
				m.emission_energy_multiplier = 4.0 * UpgradeLooks.fx_level(fx, t)
		else:
			var level := UpgradeLooks.fx_level(fx, t)
			var base: Color = f[2]
			(f[1] as Label3D).modulate = Color(base.r * level, base.g * level, base.b * level, base.a)
			if f[3]:
				(f[3] as Light3D).light_energy = float(f[4]) * level


## Draws the corner with the finishes in `have`, each in its looks from `looks` (id -> choices).
func show_looks(have: Dictionary, looks: Dictionary) -> void:
	shown = {}
	for id in have:
		if GarageUpgrades.has_options(str(id)):
			shown[id] = GarageUpgrades.clean_looks(str(id), looks.get(id, {}))
	if _room:
		_room.free()
	_fx.clear()
	_room = Node3D.new()
	_vp.add_child(_room)
	# The shed as it was built: grey concrete, plaster over a dark band, warm strip lights.
	var floor_m := _mat(Color(0.36, 0.37, 0.38), 0.0, 0.3, UpgradeLooks.noise(0.08, 0.92, 1.04), 6.0)
	var upper := _mat(Color(0.78, 0.76, 0.72), 0.0, 0.85, UpgradeLooks.noise(0.2, 0.9, 1.04), 2.0)
	var lower := _mat(Color(0.2, 0.24, 0.27), 0.0, 0.6)
	var tone := Color(1.0, 0.93, 0.82)
	var fixture := _mat(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	var energy := 1.2
	if shown.has("epoxy"):
		UpgradeLooks.epoxy_floor(floor_m, shown["epoxy"])
	var stripe := Color(0, 0, 0, 0)
	if shown.has("cladding"):
		stripe = UpgradeLooks.cladding(upper, lower, shown["cladding"])
	var strip_colour := Color(0, 0, 0, 0)
	if shown.has("led"):
		tone = UpgradeLooks.led_tone(shown["led"])
		fixture.emission = tone
		fixture.albedo_color = tone.lerp(Color.WHITE, 0.4)
		energy *= 1.35
		strip_colour = UpgradeLooks.led_strip(shown["led"])
	if shown.has("showroom"):
		UpgradeLooks.showroom_floor(floor_m, shown["showroom"])
	# Floor, two walls: the back (along x) and the left (along z).
	_box(Vector3(0.0, -0.05, 0.0), Vector3(6.0, 0.1, 6.0), floor_m)
	for wall in [[Vector3(0.0, 0.0, -1.6), Vector3(6.0, 0.0, 0.05)], [Vector3(-1.6, 0.0, 0.0), Vector3(0.05, 0.0, 6.0)]]:
		var at: Vector3 = wall[0]
		var size: Vector3 = wall[1]
		_box(at + Vector3(0.0, 1.9, 0.0), size + Vector3(0.0, 2.6, 0.0), upper)
		_box(at + Vector3(0.0, 0.6, 0.0), size + Vector3(0.0, 1.2, 0.0), lower)
		var face := Vector3(0.0, 0.0, 0.03) if size.x > 1.0 else Vector3(0.03, 0.0, 0.0)
		var thin := Vector3(size.x, 0.0, 0.01) if size.x > 1.0 else Vector3(0.01, 0.0, size.z)
		if stripe.a > 0.0:
			_box(at + face + Vector3(0.0, 1.23, 0.0), thin + Vector3(0.0, 0.05, 0.0), UpgradeLooks.paint(stripe, 0.5, 0.35))
		if strip_colour.a > 0.0:
			var strip := _glow(strip_colour, 4.0)
			_box(at + face + Vector3(0.0, 2.7, 0.0), thin + Vector3(0.0, 0.04, 0.0), strip)
			var fx := str(GarageUpgrades.choice("led", "fx", shown["led"]).get("id", "steady"))
			if fx != "steady":
				_fx.append([fx, strip, strip.emission, null, 0.0])
		if shown.has("showroom"):
			_box(at + face + Vector3(0.0, 0.06, 0.0), thin + Vector3(0.0, 0.12, 0.0), UpgradeLooks.showroom_trim(shown["showroom"]))
	# The ceiling light: a batten, or the showroom's honeycomb.
	if shown.has("showroom"):
		var glow := _glow(GarageUpgrades.choice("showroom", "glow", shown["showroom"]).get("color", Color.WHITE), 4.0)
		var r := float(GarageUpgrades.choice("showroom", "ceiling", shown["showroom"]).get("r", 0.7)) * 0.6
		for col in 4:
			for row in 3:
				var c := Vector3(-1.2 + col * 1.5 * r, 3.0, -1.2 + row * sqrt(3.0) * r + (sqrt(3.0) * r * 0.5 if col % 2 == 1 else 0.0))
				for k in 6:
					var a := Vector3.FORWARD.rotated(Vector3.UP, k * PI / 3.0) * r
					var b := Vector3.FORWARD.rotated(Vector3.UP, (k + 1) * PI / 3.0) * r
					var tube := _box(c + (a + b) * 0.5, Vector3(0.03, 0.02, a.distance_to(b)), glow)
					tube.basis = Basis.looking_at(b - a, Vector3.UP)
	else:
		_box(Vector3(0.4, 3.0, 0.2), Vector3(0.2, 0.05, 1.3), fixture)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.4, 2.8, 0.4)
	lamp.omni_range = 7.0
	lamp.light_energy = energy
	lamp.light_color = tone
	_room.add_child(lamp)
	# The neon sign on the back wall.
	if shown.has("signage"):
		_neon("TORQUE SHED", Vector3(0.3, 2.3, -1.55), 0.0, GarageUpgrades.choice("signage", "neon", shown["signage"]),
			str(GarageUpgrades.choice("signage", "fx", shown["signage"]).get("id", "steady")))
	# The lounge: a sofa against the left wall on its rug, and its neon over it.
	if shown.has("lounge"):
		var leather := _mat(GarageUpgrades.choice("lounge", "sofa", shown["lounge"]).get("color", Color.WHITE), 0.0, 0.45, UpgradeLooks.noise(1.0, 0.85, 1.05), 2.0)
		var rug := _mat(GarageUpgrades.choice("lounge", "rug", shown["lounge"]).get("color", Color.WHITE), 0.0, 0.95, UpgradeLooks.noise(0.8, 0.8, 1.1), 3.0)
		_box(Vector3(-0.4, 0.006, 0.6), Vector3(2.0, 0.01, 1.8), rug)
		_box(Vector3(-1.15, 0.22, 0.6), Vector3(0.8, 0.44, 1.8), leather)
		_box(Vector3(-1.48, 0.7, 0.6), Vector3(0.18, 0.55, 1.8), leather)
		_neon("CREW LOUNGE", Vector3(-1.55, 1.75, 0.6), PI * 0.5, GarageUpgrades.choice("lounge", "neon", shown["lounge"]), "steady")


## Glowing neon letters (and their light) on a wall.
func _neon(text: String, pos: Vector3, rot_y: float, c: Dictionary, fx: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = 96
	l.pixel_size = 0.0028
	l.outline_size = 12
	l.shaded = false
	_room.add_child(l)
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0.0, 0.0, 0.4).rotated(Vector3.UP, rot_y)
	light.omni_range = 2.5
	light.light_energy = 0.6
	_room.add_child(light)
	UpgradeLooks.neon(l, light, c)
	if fx != "steady":
		_fx.append([fx, l, l.modulate, light, light.light_energy])


func _mat(color: Color, metallic: float, roughness: float, tex: Texture2D = null, uv := 1.0) -> StandardMaterial3D:
	var m := UpgradeLooks.paint(color, metallic, roughness)
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv) * 0.25
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	_room.add_child(mi)
	return mi
