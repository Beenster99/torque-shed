extends RefCounted
## The phone sat nav (Simon: "Please add a satnav which can be a mobile phone clipped to the
## handlebar"), run from tests/run_tests.gd: its _test_phone_* functions hand over to these.
## A phone in a clip on the bar counts as a sat nav everywhere the dash units do, sits on the
## bar of every style's stock bike, shows the live map, buzzes with the engine, glows at night,
## is bought and fitted like any part and comes back from a save.

const PHONE := "phone_nav_mount"

var t: Node   # the test runner: check(), get_tree(), _order(), _bike_named()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## It's a sat nav part: in the sat nav slot, cheap, sold with the other sat navs, for every
## style, and the build (and so the game's checks: the HUD map, the adventure's help) knows it.
func test_part() -> void:
	var p := PartsDB.get_part(PHONE)
	check(PartsDB.kind_of(PHONE) == "satnav" and str(p.get("style", "")) == "phone", "the phone in a bar clip is a sat nav part")
	var dearer: Array = PartsDB.by_kind["satnav"].filter(func(id): return id != PHONE and Money.part_price(str(id)) <= Money.part_price(PHONE))
	check(dearer.is_empty() and Money.part_price(PHONE) <= 50, "and the cheapest sat nav (%s)" % TvChannels.money_text(Money.part_price(PHONE)))
	var aisle := ""
	for g in PartsComputer.GROUPS:
		if (g[1] as Array).has("satnav"):
			aisle = str(g[0])
	check(aisle == "Luggage and adventure kit", "sold on the parts computer with the dash sat navs (%s)" % aisle)
	check(PartsDB.STYLES.all(func(s): return PartsDB.styles_of(PHONE).has(s)), "listed for every style of bike")
	var b := BikeBuild.new({"satnav": PHONE})
	check(b.has_part("satnav") and b.satnav_features.has("map") and b.satnav_features.has("route"),
		"the build counts it as a sat nav with the map and the way to go %s" % str(b.satnav_features))
	check(PartsDB.spec_line(PHONE).contains("the way to go"), "its spec line: %s" % PartsDB.spec_line(PHONE))


## On every style's stock bike the clamp is round the bar itself, the phone sits within the
## bars' width, faces the rider's eye, hides none of the clocks and runs into nothing.
func test_mounts() -> void:
	var bad := []
	var spots := []
	for style in PartsDB.STYLES:
		var parts: Dictionary = Contracts.style_build(style)
		parts["satnav"] = PHONE
		var m := BikeModel.new()
		t.add_child(m)
		m.build_from(BikeBuild.new(parts))
		var cradle := m.satnav_cradle()
		var fit := m.satnav_fit
		if cradle == null or fit.is_empty() or m.satnav_screen() == null:
			bad.append("%s: no phone" % style)
			m.free()
			continue
		var at := cradle.position
		var eye := m._eye - m._head
		var clamp: Vector3 = fit["clamp"]
		var face := cradle.basis.z.dot((eye - at).normalized())
		var bar_end: Vector3 = m.bar_line()[m.bar_line().size() - 1]
		var why := []
		if m.bar_distance(clamp) > 0.006:
			why.append("clamp %.0f mm off the bar" % (m.bar_distance(clamp) * 1000.0))
		if absf(at.x) + 0.08 > bar_end.x:
			why.append("past the bar end")
		if face < 0.98:
			why.append("not facing the eye (%.2f)" % face)
		if int(fit["dash_hidden"]) > 0:
			why.append("hides %d of the clocks" % int(fit["dash_hidden"]))
		if int(fit["hits"]) > 0:
			why.append("runs into %d things" % int(fit["hits"]))
		if int(fit["blocked"]) > 0:
			why.append("%d sight lines cut" % int(fit["blocked"]))
		var dist := eye.distance_to(at)
		if 0.12 / dist < 0.1:
			why.append("too small to read (%.2f rad)" % (0.12 / dist))
		if not why.is_empty():
			bad.append("%s: %s" % [style, ", ".join(why)])
		spots.append("%s %s" % [style, "bar" if absf(at.x) > 0.06 else "middle"])
		m.free()
	check(bad.is_empty(), "on every stock style the phone clamps round the bar, within its width, facing the eye, clear of the clocks and everything else %s" % str(bad))
	print("    " + ", ".join(spots))


