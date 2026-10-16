class_name CoffeeShop
extends RefCounted
## The coffee shop next door: the Pit Stop Cafe, a small single-storey cafe on the yard west of
## the shed (past the storage room), with a counter and a kitchen hatch, tables inside, a terrace
## of tables under umbrellas in front, and a marked car park for twenty bikes in front of that.
## It's open from OPEN_HOUR to CLOSE_HOUR game time: its sign lights up, and the rest of the day
## a CLOSED sign hangs in the door and the lights are off.
##   visitors  bikers ride in during the day, on their own or in groups of two to five, on bikes
##             of every style. They park, sit down inside or out on the terrace with a coffee,
##             chat, and ride off again after a while; when it shuts they drink up and go. Some
##             wander over to the sales office to look at the bikes on show, and now and then one
##             of them makes an offer on one (like an online buyer, on the Sales page).
##             Look at a parked bike for its basics (style, engine, power, condition, roughly
##             what it's worth). Talk to its owner (F, on them or their bike) to make an offer:
##             they hardly ever sell (a bit more often the more you overpay, never often), and a
##             yes buys it into the yard as the shed's, paid from the business's account, parked
##             where it stands. They walk off to get a lift home.
##   counter   coffee, tea, cake and sandwiches, paid from your own money and served on a tray
##             you carry (it's in your hands: put it down on anything flat, the workbench in the
##             shed included, and pick it up again). Eat or drink from it with the second work
##             button for a little XP. Put an empty tray back on the counter and it's cleared away.
##
## All of it is host-authoritative shed state in Shed.coffee (saved with the shed). Players ask
## for changes with Shed.request({"a": "coffee_..."}), which Shed hands to check()/apply().
## Everything here is static, working on the Shed autoload, like Contracts and Sales.

## The building (CoffeeShopBuilding): the middle of its floor and its inside half size. Its
## front, with the door in the middle, faces +z onto the terrace and the yard.
const CENTER := Vector3(-25.25, 0.0, 59.25)
const HALF := Vector2(5.75, 3.75)          # interior: x -31.0..-19.5, z 55.5..63.0
const WALL := 0.25
const CEIL_Y := 3.0
const DOOR_HALF := 0.8
const DOOR_HEIGHT := 2.3
## The terrace in front of it and the car park in front of that, as x/z rectangles.
const TERRACE := Rect2(-31.25, 63.25, 12.0, 7.0)     # z 63.25..70.25
const CAR_PARK := Rect2(-31.8, 70.6, 14.6, 8.2)      # x -31.8..-17.2, z 70.6..78.8
## The walkway up the middle of the terrace to the door, and the aisle between the two rows of
## parking bays.
const WALK_X := -25.25
const AISLE_Z := 74.7
## The parking bays: a row along the terrace (nose to the cafe, -Z) with a gap for the walkway,
## and a longer row behind it (nose out to the yard, +Z). Twenty in all.
const ROW_A_Z := 72.0
const ROW_A_X := [-30.85, -29.5, -28.15, -26.8, -23.7, -22.35, -21.0, -19.65, -18.3]
const ROW_B_Z := 77.4
const ROW_B_X0 := -31.0
const ROW_B_STEP := 1.3
const PARK_SLOTS := 20
## The tables: where each one stands (x/z, its long side along x), and whether it's out on the
## terrace. Each has four chairs, two either side of it along z (see seat_xf).
const TABLES := [
	[Vector2(-29.85, 57.4), false], [Vector2(-27.25, 57.4), false], [Vector2(-29.85, 60.9), false], [Vector2(-27.25, 60.9), false],
	[Vector2(-29.85, 65.0), true], [Vector2(-27.25, 65.0), true], [Vector2(-23.25, 65.0), true], [Vector2(-20.65, 65.0), true],
	[Vector2(-29.85, 68.2), true], [Vector2(-27.25, 68.2), true], [Vector2(-23.25, 68.2), true], [Vector2(-20.65, 68.2), true],
]
const TABLE_SIZE := Vector3(1.4, 0.75, 0.8)
const CHAIR_X := 0.4
const CHAIR_Z := 0.65
## How far either side of a table's middle the way to its chairs runs (clear of the chairs).
const LANE := 1.25
## The counter (the middle of its foot and its size), where you stand to order, the barista
## behind it facing you, and the wall with the kitchen hatch behind them.
const COUNTER := Vector3(-22.2, 0.0, 58.62)
const COUNTER_SIZE := Vector3(4.4, 1.05, 0.65)
const ORDER_SPOT := Vector3(-22.2, 0.0, 59.6)
const BARISTA := Transform3D(Basis(Vector3.UP, PI), Vector3(-22.6, 0.0, 57.98))
const KITCHEN_Z := 57.0
const KITCHEN_X := -24.6
## The way in from the road: from the west along the loop where it passes the yard, then up
## the yard's west side (clear of the slalom, the jumps, the drop-off box and the speed humps)
## to the car park's east end.
const ROAD_IN := [Vector3(-72.0, 0.0, 134.6), Vector3(-45.0, 0.0, 133.5), Vector3(-27.0, 0.0, 134.1),
	Vector3(-27.0, 0.0, 95.0), Vector3(-16.5, 0.0, 84.0), Vector3(-16.5, 0.0, AISLE_Z)]
