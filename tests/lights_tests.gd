extends RefCounted
## Headlights, fog lamps and the graphics settings from v0.15.1 (the upscaler switched off, avatar
## shadows), run from tests/run_tests.gd: its _test_lights_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## The headlight spreads wide enough to light the verges and main beam reaches well down the road;
## on main beam the wide flood round it no longer stops short of the core (which drew an arc of
## darkness across the road about 20 m ahead); and the lights reach every layer the scenery's on.
func test_beams() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	t.add_child(sun)
	var dl := Daylight.new()
	t.add_child(dl)
	var cycle := Settings.day_night_cycle
	Settings.day_night_cycle = false
	dl.setup(env, sun)
	dl.set_time(0.0)
	var fx := BikeEffects.new()
	t.add_child(fx)
	fx.setup(Vector3(0.2, 0.4, 0.8), Vector3(0.0, 0.0, 0.7), Vector3(0.0, 1.0, -0.8), 1000.0)
	var core: SpotLight3D = fx._beam
	var flood: SpotLight3D = fx._flood
	fx.beam_mode = 1
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	var low := core.spot_range
	# Dipped is aimed down at the near road with a cut-off (see tests/beam_tests.gd for the rest).
	check(low >= 50.0 and core.light_projector != null, "dipped beam reaches %.0f m, cut off above" % low)
	check(core.spot_angle >= 30.0 and flood.spot_angle >= 55.0, "and spreads wide: %.0f degrees, the flood %.0f" % [core.spot_angle, flood.spot_angle])
	check(core.spot_attenuation < 1.0, "the core fades slowly with distance, so the road's lit well ahead (%.2f)" % core.spot_attenuation)
	fx.beam_mode = 2
	fx.update(0.016, 10.0, 0.3, true, 1.0, "tarmac", true, 0.0)
	check(core.spot_range >= 180.0 and core.spot_range > low * 1.5 and core.rotation.x > deg_to_rad(-1.0),
		"main beam reaches %.0f m, aimed nearly level" % core.spot_range)
	check(flood.spot_range >= core.spot_range * 0.85 and flood.spot_range > 60.0,
		"on main beam the flood carries on nearly as far as the core (%.0f of %.0f m): no edge 20 m ahead" % [flood.spot_range, core.spot_range])
	for l: Light3D in [core, flood]:
		var what := "the flood" if l == flood else "the core"
		check((l.light_cull_mask & 0xFFFFF) == 0xFFFFF, "%s lights every layer, the scenery's too" % what)
		check(not l.shadow_enabled, "%s casts no shadows (keeps the cost down)" % what)
		check(l.light_projector == null, "on main beam %s has no projector shrinking its pool to the middle of the cone" % what)
	fx.queue_free()
	# The fog lamps: low, very wide, reaching well up the road and the verges.
	var b := BikeBuild.new({"fog_lights": "halogen_spots"})
	var model := BikeModel.new()
	t.add_child(model)
	model.build_from(b, Color(0.5, 0.5, 0.5))
	var holder := Node3D.new()
	t.add_child(holder)
	var fog := Bike.make_fog_lights(holder, model, b)
	check(not fog.is_empty(), "the bike has %d fog lamps" % fog.size())
	for l: SpotLight3D in fog:
		check(l.spot_range >= 40.0 and l.spot_angle >= 45.0 and (l.light_cull_mask & 0xFFFFF) == 0xFFFFF and not l.shadow_enabled
			and l.light_projector == null,
			"a fog lamp reaches %.0f m and spreads %.0f degrees, lighting every layer, no shadows" % [l.spot_range, l.spot_angle])
	model.queue_free()
	holder.queue_free()
	Settings.day_night_cycle = cycle
	dl.queue_free()
	sun.queue_free()
	await _frames(2)


