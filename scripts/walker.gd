class_name Walker
extends CharacterBody3D
## The player on foot in first person. Looks at bikes and parts, picks a tool, and holds the
## action button to work: unbolt, remove, fit, bolt up, clean and restore. Every change goes
## through the Shed state so everyone in the session sees the same bikes.

signal mount_requested(bike_id: int)

const TOOLS: Array[String] = ["hands", "wrench", "brush", "repair"]
const TOOL_NAMES := {"hands": "Hands", "wrench": "Wrench", "brush": "Brush", "repair": "Grinder and welder"}
const EYE := 1.62
const WALK := 3.2
const RUN := 5.5
const REACH := 2.6
const MOUSE_SENS := 0.0025
const PAD_LOOK := 2.6

var camera: Camera3D
var tool := "hands"
var controls_enabled := true
var target := {}            # what the crosshair is on: {kind, bike, slot, spot, part, item}
var plan := {}              # what the action button would do: {action, time, verb, blocked}
var info := ""              # description of the target for the HUD
var progress := 0.0         # 0..1 of the current hold-to-work action

var _pitch := 0.0
var _hold := 0.0
var _plan_key := ""
var _need_release := false
var _held_view: Node3D
var _held_sig := ""
var _tool_view: Node3D
var _last_status := ""
var _highlighted: BikeModel


func _ready() -> void:
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	add_child(cs)
	camera = Camera3D.new()
	camera.position.y = EYE
	camera.near = 0.03
	camera.far = 2500.0
	camera.fov = 75.0
	add_child(camera)
	_set_tool_view()


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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(-event.relative.x * MOUSE_SENS, -event.relative.y * MOUSE_SENS)
	elif event.is_action_pressed("tool_next"):
		_cycle_tool(1)
	elif event.is_action_pressed("tool_prev"):
		_cycle_tool(-1)
	elif event.is_action_pressed("interact"):
		if target.get("kind", "") == "part":
			mount_requested.emit(int(target["bike"]))
	else:
		for i in TOOLS.size():
			if event.is_action_pressed("tool_%d" % (i + 1)):
				set_tool(TOOLS[i])


