extends RefCounted
## Round 0's model (kit model "standin:post", docs/scenery.md): a post at every point of a kind no round has modelled
## yet, coloured by the round that will, drawn only while SceneryStreamer.show_standins is on (Esc > Debug's scenery
## markers). A line or area is marked at its first point in the block. Its models are "post_" and the round ("post_D1").

## Each round's stand-in colour.
const ROUND_COLOURS := {"D1": Color(0.95, 0.3, 0.2), "D2": Color(0.35, 0.35, 0.4), "D3": Color(0.2, 0.55, 0.95),
	"D4": Color(0.95, 0.95, 0.95), "D5": Color(0.4, 0.8, 0.25), "D6": Color(0.75, 0.55, 0.25),
	"D7": Color(0.1, 0.85, 0.85), "D8": Color(0.95, 0.85, 0.15), "D9": Color(0.75, 0.3, 0.8)}
## The post: this tall and this thick (m).
const POST_H := 3.0
const POST_W := 0.25
## A block with this many things keeps its own copy of the roads it asks after (RoadNet.ground_at's memo): out of the
## lock the other workers wait on, worth it from a few dozen.
const MEMO_FROM := 32


static func lay_out(n: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var out := {"items": {}, "moved": 0, "skipped": 0}
	var o := Vector3(key.x * RoadBlock.SIZE, 0.0, key.y * RoadBlock.SIZE)
	var spots := []   # [region-frame point, heading or null, kit]
	for got: Array in rows.get("points", []):
		var row: Array = got[0]
		spots.append([Vector2(float(row[1]), float(row[2])), row[5], got[1]])
	for part: String in ["lines", "areas"]:
		for got: Array in rows.get(part, []):
			for p: Vector2 in (got[0][1] as PackedVector2Array):
				if SceneryStreamer.in_block(key, p):
					spots.append([p, null, got[1]])
					break
	var memo = {} if spots.size() >= MEMO_FROM else null
	for s: Array in spots:
		var p: Vector2 = s[0]
		var at := SceneryStreamer.stand(n, p, memo)
		if is_nan(at.x):
			out["skipped"] += 1
			continue
		if not is_equal_approx(at.x, p.x) or not is_equal_approx(at.z, p.y):
			out["moved"] += 1
		var turn := deg_to_rad(float(s[1])) if s[1] != null else 0.0
		# (a heading is clockwise from north; a yaw about +y is anticlockwise from -z)
		var model := "post_" + str((s[2] as Dictionary).get("round", ""))
		if not (out["items"] as Dictionary).has(model):
			out["items"][model] = []
		(out["items"][model] as Array).append(Transform3D(Basis(Vector3.UP, -turn), at - o))
	return out


## The post for model "post_ROUND", in its round's colour, stood on the ground (its foot at the origin).
static func mesh(model: String) -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(POST_W, POST_H, POST_W)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROUND_COLOURS.get(model.trim_prefix("post_"), Color(0.9, 0.9, 0.9))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.35
	var arrays := box.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += POST_H * 0.5
	arrays[Mesh.ARRAY_VERTEX] = v
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mat)
	return out
