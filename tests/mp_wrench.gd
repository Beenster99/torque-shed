extends Node
## Two-process co-op check of roadside wrenching (see Roadside), run by tests/mp_test.sh: a host
## and a client go on an adventure with toolboxes packed. The client's chain snaps; they get off
## and the host must see the client's bike stood at the roadside where they left it, then its
## toolbox open with the kit out on a cloth, and the chain fixed with the spare (gone from the
## toolbox). Then the host gets off and lends a hand with the toolbox's spanners (see ToolboxSpares):
## unbolts the client's front pads, takes them off, packs them in the client's toolbox, takes a
## spare out and fits and bolts it, all through the host's shed, and the client must see each step.
## Then it snaps again and the host tows the client on a strap: the client's bike must
## be pulled along the road behind the host's, and the host must see the strap between them.

const SEED := 654
const KM := 20.0
const KIT: Array[String] = ["tools", "spare_chain", "fuses", "levers"]   # (room left for a spare part and the old one)
const SPARE_PADS := "sintered"

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Wrench %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var packed := [false]
	var ok_start := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			if not packed[0]:
				packed[0] = true
				_pack_toolboxes()
			Adventure.start(SEED, KM)
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 40.0)
	print("MP wrench note %s: on the adventure %s" % [role, ok_start])
	var seen_parked := false
	var seen_open := false
	var seen_fixed := false
	var helped := false
	var towed_ok := false
	var strap_seen := false
	if ok_start:
		await _until(func(): return trip.world.has_ground(300.0), 20.0)
		if role == "client":
			var r := await _client_breakdown(trip)
			seen_parked = r[0]
			seen_open = r[1]
			seen_fixed = r[2]
			helped = r[3]
			towed_ok = await _client_tow(trip)
			strap_seen = true
		else:
			var r := await _host_watch(trip)
			seen_parked = r[0]
			seen_open = r[1]
			seen_fixed = r[2]
			helped = r[3]
			var t := await _host_tow(trip)
			towed_ok = t[0]
			strap_seen = t[1]
	# Home: the host ends it.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 25.0)
	var ok := ok_start and seen_parked and seen_open and seen_fixed and helped and towed_ok and strap_seen and home_ok
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP wrench %s %s: on the adventure=%s, the bike at the roadside seen=%s, its toolbox open=%s, fixed with the spare chain=%s, a mate swapped its pads=%s, towed along=%s, strap seen=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, seen_parked, seen_open, seen_fixed, helped, towed_ok, strap_seen, home_ok])
	get_tree().quit(0 if ok else 1)


## The host packs a toolbox on every bike before setting off.
func _pack_toolboxes() -> void:
	for bike in Shed.bikes:
		var old := Shed.item_on(int(bike), "toolbox")
		if old != 0:
			Shed.items.erase(old)
		var id := Shed._new_item("alloy_toolbox", 0.0, 0.0, 0.0)
		Shed._move(id, "bike", int(bike))
		Shed.bikes[bike]["slots"]["toolbox"] = id
		Shed.bikes[bike]["bolted"]["toolbox"] = true
		Shed.items[id]["contents"] = KIT.duplicate()
		# A spare set of brake pads in it, for the host to fit (see ToolboxSpares).
		Shed.items[id]["spares"] = [{"part": SPARE_PADS, "kind": "pads", "rust": 0.0, "dirt": 0.0, "wear": 0.0,
			"color": PartsDB.default_color(SPARE_PADS), "finish": "", "boxed": false}]
	Shed._mark_dirty()
	Shed.changed.emit()


