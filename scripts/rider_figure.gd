class_name RiderFigure
extends RefCounted
## Draws the basic avatar in its rider gear (see RiderGear): standing on foot (other players,
## the Shop tab's turntable) and the pieces the seated rider on a bike is made of (BikeModel).
## Everything is primitive meshes; patterns (stripes, hoops, chequers, carbon weave) are small
## textures made here and kept, one per item and colour.
##
## The standing figure faces -Z with its feet at y = 0: torso, arms, hips, legs, boots, gloves
## and, on its own node so it can nod, the head with the helmet or cap.

## Pattern names an item can have, and how they run round a limb or a helmet:
## plain; stripe (one band down the front and back, over the top of a helmet); twin (two thin
## bands either side of that); hoops (rings round); panel (the lower part in the trim colour);
## check (chequers); hivis (two reflective rings); carbon (a fine weave); race (panels down
## the sides in trim with a thin accent line).
const PATTERNS: Array[String] = ["plain", "stripe", "twin", "hoops", "panel", "check", "hivis", "carbon", "race"]
const SKIN := Color(0.85, 0.66, 0.52)
## Where the standing figure's arms hang at rest: shoulder, elbow and wrist.
const ARM_R := {"shoulder": Vector3(0.25, 1.38, 0.0), "elbow": Vector3(0.3, 1.1, -0.06), "wrist": Vector3(0.29, 1.0, -0.28)}
const ARM_L := {"shoulder": Vector3(-0.25, 1.38, 0.0), "elbow": Vector3(-0.32, 1.1, 0.02), "wrist": Vector3(-0.33, 0.86, -0.02)}
const TEX := 64

static var _textures := {}       # "pattern|base|trim|accent" -> ImageTexture
static var _mats := {}           # "item|part|tint" -> StandardMaterial3D


# ---------------------------------------------------------------------------- colours and materials

## An item's colour `key` ("base", "trim" or "accent"), with "tint" for the player's colour.
static func color_of(item: Dictionary, key: String, tint: Color) -> Color:
	var c = item.get(key, item.get("base", Color.BLACK) if key != "base" else Color.BLACK)
	if c is String:
		return tint.darkened(0.35) if c == "tint_dark" else tint
	return c


## The material for `item_id` in the player's colour `tint`. `part` "trim" gives the plain trim
## colour (buckles, cuffs, peaks), "base" the plain base colour, "" the patterned cloth or shell.
## `paint`, when not clear, takes the place of the base colour (a helmet's chosen shell colour).
static func material(item_id: String, tint: Color, part := "", paint := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [item_id, part, tint.to_html()]
	if paint.a > 0.0:
		key += "|" + paint.to_html()
	if _mats.has(key):
		return _mats[key]
	var item := RiderGear.get_item(item_id)
	var m := StandardMaterial3D.new()
	var base := color_of(item, "base", tint) if paint.a <= 0.0 else paint
	var trim := color_of(item, "trim", tint)
	var accent := color_of(item, "accent", tint)
	var pattern := str(item.get("pattern", "plain"))
	if part == "trim":
		m.albedo_color = trim
	elif part == "base" or pattern == "plain":
		m.albedo_color = base
	else:
		m.albedo_texture = pattern_texture(pattern, base, trim, accent)
	match str(item.get("finish", "textile")):
		"leather":
			m.roughness = 0.38
			m.clearcoat_enabled = true
			m.clearcoat = 0.25
		"gloss":
			m.metallic = 0.2
			m.roughness = 0.15
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
		"matte":
			m.roughness = 0.75
		"carbon":
			m.metallic = 0.35
			m.roughness = 0.25
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
		"wax":
			m.roughness = 0.5
		"denim":
			m.roughness = 0.95
		_:
			m.roughness = 0.8
	_mats[key] = m
	return m


## A small texture of `pattern` in these colours, laid out for the UVs of a capsule or sphere
## (u round it, starting at the back, v from the top down).
static func pattern_texture(pattern: String, base: Color, trim: Color, accent: Color) -> ImageTexture:
	var key := "%s|%s|%s|%s" % [pattern, base.to_html(), trim.to_html(), accent.to_html()]
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGB8)
	for y in TEX:
		for x in TEX:
			img.set_pixel(x, y, pattern_color(pattern, (x + 0.5) / TEX, (y + 0.5) / TEX, base, trim, accent))
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## The colour of `pattern` at (u, v): u goes once round (0 and 1 at the back, 0.5 at the
## front), v from the top (0) to the bottom (1).
static func pattern_color(pattern: String, u: float, v: float, base: Color, trim: Color, accent: Color) -> Color:
	# How far round from the front and from the nearer side, 0..0.5.
	var front := absf(u - 0.5)
	var back := minf(u, 1.0 - u)
	var side := absf(u - 0.25) if u < 0.5 else absf(u - 0.75)
	match pattern:
		"stripe":
			return trim if front < 0.035 or back < 0.035 else base
		"twin":
			return trim if absf(front - 0.06) < 0.02 or absf(back - 0.06) < 0.02 else base
		"hoops":
			return trim if int(floor(v * 7.0)) % 2 == 1 else base
		"panel":
			if absf(v - 0.62) < 0.02:
				return base.lerp(Color.WHITE, 0.5)
			return trim if v > 0.62 else base
		"check":
			return trim if (int(floor(u * 12.0)) + int(floor(v * 6.0))) % 2 == 0 else base
		"hivis":
			return trim if absf(v - 0.35) < 0.045 or absf(v - 0.62) < 0.045 else base
		"carbon":
			var weave := (int(floor(u * 32.0)) + int(floor(v * 16.0))) % 2 == 0
			var fine := 0.5 + 0.5 * sin((u * 32.0 + v * 16.0) * PI)
			return base.lerp(trim, (0.35 if weave else 0.0) + 0.25 * fine)
		"race":
			if absf(side - 0.1) < 0.012:
				return accent
			return trim if side < 0.09 else base
	return base


