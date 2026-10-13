class_name Walker
extends CharacterBody3D
## The player on foot in first person. Looks at bikes and parts, picks a tool, and holds the
## action button to work: unbolt, remove, fit, bolt up, clean and restore. Every change goes
## through the Shed state so everyone in the session sees the same bikes.

signal mount_requested(bike_id: int)
signal computer_requested

const TOOLS: Array[String] = ["hands", "wrench", "brush", "repair", "spray"]
const TOOL_NAMES := {"hands": "Hands", "wrench": "Wrench", "brush": "Brush", "repair": "Grinder and welder",
	"spray": "Spray can"}
const EYE := 1.62
const WALK := 3.2
const RUN := 5.5
const REACH := 2.6
const MOUSE_SENS := 0.0025
const PAD_LOOK := 2.6

var camera: Camera3D
var tool := "hands"
var controls_enabled := true
var target := {}            # what the crosshair is on: {kind, bike, engine, slot, spot}
var plan := {}              # what the action button would do: {action, time, verb, blocked}
var info := ""              # description of the target for the HUD
var progress := 0.0         # 0..1 of the current hold-to-work action
var spray_color := 0        # index into Shed.PAINTS loaded in the spray can
var spray_finish := 0       # index into Shed.FINISHES

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
	_work_sound = Sfx.make_loop_player(camera)
	_work_sound.position = Vector3(0.0, -0.3, -0.6)
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
	elif tool == "spray" and event.is_action_pressed("spray_colour"):
		spray_color = (spray_color + 1) % Shed.PAINTS.size()
		_spray_changed()
	elif tool == "spray" and event.is_action_pressed("spray_finish"):
		spray_finish = (spray_finish + 1) % Shed.FINISHES.size()
		_spray_changed()
	elif event.is_action_pressed("interact"):
		# Mark the press handled before mounting, or the same F reaches main and gets you off again.
		if target.get("kind", "") == "part" and int(target.get("bike", 0)) != 0:
			get_viewport().set_input_as_handled()
			mount_requested.emit(int(target["bike"]))
		elif target.get("kind", "") == "pc":
			get_viewport().set_input_as_handled()
			computer_requested.emit()
		elif target.get("kind", "") == "radio":
			get_viewport().set_input_as_handled()
			Shed.request({"a": "radio", "on": not Shed.radio["on"]})
	else:
		for i in TOOLS.size():
			if event.is_action_pressed("tool_%d" % (i + 1)):
				set_tool(TOOLS[i])


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
	if is_on_floor():
		_stride += Vector2(velocity.x, velocity.z).length() * delta
		if _stride > (0.85 if running else 0.7):
			_stride = 0.0
			Sfx.play_at("step", global_position, -14.0)
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
		elif c.has_meta("engine") and Shed.is_engine(int(c.get_meta("engine"))):
			t = {"kind": "part", "engine": int(c.get_meta("engine")), "slot": str(c.get_meta("slot"))}
		elif c.has_meta("spot"):
			t = {"kind": "spot", "spot": str(c.get_meta("spot"))}
		elif c.has_meta("pc"):
			t = {"kind": "pc"}
		elif c.has_meta("bin"):
			t = {"kind": "bin"}
		elif c.has_meta("radio"):
			t = {"kind": "radio"}
		elif c.has_meta("item") and Shed.items.has(int(c.get_meta("item"))):
			t = {"kind": "item", "item": int(c.get_meta("item"))}
		elif Shed.held_by(Shed.me()) != 0 and (c is CollisionObject3D) and (c as CollisionObject3D).collision_layer & 1:
			t = {"kind": "surface"}
		# Anything flat enough can take a part put down on it, whatever the crosshair is on.
		if not t.is_empty() and (hit["normal"] as Vector3).y > 0.6:
			t["drop"] = Transform3D(Basis(Vector3.UP, rotation.y), hit["position"])
	target = t
	plan = _make_plan()
	info = _describe()
	_highlight()