## The walk over to the sales office: along the front of the yard past the shed, clear of the
## retrieved bikes, the delivery area and the customer car park, to its front doors.
const TO_SALES := [Vector3(-16.5, 0.0, AISLE_Z), Vector3(-14.0, 0.0, 78.6), Vector3(14.0, 0.0, 78.6), Vector3(24.5, 0.0, 78.2)]

## What the counter sells: its name, its price (your own money), and what you do with it.
const MENU := {
	"coffee": {"name": "Coffee", "price": 3, "verb": "drink"},
	"tea": {"name": "Tea", "price": 2, "verb": "drink"},
	"cake": {"name": "Cake", "price": 3, "verb": "eat"},
	"sandwich": {"name": "Sandwich", "price": 5, "verb": "eat"},
}
const MENU_ORDER: Array[String] = ["coffee", "tea", "cake", "sandwich"]
const TRAY_MAX := 4
const MAX_TRAYS := 12
const XP_KEY := "coffee_break"
const BUY_XP_KEY := "cafe_bike"
## What having it says.
const TASTES := {"coffee": ["Proper coffee. That's the stuff.", "Strong enough to stand a spoon in.", "A flat white. Lovely."],
	"tea": ["Builder's tea, two sugars.", "A nice cuppa.", "Tea. Everything's better now."],
	"cake": ["Victoria sponge. Not bad at all.", "Carrot cake, still warm.", "Lemon drizzle. One more wouldn't hurt."],
	"sandwich": ["Bacon butty. Perfect.", "Cheese and pickle, doorstep cut.", "A sausage sandwich with brown sauce."]}

## Opening hours, game time.
const OPEN_HOUR := 8.0
const CLOSE_HOUR := 18.0
## Game hours before the first bikers come (after a new shed or opening time), between groups,
## and how long a group stays.
const FIRST_VISIT := 0.3
const SPAWN_HOURS := Vector2(0.4, 1.2)
const STAY_HOURS := Vector2(0.8, 2.0)
## How many come on their own; the rest come in groups of two to five.
const SOLO_CHANCE := 0.45
const GROUP_MAX := 5
## A visitor's chance of wandering over to look at the bikes on show (when there are any), and
## then of making an offer on one that's for sale.
const BROWSE_CHANCE := 0.3
const BUYER_CHANCE := 0.15
## Game hours a visitor's record is kept once they're leaving (for players arriving to see it),
## and how soon the ones still in leave once it shuts.
const LEAVING_HOURS := 0.5
const CLOSING_HOURS := 0.25
## Making an offer on a visitor's bike: the chance it's taken at what the bike is worth, how much
## more for each 100% over it, the most it ever is, and the share of its worth below which
## they just laugh. Each visitor hears out MAX_OFFERS offers at most.
const ACCEPT_BASE := 0.04
const ACCEPT_PER_OVER := 0.3
const ACCEPT_MAX := 0.35
const ACCEPT_FLOOR := 0.9
const MAX_OFFERS := 3
const MAX_OFFER := 1000000
## Figures' ids (CustomerView), clear of contract customers' and sales visitors'.
const ID_BASE := 800000
const BARISTA_ID := 799999
## Actions that need your hands, which you can't do with a tray in them.
const HANDS_NEEDED: Array[String] = ["unbolt", "bolt", "remove", "install", "take", "place", "set_down", "tyre_fit",
	"tyre_remove", "unpack", "grab", "scrap", "bin", "tip", "clean_many", "repair_many", "adjust_chain", "lube", "clean",
	"repair", "paint", "pour", "drain", "wash", "grab_bike", "mount", "start_build", "lighten", "coat", "blast_use"]
const CHAT := ["Lovely day for a ride.", "Just done the Moor Pass. Those hairpins!", "Best bacon butty for miles, this.",
	"Thinking of a new exhaust. Any good?", "We do a loop out to Ashby and back most Sundays.",
	"Nearly lost the back end on the Ridge run. Still grinning.", "She's been running a bit rich lately.",
	"You lot from the shed next door? Nice work.", "Forecast says rain later. We'll see.",
	"Had this one since new. Wouldn't part with it.", "Got caught behind a tractor all the way from Kettle Bridge.",
	"Coffee here's better than the services, that's for sure."]
