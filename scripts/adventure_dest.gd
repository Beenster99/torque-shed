class_name AdventureDest
extends RefCounted
## Where an adventure ride ends up (Simon: "when we get to our destination we get to see the
## amazing thing we travelled for, or the big event or the exciting activity"): a set piece just
## past the finish banner, one of a few per theme (a canyon viewpoint at sunset, a glacier and its
## summit cafe, a lighthouse on the cliffs, a bike rally, a dirt track to ride laps on, a race to
## watch), and the ride lengths the magazine offers (short, ride, epic) alongside any free km.
##
## The set piece is a site of kind "dest" planned with the road (AdventureWorld.setup passes it
## to AdventureRoute.plan), DEST_AHEAD past the finish on the right, with the land flattened
## DEST_FLAT out for it; it's built from the route like any stop, so every player sees the same.
## Reaching the finish (see Adventure, adventure_arrive) brings the whole crew to it together: a
## short moment (camera pull-back, title card, group photo, see AdventureTrip), XP for everyone,
## and a framed photo of the crew there hung on the shed wall (a trinket, PHOTO_MODEL, carrying
## the photo's record as furniture field "photo"). Each player's own game also keeps the photo in
## its album (album_path, by player name), so it's hung in their own shed too when they play it.
##
## A photo's record: {key (the same on everyone's game), dest, title, names [the crew], km, date}.

## Ride lengths: about how long each takes in real time, and the km of road. Epic needs a night's
## sleep on the way (see AdventureNeeds).
const LENGTHS := {
	"short": {"name": "Short", "km": 100.0, "minutes": 90},
	"ride": {"name": "Ride", "km": 150.0, "minutes": 120},
	"epic": {"name": "Epic", "km": 220.0, "minutes": 180, "overnight": true},
}
const LENGTH_ORDER: Array[String] = ["short", "ride", "epic"]
## The set piece: this far past the finish banner, on the right, the land kept flat this far out.
const DEST_AHEAD := 110.0
const DEST_FLAT := 70.0
## The framed photo that hangs in the shed (see Trinkets: never sold, only earned).
const PHOTO_MODEL := "trinket_adventure_photo"
## Photos an album keeps (the latest).
const ALBUM_SIZE := 60

## Every destination: name, kind (the set piece), theme, what you came for (the magazine's line),
## the title card's line, the time of day it's best at (hours; -1 leaves the clock alone).
const DESTS := {
	"canyon": {"name": "Red Rock Canyon", "kind": "canyon", "theme": "desert",
		"what": "the canyon viewpoint at sunset: towers of red rock glowing as the sun goes down",
		"line": "The canyon at sunset. Worth every grain of sand.", "hours": 17.4},
	"dune_track": {"name": "Dune Dirt Track", "kind": "dirt_track", "theme": "desert",
		"what": "a sandy dirt track in the dunes, with a jump: ride as many laps as you like",
		"line": "A dirt track in the dunes, all yours. Get some laps in.", "hours": -1.0},
	"glacier": {"name": "Glacier Summit Cafe", "kind": "glacier", "theme": "alpine",
		"what": "the glacier, and hot chocolate on the terrace of the summit cafe",
		"line": "Ice as far as you can see, and the cafe's open.", "hours": 13.0},
	"pass_race": {"name": "Pass Race Weekend", "kind": "race", "theme": "alpine",
		"what": "race day at the top of the pass: the grandstand, the paddock and the bikes flat out",
		"line": "Race day at the top of the pass. Grab a seat.", "hours": -1.0},
	"lighthouse": {"name": "Gull Point Lighthouse", "kind": "lighthouse", "theme": "coastal",
		"what": "the lighthouse on the cliffs, its beam sweeping out over the sea at dusk",
		"line": "The lighthouse at the end of the land.", "hours": 18.6},
	"sea_meet": {"name": "Seafront Bike Meet", "kind": "rally", "theme": "coastal",
		"what": "the big seafront bike meet: stalls, a stage and rows of bikes by the sea",
		"line": "Bikes as far as the eye can see, and chips.", "hours": -1.0},
	"dales_rally": {"name": "Dales Bike Rally", "kind": "rally", "theme": "hills",
		"what": "the Dales bike rally: a field full of bikes, stalls, a stage and a crowd",
		"line": "The rally's in full swing.", "hours": -1.0},
	"farm_track": {"name": "Hollow Farm Scramble", "kind": "dirt_track", "theme": "hills",
		"what": "the farm's scramble track, with a jump: ride laps till the light goes",
		"line": "A scramble track in a farmer's field. Laps, anyone?", "hours": -1.0},
	"big_rally": {"name": "Big Summer Rally", "kind": "rally", "theme": "varied",
		"what": "the biggest rally of the year: stalls, a stage, a crowd and every kind of bike",
		"line": "The Big Summer Rally. Park up and wander round.", "hours": -1.0},
	"road_race": {"name": "Road Race Sunday", "kind": "race", "theme": "varied",
		"what": "a road race to watch from the grandstand",
		"line": "They're racing. Find a seat in the stand.", "hours": -1.0},
	"moto_park": {"name": "Valley Moto Park", "kind": "dirt_track", "theme": "varied",
		"what": "a dirt track with a jump to ride laps on",
		"line": "A dirt track to ride laps on. Go on then.", "hours": -1.0},
}

## The album (photos on this machine, by player name); "" keeps it in memory only.
static var album_path := "user://adventure_album.json"
static var _album_mem := {}
static var _pictures := {}


static func of(id: String) -> Dictionary:
	return DESTS.get(id, {})


static func exists(id: String) -> bool:
	return DESTS.has(id)


## The destinations of a theme.
static func for_theme(theme: String) -> Array:
	var out := []
	for id in DESTS:
		if str(DESTS[id]["theme"]) == theme:
			out.append(id)
	return out


## The destination a ride with no other says goes to: one of its theme's, picked by the seed.
static func default_for(theme: String, seed: int) -> String:
	var list := for_theme(theme)
	if list.is_empty():
		list = for_theme("varied")
	return str(list[absi(seed) % list.size()])


## The name of a destination ("" for none).
static func name_of(id: String) -> String:
	return str(DESTS.get(id, {}).get("name", ""))


## About how long `km` takes to ride, in real minutes (the presets', in between and beyond).
static func minutes_for(km: float) -> int:
	if km <= 100.0:
		return roundi(km * 0.9)
	if km <= 150.0:
		return roundi(lerpf(90.0, 120.0, (km - 100.0) / 50.0))
	return roundi(120.0 + (km - 150.0) * 60.0 / 70.0)


static func time_text(km: float) -> String:
	var m := minutes_for(km)
	if m < 60:
		return "about %d min" % m
	return "about %d h %02d min" % [m / 60, m % 60] if m % 60 != 0 else "about %d h" % (m / 60)


## The preset `km` is ("short", "ride", "epic"), or "free".
static func length_of(km: float) -> String:
	for id in LENGTH_ORDER:
		if absf(float(LENGTHS[id]["km"]) - km) < 0.5:
			return id
	return "free"


## Whether a ride of `km` needs a night's stop on the way.
static func overnight(km: float) -> bool:
	return km >= 200.0


# ---------------------------------------------------------------------------- on the road

## The site to plan with the road for `dest` on a ride of `km` (see AdventureRoute.plan).
static func site(dest: String, km: float) -> Dictionary:
	return {"kind": "dest", "s": km * 1000.0 + DEST_AHEAD, "side": 1, "flat": DEST_FLAT, "name": name_of(dest)}


