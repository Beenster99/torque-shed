extends Node
## Two-process check of the route handshake, run by tests/mp_route_test.sh: a host and a client each start the
## real game, either both on the same baked route (the client joins and is seen), or one on the route and the
## other on the normal map (the client is told they differ, and the host never sees them join).
##   -- --role=host|client --expect=match|mismatch [--route=res://data/routes/shodoshima]

var role := "host"
var expect := "match"
var failed := ""
var joined := false
var kicked := false


func _ready() -> void:
	Shed.demo_bikes = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--expect="):
			expect = a.trim_prefix("--expect=")
	Settings.player_name = "Route %s" % role
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Net.connection_failed.connect(func(reason): failed = reason)
	Net.player_joined.connect(func(_id, _info): joined = true)
	Net.disconnected.connect(func(): kicked = true)
	if role == "host":
		main._host()
	else:
		main._join(" 127.0.0.1:24680 ")
	var deadline := Time.get_ticks_msec() + (22000 if role == "host" else 14000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if role == "client" and (joined or failed != "" or kicked):
			break
	var ok := false
	if expect == "match":
		ok = joined and failed == ""
	elif role == "client":
		# Turned away: told the maps differ, or put out by the host before they could be.
		ok = failed.contains("different") or kicked
	else:
		ok = not joined
	print("MP ROUTE %s expect=%s joined=%s kicked=%s failed=%s -> %s" % [role, expect, joined, kicked, failed.left(60), "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
