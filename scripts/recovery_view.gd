class_name RecoveryView
extends Node3D
## The recovery rig in the world (see Recovery): the truck and trailer, parked where Shed says,
## driven by you (live physics on your machine), or by someone else (moved by their network
## state). It puts the bikes on the trailer where they ride on it, draws the winch cable, the
## ratchet straps and the dolly tray, the tarp over a barn find and a beacon over each site, the
## HUD's distance to the next site and the driving read-out, and gives the walker the things to
## press F on (see use_text and use): the driver's door, the jobs clipboard, the ramp, the winch,
## the dolly tray, the strap anchors and the tarp.

const EXIT_SPEED := 1.5
const MOVE_EVERY := 1.5        # seconds between telling the host where the truck has got to
const REMOTE_DELAY := 0.12
const STRAP_ANCHORS := [Vector3(-0.42, 0.03, -0.95), Vector3(0.42, 0.03, -0.95), Vector3(-0.42, 0.03, 0.85),
	Vector3(0.42, 0.03, 0.85)]
## Where each strap meets the bike (its view's own space): the bars, then the rear footpegs.
const STRAP_BIKE := [Vector3(-0.3, 0.95, -0.55), Vector3(0.3, 0.95, -0.55), Vector3(-0.16, 0.45, 0.35), Vector3(0.16, 0.45, 0.35)]

static var current: RecoveryView

var main: Node
var car: Car
var trailer: Trailer
## This player is at the wheel.
var driving := false
var audio: EngineSound
var hud_label: Label
var _remote := {}              # peer -> [{t, s}] snapshots of their truck
var _remote_audio: EngineSound
var _dolly: Node3D
var _cable: MeshInstance3D
var _straps := {}
var _tarps := {}
var _markers := {}
var _parked_sig := ""
var _mass_sig := ""
var _move_timer := 0.0
var _view := ChaseCamera.Mode.CHASE
var _entered_at := 0
var _offers_seen := -1
var _lifted := 0               # the bike raised up on the dolly on the ground
var _strap_mat: StandardMaterial3D
var _cable_mat: StandardMaterial3D


func _ready() -> void:
	current = self
	name = "Recovery"
	process_priority = 100   # after the shed has put the bikes where Shed says
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_label = Label.new()
	hud_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud_label.position.y = 84.0   # under the flash messages
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud_label.add_theme_constant_override("outline_size", 5)
	hud_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(hud_label)
	_strap_mat = Trailer._mat(Color(0.95, 0.55, 0.05), 0.0, 0.7)
	_cable_mat = Trailer._mat(Color(0.2, 0.2, 0.22), 0.8, 0.3)
	Shed.changed.connect(_on_shed_loads)


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(delta: float) -> void:
	if not Shed.active or not Recovery.owned() or main == null or not main.in_session:
		_free_rig()
		hud_label.text = ""
		_sync_markers()
		return
	_ensure_rig()
	var drv := Recovery.driver()
	if driving:
		pass
	elif drv != 0 and drv != Shed.me() and _remote.has(drv) and not (_remote[drv] as Array).is_empty():
		_follow_remote(drv)
	else:
		var c := Recovery.car()
		var sig := str(c["xf"]) + str(c["trailer_xf"])
		if sig != _parked_sig:
			_parked_sig = sig
			car.global_transform = c["xf"]
			trailer.global_transform = c["trailer_xf"]
		car.stop_engine()
		if is_instance_valid(_remote_audio):
			_remote_audio.running = false
	trailer.ramp_down = bool(Recovery.car()["ramp"])
	if drv != 0:
		_keep_off_trailer()
	_place_loads()
	_place_dolly()
	_draw_cable()
	_draw_straps()
	_sync_tarps()
	_sync_markers()
	_update_hud()
	_ring_for_offers()
	if driving:
		_move_timer += delta
		if _move_timer >= MOVE_EVERY:
			_move_timer = 0.0
			Shed.request({"a": "recovery_move", "xf": car.global_transform, "trailer_xf": trailer.global_transform})


## Nobody rides on the trailer: while someone's driving, a walker stood on its bed or ramp is
## put down on the ground beside it, on the side they were nearer.
func _keep_off_trailer() -> void:
	var w: Walker = main.walker
	if w == null or w.process_mode == Node.PROCESS_MODE_DISABLED or not trailer.carries(w.global_position):
		return
	var l := trailer.global_transform.affine_inverse() * w.global_position
	var side := 1.0 if l.x >= 0.0 else -1.0
	var at := trailer.global_transform * Vector3(side * (Trailer.BED_HALF_W + 0.9), 0.0, clampf(l.z, Trailer.BED_FRONT, Trailer.BED_REAR))
	at.y = trailer.global_position.y
	w.place(Transform3D(w.global_basis, at))
	main.hud.flash("No riding on the trailer: you hop off as it pulls away.", 2.5, true)


