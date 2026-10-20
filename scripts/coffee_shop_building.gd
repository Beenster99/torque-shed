class_name CoffeeShopBuilding
extends SalesOffice
## The coffee shop next door, the Pit Stop Cafe (see CoffeeShop for what goes on in it): a small
## single-storey brick building with big windows, a striped awning and a lit sign. Inside, a
## counter with a coffee machine, a cake display and the till, the barista's back counter, a
## kitchen through the hatch behind it with the menu boards either side, and four tables on a
## black and white tiled floor. In front, a terrace of eight tables under umbrellas behind a row
## of planters, festoon lights, and the car park with twenty marked bike bays and a sign pylon.
## Its lights, sign glow and the OPEN sign follow the opening hours (CoffeeShop.is_open); the rest
## of the time the CLOSED signs are up. Built from SalesOffice's pieces and materials.
##
## Every position here is in world coordinates (the Workshop it's built into sits at the origin).

const C := CoffeeShop.CENTER
const H := CoffeeShop.CEIL_Y
## The front of the building (the outside face of its front wall) and where the pylon stands.
const FRONT_Z := CoffeeShop.CENTER.z + CoffeeShop.HALF.y + CoffeeShop.WALL
const PYLON := Vector3(-18.6, 0.0, 80.4)

var _open_signs: Array[Node3D] = []
var _closed_signs: Array[Node3D] = []
var _fascia: Label3D


func build() -> void:
	name = "CoffeeShop"
	add_to_group("coffee_shop")
	_make_materials()
	_make_cafe_materials()
	_build_ground()
	_build_walls()
	_build_awning_and_sign()
	_build_counter()
	_build_cafe_kitchen()
	_build_tables()
	_build_decor()
	_build_cafe_lights()
	_build_car_park()
	_show_open(CoffeeShop.is_open())


func _process(_delta: float) -> void:
	var pt := Perf.t0()
	_process_body(_delta)
	Perf.add("rooms", pt)


func _process_body(_delta: float) -> void:
	if _lights_shown != CoffeeShop.is_open():
		_show_open(CoffeeShop.is_open())


## Open: lights on, the sign lit, OPEN up. Shut: dark, CLOSED up.
func _show_open(open: bool) -> void:
	set_lights(open)
	for n in _open_signs:
		n.visible = open
	for n in _closed_signs:
		n.visible = not open
	if _fascia:
		_fascia.modulate = Color(1.0, 0.86, 0.45) if open else Color(0.45, 0.4, 0.32)


## Whether the OPEN sign is up (tests).
func open_shown() -> bool:
	return _lights_shown == true and not _open_signs.is_empty() and _open_signs[0].visible


func _make_cafe_materials() -> void:
	var brick := _material(Color(0.56, 0.25, 0.18), 0.0, 0.9, _tiles(Color(1, 1, 1), Color(0.78, 0.74, 0.7), 8), 1.0)
	brick.uv1_scale = Vector3(1.0, 1.0, 1.0) / 1.2
	_mats["brick"] = brick
	_mats["cream"] = _material(Color(0.93, 0.89, 0.8), 0.0, 0.8)
	_mats["green"] = _material(Color(0.08, 0.28, 0.2), 0.1, 0.5)
	_mats["red"] = _material(Color(0.72, 0.1, 0.08), 0.0, 0.6)
	_mats["chalk"] = _material(Color(0.06, 0.08, 0.07), 0.0, 0.9)
	_mats["cake"] = _material(Color(0.95, 0.82, 0.6), 0.0, 0.7)
	_mats["icing"] = _material(Color(0.96, 0.6, 0.7), 0.0, 0.5)
	_mats["chocolate"] = _material(Color(0.3, 0.17, 0.1), 0.0, 0.5)
	var check := _material(Color(1, 1, 1), 0.0, 0.25, _checker(), 1.0)
	check.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.6
	_mats["checker"] = check
	var terrace := _material(Color(0.72, 0.66, 0.58), 0.0, 0.9, _tiles(Color(1, 1, 1), Color(0.72, 0.72, 0.72)), 1.0)
	terrace.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.5
	_mats["terrace"] = terrace
	# Glowing bits that follow the opening hours (set_lights): the sign's neon, the pendants and
	# the festoon bulbs.
	_mats["neon"] = _glow(Color(1.0, 0.5, 0.15), 4.0)
	_mats["neon_green"] = _glow(Color(0.3, 1.0, 0.45), 3.0)
	_mats["pendant"] = _glow(Color(1.0, 0.85, 0.6), 3.0)
	_mats["bulb"] = _glow(Color(1.0, 0.8, 0.5), 3.5)
	for k in ["red", "cream", "green"]:
		var canvas := _material((_mats[k] as StandardMaterial3D).albedo_color, 0.0, 0.95)
		canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["canvas_" + k] = canvas


