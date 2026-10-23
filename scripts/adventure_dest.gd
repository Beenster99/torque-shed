class_name AdventureDest
extends RefCounted
## Where an adventure ride ends up: the last pin the crew put on the route planner's map (a real
## place: a village, a lake, a pass). The road runs on a little past it (RoutePlanner.RUN_OUT), and
## the crew are parked together just past the finish banner, looking on along the road.
##
## Reaching the finish (see Adventure, adventure_arrive) brings the whole crew there together: a
## short moment (camera pull-back, title card, group photo, see AdventureTrip), XP for everyone,
## and a framed photo of the crew there hung on the shed wall (a trinket, PHOTO_MODEL, carrying
## the photo's record as furniture field "photo"). Each player's own game also keeps the photo in
## its album (album_path, by player name), so it's hung in their own shed too when they play it.
##
## A photo's record: {key (the same on everyone's game), dest (the place's name), theme (the look
## of the land, see AdventureTheme: the picture is painted from it), title, names [the crew], km,
## date}.

## The crew are parked this far past the finish banner.
const DEST_AHEAD := 30.0
## The framed photo that hangs in the shed (see Trinkets: never sold, only earned).
const PHOTO_MODEL := "trinket_adventure_photo"
## Photos an album keeps (the latest).
const ALBUM_SIZE := 60
## Photos from before rides were planned on real maps named their made-up destination by an id: its
## name and the look of its land, so they still hang with the right caption and picture.
const LEGACY := {
	"canyon": ["Red Rock Canyon", "desert"], "dune_track": ["Dune Dirt Track", "desert"],
	"glacier": ["Glacier Summit Cafe", "alpine"], "pass_race": ["Pass Race Weekend", "alpine"],
	"lighthouse": ["Gull Point Lighthouse", "coastal"], "sea_meet": ["Seafront Bike Meet", "coastal"],
	"dales_rally": ["Dales Bike Rally", "hills"], "farm_track": ["Hollow Farm Scramble", "hills"],
	"big_rally": ["Big Summer Rally", "varied"], "road_race": ["Road Race Sunday", "varied"],
	"moto_park": ["Valley Moto Park", "varied"],
}

## The album (photos on this machine, by player name); "" keeps it in memory only.
static var album_path := "user://adventure_album.json"
static var _album_mem := {}
static var _pictures := {}


## The name of a destination: the place itself (or an old photo's made-up one).
static func name_of(dest: String) -> String:
	return str(LEGACY[dest][0]) if LEGACY.has(dest) else dest


## The look of the land in a photo of `photo` (its theme, or an old photo's destination's).
static func theme_of(photo: Dictionary) -> String:
	var theme := str(photo.get("theme", ""))
	if AdventureTheme.has(theme):
		return theme
	var dest := str(photo.get("dest", ""))
	return str(LEGACY[dest][1]) if LEGACY.has(dest) else "varied"


## About how long `km` takes to ride, in real minutes.
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


## Whether a ride of `km` needs a night's stop on the way.
static func overnight(km: float) -> bool:
	return km >= 200.0


# ---------------------------------------------------------------------------- on the road

## Where the crew are parked along the road (m): just past the finish.
static func dest_s(world: AdventureWorld) -> float:
	return minf(world.route.length + DEST_AHEAD, world.route.total - 40.0)


## Where rider `slot` is parked at the destination: in pairs on the right half of the road,
## facing on along it.
static func park_xf(world: AdventureWorld, slot: int) -> Transform3D:
	var s := dest_s(world) - 14.0 + 3.4 * float(slot / 2)
	var w := world.route.width_at_s(s)
	var lat := w * 0.25 + (0.8 if slot % 2 == 1 else -0.8)
	return world.transform_at(s, lat)


## What the camera takes in behind the crew (local): the road on ahead and the land beside it.
static func piece_point(world: AdventureWorld) -> Vector3:
	var s := minf(dest_s(world) + 60.0, world.route.total)
	var xf := world.transform_at(s, world.route.width_at_s(s) * 0.5 + 30.0)
	return xf.origin + Vector3.UP * 4.0