## Has `world` build the set piece for `dest` at its site.
static func register(world: AdventureWorld, dest: String) -> void:
	var theme := world.route.theme
	world.site_builders["dest"] = func(st, xf, _info): return build(dest, theme, st, xf)


## Where the set piece is along the road (m).
static func dest_s(world: AdventureWorld) -> float:
	return world.route.length + DEST_AHEAD


## Where rider `slot` is parked at the destination: in pairs on the right half of the road,
## beside the set piece, facing on along the road.
static func park_xf(world: AdventureWorld, slot: int) -> Transform3D:
	var s := dest_s(world) - 14.0 + 3.4 * float(slot / 2)
	var w := world.route.width_at_s(s)
	var lat := w * 0.25 + (0.8 if slot % 2 == 1 else -0.8)
	return world.transform_at(s, lat)


## The middle of the set piece (local), for the camera to look at.
static func piece_point(world: AdventureWorld) -> Vector3:
	var s := dest_s(world)
	var xf := world.transform_at(s, world.route.width_at_s(s) * 0.5 + 30.0)
	return xf.origin + Vector3.UP * 4.0


# ---------------------------------------------------------------------------- the set pieces

## The set piece for `dest` at its site frame `xf` (on the verge: +x away from the road, -z on
## along it). The land is flat at y = -0.12 out to about DEST_FLAT and 50 m either way along.
static func build(dest: String, theme: String, st: Dictionary, xf: Transform3D) -> Node3D:
	var k := AdventureStops.Kit.new()
	k.site = st
	k.rng.seed = hash([dest, int(st.get("s", 0.0))])
	k.surf = "tarmac"
	k.root = Node3D.new()
	k.root.name = "Destination"
	k.root.transform = xf
	k.root.set_meta("dest", dest)
	var vista := AdventureProps.new_arrays()   # the big shapes far off: drawn from right across the valley
	var kind := str(of(dest).get("kind", "rally"))
	match kind:
		"canyon":
			_canyon(k, vista)
		"glacier":
			_glacier(k, vista)
		"lighthouse":
			_lighthouse(k, vista)
		"dirt_track":
			_track(k, theme, false)
		"race":
			_track(k, theme, true)
		_:
			_rally(k, theme)
	_board(k, Transform3D(Basis(), Vector3(2.5, 0.0, 9.0)), name_of(dest).to_upper())
	AdventureStops._finish(k)
	if not (vista["v"] as PackedVector3Array).is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Vista"
		mi.mesh = AdventureProps.to_mesh(vista)
		AdventureChunk._range(mi, 4000.0)
		k.root.add_child(mi)
	return k.root


## The destination's name board by the road, facing the riders coming up to it.
static func _board(k: AdventureStops.Kit, at: Transform3D, text: String) -> void:
	for sx: float in [-1.6, 1.6]:
		AdventureProps.box(k.far, at * Transform3D(Basis(), Vector3(0, -0.12, sx)), Vector3(0.12, 3.0, 0.12), Color(0.35, 0.25, 0.16))
	AdventureProps.box(k.far, at * Transform3D(Basis(), Vector3(0, 1.4, 0)), Vector3(0.1, 1.6, 4.0), Color(0.42, 0.23, 0.12))
	for face: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 44
		l.pixel_size = 0.0085
		l.outline_size = 0
		l.modulate = Color(0.98, 0.92, 0.75)
		l.width = 430.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.transform = at * Transform3D(Basis(Vector3.UP, PI * 0.5 * face), Vector3(0.07 * face, 2.2, 0))
		k.root.add_child(l)


## A tall label over the set piece.
static func _sign3d(k: AdventureStops.Kit, pos: Vector3, text: String, size := 96, col := Color(1, 1, 1)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.012
	l.outline_size = 10
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	k.root.add_child(l)


## A low-poly person standing at `p` (local), facing `yaw`, in a jacket of `col`.
static func _person(a: Dictionary, p: Vector3, yaw: float, col: Color, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var legs := Color(0.15, 0.16, 0.22) if rng.randf() < 0.7 else Color(0.3, 0.28, 0.25)
	AdventureProps.box(a, Transform3D(b, p), Vector3(0.34, 0.85, 0.22), legs)
	AdventureProps.box(a, Transform3D(b, p + Vector3(0, 0.85, 0)), Vector3(0.44, 0.62, 0.26), col)
	var skin := [Color(0.92, 0.75, 0.62), Color(0.7, 0.52, 0.38), Color(0.45, 0.3, 0.2)][rng.randi_range(0, 2)] as Color
	AdventureProps.box(a, Transform3D(b, p + Vector3(0, 1.5, 0)), Vector3(0.22, 0.26, 0.24), skin)


## A low-poly bike at `xf` (pointing along local -z): wheels, engine, tank and seat.
static func _bike(a: Dictionary, xf: Transform3D, col: Color, rider := false) -> void:
	for wz: float in [-0.7, 0.7]:
		AdventureProps.cone(a, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.33, wz)), 0.33, -0.06, 0.06,
			Color(0.06, 0.06, 0.07), 10, 0.33)
	AdventureProps.box(a, xf * Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(0.26, 0.32, 0.6), Color(0.25, 0.25, 0.27))
	AdventureProps.box(a, xf * Transform3D(Basis(), Vector3(0, 0.62, -0.18)), Vector3(0.32, 0.24, 0.55), col)
	AdventureProps.box(a, xf * Transform3D(Basis(), Vector3(0, 0.66, 0.36)), Vector3(0.26, 0.1, 0.5), Color(0.08, 0.08, 0.08))
	AdventureProps.box(a, xf * Transform3D(Basis(), Vector3(0, 0.84, -0.62)), Vector3(0.66, 0.04, 0.05), Color(0.6, 0.6, 0.62))
	if rider:
		AdventureProps.box(a, xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.72, 0.15)), Vector3(0.4, 0.62, 0.3), col.darkened(0.3))
		AdventureProps.box(a, xf * Transform3D(Basis(), Vector3(0, 1.22, -0.12)), Vector3(0.3, 0.3, 0.32), col.lightened(0.3))


const JACKETS: Array[Color] = [Color(0.75, 0.12, 0.1), Color(0.1, 0.2, 0.55), Color(0.12, 0.12, 0.13), Color(0.9, 0.6, 0.1),
	Color(0.2, 0.45, 0.25), Color(0.55, 0.55, 0.58), Color(0.85, 0.85, 0.82), Color(0.45, 0.2, 0.5)]


static func _jacket(rng: RandomNumberGenerator) -> Color:
	return JACKETS[rng.randi_range(0, JACKETS.size() - 1)]