## A black and white checkerboard, one pair of tiles a texture repeat.
func _checker() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var black := (x < n / 2) != (y < n / 2)
			var c := Color(0.08, 0.08, 0.08) if black else Color(0.92, 0.91, 0.88)
			if x % (n / 2) == 0 or y % (n / 2) == 0:
				c = Color(0.5, 0.5, 0.5)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------- the building

## The slab and floors: the checkerboard in the cafe, kitchen tiles behind the counter.
func _build_ground() -> void:
	var hx := CoffeeShop.HALF.x
	var hz := CoffeeShop.HALF.y
	var t := CoffeeShop.WALL
	_solid(C + Vector3(0.0, -0.1, 0.0), Vector3(hx * 2.0 + t * 2.0, 0.2, hz * 2.0 + t * 2.0), _mats["kerb"])
	_flat(C + Vector3(0.0, 0.012, 0.0), Vector3(hx * 2.0, 0.006, hz * 2.0), _mats["checker"])
	var kx := (CoffeeShop.KITCHEN_X + C.x + hx) * 0.5
	var kz0 := C.z - hz
	_flat(Vector3(kx, 0.016, (kz0 + CoffeeShop.COUNTER.z) * 0.5), Vector3(C.x + hx - CoffeeShop.KITCHEN_X, 0.006,
		CoffeeShop.COUNTER.z - kz0), _mats["kitchen_floor"])
	# The terrace's paving, out to the car park's kerb.
	var tr := CoffeeShop.TERRACE
	_flat(Vector3(tr.get_center().x, 0.008, tr.get_center().y), Vector3(tr.size.x, 0.016, tr.size.y), _mats["terrace"])


## Brick walls, a front of big windows either side of the door, and a flat roof.
func _build_walls() -> void:
	var hx := CoffeeShop.HALF.x
	var hz := CoffeeShop.HALF.y
	var t := CoffeeShop.WALL
	var x0 := C.x - hx
	var x1 := C.x + hx
	_solid(Vector3(C.x, H * 0.5, C.z - hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, H, t), _mats["brick"])
	_solid(Vector3(x0 - t * 0.5, H * 0.5, C.z), Vector3(t, H, hz * 2.0), _mats["brick"])
	_solid(Vector3(x1 + t * 0.5, H * 0.5, C.z), Vector3(t, H, hz * 2.0), _mats["brick"])
	# Inside the walls are cream, with a green dado.
	_deco(Vector3(C.x, H * 0.5, C.z - hz + 0.005), Vector3(hx * 2.0, H, 0.01), _mats["cream"])
	_deco(Vector3(x0 + 0.005, H * 0.5, C.z), Vector3(0.01, H, hz * 2.0), _mats["cream"])
	_deco(Vector3(x1 - 0.005, H * 0.5, C.z), Vector3(0.01, H, hz * 2.0), _mats["cream"])
	_deco(Vector3(x0 + 0.012, 0.5, C.z), Vector3(0.01, 1.0, hz * 2.0), _mats["green"])
	_deco(Vector3((x0 + CoffeeShop.KITCHEN_X) * 0.5, 0.5, C.z - hz + 0.012), Vector3(CoffeeShop.KITCHEN_X - x0, 1.0, 0.01), _mats["green"])
	# The front: a brick sill and header, glass between, the door in the middle.
	var z := C.z + hz + t * 0.5
	var dx := CoffeeShop.WALK_X
	var dh := CoffeeShop.DOOR_HALF
	for side: Array in [[x0 - t, dx - dh], [dx + dh, x1 + t]]:
		var a: float = side[0]
		var b: float = side[1]
		var mid := (a + b) * 0.5
		var w := b - a
		_solid(Vector3(mid, 0.45, z), Vector3(w, 0.9, t), _mats["brick"])
		_solid(Vector3(mid, 1.7, z), Vector3(w, 1.6, 0.04), _mats["glass"], false)
		_solid(Vector3(mid, 2.75, z), Vector3(w, 0.5, t), _mats["brick"])
		for k in 4:
			_deco(Vector3(a + 0.12 + k * (w - 0.24) / 3.0, 1.7, z), Vector3(0.07, 1.6, 0.1), _mats["green"])
		_deco(Vector3(mid, 0.93, z), Vector3(w, 0.06, 0.32), _mats["green"])
	_solid(Vector3(dx, (DOOR_HEIGHT_CAFE() + H) * 0.5, z), Vector3(dh * 2.0, H - DOOR_HEIGHT_CAFE(), t), _mats["brick"])
	for s in [-1.0, 1.0]:
		_deco(Vector3(dx + s * dh, DOOR_HEIGHT_CAFE() * 0.5, z), Vector3(0.1, DOOR_HEIGHT_CAFE(), 0.3), _mats["green"])
	_deco(Vector3(dx, DOOR_HEIGHT_CAFE() + 0.05, z), Vector3(dh * 2.0 + 0.1, 0.1, 0.3), _mats["green"])
	# The door stands open, hooked back against the inside of the front wall.
	var leaf := Node3D.new()
	leaf.position = Vector3(dx - dh, 0.0, z - t * 0.5)
	leaf.rotation.y = PI * 0.5
	add_child(leaf)
	_deco(Vector3(-0.78, DOOR_HEIGHT_CAFE() * 0.5, -0.04), Vector3(1.5, DOOR_HEIGHT_CAFE() - 0.05, 0.05), _mats["green"], leaf)
	_deco(Vector3(-0.78, 1.35, -0.04), Vector3(1.2, 1.4, 0.06), _mats["glass"], leaf)
	_deco(Vector3(-0.78, 0.95, -0.075), Vector3(0.3, 0.03, 0.03), _mats["brass"], leaf)
	# The roof: flat, with a parapet; inside, the ceiling.
	_solid(Vector3(C.x, H + 0.1, C.z), Vector3(hx * 2.0 + t * 2.0 + 0.2, 0.2, hz * 2.0 + t * 2.0 + 0.2), _mats["ceiling"])
	_deco(Vector3(C.x, H + 0.4, C.z - hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, 0.4, t), _mats["brick"])
	for s in [-1.0, 1.0]:
		_deco(Vector3(C.x + s * (hx + t * 0.5), H + 0.4, C.z), Vector3(t, 0.4, hz * 2.0 + t * 2.0), _mats["brick"])
	# Mat inside the door.
	_flat(Vector3(dx, 0.02, C.z + hz - 0.6), Vector3(1.6, 0.012, 0.9), _mats["leather"])


