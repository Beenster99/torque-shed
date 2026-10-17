class_name PaintBench
extends Control
## The mixing bench, stepped up to (F at the bench in the paint mixing bay; see PaintBay and
## PaintMix). The view drops to the scale and the card down the right side runs the bench:
##   Mix       put a tin of base on the scale; pick a tint off the rack, then hold the left mouse
##             in the view and drag down to tip the bottle (the further, the faster it pours; it
##             wobbles less as you level up and on the stainless bench); hold the right mouse and
##             stir round and round until it's even; read the scale (Tare zeroes it, to weigh
##             the next tint on its own); see the colour live, and
##             how close it is to the target; add base to fix an over-pour; spray a test card;
##             name it and save it (onto the tin shelf and the swatch wall).
##   Recipes   recipe cards: the manufacturer colours, the swatch wall's own and a pasted code. A
##             card on the bench shows each tint's weight to pour and sets its colour as the
##             target; "match by eye" sets just the colour. With the automatic shaker a card
##             can be remixed in one go.
##   Supplies  bases and tints, bought with the garage's money.
## Pours and stirs go to the host every moment or so; until it's heard of them they're shown
## from here (PaintBayRoom.live), so the scale reads straight away.

signal closed

const SEND_EVERY := 0.15
const TILT_DRAG := 260.0       # pixels of drag for the bottle to go straight down
const PANEL_W := 470

var page := "mix"
var tint := ""                 # the tint picked off the rack
var _box: VBoxContainer
var _pad: Control
var _sig := ""
var _seq := 0
var _pending: Array = []       # [{seq, g, t}] pours sent the host hasn't counted yet
var _pour_g := 0.0             # poured since the last send
var _stir_g := 0.0             # stirred since the last send
var _send_t := 0.0
var _tilt := 0.0
var _pouring := false
var _press_y := 0.0
var _stirring := false
var _stir_seen := 0.0
var _last_dir := Vector2.ZERO
var _wobble_t := 0.0
var _opened_at := 0.0
var _name_edit: LineEdit
var _code_edit: LineEdit
var _scale_l: Label
var _tare_l: Label
var _match_l: Label
var _mix_l: Label
var _stir_bar: ProgressBar
var _mix_rect: ColorRect
var _target_rect: ColorRect
var _card_l: Label
var _hint: Label
var _typed_name := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("paint_bench")
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The view of the bench: pour and stir here.
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.offset_right = -PANEL_W
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_pad_input)
	add_child(_pad)
	_hint = UITheme.label("", 16, Color(1, 1, 1, 0.85))
	# Across the top of the bench view (a label left unsized would wrap a letter a line).
	_hint.anchor_right = 1.0
	_hint.offset_left = 24
	_hint.offset_right = -24
	_hint.offset_top = 20
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_pad.add_child(_hint)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	Shed.changed.connect(func(): if visible: _refresh())
	Progress.changed.connect(func(): if visible: _refresh())


## Steps up to the bench: the view goes to the scale. `where` is "bay" (the mixing bay's bench)
## or "shop" (the compact one beside it); left out, it's the one nearer the local player.
func open(where := "") -> void:
	var me := Shed.me()
	if where == "":
		var w := get_tree().get_first_node_in_group("local_walker") as Node3D if is_inside_tree() else null
		where = PaintBay.station_near(w.global_position) if w else "bay"
	if PaintBay.at_bench() != 0 and PaintBay.at_bench() != me:
		Shed.feedback.emit("%s is at the mixing bench." % Shed.crew.get(PaintBay.at_bench(), {}).get("name", "Someone"), false)
		return
	_seq = maxi(_seq, int(PaintBay.bench()["seq"].get(me, 0)))
	Shed.request({"a": "paint_bench", "on": true, "seq": _seq, "at": where})
	visible = true
	page = "mix"
	_sig = ""
	_pending.clear()
	_pour_g = 0.0
	_stir_g = 0.0
	_opened_at = Time.get_ticks_msec() / 1000.0
	var room := _room()
	var cam: Camera3D = (room.shop_camera if where == "shop" else room.bench_camera) if room else null
	if cam:
		cam.current = true
	_refresh()


