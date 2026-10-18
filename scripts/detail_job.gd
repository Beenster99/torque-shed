class_name DetailJob
extends RefCounted
## Polishing and ceramic coating a bike's paint by hand: the mini games behind the polisher
## (F with it on a washed bike in the wash bay; see DetailMode), like pressure washing it
## (WashJob). The painted panels (Detail.PANELS) are covered in points, one for each bit of paint
## the pad can get flat on (not what's tucked under the frame or behind another part), each in
## one of its panel's regions (Detail's layout, the same as the road dirt's).
##
## Polishing ("polish"): hold the pad on the paint and sweep it about. Under the pad the swirls
## come out and the gloss comes up (quicker the harder you press, the second button), but the
## paint heats up too: keep it moving and it cools between passes; hold it in one spot (or lean
## on it) and the heat builds until it burns through the clear coat, a dull chalky patch for
## good (Detail's "b"), only a respray puts right. Polishing also cuts off any coat and smears.
##
## Coating ("coat"): wipe the ceramic coat on with the applicator in overlapping passes one way
## and then across (a cross-hatch: one way only lays a thin coat), then buff the residue off with
## the microfibre (the second button) before it flashes: each bit of it left on longer than FLASH
## seconds goes hard as a smear, a high spot that has to be polished off and coated again.
##
## What's done shows on the bike there and then (its FinishLayer), and goes to the shed every few
## moments as each region's finish (`take_updates`), so the crew see it too.

const CELL := 0.03           # the paint is sampled this far apart
const OCC := 0.035           # cubes for working out what the pad can get to
const OCC_CELL := 0.045      # the rest of the bike is sampled this far apart for them
const WAY_OUT := 0.25        # clear of the bike this far out from a point and the pad can get to it
const PREP_POINTS := 300     # points a frame worked through getting ready
const REACH := 1.3           # the pad's on the paint if it's no further than this from your eye
const PAD := 0.075           # the polisher's pad (a 150 mm foam pad)
const APPLICATOR := 0.06     # the coating applicator
const TOWEL := 0.09          # the folded microfibre
const FALLOFF := 0.45        # weaker to the edge of the pad
const SKIM := 0.35           # how flat on the pad has to be: none this side on (cosines),
const FLAT := 0.75           # all of it by this
const CUT := 1.2             # share of what's left of the swirls taken out a second under the pad
const HEAVY := 1.8           # pressing hard: this much quicker
const HEAT := 0.55           # heat a second under the middle of the pad,
const HEAVY_HEAT := 2.2      # this much more pressing hard,
const COOL := 0.3            # and lost a second off it
const BURN := 1.0            # this hot and the clear coat's burnt through
const STRIP := 2.5           # coat and smears cut off a second under the polisher
const PASS := 0.55           # coat laid in one pass right over a point, in each direction
const ONE_WAY := 0.3         # what passes only one way make of the coat at most
const BUFF := 2.2            # residue buffed off a second under the towel
const FLASH := 25.0          # seconds the residue can sit before it's flashed into a smear
const FLASH_WARN := 8.0      # the HUD warns this long before
const GRID := 0.08
const JUMP := 0.12           # the pad moved further than this in a frame: lifted off, not a pass

