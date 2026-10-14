class_name Whiteboard
extends Node3D
## The crew whiteboard on the shed wall, for plans, lists and sketches. Walk up and look at it:
## hold the act button to draw where the crosshair is, the second button to rub out, number
## keys pick the pen colour (7 the eraser), the scroll wheel the thickness, T writes a line of
## text, Z undoes your last mark and holding X wipes the whole board. What's on it lives in
## Shed.board (see BoardData); this draws it into a SubViewport shown on the board's face.

## On the front wall inside, left of the roller door, between the corner and the scrap bin.
const MOUNT := Vector3(-4.85, 1.55, 70.47)
const FACING := PI           # turned to face into the shed
const SIZE := Vector2(2.4, 1.2)
const REACH := 2.5
const WIPE_TIME := 1.5       # hold this long to wipe the whole board
const SEND_EVERY := 0.06     # how often a stroke being drawn goes out to everyone
const SPLIT_AT := 240        # a stroke this long carries on as a new one
const FACE_Z := 0.021        # the writing surface, in front of the backing

var pen := 0                 # index into BoardData.COLORS
var width := 1               # index into BoardData.WIDTHS
var eraser := false
var wipe := 0.0              # 0..1 while X is held
var _wipe_done := false
var _viewport: SubViewport
var _ink: Node2D
var _live: Line2D            # the bit of your stroke not sent yet, drawn on top
var _nodes := {}             # mark id -> Line2D or Label
var _sigs := {}
var _dirty := true
var _cursor: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _stroke := {}            # the stroke you're drawing: {id, c, w, pts, sent, timer}
## Pictures: the one you're moving (its mark id, or 0), where you took hold of it, and the
## file dialog for adding one from your PC (picking is true while it's open).
var carrying := 0
var _hold_off := false
var _grab := Vector2.ZERO
var _carry_timer := 0.0
var _carry_sent := {}
var _files: FileDialog
var picking := false
var _image_at := Vector2.ZERO
const IMAGE_FIT := Vector2(420.0, 300.0)   # a new picture goes up at most this big
const TURN_STEP := 15.0                    # degrees a press of a rotate key turns a picture, snapping on
const TURN_NUDGE := 2.0                    # and with snapping off; holding the key turns it freely
const TURN_RATE := 60.0                    # degrees a second, held
var _turn_held := 0.0
const MAX_FILE_BYTES := 40000000           # bigger files than this aren't opened at all


func _ready() -> void:
	add_to_group("whiteboard")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(BoardData.PX)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = BoardData.BG
	bg.size = BoardData.PX
	_viewport.add_child(bg)
	_ink = Node2D.new()
	_viewport.add_child(_ink)
	_live = _line(1.0, Color.BLACK)
	_viewport.add_child(_live)
	_build_board()
	Shed.board_changed.connect(func(): _dirty = true)