## The client: chain snaps, off at the roadside, toolbox open, fixed. Returns what it saw of its
## own (that the shed took each step).
func _client_breakdown(trip: AdventureTrip) -> Array:
	var bike := Shed.riding(Shed.me())
	await _wait(3.0)
	Shed.request({"a": "roadside_fault", "kind": "chain_snap"})
	var snapped := await _until(func(): return Roadside.dead(bike), 10.0)
	main.bike.linear_velocity = Vector3.ZERO
	await _wait(1.0)
	main._get_off()
	var parked := await _until(func(): return Roadside.parked(bike), 10.0)
	await _wait(4.0)   # the host looks
	Shed.request({"a": "roadside_open", "bike": bike, "open": true})
	var opened := await _until(func(): return Roadside.spot_of(bike).get("open", false), 10.0)
	await _wait(4.0)
	Shed.request({"a": "roadside_fix", "bike": bike, "fault": "chain_snap", "crouched": true, "quality": 0.8})
	var fixed := await _until(func(): return not Roadside.dead(bike), 10.0)
	print("MP wrench note client: snapped %s, parked %s, opened %s, fixed %s" % [snapped, parked, opened, fixed])
	# The host gets off and swaps the front pads for a spare from the toolbox: each step seen here.
	var box := Roadside.toolbox_of(bike)
	var first := Shed.item_on(bike, "front_pads")
	var seen := {"unbolted": false, "off": false, "packed": false}
	var helped := await _until(func():
		if Shed.item_on(bike, "front_pads") == first and not Shed.is_bolted(bike, "front_pads"):
			seen["unbolted"] = true
		if Shed.item_on(bike, "front_pads") == 0:
			seen["off"] = true
		if ToolboxSpares.spares_of(box).size() == 2:
			seen["packed"] = true   # the old pads in with the spare
		var now := Shed.item_on(bike, "front_pads")
		return seen["off"] and seen["packed"] and now != 0 and now != first and Shed.is_bolted(bike, "front_pads") \
			and ToolboxSpares.spares_of(box).size() == 1, 40.0)
	print("MP wrench note client: the host's help seen %s (%s)" % [helped, str(seen)])
	await _wait(2.0)
	return [snapped and parked, opened, fixed, helped and seen["unbolted"]]


## The host watches the client's bike: stood at the roadside by them, its toolbox open, fixed.
func _host_watch(trip: AdventureTrip) -> Array:
	var theirs := [0]
	var view := [null]
	for c in trip.world.get_children():
		if c is RoadsideView:
			view[0] = c
	var parked := await _until(func():
		for id in Shed.bikes:
			if Roadside.parked(int(id)):
				theirs[0] = int(id)
		if theirs[0] == 0 or view[0] == null or not view[0]._views.has(theirs[0]):
			return false
		var node: Node3D = view[0]._views[theirs[0]]["node"]
		var them = _remote_figure()
		return them != null and node.global_position.distance_to(them) < 3.0, 30.0)
	print("MP wrench note host: the client's bike %d parked and drawn by them %s" % [theirs[0], parked])
	var opened := await _until(func():
		if view[0] == null or not view[0]._views.has(theirs[0]):
			return false
		return (view[0]._views[theirs[0]]["node"] as Node3D).get_child_count() > 3, 20.0)
	var fixed := await _until(func():
		var box := Roadside.toolbox_of(theirs[0])
		var shown: bool = view[0]._views.has(theirs[0]) and str(view[0]._views[theirs[0]]["sig"]).contains("chain")
		return theirs[0] != 0 and not Roadside.dead(theirs[0]) and Roadside.used_of(box).has("spare_chain") and shown, 20.0)
	var helped := await _host_help(theirs[0]) if fixed else false
	return [parked, opened, fixed, helped]


## The host gets off its own bike and lends a hand at the client's: the wrench from its open
## toolbox on the front pads, off and into the box, the spare set out and on, bolted up (each a
## request the host's shed checks like anyone's). Then back on its own bike for the tow.
func _host_help(theirs: int) -> bool:
	var mine := Shed.riding(Shed.me())
	main.bike.linear_velocity = Vector3.ZERO
	await _wait(1.0)
	main._get_off()
	var off := await _until(func(): return Shed.riding(Shed.me()) == 0, 10.0)
	var box := Roadside.toolbox_of(theirs)
	var ok := off
	for step in [{"a": "unbolt", "bike": theirs, "slot": "front_pads"}, {"a": "remove", "bike": theirs, "slot": "front_pads"},
			{"a": "spare_stow", "item": box}, {"a": "spare_take", "item": box, "index": 0, "part": SPARE_PADS},
			{"a": "install", "bike": theirs, "slot": "front_caliper"}, {"a": "bolt", "bike": theirs, "slot": "front_pads"}]:
		var why := Shed.check(Shed.me(), step)
		if why != "":
			print("MP wrench note host: %s refused: %s" % [str(step["a"]), why])
			ok = false
		Shed.request(step)
		await _wait(1.2)
	ok = ok and Shed.is_bolted(theirs, "front_pads") and str(Shed.items[Shed.item_on(theirs, "front_pads")]["part"]) == SPARE_PADS \
		and ToolboxSpares.spares_of(box).size() == 1
	print("MP wrench note host: got off %s, swapped the client's pads for the spare %s" % [off, ok])
	main._left_bike = 0
	main._try_mount(mine)
	var back := await _until(func(): return main.bike != null, 10.0)
	return ok and back


