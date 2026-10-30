class_name Fields
extends RefCounted
## Land texture (Ride Anywhere v2, phase D round 2, D5: docs/scenery.md): whole areas that look like what the map says
## they are. Vineyards as rows of vines following the slope, orchards and olive groves in a grid, glasshouses, plastic
## houses and polytunnels, nurseries and allotments, salt pans in pink and white, fish cages and oyster tables on the
## water, rice paddies stepped and flooded where the place is hot and wet; walls, hedges, fences and retaining walls
## along their mapped lines; quarries with their cut faces, benches and yellow machines, pithead gear, military land
## fenced with red flags and warning signs, firing ranges, cemeteries with rows of headstones in the place's style,
## golf courses with fairways, greens, bunkers and flags, race tracks on their real line, theme parks with a coaster.
##
## The streamer (SceneryStreamer) hands lay_out a block's rows of the kinds whose kit row names this script, each with
## its kit (the default with the place's region laid over it), and draws what comes back: every model one MultiMesh a
## block. An area is filled from its own polygon by scanlines on a grid anchored to the region (so an area over several
## blocks fills each with its own part, meeting at the edges), a line is cut into pieces measured from its first point
## (each the block's its middle is in). Everything is a few unit pieces stood, stretched and sheared by its transform.
##
## Simon's first rule, as here: nothing stands on a road or its verge (every piece's middle and ends are checked against
## the roads' own lines: CLEAR past the verge, and round a junction its mouth), so a lane runs between its own walls and
## a wall stops short of the carriageway; nothing changes the land (a quarry's face, a paddy's terrace and a salt pan are
## meshes over the ground, never a cut), and nothing here has collision. The second: every kind wherever the map has it,
## its look by region from the kit library's rows with a default for anywhere a region has none; nothing is keyed to a
## place (a paddy is a rice field the map tags, or farmland where the place's climate is hot and wet).

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 1
const SIZE := 512.0   # RoadBlock.SIZE
## How far past a road's verge a piece's middle and ends must be (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## At most this many pieces a block, all models together (the busiest blocks thin out the far-reaching fill first).
const MOST := 6000
## A line is cut into pieces at most this long (m), each on the land at its ends.
const STEP := 4.0
## Land steeper than this (rise over run) has its vines down the slope, gentler along the field's long axis.
const STEEP := 0.12
## A paddy's tile (m) and a salt pan's.
const PADDY := 6.0
const PAN := 10.0
## The climates (Köppen, from the place's profile) whose farmland is rice paddies, where a region's kit names them.
const HOT_WET := ["Af", "Am", "Aw", "As", "Cfa", "Cwa", "Cwb"]
## Words in a works' or quarry's name that make it a mine (pithead gear over its shaft).
const MINE_WORDS := ["colliery", "mine", " pit", "pit ", "zeche", "mina ", "shaft", "charbonnage", "bergwerk", "kopalnia", "důl"]

## The pieces' flags (UV2.x): matte, glossy (glass, water: the sky in it), lit at night (grow lights), a flag that waves.
const MATTE := 0.0
const GLOSS := 1.0
const GLOW := 2.0
const WAVE := 3.0

## The stones walls and graves are made of (vertex colours).
const STONES := {
	"gritstone": Color(0.36, 0.34, 0.3), "limestone": Color(0.72, 0.7, 0.64), "fieldstone": Color(0.5, 0.48, 0.44),
	"granite": Color(0.55, 0.54, 0.53), "basalt": Color(0.25, 0.25, 0.26), "sandstone": Color(0.66, 0.55, 0.4),
	"slate": Color(0.3, 0.32, 0.34), "render": Color(0.86, 0.84, 0.78), "concrete": Color(0.62, 0.61, 0.58),
	"adobe": Color(0.68, 0.52, 0.38), "laterite": Color(0.6, 0.36, 0.24), "brick": Color(0.52, 0.27, 0.2),
	"marble": Color(0.9, 0.9, 0.88), "white": Color(0.93, 0.93, 0.9)}
## The fences a field is closed with (fence models "fence:STYLE").
const FENCES := ["wood_wire", "barbed", "rail", "roundpole", "security", "catch", "wire"]
## The trees an orchard is planted with ("tree:KIND").
const TREES := ["apple", "olive", "citrus", "date", "coconut", "cypress", "yew"]
## The headstones a cemetery has, by its region's custom ("stone:STYLE").
const GRAVES := ["slab", "cross", "haka", "muslim", "tomb", "flat"]
## The houses of a glasshouse area ("house:KIND"): [length, width, gap between] (m).
const HOUSES := {"glass": [32.0, 9.6, 1.2], "glass_lit": [32.0, 9.6, 1.2], "plastic": [40.0, 22.0, 2.0], "tunnel": [30.0, 8.0, 2.5]}

const GREEN := Color(0.22, 0.36, 0.13)
const LEAF := Color(0.3, 0.45, 0.16)
const WOOD := Color(0.4, 0.3, 0.2)
const DARK := Color(0.1, 0.1, 0.11)
const STEEL := Color(0.45, 0.47, 0.49)
const YELLOW := Color(0.92, 0.7, 0.08)
const RED := Color(0.8, 0.08, 0.06)
const WHITE := Color(0.92, 0.92, 0.9)
const SAND := Color(0.86, 0.79, 0.6)
const MUD := Color(0.36, 0.3, 0.2)