static func DOOR_HEIGHT_CAFE() -> float:
	return CoffeeShop.DOOR_HEIGHT


## The striped awning over the windows and the terrace's inner edge, the fascia with the name
## in neon over it, and the OPEN / CLOSED sign hanging in the window by the door.
func _build_awning_and_sign() -> void:
	var hx := CoffeeShop.HALF.x
	var t := CoffeeShop.WALL
	var w := hx * 2.0 + t * 2.0
	var stripes := 14
	var sw := w / stripes
	for k in stripes:
		var x := C.x - w * 0.5 + sw * (k + 0.5)
		var mat: Material = _mats["canvas_red"] if k % 2 == 0 else _mats["canvas_cream"]
		var piece := _deco(Vector3(x, 2.62, FRONT_Z + 0.62), Vector3(sw, 0.03, 1.3), mat)
		piece.rotation.x = 0.38
		var drop := _deco(Vector3(x, 2.25, FRONT_Z + 1.24), Vector3(sw, 0.22, 0.02), mat)
		drop.rotation.x = 0.0
	# The fascia: a green board along the parapet with the name in letters and a neon outline.
	_deco(Vector3(C.x, H + 0.42, FRONT_Z + 0.06), Vector3(w + 0.1, 0.62, 0.12), _mats["green"])
	_fascia = _label("PIT STOP CAFE", Vector3(C.x, H + 0.42, FRONT_Z + 0.125), 0.0, 120, Color(1.0, 0.86, 0.45), 0.004, 10)
	_fascia.name = "CafeSign"
	_deco(Vector3(C.x, H + 0.72, FRONT_Z + 0.13), Vector3(w - 0.4, 0.03, 0.02), _mats["neon"])
	_deco(Vector3(C.x, H + 0.12, FRONT_Z + 0.13), Vector3(w - 0.4, 0.03, 0.02), _mats["neon"])
	_label("COFFEE · TEA · CAKES · SANDWICHES  ·  BIKERS WELCOME", Vector3(C.x, 2.85, FRONT_Z + 0.03), 0.0, 30,
		Color(0.95, 0.95, 0.9), 0.004)
	# The hanging sign in the window right of the door: OPEN in neon green, or CLOSED.
	var sx := CoffeeShop.WALK_X + CoffeeShop.DOOR_HALF + 0.9
	_deco(Vector3(sx, 1.9, FRONT_Z - 0.2), Vector3(0.9, 0.36, 0.02), _mats["chalk"])
	var open := _label("OPEN", Vector3(sx, 1.9, FRONT_Z - 0.185), 0.0, 56, Color(0.4, 1.0, 0.5), 0.004)
	open.name = "OpenSign"
	_open_signs.append(open)
	var open_glow := _deco(Vector3(sx, 1.9, FRONT_Z - 0.21), Vector3(0.84, 0.3, 0.01), _mats["neon_green"])
	open_glow.transparency = 0.7
	_open_signs.append(open_glow)
	var closed := _label("CLOSED\nopen 8am - 6pm", Vector3(sx, 1.9, FRONT_Z - 0.185), 0.0, 30, Color(1.0, 0.45, 0.35), 0.004)
	closed.name = "ClosedSign"
	_closed_signs.append(closed)


