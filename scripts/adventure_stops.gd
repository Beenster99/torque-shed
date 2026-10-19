class_name AdventureStops
extends RefCounted
## The places along an adventure road: villages with a short high street (shops, a pub, a bus
## stop, cars parked up), bike cafes (bikes out front, tables outside), lay-bys and rest areas
## (bins, picnic benches, a view), viewpoints (a car park and a path out to a bench and rocks),
## an inn or a campsite every so often, and a shop in every fuel station's kiosk.
##
## plan() spaces them along the route as sites (AdventureRoute.add_site) before the road is laid,
## so the road runs straight and level past each, the same on every player's game from the seed:
## food every FOOD_EVERY (a village or a cafe, or the inn or campsite when one's due), somewhere
## to pull in every REST_EVERY (a lay-by, rest area or viewpoint) and a bed every SLEEP_EVERY.
## build() makes a stop's nodes when its chunk goes into the world (AdventureChunk.commit through
## AdventureWorld.site_builders), merged into a few meshes drawn only so far, and they go with
## the chunk when it's freed behind.
##
## Every stop has a sign on the left verge SIGN_BEFORE metres ahead of it, and places to use,
## nodes in these groups (each with meta "site" (the stop's name), "site_kind" and "s" (its
## distance along the route)):
##   SEAT_GROUP "adv_seat": somewhere to sit (a bench, a picnic bench, a cafe chair, a rock, a
##       log). The node's origin is the seat itself and its -Z the way you face sat there; meta
##       "seat" ("bench", "chair", "rock", "log", "picnic") and "height" (m off the ground).
##   COUNTER_GROUP "adv_counter": somewhere to buy food and drink, the origin where you stand to
##       be served and -Z towards the counter; meta "shop" (its name) and "menu", an Array of
##       {id, name, price (pounds), food, drink} where food and drink are how much of an empty
##       meter it fills (0 to 1).
##   BED_GROUP "adv_bed": an inn room (at the inn's door) or a tent pitch (at the tent's door),
##       the origin where you stand and -Z towards it; meta "bed" ("room" or "tent"), "name" and
##       "price" (pounds a night).

const SEAT_GROUP := "adv_seat"
const COUNTER_GROUP := "adv_counter"
const BED_GROUP := "adv_bed"
## The stops' site kinds (village rows are the rest of a village's high street, built with it).
const KINDS: Array[String] = ["village", "cafe", "layby", "rest_area", "viewpoint", "inn", "campsite"]
const ROW := "village_row"
## What each kind is for, on the satnav: "food", "rest", "sleep" (fuel stations are "fuel").
const NAV := {"village": "food", "cafe": "food", "inn": "sleep", "campsite": "sleep", "layby": "rest",
	"rest_area": "rest", "viewpoint": "rest", "fuel": "fuel"}
const LABELS := {"village": "Village", "cafe": "Bike cafe", "inn": "Inn", "campsite": "Campsite", "layby": "Lay-by",
	"rest_area": "Rest area", "viewpoint": "Viewpoint", "fuel": "Fuel"}
## Spacing along the route (m): the first food, then food every so often; somewhere to pull in;
## a bed (an inn or campsite, which serve food too).
const FOOD_FIRST := [8000.0, 15000.0]
const FOOD_EVERY := [15000.0, 25000.0]
const REST_FIRST := [3000.0, 6000.0]
const REST_EVERY := [5000.0, 10000.0]
const SLEEP_EVERY := [40000.0, 60000.0]
## How far a stop keeps from any other site (m), and how far it may be nudged to find room.
const CLEAR := 360.0
const NUDGE := 1400.0
## The sign this far before a stop.
const SIGN_BEFORE := 300.0
## How far out from the road the land is kept flat for each kind (m).
const FLAT := {"village": 18.0, "village_row": 16.0, "cafe": 32.0, "layby": 13.0, "rest_area": 34.0, "viewpoint": 42.0,
	"inn": 31.0, "campsite": 44.0}
## The hard ground (its surface) each kind's pad covers: [out from the road edge, half its length].
const PADS := {"village": [3.6, 24.0], "village_row": [3.6, 24.0], "cafe": [30.0, 22.0], "layby": [6.0, 30.0],
	"rest_area": [18.0, 26.0], "viewpoint": [16.0, 18.0], "inn": [14.0, 23.0], "campsite": [8.0, 6.0]}
## How far things are drawn (m, times the draw distance setting): the buildings and big shapes,
## and the small things (benches, bins, bikes, cars).
const FAR := 900.0
const NEAR := 220.0
## The traffic's models that are parked up at the stops (their first trim), made when the
## adventure starts (each takes a few tens of ms the first time) so a stop never hitches.
const PARKED: Array[String] = ["hatchback", "saloon", "estate", "van"]

## The menus: id -> [name, price, food, drink].
const FOODS := {
	"tea": ["Mug of tea", 2.0, 0.0, 0.35], "coffee": ["Coffee", 2.8, 0.0, 0.35], "water": ["Bottle of water", 1.2, 0.0, 0.45],
	"cola": ["Can of cola", 1.6, 0.05, 0.35], "energy": ["Energy drink", 2.2, 0.05, 0.3], "shandy": ["Pint of shandy", 4.5, 0.05, 0.4],
	"ale": ["Half of ale", 3.2, 0.05, 0.25], "juice": ["Orange juice", 2.0, 0.05, 0.4], "milk": ["Pint of milk", 1.4, 0.05, 0.35],
	"bacon_roll": ["Bacon roll", 4.5, 0.35, 0.0], "breakfast": ["Full breakfast", 9.5, 0.75, 0.05], "cake": ["Slice of cake", 3.2, 0.2, 0.0],
	"burger": ["Burger", 6.5, 0.5, 0.0], "sandwich": ["Sandwich", 3.6, 0.3, 0.0], "crisps": ["Crisps", 1.1, 0.1, 0.0],
	"chocolate": ["Chocolate bar", 1.2, 0.12, 0.0], "pasty": ["Pasty", 3.4, 0.4, 0.0], "pie": ["Pie and chips", 12.5, 0.75, 0.0],
	"ploughmans": ["Ploughman's lunch", 9.0, 0.55, 0.0], "fish": ["Fish and chips", 10.5, 0.7, 0.0], "chips": ["Bag of chips", 3.5, 0.3, 0.0],
	"bread": ["Fresh bread roll", 0.9, 0.15, 0.0], "scone": ["Cream tea", 6.0, 0.3, 0.3], "dinner": ["Three-course dinner", 18.0, 0.9, 0.1],
	"noodles": ["Pot noodle", 1.5, 0.3, 0.05], "beans": ["Tin of beans", 1.1, 0.3, 0.0], "ice_cream": ["Ice cream", 2.5, 0.1, 0.1],
}
const MENUS := {
	"cafe": ["tea", "coffee", "cola", "bacon_roll", "breakfast", "burger", "cake"],
	"shop": ["water", "cola", "milk", "sandwich", "crisps", "chocolate", "pasty"],
	"fuel": ["coffee", "water", "energy", "sandwich", "crisps", "chocolate"],
	"pub": ["shandy", "ale", "juice", "pie", "ploughmans", "crisps"],
	"chippy": ["fish", "chips", "cola", "water"],
	"bakery": ["bread", "pasty", "cake", "coffee"],
	"tea_room": ["tea", "scone", "cake", "juice"],
	"inn": ["ale", "tea", "juice", "dinner", "breakfast", "ploughmans"],
	"camp": ["tea", "milk", "water", "noodles", "beans", "bread", "ice_cream"],
	"van": ["tea", "coffee", "burger", "bacon_roll", "ice_cream", "cola"],
}
const ROOM_PRICE := 65.0
const PITCH_PRICE := 12.0