func close_dialog() -> void:
	if not visible:
		return
	_flush()
	_pouring = false
	_stirring = false
	PaintBayRoom.live = {}
	Shed.request({"a": "paint_bench", "on": false})
	visible = false
	closed.emit()


func _room() -> PaintBayRoom:
	return get_tree().get_first_node_in_group("paint_bay_room") as PaintBayRoom if is_inside_tree() else null


## Presses the button labelled `text` (for tests).
func press(text: String) -> void:
	for b in _box.find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not b.is_queued_for_deletion():
			(b as Button).pressed.emit()
			return


## The buttons showing now (tests).
func buttons() -> Array[String]:
	var out: Array[String] = []
	for b in _box.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion():
			out.append((b as Button).text)
	return out


## Everything the card says now (tests).
func text() -> String:
	var lines := []
	for l in _box.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			lines.append((l as Label).text)
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("interact"):
		# F again steps back from the bench.
		get_viewport().set_input_as_handled()
		close_dialog()


# ---------------------------------------------------------------------------- pouring and stirring

func _pad_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				start_pour(mb.position.y)
			else:
				stop_pour()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_stirring = mb.pressed
			_last_dir = Vector2.ZERO
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pouring:
			set_tilt((mm.position.y - _press_y) / TILT_DRAG)
		if _stirring:
			stir_motion(mm.relative)


## The left mouse goes down in the view: the picked bottle comes up over the tin.
func start_pour(y: float) -> void:
	if tint == "" or PaintBay.bench_tin().is_empty():
		Shed.feedback.emit("Put a tin on the scale and pick a tint off the rack first." if tint == "" else "Put a tin on the scale first.", false)
		return
	_pouring = true
	_press_y = y
	_tilt = 0.0


## The left mouse comes up: the bottle goes back on the rack, for everyone watching too.
func stop_pour() -> void:
	if not _pouring:
		return
	_pouring = false
	_flush()
	Shed.request({"a": "paint_pour_stop"})


## How far the bottle's tipped, 0 upright .. 1 straight down (tests set it directly).
func set_tilt(t: float) -> void:
	_tilt = clampf(t, 0.0, 1.0)


## The mouse moving with the right button held: each full circle stirs the tin a bit more.
func stir_motion(rel: Vector2) -> void:
	if rel.length() < 1.5:
		return
	var dir := rel.normalized()
	if _last_dir != Vector2.ZERO:
		var turn := absf(_last_dir.angle_to(dir))
		stir_turns(turn / TAU)
	_last_dir = dir
	_stir_seen = 0.25


## `turns` turns of the stick (tests call it directly).
func stir_turns(turns: float) -> void:
	if PaintBay.bench_tin().is_empty() or turns <= 0.0:
		return
	_stir_g += turns * PaintMix.stir_per_turn(Progress.level())
	_stir_seen = 0.25


func _process(delta: float) -> void:
	if not visible:
		return
	var me := Shed.me()
	# Someone else got there first, or the bench went (the session ended).
	if PaintBay.at_bench() != me and Time.get_ticks_msec() / 1000.0 - _opened_at > 1.5:
		Shed.feedback.emit("You've stepped away from the mixing bench.", false)
		close_dialog()
		return
	var tin := PaintBay.bench_tin()
	if tin.is_empty():
		_pouring = false
	if not _pouring:
		_tilt = move_toward(_tilt, 0.0, delta * 3.0)
	if _pouring and tint != "":
		# A steady pour follows the tilt; a wobbly one lurches about it.
		_wobble_t += delta
		var wobble := PaintMix.pour_wobble(Progress.level(), PaintBay.kit("stainless"))
		var w := 1.0 + wobble * (sin(_wobble_t * 7.3) * 0.6 + sin(_wobble_t * 17.9 + 1.3) * 0.4)
		var room := PaintMix.MAX_TIN_GRAMS - PaintMix.total_grams(tin) - _pending_g() - _pour_g
		var left := PaintBay.stock_of(tint) - _pending_g() - _pour_g
		_pour_g += clampf(PaintMix.pour_rate(_tilt) * maxf(w, 0.0) * delta, 0.0, maxf(0.0, minf(room, left)))
	_stir_seen = maxf(0.0, _stir_seen - delta)
	_send_t += delta
	if _send_t >= SEND_EVERY:
		_send_t = 0.0
		_flush()
	# Pours the host has counted (or that it never will) drop off.
	var acked := int(PaintBay.bench()["seq"].get(me, 0))
	var now := Time.get_ticks_msec() / 1000.0
	_pending = _pending.filter(func(p): return int(p["seq"]) > acked and now - float(p["t"]) < 2.0)
	PaintBayRoom.live = {"g": _pending_g() + _pour_g, "code": tint, "tilt": _tilt if _pouring else 0.0, "stirring": _stir_seen > 0.0}
	_update_live()


