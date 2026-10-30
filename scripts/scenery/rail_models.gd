extends RefCounted
## The railway's instanced pieces (rail.gd lays one per sample along a line and scales it to fit): each made once, a
## MultiMesh of each a block. A piece along the line runs from its origin to local z = -1 (scaled to the sample's
## length), x to the line's right, y up.

const Geo := preload("res://scripts/scenery/rail_geo.gd")

const BALLAST_W := 1.6
const SHOULDER := 0.6
const SHOULDER_DROP := 0.45
const SLEEPER_TOP := 0.12
const RAIL_TOP := 0.27
const WIRE_H := 5.6
const DECK_W := 4.6
const DECK_DEPTH := 1.2

const C_BALLAST := Color(0.40, 0.38, 0.35)
const C_SHOULDER := Color(0.36, 0.34, 0.31)
const C_SLEEPER := Color(0.45, 0.44, 0.41)
const C_GRASS := Color(0.30, 0.34, 0.20)
const C_STONE := Color(0.50, 0.47, 0.42)
const C_CONCRETE := Color(0.62, 0.61, 0.58)
const C_STEEL := Color(0.22, 0.26, 0.25)
const C_RAIL := Color(0.30, 0.28, 0.26)
const C_PLATFORM := Color(0.52, 0.50, 0.48)
const C_EDGE := Color(0.92, 0.85, 0.30)
const C_POST := Color(0.12, 0.12, 0.13)

## How far each piece is drawn from (m), and to: the near track's sleepers, the far track's plain bed.
const RANGES := {"track": [0.0, 900.0], "track_narrow": [0.0, 900.0], "track_far": [900.0, 3000.0],
	"skirt_l": [0.0, 2500.0], "skirt_r": [0.0, 2500.0], "wire": [0.0, 700.0], "mast": [0.0, 1200.0],
	"deck_stone": [0.0, 3500.0], "deck_concrete": [0.0, 3000.0], "deck_steel": [0.0, 3000.0],
	"pier_stone": [0.0, 3500.0], "pier_concrete": [0.0, 3000.0], "pier_steel": [0.0, 3000.0], "arch_stone": [0.0, 3500.0],
	"beam": [0.0, 2500.0], "pillar": [0.0, 2500.0], "platform": [0.0, 1500.0], "canopy": [0.0, 1200.0],
	"canopy_post": [0.0, 800.0], "lamp_post": [0.0, 1500.0]}

static var _meshes := {}
static var _lock := Mutex.new()


