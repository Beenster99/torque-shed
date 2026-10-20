class_name BikeOrderPanel
extends Control
## A bike's card, opened with {order_bike} while looking at it (see BikeCopy): the bike turning on
## a turntable, every part on its build with what each costs you at the parts computer, the total
## and when it'll come, a slider for the quality to order it at (worn used parts up to new, see
## BikeCopy.quality_text), and two buttons: "Order one of these" (paid from your own money) and
## "Copy its blueprint". Both go through the host.

signal closed

const COPY_TIP := "Keeps it as a blueprint ({menu}, Blueprints): its parts, their colours, its paint and fit, to build from or order the usual way"

var src := {}
var title_text := ""
var plan := {}
var _box: VBoxContainer
var _preview: PartPreview
var _list: VBoxContainer
var _head: Label
var _sub: Label
var _sums: Label
var _status: Label
var _order: Button
var _copy: Button
var _quality: HSlider
var _quality_text: Label
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("bike_order_panel")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	_head = UITheme.title("ORDER ONE OF THESE", 26)
	_box.add_child(_head)
	_sub = UITheme.label("", 16, Color(1, 1, 1, 0.75))
	_box.add_child(_sub)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	_box.add_child(cols)
	_preview = PartPreview.new()
	_preview.custom_minimum_size = Vector2(360, 300)
	cols.add_child(_preview)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(UITheme.label("THE PARTS", 15, UITheme.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	scroll.add_child(_list)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	_box.add_child(qrow)
	var ends := [UITheme.label("QUALITY", 15, UITheme.ACCENT), UITheme.label("Worn", 14, Color(1, 1, 1, 0.6)), UITheme.label("New", 14, Color(1, 1, 1, 0.6))]
	for l: Label in ends:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(ends[0])
	qrow.add_child(ends[1])
	_quality = HSlider.new()
	_quality.min_value = 0.0
	_quality.max_value = 1.0
	_quality.step = BikeCopy.QUALITY_STEP
	_quality.value = 1.0
	_quality.custom_minimum_size = Vector2(200, 24)
	_quality.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quality.value_changed.connect(func(_v): _refresh())
	qrow.add_child(_quality)
	qrow.add_child(ends[2])
	_quality_text = UITheme.label("", 15)
	_quality_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_text.custom_minimum_size.x = 200.0
	_quality_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quality_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(_quality_text)
	_sums = UITheme.label("", 16)
	_sums.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_sums)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_order = Button.new()
	_order.text = "Order one of these"
	_order.pressed.connect(_press_order)
	row.add_child(_order)
	_copy = Button.new()
	_copy.text = "Copy its blueprint"
	_copy.pressed.connect(_press_copy)
	_copy.tooltip_text = COPY_TIP
	row.add_child(_copy)
	row.add_child(ContractPanel.button("Close ({back})", close_dialog))
	_status = UITheme.label("", 15, Color(1, 0.5, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	Shed.changed.connect(func(): if visible: _refresh())
	Progress.changed.connect(func(): if visible: _refresh())


## Opens the card for the bike at `src` (as BikeCopy takes it), called `bike_title`. The build
## is read now, so a rider who goes on their way leaves it as it was.
func open_bike(bike_src: Dictionary, bike_title: String) -> void:
	src = bike_src.duplicate(true)
	title_text = bike_title
	plan = BikeCopy.plan_of(src)
	_sig = ""
	_status.text = ""
	visible = true
	if plan.is_empty():
		close_dialog()
		return
	# A bike that isn't the shed's goes on as a build: what's on it doesn't change while it's open.
	if not src.has("bike"):
		src = {"build": {"name": str(plan["name"]), "parts": plan["parts"], "colors": plan.get("colors", {}), "paint": plan["paint"]}}
	_refresh()
	var cond := {}
	for slot in plan.get("colors", {}):
		cond[slot] = {"color": plan["colors"][slot]["color"]}
	_preview.show_bike("%s|%s" % [title_text, str(plan["parts"].hash())], plan["parts"], plan["paint"], cond)


func close_dialog() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	if src.has("bike"):
		var now := BikeCopy.plan_of(src)
		if now.is_empty():
			close_dialog()   # gone: sold, or taken apart
			return
		plan = now
	var q := quality()
	var rows := BikeCopy.lines(plan, Shed.me(), q)
	var cost := BikeCopy.total(rows)
	var why := Shed.check(Shed.me(), {"a": "copy_order", "src": src, "paid": cost, "quality": q})
	if why == "" and Progress.money() < cost:
		why = "You have %s: %s short." % [TvChannels.money_text(Progress.money()), TvChannels.money_text(cost - Progress.money())]
	var copy_why := Shed.check(Shed.me(), {"a": "copy_blueprint", "src": src})
	var sig := "%s|%d|%d|%s|%s|%d|%.2f" % [str(plan["parts"].hash()), cost, Progress.money(), why, copy_why, Shed.on_order.size(), q]
	if sig == _sig:
		return
	_sig = sig
	_quality_text.text = BikeCopy.quality_text(q)
	_sub.text = "%s  ·  %s  ·  %d hp built new" % [str(plan["name"]), PartsDB.style_text(plan["parts"]),
		roundi(BikeBuild.new(plan["parts"], {}).hp())]
	for c in _list.get_children():
		c.queue_free()
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var slot := UITheme.label(PartsDB.slot_name(str(r["slot"])), 14, Color(1, 1, 1, 0.5))
		slot.custom_minimum_size.x = 150.0
		var n := UITheme.label(str(r["name"]), 14)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.custom_minimum_size.x = 160.0
		var p := UITheme.label(TvChannels.money_text(int(r["price"])), 14, Color(0.75, 0.95, 0.75))
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.custom_minimum_size.x = 70.0
		for l: Label in [slot, n, p]:
			# One line each: the long names are cut short rather than wrapped.
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.clip_text = true
			line.add_child(l)
		_list.add_child(line)
	var haggle := int(Progress.skill_rank(Shed.me(), "haggler"))
	var lines := ["Total: %s for %d parts%s, from your own money (you have %s)." % [TvChannels.money_text(cost), rows.size(),
		" (Haggler: %d%% off)" % roundi(Money.HAGGLE_BUY * haggle * 100.0) if haggle > 0 else "", TvChannels.money_text(Progress.money())],
		"Delivery: " + (BikeCopy.DELIVERY if BikeCopy.is_new(q) else BikeCopy.DELIVERY.replace("boxed", "laid out"))]
	if not Shed.on_order.is_empty():
		lines.append("%d part%s already waiting on order for room in the delivery area." % [Shed.on_order.size(), "" if Shed.on_order.size() == 1 else "s"])
	_sums.text = Controls.hint("\n".join(lines))
	_order.text = "Order one of these for %s" % TvChannels.money_text(cost)
	_order.disabled = why != ""
	_order.tooltip_text = Controls.hint(why)
	_copy.disabled = copy_why != ""
	_copy.tooltip_text = Controls.hint(copy_why if copy_why != "" else COPY_TIP)
	_status.text = Controls.hint(why if why != "" else copy_why)


## The quality the slider's at (0 worn .. 1 new).
func quality() -> float:
	return BikeCopy.quality_of(_quality.value)


## Moves the quality slider (tests).
func set_quality(q: float) -> void:
	_quality.value = q


func _press_order() -> void:
	var said := BikeCopy.order(src, quality())
	if said != "":
		_status.text = Controls.hint(said)
		return
	close_dialog()


func _press_copy() -> void:
	var said := BikeCopy.copy_blueprint(src)
	if said != "":
		_status.text = Controls.hint(said)
		return
	close_dialog()


## Presses the button whose text starts with `text` (for tests).
func press(text: String) -> void:
	for b in [_order, _copy]:
		if (b as Button).text.begins_with(text) and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return


## Everything the card says now (tests).
func text() -> String:
	var out := []
	for l in _box.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			out.append((l as Label).text)
	return "\n".join(out)
