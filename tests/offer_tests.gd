extends RefCounted
## Simon's v0.21 round: making a friend an offer for a bike in their collection (its own clean
## window, HomeMakeOffer, and no message along the top as well as the window), and each bike's
## headlight switch kept where it was left. Run from tests/run_tests.gd (its _test_offer_*
## functions hand over to these).

var t: Node   # the test runner: check(), get_tree(), _bike_named()

const FRIEND := 77


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
		await t.get_tree().process_frame


## A finished shed bike nobody's riding that the business could sell.
func _for_sale() -> int:
	for id in Shed.bikes:
		if Shed.is_complete(id) and Collection.check(Shed.me(), {"a": "home_buy", "bike": id, "paid": Progress.MAX_MONEY}) == "":
			return int(id)
	return 0


## Pal (FRIEND) joins and buys a shed bike for their collection. Returns its collection id.
func _pal_bike() -> int:
	Shed._add_crew(FRIEND, "Pal")
	Collection.arrived(FRIEND)
	var b := _for_sale()
	Shed._apply(FRIEND, {"a": "home_buy", "bike": b, "paid": Collection.buy_price(b)})
	return int(Collection.bikes_of("Pal")[0]) if Collection.count_of("Pal") > 0 else 0


## Presses a key (down and up) into `vp`.
static func _key(vp: Viewport, key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		vp.push_input(ev, true)


## A left click in the middle of control `c`.
static func _click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var vp := c.get_viewport()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	vp.push_input(move, true)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = down
		vp.push_input(ev, true)


## Offers come with a window, so nobody gets a message along the top as well: not the one making
## it (their window says it's made) nor the owner (theirs comes up to answer). Messages with no
## window behind them still come: taking an offer back, and the answer to one.
func test_quiet() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var who := Collection.name_of(Shed.me())
	var told := []
	var hear := func(text: String, ok: bool): told.append([text, ok])
	Shed.feedback.connect(hear)
	var cid := _pal_bike()
	check(cid != 0, "Pal has a bike in their collection")
	Progress.set_money(20000)
	check(Collection.make_offer(cid, 6000) == "" and not Collection.offer_from(who, cid).is_empty(), "an offer made")
	check(told.is_empty(), "making it: no message along the top (%s)" % str(told))
	Shed.request({"a": "home_withdraw", "offer": int(Collection.offer_from(who, cid)["id"])})
	check(told.size() == 1 and str(told[0][0]).begins_with("Took your offer back"), "taking it back still says so (%s)" % str(told))
	# The other way round: Pal offers for a bike of yours.
	told.clear()
	Collection.make_offer(cid, 8000)
	Shed._apply(FRIEND, {"a": "home_answer", "offer": int(Collection.offer_from(who, cid)["id"]), "yes": true})
	check(str(Collection.entry(cid)["owner"]) == who, "Pal took it: the bike's yours")
	told.clear()
	Shed._apply(FRIEND, {"a": "home_offer", "bike": cid, "amount": 9000, "paid": 9000})
	check(Collection.offers_to(who).size() == 1, "Pal offers you money for it")
	check(told.is_empty(), "being offered: no message along the top, the window's enough (%s)" % str(told))
	Shed.request({"a": "home_answer", "offer": int(Collection.offers_to(who)[0]["id"]), "yes": false})
	check(told.size() == 1 and str(told[0][0]).contains("Turned down"), "answering it (the window's gone) still says so (%s)" % str(told))
	Shed.feedback.disconnect(hear)
	Progress.profile = saved
	Shed.stop()


## Where an offer starts: what it's worth in tens of pounds, or all you have if that's less.
func test_default() -> void:
	check(HomeMakeOffer.default_amount(3456, 50000) == 3450, "worth £3,456 with plenty: starts at £3,450")
	check(HomeMakeOffer.default_amount(3456, 1203) == 1200, "worth more than you have: starts at what you have")
	check(HomeMakeOffer.default_amount(3456, 4) == 4 and HomeMakeOffer.default_amount(0, 500) == Collection.MIN_OFFER,
		"a few pounds stays a few pounds; never under the least you can offer")


## The make-an-offer window in the game: opened from the bike's card with the mouse, the slider
## moved with the arrow keys, {back} to cancel, an amount typed in and Enter to make it, then
## OK to close.
func test_window() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_offer_window_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await t.get_tree().physics_frame
	var saved: Dictionary = Progress.profile.duplicate(true)
	var who := Collection.name_of(Shed.me())
	var told := []
	var hear := func(text: String, ok: bool): told.append([text, ok])
	Shed.feedback.connect(hear)
	var cid := _pal_bike()
	Progress.set_money(50000)
	var panel: HomePanel = main.home_panel
	var sheet := panel.offer_sheet
	panel.open_bike(cid)
	await _frames(2)
	check(panel.visible and panel.text().contains("[Make an offer]") and not panel._offer.disabled, "Pal's bike's card: Make an offer")
	_click(panel._offer)
	await _frames(2)
	var worth := int(Collection.entry(cid)["value"])
	check(sheet.visible and not panel._center.visible, "clicked: the offer's own window in place of the card")
	check(sheet.amount() == HomeMakeOffer.default_amount(worth, 50000) and sheet._make.text == "Make offer: %s" % Collection.money(sheet.amount())
		and not sheet._make.disabled, "it starts at what the bike's worth, on one clear button (%s)" % sheet._make.text)
	check(sheet._worth.text == Collection.money(worth) and sheet._have.text == Collection.money(50000) and sheet._sub.text.contains("Pal's"),
		"it says whose bike, what it's worth and what you have")
	check(sheet._preview.visible and sheet._preview.showing.begins_with("bike:"), "the bike's on its turntable")
	check(t.get_viewport().gui_get_focus_owner() == sheet._slider, "the slider has the keys")
	var was := sheet.amount()
	_key(t.get_viewport(), KEY_RIGHT)
	_key(t.get_viewport(), KEY_RIGHT)
	await _frames(1)
	check(sheet.amount() == was + 2 * HomeMakeOffer.STEP, "right arrow twice: £%d more (%d to %d)" % [2 * HomeMakeOffer.STEP, was, sheet.amount()])
	_key(t.get_viewport(), KEY_ESCAPE)
	await _frames(2)
	check(panel.visible and not sheet.visible and panel._center.visible and Collection.offers().is_empty() and Progress.money() == 50000,
		"Esc cancels: back to the card, nothing offered")
	panel.open_offer()
	await _frames(2)
	sheet.set_amount(60000)
	await _frames(1)
	check(sheet.amount() == 50000 and not sheet._make.disabled, "it won't go past what you have (%d)" % sheet.amount())
	# Typed in, then Enter.
	var edit := sheet._spin.get_line_edit()
	edit.grab_focus()
	edit.text = "1234"
	_key(t.get_viewport(), KEY_ENTER)
	await _frames(2)
	var o := Collection.offer_from(who, cid)
	check(not o.is_empty() and int(o["amount"]) == 1234 and Progress.money() == 50000 - 1234, "typed £1,234 and Enter: the offer's made, the money held")
	check(sheet.visible and sheet.sent and sheet._made.visible and sheet._made_text.text.contains(Collection.money(1234)), "the window says it's made")
	check(told.is_empty(), "and nothing along the top as well (%s)" % str(told))
	await _frames(1)
	check(t.get_viewport().gui_get_focus_owner() == sheet._ok, "OK has the keys")
	_key(t.get_viewport(), KEY_ENTER)
	await _frames(2)
	check(not panel.visible and not sheet.visible, "Enter on OK closes it")
	panel.open_bike(cid)
	await _frames(2)
	check(panel.text().contains("You've offered Pal") and panel.text().contains("[Take my offer back]") and not panel.text().contains("[Make an offer]"),
		"the card says it's waiting, and offers to take it back")
	panel.close_dialog()
	Shed.feedback.disconnect(hear)
	Progress.profile = saved
	main.queue_free()
	await _frames(2)
	Shed.stop()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path


## A bike's headlight switch is kept with it (Shed "beam"): off for a bike that's never had it
## touched, set only by whoever's riding it, kept when they get off, saved with the shed, sent
## to the crew, and taken home with it into a collection.
func test_beam() -> void:
	Shed.start_new("Tester", 41)
	var me := Shed.me()
	var id := 0
	for b in Shed.bikes:
		if Shed.is_complete(b):
			id = int(b)
			break
	check(id != 0 and Shed.beam_of(id) == 0, "a bike that's never had its lights touched has them off")
	check(Shed.check(me, {"a": "beam", "bike": id, "beam": 2}) != "", "only whoever's riding it can work the switch")
	Shed.bikes[id]["rider"] = me
	Shed.crew[me]["riding"] = id
	check(Shed.check(me, {"a": "beam", "bike": id, "beam": 9}) != "", "no such stop on the switch")
	Shed.request({"a": "beam", "bike": id, "beam": 2})
	check(Shed.beam_of(id) == 2, "high beam: kept with the bike")
	Shed.request({"a": "dismount", "bike": id, "xf": Shed.bikes[id]["xf"]})
	check(int(Shed.bikes[id]["rider"]) == 0 and Shed.beam_of(id) == 2, "got off: still on high beam")
	check(int((Shed._snapshot(false)["bikes"] as Dictionary)[id].get("beam", -1)) == 2, "it goes out to the crew with the bike")
	# A crew mate (a client: the host applies their request) gets on and switches it to low beam.
	Shed._add_crew(FRIEND, "Pal")
	Shed.bikes[id]["rider"] = FRIEND
	Shed.crew[FRIEND]["riding"] = id
	Shed._apply(FRIEND, {"a": "beam", "bike": id, "beam": 1})
	check(Shed.beam_of(id) == 1, "a crew mate riding it switches it: kept for everyone")
	Shed.bikes[id]["rider"] = 0
	Shed.crew[FRIEND]["riding"] = 0
	var snap: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.load_state(snap, "Tester")
	check(Shed.beam_of(id) == 1, "saved and loaded: still on low beam")
	var packed := Collection.pack(id)
	var back := Collection.unpack(packed, Transform3D())
	check(Shed.beam_of(back) == 1, "taken home into a collection and ridden out again: as it was left")
	Shed.stop()


## In the game: getting on finds the switch where it was left, L moves it and the shed keeps it,
## and getting off and on again doesn't put the lights back on.
func test_beam_ride() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_offer_beam_test.json"
	DirAccess.remove_absolute(Progress.path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	var faithful: int = t._bike_named("Old Faithful")
	check(Shed.beam_of(faithful) == 0, "Old Faithful's lights start off")
	Shed.request({"a": "mount", "bike": faithful})
	await _frames(5)
	check(main.bike != null and main.bike.beam == 0, "on the bike: the lights are off, not on")
	t._press("headlight")
	await _frames(2)
	t._press("headlight")
	await _frames(2)
	check(main.bike.beam == 2 and Shed.beam_of(faithful) == 2, "L twice: high beam, and the shed keeps it")
	main._get_off()
	await _frames(5)
	check(main.bike == null and Shed.beam_of(faithful) == 2, "got off: the switch stays on high beam")
	main._left_bike = 0
	Shed.request({"a": "mount", "bike": faithful})
	await _frames(5)
	check(main.bike != null and main.bike.beam == 2 and main.bike.effects.beam_mode == 2, "back on: high beam, as it was left")
	main.bike.engine_on = true
	await _frames(3)
	check(main.bike.effects.light_on() and main.bike.model.lights_lit(), "and with the engine running the headlight's lit")
	t._press("headlight")
	await _frames(2)
	check(main.bike.beam == 0 and Shed.beam_of(faithful) == 0, "L on round to off")
	main._get_off()
	await _frames(5)
	main._left_bike = 0
	Shed.request({"a": "mount", "bike": faithful})
	await _frames(5)
	check(main.bike != null and main.bike.beam == 0, "back on again: still off")
	main._get_off()
	main.queue_free()
	await _frames(2)
	Shed.stop()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
