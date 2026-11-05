class_name BuildingHeights
extends RefCounted
## How tall a ride's buildings are where the map doesn't say. The baker gives a building with no mapped height or
## floors one fixed height for its kind (tools/land_bake.py DEFAULT_HEIGHT: every block of flats 14 m, every house
## 5.5 m), so a whole city came out four or five storeys. Here such a building takes a height that suits where it
## stands instead: how big the town is (its population, from the region's places), how near its middle, the region's
## way of building (Europe's old centres stay low; Asia's and the Americas' climb), its footprint, and a roll of its own
## blended with its street's, so a street keeps a height of its own and a big city's middle has the odd tower.
##
## A building the map gives a height or floors for keeps it. Everything is worked out from where the building stands,
## so every game in a crew draws the same heights. Safe on a worker; the places are filed once a region under a lock.

## Bumped when the heights guessed change (folded into BuildingLooks.VERSION, so into the builder hash).
const VERSION := 1
## The baker's fallback heights by kind (land_bake.py DEFAULT_HEIGHT): a building this tall said nothing.
const FALLBACK := {"house": 5.5, "shed": 3.0, "barn": 6.0, "shop": 6.5, "block": 14.0, "industrial": 7.5,
	"worship": 8.0, "civic": 8.5}
## A storey (m), and the ground floor's extra.
const STOREY := 3.2
const GROUND := 1.0
## A place counts from this many people; one with none known counts as this many (a town).
const MIN_POP := 3000
const UNKNOWN_POP := 15000
## The places are filed in squares this size (m).
const GRID := 2000.0
## A street's heights hang together over this (m): the roll is part its square's, part its own.
const STREET := 70.0
const STREET_SHARE := 0.6
## How far a place's built-up middle reaches (m): FROM plus PER for each tenfold over 10,000 people, at most MOST.
const REACH_FROM := 700.0
const REACH_PER := 2600.0
const REACH_MOST := 9000.0
## By region: how much taller the middles build (1 as is), and how likely a tower is there (1 as is).
const CLIMB := {"british_isles": 0.85, "western_europe": 0.8, "nordic": 0.8, "mediterranean": 0.85,
	"eastern_europe": 1.0, "north_africa_middle_east": 1.05, "sub_saharan_africa": 0.95, "north_america": 1.1,
	"latin_america": 1.1, "south_asia": 1.1, "east_asia": 1.25, "south_east_asia": 1.2, "australia_nz": 1.0}
const TOWERS := {"british_isles": 0.6, "western_europe": 0.45, "nordic": 0.4, "mediterranean": 0.5,
	"eastern_europe": 0.8, "north_africa_middle_east": 1.2, "sub_saharan_africa": 0.7, "north_america": 1.3,
	"latin_america": 1.2, "south_asia": 1.0, "east_asia": 1.8, "south_east_asia": 1.6, "australia_nz": 1.0}
## A tower stands only on a footprint like this: neither side under TOWER_SIDE (m), between these areas (m²).
const TOWER_SIDE := 14.0
const TOWER_AREA := [220.0, 2500.0]

static var _index := {}     # region instance id -> {"grid": {Vector2i: [[x, z, pop, reach]]}, "n": places}
static var _lock := Mutex.new()


## The height building row `row` ([x, z, w, d, yaw, h, kind, ...], `region`'s frame) is drawn at in kit `kit`: its own
## where the map gave it one; else one that suits where it stands (see the top).
static func of(region: RealRegion, row: Array, kit: Dictionary) -> float:
	var h := float(row[5])
	var kind := RealPack.BUILDING_KINDS[clampi(int(row[6]), 0, RealPack.BUILDING_KINDS.size() - 1)]
	if region == null or not is_equal_approx(h, float(FALLBACK.get(kind, -1.0))):
		return h
	if not kind in ["block", "shop", "civic", "house"]:
		return h
	var x := float(row[0])
	var z := float(row[1])
	var place := centre_of(region, x, z, str(kit.get("density", "")))
	return guess(kind, float(row[2]), float(row[3]), x, z, float(place["size"]), float(place["central"]),
		str(kit.get("region", "")), h)