## The bike or engine a part target belongs to, as action fields.
func _where() -> Dictionary:
	if int(target.get("engine", 0)) != 0:
		return {"engine": int(target["engine"]), "slot": str(target["slot"])}
	return {"bike": int(target.get("bike", 0)), "slot": str(target.get("slot", ""))}


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
	var me := Shed.me()
	var held := Shed.held_by(me)
	var kind := str(target.get("kind", ""))
	if kind == "":
		return {}
	var item_id := target_item()
	var p := {}
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
				match kind:
					"part":
						var a := _where()
						a["a"] = "install"
						p = {"action": a, "time": 1.2, "verb": "fit the " + held_name}
					"spot":
						var on_spot := Shed.item_at_spot(str(target["spot"]))
						if Shed.is_engine(on_spot) and not Shed.is_engine(held):
							# Building an engine back up: fit the part to the block on the stand.
							p = {"action": {"a": "install", "engine": on_spot, "slot": ""}, "time": 1.2, "verb": "fit the " + held_name}
						elif on_spot != 0 and target.has("drop"):
							p = {"action": {"a": "drop", "xf": target["drop"]}, "time": 0.25, "verb": "put it down here"}
						else:
							p = {"action": {"a": "place", "spot": target["spot"]}, "time": 0.25, "verb": "put it down"}
					"bin":
						p = {"action": {"a": "bin"}, "time": 0.4, "verb": "scrap the " + held_name}
					"surface", "item":
						if target.has("drop"):
							p = {"action": {"a": "drop", "xf": target["drop"]}, "time": 0.25, "verb": "put it down here"}
			else:
				match kind:
					"part":
						var a := _where()
						a["a"] = "remove"
						p = {"action": a, "time": 1.0, "verb": "take it off"}
					"spot":
						if item_id != 0:
							p = {"action": {"a": "take", "spot": target["spot"]}, "time": 0.25, "verb": "pick it up"}
					"item":
						p = {"action": {"a": "take", "item": item_id}, "time": 0.25, "verb": "pick it up"}
					"pc":
						p = {"action": {"a": "computer"}, "time": 0.15, "verb": "use the parts computer"}
		"wrench":
			if kind == "part":
				var a := _where()
				var bolted := Shed.bolted_at_target(target)
				a["a"] = "unbolt" if bolted else "bolt"
				p = {"action": a, "time": 1.6, "verb": "unbolt it" if bolted else "bolt it up"}
		"brush":
			if item_id != 0:
				p = {"action": {"a": "clean", "item": item_id}, "time": 1.0 + 3.0 * float(Shed.items[item_id]["dirt"]), "verb": "scrub it clean"}
		"repair":
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				p = {"action": {"a": "repair", "item": item_id}, "time": 2.0 + 4.0 * (float(it["rust"]) + float(it["wear"])),
					"verb": "grind off the rust and rebuild it"}
		"spray":
			if item_id != 0:
				p = {"action": {"a": "paint", "item": item_id, "color": spray_color, "finish": Shed.FINISHES[spray_finish]},
					"time": 1.5, "verb": "spray it %s" % spray_text().to_lower()}
	if p.is_empty():
		return {}
	p["blocked"] = "" if p["action"]["a"] == "computer" else Shed.check(me, p["action"])
	return p


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
			var held := Shed.held_by(Shed.me())
			if held != 0 and tool == "hands":
				lines.append(_preview(held))
			if engine_id != 0:
				var missing := Shed.engine_missing(engine_id)
				lines.append("Engine complete." if missing.is_empty() else "Engine needs: %s" % ", ".join(missing.map(func(m): return PartsDB.slot_name(m).to_lower())))
			else:
				var bike_id := int(target["bike"])
				for note in Shed.build_of(bike_id).notes:
					lines.append("! " + note)
				var ride := Shed.check(Shed.me(), {"a": "mount", "bike": bike_id})
				lines.append("F: ride %s" % Shed.bikes[bike_id]["name"] if ride == "" else "Can't ride yet. " + ride)
		"spot":
			var spot := str(target["spot"])
			var item_id := Shed.item_at_spot(spot)
			var where: String = {"washer": "Parts washer", "repair": "Repair bench", "engine_stand": "Engine stand"}.get(spot,
				"Delivery pallet" if spot.begins_with("delivery") else "Workbench")
			if item_id != 0:
				var it: Dictionary = Shed.items[item_id]
				lines.append(PartsDB.part_name(it["part"]))
				lines.append("%s  ·  %s" % [where, PartsDB.KIND_NAMES[it["kind"]]])
				lines.append(PartsDB.spec_line(it["part"]))
				lines.append(Shed.condition_text(it))
				if Shed.is_engine(item_id) and spot == "engine_stand":
					var missing := Shed.engine_missing(item_id)
					lines.append("Engine complete." if missing.is_empty() else "Engine needs: %s" % ", ".join(missing.map(func(m): return PartsDB.slot_name(m).to_lower())))
				var held := Shed.held_by(Shed.me())
				if held != 0 and tool == "hands" and Shed.is_engine(item_id) and not Shed.is_engine(held):
					lines.append(_preview(held, {"engine": item_id, "slot": ""}))
				if spot == "washer" and float(it["dirt"]) > 0.0:
					lines.append("Washing... %d%% dirt left" % roundi(float(it["dirt"]) * 100.0))
			else:
				lines.append(where)
				match spot:
					"washer":
						lines.append("Leave a dirty part in here and it comes out clean.")
					"repair":
						lines.append("Put a part here and use the grinder and welder to restore it.")
					"engine_stand":
						lines.append("Bolt an engine on here to strip it or build it up.")
		"item":
			var it: Dictionary = Shed.items[int(target["item"])]
			lines.append(PartsDB.part_name(it["part"]))
			lines.append("Put down here  ·  %s" % PartsDB.KIND_NAMES[it["kind"]])
			lines.append(PartsDB.spec_line(it["part"]))
			lines.append(Shed.condition_text(it))
		"radio":
			lines.append("Shed radio (everyone hears it)")
			var view: Node = get_tree().get_first_node_in_group("workshop")
			if view and view.radio:
				lines.append(view.radio.now_playing())
			lines.append("F: switch %s" % ("off" if Shed.radio["on"] else "on"))
		"pc":
			lines.append("Parts computer")
			lines.append("Order any part. It turns up on the delivery pallets.")
		"bin":
			lines.append("Scrap bin")
			lines.append("Drop parts you don't want in here.")
	return "\n".join(lines)


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
	return "%s: %d → %d hp   %d → %d km/h   %d → %d kg   brakes %d → %d" % [verb, roundi(before["hp"]), roundi(after["hp"]),
		roundi(before["top_kmh"]), roundi(after["top_kmh"]), roundi(before["mass"]), roundi(after["mass"]),
		roundi(before["brake"]), roundi(after["brake"])]


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
	return controls_enabled and (Input.is_action_pressed("act") or Controls.trigger(true) > 0.5)