## Piece `model`'s mesh (made the first time it's asked for).
static func mesh(model: String) -> Mesh:
	_lock.lock()
	var have = _meshes.get(model)
	_lock.unlock()
	if have != null:
		return have
	var geo := Geo.new()
	match model:
		"track", "track_narrow", "track_far":
			_track(geo, 1.435 if model != "track_narrow" else 1.0, model != "track_far")
		"skirt_l", "skirt_r":
			# (a sheet from the shoulder's foot out and down: scaled by its depth both ways, 1.5 out for each 1 down)
			var s := -1.0 if model == "skirt_l" else 1.0
			geo.quad("matte", Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3(1.5 * s, -1, -1), Vector3(1.5 * s, -1, 0), C_GRASS)
		"wire":
			for y: float in [RAIL_TOP + WIRE_H, RAIL_TOP + WIRE_H + 1.1]:
				geo.quad("steel", Vector3(-0.02, y, 0), Vector3(0.02, y, 0), Vector3(0.02, y, -1), Vector3(-0.02, y, -1), C_STEEL)
				geo.quad("steel", Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0), Vector3(0, y + 0.02, -1), Vector3(0, y - 0.02, -1), C_STEEL)
		"mast":
			# (stood beside the track, its arms reaching back over it along -x)
			geo.box("steel", Vector3(0, (RAIL_TOP + WIRE_H + 1.6 - 0.3) * 0.5, 0), Vector3(0.12, (RAIL_TOP + WIRE_H + 1.9) * 0.5, 0.12), C_STEEL)
			geo.box("steel", Vector3(-1.4, RAIL_TOP + WIRE_H + 1.2, 0), Vector3(1.5, 0.06, 0.06), C_STEEL)
			geo.box("steel", Vector3(-1.4, RAIL_TOP + WIRE_H + 0.3, 0), Vector3(1.5, 0.04, 0.04), C_STEEL)
		"deck_stone", "deck_concrete", "deck_steel":
			_deck(geo, _style_colour(model))
		"pier_stone", "pier_concrete", "pier_steel":
			# (a unit tall from its top at 0 down to -1, DECK_W across and 1 along: scaled to its height and thickness)
			var c := _style_colour(model)
			var hw := DECK_W * 0.5 - 0.1
			for k in 4:
				var corners := [Vector2(-hw, -0.5), Vector2(hw, -0.5), Vector2(hw, 0.5), Vector2(-hw, 0.5)]
				var a: Vector2 = corners[k]
				var b: Vector2 = corners[(k + 1) % 4]
				geo.quad("matte", Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x * 1.08, -1, b.y * 1.3), Vector3(a.x * 1.08, -1, a.y * 1.3), c)
		"arch_stone":
			_arch(geo)
		"beam":
			geo.quad("matte", Vector3(-0.45, 0, 0), Vector3(0.45, 0, 0), Vector3(0.45, 0, -1), Vector3(-0.45, 0, -1), C_CONCRETE)
			for s: float in [-0.45, 0.45]:
				geo.quad("matte", Vector3(s, 0, 0), Vector3(s, 0, -1), Vector3(s, -1.4, -1), Vector3(s, -1.4, 0), C_CONCRETE)
			geo.quad("matte", Vector3(-0.45, -1.4, 0), Vector3(-0.45, -1.4, -1), Vector3(0.45, -1.4, -1), Vector3(0.45, -1.4, 0), C_CONCRETE)
		"pillar":
			geo.box("matte", Vector3(0, -0.5, 0), Vector3(0.6, 0.5, 0.6), C_CONCRETE)
		"platform":
			# (its edge at x = 0, its back at x = 1 (scaled to its width), its top at 0, its faces down to -1 (to the land))
			var stripe := 0.12
			geo.quad("matte", Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3(stripe, 0, -1), Vector3(stripe, 0, 0), C_EDGE)
			geo.quad("matte", Vector3(stripe, 0, 0), Vector3(stripe, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 0), C_PLATFORM)
			for x: float in [0.0, 1.0]:
				geo.quad("matte", Vector3(x, 0, 0), Vector3(x, 0, -1), Vector3(x, -1, -1), Vector3(x, -1, 0), C_PLATFORM.darkened(0.2))
		"canopy":
			# (over the platform from x = 0.05 to 1.05 of its width, a little higher at its back)
			geo.quad("matte", Vector3(0.05, 3.4, 0), Vector3(0.05, 3.4, -1), Vector3(1.05, 3.7, -1), Vector3(1.05, 3.7, 0), Color(0.23, 0.29, 0.36))
			geo.quad("matte", Vector3(0.05, 3.3, 0), Vector3(0.05, 3.3, -1), Vector3(0.05, 3.4, -1), Vector3(0.05, 3.4, 0), Color(0.18, 0.22, 0.27))
		"canopy_post":
			geo.box("matte", Vector3(0, 1.75, 0), Vector3(0.09, 1.75, 0.09), Color(0.2, 0.25, 0.3))
		"lamp_post":
			geo.box("matte", Vector3(0, 1.8, 0), Vector3(0.05, 1.8, 0.05), C_POST)
			geo.box("matte", Vector3(0.25, 3.62, 0), Vector3(0.3, 0.03, 0.04), C_POST)
			geo.box("glow", Vector3(0.45, 3.52, 0), Vector3(0.16, 0.07, 0.16), Color(1.0, 0.92, 0.75))
		_:
			geo.box("matte", Vector3(0, 0.5, 0), Vector3(0.2, 0.5, 0.2), Color(0.5, 0.5, 0.5))
	var m := geo.mesh()
	_lock.lock()
	_meshes[model] = m
	_lock.unlock()
	return m


static func _style_colour(model: String) -> Color:
	if model.ends_with("stone"):
		return C_STONE
	if model.ends_with("steel"):
		return C_STEEL
	return C_CONCRETE


