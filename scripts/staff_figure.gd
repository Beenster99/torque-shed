class_name StaffFigure
extends Node3D
## One member of staff as drawn (see StaffView): the same simple low-poly person as the
## customers (CustomerView), dressed in their look ({top, legs, skin, hair, tall, hat, tie,
## bald}), with arms and legs on pivots so they can walk, push a bike, carry a box or tray, bend
## to the bike with a spanner, type at the parts computer, spray, stir paint, wash, talk and stand
## there thinking. Whatever they last said floats over their head for a few seconds.
##
## Kept cheap: every figure shares the same few primitive meshes, materials are cached by colour,
## and nothing is allocated per frame (poses are a handful of floats eased towards a target).

## How quickly a pose changes to the next (per second).
const EASE := 9.0
const PELVIS_Y := 0.85

static var _meshes := {}       # "capsule", "sphere", "box", "cylinder" -> the shared mesh
static var _mats := {}         # Color -> its shared material

var worker_id := 0
var body: StaticBody3D
## Where a carried box, part or tray sits, in front of the chest.
var carry: Node3D
## The right hand, holding a tool: kept facing the way they face, whatever the arm does.
var hand: Node3D
var _pelvis: Node3D
var _spine: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _label: Label3D
var _name := ""
var _said := ""
var _hint := false
var _t := 0.0
var _phase := 0.0
# The pose now: how low they are, lean, twist, each leg and arm (rad, + is forwards), head nod.
var _drop := 0.0
var _lean := 0.0
var _twist := 0.0
var _leg := Vector2.ZERO
var _arm := Vector2.ZERO
var _nod := 0.0


## Builds the figure for worker `w` (see Staff).
func build(w: Dictionary) -> void:
	worker_id = int(w["id"])
	_name = "%s (%s)" % [str(w["name"]), Staff.role_name(str(w["role"]))]
	name = "Staff%d" % worker_id
	var look: Dictionary = w.get("look", {})
	var top: Color = look.get("top", Color(0.2, 0.3, 0.6))
	var legs: Color = look.get("legs", Color(0.15, 0.15, 0.2))
	var skin: Color = look.get("skin", Color(0.85, 0.66, 0.52))
	var hair: Color = look.get("hair", Color(0.2, 0.12, 0.06))
	body = StaticBody3D.new()
	body.collision_layer = Workshop.INTERACT_LAYER
	body.collision_mask = 0
	body.set_meta("staff", worker_id)
	body.scale = Vector3.ONE * clampf(float(look.get("tall", 1.0)), 0.85, 1.15)
	add_child(body)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	body.add_child(cs)
	var shirt := _mat(top)
	var trousers := _mat(legs)
	var shoes := _mat(Color(0.1, 0.08, 0.07))
	_pelvis = Node3D.new()
	_pelvis.position.y = PELVIS_Y
	body.add_child(_pelvis)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, 0.0, 0.0)
		_pelvis.add_child(hip)
		_part(hip, "capsule", Vector3(0.0, -0.4, 0.0), Vector3(0.22, 0.85, 0.22), trousers)
		_part(hip, "box", Vector3(0.0, -0.8, -0.05), Vector3(0.13, 0.1, 0.26), shoes)
		_legs.append(hip)
	_spine = Node3D.new()
	_pelvis.add_child(_spine)
	_part(_spine, "capsule", Vector3(0.0, 0.3, 0.0), Vector3(0.6, 0.6, 0.42), shirt)
	if look.get("tie", false):
		_part(_spine, "box", Vector3(0.0, 0.36, -0.215), Vector3(0.06, 0.3, 0.01), _mat(top.darkened(0.5)))
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.34 * side, 0.55, 0.0)
		_spine.add_child(shoulder)
		_part(shoulder, "capsule", Vector3(0.0, -0.27, 0.0), Vector3(0.14, 0.55, 0.14), shirt)
		_part(shoulder, "sphere", Vector3(0.0, -0.56, 0.0), Vector3(0.1, 0.1, 0.1), _mat(skin))
		_arms.append(shoulder)
	hand = Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0.0, -0.58, 0.0)
	_arms[1].add_child(hand)
	carry = Node3D.new()
	carry.name = "Carry"
	carry.position = Vector3(0.28, 0.22, -0.42)
	_spine.add_child(carry)
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.77, 0.0)
	_spine.add_child(_head)
	_part(_head, "sphere", Vector3.ZERO, Vector3(0.24, 0.27, 0.25), _mat(skin))
	if not look.get("bald", false):
		_part(_head, "sphere", Vector3(0.0, 0.06, 0.03), Vector3(0.26, 0.18, 0.26), _mat(hair))
	if look.get("hat", false):
		_part(_head, "cylinder", Vector3(0.0, 0.15, 0.0), Vector3(0.3, 0.1, 0.3), _mat(top.darkened(0.3)))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.1, 0.0)
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.width = 520.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate = Color(1.0, 0.92, 0.7)
	add_child(_label)
	_show_label()


