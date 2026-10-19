class_name HUD
extends Control
## Kept small on purpose: a crosshair and work progress ring, a side panel describing what you're
## looking at, and the tool bar when on foot; a compact speedo when riding. Everything else lives in the Esc menu.

var walker: Walker
var bike: Bike
var car: Car               # the recovery truck, while you're at the wheel (RecoveryView sets it)
var _message: Label
var _message_timer := 0.0
var _flash_raw := ""   # the message as sent, with its {action}s still in
var _panel: PanelContainer
var _title: Label
var _info: Label
var _prompt: Label
var _top_kmh := 0.0
var trip_km := 0.0         # this ride, for the economy readout
var trip_fuel := 0.0       # litres burnt this ride
var fuel_stop: FuelStop     # filling up at a pump and the low fuel light, while riding (main sets it)
var warn_lights: Array = []  # the dash's warning lights on now (the oil light...), while riding on an adventure (see Roadside)
var ride_hint := ""          # what to press for a breakdown out on an adventure (main sets it)
## "+6 XP Cleaning" popups under the level bar: [{amount, label, age}], newest first.
var popups: Array = []
var blast_hud: BlastHud     # the sandblaster's readout, while your hands are in the gloves
var spray_hud: SprayHud     # the spray readout, while you lay a coat on
var wash_hud: WashHud       # the pressure washing readout, while the wash controls are up
var detail_hud: DetailHud   # the polishing and coating readout, while the detailing controls are up
var _banner_level := 0
var _banner_time := 0.0
const POPUP_LIFE := 3.0
const BANNER_LIFE := 4.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message = UITheme.title("", 28, Color(1, 0.85, 0.7))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -500
	_message.offset_right = 500
	_message.offset_top = 40
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_message)
	# What you're looking at goes in a panel at the side, out of the way of the crosshair.
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_left = -430
	_panel.offset_right = -24
	_panel.offset_top = -170
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.72)
	style.border_color = Color(UITheme.ACCENT, 0.5)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	_title = UITheme.title("", 21, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_info = UITheme.label("", 15, Color(1, 1, 1, 0.85))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)
	_prompt = UITheme.label("", 17, UITheme.ACCENT)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_prompt)
	blast_hud = BlastHud.new()
	add_child(blast_hud)
	spray_hud = SprayHud.new()
	add_child(spray_hud)
	wash_hud = WashHud.new()
	add_child(wash_hud)
	detail_hud = DetailHud.new()
	add_child(detail_hud)
	Progress.xp_gained.connect(add_popup)
	Progress.cash_changed.connect(add_popup.bind(true))
	Progress.leveled_up.connect(func(level: int):
		_banner_level = level
		_banner_time = BANNER_LIFE
		Sfx.play_ui("levelup", -4.0))


## Shows "+N XP label" (or "+£N label" for cash); the same kind arriving close together adds up
## in one popup.
func add_popup(amount: int, label: String, cash := false) -> void:
	for p in popups.slice(0, 2):
		if p["label"] == label and bool(p.get("cash", false)) == cash and float(p["age"]) < 0.8:
			p["amount"] = int(p["amount"]) + amount
			p["age"] = 0.0
			return
	popups.push_front({"amount": amount, "label": label, "age": 0.0, "cash": cash})
	while popups.size() > 5:
		popups.pop_back()


## Shows a message for a few seconds. Any {action} in it shows that action's key on the
## device in use, and changes with it (see Controls.hint).
func flash(text: String, seconds := 2.5, bad := false) -> void:
	_flash_raw = text
	_message.text = Controls.hint(text)
	_message.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if bad else Color(1, 0.85, 0.7))
	_message_timer = seconds


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("hud", pt)


