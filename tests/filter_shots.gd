extends Node
## Screenshots of aiming at the air and oil filters with the engine in the frame, standing and
## crouched, on a bike of each style:
##   xvfb-run -a godot --path . res://tests/filter_shots.tscn -- --out=/tmp/shots [--styles=cafe,sport] [--engine=inline_1000] [--air=pod_filters]

const FT := preload("res://tests/filter_tests.gd")

var out_dir := "/tmp/shots"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	var styles: Array = PartsDB.STYLES.duplicate()
	var engine := ""
	var air := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--styles="):
			styles = Array(a.trim_prefix("--styles=").split(","))
		elif a.begins_with("--engine="):
			engine = a.trim_prefix("--engine=")
		elif a.begins_with("--air="):
			air = a.trim_prefix("--air=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	main._start_session()
	await _frames(30)
	var w: Walker = main.walker
	w.set_tool("hands")
	for style in styles:
		var parts := Contracts.style_build(str(style))
		if engine != "":
			parts["engine"] = engine
		if air != "":
			parts["air_filter"] = air
		var bike := Shed._new_bike(parts, 3, "Filter test", 0.1)
		Shed.changed.emit()
		await _frames(5)
		var model: BikeModel = main.workshop.bike_model(bike)
		var floor: Transform3D = main.workshop.bike_views[bike].global_transform
		for slot in FT.FILTERS:
			for pose in FT.EYES:
				var found: Array = FT.aims(model, slot, float(FT.EYES[pose]), floor, true, [w.get_rid()])
				var eye: Vector3
				var at: Vector3
				if found.is_empty():
					at = model.global_transform * model.slot_bounds(slot).get_center()
					eye = floor * Vector3(1.0, float(FT.EYES[pose]), (floor.affine_inverse() * at).z)
				else:
					eye = found[0]["eye"]
					at = found[0]["at"]
				w.set_crouched(pose == "crouched")
				var feet: Vector3 = eye - Vector3.UP * float(FT.EYES[pose])
				w.place(Transform3D(Basis(), feet))
				await _frames(30)
				var d := at - w.camera.global_position
				w.rotation.y = atan2(-d.x, -d.z)
				w._pitch = 0.0
				w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
				await _frames(10)
				var got := "%s %s" % [str(w.target.get("slot", w.target.get("kind", "-"))), w.plan.get("verb", "")]
				print("%s %s %s: %s%s  (%d s)" % [style, slot, pose, got, "" if not found.is_empty() else "  (no clear aim)", Time.get_ticks_msec() / 1000])
				await _shot("%s_%s_%s" % [style, slot, pose])
		w.set_crouched(false)
		for s in PartsDB.SLOTS:
			var on := Shed.item_on(bike, s)
			if on != 0:
				Shed.items.erase(on)
		Shed.bikes.erase(bike)
		Shed.changed.emit()
		await _frames(5)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
