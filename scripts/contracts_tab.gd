class_name ContractsTab
extends ScrollContainer
## The Esc menu's Contracts tab: every job under way with its goals, MOT sheet, deadline and
## what handing it back would pay, with Run MOT test and Hand back (see ContractPanel).

var _box: VBoxContainer
var _sig := ""


func _ready() -> void:
	name = "Contracts"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	Shed.changed.connect(func(): if is_visible_in_tree(): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh(true))
	refresh(true)


func refresh(force := false) -> void:
	var sig := ContractPanel.jobs_signature()
	if sig == _sig and not force:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(UITheme.title("Contracts", 26))
	ContractPanel.fill_jobs(_box)