func _pending_g() -> float:
	var g := 0.0
	for p in _pending:
		g += float(p["g"])
	return g


## Sends what's been poured and stirred since the last time.
func _flush() -> void:
	var me := Shed.me()
	if _pour_g > 0.0005 and tint != "":
		_seq += 1
		var g := _pour_g
		_pour_g = 0.0
		_pending.append({"seq": _seq, "g": g, "t": Time.get_ticks_msec() / 1000.0})
		Shed.request({"a": "paint_pour", "tint": tint, "g": g, "tilt": _tilt, "seq": _seq})
	if _stir_g > 0.0005:
		var s := minf(_stir_g, 0.5)
		_stir_g = 0.0
		Shed.request({"a": "paint_stir", "amount": s})
	if PaintBay.at_bench() != me:
		_pending.clear()


## The tin as it is with what's been poured here and not yet counted.
func shown_tin() -> Dictionary:
	var tin := PaintBay.bench_tin()
	if tin.is_empty():
		return {}
	var t := tin.duplicate(true)
	var extra := _pending_g() + _pour_g
	if extra > 0.0 and tint != "":
		t["tints"][tint] = float(t["tints"].get(tint, 0.0)) + extra
	t["stir"] = clampf(float(t.get("stir", 1.0)) + _stir_g, 0.0, 1.0)
	return t


## The scale's reading, the live colour, the stir and the match: every frame.
func _update_live() -> void:
	var t := shown_tin()
	var step := PaintMix.scale_step(Progress.level(), PaintBay.kit("scale"))
	if _hint:
		if t.is_empty():
			_hint.text = "Put a tin of base on the scale (right)."
		elif tint == "":
			_hint.text = "Pick a tint off the rack (right), then hold left mouse here and drag down to tip it."
		else:
			_hint.text = "%s: hold left mouse and drag down to pour (%s)  ·  hold right mouse and circle to stir" % [
				PaintBay.item_name(tint), "pouring %.1f g/s" % PaintMix.pour_rate(_tilt) if _pouring and PaintMix.pour_rate(_tilt) > 0.0
				else ("tip it further" if _pouring else "not pouring")]
	if t.is_empty() or _scale_l == null or not is_instance_valid(_scale_l):
		return
	var s := PaintMix.spec(t)
	var total := PaintMix.total_grams(t)
	_scale_l.text = "SCALE  %s" % PaintMix.read_scale(PaintBay.net_grams(t, total), step)
	if _tare_l and is_instance_valid(_tare_l):
		_tare_l.text = "tared  ·  the tin's %s in all" % PaintMix.read_scale(total, step) if PaintBay.tared(t) else "the whole tin"
	_mix_l.text = "%s  ·  %s" % [PaintMix.code_of(t).left(40), PaintMix.effect_name(str(s["effect"]))]
	_mix_rect.color = s["color"]
	_stir_bar.value = float(t.get("stir", 1.0)) * 100.0
	var target: Dictionary = PaintBay.bench().get("target", {})
	if target.get("color") is Color:
		var m := PaintMix.match_of(s["color"], target["color"], str(s["effect"]), str(target.get("effect", "")))
		_match_l.text = "Match to %s: %s" % [str(target.get("name", "target")), PaintMix.match_text(m)]
		_match_l.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if m >= PaintMix.GOOD_MATCH else Color(1.0, 0.8, 0.4))
		_target_rect.color = target["color"]
	else:
		_match_l.text = "No target: load a recipe card, or match by eye."
		_target_rect.color = Color(0.2, 0.2, 0.22)
	var card: Dictionary = PaintBay.bench().get("recipe", {})
	if _card_l and not card.is_empty():
		_card_l.text = _card_lines(card.get("tin", {}), t, step)


