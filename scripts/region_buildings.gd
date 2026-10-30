class_name RegionBuildings
extends RefCounted
## A ride's real buildings drawn in their region's kit (RegionKit): the roofs, walls, colours, shutters, balconies,
## verandahs, water tanks, stilts and huts of the place, its shop fronts, and its places of worship by kind (a church
## with a spire, a wooden chapel, an onion-domed church, a bell tower, a mission's twin towers, a mosque and its
## minaret, a mandir, a wat, a pagoda, a temple, a shrine and its torii, a stupa, a synagogue). Written into
## AdventureProps' plain arrays like the rest of a chunk's buildings, so it runs on a worker and one chunk's buildings
## stay one mesh with one shared material.

## How far a building's walls go down under the ground (m), as AdventureProps.SKIRT.
const SKIRT := AdventureProps.SKIRT
## The Maghreb's minarets are square towers; the rest are round.
const SQUARE_MINARETS := ["MA", "DZ", "TN", "EH", "MR", "LY", "ML"]
const GOLD := Color(0.86, 0.68, 0.24)
## The onion domes of central Europe's church towers: copper gone green, dark shingle, red-brown.
const ONION_COLOURS := [Color(0.27, 0.42, 0.35), Color(0.24, 0.22, 0.21), Color(0.42, 0.22, 0.16), Color(0.3, 0.3, 0.32)]
## The share of a country's mapped churches whose towers wear an onion (Germany's only south of ONION_NORTH: Bavaria
## and the south-west; north of it ONION_FAR).
const ONION_CHURCHES := {"AT": 0.65, "LI": 0.5, "SI": 0.45, "SK": 0.4, "CZ": 0.35, "DE": 0.6, "CH": 0.15, "HU": 0.15,
	"PL": 0.12, "HR": 0.2, "IT": 0.03}
const ONION_NORTH := 49.8
const ONION_FAR := 0.03
## A mapped chapel smaller than this (m²) is a wayside shrine.
const WAYSIDE := 40.0
const WHITE := Color(0.95, 0.94, 0.9)
## A kit's "pitch" is its roofs' rise over half their span, over this (1: about 56 degrees, 0.7 about 46).
const RISE := 1.5
## A "house" with a footprint bigger than this (m²) is drawn as a block.
const BIG_HOUSE := 300.0


## A real building (RealPack: its footprint's box, kind and height) into `a`, in kit `kit`: its middle on the ground
## at `pos`, turned `yaw` about up, `w` along local x and `d` along local z, `h` tall.
##
## `look` is what the map says of it (BuildingLooks.of: its roof's shape and colour, its walls', what it is), laid over
## the kit's way; {} draws it as the kit alone would.
static func real_building(a: Dictionary, pos: Vector3, w: float, d: float, yaw: float, h: float, kind: String, kit: Dictionary,
		look := {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([roundi(pos.x * 10.0), roundi(pos.z * 10.0)])
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, -SKIRT, 0.0))
	if not look.is_empty():
		kit = BuildingLooks.dress_kit(kit, look)
		if look.has("class") and mapped(a, xf, w, d, h, str(look["class"]), kit, rng, look):
			return
		if str(look.get("class", "")) == "stilt_house":
			kit["stilts"] = 1.0
	# A town's blocks and street-front houses in the region's city styles.
	var city := RegionCity.style_for(kit, kind, w, d, h, rng.randf())
	if not city.is_empty():
		if look.has("roof_colour") or look.has("wall_colour"):
			city = city.duplicate()
			if look.has("roof_colour"):
				city["roofs"] = [look["roof_colour"]]
			if look.has("wall_colour"):
				city["walls"] = [look["wall_colour"]]
		RegionCity.build(a, xf, w, d, h, kind, city, kit, rng)
		return
	match kind:
		"shed":
			var c: Color = RegionKit.pick(rng, kit["walls"])
			AdventureProps.box(a, xf, Vector3(w, h + SKIRT, d), c.darkened(0.12), false)
			_roof(a, xf, w, d, h + SKIRT, "tin" if str(kit["roof"]) != "flat" else "flat", 0.15, 0.2, RegionKit.pick(rng, kit["roofs"]), c, rng, kit)
		"barn":
			var c: Color = RegionKit.pick(rng, kit["barn"])
			var eaves := h * 0.62 + SKIRT
			AdventureProps.box(a, xf, Vector3(w, eaves, d), c, false)
			_roof(a, xf, w, d, eaves, "gable" if str(kit["roof"]) == "flat" else str(kit["roof"]), 0.4, 0.3, RegionKit.pick(rng, kit["roofs"]), c, rng, kit)
			_plate(a, xf, Vector3(0, SKIRT, d * 0.5), Vector2(minf(3.2, w * 0.5), minf(3.2, h * 0.5)), c.darkened(0.35))
		"industrial":
			var c := Color(0.62, 0.64, 0.62).lerp(RegionKit.pick(rng, kit["walls"]), 0.25)
			AdventureProps.box(a, xf, Vector3(w, h + SKIRT, d), c, false)
			_roof(a, xf, w, d, h + SKIRT, "tin", 0.12, 0.2, Color(0.5, 0.52, 0.54), c, rng, kit)
			_plate(a, xf, Vector3(0, SKIRT, d * 0.5), Vector2(minf(4.0, w * 0.5), minf(3.6, h * 0.8)), c.darkened(0.3))
		"worship":
			worship(a, xf, w, d, h, RegionKit.worship_kind(kit, rng.randf()), kit, rng)
		"shop", "block", "civic":
			_block(a, xf, w, d, h, kind, kit, rng)
		_ when w * d > BIG_HOUSE:
			_block(a, xf, w, d, h, "block", kit, rng)   # (a footprint this big is a hall or a works, not a house)
		_:
			if rng.randf() < float(kit["hut"]) and w * d < 70.0:
				_hut(a, xf, minf(w, d), rng)
			else:
				_house(a, xf, w, d, h, kit, rng)


