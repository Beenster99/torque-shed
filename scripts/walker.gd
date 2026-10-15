class_name Walker
extends CharacterBody3D
## The player on foot in first person. Looks at bikes and parts, picks a tool, and holds the
## action button to work: unbolt, remove, fit, bolt up, clean and restore. Every change goes
## through the Shed state so everyone in the session sees the same bikes. Crouches to get at
## the low bits, wheels bikes about, and pours and drains fluids with a can in hand.

signal mount_requested(bike_id: int)
signal computer_requested
signal tuning_requested
signal label_requested(furniture_id: int)
signal rename_requested(bike_id: int)

const TOOLS: Array[String] = ["hands", "wrench", "brush", "repair", "spray", "lance", "gun", "watch"]
const TOOL_NAMES := {"hands": "Hands", "wrench": "Wrench", "brush": "Brush", "repair": "Grinder and welder",
	"spray": "Spray can", "lance": "Pressure washer", "gun": "Spray gun", "watch": "Stopwatch"}
const EYE := 1.62
const CROUCH_EYE := 0.95
const WALK := 3.2
const RUN := 5.5
const CROUCH_WALK := 1.5
const HOLD_TO_PUSH := 0.35   # hold F this long on a bike to wheel it instead of getting on
const SEATED_EYE := 0.75     # eye height above the seat when sitting down
const JET_REACH := 0.3       # the pressure washer cleans every part this close to where it hits
const REACH := 2.6
const BRUSH_REACH := 0.35    # the brush cleans every part this close to where it touches
const MOUSE_SENS := 0.0025
const SPRAY_RADIUS := 0.1   # how wide the spray lands, in metres; skill will widen it later
const COVER_CELL := 0.06     # parts are sprayed a patch this size at a time
const COVER_RATE := 10.0     # coats a second where the spray is pointed
const COVER_DONE := 0.9      # this much of the part covered and the job's done
const RUN_LEVEL := 4.0       # a patch sprayed this many coats over runs (paint) or flings off (lube)
const GUN_RADIUS := 0.13     # the spray gun's fan is wider and lays an even coat across it
const GUN_RATE := 7.0
const GUN_RUN_LEVEL := 5.5
const PING_REACH := 60.0
const PAD_LOOK := 2.6
const CARRY_STEP := 0.25     # a click of the mouse wheel moves equipment you're carrying this far out or in
const CARRY_MIN := -0.15     # metres closer than arm's length it can come
const CARRY_MAX := 3.0       # and further out

var camera: Camera3D
var tool := "hands"
var controls_enabled := true
var target := {}            # what the crosshair is on: {kind, bike, engine, slot, spot}
var plan := {}              # what the action button would do: {action, time, verb, blocked}
var info := ""              # description of the target for the HUD
var progress := 0.0         # 0..1 of the current hold-to-work action
var spray_color := 0        # index into Shed.PAINTS loaded in the spray can
var spray_finish := 0       # index into Shed.FINISHES
var crouched := false
var alt_plan := {}          # what the second work button would do (drain a fluid), same shape as plan

var _pitch := 0.0
var _hold := 0.0
var _plan_key := ""
var _need_release := false
var _held_view: Node3D
var _held_sig := ""
var _tool_view: Node3D
var _last_status := ""
var _highlighted: BikeModel
var _work_sound: AudioStreamPlayer3D
var _stride := 0.0
var _push_timer := 0.0
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D
var _eye := EYE
var _f_bike := 0            # bike F went down on, waiting to see if it's a tap (ride) or a hold (push)
var _f_seat := 0            # seat F went down on: a tap sits you down, a hold picks it up to move
var _f_time := 0.0
var seat := 0               # the seat you're sitting on, or 0
var _seat_spot := Vector3.ZERO
var _active_plan := {}
var spray_skill := 1.0       # widens the spray: the tool's upgrade stage and Steady Hand (see Progress)
var coverage := 0.0          # how much of the part being sprayed is covered, 0..1
var _cover := {}             # the spray job under way: {key, plan, item, points, cells, live, splats}
var _covers := {}            # every part with a spray job on it, by job key, so you can go back to one
var _mist: CPUParticles3D
var stopwatch := Stopwatch.new()
## The tyre-fitting game under way on the tyre changer (see TyreGame), or null. While it runs the
## mouse (or right stick) works the tyre lever instead of looking about.
var tyre_game: TyreGame
var _game_key := ""
var _jet: CPUParticles3D
var blast: BlastGame         # hands in a sandblaster's gloves (see BlastGame), or null
var _blast_send := 0.0
var _blast_tick := 0.0
var _blast_done_for := 0.0
## Moments to celebrate at the sandblaster, for the HUD: [{kind: "part" or "engine", name}].
var blast_cues: Array = []
var _tool_sig := ""          # tool and upgrade stage the tool in your hand is drawn at
## Carrying equipment: how much further out than arm's length you hold it (the mouse wheel, or
## LB / RB, push it out and pull it in), and how it last snapped ({walls: the wall normals it
## sits against}, see Placement; empty when it didn't).
var carry_reach := 0.0
var snap_info := {}
var _carrying := 0           # the equipment carry_reach was set for
var _ghost: Node3D           # the outline on the floor of where the equipment will go
var _ghost_sig := ""
var _room_cache := {}        # the last free place found on a surface: {key, place}
## Turning what you hold before you put it down (the rotate keys): how far the part in your
## hands and the equipment you carry are turned from the way you face, in radians. With
## snapping on a press turns them a quarter; with it off they turn freely while the key is held.
var hold_turn := 0.0
var carry_turn := 0.0
var _turn_time := 0.0        # how long a rotate key has been held
var _held_for := 0           # the part hold_turn was set for
var _part_ghost: Node3D      # the outline of where the part in your hands will go down
var _part_ghost_sig := ""
## Scrapping what you hold or carry: how long the scrap key has been held, and once held long
## enough, what is waiting for a second press to confirm ({furniture or item, name, until}).
var scrap_armed := {}
var _scrap_hold := 0.0
var _scrap_release := false
const TURN_RATE := PI * 0.5        # free turning, radians a second
const TURN_NUDGE := PI / 36.0      # a tap with snapping off: 5 degrees
const TURN_HOLD := 0.2             # held this long, free turning starts
const SCRAP_HOLD := 1.0            # hold the scrap key this long...
const SCRAP_CONFIRM := 6.0         # ...then press it again within this long to scrap it


func _ready() -> void:
	add_to_group("local_walker")
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.3
	_shape.height = 1.75
	_shape_node = CollisionShape3D.new()
	_shape_node.shape = _shape
	_shape_node.position.y = 0.875
	add_child(_shape_node)
	camera = Camera3D.new()
	camera.position.y = EYE
	camera.near = 0.03
	camera.far = 2500.0
	camera.fov = Settings.gfx_fov
	camera.add_to_group("gfx_fov")   # follows the field-of-view setting (see Graphics)
	add_child(camera)
	_work_sound = Sfx.make_loop_player(camera)
	_work_sound.position = Vector3(0.0, -0.3, -0.6)
	_set_tool_view()
	stopwatch.max_laps = Progress.stopwatch_laps(Shed.me())
	# A tool upgrade bought in the Character tab shows in your hand straight away.
	Progress.changed.connect(func():
		stopwatch.max_laps = Progress.stopwatch_laps(Shed.me())
		if _tool_sig != "%s:%d" % [tool, Progress.tool_stage(Shed.me(), tool)]:
			_set_tool_view())


func place(xf: Transform3D) -> void:
	global_position = xf.origin + Vector3.UP * 0.05
	rotation = Vector3(0.0, xf.basis.get_euler().y, 0.0)
	_pitch = 0.0
	camera.rotation.x = 0.0
	velocity = Vector3.ZERO


func yaw() -> float:
	return rotation.y


func pitch() -> float:
	return _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if blast and _blast_input(event):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if tyre_game:
			tyre_game.move(event.relative)
		else:
			_look(-event.relative.x * MOUSE_SENS, -event.relative.y * MOUSE_SENS)
	elif event.is_action_pressed("rotate_left") or event.is_action_pressed("rotate_right"):
		if Shed.moving(Shed.me()) != 0 or Shed.held_by(Shed.me()) != 0:
			get_viewport().set_input_as_handled()
			turn_step(1 if event.is_action_pressed("rotate_left") else -1)
	elif event.is_action_pressed("scrap") and not scrap_armed.is_empty():
		get_viewport().set_input_as_handled()
		confirm_scrap()
	elif Shed.moving(Shed.me()) != 0 and (event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev")):
		# Carrying equipment, the wheel only moves it out or in (wheel up, Q or LB: further away).
		get_viewport().set_input_as_handled()
		nudge_carry(1 if event.is_action_pressed("tool_prev") else -1)
	elif Shed.moving(Shed.me()) != 0 and event.is_action_pressed("alt_act"):
		get_viewport().set_input_as_handled()
		toggle_snap()
	elif event.is_action_pressed("tool_next"):
		_cycle_tool(1)
	elif event.is_action_pressed("tool_prev"):
		_cycle_tool(-1)
	elif _screen_key() != "" and (event.is_action_pressed("alt_act") or event.is_action_pressed("spray_finish")) \
			and Shed.moving(Shed.me()) == 0:
		# Looking at a TV or one of the shed's screens: R for the next channel, T for the one before.
		get_viewport().set_input_as_handled()
		_change_channel(_screen_key(), 1 if event.is_action_pressed("alt_act") else -1)
	elif tool in ["spray", "gun"] and event.is_action_pressed("spray_colour"):
		spray_color = (spray_color + 1) % Shed.PAINTS.size()
		_spray_changed()
	elif tool in ["spray", "gun"] and event.is_action_pressed("spray_finish"):
		spray_finish = (spray_finish + 1) % Shed.FINISHES.size()
		_spray_changed()
	elif event.is_action_pressed("ping"):
		get_viewport().set_input_as_handled()
		ping()
	elif event.is_action_pressed("stopwatch") or (tool == "watch" and event.is_action_pressed("act")):
		get_viewport().set_input_as_handled()
		stopwatch.start_stop()
		Sfx.play_at("beep", camera.global_position, -6.0)
	elif tool == "watch" and event.is_action_pressed("alt_act"):
		get_viewport().set_input_as_handled()
		stopwatch.lap_or_reset()
		Sfx.play_at("beep", camera.global_position, -9.0)
	elif event.is_action_pressed("rename") and target.get("kind", "") == "part" and int(target.get("bike", 0)) != 0:
		get_viewport().set_input_as_handled()
		rename_requested.emit(int(target["bike"]))
	elif event.is_action_pressed("crouch"):
		set_crouched(not crouched)
	elif event.is_action_released("interact") and _f_seat != 0:
		get_viewport().set_input_as_handled()
		var chair := _f_seat
		_f_seat = 0
		if _f_time < HOLD_TO_PUSH:
			sit(chair)
	elif seat != 0 and (event.is_action_pressed("interact") or event.is_action_pressed("crouch")):
		get_viewport().set_input_as_handled()
		stand_up()
	elif event.is_action_released("interact") and _f_bike != 0:
		# A tap of F on a bike gets you on it; holding it takes hold of the bars (see _physics_process).
		get_viewport().set_input_as_handled()
		var bike := _f_bike
		_f_bike = 0
		if _f_time < HOLD_TO_PUSH:
			mount_requested.emit(bike)
	elif event.is_action_pressed("interact"):
		var box := _target_box()
		var pushed := Shed.moving(Shed.me())
		var wheeling := Shed.pushing_bike(Shed.me())
		var furniture := _target_furniture()
		# Mark the press handled before mounting, or the same F reaches main and gets you off again.
		if wheeling != 0:
			get_viewport().set_input_as_handled()
			Shed.request({"a": "release_bike", "bike": wheeling, "xf": _bike_push_transform(wheeling)})
			collision_mask = 1 | 2 | 4
		elif pushed != 0:
			get_viewport().set_input_as_handled()
			var model := str(Shed.furniture[pushed].get("model", ""))
			var xf = _push_transform(pushed)
			if Equipment.is_wall(model) and not _on_wall:
				Shed.feedback.emit("Hold it up against a wall to hang it.", false)
			else:
				Shed.request({"a": "release", "furniture": pushed, "xf": xf})
		elif target.get("kind", "") == "spot" and Shed.spot_role(str(target["spot"])) == "blaster" \
				and Shed.item_at_spot(str(target["spot"])) != 0 and Shed.held_by(Shed.me()) == 0:
			# Hands in the sandblaster's gloves.
			get_viewport().set_input_as_handled()
			Shed.request({"a": "blast_use", "spot": target["spot"], "on": true})
		elif box != 0:
			get_viewport().set_input_as_handled()
			Shed.request({"a": "unpack", "item": box})
			Sfx.play_at("pickup", camera.global_position - camera.global_transform.basis.z, -4.0)
		elif furniture != 0 and Shed.furniture[furniture]["kind"] == "seat":
			get_viewport().set_input_as_handled()
			_f_seat = furniture
			_f_time = 0.0
		elif furniture != 0:
			get_viewport().set_input_as_handled()
			Shed.request({"a": "grab", "furniture": furniture})
		elif target.get("kind", "") == "part" and int(target.get("bike", 0)) != 0:
			get_viewport().set_input_as_handled()
			_f_bike = int(target["bike"])
			_f_time = 0.0
		elif target.get("kind", "") == "pc":
			get_viewport().set_input_as_handled()
			computer_requested.emit()
		elif target.get("kind", "") == "dyno":
			get_viewport().set_input_as_handled()
			tuning_requested.emit()
		elif target.get("kind", "") == "radio":
			get_viewport().set_input_as_handled()
			Shed.request({"a": "radio", "on": not Shed.radio["on"]})
		elif target.get("kind", "") == "door":
			get_viewport().set_input_as_handled()
			Shed.request({"a": "door", "open": not Shed.door_open})
			Sfx.play_at("switch", camera.global_position, -6.0)
		elif target.get("kind", "") == "lights":
			get_viewport().set_input_as_handled()
			var room := str(target.get("room", ""))
			Shed.request({"a": "lights", "room": room, "on": not Shed.room_lit(room)})
			Sfx.play_at("switch", camera.global_position, -4.0)
		elif target.get("kind", "") == "dyno_kit" and not DynoRoom.f_action(target).is_empty():
			# The dyno room's light and fan switches, and the ear defenders on their hook.
			get_viewport().set_input_as_handled()
			Shed.request(DynoRoom.f_action(target))
			Sfx.play_at("switch" if str(target.get("kit", "")) != "phones" else "pickup", camera.global_position, -4.0)
	else:
		for i in TOOLS.size():
			if event.is_action_pressed("tool_%d" % (i + 1)):
				set_tool(TOOLS[i])


func set_crouched(on: bool) -> void:
	if on == crouched:
		return
	if not on:
		# Only stand up if there's head room.
		var q := PhysicsShapeQueryParameters3D.new()
		var probe := CapsuleShape3D.new()
		probe.radius = 0.28
		probe.height = 1.7
		q.shape = probe
		q.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.9)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			Shed.feedback.emit("No room to stand up here.", false)
			return
	crouched = on
	_shape.height = 1.1 if crouched else 1.75
	_shape_node.position.y = _shape.height * 0.5


