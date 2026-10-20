extends RefCounted
## The staff's trips for parts (v0.18.0), run from tests/run_tests.gd (its _test_staff_trips_*
## functions hand over to these). Simon: "Sometimes an AI Expert mechanic walks through a wall and
## just heads off to pick up a part a long way away", and "Expert mechanic AI should use the big
## trolley to load all of the purchases on to it".

var t: Node   # the test runner: check(), _bike_named(), _staff_role()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A shed with the storage annex and its racking built, and a flatbed trolley of the garage's own
## standing in the shed.
func _big_shed() -> int:
	Shed.start_new("T", 5)
	Shed.upgrades["annex"] = true
	Shed.upgrades["racking"] = true
	for xf in GarageUpgrades.racking_xfs():
		Shed._new_furniture("shelf", xf, "shelf_racking")
	return Shed._new_furniture("trolley", Transform3D(Basis(), Vector3(2.6, 0.0, 67.4)), "trolley_flatbed")


## A new spare `part` put on spot `spot` (a shelf's, a trolley's) or on the floor at `at`.
func _spare(part: String, spot := "", at := Vector3.ZERO, boxed := false) -> int:
	var id := Shed._new_item(part, 0.0, 0.0, 0.0)
	Shed.items[id]["boxed"] = boxed
	if spot != "":
		Shed._move(id, "spot", spot)
	else:
		Shed._move(id, "floor", Transform3D(Basis(), at))
	return id


## The segments of walk `pts` that aren't one of the walkways' own (corner to joined corner) and
## go from one room into another: through a wall.
func _through_walls(pts: PackedVector3Array) -> Array:
	var rooms := StaffNav._walls()
	var out := []
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var na := ""
		var nb := ""
		for n in StaffNav.NODES:
			var p := Vector3(StaffNav.NODES[n].x, 0.0, StaffNav.NODES[n].y)
			if p.distance_to(a) < 0.06:
				na = n
			if p.distance_to(b) < 0.06:
				nb = n
		if na != "" and nb != "" and (StaffNav._graph()[na] as Array).has(nb):
			continue
		var r0 := StaffNav._room(a, rooms)
		var steps := int(a.distance_to(b) / 0.1) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			if StaffNav._room(p, rooms) != r0 and not (r0 == "" and StaffNav._room(p, rooms) == "wash"):
				out.append("%s to %s into %s" % [str(Vector2(a.x, a.z)), str(Vector2(b.x, b.z)), StaffNav._room(p, rooms)])
				break
	return out


## Where a part on a shelf or a trolley is (its place on it, out in the world), and the walk to
## fetch it: from the shed, the parts computer and the deliveries, never through a wall (the
## annex is reached by its door from the storage room, its racking from in front), stood beside
## the part in the same room.
func test_walls() -> void:
	var flat := _big_shed()
	var rack := Shed.staff_rack()
	var on_rack := _spare("spark_plugs", Shed._free_surface_spot("f%ds1" % rack))
	Shed.items[on_rack]["place"] = Transform3D(Basis(), Vector3(0.3, 0.0, 0.0))
	var at := StaffJobs.item_at(on_rack)
	check(at.distance_to(Shed.STAFF_RACK_XF.origin) < 1.5 and Workshop.room_at(at) == "storage",
		"a part put on the staff rack is at the rack in the storage room (%s), not where its place on the board says (%s)" % [str(at), str(Shed.item_place(on_rack).origin)])
	var spares := [on_rack]
	for id in Shed.furniture:
		var f: Dictionary = Shed.furniture[id]
		if not str(f["kind"]) in ["shelf", "trolley"] or f["model"] == Shed.DELIVERY_RACK:
			continue
		for spot in Shed.furniture_spots(int(id)):
			if Shed.item_at_spot(str(spot)) == 0:
				spares.append(_spare("foam_filter", str(spot)))
	var rooms_seen := {}
	var bad := []
	var far := []
	for id in spares:
		var p := StaffJobs.item_at(int(id))
		var room := Workshop.room_at(Vector3(p.x, 0.0, p.z))
		rooms_seen[room] = true
		var to := StaffNav.at_item(int(id))
		var stand := StaffNav.spot(to)
		if Vector2(stand.x, stand.z).distance_to(Vector2(p.x, p.z)) > 1.3 or Workshop.room_at(stand) != room:
			far.append("%s in %s fetched from %s" % [str(Vector2(p.x, p.z)), room, str(Vector2(stand.x, stand.z))])
		for from in [StaffNav.idle("expert"), StaffNav.computer(), StaffNav.cart_delivery()]:
			bad.append_array(_through_walls(StaffNav.route(from, to, StaffNav.spot(from))))
	check(rooms_seen.has("annex") and rooms_seen.has("storage") and rooms_seen.has("shed"),
		"parts on the annex racking, the staff rack and the trolleys (%d places, in %s)" % [spares.size(), str(rooms_seen.keys())])
	check(far.is_empty(), "each is fetched from beside it, in its own room (%d not: %s)" % [far.size(), str(far.slice(0, 3))])
	check(bad.is_empty(), "and every walk there keeps to the doors (%d through a wall: %s)" % [bad.size(), str(bad.slice(0, 3))])
	var path := StaffNav.node_path("shed", "annex")
	check(path.has("store") and path.has("annex_door"), "into the annex through the storage room (%s)" % str(path))
	check(Shed.furniture.has(flat), "the flatbed's there")
	# Without the annex built, nobody heads for it.
	Shed.upgrades.erase("annex")
	var behind := Vector3(-10.9, 0.0, 50.0)
	check(not StaffNav.nearest_node(behind).begins_with("annex") and not StaffNav.node_path("shed", "yard_w").has("annex"),
		"no annex, no walking into it (%s)" % StaffNav.nearest_node(behind))
	check(StaffNav.nearest_node(Vector3(-9.0, 0.0, 58.0)) == "store" and StaffNav.nearest_node(Vector3(0.0, 0.0, 56.0)) == "dyno",
		"the corner they set off from is in the room they're in")
	Shed.stop()


