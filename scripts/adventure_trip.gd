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
##
## Once anyone reaches the destination, everyone's brought to it (parked by the set piece, see
## AdventureDest) for the arrival moment: the camera pulls back from the crew to take in what
## they came for, a title card, and the group photo (a flash, then the photo; it's kept in this
## machine's album and hangs on the shed wall). Then it's theirs to look round until the host
## picks Ride home. It also holds the magazine (AdventureMag), read in the shed.
##
## It keeps the trip computer for the whole ride (TripComputer, on the sat nav's trip page and in
## the diary's stats) and this player's camera (AdventurePhotos); at the destination, and again at
## Ride home, the Adventure Diary is put together (AdventureDiary) and, back in the shed, opened
## in its book (DiaryBook), as it can be again from the magazine or the photo on the shed wall.

static var current: AdventureTrip
## Skips the fades (the tests).
static var instant := false
## How long the arrival moment runs (s), the camera's pull-back, and when the photo's taken.
const MOMENT := 10.0
const PULL_BACK := 7.0
const PHOTO_AT := 4.5
## Ground steeper than this (its normal's height) is too steep to stand on (the walker's floor angle).
const STAND_SLOPE := 0.72
## Falling faster than this on foot (m/s, about 30 m of drop) is through the land, not down a bank.
const FALL_SPEED := 24.0

var main: Node
## The adventure's world while you're on one, else null.
var world: AdventureWorld
var trip_id := 0
var _busy := false
var _arrive_sent := false
## The arrival moment: seconds into it, or -1 while it isn't playing; done once it's begun.
var moment_t := -1.0
var moment_done := false
var _moment_cam: Camera3D
var _card: Control           # the title card and the photo
var _card_title: Label
var _card_sub: Label
var _card_flash: ColorRect
var _polaroid: PanelContainer
var _polaroid_pic: TextureRect
var _polaroid_caption: Label
var _started_at := 0         # ticks when this player set off, for the title card's time
## The magazine on the workbench, made the first time it's read.
var magazine: AdventureMag
## The map where the crew plans a journey across a real region, made the first time it is opened.
var journey_map: JourneyMap
var _hidden: Array = []      # [node, was visible, process mode] of the town put to sleep
var _hud: Label
var _crew: Label             # how far ahead or behind the rest of the crew are (see friends)
var _wrong: Label            # facing back the way you came (see wrong_way)
var _hud_timer := 0.0
var _put_back_at := 0        # ticks: when the last "back on the road" happened
## Hunger, thirst and tiredness: the meters, their effects, and sitting, eating and sleeping.
var needs: AdventureNeedsView
var _fork_panel: PanelContainer   # the choice coming up at a fork (see AdventureForks)
var _fork_label: Label
var _fork_timer := 0.0
var _fork_due := {}          # forks we've told the host we're nearly at
var _fork_choice := {}       # what the panel shows now (AdventureForks.choice)
var _map: AdventureMap       # the paper map, made the first time it's opened
## The police on the road (see AdventurePolice), while you're out here.
var police: AdventurePolice
var _nav_cache: Satnav.AdventureNav   # for the wrong-way warning on the HUD (see wrong_way)
## The trip computer for the whole ride, from setting off (see Satnav.computer).
var computer := TripComputer.new()
## This player's camera and their side of the Adventure Diary, and the book it's read in.
var photos: AdventurePhotos
var diary: DiaryBook


func _ready() -> void:
	name = "AdventureTrip"
	current = self
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_fork_panel = PanelContainer.new()
	_fork_panel.visible = false
	_fork_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.08, 0.78)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_fork_panel.add_theme_stylebox_override("panel", style)
	_fork_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_fork_panel.position = Vector2(16, 44)
	_fork_label = Label.new()
	_fork_label.add_theme_font_size_override("font_size", 16)
	_fork_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fork_panel.add_child(_fork_label)
	layer.add_child(_fork_panel)
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
	# The rest of the crew, under the money and XP in the top right (clear of the messages in the
	# middle), and the wrong-way warning under the messages.
	_crew = Label.new()
	_crew.visible = false
	_crew.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_crew.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_crew.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_crew.offset_right = -20.0
	_crew.offset_top = 58.0
	_crew.add_theme_font_size_override("font_size", 17)
	_crew.add_theme_color_override("font_color", SatnavScreen.FRIEND)
	_crew.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_crew.add_theme_constant_override("outline_size", 6)
	_crew.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_crew)
	_wrong = Label.new()
	_wrong.visible = false
	_wrong.text = "WRONG WAY: TURN AROUND"
	_wrong.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wrong.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wrong.offset_top = 84.0
	_wrong.add_theme_font_size_override("font_size", 28)
	_wrong.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	_wrong.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_wrong.add_theme_constant_override("outline_size", 8)
	_wrong.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_wrong)
	needs = AdventureNeedsView.new()
	needs.trip = self
	add_child(needs)
	_make_card(layer)
	photos = AdventurePhotos.new()
	photos.trip = self
	add_child(photos)


