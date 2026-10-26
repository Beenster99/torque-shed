extends RefCounted
## The live bike mirrors from v0.16.0 (BikeMirrors and the Mirror detail setting), run from
## tests/run_tests.gd: its _test_mirrors_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## A ridden bike with a pair of `mirrors`, its live mirrors and a first-person eye at the
## rider's: {"root", "bike", "mirrors", "cam"}.
func _rig(mirrors := "round_mirrors") -> Dictionary:
	var root := Node3D.new()
	t.add_child(root)
	var bike := Bike.new()
	bike.setup(BikeBuild.new({"mirrors": mirrors}))
	root.add_child(bike)
	bike.place(Vector3.ZERO, 0.0)
	# Held where it is, its bars where the test puts them; the mirrors still run.
	bike.freeze = true
	bike.process_mode = Node.PROCESS_MODE_DISABLED
	var bm := BikeMirrors.new()
	bm.process_mode = Node.PROCESS_MODE_ALWAYS
	bike.add_child(bm)
	# A world look with everything on, for the mirrors to make their cheap copy of.
	var env := Environment.new()
	env.sdfgi_enabled = true
	env.volumetric_fog_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 80.0
	root.add_child(cam)
	cam.current = true
	cam.global_transform = bike.model.global_transform * bike.model.eye_transform()
	return {"root": root, "bike": bike, "mirrors": bm, "cam": cam}


## Mirror detail: Off then Low to Ultra, Medium to start with; saved and loaded with the other
## graphics settings, part of the presets, a slider on the Graphics tab, and each level puts its
## picture size, frame rate and reach on the mirrors.
func test_setting() -> void:
	var had := FileAccess.file_exists(Settings.PATH)
	var before := FileAccess.get_file_as_string(Settings.PATH) if had else ""
	var keep := {}
	for k in Settings.GFX_KEYS:
		keep[k] = Settings.get(k)
	check(Settings.GFX_KEYS.has("gfx_mirrors") and Graphics.CHOICES["gfx_mirrors"] == ["off", "low", "medium", "high", "ultra"],
		"Mirror detail is a graphics setting: Off, Low, Medium, High, Ultra")
	check(Graphics.PRESETS["low"]["gfx_mirrors"] == "off" and Graphics.PRESETS["high"]["gfx_mirrors"] == "medium"
		and Graphics.PRESETS["ultra"]["gfx_mirrors"] == "ultra", "the presets set it (Low off, High medium, Ultra ultra)")
	Settings.apply_preset("high")
	check(Settings.gfx_mirrors == "medium", "the High preset (the default) has them at Medium")
	Settings.set_graphics("gfx_mirrors", "mirrorball")
	check(Settings.gfx_mirrors == "medium" and Settings.gfx_preset == "high", "a level it hasn't got is ignored")
	Settings.set_graphics("gfx_mirrors", "ultra")
	check(Settings.gfx_mirrors == "ultra" and Settings.gfx_preset == "custom", "changing it makes the preset Custom")
	Settings.save_settings()
	Settings.gfx_mirrors = "low"
	Settings.load_settings()
	check(Settings.gfx_mirrors == "ultra", "it's saved and loaded like the others (%s)" % Settings.gfx_mirrors)
	# The Graphics tab's slider.
	var tab := GraphicsTab.new()
	t.add_child(tab)
	var c: Dictionary = tab._controls.get("gfx_mirrors", {})
	var slider: HSlider = c.get("control")
	check(slider != null and slider.max_value == 4.0 and slider.value == 4.0 and (c["text"] as Label).text == "Ultra",
		"the Graphics tab has a Mirror detail slider, at Ultra")
	slider.value = 0.0
	check(Settings.gfx_mirrors == "off" and (c["text"] as Label).text == "Off", "slid right down, it's Off")
	slider.value = 2.0
	check(Settings.gfx_mirrors == "medium" and (c["text"] as Label).text == "Medium", "and back up to Medium")
	tab.queue_free()
	# Each level on the mirrors.
	var rig := _rig()
	var bm: BikeMirrors = rig["mirrors"]
	await _frames(2)
	var heights := []
	var reach := []
	for lv in ["low", "medium", "high", "ultra"]:
		Settings.set_graphics("gfx_mirrors", lv)
		await _frames(1)
		var cfg: Dictionary = BikeMirrors.LEVELS[lv]
		var ok: bool = bm.views.size() == 2 and bm.level == lv
		for v in bm.views:
			var vp: SubViewport = v["vp"]
			ok = ok and vp.size.y <= int(cfg["px"]) and vp.msaa_3d == int(cfg["msaa"]) \
				and is_equal_approx((v["cam"] as Camera3D).far, float(cfg["far"])) \
				and vp.positional_shadow_atlas_size == int(cfg["shadows"]) and vp.use_hdr_2d
		heights.append(int(cfg["px"]))
		reach.append(float(cfg["far"]))
		check(ok, "at %s both mirrors get a %d px picture at most, %d m of reach and its effects" % [lv, cfg["px"], cfg["far"]])
	check(heights == [128, 192, 256, 384] and reach == [150.0, 300.0, 500.0, 900.0], "each level up is sharper and sees further")
	check(int(BikeMirrors.LEVELS["low"]["every"]) == 3 and int(BikeMirrors.LEVELS["medium"]["every"]) == 2
		and int(BikeMirrors.LEVELS["high"]["every"]) == 1, "Low draws them every third frame, Medium every other, High every frame")
	# Low: the two take turns, a third of the frames each.
	Settings.set_graphics("gfx_mirrors", "low")
	await _frames(1)
	var drawn := 0
	for i in 12:
		await _frames(1)
		drawn += bm.drawn
	check(bm.in_sight == 2 and drawn == 8, "at Low each mirror is drawn every third frame (%d draws in 12 frames)" % drawn)
	Settings.set_graphics("gfx_mirrors", "high")
	await _frames(1)
	drawn = 0
	for i in 6:
		await _frames(1)
		drawn += bm.drawn
	check(drawn == 12, "at High both every frame (%d in 6)" % drawn)
	var env: Environment = (bm.views[0]["cam"] as Camera3D).environment
	check(env != null and not env.sdfgi_enabled and not env.volumetric_fog_enabled and not env.ssr_enabled
		and not env.glow_enabled and env.tonemap_mode == Environment.TONE_MAPPER_LINEAR,
		"drawn with a cheap environment: no GI, volumetrics, reflections or glow, left linear for the main view")
	var mask := (bm.views[0]["cam"] as Camera3D).cull_mask
	check(mask & (1 << (BikeModel.HELMET_LAYER - 1)) == 0 and mask & (1 << (BikeMirrors.GLASS_LAYER - 1)) == 0 and mask & 1 != 0,
		"their cameras leave out the rider's head and body and the glass, and see the world")
	(rig["root"] as Node).queue_free()
	for k in keep:
		Settings.set(k, keep[k])
	if had:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(before)
		f.close()
	Settings.graphics_changed.emit()
	await _frames(2)