## A canyon viewpoint: a deck with a railing and telescopes at the edge, and beyond it towers and
## mesas of banded red rock (lit up at sunset: the clock goes to evening on arrival).
static func _canyon(k: AdventureStops.Kit, vista: Dictionary) -> void:
	var wood := Color(0.45, 0.3, 0.18)
	AdventureStops._pad(k, 4.0, 24.0, -12.0, 12.0, Color(0.75, 0.6, 0.42), "tarmac")
	AdventureProps.box(k.near, Transform3D(Basis(), Vector3(26.5, -0.1, 0)), Vector3(5.0, 0.35, 16.0), wood)
	for z in range(-8, 9, 2):
		AdventureProps.box(k.near, Transform3D(Basis(), Vector3(28.9, 0.25, z)), Vector3(0.1, 1.0, 0.1), Color(0.3, 0.3, 0.32))
	AdventureProps.box(k.near, Transform3D(Basis(), Vector3(28.9, 1.2, 0)), Vector3(0.08, 0.08, 16.2), Color(0.3, 0.3, 0.32))
	k.boxes.append([Transform3D(Basis(), Vector3(28.9, 0.7, 0)), Vector3(0.2, 1.4, 16.2)])
	for z: float in [-4.0, 4.0]:
		AdventureProps.box(k.near, Transform3D(Basis(), Vector3(28.0, 0.25, z)), Vector3(0.1, 1.1, 0.1), Color(0.2, 0.22, 0.25))
		AdventureProps.box(k.near, Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(28.2, 1.35, z)), Vector3(0.18, 0.18, 0.45), Color(0.15, 0.3, 0.45))
	# Benches and a few riders' worth of shade.
	for z: float in [-7.0, 7.0]:
		AdventureProps.box(k.near, Transform3D(Basis(), Vector3(20.0, 0.0, z)), Vector3(0.5, 0.45, 2.0), wood)
	# The rock: towers and mesas in bands of red and orange, out across the canyon.
	var bands: Array[Color] = [Color(0.55, 0.22, 0.12), Color(0.68, 0.33, 0.16), Color(0.6, 0.27, 0.14), Color(0.78, 0.45, 0.24)]
	for i in 22:
		var x := k.rng.randf_range(110.0, 520.0)
		var z := k.rng.randf_range(-420.0, 420.0)
		var r := k.rng.randf_range(14.0, 46.0) * (1.0 if i % 3 != 0 else 2.2)
		var h := k.rng.randf_range(40.0, 120.0)
		var y := -40.0
		var bn := 4
		for b in bn:
			var y1 := -40.0 + (h + 40.0) * float(b + 1) / bn
			var top := r * (1.0 - 0.06 * (b + 1)) if b < bn - 1 else r * 0.82
			AdventureProps.cone(vista, Transform3D(Basis(), Vector3(x, 0, z)), r * (1.0 - 0.06 * b), y, y1, bands[(b + i) % bands.size()], 9, top)
			y = y1
		AdventureProps.cone(vista, Transform3D(Basis(), Vector3(x, 0, z)), r * 0.82, y, y + 0.5, Color(0.72, 0.4, 0.22), 9, 0.01)
	# The canyon floor's far rim, low and long.
	for i in 6:
		AdventureProps.box(vista, Transform3D(Basis(Vector3.UP, k.rng.randf_range(-0.3, 0.3)), Vector3(650.0 + 60.0 * i, -40.0, -500.0 + 200.0 * i)),
			Vector3(140.0, 70.0 + 12.0 * (i % 3), 260.0), bands[i % bands.size()].darkened(0.1))
	_sign3d(k, Vector3(26.0, 4.2, 0), "Red Rock Canyon viewpoint", 80, Color(1.0, 0.85, 0.6))


## A glacier between two rocky ridges, the snowy peaks behind, and a chalet cafe with a terrace
## of tables and parasols at the edge of the snow.
static func _glacier(k: AdventureStops.Kit, vista: Dictionary) -> void:
	AdventureStops._pad(k, 4.0, 30.0, -14.0, 14.0, Color(0.6, 0.58, 0.55), "tarmac")
	var chalet := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(22.0, -0.1, -4.0))
	AdventureStops._solid(k, chalet, Vector3(12.0, 4.0, 8.0), Color(0.5, 0.33, 0.2))
	AdventureProps.box(k.far, chalet, Vector3(12.2, 1.0, 8.2), Color(0.75, 0.74, 0.7))
	AdventureProps.gable(k.far, chalet, 12.0, 8.0, 4.0, 3.0, Color(0.92, 0.94, 0.97), Color(0.45, 0.3, 0.18))
	for sx: float in [-3.0, 0.0, 3.0]:
		AdventureProps.box(k.near, chalet * Transform3D(Basis(), Vector3(sx, 1.6, 4.05)), Vector3(1.4, 1.2, 0.06), Color(0.85, 0.75, 0.4))
	AdventureProps.box(k.near, chalet * Transform3D(Basis(), Vector3(0, 0, 4.05)), Vector3(1.2, 2.2, 0.08), Color(0.3, 0.18, 0.1))
	# The terrace: tables and parasols, a few people out in the sun.
	AdventureProps.box(k.near, Transform3D(Basis(), Vector3(14.0, -0.1, -4.0)), Vector3(7.0, 0.25, 12.0), Color(0.55, 0.4, 0.26))
	for i in 6:
		var p := Vector3(12.0 + 3.0 * float(i % 2), 0.15, -8.5 + 3.0 * float(i / 2))
		AdventureProps.cone(k.near, Transform3D(Basis(), p), 0.05, 0.0, 2.3, Color(0.8, 0.8, 0.8), 5, 0.05)
		AdventureProps.cone(k.near, Transform3D(Basis(), p + Vector3(0, 2.0, 0)), 1.3, 0.0, 0.5, [Color(0.8, 0.1, 0.1), Color(0.95, 0.95, 0.95)][i % 2] as Color, 8)
		AdventureProps.cone(k.near, Transform3D(Basis(), p), 0.45, 0.7, 0.75, Color(0.9, 0.9, 0.88), 8, 0.45)
		_person(k.near, p + Vector3(0.8, 0, 0.3), -PI * 0.5, _jacket(k.rng), k.rng)
	_sign3d(k, Vector3(22.0, 9.0, -4.0), "Summit Cafe", 72, Color(1, 0.95, 0.85))
	# The glacier: a tongue of ice coming down a long valley, crevassed, between rock ridges.
	var ice := Color(0.8, 0.88, 0.96)
	var steps := 14
	for i in steps:
		var x0 := 70.0 + 40.0 * i
		var x1 := x0 + 40.0
		var w0 := 40.0 + 6.0 * i
		var w1 := w0 + 6.0
		var y0 := -2.0 + 9.0 * i
		var y1 := y0 + 9.0
		AdventureProps._quad(vista, Vector3(x0, y0, w0), Vector3(x1, y1, w1), Vector3(x1, y1, -w1), Vector3(x0, y0, -w0), ice if i % 2 == 0 else ice.darkened(0.04))
		if i % 2 == 1:
			AdventureProps._quad(vista, Vector3(x0 + 18.0, y0 + 4.2, w0 * 0.6), Vector3(x0 + 20.0, y0 + 4.6, w0 * 0.6),
				Vector3(x0 + 20.0, y0 + 4.6, -w0 * 0.5), Vector3(x0 + 18.0, y0 + 4.2, -w0 * 0.5), Color(0.45, 0.65, 0.85))
		AdventureProps._quad(vista, Vector3(x0, y0, w0), Vector3(x0, -40.0, w0 + 2.0), Vector3(x1, -40.0, w1 + 2.0), Vector3(x1, y1, w1), ice.darkened(0.15))
		AdventureProps._quad(vista, Vector3(x1, y1, -w1), Vector3(x1, -40.0, -w1 - 2.0), Vector3(x0, -40.0, -w0 - 2.0), Vector3(x0, y0, -w0), ice.darkened(0.15))
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var c := Vector3(90.0 + 80.0 * i, 10.0 + 14.0 * i, side * (90.0 + 10.0 * i + k.rng.randf_range(0.0, 30.0)))
			AdventureProps.blob(vista, c, Vector3(60.0, 50.0 + 10.0 * i, 45.0), Color(0.42, 0.4, 0.38), i + 7)
	for i in 5:
		var px := 650.0 + 120.0 * i
		var pz := -300.0 + 150.0 * i
		var h := 260.0 + 60.0 * (i % 3)
		AdventureProps.cone(vista, Transform3D(Basis(), Vector3(px, 0, pz)), 220.0, -40.0, h * 0.55, Color(0.4, 0.39, 0.38), 7, 110.0)
		AdventureProps.cone(vista, Transform3D(Basis(), Vector3(px, 0, pz)), 110.0, h * 0.55, h, Color(0.94, 0.95, 0.98), 7)


