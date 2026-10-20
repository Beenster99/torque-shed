extends Node
## Headless entry point: exports the release bikes as .glb files (see GlbExport).
##   godot --headless --path . res://tools/export_glb.tscn -- --out=/path/to/releases/vX-glb


func _ready() -> void:
	var out := "user://glb_export"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	await get_tree().process_frame
	var reports := GlbExport.export_release(out)
	for file in reports:
		print("%s.glb: %s" % [file, reports[file]])
	get_tree().quit(0 if reports.values().all(func(r): return r["error"] == OK) else 1)
