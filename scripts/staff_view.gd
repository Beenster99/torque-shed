class_name StaffView
extends Node3D
## The garage's staff as drawn on every player's game, from Shed.staff (see Staff): each worker
## a StaffFigure walking the shed on the paths the host gave them (drawn smoothly between syncs
## from the staff clock), pushing a bike along with them (the bike follows them here every
## frame), carrying the part, box or tray of tea they have, holding the tool for the job and
## working it. Off sick, they're not here. Look at one and the HUD's look panel says who they
## are and what they're up to; press F to talk to them, give them a job or let them go
## (StaffPanel). Nothing here is shared state. Main makes one and puts it in the world.

signal talk_requested(worker_id: int)

const REACH := 3.5
## A client's staff clock is put right when it drifts this far (s) from the host's.
const CLOCK_SLACK := 0.6
## Further than this (m) between frames is a teleport: no easing.
const SNAP := 2.0
const TURN := 10.0

var main: Node                 # for the walker, the bikes and whether a menu is open
var figures := {}              # worker id -> StaffFigure
var _hands := {}               # worker id -> what's drawn in their hands (see _hand_sig)
## What each is up to, as drawn between syncs: worker id -> [carrying, anim, crouched].
var _pose := {}
var _clock := 0.0
var _looked := 0
var _tip := ["", ""]           # the look panel's text and prompt last handed to the walker
var _tip_stale := true
var _said_timer := 0.0


func _ready() -> void:
	Shed.changed.connect(sync_state)


## Brings the figures into line with Shed.staff: new staff drawn, the ones let go taken away,
## and what each is holding, doing and saying (everything that only changes with a sync, so
## nothing is worked out again every frame).
func sync_state() -> void:
	var ws := Staff.workers() if Shed.active else {}
	for id in figures.keys():
		if not ws.has(id):
			if is_instance_valid(figures[id]):
				figures[id].queue_free()
			figures.erase(id)
			_hands.erase(id)
			_pose.erase(id)
	for id in ws:
		var w: Dictionary = ws[id]
		var f: StaffFigure = figures.get(id)
		if f == null:
			f = StaffFigure.new()
			add_child(f)
			f.build(w)
			f.position = Staff.pos_at(w, Staff.clock())
			f.rotation.y = float(w.get("yaw", 0.0))
			figures[id] = f
		var here: bool = not w.get("sick", false)
		f.visible = here
		f.body.collision_layer = Workshop.INTERACT_LAYER if here else 0
		var peer := Staff.peer_of(int(id))
		var held := Shed.held_by(peer)
		var tray := CoffeeShop.tray_of(peer)
		var anim := str(w.get("anim", ""))
		_pose[id] = [held != 0 or not tray.is_empty(), anim, _crouched(w)]
		var sig := _hand_sig(w, held, tray, anim)
		if sig != str(_hands.get(id, "")):
			_hands[id] = sig
			_fill_hands(f, w, held, tray, anim)
		var jet := f.hand.get_node_or_null("Jet") as CPUParticles3D
		if jet:
			jet.emitting = anim == "lance"
		var mist := f.hand.get_node_or_null("Mist") as CPUParticles3D
		if mist:
			mist.emitting = anim == "spray"
			(mist.get_node("Haze") as CPUParticles3D).emitting = anim == "spray"
		f.set_said(Staff.saying(w))
	if absf(_clock - Staff.clock()) > CLOCK_SLACK:
		_clock = Staff.clock()
	_tip_stale = true


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("staff", pt)


func _process_body(delta: float) -> void:
	if figures.is_empty():
		if _tip[0] != "":
			_set_tip(0)
		return
	# The host's clock is the real one; a joiner's runs on between syncs.
	_clock = Staff.clock() if Shed.is_authority() else _clock + delta
	var ws := Staff.workers()
	for id in figures:
		if ws.has(id) and _pose.has(id):
			_draw_worker(figures[id], ws[id], _pose[id], delta)
	# What they said goes again after a while (checked now and then, not every frame).
	_said_timer -= delta
	if _said_timer <= 0.0:
		_said_timer = 0.5
		for id in figures:
			if ws.has(id):
				figures[id].set_said(Staff.saying(ws[id]))
	var now := _look() if main and main.walker and main.walker.controls_enabled else 0
	if now != _looked or _tip_stale:
		if now != _looked:
			if figures.has(_looked) and is_instance_valid(figures[_looked]):
				figures[_looked].set_hint(false)
			if figures.has(now):
				figures[now].set_hint(true)
			_looked = now
		_tip_stale = false
		_set_tip(now)


func _draw_worker(f: StaffFigure, w: Dictionary, pose: Array, delta: float) -> void:
	if not f.visible:
		return
	var leg: Dictionary = w["leg"]
	var walking := false
	var pushing := 0
	var yaw := float(w["yaw"])
	var at: Vector3 = w["pos"]
	if not leg.is_empty():
		var pts: PackedVector3Array = leg["pts"]
		var s := (_clock - float(leg["t0"])) * float(leg["v"])
		walking = s < float(leg["len"])
		at = Staff.pos_at(w, _clock)
		pushing = int(leg.get("push", 0))
		var cart := int(leg.get("cart", 0))
		if walking:
			var ahead := StaffNav.BIKE_AHEAD if pushing != 0 else (StaffNav.CART_AHEAD if cart != 0 else 0.0)
			yaw = StaffNav.heading(pts, maxf(0.0, s - ahead), yaw)
		if pushing != 0:
			_draw_pushed(pushing, pts, minf(s, float(leg["len"])), float(leg["len"]))
		elif cart != 0:
			# The trolley they're pushing, drawn just ahead of them between syncs.
			if main and main.workshop and Shed.furniture.has(cart):
				main.workshop.preview_furniture(cart, Staff._cart_xf(leg, _clock))
			pushing = cart
	if f.position.distance_to(at) > SNAP:
		f.rotation.y = yaw
	else:
		f.rotation.y = lerp_angle(f.rotation.y, yaw, minf(1.0, delta * TURN))
	f.position = at
	var anim: String = pose[1]
	f.animate(delta, walking, pushing != 0, pose[0], anim, not walking and pose[2])


