extends RefCounted
## The Bike shop (BikeShop, BikeShopTab): second-hand bikes and the new-bike configurator, run
## from tests/run_tests.gd (its _test_bike_shop_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## The bike that's new in the shed since `before` (its ids), or 0.
static func _new_bike(before: Array) -> int:
	for b in Shed.bikes:
		if not before.has(b):
			return int(b)
	return 0


## Today's list: every style for sale, from tired to immaculate, the same all day and different
## the next, each a real build, cheaper the more worn it is.
func test_for_sale() -> void:
	Shed.start_new("Tester", 51)
	var today := BikeShop.for_sale(20000)
	var styles := {}
	var bad := []
	var q_lo := 1.0
	var q_hi := 0.0
	for l in today:
		styles[str(l["style"])] = true
		q_lo = minf(q_lo, float(l["quality"]))
		q_hi = maxf(q_hi, float(l["quality"]))
		var parts: Dictionary = l["parts"]
		if PartsDB.sanitize_build(parts.duplicate()) != parts or int(l["miles"]) <= 0 or str(l["seller"]) == "":
			bad.append(str(l["title"]))
	check(today.size() == BikeShop.FOR_SALE and styles.size() == PartsDB.STYLES.size() and bad.is_empty() and q_lo >= 0.3 and q_hi <= 0.95,
		"%d bikes for sale, every style, real builds, %d%% to %d%% %s" % [today.size(), roundi(q_lo * 100.0), roundi(q_hi * 100.0), bad])
	var again := BikeShop.for_sale(20000)
	var tomorrow := BikeShop.for_sale(20001)
	check(str(again.map(func(l): return l["title"])) == str(today.map(func(l): return l["title"]))
		and str(tomorrow.map(func(l): return [l["title"], l["miles"]])) != str(today.map(func(l): return [l["title"], l["miles"]])),
		"the same list all day, another tomorrow")
	var l0: Dictionary = today[0]
	var src := BikeShop.src_of(str(l0["title"]), l0["parts"], l0["paint"])
	var used := BikeShop.price(src, float(l0["quality"]))
	var new := BikeShop.price(src, 1.0)
	check(used > 0 and used < new, "%s is %s, %s new" % [str(l0["title"]), TvChannels.money_text(used), TvChannels.money_text(new)])
	Shed.stop()


## Buying a second-hand bike: it comes built and ready to ride, as worn as it was listed, named
## for whoever bought it, paid from their own money.
func test_buy_used() -> void:
	Shed.start_new("Tester", 52)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(1000000)
	var list := BikeShop.for_sale(20000).filter(func(l): return float(l["quality"]) <= 0.6)
	var l: Dictionary = list[0]
	var cost := BikeShop.price(BikeShop.src_of(str(l["title"]), l["parts"], l["paint"]), float(l["quality"]))
	var before: Array = Shed.bikes.keys()
	var money := Progress.money()
	check(BikeShop.buy_used(l) == "", "buying %s goes through" % str(l["title"]))
	var id := _new_bike(before)
	var worn := 0.0
	var n := 0
	if id != 0:
		for slot in PartsDB.SLOTS:
			var it := Shed.item_on(id, slot)
			if it != 0:
				worn += float(Shed.items[it]["wear"]) + float(Shed.items[it]["dirt"])
				n += 1
	check(id != 0 and Shed.is_complete(id) and Money.rideable(id) and n > 0 and worn / n > 0.1 and str(Shed.bikes[id]["name"]).begins_with("Tester's")
		and Progress.money() == money - cost and int(Shed.bikes[id]["bay"]) == -1,
		"it's in the yard, built and rideable, worn in (%.2f a part), named %s, for %s" % [worn / maxf(n, 1.0), Shed.bikes.get(id, {}).get("name", "?"), TvChannels.money_text(cost)])
	Progress.profile = saved
	Shed.stop()


