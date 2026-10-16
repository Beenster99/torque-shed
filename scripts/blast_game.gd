class_name BlastGame
extends RefCounted
## Sandblasting an engine in a blast cabinet: a two-handed skill game. One hand turns the engine
## on the turntable (W A S D, the left stick, or hold right mouse and move it), the other
## points the nozzle and blasts (hold left mouse / RT) wherever you aim. Wherever the jet goes
## the surface turns to satin bare metal as you blast (BlastMarks), so the bits you've missed
## stay rusty; stay on one patch too long and it pits the metal. Each part's coverage is sent to
## the host a few times a second ("blast_tick"), which strips that much rust and muck off it
## there and then, so its numbers fall as you work; stepping back (F) settles it ("blast"), and
## what's bare is kept on each part (its "blast" mask, see BlastMarks.export_part), so it stays
## bare wherever the engine goes and comes back the same next time it's in a cabinet. The scan
## (X or D-pad up) lights up what's still to blast and lists it part by part and side by side.

const CELL := 0.03           # the coverage map samples each part's surface this far apart
const RADIUS := 0.07         # how wide the jet strips, metres
const RATE := 4.0            # coats a second at the middle of the jet (1 is bare metal)
const OVER := 4.5            # coats on one patch before it starts to pit
const DONE := 0.9            # this much of a part bare and it's done
const TURN_RATE := 1.8       # radians a second from the keys or stick
const TURN_MOUSE := 0.006    # radians per pixel of mouse with the turn button held
const PITCH_LIMIT := 1.25
const TICK := 0.25           # seconds between live updates to the host

var furniture := 0
var spot := ""
var engine := 0
var rot := Vector2.ZERO      # how the engine is turned on the turntable: yaw, pitch
var firing := false
var rate_mult := 1.0         # the cabinet's compressor
var radius_mult := 1.0
## item id -> {slot, name, points, normals, vox (each point's cube in the mask), cells}
var parts := {}
var marks: BlastMarks
var model: BikeModel
## The jet this frame: {at, normal, hit (on the engine), fresh (patches just stripped), rust}
var jet := {}
var _done_parts := {}
var _engine_done := false
var _sent := {}              # what the host was last told: item id -> [covered, over]
var scanning := false        # the scan's on: the engine glows where there's rust still to blast

## The sides of the engine the scan reports on, by the way a patch faces (the bike's front is -z).
const SIDES := [["Top", Vector3.UP], ["Underneath", Vector3.DOWN], ["Front", Vector3.FORWARD], ["Back", Vector3.BACK],
	["Left side", Vector3.LEFT], ["Right side", Vector3.RIGHT]]


## Starts on the engine in a blast cabinet's place. False if it isn't drawn yet.
func start(furniture_id: int, spot_name: String, engine_model: BikeModel) -> bool:
	furniture = furniture_id
	spot = spot_name
	engine = Shed.item_at_spot(spot)
	model = engine_model
	if engine == 0 or model == null or not Shed.is_engine(engine):
		return false
	var m := Equipment.get_model(str(Shed.furniture.get(furniture, {}).get("model", "")))
	rate_mult = float(m.get("rate", 1.0))
	radius_mult = float(m.get("jet", 1.0))
	var slots: Array = ["engine"]
	slots.append_array(PartsDB.ENGINE_SLOTS)
	var used := []
	for slot in slots:
		var id := engine if slot == "engine" else Shed.engine_item(engine, slot)
		if id == 0:
			continue
		var surf := model.surface_points(slot, CELL)
		var pts: PackedVector3Array = surf[0]
		if pts.is_empty():
			continue
		var cells := PackedFloat32Array()
		cells.resize(pts.size())
		parts[id] = {"slot": slot, "name": PartsDB.slot_name(slot), "points": pts, "normals": surf[1], "cells": cells}
		used.append(slot)
	if parts.is_empty():
		return false
	# The engine as it was drawn (what's kept of earlier blasting) gives way to the live mask,
	# which starts from that same kept blasting.
	for old in ["BlastSaved", "BlastMarks"]:
		var saved := model.get_node_or_null(old)
		if saved:
			saved.free()
	marks = BlastMarks.new()
	marks.name = "BlastMarks"
	marks.setup(model, used, OVER)
	model.add_child(marks)
	for id in parts:
		var it: Dictionary = Shed.items.get(int(id), {})
		if it.has("blast"):
			marks.import_data(it["blast"])
		var full := Shed.blast_full(it)
		marks.set_look(str(parts[id]["slot"]), 1.0 if full else 0.0)
	for id in parts:
		var pts: PackedVector3Array = parts[id]["points"]
		var vox := PackedInt32Array()
		vox.resize(pts.size())
		var cells: PackedFloat32Array = parts[id]["cells"]
		for i in pts.size():
			vox[i] = marks.index_of(pts[i])
			if vox[i] >= 0:
				cells[i] = marks.coats[vox[i]]
		parts[id]["vox"] = vox
		parts[id]["cells"] = cells
		# Parts already done don't cheer again.
		if float(stats(int(id))["covered"]) >= DONE:
			_done_parts[id] = true
	_engine_done = all_done()
	_sent = results()
	return true