func _card_lines(want: Dictionary, have: Dictionary, step: float) -> String:
	var lines := []
	if str(want.get("base", "")) != str(have.get("base", "")):
		lines.append("Base: %s (this tin is %s!)" % [PaintBay.item_name(str(want.get("base", ""))), PaintBay.item_name(str(have.get("base", ""))).to_lower()])
	else:
		lines.append("Base: %s  ok" % PaintBay.item_name(str(want.get("base", ""))))
	var wt: Dictionary = want.get("tints", {})
	var ht: Dictionary = have.get("tints", {})
	for code in wt:
		var w := float(wt[code])
		var h := float(ht.get(code, 0.0))
		var mark := "ok" if absf(h - w) <= maxf(step, w * 0.02) else ("over" if h > w else "")
		lines.append("%s %s: %s of %s  %s" % [code, PaintBay.item_name(str(code)), PaintMix.read_scale(h, step), PaintMix.read_scale(w, step), mark])
	for code in ht:
		if not wt.has(code):
			lines.append("%s: %s (not on the card)" % [code, PaintMix.read_scale(float(ht[code]), step)])
	if absf(float(want.get("base_g", 1000.0)) - float(have.get("base_g", 1000.0))) > 0.5:
		lines.append("Base weight: %s of %s" % [PaintMix.read_scale(float(have.get("base_g", 1000.0)), 1.0), PaintMix.read_scale(float(want.get("base_g", 1000.0)), 1.0)])
	lines.append("Accuracy so far: %d%%" % roundi(PaintMix.recipe_accuracy(have, want) * 100.0))
	return "\n".join(lines)


# ---------------------------------------------------------------------------- the card

func _refresh() -> void:
	if not visible:
		return
	var tin := PaintBay.bench_tin()
	var b := PaintBay.bench()
	var sig := "%s|%s|%s|%s|%s|%s|%s|%d|%d|%s|%s" % [page, tint, str(tin.get("id", 0)), str(tin.get("base", "")), str(b.get("recipe", {}).get("code", "")),
		str(b.get("target", {}).get("name", "")), str(PaintBay.stock().keys().filter(func(c): return PaintBay.stock_of(str(c)) > 0.5)), Progress.level(), Shed.garage_money, str(Shed.upgrades.keys()),
		str(PaintBay.recipes().keys()) + str(PaintBay._st()["shaker"])]
	if sig == _sig:
		return
	_sig = sig
	if _name_edit and is_instance_valid(_name_edit):
		_typed_name = _name_edit.text
	for c in _box.get_children():
		c.queue_free()
	_scale_l = null
	_tare_l = null
	_box.add_child(UITheme.title("MIXING BENCH", 24))
	var lv := Progress.level()
	_box.add_child(UITheme.label("Level %d  ·  scale reads to %s  ·  garage money %s" % [lv, PaintMix.read_scale(PaintMix.scale_step(lv, PaintBay.kit("scale")),
		0.1).replace(".0 g", " g"), TvChannels.money_text(Shed.garage_money)], 14, UITheme.ACCENT))
	var tabs := HBoxContainer.new()
	for p in [["mix", "Mix"], ["recipes", "Recipe cards"], ["supplies", "Supplies"]]:
		var key: String = p[0]
		var tb := ContractPanel.button(("> %s" if page == key else "%s") % p[1], func():
			page = key
			_sig = ""
			_refresh())
		tabs.add_child(tb)
	tabs.add_child(ContractPanel.button("Done (Esc)", close_dialog))
	_box.add_child(tabs)
	match page:
		"mix":
			_fill_mix(tin)
		"recipes":
			_fill_recipes(tin)
		"supplies":
			_fill_supplies()
	_update_live()