func _exit_tree() -> void:
	if current == self:
		current = null
	AdventureMag.wait_all()   # the magazine's route facts still being worked out


## Whether you're out on an adventure now (its world loaded).
func on_trip() -> bool:
	return world != null


## Whether the police are pulling you over (your throttle's cut and you brake, see Main).
func police_hold() -> bool:
	return police != null and is_instance_valid(police) and police.holding()


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
	elif world != null:
		world.apply_picks_soon(AdventureForks.picks())   # (put together off the main thread: _on_picks_taken)
	if world != null and trip_id == id and int(Shed.adventure.get("arrived", 0)) != 0 and not moment_done:
		arrive_moment()


## A way picked at a fork is in the world now: say so straight away.
func _on_picks_taken() -> void:
	_fork_timer = 0.0
	if _map and _map.visible:
		_map.refresh()


## Why this game can't ride the real road in adventure `info` ("" if it can, or the road is made up): it
## doesn't have the road, or its copy differs from the host's, and the ride would not be the same road.
static func real_mismatch(info: Dictionary) -> String:
	if info.get("plan") is Dictionary:
		# A journey the crew planned on the map: this game plans it too, and must get the host's road.
		var plan: Dictionary = info["plan"]
		var res := AdventurePlans.result(plan, true)
		if not bool(res.get("ok", false)):
			return str(res.get("error", "This game can't plan that journey."))
		if str(info.get("real_hash", "")) != (res["pack"] as RealPack).hash:
			return "Your game planned a different road from the host's: update the game to join."
		return ""
	var id := str(info.get("real", ""))
	if id == "":
		return ""
	var pack := RealPack.get_pack(id)
	if pack == null:
		return "This ride is along a real road your game doesn't have (%s): update the game to join." % id
	if str(info.get("real_hash", "")) != pack.hash:
		return "Your copy of the %s road isn't the host's: update the game to join." % pack.title
	return ""


## Into the adventure in Shed.adventure.
func enter() -> void:
	var info := Shed.adventure.duplicate(true)
	trip_id = int(info["id"])
	var why := real_mismatch(info)
	if why != "":
		_busy = false
		Shed.feedback.emit(why, false)   # (trip_id stays, so this isn't tried again every frame)
		return
	_busy = true
	_arrive_sent = false
	moment_done = false
	_started_at = Time.get_ticks_msec()
	close_magazine()
	# The bike you're on, or the one you're standing by in the shed: the one you'd like to take.
	var preferred: int = main.riding_id if main.bike else _nearest_bike()
	if not instant:
		await main._fade_to(1.0)
	if main.recovery.driving:
		main.recovery.stop_driving(false)
	if main.geometry.active:
		main.geometry.close()
	world = AdventureWorld.new()
	world.setup(int(info["seed"]), float(info["km"]), str(info.get("theme", "varied")), str(info.get("dest", "")), str(info.get("real", "")))
	world.apply_picks(AdventureForks.picks())   # a ride picked up again: the ways already taken
	_fork_due = {}
	world.focus = focus_points
	main.world.add_child(world)
	world.origin_shifted.connect(_on_shift)
	world.picks_taken.connect(_on_picks_taken)
	world.add_child(RoadsideView.new())   # bikes stood at the roadside, and tow straps (see Roadside)
	world.add_child(AdventureTraffic.new())   # cars, vans, lorries and buses both ways
	police = AdventurePolice.new()
	police.trip = self
	police.world = world
	world.add_child(police)
	_sleep_town(true)
	var from := maxf(0.0, start_s() - 120.0)
	world.preload_range(from, from + 420.0)
	var xf := start_xf()
	if main.bike:
		main.bike.place(xf.origin, xf.basis.get_euler().y)
		main.camera.snap()
	elif main.walker:
		var s0 := maxf(30.0, start_s())
		var side := world.transform_at(s0, -world.route.width_at_s(s0) * 0.5 - 1.5)
		main.walker.place(side)
	Daylight.adventure_rate = Adventure.day_rate()
	apply_theme(world.route.theme, int(info["seed"]), start_s() <= 0.0)
	Shed.request({"a": "adventure_join", "bike": preferred})
	computer.reset()
	photos.begin()   # (a ride carried on picks its diary and trip computer up again)
	if start_s() > 0.0:
		main.hud.flash("Carrying on the adventure: %.1f of %d km done. Morning, and back on the road." % [start_s() / 1000.0, roundi(float(info["km"]))], 5.0)
	else:
		main.hud.flash("%s: %d km of %s to %s. Fuel stations are signed along the way; at a fork the crew votes for the way. {paper_map} for the map when stopped." % [
			str(info.get("title", "Adventure ride")), roundi(float(info["km"])), AdventureTheme.roads_of(world.route.theme), AdventureDest.name_of(str(info.get("dest", ""))).trim_prefix("the ")], 5.0)
	_busy = false
	if not instant:
		await main._fade_to(0.0)


