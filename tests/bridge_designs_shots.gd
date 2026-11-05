extends Node
## Pictures of the ten bridge designs (BridgeKit), each built on a made-up crossing that suits it, from three-quarters
## on and beside:
##   xvfb-run -a godot --path . res://tests/bridge_designs_shots.tscn -- --out=/tmp/shots [--only=truss,lift]

var out_dir := "/tmp/shots"
var only: PackedStringArray = []

## design -> [length (m), the deck over the land's lowest (m), water under it, the valley's shape ("u", "v" or "flat")]
const CASES := {
	"stone_arch": [60.0, 12.0, true, "u"], "viaduct": [420.0, 45.0, false, "u"], "girder": [40.0, 7.0, false, "flat"],
	"truss": [180.0, 9.0, true, "u"], "bowstring": [140.0, 9.0, true, "u"], "gorge_arch": [260.0, 90.0, false, "v"],
	"cable_stayed": [420.0, 25.0, true, "u"], "suspension": [1200.0, 40.0, true, "u"], "covered": [40.0, 5.0, true, "u"],
	"lift": [30.0, 3.5, true, "flat"],
}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(960, 540)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2500.0
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()
	for design: String in CASES:
		if not only.is_empty() and not design in only:
			continue
		var c: Array = CASES[design]
		var scene := _scene(design, float(c[0]), float(c[1]), bool(c[2]), str(c[3]))
		add_child(scene)
		var length := float(c[0])
		var mid := Vector3(0.0, 30.0 - float(c[1]) * 0.4, 0.0)
		var dist := maxf(length * 0.75, 45.0)
		for view: String in ["three", "side", "road"]:
			var eye := mid + (Vector3(-length * 0.45, float(c[1]) * 0.3 + 4.0, dist) if view == "three" else Vector3(0.0, 2.0, dist * 1.15))
			var look := mid
			if view == "road":
				# (as a rider sees it, riding on from 30 m short of it)
				eye = Vector3(-length * 0.5 - 30.0, 31.6, 1.8)
				look = Vector3(-length * 0.5 + 40.0, 33.0, 0.0)
			cam.look_at_from_position(eye, look)
			for f in 6:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, design, view])
		scene.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## A crossing `length` long along x, its deck at y 30, the land `drop` below it at its lowest, water in the bottom.
func _scene(design: String, length: float, drop: float, wet: bool, shape: String) -> Node3D:
	var root := Node3D.new()
	var land := func(x: float) -> float:
		var u := clampf(absf(x) / (length * 0.5), 0.0, 1.0)
		match shape:
			"v": return 30.0 - drop * (1.0 - u)
			"flat": return 30.0 - drop if absf(x) < length * 0.5 - 3.0 else 30.0
		return 30.0 - drop * (1.0 - pow(u, 6.0))
	var n := ceili(length / BridgeKit.DS) + 1
	var ds := length / float(n - 1)
	var pts := PackedVector3Array()
	var rights := PackedVector3Array()
	var ground := PackedFloat32Array()
	var wets := PackedFloat32Array()
	for i in n:
		var x := -length * 0.5 + ds * i
		pts.append(Vector3(x, 30.0, 0.0))
		rights.append(Vector3(0.0, 0.0, 1.0))
		ground.append(land.call(x))
		wets.append(1.0 if wet and land.call(x) < 30.0 - drop + 3.0 else 0.0)
	var e := 3.7
	var rec := BridgeKit.make(pts, rights, ground, wets, e + 0.45, AdventureRoute.BRIDGE_DEPTH,
		{"design": design, "roll": 0.3, "region": "western_europe"}, ds)
	var arr := AdventureProps.new_arrays()
	BridgeKit.draw(arr, rec, func(_s: float, _p: Vector3) -> bool: return true)
	for i in n - 1:
		for side: float in [-1.0, 1.0]:
			var r := Vector3(0.0, 0.0, side)
			BridgeKit.edge(arr, rec["edge"], pts[i] + r * e, pts[i + 1] + r * e, pts[i] + r * (e + 0.45),
				pts[i + 1] + r * (e + 0.45), AdventureChunk.PARAPET, AdventureRoute.BRIDGE_DEPTH)
		AdventureProps._quad(arr, pts[i] - Vector3(0, 0, e), pts[i] + Vector3(0, 0, e), pts[i + 1] + Vector3(0, 0, e),
			pts[i + 1] - Vector3(0, 0, e), Color(0.2, 0.2, 0.21))
		var dn := Vector3.DOWN * AdventureRoute.BRIDGE_DEPTH
		AdventureProps._quad(arr, pts[i] - Vector3(0, 0, e + 0.45) + dn, pts[i] + Vector3(0, 0, e + 0.45) + dn,
			pts[i + 1] + Vector3(0, 0, e + 0.45) + dn, pts[i + 1] - Vector3(0, 0, e + 0.45) + dn, Color(0.4, 0.4, 0.38))
	var mi := MeshInstance3D.new()
	mi.mesh = AdventureProps.to_mesh(arr)
	mi.material_override = AdventureChunk._bridge_material()
	root.add_child(mi)
	# The land either side and under it, and the water.
	var g := AdventureProps.new_arrays()
	var gx := length * 0.5 + 400.0
	var steps := 200
	for k in steps:
		var x0 := -gx + 2.0 * gx * k / steps
		var x1 := -gx + 2.0 * gx * (k + 1) / steps
		AdventureProps._quad(g, Vector3(x0, land.call(x0), 600.0), Vector3(x1, land.call(x1), 600.0),
			Vector3(x1, land.call(x1), -600.0), Vector3(x0, land.call(x0), -600.0), Color(0.33, 0.45, 0.25))
	if wet:
		var wy := 30.0 - drop + 2.0
		AdventureProps._quad(g, Vector3(-gx, wy, 600.0), Vector3(gx, wy, 600.0), Vector3(gx, wy, -600.0),
			Vector3(-gx, wy, -600.0), Color(0.2, 0.32, 0.42))
	var gm := MeshInstance3D.new()
	gm.mesh = AdventureProps.to_mesh(g)
	gm.material_override = AdventureChunk._bridge_material()
	root.add_child(gm)
	return root
