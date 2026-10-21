class_name AdventureTunnels
extends RefCounted
## The tunnels through the rock on an adventure road (Simon: "the switch backs and tunnels you get
## in the alps"): AdventureRoute plans where they go (a gentle stretch through a ridge, the hill
## raised over it, see _plan_tunnels and natural_height); a chunk with some of one in it gets its
## tube (tiled walls, a sooty arched roof, solid to ride into), the rock over its roof joining the
## land either side, a concrete portal with its name board at each end, and its lights: strips of
## lamps along both shoulders and a lamp every LAMP_EVERY knots that lights the road (by day the
## tunnel is dark inside but for them; at night they're what you see by, with your headlight).
## Inside, the sky's light and the rain are kept out (AdventureWorld.shelter_at: Daylight.shelter
## dims the sun and the sky's ambient, Weather stops drawing the rain).

## The tube: its walls this far out past the road's edge, this high, and the arch over them.
const SIDE := 0.85
const WALL := 4.2
const ARCH := 2.4
const ARCH_SEGS := 6
## A lamp lighting the road every this many knots (and one more just inside each portal).
const LAMP_EVERY := 6
const LAMP_RANGE := 14.0
const LAMP_ENERGY := 1.7
const LAMP_COLOR := Color(1.0, 0.84, 0.62)
const TILE := Color(0.74, 0.73, 0.69)
const CONCRETE := Color(0.5, 0.5, 0.48)
const SOOT := Color(0.27, 0.27, 0.27)
const PORTAL := Color(0.62, 0.61, 0.58)
const NAMES: Array[String] = ["Kestrel", "Raven", "Gorge", "Eagle", "Falcon", "Stag", "Cloud", "Black Crag", "High Moor", "Hollow"]

static var _glow_mat: StandardMaterial3D
static var _tube_mat: StandardMaterial3D


## The cross-section of the tube beside knot `i`: [Vector2(lat, height over the road)] from the
## road's left edge along the kerb to the foot of the wall, up over the arch and down to the
## right foot and the road's right edge.
static func profile(route: AdventureRoute, i: int) -> Array:
	var e := route.width[i] * 0.5
	var w := e + SIDE
	var out := [Vector2(-e, -0.02), Vector2(-w, -0.1)]
	for k in ARCH_SEGS + 1:
		var th := PI - PI * k / ARCH_SEGS
		out.append(Vector2(w * cos(th), WALL + ARCH * sin(th)))
	out.append(Vector2(w, -0.1))
	out.append(Vector2(e, -0.02))
	return out


## The tunnel's name and length for its boards.
static func title(route: AdventureRoute, id: int) -> String:
	var t: Dictionary = route.tunnels[id]
	var name_i := absi(hash([route.seed_value, "tunnel", id])) % NAMES.size()
	return "%s Tunnel  %d m" % [NAMES[name_i], roundi((int(t["k1"]) - int(t["k0"])) * AdventureRoute.STEP)]