## The theme's sky and weather (AdventureTheme): the sky and haze tinted, the weather changing
## by the theme's odds, and on a fresh start (`fresh`; not carrying on after a night) the time of
## day it sets off at and its first weather, from the seed. The host's clock and weather are
## everyone's (Daylight, Weather), so on a client only the tint and odds are its own.
func apply_theme(theme: String, seed: int, fresh: bool) -> void:
	Daylight.set_tint(AdventureTheme.get_value(theme, "sky", {}))
	Weather.odds = (AdventureTheme.get_value(theme, "weather", {}) as Dictionary).duplicate()
	if not fresh:
		return
	var hour := float(AdventureTheme.get_value(theme, "start_hour", -1.0))
	if hour >= 0.0 and Daylight.current and not Daylight.set_by_host():
		Daylight.current.set_time(hour)
	if Weather.current and not Weather.set_by_host() and not Weather.STATES.has(Settings.weather):
		var pick := AdventureTheme.weather_pick(theme, float(absi(hash([seed, "weather"])) % 1000) / 1000.0)
		if pick != "":
			Weather.current.change_to(pick, true)


## Back to the shed from the adventure: the bike you're on parked in its bay (fuel, wear and
## muck as the road left them), you on foot at the shed door.
func leave() -> void:
	_busy = true
	# The diary put together while the road's still here, to open back at the shed.
	var kept := photos.diary_id if photos.finish() else ""
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
	main.workshop.sync_state()   # (left as it was while you were away: see Main._on_shed_changed)
	if main.contracts_view:
		main.contracts_view.sync_state()   # and the customers who came in meanwhile
	if main.walker:
		main.walker.place(Workshop.walker_spawn(Net.local_slot()))
	main.camera.snap()
	main.hud.flash("Back at the shed.", 3.0)
	_busy = false
	if not instant:
		await main._fade_to(0.0)
	if kept != "" and main.in_session:
		open_diary(kept)


## Drops the adventure at once, as the session ends (nothing is asked of the shed).
func reset() -> void:
	_unload()
	_busy = false


func _unload() -> void:
	if needs:
		needs.reset()
	if photos:
		photos.end()
	close_map()
	_end_moment()
	moment_done = false
	if world:
		# Gone at the end of the frame: until then it mustn't follow you home and shift the
		# origin (which would move you, at the shed, by the shift).
		world.focus = Callable()
		world.origin_shifted.disconnect(_on_shift)
		world.queue_free()
		world = null
	police = null
	trip_id = 0
	_sleep_town(false)
	Daylight.adventure_rate = 0.0
	Daylight.set_tint({})
	Weather.odds = {}
	_hud.visible = false
	_crew.visible = false
	_wrong.visible = false
	_fork_panel.visible = false


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


## Where you start: your place on the grid, by your place in the crew; carrying on an adventure
## put away overnight, at the side of the road where you slept (staggered a bike length apart).
func start_xf() -> Transform3D:
	var ids := Shed.crew.keys()
	ids.sort()
	var slot := maxi(0, ids.find(Shed.me()))
	var s := start_s()
	if s > 0.0:
		var at := clampf(s - 4.0 * float(slot), 20.0, world.route.length - 40.0)
		return world.transform_at(at, -world.route.width_at_s(at) * 0.25)
	return world.start_xf(slot)