const NAME_A: Array[String] = ["Ash", "Thorn", "Brack", "Elm", "Stan", "Hol", "Brad", "Lang", "Kel", "Wick", "Mar", "Fen",
	"Hart", "Cold", "Mill", "Red", "Wether", "Oak", "Swin", "Bur"]
const NAME_B: Array[String] = ["by", "bridge", "ford", "ton", "ley", "well", "combe", "stead", "wick", "hope", "thwaite", "dale",
	"field", "worth", "ham", "moor"]
const CAFE_NAMES: Array[String] = ["Kickstand Cafe", "Twisties Cafe", "The Pit Stop", "Chain & Sprocket", "Top Box Diner",
	"The Apex Cafe", "Throttle Stop", "Gearbox Cafe", "Two Wheels Tea Bar", "The Rev Counter"]
const INN_NAMES: Array[String] = ["The Drovers Inn", "The Red Lion", "The Wheatsheaf", "The Packhorse", "The Black Bull",
	"The Rising Sun", "The Coach and Horses", "The Shepherd's Rest"]
const PUB_NAMES: Array[String] = ["The Crown", "The Plough", "The Fox", "The Bell", "The White Hart", "The Swan", "The Royal Oak"]
const CAMP_NAMES: Array[String] = ["Riverside Camping", "Hollow Oak Campsite", "Starfield Camping", "Beck Farm Campsite",
	"Hilltop Pitches", "Pine Hollow Camping"]
const VIEW_NAMES: Array[String] = ["Hawk Ridge", "Eagle Point", "Windy Gap", "Ravens Crag", "Sunset Edge", "High Tor",
	"Cloud Rock", "Kestrel View"]

const SIGN_BLUE := Color(0.08, 0.2, 0.55)
const SIGN_BROWN := Color(0.42, 0.22, 0.12)
const SIGN_GREEN := Color(0.06, 0.32, 0.18)


# ---------------------------------------------------------------------------- planning

## Spaces the stops along `route` (called by AdventureRoute.plan once its fuel stations are in,
## before the road is laid). Their own rng, so the stops don't change the rest of the plan's draws.
static func plan(route: AdventureRoute) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "adventure_stops", route.theme])
	var length := route.length
	# Food, and a bed when one's due (which is food too).
	var last_sleep := 0.0
	var s := rng.randf_range(FOOD_FIRST[0], FOOD_FIRST[1])
	var cafes := 0
	var villages := 0
	while s < length - 2500.0:
		var at := _room_at(route, s, 900.0)
		if at < 0.0:
			s += 500.0
			continue
		s = at
		var d := s - last_sleep
		var kind := ""
		if d >= SLEEP_EVERY[0] - 1.0:
			kind = "inn" if rng.randf() < 0.6 else "campsite"
			last_sleep = s
		else:
			# Mostly taking turns, so a ride sees both.
			kind = "cafe" if (cafes < villages or (cafes == villages and rng.randf() < 0.5)) else "village"
			if kind == "cafe":
				cafes += 1
			else:
				villages += 1
		_add(route, rng, kind, s)
		var gap := rng.randf_range(FOOD_EVERY[0], FOOD_EVERY[1])
		d = s - last_sleep
		if d < SLEEP_EVERY[0] and d + gap > SLEEP_EVERY[1]:
			gap = maxf(FOOD_EVERY[0], SLEEP_EVERY[1] - d - 300.0)
		s += gap
	# Somewhere to pull in.
	s = rng.randf_range(REST_FIRST[0], REST_FIRST[1])
	while s < length - 1500.0:
		var at := _room_at(route, s, NUDGE)
		if at < 0.0:
			s += REST_EVERY[0]
			continue
		var roll := rng.randf()
		_add(route, rng, "viewpoint" if roll < 0.35 else ("rest_area" if roll < 0.55 else "layby"), at)
		s = at + rng.randf_range(REST_EVERY[0], REST_EVERY[1])


## The nearest place to `s` within `reach` that's CLEAR of every site (and the start), or -1.
static func _room_at(route: AdventureRoute, s: float, reach: float) -> float:
	var step := 50.0
	var k := 0
	while k * step <= reach:
		for sign: float in ([1.0] if k == 0 else [1.0, -1.0]):
			var at := snappedf(s + sign * k * step, AdventureRoute.STEP)
			if at > 600.0 and at < route.length - 400.0 and _clear(route, at):
				return at
		k += 1
	return -1.0


static func _clear(route: AdventureRoute, s: float) -> bool:
	for st in route.sites:
		var gap := CLEAR + (120.0 if str(st["kind"]) == "village" else 0.0)
		if absf(float(st["s"]) - s) < gap:
			return false
	return true


## Adds a stop of `kind` at `s` (and a village's other rows), named and seeded.
static func _add(route: AdventureRoute, rng: RandomNumberGenerator, kind: String, s: float) -> void:
	var side := -1 if rng.randf() < 0.65 else 1   # mostly on the left, the near side
	var site := route.add_site(kind, s, side, float(FLAT[kind]), _name(rng, kind))
	site["stop"] = true
	site["seed"] = rng.randi()
	if kind == "village":
		# The high street: three rows of shops on this side, two over the road.
		var rows := [[-46.0, side], [46.0, side], [0.0, -side], [-46.0, -side], [46.0, -side]]
		for k in rows.size():
			var row := route.add_site(ROW, s + float(rows[k][0]), int(rows[k][1]), float(FLAT[ROW]), str(site["name"]))
			row["row"] = k
			row["seed"] = rng.randi()
			row["main_s"] = s


static func _name(rng: RandomNumberGenerator, kind: String) -> String:
	match kind:
		"village":
			return NAME_A[rng.randi() % NAME_A.size()] + NAME_B[rng.randi() % NAME_B.size()]
		"cafe":
			return CAFE_NAMES[rng.randi() % CAFE_NAMES.size()]
		"inn":
			return INN_NAMES[rng.randi() % INN_NAMES.size()]
		"campsite":
			return CAMP_NAMES[rng.randi() % CAMP_NAMES.size()]
		"viewpoint":
			return VIEW_NAMES[rng.randi() % VIEW_NAMES.size()] + " Viewpoint"
		"rest_area":
			return "Rest area"
	return "Lay-by"


## The stops on `route` (the places themselves, not a village's extra rows), in order.
static func stops(route: AdventureRoute) -> Array:
	return route.sites.filter(func(st): return KINDS.has(str(st["kind"])))


## The menu of `key` (see MENUS) as the counters carry it.
static func menu(key: String) -> Array:
	var out := []
	for id in MENUS.get(key, []):
		var f: Array = FOODS[id]
		out.append({"id": id, "name": f[0], "price": f[1], "food": f[2], "drink": f[3]})
	return out


## The surface of a stop's hard ground at `s`, `lat` metres off the centre line (+ right), or "".
static func pad_surface(route: AdventureRoute, s: float, lat: float) -> String:
	var e := route.width_at_s(s) * 0.5
	for st in route.sites:
		var pad: Array = PADS.get(str(st["kind"]), [])
		if pad.is_empty() or absf(float(st["s"]) - s) > float(pad[1]) or signf(lat) != float(st["side"]):
			continue
		if absf(lat) < e + 0.9 + float(pad[0]):
			return "gravel" if str(st["kind"]) in ["layby", "viewpoint", "campsite"] else "tarmac"
	return ""


# ---------------------------------------------------------------------------- building

