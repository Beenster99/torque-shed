extends Node
## Close-ups of road dirt, dust, dead flies and rust on new-look bikes, to judge how they read:
##   xvfb-run -a godot --path . res://tests/grime_shots.tscn -- --out=/tmp/grime [--only=mud,flies] [--big] [--baked]
## (--baked draws them as a bike being ridden is, merged for the road; else as the shed has them.)
## Writes one picture a case: mud (a bike after a wet ride, low at the front), flies (a fairing
## nose after a fast one), dusty (a bike stood about in a barn), rust (a rusty classic close on
## the tank and frame), rust_far (the same bike whole) and engine (a well-ridden bike close on the engine).
var out_dir := "/tmp/grime"
var only: Array = []
var baked := false
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(","))
		elif a == "--baked":
			baked = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1920, 1200) if OS.get_cmdline_user_args().has("--big") else Vector2i(1280, 800)
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
	# [name, style, condition (slot -> {...}), camera, look at]
	var mucky := _ridden(1.6, 0.0)
	var buggy := _ridden(0.0, 14.0)
	var both := _ridden(1.1, 6.0)
	var dusty := {}
	for s in PartsDB.SLOTS:
		dusty[s] = {"dirt": 0.55}
	var rusty := {}
	for s in PartsDB.SLOTS:
		rusty[s] = {"rust": 0.6, "wear": 0.3}
	var cases := [
		["mud", "adventure", mucky, Vector3(1.25, 0.72, -1.55), Vector3(0.0, 0.45, -0.35)],
		["flies", "sport", buggy, Vector3(0.75, 1.05, -1.6), Vector3(0.05, 0.8, -0.55)],
		["dusty", "classic", dusty, Vector3(2.4, 1.15, -1.9), Vector3(0.0, 0.55, 0.0)],
		["rust", "classic", rusty, Vector3(1.1, 1.05, -0.6), Vector3(0.05, 0.7, 0.05)],
		["rust_far", "classic", rusty, Vector3(2.4, 1.15, -1.9), Vector3(0.0, 0.55, 0.0)],
		["engine", "naked", both, Vector3(1.15, 0.85, -0.95), Vector3(0.1, 0.5, -0.15)],
	]
	for c in cases:
		if not only.is_empty() and not only.has(c[0]):
			continue
		var m := BikeModel.new()
		m.look = BikeLook.NEW
		m.baked = baked
		add_child(m)
		var bb := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(c[1])))
		# (The bike's own paint and finishes, with the dirt or rust on top.)
		var cond := {}
		for s in PartsDB.SLOTS:
			cond[s] = (bb.condition.get(s, {}) as Dictionary).duplicate()
			cond[s].merge(c[2].get(s, {}), true)
		m.build_from(bb, Color(0.7, 0.12, 0.1), {}, cond, false)
		m.position = Vector3(0.0, -m.foot_ground_y(), 0.0)
		cam.global_position = c[3]
		cam.look_at(c[4], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, c[0]])
		print("shot ", c[0])
		m.free()
	get_tree().quit()


## Every part's dirt after a ride: `mud` road-muck km and `flies` fly-km (see Dirt.accrue).
func _ridden(mud: float, flies: float) -> Dictionary:
	var out := {}
	for s in PartsDB.SLOTS:
		var it := {"dirt": 0.0}
		Dirt.accrue(it, s, mud, flies, float(Shed.DIRT_EXPOSURE.get(s, 0.4)), 1.0)
		if float(it.get("dirt", 0.0)) > 0.0:
			out[s] = it
	return out

