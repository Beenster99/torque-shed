class_name ShedPumpView
extends Node3D
## The shed's petrol pump as the crew sees it (ShedPump has the rules): a red wall-mounted
## cabinet on the outside of the front wall beside the roller door, its little lit display
## counting the litres and pounds of the sale, and the nozzle on its rubber hose. The nozzle
## hangs in its holster, follows the hand of whoever has lifted it (yours, or a mate's), and
## sits in a bike's filler with the petrol running in while they pour.
##
## The hose is one mesh: a thin tube along a sagging curve from the pump to the nozzle, made
## again only when the nozzle moves, so it costs a single draw.

## The nozzle, in its own space: the spout points along -Z from the grip, the hose goes into
## the back of it at TAIL, and the petrol comes out at TIP.
const TAIL := Vector3(0.0, 0.012, 0.13)
const TIP := Vector3(0.0, -0.035, -0.25)
const HOSE_RADIUS := 0.014
const HOSE_SIDES := 6
const HOSE_RINGS := 22
## Where the nozzle sits in your hand, from the camera (first person).
const IN_HAND := Vector3(0.2, -0.3, -0.5)

var workshop: Workshop
var nozzle: Node3D
var display: Label3D
var _hose: MeshInstance3D
var _hose_mesh: ArrayMesh
var _hose_sig := ""
var _stream: MeshInstance3D
var _display_sig := ""
var _sound: AudioStreamPlayer3D
var _was_pouring := false
var _pulled := false           # the hose pulled out of your hand: asked once


func build(shop: Workshop) -> void:
	workshop = shop
	name = "ShedPump"
	add_to_group("shed_pump")
	var x := ShedPump.X
	var z := ShedPump.WALL_Z
	var red := _mat(Color(0.66, 0.08, 0.06), 0.15, 0.4)
	var cream := _mat(Color(0.92, 0.89, 0.8), 0.0, 0.6)
	var dark := _mat(Color(0.05, 0.05, 0.055), 0.2, 0.55)
	var steel := _mat(Color(0.7, 0.71, 0.73), 0.85, 0.35)
	# The cabinet on its wall plate: a red case with a cream face, the display window up top
	# and the holster on the right, the pipe from the tank coming up out of the ground into it.
	var boxes := {red: [], cream: [], dark: [], steel: []}
	boxes[steel].append([Vector3(x, 1.25, z + 0.01), Vector3(0.7, 1.1, 0.02)])
	boxes[red].append([Vector3(x, 1.27, z + 0.15), Vector3(0.56, 0.9, 0.26)])
	boxes[red].append([Vector3(x, 1.75, z + 0.17), Vector3(0.6, 0.08, 0.3)])
	boxes[cream].append([Vector3(x, 1.24, z + 0.285), Vector3(0.48, 0.74, 0.012)])
	boxes[dark].append([Vector3(x - 0.03, 1.47, z + 0.293), Vector3(0.34, 0.2, 0.01)])
	boxes[dark].append([Vector3(x - 0.14, 0.84, z + 0.18), Vector3(0.1, 0.06, 0.1)])
	# The holster: a dark boot the spout drops into, on a bracket.
	var h := ShedPump.HOLSTER
	boxes[dark].append([h + Vector3(0.0, -0.08, 0.0), Vector3(0.09, 0.16, 0.09)])
	boxes[steel].append([h + Vector3(0.0, -0.12, -0.03), Vector3(0.05, 0.03, 0.05)])
	boxes[steel].append([Vector3(x + 0.2, 0.36, z + 0.06), Vector3(0.05, 0.72, 0.05)])
	for mat in boxes:
		add_child(_merged(boxes[mat], mat))
	display = Label3D.new()
	display.name = "Display"
	display.font_size = 34
	display.pixel_size = 0.0016
	display.modulate = Color(0.55, 1.0, 0.6)
	display.outline_size = 0
	display.shaded = false
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.position = Vector3(x - 0.03, 1.47, z + 0.3)
	add_child(display)
	var head := Label3D.new()
	head.text = "UNLEADED  %dp/L" % roundi(ShedPump.price() * 100.0)
	head.font_size = 30
	head.pixel_size = 0.0018
	head.modulate = Color(0.95, 0.95, 0.9)
	head.outline_size = 0
	head.position = Vector3(x, 1.75, z + 0.323)
	add_child(head)
	var sub := Label3D.new()
	sub.text = "TORQUE SHED\nTRADE ACCOUNT"
	sub.font_size = 22
	sub.pixel_size = 0.0018
	sub.modulate = Color(0.55, 0.08, 0.06)
	sub.outline_size = 0
	sub.position = Vector3(x - 0.05, 1.07, z + 0.293)
	add_child(sub)
	# Solid to walk into, and something to look at and lift the nozzle from.
	var body := StaticBody3D.new()
	body.name = "PumpBody"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.7, 0.3)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(x, 0.85, z + 0.15)
	add_child(body)
	var t := workshop._target(Vector3(x + 0.03, 1.2, z + 0.24), Vector3(0.66, 1.0, 0.24), {"shed_pump": "pump"}, self)
	t.name = "PumpTarget"
	_build_nozzle(red, dark, steel)
	_build_hose(dark)
	_display_text()