func _process_body(delta: float) -> void:
	_message_timer -= delta
	for p in popups:
		p["age"] = float(p["age"]) + delta
	popups = popups.filter(func(p): return float(p["age"]) < POPUP_LIFE)
	_banner_time = maxf(0.0, _banner_time - delta)
	if _message_timer <= 0.0 and _message.text != "":
		_message.text = ""
		_flash_raw = ""
	elif _message_timer > 0.0:
		_message.text = Controls.hint(_flash_raw)
	if car != null and not is_instance_valid(car):
		car = null
	var on_foot := walker != null and bike == null and car == null
	blast_hud.walker = walker if on_foot else null
	spray_hud.walker = walker if on_foot else null
	wash_hud.walker = walker if on_foot else null
	detail_hud.walker = walker if on_foot else null
	_panel.visible = on_foot and walker.blast == null and not spray_hud.showing() and not wash_hud.showing() and not detail_hud.showing() \
		and (walker.info != "" or walker.look_info != "" or not walker.plan.is_empty() or walker.crouched)
	if on_foot:
		# What the cafe's bikers and the like say (Walker.look_info) comes first, over what the
		# walker's own targeting has to say.
		var text := walker.info
		if walker.look_info != "":
			text = walker.look_info + ("\n" + walker.info if walker.info != "" else "")
		var lines := Controls.hint(text).split("\n")
		_title.text = lines[0]
		_info.text = "\n".join(lines.slice(1))
		_info.visible = _info.text != ""
		var plan := walker.plan
		var prompts := []
		if walker.look_prompt != "":
			prompts.append(Controls.hint(walker.look_prompt))
		var blocked := false
		if not plan.is_empty():
			blocked = plan["blocked"] != ""
			prompts.append(Controls.hint(plan["blocked"] if blocked else "Hold %s to %s" % [_act_key(), plan["verb"]]))
		var alt := walker.alt_plan
		if not alt.is_empty() and alt["blocked"] == "":
			prompts.append("Hold %s to %s" % [_alt_key(), alt["verb"]])
		if walker.tap_prompt != "":
			prompts.append(Controls.hint(walker.tap_prompt))
		if walker.crouched:
			prompts.append(Controls.hint("Crouching ({crouch} to stand up)"))
		_prompt.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if blocked and prompts.size() == 1 else UITheme.ACCENT)
		_prompt.text = "\n".join(prompts)
	if bike and bike.is_crashed:
		_flash_raw = "Crashed! Press {respawn} to get back on"
		_message.text = Controls.hint(_flash_raw)
		_message_timer = 0.1
	queue_redraw()


func _act_key() -> String:
	return Controls.key("work")


func _alt_key() -> String:
	return Controls.key("work2")


func _draw() -> void:
	if bike:
		_draw_speedo()
	elif car:
		_draw_truck_dash()
	elif walker:
		_draw_crosshair()
		_draw_toolbar()
		if walker.tyre_game is PlugGame:
			_draw_plug_game(walker.tyre_game)
		elif walker.tyre_game:
			_draw_tyre_game(walker.tyre_game)
	if walker and (walker.stopwatch.showing() or (bike == null and walker.tool == "watch")):
		_draw_stopwatch()
	if walker:
		_draw_level()
		_draw_badges()


## Small reminders down the left: ear defenders on, carrying the dyno's extraction hose.
func _draw_badges() -> void:
	var badges := []
	if Shed.wearing_headphones(Shed.me()):
		badges.append(["EAR DEFENDERS ON", Controls.hint("Everything's muffled. {interact} at their hook to hang them up.")])
	if Shed.hose_holder() == Shed.me():
		badges.append(["CARRYING THE EXHAUST HOSE", "Hold %s on the exhaust to fit it." % _act_key()])
	var font := get_theme_default_font()
	var y := size.y * 0.42
	for b in badges:
		var r := Rect2(24.0, y, 380.0, 50.0)
		draw_rect(r, Color(0.04, 0.05, 0.07, 0.72))
		draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), Color(0.95, 0.72, 0.05))
		draw_string(font, r.position + Vector2(14.0, 21.0), b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.72, 0.05))
		draw_string(font, r.position + Vector2(14.0, 40.0), b[1], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, Color(1, 1, 1, 0.75))
		y += 58.0