## Which spare they go for: the nearest by the walk there (a box a little further, for the
## unpacking), only ones they can get to; never one out on the roads, upstairs or on a mezzanine.
func test_nearest_stock() -> void:
	_big_shed()
	Staff.hire_one_of_each()
	var ex: int = t._staff_role("expert")
	var w := Staff.worker(ex)
	var job := StaffJobs.new_job(w, {"kind": "service", "bike": t._bike_named("Rusty Ranger")})
	w["job"] = job
	var annex_rack := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["model"] == "shelf_racking":
			annex_rack = int(id)
	var far_one := _spare("knobbly_mx_90", Shed.furniture_spots(annex_rack)[0])
	var road := _spare("knobbly_mx_90", "", Vector3(0.0, 0.0, 6.0))
	var upstairs := _spare("knobbly_mx_90", "", Vector3(-8.0, GarageUpgrades.MEZZ_TOP, 42.0))
	var box := Shed.deliver_new("knobbly_mx_90")
	var walk := func(id: int) -> float:
		return StaffNav.length(StaffNav.route(w["at"], StaffNav.at_item(id), w["pos"]))
	print("    walks: to the delivery box %.1f m, to the annex racking %.1f m" % [walk.call(box), walk.call(far_one)])
	check(box != 0 and StaffJobs.find_stock("knobbly_mx_90", job) == box,
		"a boxed one in the delivery area beats an unboxed one at the far end of the annex (%.0f m against %.0f m)" % [walk.call(box), walk.call(far_one)])
	Shed._erase_item(box)
	check(StaffJobs.find_stock("knobbly_mx_90", job) == far_one, "with that gone, the annex one: a long walk, but on the walkways")
	Shed._erase_item(far_one)
	check(StaffJobs.find_stock("knobbly_mx_90", job) == 0 and not StaffNav.reachable(StaffJobs.item_at(road))
		and not StaffNav.reachable(StaffJobs.item_at(upstairs)), "one out on the road or up on the mezzanine isn't one they'll go for")
	# A plain mechanic's service from what's on the staff rack (nothing bought): every step of every
	# walk on the walkways, through the doors.
	Shed._erase_item(road)
	Shed._erase_item(upstairs)
	w["job"] = {}
	var id: int = t._staff_role("mechanic")
	var mech := Staff.worker(id)
	var ranger: int = t._bike_named("Rusty Ranger")
	var rack := Shed.staff_rack()
	for part in ["sintered", "sintered", "copper_plugs", "foam_filter", "paper_oil"]:
		var s := _spare(part, "", Vector3.ZERO)
		StaffJobs.put_on_rack(mech, s)
	Shed.request({"a": "staff_assign", "worker": id, "job": {"kind": "service", "bike": ranger}})
	var rooms := StaffNav._walls()
	var prev := Staff.pos_at(mech, Staff.clock())
	var wall := []
	var off := []
	var at_rack := false
	for i in 9000:
		Staff.process(Staff.TICK)
		if (mech["job"] as Dictionary).is_empty() and i > 4:
			break
		var p := Staff.pos_at(mech, Staff.clock())
		at_rack = at_rack or p.distance_to(StaffNav.spot(StaffNav.rack())) < 0.5
		if not Shed.WORK_AREA.has_point(Vector2(p.x, p.z)):
			off.append(str(Vector2(p.x, p.z)))
		if StaffNav._room(p, rooms) != StaffNav._room(prev, rooms):
			var by_door := false
			for n in StaffNav.NODES:
				by_door = by_door or (StaffNav.NODES[n] as Vector2).distance_to(Vector2(p.x, p.z)) < 1.6
			if not by_door:
				wall.append(str(Vector2(p.x, p.z)))
		prev = p
	print("    " + Staff.saying(mech))
	check((mech["job"] as Dictionary).is_empty() and Staff.saying(mech).contains("serviced") and at_rack,
		"the service gets done with the parts from the staff rack (%s)" % Staff.saying(mech))
	check(off.is_empty() and wall.is_empty(), "never off round the garage (%d: %s) nor through a wall (%d: %s)" % [off.size(), str(off.slice(0, 3)),
		wall.size(), str(wall.slice(0, 3))])
	Shed.stop()