## A lighthouse on a rocky headland with the keeper's cottage, the sea out beyond the cliffs, and
## the lamp turning (its beam shows at dusk: the clock goes to evening on arrival).
static func _lighthouse(k: AdventureStops.Kit, vista: Dictionary) -> void:
	AdventureStops._pad(k, 4.0, 20.0, -10.0, 10.0, Color(0.55, 0.55, 0.52), "tarmac")
	var base := Vector3(44.0, -0.1, 0.0)
	# The headland: rocks round the foot of the tower, cliffs dropping to the sea beyond.
	for i in 9:
		var a := TAU * i / 9.0
		AdventureProps.blob(k.far, base + Vector3(cos(a) * 9.0, 0.2, sin(a) * 9.0), Vector3(4.0, 2.2, 3.5), Color(0.42, 0.4, 0.37), i)
	for i in 10:
		AdventureProps.box(vista, Transform3D(Basis(Vector3.UP, k.rng.randf_range(-0.2, 0.2)), Vector3(72.0 + k.rng.randf_range(0.0, 6.0), -26.0, -90.0 + 20.0 * i)),
			Vector3(8.0, 26.0, 24.0), Color(0.36, 0.34, 0.3).lightened(0.05 * (i % 3)))
	# The tower, striped red and white, its gallery, lamp room and cap.
	var bands := 6
	var h := 24.0
	for b in bands:
		var r0 := lerpf(3.4, 2.3, float(b) / bands)
		var r1 := lerpf(3.4, 2.3, float(b + 1) / bands)
		AdventureProps.cone(k.far, Transform3D(Basis(), base), r0, h * b / bands, h * (b + 1) / bands,
			Color(0.75, 0.1, 0.1) if b % 2 == 0 else Color(0.95, 0.95, 0.93), 12, r1)
	k.boxes.append([Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)), Vector3(5.0, h, 5.0)])
	AdventureProps.cone(k.far, Transform3D(Basis(), base), 3.2, h, h + 0.4, Color(0.15, 0.15, 0.16), 12, 3.2)
	AdventureProps.cone(k.far, Transform3D(Basis(), base), 1.5, h + 3.2, h + 5.0, Color(0.15, 0.15, 0.16), 12)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = 2.8
	lamp.mesh = cyl
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.92, 0.6)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.85, 0.5)
	lm.emission_energy_multiplier = 3.0
	lamp.material_override = lm
	lamp.position = base + Vector3(0, h + 1.8, 0)
	k.root.add_child(lamp)
	var beam := _Beam.new()
	beam.position = base + Vector3(0, h + 1.8, 0)
	k.root.add_child(beam)
	# The keeper's cottage.
	var cot := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(30.0, -0.1, -12.0))
	AdventureStops._solid(k, cot, Vector3(9.0, 3.0, 6.0), Color(0.95, 0.95, 0.92))
	AdventureProps.gable(k.far, cot, 9.0, 6.0, 3.0, 2.2, Color(0.25, 0.27, 0.3), Color(0.95, 0.95, 0.92))
	# The sea, out past the cliffs.
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000.0, 3000.0)
	sea.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.24, 0.36)
	sm.metallic = 0.3
	sm.roughness = 0.15
	sea.material_override = sm
	sea.position = Vector3(1580.0, -14.0, 0.0)
	k.root.add_child(sea)
	_sign3d(k, base + Vector3(-6.0, 6.0, 8.0), "Gull Point Lighthouse", 72, Color(1, 0.95, 0.85))


## The lighthouse's beams, turning.
class _Beam extends Node3D:
	var _light: SpotLight3D

	func _ready() -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.9, 0.6, 0.22)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		for side: float in [1.0, -1.0]:
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.3
			c.bottom_radius = 7.0
			c.height = 90.0
			c.radial_segments = 10
			c.cap_top = false
			c.cap_bottom = false
			mi.mesh = c
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.rotation = Vector3(0, 0, -PI * 0.5 * side)
			mi.position = Vector3(45.0 * side, 0, 0)
			add_child(mi)
		_light = SpotLight3D.new()
		_light.light_color = Color(1.0, 0.9, 0.65)
		_light.light_energy = 6.0
		_light.spot_range = 200.0
		_light.spot_angle = 8.0
		_light.rotation = Vector3(0, PI * 0.5, 0)
		add_child(_light)

	func _process(delta: float) -> void:
		rotation.y += delta * 0.9
		visible = Daylight.darkness() > 0.15