## Sits down on a seat, on the free place nearest you. Walking off (or F) stands you up.
func sit(id: int) -> void:
	if not Shed.furniture.has(id) or Shed.held_by(Shed.me()) != 0:
		Shed.feedback.emit("Put the part down first." if Shed.furniture.has(id) else "", false)
		return
	var f: Dictionary = Shed.furniture[id]
	var model := str(f["model"])
	var best := Vector3.ZERO
	var best_d := INF
	var size: Vector3 = Equipment.get_model(model).get("size", Vector3.ONE)
	for n in maxi(1, roundi(size.x / 0.6)):
		var p := EquipmentView.sit_point(model, n)
		var d: float = ((f["xf"] as Transform3D) * p).distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	set_crouched(false)
	seat = id
	# Sit with your back to the seat's back, facing out the front, eyes above the cushion.
	_seat_spot = best + Vector3.UP * SEATED_EYE
	rotation.y = (f["xf"] as Transform3D).basis.get_euler().y
	_shape_node.disabled = true
	Shed.feedback.emit("Sitting down. Move or press F to get up.", true)


func stand_up() -> void:
	if seat == 0:
		return
	var f: Dictionary = Shed.furniture.get(seat, {})
	seat = 0
	_shape_node.disabled = false
	if not f.is_empty():
		var fwd := (f["xf"] as Transform3D).basis.z
		global_position = (f["xf"] as Transform3D).origin + Vector3(fwd.x, 0.0, fwd.z).normalized() * 0.75 + Vector3.UP * 0.05


func _look(dyaw: float, dpitch: float) -> void:
	rotation.y += dyaw
	_pitch = clampf(_pitch + dpitch, -1.45, 1.45)
	camera.rotation.x = _pitch


func _spray_changed() -> void:
	get_viewport().set_input_as_handled()
	_set_tool_view()
	_plan_key = ""
	Shed.feedback.emit("Spray can: %s" % spray_text(), true)


## "Gloss red": what the spray can is loaded with.
func spray_text() -> String:
	return "%s %s" % [Shed.FINISH_NAMES[Shed.FINISHES[spray_finish]], Shed.PAINT_NAMES[spray_color]]


func _cycle_tool(step: int) -> void:
	set_tool(TOOLS[(TOOLS.find(tool) + step + TOOLS.size()) % TOOLS.size()])


