class_name Dirt
extends RefCounted
## Road dirt on a part, region by region (the way Farming Simulator lets muck build up on a
## machine): each part's dirt is a little grid over its own bounds on the bike, NX along it
## (front to back) by NY up it (bottom to top), for each of the six ways a surface can face (+x,
## -x, +y, -y, +z, -z in the bike model's axes: x across, y up, -z forward). That's CELLS levels,
## 0 (clean) .. 1 (caked), kept on the item as "grime" (a byte a cell) alongside its overall "dirt"
## (always their mean, so everything that only knows a part's dirt keeps working).
##
## Riding puts it on where it really goes: the front tyre throws muck up and back over the fork,
## the front of the engine and the frame's down tubes (a front mudguard catches most of it on its
## underside), the rear tyre plasters the underside of the tail and the back of the engine, road
## spray coats the lower sides and the bottom of everything, a little dust settles on top, and at
## speed the front (headlight, fairing nose and screen, the tops of the fork legs) collects dead
## flies. Distance builds it up, faster off the tarmac, faster in the wet, and it builds slower the
## more caked a patch already is.
##
## A part whose overall dirt was changed by something that only knows the overall figure (the
## parts washer, the brush, a contract's mucky bike, a save from before regions) has its regions
## brought into line with it when they're read: scaled down evenly, or the extra laid on in the
## part's usual pattern. A part with no regions yet gets that pattern too: a delivered bike is
## dusty on top and muddy underneath, not evenly tinted.

const NX := 6
const NY := 4
const DIRS := 6
const CELLS := NX * NY * DIRS
const CLEAN := 0.04          # a patch this clean or cleaner counts as clean
const FLY_RATE := 0.12       # dead flies on the front a fly-km (see main.gd's ride stats)
## Where each slot's part spans on a bike, round its BikeBuild.PART_SPOT: [length as a share of
## the wheelbase, height in m]. Anything not listed is a small part (SMALL).
const SPAN := {
	"frame": [0.95, 0.6], "fork": [0.2, 0.75], "shock": [0.1, 0.3], "front_wheel": [0.3, 0.6], "rear_wheel": [0.3, 0.62],
	"front_tyre": [0.3, 0.6], "rear_tyre": [0.3, 0.62], "front_disc": [0.2, 0.4], "rear_disc": [0.18, 0.35], "tank": [0.3, 0.2],
	"saddle": [0.35, 0.12], "handlebars": [0.12, 0.12], "engine": [0.35, 0.4], "head": [0.2, 0.15], "cooling": [0.08, 0.35],
	"gearbox": [0.2, 0.2], "exhaust": [0.8, 0.35], "final_drive": [0.4, 0.15], "chain": [0.45, 0.15], "tail": [0.35, 0.3],
	"fairing": [0.35, 0.5], "front_mudguard": [0.3, 0.12], "side_panels": [0.2, 0.2], "swingarm": [0.45, 0.12],
	"panniers": [0.35, 0.35], "top_box": [0.25, 0.25], "guards": [0.3, 0.2], "number_boards": [0.3, 0.25],
}
const SMALL := [0.15, 0.15]
## Parts that spin (or run round): the muck goes on all over them, not on one side.
const ROTATING: Array[String] = ["front_wheel", "rear_wheel", "front_tyre", "rear_tyre", "front_disc", "rear_disc", "chain"]
## How much more the underside of a guard catches than the parts round it: a mudguard's job.
const GUARD_UNDERSIDE := {"front_mudguard": 3.0, "tail": 2.4, "guards": 1.5, "swingarm": 1.4, "final_drive": 1.3}
## The parts out in front that collect dead flies at speed, and how many land on each.
const FLY_SLOTS := {"headlight": 1.0, "fairing": 1.0, "fog_lights": 0.9, "mirrors": 0.6, "front_mudguard": 0.7, "fork": 0.55,
	"indicators": 0.5, "number_boards": 0.6, "handlebars": 0.35, "dashboard": 0.35, "tank": 0.3, "front_master": 0.3,
	"horn": 0.5, "cooling": 0.45, "steering_damper": 0.3}

static var _mud_cache := {}
static var _rest_cache := {}
static var _fly_cache := {}


## The cell index for facing `d` (0..5: +x, -x, +y, -y, +z, -z), `ix` along (0 front) and `iy` up.
static func index(d: int, ix: int, iy: int) -> int:
	return (d * NY + iy) * NX + ix


## The facing a direction (model space) is mostly along.
static func facing_of(n: Vector3) -> int:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return 0 if n.x > 0.0 else 1
	if a.y >= a.z:
		return 2 if n.y > 0.0 else 3
	return 4 if n.z > 0.0 else 5


## The cell (without its facing) a point in a part's bounds `box` (model space) falls in: ix + iy * NX.
static func spot_in(box: AABB, p: Vector3) -> int:
	var rel := (p - box.position) / Vector3(maxf(box.size.x, 1e-4), maxf(box.size.y, 1e-4), maxf(box.size.z, 1e-4))
	var ix := clampi(floori(rel.z * NX), 0, NX - 1)
	var iy := clampi(floori(rel.y * NY), 0, NY - 1)
	return ix + iy * NX