static var _meshes := {}
static var _meshes_lock := Mutex.new()
static var _material: ShaderMaterial
static var _ticked := -1


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of this script's rows (SceneryStreamer's: {"points": [[row, kit], ...], "lines": ...,
## "areas": ...}, in the region frame): {"items": {model: [Transform3D in the block's frame, its corner at key * SIZE]},
## "dress": whether its lamps and flags want the clock, "skipped": pieces left out by the roads or the cap}. Safe on a
## worker.
static func lay_out(n: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := _Block.new(n, key)
	# (the lines first: the walls and hedges by the road are what a rider sees most of; then the areas, the smaller
	# first, so a block full of farmland still has its cemetery and its quarry)
	for pair: Array in rows.get("lines", []):
		var row: Array = pair[0]
		var line: PackedVector2Array = row[1]
		if line.size() >= 2:
			_line(b, str(row[0]), line, row[2], row[3], pair[1])
	var areas: Array = []
	for pair: Array in rows.get("areas", []):
		var ring: PackedVector2Array = pair[0][1]
		if ring.size() >= 3:
			areas.append([absf(signed_area(ring)), pair])
	areas.sort_custom(func(x, y): return x[0] < y[0])
	for a: Array in areas:
		var row: Array = a[1][0]
		_area(b, str(row[0]), row[1], str(row[4]), str(row[3]) if row[3] != null else "", a[1][1], float(a[0]))
	var out := {"items": b.items, "skipped": b.skipped}
	if b.lively:
		out["dress"] = true
	return out


static func _line(b: _Block, kind: String, line: PackedVector2Array, height, width, k: Dictionary) -> void:
	match kind:
		"wall", "retaining_wall", "hedge", "fence":
			_boundary(b, kind, line, height, k)
		"race_track":
			_track(b, line, float(width) if width != null else float(k.get("width", 10.0)), k)
		"roller_coaster":
			_coaster_line(b, line, k)
		_:
			_boundary(b, "fence", line, null, k)


static func _area(b: _Block, kind: String, ring: PackedVector2Array, id: String, name: String, k: Dictionary, area: float) -> void:
	if b.full():
		b.skipped += 1
		return
	match kind:
		"wall", "retaining_wall", "hedge", "fence":
			_boundary(b, kind, closed(ring), null, k)
		"vineyard": _vineyard(b, ring, k)
		"orchard": _orchard(b, ring, k)
		"plant_nursery": _nursery(b, ring, k)
		"greenhouses": _glasshouses(b, ring, k)
		"allotments": _allotments(b, ring, k)
		"salt_pond": _salt(b, ring, k, id)
		"aquaculture": _aquaculture(b, ring, k)
		"paddy": _paddies(b, ring, k)
		"farmland":
			if _hot_wet(b, ring, k):
				_paddies(b, ring, k)
		"quarry": _quarry(b, ring, k, id, name)
		"works": _works(b, ring, k, id, name, area)
		"military", "danger_area": _military(b, ring, k, false)
		"range": _military(b, ring, k, true)
		"cemetery", "grave_yard": _cemetery(b, ring, k, kind == "grave_yard")
		"golf_fairway": _drape(b, ring, 8.0, "drape:fairway", k, true)
		"golf_green": _green(b, ring, k)
		"golf_bunker": _drape(b, ring, 3.0, "drape:sand", k)
		"golf_tee": _drape(b, ring, 3.0, "drape:tee", k)
		"race_track": _circuit(b, ring, k)
		"theme_park": _theme_park(b, ring, k, area)
		"zoo": _boundary(b, "fence", closed(ring), null, {"fence": "wire"})
		_: pass   # (golf_course: its parts are mapped on their own)


# ---------------------------------------------------------------------------- walls, hedges and fences

## A wall, hedge, fence or retaining wall along `line`: pieces of at most STEP on the land at their ends, each left
## out where its middle or an end is within CLEAR of a road's verge (so it stops short of the carriageway, never
## crosses it). Its look from the kit: "stone", "h", "t" for a wall; "fence" for a fence.
static func _boundary(b: _Block, kind: String, line: PackedVector2Array, height, k: Dictionary) -> void:
	var model := ""
	var h := 1.0
	var t := 0.6
	match kind:
		"wall":
			var stone := str(k.get("stone", "fieldstone"))
			model = "wall:" + (stone if STONES.has(stone) else "fieldstone")
			h = float(height) if height != null and float(height) > 0.3 and float(height) < 4.0 else float(k.get("h", 1.2))
			t = float(k.get("t", 0.6))
		"retaining_wall":
			var stone := str(k.get("stone", "concrete"))
			model = "wall:" + (stone if STONES.has(stone) else "concrete")
			h = float(height) if height != null and float(height) > 0.3 and float(height) < 8.0 else float(k.get("h", 1.8))
			t = 0.45
		"hedge":
			model = "hedge:" + str(k.get("leaf", "green"))
			h = float(k.get("h", 1.7))
			t = float(k.get("t", 1.1))
		_:
			var style := str(k.get("fence", "wood_wire"))
			model = "fence:" + (style if FENCES.has(style) else "wood_wire")
			t = 0.2
	var pad := CLEAR + t * 0.5
	for piece: Array in steps(b, line, STEP if kind != "fence" else 3.0):
		if b.full():
			return
		var p: Vector2 = piece[0]
		var q: Vector2 = piece[1]
		if not (b.clear((p + q) * 0.5, pad) and b.clear(p, pad) and b.clear(q, pad)):
			b.skipped += 1
			continue
		var yp := b.ground(p)
		var yq := b.ground(q)
		if is_nan(yp) or is_nan(yq):
			continue
		# (sunk a little, so a piece on a bump doesn't show daylight under it)
		var sink := 0.25 if kind != "fence" else 0.0
		b.put(model, slope(b.local(p, yp - sink), b.local(q, yq - sink), t if kind != "fence" else 1.0, h + sink if kind != "fence" else 1.0))


# ---------------------------------------------------------------------------- vines, trees and glass

## Rows of vines over `ring`, each row along the field's long axis (down the slope where it's steep), 9 m pieces of
## trellis on the land at their ends; a bush vine region (kit "vine": "bush") has its vines as low bushes in
## a grid instead.
static func _vineyard(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var dir := _row_dir(b, ring)
	var gap := float(k.get("rows", 2.2))
	if str(k.get("vine", "trellis")) == "bush":
		for p: Vector2 in grid(b, ring, dir, 1.8, gap, 1.0, CLEAR + 1.0, 0.0):
			b.stand("bush_vine", p, dir, 1.0)
		return
	var along := 9.0
	for p: Vector2 in grid(b, ring, dir, along, gap, 1.5, CLEAR + 1.0, along):
		var a := p - dir * along * 0.5
		var c := p + dir * along * 0.5
		var ya := b.ground(a)
		var yc := b.ground(c)
		if is_nan(ya) or is_nan(yc):
			continue
		b.put("vine", slope(b.local(a, ya - 0.1), b.local(c, yc - 0.1), 1.0, 1.0))


## An orchard's trees in a grid (every other row half a space on), the kit's "tree" ("apple", "olive", "citrus",
## "date", "coconut").
static func _orchard(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var tree := str(k.get("tree", "apple"))
	if not TREES.has(tree):
		tree = "apple"
	var space := float(k.get("space", 6.0))
	for p: Vector2 in grid(b, ring, axis(ring), space, space, 2.0, CLEAR + 2.0, 0.0, true):
		b.stand("tree:" + tree, p, Vector2(cos(seed_of(p) * TAU), sin(seed_of(p) * TAU)), lerpf(0.8, 1.15, seed_of(p + Vector2(7, 3))))


## A plant nursery: rows of young shrubs, with a polytunnel at one end of the bigger.
static func _nursery(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var dir := axis(ring)
	var made := 0
	for p: Vector2 in grid(b, ring, dir, 30.0, 10.0, 2.0, CLEAR + 5.0, 30.0):
		if made % 3 == 0:
			b.stand("house:tunnel", p, dir, 1.0, -0.6)
		else:
			for i in 8:
				for j in 3:
					var q := p + dir * (float(i) - 3.5) * 3.5 + Vector2(-dir.y, dir.x) * (float(j) - 1.0) * 2.6
					if b.clear(q, CLEAR):
						b.stand("shrub", q, dir, lerpf(0.7, 1.2, seed_of(q)))
		made += 1


## Glasshouses, plastic houses or polytunnels (the kit's "house") over `ring` in rows along its long axis, as many as
## fit; glass with "lit" true glows at night with its grow lights.
static func _glasshouses(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var kind := str(k.get("house", "glass"))
	if kind == "glass" and bool(k.get("lit", false)):
		kind = "glass_lit"
		b.lively = true
	if not HOUSES.has(kind):
		kind = "glass"
	var dims: Array = HOUSES[kind]
	var dir := axis(ring)
	for p: Vector2 in grid(b, ring, dir, float(dims[0]) + float(dims[2]), float(dims[1]) + float(dims[2]), 1.0,
			CLEAR + float(dims[1]) * 0.5, float(dims[0])):
		var low := b.ground(p)
		for e: Vector2 in [p + dir * float(dims[0]) * 0.5, p - dir * float(dims[0]) * 0.5]:
			low = minf(low, b.ground(e))
		if is_nan(low):
			continue
		b.put("house:" + kind, piece(b.local(p, low), dir, Vector3.ONE))


## Allotments: plots of dug earth and rows of crops, a shed to every third.
static func _allotments(b: _Block, ring: PackedVector2Array, _k: Dictionary) -> void:
	var dir := axis(ring)
	for p: Vector2 in grid(b, ring, dir, 6.0, 11.0, 1.0, CLEAR + 4.0, 0.0):
		b.drape("plot", p, dir, 1.0)
		if seed_of(p) < 0.34:
			b.stand("shed", p + Vector2(-dir.y, dir.x) * 4.2, dir, 1.0)


# ---------------------------------------------------------------------------- water and salt

## Salt pans: flat beds in pink, white and brine, each pan a few tiles of PAN square (pans of 40 by 30 m, their colour
## by the pan), a little apart in height so their edges show, at the sea's level at least; a heap of salt to a pan in
## twenty.
static func _salt(b: _Block, ring: PackedVector2Array, _k: Dictionary, _id: String) -> void:
	var dir := axis(ring)
	var across := Vector2(-dir.y, dir.x)
	for p: Vector2 in grid(b, ring, dir, PAN, PAN, 0.5, CLEAR + PAN * 0.75, 0.0):
		var pan := Vector2i(floori(p.dot(dir) / 40.0), floori(p.dot(across) / 30.0))
		var s := seed_of(Vector2(pan))
		var model := "pan:pink" if s < 0.45 else ("pan:white" if s < 0.8 else "pan:brine")
		var top := maxf(b.top(p, dir, PAN), 0.0) + 0.06 + s * 0.08
		if is_nan(top):
			continue
		b.slab(model, p, dir, PAN, top, top - 1.2)
		if s > 0.95 and seed_of(p) < 0.08:
			b.stand("salt_heap", p, dir, lerpf(0.8, 1.3, seed_of(p + Vector2.ONE)))


## Fish cages, mussel rafts or oyster tables (the kit's "farm") on the water over `ring`; on land (a fish farm's
## ponds) ponds as flat tiles of water.
static func _aquaculture(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	var dir := axis(ring)
	var mid := centroid(ring)
	var h := b.bare(mid)
	if is_nan(h):
		h = 0.0
	if h > 0.6:
		for p: Vector2 in grid(b, ring, dir, PAN, PAN, 1.0, CLEAR + PAN, 0.0):
			var top := b.top(p, dir, PAN) + 0.15
			if not is_nan(top):
				b.slab("pond", p, dir, PAN, top, top - 1.5)
		return
	match str(k.get("farm", "cages")):
		"oysters":
			for p: Vector2 in grid(b, ring, dir, 7.0, 3.0, 2.0, CLEAR + 4.0, 6.0):
				b.put("oyster_table", piece(b.local(p, 0.0), dir, Vector3.ONE))
		"rafts":
			for p: Vector2 in grid(b, ring, dir, 14.0, 14.0, 3.0, CLEAR + 8.0, 0.0):
				b.put("raft", piece(b.local(p, 0.0), dir, Vector3.ONE))
		_:
			for p: Vector2 in grid(b, ring, dir, 50.0, 50.0, 12.0, CLEAR + 14.0, 0.0):
				b.put("cage", piece(b.local(p, 0.0), dir, Vector3.ONE))


## Rice paddies over `ring`: tiles of PADDY square, each flat at the top of the land under it (so down a hillside they
## step, terrace by terrace), flooded and mirroring the sky or green with rice, field by field.
static func _paddies(b: _Block, ring: PackedVector2Array, _k: Dictionary) -> void:
	var dir := axis(ring)
	var across := Vector2(-dir.y, dir.x)
	for p: Vector2 in grid(b, ring, dir, PADDY, PADDY, 0.5, CLEAR + PADDY * 0.75, 0.0):
		var top := b.top(p, dir, PADDY)
		var low := b.low(p, dir, PADDY)
		if is_nan(top) or is_nan(low):
			continue
		var field := Vector2i(floori(p.dot(dir) / 24.0), floori(p.dot(across) / 18.0))
		var model := "paddy:water" if seed_of(Vector2(field) + Vector2(0.5, 9.0)) < 0.65 else "paddy:rice"
		b.slab(model, p, dir, PADDY, top + 0.12, low - 0.4)


## Whether farmland `ring` is paddies: where its region's kit names "climates" and the place's is one of them.
static func _hot_wet(b: _Block, ring: PackedVector2Array, k: Dictionary) -> bool:
	var climates: Array = k.get("climates", [])
	if climates.is_empty():
		return false
	var mid := centroid(ring)
	return climates.has(b.koppen(mid))


# ---------------------------------------------------------------------------- quarries, works, the army's land

## A quarry: where the land rises outside its edge, a cut face of rock in benches up to the land's height (a mesh
## stood against the hillside, never a cut); elsewhere a low bank of spoil; a few yellow machines and heaps of stone
## round its middle (its floor is the land cover's: the Terrain's). A mine by name has its pithead gear.
static func _quarry(b: _Block, ring: PackedVector2Array, k: Dictionary, id: String, name: String) -> void:
	var cw := signed_area(ring) > 0.0
	for pc: Array in steps(b, closed(ring), 10.0):
		if b.full():
			return
		var p: Vector2 = pc[0]
		var q: Vector2 = pc[1]
		var f := (q - p).normalized()
		var inward := Vector2(-f.y, f.x) * (1.0 if cw else -1.0)
		var mid := (p + q) * 0.5
		var outside := b.bare(mid - inward * 15.0)
		var inside := b.bare(mid + inward * 12.0)
		if is_nan(outside) or is_nan(inside):
			continue
		var rise := outside - inside
		if rise > 3.0:
			for i in mini(4, int(ceil(rise / 5.0))):
				var off := inward * (2.0 + 6.0 * i)
				var a := p + off
				var c := q + off
				if not (b.clear(a, CLEAR + 1.0) and b.clear(c, CLEAR + 1.0)):
					continue
				var ya := b.ground(a)
				var yc := b.ground(c)
				var h := minf(rise - 5.0 * i, 5.0) + 0.5
				if is_nan(ya) or is_nan(yc) or h <= 0.6:
					continue
				b.put("bench", slope(b.local(a, ya - 0.5), b.local(c, yc - 0.5), 5.5, h))
		else:
			var a := p + inward * 3.0
			var c := q + inward * 3.0
			if b.clear(a, CLEAR + 3.0) and b.clear(c, CLEAR + 3.0):
				var ya := b.ground(a)
				var yc := b.ground(c)
				if not is_nan(ya) and not is_nan(yc):
					b.put("spoil", slope(b.local(a, ya - 0.3), b.local(c, yc - 0.3), 6.0, 2.6))
	var mid := centroid(ring)
	if not Geometry2D.is_point_in_polygon(mid, ring):
		mid = ring[0].lerp(ring[ring.size() / 2], 0.5)
	var turn := seed_of(Vector2(hash(id) % 1000, 3)) * TAU
	var dir := Vector2(cos(turn), sin(turn))
	var at := 0
	for m: String in ["excavator", "dumper", "heap", "loader", "heap", "dumper"]:
		var q := mid + dir.rotated(at * 1.1) * (12.0 + 9.0 * at)
		at += 1
		if Geometry2D.is_point_in_polygon(q, ring) and b.clear(q, CLEAR + 5.0):
			b.stand(m, q, dir.rotated(at * 0.7), 1.0)
	if _is_mine(name):
		_headframe(b, ring)


## Works: pithead gear over a mine's shaft (by its name), a chimney over a big works.
static func _works(b: _Block, ring: PackedVector2Array, _k: Dictionary, _id: String, name: String, area: float) -> void:
	if _is_mine(name):
		_headframe(b, ring)
	elif area > 30000.0:
		var mid := centroid(ring)
		if Geometry2D.is_point_in_polygon(mid, ring) and b.mine(mid) and b.clear(mid, CLEAR + 4.0):
			b.stand("chimney", mid, Vector2(0, 1), 1.0)


static func _headframe(b: _Block, ring: PackedVector2Array) -> void:
	var mid := centroid(ring)
	if b.mine(mid) and b.clear(mid, CLEAR + 12.0):
		b.stand("headframe", mid, axis(ring), 1.0)


static func _is_mine(name: String) -> bool:
	var n := " " + name.to_lower() + " "
	for w: String in MINE_WORDS:
		if w in n:
			return true
	return false


## Military land or a danger area: a security fence round it (a range's a wire one), red flags on poles along it and
## warning signs by them; a range a tall red flag at its first corner too.
static func _military(b: _Block, ring: PackedVector2Array, k: Dictionary, range_: bool) -> void:
	var fk := k.duplicate()
	fk["fence"] = str(k.get("fence", "wire" if range_ else "security"))
	_boundary(b, "fence", closed(ring), null, fk)
	var every := float(k.get("flags", 150.0))
	var cw := signed_area(ring) > 0.0
	var s := 0.0
	var next := every * 0.5
	var line := closed(ring)
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var d := p.distance_to(q)
		while next < s + d:
			var at := p.lerp(q, (next - s) / d)
			var f := (q - p) / d
			var inward := Vector2(-f.y, f.x) * (1.0 if cw else -1.0)
			var flag := at + inward * 2.0
			if b.mine(flag) and b.clear(flag, CLEAR + 1.0):
				b.stand("flag:red", flag, f, 1.0)
				b.lively = true
			var sign := at - inward * 1.2
			if b.mine(sign) and b.clear(sign, CLEAR + 0.6):
				b.stand("sign:danger", sign, -inward, 1.0)
			next += every
		s += d
	if range_ and b.mine(ring[0]):
		var c := centroid(ring)
		var at := ring[0].lerp(c, 0.04)
		if b.clear(at, CLEAR + 1.0):
			b.stand("flag:range", at, Vector2(0, 1), 1.0)
			b.lively = true


# ---------------------------------------------------------------------------- cemeteries, golf, tracks, parks

## A cemetery's rows of headstones in its region's style (the kit's "stone": "slab", "cross", "haka", "muslim",
## "tomb", "flat"), with a dark tree to a space of the kit's "trees" ("yew", "cypress"); an old churchyard's stones
## lean.
static func _cemetery(b: _Block, ring: PackedVector2Array, k: Dictionary, old: bool) -> void:
	var style := str(k.get("graves", "slab"))
	if not GRAVES.has(style):
		style = "slab"
	var dir := axis(ring)
	var face := Vector2(-dir.y, dir.x)
	var space := Vector2(float(k.get("along", 1.6)), float(k.get("across", 2.8)))
	if style == "tomb":
		space = Vector2(2.6, 3.6)
	for p: Vector2 in grid(b, ring, dir, space.x, space.y, 1.5, CLEAR + 1.5, 0.0):
		var s := seed_of(p)
		if s < 0.12:
			continue   # (a gap in the row)
		var model := "stone:" + style
		if style == "flat" and s > 0.84:
			model = "stone:slab"
		var y := b.ground(p)
		if is_nan(y):
			continue
		var turn := Basis(Vector3.UP, atan2(face.x, face.y))
		if old:
			turn = turn * Basis(Vector3.RIGHT, (s - 0.5) * 0.25) * Basis(Vector3.FORWARD, (seed_of(p + Vector2.ONE) - 0.5) * 0.14)
		var sc := lerpf(0.85, 1.15, seed_of(p + Vector2(3, 1)))
		b.put(model, Transform3D(turn.scaled(Vector3.ONE * sc), b.local(p, y - 0.05)))
	var trees := str(k.get("trees", ""))
	if trees != "":
		for p: Vector2 in grid(b, ring, dir, 21.0, 19.0, 3.0, CLEAR + 3.0, 0.0, true):
			b.stand("tree:" + trees, p + face * 1.4, dir, lerpf(0.8, 1.2, seed_of(p)))


## A golf green: its tile and a flag in its middle.
static func _green(b: _Block, ring: PackedVector2Array, k: Dictionary) -> void:
	_drape(b, ring, 4.0, "drape:green", k)
	var mid := centroid(ring)
	if b.mine(mid) and Geometry2D.is_point_in_polygon(mid, ring) and b.clear(mid, CLEAR):
		b.stand("golf_flag", mid, Vector2(0, 1), 1.0)
		b.lively = true


## `ring` covered in tiles of `model`, `size` square, each laid on the land's slope under it a little above it (a
## fairway's mown stripes alternate row by row when `stripes`).
static func _drape(b: _Block, ring: PackedVector2Array, size: float, model: String, _k: Dictionary, stripes := false) -> void:
	var dir := axis(ring)
	var across := Vector2(-dir.y, dir.x)
	for p: Vector2 in grid(b, ring, dir, size, size, 0.0, CLEAR + size * 0.75, 0.0):
		var m := model
		if stripes and posmod(floori(p.dot(across) / size), 2) == 1:
			m = model + "2"
		b.drape(m, p, dir, size)


## A race track on its real line: its tarmac (red and white kerbs at its edges) as pieces on the land, `width` wide,
## where it isn't a road the ride takes already; and a tyre wall either side.
static func _track(b: _Block, line: PackedVector2Array, width: float, _k: Dictionary) -> void:
	width = clampf(width, 4.0, 18.0)
	for pc: Array in steps(b, line, 6.0):
		if b.full():
			return
		var p: Vector2 = pc[0]
		var q: Vector2 = pc[1]
		var pad := CLEAR + width * 0.5
		if not (b.clear((p + q) * 0.5, pad) and b.clear(p, pad) and b.clear(q, pad)):
			b.skipped += 1
			continue
		var yp := b.ground(p)
		var yq := b.ground(q)
		if is_nan(yp) or is_nan(yq):
			continue
		b.put("track", slope(b.local(p, yp + 0.04), b.local(q, yq + 0.04), width, 1.0))
		var f := (q - p).normalized()
		var side := Vector2(-f.y, f.x) * (width * 0.5 + 5.0)
		for s: float in [-1.0, 1.0]:
			var a := p + side * s
			var c := q + side * s
			if b.clear(a, CLEAR + 0.5) and b.clear(c, CLEAR + 0.5):
				var ya := b.ground(a)
				var yc := b.ground(c)
				if not is_nan(ya) and not is_nan(yc):
					b.put("tyres", slope(b.local(a, ya), b.local(c, yc), 1.0, 1.0))


## A circuit's land: a catch fence round it and a grandstand on its longest side, facing in.
static func _circuit(b: _Block, ring: PackedVector2Array, _k: Dictionary) -> void:
	_boundary(b, "fence", closed(ring), null, {"fence": "catch"})
	var cw := signed_area(ring) > 0.0
	var best := 0
	for i in ring.size():
		if ring[i].distance_to(ring[(i + 1) % ring.size()]) > ring[best].distance_to(ring[(best + 1) % ring.size()]):
			best = i
	var p := ring[best]
	var q := ring[(best + 1) % ring.size()]
	if p.distance_to(q) < 60.0:
		return
	var f := (q - p).normalized()
	var inward := Vector2(-f.y, f.x) * (1.0 if cw else -1.0)
	var at := (p + q) * 0.5 + inward * 14.0
	if b.mine(at) and b.clear(at, CLEAR + 25.0):
		b.stand("grandstand", at, inward, 1.0)


## A theme park big enough for one: a roller coaster in its middle, and a big wheel beside it.
static func _theme_park(b: _Block, ring: PackedVector2Array, _k: Dictionary, area: float) -> void:
	if area < 15000.0:
		return
	var mid := centroid(ring)
	var dir := axis(ring)
	if Geometry2D.is_point_in_polygon(mid, ring) and b.mine(mid) and b.clear(mid, CLEAR + 70.0):
		b.stand("coaster", mid, dir, 1.0)
	var wheel := mid + Vector2(-dir.y, dir.x) * 70.0
	if Geometry2D.is_point_in_polygon(wheel, ring) and b.mine(wheel) and b.clear(wheel, CLEAR + 25.0):
		b.stand("big_wheel", wheel, dir, 1.0)


## A roller coaster on its mapped line: its track rising and falling over the land on legs.
static func _coaster_line(b: _Block, line: PackedVector2Array, _k: Dictionary) -> void:
	var s := 0.0
	for pc: Array in steps(b, line, 4.0):
		var p: Vector2 = pc[0]
		var q: Vector2 = pc[1]
		s = float(pc[2])
		if not (b.clear(p, CLEAR + 1.0) and b.clear(q, CLEAR + 1.0)):
			continue
		var yp := b.ground(p)
		var yq := b.ground(q)
		if is_nan(yp) or is_nan(yq):
			continue
		var hp := 4.0 + 12.0 * (0.5 + 0.5 * sin(s / 35.0))
		var hq := 4.0 + 12.0 * (0.5 + 0.5 * sin((s + p.distance_to(q)) / 35.0))
		b.put("coaster_rail", slope(b.local(p, yp + hp), b.local(q, yq + hq), 1.0, 1.0))
		if posmod(int(s / 4.0), 2) == 0:
			b.put("coaster_leg", Transform3D(Basis().scaled(Vector3(1, hp, 1)), b.local(p, yp)))


# ---------------------------------------------------------------------------- the grid and the geometry

## The middles of a grid over the part of `ring` in block `b`: rows `dv` apart across `dir` and points `du` apart along
## it, both anchored to the region (so blocks meet), each at least `inset` in from the ring along its row (and `fit`
## long pieces wholly inside it), clear of every road by `pad`; the rows staggered half a space when `stagger`.
static func grid(b: _Block, ring: PackedVector2Array, dir: Vector2, du: float, dv: float, inset: float, pad: float,
		fit: float, stagger := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var across := Vector2(-dir.y, dir.x)
	var uv := PackedVector2Array()
	uv.resize(ring.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in ring.size():
		var q := Vector2(ring[i].dot(dir), ring[i].dot(across))
		uv[i] = q
		lo = lo.min(q)
		hi = hi.max(q)
	# (the block's own box in the grid's frame, a little over, so a piece whose middle is in the block is found)
	var blo := Vector2(INF, INF)
	var bhi := Vector2(-INF, -INF)
	for c: Vector2 in [b.corner, b.corner + Vector2(SIZE, 0), b.corner + Vector2(0, SIZE), b.corner + Vector2(SIZE, SIZE)]:
		var q := Vector2(c.dot(dir), c.dot(across))
		blo = blo.min(q)
		bhi = bhi.max(q)
	lo = lo.max(blo)
	hi = hi.min(bhi)
	if lo.x >= hi.x or lo.y >= hi.y:
		return out
	var v := (floorf(lo.y / dv) + 0.5) * dv
	var row := floori(lo.y / dv)
	while v < hi.y:
		var xs := crossings(uv, v)
		var shift := du * 0.5 if stagger and posmod(row, 2) == 1 else 0.0
		for j in range(0, xs.size() - 1, 2):
			var a := xs[j] + inset + fit * 0.5
			var c := xs[j + 1] - inset - fit * 0.5
			if a > c:
				continue
			var u := (floorf((a - shift) / du) + 0.5) * du + shift
			if u < a:
				u += du
			while u <= c:
				var p := dir * u + across * v
				if b.mine(p):
					if b.clear(p, pad):
						out.append(p)
					else:
						b.skipped += 1
				u += du
		v += dv
		row += 1
		if out.size() + b.count > MOST:
			break
	return out


## Where row `v` (the grid frame's) crosses polygon `uv`: the u of each crossing, in order (in and out in pairs).
static func crossings(uv: PackedVector2Array, v: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := uv.size()
	for i in n:
		var a := uv[i]
		var c := uv[(i + 1) % n]
		if (a.y <= v) == (c.y <= v):
			continue
		out.append(a.x + (v - a.y) / (c.y - a.y) * (c.x - a.x))
	out.sort()
	return out


## The pieces of `line` (region frame) at most `step` long, each in the block its middle is in: [[a, b, s along], ...]
## (measured from the line's first point, so a line over two blocks meets itself).
static func steps(b: _Block, line: PackedVector2Array, step: float) -> Array:
	var out := []
	var s := 0.0
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var d := p.distance_to(q)
		if d < 0.05:
			continue
		var n := maxi(1, int(ceil(d / step)))
		for j in n:
			var a := p.lerp(q, float(j) / n)
			var c := p.lerp(q, float(j + 1) / n)
			if b.mine((a + c) * 0.5):
				out.append([a, c, s + d * float(j) / n])
		s += d
	return out


## `ring` with its first point again at the end (a line all the way round).
static func closed(ring: PackedVector2Array) -> PackedVector2Array:
	var out := ring.duplicate()
	if out.size() > 0 and out[0] != out[out.size() - 1]:
		out.append(out[0])
	return out


## The long axis of `ring` (a unit direction: its points' first principal axis).
static func axis(ring: PackedVector2Array) -> Vector2:
	var m := Vector2.ZERO
	for p in ring:
		m += p
	m /= maxf(1.0, ring.size())
	var xx := 0.0
	var xz := 0.0
	var zz := 0.0
	for p in ring:
		var d := p - m
		xx += d.x * d.x
		xz += d.x * d.y
		zz += d.y * d.y
	var t := 0.5 * atan2(2.0 * xz, xx - zz)
	return Vector2(cos(t), sin(t))


## A vineyard's rows: down the slope where the land under its middle is steeper than STEEP, else its long axis.
static func _row_dir(b: _Block, ring: PackedVector2Array) -> Vector2:
	var mid := centroid(ring)
	var e := b.bare(mid + Vector2(10, 0)) - b.bare(mid - Vector2(10, 0))
	var s := b.bare(mid + Vector2(0, 10)) - b.bare(mid - Vector2(0, 10))
	var g := Vector2(e, s) / 20.0
	if not is_nan(g.x) and not is_nan(g.y) and g.length() > STEEP:
		return g.normalized()
	return axis(ring)


static func centroid(ring: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		var cr := p.x * q.y - q.x * p.y
		a += cr
		c += (p + q) * cr
	if absf(a) < 1e-6:
		var m := Vector2.ZERO
		for p in ring:
			m += p
		return m / maxf(1.0, ring.size())
	return c / (3.0 * a)


static func signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## A number in 0..1 from where `p` is: the same on every machine.
static func seed_of(p: Vector2) -> float:
	return float(absi(hash(Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0)))) % 10007) / 10007.0


## A unit piece (its middle at the bottom, x across, y up, z along) at `at` (block frame), its z along `f` (a unit
## direction on the ground), `size` (across, up, along) big.
static func piece(at: Vector3, f: Vector2, size: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3(f.y, 0.0, -f.x) * size.x, Vector3.UP * size.y, Vector3(f.x, 0.0, f.y) * size.z), at)


## A unit piece along a slope: from `a` to `b` (block frame, both at its bottom's middle), `w` across, `h` up, its
## sides kept upright (a sheared box, so pieces down a hill meet end to end).
static func slope(a: Vector3, b: Vector3, w: float, h: float) -> Transform3D:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var f := d.normalized() if d.length() > 1e-4 else Vector2(0, 1)
	return Transform3D(Basis(Vector3(f.y, 0.0, -f.x) * w, Vector3.UP * h, b - a), (a + b) * 0.5)


## A block's laying out: where it is, the roads, what it has made so far.
class _Block:
	var n: RoadNet
	var key: Vector2i
	var corner: Vector2
	var box: Rect2
	var items := {}
	var memo := {}
	var heights := {}
	var count := 0
	var skipped := 0
	var lively := false
	var _mouths := {}
	var _climates := {}
	var _gaps := {}   # Vector2i lattice point -> its gap
	var _near_cells := {}   # Vector2i RoadNet.GRID square -> _near_of's
	var _exact := 0
	var _cuts := {}   # Vector2i lattice point -> ground_at less the bare land there

	## Past where the net files a road near (m), as far as gap can tell.
	const FAR := 48.0
	## The lattice the roads' gaps are worked out on (m), and the coarser one what they do to the land (eased between);
	## nearer a road's verge than EXACT the land is worked out point by point.
	const LATTICE := 4.0
	const CUT := 16.0
	const EXACT := 6.0
	## At most this many of the roads' cuts worked out a block (each is costly, RoadNet.ground_at): past it the land
	## is taken as bare, the same on every machine (the pieces come in the same order).
	const CUTS_MOST := 600

	func _init(net: RoadNet, k: Vector2i) -> void:
		n = net
		key = k
		corner = Vector2(k) * SIZE
		box = Rect2(corner, Vector2.ONE * SIZE)

	func mine(p: Vector2) -> bool:
		return box.has_point(p)

	func full() -> bool:
		return count >= MOST

	func put(model: String, xf: Transform3D) -> void:
		if count >= MOST:
			skipped += 1
			return
		if not items.has(model):
			items[model] = []
		(items[model] as Array).append(xf)
		count += 1

	## `model` stood on the land at region-frame `p`, its z along `f`, scaled `s` (sunk `sink` m).
	func stand(model: String, p: Vector2, f: Vector2, s: float, sink := -0.05) -> void:
		var y := ground(p)
		if is_nan(y):
			return
		put(model, Fields.piece(local(p, y + sink), f.normalized() if f.length() > 1e-5 else Vector2(0, 1), Vector3.ONE * s))

	## A tile of `model`, `size` square round `p`, along `f`, laid on the land's slope there a little above it.
	func drape(model: String, p: Vector2, f: Vector2, size: float) -> void:
		var h := size * 0.5
		var across := Vector2(-f.y, f.x)
		var y := ground(p)
		var yu := ground(p + f * h) - ground(p - f * h)
		var yv := ground(p + across * h) - ground(p - across * h)
		if is_nan(y) or is_nan(yu) or is_nan(yv):
			return
		put(model, Transform3D(Basis(Vector3(across.x * size, yv, across.y * size), Vector3.UP, Vector3(f.x * size, yu, f.y * size)),
			local(p, y + 0.12)))

	## A flat slab of `model`, `size` square round `p` along `f`, its top at `top` and its bottom at `bottom` (m).
	func slab(model: String, p: Vector2, f: Vector2, size: float, top: float, bottom: float) -> void:
		put(model, Transform3D(Basis(Vector3(-f.y, 0.0, f.x) * size, Vector3.UP * maxf(0.2, top - bottom), Vector3(f.x, 0.0, f.y) * size),
			local(p, top)))

	## The highest and lowest of the land at the corners of a tile `size` square round `p` along `f`.
	func top(p: Vector2, f: Vector2, size: float) -> float:
		var out := -INF
		for c in _corners(p, f, size):
			out = maxf(out, ground(c))
		return out if out > -INF else NAN

	func low(p: Vector2, f: Vector2, size: float) -> float:
		var out := INF
		for c in _corners(p, f, size):
			out = minf(out, ground(c))
		return out if out < INF else NAN

	func _corners(p: Vector2, f: Vector2, size: float) -> Array[Vector2]:
		var h := size * 0.5
		var a := Vector2(-f.y, f.x) * h
		return [p + f * h + a, p + f * h - a, p - f * h + a, p - f * h - a]

	## The bare land at region-frame `p` (NAN beyond the land held).
	func bare(p: Vector2) -> float:
		return float(n.height.call(p.x, p.y))

	## The land as drawn at `p`, the roads' banks cut in (RoadNet.ground_at, only where a road's bank can reach): the
	## bare land there with what the roads do to it worked out on a CUT lattice and eased between (it changes slowly
	## past the verge; the costly part is the roads'), kept by the half metre (a tile's corners are its neighbours').
	func ground(p: Vector2) -> float:
		var k := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
		var have = heights.get(k)
		if have != null:
			return have
		var h := bare(p)
		if not is_nan(h):
			var gi := Vector2i(roundi(p.x / LATTICE), roundi(p.y / LATTICE))
			var g := _gap_at(gi)
			var d := p.distance_to(Vector2(gi) * LATTICE)
			if g - d >= FAR:
				pass
			elif g + d < EXACT and _exact < CUTS_MOST:
				# (near the verge the land changes too fast to ease between: worked out here)
				h = n.ground_at(p.x, p.y, h, memo)
				_exact += 1
			else:
				var f := p / CUT
				var i := Vector2i(floori(f.x), floori(f.y))
				var t := f - Vector2(i)
				var d00 := _cut(i)
				var d10 := _cut(i + Vector2i(1, 0))
				var d01 := _cut(i + Vector2i(0, 1))
				var d11 := _cut(i + Vector2i(1, 1))
				if d00 != 0.0 or d10 != 0.0 or d01 != 0.0 or d11 != 0.0:
					h += lerpf(lerpf(d00, d10, t.x), lerpf(d01, d11, t.x), t.y)
		heights[k] = h
		return h

	## What the roads do to the land at CUT lattice point `i` (m: ground_at less the bare land; 0 past every road's
	## bank).
	func _cut(i: Vector2i) -> float:
		var have = _cuts.get(i)
		if have != null:
			return have
		var p := Vector2(i) * CUT
		var d := 0.0
		if gap(p) < FAR and _cuts.size() < CUTS_MOST:
			var h := bare(p)
			if not is_nan(h):
				d = n.ground_at(p.x, p.y, h, memo) - h
		_cuts[i] = d
		return d

	## The gap (gap's) at lattice point `i`, worked out once.
	func _gap_at(i: Vector2i) -> float:
		var have = _gaps.get(i)
		if have != null:
			return have
		var g := gap(Vector2(i) * LATTICE)
		_gaps[i] = g
		return g

	## How far `p` is past the verge of the nearest road (m: negative on one; FAR where none is filed near it), from
	## the roads' own lines and the net's own filing of them (RoadNet._near_at). A junction counts as a disc round its
	## node, as wide as its widest road and the bell of its corners.
	func gap(p: Vector2) -> float:
		var c := Vector2i(floori(p.x / RoadNet.GRID), floori(p.y / RoadNet.GRID))
		var near = _near_cells.get(c)
		if near == null:
			near = _near_of(p)
			_near_cells[c] = near
		var segs: PackedVector2Array = near[0]
		var halves: PackedFloat32Array = near[1]
		var mouths: PackedVector3Array = near[2]
		var best := FAR
		for i in halves.size():
			var a := segs[i * 2]
			var ab := segs[i * 2 + 1] - a
			var l2 := ab.length_squared()
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-8 else 0.0
			var d := (a + ab * t).distance_to(p) - halves[i]
			if d < best:
				best = d
		for m in mouths:
			best = minf(best, Vector2(m.x, m.y).distance_to(p) - m.z)
		return best

	## The roads the net files in the GRID square round `p`: [their pieces' ends in pairs, each piece's half width and
	## verge, the junctions' mouths (x, z, reach)], gathered once a square.
	func _near_of(p: Vector2) -> Array:
		var near: Array = n._near_at(p.x, p.y)
		var cands: PackedInt32Array = near[0]
		var segs := PackedVector2Array()
		var halves := PackedFloat32Array()
		var mouths := PackedVector3Array()
		var seen := {}
		for c in cands.size():
			var e := cands[c]
			var line := n.line_of(e)
			var half := n.width_of(e) * 0.5 + RoadNet.VERGE
			var pieces: PackedInt32Array = near[1][c]
			for q in pieces.size():
				var k := pieces[q]
				segs.append(line[k - 1])
				segs.append(line[k])
				halves.append(half)
			for nd: int in [n.region.edge_a[e], n.region.edge_b[e]]:
				if n.region.adjacent[nd].size() >= 3 and not seen.has(nd):
					seen[nd] = true
					var at: Vector2 = n.region.node_pos[nd]
					mouths.append(Vector3(at.x, at.y, _mouth(nd)))
		return [segs, halves, mouths]

	## Whether `p` is clear of every road: `pad` past its verge. (A gap moves no faster than the point does, so the
	## nearest lattice point's answers most: only a point near the line is looked at itself.)
	func clear(p: Vector2, pad := CLEAR) -> bool:
		var i := Vector2i(roundi(p.x / LATTICE), roundi(p.y / LATTICE))
		var g := _gap_at(i)
		var d := p.distance_to(Vector2(i) * LATTICE)
		if g - d >= pad:
			return true
		if g + d < pad:
			return false
		return gap(p) >= pad

	func _mouth(nd: int) -> float:
		var have = _mouths.get(nd)
		if have != null:
			return have
		var widest := 0.0
		for e in n.region.adjacent[nd]:
			widest = maxf(widest, n.width_of(e))
		var r := widest * 0.5 + RoadNet.VERGE + RoadNet.FILLET + 6.0
		_mouths[nd] = r
		return r

	## The climate (Köppen) of the place at region-frame `p`, from its cell's profile.
	func koppen(p: Vector2) -> String:
		var r := n.region
		var m := RealTerrain.metres_per_degree(r.frame_lat)
		var cell := RealRegion.cell_of(r.frame_lat - p.y / m.x, r.frame_lon + p.x / m.y)
		var have = _climates.get(cell)
		if have == null:
			have = str(PlaceProfile.of_cell(cell).get("koppen", ""))
			_climates[cell] = have
		return have

	func local(p: Vector2, y: float) -> Vector3:
		return Vector3(p.x - corner.x, y, p.y - corner.y)


# ---------------------------------------------------------------------------- dressing a block (main thread)

## A block with lamps or flags gets a ticker that keeps the material's clock and the night's lamps.
static func dress(node: Node3D, data) -> void:
	if data == true:
		node.add_child(_Tick.new())


static func tick() -> void:
	var f := Engine.get_process_frames()
	if f == _ticked:
		return
	_ticked = f
	material().set_shader_parameter("night", Daylight.current.lamps if Daylight.current != null else 0.0)
	material().set_shader_parameter("clock", fmod(Time.get_unix_time_from_system(), 3600.0))


class _Tick extends Node:
	func _process(_delta: float) -> void:
		Fields.tick()


# ---------------------------------------------------------------------------- the models

## The mesh of `model` (built once).
static func mesh(model: String) -> Mesh:
	_meshes_lock.lock()
	var got = _meshes.get(model)
	_meshes_lock.unlock()
	if got != null:
		return got
	var b := _Build.new()
	var parts := model.split(":")
	match parts[0]:
		"wall": _wall(b, STONES.get(parts[1] if parts.size() > 1 else "", STONES["fieldstone"]))
		"hedge": _hedge(b, parts[1] if parts.size() > 1 else "green")
		"fence": _fence(b, parts[1] if parts.size() > 1 else "wood_wire")
		"vine": _vine(b)
		"bush_vine": _bush_vine(b)
		"tree": _tree(b, parts[1] if parts.size() > 1 else "apple")
		"shrub": b.blob(Vector3(0, 0.45, 0), Vector3(0.5, 0.45, 0.5), LEAF)
		"house": _house(b, parts[1] if parts.size() > 1 else "glass")
		"plot": _plot(b)
		"shed": _shed(b)
		"pan": _slab(b, {"pink": Color(0.88, 0.6, 0.62), "white": Color(0.95, 0.94, 0.9), "brine": Color(0.55, 0.62, 0.66)}.get(parts[1] if parts.size() > 1 else "", WHITE), Color(0.6, 0.55, 0.45), GLOSS if parts.size() > 1 and parts[1] == "brine" else MATTE)
		"salt_heap": b.cone(Vector3.ZERO, 3.0, 2.6, 10, WHITE)
		"paddy": _slab(b, Color(0.42, 0.5, 0.55) if parts.size() > 1 and parts[1] == "water" else Color(0.38, 0.58, 0.16), Color(0.33, 0.4, 0.2), GLOSS if parts.size() > 1 and parts[1] == "water" else MATTE)
		"pond": _slab(b, Color(0.28, 0.34, 0.26), Color(0.35, 0.36, 0.25), GLOSS)
		"cage": _cage(b)
		"raft": _raft(b)
		"oyster_table": _oyster_table(b)
		"bench": _bench(b)
		"spoil": _spoil(b)
		"drape": _tile(b, {"fairway": Color(0.3, 0.55, 0.18), "fairway2": Color(0.36, 0.62, 0.22), "green": Color(0.34, 0.66, 0.24),
			"sand": SAND, "tee": Color(0.4, 0.64, 0.25), "gravel": Color(0.6, 0.58, 0.53)}.get(parts[1] if parts.size() > 1 else "", GREEN))
		"heap": b.cone(Vector3.ZERO, 5.0, 3.5, 9, Color(0.62, 0.6, 0.55))
		"excavator": _excavator(b)
		"dumper": _dumper(b)
		"loader": _loader(b)
		"headframe": _headframe_mesh(b)
		"chimney": b.lathe(Vector3.ZERO, [[0.0, 2.2], [45.0, 1.3]], 10, Color(0.5, 0.28, 0.2))
		"flag": _flag(b, parts[1] if parts.size() > 1 else "red")
		"sign": _danger_sign(b)
		"stone": _grave(b, parts[1] if parts.size() > 1 else "slab")
		"golf_flag": _golf_flag(b)
		"track": _track_mesh(b)
		"tyres": _tyres(b)
		"grandstand": _grandstand(b)
		"coaster": _coaster(b)
		"big_wheel": _big_wheel(b)
		"coaster_rail": _coaster_rail(b)
		"coaster_leg": b.box(Vector3(0, 0.5, 0), Vector3(0.35, 1.0, 0.35), Basis(), WHITE)
		_: b.box(Vector3(0, 1.0, 0), Vector3(0.4, 2.0, 0.4), Basis(), RED)
	var m := b.commit(material())
	_meshes_lock.lock()
	_meshes[model] = m
	_meshes_lock.unlock()
	return m


## A dry-stone wall (or a rendered or concrete one), 1 across, 1 up and 1 along (stretched by its piece): a battered
## face of stones in shades of its colour, and its coping on top.
static func _wall(b: _Build, col: Color) -> void:
	for i in 4:
		var z0 := -0.5 + i * 0.25
		var shade := 0.85 + 0.3 * float((i * 7) % 5) / 5.0
		b.box(Vector3(0, 0.42, z0 + 0.125), Vector3(1.0, 0.84, 0.25), Basis(), col * shade)
	b.box(Vector3(0, 0.88, 0), Vector3(0.7, 0.1, 1.0), Basis(), col * 0.8)
	b.box(Vector3(0, 0.96, 0), Vector3(0.55, 0.08, 1.0), Basis(), col * 0.7)


static func _hedge(b: _Build, kind: String) -> void:
	var col: Color = {"green": Color(0.17, 0.3, 0.11), "dark": Color(0.13, 0.22, 0.1), "bright": Color(0.24, 0.42, 0.14),
		"bocage": Color(0.16, 0.27, 0.1)}.get(kind, Color(0.17, 0.3, 0.11))
	b.box(Vector3(0, 0.4, 0), Vector3(1.0, 0.8, 1.0), Basis(), col * 0.85)
	b.box(Vector3(0, 0.85, 0), Vector3(0.82, 0.3, 1.0), Basis(), col)
	b.box(Vector3(0.1, 0.92, -0.25), Vector3(0.6, 0.18, 0.45), Basis(), col * 1.12)


## A run of fence, its post at the start (z -0.5) and its rails or wires to the end (z 0.5), in metres across and up
## (z is stretched about three times: the posts are thin in it to stay posts).
static func _fence(b: _Build, style: String) -> void:
	match style:
		"barbed":
			b.box(Vector3(0, 0.6, -0.5), Vector3(0.06, 1.25, 0.02), Basis(), DARK)
			for y in [0.4, 0.75, 1.1]:
				b.box(Vector3(0, y, 0), Vector3(0.015, 0.015, 1.0), Basis(), STEEL)
		"rail":
			b.box(Vector3(0, 0.65, -0.5), Vector3(0.14, 1.3, 0.045), Basis(), WHITE)
			for y in [0.45, 0.8, 1.15]:
				b.box(Vector3(0, y, 0), Vector3(0.05, 0.14, 1.0), Basis(), WHITE * 0.95)
		"roundpole":
			# (the Nordic roundpole fence: slanted poles held between pairs of uprights)
			b.box(Vector3(-0.06, 0.7, -0.5), Vector3(0.07, 1.4, 0.025), Basis(), WOOD * 0.8)
			b.box(Vector3(0.06, 0.7, -0.5), Vector3(0.07, 1.4, 0.025), Basis(), WOOD * 0.8)
			for i in 3:
				b.box(Vector3(0, 0.7, -0.3 + i * 0.33), Vector3(0.06, 1.5, 0.06), Basis(Vector3.RIGHT, 0.75), Color(0.48, 0.4, 0.3))
		"security":
			b.box(Vector3(0, 1.25, -0.5), Vector3(0.07, 2.5, 0.025), Basis(), STEEL)
			b.box(Vector3(0, 1.15, 0), Vector3(0.02, 2.2, 1.0), Basis(), Color(0.52, 0.55, 0.56, 1.0) * 0.8)
			b.box(Vector3(0, 2.45, 0), Vector3(0.25, 0.12, 1.0), Basis(), DARK)
		"catch":
			b.box(Vector3(0, 2.0, -0.5), Vector3(0.1, 4.0, 0.035), Basis(), STEEL)
			b.box(Vector3(0, 2.0, 0), Vector3(0.02, 3.6, 1.0), Basis(), Color(0.4, 0.42, 0.43))
			b.box(Vector3(0, 0.45, 0), Vector3(0.35, 0.9, 1.0), Basis(), Color(0.85, 0.85, 0.83))
		"wire":
			b.box(Vector3(0, 0.6, -0.5), Vector3(0.05, 1.2, 0.018), Basis(), STEEL)
			b.box(Vector3(0, 0.6, 0), Vector3(0.01, 1.05, 1.0), Basis(), Color(0.5, 0.52, 0.52))
		_:
			b.box(Vector3(0, 0.6, -0.5), Vector3(0.1, 1.25, 0.035), Basis(), WOOD)
			for y in [0.45, 0.8, 1.1]:
				b.box(Vector3(0, y, 0), Vector3(0.012, 0.012, 1.0), Basis(), STEEL)


## A row of trellised vines along a piece (z -0.5 to 0.5): a post at its start, two wires and the canopy.
## (z is stretched about nine times: the posts are thin in it to stay posts)
static func _vine(b: _Build) -> void:
	b.box(Vector3(0, 0.85, -0.5), Vector3(0.08, 1.7, 0.009), Basis(), WOOD)
	b.box(Vector3(0, 0.75, 0.0), Vector3(0.06, 1.5, 0.007), Basis(), WOOD * 0.9)
	b.box(Vector3(0, 0.3, 0), Vector3(0.05, 0.6, 0.98), Basis(), Color(0.3, 0.22, 0.14))
	b.box(Vector3(0, 0.95, 0), Vector3(0.45, 0.7, 0.98), Basis(), Color(0.27, 0.4, 0.13))
	for i in 4:
		var z := -0.375 + i * 0.25
		var shade := 0.9 + 0.08 * float((i * 5) % 3)
		b.box(Vector3(0.03 * (i % 2), 1.38, z), Vector3(0.36, 0.3, 0.2), Basis(), Color(0.33, 0.5, 0.17) * shade)


static func _bush_vine(b: _Build) -> void:
	b.box(Vector3(0, 0.25, 0), Vector3(0.12, 0.5, 0.12), Basis(), Color(0.3, 0.22, 0.14))
	b.blob(Vector3(0, 0.7, 0), Vector3(0.6, 0.38, 0.6), Color(0.32, 0.46, 0.16))


static func _tree(b: _Build, kind: String) -> void:
	match kind:
		"olive":
			b.lathe(Vector3.ZERO, [[0.0, 0.22], [1.3, 0.16]], 6, Color(0.36, 0.32, 0.26))
			b.blob(Vector3(0, 2.3, 0), Vector3(2.2, 1.2, 2.0), Color(0.4, 0.46, 0.32))
			b.blob(Vector3(0.6, 2.9, 0.3), Vector3(1.3, 0.8, 1.2), Color(0.45, 0.5, 0.36))
		"citrus":
			b.lathe(Vector3.ZERO, [[0.0, 0.12], [0.8, 0.1]], 6, WOOD)
			b.blob(Vector3(0, 1.8, 0), Vector3(1.6, 1.4, 1.6), Color(0.13, 0.3, 0.1))
			for i in 7:
				var a := TAU * i / 7.0
				b.box(Vector3(cos(a) * 1.45, 1.6 + 0.3 * sin(a * 3.0), sin(a) * 1.45), Vector3.ONE * 0.16, Basis(), Color(0.95, 0.55, 0.08))
		"date", "coconut":
			var tall := 9.0 if kind == "date" else 11.0
			var lean := 0.0 if kind == "date" else 0.6
			b.lathe(Vector3.ZERO, [[0.0, 0.3], [tall, 0.22]], 6, Color(0.42, 0.34, 0.24))
			var top := Vector3(lean, tall, 0)
			for i in 9:
				var a := TAU * i / 9.0
				var out := Vector3(cos(a), 0, sin(a))
				var tip := top + out * 3.6 + Vector3.DOWN * 1.6
				var side := out.cross(Vector3.UP).normalized() * 0.5
				b.quad(top - side * 0.2, top + side * 0.2, tip + side, tip - side, Color(0.3, 0.42, 0.16) if kind == "date" else Color(0.25, 0.45, 0.12))
			if kind == "coconut":
				b.box(top + Vector3(0, -0.4, 0), Vector3(0.6, 0.4, 0.6), Basis(), Color(0.35, 0.3, 0.12))
		"cypress":
			b.cone(Vector3(0, 0.6, 0), 0.9, 9.0, 7, Color(0.1, 0.2, 0.1))
			b.lathe(Vector3.ZERO, [[0.0, 0.15], [0.8, 0.15]], 5, WOOD)
		"yew":
			b.lathe(Vector3.ZERO, [[0.0, 0.35], [1.6, 0.3]], 6, Color(0.35, 0.22, 0.16))
			b.blob(Vector3(0, 3.2, 0), Vector3(3.0, 2.6, 3.0), Color(0.09, 0.18, 0.08))
		_:
			b.lathe(Vector3.ZERO, [[0.0, 0.14], [1.2, 0.11]], 6, WOOD)
			b.blob(Vector3(0, 2.3, 0), Vector3(1.8, 1.3, 1.8), Color(0.2, 0.38, 0.12))
			for i in 5:
				var a := TAU * i / 5.0 + 0.4
				b.box(Vector3(cos(a) * 1.6, 2.0 + 0.4 * sin(a * 2.0), sin(a) * 1.6), Vector3.ONE * 0.14, Basis(), Color(0.75, 0.12, 0.1))


## A glasshouse (Venlo roofs of glass that catch the sky; lit glows orange at night), a flat plastic house of the
## Spanish south, or a polytunnel: its middle at the bottom, its length along z, a skirt below the ground.
static func _house(b: _Build, kind: String) -> void:
	var dims: Array = HOUSES.get(kind, HOUSES["glass"])
	var l := float(dims[0])
	var w := float(dims[1])
	match kind:
		"plastic":
			var col := Color(0.86, 0.86, 0.83)
			b.box(Vector3(0, 1.0, 0), Vector3(w, 4.0, l), Basis(), col * 0.92, GLOSS)
			var bays := 6
			for i in bays:
				var x0 := -w * 0.5 + w * i / bays
				var x1 := x0 + w / bays
				var xm := (x0 + x1) * 0.5
				b.quad(Vector3(x0, 3.0, -l * 0.5), Vector3(xm, 3.5, -l * 0.5), Vector3(xm, 3.5, l * 0.5), Vector3(x0, 3.0, l * 0.5), col, GLOSS)
				b.quad(Vector3(xm, 3.5, -l * 0.5), Vector3(x1, 3.0, -l * 0.5), Vector3(x1, 3.0, l * 0.5), Vector3(xm, 3.5, l * 0.5), col * 0.97, GLOSS)
		"tunnel":
			var col := Color(0.9, 0.91, 0.9)
			var sides := 8
			for i in sides:
				var a0 := PI * i / sides
				var a1 := PI * (i + 1) / sides
				var p0 := Vector3(cos(a0) * w * 0.5, sin(a0) * 3.4, 0)
				var p1 := Vector3(cos(a1) * w * 0.5, sin(a1) * 3.4, 0)
				b.quad(p0 + Vector3(0, 0, -l * 0.5), p1 + Vector3(0, 0, -l * 0.5), p1 + Vector3(0, 0, l * 0.5), p0 + Vector3(0, 0, l * 0.5), col * (0.9 + 0.1 * sin(a0)), GLOSS)
				b.tri(Vector3(0, 0, -l * 0.5), p1 + Vector3(0, 0, -l * 0.5), p0 + Vector3(0, 0, -l * 0.5), col * 0.85, GLOSS)
				b.tri(Vector3(0, 0, l * 0.5), p0 + Vector3(0, 0, l * 0.5), p1 + Vector3(0, 0, l * 0.5), col * 0.85, GLOSS)
			b.box(Vector3(0, -0.6, 0), Vector3(w, 1.2, l), Basis(), MUD)
		_:
			var glass := Color(0.62, 0.72, 0.76)
			var flag := GLOW if kind == "glass_lit" else GLOSS
			b.box(Vector3(0, 1.3, 0), Vector3(w, 5.0, l), Basis(), glass * 0.85, flag)
			var ridges := 3
			for i in ridges:
				var x0 := -w * 0.5 + w * i / ridges
				var x1 := x0 + w / ridges
				var xm := (x0 + x1) * 0.5
				b.quad(Vector3(x0, 3.8, -l * 0.5), Vector3(xm, 4.6, -l * 0.5), Vector3(xm, 4.6, l * 0.5), Vector3(x0, 3.8, l * 0.5), glass, flag)
				b.quad(Vector3(xm, 4.6, -l * 0.5), Vector3(x1, 3.8, -l * 0.5), Vector3(x1, 3.8, l * 0.5), Vector3(xm, 4.6, l * 0.5), glass * 1.08, flag)
				b.tri(Vector3(x0, 3.8, -l * 0.5), Vector3(x1, 3.8, -l * 0.5), Vector3(xm, 4.6, -l * 0.5), glass * 0.9, flag)
				b.tri(Vector3(x1, 3.8, l * 0.5), Vector3(x0, 3.8, l * 0.5), Vector3(xm, 4.6, l * 0.5), glass * 0.9, flag)
			for z in range(-int(l * 0.5), int(l * 0.5) + 1, 4):
				b.box(Vector3(0, 4.0, z), Vector3(w + 0.05, 0.12, 0.08), Basis(), WHITE * 0.85)


## An allotment plot (6 by 10 m round its middle, on the land): dug earth, rows of greens and a few canes.
static func _plot(b: _Build) -> void:
	b.box(Vector3(0, -0.05, 0), Vector3(0.95, 0.12, 0.95), Basis(), Color(0.33, 0.25, 0.17))
	for i in 4:
		b.box(Vector3(-0.35 + i * 0.22, 0.05, 0), Vector3(0.08, 0.05, 0.85), Basis(), Color(0.25, 0.45, 0.15))


static func _shed(b: _Build) -> void:
	b.box(Vector3(0, 1.0, 0), Vector3(2.0, 2.0, 2.6), Basis(), Color(0.32, 0.36, 0.26))
	b.box(Vector3(0, 2.1, 0), Vector3(2.3, 0.12, 2.9), Basis(Vector3.FORWARD, 0.1), DARK)


## A slab 1 square round its middle and 1 deep (stretched by its tile): `top` its surface, `side` its banks.
static func _slab(b: _Build, top: Color, side: Color, flag: float) -> void:
	b.quad(Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), top, flag)
	b.box(Vector3(0, -0.5, 0), Vector3(1.0, 1.0, 1.0), Basis(), side)
	b.box(Vector3(0, 0.015, 0.49), Vector3(1.0, 0.03, 0.02), Basis(), side * 1.1)
	b.box(Vector3(0.49, 0.015, 0), Vector3(0.02, 0.03, 1.0), Basis(), side * 1.1)


## A tile laid on the land (stretched and tilted by its transform), with a little skirt under its edges.
static func _tile(b: _Build, col: Color) -> void:
	b.quad(Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), col)
	b.box(Vector3(0, -0.2, 0), Vector3(1.0, 0.4, 1.0), Basis(), col * 0.8)


static func _cage(b: _Build) -> void:
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		b.beam(Vector3(cos(a0) * 12.0, 0.25, sin(a0) * 12.0), Vector3(cos(a1) * 12.0, 0.25, sin(a1) * 12.0), 0.35, Color(0.12, 0.13, 0.14))
		if i % 2 == 0:
			b.box(Vector3(cos(a0) * 12.0, 0.9, sin(a0) * 12.0), Vector3(0.08, 1.2, 0.08), Basis(), DARK)
	b.lathe(Vector3(0, 1.4, 0), [[0.0, 11.8], [0.05, 11.8]], 16, Color(0.2, 0.22, 0.2), false)


static func _raft(b: _Build) -> void:
	for i in 4:
		b.box(Vector3(-4.5 + i * 3.0, 0.3, 0), Vector3(0.25, 0.25, 10.0), Basis(), WOOD)
		b.box(Vector3(0, 0.45, -4.5 + i * 3.0), Vector3(10.0, 0.2, 0.25), Basis(), WOOD * 0.9)
	for x in [-4.0, 4.0]:
		for z in [-4.0, 0.0, 4.0]:
			b.box(Vector3(x, 0.12, z), Vector3(0.8, 0.4, 0.8), Basis(), Color(0.85, 0.82, 0.3))


static func _oyster_table(b: _Build) -> void:
	for z in [-2.8, 0.0, 2.8]:
		b.box(Vector3(-0.45, 0.25, z), Vector3(0.05, 0.5, 0.05), Basis(), STEEL)
		b.box(Vector3(0.45, 0.25, z), Vector3(0.05, 0.5, 0.05), Basis(), STEEL)
	b.box(Vector3(0, 0.55, 0), Vector3(1.0, 0.12, 6.0), Basis(), Color(0.15, 0.17, 0.16))


## A bench of a quarry's face (1 along, `h` up, its front face to +x: stretched by its piece): grey rock, its top lighter.
static func _bench(b: _Build) -> void:
	b.box(Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0), Basis(), Color(0.55, 0.53, 0.5))
	b.box(Vector3(0, 0.98, 0), Vector3(1.0, 0.04, 1.0), Basis(), Color(0.68, 0.66, 0.6))
	b.box(Vector3(0.48, 0.5, 0.2), Vector3(0.06, 0.8, 0.35), Basis(), Color(0.46, 0.45, 0.42))


static func _spoil(b: _Build) -> void:
	b.quad(Vector3(-0.5, 0, -0.5), Vector3(0, 1, -0.5), Vector3(0, 1, 0.5), Vector3(-0.5, 0, 0.5), Color(0.5, 0.46, 0.38))
	b.quad(Vector3(0, 1, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(0, 1, 0.5), Color(0.44, 0.4, 0.33))


static func _wheels(b: _Build, at: Array, r: float) -> void:
	for p: Vector3 in at:
		b.box(p, Vector3(0.5, r * 2.0, r * 2.0), Basis(), DARK)


static func _dumper(b: _Build) -> void:
	_wheels(b, [Vector3(-1.4, 0.9, -2.0), Vector3(1.4, 0.9, -2.0), Vector3(-1.4, 0.9, 2.2), Vector3(1.4, 0.9, 2.2)], 0.9)
	b.box(Vector3(0, 1.6, 0), Vector3(2.4, 0.6, 6.0), Basis(), YELLOW * 0.8)
	b.box(Vector3(0, 2.7, 0.9), Vector3(3.0, 1.6, 4.2), Basis(Vector3.RIGHT, -0.08), YELLOW)
	b.box(Vector3(0, 2.6, -2.3), Vector3(2.2, 1.6, 1.4), Basis(), YELLOW)
	b.box(Vector3(0, 2.8, -3.0), Vector3(1.9, 0.8, 0.05), Basis(), Color(0.2, 0.25, 0.3), GLOSS)


static func _excavator(b: _Build) -> void:
	b.box(Vector3(-1.3, 0.5, 0), Vector3(0.7, 1.0, 4.6), Basis(), DARK)
	b.box(Vector3(1.3, 0.5, 0), Vector3(0.7, 1.0, 4.6), Basis(), DARK)
	b.box(Vector3(0, 1.7, 0.4), Vector3(2.8, 1.3, 3.6), Basis(), YELLOW)
	b.box(Vector3(-0.8, 2.9, -0.6), Vector3(1.1, 1.2, 1.4), Basis(), YELLOW)
	b.beam(Vector3(0.3, 2.3, -1.2), Vector3(0.3, 5.2, -4.0), 0.5, YELLOW * 0.9)
	b.beam(Vector3(0.3, 5.2, -4.0), Vector3(0.3, 1.2, -6.2), 0.4, YELLOW * 0.9)
	b.box(Vector3(0.3, 0.9, -6.4), Vector3(1.2, 0.9, 0.9), Basis(), DARK)


static func _loader(b: _Build) -> void:
	_wheels(b, [Vector3(-1.2, 0.75, -1.4), Vector3(1.2, 0.75, -1.4), Vector3(-1.2, 0.75, 1.6), Vector3(1.2, 0.75, 1.6)], 0.75)
	b.box(Vector3(0, 1.6, 0.4), Vector3(2.0, 1.2, 4.0), Basis(), YELLOW)
	b.box(Vector3(0, 2.9, 0.2), Vector3(1.5, 1.4, 1.5), Basis(), YELLOW)
	b.box(Vector3(0, 1.0, -2.8), Vector3(2.6, 1.0, 0.9), Basis(), DARK * 2.0)


## Pithead gear: a steel headframe with its winding wheels on top, its back legs raked, a winding house behind.
static func _headframe_mesh(b: _Build) -> void:
	var top := 24.0
	for x in [-2.5, 2.5]:
		b.beam(Vector3(x, 0, -2.5), Vector3(x * 0.5, top, 0), 0.6, STEEL)
		b.beam(Vector3(x, 0, 2.5), Vector3(x * 0.5, top, 0), 0.6, STEEL)
		b.beam(Vector3(x, 0, 12.0), Vector3(x * 0.5, top - 1.0, 0.5), 0.7, STEEL)
	for y in [6.0, 12.0, 18.0]:
		b.box(Vector3(0, y, 0), Vector3(4.0, 0.3, 0.3), Basis(), STEEL)
	b.box(Vector3(0, top, 0), Vector3(4.0, 0.6, 3.0), Basis(), STEEL * 0.8)
	for x in [-1.0, 1.0]:
		b.lathe(Vector3(x, top + 2.6, 0), [[-0.15, 2.6], [0.15, 2.6]], 14, DARK * 1.5, true)
	b.box(Vector3(0, 4.0, 18.0), Vector3(10.0, 8.0, 8.0), Basis(), Color(0.52, 0.27, 0.2))
	b.box(Vector3(0, 8.3, 18.0), Vector3(10.5, 0.6, 8.5), Basis(), DARK)


## A red flag on its pole (a range's is taller), waving.
static func _flag(b: _Build, kind: String) -> void:
	var h := 9.0 if kind == "range" else 5.5
	b.box(Vector3(0, h * 0.5, 0), Vector3(0.1, h, 0.1), Basis(), WHITE)
	var w := 2.2 if kind == "range" else 1.4
	var t := h - 0.1
	var hh := 1.4 if kind == "range" else 0.9
	# (UV.x the way along the flag from its pole, for the shader's wave)
	b.quad_uv(Vector3(0, t, 0), Vector3(0, t - hh, 0), Vector3(0, t - hh, w), Vector3(0, t, w), RED, WAVE)


static func _danger_sign(b: _Build) -> void:
	b.box(Vector3(0, 0.9, 0), Vector3(0.08, 1.8, 0.08), Basis(), STEEL)
	b.box(Vector3(0, 1.75, 0.06), Vector3(1.2, 0.8, 0.04), Basis(), WHITE)
	b.box(Vector3(0, 1.95, 0.085), Vector3(1.1, 0.25, 0.02), Basis(), RED)
	b.box(Vector3(0, 1.6, 0.085), Vector3(0.9, 0.08, 0.02), Basis(), DARK)
	b.box(Vector3(0, 1.48, 0.085), Vector3(0.7, 0.06, 0.02), Basis(), DARK)


## A headstone, cross, grave pillar or tomb (facing +z), in its region's style.
static func _grave(b: _Build, style: String) -> void:
	var stone := Color(0.6, 0.6, 0.58)
	match style:
		"cross":
			b.box(Vector3(0, 0.1, -0.9), Vector3(0.8, 0.2, 1.8), Basis(), stone * 0.85)
			b.box(Vector3(0, 0.6, 0), Vector3(0.1, 1.0, 0.1), Basis(), WHITE * 0.9)
			b.box(Vector3(0, 0.85, 0), Vector3(0.5, 0.09, 0.1), Basis(), WHITE * 0.9)
		"haka":
			b.box(Vector3(0, 0.15, 0), Vector3(0.9, 0.3, 0.9), Basis(), Color(0.5, 0.5, 0.5))
			b.box(Vector3(0, 0.38, 0), Vector3(0.6, 0.16, 0.6), Basis(), Color(0.4, 0.4, 0.42))
			b.box(Vector3(0, 0.95, 0), Vector3(0.32, 1.0, 0.32), Basis(), Color(0.28, 0.28, 0.3))
			b.box(Vector3(0, 1.48, 0), Vector3(0.36, 0.06, 0.36), Basis(), Color(0.28, 0.28, 0.3))
			b.box(Vector3(0.55, 0.6, 0.4), Vector3(0.05, 1.2, 0.08), Basis(), Color(0.7, 0.62, 0.45))
		"muslim":
			b.box(Vector3(0, 0.12, -0.9), Vector3(0.6, 0.24, 1.9), Basis(), WHITE * 0.92)
			b.box(Vector3(0, 0.55, 0), Vector3(0.28, 0.75, 0.07), Basis(), WHITE)
			b.box(Vector3(0, 0.45, -1.8), Vector3(0.2, 0.5, 0.07), Basis(), WHITE)
		"tomb":
			b.box(Vector3(0, 0.6, -1.0), Vector3(1.1, 1.2, 2.2), Basis(), WHITE * 0.95)
			b.box(Vector3(0, 1.25, -1.0), Vector3(1.25, 0.1, 2.35), Basis(), Color(0.8, 0.78, 0.74))
			b.box(Vector3(0, 1.75, -0.2), Vector3(0.08, 0.9, 0.08), Basis(), Color(0.75, 0.72, 0.68))
			b.box(Vector3(0, 1.95, -0.2), Vector3(0.45, 0.08, 0.08), Basis(), Color(0.75, 0.72, 0.68))
		"flat":
			b.box(Vector3(0, 0.03, 0), Vector3(0.6, 0.08, 0.35), Basis(), Color(0.4, 0.32, 0.2))
			b.box(Vector3(0, 0.07, 0.1), Vector3(0.1, 0.12, 0.05), Basis(), Color(0.55, 0.45, 0.25))
		_:
			b.box(Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.09), Basis(), stone)
			b.lathe(Vector3(0, 0.9, 0), [[0.0, 0.3], [0.1, 0.25], [0.16, 0.1]], 8, stone)
			b.box(Vector3(0, 0.03, -0.9), Vector3(0.7, 0.06, 1.7), Basis(), Color(0.3, 0.42, 0.18))


static func _golf_flag(b: _Build) -> void:
	b.box(Vector3(0, 1.1, 0), Vector3(0.03, 2.2, 0.03), Basis(), WHITE)
	b.quad_uv(Vector3(0, 2.15, 0), Vector3(0, 1.8, 0), Vector3(0, 1.8, 0.55), Vector3(0, 2.15, 0.55), Color(0.95, 0.85, 0.1), WAVE)


## A race track's tarmac (1 across, its pieces stretched to its width), red and white kerbs at its edges.
static func _track_mesh(b: _Build) -> void:
	b.box(Vector3(0, -0.15, 0), Vector3(0.94, 0.3, 1.0), Basis(), Color(0.2, 0.2, 0.21))
	for x in [-0.485, 0.485]:
		b.box(Vector3(x, -0.13, -0.25), Vector3(0.03, 0.3, 0.5), Basis(), RED)
		b.box(Vector3(x, -0.13, 0.25), Vector3(0.03, 0.3, 0.5), Basis(), WHITE)
	b.box(Vector3(0, 0.005, 0), Vector3(0.01, 0.01, 0.4), Basis(), WHITE * 0.9)


static func _tyres(b: _Build) -> void:
	for i in 4:
		b.box(Vector3(0, 0.25 + (i % 2) * 0.45, -0.375 + i * 0.25), Vector3(0.7, 0.45, 0.24), Basis(), DARK * 1.2)
	b.box(Vector3(0, 0.45, 0), Vector3(0.05, 0.9, 1.0), Basis(), Color(0.2, 0.3, 0.6))


static func _grandstand(b: _Build) -> void:
	for i in 8:
		b.box(Vector3(0, 0.5 + i * 0.7, -i * 0.9), Vector3(60.0, 1.0 + i * 1.4, 0.9), Basis(), Color(0.75, 0.75, 0.73) * (0.9 + 0.02 * i))
		b.box(Vector3(0, 1.05 + i * 1.4, -i * 0.9 + 0.2), Vector3(59.0, 0.25, 0.4), Basis(), Color(0.15, 0.3, 0.6))
	for x in [-29.0, -10.0, 10.0, 29.0]:
		b.box(Vector3(x, 7.5, -8.5), Vector3(0.4, 15.0, 0.4), Basis(), STEEL)
	b.box(Vector3(0, 15.0, -3.5), Vector3(62.0, 0.4, 12.0), Basis(Vector3.RIGHT, 0.12), STEEL * 0.8)


## A roller coaster round its middle: a lift hill, a drop, a loop and turns, on white legs, the track red.
static func _coaster(b: _Build) -> void:
	var pts := []
	var n := 72
	for i in n:
		var t := TAU * i / n
		var x := cos(t) * 55.0
		var z := sin(t) * 24.0 + sin(t * 3.0) * 6.0
		var y := 6.0 + 26.0 * pow(maxf(0.0, sin(t)), 3.0) + 7.0 * (0.5 + 0.5 * cos(t * 4.0))
		pts.append(Vector3(x, y, z))
	for i in n:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[(i + 1) % n]
		b.beam(a, c, 0.9, RED)
		if i % 3 == 0:
			b.beam(Vector3(a.x, 0, a.z), a, 0.35, WHITE)
	# The loop.
	var at := Vector3(-30.0, 0, -18.0)
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		b.beam(at + Vector3(sin(a0) * 9.0, 10.0 - cos(a0) * 9.0, i * 0.15), at + Vector3(sin(a1) * 9.0, 10.0 - cos(a1) * 9.0, (i + 1) * 0.15), 0.8, RED)
	b.beam(at + Vector3(0, 0, 1.5), at + Vector3(0, 1.0, 1.5), 1.2, WHITE)


static func _big_wheel(b: _Build) -> void:
	var c := Vector3(0, 24.0, 0)
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		var p0 := c + Vector3(cos(a0) * 20.0, sin(a0) * 20.0, 0)
		var p1 := c + Vector3(cos(a1) * 20.0, sin(a1) * 20.0, 0)
		b.beam(p0, p1, 0.4, WHITE)
		if i % 2 == 0:
			b.beam(c, p0, 0.15, WHITE * 0.9)
			b.box(p0 + Vector3(0, -1.4, 0), Vector3(1.6, 1.8, 1.6), Basis(), [RED, YELLOW, Color(0.1, 0.4, 0.8)][i % 3])
	for x in [-6.0, 6.0]:
		b.beam(Vector3(x, 0, -3.0), c, 0.6, STEEL)
		b.beam(Vector3(x, 0, 3.0), c, 0.6, STEEL)


static func _coaster_rail(b: _Build) -> void:
	b.box(Vector3(-0.45, 0.1, 0), Vector3(0.12, 0.12, 1.0), Basis(), RED)
	b.box(Vector3(0.45, 0.1, 0), Vector3(0.12, 0.12, 1.0), Basis(), RED)
	b.box(Vector3(0, -0.15, 0), Vector3(0.3, 0.3, 1.0), Basis(), RED * 0.8)


## Builds a mesh of boxes, blobs, cones and lathes: vertex coloured, its flags in UV2 (see MATTE).
class _Build:
	var st := SurfaceTool.new()
	var any := false

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, flag := MATTE, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		var ps := [a, b, c]
		for i in 3:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(uv[i])
			st.set_uv2(Vector2(flag, 0.0))
			st.add_vertex(ps[i])
		any = true

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flag := MATTE) -> void:
		tri(a, b, c, col, flag)
		tri(a, c, d, col, flag)

	## A quad whose UV.x runs 0 at its a-b edge to 1 at its c-d edge (a flag's way from its pole).
	func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flag: float) -> void:
		tri(a, b, c, col, flag, [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
		tri(a, c, d, col, flag, [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)])

	## A box centred `c`, `size`, turned by `basis`.
	func box(c: Vector3, size: Vector3, basis: Basis, col: Color, flag := MATTE) -> void:
		var h := size * 0.5
		var p := []
		for i in 8:
			p.append(c + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, flag)

	## A square beam from `a` to `b`, `w` thick.
	func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
		var d := b - a
		if d.length() < 1e-4:
			return
		var y := d.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		box((a + b) * 0.5, Vector3(w, d.length(), w), Basis(x, y, z), col)

	## A lathe round the y axis through `at`: rings [[y, r], ...] (from the bottom), `sides` round, capped on top.
	func lathe(at: Vector3, rings: Array, sides: int, col: Color, cap := true) -> void:
		for i in range(rings.size() - 1):
			var y0 := float(rings[i][0])
			var r0 := float(rings[i][1])
			var y1 := float(rings[i + 1][0])
			var r1 := float(rings[i + 1][1])
			for s in sides:
				var a0 := TAU * s / sides
				var a1 := TAU * (s + 1) / sides
				quad(at + Vector3(cos(a0) * r0, y0, sin(a0) * r0), at + Vector3(cos(a0) * r1, y1, sin(a0) * r1),
					at + Vector3(cos(a1) * r1, y1, sin(a1) * r1), at + Vector3(cos(a1) * r0, y0, sin(a1) * r0), col)
		if cap:
			var top: Array = rings[rings.size() - 1]
			var yt := float(top[0])
			var rt := float(top[1])
			if rt > 0.0:
				for s in sides:
					var a0 := TAU * s / sides
					var a1 := TAU * (s + 1) / sides
					tri(at + Vector3(0, yt, 0), at + Vector3(cos(a1) * rt, yt, sin(a1) * rt), at + Vector3(cos(a0) * rt, yt, sin(a0) * rt), col)

	## A cone `r` round at the bottom, `h` high, standing at `at`.
	func cone(at: Vector3, r: float, h: float, sides: int, col: Color) -> void:
		lathe(at, [[0.0, r], [h * 0.6, r * 0.45], [h, 0.0]], sides, col, false)

	## A rounded lump (a crown of leaves, a bush): a low-poly ball `r` (x, y, z radii) round `c`, a little lumpy.
	func blob(c: Vector3, r: Vector3, col: Color) -> void:
		var rows := 4
		var sides := 7
		var ring := func(i: int, s: int) -> Vector3:
			var v := PI * i / rows
			var u := TAU * s / sides + (0.3 if i % 2 == 1 else 0.0)
			var lump := 1.0 + 0.12 * sin(float(s) * 2.3 + float(i) * 1.7)
			return c + Vector3(sin(v) * cos(u) * r.x, -cos(v) * r.y, sin(v) * sin(u) * r.z) * lump
		for i in rows:
			for s in sides:
				var shade := 0.85 + 0.3 * float(i) / rows
				quad(ring.call(i, s), ring.call(i + 1, s), ring.call(i + 1, s + 1), ring.call(i, s + 1), col * shade)

	func commit(mat: Material) -> Mesh:
		var m := st.commit() if any else ArrayMesh.new()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


# ---------------------------------------------------------------------------- the shader

static func material() -> ShaderMaterial:
	if _material == null:
		var s := Shader.new()
		s.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = s
	return _material


const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)
uniform float clock = 0.0;   // seconds, for the flags' wave
varying float flag;

void vertex() {
	flag = UV2.x;
	if (flag > 2.5) {
		// A flag: waved out from its pole (UV.x 0 there, 1 at its fly end).
		float w = UV.x;
		VERTEX.x += sin(clock * 5.0 + VERTEX.z * 2.5 + VERTEX.y) * 0.18 * w;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (flag > 0.5 && flag < 2.5) {
		// Glass and water: smooth, the sky in it.
		ROUGHNESS = 0.06;
		SPECULAR = 0.9;
		METALLIC = 0.15;
		if (flag > 1.5) {
			EMISSION = vec3(1.0, 0.55, 0.25) * 1.6 * night;
		}
	} else {
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
	}
}
"""