func _ensure_rig() -> void:
	if car != null:
		return
	car = Car.new()
	car.name = "RecoveryTruck"
	car.freeze = true
	car.set_meta("chase_scale", 2.0)
	add_child(car)
	trailer = Trailer.new()
	trailer.name = "RecoveryTrailer"
	trailer.freeze = true
	add_child(trailer)
	trailer.car = car
	trailer.add_collision_exception_with(car)
	trailer.load_moved.connect(_on_load_moved)
	trailer.load_fell.connect(_on_load_fell)
	_parked_sig = ""
	# The things to press F on.
	_use_box(car, Vector3(0.16, 1.0, 1.0), Vector3(0.98, 1.2, -0.55), {"what": "drive"})
	_use_box(car, Vector3(0.16, 1.0, 1.0), Vector3(-0.98, 1.2, -0.55), {"what": "jobs"})
	_use_box(trailer, Vector3(0.35, 0.6, 0.3), Trailer.WINCH + Vector3(0.0, -0.15, 0.0), {"what": "winch"})
	_use_box(trailer, Vector3(1.5, 0.5, 0.35), Vector3(0.0, Trailer.BED_Y + 0.15, Trailer.BED_REAR + 0.15), {"what": "ramp"})
	_use_box(trailer, Vector3(0.2, 0.4, 2.0), Vector3(-Trailer.BED_HALF_W - 0.12, Trailer.BED_Y - 0.1, -0.1), {"what": "dolly"})
	for slot in Trailer.SLOTS_X.size():
		for p in Recovery.STRAPS:
			var a: Vector3 = STRAP_ANCHORS[p]
			_use_box(trailer, Vector3(0.2, 0.2, 0.2), Vector3(float(Trailer.SLOTS_X[slot]) + a.x, Trailer.BED_Y + 0.08, Trailer.SLOT_Z + a.z),
				{"what": "strap", "slot": slot, "point": p})
	_dolly = Node3D.new()
	_dolly.name = "Dolly"
	add_child(_dolly)
	Trailer.build_dolly(_dolly)
	_use_box(_dolly, Vector3(0.45, 0.35, 2.1), Vector3(0.0, 0.15, 0.0), {"what": "dolly"})
	_cable = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, 1.0)
	_cable.mesh = bm
	_cable.material_override = _cable_mat
	add_child(_cable)


