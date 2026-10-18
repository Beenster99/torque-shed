extends RefCounted
## The job cards (Workflow), their TV channel (WorkflowTv) and the touch screens (ScreenTouch,
## Dashboard), run from tests/run_tests.gd (its _test_workflow_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()
var rec: RefCounted   # the recovery tests, for their shed, jobs and deliveries


func _init(runner: Node) -> void:
	t = runner
	rec = load("res://tests/recovery_tests.gd").new(runner)


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A crashed bike recovered to the yard, waiting to be assessed.
func _delivered_crash() -> Dictionary:
	rec._shed_with_rig()
	rec._park_at(Recovery.PARK)
	var job: Dictionary = rec._job("crash", true)
	rec._deliver(job)
	return job


func _button(d: Dictionary, a: String, task := "") -> Dictionary:
	for b in d.get("buttons", []):
		if str(b["act"].get("a", "")) == a and (task == "" or str(b["act"].get("task", "")) == task):
			return b
	return {}


func _row(d: Dictionary, text: String) -> Dictionary:
	for r in d.get("rows", []):
		if str(r["text"]) == text:
			return r
	return {}


## Assess vehicle is shed state: the damage list, prices and task list go on the bike's card for
## everyone, the decision is made at those prices, and it's all kept in the save.
func test_assess() -> void:
	var job := _delivered_crash()
	var me := Shed.me()
	var bike := int(job["bike"])
	Shed._add_crew(5, "Pal")
	check(not Workflow.assessed(bike) and str(job["state"]) == "delivered", "a recovered bike comes in unassessed")
	Shed.screens["crew"] = {"ch": "workflow", "bike": bike}
	var d := WorkflowTv.data("crew")
	check(int(d["bike"]) == bike and not _button(d, "card_assess").is_empty() and _button(d, "recovery_buy").is_empty(),
		"its job card shows Assess vehicle, and no prices yet")
	Shed.request({"a": "card_assess", "bike": bike})
	var c := Workflow.card(bike)
	var live := Recovery.assess(bike, job)
	check(Workflow.assessed(bike) and (c["rows"] as Array).size() == (live["rows"] as Array).size() and int(c["repair"]) == int(live["repair"]),
		"assessed: every part's condition and the repair estimate are on the card (%s)" % TvChannels.money_text(int(c.get("repair", 0))))
	check(c["prices"] is Dictionary and int(c["prices"]["buy"]) == int(live["buy"]) and str(c["by"]) == "Recovery tester",
		"with the three prices, and who assessed it")
	var fixes: Array = live["rows"].filter(func(r): return str(r["fix"]) != "ok")
	check((c["tasks"] as Array).size() >= fixes.size() + 1 and str(c["tasks"][-1]["fix"]) == "bolted",
		"each repair is a task on the card, ending with every part on and bolted (%d tasks)" % (c["tasks"] as Array).size())
	# The old menu (Esc, Recovery) shows the same assessment, and points to the screens.
	var box := VBoxContainer.new()
	RecoveryPanel.fill_assessment(box, job, func(): pass)
	var said := box.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(said.any(func(s): return str(s).contains("Assessed by Recovery tester") and str(s).contains("Workflow channel")),
		"the Recovery menu shows the card's assessment and points to the Workflow channel")
	box.free()
	# A client gets the card with the next sync of the shed.
	var synced: Dictionary = Shed._snapshot().duplicate(true)
	check(synced["bikes"][bike].get("card") is Dictionary and synced["bikes"][bike]["card"]["rows"].size() == c["rows"].size(),
		"the card goes out to the crew with the shed")
	d = WorkflowTv.data("crew")
	check(not _button(d, "recovery_buy").is_empty() and not _button(d, "recovery_insurer").is_empty() and _button(d, "card_assess").is_empty(),
		"the card now offers buy, break and insurer work")
	# The prices stay as assessed: the decision is made at the price the crew saw.
	var price := int(c["prices"]["buy"])
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike, slot)
		if id != 0 and not PartsDB.is_fluid(str(Shed.items[id]["part"])):
			Shed.items[id]["wear"] = 0.0
	check(int(Recovery.assess(bike, job)["buy"]) != price and int(Recovery.quote(job)["buy"]) == price,
		"worked on since, the quote is still the assessed one (%s)" % TvChannels.money_text(price))
	# Saved and loaded.
	SaveGame.write("test_workflow", {"version": SaveGame.VERSION, "shed": Shed.save_snapshot()})
	var back := SaveGame.read("test_workflow")
	SaveGame.delete_slot("test_workflow")
	Shed.load_state(back["shed"], "Recovery tester")
	check(Workflow.assessed(bike) and int(Workflow.card(bike)["prices"]["buy"]) == price, "the card comes back from the save")
	var m := Shed.garage_money
	Shed.request({"a": "recovery_buy", "job": int(job["id"])})
	check(Shed.garage_money == m - price and Shed.bikes.has(bike) and Workflow.assessed(bike),
		"bought at the assessed price, and the card stays with the project bike")
	# A save from before job cards.
	var old: Dictionary = Shed._snapshot().duplicate(true)
	old["bikes"][bike].erase("card")
	Shed.load_state(old, "Recovery tester")
	check(not Workflow.assessed(bike) and Workflow.next_step(bike).contains("Assess"), "a bike from an old save just has no card yet")
	check(Shed.check(me, {"a": "card_assess", "bike": 999999}) != "", "the host refuses a bike that isn't there")
	Shed.stop()