## The mirror camera sits at the eye reflected through the glass and looks back through it, the
## picture's near plane on the glass; a point behind the bike seen in the glass is where the
## picture shows it; and it follows the glass as the bars turn and as the world's origin moves.
func test_follows_glass() -> void:
	var was := Settings.gfx_mirrors
	Settings.set_graphics("gfx_mirrors", "high")
	# The maths alone: an eye in front of a glass facing +Z.
	var frame := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.4, 1.0, -0.5))
	var eye := Vector3(0.0, 1.3, 0.2)
	var view := BikeMirrors.mirror_view(eye, frame, Vector2(0.1, 0.1))
	var n := frame.basis.z
	var xf: Transform3D = view["xf"]
	var mid := (xf.origin + eye) * 0.5
	check(absf((mid - frame.origin).dot(n)) < 1e-4 and (xf.origin - eye).normalized().cross(n).length() < 1e-4,
		"the camera is the eye reflected through the glass's plane")
	check((-xf.basis.z).dot(n) > 0.9999 and is_equal_approx(float(view["near"]), (eye - frame.origin).dot(n)),
		"looking back through the glass, the near plane on the glass")
	check(BikeMirrors.mirror_view(frame.origin - n * 0.3, frame, Vector2(0.1, 0.1)).is_empty(), "nothing from behind the glass")
	var rig := _rig("sport_mirrors")
	var bike: Bike = rig["bike"]
	var bm: BikeMirrors = rig["mirrors"]
	var cam: Camera3D = rig["cam"]
	await _frames(3)
	check(bm.views.size() == 2 and bm.in_sight == 2, "from the saddle both mirrors are in sight (%d of %d)" % [bm.in_sight, bm.views.size()])
	var right := 0 if (bm.views[0]["frame"] as Node3D).global_position.x > 0.0 else 1
	var side_view: Dictionary = bm.views[right]
	var face := (side_view["frame"] as Node3D).global_transform
	check(face.basis.z.dot(Vector3(0, 0, 1)) > 0.8 and face.basis.z.x < 0.0,
		"the right-hand mirror faces back at the rider, turned in towards them")
	# The reflection maths through the live camera: points across the glass, and what's behind.
	var errors := []
	var behind := []
	var glass: MeshInstance3D = side_view["glass"]
	var to_frame := (side_view["frame"] as Node3D).transform.affine_inverse() * glass.transform
	var rows := BikeMirrors.uv_rows(to_frame, side_view["size"])
	var mcam: Camera3D = side_view["cam"]
	var vp: SubViewport = side_view["vp"]
	var size: Vector2 = side_view["size"]
	for a in [Vector2(0.0, 0.0), Vector2(0.3, 0.2), Vector2(-0.35, 0.1), Vector2(0.2, -0.3)]:
		var on_glass := face * Vector3(a.x * size.x, a.y * size.y, 0.0)
		var p_mesh := to_frame.affine_inverse() * Vector3(a.x * size.x, a.y * size.y, 0.0)
		var uv := BikeMirrors.uv_of(rows, p_mesh)
		var d := (on_glass - cam.global_position).normalized()
		var out := d - 2.0 * d.dot(face.basis.z) * face.basis.z
		var far_point := on_glass + out * 25.0
		var seen := mcam.unproject_position(far_point) / Vector2(vp.size)
		errors.append(snappedf(seen.distance_to(uv), 0.001))
		behind.append(snappedf(out.z, 0.01))
	check(errors.all(func(e): return e < 0.01), "a point behind seen in the glass is where the picture puts it (UV errors %s)" % str(errors))
	check(behind.all(func(z): return z > 0.7), "and the glass looks back down the road behind (%s)" % str(behind))
	var corner := face * Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	var c_uv := mcam.unproject_position(corner + (corner - mcam.global_position).normalized() * 0.0001) / Vector2(vp.size)
	check(c_uv.distance_to(Vector2(0.0, 0.0)) < 0.03, "the glass's corner is the picture's corner, flipped across (%s)" % str(c_uv))
	# Steering: the glass turns with the bars, and the camera with it.
	var before := mcam.global_transform
	bike.model.update_pose_from(0.35, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	await _frames(2)
	var turned := (side_view["frame"] as Node3D).global_transform
	var want := BikeMirrors.mirror_view(cam.global_position, turned, size)
	check(turned.origin.distance_to(face.origin) > 0.03 and mcam.global_transform.origin.distance_to(before.origin) > 0.03
		and mcam.global_transform.origin.distance_to((want["xf"] as Transform3D).origin) < 1e-3,
		"turning the bars swings the glass, and its camera follows (%.3f m)" % mcam.global_transform.origin.distance_to(before.origin))
	bike.model.update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	await _frames(1)
	# A floating-origin shift: everything moves together, and the camera stays put on the glass.
	var rel := (side_view["frame"] as Node3D).global_transform.affine_inverse() * mcam.global_transform
	var shift := Vector3(-4000.0, 0.0, 2500.0)
	bike.global_position += shift
	cam.global_position += shift
	await _frames(2)
	var rel2 := (side_view["frame"] as Node3D).global_transform.affine_inverse() * mcam.global_transform
	check(rel2.origin.distance_to(rel.origin) < 0.01, "after the origin moves 4.7 km it's still the same view in the glass")
	# The glass shows the picture; another rider's bike (RemoteBike) keeps plain glass.
	check(glass.material_override is ShaderMaterial and glass.layers == 1 << (BikeMirrors.GLASS_LAYER - 1),
		"the glass shows the live picture, on a layer of its own")
	var other := RemoteBike.new()
	check(BikeMirrors.of(other) == null, "other riders' bikes have no live mirrors")
	other.free()
	# Looking away (head turned right round), neither is drawn.
	cam.global_basis = cam.global_basis * Basis(Vector3.UP, PI)
	await _frames(2)
	check(bm.in_sight == 0 and bm.drawn == 0, "looking the other way, nothing is drawn (%d)" % bm.drawn)
	(rig["root"] as Node).queue_free()
	Settings.set_graphics("gfx_mirrors", was)
	await _frames(2)


## Off: no viewports and nothing done each frame, the glass its plain shiny self again.
func test_off() -> void:
	var was := Settings.gfx_mirrors
	Settings.set_graphics("gfx_mirrors", "medium")
	var rig := _rig()
	var bm: BikeMirrors = rig["mirrors"]
	await _frames(2)
	var glass: MeshInstance3D = bm.views[0]["glass"]
	check(bm.live() and bm.find_children("*", "SubViewport", true, false).size() == 2, "on, each mirror has a viewport")
	Settings.set_graphics("gfx_mirrors", "off")
	await _frames(2)
	var mat := glass.material_override as StandardMaterial3D
	check(not bm.live() and bm.views.is_empty() and bm.find_children("*", "SubViewport", true, false).is_empty(),
		"Off, the viewports are gone")
	check(not bm.is_processing(), "and it does nothing each frame")
	check(mat != null and mat.metallic > 0.9 and glass.layers == 1, "the glass is the plain shiny material again")
	var was_on := Perf.on
	Perf.on = true
	Perf.shown = {}
	Perf._frame.clear()
	await _frames(3)
	check(not Perf._frame.has("mirrors") and not Perf._frame.has("mirrors_gpu"), "the profiler sees nothing from it")
	Perf.on = was_on
	(rig["root"] as Node).queue_free()
	Settings.set_graphics("gfx_mirrors", was)
	await _frames(2)