## How far along the road you start (m): 0 from the start, else where you slept.
func start_s() -> float:
	return maxf(0.0, AdventureNeeds.resume_s(str(Shed.crew.get(Shed.me(), {}).get("name", ""))))


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
	if _moment_cam:
		_moment_cam.global_position -= d
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
	elif main.walker and not hit.is_empty():
		_keep_walker(hit)
	var s := float(hit.get("s", 0.0))
	if not _arrive_sent and not hit.is_empty() and s >= world.route.length - 12.0 and absf(float(hit["lat"])) < 30.0:
		_arrive_sent = true
		Shed.request({"a": "adventure_arrive"})
	if world == null:
		Perf.add("adventure_trip", pt)
		return   # the ride just ended
	if main.bike:
		computer.step(delta, main.bike.speed, main.bike.global_position.y, main.bike.fuel_litres, main.bike.surface)
	_hud_timer -= delta
	if _hud_timer <= 0.0 and not hit.is_empty():
		_hud_timer = 0.25
		_hud.text = hud_text(s)
		_hud.visible = true
		_crew.text = crew_text()
		_crew.visible = _crew.text != ""
		# On the bike, sat nav or not (one fitted says so on its screen too).
		_wrong.visible = main.bike != null and int(Shed.adventure.get("arrived", 0)) == 0 and not map_open() and not main.menu.visible and wrong_way()
	if not hit.is_empty():
		_forks(s, delta)
	if _map and _map.visible:
		if main.bike and absf(main.bike.speed) > 2.0:
			close_map()
		else:
			_map.tick(delta)
	Perf.add("adventure_trip", pt)


## The line at the top of the screen: how far you've come, the road, the way you're on through a
## fork, and the next fuel.
func hud_text(s: float) -> String:
	var r := world.route
	if int(Shed.adventure.get("arrived", 0)) != 0:
		return "At %s, %d km from the start.   %s" % [AdventureDest.name_of(str(Shed.adventure.get("dest", ""))), roundi(r.length / 1000.0),
			Controls.hint("Ride home from the {menu} menu when everyone's ready.") if Shed.is_authority() else "The host rides everyone home when you're ready."]
	var text := "Adventure  %.1f / %.0f km   %s, %s" % [s / 1000.0, r.length / 1000.0,
		AdventureSurface.NAMES.get(r.surface_at_s(s), "Road"), str(AdventureRoute.KIND_NAMES.get(r.kind_at_s(s), "")).to_lower()]
	var f := r.fork_at(s)
	if f >= 0:
		var way := r.way_of(f, int(r.choices.get(f, 0)))
		text += "   On %s %s, %.1f km to go on it" % [str(way["letter"]), str(way["name"]), (r.rejoin_s(f) - s) / 1000.0]
	for st in r.sites_of("fuel"):
		if float(st["s"]) > s - 30.0:
			text += "   Fuel in %.1f km" % maxf(0.0, (float(st["s"]) - s) / 1000.0)
			break
	return text


# ---------------------------------------------------------------------------- forks and the map

## Coming up to a fork at `s`: the choice on the HUD (with everyone's votes), and once anyone is
## LOCK_DIST from a fork still open, the host is told so the main road's taken by default.
func _forks(s: float, delta: float) -> void:
	var r := world.route
	var f := r.next_fork(s)
	if f >= 0 and not r.decided.has(f) and r.fork_s(f) - s < AdventureForks.LOCK_DIST and not _fork_due.has(f):
		_fork_due[f] = true
		Shed.request({"a": "adventure_fork_due", "fork": f})
	_fork_timer -= delta
	if _fork_timer > 0.0:
		return
	_fork_timer = 0.25
	_fork_choice = AdventureForks.choice(r, s)
	_fork_panel.visible = not _fork_choice.is_empty() and not map_open() and not (main.menu.visible if main and main.menu else false)
	if _fork_panel.visible:
		_fork_label.text = "\n".join(AdventureForks.choice_lines(_fork_choice, main.bike != null))
		_fork_panel.reset_size()


