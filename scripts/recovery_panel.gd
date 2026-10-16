class_name RecoveryPanel
extends Control
## The recovery jobs clipboard (the truck's passenger door, or Esc, Recovery): the barn finds
## and crash rescues on offer with Accept and Decline, the ones out to fetch with where they
## are, and for a bike brought back to the yard its assessment: every part's condition, what
## putting it right would cost and what it's worth, and the three choices (buy it, break it for
## parts, or repair it for the insurer). An insurer job shows what's still to do and Collect.

signal closed

var job_id := 0               # the job whose assessment is open, 0 for the list
var _box: VBoxContainer
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	Shed.changed.connect(func(): if visible: _refresh())


func open_list() -> void:
	job_id = 0
	_sig = ""
	visible = true
	_refresh()


func open_assessment(id: int) -> void:
	job_id = id
	_sig = ""
	visible = true
	_refresh()


func close_dialog() -> void:
	visible = false
	closed.emit()


## Presses the button labelled `text` (for tests); true when there was one to press.
func press(text: String) -> bool:
	for b in _box.find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not b.is_queued_for_deletion():
			(b as Button).pressed.emit()
			return true
	return false


func _refresh() -> void:
	if job_id != 0 and not Recovery.jobs().has(job_id):
		job_id = 0
	var sig := str(job_id) + signature()
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	var self_ref := self
	if job_id != 0:
		fill_assessment(_box, Recovery.jobs()[job_id], func(): self_ref.open_list())
		_box.add_child(ContractPanel.button("Back to the list", open_list))
	else:
		_box.add_child(UITheme.title("RECOVERY JOBS", 24))
		fill(_box, func(id): self_ref.open_assessment(id))
	_box.add_child(ContractPanel.button("Close (Esc)", close_dialog))


## Changes to anything the list shows, so it's only rebuilt when they happen.
static func signature() -> String:
	var bits := [Recovery.owned(), Recovery.offers().keys(), Shed.garage_money, Recovery._st()["done"].size()]
	for id in Recovery.jobs():
		var j: Dictionary = Recovery.jobs()[id]
		bits.append([id, j["state"], Recovery.is_loaded(int(j["bike"])), Recovery.insurer_left(j) if str(j["state"]) == "insurer" else []])
	return str(bits)


## Fills `box` with the offers, the jobs under way and the last few done. `assess` opens a
## delivered job's assessment (by id).
static func fill(box: VBoxContainer, assess: Callable) -> void:
	if not Recovery.owned():
		var lv := Recovery.LEVEL
		box.add_child(UITheme.label("The garage hasn't got a recovery truck. At character level %d (you're level %d) you can buy the truck and bike trailer from the parts computer's Garage upgrades (Vehicles), and then the phone rings with barn finds and crash rescues to fetch." % [
			lv, Progress.level()], 15, Color(1, 1, 1, 0.75)))
		return
	var me := Shed.me()
	box.add_child(UITheme.label("ON OFFER", 15, UITheme.ACCENT))
	if Recovery.offers().is_empty():
		box.add_child(UITheme.label("Nothing on offer right now: the phone rings when a job comes in.", 14, Color(1, 1, 1, 0.6)))
	for id in Recovery.offers():
		var o: Dictionary = Recovery.offers()[id]
		box.add_child(UITheme.title("%s: %s" % [Recovery.KIND_NAMES[str(o["kind"])], str(o["name"]).capitalize()], 19))
		var who := "%s, %s" % [o["contact"], "the owner" if str(o["kind"]) == "barn" else "for %s" % o["insurer"]]
		box.add_child(UITheme.label("\"%s\"  (%s)" % [o["blurb"], who], 15, Color(1, 1, 1, 0.75)))
		box.add_child(UITheme.label("A %s at %s, %.1f km from the yard. %s Call-out fee %s on delivery." % [o["model"], o["site"],
			float(o["km"]), "It may not roll." if not bool(o["rolls"]) else "", Recovery.money(int(o["fee"]))], 15))
		var why := Shed.check(me, {"a": "recovery_accept", "offer": int(id)})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var acc := ContractPanel.button("Accept", func(): Shed.request({"a": "recovery_accept", "offer": int(id)}))
		acc.disabled = why != ""
		acc.tooltip_text = why
		row.add_child(acc)
		row.add_child(ContractPanel.button("Decline", func(): Shed.request({"a": "recovery_decline", "offer": int(id)})))
		box.add_child(row)
		if why != "":
			box.add_child(UITheme.label(why, 14, Color(1, 0.5, 0.4)))
	box.add_child(UITheme.label("UNDER WAY", 15, UITheme.ACCENT))
	if Recovery.jobs().is_empty():
		box.add_child(UITheme.label("No recoveries under way.", 14, Color(1, 1, 1, 0.6)))
	for id in Recovery.jobs():
		var j: Dictionary = Recovery.jobs()[id]
		box.add_child(UITheme.title(str(j["name"]).capitalize(), 19))
		var bike_id := int(j["bike"])
		match str(j["state"]):
			"collect":
				var where := "on the trailer, strapped down" if Recovery.secure(bike_id) else ("on the trailer, NOT strapped down"
					if Recovery.is_loaded(bike_id) else "waiting at %s" % j["site"])
				box.add_child(UITheme.label("To fetch: %s. %s" % [where, "It won't roll: take the dolly tray." if not bool(j["rolls"])
					else "It rolls: winch it up the ramp."], 15))
			"delivered":
				box.add_child(UITheme.label("In the yard. Assess it and decide what to do with it.", 15))
				box.add_child(ContractPanel.button("Assess it", func(): assess.call(int(id))))
			"insurer":
				var left := Recovery.insurer_left(j)
				box.add_child(UITheme.label("Repair for %s, paying %s. %s" % [j["insurer"], Recovery.money(int(j.get("pay", 0))),
					"Still to do: %s." % ", ".join(left) if not left.is_empty() else "Up to spec."], 15,
					Color(0.5, 0.95, 0.55) if left.is_empty() else Color(0.85, 0.87, 0.9)))
				var why2 := Shed.check(me, {"a": "recovery_collect", "job": int(id)})
				var col := ContractPanel.button("Insurer collects", func(): Shed.request({"a": "recovery_collect", "job": int(id)}))
				col.disabled = why2 != ""
				col.tooltip_text = why2
				box.add_child(col)
	var done: Array = Recovery._st()["done"]
	if not done.is_empty():
		box.add_child(UITheme.label("DONE", 15, UITheme.ACCENT))
		for d in done.slice(0, 6):
			box.add_child(UITheme.label("Day %d  %s  ·  %s  ·  net %s" % [int(d["day"]), str(d["name"]).capitalize(), d["outcome"],
				Recovery.money(int(d["net"]))], 14, Color(1, 1, 1, 0.75)))