## A track on the flat: dirt with hay bales and a jump to ride laps on (`race` false), or tarmac with
## kerbs, a grandstand full of people and racers going round (`race` true).
static func _track(k: AdventureStops.Kit, theme: String, race: bool) -> void:
	var c := Vector3(38.0, 0.0, 0.0)
	var rx := 24.0
	var rz := 40.0
	var w := 7.0 if not race else 9.0
	var col := Color(0.42, 0.3, 0.2) if not race else Color(0.2, 0.2, 0.21)
	if theme == "desert" and not race:
		col = Color(0.66, 0.5, 0.32)
	var n := 48
	var body := StaticBody3D.new()
	body.name = "Track"
	body.collision_layer = 1
	body.set_meta("surface", "tarmac" if race else "gravel")
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector3(cos(a0) * rx, 0, sin(a0) * rz)
		var p1 := c + Vector3(cos(a1) * rx, 0, sin(a1) * rz)
		var o0 := Vector3(cos(a0) / rx, 0, sin(a0) / rz).normalized() * w * 0.5
		var o1 := Vector3(cos(a1) / rx, 0, sin(a1) / rz).normalized() * w * 0.5
		var y := -0.07
		AdventureProps._quad(k.far, p0 - o0 + Vector3(0, y, 0), p1 - o1 + Vector3(0, y, 0), p1 + o1 + Vector3(0, y, 0), p0 + o0 + Vector3(0, y, 0), col)
		# The collision: a thin slab along each piece, its top level with the track.
		var mid := (p0 + p1) * 0.5
		var along := p1 - p0
		var basis := Basis(along.cross(Vector3.UP).normalized(), Vector3.UP, -along.normalized())
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, 0.2, along.length() + 0.3)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis, mid + Vector3(0, y - 0.1, 0))
		body.add_child(cs)
		# The edges: hay bales round a dirt track, red and white kerbs round a race track.
		if race:
			for side: float in [-1.0, 1.0]:
				var e0 := p0 + o0 * side * 1.0
				var e1 := p1 + o1 * side * 1.0
				var kc := Color(0.85, 0.1, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.95)
				var q := [e0 + Vector3(0, -0.05, 0), e1 + Vector3(0, -0.05, 0), e1 + o1.normalized() * 0.8 * side + Vector3(0, -0.05, 0),
					e0 + o0.normalized() * 0.8 * side + Vector3(0, -0.05, 0)]
				if side < 0.0:
					q.reverse()
				AdventureProps._quad(k.near, q[0], q[1], q[2], q[3], kc)
		elif i % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var bp := p0 + o0 * side * 1.25
				AdventureProps.box(k.near, Transform3D(basis, bp + Vector3(0, -0.12, 0)), Vector3(0.6, 0.5, 1.1), Color(0.85, 0.72, 0.35))
	k.root.add_child(body)
	# The start and finish: a gantry over the track on the near straight.
	var gate := c + Vector3(-rx, 0, 0)
	for sz: float in [-1.0, 1.0]:
		AdventureProps.box(k.far, Transform3D(Basis(), gate + Vector3(0, -0.1, 0)) * Transform3D(Basis(), Vector3(0, 0, sz * (w * 0.5 + 0.8))),
			Vector3(0.3, 4.6, 0.3), Color(0.25, 0.25, 0.28))
	AdventureProps.box(k.far, Transform3D(Basis(), gate + Vector3(0, 4.0, 0)), Vector3(0.3, 0.9, w + 2.0), Color(0.1, 0.1, 0.12))
	for i in 8:
		AdventureProps.box(k.near, Transform3D(Basis(), gate + Vector3(0, -0.06, -w * 0.5 + w * (i + 0.5) / 8.0)), Vector3(0.5, 0.01, w / 8.0),
			Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.05, 0.05, 0.05))
	var flag := Label3D.new()
	flag.text = "START  FINISH" if race else "DIRT TRACK"
	flag.font_size = 72
	flag.pixel_size = 0.01
	flag.outline_size = 0
	flag.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), gate + Vector3(-0.17, 4.45, 0))
	k.root.add_child(flag)
	if not race:
		# A jump on the far straight: a ramp up and a table down.
		var jx := c.x + rx
		var ramp := Transform3D(Basis(Vector3.RIGHT, 0.28), Vector3(jx, -0.5, -3.0))
		AdventureProps.box(k.near, ramp, Vector3(w - 1.0, 1.0, 5.0), col.lightened(0.08))
		k.boxes.append([ramp * Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(w - 1.0, 1.0, 5.0)])
		var down := Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(jx, -0.5, 4.0))
		AdventureProps.box(k.near, down, Vector3(w - 1.0, 1.0, 5.0), col.lightened(0.05))
		k.boxes.append([down * Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(w - 1.0, 1.0, 5.0)])
		# The marshal's hut and a few watching.
		AdventureStops._solid(k, Transform3D(Basis(), c + Vector3(-rx - 9.0, -0.1, 12.0)), Vector3(3.0, 2.4, 3.0), Color(0.3, 0.42, 0.3))
		for i in 8:
			_person(k.near, c + Vector3(-rx - 6.0 + k.rng.randf_range(-1.0, 1.0), -0.1, -14.0 + 3.5 * i), PI * 0.5, _jacket(k.rng), k.rng)
		return
	# The grandstand between the road and the track, full of people facing the track.
	var stand := c + Vector3(-rx - 9.5, -0.1, 0.0)
	for row in 5:
		AdventureStops._solid(k, Transform3D(Basis(), stand + Vector3(-1.2 * row, 0, 0)), Vector3(1.2, 0.5 + 0.5 * row, 30.0), Color(0.55, 0.56, 0.6))
		for i in 18:
			if k.rng.randf() < 0.75:
				_person(k.near, stand + Vector3(-1.2 * row, 0.5 + 0.5 * row - 0.6, -14.0 + 1.6 * i + k.rng.randf_range(-0.2, 0.2)), PI * 0.5,
					_jacket(k.rng), k.rng)
	AdventureProps.box(k.far, Transform3D(Basis(), stand + Vector3(-3.0, 4.5, 0)), Vector3(8.0, 0.2, 31.0), Color(0.75, 0.15, 0.12))
	# The racers, going round.
	var racers := _Racers.new()
	racers.setup(c, rx, rz, k.rng.randi())
	k.root.add_child(racers)


## Bikes racing round an oval at their own pace, each a little mesh.
class _Racers extends Node3D:
	var c := Vector3.ZERO
	var rx := 24.0
	var rz := 40.0
	var _bikes: Array = []    # [node, angle, rate, lane]

	func setup(centre: Vector3, rad_x: float, rad_z: float, seed_value: int) -> void:
		c = centre
		rx = rad_x
		rz = rad_z
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var cols: Array[Color] = [Color(0.85, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.1, 0.6, 0.25),
			Color(0.95, 0.95, 0.95), Color(0.5, 0.15, 0.6)]
		for i in cols.size():
			var a := AdventureProps.new_arrays()
			AdventureDest._bike(a, Transform3D(), cols[i], true)
			var mi := MeshInstance3D.new()
			mi.mesh = AdventureProps.to_mesh(a)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_bikes.append([mi, -0.25 * i, rng.randf_range(0.5, 0.6), rng.randf_range(-2.5, 2.5)])
		_place()

	func _process(delta: float) -> void:
		for b in _bikes:
			b[1] = float(b[1]) + float(b[2]) * delta
		_place()

	func _place() -> void:
		for b in _bikes:
			var a := float(b[1])
			var lane := float(b[3])
			var dir := Vector3(-sin(a) * rx, 0, cos(a) * rz).normalized()
			var out := Vector3(cos(a) / rx, 0, sin(a) / rz).normalized()
			var p := c + Vector3(cos(a) * rx, -0.07, sin(a) * rz) + out * lane
			var node: Node3D = b[0]
			node.transform = Transform3D(Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, -dir) * Basis(Vector3.FORWARD, 0.35), p)