## Chunk i0..i1's share of any tunnel (AdventureChunk.build; `land` its land rows {side: {v}}),
## into out["tunnel"] (nothing when there's none in it): {tube, faces (collision), cap, glow,
## portals, lights [local positions], boards [{xf, text}]}.
static func build(route: AdventureRoute, i0: int, i1: int, ax: float, az: float, land: Dictionary, out: Dictionary) -> void:
	var inside := []
	for i in range(i0, i1 + 1):
		inside.append(route.in_tunnel(i))
	if not inside.has(true):
		return
	var tube := AdventureProps.new_arrays()
	var cap := AdventureProps.new_arrays()
	var glow := AdventureProps.new_arrays()
	var portals := AdventureProps.new_arrays()
	var faces := PackedVector3Array()
	var lights := []
	var boards := []
	var cols := AdventureChunk.land_cols(route)
	var lv: PackedVector3Array = land[-1]["v"]
	var rv: PackedVector3Array = land[1]["v"]
	var rings := []   # each row's tube points (local), or [] outside
	for r in inside.size():
		var i := i0 + r
		if not inside[r]:
			rings.append([])
			continue
		var c := Vector3(route.px[i] - ax, route.ph[i], route.pz[i] - az)
		var right := Vector3(cos(route.hd[i]), 0.0, sin(route.hd[i]))
		var ring := []
		for q: Vector2 in profile(route, i):
			ring.append(c + right * q.x + Vector3.UP * q.y)
		rings.append(ring)
	for r in inside.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		if a.is_empty() or b.is_empty():
			continue
		var i := i0 + r
		for k in a.size() - 1:
			var h := (a[k] as Vector3).y - route.ph[i]
			var col := TILE if h < 1.4 and (a[k + 1] as Vector3).y - route.ph[i] < 1.5 else (CONCRETE if h < WALL - 0.1 else SOOT)
			if col == TILE and i % 2 == 0:
				col = col.darkened(0.05)
			AdventureProps._quad(tube, a[k], b[k], b[k + 1], a[k + 1], col)
			faces.append_array([a[k], b[k], b[k + 1], a[k], b[k + 1], a[k + 1]])
		# The lamps along both shoulders (gaps between, so it streams past), and the rock over the roof.
		for k: int in [2, ARCH_SEGS + 2]:
			var p0: Vector3 = (a[k] as Vector3).lerp(a[k + (1 if k == 2 else -1)], 0.3)
			var p1: Vector3 = (b[k] as Vector3).lerp(b[k + (1 if k == 2 else -1)], 0.3)
			var inward := (Vector3(route.px[i] - ax, p0.y, route.pz[i] - az) - p0).normalized() * 0.06
			var along := p1 - p0
			AdventureJunctions._strip(glow, p0 + inward + along * 0.1, p0 + inward + along * 0.75, 0.16, LAMP_COLOR)
		# (from the land's first column each side: over a tunnel it's the hill's height)
		var lc := cols - 1
		var la := lv[r * cols + lc]
		var lb := lv[(r + 1) * cols + lc]
		var ra := rv[r * cols]
		var rb := rv[(r + 1) * cols]
		var ma := (la + ra) * 0.5
		ma.y = maxf(la.y, ra.y) + 0.8
		var mb := (lb + rb) * 0.5
		mb.y = maxf(lb.y, rb.y) + 0.8
		var rock: Color = route.look["land"][route.surface_at_s(i * AdventureRoute.STEP)]
		rock = rock.lerp(Color(0.45, 0.43, 0.4), 0.6)
		AdventureProps._quad(cap, la, ma, mb, lb, rock)
		AdventureProps._quad(cap, ma, ra, rb, mb, rock)
	for r in inside.size():
		if not inside[r]:
			continue
		var i := i0 + r
		var e := route.eq[i] if i < route.eq.size() else i
		var tn := route.tun_k[i]
		var t: Dictionary = route.tunnels[tn]
		var from_k0 := e - int(t["k0"])
		var to_k1 := int(t["k1"]) - e
		if from_k0 % LAMP_EVERY == 2 or to_k1 == 2:
			lights.append(Vector3(route.px[i] - ax, route.ph[i] + WALL + 1.4, route.pz[i] - az))
		if from_k0 == 0 or to_k1 == 0:
			_portal(route, i, ax, az, rings[r], -1.0 if from_k0 == 0 else 1.0, portals, faces, boards, title(route, tn))
	out["tunnel"] = {"tube": tube, "faces": faces, "cap": cap, "glow": glow, "portals": portals, "lights": lights, "boards": boards}


## A portal at knot `i` (its tube's first or last ring `ring`), facing `face` (-1 back down the
## road, the way in for traffic going on; +1 on): the concrete headwall round the arch up to the
## rock, a band round the arch, wing walls either side, and the name board over it.
static func _portal(route: AdventureRoute, i: int, ax: float, az: float, ring: Array, face: float, arr: Dictionary,
		faces: PackedVector3Array, boards: Array, text: String) -> void:
	var fwd := Vector3(sin(route.hd[i]), 0.0, -cos(route.hd[i]))
	var right := Vector3(cos(route.hd[i]), 0.0, sin(route.hd[i]))
	var c := Vector3(route.px[i] - ax, route.ph[i], route.pz[i] - az)
	var off := fwd * face * 0.25
	var top := route.ph[i] + AdventureRoute.TUNNEL_COVER + 0.4
	var w := route.width[i] * 0.5 + SIDE
	var wing := w + 2.8
	var quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
		# Facing out of the tunnel whichever end it is.
		if face < 0.0:
			AdventureProps._quad(arr, p0, p1, p2, p3, col)
		else:
			AdventureProps._quad(arr, p3, p2, p1, p0, col)
		faces.append_array([p0, p1, p2, p0, p2, p3])
	# Over the arch: from each of its points straight up to the top.
	for k in range(2, ring.size() - 3):
		var a: Vector3 = ring[k] + off
		var b: Vector3 = ring[k + 1] + off
		quad.call(a, b, Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), PORTAL)
	# The wings, either side of the arch.
	var lb := c - right * wing + off
	var rb := c + right * wing + off
	var lw: Vector3 = ring[1] + off
	var rw: Vector3 = ring[ring.size() - 2] + off
	quad.call(lb + Vector3.DOWN * 0.4, lw + Vector3.DOWN * 0.3, Vector3(lw.x, top, lw.z), Vector3(lb.x, top, lb.z), PORTAL.darkened(0.06))
	quad.call(rw + Vector3.DOWN * 0.3, rb + Vector3.DOWN * 0.4, Vector3(rb.x, top, rb.z), Vector3(rw.x, top, rw.z), PORTAL.darkened(0.06))
	# A lighter band round the arch, standing a little proud.
	var hub := c + Vector3.UP * WALL + off * 2.0
	var band := func(k: int) -> Vector3:
		var p: Vector3 = ring[k] + off * 2.0
		if k == 1 or k == ring.size() - 2:
			return p + right * (0.45 if k > 1 else -0.45)   # the wall's feet: straight out
		return p + (p - hub).normalized() * 0.45
	for k in range(1, ring.size() - 2):
		var a: Vector3 = ring[k] + off * 2.0
		var b: Vector3 = ring[k + 1] + off * 2.0
		quad.call(band.call(k), band.call(k + 1), b, a, PORTAL.lightened(0.18))
	# The name board.
	var board_c := c + Vector3.UP * (WALL + ARCH + 0.9) + off * 3.0
	var bxf := Transform3D(Basis(Vector3.UP, atan2(fwd.x * face, fwd.z * face)), board_c)
	AdventureProps.box(arr, bxf * Transform3D(Basis(), Vector3(0, -0.35, 0)), Vector3(4.2, 0.7, 0.06), Color(0.08, 0.22, 0.55))
	boards.append({"xf": bxf * Transform3D(Basis(), Vector3(0, 0.0, 0.05)), "text": text})


