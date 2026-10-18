class_name WashJob
extends RefCounted
## Pressure washing a bike by hand: the mini game behind the pressure washer (F with it on a
## bike), like spraying a coat on (SprayJob). The bike's surfaces are covered in points
## (BikeModel.surface_points), one for each side of them the jet can get to (not the inside of a
## tank or the faces shut away behind something), each in one of its part's dirt regions (Dirt).
##
## Where the jet lands it washes the dirt off the surfaces facing it (a surface side on to it
## barely gets wet, one facing away not at all, so you have to go round the bike, and raise it on
## the wash bay's lift and crouch for underneath), as wide as the distance makes it and weaker the
## further off you are; caked muck takes longer than a film of dust. What's washed off shows on the bike there and then, exactly
## where the jet went (DirtLayer's wash mask), and the shed hears every few moments how much of
## each region has come off, as a share of what was there (`take_updates`), so the rest of the
## crew see it come clean too, and two of you can wash the same bike at once.
##
## A part is clean once all of it is (PART_DONE of its surface): a ding, and it's called clean to
## the shed. The whole bike clean: a bigger one.

const CELL := 0.045          # the surface is sampled this far apart
const OCC := 0.035           # cubes for working out which sides of the surface the jet can get to
const WAY_OUT := 0.4         # metres clear of the bike out from a point, and the jet can get to it
const PREP_POINTS := 250     # points a frame worked through getting ready
const RADIUS := 0.12         # the jet's footprint at D_REF (a fan tip: a good wide stripe)
const D_REF := 0.6
const RATE := 14.0           # washed off a second in the middle of the jet (less for caked muck)
const FALLOFF := 0.35        # weaker to the edge of the footprint
const CAKED := 1.0           # how much longer caked muck takes than a film of dust (see grip())
const NEAR := 0.15           # closer than this the footprint's tiny
const FAR := 1.2             # further than this it starts to lose its bite
const OUT := 2.6             # and past this it doesn't reach at all
const SKIM := 0.1            # how square on the jet has to meet a surface: none at all this side on,
const FACE_ON := 0.5         # all of it by this (cosines)
const PART_DONE := 0.975     # this much of a part clean and it's done
const SPECKS := 0.02         # or all but this share of its patches (at least SPECKS_MIN), see _clean_enough
const SPECKS_MIN := 3
const CREDIT_SPAN := 0.3     # a patch this much dirtier than clean counts for nothing
const GRID := 0.1            # the entries are filed in cubes this size, to find those near the jet

var bike := 0
var model: BikeModel
var layer: DirtLayer
var slots: Array[String] = []
var items: Array[int] = []   # the part in each slot (same order)
var boxes: Array[AABB] = []  # each part's bounds, as its regions are laid over it
## One entry for each side of a surface point the jet can get to: where (model space), facing
## which way (outwards), on which part, in which of its regions (Dirt cell), its cube in the
## wash mask, and how much has been washed off it (0..1).
var e_pos := PackedVector3Array()
var e_n := PackedVector3Array()
var e_slot := PackedInt32Array()
var e_cell := PackedInt32Array()
var e_vox := PackedInt32Array()
var e_w := PackedFloat32Array()
## Per part and region (slot index * Dirt.CELLS + cell): how dirty it was before this wash (as
## it's drawn: evened out by what's already been washed), entries in it, washed off them all
## told, and the share washed as last sent to the shed.
var start := PackedFloat32Array()
var count := PackedFloat32Array()
var wsum := PackedFloat32Array()
var sent := PackedFloat32Array()
var part_n := PackedInt32Array()   # entries on each part
var slick := PackedFloat32Array()  # how much quicker each part washes off (its ceramic coat, see Detail)
var done := {}               # slot index -> true once it's clean
var dinged := {}             # slot index -> true once its ding has gone off (once a part)
var bike_done := false
var bike_dinged := false
var to_call_clean: Array[int] = []   # parts gone clean since the last update to the shed
var cues: Array = []         # things to tell the player: {kind ("part" or "bike"), name}
## The jet this frame: {hit, at (world), normal, dist, zone, radius, slot}
var jet := {}
var ready := false
var _raw_p := PackedVector3Array()
var _raw_n := PackedVector3Array()
var _raw_s := PackedInt32Array()
var _occ := PackedByteArray()
var _occ_origin := Vector3.ZERO
var _occ_dims := Vector3i.ONE
var _prep := 0
var _stats := {}
var _stats_age := 1.0
var _eye := Vector3.INF
var _mid := Vector3.ZERO
static var _tilts: Array[Vector3] = []
## The entries filed by cube (Vector3i -> [entry indices]), the box round them all, and each
## part's entries (by slot index): the jet only looks at the ones it can reach.
var _grid := {}
var _grid_box := AABB()
var _slot_entries: Array = []