func set_tool(new_tool: String) -> void:
	if new_tool == tool:
		return
	if Shed.held_by(Shed.me()) != 0 and new_tool != "hands":
		Shed.feedback.emit("Put the part down first.", false)
		return
	tool = new_tool
	progress = 0.0
	_hold = 0.0
	_set_tool_view()
	_send_status("")


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	var running := false
	if controls_enabled:
		input = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
		input += Controls.stick()
		input = input.limit_length(1.0)
		running = Input.is_action_pressed("sprint")
		var look := Controls.stick(true)
		if tyre_game:
			tyre_game.aim(look)
		elif look != Vector2.ZERO:
			_look(-look.x * PAD_LOOK * delta, -look.y * PAD_LOOK * 0.7 * delta)
	if blast or Shed.blasting(Shed.me()) != 0:
		# At the sandblaster: the keys and the left stick turn the engine instead of walking.
		_blast_frame(delta, input)
		input = Vector2.ZERO
	if seat != 0:
		if not Shed.furniture.has(seat) or Shed.furniture[seat]["mover"] != 0 or input.length() > 0.5:
			stand_up()
		else:
			input = Vector2.ZERO
			global_position = Shed.furniture[seat]["xf"] * _seat_spot - Vector3.UP * SEATED_EYE
			velocity = Vector3.ZERO
	var pace := CROUCH_WALK if crouched else (RUN if running else WALK)
	if Shed.pushing_bike(Shed.me()) != 0:
		pace = minf(pace, 2.4)   # a bike is heavy to wheel about
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)) * pace
	velocity.x = move_toward(velocity.x, wish.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 30.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if is_on_floor():
		_stride += Vector2(velocity.x, velocity.z).length() * delta
		if _stride > (0.85 if running else 0.7):
			_stride = 0.0
			Sfx.footstep(global_position, running)
	if global_position.y < -20.0:
		place(Workshop.walker_spawn(0))
	_eye = move_toward(_eye, CROUCH_EYE if crouched else EYE, delta * 4.0)
	if seat != 0:
		_eye = SEATED_EYE
	camera.position.y = _eye
	if _f_bike != 0:
		_f_time += delta
		if _f_time >= HOLD_TO_PUSH:
			Shed.request({"a": "grab_bike", "bike": _f_bike})
			_f_bike = 0
	if _f_seat != 0:
		_f_time += delta
		if _f_time >= HOLD_TO_PUSH:
			Shed.request({"a": "grab", "furniture": _f_seat})
			_f_seat = 0
	_update_turning(delta)
	var pushed := Shed.moving(Shed.me())
	var wheeling := Shed.pushing_bike(Shed.me())
	if wheeling != 0:
		_push_bike(wheeling, delta)
	elif pushed != 0:
		_push(pushed, delta)
	if pushed == 0 or wheeling != 0:
		_carrying = 0
		_update_ghost(0, Transform3D())
	if (pushed != 0 or wheeling != 0 or blast) and _part_ghost:
		_part_ghost.visible = false
	if wheeling == 0 and pushed == 0 and blast:
		target = {}
		plan = {}
		alt_plan = {}
		info = _blast_info()
		_highlight()
	elif wheeling == 0 and pushed == 0:
		if collision_mask != 1 | 2 | 4:
			collision_mask = 1 | 2 | 4
		_update_target()
	if blast:
		_update_held_view()
		return
	_update_work(delta)
	_update_scrap(delta)
	_update_held_view()
	_update_jet()
	_update_mist()
	if tool == "watch" and is_instance_valid(_tool_view):
		ToolModels.set_hand_seconds(_tool_view, stopwatch.elapsed())


# ---------------------------------------------------------------------------- targeting

func _update_target() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | Workshop.INTERACT_LAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and (hit["collider"] as Object).has_meta("shelf"):
		# The space over a shelf board: a part sitting on it, further in, comes first.
		var skip: Array[RID] = [get_rid(), hit["rid"]]
		for i in 3:
			q.exclude = skip
			var past := get_world_3d().direct_space_state.intersect_ray(q)
			if past.is_empty():
				break
			var pc: Object = past["collider"]
			if pc.has_meta("spot") or pc.has_meta("item"):
				hit = past
				break
			if not pc.has_meta("shelf"):
				break
			skip.append(past["rid"])
	var t := {}
	if hit:
		var c: Object = hit["collider"]
		if c.has_meta("bike") and Shed.bikes.has(int(c.get_meta("bike"))):
			t = {"kind": "part", "bike": int(c.get_meta("bike")), "slot": str(c.get_meta("slot"))}
		elif c.has_meta("engine") and Shed.is_engine(int(c.get_meta("engine"))):
			t = {"kind": "part", "engine": int(c.get_meta("engine")), "slot": str(c.get_meta("slot"))}
		elif c.has_meta("spot"):
			t = {"kind": "spot", "spot": str(c.get_meta("spot"))}
		elif c.has_meta("pc"):
			t = {"kind": "pc"}
		elif c.has_meta("dyno"):
			t = {"kind": "dyno"}
		elif c.has_meta("screen"):
			t = {"kind": "screen", "screen": str(c.get_meta("screen"))}
		elif c.has_meta("bin"):
			t = {"kind": "bin", "bin": str(c.get_meta("bin"))}
		elif c.has_meta("radio"):
			t = {"kind": "radio"}
		elif c.has_meta("door_switch"):
			t = {"kind": "door"}
		elif c.has_meta("light_switch"):
			# The shed's own switch says true; a side room's says which room.
			var room = c.get_meta("light_switch")
			t = {"kind": "lights", "room": room if room is String else ""}
		elif c.has_meta("dyno_kit"):
			t = {"kind": "dyno_kit", "kit": str(c.get_meta("dyno_kit")), "point": int(c.get_meta("point", 0))}
		elif c.has_meta("whiteboard"):
			t = {"kind": "board"}   # the Whiteboard handles drawing on it itself
		elif c.has_meta("top"):
			# The top of a workbench, washer or repair machine: parts go anywhere on it.
			t = {"kind": "top", "top": str(c.get_meta("top")), "furniture": int(c.get_meta("furniture", 0))}
		elif c.has_meta("furniture") and Shed.furniture.has(int(c.get_meta("furniture"))):
			t = {"kind": "furniture", "furniture": int(c.get_meta("furniture"))}
		elif c.has_meta("label") and Shed.furniture.has(int(c.get_meta("label"))):
			t = {"kind": "label", "furniture": int(c.get_meta("label"))}
		elif c.has_meta("item") and Shed.items.has(int(c.get_meta("item"))):
			t = {"kind": "item", "item": int(c.get_meta("item"))}
		elif Shed.held_by(Shed.me()) != 0 and (c is CollisionObject3D) and (c as CollisionObject3D).collision_layer & 1:
			t = {"kind": "surface"}
		if not t.is_empty():
			t["at"] = hit["position"]
		# Anything flat enough can take a part put down on it, whatever the crosshair is on.
		if not t.is_empty() and (hit["normal"] as Vector3).y > 0.6:
			# Turned the way you face, and however far you've turned the part in your hands.
			t["drop"] = Transform3D(Basis(Vector3.UP, rotation.y + hold_turn), hit["position"])
	target = t
	plan = _make_plan()
	_scale_time(plan)
	_scale_time(alt_plan)
	info = _describe()
	_update_part_ghost()
	var held_now := Shed.held_by(Shed.me())
	if held_now != 0 and tool == "hands" and str(plan.get("action", {}).get("a", "")) in ["drop", "set_down"]:
		info += "\n%s: turn it before you put it down (%s)%s" % [_keys("rotate_left", "rotate_right"),
			"a quarter at a time" if Settings.snap_placement else "hold to turn it freely",
			"  ·  turned %d°" % roundi(rad_to_deg(hold_turn)) if absf(hold_turn) > 0.01 else ""]
	if held_now != 0:
		info += "\nHold %s: scrap the %s for good" % [_keys("scrap"), Shed.item_title(held_now).to_lower()]
	var geo_key := Settings.binding_text("geometry_mode", false)
	if str(target.get("kind", "")) == "part" and int(target.get("bike", 0)) != 0 and geo_key != "":
		info += "\n%s: geometry mode (move, turn and size this bike's parts)" % geo_key
	if str(target.get("kind", "")) == "spot" and Shed.spot_role(str(target["spot"])) == "blaster" \
			and Shed.item_at_spot(str(target["spot"])) != 0 and Shed.held_by(Shed.me()) == 0:
		info += "\nF: hands in the gloves and sandblast it back to bare metal"
	if not _cover.is_empty() and target_item() == int(_cover["item"]):
		var st := cover_stats()
		info += "\nSprayed so far: %d%% covered%s" % [roundi(st["covered"] * 100.0),
			"  ·  overdone in places" if st["over"] > 0.04 else ""]
	_highlight()


# ---------------------------------------------------------------------------- moving furniture

## A boxed part under the crosshair, which F unpacks.
func _target_box() -> int:
	var item := target_item()
	if item != 0 and Shed.items[item].get("boxed", false) and target.get("kind", "") in ["item", "spot"]:
		return item
	return 0


## The equipment under the crosshair, which F grabs to push around: an engine stand, shelving,
## the top of a bench or washer, or the whiteboard.
func _target_furniture() -> int:
	match str(target.get("kind", "")):
		"furniture", "label":
			return int(target["furniture"])
		"top":
			return int(target.get("furniture", 0))
		"board":
			return Shed.whiteboard_id()
		"spot":
			var f := Shed.furniture_of_spot(str(target["spot"]))
			if not f.is_empty():
				return int(f["id"])
	return 0


## How far in front of you equipment you're carrying sits: arm's length (`base`) plus however
## far the mouse wheel has pushed it out, kept between CARRY_MIN and CARRY_MAX of that.
static func carry_distance(base: float, extra: float) -> float:
	return base + clampf(extra, CARRY_MIN, CARRY_MAX)


## Pushes the equipment you're carrying a step further away (1) or pulls it a step closer (-1).
func nudge_carry(dir: int) -> void:
	carry_reach = clampf(carry_reach + CARRY_STEP * dir, CARRY_MIN, CARRY_MAX)


## Turns snapping to walls and corners on or off (the Esc menu has it too).
func toggle_snap() -> void:
	Settings.snap_placement = not Settings.snap_placement
	Settings.save_settings()
	Shed.feedback.emit("Snapping to walls and corners %s" % ("on" if Settings.snap_placement else "off"), true)


## A press of a rotate key (1 left, -1 right): the equipment you carry or the part in your hands
## turns a quarter with snapping on, or a nudge with it off (holding the key turns it on, see
## _update_turning). A poster turns between portrait and landscape on the wall.
func turn_step(dir: int) -> void:
	var pushed := Shed.moving(Shed.me())
	if pushed != 0:
		var f: Dictionary = Shed.furniture[pushed]
		if Equipment.is_wall(str(f.get("model", ""))):
			if f["kind"] == "poster":
				Shed.request({"a": "turn_poster", "furniture": pushed, "turn": int(f.get("turn", 0)) + dir})
			else:
				Shed.feedback.emit("The %s only hangs one way up." % Shed.furniture_name(f).to_lower(), false)
			return
		carry_turn = _stepped(carry_turn, dir)
	elif Shed.held_by(Shed.me()) != 0:
		hold_turn = _stepped(hold_turn, dir)
		_room_cache = {}


static func _has_parts_on(furniture_id: int) -> bool:
	for spot in Shed.furniture_spots(furniture_id):
		if Shed.item_at_spot(spot) != 0:
			return true
	return false


## The keys (or pad buttons, with a pad in use) on actions, for the hints: ", / .".
static func _keys(a: String, b := "") -> String:
	var pad := Controls.active_device >= 0
	var out := []
	for action in [a, b]:
		if action != "":
			var t := Settings.binding_text(action, pad)
			if t != "":
				out.append(t.get_slice(" / ", 0))
	return " / ".join(out) if not out.is_empty() else "-"


static func _stepped(angle: float, dir: int) -> float:
	if Settings.snap_placement:
		return wrapf(Placement.snap_yaw(angle + dir * PI * 0.5), -PI, PI)
	return wrapf(angle + dir * TURN_NUDGE, -PI, PI)


## With snapping off, holding a rotate key keeps turning what you hold or carry.
func _update_turning(delta: float) -> void:
	var spin := Input.get_axis("rotate_right", "rotate_left") if controls_enabled else 0.0
	_turn_time = _turn_time + delta if spin != 0.0 else 0.0
	var held := Shed.held_by(Shed.me())
	if held != _held_for:
		# Something new in your hands starts the way you face.
		_held_for = held
		hold_turn = 0.0
	if Settings.snap_placement or _turn_time < TURN_HOLD:
		return
	var pushed := Shed.moving(Shed.me())
	if pushed != 0 and not Equipment.is_wall(str(Shed.furniture[pushed].get("model", ""))):
		carry_turn = wrapf(carry_turn + spin * TURN_RATE * delta, -PI, PI)
	elif pushed == 0 and held != 0:
		hold_turn = wrapf(hold_turn + spin * TURN_RATE * delta, -PI, PI)


## What the scrap key would scrap: the equipment you're carrying or the part in your hands, as
## the host's action fields, or {}.
func _scrap_target() -> Dictionary:
	var pushed := Shed.moving(Shed.me())
	if pushed != 0:
		return {"furniture": pushed, "name": Shed.furniture_name(Shed.furniture[pushed]).to_lower()}
	var held := Shed.held_by(Shed.me())
	if held != 0:
		return {"item": held, "name": Shed.item_title(held).to_lower()}
	return {}


## Holding the scrap key: once it's been held SCRAP_HOLD seconds, a second press scraps it.
func _update_scrap(delta: float) -> void:
	var what := _scrap_target()
	if not scrap_armed.is_empty():
		var same: bool = not what.is_empty() and what.get("furniture", 0) == scrap_armed.get("furniture", 0) \
			and what.get("item", 0) == scrap_armed.get("item", 0)
		if not same or Time.get_ticks_msec() > int(scrap_armed["until"]):
			scrap_armed = {}
			Shed.feedback.emit("Kept it.", true)
	var down := controls_enabled and Input.is_action_pressed("scrap")
	if not down:
		_scrap_hold = 0.0
		_scrap_release = false
		return
	if what.is_empty() or not scrap_armed.is_empty() or _scrap_release:
		return
	var why := Shed.check(Shed.me(), _scrap_action(what))
	if why != "":
		Shed.feedback.emit(why, false)
		_scrap_release = true
		return
	_scrap_hold += delta
	progress = clampf(_scrap_hold / SCRAP_HOLD, 0.0, 1.0)
	if _scrap_hold >= SCRAP_HOLD:
		_scrap_hold = 0.0
		_scrap_release = true
		progress = 0.0
		scrap_armed = what.duplicate()
		scrap_armed["until"] = Time.get_ticks_msec() + int(SCRAP_CONFIRM * 1000.0)
		var key := Settings.binding_text("scrap", Controls.active_device >= 0).get_slice(" / ", 0)
		Shed.feedback.emit("Scrap the %s for good? Press %s again in the next few seconds to scrap it." % [what["name"], key], false)


## The second press after holding the scrap key: it goes for good.
func confirm_scrap() -> void:
	if scrap_armed.is_empty():
		return
	Shed.request(_scrap_action(scrap_armed))
	scrap_armed = {}
	Sfx.play_at("pickup", camera.global_position, -4.0)


func _scrap_action(what: Dictionary) -> Dictionary:
	if what.has("furniture"):
		return {"a": "scrap", "furniture": int(what["furniture"])}
	# Anything bolted to it or a tyre on it goes on the floor in front of you.
	var fwd := -transform.basis.z
	var at := global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 0.8
	return {"a": "scrap", "item": int(what["item"]), "at": Transform3D(Basis(Vector3.UP, rotation.y), at)}


## Where the equipment being pushed sits: in front of you, square to you, as far out as the
## mouse wheel has put it (but not through a wall). With snapping on it squares up to the walls
## and slides flush against a wall or into a corner that's close (see Placement).
func _push_transform(id: int) -> Transform3D:
	var model := str(Shed.furniture[id].get("model", ""))
	var size := Shed.furniture_size(Shed.furniture[id])
	snap_info = {}
	if Equipment.is_wall(model):
		return _wall_transform(size)
	var ignore: Array[RID] = [get_rid()]
	var view: Node = get_tree().get_first_node_in_group("workshop")
	if view:
		# Not the thing being moved, or a ramp would climb up its own deck.
		ignore.append_array(view.furniture_rids(id))
	# How far it reaches towards you and away, turned however you've turned it.
	var half := absf(cos(carry_turn)) * size.z * 0.5 + absf(sin(carry_turn)) * size.x * 0.5
	var base := 1.05 if Shed.furniture[id]["kind"] == "stand" else 0.55 + half
	var fwd := -transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var dist := carry_distance(base, carry_reach)
	if dist > base:
		dist = minf(dist, maxf(base, _wall_gap(flat, ignore) - half - 0.02))
	var at := global_position + flat * dist
	at.y = global_position.y
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 2.0, 1)
	q.exclude = ignore
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and (hit["normal"] as Vector3).y > 0.8:
		at.y = (hit["position"] as Vector3).y
	var xf := Transform3D(Basis(Vector3.UP, rotation.y + carry_turn), at)
	if Settings.snap_placement and not Equipment.is_yard(model):
		snap_info = Placement.snap(get_world_3d().direct_space_state, xf, size, ignore)
		xf = snap_info["xf"]
	return xf


## How far ahead the nearest wall is, low down and at waist height. Other equipment doesn't
## count: you can hold something out over a bench.
func _wall_gap(dir: Vector3, ignore: Array[RID]) -> float:
	var space := get_world_3d().direct_space_state
	var best := INF
	for h in [0.3, 1.0]:
		var from: Vector3 = global_position + Vector3.UP * h
		var skip: Array[RID] = ignore.duplicate()
		for i in 6:
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * (CARRY_MAX + 4.0), 1)
			q.exclude = skip
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			if _is_equipment(hit["collider"]):
				skip.append(hit["rid"])
				continue
			best = minf(best, from.distance_to(hit["position"]))
			break
	return best


static func _is_equipment(o: Object) -> bool:
	var n := o as Node
	while n != null:
		if n is EquipmentView:
			return true
		n = n.get_parent()
	return false


var _on_wall := false


## Where a poster, TV or the whiteboard you're carrying would hang: flat on the wall you're
## looking at, at the height you're looking, or held up in front of you if there's no wall in
## reach (the mouse wheel reaches further). With snapping on, it slides into a corner that's close.
func _wall_transform(size: Vector3) -> Transform3D:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (3.0 + maxf(carry_reach, 0.0)), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and absf((hit["normal"] as Vector3).y) < 0.3:
		var n: Vector3 = hit["normal"]
		n.y = 0.0
		n = n.normalized()
		var at: Vector3 = hit["position"] + n * 0.025
		at.y = clampf(at.y, size.y * 0.5 + 0.5, Workshop.HEIGHT - size.y * 0.5 - 0.1)
		at = _clear_of_corners(at, n, size)
		if Settings.snap_placement:
			at = _into_corner(at, n, size)
		_on_wall = true
		return Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), at)
	_on_wall = false
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	return Transform3D(Basis(Vector3.UP, rotation.y + PI), from + flat * 0.9 + Vector3.DOWN * 0.2)


## Slides something hanging on a wall along it until neither end pokes into a wall round the
## corner (big TVs are three metres wide). Looks along the wall both ways, just in front of it.
func _clear_of_corners(at: Vector3, normal: Vector3, size: Vector3) -> Vector3:
	var along := normal.cross(Vector3.UP).normalized()
	var space := get_world_3d().direct_space_state
	var half := size.x * 0.5 + 0.02
	var from := at + normal * maxf(size.z, 0.06)
	for i in 2:
		var free := []
		for dir in [along, -along]:
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * half, 1)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			free.append(from.distance_to(hit["position"]) if hit else half)
		var shift := (half - float(free[0])) * -1.0 + (half - float(free[1]))
		if absf(shift) < 0.001:
			break
		at += along * shift
		from += along * shift
	return at


## Snapping a wall hanging: with a corner within Placement.SNAP_REACH of one end, slides it
## along to sit tight in the corner.
func _into_corner(at: Vector3, normal: Vector3, size: Vector3) -> Vector3:
	var along := normal.cross(Vector3.UP).normalized()
	var space := get_world_3d().direct_space_state
	var half := size.x * 0.5
	var from := at + normal * maxf(size.z, 0.06)
	var best := INF
	var best_dir := Vector3.ZERO
	for dir in [along, -along]:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * (half + Placement.SNAP_REACH), 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit and from.distance_to(hit["position"]) < best:
			best = from.distance_to(hit["position"])
			best_dir = dir
	if best == INF:
		return at
	snap_info = {"walls": [normal, -best_dir]}
	return at + best_dir * (best - half - Placement.GAP)