static func _mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	_mats[c] = m
	return m


static func _mesh(kind: String) -> PrimitiveMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: PrimitiveMesh
	match kind:
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = 0.5
			c.height = 2.0
			c.radial_segments = 10
			c.rings = 4
			mesh = c
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 12
			s.rings = 6
			mesh = s
		"cylinder":
			var y := CylinderMesh.new()
			y.top_radius = 0.5
			y.bottom_radius = 0.5
			y.height = 1.0
			y.radial_segments = 12
			mesh = y
		_:
			mesh = BoxMesh.new()
	_meshes[kind] = mesh
	return mesh


func _part(parent: Node3D, kind: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	if kind == "capsule":
		size.y *= 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)


## Looked at (the look panel says who they are; nothing changes on the figure for now).
func set_hint(on: bool) -> void:
	if on == _hint:
		return
	_hint = on
	_show_label()


## What they're saying ("" for nothing).
func set_said(text: String) -> void:
	if text == _said:
		return
	_said = text
	_show_label()


func _show_label() -> void:
	if _label == null:
		return
	# Who they are goes in the look panel (StaffView.tooltip); only what they say floats.
	_label.text = "\"%s\"" % _said if _said != "" else ""
	_label.visible = _said != ""


## Moves the pose on `delta` seconds: walking (pushing a bike, or carrying something, with
## their arms out in front), or standing doing `anim` (see StaffJobs: "wrench", "hands",
## "type", "spray", "lance", "mix", "pour", "talk", "think", "detail", "grind"...), crouched
## down to the bike when `low`.
func animate(delta: float, walking: bool, pushing: bool, carrying: bool, anim: String, low: bool) -> void:
	_t += delta
	var drop := 0.0
	var lean := 0.0
	var twist := 0.0
	var leg := Vector2.ZERO
	var arm := Vector2.ZERO
	var nod := 0.0
	if walking:
		_phase += delta * (6.0 if pushing else 7.0)
		var swing := sin(_phase)
		leg = Vector2(swing, -swing) * 0.5
		if pushing:
			arm = Vector2(1.25, 1.25)
			lean = -0.18
		elif carrying:
			arm = Vector2(1.2, 1.2)
		else:
			arm = Vector2(-swing, swing) * 0.35
	else:
		match anim:
			"wrench", "fit", "grind", "changer", "oil", "blaster", "fairing", "tail":
				arm = Vector2(0.9, 1.1 + sin(_t * 6.0) * 0.3)
				lean = -0.25
			"type":
				arm = Vector2(1.15 + sin(_t * 17.0) * 0.06, 1.15 + sin(_t * 19.0 + 1.0) * 0.06)
				lean = -0.08
				nod = 0.2
			"spray", "lance":
				arm = Vector2(0.5, 1.45)
				twist = sin(_t * 1.6) * 0.35
			"mix":
				arm = Vector2(0.9, 1.1 + sin(_t * 5.0) * 0.18)
				twist = cos(_t * 5.0) * 0.12
				lean = -0.2
				nod = 0.25
			"pour":
				arm = Vector2(1.0, 1.35)
				lean = -0.12
				nod = 0.2
			"detail":
				arm = Vector2(1.0 + sin(_t * 4.0) * 0.2, 1.0 + cos(_t * 4.0) * 0.2)
				lean = -0.3
			"talk":
				arm = Vector2(0.15, 0.35 + absf(sin(_t * 2.4)) * 0.7)
				nod = sin(_t * 3.0) * 0.1
			"think":
				arm = Vector2(0.6, 2.3)
				nod = -0.15
			"tray", "carry":
				arm = Vector2(1.2, 1.2)
			"":
				arm = Vector2(0.04, 0.04) * sin(_t * 1.3)
			_:
				arm = Vector2(0.95 + sin(_t * 4.0) * 0.12, 0.95 - sin(_t * 4.0) * 0.12)
				lean = -0.12
		if carrying and anim == "":
			arm = Vector2(1.2, 1.2)
		if low:
			# Down on their haunches at the bike: thighs forward, leaning in.
			drop = 0.36
			leg = Vector2(1.1, 1.0)
			lean -= 0.2
	var k := minf(1.0, delta * EASE)
	_drop = lerpf(_drop, drop, k)
	_lean = lerpf(_lean, lean, k)
	_twist = lerpf(_twist, twist, k)
	_leg = _leg.lerp(leg, k if not walking else 1.0)
	_arm = _arm.lerp(arm, k)
	_nod = lerpf(_nod, nod, k)
	_pelvis.position.y = PELVIS_Y - _drop
	_spine.rotation = Vector3(_lean, _twist, 0.0)
	_legs[0].rotation.x = _leg.x
	_legs[1].rotation.x = _leg.y
	_arms[0].rotation.x = _arm.x
	_arms[1].rotation.x = _arm.y
	_head.rotation.x = -_nod
	# The tool stays pointing the way they face, out in front of the hand.
	hand.rotation.x = -_arm.y - _lean