# ---------------------------------------------------------------------------- inside

## The counter (with the coffee machine, the cake display and the till), the barista's back
## counter, and the wall with the kitchen hatch and the menu boards.
func _build_counter() -> void:
	var c := CoffeeShop.COUNTER
	var size := CoffeeShop.COUNTER_SIZE
	var counter := _solid(c + Vector3(0.0, size.y * 0.5, 0.0), size, _mats["oak"])
	counter.name = "CafeCounter"
	counter.set_meta("coffee_counter", true)
	_deco(c + Vector3(0.0, size.y + 0.02, 0.0), Vector3(size.x + 0.1, 0.04, size.z + 0.1), _mats["quartz"])
	_deco(c + Vector3(0.0, 0.5, size.z * 0.5 + 0.01), Vector3(size.x - 0.2, 0.7, 0.01), _mats["green"])
	_label("PIT STOP", c + Vector3(0.0, 0.6, size.z * 0.5 + 0.02), 0.0, 60, Color(1.0, 0.86, 0.45), 0.004)
	var top := c.y + size.y + 0.04
	# The coffee machine at the back of the counter, facing the barista, with cups on top.
	var m := c + Vector3(-1.4, top, -0.1)
	_deco(m + Vector3(0.0, 0.24, 0.0), Vector3(0.7, 0.48, 0.42), _mats["chrome"])
	_deco(m + Vector3(0.0, 0.34, -0.22), Vector3(0.6, 0.18, 0.02), _mats["red"])
	for k in 2:
		_cyl(m + Vector3(-0.16 + k * 0.32, 0.16, -0.27), 0.04, 0.08, _mats["anthracite"])
		_cyl(m + Vector3(-0.16 + k * 0.32, 0.03, -0.3), 0.035, 0.06, _mats["white_gloss"])
	for k in 5:
		_cyl(m + Vector3(-0.24 + k * 0.12, 0.52, 0.0), 0.035, 0.07, _mats["white_gloss"])
	# Grinder beside it.
	_cyl(m + Vector3(0.55, 0.18, 0.0), 0.09, 0.36, _mats["anthracite"])
	_cyl(m + Vector3(0.55, 0.44, 0.0), 0.08, 0.16, _mats["glass"], 0.05)
	# The cake display at the east end: a glass case with cakes on stands.
	var d := c + Vector3(1.5, top, 0.0)
	_deco(d + Vector3(0.0, 0.01, 0.0), Vector3(1.0, 0.02, 0.55), _mats["white_gloss"])
	_deco(d + Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.42, 0.55), _mats["glass"])
	for k in 3:
		var at := d + Vector3(-0.3 + k * 0.3, 0.02, 0.0)
		var mat: Material = [_mats["cake"], _mats["chocolate"], _mats["icing"]][k]
		_cyl(at + Vector3(0.0, 0.07, 0.0), 0.11, 0.12, mat)
		_cyl(at + Vector3(0.0, 0.14, 0.0), 0.112, 0.02, _mats["icing"] if k != 2 else _mats["cream"])
	# The till and a tip jar.
	_deco(c + Vector3(0.4, top + 0.08, 0.15), Vector3(0.32, 0.16, 0.26), _mats["anthracite"])
	_deco(c + Vector3(0.4, top + 0.2, 0.08), Vector3(0.26, 0.14, 0.02), _mats["monitor"])
	_cyl(c + Vector3(0.0, top + 0.07, 0.22), 0.06, 0.14, _mats["glass"])
	# The barista's back counter against the kitchen wall, with a fridge of milk under it.
	var kz := CoffeeShop.KITCHEN_Z
	var bx0 := CoffeeShop.KITCHEN_X + 0.2
	var bx1 := C.x + CoffeeShop.HALF.x - 0.05
	_solid(Vector3((bx0 + bx1) * 0.5, 0.475, kz + 0.4), Vector3(bx1 - bx0, 0.95, 0.5), _mats["white_gloss"])
	_deco(Vector3((bx0 + bx1) * 0.5, 0.97, kz + 0.4), Vector3(bx1 - bx0, 0.04, 0.52), _mats["oak"])
	for k in 4:
		_cyl(Vector3(bx0 + 0.4 + k * 0.25, 1.05, kz + 0.35), 0.05, 0.12, _mats["white_gloss"])
	# The wall behind, with the hatch through to the kitchen.
	var hatch := Vector2(-22.9, -21.5)
	var wx0 := CoffeeShop.KITCHEN_X
	var wx1 := C.x + CoffeeShop.HALF.x
	var wz := kz + 0.075
	_solid(Vector3((wx0 + hatch.x) * 0.5, H * 0.5, wz), Vector3(hatch.x - wx0, H, 0.15), _mats["cream"])
	_solid(Vector3((hatch.y + wx1) * 0.5, H * 0.5, wz), Vector3(wx1 - hatch.y, H, 0.15), _mats["cream"])
	_solid(Vector3((hatch.x + hatch.y) * 0.5, 0.475, wz), Vector3(hatch.y - hatch.x, 0.95, 0.15), _mats["cream"])
	_solid(Vector3((hatch.x + hatch.y) * 0.5, (1.85 + H) * 0.5, wz), Vector3(hatch.y - hatch.x, H - 1.85, 0.15), _mats["cream"])
	_deco(Vector3((hatch.x + hatch.y) * 0.5, 0.97, wz), Vector3(hatch.y - hatch.x + 0.1, 0.04, 0.3), _mats["steel"])
	_label("ORDER HERE", Vector3((hatch.x + hatch.y) * 0.5, 2.0, wz + 0.08), 0.0, 34, Color(1.0, 0.86, 0.45), 0.004)
	# The menu boards either side of the hatch.
	for side: Array in [[-23.75, "COFFEE   £3\nTEA   £2"], [-20.6, "CAKE   £3\nSANDWICH   £5"]]:
		var bx: float = side[0]
		_deco(Vector3(bx, 2.3, wz + 0.085), Vector3(1.4, 0.8, 0.03), _mats["chalk"])
		_deco(Vector3(bx, 2.3, wz + 0.08), Vector3(1.48, 0.88, 0.02), _mats["oak"])
		_label(str(side[1]), Vector3(bx, 2.3, wz + 0.105), 0.0, 40, Color(0.95, 0.95, 0.9), 0.004)
	# The kitchen's side wall.
	var kd := kz - (C.z - CoffeeShop.HALF.y)
	_solid(Vector3(wx0 - 0.075, H * 0.5, kz - kd * 0.5), Vector3(0.15, H, kd), _mats["cream"])


