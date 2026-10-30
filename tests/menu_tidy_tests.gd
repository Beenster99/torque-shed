extends RefCounted
## The tidied menus (v0.39.0): the garage's panel without its Workshop tab (the adventure buttons
## now on the Esc menu itself), the Controller tab without its Controls list, and a compact
## Gameplay tab. Run from tests/run_tests.gd (its _test_menu_tidy_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

## The Gameplay tab's rows must fit in this many pixels (the Settings panel shows about 560 of
## them below its tab bar: the tidied tab takes about 550, so it fits without scrolling; before the tidy it took
## about 1320, and was wider than the panel too).
const GAMEPLAY_MAX_HEIGHT := 600.0


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


static func _tab_names(tabs: TabContainer) -> Array:
	var out := []
	for i in tabs.get_tab_count():
		out.append(tabs.get_tab_title(i))
	return out


## An Esc menu, open in the shed, for the checks.
func _menu() -> MainMenu:
	Shed.start_new("Tester", 5)
	var menu := MainMenu.new()
	t.add_child(menu)
	await _frames(2)
	menu.show_pause()
	await _frames(2)
	return menu


## Simon: "remove Workshop menu on company page". The garage's panel has no Workshop tab; the
## adventure buttons sit on the Esc menu, ordering a project bike is the parts computer's,
## building from a blueprint the Blueprints tab's and geometry mode its key's.
func test_no_workshop() -> void:
	var menu: MainMenu = await _menu()
	var garage := _tab_names(menu._garage_tabs)
	check(not garage.has("Workshop"), "the garage's panel has no Workshop tab (%s)" % ", ".join(garage))
	for want in ["Money", "Staff", "Contracts", "Recovery truck", "Blueprints"]:
		check(garage.has(want), "the garage's panel still has %s" % want)
	check(not menu._garage_badge.tooltip_text.to_lower().contains("workshop"), "the garage badge no longer mentions a workshop")
	check(menu._pause_box.is_ancestor_of(menu._adventure) and menu._pause_box.is_ancestor_of(menu._continue_adventure)
		and menu._pause_box.is_ancestor_of(menu._paper_map), "the adventure buttons are on the Esc menu")
	check(menu._adventure.is_visible_in_tree() and menu._adventure.text == "Adventure ride" and not menu._adventure.disabled,
		"Adventure ride shows on the Esc menu: %s" % menu._adventure.text)
	check(menu._adventure.tooltip_text.contains("Route planner"), "its explanation is in its tooltip")
	check(menu._adventure.get_combined_minimum_size().x <= 420.0, "and it keeps the Esc menu narrow")
	check(not menu._continue_adventure.visible and not menu._paper_map.visible, "no Continue adventure or paper map with none on")
	var texts := menu.find_children("*", "Button", true, false).map(func(b): return (b as Button).text)
	check(not texts.any(func(x): return x.begins_with("Order a project bike") or x.begins_with("Build from blueprint") or x.begins_with("Geometry mode")),
		"no Order a project bike, Build from blueprint or Geometry mode buttons left in the menus")
	var computer := (load("res://scripts/parts_computer.gd") as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	check(computer.has("order_bike"), "the parts computer still orders project bikes")
	check(Settings.ACTIONS.any(func(a): return a[0] == "geometry_mode"), "geometry mode's key is on the Key bindings list")
	menu.show_blueprints()
	check(menu._garage_tabs.get_current_tab_control() == menu.blueprints, "blueprints still open on their own tab")
	menu.queue_free()
	await _frames(1)


## Simon: "remove the controls sub tab under controller in settings". The Controller tab has the
## key bindings and the controller check only.
func test_no_controls_list() -> void:
	var menu: MainMenu = await _menu()
	check(_tab_names(menu._controller) == ["Key bindings", "Controller check"],
		"the Controller tab: %s" % ", ".join(_tab_names(menu._controller)))
	check(menu._controller.get_current_tab_control() == menu.keybinds, "it opens on the key bindings")
	menu.queue_free()
	await _frames(1)


## Simon: "tidy up and make more compact the Gameplay settings tab". Short headings, toggles two
## to a row, each slider with its label and value on one line, and every setting still there and
## working; it all fits with far less scrolling.
func test_gameplay_compact() -> void:
	var menu: MainMenu = await _menu()
	menu.toggle_panel(menu._tabs)
	menu._tabs.current_tab = menu._tabs.get_tab_idx_from_control(menu._gameplay)
	await _frames(3)
	var box := menu._gameplay.get_child(0) as Control
	var tall := box.get_combined_minimum_size().y
	var shown := (menu._gameplay as Control).size.y
	print("    Gameplay tab: %.0f px of rows in %.0f px of panel" % [tall, shown])
	check(tall < GAMEPLAY_MAX_HEIGHT, "the Gameplay tab is compact: %.0f px of rows (under %.0f)" % [tall, GAMEPLAY_MAX_HEIGHT])
	check(box.get_combined_minimum_size().x <= 760.0, "and no wider than the panel (%.0f px)" % box.get_combined_minimum_size().x)
	var heads := box.get_children().filter(func(c): return c is Label).map(func(c): return (c as Label).text)
	for want in ["Riding", "Camera", "Sat nav", "Units and placing", "Time and weather"]:
		check(heads.has(want), "a %s heading" % want)
	# Every setting is still there, inside the tab, and does what it did.
	var checks := []
	for c in box.find_children("*", "CheckBox", true, false):
		checks.append((c as CheckBox).text)
	for start in ["Automatic gearbox", "Direct bars", "Telemetry overlay", "Look into corners", "Chase camera recentres",
			"Third person on foot", "Sat nav on the HUD", "Satellite view", "Portrait", "Snap to walls", "Free rotate", "Day/night cycle"]:
		check(checks.any(func(x): return x.begins_with(start)), "a %s toggle" % start)
	for n in [menu._auto, menu.look_corner, menu._third_person, menu._snap, menu._free_rotate, menu._cycle, menu._assist,
			menu._day_length, menu._time, menu._weather]:
		check(menu._gameplay.is_ancestor_of(n), "%s is on the Gameplay tab" % n.name)
	check(menu._satnav_checks.size() == 3 and menu._satnav_sliders.size() == 4, "the sat nav's toggles and sliders are all kept in step")
	# Toggles sit two to a row, with the long explanations in tooltips.
	var grid := menu._auto.get_parent() as GridContainer
	check(grid != null and grid.columns == 2, "the toggles sit in two columns")
	check(menu.look_corner.tooltip_text.contains("heads turn"), "the long explanations moved into tooltips")
	# A slider has its label and its value on the same row.
	var row := menu._assist.get_parent() as HBoxContainer
	check(row != null and row.get_child(0) is Label and row.get_child(row.get_child_count() - 1) is Label,
		"Riding realism's label and value share its row")
	var was := Settings.assist
	menu._assist.value = 0.0
	var value := row.get_child(row.get_child_count() - 1) as Label
	check(value.text.begins_with("0.00") and menu._assist.tooltip_text == MainMenu.realism_text(0.0), "its value shows, what it means in the tooltip: %s" % value.text)
	menu._assist.value = was
	check(is_equal_approx(Settings.assist, was), "and it still sets Riding realism")
	for s in menu._satnav_sliders:
		var line := (s[0] as Control).get_parent() as GridContainer
		check(line != null and line.columns == 6, "the %s slider shares a row with its label and value" % str(s[1]))
	var was_auto := Settings.auto_shift
	menu._auto.button_pressed = not was_auto
	check(Settings.auto_shift == not was_auto, "ticking a toggle still sets it")
	menu._auto.button_pressed = was_auto
	menu.queue_free()
	await _frames(1)


## Simon: "Remove the Adventure (host) section of the Debug menu but keep the "End Adventure" button and make it
## accessible to all users. If a guest ends an adventure they leave, if the host ends an adventure everyone has to
## leave". The Debug tab has no adventure section; the Esc menu's adventure button ends it for everyone (the host,
## after asking) or leaves it (a guest: off the ride, their bike left at the roadside brought home, the rest riding on).
## (The two-machine run of a guest leaving is in tests/mp_adventure.gd.)
func test_leave() -> void:
	Shed.start_new("Tester", 5)
	var debug := DebugTab.new()
	t.add_child(debug)
	await _frames(1)
	var words := debug.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	words.append_array(debug.find_children("*", "BaseButton", true, false).map(func(b): return str((b as BaseButton).get("text"))))
	check(not words.has("Adventure (host)") and not words.any(func(x): return x in ["Start adventure", "End adventure", "Skip 1 km ahead", "Skip 10 km ahead"]),
		"the Debug tab has no Adventure (host) section")
	check(debug.find_child("RoadNetworkToggle", true, false) != null and debug.find_child("SceneryStandinsToggle", true, false) != null,
		"its road network and scenery marker toggles are kept")
	debug.queue_free()
	# A guest leaves: off the ride on their own, the host and the rest riding on.
	Shed.crew[2] = {"name": "Guest", "riding": 0}
	var bike: int = Shed.bikes.keys()[0]
	Shed.bikes[bike]["roadside"] = true
	Shed.bikes[bike]["rider"] = 0
	Shed.adventure = {"id": 77, "plan": {}, "km": 40.0, "riders": {1: 0, 2: bike}, "left": [], "arrived": 0}
	check(str(Adventure.menu_text()[0]).begins_with("End the adventure for everyone"), "the host's button ends it for everyone: %s" % Adventure.menu_text()[0])
	check(Adventure.check(1, {"a": "adventure_leave"}) != "", "the host doesn't just leave: it ends for everyone")
	var said := Adventure.apply(2, {"a": "adventure_leave"})
	check(said.contains("Guest has left the adventure"), "the crew is told: %s" % said)
	check(Adventure.active() and Adventure.has_left(2) and not Adventure.has_left(1), "the adventure carries on without the guest")
	check(not (Shed.adventure["riders"] as Dictionary).has(2) and (Shed.adventure["riders"] as Dictionary).has(1), "the guest is off the ride, the host on it")
	check(not Shed.bikes[bike].has("roadside"), "the guest's bike left at the roadside is brought home")
	check(Adventure.check(2, {"a": "adventure_join"}) != "" and Adventure.check(2, {"a": "adventure_leave"}) != "",
		"a guest who's left doesn't join it again, nor leave twice")
	var kept: Dictionary = Shed.adventure.duplicate(true)
	kept["plan"] = {"region": "x"}
	check(Adventure.sanitize(kept).get("left", []) == [2], "who's left goes round with the adventure")
	# The host's button asks first, then ends it for everyone.
	var menu: MainMenu = await _menu()
	Shed.adventure = {"id": 78, "plan": {}, "km": 40.0, "riders": {1: 0}, "left": [], "arrived": 0}
	menu._refresh_adventure()
	check(menu._adventure.text == "End the adventure for everyone" and not menu._adventure.disabled and menu._adventure.is_visible_in_tree(),
		"the host's Esc menu offers: %s" % menu._adventure.text)
	menu._adventure.pressed.emit()
	await _frames(1)
	check(Adventure.active() and menu._confirm.visible, "it asks first")
	menu._confirm.confirmed.emit()
	await _frames(1)
	check(not Adventure.active(), "and then ends it for everyone")
	Shed.crew.erase(2)
	menu.queue_free()
	await _frames(1)