## A bike rally in a field: rows of parked bikes, stalls under gazebos, a stage with a banner,
## a burger van and a crowd milling about.
static func _rally(k: AdventureStops.Kit, theme: String) -> void:
	var field := Color(0.36, 0.5, 0.22)
	if theme == "desert":
		field = Color(0.72, 0.6, 0.42)
	elif theme == "alpine":
		field = Color(0.42, 0.55, 0.3)
	AdventureStops._pad(k, 3.0, 62.0, -40.0, 40.0, field, "tarmac")
	# Parked bikes in rows near the road.
	for row in 3:
		for i in 14:
			var p := Vector3(8.0 + 3.2 * row, -0.1, -26.0 + 4.0 * i + (1.0 if row % 2 == 1 else 0.0))
			_bike(k.near, Transform3D(Basis(Vector3.UP, PI * 0.5 + k.rng.randf_range(-0.15, 0.15)), p), _jacket(k.rng))
	# Stalls under gazebos.
	var canopies: Array[Color] = [Color(0.85, 0.15, 0.1), Color(0.1, 0.3, 0.75), Color(0.95, 0.8, 0.15), Color(0.95, 0.95, 0.95), Color(0.15, 0.55, 0.3)]
	for i in 7:
		var g := Vector3(28.0, -0.1, -30.0 + 10.0 * i)
		for sx: float in [-1.5, 1.5]:
			for sz: float in [-1.5, 1.5]:
				AdventureProps.box(k.near, Transform3D(Basis(), g + Vector3(sx, 0, sz)), Vector3(0.06, 2.4, 0.06), Color(0.8, 0.8, 0.82))
		AdventureProps.cone(k.far, Transform3D(Basis(Vector3.UP, PI * 0.25), g + Vector3(0, 2.4, 0)), 2.3, 0.0, 1.0, canopies[i % canopies.size()], 4)
		AdventureStops._solid(k, Transform3D(Basis(), g + Vector3(-1.2, 0, 0)), Vector3(0.7, 0.9, 2.6), Color(0.45, 0.32, 0.2), true)
	# The stage, its backdrop and banner.
	var stage := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(50.0, -0.1, 0.0))
	AdventureStops._solid(k, stage, Vector3(14.0, 1.2, 7.0), Color(0.12, 0.12, 0.14))
	AdventureProps.box(k.far, stage * Transform3D(Basis(), Vector3(0, 1.2, -3.4)), Vector3(14.0, 6.0, 0.3), Color(0.1, 0.1, 0.12))
	for sx: float in [-6.8, 6.8]:
		AdventureProps.box(k.far, stage * Transform3D(Basis(), Vector3(sx, 1.2, -3.0)), Vector3(0.4, 7.0, 0.4), Color(0.3, 0.3, 0.32))
	AdventureProps.box(k.far, stage * Transform3D(Basis(), Vector3(0, 7.8, -3.0)), Vector3(14.2, 0.5, 0.5), Color(0.3, 0.3, 0.32))
	_sign3d(k, Vector3(49.5, 5.6, 0.0), "BIKE RALLY", 110, Color(1.0, 0.8, 0.2))
	for i in 3:
		_person(k.near, Vector3(49.0, 1.1, -3.0 + 3.0 * i), -PI * 0.5, _jacket(k.rng), k.rng)
	# The burger van.
	var van := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(36.0, -0.1, 32.0))
	AdventureStops._solid(k, van, Vector3(6.0, 2.8, 2.4), Color(0.92, 0.9, 0.85))
	AdventureProps.box(k.near, van * Transform3D(Basis(), Vector3(0, 1.2, 1.22)), Vector3(3.4, 1.0, 0.04), Color(0.2, 0.2, 0.22))
	# Flags along the field's edge.
	for i in 9:
		var fp := Vector3(60.0, -0.1, -36.0 + 9.0 * i)
		AdventureProps.box(k.far, Transform3D(Basis(), fp), Vector3(0.08, 6.0, 0.08), Color(0.8, 0.8, 0.8))
		AdventureProps.box(k.far, Transform3D(Basis(), fp + Vector3(0, 4.6, 0.6)), Vector3(0.03, 1.2, 1.2), canopies[i % canopies.size()])
	# The crowd: in front of the stage, round the stalls and among the bikes.
	for i in 90:
		var p: Vector3
		if i < 40:
			p = Vector3(k.rng.randf_range(36.0, 45.0), -0.1, k.rng.randf_range(-8.0, 8.0))
		elif i < 70:
			p = Vector3(k.rng.randf_range(22.0, 32.0), -0.1, k.rng.randf_range(-32.0, 32.0))
		else:
			p = Vector3(k.rng.randf_range(6.0, 18.0), -0.1, k.rng.randf_range(-30.0, 30.0))
		var yaw := -PI * 0.5 + k.rng.randf_range(-0.4, 0.4) if i < 40 else k.rng.randf_range(0.0, TAU)
		_person(k.near, p, yaw, _jacket(k.rng), k.rng)


# ---------------------------------------------------------------------------- the photo

## The photo's record for the adventure in `adv` (Shed.adventure), with the crew's names.
static func make_photo(adv: Dictionary, names: Array) -> Dictionary:
	var dest := str(adv.get("dest", ""))
	var key := "%d-%s-%d" % [int(adv.get("seed", 0)), dest, int(Time.get_unix_time_from_system())]
	return {"key": key, "dest": dest, "title": str(adv.get("title", name_of(dest))), "names": names.duplicate(),
		"km": roundi(float(adv.get("km", 0.0))), "date": Time.get_date_string_from_system()}


## A photo record as received or loaded: every field there and the right type, or {} if it isn't one.
static func sanitize_photo(v) -> Dictionary:
	if not (v is Dictionary) or str(v.get("key", "")) == "" or not exists(str(v.get("dest", ""))):
		return {}
	var names := []
	if v.get("names") is Array:
		for n in (v["names"] as Array).slice(0, 8):
			names.append(str(n).left(24))
	return {"key": str(v["key"]).left(64), "dest": str(v["dest"]), "title": str(v.get("title", "")).left(48), "names": names,
		"km": clampi(int(v.get("km", 0)), 0, 1000), "date": str(v.get("date", "")).left(16)}


## The picture of `dest` (with `riders` of the crew in front: 0 for the magazine's), painted
## pixel by pixel and kept.
static func picture(dest: String, riders := 0) -> ImageTexture:
	var key := "%s:%d" % [dest, riders]
	if _pictures.has(key):
		return _pictures[key]
	var tex := ImageTexture.create_from_image(paint(dest, riders))
	_pictures[key] = tex
	return tex


const PIC_W := 192
const PIC_H := 128