# ---------------------------------------------------------------------------- the photo

## The photo's record for the adventure in `adv` (Shed.adventure), with the crew's names.
static func make_photo(adv: Dictionary, names: Array) -> Dictionary:
	var dest := str(adv.get("dest", ""))
	var key := "%d-%s-%d" % [int(adv.get("seed", 0)), dest.left(24), int(Time.get_unix_time_from_system())]
	return {"key": key, "dest": dest, "theme": str(adv.get("theme", "varied")), "title": str(adv.get("title", dest)),
		"names": names.duplicate(), "km": roundi(float(adv.get("km", 0.0))), "date": Time.get_date_string_from_system()}


## A photo record as received or loaded: every field there and the right type, or {} if it isn't one.
static func sanitize_photo(v) -> Dictionary:
	if not (v is Dictionary) or str(v.get("key", "")) == "" or str(v.get("dest", "")) == "":
		return {}
	var names := []
	if v.get("names") is Array:
		for n in (v["names"] as Array).slice(0, 8):
			names.append(str(n).left(24))
	return {"key": str(v["key"]).left(64), "dest": str(v["dest"]).left(48), "theme": theme_of(v), "title": str(v.get("title", "")).left(48),
		"names": names, "km": clampi(int(v.get("km", 0)), 0, 1000), "date": str(v.get("date", "")).left(16)}


## The picture of the crew out in land of `theme` (`riders` of them stood in front), painted pixel
## by pixel and kept.
static func picture(theme: String, riders := 0) -> ImageTexture:
	var key := "%s:%d" % [theme, riders]
	if _pictures.has(key):
		return _pictures[key]
	var tex := ImageTexture.create_from_image(paint(theme, riders))
	_pictures[key] = tex
	return tex


const PIC_W := 192
const PIC_H := 128
const JACKETS: Array[Color] = [Color(0.75, 0.12, 0.1), Color(0.1, 0.2, 0.55), Color(0.12, 0.12, 0.13), Color(0.9, 0.6, 0.1),
	Color(0.2, 0.45, 0.25), Color(0.55, 0.55, 0.58), Color(0.85, 0.85, 0.82), Color(0.45, 0.2, 0.5)]


## Paints the land of `theme` (the road running off into it) with `riders` stood in front.
static func paint(theme: String, riders := 0) -> Image:
	var img := Image.create(PIC_W, PIC_H, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme)
	_sky(img, Color(0.3, 0.55, 0.88), Color(0.75, 0.85, 0.95), 0.55)
	var ground := {"desert": Color(0.76, 0.62, 0.42), "alpine": Color(0.4, 0.56, 0.28), "coastal": Color(0.4, 0.55, 0.3)}.get(theme, Color(0.32, 0.5, 0.2)) as Color
	if theme == "alpine":
		for i in 4:
			var cx := 0.12 + 0.27 * i
			_tri(img, Vector2(cx - 0.2, 0.56), Vector2(cx, 0.18), Vector2(cx + 0.2, 0.56), Color(0.5, 0.5, 0.52))
			_tri(img, Vector2(cx - 0.06, 0.28), Vector2(cx, 0.18), Vector2(cx + 0.06, 0.28), Color(0.95, 0.96, 0.98))
	elif theme == "coastal":
		_rect(img, 0.0, 0.48, 1.0, 0.56, Color(0.12, 0.3, 0.5))
		_tri(img, Vector2(0.55, 0.56), Vector2(0.78, 0.36), Vector2(1.1, 0.56), Color(0.25, 0.38, 0.22))
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
	# The road running away into it.
	_tri(img, Vector2(0.2, 1.0), Vector2(0.5, 0.56), Vector2(0.8, 1.0), Color(0.24, 0.24, 0.26))
	_tri(img, Vector2(0.49, 1.0), Vector2(0.5, 0.56), Vector2(0.51, 1.0), Color(0.9, 0.9, 0.85))
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
	pm.albedo_texture = picture(theme_of(photo), maxi(1, (photo.get("names", []) as Array).size()))
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


