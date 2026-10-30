class_name BikeLookNew
## The new bike look's way of folding a ridden-past bike into few meshes (see BikeLook), in
## place of BikeModel._bake_static's, which the Classic look keeps. Classic merges a part's
## pieces only where they share a material, and a bike has well over a hundred: here every
## ordinary surface is drawn by the one bike shader (BikeShader) with what it looks like on its
## vertices, so all of them hanging from the same node become one mesh and one draw. Parts that
## carry something of their own after the bake (road dirt, a detailed finish, blasting, a
## geometry-mode offset) keep a mesh to themselves, so that still lands on just that part; and
## what the shader doesn't draw (glass, lamps, mirrors, tyre treads, painted-on effects) stays as
## Classic merges it.

## How sharp a crease the simplified levels of detail keep (degrees), as Godot's importer.
const LOD_ANGLE := 25.0
## Where the Bike detail setting's levels are measured (see BikeLook.stats): a mate's bike a few
## car lengths off and one far down the road, in metres at 1080p.
const NEAR := 30.0
const FAR := 120.0

## Per-vertex channels, all four floats wide (see BikeShader).
const CUSTOM_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)

## The finishes the bike shader adds its own detail to (see finish_of), as CUSTOM3.x.
enum Finish { PLAIN, PAINT, METAL_FLAKE, CHROME, ALLOY, BRUSHED, RUBBER, LEATHER, CARBON }
## How far from the head an exhaust header colours with heat, in metres, and how much heat a
## brand-new pipe shows (a worn one shows it all).
const HEAT_REACH := 0.3
const HEAT_NEW := 0.35


## Merges `model`'s still pieces (see BikeModel._bake_static for which). Returns how many
## meshes were merged away.
static func bake(model: BikeModel) -> int:
	var moving := {}
	for s in model._struts:
		moving[s["mi"]] = true
	for n in model._needles:
		moving[n["node"]] = true
	var lamps := {}
	for l in model._lamps:
		lamps[l["mat"]] = true
	var kits := _kit_textures()
	var gone := 0
	var groups := {}       # key -> {"slot", "shader", "mat", "pieces": [[mesh, surface, transform, look, slot]]}
	var order := []        # the keys in the order met, so the merged meshes come out alike every time
	var keep := {}         # slot -> its meshes left as they were
	for slot in model._slot_meshes:
		keep[slot] = []
		var own := _keeps_own(model, slot)
		for mi in model._slot_meshes[slot]:
			if not _can_merge(model, mi, moving):
				keep[slot].append(mi)
				continue
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				var look := _look_of(mat, lamps, kits)
				if slot == "exhaust" and not look.is_empty() and m.get_parent() == model and not model._exhaust_ports.is_empty() \
						and look["finish"] in [Finish.CHROME, Finish.ALLOY, Finish.BRUSHED]:
					look = look.duplicate()
					look["ports"] = model._exhaust_ports
					look["heat"] = lerpf(HEAT_NEW, 1.0, clampf(float((model.condition.get(slot, {}) as Dictionary).get("wear", 0.0)) if model.condition.get(slot) is Dictionary else 0.0, 0.0, 1.0))
				var key: Array
				if look.is_empty():
					key = [slot, m.get_parent(), mat, m.cast_shadow, m.layers, model._stock_pieces.has(mi)]
				else:
					key = [slot if own else "", m.get_parent(), null, m.cast_shadow, m.layers, model._stock_pieces.has(mi)]
				if not groups.has(key):
					groups[key] = {"slot": key[0], "shader": not look.is_empty(), "mat": mat, "pieces": []}
					order.append(key)
				groups[key]["pieces"].append([m.mesh, s, m.transform, look, slot])
			m.get_parent().remove_child(m)
			m.queue_free()
			gone += 1
	var shadow_groups := {}   # [parent, layers, slot or ""] -> the merged meshes whose shadows go together
	for key in order:
		var g: Dictionary = groups[key]
		var shared: bool = g["slot"] == ""
		var merged := MeshInstance3D.new()
		merged.name = "Baked_shared" if shared else "Baked_" + str(g["slot"])
		if g["shader"]:
			_set_mesh(merged, _shaded_arrays(g["pieces"]), CUSTOM_FORMAT)
			merged.material_override = BikeShader.material()
			merged.lod_bias = BikeLook.lod_bias(model)
		else:
			var st := SurfaceTool.new()
			for piece in g["pieces"]:
				st.append_from(piece[0], piece[1], piece[2])
			_set_mesh(merged, st.commit_to_arrays(), 0)
			merged.material_override = g["mat"]
			merged.lod_bias = BikeLook.lod_bias(model)
		merged.cast_shadow = key[3]
		if merged.mesh.get_aabb().get_longest_axis_size() < BikeModel.SHADOW_MIN:
			merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		merged.layers = key[4]
		(key[1] as Node).add_child(merged)
		if shared:
			# Drawing several parts at once: each part keeps the shape of its own pieces in it,
			# for its size and for what's drawn over just that part later (see BikeModel.slot_shapes).
			model._shared.append(merged)
			var by_slot := {}
			for piece in g["pieces"]:
				if not by_slot.has(piece[4]):
					by_slot[piece[4]] = []
				by_slot[piece[4]].append(piece)
			for slot in by_slot:
				if not model._slot_shapes.has(slot):
					model._slot_shapes[slot] = []
				model._slot_shapes[slot].append([key[1], _shape(by_slot[slot]), key[5]])
		else:
			keep[g["slot"]].append(merged)
		model._baked_pieces[merged.get_instance_id()] = true
		if key[5]:
			model._stock_pieces[merged] = true   # still left out of the part's size
		gone -= 1
		if merged.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and (g["shader"] or BikeModel._plain_caster(g["mat"])):
			var sk := [key[1], key[4], g["slot"]]
			if not shadow_groups.has(sk):
				shadow_groups[sk] = []
			shadow_groups[sk].append(merged)
	for slot in keep:
		model._slot_meshes[slot] = keep[slot]
	# One shadow for each node's merged pieces, as the Classic bake casts them.
	for sk in shadow_groups:
		var pieces: Array = shadow_groups[sk]
		if pieces.size() < 2:
			continue
		var sh := MeshInstance3D.new()
		sh.name = "BakedShadow"
		sh.mesh = BikeModel.shape_mesh(pieces)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sh.layers = sk[1]
		(sk[0] as Node).add_child(sh)
		for mi in pieces:
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if sk[2] == "":
			model._shared.append(sh)
		else:
			model.add_slot_extra(str(sk[2]), sh)
	return gone


