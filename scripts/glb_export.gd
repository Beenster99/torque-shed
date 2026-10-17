class_name GlbExport
extends RefCounted
## Exports finished bikes as .glb files for other 3D apps: a BikeModel built with its paint and
## no rider, flattened into one mesh per part (slot) with plain PBR materials, in metres, Y up,
## the front facing +Z and the origin on the ground halfway between the wheels.
##   godot --headless --path . res://tools/export_glb.tscn -- --out=DIR
## What doesn't survive the trip: rust and patina detail layers (glTF has no second albedo),
## clear coat (written as plain gloss), triplanar textures (baked to box-projected UVs instead),
## and dirt and paint-effect shader passes (left off: the exports are clean bikes).

## The bikes a release exports: a style, a name, the seed its parts are drawn with (Shed.style_parts),
## and the paint on its painted parts ({slot: [paint index, finish]}; others keep their catalogue colour).
const BIKES := [
	{"style": "classic", "name": "Burgundy Twin", "seed": 7, "paint": {"tank": [12, "gloss"], "side_panels": [12, "gloss"]}},
	{"style": "cafe", "name": "Green Ton-Up", "seed": 7, "paint": {"tank": [3, "gloss"], "tail": [3, "gloss"], "side_panels": [14, "gloss"]}},
	{"style": "sport", "name": "Blue Thousand", "seed": 7, "paint": {"tank": [1, "metallic"]}},
	{"style": "mx", "name": "Gold Dirt", "seed": 7, "paint": {}},
	{"style": "chopper", "name": "Purple Rake", "seed": 7, "paint": {"tank": [4, "metallic"], "tail": [4, "metallic"]}},
]


## Slots the README leaves out of a bike's part list (hidden or too small to matter in a model).
const README_SKIP := ["front_pads", "rear_pads", "front_caliper", "rear_caliper", "front_master", "rear_master", "chain", "final_drive"]


## The release's bikes, each {style, name, file, parts, cond, paint}: parts drawn the way a style
## project bike's are, from a fixed seed so a re-export gives the same bikes.
static func pick_bikes() -> Array:
	var out := []
	var rng: RandomNumberGenerator = Shed._rng
	var saved := rng.state
	for b in BIKES:
		rng.seed = int(b["seed"])
		var parts := Shed.style_parts(str(b["style"]))
		var cond := {}
		for slot in b["paint"]:
			var p: Array = b["paint"][slot]
			cond[slot] = {"color": Shed.PAINTS[int(p[0])], "finish": str(p[1])}
		var body: Color = cond.get("tank", {}).get("color", PartsDB.default_color(str(parts.get("tank", ""))))
		var file := "%s_%s" % [b["style"], str(b["name"]).to_lower().replace(" ", "_").replace("-", "_")]
		out.append({"style": b["style"], "name": b["name"], "file": file, "parts": parts, "cond": cond, "paint": body})
	rng.state = saved
	return out


## The in-game model of `bike` (from pick_bikes), riderless and not in the tree.
static func bike_model(bike: Dictionary) -> BikeModel:
	var model := BikeModel.new()
	model.build_from(BikeBuild.new(bike["parts"], bike["cond"]), bike["paint"], {}, bike["cond"], false)
	return model