func _use_box(parent: Node3D, size: Vector3, at: Vector3, use: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.set_meta("use_node", self)
	body.set_meta("use", use)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	parent.add_child(body)
	return body


func _free_rig() -> void:
	if driving:
		stop_driving(false)
	for n in [car, trailer, _dolly, _cable]:
		if is_instance_valid(n):
			n.queue_free()
	car = null
	trailer = null
	_dolly = null
	_cable = null
	for k in _straps:
		if is_instance_valid(_straps[k]):
			_straps[k].queue_free()
	_straps.clear()
	for k in _tarps:
		if is_instance_valid(_tarps[k]):
			_tarps[k].queue_free()
	_tarps.clear()


# ---------------------------------------------------------------------------- what's on the trailer

func _bike_view(id: int) -> Node3D:
	if main == null or main.workshop == null:
		return null
	return main.workshop.bike_views.get(id) as Node3D


## Each bike on (or going up or down) the trailer stands where it rides on it.
func _place_loads() -> void:
	var loads := Recovery.loads()
	var masses := []
	for id in loads:
		var l: Dictionary = loads[id]
		var z := float(l.get("z", 0.0))
		if driving and trailer.load_sim.has(id):
			z = float(trailer.load_sim[id]["z"])
		var local := Trailer.load_transform(int(l["slot"]), float(l["s"]), z, bool(l.get("tipped", false)), Recovery._wheelbase(int(id)))
		if bool(l.get("dolly", false)):
			local.origin.y += Recovery.DOLLY_LIFT
		masses.append([float(Shed.bikes.get(id, {}).get("mass", 190.0)), local.origin + Vector3.UP * 0.5])
		var view := _bike_view(int(id))
		if view:
			view.global_transform = trailer.global_transform * local
	var sig := str(masses)
	if sig != _mass_sig:
		_mass_sig = sig
		trailer.set_loads(masses)


## Raises the model inside bike `id`'s view by `h` (0 puts it back down).
func _lift(id: int, h: float) -> void:
	var view := _bike_view(id)
	if view and view.get_child_count() > 0 and view.get_child(0) is Node3D:
		(view.get_child(0) as Node3D).position.y = h


## The dolly tray: on its rail, on the ground, or under the bike on it.
func _place_dolly() -> void:
	var d := Recovery.dolly()
	var at := str(d["at"])
	trailer.dolly_stowed.visible = at == "trailer"
	_dolly.visible = at != "trailer"
	# The bike stood on the dolly on the ground is raised inside its view (the view itself is
	# where Shed, or the one pushing it, puts it); on the trailer _place_loads raises it.
	var lifted := int(d["bike"]) if at == "bike" else 0
	if _lifted != lifted:
		_lift(_lifted, 0.0)
		_lifted = lifted
	_lift(lifted, Recovery.DOLLY_LIFT)
	match at:
		"ground":
			_dolly.global_transform = d["xf"]
		"bike", "load":
			var view := _bike_view(int(d["bike"]))
			if view:
				var xf := view.global_transform
				_dolly.global_transform = xf if at == "bike" else xf.translated(-xf.basis.y * Recovery.DOLLY_LIFT)
			else:
				_dolly.global_transform = d["xf"]
	if at == "trailer":
		_dolly.global_transform = Transform3D(Basis(), Vector3(0.0, -50.0, 0.0))


func _draw_cable() -> void:
	var id := int(Recovery.car()["winch"])
	var view := _bike_view(id)
	_cable.visible = id != 0 and view != null
	if not _cable.visible:
		return
	var from := trailer.global_transform * Trailer.WINCH
	var to := view.global_transform * Vector3(0.0, 0.55, -Recovery._wheelbase(id) * 0.5 - 0.1)
	_line(_cable, from, to)
	trailer.winch_drum.rotation.x += 0.15 * float(Recovery.car()["winch_dir"])


static func _line(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := maxf(d.length(), 0.01)
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(d / len, up)
	mi.global_transform = Transform3D(basis.scaled_local(Vector3(1.0, 1.0, len)), (from + to) * 0.5)


func _draw_straps() -> void:
	var want := {}
	for id in Recovery.loads():
		var l: Dictionary = Recovery.loads()[id]
		var view := _bike_view(int(id))
		if view == null:
			continue
		var st: Array = l.get("straps", [])
		for p in st.size():
			if not st[p]:
				continue
			var key := "%d:%d" % [int(id), p]
			want[key] = true
			if not _straps.has(key):
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.035, 0.004, 1.0)
				mi.mesh = bm
				mi.material_override = _strap_mat
				add_child(mi)
				_straps[key] = mi
			var a: Vector3 = STRAP_ANCHORS[p]
			var from := trailer.global_transform * Vector3(float(Trailer.SLOTS_X[int(l["slot"])]) + a.x, Trailer.BED_Y + a.y,
				Trailer.SLOT_Z + a.z + float(l.get("z", 0.0)))
			_line(_straps[key], from, view.global_transform * (STRAP_BIKE[p] as Vector3))
	for key in _straps.keys():
		if not want.has(key):
			_straps[key].queue_free()
			_straps.erase(key)


## A barn find still under its tarp: a green sheet draped over it, which F pulls off.
func _sync_tarps() -> void:
	var want := {}
	for jid in Recovery.jobs():
		var j: Dictionary = Recovery.jobs()[jid]
		if not bool(j.get("tarp", false)):
			continue
		var id := int(j["bike"])
		var view := _bike_view(id)
		if view == null:
			continue
		want[id] = true
		if not _tarps.has(id):
			var t := Node3D.new()
			add_child(t)
			var green := Trailer._mat(Color(0.18, 0.26, 0.16), 0.0, 0.95)
			Trailer._box(t, Vector3(0.95, 0.05, 2.4), Vector3(0.0, 1.12, 0.0), green, Vector3(0.0, 0.0, 0.0))
			for side: float in [-1.0, 1.0]:
				Trailer._box(t, Vector3(0.05, 1.05, 2.3), Vector3(side * 0.47, 0.6, 0.0), green, Vector3(0.0, 0.0, side * 0.12))
			for end: float in [-1.0, 1.0]:
				Trailer._box(t, Vector3(0.9, 0.9, 0.05), Vector3(0.0, 0.62, end * 1.18), green, Vector3(end * 0.15, 0.0, 0.0))
			_use_box(t, Vector3(1.0, 1.15, 2.4), Vector3(0.0, 0.6, 0.0), {"what": "tarp", "bike": id})
			_tarps[id] = t
		var vx := view.global_transform
		(_tarps[id] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, vx.basis.get_euler().y), vx.origin)
	for id in _tarps.keys():
		if not want.has(id):
			_tarps[id].queue_free()
			_tarps.erase(id)