## Your level and XP bar, top right, with XP popups fading under it and the level-up banner.
func _draw_level() -> void:
	var font := get_theme_default_font()
	var s := Progress.own_summary()
	var w := 250.0
	var r := Rect2(size.x - w - 24.0, 18.0, w, 40.0)
	draw_rect(r, Color(0.03, 0.03, 0.04, 0.55))
	draw_string(font, r.position + Vector2(10, 18), "LV %d" % s["level"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.ACCENT)
	# Your own cash, just left of the level box.
	var cash := TvChannels.money_text(Progress.money())
	var cw := font.get_string_size(cash, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20.0
	draw_rect(Rect2(r.position.x - cw - 8.0, r.position.y, cw, r.size.y), Color(0.03, 0.03, 0.04, 0.55))
	draw_string(font, Vector2(r.position.x - cw + 2.0, r.position.y + 26), cash, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.95, 0.55))
	var pts := int(s["tool_points"]) + int(s["skill_points"])
	var right := "%d / %d XP" % [int(s["xp"]), int(s["xp_next"])]
	if pts > 0:
		right = "%d point%s to spend (%s)" % [pts, "" if pts == 1 else "s", Controls.key("menu")]
	draw_string(font, r.position + Vector2(60, 18), right, HORIZONTAL_ALIGNMENT_RIGHT, w - 70.0, 12,
		UITheme.ACCENT if pts > 0 else Color(1, 1, 1, 0.65))
	var span := maxf(1.0, float(int(s["xp_next"]) - int(s["xp_level_start"])))
	var frac := clampf(float(int(s["xp"]) - int(s["xp_level_start"])) / span, 0.0, 1.0)
	var bar := Rect2(r.position + Vector2(10, 26), Vector2(w - 20.0, 6))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), UITheme.ACCENT)
	for i in popups.size():
		var p: Dictionary = popups[i]
		var age := float(p["age"])
		var alpha := clampf((POPUP_LIFE - age) / 0.8, 0.0, 1.0) * clampf(age / 0.12, 0.0, 1.0)
		var y := r.end.y + 20.0 + i * 20.0 - minf(age, 0.25) * 16.0
		var amt := int(p["amount"])
		if p.get("cash", false):
			draw_string(font, Vector2(r.position.x, y), "%s%s  %s" % ["+" if amt >= 0 else "", TvChannels.money_text(amt), p["label"]],
				HORIZONTAL_ALIGNMENT_RIGHT, w, 14, Color(0.55, 0.95, 0.55, alpha * 0.9) if amt >= 0 else Color(1.0, 0.55, 0.45, alpha * 0.9))
		else:
			draw_string(font, Vector2(r.position.x, y), "+%d XP  %s" % [amt, p["label"]], HORIZONTAL_ALIGNMENT_RIGHT, w,
				14, Color(1.0, 0.85, 0.45, alpha * 0.9))
	if _banner_time > 0.0:
		var a := clampf(_banner_time / 0.6, 0.0, 1.0) * clampf((BANNER_LIFE - _banner_time) / 0.25, 0.0, 1.0)
		var y := size.y * 0.3
		draw_rect(Rect2(0, y - 52, size.x, 84), Color(0, 0, 0, 0.45 * a))
		draw_string(font, Vector2(0, y), "LEVEL %d" % _banner_level, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(UITheme.ACCENT, a))
		draw_string(font, Vector2(0, y + 24), Controls.hint("A tool point and a skill point to spend: {menu}, then the Character tab"),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.85 * a))