## Turns the engine on the turntable: x spins it round, y tips it over.
func turn(by: Vector2) -> void:
	rot.x = wrapf(rot.x + by.x, -PI, PI)
	rot.y = clampf(rot.y + by.y, -PITCH_LIMIT, PITCH_LIMIT)


## How the engine sits on the turntable for `r` (yaw, pitch).
static func pivot_basis(r: Vector2) -> Basis:
	return Basis(Vector3.UP, r.x) * Basis(Vector3.RIGHT, r.y)


## One frame of blasting along the ray from `from` in `dir`. `hit` is where the ray met the
## engine ({} for a miss: the jet hits the cabinet).
func step(delta: float, blasting: bool, from: Vector3, dir: Vector3, hit: Dictionary) -> void:
	firing = blasting
	jet = {}
	if not blasting:
		return
	if hit.is_empty() or model == null or not is_instance_valid(model) or marks == null:
		jet = {"at": from + dir * 0.9, "normal": -dir, "hit": false, "fresh": 0, "rust": 0.0}
		return
	var at: Vector3 = hit["position"]
	var normal: Vector3 = hit.get("normal", -dir)
	var inv := model.global_transform.affine_inverse()
	var local_at: Vector3 = inv * at
	var along: Vector3 = (inv.basis * dir).normalized()
	# The jet bites hardest head on.
	var facing := clampf(-normal.dot(dir), 0.0, 1.0)
	marks.paint(local_at, along, RADIUS * radius_mult, delta * RATE * rate_mult * (0.4 + 0.6 * facing))
	var fresh := 0
	var rust := 0.0
	var reach := RADIUS * radius_mult + 0.1
	for id in parts:
		var p: Dictionary = parts[id]
		var points: PackedVector3Array = p["points"]
		var vox: PackedInt32Array = p["vox"]
		var cells: PackedFloat32Array = p["cells"]
		var touched := false
		for i in points.size():
			if vox[i] < 0 or absf(points[i].x - local_at.x) > reach or absf(points[i].y - local_at.y) > reach \
					or absf(points[i].z - local_at.z) > reach:
				continue
			var now := marks.coats[vox[i]]
			if now == cells[i]:
				continue
			if cells[i] < 1.0 and now >= 1.0:
				fresh += 1
			cells[i] = now
			touched = true
		if touched:
			p["cells"] = cells
			if was_rusty(int(id)):
				rust = maxf(rust, float(Shed.items[int(id)]["rust"]) + float(Shed.items[int(id)]["dirt"]) * 0.5)
	jet = {"at": at, "normal": normal, "hit": true, "fresh": fresh, "rust": clampf(rust, 0.0, 1.0)}


func was_rusty(id: int) -> bool:
	return Shed.items.has(id) and (float(Shed.items[id]["rust"]) > 0.02 or float(Shed.items[id]["dirt"]) > 0.02)


## How far a part has got: {covered, over} as fractions of its patches.
func stats(id: int) -> Dictionary:
	var p: Dictionary = parts.get(id, {})
	if p.is_empty():
		return {"covered": 0.0, "over": 0.0}
	var cells: PackedFloat32Array = p["cells"]
	var covered := 0
	var over := 0
	for c in cells:
		if c >= 1.0:
			covered += 1
		if c >= OVER:
			over += 1
	return {"covered": float(covered) / cells.size(), "over": float(over) / cells.size()}


## Bare metal over the whole engine, 0..1, every patch counting the same.
func total() -> float:
	var n := 0
	var bare := 0
	for id in parts:
		var cells: PackedFloat32Array = parts[id]["cells"]
		n += cells.size()
		for c in cells:
			if c >= 1.0:
				bare += 1
	return float(bare) / maxf(n, 1)