## Puts the stops' builders (and the fuel stations' shops) into `world`'s site builders, and
## makes the parked cars' meshes ready.
static func register(world: AdventureWorld) -> void:
	for kind in PARKED:
		VehicleModel.parts(kind, 0)
	for kind in KINDS + [ROW]:
		world.site_builders[kind] = func(site, xf, _info): return build(world.route, site, xf)
	var fuel: Callable = world.site_builders.get("fuel", Callable())
	world.site_builders["fuel"] = func(site, xf, info):
		var node = fuel.call(site, xf, info) if fuel.is_valid() else null
		if node is Node3D:
			fuel_shop(world.route, site, xf, node)
		return node


## What's being built for one stop: its merged meshes (far: buildings and big shapes; near: the
## small things), its collision boxes, and its node.
class Kit:
	extends RefCounted
	var far := AdventureProps.new_arrays()
	var near := AdventureProps.new_arrays()
	var boxes := []   # [Transform3D, size]
	var root: Node3D
	var site: Dictionary
	var rng := RandomNumberGenerator.new()
	var surf := "tarmac"
	## The theme's building style (AdventureTheme.STYLES) and its name.
	var style: Dictionary = AdventureTheme.STYLES["mixed"]
	var style_name := "mixed"


## A stop's node at `xf` (the site's frame on the road's edge: local +x away from the road).
static func build(route: AdventureRoute, site: Dictionary, xf: Transform3D) -> Node3D:
	var k := Kit.new()
	k.site = site
	k.rng.seed = int(site.get("seed", hash([route.seed_value, site["s"]])))
	k.surf = route.surface_at_s(float(site["s"]))
	k.style_name = str(AdventureTheme.get_value(route.theme, "style", "mixed"))
	k.style = AdventureTheme.style(route.theme)
	k.root = Node3D.new()
	k.root.name = "Stop_%s_%d" % [str(site["kind"]), int(site["s"])]
	k.root.transform = xf
	k.root.set_meta("site", site)
	k.root.set_meta("style", k.style_name)
	match str(site["kind"]):
		"village":
			_village(k)
		ROW:
			_row(k)
		"cafe":
			_cafe(k)
		"layby":
			_layby(k, false)
		"rest_area":
			_layby(k, true)
		"viewpoint":
			_viewpoint(k)
		"inn":
			_inn(k)
		"campsite":
			_campsite(k)
	if str(site["kind"]) != ROW:
		_sign(route, k, xf)
	_finish(k)
	return k.root


## Turns the kit's arrays into its meshes and collision.
static func _finish(k: Kit) -> void:
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	for part in [["Far", k.far, FAR], ["Near", k.near, NEAR]]:
		var arr: Dictionary = part[1]
		if (arr["v"] as PackedVector3Array).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = AdventureProps.to_mesh(arr)
		if part[0] == "Near":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		AdventureChunk._range(mi, float(part[2]) * scale)
		k.root.add_child(mi)
	if not k.boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		body.set_meta("surface", "tarmac")
		for b in k.boxes:
			var shape := BoxShape3D.new()
			shape.size = b[1]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = b[0]
			body.add_child(cs)
		k.root.add_child(body)


# ---------------------------------------------------------------------------- pieces

## A box that's solid too (standing on xf's origin, like AdventureProps.box).
static func _solid(k: Kit, xf: Transform3D, size: Vector3, col: Color, near := false) -> void:
	AdventureProps.box(k.near if near else k.far, xf, size, col)
	k.boxes.append([xf * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), size])


## Hard ground from x0 to x1 out from the road and z0 to z1 along it, level with the road, with
## its own collision carrying `surface`.
static func _pad(k: Kit, x0: float, x1: float, z0: float, z1: float, col: Color, surface: String) -> void:
	col = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55)   # flat to the sky it reads much lighter than the walls
	AdventureProps._quad(k.far, Vector3(x0, 0.03, z1), Vector3(x1, 0.03, z1), Vector3(x1, 0.03, z0), Vector3(x0, 0.03, z0), col)
	AdventureProps.box(k.far, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, -0.6, (z0 + z1) * 0.5)),
		Vector3(x1 - x0, 0.62, z1 - z0), col.darkened(0.25), false)
	var body := StaticBody3D.new()
	body.name = "Pad"
	body.collision_layer = 1
	body.set_meta("surface", surface)
	var shape := BoxShape3D.new()
	shape.size = Vector3(x1 - x0, 0.6, z1 - z0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3((x0 + x1) * 0.5, -0.27, (z0 + z1) * 0.5)
	body.add_child(cs)
	k.root.add_child(body)


## Facing the road (local +z towards it) at (x, z) in the site's frame.
static func _front(x: float, z: float, y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, y, z))


## A node in `group` at `at` facing `dir` (site frame, flat), with `meta` on it.
static func _spot(k: Kit, group: String, at: Vector3, dir: Vector3, meta: Dictionary) -> Node3D:
	var n := Marker3D.new()
	n.name = "%s%d" % [group, k.root.get_child_count()]
	var f := Vector3(dir.x, 0.0, dir.z).normalized()
	n.transform = Transform3D(Basis.looking_at(f, Vector3.UP), at)
	n.add_to_group(group)
	n.set_meta("site", str(k.site.get("name", "")))
	n.set_meta("site_kind", str(k.site.get("kind", "")))
	n.set_meta("s", float(k.site.get("main_s", k.site.get("s", 0.0))))
	for key in meta:
		n.set_meta(key, meta[key])
	k.root.add_child(n)
	return n


static func _seat(k: Kit, at: Vector3, dir: Vector3, kind: String, height: float) -> void:
	_spot(k, SEAT_GROUP, at + Vector3(0, height, 0), dir, {"seat": kind, "height": height})


## A counter: you stand at `at` facing `dir` (towards it) to buy from `menu_key`'s menu.
static func _counter(k: Kit, at: Vector3, dir: Vector3, shop_name: String, menu_key: String) -> void:
	_spot(k, COUNTER_GROUP, at, dir, {"shop": shop_name, "menu": menu(menu_key)})


static func _bed(k: Kit, at: Vector3, dir: Vector3, kind: String, bed_name: String, price: float) -> void:
	_spot(k, BED_GROUP, at, dir, {"bed": kind, "name": bed_name, "price": price})


## A park bench at `xf` (its seat facing local +z), a seat for two.
static func _bench(k: Kit, xf: Transform3D) -> void:
	var wood := Color(0.48, 0.34, 0.2)
	var iron := Color(0.12, 0.12, 0.13)
	for sx: float in [-0.75, 0.75]:
		AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(sx, 0, 0)), Vector3(0.06, 0.45, 0.45), iron)
	AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), Vector3(1.7, 0.05, 0.45), wood)
	AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(0, 0.5, -0.22)), Vector3(1.7, 0.4, 0.05), wood)
	var fwd := xf.basis.z.normalized()
	for sx: float in [-0.42, 0.42]:
		_seat(k, xf * Vector3(sx, 0, 0.02), fwd, "bench", 0.45)


## A picnic bench at `xf` (its long side along local x): a table with a bench either side, two
## seats on each, facing over the table.
static func _picnic(k: Kit, xf: Transform3D) -> void:
	var wood := Color(0.55, 0.4, 0.24)
	AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(0, 0.7, 0)), Vector3(1.9, 0.05, 0.75), wood)
	for sx: float in [-0.75, 0.75]:
		AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(sx, 0, 0)), Vector3(0.08, 0.7, 1.5), wood.darkened(0.2))
	for sz: float in [-0.65, 0.65]:
		AdventureProps.box(k.near, xf * Transform3D(Basis(), Vector3(0, 0.4, sz)), Vector3(1.9, 0.05, 0.28), wood)
		var face := xf.basis * Vector3(0, 0, -signf(sz))
		for sx: float in [-0.45, 0.45]:
			_seat(k, xf * Vector3(sx, 0, sz), face, "picnic", 0.43)
	k.boxes.append([xf * Transform3D(Basis(), Vector3(0, 0.4, 0)), Vector3(1.9, 0.8, 1.5)])