## The stopwatch readout, top left, with the last few laps. It stays up while you ride.
func _draw_stopwatch() -> void:
	var font := get_theme_default_font()
	var sw := walker.stopwatch
	var r := Rect2(24, 24, 230, 70 + 22 * sw.laps.size())
	draw_rect(r, Color(0.03, 0.03, 0.04, 0.65))
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), UITheme.ACCENT if sw.running else Color(1, 1, 1, 0.4))
	draw_string(font, r.position + Vector2(14, 20), "STOPWATCH" + ("" if sw.running else "  (stopped)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1, 1, 1, 0.6))
	draw_string(font, r.position + Vector2(14, 56), Stopwatch.format(sw.elapsed()), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	for i in sw.laps.size():
		draw_string(font, r.position + Vector2(14, 82 + 22 * i), "Lap %d   %s" % [i + 1, Stopwatch.format(sw.laps[i])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	if bike == null and walker.tool == "watch":
		var hint := Controls.hint("{act}: start / stop   {alt_act}: lap / reset   {stopwatch}: start / stop anywhere")
		draw_string(font, Vector2(r.position.x, r.end.y + 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))


## The tyre changer game: the rim as a ring, the marker going round it, your tyre lever, and
## each stretch of the rim coloured by how well the bead went on there.
func _draw_tyre_game(game: TyreGame) -> void:
	var font := get_theme_default_font()
	var c := size * 0.5
	var r := minf(size.y * 0.2, 150.0)
	draw_circle(c, r + 34.0, Color(0.03, 0.03, 0.04, 0.55))
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 10.0, true)
	for i in TyreGame.SEGMENTS:
		var q := game.segment(i)
		if q < 0.0:
			continue
		var a0 := -PI * 0.5 + TAU * i / TyreGame.SEGMENTS
		draw_arc(c, r, a0, a0 + TAU / TyreGame.SEGMENTS + 0.01, 4, Color(1.0, 0.3, 0.2).lerp(Color(0.3, 1.0, 0.4), q), 10.0, true)
	var m := c + game.marker() * r
	draw_circle(m, 13.0, Color(0, 0, 0, 0.5))
	draw_circle(m, 10.0, UITheme.ACCENT)
	var lever := c + game.cursor * r
	var on := game.on_target()
	draw_line(c, lever, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(lever, 7.0, Color(1, 1, 1).lerp(Color(0.3, 1.0, 0.4), on))
	var hint := Controls.hint("Keep the lever on the marker with the {aim}")
	draw_string(font, Vector2(0, c.y - r - 48), "WORK THE TYRE ON", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UITheme.ACCENT)
	draw_string(font, Vector2(0, c.y + r + 52), "%s  ·  bead %d%%" % [hint, roundi(game.quality() * 100.0)],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.8))


## The puncture plug game: the tread laid out as a strip, the soapy nozzle (then the reamer) on
## it, bubbles foaming thicker the nearer it is to the hole, and the plug going in.
func _draw_plug_game(game: PlugGame) -> void:
	var font := get_theme_default_font()
	var w := minf(size.x * 0.4, 560.0)   # clear of the part info down the right
	var strip := Rect2(size.x * 0.5 - w * 0.5, size.y * 0.5 + 60.0, w, 46.0)
	draw_rect(strip.grow(28.0), Color(0.03, 0.03, 0.04, 0.6))
	draw_rect(strip, Color(0.07, 0.07, 0.08))
	var rg := game as RoadsideGame   # a roadside fix run the same way (see RoadsideGame)
	if rg != null:
		_draw_roadside_strip(rg, strip)
	else:
		# The tread blocks.
		var blocks := 26
		for i in blocks:
			var x := strip.position.x + (i + 0.5) * strip.size.x / blocks
			draw_line(Vector2(x - 6.0, strip.position.y + 4.0), Vector2(x + 6.0, strip.end.y - 4.0), Color(0.16, 0.16, 0.17), 5.0)
	var at := func(u: float) -> float: return strip.position.x + (u * 0.5 + 0.5) * strip.size.x
	var nozzle_x: float = at.call(game.cursor.x)
	var t := float(Time.get_ticks_msec()) / 1000.0
	if not game.found and rg != null:
		# The test lamp (or the pliers, or the lever) glowing brighter the nearer it is.
		var glow := game.foam()
		draw_circle(Vector2(nozzle_x, strip.get_center().y), 6.0 + 14.0 * glow, Color(1.0, 0.85, 0.3, 0.15 + 0.55 * glow))
		draw_line(Vector2(nozzle_x, strip.position.y - 26.0), Vector2(nozzle_x, strip.get_center().y), Color(0.85, 0.85, 0.9), 4.0)
		draw_circle(Vector2(nozzle_x, strip.position.y - 30.0), 7.0, Color(1.0, 0.85, 0.3).lerp(Color(0.6, 0.6, 0.6), 1.0 - glow))
		var lock_r := game.lock_progress()
		if lock_r > 0.0:
			draw_arc(Vector2(nozzle_x, strip.position.y - 30.0), 13.0, -PI * 0.5, -PI * 0.5 + TAU * lock_r, 24, UITheme.ACCENT, 3.0, true)
		draw_string(font, Vector2(0, strip.position.y - 56.0), rg.label("find"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UITheme.ACCENT)
		draw_string(font, Vector2(0, strip.end.y + 44.0), Controls.hint(rg.label("find_hint")), HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(0, strip.end.y + 66.0), "%.0f s left" % maxf(0.0, PlugGame.FIND_TIME - game.t), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1, 1, 1, 0.55))
		return
	if not game.found:
		# Soap where the nozzle is: a few bubbles anywhere, a froth growing right over the hole.
		var foam := game.foam()
		var n := 3 + roundi(foam * 14.0)
		for i in n:
			var k := float(i) / maxf(float(n), 1.0)
			var jx := sin(t * 3.1 + i * 2.39) * (10.0 + 6.0 * foam)
			var jy := cos(t * 2.3 + i * 1.71) * 14.0
			var r := 2.5 + (5.0 + 3.0 * sin(t * 6.0 + i)) * foam * (0.5 + k)
			draw_arc(Vector2(nozzle_x + jx, strip.get_center().y + jy), r, 0.0, TAU, 12, Color(0.9, 0.95, 1.0, 0.45 + 0.4 * foam), 1.5, true)
		draw_line(Vector2(nozzle_x, strip.position.y - 26.0), Vector2(nozzle_x, strip.position.y - 4.0), Color(0.5, 0.8, 1.0), 4.0)
		draw_circle(Vector2(nozzle_x, strip.position.y - 30.0), 7.0, Color(0.5, 0.8, 1.0))
		var lock := game.lock_progress()
		if lock > 0.0:
			draw_arc(Vector2(nozzle_x, strip.position.y - 30.0), 13.0, -PI * 0.5, -PI * 0.5 + TAU * lock, 24, UITheme.ACCENT, 3.0, true)
		draw_string(font, Vector2(0, strip.position.y - 56.0), "FIND THE HISS", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UITheme.ACCENT)
		draw_string(font, Vector2(0, strip.end.y + 44.0), Controls.hint("Sweep the soapy spray along the tread with the {aim}: hold it where it froths up"),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.8))
		var left := maxf(0.0, PlugGame.FIND_TIME - game.t)
		draw_string(font, Vector2(0, strip.end.y + 66.0), "soap left %.0f s" % left, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1, 1, 1, 0.55))
		return
	# Found: the hole, drifting as the tyre creeps, and the reamer to keep on it.
	var hole_x: float = at.call(game.hole_now())
	draw_circle(Vector2(hole_x, strip.get_center().y), 6.0, Color(0.95, 0.85, 0.3))
	var on := game.on_target()
	draw_line(Vector2(nozzle_x, strip.position.y - 34.0), Vector2(nozzle_x, strip.get_center().y), Color(0.75, 0.75, 0.78), 4.0)
	draw_line(Vector2(nozzle_x - 16.0, strip.position.y - 34.0), Vector2(nozzle_x + 16.0, strip.position.y - 34.0), Color(0.75, 0.75, 0.78), 6.0)
	draw_circle(Vector2(nozzle_x, strip.get_center().y), 4.0, Color(1, 1, 1).lerp(Color(0.3, 1.0, 0.4), on))
	var bar := Rect2(strip.position.x, strip.end.y + 14.0, strip.size.x, 6.0)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * game.plug_progress(), bar.size.y)), UITheme.ACCENT)
	draw_string(font, Vector2(0, strip.position.y - 56.0), rg.label("fix") if rg else "PUSH THE PLUG IN", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UITheme.ACCENT)
	draw_string(font, Vector2(0, strip.end.y + 44.0), "%s  ·  %s %d%%" % [Controls.hint(rg.label("fix_hint") if rg else "Keep the reamer on the hole with the {aim}"),
		rg.label("score") if rg else "plug", roundi(game.quality() * 100.0)], HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.8))