## Your vote for way `w` at the fork coming up (the host's is the pick).
func vote(w: int) -> void:
	if _fork_choice.is_empty() or int(_fork_choice["picked"]) >= 0 or w >= (_fork_choice["ways"] as Array).size():
		return
	Shed.request({"a": "adventure_vote", "fork": int(_fork_choice["fork"]), "way": w})
	_fork_timer = 0.0


## What the fork panel shows now ({} when there's no fork coming up).
func fork_choice() -> Dictionary:
	return _fork_choice


func _unhandled_input(event: InputEvent) -> void:
	if world == null or _busy or main == null or main.menu.visible:
		return
	if event.is_action_pressed("paper_map"):
		if map_open():
			close_map()
		else:
			var why := map_reason()
			if why == "":
				open_map()
			else:
				main.hud.flash(why, 1.5, true)
		get_viewport().set_input_as_handled()
		return
	# On the bike, 1 2 3 vote at a fork (on foot they're the tools: vote on the map there).
	if main.bike != null and not _fork_choice.is_empty():
		for k in 3:
			if event.is_action_pressed("tool_%d" % (k + 1)):
				vote(k)
				get_viewport().set_input_as_handled()
				return


## Why the paper map can't come out now ("" if it can): you have to stop first.
func map_reason() -> String:
	if world == null:
		return "The map's for adventure rides."
	if main.bike != null and absf(main.bike.speed) > 1.5:
		return "Stop first to get the map out."
	return ""


func map_open() -> bool:
	return _map != null and _map.visible


## Gets the paper map out: the whole route, where everyone is, the ways chosen, fuel and stops.
func open_map() -> void:
	if world == null:
		return
	if _map == null:
		_map = AdventureMap.new()
		_map.trip = self
		_hud.get_parent().add_child(_map)
		_map.closed.connect(close_map)
	_map.open()
	_fork_panel.visible = false
	main._capture_mouse(false)


func close_map() -> void:
	if _map == null or not _map.visible:
		return
	_map.visible = false
	if main and main.in_session and not main.menu.visible:
		main._capture_mouse(true)


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


## On foot, fallen through the land (or off the edge of it): falling as fast as only a long drop
## makes you, you're stood back at the roadside.
func _keep_walker(hit: Dictionary) -> void:
	var s: float = hit["s"]
	var w: Walker = main.walker
	if not w.is_on_floor() and w.velocity.y < -FALL_SPEED and Time.get_ticks_msec() - _put_back_at > 1500:
		_put_back_at = Time.get_ticks_msec()
		main.walker.place(world.transform_at(s, -world.route.width_at_s(s) * 0.5 + 0.5))   # on the road, at its edge
		main.hud.flash("Back by the road.", 2.0, true)


## Where you're stood getting off a bike stopped at local `ground` facing `heading`: on the ground
## beside it, found for itself. Across a mountainside that's well above (or below) the ground under
## the bike, and placed at the bike's height you'd be inside the hill and drop straight through
## it. Too steep to stand there (a cutting's bank), the nearest spot round it that isn't; none,
## the edge of the road beside it.
func step_off_spot(ground: Vector3, heading: float) -> Vector3:
	var right := Basis(Vector3.UP, heading) * Vector3.RIGHT
	var space := world.get_world_3d().direct_space_state
	for reach in [0.9, 1.6, 2.6]:
		# The left first (the side you get off), then on round.
		for k in 8:
			var at: Vector3 = ground - right.rotated(Vector3.UP, -TAU * k / 8.0) * reach
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0, 1)
			var foot := space.intersect_ray(q)
			if foot and (foot["normal"] as Vector3).y > STAND_SLOPE:
				return foot["position"]
	var hit := world.locate_local(ground)
	if hit.is_empty():
		return ground - right * 0.9
	var s := float(hit["s"])
	var edge := world.route.width_at_s(s) * 0.5 - 0.4
	return world.transform_at(s, clampf(float(hit["lat"]), -edge, edge)).origin


## Where a crash picks you up (Bike.respawn_at): off the road, back on it at the nearest point
## along it, on your side and facing on towards the destination (AdventureWorld.back_on_road);
## on the road, or not out on an adventure, null: where you lie, as in town.
func respawn_spot(p: Vector3):
	if world == null:
		return null
	var xf = world.back_on_road(p)
	if xf is Transform3D:
		main.hud.flash("Back on the road.", 2.0, true)
		main.camera.snap.call_deferred()   # once the bike's there
	return xf


