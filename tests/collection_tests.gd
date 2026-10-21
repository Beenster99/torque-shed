extends RefCounted
## The crew's own bike collections at their houses (Collection, HomePlots, HomesView, HomeDisplay,
## HomePanel, HomeOfferPanel), run from tests/run_tests.gd (its _test_collection_* functions hand
## over to these).

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


## The shed's own finished bikes, free to sell.
func _for_sale() -> Array:
	var out := []
	for id in Shed.bikes:
		if Shed.is_complete(id) and Collection.check(Shed.me(), {"a": "home_buy", "bike": id, "paid": Progress.MAX_MONEY}) == "":
			out.append(int(id))
	return out


## A new finished bike in the shed (ordered new, as BikeCopy does), returned by id.
func _new_bike() -> int:
	var src := {}
	for id in Shed.bikes:
		if Shed.is_complete(id):
			src = {"bike": int(id)}
	if src.is_empty():
		# Every finished one's been bought: one like the first in a collection.
		var l := Collection.look(Collection.entry(int(Collection.bikes().keys()[0]))["pack"])
		src = {"build": {"name": l["name"], "parts": l["parts"], "paint": l["paint"]}}
	var before := Shed.bikes.keys()
	var cost := BikeCopy.total(BikeCopy.lines(BikeCopy.plan_of(src), Shed.me(), 1.0))
	Progress.set_money(Progress.money() + cost)
	BikeCopy.order(src, 1.0)
	for id in Shed.bikes:
		if not before.has(id):
			return int(id)
	return 0


## Buys a bike for this player's collection, with the money for it. Returns its collection id.
func _buy_one() -> int:
	var b: int = _for_sale()[0] if not _for_sale().is_empty() else _new_bike()
	Progress.set_money(Progress.money() + Collection.buy_price(b))
	var before := Collection.bikes().keys()
	Collection.buy(b)
	for cid in Collection.bikes():
		if not before.has(cid):
			return int(cid)
	return 0


## Slots by level: three to start, one more every two levels, never more than twenty.
func test_slots() -> void:
	check(Collection.slots_for_level(1) == 3 and Collection.slots_for_level(2) == 3 and Collection.slots_for_level(3) == 4
		and Collection.slots_for_level(5) == 5, "three slots at the start, a fourth at level 3, a fifth at level 5")
	check(Collection.slots_for_level(35) == 20 and Collection.slots_for_level(Progress.MAX_LEVEL) == 20 and Collection.slots_for_level(999) == 20,
		"twenty at level 35, and never more")
	var rising := true
	for lv in range(1, Progress.MAX_LEVEL + 1):
		var s := Collection.slots_for_level(lv)
		if s < Collection.slots_for_level(maxi(1, lv - 1)) or s > 20 or s < 3:
			rising = false
	check(rising, "slots only go up with the levels, between 3 and 20")
	var round_trip := true
	for s in range(3, 21):
		if Collection.slots_for_level(Collection.level_for_slots(s)) != s or (s > 3 and Collection.slots_for_level(Collection.level_for_slots(s) - 1) != s - 1):
			round_trip = false
	check(round_trip, "level_for_slots is the level each slot comes at")
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.profile["xp"] = Progress.xp_for_level(9)
	check(Collection.slots_of(Shed.me()) == 7, "your slots go by your own level (level 9: 7)")
	Shed._add_crew(FRIEND, "Pal")
	Progress._summaries[FRIEND] = {"level": 21}
	check(Collection.slots_of(FRIEND) == 13, "and a friend's by the level they report (level 21: 13)")
	Progress._summaries.erase(FRIEND)
	Progress.profile = saved
	Shed.stop()


