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


## Simon: "add mudguards, panniers, topbox as options on the new bike configurator", "allow for
## the change of colour for mudguards" and "a faded background, with zoom and stop rotation for
## bike preview window". The configurator offers the front mudguard, the rear guard or tail,
## panniers and a top box (none too); the mudguards come in the factory's colour till one is
## picked, then front and rear in it (a tail cowl keeps its own); the turntable is a studio that
## fades at its edges, it stops turning and zooms in, and a part changed keeps the view.
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
	for slot in ["front_mudguard", "tail", "panniers", "top_box"]:
		var ob: OptionButton = tab.find_child("Slot_" + slot, true, false)
		var opts := BikeShop.options(slot, "tourer", tab.parts)
		if ob != null and opts.has("none") and opts.size() >= 3:
			rows.append(slot)
	check(rows.size() == 4, "the configurator offers mudguards, a rear guard, panniers and a top box, or none (%s)" % [rows])
	check(BikeShop.slot_label("tail") == "Rear guard, tail" and BikeShop.slot_label("top_box") == "Top box", "named plainly")
	# Luggage on a cafe racer, and a long rear mudguard.
	tab._new_style("cafe")
	tab.show_mode("new")
	tab.set_part("panniers", "canvas_throwover")
	tab.set_part("top_box", "wooden_crate")
	tab.set_part("tail", "classic_mudguard")
	check(tab.parts["panniers"] == "canvas_throwover" and tab.parts["top_box"] == "wooden_crate" and tab.parts["tail"] == "classic_mudguard",
		"panniers, a top box and a rear mudguard go on a cafe racer")
	var guards: ColorPickerButton = tab.find_child("Colour_mudguards", true, false)
	var fac: Button = tab.find_child("MudguardsFactory", true, false)
	check(guards != null and fac != null and fac.disabled and not tab.colours.has("mudguards")
		and guards.color == PartsDB.default_color(str(tab.parts["front_mudguard"])),
		"the mudguards' colour starts as the factory's (%s), with nothing to put back" % guards.color if guards else "no mudguard colour")
	var picker := guards.get_picker() if guards else null
	check(picker != null and not picker.sliders_visible and not picker.color_modes_visible and picker.presets_visible
		and picker.get_presets().size() == Shed.PAINTS.size(),
		"its picker is the small one, with the paint shop's colours as its swatches and room for recent colours")
	var red := Color(0.75, 0.1, 0.08)
	tab.set_colour("mudguards", red)
	var b: Dictionary = tab._src()["build"]
	check(b["colors"].get("front_mudguard", {}).get("color") == red and b["colors"].get("tail", {}).get("color") == red and not fac.disabled,
		"picked red, both mudguards are red")
	tab.set_part("tail", "cafe_ducktail")
	b = tab._src()["build"]
	check(b["colors"].get("front_mudguard", {}).get("color") == red and not b["colors"].has("tail"), "a ducktail cowl keeps its own colour")
	var before: Array = Shed.bikes.keys()
	tab._press_buy()
	var id := _new_bike(before)
	var guard := Shed.item_on(id, "front_mudguard") if id != 0 else 0
	var bags := Shed.item_on(id, "panniers") if id != 0 else 0
	check(guard != 0 and Shed.items[guard]["color"] == red and bags != 0 and Shed.items[bags]["part"] == "canvas_throwover",
		"ordered, it comes with a red front mudguard and its panniers on")
	(tab.find_child("MudguardsFactory", true, false) as Button).pressed.emit()
	await _frames(1)
	check(not tab.colours.has("mudguards") and not tab._src()["build"]["colors"].has("front_mudguard"), "As they come puts the factory's colour back")
	# The turntable.
	var pv: PartPreview = tab._preview
	check(pv.studio and pv.material is ShaderMaterial, "the bike sits in a soft studio that fades at its edges")
	var stop: Button = tab.find_child("StopTurning", true, false)
	stop.button_pressed = true
	var turn := pv.pivot.rotation.y
	await _frames(5)
	check(not pv.spinning and is_equal_approx(pv.pivot.rotation.y, turn) and stop.text == "Start turning", "Stop turning stops it")
	var far := pv.camera.position.length()
	(tab.find_child("ZoomIn", true, false) as Button).pressed.emit()
	var near := pv.camera.position.length()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	pv._gui_input(wheel)
	check(pv.zoom > 1.3 and near < far * 0.85 and pv.camera.position.length() < near, "zoom in, with the button or the mouse wheel (%.2fx)" % pv.zoom)
	for i in 30:
		pv.zoom_by(2.0)
	check(is_equal_approx(pv.zoom, PartPreview.ZOOM_MAX), "but only so far")
	var z := pv.zoom
	tab.set_part("top_box", "none")
	await _frames(1)
	check(is_equal_approx(pv.zoom, z) and is_equal_approx(pv.pivot.rotation.y, turn), "a part changed keeps the view where it was")
	(tab.find_child("WholeBike", true, false) as Button).pressed.emit()
	check(pv.zoom == 1.0 and pv.look == Vector2.ZERO, "See it all goes back to the whole bike")
	stop.button_pressed = false
	check(pv.spinning and stop.text == "Stop turning", "and it turns again")
	tab.queue_free()
	Progress.profile = saved
	Shed.stop()
