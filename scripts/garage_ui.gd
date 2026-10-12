class_name GarageUI
extends Control
## The garage: pick a part for each slot, see the stats and dyno curve change, then ride it.
## Builds can be saved as blueprints and loaded again.

signal build_applied(build: Dictionary)
signal closed

const BLUEPRINT_DIR := "user://blueprints"

var _pickers := {}       # slot -> OptionButton
var _descriptions := {}  # slot -> Label
var _stats: Label
var _dyno: DynoGraph
var _bp_name: LineEdit
var _bp_list: OptionButton
var _current := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 24
	root.offset_right = -24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	root.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var slots := VBoxContainer.new()
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("separation", 6)
	scroll.add_child(slots)
	slots.add_child(UITheme.title("THE GARAGE"))
	slots.add_child(UITheme.label("Swap parts, watch the numbers, then ride it.", 15, Color(1, 1, 1, 0.6)))
	for slot in PartsDB.SLOTS:
		slots.add_child(UITheme.label(PartsDB.SLOT_NAMES[slot].to_upper(), 14, UITheme.ACCENT))
		var picker := OptionButton.new()
		for id in PartsDB.by_slot[slot]:
			picker.add_item(PartsDB.get_part(id)["name"])
			picker.set_item_metadata(picker.item_count - 1, id)
		picker.item_selected.connect(func(_i): _on_changed())
		slots.add_child(picker)
		var desc := UITheme.label("", 14, Color(1, 1, 1, 0.55))
		slots.add_child(desc)
		_pickers[slot] = picker
		_descriptions[slot] = desc

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
	root.add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	right.add_child(col)
	col.add_child(UITheme.title("SPEC SHEET", 22))
	_stats = UITheme.label("", 17)
	col.add_child(_stats)
	col.add_child(UITheme.title("DYNO", 22))
	_dyno = DynoGraph.new()
	_dyno.custom_minimum_size = Vector2(460, 230)
	col.add_child(_dyno)
	col.add_child(UITheme.title("BLUEPRINTS", 22))
	var save_row := HBoxContainer.new()
	_bp_name = LineEdit.new()
	_bp_name.placeholder_text = "Blueprint name"
	_bp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_bp_name)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_save_blueprint)
	save_row.add_child(save_btn)
	col.add_child(save_row)
	var load_row := HBoxContainer.new()
	_bp_list = OptionButton.new()
	_bp_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_bp_list)
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_load_blueprint)
	load_row.add_child(load_btn)
	col.add_child(load_row)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var cancel := Button.new()
	cancel.text = "Close"
	cancel.pressed.connect(func(): closed.emit())
	buttons.add_child(cancel)
	var ride := Button.new()
	ride.text = "Build it and ride"
	ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ride.pressed.connect(func(): build_applied.emit(_current.duplicate()))
	buttons.add_child(ride)
	col.add_child(buttons)


func open(build: Dictionary) -> void:
	_current = PartsDB.sanitize_build(build)
	for slot in PartsDB.SLOTS:
		var picker: OptionButton = _pickers[slot]
		for i in picker.item_count:
			if picker.get_item_metadata(i) == _current[slot]:
				picker.select(i)
	_refresh_blueprints()
	_on_changed()
	show()


func _on_changed() -> void:
	for slot in PartsDB.SLOTS:
		var picker: OptionButton = _pickers[slot]
		_current[slot] = picker.get_item_metadata(picker.selected)
		_descriptions[slot].text = PartsDB.get_part(_current[slot]).get("description", "")
	var b := BikeBuild.new(_current)
	var pk := b.peak_power()
	_stats.text = "\n".join([
		"Weight:  %d kg (%d kg with rider)" % [roundi(b.bike_mass), roundi(b.total_mass)],
		"Engine:  %d cc, %d cyl, %d hp at %d rpm" % [roundi(b.displacement), b.cylinders, roundi(b.hp()), roundi(pk["rpm"])],
		"Torque:  %d Nm at %d rpm, redline %d" % [roundi(b.peak_torque), roundi(b.peak_torque_rpm), roundi(b.redline)],
		"Power to weight:  %d hp per tonne" % roundi(b.hp() / b.total_mass * 1000.0),
		"Gearing:  %d speeds, final drive %.2f" % [b.gear_count(), b.final_drive],
		"Top speed (est.):  %d km/h" % roundi(b.top_speed_estimate() * 3.6),
		"Wheelbase:  %d mm, rake %.0f deg" % [roundi(b.wheelbase * 1000), b.rake_deg],
		"Suspension:  %d mm front, %d mm rear" % [roundi(b.front_travel * 1000), roundi(b.rear_travel * 1000)],
		"Tyre grip:  tarmac %.2f, dirt %.2f" % [b.grip.get("tarmac", 0.0), b.grip.get("dirt", 0.0)],
	])
	_dyno.show_build(b)


func _refresh_blueprints() -> void:
	_bp_list.clear()
	DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)
	var dir := DirAccess.open(BLUEPRINT_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			_bp_list.add_item(f.get_basename())


func _save_blueprint() -> void:
	var name := _bp_name.text.strip_edges().validate_filename()
	if name == "":
		name = "bike_%d" % Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)
	var f := FileAccess.open("%s/%s.json" % [BLUEPRINT_DIR, name], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": name, "version": 1, "parts": _current}, "\t"))
	_refresh_blueprints()


func _load_blueprint() -> void:
	if _bp_list.selected < 0:
		return
	var path := "%s/%s.json" % [BLUEPRINT_DIR, _bp_list.get_item_text(_bp_list.selected)]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.has("parts"):
		open(data["parts"])