## The outline on the floor of where the equipment you're carrying will go, blue when it has
## snapped to a wall or corner.
func _update_ghost(id: int, xf: Transform3D) -> void:
	var model := str(Shed.furniture.get(id, {}).get("model", ""))
	if id == 0 or Equipment.is_wall(model):
		if _ghost:
			_ghost.visible = false
		return
	var size := Shed.furniture_size(Shed.furniture[id])
	var snapped: bool = not (snap_info.get("walls", []) as Array).is_empty()
	var sig := "%s:%s" % [model, snapped]
	if _ghost == null:
		_ghost = Node3D.new()
		_ghost.top_level = true
		add_child(_ghost)
	if sig != _ghost_sig:
		_ghost_sig = sig
		for c in _ghost.get_children():
			c.free()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.25, 0.75, 1.0, 0.3) if snapped else Color(1.0, 1.0, 1.0, 0.18)
		var edge := mat.duplicate() as StandardMaterial3D
		edge.albedo_color.a = 0.85
		var pieces := [[Vector3(size.x, 0.004, size.z), Vector3.ZERO, mat]]
		for side in [-1.0, 1.0]:
			pieces.append([Vector3(size.x, 0.008, 0.03), Vector3(0.0, 0.002, side * size.z * 0.5), edge])
			pieces.append([Vector3(0.03, 0.008, size.z), Vector3(side * size.x * 0.5, 0.002, 0.0), edge])
		for p in pieces:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = p[0]
			mi.mesh = box
			mi.material_override = p[2]
			mi.position = p[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost.add_child(mi)
	_ghost.global_transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.012)
	_ghost.visible = true


