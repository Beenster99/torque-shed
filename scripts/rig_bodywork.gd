class_name RigBodywork
extends RefCounted
## Rig built look, bodywork track (H3): the tank, the seat and the tail cowl fitted to the lines
## the bike rig hands over (BikeModel.rig; the lines agreement, section 3), instead of placed on
## their own. The Blender parts (blender/parts/tank, saddle, tail) carry shape keys; this works
## out each key's weight for the bike and the warp that bends the part onto its lines, and
## BlenderParts.morphed draws it. Nothing here moves the rig's lines: it only fits to them.
##
## The tank's tunnel sits on the rig's tank floor from its nose to its rear, its cheeks reaching
## round the head stock, its top no higher than the rig allows and its knee recesses where the
## rider's knees are. The seat's pan sits on the seat rails, its foam bringing its top to the
## published seat height at the hip point, its nose matched to the tank's rear. The tail cowl
## carries on from the seat's end along the rails to the rig's tail.

const TANK_KNEE := {"sport": 1.0, "race": 1.0, "wedge": 1.0, "streetfighter": 1.0, "gt": 0.8, "adv": 0.8, "touring": 0.7,
	"cafe": 0.8, "enduro": 0.5, "teardrop": 0.35}   # how deep each shape's knee recesses go (none on the rest)
const KNEE_AT := [0.58, 0.84]    # where the tank's two knee keys are centred, share of its length
const BASE_TUNNEL_HALF := 0.035  # m: the glb's own tunnel half width and depth below the roof
const BASE_TUNNEL_DEEP := 0.035
const TUNNEL_SINK := 0.08        # m the tank sinks round the spine at tunnel_height 1
const TUNNEL_SPARE := 0.006      # m kept between the spine and the tunnel's walls
const SEAT_NOSE_W := 0.06        # m each key moves at weight 1 (see the Blender scripts)
const SEAT_NOSE_H := 0.04
const SEAT_FOAM := 0.04
const COWL_FRONT_W := 0.05
const COWL_FRONT_H := 0.04
const COWL_KICK := 0.08


## Whether `rig` has what the bodywork fits to.
static func has_rig(rig: Dictionary) -> bool:
	return rig.has("tank_floor") and rig.has("tank_nose") and rig.has("tank_rear") and (rig["tank_floor"] as PackedVector3Array).size() >= 2


## The point on `line` (a polyline running back along +Z) at `z`, carried straight on past its
## ends; and its direction there: [point, unit direction].
static func line_at(line: PackedVector3Array, z: float) -> Array:
	var n := line.size()
	var k := 1
	while k < n - 1 and line[k].z < z:
		k += 1
	var a := line[k - 1]
	var b := line[k]
	var d := b - a
	if absf(d.z) < 0.00001:
		return [a, Vector3.BACK]
	var f := (z - a.z) / d.z
	if k > 1 and k < n - 1:
		f = clampf(f, 0.0, 1.0)
	return [a + d * f, d.normalized()]


## Up from a line running in the bike's YZ plane along `dir`: square to it, towards +Y.
static func up_from(dir: Vector3) -> Vector3:
	var up := Vector3(0.0, dir.z, -dir.y)
	return up.normalized() if up.y >= 0.0 else -up.normalized()


# ---------------------------------------------------------------------------- tank