## Paints the picture of `dest` with `riders` stood in front.
static func paint(dest: String, riders := 0) -> Image:
	var img := Image.create(PIC_W, PIC_H, false, Image.FORMAT_RGB8)
	var d := of(dest)
	var kind := str(d.get("kind", "rally"))
	var theme := str(d.get("theme", "varied"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dest)
	match kind:
		"canyon":
			_sky(img, Color(0.32, 0.2, 0.45), Color(0.98, 0.58, 0.25), 0.62)
			_disc(img, 0.68, 0.5, 0.07, Color(1.0, 0.85, 0.45))
			for i in 9:
				var x := rng.randf_range(-0.05, 1.0)
				var wdt := rng.randf_range(0.06, 0.16)
				var top := rng.randf_range(0.28, 0.5)
				_rect(img, x, top, x + wdt, 0.72, Color(0.45, 0.17, 0.1).lerp(Color(0.62, 0.28, 0.14), rng.randf()))
				_rect(img, x + wdt * 0.1, top, x + wdt * 0.9, top + 0.03, Color(0.78, 0.42, 0.2))
			_rect(img, 0.0, 0.66, 1.0, 1.0, Color(0.5, 0.26, 0.13))
			_rect(img, 0.0, 0.78, 1.0, 0.8, Color(0.25, 0.22, 0.2))
			for i in 12:
				_rect(img, i / 12.0 + 0.02, 0.78, i / 12.0 + 0.03, 0.9, Color(0.25, 0.22, 0.2))
		"glacier":
			_sky(img, Color(0.25, 0.45, 0.8), Color(0.7, 0.82, 0.95), 0.5)
			for i in 5:
				var cx := 0.1 + 0.2 * i + rng.randf_range(-0.05, 0.05)
				var top := rng.randf_range(0.12, 0.3)
				_tri(img, Vector2(cx - 0.22, 0.62), Vector2(cx, top), Vector2(cx + 0.22, 0.62), Color(0.45, 0.43, 0.42))
				_tri(img, Vector2(cx - 0.07, top + 0.1), Vector2(cx, top), Vector2(cx + 0.07, top + 0.1), Color(0.95, 0.96, 0.98))
			_tri(img, Vector2(0.25, 1.0), Vector2(0.5, 0.42), Vector2(0.85, 1.0), Color(0.82, 0.9, 0.97))
			_rect(img, 0.0, 0.72, 0.3, 1.0, Color(0.5, 0.5, 0.5))
			_rect(img, 0.72, 0.5, 0.95, 0.72, Color(0.5, 0.33, 0.2))
			_tri(img, Vector2(0.69, 0.5), Vector2(0.835, 0.38), Vector2(0.98, 0.5), Color(0.93, 0.95, 0.98))
			_rect(img, 0.0, 0.72, 1.0, 1.0, Color(0.55, 0.55, 0.53))
			for i in 3:
				_tri(img, Vector2(0.6 + 0.1 * i, 0.66), Vector2(0.64 + 0.1 * i, 0.6), Vector2(0.68 + 0.1 * i, 0.66), Color(0.85, 0.15, 0.12))
		"lighthouse":
			_sky(img, Color(0.12, 0.14, 0.35), Color(0.95, 0.55, 0.5), 0.55)
			_rect(img, 0.0, 0.55, 1.0, 0.82, Color(0.1, 0.22, 0.38))
			_tri(img, Vector2(0.45, 0.82), Vector2(0.62, 0.52), Vector2(1.1, 0.82), Color(0.2, 0.3, 0.18))
			_rect(img, 0.62, 0.52, 1.0, 0.82, Color(0.2, 0.3, 0.18))
			for b in 5:
				_rect(img, 0.72, 0.2 + 0.064 * b, 0.78, 0.2 + 0.064 * (b + 1), Color(0.8, 0.1, 0.1) if b % 2 == 0 else Color(0.95, 0.95, 0.93))
			_rect(img, 0.71, 0.13, 0.79, 0.2, Color(1.0, 0.9, 0.55))
			_tri(img, Vector2(0.75, 0.165), Vector2(0.0, 0.05), Vector2(0.0, 0.3), Color(0.6, 0.55, 0.45))
			_rect(img, 0.0, 0.82, 1.0, 1.0, Color(0.28, 0.36, 0.2))
		_:
			# The rally, the dirt track and the race: a field (sand, alpine meadow, by the sea).
			var sky_top := Color(0.3, 0.55, 0.88)
			_sky(img, sky_top, Color(0.75, 0.85, 0.95), 0.55)
			var ground := {"desert": Color(0.76, 0.62, 0.42), "alpine": Color(0.4, 0.56, 0.28), "coastal": Color(0.4, 0.55, 0.3)}.get(theme, Color(0.32, 0.5, 0.2)) as Color
			if theme == "alpine":
				for i in 4:
					var cx := 0.12 + 0.27 * i
					_tri(img, Vector2(cx - 0.2, 0.56), Vector2(cx, 0.18), Vector2(cx + 0.2, 0.56), Color(0.5, 0.5, 0.52))
					_tri(img, Vector2(cx - 0.06, 0.28), Vector2(cx, 0.18), Vector2(cx + 0.06, 0.28), Color(0.95, 0.96, 0.98))
			elif theme == "coastal":
				_rect(img, 0.0, 0.48, 1.0, 0.56, Color(0.12, 0.3, 0.5))
			elif theme == "desert":
				_rect(img, 0.1, 0.38, 0.2, 0.56, Color(0.6, 0.28, 0.14))
				_rect(img, 0.7, 0.42, 0.86, 0.56, Color(0.55, 0.25, 0.12))
			else:
				for i in 6:
					_disc(img, i / 5.0, 0.56, 0.12, Color(0.22, 0.38, 0.16))
			_rect(img, 0.0, 0.55, 1.0, 1.0, ground)
			if theme == "hills":
				# Stone walls up the fellside behind, and sheep.
				for i in 3:
					_rect(img, 0.0, 0.565 + 0.03 * i, 1.0, 0.572 + 0.03 * i, Color(0.55, 0.53, 0.48))
				for i in 7:
					_disc(img, rng.randf(), rng.randf_range(0.57, 0.64), 0.012, Color(0.95, 0.95, 0.92))
			if kind == "rally":
				for i in 6:
					var x := 0.08 + 0.15 * i
					_rect(img, x, 0.5, x + 0.1, 0.62, Color(0.85, 0.85, 0.85))
					_tri(img, Vector2(x - 0.01, 0.5), Vector2(x + 0.05, 0.43), Vector2(x + 0.11, 0.5),
						[Color(0.85, 0.15, 0.1), Color(0.1, 0.3, 0.75), Color(0.95, 0.8, 0.15)][i % 3] as Color)
				for i in 120:
					_disc(img, rng.randf(), rng.randf_range(0.6, 0.78), 0.012, JACKETS[rng.randi_range(0, JACKETS.size() - 1)])
				_rect(img, 0.0, 0.3, 0.12, 0.6, Color(0.1, 0.1, 0.12))
			else:
				var race := kind == "race"
				_ellipse(img, 0.5, 0.72, 0.46, 0.14, Color(0.25, 0.25, 0.26) if race else Color(0.45, 0.32, 0.2))
				_ellipse(img, 0.5, 0.72, 0.34, 0.08, ground)
				if race:
					_rect(img, 0.05, 0.44, 0.5, 0.58, Color(0.55, 0.56, 0.6))
					for i in 60:
						_disc(img, rng.randf_range(0.06, 0.49), rng.randf_range(0.46, 0.56), 0.01, JACKETS[rng.randi_range(0, JACKETS.size() - 1)])
					for i in 4:
						var x := 0.3 + 0.12 * i
						_rect(img, x - 0.06, 0.835, x - 0.01, 0.845, Color(0.9, 0.9, 0.9))
						_disc(img, x, 0.83, 0.022, JACKETS[i])
				else:
					for i in 18:
						var a := TAU * i / 18.0
						_disc(img, 0.5 + cos(a) * 0.5, 0.72 + sin(a) * 0.17, 0.014, Color(0.88, 0.75, 0.35))
					# A rider in the air off the jump, dust behind.
					_disc(img, 0.62, 0.42, 0.03, Color(0.15, 0.15, 0.17))
					_disc(img, 0.56, 0.44, 0.025, Color(0.08, 0.08, 0.08))
					_disc(img, 0.68, 0.44, 0.025, Color(0.08, 0.08, 0.08))
					for i in 6:
						_disc(img, 0.5 - 0.03 * i, 0.5 + 0.02 * i, 0.03 + 0.008 * i, Color(0.7, 0.6, 0.45))
	_riders(img, riders, rng)
	return img


## The crew stood in a line along the bottom of the photo, helmets under their arms.
static func _riders(img: Image, n: int, rng: RandomNumberGenerator) -> void:
	n = mini(n, 8)
	for i in n:
		var x := 0.5 + (float(i) - (n - 1) * 0.5) * 0.11
		var col := JACKETS[(i * 3 + 1) % JACKETS.size()]
		_rect(img, x - 0.03, 0.8, x + 0.03, 1.0, col)
		_rect(img, x - 0.025, 0.92, x + 0.025, 1.0, Color(0.12, 0.12, 0.15))
		_disc(img, x, 0.75, 0.035, Color(0.92, 0.75, 0.62).darkened(rng.randf_range(0.0, 0.4)))
		_disc(img, x + 0.045, 0.88, 0.028, JACKETS[(i * 5 + 2) % JACKETS.size()])


static func _sky(img: Image, top: Color, horizon: Color, at: float) -> void:
	for y in PIC_H:
		var v := float(y) / PIC_H
		img.fill_rect(Rect2i(0, y, PIC_W, 1), top.lerp(horizon, clampf(v / at, 0.0, 1.0)))


static func _rect(img: Image, x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	var a := Vector2i(clampi(roundi(x0 * PIC_W), 0, PIC_W), clampi(roundi(y0 * PIC_H), 0, PIC_H))
	var b := Vector2i(clampi(roundi(x1 * PIC_W), 0, PIC_W), clampi(roundi(y1 * PIC_H), 0, PIC_H))
	if b.x > a.x and b.y > a.y:
		img.fill_rect(Rect2i(a, b - a), col)


## A disc of radius `r` (in the picture's height) at (x, y) (fractions of the picture).
static func _disc(img: Image, x: float, y: float, r: float, col: Color) -> void:
	_ellipse(img, x, y, r * PIC_H / PIC_W, r, col)


static func _ellipse(img: Image, x: float, y: float, rx: float, ry: float, col: Color) -> void:
	var cx := x * PIC_W
	var cy := y * PIC_H
	var ax := maxf(rx * PIC_W, 0.5)
	var ay := maxf(ry * PIC_H, 0.5)
	for py in range(maxi(0, floori(cy - ay)), mini(PIC_H, ceili(cy + ay) + 1)):
		var dy := (py + 0.5 - cy) / ay
		if absf(dy) > 1.0:
			continue
		var half := ax * sqrt(1.0 - dy * dy)
		var x0 := clampi(roundi(cx - half), 0, PIC_W)
		var x1 := clampi(roundi(cx + half), 0, PIC_W)
		if x1 > x0:
			img.fill_rect(Rect2i(x0, py, x1 - x0, 1), col)


static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var pa := a * Vector2(PIC_W, PIC_H)
	var pb := b * Vector2(PIC_W, PIC_H)
	var pc := c * Vector2(PIC_W, PIC_H)
	var poly := PackedVector2Array([pa, pb, pc])
	var y0 := maxi(0, floori(minf(pa.y, minf(pb.y, pc.y))))
	var y1 := mini(PIC_H - 1, ceili(maxf(pa.y, maxf(pb.y, pc.y))))
	var x0 := maxi(0, floori(minf(pa.x, minf(pb.x, pc.x))))
	var x1 := mini(PIC_W - 1, ceili(maxf(pa.x, maxf(pb.x, pc.x))))
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			if Geometry2D.is_point_in_polygon(Vector2(px + 0.5, py + 0.5), poly):
				img.set_pixel(px, py, col)


## The framed photo on the shed wall (see Trinkets: `parent` is its EquipmentView, +Z out from
## the wall): a dark wooden frame, the picture of the crew there, and a brass plate underneath.
static func build_photo(parent: Node3D, photo: Dictionary) -> void:
	var size: Vector3 = Trinkets.MODELS[PHOTO_MODEL]["size"]
	var frame := Trinkets._mat(Color(0.18, 0.12, 0.08), 0.0, 0.45)
	Trinkets._box(parent, Vector3(0.0, 0.0, 0.015), Vector3(size.x, size.y, 0.03), frame)
	var mount := Trinkets._mat(Color(0.93, 0.91, 0.86), 0.0, 0.8)
	Trinkets._box(parent, Vector3(0.0, 0.0, 0.031), Vector3(size.x - 0.06, size.y - 0.06, 0.002), mount)
	var pic := MeshInstance3D.new()
	pic.name = "Picture"
	var q := QuadMesh.new()
	q.size = Vector2(size.x - 0.12, (size.x - 0.12) * float(PIC_H) / PIC_W)
	pic.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = picture(str(photo.get("dest", "big_rally")), maxi(1, (photo.get("names", []) as Array).size()))
	pm.roughness = 0.25
	pic.material_override = pm
	pic.position = Vector3(0.0, 0.035, 0.034)
	parent.add_child(pic)
	var plate := Trinkets._mat(Color(0.72, 0.58, 0.28), 0.8, 0.3)
	Trinkets._box(parent, Vector3(0.0, -size.y * 0.5 + 0.06, 0.034), Vector3(size.x * 0.6, 0.06, 0.004), plate)
	var l := Label3D.new()
	l.name = "Caption"
	l.text = caption(photo)
	l.font_size = 22
	l.pixel_size = 0.0011
	l.outline_size = 0
	l.modulate = Color(0.12, 0.09, 0.05)
	l.width = 380.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector3(0.0, -size.y * 0.5 + 0.06, 0.037)
	parent.add_child(l)


## The plate under the photo: where, how far, when, and who.
static func caption(photo: Dictionary) -> String:
	var names: Array = photo.get("names", [])
	return "%s  ·  %d km  ·  %s\n%s" % [name_of(str(photo.get("dest", ""))), int(photo.get("km", 0)), str(photo.get("date", "")),
		", ".join(names.map(func(n): return str(n)))]


## Furniture showing the photo `key` ({} when none hangs in the shed).
static func photo_on_wall(key: String) -> Dictionary:
	for id in Shed.furniture:
		var f: Dictionary = Shed.furniture[id]
		if str(f.get("model", "")) == PHOTO_MODEL and str((f.get("photo", {}) as Dictionary).get("key", "")) == key:
			return f
	return {}


## Spots on the shed's front wall, high up either side of the roller door, the photos go in turn.
static func wall_spots() -> Array:
	var out := []
	var z := Workshop.CENTER.z + Workshop.HALF.y - 0.025
	for y: float in [2.75, 2.15, 3.35]:
		for x: float in [3.0, 3.75, 4.5, 5.25, 6.0, -3.0, -3.75, -4.5, -5.25, -6.0]:
			if y < 2.5 and x < 0.0:
				continue   # the whiteboard
			out.append(Transform3D(Basis(Vector3.UP, PI), Vector3(Workshop.CENTER.x + x, y, z)))
	return out


## Where the next photo hangs: the first wall spot clear of anything else on the wall, else
## outside by the roller door with the deliveries (null if there's no room there either).
static func free_wall_xf() -> Variant:
	for xf: Transform3D in wall_spots():
		var clear := true
		for id in Shed.furniture:
			var o: Vector3 = (Shed.furniture[id]["xf"] as Transform3D).origin
			if o.distance_to(xf.origin) < 0.62:
				clear = false
				break
		if clear:
			return xf
	return Shed.free_delivery_xf(Trinkets.MODELS[PHOTO_MODEL]["size"])


## Host: hangs `photo` in the shed (unless it's there already). Returns the furniture id, or 0.
static func hang(photo: Dictionary) -> int:
	photo = sanitize_photo(photo)
	if photo.is_empty() or not photo_on_wall(str(photo["key"])).is_empty():
		return 0
	var xf = free_wall_xf()
	if xf == null:
		return 0
	var fid: int = Shed._new_furniture("trinket", xf, PHOTO_MODEL)
	Shed.furniture[fid]["photo"] = photo
	return fid


# ---------------------------------------------------------------------------- the album

static func _read_album() -> Dictionary:
	if album_path == "":
		return _album_mem.duplicate(true)
	if not FileAccess.file_exists(album_path):
		return {}
	var f := FileAccess.open(album_path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


## This machine's photos for `player`, oldest first.
static func album_of(player: String) -> Array:
	var out := []
	var list = _read_album().get(player, [])
	if list is Array:
		for p in list:
			var clean := sanitize_photo(p)
			if not clean.is_empty():
				out.append(clean)
	return out


## Keeps `photo` in `player`'s album on this machine (once).
static func album_add(player: String, photo: Dictionary) -> void:
	photo = sanitize_photo(photo)
	if photo.is_empty():
		return
	var all := _read_album()
	var list: Array = all.get(player, []) if all.get(player) is Array else []
	for p in list:
		if p is Dictionary and str(p.get("key", "")) == str(photo["key"]):
			return
	list.append(photo)
	all[player] = list.slice(-ALBUM_SIZE)
	if album_path == "":
		_album_mem = all
		return
	var f := FileAccess.open(album_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "\t"))
		f.close()


## Playing your own shed (solo or hosting): the photos in your album that aren't on its walls yet
## go up (each through the host, adventure_photo).
static func hang_album(player: String) -> int:
	var n := 0
	for p in album_of(player):
		if photo_on_wall(str(p["key"])).is_empty():
			Shed.request({"a": "adventure_photo", "photo": p})
			n += 1
	return n