## The outline of where the part in your hands will go down, turned as it'll lie: on the floor
## or a bench, washer, repair machine or shelf. Red when it can't go there.
func _update_part_ghost() -> void:
	var held := Shed.held_by(Shed.me())
	var a: Dictionary = plan.get("action", {})
	var xf = null
	if held != 0 and tool == "hands":
		match str(a.get("a", "")):
			"drop":
				xf = a["xf"]
			"set_down":
				var s := Shed.surface(str(a["top"]))
				if not s.is_empty():
					xf = (s["xf"] as Transform3D) * Shed._flat_place(a["xf"], float(s["top"]))
	if not (xf is Transform3D):
		if _part_ghost:
			_part_ghost.visible = false
		return
	var foot := Shed.item_footprint(held)
	var ok := str(plan.get("blocked", "")) == ""
	var sig := "%.3f:%.3f:%s" % [foot.x, foot.y, ok]
	if _part_ghost == null:
		_part_ghost = Node3D.new()
		_part_ghost.top_level = true
		add_child(_part_ghost)
	if sig != _part_ghost_sig:
		_part_ghost_sig = sig
		for c in _part_ghost.get_children():
			c.free()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.16) if ok else Color(1.0, 0.25, 0.2, 0.2)
		var edge := mat.duplicate() as StandardMaterial3D
		edge.albedo_color.a = 0.8
		var bar := 0.012
		var pieces := [[Vector3(foot.x, 0.002, foot.y), Vector3.ZERO, mat]]
		for side in [-1.0, 1.0]:
			pieces.append([Vector3(foot.x, 0.004, bar), Vector3(0.0, 0.001, side * foot.y * 0.5), edge])
			pieces.append([Vector3(bar, 0.004, foot.y), Vector3(side * foot.x * 0.5, 0.001, 0.0), edge])
		# A notch on the front edge, so you can see which way round it goes.
		pieces.append([Vector3(minf(0.06, foot.x * 0.5), 0.005, bar * 2.0), Vector3(0.0, 0.002, -foot.y * 0.5), edge])
		for p in pieces:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = p[0]
			mi.mesh = box
			mi.material_override = p[2]
			mi.position = p[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_part_ghost.add_child(mi)
	_part_ghost.global_transform = Transform3D((xf as Transform3D).basis, (xf as Transform3D).origin + Vector3.UP * 0.006)
	_part_ghost.visible = true


## "Snapped into the corner" or "Snapped to the wall", or "" when it hasn't snapped.
func snap_text() -> String:
	match (snap_info.get("walls", []) as Array).size():
		0:
			return ""
		1:
			return "Snapped flush to the wall"
	return "Snapped into the corner"


func _push(id: int, delta: float) -> void:
	if id != _carrying:
		# Picked up something new: it starts at arm's length, the way you face.
		_carrying = id
		carry_reach = 0.0
		carry_turn = 0.0
	var xf := _push_transform(id)
	var view: Node = get_tree().get_first_node_in_group("workshop")
	if view:
		view.preview_furniture(id, xf)
	_update_ghost(id, xf)
	_push_timer += delta
	if _push_timer > 0.1:
		_push_timer = 0.0
		Shed.request({"a": "move_furniture", "furniture": id, "xf": xf})
	target = {}
	plan = {}
	var pad := Controls.active_device >= 0
	var lines := []
	var what := Shed.furniture_name(Shed.furniture[id]).to_lower()
	if Equipment.is_wall(str(Shed.furniture[id].get("model", ""))):
		lines.append("Carrying the %s" % what)
		lines.append("F: hang it here" if _on_wall else "Look at a wall to hang it up.")
	else:
		lines.append("Moving the %s" % what)
		lines.append("Walk to move it and turn to face it the way you want.")
		lines.append("%s: push it further away or pull it closer" % ("LB / RB" if pad else "Mouse wheel"))
		lines.append("F: put it down here")
		lines.append("%s: turn it (%s)" % [_keys("rotate_left", "rotate_right"),
			"a quarter at a time" if Settings.snap_placement else "hold to turn it freely"])
	if Shed.furniture[id]["kind"] == "poster":
		lines.append("%s: turn it (portrait or landscape)" % _keys("rotate_left", "rotate_right"))
	if Shed.check(Shed.me(), {"a": "scrap", "furniture": id}) == "":
		lines.append("Hold %s: scrap it for good%s" % [_keys("scrap"), ", and drop what's on it" if _has_parts_on(id) else ""])
	var snap := snap_text()
	if Settings.snap_placement:
		lines.append("%s%s: snapping off" % [snap + "  ·  " if snap != "" else "Snapping to walls and corners  ·  ", "X" if pad else "R / right mouse"])
	else:
		lines.append("Snapping off  ·  %s: snap to walls and corners" % ("X" if pad else "R / right mouse"))
	info = "\n".join(lines)
	_highlight()


## Where the bike you're wheeling goes: beside you on your right, pointing the way you face,
## with you holding the bars.
func _bike_push_transform(_id: int) -> Transform3D:
	var heading := rotation.y
	var b := Basis(Vector3.UP, heading)
	var at := global_position + b * Vector3(0.75, 0.0, 0.25)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 2.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	at.y = (hit["position"] as Vector3).y if hit else global_position.y
	return Transform3D(b, at)


func _push_bike(id: int, delta: float) -> void:
	# Parked bikes are solid to walk into; the one in your hands mustn't shove you about.
	collision_mask = 1 | 2
	var xf := _bike_push_transform(id)
	var view: Node = get_tree().get_first_node_in_group("workshop")
	if view:
		view.preview_bike(id, xf)
	_push_timer += delta
	if _push_timer > 0.1:
		_push_timer = 0.0
		Shed.request({"a": "move_bike", "bike": id, "xf": xf})
	target = {}
	plan = {}
	alt_plan = {}
	info = "Wheeling %s\nWalk to push it, back up to pull it. Bikes don't have reverse.\nF: let go (it goes on its stand, or into a bay's paddock stand)" % \
		str(Shed.bikes[id]["name"])
	_highlight()


## The bike or engine a part target belongs to, as action fields.
func _where() -> Dictionary:
	if int(target.get("engine", 0)) != 0:
		return {"engine": int(target["engine"]), "slot": str(target["slot"]), "crouched": crouched}
	return {"bike": int(target.get("bike", 0)), "slot": str(target.get("slot", "")), "crouched": crouched}


## The item the crosshair is on: a fitted part, or whatever sits on a spot.
func target_item() -> int:
	match str(target.get("kind", "")):
		"part":
			return Shed.item_at_target(target)
		"spot":
			return Shed.item_at_spot(str(target["spot"]))
		"item":
			return int(target["item"])
	return 0


func _make_plan() -> Dictionary:
	alt_plan = {}
	var me := Shed.me()
	var held := Shed.held_by(me)
	var kind := str(target.get("kind", ""))
	if kind == "":
		return {}
	if kind == "dyno_kit" or Shed.hose_holder() == me:
		# The dyno room's straps and extraction hose (carrying the hose, that's all you can do).
		var dp := DynoRoom.plan_for(target, me)
		if not dp.is_empty():
			dp["blocked"] = Shed.check(me, dp["action"])
		return dp
	if held != 0 and tool == "hands" and PartsDB.is_fluid(Shed.items[held]["part"]):
		var fp := _fluid_plan(held, kind)
		if not fp.is_empty() or kind == "part":
			return fp
	var item_id := target_item()
	var p := {}
	if kind == "label":
		return {"action": {"a": "write_label"}, "time": 0.15, "verb": "write a label for these shelves", "blocked": ""}
	if kind in ["furniture", "door", "lights", "board", "screen"]:
		return {}
	if kind == "radio":
		if Shed.stations.is_empty():
			return {}
		if not Shed.radio["on"]:
			p = {"action": {"a": "radio", "on": true}, "time": 0.2, "verb": "switch the radio on"}
		else:
			var next := (int(Shed.radio["station"]) + 1) % Shed.stations.size()
			p = {"action": {"a": "radio", "on": true, "station": next}, "time": 0.2,
				"verb": "tune to %s" % Shed.station_name(next)}
		p["blocked"] = Shed.check(me, p["action"])
		return p
	match tool:
		"hands":
			if held != 0:
				var held_name := Shed.item_title(held)
				var bay := Shed.bay_at(target["at"]) if target.has("at") and kind != "part" else -1
				if bay >= 0 and Shed.items[held]["kind"] == "frame" and Shed.bay_is_free(bay):
					# A bare frame on an empty bay's paddock stand starts a bike from scratch.
					p = {"action": {"a": "start_build", "bay": bay}, "time": 1.5,
						"verb": "set the frame up on the paddock stand in bay %d" % (bay + 1)}
					p["blocked"] = Shed.check(me, p["action"])
					return p
				match kind:
					"part":
						var a := _where()
						a["a"] = "install"
						p = {"action": a, "time": 1.2, "verb": "fit the " + held_name}
					"spot":
						var on_spot := Shed.item_at_spot(str(target["spot"]))
						if Shed.spot_role(str(target["spot"])) == "changer" and on_spot != 0 and Shed.items[held]["kind"] == "tyre":
							# Work the tyre on round the rim: a skill game (TyreGame).
							p = {"action": {"a": "tyre_fit", "spot": target["spot"]}, "time": TyreGame.GRACE + TyreGame.DURATION,
								"game": "tyre", "verb": "work the tyre on: keep the lever on the marker round the rim"}
						elif Shed.is_engine(on_spot) and not Shed.is_engine(held) and Shed.surface_of_spot(str(target["spot"])) == "":
							# Building an engine back up: fit the part to the block on the stand.
							p = {"action": {"a": "install", "engine": on_spot, "slot": ""}, "time": 1.2, "verb": "fit the " + held_name}
						elif Shed.surface_of_spot(str(target["spot"])) != "":
							# Looking at a part on a bench, washer or repair machine: down beside it.
							p = _set_down_plan(Shed.surface_of_spot(str(target["spot"])))
						elif on_spot != 0 and target.has("drop"):
							p = {"action": {"a": "drop", "xf": target["drop"]}, "time": 0.25, "verb": "put it down here"}
						else:
							p = {"action": {"a": "place", "spot": target["spot"]}, "time": 0.25, "verb": "put it down"}
					"bin":
						var which := str(target.get("bin", "general"))
						p = {"action": {"a": "bin", "bin": which}, "time": 0.4,
							"verb": ("throw the %s away" if which == "general" else "recycle the %s") % held_name}
					"top":
						p = _set_down_plan(str(target["top"]))
					"surface", "item":
						if target.has("drop"):
							p = {"action": {"a": "drop", "xf": target["drop"]}, "time": 0.25, "verb": "put it down here"}
			else:
				match kind:
					"part":
						var a := _where()
						var slot := str(target.get("slot", ""))
						if slot in ["side_stand", "centre_stand"] and int(target.get("bike", 0)) != 0 and Shed.bolted_at_target(target):
							# Working the stand itself: kick it down, or heave the bike up onto it.
							var which := slot.trim_suffix("_stand")
							p = {"action": {"a": "set_stand", "bike": int(target["bike"]), "stand": which}, "time": 0.6 if which == "side" else 1.4,
								"verb": "kick the side stand down" if which == "side" else "heave it up onto the centre stand"}
						else:
							a["a"] = "remove"
							p = {"action": a, "time": 1.0, "verb": "take it off"}
					"spot":
						if item_id != 0 and Shed.spot_role(str(target["spot"])) == "changer" and Shed.tyre_on_wheel(item_id) != 0:
							# On the tyre changer: break the bead and lever the old tyre off, or lift the wheel off whole.
							p = {"action": {"a": "tyre_remove", "spot": target["spot"]}, "time": Shed.TYRE_REMOVE_TIME,
								"verb": "break the bead and lever the tyre off"}
							alt_plan = {"action": {"a": "take", "spot": target["spot"]}, "time": 0.4, "verb": "lift the wheel off, tyre and all"}
							alt_plan["blocked"] = Shed.check(me, alt_plan["action"])
						elif item_id != 0:
							p = {"action": {"a": "take", "spot": target["spot"]}, "time": 0.25, "verb": "pick it up"}
					"item":
						p = {"action": {"a": "take", "item": item_id}, "time": 0.25, "verb": "pick it up"}
					"pc":
						p = {"action": {"a": "computer"}, "time": 0.15, "verb": "use the parts computer"}
					"dyno":
						p = {"action": {"a": "tuning"}, "time": 0.15, "verb": "use the dyno desk"}
		"wrench":
			if kind == "part":
				var a := _where()
				var bolted := Shed.bolted_at_target(target)
				a["a"] = "unbolt" if bolted else "bolt"
				p = {"action": a, "time": 1.6, "verb": "unbolt it" if bolted else "bolt it up"}
				if str(target.get("slot", "")) == "chain" and int(target.get("bike", 0)) != 0:
					alt_plan = {"action": {"a": "adjust_chain", "bike": int(target["bike"]), "crouched": crouched}, "time": 3.0,
						"verb": "adjust the chain tension"}
					alt_plan["blocked"] = Shed.check(me, alt_plan["action"])
		"brush":
			if item_id != 0 or target.has("at"):
				# The brush scrubs everything around where it lands, not just one part.
				var near := [] if item_id == 0 else [item_id]
				var view: Node = get_tree().get_first_node_in_group("workshop")
				if view and target.has("at"):
					for id in view.items_near(target["at"], BRUSH_REACH * Progress.spread_mult(me, "brush")):
						if not near.has(id) and Shed.items.has(id) and float(Shed.items[id]["dirt"]) >= 0.02:
							near.append(id)
				var dirt := 0.0
				for id in near:
					dirt += float(Shed.items[id]["dirt"])
				if not near.is_empty():
					p = {"action": {"a": "clean_many", "items": near}, "time": 1.0 + minf(2.5 * dirt, 5.0),
						"verb": "scrub it clean" if near.size() == 1 else "scrub %d parts clean" % near.size()}
		"repair":
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				var batch: Array = Shed.repair_batch(str(it["ref"])) if it["at"] == "spot" else []
				if batch.size() > 1:
					p = {"action": {"a": "repair_many", "items": batch}, "time": Shed.repair_time(batch),
						"verb": "restore all %d parts on the %s" % [batch.size(), Shed.furniture_name(Shed.furniture_of_spot(str(it["ref"]))).to_lower()]}
				else:
					p = {"action": {"a": "repair", "item": item_id}, "time": Shed.repair_time([item_id]),
						"verb": "grind off the rust and rebuild it"}
			elif kind == "top" and int(target.get("furniture", 0)) != 0 and Shed.surface(str(target["top"])).get("kind", "") == "repair":
				# Aimed at the machine's top between parts: it does the lot.
				var batch: Array = Shed.repair_batch(str(Shed.furniture_spots(int(target["furniture"]))[0]))
				if not batch.is_empty():
					p = {"action": {"a": "repair_many", "items": batch}, "time": Shed.repair_time(batch),
						"verb": "restore all %d part%s on the %s" % [batch.size(), "" if batch.size() == 1 else "s",
							Shed.surface_name(str(target["top"])).to_lower()]}
		"spray":
			if item_id != 0:
				p = {"action": {"a": "paint", "item": item_id, "color": spray_color, "finish": Shed.FINISHES[spray_finish]},
					"time": 1.5, "coverage": true, "verb": "spray it %s: sweep over all of it, evenly" % spray_text().to_lower()}
		"gun":
			if item_id != 0:
				p = {"action": {"a": "paint", "item": item_id, "color": spray_color, "finish": Shed.FINISHES[spray_finish], "gun": true},
					"time": 1.5, "coverage": true, "verb": "spray %s: go along the parts in steady passes" % spray_text().to_lower()}
		"lance":
			if target.has("at"):
				var near := [] if item_id == 0 else [item_id]
				var view: Node = get_tree().get_first_node_in_group("workshop")
				if view:
					for id in view.items_near(target["at"], JET_REACH * Progress.spread_mult(me, "lance")):
						if not near.has(id) and Shed.items.has(id):
							near.append(id)
				if not near.is_empty() or item_id != 0:
					p = {"action": {"a": "wash", "items": near, "at": target["at"]}, "time": 0.2, "verb": "blast the muck off"}
	if p.is_empty():
		return {}
	p["blocked"] = "" if p["action"]["a"] in ["computer", "tuning", "write_label"] else Shed.check(me, p["action"])
	return p


## Putting the part in your hands down on a workbench, washer or repair machine, anywhere on
## top there's room: where the crosshair meets the top, or the nearest clear place to it,
## turned the way you face and however far you have turned it (square to the top with snapping
## on). The host checks it fits (Shed.surface_fits).
func _set_down_plan(key: String) -> Dictionary:
	var s := Shed.surface(key)
	var held := Shed.held_by(Shed.me())
	if s.is_empty() or held == 0:
		return {}
	var frame: Transform3D = s["xf"]
	var inv := frame.affine_inverse()
	var from := inv * camera.global_position
	var dir := inv.basis * -camera.global_transform.basis.z
	var top := float(s["top"])
	var aim := Vector2.ZERO
	if dir.y < -0.01:
		var hit := from + dir * ((top - from.y) / dir.y)
		aim = Vector2(hit.x, hit.z)
	elif target.has("at"):
		var local := inv * (target["at"] as Vector3)
		aim = Vector2(local.x, local.z)
	# Square to the top with snapping on, else just as you've turned it.
	var yaw := rotation.y + hold_turn - frame.basis.get_euler().y
	if Settings.snap_placement:
		yaw = Placement.snap_yaw(yaw)
	var ck := "%s:%d:%d:%d:%d:%d" % [key, held, roundi(aim.x * 40.0), roundi(aim.y * 40.0), roundi(yaw / (PI / 36.0)),
		Shed.surface_items(key).size()]
	if _room_cache.get("key", "") != ck:
		_room_cache = {"key": ck, "place": Shed.find_room(key, held, aim, yaw)}
	var place = _room_cache["place"]
	var verb := ("put it in the %s" if s["kind"] == "washer" else "put it on the %s") % Shed.surface_name(key).to_lower()
	if not (place is Transform3D):
		# Nowhere near: ask for where you're looking, and the host says why not.
		place = Transform3D(Basis(Vector3.UP, yaw), Vector3(aim.x, top, aim.y))
	return {"action": {"a": "set_down", "top": key, "xf": place}, "time": 0.25, "verb": verb}


## With a can or bottle in hand: pour it into the tank, engine or brakes (first button), drain
## them into it (second button), or tip what's in it away in the scrap bin.
func _fluid_plan(held: int, kind: String) -> Dictionary:
	var me := Shed.me()
	var can: Dictionary = Shed.items[held]
	var fluid := PartsDB.kind_of(can["part"])
	if fluid == "chain_lube":
		var chain := target_item() if kind in ["part", "spot", "item"] else 0
		if chain != 0 and Shed.items[chain]["kind"] == "chain":
			var lube := {"action": {"a": "lube", "item": chain, "crouched": crouched}, "time": 2.5, "coverage": true,
				"verb": "sweep the lube along the whole chain"}
			lube["blocked"] = Shed.check(me, lube["action"])
			return lube
		if kind != "bin":
			return {}
	var holder := 0
	match kind:
		"part":
			holder = Shed.fluid_holder(target, fluid)
		"spot":
			var on_spot := Shed.item_at_spot(str(target["spot"]))
			if Shed.is_engine(on_spot) and fluid == "oil":
				holder = on_spot
		"bin":
			# Old fluid goes in general waste; the recycling bins take the empty container.
			if float(can["fluid"]["litres"]) > 0.0 and str(target.get("bin", "general")) == "general":
				var tip := {"action": {"a": "tip"}, "time": 1.5, "verb": "tip it away"}
				tip["blocked"] = Shed.check(me, tip["action"])
				return tip
			return {}
	if holder == 0:
		return {}
	var what: String = PartsDB.KIND_NAMES[fluid].to_lower()
	var where := PartsDB.slot_name(PartsDB.slots_for_kind(PartsDB.kind_of(Shed.items[holder]["part"]))[0]).to_lower()
	if fluid == "brake_fluid":
		where = "brake reservoir"
	var pour := {"action": {"a": "pour", "item": holder}, "time": Shed.pour_time(can, Shed.items[holder]),
		"verb": "pour the %s into the %s" % [what, where]}
	pour["blocked"] = Shed.check(me, pour["action"])
	alt_plan = {"action": {"a": "drain", "item": holder, "crouched": crouched}, "time": Shed.pour_time(Shed.items[holder], can),
		"verb": "drain the %s into your %s" % [what, str(PartsDB.get_part(can["part"])["container"]).to_lower()]}
	alt_plan["blocked"] = Shed.check(me, alt_plan["action"])
	return pour


func _describe() -> String:
	var kind := str(target.get("kind", ""))
	var lines := []
	match kind:
		"part":
			var slot := str(target["slot"])
			var item_id := target_item()
			var engine_id := int(target.get("engine", 0))
			var owner := "the engine on the stand" if engine_id != 0 else str(Shed.bikes[target["bike"]]["name"])
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				lines.append(PartsDB.part_name(it["part"]))
				lines.append("%s on %s  ·  %s" % [PartsDB.slot_name(slot), owner, "bolted" if Shed.bolted_at_target(target) else "LOOSE"])
				lines.append(PartsDB.spec_line(it["part"]))
				lines.append(Shed.condition_text(it))
				lines.append(PartsDB.bin_text(str(it["part"])))
				if it.has("fluid"):
					lines.append(Shed.fluid_text(it))
				var whisper := _whisper(slot, engine_id)
				if whisper != "":
					lines.append(whisper)
			var held := Shed.held_by(Shed.me())
			if held != 0 and tool == "hands" and not PartsDB.is_fluid(Shed.items[held]["part"]):
				lines.append(_preview(held))
			if engine_id != 0:
				var missing := Shed.engine_missing(engine_id)
				lines.append("Engine complete." if missing.is_empty() else "Engine needs: %s" % ", ".join(missing.map(func(m): return PartsDB.slot_name(m).to_lower())))
			else:
				var bike_id := int(target["bike"])
				for note in Shed.build_of(bike_id).notes:
					lines.append("! " + note)
				lines.append("N: give it a name")
				var ride := Shed.check(Shed.me(), {"a": "mount", "bike": bike_id})
				lines.append("F: ride %s" % Shed.bikes[bike_id]["name"] if ride == "" else "Can't ride yet. " + ride)
				var wheel := Shed.check(Shed.me(), {"a": "grab_bike", "bike": bike_id})
				if wheel == "":
					lines.append("Hold F: wheel it about")
		"spot":
			var spot := str(target["spot"])
			var item_id := Shed.item_at_spot(spot)
			var f := Shed.furniture_of_spot(spot)
			var where: String = "Workbench" if f.is_empty() else Shed.furniture_name(f)
			var role := Shed.spot_role(spot)
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				lines.append(PartsDB.part_name(it["part"]))
				lines.append("%s  ·  %s" % [where, PartsDB.KIND_NAMES[it["kind"]]])
				lines.append(PartsDB.spec_line(it["part"]))
				lines.append(Shed.condition_text(it))
				lines.append(PartsDB.bin_text(str(it["part"])))
				if it.get("boxed", false):
					lines.append("F: unpack it")
				if it.has("fluid") and not PartsDB.is_fluid(it["part"]):
					lines.append(Shed.fluid_text(it))
				if Shed.is_engine(item_id) and Shed.is_stand_spot(spot) and not it.get("boxed", false):
					var missing := Shed.engine_missing(item_id)
					lines.append("Engine complete." if missing.is_empty() else "Engine needs: %s" % ", ".join(missing.map(func(m): return PartsDB.slot_name(m).to_lower())))
				var held := Shed.held_by(Shed.me())
				if held != 0 and tool == "hands" and Shed.is_engine(item_id) and not Shed.is_engine(held):
					lines.append(_preview(held, {"engine": item_id, "slot": ""}))
				if role == "washer" and float(it["dirt"]) > 0.0:
					lines.append("Washing... %d%% dirt left" % roundi(float(it["dirt"]) * 100.0))
				if role == "repair":
					var batch := Shed.repair_batch(spot)
					if batch.size() > 1:
						lines.append("Grinder: restores all %d parts on here at once" % batch.size())
				if role == "changer":
					lines.append_array(_changer_lines(item_id))
			else:
				lines.append(where)
				match role:
					"washer":
						lines.append("Leave dirty parts in here and they come out clean.")
					"repair":
						lines.append("Put parts here and use the grinder and welder to restore them all at once.")
					"changer":
						lines.append("Take a wheel off a bike (its tyre comes with it) and put it here to change the tyre.")
					_:
						if Shed.is_stand_spot(spot):
							lines.append("Bolt an engine on here to strip it or build it up.")
						elif not f.is_empty():
							lines.append("Store parts and boxed stock here.")
				if not f.is_empty():
					lines.append(Equipment.spec_line(str(f["model"])))
					if not Equipment.FIXED_KINDS.has(str(f["kind"])):
						lines.append("F: move it somewhere else")
		"item":
			var it: Dictionary = Shed.items[int(target["item"])]
			lines.append(PartsDB.part_name(it["part"]))
			lines.append("Put down here  ·  %s" % PartsDB.KIND_NAMES[it["kind"]])
			lines.append(PartsDB.spec_line(it["part"]))
			lines.append(Shed.condition_text(it))
			lines.append(PartsDB.bin_text(str(it["part"])))
			if it.get("boxed", false):
				lines.append("F: unpack it")
		"radio":
			lines.append("Shed radio (everyone hears it)")
			var view: Node = get_tree().get_first_node_in_group("workshop")
			if view and view.radio:
				lines.append(view.radio.now_playing())
			lines.append("F: switch %s" % ("off" if Shed.radio["on"] else "on"))
		"furniture", "label":
			var f: Dictionary = Shed.furniture[int(target["furniture"])]
			lines.append(Shed.furniture_name(f))
			lines.append(Equipment.spec_line(str(f["model"])))
			match str(f["kind"]):
				"seat":
					lines.append("F: sit down   Hold F: move it")
				"tv":
					lines.append_array(_channel_lines(_screen_key()))
					lines.append("F: take it down to hang somewhere else")
				"poster":
					lines.append("F: take it down to hang somewhere else")
				"booth", "changer":
					lines.append("Built into the shed")
				_:
					lines.append("F: move it somewhere else")
			if kind == "label":
				lines.append("Hold %s on the label to write on it" % ("RT" if Controls.active_device >= 0 else "left mouse"))
		"screen":
			var key := _screen_key()
			lines.append("Crew board screen" if key == "crew" else "Bay %d screen" % (int(key.trim_prefix("bay")) + 1))
			lines.append_array(_channel_lines(key))
		"door":
			lines.append("Roller door")
			lines.append("F: %s" % ("close it" if Shed.door_open else "open it"))
		"lights":
			var room := str(target.get("room", ""))
			lines.append({"paint": "Paint shop lights", "storage": "Storage room lights", "sales": "Sales office lights"}.get(room, "Shed lights"))
			lines.append("F: switch them %s" % ("off" if Shed.room_lit(room) else "on"))
		"board":
			var board: Node = get_tree().get_first_node_in_group("whiteboard")
			if board:
				lines.append_array(board.describe())
			if Shed.whiteboard_id() != 0:
				lines.append("F: take it down to hang it on another wall")
		"top":
			var key := str(target["top"])
			var s := Shed.surface(key)
			lines.append(Shed.surface_name(key))
			var on := Shed.surface_items(key)
			match str(s.get("kind", "")):
				"washer":
					lines.append("Put dirty parts in anywhere there's room and they come out clean.")
				"repair":
					lines.append("Put parts on it anywhere there's room, then use the grinder and welder to restore them all at once.")
				_:
					lines.append("Put parts down anywhere along it there's room.")
			if not on.is_empty():
				lines.append("%d part%s on it" % [on.size(), "" if on.size() == 1 else "s"])
			if int(s.get("rated", 0)) > 0 and on.size() > int(s["rated"]) and str(s.get("kind", "")) in ["washer", "repair"]:
				lines.append("More than %d on it, so it works a little slower on each." % int(s["rated"]))
			var fid := int(target.get("furniture", 0))
			if fid != 0 and Shed.furniture.has(fid):
				lines.append(Equipment.spec_line(str(Shed.furniture[fid]["model"])))
				lines.append("F: move it somewhere else")
		"pc":
			lines.append("Parts computer")
			lines.append("Order parts and equipment. Deliveries are left outside by the roller door.")
		"dyno_kit":
			lines.append_array(DynoRoom.describe(target, Shed.me()))
		"dyno":
			lines.append("Dyno desk")
			var on := Shed.dyno_bike()
			lines.append("F: tune %s and run the dyno" % (Shed.bikes[on]["name"] if on != 0 else "a bike"))
		"bin":
			var which := str(target.get("bin", "general"))
			lines.append(str(PartsDB.BIN_NAMES.get(which, "Bin")))
			match which:
				"plastic":
					lines.append("Plastic only: oil and brake fluid bottles, drain pans, plastic cases and top boxes.")
				"metal":
					lines.append("Metal only: frames, engines, wheels, discs, exhausts, chains, jerry cans and aerosols.")
				_:
					lines.append("Takes anything you don't want, and old fluid tipped out of a can.")
			var held := Shed.held_by(Shed.me())
			if held != 0:
				lines.append(PartsDB.bin_text(str(Shed.items[held]["part"])))
				var why := Shed.bin_check(held, which)
				if why != "":
					lines.append("Not in here: " + why)
				elif which == "general" and PartsDB.bin_for(str(Shed.items[held]["part"])) != "general":
					lines.append("It could be recycled instead, for more XP.")
	return "\n".join(lines)


## Engine Whisperer (a skill): how much power a worn or grimy engine part is costing, worked
## out by comparing the engine with that part as new.
func _whisper(slot: String, engine_id: int) -> String:
	if Progress.skill_rank(Shed.me(), "engine_whisperer") <= 0:
		return ""
	if not (slot == "engine" or slot == "exhaust" or PartsDB.is_engine_slot(slot)):
		return ""
	var build: BikeBuild = Shed.engine_build(engine_id) if engine_id != 0 else Shed.build_of(int(target["bike"]))
	var cond: Dictionary = build.condition.duplicate(true)
	if not cond.has(slot):
		return ""
	for k in ["rust", "dirt", "wear"]:
		cond[slot][k] = 0.0
	var lost := BikeBuild.new(build.parts, cond, build.tune).hp() - build.hp()
	if lost < 0.1:
		return "Engine Whisperer: it isn't costing any power."
	return "Engine Whisperer: its wear and grime are costing about %.1f hp." % lost


## What the tyre changer shows about the wheel on it: its tyre and how it went on, or whether
## the tyre in your hands fits.
func _changer_lines(wheel: int) -> Array:
	var out := []
	var tyre := Shed.tyre_on_wheel(wheel)
	var wheel_part := str(Shed.items[wheel]["part"])
	if tyre != 0:
		var it: Dictionary = Shed.items[tyre]
		out.append("Tyre on it: %s" % PartsDB.part_name(it["part"]))
		if it.has("bead"):
			out.append(Shed.bead_text(it))
		out.append("Hold %s: lift the wheel off, tyre and all" % ("LT" if Controls.active_device >= 0 else "right mouse"))
	else:
		out.append("No tyre on it. Tyres that fit: %d to %d mm wide, made for %s rims" % [PartsDB.tyre_range(wheel_part).x,
			PartsDB.tyre_range(wheel_part).y, PartsDB.inch_text(float(PartsDB.get_part(wheel_part).get("diameter", 17.0)))])
		var held := Shed.held_by(Shed.me())
		if held != 0 and Shed.items[held]["kind"] == "tyre":
			var why := PartsDB.tyre_fit_reason(str(Shed.items[held]["part"]), wheel_part)
			out.append(why if why != "" else "The %s fits this rim." % PartsDB.part_name(Shed.items[held]["part"]))
	return out


## The screen under the crosshair with channels to change (see TvChannels), or "".
func _screen_key() -> String:
	match str(target.get("kind", "")):
		"screen":
			return str(target["screen"])
		"furniture":
			if str(Shed.furniture.get(int(target["furniture"]), {}).get("kind", "")) == "tv":
				return "f%d" % int(target["furniture"])
	return ""


## "On CH 3: XP goals" and which keys change it, for the info panel.
func _channel_lines(key: String) -> Array:
	if key == "":
		return []
	var state := Shed.screen_channel(key)
	var label := TvChannels.osd_label(key, state, Shed.riders())
	var pad := Controls.active_device >= 0
	return ["Showing " + label,
		"%s: next channel   %s: previous" % ["X" if pad else "R / right mouse", "B" if pad else "T"]]


## Changes the channel on the screen you're looking at, through the host.
func _change_channel(key: String, dir: int) -> void:
	Shed.request({"a": "tv_channel", "screen": key, "step": dir})
	Sfx.play_at("beep", camera.global_position, -14.0)


## How fitting `item_id` at the target would change the numbers.
func _preview(item_id: int, at := {}) -> String:
	var action := _where() if at.is_empty() else at
	var where := Shed.install_slot(action, item_id)
	if where.has("error"):
		return where["error"]
	var slot: String = where["slot"]
	var before: Dictionary
	var after: Dictionary
	if action.has("engine"):
		before = Shed.engine_build(int(action["engine"])).summary()
		after = Shed.engine_build(int(action["engine"]), item_id, slot).summary()
	else:
		before = Shed.build_of(int(action["bike"])).summary()
		after = Shed.build_of(int(action["bike"]), item_id, slot).summary()
	var verb := "Fit as %s" % PartsDB.slot_name(slot).to_lower()
	return "%s: %d → %d hp   %d → %d %s   %d → %d %s   brakes %d → %d   %s → %s" % [verb, roundi(before["hp"]), roundi(after["hp"]),
		Units.speed_value(before["top_kmh"] / 3.6), Units.speed_value(after["top_kmh"] / 3.6), Units.speed_unit(),
		roundi(Units.mass_value(before["mass"])), roundi(Units.mass_value(after["mass"])), Units.mass_unit(),
		roundi(before["brake"]), roundi(after["brake"]), Units.economy(before["economy"]), Units.economy(after["economy"])]


func _highlight() -> void:
	var model: BikeModel = null
	var slot := ""
	if target.get("kind", "") == "part":
		var view: Node = get_tree().get_first_node_in_group("workshop")
		if view:
			model = view.model_for(target)
			slot = target["slot"]
	if _highlighted and is_instance_valid(_highlighted) and _highlighted != model:
		_highlighted.highlight("")
	_highlighted = model
	if model:
		model.highlight(slot)


# ---------------------------------------------------------------------------- working

func _acting() -> bool:
	return controls_enabled and (_main_button() or _alt_button())


func _main_button() -> bool:
	return Input.is_action_pressed("act") or Controls.trigger(true) > 0.5


## The second work button, for draining. Only counts when there's something to drain.
func _alt_button() -> bool:
	return not alt_plan.is_empty() and (Input.is_action_pressed("alt_act") or Controls.trigger(false) > 0.5)


func _update_work(delta: float) -> void:
	var use_alt := controls_enabled and _alt_button() and not _main_button()
	var plan_now: Dictionary = alt_plan if use_alt else plan
	if _tyre_game_step(delta, plan_now, use_alt):
		return
	# Spraying is a skill: sweep the can over the part until it's all covered, without
	# lingering in one place. The job carries on while the button's held, even off the part.
	if not use_alt and _acting() and not _need_release:
		if plan_now.get("coverage", false) and plan_now["blocked"] == "":
			_coverage_step(delta, plan_now)
			return
		if not _cover.is_empty() and _cover.get("live", false):
			_coverage_step(delta, _cover["plan"])
			return
	if not _cover.is_empty() and _cover.get("live", false):
		_cover["live"] = false
		Sfx.set_loop(_work_sound, "")
		_send_status("")
		progress = 0.0
	_active_plan = plan_now
	var key := ("alt:" if use_alt else "") + str(plan_now.get("action", {}))
	var a_now := str(plan_now.get("action", {}).get("a", ""))
	if a_now in ["drop", "wash", "set_down"]:
		key = a_now  # the spot moves with the crosshair; keep the hold going
	if not _acting():
		_need_release = false
	if plan_now.is_empty() or plan_now["blocked"] != "" or key != _plan_key or not _acting() or _need_release:
		Sfx.set_loop(_work_sound, "")
		if _hold > 0.0 and _last_status != "":
			_send_status("")
		_hold = 0.0
		progress = 0.0
		_plan_key = key
		if _acting() and not plan_now.is_empty() and plan_now["blocked"] != "" and not _need_release:
			Shed.feedback.emit(plan_now["blocked"], false)
			_need_release = true
		return
	if _hold == 0.0:
		_send_status(_activity_text(), _changer_of(plan_now))
		Sfx.set_loop(_work_sound, Sfx.WORK_LOOPS.get(a_now, ""))
	_hold += delta
	progress = clampf(_hold / float(plan_now["time"]), 0.0, 1.0)
	if progress >= 1.0:
		if a_now == "computer":
			computer_requested.emit()
		elif a_now == "tuning":
			tuning_requested.emit()
		elif a_now == "write_label":
			label_requested.emit(int(target.get("furniture", 0)))
		else:
			var held_before := Shed.held_by(Shed.me())
			Shed.request(plan_now["action"])
			Sfx.job_done(a_now, plan_now["action"], held_before, camera.global_position - camera.global_transform.basis.z * 1.2)
		if a_now == "wash":
			# The jet keeps going for as long as you hold the trigger.
			_hold = 0.0
			progress = 0.0
			return
		Sfx.set_loop(_work_sound, "")
		_hold = 0.0
		progress = 0.0
		_need_release = true
		_send_status("")


## The tyre changer piece of work under way, if any: the furniture id of the changer.
func _changer_of(p: Dictionary) -> int:
	var spot := str(p.get("action", {}).get("spot", ""))
	if spot == "" or Shed.spot_role(spot) != "changer":
		return 0
	return int(Shed.furniture_of_spot(spot)["id"])


## Runs the tyre-fitting game while the work button is held on the changer with a tyre in hand.
## Letting go, or looking away, before the marker has gone round lets the bead slip back off.
## Returns true while the game has the work button.
func _tyre_game_step(delta: float, plan_now: Dictionary, use_alt: bool) -> bool:
	var playing: bool = not use_alt and plan_now.get("game", "") == "tyre" and plan_now["blocked"] == "" and _acting() \
		and not _need_release
	var key := str(plan_now.get("action", {}))
	if tyre_game and (not playing or key != _game_key):
		tyre_game = null
		progress = 0.0
		_send_status("")
		Sfx.set_loop(_work_sound, "")
		Shed.feedback.emit("The bead slipped back off the rim. Hold on all the way round.", false)
		_need_release = _acting()
		return true
	if not playing:
		return false
	if tyre_game == null:
		tyre_game = TyreGame.new()
		_game_key = key
		_active_plan = plan_now
		_send_status("Fitting a tyre on the tyre changer", _changer_of(plan_now))
		Sfx.set_loop(_work_sound, Sfx.WORK_LOOPS.get("tyre_fit", ""))
	tyre_game.step(delta)
	progress = tyre_game.progress()
	if tyre_game.done():
		var a: Dictionary = plan_now["action"].duplicate()
		a["quality"] = tyre_game.quality()
		Shed.request(a)
		tyre_game = null
		progress = 0.0
		_need_release = true
		_hold = 0.0
		_send_status("")
		Sfx.set_loop(_work_sound, "")
		Sfx.play_at("bead_pop", camera.global_position - camera.global_transform.basis.z * 1.2, -4.0)
	return true


## One frame of spraying: whatever patches of the part are under the spray get another coat.
## With the spray gun in a paint booth, the fan coats every part hanging there that it passes.
func _coverage_step(delta: float, plan_now: Dictionary) -> void:
	var a: Dictionary = plan_now["action"]
	var item := int(a["item"])
	var gun := bool(a.get("gun", false))
	var key := _cover_key(a)
	if _cover.get("key", "") != key:
		_cover = _covers.get(key, {})
		if _cover.is_empty():
			_cover = _start_cover(item, key, plan_now)
			if _cover.is_empty():
				return
			_covers[key] = _cover
	if not _cover["live"]:
		_cover["live"] = true
		_active_plan = plan_now
		_send_status(_activity_text())
		Sfx.set_loop(_work_sound, "spray_gun" if gun else Sfx.WORK_LOOPS.get(str(a["a"]), "spray"))
	var jobs: Array = [_cover]
	if gun:
		# Every other part on the booth's hooks gets its own job, so one pass can coat them all.
		var it: Dictionary = Shed.items.get(item, {})
		if not it.is_empty() and it["at"] == "spot":
			var booth := Shed.furniture_of_spot(str(it["ref"]))
			if not booth.is_empty():
				for spot in Shed.furniture_spots(int(booth["id"])):
					var other := Shed.item_at_spot(spot)
					if other == 0 or other == item or Shed.items[other].get("boxed", false):
						continue
					var oa := a.duplicate()
					oa["item"] = other
					var ok := _cover_key(oa)
					if not _covers.has(ok):
						var op := plan_now.duplicate()
						op["action"] = oa
						var job := _start_cover(other, ok, op)
						if job.is_empty():
							continue
						_covers[ok] = job
					jobs.append(_covers[ok])
	if target.has("at"):
		var kit := _cover_tool(a)
		spray_skill = Progress.spread_mult(Shed.me(), kit)
		var reach := (GUN_RADIUS if gun else SPRAY_RADIUS) * spray_skill
		var rate := (GUN_RATE if gun else COVER_RATE) * Progress.cover_rate_mult(Shed.me(), kit)
		var falloff := 0.15 if gun else 0.5
		var hit_at: Vector3 = target["at"]
		var view_dir := -camera.global_transform.basis.z
		# The crosshair may only be on a part's rough grab box: find where the spray meets its surface.
		var sq := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + view_dir * 6.0,
			1 | 4 | BikeModel.SPRAY_LAYER)
		sq.exclude = [get_rid()]
		var surf := get_world_3d().direct_space_state.intersect_ray(sq)
		if not surf.is_empty():
			hit_at = surf["position"]
		for job in jobs:
			var xf: Transform3D = job["xf"]
			var splat_node: Node3D = job.get("splats", null)
			if is_instance_valid(splat_node):
				xf = splat_node.global_transform   # the part as it is now, swung or moved
				var swing := _swing_of(job)
				if swing and gun:
					swing.push(view_dir * delta * 0.35)
			var local: Vector3 = xf.affine_inverse() * hit_at
			# The spray is a cone along the line of sight: it lands in a round patch across that line,
			# so a face at a slant gets a longer splash.
			var along: Vector3 = (xf.basis.inverse() * view_dir).normalized()
			var points: PackedVector3Array = job["points"]
			var cells: PackedFloat32Array = job["cells"]
			var splats: PaintSplats = job.get("splats", null)
			for i in points.size():
				var v := points[i] - local
				var depth := v.dot(along)
				if absf(depth) > 0.25:
					continue
				var d := (v - along * depth).length()
				if d < reach:
					cells[i] += delta * rate * (1.0 - falloff * d / reach)
					if is_instance_valid(splats):
						splats.set_coats(i, cells[i] * (RUN_LEVEL / float(job.get("runs", RUN_LEVEL))))
			job["cells"] = cells
	for job in jobs:
		var stats := _job_stats(job)
		if job["key"] == _cover.get("key", ""):
			coverage = stats["covered"]
			progress = clampf(coverage / COVER_DONE, 0.0, 1.0)
		if stats["covered"] >= COVER_DONE:
			var done := (job["plan"]["action"] as Dictionary).duplicate()
			done["quality"] = clampf(stats["covered"] * (1.0 - stats["over"] * 0.6), 0.0, 1.0)
			done["waste"] = stats["over"]
			Shed.request(done)
			if is_instance_valid(job.get("splats", null)):
				job["splats"].finish_job()
			_covers.erase(job["key"])
			if job["key"] == _cover.get("key", ""):
				Sfx.set_loop(_work_sound, "")
				_send_status("")
				_cover = {}
				coverage = 0.0
				progress = 0.0
				_need_release = true


