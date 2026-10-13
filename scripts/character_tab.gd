class_name CharacterTab
extends ScrollContainer
## The Esc menu's Character tab: your level and XP, the hand tool upgrades (spend a tool point
## on the next stage of a tool), the skills tree (spend skill points on ranks), and the goals
## that pay a lump of XP. Everything comes from and goes to Progress.

var _box: VBoxContainer
var _tree: SkillTreeView
var _skill_info: Label
var _due := false


func _ready() -> void:
	name = "Character"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	Progress.changed.connect(func(): _due = true)
	visibility_changed.connect(func(): _due = true)
	_rebuild()


func _process(_delta: float) -> void:
	if _due and is_visible_in_tree():
		_due = false
		_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var s := Progress.own_summary()
	var lv: int = s["level"]
	_box.add_child(UITheme.title("%s  ·  Level %d" % [s["name"], lv], 26))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var span: int = maxi(1, int(s["xp_next"]) - int(s["xp_level_start"]))
	bar.max_value = span
	bar.value = clampi(int(s["xp"]) - int(s["xp_level_start"]), 0, span)
	_box.add_child(bar)
	var to_go := int(s["xp_next"]) - int(s["xp"])
	_box.add_child(UITheme.label("%d XP in total.  %s" % [s["xp"],
		"%d XP to level %d." % [to_go, lv + 1] if lv < Progress.MAX_LEVEL else "Top level!"], 15, Color(1, 1, 1, 0.75)))
	_box.add_child(UITheme.label("Tool points to spend: %d     Skill points to spend: %d     (one of each every level)" % [
		s["tool_points"], s["skill_points"]], 16, UITheme.ACCENT))
	_tools()
	_skills()
	_goals()


## A card per hand tool: its stage now, what the next one does, and the upgrade button.
func _tools() -> void:
	_box.add_child(UITheme.title("Tool upgrades", 21))
	_box.add_child(UITheme.label("Each stage makes a tool quicker (and wider, for the brush, sprays and washer) and better looking.", 14,
		Color(1, 1, 1, 0.6)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_box.add_child(grid)
	var tools: Array = Walker.TOOLS.duplicate()
	for t in Progress.TOOL_INFO:
		if not tools.has(t) and Progress.tool_stage(Shed.me(), str(t)) > 0:
			tools.append(t)
	for t in tools:
		var tool := str(t)
		var stage := Progress.tool_stage(Shed.me(), tool)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.04)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		style.border_color = Color(UITheme.ACCENT, 0.25 + 0.15 * stage)
		style.border_width_left = 3
		card.add_theme_stylebox_override("panel", style)
		var col := VBoxContainer.new()
		card.add_child(col)
		var pips := "●".repeat(stage) + "○".repeat(5 - stage)
		col.add_child(UITheme.label("%s   %s" % [Progress.tool_name(tool), pips], 17, Color.WHITE))
		col.add_child(UITheme.label(Progress.tool_effect_text(tool, stage), 13, Color(1, 1, 1, 0.7)))
		if stage < 5:
			col.add_child(UITheme.label("Next: " + Progress.tool_effect_text(tool, stage + 1), 13, Color(UITheme.ACCENT, 0.85)))
		var why := Progress.tool_block(tool)
		var b := Button.new()
		b.text = "Upgrade (1 tool point)" if why == "" else why
		b.disabled = why != ""
		b.pressed.connect(func():
			var err := Progress.upgrade_tool(tool)
			if err == "":
				Sfx.play_ui("clink", -6.0))
		col.add_child(b)
		grid.add_child(card)


func _skills() -> void:
	_box.add_child(UITheme.title("Skills", 21))
	_box.add_child(UITheme.label("Click a skill to put a point in it. Lit outlines are ready to buy; deeper skills need one before them and a higher level (2, 5, 10).",
		14, Color(1, 1, 1, 0.6)))
	_tree = SkillTreeView.new()
	_box.add_child(_tree)
	_skill_info = UITheme.label("Point at a skill to read what it does.", 15, Color(1, 1, 1, 0.85))
	_skill_info.custom_minimum_size.y = 44
	_box.add_child(_skill_info)
	_tree.hovered.connect(func(id: String): _skill_info.text = _skill_text(id))
	_tree.chosen.connect(func(id: String):
		var err := Progress.buy_skill(id)
		if err != "":
			_skill_info.text = "%s: %s" % [Progress.SKILLS[id]["name"], err]
		else:
			Sfx.play_ui("clink", -6.0))
	var respec := Button.new()
	respec.text = "Respec: take back every skill point"
	respec.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	respec.pressed.connect(func(): Progress.respec())
	_box.add_child(respec)


func _skill_text(id: String) -> String:
	if id == "":
		return "Point at a skill to read what it does."
	var sk: Dictionary = Progress.SKILLS[id]
	var rank := Progress.skill_rank(Shed.me(), id)
	var why := Progress.skill_block(id)
	return "%s (%s, rank %d of %d): %s%s" % [sk["name"], Progress.BRANCH_NAMES[sk["branch"]], rank, sk["ranks"], sk["desc"],
		"" if why == "" else "  [%s]" % why]


func _goals() -> void:
	_box.add_child(UITheme.title("Goals", 21))
	for g in Progress.own_summary()["goals"]:
		var done: bool = g["done"]
		var need := float(g["need"])
		var have := minf(float(g["have"]), need)
		var count := "" if done else ("  (%s / %s)" % [_num(have), _num(need)])
		_box.add_child(UITheme.label("%s  %s%s   +%d XP" % ["✔" if done else "○", g["text"], count, g["xp"]], 15,
			Color(0.55, 0.9, 0.55) if done else Color(1, 1, 1, 0.8)))


static func _num(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.01 or v >= 10.0 else "%.1f" % v
