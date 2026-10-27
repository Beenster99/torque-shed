extends Node
## Screenshots of the respawn ghost (see BikeGhost) in the real game: a bike in the shed's yard
## just respawned, then in its last flickering second and solid again, and the same out on an
## adventure, with a crew mate's ghosted bike beside it.
##   xvfb-run -a godot --path . res://tests/ghost_shots.tscn -- --out=/tmp/shots [--adventure-only]

const Rides := preload("res://tests/rides.gd")

var out_dir := "/tmp/shots"
var main: Node
var yard := true


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a == "--adventure-only":
			yard = false
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	SaveGame.slot_override = "shots"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main.menu.new_shed = true
	main._start_session()
	await _frames(20)
	if Daylight.current:
		Daylight.current.set_time(13.0)
	if Weather.current:
		Weather.current.change_to("clear", true)
	Shed.request({"a": "mount", "bike": _bike_named("Old Faithful")})
	await _frames(10)
	if main.bike == null:
		print("not on a bike")
		get_tree().quit(1)
		return
	# Out in the yard, facing away from the shed.
	main.bike.place(Shed.RETRIEVE_ROW + Vector3(4.0, 0.0, 4.0), PI * 0.5)
	if yard:
		await _frames(60)
		await _ghost_shots("yard")
	# Out on an adventure.
	main.bike.place(Shed.RETRIEVE_ROW + Vector3(4.0, 0.0, 4.0), PI * 0.5)
	Rides.start(20.0, 3)
	var trip: AdventureTrip = main.trip
	var t0 := Time.get_ticks_msec()
	while not (trip.on_trip() and main.bike != null) and Time.get_ticks_msec() - t0 < 120000:
		await _frames(5)
	if not trip.on_trip():
		print("no adventure")
		get_tree().quit(1)
		return
	var w := trip.world
	var s := 900.0
	trip.jump(s - w.distance_of(main.bike.global_position, "shot"))
	var end := Time.get_ticks_msec() + 60000
	await _frames(30)
	while Time.get_ticks_msec() < end:
		await _frames(5)
		if w.wanted_chunks().all(func(c): return w.chunks.has(c)) and (w.land == null or not w.land.busy()):
			break
	var xf := w.transform_at(s, -1.6)
	main.bike.place(xf.origin, w.heading_at(s))
	# A crew mate just respawned too, a little ahead in the other lane.
	var rb := RemoteBike.new()
	main.world.add_child(rb)
	rb.setup("Mate", BikeBuild.new({}), Color(0.15, 0.3, 0.8))
	var at := w.transform_at(s + 6.0, 1.6)
	var st: PackedFloat32Array = main.bike.get_net_state()
	var q := Basis(Vector3.UP, w.heading_at(s + 6.0) + PI).get_rotation_quaternion()
	for k in 3:
		st[k] = at.origin[k] + (0.35 if k == 1 else 0.0)
	st[3] = q.x
	st[4] = q.y
	st[5] = q.z
	st[6] = q.w
	st[7] = 0.0
	st[8] = 0.0
	st[9] = 0.0
	st[27] = 60.0
	for i in 10:
		rb.push_state(st)
		await _frames(1)
	await _frames(30)
	await _ghost_shots("adventure", rb, st)
	SaveGame.delete_slot("shots")
	get_tree().quit()


## Respawns and takes three pictures: ghosted, its last flickering second, and solid again.
func _ghost_shots(where: String, rb: RemoteBike = null, st := PackedFloat32Array()) -> void:
	main.bike.respawn()
	main.bike.ghost_left = 60.0   # held as a ghost for the pictures
	main.camera.snap()
	await _frames(90)
	if rb:
		# (Their ghost is timed on the clock, and a frame drawn without a GPU can take seconds.)
		st[27] = 60.0
		rb.push_state(st)
		await _frames(3)
	_save("%s_ghost" % where)
	main.bike.ghost_left = 0.85
	if rb:
		st[27] = 0.75
		rb.push_state(st)
	await _frames(4)
	_save("%s_flicker" % where)
	if rb:
		st[27] = 0.0
		rb.push_state(st)
	main.bike.ghost_left = 0.01
	await _frames(30)
	_save("%s_solid" % where)


func _save(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("ghost_%s.png" % n))
	print("saved ", n, " ghost ", main.bike.ghost_left if main.bike else -1.0)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
