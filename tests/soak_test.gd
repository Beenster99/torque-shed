extends Node
## Soak test, run by tests/soak_test.sh: a host and two clients play the real game together for
## a while (`--secs`, 240 by default) with the game clock sped up: the host hires one of each of
## the staff, customers keep arriving, the bikers are out on the roads; one client rides round
## the road loop, the other rides alongside it, and the host walks about the shed. Every ten
## seconds each prints its node, object and orphan counts, memory, sound players and particles
## alive, the shed's state size and the bytes it sent and got over the network; at the end each
## checks nothing grew without bound: the last third of the run against the first (after a
## settling-in minute). Simon's three-player sessions crashed to the desktop after an hour.

const PORT := 24711
## The most the host may send each other player, on average, KB a second.
const NET_LIMIT := 60.0
var role := "host"
var secs := 240
var main: Node
var samples: Array = []      # {t, nodes, orphans, objects, mem, audio, particles, timers, sent, got, snapshot}
var _sent := 0
var _got := 0


func _ready() -> void:
	Shed.demo_bikes = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--secs="):
			secs = int(a.trim_prefix("--secs="))
	Settings.player_name = "Soak %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var info := {"name": Settings.player_name, "color": Color(0.2, 0.5, 0.9)}
	if role == "host":
		Net.host(info, PORT)
		main._start_session()
	else:
		Net.join("127.0.0.1:%d" % PORT, info)
	var start := Time.get_ticks_msec()
	while not main.in_session and Time.get_ticks_msec() - start < 30000:
		await get_tree().process_frame
	if not main.in_session:
		print("SOAK FAIL %s: never got into the shed" % role)
		get_tree().quit(1)
		return
	if role == "host":
		Shed.request({"a": "money_debug_grant"})
		Shed.request({"a": "staff_debug_hire_all"})
		Engine.time_scale = 3.0
	# The profiler's timers, for where each side's frame goes (see Perf).
	Perf.on = true
	var next_report := 0
	var next_move := 0
	var next_customer := 0
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < secs * 1000:
		await get_tree().physics_frame
		if Engine.get_physics_frames() % maxi(1, roundi(Engine.physics_ticks_per_second / 60.0)) == 0:
			Perf.end_frame(10.0)
		var t := Time.get_ticks_msec() - start
		_count_net()
		if role == "host" and t >= next_customer:
			next_customer = t + 15000
			Shed.request({"a": "contract_spawn"})
		if t >= next_move:
			next_move = t + 20000
			_move(t)
		_drive(t)
		if t >= next_report:
			next_report = t + 10000
			_sample(t / 1000.0)
	_count_net()
	_sample(secs)
	var ok := _verdict()
	Input.action_release("throttle")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	# The host stays a moment so the clients finish first.
	if role == "host":
		var linger := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < linger:
			await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


## Every 20 s: the clients get on their bike (again) on the road loop, side by side.
func _move(t: int) -> void:
	if role == "host":
		return
	var want := _bike_named("Old Faithful" if role == "client1" else "Rusty Ranger")
	if main.bike == null and want != 0 and Shed.riding(Shed.me()) == 0:
		Shed.request({"a": "mount", "bike": want})
		return
	if main.bike:
		var road: Transform3D = main.world.road_transform(fmod(t / 100000.0, 1.0))
		var side: Vector3 = road.basis.x * (0.0 if role == "client1" else 2.5)
		main.bike.place(road.origin + side, road.basis.get_euler().y)
		main.bike.engine_on = true


## Rides (the clients) or walks up and down (the host).
func _drive(t: int) -> void:
	if role == "host" or main.bike == null:
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_press("move_forward" if (t / 1500) % 2 == 0 else "move_back")
		return
	Input.action_press("throttle", 0.35)


func _count_net() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.host == null:
		return
	_sent += int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	_got += int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))


func _sample(t: float) -> void:
	var c := {"audio": 0, "particles": 0, "timers": 0}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			c["audio"] += 1
		elif n is CPUParticles3D or n is GPUParticles3D:
			c["particles"] += 1
		elif n is Timer:
			c["timers"] += 1
		stack.append_array(n.get_children())
	var s := {"t": t, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"audio": c["audio"], "particles": c["particles"], "timers": c["timers"],
		"sent": _sent, "got": _got, "snapshot": var_to_bytes(Shed._snapshot(false)).size(), "remotes": main.remotes.size()}
	_sent = 0
	_got = 0
	samples.append(s)
	var top := []
	for r in Perf.ranked().slice(0, 6):
		top.append("%s %.2f ms" % [r[0], r[1]])
	print("SOAK %s t=%4.0fs  slowest: %s" % [role, t, ", ".join(top)])
	print("SOAK %s t=%4.0fs game %.1fh  nodes %d  orphans %d  objects %d  mem %.0f MB  sounds %d  particles %d  timers %d  net out %.1f KB/s in %.1f KB/s  shed state %d KB  remotes %d  riding %s" % [
		role, t, Daylight.time_of_day(), s["nodes"], s["orphans"], s["objects"], s["mem"], s["audio"], s["particles"], s["timers"],
		s["sent"] / 10000.0, s["got"] / 10000.0, s["snapshot"] / 1000, main.remotes.size(), str(main.bike != null)])


## Checks nothing grew without bound: the last third of the samples against the ones just
## after the first minute (when everyone has joined and the staff have started work).
func _verdict() -> bool:
	var early: Array = samples.filter(func(s): return s["t"] >= 60.0 and s["t"] < 60.0 + (secs - 60.0) / 3.0)
	var late: Array = samples.filter(func(s): return s["t"] >= secs - (secs - 60.0) / 3.0)
	if early.is_empty() or late.is_empty():
		print("SOAK FAIL %s: too short a run to judge (%d samples)" % [role, samples.size()])
		return false
	var ok := true
	var notes := []
	# [what, allowed growth as a share, plus a flat allowance]
	for k in [["nodes", 0.25, 800.0], ["objects", 0.25, 2000.0], ["mem", 0.2, 60.0], ["audio", 0.3, 12.0],
			["particles", 0.3, 12.0], ["timers", 0.3, 5.0], ["orphans", 0.0, 50.0], ["snapshot", 0.5, 40000.0]]:
		var a := _avg(early, k[0])
		var b := _avg(late, k[0])
		var limit: float = a * (1.0 + float(k[1])) + float(k[2])
		var fine := b <= limit
		ok = ok and fine
		notes.append("%s %.0f -> %.0f%s" % [k[0], a, b, "" if fine else " (TOO MUCH)"])
	# What the host sends each of the crew (a home connection's upload is often only a few
	# hundred KB a second all told): the whole shed used to go out many times a second.
	if role == "host":
		var per := 0.0
		for r in late:
			per += float(r["sent"]) / 10000.0 / maxf(int(r["remotes"]), 1)
		per /= late.size()
		var fine := per <= NET_LIMIT
		ok = ok and fine
		notes.append("sent %.1f KB/s to each player%s" % [per, "" if fine else " (TOO MUCH, at most %.0f)" % NET_LIMIT])
	print("SOAK %s %s: %s" % ["PASS" if ok else "FAIL", role, ", ".join(notes)])
	return ok


static func _avg(rows: Array, key: String) -> float:
	var sum := 0.0
	for r in rows:
		sum += float(r[key])
	return sum / maxf(rows.size(), 1)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0
