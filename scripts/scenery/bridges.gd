class_name BridgeKit
extends RefCounted
## Bridges in ten designs (the city survey's bridge family): stone arches, a concrete viaduct, a girder overbridge, a
## steel truss, a bowstring arch, a gorge arch, cable-stayed, suspension, a covered timber bridge and a lifting canal
## bridge. Only what's built round a bridge changes: the deck that's ridden on (its height, grip and collision) is the
## road's as it always was, and the land under it too, so a road, a ride's hash or a postcard never moves.
##
## Each bridge picks its own design (pick) from what can be measured of it: how long it is, how high its deck is over
## the land, whether it's over water, a road or a canal, how big a road it carries and the region of the world it's in,
## with a roll from where it stands for the rest (the same on every machine). The map's own word on a bridge's structure
## isn't baked into the cells (Overture's roads carry only "is a bridge"), so it's never asked.
##
## A bridge is a record (make): the deck's middle every DS metres from one end to the other, in the caller's block or
## chunk frame, with its sideways direction and the land under it. draw lays the parts of it whose anchor the caller
## keeps (`keep`, by distance along the bridge and position), so a bridge across several blocks or chunks is built once,
## a part in each. edge draws the deck's sides (parapet, crash barrier or railing) along the caller's own road points.

## The record's points are this far apart along the bridge (m).
const DS := 2.0
const DESIGNS := ["stone_arch", "viaduct", "girder", "truss", "bowstring", "gorge_arch", "cable_stayed", "suspension",
	"covered", "lift"]
## A pier only where the deck's underside is this far over the land (m).
const PIER_MIN := 1.5
## A parapet's height over the deck (m: the single-line ride's, AdventureChunk.PARAPET).
const RAIL_KERB := 0.25

const STONE := [Color(0.62, 0.58, 0.5), Color(0.55, 0.54, 0.52), Color(0.66, 0.6, 0.47)]
const BRICK := Color(0.56, 0.32, 0.24)
const CONCRETE := Color(0.68, 0.67, 0.64)
const STEEL := Color(0.36, 0.38, 0.4)
const CABLE := Color(0.82, 0.82, 0.8)
## Paint by design (a roll picks one).
const PAINT := {
	"girder": [Color(0.2, 0.36, 0.26), Color(0.22, 0.32, 0.5), Color(0.5, 0.52, 0.52), Color(0.82, 0.78, 0.66)],
	"truss": [Color(0.5, 0.18, 0.12), Color(0.22, 0.36, 0.26), Color(0.45, 0.48, 0.5), Color(0.7, 0.72, 0.72)],
	"bowstring": [Color(0.9, 0.9, 0.88), Color(0.2, 0.36, 0.62), Color(0.72, 0.16, 0.12)],
	"suspension": [Color(0.75, 0.27, 0.13), Color(0.6, 0.62, 0.62), Color(0.22, 0.36, 0.3)],
	"cable_stayed": [Color(0.9, 0.9, 0.88), CONCRETE],
	"covered": [Color(0.55, 0.18, 0.12), Color(0.45, 0.32, 0.2)],
	"lift": [Color(0.93, 0.93, 0.9)],
}
## Regions whose older bridges are steel more often than stone, and the ones with old stone bridges everywhere.
const STEEL_REGIONS := ["north_america", "australia_nz"]
const STONE_REGIONS := ["british_isles", "western_europe", "mediterranean", "eastern_europe", "nordic"]
## Countries with covered timber bridges, and with lifting bridges over their canals.
const COVERED_COUNTRIES := ["CH", "AT", "DE", "US", "CA", "LU"]
const LIFT_COUNTRIES := ["NL", "BE", "DE", "DK"]


## A bridge's design from what's known of it: {length (m), clear (the most its deck's underside is over the land, m),
## wet (its share over water, 0..1), over_road, big (a motorway or trunk road), region (RegionKit's), country (ISO),
## canal (it crosses a canal), roll (0..1, its own)}.
static func pick(f: Dictionary) -> String:
	var length := float(f.get("length", 0.0))
	var clear := float(f.get("clear", 0.0))
	var wet := float(f.get("wet", 0.0)) >= 0.25
	var over_road := bool(f.get("over_road", false))
	var big := bool(f.get("big", false))
	var region := str(f.get("region", ""))
	var country := str(f.get("country", "")).to_upper()
	var roll := float(f.get("roll", 0.5))
	var steel_land := region in STEEL_REGIONS
	var stone_land := region in STONE_REGIONS
	if bool(f.get("canal", false)) and length < 45.0 and country in LIFT_COUNTRIES and not big:
		return "lift"
	if length >= 600.0 and (wet or clear >= 30.0):
		return "suspension" if length >= 1000.0 or roll < 0.45 else "cable_stayed"
	if over_road and not wet and length < 90.0:
		return "girder"
	if clear >= 40.0 and length >= 80.0:
		return "gorge_arch" if length <= 420.0 and roll < 0.55 else "viaduct"
	if wet and length >= 200.0:
		if roll < 0.4:
			return "cable_stayed"
		return "truss" if steel_land and roll < 0.75 else ("viaduct" if big else "bowstring")
	if big and length >= 60.0:
		return "viaduct"
	if wet and length >= 50.0:
		if steel_land:
			return "truss" if roll < 0.7 else "bowstring"
		if roll < 0.45:
			return "bowstring"
		return "stone_arch" if stone_land and length < 140.0 else ("truss" if roll < 0.7 else "viaduct")
	if length < 60.0 and not big and country in COVERED_COUNTRIES and roll < 0.12:
		return "covered"
	if length < 60.0:
		if stone_land or (not steel_land and roll < 0.6):
			return "stone_arch" if clear < 25.0 else "viaduct"
		return "truss" if wet and roll < 0.5 else "girder"
	if clear >= 15.0 or big:
		return "viaduct"
	return "stone_arch" if stone_land and length < 140.0 else "girder"


