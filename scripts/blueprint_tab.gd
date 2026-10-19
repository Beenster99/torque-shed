class_name BlueprintTab
extends VBoxContainer
## The Esc menu's Blueprints tab: the shed's saved blueprints (rename, delete, build one in an
## empty bay) and the blueprint builds under way, with what each still needs and a button to
## order the missing parts. Every change goes through the host.

var _list: VBoxContainer
var _builds: VBoxContainer
var _sig := ""


func _ready() -> void:
	name = "Blueprints"
	add_theme_constant_override("separation", 10)
	add_child(UITheme.label("Save a bike as a blueprint in geometry mode ({geometry_mode} at a bike, then Save + blueprint), or copy any bike you "
		+ "look at, the cafe's included ({order_bike}, Copy its blueprint). Build one here: "
		+ "pick an empty bay and a hologram of the finished bike appears in it. Order the missing parts, put a frame on "
		+ "the bay's stand and fit the parts the hologram shows. The new bike gets the blueprint's fit.", 15, Color(1, 1, 1, 0.7)))
	add_child(UITheme.title("Blueprints", 22))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	add_child(UITheme.title("Builds under way", 22))
	var scroll2 := ScrollContainer.new()
	scroll2.custom_minimum_size = Vector2(0, 220)
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll2)
	_builds = VBoxContainer.new()
	_builds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_builds.add_theme_constant_override("separation", 6)
	scroll2.add_child(_builds)
	Shed.changed.connect(func(): if is_visible_in_tree(): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh(true))
	refresh(true)


## What the tab shows, so it's only rebuilt (losing a half-typed name) when that changes.
func _signature() -> String:
	var parts := [str(Shed.blueprints.keys()), str(Shed.blueprints.values().map(func(b): return b["name"]))]
	for bay in Workshop.bay_count():
		parts.append("%s:%s" % [Shed.bay_is_free(bay) and not Shed.holograms.has(bay), str(_states(bay))])
	return "|".join(parts)


func _states(bay: int) -> Array:
	var plan := Shed.plan_at(bay)
	if plan.is_empty():
		return []
	return Shed.plan_rows(plan, Shed.plan_bike(bay)).map(func(r): return r["state"])


func refresh(force := false) -> void:
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	for c in _builds.get_children():
		c.queue_free()
	var empty_bays := []
	for bay in Workshop.bay_count():
		if Shed.bay_is_free(bay) and not Shed.holograms.has(bay):
			empty_bays.append(bay)
	var ids: Array = Shed.blueprints.keys()
	ids.sort()
	if ids.is_empty():
		_list.add_child(UITheme.label("No blueprints yet.", 15, Color(1, 1, 1, 0.5)))
	for id in ids:
		_list.add_child(_blueprint_row(int(id), empty_bays))
	var bays := Shed.plan_bays()
	if bays.is_empty():
		_builds.add_child(UITheme.label("None.", 15, Color(1, 1, 1, 0.5)))
	for bay in bays:
		_builds.add_child(_build_row(int(bay)))


func _blueprint_row(id: int, empty_bays: Array) -> Control:
	var bp: Dictionary = Shed.blueprints[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var edit := LineEdit.new()
	edit.text = str(bp["name"])
	edit.max_length = 28
	edit.custom_minimum_size.x = 190.0
	edit.tooltip_text = "Type a new name and press Enter to rename it"
	edit.text_submitted.connect(func(t): Shed.request({"a": "bp_rename", "bp": id, "name": t}))
	row.add_child(edit)
	var parts := 0
	for slot in bp.get("parts", {}):
		if str(bp["parts"][slot]) != "none":
			parts += 1
	var info := UITheme.label("%d parts, %d fitted by hand" % [parts, (bp.get("geo", {}) as Dictionary).size()], 14, Color(1, 1, 1, 0.6))
	info.custom_minimum_size.x = 150.0
	row.add_child(info)
	var pick := OptionButton.new()
	for bay in empty_bays:
		pick.add_item("Bay %d" % (int(bay) + 1), int(bay))
	if empty_bays.is_empty():
		pick.add_item("No empty bay", -1)
		pick.disabled = true
	row.add_child(pick)
	var build := Button.new()
	build.text = "Build from blueprint"
	build.disabled = empty_bays.is_empty()
	build.pressed.connect(func():
		Shed.request({"a": "bp_build", "bp": id, "bay": pick.get_selected_id()}))
	row.add_child(build)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func(): Shed.request({"a": "bp_delete", "bp": id}))
	row.add_child(del)
	return row


func _build_row(bay: int) -> Control:
	var plan := Shed.plan_at(bay)
	var rows := Shed.plan_rows(plan, Shed.plan_bike(bay))
	var col := VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var done := rows.filter(func(r): return r["state"] in ["fitted", "other"]).size()
	var needed: Array = rows.filter(func(r): return r["state"] == "needed")
	var ordered := rows.filter(func(r): return r["state"] == "ordered").size()
	var title := UITheme.label("Bay %d: %s, %d of %d parts on, %d on order, %d needed%s" % [bay + 1, plan.get("name", ""), done,
		rows.size(), ordered, needed.size(), "" if Shed.plan_bike(bay) != 0 else " (waiting for a frame)"], 15, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var order := Button.new()
	order.text = "Order missing parts"
	order.disabled = needed.is_empty()
	order.pressed.connect(func(): Shed.request({"a": "bp_order", "bay": bay}))
	head.add_child(order)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): Shed.request({"a": "bp_cancel", "bay": bay}))
	head.add_child(cancel)
	col.add_child(head)
	if not needed.is_empty():
		var names: Array = needed.map(func(r): return str(r["name"]))
		var price := 0
		for r in needed:
			price += Shed.part_price(str(r["part"]))
		col.add_child(UITheme.label("Needed: %s. Price: %s, from the business's account." % [", ".join(names), TvChannels.money_text(price)],
			13, Color(1, 0.75, 0.6)))
	return col