## What a roadside game's strip shows: a row of fuses, the run of the spare chain, or the bar
## end with the lever's pivot.
func _draw_roadside_strip(game: RoadsideGame, strip: Rect2) -> void:
	match game.kind:
		"fuse":
			var n := 12
			for i in n:
				var x := strip.position.x + (i + 0.5) * strip.size.x / n
				var col: Color = [Color(0.85, 0.2, 0.15), Color(0.2, 0.45, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35)][i % 4]
				draw_rect(Rect2(x - 9.0, strip.position.y + 8.0, 18.0, strip.size.y - 16.0), col.darkened(0.25))
				draw_rect(Rect2(x - 3.0, strip.position.y + 4.0, 6.0, 6.0), Color(0.8, 0.8, 0.82))
		"chain":
			var links := 30
			for i in links:
				var x := strip.position.x + (i + 0.5) * strip.size.x / links
				draw_arc(Vector2(x, strip.get_center().y), 7.0, 0.0, TAU, 12, Color(0.55, 0.55, 0.58), 3.0, true)
		_:
			draw_rect(Rect2(strip.position.x, strip.get_center().y - 5.0, strip.size.x, 10.0), Color(0.5, 0.5, 0.52))


func _draw_crosshair() -> void:
	var c := size * 0.5
	var col := UITheme.ACCENT if not walker.target.is_empty() else Color(1, 1, 1, 0.7)
	draw_circle(c, 3.0, Color(0, 0, 0, 0.5))
	draw_circle(c, 2.0, col)
	if walker.progress > 0.0:
		draw_arc(c, 18.0, 0.0, TAU, 40, Color(0, 0, 0, 0.4), 5.0, true)
		draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * walker.progress, 40, UITheme.ACCENT, 5.0, true)