## The assessment of a delivered bike: its parts, the repair estimate and the three choices.
static func fill_assessment(box: VBoxContainer, job: Dictionary, after: Callable) -> void:
	var bike_id := int(job["bike"])
	var a := Recovery.assess(bike_id, job)
	box.add_child(UITheme.title("ASSESSMENT: %s" % str(job["name"]).to_upper(), 22))
	box.add_child(UITheme.label("%s  ·  %s  ·  %s" % [Recovery.KIND_NAMES[str(job["kind"])], Shed.bikes[bike_id]["name"],
		"owner %s" % job["contact"] if str(job["kind"]) == "barn" else "%s's customer, %s" % [job["insurer"], job["contact"]]], 15, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for h in ["Part", "Condition", "Needs", "Cost"]:
		grid.add_child(UITheme.label(h, 13, UITheme.ACCENT))
	for r in a["rows"]:
		var hp := float(r["health"])
		var col := Color(0.5, 0.95, 0.55) if hp >= 0.8 else (Color(1.0, 0.8, 0.35) if hp >= 0.4 else Color(1.0, 0.45, 0.35))
		grid.add_child(UITheme.label(str(r["name"]), 13))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 14)
		bar.max_value = 100.0
		bar.value = hp * 100.0
		bar.show_percentage = false
		bar.modulate = col
		bar.tooltip_text = str(r["text"])
		grid.add_child(bar)
		grid.add_child(UITheme.label({"ok": "fine", "restore": "restore", "replace": "REPLACE"}[str(r["fix"])], 13, col))
		grid.add_child(UITheme.label(Recovery.money(int(r["cost"])) if int(r["cost"]) > 0 else "-", 13))
	box.add_child(UITheme.label("Estimated repair: %s  ·  worth %s as it stands, about %s put right." % [Recovery.money(int(a["repair"])),
		Recovery.money(int(a["now"])), Recovery.money(int(a["fixed"]))], 17, Color(1, 1, 1, 0.9)))
	var me := Shed.me()
	var choices := [
		["Buy it for %s" % Recovery.money(int(a["buy"])), "recovery_buy",
			"Pay %s their price and it's the garage's own project bike." % job["contact"]],
		["Break it for parts (%s)" % Recovery.money(int(a["salvage"])), "recovery_salvage",
			"Pay less for it as spares: every part comes off into the delivery area and the frame goes for scrap."],
		["Do the work for the insurer (pays %s)" % Recovery.money(int(a["insurer"])), "recovery_insurer",
			"%s pays you to put the damaged parts right (to %d%% or better), then they collect it." % [job["insurer"],
				roundi(Recovery.INSURER_HEALTH * 100.0)]],
	]
	for c in choices:
		var act := {"a": str(c[1]), "job": int(job["id"])}
		var why := Shed.check(me, act)
		var b := ContractPanel.button(str(c[0]), func():
			Shed.request(act)
			after.call())
		b.disabled = why != ""
		b.tooltip_text = why
		box.add_child(b)
		box.add_child(UITheme.label(str(c[2]) if why == "" else why, 13, Color(1, 1, 1, 0.6) if why == "" else Color(1, 0.5, 0.4)))
