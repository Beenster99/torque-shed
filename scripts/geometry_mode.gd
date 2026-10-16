class_name GeometryMode
extends Control
## Geometry mode: fit a bike's parts by hand. The mouse is freed and the camera orbits the bike;
## click any part of it to select it, then drag the gizmo's arrows (move), rings (rotate) or boxes
## (stretch along one axis, or the middle box to size it all over), like Blender or Unreal.
## W / E / R switch handles, Ctrl snaps (1 cm, 5 degrees, 5%), Z undoes, Backspace resets the
## part. Right-drag orbits, middle-drag pans and the wheel zooms.
##
## Edits belong to this one bike (Shed.bikes[id].geo, see GeoGizmo) and are a draft until saved:
## "Save to this bike" sends them to the host, "Save + blueprint" also keeps the bike as a named
## blueprint to build again. Leaving with unsaved changes asks to save or discard them.

signal closed

const ORBIT_SPEED := 0.008
const MIN_DIST := 0.6
const MAX_DIST := 6.0

var active := false
var bike_id := 0
var draft := {}                 # slot -> offset, as being edited
var saved := {}                 # the bike's fit when opened or last saved
var selected := ""
var workshop: Workshop
var camera: Camera3D
var gizmo: GeoGizmo
var snap_always := false
var _back_camera: Camera3D
var _model: BikeModel
var _undo: Array = []           # drafts before each change
var _drag := {}                 # the handle being dragged and where it started
var _orbiting := false
var _panning := false
var _yaw := 0.0
var _pitch := -0.35
var _dist := 2.6
var _focus := Vector3.ZERO
var _title: Label
var _part_label: Label
var _readout: Label
var _status: Label
var _mode_btns: Array = []
var _snap_box: CheckBox
var _name_edit: LineEdit
var _confirm: PanelContainer
var _confirm_text: Label
var _panel: PanelContainer
## The list of the bike's parts down the left, another way to pick one: slot -> its button.
var _list_panel: PanelContainer
var _list: VBoxContainer
var part_buttons := {}
var _list_sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -420.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	col.add_child(UITheme.title("GEOMETRY MODE", 24))
	_title = UITheme.label("", 17, Color.WHITE)
	col.add_child(_title)
	col.add_child(UITheme.label("Click a part of the bike (or pick it in the list on the left) to select it, then drag the handles. W move, E rotate, R scale "
		+ "(the middle box sizes it all over). Hold Ctrl to snap, Z undo, Backspace resets the part. "
		+ "Right-drag to orbit, middle-drag to pan, wheel to zoom. Only this bike changes.", 14, Color(1, 1, 1, 0.6)))
	_part_label = UITheme.label("No part selected", 17, UITheme.ACCENT)
	col.add_child(_part_label)
	var modes := HBoxContainer.new()
	for m in 3:
		var b := _button("%s (%s)" % [GeoGizmo.MODE_NAMES[m], ["W", "E", "R"][m]], set_mode.bind(m))
		b.toggle_mode = true
		modes.add_child(b)
		_mode_btns.append(b)
	col.add_child(modes)
	_snap_box = CheckBox.new()
	_snap_box.text = "Always snap (or hold Ctrl)"
	_snap_box.focus_mode = Control.FOCUS_NONE
	_snap_box.toggled.connect(func(v): snap_always = v)
	col.add_child(_snap_box)
	_readout = UITheme.label("", 15, Color(0.85, 0.95, 1.0))
	col.add_child(_readout)
	var edits := HBoxContainer.new()
	edits.add_child(_button("Undo (Z)", undo))
	edits.add_child(_button("Reset part", reset_part))
	edits.add_child(_button("Reset all", reset_all))
	col.add_child(edits)
	col.add_child(_button("Save to this bike", save))
	var bp_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Blueprint name"
	_name_edit.max_length = 28
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t): save_blueprint(_name_edit.text))
	bp_row.add_child(_name_edit)
	bp_row.add_child(_button("Save + blueprint", func(): save_blueprint(_name_edit.text)))
	col.add_child(bp_row)
	col.add_child(_button("Exit (F2 / Esc)", request_exit))
	_status = UITheme.label("", 14, Color(1, 0.8, 0.55))
	col.add_child(_status)
	_confirm = PanelContainer.new()
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.offset_left = -260.0
	_confirm.offset_right = 260.0
	_confirm.offset_top = -80.0
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)
	var cc := VBoxContainer.new()
	cc.add_theme_constant_override("separation", 10)
	_confirm.add_child(cc)
	_confirm_text = UITheme.label("", 17, Color.WHITE)
	cc.add_child(_confirm_text)
	var crow := HBoxContainer.new()
	crow.add_child(_button("Save and exit", func(): save(); close()))
	crow.add_child(_button("Discard changes", discard_and_close))
	crow.add_child(_button("Keep editing", func(): _confirm.visible = false))
	cc.add_child(crow)
	# The bike's parts as a list on the left: click one to select it, same as clicking it on the bike.
	_list_panel = PanelContainer.new()
	_list_panel.offset_left = 16.0
	_list_panel.offset_right = 336.0
	_list_panel.offset_top = 16.0
	_list_panel.anchor_bottom = 1.0
	_list_panel.offset_bottom = -16.0
	_list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_list_panel)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 6)
	_list_panel.add_child(lcol)
	lcol.add_child(UITheme.title("PARTS", 20))
	var lhint := UITheme.label("Click one to select it.", 14, Color(1, 1, 1, 0.6))
	lcol.add_child(lhint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lcol.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	Shed.feedback.connect(func(text, _ok): if active: _status.text = text)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------------------- opening and closing

## Starts editing a parked bike. `back` is the camera to go back to afterwards.
func open(id: int, ws: Workshop, back: Camera3D) -> bool:
	if not Shed.bikes.has(id) or Shed.bikes[id]["rider"] != 0 or ws == null or not ws.bike_views.has(id):
		return false
	workshop = ws
	bike_id = id
	ws.editing_bike = id
	_back_camera = back
	saved = GeoGizmo.sanitize(Shed.geometry_of(id)).duplicate(true)
	draft = saved.duplicate(true)
	_undo.clear()
	_drag = {}
	selected = ""
	_model = null
	if camera == null or not is_instance_valid(camera):
		camera = Camera3D.new()
		camera.name = "GeometryCamera"
		camera.fov = 60.0
		camera.near = 0.03
		ws.add_child(camera)
	if gizmo == null or not is_instance_valid(gizmo):
		gizmo = GeoGizmo.new()
		ws.add_child(gizmo)
	gizmo.visible = false
	var view: Node3D = ws.bike_views[id]
	_focus = view.global_position + Vector3.UP * 0.55
	var from := back.global_position if back else _focus + Vector3(1.5, 0.6, 1.5)
	var v := from - _focus
	_dist = clampf(v.length(), 1.4, 3.2)
	_yaw = atan2(v.x, v.z)
	_pitch = clampf(-asin(clampf(v.y / maxf(v.length(), 0.01), -1.0, 1.0)), -1.3, 0.4)
	_update_camera()
	camera.current = true
	active = true
	visible = true
	_confirm.visible = false
	_status.text = ""
	_name_edit.text = str(Shed.bikes[id]["name"])
	_title.text = str(Shed.bikes[id]["name"])
	set_mode(GeoGizmo.Mode.MOVE)
	_sync_model()
	_list_sig = ""
	_refresh_list()
	return true


## Leaves, asking first if there are changes not saved.
func request_exit() -> void:
	if is_dirty():
		_confirm_text.text = "You've changed %s and not saved it. Save the changes to this bike?" % _title.text
		_confirm.visible = true
		return
	close()


## Puts the bike back as it was saved and leaves.
func discard_and_close() -> void:
	draft = saved.duplicate(true)
	if _model and is_instance_valid(_model):
		_model.apply_geometry(GeoGizmo.sanitize(Shed.geometry_of(bike_id)))
		_model.build_pickers({"bike": bike_id})
	close()


func close() -> void:
	if not active:
		return
	active = false
	visible = false
	_confirm.visible = false
	_drag = {}
	if _model and is_instance_valid(_model):
		_model.highlight("")
	if gizmo:
		gizmo.visible = false
	if _back_camera and is_instance_valid(_back_camera):
		_back_camera.current = true
	_model = null
	if workshop and is_instance_valid(workshop):
		workshop.editing_bike = 0
	closed.emit()


func is_dirty() -> bool:
	return GeoGizmo.sanitize(draft) != GeoGizmo.sanitize(saved)


# ---------------------------------------------------------------------------- editing

func set_mode(m: int) -> void:
	if gizmo:
		gizmo.set_mode(m)
	for i in _mode_btns.size():
		(_mode_btns[i] as Button).set_pressed_no_signal(i == m)


func select(slot: String) -> void:
	selected = slot
	_drag = {}
	if _model and is_instance_valid(_model):
		_model.highlight(slot)
	for s in part_buttons:
		var b: Button = part_buttons[s]
		if is_instance_valid(b):
			b.set_pressed_no_signal(s == slot)
			if s == slot and b.is_inside_tree():
				var scroll := _list.get_parent() as ScrollContainer
				if scroll:
					scroll.ensure_control_visible(b)


# ---------------------------------------------------------------------------- the parts list

## The slots that can be picked on this bike: every part fitted and drawn, in the catalogue's
## slot order (the same ones a click on the bike can pick).
func pickable_slots() -> Array:
	var out := []
	if _model == null or not is_instance_valid(_model):
		return out
	for slot in PartsDB.SLOTS:
		if _model.is_fitted(slot) and not (_model._slot_meshes.get(slot, []) as Array).is_empty() and Shed.item_on(bike_id, slot) != 0:
			out.append(slot)
	return out


## "Fork: Showa USD forks" for a slot's row, with a mark if it's been moved.
func row_text(slot: String) -> String:
	var item := Shed.item_on(bike_id, slot)
	var part := PartsDB.part_name(str(Shed.items[item]["part"])) if item != 0 and Shed.items.has(item) else "(empty)"
	return "%s%s: %s" % ["* " if draft.has(slot) else "", PartsDB.slot_name(slot), part]


## Rebuilds the list when the parts on the bike (or which ones are moved) change.
func _refresh_list() -> void:
	var slots := pickable_slots()
	var sig := ",".join(slots.map(func(s): return row_text(str(s))))
	if sig == _list_sig:
		return
	_list_sig = sig
	for c in _list.get_children():
		c.queue_free()
	part_buttons.clear()
	for slot in slots:
		var b := Button.new()
		b.text = row_text(slot)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = b.text
		b.button_pressed = slot == selected
		b.pressed.connect(select.bind(slot))
		_list.add_child(b)
		part_buttons[slot] = b
	if slots.is_empty():
		_list.add_child(UITheme.label("No parts on this bike.", 14, Color(1, 1, 1, 0.5)))


## Changes one part's offset as one undoable step.
func set_part_offset(slot: String, off: Dictionary) -> void:
	if slot == "":
		return
	_undo.append(draft.duplicate(true))
	_set_draft(slot, off)
	_refit()


func undo() -> void:
	if _undo.is_empty():
		return
	draft = _undo.pop_back()
	_drag = {}
	_refit()


func reset_part() -> void:
	if selected != "" and draft.has(selected):
		set_part_offset(selected, GeoGizmo.identity())


func reset_all() -> void:
	if draft.is_empty():
		return
	_undo.append(draft.duplicate(true))
	draft = {}
	_refit()


## Sends the draft to the host for this bike.
func save() -> void:
	draft = GeoGizmo.sanitize(draft)
	Shed.request({"a": "geo_save", "bike": bike_id, "geo": draft.duplicate(true)})
	saved = draft.duplicate(true)


## Saves to this bike and keeps it as a blueprint called `bp_name`.
func save_blueprint(bp_name: String) -> void:
	if bp_name.strip_edges() == "":
		_status.text = "Type a name for the blueprint first."
		return
	draft = GeoGizmo.sanitize(draft)
	Shed.request({"a": "geo_blueprint", "bike": bike_id, "geo": draft.duplicate(true), "name": bp_name.strip_edges()})
	saved = draft.duplicate(true)


func _set_draft(slot: String, off: Dictionary) -> void:
	if GeoGizmo.is_identity(off):
		draft.erase(slot)
	else:
		draft[slot] = off.duplicate(true)


## Shows the draft on the bike and refits its click targets.
func _refit() -> void:
	if _model and is_instance_valid(_model):
		_model.apply_geometry(draft.duplicate(true))
		_model.build_pickers({"bike": bike_id})


func _snapping() -> bool:
	return snap_always or Input.is_action_pressed("geo_snap")


# ---------------------------------------------------------------------------- frame by frame

func _process(_delta: float) -> void:
	if not active:
		return
	if not Shed.bikes.has(bike_id) or Shed.bikes[bike_id]["rider"] != 0 or workshop == null or not workshop.bike_views.has(bike_id):
		Shed.feedback.emit("That bike has gone, so geometry mode closed.", false)
		close()
		return
	_sync_model()
	_refresh_list()
	_update_camera()
	var show_gizmo := selected != "" and _model != null and _model.is_fitted(selected)
	gizmo.visible = show_gizmo
	if show_gizmo:
		var mx := _model.global_transform
		var part := _model.geo_xform(selected)
		gizmo.place(Transform3D(mx.basis.orthonormalized(), mx * part.origin), part.basis, camera)
		if _drag.is_empty() and not _confirm.visible:
			gizmo.set_hover(gizmo.pick(camera, get_viewport().get_mouse_position()))
	_update_readout()


## The workshop redraws a bike when anything about it changes: keep the draft on the new one.
func _sync_model() -> void:
	var m := workshop.bike_model(bike_id)
	if m != _model:
		_model = m
		_refit()
		_model.highlight(selected)


func _update_camera() -> void:
	if camera == null:
		return
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.global_position = _focus + dir * _dist
	camera.look_at(_focus, Vector3.UP)


func _update_readout() -> void:
	if selected == "":
		_part_label.text = "No part selected: click one"
		_readout.text = "%d part%s moved on this bike%s" % [draft.size(), "" if draft.size() == 1 else "s", "  (not saved)" if is_dirty() else ""]
		return
	var item := Shed.item_on(bike_id, selected)
	_part_label.text = "%s: %s" % [PartsDB.slot_name(selected), PartsDB.part_name(str(Shed.items[item]["part"])) if item != 0 else "(empty)"]
	var o := GeoGizmo.offset_of(draft, selected)
	var p: Vector3 = o["p"] * 100.0
	var r: Vector3 = o["r"]
	var s: Vector3 = o["s"] * 100.0
	_readout.text = "Move    X %+6.1f  Y %+6.1f  Z %+6.1f cm\nRotate  X %+6.1f  Y %+6.1f  Z %+6.1f deg\nScale   X %5.0f  Y %5.0f  Z %5.0f %%%s" % [
		p.x, p.y, p.z, r.x, r.y, r.z, s.x, s.y, s.z, "\n(not saved)" if is_dirty() else ""]


# ---------------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("menu") or event.is_action_pressed("geometry_mode"):
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			_confirm.visible = false
		else:
			request_exit()
		return
	if _confirm.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		get_viewport().set_input_as_handled()
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press(mb.position)
				else:
					_release()
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist * 0.9, MIN_DIST, MAX_DIST)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist * 1.1, MIN_DIST, MAX_DIST)
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _drag.is_empty():
			_drag_to(mm.position)
		elif _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch + mm.relative.y * ORBIT_SPEED, -1.4, 0.6)
		elif _panning and camera:
			var b := camera.global_basis
			_focus += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0015
		return
	if event.is_action_pressed("geo_move"):
		set_mode(GeoGizmo.Mode.MOVE)
	elif event.is_action_pressed("geo_rotate"):
		set_mode(GeoGizmo.Mode.ROTATE)
	elif event.is_action_pressed("geo_scale"):
		set_mode(GeoGizmo.Mode.SCALE)
	elif event.is_action_pressed("geo_undo"):
		undo()
	elif event.is_action_pressed("geo_reset"):
		reset_part()
	else:
		return
	get_viewport().set_input_as_handled()