## Whether you're facing back the way you came (the sat nav's warning, see Satnav.AdventureNav).
func wrong_way() -> bool:
	var me: Node3D = main.bike if main.bike else main.walker
	if world == null or me == null:
		return false
	var fwd := -me.global_transform.basis.z
	var g := _nav().satnav_guide(Vector2(me.global_position.x, me.global_position.z), Vector2(fwd.x, fwd.z).normalized())
	return bool(g.get("wrong_way", false))


func _nav() -> Satnav.AdventureNav:
	if _nav_cache == null or _nav_cache.world != world:
		_nav_cache = Satnav.AdventureNav.new(world)
	return _nav_cache


## The rest of the crew along the road: [{peer, name, ahead (m along the road from you, negative
## behind), at (local)}], nearest first. Along the road, not as the crow flies: a mate on the
## hairpin just above you is as far ahead as the road there says.
func friends() -> Array:
	var out := []
	if world == null or main == null:
		return out
	var mine := world.distance_of(focus_points()[0], "own")
	if mine < 0.0:
		return out
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if not is_instance_valid(rp):
			continue
		var at: Vector3 = rp.world_position()
		var s := world.distance_of(at, "friend_%d" % int(peer))
		if s < 0.0:
			continue
		out.append({"peer": int(peer), "name": str(Shed.crew.get(peer, {}).get("name", rp.player_name)), "ahead": s - mine, "at": at})
	out.sort_custom(func(a, b): return absf(float(a["ahead"])) < absf(float(b["ahead"])))
	return out


## The crew on the HUD, a line each, nearest first: "Dave 1.2 km ahead", "Sam 300 m behind"
## ("" riding alone).
func crew_text() -> String:
	var bits := PackedStringArray()
	for f in friends():
		bits.append(friend_text(str(f["name"]), float(f["ahead"])))
	return "\n".join(bits)


## "Dave 1.2 km ahead", "Sam 300 m behind", "Jo with you": a mate `ahead` metres on along the road.
static func friend_text(who: String, ahead: float) -> String:
	var d := absf(ahead)
	if d < 30.0:
		return "%s with you" % who
	var how := "ahead" if ahead > 0.0 else "behind"
	if Units.imperial():
		var mi := Units.distance_value(d / 1000.0)
		return "%s %.1f mi %s" % [who, mi, how] if mi >= 0.1 else "%s %d yd %s" % [who, roundi(d * 1.0936 / 10.0) * 10, how]
	if d < 1000.0:
		return "%s %d m %s" % [who, roundi(d / 10.0) * 10, how]
	return "%s %.1f km %s" % [who, d / 1000.0, how]


## Moves your bike `metres` along the road (the Debug tab, for trying things out).
func jump(metres: float) -> void:
	if world == null:
		return
	var p: Vector3 = focus_points()[0]
	# Never past a fork that isn't decided: there's no road there yet.
	var s := clampf(world.distance_of(p, "own") + metres, 0.0, minf(world.route.total, world.route.stream_end()) - 20.0)
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


# ---------------------------------------------------------------------------- arriving

## Everyone's at the destination (someone got there first): you're brought to it too, parked by
## the set piece with the rest of the crew, and the moment plays. The photo goes in your album.
func arrive_moment() -> void:
	moment_done = true
	var photo = Shed.adventure.get("photo", {})
	if photo is Dictionary and not photo.is_empty():
		AdventureDest.album_add(_my_name(), photo)
	var id := trip_id
	if not instant:
		_busy = true
		await main._fade_to(1.0)
		_busy = false
	if world == null or trip_id != id:
		return
	park_at_dest()
	_start_moment()
	if not instant:
		await main._fade_to(0.0)
	sync()   # anything that came in while the screen was dark


func _my_name() -> String:
	return str(Shed.crew.get(Shed.me(), {}).get("name", Settings.player_name))


## Puts you at your place by the set piece: on your bike, stopped, or on foot beside the road.
func park_at_dest() -> void:
	var ids := Shed.crew.keys()
	ids.sort()
	var slot := maxi(0, ids.find(Shed.me()))
	var ds := AdventureDest.dest_s(world)
	world.preload_range(ds - 160.0, ds + 160.0)
	var xf := AdventureDest.park_xf(world, slot)
	if main.bike:
		main.bike.place(xf.origin, xf.basis.get_euler().y)
		main.bike.linear_velocity = Vector3.ZERO
		main.bike.angular_velocity = Vector3.ZERO
		main.camera.snap()
	elif main.walker:
		main.walker.place(xf)


