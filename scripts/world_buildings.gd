class_name WorldBuildings
extends RefCounted
## Simple low-poly buildings and shapes for the riding map's villages and farms, written
## into SurfaceTools (vertex coloured, flat shaded) so a whole village is three meshes:
## walls, roofs and windows (the windows glow at night). Also the cylinders and lumpy blobs
## the trees and rocks are made of.

const DOOR := Color(0.24, 0.17, 0.12)
const BRICK := Color(0.5, 0.26, 0.2)
const SHUTTER := Color(0.2, 0.2, 0.22)


## Adds building `kind` ("house", "farmhouse", "pub", "church", "barn", "shed", "silo") at
## `xf` (origin on the lowest ground under it, front facing +Z), `size` (width, wall height,
## depth), to the three SurfaceTools.
static func add(kind: String, xf: Transform3D, size: Vector3, wall: Color, roof: Color,
		walls: SurfaceTool, roofs: SurfaceTool, windows: SurfaceTool) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	match kind:
		"silo":
			cylinder(walls, xf.translated_local(Vector3.DOWN * 0.5), w * 0.5, w * 0.5, h + 0.5, 16, wall, false)
			cylinder(roofs, xf.translated_local(Vector3.UP * h), w * 0.52, 0.2, w * 0.35, 16, roof, true)
			# A ladder up the side.
			box(walls, xf, Vector3(0.0, h * 0.5, w * 0.5 + 0.08), Vector3(0.45, h, 0.06), SHUTTER)
		"barn":
			box(walls, xf, Vector3(0.0, (h - 0.5) * 0.5, 0.0), Vector3(w, h + 0.5, d), wall)
			prism(roofs, walls, xf, Vector3(0.0, h, 0.0), w * 0.5 + 0.4, d * 0.5 + 0.4, w * 0.36, true, roof, wall)
			box(walls, xf, Vector3(0.0, h * 0.38, d * 0.5 + 0.03), Vector3(w * 0.5, h * 0.76, 0.06), DOOR)
			box(walls, xf, Vector3(0.0, h * 0.38, d * 0.5 + 0.07), Vector3(w * 0.5, 0.18, 0.04), wall.lightened(0.4))
		"shed":
			box(walls, xf, Vector3(0.0, (h - 0.5) * 0.5, 0.0), Vector3(w, h + 0.5, d), wall)
			prism(roofs, walls, xf, Vector3(0.0, h, 0.0), w * 0.5 + 0.3, d * 0.5 + 0.3, 1.0, false, roof, wall)
			box(walls, xf, Vector3(0.0, 1.4, d * 0.5 + 0.03), Vector3(w * 0.6, 2.8, 0.06), DOOR)
		"church":
			box(walls, xf, Vector3(0.0, (h - 0.5) * 0.5, 0.0), Vector3(w, h + 0.5, d), wall)
			prism(roofs, walls, xf, Vector3(0.0, h, 0.0), w * 0.5 + 0.3, d * 0.5 + 0.3, 5.0, true, roof, wall)
			var tower := Vector3(0.0, 0.0, d * 0.5 + 2.0)
			box(walls, xf, tower + Vector3(0.0, (h + 7.5) * 0.5, 0.0), Vector3(4.6, h + 8.5, 4.6), wall.darkened(0.05))
			cylinder(roofs, xf.translated_local(tower + Vector3.UP * (h + 8.0)), 3.3, 0.05, 9.0, 4, roof, false, PI * 0.25)
			box(walls, xf, tower + Vector3(0.0, 1.4, 2.33), Vector3(1.5, 2.8, 0.06), DOOR)
			for k in 3:
				for side: float in [-1.0, 1.0]:
					box(windows, xf, Vector3(side * (w * 0.5 + 0.03), h * 0.5, -d * 0.3 + k * d * 0.3), Vector3(0.06, 3.0, 1.0), Color.WHITE)
			box(windows, xf, tower + Vector3(0.0, h + 5.0, 2.33), Vector3(1.0, 1.6, 0.06), Color.WHITE)
		_:
			# Houses, the farmhouse and the pub: a pitched roof, a chimney, a door, windows.
			box(walls, xf, Vector3(0.0, (h - 0.5) * 0.5, 0.0), Vector3(w, h + 0.5, d), wall)
			var pitch := d * 0.42
			prism(roofs, walls, xf, Vector3(0.0, h, 0.0), w * 0.5 + 0.35, d * 0.5 + 0.35, pitch, false, roof, wall)
			box(walls, xf, Vector3(w * 0.3, h + pitch * 0.55, 0.0), Vector3(0.7, pitch + 1.2, 0.8), BRICK)
			box(walls, xf, Vector3(0.0, 1.05, d * 0.5 + 0.03), Vector3(1.0, 2.1, 0.06), DOOR)
			var floors := 2 if h > 4.8 else 1
			for f in floors:
				var y := 1.5 + f * 2.7
				for x: float in ([-w * 0.28, w * 0.28] if f == 0 else [-w * 0.28, 0.0, w * 0.28]):
					box(windows, xf, Vector3(x, y, d * 0.5 + 0.03), Vector3(1.1, 1.2, 0.06), Color.WHITE)
					box(windows, xf, Vector3(x, y, -d * 0.5 - 0.03), Vector3(1.1, 1.2, 0.06), Color.WHITE)
				for side: float in [-1.0, 1.0]:
					box(windows, xf, Vector3(side * (w * 0.5 + 0.03), y, 0.0), Vector3(0.06, 1.2, 1.0), Color.WHITE)
			if kind == "pub":
				# The pub's sign board over the door.
				box(walls, xf, Vector3(-w * 0.32, h - 0.9, d * 0.5 + 0.6), Vector3(1.2, 0.8, 0.08), Color(0.3, 0.12, 0.08))
				box(walls, xf, Vector3(-w * 0.32, h - 0.4, d * 0.5 + 0.3), Vector3(0.08, 0.08, 0.7), SHUTTER)