## A round cafe table at `at` with `n` chairs round it facing in.
static func _table(k: Kit, at: Vector3, n: int, col: Color) -> void:
	AdventureProps.cone(k.near, Transform3D(Basis(), at), 0.05, 0.0, 0.72, Color(0.15, 0.15, 0.15), 5, 0.05)
	AdventureProps.cone(k.near, Transform3D(Basis(), at), 0.45, 0.72, 0.76, col, 10, 0.45)
	for j in n:
		var a := TAU * j / n + 0.4
		var p := at + Vector3(cos(a), 0, sin(a)) * 0.8
		var face := (at - p).normalized()
		var cxf := Transform3D(Basis.looking_at(-face, Vector3.UP), p)   # local +z towards the table
		AdventureProps.box(k.near, cxf, Vector3(0.42, 0.45, 0.42), Color(0.2, 0.2, 0.22))
		AdventureProps.box(k.near, cxf * Transform3D(Basis(), Vector3(0, 0.45, -0.19)), Vector3(0.42, 0.42, 0.05), Color(0.2, 0.2, 0.22))
		_seat(k, p, face, "chair", 0.45)


static func _bin(k: Kit, at: Vector3) -> void:
	AdventureProps.cone(k.near, Transform3D(Basis(), at), 0.28, 0.0, 0.85, Color(0.12, 0.25, 0.14), 8, 0.3)
	AdventureProps.cone(k.near, Transform3D(Basis(), at), 0.31, 0.85, 0.92, Color(0.08, 0.08, 0.08), 8, 0.31)


## A sit-on rock at `at`, facing `dir`.
static func _rock(k: Kit, at: Vector3, dir: Vector3, seed_value: int) -> void:
	AdventureProps.blob(k.near, at + Vector3(0, 0.2, 0), Vector3(0.75, 0.42, 0.6), Color(0.5, 0.49, 0.46), seed_value)
	_seat(k, at, dir, "rock", 0.5)


## A street lamp at `at` that lights at night.
static func _lamp(k: Kit, at: Vector3, light := true) -> void:
	AdventureProps.box(k.far, Transform3D(Basis(), at), Vector3(0.14, 5.0, 0.14), Color(0.2, 0.21, 0.22))
	AdventureProps.box(k.far, Transform3D(Basis(), at + Vector3(-0.5, 4.9, 0)), Vector3(1.1, 0.12, 0.25), Color(0.2, 0.21, 0.22))
	if light:
		var lamp := OmniLight3D.new()
		lamp.position = at + Vector3(-0.8, 4.6, 0)
		lamp.omni_range = 18.0
		lamp.light_energy = 0.0
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.shadow_enabled = false
		lamp.add_to_group(Daylight.NIGHT_LIGHTS)
		lamp.set_meta("night_energy", 1.8)
		k.root.add_child(lamp)


## A building `w` wide (along the road), `d` deep and `h` to the eaves, its front facing the road
## at `x` out (from the road's edge) and `z` along, with a door, windows and a name over the door.
## Returns the transform of its door, on the ground in front of it (local +z out of the door).
static func _house(k: Kit, x: float, z: float, w: float, d: float, h: float, wall: Color, roof: Color, title := "",
		awning := Color(0, 0, 0, 0), flat_roof := false) -> Transform3D:
	flat_roof = flat_roof or bool(k.style["flat"])   # adobe
	var xf := _front(x + d * 0.5, z)
	AdventureProps.box(k.far, xf, Vector3(w, h, d), wall, flat_roof)
	k.boxes.append([xf * Transform3D(Basis(), Vector3(0, h * 0.5, 0)), Vector3(w, h, d)])
	if flat_roof:
		AdventureProps.box(k.far, xf * Transform3D(Basis(), Vector3(0, h, 0)), Vector3(w + 0.3, 0.25, d + 0.3), roof)
	else:
		AdventureProps.gable(k.far, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), d, w, h, minf(d * 0.4, 3.0), roof, wall)
	var front := d * 0.5
	var glass := Color(0.14, 0.19, 0.26)
	var door_x := -w * 0.5 + 1.4 if w > 6.0 else 0.0
	AdventureProps.box(k.far, xf * Transform3D(Basis(), Vector3(door_x, 0, front)), Vector3(1.1, 2.1, 0.08), Color(0.25, 0.14, 0.09))
	# A shop window on the ground floor, windows above.
	AdventureProps.box(k.far, xf * Transform3D(Basis(), Vector3(door_x + w * 0.42, 0.6, front)), Vector3(w * 0.5, 1.5, 0.06), glass)
	if h > 4.5:
		for wx: float in [-w * 0.3, 0.0, w * 0.3]:
			AdventureProps.box(k.far, xf * Transform3D(Basis(), Vector3(wx, h - 2.0, front)), Vector3(1.0, 1.1, 0.06), glass)
	if awning.a > 0.0:
		var ax := xf * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(door_x + w * 0.42, 2.45, front + 0.7))
		AdventureProps.box(k.far, ax, Vector3(w * 0.55, 0.06, 1.5), awning)
	if title != "":
		AdventureProps.box(k.far, xf * Transform3D(Basis(), Vector3(0, 2.75, front)), Vector3(w * 0.8, 0.6, 0.1), Color(0.12, 0.12, 0.14))
		var label := Label3D.new()
		label.text = title
		label.font_size = 64
		label.pixel_size = 0.0075
		label.outline_size = 0
		label.modulate = Color(0.98, 0.94, 0.8)
		label.width = w * 0.8 / 0.0075
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.transform = xf * Transform3D(Basis(), Vector3(0, 3.05, front + 0.07))
		label.visibility_range_end = 140.0
		k.root.add_child(label)
	return xf * Transform3D(Basis(), Vector3(door_x, 0, front + 0.9))


## A parked car (one of the traffic's own models, its far mesh) at `xf` (facing local -z).
static func _car(k: Kit, xf: Transform3D) -> void:
	var kind := PARKED[k.rng.randi() % PARKED.size()]
	var look := VehicleModel.look_of(kind, k.rng.randi() % 100000)
	var parts := VehicleModel.parts(kind, 0)
	var mi := MeshInstance3D.new()
	mi.name = "Car"
	mi.mesh = parts["far"]
	var keys: Array = parts["keys_far"]
	for i in keys.size():
		if keys[i] == "paint":
			mi.set_surface_override_material(i, VehicleModel.paint_material(look["paint"]))
		elif keys[i] == "paint2":
			mi.set_surface_override_material(i, VehicleModel.paint_material(look["paint2"]))
	mi.transform = xf
	AdventureChunk._range(mi, NEAR * clampf(Settings.gfx_draw_distance, 0.5, 2.0))
	k.root.add_child(mi)
	var spec: Dictionary = VehicleModel.SPECS[kind]
	k.boxes.append([xf * Transform3D(Basis(), Vector3(0, float(spec["h"]) * 0.5, 0)), Vector3(float(spec["w"]) * 2.0, float(spec["h"]), float(spec["len"]))])


