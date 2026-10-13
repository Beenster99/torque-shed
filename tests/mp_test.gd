extends Node
## Two-process co-op check, run by tests/mp_test.sh: a host and a client each start the real
## game. The client must receive the host's shed, unbolt a part and put another down on the
## floor and tune a tyre pressure, which the host must then see, each puts a mark on the whiteboard
## the other must see, and both must see each other walk.

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
	var xp_start := -1
	var xp_ok := false
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
		# XP: the host pays the client for its work, and learns the client's level from its report.
		if xp_start < 0:
			xp_start = int(Progress.profile["xp"])
		if role == "client":
			xp_ok = int(Progress.profile["xp"]) > xp_start
		elif main.remotes.size() == 1:
			xp_ok = str(Progress.summary(main.remotes.keys()[0]).get("name", "")) == "Test client"
		if role == "client" and ranger != 0 and not asked:
			Shed.request({"a": "unbolt", "bike": ranger, "slot": "exhaust"})
			Shed.request({"a": "take", "spot": "bench_0"})
			Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.5, 0.0, 1.5))})
			Shed.board_request({"a": "board_draw", "id": 4242, "c": 1, "w": 6.0, "from": 0,
				"pts": PackedVector2Array([Vector2(100, 100), Vector2(300, 200)]), "done": true})
			Shed.request({"a": "tune", "bike": ranger, "key": "psi_f", "value": 0.9})
			asked = true
		if role == "host" and Shed.crew.size() == 2 and not asked:
			Shed.board_request({"a": "board_text", "id": 4343, "c": 2, "s": 38, "at": Vector2(500, 300), "text": "Host's list"})
			asked = true
		# Each side's whiteboard marks reach the other.
		var board_ok := BoardData.find(Shed.board, 4242) >= 0 and BoardData.find(Shed.board, 4343) >= 0
		var dropped := false
		for id in Shed.floor_items():
			dropped = dropped or (Shed.items[id]["ref"] is Transform3D)
		var tuned := ranger != 0 and is_equal_approx(float(Shed.tune_of(ranger).get("psi_f", 0.0)), 0.9)
		if ranger != 0 and not Shed.is_bolted(ranger, "exhaust") and dropped and tuned and Shed.crew.size() == 2 and board_ok and xp_ok:
			shed_ok = true
	# Keep running for a moment so the other side can finish its own check.
	var linger := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
	var ok := moved and shed_ok
	print("MP %s %s: saw the other player move=%s, shared shed in step=%s (bikes %d, crew %d, board marks %d, xp %s)" % [
		"PASS" if ok else "FAIL", role, moved, shed_ok, Shed.bikes.size(), Shed.crew.size(), Shed.board["marks"].size(), xp_ok])
	get_tree().quit(0 if ok else 1)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0