## An expert's order for a job on the biggest trolley there is: a flatbed of the garage's own
## taken out to the deliveries, every box of the order loaded onto it, wheeled over to the bike in
## one go (nothing fetched by hand from out there), and back where it was after.
func test_flatbed_kit() -> void:
	var flat := _big_shed()
	var flat_at: Vector3 = (Shed.furniture[flat]["xf"] as Transform3D).origin
	var staff_cart := Shed.staff_trolley()
	var staff_at: Vector3 = (Shed.furniture[staff_cart]["xf"] as Transform3D).origin
	Staff.hire_one_of_each()
	var ex: int = t._staff_role("expert")
	var w := Staff.worker(ex)
	var ranger: int = t._bike_named("Rusty Ranger")
	Shed.request({"a": "staff_assign", "worker": ex, "job": {"kind": "service", "bike": ranger}})
	var deck := "f%d" % flat
	var kit_size := 0
	var most := 0
	var left_out := -1
	var by_hand := 0
	var carried := 0
	var cart_used := 0
	for i in 16000:
		Staff.process(Staff.TICK)
		var job: Dictionary = w["job"]
		if job.is_empty() and i > 4:
			break
		var kit: Array = job.get("kit", [])
		kit_size = maxi(kit_size, kit.size())
		cart_used = int(job.get("cart", cart_used))
		most = maxi(most, Shed.surface_items(deck).size())
		var c: Vector3 = (Shed.furniture[flat]["xf"] as Transform3D).origin
		if left_out < 0 and str(job.get("kit_stage", "")) == "done" and c.distance_to(StaffNav.spot(StaffNav.cart_by_bike(ranger))) < 1.0:
			# Got to the bike: what of the order's still out at the deliveries?
			left_out = kit.filter(func(id): return Shed.items.has(int(id)) and Shed.DELIVERY_AREA.grow(1.0).has_point(Vector2(StaffJobs.item_at(int(id)).x, StaffJobs.item_at(int(id)).z))).size()
		# Carrying one of the order further than the trolley's reach: a trip by hand.
		var held := Shed.held_by(Staff.peer_of(ex))
		if held != carried:
			carried = held
			if held != 0 and kit.has(held):
				var p := Staff.pos_at(w, Staff.clock())
				if Shed.DELIVERY_AREA.grow(1.5).has_point(Vector2(p.x, p.z)) and str(job.get("kit_stage", "")) == "done":
					by_hand += 1
	print("    %d parts ordered, %d on the flatbed at once, %d left at the deliveries, %d fetched by hand: %s" % [kit_size, most, left_out, by_hand, Staff.saying(w)])
	check((w["job"] as Dictionary).is_empty() and Staff.saying(w).contains("serviced"), "the expert gets the service done (%s)" % Staff.saying(w))
	check(cart_used == flat, "on the flatbed, the biggest trolley in the garage, not the staff's little one")
	check(kit_size >= 8 and most == kit_size and left_out == 0 and by_hand == 0,
		"every box of the order on it at once (%d of %d) and over to the bike in one trip, none left out there (%d) or fetched by hand (%d)" % [most, kit_size, left_out, by_hand])
	check((Shed.furniture[flat]["xf"] as Transform3D).origin.distance_to(flat_at) < 0.7 and int(Shed.furniture[flat]["mover"]) == 0
		and Shed.surface_items(deck).is_empty(), "then the flatbed's unloaded and wheeled back where it was")
	check((Shed.furniture[staff_cart]["xf"] as Transform3D).origin.distance_to(staff_at) < 0.1, "and the staff trolley wasn't touched")
	# Someone else's things on it: not theirs to take.
	var mine := _spare("spark_plugs", Shed._free_surface_spot(deck))
	var job2 := {"kit": []}
	check(StaffJobs.kit_cart(w, job2) == staff_cart, "with a crew mate's part on the flatbed, they take the staff trolley")
	Shed._erase_item(mine)
	Shed.stop()
