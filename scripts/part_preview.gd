class_name PartPreview
extends SubViewportContainer
## A small turntable for the parts computer: the part picked in the list, drawn in 3D in a
## little world of its own and turning slowly so you can see it all round. Drag it with the
## mouse to turn it yourself. Shows a catalogue part (BikeModel.part_display) or a loose item
## from the shed (BikeModel.item_display, for the Sell aisle).

const SPIN := 0.6           # radians a second it turns on its own
const DRAG_TURN := 0.01     # radians per pixel dragged
const FOV := 32.0

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
## What's on the turntable: "part:<id>", "item:<id>" or "".
var showing := ""
var _dragging := false
var _hold := 0.0            # after a drag it waits a moment before turning on its own again


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 180)
	tooltip_text = "Drag to turn it"
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.size = Vector2i(420, 200)
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.3
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(-140.0), 0.0)
	fill.light_energy = 0.5
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.01
	camera.far = 50.0
	viewport.add_child(camera)
	pivot = Node3D.new()
	pivot.name = "Turntable"
	viewport.add_child(pivot)


## Puts a catalogue part on the turntable (or nothing for "", or anything that isn't a part).
func show_part(part_id: String) -> void:
	if part_id == "" or PartsDB.get_part(part_id).is_empty():
		clear()
		return
	var key := "part:" + part_id
	if key == showing:
		return
	_put(BikeModel.part_display(part_id, {}), key)


## Puts a loose item from the shed on the turntable, as it is now (boxed, rusty, with its tyre...).
func show_item(item_id: int) -> void:
	if not Shed.items.has(item_id):
		clear()
		return
	_put(BikeModel.item_display(item_id), "item:%d" % item_id)


func clear() -> void:
	showing = ""
	for c in pivot.get_children():
		c.queue_free()
	visible = false


func _put(node: Node3D, key: String) -> void:
	for c in pivot.get_children():
		c.queue_free()
	showing = key
	visible = true
	var size: Vector3 = node.get_meta("size", Vector3.ONE * 0.4)
	# Sat on the turntable with its middle over the centre, and the camera far enough back
	# that the whole of it fits whichever way it's turned.
	node.position = Vector3(0.0, -size.y * 0.5, 0.0)
	pivot.add_child(node)
	pivot.rotation = Vector3(0.0, -0.6, 0.0)
	var radius := maxf(0.05, Vector3(size.x, size.y, size.z).length() * 0.5)
	var aspect := float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	var half := deg_to_rad(FOV * 0.5)
	var fit := maxf(radius / tan(half), radius / (tan(half) * aspect))
	var dist := fit * 0.95
	camera.position = Vector3(0.0, dist * 0.32, dist)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or showing == "":
		return
	_hold = maxf(0.0, _hold - delta)
	if not _dragging and _hold <= 0.0:
		pivot.rotation.y += SPIN * delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_hold = 1.5
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pivot.rotation.y += (event as InputEventMouseMotion).relative.x * DRAG_TURN
		pivot.rotation.x = clampf(pivot.rotation.x + (event as InputEventMouseMotion).relative.y * DRAG_TURN * 0.5, -0.8, 0.8)
		accept_event()