func _update_work(delta: float) -> void:
	var key := str(plan.get("action", {}))
	if plan.get("action", {}).get("a", "") == "drop":
		key = "drop"  # the spot moves with the crosshair; keep the hold going
	if not _acting():
		_need_release = false
	if plan.is_empty() or plan["blocked"] != "" or key != _plan_key or not _acting() or _need_release:
		Sfx.set_loop(_work_sound, "")
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
		Sfx.set_loop(_work_sound, Sfx.WORK_LOOPS.get(plan["action"]["a"], ""))
	_hold += delta
	progress = clampf(_hold / float(plan["time"]), 0.0, 1.0)
	if progress >= 1.0:
		if plan["action"]["a"] == "computer":
			computer_requested.emit()
		else:
			Shed.request(plan["action"])
			var done: String = Sfx.DONE_SOUNDS.get(plan["action"]["a"], "")
			if done != "":
				Sfx.play_at(done, camera.global_position - camera.global_transform.basis.z * 1.2, -4.0)
		Sfx.set_loop(_work_sound, "")
		_hold = 0.0
		progress = 0.0
		_need_release = true
		_send_status("")


func _activity_text() -> String:
	var a: Dictionary = plan["action"]
	var what := ""
	if target.get("kind", "") == "part":
		var owner := "the engine" if int(target.get("engine", 0)) != 0 else str(Shed.bikes[target["bike"]]["name"])
		what = "the %s on %s" % [PartsDB.slot_name(target["slot"]).to_lower(), owner]
	var verbs := {"unbolt": "Unbolting", "bolt": "Bolting up", "remove": "Removing", "install": "Fitting a part to",
		"clean": "Cleaning", "repair": "Restoring", "paint": "Spraying", "take": "Picking up a part",
		"place": "Putting down a part", "drop": "Putting down a part", "radio": "Fiddling with the radio", "bin": "Scrapping a part", "computer": "Browsing the parts computer"}
	var verb: String = verbs.get(a["a"], "Working on")
	if a["a"] in ["clean", "repair", "paint"] and what == "":
		what = "the " + Shed.item_title(int(a["item"]))
	if a["a"] == "install":
		what = "the engine" if int(a.get("engine", 0)) != 0 else str(Shed.bikes[int(a.get("bike", 0))]["name"])
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
		sig = "%d:%s:%.1f:%.1f:%.1f:%s:%s" % [held, it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", "")]
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
	_held_view = BikeModel.item_display(held)
	var size: Vector3 = _held_view.get_meta("size", Vector3.ONE)
	var s := clampf(0.55 / maxf(size.x, maxf(size.y, size.z)), 0.2, 1.0)
	_held_view.scale = Vector3.ONE * s
	_held_view.position = Vector3(0.0, -0.42, -0.75)
	_held_view.rotation = Vector3(0.0, 0.5, 0.0)
	camera.add_child(_held_view)


func _set_tool_view() -> void:
	if _tool_view:
		_tool_view.queue_free()
	_tool_view = make_tool_mesh(tool, Shed.PAINTS[spray_color])
	_tool_view.position = Vector3(0.28, -0.28, -0.5)
	_tool_view.rotation = Vector3(0.25, -0.3, 0.0)
	camera.add_child(_tool_view)


## A simple mesh of a tool, held in the hand. Shared with other players' avatars.
static func make_tool_mesh(which: String, can_color := Color(0.9, 0.75, 0.1)) -> Node3D:
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
		"spray":
			var can := StandardMaterial3D.new()
			can.albedo_color = can_color
			can.metallic = 0.6
			can.roughness = 0.3
			parts = [[Vector3(0, -0.02, 0), Vector3(0.06, 0.18, 0.06), can], [Vector3(0, 0.09, 0), Vector3(0.03, 0.04, 0.03), steel],
				[Vector3(0, 0.12, -0.01), Vector3(0.02, 0.02, 0.03), grip]]
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