## A 1 m piece of track of gauge `gauge`: the ballast's top and shoulders, the rails, and (near) its sleepers.
static func _track(geo: Geo, gauge: float, sleepers: bool) -> void:
	var w := BALLAST_W
	var o := BALLAST_W + SHOULDER
	geo.quad("matte", Vector3(-w, 0, 0), Vector3(-w, 0, -1), Vector3(w, 0, -1), Vector3(w, 0, 0), C_BALLAST)
	for s: float in [-1.0, 1.0]:
		geo.quad("matte", Vector3(w * s, 0, 0), Vector3(w * s, 0, -1), Vector3(o * s, -SHOULDER_DROP, -1), Vector3(o * s, -SHOULDER_DROP, 0), C_SHOULDER)
	if sleepers:
		# (four a metre-long piece's worth of sleepers... spaced as a 4 m piece's six)
		var half := gauge * 0.5 + 0.55
		for k in 6:
			var z0 := -(k + 0.2) / 6.0
			var z1 := -(k + 0.8) / 6.0
			geo.quad("matte", Vector3(-half, SLEEPER_TOP, z0), Vector3(-half, SLEEPER_TOP, z1), Vector3(half, SLEEPER_TOP, z1), Vector3(half, SLEEPER_TOP, z0), C_SLEEPER)
			for z: float in [z0, z1]:
				geo.quad("matte", Vector3(-half, 0, z), Vector3(half, 0, z), Vector3(half, SLEEPER_TOP, z), Vector3(-half, SLEEPER_TOP, z), C_SLEEPER.darkened(0.15))
	for s: float in [-1.0, 1.0]:
		var x := gauge * 0.5 * s
		var hw := 0.036
		var low := SLEEPER_TOP if sleepers else 0.05
		geo.quad("steel", Vector3(x - hw, RAIL_TOP, 0), Vector3(x - hw, RAIL_TOP, -1), Vector3(x + hw, RAIL_TOP, -1), Vector3(x + hw, RAIL_TOP, 0), Color(0.55, 0.53, 0.5))
		for e: float in [-hw, hw]:
			geo.quad("steel", Vector3(x + e, low, 0), Vector3(x + e, low, -1), Vector3(x + e, RAIL_TOP, -1), Vector3(x + e, RAIL_TOP, 0), C_RAIL)


## A 1 m piece of bridge deck: its ballast-coloured top, sides down DECK_DEPTH, underside, and a parapet each side.
static func _deck(geo: Geo, c: Color) -> void:
	var h := DECK_W * 0.5
	geo.quad("matte", Vector3(-h, -0.02, 0), Vector3(-h, -0.02, -1), Vector3(h, -0.02, -1), Vector3(h, -0.02, 0), C_SHOULDER)
	for s: float in [-1.0, 1.0]:
		geo.quad("matte", Vector3(h * s, 1.0, 0), Vector3(h * s, 1.0, -1), Vector3(h * s, -DECK_DEPTH, -1), Vector3(h * s, -DECK_DEPTH, 0), c)
		var i := (h - 0.35) * s
		geo.quad("matte", Vector3(i, 1.0, 0), Vector3(i, 1.0, -1), Vector3(i, -0.02, -1), Vector3(i, -0.02, 0), c.darkened(0.08))
		geo.quad("matte", Vector3(i, 1.0, 0), Vector3(i, 1.0, -1), Vector3(h * s, 1.0, -1), Vector3(h * s, 1.0, 0), c.lightened(0.05))
	geo.quad("matte", Vector3(-h, -DECK_DEPTH, 0), Vector3(-h, -DECK_DEPTH, -1), Vector3(h, -DECK_DEPTH, -1), Vector3(h, -DECK_DEPTH, 0), c.darkened(0.2))


## A stone arch a unit across (inner face to inner face, from z = 0 to -1), under a deck whose underside is at y = 0: a
## round arch springing at y = -0.65, its crown at -0.15, the spandrel walls each side up to the deck and its underside.
static func _arch(geo: Geo) -> void:
	var h := DECK_W * 0.5 - 0.1
	var steps := 10
	var prev: Array = []
	for k in steps + 1:
		var ang := PI * k / steps
		var z := -0.5 + cos(ang) * 0.5
		var y := -0.65 + sin(ang) * 0.5
		var cur := [Vector3(-h, y, z), Vector3(h, y, z), Vector3(-h, 0, z), Vector3(h, 0, z)]
		if not prev.is_empty():
			geo.quad("matte", prev[2], cur[2], cur[0], prev[0], C_STONE)
			geo.quad("matte", prev[3], cur[3], cur[1], prev[1], C_STONE)
			geo.quad("matte", prev[0], cur[0], cur[1], prev[1], C_STONE.darkened(0.18))
		prev = cur
