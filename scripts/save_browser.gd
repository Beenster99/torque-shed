class_name SaveBrowser
extends PanelContainer
## The Load screen: every save game (see SaveGame) with its picture, name, when it was last
## played, the time played, the player's level and the garage's money, the latest first. From
## the title it plays one solo or hosts it; from the Esc menu it also saves, saves as a new game
## and loads another. Each save can be renamed or deleted (asked first).

signal load_game(id: String, as_host: bool)
signal save_now
signal save_as(called: String)
signal save_renamed(id: String, called: String)
## Something about the saves changed (one renamed, deleted or added): the title line follows.
signal changed
signal closed

const THUMB := Vector2(192, 108)

## Opened from the Esc menu, during a game, rather than from the title.
var in_game := false
var _title: Label
var _save_row: HBoxContainer
var _status: Label
var _list: VBoxContainer
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_alt: Button
var _name_except := ""
var _name_action: Callable
var _confirm: ConfirmationDialog
var _confirm_action: Callable


func _ready() -> void:
	name = "SaveGames"
	custom_minimum_size = Vector2(760, 600)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var top := HBoxContainer.new()
	_title = UITheme.title("Load a game", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(_button("Back", func(): close()))
	col.add_child(top)
	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 12)
	_save_row.add_child(_button("Save", func(): save_now.emit(); refresh.call_deferred()))
	_save_row.add_child(_button("Save as a new game...", func():
		ask_name("Save as a new game", "Save", SaveGame.unique_name(_current_name() + " copy"), "",
			func(called, _alt): save_as.emit(called); refresh.call_deferred())))
	col.add_child(_save_row)
	_status = UITheme.label("", 14, Color(1, 1, 1, 0.65))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_build_dialogs()


func _build_dialogs() -> void:
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.dialog_hide_on_ok = false
	var box := VBoxContainer.new()
	box.add_child(UITheme.label("Name this save:", 15))
	_name_edit = LineEdit.new()
	_name_edit.max_length = SaveGame.NAME_LENGTH
	_name_edit.custom_minimum_size.x = 360.0
	_name_edit.text_submitted.connect(func(_t): _name_ok(false))
	box.add_child(_name_edit)
	_name_error = UITheme.label("", 14, Color(1, 0.6, 0.5))
	box.add_child(_name_error)
	_name_dialog.add_child(box)
	_name_dialog.confirmed.connect(func(): _name_ok(false))
	_name_dialog.custom_action.connect(func(_a): _name_ok(true))
	add_child(_name_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm)


## Shows the saves; `from_game` when opened from the Esc menu.
func open(from_game: bool) -> void:
	in_game = from_game
	refresh()
	show()


func close() -> void:
	hide()
	closed.emit()


## Lists the saves again.
func refresh() -> void:
	if _list == null:
		return
	var client := Net.is_online() and not Net.is_host()
	_title.text = "Save games" if in_game else "Load a game"
	_save_row.visible = in_game and not client
	_status.text = ("Playing %s. %s" % [_current_name(), SaveGame.status_text()]) if in_game else \
		"Pick a game to carry on with. Each save keeps its own garage and its own character."
	for child in _list.get_children():
		child.queue_free()
	var saves := SaveGame.list_saves()
	if saves.is_empty():
		_list.add_child(UITheme.label("No saved games yet. Start one with New game.", 16, Color(1, 1, 1, 0.7)))
	for meta in saves:
		_list.add_child(_row(meta, client))


func _current_name() -> String:
	return str(SaveGame.read_meta(SaveGame.active_slot()).get("name", "this game"))