## The bike they're wheeling, drawn just ahead of them along the way they're going.
func _draw_pushed(bike: int, pts: PackedVector3Array, s: float, length: float) -> void:
	if main == null or main.workshop == null or not main.workshop.bike_views.has(bike) or not Shed.bikes.has(bike):
		return
	var y := (Shed.bikes[bike]["xf"] as Transform3D).origin.y
	var p := StaffNav.along(pts, minf(s, length))
	var xf := Transform3D(Basis(Vector3.UP, StaffNav.heading(pts, s)), Vector3(p.x, y, p.z))
	(main.workshop.bike_views[bike] as Node3D).transform = xf


## Whether the work step they're on has them down at the bike.
static func _crouched(w: Dictionary) -> bool:
	var job: Dictionary = w.get("job", {})
	if job.is_empty():
		return false
	var steps: Array = job.get("steps", [])
	var i := int(job.get("i", 0))
	if i >= steps.size() or not (steps[i] is Dictionary):
		return false
	var act = steps[i].get("act", {})
	return act is Dictionary and act.get("crouched", false)


## The tool a job's work looks like it needs.
static func tool_for(anim: String) -> String:
	match anim:
		"wrench", "fit", "changer", "oil", "fairing", "tail":
			return "wrench"
		"lance":
			return "lance"
		"spray":
			return "gun"
		"grind", "blaster":
			return "repair"
		"detail":
			return "brush"
	return "hands"


static func _hand_sig(w: Dictionary, held: int, tray: Dictionary, anim: String) -> String:
	var it: Dictionary = Shed.items.get(held, {})
	return "%d|%s|%s|%s" % [held, str(it.get("boxed", false)), str(tray.get("items", "-")), tool_for(anim)]


## What they hold: a part (or its box) or the tray of teas out in front, else the tool for
## the job in their hand.
func _fill_hands(f: StaffFigure, w: Dictionary, held: int, tray: Dictionary, anim: String) -> void:
	for c in f.carry.get_children():
		c.queue_free()
	for c in f.hand.get_children():
		c.queue_free()
	if held != 0 or not tray.is_empty():
		RemotePlayer.fill_hand(f.carry, Staff.peer_of(int(w["id"])), "hands")
		return
	var tool := tool_for(anim)
	if tool == "hands":
		return
	var t := Walker.make_tool_mesh(tool, Color(0.9, 0.75, 0.1), 1)
	f.hand.add_child(t)
	if tool == "lance":
		var jet := Walker.make_jet()
		jet.name = "Jet"
		jet.position = Vector3(0.0, 0.0, -0.6)
		f.hand.add_child(jet)
	elif tool == "gun":
		var mist := Walker.make_mist()
		mist.name = "Mist"
		mist.color = Color(0.85, 0.85, 0.85)
		mist.position = Vector3(0.0, 0.1, -0.15)
		f.hand.add_child(mist)


# ---------------------------------------------------------------------------- looking and talking

## The worker under the crosshair of the player on foot (0 for none).
func _look() -> int:
	if main == null or main.walker == null or main.bike != null:
		return 0
	if Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0:
		return 0
	var cam: Camera3D = main.walker.camera
	if cam == null or not cam.is_inside_tree():
		return 0
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH, Workshop.INTERACT_LAYER | 1)
	q.exclude = [main.walker.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit:
		return 0
	var c: Object = hit["collider"]
	return int(c.get_meta("staff")) if c.has_meta("staff") else 0


## The worker being looked at (tests).
func looked() -> int:
	return _looked


func _set_tip(id: int) -> void:
	var tip := tooltip(id)
	if tip == _tip or main == null or main.walker == null:
		return
	# Only clear the look panel when it's still showing ours (another thing may have it now).
	if tip[0] != "" or main.walker.look_info == _tip[0]:
		main.walker.look_info = tip[0]
		main.walker.look_prompt = tip[1]
	_tip = tip


## The look panel for worker `id`: [who they are and what they're doing, the key prompt].
static func tooltip(id: int) -> Array:
	var w := Staff.worker(id)
	if w.is_empty():
		return ["", ""]
	var lines := ["%s  ·  %s, level %d" % [str(w["name"]), Staff.role_name(str(w["role"])), Staff.level(w)],
		Staff.status_text(w), "%s  ·  %s a day" % [Staff.mood_word(w).left(1).to_upper() + Staff.mood_word(w).substr(1), Staff.money(int(w["wage"]))]]
	return ["\n".join(lines), "%s: talk to %s" % [Controls.key("interact"), Staff.first_name(w)]]


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or main == null or main.walker == null or not main.walker.controls_enabled:
		return
	var id := _look()
	if id != 0:
		get_viewport().set_input_as_handled()
		talk_requested.emit(id)