## The Workflow channel: the task list ticks itself off as the work is done (or by hand), the
## parts stand as missing, ordered or in stock, staff can be given a task, and the page draws.
func test_channel() -> void:
	var job := _delivered_crash()
	var me := Shed.me()
	var bike := int(job["bike"])
	Shed.request({"a": "card_assess", "bike": bike})
	Shed.request({"a": "recovery_insurer", "job": int(job["id"])})
	check(str(job["state"]) == "insurer" and (job["spec"] as Array).size() == Workflow.card(bike)["rows"].filter(func(r): return str(r["fix"]) != "ok").size(),
		"the insurer's spec is the assessed repairs")
	Shed.screens["crew"] = {"ch": "workflow", "bike": bike}
	var d := WorkflowTv.data("crew")
	var met0 := int(d["met"])
	check(met0 < int(d["total"]) - 3 and int(d["total"]) > 1 and str(d["next"]).begins_with("Next:"), "nothing's done yet, and it says what's next (%s; %d of %d: %s)" % [d["next"], int(d["met"]), int(d["total"]), str(d["rows"].map(func(r): return [r["text"], r["done"]]))])
	check(not _button(d, "recovery_collect").is_empty() and str(_button(d, "recovery_collect")["off"]).contains("spec"),
		"Insurer collects is there, but not yet")
	# Put the first task's part right: it ticks itself off.
	var task: Dictionary = Workflow.card(bike)["tasks"][0]
	var id := Shed.item_on(bike, str(task["slot"]))
	for k in ["wear", "rust", "dirt"]:
		Shed.items[id][k] = 0.0
	Shed.items[id]["scuff"] = false
	d = WorkflowTv.data("crew")
	check(bool(_row(d, str(task["text"]))["done"]) and int(d["met"]) == met0 + 1, "put right, %s ticks itself off" % task["text"])
	check(Shed.check(me, {"a": "card_tick", "bike": bike, "task": task["id"], "on": false}) != "", "and can't be unticked: the bike says it's done")
	# Tick one off by hand, and back.
	var task2: Dictionary = Workflow.card(bike)["tasks"][1]
	Shed.request({"a": "card_tick", "bike": bike, "task": task2["id"], "on": true})
	check(Workflow.is_done(bike, task2) and int(WorkflowTv.data("crew")["met"]) == met0 + 2, "ticked off by hand")
	Shed.request({"a": "card_tick", "bike": bike, "task": task2["id"], "on": false})
	check(not Workflow.is_done(bike, task2), "and unticked")
	# A part to replace: missing, then ordered from the card.
	var rep := {}
	for t2 in Workflow.card(bike)["tasks"]:
		if str(t2["fix"]) == "replace" and not Workflow.is_done(bike, t2):
			rep = t2
	if rep.is_empty():
		Workflow.card(bike)["tasks"].push_front({"id": "tank", "text": "Replace the tank", "slot": "tank", "part": str(Shed.items[Shed.item_on(bike, "tank")]["part"]), "fix": "replace"})
		rep = Workflow.card(bike)["tasks"][0]
		Shed.items[Shed.item_on(bike, "tank")]["wear"] = 0.95
	check(Workflow.part_state(bike, rep, Workflow.stock()) == "missing" and Workflow.missing_parts(bike).has(str(rep["part"])),
		"a part to replace that the shed hasn't got is missing")
	var m := Shed.garage_money
	d = WorkflowTv.data("crew")
	check(not _button(d, "card_order").is_empty() and str(_button(d, "card_order")["off"]) == "", "the card offers to order what's missing")
	Shed.request(_button(d, "card_order")["act"])
	check(Shed.garage_money < m and Workflow.part_state(bike, rep, Workflow.stock()) == "ordered" and Workflow.missing_parts(bike).is_empty(),
		"ordered: it's boxed in the delivery area and the business paid")
	# Give a task to the staff.
	Shed.request({"a": "staff_debug_hire_all"})
	var free := {}
	for t3 in Workflow.card(bike)["tasks"]:
		if not Workflow.is_done(bike, t3) and not Workflow.staff_job(bike, t3).is_empty():
			free = t3
			break
	var why := Shed.check(me, {"a": "card_assign", "bike": bike, "task": free.get("id", "")})
	check(not free.is_empty() and why == "", "a task can go to the staff (%s)" % why)
	Shed.request({"a": "card_assign", "bike": bike, "task": free["id"]})
	var on := false
	for wid in Staff.workers():
		on = on or int(Staff.workers()[wid]["job"].get("bike", 0)) == bike
	d = WorkflowTv.data("crew")
	check(on and str(_row(d, str(free["text"])).get("who", "")) != "" and not (d["on"] as Array).is_empty(),
		"one of the staff takes it on, and the card says who (%s)" % str(d["on"]))
	# The whole list as a project, to a mechanic: the card's tasks still to do, in order.
	var first_left: Dictionary = (Workflow.card(bike)["tasks"] as Array).filter(func(x): return not Workflow.is_done(bike, x))[0]
	var left := (Workflow.card(bike)["tasks"] as Array).filter(func(x): return not Workflow.is_done(bike, x)).size()
	var pb := _button(d, "card_project")
	check(not pb.is_empty() and str(pb["off"]) == "", "the card offers to assign the whole project")
	Shed.request(pb["act"])
	var proj := {}
	for wid in Staff.workers():
		var j: Dictionary = Staff.workers()[wid]["job"]
		if str(j.get("kind", "")) == "project" and int(j.get("bike", 0)) == bike:
			proj = Staff.workers()[wid]
	check(not proj.is_empty() and str(proj["role"]) in ["mechanic", "expert"] and (proj["job"]["tasks"] as Array).size() == left
		and str(proj["job"]["tasks"][0]["text"]) == str(first_left["text"]), "one who can takes the card's list on as a project, in order (%d tasks)" % left)
	check(_button(WorkflowTv.data("crew"), "card_project").is_empty(), "and the card doesn't offer it again while they're on it")
	# Who's been at it.
	var act := {"a": "unbolt", "bike": bike, "slot": "tank"}
	var why2 := Shed.check(me, act)
	Shed.request(act)
	check(Workflow.card(bike)["who"].has("Recovery tester"), "the card notes who's worked on it (%s)" % why2)
	# The page draws, and on a bay screen the channel comes after the bay page.
	var dash := Dashboard.new("bike", 2.0)
	t.add_child(dash)
	dash._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	dash.show_page("workflow", d)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	var empty := WorkflowTv.data("bay3")
	dash.show_page("workflow", empty)
	await t.get_tree().process_frame
	check(TvChannels.channels_for("bay1")[1] == "workflow" and TvChannels.channels_for("crew").has("workflow"),
		"every screen has the Workflow channel, a bay screen's straight after its bay page")
	dash.queue_free()
	Shed.stop()