## Where the crew stands for the photo (local): the middle of the parked bikes, at head height.
func _group_point() -> Vector3:
	var a := AdventureDest.park_xf(world, 0).origin
	var b := AdventureDest.park_xf(world, 3).origin
	return (a + b) * 0.5 + Vector3.UP * 1.3


func _start_moment() -> void:
	moment_t = 0.0
	if _moment_cam == null:
		_moment_cam = Camera3D.new()
		_moment_cam.name = "ArrivalCamera"
		_moment_cam.fov = 62.0
		_moment_cam.far = 6000.0
		main.world.add_child(_moment_cam)
	_moment_cam.current = true
	var dest := AdventureDest.of(str(Shed.adventure.get("dest", "")))
	var mins := maxi(1, (Time.get_ticks_msec() - _started_at) / 60000)
	_card_title.text = AdventureDest.name_of(str(Shed.adventure.get("dest", "")))
	_card_sub.text = "%s  ·  %d km  ·  %s\n%s" % [str(Shed.adventure.get("title", "")), roundi(float(Shed.adventure.get("km", 0.0))),
		"%d h %02d min in the saddle" % [mins / 60, mins % 60] if mins >= 60 else "%d min in the saddle" % mins, str(dest.get("line", ""))]
	var photo: Dictionary = Shed.adventure.get("photo", {})
	_polaroid_pic.texture = AdventureDest.picture(str(Shed.adventure.get("dest", "")), maxi(1, (photo.get("names", []) as Array).size()))
	_polaroid_caption.text = AdventureDest.caption(photo) if not photo.is_empty() else ""
	_card.visible = true
	_card.modulate.a = 0.0
	_polaroid.visible = false
	_tick_moment(0.0)
	Sfx.play_ui("levelup", -4.0)


## Runs the moment on: the camera pulling back from the crew to take in the set piece, the
## title card fading in and out, and the flash and the photo.
func _tick_moment(delta: float) -> void:
	moment_t += delta
	var t := moment_t
	if world and _moment_cam:
		var group := _group_point()
		var piece := AdventureDest.piece_point(world)
		var right := Vector3(piece.x - group.x, 0.0, piece.z - group.z).normalized()
		var fwd := right.cross(Vector3.UP)
		var k := smoothstep(0.0, PULL_BACK, t)
		var from := group - right * 7.0 + fwd * 1.5 + Vector3.UP * 0.8
		var to := group - right * 26.0 - fwd * 14.0 + Vector3.UP * 13.0
		var look := group.lerp((group + piece) * 0.5, k)
		_moment_cam.global_position = from.lerp(to, k)
		if _moment_cam.global_position.distance_to(look) > 0.1:
			_moment_cam.look_at(look, Vector3.UP)
	_card.modulate.a = clampf(minf((t - 0.4) / 1.0, (MOMENT - 0.3 - t) / 1.0), 0.0, 1.0)
	var since := t - PHOTO_AT
	if t >= PHOTO_AT - 0.2 and t - delta < PHOTO_AT - 0.2:
		# The crew at the destination, for the diary: the frame just before the flash.
		photos.snap("arrive", "We made it: %s" % AdventureDest.name_of(str(Shed.adventure.get("dest", ""))), "arrive")
	_card_flash.color.a = clampf(1.0 - since / 0.45, 0.0, 1.0) if since >= 0.0 else 0.0
	if since >= 0.0 and since - delta < 0.0:
		Sfx.play_ui("clink", -2.0)
	_polaroid.visible = since >= 0.0
	_polaroid.rotation = deg_to_rad(-4.0) * clampf(since, 0.0, 1.0)
	if t >= MOMENT:
		_end_moment()
		if photos.finish():
			main.hud.flash("The Adventure Diary's put together: read it after Ride home, or any time from the magazine on the workbench or the photo on the shed wall.", 6.0)


## The moment's over (or the ride is): back to your own camera.
func _end_moment() -> void:
	moment_t = -1.0
	if _card:
		_card.visible = false
	if _moment_cam:
		_moment_cam.queue_free()
		_moment_cam = null
		if main and main.bike:
			main.camera.current = true
		elif main and main.walker:
			main.walker.camera.current = true


