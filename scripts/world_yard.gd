class_name WorldYard
extends Node3D
## The Build Yard behind the shed, laid out as a test area for the bikes you build:
##  - an acceleration lane (two lanes, the "drag strip") from a start line to a chequered
##    brake line, then a braking zone marked every 5 m and a run-off,
##  - a skid pad circle east of the sales office for steady-state cornering,
##  - a slalom line and a jump line (cones, posts and ramps from Shed's yard kit),
##  - a slow-control area west of the shed: a U-turn box, a figure of eight and a lane of
##    speed humps for the suspension,
##  - an obstacle corner, and a marked drop-off box where ordered yard kit is left.
## It's reached from the shed's forecourt on the High Street (see WorldTown) by a lane either
## side of the buildings (GROUND: the yard, and the forecourt and lanes, all one level slab).
## The slab's top is flush with the grass round it (see WorldTerrain.HOME_LEVEL), so there's
## no kerb at its edge. The loop's start gantry stands where the loop passes the town.

const CENTER := Vector2(0.0, -10.0)
const HALF := Vector2(65.0, 45.0)
## The acceleration lane runs along x from START_X to the brake line at BRAKE_X, then the
## braking zone (marked every 5 m) to BRAKE_END, between z LANE_Z.x and LANE_Z.y.
const START_X := -58.0
const BRAKE_X := 0.0
const BRAKE_END := 40.0
const LANE_Z := Vector2(-14.0, -6.0)
const SKID_PAD := Vector3(50.0, 0.0, -36.0)
const SKID_RADIUS := 11.0
const SLALOM_Z := 2.0
const SLALOM_X := [-24.0, -18.0, -12.0, -6.0, 0.0, 6.0]
const JUMP_Z := 13.0
const HUMPS_X := [-56.0, -50.0, -44.0, -38.0, -32.0]
const HUMPS_Z := -19.0
const UTURN := Rect2(-62.0, -31.0, 38.0, 7.0)
const FIGURE_EIGHT := [Vector2(-52.0, -44.0), Vector2(-38.0, -44.0)]
const FIGURE_EIGHT_R := 6.0
const DROP_OFF := Rect2(-62.0, -5.0, 32.0, 16.0)
## The level slab, as x/z rectangles: the yard itself, and the forecourt along the front of the
## buildings out to the High Street's kerb with the lanes either side of them up to the yard.
const GROUND: Array[Rect2] = [Rect2(-65.0, -55.0, 130.0, 90.0), Rect2(-45.0, 35.0, 90.0, 53.5)]
## The lanes from the forecourt up to the yard, either side of the buildings (x/z rectangles).
const LANES: Array[Rect2] = [Rect2(-45.0, 35.0, 12.0, 30.0), Rect2(33.0, 35.0, 12.0, 30.0)]

var _paint := SurfaceTool.new()
var _labels := []


## The yard kit a new shed starts with, laid out on the test area: [kind, transform, model]
## for Shed to make into furniture. Ramps' decks rise towards their local -Z.
static func starting_kit() -> Array:
	var east := Basis(Vector3.UP, -PI * 0.5)    # ridden heading +x
	var west := Basis(Vector3.UP, PI * 0.5)
	var north := Basis()
	var kit := []
	# The jump line along z = JUMP_Z, ridden east: the big ramp onto a landing.
	kit.append(["ramp", Transform3D(east, Vector3(-20.0, 0.0, JUMP_Z)), "ramp_large"])
	kit.append(["ramp", Transform3D(west, Vector3(-6.0, 0.0, JUMP_Z)), "ramp_landing"])
	kit.append(["marker", Transform3D(north, Vector3(-1.0, 0.0, JUMP_Z + 2.4)), "flag_chequered"])
	# Smaller kickers and the tabletop alongside it.
	kit.append(["ramp", Transform3D(east, Vector3(-22.0, 0.0, 8.5)), "ramp_small"])
	kit.append(["ramp", Transform3D(east, Vector3(-12.0, 0.0, 8.5)), "ramp_medium"])
	kit.append(["obstacle", Transform3D(east, Vector3(4.0, 0.0, 8.5)), "tabletop"])
	# The slalom: flags at the gate, then cones and posts on their painted spots.
	kit.append(["marker", Transform3D(north, Vector3(-30.0, 0.0, SLALOM_Z - 2.2)), "flag_red"])
	kit.append(["marker", Transform3D(north, Vector3(-30.0, 0.0, SLALOM_Z + 2.2)), "flag_blue"])
	for i in SLALOM_X.size():
		kit.append(["marker", Transform3D(north, Vector3(SLALOM_X[i], 0.0, SLALOM_Z)), "cone" if i % 3 != 2 else "post"])
	# The obstacle corner: things to ride round and over, and walls and fences.
	kit.append(["obstacle", Transform3D(north, Vector3(44.0, 0.0, 0.0)), "barrels"])
	kit.append(["obstacle", Transform3D(north, Vector3(49.0, 0.0, 0.0)), "log"])
	kit.append(["obstacle", Transform3D(north, Vector3(54.0, 0.0, 0.0)), "hay_bales"])
	kit.append(["obstacle", Transform3D(north, Vector3(59.0, 0.0, 0.0)), "tyre_stack"])
	kit.append(["obstacle", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(58.0, 0.0, 7.0)), "car_wreck"])
	kit.append(["barrier", Transform3D(north, Vector3(43.0, 0.0, 14.0)), "wall_concrete"])
	kit.append(["barrier", Transform3D(north, Vector3(45.2, 0.0, 14.0)), "wall_concrete"])
	kit.append(["barrier", Transform3D(north, Vector3(49.0, 0.0, 14.0)), "wall_brick"])
	kit.append(["barrier", Transform3D(north, Vector3(53.0, 0.0, 14.0)), "fence_wood"])
	kit.append(["barrier", Transform3D(north, Vector3(57.5, 0.0, 14.0)), "fence_mesh"])
	return kit


