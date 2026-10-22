extends Node
## Two-process co-op check of the police on an adventure (see AdventurePolice), run by
## tests/mp_test.sh after the others: a host and a client start the real game and the host starts
## an adventure. Both stand 3 km in; the host puts a police car on patrol ahead of them, and the
## client rides past it far too fast (moved along the road at 40 m/s, the car doing about 23)
## then stops. The host's police must chase the client, never the host; the client must see the
## car lit up and chasing it, be held (pulled over), and pay the fine from its own money; the
## host must see the fine paid, nothing for itself and its own money untouched. Then the host
## ends the adventure.

const Rides := preload("res://tests/rides.gd")

const SEED := 321
const KM := 40.0
const HOST_S := 3000.0
const CLIENT_S := 3100.0
const POLICE_S := 3220.0
const FAST := 40.0
const MONEY := 1000

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Cop %s" % role
	# Planned before connecting: planning a long ride holds the game for seconds, longer than the link waits.
	Rides.pack(KM)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var on := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			Rides.start(KM, SEED)
		return trip.on_trip() and main.bike != null and _remote_bike() != null and trip.police != null, 40.0)
	Progress.set_money(MONEY)
	var me := Shed.me()
	var other := 0
	for peer in Shed.crew:
		if int(peer) != me:
			other = int(peer)
	var my_s := HOST_S if role == "host" else CLIENT_S
	var my_lat := -1.5
	if on:
		_jump_to(trip, my_s, my_lat)
	var chased_client := false
	var chased_host := false
	var lit_seen := false
	var held_seen := false
	var paid := false
	var fine := {}
	if on and role == "host":
		# Once the client's stood at its spot, a police car on patrol ahead of both.
		var ready := await _until(func():
			_hold(trip, my_s, my_lat)
			var rb := _remote_bike()
			var s := trip.world.distance_of(rb.global_position, "check") if rb else -1.0
			return absf(s - CLIENT_S) < 20.0, 30.0)
		if ready:
			trip.police.spawn(POLICE_S, 1, false, 0.85)
		var flags := {"client": false, "host": false}
		paid = await _until(func():
			_hold(trip, my_s, my_lat)
			flags["client"] = flags["client"] or trip.police.chasing(other)
			flags["host"] = flags["host"] or trip.police.chasing(me) or trip.police.holding(me)
			var f := AdventurePolice.fines_of(other)
			return not f.is_empty() and int(f[-1]["paid"]) >= 0, 60.0)
		chased_client = flags["client"]
		chased_host = flags["host"]
		var fs := AdventurePolice.fines_of(other)
		fine = fs[-1] if not fs.is_empty() else {}
		print("MP police note host: client chased %s, host chased %s, fine %s, my fines %s, my money %d" % [chased_client, chased_host,
			str(fine), str(AdventurePolice.fines_of(me)), Progress.money()])
	elif on:
		# Wait for the car, then ride past it fast and stop a little way on.
		var came := await _until(func():
			_hold(trip, my_s, my_lat)
			return not trip.police.cars.is_empty(), 40.0)
		var flags := {"lit": false, "held": false, "chased": false, "stopped": false}
		var at := [my_s]
		var stop_at := [INF]
		if came:
			paid = await _until(func():
				var id: int = trip.police.cars.keys()[0] if not trip.police.cars.is_empty() else 0
				var st := trip.police.driver.state(id) if id != 0 else {}
				if not flags["stopped"] and not st.is_empty():
					at[0] += FAST * get_physics_process_delta_time()
					if at[0] > float(st["s"]) + 70.0:
						flags["stopped"] = true
				_hold(trip, at[0], my_lat, not flags["stopped"])
				if id != 0:
					var body := trip.police.driver.body(id)
					flags["lit"] = flags["lit"] or (body != null and body.blues != Vector2.ZERO)
				flags["chased"] = flags["chased"] or trip.police.chasing(me)
				flags["held"] = flags["held"] or trip.police.holding(me) or trip.police_hold()
				var f := AdventurePolice.fines_of(me)
				return not f.is_empty() and int(f[-1]["paid"]) >= 0 and Progress.money() < MONEY, 70.0)
		lit_seen = flags["lit"]
		held_seen = flags["held"]
		chased_client = flags["chased"]
		var fs := AdventurePolice.fines_of(me)
		fine = fs[-1] if not fs.is_empty() else {}
		print("MP police note client: car came %s, chased %s, lights %s, held %s, fine %s, money %d, said %s" % [came, chased_client, lit_seen, held_seen,
			str(fine), Progress.money(), str(trip.police.messages)])
	var ok := false
	if role == "host":
		ok = on and chased_client and not chased_host and paid and AdventurePolice.fines_of(me).is_empty() and Progress.money() == MONEY
	else:
		ok = on and chased_client and lit_seen and held_seen and paid and not fine.is_empty() \
			and Progress.money() == MONEY - int(fine["amount"]) and trip.police.messages.any(func(m): return str(m).begins_with("Fined £"))
	# Home: the host ends it (once the client has had time to finish, too).
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 4000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and not Adventure.active(), 25.0)
	ok = ok and home_ok
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	if role == "host":
		print("MP police %s host: both on the adventure=%s, the speeding client chased=%s, the host never chased=%s, the client's fine paid=%s, none for the host and its money untouched=%s, home=%s" % [
			"PASS" if ok else "FAIL", on, chased_client, not chased_host, paid, AdventurePolice.fines_of(me).is_empty() and Progress.money() == MONEY, home_ok])
	else:
		print("MP police %s client: on=%s, chased=%s, saw the blue lights=%s, pulled over=%s, fined £%d from its own money=%s, home=%s" % [
			"PASS" if ok else "FAIL", on, chased_client, lit_seen, held_seen, int(fine.get("amount", 0)), paid, home_ok])
	get_tree().quit(0 if ok else 1)


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _remote_bike() -> Node3D:
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			return rp.bike
	return null


func _jump_to(trip: AdventureTrip, s: float, lat: float) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	trip.jump(s - trip.world.distance_of(main.bike.global_position, "own"))
	var xf := trip.world.transform_at(s, lat)
	main.bike.place(xf.origin, trip.world.heading_at(s))


## Keeps our bike at `s`, `lat` (put back if it's strayed, or every tick while `moving`).
func _hold(trip: AdventureTrip, s: float, lat: float, moving := false) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	var xf := trip.world.transform_at(s, lat)
	if moving or main.bike.global_position.distance_to(xf.origin) > 0.8 or main.bike.is_crashed:
		main.bike.place(xf.origin, trip.world.heading_at(s))
		if moving:
			main.bike.linear_velocity = -xf.basis.z * FAST   # riding along it, as far as anyone can tell
