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

var role := "host"
var main: Node
## Where the client wheels the trolley to.
var TROLLEY_XF := Transform3D(Basis(Vector3.UP, 0.5), Workshop.CENTER + Vector3(-1.5, 0.0, 3.0))
## Where the client puts its tray from the coffee shop down: on the cafe's floor.
var CAFE_TRAY_XF := Transform3D(Basis(), CoffeeShop.CENTER + Vector3(0.0, 0.0, 3.0))


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
		if ranger != 0 and not Shed.is_bolted(ranger, "exhaust") and dropped and tuned and Shed.crew.size() == 2 and board_ok and tv_ok and xp_ok and prints_ok and lights_ok and geo_ok and scrap_ok and weather_ok and money_ok and customer_ok and bell_ok and upgrade_ok and gear_ok and retrieve_ok and lift_ok and sales_ok and trolley_ok and emote_ok and cafe_ok:
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
	print("MP %s %s: saw the other player move=%s, shared shed in step=%s (bikes %d, crew %d, board marks %d, xp %s, picture %s, posters %d, scrapped %s, money %s, customers %d, extension %s, gear %s, retrieved %s, lift %s, sales %s, trolley %s, emotes %s, cafe %s)" % [
		"PASS" if ok else "FAIL", role, moved, shed_ok, Shed.bikes.size(), Shed.crew.size(), Shed.board["marks"].size(), xp_ok, _picture_ok(), Shed.posters.size(), scrap_ok, money_ok, Contracts.customers().size(), GarageUpgrades.owned("wing"), gear_ok, retrieve_ok, Shed.lifts.has(4), sales_ok, trolley_ok, emote_ok, cafe_ok])
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