func build(world: World) -> void:
	name = "Yard"
	_build_slab(world)
	_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	_mark_acceleration_lane()
	_mark_skid_pad()
	_mark_slalom_and_jumps()
	_mark_slow_area()
	_mark_drop_off()
	_paint.generate_normals()
	var paint := MeshInstance3D.new()
	paint.name = "Markings"
	paint.mesh = _paint.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	paint.material_override = world._wet(mat, 0.7)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paint)
	_build_humps(world)
	_build_cones()
	_build_boards()
	_build_gantry(world)


## The concrete slab: solid to the tyres, its top at y = 0.
func _build_slab(world: World) -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.38, 0.36, 0.33)
	concrete.roughness = 0.97
	concrete.albedo_texture = world._noise_texture(0.15, Color(0.82, 0.82, 0.82), Color(1.08, 1.08, 1.08))
	concrete.uv1_scale = Vector3(12.0, 12.0, 12.0)
	world._wet(concrete, 0.8)
	for k in GROUND.size():
		var r: Rect2 = GROUND[k]
		var body := StaticBody3D.new()
		body.name = "Slab" if k == 0 else "Forecourt"
		body.set_meta("surface", "tarmac")
		body.position = Vector3(r.get_center().x, -0.25, r.get_center().y)
		var shape := BoxShape3D.new()
		shape.size = Vector3(r.size.x, 0.5, r.size.y)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = concrete
		body.add_child(mi)
		add_child(body)


# ---------------------------------------------------------------------------- paint

const WHITE := Color(0.93, 0.93, 0.9)
const YELLOW := Color(0.95, 0.8, 0.15)
const RED := Color(0.8, 0.15, 0.1)
const AMBER := Color(0.95, 0.55, 0.1)
const GREEN := Color(0.2, 0.6, 0.25)
const BLUE := Color(0.2, 0.4, 0.8)


## A painted rectangle centred at (x, z), `sx` by `sz`, turned `angle` about up.
func _rect(x: float, z: float, sx: float, sz: float, color: Color, angle := 0.0, lift := 0.006) -> void:
	var b := Basis(Vector3.UP, angle)
	var c := Vector3(x, lift, z)
	var corners := [Vector3(-sx, 0, -sz), Vector3(sx, 0, -sz), Vector3(sx, 0, sz), Vector3(-sx, 0, sz)]
	var pts := []
	for k in corners:
		pts.append(c + b * (k * 0.5))
	_paint.set_color(color)
	for i in [0, 1, 2, 0, 2, 3]:
		_paint.add_vertex(pts[i])


## A painted ring (or dashed ring) of radius `r` and line width `w`.
func _ring(center: Vector3, r: float, w: float, color: Color, dashes := 0) -> void:
	var segs := 96
	for i in segs:
		if dashes > 0 and (i * dashes / segs) % 2 == 1:
			continue
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var pts := [Vector3(cos(a0) * (r - w * 0.5), 0, sin(a0) * (r - w * 0.5)), Vector3(cos(a1) * (r - w * 0.5), 0, sin(a1) * (r - w * 0.5)),
			Vector3(cos(a1) * (r + w * 0.5), 0, sin(a1) * (r + w * 0.5)), Vector3(cos(a0) * (r + w * 0.5), 0, sin(a0) * (r + w * 0.5))]
		_paint.set_color(color)
		for k in [0, 3, 2, 0, 2, 1]:
			_paint.add_vertex(center + Vector3(0.0, 0.006, 0.0) + pts[k])