func _build_board() -> void:
	var alu := _mat(Color(0.72, 0.74, 0.76), 0.8, 0.35)
	_box(Vector3(0.0, 0.0, 0.01), Vector3(SIZE.x + 0.02, SIZE.y + 0.02, 0.02), _mat(Color(0.5, 0.5, 0.52), 0.0, 0.8))
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	face.mesh = quad
	var gloss := StandardMaterial3D.new()
	gloss.albedo_texture = _viewport.get_texture()
	gloss.roughness = 0.14
	gloss.metallic_specular = 0.75
	# A touch of glow keeps it readable in a dim corner, like light bouncing off white enamel.
	gloss.emission_enabled = true
	gloss.emission_texture = _viewport.get_texture()
	gloss.emission_energy_multiplier = 0.12
	face.material_override = gloss
	face.position.z = FACE_Z
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	# Aluminium frame round the edge.
	var bar := 0.035
	for side in [-1.0, 1.0]:
		_box(Vector3(0.0, side * (SIZE.y + bar) * 0.5, bar * 0.5), Vector3(SIZE.x + bar * 2.0, bar, bar), alu)
		_box(Vector3(side * (SIZE.x + bar) * 0.5, 0.0, bar * 0.5), Vector3(bar, SIZE.y, bar), alu)
	# The pen tray along the bottom, with a few markers and the eraser in it.
	var tray_y := -SIZE.y * 0.5 - bar - 0.008
	var tray_x := SIZE.x * 0.18
	_box(Vector3(tray_x, tray_y, 0.045), Vector3(1.1, 0.012, 0.08), alu)
	_box(Vector3(tray_x, tray_y + 0.014, 0.083), Vector3(1.1, 0.03, 0.006), alu)
	var body := _mat(Color(0.92, 0.92, 0.9), 0.0, 0.4)
	for i in 4:
		var x := tray_x - 0.4 + i * 0.16
		var pen_body := _cylinder(0.009, 0.11, body)
		pen_body.position = Vector3(x, tray_y + 0.015, 0.04 + (i % 2) * 0.016)
		var cap := _cylinder(0.0095, 0.035, _mat(BoardData.COLORS[i], 0.0, 0.35))
		cap.position = pen_body.position + Vector3(0.07, 0.0, 0.0)
	_box(Vector3(tray_x + 0.33, tray_y + 0.012, 0.045), Vector3(0.13, 0.012, 0.05), _mat(Color(0.15, 0.15, 0.17), 0.0, 1.0))
	_box(Vector3(tray_x + 0.33, tray_y + 0.032, 0.045), Vector3(0.13, 0.028, 0.05), _mat(Color(0.1, 0.3, 0.7), 0.0, 0.5))
	# What the crosshair finds.
	var target := StaticBody3D.new()
	target.collision_layer = Workshop.INTERACT_LAYER
	target.collision_mask = 0
	target.set_meta("whiteboard", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SIZE.y, 0.04)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.z = 0.02
	target.add_child(cs)
	add_child(target)
	# A dot on the board where your pen is, in its colour.
	_cursor = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.001
	disc.radial_segments = 20
	disc.rings = 1
	_cursor.mesh = disc
	_cursor_mat = StandardMaterial3D.new()
	_cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor.material_override = _cursor_mat
	_cursor.rotation.x = PI * 0.5
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.visible = false
	add_child(_cursor)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi


## A marker pen lying along the tray.
func _cylinder(radius: float, length: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.rotation.z = PI * 0.5
	add_child(mi)
	return mi


static func _line(w: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = w
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	return line


# ---------------------------------------------------------------------------- drawing the board

## Brings the board's ink up to date with Shed.board, remaking only the marks that changed.
func _refresh() -> void:
	_dirty = false
	var marks: Array = Shed.board.get("marks", [])
	var seen := {}
	for i in marks.size():
		var m: Dictionary = marks[i]
		var id := int(m["id"])
		seen[id] = true
		var sig := _sig(m)
		var node: CanvasItem = _nodes.get(id, null)
		if node == null or _sigs.get(id, "") != sig:
			if node != null and not _fits(node, m):
				_ink.remove_child(node)
				node.queue_free()
				node = null
			node = mark_node(m, node)
			if node.get_parent() == null:
				_ink.add_child(node)
			_nodes[id] = node
			_sigs[id] = sig
		if node.get_index() != i:
			_ink.move_child(node, i)
	for id in _nodes.keys():
		if not seen.has(id):
			_ink.remove_child(_nodes[id])
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)
			_sigs.erase(id)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## What a mark looks like now, so only the marks that changed are drawn again.
static func _sig(m: Dictionary) -> String:
	if m.has("img"):
		return "img|%d|%s|%s|%s|%.2f" % [int(m["img"]), str(m["at"]), str(m["sz"]), str(Shed.image_texture(int(m["img"])) != null),
			BoardData.rotation_of(m)]
	if m.has("text"):
		return "%s|%d|%d|%s" % [m["text"], int(m["c"]), int(m["s"]), str(m["at"])]
	var pts: PackedVector2Array = m["pts"]
	return "%d|%s|%s" % [pts.size(), str(pts[0]), str(pts[pts.size() - 1])]


## Whether `node` is the right kind of node to draw `m` with.
static func _fits(node: CanvasItem, m: Dictionary) -> bool:
	if m.has("img"):
		return node is TextureRect
	return (node is Label) == m.has("text") and not node is TextureRect


static var _waiting_tex: Texture2D


## The node that draws mark `m` on a board (or a poster print of one), reusing `node` if given.
static func mark_node(m: Dictionary, node: CanvasItem) -> CanvasItem:
	if m.has("img"):
		var pic: TextureRect = node if node != null else TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		var tex := Shed.image_texture(int(m["img"]))
		if tex == null:
			# Still on its way from whoever put it up: a grey card where it goes.
			if _waiting_tex == null:
				var grey := Image.create(1, 1, false, Image.FORMAT_RGBA8)
				grey.fill(Color(0.78, 0.8, 0.82))
				_waiting_tex = ImageTexture.create_from_image(grey)
			tex = _waiting_tex
		pic.texture = tex
		pic.position = m["at"]
		pic.size = m["sz"]
		# Turned about its middle, clockwise.
		pic.pivot_offset = (m["sz"] as Vector2) * 0.5
		pic.rotation = deg_to_rad(BoardData.rotation_of(m))
		return pic
	if m.has("text"):
		var label: Label = node if node != null else Label.new()
		label.text = str(m["text"])
		label.position = m["at"]
		label.add_theme_font_size_override("font_size", int(m["s"]))
		label.add_theme_color_override("font_color", BoardData.color_of(m))
		return label
	var line: Line2D = node if node != null else _line(1.0, Color.BLACK)
	line.width = float(m["w"])
	line.default_color = BoardData.color_of(m)
	line.points = _drawable(m["pts"])
	return line


## A single dab still needs two points to show as a dot.
static func _drawable(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() == 1:
		return PackedVector2Array([pts[0], pts[0] + Vector2(0.5, 0.0)])
	return pts


# ---------------------------------------------------------------------------- using it

func _local_walker() -> Walker:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.get_parent() is Walker:
		return cam.get_parent() as Walker
	return null


## Whether the local player is at the board looking at it, ready to draw.
func _here() -> bool:
	var w := _local_walker()
	return w != null and w.controls_enabled and str(w.target.get("kind", "")) == "board"


## Where the crosshair lands on the board, in board pixels, or (-1, -1) when it's off it.
func aim(w: Walker) -> Vector2:
	if w == null:
		return Vector2(-1, -1)
	var inv := global_transform.affine_inverse()
	var from := inv * w.camera.global_position
	var dir := inv.basis * -w.camera.global_transform.basis.z
	if dir.z > -0.0001:
		return Vector2(-1, -1)
	var t := (FACE_Z - from.z) / dir.z
	var hit := from + dir * t
	if t < 0.0 or t > REACH or absf(hit.x) > SIZE.x * 0.5 or absf(hit.y) > SIZE.y * 0.5:
		return Vector2(-1, -1)
	return Vector2((hit.x / SIZE.x + 0.5) * BoardData.PX.x, (0.5 - hit.y / SIZE.y) * BoardData.PX.y)


func _local(p: Vector2) -> Vector3:
	return Vector3((p.x / BoardData.PX.x - 0.5) * SIZE.x, (0.5 - p.y / BoardData.PX.y) * SIZE.y, FACE_Z + 0.002)


func _process(delta: float) -> void:
	var w := _local_walker()
	var p := aim(w) if _here() else Vector2(-1, -1)
	var on := p.x >= 0.0
	if carrying != 0:
		_update_carry(p, delta)
		on = false   # no drawing while a picture is in hand
		_hold_off = true
	elif _hold_off:
		# The press that put a picture down mustn't carry on as a line: wait for it to be let go.
		_hold_off = Input.is_action_pressed("act") or Controls.trigger(true) > 0.5
		on = on and not _hold_off
	var rubbing := on and (Input.is_action_pressed("alt_act") or Controls.trigger(false) > 0.5)
	var drawing := on and (Input.is_action_pressed("act") or Controls.trigger(true) > 0.5)
	var c := BoardData.ERASER if rubbing or eraser else pen
	var px := BoardData.ERASER_WIDTH if c == BoardData.ERASER else float(BoardData.WIDTHS[width])
	_cursor.visible = on
	if on:
		_cursor.position = _local(p)
		var r := maxf(px, 4.0) * SIZE.x / BoardData.PX.x
		_cursor.scale = Vector3(r, 1.0, r)
		_cursor_mat.albedo_color = Color(0.4, 0.42, 0.45, 0.45) if c == BoardData.ERASER else Color(BoardData.COLORS[c], 0.85)
	if (drawing or rubbing) and on:
		if _stroke.is_empty() or int(_stroke["c"]) != c or float(_stroke["w"]) != px:
			_end_stroke()
			_stroke = {"id": _new_id(), "c": c, "w": px, "pts": PackedVector2Array([p]), "sent": 0, "timer": SEND_EVERY}
		else:
			var pts: PackedVector2Array = _stroke["pts"]
			if p.distance_to(pts[pts.size() - 1]) >= maxf(1.5, px * 0.2):
				pts.append(p)
				_stroke["pts"] = pts
				if pts.size() >= SPLIT_AT:
					# Long lines go on as a new stroke from here, so none gets too big to send.
					_end_stroke()
					_stroke = {"id": _new_id(), "c": c, "w": px, "pts": PackedVector2Array([p]), "sent": 0, "timer": SEND_EVERY}
		_stroke["timer"] = float(_stroke["timer"]) + delta
		if float(_stroke["timer"]) >= SEND_EVERY:
			_send(false)
	else:
		_end_stroke()
	_update_live()
	_update_wipe(w, delta)
	if _dirty:
		_refresh()


func _new_id() -> int:
	return 1 + randi() % 1000000000


## Sends the points drawn since last time.
func _send(done: bool) -> void:
	var pts: PackedVector2Array = _stroke["pts"]
	var sent := int(_stroke["sent"])
	_stroke["timer"] = 0.0
	var op := {"a": "board_draw", "id": _stroke["id"], "c": _stroke["c"], "w": _stroke["w"], "from": sent,
		"pts": pts.slice(sent)}
	if done:
		# The finished stroke goes out once more, smoothed down to the points that matter.
		op["from"] = 0
		op["pts"] = BoardData.simplify(pts)
		op["done"] = true
	elif sent >= pts.size():
		return
	_stroke["sent"] = pts.size()
	Shed.board_request(op)


func _end_stroke() -> void:
	if _stroke.is_empty():
		return
	_send(true)
	_stroke = {}


func _update_live() -> void:
	var want := PackedVector2Array()
	if not _stroke.is_empty():
		var pts: PackedVector2Array = _stroke["pts"]
		var sent := int(_stroke["sent"])
		if sent < pts.size():
			want = _drawable(pts.slice(maxi(0, sent - 1)))
			_live.width = float(_stroke["w"])
			_live.default_color = BoardData.color_of({"c": _stroke["c"]})
	if want != _live.points:
		_live.points = want
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Hold X at the board to wipe it all clean. The crosshair ring shows how long is left.
func _update_wipe(w: Walker, delta: float) -> void:
	var holding := _here() and Input.is_action_pressed("board_wipe")
	if not holding:
		wipe = 0.0
		_wipe_done = false
		return
	if _wipe_done:
		return
	wipe = minf(1.0, wipe + delta / WIPE_TIME)
	w.progress = wipe
	if wipe >= 1.0:
		_wipe_done = true
		wipe = 0.0
		w.progress = 0.0
		Shed.board_request({"a": "board_clear"})


func _input(event: InputEvent) -> void:
	if not _here() or event is InputEventMouseMotion:
		return
	if carrying != 0 and (event.is_action_pressed("board_move") or event.is_action_pressed("act")):
		drop_image()
	elif carrying != 0 and (event.is_action_pressed("tool_next") or event.is_action_pressed("board_bigger")):
		_scale_carried(1.15)
	elif carrying != 0 and (event.is_action_pressed("tool_prev") or event.is_action_pressed("board_smaller")):
		_scale_carried(1.0 / 1.15)
	elif carrying != 0 and (event.is_action_pressed("rotate_left") or event.is_action_pressed("rotate_right")):
		_turn_carried(1 if event.is_action_pressed("rotate_right") else -1)
	elif event.is_action_pressed("rotate_left") or event.is_action_pressed("rotate_right"):
		# Over a picture without holding it: turn it where it is.
		var over := BoardData.image_at(Shed.board, aim(_local_walker()))
		if over == 0:
			return
		_turn(over, 1 if event.is_action_pressed("rotate_right") else -1)
	elif event.is_action_pressed("board_move"):
		take_image()
	elif event.is_action_pressed("board_bigger") or event.is_action_pressed("board_smaller"):
		# Over a picture without holding it: size it where it is.
		var under := BoardData.image_at(Shed.board, aim(_local_walker()))
		if under != 0:
			_resize(under, 1.15 if event.is_action_pressed("board_bigger") else 1.0 / 1.15)
	elif event.is_action_pressed("board_image"):
		_pick_image.call_deferred()
	elif event.is_action_pressed("board_poster"):
		_name_poster.call_deferred()
	elif event.is_action_pressed("board_undo"):
		Shed.board_request({"a": "board_undo"})
	elif event.is_action_pressed("board_text"):
		_write_here.call_deferred()
	elif event.is_action_pressed("board_colour"):
		pen = (pen + 1) % BoardData.COLORS.size()   # B on a pad: the next colour
		eraser = false
	elif event.is_action_pressed("tool_next"):
		width = mini(width + 1, BoardData.WIDTHS.size() - 1)
	elif event.is_action_pressed("tool_prev"):
		width = maxi(width - 1, 0)
	elif event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_CTRL:
		pass   # Ctrl+Z undoes here, so Ctrl doesn't crouch
	elif event.is_action("act") or event.is_action("alt_act") or event.is_action("spray_colour") or event.is_action("spray_finish") \
			or event.is_action("board_wipe") or event.is_action("board_colour") or event.is_action("board_move") \
			or event.is_action("board_poster") or event.is_action("board_image") or event.is_action("rotate_left") \
			or event.is_action("rotate_right"):
		pass   # held, and read in _process; the tool in your hand stays out of it
	else:
		var picked := false
		for i in 8:
			if event.is_action_pressed("tool_%d" % (i + 1)):
				picked = true
				if i < BoardData.COLORS.size():
					pen = i
					eraser = false
				elif i == BoardData.COLORS.size():
					eraser = true
		if not picked:
			return
	get_viewport().set_input_as_handled()


## T at the board: type a line of text where the crosshair is. Enter puts it up and moves to
## the next line down, so lists are quick to write.
func _write_here() -> void:
	var p := aim(_local_walker())
	var dialog: Node = get_tree().get_first_node_in_group("label_dialog")
	if p.x < 0.0 or dialog == null:
		return
	var s: int = BoardData.TEXT_SIZES[width]
	dialog.open_board(self, Vector2(p.x, p.y - s * 0.6))
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Puts a line of text up at `at` in the pen's colour, and gives where the next line goes.
func write_text(text: String, at: Vector2) -> Vector2:
	var s: int = BoardData.TEXT_SIZES[width]
	Shed.board_request({"a": "board_text", "id": _new_id(), "c": pen, "s": s, "at": at, "text": text})
	return Vector2(at.x, minf(at.y + s * 1.15, BoardData.PX.y - s))


# ---------------------------------------------------------------------------- pictures and posters

## U at the board: pick a picture on your PC to put up where the crosshair is.
func _pick_image() -> void:
	var p := aim(_local_walker())
	if p.x < 0.0:
		return
	_image_at = p
	if _files == null:
		_files = FileDialog.new()
		_files.title = "Put a picture on the whiteboard"
		_files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_files.access = FileDialog.ACCESS_FILESYSTEM
		_files.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
		_files.use_native_dialog = true
		_files.file_selected.connect(func(path: String):
			_done_picking()
			add_image_file(path, _image_at))
		_files.canceled.connect(_done_picking)
		add_child(_files)
	picking = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_files.popup_centered_ratio(0.6)


func _done_picking() -> void:
	picking = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Puts the picture in the file at `path` (PNG, JPEG or WebP) on the board, centred on `at`:
## shrunk to at most BoardData.IMAGE_PX, packed small and sent to the crew. Gives its mark id.
func add_image_file(path: String, at: Vector2) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Shed.feedback.emit("Couldn't open that file.", false)
		return 0
	var big := f.get_length() > MAX_FILE_BYTES
	f.close()
	if big:
		Shed.feedback.emit("That file is too big. Pick a picture under 40 MB.", false)
		return 0
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		Shed.feedback.emit("That isn't a picture the board can show (PNG, JPEG or WebP).", false)
		return 0
	return add_image(img, at)


## Puts `img` on the board centred on `at` (board pixels). Gives its mark id, or 0.
func add_image(img: Image, at: Vector2) -> int:
	var data := Shed.pack_image(img)
	if data.is_empty():
		Shed.feedback.emit("That picture couldn't be made small enough to share.", false)
		return 0
	var aspect := float(img.get_width()) / maxf(1.0, img.get_height())
	var sz := Vector2(IMAGE_FIT.x, IMAGE_FIT.x / aspect)
	if sz.y > IMAGE_FIT.y:
		sz = Vector2(IMAGE_FIT.y * aspect, IMAGE_FIT.y)
	sz = sz.max(Vector2(BoardData.IMAGE_MIN, BoardData.IMAGE_MIN))
	var id := Shed.board_add_image(data, at - sz * 0.5, sz)
	if id != 0:
		Shed.feedback.emit("Picture up. Look at it and press M to move it, + or - to size it.", true)
	return id


## M at the board over a picture: take hold of it to move it (M or left mouse puts it down).
func take_image() -> bool:
	var p := aim(_local_walker())
	var id := BoardData.image_at(Shed.board, p)
	if id == 0:
		return false
	var m: Dictionary = Shed.board["marks"][BoardData.find(Shed.board, id)]
	carrying = id
	_grab = p - (m["at"] as Vector2)
	_carry_sent = {"at": m["at"], "sz": m["sz"], "rot": BoardData.rotation_of(m)}
	_carry_timer = 0.0
	return true


## Puts the picture you're moving down where it is.
func drop_image() -> void:
	if carrying == 0:
		return
	_send_move(true)
	carrying = 0


func _update_carry(p: Vector2, delta: float) -> void:
	var i := BoardData.find(Shed.board, carrying)
	if i < 0:
		carrying = 0   # rubbed out or undone meanwhile
		return
	if p.x < 0.0:
		drop_image()   # looked off the board or walked away
		return
	var sz: Vector2 = Shed.board["marks"][i]["sz"]
	_grab = _grab.clamp(Vector2.ZERO, sz)
	# With snapping off, holding a rotate key turns it freely.
	var spin := Input.get_axis("rotate_left", "rotate_right")
	_turn_held = _turn_held + delta if spin != 0.0 else 0.0
	if spin != 0.0 and not Settings.snap_placement and _turn_held > 0.2:
		_set_turn(BoardData.rotation_of(Shed.board["marks"][i]) + spin * TURN_RATE * delta)
	_move_here(p - _grab, sz)
	_carry_timer += delta
	if _carry_timer >= SEND_EVERY * 2.0:
		_send_move(false)


## Moves the picture you hold on your own board straight away; it goes to the crew in _send_move.
func _move_here(at: Vector2, sz: Vector2, rot = null) -> void:
	var raw := {"a": "board_move", "id": carrying, "at": at, "sz": sz}
	if rot != null:
		raw["rot"] = rot
	var op := BoardData.clean(raw, Shed.me(), "")
	if not op.is_empty() and BoardData.apply(Shed.board, op):
		Shed.board_changed.emit()


## Sends where the picture is to the crew, if it moved since last time.
func _send_move(_final: bool) -> void:
	_carry_timer = 0.0
	var i := BoardData.find(Shed.board, carrying)
	if i < 0:
		return
	var m: Dictionary = Shed.board["marks"][i]
	var rot := BoardData.rotation_of(m)
	if _carry_sent.get("at") == m["at"] and _carry_sent.get("sz") == m["sz"] and is_equal_approx(float(_carry_sent.get("rot", 0.0)), rot):
		return
	_carry_sent = {"at": m["at"], "sz": m["sz"], "rot": rot}
	Shed.board_request({"a": "board_move", "id": carrying, "at": m["at"], "sz": m["sz"], "rot": rot})


func _scale_carried(k: float) -> void:
	var i := BoardData.find(Shed.board, carrying)
	if i < 0:
		return
	var m: Dictionary = Shed.board["marks"][i]
	var old: Vector2 = m["sz"]
	var sz := _scaled(old, k)
	# Grown or shrunk about where you hold it.
	var grab := _grab * (sz / old)
	_move_here((m["at"] as Vector2) + _grab - grab, sz)
	_grab = grab


## A press of a rotate key while moving a picture (1 clockwise, -1 back): 15 degrees, onto the
## next multiple of 15, with snapping on; a nudge with it off.
func _turn_carried(dir: int) -> void:
	var i := BoardData.find(Shed.board, carrying)
	if i >= 0:
		_set_turn(turned(BoardData.rotation_of(Shed.board["marks"][i]), dir))


## `rot` turned one press of a rotate key `dir` (see _turn_carried).
static func turned(rot: float, dir: int) -> float:
	if Settings.snap_placement:
		# On to the next multiple of 15 that way (from 7 degrees: 15 one way, 0 the other).
		var steps := floorf(rot / TURN_STEP + 0.001) + 1.0 if dir > 0 else ceilf(rot / TURN_STEP - 0.001) - 1.0
		return wrapf(steps * TURN_STEP, 0.0, 360.0)
	return wrapf(rot + dir * TURN_NUDGE, 0.0, 360.0)


## Turns the picture you hold to `rot` degrees on your own board; it goes to the crew in _send_move.
func _set_turn(rot: float) -> void:
	var i := BoardData.find(Shed.board, carrying)
	if i < 0:
		return
	var m: Dictionary = Shed.board["marks"][i]
	_move_here(m["at"], m["sz"], rot)


## Turns picture `id` a press of a rotate key where it is.
func _turn(id: int, dir: int) -> void:
	var m: Dictionary = Shed.board["marks"][BoardData.find(Shed.board, id)]
	Shed.board_request({"a": "board_move", "id": id, "at": m["at"], "sz": m["sz"], "rot": turned(BoardData.rotation_of(m), dir)})


## Sizes picture `id` by `k` about its middle.
func _resize(id: int, k: float) -> void:
	var m: Dictionary = Shed.board["marks"][BoardData.find(Shed.board, id)]
	var old: Vector2 = m["sz"]
	var sz := _scaled(old, k)
	Shed.board_request({"a": "board_move", "id": id, "at": (m["at"] as Vector2) + (old - sz) * 0.5, "sz": sz})


## `sz` times `k`, keeping its shape, no smaller than BoardData.IMAGE_MIN and no bigger than the board.
static func _scaled(sz: Vector2, k: float) -> Vector2:
	var lo := BoardData.IMAGE_MIN / minf(sz.x, sz.y)
	var hi := minf(BoardData.PX.x / sz.x, BoardData.PX.y / sz.y)
	return sz * clampf(k, lo, maxf(lo, hi))


## K at the board: name what's on it, and it's saved as a poster to order from the parts computer.
func _name_poster() -> void:
	var dialog: Node = get_tree().get_first_node_in_group("label_dialog")
	if dialog == null:
		return
	if Shed.board.get("marks", []).is_empty():
		Shed.feedback.emit("The board is clean: draw something to make a poster of.", false)
		return
	dialog.open_named("MAKE A POSTER OF THE BOARD", "A name for the poster, e.g. Bay 3 build plan", "", 32,
		func(text: String): make_poster(text))
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Saves what's on the board now as a poster design called `poster_name` (see Shed.posters).
func make_poster(poster_name: String) -> void:
	Shed.request({"a": "board_poster", "name": poster_name})


func pen_text() -> String:
	if eraser:
		return "Eraser"
	return "%s %s pen" % [BoardData.COLOR_NAMES[pen], str(BoardData.WIDTH_NAMES[width]).to_lower()]


## The first key (or pad button) on `action`, for the hints.
static func _k(action: String, pad := false) -> String:
	var t := Settings.binding_text(action, pad)
	return t.get_slice(" / ", 0) if t != "" else "-"


## The side panel's lines while you're looking at the board.
func describe() -> Array:
	var marks: Array = Shed.board.get("marks", [])
	var lines := ["Whiteboard", "Holding: %s" % pen_text()]
	lines.append("Hold left mouse: draw  ·  hold right mouse: rub out")
	lines.append("%s: write a line of text  ·  %s: undo your last mark" % [_k("board_text"), _k("board_undo")])
	lines.append("Hold %s: wipe the whole board clean" % _k("board_wipe"))
	lines.append("%s: add a picture from your PC  ·  %s: make a poster of the board" % [_k("board_image"), _k("board_poster")])
	if carrying != 0:
		lines.append("Moving a picture: %s or left mouse puts it down, scroll or %s / %s sizes it" % [
			_k("board_move"), _k("board_bigger"), _k("board_smaller")])
		lines.append("%s / %s turns it (%s)" % [_k("rotate_left"), _k("rotate_right"),
			"15 degrees at a time" if Settings.snap_placement else "hold to turn it freely"])
	elif BoardData.image_at(Shed.board, aim(_local_walker())) != 0:
		lines.append("On a picture: %s moves it, %s / %s sizes it, %s / %s turns it" % [_k("board_move"), _k("board_bigger"),
			_k("board_smaller"), _k("rotate_left"), _k("rotate_right")])
	if marks.is_empty():
		lines.append("The board is clean.")
	else:
		lines.append("%d marks on it, the last by %s" % [marks.size(), str(marks[marks.size() - 1].get("by", "someone"))])
	return lines


## The pen picker over the tool bar while you're at the board, drawn by the HUD.
func draw_picker(hud: Control, font: Font, toolbar_y: float) -> void:
	var n := BoardData.COLORS.size() + 1
	var sw := 32.0
	var gap := 8.0
	var widths := BoardData.WIDTHS.size()
	var swatches := n * (sw + gap) + 24.0 + widths * (sw + gap) - gap
	var pad := Controls.device() >= 0 and Controls.active_device >= 0
	var hint := "RT: draw   LT: rub out   %s: colour   LB / RB: thickness   %s: undo   %s: move picture   %s: poster" % [
		_k("board_colour", true), _k("board_undo", true), _k("board_move", true), _k("board_poster", true)] if pad else \
		"1-6: colour   7: eraser   scroll: thickness   %s: text   %s: undo   hold %s: wipe   %s: picture   %s: poster" % [
		_k("board_text"), _k("board_undo"), _k("board_wipe"), _k("board_image"), _k("board_poster")]
	if carrying != 0:
		hint = ("D-pad up or A puts it down   LB / RB: size   %s: turn" % _k("rotate_right", true) if pad else \
			"%s or left mouse puts it down   scroll or %s / %s: size   %s / %s: turn" % [
			_k("board_move"), _k("board_bigger"), _k("board_smaller"), _k("rotate_left"), _k("rotate_right")])
	if wipe > 0.0:
		hint = "Wiping the whole board... keep holding X"
	var total := maxf(swatches, font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var x0 := hud.size.x * 0.5 - total * 0.5
	var y := toolbar_y - 112.0
	hud.draw_rect(Rect2(x0 - 14, y - 32, total + 28, 96), Color(0.05, 0.06, 0.08, 0.7))
	hud.draw_string(font, Vector2(x0, y - 12), "WHITEBOARD  ·  %s" % pen_text().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	for i in n:
		var r := Rect2(x0 + i * (sw + gap), y, sw, sw)
		var picked := (i == pen and not eraser) or (i == n - 1 and eraser)
		if picked:
			r = r.grow(3.0)
		if i < n - 1:
			hud.draw_rect(r, BoardData.COLORS[i])
		else:
			hud.draw_rect(r, Color(0.1, 0.3, 0.7))
			hud.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.6), Vector2(r.size.x, r.size.y * 0.4)), Color(0.15, 0.15, 0.17))
		if picked:
			hud.draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
		hud.draw_string(font, r.position + Vector2(3, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	var ink: Color = BoardData.COLORS[pen]
	var wx := x0 + n * (sw + gap) + 24.0
	for i in widths:
		var r := Rect2(wx + i * (sw + gap), y, sw, sw)
		hud.draw_rect(r, Color(0.95, 0.96, 0.965) if i != width else Color(1, 1, 1))
		hud.draw_circle(r.get_center(), maxf(1.5, float(BoardData.WIDTHS[i]) * 0.5), ink)
		if i == width:
			hud.draw_rect(r.grow(2.0), UITheme.ACCENT, false, 2.0)
	hud.draw_string(font, Vector2(x0, y + 56), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
