class_name TuningComputer
extends Control
## The dyno desk in the tuning room: tune the bike on the rig (or any bike close by) and run
## it on the dyno. Engine map, ignition and rev limiter; suspension clickers where the parts
## have them; tyre pressures and chain tension; sprockets and, with a cassette gearbox, the
## ratio spacing; the fitted ECU's rider aids (traction control, stability control and
## anti-wheelie, those it has: off or a level each); and drilling and trimming parts for lightness. Every change goes through the
## Shed so the whole crew sees the same tune, and riding uses it too.

signal closed

const REACH := 10.0           # metres: bikes this close to you can be tuned from the desk
const SEND_EVERY := 0.12      # seconds between slider updates sent to the host
## Each tab's settings: [key, name, slider step].
const TABS := {
	"Engine": [["map", "Fuel map", 0.05], ["ignition", "Ignition timing", 0.05], ["limiter", "Rev limiter", 100.0]],
	"Suspension": [["f_preload", "Front preload", 0.1], ["f_bump", "Front compression", 0.1], ["f_rebound", "Front rebound", 0.1],
		["r_preload", "Rear preload", 0.1], ["r_bump", "Rear compression", 0.1], ["r_rebound", "Rear rebound", 0.1]],
	"Tyres & chain": [["psi_f", "Front tyre pressure", 0.05], ["psi_r", "Rear tyre pressure", 0.05], ["chain", "Chain slack", 1.0]],
	"Gearing": [["sprocket_f", "Front sprocket", 1.0], ["sprocket_r", "Rear sprocket", 1.0], ["spread", "Ratio spacing", 0.1]],
	"Rider aids": [["aid_traction", "Traction control", 1.0], ["aid_stability", "Stability control", 1.0],
		["aid_anti_wheelie", "Anti-wheelie", 1.0]],
}
## What each of the ECU's rider aids does, under its slider.
const AID_HELP := {
	"aid_traction": "Cuts the power when the back tyre spins up. Higher steps in sooner and harder; off lets it slide.",
	"aid_stability": "Damps a weave, a tank-slapper or a twitchy slide. Higher holds the bike steadier.",
	"aid_anti_wheelie": "Trims the power to keep the front wheel down. Lower lets it lift further; off for wheelies.",
}

var bike_id := 0
var _from := Vector3.ZERO
var _bikes: OptionButton
var _tabs: TabContainer
var _rows := {}               # key -> {slider, value, why, reset}
var _weight: VBoxContainer
var _aids_note: Label         # the Rider aids tab's line on what this bike's ECU offers
var _summary: Label
var _graph: DynoGraph
var _ride_graph: TelemetryGraph   # the last ride's telemetry, shown while the Last ride tab is open
var _ride_text: Label
var _ride_wait := 0.0            # seconds till the Last ride page is redrawn
var _run: Button
var _status: Label
var _pending := {}            # key -> value waiting to be sent
var _dragging := ""
var _send_timer := 0.0
var _weight_sig := ""
var _refreshing := false      # set while the sliders are moved to match the Shed, so it isn't sent back


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	theme.set_stylebox("slider", "HSlider", track)
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = UITheme.ACCENT.darkened(0.2)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(UITheme.title("DYNO & TUNING"))
	_bikes = OptionButton.new()
	_bikes.custom_minimum_size = Vector2(340, 40)
	_bikes.item_selected.connect(func(i): _select(_bikes.get_item_id(i)))
	head.add_child(_bikes)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var stock := Button.new()
	stock.text = "Back to stock"
	stock.pressed.connect(_reset_all)
	head.add_child(stock)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_computer)
	head.add_child(close)
	root.add_child(head)
	root.add_child(UITheme.label("Change a setting, run the dyno and compare: the last run stays on the graph, dashed. "
		+ "Riding uses the same tune.", 15, Color(1, 1, 1, 0.6)))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_tabs)
	for tab in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		_tabs.add_child(scroll)
		if tab == "Rider aids":
			_aids_note = UITheme.label("", 15, Color(1, 1, 1, 0.6))
			_aids_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(_aids_note)
		for row in TABS[tab]:
			_add_row(list, str(row[0]), str(row[1]), float(row[2]))
	var wscroll := ScrollContainer.new()
	wscroll.name = "Weight"
	wscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wscroll.follow_focus = true
	_weight = VBoxContainer.new()
	_weight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight.add_theme_constant_override("separation", 6)
	wscroll.add_child(_weight)
	_tabs.add_child(wscroll)
	_build_ride_tab()
	_summary = UITheme.label("", 15, UITheme.ACCENT)
	left.add_child(_summary)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	_graph = DynoGraph.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_graph)
	_ride_graph = TelemetryGraph.new()
	_ride_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ride_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride_graph.visible = false
	right.add_child(_ride_graph)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_run = Button.new()
	_run.text = "Run the dyno"
	_run.custom_minimum_size = Vector2(220, 48)
	_run.pressed.connect(func(): Shed.request({"a": "dyno_run", "bike": bike_id}))
	bar.add_child(_run)
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.75))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	right.add_child(bar)

	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	Shed.changed.connect(func(): if visible: refresh())


