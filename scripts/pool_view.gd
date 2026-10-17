class_name PoolView
extends Node3D
## The lounge's pool table come to life (see PoolGame for the game): the balls where Shed.pool
## has them, every shot played out on the felt as it was taken, and the cue for whoever's at
## the table. F on the table racks them up, joins a game or steps up to take your shot; then
## the view drops behind the cue ball:
##   mouse left/right   aim (hold Shift to aim finely); the right stick on a pad
##   mouse up/down      look down the cue or up over the table
##   hold left mouse    draw the cue back for power (it swings up and back down); let go to shoot
##   R twice            rack up a new game, just you; F steps back
## Sits on the middle of the felt, the table's long way along its z.

const AIM_MOUSE := 0.0018
const FINE := 0.2
const PITCH_MOUSE := 0.003
const PAD_AIM := 1.2
const CHARGE := 1.3          # seconds from no power to full, and as long back down
const CUE_LENGTH := 1.45
const REACH := 2.6

var _balls: Array[MeshInstance3D] = []
var _last_at: Array[Vector2] = []
var _sim := {}                 # the shot being played out on this table, or {}
var _shown := -1               # the last shot (its "n") this table has played out
var _shown_game := -1
var _cue: MeshInstance3D
var _guide: MeshInstance3D
var _guide_mesh: ImmediateMesh
var _ghost: MeshInstance3D
var _cam: Camera3D
var _hud: CanvasLayer
var _hud_text: Label
var _power_bar: ColorRect
var _power_back: ColorRect
## "" walking about, "aim" lining up a shot, "watch" watching it roll from behind the cue.
var mode := ""
var aim := 0.0
var pitch := 0.25
var power := 0.0
var _charging := false
var _charge_t := 0.0
var _walker: Walker
var _wait := 0.0               # seconds left to wait for the host to answer (a rack or a shot)
var _sent_shot := -1           # the shot count when we shot, to see it come back
var _rerack := 0.0             # seconds left to press R again for a new game
var _strike := 0.0             # seconds since the shot being played out was struck
var _strike_angle := 0.0
var _hits := 0
var _pots := 0


func _ready() -> void:
	name = "PoolTable"
	var colors := [Color(0.95, 0.95, 0.9), Color(0.95, 0.78, 0.08), Color(0.1, 0.22, 0.8), Color(0.85, 0.1, 0.08),
		Color(0.4, 0.12, 0.55), Color(0.95, 0.45, 0.05), Color(0.05, 0.5, 0.2), Color(0.5, 0.08, 0.08), Color(0.04, 0.04, 0.04)]
	var sphere := SphereMesh.new()
	sphere.radius = PoolGame.R
	sphere.height = PoolGame.R * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	for i in 16:
		var ball := MeshInstance3D.new()
		ball.name = "Ball%d" % i
		ball.mesh = sphere
		var m := StandardMaterial3D.new()
		m.albedo_texture = _ball_texture(colors[i if i <= 8 else i - 8], i > 8)
		m.roughness = 0.12
		m.metallic_specular = 0.7
		ball.material_override = m
		# Each turned a different way, so the stripes don't all line up.
		ball.basis = Basis(Vector3(1, 0, 0), i * 1.3) * Basis(Vector3.UP, i * 2.1)
		add_child(ball)
		_balls.append(ball)
		_last_at.append(Vector2.ZERO)
	# The pockets: dark holes in the felt and through the rails' corners over them.
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.02, 0.02, 0.02)
	hole.roughness = 1.0
	for k in PoolGame.POCKETS.size():
		var pk: Vector2 = PoolGame.POCKETS[k]
		for y in [0.001, 0.0655]:
			var disc := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = PoolGame.POCKET_R[k] * 0.85
			dm.bottom_radius = dm.top_radius
			dm.height = 0.002
			dm.radial_segments = 20
			disc.mesh = dm
			disc.material_override = hole
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disc.position = Vector3(pk.x, y, pk.y)
			add_child(disc)
	# The cue: a tapered ash shaft with a dark butt and a pale tip end.
	_cue = MeshInstance3D.new()
	_cue.name = "Cue"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0065
	cm.bottom_radius = 0.015
	cm.height = CUE_LENGTH
	cm.radial_segments = 10
	_cue.mesh = cm
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = _cue_texture()
	wood.roughness = 0.35
	_cue.material_override = wood
	add_child(_cue)
	_rest_cue()
	_guide_mesh = ImmediateMesh.new()
	_guide = MeshInstance3D.new()
	_guide.mesh = _guide_mesh
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1, 1, 1, 0.75)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guide.material_override = gm
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.visible = false
	add_child(_guide)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = sphere
	var ghm := StandardMaterial3D.new()
	ghm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghm.albedo_color = Color(1, 1, 1, 0.22)
	ghm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.material_override = ghm
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_cam = Camera3D.new()
	_cam.name = "PoolCamera"
	_cam.fov = 60.0
	_cam.near = 0.02
	add_child(_cam)
	# F on the table (the walker's "use" targets, like the recovery rig's).
	var body := StaticBody3D.new()
	body.name = "PoolUse"
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.set_meta("use_node", self)
	body.set_meta("use", {"what": "pool"})
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 0.12, 2.4)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0.0, 0.03, 0.0)
	add_child(body)
	var last: Dictionary = Shed.pool.get("last", {})
	_shown = int(last.get("n", -1))
	_shown_game = int(Shed.pool.get("game", 0))
	_show_balls(_table_balls())