func _draw_toolbar() -> void:
	var font := get_theme_default_font()
	var n := Walker.TOOLS.size()
	var w := minf(120.0, (size.x - 40.0) / n - 8.0)
	var x0 := size.x * 0.5 - n * (w + 8.0) * 0.5
	var y := size.y - 70.0
	for i in n:
		var t: String = Walker.TOOLS[i]
		var r := Rect2(x0 + i * (w + 8.0), y, w, 46)
		var active := t == walker.tool
		draw_rect(r, Color(0.05, 0.06, 0.08, 0.75 if active else 0.45))
		if active:
			draw_rect(r, UITheme.ACCENT, false, 2.0)
		draw_string(font, r.position + Vector2(8, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
		var label: String = {"hands": "Hands", "wrench": "Wrench", "brush": "Brush", "repair": "Grinder", "spray": "Spray can",
			"lance": "Pressure wash", "gun": "Spray gun", "watch": "Stopwatch", "polisher": "Polisher"}.get(t, t)
		draw_string(font, r.position + Vector2(0, 34), label, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color.WHITE if active else Color(1, 1, 1, 0.65))
		var stage := Progress.tool_stage(Shed.me(), t)
		if stage > 0:
			draw_string(font, r.position + Vector2(0, 18), "●".repeat(stage), HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0, 9, Color(UITheme.ACCENT, 0.9))
	var board: Node = get_tree().get_first_node_in_group("whiteboard") if walker.target.get("kind", "") == "board" else null
	if board:
		board.draw_picker(self, font, y)
	elif walker.tool in ["spray", "gun"] and not spray_hud.showing():
		_draw_spray_picker(font, y)
	var held := Shed.held_by(Shed.me())
	if held != 0:
		draw_string(font, Vector2(0, y - 10), "Carrying: " + Shed.item_title(held), HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, UITheme.ACCENT)


## The spray can's colour swatches and finishes, above the tool bar while it's in your hand.
func _draw_spray_picker(font: Font, toolbar_y: float) -> void:
	var n := Shed.PAINTS.size()
	var sw := 30.0
	var gap := 6.0
	var total := n * (sw + gap) - gap
	var x0 := size.x * 0.5 - total * 0.5
	var gun: bool = walker.tool == "gun"
	var y := toolbar_y - 152.0
	draw_rect(Rect2(x0 - 14, y - 32, total + 28, 136), Color(0.05, 0.06, 0.08, 0.7))
	draw_string(font, Vector2(x0, y - 12), "%s  ·  %s" % ["SPRAY GUN (PAINT BOOTH)" if walker.tool == "gun" else "SPRAY CAN",
		walker.spray_text().to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	for i in n:
		var r := Rect2(x0 + i * (sw + gap), y, sw, sw)
		if i == walker.spray_color:
			r = r.grow(4.0)
		draw_rect(r, Shed.PAINTS[i])
		if i == walker.spray_color:
			draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
	var fx := x0
	for i in Shed.FINISHES.size():
		var label: String = Shed.FINISH_NAMES[Shed.FINISHES[i]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0
		var r := Rect2(fx, y + 42, w, 24)
		var on := i == walker.spray_finish
		draw_rect(r, Color(1, 1, 1, 0.18) if on else Color(1, 1, 1, 0.05))
		if on:
			draw_rect(r, UITheme.ACCENT, false, 2.0)
		draw_string(font, r.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if on else Color(1, 1, 1, 0.6))
		fx += w + 6.0
	var hint_y := y + 122
	# Then the other coats: grey primer and clear lacquer (and the spray gun's protective coats).
	fx = x0
	draw_string(font, Vector2(fx, y + 91), "COATS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.ACCENT)
	fx += 58.0
	var loads := walker.spray_loads()
	for k in range(Shed.FINISHES.size(), loads.size()):
		var l: Dictionary = loads[k]
		var label := walker.load_label(l)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		var r := Rect2(fx, y + 74, w, 24)
		var on := walker.spray_finish == k
		draw_rect(r, Color(1, 1, 1, 0.18) if on else Color(1, 1, 1, 0.05))
		if on:
			draw_rect(r, UITheme.ACCENT, false, 2.0)
		draw_string(font, r.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if on else Color(1, 1, 1, 0.6))
		fx += w + 6.0
	var hint := Controls.hint("{spray_colour}: colour   {spray_finish}: finish or coat   {blast_scan}: scan")
	draw_string(font, Vector2(x0, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, total, 14, Color(1, 1, 1, 0.6))


## The speedo shows what the bike's dashboard can: an old analogue clock gives you only speed,
## a race logger adds revs, gear, a shift light and your top speed.
func _draw_speedo() -> void:
	if bike.build == null:
		return
	var features: Array = bike.build.dash_features
	var font := get_theme_default_font()
	var r := Rect2(size.x - 250, size.y - 172, 226, 148)
	draw_rect(r, Color(0.03, 0.03, 0.04, 0.6))
	_top_kmh = maxf(_top_kmh, absf(bike.speed) * 3.6)
	draw_string(font, r.position + Vector2(12, 58), "%d" % Units.speed_value(bike.speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	draw_string(font, r.position + Vector2(120, 34), Units.speed_unit(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.6))
	if features.has("gear"):
		draw_string(font, r.position + Vector2(120, 60), "GEAR %s" % Bike.gear_name(bike.gear), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.ACCENT)
	if features.has("top_speed"):
		draw_string(font, r.position + Vector2(170, 34), "TOP %d" % Units.speed_value(_top_kmh / 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var frac := clampf(bike.rpm / bike.build.redline, 0.0, 1.0)
	if features.has("rpm"):
		draw_rect(Rect2(r.position + Vector2(12, 74), Vector2(202, 8)), Color(1, 1, 1, 0.12))
		var col := UITheme.ACCENT if frac < 0.92 else Color(1, 0.2, 0.15)
		draw_rect(Rect2(r.position + Vector2(12, 74), Vector2(202 * frac, 8)), col)
	if features.has("shift_light") and frac > 0.88:
		draw_circle(r.position + Vector2(206, 18), 8.0, Color(1, 0.15, 0.1) if frac > 0.94 else Color(1, 0.85, 0.1))
	# Fuel gauge and how far this ride's petrol has gone.
	var fuel := clampf(bike.fuel_litres / maxf(bike.build.fuel_capacity, 0.1), 0.0, 1.0)
	draw_string(font, r.position + Vector2(12, 106), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	draw_rect(Rect2(r.position + Vector2(52, 96), Vector2(162, 10)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(r.position + Vector2(52, 96), Vector2(162 * fuel, 10)), Color(1, 0.3, 0.2) if fuel < 0.15 else Color(0.9, 0.85, 0.3))
	var used := trip_fuel + bike.fuel_used
	var economy := Units.economy(trip_km / used) if used > 0.01 and trip_km > 0.05 else "-- " + Units.economy_unit()
	draw_string(font, r.position + Vector2(12, 130), "%.1f L  ·  %s" % [bike.fuel_litres, economy], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))
	if fuel_stop and fuel_stop.low() and int(Time.get_ticks_msec() / 500) % 2 == 0:
		# The low fuel light, blinking.
		draw_string(font, r.position + Vector2(140, 106), "LOW FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.65, 0.1))
	_draw_heat_hints(r)
	# The warning lights (see Roadside): the oil light, red and steady.
	var lx := r.position.x + 12.0
	for l in warn_lights:
		var lw := 14.0 + 8.0 * str(l).length()
		draw_rect(Rect2(Vector2(lx, r.position.y - 30.0), Vector2(lw, 22.0)), Color(0.75, 0.08, 0.05, 0.9))
		draw_string(font, Vector2(lx + 7.0, r.position.y - 14.0), str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.85))
		lx += lw + 6.0
	var hint := ""
	if fuel_stop and fuel_stop.filling:
		hint = "Filling up: %.1f L  ·  %s" % [fuel_stop.litres, TvChannels.money_text(ceili(fuel_stop.litres * FuelStop.price_of(fuel_stop.pump)))]
	elif fuel_stop and fuel_stop.pump_here() != null and not bike.is_crashed:
		hint = Controls.hint("Hold {interact}: fill up (%dp a litre, your money)   ·   %.1f of %.0f L in the tank" % [
			roundi(FuelStop.price_of(fuel_stop.pump_here()) * 100.0), bike.fuel_litres, bike.build.fuel_capacity]) \
			if fuel_stop.space() >= 0.05 else Controls.hint("The tank's full   ·   {interact}: get off")
	elif ride_hint != "":
		hint = Controls.hint(ride_hint)
	elif not bike.engine_on and not bike.is_crashed:
		hint = "Starting..." if bike.is_starting() else Controls.hint("Engine off: press {ignition} to start it")
	elif absf(bike.speed) < 2.0 and not bike.is_crashed:
		hint = Controls.hint("{interact}: get off   ·   {ignition}: engine off   ·   hold {front_brake}: paddle back   ·   {front_brake} + {throttle}: burnout")
	if hint != "":
		draw_string(font, Vector2(0, size.y - 40), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.75))


## Beside the speedo, how warm the tyres and the engine are (cold, warm or hot), and a warning
## while the brakes are fading (see BikeHeat).
func _draw_heat_hints(panel: Rect2) -> void:
	var h := bike.heat
	if h == null:
		return
	var font := get_theme_default_font()
	var rows := [["TYRES", h.tyre_state()], ["ENGINE", h.engine_state()]]
	if h.brakes_fading():
		rows.append(["BRAKES", "fading"])
	var colours := {"cold": Color(0.45, 0.72, 1.0), "warm": Color(0.45, 0.85, 0.45), "hot": Color(1.0, 0.35, 0.25),
		"fading": Color(1.0, 0.35, 0.25)}
	var y := panel.position.y
	for row in rows:
		var box := Rect2(panel.position.x - 138.0, y, 130.0, 28.0)
		draw_rect(box, Color(0.03, 0.03, 0.04, 0.6))
		var col: Color = colours.get(row[1], Color.WHITE)
		draw_circle(box.position + Vector2(12.0, 14.0), 5.0, col)
		draw_string(font, box.position + Vector2(24.0, 19.0), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		draw_string(font, box.position + Vector2(82.0, 19.0), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 34.0


## The truck's dash, in the corner where a bike's speedo goes: the speed, the gear lever's
## positions with the one it's in lit (R N D on the automatic, R N 1-6 on the manual), the revs,
## the headlamp telltale, and what to press when it's stopped or not running.
func _draw_truck_dash() -> void:
	var font := get_theme_default_font()
	var r := Rect2(size.x - 250, size.y - 150, 226, 126)
	draw_rect(r, Color(0.03, 0.03, 0.04, 0.6))
	draw_string(font, r.position + Vector2(12, 58), "%d" % Units.speed_value(absf(car.speed)), HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	draw_string(font, r.position + Vector2(120, 34), Units.speed_unit(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.6))
	# The headlamp telltale: green dipped, blue main beam.
	if car.engine_on and car.beam > 0:
		var main_beam := car.beam >= 2
		draw_string(font, r.position + Vector2(176, 34), "MAIN" if main_beam else "DIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.35, 0.6, 1.0) if main_beam else Color(0.35, 0.9, 0.45))
	# The handbrake telltale: a red (P) in a ring while it's pulled up and left on.
	if car.parking_brake or car.handbrake > 0.3:
		var c := r.position + Vector2(196, 58)
		var red := Color(1.0, 0.22, 0.15)
		draw_arc(c, 11.0, 0.0, TAU, 24, red, 2.0)
		draw_arc(c, 15.0, deg_to_rad(-50.0), deg_to_rad(50.0), 8, red, 1.5)
		draw_arc(c, 15.0, deg_to_rad(130.0), deg_to_rad(230.0), 8, red, 1.5)
		draw_string(font, c + Vector2(-5, 5), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, red)
	var stops: Array = ["R", "N", "D"] if car.auto_shift else ["R", "N", "1", "2", "3", "4", "5", "6"]
	var lit := "R" if car.gear < 0 else ("N" if car.gear == 0 else ("D" if car.auto_shift else str(car.gear)))
	var x := 12.0
	for stop: String in stops:
		var on := stop == lit
		var label: String = stop + (str(car.gear) if on and stop == "D" else "")
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 10.0
		if on:
			draw_rect(Rect2(r.position + Vector2(x, 66), Vector2(w, 24)), Color(1, 0.3, 0.2) if stop == "R" else UITheme.ACCENT)
		draw_string(font, r.position + Vector2(x + 5, 85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.05, 0.05, 0.05) if on else Color(1, 1, 1, 0.45))
		x += w + 2.0
	var frac := clampf(car.rpm / Car.REDLINE, 0.0, 1.0)
	draw_rect(Rect2(r.position + Vector2(12, 100), Vector2(202, 8)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(r.position + Vector2(12, 100), Vector2(202 * frac, 8)), UITheme.ACCENT if frac < 0.9 else Color(1, 0.2, 0.15))
	draw_string(font, r.position + Vector2(12, 120), "%d rpm" % (roundi(car.rpm / 50.0) * 50), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var hint := ""
	if not car.engine_on:
		hint = "Starting..." if car.is_starting() else Controls.hint("Engine off: press {ignition} to start it")
	elif absf(car.speed) < 1.0:
		var rev := ""
		if car.gear < 0:
			rev = "{throttle} or {shift_up}: drive" if car.pedals_swapped() else ("{shift_up}: drive" if car.auto_shift else "{shift_up}: neutral")
		elif car.auto_shift:
			rev = "hold {front_brake} or press {shift_down}: reverse"
		elif car.gear == 0:
			rev = "{shift_down}: reverse   ·   {shift_up}: first"
		else:
			rev = "{shift_down}: down to neutral, then reverse"
		var hb := "{handbrake}: handbrake off" if car.parking_brake else "{handbrake}: handbrake on"
		hint = Controls.hint("{interact}: get out   ·   %s   ·   %s   ·   {headlight}: headlamps   ·   {ignition}: engine off" % [rev, hb])
	if hint != "":
		draw_string(font, Vector2(0, size.y - 40), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.75))
