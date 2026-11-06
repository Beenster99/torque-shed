class_name RegionCity
extends RefCounted
## A town's or a city's buildings in their region's own city styles (data/region_kits.json "city", by share): British
## terraces with bay windows and chimney stacks, sandstone tenements, Parisian mansard blocks, narrow gabled town
## houses, plain modern blocks (with balconies where the region has them), glass towers, panel blocks, shophouses with
## their arcades and signboards, flat-roofed courtyard houses, residential high-rises, arcaded streets. Each building
## takes a style its height suits, its own colour from the style's palette, and its own roofline, rooftop and ground
## floor, so no two streets look alike; North America's brownstones and Art Deco blocks stepping back as they climb.
## Written into AdventureProps' plain arrays as RegionBuildings does.

const SKIRT := AdventureProps.SKIRT
## The heights (m) each style is built to, [lowest, highest].
const HEIGHTS := {
	"terrace": [0.0, 12.0], "tenement": [7.0, 21.0], "mansard": [10.0, 28.0], "gabled": [0.0, 18.0],
	"modern": [0.0, 45.0], "tower": [24.0, INF], "panel": [10.0, 55.0], "shophouse": [0.0, 16.0],
	"courtyard": [0.0, 14.0], "highrise": [18.0, INF], "arcade": [0.0, 21.0],
	"brownstone": [7.0, 19.0], "deco": [16.0, INF],
}
## The styles a house (not a block) of a town may be built in: the low, street-front ones.
const LOW := ["terrace", "gabled", "shophouse", "arcade", "courtyard", "tenement", "brownstone"]
## More windows than this on a building and its floors are drawn as bands of glass instead (towers stay light).
const MOST_WINDOWS := 260
const CONCRETE := Color(0.72, 0.71, 0.68)
const DARK := Color(0.13, 0.13, 0.14)


## The style building `kind` (RealPack's), `h` tall with a `w` x `d` footprint, takes in `kit`'s city, or {} when it
## isn't a city building (a house out of town, a barn, a place of worship): picked by `roll` (0..1) among the styles
## whose heights suit it, by their shares.
static func style_for(kit: Dictionary, kind: String, w: float, d: float, h: float, roll: float) -> Dictionary:
	var styles: Array = kit.get("city", [])
	if styles.is_empty():
		return {}
	var urban := str(kit.get("density", "")) in ["town", "city"]
	var low := false
	match kind:
		"block", "shop", "civic":
			pass
		"house":
			# A town house of two storeys or more, or one of a row (long and narrow), stands on a street.
			var row := maxf(w, d) > 12.0 and maxf(w, d) > 2.2 * minf(w, d)
			if not urban or not (h >= 6.5 or row):
				return {}
			low = true
		_:
			return {}
	var fits := []
	var total := 0.0
	for s: Dictionary in styles:
		var name := str(s.get("style", ""))
		var hs: Array = HEIGHTS.get(name, [0.0, INF])
		if h < float(hs[0]) or h > float(hs[1]) or (low and not name in LOW):
			continue
		fits.append(s)
		total += float(s.get("share", 1.0))
	if fits.is_empty():
		if low:
			return {}
		return {"style": "tower" if h >= 24.0 else "modern"}
	var at := roll * total
	for s: Dictionary in fits:
		at -= float(s.get("share", 1.0))
		if at <= 0.0:
			return s
	return fits[-1]


## Building `kind` in city style `style` (style_for) into `a` at `xf` (its origin SKIRT under the ground at its middle,
## local +z its front), `w` x `d`, `h` tall.
static func build(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kind: String, style: Dictionary, kit: Dictionary,
		rng: RandomNumberGenerator) -> void:
	# The street front along the long side.
	if w < d:
		xf = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		var t := w
		w = d
		d = t
	var wall: Color = _jitter(RegionKit.pick(rng, style.get("walls", kit["walls"])), rng)
	var roof: Color = RegionKit.pick(rng, style.get("roofs", kit["roofs"]))
	var trim: Color = style.get("trim", kit["trim"])
	var glass: Color = style.get("glass", kit["glass"])
	var shop := kind == "shop" or (kind != "civic" and rng.randf() < 0.35)
	match str(style.get("style", "modern")):
		"terrace":
			_terrace(a, xf, w, d, h, wall, roof, trim, glass, kit, rng)
		"tenement":
			_tenement(a, xf, w, d, h, wall, roof, trim, glass, shop, kit, rng)
		"mansard":
			_mansard(a, xf, w, d, h, wall, roof, trim, glass, shop, kit, rng)
		"gabled":
			_gabled(a, xf, w, d, h, style, roof, trim, glass, shop, kit, rng)
		"tower":
			_tower(a, xf, w, d, h, wall, glass, rng)
		"panel":
			_panel(a, xf, w, d, h, wall, glass, rng)
		"shophouse":
			_shophouse(a, xf, w, d, h, style, trim, glass, kit, rng)
		"courtyard":
			_courtyard(a, xf, w, d, h, wall, trim, glass, kit, rng)
		"highrise":
			_highrise(a, xf, w, d, h, wall, glass, kit, rng)
		"arcade":
			_arcade(a, xf, w, d, h, wall, roof, trim, glass, kit, rng)
		"brownstone":
			_brownstone(a, xf, w, d, h, wall, trim, glass, shop, kit, rng)
		"deco":
			_deco(a, xf, w, d, h, wall, trim, glass, shop, kit, rng)
		_:
			_modern(a, xf, w, d, h, wall, glass, bool(style.get("balconies", false)), shop, kit, rng)


# ---------------------------------------------------------------------------- the styles

