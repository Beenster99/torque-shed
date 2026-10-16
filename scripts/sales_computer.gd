class_name SalesComputer
extends Control
## The Sales page on the office PC upstairs in the sales office (F at its big screen). Four tabs:
##   Showroom       the four display stands: each bike's costs (bought for, parts, labour), its
##                  worth (parts and condition, complete and ready to ride), how unusual it is,
##                  a recommended price for a target margin and why, and its asking price
##                  (put it up for sale, change it, take it off, or sell it to the trade now).
##   Offers         online buyers' offers: accept, turn down or counter-offer, with the profit
##                  and margin of each figure.
##   Part exchange  a buyer who rode in on their own bike: its model, parts, condition,
##                  mileage, retail and trade value, what they want for it, and the deal.
##   Deals          the last bikes sold and what each made.
## Everything goes through the Shed (Sales.check/apply on the host), so the whole crew sees it.

signal closed

const TABS: Array[String] = ["Showroom", "Offers", "Part exchange", "Deals"]
const DIM := Color(1, 1, 1, 0.55)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)

var stand := 0                 # the stand picked on the Showroom tab
var _tabs: TabContainer
var _pages := {}               # tab name -> VBoxContainer
var _money: Label
var _status: Label
var _sig := ""
var _ask_edit := {}            # bike id -> asking price typed in, kept over refreshes
var _margin_pick := {}         # bike id -> target margin picked
var _counter_edit := {}        # offer id -> counter-offer typed in
var _px_edit := {}             # part-exchange id -> allowance typed in
var _focus_px := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
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
	head.add_child(UITheme.title("SALES"))
	_money = UITheme.label("", 18, GOOD)
	head.add_child(_money)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_computer)
	head.add_child(close)
	root.add_child(head)
	root.add_child(UITheme.label("Stand a bike on a display stand in the showroom (ride it or wheel it on), price it here, "
		+ "and deal with the buyers it brings in.", 15, DIM))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	for t in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = t
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		_tabs.add_child(scroll)
		_pages[t] = list
	_tabs.tab_changed.connect(func(_i): _sig = ""; refresh())
	_status = UITheme.label("", 15, Color(1, 1, 1, 0.75))
	root.add_child(_status)
	Shed.feedback.connect(func(text, _ok): if visible: _status.text = text)
	Shed.changed.connect(func(): if visible: refresh())


## Opens the page: on the Offers tab when an offer or part-exchange is waiting, else the showroom.
func open(tab := "") -> void:
	visible = true
	_status.text = ""
	if tab == "":
		tab = "Showroom"
		if not Sales.px().is_empty():
			tab = "Part exchange"
		elif Sales.offers().values().any(func(o): return str(o["state"]) == "open"):
			tab = "Offers"
	_tabs.current_tab = maxi(0, TABS.find(tab))
	_sig = ""
	refresh()
	_focus_first.call_deferred()


## Opens it on a part-exchange buyer (talking to them in the showroom).
func open_px(px_id: int) -> void:
	_focus_px = px_id
	open("Part exchange")


