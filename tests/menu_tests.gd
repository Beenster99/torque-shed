extends RefCounted
## The Esc menu's layout (see MainMenu): its short list of buttons, the Settings panel's tabs,
## and the corner badges that open the garage's panel and yours; and the Debug tab fixing a bike
## up, now or by itself while riding (see Shed.debug_fix_bike). Run from tests/run_tests.gd:
## its _test_menu_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## The buttons showing in `box`, top to bottom (rows of buttons read left to right).
static func _shown_buttons(box: Control) -> Array:
	var out := []
	for b in box.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			out.append((b as Button).text)
	return out


static func _tab_names(tabs: TabContainer) -> Array:
	var out := []
	for i in tabs.get_tab_count():
		out.append(tabs.get_tab_title(i))
	return out


## Esc: Continue, Settings, saving, Leave and return to title and Exit game, and nothing else;
## Settings opens Graphics, Sound, Gameplay, Controller and Debug; the garage's badge (top left)
## opens Money, Staff, Contracts and the Recovery truck; the profile picture (top right) opens
## your profile, Character and the Shop.
func test_layout() -> void:
	Shed.start_new("Tester", 5)
	var menu := MainMenu.new()
	t.add_child(menu)
	await _frames(2)
	menu.show_pause()
	await _frames(2)
	var col := menu._pause_box.get_parent() as Control
	var shown := _shown_buttons(col)
	check(shown == ["Continue", "Settings", "Save now", "Save as...", "Save games...", "Leave and return to title", "Exit game"],
		"the Esc menu is short: %s" % ", ".join(shown))
	for gone in ["Back to the shed", "Adventure ride", "Order a project bike", "Build from blueprint"]:
		check(not shown.has(gone), "no %s button in the Esc menu" % gone)
	check(menu.open_panel() == null, "it opens with no panel beside it")
	menu._settings_button.pressed.emit()
	check(menu.open_panel() == menu._tabs and _tab_names(menu._tabs) == ["Graphics", "Sound", "Gameplay", "Controller", "Debug"],
		"Settings opens its tabs: %s" % ", ".join(_tab_names(menu._tabs)))
	check(_tab_names(menu._controller) == ["Controls", "Key bindings", "Controller check"], "the Controller tab has the controls, key bindings and the pad check")
	check(menu._auto.get_parent().get_parent() == menu._gameplay and menu.debug.get_parent() == menu._tabs,
		"riding settings under Gameplay, the testing helpers under Debug")
	var screen := t.get_viewport().get_visible_rect()
	var g := menu._garage_badge.get_global_rect()
	var p := menu._profile_badge.get_global_rect()
	check(menu._garage_badge.visible and g.position.x < 40.0 and g.position.y < 40.0, "the garage's badge sits in the top left corner")
	check(menu._profile_badge.visible and screen.end.x - p.end.x < 40.0 and p.position.y < 40.0 and screen.encloses(p),
		"the profile picture sits in the top right corner")
	check(menu._garage_badge.text.contains("Account"), "the garage's badge has its name and account: %s" % menu._garage_badge.text.replace("\n", " / "))
	check(menu._profile_badge.text.begins_with(menu.player_name()) and menu._profile_badge.text.contains("Level"),
		"the profile badge has your name and level: %s" % menu._profile_badge.text.replace("\n", " / "))
	menu._garage_badge.pressed.emit()
	var garage := _tab_names(menu._garage_tabs)
	check(menu.open_panel() == menu._garage_tabs and not menu._tabs.visible, "the garage's badge opens its panel in place of Settings")
	for want in ["Money", "Staff", "Contracts", "Recovery truck"]:
		check(garage.has(want), "the garage's panel has %s (%s)" % [want, ", ".join(garage)])
	check(menu._adventure.get_parent().get_parent().name == "Workshop" and menu.blueprints.get_parent() == menu._garage_tabs,
		"adventures, project bikes and blueprints moved to the garage's panel")
	menu._profile_badge.pressed.emit()
	await _frames(1)
	check(menu.open_panel() == menu._profile_tabs and _tab_names(menu._profile_tabs) == ["Profile", "Character", "Shop"],
		"the profile picture opens your profile, character and shop")
	check(menu._profile_info.text.contains("Your cash"), "with your profile information")
	menu._profile_badge.pressed.emit()
	check(menu.open_panel() == null, "clicking it again closes it")
	menu.show_blueprints()
	check(menu.open_panel() == menu._garage_tabs and menu._garage_tabs.get_current_tab_control() == menu.blueprints, "Build from blueprint opens the garage's Blueprints tab")
	menu.show_title()
	check(not menu._garage_badge.visible and not menu._profile_badge.visible, "no badges on the title screen")
	menu.queue_free()
	await _frames(1)


## Debug: Fix my bike now puts the bike right (wear, punctures, faults, the chain, fuel), and the
## automatic fix does it by itself whenever the bike you're riding needs it.
func test_fix_bike() -> void:
	Shed.start_new("Tester", 81)
	var me := Shed.me()
	var bike: int = t._bike_named("Old Faithful")
	var tyre := Shed.item_on(bike, "rear_tyre")
	var chain := Shed.item_on(bike, "chain")
	var tank := Shed.item_on(bike, "tank")
	var wreck := func() -> void:
		for id in Shed.bikes[bike]["slots"].values():
			if not Shed.items.has(int(id)):
				continue
			Shed.items[int(id)]["wear"] = 0.6
			Shed.items[int(id)]["rust"] = 0.3
		Shed.puncture_tyre(bike, "rear", "fast", 1.2)
		Shed.items[chain]["slack"] = 50.0
		Shed.bikes[bike]["faults"] = {"lever": "clutch"}
		if tank != 0:
			Shed.items[tank]["fluid"] = {"type": "unleaded", "litres": 0.5, "age": 0.0}
	wreck.call()
	check(DebugTab.needs_fix(bike) and not Roadside.active(bike).is_empty(), "a worn bike, a puncture, a slack chain and a snapped lever")
	var tab := DebugTab.new()
	t.add_child(tab)
	Shed.bikes[bike]["rider"] = me
	Shed.crew[me]["riding"] = bike
	tab.fix_bike()
	check(Roadside.active(bike).is_empty() and not Puncture.punctured(Shed.items[tyre]) and float(Shed.items[tyre]["wear"]) == 0.0
		and float(Shed.items[chain]["slack"]) == Shed.CHAIN_SLACK_SET, "Fix my bike now: no faults, the tyre holds, the chain's set")
	check(tank == 0 or Shed.fuel_space(bike) < 0.01, "and the tank's brimmed")
	check(not DebugTab.needs_fix(bike), "nothing left to fix")
	# The automatic fix, while riding.
	wreck.call()
	tab.auto_fix_tick(10.0)
	check(DebugTab.needs_fix(bike), "off, the automatic fix leaves it alone")
	tab.auto_fix = true
	tab.auto_fix_tick(10.0)
	check(not DebugTab.needs_fix(bike), "on, it fixes the bike you're riding as soon as it needs it")
	Shed.items[chain]["wear"] = 0.05
	check(not DebugTab.needs_fix(bike), "a little wear isn't worth a fix")
	Shed.crew[me]["riding"] = 0
	Shed.bikes[bike]["rider"] = 0
	tab.queue_free()
	await _frames(1)
