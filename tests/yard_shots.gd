extends Node
## Screenshots of every piece of yard kit, one at a time out on a clear patch of the yard, and
## (with --jump) a bike jumping the row of buses off the huge ramp:
##   xvfb-run -a godot --path . res://tests/yard_shots.tscn -- --out=/tmp/shots [--tag=after] [--jump] [--only=bus_row]

var out_dir := "/tmp/shots"
var tag := ""
var jump := false
var only := ""
var main: Node
var cam: Camera3D
## Where each piece is put down for its picture: a clear bit of the yard west of the skid pad.
const SPOT := Vector3(14.0, 0.0, -40.0)


func _ready() -> void:
	Shed.demo_bikes = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=") + "_"
		elif a == "--jump":
			jump = true
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main._start_session()
	await _frames(30)
	if Daylight.current:
		Daylight.current.hours = 11.0
	if Weather.current:
		Weather.current.change_to("clear", true)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	add_child(cam)
	# The yard's own kit out of the way, so each piece is seen on its own.
	for id in Shed.furniture.keys():
		if Equipment.is_yard(str(Shed.furniture[id]["model"])):
			Shed.furniture.erase(id)
	Shed.changed.emit()
	await _frames(5)
	if jump:
		await _jump()
	else:
		for kind in Equipment.YARD_KINDS:
			for model: String in Equipment.by_kind(kind):
				if only != "" and not only.split(",").has(model):
					continue
				await _piece(kind, model)
	get_tree().quit()


func _piece(kind: String, model: String) -> void:
	var size: Vector3 = Equipment.get_model(model)["size"]
	var fid := Shed._new_furniture(kind, Transform3D(Basis(Vector3.UP, PI * 0.5), SPOT), model)
	Shed.changed.emit()
	await _frames(4)
	var reach := maxf(maxf(size.x, size.z), size.y * 1.6)
	var mid := SPOT + Vector3(0.0, size.y * 0.45, 0.0)
	# Three quarters on from the front (the low end of a ramp), then from the back.
	await _look(mid + Vector3(reach * 0.9 + 1.2, size.y * 0.5 + 0.9, reach * 0.75 + 1.0), mid, "%s%s_a" % [tag, model])
	await _look(mid + Vector3(-reach * 0.9 - 1.0, size.y * 0.4 + 0.6, -reach * 0.6 - 1.0), mid, "%s%s_b" % [tag, model])
	Shed.furniture.erase(fid)
	Shed.changed.emit()
	await _frames(2)


## The huge launch ramp, the row of buses and the huge landing, ridden east, photographed from
## the side as the bike flies over.
func _jump() -> void:
	var tests: RefCounted = load("res://tests/yard_items_tests.gd").new(self)
	# Along z = -40 from x = -30: the run-up from the yard's west edge, the roll-out towards the skid pad.
	var line: Dictionary = tests.lay_bus_jump(Vector3(-25.5, 0.0, -40.0))
	for piece: Array in line["pieces"]:
		Shed._new_furniture(Equipment.kind_of(piece[0]), piece[1], piece[0])
	Shed.changed.emit()
	await _frames(5)
	var bike := Bike.new()
	bike.setup(BikeBuild.new())
	main.world.add_child(bike)
	var lip: Vector3 = line["lip"]
	await _look(lip + Vector3(-14.0, 4.0, 20.0), lip + Vector3(8.0, -0.5, 0.0), "%sbus_jump_0_line" % tag)
	await _look(lip + Vector3(-12.0, 1.2, -1.5), lip + Vector3(14.0, 1.0, 0.0), "%sbus_jump_0_rider_view" % tag)
	var shots := [0]
	await tests.ride_jump(bike, line, func(i: int, b: Bike) -> void:
		if i % 18 == 0 and b.global_position.x > lip.x - 3.0 and b.global_position.x < lip.x + 30.0 and shots[0] < 10:
			shots[0] += 1
			cam.global_position = Vector3(b.global_position.x - 5.0, lip.y + 0.5, lip.z + 14.0)
			cam.look_at(b.global_position + Vector3(3.0, -0.5, 0.0))
			await _shot("%sbus_jump_%d" % [tag, shots[0]]), 16.5, 0.3, 32.0)


func _look(from: Vector3, at: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.make_current()
	await _frames(12)
	await _shot(name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


## For the test helpers it borrows (they report through check()).
func check(cond: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", what])