func _exit_tree() -> void:
	if mode != "":
		_step_back()


## A ball's skin for a SphereMesh: all its colour, or white with a band round the middle (a
## stripe), with a white spot on each side for its number.
static func _ball_texture(c: Color, stripe: bool) -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 64:
			var col := c
			if stripe and (y < 10 or y > 21):
				col = Color(0.95, 0.95, 0.9)
			for cx in [16, 48]:
				if Vector2((x - cx) * 0.5, y - 16).length() < 3.2 and c != Color(0.95, 0.95, 0.9):
					col = Color(0.95, 0.95, 0.9)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Along the cue (the CylinderMesh's v runs tip to butt): a pale tip, the ash shaft, a dark butt.
static func _cue_texture() -> ImageTexture:
	var img := Image.create(4, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var col := Color(0.82, 0.68, 0.45)
		if y < 1:
			col = Color(0.2, 0.35, 0.7)
		elif y < 2:
			col = Color(0.95, 0.93, 0.85)
		elif y > 40:
			col = Color(0.12, 0.06, 0.04) if y % 9 != 0 else Color(0.8, 0.75, 0.6)
		for x in 4:
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## The balls as they stand: the game's, or a rack waiting on the felt before anyone's played.
func _table_balls() -> Array:
	var balls: Array = Shed.pool.get("balls", [])
	return balls if balls.size() == 16 else PoolGame.rack(0)


func _show_balls(balls: Array) -> void:
	for i in 16:
		var b: Array = balls[i]
		var at := Vector2(float(b[0]), float(b[1]))
		_place_ball(i, at, bool(b[2]))


## Puts ball `i` at `at` on the felt, rolled over by however far it went since last time.
func _place_ball(i: int, at: Vector2, on: bool) -> void:
	var ball := _balls[i]
	ball.visible = on
	var moved := at - _last_at[i]
	if on and moved.length() > 0.00001 and moved.length() < 0.5:
		var axis := Vector3(-moved.y, 0.0, moved.x).normalized()
		ball.basis = Basis(axis, moved.length() / PoolGame.R) * ball.basis
		ball.basis = ball.basis.orthonormalized()
	_last_at[i] = at
	ball.position = Vector3(at.x, PoolGame.R, at.y)


## The cue lying along the top of a rail when nobody's using it.
func _rest_cue() -> void:
	_cue.basis = Basis(Vector3.RIGHT, PI * 0.5)
	_cue.position = Vector3(PoolGame.HX + 0.05, 0.08, 0.1)


func _process(delta: float) -> void:
	var st: Dictionary = Shed.pool
	var last: Dictionary = st.get("last", {})
	var n := int(last.get("n", -1))
	if int(st.get("game", 0)) != _shown_game or n < _shown:
		# A new rack.
		_shown_game = int(st.get("game", 0))
		_shown = n
		_sim = {}
	elif n != _shown:
		# A shot to play out, from the balls as they lay when it was taken.
		_shown = n
		_sim = PoolGame.sim_from(last["from"])
		_show_balls(last["from"])
		PoolGame.strike(_sim, float(last["angle"]), float(last["power"]))
		_strike = 0.0
		_strike_angle = float(last["angle"])
		_hits = 0
		_pots = 0
		Sfx.play_at("clink", global_position, -10.0)
	if not _sim.is_empty():
		_strike += delta
		var steps := int(round(delta / PoolGame.DT))
		for s in clampi(steps, 1, 40):
			if not PoolGame.moving(_sim):
				break
			PoolGame.step(_sim)
		if int(_sim["hits"]) > _hits:
			_hits = int(_sim["hits"])
			Sfx.play_at("clink", global_position, -16.0)
		if (_sim["potted"] as Array).size() > _pots:
			_pots = (_sim["potted"] as Array).size()
			Sfx.play_at("clunk", global_position, -12.0)
		if not PoolGame.moving(_sim) or float(_sim["t"]) > PoolGame.MAX_TIME:
			_sim = {}
		else:
			var balls := PoolGame.balls_of(_sim)
			_show_balls(balls)
	if _sim.is_empty():
		_show_balls(_table_balls())
	_rerack = maxf(0.0, _rerack - delta)
	if mode != "" and (_walker == null or not is_instance_valid(_walker) or _walker.process_mode != Node.PROCESS_MODE_DISABLED):
		# Something else took over (geometry mode, getting on a bike): leave the table.
		_step_back()
	elif mode != "" and not _cam.current:
		_cam.current = true
	match mode:
		"":
			_update_idle_cue()
			if _wait > 0.0:
				# We racked: step up for the break as soon as the host says it's ours.
				_wait -= delta
				if _my_shot():
					_wait = 0.0
					_take_aim()
		"aim":
			_aim_frame(delta)
		"watch":
			_watch_frame(delta)


## Whether it's our shot now, with the balls stopped.
func _my_shot() -> bool:
	return PoolGame.shooter() == Shed.me() and _sim.is_empty()


## Nobody here at the cue: it lies on the rail, or follows through on someone else's shot.
func _update_idle_cue() -> void:
	_guide.visible = false
	_ghost.visible = false
	if not _sim.is_empty() and _strike < 0.35:
		var from: Array = Shed.pool["last"]["from"]
		var cue_at := Vector2(float(from[0][0]), float(from[0][1]))
		_pose_cue(cue_at, _strike_angle, 0.12 - _strike * 0.5)
	else:
		_rest_cue()


## Holds the cue behind `at` along `angle`, its tip `gap` back from the ball, the butt raised.
func _pose_cue(at: Vector2, angle: float, gap: float) -> void:
	var d := PoolGame.aim_dir(angle)
	var back := Vector3(-d.x, 0.0, -d.y)
	var up := back.rotated(Vector3(-back.z, 0.0, back.x), deg_to_rad(-6.0)).normalized()
	var tip := Vector3(at.x, PoolGame.R, at.y) + back * (PoolGame.R + maxf(gap, 0.0))
	var y := -up   # the cylinder's +y (its thin end) points down the cue at the ball
	var x := y.cross(Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	_cue.basis = Basis(x, y, z)
	_cue.position = tip + up * CUE_LENGTH * 0.5


# ---------------------------------------------------------------------------- F on the table

func use_text(_t: Dictionary) -> String:
	var st: Dictionary = Shed.pool
	var me := Shed.me()
	var players: Array = st["players"]
	var lines := ["Pool table"]
	var f := Walker._keys("interact")
	if PoolGame.playing():
		var who := []
		for i in players.size():
			var g := PoolGame.group_of_player(i)
			who.append("%s%s" % [PoolGame.player_name(int(players[i])), " (%s)" % g if g != "" else ""])
		lines.append("Playing: %s" % ", ".join(who) if not who.is_empty() else "Nobody playing")
		if str(st["msg"]) != "" and _sim.is_empty():
			lines.append(str(st["msg"]))
		if not _sim.is_empty():
			lines.append("The balls are rolling...")
		elif PoolGame.shooter() == me:
			lines.append("%s: take your shot" % f)
		elif players.has(me):
			lines.append("%s's shot" % PoolGame.player_name(PoolGame.shooter()))
		elif players.size() < PoolGame.MAX_PLAYERS:
			lines.append("%s: join the game" % f)
		else:
			lines.append("Wait for this game to finish to play.")
	else:
		if str(st["msg"]) != "":
			lines.append(str(st["msg"]))
		lines.append("%s: rack them up (eight-ball, on your own or with a mate)" % f)
	return "\n".join(lines)


func use(_t: Dictionary) -> void:
	var me := Shed.me()
	var players: Array = Shed.pool["players"]
	if not _sim.is_empty():
		Shed.feedback.emit("Wait for the balls to stop.", false)
	elif not PoolGame.playing():
		Shed.request({"a": "pool_rack"})
		_wait = 3.0
	elif PoolGame.shooter() == me:
		_take_aim()
	elif players.has(me):
		Shed.feedback.emit("It's %s's shot." % PoolGame.player_name(PoolGame.shooter()), false)
	else:
		Shed.request({"a": "pool_join"})


# ---------------------------------------------------------------------------- at the cue

## Steps up behind the cue ball: the walker stands still and the view drops down the cue,
## pointing where you were looking.
func _take_aim() -> void:
	if mode == "":
		_walker = get_tree().get_first_node_in_group("local_walker") as Walker
		if _walker == null:
			return
		var fwd := -_walker.global_transform.basis.z
		var local := global_transform.basis.inverse() * fwd
		aim = atan2(local.x, -local.z)
		_walker.process_mode = Node.PROCESS_MODE_DISABLED
		for key in ["info", "look_info", "look_prompt", "tap_prompt"]:
			_walker.set(key, "")
		_walker.plan = {}
		_walker.alt_plan = {}
		_walker.target = {}
		_cam.current = true
		_make_hud()
	mode = "aim"
	power = 0.0
	_charging = false
	_hud.visible = true


## Back to walking about.
func _step_back() -> void:
	mode = ""
	_charging = false
	power = 0.0
	if _hud:
		_hud.visible = false
	if _walker and is_instance_valid(_walker):
		_walker.process_mode = Node.PROCESS_MODE_INHERIT
		_walker.camera.current = true
	_walker = null


func _input(event: InputEvent) -> void:
	if mode == "":
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	if not captured:
		return
	if event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if mode == "aim":
			aim -= rel.x * AIM_MOUSE * (FINE if Input.is_action_pressed("sprint") else 1.0)
		pitch = clampf(pitch + rel.y * PITCH_MOUSE, 0.0, 1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_step_back()
	elif mode == "aim" and event.is_action_pressed("act"):
		get_viewport().set_input_as_handled()
		_charging = true
		_charge_t = 0.0
	elif mode == "aim" and event.is_action_released("act") and _charging:
		get_viewport().set_input_as_handled()
		shoot()
	elif mode == "aim" and event.is_action_pressed("alt_act"):
		get_viewport().set_input_as_handled()
		if _rerack > 0.0:
			_rerack = 0.0
			Shed.request({"a": "pool_rack"})
			_wait = 3.0
			_step_back()
		else:
			_rerack = 2.0
			Shed.feedback.emit("Press %s again to rack up a new game (just you)." % Walker._keys("alt_act"), true)
	elif event.is_action_pressed("act") or event.is_action_pressed("alt_act") or event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()


## Takes the shot lined up: `aim` with `power` (also the tests' way in).
func shoot() -> void:
	_charging = false
	if not _my_shot():
		return
	_sent_shot = int(Shed.pool["shots"])
	Shed.request({"a": "pool_shot", "angle": aim, "power": power})
	mode = "watch"
	_wait = 3.0


func _cue_ball() -> Vector2:
	var b: Array = _table_balls()[0]
	return Vector2(float(b[0]), float(b[1]))


func _aim_frame(delta: float) -> void:
	if not _my_shot():
		mode = "watch"
		_wait = 0.0
		return
	var look := Controls.stick(true)
	if look != Vector2.ZERO:
		aim -= look.x * PAD_AIM * delta * (FINE if Input.is_action_pressed("sprint") else 1.0)
		pitch = clampf(pitch + look.y * delta, 0.0, 1.0)
	# The pad's right trigger works like the left mouse button.
	var trig := Controls.trigger(true) > 0.5
	if trig and not _charging:
		_charging = true
		_charge_t = 0.0
	elif not trig and _charging and not Input.is_action_pressed("act") and Controls.active_device >= 0:
		shoot()
		return
	if _charging:
		_charge_t += delta
		var ph := fmod(_charge_t, CHARGE * 2.0) / CHARGE
		power = ph if ph <= 1.0 else 2.0 - ph
	var at := _cue_ball()
	_pose_cue(at, aim, 0.015 + power * 0.22)
	_place_camera(at)
	_draw_guide(at)
	_update_hud()


## Watching the shot roll from where you took it; your turn again, back to the cue.
func _watch_frame(delta: float) -> void:
	_guide.visible = false
	_ghost.visible = false
	_update_idle_cue()
	_place_camera(_cue_ball() if _sim.is_empty() else Vector2(float(Shed.pool["last"]["from"][0][0]), float(Shed.pool["last"]["from"][0][1])))
	_update_hud()
	_wait -= delta
	var answered := int(Shed.pool["shots"]) > _sent_shot or _sent_shot < 0
	if not answered and _wait > 0.0:
		return
	if not _sim.is_empty():
		return
	if _my_shot():
		_sent_shot = -1
		_take_aim()
	else:
		_step_back()


## Down the cue, low, or up over the table, looking along the shot.
func _place_camera(at: Vector2) -> void:
	var d := PoolGame.aim_dir(aim)
	var dir := global_transform.basis * Vector3(d.x, 0.0, d.y)
	var ball := to_global(Vector3(at.x, PoolGame.R, at.y))
	var elev := lerpf(0.2, 1.05, pitch)
	var dist := lerpf(0.75, 1.25, pitch)   # under the lamp shades over the table
	var eye := ball - dir * cos(elev) * dist + Vector3.UP * (sin(elev) * dist + 0.06)
	_cam.global_position = eye
	_cam.look_at(ball + dir * lerpf(0.45, 0.2, pitch), Vector3.UP)


## The line the cue ball will take to the first thing it hits, a ghost ball where it touches,
## and the way the ball it hits will go.
func _draw_guide(at: Vector2) -> void:
	var d := PoolGame.aim_dir(aim)
	var balls := _table_balls()
	var best := 4.0
	var hit := -1
	for i in range(1, 16):
		if not bool(balls[i][2]):
			continue
		var c := Vector2(float(balls[i][0]), float(balls[i][1])) - at
		var along := c.dot(d)
		if along <= 0.0:
			continue
		var off2 := c.length_squared() - along * along
		var r2 := PoolGame.R * PoolGame.R * 4.0
		if off2 >= r2:
			continue
		var t := along - sqrt(r2 - off2)
		if t < best:
			best = t
			hit = i
	# Or the cushion it runs into first.
	for k in 2:
		var dk := d[k]
		if absf(dk) > 0.0001:
			var wall := (PoolGame.HX if k == 0 else PoolGame.HZ) - PoolGame.R
			var t := (signf(dk) * wall - at[k]) / dk
			if t > 0.0 and t < best:
				best = t
				hit = -1
	var end := at + d * best
	var y := 0.004
	_guide_mesh.clear_surfaces()
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_guide_mesh.surface_add_vertex(Vector3(at.x, y, at.y))
	_guide_mesh.surface_add_vertex(Vector3(end.x, y, end.y))
	if hit >= 0:
		var obj := Vector2(float(balls[hit][0]), float(balls[hit][1]))
		var out := (obj - end).normalized()
		_guide_mesh.surface_add_vertex(Vector3(obj.x, y, obj.y))
		_guide_mesh.surface_add_vertex(Vector3(obj.x + out.x * 0.3, y, obj.y + out.y * 0.3))
	_guide_mesh.surface_end()
	_guide.visible = true
	_ghost.visible = hit >= 0
	_ghost.position = Vector3(end.x, PoolGame.R, end.y)


func _make_hud() -> void:
	if _hud:
		return
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.offset_top = -260.0
	box.offset_bottom = -104.0   # clear of the tool bar
	box.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(box)
	_hud_text = UITheme.label("", 16)
	_hud_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_text.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud_text.add_theme_constant_override("outline_size", 6)
	box.add_child(_hud_text)
	_power_back = ColorRect.new()
	_power_back.color = Color(0, 0, 0, 0.55)
	_power_back.custom_minimum_size = Vector2(320, 14)
	_power_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_power_back)
	_power_bar = ColorRect.new()
	_power_bar.color = UITheme.ACCENT
	_power_bar.position = Vector2(2, 2)
	_power_back.add_child(_power_bar)


func _update_hud() -> void:
	if _hud == null:
		return
	var st: Dictionary = Shed.pool
	var me_at: int = (st["players"] as Array).find(Shed.me())
	var g := PoolGame.group_of_player(me_at) if me_at >= 0 else ""
	var lines := []
	if str(st["msg"]) != "" and _sim.is_empty():   # not till the balls have done what it says
		lines.append(str(st["msg"]))
	if mode == "aim":
		var on_black := g != "" and PoolGame.left_of(st["balls"], g) == 0
		lines.append("Your shot%s" % (": on the black" if on_black else (" (%s)" % g if g != "" else ": the table's open")))
		lines.append("Mouse: aim (Shift: fine)  ·  up/down: view  ·  hold %s: power, let go to shoot  ·  %s twice: new game  ·  %s: step back" % [
			"left mouse" if Controls.active_device < 0 else "RT", Walker._keys("alt_act"), Walker._keys("interact")])
	else:
		lines.append("%s: step back" % Walker._keys("interact"))
	_hud_text.text = "\n".join(lines)
	_power_back.visible = mode == "aim"
	_power_bar.size = Vector2(316.0 * power, 10.0)
	_power_bar.color = UITheme.ACCENT.lerp(Color(1.0, 0.25, 0.15), power)