## Everything the tank needs: {"weights", "warp" (Callable: glb point -> model point), "len",
## "kx", "ky"} for a tank of `shape` (TANK_SHAPES's), `size` (capacity) and look `sc`.
static func tank_fit(rig: Dictionary, shape_name: String, shape: Dictionary, size: float, sc: Vector3) -> Dictionary:
	var floor_line: PackedVector3Array = rig["tank_floor"]
	var nose: Vector3 = rig["tank_nose"]
	var rear: Vector3 = rig["tank_rear"]
	var length := maxf(rear.z - nose.z, 0.2)
	var kx := size * sc.y
	var ky := size * sc.z
	var half_w := float(rig.get("tunnel_half_w", 0.02))
	# The flanks come down past the bottom of the spine: the tank sinks round it, its tunnel taller.
	var sink := maxf(2.0 * half_w + 0.012 - BASE_TUNNEL_DEEP * ky, 0.0)
	# Line 2: the tank's top no higher than the rig allows. It sinks further round the spine (as a
	# fat bob does), up to half its height, and what's left over is squashed.
	if rig.has("tank_top_max"):
		var top_max := float(rig["tank_top_max"])
		var over := 0.0
		var tallest := 0.0
		for k in shape["keys"]:
			var at: Vector3 = line_at(floor_line, nose.z + float(k[0]) * length)[0]
			var rise := (float(k[2]) + float(k[3])) * ky
			tallest = maxf(tallest, rise)
			over = maxf(over, at.y + rise - top_max)
		sink = maxf(sink, minf(over, tallest * 0.5))
		var left := over - sink
		if left > 0.0 and tallest > 0.01:
			var squash := maxf((tallest - left) / tallest, 0.6)
			ky *= squash
			sink *= squash
	var weights := {
		"tunnel_width": clampf((half_w + TUNNEL_SPARE - BASE_TUNNEL_HALF) / 0.05 / maxf(kx, 0.5), -0.3, 1.5),
		"tunnel_height": sink / (TUNNEL_SINK * ky),
		"tunnel_length": 1.0,
		"nose_reach": 0.6,
	}
	var depth := float(TANK_KNEE.get(shape_name, 0.0))
	if depth > 0.0 and rig.has("knee_r"):
		var t := clampf(((rig["knee_r"] as Vector3).z - nose.z) / length, KNEE_AT[0], KNEE_AT[1])
		var f := (t - KNEE_AT[0]) / (KNEE_AT[1] - KNEE_AT[0])
		weights["knee_fore"] = depth * (1.0 - f)
		weights["knee_aft"] = depth * f
	var warp := func(p: Vector3) -> Vector3:
		var on: Array = line_at(floor_line, nose.z + p.z * length)
		return (on[0] as Vector3) + up_from(on[1]) * (p.y * ky) + Vector3(p.x * kx, 0.0, 0.0)
	return {"weights": weights, "warp": warp, "len": length, "kx": kx, "ky": ky, "sink": sink}


## The tank's loft sections as the rest of the bike reads them (BikeModel._tank_secs: the filler
## cap, badges, stripes, the fairing's and the kit's lines), from its shape fitted as `fit`.
static func tank_secs(rig: Dictionary, shape: Dictionary, fit: Dictionary, steps: int) -> Array:
	var floor_line: PackedVector3Array = rig["tank_floor"]
	var nose: Vector3 = rig["tank_nose"]
	var out := []
	for i in steps + 1:
		var u := float(i) / steps
		var k := BikeModel._key_at(shape["keys"], u)
		var on: Array = line_at(floor_line, nose.z + u * float(fit["len"]))
		var down: float = k[2] * float(fit["ky"])
		out.append({"c": (on[0] as Vector3) + Vector3(0.0, down - float(fit["sink"]), 0.0), "w": k[0] * float(fit["kx"]), "up": k[1] * float(fit["ky"]),
			"down": down, "n": shape["n"], "bw": shape["bw"]})
	return out


# ---------------------------------------------------------------------------- seat