## The client: back on, the chain snaps again, and the host's bike tows it on.
func _client_tow(trip: AdventureTrip) -> bool:
	var bike := Shed.riding(Shed.me())
	for id in Shed.bikes:
		if Roadside.parked(int(id)) and int(Shed.bikes[id].get("rider", 0)) == 0:
			bike = int(id)
	main._try_mount(bike)
	await _until(func(): return main.bike != null, 10.0)
	Shed.request({"a": "roadside_fault", "kind": "chain_snap"})
	await _until(func(): return Roadside.dead(bike), 10.0)
	var host_peer := 1
	# Held on the back brake while it waits, as a rider would on a hill (the new roads climb).
	Input.action_press("rear_brake")
	var near := await _until(func():
		var rb := _remote_bike()
		return rb != null and main.bike != null and rb.global_position.distance_to(main.bike.global_position) < Roadside.TOW_REACH \
			and absf(main.bike.speed) < Roadside.TOW_STOPPED, 30.0)
	main._tow_button()
	var tied := await _until(func(): return int(Shed.bikes[bike].get("tow", 0)) == host_peer, 10.0)
	# Off the brake once the host's bike moves off up the road and takes up the strap.
	var rb0 := _remote_bike()
	var at0: float = trip.world.distance_of(rb0.global_position, "towing") if rb0 else 0.0
	await _until(func():
		var rb := _remote_bike()
		return rb == null or trip.world.distance_of(rb.global_position, "towing") > at0 + 2.0, 10.0)
	Input.action_release("rear_brake")
	var from := trip.world.distance_of(main.bike.global_position, "own")
	var went := [0.0]
	var pulled := await _until(func():
		if main.bike == null:
			return false
		went[0] = trip.world.distance_of(main.bike.global_position, "own") - from
		return went[0] > 25.0 and not main.bike.is_crashed, 40.0)
	print("MP wrench note client: near the host %s, tied on %s, pulled %.1f m along the road %s" % [near, tied, went[0], pulled])
	Shed.request({"a": "roadside_untow"})
	return near and tied and pulled


## The host waits for the client to tie on, then rides off down the road, seeing the strap.
func _host_tow(trip: AdventureTrip) -> Array:
	# Ride up beside the client's bike: just ahead of it, on the road.
	var their_bike := [0]
	await _until(func():
		for id in Shed.bikes:
			if int(id) != Shed.riding(Shed.me()) and int(Shed.bikes[id].get("rider", 0)) != 0:
				their_bike[0] = int(id)
		return their_bike[0] != 0 and _remote_bike() != null, 30.0)
	# Once its chain has gone and it's come to rest where the client got on it: the remote bike is
	# drawn where it was a moment ago, and placed off a stale spot the host ends up behind it.
	await _until(func(): return Roadside.dead(their_bike[0]), 30.0)
	var rb := _remote_bike()
	if rb == null:
		return [false, false]
	var still := [rb.global_position, Time.get_ticks_msec()]
	await _until(func():
		if rb.global_position.distance_to(still[0]) > 0.2:
			still[0] = rb.global_position
			still[1] = Time.get_ticks_msec()
		return Time.get_ticks_msec() - int(still[1]) > 1000, 15.0)
	var s := trip.world.distance_of(rb.global_position, "host")
	var xf := trip.world.transform_at(s + 6.0, -trip.world.route.width_at_s(s) * 0.25)
	main.bike.place(xf.origin, trip.world.heading_at(s + 6.0))
	# On the brake while the client ties on: the new roads climb, and a bike left to itself rolls
	# back down on to the one it's meant to tow.
	Input.action_press("rear_brake")
	var tied := await _until(func(): return int(Shed.bikes[their_bike[0]].get("tow", 0)) == Shed.me(), 30.0)
	var view: RoadsideView = null
	for c in trip.world.get_children():
		if c is RoadsideView:
			view = c
	main.bike.engine_on = true
	main.bike.gear = 1
	main.bike.fuel_litres = main.bike.build.fuel_capacity
	var strap := [false]
	Input.action_press("throttle", 0.35)
	Input.action_release("rear_brake")
	var done := await _until(func():
		if view and view._straps.has(their_bike[0]):
			strap[0] = true
		return int(Shed.bikes[their_bike[0]].get("tow", 0)) == 0, 45.0)
	Input.action_release("throttle")
	main.bike.throttle = 0.0
	print("MP wrench note host: tied %s, strap seen %s, untied %s" % [tied, strap[0], done])
	return [tied and done, strap[0]]


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame


func _remote_bike() -> Node3D:
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			return rp.bike
	return null


## Where the other player stands on foot, or null.
func _remote_figure():
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike == null:
			return rp.world_position()
	return null