func _add_row(list: VBoxContainer, key: String, title: String, step: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var name_label := UITheme.label(title, 17)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var value := UITheme.label("", 16, UITheme.ACCENT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(value)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Put it back to how it came from the factory"
	reset.pressed.connect(func(): Shed.request({"a": "tune", "bike": bike_id, "key": key, "reset": true}))
	top.add_child(reset)
	box.add_child(top)
	var slider := HSlider.new()
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 26)
	slider.value_changed.connect(func(v):
		if _refreshing:
			return
		_pending[key] = v
		_show_value(key, v))
	slider.drag_started.connect(func(): _dragging = key)
	slider.drag_ended.connect(func(_changed): _dragging = "")
	box.add_child(slider)
	var why := UITheme.label("", 14, Color(1, 1, 1, 0.5))
	if AID_HELP.has(key):
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(why)
	list.add_child(box)
	_rows[key] = {"slider": slider, "value": value, "why": why, "reset": reset, "box": box}


func open(from := Vector3.ZERO) -> void:
	_from = from
	visible = true
	_status.text = ""
	var on := Shed.dyno_bike()
	if on != 0:
		bike_id = on
	elif not _in_reach(bike_id):
		bike_id = 0
	refresh()
	# Somewhere for a pad to start: A runs the dyno, the d-pad goes to the settings.
	_run.grab_focus()


func close_computer() -> void:
	_flush()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		close_computer()
	elif event is InputEventJoypadButton and (event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev")):
		# LB / RB on a pad: the next or previous tab, with the focus on its first setting.
		var step := 1 if event.is_action_pressed("tool_next") else -1
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		_focus_tab.call_deferred()
	else:
		return
	get_viewport().set_input_as_handled()


## The pad's focus on the first setting in the tab showing, or the Run button.
func _focus_tab() -> void:
	var tab := _tabs.get_current_tab_control()
	var stack: Array = [tab] if tab else []
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Control and n != tab and (n as Control).focus_mode != Control.FOCUS_NONE and (n as Control).is_visible_in_tree() \
				and not (n is ScrollBar):
			if not (n is BaseButton and (n as BaseButton).disabled):
				(n as Control).grab_focus()
				return
		stack.append_array(n.get_children())
	_run.grab_focus()


func _in_reach(id: int) -> bool:
	if not Shed.bikes.has(id) or Shed.bikes[id]["rider"] != 0:
		return false
	return Shed.on_dyno(id) or (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(_from) < REACH or _from == Vector3.ZERO


## The bikes that can be tuned from here: the one on the dyno first, then those within reach.
func tunable_bikes() -> Array:
	var out := []
	var on := Shed.dyno_bike()
	if on != 0:
		out.append(on)
	var near := []
	for id in Shed.bikes:
		if id != on and _in_reach(id):
			near.append(id)
	near.sort_custom(func(a, b): return (Shed.bikes[a]["xf"] as Transform3D).origin.distance_to(_from) < (Shed.bikes[b]["xf"] as Transform3D).origin.distance_to(_from))
	out.append_array(near)
	return out


func _select(id: int) -> void:
	_flush()
	bike_id = id
	refresh()


func _reset_all() -> void:
	if not Shed.bikes.has(bike_id):
		return
	var tune := Shed.tune_of(bike_id)
	for key in tune:
		Shed.request({"a": "tune", "bike": bike_id, "key": key, "reset": true})


func refresh() -> void:
	_refreshing = true
	_refresh()
	_refreshing = false


func _refresh() -> void:
	var ids := tunable_bikes()
	if not ids.has(bike_id):
		bike_id = ids[0] if not ids.is_empty() else 0
	_bikes.clear()
	for id in ids:
		_bikes.add_item("%s%s" % [Shed.bikes[id]["name"], "  (on the dyno)" if Shed.on_dyno(id) else ""], id)
		if id == bike_id:
			_bikes.select(_bikes.item_count - 1)
	if bike_id == 0:
		_bikes.add_item("No bike in reach: wheel one onto the dyno", 0)
		for key in _rows:
			(_rows[key]["slider"] as HSlider).editable = false
			(_rows[key]["reset"] as Button).disabled = true
		_summary.text = ""
		_run.disabled = true
		_graph.show_runs("DYNO", [], 1.0, {}, "Wheel a bike onto the dyno, or bring one close, to tune it.")
		return
	var build := Shed.build_of(bike_id)
	# Fine Tuning (a skill) shows its wider range before the first change is made.
	build.tune["reach"] = maxf(float(build.tune.get("reach", 0.0)), Progress.tune_reach(Shed.me()))
	var tune := Shed.tune_of(bike_id)
	for key in _rows:
		var row: Dictionary = _rows[key]
		var slider: HSlider = row["slider"]
		var why := build.tune_block(key)
		var home: Array = Shed.TUNE_HOME[key]
		if why == "" and home[0] != "bike" and Shed.item_on(bike_id, str(home[0])) == 0:
			why = "There's no %s fitted." % PartsDB.slot_name(str(home[0])).to_lower()
		var r := build.tune_range(key)
		if why == "" and r.x >= r.y:
			why = "Can't be changed with this ECU."
		if why == "" and key in ["map", "ignition", "limiter"]:
			why = _ecu_text(build, key)
		if AID_HELP.has(key):
			# Only the aids this bike's ECU has are shown.
			(row["box"] as Control).visible = why == ""
			why = AID_HELP[key] if why == "" else why
		(row["why"] as Label).text = why
		slider.min_value = r.x
		slider.max_value = maxf(r.y, r.x + 0.001)
		var blocked: bool = build.tune_block(key) != "" or r.x >= r.y or (home[0] != "bike" and Shed.item_on(bike_id, str(home[0])) == 0)
		slider.editable = not blocked
		(row["reset"] as Button).disabled = blocked or not (tune.has(key) or key == "chain")
		var v := build.tune_value(key) if key != "chain" else build.chain_slack
		if _dragging != key and not _pending.has(key):
			slider.set_value_no_signal(v)
		_show_value(key, slider.value if (_dragging == key or _pending.has(key)) else v, build)
	_aids_note.text = aids_note(build)
	_run.disabled = not Shed.on_dyno(bike_id)
	_run.text = "Run the dyno" if Shed.on_dyno(bike_id) else "Put it on the dyno to run it"
	_refresh_weight()
	var s := build.summary()
	_summary.text = "Now: %.1f hp  ·  %.0f Nm  ·  top %s  ·  %s  ·  %s\nEngine wear x%.1f  ·  0-100 %s%s" % [
		float(s["hp"]), float(s["torque"]), Units.kmh(float(s["top_kmh"])), Units.mass(build.bike_mass),
		Units.economy(float(s["economy"])), build.engine_stress, "%.2f s" % build.zero_to_100() if build.zero_to_100() > 0.0 else "--",
		("\n" + "\n".join(build.notes.slice(0, 3))) if not build.notes.is_empty() else ""]
	_summary.text += dyno_reader_text(build, Progress.skill_rank(Shed.me(), "dyno_reader"))
	_update_graph()


## Dyno Reader (a skill): what wear, rust and grime are costing (rank 1), and the one part whose
## restoration would give the most back (rank 2). "" without the skill.
static func dyno_reader_text(build: BikeBuild, rank: int) -> String:
	if rank <= 0:
		return ""
	var hp := build.hp()
	var fresh := build.condition.duplicate(true)
	for slot in fresh:
		for k in ["rust", "dirt", "wear"]:
			fresh[slot][k] = 0.0
	var text := "\nDyno Reader: wear and grime cost %.1f hp" % maxf(0.0, BikeBuild.new(build.parts, fresh, build.tune).hp() - hp)
	if rank >= 2:
		var best_slot := ""
		var best := 0.1
		for slot in build.condition:
			var one := build.condition.duplicate(true)
			for k in ["rust", "dirt", "wear"]:
				one[slot][k] = 0.0
			var gain := BikeBuild.new(build.parts, one, build.tune).hp() - hp
			if gain > best:
				best = gain
				best_slot = str(slot)
		if best_slot != "":
			text += "  ·  restore the %s first (+%.1f hp)" % [PartsDB.slot_name(best_slot).to_lower(), best]
	return text


## The Rider aids tab's line: which aids the fitted ECU has that can be set here, or that it has none.
static func aids_note(build: BikeBuild) -> String:
	var ecu := PartsDB.part_name(build.parts["ecu"]) if build.has_part("ecu") else ""
	var names: Array[String] = []
	for aid in BikeBuild.AID_KEYS:
		if build.has_aid(aid):
			names.append(str(PartsDB.ECU_AID_NAMES.get(aid, aid)))
	if names.is_empty():
		return ("%s: no rider aids to set. A sport or race ECU brings traction control, anti-wheelie and stability control." % ecu) \
			if ecu != "" else "No ECU fitted, so no rider aids. A sport or race ECU brings traction control, anti-wheelie and stability control."
	return "%s: set its %s here. Each goes from off to level %d; level %d is how it comes from the factory. Riding uses them." % [
		ecu, " and ".join(names) if names.size() <= 2 else ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1],
		BikeBuild.AID_LEVELS, BikeBuild.AID_STOCK]


func _ecu_text(build: BikeBuild, key: String) -> String:
	var ecu := PartsDB.part_name(build.parts["ecu"]) if build.has_part("ecu") else "No ECU (jets and timing plate)"
	if key == "limiter":
		return "%s: up to %+d rpm over stock." % [ecu, roundi(build.tune_range("limiter").y)]
	return "%s: %d%% of the range. A remap or race ECU opens it all up." % [ecu, roundi(build.ecu_reach() * 100.0)] \
		if build.ecu_reach() < 1.0 else "%s: full range." % ecu


func _show_value(key: String, v: float, build: BikeBuild = null) -> void:
	if build == null:
		if not Shed.bikes.has(bike_id):
			return
		build = Shed.build_of(bike_id)
	(_rows[key]["value"] as Label).text = value_text(key, v, build)


## How a setting reads on the desk: "Rich 20%", "+3.0° advance", "2.10 bar (30 psi)".
static func value_text(key: String, v: float, build: BikeBuild) -> String:
	match key:
		"map":
			return "Stock" if absf(v) < 0.01 else ("%s %d%%" % ["Rich" if v > 0.0 else "Lean", roundi(absf(v) * 100.0)])
		"ignition":
			return "Stock" if absf(v) < 0.01 else "%+.1f° %s" % [v * 6.0, "advance" if v > 0.0 else "retard"]
		"limiter":
			return "%d rpm (%+d)" % [roundi(build.stock_redline + v), roundi(v)]
		"psi_f", "psi_r":
			var best := build.tune_default(key)
			return "%.2f bar · %d psi%s" % [v, roundi(v * 14.504), "" if absf(v - best) < 0.03 else " (best %.1f)" % best]
		"chain":
			return "%d mm (%s)" % [roundi(v), "too tight" if v < Shed.CHAIN_SLACK_GOOD.x else ("too slack" if v > Shed.CHAIN_SLACK_GOOD.y else "right")]
		"sprocket_f", "sprocket_r":
			var f := v if key == "sprocket_f" else build.tune_value("sprocket_f")
			var r := v if key == "sprocket_r" else build.tune_value("sprocket_r")
			return "%d teeth (%.2f:1)" % [roundi(v), r / f]
		"spread":
			return "Stock" if absf(v) < 0.01 else "%s %d%%" % ["Wider" if v > 0.0 else "Closer", roundi(absf(v) * 100.0)]
		"aid_traction", "aid_stability", "aid_anti_wheelie":
			var level := roundi(v)
			if level <= 0:
				return "Off"
			return "Level %d of %d%s" % [level, BikeBuild.AID_LEVELS, " (factory)" if level == BikeBuild.AID_STOCK else ""]
	var clicks := roundi(v * 10.0)
	return "Stock" if clicks == 0 else "%+d clicks (%s)" % [clicks, "firmer" if clicks > 0 else "softer"]


## Parts on the bike that can be drilled and trimmed for lightness.
func _refresh_weight() -> void:
	var sig := str(bike_id)
	var list := []
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id == 0:
			continue
		var part := str(Shed.items[id]["part"])
		var cut := BikeBuild.lighten_cut(part)
		if cut <= 0.0 and not PartsDB.is_lightweight(part):
			continue
		list.append([slot, id, part, cut])
		sig += "|%d:%s" % [id, Shed.items[id].get("lightened", false)]
	if sig == _weight_sig:
		return
	_weight_sig = sig
	for c in _weight.get_children():
		c.queue_free()
	_weight.add_child(UITheme.label("Drill and trim parts to save weight. It's done once per part and costs it some condition: "
		+ "a lightened part is a little weaker and wears faster.", 15, Color(1, 1, 1, 0.6)))
	for entry in list:
		var it: Dictionary = Shed.items[int(entry[1])]
		var mass := float(PartsDB.get_part(str(entry[2])).get("mass", 0.0))
		var row := HBoxContainer.new()
		var text := UITheme.label("%s: %s, %s" % [PartsDB.slot_name(str(entry[0])), PartsDB.part_name(str(entry[2])),
			Units.mass(mass * (1.0 - BikeBuild.lighten_cut(str(entry[2]), float(it.get("lighten_extra", 0.0)))) if it.get("lightened", false) else mass, 1)], 16)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 0)
		if PartsDB.is_lightweight(str(entry[2])):
			b.text = "Already light"
			b.disabled = true
		elif it.get("lightened", false):
			b.text = "Lightened"
			b.disabled = true
		else:
			b.text = "Lighten (-%s)" % Units.mass(mass * BikeBuild.lighten_cut(str(entry[2]), Progress.lighten_bonus(Shed.me())), 1)
			var item_id := int(entry[1])
			b.pressed.connect(func(): Shed.request({"a": "lighten", "item": item_id}))
		row.add_child(b)
		_weight.add_child(row)


func _update_graph() -> void:
	if not Shed.bikes.has(bike_id):
		return
	var runs: Array = Shed.bikes[bike_id].get("dyno", {}).get("runs", [])
	var room: Node = get_tree().get_first_node_in_group("dyno_room") if is_inside_tree() else null
	var p := 1.0
	var live := {}
	if room:
		p = room.progress_for(bike_id)
		live = room.live_for(bike_id)
	_graph.show_runs("DYNO: %s" % Shed.bikes[bike_id]["name"], runs, p, live,
		"" if not runs.is_empty() else ("Press Run the dyno to see its curves." if Shed.on_dyno(bike_id)
		else "Wheel it onto the dyno to measure it. You can still tune it here."))


## Sends the slider moves waiting to go.
func _flush() -> void:
	for key in _pending:
		if Shed.bikes.has(bike_id):
			Shed.request({"a": "tune", "bike": bike_id, "key": key, "value": float(_pending[key])})
	_pending.clear()


## The Last ride tab: what the telemetry recorded on your last ride (RideTelemetry.last), drawn
## as strip charts in place of the dyno graph while the tab is open.
func _build_ride_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Last ride"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ride_text = UITheme.label("", 15)
	_ride_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ride_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ride_text)
	_tabs.add_child(scroll)


