class_name Towers
extends RefCounted
## A city's real skyline: its tall buildings (40 m and more), its big ones (2,500 m² and more) and a tall building's
## parts (its podium, its setbacks, its spire's stages), as the map has them in the features' "towers"
## (tools/feature_bake.py; RealRegion.add_features makes each an area of kind "tower", or "skyscraper" from
## SKYSCRAPER m up so it's seen from miles off). Each is its own outline drawn straight up from the ground (or from where
## a part starts above it) to its height, in the colour the map gives its walls or the colour of what it is (an office's
## glass, a block of flats' render), its floors in bands of glass that light up after dark.
##
## A row of the cell's buildings.json standing inside a tower's outline isn't drawn by the road block
## (BuildingLooks.of says "tower"), so a tower is drawn once, whole, at its real height. Like all scenery it has no
## collision and never touches a road or the land.

## Bumped when what a block lays out changes.
const VERSION := 1
## A tower at least this tall (m) is a "skyscraper" row, seen from further off.
const SKYSCRAPER := 100.0
## How far its walls go down under the ground (m), as the buildings'.
const SKIRT := AdventureProps.SKIRT
## A storey (m) and the band of glass along each.
const STOREY := 3.6
const BAND := 1.7
## A tower's floors are banded every this many storeys once it's taller than this (m), so a tall one stays light.
const TALL_BANDS := [[60.0, 1], [140.0, 2], [INF, 3]]
## Walls shorter than this (m) get no bands.
const BAND_EDGE := 3.0
## The height (m) of a big building the map gives none for, where nothing better is known.
const BIG_HEIGHT := 9.0
## Glass tints for offices and the like, and render for homes.
const GLASS := [Color(0.27, 0.36, 0.42), Color(0.22, 0.3, 0.36), Color(0.33, 0.4, 0.42), Color(0.2, 0.24, 0.3),
	Color(0.42, 0.48, 0.52), Color(0.34, 0.3, 0.26)]
const RENDER := [Color(0.82, 0.8, 0.76), Color(0.74, 0.72, 0.68), Color(0.86, 0.82, 0.74), Color(0.66, 0.62, 0.58),
	Color(0.6, 0.38, 0.3)]
const OFFICES := ["office", "commercial", "retail", "hotel", "bank", "government", "civic", "public"]
const HOMES := ["apartments", "residential", "dormitory", "house", "terrace"]


static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var o := Vector3(key.x * RoadBlock.SIZE, 0.0, key.y * RoadBlock.SIZE)
	var a := AdventureProps.new_arrays()
	var reach := 0.0
	var placed := 0
	var skipped := 0
	for pair: Array in rows.get("areas", []):
		var row: Array = pair[0]
		var ring: PackedVector2Array = row[1]
		if ring.size() < 3:
			continue
		var mid := centre(ring)
		if not SceneryStreamer.in_block(key, mid):
			continue
		reach = maxf(reach, float((pair[1] as Dictionary).get("reach", 2500.0)))
		if build(a, net, ring, row, o):
			placed += 1
		else:
			skipped += 1
	if placed == 0:
		return {"items": {}, "skipped": skipped}
	return {"items": {}, "skipped": skipped, "dress": {"arrays": a, "reach": reach}}


static func mesh(_model: String) -> Mesh:
	return BoxMesh.new()   # (nothing is instanced: each tower is its own shape, made in dress)


## The block's towers as one mesh, lit windows and all, drawn out to their reach.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary or not (data as Dictionary).has("arrays"):
		return
	var mi := MeshInstance3D.new()
	mi.name = "Towers"
	mi.mesh = AdventureProps.to_mesh(data["arrays"])
	mi.material_override = WindowLights.material()
	mi.visibility_range_end = float(data.get("reach", 2500.0)) * clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	node.add_child(mi)