## The house plots: within 1 km of the shed, clear of the roads, the town and the map's own
## buildings, apart from each other, with a drive out to a road; and the land under them level.
func test_plots() -> void:
	var data := World._data_for(1234)
	var roads: WorldRoads = data["roads"]
	var terrain: WorldTerrain = data["terrain"]
	check(HomePlots.PLOTS.size() >= Net.MAX_PLAYERS, "a plot for every player a shed can have (%d)" % HomePlots.PLOTS.size())
	var far := 0.0
	var shed := Vector2(Workshop.CENTER.x, Workshop.CENTER.z)
	for i in HomePlots.PLOTS.size():
		for c in HomePlots.corners(i):
			far = maxf(far, c.distance_to(shed))
	check(far < 1000.0, "every house is within 1 km of the shed (the furthest corner %.0f m)" % far)
	var on_road := []
	var in_town := []
	for i in HomePlots.PLOTS.size():
		var r := HomePlots.RECT
		for gx in range(int(r.position.x), int(r.end.x) + 1, 2):
			for gz in range(int(r.position.y), int(r.end.y) + 1, 2):
				var p := HomePlots.to_map(i, Vector2(gx, gz))
				var near := roads.nearest(p.x, p.y, 30.0)
				if not near.is_empty() and float(near["d"]) < float(roads.roads[int(near["road"])]["hw"]) + 1.0 and not on_road.has(i):
					on_road.append(i)
				if WorldTerrain.HOME.has_point(p) and not in_town.has(i):
					in_town.append(i)
	check(on_road.is_empty(), "no house or courtyard on a road %s" % str(on_road))
	check(in_town.is_empty(), "nor in the town round the shed %s" % str(in_town))
	var hit := []
	for b in data["props"]["buildings"]:
		var at: Vector3 = (b["xf"] as Transform3D).origin
		var size: Vector3 = b.get("size", Vector3.ONE * 8.0) if b.get("size") is Vector3 else Vector3.ONE * 8.0
		if HomePlots.on_plot(at.x, at.z, maxf(size.x, size.z) * 0.5):
			hit.append(str(b["kind"]))
	check(hit.is_empty(), "nor on any of the map's own buildings %s" % str(hit))
	var apart := INF
	for i in HomePlots.PLOTS.size():
		for j in range(i + 1, HomePlots.PLOTS.size()):
			apart = minf(apart, (HomePlots.PLOTS[i]["at"] as Vector2).distance_to(HomePlots.PLOTS[j]["at"]))
	check(apart > 80.0, "the houses don't overlap each other (the closest two %.0f m apart)" % apart)
	var no_drive := []
	for i in HomePlots.PLOTS.size():
		var end := HomePlots.to_map(i, Vector2((HomePlots.GATE_X.x + HomePlots.GATE_X.y) * 0.5, HomePlots.DRIVE_TO + 1.0))
		var near := roads.nearest(end.x, end.y, 30.0)
		if near.is_empty() or float(near["d"]) > float(roads.roads[int(near["road"])]["hw"]) + 3.0:
			no_drive.append(i)
	check(no_drive.is_empty(), "every drive reaches a road %s" % str(no_drive))
	var lumpy := []
	for i in HomePlots.PLOTS.size():
		var lv := HomePlots.level(i)
		# Inside the last grid square of its edges (the walls go down past a road's banking).
		for c in HomePlots.corners(i, -WorldTerrain.SPACING - 0.5):
			if absf(terrain.height_at(c.x, c.y) - (lv - 0.1)) > 0.3:
				lumpy.append(i)
				break
	check(HomePlots.levels.size() == HomePlots.PLOTS.size() and lumpy.is_empty(), "the land under each house is levelled %s" % str(lumpy))
	var styles := {}
	for n in ["Simon", "Pal", "Dave", "Jo", "Kim", "Sam", "Alex", "Chris", "Lee", "Ash"]:
		styles[HomePlots.style_for(n)] = true
		check(HomePlots.style_for(n) == HomePlots.style_for(n.to_upper() + " "), "a player's house style comes from their name (%s)" % n)
	check(styles.size() >= 3, "and the crew's houses come in different styles (%s)" % str(styles.keys()))