## Touching a screen: the cursor lights the button under it, a touch goes into the screen's
## viewport and finds the button, and its request changes the shed. A pad holds the cursor on
## the screen and moves it, touches with A and leaves with B.
func test_touch() -> void:
	var job := _delivered_crash()
	var bike := int(job["bike"])
	Shed.screens["crew"] = {"ch": "workflow", "bike": bike}
	var dash := Dashboard.new("crew", 2.0)
	dash.key = "crew"
	t.add_child(dash)
	dash.show_page("workflow", WorkflowTv.data("crew"))
	var b := _button(dash.data, "card_assess")
	var at: Vector2 = (b["r"] as Rect2).get_center()
	# Pointing at it from in front: the ray lands on that point of the page.
	var aim := dash.global_transform * Vector3((at.x / Dashboard.PX.x - 0.5) * 2.0, (0.5 - at.y / Dashboard.PX.y) * dash.height(), 0.03)
	var from := dash.global_transform * Vector3(0.3, -0.2, 1.8)
	var px = dash.page_point(from, (aim - from).normalized())
	check(px is Vector2 and (px as Vector2).distance_to(at) < 1.0, "a look at the screen lands on the page where it points (%s)" % str(px))
	check(dash.page_point(from, (from - aim).normalized()) == null, "looking away from it doesn't")
	dash.set_cursor(at)
	check(dash.cursor_on() and str(dash.hovered().get("act", {}).get("a", "")) == "card_assess", "the cursor lights the Assess vehicle button")
	check(dash.buttons().any(func(x): return str(x["act"].get("a", "")) == "tv_channel"), "and the channel buttons show while it's on the screen")
	var hit := dash.tap(at)
	check(str(hit.get("act", {}).get("a", "")) == "card_assess", "a touch goes into the screen's viewport and finds the button")
	check(dash.tap(Vector2(300, 300)).is_empty(), "a touch on no button finds nothing")
	# Through ScreenTouch, as the player's touch does it.
	var w := Walker.new()
	var st := ScreenTouch.new(w)
	t.add_child(st)
	st._dash = dash
	st._px = at
	check(st.touch() and Workflow.assessed(bike), "touched: the bike is assessed, in the shed for everyone")
	dash.show_page("workflow", WorkflowTv.data("crew"))
	# Holding the cursor on it (a pad): moved about, A touches, B leaves.
	st.focused = "crew"
	var buy := _button(dash.data, "recovery_insurer")
	st._px = Vector2.ZERO
	st.move_cursor((buy["r"] as Rect2).get_center())
	check(str(dash.hovered().get("act", {}).get("a", "")) == "recovery_insurer", "the held cursor moves onto Insurer job")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	st._input(ev)
	check(str(job["state"]) == "insurer", "A touches it: it's an insurer job now")
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40, 0)
	var before := st._px
	st._input(mm)
	check(st._px.distance_to(before + Vector2(40, 0) * ScreenTouch.MOUSE_SPEED) < 0.1, "the mouse moves the held cursor too")
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	st._input(back)
	check(st.focused == "" and not dash.cursor_on(), "B leaves the screen")
	# The channel buttons: a touch changes channel for everyone.
	dash.set_cursor(Vector2(500, 300))
	var next: Dictionary = dash.buttons().filter(func(x): return str(x["act"].get("a", "")) == "tv_channel" and int(x["act"]["step"]) == 1)[0]
	st._dash = dash
	st._px = (next["r"] as Rect2).get_center()
	dash.set_cursor(st._px)
	st.touch()
	check(Shed.screen_channel("crew")["ch"] != "workflow", "the > button changes the channel (%s)" % Shed.screen_channel("crew")["ch"])
	st.queue_free()
	w.free()
	dash.queue_free()
	Shed.stop()