## A painted spot (a filled circle) for a cone or a marker.
func _spot(x: float, z: float, r: float, color: Color) -> void:
	var c := Vector3(x, 0.007, z)
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		_paint.set_color(color)
		_paint.add_vertex(c)
		_paint.add_vertex(c + Vector3(cos(a0), 0, sin(a0)) * r)
		_paint.add_vertex(c + Vector3(cos(a1), 0, sin(a1)) * r)


## The outline of `rect` (x, z) in lines `w` wide.
func _outline(rect: Rect2, w: float, color: Color) -> void:
	var c := rect.get_center()
	_rect(c.x, rect.position.y, rect.size.x, w, color)
	_rect(c.x, rect.end.y, rect.size.x, w, color)
	_rect(rect.position.x, c.y, w, rect.size.y, color)
	_rect(rect.end.x, c.y, w, rect.size.y, color)


## Flat painted words on the ground, readable riding towards -Z turned by `angle`.
func _words(text: String, at: Vector3, size: int, color: Color, angle := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = at + Vector3(0.0, 0.012, 0.0)
	l.rotation = Vector3(-PI * 0.5, angle, 0.0)
	l.visibility_range_end = 120.0
	add_child(l)


func _mark_acceleration_lane() -> void:
	var mid := (LANE_Z.x + LANE_Z.y) * 0.5
	var run_end := HALF.x - 3.0
	# Lane edges and the dashed divider.
	for z in [LANE_Z.x, LANE_Z.y]:
		_rect((START_X + run_end) * 0.5, z, run_end - START_X, 0.18, WHITE)
	var x := START_X
	while x < BRAKE_X:
		_rect(x + 1.5, mid, 3.0, 0.15, YELLOW)
		x += 6.0
	# Start line, with a box for each lane.
	_rect(START_X, mid, 0.5, LANE_Z.y - LANE_Z.x, WHITE)
	for z in [LANE_Z.x + 2.0, LANE_Z.y - 2.0]:
		_words("START", Vector3(START_X + 3.5, 0.0, z), 160, WHITE, -PI * 0.5)
	# Every 10 m to the brake line.
	for d in range(10, int(BRAKE_X - START_X), 10):
		_rect(START_X + d, LANE_Z.x - 0.6, 0.3, 1.2, WHITE)
		_rect(START_X + d, LANE_Z.y + 0.6, 0.3, 1.2, WHITE)
		_words("%d m" % d, Vector3(START_X + d, 0.0, LANE_Z.x - 2.0), 90, WHITE, -PI * 0.5)
	# The braking zone: a line every 5 m on bands of green, amber and red.
	for d in range(0, int(BRAKE_END - BRAKE_X), 5):
		var band := GREEN if d < 15 else (AMBER if d < 25 else RED)
		_rect(BRAKE_X + d + 2.5, LANE_Z.x - 0.9, 5.0, 1.2, band)
		_rect(BRAKE_X + d + 2.5, LANE_Z.y + 0.9, 5.0, 1.2, band)
		if d > 0:
			_rect(BRAKE_X + d, mid, 0.14, LANE_Z.y - LANE_Z.x, WHITE)
			_words("%d" % d, Vector3(BRAKE_X + d + 0.8, 0.0, mid - 2.0), 110, WHITE, -PI * 0.5)
	_words("BRAKE", Vector3(BRAKE_X - 3.0, 0.0, mid - 2.0), 150, WHITE, -PI * 0.5)
	_words("BRAKE", Vector3(BRAKE_X - 3.0, 0.0, mid + 2.0), 150, WHITE, -PI * 0.5)
	# The run-off: hatched.
	var h := BRAKE_END + 1.0
	while h < run_end - 1.0:
		_rect(h, mid, 0.4, LANE_Z.y - LANE_Z.x - 1.0, Color(0.85, 0.85, 0.8), 0.6)
		h += 2.5
	_rect(BRAKE_END, mid, 0.3, LANE_Z.y - LANE_Z.x, WHITE)
	# The chequered brake line.
	var line := Node3D.new()
	line.name = "BrakeLine"
	add_child(line)
	for i in 16:
		for j in 2:
			_rect(BRAKE_X - 0.25 + j * 0.5, LANE_Z.x + 0.25 + i * 0.5, 0.5, 0.5,
				Color(0.05, 0.05, 0.05) if (i + j) % 2 == 0 else Color(0.95, 0.95, 0.95), 0.0, 0.008)


func _mark_skid_pad() -> void:
	_ring(SKID_PAD, SKID_RADIUS, 0.3, YELLOW)
	_ring(SKID_PAD, SKID_RADIUS - 3.0, 0.15, WHITE, 24)
	_ring(SKID_PAD, SKID_RADIUS + 3.0, 0.15, WHITE, 24)
	for i in 8:
		var a := TAU * i / 8.0
		_spot(SKID_PAD.x + cos(a) * (SKID_RADIUS - 1.5), SKID_PAD.z + sin(a) * (SKID_RADIUS - 1.5), 0.3, AMBER)
	_words("SKID PAD", SKID_PAD + Vector3(0.0, 0.0, 0.0), 200, WHITE)


func _mark_slalom_and_jumps() -> void:
	# Gate lines either end of the slalom, and a spot under each cone.
	_rect(-30.0, SLALOM_Z, 0.3, 6.0, WHITE)
	_rect(12.0, SLALOM_Z, 0.3, 6.0, WHITE)
	for x in SLALOM_X:
		_spot(x, SLALOM_Z, 0.35, AMBER)
	_words("SLALOM", Vector3(-27.0, 0.0, SLALOM_Z + 4.4), 140, WHITE, -PI * 0.5)
	# The jump area: a box round the jump line, and arrows for the way to ride it.
	_outline(Rect2(-28.0, JUMP_Z - 7.5, 42.0, 11.0), 0.2, YELLOW)
	for z in [JUMP_Z, JUMP_Z - 4.5]:
		for k in 3:
			_rect(-34.0 + k * 1.5, z, 1.0, 0.25, WHITE, 0.0)
	_words("JUMPS", Vector3(-25.5, 0.0, JUMP_Z + 2.3), 120, YELLOW, -PI * 0.5)


func _mark_slow_area() -> void:
	# The U-turn box: turn round inside the lines without a foot down.
	_outline(UTURN, 0.2, WHITE)
	_words("U-TURN BOX", Vector3(UTURN.get_center().x, 0.0, UTURN.get_center().y), 140, WHITE)
	# A figure of eight round two circles.
	for c in FIGURE_EIGHT:
		_ring(Vector3(c.x, 0.0, c.y), FIGURE_EIGHT_R, 0.18, BLUE)
		_spot(c.x, c.y, 0.35, AMBER)
	_words("FIGURE OF EIGHT", Vector3(-45.0, 0.0, FIGURE_EIGHT[0].y + 8.0), 110, WHITE)
	# The hump lane.
	_outline(Rect2(HUMPS_X[0] - 6.0, HUMPS_Z - 1.8, HUMPS_X[HUMPS_X.size() - 1] - HUMPS_X[0] + 12.0, 3.6), 0.15, WHITE)
	_words("SPEED HUMPS", Vector3(HUMPS_X[0] - 2.0, 0.0, HUMPS_Z + 3.0), 110, WHITE)


func _mark_drop_off() -> void:
	_outline(DROP_OFF, 0.25, YELLOW)
	var x := DROP_OFF.position.x + 1.0
	while x < DROP_OFF.end.x - 1.0:
		_rect(x, DROP_OFF.position.y + 0.8, 0.3, 1.2, YELLOW, 0.5)
		x += 2.0
	_words("YARD KIT DROP-OFF", Vector3(DROP_OFF.get_center().x, 0.0, DROP_OFF.end.y - 1.4), 150, YELLOW)


# ---------------------------------------------------------------------------- solid bits

## Rounded speed humps across the hump lane, 8 cm high: solid, so they work the suspension.
func _build_humps(world: World) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.21)
	mat.roughness = 0.85
	world._wet(mat, 0.9)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = YELLOW
	stripe.roughness = 0.6
	var length := 1.4
	var height := 0.08
	var width := 3.4
	var profile := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		profile.append(Vector2((t - 0.5) * length, height * sin(PI * t)))
	for hx in HUMPS_X:
		var body := StaticBody3D.new()
		body.set_meta("surface", "tarmac")
		body.position = Vector3(hx, 0.0, HUMPS_Z)
		var pts := PackedVector3Array()
		for p in profile:
			pts.append(Vector3(p.x, p.y, -width * 0.5))
			pts.append(Vector3(p.x, p.y, width * 0.5))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in profile.size() - 1:
			var a := profile[k]
			var b := profile[k + 1]
			var q := [Vector3(a.x, a.y, -width * 0.5), Vector3(b.x, b.y, -width * 0.5), Vector3(b.x, b.y, width * 0.5), Vector3(a.x, a.y, width * 0.5)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[i])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		body.add_child(mi)
		for s in 3:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.01, 0.3)
			bar.mesh = bm
			bar.material_override = stripe
			bar.position = Vector3(0.0, height + 0.002, -1.1 + s * 1.1)
			body.add_child(bar)
		add_child(body)


