class_name AdventureTrip
extends Node
## This player's side of an adventure ride (see Adventure for the shared state): when the host
## starts one, a fade to black, the town put to sleep (hidden, its processing and collision off),
## the adventure's road (AdventureWorld) loaded in its place and you on a bike at the start (the
## one you were on or by, or another the host finds you); when it ends, back to the shed with
## the bike parked in its bay, everything it went through on the road kept.
##
## Out there it keeps your bike, the camera, your walker and the other players in step with the
## world's floating origin, puts a bike that's left the road back on it, tells the host when you
## reach the destination, runs the day faster (Adventure.day_rate) and shows how far you've come.

static var current: AdventureTrip
## Skips the fades (the tests).
static var instant := false

var main: Node
## The adventure's world while you're on one, else null.
var world: AdventureWorld
var trip_id := 0
var _busy := false
var _arrive_sent := false
var _arrive_timer := 0.0
var _hidden: Array = []      # [node, was visible, process mode] of the town put to sleep
var _hud: Label
var _hud_timer := 0.0
var _put_back_at := 0        # ticks: when the last "back on the road" happened


func _ready() -> void:
	name = "AdventureTrip"
	current = self
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Label.new()
	_hud.visible = false
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.position.y = 8.0
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)


func _exit_tree() -> void:
	if current == self:
		current = null


## Whether you're out on an adventure now (its world loaded).
func on_trip() -> bool:
	return world != null


## Called whenever the shed changes: loads the adventure the host started, or brings you home
## from one that's over.
func sync() -> void:
	if _busy or not main.in_session:
		return
	var id := int(Shed.adventure.get("id", 0))
	if id != 0 and id != trip_id:
		if trip_id != 0:
			reset()
		enter()
	elif trip_id != 0 and id != trip_id:
		leave()


## Into the adventure in Shed.adventure.
func enter() -> void:
	var info := Shed.adventure.duplicate(true)
	trip_id = int(info["id"])
	_busy = true
	_arrive_sent = false
	_arrive_timer = 0.0
	# The bike you're on, or the one you're standing by in the shed: the one you'd like to take.
	var preferred: int = main.riding_id if main.bike else _nearest_bike()
	if not instant:
		await main._fade_to(1.0)
	if main.recovery.driving:
		main.recovery.stop_driving(false)
	if main.geometry.active:
		main.geometry.close()
	world = AdventureWorld.new()
	world.setup(int(info["seed"]), float(info["km"]), str(info.get("theme", "varied")))
	world.focus = focus_points
	main.world.add_child(world)
	world.origin_shifted.connect(_on_shift)
	_sleep_town(true)
	world.preload_range(0.0, 420.0)
	var xf := start_xf()
	if main.bike:
		main.bike.place(xf.origin, xf.basis.get_euler().y)
		main.camera.snap()
	elif main.walker:
		var side := world.transform_at(30.0, -world.route.width_at_s(30.0) * 0.5 - 1.5)
		main.walker.place(side)
	Daylight.adventure_rate = Adventure.day_rate()
	Shed.request({"a": "adventure_join", "bike": preferred})
	main.hud.flash("Adventure ride: %d km of varied roads. Fuel stations are signed along the way." % roundi(float(info["km"])), 5.0)
	_busy = false
	if not instant:
		await main._fade_to(0.0)


## Back to the shed from the adventure: the bike you're on parked in its bay (fuel, wear and
## muck as the road left them), you on foot at the shed door.
func leave() -> void:
	_busy = true
	if not instant:
		await main._fade_to(1.0)
	if main.bike != null:
		if main.bike.is_crashed:
			main.bike.respawn()
		main._send_ride_stats()
		var id: int = main.riding_id
		Shed.request({"a": "dismount", "bike": id, "xf": main.garage_spot(id)})
		main._stop_riding()
	_unload()
	if main.walker:
		main.walker.place(Workshop.walker_spawn(Net.local_slot()))
	main.camera.snap()
	main.hud.flash("Back at the shed.", 3.0)
	_busy = false
	if not instant:
		await main._fade_to(0.0)


## Drops the adventure at once, as the session ends (nothing is asked of the shed).
func reset() -> void:
	_unload()
	_busy = false


func _unload() -> void:
	if world:
		world.queue_free()
		world = null
	trip_id = 0
	_sleep_town(false)
	Daylight.adventure_rate = 0.0
	_hud.visible = false


## Hides the town and stops it (processing and collision) while you're away on the adventure,
## or brings it all back. The sky, sun, weather and lighting stay, and so do you, the camera
## and the other players.
func _sleep_town(on: bool) -> void:
	if not on:
		for entry in _hidden:
			var node: Node = entry[0]
			if is_instance_valid(node):
				node.process_mode = entry[2]
				if node is Node3D:
					(node as Node3D).visible = entry[1]
		_hidden.clear()
		return
	for child in main.world.get_children():
		if child is WorldEnvironment or child is DirectionalLight3D or child is Daylight or child is Lighting \
				or child is Weather or child is Camera3D or child is Walker or child is RemotePlayer or child is Bike \
				or child is AdventureWorld or child is RigidBody3D:
			continue
		_hidden.append([child, child.visible if child is Node3D else true, child.process_mode])
		child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is Node3D:
			(child as Node3D).visible = false


## Where you start: your place on the grid, by your place in the crew.
func start_xf() -> Transform3D:
	var ids := Shed.crew.keys()
	ids.sort()
	return world.start_xf(maxi(0, ids.find(Shed.me())))