## Middle mouse: point something out to the crew.
func ping() -> void:
	var what := PingMarker.ping_from(camera, [get_rid()], PING_REACH)
	if what == "":
		Shed.feedback.emit("Nothing there to ping.", false)


## The hook swing a job's part hangs from, if any.
func _swing_of(job: Dictionary) -> Swing:
	var n: Node = job.get("node", null)
	if is_instance_valid(n) and n.get_parent() is Swing:
		return n.get_parent() as Swing
	return null


func _cover_key(a: Dictionary) -> String:
	return str(a.get("a", "")) + ":" + str(int(a["item"])) + ":" + str(a.get("color", "")) + str(a.get("finish", "")) \
		+ (":gun" if a.get("gun", false) else "")


## A fresh spray job on `item`: the bits of it you can see from where you stand, found by
## looking over it ray by ray, each needing a coat. The undersides you can't reach don't count.
func _start_cover(item: int, key: String, plan_now: Dictionary) -> Dictionary:
	var view: Node = get_tree().get_first_node_in_group("workshop")
	var frame: Dictionary = view.item_frame(item) if view else {}
	if frame.is_empty():
		return {}
	var box: AABB = frame["box"]
	var xf: Transform3D = frame["xf"]
	var eye := camera.global_position
	var space := get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	const N := 9
	# First against the part's own shapes; a part with only a rough box round it falls back to that.
	for mask in [1 | 4 | BikeModel.SPRAY_LAYER, 1 | 4 | Workshop.INTERACT_LAYER]:
		var seen := {}
		for i in N:
			for j in N:
				for k in N:
					var at := xf * (box.position + box.size * Vector3((i + 0.5) / N, (j + 0.5) / N, (k + 0.5) / N))
					var q := PhysicsRayQueryParameters3D.create(eye, eye + (at - eye) * 1.5, mask)
					q.exclude = [get_rid()]
					var hit := space.intersect_ray(q)
					if hit.is_empty() or _item_hit(hit["collider"]) != item:
						continue
					var local: Vector3 = xf.affine_inverse() * (hit["position"] as Vector3)
					var cell := Vector3i((local / (COVER_CELL * 0.7)).floor())
					if not seen.has(cell):
						seen[cell] = true
						points.append(local)
						normals.append((xf.basis.inverse() * (hit["normal"] as Vector3)).normalized())
		if not points.is_empty():
			break
	if points.is_empty():
		return {}
	var cells := PackedFloat32Array()
	cells.resize(points.size())
	var a: Dictionary = plan_now["action"]
	var splats := PaintSplats.new()
	var paint: Color = Shed.PAINTS[clampi(int(a.get("color", 0)), 0, Shed.PAINTS.size() - 1)] if a["a"] == "paint" \
		else Color(0.22, 0.17, 0.1, 0.8)
	splats.setup(xf, points, normals, COVER_CELL, paint, str(a.get("finish", "gloss")))
	# The wet paint rides on the part, so it stays put if the part swings or the bike moves.
	var holder: Node3D = frame.get("node", null)
	if is_instance_valid(holder):
		holder.add_child(splats)
		splats.transform = holder.global_transform.affine_inverse() * xf
	else:
		get_parent().add_child(splats)
	# Upgraded tools lay paint faster, so a patch takes more coats before it runs; Steady Hand more still.
	var runs := (GUN_RUN_LEVEL if a.get("gun", false) else RUN_LEVEL) * Progress.run_level_mult(Shed.me(), _cover_tool(a))
	return {"key": key, "plan": plan_now, "item": item, "points": points, "cells": cells, "live": false, "xf": xf,
		"splats": splats, "node": holder, "runs": runs}