func close_computer() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		close_computer()
	elif event is InputEventJoypadButton and (event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev")):
		var step := 1 if event.is_action_pressed("tool_next") else -1
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		_focus_first.call_deferred()
	else:
		return
	get_viewport().set_input_as_handled()


func _focus_first() -> void:
	var page: Node = _pages[TABS[_tabs.current_tab]]
	var stack: Array = [page]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is BaseButton and n.is_inside_tree() and (n as Control).is_visible_in_tree() and not (n as BaseButton).disabled:
			(n as Control).grab_focus()
			return
		stack.append_array(n.get_children())


func current_tab() -> String:
	return TABS[_tabs.current_tab]


## What the page shows depends on: rebuilt only when this changes, so typing isn't lost.
func _signature() -> String:
	var stands := []
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		stands.append(Sales.bike_on_stand(i))
	var s := Sales._st()
	return var_to_str([current_tab(), stand, stands, s["listings"], s["offers"], s["px"], (s["deals"] as Array).size(),
		(s["news"] as Array).size()])


func refresh() -> void:
	_money.text = "Business account %s" % Sales.money(Shed.garage_money)
	_tabs.set_tab_title(1, "Offers (%d)" % Sales.offers().size() if not Sales.offers().is_empty() else "Offers")
	_tabs.set_tab_title(2, "Part exchange (%d)" % Sales.px().size() if not Sales.px().is_empty() else "Part exchange")
	var sig := _signature()
	if sig == _sig:
		return
	_sig = sig
	var page: VBoxContainer = _pages[current_tab()]
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	match current_tab():
		"Showroom":
			_build_showroom(page)
		"Offers":
			_build_offers(page)
		"Part exchange":
			_build_px(page)
		"Deals":
			_build_deals(page)


# ---------------------------------------------------------------------------- helpers

func _row(parent: Container, label: String, value: String, color := Color.WHITE, size := 17) -> void:
	var h := HBoxContainer.new()
	var l := UITheme.label(label, size, DIM)
	l.custom_minimum_size = Vector2(300, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var v := UITheme.label(value, size, color)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	parent.add_child(h)


func _button(parent: Container, text: String, call: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(call)
	parent.add_child(b)
	return b


func _money_box(value: int, changed: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 10000000
	sb.step = 10
	sb.rounded = true
	sb.prefix = TvChannels.CURRENCY
	sb.custom_minimum_size = Vector2(170, 0)
	sb.select_all_on_focus = true
	sb.value = value
	sb.value_changed.connect(func(v): changed.call(int(v)))
	return sb


func _card(parent: Container) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


## The bike's paint, panel by panel (see BikePaintInfo): a swatch of each panel's colour, its
## name, and its paint, finish, coats, lacquer, how the job came out and any stripe.
func _paint_card(parent: Container, bike: int) -> void:
	var card := _card(parent)
	card.add_child(UITheme.label("PAINT, PANEL BY PANEL", 14, UITheme.ACCENT))
	var list := BikePaintInfo.panels(bike)
	if list.is_empty():
		card.add_child(UITheme.label("No painted panels fitted.", 16, DIM))
		return
	for e in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = e["color"] if e["color"] is Color else Color.WHITE
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(swatch)
		var l := UITheme.label(str(e["name"]), 16, DIM)
		l.custom_minimum_size = Vector2(170, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.tooltip_text = str(e["part"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
		var v := UITheme.label(BikePaintInfo.line(e), 16, Color.WHITE)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(v)
		card.add_child(h)


static func _margin_color(amount: int, sunk: int) -> Color:
	return GOOD if amount >= sunk else BAD


# ---------------------------------------------------------------------------- showroom

func _build_showroom(page: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	page.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(UITheme.label("DISPLAY STANDS", 14, UITheme.ACCENT))
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		var b := Sales.bike_on_stand(i)
		var text := "Stand %d: free" % (i + 1)
		if b != 0:
			var ask := int(Sales.listings().get(b, {}).get("ask", 0))
			text = "Stand %d: %s\n%s" % [i + 1, str(Shed.bikes[b]["name"]).left(20), Sales.money(ask) if ask > 0 else "not for sale yet"]
		var btn := Button.new()
		btn.text = text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = i == stand
		btn.custom_minimum_size = Vector2(320, 64)
		btn.pressed.connect(func(): stand = i; _sig = ""; refresh())
		left.add_child(btn)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var bike := Sales.bike_on_stand(stand)
	if bike == 0:
		right.add_child(UITheme.title("Stand %d is free" % (stand + 1), 24, Color.WHITE))
		right.add_child(UITheme.label("Ride a bike into the showroom through the front doors, or wheel it in (hold F on it), "
			+ "and stop or let go of it on a display stand. Then price it here.", 17, DIM))
		return
	_build_bike(right, bike)


func _build_bike(right: VBoxContainer, bike: int) -> void:
	var listed: Dictionary = Sales.listings().get(bike, {})
	var margin := float(_margin_pick.get(bike, listed.get("margin", Sales.DEFAULT_MARGIN)))
	var ap := Sales.appraise(bike, margin)
	right.add_child(UITheme.title(str(Shed.bikes[bike]["name"]), 26, Color.WHITE))
	if Sales.is_customer_bike(bike):
		right.add_child(UITheme.label("A customer's bike, in for a job: it isn't the shed's to sell.", 17, BAD))
		return
	var state := "Complete and ready to ride" if ap["rideable"] else ("Complete, but no petrol and oil in it" if ap["complete"]
		else "Not finished: parts missing or loose")
	right.add_child(UITheme.label("%s  ·  condition %d%%" % [state, roundi(float(ap["condition"]) * 100.0)], 16, DIM))
	right.add_child(UITheme.label("Style: %s" % PartsDB.style_text(Contracts.current_parts(bike)), 16, DIM))
	_paint_card(right, bike)
	var cost := _card(right)
	cost.add_child(UITheme.label("WHAT IT'S COST", 14, UITheme.ACCENT))
	_row(cost, "Bought for" + ("" if ap["bought_known"] else " (about)"), Sales.money(int(ap["bought"])))
	_row(cost, "Parts fitted", Sales.money(int(ap["parts"])))
	_row(cost, "Labour (the crew's wages on it)", Sales.money(int(ap["labour"])))
	_row(cost, "Money sunk in", Sales.money(int(ap["sunk"])), UITheme.ACCENT, 19)
	var value := _card(right)
	value.add_child(UITheme.label("WHAT IT'S WORTH", 14, UITheme.ACCENT))
	_row(value, "Its parts as they are", Sales.money(int(ap["worth"])))
	_row(value, "Complete, ready to ride", Sales.money(int(ap["retail"])))
	var why: Array = ap["unique_why"]
	_row(value, "Uniqueness %d%% (+%d%%)" % [roundi(float(ap["unique"]) * 100.0), roundi(float(ap["premium"]) * 100.0)],
		", ".join(why) if not why.is_empty() else "a common bike, as it came")
	_row(value, "Fair price to a private buyer", Sales.money(int(ap["fair"])), UITheme.ACCENT, 19)
	_row(value, "The trade pays now", Sales.money(int(ap["trade"])), DIM)
	var price := _card(right)
	price.add_child(UITheme.label("PRICING IT", 14, UITheme.ACCENT))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mrow.add_child(UITheme.label("Target margin", 17, DIM))
	for m in Sales.MARGINS:
		var mb := Button.new()
		mb.text = "%d%%" % roundi(m * 100.0)
		mb.toggle_mode = true
		mb.button_pressed = is_equal_approx(m, margin)
		mb.pressed.connect(func(): _margin_pick[bike] = m; _sig = ""; refresh())
		mrow.add_child(mb)
	price.add_child(mrow)
	_row(price, "At that margin you'd want", Sales.money(int(ap["target"])))
	_row(price, "Recommended", Sales.money(int(ap["recommended"])), GOOD, 20)
	price.add_child(UITheme.label(str(ap["why"]), 15, Color(1, 1, 1, 0.75)))
	var ask := int(_ask_edit.get(bike, listed.get("ask", ap["recommended"])))
	var preview := UITheme.label("", 16)
	var interest := UITheme.label("", 15, DIM)
	var show := func(v: int) -> void:
		preview.text = "At %s: %s" % [Sales.money(v), Sales.margin_text(v, int(ap["sunk"]))]
		preview.add_theme_color_override("font_color", _margin_color(v, int(ap["sunk"])))
		interest.text = "Buyers: " + Sales.interest_text(Sales.interest(bike, v))
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 10)
	arow.add_child(UITheme.label("Asking price", 17, DIM))
	var box := _money_box(ask, func(v: int):
		_ask_edit[bike] = v
		show.call(v))
	arow.add_child(box)
	_button(arow, "Use recommended", func():
		_ask_edit[bike] = int(ap["recommended"])
		box.value = int(ap["recommended"]))
	_button(arow, "Change the price" if not listed.is_empty() else "Put it up for sale", func():
		Shed.request({"a": "sale_list", "bike": bike, "ask": int(box.value), "margin": margin})
		_ask_edit.erase(bike))
	price.add_child(arow)
	price.add_child(preview)
	price.add_child(interest)
	show.call(ask)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	if not listed.is_empty():
		var since := Sales.clock() - float(listed.get("since", Sales.clock()))
		price.add_child(UITheme.label("For sale at %s for %s." % [Sales.money(int(listed["ask"])), _hours_text(since)], 16, GOOD))
		_button(brow, "Take it off sale", func(): Shed.request({"a": "sale_unlist", "bike": bike}))
	var trade := Money.bike_sale(bike, Shed.me())
	_button(brow, "Sell to the trade now: %s" % Sales.money(trade), func(): Shed.request({"a": "money_sell_bike", "bike": bike}),
		trade <= 0)
	price.add_child(brow)


static func _hours_text(h: float) -> String:
	if h < 1.0:
		return "under an hour"
	if h < 48.0:
		return "%d hour%s" % [int(h), "" if int(h) == 1 else "s"]
	return "%d days" % int(h / 24.0)


# ---------------------------------------------------------------------------- offers

func _build_offers(page: VBoxContainer) -> void:
	if Sales.offers().is_empty():
		page.add_child(UITheme.title("No offers in", 24, Color.WHITE))
		page.add_child(UITheme.label("Buyers find the bikes that are up for sale on the showroom stands. The fairer the asking price, "
			+ "the more of them; a till rings here and in the shed when one makes an offer.", 17, DIM))
	var ids: Array = Sales.offers().keys()
	ids.sort()
	for id in ids:
		_build_offer(page, int(id))
	_build_news(page)


func _build_offer(page: VBoxContainer, id: int) -> void:
	var o: Dictionary = Sales.offers()[id]
	var bike := int(o["bike"])
	var ap := Sales.appraise(bike)
	var sunk := int(ap.get("sunk", 0))
	var card := _card(page)
	var stand_no := Sales.stand_of(bike)
	card.add_child(UITheme.title("%s, for %s" % [o["buyer"], o["bike_name"]], 22, Color.WHITE))
	card.add_child(UITheme.label("Asking %s%s  ·  fair price %s  ·  money sunk in %s" % [Sales.money(int(o["ask"])),
		(" on stand %d" % (stand_no + 1)) if stand_no >= 0 else " (off its stand)", Sales.money(int(ap.get("fair", 0))), Sales.money(sunk)], 15, DIM))
	card.add_child(UITheme.label("\"%s\"" % str(o.get("said", "")), 17, Color(1, 1, 1, 0.85)))
	var amt := int(o["amount"])
	var line := UITheme.label("Their offer %s: %s%s" % [Sales.money(amt), Sales.margin_text(amt, sunk),
		"  ·  final offer" if o.get("final", false) else ""], 19, _margin_color(amt, sunk))
	card.add_child(line)
	var hist: Array[String] = []
	for h in o.get("history", []):
		hist.append("%s %s" % ["They" if str(h.get("who", "")) == "buyer" else "You", Sales.money(int(h.get("amt", 0)))])
	if hist.size() > 1:
		card.add_child(UITheme.label("So far: " + ", ".join(hist), 15, DIM))
	if str(o["state"]) == "waiting":
		card.add_child(UITheme.label("You countered with %s (%s). Waiting for their answer..." % [Sales.money(int(o["counter"])),
			Sales.margin_text(int(o["counter"]), sunk)], 16, UITheme.ACCENT))
		return
	card.add_child(UITheme.label("They'll wait about %s for an answer." % _hours_text(float(o["expires"]) - Sales.clock()), 14, DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_button(row, "Accept %s" % Sales.money(amt), func(): Shed.request({"a": "sale_accept", "offer": id}))
	_button(row, "Turn it down", func(): Shed.request({"a": "sale_reject", "offer": id}))
	var counter := int(_counter_edit.get(id, Money._nice((amt + int(o["ask"])) * 0.5)))
	var preview := UITheme.label("", 15)
	var show := func(v: int) -> void:
		preview.text = "Counter at %s: %s" % [Sales.money(v), Sales.margin_text(v, sunk)]
		preview.add_theme_color_override("font_color", _margin_color(v, sunk))
	var box := _money_box(counter, func(v: int):
		_counter_edit[id] = v
		show.call(v))
	row.add_child(box)
	_button(row, "Counter-offer", func(): Shed.request({"a": "sale_counter", "offer": id, "amount": int(box.value)}))
	card.add_child(row)
	card.add_child(preview)
	show.call(counter)


func _build_news(page: VBoxContainer) -> void:
	var news: Array = Sales._st().get("news", [])
	if news.is_empty():
		return
	page.add_child(UITheme.label("LATELY", 14, UITheme.ACCENT))
	for n in news:
		page.add_child(UITheme.label(str(n.get("text", "")), 15, DIM))


# ---------------------------------------------------------------------------- part exchange

func _build_px(page: VBoxContainer) -> void:
	if Sales.px().is_empty():
		page.add_child(UITheme.title("Nobody waiting", 24, Color.WHITE))
		page.add_child(UITheme.label("Now and then a buyer rides up on their own bike, parks out front and comes in to the bike "
			+ "they're after, wanting to part-exchange. Talk to them (F) or deal with them here.", 17, DIM))
	for id in Sales.px():
		_build_one_px(page, int(id))


func _build_one_px(page: VBoxContainer, id: int) -> void:
	var p: Dictionary = Sales.px()[id]
	var target := int(p["target"])
	var listed: Dictionary = Sales.listings().get(target, {})
	var price := int(listed.get("ask", p.get("ask", 0)))
	var ap := Sales.appraise(target)
	var sunk := int(ap.get("sunk", 0))
	var card := _card(page)
	card.add_child(UITheme.title("%s, after %s (asking %s)" % [p["name"], p["target_name"], Sales.money(price)], 22, Color.WHITE))
	card.add_child(UITheme.label("\"%s\"" % str(p.get("said", "")), 17, Color(1, 1, 1, 0.85)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	card.add_child(cols)
	var theirs := VBoxContainer.new()
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(theirs)
	theirs.add_child(UITheme.label("THEIR BIKE", 14, UITheme.ACCENT))
	var cond: Dictionary = p.get("cond", {})
	var wear := 0.0
	var rust := 0.0
	for slot in cond:
		wear += float(cond[slot].get("wear", 0.0))
		rust += float(cond[slot].get("rust", 0.0))
	var n := maxf(1.0, float(cond.size()))
	_row(theirs, "Model", "%s, %s" % [str(p["model"]), Shed.PAINT_NAMES[int(p.get("paint", 0)) % Shed.PAINT_NAMES.size()]])
	_row(theirs, "Mileage", "%s km" % _thousands(int(p.get("km", 0))))
	_row(theirs, "Condition", "%d%%" % roundi(float(p.get("condition", 0.0)) * 100.0))
	_row(theirs, "Wear / rust", "%d%% / %d%% on average" % [roundi(wear / n * 100.0), roundi(rust / n * 100.0)])
	_row(theirs, "Estimated retail value", Sales.money(int(p["retail"])), Color.WHITE, 18)
	_row(theirs, "Estimated trade value", Sales.money(int(p["trade"])), DIM, 18)
	var parts := VBoxContainer.new()
	parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(parts)
	parts.add_child(UITheme.label("WHAT'S ON IT", 14, UITheme.ACCENT))
	for line in Sales.px_part_lines(p):
		parts.add_child(UITheme.label(line, 15, DIM))
	var want := int(p["want"])
	card.add_child(UITheme.label("They want %s for it%s, so they'd pay %s on top for %s." % [Sales.money(want),
		" (their last word)" if p.get("final", false) else "", Sales.money(price - want), p["target_name"]], 18, UITheme.ACCENT))
	var preview := UITheme.label("", 16)
	var show := func(v: int) -> void:
		var cash := price - v
		var deal := cash + int(p["trade"])
		preview.text = "Allowing %s: %s cash in; with their bike at trade value the deal is worth %s for a bike that cost %s: %s" % [
			Sales.money(v), Sales.money(cash), Sales.money(deal), Sales.money(sunk), Sales.margin_text(deal, sunk)]
		preview.add_theme_color_override("font_color", _margin_color(deal, sunk))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_button(row, "Accept their %s" % Sales.money(want), func(): Shed.request({"a": "sale_px_accept", "px": id}))
	var allow := int(_px_edit.get(id, mini(int(p["trade"]), want - 10)))
	var box := _money_box(allow, func(v: int):
		_px_edit[id] = v
		show.call(v))
	row.add_child(UITheme.label("Offer", 17, DIM))
	row.add_child(box)
	_button(row, "Offer this for it", func(): Shed.request({"a": "sale_px_offer", "px": id, "amount": int(box.value)}))
	_button(row, "Send them away", func(): Shed.request({"a": "sale_px_decline", "px": id}))
	card.add_child(row)
	card.add_child(preview)
	show.call(allow)
	card.add_child(UITheme.label("They'll wait about %s more." % _hours_text(float(p["leave_at"]) - Sales.clock()), 14, DIM))
	if id == _focus_px:
		_focus_px = 0
		(func():
			if is_instance_valid(box) and box.is_inside_tree():
				box.grab_focus()).call_deferred()


static func _thousands(v: int) -> String:
	return TvChannels.money_text(v).trim_prefix(TvChannels.CURRENCY)


# ---------------------------------------------------------------------------- deals

func _build_deals(page: VBoxContainer) -> void:
	var deals: Array = Sales._st().get("deals", [])
	page.add_child(UITheme.label("Showroom takings %s" % Sales.money(int(Sales._st().get("earned", 0))), 18, GOOD))
	if deals.is_empty():
		page.add_child(UITheme.label("Nothing sold yet.", 17, DIM))
	for d in deals:
		var kind := str(d.get("kind", ""))
		var how := {"online": "online buyer", "px": "part-exchange", "trade": "the trade"}.get(kind, kind) as String
		var extra := (" with %s off for their bike" % Sales.money(int(d.get("allowance", 0)))) if kind == "px" else ""
		var profit := int(d.get("profit", 0))
		page.add_child(UITheme.label("Day %d  ·  %s to %s (%s) for %s%s  ·  %s" % [int(d.get("day", 1)), str(d.get("bike", "")),
			str(d.get("buyer", "")), how, Sales.money(int(d.get("price", 0))), extra,
			Sales.margin_text(int(d.get("price", 0)), int(d.get("sunk", 0)))], 16, GOOD if profit >= 0 else BAD))
	_build_news(page)