## A tall beacon over each bike still to fetch, seen from far off.
func _sync_markers() -> void:
	var want := {}
	if Shed.active and Recovery.owned():
		for jid in Recovery.jobs():
			var j: Dictionary = Recovery.jobs()[jid]
			if str(j["state"]) != "collect" or Recovery.is_loaded(int(j["bike"])) or not Shed.bikes.has(int(j["bike"])):
				continue
			want[jid] = true
			if not _markers.has(jid):
				var m := Node3D.new()
				add_child(m)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(1.0, 0.6, 0.1, 0.35)
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				var beam := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.25
				cm.bottom_radius = 0.6
				cm.height = 60.0
				beam.mesh = cm
				beam.material_override = mat
				beam.position.y = 32.0
				beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				m.add_child(beam)
				var label := Label3D.new()
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.no_depth_test = true
				label.fixed_size = true
				label.pixel_size = 0.0012
				label.font_size = 26
				label.outline_size = 8
				label.position.y = 4.0
				label.modulate = Color(1.0, 0.75, 0.3)
				label.text = str(j["name"]).capitalize()
				m.add_child(label)
				_markers[jid] = m
			var b: Dictionary = Shed.bikes[int(j["bike"])]
			var m: Node3D = _markers[jid]
			m.global_position = (b["xf"] as Transform3D).origin
			# The beam fades out as you get there, so it isn't in the way of the work.
			var cam := get_viewport().get_camera_3d()
			var near := 1.0 if cam == null else clampf((cam.global_position.distance_to(m.global_position) - 12.0) / 30.0, 0.0, 1.0)
			var beam := m.get_child(0) as MeshInstance3D
			(beam.material_override as StandardMaterial3D).albedo_color.a = 0.35 * near
			beam.visible = near > 0.01
	for jid in _markers.keys():
		if not want.has(jid):
			_markers[jid].queue_free()
			_markers.erase(jid)


## The phone rings when a new recovery job comes in.
func _ring_for_offers() -> void:
	var n := Recovery.offers().size()
	if _offers_seen >= 0 and n > _offers_seen and main.hud:
		var newest := {}
		for id in Recovery.offers():
			if newest.is_empty() or int(id) > int(newest["id"]):
				newest = Recovery.offers()[id]
		Sfx.play_at("phone_ring", main.camera.global_position if not (main.walker and main.walker.camera.current) else main.walker.camera.global_position, -6.0)
		main.hud.flash("Phone: a recovery job, %s (%s). {menu}, Recovery or the clipboard in the truck." % [
			str(newest.get("name", "")).capitalize(), Recovery.money(int(newest.get("fee", 0)))], 6.0)
	_offers_seen = n


func _update_hud() -> void:
	var lines := []
	var from: Vector3 = car.global_position if driving else (main.walker.global_position if main.walker else car.global_position)
	var site := Recovery.next_site(from)
	if not site.is_empty():
		lines.append("RECOVERY  %s  ·  %s" % [site["name"], Recovery.distance_text(from, site["at"])])
	if driving:
		# The speed, gears and lamps are on the truck's dash in the corner (Hud._draw_truck_dash).
		var loose := 0
		for id in Recovery.loads():
			if not Recovery.secure(int(id)):
				loose += 1
		if loose > 0:
			lines.append("%d bike%s on the trailer not strapped down: go easy" % [loose, "" if loose == 1 else "s"])
	hud_label.text = "\n".join(lines)


# ---------------------------------------------------------------------------- pressing F on the rig

## The prompt for something on the rig the walker is looking at.
func use_text(t: Dictionary) -> String:
	var u: Dictionary = t.get("use", {})
	var me := Shed.me()
	match str(u.get("what", "")):
		"drive":
			var why := Shed.check(me, {"a": "recovery_enter"})
			return "Recovery truck\n" + ("{interact}: get in and drive" if why == "" else why)
		"jobs":
			return "Recovery jobs clipboard\n{interact}: see the jobs on offer and the ones under way"
		"ramp":
			var down := bool(Recovery.car()["ramp"])
			var why := Shed.check(me, {"a": "recovery_ramp", "down": not down})
			return "Trailer ramp\n" + (("{interact}: raise the ramp" if down else "{interact}: lower the ramp") if why == "" else why)
		"winch":
			return "Winch\n" + _winch_prompt()[0]
		"dolly":
			return "Dolly tray\n" + _dolly_prompt()[0]
		"strap":
			var id := _bike_in_slot(int(u["slot"]))
			if id == 0:
				return "Strap anchor\nNothing in this channel."
			var on: bool = (Recovery.loads()[id]["straps"] as Array)[int(u["point"])]
			var why := Shed.check(me, {"a": "recovery_strap", "bike": id, "point": int(u["point"])})
			return "Ratchet strap, %s, on %s (%d of 4 tight)\n%s" % [Recovery.STRAP_NAMES[int(u["point"])], Shed.bikes[id]["name"],
				Recovery.straps_on(id), ("{interact}: undo it" if on else "{interact}: ratchet it tight") if why == "" else why]
		"tarp":
			return "A bike under a tarp\n{interact}: pull the tarp off"
	return ""


