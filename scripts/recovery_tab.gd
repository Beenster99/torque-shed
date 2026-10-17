class_name RecoveryTab
extends ScrollContainer
## The Esc menu's Recovery tab: the recovery jobs on offer and under way, and a delivered bike's
## assessment (see RecoveryPanel).

var _box: VBoxContainer
var _sig := ""
var _job := 0


func _ready() -> void:
	name = "Recovery"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	Shed.changed.connect(func(): if is_visible_in_tree(): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh(true))
	refresh(true)


func refresh(force := false) -> void:
	if _job != 0 and not Recovery.jobs().has(_job):
		_job = 0
	var sig := str(_job) + RecoveryPanel.signature()
	if sig == _sig and not force:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	if _job != 0:
		RecoveryPanel.fill_assessment(_box, Recovery.jobs()[_job], func(): _show(0))
		_box.add_child(ContractPanel.button("Back to the list", func(): _show(0)))
		return
	_box.add_child(UITheme.title("Recovery", 26))
	RecoveryPanel.fill(_box, _show)


func _show(id: int) -> void:
	_job = id
	refresh(true)