## A row of terraced houses: a house every five metres or so, each its own shade and door colour, with a bay window,
## and chimney stacks along the ridge at the party walls.
static func _terrace(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, roof: Color, trim: Color,
		glass: Color, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var floors := clampi(int(h / 2.9), 2, 3)
	var top := floors * 2.9
	var n := maxi(1, roundi(w / 5.2))
	var uw := w / n
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	for u in n:
		var ux := (float(u) + 0.5) * uw - w * 0.5
		var c := _jitter(wall, rng, 0.05)
		AdventureProps.box(a, xf.translated_local(Vector3(ux, 0, 0)), Vector3(uw, top + SKIRT, d), c, false)
		var door: Color = RegionKit.pick(rng, kit["door"])
		var dx := ux + uw * (0.3 if u % 2 == 0 else -0.3)
		var bx := ux - uw * (0.18 if u % 2 == 0 else -0.18)
		RegionBuildings._plate(a, body, Vector3(dx, 0, d * 0.5), Vector2(0.95, 2.1), door)
		RegionBuildings._plate(a, body, Vector3(dx, 2.1, d * 0.5), Vector2(1.15, 0.25), trim)
		# The bay window, its glass on three sides and a little roof of its own.
		var bay := body.translated_local(Vector3(bx, 0, d * 0.5 + 0.35))
		AdventureProps.box(a, bay, Vector3(2.2, 2.5, 0.7), c.darkened(0.04))
		RegionBuildings._plate(a, bay, Vector3(0, 0.8, 0.35), Vector2(1.8, 1.4), WindowLights.mark(glass, bay * Vector3(0, 0.8, 0.35)))
		AdventureProps.box(a, bay.translated_local(Vector3(0, 2.5, 0)), Vector3(2.35, 0.18, 0.85), roof)
		for f in range(1, floors):
			for sx: float in [-0.22, 0.22]:
				RegionBuildings._plate(a, body, Vector3(ux + sx * uw, 0.9 + f * 2.9, d * 0.5), Vector2(1.0, 1.35), trim)
				RegionBuildings._plate(a, body, Vector3(ux + sx * uw, 0.98 + f * 2.9, d * 0.5 + 0.01), Vector2(0.84, 1.2), WindowLights.mark(glass, body * Vector3(ux + sx * uw, 0.98 + f * 2.9, d * 0.5 + 0.01)))
		for f in floors:
			RegionBuildings._plate(a, body, Vector3(ux, 0.9 + f * 2.9, d * 0.5), Vector2(1.0, 1.2), WindowLights.mark(glass, body * Vector3(ux, 0.9 + f * 2.9, d * 0.5)), -1.0)
	var rise := d * 0.5 * float(kit["pitch"]) * RegionBuildings.RISE * 0.8
	RegionBuildings._roof(a, body, w, d, top, "gable", float(kit["pitch"]) * 0.8, 0.15, roof, wall, rng, kit)
	for u in range(0, n + 1):
		var px := clampf(float(u) * uw - w * 0.5, -w * 0.5 + 0.5, w * 0.5 - 0.5)
		AdventureProps.box(a, body.translated_local(Vector3(px, top + rise * 0.6, 0)), Vector3(0.9, rise * 0.4 + 1.1, 0.7), wall.darkened(0.2))


## A sandstone tenement: three to five storeys of even windows, a string course over the ground floor and a cornice at
## the top, a shallow slate roof with broad chimney stacks, shops along the ground floor of some.
static func _tenement(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, roof: Color, trim: Color,
		glass: Color, shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := 3.3
	var floors := clampi(int(h / fh), 3, 6)
	var top := floors * fh
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	var band := wall.darkened(0.12)
	AdventureProps.box(a, body.translated_local(Vector3(0, fh - 0.15, 0)), Vector3(w + 0.16, 0.25, d + 0.16), band)
	AdventureProps.box(a, body.translated_local(Vector3(0, top - 0.4, 0)), Vector3(w + 0.4, 0.45, d + 0.4), band)
	_windows(a, body, w, d, floors, fh, 1 if shop else 0, 1.0, 1.7, 2.6, glass, band, false)
	if shop:
		_shopfronts(a, body, w, d, kit, glass, rng)
	else:
		var close := body.translated_local(Vector3(0, 0, 0))
		RegionBuildings._plate(a, close, Vector3(0, 0, d * 0.5), Vector2(1.4, 2.6), RegionKit.pick(rng, kit["door"]))
	RegionBuildings._roof(a, body, w, d, top, "gable", 0.35, 0.1, roof, wall, rng, kit)
	var rise := d * 0.5 * 0.35 * RegionBuildings.RISE
	var n := maxi(1, roundi(w / 9.0))
	for u in range(0, n + 1):
		var px := clampf(float(u) / n * w - w * 0.5, -w * 0.5 + 1.0, w * 0.5 - 1.0)
		AdventureProps.box(a, body.translated_local(Vector3(px, top, 0)), Vector3(2.0, rise + 1.2, 0.8), wall.darkened(0.08))


## A Parisian block: pale stone, tall windows, balconies along the second floor and the top, a zinc mansard roof with
## dormers.
static func _mansard(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, roof: Color, trim: Color,
		glass: Color, shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := 3.2
	var floors := clampi(int((h - 3.0) / fh), 3, 7)
	var top := floors * fh
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	_windows(a, body, w, d, floors, fh, 1 if shop else 0, 1.1, 2.0, 2.5, glass, trim, false)
	if shop:
		_shopfronts(a, body, w, d, kit, glass, rng)
	var iron := Color(0.12, 0.12, 0.13)
	for f: int in [2, floors - 1]:
		if f >= 1 and f < floors:
			_balcony_strip(a, body, w, d, f * fh, iron, wall)
	AdventureProps.box(a, body.translated_local(Vector3(0, top - 0.3, 0)), Vector3(w + 0.3, 0.3, d + 0.3), wall.darkened(0.1))
	# The mansard: steep slopes up to a flat top, its dormers out of the front and back.
	var inset := 1.0
	var rise := 2.8
	var p := func(x: float, y: float, z: float) -> Vector3: return body * Vector3(x, y, z)
	var b0: Vector3 = p.call(-w * 0.5, top, -d * 0.5)
	var b1: Vector3 = p.call(w * 0.5, top, -d * 0.5)
	var b2: Vector3 = p.call(w * 0.5, top, d * 0.5)
	var b3: Vector3 = p.call(-w * 0.5, top, d * 0.5)
	var t0: Vector3 = p.call(-w * 0.5 + inset, top + rise, -d * 0.5 + inset)
	var t1: Vector3 = p.call(w * 0.5 - inset, top + rise, -d * 0.5 + inset)
	var t2: Vector3 = p.call(w * 0.5 - inset, top + rise, d * 0.5 - inset)
	var t3: Vector3 = p.call(-w * 0.5 + inset, top + rise, d * 0.5 - inset)
	var bz := body.basis.z
	var bx := body.basis.x
	RegionBuildings._face(a, [b3, b2, t2, t3], bz, roof)
	RegionBuildings._face(a, [b0, b1, t1, t0], -bz, roof.darkened(0.06))
	RegionBuildings._face(a, [b1, b2, t2, t1], bx, roof.darkened(0.03))
	RegionBuildings._face(a, [b0, b3, t3, t0], -bx, roof.darkened(0.03))
	RegionBuildings._face(a, [t0, t1, t2, t3], body.basis.y, roof.darkened(0.15))
	var bays := clampi(int(w / 2.5), 1, 12)
	for face: float in [1.0, -1.0]:
		for b in bays:
			var x := ((float(b) + 0.5) / bays - 0.5) * (w - 2.0 * inset)
			var dorm := body.translated_local(Vector3(x, top + 0.6, face * (d * 0.5 - inset * 0.55)))
			AdventureProps.box(a, dorm, Vector3(1.0, 1.4, 0.9), wall)
			RegionBuildings._plate(a, dorm, Vector3(0, 0.15, 0.45 * face), Vector2(0.7, 1.0), WindowLights.mark(glass, dorm * Vector3(0, 0.15, 0.45 * face)), face)
	for k in rng.randi_range(1, 3):
		AdventureProps.box(a, body.translated_local(Vector3(rng.randf_range(-0.4, 0.4) * w, top + rise, rng.randf_range(-0.2, 0.2) * d)),
			Vector3(0.7, 1.2, 1.8), Color(0.62, 0.36, 0.28))


## A street of narrow town houses, each its own height and colour, its gable to the street.
static func _gabled(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, style: Dictionary, roof: Color, trim: Color,
		glass: Color, shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := maxi(1, roundi(w / 6.0))
	var uw := w / n
	var walls: Array = style.get("walls", kit["walls"])
	for u in n:
		var ux := (float(u) + 0.5) * uw - w * 0.5
		var floors := clampi(int(h / 3.0) + rng.randi_range(-1, 1), 2, 5)
		var top := floors * 3.0
		var c := _jitter(RegionKit.pick(rng, walls), rng)
		var uxf := xf.translated_local(Vector3(ux, 0, 0))
		var body := uxf.translated_local(Vector3(0, SKIRT, 0))
		AdventureProps.box(a, uxf, Vector3(uw - 0.04, top + SKIRT, d), c, false)
		_windows(a, body, uw, d, floors, 3.0, 1 if (shop and u % 2 == 0) else 0, 1.0, 1.6, 2.2, glass, trim, false)
		if shop and u % 2 == 0:
			_shopfronts(a, body, uw, d, kit, glass, rng)
		else:
			RegionBuildings._plate(a, body, Vector3(-uw * 0.25, 0, d * 0.5), Vector2(1.0, 2.2), RegionKit.pick(rng, kit["door"]))
		# The ridge from front to back: the gable end faces the street.
		RegionBuildings._gable(a, body, uw - 0.04, d, top, (uw * 0.5) * 1.6, 0.1, RegionKit.pick(rng, style.get("roofs", kit["roofs"])), c)
		RegionBuildings._plate(a, body, Vector3(0, top + uw * 0.3, d * 0.5), Vector2(0.8, 1.0), WindowLights.mark(glass, body * Vector3(0, top + uw * 0.3, d * 0.5)))


## A modern block: render or concrete, a band of windows round every floor, a glazed ground floor for a shop, balconies
## where the region has them, a parapet and the plant room and odds and ends on its flat roof. Some have a ground floor
## clad in another stone, fins up the front, or their top floor or two stepped back behind a terrace.
static func _modern(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, glass: Color, balconies: bool,
		shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := rng.randf_range(3.0, 3.5)
	var floors := clampi(int(h / fh), 1, 16)
	# The top floor or two set back behind a terrace on a block of four or more.
	var back := 0
	if floors >= 4 and minf(w, d) > 9.0 and rng.randf() < 0.35:
		back = 1 if floors < 8 or rng.randf() < 0.6 else 2
	var low := floors - back
	var top := low * fh
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	# Windows in a grid, or in bands as tall as the building's taste.
	var grid := rng.randf() < 0.55
	var wh := rng.randf_range(1.2, 1.9) if grid else rng.randf_range(0.9, 1.6)
	var ww := rng.randf_range(1.1, 2.0)
	var gap := rng.randf_range(2.4, 3.6) if grid else 0.0
	_windows(a, body, w, d, low, fh, 1 if shop else 0, ww, wh, gap, glass, wall.darkened(0.15), true)
	if not shop and rng.randf() < 0.4:
		# A ground floor clad in stone or tile of another colour.
		var base := wall.darkened(0.3) if rng.randf() < 0.5 else CONCRETE.lerp(Color(0.55, 0.5, 0.44), rng.randf())
		AdventureProps.box(a, xf, Vector3(w + 0.12, SKIRT + fh * 0.95, d + 0.12), base, false)
		_windows(a, body, w, d, 1, fh, 0, ww, wh, gap, glass, base.darkened(0.15), true)
	if shop:
		_shopfronts(a, body, w, d, kit, glass, rng)
	if not grid and rng.randf() < 0.3 and low >= 3:
		# Fins up the front between the bands of glass.
		var fin := wall.lightened(0.12) if rng.randf() < 0.6 else DARK
		var n := clampi(int(w / 3.0), 2, 16)
		for k in n + 1:
			var x := (float(k) / n - 0.5) * (w - 0.3)
			AdventureProps.box(a, body.translated_local(Vector3(x, fh, d * 0.5 + 0.2)), Vector3(0.22, top - fh, 0.4), fin)
	if balconies and low >= 2:
		var rail := wall.lightened(0.1) if rng.randf() < 0.5 else DARK
		for f in range(1, low):
			_balconies(a, body, w, d, f * fh, rail, wall)
	if back == 0:
		_flat_top(a, body, w, d, top, wall, kit, rng)
		return
	# The terrace round the set-back floors: a rail along its edge, the floors above with walls of glass.
	AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(w + 0.1, 0.12, d + 0.1), Color(0.42, 0.4, 0.38))
	for side in _sides(body, w, d):
		RegionBuildings._plate(a, side[0], Vector3(0, top + 0.1, side[1]), Vector2(side[2], 1.0), DARK)
	var bw := w - 3.0
	var bd := d - 3.0
	var up := body.translated_local(Vector3(0, top, 0))
	AdventureProps.box(a, up, Vector3(bw, back * fh, bd), wall.lightened(0.06), false)
	_windows(a, up, bw, bd, back, fh, 0, 2.2, 2.2, 3.0, glass, wall.darkened(0.1), true)
	_flat_top(a, up, bw, bd, back * fh, wall, kit, rng)


## A glass tower: a curtain wall with the floors' edges showing, a podium at its foot, and its own top: straight up,
## stepped back once or twice as it climbs, a crown of fins or a sloping glass top, a spire on the tallest, a mast on
## others, and lamps on its corners lit after dark.
static func _tower(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, glass: Color, rng: RandomNumberGenerator) -> void:
	var tint: Color = [glass.lightened(0.15), Color(0.22, 0.32, 0.38), Color(0.3, 0.36, 0.34), Color(0.2, 0.24, 0.3),
		Color(0.36, 0.3, 0.24), Color(0.5, 0.56, 0.6)][rng.randi_range(0, 5)]
	var fh := 3.6
	var floors := clampi(int(h / fh), 6, 90)
	var frame := CONCRETE.lerp(wall, 0.3) if rng.randf() < 0.6 else DARK
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	# The podium: a low skirt, or a block of a few floors of its own with shops.
	var pod := 7.0
	if minf(w, d) > 22.0 and rng.randf() < 0.45:
		pod = fh * rng.randi_range(2, 4)
		AdventureProps.box(a, xf, Vector3(w + 2.0, SKIRT + pod, d + 2.0), frame.lerp(tint, 0.3), false)
		_windows(a, body, w + 2.0, d + 2.0, int(pod / fh), fh, 0, 3.0, 2.4, 4.0, glass, frame, true)
		AdventureProps.box(a, body.translated_local(Vector3(0, pod, 0)), Vector3(w + 2.1, 0.3, d + 2.1), frame.darkened(0.1))
	else:
		AdventureProps.box(a, xf, Vector3(w + 1.0, SKIRT + pod, d + 1.0), frame)
	# Its tiers: straight up, or stepped back once or twice on a tall one.
	var tiers := 1
	if floors >= 18 and rng.randf() < 0.45:
		tiers = 2 if floors < 36 or rng.randf() < 0.5 else 3
	var tw := w
	var td := d
	var from := 0
	var top := 0.0
	for t in tiers:
		var to := floors if t == tiers - 1 else int(floors * (0.55 + 0.25 * t))
		var y0 := from * fh
		top = to * fh
		var at := body.translated_local(Vector3(0, y0, 0))
		AdventureProps.box(a, at if t > 0 else xf, Vector3(tw, top - y0 + (0.0 if t > 0 else SKIRT), td), tint, false)
		# The floors' edges, every floor or every other on a tall one.
		var every := 1 if floors <= 30 else 2
		for f in range(maxi(from, 2), to, every):
			for side in _sides(body, tw, td):
				RegionBuildings._plate(a, side[0], Vector3(0, f * fh - 0.25, side[1]), Vector2(side[2] + 0.04, 0.35), frame)
		# A few lit windows' worth of glass marked on each floor, so it has its pattern after dark.
		for f in range(maxi(from, 2), to, 2 if floors > 40 else 1):
			for side in _sides(body, tw, td):
				var n := maxi(1, int(float(side[2]) / 6.0))
				for k in n:
					var x := ((float(k) + 0.5) / n - 0.5) * float(side[2])
					var p := Vector3(x, f * fh + 0.9, float(side[1]) + 0.01)
					RegionBuildings._plate(a, side[0], p, Vector2(float(side[2]) / n - 0.6, 2.0), WindowLights.mark(tint, side[0] * p))
		if t < tiers - 1:
			AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(tw + 0.2, 0.5, td + 0.2), frame)
			tw *= rng.randf_range(0.7, 0.82)
			td *= rng.randf_range(0.7, 0.82)
		from = to
	var crown := body.translated_local(Vector3(0, top, 0))
	match rng.randi_range(0, 3):
		0:
			# A plant room behind a screen.
			AdventureProps.box(a, crown, Vector3(tw * 0.7, 3.5, td * 0.7), frame)
		1:
			# A crown of fins standing proud of the roof.
			var n := clampi(int(tw / 2.5), 3, 12)
			for side in _sides(crown, tw, td):
				for k in n + 1:
					var x := (float(k) / n - 0.5) * (float(side[2]) - 0.3)
					AdventureProps.box(a, (side[0] as Transform3D).translated_local(Vector3(x, 0, float(side[1]) - 0.15)), Vector3(0.25, 6.0, 0.3), frame)
		2:
			# A sloping glass top.
			RegionBuildings._roof(a, crown, tw, td, 0.0, "hip", 0.9, 0.0, tint.lightened(0.1), tint, rng, {})
		_:
			# A stepped top, each step a little smaller.
			for k in 3:
				var f := 0.8 - 0.2 * k
				AdventureProps.box(a, crown.translated_local(Vector3(0, k * 2.5, 0)), Vector3(tw * f, 2.5, td * f), frame if k % 2 == 0 else tint)
	if top > 140.0 and rng.randf() < 0.6:
		AdventureProps.cone(a, crown, minf(tw, td) * 0.12, 0.0, top * 0.18, Color(0.72, 0.73, 0.75), 6)
	elif rng.randf() < 0.5:
		AdventureProps.box(a, crown.translated_local(Vector3(0, 3.5, 0)), Vector3(0.25, 8.0, 0.25), Color(0.7, 0.7, 0.72))
	# Lamps on its corners for the aircraft, lit after dark as a window is.
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			var p := Vector3(cx * (tw - 0.4), 0.0, cz * (td - 0.4))
			AdventureProps.box(a, crown.translated_local(p), Vector3(0.35, 0.35, 0.35), Color(0.75, 0.08, 0.06, float(WindowLights.LOW) / 255.0))


## A panel block: rows of identical windows, columns of balconies up the front, a flat roof.
static func _panel(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, glass: Color, rng: RandomNumberGenerator) -> void:
	var fh := 2.8
	var floors := clampi(int(h / fh), 4, 20)
	var top := floors * fh
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	_windows(a, body, w, d, floors, fh, 0, 1.4, 1.4, 3.0, glass, wall.darkened(0.2), true)
	# The joints between the panels, and the balconies, some glazed in.
	for f in range(1, floors):
		RegionBuildings._plate(a, body, Vector3(0, f * fh - 0.05, d * 0.5 + 0.01), Vector2(w, 0.1), wall.darkened(0.25))
	var cols := clampi(int(w / 9.0), 1, 5)
	for c in cols:
		var x := ((float(c) + 0.5) / cols - 0.5) * w
		for f in range(1, floors):
			var col := wall.lightened(0.08) if (c + f) % 3 != 0 else Color(0.5, 0.56, 0.6)
			AdventureProps.box(a, body.translated_local(Vector3(x, f * fh, d * 0.5 + 0.6)), Vector3(3.0, 1.1, 1.2), col, false)
	AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(w + 0.2, 0.4, d + 0.2), wall.darkened(0.1))
	AdventureProps.box(a, body.translated_local(Vector3(w * 0.3 * (rng.randf() - 0.5), top, 0)), Vector3(4.0, 2.4, 4.0), wall.darkened(0.15))


## A row of shophouses: narrow fronts, each its own colour, the upper floors over an arcade on pillars, a signboard
## over each shop, shutters at the windows above.
static func _shophouse(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, style: Dictionary, trim: Color, glass: Color,
		kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := maxi(1, roundi(w / 5.0))
	var uw := w / n
	var walls: Array = style.get("walls", kit["walls"])
	var shutters: Array = kit["shutters"]
	var fascia: Array = kit["shop"]["fascia"]
	var deep := minf(2.0, d * 0.25)
	for u in n:
		var ux := (float(u) + 0.5) * uw - w * 0.5
		var floors := clampi(int(h / 3.2) + rng.randi_range(-1, 1), 2, 5)
		var top := floors * 3.2
		var c := _jitter(RegionKit.pick(rng, walls), rng)
		var uxf := xf.translated_local(Vector3(ux, 0, 0))
		var body := uxf.translated_local(Vector3(0, SKIRT, 0))
		# The ground floor stands back under the arcade; the floors above come out to the street.
		AdventureProps.box(a, uxf.translated_local(Vector3(0, 0, -deep * 0.5)), Vector3(uw - 0.04, SKIRT + 3.2, d - deep), c.darkened(0.1), false)
		AdventureProps.box(a, body.translated_local(Vector3(0, 3.2, 0)), Vector3(uw - 0.04, top - 3.2, d), c, true)
		RegionBuildings._plate(a, body, Vector3(0, 0.2, d * 0.5 - deep), Vector2(uw * 0.8, 2.6), WindowLights.mark(glass.lightened(0.1), body * Vector3(0, 0.2, d * 0.5 - deep)))
		AdventureProps.box(a, uxf.translated_local(Vector3(-uw * 0.5 + 0.2, 0, d * 0.5 - 0.2)), Vector3(0.35, SKIRT + 3.2, 0.35), c.darkened(0.05))
		RegionBuildings._plate(a, body, Vector3(0, 3.35, d * 0.5), Vector2(uw * 0.85, 0.8), RegionKit.pick(rng, fascia, trim))
		var shutter: Color = RegionKit.pick(rng, shutters, c.darkened(0.3))
		for f in range(1, floors):
			for sx: float in ([0.0] if uw < 4.5 else [-0.22, 0.22]):
				RegionBuildings._plate(a, body, Vector3(sx * uw, 0.8 + f * 3.2, d * 0.5), Vector2(1.0, 1.5), WindowLights.mark(glass, body * Vector3(sx * uw, 0.8 + f * 3.2, d * 0.5)))
				RegionBuildings._plate(a, body, Vector3(sx * uw - 0.75, 0.8 + f * 3.2, d * 0.5 + 0.01), Vector2(0.45, 1.5), shutter)
				RegionBuildings._plate(a, body, Vector3(sx * uw + 0.75, 0.8 + f * 3.2, d * 0.5 + 0.01), Vector2(0.45, 1.5), shutter)
		if str(kit["roof"]) == "flat" or rng.randf() < 0.5:
			AdventureProps.box(a, body.translated_local(Vector3(0, top, d * 0.5 - 0.1)), Vector3(uw - 0.04, 0.8, 0.2), c.lightened(0.1))
		else:
			RegionBuildings._roof(a, body, uw - 0.04, d, top, "gable", 0.45, 0.3, RegionKit.pick(rng, kit["roofs"]), c, rng, kit)


## A courtyard house: thick plain walls, few small windows, an arched door, a parapet round its roof terrace.
static func _courtyard(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, trim: Color, glass: Color,
		kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var floors := clampi(int(h / 3.2), 1, 4)
	var top := floors * 3.2
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	var door: Color = RegionKit.pick(rng, kit["door"])
	RegionBuildings._plate(a, body, Vector3(0, 0, d * 0.5), Vector2(1.6, 2.6), door)
	RegionBuildings._plate(a, body, Vector3(0, 2.6, d * 0.5), Vector2(1.0, 0.4), door)
	RegionBuildings._plate(a, body, Vector3(0, 2.6, d * 0.5 - 0.01), Vector2(2.2, 0.7), trim)
	_windows(a, body, w, d, floors, 3.2, 1, 0.8, 1.0, 4.5, glass.darkened(0.3), trim, true)
	var rail := Color(0.24, 0.22, 0.2)
	for side in _sides(body, w, d):
		AdventureProps.box(a, side[0].translated_local(Vector3(0, top, side[1] - 0.12)), Vector3(side[2], 1.0, 0.24), wall)
	if rng.randf() < 0.4:
		# A room on the roof and its awning.
		AdventureProps.box(a, body.translated_local(Vector3(w * 0.25, top, -d * 0.2)), Vector3(w * 0.35, 2.6, d * 0.4), wall.darkened(0.05))
		RegionBuildings._lean_to(a, body, Vector3(w * 0.25, top + 2.4, -d * 0.2 + d * 0.2), w * 0.35, 1.4, 0.3, RegionKit.pick(rng, kit["shop"]["awning"], rail))
	_rooftop(a, body, w, d, top, kit, rng)


## A residential high-rise: a balcony along every floor front and back, windows round the sides, tanks or a plant room on
## its roof.
static func _highrise(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, glass: Color, kit: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var fh := 3.0
	var floors := clampi(int(h / fh), 6, 50)
	var top := floors * fh
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	_windows(a, body, w, d, floors, fh, 1, 1.4, 1.5, 0.0, glass, wall.darkened(0.15), true)
	var rail := [Color(0.85, 0.85, 0.82), DARK, wall.darkened(0.2), Color(0.4, 0.5, 0.58)][rng.randi_range(0, 3)] as Color
	for f in range(1, floors):
		for face: float in [1.0, -1.0]:
			AdventureProps.box(a, body.translated_local(Vector3(0, f * fh - 0.1, face * (d * 0.5 + 0.6))), Vector3(w - 1.0, 0.15, 1.2), wall.lightened(0.05))
			RegionBuildings._plate(a, body, Vector3(0, f * fh + 0.05, d * 0.5 + 1.17), Vector2(w - 1.0, 1.0), rail, face)
	_flat_top(a, body, w, d, top, wall, kit, rng)


## An arcaded street front: a colonnade along the ground floor, tall shuttered windows with little balconies above, a
## shallow tiled roof or a flat one.
static func _arcade(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, roof: Color, trim: Color,
		glass: Color, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := 3.4
	var floors := clampi(int(h / fh), 2, 6)
	var top := floors * fh
	var deep := minf(2.6, d * 0.3)
	AdventureProps.box(a, xf.translated_local(Vector3(0, 0, -deep * 0.5)), Vector3(w, SKIRT + fh, d - deep), wall.darkened(0.12), false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	AdventureProps.box(a, body.translated_local(Vector3(0, fh, 0)), Vector3(w, top - fh, d), wall, false)
	var bays := clampi(int(w / 3.2), 1, 14)
	for b in bays + 1:
		var x := float(b) / bays * (w - 0.5) - (w - 0.5) * 0.5
		AdventureProps.box(a, xf.translated_local(Vector3(x, 0, d * 0.5 - 0.25)), Vector3(0.5, SKIRT + fh, 0.5), wall)
	RegionBuildings._plate(a, body, Vector3(0, 0.2, d * 0.5 - deep), Vector2(w * 0.85, 2.6), WindowLights.mark(glass.lightened(0.1), body * Vector3(0, 0.2, d * 0.5 - deep)))
	var shutter: Color = RegionKit.pick(rng, kit["shutters"], trim)
	for f in range(1, floors):
		for b in bays:
			var x := ((float(b) + 0.5) / bays - 0.5) * w
			RegionBuildings._plate(a, body, Vector3(x, f * fh + 0.1, d * 0.5), Vector2(1.0, 2.3), WindowLights.mark(glass, body * Vector3(x, f * fh + 0.1, d * 0.5)))
			RegionBuildings._plate(a, body, Vector3(x - 0.72, f * fh + 0.1, d * 0.5 + 0.01), Vector2(0.42, 2.3), shutter)
			RegionBuildings._plate(a, body, Vector3(x + 0.72, f * fh + 0.1, d * 0.5 + 0.01), Vector2(0.42, 2.3), shutter)
			AdventureProps.box(a, body.translated_local(Vector3(x, f * fh, d * 0.5 + 0.35)), Vector3(1.4, 0.12, 0.7), wall.darkened(0.1))
			RegionBuildings._plate(a, body, Vector3(x, f * fh + 0.12, d * 0.5 + 0.67), Vector2(1.4, 0.8), DARK)
	if str(kit["roof"]) == "flat" or rng.randf() < 0.4:
		_flat_top(a, body, w, d, top, wall, kit, rng)
	else:
		RegionBuildings._roof(a, body, w, d, top, "hip", 0.3, 0.5, roof, wall, rng, kit)


## A brownstone row: tall narrow houses of brown stone, each with its stoop of steps up to a raised door, tall windows
## with stone heads, and a heavy cornice along the top; a shop in the raised basement now and then.
static func _brownstone(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, trim: Color, glass: Color,
		shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := 3.4
	var floors := clampi(int(h / fh), 3, 5)
	var top := floors * fh + 1.2
	var n := maxi(1, roundi(w / 6.0))
	var uw := w / n
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	for u in n:
		var ux := (float(u) + 0.5) * uw - w * 0.5
		var c := _jitter(wall, rng, 0.06)
		AdventureProps.box(a, xf.translated_local(Vector3(ux, 0, 0)), Vector3(uw, top + SKIRT, d), c, false)
		var left := u % 2 == 0
		var dx := ux + uw * (0.28 if left else -0.28)
		# The stoop: steps up to the door on the raised first floor, its rails.
		for k in 6:
			AdventureProps.box(a, body.translated_local(Vector3(dx, 0, d * 0.5 + 2.6 - k * 0.42)), Vector3(1.6, 0.22 * (k + 1), 0.45), c.darkened(0.1))
		RegionBuildings._plate(a, body, Vector3(dx, 1.4, d * 0.5), Vector2(1.1, 2.4), RegionKit.pick(rng, kit["door"]))
		RegionBuildings._plate(a, body, Vector3(dx, 3.8, d * 0.5), Vector2(1.5, 0.3), c.darkened(0.2))
		for f in floors:
			var y := 1.6 + f * fh
			for k in (2 if f == 0 else 3):
				var x := ux + (uw * (-0.15 if left else 0.15)) + (k - (0.5 if f == 0 else 1.0)) * 1.35
				if f == 0:
					x = ux - uw * (0.18 if left else -0.18) + (k - 0.5) * 1.3
				RegionBuildings._plate(a, body, Vector3(x, y - 0.1, d * 0.5), Vector2(1.05, 2.15), trim)
				RegionBuildings._plate(a, body, Vector3(x, y, d * 0.5 + 0.01), Vector2(0.85, 1.95), WindowLights.mark(glass, body * Vector3(x, y, d * 0.5)))
				RegionBuildings._plate(a, body, Vector3(x, y + 2.0, d * 0.5 + 0.02), Vector2(1.2, 0.22), c.darkened(0.22))
		if shop and u % 3 == 1:
			RegionBuildings._plate(a, body, Vector3(ux - uw * 0.1, -0.2, d * 0.5 + 0.02), Vector2(uw * 0.4, 1.4), WindowLights.mark(glass.lightened(0.2), body * Vector3(ux, 0, d * 0.5)))
	# The cornice along the top.
	AdventureProps.box(a, body.translated_local(Vector3(0, top - 0.6, d * 0.5 + 0.3)), Vector3(w + 0.2, 0.7, 0.6), trim.darkened(0.15))
	AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(w, 0.1, d), Color(0.3, 0.3, 0.31))
	_rooftop(a, body, w, d, top, kit, rng)


## An Art Deco block: stone or buff brick piers running up between recessed windows, its upper floors stepped back in
## tiers, a crown on the top step.
static func _deco(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, wall: Color, trim: Color, glass: Color,
		shop: bool, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var fh := 3.5
	var floors := clampi(int(h / fh), 5, 70)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	var stone := wall.lerp(Color(0.82, 0.76, 0.62), 0.4)
	var tiers := 1 if floors < 9 else (2 if floors < 24 else 3)
	var tw := w
	var td := d
	var from := 0
	var top := 0.0
	for t in tiers:
		var to := floors if t == tiers - 1 else int(floors * (0.6 + 0.2 * t))
		top = to * fh
		var y0 := from * fh
		var at := body.translated_local(Vector3(0, y0, 0))
		AdventureProps.box(a, at if t > 0 else xf, Vector3(tw, top - y0 + (0.0 if t > 0 else SKIRT), td), stone, false)
		for side in _sides(body, tw, td):
			var len := float(side[2])
			var n := clampi(int(len / 3.2), 2, 24)
			for k in n:
				var x := ((float(k) + 0.5) / n - 0.5) * len
				# A strip of recessed windows and dark spandrels, a pier either side.
				RegionBuildings._plate(a, side[0], Vector3(x, y0 + (fh if t == 0 else 0.3), float(side[1])), Vector2(len / n - 0.9,
					top - y0 - (fh if t == 0 else 0.3) - 0.8), Color(0.2, 0.2, 0.22))
				for f in range(maxi(from, 1), to):
					var p := Vector3(x, f * fh + 0.7, float(side[1]) + 0.01)
					RegionBuildings._plate(a, side[0], p, Vector2(len / n - 1.2, 2.0), WindowLights.mark(glass, side[0] * p))
			for k in n + 1:
				var x := (float(k) / n - 0.5) * len
				AdventureProps.box(a, (side[0] as Transform3D).translated_local(Vector3(x, y0, float(side[1]))), Vector3(0.5, top - y0 + 1.0, 0.3), stone.lightened(0.06))
		AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(tw + 0.3, 0.6, td + 0.3), trim)
		tw *= 0.78
		td *= 0.78
		from = to
	if shop:
		_shopfronts(a, body, w, d, kit, glass, rng)
	var crown := body.translated_local(Vector3(0, top + 0.6, 0))
	AdventureProps.box(a, crown, Vector3(tw, 3.0, td), stone)
	AdventureProps.box(a, crown.translated_local(Vector3(0, 3.0, 0)), Vector3(tw * 0.6, 2.4, td * 0.6), stone.lightened(0.05))
	if floors > 25:
		AdventureProps.cone(a, crown.translated_local(Vector3(0, 5.4, 0)), minf(tw, td) * 0.18, 0.0, floors * 0.6, Color(0.7, 0.71, 0.72), 8)


# ---------------------------------------------------------------------------- the parts

## The windows of a building's floors (from floor `from` up) along its front and back, and its ends too with `ends`
## (a building that stands on its own; a row's ends are its party walls): one every `gap` metres, `ww` by `wh` with a
## surround; or, with gap 0 or too many of them, a band of glass along each floor.
static func _windows(a: Dictionary, body: Transform3D, w: float, d: float, floors: int, fh: float, from: int, ww: float, wh: float,
		gap: float, glass: Color, surround: Color, ends: bool) -> void:
	var sides := _sides(body, w, d)
	if not ends:
		sides = [sides[0], sides[1]]
	var count := 0
	if gap > 0.0:
		for side in sides:
			count += maxi(1, int(float(side[2]) / gap)) * (floors - from)
	var bands := gap <= 0.0 or count > MOST_WINDOWS
	# (windows drawn one by one are drawn close to only: from further off, the bands of glass a["far"] has, where it has
	# them, are drawn in their place: see RoadStreamer.FINE_REACH)
	var far: Dictionary = a.get("far", {}) if not bands else {}
	for side in sides:
		var sxf: Transform3D = side[0]
		var z: float = side[1]
		var len: float = side[2]
		var n := maxi(1, int(len / maxf(gap, 0.1)))
		for f in range(from, floors):
			var y := f * fh + (fh - wh) * 0.55
			if bands:
				RegionBuildings._plate(a, sxf, Vector3(0, y, z), Vector2(len - 1.0, wh), WindowLights.mark(glass, sxf * Vector3(0, y, z)))
				continue
			if not far.is_empty():
				RegionBuildings._plate(far, sxf, Vector3(0, y, z), Vector2(len - 1.0, wh), WindowLights.mark(glass, sxf * Vector3(0, y, z)))
			for k in n:
				var x := ((float(k) + 0.5) / n - 0.5) * len
				RegionBuildings._plate(a, sxf, Vector3(x, y - 0.1, z), Vector2(ww + 0.2, wh + 0.2), surround)
				RegionBuildings._plate(a, sxf, Vector3(x, y, z + 0.01), Vector2(ww, wh), WindowLights.mark(glass, sxf * Vector3(x, y, z)))


## The shop fronts along a building's ground floor: wide windows, a fascia and an awning for each.
static func _shopfronts(a: Dictionary, body: Transform3D, w: float, d: float, kit: Dictionary, glass: Color, rng: RandomNumberGenerator) -> void:
	var n := maxi(1, roundi(w / 7.0))
	var uw := w / n
	for u in n:
		var x := (float(u) + 0.5) * uw - w * 0.5
		var fascia: Color = RegionKit.pick(rng, kit["shop"]["fascia"], DARK)
		RegionBuildings._plate(a, body, Vector3(x, 0.25, d * 0.5), Vector2(uw - 0.8, 2.3), WindowLights.mark(glass.lightened(0.18), body * Vector3(x, 0.25, d * 0.5)))
		AdventureProps.box(a, body.translated_local(Vector3(x, 2.7, d * 0.5 + 0.08)), Vector3(uw - 0.3, 0.55, 0.16), fascia)
		RegionBuildings._shop_name(a, body, Vector3(x, 2.975, d * 0.5 + 0.17), uw - 1.0, 0.32, fascia, kit, rng)
		if rng.randf() < 0.5:
			RegionBuildings._lean_to(a, body, Vector3(x, 2.65, d * 0.5 + 0.16), uw - 0.6, 1.2, 0.45, RegionKit.pick(rng, kit["shop"]["awning"], fascia))


## A balcony slab and its railing all along the front at height `y`.
static func _balcony_strip(a: Dictionary, body: Transform3D, w: float, d: float, y: float, rail: Color, slab: Color) -> void:
	AdventureProps.box(a, body.translated_local(Vector3(0, y - 0.12, d * 0.5 + 0.4)), Vector3(w - 0.4, 0.14, 0.8), slab.darkened(0.08))
	RegionBuildings._plate(a, body, Vector3(0, y + 0.02, d * 0.5 + 0.77), Vector2(w - 0.4, 0.9), rail)


## A balcony per bay along the front at height `y`.
static func _balconies(a: Dictionary, body: Transform3D, w: float, d: float, y: float, rail: Color, slab: Color) -> void:
	var n := clampi(int(w / 4.5), 1, 8)
	for k in n:
		var x := ((float(k) + 0.5) / n - 0.5) * w
		AdventureProps.box(a, body.translated_local(Vector3(x, y - 0.12, d * 0.5 + 0.55)), Vector3(2.8, 0.14, 1.1), slab.darkened(0.08))
		RegionBuildings._plate(a, body, Vector3(x, y + 0.02, d * 0.5 + 1.07), Vector2(2.8, 0.95), rail)


## A flat roof's parapet and what stands on it.
static func _flat_top(a: Dictionary, body: Transform3D, w: float, d: float, top: float, wall: Color, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var cap := wall.darkened(0.12)
	AdventureProps.box(a, body.translated_local(Vector3(0, top, 0)), Vector3(w + 0.1, 0.12, d + 0.1), Color(0.36, 0.36, 0.37))
	for side in _sides(body, w, d):
		AdventureProps.box(a, side[0].translated_local(Vector3(0, top, side[1] - 0.1)), Vector3(side[2], 0.6 + rng.randf() * 0.4, 0.2), cap)
	_rooftop(a, body, w, d, top, kit, rng)


## The odds and ends on a flat roof: a plant room or a stair head, air-conditioning boxes, water tanks where the region
## has them, an aerial.
static func _rooftop(a: Dictionary, body: Transform3D, w: float, d: float, top: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	if w * d > 120.0 and rng.randf() < 0.7:
		AdventureProps.box(a, body.translated_local(Vector3(rng.randf_range(-0.25, 0.25) * w, top, rng.randf_range(-0.2, 0.2) * d)),
			Vector3(minf(6.0, w * 0.3), 2.6, minf(5.0, d * 0.35)), CONCRETE)
	for k in rng.randi_range(0, 3):
		AdventureProps.box(a, body.translated_local(Vector3(rng.randf_range(-0.4, 0.4) * w, top, rng.randf_range(-0.35, 0.35) * d)),
			Vector3(1.0, 0.8, 0.8), Color(0.78, 0.78, 0.76))
	if rng.randf() < float(kit.get("tanks", 0.0)) * 1.5:
		var tank := body.translated_local(Vector3(rng.randf_range(-0.3, 0.3) * w, top + 0.4, rng.randf_range(-0.3, 0.3) * d))
		AdventureProps.cone(a, tank, 0.7, 0.0, 1.4, Color(0.12, 0.12, 0.13), 8, 0.7)
		AdventureProps.cone(a, tank, 0.7, 1.4, 1.45, Color(0.16, 0.16, 0.17), 8)
	if rng.randf() < 0.3:
		AdventureProps.box(a, body.translated_local(Vector3(rng.randf_range(-0.4, 0.4) * w, top, rng.randf_range(-0.3, 0.3) * d)),
			Vector3(0.08, 3.0, 0.08), Color(0.6, 0.6, 0.62))


## A building's four walls, each as [its frame (local +z out of the wall), the wall's z in it, its length]: the front,
## the back, then the two ends.
static func _sides(body: Transform3D, w: float, d: float) -> Array:
	return [
		[body, d * 0.5, w],
		[body * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), d * 0.5, w],
		[body * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), w * 0.5, d],
		[body * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO), w * 0.5, d],
	]


## `c` a little lighter or darker, warmer or cooler, so a row of the same palette doesn't repeat.
static func _jitter(c: Color, rng: RandomNumberGenerator, amount := 0.08) -> Color:
	var k := rng.randf_range(-amount, amount)
	var out := c.lightened(k) if k > 0.0 else c.darkened(-k)
	return out.lerp(Color(0.85, 0.7, 0.55) if rng.randf() < 0.5 else Color(0.6, 0.66, 0.72), rng.randf() * amount * 0.5)