## A building's height (m) where the map doesn't say: `kind` with a `w` x `d` footprint at (x, z), in a place of `size`
## (log10 of its people) `central` (0 at its edge, 1 at its middle) of the way in, in region kit `region`; `fallback`
## where nothing suits it better.
static func guess(kind: String, w: float, d: float, x: float, z: float, size: float, central: float, region: String,
		fallback: float) -> float:
	var own := _roll(x, z, 1)
	var street := _roll(floorf(x / STREET), floorf(z / STREET), 2)
	var roll := lerpf(own, street, STREET_SHARE)
	var big := maxf(0.0, size - 3.5)   # (a town of 3,000 or so: 0; 10,000,000: 3.5)
	var climb := float(CLIMB.get(region, 1.0))
	if kind == "house":
		# A town house near the middle of a place of any size is a storey or two taller than a village's.
		if central < 0.15 or size < 4.0:
			return fallback
		var most := 2.0 + central * minf(big, 2.5) * 1.2 * climb
		return floorf(lerpf(2.0, most + 0.99, roll)) * STOREY + GROUND
	var lo := 2.0 + central * big * 1.1 * climb
	var hi := 3.5 + central * big * 2.4 * climb
	if kind == "shop":
		hi = maxf(lo, hi * 0.8)
	var floors := floorf(lerpf(lo, hi + 0.99, pow(roll, 1.2)))
	# Now and then, in the middle of a big place, a tower.
	var tower := central * central * maxf(0.0, size - 4.7) * 0.07 * float(TOWERS.get(region, 1.0))
	var area := w * d
	if minf(w, d) >= TOWER_SIDE and area >= TOWER_AREA[0] and area <= TOWER_AREA[1] and _roll(x, z, 3) < tower:
		floors = 12.0 + floorf(_roll(x, z, 4) * (10.0 + maxf(0.0, size - 5.0) * 16.0 * climb))
	return maxf(floors, 1.0) * STOREY + GROUND


## The place whose middle building at (x, z) stands nearest the heart of, by its size: {"size": log10 of its people,
## "central": 0..1}. A place of `density` "city" or "town" with none near still counts as a town.
static func centre_of(region: RealRegion, x: float, z: float, density := "") -> Dictionary:
	var idx := _index_of(region)
	var best := {"size": log(float(UNKNOWN_POP)) / log(10.0) if density in ["city", "town"] else 3.0,
		"central": 0.3 if density == "city" else 0.0}
	var score := float(best["central"]) * float(best["size"])
	for p: Array in (idx["grid"] as Dictionary).get(Vector2i(floori(x / GRID), floori(z / GRID)), []):
		var dist := Vector2(float(p[0]) - x, float(p[1]) - z).length()
		var c := 1.0 - dist / float(p[3])
		if c <= 0.0:
			continue
		var s := log(float(p[2])) / log(10.0)
		if c * s > score:
			score = c * s
			best = {"size": s, "central": c}
	return best


## How far place of `pop` people's built-up middle reaches (m).
static func reach_of(pop: float) -> float:
	return clampf(REACH_FROM + REACH_PER * (log(maxf(pop, 1.0)) / log(10.0) - 4.0), REACH_FROM, REACH_MOST)


## A roll 0..1 from where something is and what it's for (the same in every game).
static func _roll(x: float, z: float, what: int) -> float:
	return float(posmod(hash([roundi(x * 4.0), roundi(z * 4.0), what]), 100003)) / 100003.0


## `region`'s towns filed by the GRID squares their middles reach into: worked out once a region, under a lock.
static func _index_of(region: RealRegion) -> Dictionary:
	var id := region.get_instance_id()
	_lock.lock()
	var got = _index.get(id)
	if got == null or int(got["n"]) != region.places.size():
		if _index.size() > 4:
			_index.clear()   # (rides come and go: keep only the last few regions')
		var grid := {}
		for p in region.places:
			if not p is Dictionary or str(p.get("kind", "")) != "town":
				continue
			var pop := float(p.get("pop", 0))
			if pop <= 0.0:
				pop = UNKNOWN_POP
			if pop < MIN_POP:
				continue
			var r := reach_of(pop)
			var px := float(p["x"])
			var pz := float(p["z"])
			for gx in range(floori((px - r) / GRID), floori((px + r) / GRID) + 1):
				for gz in range(floori((pz - r) / GRID), floori((pz + r) / GRID) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					(grid[k] as Array).append([px, pz, pop, r])
		got = {"grid": grid, "n": region.places.size()}
		_index[id] = got
	_lock.unlock()
	return got