## A house: walls of the kit's, its roof (pitched, hipped, low tin, or flat with a parapet), a door and windows with
## their shutters, and whatever else the kit has houses wear (a timber upper storey, a balcony, a verandah, a water
## tank and rebar on a flat roof, stilts).
static func _house(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var wall: Color = RegionKit.pick(rng, kit["walls"])
	var roof_c: Color = RegionKit.pick(rng, kit["roofs"])
	var floors := clampi(int(h / 3.0), 1, 4)
	var wall_h := floors * 3.0
	var base := SKIRT
	var stilts := rng.randf() < float(kit["stilts"]) and floors <= 2
	if stilts:
		# Raised on posts, a ladder of steps to the door.
		var post := Color(0.36, 0.26, 0.18)
		for px: float in [-0.5, 0.5]:
			for pz: float in [-0.5, 0.5]:
				AdventureProps.box(a, xf.translated_local(Vector3(px * (w - 0.4), 0, pz * (d - 0.4))), Vector3(0.25, SKIRT + 2.2, 0.25), post)
		base = SKIRT + 2.2
		AdventureProps.box(a, xf.translated_local(Vector3(0, base - 0.15, 0)), Vector3(w + 0.2, 0.15, d + 0.2), post)
	var body := xf.translated_local(Vector3(0, base, 0))
	if stilts:
		AdventureProps.box(a, body, Vector3(w, wall_h, d), wall, false)
	else:
		AdventureProps.box(a, xf, Vector3(w, wall_h + SKIRT, d), wall, false)
	var plinth = kit.get("plinth")
	if plinth is Color and not stilts:
		AdventureProps.box(a, xf.translated_local(Vector3(0, 0, 0)), Vector3(w + 0.06, SKIRT + 0.5, d + 0.06), plinth, false)
	var timber = kit.get("timber")
	if timber is Color and floors >= 2:
		# The upper storey clad in timber, a little proud of the render below.
		AdventureProps.box(a, body.translated_local(Vector3(0, 3.0, 0)), Vector3(w + 0.08, wall_h - 3.0, d + 0.08), timber, false)
	var form := str(kit["roof"])
	if rng.randf() < float(kit["flat"]):
		form = "flat"
	_roof(a, body, w, d, wall_h, form, float(kit["pitch"]), float(kit["eaves"]), roof_c, wall if not (timber is Color) else timber, rng, kit)
	if form != "flat" and rng.randf() < float(kit["chimney"]):
		AdventureProps.box(a, body.translated_local(Vector3(w * 0.3, wall_h, -d * 0.15)), Vector3(0.6, minf(w, d) * float(kit["pitch"]) * RISE * 0.5 + 1.0, 0.6),
			wall.darkened(0.25))
	# The door and windows, front and back, and the shutters either side of each.
	var trim: Color = kit["trim"]
	var glass: Color = kit["glass"]
	var door: Color = RegionKit.pick(rng, kit["door"])
	var shutters: Array = kit["shutters"]
	var shutter: Color = RegionKit.pick(rng, shutters, trim)
	var bays := clampi(int(w / 2.6), 1, 6)
	for f in floors:
		for face: float in [1.0, -1.0]:
			for b in bays:
				var bx := ((float(b) + 0.5) / bays - 0.5) * w
				if f == 0 and face > 0.0 and b == bays / 2:
					_plate(a, body, Vector3(bx, 0.0, d * 0.5), Vector2(1.0, 2.1), door, face)
					_plate(a, body, Vector3(bx, 2.1, d * 0.5), Vector2(1.2, 0.12), trim, face)
					continue
				var y := 0.9 + f * 3.0
				_plate(a, body, Vector3(bx, y - 0.08, d * 0.5), Vector2(1.06, 1.36), trim, face)
				_plate(a, body, Vector3(bx, y, d * 0.5 + 0.01), Vector2(0.9, 1.2), glass, face)
				if not shutters.is_empty():
					for sx: float in [-0.75, 0.75]:
						_plate(a, body, Vector3(bx + sx, y - 0.04, d * 0.5 + 0.02), Vector2(0.45, 1.28), shutter, face)
	# A balcony across the first floor's front.
	if floors >= 2 and rng.randf() < float(kit["balcony"]):
		var rail: Color = timber if timber is Color else trim.darkened(0.1)
		AdventureProps.box(a, body.translated_local(Vector3(0, 2.9, d * 0.5 + 0.55)), Vector3(w * 0.8, 0.14, 1.1), rail)
		AdventureProps.box(a, body.translated_local(Vector3(0, 3.04, d * 0.5 + 1.05)), Vector3(w * 0.8, 0.9, 0.08), rail)
	# A verandah along the front: posts and a lean-to roof.
	if floors <= 2 and rng.randf() < float(kit["verandah"]) and not stilts:
		var vd := 2.2
		var post := trim
		for k in 4:
			var px := (float(k) / 3.0 - 0.5) * (w - 0.3)
			AdventureProps.box(a, body.translated_local(Vector3(px, 0, d * 0.5 + vd)), Vector3(0.14, 2.5, 0.14), post)
		_lean_to(a, body, Vector3(0, 2.75, d * 0.5), w + 0.2, vd + 0.3, 0.45, roof_c)
	if form == "flat":
		if rng.randf() < float(kit["tanks"]):
			var tank := body.translated_local(Vector3(w * 0.25, wall_h + 0.5, -d * 0.2))
			AdventureProps.cone(a, tank, 0.6, 0.0, 1.2, Color(0.12, 0.12, 0.13), 8, 0.6)
			AdventureProps.cone(a, tank, 0.6, 1.2, 1.25, Color(0.16, 0.16, 0.17), 8)
			for sx: float in [-0.4, 0.4]:
				AdventureProps.box(a, body.translated_local(Vector3(w * 0.25 + sx, wall_h, -d * 0.2)), Vector3(0.1, 0.5, 0.9), Color(0.4, 0.4, 0.42))
		if rng.randf() < float(kit["rebar"]):
			# Rebar left sticking up from the corners, for the next floor.
			var steel := Color(0.38, 0.26, 0.2)
			for px: float in [-0.5, 0.5]:
				for pz: float in [-0.5, 0.5]:
					AdventureProps.box(a, body.translated_local(Vector3(px * (w - 0.3), wall_h + 0.4, pz * (d - 0.3))), Vector3(0.05, 1.3, 0.05), steel)


## A shop, a block of flats or offices, a civic building: floors of windows, a flat or pitched roof as the kit's, and
## a shop's front: a wide window, a fascia board and an awning in the place's colours.
static func _block(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kind: String, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var wall: Color = RegionKit.pick(rng, kit["walls"])
	if kind == "civic":
		wall = wall.lerp(Color(0.9, 0.88, 0.84), 0.4)
	var floors := maxi(1, int(h / 3.2))
	var top := floors * 3.2
	AdventureProps.box(a, xf, Vector3(w, top + SKIRT, d), wall, false)
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	var form := str(kit["roof"])
	if floors >= 3 or rng.randf() < float(kit["flat"]) or w * d > 400.0:
		form = "flat"
	_roof(a, body, w, d, top, form, minf(float(kit["pitch"]), 0.5), float(kit["eaves"]), RegionKit.pick(rng, kit["roofs"]), wall, rng, kit)
	var glass: Color = kit["glass"]
	var trim: Color = kit["trim"]
	var bays := clampi(int(w / 3.0), 1, 8)
	for f in floors:
		if kind == "shop" and f == 0:
			continue
		for face: float in [1.0, -1.0]:
			for b in bays:
				var bx := ((float(b) + 0.5) / bays - 0.5) * w
				_plate(a, body, Vector3(bx, 0.9 + f * 3.2, d * 0.5), Vector2(minf(1.4, w / bays * 0.6), 1.3), glass, face)
	if kind == "shop":
		var fascia: Color = RegionKit.pick(rng, kit["shop"]["fascia"], trim)
		var awning: Color = RegionKit.pick(rng, kit["shop"]["awning"], fascia)
		_plate(a, body, Vector3(0, 0.25, d * 0.5), Vector2(w * 0.8, 2.1), glass.lightened(0.15))
		AdventureProps.box(a, body.translated_local(Vector3(0, 2.55, d * 0.5 + 0.08)), Vector3(w * 0.9, 0.6, 0.16), fascia)
		_shop_name(a, body, Vector3(0, 2.85, d * 0.5 + 0.17), w * 0.8, 0.34, fascia, kit, rng)
		_lean_to(a, body, Vector3(0, 2.5, d * 0.5 + 0.16), w * 0.85, 1.3, 0.5, awning)


## A round hut with a thatched cone (rural Africa).
static func _hut(a: Dictionary, xf: Transform3D, size: float, rng: RandomNumberGenerator) -> void:
	var r := clampf(size * 0.5, 2.0, 3.5)
	var mud: Color = [Color(0.66, 0.46, 0.3), Color(0.74, 0.56, 0.38), Color(0.6, 0.42, 0.28)][rng.randi_range(0, 2)]
	AdventureProps.cone(a, xf, r, 0.0, SKIRT + 2.2, mud, 10, r)
	AdventureProps.cone(a, xf, r + 0.6, SKIRT + 2.2, SKIRT + 2.2 + r * 0.9, Color(0.62, 0.52, 0.32), 10)
	_plate(a, xf, Vector3(0, SKIRT, r - 0.02), Vector2(0.8, 1.7), Color(0.2, 0.14, 0.1))


## A place of worship of `kind` (RegionKit.worship_kind) over a `w` x `d` footprint, `h` tall.
static func worship(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kind: String, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var body := xf.translated_local(Vector3(0, SKIRT, 0))
	var long := maxf(w, d)
	var wide := minf(w, d)
	# The long side along local z, the front at +z.
	if w > d:
		body = body * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		xf = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var wall_h := clampf(h * 0.55, 4.0, 9.0)
	var stone: Color = RegionKit.pick(rng, kit["walls"]).lerp(Color(0.82, 0.78, 0.7), 0.4)
	var roof_c: Color = RegionKit.pick(rng, kit["roofs"])
	var glass: Color = kit["glass"]
	match kind:
		"church":
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), stone, false)
			_roof(a, body, wide, long, wall_h, "gable", 0.9, 0.3, roof_c, stone, rng, kit)
			var t := body.translated_local(Vector3(0, -SKIRT, long * 0.5 - 2.2))
			AdventureProps.box(a, t, Vector3(4.4, SKIRT + wall_h + 7.0, 4.4), stone.darkened(0.06))
			AdventureProps.cone(a, t.rotated_local(Vector3.UP, PI * 0.25), 3.2, SKIRT + wall_h + 7.0, SKIRT + wall_h + 17.0, roof_c, 4)
			_plate(a, t, Vector3(0, SKIRT, 2.2), Vector2(1.4, 2.8), Color(0.3, 0.16, 0.1))
			_side_windows(a, body, wide, long, wall_h * 0.4, 2.8, glass)
		"chapel":
			var white := WHITE if rng.randf() < 0.7 else stone
			AdventureProps.box(a, xf, Vector3(wide, wall_h * 0.8 + SKIRT, long), white, false)
			_roof(a, body, wide, long, wall_h * 0.8, "gable", 0.9, 0.3, roof_c, white, rng, kit)
			var t := body.translated_local(Vector3(0, wall_h * 0.8, long * 0.5 - 1.6))
			AdventureProps.box(a, t, Vector3(2.2, wide * 0.45 + 3.0, 2.2), white)
			AdventureProps.cone(a, t.rotated_local(Vector3.UP, PI * 0.25), 1.7, wide * 0.45 + 3.0, wide * 0.45 + 9.0, roof_c, 4)
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(1.4, 2.6), Color(0.3, 0.16, 0.1))
			_side_windows(a, body, wide, long, wall_h * 0.3, 2.2, glass)
		"orthodox":
			var white := WHITE.lerp(stone, 0.3)
			var dome := [Color(0.85, 0.66, 0.22), Color(0.2, 0.42, 0.3), Color(0.24, 0.36, 0.6)][rng.randi_range(0, 2)] as Color
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), white, false)
			_roof(a, body, wide, long, wall_h, "gable", 0.5, 0.2, dome.darkened(0.3), white, rng, kit)
			var drum := body.translated_local(Vector3(0, wall_h + wide * 0.25, 0))
			AdventureProps.cone(a, drum, wide * 0.22, -1.0, 2.5, white, 10, wide * 0.22)
			_onion(a, drum.translated_local(Vector3(0, 2.5, 0)), wide * 0.27, dome)
			var t := body.translated_local(Vector3(0, -SKIRT, long * 0.5 - 1.7))
			AdventureProps.box(a, t, Vector3(3.4, SKIRT + wall_h + 5.0, 3.4), white)
			_onion(a, t.translated_local(Vector3(0, SKIRT + wall_h + 5.0, 0)), 1.6, dome)
			_side_windows(a, body, wide, long, wall_h * 0.4, 2.4, glass)
		"campanile":
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), stone, false)
			_roof(a, body, wide, long, wall_h, "gable", 0.35, 0.3, roof_c, stone, rng, kit)
			var t := body.translated_local(Vector3(wide * 0.5 - 1.8, -SKIRT, long * 0.25))
			AdventureProps.box(a, t, Vector3(3.6, SKIRT + wall_h + 9.0, 3.6), stone.darkened(0.05))
			AdventureProps.box(a, t.translated_local(Vector3(0, SKIRT + wall_h + 6.5, 0)), Vector3(3.7, 1.6, 3.7), Color(0.12, 0.12, 0.13), false)
			AdventureProps.cone(a, t.rotated_local(Vector3.UP, PI * 0.25), 2.7, SKIRT + wall_h + 9.0, SKIRT + wall_h + 11.0, roof_c, 4)
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(1.6, 3.0), Color(0.36, 0.22, 0.12))
			_plate(a, body, Vector3(0, wall_h * 0.6, long * 0.5), Vector2(1.4, 1.4), glass)
		"mission":
			var face := [WHITE, Color(0.92, 0.78, 0.4), Color(0.86, 0.6, 0.5)][rng.randi_range(0, 2)] as Color
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), face, false)
			_roof(a, body, wide, long, wall_h, "flat", 0.0, 0.0, face.darkened(0.15), face, rng, kit)
			# The front: a gable-topped wall between two towers with little domes.
			AdventureProps.box(a, body.translated_local(Vector3(0, 0, long * 0.5 - 0.3)), Vector3(wide, wall_h + 2.0, 0.6), face)
			for sx: float in [-1.0, 1.0]:
				var t := body.translated_local(Vector3(sx * (wide * 0.5 - 1.2), -SKIRT, long * 0.5 - 1.3))
				AdventureProps.box(a, t, Vector3(2.6, SKIRT + wall_h + 6.0, 2.6), face)
				AdventureProps.box(a, t.translated_local(Vector3(0, SKIRT + wall_h + 3.5, 0)), Vector3(2.7, 1.4, 2.7), Color(0.14, 0.12, 0.11), false)
				_dome(a, t.translated_local(Vector3(0, SKIRT + wall_h + 6.0, 0)), 1.3, face.darkened(0.1))
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(2.0, 3.4), Color(0.36, 0.2, 0.1))
		"mosque":
			var face: Color = RegionKit.pick(rng, kit["walls"]).lerp(WHITE, 0.3)
			var dome := [face, Color(0.24, 0.5, 0.46), Color(0.86, 0.68, 0.24)][rng.randi_range(0, 2)] as Color
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), face, false)
			_roof(a, body, wide, long, wall_h, "flat", 0.0, 0.0, face.darkened(0.1), face, rng, kit)
			_dome(a, body.translated_local(Vector3(0, wall_h, 0)), wide * 0.36, dome)
			var t := body.translated_local(Vector3(wide * 0.5 - 1.6, -SKIRT, long * 0.5 - 1.6))
			var tall := SKIRT + wall_h + 12.0
			if kit.get("country", "") in SQUARE_MINARETS:
				AdventureProps.box(a, t, Vector3(3.0, tall, 3.0), face)
				AdventureProps.box(a, t.translated_local(Vector3(0, tall, 0)), Vector3(1.6, 2.4, 1.6), face)
				AdventureProps.box(a, t.translated_local(Vector3(0, tall - 2.4, 0)), Vector3(3.1, 0.5, 3.1), Color(0.24, 0.5, 0.42), false)
				_dome(a, t.translated_local(Vector3(0, tall + 2.4, 0)), 0.8, dome)
			else:
				AdventureProps.cone(a, t, 0.9, 0.0, tall, face, 8, 0.75)
				AdventureProps.cone(a, t, 1.3, tall - 2.5, tall - 2.1, face.darkened(0.1), 8, 1.3)
				AdventureProps.cone(a, t, 0.75, tall, tall + 3.0, dome, 8)
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(1.8, 3.0), Color(0.18, 0.36, 0.34))
		"mandir":
			var face := [WHITE, Color(0.94, 0.62, 0.3), Color(0.9, 0.8, 0.6)][rng.randi_range(0, 2)] as Color
			AdventureProps.box(a, xf, Vector3(wide, wall_h * 0.6 + SKIRT, long), face, false)
			_roof(a, body, wide, long, wall_h * 0.6, "flat", 0.0, 0.0, face.darkened(0.1), face, rng, kit)
			# The shikhara: a tall ribbed tower over the shrine, a flag on top.
			var t := body.translated_local(Vector3(0, wall_h * 0.6, -long * 0.15))
			AdventureProps.cone(a, t, wide * 0.4, 0.0, wide * 0.9 + 4.0, face.darkened(0.05), 8, wide * 0.08)
			AdventureProps.cone(a, t, wide * 0.12, wide * 0.9 + 4.0, wide * 0.9 + 4.8, GOLD, 8)
			AdventureProps.box(a, t.translated_local(Vector3(0.4, wide * 0.9 + 4.6, 0)), Vector3(0.9, 0.5, 0.04), Color(0.95, 0.45, 0.1))
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(1.6, 2.4), Color(0.5, 0.2, 0.1))
		"wat":
			AdventureProps.box(a, xf, Vector3(wide, wall_h * 0.7 + SKIRT, long), WHITE, false)
			var red := Color(0.74, 0.22, 0.14)
			var green := Color(0.2, 0.46, 0.3)
			for tier in 3:
				var tw := wide * (1.0 - tier * 0.18)
				var tl := long * (1.0 - tier * 0.12)
				_roof(a, body.translated_local(Vector3(0, tier * 1.6, 0)), tw, tl, wall_h * 0.7, "gable", 1.3, 0.5, red if tier % 2 == 0 else green, GOLD, rng, kit)
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(1.8, 3.0), Color(0.5, 0.12, 0.08))
		"pagoda", "temple":
			var post := Color(0.62, 0.16, 0.12) if kit.get("country", "") != "JP" else Color(0.36, 0.26, 0.18)
			var tiers := 2 if kind == "pagoda" else 1
			AdventureProps.box(a, xf, Vector3(wide, SKIRT + 0.8, long), Color(0.6, 0.58, 0.54))
			# (the hall a metre in from the platform's edge all round, its broad eaves over the platform)
			wide = maxf(wide - 2.0, 2.0)
			long = maxf(long - 2.0, 2.0)
			var hall := body.translated_local(Vector3(0, 0.8, 0))
			AdventureProps.box(a, hall, Vector3(wide, wall_h * 0.7, long), Color(0.9, 0.88, 0.82), false)
			for k in 4:
				var px := (float(k) / 3.0 - 0.5) * wide
				_plate(a, hall, Vector3(px, 0, long * 0.5), Vector2(0.4, wall_h * 0.7), post)
			for tier in tiers:
				_roof(a, hall.translated_local(Vector3(0, tier * 2.4, 0)), wide * (1.0 - tier * 0.3), long * (1.0 - tier * 0.3), wall_h * 0.7,
					"hip", 0.55, 1.4, Color(0.24, 0.26, 0.3), post, rng, kit)
		"shrine":
			var hall := body.translated_local(Vector3(0, 0, -long * 0.2))
			var small := Vector2(minf(wide, 8.0), minf(long * 0.6, 10.0))
			AdventureProps.box(a, xf.translated_local(Vector3(0, 0, -long * 0.2)), Vector3(small.x, SKIRT + 3.5, small.y), Color(0.86, 0.82, 0.72), false)
			_roof(a, hall, small.x, small.y, 3.5, "gable", 0.7, 0.5, Color(0.3, 0.26, 0.22), Color(0.86, 0.82, 0.72), rng, kit)
			# The torii gate at the front of its ground.
			var torii := body.translated_local(Vector3(0, -SKIRT, long * 0.5 - 0.5))
			var red := Color(0.86, 0.26, 0.12)
			var span := minf(1.6, wide * 0.5 - 1.0)
			for sx: float in [-span, span]:
				AdventureProps.cone(a, torii.translated_local(Vector3(sx, 0, 0)), 0.22, 0.0, SKIRT + 4.4, red, 8, 0.2)
			AdventureProps.box(a, torii.translated_local(Vector3(0, SKIRT + 4.4, 0)), Vector3(span * 2.0 + 2.0, 0.35, 0.4), Color(0.12, 0.1, 0.1))
			AdventureProps.box(a, torii.translated_local(Vector3(0, SKIRT + 3.6, 0)), Vector3(span * 2.0 + 1.0, 0.25, 0.25), red)
		"stupa":
			var t := body
			AdventureProps.box(a, xf, Vector3(wide, SKIRT + 1.5, wide), WHITE)
			_dome(a, t.translated_local(Vector3(0, 1.5, 0)), wide * 0.4, WHITE)
			AdventureProps.box(a, t.translated_local(Vector3(0, 1.5 + wide * 0.38, 0)), Vector3(wide * 0.2, 1.0, wide * 0.2), WHITE.darkened(0.05))
			AdventureProps.cone(a, t, wide * 0.1, 2.5 + wide * 0.38, 2.5 + wide * 0.38 + wide * 0.5 + 2.0, GOLD, 8)
		"onion_church", "onion_chapel":
			# The Alpine and central European kind: white walls, a steep roof, and a tower capped with an onion.
			var white := WHITE.lerp(stone, 0.15)
			var small := kind == "onion_chapel"
			var wh := wall_h * (0.8 if small else 1.0)
			var dome := ONION_COLOURS[rng.randi_range(0, ONION_COLOURS.size() - 1)] as Color
			AdventureProps.box(a, xf, Vector3(wide, wh + SKIRT, long), white, false)
			_roof(a, body, wide, long, wh, "gable", 1.0, 0.3, roof_c, white, rng, kit)
			var t: Transform3D
			var side: float
			var tall: float
			if small:
				# (a turret astride the ridge at the front)
				side = 1.6
				t = body.translated_local(Vector3(0, wh, long * 0.5 - side))
				tall = wide * 0.5 * RISE + 1.6
			else:
				# (a tower at the front, inside the map's outline like everything here, its foot in the ground)
				side = 4.6
				t = body.translated_local(Vector3(0, -SKIRT, long * 0.5 - side * 0.5))
				tall = SKIRT + wh + 9.0
			AdventureProps.box(a, t, Vector3(side, tall, side), white)
			var top := t.translated_local(Vector3(0, tall, 0))
			AdventureProps.box(a, top, Vector3(side * 1.04, 0.3, side * 1.04), white.darkened(0.15))
			_onion(a, top.translated_local(Vector3(0, 0.3, 0)), side * 0.62, dome)
			if not small:
				# (a clock face on each side of the tower, and the belfry's openings)
				for f: float in [1.0, -1.0]:
					_plate(a, t, Vector3(0, tall - 3.4, side * 0.5), Vector2(1.4, 1.4), Color(0.12, 0.13, 0.16), f)
					_plate(a, t.rotated_local(Vector3.UP, PI * 0.5), Vector3(0, tall - 3.4, side * 0.5), Vector2(1.4, 1.4), Color(0.12, 0.13, 0.16), f)
				_plate(a, t, Vector3(0, tall - 6.2, side * 0.5), Vector2(1.2, 1.2), GOLD.darkened(0.2))
			_plate(a, body, Vector3(0, 0, long * 0.5 - (0.0 if small else side)), Vector2(1.4, 2.6), Color(0.3, 0.16, 0.1))
			_side_windows(a, body, wide, long, wh * 0.35, wh * 0.4, glass)
		"cathedral":
			# A long nave, a tower over its crossing, and twin towers at the west front.
			var nave_h := clampf(h * 0.6, 12.0, 26.0)
			AdventureProps.box(a, xf, Vector3(wide, nave_h + SKIRT, long), stone, false)
			_roof(a, body, wide, long, nave_h, "gable", 1.0, 0.3, roof_c, stone, rng, kit)
			var cross := xf.translated_local(Vector3(0, 0, -long * 0.1))
			AdventureProps.box(a, cross, Vector3(wide * 0.55, SKIRT + nave_h + wide * 0.5 * RISE + 4.0, wide * 0.55), stone.darkened(0.04))
			var towers := clampf(h, nave_h + 10.0, 80.0)
			for sx: float in [-1.0, 1.0]:
				var t := body.translated_local(Vector3(sx * (wide * 0.5 - wide * 0.17), -SKIRT, long * 0.5 - wide * 0.17))
				AdventureProps.box(a, t, Vector3(wide * 0.34, SKIRT + towers * 0.78, wide * 0.34), stone.darkened(0.06))
				AdventureProps.cone(a, t.rotated_local(Vector3.UP, PI * 0.25), wide * 0.16, SKIRT + towers * 0.78, SKIRT + towers, roof_c.darkened(0.1), 8)
			_plate(a, body, Vector3(0, wall_h * 0.2, long * 0.5), Vector2(wide * 0.3, wide * 0.3), glass.lightened(0.2))
			_plate(a, body, Vector3(0, 0, long * 0.5), Vector2(2.4, 4.2), Color(0.3, 0.16, 0.1))
			_side_windows(a, body, wide, long, nave_h * 0.35, nave_h * 0.45, glass)
		"wayside":
			# A wayside shrine or a tiny chapel: a whitewashed niche under a little roof, a picture in it.
			var white := WHITE.lerp(stone, 0.1)
			var sw := clampf(wide, 1.2, 4.0)
			var sl := clampf(long, 1.2, 5.0)
			var sh := clampf(h, 2.2, 4.0)
			AdventureProps.box(a, xf, Vector3(sw, sh + SKIRT, sl), white, false)
			_roof(a, body, sw, sl, sh, "gable", 1.0, 0.25, roof_c, white, rng, kit)
			_plate(a, body, Vector3(0, sh * 0.3, sl * 0.5), Vector2(sw * 0.5, sh * 0.45), Color(0.16, 0.18, 0.3))
			_plate(a, body, Vector3(0, sh * 0.36, sl * 0.5 + 0.01), Vector2(sw * 0.3, sh * 0.3), GOLD)
			AdventureProps.box(a, body.translated_local(Vector3(0, sh + sw * 0.5 * RISE + 0.1, sl * 0.5)), Vector3(0.08, 0.7, 0.08), Color(0.2, 0.2, 0.22))
			AdventureProps.box(a, body.translated_local(Vector3(0, sh + sw * 0.5 * RISE + 0.55, sl * 0.5)), Vector3(0.4, 0.08, 0.08), Color(0.2, 0.2, 0.22))
		_:   # a synagogue, and anything else: a stone hall with a small dome
			AdventureProps.box(a, xf, Vector3(wide, wall_h + SKIRT, long), stone, false)
			_roof(a, body, wide, long, wall_h, "flat", 0.0, 0.0, stone.darkened(0.1), stone, rng, kit)
			_dome(a, body.translated_local(Vector3(0, wall_h, 0)), wide * 0.25, Color(0.5, 0.56, 0.6))
			_side_windows(a, body, wide, long, wall_h * 0.35, 2.6, glass)


