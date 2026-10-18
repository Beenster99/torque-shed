extends Node
## Two-process co-op check, run by tests/mp_test.sh: a host and a client each start the real
## game. The client must receive the host's shed, unbolt a part and put another down on the
## floor, tune a tyre pressure and change the crew board's channel, which the host must then see, each puts a mark on the whiteboard
## the other must see (the client also puts up a picture, sent in chunks, and the host makes a
## poster of the board that the client must get), the client's weather follows the host's, and
## both must see each other walk. The client also orders an A0 poster and, once it's in, carries
## it and scraps it: both must see it come and go. Money: the client's unbolting pays it a wage
## from the host, it sends some to the business (the host's ledger must show it) and the host
## sends the client some of its own cash, which must arrive.
## The host also sends a customer to reception, whom the client must see riding in on their bike.
## The host rings the sales office bell, and the client must hear it.
## The client buys bays 5 and 6 and raises bay 5's lift: both must see it go up.
## The client orders a trolley and a part, loads the box onto the trolley and wheels it into the
## shed: both must see the box, with its "for" note, ride on the trolley. The client waves and
## the host must see its figure wave; the host pings and the client must see it point.
## The host puts a biker out on the roads, and the client must see them riding along.
## Recovery: the host gives the garage the recovery rig and puts a crash rescue on the phone; the
## client takes the job on, gets in the truck (the host must see it driving) and parks it
## somewhere new: both must see the job's bike out at its site and the truck where it was left.
## Then the host gets in its passenger seat by the passenger door: the client must see the door
## swing open and the host sat in the cab (their figure gone from outside), and both see them out.
## Pool: the host racks up in the crew lounge and the client joins; each must see a shot the
## other took played out on its own table, and its own come back from the host.

var role := "host"
var main: Node
## Where the client wheels the trolley to.
var TROLLEY_XF := Transform3D(Basis(Vector3.UP, 0.5), Workshop.CENTER + Vector3(-1.5, 0.0, 3.0))
## Where the client puts its tray from the coffee shop down: on the cafe's floor.
var CAFE_TRAY_XF := Transform3D(Basis(), CoffeeShop.CENTER + Vector3(0.0, 0.0, 3.0))
var SPRAY_XF := Transform3D(Basis(), Workshop.CENTER + Vector3(-2.5, 0.0, 1.0))   # where the tank to spray is left