## How much of the jet lands on a surface it meets at `facing` (the cosine of the angle between
## them): none side on, all of it square on.
static func take(facing: float) -> float:
	return clampf((facing - SKIM) / (FACE_ON - SKIM), 0.0, 1.0)


## How hard dirt as thick as `level` (0..1) holds on: the jet's rate is divided by this, so a
## film of dust goes in a flash and caked mud takes a couple of passes.
static func grip(level: float) -> float:
	return 0.4 + CAKED * level


## Starts on bike `bike_id` drawn as `bike_model`. False if there's nothing of it to wash.
## Getting ready (which sides of it the jet can get to) is worked through a frame at a time by
## prepare(); prepare_all() does it at once.
func setup(bike_id: int, bike_model: BikeModel) -> bool:
	bike = bike_id
	model = bike_model
	if model == null or not is_instance_valid(model):
		return false
	var bounds := AABB()
	var first := true
	for slot in model._slot_meshes:
		var id := Shed.item_on(bike, str(slot))
		if id == 0 or not Shed.items.has(id) or not model.is_fitted(str(slot)):
			continue
		var shown := (model._slot_meshes[slot] as Array).filter(func(mi): return is_instance_valid(mi) and (mi as Node3D).visible)
		if shown.is_empty():
			continue
		var box := model.slot_bounds(str(slot))
		if box.size == Vector3.ZERO:
			continue
		var surf := model.surface_points(str(slot), CELL)
		if (surf[0] as PackedVector3Array).is_empty():
			continue
		var si := slots.size()
		slots.append(str(slot))
		items.append(id)
		boxes.append(box)
		slick.append(Detail.wash_mult(Shed.items[id]))
		_raw_p.append_array(surf[0])
		_raw_n.append_array(surf[1])
		for k in (surf[0] as PackedVector3Array).size():
			_raw_s.append(si)
		bounds = box if first else bounds.merge(box)
		first = false
	if slots.is_empty():
		return false
	_mid = bounds.get_center()
	_build_occupancy(bounds)
	layer = model.ensure_dirt_layer()
	layer.make_mask(bounds)
	layer.held_by_job = true
	var n := slots.size() * Dirt.CELLS
	start.resize(n)
	count.resize(n)
	count.fill(0.0)
	wsum.resize(n)
	wsum.fill(0.0)
	sent.resize(n)
	part_n.resize(slots.size())
	part_n.fill(0)
	for si in slots.size():
		var synced := Dirt.cells(Shed.items[items[si]], slots[si])
		layer.levels[slots[si]] = synced
		var drawn := layer.drawn(slots[si])
		for c in Dirt.CELLS:
			start[si * Dirt.CELLS + c] = drawn[c]
	return true


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
		if nn == Vector3.ZERO:
			continue
		for side in [nn, -nn]:
			if _open(p, side):
				_add_entry(p, side, si)
	if _prep >= _raw_p.size():
		_finish_prep()
	return ready


func prepare_all() -> void:
	while not prepare(100000):
		pass


func _add_entry(p: Vector3, n: Vector3, si: int) -> void:
	var c := Dirt.facing_of(n) * Dirt.NX * Dirt.NY + Dirt.spot_in(boxes[si], p)
	var vox := layer.index_of(p)
	e_pos.append(p)
	e_n.append(n)
	e_slot.append(si)
	e_cell.append(c)
	e_vox.append(vox)
	# Anything already washed off here (an earlier go at it) stays washed.
	var w := layer.washed_facing(vox, n)
	e_w.append(w)
	count[si * Dirt.CELLS + c] += 1.0
	wsum[si * Dirt.CELLS + c] += w
	part_n[si] += 1