## One save: its picture, name and details, and what can be done with it.
func _row(meta: Dictionary, client: bool) -> Control:
	var id := str(meta["id"])
	var here := id == SaveGame.active_slot()
	var panel := PanelContainer.new()
	panel.name = "Save_" + id
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06) if not here else Color(UITheme.ACCENT, 0.14)
	style.border_color = UITheme.ACCENT if here else Color(1, 1, 1, 0.12)
	style.set_border_width_all(2 if here else 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var pic := SaveGame.thumbnail(id)
	if pic:
		var tr := TextureRect.new()
		tr.texture = pic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = THUMB
		row.add_child(tr)
	else:
		var blank := ColorRect.new()
		blank.color = Color(0.16, 0.17, 0.2)
		blank.custom_minimum_size = THUMB
		var l := UITheme.label("New shed" if bool(meta.get("fresh", false)) else "No picture yet", 13, Color(1, 1, 1, 0.45))
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		blank.add_child(l)
		row.add_child(blank)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	var title := UITheme.label(str(meta["name"]), 21, UITheme.ACCENT if here else Color(1, 1, 1, 0.95))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	if here:
		info.add_child(UITheme.label("Playing now" if in_game else "Last played", 13, UITheme.ACCENT))
	var who := str(meta.get("player", ""))
	info.add_child(UITheme.label("Level %d%s    Garage %s    %d bike%s" % [int(meta.get("level", 1)),
		"  " + who if who != "" else "", TvChannels.money_text(int(meta.get("garage_money", 0))),
		int(meta.get("bikes", 0)), "" if int(meta.get("bikes", 0)) == 1 else "s"], 15))
	info.add_child(UITheme.label("Played %s    Last played %s" % [SaveGame.play_time_text(float(meta.get("play_time", 0.0))),
		SaveGame._date_text(int(meta.get("saved_at", 0)))], 14, Color(1, 1, 1, 0.65)))
	row.add_child(info)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.custom_minimum_size.x = 120.0
	if not in_game:
		buttons.add_child(_button("Play solo", func(): load_game.emit(id, false)))
		buttons.add_child(_button("Host co-op", func(): load_game.emit(id, true)))
	elif not client:
		var load_b := _button("Load", func(): _ask_load(meta))
		load_b.disabled = here
		buttons.add_child(load_b)
	if not client:
		buttons.add_child(_button("Rename", func():
			ask_name("Rename %s" % str(meta["name"]), "Rename", str(meta["name"]), id, func(called, _alt):
				if SaveGame.rename_slot(id, called):
					save_renamed.emit(id, called)
				refresh()
				changed.emit())))
		var del := _button("Delete", func(): _ask_delete(meta))
		del.disabled = in_game and here
		del.tooltip_text = "This is the game you're playing." if del.disabled else ""
		buttons.add_child(del)
	row.add_child(buttons)
	return panel


func _ask_load(meta: Dictionary) -> void:
	var text := "Load %s?\n%s is saved first." % [str(meta["name"]), _current_name()]
	if Net.is_host():
		text += "\nYour crew will be sent back to their title screens."
	_ask("Load a game", text, "Load", func(): load_game.emit(str(meta["id"]), Net.is_host()))


func _ask_delete(meta: Dictionary) -> void:
	var id := str(meta["id"])
	_ask("Delete a save", "Delete %s?\nIts garage and character are gone for good." % str(meta["name"]), "Delete", func():
		delete_save(id))


## Deletes a save. The title's game moves on to the latest one left.
func delete_save(id: String) -> void:
	var was_current := id == SaveGame.active_slot()
	SaveGame.delete_slot(id)
	if was_current and not in_game:
		var left := SaveGame.list_saves()
		SaveGame.use_slot(str(left[0]["id"]) if not left.is_empty() else "")
	refresh()
	changed.emit()


func _ask(title: String, text: String, ok: String, action: Callable) -> void:
	_confirm.title = title
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok
	_confirm_action = action
	_confirm.popup_centered()


## Asks for a save's name: `action` gets (name, alt) once it's one that can be used. `alt_text`
## adds a second OK button (alt = true), like New game's Host co-op.
func ask_name(title: String, ok: String, initial: String, except_id: String, action: Callable, alt_text := "") -> void:
	_name_dialog.title = title
	_name_dialog.ok_button_text = ok
	_name_edit.text = initial
	_name_error.text = ""
	_name_except = except_id
	_name_action = action
	if _name_alt:
		_name_dialog.remove_button(_name_alt)
		_name_alt.queue_free()
		_name_alt = null
	if alt_text != "":
		_name_alt = _name_dialog.add_button(alt_text, true, "alt")
	_name_dialog.popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()


## The name dialog's OK: says what's wrong with the name, or goes ahead.
func _name_ok(alt: bool) -> void:
	var called := _name_edit.text.strip_edges()
	var why := SaveGame.name_problem(called, _name_except)
	if why != "":
		_name_error.text = why
		return
	_name_dialog.hide()
	_name_action.call(called, alt)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
