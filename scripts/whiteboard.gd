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


func _line(w: float, color: Color) -> Line2D:
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
			if node != null and (node is Label) != m.has("text"):
				node.queue_free()
				node = null
			node = _show_mark(m, node)
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


func _sig(m: Dictionary) -> String:
	if m.has("text"):
		return "%s|%d|%d|%s" % [m["text"], int(m["c"]), int(m["s"]), str(m["at"])]
	var pts: PackedVector2Array = m["pts"]
	return "%d|%s|%s" % [pts.size(), str(pts[0]), str(pts[pts.size() - 1])]


func _show_mark(m: Dictionary, node: CanvasItem) -> CanvasItem:
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
func _drawable(pts: PackedVector2Array) -> PackedVector2Array:
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
	if event.is_action_pressed("board_undo"):
		Shed.board_request({"a": "board_undo"})
	elif event.is_action_pressed("board_text"):
		_write_here.call_deferred()
	elif event.is_action_pressed("spray_finish"):
		pen = (pen + 1) % BoardData.COLORS.size()   # B on a pad: the next colour
		eraser = false
	elif event.is_action_pressed("tool_next"):
		width = mini(width + 1, BoardData.WIDTHS.size() - 1)
	elif event.is_action_pressed("tool_prev"):
		width = maxi(width - 1, 0)
	elif event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_CTRL:
		pass   # Ctrl+Z undoes here, so Ctrl doesn't crouch
	elif event.is_action("act") or event.is_action("alt_act") or event.is_action("spray_colour") or event.is_action("spray_finish") \
			or event.is_action("board_wipe"):
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


func pen_text() -> String:
	if eraser:
		return "Eraser"
	return "%s %s pen" % [BoardData.COLOR_NAMES[pen], str(BoardData.WIDTH_NAMES[width]).to_lower()]


## The side panel's lines while you're looking at the board.
func describe() -> Array:
	var marks: Array = Shed.board.get("marks", [])
	var lines := ["Whiteboard", "Holding: %s" % pen_text()]
	lines.append("Hold left mouse: draw  ·  hold right mouse: rub out")
	lines.append("T: write a line of text  ·  Z: undo your last mark")
	lines.append("Hold X: wipe the whole board clean")
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
	var hint := "RT: draw   LT: rub out   B: colour   LB / RB: thickness   D-pad left: undo" if pad else \
		"1-6: colour   7: eraser   scroll: thickness   T: text   Z: undo   hold X: wipe"
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