## The tool doing a spray job: the gun, the spray can, or a can of chain lube in your hands.
func _cover_tool(a: Dictionary) -> String:
	if a.get("gun", false):
		return "gun"
	return "spray" if str(a.get("a", "")) == "paint" else "hands"


## Shortens a job's hold time for the tool's upgrade stage and the skills that speed it up.
func _scale_time(p: Dictionary) -> void:
	if p.is_empty() or p.get("coverage", false) or not p.has("time"):
		return
	var a := str(p["action"].get("a", ""))
	if a in ["computer", "tuning", "write_label", "wash", "radio"]:
		return
	p["time"] = float(p["time"]) * Progress.time_mult(Shed.me(), tool, p["action"])


## The part a ray hit, the same way the crosshair reads it.
func _item_hit(c: Object) -> int:
	if c == null:
		return 0
	if c.has_meta("bike") and Shed.bikes.has(int(c.get_meta("bike"))):
		return Shed.item_at_target({"bike": int(c.get_meta("bike")), "slot": str(c.get_meta("slot"))})
	if c.has_meta("engine"):
		return Shed.item_at_target({"engine": int(c.get_meta("engine")), "slot": str(c.get_meta("slot"))})
	if c.has_meta("spot"):
		return Shed.item_at_spot(str(c.get_meta("spot")))
	if c.has_meta("item"):
		return int(c.get_meta("item"))
	return 0


## How the spray job is going: {covered, over} as fractions of the part's patches.
func cover_stats() -> Dictionary:
	return _job_stats(_cover)


func _job_stats(job: Dictionary) -> Dictionary:
	if job.is_empty():
		return {"covered": 0.0, "over": 0.0}
	var cells: PackedFloat32Array = job["cells"]
	var runs := float(job.get("runs", GUN_RUN_LEVEL if job["plan"]["action"].get("gun", false) else RUN_LEVEL))
	var covered := 0
	var over := 0
	for c in cells:
		if c >= 0.8:   # wet paint flows out to fill a thin patch
			covered += 1
		if c >= runs:
			over += 1
	return {"covered": float(covered) / cells.size(), "over": float(over) / cells.size()}