func _build_nozzle(body_mat: Material, dark: Material, steel: Material) -> void:
	nozzle = Node3D.new()
	nozzle.name = "Nozzle"
	add_child(nozzle)
	# The housing and its grip, the spout out of the front with its bend, the trigger under it
	# inside its guard, and the hose's swivel at the back.
	var parts := [[body_mat, Vector3(0.0, 0.0, -0.02), Vector3(0.05, 0.075, 0.12)],
		[dark, Vector3(0.0, 0.0, 0.085), Vector3(0.042, 0.06, 0.1)],
		[dark, Vector3(0.0, -0.06, 0.03), Vector3(0.012, 0.03, 0.08)],
		[steel, Vector3(0.0, -0.085, 0.04), Vector3(0.036, 0.008, 0.15)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[2]
		mi.mesh = bm
		mi.material_override = p[0]
		mi.position = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nozzle.add_child(mi)
	var spout := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.009
	cm.bottom_radius = 0.012
	cm.height = 0.17
	cm.radial_segments = 8
	cm.rings = 1
	spout.mesh = cm
	spout.material_override = steel
	spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Along -Z, bent a little down towards the tip.
	spout.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.2), Vector3(0.0, -0.018, -0.165))
	nozzle.add_child(spout)
	var swivel := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.018
	sm.bottom_radius = 0.018
	sm.height = 0.04
	sm.radial_segments = 8
	sm.rings = 1
	swivel.mesh = sm
	swivel.material_override = steel
	swivel.rotation.x = PI * 0.5
	swivel.position = TAIL + Vector3(0.0, 0.0, -0.01)
	swivel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nozzle.add_child(swivel)
	# The petrol running out of the spout while it pours, and the pump's hum and gurgle.
	_stream = MeshInstance3D.new()
	_stream.name = "Petrol"
	var st := CylinderMesh.new()
	st.top_radius = 0.005
	st.bottom_radius = 0.004
	st.height = 0.07
	st.radial_segments = 6
	st.rings = 1
	_stream.mesh = st
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.95, 0.75, 0.3, 0.55)
	amber.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amber.emission_enabled = true
	amber.emission = Color(0.5, 0.35, 0.1)
	amber.roughness = 0.1
	_stream.material_override = amber
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stream.visible = false
	add_child(_stream)
	_sound = Sfx.make_loop_player(nozzle)


func _build_hose(mat: Material) -> void:
	_hose = MeshInstance3D.new()
	_hose.name = "Hose"
	_hose_mesh = ArrayMesh.new()
	_hose.mesh = _hose_mesh
	var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.7
	_hose.material_override = m
	_hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hose)


# ---------------------------------------------------------------------------- every frame

func _process(_delta: float) -> void:
	var pt := Perf.t0()
	_update()
	Perf.add("shed_pump", pt)


## Puts the nozzle where it is, draws the hose to it if it's moved, runs the display, the
## petrol and the sound, and pulls the nozzle out of your hand if you've walked off too far.
func _update() -> void:
	var xf := nozzle_transform()
	nozzle.global_transform = xf
	var tail := xf * TAIL
	var sig := str(tail.snapped(Vector3.ONE * 0.004)) + str(xf.basis.z.snapped(Vector3.ONE * 0.05))
	if sig != _hose_sig:
		_hose_sig = sig
		_draw_hose(tail, xf.basis.z)
	var pouring := ShedPump.pouring() != 0
	if pouring != _was_pouring:
		_was_pouring = pouring
		Sfx.set_loop(_sound, "pour" if pouring else "")
		if not pouring:
			Sfx.play_at("clink", xf.origin, -6.0)
	_stream.visible = pouring
	if pouring:
		var tip := xf * TIP
		_stream.global_transform = Transform3D(Basis(), tip + Vector3.DOWN * 0.035)
		_stream.scale.y = randf_range(0.85, 1.1)
	_display_text()
	# Carried too far from the pump, the hose pulls the nozzle out of your hand.
	if ShedPump.holder() == Shed.me() and is_inside_tree():
		var w := get_tree().get_first_node_in_group("local_walker") as Node3D
		if w != null and ShedPump.overstretched(w.global_position):
			if not _pulled:
				_pulled = true
				Shed.request({"a": "pump_nozzle", "to": "pump"})
				Shed.feedback.emit("The hose won't stretch that far: the nozzle's back on the pump.", false)
		else:
			_pulled = false
	else:
		_pulled = false


