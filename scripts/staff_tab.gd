class_name StaffTab
extends ScrollContainer
## The Esc menu's Staff tab: the garage's payroll (each worker's role, skill level, what they're
## doing, mood and wage, with Talk / Assign and Let go), the day's wages and how the running
## costs setting bites on them, and the hiring board: today's candidates, one or more per role,
## with their look, back story, skill and wage. Roles unlock with your character level (the
## Expert Mechanic last); the board changes every day. Everything goes through the host as
## staff_* requests (see Staff).

signal talk_requested(worker_id: int)

var _box: VBoxContainer
var _status: Label
var _staff: VBoxContainer
var _board: VBoxContainer
var _wages: Label
var _sig := ""
var _confirm_id := 0


func _ready() -> void:
	name = "Staff"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	_box.add_child(UITheme.title("Staff", 26))
	_box.add_child(UITheme.label("Hire people to work in the shed. Give them a job (here, or walk up and press {interact}) and they go "
		+ "and do it with the shed's own parts and kit, then come back and tell you. With nothing to do they get on with their own "
		+ "duty: the receptionist greets customers, the salesman deals with buyers, and someone goes for teas now and then.", 14,
		Color(1, 1, 1, 0.6)))
	_status = UITheme.label("", 15, Color(1, 0.85, 0.7))
	_box.add_child(_status)
	Shed.feedback.connect(func(text: String, _ok: bool):
		if is_visible_in_tree():
			_status.text = text)
	_box.add_child(UITheme.title("On the payroll", 20))
	_wages = UITheme.label("", 15, UITheme.ACCENT)
	_box.add_child(_wages)
	_staff = VBoxContainer.new()
	_staff.add_theme_constant_override("separation", 6)
	_box.add_child(_staff)
	_box.add_child(UITheme.title("Hiring board", 20))
	_box.add_child(UITheme.label("New faces every morning. A better hand costs more, and everyone's wage goes up as they get better.",
		14, Color(1, 1, 1, 0.6)))
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 6)
	_box.add_child(_board)
	Shed.changed.connect(func(): if is_visible_in_tree(): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())


## Fills the lists in again if anything shown has changed.
func refresh() -> void:
	var parts := [Progress.level(), _confirm_id, str(Shed.bank.get("costs", "normal"))]
	for id in Staff.workers():
		var w: Dictionary = Staff.workers()[id]
		parts.append("%d|%s|%d|%d|%s|%s" % [int(id), Staff.status_text(w), Staff.level(w), int(w["wage"]), Staff.mood_word(w), str(w["sick"])])
	parts.append(str(Staff.board().keys()))
	var sig := str(parts)
	if sig == _sig:
		return
	_sig = sig
	_fill_staff()
	_fill_board()


func _fill_staff() -> void:
	for c in _staff.get_children():
		c.queue_free()
	var ids: Array = Staff.workers().keys()
	ids.sort()
	var bill := Staff.wage_bill()
	var mode := str(Shed.bank.get("costs", "normal"))
	var mult := float(Money.COSTS_MULT.get(mode, 1.0))
	_wages.text = "%d of %d  ·  wages %s a day, paid with the nightly running costs bill: %s tonight with running costs on %s." % [
		ids.size(), Staff.MAX_STAFF, Staff.money(bill), Staff.money(roundi(bill * mult)), str(Money.COSTS_NAMES.get(mode, mode))]
	if ids.is_empty():
		_staff.add_child(UITheme.label("Nobody yet.", 15, Color(1, 1, 1, 0.55)))
	for id in ids:
		var w: Dictionary = Staff.workers()[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_swatch(w["look"].get("top", Color.GRAY)))
		var info := UITheme.label("%s  ·  %s, level %d  ·  %s  ·  %s a day\n%s" % [str(w["name"]), Staff.role_name(str(w["role"])),
			Staff.level(w), Staff.mood_word(w), Staff.money(int(w["wage"])), Staff.status_text(w)], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var wid := int(id)
		row.add_child(_button("Talk / assign", func(): talk_requested.emit(wid)))
		if _confirm_id == wid:
			row.add_child(_button("Yes, let %s go" % Staff.first_name(w), func():
				_confirm_id = 0
				Shed.request({"a": "staff_fire", "worker": wid})))
			row.add_child(_button("No", func():
				_confirm_id = 0
				refresh()))
		else:
			row.add_child(_button("Let go", func():
				_confirm_id = wid
				refresh()))
		_staff.add_child(row)


func _fill_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	var ids: Array = Staff.board().keys()
	ids.sort_custom(func(a, b): return Staff.ROLES.find(str(Staff.board()[a]["role"])) < Staff.ROLES.find(str(Staff.board()[b]["role"])))
	if ids.is_empty():
		_board.add_child(UITheme.label("Nobody's looking today.", 15, Color(1, 1, 1, 0.55)))
	for id in ids:
		var c: Dictionary = Staff.board()[id]
		var role := str(c["role"])
		var need := int(Staff.UNLOCK.get(role, 1))
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		row.add_child(_swatch(c["look"].get("top", Color.GRAY)))
		var story := []
		for bit in c.get("story", []):
			if bit is Array and bit.size() > 1:
				story.append(str(bit[1]))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UITheme.label("%s  ·  %s  ·  level %d  ·  %s a day" % [str(c["name"]), Staff.role_name(role), int(c["level"]),
			Staff.money(int(c["wage"]))], 16))
		info.add_child(UITheme.label(" ".join(story), 13, Color(1, 1, 1, 0.6)))
		row.add_child(info)
		var cid := int(id)
		if Progress.level() < need:
			var l := UITheme.label("Unlocks at level %d" % need, 14, Color(1, 0.7, 0.4))
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(l)
		else:
			var why := Shed.check(Shed.me(), {"a": "staff_hire", "cand": cid})
			var b := _button("Hire", func(): Shed.request({"a": "staff_hire", "cand": cid}))
			b.disabled = why != ""
			b.tooltip_text = why
			row.add_child(b)
		_board.add_child(panel)


func _swatch(c) -> ColorRect:
	var r := ColorRect.new()
	r.color = c if c is Color else Color.GRAY
	r.custom_minimum_size = Vector2(10, 40)
	return r


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


## Presses the button labelled `text` (for tests): the first, or the `nth` one.
func press(text: String, nth := 0) -> void:
	var n := 0
	for b in find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not b.is_queued_for_deletion():
			if n == nth:
				(b as Button).pressed.emit()
				return
			n += 1


## Everything the tab says now (tests).
func text() -> String:
	var lines := []
	for l in find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			lines.append((l as Label).text)
	return "\n".join(lines)
