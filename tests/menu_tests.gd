extends RefCounted
## The Esc menu's layout (see MainMenu): its short list of buttons, the Settings panel's tabs,
## and the corner badges that open the garage's panel and yours; and the Debug tab with no bike
## fixing on it. Run from tests/run_tests.gd:
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


## Esc: Continue, Settings, the adventure ride, saving, Leave and return to title and Exit game, and nothing else;
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
	check(shown == ["Continue", "Settings", "Adventure ride", "Save now", "Save as...", "Save games...", "Leave and return to title", "Exit game"],
		"the Esc menu is short: %s" % ", ".join(shown))
	for gone in ["Back to the shed", "Order a project bike", "Build from blueprint"]:
		check(not shown.has(gone), "no %s button in the Esc menu" % gone)
	check(menu.open_panel() == null, "it opens with no panel beside it")
	menu._settings_button.pressed.emit()
	check(menu.open_panel() == menu._tabs and _tab_names(menu._tabs) == ["Graphics", "Sound", "Gameplay", "Controller", "Debug"],
		"Settings opens its tabs: %s" % ", ".join(_tab_names(menu._tabs)))
	check(_tab_names(menu._controller) == ["Key bindings", "Controller check"], "the Controller tab has the key bindings and the pad check")
	check(menu._gameplay.is_ancestor_of(menu._auto) and menu.debug.get_parent() == menu._tabs,
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
	check(menu._pause_box.is_ancestor_of(menu._adventure) and menu.blueprints.get_parent() == menu._garage_tabs,
		"adventures on the Esc menu, blueprints on the garage's panel")
	menu._profile_badge.pressed.emit()
	await _frames(1)
	check(menu.open_panel() == menu._profile_tabs and _tab_names(menu._profile_tabs) == ["Profile", "Character", "Shop", "Bike shop"],
		"the profile picture opens your profile, character, shop and bike shop")
	check(menu._profile_info.text.contains("Your cash"), "with your profile information")
	menu._profile_badge.pressed.emit()
	check(menu.open_panel() == null, "clicking it again closes it")
	menu.show_blueprints()
	check(menu.open_panel() == menu._garage_tabs and menu._garage_tabs.get_current_tab_control() == menu.blueprints, "Build from blueprint opens the garage's Blueprints tab")
	menu.show_title()
	check(not menu._garage_badge.visible and not menu._profile_badge.visible, "no badges on the title screen")
	menu.queue_free()
	await _frames(1)


## Debug: there's no fixing a bike up any more (Simon: "remove fixing bike from debug menu"),
## and no punctures to give one.
func test_fix_bike() -> void:
	Shed.start_new("Tester", 81)
	var tab := DebugTab.new()
	t.add_child(tab)
	await _frames(1)
	var texts := tab.find_children("*", "BaseButton", true, false).map(func(b): return str((b as BaseButton).get("text")))
	check(not texts.any(func(x): return x.contains("Fix my bike") or x.contains("fix my bike") or x.contains("puncture")),
		"the Debug tab has no bike fixing or puncture buttons")
	check(not tab.has_method("fix_bike") and not Shed.has_method("debug_fix_bike"), "nor anything behind them")
	tab.queue_free()
	await _frames(1)


## The opening film (SplashVideo): a headless run never plays it, and played anyway it shows
## the film over everything, a key press skips it, and it fades away and is gone.
func test_splash() -> void:
	check(SplashVideo.play_over(t) == null, "splash: a headless run plays no opening film")
	check(ResourceLoader.exists(SplashVideo.PATH), "splash: the opening film is in the game")
	var s := SplashVideo.new()
	t.add_child(s)
	await _frames(3)
	check(s.player.stream != null and s.player.is_playing(), "splash: the film plays")
	check(s.layer > 1, "splash: the film shows over the title screen")
	var ended := [false]
	s.finished.connect(func(): ended[0] = true)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	await t.get_tree().create_timer(SplashVideo.FADE + 0.3).timeout
	check(ended[0], "splash: a key press skips the film")
	check(not is_instance_valid(s), "splash: the skipped film is gone")