## The nearest bike to you in the shed with nobody on it (within a few metres), or 0.
func _nearest_bike() -> int:
	if main.walker == null:
		return 0
	var best := 0
	var best_d := 6.0
	for id in Shed.bikes:
		if int(Shed.bikes[id].get("rider", 0)) != 0:
			continue
		var d := (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(main.walker.global_position)
		if d < best_d:
			best_d = d
			best = int(id)
	return best


## Your position first, then everyone else's: where the road has to be.
func focus_points() -> Array:
	var out := []
	if main.bike:
		out.append(main.bike.global_position)
	elif main.walker:
		out.append(main.walker.global_position)
	else:
		out.append(main.camera.global_position)
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp):
			out.append(rp.world_position())
	return out


## The world's origin moved by `d`: your bike, the camera, your walker, the other players and the
## skid marks move with it.
func _on_shift(d: Vector3) -> void:
	if main.bike:
		main.bike.shift_origin(d)
	main.camera.shift_origin(d)
	if main.walker:
		main.walker.global_position -= d
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp):
			rp.shift_origin(d)
	var marks := SkidMarks.shared(get_tree())
	if marks and marks.multimesh:
		var mm := marks.multimesh
		for k in mm.instance_count:
			var t := mm.get_instance_transform(k)
			t.origin -= d
			mm.set_instance_transform(k, t)


# ---------------------------------------------------------------------------- network

## Your snapshot for the network, with your origin on it while you're out here.
func tag_state(state: PackedFloat32Array) -> PackedFloat32Array:
	return world.tag_state(state) if world and not state.is_empty() else state


## Someone's snapshot put into your frame.
func untag_state(state: PackedFloat32Array) -> PackedFloat32Array:
	if world:
		return world.untag_state(state)
	return AdventureWorld.untag(state, Vector3.ZERO) if not state.is_empty() and state[state.size() - 1] == AdventureWorld.NET_TAG else state


# ---------------------------------------------------------------------------- out on the road

func _physics_process(delta: float) -> void:
	if world == null or _busy:
		return
	var pt := Perf.t0()
	var p: Vector3 = focus_points()[0]
	world.follow(p)
	var hit := world.locate_local(p, "own")
	if main.bike and not hit.is_empty():
		_keep_on_road(hit)
	var s := float(hit.get("s", 0.0))
	if not _arrive_sent and not hit.is_empty() and s >= world.route.length - 12.0 and absf(float(hit["lat"])) < 30.0:
		_arrive_sent = true
		Shed.request({"a": "adventure_arrive"})
	# The host takes everyone home a few seconds after someone gets there.
	if Shed.is_authority() and int(Shed.adventure.get("arrived", 0)) != 0:
		_arrive_timer += delta
		if _arrive_timer >= Adventure.ARRIVE_WAIT:
			_arrive_timer = -1000.0
			Shed.request({"a": "adventure_end"})
	_hud_timer -= delta
	if _hud_timer <= 0.0 and not hit.is_empty():
		_hud_timer = 0.25
		_hud.text = hud_text(s)
		_hud.visible = true
	Perf.add("adventure_trip", pt)


## The line at the top of the screen: how far you've come, the road, and the next fuel.
func hud_text(s: float) -> String:
	var r := world.route
	var text := "Adventure  %.1f / %.0f km   %s, %s" % [s / 1000.0, r.length / 1000.0,
		AdventureSurface.NAMES.get(r.surface_at_s(s), "Road"), str(AdventureRoute.KIND_NAMES.get(r.kind_at_s(s), "")).to_lower()]
	for st in r.sites_of("fuel"):
		if float(st["s"]) > s - 30.0:
			text += "   Fuel in %.1f km" % maxf(0.0, (float(st["s"]) - s) / 1000.0)
			break
	return text


## A bike that's gone well off the road (or fallen through the land) is put back on it, facing
## the way the road goes.
func _keep_on_road(hit: Dictionary) -> void:
	var bike: Bike = main.bike
	var s: float = hit["s"]
	var road_h := world.route.height_at_s(s)
	var lost := absf(float(hit["lat"])) > 75.0 or bike.global_position.y < road_h - 25.0 or not world.has_ground(s)
	if lost and Time.get_ticks_msec() - _put_back_at > 1500:
		_put_back_at = Time.get_ticks_msec()
		var xf := world.transform_at(s, -world.route.width_at_s(s) * 0.25)
		bike.place(xf.origin, world.heading_at(s))
		main.camera.snap()
		main.hud.flash("Back on the road.", 2.0, true)


## Moves your bike `metres` along the road (the Debug tab, for trying things out).
func jump(metres: float) -> void:
	if world == null:
		return
	var p: Vector3 = focus_points()[0]
	var s := clampf(world.distance_of(p, "own") + metres, 0.0, world.route.total - 20.0)
	world.preload_range(s - 100.0, s + 300.0)
	var xf := world.transform_at(s, -world.route.width_at_s(s) * 0.25)
	if main.bike:
		var v: Vector3 = main.bike.linear_velocity
		main.bike.place(xf.origin, world.heading_at(s))
		main.bike.linear_velocity = xf.basis * Vector3(0, 0, -v.length())
	elif main.walker:
		main.walker.place(xf)
	main.camera.snap()


## Why "Back to the garage" can't be used out here ("" if it can).
func home_reason() -> String:
	return "You're out on an adventure: %s." % ("end it from this menu to bring everyone home" if Shed.is_authority() else "the host ends it")
