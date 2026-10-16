class_name SprayJob
extends RefCounted
## One coat being sprayed on one part, by hand: the skill game behind the spray can and the
## spray gun. Like the sandblaster (BlastGame), the part's surface is covered in points
## (BikeModel.surface_points) and the coat itself is painted on the part as you go (SprayMarks),
## so you see the paint land, see the gaps you've missed and see it run where you've overdone it.
##
## How it lays on depends on how you hold it. The fan widens and thins with distance: in the
## sweet spot (NEAR to FAR away, wider with the tool's upgrades and Steady Hand) a steady pass
## lays an even coat; too close and it piles on in a tight spot and runs; too far and it lands
## dry and rough, and past OUT it doesn't reach at all. Sweep too fast and it goes on thin; linger
## and it runs. A point counts once you've seen it (the side facing you, not hidden behind
## something), so walking round a hung part brings its back into the job.
##
## The coats, in order: an optional grey primer ("primer"), the colour ("paint"; an engine enamel
## is a colour too) and an optional clear lacquer ("clear"). The finished coat goes to the host as
## a normal Shed.request (prime / paint / coat) with its quality and how much ran.

const CELL := 0.03           # the coverage map samples the surface this far apart
const MAX_POINTS := 5000
const FULL := 0.8            # coats for a full film (wet paint flows out to fill a thin patch)
const DONE := 0.9            # this much of what you can see covered and the coat's on
const AUTO_DONE := 0.995     # all of it: done there and then, without letting go
const FLOW := 0.9            # of the tool's stock rate: steady passes, half overlapping, make a good coat
const D_REF := 0.8           # the fan's stock width and flow are at this distance, metres
const NEAR := 0.5            # closer than this it piles on and runs
const FAR := 1.3             # further than this it starts to land dry
const DRY_SPAN := 0.55       # all of it dry this far past FAR
const OUT := 1.1             # and none of it reaches this far past FAR
const SLOW := 0.15           # sweeping slower than this (m/s) and it piles on
const FAST := 2.2            # faster than this and it goes on thin
const SEEN_BUDGET := 160     # points checked for line of sight a frame

var key := ""
var plan := {}               # the walker's plan for it (its "action" goes to the host)
var item := 0
var items: Array = []        # the parts whose surfaces count (an engine's coat goes on the lot)
var layer := "paint"         # "primer", "paint" (or an engine enamel) or "clear"
var model: BikeModel
var slots: Array = []
var marks: SprayMarks
var holder: Node3D           # what the part is drawn in (its hook swing, the floor, a bike)
var points := PackedVector3Array()
var normals := PackedVector3Array()
var vox := PackedInt32Array()
var seen := PackedByteArray()
var seen_n := 0
var live := false
var look := {}
## The tool: fan radius at D_REF, flow (coats a second at D_REF), falloff to the fan's edge,
## coats before it runs, and how much wider the sweet spot is (skill).
var radius := 0.1
var rate := 10.0
var falloff := 0.5
var runs := 4.0
var band := 1.0
## The jet this frame: {hit, at, normal, dist, zone ("close", "good", "far", "out"), radius, speed, pace}
var jet := {}
var last := {}               # stats() as of the last step
var cues: Array = []         # things to tell the player: {kind, text}
var _last_at := Vector3.INF
var _speed := 0.0
var _check_from := 0
var _told := {}
var _occupied := PackedByteArray()   # the mask's cubes with some of the part's surface in them


## Starts on `item_id` drawn on `part_model` in `part_slots`. False if there's nothing to spray.
func setup(item_id: int, job_key: String, walker_plan: Dictionary, part_model: BikeModel, part_slots: Array,
		coat_look: Dictionary, run_level: float) -> bool:
	item = item_id
	key = job_key
	plan = walker_plan
	model = part_model
	look = coat_look
	runs = run_level
	var a: Dictionary = plan.get("action", {})
	layer = layer_of(a)
	items = [item_id]
	if model == null or not is_instance_valid(model):
		return false
	var cell := CELL
	for attempt in 3:
		points = PackedVector3Array()
		normals = PackedVector3Array()
		slots = []
		for slot in part_slots:
			var surf := model.surface_points(slot, cell)
			if (surf[0] as PackedVector3Array).is_empty():
				continue
			slots.append(slot)
			points.append_array(surf[0])
			normals.append_array(surf[1])
		if points.size() <= MAX_POINTS:
			break
		cell *= 1.5
	if points.is_empty():
		return false
	marks = SprayMarks.new()
	marks.name = "SprayMarks"
	if not marks.setup(model, slots, runs, look):
		marks.free()
		marks = null
		return false
	model.add_child(marks)
	vox.resize(points.size())
	_index_points()
	seen.resize(points.size())
	seen.fill(0)
	seen_n = 0
	return true


## Finds each point's cube in the mask, and which cubes the part's surface passes through (sampled
## finer than the cubes, so the shell has no holes for a line of sight to slip through).
func _index_points() -> void:
	for i in points.size():
		vox[i] = marks.index_of(points[i])
	_occupied.resize(marks.coats.size())
	_occupied.fill(0)
	for slot in slots:
		var fine: PackedVector3Array = model.surface_points(slot, marks.voxel * 0.6)[0]
		for p in fine:
			var k := marks.index_of(p)
			if k >= 0:
				_occupied[k] = 1


## Whether nothing of the part itself is in the way between a point on it and `eye` (model
## space): a walk back along the line through the cubes its surface is in.
func _clear_to(p: Vector3, eye: Vector3) -> bool:
	var to := eye - p
	var length := to.length()
	if length < 0.01:
		return true
	var d := to / length
	var step := marks.voxel * 0.5
	var t := marks.voxel * 2.5
	var box := AABB(marks.origin, Vector3(marks.dims) * marks.voxel)
	while t < length:
		var q := p + d * t
		if not box.has_point(q):
			return true
		var i := marks.index_of(q)
		if i >= 0 and _occupied[i] != 0:
			return false
		t += step
	return true


## Which coat an action lays on.
static func layer_of(a: Dictionary) -> String:
	match str(a.get("a", "")):
		"prime":
			return "primer"
		"coat":
			return "paint" if Shed.COATS.get(str(a.get("coat", "")), {}).has("paint") else "clear"
	return "paint"


## How a coat looks going on over `it` (see SprayMarks.setup).
static func look_for(a: Dictionary, it: Dictionary) -> Dictionary:
	var lay := layer_of(a)
	var old: Color = it.get("color", Color(0.5, 0.5, 0.5))
	var bare := Shed.blast_full(it)
	# The old paint, flatted back for the new coat to key to: dull and matte (no gloss left on it),
	# so a missed bit shows against the wet new coat.
	var flatted := Color.from_hsv(old.h, old.s * 0.8, clampf(old.v * 0.8, 0.0, 1.0), 0.0 if bare else 0.85)
	match lay:
		"primer":
			return {"color": Shed.PRIMER_COLOR, "rough": 0.75, "metal": 0.0, "under": flatted, "under_rough": 0.95}
		"clear":
			# Without its lacquer the colour looks flat; with it, a wet clear gloss.
			var c := old.darkened(0.12)
			return {"color": old, "rough": 0.04, "metal": 0.0, "clear": true, "under": Color(c.r, c.g, c.b, 0.0 if bare else 0.35),
				"under_rough": 0.9}
	if a.get("cup", false):
		# Paint mixed in the mixing bay, from the gun's cup: what this coat leaves (PaintBay.cup_look).
		var wet := PaintBay.cup_look(it)
		if not wet.is_empty():
			var below := flatted
			if it.get("primer_top", false):
				below.a = 0.0
			return {"color": wet["color"], "rough": wet["rough"], "metal": wet["metal"], "under": below, "under_rough": 0.95}
	var col: Color = Shed.PAINTS[clampi(int(a.get("color", 0)), 0, Shed.PAINTS.size() - 1)]
	var finish := str(a.get("finish", "gloss"))
	if str(a.get("a", "")) == "coat":
		var spec: Dictionary = Shed.COATS.get(str(a.get("coat", "")), {})
		col = Shed.PAINTS[int(spec.get("paint", 0))]
		finish = str(spec.get("finish", "gloss"))
	var rough := 0.12
	var metal := 0.05
	match finish:
		"matte":
			rough = 0.85
			metal = 0.0
		"metallic":
			rough = 0.3
			metal = 0.75
			col = col.lightened(0.08)
		"chrome":
			rough = 0.1
			metal = 1.0
			col = col.lerp(Color(0.97, 0.97, 0.99), 0.7)
		"patina":
			rough = 0.75
			metal = 0.1
			col = Color.from_hsv(col.h, col.s * 0.55, col.v * 0.8)
	# On primer, the primer is what shows through (the part's drawn in it already).
	var under := flatted
	if it.get("primer_top", false):
		under.a = 0.0
	return {"color": col, "rough": rough, "metal": metal, "under": under, "under_rough": 0.95}


## Sets the tool: fan radius and flow at D_REF, falloff to the edge, and how much wider the
## sweet spot is.
func set_tool(fan_radius: float, flow: float, edge_falloff: float, sweet_mult := 1.0) -> void:
	radius = fan_radius
	rate = flow
	falloff = edge_falloff
	band = maxf(sweet_mult, 0.5)


## The sweet spot for this tool and skill: [near, far].
func sweet() -> Vector2:
	return Vector2(NEAR / band, FAR * band)


## How the fan lands at `dist`: {zone, radius, flow (coats a second at the middle), dry}.
func fan_at(dist: float) -> Dictionary:
	var s := sweet()
	var d := maxf(dist, 0.05)
	# The fan spreads with distance, and thins as it spreads; closer than the sweet spot it piles
	# on fast in a tight spot.
	var r := radius * clampf(d / D_REF, 0.6, 1.8)
	var flow := rate * FLOW * clampf(D_REF / d * (1.0 + 3.0 * maxf(0.0, s.x - d) / s.x), 0.3, 4.0)
	var dryness := smoothstep(s.y, s.y + DRY_SPAN, d)
	flow *= 1.0 - smoothstep(s.y + DRY_SPAN * 0.6, s.y + OUT, d)
	var zone := "good"
	if d < s.x:
		zone = "close"
	elif d > s.y + OUT:
		zone = "out"
	elif d > s.y:
		zone = "far"
	return {"zone": zone, "radius": r, "flow": flow, "dry": dryness}


## Marks the points you can see from `eye` as part of the job, a few at a time (all of them with
## `budget` < 0). `visible` is called as visible.call(world_point, world_normal) -> bool.
func look_over(eye: Vector3, visible: Callable, budget := SEEN_BUDGET) -> void:
	if model == null or not is_instance_valid(model) or points.is_empty():
		return
	var xf := model.global_transform
	var inv := xf.affine_inverse()
	var n := points.size()
	var count := n if budget < 0 else mini(budget, n)
	for k in count:
		var i := (_check_from + k) % n
		if seen[i] != 0:
			continue
		var p := xf * points[i]
		var nw := (xf.basis * normals[i]).normalized()
		# (A mesh's faces don't all wind the same way, so a normal may point in or out.)
		# Side on, the spray skims off: it counts once you've seen it more face on.
		if absf(nw.dot((eye - p).normalized())) < 0.2:
			continue
		if not _clear_to(points[i], inv * eye):
			continue
		if visible.call(p, nw):
			seen[i] = 1
			seen_n += 1
	_check_from = (_check_from + count) % n


## Where the line from `eye` along `dir` first meets the part's own surface (its fitted shapes are
## only boxes, so a ray can stop well short of a curved pipe): {at, normal, t (how far)}, or {}.
func surface_hit(eye: Vector3, dir: Vector3, width := 0.035) -> Dictionary:
	if model == null or not is_instance_valid(model) or points.is_empty():
		return {}
	var xf := model.global_transform
	var inv := xf.affine_inverse()
	var e: Vector3 = inv * eye
	var d: Vector3 = (inv.basis * dir).normalized()
	var best := INF
	var bi := -1
	for i in points.size():
		var v := points[i] - e
		var t := v.dot(d)
		if t <= 0.0 or t >= best:
			continue
		if (v - d * t).length_squared() < width * width:
			best = t
			bi = i
	if bi < 0:
		return {}
	var n := (xf.basis * normals[bi]).normalized()
	if n.dot(dir) > 0.0:
		n = -n   # towards you
	return {"at": xf * (e + d * best), "normal": n, "t": best * (xf.basis * d).length()}


## One frame of spraying from `eye` along `dir`, the spray meeting a surface at `at` (`hit`
## false: it meets nothing, and lands nowhere). Returns the cubes it coated. Not `firing`, it only
## works out where the fan would land, how far off and how fast it's going (aiming, trigger off).
func step(delta: float, eye: Vector3, dir: Vector3, hit: bool, at: Vector3, normal := Vector3.UP, firing := true) -> int:
	jet = {"hit": hit, "at": at, "normal": normal, "dist": eye.distance_to(at), "zone": "out", "radius": radius, "speed": _speed,
		"pace": "good"}
	if not hit or marks == null or not is_instance_valid(marks) or model == null or not is_instance_valid(model):
		_last_at = Vector3.INF
		_speed = 0.0
		jet["speed"] = 0.0
		return 0
	var fan := fan_at(eye.distance_to(at))
	# How fast the spray's going over the surface, smoothed.
	if _last_at != Vector3.INF and delta > 0.0:
		var moved := _last_at.distance_to(at)
		if moved < 0.4:
			_speed = lerpf(_speed, moved / delta, clampf(delta * 6.0, 0.0, 1.0))
	_last_at = at
	var pace := "good"
	if _speed < SLOW:
		pace = "slow"
	elif _speed > FAST:
		pace = "fast"
	jet["zone"] = fan["zone"]
	jet["radius"] = fan["radius"]
	jet["speed"] = _speed
	jet["pace"] = pace
	jet["dry"] = fan["dry"]
	if not firing:
		return 0
	var inv := model.global_transform.affine_inverse()
	var local_at: Vector3 = inv * at
	var along: Vector3 = (inv.basis * dir).normalized()
	var n := marks.paint(local_at, along, float(fan["radius"]), delta * float(fan["flow"]), float(fan["dry"]), falloff)
	last = stats()
	if n > 0:
		_note()
	return n


## Tells the player how it's going: runs and dry spray as they happen, and the coat being on.
func _note() -> void:
	var r := float(last["runs"])
	if r > 0.02 and (not _told.has("runs") or r > float(_told["runs"]) + 0.04):
		_told["runs"] = r
		cues.append({"kind": "runs", "text": "Runs! Keep it moving" if str(jet.get("zone", "")) != "close" else "Runs! Too close"})
	var dr := float(last["dry"])
	if dr > 0.04 and (not _told.has("dry") or dr > float(_told["dry"]) + 0.06):
		_told["dry"] = dr
		cues.append({"kind": "dry", "text": "Dry spray! Get closer"})
	if ready() and not _told.has("ready"):
		_told["ready"] = true
		cues.append({"kind": "ready", "text": "Coat on! Let go to finish, or fill the last gaps"})


## How the coat's going over what you've seen of the part, as fractions of it: {covered (a full
## film), thin (paint, but not enough), runs (over the run level), dry (a full film, but mostly
## landed dry), even (of what's been sprayed, how much is a good coat), seen (points in the job),
## coats (average)}.
func stats() -> Dictionary:
	var covered := 0
	var thin := 0
	var run := 0
	var dried := 0
	var good := 0
	var touched := 0
	var total := 0.0
	var coats := marks.coats if marks != null and is_instance_valid(marks) else PackedFloat32Array()
	var dry := marks.dry if marks != null and is_instance_valid(marks) else PackedFloat32Array()
	if coats.is_empty():
		return {"covered": 0.0, "thin": 0.0, "runs": 0.0, "dry": 0.0, "even": 1.0, "seen": 0, "coats": 0.0}
	for i in points.size():
		if seen[i] == 0:
			continue
		var c := coats[vox[i]] if vox[i] >= 0 else 0.0
		var d := dry[vox[i]] / maxf(c, 0.001) if vox[i] >= 0 and c > 0.0 else 0.0
		total += c
		if c > 0.05:
			touched += 1
		if c >= FULL:
			covered += 1
			if c < runs and d < 0.5:
				good += 1
			if d >= 0.5:
				dried += 1
		elif c > 0.05:
			thin += 1
		if c >= runs:
			run += 1
	var n := maxf(seen_n, 1)
	return {"covered": covered / n, "thin": thin / n, "runs": run / n, "dry": dried / n,
		"even": float(good) / touched if touched > 0 else 1.0, "seen": seen_n, "coats": total / n}


## How good the coat is, 0..1: how much of it is covered, less for runs and dry spray.
func quality(st := {}) -> float:
	if st.is_empty():
		st = stats()
	return clampf(float(st["covered"]) * (1.0 - float(st["runs"]) * 0.6 - float(st["dry"]) * 0.35), 0.0, 1.0)


## Whether enough is covered to call it a coat (letting go then finishes it).
func ready() -> bool:
	if seen_n == 0:
		return false
	var st := stats() if last.is_empty() else last
	return float(st["covered"]) >= DONE


## Whether it's all covered, so it's done without letting go.
func complete() -> bool:
	return not last.is_empty() and float(last["covered"]) >= AUTO_DONE


## The action to send the host for the finished coat.
func result() -> Dictionary:
	var st := stats()
	var done: Dictionary = (plan["action"] as Dictionary).duplicate()
	done["quality"] = snappedf(quality(st), 0.001)
	done["waste"] = snappedf(float(st["runs"]), 0.001)
	return done


## The mask's still on the part it was set up on (not redrawn since).
func attached() -> bool:
	return marks != null and is_instance_valid(marks) and model != null and is_instance_valid(model) and marks.get_parent() == model


## The part was redrawn mid-job: carry on on its new model, keeping what's been sprayed.
func rebind(part_model: BikeModel, part_slots: Array) -> bool:
	if part_model == null or not is_instance_valid(part_model):
		return false
	var old := marks if marks != null and is_instance_valid(marks) else null
	var fresh := SprayMarks.new()
	fresh.name = "SprayMarks"
	if not fresh.setup(part_model, part_slots, runs, look):
		fresh.free()
		return false
	part_model.add_child(fresh)
	if old != null:
		fresh.adopt(old)
		old.restore()
		old.queue_free()
	model = part_model
	marks = fresh
	_index_points()
	return true


## Done or given up: the wet coat flashes and is left to dry as the part is redrawn in it.
func finish(flash := true) -> void:
	if marks != null and is_instance_valid(marks):
		if flash:
			marks.flash_done()
		else:
			marks.restore()
			marks.queue_free()
	live = false


func set_scan(on: bool) -> void:
	if marks != null and is_instance_valid(marks):
		marks.set_scan(on)


## What the HUD shows for the coat's steps on this part: primer, colour and lacquer, each
## {name, state ("done", "now", "todo", "skip"), optional, q}.
func steps() -> Array:
	var it: Dictionary = Shed.items.get(item, {})
	var primed := it.has("primer")
	var painted: bool = it.has("paint_quality") and not it.get("primer_top", false)
	var lacquered: bool = Shed.coat_gloss(str(it.get("coat", ""))) > 0.0
	var out := []
	out.append({"name": "Primer", "optional": true, "q": float(it.get("primer", 0.0)),
		"state": "now" if layer == "primer" else ("done" if primed else ("skip" if painted or layer != "primer" else "todo"))})
	out.append({"name": "Colour", "optional": false, "q": float(it.get("paint_quality", 0.0)),
		"state": "now" if layer == "paint" else ("done" if painted else "todo")})
	out.append({"name": "Lacquer", "optional": true, "q": float(it.get("coat_q", 0.0)),
		"state": "now" if layer == "clear" else ("done" if lacquered else "todo")})
	return out