func _finish_prep() -> void:
	ready = true
	_raw_p = PackedVector3Array()
	_raw_n = PackedVector3Array()
	_raw_s = PackedInt32Array()
	_occ = PackedByteArray()
	for k in sent.size():
		sent[k] = wsum[k] / count[k] if count[k] > 0.0 else 0.0
	_build_grid()
	# Parts that are clean already (or the jet can't get at) are done, without a ding.
	var cleans := _part_cleans()
	for si in slots.size():
		if part_n[si] == 0 or _clean_enough(si, float(cleans[si])):
			done[si] = true
			dinged[si] = true
	bike_done = done.size() >= slots.size()
	bike_dinged = bike_done
	_show()


## Files every entry in its cube of the grid, and under its part.
func _build_grid() -> void:
	_grid.clear()
	_slot_entries.clear()
	var per_part := []
	for si in slots.size():
		per_part.append([])
	for i in e_pos.size():
		var p := e_pos[i]
		_grid_box = AABB(p, Vector3.ZERO) if i == 0 else _grid_box.expand(p)
		var c := Vector3i((p / GRID).floor())
		var list: Array = _grid.get(c, [])
		if list.is_empty():
			_grid[c] = list
		list.append(i)
		(per_part[e_slot[i]] as Array).append(i)
	for list in per_part:
		_slot_entries.append(PackedInt32Array(list))


## The entries within `r` of `p` (model space) and perhaps a few more, in order.
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
	out.sort()
	return out