## A motorbike parked on its side stand at `xf` (facing local -z), in `col`.
static func _bike(k: Kit, xf: Transform3D, col: Color) -> void:
	var lean := xf * Transform3D(Basis(Vector3.BACK, 0.12), Vector3.ZERO)
	var tyre := Color(0.05, 0.05, 0.05)
	for wz: float in [-0.72, 0.72]:
		# A wheel: two square slabs turned 45 degrees to each other, an octagon from the side.
		for turn: float in [0.0, PI * 0.25]:
			AdventureProps.box(k.near, lean * Transform3D(Basis(Vector3.RIGHT, turn), Vector3(0, 0.33, wz)) * Transform3D(Basis(), Vector3(0, -0.29, 0)),
				Vector3(0.12, 0.58, 0.58), tyre)
	AdventureProps.box(k.near, lean * Transform3D(Basis(), Vector3(0, 0.38, 0)), Vector3(0.28, 0.32, 0.9), Color(0.2, 0.2, 0.21))   # engine
	AdventureProps.box(k.near, lean * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.72, -0.12)), Vector3(0.34, 0.26, 0.6), col)   # tank
	AdventureProps.box(k.near, lean * Transform3D(Basis(), Vector3(0, 0.76, 0.45)), Vector3(0.28, 0.1, 0.6), Color(0.08, 0.08, 0.08))   # seat
	AdventureProps.box(k.near, lean * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, 0.62, -0.65)), Vector3(0.06, 0.55, 0.06), Color(0.6, 0.6, 0.62))   # forks
	AdventureProps.box(k.near, lean * Transform3D(Basis(), Vector3(0, 0.95, -0.55)), Vector3(0.7, 0.04, 0.04), Color(0.1, 0.1, 0.1))   # bars
	if k.rng.randf() < 0.5:
		AdventureProps.box(k.near, lean * Transform3D(Basis(), Vector3(0, 0.84, 0.82)), Vector3(0.42, 0.32, 0.36), Color(0.1, 0.1, 0.11))   # top box


## The roadside sign SIGN_BEFORE metres ahead of the stop, on the left verge facing the way you
## come, built into the stop's node (in its frame) so it comes and goes with it.
static func _sign(route: AdventureRoute, k: Kit, xf: Transform3D) -> void:
	var site := k.site
	var s := float(site["s"])
	var ss := maxf(s - SIGN_BEFORE, 20.0)
	var si: int = site["i"]
	var h := route.hd[si]
	var e := route.width[si] * 0.5
	var lat := (e + 0.9) * float(site["side"])
	# The chunk's anchor, from where the site's frame sits in it.
	var ax := route.px[si] + cos(h) * lat - xf.origin.x
	var az := route.pz[si] + sin(h) * lat - xf.origin.z
	var hs := route.heading_at_s(ss)
	var slat := -(route.width_at_s(ss) * 0.5 + 1.8)
	var p := route.xz_at(ss, slat)
	var i := clampi(int(round(ss / AdventureRoute.STEP)), 0, route.knot_count() - 1)
	var y := route.land_height(i, slat, p[0], p[1])
	var r := Vector3(cos(hs), 0, sin(hs))
	var fwd := Vector3(sin(hs), 0, -cos(hs))
	var world_xf := Transform3D(Basis(r, Vector3.UP, -fwd), Vector3(p[0] - ax, y - 0.05, p[1] - az))
	var local := xf.affine_inverse() * world_xf
	var kind := str(site["kind"])
	var col := SIGN_BROWN if kind in ["viewpoint", "campsite", "inn"] else (SIGN_BLUE if kind in ["layby", "rest_area"] else SIGN_GREEN)
	var text := "%s\n%s" % [str(site["name"]), _sign_line(kind)]
	if kind == "layby":
		text = "P  Lay-by\n%d m" % int(SIGN_BEFORE)
	elif kind == "rest_area":
		text = "P  Rest area\nWC  picnic  %d m" % int(SIGN_BEFORE)
	var board_w := 3.4
	for sx: float in [-board_w * 0.42, board_w * 0.42]:
		AdventureProps.box(k.far, local * Transform3D(Basis(), Vector3(sx, 0, 0)), Vector3(0.09, 2.2, 0.09), Color(0.55, 0.56, 0.58))
	AdventureProps.box(k.far, local * Transform3D(Basis(), Vector3(0, 1.3, 0)), Vector3(board_w, 1.25, 0.06), col)
	AdventureProps.box(k.far, local * Transform3D(Basis(), Vector3(0, 1.3, -0.035)), Vector3(board_w + 0.08, 1.33, 0.02), Color(0.95, 0.95, 0.95))
	var label := Label3D.new()
	label.name = "Sign"
	label.text = text
	label.font_size = 56
	label.pixel_size = 0.0062
	label.outline_size = 0
	label.modulate = Color(1, 1, 1)
	label.width = (board_w - 0.2) / 0.0062
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.transform = local * Transform3D(Basis(), Vector3(0, 1.3 + 0.625, 0.04))
	label.visibility_range_end = 220.0
	label.set_meta("for_s", s)
	k.root.add_child(label)
	k.root.set_meta("sign", label)
	# A village also has its name where the houses start.
	if kind == "village":
		var vs := s - 95.0
		var vh := route.heading_at_s(vs)
		var vlat := -(route.width_at_s(vs) * 0.5 + 1.6)
		var vp := route.xz_at(vs, vlat)
		var vi := clampi(int(round(vs / AdventureRoute.STEP)), 0, route.knot_count() - 1)
		var vr := Vector3(cos(vh), 0, sin(vh))
		var vf := Vector3(sin(vh), 0, -cos(vh))
		var vxf := xf.affine_inverse() * Transform3D(Basis(vr, Vector3.UP, -vf), Vector3(vp[0] - ax, route.land_height(vi, vlat, vp[0], vp[1]) - 0.05, vp[1] - az))
		AdventureProps.box(k.far, vxf, Vector3(0.08, 1.4, 0.08), Color(0.55, 0.56, 0.58))
		AdventureProps.box(k.far, vxf * Transform3D(Basis(), Vector3(0, 1.0, 0)), Vector3(1.9, 0.6, 0.05), Color(0.96, 0.96, 0.94))
		var vl := Label3D.new()
		vl.text = str(site["name"])
		vl.font_size = 48
		vl.pixel_size = 0.007
		vl.outline_size = 0
		vl.modulate = Color(0.05, 0.05, 0.05)
		vl.transform = vxf * Transform3D(Basis(), Vector3(0, 1.3, 0.04))
		vl.visibility_range_end = 150.0
		k.root.add_child(vl)


static func _sign_line(kind: String) -> String:
	match kind:
		"village":
			return "Shops  pub  %d m" % int(SIGN_BEFORE)
		"cafe":
			return "Bikers welcome  %d m" % int(SIGN_BEFORE)
		"inn":
			return "Food  rooms  %d m" % int(SIGN_BEFORE)
		"campsite":
			return "Tents  shop  %d m" % int(SIGN_BEFORE)
		"viewpoint":
			return "Parking  %d m" % int(SIGN_BEFORE)
	return "%d m" % int(SIGN_BEFORE)


# ---------------------------------------------------------------------------- the places

## The walls a stop's buildings may have: the theme's style (whitewash, adobe, chalet, stone), or
## the varied mix (sandy colours out on the sand).
static func _walls(k: Kit) -> Array:
	if k.style_name != "mixed":
		return k.style["walls"]
	if k.surf == "sand":
		return [Color(0.86, 0.74, 0.55), Color(0.92, 0.85, 0.7), Color(0.8, 0.66, 0.5)]
	return [Color(0.86, 0.82, 0.72), Color(0.72, 0.62, 0.5), Color(0.6, 0.32, 0.24), Color(0.9, 0.9, 0.88), Color(0.68, 0.7, 0.66)]


static func _roof(k: Kit) -> Color:
	if k.surf == "snow":
		return Color(0.92, 0.93, 0.96)
	if k.style_name != "mixed":
		return _pick(k, k.style["roofs"])
	return [Color(0.25, 0.22, 0.22), Color(0.45, 0.2, 0.15), Color(0.32, 0.34, 0.36)][k.rng.randi() % 3]