## Tower area row `row` (["tower", ring, height or null, starts at, name, id, {"group", "look"}]) with outline `ring`
## into `a`, in the frame whose corner is `o`. False where the land under it isn't known yet.
static func build(a: Dictionary, net: RoadNet, ring: PackedVector2Array, row: Array, o: Vector3) -> bool:
	# Stood on the lowest of the land under its corners, its walls on down under it.
	var ground := INF
	for p in ring:
		var y := float(net.height.call(p.x, p.y))
		if not is_nan(y):
			ground = minf(ground, y)
	if ground == INF:
		return false
	var mid := centre(ring)
	var extra: Dictionary = row[6] if row.size() > 6 and row[6] is Dictionary else {}
	var look: Dictionary = extra.get("look", {})
	var cls := str(look.get("class", ""))
	var h = row[2]
	if h == null:
		var box := _box(ring)
		var place := BuildingHeights.centre_of(net.region, mid.x, mid.y) if net.region != null else {"size": 3.0, "central": 0.0}
		h = BuildingHeights.guess("block", box.size.x, box.size.y, mid.x, mid.y, float(place["size"]),
			float(place["central"]), "", BIG_HEIGHT)
	var top := ground + float(h)
	var low := float(row[3]) if row[3] != null else 0.0
	var bottom := ground - SKIRT if low < 0.5 else ground + low
	if top <= bottom + 0.5:
		return false
	var roll := absi(hash(str(row[5]) + str(extra.get("group", ""))))
	var glassy := cls in OFFICES or str(look.get("material", "")) == "glass" or (float(h) >= 60.0 and not cls in HOMES)
	var wall: Color
	if look.has("wall_colour"):
		wall = look["wall_colour"]
	elif glassy:
		wall = GLASS[roll % GLASS.size()]
	else:
		wall = RENDER[roll % RENDER.size()]
	var glass: Color = wall.lightened(0.12) if glassy else Color(0.26, 0.3, 0.33)
	var roof: Color = look.get("roof_colour", wall.darkened(0.35).lerp(Color(0.4, 0.4, 0.41), 0.5))
	# Its outline anticlockwise from above, so each wall's outside is to its right.
	var pts := ring.duplicate()
	if _signed_area(pts) > 0.0:
		pts.reverse()
	var n := pts.size()
	var every := 1
	for t: Array in TALL_BANDS:
		if float(h) < float(t[0]):
			every = int(t[1])
			break
	var banded := float(h) >= 12.0
	for i in n:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % n]
		var a0 := Vector3(p0.x, bottom, p0.y) - o
		var a1 := Vector3(p1.x, bottom, p1.y) - o
		var b0 := Vector3(p0.x, top, p0.y) - o
		var b1 := Vector3(p1.x, top, p1.y) - o
		var shade := wall.darkened(0.06 * float(i % 2))
		AdventureProps._quad(a, a0, a1, b1, b0, shade)
		var edge := p1 - p0
		var length := edge.length()
		if not banded or length < BAND_EDGE:
			continue
		# A band of glass along each floor (each lit or not after dark), a hair proud of the wall.
		var out := Vector3(-edge.y, 0.0, edge.x) / length * 0.04
		var inset := edge / length * minf(0.4, length * 0.1)
		var q0 := Vector3(p0.x + inset.x, 0.0, p0.y + inset.y) - o + out
		var q1 := Vector3(p1.x - inset.x, 0.0, p1.y - inset.y) - o + out
		var y := maxf(bottom, ground) + 0.8
		while y + BAND < top - 1.0:
			var c := WindowLights.mark(glass, (q0 + q1) * 0.5 + Vector3(0.0, y, 0.0) + o)
			AdventureProps._quad(a, q0 + Vector3.UP * y, q1 + Vector3.UP * y, q1 + Vector3.UP * (y + BAND), q0 + Vector3.UP * (y + BAND), c)
			y += STOREY * every
	# Its roof.
	var tris := Geometry2D.triangulate_polygon(pts)
	for k in range(0, tris.size() - 2, 3):
		var r0 := Vector3(pts[tris[k]].x, top, pts[tris[k]].y) - o
		var r1 := Vector3(pts[tris[k + 1]].x, top, pts[tris[k + 1]].y) - o
		var r2 := Vector3(pts[tris[k + 2]].x, top, pts[tris[k + 2]].y) - o
		if (r1 - r0).cross(r2 - r0).y >= 0.0:
			AdventureProps._tri(a, r0, r1, r2, roof)
		else:
			AdventureProps._tri(a, r0, r2, r1, roof)
	return true


## A ring's middle (its points' mean: near enough for a building's outline).
static func centre(ring: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for p in ring:
		s += p
	return s / maxf(1.0, float(ring.size()))


static func _signed_area(ring: PackedVector2Array) -> float:
	var s := 0.0
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5


static func _box(ring: PackedVector2Array) -> Rect2:
	var r := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		r = r.expand(p)
	return r