## Through the hatch: the kitchen, with a cooker, a fridge, shelves and a bread board.
func _build_cafe_kitchen() -> void:
	var z0 := C.z - CoffeeShop.HALF.y
	_solid(Vector3(-23.6, 0.45, z0 + 0.35), Vector3(1.4, 0.9, 0.6), _mats["steel"])
	_deco(Vector3(-23.6, 0.92, z0 + 0.35), Vector3(1.4, 0.04, 0.6), _mats["stone_dark"])
	for k in 2:
		_cyl(Vector3(-23.9 + k * 0.6, 1.0, z0 + 0.35), 0.12, 0.12, _mats["anthracite"])
	_solid(Vector3(-20.0, 0.95, z0 + 0.35), Vector3(0.75, 1.9, 0.6), _mats["chrome"])
	_solid(Vector3(-21.7, 0.45, z0 + 0.35), Vector3(1.5, 0.9, 0.6), _mats["white_gloss"])
	_deco(Vector3(-21.7, 0.92, z0 + 0.35), Vector3(1.5, 0.04, 0.6), _mats["oak"])
	for k in 3:
		_deco(Vector3(-21.9 + k * 0.25, 0.98, z0 + 0.3), Vector3(0.18, 0.08, 0.1), _mats["cake"])
	_deco(Vector3(-22.2, 1.8, z0 + 0.15), Vector3(2.6, 0.04, 0.25), _mats["oak"])
	for k in 6:
		_cyl(Vector3(-23.3 + k * 0.4, 1.9, z0 + 0.15), 0.06, 0.16, [_mats["red"], _mats["glass"], _mats["cream"]][k % 3])