## The display ring: twenty places in the courtyard, each bike facing the middle, with its stand
## in front of it facing the middle too.
func test_ring() -> void:
	var plot := 2
	var c := HomePlots.frame(plot).origin
	var ok := true
	var gap := INF
	var spots := []
	for s in HomePlots.RING_SPOTS:
		var xf := HomePlots.ring_xf(plot, s)
		var sxf := HomePlots.stand_xf(plot, s)
		var to_mid := (c - xf.origin).normalized()
		var fwd := -xf.basis.z
		var stand_face := sxf.basis.z
		if fwd.dot(to_mid) < 0.99 or stand_face.dot((c - sxf.origin).normalized()) < 0.99:
			ok = false
		if absf(xf.origin.distance_to(c) - HomePlots.RING_R) > 0.01 or absf(sxf.origin.distance_to(xf.origin) - HomePlots.STAND_IN) > 0.01:
			ok = false
		if not HomePlots.in_courtyard(plot, xf.origin) or not HomePlots.in_courtyard(plot, sxf.origin):
			ok = false
		var local := HomePlots.to_local(plot, xf.origin)
		if HomePlots.HOUSE.grow(1.0).has_point(local) or HomePlots.GARAGE.grow(1.0).has_point(local):
			ok = false
		for p in spots:
			gap = minf(gap, (p as Vector3).distance_to(xf.origin))
		spots.append(xf.origin)
	check(HomePlots.RING_SPOTS == Collection.MAX_SLOTS, "a place in the ring for every bike a collection can hold")
	check(ok, "each bike faces the middle of the ring in the courtyard, its stand in front of it facing the middle")
	check(gap > 2.0, "with room between them (%.2f m)" % gap)
	check(HomePlots.in_courtyard(plot, HomePlots.pickup_xf(plot).origin) and HomePlots.in_courtyard(plot, HomePlots.gate(plot) - HomePlots.frame(plot).basis.z * 0.5),
		"the pick-up place by the garages and the gate are in the courtyard")
	check(not HomePlots.in_courtyard(plot, c + Vector3(0, 0, 0) + HomePlots.frame(plot).basis.z * 40.0) and not HomePlots.in_courtyard(plot, c + Vector3.UP * 6.0),
		"out on the road, or up above it, isn't")


## Buying a bike from the business with your own money: refused when short of money or when the
## collection is full; bought, it's out of the shed and on show at your house.
func test_buy() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	Progress.profile["xp"] = 0
	var who := Collection.name_of(Shed.me())
	var plot := Collection.plot_of(who)
	check(plot >= 0 and Collection.style_of(who) == HomePlots.style_for(who), "a new shed gives you a house (plot %d, %s)" % [plot, Collection.style_of(who)])
	var list := _for_sale()
	var b: int = list[0] if not list.is_empty() else _new_bike()
	var price := Collection.buy_price(b)
	check(price > 0, "a finished shed bike has a price (%s)" % Collection.money(price))
	var unfinished := 0
	for id in Shed.bikes:
		if not Shed.is_complete(id) and not Sales.is_customer_bike(id):
			unfinished = id
	if unfinished != 0:
		check(Collection.check(Shed.me(), {"a": "home_buy", "bike": unfinished, "paid": Progress.MAX_MONEY}).contains("finished"),
			"an unfinished one can't be bought")
	Progress.set_money(price - 1)
	var garage := Shed.garage_money
	var said := Collection.buy(b)
	check(said.contains("you have") and Progress.money() == price - 1 and Shed.bikes.has(b) and Collection.count_of(who) == 0,
		"short of money: refused, nothing taken (%s)" % said)
	# Paid short to the host (the price went up): refunded in full.
	Progress.set_money(1000)
	Shed.request({"a": "home_buy", "bike": b, "paid": 10})
	check(Progress.money() == 1010 and Shed.bikes.has(b), "a buy paid short is turned down and the money comes back")
	Progress.set_money(price + 250)
	var name := str(Shed.bikes[b]["name"])
	said = Collection.buy(b)
	check(said == "" and Progress.money() == 250 and Shed.garage_money == garage + price, "bought from your own money, paid to the business")
	check(not Shed.bikes.has(b) and Collection.count_of(who) == 1, "it's out of the shed and in your collection")
	var cid: int = Collection.bikes_of(who)[0]
	var e := Collection.entry(cid)
	check(str(e["name"]) == name and int(e["paid"]) == price and int(e["value"]) > 0 and Collection.on_show(plot, int(e["spot"])) == cid,
		"on show at your house, what you paid noted")
	var items_of_bike := 0
	for id in Shed.items:
		if str(Shed.items[id].get("at", "")) == "bike" and int(Shed.items[id].get("ref", 0)) == b:
			items_of_bike += 1
	check(items_of_bike == 0 and (e["pack"]["items"] as Dictionary).size() > 20, "every part of it went with it")
	var deal: Dictionary = (Shed.sales["deals"] as Array)[0]
	check(str(deal["buyer"]) == who and str(deal["kind"]) == "crew" and int(deal["price"]) == price, "the sale is in the business's books, to you")
	_buy_one()
	_buy_one()
	check(Collection.count_of(who) == 3, "three bikes: a full collection at level 1")
	var more: int = _for_sale()[0] if not _for_sale().is_empty() else _new_bike()
	Progress.set_money(Collection.buy_price(more) + 5)
	said = Collection.buy(more)
	check(said.contains("full") and said.contains("level 3") and Shed.bikes.has(more), "a fourth is refused: full, and it says when another slot comes (%s)" % said)
	Progress.profile["xp"] = Progress.xp_for_level(3)
	check(Collection.buy(more) == "" and Collection.count_of(who) == 4, "at level 3 there's room for a fourth")
	Progress.profile = saved
	Shed.stop()