## Where the nozzle is: in the filler of the bike it's pouring into, in the hand of whoever has
## it, or in its holster on the pump.
func nozzle_transform() -> Transform3D:
	var by := ShedPump.holder()
	var bike := ShedPump.pouring()
	var hand = _hand_of(by) if by != 0 else null
	if bike != 0 and Shed.bikes.has(bike):
		# Spout down into the filler, the grip leaning back towards whoever's holding it.
		var cap := ShedPump.filler_point(bike)
		var back := Vector3(ShedPump.HOSE_ROOT.x - cap.x, 0.0, ShedPump.HOSE_ROOT.z - cap.z)
		if hand is Transform3D:
			back = Vector3((hand as Transform3D).origin.x - cap.x, 0.0, (hand as Transform3D).origin.z - cap.z)
		back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		var b := Basis.looking_at((Vector3.DOWN * 0.8 - back * 0.6).normalized(), Vector3.UP)
		return Transform3D(b, cap + Vector3.UP * 0.07 - b * TIP)
	if hand is Transform3D:
		return hand
	# In the holster: spout down into the boot, the grip standing out from the wall.
	var hb := Basis.looking_at(Vector3.DOWN, Vector3.BACK)
	return Transform3D(hb, ShedPump.HOLSTER + Vector3.DOWN * 0.06 - hb * TIP)


## Where `peer`'s hand holding the nozzle is: yours in front of your camera, a mate's on their
## figure. Null when they're not to be seen.
func _hand_of(peer: int):
	if not is_inside_tree():
		return null
	if peer == Shed.me():
		var w := get_tree().get_first_node_in_group("local_walker") as Walker
		if w != null and w.camera != null:
			var cam := w.camera.global_transform
			return Transform3D(cam.basis * Basis(Vector3.RIGHT, -0.3), cam * IN_HAND)
		return null
	for rp in get_tree().get_nodes_in_group("remote_players"):
		if int(rp.get("peer")) == peer and rp.has_method("hand_transform"):
			var hx: Transform3D = rp.hand_transform()
			return Transform3D(hx.basis.orthonormalized() * Basis(Vector3.RIGHT, -0.3), hx.origin)
	return null


## The display: this sale's pounds and litres, and the price a litre.
func _display_text() -> void:
	var litres := float(Shed.pump.get("litres", 0.0))
	var cost := float(Shed.pump.get("cost", 0.0))
	var sig := "%.2f|%.2f" % [litres, cost]
	if sig == _display_sig:
		return
	_display_sig = sig
	display.text = "£%.2f\n%.2f L" % [cost, litres]


## The hose from where it leaves the pump to the back of the nozzle (`out`: the way the
## nozzle's back faces), sagging with the slack and lying on the ground where it reaches it.
func _draw_hose(tail: Vector3, out: Vector3) -> void:
	var a := ShedPump.HOSE_ROOT
	var d := tail
	var slack := clampf(ShedPump.HOSE - a.distance_to(d), 0.0, ShedPump.HOSE)
	var sag := clampf(slack * 0.45, 0.08, 1.1)
	var b := a + Vector3(0.0, -sag, 0.12)
	var c := d + out * 0.22 + Vector3(0.0, -sag * 0.8, 0.0)
	var pts := PackedVector3Array()
	for i in HOSE_RINGS:
		var t := float(i) / (HOSE_RINGS - 1)
		var u := 1.0 - t
		var p := a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t
		p.y = maxf(p.y, HOSE_RADIUS + 0.01)
		pts.append(p)
	_hose_mesh.clear_surfaces()
	_hose_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tube(pts, HOSE_RADIUS, HOSE_SIDES))
	# Drawn in world space: the hose's node stays at the origin.
	_hose.global_transform = Transform3D.IDENTITY


## A tube of `radius` round a line of points, `sides` round: mesh arrays.
static func tube(pts: PackedVector3Array, radius: float, sides: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := pts.size()
	var across := Vector3.RIGHT
	for i in n:
		var along := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		# Carry the side on from the last ring, so the tube doesn't twist.
		var s := across - along * across.dot(along)
		if s.length() < 0.01:
			s = along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT)
		s = s.normalized()
		across = s
		var up := along.cross(s)
		for k in sides:
			var ang := TAU * k / sides
			var nrm := s * cos(ang) + up * sin(ang)
			verts.append(pts[i] + nrm * radius)
			normals.append(nrm)
	for i in n - 1:
		for k in sides:
			var a0 := i * sides + k
			var a1 := i * sides + (k + 1) % sides
			idx.append_array([a0, a1, a0 + sides, a1, a1 + sides, a0 + sides])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


# ---------------------------------------------------------------------------- building

func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Boxes ([centre, size]) of one material as one mesh: one draw for them all.
func _merged(boxes: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bx in boxes:
		var bm := BoxMesh.new()
		bm.size = bx[1]
		st.append_from(bm, 0, Transform3D(Basis(), bx[0]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi
