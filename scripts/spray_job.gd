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
## and it runs. Paint only lands on the surfaces facing the gun (see SprayMarks), so the job is
## all of the part's outside a spray could get to (not the faces down on the floor or hidden
## inside it): one side of a tank is only about half of it, and you have to walk round to do the
## far side and get down to spray underneath.
##
## The coats, in order: an optional grey primer ("primer"), the colour ("paint"; an engine enamel
## is a colour too) and an optional clear lacquer ("clear"). The finished coat goes to the host as
## a normal Shed.request (prime / paint / coat) with its quality and how much ran.

const CELL := 0.03           # the coverage map samples the surface this far apart
const MAX_POINTS := 5000
const FULL := 0.8            # coats for a full film (wet paint flows out to fill a thin patch)
const DONE := 0.9            # this much of it covered and the coat's on
const AUTO_DONE := 0.995     # all of it: done there and then, without letting go
const FLOW := 0.9            # of the tool's stock rate: steady passes, half overlapping, make a good coat
const D_REF := 0.8           # the fan's stock width and flow are at this distance, metres
const NEAR := 0.5            # closer than this it piles on and runs
const FAR := 1.3             # further than this it starts to land dry
const DRY_SPAN := 0.55       # all of it dry this far past FAR
const OUT := 1.1             # and none of it reaches this far past FAR
const SLOW := 0.15           # sweeping slower than this (m/s) and it piles on
const FAST := 2.2            # faster than this and it goes on thin
const WAY_OUT := 0.6         # metres clear of the part itself, out from a point, and a spray can get to it
## The ways out from a point that are tried to see if a spray could get to it (all 26 round a cube).
static var _ways: Array[Vector3] = []

var key := ""
var plan := {}               # the walker's plan for it (its "action" goes to the host)
var item := 0
var items: Array = []        # the parts whose surfaces count (an engine's coat goes on the lot)
var layer := "paint"         # "primer", "paint" (or an engine enamel) or "clear"
var model: BikeModel
var slots: Array = []
var marks: SprayMarks
var holder: Node3D           # what the part is drawn in (its hook swing, the floor, a bike)
## The job's points on the part's outside (model space), each with the way its surface faces
## out; a thin sheet (open both sides) has a point for each side.
var points := PackedVector3Array()
var normals := PackedVector3Array()
var vox := PackedInt32Array()
var seen_n := 0              # how many points the job has
var dropped := 0             # points of the part no spray could reach (inside it, down on the floor)
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
var _eye := Vector3.INF      # where the last spray came from
var _mid := Vector3.INF
var _speed := 0.0
var _told := {}
var _occupied := PackedByteArray()   # the mask's cubes with some of the part's surface in them


## Starts on `item_id` drawn on `part_model` in `part_slots`. False if there's nothing to spray.
## `open_way`, if given, says whether anything else (the floor, the bench, the rest of a bike) is
## in the way of spraying a point of it from a direction: open_way.call(world_point, world_dir) -> bool.
func setup(item_id: int, job_key: String, walker_plan: Dictionary, part_model: BikeModel, part_slots: Array,
		coat_look: Dictionary, run_level: float, open_way := Callable()) -> bool:
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
	_index_points()
	_expose(open_way)
	if points.is_empty():
		marks.restore()
		marks.queue_free()
		marks = null
		return false
	return true


## Finds each point's cube in the mask, and which cubes the part's surface passes through (sampled
## finer than the cubes, so the shell has no holes for a line of sight to slip through).
func _index_points() -> void:
	vox.resize(points.size())
	for i in points.size():
		vox[i] = marks.index_of(points[i])
	_occupied.resize(marks.dry.size())
	_occupied.fill(0)
	for slot in slots:
		var fine: PackedVector3Array = model.surface_points(slot, marks.voxel * 0.6)[0]
		for p in fine:
			var k := marks.index_of(p)
			if k >= 0:
				_occupied[k] = 1


## Whether nothing of the part itself is in the way going out from a point on it along `d` (model
## space, unit): a walk out along the line through the cubes its surface is in, to the mask's edge
## (or WAY_OUT, past which there's room for a spray to come in at it).
func _clear_way(p: Vector3, d: Vector3) -> bool:
	var step := marks.voxel * 0.6
	var t := marks.voxel * 2.5
	var box := AABB(marks.origin, Vector3(marks.dims) * marks.voxel)
	while t < WAY_OUT:
		var q := p + d * t
		if not box.has_point(q):
			return true
		var i := marks.index_of(q)
		if i >= 0 and _occupied[i] != 0:
			return false
		t += step
	return true


static func ways() -> Array[Vector3]:
	if _ways.is_empty():
		for x in [-1, 0, 1]:
			for y in [-1, 0, 1]:
				for z in [-1, 0, 1]:
					if x != 0 or y != 0 or z != 0:
						_ways.append(Vector3(x, y, z).normalized())
	return _ways


## Whether a spray could get to a point from the side `n` faces (model space, unit): straight out
## along it, or failing that from round about it, with nothing of the part or (`open_way`) of
## anything else in the way.
func _open_side(p: Vector3, n: Vector3, xf: Transform3D, open_way: Callable, look_round := true) -> bool:
	var tries: Array[Vector3] = [n]
	if look_round:
		for w in ways():
			if w.dot(n) >= 0.45:
				tries.append(w)
	var world_tries := 0
	for d in tries:
		if not _clear_way(p, d):
			continue
		if not open_way.is_valid():
			return true
		if open_way.call(xf * p, (xf.basis * d).normalized()):
			return true
		world_tries += 1
		if world_tries >= 3:
			return false
	return false


## Works out which of the part's surface a spray could get to, and which way each bit of it faces
## out (a mesh's faces don't all wind the same way, so a normal may point in or out): the job is
## what can be reached. A thin sheet open both sides is two points, one for each side, and the
## faces down on the floor or shut inside the part are left out.
func _expose(open_way: Callable) -> void:
	var xf := model.global_transform
	var out_p := PackedVector3Array()
	var out_n := PackedVector3Array()
	var count := points.size()
	for i in count:
		var p := points[i]
		var n := normals[i].normalized()
		if n == Vector3.ZERO:
			continue
		var front := _open_side(p, n, xf, open_way)
		# Straight through the other way first: inside a closed shell it meets the far wall.
		var back := _open_side(p, -n, xf, open_way, not front)
		if front:
			out_p.append(p)
			out_n.append(n)
		if back:
			out_p.append(p)
			out_n.append(-n)
	dropped = count - mini(count, out_p.size())
	points = out_p
	normals = out_n
	seen_n = points.size()
	vox.resize(points.size())
	for i in points.size():
		vox[i] = marks.index_of(points[i])


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
	# Masking tape on it stays in sight until it's sprayed over: the part's drawn as it is.
	var taped: bool = it.get("tape") is Dictionary and not it.get("primer_top", false)
	var flatted := Color.from_hsv(old.h, old.s * 0.8, clampf(old.v * 0.8, 0.0, 1.0), 0.0 if bare or taped else 0.85)
	match lay:
		"primer":
			return {"color": Shed.PRIMER_COLOR, "rough": 0.75, "metal": 0.0, "under": flatted, "under_rough": 0.95}
		"clear":
			return _clear_look(it, 0.04)
	if a.get("cup", false):
		# Paint mixed in the mixing bay, from the gun's cup: what this coat leaves (PaintBay.cup_look).
		var wet := PaintBay.cup_look(it)
		var cup: Dictionary = PaintBay.cup_of(Shed.me())
		if cup.get("mix") is Dictionary and str(cup["mix"].get("effect", "")) == "lacquer" and not wet.is_empty():
			# Lacquer from the cup is clear: the colours under it (stripes, flake) stay as they are.
			return _clear_look(it, float(wet["rough"]))
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


## Clear lacquer going on over `it`: a wet gloss over the colour, which stays as it is (stripes,
## two-tones and effects too). Missed bits of a plain colour look a little flat without it.
static func _clear_look(it: Dictionary, rough: float) -> Dictionary:
	var old: Color = it.get("color", Color(0.5, 0.5, 0.5))
	var c := old.darkened(0.12)
	var plain: bool = not Shed.blast_full(it) and not (it.get("mix") is Dictionary) and not (it.get("mask") is Dictionary) \
		and not (it.get("tape") is Dictionary)
	return {"color": old, "rough": rough, "metal": 0.0, "clear": true, "under": Color(c.r, c.g, c.b, 0.35 if plain else 0.0),
		"under_rough": 0.9, "keep": not plain}


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
	_eye = eye
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


## How the coat's going over all of the part a spray can get to, as fractions of it: {covered (a
## full film), thin (paint, but not enough), runs (over the run level), dry (a full film, but
## mostly landed dry), even (of what's been sprayed, how much is a good coat), seen (points in the
## job), coats (average), sides (how much is covered on the side facing you, the far side, the
## top and underneath, -1 for a side with none of the part on it: {near, far, top, under}, as of
## where you last sprayed from)}.
func stats() -> Dictionary:
	var covered := 0
	var thin := 0
	var run := 0
	var dried := 0
	var good := 0
	var touched := 0
	var total := 0.0
	if marks == null or not is_instance_valid(marks) or marks.coats.is_empty() or points.is_empty():
		return {"covered": 0.0, "thin": 0.0, "runs": 0.0, "dry": 0.0, "even": 1.0, "seen": 0, "coats": 0.0,
			"sides": {"near": -1.0, "far": -1.0, "top": -1.0, "under": -1.0}}
	# Which side of the part each point's on, seen from where you are.
	var basis := model.global_transform.basis if model != null and is_instance_valid(model) else Basis()
	var toward := Vector2.ZERO
	if _eye != Vector3.INF and model != null and is_instance_valid(model):
		var t := _eye - model.global_transform * _middle()
		toward = Vector2(t.x, t.z).normalized()
	var side_n := {"near": 0, "far": 0, "top": 0, "under": 0}
	var side_c := {"near": 0, "far": 0, "top": 0, "under": 0}
	for i in points.size():
		var c := marks.coats_facing(vox[i], normals[i])
		var d := marks.dry_of(vox[i]) if c > 0.0 else 0.0
		total += c
		if c > 0.05:
			touched += 1
		var nw := (basis * normals[i]).normalized()
		var side := "near"
		if nw.y > 0.6:
			side = "top"
		elif nw.y < -0.6:
			side = "under"
		elif toward != Vector2.ZERO and Vector2(nw.x, nw.z).dot(toward) < 0.0:
			side = "far"
		side_n[side] += 1
		if c >= FULL:
			covered += 1
			side_c[side] += 1
			if c < runs and d < 0.5:
				good += 1
			if d >= 0.5:
				dried += 1
		elif c > 0.05:
			thin += 1
		if c >= runs:
			run += 1
	var n := maxf(seen_n, 1)
	var sides := {}
	for k in side_n:
		sides[k] = float(side_c[k]) / side_n[k] if side_n[k] > 0 else -1.0
	return {"covered": covered / n, "thin": thin / n, "runs": run / n, "dry": dried / n,
		"even": float(good) / touched if touched > 0 else 1.0, "seen": seen_n, "coats": total / n, "sides": sides}


## The middle of the job's points (model space).
func _middle() -> Vector3:
	if _mid == Vector3.INF:
		var sum := Vector3.ZERO
		for p in points:
			sum += p
		_mid = sum / maxf(points.size(), 1)
	return _mid


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