## Does what pressing F on the rig does.
func use(t: Dictionary) -> void:
	var u: Dictionary = t.get("use", {})
	match str(u.get("what", "")):
		"drive":
			var why := Shed.check(Shed.me(), {"a": "recovery_enter"})
			if why != "":
				Shed.feedback.emit(why, false)
				return
			Shed.request({"a": "recovery_enter"})
		"jobs":
			if main.has_method("open_recovery"):
				main.open_recovery()
		"ramp":
			Shed.request({"a": "recovery_ramp", "down": not bool(Recovery.car()["ramp"])})
			Sfx.play_at("switch", trailer.global_position, -4.0)
		"winch":
			var a: Dictionary = _winch_prompt()[1]
			if not a.is_empty():
				Shed.request(a)
				Sfx.play_at("ratchet", trailer.global_transform * Trailer.WINCH, -6.0)
		"dolly":
			var a2: Dictionary = _dolly_prompt()[1]
			if not a2.is_empty():
				Shed.request(a2)
		"strap":
			var id := _bike_in_slot(int(u["slot"]))
			if id != 0:
				var on: bool = (Recovery.loads()[id]["straps"] as Array)[int(u["point"])]
				Shed.request({"a": "recovery_strap", "bike": id, "point": int(u["point"]), "on": not on})
				Sfx.play_at("ratchet", t.get("at", trailer.global_position), -3.0)
		"tarp":
			Shed.request({"a": "recovery_tarp", "bike": int(u["bike"])})


func _bike_in_slot(slot: int) -> int:
	for id in Recovery.loads():
		if int(Recovery.loads()[id]["slot"]) == slot and Recovery.on_bed(int(id)):
			return int(id)
	return 0


## What F at the winch does now, [prompt, action]: stop it, winch up the bike at the foot of
## the ramp, or let one down.
func _winch_prompt() -> Array:
	var me := Shed.me()
	if int(Recovery.car()["winch"]) != 0:
		return ["{interact}: stop the winch", {"a": "recovery_winch_stop"}]
	var near := nearest_at_ramp()
	if near != 0:
		var why := Shed.check(me, {"a": "recovery_winch", "bike": near})
		var verb := "push %s up on the dolly" if Recovery.on_dolly(near) else "winch %s up the ramp"
		return [("{interact}: " + verb % Shed.bikes[near]["name"]) if why == "" else why, {"a": "recovery_winch", "bike": near} if why == "" else {}]
	for id in Recovery.loads():
		if Recovery.on_bed(int(id)):
			var why2 := Shed.check(me, {"a": "recovery_unload", "bike": int(id)})
			if why2 == "":
				return ["{interact}: let %s down the ramp" % Shed.bikes[int(id)]["name"], {"a": "recovery_unload", "bike": int(id)}]
			return [why2, {}]
	if not bool(Recovery.car()["ramp"]):
		return ["Lower the ramp, then wheel a bike to its foot to winch it up.", {}]
	return ["Wheel a bike to the foot of the ramp, facing up it, to winch it on.", {}]


## The bike standing nearest the foot of the parked trailer's ramp, or 0.
func nearest_at_ramp() -> int:
	var inv := Recovery.trailer_xf().affine_inverse()
	var best := 0
	var best_d := Recovery.REACH + 1.0
	for id in Shed.bikes:
		if Recovery.loads().has(id) or int(Shed.bikes[id]["rider"]) != 0:
			continue
		var at: Vector3 = inv * (Shed.bikes[id]["xf"] as Transform3D).origin
		if at.z < Trailer.ramp_foot_z() - 0.5 or absf(at.x) > 2.0:
			continue
		var d := absf(at.z - Trailer.start_z()) + absf(at.x) * 0.5
		if d < best_d:
			best_d = d
			best = int(id)
	return best


