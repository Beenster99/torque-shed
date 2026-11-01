extends Node
## Rig built bodywork (H3) side on: each style's stock bike in the Rig built look, bare (no rider),
## with its tank, seat and tail fitted to the rig's lines, against the same bike with the bodywork
## placed the old way (RigBodywork.on off).
##   xvfb-run -a godot --path . res://tests/rig_body_shots.tscn -- --out=/tmp/rig [--styles=cafe,sport] [--provisional]
## --provisional makes up a rig from the old layout's datums (for before the bike rig, H1, is in).
## Writes <style>_rig.png and <style>_old.png.
var out_dir := "/tmp/rig"
var styles: Array = []
var provisional := false
var cam: Camera3D


func _ready() -> void:
	styles = Array(PartsDB.STYLES)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--styles="):
			styles = Array(a.trim_prefix("--styles=").split(","))
		elif a == "--provisional":
			provisional = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1000, 620)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.8, 0.83)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.9
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 60.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.9
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(4.0, 0.75, 0.0)
	cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	for style in styles:
		for with_rig in [true, false]:
			var m := BikeModel.new()
			m.look = BikeLook.NEW
			add_child(m)
			var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
			RigBodywork.on = with_rig
			if with_rig and provisional:
				m._lay_out(build)
				m.rig = provisional_rig(m, build)
			m.build_from(build, Color(0.7, 0.12, 0.1), {}, null, false)
			m.position = Vector3(0.0, -m.foot_ground_y(), 0.0)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, style, "rig" if with_rig else "old"])
			m.free()
	RigBodywork.on = true
	get_tree().quit()


## A stand-in for the bike rig's hand-over (lines agreement 3) from the old layout's datums.
static func provisional_rig(m: BikeModel, build: BikeBuild) -> Dictionary:
	var nose := m._head + Vector3(0.0, -0.07, 0.09)
	var rear := m._seat_front + Vector3(0.0, -0.02, 0.0)
	var floor_line := PackedVector3Array()
	for i in 9:
		floor_line.append(nose.lerp(rear, i / 8.0))
	var rails_a := Vector3(0.0, m._seat_y - 0.1, m._seat_front.z)
	var rails_b := Vector3(0.0, m._tail.y - 0.08, m._tail.z)
	return {"spine": floor_line, "tank_floor": floor_line, "tank_nose": nose, "tank_rear": rear,
		"tank_top_max": m._head.y + 0.04, "tunnel_half_w": 0.02, "knee_r": Vector3(0.12, rear.y + 0.05, rear.z - 0.12),
		"knee_l": Vector3(-0.12, rear.y + 0.05, rear.z - 0.12), "seat_rails": [rails_a, rails_b], "rail_half_w": 0.1,
		"seat_surface": Vector3(0.0, build.seat_height - build.rear_radius, m._seat_front.z + 0.18), "tail": m._tail + Vector3(0.0, 0.0, 0.3)}
