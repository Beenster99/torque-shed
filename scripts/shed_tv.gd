class_name ShedTv
extends Node3D
## A wall TV in the shed. When someone is out riding it shows them live from a chase camera;
## when nobody is, it shows the crew board. The live picture comes from one camera the
## Workshop shares between every TV (see Workshop.tv_feed).

var board: Dashboard
var _feed: MeshInstance3D
var _feed_mat: StandardMaterial3D
var _caption: Label3D


func _init(width: float, height: float) -> void:
	board = Dashboard.new("crew", width)
	add_child(board)
	_feed_mat = StandardMaterial3D.new()
	_feed_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feed = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width * 9.0 / 16.0)
	_feed.mesh = quad
	_feed.material_override = _feed_mat
	_feed.position.z = 0.032
	_feed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_feed.visible = false
	add_child(_feed)
	_caption = Label3D.new()
	_caption.font_size = 32
	_caption.pixel_size = width / 1400.0
	_caption.outline_size = 8
	_caption.modulate = Color(1.0, 0.9, 0.5)
	_caption.position = Vector3(0.0, -width * 9.0 / 32.0 + width * 0.04, 0.034)
	_caption.visible = false
	add_child(_caption)
	var _unused := height


## Shows the live picture (null for the crew board) with a caption such as "LIVE: Simon on Old Faithful".
func show_feed(texture: Texture2D, caption: String) -> void:
	_feed.visible = texture != null
	_caption.visible = texture != null
	if texture:
		_feed_mat.albedo_texture = texture
		_caption.text = caption


func is_live() -> bool:
	return _feed.visible