## Exports every release bike into `dir` as <style>_<name>.glb with a README.txt. Returns
## {file: report} (see export_model).
static func export_release(dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var reports := {}
	var readme := PackedStringArray(["Torque Shed bikes as .glb", "",
		"Each file is one bike in metres, Y up, the front facing +Z, the origin on the ground halfway",
		"between the wheels. One mesh per part (frame, tank, engine, ...), plain PBR materials.",
		"Not carried over: clear coat (comes out as plain gloss), rust/patina layers, dirt.", ""])
	for bike in pick_bikes():
		var model := bike_model(bike)
		var path := "%s/%s.glb" % [dir, bike["file"]]
		var rep := export_model(model, path, str(bike["name"]))
		model.free()
		reports[bike["file"]] = rep
		readme.append("%s.glb  %s, %s (%d meshes, %d materials)" % [bike["file"], bike["name"],
			PartsDB.style_name(str(bike["style"])), rep["meshes"], rep["materials"]])
		for slot in PartsDB.SLOTS:
			var id := str(bike["parts"].get(slot, "none"))
			if id == "none" or PartsDB.ENGINE_SLOTS.has(slot) or README_SKIP.has(slot):
				continue
			var paint := ""
			if bike["cond"].has(slot):
				var p: Array = BIKES.filter(func(b): return b["name"] == bike["name"])[0]["paint"][slot]
				paint = "  [painted %s, %s]" % [Shed.PAINT_NAMES[int(p[0])], p[1]]
			readme.append("    %-16s %s%s" % [_slot_label(slot), PartsDB.get_part(id).get("name", id), paint])
		readme.append("")
	var f := FileAccess.open(dir + "/README.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(readme) + "\n")
	return reports


## A slot's name for the README: "Front brake", "Rear wheel", "Fuel tank".
static func _slot_label(slot: String) -> String:
	if slot.ends_with("_disc"):
		return slot.get_slice("_", 0).capitalize() + " brake"
	if slot.begins_with("front_") or slot.begins_with("rear_"):
		return slot.get_slice("_", 0).capitalize() + " " + slot.substr(slot.find("_") + 1).replace("_", " ")
	return str(PartsDB.KIND_NAMES.get(slot, PartsDB.KIND_NAMES.get(PartsDB.SLOT_KIND.get(slot, slot), slot)))


## Writes `model` (a built BikeModel) to `path` as a .glb. Returns {error, meshes, materials,
## labels, dropped}: how many part meshes and materials went out, how many text labels were
## turned into geometry, and what was left off.
static func export_model(model: BikeModel, path: String, root_name := "Bike") -> Dictionary:
	var root := scene_for(model, root_name)
	var rep: Dictionary = root.get_meta("report")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	root.free()
	rep["error"] = err
	return rep


## A plain scene of `model` ready for glTF: a Node3D holding one MeshInstance3D per part, every
## mesh baked into the export's space (ground origin, front to +Z), materials as baked
## StandardMaterial3Ds, text labels as text geometry.
static func scene_for(model: BikeModel, root_name := "Bike") -> Node3D:
	var to_out := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, model._build.rear_radius, 0.0))
	var slot_of := {}
	for slot in model._slot_meshes:
		for mi in model._slot_meshes[slot]:
			slot_of[mi] = slot
	var groups := {}       # slot -> {material key -> {mat, v, n, uv, idx}}
	var mats := {}         # material key -> baked material
	var rep := {"meshes": 0, "materials": 0, "labels": 0, "dropped": []}
	for node in _walk(model):
		if not _shown(node, model):
			continue
		var mesh: Mesh = null
		var src_mat: Material = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
			src_mat = (node as MeshInstance3D).material_override
		elif node is Label3D:
			mesh = _label_mesh(node as Label3D)
			src_mat = _label_mat(node as Label3D)
			rep["labels"] += 1
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			# Repeated bits (a knobbly's knobs): each copy baked in where it sits.
			var mm := (node as MultiMeshInstance3D).multimesh
			var mslot := str(slot_of.get(node, _slot_up(node, slot_of, model)))
			var mxf := to_out * _xform_in(node as Node3D, model)
			# Where each copy sits: from the model's own note if it kept one (the renderer holds them,
			# and a headless run's stand-in renderer forgets them), else from the multimesh.
			var placed: Array = node.get_meta("instances", [])
			if placed.is_empty():
				for i in mm.instance_count:
					placed.append(mm.get_instance_transform(i))
			for i in placed.size():
				for s in mm.mesh.get_surface_count():
					var mmat: Material = (node as MultiMeshInstance3D).material_override
					var baked := bake_material(mmat if mmat != null else mm.mesh.surface_get_material(s), rep)
					var key := _mat_key(baked)
					if not mats.has(key):
						mats[key] = baked
					_append(groups, mslot, key, mats[key], mm.mesh, s, mxf * (placed[i] as Transform3D))
			continue
		elif node is VisualInstance3D:
			rep["dropped"].append(node.get_class())
			continue
		if mesh == null:
			continue
		var slot := str(slot_of.get(node, _slot_up(node, slot_of, model)))
		var xf := to_out * _xform_in(node as Node3D, model)
		for s in mesh.get_surface_count():
			var m: Material = src_mat if src_mat != null else mesh.surface_get_material(s)
			var baked := bake_material(m, rep)
			var key := _mat_key(baked)
			if not mats.has(key):
				mats[key] = baked
			_append(groups, slot, key, mats[key], mesh, s, xf)
	var root := Node3D.new()
	root.name = root_name.validate_node_name()
	for slot in groups:
		var am := ArrayMesh.new()
		for key in groups[slot]:
			var g: Dictionary = groups[slot][key]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g["v"]
			arrays[Mesh.ARRAY_NORMAL] = g["n"]
			arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
			arrays[Mesh.ARRAY_INDEX] = g["idx"]
			var mat: StandardMaterial3D = g["mat"]
			if mat.normal_enabled:
				var st := SurfaceTool.new()
				st.create_from_arrays(arrays)
				st.generate_tangents()
				arrays = st.commit_to_arrays()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.name = str(slot)
		mi.mesh = am
		root.add_child(mi)
		rep["meshes"] += 1
	rep["materials"] = mats.size()
	root.set_meta("report", rep)
	return root