static func _pick(k: Kit, list: Array) -> Variant:
	return list[k.rng.randi() % list.size()]


## The heart of a village: the pub with its beer garden, a bus stop, and the pavement.
static func _village(k: Kit) -> void:
	var pave := Color(0.62, 0.61, 0.58)
	_pad(k, 0.6, 3.6, -24.0, 24.0, pave, "tarmac")
	var pub_name: String = _pick(k, PUB_NAMES)
	var door := _house(k, 3.8, -8.0, 15.0, 9.0, 6.2, _pick(k, _walls(k)), _roof(k), pub_name.to_upper())
	_counter(k, door.origin, -door.basis.z, pub_name, "pub")
	# The beer garden beside it, behind a low wall.
	AdventureProps._quad(k.far, Vector3(4.0, 0.02, 20.0), Vector3(14.0, 0.02, 20.0), Vector3(14.0, 0.02, 3.0), Vector3(4.0, 0.02, 3.0), Color(0.3, 0.42, 0.2))
	_solid(k, Transform3D(Basis(), Vector3(4.0, 0, 11.5)), Vector3(0.3, 0.7, 17.0), Color(0.55, 0.52, 0.46), true)
	for z: float in [7.0, 12.5, 18.0]:
		_picnic(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(9.0, 0, z)))
	_bin(k, Vector3(4.6, 0.03, 2.2))
	# The bus stop on the pavement: a shelter with a bench in it, facing the road.
	var bus := _front(2.6, -20.0, 0.03)
	AdventureProps.box(k.near, bus * Transform3D(Basis(), Vector3(0, 0, -0.6)), Vector3(3.0, 2.3, 0.06), Color(0.6, 0.7, 0.75, 1.0))
	AdventureProps.box(k.near, bus * Transform3D(Basis(), Vector3(0, 2.3, 0)), Vector3(3.1, 0.08, 1.3), Color(0.2, 0.2, 0.22))
	for sx: float in [-1.5, 1.5]:
		AdventureProps.box(k.near, bus * Transform3D(Basis(), Vector3(sx, 0, 0)), Vector3(0.06, 2.3, 1.2), Color(0.2, 0.2, 0.22))
	_bench(k, bus * Transform3D(Basis(), Vector3(0, 0, -0.35)))
	AdventureProps.box(k.far, bus * Transform3D(Basis(), Vector3(1.9, 0, 0.3)), Vector3(0.08, 2.6, 0.08), Color(0.3, 0.3, 0.32))
	AdventureProps.box(k.far, bus * Transform3D(Basis(), Vector3(1.9, 2.3, 0.3)), Vector3(0.5, 0.5, 0.05), Color(0.9, 0.75, 0.1))
	var bl := Label3D.new()
	bl.text = "BUS"
	bl.font_size = 40
	bl.pixel_size = 0.006
	bl.modulate = Color(0.05, 0.05, 0.05)
	bl.outline_size = 0
	bl.transform = bus * Transform3D(Basis(), Vector3(1.9, 2.55, 0.33))
	bl.visibility_range_end = 80.0
	k.root.add_child(bl)
	_lamp(k, Vector3(1.0, 0.03, 0.0))


## A row of a village's high street: shops and houses on the pavement, a tea room's tables, or
## the car park.
static func _row(k: Kit) -> void:
	var pave := Color(0.62, 0.61, 0.58)
	var row := int(k.site.get("row", 0))
	var name := str(k.site.get("name", ""))
	if row == 2:
		# Over the road from the pub: the village car park.
		_pad(k, 0.6, 15.0, -22.0, 22.0, Color(0.3, 0.3, 0.31), "tarmac")
		for j in 6:
			var z := -16.0 + j * 4.2
			AdventureProps.box(k.far, Transform3D(Basis(), Vector3(9.0, 0.035, z - 2.1)), Vector3(9.0, 0.01, 0.1), Color(0.9, 0.9, 0.88))
			if k.rng.randf() < 0.65:
				_car(k, Transform3D(Basis(Vector3.UP, PI * 0.5 if k.rng.randf() < 0.5 else -PI * 0.5), Vector3(9.5, 0.03, z)))
		_bench(k, _front(15.6, 18.0, 0.0) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
		_lamp(k, Vector3(1.0, 0.03, 0.0), false)
		return
	_pad(k, 0.6, 3.6, -24.0, 24.0, pave, "tarmac")
	var shops := [["General Store", "shop"], ["Bakery", "bakery"], ["Fish & Chips", "chippy"], ["Tea Room", "tea_room"],
		["Post Office", ""], ["Butcher", ""], ["Hardware", ""], ["", ""], ["", ""]]
	var z := -22.0
	var made := 0
	while z < 20.0:
		var w := k.rng.randf_range(8.0, 12.0)
		w = minf(w, 22.0 - z)
		if w < 5.0:
			break
		var pick: Array = shops[k.rng.randi() % shops.size()]
		# Every row has at least one place to eat; the first row has the general store.
		if row == 0 and made == 0:
			pick = shops[0]
		elif made == 1 and row != 0:
			pick = shops[1 + k.rng.randi() % 3]
		var title: String = pick[0]
		var awning: Color = _pick(k, [Color(0.15, 0.35, 0.2), Color(0.6, 0.12, 0.1), Color(0.12, 0.22, 0.45)]) if title != "" else Color(0, 0, 0, 0)
		var door := _house(k, 3.8, z + w * 0.5, w, 8.0, 5.6 if k.rng.randf() < 0.6 else 3.2, _pick(k, _walls(k)), _roof(k),
			title.to_upper(), awning, k.rng.randf() < 0.2)
		if pick[1] != "":
			_counter(k, door.origin, -door.basis.z, "%s %s" % [name, title], pick[1])
			if pick[1] == "tea_room" or pick[1] == "bakery":
				_table(k, door.origin + door.basis.z * 0.2 + door.basis.x * 2.4, 2, Color(0.9, 0.9, 0.88))
		made += 1
		z += w + 0.4
	_bin(k, Vector3(3.2, 0.03, 0.5))
	_bench(k, _front(3.1, 6.0, 0.03))
	_lamp(k, Vector3(1.0, 0.03, -12.0), row == 0)


## A bike cafe: a forecourt with the bikes parked out front, tables outside and the cafe behind.
static func _cafe(k: Kit) -> void:
	var name := str(k.site.get("name", "Cafe"))
	_pad(k, 0.6, 30.0, -22.0, 22.0, Color(0.33, 0.33, 0.34) if k.surf != "sand" else Color(0.6, 0.55, 0.45), "tarmac")
	var wall: Color = _pick(k, [Color(0.15, 0.15, 0.17), Color(0.85, 0.82, 0.74), Color(0.55, 0.15, 0.12)])
	var door := _house(k, 21.0, 5.0, 17.0, 8.5, 4.0, wall, Color(0.2, 0.2, 0.22), name.to_upper(), Color(0.85, 0.5, 0.08), true)
	_counter(k, door.origin, -door.basis.z, name, "cafe")
	# A serving hatch at the side for the queue out the door.
	_counter(k, door.origin + door.basis.x * 6.0, -door.basis.z, name + " (hatch)", "van")
	# The tables outside, under umbrellas.
	for j in 4:
		var at := Vector3(15.0 if j % 2 == 0 else 11.0, 0.03, -2.0 + j * 4.2)
		_table(k, at, 4, Color(0.92, 0.92, 0.9))
		AdventureProps.cone(k.near, Transform3D(Basis(), at), 0.03, 0.76, 2.3, Color(0.3, 0.3, 0.3), 4, 0.03)
		AdventureProps.cone(k.near, Transform3D(Basis(), at), 1.4, 2.0, 2.45, [Color(0.85, 0.15, 0.1), Color(0.95, 0.95, 0.92)][j % 2], 8)
	# The bikes parked in a row at the front, angled in, and a couple of cars at the end.
	var cols := [Color(0.85, 0.1, 0.08), Color(0.1, 0.1, 0.12), Color(0.95, 0.6, 0.05), Color(0.1, 0.35, 0.7), Color(0.85, 0.85, 0.85),
		Color(0.1, 0.45, 0.2)]
	var bikes := 4 + k.rng.randi() % 5
	for j in bikes:
		_bike(k, Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.35), Vector3(5.5, 0.03, -19.0 + j * 1.6)), cols[k.rng.randi() % cols.size()])
	for j in 2:
		if k.rng.randf() < 0.7:
			_car(k, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(8.0, 0.03, 15.0 + j * 3.2)))
	_bench(k, _front(20.4, -6.0, 0.03))
	_bin(k, Vector3(20.5, 0.03, -9.0))
	# A sign on a pole by the road.
	AdventureProps.box(k.far, Transform3D(Basis(), Vector3(2.0, 0.03, -21.0)), Vector3(0.2, 4.5, 0.2), Color(0.3, 0.3, 0.32))
	AdventureProps.box(k.far, _front(2.0, -21.0, 3.6), Vector3(3.0, 1.2, 0.15), Color(0.85, 0.5, 0.08))
	var label := Label3D.new()
	label.text = "BIKE CAFE"
	label.font_size = 64
	label.pixel_size = 0.009
	label.outline_size = 6
	label.transform = _front(1.9, -21.0, 4.2)
	label.visibility_range_end = 200.0
	k.root.add_child(label)
	_lamp(k, Vector3(19.0, 0.03, -12.0))


