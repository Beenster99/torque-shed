class_name EmoteBar
extends PanelContainer
## The emote bar along the bottom of the screen while it's open (B on foot): each emote with
## the key that picks it (see Emotes and Walker.emote_menu_open).

var walker: Walker
var _row: HBoxContainer


func _ready() -> void:
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = -150.0
	offset_bottom = -96.0
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 18)
	add_child(_row)
	_row.add_child(UITheme.label("EMOTES", 16, UITheme.ACCENT))
	for i in Emotes.LIST.size():
		var e: String = Emotes.LIST[i]
		_row.add_child(UITheme.label("%d  %s" % [i + 1, Emotes.NAMES[e]], 16, Color.WHITE))
	_row.add_child(UITheme.label("%s: close" % Walker._keys("emote_menu"), 14, Color(1, 1, 1, 0.55)))
	for c in _row.get_children():
		(c as Label).autowrap_mode = TextServer.AUTOWRAP_OFF   # one line each, the bar sizes to fit
	visible = false


func _process(_delta: float) -> void:
	visible = walker != null and is_instance_valid(walker) and walker.emote_menu_open and walker.controls_enabled \
		and walker.process_mode != Node.PROCESS_MODE_DISABLED