## Traffic cones that stay put round the skid pad (no collision: ride through them).
func _build_cones() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.18
	cm.height = 0.5
	cm.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = 8
	for i in 8:
		var a := TAU * i / 8.0
		mm.set_instance_transform(i, Transform3D(Basis(), SKID_PAD + Vector3(cos(a) * (SKID_RADIUS - 1.5), 0.25, sin(a) * (SKID_RADIUS - 1.5))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## Boards beside the braking zone, a number every 10 m, readable from the lane.
func _build_boards() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.85, 0.85, 0.82)
	for d in range(0, int(BRAKE_END - BRAKE_X) + 1, 10):
		var x := BRAKE_X + d
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.6, 0.8)
		board.mesh = bm
		board.material_override = post_mat
		board.position = Vector3(x, 1.0, LANE_Z.x - 2.6)
		add_child(board)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, 0.7, 0.06)
		post.mesh = pm
		post.material_override = post_mat
		post.position = Vector3(x, 0.35, LANE_Z.x - 2.6)
		add_child(post)
		var l := Label3D.new()
		l.text = "%d" % d if d > 0 else "0"
		l.font_size = 64
		l.pixel_size = 0.006
		l.modulate = Color(0.1, 0.1, 0.1)
		l.outline_size = 0
		l.position = Vector3(x - 0.035, 1.0, LANE_Z.x - 2.6)
		l.rotation.y = -PI * 0.5
		add_child(l)