var bike := 0
var model: BikeModel
var layer: FinishLayer
var mode := "polish"          # or "coat"
var slots: Array[String] = []
var items: Array[int] = []
var boxes: Array[AABB] = []
## One entry for each point of paint the pad can get to: where (model space), facing which way,
## on which panel, in which region, its gloss, heat (as of when), burnt, the coat passes each
## way, coat, residue on it (and since when) and smear.
var e_pos := PackedVector3Array()
var e_n := PackedVector3Array()
var e_slot := PackedInt32Array()
var e_cell := PackedInt32Array()
var e_g := PackedFloat32Array()
var e_h := PackedFloat32Array()
var e_ht := PackedFloat32Array()
var e_b := PackedByteArray()
var e_a1 := PackedFloat32Array()
var e_a2 := PackedFloat32Array()
var e_c := PackedFloat32Array()
var e_r := PackedFloat32Array()
var e_rt := PackedFloat32Array()
var e_s := PackedFloat32Array()
## Per panel and region (slot index * Dirt.CELLS + cell): entries, and their sums.
var count := PackedFloat32Array()
var sum_g := PackedFloat32Array()
var sum_b := PackedFloat32Array()
var sum_c := PackedFloat32Array()
var sum_r := PackedFloat32Array()
var sum_s := PackedFloat32Array()
var part_n := PackedInt32Array()
## Each panel's finish as it came in (the regions this job hasn't any paint in keep it).
var base: Array = []
var changed := {}             # slot index -> true: drawn and sent since
var _drawn := {}              # slot index -> true: changed since last drawn
var clock := 0.0
## Where the pad is this frame: {hit, contact, at (world), normal, slot, dist, heat}.
var pad := {}
var cues: Array = []          # {kind ("burn", "gloss", "coat", "smear"), name}
var ready := false
var _raw_p := PackedVector3Array()
var _raw_n := PackedVector3Array()
var _raw_s := PackedInt32Array()
var _occ := PackedByteArray()
var _occ_origin := Vector3.ZERO
var _occ_dims := Vector3i.ONE
var _prep := 0
var _grid := {}
var _grid_box := AABB()
var _last_at := Vector3.INF
var _flash_check := 0.0
var _draw_wait := 0.0
var _stats := {}
var _stats_age := 1.0
var _gloss_dinged := {}
var _coat_dinged := {}


## How much of the pad works on paint it meets at `facing` (the cosine between them).
static func take(facing: float) -> float:
	return clampf((facing - SKIM) / (FLAT - SKIM), 0.0, 1.0)


## Starts on bike `bike_id` drawn as `bike_model`. False if it has no detailed panels drawn yet
## (Detail's "shine_start" puts them on; the bike's redrawn with them a moment later).
func setup(bike_id: int, bike_model: BikeModel, start_mode := "polish") -> bool:
	bike = bike_id
	model = bike_model
	mode = start_mode
	if model == null or not is_instance_valid(model) or model.finish_layer == null or not is_instance_valid(model.finish_layer):
		return false
	layer = model.finish_layer
	var bounds := AABB()
	var first := true
	for slot in Detail.PANELS:
		var id := Shed.item_on(bike, slot)
		if id == 0 or not Shed.items.has(id) or not layer._meshes.has(slot) or not model.is_fitted(slot):
			continue
		var box := model.slot_bounds(slot)
		if box.size == Vector3.ZERO:
			continue
		var surf := _paint_points(slot)
		if (surf[0] as PackedVector3Array).is_empty():
			continue
		var si := slots.size()
		slots.append(slot)
		items.append(id)
		boxes.append(box)
		base.append(Detail.data(Shed.items[id]))
		_raw_p.append_array(surf[0])
		_raw_n.append_array(surf[1])
		for k in (surf[0] as PackedVector3Array).size():
			_raw_s.append(si)
		bounds = box if first else bounds.merge(box)
		first = false
	if slots.is_empty():
		return false
	_build_occupancy(bounds)
	layer.held_by_job = true
	var n := slots.size() * Dirt.CELLS
	for a in [count, sum_g, sum_b, sum_c, sum_r, sum_s]:
		(a as PackedFloat32Array).resize(n)
		(a as PackedFloat32Array).fill(0.0)
	part_n.resize(slots.size())
	part_n.fill(0)
	return true


## Points over a panel's painted meshes (the ones carrying its finish pass), CELL apart.
func _paint_points(slot: String) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot) + 7
	for g in layer._meshes.get(slot, []):
		var mi := g as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or mi.mesh == null or not mi.visible:
			continue
		var xf := model._local_xform(mi)
		var faces := mi.mesh.get_faces()
		for f in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[f]
			var b: Vector3 = xf * faces[f + 1]
			var c: Vector3 = xf * faces[f + 2]
			var nn := (c - a).cross(b - a)
			var area := nn.length() * 0.5
			if area < 1e-7:
				continue
			nn = nn.normalized()
			for k in ceili(area / (CELL * CELL) * 1.5):
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := a + (b - a) * u + (c - a) * v
				var key := Vector3i((p / CELL).floor())
				if seen.has(key):
					continue
				seen[key] = true
				points.append(p)
				normals.append(nn)
	return [points, normals]


