extends Node
## The skyline's models (scripts/scenery/skyline.gd) side by side, by day and by night, with their wires:
##   xvfb-run -a godot --path . res://tests/skyline_shots.tscn -- --out=/tmp/skyline
## Three line-ups: the tall things (turbines, masts, cooling towers, the pylons of each region with their wires), the
## towers and tanks (each region's water tower, silos, minarets, bell towers), and the small things (poles, lifts and
## their cabins, yards, panels). Each as sky_*.png and night_*.png.

var out_dir := "/tmp/skyline"

const LINEUPS := {
	"tall": {"models": ["turbine", "tv_tower", "mast", "cooling", "pylon", "pylon_danube", "pylon_wide", "pylon_tall", "radar"],
		"gap": 70.0, "eye": Vector3(260.0, 45.0, 330.0), "look": Vector3(260.0, 55.0, 0.0)},
	"towers": {"models": ["water_tower", "water_sphere", "water_chalice", "water_square", "silo", "silo_blue", "elevator",
		"tank", "gasometer", "minaret", "minaret_square", "minaret_dome", "campanile", "bell_pavilion", "round_tower",
		"lookout", "watchtower", "monopole", "floodlight"], "gap": 34.0, "eye": Vector3(300.0, 30.0, 190.0),
		"look": Vector3(300.0, 14.0, 0.0)},
	"small": {"models": ["pole", "pole_concrete", "pole_tel", "portal", "transformer", "kiosk", "solar_row", "lift_pylon",
		"lift_station", "lift_terminal", "piste_pole"], "gap": 16.0, "eye": Vector3(80.0, 9.0, 55.0),
		"look": Vector3(80.0, 5.0, 0.0)},
}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1600, 800)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 150.0, 0.0)   # (from over the camera's shoulder)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	env.environment.sky.sky_material = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.42, 0.22)
	plane.material = gm
	ground.mesh = plane
	add_child(ground)
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	for when in ["sky", "night"]:
		for name: String in LINEUPS:
			var lineup: Dictionary = LINEUPS[name]
			var holder := Node3D.new()
			add_child(holder)
			var w := Skyline._Wires.new()
			var models: Array = lineup["models"]
			var gap := float(lineup["gap"])
			for i in models.size():
				var m: String = models[i]
				var mi := MeshInstance3D.new()
				mi.mesh = Skyline.mesh(m)
				var at := Vector3(i * gap, 0.0, 0.0)
				var basis := Basis()
				match m:
					"tank":
						basis = basis.scaled(Vector3(8, 9, 8))
					"gasometer":
						basis = basis.scaled(Vector3(0.5, 0.6, 0.5))
					"turbine":
						basis = Basis(Vector3.UP, Skyline._yaw(-Vector2(0, -1)))   # (facing the camera)
						basis = basis.scaled(Vector3.ONE * 0.7)
				mi.transform = Transform3D(basis, at)
				holder.add_child(mi)
				if m == "steam":
					continue
				if m == "cooling":
					var steam := MeshInstance3D.new()
					steam.mesh = Skyline.mesh("steam")
					steam.transform = mi.transform
					holder.add_child(steam)
				# (each support with a span of wire off to the back, as on a line)
				if Skyline.SUPPORTS.has(m):
					var a := Transform3D(Basis(Vector3.UP, Skyline._yaw(Vector2(0, -1))), at)
					var b := Transform3D(a.basis, at + Vector3(0, 0, -260.0 if gap > 30.0 else -60.0))
					var b_mi := MeshInstance3D.new()
					b_mi.mesh = mi.mesh
					b_mi.transform = b
					holder.add_child(b_mi)
					for wire: Vector3 in Skyline.SUPPORTS[m]["wires"]:
						var span := (a * wire).distance_to(b * wire)
						w.catenary(a * wire, b * wire, span * (0.03 if gap > 30.0 else 0.015), 0.03, Color(0.23, 0.24, 0.25))
			if name == "small":
				for cabin: String in ["gondola", "chair", "cable_car", "tbar"]:
					var c := MeshInstance3D.new()
					c.mesh = Skyline.mesh(cabin)
					c.position = Vector3(models.find("lift_pylon") * gap + 2.6, 15.0, -10.0 - 9.0 * ["gondola", "chair", "cable_car", "tbar"].find(cabin))
					holder.add_child(c)
			if w.count > 0:
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, w.arrays())
				mesh.surface_set_material(0, Skyline.material())
				var wm := MeshInstance3D.new()
				wm.mesh = mesh
				holder.add_child(wm)
			cam.position = lineup["eye"]
			cam.look_at(lineup["look"], Vector3.UP)
			var night: bool = when == "night"
			sun.light_energy = 0.03 if night else 1.2
			sky.sky_top_color = Color(0.01, 0.015, 0.04) if night else Color(0.38, 0.45, 0.6)
			sky.sky_horizon_color = Color(0.03, 0.04, 0.08) if night else Color(0.65, 0.7, 0.75)
			sky.ground_horizon_color = sky.sky_horizon_color
			env.environment.ambient_light_energy = 0.15 if night else 1.0
			Skyline.material().set_shader_parameter("night", 1.0 if night else 0.0)
			Skyline.material().set_shader_parameter("blink", 1.0)
			Skyline.material().set_shader_parameter("spin", 0.4)
			Skyline._steam_material().set_shader_parameter("night", 1.0 if night else 0.0)
			for i in 6:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [when, name]))
			print("saved %s_%s" % [when, name])
			holder.queue_free()
			await get_tree().process_frame
	get_tree().quit()
