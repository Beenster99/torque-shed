extends Node
## Classic and New side by side (see BikeLook): each style's stock bike, ridden-past (baked),
## drawn in both looks from the same spot, plus a rusty, a patina-painted and a carbon and
## brushed-alloy bike, with how far apart the two pictures are:
##   xvfb-run -a godot --path . res://tests/bike_look_shots.tscn -- --out=/tmp/look [--styles=cafe,sport]
## Writes <style>_classic.png, <style>_new.png and diff.json (mean and worst pixel difference, 0..255).
var out_dir := "/tmp/look"
var styles: Array = []
var cam: Camera3D


func _ready() -> void:
	styles = Array(PartsDB.STYLES)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--styles="):
			styles = Array(a.trim_prefix("--styles=").split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(960, 600)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.8
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mi.mesh = plane
	var tarmac := StandardMaterial3D.new()
	tarmac.albedo_color = Color(0.25, 0.25, 0.26)
	tarmac.roughness = 0.95
	floor_mi.material_override = tarmac
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(2.9, 1.25, -2.3)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	var diffs := {}
	var cases := []
	for style in styles:
		cases.append([style, Contracts.style_build(style), null])
	var rusty := {}
	var patina := {}
	for s in PartsDB.SLOTS:
		rusty[s] = {"rust": 0.6, "wear": 0.3}
	for s in ["tank", "frame", "front_mudguard", "tail", "side_panels"]:
		patina[s] = {"color": Color(0.2, 0.45, 0.3), "finish": "patina"}
	if styles.size() == PartsDB.STYLES.size():
		cases.append(["rusty", Contracts.style_build("classic"), rusty])
		cases.append(["patina", Contracts.style_build("cafe"), patina])
	for c in cases:
		var shots := {}
		for look in BikeLook.LOOKS:
			var m := BikeModel.new()
			m.look = look
			m.baked = true
			add_child(m)
			m.build_from(BikeBuild.new(PartsDB.sanitize_build(c[1])), Color(0.7, 0.12, 0.1), {}, c[2])
			m.position = Vector3(0.0, -m.foot_ground_y(), 0.0)
			for i in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [out_dir, c[0], look])
			shots[look] = img
			m.free()
		diffs[c[0]] = _diff(shots[BikeLook.CLASSIC], shots[BikeLook.NEW])
		print(c[0], " ", diffs[c[0]])
	var f := FileAccess.open(out_dir + "/diff.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(diffs, "\t"))
	f.close()
	get_tree().quit()


## How far apart two pictures are: the mean difference over every pixel and channel, the
## worst, and the share of pixels off by more than 8 (0..255).
func _diff(a: Image, b: Image) -> Dictionary:
	var total := 0.0
	var worst := 0
	var off := 0
	var da := a.get_data()
	var db := b.get_data()
	var step := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	var n := mini(da.size(), db.size())
	for i in range(0, n, step):
		var d := maxi(maxi(absi(da[i] - db[i]), absi(da[i + 1] - db[i + 1])), absi(da[i + 2] - db[i + 2]))
		total += d
		worst = maxi(worst, d)
		if d > 8:
			off += 1
	return {"mean": snappedf(total / (n / step), 0.01), "worst": worst, "off": snappedf(float(off) / (n / step), 0.0001)}