## The tables: four inside, eight out on the terrace under umbrellas, four chairs each.
func _build_tables() -> void:
	for i in CoffeeShop.TABLES.size():
		var at: Vector2 = CoffeeShop.TABLES[i][0]
		var out: bool = CoffeeShop.TABLES[i][1]
		var size := CoffeeShop.TABLE_SIZE
		var top_mat: Material = _mats["oak"] if not out else _mats["white_gloss"]
		var leg_mat: Material = _mats["anthracite"] if not out else _mats["alu"]
		var p := Vector3(at.x, 0.0, at.y)
		# Invisible collision to the top's height, so a tray can be put down on it.
		_blocker(p + Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x, size.y, size.z))
		_deco(p + Vector3(0.0, size.y - 0.02, 0.0), Vector3(size.x, 0.04, size.z), top_mat)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_deco(p + Vector3(sx * (size.x * 0.5 - 0.08), size.y * 0.5 - 0.02, sz * (size.z * 0.5 - 0.08)),
					Vector3(0.04, size.y - 0.04, 0.04), leg_mat)
		# A sugar bowl and a napkin holder.
		_cyl(p + Vector3(0.1, size.y + 0.03, 0.0), 0.04, 0.06, _mats["white_gloss"])
		_deco(p + Vector3(-0.12, size.y + 0.05, 0.0), Vector3(0.08, 0.1, 0.04), _mats["steel"])
		for k in 4:
			_cafe_chair(CoffeeShop.seat_xf(i * 4 + k), out)
		if out:
			# The umbrella, its pole through the middle of the table.
			_cyl(p + Vector3(0.0, 1.2, 0.0), 0.025, 2.4, _mats["steel"])
			var canvas: Material = [_mats["canvas_red"], _mats["canvas_green"], _mats["canvas_cream"]][i % 3]
			var shade := _cyl(p + Vector3(0.0, 2.3, 0.0), 1.25, 0.42, canvas, 0.03)
			(shade.mesh as CylinderMesh).radial_segments = 8
			(shade.mesh as CylinderMesh).cap_bottom = false
			_cyl(p + Vector3(0.0, 2.55, 0.0), 0.04, 0.08, _mats["steel"])


## A chair at `xf` (on the floor, -Z facing the table): a seat, a back and four legs.
func _cafe_chair(xf: Transform3D, out: bool) -> void:
	var n := Node3D.new()
	n.transform = xf
	add_child(n)
	var seat_mat: Material = _mats["oak"] if not out else _mats["green"]
	var leg_mat: Material = _mats["anthracite"] if not out else _mats["alu"]
	_deco(Vector3(0.0, 0.45, 0.02), Vector3(0.42, 0.04, 0.4), seat_mat, n)
	_deco(Vector3(0.0, 0.72, 0.21), Vector3(0.42, 0.42, 0.03), seat_mat, n)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_deco(Vector3(sx * 0.18, 0.22, 0.02 + sz * 0.17), Vector3(0.03, 0.44, 0.03), leg_mat, n)


## Pictures of bikes on the walls, a chalkboard of specials, helmets on a shelf and plants.
func _build_decor() -> void:
	var x0 := C.x - CoffeeShop.HALF.x
	var colors := [Color(0.75, 0.2, 0.1), Color(0.15, 0.35, 0.65), Color(0.9, 0.65, 0.1)]
	for k in 3:
		var z := C.z - 2.4 + k * 2.4
		_deco(Vector3(x0 + 0.03, 1.8, z), Vector3(0.03, 0.75, 1.0), _mats["anthracite"])
		var pic := _material(colors[k], 0.0, 0.6)
		_deco(Vector3(x0 + 0.05, 1.8, z), Vector3(0.01, 0.62, 0.86), pic)
		# A bike's silhouette on it: two wheels and a body.
		for w in [-0.25, 0.25]:
			_cyl(Vector3(x0 + 0.06, 1.68, z + w), 0.12, 0.01, _mats["anthracite"]).rotation.z = PI * 0.5
		_deco(Vector3(x0 + 0.06, 1.8, z), Vector3(0.01, 0.12, 0.36), _mats["anthracite"])
	# The specials board by the door, inside.
	var b := Vector3(-19.55, 1.4, C.z + 2.5)
	_deco(b, Vector3(0.03, 0.9, 0.7), _mats["chalk"])
	_label("TODAY\nbacon butty\nlemon drizzle\nflat white", b + Vector3(-0.02, 0.0, 0.0), -PI * 0.5, 28, Color(0.95, 0.95, 0.9), 0.004)
	# Helmets on a shelf on the back wall, left behind by regulars.
	var shelf := Vector3(-28.5, 2.1, C.z - CoffeeShop.HALF.y + 0.15)
	_deco(shelf, Vector3(2.0, 0.04, 0.28), _mats["oak"])
	for k in 3:
		var hm := _ball(shelf + Vector3(-0.6 + k * 0.6, 0.15, 0.0), 0.14, [_mats["red"], _mats["anthracite"], _mats["white_gloss"]][k])
		hm.scale = Vector3(1.0, 0.9, 1.1)
	# Plants in the corners.
	for p in [Vector3(x0 + 0.35, 0.0, C.z + CoffeeShop.HALF.y - 0.35), Vector3(-24.0, 0.0, C.z + CoffeeShop.HALF.y - 0.35)]:
		_cyl(p + Vector3(0.0, 0.2, 0.0), 0.2, 0.4, _mats["pot"], 0.24)
		_ball(p + Vector3(0.0, 0.65, 0.0), 0.32, _mats["plant"])


