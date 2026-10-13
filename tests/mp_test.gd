extends Node
## Two-process co-op check, run by tests/mp_test.sh: a host and a client each start the real
## game. The client must receive the host's shed, unbolt a part and put another down on the
## floor, which the host must then see, and both must see each other walk.

var role := "host"
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Test %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join(" 127.0.0.1:24680 ")
	var deadline := Time.get_ticks_msec() + 25000
	var moved := false
	var shed_ok := false
	var start := Vector3.ZERO
	var asked := false
	while Time.get_ticks_msec() < deadline and not (moved and shed_ok):
		await get_tree().physics_frame
		if not main.in_session:
			continue
		# Walk up and down so the other side sees movement.
		var t := Time.get_ticks_msec() / 1000.0
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_press("move_forward" if fmod(t, 2.0) < 1.0 else "move_back")
		if main.remotes.size() == 1:
			var rp: RemotePlayer = main.remotes.values()[0]
			var p := rp.world_position()
			if start == Vector3.ZERO and p != Vector3.ZERO:
				start = p
			elif start != Vector3.ZERO and p.distance_to(start) > 0.8:
				moved = true
		var ranger := _bike_named("Rusty Ranger")
		if role == "client" and ranger != 0 and not asked:
			Shed.request({"a": "unbolt", "bike": ranger, "slot": "exhaust"})
			Shed.request({"a": "take", "spot": "bench_0"})
			Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.5, 0.0, 1.5))})
			asked = true
		var dropped := false
		for id in Shed.floor_items():
			dropped = dropped or (Shed.items[id]["ref"] is Transform3D)
		if ranger != 0 and not Shed.is_bolted(ranger, "exhaust") and dropped and Shed.crew.size() == 2:
			shed_ok = true
	# Keep running for a moment so the other side can finish its own check.
	var linger := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
	var ok := moved and shed_ok
	print("MP %s %s: saw the other player move=%s, shared shed in step=%s (bikes %d, crew %d)" % [
		"PASS" if ok else "FAIL", role, moved, shed_ok, Shed.bikes.size(), Shed.crew.size()])
	get_tree().quit(0 if ok else 1)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0