func _press(mouse: Vector2) -> void:
	if gizmo.visible:
		var h := gizmo.pick(camera, mouse)
		if h >= 0:
			_start_drag(h, mouse)
			return
	select(_pick_part(mouse))


func _release() -> void:
	if _drag.is_empty():
		return
	var before: Dictionary = _drag["before"]
	_drag = {}
	if GeoGizmo.sanitize(before) != GeoGizmo.sanitize(draft):
		_undo.append(before)
	_refit()


## The part of this bike under the mouse, or "".
func _pick_part(mouse: Vector2) -> String:
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 30.0
	var space := camera.get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(from, to, BikeModel.PICK_LAYER)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return ""
		var c: Object = hit["collider"]
		if c.has_meta("bike") and int(c.get_meta("bike")) == bike_id and c.has_meta("slot"):
			return str(c.get_meta("slot"))
		skip.append((c as CollisionObject3D).get_rid())
	return ""


func _start_drag(h: int, mouse: Vector2) -> void:
	var center := gizmo.global_position
	_drag = {"h": h, "mode": gizmo.mode, "mouse": mouse, "center": center, "before": draft.duplicate(true),
		"start": GeoGizmo.offset_of(draft, selected)}
	var ro := camera.project_ray_origin(mouse)
	var rd := camera.project_ray_normal(mouse)
	match gizmo.mode:
		GeoGizmo.Mode.MOVE:
			_drag["dir"] = gizmo.axis_dir(h)
			_drag["t0"] = GeoGizmo.line_param(center, _drag["dir"], ro, rd)
		GeoGizmo.Mode.ROTATE:
			var axis := gizmo.axis_dir(h)
			_drag["dir"] = axis
			var hit = GeoGizmo.plane_point(center, axis, ro, rd)
			# Seen edge on, the ring turns with the mouse going sideways instead.
			if hit is Vector3 and absf(rd.normalized().dot(axis)) > 0.15:
				_drag["v0"] = (hit as Vector3) - center
		GeoGizmo.Mode.SCALE:
			if h != GeoGizmo.UNIFORM:
				var sdir := (_model.global_basis.orthonormalized() * GeoGizmo.rotation_of(_drag["start"])) * GeoGizmo.unit(h)
				_drag["dir"] = sdir.normalized()
				_drag["t0"] = GeoGizmo.line_param(center, _drag["dir"], ro, rd)