## Taking a bike out of the collection and bringing it back: it leaves the display while it's
## out and goes back on show once parked in the courtyard; a friend can't ride it or wheel it off.
func test_take() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var me := Shed.me()
	var who := Collection.name_of(me)
	var plot := Collection.plot_of(who)
	var cid := _buy_one()
	var spot := int(Collection.entry(cid)["spot"])
	Shed._add_crew(FRIEND, "Pal")
	check(Shed.check(FRIEND, {"a": "home_take", "bike": cid}).contains("only they"), "a friend can't take your bike out")
	Shed.request({"a": "home_take", "bike": cid})
	var id := int(Collection.entry(cid)["out"])
	check(id != 0 and Shed.bikes.has(id) and Collection.on_show(plot, spot) == 0, "taken out: it's off the display and a bike again")
	var xf: Transform3D = Shed.bikes[id]["xf"]
	check(HomePlots.in_courtyard(plot, xf.origin) and xf.origin.distance_to(HomePlots.pickup_xf(plot).origin) < 12.0,
		"left in front of the garages, at the house, not at the shed (%.0f m from the shed)" % xf.origin.distance_to(Workshop.CENTER))
	check(Shed.is_complete(id) and Collection.owner_of_bike(id) == who and Sales.is_customer_bike(id), "whole, and yours: not one the shed can sell")
	check(Shed.check(FRIEND, {"a": "mount", "bike": id}).contains("only they can ride it") and Shed.check(FRIEND, {"a": "grab_bike", "bike": id}).contains("only they"),
		"a friend can't ride it or wheel it off")
	check(Shed.check(me, {"a": "home_take", "bike": cid}).contains("out already"), "it can't be taken out twice")
	check(Shed.check(me, {"a": "mount", "bike": id}) == "", "you can get on it")
	Shed.request({"a": "mount", "bike": id})
	# Ridden to the shed and parked there, it stays out.
	var yard := Transform3D(Basis(), Workshop.CENTER + Vector3(0.0, 0.0, 12.0))
	Shed.request({"a": "dismount", "bike": id, "xf": yard})
	check(Shed.bikes.has(id) and int(Collection.entry(cid)["out"]) == id, "parked anywhere else, it stays out")
	Shed.request({"a": "mount", "bike": id})
	Shed.request({"a": "dismount", "bike": id, "xf": HomePlots.frame(plot) * Transform3D(Basis(), Vector3(3.0, 0.0, 9.0))})
	var e := Collection.entry(cid)
	check(not Shed.bikes.has(id) and int(e["out"]) == 0 and Collection.on_show(plot, spot) == cid and e.get("pack") is Dictionary,
		"parked back in the courtyard: back on show in its place")
	# Wheeled in by hand works too.
	Shed.request({"a": "home_take", "bike": cid})
	id = int(Collection.entry(cid)["out"])
	Shed.request({"a": "grab_bike", "bike": id})
	Shed.request({"a": "release_bike", "bike": id, "xf": HomePlots.frame(plot) * Transform3D(Basis(), Vector3(-4.0, 0.0, 6.0))})
	check(not Shed.bikes.has(id) and Collection.on_show(plot, spot) == cid, "wheeled into the courtyard and let go: back on show")
	Progress.profile = saved
	Shed.stop()