func _fill_mix(tin: Dictionary) -> void:
	var me := Shed.me()
	if tin.is_empty():
		_box.add_child(UITheme.label("PUT A TIN ON THE SCALE: A LITRE OF BASE", 14, UITheme.ACCENT))
		for base in PaintMix.BASE_ORDER:
			var why := Shed.check(me, {"a": "paint_tin_new", "base": base})
			var bb := ContractPanel.button("%s  (%s in stock)" % [PaintBay.item_name(base), PaintBay.stock_text(base)], func():
				Shed.request({"a": "paint_tin_new", "base": base})
				tint = "")
			bb.disabled = why != ""
			bb.tooltip_text = why
			_box.add_child(bb)
		_box.add_child(_note("White, black or silver base for solid and metallic colours; clear base for candy (level 8); clear lacquer "
			+ "with flattener for satin (15%) or matt (40%). A tin from the shelf goes on the scale too: hold it and press F here."))
		var card: Dictionary = PaintBay.bench().get("recipe", {})
		if not card.is_empty():
			_box.add_child(UITheme.label("Recipe card on the bench: %s (%s base)" % [str(card.get("name", "")), PaintBay.item_name(str(card.get("tin", {}).get("base", "W"))).to_lower()], 15))
		return
	# The scale (with its tare button, to weigh the next tint from 0 g) and the colour.
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 10)
	var reading := VBoxContainer.new()
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 0)
	_scale_l = UITheme.label("", 26, Color(0.6, 1.0, 0.7))
	reading.add_child(_scale_l)
	_tare_l = UITheme.label("", 13, Color(1, 1, 1, 0.55))
	reading.add_child(_tare_l)
	scale_row.add_child(reading)
	var tare := _act("Tare: reset to 0 g", {"a": "paint_tare"})
	tare.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tare.tooltip_text = "Zero the scale with the tin on it, so the next tint or effect is weighed on its own."
	scale_row.add_child(tare)
	_box.add_child(scale_row)
	_mix_l = UITheme.label("", 14, Color(1, 1, 1, 0.75))
	_box.add_child(_mix_l)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	_mix_rect = ColorRect.new()
	_mix_rect.custom_minimum_size = Vector2(150, 56)
	swatches.add_child(_mix_rect)
	_target_rect = ColorRect.new()
	_target_rect.custom_minimum_size = Vector2(150, 56)
	swatches.add_child(_target_rect)
	var legend := UITheme.label("mix\ntarget", 13, Color(1, 1, 1, 0.55))
	legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	swatches.add_child(legend)
	_box.add_child(swatches)
	_match_l = UITheme.label("", 16)
	_box.add_child(_match_l)
	var stir_row := HBoxContainer.new()
	var stirred := UITheme.label("Stirred", 14)
	stirred.autowrap_mode = TextServer.AUTOWRAP_OFF
	stir_row.add_child(stirred)
	_stir_bar = ProgressBar.new()
	_stir_bar.custom_minimum_size = Vector2(300, 18)
	_stir_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stir_row.add_child(_stir_bar)
	_box.add_child(stir_row)
	var card: Dictionary = PaintBay.bench().get("recipe", {})
	if not card.is_empty():
		_box.add_child(UITheme.label("RECIPE CARD: %s" % str(card.get("name", "")).to_upper(), 14, UITheme.ACCENT))
		_card_l = UITheme.label("", 14)
		_box.add_child(_card_l)
	else:
		_card_l = null
	# The rack.
	_box.add_child(UITheme.label("THE TINT RACK: PICK ONE TO POUR", 14, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for code in PaintMix.TINT_ORDER:
		var c := str(code)
		if not PaintMix.on_rack(c, PaintBay.kit("effects")):
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		var chip := ColorRect.new()
		chip.color = PaintMix.TINTS[c]["color"]
		chip.custom_minimum_size = Vector2(12, 30)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var lock := PaintBay.locked(me, c)
		var why := lock if lock != "" else PaintMix.pour_problem(tin, c)
		if why == "" and PaintBay.stock_of(c) <= 0.001:
			why = "Empty: order more."
		var tb := Button.new()
		tb.toggle_mode = true
		tb.button_pressed = tint == c
		# Two lines, small enough that every name reads in full in half the card's width:
		# the name, then its code and how much is left.
		tb.text = "%s\n%s  ·  %s" % [str(PaintMix.TINTS[c]["name"]), c, PaintBay.stock_text(c) if lock == "" else lock.to_lower()]
		tb.add_theme_font_size_override("font_size", 14)
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.disabled = why != "" and tint != c
		tb.tooltip_text = why
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(func():
			_flush()
			tint = c
			_sig = ""
			_refresh())
		row.add_child(tb)
		grid.add_child(row)
	_box.add_child(grid)
	if not PaintBay.kit("effects"):
		_box.add_child(_note("Pearls, candies, flakes and chameleons go on the effects rack (a garage upgrade, at the parts computer)."))
	# What to do with the tin.
	var acts := HFlowContainer.new()
	acts.add_child(_act("Add %d g base" % roundi(PaintMix.ADD_BASE_G), {"a": "paint_add_base"}))
	acts.add_child(_act("Test card", {"a": "paint_test"}))
	acts.add_child(_act("Auto shaker (%ds)" % roundi(PaintBay.AUTO_SHAKE_TIME) if PaintBay.kit("shaker") else "Shaker (%ds)" % roundi(PaintBay.SHAKE_TIME),
		{"a": "paint_shake"}))
	acts.add_child(_act("Tip it away", {"a": "paint_tin_empty"}))
	_box.add_child(acts)
	_box.add_child(_note("Over-poured? Add base to bring it back: it takes more paint (and stirring) but gets the colour back."))
	var name_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name it (e.g. Midnight Blue)"
	_name_edit.max_length = 32
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_name := str(card.get("name", ""))
	_name_edit.text = _typed_name if _typed_name != "" else card_name
	name_row.add_child(_name_edit)
	var save := ContractPanel.button("Save tin", func():
		_flush()
		Shed.request({"a": "paint_tin_save", "name": _name_edit.text.strip_edges()})
		_typed_name = ""
		tint = "")
	name_row.add_child(save)
	_box.add_child(name_row)
	_box.add_child(_note("Saved tins go on the tin shelf (take one to the paint shop, right mouse fills the spray gun's cup) and the recipe on the swatch wall."))


func _act(label: String, action: Dictionary) -> Button:
	var why := Shed.check(Shed.me(), action)
	var b := ContractPanel.button(label, func():
		_flush()
		Shed.request(action))
	b.disabled = why != ""
	b.tooltip_text = why
	return b


func _note(t: String) -> Label:
	var l := UITheme.label(t, 13, Color(1, 1, 1, 0.55))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 70, 0)
	return l


func _fill_recipes(tin: Dictionary) -> void:
	var me := Shed.me()
	var card: Dictionary = PaintBay.bench().get("recipe", {})
	if not card.is_empty() or not PaintBay.bench().get("target", {}).is_empty():
		_box.add_child(ContractPanel.button("Put the card and target away", func(): Shed.request({"a": "paint_target", "clear": true})))
	# A pasted code, and the one on the bench to copy.
	var code_row := HBoxContainer.new()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Paste a recipe code (W-PB40-LY12.5:M)"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_edit)
	code_row.add_child(ContractPanel.button("Load", func():
		var code := _code_edit.text.strip_edges()
		Shed.request({"a": "paint_recipe", "code": code, "name": "Recipe %s" % code.left(12)})))
	_box.add_child(code_row)
	if not card.is_empty():
		_box.add_child(ContractPanel.button("Copy this card's code: %s" % str(card.get("code", "")).left(30), func():
			DisplayServer.clipboard_set(str(card.get("code", "")))
			Shed.feedback.emit("Recipe code copied: paste it to a mate.", true)))
	if not tin.is_empty():
		_box.add_child(ContractPanel.button("Copy the tin's code: %s" % PaintMix.full_code(tin).left(30), func():
			DisplayServer.clipboard_set(PaintMix.full_code(tin))
			Shed.feedback.emit("Recipe code copied: paste it to a mate.", true)))
	var remix := PaintBay.kit("shaker")
	# The swatch wall's own.
	if not PaintBay.recipes().is_empty():
		_box.add_child(UITheme.label("THE SWATCH WALL", 14, UITheme.ACCENT))
		for id in PaintBay.swatch_order():
			var r: Dictionary = PaintBay.recipes()[id]
			_box.add_child(_recipe_row(str(r["name"]), str(r["code"]), r.get("mix", {}).get("color", Color.WHITE), "",
				str(r.get("mix", {}).get("effect", "solid")), remix))
	_box.add_child(UITheme.label("MANUFACTURER COLOURS (%d)" % PaintMix.library().size(), 14, UITheme.ACCENT))
	var brand := ""
	for e in PaintMix.library():
		if str(e["brand"]) != brand:
			brand = str(e["brand"])
			_box.add_child(UITheme.label(brand, 13, Color(1, 1, 1, 0.6)))
		var lv := PaintMix.level_needed(PaintMix.parse_code(str(e["code"])))
		var lock := "level %d" % lv if lv > Progress.level() else ""
		var finish := str(e.get("finish", "gloss"))
		var extra := "" if finish == "gloss" else "%s: lacquer with %d%% flattener over it" % [finish, roundi(float(PaintMix.SHEENS.get(finish if finish != "matt" else "matt", 0.0)) * 100.0)]
		_box.add_child(_recipe_row(PaintMix.library_name(e), str(e["code"]), e["rgb"], lock if lock != "" else extra, str(e["effect"]), remix, e["rgb"]))
	_box.add_child(_note("A card on the bench shows the grams of each tint to pour, and its colour is the target. "
		+ "'By eye' sets only the real colour to match. Close matches (over 95%) earn more XP and pay more on colour match jobs."))


func _recipe_row(title: String, code: String, color: Color, note: String, effect: String, remix: bool, eye = null) -> Control:
	var row := HBoxContainer.new()
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(22, 22)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var l := UITheme.label("%s  ·  %s%s" % [title, PaintMix.effect_name(effect).to_lower(), "\n" + note if note != "" else ""], 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var load_b := ContractPanel.button("Card", func(): Shed.request({"a": "paint_recipe", "code": code, "name": title.left(32)}))
	load_b.tooltip_text = code
	row.add_child(load_b)
	if eye is Color:
		row.add_child(ContractPanel.button("By eye", func():
			Shed.request({"a": "paint_target", "name": title.left(32), "color": eye, "effect": effect})))
	if remix:
		var act := {"a": "paint_remix", "code": code, "name": title.left(32)}
		var why := Shed.check(Shed.me(), act)
		var rb := ContractPanel.button("Remix", func(): Shed.request(act))
		rb.disabled = why != ""
		rb.tooltip_text = why
		row.add_child(rb)
	return row


func _fill_supplies() -> void:
	_box.add_child(UITheme.label("PAINT SUPPLIES, FROM THE GARAGE'S MONEY", 14, UITheme.ACCENT))
	for code in PaintBay.supplies():
		var c := str(code)
		var row := HBoxContainer.new()
		var chip := ColorRect.new()
		chip.color = PaintMix.BASES[c]["color"] if PaintMix.BASES.has(c) else PaintMix.TINTS[c]["color"]
		chip.custom_minimum_size = Vector2(14, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var lock := PaintBay.locked(Shed.me(), c)
		var l := UITheme.label("%s  ·  %s%s" % [PaintBay.item_name(c), PaintBay.stock_text(c), "  ·  " + lock.to_lower() if lock != "" else ""], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var act := {"a": "paint_buy", "code": c, "n": 1}
		var why := Shed.check(Shed.me(), act)
		var bb := ContractPanel.button("Buy %s" % TvChannels.money_text(PaintBay.price(c)), func(): Shed.request(act))
		bb.disabled = why != ""
		bb.tooltip_text = why
		row.add_child(bb)
		_box.add_child(row)
	_box.add_child(_note("A tin of base is a litre; a bottle of tint %d g. A litre covers about a tank, the guards and the side panels; a whole bike takes about two." % roundi(PaintMix.BOTTLE_G)))