## The seat on the rails: {"weights", "warp", "z0", "z1", "rail_y" (Callable z -> y)} for a seat of
## `shape` (SEAT_SHAPES's) and look `sc`, reaching back to the rails' end (or the `span` of them a
## solo seat covers), its nose against `tank_rear_sec` (the tank's last section).
static func seat_fit(rig: Dictionary, shape: Dictionary, sc: Vector3, span: float, tank_rear_sec: Dictionary, foam_extra: float) -> Dictionary:
	var rails: Array = rig["seat_rails"]
	var a: Vector3 = rails[0]
	var b: Vector3 = rails[1]
	var z0 := a.z
	if rig.has("tank_rear"):
		# Line 3: the seat's nose meets the tank's rear (or runs over it on an MX bike).
		z0 = maxf(a.z, (rig["tank_rear"] as Vector3).z - 0.01) if not rig.get("seat_overlap", false) else a.z + float(shape.get("from", 0.0))
	var z1 := lerpf(z0, maxf(b.z + float(shape.get("to", 0.0)), z0 + 0.25), span * sc.x)
	var slope := (b.y - a.y) / maxf(b.z - a.z, 0.01)
	var rail_y := func(z: float) -> float: return a.y + slope * (z - a.z)
	var length := z1 - z0
	var keys: Array = shape["keys"]
	var weights := {}
	# The foam brings the top up to the published seat height at the hip point.
	if rig.has("seat_surface"):
		var hip: Vector3 = rig["seat_surface"]
		var u := clampf((hip.z - z0) / maxf(length, 0.01), 0.0, 1.0)
		var k := BikeModel._seat_key_at(keys, u)
		var top: float = (float(k[2]) + float(k[3]) + float(k[1])) * sc.z
		weights["foam"] = clampf((hip.y - rail_y.call(hip.z) - top) / SEAT_FOAM / maxf(sc.z, 0.5) + foam_extra / SEAT_FOAM, -1.0, 2.5)
	# Line 3: its nose as wide and as tall as the tank's rear.
	if not tank_rear_sec.is_empty():
		var k0 := BikeModel._seat_key_at(keys, 0.0)
		weights["nose_width"] = clampf((float(tank_rear_sec["w"]) - float(k0[0]) * sc.y) / SEAT_NOSE_W, -1.0, 1.5)
		var tank_top := (tank_rear_sec["c"] as Vector3).y + float(tank_rear_sec["up"])
		var seat_top: float = rail_y.call(z0) + (float(k0[1]) + float(k0[2]) + float(k0[3]) + SEAT_FOAM * float(weights.get("foam", 0.0))) * sc.z
		weights["nose_height"] = clampf((tank_top - seat_top) / SEAT_NOSE_H, -1.0, 1.5)
	var dir := Vector3(0.0, slope, 1.0).normalized()
	var up := up_from(dir)
	var warp := func(p: Vector3) -> Vector3:
		var z := z0 + p.z * length
		return Vector3(p.x * sc.y, rail_y.call(z), z) + up * (p.y * sc.z)
	return {"weights": weights, "warp": warp, "z0": z0, "z1": z1, "rail_y": rail_y, "sc": sc}


# ---------------------------------------------------------------------------- tail cowl

## Where a cowl of `keys` (TAIL_COWLS's) starts along the rails: as long as its look's `ln` says,
## ending at the rig's tail (lines agreement line 4), but not over the front of the seat.
static func cowl_start(rig: Dictionary, keys: Array, ln: float, seat_z0: float, seat_z1: float) -> float:
	var ref_len := maxf(float(keys[keys.size() - 1][0]) - float(keys[0][0]), 0.05)
	if not rig.has("tail"):
		return seat_z1
	return clampf(float((rig["tail"] as Vector3).z) - ref_len * ln, seat_z0 + 0.3, seat_z1)


## A cowl from `from` (on the rails) to the rig's tail: {"weights", "warp"}. `keys` are
## TAIL_COWLS's, `seat_end` the seat's last section (for the join), `ln` the look's length (the
## rig's tail wins when there is one).
static func cowl_fit(rig: Dictionary, keys: Array, from: Vector3, slope: float, ln: float, seat_end: Dictionary) -> Dictionary:
	var ref_len := maxf(float(keys[keys.size() - 1][0]) - float(keys[0][0]), 0.05)
	var to_z := float((rig["tail"] as Vector3).z) if rig.has("tail") else from.z + ref_len * ln
	var kz := clampf((to_z - from.z) / ref_len, 0.5, 1.6)
	var weights := {}
	if not seat_end.is_empty():
		weights["front_width"] = clampf((float(seat_end["w"]) - float(keys[0][1])) / COWL_FRONT_W, -1.0, 1.0)
	if rig.has("tail") and rig.has("tail_top"):
		weights["kick"] = clampf((float(rig["tail_top"]) - from.y) / COWL_KICK, 0.0, 1.5)
	var dir := Vector3(0.0, slope, 1.0).normalized()
	var up := up_from(dir)
	var warp := func(p: Vector3) -> Vector3:
		return from + dir * (p.z * kz) + up * p.y + Vector3(p.x, 0.0, 0.0)
	return {"weights": weights, "warp": warp}