## The configurator: a style's stock build, its parts changed slot by slot from the ones that
## suit it, its colours picked; ordered, it comes new in those parts and colours. The tab shows
## the list and the configurator, and the price on the button.
func test_configurator() -> void:
	Shed.start_new("Tester", 53)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(1000000)
	var tab := BikeShopTab.new()
	t.add_child(tab)
	await _frames(1)
	tab.show_mode("used")
	check(tab.find_children("Listing*", "Button", true, false).size() == BikeShop.FOR_SALE and tab._buy.text.begins_with("Buy it for"),
		"the second-hand list, with the price on the button (%s)" % tab._buy.text)
	tab._new_style("naked")
	tab.show_mode("new")
	var exhausts := BikeShop.options("exhaust", "naked", tab.parts)
	var other: String = exhausts.filter(func(e): return e != str(tab.parts["exhaust"]) and e != "none")[0]
	tab.set_part("exhaust", other)
	# Picking from a dropdown rebuilds the list, but only once the dropdown has finished sending
	# its signal: freeing it mid-signal crashed the game (v0.42.0).
	var sb: OptionButton = tab.find_child("Slot_saddle", true, false)
	var saddles := BikeShop.options("saddle", "naked", tab.parts)
	var bi := saddles.find(saddles.filter(func(e): return e != str(tab.parts["saddle"]))[0])
	sb.item_selected.emit(bi)
	var kept := is_instance_valid(sb)
	await _frames(1)
	var sty: OptionButton = tab.find_child("Style", true, false)
	sty.item_selected.emit(PartsDB.STYLES.find("cafe"))
	kept = kept and is_instance_valid(sty)
	await _frames(1)
	check(kept and not is_instance_valid(sb) and tab.style == "cafe" and tab.find_child("Slot_saddle", true, false) != null,
		"a part or style picked from its dropdown rebuilds the list after the dropdown is done with it, not under it")
	tab._new_style("naked")
	tab.show_mode("new")
	tab.set_part("exhaust", other)
	var red := Color(0.8, 0.1, 0.1)
	var gold := Color(0.8, 0.62, 0.2)
	tab.set_colour("frame", red)
	tab.set_colour("wheels", gold)
	check(tab.find_child("Slot_exhaust", true, false) != null and tab.find_child("Colour_frame", true, false) != null
		and tab._buy.text.begins_with("Order it for") and not tab._buy.disabled, "the configurator: a choice for each part and colour (%s)" % tab._buy.text)
	var before: Array = Shed.bikes.keys()
	tab._press_buy()
	var id := _new_bike(before)
	var frame := Shed.item_on(id, "frame") if id != 0 else 0
	var wheel := Shed.item_on(id, "rear_wheel") if id != 0 else 0
	check(id != 0 and Shed.items[Shed.item_on(id, "exhaust")]["part"] == other and Shed.items[frame]["color"] == red
		and Shed.items[wheel]["color"] == gold and float(Shed.items[frame]["wear"]) == 0.0 and str(PartsDB.detect_style(Contracts.current_parts(id))["style"]) != "",
		"ordered, it comes new with that exhaust, a red frame and gold wheels: %s" % Shed.bikes.get(id, {}).get("name", "?"))
	tab.queue_free()
	Progress.profile = saved
	Shed.stop()