## Puts the Bike detail setting into effect on `model`'s merged meshes (see BikeLook.lod_bias).
static func set_detail(model: BikeModel) -> void:
	var bias := BikeLook.lod_bias(model)
	for mi in model._shared:
		(mi as GeometryInstance3D).lod_bias = bias
	for slot in model._slot_meshes:
		for mi in model._slot_meshes[slot]:
			if model.baked_piece(mi):
				(mi as GeometryInstance3D).lod_bias = bias


## Whether drawing `geo` (a bike's fit, see BikeModel.apply_geometry) would move a part whose
## pieces are drawn together with others': then the bike is drawn again, that part on its own.
static func moves_shared(model: BikeModel, geo: Dictionary) -> bool:
	for slot in geo:
		if model._slot_shapes.has(slot) and str(geo[slot]) != str(model.geometry.get(slot)):
			return true
	return false


## `shapes` (a part's shape meshes, see bake) and `first` (another shape mesh, or null) as one.
static func join_shapes(first: ArrayMesh, shapes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	for m in ([first] if first != null else []) + shapes:
		st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


## The corners and facings of `pieces` ([mesh, surface, transform, ...]) as one mesh, in the
## node they hang from.
static func _shape(pieces: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	for piece in pieces:
		var xf: Transform3D = piece[2]
		var nb := xf.basis.inverse().transposed()
		var arrays := (piece[0] as Mesh).surface_get_arrays(piece[1])
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n = arrays[Mesh.ARRAY_NORMAL]
		var has_n: bool = n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()
		var base := verts.size()
		for i in v.size():
			verts.append(xf * v[i])
			normals.append((nb * (n[i] as Vector3)).normalized() if has_n else Vector3.UP)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			for i in idx:
				index.append(base + i)
		else:
			for i in v.size():
				index.append(base + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = index
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Whether a part's mesh can be merged into others: as the Classic bake (BikeModel._can_bake),
## and the cables, hoses and leads too, which are only marked to be left behind when a part is
## shown off the bike ("bike_only").
static func _can_merge(model: BikeModel, mi, moving: Dictionary) -> bool:
	if not is_instance_valid(mi) or not (mi is MeshInstance3D):
		return false
	var m := mi as MeshInstance3D
	if m.get_meta_list() != [&"bike_only"]:
		return model._can_bake(mi, moving)
	m.remove_meta(&"bike_only")
	var ok := model._can_bake(mi, moving)
	m.set_meta(&"bike_only", true)
	return ok


## Whether `slot`'s part keeps a mesh of its own after the bake: something is drawn over just
## that part afterwards (dirt, a detailed finish, blasting) or it's moved in geometry mode.
static func _keeps_own(model: BikeModel, slot: String) -> bool:
	if model.geometry.has(slot):
		return true
	var cond = model.condition.get(slot)
	if not (cond is Dictionary):
		return false
	var c := cond as Dictionary
	return float(c.get("dirt", 0.0)) > 0.003 or c.get("shine") is Dictionary or c.has("blast") or c.get("blast_full", false)


## TextureKit's textures -> [kind, which map ("normal", "albedo" or "rough")].
static func _kit_textures() -> Dictionary:
	var out := {}
	for kind in TextureKit.KINDS:
		var tex: Dictionary = TextureKit._texture_set(kind)
		for k in tex:
			if tex[k] is Texture2D:
				out[tex[k]] = [kind, k]
	return out


## What a surface's material looks like, for the bike shader to draw it just the same:
## {albedo, metallic, roughness, clearcoat, clearcoat_roughness, kit, scale, depth, rust, finish}.
## Empty for a material the shader doesn't draw (it stays as it is).
static func _look_of(mat: Material, lamps: Dictionary, kits: Dictionary) -> Dictionary:
	if not (mat is StandardMaterial3D) or lamps.has(mat):
		return {}
	var m := mat as StandardMaterial3D
	for meta in m.get_meta_list():
		if meta != &"paint_surface":
			return {}
	if m.next_pass != null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.emission_enabled \
			or m.cull_mode != BaseMaterial3D.CULL_BACK or m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX or m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY \
			or m.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or m.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX \
			or m.grow or m.vertex_color_use_as_albedo or m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
			or m.use_point_size or m.no_depth_test or m.fixed_size or m.disable_receive_shadows or m.disable_ambient_light \
			or m.metallic_texture != null or m.metallic_specular != 0.5 or m.ao_enabled or m.rim_enabled \
			or m.anisotropy_enabled or m.heightmap_enabled or m.subsurf_scatter_enabled or m.backlight_enabled \
			or m.refraction_enabled or m.clearcoat_texture != null or m.uv1_world_triplanar or m.uv1_offset != Vector3.ZERO \
			or m.uv1_triplanar_sharpness != 1.0 or m.albedo_color.a < 1.0 or m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		return {}
	var textured := m.normal_enabled or m.albedo_texture != null or m.roughness_texture != null or m.detail_enabled
	if textured and not m.uv1_triplanar:
		return {}
	if textured and (m.uv1_scale.x != m.uv1_scale.y or m.uv1_scale.y != m.uv1_scale.z):
		return {}
	var kit := ""
	for t in [m.normal_texture if m.normal_enabled else null, m.albedo_texture, m.roughness_texture]:
		if t == null:
			continue
		if not kits.has(t) or (kit != "" and kit != kits[t][0]):
			return {}
		kit = kits[t][0]
	if m.roughness_texture != null and m.roughness_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_RED:
		return {}
	if m.normal_enabled and m.normal_texture == null:
		return {}
	var rust := 0.0
	if m.detail_enabled:
		if m.detail_normal != null or m.detail_uv_layer != BaseMaterial3D.DETAIL_UV_1 or kit != "":
			return {}
		var level := -1
		for l in BikeModel._rust_masks:
			if BikeModel._rust_masks[l] == m.detail_mask:
				level = int(l)
		if m.detail_albedo == BikeModel._rust_albedo and m.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MIX and level > 0:
			rust = float(level)
		elif m.detail_albedo == BikeModel._patina_albedo and m.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MUL and level > 0:
			rust = -float(level)
		else:
			return {}
	var clearcoat := m.clearcoat if m.clearcoat_enabled else 0.0
	return {"albedo": m.albedo_color, "metallic": m.metallic, "roughness": m.roughness,
		"clearcoat": clearcoat, "clearcoat_roughness": m.clearcoat_roughness,
		"kit": float(BikeShader.kit_layer(kit)) if kit != "" else -1.0, "scale": m.uv1_scale.x,
		"depth": m.normal_scale if m.normal_enabled else 0.0, "rust": rust,
		"finish": finish_of(m.albedo_color, m.metallic, m.roughness, clearcoat, kit)}


## Which finish a surface is, from what its material is made of: the bike shader adds each its
## own close-up detail (see BikeShader).
static func finish_of(albedo: Color, metallic: float, roughness: float, clearcoat: float, kit: String) -> int:
	match kit:
		"carbon":
			return Finish.CARBON
		"grain", "quilt":
			return Finish.LEATHER
		"brushed":
			return Finish.BRUSHED
		"":
			pass
		_:
			return Finish.PLAIN
	if clearcoat > 0.0 and metallic < 0.9:
		return Finish.METAL_FLAKE if metallic >= 0.2 else Finish.PAINT
	if metallic >= 0.95:
		return Finish.CHROME if roughness <= 0.16 else (Finish.ALLOY if roughness <= 0.45 else Finish.PLAIN)
	if metallic <= 0.1 and roughness >= 0.8 and albedo.get_luminance() < 0.15:
		return Finish.RUBBER
	return Finish.PLAIN


## The arrays of one mesh of `pieces` ([mesh, surface, transform, look]), each piece's look on
## its vertices.
static func _shaded_arrays(pieces: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	var index := PackedInt32Array()
	for piece in pieces:
		var mesh: Mesh = piece[0]
		var s: int = piece[1]
		var xf: Transform3D = piece[2]
		var look: Dictionary = piece[3]
		var nb := xf.basis.inverse().transposed()
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n = arrays[Mesh.ARRAY_NORMAL]
		var has_n: bool = n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()
		var base := verts.size()
		var a: Color = look["albedo"]
		var l0 := [a.r, a.g, a.b, float(look["metallic"])]
		var l1 := [float(look["roughness"]), float(look["clearcoat"]), float(look["clearcoat_roughness"]), float(look["depth"])]
		var l2 := [float(look["kit"]), float(look["scale"]), float(look["rust"]), 0.0]
		var finish := float(look.get("finish", Finish.PLAIN))
		var ports: Array = look.get("ports", [])
		var heat := float(look.get("heat", 0.0))
		for i in v.size():
			var at := xf * v[i]
			verts.append(at)
			normals.append((nb * (n[i] as Vector3)).normalized() if has_n else Vector3.UP)
			c0.append_array(l0)
			c1.append_array(l1)
			c2.append_array(l2)
			# How hot this bit of pipe runs: hottest where it leaves the head.
			var hot := 0.0
			for port in ports:
				hot = maxf(hot, 1.0 - at.distance_to(port) / HEAT_REACH)
			c3.append_array([finish, clampf(hot, 0.0, 1.0) * heat, 0.0, 0.0])
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			for i in idx:
				index.append(base + i)
		else:
			for i in v.size():
				index.append(base + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_CUSTOM2] = c2
	arr[Mesh.ARRAY_CUSTOM3] = c3
	arr[Mesh.ARRAY_INDEX] = index
	return arr


## Gives `mi` a mesh of `arr` (a surface's arrays, `flags` its format), and then its lighter
## levels of detail, simplified the way Godot simplifies an imported model (Godot picks one by
## how big the bike is on screen): the small pieces go first, then the shapes thin out, down to
## the bike's outline far off. Working those out takes a while, so it's done off the main
## thread and the mesh swapped when it's ready (at once with `lods_now`, for the tests).
static func _set_mesh(mi: MeshInstance3D, arr: Array, flags: int) -> void:
	if lods_now:
		mi.mesh = _with_lods(_simplified(arr, flags), arr)
		return
	var plain := ArrayMesh.new()
	plain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mi.mesh = plain
	var out := []   # filled with the simplified mesh by the worker
	var task := WorkerThreadPool.add_task(func(): out.append(_simplified(arr, flags)))
	_pending.append([task, weakref(mi), plain, out, arr])
	_watch()


## The levels of detail being worked out: [task, the mesh instance (weak), the mesh it had,
## [the result], arrays]. Checked each frame, and finished off before the game closes, so
## nothing is left holding a mesh once the renderer has gone.
static var _pending: Array = []
static var _watching := false


static func _watch() -> void:
	if _watching:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_watching = true
	tree.process_frame.connect(_check_pending)
	tree.root.tree_exiting.connect(finish_pending)


static func _check_pending() -> void:
	var left := []
	for p in _pending:
		if WorkerThreadPool.is_task_completed(p[0]):
			WorkerThreadPool.wait_for_task_completion(p[0])
			_swap(p[1], p[2], p[3][0], p[4])
		else:
			left.append(p)
	_pending = left


## Waits for the levels of detail still being worked out, and drops them (the game's closing).
static func finish_pending() -> void:
	for p in _pending:
		WorkerThreadPool.wait_for_task_completion(p[0])
	_pending.clear()


static var lods_now := false


static func _simplified(arr: Array, flags: int) -> ImporterMesh:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "", flags)
	im.generate_lods(LOD_ANGLE, 60.0, [])
	return im


static func _swap(target: WeakRef, was: Mesh, im: ImporterMesh, arr: Array) -> void:
	var mi := target.get_ref() as MeshInstance3D
	if mi != null and mi.mesh == was:
		mi.mesh = _with_lods(im, arr)


static func _with_lods(im: ImporterMesh, arr: Array) -> ArrayMesh:
	var out := im.get_mesh()
	var index = arr[Mesh.ARRAY_INDEX]
	var tris := [(index as PackedInt32Array).size() / 3 if index is PackedInt32Array and not (index as PackedInt32Array).is_empty() \
		else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3]
	for i in im.get_surface_lod_count(0):
		tris.append([im.get_surface_lod_size(0, i), im.get_surface_lod_indices(0, i).size() / 3])
	# The triangles at each level, for the budgets (see BikeLook.stats).
	out.set_meta(&"lod_tris", tris)
	return out