## Parts that have just reached DONE, once each, for a ding, a flash and a word on the HUD.
func newly_done() -> Array:
	var out := []
	for id in parts:
		if not _done_parts.has(id) and float(stats(int(id))["covered"]) >= DONE:
			_done_parts[id] = true
			out.append(id)
			if marks:
				marks.flash_part(str(parts[id]["slot"]))
	return out


## True once, the moment every part is done.
func engine_just_done() -> bool:
	if _engine_done or not all_done():
		return false
	_engine_done = true
	return true


func all_done() -> bool:
	for id in parts:
		if float(stats(int(id))["covered"]) < DONE:
			return false
	return true


## What gets sent to the host: item id -> [covered, over].
func results() -> Dictionary:
	var out := {}
	for id in parts:
		var st := stats(int(id))
		out[int(id)] = [snappedf(float(st["covered"]), 0.001), snappedf(float(st["over"]), 0.001)]
	return out


## The parts that have come on since the host was last told, for a live update ({} if none).
func changed_results() -> Dictionary:
	var out := {}
	var now := results()
	for id in now:
		var was: Array = _sent.get(id, [0.0, 0.0])
		var r: Array = now[id]
		if absf(float(r[0]) - float(was[0])) >= 0.005 or absf(float(r[1]) - float(was[1])) >= 0.005:
			out[id] = r
			_sent[id] = r
	return out


## Lines for the HUD: each part with how much of it is bare, and its condition now.
func lines() -> Array:
	var out := []
	for id in parts:
		var st := stats(int(id))
		var it: Dictionary = Shed.items.get(int(id), {})
		out.append({"id": int(id), "name": str(parts[id]["name"]), "covered": float(st["covered"]), "over": float(st["over"]),
			"rust": float(it.get("rust", 0.0)), "dirt": float(it.get("dirt", 0.0)), "wear": float(it.get("wear", 0.0)),
			"health": BikeBuild.part_health(Shed.condition_of(it)) if not it.is_empty() else 0.0,
			"done": float(st["covered"]) >= DONE})
	return out


## Stepping back: the bare metal stays on the engine as it is (the host keeps it on each part and
## the engine is redrawn from that), only the scan goes off.
func clear() -> void:
	if is_instance_valid(marks):
		marks.set_scan(false)
	scanning = false
	marks = null


## What's bare on each part, to keep on it: item id -> {o, d, v (the mask), c (bare), p (pitted)}.
func masks() -> Dictionary:
	var out := {}
	if marks == null or not is_instance_valid(marks):
		return out
	for id in parts:
		var data := marks.export_part(parts[id]["vox"])
		if data.is_empty():
			continue
		var st := stats(int(id))
		data["c"] = snappedf(float(st["covered"]), 0.001)
		data["p"] = snappedf(float(st["over"]), 0.001)
		out[int(id)] = data
	return out


## Turns the scan on or off.
func set_scan(on: bool) -> void:
	scanning = on
	if marks and is_instance_valid(marks):
		marks.set_scan(on)


## What the scan shows: how much is still to blast over the whole engine ("left"), on each part
## ("parts": [{name, left}]) and on each side of it ("sides": [{name, left}], by which way each
## patch faces), as fractions of their patches.
func scan() -> Dictionary:
	var side_n := []
	var side_left := []
	for s in SIDES:
		side_n.append(0)
		side_left.append(0)
	var part_rows := []
	var n := 0
	var left := 0
	for id in parts:
		var cells: PackedFloat32Array = parts[id]["cells"]
		var normals: PackedVector3Array = parts[id]["normals"]
		var p_left := 0
		for i in cells.size():
			var still := cells[i] < 1.0
			if still:
				p_left += 1
			var best := 0
			var best_d := -2.0
			for k in SIDES.size():
				var d := normals[i].dot(SIDES[k][1])
				if d > best_d:
					best_d = d
					best = k
			side_n[best] += 1
			if still:
				side_left[best] += 1
		n += cells.size()
		left += p_left
		part_rows.append({"id": int(id), "name": str(parts[id]["name"]), "left": float(p_left) / maxf(cells.size(), 1)})
	var sides := []
	for k in SIDES.size():
		if int(side_n[k]) > 0:
			sides.append({"name": str(SIDES[k][0]), "left": float(side_left[k]) / float(side_n[k])})
	return {"left": float(left) / maxf(n, 1), "parts": part_rows, "sides": sides}