## Upscaler off: the 3D view renders at the window's own resolution with nothing scaled, whatever
## the render scale; it's offered in the Graphics tab and saved with the rest.
func test_upscaler_off() -> void:
	var was := [Settings.gfx_upscaler, Settings.gfx_render_scale, Settings.gfx_preset]
	var vp := SubViewport.new()
	t.add_child(vp)
	Settings.set_graphics("gfx_render_scale", 0.6)
	Settings.set_graphics("gfx_upscaler", "fsr2")
	Graphics.apply_viewport(vp)
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and is_equal_approx(vp.scaling_3d_scale, 0.6),
		"at 60%% with FSR 2.2 the view is upscaled (scale %.2f)" % vp.scaling_3d_scale)
	Settings.set_graphics("gfx_upscaler", "off")
	check(Settings.gfx_upscaler == "off" and Settings.gfx_preset == "custom", "the upscaler can be switched off (preset now custom)")
	Graphics.apply_viewport(vp)
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and is_equal_approx(vp.scaling_3d_scale, 1.0),
		"off: native resolution, nothing scaled (scale %.2f), whatever the render scale" % vp.scaling_3d_scale)
	Settings.save_settings()
	Settings.gfx_upscaler = "fsr1"
	Settings.load_settings()
	check(Settings.gfx_upscaler == "off", "and it's saved and loaded like the other settings")
	var tab := GraphicsTab.new()
	t.add_child(tab)
	var ob: OptionButton = tab._controls["gfx_upscaler"]["control"]
	var values: Array = tab._controls["gfx_upscaler"]["values"]
	var slider: HSlider = tab._controls["gfx_render_scale"]["control"]
	check(values.has("off") and ob.selected == values.find("off") and not slider.editable,
		"the Graphics tab offers Off next to the upscalers, with the render scale greyed out")
	ob.select(values.find("fsr1"))
	ob.item_selected.emit(values.find("fsr1"))
	check(Settings.gfx_upscaler == "fsr1" and slider.editable, "picking FSR 1 again brings the render scale back")
	tab.queue_free()
	vp.queue_free()
	Settings.gfx_upscaler = was[0]
	Settings.gfx_render_scale = was[1]
	Settings.gfx_preset = was[2]
	Settings.save_settings()
	await _frames(2)