## Marks the cubes round the panels that have any of the bike in them, from every part on it.
func _build_occupancy(bounds: AABB) -> void:
	var box := bounds.grow(WAY_OUT + OCC * 2.0)
	_occ_origin = box.position
	_occ_dims = Vector3i(maxi(1, ceili(box.size.x / OCC)), maxi(1, ceili(box.size.y / OCC)), maxi(1, ceili(box.size.z / OCC)))
	_occ.resize(_occ_dims.x * _occ_dims.y * _occ_dims.z)
	_occ.fill(0)
	var all := PackedVector3Array()
	for slot in model._slot_meshes:
		if not model.is_fitted(str(slot)) or (model._slot_meshes[slot] as Array).is_empty():
			continue
		if slots.has(str(slot)):
			continue
		all.append_array(model.surface_points(str(slot), OCC_CELL)[0])
	all.append_array(_raw_p)
	for p in all:
		var v := Vector3i(((p - _occ_origin) / OCC).floor())
		if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= _occ_dims.x or v.y >= _occ_dims.y or v.z >= _occ_dims.z:
			continue
		_occ[v.x + _occ_dims.x * (v.y + _occ_dims.y * v.z)] = 1


## Works through some more of getting ready; true once it's ready.
func prepare(budget := PREP_POINTS) -> bool:
	if ready:
		return true
	var stop := mini(_prep + budget, _raw_p.size())
	while _prep < stop:
		var p := _raw_p[_prep]
		var nn := _raw_n[_prep].normalized()
		var si := _raw_s[_prep]
		_prep += 1
		if nn != Vector3.ZERO and _clear(p, nn):
			_add_entry(p, nn, si)
	if _prep >= _raw_p.size():
		_finish_prep()
	return ready


func prepare_all() -> void:
	while not prepare(100000):
		pass


func _clear(p: Vector3, d: Vector3) -> bool:
	var t := OCC * 2.5
	while t < WAY_OUT:
		var v := Vector3i(((p + d * t - _occ_origin) / OCC).floor())
		if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= _occ_dims.x or v.y >= _occ_dims.y or v.z >= _occ_dims.z:
			return true
		if _occ[v.x + _occ_dims.x * (v.y + _occ_dims.y * v.z)] != 0:
			return false
		t += OCC
	return true


func _add_entry(p: Vector3, n: Vector3, si: int) -> void:
	var c := Dirt.facing_of(n) * Dirt.NX * Dirt.NY + Dirt.spot_in(boxes[si], p)
	var d: Dictionary = base[si]
	var k := si * Dirt.CELLS + c
	e_pos.append(p)
	e_n.append(n)
	e_slot.append(si)
	e_cell.append(c)
	var burnt: bool = d["b"][c] >= 128
	var g: float = 0.0 if burnt else d["g"][c] / 255.0
	e_g.append(g)
	e_h.append(0.0)
	e_ht.append(0.0)
	e_b.append(1 if burnt else 0)
	var cv: float = d["c"][c] / 255.0
	e_c.append(cv)
	e_a1.append(cv)
	e_a2.append(cv)
	var r: float = d["r"][c] / 255.0
	e_r.append(r)
	e_rt.append(0.0)
	var sm: float = d["s"][c] / 255.0
	e_s.append(sm)
	count[k] += 1.0
	sum_g[k] += g
	sum_b[k] += 1.0 if burnt else 0.0
	sum_c[k] += cv
	sum_r[k] += r
	sum_s[k] += sm
	part_n[si] += 1