# ---------------------------------------------------------------------------- nodes

## Makes chunk `data`'s tunnel (see build) into nodes under the chunk's `node`.
static func commit(data: Dictionary, node: Node3D) -> void:
	var t: Dictionary = data.get("tunnel", {})
	if t.is_empty():
		return
	var root := Node3D.new()
	root.name = "Tunnel"
	node.add_child(root)
	var tube := MeshInstance3D.new()
	tube.name = "Tube"
	tube.mesh = AdventureProps.to_mesh(t["tube"])
	tube.material_override = tube_material()
	root.add_child(tube)
	var cap := MeshInstance3D.new()
	cap.name = "Rock"
	cap.mesh = AdventureProps.to_mesh(t["cap"])
	cap.material_override = AdventureSurface.land_material()
	root.add_child(cap)
	if not (t["portals"]["v"] as PackedVector3Array).is_empty():
		var p := MeshInstance3D.new()
		p.name = "Portals"
		p.mesh = AdventureProps.to_mesh(t["portals"])
		p.material_override = tube_material()
		root.add_child(p)
	var g := MeshInstance3D.new()
	g.name = "LampStrips"
	g.mesh = AdventureProps.to_mesh(t["glow"])
	g.material_override = glow_material()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	for at in t["lights"]:
		var l := OmniLight3D.new()
		l.omni_range = LAMP_RANGE
		l.light_energy = LAMP_ENERGY
		l.light_color = LAMP_COLOR
		l.shadow_enabled = false
		l.position = at
		l.add_to_group("adv_tunnel_lamp")
		root.add_child(l)
	for b in t["boards"]:
		var label := Label3D.new()
		label.text = str(b["text"]).to_upper()
		label.font_size = 64
		label.pixel_size = 0.0075
		label.outline_size = 0
		label.modulate = Color(0.95, 0.95, 0.95)
		label.transform = b["xf"]
		label.visibility_range_end = 220.0
		root.add_child(label)
	var body := StaticBody3D.new()
	body.name = "TunnelBody"
	body.collision_layer = 1
	body.set_meta("surface", "tarmac")
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(t["faces"])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


## The tube's material: vertex coloured, both sides drawn (the portals' hoods are seen from out).
static func tube_material() -> StandardMaterial3D:
	if _tube_mat:
		return _tube_mat
	_tube_mat = StandardMaterial3D.new()
	_tube_mat.vertex_color_use_as_albedo = true
	_tube_mat.vertex_color_is_srgb = true
	_tube_mat.roughness = 0.75
	_tube_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tube_mat.albedo_texture = AdventureSurface.noise_texture(0.08, 0.8, 1.1, 91)
	_tube_mat.uv1_triplanar = true
	_tube_mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	return _tube_mat


## The lamp strips' glow: lit whatever the time of day.
static func glow_material() -> StandardMaterial3D:
	if _glow_mat:
		return _glow_mat
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.emission_enabled = true
	_glow_mat.emission = LAMP_COLOR
	_glow_mat.emission_energy_multiplier = 2.2
	return _glow_mat