## In the real shed: look at a bay screen up close, a cursor shows on it; click and the button
## under the crosshair is touched; E holds the cursor and Esc lets go.
func test_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	var w: Walker = main.walker
	Shed.screens["bay0"] = {"ch": "workflow", "rider": 0}
	main.workshop._refresh_dashboards()
	var screen: Dashboard = main.workshop.screens()["bay0"]
	var bike := Workflow.subject("bay0")
	check(bike != 0 and screen.kind == "workflow", "bay 1's screen shows its bike's job card (%d)" % bike)
	var b := _button(screen.data, "card_assess")
	var at: Vector2 = (b["r"] as Rect2).get_center()
	var aim := screen.global_transform * Vector3((at.x / Dashboard.PX.x - 0.5) * screen.width, (0.5 - at.y / Dashboard.PX.y) * screen.height(), 0.03)
	w.place(Transform3D(Basis(), Vector3(aim.x, 0.0, screen.global_position.z + 2.2)))
	await t._aim_point(w, aim)
	await t.get_tree().process_frame
	check(w._screen_key() == "bay0" and screen.cursor_on(), "looking at it up close puts the cursor on it")
	check(str(screen.hovered().get("act", {}).get("a", "")) == "card_assess", "over the Assess vehicle button (%s)" % str(screen.hovered().get("t", "")))
	check(w.info.contains("touch the screen"), "the panel says it can be touched")
	t._press("act")
	await t.get_tree().process_frame
	check(Workflow.assessed(bike), "a click touches it: assessed")
	t._press("interact")
	await t.get_tree().process_frame
	check(w.touch.focused == "bay0" and not w.controls_enabled, "E holds the cursor on the screen, and you stand still")
	t._press("menu")
	await t.get_tree().process_frame
	check(w.touch.focused == "" and w.controls_enabled and not main.menu.visible, "Esc lets go of it (and doesn't open the menu)")
	# Further back, out of the hands' reach, the screen high on the wall can still be touched.
	w.place(Transform3D(Basis(), Vector3(aim.x + 0.5, 0.0, screen.global_position.z + 3.6)))
	await t._aim_point(w, aim)
	await t.get_tree().process_frame
	check(w._screen_key() == "" and screen.cursor_on(), "from further back the cursor still finds the screen (%s)" % str(w.target.get("kind", "")))
	# Not from behind it, through the wall.
	var behind := screen.global_transform * Vector3(0.0, -1.0, -2.0)
	check(screen.page_point(behind, (screen.global_position - behind).normalized()) == null, "a screen can't be touched from behind")
	main._leave()
	main.queue_free()
	await t.get_tree().physics_frame