## Riding it: the live map is lit on the phone's screen (the same view as the dash units), the
## HUD map knows there's a sat nav, the phone buzzes with the engine and the screen glows after
## dark; everyone else's copy of the bike shows a lit screen with the ignition on.
func test_screen() -> void:
	var world := World.new()
	t.add_child(world)
	world.generate(1234)
	var bike := Bike.new()
	bike.setup(BikeBuild.new({"satnav": PHONE}))
	world.add_child(bike)
	var spawn: Transform3D = world.spawn_point(0)
	bike.place(spawn.origin, spawn.basis.get_euler().y)
	bike.engine_on = true
	var nav := Satnav.new(bike, world)
	t.add_child(nav)
	await _frames(3)
	check(nav.fitted(), "the sat nav sees the phone as one fitted (so the M map and the adventure's help work)")
	nav.refresh()
	await _frames(3)
	var mat := bike.model.satnav_screen().material_override as StandardMaterial3D
	check(mat.albedo_texture == nav.viewport.get_texture(), "the live map is lit on the phone's screen")
	check(not (nav.screen.view["roads"] as Array).is_empty() and (nav.screen.view["route"] as PackedVector2Array).size() > 10
		and nav.screen.features.has("route"), "showing the roads round the bike and the way ahead, like the dash units")
	check(nav.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "the screen's viewport is drawn only when it changes, not every frame")
	# The engine buzzes the phone in its cradle, a fraction of a millimetre.
	var cradle := bike.model.satnav_cradle()
	var rest := bike.model._satnav_rest
	var moved := 0.0
	for i in 6:
		bike.model.set_gauges(0.3, 0.5)
		moved = maxf(moved, cradle.position.distance_to(rest))
		await _frames(1)
	check(moved > 0.0001 and moved <= KitModel.BUZZ + 0.0001, "the phone buzzes in its cradle with the engine (%.2f mm)" % (moved * 1000.0))
	bike.model.set_gauges(0.0, 0.0)
	check(cradle.position == rest, "and sits still with it stopped")
	# Night: the screen glows.
	var day := Daylight.new()
	var old := Daylight.current
	Daylight.current = day
	day.dark = 0.0
	bike.model._show_satnav()
	var glow := bike.model.satnav_glow()
	check(glow != null and not glow.visible, "no glow by day")
	day.dark = 0.9
	bike.model._show_satnav()
	check(glow.visible and glow.light_energy > 0.1 and not glow.shadow_enabled, "after dark the screen glows on the bars (a little light, no shadows)")
	# Engine off: dark, and no glow.
	bike.engine_on = false
	nav._timer = 0.0
	nav._tick(0.01)
	check(mat.albedo_texture == null and not glow.visible, "with the engine off the screen is dark")
	# Someone else's copy of the bike (co-op): the phone is there, lit with the ignition on.
	var other := BikeModel.new()
	t.add_child(other)
	other.build_from(BikeBuild.new({"satnav": PHONE}))
	check(other.satnav_cradle() != null and other.satnav_screen().is_visible_in_tree(), "everyone else sees the phone on your bike")
	var omat := other.satnav_screen().material_override as StandardMaterial3D
	check(omat.albedo_texture == null, "dark while it's parked")
	other.set_lights(true, false)
	check(omat.albedo_texture == KitModel.idle_screen() and other.satnav_glow().visible, "lit with a map (and glowing after dark) while its engine runs")
	Daylight.current = old
	day.free()
	other.free()
	nav.queue_free()
	world.queue_free()
	await _frames(1)


## Bought from the parts computer, fitted to a bike in the shed like any part, and back from a
## save on the bike.
func test_buy_fit_save() -> void:
	Shed.start_new("Tester", 71)
	var me := Shed.me()
	var money := Shed.garage_money
	Shed.request({"a": "order_part", "part": PHONE})
	var box := 0
	for id in Shed.items:
		if str(Shed.items[id]["part"]) == PHONE:
			box = id
	check(box != 0 and Shed.garage_money == money - Money.buy_price(PHONE, me), "ordered from the parts computer for %s" % TvChannels.money_text(Money.buy_price(PHONE, me)))
	var bike: int = t._bike_named("Old Faithful")
	Shed.items[box]["boxed"] = false
	Shed._move(box, "held", me)
	var why := Shed.check(me, {"a": "install", "bike": bike, "slot": "satnav", "crouched": true})
	Shed.request({"a": "install", "bike": bike, "slot": "satnav", "crouched": true})
	Shed.request({"a": "bolt", "bike": bike, "slot": "satnav", "crouched": true})
	check(Shed.item_on(bike, "satnav") == box and Shed.is_bolted(bike, "satnav"), "it clips on and is tightened up %s" % why)
	check(Shed.build_of(bike).has_part("satnav"), "and the bike has a sat nav")
	var saved: Dictionary = str_to_var(var_to_str(Shed._snapshot()))
	Shed.start_new("Tester", 72)
	Shed.load_state(saved, "Tester")
	check(Shed.item_on(bike, "satnav") != 0 and str(Shed.items[Shed.item_on(bike, "satnav")]["part"]) == PHONE and Shed.build_of(bike).has_part("satnav"),
		"it comes back from a save, still on the bike")
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(Shed.build_of(bike))
	check(m.satnav_cradle() != null, "and is drawn on it")
	m.free()