## A face through `pts` (in order round it), turned to face `outward`.
static func face(st: SurfaceTool, pts: Array, outward: Vector3, color: Color) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var n := (c - a).cross(b - a)
	var flip := n.dot(outward) < 0.0
	if n.length_squared() < 1e-10:
		return
	n = n.normalized() * (-1.0 if flip else 1.0)
	for k in range(1, pts.size() - 1):
		var tri := [pts[0], pts[k], pts[k + 1]]
		if flip:
			tri = [pts[0], pts[k + 1], pts[k]]
		for v in tri:
			st.set_color(color)
			st.set_normal(n)
			st.add_vertex(v)


## A box of `size` centred at `center` in `xf`'s frame.
static func box(st: SurfaceTool, xf: Transform3D, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c := []
	for k in 8:
		c.append(xf * (center + Vector3(h.x * (1 if k & 1 else -1), h.y * (1 if k & 2 else -1), h.z * (1 if k & 4 else -1))))
	var mid: Vector3 = xf * center
	for q in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		var pts := [c[q[0]], c[q[1]], c[q[2]], c[q[3]]]
		var fc: Vector3 = (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
		face(st, pts, fc - mid, color)


## A pitched roof on top of `base` (in `xf`'s frame): eaves `hx` by `hz` out from the middle,
## the ridge `rise` above them along x (or along z with `along_z`). Its gable ends go in `ends`.
static func prism(st: SurfaceTool, ends: SurfaceTool, xf: Transform3D, base: Vector3, hx: float, hz: float, rise: float,
		along_z: bool, color: Color, end_color: Color) -> void:
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * (base + Vector3(x, y, z))
	var mid: Vector3 = p.call(0.0, rise * 0.4, 0.0)
	if not along_z:
		var fl: Vector3 = p.call(-hx, 0.0, hz)
		var fr: Vector3 = p.call(hx, 0.0, hz)
		var bl: Vector3 = p.call(-hx, 0.0, -hz)
		var br: Vector3 = p.call(hx, 0.0, -hz)
		var rl: Vector3 = p.call(-hx, rise, 0.0)
		var rr: Vector3 = p.call(hx, rise, 0.0)
		face(st, [fl, fr, rr, rl], (fl + rr) * 0.5 - mid, color)
		face(st, [bl, br, rr, rl], (bl + rr) * 0.5 - mid, color)
		face(st, [fl, bl, br, fr], Vector3.DOWN, color.darkened(0.3))
		face(ends, [fl, bl, rl], (fl + bl) * 0.5 - mid, end_color)
		face(ends, [fr, br, rr], (fr + br) * 0.5 - mid, end_color)
	else:
		var lf: Vector3 = p.call(-hx, 0.0, hz)
		var lb: Vector3 = p.call(-hx, 0.0, -hz)
		var rf: Vector3 = p.call(hx, 0.0, hz)
		var rb: Vector3 = p.call(hx, 0.0, -hz)
		var tf: Vector3 = p.call(0.0, rise, hz)
		var tb: Vector3 = p.call(0.0, rise, -hz)
		face(st, [lf, lb, tb, tf], (lf + tb) * 0.5 - mid, color)
		face(st, [rf, rb, tb, tf], (rf + tb) * 0.5 - mid, color)
		face(st, [lf, lb, rb, rf], Vector3.DOWN, color.darkened(0.3))
		face(ends, [lf, rf, tf], (lf + rf) * 0.5 - mid, end_color)
		face(ends, [lb, rb, tb], (lb + rb) * 0.5 - mid, end_color)


## A cylinder or cone standing on `xf`'s origin: radius r0 at the bottom, r1 at the top,
## `height` tall, with `segs` sides (turned `turn`), and a lid when `lid`.
static func cylinder(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, height: float, segs: int, color: Color,
		lid: bool, turn := 0.0) -> void:
	var axis_mid: Vector3 = xf * Vector3(0.0, height * 0.5, 0.0)
	for i in segs:
		var a0 := turn + TAU * i / segs
		var a1 := turn + TAU * (i + 1) / segs
		var b0: Vector3 = xf * Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var b1: Vector3 = xf * Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var t0: Vector3 = xf * Vector3(cos(a0) * r1, height, sin(a0) * r1)
		var t1: Vector3 = xf * Vector3(cos(a1) * r1, height, sin(a1) * r1)
		var out: Vector3 = (b0 + b1 + t0 + t1) * 0.25 - axis_mid
		if r1 < 0.001:
			face(st, [b0, b1, t0], out, color)
		else:
			face(st, [b0, b1, t1, t0], out, color)
		if lid and r1 > 0.01:
			var top: Vector3 = xf * Vector3(0.0, height, 0.0)
			face(st, [top, t0, t1], (xf.basis * Vector3.UP), color)


## A lumpy ball at `center`, `scale` in size: a faceted sphere pushed in and out by noise
## (`rough` of its radius), different for each `seed_value`.
static func blob(st: SurfaceTool, center: Vector3, scale: Vector3, seed_value: int, rough := 0.18) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.3
	var rings := 6
	var segs := 10
	var pts := []
	for i in rings + 1:
		var theta := PI * i / rings
		var row := []
		for j in segs:
			var phi := TAU * j / segs + (0.3 if i % 2 == 1 else 0.0)
			var dir := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var r := 1.0 + noise.get_noise_3dv(dir * 1.5) * rough * 2.0
			if i == rings:
				r = minf(r, 0.85)   # a flatter base
			row.append(center + dir * r * scale)
		pts.append(row)
	var color := Color.WHITE
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % segs]
			var c: Vector3 = pts[i + 1][(j + 1) % segs]
			var d: Vector3 = pts[i + 1][j]
			if i == 0:
				face(st, [a, c, d], (a + c + d) / 3.0 - center, color)
			elif i == rings - 1:
				face(st, [a, b, d], (a + b + d) / 3.0 - center, color)
			else:
				face(st, [a, b, c], (a + b + c) / 3.0 - center, color)
				face(st, [a, c, d], (a + c + d) / 3.0 - center, color)