## What F on the dolly tray does now, [prompt, action].
func _dolly_prompt() -> Array:
	var d := Recovery.dolly()
	var me := Shed.me()
	match str(d["at"]):
		"trailer":
			var target := _seized_near(30.0)
			var a := {"a": "recovery_dolly_off", "bike": target}
			var why := Shed.check(me, a)
			if why != "":
				return [why, {}]
			return ["{interact}: carry it over to %s" % Shed.bikes[target]["name"] if target != 0 else "{interact}: take it off the side rail", a]
		"ground":
			var near := 0
			var best := Recovery.DOLLY_REACH
			for id in Shed.bikes:
				var dd: float = (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to((d["xf"] as Transform3D).origin)
				if dd < best and not Recovery.loads().has(id):
					best = dd
					near = int(id)
			if near != 0:
				var a2 := {"a": "recovery_dolly_load", "bike": near}
				var why2 := Shed.check(me, a2)
				return [("{interact}: get %s up on the dolly" % Shed.bikes[near]["name"]) if why2 == "" else why2, a2 if why2 == "" else {}]
			var why3 := Shed.check(me, {"a": "recovery_dolly_stow"})
			return ["{interact}: hang it back on the trailer's side rail" if why3 == "" else why3, {"a": "recovery_dolly_stow"} if why3 == "" else {}]
		"bike":
			var why4 := Shed.check(me, {"a": "recovery_dolly_unload"})
			return ["{interact}: lift the bike off the dolly" if why4 == "" else why4, {"a": "recovery_dolly_unload"} if why4 == "" else {}]
	return ["It's on the trailer with the bike.", {}]


## A recovery bike that won't roll within `reach` metres of the trailer, or 0.
func _seized_near(reach: float) -> int:
	var t := Recovery.trailer_xf().origin
	for jid in Recovery.jobs():
		var id := int(Recovery.jobs()[jid]["bike"])
		if Shed.bikes.has(id) and Recovery.seized(id) and (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(t) < reach:
			return id
	return 0


# ---------------------------------------------------------------------------- driving

## You're at the wheel: the truck and trailer come alive under you.
func start_driving() -> void:
	if driving or car == null:
		return
	driving = true
	_entered_at = Time.get_ticks_msec()
	var c := Recovery.car()
	car.freeze = false
	trailer.freeze = false
	car.place(c["xf"])
	trailer.place(c["trailer_xf"])
	trailer.attach()
	# You get in with the engine off and start it on the key, as on a bike.
	car.engine_on = false
	car.rpm = 0.0
	car.controls_enabled = true
	trailer.load_sim.clear()
	for id in Recovery.loads():
		var l: Dictionary = Recovery.loads()[id]
		trailer.load_sim[id] = {"z": float(l.get("z", 0.0)), "v": 0.0, "straps": Recovery.straps_on(int(id)),
			"secure": Recovery.secure(int(id)), "sent": float(l.get("z", 0.0))}
	audio = EngineSound.new()
	car.add_child(audio)
	audio.setup_spec(Car.engine_spec())
	audio.exhaust_at.position = Vector3(0.6, 0.35, 2.6)
	audio.engine_at.position = Vector3(0.0, 0.9, -1.8)
	main.camera.target = car
	main.camera.set_mode(_view)
	main.camera.snap()
	main.camera.current = true
	main._set_walker_active(false)
	main.hud.car = car
	if not car.engine_changed.is_connected(_on_engine_changed):
		car.engine_changed.connect(_on_engine_changed)
		car.gear_changed.connect(_on_gear_changed)
	Sfx.play_at("door", car.global_position, -12.0)


func _on_engine_changed(running: bool) -> void:
	if driving and running:
		main.hud.flash("Engine running", 1.2)


## Into reverse: say which pedal backs it up, since that depends on how you got there.
func _on_gear_changed(g: int) -> void:
	if not driving or g >= 0:
		return
	if car.pedals_swapped():
		main.hud.flash("Reverse: hold {front_brake} to back up, {throttle} to stop", 2.0)
	else:
		main.hud.flash("Reverse: {throttle} backs up, {front_brake} brakes, {shift_up} for drive", 2.0)


## Out of the truck: it's parked where it stands (the host is told, unless `tell` is off), and
## you're stood by the driver's door.
func stop_driving(tell := true) -> void:
	if not driving:
		return
	driving = false
	main.hud.car = null
	if tell:
		Shed.request({"a": "recovery_exit", "xf": _settled(car.global_transform), "trailer_xf": _settled(trailer.global_transform)})
	trailer.unhitch()
	car.freeze = true
	trailer.freeze = true
	_parked_sig = ""
	if is_instance_valid(audio):
		audio.queue_free()
	audio = null
	if main.walker:
		var door := car.global_transform * Vector3(1.7, 0.0, -0.6)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(door + Vector3.UP * 2.0, door + Vector3.DOWN * 3.0, 1))
		if hit:
			door = hit["position"]
		var fwd := -car.global_basis.z
		main.walker.place(Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z) + PI * 0.5), door))
		main._set_walker_active(true)
		main.walker.camera.current = true