func _drag_to(mouse: Vector2) -> void:
	if _drag.is_empty():
		return
	var ro := camera.project_ray_origin(mouse)
	var rd := camera.project_ray_normal(mouse)
	var h: int = _drag["h"]
	var start: Dictionary = _drag["start"]
	var center: Vector3 = _drag["center"]
	var off := start
	match int(_drag["mode"]):
		GeoGizmo.Mode.MOVE:
			var t := GeoGizmo.line_param(center, _drag["dir"], ro, rd)
			off = GeoGizmo.moved(start, h, t - float(_drag["t0"]), _snapping())
		GeoGizmo.Mode.ROTATE:
			var deg := (mouse.x - (_drag["mouse"] as Vector2).x) * 0.5
			if _drag.has("v0"):
				var hit = GeoGizmo.plane_point(center, _drag["dir"], ro, rd)
				if hit is Vector3:
					deg = GeoGizmo.angle_about(_drag["v0"], (hit as Vector3) - center, _drag["dir"])
			off = GeoGizmo.rotated(start, h, deg, _snapping())
		GeoGizmo.Mode.SCALE:
			var factor := 1.0
			if h == GeoGizmo.UNIFORM:
				var d := mouse - (_drag["mouse"] as Vector2)
				factor = maxf(0.05, 1.0 + (d.x - d.y) / 200.0)
			else:
				var t0 := float(_drag["t0"])
				var t := GeoGizmo.line_param(center, _drag["dir"], ro, rd)
				factor = maxf(0.05, t / t0) if absf(t0) > 0.001 else 1.0
			off = GeoGizmo.scaled(start, h, factor, _snapping())
	_set_draft(selected, off)
	if _model and is_instance_valid(_model):
		_model.apply_geometry(draft.duplicate(true))