## Test hook: when 0..1 it stands in for the dice when an offer is weighed (-1: roll them).
static var test_roll := -1.0


# ---------------------------------------------------------------------------- state

## A new shed's coffee shop: nobody in yet, no trays out.
static func empty() -> Dictionary:
	return {"clock": 0.0, "next_at": FIRST_VISIT, "open": true, "visitors": {}, "trays": {}, "next": 1, "next_group": 1,
		"served": 0, "bought": 0}


## Saved or synced coffee shop made safe to use: anything missing (sheds from before the cafe)
## gets its default.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
		elif s.has(key) and key in ["clock", "next_at"] and (s[key] is int or s[key] is float):
			out[key] = float(s[key])
	return out


static func _st() -> Dictionary:
	if not (Shed.coffee is Dictionary) or not Shed.coffee.has("visitors"):
		Shed.coffee = empty()
	return Shed.coffee


static func clock() -> float:
	return float(_st()["clock"])


static func visitors() -> Dictionary:
	return _st()["visitors"]


static func trays() -> Dictionary:
	return _st()["trays"]


static func is_open() -> bool:
	return bool(_st()["open"])


## Whether the cafe is open at `h` hours.
static func open_at(h: float) -> bool:
	return h >= OPEN_HOUR and h < CLOSE_HOUR


static func money(v: int) -> String:
	return TvChannels.money_text(v)


static func price(item: String) -> int:
	return int(MENU.get(item, {}).get("price", 0))


static func item_name(item: String) -> String:
	return str(MENU.get(item, {}).get("name", item))


## "Open till 18:00" or "Closed, opens at 08:00".
static func hours_text() -> String:
	if is_open():
		return "Open till %s" % Daylight.clock_text(CLOSE_HOUR)
	return "Closed, opens at %s" % Daylight.clock_text(OPEN_HOUR)


# ---------------------------------------------------------------------------- places

## The building's floor as an x/z rectangle (a room: see Workshop.rooms).
static func footprint() -> Rect2:
	return Rect2(CENTER.x - HALF.x, CENTER.z - HALF.y, HALF.x * 2.0, HALF.y * 2.0)


## Parking bay `i`: where a visitor's bike stands, and which way its nose points.
static func park_xf(i: int) -> Transform3D:
	var k := clampi(i, 0, PARK_SLOTS - 1)
	if k < ROW_A_X.size():
		return Transform3D(Basis(), Vector3(float(ROW_A_X[k]), 0.0, ROW_A_Z))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(ROW_B_X0 + ROW_B_STEP * (k - ROW_A_X.size()), 0.0, ROW_B_Z))


## Where the rider stands getting on or off the bike in bay `i`: beside it, on the aisle side.
static func park_side(i: int) -> Vector3:
	var xf := park_xf(i)
	var p := xf.origin + xf.basis.x * 0.65 + xf.basis.z * 0.35
	p.y = 0.0
	return p


static func seat_count() -> int:
	return TABLES.size() * 4


## Chair `s`: where someone sits (on the floor under the chair) facing the table (-Z at it).
## Chairs 0 and 1 of a table are on its north side, 2 and 3 on its south.
static func seat_xf(s: int) -> Transform3D:
	var t: Vector2 = TABLES[clampi(s / 4, 0, TABLES.size() - 1)][0]
	var k := s % 4
	var north := k < 2
	var at := Vector3(t.x + (-CHAIR_X if k % 2 == 0 else CHAIR_X), 0.0, t.y + (-CHAIR_Z if north else CHAIR_Z))
	return Transform3D(Basis(Vector3.UP, PI) if north else Basis(), at)


## Whether chair `s` is out on the terrace.
static func seat_outdoors(s: int) -> bool:
	return bool(TABLES[clampi(s / 4, 0, TABLES.size() - 1)][1])


## The way from the walkway to chair `s`: up the walkway to its side of its table, along it
## and in to the chair.
static func seat_way(s: int) -> PackedVector3Array:
	var t: Vector2 = TABLES[clampi(s / 4, 0, TABLES.size() - 1)][0]
	var lane := t.y + (-LANE if s % 4 < 2 else LANE)
	var seat := seat_xf(s).origin
	return PackedVector3Array([Vector3(WALK_X, 0.0, AISLE_Z), Vector3(WALK_X, 0.0, lane), Vector3(seat.x, 0.0, lane), seat])


## The ride in from the road into bay `park`.
static func ride_in(park: int) -> PackedVector3Array:
	var pts := PackedVector3Array(ROAD_IN)
	var slot := park_xf(park).origin
	pts.append(Vector3(slot.x + 1.5, 0.0, AISLE_Z))
	pts.append(slot)
	return pts


