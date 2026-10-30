class_name BikeLook
## How bikes are drawn: "classic", the bikes as they were before the look overhaul, kept just as
## they are as a fallback, or "new", the overhaul (one bike shader, levels of detail and, part by
## part, the Blender-made shapes). Chosen in the Esc menu's Debug tab and kept in the settings.
## It only changes what this player sees: the parts, saves and what goes over the network are the
## same in both, so players on different looks ride together as usual.

const CLASSIC := "classic"
const NEW := "new"
const LOOKS: Array[String] = [CLASSIC, NEW]
const NAMES := {CLASSIC: "Classic", NEW: "New"}
## Every BikeModel is in this group while it's in the tree, so a change of look reaches them all.
const GROUP := &"bike_models"
## The Bike detail setting's steps (Settings.gfx_bike_detail), and how far each keeps a bike's
## levels of detail (see BikeLookNew._with_lods): Low thins them out four times nearer than
## High, Ultra keeps them twice as far. Other riders' bikes are drawn a step lower than yours.
const DETAIL: Array[String] = ["low", "medium", "high", "ultra"]
const LOD_BIAS := {"low": 0.25, "medium": 0.5, "high": 1.0, "ultra": 2.0}


## The look the player has chosen.
static func current() -> String:
	return Settings.bike_look


## Whether a model draws in the new look.
static func is_new(model: BikeModel) -> bool:
	return model.drawn_look() == NEW


## Switches every bike to `look` there and then (the garage's, the road's, other players' and
## the parked ones), and remembers it. Bikes pinned to a look of their own stay as they are.
static func choose(new_look: String) -> void:
	if not LOOKS.has(new_look) or new_look == Settings.bike_look:
		return
	Settings.bike_look = new_look
	Settings.save_settings()
	for m in Settings.get_tree().get_nodes_in_group(GROUP):
		if m is BikeModel and (m as BikeModel).look == "":
			(m as BikeModel).redraw_look()


## The Bike detail step `model` is drawn at: the setting for the player's own bike, a step
## lower for everyone else's.
static func detail_of(model: BikeModel) -> String:
	var i := maxi(DETAIL.find(Settings.gfx_bike_detail), 0)
	return DETAIL[i if model.own_rider else maxi(i - 1, 0)]


static func lod_bias(model: BikeModel) -> float:
	return float(LOD_BIAS[detail_of(model)])


## Puts the Bike detail setting into effect on every bike drawn in the new look.
static func apply_detail(tree: SceneTree) -> void:
	for m in tree.get_nodes_in_group(GROUP):
		if m is BikeModel:
			BikeLookNew.set_detail(m as BikeModel)


## What a model costs to draw, for the budgets and the Classic check: "draws" (a draw per
## surface of each visible mesh, shadows aside), "materials" (different ones), "tris", "meshes"
## and "shadow_draws" (the surfaces drawn into the shadow maps); "tris_lod1" and "tris_lod2" for
## the triangles drawn a mate's bike's distance off and far down the road (see BikeLookNew.NEAR), "rider_draws" and
## "rider_tris" for the rider's share.
static func stats(model: Node3D) -> Dictionary:
	var out := {"draws": 0, "materials": 0, "tris": 0, "meshes": 0, "shadow_draws": 0, "tris_lod1": 0, "tris_lod2": 0,
		"rider_draws": 0, "rider_tris": 0}
	var rider: Node = model.get("_rider")
	var bias := lod_bias(model) if model is BikeModel else 1.0
	var mats := {}
	var todo: Array[Node] = [model]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		todo.append_array(n.get_children())
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var shadow_only := mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		for s in mi.mesh.get_surface_count():
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				out["shadow_draws"] += 1
			if shadow_only:
				continue
			out["draws"] += 1
			var mat := mi.get_active_material(s)
			if mat != null:
				mats[mat] = true
			var tris := _tris(mi.mesh, s)
			out["tris"] += tris
			var lods = mi.mesh.get_meta(&"lod_tris") if mi.mesh.has_meta(&"lod_tris") else null
			out["tris_lod1"] += lod_tris(lods, BikeLookNew.NEAR, bias) if lods is Array else tris
			out["tris_lod2"] += lod_tris(lods, BikeLookNew.FAR, bias) if lods is Array else tris
			if rider != null and rider.is_ancestor_of(mi):
				out["rider_draws"] += 1
				out["rider_tris"] += tris
		if not shadow_only:
			out["meshes"] += 1
	out["materials"] = mats.size()
	return out


## The triangles Godot draws of a mesh with levels of detail `lods` ([all, [size, tris] ...],
## see BikeLookNew._shaded_mesh) `distance` metres off, at the High detail level's threshold of a
## pixel (Graphics.LOD_THRESHOLD) and a 75 degree view 1080 pixels high, `bias` its lod_bias.
static func lod_tris(lods: Array, distance: float, bias := 1.0) -> int:
	var pixel := distance * 2.0 * tan(deg_to_rad(75.0) * 0.5) / 1080.0
	var out := int(lods[0])
	for l in lods.slice(1):
		if float(l[0]) * bias / pixel > 1.0:
			break
		out = int(l[1])
	return out


static func _tris(mesh: Mesh, s: int) -> int:
	if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
		return 0
	var arrays := mesh.surface_get_arrays(s)
	var idx = arrays[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		return (idx as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