## Forgets the photo `key` from every album on this machine (so it isn't hung again). Whether
## it was in one.
static func album_forget(key: String) -> bool:
	var all := _read_album()
	var found := false
	for player in all.keys():
		if not (all[player] is Array):
			continue
		var kept: Array = (all[player] as Array).filter(func(p): return not (p is Dictionary and str(p.get("key", "")) == key))
		if kept.size() != (all[player] as Array).size():
			found = true
			all[player] = kept
	if not found:
		return false
	if album_path == "":
		_album_mem = all
		return true
	var f := FileAccess.open(album_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "\t"))
		f.close()
	return true


# ---------------------------------------------------------------------------- taking one down

## Simon: "We need to be able to delete wall mounted diaries." An adventure's photo on the shed
## wall is taken down the way the shed scraps anything (hold the scrap key, then press it again to
## say yes): the photo goes from the shed for the whole crew (action diary_delete {furniture},
## through the host), the host's game forgets it from its album so it isn't hung again, and the
## Adventure Diary of that ride is deleted on the machine of whoever took it down. Everyone else
## keeps their own copy of the diary (it's on their own computer), still in the magazine.
##
## Who may: the host, or anyone named on the photo (they were on that ride). Playing alone, you.

## Whether `peer` is one of the riders named on photo furniture `f`.
static func rode_on(peer: int, f: Dictionary) -> bool:
	var who := str(Shed.crew.get(peer, {}).get("name", ""))
	var names: Array = (f.get("photo", {}) as Dictionary).get("names", [])
	return who != "" and names.map(func(n): return str(n)).has(who)


## Why `peer` can't take down the photo the action names, or "" (`online`: in co-op, where only
## the host and that ride's riders may).
static func delete_check(peer: int, action: Dictionary, online := Net.is_online()) -> String:
	var f: Dictionary = Shed.furniture.get(int(action.get("furniture", 0)), {})
	if f.is_empty():
		return "That has gone."
	if str(f.get("model", "")) != PHOTO_MODEL:
		return "That's not an adventure's photo."
	if Staff.is_staff_peer(peer):
		return "The staff leave the crew's photos alone."
	if online and peer != 1 and not rode_on(peer, f):
		return "Only the host or someone who was on that ride can take it down."
	if int(f.get("mover", 0)) != 0 and int(f["mover"]) != peer:
		return "Someone else is moving that."
	var key := str((f.get("photo", {}) as Dictionary).get("key", ""))
	if Adventure.active() and str((Shed.adventure.get("photo", {}) as Dictionary).get("key", "")) == key:
		return "Not while that adventure is still on: ride home first."
	return ""


## Host: takes the photo down (see delete_check) and forgets it from this machine's album. What
## to tell the crew: {key, mine (for who took it down), others (for everyone else)}.
static func take_down(peer: int, action: Dictionary) -> Dictionary:
	var id := int(action["furniture"])
	var photo: Dictionary = Shed.furniture[id].get("photo", {})
	var key := str(photo.get("key", ""))
	Shed.furniture.erase(id)
	album_forget(key)
	var where := name_of(str(photo.get("dest", "")))
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	return {"key": key,
		"mine": "Took down the photo of %s and deleted its Adventure Diary." % where,
		"others": "%s took down the photo of %s. Your own copy of its diary is still in the magazine, if you have one." % [who, where]}


## On the machine of whoever took the photo `key` down: its diary deleted, and the album forgets
## it. Whether there was a diary to delete.
static func forget_here(key: String) -> bool:
	album_forget(key)
	var id := AdventureDiary.find_by_photo(key)
	return id != "" and AdventureDiary.delete(id)