## The ride away: backing out of bay `park` into the aisle, out along it and back to the road.
static func ride_out(park: int) -> PackedVector3Array:
	var slot := park_xf(park).origin
	var pts := PackedVector3Array([slot, Vector3(slot.x, 0.0, AISLE_Z)])
	for i in range(ROAD_IN.size() - 1, -1, -1):
		pts.append(ROAD_IN[i])
	return pts


## From beside the bike in bay `park` to chair `seat`.
static func walk_to_seat(park: int, seat: int) -> PackedVector3Array:
	var side := park_side(park)
	var pts := PackedVector3Array([side, Vector3(side.x, 0.0, AISLE_Z)])
	pts.append_array(seat_way(seat))
	return pts


## From chair `seat` back to the bike in bay `park`.
static func walk_from_seat(seat: int, park: int) -> PackedVector3Array:
	var pts := _reversed(walk_to_seat(park, seat))
	return pts


## Where visitor `v` stands in the showroom: by the bike on their stand, side by side with any
## others looking at it.
static func showroom_xf(stand: int, k := 0) -> Transform3D:
	var xf := SalesView.viewing_xf(maxi(stand, 0))
	return xf.translated_local(Vector3((k % 3 - 1) * 0.55, 0.0, 0.0))


## From chair `seat` over to the sales office, in through its doors and up to the bike on show on
## `stand`.
static func walk_to_showroom(seat: int, stand: int, k := 0) -> PackedVector3Array:
	var pts := _reversed(seat_way(seat))
	pts.append_array(PackedVector3Array(TO_SALES))
	pts.append(SalesView.door_out())
	pts.append(SalesView.door_in())
	pts.append(showroom_xf(stand, k).origin)
	return pts


## From the showroom back out to the bike in bay `park`.
static func walk_showroom_to_bike(stand: int, park: int, k := 0) -> PackedVector3Array:
	var pts := PackedVector3Array([showroom_xf(stand, k).origin, SalesView.door_in(), SalesView.door_out()])
	for i in range(TO_SALES.size() - 1, -1, -1):
		pts.append(TO_SALES[i])
	var side := park_side(park)
	pts.append(Vector3(side.x, 0.0, AISLE_Z))
	pts.append(side)
	return pts


