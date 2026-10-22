extends Node
## A screenshot of the shed's journey map, for checking how it looks:
##   xvfb-run -a godot --path . res://tests/journey_shots.tscn -- --out=/tmp/shots [--region=shodoshima]
## Pins a journey across the region, lets it plan, and saves the map whole and zoomed in.

var out_dir := "/tmp/shots"
var region := "shodoshima"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--region="):
			region = a.trim_prefix("--region=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.22)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var r := RealRegion.get_region(region)
	var map := JourneyMap.new()
	add_child(map)
	map.open(region)
	await get_tree().process_frame
	var ends := [Vector2(-7900, 1500), Vector2(-1500, -3000), Vector2(5900, 2200)]
	for p: Vector2 in ends:
		Shed.request({"a": "adventure_pin", "region": region, "x": p.x, "z": p.y})
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		if map._view.shade != null and map._view.route_pts.size() > 1:
			break
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("journey_whole.png"))
	map._view._scale = 0.06
	map._centre = Vector2(-1500, -3000)
	map._canvas.queue_redraw()
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("journey_zoom.png"))
	print("saved")
	get_tree().quit()