func _ready() -> void:
	# The old demo bikes these were written round (a player's new shed starts empty).
	Shed.demo_bikes = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Test %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join(" 127.0.0.1:24680 ")
	var deadline := Time.get_ticks_msec() + 40000
	var moved := false
	var shed_ok := false
	var start := Vector3.ZERO
	var span := AABB()
	var own := AABB()   # how far this side's own walker went (for the diagnostic)
	var own_seen := false
	var asked := false
	var xp_start := -1
	var xp_ok := false
	var postered := false
	var poster_seen := false
	var scrap_asked := false
	var scrap_ok := false
	var cash_start := -1
	var paid_ok := false
	var money_sent := false
	var money_ok := false
	var customer_sent := false
	var money_set := false
	var upgrade_asked := false
	var bays_asked := false
	var lift_asked := false
	var gear_asked := false
	var gear_ok := false
	var left_out := false
	var retrieve_asked := false
	var retrieve_ok := false
	var stood := false
	var listed_asked := false
	var offered := false
	var sales_ok := false
	var trolley_asked := false
	var trolley_box := 0
	var trolley_took := false
	var trolley_loaded := false
	var trolley_moved := false
	var trolley_ok := false
	var emote_sent := false
	var emote_ok := false
	var cafe_spawned := false
	var cafe_bought := false
	var cafe_down := false
	var cafe_ok := false
	var staff_hired := false
	var staff_asked := false
	var staff_ok := false
	var card_asked := false
	var card_ticked := false
	var card_ok := false
	var spray_made := false
	var spray_step := 0
	var spray_ok := false
	var paint_step := 0
	var paint_ok := false
	var traffic_ok := false
	var traffic_s := -1.0
	var paint_t := 0
	var bottle_seen := false    # the host saw the client's bottle tipped over the tin
	var bottle_back := false    # and back on the rack once the client let go (and stirred)
	var tare_seen := false      # the scale zeroed, on both sides
	var avatar_ok := false
	var graph_ok := false
	var rec_step := 0
	var rec_t := 0
	var rec_drove := false      # the host saw the client at the wheel; the client was driving
	var rec_ok := false
	var pass_step := 0
	var pass_t := 0
	var pass_seen := false     # the client saw the host sat in the passenger seat, its door open
	var pass_ok := false
	var REC_PARK := Recovery.PARK.translated(Vector3(-6.0, 0.0, 2.0))
	var wash_step := 0
	var wash_ok := false
	var shine_step := 0
	var shine_ok := false
	var pool_t := 0             # when this side last tried to shoot, msec
	var pool_own := false        # a shot this side took came back from the host
	var pool_other := false      # and one the other side took arrived here
	var pool_ok := false
	while Time.get_ticks_msec() < deadline and not (moved and shed_ok):
		await get_tree().physics_frame
		if not main.in_session:
			continue
		# Walk up and down so the other side sees movement.
		# Turn round every second of game time, not wall time: on a slow machine a wall-clock second
		# can be a handful of frames, too short a walk for the other side to see.
		var t := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_press("move_forward" if fmod(t, 2.0) < 1.0 else "move_back")
		if main.walker:
			if own_seen:
				own = own.expand(main.walker.global_position)
			else:
				own = AABB(main.walker.global_position, Vector3.ZERO)
				own_seen = true
		if main.remotes.size() == 1:
			var rp: RemotePlayer = main.remotes.values()[0]
			var p := rp.world_position()
			# Moved: the other player's walk spans more than 0.8 m (from wherever it was first seen).
			if start == Vector3.ZERO and p != Vector3.ZERO:
				start = p
				span = AABB(p, Vector3.ZERO)
			elif start != Vector3.ZERO:
				span = span.expand(p)
				if span.size.length() > 0.8:
					moved = true
		var ranger := _bike_named("Rusty Ranger")
		# Garage upgrades: the host puts money in the garage, the client buys the extension with
		# it, and both sheds are rebuilt with it.
		if role == "host" and not money_set:
			Shed.request({"a": "garage_money", "value": 100000})
			money_set = true
		if role == "client" and not upgrade_asked and Shed.garage_money >= GarageUpgrades.price("wing"):
			Shed.request({"a": "buy_upgrade", "id": "wing"})
			# And an epoxy floor in a colour and effect picked on the client.
			Shed.request({"a": "buy_upgrade", "id": "epoxy", "looks": {"colour": "blue", "effect": "gloss"}})
			upgrade_asked = true
		var ws: Workshop = main.world.workshop if main.world else null
		var upgrade_ok := GarageUpgrades.owned("wing") and ws != null and ws.get_node_or_null("Upgrades/Built/WingFloor") != null \
			and str(Shed.looks.get("epoxy", {}).get("colour", "")) == "blue" and str(ws.upgrades.looks_shown().get("epoxy", {}).get("effect", "")) == "gloss"
		# Bike lifts: the client buys bays 5 and 6 and raises bay 5's lift; both see it rise.
		if role == "client" and GarageUpgrades.owned("wing") and not bays_asked and Shed.garage_money >= GarageUpgrades.price("bays_56"):
			Shed.request({"a": "buy_upgrade", "id": "bays_56"})
			bays_asked = true
		if role == "client" and GarageUpgrades.owned("bays_56") and not lift_asked:
			Shed.request({"a": "lift", "bay": 4, "up": true})
			lift_asked = true
		var lift_node: Node3D = ws.get_node_or_null("Upgrades/Built/LiftBase4/Lift4") if ws != null else null
		var lift_ok := Shed.lifts.has(4) and lift_node != null and lift_node.position.y > 0.1
		# XP: the host pays the client for its work, and learns the client's level from its report.
		if xp_start < 0:
			xp_start = int(Progress.profile["xp"])
		if role == "client":
			xp_ok = int(Progress.profile["xp"]) > xp_start
		elif main.remotes.size() == 1:
			xp_ok = str(Progress.summary(main.remotes.keys()[0]).get("name", "")) == "Test client"
		if role == "client" and ranger != 0 and not asked:
			Shed.request({"a": "unbolt", "bike": ranger, "slot": "exhaust"})
			Shed.request({"a": "take", "spot": "bench_0"})
			Shed.request({"a": "drop", "xf": Transform3D(Basis(), Workshop.CENTER + Vector3(0.5, 0.0, 1.5))})
			Shed.board_request({"a": "board_draw", "id": 4242, "c": 1, "w": 6.0, "from": 0,
				"pts": PackedVector2Array([Vector2(100, 100), Vector2(300, 200)]), "done": true})
			Shed.request({"a": "tune", "bike": ranger, "key": "psi_f", "value": 0.9})
			Shed.request({"a": "tv_channel", "screen": "crew", "step": 1})
			# A picture big enough to go in several chunks.
			Shed.board_add_image(Shed.pack_image(_noise(400, 300)), Vector2(650, 120), Vector2(400, 300))
			Shed.request({"a": "lights", "room": "paint", "on": false})
			# Geometry mode: the client's fit for the tank reaches the host's shed.
			Shed.request({"a": "geo_save", "bike": ranger, "geo": {"tank": {"p": Vector3(0.0, 0.05, 0.0), "r": Vector3.ZERO, "s": Vector3.ONE}}})
			Shed.request({"a": "order_furniture", "model": "poster_mx", "psize": "a0"})
			asked = true
		# The A0 poster the client ordered arrives in that size; the client then scraps it.
		var mx := 0
		for fid in Shed.furniture:
			if Shed.furniture[fid]["model"] == "poster_mx":
				mx = fid
		if mx != 0 and str(Shed.furniture[mx].get("psize", "")) == "a0":
			poster_seen = true
		if role == "client" and mx != 0 and poster_seen and not scrap_asked:
			Shed.request({"a": "grab", "furniture": mx})
			Shed.request({"a": "scrap", "furniture": mx})
			scrap_asked = true
		scrap_ok = poster_seen and mx == 0
		# Money: wages reach the client, and transfers go both ways through the host.
		if cash_start < 0:
			cash_start = Progress.money()
		var ledger_ok: bool = Shed.bank["ledger"].any(func(e): return str(e["why"]) == "From Test client")
		if role == "client":
			paid_ok = paid_ok or Progress.money() > cash_start
			if paid_ok and not money_sent:
				money_sent = Money.send(0, 1) == ""
			var got: bool = Progress.profile["cash_log"].any(func(e): return str(e["why"]) == "From Test host")
			money_ok = paid_ok and ledger_ok and got
		else:
			if main.remotes.size() == 1 and not money_sent:
				Progress.earn(10, "Test")
				money_sent = Money.send(int(main.remotes.keys()[0]), 5) == ""
			money_ok = ledger_ok and money_sent
		# Rider gear: the client puts on an MX helmet, and the host sees it on the client's figure.
		if role == "client" and not gear_asked:
			Progress.profile["gear"]["owned"].append("helmet_mx")
			RiderGear.wear("helmet_mx")
			gear_asked = true
		if role == "client":
			gear_ok = RiderGear.worn_of(Shed.me())["helmet"] == "helmet_mx"
		elif main.remotes.size() == 1:
			var other: RemotePlayer = main.remotes.values()[0]
			gear_ok = other.gear.get("helmet", "") == "helmet_mx" and other._head_look.get_child_count() > 3
		# The other player is drawn whole for this side's first-person eye: on foot, and riding
		# (only your own rider's helmet and torso are left out of it).
		if main.remotes.size() == 1 and not avatar_ok and ranger != 0:
			var them: RemotePlayer = main.remotes.values()[0]
			var eye_hidden := func(n: Node) -> int:
				return n.find_children("*", "VisualInstance3D", true, false).filter(func(c):
					return (c as VisualInstance3D).layers & (1 << (BikeModel.HELMET_LAYER - 1)) != 0).size()
			if them.riding_bike == 0:
				var on_foot: int = eye_hidden.call(them._figure)
				them._start_riding(ranger)
				avatar_ok = on_foot == 0 and them.bike != null and not them.bike.model.own_rider and eye_hidden.call(them.bike) == 0
				them._stop_riding()
		# The money graphs: the business's series goes out with the shed, so both sides draw it.
		var rows: Array = Shed.bank.get("series", {}).get("minute", [])
		graph_ok = rows.size() >= 2 and int(Money.graph("minute")[-1]) == Shed.garage_money
		# A bike left out on the road: the host leaves Old Faithful out there, the client has the
		# recovery truck bring it back, and both see it back in the yard.
		var faithful := _bike_named("Old Faithful")
		if role == "host" and Shed.crew.size() == 2 and faithful != 0 and not left_out and Shed.garage_money >= 1000:
			Shed.bikes[faithful]["xf"] = Transform3D(Basis(), Vector3(150.0, 2.0, 20.0))
			Shed._mark_dirty()
			left_out = true
		if role == "client" and faithful != 0 and Shed.abandoned_bikes().has(faithful) and not retrieve_asked:
			Shed.request({"a": "retrieve_bike", "bike": faithful})
			retrieve_asked = true
		retrieve_ok = retrieve_ok or ((left_out or retrieve_asked) and faithful != 0 and Shed.bike_at_work(faithful)
			and (Shed.bikes[faithful]["xf"] as Transform3D).origin.distance_to(Shed.RETRIEVE_ROW) < 10.0)
		# The host makes a poster of the board once the client's picture is on it.
		if role == "host" and not postered and _picture_ok():
			Shed.request({"a": "board_poster", "name": "MP poster"})
			postered = true
		var prints_ok := _picture_ok() and Shed.posters.size() == 1 and Shed.poster_marks(Shed.posters.keys()[0]).any(func(m): return m.has("img"))
		# The host rings the sales office bell once the client is in: the client must hear it.
		if role == "host" and Shed.crew.size() == 2 and Shed.bells_heard == 0:
			Shed.ring_bell()
		var bell_ok := Shed.bells_heard > 0
		if role == "host" and Shed.crew.size() == 2 and not asked:
			Shed.board_request({"a": "board_text", "id": 4343, "c": 2, "s": 38, "at": Vector2(500, 300), "text": "Host's list"})
			asked = true
		# Each side's whiteboard marks reach the other.
		var board_ok := BoardData.find(Shed.board, 4242) >= 0 and BoardData.find(Shed.board, 4343) >= 0
		var dropped := false
		for id in Shed.floor_items():
			dropped = dropped or (Shed.items[id]["ref"] is Transform3D)
		var tuned := ranger != 0 and is_equal_approx(float(Shed.tune_of(ranger).get("psi_f", 0.0)), 0.9)
		var tv_ok: bool = Shed.screen_channel("crew")["ch"] == "live"   # the client changed the crew board's channel
		var lights_ok := not Shed.room_lit("paint")   # the client switched the paint shop lights off
		var geo_ok := ranger != 0 and Shed.geometry_of(ranger).has("tank")
		# And the bike in this side's shed is drawn with it straight away.
		if geo_ok and main.workshop:
			var gm: BikeModel = main.workshop.bike_model(ranger)
			var tank_at := gm.geo_xform("tank").origin - gm.geo_pivot("tank") if gm else Vector3.ZERO
			var gnode: Node3D = gm.find_child("Geo_tank", true, false) if gm else null
			geo_ok = gm != null and gm.geometry.has("tank") and absf(tank_at.y - 0.05) < 0.005 and gnode != null and absf(gnode.transform.origin.y - 0.05) < 0.005
			if not geo_ok and Engine.get_process_frames() % 120 == 0:
				print("MP %s geo waiting: model %s tank offset %s node %s" % [role, gm != null, tank_at, gnode.transform.origin if gnode else "none"])
		# Weather: the host holds it at fog and the client's sky follows.
		if role == "host" and Weather.current and Weather.current.state != "fog":
			Settings.weather = "fog"
			Weather.current.change_to("fog", true)
		var weather_ok := Weather.current != null and Weather.current.state == "fog"
		# Road traffic: the host puts a biker out on the roads, and the client sees them ride along.
		var tr: RoadTraffic = main.traffic
		if role == "host" and Shed.crew.size() == 2 and tr.active_count() == 0:
			tr.spawn_one(0.0, 600.0)
		if not traffic_ok and tr.active_count() > 0:
			var first: Dictionary = tr.riders.filter(func(d): return not d.is_empty())[0]
			if traffic_s < 0.0:
				traffic_s = float(first["s"])
			traffic_ok = absf(float(first["s"]) - traffic_s) > 2.0 and tr._views.any(func(v): return not v.is_empty())
		# Contracts: the host sends a customer to reception and the client sees them walk in.
		if role == "host" and Shed.crew.size() == 2 and not customer_sent:
			Shed.request({"a": "contract_spawn", "kind": "maint"})
			customer_sent = true
		# They ride in on their own bike, which both sides see.
		var customer_ok: bool = not Contracts.customers().is_empty() and not main.contracts_view.views.is_empty() \
			and main.contracts_view.views.values().any(func(v): return is_instance_valid(v) and (v as CustomerView).has_bike())
		# Selling: the host puts Barn Find on a showroom stand, the client lists it from its sales
		# PC, the host's buyer makes an offer, and both see the offer and hear the till.
		var barn := _bike_named("Barn Find")
		if role == "host" and Shed.crew.size() == 2 and barn != 0 and not stood:
			Shed.bikes[barn]["xf"] = Workshop.SHOWROOM_SPOTS[1]
			Shed._mark_dirty()
			stood = true
		if role == "client" and barn != 0 and Sales.stand_of(barn) >= 0 and not listed_asked:
			Shed.request({"a": "sale_list", "bike": barn, "ask": 4000, "margin": 0.2})
			listed_asked = true
		if role == "host" and barn != 0 and Sales.listings().has(barn) and not offered:
			offered = Sales.make_offer(barn) != 0
			Shed._mark_dirty()
		sales_ok = sales_ok or (barn != 0 and Sales.listings().has(barn) and not Sales.offers().is_empty() and main.sales_view.tills > 0)
		# A trolley: the client orders one and a part, loads the box (with its "for" note) onto
		# the trolley and wheels it into the shed; both see the box ride along on it.
		var trolley := 0
		for fid in Shed.furniture:
			if Shed.furniture[fid]["model"] == "trolley_parts":
				trolley = fid
		if role == "client" and Shed.crew.size() == 2 and not trolley_asked:
			Shed.request({"a": "order_furniture", "model": "trolley_parts"})
			Shed.request({"a": "order_part", "part": "iridium_plugs"})
			trolley_asked = true
		if trolley_box == 0:
			for iid in Shed.items:
				if Shed.items[iid]["part"] == "iridium_plugs" and Shed.items[iid].get("boxed", false) and str(Shed.items[iid].get("by", "")) == "Test client":
					trolley_box = iid
		var tkey := "f%d" % trolley
		if role == "client" and trolley != 0 and trolley_box != 0 and Shed.items.has(trolley_box):
			var tb: Dictionary = Shed.items[trolley_box]
			if not trolley_took and Shed.held_by(Shed.me()) == 0 and tb["at"] != "held" and not Shed.surface_items(tkey).has(trolley_box):
				Shed.request({"a": "take", "item": trolley_box} if tb["at"] == "floor" else {"a": "take", "spot": str(tb["ref"])})
				trolley_took = true
			elif not trolley_loaded and Shed.held_by(Shed.me()) == trolley_box:
				var place = Shed.find_room(tkey, trolley_box, Vector2.ZERO)
				if place is Transform3D:
					Shed.request({"a": "set_down", "top": tkey, "xf": place})
					trolley_loaded = true
			elif trolley_loaded and not trolley_moved and Shed.surface_items(tkey).has(trolley_box):
				Shed.request({"a": "grab", "furniture": trolley})
				Shed.request({"a": "move_furniture", "furniture": trolley, "xf": TROLLEY_XF})
				Shed.request({"a": "release", "furniture": trolley, "xf": TROLLEY_XF})
				trolley_moved = true
		if trolley != 0 and trolley_box != 0 and Shed.items.has(trolley_box) and Shed.surface_items(tkey).has(trolley_box) \
				and (Shed.furniture[trolley]["xf"] as Transform3D).origin.distance_to(TROLLEY_XF.origin) < 0.01 and ws != null:
			var on_view: Node3D = ws._spot_nodes.get(str(Shed.items[trolley_box]["ref"]))
			trolley_ok = on_view != null and ws.furniture_nodes.has(trolley) and ws.furniture_nodes[trolley].is_ancestor_of(on_view) \
				and on_view.get_node_or_null("OrderNote") != null
		# The coffee shop: a group of bikers rides in to the host's cafe and the client sees them on
		# their bikes; the client buys a coffee and puts its tray down, and the host sees it there.
		if role == "host" and Shed.crew.size() == 2 and not CoffeeShop.is_open() and Daylight.current:
			Daylight.current.set_time(10.0)
		if role == "host" and Shed.crew.size() == 2 and CoffeeShop.is_open() and not cafe_spawned:
			cafe_spawned = not CoffeeShop.spawn_group(3).is_empty()
			Shed.changed.emit()
		if role == "client" and Shed.crew.size() == 2 and CoffeeShop.is_open() and trolley_ok and scrap_ok and retrieve_ok and not cafe_bought \
				and Shed.held_by(Shed.me()) == 0:
			Progress.earn(10, "Test")
			cafe_bought = CoffeeShop.buy("coffee") == ""
		if role == "client" and cafe_bought and not cafe_down and CoffeeShop.carrying(Shed.me()):
			Shed.request({"a": "coffee_tray_down", "xf": CAFE_TRAY_XF})
			cafe_down = true
		var tray_seen := false
		for ct in CoffeeShop.trays().values():
			tray_seen = tray_seen or (int(ct["holder"]) == 0 and ct["items"] == ["coffee"] and (ct["xf"] as Transform3D).origin.distance_to(CAFE_TRAY_XF.origin) < 0.01)
		var bikers_seen: bool = main.coffee_view.views.values().any(func(v): return is_instance_valid(v) and (v as CoffeeVisitor).has_bike())
		cafe_ok = cafe_ok or (tray_seen and main.coffee_view.trays.size() >= 1 and bikers_seen)
		# Staff: the host takes on one of each, the client sends one off for teas (a request the
		# host checks and does), and both see every worker drawn and the tea run under way.
		if role == "host" and Shed.crew.size() == 2 and not staff_hired:
			Shed.request({"a": "staff_debug_hire_all"})
			staff_hired = true
		var tea_worker := 0
		for wid in Staff.workers():
			if str(Staff.workers()[wid]["role"]) == "reception":
				tea_worker = int(wid)
		if role == "client" and tea_worker != 0 and not staff_asked:
			Shed.request({"a": "staff_assign", "worker": tea_worker, "job": {"kind": "tea"}})
			staff_asked = true
		var on_tea := tea_worker != 0 and str(Staff.worker(tea_worker)["job"].get("kind", "")) == "tea"
		var tea_done := (Shed.staff.get("news", []) as Array).any(func(n): return str(n).contains("Tea's up"))
		staff_ok = staff_ok or (Staff.workers().size() == Staff.MAX_STAFF and main.staff_view.figures.size() == Staff.MAX_STAFF
			and (on_tea or tea_done))
		# Job cards: the client assesses the Rusty Ranger and the host ticks its first task off by
		# hand; both see the card with the tick (see Workflow).
		if role == "client" and ranger != 0 and Shed.crew.size() == 2 and not card_asked:
			Shed.request({"a": "card_assess", "bike": ranger})
			card_asked = true
		var card := Workflow.card(ranger)
		if role == "host" and card.get("tasks") is Array and not card_ticked:
			Shed.request({"a": "card_tick", "bike": ranger, "task": card["tasks"][0]["id"], "on": true})
			card_ticked = true
		card_ok = card_ok or (Workflow.assessed(ranger) and str(card.get("by", "")) == "Test client"
			and Workflow.is_done(ranger, card["tasks"][0]))
		# Emotes: the client waves and the host sees its figure wave; the host pings and the
		# client sees the host's figure point at it.
		if Shed.crew.size() == 2 and main.remotes.size() == 1 and not emote_sent:
			if role == "client":
				Shed.request({"a": "emote", "e": "wave"})
			else:
				Shed.request({"a": "ping", "at": Workshop.CENTER + Vector3(2.0, 1.0, 0.0), "what": "Over here"})
			emote_sent = true
		if main.remotes.size() == 1:
			var seen: Array = main.remotes.values()[0].emotes_seen
			emote_ok = seen.has("point") if role == "client" else seen.has("wave")
		if role == "host" and emote_sent and not emote_ok and main.remotes.size() == 1 and Engine.get_process_frames() % 240 == 0:
			# The client may not have been listening yet: ask again now and then.
			emote_sent = false
		if role == "client" and not emote_ok and emote_sent and Engine.get_process_frames() % 240 == 0:
			emote_sent = false
		# Hand spraying: the host leaves a bare tank on the floor; the client primes it, paints
		# it and lacquers it with spray cans, every coat checked by the host, and both see the
		# three coats on it.
		if role == "host" and Shed.crew.size() == 2 and not spray_made:
			var st := Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[0])
			Shed._move(st, "floor", SPRAY_XF)
			Shed._mark_dirty()
			spray_made = true
		var spray_tank := 0
		for iid in Shed.items:
			var si: Dictionary = Shed.items[iid]
			if si["part"] == "cafe_15" and si["at"] == "floor" and si["ref"] is Transform3D and (si["ref"] as Transform3D).origin.distance_to(SPRAY_XF.origin) < 0.01:
				spray_tank = iid
		if role == "client" and spray_tank != 0:
			var sit: Dictionary = Shed.items[spray_tank]
			if spray_step == 0:
				Shed.request({"a": "prime", "item": spray_tank, "quality": 0.9, "waste": 0.0})
				spray_step = 1
			elif spray_step == 1 and sit.get("primer_top", false):
				Shed.request({"a": "paint", "item": spray_tank, "color": 2, "finish": "gloss", "quality": 0.8, "waste": 0.0})
				spray_step = 2
			elif spray_step == 2 and sit.has("paint_quality") and not sit.get("primer_top", false):
				Shed.request({"a": "coat", "item": spray_tank, "coat": "clear", "quality": 0.9, "waste": 0.0})
				spray_step = 3
		if spray_tank != 0:
			var sd: Dictionary = Shed.items[spray_tank]
			spray_ok = float(sd.get("primer", 0.0)) > 0.5 and float(sd.get("paint_quality", 0.0)) > 0.8 \
				and str(sd.get("coat", "")) == "clear" and not sd.get("primer_top", false) and sd["color"] == Shed.PAINTS[2]
		# The paint mixing bay: the client buys a bottle of tint with garage money, steps up to the
		# bench, weighs blue into a tin of white, stirs it and saves it as "MP Blue"; the host checks
		# every step and both see its tin on the shelf and its card on the swatch wall.
		if role == "client" and spray_ok and Shed.crew.size() == 2:
			match paint_step:
				0:
					Shed.request({"a": "paint_buy", "code": "PB", "n": 1})
					Shed.request({"a": "paint_bench", "on": true})
					paint_step = 1
				1:
					if PaintBay.at_bench() == Shed.me():
						Shed.request({"a": "paint_tin_new", "base": "W"})
						paint_step = 2
				2:
					if not PaintBay.bench_tin().is_empty():
						Shed.request({"a": "paint_pour", "tint": "PB", "g": 20.0, "tilt": 0.6, "seq": 1})
						paint_t = Engine.get_physics_frames()
						paint_step = 5
				5:
					# Holding the bottle tipped a moment, then letting go, zeroing the scale and stirring.
					if Engine.get_physics_frames() - paint_t > 20:
						Shed.request({"a": "paint_pour_stop"})
						Shed.request({"a": "paint_tare"})
						Shed.request({"a": "paint_stir", "amount": 0.5})
						Shed.request({"a": "paint_stir", "amount": 0.5})
						paint_step = 3
				3:
					if float(PaintBay.bench_tin().get("stir", 0.0)) > 0.95 and float(PaintBay.bench_tin().get("tints", {}).get("PB", 0.0)) > 19.0 and tare_seen:
						Shed.request({"a": "paint_tin_save", "name": "MP Blue"})
						Shed.request({"a": "paint_bench", "on": false})
						paint_step = 4
		if PaintBay.tared(PaintBay.bench_tin()) and absf(PaintBay.net_grams(PaintBay.bench_tin(), PaintMix.total_grams(PaintBay.bench_tin()))) < 0.01:
			tare_seen = true
		if role == "host" and ws != null and ws.paint_bay != null and PaintBay.at_bench() != 0 and PaintBay.at_bench() != Shed.me():
			if ws.paint_bay._pour_bottle != null and ws.paint_bay._pour_code == "PB":
				bottle_seen = true
			elif bottle_seen and tare_seen and ws.paint_bay._pour_bottle == null and (ws.paint_bay._rack_bottles["PB"][0] as Node3D).visible:
				bottle_back = true
		var mp_blue := PaintBay.recipes().values().filter(func(r): return str(r["name"]) == "MP Blue")
		if not mp_blue.is_empty() and ws != null and ws.paint_bay != null:
			var cards := ws.paint_bay.find_children("*", "StaticBody3D", true, false).filter(func(b): return str(b.get_meta("paint_bay", "")) == "swatch")
			var shelved := PaintBay.tins().values().filter(func(t): return str(t.get("name", "")) == "MP Blue" and str(t["at"]) == "shelf")
			paint_ok = cards.size() >= 1 and shelved.size() == 1 and float(PaintBay.stock_of("PB")) > PaintBay.STARTER_TINT - 20.0 \
				and str(mp_blue[0]["code"]).begins_with("W-PB20") and PaintBay.at_bench() == 0 and tare_seen and (role != "host" or bottle_back)
		# Recovery (see the top): the host grants the rig and a job, the client drives off with it.
		if Shed.crew.size() == 2 and main.remotes.size() == 1:
			if role == "host" and rec_step == 0:
				Shed.request({"a": "recovery_grant"})
				Shed.request({"a": "recovery_spawn", "kind": "crash"})
				rec_step = 1
			if role == "client":
				match rec_step:
					0:
						if Recovery.owned() and not Recovery.offers().is_empty():
							Shed.request({"a": "recovery_accept", "offer": int(Recovery.offers().keys()[0])})
							rec_step = 1
					1:
						if not Recovery.jobs().is_empty() and Recovery.driver() == 0:
							Shed.request({"a": "recovery_enter"})
							rec_step = 2
					2:
						# Asked again now and then: the host turns it down while this player's still busy
						# with an earlier step (just as a player would press F again).
						if not main.recovery.driving and Recovery.driver() == 0 and Engine.get_process_frames() % 60 == 0:
							Shed.request({"a": "recovery_enter"})
						if main.recovery.driving:
							rec_drove = true
							rec_t += 1
							if rec_t > 90:
								main.recovery.car.place(REC_PARK)
								main.recovery.trailer.place(Recovery.trailer_park(REC_PARK))
								main.recovery.stop_driving()
								rec_step = 3
			if role == "host" and Recovery.driver() != 0 and (main.remotes.values()[0] as RemotePlayer).driving:
				rec_drove = true
		var rv: RecoveryView = main.recovery
		var rec_job_ok := Recovery.jobs().size() == 1 and Shed.bikes.has(int(Recovery.jobs().values()[0]["bike"]))
		rec_ok = rec_ok or (rec_drove and rec_job_ok and Recovery.driver() == 0 and rv.car != null
			and (Recovery.car()["xf"] as Transform3D).origin.distance_to(REC_PARK.origin) < 0.3
			and rv.car.global_position.distance_to(REC_PARK.origin) < 0.3)
		# The passenger seat (see the top): the host gets in once the truck's parked, sits a
		# couple of seconds and gets out; the client sees the door swing and them sat in the cab.
		if rec_ok and rv.car != null and main.remotes.size() == 1:
			var other: RemotePlayer = main.remotes.values()[0]
			if role == "host":
				match pass_step:
					0:
						if Recovery.driver() == 0 and Engine.get_process_frames() % 30 == 0:
							Shed.request({"a": "recovery_board"})
						if rv.riding_along:
							pass_step = 1
					1:
						pass_t += 1
						if pass_t > 150:
							rv.stop_riding_along()
							pass_step = 2
					2:
						pass_ok = Recovery.passenger() == 0 and not rv.riding_along and main.walker.visible
			else:
				if Recovery.passenger() == other.peer and rv._seat_figs.has(other.peer) and float(rv.car.door_open[0]) > 0.0 \
						and not other._figure.visible:
					pass_seen = true
				pass_ok = pass_seen and Recovery.passenger() == 0 and rv._seat_figs.is_empty() and other._figure.visible
		# Pressure washing together: the host mucks up the Ranger's front tyre, fork and engine and
		# washes half the dirt off the tyre; the client washes half off the fork and calls the
		# engine clean, with its jet firing; both see all three, and the host sees the client's water.
		if ranger != 0 and Shed.crew.size() == 2:
			var w_tyre := Shed.item_on(ranger, "front_tyre")
			var w_fork := Shed.item_on(ranger, "fork")
			var w_engine := Shed.item_on(ranger, "engine")
			var all_cells := func(f: float) -> Dictionary:
				var d := {}
				for k in Dirt.CELLS:
					d[k] = f
				return d
			if role == "host" and wash_step == 0 and w_tyre != 0 and w_fork != 0 and w_engine != 0:
				var muck := PackedFloat32Array()
				muck.resize(Dirt.CELLS)
				muck.fill(0.8)
				for wid in [w_tyre, w_fork, w_engine]:
					Dirt.store(Shed.items[wid], muck)
				# Washing's done in the wash bay, so the Ranger goes in there first.
				Shed.bikes[ranger]["xf"] = Transform3D(Basis(), Workshop.WASH_CENTER)
				Shed._mark_dirty()
				Shed.request({"a": "wash_cells", "bike": ranger, "parts": {w_tyre: all_cells.call(0.5)}, "clean": []})
				wash_step = 1
			if role == "client" and wash_step == 0 and w_fork != 0 and absf(float(Shed.items[w_fork]["dirt"]) - 0.8) < 0.01 \
					and absf(float(Shed.items[w_tyre]["dirt"]) - 0.4) < 0.01:
				Shed.request({"a": "wash_aim", "fire": true, "bike": ranger, "at": (Shed.bikes[ranger]["xf"] as Transform3D).origin + Vector3.UP * 0.5, "n": Vector3.RIGHT})
				Shed.request({"a": "wash_cells", "bike": ranger, "parts": {w_fork: all_cells.call(0.5)}, "clean": [w_engine]})
				wash_step = 1
			var seen_water: bool = role == "client" or (main.remotes.size() == 1 and ws != null and ws._wash_fx.has(int(main.remotes.keys()[0])))
			wash_ok = wash_ok or (w_tyre != 0 and absf(float(Shed.items[w_tyre]["dirt"]) - 0.4) < 0.01 and absf(float(Shed.items[w_fork]["dirt"]) - 0.4) < 0.01
				and float(Shed.items[w_engine]["dirt"]) == 0.0 and Dirt.side(Dirt.cells(Shed.items[w_fork], "fork"), 0) < 0.41 and seen_water)
		# Detailing together, once it's washed: the client polishes the Ranger's tank to a deep gloss
		# (as its mini game sends it), the host's AI-style step lays a ceramic coat on; both see
		# both, and the host's Ranger is drawn with its finish.
		if ranger != 0 and wash_ok and Shed.crew.size() == 2 and Shed.item_on(ranger, "tank") != 0:
			var s_tank := Shed.item_on(ranger, "tank")
			if role == "client" and shine_step == 0:
				var fin := Detail.data(Shed.items[s_tank])
				var shiny := PackedByteArray()
				shiny.resize(Dirt.CELLS)
				shiny.fill(240)
				fin["g"] = shiny
				Shed.request({"a": "shine_cells", "bike": ranger, "parts": {s_tank: fin}})
				shine_step = 1
			var s_st := Detail.part_stats(Shed.items[s_tank])
			if role == "host" and shine_step == 0 and float(s_st["gloss"]) > 0.9:
				Shed.request({"a": "shine_step", "bike": ranger, "step": "coat", "amount": 5.0, "skill": 1.0})
				shine_step = 1
			var drawn: bool = role == "client" or (ws != null and ws.bike_model(ranger) != null and ws.bike_model(ranger).finish_layer != null)
			shine_ok = shine_ok or (float(s_st["gloss"]) > 0.9 and float(s_st["coat"]) > 0.5 and drawn)
		# Pool in the crew lounge: the host gives the garage the lounge and racks up, the client
		# joins, and they take turns at the table until each has seen a shot the other took
		# played out on its own table.
		if Shed.crew.size() == 2:
			if role == "host" and not GarageUpgrades.owned("lounge"):
				Shed.request({"a": "garage_money", "value": Shed.garage_money + GarageUpgrades.price("lounge")})
				Shed.request({"a": "buy_upgrade", "id": "lounge"})
			if role == "host" and GarageUpgrades.owned("lounge") and not PoolGame.playing() and Time.get_ticks_msec() > pool_t + 1000:
				pool_t = Time.get_ticks_msec()
				Shed.request({"a": "pool_rack"})
			var pool_players: Array = Shed.pool["players"]
			if role == "client" and PoolGame.playing() and not pool_players.has(Shed.me()) and pool_players.size() < 2 \
					and Time.get_ticks_msec() > pool_t + 1000:
				pool_t = Time.get_ticks_msec()
				Shed.request({"a": "pool_join"})
			var pool_view: PoolView = ws.get_node_or_null("Upgrades/Built/PoolTable") if ws else null
			if PoolGame.shooter() == Shed.me() and pool_players.size() == 2 and Time.get_ticks_msec() > pool_t + 1500 \
					and pool_view != null and pool_view._sim.is_empty():
				# At whichever ball's still on the table, or a full-power break.
				pool_t = Time.get_ticks_msec()
				var pb: Array = Shed.pool["balls"]
				var angle := 0.003
				if int(Shed.pool["shots"]) > 0:
					for bi in range(1, 16):
						if bool(pb[bi][2]) and bi != 8:
							angle = atan2(float(pb[bi][0]) - float(pb[0][0]), -(float(pb[bi][1]) - float(pb[0][1])))
							break
				Shed.request({"a": "pool_shot", "angle": angle, "power": 1.0 if int(Shed.pool["shots"]) == 0 else 0.6})
			var pool_by := int(Shed.pool["last"].get("by", 0))
			var played_out: bool = pool_view != null and pool_view._shown == int(Shed.pool["last"].get("n", -2)) \
				and pool_view._sim.is_empty()
			if pool_by == Shed.me() and played_out:
				pool_own = true
			elif pool_by != 0 and played_out:
				pool_other = true
			pool_ok = pool_own and pool_other
		if ranger != 0 and not Shed.is_bolted(ranger, "exhaust") and dropped and tuned and Shed.crew.size() == 2 and board_ok and tv_ok and xp_ok and prints_ok and lights_ok and geo_ok and scrap_ok and weather_ok and money_ok and customer_ok and bell_ok and upgrade_ok and gear_ok and retrieve_ok and lift_ok and sales_ok and trolley_ok and emote_ok and cafe_ok and staff_ok and spray_ok and paint_ok and traffic_ok and avatar_ok and graph_ok and rec_ok and pass_ok and wash_ok and shine_ok and pool_ok and card_ok:
			shed_ok = true
	# Keep running for a moment so the other side can finish its own check: the client stays (and
	# keeps walking) until the host has finished and gone, or 20 s at most.
	var linger := Time.get_ticks_msec() + (20000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and shed_ok and not main.in_session:
			break
		var tl := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_press("move_forward" if fmod(tl, 2.0) < 1.0 else "move_back")
	var ok := moved and shed_ok
	print("MP note %s: own walk span %s; the other player: remotes %d, first seen %s, span %s" % [
		role, own.size, main.remotes.size(), start, span.size])
	print("MP %s %s: saw the other player move=%s, shared shed in step=%s (bikes %d, crew %d, board marks %d, xp %s, picture %s, posters %d, scrapped %s, money %s, customers %d, extension %s, gear %s, retrieved %s, lift %s, sales %s, trolley %s, emotes %s, cafe %s, staff %s, spray coats %s, paint bay %s, traffic %s, avatar whole %s, graphs %s, recovery %s, passenger %s, washing %s, detailing %s, pool shots each way %s/%s, job card %s)" % [
		"PASS" if ok else "FAIL", role, moved, shed_ok, Shed.bikes.size(), Shed.crew.size(), Shed.board["marks"].size(), xp_ok, _picture_ok(), Shed.posters.size(), scrap_ok, money_ok, Contracts.customers().size(), GarageUpgrades.owned("wing"), gear_ok, retrieve_ok, Shed.lifts.has(4), sales_ok, trolley_ok, emote_ok, cafe_ok, staff_ok, spray_ok, paint_ok, traffic_ok, avatar_ok, graph_ok, rec_ok, pass_ok, wash_ok, shine_ok, pool_own, pool_other, card_ok])
	get_tree().quit(0 if ok else 1)


## Whether a picture is up on the board with its bytes here, decoded and drawable.
func _picture_ok() -> bool:
	for m in Shed.board["marks"]:
		if m.has("img") and Shed.image_texture(int(m["img"])) != null:
			return true
	return false


func _noise(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(rng.randf(), float(y) / h, float(x) / w))
	return img


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0