## A building the map says is something of its own (BuildingLooks: a church, a mosque, a hangar, a trullo, a ger) drawn
## as one in kit `kit`'s way, inside its outline; false where its class has no model of its own (it's drawn by its kind
## as before).
static func mapped(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, cls: String, kit: Dictionary,
		rng: RandomNumberGenerator, look: Dictionary) -> bool:
	var area := w * d
	match cls:
		"church", "monastery":
			worship(a, xf, w, d, h, church_kind(kit, look, rng, "church"), kit, rng)
		"cathedral":
			worship(a, xf, w, d, h, "cathedral" if area > 600.0 else church_kind(kit, look, rng, "church"), kit, rng)
		"chapel":
			worship(a, xf, w, d, h, "wayside" if area < WAYSIDE else church_kind(kit, look, rng, "chapel"), kit, rng)
		"mosque":
			worship(a, xf, w, d, h, "mosque", kit, rng)
		"synagogue":
			worship(a, xf, w, d, h, "synagogue", kit, rng)
		"temple":
			worship(a, xf, w, d, h, temple_kind(kit, rng.randf()), kit, rng)
		"shrine":
			if area < WAYSIDE and str(kit.get("country", "")) != "JP":
				worship(a, xf, w, d, h, "wayside", kit, rng)
			else:
				worship(a, xf, w, d, h, "shrine" if str(kit.get("country", "")) in ["JP", "KR", "TW"] else temple_kind(kit, rng.randf()), kit, rng)
		"hangar":
			_hangar(a, xf, w, d, h, rng)
		"silo", "grain_silo":
			_silos(a, xf, w, d, h)
		"stadium":
			_stadium(a, xf, w, d, h, kit, rng)
		"grandstand":
			_grandstand(a, xf, w, d, h, kit, rng)
		"greenhouse", "glasshouse":
			_greenhouse(a, xf, w, d, h)
		"bunker":
			_bunker(a, xf, w, d)
		"train_station":
			_station(a, xf, w, d, h, kit, rng)
		"trullo":
			_trullo(a, xf, w, d)
		"ger":
			_ger(a, xf, w, d)
		"beach_hut":
			_beach_hut(a, xf, w, d, rng)
		"castle", "fort":
			_keep(a, xf, w, d, h, kit, rng)
		"lighthouse":
			_lighthouse(a, xf, w, d, h)
		"windmill":
			_windmill(a, xf, w, d, h, kit, rng)
		_:
			return false
	return true