## Avatar shadow: one switch for whether people cast shadows (you and the other players on foot
## and riding, staff, customers and the townsfolk), put on every figure at once, saved, and their
## own shadow settings back when it's on again.
func test_avatar_shadows() -> void:
	var was := Settings.gfx_avatar_shadows
	Settings.set_graphics("gfx_avatar_shadows", true)
	var holder := Node3D.new()
	t.add_child(holder)
	var player := RiderFigure.make({}, Color(0.8, 0.2, 0.2))
	holder.add_child(player)
	var staff := StaffFigure.new()
	staff.build({"id": 9, "name": "Pat", "role": "mechanic"})
	holder.add_child(staff)
	var model := BikeModel.new()
	model.rider_color = Color(0.2, 0.4, 0.8)
	holder.add_child(model)
	model.build_from(BikeBuild.new(), Color(0.5, 0.5, 0.5))
	var plain := MeshInstance3D.new()
	plain.mesh = BoxMesh.new()
	holder.add_child(plain)
	var people: Array[GeometryInstance3D] = []
	var roots: Array[Node] = [player, staff, model._rider]
	for i in roots.size():
		var found := roots[i].find_children("*", "MeshInstance3D", true, false)
		check(not found.is_empty(), "%s is drawn (%d meshes)" % [["a player", "a member of staff", "a rider on a bike"][i], found.size()])
		for g in found:
			people.append(g)
	var casting := func() -> int:
		var n := 0
		for g in people:
			if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				n += 1
		return n
	var all_on: int = casting.call()
	check(all_on > people.size() * 0.8, "with Avatar shadow on, figures cast shadows (%d of %d meshes)" % [all_on, people.size()])
	check(people.all(func(g): return g.is_in_group(Graphics.AVATAR_GROUP)), "every mesh of a player, staff member and rider is a figure's")
	Settings.set_graphics("gfx_avatar_shadows", false)
	await _frames(1)
	check(casting.call() == 0, "switched off, none of them do (%d)" % casting.call())
	check(plain.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the rest of the world still does")
	var late := RiderFigure.make({}, Color(0.1, 0.8, 0.2))
	holder.add_child(late)
	check(late.find_children("*", "MeshInstance3D", true, false).all(func(g): return g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
		"a figure dressed while it's off casts none either")
	Settings.save_settings()
	Settings.gfx_avatar_shadows = true
	Settings.load_settings()
	check(not Settings.gfx_avatar_shadows, "the setting is saved and loaded like the others")
	Settings.set_graphics("gfx_avatar_shadows", true)
	await _frames(1)
	check(casting.call() == all_on, "on again, each casts as it did before (%d)" % casting.call())
	var tab := GraphicsTab.new()
	t.add_child(tab)
	check(tab._controls.has("gfx_avatar_shadows") and (tab._controls["gfx_avatar_shadows"]["control"] as CheckBox).button_pressed,
		"the Graphics tab has the switch, ticked")
	tab.queue_free()
	holder.queue_free()
	Settings.gfx_avatar_shadows = was
	Settings.save_settings()
	await _frames(2)


## The far countryside round the town has no holes: where a near chunk of land meets a far one,
## each one's skirt hangs below the other's edge all the way along (in the mountains the far
## mesh's edge can rise metres above the near one's between its samples, and the sky showed
## through), and the two levels of detail of a chunk switch over at the same distance.
func test_far_terrain() -> void:
	var world := World.new()
	t.add_child(world)
	world.generate(1234)
	await t.get_tree().physics_frame
	var terr := world.terrain
	var count := WorldTerrain.chunk_count()
	var slits := 0
	var worst_old := 0.0
	for cz in count:
		for cx in count:
			var near := terr.chunk_mesh(cx, cz, 1)
			var far := terr.chunk_mesh(cx, cz, WorldTerrain.COARSE)
			var nv: PackedVector3Array = near.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var fv: PackedVector3Array = far.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var np := WorldTerrain.CHUNK + 1
			var fp := WorldTerrain.CHUNK / WorldTerrain.COARSE + 1
			for e in 4:
				var fixed_n := 0 if e % 2 == 0 else np - 1
				var fixed_f := 0 if e % 2 == 0 else fp - 1
				var rows := e < 2   # edges 0 and 1 run along a row, 2 and 3 along a column
				var n_drop := nv[(fixed_n * np if rows else fixed_n)].y - nv[np * np + e * np].y
				var f_drop := fv[(fixed_f * fp if rows else fixed_f)].y - fv[fp * fp + e * fp].y
				for q in np:
					var nh := nv[fixed_n * np + q if rows else q * np + fixed_n].y
					var u := float(q) / WorldTerrain.COARSE
					var a := mini(int(u), fp - 2)
					var fa := fv[fixed_f * fp + a if rows else a * fp + fixed_f].y
					var fb := fv[fixed_f * fp + a + 1 if rows else (a + 1) * fp + fixed_f].y
					var fh := lerpf(fa, fb, u - a)
					worst_old = maxf(worst_old, absf(fh - nh) - WorldTerrain.SKIRT)
					if fh - f_drop > nh + 0.01 or nh - n_drop > fh + 0.01:
						slits += 1
	check(worst_old > 0.0, "the far land's edge parts from the near land's by more than the old skirt somewhere (%.1f m more)" % worst_old)
	check(slits == 0, "but every edge's skirt now hangs below its neighbour's all the way along (%d slits)" % slits)
	var lod_pairs := 0
	var same_box := 0
	var meshes := world.find_child("TerrainMesh", true, false)
	var kids := meshes.get_children() if meshes else []
	for i in range(0, kids.size() - 1, 2):
		var a := kids[i] as MeshInstance3D
		var b := kids[i + 1] as MeshInstance3D
		if a == null or b == null:
			continue
		lod_pairs += 1
		if a.custom_aabb == b.custom_aabb and a.custom_aabb.size != Vector3.ZERO \
				and is_equal_approx(a.visibility_range_end, b.visibility_range_begin):
			same_box += 1
	check(lod_pairs == count * count and same_box == lod_pairs,
		"each chunk's near and far meshes share one box and hand over at one distance (%d of %d)" % [same_box, lod_pairs])
	world.queue_free()
	await _frames(2)


const KIT := {"frame": "adv_trellis", "panniers": "adv_alloy_black", "top_box": "adv_black_top_42", "tank_bag": "rally_tank_bag",
	"aux_tank": "rear_rally_tank_10", "toolbox": "alloy_toolbox", "satnav": "adventure_gps", "fairing": "adv_tall_screen_adj",
	"fog_lights": "halogen_spots"}


## An adventure bike with all its kit, muddy, as it's drawn left at a fuel station (whole, with its
## pickers) and ridden (merged meshes): every surface keeps a real facing and stays rough enough
## not to glare, and none of the bike's own lamps lights the air at its lens (in the volumetric
## fog a lamp right at its lens can blow up into a white glow round the bike).
func test_kit_bike_materials() -> void:
	Shed.start_new("Tester", 7)
	var parts: Dictionary = Shed.build_of(t._bike_named("Old Faithful")).parts.duplicate()
	parts.merge(KIT, true)
	var cond := {}
	for slot in parts:
		cond[slot] = {"dirt": 0.6, "rust": 0.2, "wear": 0.1}
	for baked in [false, true]:
		var m := BikeModel.new()
		m.baked = baked
		t.add_child(m)
		m.build_from(BikeBuild.new(parts, cond), Color(0.75, 0.62, 0.45), {}, cond, baked)
		if not baked:
			m.build_pickers({"bike": 1})
		var meshes := 0
		var bad_normals := 0
		var glare := []
		var seen := {}
		for n in m.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			meshes += 1
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var nrm = arr[Mesh.ARRAY_NORMAL]
				if nrm is PackedVector3Array:
					for v in (nrm as PackedVector3Array):
						if not (v.length() > 0.5):
							bad_normals += 1
				var mat := mi.get_active_material(si)
				while mat != null and not seen.has(mat):
					seen[mat] = true
					if mat is BaseMaterial3D and (mat as BaseMaterial3D).roughness < BikeModel.MIN_ROUGHNESS - 0.001:
						glare.append(str(mi.name))
					mat = mat.next_pass
		var kind := "ridden (merged)" if baked else "parked at the roadside"
		check(meshes > 100 and bad_normals == 0, "%s: %d meshes, every vertex facing somewhere (%d without)" % [kind, meshes, bad_normals])
		check(glare.is_empty(), "%s: nothing smoother than the glare limit %s" % [kind, str(glare)])
		m.queue_free()
	var holder := Node3D.new()
	t.add_child(holder)
	var b := BikeBuild.new(parts)
	var model := BikeModel.new()
	holder.add_child(model)
	model.build_from(b, Color(0.5, 0.5, 0.5))
	var fog := Bike.make_fog_lights(holder, model, b)
	var fx := BikeEffects.new()
	holder.add_child(fx)
	fx.setup(Vector3(0.2, 0.4, 0.8), Vector3(0.0, 0.0, 0.7), Vector3(0.0, 1.0, -0.8), 1000.0)
	fx.update(0.016, 0.0, 0.0, true, 1.0, "tarmac", true, 0.0)
	check(not fog.is_empty() and fog.all(func(l): return l.light_volumetric_fog_energy == 0.0) and fx._lamp_glow.light_volumetric_fog_energy == 0.0,
		"the fog lamps and the glow at the headlamp's lens keep out of the volumetric fog")
	holder.queue_free()
	Shed.stop()
	await _frames(2)