# ---------------------------------------------------------------------------- meshes

static func mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.layers = layers
	Graphics.avatar_mesh(mi)
	parent.add_child(mi)
	return mi


static func sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


static func box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, layers := 1) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(parent, b, mat, center, layers)


## A rounded limb (a capsule) from `a` to `b`, `radius` thick.
static func limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, layers := 1) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(a.distance_to(b) + radius * 2.0, radius * 2.0 + 0.001)
	c.radial_segments = 16
	c.rings = 4
	var mi := mesh(parent, c, mat, (a + b) * 0.5, layers)
	mi.basis = basis_along(b - a)
	return mi


## A ring or short tube (a cylinder) from `a` to `b`.
static func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, layers := 1) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = maxf(a.distance_to(b), 0.001)
	c.radial_segments = 16
	c.rings = 1
	var mi := mesh(parent, c, mat, (a + b) * 0.5, layers)
	mi.basis = basis_along(b - a)
	return mi


## A basis whose Y axis runs along `dir`, keeping its front (-Z) facing forward where it can,
## so a pattern's front stripe stays at the front of an arm or leg.
static func basis_along(dir: Vector3) -> Basis:
	if dir.length() < 0.0001:
		return Basis()
	var up := dir.normalized()
	var back := Vector3.BACK - up * up.dot(Vector3.BACK)
	if back.length() < 0.01:
		back = Vector3.UP - up * up.dot(Vector3.UP)
	back = back.normalized()
	var right := up.cross(back).normalized()
	return Basis(right, up, back)


# ---------------------------------------------------------------------------- the pieces

## A helmet (or the cap) centred at `c`, `r` its shell radius, facing -Z, with the face under
## it (eyes, brows and nose). `on_bike` adds the head and neck too (a seated rider has none of
## its own), and swaps the cap for a plain lid in its colour: nobody rides in a cap. `worn` is
## the worn set (see RiderGear), for the helmet's colour, visor and goggles and whose visor it
## follows. Returns what it added: the helmet's node (see HelmetModel), or the cap's meshes.
static func helmet(parent: Node3D, c: Vector3, r: float, item_id: String, tint: Color, layers := 1, on_bike := false,
		worn := {}) -> Array:
	var item := RiderGear.get_item(item_id)
	if str(item.get("shape", "")) == "cap" and not on_bike:
		# The cap sits on the head (drawn with it): a crown and a peak, and the face under the peak.
		var shell := material(item_id, tint, "", RiderGear.shell_color(worn, tint))
		var face := HelmetModel.face(parent, c, r * 1.1, layers)
		var crown := mesh(parent, sphere(0.5), shell, c + Vector3(0.0, r * 0.45, r * 0.12), layers)
		crown.scale = Vector3(r * 1.65, r * 1.0, r * 1.75)
		return [face, crown, box(parent, c + Vector3(0.0, r * 0.25, -r * 1.05), Vector3(r * 1.35, r * 0.12, r * 0.85), shell, layers)]
	return [HelmetModel.face(parent, c + HelmetModel.HEAD_AT * r, r, layers, on_bike),
		HelmetModel.build(parent, c, r, item_id, tint, layers, worn)]