## The kind of church a mapped church (or chapel, `base`) is in kit `kit`'s country: an onion-towered one in central
## Europe's share (ONION_CHURCHES), else one of the kit's own Christian kinds by their shares (an Orthodox church in
## Greece, a mission in Mexico), else `base`.
static func church_kind(kit: Dictionary, look: Dictionary, rng: RandomNumberGenerator, base: String) -> String:
	var country := str(kit.get("country", ""))
	var share := float(ONION_CHURCHES.get(country, 0.0))
	if country == "DE" and float(look.get("lat", 0.0)) > ONION_NORTH:
		share = ONION_FAR
	if rng.randf() < share:
		return "onion_" + base
	var shares: Dictionary = kit.get("facts", {}).get("worship", {})
	var christian := {}
	for k in shares:
		if str(k) in ["church", "orthodox", "campanile", "mission"]:
			christian[k] = shares[k]
	if christian.is_empty():
		return base
	var got := RegionKit.worship_kind({"facts": {"worship": christian}}, rng.randf())
	return base if got == "church" else got


## The kind of temple kit `kit`'s country builds (a mandir, a wat, a pagoda), for `roll` (0..1): its non-Christian,
## non-Muslim kinds by their shares, else a plain temple.
static func temple_kind(kit: Dictionary, roll: float) -> String:
	var shares: Dictionary = kit.get("facts", {}).get("worship", {})
	var temples := {}
	for k in shares:
		if str(k) in ["mandir", "wat", "pagoda", "temple", "stupa", "shrine"]:
			temples[k] = shares[k]
	return "temple" if temples.is_empty() else RegionKit.worship_kind({"facts": {"worship": temples}}, roll)