func _process(delta: float) -> void:
	if moment_t >= 0.0:
		_tick_moment(delta)


## The title card (the destination's name, the ride, how long it took) and the photo.
func _make_card(layer: CanvasLayer) -> void:
	_card = Control.new()
	_card.name = "ArrivalCard"
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position.y = 90.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(box)
	var kicker := _card_label("YOU MADE IT", 22, UITheme.ACCENT)
	box.add_child(kicker)
	_card_title = _card_label("", 64, Color(1, 1, 1))
	box.add_child(_card_title)
	_card_sub = _card_label("", 22, Color(0.95, 0.92, 0.85))
	box.add_child(_card_sub)
	_polaroid = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.97, 0.96, 0.93)
	ps.set_content_margin_all(12)
	ps.content_margin_bottom = 8
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size = 10
	_polaroid.add_theme_stylebox_override("panel", ps)
	_polaroid.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_polaroid.position = Vector2(-470, -400)
	_polaroid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_polaroid)
	var pv := VBoxContainer.new()
	_polaroid.add_child(pv)
	_polaroid_pic = TextureRect.new()
	_polaroid_pic.custom_minimum_size = Vector2(384, 256)
	_polaroid_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_polaroid_pic.stretch_mode = TextureRect.STRETCH_SCALE
	pv.add_child(_polaroid_pic)
	_polaroid_caption = Label.new()
	_polaroid_caption.add_theme_font_size_override("font_size", 15)
	_polaroid_caption.add_theme_color_override("font_color", Color(0.15, 0.13, 0.12))
	_polaroid_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_polaroid_caption.custom_minimum_size = Vector2(384, 0)
	_polaroid_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_polaroid_caption)
	_card_flash = ColorRect.new()
	_card_flash.color = Color(1, 1, 1, 0)
	_card_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.add_child(_card_flash)


func _card_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------------------- the magazine

## Picks up the magazine on the workbench (open at article `at`, or where it was left).
func open_magazine(at := "") -> void:
	if main == null or not main.in_session:
		return
	if magazine == null:
		magazine = AdventureMag.new()
		magazine.visible = false
		_hud.get_parent().add_child(magazine)
		magazine.closed.connect(close_magazine)
	if main.menu.visible:
		main.menu.hide()
	magazine.open(at)
	main._capture_mouse(false)


## Unfolds the shed's map of region `region_id` (from the magazine page `article_id`).
func open_journey(region_id: String, article_id := "") -> void:
	if main == null or not main.in_session:
		return
	if journey_map == null:
		journey_map = JourneyMap.new()
		journey_map.visible = false
		_hud.get_parent().add_child(journey_map)
		journey_map.closed.connect(close_journey)
	if magazine != null:
		magazine.visible = false
	journey_map.article_id = article_id
	journey_map.open(region_id)
	main._capture_mouse(false)


func close_journey() -> void:
	if journey_map == null or not journey_map.visible:
		return
	journey_map.visible = false
	if main and main.in_session and not main.menu.visible:
		main._capture_mouse(true)


func journey_open() -> bool:
	return journey_map != null and journey_map.visible


func close_magazine() -> void:
	if magazine == null or not magazine.visible:
		return
	magazine.visible = false
	if main and main.in_session and not main.menu.visible:
		main._capture_mouse(true)


func magazine_open() -> bool:
	return magazine != null and magazine.visible


# ---------------------------------------------------------------------------- the diary

## Opens the Adventure Diary book: at diary `id`, or on the shelf of every diary on this machine.
func open_diary(id := "") -> void:
	if main == null or not main.in_session:
		return
	if diary == null:
		diary = DiaryBook.new()
		diary.visible = false
		_hud.get_parent().add_child(diary)
		diary.closed.connect(close_diary)
	if main.menu.visible:
		main.menu.hide()
	close_magazine()
	if id == "" or not diary.open_diary(id):
		diary.open_shelf()
	main._capture_mouse(false)


func close_diary() -> void:
	if diary == null or not diary.visible:
		return
	diary.visible = false
	if main and main.in_session and not main.menu.visible and not magazine_open() and not journey_open():
		main._capture_mouse(true)


func diary_open() -> bool:
	return diary != null and diary.visible