## Whether the Last ride tab is the one open.
func showing_ride() -> bool:
	var tab := _tabs.get_current_tab_control()
	return tab != null and tab.name == "Last ride"


func _update_ride() -> void:
	var tel := RideTelemetry.last
	_ride_graph.telemetry = tel
	_ride_graph.queue_redraw()
	if tel == null or tel.size() < 2:
		_ride_text.text = "No ride recorded yet. Ride a bike and come back: the telemetry logs every ride."
		return
	var s := tel.summary()
	_ride_text.text = ("%s\n\n%d:%02d ridden, top speed %s\nMost lean %.0f°\nHardest braking %.2f g, hardest cornering %.2f g\n"
		+ "Past the grip: front %.1f s, rear %.1f s\n\nThe charts show speed, lean, steering, bar torque, each tyre's "
		+ "slip ratio and slip angle, how much of its grip it used (1 is the limit: above it the tyre slides), "
		+ "the loads on the tyres, the throttle and brakes, the gear and the revs. Front tyre blue, rear orange. "
		+ "F3 shows the same live at the side of the screen while you ride.") % [
		tel.bike_name if tel.bike_name != "" else "Last ride", int(s["duration"]) / 60, int(s["duration"]) % 60,
		Units.kmh(float(s["top_kmh"])), s["max_lean"], s["max_brake_g"], s["max_lat_g"], s["front_over"], s["rear_over"]]


func _process(delta: float) -> void:
	if not visible:
		return
	var ride := showing_ride()
	_ride_graph.visible = ride
	_graph.visible = not ride
	_ride_wait -= delta
	if ride and _ride_wait <= 0.0:
		_ride_wait = 0.5
		_update_ride()
	_send_timer -= delta
	if _send_timer <= 0.0 and not _pending.is_empty():
		_send_timer = SEND_EVERY
		_flush()
	_update_graph()