## Pendants over the tables and the counter, a light in the kitchen and an ambient probe, all on
## while it's open; festoon bulbs over the terrace.
func _build_cafe_lights() -> void:
	var lamps := [Vector3(-29.85, 0.0, 57.4), Vector3(-27.25, 0.0, 57.4), Vector3(-29.85, 0.0, 60.9), Vector3(-27.25, 0.0, 60.9),
		Vector3(-23.3, 0.0, 58.6), Vector3(-21.1, 0.0, 58.6)]
	for p in lamps:
		_cyl(p + Vector3(0.0, H - 0.3, 0.0), 0.006, 0.6, _mats["anthracite"])
		_cyl(p + Vector3(0.0, H - 0.68, 0.0), 0.04, 0.18, _mats["green"], 0.17)
		_ball(p + Vector3(0.0, H - 0.78, 0.0), 0.06, _mats["pendant"])
	var fills := [[Vector3(-28.5, 2.3, 59.2), 6.5, 1.0, true], [Vector3(-22.2, 2.3, 59.0), 5.0, 0.9, false],
		[Vector3(-22.2, 2.2, 56.2), 3.5, 0.7, false], [Vector3(-25.25, 2.4, 62.0), 4.0, 0.5, false]]
	for f in fills:
		var omni := OmniLight3D.new()
		omni.position = f[0]
		omni.omni_range = f[1]
		omni.light_energy = f[2]
		omni.light_color = Color(1.0, 0.85, 0.65)
		omni.shadow_enabled = f[3]
		add_child(omni)
		_lights.append(omni)
	_probe = ReflectionProbe.new()
	_probe.position = C + Vector3(0.0, H * 0.5, 0.0)
	_probe.size = Vector3(CoffeeShop.HALF.x * 2.0 + 0.2, H, CoffeeShop.HALF.y * 2.0 + 0.2)
	_probe.interior = true
	_probe.box_projection = true
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color(0.66, 0.58, 0.5)
	_probe.ambient_color_energy = 0.5
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)
	# Festoon lights: strings of bulbs from the awning out to two posts at the terrace's front.
	var tr := CoffeeShop.TERRACE
	var posts := [Vector3(tr.position.x + 0.15, 0.0, tr.end.y - 0.2), Vector3(tr.end.x - 0.15, 0.0, tr.end.y - 0.2)]
	for p in posts:
		_cyl(p + Vector3(0.0, 1.4, 0.0), 0.05, 2.8, _mats["anthracite"])
	var ends := [[Vector3(tr.position.x + 0.3, 2.7, FRONT_Z + 0.1), posts[1] + Vector3(0.0, 2.75, 0.0)],
		[Vector3(tr.end.x - 0.3, 2.7, FRONT_Z + 0.1), posts[0] + Vector3(0.0, 2.75, 0.0)],
		[posts[0] + Vector3(0.0, 2.75, 0.0), posts[1] + Vector3(0.0, 2.75, 0.0)]]
	for e in ends:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		for k in 15:
			var u := (k + 0.5) / 15.0
			var p := a.lerp(b, u) - Vector3.UP * (0.35 * 4.0 * u * (1.0 - u))
			_ball(p, 0.035, _mats["bulb"])


# ---------------------------------------------------------------------------- outside