## A gloved hand at `at`, the forearm running off towards `elbow`.
static func glove(parent: Node3D, at: Vector3, elbow: Vector3, r: float, item_id: String, tint: Color, layers := 1) -> void:
	var item := RiderGear.get_item(item_id)
	var extras: Array = item.get("extras", [])
	var base := material(item_id, tint, "base")
	var trim := material(item_id, tint, "trim")
	var g := mesh(parent, sphere(r), base, at, layers)
	g.scale = Vector3(1.0, 1.0, 1.15)
	var up := (elbow - at).normalized()
	if extras.has("cuffs"):
		tube(parent, at + up * r * 0.6, at + up * r * 2.6, r * 0.95, trim, layers)
	if extras.has("knuckles"):
		# Armour across the back of the hand.
		var k := box(parent, at - up * r * 0.3 + Vector3.UP * r * 0.6, Vector3(r * 1.3, r * 0.9, r * 0.35), trim, layers)
		k.basis = basis_along(up)


## A boot with its sole on the ground at `foot` (the middle of the sole), the toe pointing
## along `toe_dir`, the shaft running `item.high` up the shin towards `knee`.
static func boot(parent: Node3D, foot: Vector3, knee: Vector3, toe_dir: Vector3, item_id: String, tint: Color, layers := 1) -> void:
	var item := RiderGear.get_item(item_id)
	var extras: Array = item.get("extras", [])
	var base := material(item_id, tint, "base")
	var trim := material(item_id, tint, "trim")
	var sole_mat := trim if extras.has("sole") else material("boots_work", tint, "base")
	var high := float(item.get("high", 0.13))
	var fwd := Vector3(toe_dir.x, 0.0, toe_dir.z).normalized()
	var b := Basis.looking_at(fwd, Vector3.UP)
	var foot_box := box(parent, foot + Vector3.UP * 0.05 + fwd * 0.05, Vector3(0.13, 0.09, 0.27), base, layers)
	foot_box.basis = b
	var sole := box(parent, foot + Vector3.UP * 0.008 + fwd * 0.05, Vector3(0.14, 0.016, 0.28), sole_mat, layers)
	sole.basis = b
	if extras.has("toe"):
		var toe := box(parent, foot + Vector3.UP * 0.05 + fwd * 0.17, Vector3(0.135, 0.07, 0.06), trim, layers)
		toe.basis = b
	var up := (knee - foot).normalized()
	var top := foot + up * high
	tube(parent, foot + Vector3.UP * 0.04, top, 0.072, base, layers)
	if extras.has("buckles"):
		var n := 4 if high > 0.34 else 1
		for i in n:
			var at := foot + up * (high * (0.35 + 0.6 * float(i + 1) / float(n + 1)) if n > 1 else high - 0.03)
			tube(parent, at - up * 0.012, at + up * 0.012, 0.077, trim, layers)


## Knee guards on the front of a knee at `knee`, the shin running off towards `ankle`.
static func knee_guard(parent: Node3D, knee: Vector3, hip: Vector3, ankle: Vector3, r: float, item_id: String, tint: Color, layers := 1) -> void:
	var trim := material(item_id, tint, "trim")
	var bend := ((hip - knee).normalized() + (ankle - knee).normalized())
	var out := -bend.normalized() if bend.length() > 0.05 else Vector3.FORWARD
	# Out past the thigh, which is thicker than the shin at the knee.
	var k := box(parent, knee + out * r * 1.2, Vector3(r * 1.5, r * 1.9, r * 0.45), trim, layers)
	k.basis = basis_along(ankle - hip)


# ---------------------------------------------------------------------------- the standing figure