## Offers between players: the money's held till the owner answers; declined it goes back,
## accepted it goes to the owner and the bike to the buyer's collection.
func test_offers() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var me := Shed.me()
	var who := Collection.name_of(me)
	Shed._add_crew(FRIEND, "Pal")
	Collection.arrived(FRIEND)
	var pal_plot := Collection.plot_of("Pal")
	check(pal_plot >= 0 and pal_plot != Collection.plot_of(who), "a friend joining gets a house of their own (plot %d)" % pal_plot)
	# Pal's bike: bought into their collection by the host.
	var b: int = _for_sale()[0] if not _for_sale().is_empty() else _new_bike()
	var price := Collection.buy_price(b)
	Shed._apply(FRIEND, {"a": "home_buy", "bike": b, "paid": price})
	check(Collection.count_of("Pal") == 1, "Pal buys a bike for their collection")
	var cid: int = Collection.bikes_of("Pal")[0]
	check(Collection.check(me, {"a": "home_offer", "bike": cid, "amount": 0, "paid": 0}) != "", "an offer of nothing isn't one")
	Progress.set_money(100)
	check(Collection.make_offer(cid, 5000).contains("only have") and Progress.money() == 100, "you can't offer money you haven't got")
	Progress.set_money(20000)
	check(Collection.make_offer(cid, 6000) == "" and Progress.money() == 14000, "an offer: the money's taken and held")
	var o := Collection.offer_from(who, cid)
	check(not o.is_empty() and str(o["to"]) == "Pal" and int(o["amount"]) == 6000 and Collection.offers_to("Pal").size() == 1, "it's waiting for Pal")
	check(Collection.make_offer(cid, 100) != "" and Progress.money() == 14000, "one offer on a bike at a time")
	check(Shed.check(me, {"a": "home_answer", "offer": int(o["id"]), "yes": true}).contains("isn't for you"), "only the owner can answer it")
	# Taken back.
	Shed.request({"a": "home_withdraw", "offer": int(o["id"])})
	check(Collection.offers().is_empty() and Progress.money() == 20000, "taken back: the money's yours again")
	# Declined.
	Collection.make_offer(cid, 7000)
	o = Collection.offer_from(who, cid)
	Shed._apply(FRIEND, {"a": "home_answer", "offer": int(o["id"]), "yes": false})
	check(Collection.offers().is_empty() and Progress.money() == 20000 and str(Collection.entry(cid)["owner"]) == "Pal", "declined: the money comes back, the bike stays Pal's")
	# Accepted: Pal (not online here) is owed the money; the bike's yours.
	Collection.make_offer(cid, 8000)
	o = Collection.offer_from(who, cid)
	Shed._apply(FRIEND, {"a": "home_answer", "offer": int(o["id"]), "yes": true})
	var e := Collection.entry(cid)
	check(str(e["owner"]) == who and int(e["paid"]) == 8000 and Progress.money() == 12000 and Collection.count_of("Pal") == 0 and Collection.count_of(who) == 1,
		"accepted: the bike's yours, on show at your house")
	check(int(Shed.homes["owed"].get("Pal", 0)) == 8000, "and the money's Pal's (held for them while they're not connected)")
	check(Collection.on_show(Collection.plot_of(who), int(e["spot"])) == cid and Collection.on_show(pal_plot, 0) == 0, "it moved from Pal's ring to yours")
	# The other way round: you're the owner, Pal offers; you accept and the money's yours.
	Progress.profile["xp"] = Progress.xp_for_level(10)
	Shed.homes["offers"][900] = {"id": 900, "bike": cid, "from": "Pal", "to": who, "amount": 9500, "level": 5}
	check(Shed.check(me, {"a": "home_answer", "offer": 900, "yes": true}) == "", "an offer for your bike: you can accept it")
	Shed.request({"a": "home_answer", "offer": 900, "yes": true})
	check(Progress.money() == 21500 and str(Collection.entry(cid)["owner"]) == "Pal", "accepted: %s into your own money and the bike's Pal's" % Collection.money(9500))
	Progress.profile = saved
	Shed.stop()