## A part's dirt by region as it is now (see the top): its stored regions brought into line with
## its overall dirt, or its usual pattern. `it` is an item, or a condition (Shed.condition_of).
static func cells(it: Dictionary, slot := "") -> PackedFloat32Array:
	var dirt := clampf(float(it.get("dirt", 0.0)), 0.0, 1.0)
	var out := PackedFloat32Array()
	var g = it.get("grime")
	if g is PackedByteArray and (g as PackedByteArray).size() == CELLS:
		out.resize(CELLS)
		var sum := 0.0
		for i in CELLS:
			out[i] = (g as PackedByteArray)[i] / 255.0
			sum += out[i]
		var mean := sum / CELLS
		if absf(mean - dirt) <= 0.006:
			return out
		if dirt < mean:
			# Cleaned by something that only knows the overall dirt: evenly, all over.
			var k := dirt / maxf(mean, 1e-5)
			for i in CELLS:
				out[i] *= k
			return out
		return _lay_on(out, rest_pattern(_slot_of(it, slot)), dirt)
	var none := PackedFloat32Array()
	none.resize(CELLS)
	if dirt <= 0.0:
		return none
	return _lay_on(none, rest_pattern(_slot_of(it, slot)), dirt)


## Keeps `levels` on an item: its regions, and its overall dirt as their mean.
static func store(it: Dictionary, levels: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(CELLS)
	var sum := 0
	for i in CELLS:
		var b := clampi(roundi(levels[i] * 255.0), 0, 255)
		bytes[i] = b
		sum += b
	it["grime"] = bytes
	it["dirt"] = float(sum) / (255.0 * CELLS)


## Wipes a part's regions clean.
static func clear(it: Dictionary) -> void:
	var none := PackedFloat32Array()
	none.resize(CELLS)
	store(it, none)


## Whether every region of a part is clean.
static func is_clean(levels: PackedFloat32Array) -> bool:
	for v in levels:
		if v > CLEAN:
			return false
	return true


## Adds `amount` (as a mean over the part) in `pattern` to `levels`, finding how much of the
## pattern it takes so the mean comes out at `target` (a caked patch can't take more).
static func _lay_on(levels: PackedFloat32Array, pattern: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var lo := 0.0
	var hi := 4.0
	var out := levels
	for step in 16:
		var s := (lo + hi) * 0.5
		var sum := 0.0
		for i in CELLS:
			sum += minf(1.0, levels[i] + s * pattern[i])
		if sum / CELLS < target:
			lo = s
		else:
			hi = s
	out = levels.duplicate()
	for i in CELLS:
		out[i] = minf(1.0, levels[i] + hi * pattern[i])
	return out


static func _slot_of(it: Dictionary, slot: String) -> String:
	if slot != "":
		return slot
	var part := str(it.get("part", ""))
	if part == "":
		return ""
	var fits: Array = PartsDB.slots_for_kind(PartsDB.kind_of(part))
	return str(fits[0]) if not fits.is_empty() else ""


## Where a cell sits on the bike: [share of the wheelbase back from the front axle, height in m].
static func where(slot: String, ix: int, iy: int) -> Vector2:
	var spot: Array = BikeBuild.PART_SPOT.get(slot, [0.5, 0.5])
	var span: Array = SPAN.get(slot, SMALL)
	var u := (ix + 0.5) / NX
	var v := (iy + 0.5) / NY
	return Vector2(float(spot[0]) + (u - 0.5) * float(span[0]), float(spot[1]) + (v - 0.5) * float(span[1]))


## How much of the road muck a cell catches on a ride, relative to the rest of the bike: the
## front tyre's spray, the rear tyre's, what it kicks forward, the road spray along the lower
## sides and underneath, and a little everywhere. `spray` is how much more of the front tyre's
## spray gets past the front mudguard (Shed.front_spray: 1 behind a full guard).
static func _muck(slot: String, d: int, z: float, y: float, spray: float) -> float:
	if ROTATING.has(slot):
		return 1.0
	# Facing: +x, -x, +y, -y, +z (back), -z (front).
	var f_front: float = [0.45, 0.45, 0.1, 0.8, 0.15, 1.0][d]
	var f_rear: float = [0.4, 0.4, 0.05, 1.0, 0.2, 0.8][d]
	var f_kick: float = [0.3, 0.3, 0.05, 0.4, 0.9, 0.1][d]
	var f_low: float = [1.0, 1.0, 0.1, 1.0, 0.4, 0.6][d]
	var front := exp(-pow((z - 0.25) / 0.25, 2.0)) * clampf(1.1 - y / 0.8, 0.0, 1.0)
	var rear := exp(-pow((z - 1.08) / 0.25, 2.0)) * clampf(1.2 - y, 0.0, 1.0)
	var kick := exp(-pow((z - 0.72) / 0.2, 2.0)) * clampf(1.0 - y / 0.7, 0.0, 1.0)
	var low := pow(clampf(1.0 - y / 0.75, 0.0, 1.0), 1.5)
	var r := 0.15 + 1.8 * front * f_front * spray + 0.9 * rear * f_rear + 0.5 * kick * f_kick + 0.8 * low * f_low
	if d == 3 and GUARD_UNDERSIDE.has(slot):
		r *= float(GUARD_UNDERSIDE[slot])
	return r


## A ride's muck pattern for a part, scaled so the part as a whole takes its usual share
## (Shed.DIRT_EXPOSURE, more in the front tyre's spray without a guard: `exposure` has that).
static func mud_pattern(slot: String, spray: float, exposure: float) -> PackedFloat32Array:
	var key := "%s|%.2f|%.2f" % [slot, spray, exposure]
	if _mud_cache.has(key):
		return _mud_cache[key]
	var out := PackedFloat32Array()
	out.resize(CELLS)
	var sum := 0.0
	for d in DIRS:
		for iy in NY:
			for ix in NX:
				var at := where(slot, ix, iy)
				var r := _muck(slot, d, at.x, at.y, spray)
				out[index(d, ix, iy)] = r
				sum += r
	var k := exposure * CELLS / maxf(sum, 1e-5)
	for i in CELLS:
		out[i] *= k
	_mud_cache[key] = out
	return out


## How dirt sits on a part that's been stood about after its last ride (a delivered bike, a part
## from a scrapyard): its ride pattern, under dust that's settled mostly on top. Mean 1.
static func rest_pattern(slot: String) -> PackedFloat32Array:
	if _rest_cache.has(slot):
		return _rest_cache[slot]
	var mud := mud_pattern(slot, 1.4, 1.0)
	var out := PackedFloat32Array()
	out.resize(CELLS)
	var dust: Array = [1.0, 1.0, 2.4, 0.4, 1.0, 1.0]
	var sum := 0.0
	for d in DIRS:
		for iy in NY:
			for ix in NX:
				var i := index(d, ix, iy)
				out[i] = 0.5 * mud[i] + 0.5 * float(dust[d])
				sum += out[i]
	for i in CELLS:
		out[i] *= CELLS / maxf(sum, 1e-5)
	_rest_cache[slot] = out
	return out


## Where dead flies land on a part at speed: the forward faces of the parts out in front, high up.
static func fly_pattern(slot: String) -> PackedFloat32Array:
	if _fly_cache.has(slot):
		return _fly_cache[slot]
	var out := PackedFloat32Array()
	out.resize(CELLS)
	var gain := float(FLY_SLOTS.get(slot, 0.0))
	if gain > 0.0:
		for iy in NY:
			for ix in NX:
				var at := where(slot, ix, iy)
				var w := gain * smoothstep(0.4, 0.75, at.y) * (1.0 - smoothstep(0.15, 0.45, at.x))
				out[index(5, ix, iy)] = w
				# A few smeared round the sides of the nose.
				out[index(0, ix, iy)] = w * 0.12
				out[index(1, ix, iy)] = w * 0.12
	_fly_cache[slot] = out
	return out


## A ride's dirt on one part: `mud` road-muck km (main.gd: distance times how mucky the ground,
## the weather and the speed made it), `flies` fly-km (distance at speed). `exposure` and
## `spray` as for mud_pattern; `protect` is the part's protective coat (it stops 60% sticking).
static func accrue(it: Dictionary, slot: String, mud: float, flies: float, exposure: float, spray: float, protect := 0.0) -> void:
	if mud <= 0.0 and flies <= 0.0:
		return
	var levels := cells(it, slot)
	var mp := mud_pattern(slot, spray, exposure)
	var fp := fly_pattern(slot)
	var keep := 1.0 - 0.6 * protect
	for i in CELLS:
		var add := (mud * Shed.ROAD_DIRT * mp[i] + flies * FLY_RATE * fp[i]) * keep
		if add > 0.0:
			# A patch that's already caked takes less.
			levels[i] = minf(1.0, levels[i] + add * (1.0 - 0.7 * levels[i]))
	store(it, levels)


## The regions of a bike's parts as they are now: slot -> levels, for every part fitted.
static func of_bike(bike_id: int) -> Dictionary:
	var out := {}
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			out[slot] = cells(Shed.items[id], slot)
	return out


## A short signature of a bike's dirt, to know when to redraw it.
static func sig_of_bike(bike_id: int) -> String:
	var parts := PackedStringArray()
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			var it: Dictionary = Shed.items[id]
			parts.append("%d:%.4f:%d" % [id, float(it.get("dirt", 0.0)), hash(it.get("grime", 0))])
	return ",".join(parts)


## How dirty one side of a part is, 0..1 (a mean over that facing's regions).
static func side(levels: PackedFloat32Array, d: int) -> float:
	var sum := 0.0
	for iy in NY:
		for ix in NX:
			sum += levels[index(d, ix, iy)]
	return sum / (NX * NY)