## Builds the standing figure in `gear` (slot -> item id) into `body` (feet at y = 0, facing
## -Z) and `head` (a node at eye height the head turns on). `tint` is the player's colour.
## Only adds meshes: clear the nodes first to dress again.
static func standing(body: Node3D, head: Node3D, gear: Dictionary, tint: Color) -> void:
	var worn := RiderGear.clean_worn(gear)
	var jacket := str(worn["jacket"])
	var trousers := str(worn["trousers"])
	var jm := material(jacket, tint)
	var tm := material(trousers, tint)
	var jx: Array = RiderGear.get_item(jacket).get("extras", [])
	var tx: Array = RiderGear.get_item(trousers).get("extras", [])
	# Torso and hips.
	var torso := limb(body, Vector3(0.0, 1.03, 0.0), Vector3(0.0, 1.3, 0.0), 0.2, jm)
	torso.scale = Vector3(1.38, 1.0, 1.0)
	var hips := mesh(body, sphere(0.5), tm, Vector3(0.0, 0.86, 0.0))
	hips.scale = Vector3(0.44, 0.26, 0.32)
	var neck := mesh(body, sphere(0.06), _skin(), Vector3(0.0, 1.5, 0.0))
	neck.scale = Vector3(1.0, 1.4, 1.0)
	if jx.has("hump"):
		var hump := mesh(body, sphere(0.5), jm, Vector3(0.0, 1.36, 0.17))
		hump.scale = Vector3(0.26, 0.2, 0.14)
	if jx.has("collar"):
		tube(body, Vector3(0.0, 1.44, 0.0), Vector3(0.0, 1.5, 0.0), 0.085, material(jacket, tint, "trim"))
	if jx.has("pockets"):
		for side in [-1.0, 1.0]:
			box(body, Vector3(0.12 * side, 1.12, -0.2), Vector3(0.1, 0.08, 0.02), material(jacket, tint, "trim"))
	# Arms: the right one reaching forward to what's in hand, the left down by the side. Each
	# hangs from a node at its shoulder ("ArmR", "ArmL") so emotes can swing it (see Emotes).
	for side in [-1.0, 1.0]:
		var arm: Dictionary = ARM_R if side > 0 else ARM_L
		var sh: Vector3 = arm["shoulder"]
		var pivot := Node3D.new()
		pivot.name = "ArmR" if side > 0 else "ArmL"
		pivot.position = sh
		body.add_child(pivot)
		var elbow: Vector3 = arm["elbow"] - sh
		var wrist: Vector3 = arm["wrist"] - sh
		limb(pivot, Vector3.ZERO, elbow, 0.058, jm)
		limb(pivot, elbow, wrist, 0.052, jm)
		glove(pivot, wrist + (wrist - elbow).normalized() * 0.04, elbow, 0.05, str(worn["gloves"]), tint)
	# Legs and boots, each hanging from a node at its hip ("LegR", "LegL") so walking can swing
	# it (see walk_pose).
	for side in [-1.0, 1.0]:
		var hip := Vector3(0.11 * side, 0.82, 0.0)
		var leg := Node3D.new()
		leg.name = "LegR" if side > 0 else "LegL"
		leg.position = hip
		body.add_child(leg)
		var knee := Vector3(0.115 * side, 0.47, -0.02) - hip
		var ankle := Vector3(0.12 * side, 0.1, 0.0) - hip
		limb(leg, Vector3.ZERO, knee, 0.095, tm)
		limb(leg, knee, ankle, 0.08, tm)
		if tx.has("knees"):
			knee_guard(leg, knee, Vector3.ZERO, ankle, 0.08, trousers, tint)
		boot(leg, Vector3(0.12 * side, 0.0, -0.02) - hip, knee, Vector3.FORWARD, str(worn["boots"]), tint)
	# The head, and the helmet or cap on it.
	var face := mesh(head, sphere(0.5), _skin(), Vector3.ZERO)
	face.scale = Vector3(0.24, 0.27, 0.25)
	var lid := str(worn["helmet"])
	var shape := str(RiderGear.get_item(lid).get("shape", "full"))
	if shape == "cap":
		helmet(head, Vector3(0.0, 0.0, 0.0), 0.15, lid, tint, 1, false, worn)
	else:
		helmet(head, Vector3(0.0, 0.03, 0.0), 0.165, lid, tint, 1, false, worn)


## Swings a standing figure's legs (and bobs it a touch) for walking: `phase` is how far
## through the stride it is, in radians (one stride, left and right, a turn), and `amount`
## 0 (stood still) to 1 (a full stride), more for a run.
static func walk_pose(body: Node3D, phase: float, amount: float) -> void:
	var swing := sin(phase) * 0.45 * amount
	for leg_name in ["LegR", "LegL"]:
		var leg := body.get_node_or_null(leg_name) as Node3D
		if leg:
			leg.rotation.x = swing if leg_name == "LegR" else -swing


static func _skin() -> StandardMaterial3D:
	var key := "skin"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = SKIN
		m.roughness = 0.6
		_mats[key] = m
	return _mats[key]


## A whole standing figure on one node, for previews: {root, head}.
static func make(gear: Dictionary, tint: Color) -> Node3D:
	var root := Node3D.new()
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.62, 0.0)
	root.add_child(head)
	standing(root, head, gear, tint)
	return root