## Simon: "add mudguards, panniers, topbox as options on the new bike configurator", "add satnav,
## toolbox as options", "allow as many parts as possible to have a choice of colours (add the
## colour picker next to the option)", a logo and a brand name "stamped on the tank and background
## of preview (colour picker too)", and the view worked with the mouse (right-click stops and
## starts it turning) instead of buttons. The colour panel shows its swatches and recent colours.
func test_configurator_extras() -> void:
	Shed.start_new("Tester", 54)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.set_money(1000000)
	var tab := BikeShopTab.new()
	t.add_child(tab)
	await _frames(1)
	tab._new_style("tourer")
	tab.show_mode("new")
	var rows := []
	for slot in ["front_mudguard", "tail", "panniers", "top_box", "satnav", "toolbox"]:
		var ob: OptionButton = tab.find_child("Slot_" + slot, true, false)
		var opts := BikeShop.options(slot, "tourer", tab.parts)
		if ob != null and opts.has("none") and opts.size() >= 3:
			rows.append(slot)
	check(rows.size() == 6, "the configurator offers mudguards, a rear guard, panniers, a top box, a sat nav and a toolbox, or none (%s)" % [rows])
	# A colour beside every part that's there.
	var missing := []
	for slot in BikeShop.CONFIG_SLOTS:
		var there := str(tab.parts.get(slot, "none")) != "none"
		if there != (tab.find_child("Colour_" + slot, true, false) != null):
			missing.append(slot)
	check(missing.is_empty(), "a colour beside each part on the bike, none beside an empty slot %s" % [missing])
	check(tab.find_children("StopTurning", "", true, false).is_empty() and tab.find_children("ZoomIn", "", true, false).is_empty(),
		"no view buttons: the tips under the turntable say how (%s)" % tab._view_hint.text)
	# Luggage, a sat nav and red mudguards on a cafe racer.
	tab._new_style("cafe")
	tab.show_mode("new")
	tab.set_part("panniers", "canvas_throwover")
	tab.set_part("top_box", "wooden_crate")
	tab.set_part("satnav", "phone_nav_mount")
	tab.set_part("tail", "classic_mudguard")
	check(tab.parts["panniers"] == "canvas_throwover" and tab.parts["satnav"] == "phone_nav_mount" and tab.parts["tail"] == "classic_mudguard",
		"panniers, a top box, a sat nav and a rear mudguard go on a cafe racer")
	var guard: ColourChoice = tab.find_child("Colour_front_mudguard", true, false)
	check(guard != null and guard.color == PartsDB.default_color(str(tab.parts["front_mudguard"]))
		and not (tab.find_child("Reset_front_mudguard", true, false) as Button).visible,
		"a part's colour starts as it comes, with nothing to reset")
	var red := Color(0.75, 0.1, 0.08)
	var blue := Color(0.1, 0.2, 0.55)
	var green := Color(0.1, 0.45, 0.2)
	guard.color_changed.emit(red)
	tab.set_colour("tail", red)
	tab.set_colour("tank", blue)
	tab.set_colour("saddle", green)
	check((tab.find_child("Reset_front_mudguard", true, false) as Button).visible, "changed, it can be reset")
	tab.set_logo("wings")
	tab.badge["logo_color"] = Color(0.9, 0.75, 0.2)
	(tab.find_child("Brand", true, false) as LineEdit).text_changed.emit("Bennett Motor Works Ltd")
	var b: Dictionary = tab._src()["build"]
	var tank: Dictionary = b["colors"].get("tank", {})
	check(b["colors"].get("front_mudguard", {}).get("color") == red and b["colors"].get("tail", {}).get("color") == red
		and b["colors"].get("saddle", {}).get("color") == green and tank.get("color") == blue and b["paint"] == blue,
		"picked colours go on the order: red mudguards, a green seat, a blue tank")
	check(tank.get("badge", {}).get("logo") == "wings" and str(tank.get("badge", {}).get("brand", "")) == "Bennett Motor Wo",
		"the badge rides on the tank, its brand cut to %d letters (%s)" % [BikeBadge.BRAND_MAX, tank.get("badge", {})])
	# Drawn: on both sides of the tank, and the logo behind the bike in the preview.
	await _frames(2)
	var pv: PartPreview = tab._preview
	var model: BikeModel = pv.pivot.find_children("*", "BikeModel", true, false)[0] if not pv.pivot.find_children("*", "BikeModel", true, false).is_empty() else null
	var logos := model.find_children("BadgeLogo*", "Sprite3D", false, false) if model else []
	var brands := model.find_children("BadgeBrand*", "Label3D", false, false) if model else []
	var box := model.slot_bounds("tank") if model else AABB()
	var sides := logos.filter(func(n): return (n as Node3D).position.x > box.end.x - 0.001).size() + logos.filter(func(n): return (n as Node3D).position.x < box.position.x + 0.001).size()
	check(logos.size() == 2 and brands.size() == 2 and sides == 2 and (brands[0] as Label3D).text == "Bennett Motor Wo",
		"the logo and the brand are stamped on both sides of the tank (%d logos, %d brands, %d sides)" % [logos.size(), brands.size(), sides])
	check(pv.backdrop != null and pv.backdrop.visible and pv.backdrop.texture == BikeBadge.texture("wings"), "and the logo stands behind the bike in the preview")
	var before: Array = Shed.bikes.keys()
	tab._press_buy()
	var id := _new_bike(before)
	var tank_item := Shed.item_on(id, "tank") if id != 0 else 0
	var g := Shed.item_on(id, "front_mudguard") if id != 0 else 0
	check(tank_item != 0 and Shed.items[tank_item].get("badge", {}).get("logo") == "wings" and Shed.items[tank_item]["color"] == blue
		and g != 0 and Shed.items[g]["color"] == red and Shed.item_on(id, "satnav") != 0,
		"ordered, it comes with its badge on its blue tank, red mudguards and the sat nav fitted")
	var cond := Shed.condition_of(Shed.items[tank_item]) if tank_item != 0 else {}
	check(cond.get("badge", {}).get("brand") == "Bennett Motor Wo", "and the tank's condition carries the badge to wherever it's drawn")
	(tab.find_child("Reset_front_mudguard", true, false) as Button).pressed.emit()
	await _frames(1)
	check(not tab.colours.has("front_mudguard") and not tab._src()["build"]["colors"].has("front_mudguard"), "Reset puts the factory's colour back")
	# The colour panel: the square, the paint shop's swatches and the colours picked lately.
	ColourChoice.remember(Color(0.3, 0.6, 0.9))
	var cp: ColourChoice = tab.find_child("Colour_saddle", true, false)
	cp.open()
	await _frames(2)
	var panel: PopupPanel = cp.find_child("ColourPanel", true, false)
	var sw: GridContainer = panel.find_child("Swatches", true, false) if panel else null
	var rec: HBoxContainer = panel.find_child("Recent", true, false) if panel else null
	var room := Rect2(tab.get_viewport().get_visible_rect())
	check(panel != null and panel.visible and sw.get_child_count() == Shed.PAINTS.size() and rec.get_child_count() >= 1
		and room.encloses(Rect2(Vector2(panel.position), Vector2(panel.size))),
		"the colour panel shows every swatch and the recent colours, all on the screen")
	(sw.get_child(0) as Button).pressed.emit()
	panel.hide()
	check(tab.colours.get("saddle") == Shed.PAINTS[0] and ColourChoice.recent[0] == Shed.PAINTS[0], "a swatch picks its colour, and it goes in the recent ones")
	# The turntable: right-click stops and starts it, the wheel zooms, a part changed keeps the view.
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	pv._gui_input(right)
	var up := right.duplicate()
	up.pressed = false
	pv._gui_input(up)
	var turn := pv.pivot.rotation.y
	await _frames(5)
	check(not pv.spinning and is_equal_approx(pv.pivot.rotation.y, turn), "a right-click stops it turning")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	pv._gui_input(wheel)
	pv._gui_input(wheel)
	var z := pv.zoom
	tab.set_part("top_box", "none")
	await _frames(1)
	check(z > 1.2 and is_equal_approx(pv.zoom, z) and is_equal_approx(pv.pivot.rotation.y, turn), "the wheel zooms in, and a part changed keeps the view")
	pv._gui_input(right)
	pv._gui_input(up)
	check(pv.spinning, "and another right-click starts it again")
	tab.queue_free()
	Progress.profile = saved
	Shed.stop()