func _look(dyaw: float, dpitch: float) -> void:
	rotation.y += dyaw
	_pitch = clampf(_pitch + dpitch, -1.45, 1.45)
	camera.rotation.x = _pitch


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
		if look != Vector2.ZERO:
			_look(-look.x * PAD_LOOK * delta, -look.y * PAD_LOOK * 0.7 * delta)
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)) * (RUN if running else WALK)
	velocity.x = move_toward(velocity.x, wish.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 30.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if global_position.y < -20.0:
		place(Workshop.walker_spawn(0))
	_update_target()
	_update_work(delta)
	_update_held_view()


# ---------------------------------------------------------------------------- targeting

func _update_target() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | Workshop.INTERACT_LAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var t := {}
	if hit:
		var c: Object = hit["collider"]
		if c.has_meta("bike") and Shed.bikes.has(int(c.get_meta("bike"))):
			t = {"kind": "part", "bike": int(c.get_meta("bike")), "slot": str(c.get_meta("slot"))}
		elif c.has_meta("spot"):
			t = {"kind": "spot", "spot": str(c.get_meta("spot"))}
		elif c.has_meta("shelf"):
			t = {"kind": "shelf", "part": str(c.get_meta("shelf"))}
		elif c.has_meta("bin"):
			t = {"kind": "bin"}
	target = t
	plan = _make_plan()
	info = _describe()
	_highlight()


func _make_plan() -> Dictionary:
	var me := Shed.me()
	var held := Shed.held_by(me)
	var kind := str(target.get("kind", ""))
	if kind == "":
		return {}
	var bike_id := int(target.get("bike", 0))
	var slot := str(target.get("slot", ""))
	var spot_item := Shed.item_at_spot(str(target.get("spot", ""))) if kind == "spot" else 0
	var p := {}
	match tool:
		"hands":
			if held != 0:
				var held_name := Shed.item_title(held)
				match kind:
					"part":
						p = {"action": {"a": "install", "bike": bike_id}, "time": 1.2, "verb": "fit the " + held_name}
					"spot":
						p = {"action": {"a": "place", "spot": target["spot"]}, "time": 0.25, "verb": "put it down"}
					"bin", "shelf":
						p = {"action": {"a": "bin"}, "time": 0.4, "verb": "scrap the " + held_name}
			else:
				match kind:
					"part":
						p = {"action": {"a": "remove", "bike": bike_id, "slot": slot}, "time": 1.0, "verb": "take it off"}
					"spot":
						if spot_item != 0:
							p = {"action": {"a": "take", "spot": target["spot"]}, "time": 0.25, "verb": "pick it up"}
					"shelf":
						p = {"action": {"a": "shelf_take", "part": target["part"]}, "time": 0.5, "verb": "take a new one"}
		"wrench":
			if kind == "part":
				var bolted := Shed.is_bolted(bike_id, slot)
				p = {"action": {"a": "unbolt" if bolted else "bolt", "bike": bike_id, "slot": slot}, "time": 1.6,
					"verb": "unbolt it" if bolted else "bolt it up"}
		"brush":
			var item_id := Shed.item_on(bike_id, slot) if kind == "part" else spot_item
			if item_id != 0:
				p = {"action": {"a": "clean", "item": item_id}, "time": 1.0 + 3.0 * float(Shed.items[item_id]["dirt"]), "verb": "scrub it clean"}
		"repair":
			var item_id := Shed.item_on(bike_id, slot) if kind == "part" else spot_item
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				p = {"action": {"a": "repair", "item": item_id}, "time": 2.0 + 4.0 * (float(it["rust"]) + float(it["wear"])),
					"verb": "grind off the rust and rebuild it"}
	if p.is_empty():
		return {}
	p["blocked"] = Shed.check(me, p["action"])
	return p


func _describe() -> String:
	var kind := str(target.get("kind", ""))
	var lines := []
	match kind:
		"part":
			var bike_id := int(target["bike"])
			var slot := str(target["slot"])
			var item_id := Shed.item_on(bike_id, slot)
			var bike: Dictionary = Shed.bikes[bike_id]
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				lines.append(PartsDB.part_name(it["part"]))
				lines.append("%s on %s  ·  %s" % [PartsDB.SLOT_NAMES[slot], bike["name"], "bolted" if Shed.is_bolted(bike_id, slot) else "LOOSE"])
				lines.append(Shed.condition_text(it))
			var held := Shed.held_by(Shed.me())
			if held != 0 and tool == "hands":
				lines.append(_preview(bike_id, held))
			var ride := Shed.check(Shed.me(), {"a": "mount", "bike": bike_id})
			lines.append("F: ride %s" % bike["name"] if ride == "" else "Can't ride yet. " + ride)
		"spot":
			var item_id := Shed.item_at_spot(str(target["spot"]))
			var where: String = {"washer": "Parts washer", "repair": "Repair bench"}.get(target["spot"], "Workbench")
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				lines.append(PartsDB.part_name(it["part"]))
				lines.append("%s  ·  %s" % [where, PartsDB.SLOT_NAMES[it["slot"]]])
				lines.append(Shed.condition_text(it))
				if target["spot"] == "washer" and float(it["dirt"]) > 0.0:
					lines.append("Washing... %d%% dirt left" % roundi(float(it["dirt"]) * 100.0))
			else:
				lines.append(where)
				if target["spot"] == "washer":
					lines.append("Leave a dirty part in here and it comes out clean.")
				elif target["spot"] == "repair":
					lines.append("Put a part here and use the grinder and welder to restore it.")
		"shelf":
			var part := PartsDB.get_part(str(target["part"]))
			lines.append("New: " + str(part["name"]))
			lines.append(str(part.get("description", "")))
			lines.append("%s  ·  %.1f kg" % [PartsDB.SLOT_NAMES[part["slot"]], float(part.get("mass", 0.0))])
		"bin":
			lines.append("Scrap bin")
			lines.append("Drop parts you don't want in here.")
	return "\n".join(lines)


## How fitting `item_id` would change the bike's numbers.
func _preview(bike_id: int, item_id: int) -> String:
	var slot: String = Shed.items[item_id]["slot"]
	var before := Shed.build_of(bike_id).summary()
	var after := Shed.build_of(bike_id, item_id).summary()
	var verb := "Swap in" if Shed.item_on(bike_id, slot) != 0 else "Fit"
	return "%s: %d → %d hp   %d → %d km/h   %d → %d kg" % [verb, roundi(before["hp"]), roundi(after["hp"]),
		roundi(before["top_kmh"]), roundi(after["top_kmh"]), roundi(before["mass"]), roundi(after["mass"])]


func _highlight() -> void:
	var model: BikeModel = null
	var slot := ""
	if target.get("kind", "") == "part":
		var view: Node = get_tree().get_first_node_in_group("workshop")
		if view and view.bike_views.has(target["bike"]):
			model = view.bike_views[target["bike"]].get_child(0) as BikeModel
			slot = target["slot"]
	if _highlighted and is_instance_valid(_highlighted) and _highlighted != model:
		_highlighted.highlight("")
	_highlighted = model
	if model:
		model.highlight(slot)


# ---------------------------------------------------------------------------- working

func _acting() -> bool:
	return controls_enabled and (Input.is_action_pressed("act") or Controls.trigger(true) > 0.5)


func _update_work(delta: float) -> void:
	var key := str(plan.get("action", {}))
	if not _acting():
		_need_release = false
	if plan.is_empty() or plan["blocked"] != "" or key != _plan_key or not _acting() or _need_release:
		if _hold > 0.0 and _last_status != "":
			_send_status("")
		_hold = 0.0
		progress = 0.0
		_plan_key = key
		if _acting() and not plan.is_empty() and plan["blocked"] != "" and not _need_release:
			Shed.feedback.emit(plan["blocked"], false)
			_need_release = true
		return
	if _hold == 0.0:
		_send_status(_activity_text())
	_hold += delta
	progress = clampf(_hold / float(plan["time"]), 0.0, 1.0)
	if progress >= 1.0:
		Shed.request(plan["action"])
		_hold = 0.0
		progress = 0.0
		_need_release = true
		_send_status("")


func _activity_text() -> String:
	var a: Dictionary = plan["action"]
	var what := ""
	if target.get("kind", "") == "part":
		what = "the %s on %s" % [PartsDB.SLOT_NAMES[target["slot"]].to_lower(), Shed.bikes[target["bike"]]["name"]]
	var verbs := {"unbolt": "Unbolting", "bolt": "Bolting up", "remove": "Removing", "install": "Fitting a part to",
		"clean": "Cleaning", "repair": "Restoring", "shelf_take": "Fetching a new part", "take": "Picking up a part",
		"place": "Putting down a part", "bin": "Scrapping a part"}
	var verb: String = verbs.get(a["a"], "Working on")
	if a["a"] in ["clean", "repair"] and what == "":
		what = "the " + Shed.item_title(int(a["item"]))
	if a["a"] == "install":
		what = Shed.bikes[target["bike"]]["name"]
	return ("%s %s" % [verb, what]).strip_edges()


func _send_status(activity: String) -> void:
	var sig := tool + "|" + activity
	if sig == _last_status:
		return
	_last_status = sig
	Shed.request({"a": "status", "tool": tool, "activity": activity})


# ---------------------------------------------------------------------------- what's in your hands

func _update_held_view() -> void:
	var held := Shed.held_by(Shed.me())
	var sig := ""
	if held != 0:
		var it: Dictionary = Shed.items[held]
		sig = "%d:%s:%.1f:%.1f:%.1f" % [held, it["part"], it["rust"], it["dirt"], it["wear"]]
		if tool != "hands":
			tool = "hands"
			_set_tool_view()
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
	var it: Dictionary = Shed.items[held]
	_held_view = BikeModel.part_display(it["part"], Shed.condition_of(it))
	var size: Vector3 = _held_view.get_meta("size", Vector3.ONE)
	var s := clampf(0.55 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
	_held_view.scale = Vector3.ONE * s
	_held_view.position = Vector3(0.0, -0.42, -0.75)
	_held_view.rotation = Vector3(0.0, 0.5, 0.0)
	camera.add_child(_held_view)


func _set_tool_view() -> void:
	if _tool_view:
		_tool_view.queue_free()
	_tool_view = make_tool_mesh(tool)
	_tool_view.position = Vector3(0.28, -0.28, -0.5)
	_tool_view.rotation = Vector3(0.25, -0.3, 0.0)
	camera.add_child(_tool_view)


## A simple mesh of a tool, held in the hand. Shared with other players' avatars.
static func make_tool_mesh(which: String) -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.81, 0.83)
	steel.metallic = 1.0
	steel.roughness = 0.25
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.75, 0.12, 0.08)
	grip.roughness = 0.6
	var parts := []
	match which:
		"wrench":
			parts = [[Vector3(0, 0, 0), Vector3(0.025, 0.22, 0.012), steel], [Vector3(0, 0.12, 0), Vector3(0.06, 0.04, 0.014), steel],
				[Vector3(0, -0.06, 0), Vector3(0.03, 0.1, 0.02), grip]]
		"brush":
			var bristle := StandardMaterial3D.new()
			bristle.albedo_color = Color(0.85, 0.7, 0.35)
			parts = [[Vector3(0, -0.05, 0), Vector3(0.03, 0.18, 0.03), grip], [Vector3(0, 0.07, 0), Vector3(0.07, 0.06, 0.04), steel],
				[Vector3(0, 0.12, 0), Vector3(0.065, 0.05, 0.035), bristle]]
		"repair":
			var body := StandardMaterial3D.new()
			body.albedo_color = Color(0.1, 0.3, 0.75)
			body.roughness = 0.4
			parts = [[Vector3(0, -0.04, 0), Vector3(0.05, 0.2, 0.05), body], [Vector3(0, 0.08, 0.03), Vector3(0.06, 0.05, 0.06), body],
				[Vector3(0, 0.08, 0.07), Vector3(0.11, 0.11, 0.008), steel]]
		_:
			pass  # bare hands: nothing to draw
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[1]
		mi.mesh = box
		mi.material_override = p[2]
		mi.position = p[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root