## Selling a bike back to the business: about 70% of what it's worth, from the business's money
## into your own, and the bike becomes the shed's to sell on.
func test_sell() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var me := Shed.me()
	var who := Collection.name_of(me)
	var cid := _buy_one()
	var e := Collection.entry(cid)
	var price := Collection.sell_price(cid)
	check(price == roundi(int(e["value"]) * 0.7) and price < int(e["paid"]), "selling back fetches 70%% of what it's worth (%s of %s), less than you paid" % [
		Collection.money(price), Collection.money(int(e["value"]))])
	Shed._add_crew(FRIEND, "Pal")
	check(Shed.check(FRIEND, {"a": "home_sell", "bike": cid}).contains("only they"), "only its owner can sell it")
	Shed.homes["offers"][901] = {"id": 901, "bike": cid, "from": "Pal", "to": who, "amount": 300, "level": 1}
	var garage := Shed.garage_money
	var money := Progress.money()
	var before := Shed.bikes.keys()
	Shed.request({"a": "home_sell", "bike": cid})
	var id := 0
	for b in Shed.bikes:
		if not before.has(b):
			id = int(b)
	check(Progress.money() == money + price and Shed.garage_money == garage - price, "paid from the business's money into yours")
	check(Collection.entry(cid).is_empty() and id != 0 and not Collection.is_private(id) and not Sales.is_customer_bike(id) and int(Shed.bikes[id].get("bought", 0)) == price,
		"the bike's the shed's now, at the shed, bought for what was paid")
	check(Shed.is_complete(id) and (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(Workshop.CENTER) < 40.0, "whole, and at the shed")
	check(Collection.offers().is_empty() and int(Shed.homes["owed"].get("Pal", 0)) == 300, "an offer on it is called off, the money back to whoever made it")
	# The business can't pay what it hasn't got.
	cid = _buy_one()
	Shed.garage_money = 0
	check(Shed.check(me, {"a": "home_sell", "bike": cid}).contains("can't afford"), "the business can't buy it back with no money")
	Progress.profile = saved
	Shed.stop()


## The stand's card: power, torque, top speed, 0-60, weight, economy, condition and value, with
## the parts worth a look and whose it is.
func test_stats() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var cid := _buy_one()
	var text := Collection.stats_text(cid)
	var lines := ["Power", "Torque", "Top speed", "Weight", "Economy", "Condition", "Value", "Paid", "Engine"]
	var missing := lines.filter(func(l): return not text.contains(l + ": "))
	check(missing.is_empty() and (text.contains("0-60 mph: ") or text.contains("0-100 km/h: ")), "the card has every number %s" % str(missing))
	check(text.contains("bhp") and text.contains("Nm") and text.contains("%") and text.contains("Tester's"), "in its units, and whose it is:\n%s" % text)
	var b := Collection.build_of(cid)
	check(b.zero_to(96.56) > 1.0 and b.zero_to(96.56) < b.zero_to_100() and b.zero_to_100() < 30.0, "0-60 comes before 0-100 (%.1f s, %.1f s)" % [b.zero_to(96.56), b.zero_to_100()])
	check(Collection.highlights(b.parts).size() >= 2 and str(Collection.highlights(b.parts)[0]).begins_with("Engine"), "the parts worth a look start with its engine")
	Progress.profile = saved
	Shed.stop()


## A collection saves with the shed: houses, bikes on show, one out on the road, offers and
## money owed all come back.
func test_save() -> void:
	Shed.start_new("Tester", 41)
	var saved: Dictionary = Progress.profile.duplicate(true)
	var who := Collection.name_of(Shed.me())
	var a := _buy_one()
	var b := _buy_one()
	Shed.request({"a": "home_take", "bike": b})
	var out := int(Collection.entry(b)["out"])
	Shed._add_crew(FRIEND, "Pal")
	Collection.arrived(FRIEND)
	Shed.homes["owed"]["Pal"] = 1234
	Shed.homes["offers"][902] = {"id": 902, "bike": a, "from": "Pal", "to": who, "amount": 500, "level": 1}
	var plots := {"me": Collection.plot_of(who), "pal": Collection.plot_of("Pal")}
	var pack_a: Dictionary = Collection.entry(a)["pack"]
	var snap: Dictionary = str_to_var(var_to_str(Shed.save_snapshot()))
	Shed.stop()
	check(Collection.bikes().is_empty(), "closed, nothing's left")
	Shed.load_state(snap, "Tester")
	check(Collection.plot_of(who) == plots["me"] and Collection.plot_of("Pal") == plots["pal"], "the houses stay where they were")
	check(Collection.count_of(who) == 2 and Collection.entry(a)["pack"]["bike"]["slots"] == pack_a["bike"]["slots"]
		and Collection.on_show(plots["me"], int(Collection.entry(a)["spot"])) == a, "the bikes on show come back as they were")
	check(int(Collection.entry(b)["out"]) == out and Shed.bikes.has(out) and Collection.owner_of_bike(out) == who, "and the one out on the road is still out, still yours")
	check(int(Shed.homes["owed"].get("Pal", 0)) == 1234 and Collection.offers().has(902), "money owed and offers waiting are kept")
	check(Collection.sanitize(null) == Collection.empty() and Collection.sanitize({"bikes": {5: {"owner": "x"}}})["bikes"].is_empty(), "an older save, or a broken entry, is made safe")
	Progress.profile = saved
	Shed.stop()


## In a session: your house is built on the map, the bikes on show are dressed once you walk up,
## a stand's {interact} opens the bike's card, and an offer for one of yours comes up to answer.
func test_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	await t.get_tree().physics_frame
	var saved: Dictionary = Progress.profile.duplicate(true)
	var who := Collection.name_of(Shed.me())
	var plot := Collection.plot_of(who)
	# Bought from the bike's card (BikeOrderPanel, {order_bike} at a shed bike).
	var b: int = _for_sale()[0]
	var price := Collection.buy_price(b)
	Progress.set_money(price + 10)
	var order: BikeOrderPanel = main.bike_order_panel
	order.open_bike({"bike": b}, str(Shed.bikes[b]["name"]))
	await _frames(1)
	check(order._buy.visible and not order._buy.disabled and order._buy.text == "Buy it for my collection (%s)" % Collection.money(price),
		"a shed bike's card offers it for your collection, at its price (%s)" % order._buy.text)
	order.press("Buy it for my collection")
	await _frames(1)
	check(not order.visible and not Shed.bikes.has(b) and Progress.money() == 10 and Collection.count_of(who) == 1, "bought from your own money")
	var cid: int = Collection.bikes_of(who)[0]
	await _frames(30)
	var homes: HomesView = main.world.homes
	var disp := homes.display(plot)
	check(disp != null and homes.houses[plot]["node"].get_node_or_null("Walls") != null and homes.houses[plot]["node"].get_node_or_null("Gravel") != null,
		"your house is on the map, with its courtyard")
	check(disp != null and disp.shown.size() == 1 and disp._targets.size() == 1 and disp._boxes != null, "your bike on show in its ring, with its stand")
	var w: Walker = main.walker
	var spot := int(Collection.entry(cid)["spot"])
	var sxf := HomePlots.stand_xf(plot, spot)
	# Stand in the middle of the ring, looking at the stand.
	var mid := HomePlots.frame(plot).origin
	var stand_at := sxf.origin + (mid - sxf.origin).normalized() * 1.1
	w.place(Transform3D(Basis(Vector3.UP, atan2(-(sxf.origin - stand_at).x, -(sxf.origin - stand_at).z)), stand_at + Vector3.UP * 0.1))
	w._look(0.0, -0.6)
	await _frames(8)
	for i in 40:
		if disp.models.size() == 1:
			break
		await _frames(2)
	check(disp.models.size() == 1 and disp.models[spot].get_child(0).get_child(0) is BikeModel, "walked up to it, the bike is drawn as itself")
	check(Sfx.ground_at(stand_at) == "gravel" and Sfx.step_surface(stand_at) in ["gravel", "puddle"], "pea shingle underfoot")
	check(str(w.target.get("use", {}).get("what", "")) == "home_stand" and w.info.contains(str(Collection.entry(cid)["name"])),
		"the crosshair finds its stand (%s)" % w.info.replace("\n", " / "))
	var t_use: Dictionary = {"use": {"what": "home_stand", "plot": plot, "spot": spot}}
	check(disp.use_text(t_use).contains(str(Collection.entry(cid)["name"])) and disp.use_text(t_use).contains("ride it out"), "the stand says what's on it")
	disp.use(t_use)
	await _frames(2)
	var panel: HomePanel = main.home_panel
	var text := panel.text()
	check(panel.visible and text.contains("YOUR") and text.contains("Power") and text.contains("[Ride it out]") and text.contains("Sell it to the garage"),
		"{interact} at the stand: the bike's card, its numbers, ride it out or sell it")
	panel.press("Ride it out")
	await _frames(2)
	var id := int(Collection.entry(cid)["out"])
	check(not panel.visible and id != 0 and main.workshop.bike_views.has(id), "Ride it out: it's in front of the garages, ready to ride")
	Shed.request({"a": "grab_bike", "bike": id})
	Shed.request({"a": "release_bike", "bike": id, "xf": HomePlots.ring_xf(plot, spot)})
	await _frames(20)
	check(disp.shown.has(spot), "parked back in the courtyard, it's back on show")
	# A friend's bike: their card offers to buy it, not to ride it.
	Shed._add_crew(FRIEND, "Pal")
	Collection.entry(cid)["owner"] = "Pal"
	Progress.set_money(50000)
	panel.open_bike(cid)
	panel.set_amount(2500)
	await _frames(1)
	text = panel.text()
	check(panel.visible and text.contains("PAL'S") and text.contains("[Offer £2,500]") and not text.contains("[Ride it out]") and not text.contains("Sell it"),
		"a friend's bike: make them an offer, no riding it out (%s)" % text.replace("\n", " / "))
	panel.press("Offer")
	await _frames(1)
	check(not panel.visible and Progress.money() == 47500 and not Collection.offer_from(who, cid).is_empty(), "Offer: the money's held and Pal has the offer")
	Shed.request({"a": "home_withdraw", "offer": int(Collection.offer_from(who, cid)["id"])})
	Collection.entry(cid)["owner"] = who
	Shed.crew.erase(FRIEND)
	# A friend's offer for it comes up to answer.
	Shed.homes["offers"][903] = {"id": 903, "bike": cid, "from": "Pal", "to": who, "amount": 4321, "level": 1}
	Shed.homes_touched()
	await _frames(80)
	var offer: HomeOfferPanel = main.home_offer
	check(offer.visible and offer._body.text.contains("Pal offers you") and offer._yes.text.contains(Collection.money(4321)), "an offer for your bike comes up: %s" % offer._body.text)
	offer.answer(false)
	await _frames(2)
	check(not offer.visible and Collection.offers().is_empty(), "declined, it's gone")
	var hud: HUD = main.hud
	check(hud.home_marker().is_empty(), "at your house, the HUD's marker for it is hidden")
	# Back at the shed, facing away from the house: the marker says how far, and points behind.
	var home := HomePlots.to_map(plot, Vector2.ZERO)
	var spawn := Workshop.walker_spawn(0)
	var away := Vector2(spawn.origin.x - home.x, spawn.origin.z - home.y)
	w.place(Transform3D(Basis(Vector3.UP, atan2(-away.x, -away.y)), spawn.origin))
	w._look(0.0, 0.0)
	await _frames(3)
	var m := hud.home_marker()
	check(not m.is_empty() and absf(float(m["d"]) - away.length()) < 1.0 and absf(absf(float(m["angle"])) - PI) < 0.3,
		"from the shed, the HUD says how far your house is and points the way (%s)" % str(m))
	Progress.profile = saved
	main.queue_free()
	await _frames(2)
	Shed.stop()