## A bridge's record from its deck's middle every `ds` m (about DS: `pts`, the road's surface there), its sideways direction
## (`rights`), the land under it (`ground`) and whether that's water (`wet`, 0 or 1 each), in the caller's frame: its
## deck `w` m either side of the middle to its outer edge, `depth` deep, and `facts` for pick (region, country, big,
## canal, roll; avoid: [Vector2(from, to)] m along it where no pier may stand, the roads under it).
static func make(pts: PackedVector3Array, rights: PackedVector3Array, ground: PackedFloat32Array,
		wet: PackedFloat32Array, w: float, depth: float, facts: Dictionary, ds := DS) -> Dictionary:
	var n := pts.size()
	var length := ds * float(maxi(n - 1, 1))
	var clear := 0.0
	var wets := 0.0
	for k in n:
		clear = maxf(clear, pts[k].y - depth - ground[k])
		wets += wet[k] if k < wet.size() else 0.0
	var f := facts.duplicate()
	f["length"] = length
	f["clear"] = clear
	f["wet"] = wets / float(maxi(n, 1))
	f["over_road"] = not (facts.get("avoid", []) as Array).is_empty()
	var design := str(facts["design"]) if facts.has("design") else pick(f)
	var roll := float(f.get("roll", 0.5))
	var rec := {"pts": pts, "rights": rights, "ground": ground, "wet": wet, "n": n, "ds": ds, "length": length, "w": w,
		"depth": depth, "clear": clear, "design": design, "roll": roll, "avoid": facts.get("avoid", []),
		"wet_share": f["wet"]}
	var paint: Array = PAINT.get(design, [CONCRETE])
	rec["paint"] = paint[int(roll * 997.0) % paint.size()]
	var stone: Color = STONE[int(roll * 613.0) % STONE.size()]
	if str(facts.get("region", "")) in ["british_isles", "western_europe"] and int(roll * 211.0) % 4 == 0:
		stone = BRICK
	rec["stone"] = stone
	match design:
		"stone_arch":
			rec["edge"] = {"kind": "stone", "col": stone}
		"gorge_arch":
			rec["stone"] = stone if roll < 0.5 else CONCRETE
			rec["edge"] = {"kind": "stone" if roll < 0.5 else "concrete", "col": rec["stone"]}
		"viaduct", "cable_stayed", "suspension":
			rec["edge"] = {"kind": "concrete", "col": CONCRETE}
		"girder", "truss", "bowstring", "lift":
			rec["edge"] = {"kind": "rail", "col": rec["paint"] if design != "truss" else STEEL,
				"fascia": rec["paint"] if design in ["girder", "bowstring"] else CONCRETE}
		"covered":
			rec["edge"] = {"kind": "timber", "col": Color(0.42, 0.3, 0.2)}
	return rec


## How a bridge's sides look ({kind: stone, concrete, rail or timber, col, fascia}), for a bridge with no record: the
## old stone parapet.
static func plain_edge() -> Dictionary:
	return {"kind": "stone", "col": STONE[0]}


