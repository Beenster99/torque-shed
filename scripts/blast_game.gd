class_name BlastGame
extends RefCounted
## Sandblasting an engine in a blast cabinet: a two-handed skill game. One hand turns the engine
## on the turntable (W A S D, the left stick, or hold right mouse and move it), the other
## points the nozzle and blasts (hold left mouse / RT) wherever you aim. Every patch of the
## engine and its ancillaries the jet hits is stripped back to bare metal (BlastMarks); stay
## on one patch too long and it pits the metal. When you step back (F), the host takes the
## coverage of each part and strips that much rust and muck off it (Shed "blast").

const CELL := 0.035          # the engine's surface is tracked in patches this big
const RADIUS := 0.07         # how wide the jet strips, metres
const RATE := 4.0            # coats a second at the middle of the jet (1 is bare metal)
const OVER := 4.5            # coats on one patch before it starts to pit
const DONE := 0.9            # this much of a part bare and it's done
const TURN_RATE := 1.8       # radians a second from the keys or stick
const TURN_MOUSE := 0.006    # radians per pixel of mouse with the turn button held
const PITCH_LIMIT := 1.25

var furniture := 0
var spot := ""
var engine := 0
var rot := Vector2.ZERO      # how the engine is turned on the turntable: yaw, pitch
var firing := false
var rate_mult := 1.0         # the cabinet's compressor
var radius_mult := 1.0
## item id -> {slot, name, start (first patch in the marks), points, normals, cells}
var parts := {}
var marks: BlastMarks
var model: BikeModel
## The jet this frame: {at, normal, hit (on the engine), fresh (patches just stripped), rust}
var jet := {}
var _done_parts := {}


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
	var all_points := PackedVector3Array()
	var all_normals := PackedVector3Array()
	var slots: Array = ["engine"]
	slots.append_array(PartsDB.ENGINE_SLOTS)
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
		parts[id] = {"slot": slot, "name": PartsDB.slot_name(slot), "start": all_points.size(), "points": pts,
			"normals": surf[1], "cells": cells}
		all_points.append_array(pts)
		all_normals.append_array(surf[1])
	if parts.is_empty():
		return false
	marks = BlastMarks.new()
	marks.name = "BlastMarks"
	marks.setup(all_points, all_normals, CELL, OVER)
	model.add_child(marks)
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
	if hit.is_empty() or model == null or not is_instance_valid(model):
		jet = {"at": from + dir * 0.9, "normal": -dir, "hit": false, "fresh": 0, "rust": 0.0}
		return
	var at: Vector3 = hit["position"]
	var inv := model.global_transform.affine_inverse()
	var local_at: Vector3 = inv * at
	var along: Vector3 = (inv.basis * dir).normalized()
	var reach := RADIUS * radius_mult
	var rate := RATE * rate_mult
	var fresh := 0
	var rust := 0.0
	for id in parts:
		var p: Dictionary = parts[id]
		var points: PackedVector3Array = p["points"]
		var normals: PackedVector3Array = p["normals"]
		var cells: PackedFloat32Array = p["cells"]
		var start := int(p["start"])
		var touched := false
		for i in points.size():
			var v := points[i] - local_at
			var depth := v.dot(along)
			if depth < -0.05 or depth > 0.09:
				continue
			var d := (v - along * depth).length()
			if d >= reach:
				continue
			# The jet only bites on faces turned towards it, and hardest head on.
			var facing := -normals[i].dot(along)
			if facing < 0.15:
				continue
			var was := cells[i]
			cells[i] = was + delta * rate * (1.0 - 0.6 * d / reach) * (0.4 + 0.6 * facing)
			if was < 1.0 and cells[i] >= 1.0:
				fresh += 1
			marks.set_coats(start + i, cells[i])
			touched = true
		if touched:
			p["cells"] = cells
			if was_rusty(int(id)):
				rust = maxf(rust, float(Shed.items[int(id)]["rust"]) + float(Shed.items[int(id)]["dirt"]) * 0.5)
	jet = {"at": at, "normal": hit.get("normal", -dir), "hit": true, "fresh": fresh, "rust": clampf(rust, 0.0, 1.0)}


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


## Parts that have just reached DONE, once each, for a ting and a word on the HUD.
func newly_done() -> Array:
	var out := []
	for id in parts:
		if not _done_parts.has(id) and float(stats(int(id))["covered"]) >= DONE:
			_done_parts[id] = true
			out.append(id)
	return out


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


## Lines for the HUD: each part with how much of it is bare.
func lines() -> Array:
	var out := []
	for id in parts:
		var st := stats(int(id))
		out.append({"name": str(parts[id]["name"]), "covered": float(st["covered"]), "over": float(st["over"]),
			"rust": float(Shed.items.get(int(id), {}).get("rust", 0.0))})
	return out


## Takes the bare-metal patches off the engine (the job's done or abandoned).
func clear() -> void:
	if is_instance_valid(marks):
		marks.queue_free()
	marks = null