func _activity_text() -> String:
	var a: Dictionary = _active_plan["action"]
	var what := ""
	if target.get("kind", "") == "part":
		var owner := "the engine" if int(target.get("engine", 0)) != 0 else str(Shed.bikes[target["bike"]]["name"])
		what = "the %s on %s" % [PartsDB.slot_name(target["slot"]).to_lower(), owner]
	var verbs := {"unbolt": "Unbolting", "bolt": "Bolting up", "remove": "Removing", "install": "Fitting a part to",
		"clean": "Cleaning", "clean_many": "Scrubbing", "repair": "Restoring", "paint": "Spraying", "take": "Picking up a part",
		"place": "Putting down a part", "set_down": "Putting down a part", "start_build": "Starting a bike from scratch", "drop": "Putting down a part", "radio": "Fiddling with the radio", "bin": "Scrapping a part", "computer": "Browsing the parts computer", "tuning": "Tuning at the dyno desk",
		"pour": "Topping up", "drain": "Draining", "tip": "Tipping away old fluid", "wash": "Pressure washing", "set_stand": "Putting a bike on its stand",
		"repair_many": "Restoring parts on", "adjust_chain": "Adjusting the chain on", "lube": "Lubing the chain on",
		"tyre_fit": "Fitting a tyre on the tyre changer", "tyre_remove": "Levering a tyre off on the tyre changer"}
	var verb: String = verbs.get(a["a"], "Working on")
	if a["a"] == "clean_many" and what == "":
		what = "%d parts" % a["items"].size()
	if a["a"] in ["clean", "repair", "paint"] and what == "":
		what = "the " + Shed.item_title(int(a["item"]))
	if a["a"] == "install":
		what = "the engine" if int(a.get("engine", 0)) != 0 else str(Shed.bikes[int(a.get("bike", 0))]["name"])
	if a["a"] in ["pour", "drain"] and what == "":
		what = "the " + Shed.item_title(int(a["item"]))
	if a["a"] == "wash" and what == "":
		what = "%d parts" % a["items"].size()
	return ("%s %s" % [verb, what]).strip_edges()


func _send_status(activity: String, changer := 0) -> void:
	var sig := "%s|%s|%d" % [tool, activity, changer if activity != "" else 0]
	if sig == _last_status:
		return
	_last_status = sig
	Shed.request({"a": "status", "tool": tool, "activity": activity, "changer": changer if activity != "" else 0})


# ---------------------------------------------------------------------------- what's in your hands

func _update_held_view() -> void:
	var held := Shed.held_by(Shed.me())
	var sig := ""
	if held != 0:
		var it: Dictionary = Shed.items[held]
		sig = "%d:%s:%.1f:%.1f:%.1f:%s:%s:%s" % [held, it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", ""),
			"%.2f" % float(it["fluid"]["litres"]) if it.has("fluid") else ""]
		if tool != "hands":
			tool = "hands"
			_set_tool_view()
	if is_instance_valid(_held_view):
		_held_view.rotation.y = 0.5 + hold_turn   # turned in your hands as you turn it
	if sig == _held_sig:
		return
	_held_sig = sig
	if _held_view:
		_held_view.queue_free()
		_held_view = null
	if _tool_view:
		_tool_view.visible = held == 0
	if held == 0:
		return
	_held_view = BikeModel.item_display(held)
	var size: Vector3 = _held_view.get_meta("size", Vector3.ONE)
	var s := clampf(0.55 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
	_held_view.scale = Vector3.ONE * s
	_held_view.position = Vector3(0.0, -0.42, -0.75)
	_held_view.rotation = Vector3(0.0, 0.5 + hold_turn, 0.0)
	camera.add_child(_held_view)


func _set_tool_view() -> void:
	if _tool_view:
		_tool_view.queue_free()
	_jet = null
	var stage := Progress.tool_stage(Shed.me(), tool)
	_tool_sig = "%s:%d" % [tool, stage]
	_tool_view = make_tool_mesh(tool, Shed.PAINTS[spray_color], stage)
	_tool_view.position = Vector3(0.28, -0.28, -0.5)
	_tool_view.rotation = Vector3(0.25, -0.3, 0.0)
	if tool == "lance":
		_tool_view.position = Vector3(0.22, -0.26, -0.3)
		_tool_view.rotation = Vector3(0.05, -0.12, 0.0)
		_jet = make_jet()
		_jet.spread *= Progress.spread_mult(Shed.me(), "lance")
		_jet.position = Vector3(0.0, 0.0, -0.6)
		_tool_view.add_child(_jet)
	elif tool == "watch":
		# Held up to read, face towards you.
		_tool_view.position = Vector3(0.2, -0.2, -0.42)
		_tool_view.rotation = Vector3(0.35, -0.25, 0.0)
	camera.add_child(_tool_view)


## A fan of water from the pressure washer's nozzle. Shared with other players' avatars.
static func make_jet() -> CPUParticles3D:
	return WaterSpray.make()


## The fine cloud of paint (or lube) coming off the nozzle while you spray.
static func make_mist() -> CPUParticles3D:
	# The atomised spray itself: a fast cone of fine droplets that slows in the air, with a
	# soft overspray haze (a child emitter) that drifts and hangs after it.
	var mist := _spray_particles(420, 0.42, 0.004, 0.011, 0.9)
	mist.spread = 9.0
	mist.initial_velocity_min = 5.5
	mist.initial_velocity_max = 8.5
	mist.damping_min = 9.0
	mist.damping_max = 14.0
	mist.gravity = Vector3(0.0, -0.6, 0.0)
	var haze := _spray_particles(60, 1.6, 0.05, 0.11, 0.13)
	haze.name = "Haze"
	haze.spread = 16.0
	haze.initial_velocity_min = 1.0
	haze.initial_velocity_max = 2.2
	haze.damping_min = 1.5
	haze.damping_max = 2.5
	haze.gravity = Vector3(0.0, 0.05, 0.0)
	var grow := Curve.new()
	grow.max_value = 5.0
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 5.0))
	haze.scale_amount_curve = grow
	mist.add_child(haze)
	return mist


static func _spray_particles(count: int, life: float, size_min: float, size_max: float, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0.0, 0.0, -1.0)
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, alpha))
	fade.add_point(0.15, Color(1, 1, 1, alpha))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.5, Color(1, 1, 1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	m.albedo_texture = tex
	quad.material = m
	p.mesh = quad
	return p


func _update_mist() -> void:
	var on := not _cover.is_empty() and bool(_cover.get("live", false)) and _acting()
	if _mist == null:
		if not on:
			return
		_mist = make_mist()
		camera.add_child(_mist)
	var haze: CPUParticles3D = _mist.get_node("Haze")
	if on:
		var a: Dictionary = _cover["plan"]["action"]
		var c: Color = Shed.PAINTS[clampi(int(a.get("color", 0)), 0, Shed.PAINTS.size() - 1)] if a["a"] == "paint" else Color(0.45, 0.35, 0.2)
		_mist.color = c
		haze.color = c.lightened(0.15)
		var gun := bool(a.get("gun", false))
		_mist.spread = (6.5 if gun else 9.0) * spray_skill
		haze.spread = 12.0 if gun else 16.0
		# From the nozzle of the tool in your hand, towards where you're aiming.
		var nozzle := camera.global_transform * Vector3(0.2, -0.2, -0.55)
		if is_instance_valid(_tool_view) and _tool_view.has_meta("nozzle"):
			nozzle = _tool_view.global_transform * (_tool_view.get_meta("nozzle") as Vector3)
		var aim: Vector3 = target.get("at", camera.global_position - camera.global_transform.basis.z * 1.0)
		_mist.global_position = nozzle
		var dir := (aim - nozzle).normalized()
		_mist.direction = camera.global_transform.basis.inverse() * dir
		haze.direction = _mist.direction
	_mist.emitting = on
	haze.emitting = on


func _update_jet() -> void:
	if _jet == null:
		return
	var a := str(_active_plan.get("action", {}).get("a", ""))
	_jet.emitting = tool == "lance" and _acting() and a == "wash" and str(_active_plan.get("blocked", "")) in ["", "It's already clean."]


## A simple mesh of a tool, held in the hand, at its upgrade stage (0..5, see ToolModels).
## Shared with other players' avatars.
static func make_tool_mesh(which: String, can_color := Color(0.9, 0.75, 0.1), stage := 0) -> Node3D:
	return ToolModels.make("stopwatch" if which == "watch" else which, can_color, stage)


# ---------------------------------------------------------------------------- the sandblaster

## Mouse and buttons at the sandblaster: hold the alt button and move the mouse to turn the
## engine, F to step back. Returns true when the event was used.
func _blast_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (Input.is_action_pressed("alt_act") or Controls.trigger(false) > 0.5):
		blast.turn(Vector2(event.relative.x, event.relative.y) * BlastGame.TURN_MOUSE)
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		finish_blast()
		return true
	return false


## Starts the game once the host has put our hands in the gloves, runs it, and ends it if the
## engine or the cabinet goes.
func _blast_frame(delta: float, input: Vector2) -> void:
	var at := Shed.blasting(Shed.me())
	if blast == null:
		if at == 0:
			return
		var spot := ""
		for s in Shed.furniture_spots(at):
			spot = s
		var view: Node = get_tree().get_first_node_in_group("workshop")
		var model: BikeModel = view.model_for({"engine": Shed.item_at_spot(spot)}) if view and spot != "" else null
		var game := BlastGame.new()
		if model == null or not game.start(at, spot, model):
			Shed.request({"a": "blast_use", "on": false})
			return
		blast = game
		_blast_tick = BlastGame.TICK
		crouched = false
		_send_status("Sandblasting an engine")
		return
	if at != blast.furniture or Shed.item_at_spot(blast.spot) != blast.engine or not is_instance_valid(blast.model):
		_end_blast()
		return
	if controls_enabled:
		blast.turn(Vector2(input.x, -input.y) * BlastGame.TURN_RATE * delta)
	var firing := controls_enabled and _main_button()
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.0, BikeModel.SPRAY_LAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	blast.step(delta, firing, from, dir, hit)
	var j := blast.jet
	var view: Node = get_tree().get_first_node_in_group("workshop")
	var cab: EquipmentView = view.furniture_nodes.get(blast.furniture, null) if view else null
	if cab:
		var aim: Vector3 = j.get("at", from + dir * 0.9)
		cab.set_blast(blast.rot, firing, aim, j.get("normal", Vector3.UP), float(j.get("rust", 0.0)), int(j.get("fresh", 0)))
	for id in blast.newly_done():
		# Ding, a flash on the part and "Bare metal!" on the screen.
		Sfx.play_at("ting", camera.global_position + dir, -1.0)
		blast_cues.append({"kind": "part", "name": str(blast.parts[id]["name"])})
	if blast.engine_just_done():
		Sfx.play_ui("levelup", -4.0)
		blast_cues.append({"kind": "engine", "name": "Engine"})
		_blast_done_for = 0.0
	_blast_send -= delta
	if _blast_send <= 0.0:
		_blast_send = 0.12
		Shed.request({"a": "blast_aim", "rot": blast.rot, "fire": firing, "at": j.get("at", Vector3.ZERO)})
	# The rust, muck and wear numbers change as you go: the host is told a few times a second.
	_blast_tick -= delta
	if _blast_tick <= 0.0:
		_blast_tick = BlastGame.TICK
		var news := blast.changed_results()
		if not news.is_empty():
			Shed.request({"a": "blast_tick", "spot": blast.spot, "parts": news})
	if blast.all_done() and not firing:
		# Done: a moment to take it in, then step back.
		_blast_done_for += delta
		if _blast_done_for > 2.5:
			finish_blast()
	else:
		_blast_done_for = 0.0


## Steps back from the sandblaster: the host strips each part by how much of it is bare.
func finish_blast() -> void:
	if blast == null:
		Shed.request({"a": "blast_use", "on": false})
		return
	if blast.total() > 0.0:
		Shed.request({"a": "blast", "spot": blast.spot, "parts": blast.results()})
	else:
		Shed.request({"a": "blast_use", "on": false})
	_end_blast()


func _end_blast() -> void:
	if blast:
		blast.clear()
	blast = null
	blast_cues.clear()
	_blast_done_for = 0.0
	if Shed.blasting(Shed.me()) != 0:
		Shed.request({"a": "blast_use", "on": false})
	_send_status("")


## The side panel at the sandblaster (the HUD shows the full readout: see BlastHud).
func _blast_info() -> String:
	var lines := ["Sandblasting: %d%% bare metal" % roundi(blast.total() * 100.0)]
	for l in blast.lines():
		var mark := "  ·  pitted!" if float(l["over"]) > 0.05 else ("  ·  done" if float(l["covered"]) >= BlastGame.DONE else "")
		lines.append("%s  %d%%%s" % [l["name"], roundi(float(l["covered"]) * 100.0), mark])
	lines.append(blast_controls())
	return "\n".join(lines)


func blast_controls() -> String:
	var pad := Controls.device() >= 0 and Controls.active_device >= 0
	return "Hold RT to blast · left stick turns the engine · Y steps back" if pad else \
		"Hold left mouse to blast · W A S D (or hold right mouse) turns the engine · F steps back"