## One stretch of a deck's side into `arr`, from its inside edge at the road `in0`..`in1` to its outside `out0`..`out1`
## (both at the road's surface): `h` tall (a parapet's height), its outer face on down `depth` under the road, in edge
## style `st` (make's "edge"). The caller lays the inside's collision, as tall as `h` whatever the look.
static func edge(arr: Dictionary, st: Dictionary, in0: Vector3, in1: Vector3, out0: Vector3, out1: Vector3, h: float,
		depth: float) -> void:
	var col: Color = st.get("col", STONE[0])
	var top := Vector3.UP * h
	var dn := Vector3.DOWN * depth
	match str(st.get("kind", "stone")):
		"stone", "concrete":
			AdventureProps._quad(arr, in0, in1, in1 + top, in0 + top, col.darkened(0.06))
			AdventureProps._quad(arr, in0 + top, in1 + top, out1 + top, out0 + top, col.lightened(0.08))
			AdventureProps._quad(arr, out0 + top, out1 + top, out1 + dn, out0 + dn, col)
			if str(st["kind"]) == "concrete":
				# (a steel rail along the top of the barrier)
				var r := Vector3.UP * (h + 0.12)
				var m0 := in0.lerp(out0, 0.3)
				var m1 := in1.lerp(out1, 0.3)
				AdventureProps._quad(arr, m0 + top, m1 + top, m1 + r, m0 + r, STEEL)
		"rail":
			var kerb := Vector3.UP * RAIL_KERB
			var fascia: Color = st.get("fascia", CONCRETE)
			AdventureProps._quad(arr, in0, in1, in1 + kerb, in0 + kerb, CONCRETE.darkened(0.1))
			AdventureProps._quad(arr, in0 + kerb, in1 + kerb, out1 + kerb, out0 + kerb, CONCRETE)
			AdventureProps._quad(arr, out0 + kerb, out1 + kerb, out1 + dn, out0 + dn, fascia)
			# A post at the stretch's start, a top rail and a middle one, along the middle of the kerb.
			var m0 := in0.lerp(out0, 0.5)
			var m1 := in1.lerp(out1, 0.5)
			var across := (out0 - in0).normalized() * 0.06
			AdventureProps._quad(arr, m0 + kerb - across, m0 + kerb + across, m0 + top + across, m0 + top - across, col)
			for y: float in [h, h * 0.62]:
				var a := Vector3.UP * y
				var b := Vector3.UP * (y - 0.1)
				AdventureProps._quad(arr, m0 + b, m1 + b, m1 + a, m0 + a, col)
		"timber":
			var kerb := Vector3.UP * 0.3
			AdventureProps._quad(arr, in0, in1, in1 + kerb, in0 + kerb, col)
			AdventureProps._quad(arr, in0 + kerb, in1 + kerb, out1 + kerb, out0 + kerb, col.lightened(0.06))
			AdventureProps._quad(arr, out0 + kerb, out1 + kerb, out1 + dn, out0 + dn, col.darkened(0.1))