## A lay-by (a gravel pull-in, bins and a picnic bench looking out), or a bigger rest area with
## a toilet block, picnic benches on the grass and an information board.
static func _layby(k: Kit, big: bool) -> void:
	var gravel := Color(0.5, 0.47, 0.42) if k.surf != "snow" else Color(0.75, 0.76, 0.78)
	if not big:
		_pad(k, 0.6, 6.0, -30.0, 30.0, gravel, "gravel")
		_bin(k, Vector3(6.6, 0.0, -8.0))
		_bin(k, Vector3(6.6, 0.0, 9.0))
		_picnic(k, Transform3D(Basis(), Vector3(9.5, -0.1, 0.0)))
		_bench(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(9.0, -0.1, 14.0)))
		AdventureProps.box(k.far, Transform3D(Basis(), Vector3(0.9, 0.0, -28.0)), Vector3(0.08, 2.2, 0.08), Color(0.6, 0.6, 0.62))
		AdventureProps.box(k.far, _front(0.9, -28.0, 1.6), Vector3(0.7, 0.7, 0.05), SIGN_BLUE)
		return
	_pad(k, 0.6, 18.0, -26.0, 26.0, Color(0.32, 0.32, 0.33), "tarmac")
	for j in 5:
		AdventureProps.box(k.far, Transform3D(Basis(), Vector3(12.0, 0.035, -14.0 + j * 4.0)), Vector3(9.0, 0.01, 0.1), Color(0.9, 0.9, 0.88))
	if k.rng.randf() < 0.6:
		_car(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12.0, 0.03, -12.0)))
	_house(k, 19.0, -18.0, 7.0, 5.0, 2.8, Color(0.6, 0.58, 0.52), Color(0.25, 0.25, 0.27), "TOILETS", Color(0, 0, 0, 0), true)
	# A vending machine by the toilets.
	_solid(k, _front(19.4, -12.5, 0.03), Vector3(1.0, 1.9, 0.8), Color(0.75, 0.12, 0.1), true)
	_counter(k, Vector3(18.4, 0.03, -12.5), Vector3(1, 0, 0), "Vending machine", "fuel")
	for j in 3:
		_picnic(k, Transform3D(Basis(Vector3.UP, 0.3 * (j - 1)), Vector3(23.0 + j * 2.5, -0.1, -4.0 + j * 7.0)))
	_bench(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(30.0, -0.1, 16.0)))
	_bin(k, Vector3(18.6, 0.03, 0.0))
	_bin(k, Vector3(18.6, 0.03, 12.0))
	# The information board.
	var board := _front(18.8, 6.0, 0.0)
	AdventureProps.box(k.far, board * Transform3D(Basis(), Vector3(-0.6, 0, 0)), Vector3(0.1, 1.9, 0.1), Color(0.35, 0.25, 0.15))
	AdventureProps.box(k.far, board * Transform3D(Basis(), Vector3(0.6, 0, 0)), Vector3(0.1, 1.9, 0.1), Color(0.35, 0.25, 0.15))
	AdventureProps.box(k.far, board * Transform3D(Basis(), Vector3(0, 1.0, 0)), Vector3(1.5, 0.9, 0.06), Color(0.2, 0.3, 0.22))
	_lamp(k, Vector3(17.5, 0.03, -2.0), false)


## A viewpoint: a car park, and a path out to a low wall with a bench, rocks to sit on and a
## telescope, looking out over the land.
static func _viewpoint(k: Kit) -> void:
	var gravel := Color(0.52, 0.49, 0.44) if k.surf != "snow" else Color(0.78, 0.79, 0.82)
	_pad(k, 0.6, 16.0, -18.0, 18.0, gravel, "gravel")
	for j in 4:
		if k.rng.randf() < 0.45:
			_car(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(11.0, 0.03, -12.0 + j * 3.4)))
	# The path, gravel on the grass, out to the edge.
	AdventureProps._quad(k.far, Vector3(16.0, 0.0, 1.0), Vector3(38.0, 0.0, 1.0), Vector3(38.0, 0.0, -1.0), Vector3(16.0, 0.0, -1.0), gravel.darkened(0.08))
	AdventureProps._quad(k.far, Vector3(35.0, 0.0, 6.0), Vector3(41.0, 0.0, 6.0), Vector3(41.0, 0.0, -6.0), Vector3(35.0, 0.0, -6.0), gravel.darkened(0.08))
	# The low stone wall along the edge, the bench and the rocks looking out.
	_solid(k, Transform3D(Basis(), Vector3(41.6, -0.1, 0.0)), Vector3(0.5, 0.75, 14.0), Color(0.55, 0.53, 0.5))
	_bench(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(39.6, -0.1, -2.0)))
	_bench(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(39.6, -0.1, 2.5)))
	_rock(k, Vector3(37.5, -0.1, 5.5), Vector3(1, 0, 0.3), 21)
	_rock(k, Vector3(38.0, -0.1, -5.5), Vector3(1, 0, -0.2), 23)
	# The telescope on its post, and a board saying what you're looking at.
	AdventureProps.box(k.near, Transform3D(Basis(), Vector3(40.5, -0.1, 0.4)), Vector3(0.12, 1.2, 0.12), Color(0.2, 0.2, 0.22))
	AdventureProps.box(k.near, Transform3D(Basis(Vector3.BACK, 0.2), Vector3(40.5, 1.15, 0.4)), Vector3(0.6, 0.22, 0.22), Color(0.15, 0.3, 0.2))
	AdventureProps.box(k.far, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(17.0, 0.0, 2.5)), Vector3(1.2, 1.5, 0.06), SIGN_BROWN)
	_bin(k, Vector3(16.6, 0.0, -2.0))


