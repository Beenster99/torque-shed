class_name BoardPrint
extends Node3D
## A whiteboard drawing printed as a poster (see Shed.posters): the design's marks drawn the
## way the board draws them (Whiteboard.mark_node) into a SubViewport, shown on a sheet in a
## thin black frame. Drawn again when the print's data, or a picture in it, arrives.

const PX_SCALE := 0.75       # the print's resolution, against the board's own

var design := 0
var _viewport: SubViewport
var _ink: Node2D
var _size := Vector2.ONE


func _init(design_id: int, size: Vector2) -> void:
	design = design_id
	_size = size
	name = "BoardPrint"


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(BoardData.PX * PX_SCALE)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = BoardData.BG
	bg.size = BoardData.PX
	_ink = Node2D.new()
	_ink.scale = Vector2(PX_SCALE, PX_SCALE)
	_viewport.add_child(_ink)
	_ink.add_child(bg)
	var sheet := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = _size
	sheet.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.roughness = 0.75
	mat.metallic_specular = 0.3
	sheet.material_override = mat
	sheet.position.z = 0.004
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.06, 0.06, 0.07)
	frame.roughness = 0.5
	var bar := 0.02
	for side in [-1.0, 1.0]:
		_bar(Vector3(0.0, side * (_size.y + bar) * 0.5, 0.008), Vector3(_size.x + bar * 2.0, bar, 0.016), frame)
		_bar(Vector3(side * (_size.x + bar) * 0.5, 0.0, 0.008), Vector3(bar, _size.y, 0.016), frame)
	Shed.blob_arrived.connect(_on_blob)
	redraw()


func _bar(center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	add_child(mi)


func _on_blob(id: int) -> void:
	var p: Dictionary = Shed.posters.get(design, {})
	if id == int(p.get("blob", 0)) or Array(p.get("imgs", [])).has(id):
		redraw()


## How many marks the print shows (0 until its data has arrived).
func mark_count() -> int:
	return _ink.get_child_count() - 1 if _ink else 0


## Draws the design's marks afresh.
func redraw() -> void:
	for i in range(_ink.get_child_count() - 1, 0, -1):
		var old := _ink.get_child(i)
		_ink.remove_child(old)
		old.queue_free()
	for m in Shed.poster_marks(design):
		_ink.add_child(Whiteboard.mark_node(m, null))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