## Every node under `n`, depth first.
static func _walk(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


## Whether `node` shows on the bike: it and every parent up to the model are visible.
static func _shown(node: Node, model: Node) -> bool:
	var n := node
	while n != null and n != model:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## The slot of the nearest parent that has one (labels hang off a slot's meshes), or "body".
static func _slot_up(node: Node, slot_of: Dictionary, model: Node) -> String:
	var n := node.get_parent()
	while n != null and n != model:
		if slot_of.has(n):
			return slot_of[n]
		n = n.get_parent()
	return "body"


static func _xform_in(node: Node3D, model: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != model and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Adds surface `s` of `mesh`, moved by `xf`, to the slot's batch for material `key`. Normals
## follow the transform; a mirrored transform has its triangles turned round to face out.
## Textures that were mapped triplanar get box-projected UVs from the baked positions.
static func _append(groups: Dictionary, slot: String, key: String, mat: StandardMaterial3D, mesh: Mesh, s: int, xf: Transform3D) -> void:
	if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
		return
	var arrays := mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	if not groups.has(slot):
		groups[slot] = {}
	if not groups[slot].has(key):
		groups[slot][key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}
	var g: Dictionary = groups[slot][key]
	var base: int = (g["v"] as PackedVector3Array).size()
	var nb := xf.basis.inverse().transposed()
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var tri: float = mat.get_meta("box_uv", 0.0)
	var v_out: PackedVector3Array = g["v"]
	var n_out: PackedVector3Array = g["n"]
	var uv_out: PackedVector2Array = g["uv"]
	for i in verts.size():
		var p := xf * verts[i]
		var nrm := Vector3.UP
		if normals is PackedVector3Array and i < (normals as PackedVector3Array).size():
			nrm = (nb * (normals as PackedVector3Array)[i]).normalized()
		v_out.append(p)
		n_out.append(nrm)
		if tri > 0.0:
			var a := nrm.abs()
			var uv := Vector2(p.z, p.y) if a.x >= a.y and a.x >= a.z else (Vector2(p.x, p.z) if a.y >= a.z else Vector2(p.x, p.y))
			uv_out.append(uv * tri)
		elif uvs is PackedVector2Array and i < (uvs as PackedVector2Array).size():
			uv_out.append((uvs as PackedVector2Array)[i])
		else:
			uv_out.append(Vector2.ZERO)
	var idx = arrays[Mesh.ARRAY_INDEX]
	if not (idx is PackedInt32Array) or (idx as PackedInt32Array).is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var flip := xf.basis.determinant() < 0.0
	var i_out: PackedInt32Array = g["idx"]
	var ii: PackedInt32Array = idx
	for t in range(0, ii.size() - 2, 3):
		i_out.append(base + ii[t])
		if flip:
			i_out.append(base + ii[t + 2])
			i_out.append(base + ii[t + 1])
		else:
			i_out.append(base + ii[t + 1])
			i_out.append(base + ii[t + 2])
	g["v"] = v_out
	g["n"] = n_out
	g["uv"] = uv_out
	g["idx"] = i_out


## A plain StandardMaterial3D standing in for `m` in glTF: colour, metal, roughness, emission,
## alpha and the albedo, roughness and normal textures. A triplanar texture is tagged with its
## scale ("box_uv") for _append to project. Shader materials come out as their albedo
## parameter, or mid grey, and are noted in `rep`.
static func bake_material(m: Material, rep: Dictionary) -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		out.albedo_color = b.albedo_color
		out.albedo_texture = b.albedo_texture
		out.metallic = b.metallic
		out.roughness = b.roughness
		# Clear coat goes out as a glossier base: glTF viewers mostly ignore the clearcoat extension.
		if b.clearcoat_enabled:
			out.roughness = lerpf(b.roughness, minf(b.roughness, b.clearcoat_roughness + 0.1), b.clearcoat)
		out.roughness_texture = b.roughness_texture
		out.roughness_texture_channel = b.roughness_texture_channel
		out.metallic_texture = b.metallic_texture
		out.normal_enabled = b.normal_enabled and b.normal_texture != null
		# Triplanar mapping blends three reads of the bumps, which softens them; one box-projected
		# read is sharper, so it goes out a little shallower to match.
		out.normal_texture = _scaled_normals(b.normal_texture, b.normal_scale * (0.6 if b.uv1_triplanar else 1.0)) if out.normal_enabled else null
		out.emission_enabled = b.emission_enabled
		out.emission = b.emission
		out.emission_energy_multiplier = b.emission_energy_multiplier
		out.transparency = b.transparency
		out.cull_mode = b.cull_mode
		out.shading_mode = b.shading_mode
		if b.uv1_triplanar and (b.albedo_texture or b.roughness_texture or b.normal_texture):
			out.set_meta("box_uv", b.uv1_scale.x)
		else:
			out.uv1_scale = b.uv1_scale
			out.uv1_offset = b.uv1_offset
		if b.detail_enabled and not rep["dropped"].has("detail layer (rust/patina)"):
			rep["dropped"].append("detail layer (rust/patina)")
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		for p in ["albedo", "albedo_color", "color", "base_color"]:
			var v = sm.get_shader_parameter(p)
			if v is Color:
				out.albedo_color = v
				break
		if not rep["dropped"].has("shader material (baked to flat colour)"):
			rep["dropped"].append("shader material (baked to flat colour)")
	else:
		out.albedo_color = Color(0.5, 0.5, 0.5)
	return out


static var _normal_cache := {}


## `tex` with its bumps flattened (or deepened) by `depth`: the glTF exporter writes no normal
## strength, so a gentle crinkle finish would come out at full depth.
static func _scaled_normals(tex: Texture2D, depth: float) -> Texture2D:
	if is_equal_approx(depth, 1.0):
		return tex
	var key := "%s|%.3f" % [tex.get_rid(), depth]
	if _normal_cache.has(key):
		return _normal_cache[key]
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var n := Vector3((c.r * 2.0 - 1.0) * depth, (c.g * 2.0 - 1.0) * depth, maxf(c.b * 2.0 - 1.0, 0.05)).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var out := ImageTexture.create_from_image(img)
	_normal_cache[key] = out
	return out


## Identical baked materials share one glTF material.
static func _mat_key(m: StandardMaterial3D) -> String:
	return "%s|%.3f|%.3f|%s|%s|%s|%s|%d|%s|%.2f|%d|%s" % [m.albedo_color.to_html(), m.metallic, m.roughness,
		m.albedo_texture.get_rid() if m.albedo_texture else "", m.roughness_texture.get_rid() if m.roughness_texture else "",
		m.normal_texture.get_rid() if m.normal_texture else "", m.emission.to_html() if m.emission_enabled else "",
		m.transparency, str(m.get_meta("box_uv", 0.0)), m.emission_energy_multiplier, m.cull_mode, m.uv1_scale]


## A Label3D's text as flat text geometry (TextMesh), the same size and way round.
static func _label_mesh(l: Label3D) -> Mesh:
	if l.text.strip_edges() == "":
		return null
	var tm := TextMesh.new()
	tm.text = l.text
	tm.font = l.font
	tm.font_size = l.font_size
	tm.pixel_size = l.pixel_size
	tm.depth = 0.0004
	tm.horizontal_alignment = l.horizontal_alignment
	tm.vertical_alignment = l.vertical_alignment
	tm.offset = l.offset
	return tm


static func _label_mat(l: Label3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = l.modulate
	m.roughness = 0.6
	return m
