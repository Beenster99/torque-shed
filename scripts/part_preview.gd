class_name PartPreview
extends SubViewportContainer
## A small turntable for the parts computer: the part picked in the list, drawn in 3D in a
## little world of its own and turning slowly so you can see it all round. Drag it with the
## mouse to turn it yourself. Shows a catalogue part (BikeModel.part_display) or a loose item
## from the shed (BikeModel.item_display, for the Sell aisle).

const SPIN := 0.6           # radians a second it turns on its own
const DRAG_TURN := 0.01     # radians per pixel dragged
const FOV := 32.0
const LIFT := 0.32          # how far the camera looks down: up this much for each metre back
const FILL := 0.82          # how much of the picture the part fills, at most, in the studio

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
## What's on the turntable: "part:<id>", "item:<id>" or "".
var showing := ""
## Whether it's set up as a photo studio (see use_studio), and the soft shadow it sits on there.
var studio := false
var shadow: MeshInstance3D
var _env: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _dragging := false
var _size := Vector3.ONE      # the size of what's on the turntable
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
	_env = e
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	_key = key
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.3
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	_fill = fill
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


## Sets it up as a photo studio, for the parts computer: a soft grey backdrop fading from light
## overhead to mid grey at the floor, a shadow under the part, and key, fill and rim lights, so a
## black tyre or carbon bars stand out as well as chrome does (and chrome has something to show).
func use_studio() -> void:
	if studio:
		return
	studio = true
	viewport.transparent_bg = false
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.86, 0.87, 0.89)
	sky_mat.sky_horizon_color = Color(0.58, 0.6, 0.63)
	sky_mat.sky_curve = 0.25
	sky_mat.ground_horizon_color = Color(0.58, 0.6, 0.63)
	sky_mat.ground_bottom_color = Color(0.46, 0.47, 0.5)
	sky_mat.ground_curve = 0.12
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	# The light all round is a plain soft grey, but chrome and gloss reflect the backdrop.
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.8, 0.82, 0.86)
	_env.ambient_light_energy = 0.55
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_key.light_energy = 1.5
	_key.light_color = Color(1.0, 0.97, 0.92)
	_key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_fill.light_energy = 0.55
	_fill.light_color = Color(0.85, 0.9, 1.0)
	_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# From behind and above, so a dark part's outline catches the light against the backdrop.
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(170.0), 0.0)
	rim.light_energy = 1.1
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	viewport.add_child(rim)
	# A soft round shadow on the floor under the part (it doesn't turn, so it's round).
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.5))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	grad.add_point(0.55, Color(0.0, 0.0, 0.0, 0.22))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.visible = false
	viewport.add_child(shadow)


## Puts a catalogue part on the turntable (or nothing for "", or anything that isn't a part).
func show_part(part_id: String, cond := {}) -> void:
	if part_id == "" or PartsDB.get_part(part_id).is_empty():
		clear()
		return
	# `cond` is how it's drawn: the colours picked for it at the parts computer (see PartColours).
	var key := "part:" + part_id + ("" if cond.is_empty() else ":%d" % hash(cond))
	if key == showing:
		return
	_put(BikeModel.part_display(part_id, cond), key)


## Puts a loose item from the shed on the turntable, as it is now (boxed, rusty, with its tyre...).
func show_item(item_id: int) -> void:
	if not Shed.items.has(item_id):
		clear()
		return
	_put(BikeModel.item_display(item_id), "item:%d" % item_id)


## Puts a whole bike on the turntable: `parts` built up in `paint`, `cond` its parts' colours
## (BikeBuild's condition), nobody on it. `key` says which bike, so it's only rebuilt for another.
func show_bike(key: String, parts: Dictionary, paint: Color, cond := {}) -> void:
	if key == showing:
		return
	var build := BikeBuild.new(PartsDB.sanitize_build(parts.duplicate()), cond)
	var holder := Node3D.new()
	var model := BikeModel.new()
	model.baked = true
	# The bike it replaces: on the same frame, the new one re-forms from it (see BikeReform).
	for c in pivot.get_children():
		if c.get_child_count() > 0 and c.get_child(0) is BikeModel:
			model.reform_from = (c.get_child(0) as BikeModel).rig
	model.position.y = build.rear_radius
	holder.add_child(model)
	model.build_from(build, paint, {}, null, false)
	# Its middle over the turntable: the wheels sit either side of the model's origin.
	holder.set_meta("size", Vector3(0.8, 1.15, build.wheelbase + build.rear_radius * 2.0))
	_put(holder, "bike:" + key)
	holder.position = Vector3(0.0, -0.55, 0.0)
	if shadow:
		shadow.position.y = -0.552


func clear() -> void:
	showing = ""
	for c in pivot.get_children():
		c.queue_free()
	if shadow:
		shadow.visible = false
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
	if shadow:
		# On the floor under it, as wide as it is whichever way it's turned.
		var across := maxf(0.08, Vector2(size.x, size.z).length() * 1.25)
		shadow.position = Vector3(0.0, -size.y * 0.5 - 0.002, 0.0)
		shadow.scale = Vector3(across, 1.0, across)
		shadow.visible = true
	_size = size
	if studio:
		_frame()
		return
	var radius := maxf(0.05, Vector3(size.x, size.y, size.z).length() * 0.5)
	var aspect := float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	var half := deg_to_rad(FOV * 0.5)
	var fit := maxf(radius / tan(half), radius / (tan(half) * aspect))
	var dist := fit * 0.95
	camera.position = Vector3(0.0, dist * 0.32, dist)
	camera.look_at(Vector3.ZERO, Vector3.UP)


## In the studio, the camera as close as it can be with the part filling FILL of the picture
## whichever way it's turned: it's worked out for the part's box at a turn of the turntable
## every 22.5 degrees, for the picture's shape now (and again whenever that changes).
func _frame() -> void:
	var aspect := size.x / size.y if size.x > 1.0 and size.y > 1.0 else float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	var tan_half := tan(deg_to_rad(FOV * 0.5))
	var back := Vector3(0.0, LIFT, 1.0)
	var k := back.normalized()
	var cam := Transform3D(Basis(), back).looking_at(Vector3.ZERO, Vector3.UP)
	var right := cam.basis.x
	var up := cam.basis.y
	var need := 0.05
	for turn in 16:
		var b := Basis(Vector3.UP, TAU * turn / 16.0)
		for i in 8:
			var p := b * Vector3(_size.x * ((i & 1) - 0.5), _size.y * (((i >> 1) & 1) - 0.5), _size.z * (((i >> 2) & 1) - 0.5))
			var reach := maxf(absf(p.dot(right)) / (tan_half * aspect * FILL), absf(p.dot(up)) / (tan_half * FILL))
			need = maxf(need, p.dot(k) + reach)
	camera.position = k * need
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and studio and showing != "":
		_frame()


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