## The loop's start gantry across the road on the yard's south side.
func _build_gantry(world: World) -> void:
	var loop: Dictionary = world.roads.roads[0]
	var i := WorldRoads.nearest_sample(loop, Vector2(0.0, 137.8))
	var p := world.roads.point(0, i)
	var dir: Vector2 = (loop["dir"] as PackedVector2Array)[i]
	var right := Vector3(-dir.y, 0.0, dir.x)
	var yaw := atan2(-dir.x, -dir.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.25)
	mat.metallic = 0.5
	mat.roughness = 0.5
	var span := float(loop["hw"]) + 2.2
	for side: float in [-1.0, 1.0]:
		var foot: Vector3 = p + right * span * side
		var body := StaticBody3D.new()
		body.set_meta("surface", "tarmac")
		body.position = foot + Vector3.UP * 2.8
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, 5.6, 0.3)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = shape.size
		mi.mesh = bm
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(span * 2.0 + 0.4, 1.0, 0.25)
	beam.mesh = beam_mesh
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.08, 0.12, 0.2)
	beam.material_override = sign_mat
	beam.position = p + Vector3.UP * 5.3
	beam.rotation.y = yaw
	add_child(beam)
	for face: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "THE LOOP  %.1f km" % (float(loop["length"]) / 1000.0)
		l.font_size = 96
		l.pixel_size = 0.008
		l.modulate = Color(1.0, 0.85, 0.3)
		l.outline_size = 0
		l.position = p + Vector3.UP * 5.3 + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.14 * face)
		l.rotation.y = yaw + (0.0 if face > 0.0 else PI)
		add_child(l)
	# A chequered start line across the road.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = loop["hw"]
	var along := Vector3(dir.x, 0.0, dir.y)
	var cells := int(hw * 2.0 / 0.5)
	for c in cells:
		for r in 2:
			st.set_color(Color(0.05, 0.05, 0.05) if (c + r) % 2 == 0 else Color(0.95, 0.95, 0.95))
			var o: Vector3 = p + Vector3.UP * 0.035 + right * (-hw + c * 0.5) + along * (r * 0.5 - 0.5)
			var q := [o, o + right * 0.5, o + right * 0.5 + along * 0.5, o + along * 0.5]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	st.generate_normals()
	var line := MeshInstance3D.new()
	line.name = "StartLine"
	line.mesh = st.commit()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = lm
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