## What's built round bridge `rec` into `arr`: its piers, arches, beams, towers and cables, those of its parts whose
## anchor `keep` (s m along it, p in the record's frame -> bool) takes.
static func draw(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	if int(rec["n"]) < 2:
		return
	match str(rec["design"]):
		"stone_arch": _stone_arch(arr, rec, keep)
		"viaduct": _viaduct(arr, rec, keep)
		"girder": _girder(arr, rec, keep)
		"truss": _truss(arr, rec, keep)
		"bowstring": _bowstring(arr, rec, keep)
		"gorge_arch": _gorge_arch(arr, rec, keep)
		"cable_stayed": _cable_stayed(arr, rec, keep)
		"suspension": _suspension(arr, rec, keep)
		"covered": _covered(arr, rec, keep)
		"lift": _lift(arr, rec, keep)


# ---------------------------------------------------------------------------- along the bridge

## The deck's middle at the road's surface `s` m along.
static func centre(rec: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = rec["pts"]
	var f := clampf(s / float(rec["ds"]), 0.0, float(pts.size() - 1))
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


static func right(rec: Dictionary, s: float) -> Vector3:
	var r: PackedVector3Array = rec["rights"]
	var f := clampf(s / float(rec["ds"]), 0.0, float(r.size() - 1))
	var i := mini(int(f), r.size() - 2)
	return r[i].lerp(r[i + 1], f - i).normalized()


static func ground(rec: Dictionary, s: float) -> float:
	var g: PackedFloat32Array = rec["ground"]
	var f := clampf(s / float(rec["ds"]), 0.0, float(g.size() - 1))
	var i := mini(int(f), g.size() - 2)
	return lerpf(g[i], g[i + 1], f - i)


static func _wet_at(rec: Dictionary, s: float) -> bool:
	var g: PackedFloat32Array = rec["wet"]
	return not g.is_empty() and g[clampi(roundi(s / float(rec["ds"])), 0, g.size() - 1)] > 0.5


## A point `lat` m to the right of the deck's middle `s` m along, `up` over the road's surface there.
static func at(rec: Dictionary, s: float, lat: float, up: float) -> Vector3:
	return centre(rec, s) + right(rec, s) * lat + Vector3.UP * up


## The deck's underside `s` m along (its height).
static func under(rec: Dictionary, s: float) -> float:
	return centre(rec, s).y - float(rec["depth"])


## Whether a pier may stand `s` m along: not in a road under the bridge.
static func _free(rec: Dictionary, s: float, pad := 0.0) -> bool:
	for av: Vector2 in rec["avoid"]:
		if s > av.x - pad and s < av.y + pad:
			return false
	return true


## The places m along a bridge `length` long where its piers stand about `gap` apart, evenly (not the ends).
static func spaced(length: float, gap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(1, roundi(length / maxf(gap, 1.0)))
	for i in range(1, n):
		out.append(length * float(i) / float(n))
	return out


## A beam `t` thick from `a` to `b`.
static func beam(arr: Dictionary, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var x := (y.cross(Vector3.UP) if absf(y.y) < 0.95 else y.cross(Vector3.RIGHT)).normalized()
	var z := x.cross(y)
	AdventureProps.box(arr, Transform3D(Basis(x * t, d, z * t), a), Vector3.ONE, col, true)


## An upright block `s` m along, `lat` to the right, from height `y0` to `y1`, `across` wide and `along` long.
static func block(arr: Dictionary, rec: Dictionary, s: float, lat: float, y0: float, y1: float, across: float,
		along: float, col: Color) -> void:
	if y1 - y0 < 0.05:
		return
	var r := right(rec, s)
	var fwd := Vector3(-r.z, 0.0, r.x)
	var p := centre(rec, s) + r * lat
	AdventureProps.box(arr, Transform3D(Basis(r * across, Vector3.UP * (y1 - y0), fwd * along), Vector3(p.x, y0, p.z)),
		Vector3.ONE, col, true)


## A pier `s` m along, from under the land up to `top`: `across` wide (one block, or two columns where it's wide),
## `along` long, with cutwaters where it stands in water.
static func pier(arr: Dictionary, rec: Dictionary, s: float, top: float, across: float, along: float, col: Color,
		cutwaters := true) -> void:
	var g := ground(rec, s)
	if top - g < 0.3:
		return
	block(arr, rec, s, 0.0, g - 1.5, top, across, along, col)
	if cutwaters and _wet_at(rec, s):
		# (a square block turned 45 degrees at each end of the pier: its noses point up and down the river)
		var r := right(rec, s)
		var fwd := r.cross(Vector3.UP)
		var nose := along * 0.7071
		var x := (r + fwd).normalized()
		var hgt := minf(top, g + 4.0) - g + 1.5
		for side: float in [-1.0, 1.0]:
			var p := centre(rec, s) + r * side * across * 0.5
			AdventureProps.box(arr, Transform3D(Basis(x * nose, Vector3.UP * hgt, x.cross(Vector3.UP) * nose),
				Vector3(p.x, g - 1.5, p.z)), Vector3.ONE, col.darkened(0.05), true)


## Calls `f` for each stretch of the bridge (s0, s1, its record's spacing / `sub` long) whose middle `keep` takes.
static func _stretches(rec: Dictionary, keep: Callable, sub: int, f: Callable, from := 0.0, to := INF) -> void:
	var length := float(rec["length"])
	to = minf(to, length)
	var step := float(rec["ds"]) / float(sub)
	var s := maxf(from, 0.0)
	while s < to - 0.001:
		var e := minf(s + step, to)
		var m := (s + e) * 0.5
		if keep.call(m, centre(rec, m)):
			f.call(s, e)
		s = e


static func _keeps(rec: Dictionary, keep: Callable, s: float) -> bool:
	return keep.call(s, centre(rec, s))


# ---------------------------------------------------------------------------- the designs

## Round stone arches between piers with cutwaters (a tall one's piers make it an arched viaduct), and arches from the
## abutments at each end.
static func _stone_arch(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var span := clampf(float(rec["clear"]) * 0.9, 6.0, 18.0)
	var stone: Color = rec["stone"]
	var w := float(rec["w"])
	var ends := PackedFloat32Array([0.0])
	ends.append_array(spaced(length, span))
	ends.append(length)
	var springs := PackedFloat32Array()
	for k in ends.size():
		var s := ends[k]
		var half := (ends[mini(k + 1, ends.size() - 1)] - ends[maxi(k - 1, 0)]) * 0.5
		var top := under(rec, s) - 0.6
		springs.append(minf(top - 0.1, maxf(ground(rec, s) + 0.3, top - half * 0.55)))
	var arch_y := func(s: float) -> float:
		var j := 0
		while j < ends.size() - 2 and s > ends[j + 1]:
			j += 1
		var a := ends[j]
		var b := ends[j + 1]
		var t := clampf((s - a) / maxf(b - a, 0.01), 0.0, 1.0)
		var base := lerpf(springs[j], springs[j + 1], t)
		var top := under(rec, s) - 0.6
		var u := t * 2.0 - 1.0
		return base + (top - base) * sqrt(maxf(0.0, 1.0 - u * u))
	var fn1 := func(s0: float, s1: float) -> void:
		var y0: float = arch_y.call(s0)
		var y1: float = arch_y.call(s1)
		var u0 := under(rec, s0)
		var u1 := under(rec, s1)
		if y0 >= u0 - 0.02 and y1 >= u1 - 0.02:
			return
		for side: float in [-1.0, 1.0]:
			var a0 := at(rec, s0, side * w, 0.0)
			var a1 := at(rec, s1, side * w, 0.0)
			AdventureProps._quad(arr, Vector3(a0.x, u0, a0.z), Vector3(a1.x, u1, a1.z), Vector3(a1.x, y1, a1.z),
				Vector3(a0.x, y0, a0.z), stone.darkened(0.03))
		var l0 := at(rec, s0, -w, 0.0)
		var r0 := at(rec, s0, w, 0.0)
		var l1 := at(rec, s1, -w, 0.0)
		var r1 := at(rec, s1, w, 0.0)
		AdventureProps._quad(arr, Vector3(l0.x, y0, l0.z), Vector3(r0.x, y0, r0.z), Vector3(r1.x, y1, r1.z),
			Vector3(l1.x, y1, l1.z), stone.darkened(0.3))
	_stretches(rec, keep, 4, fn1)
	for k in range(1, ends.size() - 1):
		var s := ends[k]
		if not _keeps(rec, keep, s) or under(rec, s) - ground(rec, s) < PIER_MIN:
			continue
		pier(arr, rec, s, springs[k] + 0.4, w * 2.0, clampf(span * 0.16, 1.2, 2.6), stone.darkened(0.08))


## Slim concrete piers with hammerhead caps far apart, a box girder under the deck and crash barriers.
static func _viaduct(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"])
	var col := CONCRETE
	var girder := 1.4
	var fn2 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, w * 0.62, girder, col.darkened(0.12))
	_stretches(rec, keep, 1, fn2)
	for s in spaced(length, clampf(float(rec["clear"]) * 1.2, 30.0, 60.0)):
		if not _keeps(rec, keep, s) or not _free(rec, s, 4.0) or under(rec, s) - ground(rec, s) < PIER_MIN + girder:
			continue
		_hammerhead(arr, rec, s, under(rec, s) - girder, col)


## A box girder under the deck from `s0` to `s1`: `half` either side, `deep` under the deck's underside.
static func _box_girder(arr: Dictionary, rec: Dictionary, s0: float, s1: float, half: float, deep: float, col: Color) -> void:
	var u0 := under(rec, s0)
	var u1 := under(rec, s1)
	var l0 := at(rec, s0, -half, 0.0)
	var r0 := at(rec, s0, half, 0.0)
	var l1 := at(rec, s1, -half, 0.0)
	var r1 := at(rec, s1, half, 0.0)
	for p: Array in [[l0, l1], [r0, r1]]:
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		AdventureProps._quad(arr, Vector3(a.x, u0, a.z), Vector3(b.x, u1, b.z), Vector3(b.x, u1 - deep, b.z),
			Vector3(a.x, u0 - deep, a.z), col)
	AdventureProps._quad(arr, Vector3(l0.x, u0 - deep, l0.z), Vector3(r0.x, u0 - deep, r0.z),
		Vector3(r1.x, u1 - deep, r1.z), Vector3(l1.x, u1 - deep, l1.z), col.darkened(0.2))


## A concrete pier `s` m along up to `top`: one column (two where the deck is wide or it's tall) and a hammerhead.
static func _hammerhead(arr: Dictionary, rec: Dictionary, s: float, top: float, col: Color) -> void:
	var w := float(rec["w"])
	var cap := 1.2
	var g := ground(rec, s)
	if w * 2.0 > 13.0 or top - g > 45.0:
		for side: float in [-1.0, 1.0]:
			block(arr, rec, s, side * w * 0.45, g - 1.5, top - cap, 2.2, 2.4, col.darkened(0.06))
	else:
		block(arr, rec, s, 0.0, g - 1.5, top - cap, clampf(w * 0.5, 2.2, 4.0), 2.2, col.darkened(0.06))
	block(arr, rec, s, 0.0, top - cap, top, w * 1.5, 2.4, col)


## A deep painted beam under each side, concrete abutments and, on a long one, piers clear of the road beneath.
static func _girder(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"])
	var paint: Color = rec["paint"]
	var fn3 := func(s0: float, s1: float) -> void:
		var u0 := under(rec, s0)
		var u1 := under(rec, s1)
		for side: float in [-1.0, 1.0]:
			var a := at(rec, s0, side * (w - 0.05), 0.0)
			var b := at(rec, s1, side * (w - 0.05), 0.0)
			AdventureProps._quad(arr, Vector3(a.x, u0, a.z), Vector3(b.x, u1, b.z), Vector3(b.x, u1 - 0.9, b.z),
				Vector3(a.x, u0 - 0.9, a.z), paint)
		_box_girder(arr, rec, s0, s1, w - 0.05, 0.9, paint.darkened(0.25))
	_stretches(rec, keep, 1, fn3)
	for s: float in [2.0, length - 2.0]:
		if _keeps(rec, keep, s):
			block(arr, rec, s, 0.0, ground(rec, s) - 1.5, under(rec, s) - 0.9, w * 2.3, 3.0, CONCRETE.darkened(0.08))
	if length > 40.0:
		for s in spaced(length, 28.0):
			if _keeps(rec, keep, s) and _free(rec, s, 3.0) and under(rec, s) - ground(rec, s) > PIER_MIN + 0.9:
				_hammerhead(arr, rec, s, under(rec, s) - 0.9, CONCRETE)


## Riveted lattice sides over the deck, span by span on piers: Pratt panels, portal ends and bracing overhead.
static func _truss(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"]) + 0.3
	var col: Color = rec["paint"]
	var spans := maxi(1, ceili(length / 90.0))
	var span := length / float(spans)
	var h := clampf(span * 0.12, 5.6, 9.0)
	var panels := maxi(3, roundi(span / 6.0))
	var pl := span / float(panels)
	for j in spans:
		var a := span * j
		for k in panels:
			var s0 := a + pl * k
			var s1 := s0 + pl
			if not _keeps(rec, keep, (s0 + s1) * 0.5):
				continue
			for side: float in [-1.0, 1.0]:
				var lat := side * w
				beam(arr, at(rec, s0, lat, 0.2), at(rec, s1, lat, 0.2), 0.45, col)
				if k == 0:
					beam(arr, at(rec, s0, lat, 0.2), at(rec, s1, lat, h), 0.5, col)
				elif k == panels - 1:
					beam(arr, at(rec, s1, lat, 0.2), at(rec, s0, lat, h), 0.5, col)
				else:
					beam(arr, at(rec, s0, lat, h), at(rec, s1, lat, h), 0.5, col)
				if k < panels - 1:
					beam(arr, at(rec, s1, lat, 0.2), at(rec, s1, lat, h), 0.3, col)
				# (Pratt diagonals, sloping down towards the middle)
				if k > 0 and k < panels - 1:
					if s0 - a < span * 0.5:
						beam(arr, at(rec, s0, lat, h), at(rec, s1, lat, 0.2), 0.24, col)
					else:
						beam(arr, at(rec, s1, lat, h), at(rec, s0, lat, 0.2), 0.24, col)
			if k > 0 and k < panels - 1:
				beam(arr, at(rec, s0, -w, h), at(rec, s0, w, h), 0.3, col)
				beam(arr, at(rec, s0, -w, h - 0.1), at(rec, s1, w, h - 0.1), 0.16, col.darkened(0.1))
		if j > 0 and _keeps(rec, keep, a) and under(rec, a) - ground(rec, a) > PIER_MIN:
			pier(arr, rec, a, under(rec, a), w * 2.0 + 0.6, 2.4, rec["stone"])
	var fn4 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, w, 0.5, STEEL)
	_stretches(rec, keep, 1, fn4)


## An arch over the deck each side from end to end of each span, hangers down to the deck, and bracing between the
## arches where they're high enough.
static func _bowstring(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"]) + 0.3
	var col: Color = rec["paint"]
	var spans := maxi(1, ceili(length / 160.0))
	var span := length / float(spans)
	var rise := clampf(span * 0.17, 7.0, 32.0)
	var segs := maxi(8, roundi(span / 6.0))
	for j in spans:
		var a := span * j
		var y := func(t: float) -> float: return 0.3 + rise * 4.0 * t * (1.0 - t)
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var s0 := a + span * t0
			var s1 := a + span * t1
			if not _keeps(rec, keep, (s0 + s1) * 0.5):
				continue
			for side: float in [-1.0, 1.0]:
				beam(arr, at(rec, s0, side * w, y.call(t0)), at(rec, s1, side * w, y.call(t1)), 0.8, col)
				if k > 0:
					beam(arr, at(rec, s0, side * w, 0.2), at(rec, s0, side * w, y.call(t0)), 0.12, CABLE.darkened(0.2))
			if y.call(t0) > 6.5 and k % 2 == 0:
				beam(arr, at(rec, s0, -w, y.call(t0)), at(rec, s0, w, y.call(t0)), 0.45, col)
		if j > 0 and _keeps(rec, keep, a) and under(rec, a) - ground(rec, a) > PIER_MIN:
			pier(arr, rec, a, under(rec, a) - 0.8, w * 2.0, 3.0, CONCRETE)
	var fn5 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, w, 0.8, col.darkened(0.15))
	_stretches(rec, keep, 1, fn5)


## One great arch under the deck springing from the valley's sides, columns up from it to the deck, and piers on the
## approaches.
static func _gorge_arch(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"])
	var col: Color = rec["stone"]
	var main := minf(length * 0.8, 350.0)
	var sa := (length - main) * 0.5
	var sb := sa + main
	var ga := ground(rec, sa)
	var gb := ground(rec, sb)
	var crown := under(rec, length * 0.5) - 1.2
	var lat := w * 0.7
	var y := func(t: float) -> float:
		return lerpf(ga, gb, t) + (crown - lerpf(ga, gb, 0.5)) * 4.0 * t * (1.0 - t)
	var segs := maxi(12, roundi(main / 10.0))
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var s0 := sa + main * t0
		var s1 := sa + main * t1
		if not _keeps(rec, keep, (s0 + s1) * 0.5):
			continue
		for side: float in [-1.0, 1.0]:
			var p0 := at(rec, s0, side * lat, 0.0)
			var p1 := at(rec, s1, side * lat, 0.0)
			beam(arr, Vector3(p0.x, y.call(t0), p0.z), Vector3(p1.x, y.call(t1), p1.z), 1.8, col)
		if k % 2 == 1:
			beam(arr, Vector3(at(rec, s0, -lat, 0.0).x, y.call(t0), at(rec, s0, -lat, 0.0).z),
				Vector3(at(rec, s0, lat, 0.0).x, y.call(t0), at(rec, s0, lat, 0.0).z), 0.8, col.darkened(0.08))
	# Columns from the arch (or the land) up to the deck.
	var gap := 12.0
	var s := gap * 0.5
	while s < length:
		if _keeps(rec, keep, s) and under(rec, s) - ground(rec, s) > PIER_MIN:
			var foot := ground(rec, s) - 1.5
			if s > sa and s < sb:
				foot = maxf(foot, y.call((s - sa) / main))
			for side: float in [-1.0, 1.0]:
				block(arr, rec, s, side * lat, foot, under(rec, s) - 0.6, 1.1, 1.1, col.darkened(0.05))
			block(arr, rec, s, 0.0, under(rec, s) - 0.6, under(rec, s), lat * 2.0 + 1.2, 1.2, col)
		s += gap if s > sa and s < sb else gap * 2.0
	var fn6 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, lat + 0.6, 0.6, col.darkened(0.15))
	_stretches(rec, keep, 1, fn6)


## One pylon in the middle (two on a long one), H or A shaped, with fans of cables to the deck's edges; piers on the
## approaches.
static func _cable_stayed(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"])
	var roll := float(rec["roll"])
	var col: Color = rec["paint"]
	var pylons: Array = [length * 0.5] if length < 450.0 else [length * 0.28, length * 0.72]
	var reach := length * (0.42 if pylons.size() == 1 else 0.2)
	var hp := clampf(reach * 0.42, 25.0, 140.0)
	var shape_a := int(roll * 389.0) % 2 == 0
	var leg := w + 1.6
	var nc := clampi(roundi(reach / 10.0), 6, 22)
	var fn7 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, w * 0.8, 1.6, CONCRETE.darkened(0.12))
	_stretches(rec, keep, 1, fn7)
	for sp: float in pylons:
		if not _keeps(rec, keep, sp):
			continue
		var g := ground(rec, sp)
		var deck := centre(rec, sp).y
		for side: float in [-1.0, 1.0]:
			var foot := at(rec, sp, side * leg, 0.0)
			beam(arr, Vector3(foot.x, g - 2.0, foot.z), Vector3(foot.x, deck, foot.z), 2.6, col.darkened(0.05))
			var top := at(rec, sp, 0.0 if shape_a else side * leg, hp)
			beam(arr, Vector3(foot.x, deck, foot.z), top, 2.2, col)
		block(arr, rec, sp, 0.0, under(rec, sp) - 2.0, under(rec, sp), leg * 2.0 + 2.6, 3.0, col.darkened(0.1))
		if not shape_a:
			for f: float in [0.55, 0.97]:
				beam(arr, at(rec, sp, -leg, hp * f), at(rec, sp, leg, hp * f), 1.6, col)
		for k in nc:
			var d := reach * float(k + 1) / nc
			var hy := hp * (0.6 + 0.36 * float(k + 1) / nc)
			for dir: float in [-1.0, 1.0]:
				var sd := clampf(sp + dir * d, 1.0, length - 1.0)
				for side: float in [-1.0, 1.0]:
					var lat_top := 0.0 if shape_a else side * leg
					if shape_a:
						lat_top = side * leg * (1.0 - hy / hp)
					beam(arr, at(rec, sp, lat_top, hy), at(rec, sd, side * (w - 0.1), 0.3), 0.16, CABLE)
	for s in spaced(length, 45.0):
		var near := false
		for sp: float in pylons:
			near = near or absf(s - sp) < reach + 10.0
		if near or not _keeps(rec, keep, s) or not _free(rec, s, 4.0) or under(rec, s) - ground(rec, s) < PIER_MIN + 1.6:
			continue
		_hammerhead(arr, rec, s, under(rec, s) - 1.6, CONCRETE)


## Two towers, main cables sagging between them and down to anchorages at the ends, hangers to the deck every few
## metres, and a stiffening girder under it.
static func _suspension(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"])
	var col: Color = rec["paint"]
	var f := 0.18 if length >= 800.0 else 0.22
	var sa := length * f
	var sb := length * (1.0 - f)
	var ht := clampf((sb - sa) * 0.11, 30.0, 180.0)
	var lat := w + 0.35
	var leg := w + 2.0
	var cable_y := func(s: float) -> float:
		if s < sa:
			return lerpf(1.2, ht, s / sa)
		if s > sb:
			return lerpf(ht, 1.2, (s - sb) / (length - sb))
		var u := (s - (sa + sb) * 0.5) / ((sb - sa) * 0.5)
		return 3.0 + (ht - 3.0) * u * u
	var fn8 := func(s0: float, s1: float) -> void:
		_box_girder(arr, rec, s0, s1, w, 2.2, col.darkened(0.2))
		for side: float in [-1.0, 1.0]:
			beam(arr, at(rec, s0, side * lat, cable_y.call(s0)), at(rec, s1, side * lat, cable_y.call(s1)), 0.7, CABLE.darkened(0.1))
		# (a hanger every 12 m)
		var hk := ceilf(s0 / 12.0) * 12.0
		if hk < s1 and hk > 2.0 and hk < length - 2.0 and absf(hk - sa) > 3.0 and absf(hk - sb) > 3.0:
			for side: float in [-1.0, 1.0]:
				beam(arr, at(rec, hk, side * lat, 0.3), at(rec, hk, side * lat, cable_y.call(hk)), 0.14, CABLE.darkened(0.25))
	_stretches(rec, keep, 1, fn8)
	for st: float in [sa, sb]:
		if not _keeps(rec, keep, st):
			continue
		var g := ground(rec, st)
		for side: float in [-1.0, 1.0]:
			var foot := at(rec, st, side * leg, 0.0)
			beam(arr, Vector3(foot.x, g - 2.0, foot.z), at(rec, st, side * leg, ht + 2.0), 3.2, col)
		for fy: float in [0.97, 0.6]:
			beam(arr, at(rec, st, -leg, ht * fy), at(rec, st, leg, ht * fy), 2.4, col)
		block(arr, rec, st, 0.0, under(rec, st) - 3.0, under(rec, st), leg * 2.0 + 3.2, 3.6, col.darkened(0.1))
	for s: float in [3.0, length - 3.0]:
		if _keeps(rec, keep, s):
			for side: float in [-1.0, 1.0]:
				block(arr, rec, s, side * (w + 2.2), ground(rec, s) - 2.0, centre(rec, s).y + 1.5, 3.6, 6.0, CONCRETE)


## A timber house over the deck: walls with a band of windows, a gabled roof, and stone piers under it.
static func _covered(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"]) + 0.05
	var col: Color = rec["paint"]
	var roof := Color(0.3, 0.26, 0.24)
	var eave := 4.6
	var ridge := eave + w * 0.6
	var from := minf(2.0, length * 0.2)
	var to := length - from
	var fn9 := func(s0: float, s1: float) -> void:
		var window := int(floorf(s0 / 2.0)) % 2 == 1
		for side: float in [-1.0, 1.0]:
			for band: Array in [[0.3, 1.3, col], [1.3, 2.3, Color(0.08, 0.07, 0.06) if window else col], [2.3, eave, col]]:
				AdventureProps._quad(arr, at(rec, s0, side * w, band[0]), at(rec, s1, side * w, band[0]),
					at(rec, s1, side * w, band[1]), at(rec, s0, side * w, band[1]), band[2] as Color)
			AdventureProps._quad(arr, at(rec, s0, side * (w + 0.6), eave - 0.25), at(rec, s1, side * (w + 0.6), eave - 0.25),
				at(rec, s1, 0.0, ridge), at(rec, s0, 0.0, ridge), roof)
	_stretches(rec, keep, 1, fn9, from, to)
	for s: float in [from, to]:
		if not _keeps(rec, keep, s):
			continue
		AdventureProps._tri(arr, at(rec, s, -(w + 0.6), eave - 0.25), at(rec, s, w + 0.6, eave - 0.25), at(rec, s, 0.0, ridge),
			col.darkened(0.1))
		AdventureProps._quad(arr, at(rec, s, -(w + 0.6), eave - 0.6), at(rec, s, w + 0.6, eave - 0.6),
			at(rec, s, w + 0.6, eave - 0.25), at(rec, s, -(w + 0.6), eave - 0.25), col.darkened(0.1))
	for s in spaced(length, 22.0):
		if _keeps(rec, keep, s) and under(rec, s) - ground(rec, s) > PIER_MIN:
			pier(arr, rec, s, under(rec, s), w * 2.0, 1.8, rec["stone"])


## A white lifting bridge drawn down: a portal with balance beams over the road, rods to the end of the leaf, and
## brick abutments either side of the canal.
static func _lift(arr: Dictionary, rec: Dictionary, keep: Callable) -> void:
	var length := float(rec["length"])
	var w := float(rec["w"]) + 0.3
	var col: Color = rec["paint"]
	var leaf := minf(10.0, length * 0.6)
	var hinge := (length - leaf) * 0.5
	var post := hinge - 0.8
	var top := 7.5
	if _keeps(rec, keep, post):
		for side: float in [-1.0, 1.0]:
			beam(arr, at(rec, post, side * w, 0.0), at(rec, post, side * w, top + 0.4), 0.45, col)
			var back := at(rec, post - 5.0, side * w, top + 0.4)
			var front := at(rec, hinge + leaf, side * w, top + 0.4)
			beam(arr, back, front, 0.5, col)
			block(arr, rec, post - 5.0, side * w, back.y - 1.1, back.y, 0.7, 1.4, Color(0.15, 0.15, 0.15))
			beam(arr, front, at(rec, hinge + leaf, side * w, 0.3), 0.1, Color(0.12, 0.12, 0.12))
		beam(arr, at(rec, post, -w, top), at(rec, post, w, top), 0.4, col)
		beam(arr, at(rec, post, -w, top - 1.8), at(rec, post, w, top - 1.8), 0.3, col)
	for s: float in [hinge - 0.5, hinge + leaf + 0.5]:
		if _keeps(rec, keep, s):
			block(arr, rec, s, 0.0, ground(rec, s) - 1.5, under(rec, s), w * 2.0 + 0.6, 1.6, BRICK)
