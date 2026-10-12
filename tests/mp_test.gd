extends Node
## Two-process multiplayer check, run by tests/mp_test.sh:
## a host and a client each start the real game, ride, and confirm they see each other move.

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
		main._join("127.0.0.1")
	var deadline := Time.get_ticks_msec() + 20000
	var moved := false
	var start := Vector3.ZERO
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		Input.action_press("throttle", 0.4)
		if main.remotes.size() == 1:
			var rb: Node3D = main.remotes.values()[0]
			if start == Vector3.ZERO and rb.global_position != Vector3.ZERO:
				start = rb.global_position
			elif start != Vector3.ZERO and rb.global_position.distance_to(start) > 3.0:
				moved = true
				break
	# Keep sending for a moment so the other side can finish its own check.
	var linger := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
	if moved:
		print("MP PASS %s saw the other rider move" % role)
	else:
		print("MP FAIL %s did not see the other rider move (remotes: %d)" % [role, main.remotes.size()])
	get_tree().quit(0 if moved else 1)