func _finish_prep() -> void:
	ready = true
	_raw_p = PackedVector3Array()
	_raw_n = PackedVector3Array()
	_raw_s = PackedInt32Array()
	_occ = PackedByteArray()
	_grid.clear()
	for i in e_pos.size():
		var p := e_pos[i]
		_grid_box = AABB(p, Vector3.ZERO) if i == 0 else _grid_box.expand(p)
		var c := Vector3i((p / GRID).floor())
		var list: Array = _grid.get(c, [])
		if list.is_empty():
			_grid[c] = list
		list.append(i)
	# Panels already glossy or coated don't ding again.
	for si in slots.size():
		var st := panel(si)
		if float(st["gloss"]) >= Detail.GLOSS_GOOD:
			_gloss_dinged[si] = true
		if float(st["coat"]) >= Detail.COAT_GOOD:
			_coat_dinged[si] = true
		changed[si] = true
		_drawn[si] = true
	_show()


func _entries_near(p: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := Vector3i(((p - Vector3.ONE * r) / GRID).floor())
	var hi := Vector3i(((p + Vector3.ONE * r) / GRID).floor())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var list = _grid.get(Vector3i(x, y, z))
				if list != null:
					out.append_array(PackedInt32Array(list))
	return out


## Where the line from `eye` along `dir` (world) first meets the paint the pad can get to:
## {at, normal, t, slot (index)}, or {}.
func surface_hit(eye: Vector3, dir: Vector3, width := 0.025) -> Dictionary:
	if not ready or model == null or not is_instance_valid(model) or e_pos.is_empty():
		return {}
	var xf := model.global_transform
	var inv := xf.affine_inverse()
	var e: Vector3 = inv * eye
	var d: Vector3 = (inv.basis * dir).normalized()
	var best := INF
	var bi := -1
	# Along the line out to arm's length, through the grid.
	var t := 0.0
	var seen := {}
	while t <= REACH + GRID:
		var q := e + d * t
		var c := Vector3i((q / GRID).floor())
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var cc := c + Vector3i(dx, dy, dz)
					if seen.has(cc):
						continue
					seen[cc] = true
					var list = _grid.get(cc)
					if list == null:
						continue
					for i in list:
						var v := e_pos[i] - e
						var tt := v.dot(d)
						if tt <= 0.0 or tt >= best or e_n[i].dot(d) > 0.0:
							continue
						if (v - d * tt).length_squared() < width * width:
							best = tt
							bi = i
		if bi >= 0 and best < t - GRID:
			break
		t += GRID * 0.5
	if bi < 0:
		return {}
	return {"at": xf * (e + d * best), "normal": (xf.basis * e_n[bi]).normalized(), "t": best * (xf.basis * d).length(), "slot": e_slot[bi]}


## One frame from `eye` along `dir` (world). `work`: the main button (polishing, or wiping the
## coat on); `alt`: the second (pressing hard on the polisher, or the microfibre buffing).
## `speed` is the polisher's own (its upgrades).
func step(delta: float, eye: Vector3, dir: Vector3, work: bool, alt: bool, speed := 1.0) -> void:
	clock += delta
	var sh := surface_hit(eye, dir)
	var contact := not sh.is_empty() and float(sh["t"]) <= REACH
	pad = {"hit": not sh.is_empty(), "contact": contact, "at": sh.get("at", eye + dir), "normal": sh.get("normal", Vector3.UP),
		"slot": int(sh["slot"]) if not sh.is_empty() else -1, "dist": float(sh.get("t", REACH + 1.0)), "heat": 0.0}
	_stats_age += delta
	_flash_check -= delta
	if _flash_check <= 0.0:
		_flash_check = 0.25
		_flash()
	if not ready:
		return
	var inv := model.global_transform.affine_inverse()
	var a: Vector3 = inv * (pad["at"] as Vector3)
	var d: Vector3 = (inv.basis * dir).normalized()
	var moved := Vector3.ZERO
	if contact and _last_at != Vector3.INF and a.distance_to(_last_at) < JUMP:
		moved = a - _last_at
	_last_at = a if contact else Vector3.INF
	pad["heat"] = _heat_near(a, PAD * 0.5) if contact else 0.0
	if not contact or not (work or alt):
		_redraw(delta)
		return
	var touched := {}
	if mode == "polish":
		_polish(a, d, delta, alt, speed, touched)
	elif work and not alt:
		_lay(a, d, moved, touched)
	elif alt:
		_buff(a, d, delta, touched)
	pad["heat"] = _heat_near(a, PAD * 0.5)
	for si in touched:
		changed[si] = true
		_drawn[si] = true
	_check_cues(touched)
	_stats_age = 1.0
	_redraw(delta)


func _heat_now(i: int) -> float:
	return maxf(0.0, e_h[i] - COOL * (clock - e_ht[i]))


## The hottest the paint is under the middle of the pad.
func _heat_near(a: Vector3, r: float) -> float:
	var top := 0.0
	for i in _entries_near(a, r):
		if e_pos[i].distance_squared_to(a) <= r * r:
			top = maxf(top, _heat_now(i))
	return top


func _polish(a: Vector3, d: Vector3, delta: float, hard: bool, speed: float, touched: Dictionary) -> void:
	var r := PAD * speed_spread(speed)
	var press := HEAVY if hard else 1.0
	var heat := HEAT * (HEAVY_HEAT if hard else 1.0)
	for i in _entries_near(a, r):
		var l := e_pos[i].distance_to(a)
		if l > r:
			continue
		var tk := take(-e_n[i].dot(d))
		if tk <= 0.0:
			continue
		var w := tk * (1.0 - FALLOFF * l / r)
		var k := e_slot[i] * Dirt.CELLS + e_cell[i]
		touched[e_slot[i]] = true
		# The heat builds under the pad and goes off it again as it moves on.
		var h := _heat_now(i) + heat * w * delta
		e_h[i] = h
		e_ht[i] = clock
		if e_b[i] == 0 and h >= BURN:
			# Through the clear coat: dull for good.
			e_b[i] = 1
			sum_b[k] += 1.0
			sum_g[k] -= e_g[i]
			e_g[i] = 0.0
			cues.append({"kind": "burn", "name": PartsDB.slot_name(slots[e_slot[i]]), "slot": slots[e_slot[i]]})
		if e_b[i] == 0:
			var g := e_g[i] + (1.0 - e_g[i]) * minf(1.0, CUT * press * speed * w * delta)
			sum_g[k] += g - e_g[i]
			e_g[i] = g
		# It cuts off any coat, residue and smears there too.
		var keep := 1.0 - minf(1.0, STRIP * press * w * delta)
		var nc := e_c[i] * keep
		sum_c[k] += nc - e_c[i]
		e_c[i] = nc
		e_a1[i] *= keep
		e_a2[i] *= keep
		var nr := e_r[i] * keep
		sum_r[k] += nr - e_r[i]
		e_r[i] = nr
		var ns := e_s[i] * keep
		sum_s[k] += ns - e_s[i]
		e_s[i] = ns


## How much bigger the pad works with the polisher's upgrades.
static func speed_spread(speed: float) -> float:
	return clampf(1.0 + (speed - 1.0) * 0.5, 1.0, 1.5)


## Wiping the coat on: each point the applicator crosses gets a pass along the way it went,
## counted one way (along the bike) and across; a cross-hatch makes a full coat.
func _lay(a: Vector3, d: Vector3, moved: Vector3, touched: Dictionary) -> void:
	var dist := moved.length()
	if dist <= 1e-5:
		return
	var n: Vector3 = (-d).normalized()
	var along := Vector3.BACK - n * n.dot(Vector3.BACK)
	if along.length() < 0.3:
		along = Vector3.RIGHT - n * n.dot(Vector3.RIGHT)
	along = along.normalized()
	var across := n.cross(along).normalized()
	var m := moved - n * n.dot(moved)
	var u := absf(m.dot(along)) / (2.0 * APPLICATOR) * PASS
	var v := absf(m.dot(across)) / (2.0 * APPLICATOR) * PASS
	for i in _entries_near(a, APPLICATOR):
		if e_pos[i].distance_to(a) > APPLICATOR:
			continue
		var tk := take(-e_n[i].dot(d))
		if tk <= 0.0:
			continue
		var k := e_slot[i] * Dirt.CELLS + e_cell[i]
		touched[e_slot[i]] = true
		e_a1[i] = minf(1.0, e_a1[i] + u * tk)
		e_a2[i] = minf(1.0, e_a2[i] + v * tk)
		var lo := minf(e_a1[i], e_a2[i])
		var hi := maxf(e_a1[i], e_a2[i])
		var c := clampf(lo * (1.0 - ONE_WAY) + hi * ONE_WAY, 0.0, 1.0)
		if c > e_c[i]:
			var add := c - e_c[i]
			sum_c[k] += add
			e_c[i] = c
			# Fresh coat is wet residue till it's buffed off; its flash clock starts with the first.
			if e_r[i] < 0.02:
				e_rt[i] = clock
			var nr := minf(1.0, e_r[i] + add * 1.4 + 0.02)
			sum_r[k] += nr - e_r[i]
			e_r[i] = nr


## Buffing the residue off with the microfibre (it can't shift a smear: that's gone hard).
func _buff(a: Vector3, d: Vector3, delta: float, touched: Dictionary) -> void:
	for i in _entries_near(a, TOWEL):
		var l := e_pos[i].distance_to(a)
		if l > TOWEL or e_r[i] <= 0.0:
			continue
		var tk := take(-e_n[i].dot(d))
		if tk <= 0.0:
			continue
		var k := e_slot[i] * Dirt.CELLS + e_cell[i]
		touched[e_slot[i]] = true
		var nr := maxf(0.0, e_r[i] - BUFF * tk * (1.0 - 0.4 * l / TOWEL) * delta)
		if nr < 0.02:
			nr = 0.0
		sum_r[k] += nr - e_r[i]
		e_r[i] = nr


## Residue that's sat too long flashes into a smear.
func _flash() -> void:
	if not ready:
		return
	var hit := {}
	for i in e_pos.size():
		if e_r[i] > 0.0 and clock - e_rt[i] > FLASH:
			var k := e_slot[i] * Dirt.CELLS + e_cell[i]
			var ns := minf(1.0, e_s[i] + e_r[i])
			sum_s[k] += ns - e_s[i]
			e_s[i] = ns
			sum_r[k] -= e_r[i]
			e_r[i] = 0.0
			hit[e_slot[i]] = true
	for si in hit:
		changed[si] = true
		_drawn[si] = true
		cues.append({"kind": "smear", "name": PartsDB.slot_name(slots[si]), "slot": slots[si]})
	if not hit.is_empty():
		_stats_age = 1.0


## The soonest any residue flashes, in seconds (INF with none on), and on which panel.
func flash_left() -> Dictionary:
	var best := INF
	var bs := -1
	for i in e_pos.size():
		if e_r[i] > 0.0:
			var left := FLASH - (clock - e_rt[i])
			if left < best:
				best = left
				bs = e_slot[i]
	return {"left": best, "slot": bs}


func _check_cues(touched: Dictionary) -> void:
	for si in touched:
		var st := panel(si)
		if not _gloss_dinged.has(si) and float(st["gloss"]) >= Detail.GLOSS_GOOD and int(st["burns"]) == 0:
			_gloss_dinged[si] = true
			cues.append({"kind": "gloss", "name": PartsDB.slot_name(slots[si]), "slot": slots[si]})
		if not _coat_dinged.has(si) and float(st["coat"]) >= Detail.COAT_GOOD and float(st["residue"]) < 0.02 and int(st["smears"]) == 0:
			_coat_dinged[si] = true
			cues.append({"kind": "coat", "name": PartsDB.slot_name(slots[si]), "slot": slots[si]})


## How a panel is going: {gloss, coat, residue, burns (regions), smears (regions)}, over the
## regions this job has paint in.
func panel(si: int) -> Dictionary:
	var n := 0
	var g := 0.0
	var c := 0.0
	var r := 0.0
	var burns := 0
	var smears := 0
	for cell in Dirt.CELLS:
		var k := si * Dirt.CELLS + cell
		if count[k] <= 0.0:
			continue
		n += 1
		g += sum_g[k] / count[k]
		c += sum_c[k] / count[k]
		r += sum_r[k] / count[k]
		if _burn_level(k) >= Detail.BURN_AT:
			burns += 1
		if sum_s[k] / count[k] >= Detail.SMEAR_AT:
			smears += 1
	if n == 0:
		return {"gloss": 1.0, "coat": 1.0, "residue": 0.0, "burns": 0, "smears": 0}
	return {"gloss": g / n, "coat": c / n, "residue": r / n, "burns": burns, "smears": smears}


## A region's burn as kept: a few burnt points show as a patch there.
func _burn_level(k: int) -> float:
	return clampf(sum_b[k] / maxf(count[k], 1.0) * 4.0, 0.0, 1.0) if sum_b[k] > 0.0 else 0.0


## How it's going: {gloss, coat (the whole bike's, over its panels), burns, smears, panels:
## [{slot, name, gloss, coat, residue, burns, smears}] (least done first)}.
func stats() -> Dictionary:
	if _stats_age < 0.1 and not _stats.is_empty():
		return _stats
	_stats_age = 0.0
	var parts := []
	var g := 0.0
	var c := 0.0
	var burns := 0
	var smears := 0
	var n := 0
	for si in slots.size():
		if part_n[si] == 0:
			continue
		var st := panel(si)
		st["slot"] = slots[si]
		st["name"] = PartsDB.slot_name(slots[si])
		st["index"] = si
		parts.append(st)
		g += float(st["gloss"])
		c += float(st["coat"])
		burns += int(st["burns"])
		smears += int(st["smears"])
		n += 1
	var key := "gloss" if mode == "polish" else "coat"
	parts.sort_custom(func(x, y): return float(x[key]) < float(y[key]))
	_stats = {"gloss": g / maxf(n, 1), "coat": c / maxf(n, 1), "burns": burns, "smears": smears, "panels": parts}
	return _stats


## A panel's finish as this job has it, for the shed and the drawing (see Detail.data).
func finish_of(si: int) -> Dictionary:
	var d: Dictionary = base[si]
	var g: PackedByteArray = (d["g"] as PackedByteArray).duplicate()
	var b: PackedByteArray = (d["b"] as PackedByteArray).duplicate()
	var c: PackedByteArray = (d["c"] as PackedByteArray).duplicate()
	var r: PackedByteArray = (d["r"] as PackedByteArray).duplicate()
	var s: PackedByteArray = (d["s"] as PackedByteArray).duplicate()
	var u: PackedByteArray = (d["u"] as PackedByteArray).duplicate()
	for cell in Dirt.CELLS:
		var k := si * Dirt.CELLS + cell
		if count[k] <= 0.0:
			u[cell] = 0
			continue
		u[cell] = 1
		g[cell] = clampi(roundi(sum_g[k] / count[k] * 255.0), 0, 255)
		b[cell] = clampi(roundi(_burn_level(k) * 255.0), 0, 255)
		c[cell] = clampi(roundi(sum_c[k] / count[k] * 255.0), 0, 255)
		r[cell] = clampi(roundi(sum_r[k] / count[k] * 255.0), 0, 255)
		s[cell] = clampi(roundi(sum_s[k] / count[k] * 255.0), 0, 255)
	return {"g": g, "b": b, "c": c, "r": r, "s": s, "u": u}


## What's changed since the last update, for the shed: {item: finish}, or {} if nothing has.
func take_updates() -> Dictionary:
	var out := {}
	for si in changed:
		out[items[si]] = finish_of(si)
	changed.clear()
	return out


func _redraw(delta: float) -> void:
	_draw_wait -= delta
	if _draw_wait > 0.0 or _drawn.is_empty():
		return
	_draw_wait = 1.0 / 15.0
	_show(_drawn)
	_drawn.clear()


## Draws the panels as this job has them (those in `only`, by slot index, or all).
func _show(only := {}) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	for si in slots.size():
		if only.is_empty() or only.has(si):
			layer.set_finish(slots[si], finish_of(si))


## Draws everything now (for tests and screenshots).
func flush() -> void:
	_show()
	_drawn.clear()


## Whether the finish pass is still on the bike as drawn (it hasn't been redrawn since).
func attached() -> bool:
	return layer != null and is_instance_valid(layer) and model != null and is_instance_valid(model) and layer.get_parent() == model


## Done (or stepped back): the bike's drawn from the shed's finish again.
func finish() -> void:
	if layer != null and is_instance_valid(layer):
		layer.held_by_job = false
		layer.set_scan(false)