## Stood level on its wheels as it is, for parking: no roll or pitch left in it.
func _settled(xf: Transform3D) -> Transform3D:
	var fwd := -xf.basis.z
	var flat := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	return Transform3D(flat, xf.origin)


## The driving keys. True when the event was the truck's.
func drive_input(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		if Time.get_ticks_msec() - _entered_at < 600:
			return true
		if absf(car.speed) > EXIT_SPEED:
			main.hud.flash("Stop first, then get out.", 1.5, true)
			return true
		stop_driving()
		return true
	if event.is_action_pressed("camera"):
		_view = ChaseCamera.Mode.HELMET if main.camera.mode == ChaseCamera.Mode.CHASE else ChaseCamera.Mode.CHASE
		main.camera.set_mode(_view)
		return true
	if event.is_action_pressed("ignition"):
		_ignition()
		return true
	if event.is_action_pressed("headlight"):
		main.hud.flash("Headlamps: %s" % car.cycle_beam(), 1.2)
		return true
	if event.is_action_pressed("shift_up"):
		car.shift_up()
		return true
	if event.is_action_pressed("shift_down"):
		car.shift_down()
		return true
	if event.is_action_pressed("toggle_auto_shift"):
		Settings.auto_shift = not Settings.auto_shift
		main.hud.flash("Gearbox: %s" % ("automatic" if Settings.auto_shift else "manual (shift up and down yourself)"), 1.5)
		return true
	if event.is_action_pressed("respawn"):
		_right_the_truck()
		return true
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
		var rel: Vector2 = event.relative
		main.camera.add_orbit(-rel.x * ChaseCamera.MOUSE_ORBIT, rel.y * ChaseCamera.MOUSE_ORBIT)
		return true
	return false


## Starts or stops the engine on the key, as on the bikes.
func _ignition() -> void:
	var at := car.global_transform * Car.EYE
	if car.engine_on or car.is_starting():
		car.stop_engine()
		main.hud.flash("Engine off", 1.2)
		Sfx.play_at("switch", at, -6.0)
		return
	car.start_engine()
	Sfx.play_at("switch", at, -10.0)   # the starter itself is the engine sound's


## Stuck on its roof or its side: back on its wheels where it is, trailer and all.
func _right_the_truck() -> void:
	var fwd := -car.global_basis.z
	var at := car.global_position + Vector3.UP * 0.5
	trailer.unhitch()
	car.place(Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at))
	trailer.hitch_to(car)


## Each physics tick at the wheel: the controls (when `active`), the sound, and the map's edge.
func drive_physics(_delta: float, active: bool) -> void:
	if not driving:
		return
	if active:
		var stick := Controls.stick()
		car.throttle = maxf(Input.get_action_strength("throttle"), Controls.trigger(true))
		car.brake = maxf(Input.get_action_strength("front_brake"), Controls.trigger(false))
		car.handbrake = Input.get_action_strength("rear_brake")
		car.steer_input = clampf(Input.get_axis("lean_left", "lean_right") + stick.x, -1.0, 1.0)
		var look := Controls.stick(true)
		if look != Vector2.ZERO:
			main.camera.add_orbit(-look.x * ChaseCamera.STICK_ORBIT * _delta, look.y * ChaseCamera.STICK_ORBIT * _delta)
	else:
		car.throttle = 0.0
		car.brake = 1.0
		car.steer_input = 0.0
	car.auto_shift = Settings.auto_shift
	main.camera.recentre = Settings.camera_recentre
	if audio:
		audio.rpm = car.rpm
		audio.gear = maxi(car.gear, 1)
		audio.throttle = car.sound_load()
		audio.running = car.engine_on
		audio.cranking = car.is_starting()
		audio.speed = car.speed
		audio.view = "rider" if main.camera.mode == ChaseCamera.Mode.HELMET else "chase"
	if active and Input.is_action_just_pressed("horn"):
		Sfx.play_at("horn_disc", car.global_position, -2.0)
	var p := car.global_position
	if p.y < main.world.terrain_height(p.x, p.z) - 15.0 or absf(p.x) > World.MAP_HALF - 1.0 or absf(p.z) > World.MAP_HALF - 1.0:
		trailer.unhitch()
		car.place(Recovery.PARK)
		trailer.hitch_to(car)
		main.hud.flash("Lost the truck off the map: it's back in the yard.", 3.0, true)