## The entries within `width` of the line from `e` along `d` (model space, d of unit length)
## and perhaps a few more, in order.
func _entries_along(e: Vector3, d: Vector3, width: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var box := _grid_box.grow(width + 0.01)
	# Where the line is in the box round the entries.
	var t0 := 0.0
	var t1 := INF
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if e[axis] < box.position[axis] or e[axis] > box.end[axis]:
				return out
			continue
		var ta := (box.position[axis] - e[axis]) / d[axis]
		var tb := (box.end[axis] - e[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 < t0:
		return out
	var step := GRID * 0.5
	var m := sqrt(width * width + step * step * 0.25) + 0.001
	var seen := {}
	var t := t0
	while true:
		var q := e + d * minf(t, t1)
		var lo := Vector3i(((q - Vector3.ONE * m) / GRID).floor())
		var hi := Vector3i(((q + Vector3.ONE * m) / GRID).floor())
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var c := Vector3i(x, y, z)
					if seen.has(c):
						continue
					seen[c] = true
					var list = _grid.get(c)
					if list != null:
						out.append_array(PackedInt32Array(list))
		if t >= t1:
			break
		t += step
	out.sort()
	return out


## Marks which cubes round the bike have some of it in them (a little fattened, so the jet can't
## slip between the sample points), for working out what it can get to.
func _build_occupancy(bounds: AABB) -> void:
	var box := bounds.grow(OCC * 2.0)
	_occ_origin = box.position
	_occ_dims = Vector3i(maxi(1, ceili(box.size.x / OCC)), maxi(1, ceili(box.size.y / OCC)), maxi(1, ceili(box.size.z / OCC)))
	_occ.resize(_occ_dims.x * _occ_dims.y * _occ_dims.z)
	_occ.fill(0)
	for p in _raw_p:
		var v := Vector3i(((p - _occ_origin) / OCC).floor())
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var q := v + Vector3i(dx, dy, dz)
					if q.x >= 0 and q.y >= 0 and q.z >= 0 and q.x < _occ_dims.x and q.y < _occ_dims.y and q.z < _occ_dims.z:
						_occ[q.x + _occ_dims.x * (q.y + _occ_dims.y * q.z)] = 1


static func tilts() -> Array[Vector3]:
	if _tilts.is_empty():
		for v in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			_tilts.append(v)
	return _tilts


## Whether the jet could get to a point from the side `n` faces: straight out along it, or
## failing that from a little round about it, with nothing of the bike in the way.
func _open(p: Vector3, n: Vector3) -> bool:
	if _clear(p, n):
		return true
	for t in tilts():
		if absf(t.dot(n)) > 0.9:
			continue
		if _clear(p, (n + t * 0.8).normalized()):
			return true
	return false


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


## Where the line from `eye` along `dir` (world) first meets the bike's washable surface (a side
## of it facing back up the line): {at, normal, t, slot (index)}, or {}.
func surface_hit(eye: Vector3, dir: Vector3, width := 0.03) -> Dictionary:
	if not ready or model == null or not is_instance_valid(model) or e_pos.is_empty():
		return {}
	var xf := model.global_transform
	var inv := xf.affine_inverse()
	var e: Vector3 = inv * eye
	var d: Vector3 = (inv.basis * dir).normalized()
	var best := INF
	var bi := -1
	for i in _entries_along(e, d, width):
		var v := e_pos[i] - e
		var t := v.dot(d)
		if t <= 0.0 or t >= best or e_n[i].dot(d) > 0.0:
			continue
		if (v - d * t).length_squared() < width * width:
			best = t
			bi = i
	if bi < 0:
		return {}
	return {"at": xf * (e + d * best), "normal": (xf.basis * e_n[bi]).normalized(), "t": best * (xf.basis * d).length(), "slot": e_slot[bi]}


## How the jet lands at `dist`: {zone ("close", "good", "far", "out"), radius, power (0..1)}.
static func jet_at(dist: float, spread := 1.0) -> Dictionary:
	var zone := "good"
	if dist < NEAR:
		zone = "close"
	elif dist > OUT:
		zone = "out"
	elif dist > FAR:
		zone = "far"
	return {"zone": zone, "radius": RADIUS * spread * clampf(dist / D_REF, 0.5, 2.4), "power": 1.0 - smoothstep(FAR, OUT, dist)}


## One frame of washing from `eye` along `dir` (world). `hit`/`at`/`normal`: where the jet meets
## anything at all (the floor, a wall: it splashes there when it misses the bike). Not `firing`, it
## only works out where the jet would land. `strength` is the washer's own (its upgrades and
## Elbow Grease), `spread` how much wider it is.
func step(delta: float, eye: Vector3, dir: Vector3, firing: bool, hit := false, at := Vector3.ZERO, normal := Vector3.UP,
		strength := 1.0, spread := 1.0) -> void:
	_eye = eye
	var sh := surface_hit(eye, dir)
	var on_bike := not sh.is_empty() and (not hit or eye.distance_to(at) > float(sh["t"]) - 0.05)
	if on_bike:
		at = sh["at"]
		normal = sh["normal"]
		hit = true
	var dist := eye.distance_to(at) if hit else OUT + 1.0
	var j := jet_at(dist, spread)
	jet = {"hit": hit, "bike": on_bike, "at": at, "normal": normal, "dist": dist, "zone": j["zone"] if hit else "out",
		"radius": j["radius"], "slot": int(sh["slot"]) if on_bike else -1}
	_stats_age += delta
	if not firing or not on_bike or not ready:
		return
	var inv := model.global_transform.affine_inverse()
	var a: Vector3 = inv * at
	var d: Vector3 = (inv.basis * dir).normalized()
	var r := float(j["radius"])
	var power := float(j["power"]) * strength
	if power <= 0.0:
		return
	var r2 := r * r
	var hit_level := 0.3
	var hs := int(sh["slot"])
	var touched := {}
	for i in _entries_near(a, r):
		var v := e_pos[i] - a
		var l2 := v.length_squared()
		if l2 > r2:
			continue
		var tk := take(-e_n[i].dot(d))
		if tk <= 0.0 or e_w[i] >= 1.0:
			continue
		var k := e_slot[i] * Dirt.CELLS + e_cell[i]
		var lvl := start[k]
		if e_slot[i] == hs:
			hit_level = lvl
		var add := minf(1.0 - e_w[i], delta * RATE * power * tk * (1.0 - FALLOFF * sqrt(l2) / r) / grip(lvl) * slick[e_slot[i]])
		e_w[i] += add
		wsum[k] += add
		touched[e_slot[i]] = true
	layer.wash(a, d, r, delta * RATE * power / grip(hit_level), FALLOFF)
	_stats_age = 1.0
	_check_done(touched)
	_show(touched)


## How clean a part is now, 0..1: each side of its surface the jet can get to counts in full once
## it's clean, and less the dirtier it still is.
func part_clean(si: int) -> float:
	if part_n[si] == 0:
		return 1.0
	if done.get(si, false):
		return 1.0
	var sum := 0.0
	var n := 0
	for i in e_pos.size():
		if e_slot[i] != si:
			continue
		n += 1
		var lp := start[si * Dirt.CELLS + e_cell[i]] * (1.0 - e_w[i])
		sum += 1.0 if lp <= Dirt.CLEAN else clampf(1.0 - (lp - Dirt.CLEAN) / CREDIT_SPAN, 0.0, 1.0)
	return sum / maxf(n, 1)


func _check_done(touched := {}) -> void:
	# Only the parts the jet's just been on can have come clean (all of them after a resync).
	var only := touched.duplicate()
	var cleans := _part_cleans(only)
	for si in slots.size():
		if done.get(si, false) or (not only.is_empty() and not only.has(si)):
			continue
		if _clean_enough(si, float(cleans[si])):
			done[si] = true
			to_call_clean.append(items[si])
			# The last specks go with it.
			for c in Dirt.CELLS:
				start[si * Dirt.CELLS + c] = 0.0
			layer.wash_all(boxes[si])
			touched[si] = true
			if not dinged.get(si, false):
				dinged[si] = true
				cues.append({"kind": "part", "name": PartsDB.slot_name(slots[si]), "slot": slots[si]})
	if not bike_done and done.size() >= slots.size():
		bike_done = true
		# The bits the jet can't get at go with the rest, so the shed calls the whole bike clean.
		for si in slots.size():
			if not to_call_clean.has(items[si]):
				to_call_clean.append(items[si])
		if not bike_dinged:
			bike_dinged = true
			cues.append({"kind": "bike", "name": str(Shed.bikes.get(bike, {}).get("name", "The bike"))})


## Whether a part `clean` (0..1) clean is done: PART_DONE of it, or all but a few patches (SPECKS:
## a speck in a fold the jet can't quite get square on to shouldn't hold it up).
func _clean_enough(si: int, clean: float) -> bool:
	return clean >= PART_DONE or (1.0 - clean) * part_n[si] <= maxf(SPECKS_MIN, SPECKS * part_n[si])


## How clean every part is: [one per slot index]. With `only` (slot index -> true), just those
## parts are gone over (the rest aren't, and come back as clean).
func _part_cleans(only := {}) -> Array:
	var sums := PackedFloat32Array()
	sums.resize(slots.size())
	var ns := PackedInt32Array()
	ns.resize(slots.size())
	if only.is_empty() or _slot_entries.size() != slots.size():
		for i in e_pos.size():
			var si := e_slot[i]
			ns[si] += 1
			var lp := start[si * Dirt.CELLS + e_cell[i]] * (1.0 - e_w[i])
			sums[si] += 1.0 if lp <= Dirt.CLEAN else clampf(1.0 - (lp - Dirt.CLEAN) / CREDIT_SPAN, 0.0, 1.0)
	else:
		for si in only:
			for i in (_slot_entries[si] as PackedInt32Array):
				ns[si] += 1
				var lp := start[si * Dirt.CELLS + e_cell[i]] * (1.0 - e_w[i])
				sums[si] += 1.0 if lp <= Dirt.CLEAN else clampf(1.0 - (lp - Dirt.CLEAN) / CREDIT_SPAN, 0.0, 1.0)
	var out := []
	for si in slots.size():
		out.append(1.0 if done.get(si, false) or ns[si] == 0 else sums[si] / ns[si])
	return out


## How the wash is going: {clean (the whole bike, 0..1), parts ([{slot, name, clean}], dirtiest
## first), sides ({near, far, top, under} clean, as seen from where you are; -1 for none)}.
func stats() -> Dictionary:
	if _stats_age < 0.1 and not _stats.is_empty():
		return _stats
	_stats_age = 0.0
	var cleans := _part_cleans()
	var basis := model.global_transform.basis if model != null and is_instance_valid(model) else Basis()
	var toward := Vector2.ZERO
	if _eye != Vector3.INF and model != null and is_instance_valid(model):
		var t := _eye - model.global_transform * _mid
		toward = Vector2(t.x, t.z).normalized()
	# Tallied by side (near, far, top, under) in arrays: this goes through every point.
	var side_n := PackedInt32Array([0, 0, 0, 0])
	var side_c := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var is_done := PackedByteArray()
	is_done.resize(slots.size())
	for si in slots.size():
		is_done[si] = 1 if done.get(si, false) else 0
	var total := 0.0
	for i in e_pos.size():
		var si := e_slot[i]
		var lp := 0.0 if is_done[si] == 1 else start[si * Dirt.CELLS + e_cell[i]] * (1.0 - e_w[i])
		var credit := 1.0 if lp <= Dirt.CLEAN else clampf(1.0 - (lp - Dirt.CLEAN) / CREDIT_SPAN, 0.0, 1.0)
		total += credit
		var nw := (basis * e_n[i]).normalized()
		var side := 0
		if nw.y > 0.6:
			side = 2
		elif nw.y < -0.6:
			side = 3
		elif toward != Vector2.ZERO and Vector2(nw.x, nw.z).dot(toward) < 0.0:
			side = 1
		side_n[side] += 1
		side_c[side] += credit
	var sides := {}
	var names := ["near", "far", "top", "under"]
	for k in 4:
		sides[names[k]] = float(side_c[k]) / side_n[k] if side_n[k] > 0 else -1.0
	var parts := []
	for si in slots.size():
		if part_n[si] > 0:
			parts.append({"slot": slots[si], "name": PartsDB.slot_name(slots[si]), "clean": float(cleans[si]), "item": items[si]})
	parts.sort_custom(func(x, y): return float(x["clean"]) < float(y["clean"]))
	_stats = {"clean": total / maxf(e_pos.size(), 1) if not bike_done else 1.0, "parts": parts, "sides": sides}
	return _stats


## How clean the part in slot index `si` is, for the readout.
func clean_of(si: int) -> float:
	if si < 0 or si >= slots.size():
		return 0.0
	for p in stats()["parts"]:
		if str(p["slot"]) == slots[si]:
			return float(p["clean"])
	return 1.0


## What's been washed since the last update, for the shed: {parts: {item: {cell: factor}} (each
## region's dirt times its factor), clean: [items now clean]}, or {} if nothing's changed.
func take_updates() -> Dictionary:
	var parts := {}
	for si in slots.size():
		var cells := {}
		for c in Dirt.CELLS:
			var k := si * Dirt.CELLS + c
			if count[k] <= 0.0:
				continue
			var share := wsum[k] / count[k]
			if share < sent[k] + 0.01 and not (share >= 0.999 and sent[k] < 0.999):
				continue
			cells[c] = 0.0 if share >= 0.999 else snappedf((1.0 - share) / maxf(1.0 - sent[k], 1e-4), 0.0001)
			sent[k] = share
		if not cells.is_empty():
			parts[items[si]] = cells
	var clean := to_call_clean.duplicate()
	to_call_clean.clear()
	if parts.is_empty() and clean.is_empty():
		return {}
	return {"parts": parts, "clean": clean}


## The shed's dirt has come in: what someone else has washed off (or the shed's called clean)
## shows here too.
func resync() -> void:
	if not ready:
		return
	var changed := false
	for si in slots.size():
		if not Shed.items.has(items[si]):
			continue
		var synced := Dirt.cells(Shed.items[items[si]], slots[si])
		for c in Dirt.CELLS:
			var k := si * Dirt.CELLS + c
			var share := wsum[k] / count[k] if count[k] > 0.0 else 0.0
			var mine := start[k] * (1.0 - share)
			if synced[c] < mine - 0.02:
				start[k] = synced[c] / maxf(1.0 - share, 0.02)
				changed = true
	if changed:
		_check_done()
		_stats_age = 1.0
		_show()


## Draws the wash as it is now on the bike (the parts in `only`, by slot index, or all of them):
## each region as dirty as it was, the mask showing what's come off.
func _show(only := {}) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	for si in slots.size():
		if not only.is_empty() and not only.has(si):
			continue
		var lv := PackedFloat32Array()
		lv.resize(Dirt.CELLS)
		var share := PackedFloat32Array()
		share.resize(Dirt.CELLS)
		for c in Dirt.CELLS:
			var k := si * Dirt.CELLS + c
			share[c] = wsum[k] / count[k] if count[k] > 0.0 else 0.0
			lv[c] = start[k] * (1.0 - share[c])
		layer.levels[slots[si]] = lv
		layer.washed_share[slots[si]] = share
		if not layer._mats.has(slots[si]) and DirtLayer._any(lv):
			layer._add_slot(slots[si])
		layer._push(slots[si])


## Whether the mask's still on the bike as drawn (it hasn't been redrawn since).
func attached() -> bool:
	return layer != null and is_instance_valid(layer) and model != null and is_instance_valid(model) and layer.get_parent() == model


## Done (or stepped back): the bike's drawn by the shed's own dirt again, keeping what the mask
## shows of the washing.
func finish() -> void:
	if layer != null and is_instance_valid(layer):
		layer.held_by_job = false
		layer.set_scan(false)