## Their bike sold, a visitor walks off to the road for their lift home: from their chair (or
## the showroom, `stand` >= 0) out past the car park and down the yard.
static func walk_off(seat: int, stand := -1, k := 0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	if stand >= 0:
		pts = PackedVector3Array([showroom_xf(stand, k).origin, SalesView.door_in(), SalesView.door_out()])
		for i in range(TO_SALES.size() - 1, -1, -1):
			pts.append(TO_SALES[i])
	else:
		pts = _reversed(seat_way(seat))
		pts.append(ROAD_IN[ROAD_IN.size() - 1])
	for i in range(ROAD_IN.size() - 2, 1, -1):
		pts.append(ROAD_IN[i])
	return pts


static func _reversed(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(pts.size() - 1, -1, -1):
		out.append(pts[i])
	return out


## Where a tray goes on the counter when the shed puts one back (the `k`th along it).
static func counter_spot(k: int) -> Transform3D:
	return Transform3D(Basis(), COUNTER + Vector3(-1.6 + 0.55 * (k % 6), COUNTER_SIZE.y, 0.02))


## Whether `at` is on the counter top (an empty tray put down there is cleared away).
static func on_counter(at: Vector3) -> bool:
	return absf(at.x - COUNTER.x) < COUNTER_SIZE.x * 0.5 + 0.1 and absf(at.z - COUNTER.z) < COUNTER_SIZE.z * 0.5 + 0.1 \
		and absf(at.y - COUNTER_SIZE.y) < 0.2


# ---------------------------------------------------------------------------- trays

## The tray `peer` is carrying, or {}.
static func tray_of(peer: int) -> Dictionary:
	for id in trays():
		if int(trays()[id].get("holder", 0)) == peer:
			return trays()[id]
	return {}


static func carrying(peer: int) -> bool:
	return not tray_of(peer).is_empty()


## "coffee and cake", for the HUD and messages.
static func items_text(items: Array) -> String:
	if items.is_empty():
		return "nothing (it's empty)"
	var names: Array[String] = []
	for it in items:
		names.append(item_name(str(it)).to_lower())
	if names.size() == 1:
		return names[0]
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]


## What having the next thing on a tray is: "drink the coffee", "eat the cake".
static func eat_verb(tray: Dictionary) -> String:
	var items: Array = tray.get("items", [])
	if items.is_empty():
		return ""
	var it := str(items[0])
	return "%s the %s" % [str(MENU.get(it, {}).get("verb", "have")), item_name(it).to_lower()]


## Host: a new tray in `peer`'s hands. Past MAX_TRAYS the oldest one put down is cleared away.
static func _new_tray(peer: int) -> Dictionary:
	var s := _st()
	var id := int(s["next"])
	s["next"] = id + 1
	var t := {"id": id, "items": [], "holder": peer, "xf": Transform3D()}
	trays()[id] = t
	while trays().size() > MAX_TRAYS:
		var oldest := 0
		for k in trays():
			if int(trays()[k]["holder"]) == 0 and (oldest == 0 or int(k) < oldest):
				oldest = int(k)
		if oldest == 0:
			break
		trays().erase(oldest)
	return t


## Host: whatever `peer` was carrying goes back on the counter (they've left, or a save was opened).
static func put_back(peer: int) -> void:
	var t := tray_of(peer)
	if t.is_empty():
		return
	var n := 0
	for id in trays():
		if int(trays()[id]["holder"]) == 0 and on_counter((trays()[id]["xf"] as Transform3D).origin):
			n += 1
	t["holder"] = 0
	t["xf"] = counter_spot(n)


## Host: after a save is opened, nobody is carrying anything.
static func after_load() -> void:
	var holders := []
	for id in trays():
		var h := int(trays()[id].get("holder", 0))
		if h != 0:
			holders.append(h)
		if not (trays()[id].get("xf") is Transform3D):
			trays()[id]["xf"] = counter_spot(0)
		if not (trays()[id].get("items") is Array):
			trays()[id]["items"] = []
	for h in holders:
		put_back(h)


# ---------------------------------------------------------------------------- visitors

## What a visitor's bike is in a line: style, engine, power, condition and roughly its worth.
static func bike_line(v: Dictionary) -> String:
	var b: Dictionary = v.get("bike", {})
	return "%s  ·  %s  ·  %d hp  ·  %d%% condition  ·  worth about %s" % [str(b.get("style_text", "A bike")), str(b.get("model", "")),
		int(b.get("hp", 0)), roundi(float(b.get("condition", 0.0)) * 100.0), money(rough_value(v))]


## What a visitor's bike is roughly worth, to the nearest hundred.
static func rough_value(v: Dictionary) -> int:
	return maxi(100, roundi(float(v.get("bike", {}).get("value", 0)) / 100.0) * 100)


static func first_name(v: Dictionary) -> String:
	return str(v.get("name", "Someone")).get_slice(" ", 0)


## Whether a visitor can be talked to (still here, with their own bike).
static func here(v: Dictionary) -> bool:
	return str(v.get("state", "")) in ["in", "browse"]


## The chance an offer of `amount` for a bike worth `value` is taken: low, a little higher the
## more it's over, and never more than ACCEPT_MAX.
static func accept_chance(amount: int, value: int) -> float:
	var r := float(amount) / maxf(1.0, float(value))
	if r < ACCEPT_FLOOR:
		return 0.0
	return clampf(ACCEPT_BASE + (r - 1.0) * ACCEPT_PER_OVER, ACCEPT_BASE * 0.25, ACCEPT_MAX)


## Parking bays nobody's using (no visitor's bike and no bike of the shed's stands in them).
static func free_parks() -> Array:
	var taken := {}
	for id in visitors():
		var v: Dictionary = visitors()[id]
		if str(v["state"]) != "sold" or Shed.bikes.has(int(v.get("bike_id", 0))):
			taken[int(v.get("park", -1))] = true
	var out := []
	for i in PARK_SLOTS:
		if taken.has(i):
			continue
		var at := park_xf(i).origin
		var clear := true
		for b in Shed.bikes.values():
			var o: Vector3 = (b["xf"] as Transform3D).origin
			if Vector2(o.x - at.x, o.z - at.z).length() < 1.0:
				clear = false
		if clear:
			out.append(i)
	return out


## `n` free chairs for a group: round one table if it can, else at tables side by side.
static func free_seats(n: int, rng: RandomNumberGenerator) -> Array:
	var taken := {}
	for id in visitors():
		if here(visitors()[id]) or str(visitors()[id]["state"]) == "out":
			taken[int(visitors()[id].get("seat", -1))] = true
	var order := range(TABLES.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out := []
	for t in order:
		var free := []
		for k in 4:
			if not taken.has(int(t) * 4 + k):
				free.append(int(t) * 4 + k)
		if free.size() >= n:
			return free.slice(0, n)
	for t in order:
		for k in 4:
			if out.size() < n and not taken.has(int(t) * 4 + k):
				out.append(int(t) * 4 + k)
	return out if out.size() == n else []


## A biker's bike: of a style (as they come, see Shed.style_parts) or now and then a parts-bin
## mix, ridden a bit, with what the cafe's info line shows worked out once.
static func _make_bike(rng: RandomNumberGenerator) -> Dictionary:
	var style: String = PartsDB.STYLES[rng.randi() % PartsDB.STYLES.size()]
	var parts: Dictionary = Shed.style_parts(style) if rng.randf() < 0.75 else Contracts.random_parts(rng, true)
	if str(parts.get("side_stand", "none")) == "none" and str(parts.get("centre_stand", "none")) == "none":
		parts["side_stand"] = PartsDB.DEFAULT_BUILD["side_stand"]
	parts = PartsDB.sanitize_build(parts)
	var age := rng.randf_range(0.03, 0.45)
	var cond := {}
	for slot in parts:
		if str(parts[slot]) == "none":
			continue
		cond[slot] = {"rust": clampf(age * rng.randf_range(0.1, 0.7), 0.0, 1.0), "dirt": clampf(age * rng.randf_range(0.4, 1.3), 0.0, 1.0),
			"wear": clampf(age * rng.randf_range(0.3, 1.0), 0.0, 1.0)}
	var values := Sales.px_values(parts, cond)
	var look := PartsDB.detect_style(parts)
	return {"parts": parts, "paint": rng.randi() % Shed.PAINTS.size(), "cond": cond, "age": age,
		"km": roundi(age * 40000.0 + rng.randf_range(500.0, 8000.0)), "style": str(look["style"]) if look["proper"] else "",
		"style_text": PartsDB.style_text(parts), "model": Sales.model_text(parts), "hp": roundi(BikeBuild.new(parts, cond).hp()),
		"value": int(values["retail"]), "condition": float(values["condition"])}


## A group of bikers rides in (host only): `size` of them (0: one on their own or a group, at
## random), as many as there are free bays and chairs for. Returns their ids.
static func spawn_group(size := 0) -> Array:
	var rng: RandomNumberGenerator = Shed._rng
	if size <= 0:
		size = 1 if rng.randf() < SOLO_CHANCE else rng.randi_range(2, GROUP_MAX)
	var parks := free_parks()
	size = mini(size, parks.size())
	var seats := free_seats(size, rng) if size > 0 else []
	while size > 0 and seats.is_empty():
		size -= 1
		seats = free_seats(size, rng) if size > 0 else []
	if size <= 0:
		return []
	var s := _st()
	var group := int(s["next_group"])
	s["next_group"] = group + 1
	var now := clock()
	var leave := now + rng.randf_range(STAY_HOURS.x, STAY_HOURS.y)
	# Bays next to each other where there are any.
	var start := rng.randi() % maxi(1, parks.size() - size + 1)
	var out := []
	for i in size:
		var who := Sales._person(rng)
		if rng.randf() < 0.5:
			who["look"]["top"] = Color(0.07, 0.07, 0.08)   # in their leathers
		var id := int(s["next"])
		s["next"] = id + 1
		visitors()[id] = {"id": id, "group": group, "name": who["name"], "look": who["look"], "park": int(parks[start + i]),
			"seat": int(seats[i]), "arrived": now, "since": now, "leave_at": leave, "state": "in", "stand": -1, "offers": 0,
			"browse_at": now + (leave - now) * rng.randf_range(0.35, 0.7) if rng.randf() < BROWSE_CHANCE else -1.0,
			"chat": CHAT[rng.randi() % CHAT.size()], "said": "", "bike": _make_bike(rng)}
		out.append(id)
	Shed._mark_dirty()
	return out


static func _set_state(v: Dictionary, state: String) -> void:
	v["state"] = state
	v["since"] = clock()


## A showroom stand with a bike on show for a visitor to go and look at, or -1.
static func _stand_to_browse(rng: RandomNumberGenerator) -> int:
	var stands := []
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		if Sales.bike_on_stand(i) != 0:
			stands.append(i)
	return int(stands[rng.randi() % stands.size()]) if not stands.is_empty() else -1


## How many others are already looking at the bike on `stand` (where this one stands among them).
static func _lookers(stand: int) -> int:
	var n := 0
	for id in visitors():
		if str(visitors()[id]["state"]) == "browse" and int(visitors()[id].get("stand", -1)) == stand:
			n += 1
	return n


# ---------------------------------------------------------------------------- time passing

## The host's clock moves on: the cafe opens and shuts with the time of day, bikers come and
## go. `delta` is real seconds.
static func process(delta: float) -> void:
	advance(delta * Contracts.hours_rate(), Daylight.time_of_day())


## Moves the cafe's clock on `hours` game hours with the time of day at `tod` (host only).
static func advance(hours: float, tod: float) -> void:
	var s := _st()
	var before := float(s["clock"])
	s["clock"] = before + maxf(hours, 0.0)
	var now := float(s["clock"])
	var rng: RandomNumberGenerator = Shed._rng
	var changed := false
	var open := open_at(tod)
	if open != bool(s["open"]):
		s["open"] = open
		changed = true
		if open:
			s["next_at"] = now + FIRST_VISIT   # the first bikers turn up a little after opening
	for id in visitors().keys():
		var v: Dictionary = visitors()[id]
		var st := str(v["state"])
		if st in ["in", "browse"]:
			if not open and float(v["leave_at"]) > now + CLOSING_HOURS:
				v["leave_at"] = now + CLOSING_HOURS   # drinking up: it's closing time
				changed = true
			if now >= float(v["leave_at"]):
				_set_state(v, "out")
				changed = true
			elif st == "in" and float(v.get("browse_at", -1.0)) >= 0.0 and now >= float(v["browse_at"]):
				v["browse_at"] = -1.0
				var stand := _stand_to_browse(rng)
				if stand >= 0:
					v["stand"] = stand
					v["look_k"] = _lookers(stand)
					_set_state(v, "browse")
					_maybe_buyer(v, stand, rng)
				changed = true
		elif now - float(v.get("since", now)) > LEAVING_HOURS:
			visitors().erase(id)
			changed = true
	if open and now >= float(s["next_at"]):
		s["next_at"] = now + rng.randf_range(SPAWN_HOURS.x, SPAWN_HOURS.y)
		if not spawn_group().is_empty():
			changed = true
	if changed or floor(before) != floor(now):
		Shed._mark_dirty()
	if changed:
		Shed.changed.emit()


## A visitor looking at a bike that's for sale may make an offer on it, like a buyer online
## (it comes in on the Sales page and rings the till).
static func _maybe_buyer(v: Dictionary, stand: int, rng: RandomNumberGenerator) -> void:
	var b := Sales.bike_on_stand(stand)
	if b == 0 or not Sales.active(b) or Sales.offers().size() >= Sales.MAX_OFFERS or Sales._offers_on(b) >= Sales.MAX_OFFERS_PER_BIKE \
			or rng.randf() >= BUYER_CHANCE:
		return
	var oid := Sales.make_offer(b)
	var o: Dictionary = Sales.offers()[oid]
	o["buyer"] = str(v["name"])
	o["look"] = v["look"]
	o["said"] = "Spotted it from the cafe next door. " + str(o["said"])
	var news: Array = Sales._st()["news"]
	if not news.is_empty():
		news[0]["text"] = ("%s, in from the cafe, offered %s for %s." % [v["name"], money(int(o["amount"])), o["bike_name"]]).left(90)


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a "coffee_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	match a:
		"coffee_buy":
			var item := str(action.get("item", ""))
			if not MENU.has(item):
				return "That's not on the menu."
			if not is_open():
				return "The cafe's closed. It opens at %s." % Daylight.clock_text(OPEN_HOUR)
			if Shed.held_by(peer) != 0:
				return "Your hands are full. Put the part down first."
			var t := tray_of(peer)
			if not t.is_empty() and (t["items"] as Array).size() >= TRAY_MAX:
				return "Your tray's full."
			if int(action.get("paid", 0)) != price(item):
				return "The %s is %s." % [item_name(item).to_lower(), money(price(item))]
		"coffee_tray_down":
			if not carrying(peer):
				return "You're not carrying a tray."
			var xf = action.get("xf")
			if not (xf is Transform3D):
				return "Put it down on something flat."
			var at := (xf as Transform3D).origin
			if at.y < -0.5 or at.y > 6.0 or not Shed.in_work_area(at):
				return "Not out here: put it down at the cafe or the shed."
		"coffee_tray_take":
			var id := int(action.get("tray", 0))
			if not trays().has(id):
				return "That tray has gone."
			if int(trays()[id]["holder"]) != 0:
				return "Someone's carrying it."
			if carrying(peer):
				return "You've already got a tray."
			if Shed.held_by(peer) != 0:
				return "Your hands are full."
		"coffee_eat":
			var id := int(action.get("tray", 0))
			if not trays().has(id):
				return "That tray has gone."
			var holder := int(trays()[id]["holder"])
			if holder != 0 and holder != peer:
				return "That's someone else's."
			if (trays()[id]["items"] as Array).is_empty():
				return "There's nothing left on it."
		"coffee_offer":
			var v: Dictionary = visitors().get(int(action.get("visitor", 0)), {})
			if v.is_empty() or not here(v):
				return "They've gone."
			var amt := int(action.get("amount", 0))
			if amt <= 0:
				return "Name a price."
			if amt > MAX_OFFER:
				return "That's silly money."
			if int(v.get("offers", 0)) >= MAX_OFFERS:
				return "%s isn't selling. Leave it." % first_name(v)
			if amt > Shed.garage_money:
				return "The business only has %s." % money(Shed.garage_money)
		_:
			return "Unknown action."
	return ""


## Host: does a checked "coffee_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	match a:
		"coffee_buy":
			var item := str(action["item"])
			var t := tray_of(peer)
			if t.is_empty():
				t = _new_tray(peer)
			(t["items"] as Array).append(item)
			_st()["served"] = int(_st()["served"]) + 1
			return "%s on your tray (%s). Hold %s to %s it." % [item_name(item), money(price(item)),
				"right mouse", str(MENU[item]["verb"])]
		"coffee_tray_down":
			var t := tray_of(peer)
			var xf: Transform3D = action["xf"]
			if (t["items"] as Array).is_empty() and on_counter(xf.origin):
				trays().erase(int(t["id"]))
				return "You hand the empty tray back. Cheers!"
			t["holder"] = 0
			t["xf"] = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
			return ""
		"coffee_tray_take":
			trays()[int(action["tray"])]["holder"] = peer
			return ""
		"coffee_eat":
			var t: Dictionary = trays()[int(action["tray"])]
			var item := str((t["items"] as Array).pop_front())
			Shed._xp(peer, XP_KEY, 1.0, item)
			var lines: Array = TASTES.get(item, ["Lovely."])
			return str(lines[Shed._rng.randi() % lines.size()])
		"coffee_offer":
			return _offer(peer, int(action["visitor"]), int(action["amount"]))
	return ""


## An offer for a visitor's bike: weighed, and almost always turned down.
static func _offer(peer: int, id: int, amount: int) -> String:
	var v: Dictionary = visitors()[id]
	v["offers"] = int(v.get("offers", 0)) + 1
	var value := int(v["bike"]["value"])
	var chance := accept_chance(amount, value)
	var roll := test_roll if test_roll >= 0.0 else Shed._rng.randf()
	if roll < chance and Shed.charge_garage(amount, "Bought %s's bike at the cafe" % v["name"]):
		return _buy_bike(peer, v, amount)
	var r := float(amount) / maxf(1.0, float(value))
	var said := ""
	if r < ACCEPT_FLOOR:
		said = "Ha! It's worth a lot more than %s, mate." % money(amount)
	elif int(v["offers"]) >= MAX_OFFERS:
		said = "I've said no. She's not for sale. Enjoy your coffee."
	elif r < 1.3:
		said = ["Nah, she's not for sale.", "Tempting, but no.", "I'd miss it too much."][Shed._rng.randi() % 3]
	else:
		said = ["That's a good offer... but no. Sorry.", "Blimey. Let me think... no. Not today.",
			"You're keen! Still no, though."][Shed._rng.randi() % 3]
	v["said"] = said
	return "%s: \"%s\"" % [v["name"], said]


## The offer's taken: the bike is the shed's, parked where it stands in the cafe car park, and
## its rider walks off to get a lift home.
static func _buy_bike(peer: int, v: Dictionary, amount: int) -> String:
	var b: Dictionary = v["bike"]
	var paint = Shed.PAINTS[int(b.get("paint", 0)) % Shed.PAINTS.size()]
	var kind := PartsDB.style_noun(str(b["style"])) if str(b.get("style", "")) != "" else "bike"
	var bike_name := "%s's %s" % [first_name(v), kind]
	var id := Shed._new_bike(b["parts"], 0, bike_name, float(b.get("age", 0.2)), paint)
	var bike: Dictionary = Shed.bikes[id]
	bike["bay"] = -1
	bike["xf"] = park_xf(int(v["park"]))
	var cond: Dictionary = b.get("cond", {})
	for slot in cond:
		var it_id := Shed.item_on(id, str(slot))
		if it_id != 0 and cond[slot] is Dictionary:
			for k in ["rust", "dirt", "wear"]:
				Shed.items[it_id][k] = float(cond[slot].get(k, Shed.items[it_id][k]))
	bike["stand"] = Shed._rest_stand(id)
	bike["bought"] = amount
	bike["km"] = int(b.get("km", 0))
	Contracts.refresh_delivered(id)
	v["bike_id"] = id
	v["said"] = "Go on then. Look after her."
	_set_state(v, "sold")
	_st()["bought"] = int(_st()["bought"]) + 1
	Shed._xp(peer, BUY_XP_KEY, 1.0, "visitor:%d" % int(v["id"]))
	return "%s takes %s for it! %s is the shed's now, parked outside the cafe. %s walks off to get a lift home." % [
		v["name"], money(amount), bike_name, first_name(v)]


## Buys `item` from the counter for this player: their own money, then the host puts it on their
## tray. "" when it's on its way, else why not.
static func buy(item: String) -> String:
	var action := {"a": "coffee_buy", "item": item, "paid": price(item)}
	var why := Shed.check(Shed.me(), action)
	if why != "":
		return why
	if not Progress.spend(price(item), "Cafe: %s" % item_name(item).to_lower()):
		return "You only have %s." % money(Progress.money())
	Shed.request(action)
	return ""