## The terrace's planters, the car park with its twenty bays, a lamp and the sign pylon.
func _build_car_park() -> void:
	var tr := CoffeeShop.TERRACE
	var cp := CoffeeShop.CAR_PARK
	# Planters along the front of the terrace, with the gap for the walkway.
	var gap := Vector2(CoffeeShop.WALK_X - 1.05, CoffeeShop.WALK_X + 1.05)
	for span: Vector2 in [Vector2(tr.position.x + 0.1, gap.x), Vector2(gap.y, tr.end.x - 0.1)]:
		var mid := (span.x + span.y) * 0.5
		var w := span.y - span.x
		_solid(Vector3(mid, 0.22, tr.end.y - 0.2), Vector3(w, 0.44, 0.4), _mats["anthracite"])
		_deco(Vector3(mid, 0.55, tr.end.y - 0.2), Vector3(w - 0.1, 0.3, 0.32), _mats["plant"])
	# Tarmac, a kerb along the terrace and white bay lines.
	_flat(Vector3(cp.get_center().x, 0.007, cp.get_center().y), Vector3(cp.size.x, 0.014, cp.size.y), _mats["tarmac"])
	_flat(Vector3(cp.get_center().x, 0.03, cp.position.y), Vector3(cp.size.x, 0.06, 0.16), _mats["kerb"])
	var xs := []
	for i in CoffeeShop.PARK_SLOTS:
		var o := CoffeeShop.park_xf(i).origin
		xs.append([o, i < CoffeeShop.ROW_A_X.size()])
	for e in xs:
		var o: Vector3 = e[0]
		var step := 1.35 if e[1] else CoffeeShop.ROW_B_STEP
		for s in [-0.5, 0.5]:
			_flat(Vector3(o.x + s * step, 0.016, o.z), Vector3(0.07, 0.004, 2.2), _mats["line"])
	_flat(Vector3(cp.get_center().x, 0.016, CoffeeShop.ROW_A_Z + 1.15), Vector3(cp.size.x - 0.6, 0.004, 0.07), _mats["line"])
	_flat(Vector3(cp.get_center().x, 0.016, CoffeeShop.ROW_B_Z - 1.15), Vector3(cp.size.x - 0.6, 0.004, 0.07), _mats["line"])
	var word := _label("MOTORCYCLES ONLY", Vector3(CoffeeShop.WALK_X - 2.5, 0.02, CoffeeShop.AISLE_Z), 0.0, 90, Color(0.92, 0.92, 0.88), 0.006)
	word.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	# A lamp at the car park's west end that comes on at dusk.
	var base := Vector3(cp.position.x - 0.4, 0.0, CoffeeShop.AISLE_Z)
	_cyl(base + Vector3(0.0, 2.5, 0.0), 0.06, 5.0, _mats["alu"])
	_deco(base + Vector3(0.45, 5.0, 0.0), Vector3(0.9, 0.08, 0.25), _mats["alu"])
	var lens := _deco(base + Vector3(0.55, 4.955, 0.0), Vector3(0.6, 0.01, 0.2), _mats["night_white"])
	_night(lens, 5.0)
	var spot := SpotLight3D.new()
	spot.position = base + Vector3(0.55, 4.9, 0.0)
	spot.rotation.x = -PI * 0.5
	spot.spot_angle = 65.0
	spot.spot_range = 10.0
	spot.light_color = Color(1.0, 0.92, 0.8)
	spot.light_energy = 0.0
	spot.visible = false
	spot.set_meta("night_energy", 4.0)
	spot.add_to_group(Daylight.NIGHT_LIGHTS)
	add_child(spot)
	# The sign pylon by the way in, with OPEN or CLOSED under the name.
	_solid(PYLON + Vector3(0.0, 1.8, 0.0), Vector3(1.0, 3.6, 0.3), _mats["green"])
	_deco(PYLON + Vector3(0.0, 3.62, 0.0), Vector3(1.1, 0.06, 0.36), _mats["neon"])
	_label("PIT STOP\nCAFE", PYLON + Vector3(0.0, 2.9, 0.16), 0.0, 60, Color(1.0, 0.86, 0.45), 0.004)
	_label("BIKERS\nWELCOME", PYLON + Vector3(0.0, 2.0, 0.16), 0.0, 40, Color(1, 1, 1), 0.004)
	var open := _label("OPEN", PYLON + Vector3(0.0, 1.1, 0.16), 0.0, 48, Color(0.4, 1.0, 0.5), 0.004)
	_open_signs.append(open)
	var closed := _label("CLOSED", PYLON + Vector3(0.0, 1.1, 0.16), 0.0, 48, Color(1.0, 0.45, 0.35), 0.004)
	_closed_signs.append(closed)