## An inn: a two-storey pub with rooms, its car park and a few tables outside.
static func _inn(k: Kit) -> void:
	var name := str(k.site.get("name", "Inn"))
	_pad(k, 0.6, 14.0, -23.0, 23.0, Color(0.33, 0.33, 0.34), "tarmac")
	var wall: Color = _pick(k, [Color(0.92, 0.9, 0.84), Color(0.62, 0.55, 0.45), Color(0.82, 0.78, 0.68)] if k.style_name == "mixed" else _walls(k))
	var door := _house(k, 15.0, 0.0, 22.0, 11.0, 6.6, wall, _roof(k), name.to_upper())
	_counter(k, door.origin, -door.basis.z, name, "inn")
	# The rooms upstairs: you book one at the door.
	for j in 4:
		_bed(k, door.origin + door.basis.x * (2.0 + j * 1.2), -door.basis.z, "room", "%s, room %d" % [name, j + 1], ROOM_PRICE)
	for j in 3:
		_picnic(k, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10.0, 0.03, 12.0 + j * 4.0)))
	for j in 5:
		if k.rng.randf() < 0.55:
			_car(k, Transform3D(Basis(Vector3.UP, PI * 0.5 if j % 2 == 0 else -PI * 0.5), Vector3(8.5, 0.03, -20.0 + j * 3.3)))
	# The hanging sign by the road.
	AdventureProps.box(k.far, Transform3D(Basis(), Vector3(1.6, 0.03, -21.0)), Vector3(0.18, 4.2, 0.18), Color(0.3, 0.2, 0.12))
	AdventureProps.box(k.far, _front(1.6, -21.0, 2.4), Vector3(1.4, 1.2, 0.08), Color(0.35, 0.12, 0.1))
	_bin(k, Vector3(14.2, 0.03, -10.0))
	_lamp(k, Vector3(13.6, 0.03, -12.0))


## A campsite: a gravel track in past the site shop to a field of tents, a fire pit with logs
## round it, a picnic bench and a toilet block.
static func _campsite(k: Kit) -> void:
	var name := str(k.site.get("name", "Campsite"))
	var gravel := Color(0.5, 0.47, 0.42)
	_pad(k, 0.6, 8.0, -6.0, 6.0, gravel, "gravel")
	AdventureProps._quad(k.far, Vector3(8.0, 0.01, 2.0), Vector3(40.0, 0.01, 2.0), Vector3(40.0, 0.01, -2.0), Vector3(8.0, 0.01, -2.0), gravel)
	var shop := _house(k, 9.0, -11.0, 7.0, 5.0, 3.0, Color(0.55, 0.42, 0.28), _roof(k), "SITE SHOP")
	_counter(k, shop.origin, -shop.basis.z, name + " shop", "camp")
	_house(k, 34.0, -16.0, 6.0, 4.0, 2.8, Color(0.7, 0.68, 0.62), Color(0.3, 0.3, 0.32), "WC", Color(0, 0, 0, 0), true)
	# The tents, in two rows either side of the track, each a pitch to sleep in.
	var tent_cols := [Color(0.85, 0.45, 0.1), Color(0.15, 0.4, 0.2), Color(0.2, 0.35, 0.7), Color(0.75, 0.15, 0.12), Color(0.85, 0.8, 0.2)]
	var n := 0
	for row: float in [-1.0, 1.0]:
		for j in 3:
			var at := Vector3(16.0 + j * 8.0, 0.0, row * 8.0)
			var face := Vector3(0, 0, -row)   # the door towards the track
			var txf := Transform3D(Basis.looking_at(-face, Vector3.UP), at)
			var col: Color = tent_cols[k.rng.randi() % tent_cols.size()]
			_tent(k, txf, col)
			n += 1
			_bed(k, at + face * 1.9, -face, "tent", "%s, pitch %d" % [name, n], PITCH_PRICE)
	# The fire pit and its logs, on the far side of the field.
	var fire := Vector3(26.0, 0.0, 16.5)
	AdventureProps.cone(k.near, Transform3D(Basis(), fire), 0.8, 0.0, 0.2, Color(0.35, 0.33, 0.3), 9, 0.7)
	AdventureProps.cone(k.near, Transform3D(Basis(), fire), 0.5, 0.0, 0.25, Color(0.1, 0.08, 0.06), 7, 0.4)
	for j in 4:
		var a := TAU * j / 4.0 + 0.3
		var p := fire + Vector3(cos(a), 0, sin(a)) * 2.0
		var lxf := Transform3D(Basis.looking_at(Vector3(-sin(a), 0, cos(a)), Vector3.UP), p)
		AdventureProps.box(k.near, lxf * Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3(0, 0, 0)), Vector3(0.4, 0.4, 1.8), Color(0.4, 0.28, 0.17))
		_seat(k, p, (fire - p).normalized(), "log", 0.4)
	var glow := OmniLight3D.new()
	glow.position = fire + Vector3(0, 0.6, 0)
	glow.omni_range = 9.0
	glow.light_energy = 0.0
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.add_to_group(Daylight.NIGHT_LIGHTS)
	glow.set_meta("night_energy", 1.5)
	k.root.add_child(glow)
	_picnic(k, Transform3D(Basis(), Vector3(12.0, 0.0, 12.0)))
	_bin(k, Vector3(8.6, 0.0, 4.0))
	# The gate posts and the site's board at the entrance.
	for sz: float in [-2.6, 2.6]:
		AdventureProps.box(k.far, Transform3D(Basis(), Vector3(8.0, 0.0, sz)), Vector3(0.25, 1.4, 0.25), Color(0.4, 0.3, 0.2))
	AdventureProps.box(k.far, _front(7.0, 4.5, 0.0), Vector3(0.12, 2.2, 0.12), Color(0.4, 0.3, 0.2))
	AdventureProps.box(k.far, _front(7.0, 4.5, 1.4), Vector3(2.2, 0.9, 0.08), SIGN_BROWN)


## A ridge tent at `xf` (its door at local +z): two sloping sides and a flysheet.
static func _tent(k: Kit, xf: Transform3D, col: Color) -> void:
	var w := 1.1
	var l := 1.5
	var h := 1.25
	var a := k.far
	var p := [xf * Vector3(-w, 0, -l), xf * Vector3(w, 0, -l), xf * Vector3(w, 0, l), xf * Vector3(-w, 0, l),
		xf * Vector3(0, h, -l), xf * Vector3(0, h, l)]
	AdventureProps._quad(a, p[3], p[5], p[4], p[0], col)
	AdventureProps._quad(a, p[1], p[4], p[5], p[2], col.darkened(0.1))
	AdventureProps._tri(a, p[0], p[4], p[1], col.darkened(0.2))
	AdventureProps._tri(a, p[2], p[5], p[3], col.darkened(0.3))
	k.boxes.append([xf * Transform3D(Basis(), Vector3(0, h * 0.35, 0)), Vector3(w * 1.6, h * 0.7, l * 2.0)])


## A fuel station's shop: a counter at the kiosk's door, a bench and a bin outside it (into
## `node`, the station AdventureProps.fuel_station built).
static func fuel_shop(_route: AdventureRoute, site: Dictionary, _xf: Transform3D, node: Node3D) -> void:
	var k := Kit.new()
	k.site = site
	k.root = node
	k.rng.seed = hash(["fuel_shop", site["s"]])
	# The kiosk's door is on its road side, 3 m along (see AdventureProps.fuel_station).
	_counter(k, Vector3(24.0 - 9.0, 0.03, 3.0), Vector3(1, 0, 0), "Fuel station shop", "fuel")
	_bench(k, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(24.0 - 8.6, 0.03, -4.5)))
	_bin(k, Vector3(24.0 - 8.5, 0.03, 6.5))
	_finish(k)