## [2, truck..., trailer...] for the network while you drive.
func net_state() -> PackedFloat32Array:
	var s := PackedFloat32Array([2.0])
	s.append_array(car.get_net_state())
	s.append_array(trailer.get_net_state())
	return s


func _on_load_moved(bike_id: int, z: float) -> void:
	if driving:
		Shed.request({"a": "recovery_slide", "bike": bike_id, "z": z})


## A loose bike has gone over the side of the bed: down on the road beside the trailer.
func _on_load_fell(bike_id: int, side: float, _speed: float) -> void:
	if not driving or not Recovery.loads().has(bike_id):
		return
	var l: Dictionary = Recovery.loads()[bike_id]
	var local := Trailer.load_transform(int(l["slot"]), Trailer.s_end(), float(l.get("z", 0.0)))
	local.origin.x = side * (Trailer.BED_HALF_W + 0.9)
	var at := trailer.global_transform * local.origin
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1))
	if hit:
		at = hit["position"]
	var fwd := -trailer.global_basis.z
	Shed.request({"a": "recovery_fall", "bike": bike_id, "xf": Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at)})
	Sfx.play_at("scrap", at, 0.0)
	if main.hud:
		main.hud.flash("%s came off the trailer!" % str(Shed.bikes.get(bike_id, {}).get("name", "A bike")), 3.0, true)


## Keeps the trailer's idea of each bike's straps up to date as they're done up or undone.
func _on_shed_loads() -> void:
	if not driving or trailer == null:
		return
	for id in trailer.load_sim.keys():
		if not Recovery.loads().has(id):
			trailer.load_sim.erase(id)
		else:
			trailer.load_sim[id]["straps"] = Recovery.straps_on(int(id))
			trailer.load_sim[id]["secure"] = Recovery.secure(int(id))


# ---------------------------------------------------------------------------- other players' truck

## Another player's network state while they drive: [2, truck..., trailer...].
func remote_state(peer: int, s: PackedFloat32Array) -> void:
	if not _remote.has(peer):
		_remote[peer] = []
	var list: Array = _remote[peer]
	list.append({"t": Time.get_ticks_msec() / 1000.0, "s": s})
	while list.size() > 12:
		list.pop_front()


func _follow_remote(peer: int) -> void:
	var list: Array = _remote[peer]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(list[-1]["t"]) > 3.0:
		return   # stale: leave it where it was
	var render_t := now - REMOTE_DELAY
	var a: Dictionary = list[0]
	var b: Dictionary = list[-1]
	for i in range(list.size() - 1):
		if float(list[i]["t"]) <= render_t and float(list[i + 1]["t"]) >= render_t:
			a = list[i]
			b = list[i + 1]
			break
	var span := float(b["t"]) - float(a["t"])
	var f := 1.0 if span <= 0.0 else clampf((render_t - float(a["t"])) / span, 0.0, 1.0)
	var sa: PackedFloat32Array = a["s"]
	var sb: PackedFloat32Array = b["s"]
	car.set_net_state(sb, 1)
	trailer.set_net_state(sb, 1 + Car.NET_SIZE)
	if sa.size() == sb.size() and f < 1.0:
		var ca := car.global_transform
		car.set_net_state(sa, 1)
		car.global_transform = car.global_transform.interpolate_with(ca, f)
		var ta := trailer.global_transform
		trailer.set_net_state(sa, 1 + Car.NET_SIZE)
		trailer.global_transform = trailer.global_transform.interpolate_with(ta, f)
	_parked_sig = ""
	if _remote_audio == null or not is_instance_valid(_remote_audio):
		_remote_audio = EngineSound.new()
		car.add_child(_remote_audio)
		_remote_audio.setup_spec(Car.engine_spec())
		_remote_audio.set_distant_filter(true)
	_remote_audio.rpm = car.rpm
	_remote_audio.running = car.engine_on
	_remote_audio.cranking = car.is_starting()
	_remote_audio.throttle = sb[1 + 12]
	_remote_audio.gear = maxi(car.gear, 1)
	_remote_audio.speed = Vector3(sb[1 + 7], sb[1 + 8], sb[1 + 9]).length()


## Where another player's truck is (for saving and the TVs), or null.
func remote_transform(peer: int):
	if Recovery.driver() == peer and car:
		return car.global_transform
	return null