## A barrel-vaulted hangar: low walls, a curved roof of sheet metal, big doors at one end.
static func _hangar(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var frame := xf
	var ww := w
	var dd := d
	if w > d:
		frame = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		ww = d
		dd = w
	var metal := [Color(0.62, 0.64, 0.62), Color(0.42, 0.48, 0.44), Color(0.55, 0.5, 0.42)][rng.randi_range(0, 2)] as Color
	var wall := clampf(h * 0.35, 2.0, 5.0)
	var rise := clampf(ww * 0.3, 2.0, maxf(h - wall, 2.0))
	AdventureProps.box(a, frame, Vector3(ww, wall + SKIRT, dd), metal.darkened(0.1), false)
	_vault(a, frame, ww, dd, SKIRT + wall, rise, metal)
	_plate(a, frame, Vector3(0, SKIRT, dd * 0.5), Vector2(ww * 0.8, wall + rise * 0.6), metal.darkened(0.3))


## A curved roof `rise` high over a `w` x `d` box, its springing line `y` up, curving across x and running along z.
static func _vault(a: Dictionary, xf: Transform3D, w: float, d: float, y: float, rise: float, col: Color) -> void:
	var n := 8
	var p := func(i: int, z: float) -> Vector3:
		var t := float(i) / n
		return xf * Vector3((t - 0.5) * w, y + rise * sin(t * PI), z)
	for i in n:
		var shade := col.darkened(0.08 * absf(float(i) / n - 0.5))
		_face(a, [p.call(i, -d * 0.5), p.call(i + 1, -d * 0.5), p.call(i + 1, d * 0.5), p.call(i, d * 0.5)], xf.basis.y, shade)
	for z: float in [-d * 0.5, d * 0.5]:
		var mid: Vector3 = xf * Vector3(0, y, z)
		for i in n:
			_face(a, [mid, p.call(i, z), p.call(i + 1, z)], xf.basis.z * signf(z), col.darkened(0.15))


## A row of tall round silos along the footprint's long side.
static func _silos(a: Dictionary, xf: Transform3D, w: float, d: float, h: float) -> void:
	var frame := xf if d >= w else xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var r := clampf(minf(w, d) * 0.5, 2.0, 8.0)
	var long := maxf(w, d)
	var n := clampi(int(long / (r * 2.0)), 1, 8)
	var tall := clampf(h, 10.0, 45.0)
	var col := Color(0.76, 0.76, 0.74)
	for k in n:
		var t := frame.translated_local(Vector3(0, 0, ((float(k) + 0.5) / n - 0.5) * long))
		AdventureProps.cone(a, t, r * 0.96, 0.0, SKIRT + tall, col.darkened(0.04 * (k % 2)), 12, r * 0.96)
		AdventureProps.cone(a, t, r * 0.96, SKIRT + tall, SKIRT + tall + r * 0.35, col.darkened(0.12), 12)


## A stadium: banks of stands round the footprint's edge, roofed on the long sides, floodlights at the corners.
static func _stadium(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var tall := clampf(h, 8.0, 40.0)
	var bank := clampf(minf(w, d) * 0.18, 6.0, 40.0)
	var concrete := Color(0.7, 0.69, 0.66)
	var seats: Color = [Color(0.62, 0.12, 0.12), Color(0.14, 0.24, 0.5), Color(0.2, 0.42, 0.24)][rng.randi_range(0, 2)]
	for side in 4:
		var turn := Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3.ZERO)
		var along := w if side % 2 == 0 else d
		var across := d if side % 2 == 0 else w
		var frame := xf * turn
		_stand(a, frame.translated_local(Vector3(0, 0, across * 0.5 - bank * 0.5)), along - bank * 2.0 * (side % 2), bank, tall, concrete, seats,
			side % 2 == 0)
	AdventureProps.box(a, xf, Vector3(w - bank * 2.0, SKIRT + 0.05, d - bank * 2.0), Color(0.24, 0.46, 0.2))
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var t := xf.translated_local(Vector3(c.x * (w - 5.0), 0, c.y * (d - 5.0)))
		AdventureProps.box(a, t, Vector3(0.8, SKIRT + tall + 14.0, 0.8), Color(0.6, 0.62, 0.64))
		AdventureProps.box(a, t.translated_local(Vector3(0, SKIRT + tall + 14.0, 0)), Vector3(4.0, 2.0, 0.6), Color(0.85, 0.85, 0.8))


## A grandstand: one bank of seats over the footprint, its back to -z, a cantilever roof over it.
static func _grandstand(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, _kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var frame := xf if w >= d else xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var seats: Color = [Color(0.62, 0.12, 0.12), Color(0.14, 0.24, 0.5), Color(0.2, 0.42, 0.24)][rng.randi_range(0, 2)]
	_stand(a, frame, maxf(w, d), minf(w, d), clampf(h, 5.0, 25.0), Color(0.7, 0.69, 0.66), seats, true)


## A bank of seats `along` wide and `deep` deep, rising to `tall` at the back (+z), roofed if `roofed`.
static func _stand(a: Dictionary, xf: Transform3D, along: float, deep: float, tall: float, concrete: Color, seats: Color, roofed: bool) -> void:
	var steps := clampi(int(deep / 1.5), 3, 16)
	for k in steps:
		var z := -deep * 0.5 + (float(k) + 0.5) * deep / steps
		var y := SKIRT + tall * 0.7 * (float(k) + 1.0) / steps
		AdventureProps.box(a, xf.translated_local(Vector3(0, 0, z)), Vector3(along, y, deep / steps), seats if k % 2 == 0 else seats.darkened(0.12))
	AdventureProps.box(a, xf.translated_local(Vector3(0, 0, deep * 0.5 - 0.3)), Vector3(along, SKIRT + tall, 0.6), concrete)
	if roofed:
		AdventureProps.box(a, xf.translated_local(Vector3(0, SKIRT + tall, 0)), Vector3(along, 0.4, deep), concrete.lightened(0.1))


## A glasshouse: glass walls and a glass gable roof on a light frame.
static func _greenhouse(a: Dictionary, xf: Transform3D, w: float, d: float, h: float) -> void:
	var glass := Color(0.72, 0.82, 0.8)
	var wall := clampf(h * 0.6, 2.0, 4.0)
	AdventureProps.box(a, xf, Vector3(w, wall + SKIRT, d), glass, false)
	var frame := xf if d >= w else xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	_gable(a, frame.translated_local(Vector3(0, SKIRT, 0)), minf(w, d), maxf(w, d), wall, minf(w, d) * 0.25, 0.05, glass.lightened(0.1), glass)
	var n := clampi(int(maxf(w, d) / 3.0), 2, 30)
	for k in n + 1:
		AdventureProps.box(a, frame.translated_local(Vector3(0, 0, (float(k) / n - 0.5) * maxf(w, d))), Vector3(minf(w, d) + 0.05, SKIRT + wall, 0.08),
			Color(0.9, 0.9, 0.88), false)


## A bunker: a low block of concrete half in the ground, its slit to the front.
static func _bunker(a: Dictionary, xf: Transform3D, w: float, d: float) -> void:
	var concrete := Color(0.55, 0.55, 0.52)
	AdventureProps.box(a, xf, Vector3(w, SKIRT + 1.8, d), concrete)
	AdventureProps.box(a, xf.translated_local(Vector3(0, SKIRT + 1.8, 0)), Vector3(w - 0.6, 0.5, d - 0.6), concrete.darkened(0.08))
	_plate(a, xf, Vector3(0, SKIRT + 1.0, d * 0.5), Vector2(w * 0.5, 0.3), Color(0.06, 0.06, 0.07))


## A railway station: a hall with tall windows and a clock over its door.
static func _station(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var frame := xf if w >= d else xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var ww := maxf(w, d)
	var dd := minf(w, d)
	var wall: Color = RegionKit.pick(rng, kit["walls"]).lerp(Color(0.8, 0.72, 0.6), 0.3)
	var tall := clampf(h, 5.0, 14.0)
	AdventureProps.box(a, frame, Vector3(ww, tall + SKIRT, dd), wall, false)
	var body := frame.translated_local(Vector3(0, SKIRT, 0))
	_roof(a, body, ww, dd, tall, "hip" if str(kit["roof"]) != "flat" else "flat", 0.4, 0.4, RegionKit.pick(rng, kit["roofs"]), wall, rng, kit)
	var bays := clampi(int(ww / 4.0), 2, 12)
	for b in bays:
		_plate(a, body, Vector3(((float(b) + 0.5) / bays - 0.5) * ww, 1.0, dd * 0.5), Vector2(1.6, tall * 0.55), kit["glass"])
	_plate(a, body, Vector3(0, tall * 0.72, dd * 0.5 + 0.02), Vector2(1.2, 1.2), Color(0.95, 0.94, 0.9))
	_plate(a, body, Vector3(0, tall * 0.72 + 0.1, dd * 0.5 + 0.03), Vector2(0.08, 0.5), Color(0.1, 0.1, 0.1))


## A trullo: a whitewashed round wall under a cone of grey stone, a white pinnacle on top (Apulia).
static func _trullo(a: Dictionary, xf: Transform3D, w: float, d: float) -> void:
	var r := clampf(minf(w, d) * 0.5, 1.8, 4.5)
	AdventureProps.cone(a, xf, r, 0.0, SKIRT + 2.4, Color(0.95, 0.94, 0.9), 12, r)
	AdventureProps.cone(a, xf, r * 1.02, SKIRT + 2.4, SKIRT + 2.4 + r * 1.4, Color(0.5, 0.49, 0.46), 12, r * 0.12)
	AdventureProps.cone(a, xf, r * 0.12, SKIRT + 2.4 + r * 1.4, SKIRT + 2.4 + r * 1.4 + 0.7, Color(0.95, 0.94, 0.9), 8)
	_plate(a, xf, Vector3(0, SKIRT, r - 0.05), Vector2(0.9, 1.9), Color(0.3, 0.2, 0.12))


## A ger: a round white felt tent, its low cone of a roof and the door painted orange.
static func _ger(a: Dictionary, xf: Transform3D, w: float, d: float) -> void:
	var r := clampf(minf(w, d) * 0.5, 2.5, 5.0)
	AdventureProps.cone(a, xf, r, 0.0, SKIRT + 1.6, Color(0.93, 0.92, 0.88), 14, r)
	AdventureProps.cone(a, xf, r * 1.03, SKIRT + 1.6, SKIRT + 1.6 + r * 0.4, Color(0.88, 0.86, 0.8), 14, r * 0.15)
	_plate(a, xf, Vector3(0, SKIRT, r - 0.05), Vector2(0.9, 1.4), Color(0.85, 0.42, 0.12))


## A beach hut: a small wooden hut with a pitched roof, its door and front in a bright colour.
static func _beach_hut(a: Dictionary, xf: Transform3D, w: float, d: float, rng: RandomNumberGenerator) -> void:
	var colours := [Color(0.2, 0.42, 0.7), Color(0.85, 0.3, 0.3), Color(0.95, 0.8, 0.25), Color(0.3, 0.66, 0.5), Color(0.95, 0.95, 0.92),
		Color(0.9, 0.55, 0.65)]
	var c: Color = colours[rng.randi_range(0, colours.size() - 1)]
	var hw := clampf(w, 1.5, 3.0)
	var hd := clampf(d, 1.5, 3.5)
	AdventureProps.box(a, xf, Vector3(hw, SKIRT + 2.2, hd), c, false)
	_gable(a, xf.translated_local(Vector3(0, SKIRT, 0)), hw, hd, 2.2, hw * 0.4, 0.15, Color(0.95, 0.95, 0.92), c)
	_plate(a, xf, Vector3(0, SKIRT, hd * 0.5), Vector2(hw * 0.6, 1.9), c.darkened(0.25))


## A castle's keep or a fort: stone walls topped with battlements, a turret at each corner.
static func _keep(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var stone: Color = RegionKit.pick(rng, kit["walls"]).lerp(Color(0.6, 0.57, 0.5), 0.6)
	var tall := clampf(h, 8.0, 30.0)
	AdventureProps.box(a, xf, Vector3(w, tall + SKIRT, d), stone)
	_battlements(a, xf.translated_local(Vector3(0, SKIRT + tall, 0)), w, d, stone)
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var t := xf.translated_local(Vector3(c.x * (w - 3.0), 0, c.y * (d - 3.0)))
		AdventureProps.cone(a, t, 1.6, 0.0, SKIRT + tall + 3.0, stone.darkened(0.05), 10, 1.6)
		AdventureProps.cone(a, t, 1.8, SKIRT + tall + 3.0, SKIRT + tall + 3.6, stone.darkened(0.12), 10, 1.8)


## Battlements round the top of a `w` x `d` box at `xf`'s origin: merlons every 1.6 m along each edge.
static func _battlements(a: Dictionary, xf: Transform3D, w: float, d: float, stone: Color) -> void:
	for side in 4:
		var along := w if side % 2 == 0 else d
		var across := d if side % 2 == 0 else w
		var frame := xf * Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3.ZERO)
		var n := maxi(2, int(along / 1.6))
		for k in n:
			if k % 2 == 1:
				continue
			AdventureProps.box(a, frame.translated_local(Vector3(((float(k) + 0.5) / n - 0.5) * along, 0, across * 0.5 - 0.3)),
				Vector3(along / n, 0.9, 0.6), stone.darkened(0.04))


## A lighthouse: a tapering white tower (banded red where the coast has it), its gallery and lantern lit.
static func _lighthouse(a: Dictionary, xf: Transform3D, w: float, d: float, h: float) -> void:
	var r := clampf(minf(w, d) * 0.5, 2.0, 5.0)
	var tall := clampf(h, 10.0, 50.0)
	for k in 4:
		var y0 := SKIRT + tall * k / 4.0 if k > 0 else 0.0
		var y1 := SKIRT + tall * (k + 1) / 4.0
		var rr0 := lerpf(r, r * 0.6, float(k) / 4.0)
		var rr1 := lerpf(r, r * 0.6, float(k + 1) / 4.0)
		AdventureProps.cone(a, xf, rr0, y0, y1, Color(0.95, 0.95, 0.93) if k % 2 == 0 else Color(0.78, 0.12, 0.1), 12, rr1)
	var top := xf.translated_local(Vector3(0, SKIRT + tall, 0))
	AdventureProps.cone(a, top, r * 0.85, 0.0, 0.3, Color(0.15, 0.15, 0.16), 12, r * 0.85)
	AdventureProps.cone(a, top, r * 0.45, 0.3, 2.6, Color(0.95, 0.9, 0.6), 10, r * 0.45)
	AdventureProps.cone(a, top, r * 0.5, 2.6, 3.8, Color(0.15, 0.15, 0.16), 10)


## A windmill: a tapering tower, its cap and four sails facing the front.
static func _windmill(a: Dictionary, xf: Transform3D, w: float, d: float, h: float, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var r := clampf(minf(w, d) * 0.5, 3.0, 7.0)
	var tall := clampf(h, 10.0, 25.0)
	var body: Color = RegionKit.pick(rng, kit["walls"])
	AdventureProps.cone(a, xf, r, 0.0, SKIRT + tall, body, 8, r * 0.65)
	AdventureProps.cone(a, xf, r * 0.75, SKIRT + tall, SKIRT + tall + r * 0.8, Color(0.3, 0.3, 0.3), 8)
	var hub := xf.translated_local(Vector3(0, SKIRT + tall, r * 0.8))
	for k in 4:
		var turn := hub * Transform3D(Basis(Vector3.BACK, PI * 0.5 * k + 0.3), Vector3.ZERO)
		AdventureProps.box(a, turn.translated_local(Vector3(0, 0, 0)), Vector3(1.6, tall * 0.55, 0.12), Color(0.85, 0.82, 0.74))


## A roof over a `w` x `d` box `eaves` up in `xf`'s frame: "gable" (ridge along the long side), "hip", "tin" (a low
## gable of sheet metal), or "flat" (a slab, with the kit's parapet).
static func _roof(a: Dictionary, xf: Transform3D, w: float, d: float, eaves: float, form: String, pitch: float, over: float,
		col: Color, wall: Color, _rng: RandomNumberGenerator, kit: Dictionary) -> void:
	var frame := xf
	var ww := w
	var dd := d
	if w > d:
		# (the ridge along local z)
		frame = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		ww = d
		dd = w
	match form:
		"flat":
			AdventureProps.box(a, xf.translated_local(Vector3(0, eaves, 0)), Vector3(w + over * 2.0, 0.18, d + over * 2.0), col)
			if bool(kit.get("parapet", false)):
				for side: float in [-1.0, 1.0]:
					AdventureProps.box(a, xf.translated_local(Vector3(0, eaves, side * (d * 0.5 - 0.1))), Vector3(w, 0.7, 0.2), wall)
					AdventureProps.box(a, xf.translated_local(Vector3(side * (w * 0.5 - 0.1), eaves, 0)), Vector3(0.2, 0.7, d - 0.4), wall)
		"hip":
			_hip(a, frame, ww, dd, eaves, ww * 0.5 * pitch * RISE, over, col)
		"tin":
			_gable(a, frame, ww, dd, eaves, ww * 0.5 * maxf(pitch, 0.12) * RISE, over, col, wall)
		_:
			_gable(a, frame, ww, dd, eaves, ww * 0.5 * pitch * RISE, over, col, wall)


## A gable roof, its ridge along local z, `rise` above the eaves, `over` out past the walls, with its gable ends.
static func _gable(a: Dictionary, xf: Transform3D, w: float, d: float, eaves: float, rise: float, over: float, col: Color, gable_col: Color) -> void:
	var hw := w * 0.5 + over
	var hd := d * 0.5 + over
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var drop := over * rise / maxf(w * 0.5, 0.1)
	var e0: Vector3 = p.call(-hw, eaves - drop, -hd)
	var e1: Vector3 = p.call(hw, eaves - drop, -hd)
	var e2: Vector3 = p.call(hw, eaves - drop, hd)
	var e3: Vector3 = p.call(-hw, eaves - drop, hd)
	var r0: Vector3 = p.call(0, eaves + rise, -hd)
	var r1: Vector3 = p.call(0, eaves + rise, hd)
	var up := xf.basis.y
	_face(a, [e0, e3, r1, r0], -xf.basis.x + up, col)
	_face(a, [e1, r0, r1, e2], xf.basis.x + up, col.darkened(0.06))
	_face(a, [e0, e1, e2, e3], -up, col.darkened(0.4))
	var g0: Vector3 = p.call(-w * 0.5, eaves, -d * 0.5)
	var g1: Vector3 = p.call(w * 0.5, eaves, -d * 0.5)
	var g2: Vector3 = p.call(w * 0.5, eaves, d * 0.5)
	var g3: Vector3 = p.call(-w * 0.5, eaves, d * 0.5)
	_face(a, [g0, g1, p.call(0, eaves + rise, -d * 0.5)], -xf.basis.z, gable_col)
	_face(a, [g3, g2, p.call(0, eaves + rise, d * 0.5)], xf.basis.z, gable_col)


## A hipped roof: four slopes up to a ridge along local z (a point over a square).
static func _hip(a: Dictionary, xf: Transform3D, w: float, d: float, eaves: float, rise: float, over: float, col: Color) -> void:
	var hw := w * 0.5 + over
	var hd := d * 0.5 + over
	var rl := maxf(hd - hw, 0.0)
	var drop := over * rise / maxf(w * 0.5, 0.1)
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var e0: Vector3 = p.call(-hw, eaves - drop, -hd)
	var e1: Vector3 = p.call(hw, eaves - drop, -hd)
	var e2: Vector3 = p.call(hw, eaves - drop, hd)
	var e3: Vector3 = p.call(-hw, eaves - drop, hd)
	var r0: Vector3 = p.call(0, eaves + rise, -rl)
	var r1: Vector3 = p.call(0, eaves + rise, rl)
	var up := xf.basis.y
	_face(a, [e0, e3, r1, r0], -xf.basis.x + up, col)
	_face(a, [e1, r0, r1, e2], xf.basis.x + up, col.darkened(0.06))
	_face(a, [e3, e2, r1], xf.basis.z + up, col.darkened(0.03))
	_face(a, [e0, r0, e1], -xf.basis.z + up, col.darkened(0.09))
	_face(a, [e0, e1, e2, e3], -up, col.darkened(0.4))


## A lean-to roof (a verandah's, an awning) out from a wall: its top edge `w` wide at `at` (on the wall, local), out
## `depth` along +z and down `fall`.
static func _lean_to(a: Dictionary, xf: Transform3D, at: Vector3, w: float, depth: float, fall: float, col: Color) -> void:
	var t0: Vector3 = xf * (at + Vector3(-w * 0.5, 0, 0))
	var t1: Vector3 = xf * (at + Vector3(w * 0.5, 0, 0))
	var b1: Vector3 = xf * (at + Vector3(w * 0.5, -fall, depth))
	var b0: Vector3 = xf * (at + Vector3(-w * 0.5, -fall, depth))
	_face(a, [t0, t1, b1, b0], xf.basis.y + xf.basis.z * 0.3, col)
	_face(a, [t0, b0, b1, t1], -xf.basis.y, col.darkened(0.35))


## A dome: a hemisphere of radius `r` sitting on `xf`'s origin.
static func _dome(a: Dictionary, xf: Transform3D, r: float, col: Color) -> void:
	var rings := 4
	for k in rings:
		var p0 := PI * 0.5 * k / rings
		var p1 := PI * 0.5 * (k + 1) / rings
		AdventureProps.cone(a, xf, r * cos(p0), r * sin(p0), r * sin(p1), col.lightened(0.04 * k), 12, r * cos(p1) if k < rings - 1 else 0.0)


## An onion dome of radius `r` on `xf`'s origin, with its spike.
static func _onion(a: Dictionary, xf: Transform3D, r: float, col: Color) -> void:
	var prof := [[0.7, 0.0], [1.0, 0.35], [0.95, 0.7], [0.6, 1.05], [0.15, 1.4], [0.0, 1.6]]
	for k in prof.size() - 1:
		AdventureProps.cone(a, xf, r * float(prof[k][0]), r * float(prof[k][1]), r * float(prof[k + 1][1]), col.lightened(0.05 * k), 10,
			r * float(prof[k + 1][0]))
	AdventureProps.box(a, xf.translated_local(Vector3(0, r * 1.6, 0)), Vector3(0.08, r * 0.8, 0.08), GOLD)


## Tall windows down both long sides.
static func _side_windows(a: Dictionary, xf: Transform3D, w: float, d: float, y: float, tall: float, glass: Color) -> void:
	var n := clampi(int(d / 4.0), 2, 6)
	for k in n:
		var z := ((float(k) + 0.5) / n - 0.5) * d * 0.8
		for side: float in [-1.0, 1.0]:
			var c: Vector3 = xf * Vector3(side * (w * 0.5 + 0.03), y + tall * 0.5, z)
			var ax := xf.basis.z * 0.5
			var up := xf.basis.y * tall * 0.5
			_face(a, [c - ax - up, c + ax - up, c + ax + up, c - ax + up], xf.basis.x * side, glass)


## A flat plate on a wall facing local +z (`face` -1: the back wall, facing -z): its bottom middle at `at` (z the
## wall's), `size` wide and tall, just proud of the wall.
static func _plate(a: Dictionary, xf: Transform3D, at: Vector3, size: Vector2, col: Color, face := 1.0) -> void:
	var z := (at.z + 0.03) * face
	var x0 := at.x - size.x * 0.5
	var x1 := at.x + size.x * 0.5
	var pts := [xf * Vector3(x0, at.y, z), xf * Vector3(x1, at.y, z), xf * Vector3(x1, at.y + size.y, z), xf * Vector3(x0, at.y + size.y, z)]
	_face(a, pts, xf.basis.z * face, col)


## A shop's name on its fascia: a word the country's shops have (SignWords.shop_word, in the local script), centred at
## `at` on the front, `h` m tall and no wider than `most`, in white on a dark fascia or near-black on a light one.
static func _shop_name(a: Dictionary, xf: Transform3D, at: Vector3, most: float, h: float, fascia: Color, kit: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var word := SignWords.shop_word(kit.get("facts", {}), rng)
	if word == "" or most < 1.0:
		return
	var ink := Color(0.95, 0.94, 0.9) if fascia.get_luminance() < 0.55 else Color(0.08, 0.08, 0.09)
	var b := xf.basis.orthonormalized()
	SignWords.draw(a, word, xf * at, b.x, b.y, h, ink, b.z, most)


## A flat face through `pts` (in order round it), turned to face `out`.
static func _face(a: Dictionary, pts: Array, out: Vector3, col: Color) -> void:
	var p0: Vector3 = pts[0]
	for k in range(1, pts.size() - 1):
		var p1: Vector3 = pts[k]
		var p2: Vector3 = pts[k + 1]
		var n := (p1 - p0).cross(p2 - p0)
		if n.length_squared() < 1e-12:
			continue
		if n.dot(out) >= 0.0:
			AdventureProps._tri(a, p0, p1, p2, col)
		else:
			AdventureProps._tri(a, p0, p2, p1, col)
