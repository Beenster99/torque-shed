class_name PlaceLook
extends RefCounted
## The look of a real ride, chosen by the place it's in (PlaceProfile, T1) and the month, instead of one of
## AdventureTheme's hand themes: the colour of the ground (the kit's grass, greener or drier by the month's rain, with
## the satellite's own colour of the ground taking over further from the road), what covers it (woods, crops by the
## season, scrub, bare rock), the plants the scenery placer puts down (a vegetation kit by climate zone and altitude),
## the field boundaries and the size of the fields (by country), the sun's path (by latitude and month), the sky's
## tint and haze, the snow line, and the odds of each kind of weather (from the month's climate normals).
##
## choose() is a pure function of the profile and the month (no scene, no network), so the look can be tested on its
## own and every player of a co-op ride gets the same one. for_pack() finds a ride's profiles (blocking on the network
## the first time a cell's is asked for: warm() it on a worker first) and adds the satellite's ground to the look.
##
## The look (AdventureRoute.look) is a Dictionary:
##   kit, kit_name, month (1..12), local_month (the season's: six on in the south), green (0 parched .. 1 lush),
##   autumn (the share of broadleaves turned), land, patch, verge, road ({surface: Color}, AdventureSurface.IDS),
##   cover ({cover: [Color, share]}, over AdventureChunk.COVER_TINT), woods (far forest), plants ({kind: tries a chunk},
##   for the scenery placer), broad, needle (the canopy map's trees), bounds ([kind, {surface: odds}]), field_m,
##   snow_line (m above the sea, INF for none), sky ({top, horizon, fog, amount, haze, lat, decl}: Daylight.set_tint),
##   weather ({state: odds}), start_hour, ground ([{south, west, north, east, size, rgb}], the satellite's tints).

## The vegetation kits, by climate zone and altitude (see kit_of).
const KITS: Array[String] = ["temperate", "boreal", "mediterranean", "arid", "tropical_dry", "tropical_wet", "alpine"]
const KIT_NAMES := {"temperate": "Temperate broadleaf", "boreal": "Boreal forest", "mediterranean": "Mediterranean",
	"arid": "Arid", "tropical_dry": "Tropical dry", "tropical_wet": "Tropical wet", "alpine": "Alpine"}
## Each kit's colours (grass in a wet month and a parched one, the patches mixed into it, its woods, scrub and bare
## rock), what the scenery placer tries to put down a chunk (thinned to the cover, AdventureChunk.ODDS), the canopy
## map's broadleaf and conifer, and whether its broadleaves turn in the autumn.
const KIT := {
	"temperate": {"grass": Color(0.27, 0.45, 0.17), "dry": Color(0.56, 0.52, 0.3), "patch": Color(0.36, 0.5, 0.2),
		"forest": Color(0.1, 0.23, 0.1), "shrub": Color(0.32, 0.4, 0.2), "rock": Color(0.46, 0.45, 0.42),
		"plants": {"tree": 150, "oak": 80, "pine": 35, "bush": 70, "rock": 24, "sheep": 10},
		"broad": "oak", "needle": "pine", "turns": true},
	"boreal": {"grass": Color(0.3, 0.4, 0.2), "dry": Color(0.5, 0.48, 0.3), "patch": Color(0.38, 0.42, 0.26),
		"forest": Color(0.07, 0.17, 0.09), "shrub": Color(0.26, 0.32, 0.18), "rock": Color(0.44, 0.44, 0.43),
		"plants": {"pine": 200, "birch": 90, "bush": 40, "rock": 34},
		"broad": "birch", "needle": "pine", "turns": true},
	"mediterranean": {"grass": Color(0.42, 0.46, 0.22), "dry": Color(0.72, 0.6, 0.38), "patch": Color(0.54, 0.46, 0.3),
		"forest": Color(0.2, 0.28, 0.14), "shrub": Color(0.4, 0.42, 0.25), "rock": Color(0.64, 0.56, 0.46),
		"plants": {"olive": 60, "cypress": 22, "pine": 50, "dry_bush": 90, "bush": 25, "rock": 40},
		"broad": "olive", "needle": "pine", "turns": false},
	"arid": {"grass": Color(0.6, 0.55, 0.34), "dry": Color(0.8, 0.64, 0.44), "patch": Color(0.72, 0.5, 0.35),
		"forest": Color(0.34, 0.36, 0.22), "shrub": Color(0.52, 0.47, 0.3), "rock": Color(0.66, 0.45, 0.32),
		"plants": {"dry_bush": 110, "tussock": 50, "acacia": 14, "red_rock": 40, "rock": 30},
		"broad": "acacia", "needle": "pine", "turns": false},
	"tropical_dry": {"grass": Color(0.36, 0.46, 0.18), "dry": Color(0.68, 0.57, 0.35), "patch": Color(0.54, 0.43, 0.28),
		"forest": Color(0.2, 0.3, 0.12), "shrub": Color(0.42, 0.43, 0.22), "rock": Color(0.58, 0.47, 0.38),
		"plants": {"acacia": 70, "tree": 40, "pine": 50, "dry_bush": 70, "bush": 30, "rock": 24},
		"broad": "acacia", "needle": "pine", "turns": false},
	"tropical_wet": {"grass": Color(0.22, 0.48, 0.12), "dry": Color(0.42, 0.48, 0.2), "patch": Color(0.3, 0.52, 0.16),
		"forest": Color(0.07, 0.27, 0.08), "shrub": Color(0.2, 0.4, 0.12), "rock": Color(0.42, 0.4, 0.36),
		"plants": {"jungle_tree": 170, "palm": 50, "tree": 40, "bush": 100, "rock": 10},
		"broad": "jungle_tree", "needle": "pine", "turns": false},
	"alpine": {"grass": Color(0.34, 0.46, 0.2), "dry": Color(0.58, 0.54, 0.36), "patch": Color(0.5, 0.48, 0.42),
		"forest": Color(0.08, 0.2, 0.1), "shrub": Color(0.3, 0.36, 0.2), "rock": Color(0.52, 0.5, 0.48),
		"plants": {"pine": 150, "rock": 60, "tussock": 50, "bush": 25, "sheep": 6},
		"broad": "tree", "needle": "pine", "turns": true},
}
## The plants only the Americas have (cactus and agave: none in Morocco's or Australia's deserts).
const AMERICAS_PLANTS := {"cactus": 18, "agave": 30}
## Palms along a warm coast.
const COAST_PALMS := 30
## Grass asleep in the cold, a broadleaf wood in the autumn, snow.
const WINTER_GRASS := Color(0.44, 0.43, 0.31)
const AUTUMN := Color(0.46, 0.28, 0.1)
const SNOW := Color(0.9, 0.92, 0.96)
## Crops through the year (by the season's month, 1..12, for the temperate kits and the Mediterranean's, a few months
## ahead): young green, ripe gold, stubble and ploughland, winter's bare earth.
const CROP := {"green": Color(0.42, 0.56, 0.22), "gold": Color(0.76, 0.65, 0.33), "stubble": Color(0.58, 0.48, 0.3),
	"bare": Color(0.42, 0.36, 0.26)}
const CROP_YEAR := ["bare", "bare", "green", "green", "green", "gold", "gold", "gold", "stubble", "stubble", "bare", "bare"]
const CROP_YEAR_MED := ["green", "green", "green", "green", "gold", "gold", "stubble", "stubble", "bare", "bare", "green", "green"]
## Field boundaries and how big the fields are (m, the land's patches), by country; others take their kit's.
const FIELDS := {
	"GB": [["wall_hedge", {"tarmac": 0.85, "gravel": 0.6}], 110.0], "IE": [["wall_hedge", {"tarmac": 0.8, "gravel": 0.6}], 110.0],
	"NL": [["fence", {"tarmac": 0.2}], 260.0], "BE": [["fence", {"tarmac": 0.3}], 200.0],
	"DE": [["fence", {"tarmac": 0.3, "gravel": 0.2}], 150.0], "AT": [["fence", {"tarmac": 0.4, "gravel": 0.3}], 120.0],
	"CH": [["fence", {"tarmac": 0.4, "gravel": 0.3}], 110.0], "FR": [["hedge", {"tarmac": 0.35, "gravel": 0.2}], 180.0],
	"JP": [[], 50.0], "MA": [["wall", {"tarmac": 0.2, "gravel": 0.2}], 90.0], "MX": [["fence", {"tarmac": 0.45, "gravel": 0.3}], 120.0],
	"NZ": [["fence", {"tarmac": 0.6, "gravel": 0.5}], 220.0], "US": [["fence", {"tarmac": 0.55, "gravel": 0.4}], 400.0],
	"CA": [["fence", {"tarmac": 0.5, "gravel": 0.4}], 400.0], "AU": [["fence", {"tarmac": 0.5, "gravel": 0.4}], 450.0],
	"ES": [["wall", {"tarmac": 0.2, "gravel": 0.2}], 160.0], "IT": [["wall", {"tarmac": 0.25, "gravel": 0.2}], 120.0],
}
const KIT_FIELDS := {
	"temperate": [["fence", {"tarmac": 0.55, "gravel": 0.3}], 150.0], "boreal": [["fence", {"tarmac": 0.3}], 160.0],
	"mediterranean": [["wall", {"tarmac": 0.25, "gravel": 0.2}], 130.0], "arid": [["fence", {"tarmac": 0.12}], 200.0],
	"tropical_dry": [["fence", {"tarmac": 0.35, "gravel": 0.25}], 140.0], "tropical_wet": [["fence", {"tarmac": 0.2}], 120.0],
	"alpine": [["fence", {"tarmac": 0.3, "gravel": 0.15}], 120.0],
}
## How the snow line falls with the month's mean temperature (°C a metre) and the mean it lies at (°C).
const LAPSE := 0.0065
const SNOW_TEMP := -1.5
## How much the satellite's mean colour of a place's land tones its kit's grass up close.
const TINT_LAND := 0.35
## How far from the road (m) the satellite's colour of the ground takes over from the kit's and the cover's, and how
## much it takes there (its 1.7 km pixels are no use up close).
const GROUND_NEAR := [40.0, 0.18]
const GROUND_FAR := [700.0, 0.7]

## The month a look is chosen for (0: this month, by the clock). The postcards hold it.
static var month_override := 0
static var _bundled := {}
static var _lock := Mutex.new()


## The month the look is for: month_override, else this month.
static func month_now() -> int:
	return month_override if month_override > 0 else int(Time.get_date_dict_from_system()["month"])


## The vegetation kit for profile `p`: by its Köppen zone, with the mountains alpine (above the trees in the temperate
## zones' high ground, but not the tropics' or the deserts' high plateaux) and the cold continental zones boreal.
static func kit_of(p: Dictionary) -> String:
	var k := str(p.get("koppen", "Cfb"))
	var band := str(p.get("altitude_band", "lowland"))
	var lat := absf(float(p.get("lat", 0.0)))
	var second := k.substr(1, 1)
	var third := k.substr(2, 1)
	match k.substr(0, 1):
		"A":
			return "tropical_wet" if k in ["Af", "Am"] else "tropical_dry"
		"B":
			return "arid"
		"C":
			if band == "high" or (band == "mountain" and lat >= 40.0):
				return "alpine"
			if second == "s":
				return "mediterranean"
			if second == "w" and lat < 30.0:
				return "tropical_dry"
			return "temperate"
		"D":
			if band in ["mountain", "high"]:
				return "alpine"
			return "boreal" if third in ["c", "d"] else "temperate"
		"E":
			return "alpine"
	return "temperate"


## Within a kit, the shade of the place's own zone: {grass: [Color, how far], forest: [Color, how far], autumn (times
## the kit's), plants ({kind: more or fewer}), and perhaps broad and needle (the canopy map's trees, for the kit's)}. The temperate kit spans the most: a warm humid summer's (Cfa, Japan's
## evergreen woods and cedars), a continental one's (Dfb, darker and more conifers), a southern one's (evergreen bush),
## flat lowland's lush open pasture (a polder, a fen), and the wet uplands' moorland.
static func zone_shade(p: Dictionary, kit: String) -> Dictionary:
	var out := {"grass": [Color.BLACK, 0.0], "forest": [Color.BLACK, 0.0], "autumn": 1.0, "plants": {}}
	var k := str(p.get("koppen", "Cfb"))
	var lat := float(p.get("lat", 0.0))
	if kit != "temperate":
		if lat < 0.0:
			out["autumn"] = 0.4
		return out
	if k.substr(2, 1) == "a" and k.substr(0, 1) == "C":
		out["grass"] = [Color(0.4, 0.54, 0.16), 0.4]
		out["forest"] = [Color(0.12, 0.3, 0.12), 0.5]
		out["autumn"] = 0.4
		out["plants"] = {"cypress": 40, "jungle_tree": 40, "tree": -50, "oak": -60, "sheep": -10}
		out["broad"] = "jungle_tree"
		out["needle"] = "cypress"
	elif k.substr(0, 1) == "D":
		out["grass"] = [Color(0.2, 0.38, 0.16), 0.3]
		out["forest"] = [Color(0.06, 0.18, 0.09), 0.5]
		out["plants"] = {"pine": 70, "tree": -40, "sheep": -6}
	elif lat < 0.0:
		out["grass"] = [Color(0.3, 0.52, 0.22), 0.3]
		out["forest"] = [Color(0.08, 0.24, 0.12), 0.5]
		out["autumn"] = 0.0
		out["plants"] = {"jungle_tree": 60, "oak": -80, "tree": -40}
		out["broad"] = "jungle_tree"
	elif int(p["altitude"]["max"]) - int(p["altitude"]["min"]) < 60 and str(p.get("altitude_band", "")) == "lowland":
		out["grass"] = [Color(0.3, 0.56, 0.16), 0.4]
		out["plants"] = {"tree": -100, "oak": -50, "pine": -25, "bush": -30, "rock": -20, "sheep": 6}
	elif str(p.get("altitude_band", "")) in ["upland", "mountain"]:
		out["grass"] = [Color(0.46, 0.44, 0.28), 0.28]
		out["plants"] = {"tree": -60, "oak": -30, "sheep": 8, "tussock": 30}
	return out


## The month of the year as the seasons have it at latitude `lat`: six on in the southern hemisphere.
static func local_month(month: int, lat: float) -> int:
	return month if lat >= 0.0 else (month + 5) % 12 + 1


## How green the grass is in `month` of profile `p`, 0 (parched) to 1 (lush): the month's rain against what the warmth
## dries out, with a little of the month before's (the ground takes time to green or brown).
static func greenness(p: Dictionary, month: int) -> float:
	var now := PlaceProfile.month(p, month)
	var before := PlaceProfile.month(p, (month + 10) % 12 + 1)
	return 0.65 * _wet(now) + 0.35 * _wet(before)


static func _wet(m: Dictionary) -> float:
	return clampf(float(m["rain_mm"]) / (25.0 + 4.0 * maxf(float(m["temp_c"]), 0.0)), 0.0, 1.0)


## The sun's declination (degrees) in the middle of `month`.
static func declination(month: int) -> float:
	var day := 15.0 + 30.42 * (clampi(month, 1, 12) - 1)
	return -23.44 * cos(TAU / 365.0 * (day + 10.0))


## Hours of daylight in `month` at latitude `lat` (degrees).
static func day_hours(lat: float, month: int) -> float:
	var c := -tan(deg_to_rad(lat)) * tan(deg_to_rad(declination(month)))
	return 24.0 / PI * acos(clampf(c, -1.0, 1.0))


## The look of profile `p` in `month` (1..12), without the satellite's ground (for_pack adds that).
static func choose(p: Dictionary, month: int) -> Dictionary:
	month = clampi(month, 1, 12)
	var kit := kit_of(p)
	var k: Dictionary = KIT[kit]
	var lat := float(p.get("lat", 0.0))
	var lm := local_month(month, lat)
	var m := PlaceProfile.month(p, month)
	var green := greenness(p, month)
	var temp := float(m["temp_c"])
	var cold := 1.0 - smoothstep(0.0, 8.0, temp)
	var guessed := bool(p.get("guessed", false))
	var shade := zone_shade(p, kit)
	var grass: Color = (k["dry"] as Color).lerp(k["grass"], green).lerp(WINTER_GRASS, cold * 0.5)
	grass = grass.lerp(shade["grass"][0], float(shade["grass"][1]))
	var patch: Color = (k["patch"] as Color).lerp(k["dry"], (1.0 - green) * 0.4).lerp(WINTER_GRASS, cold * 0.3)
	# The place's own colour from space (its land's, not its sea's) tones the kit's, less so for a guess.
	var seen := land_tint(p)
	if seen.a > 0.0:
		grass = grass.lerp(Color(seen.r, seen.g, seen.b), TINT_LAND)
		patch = patch.lerp(Color(seen.r, seen.g, seen.b), TINT_LAND * 0.8)
	# The broadleaves turn in the autumn (fewer of a southern wood's: most are evergreen).
	var autumn := 0.0
	if bool(k["turns"]):
		autumn = float({9: 0.12, 10: 0.5, 11: 0.35}.get(lm, 0.0)) * float(shade["autumn"])
	var look := {"kit": kit, "kit_name": KIT_NAMES[kit], "month": month, "local_month": lm, "green": green, "autumn": autumn}
	# The land beside each surface, and the road.
	var sunny := _sun_share(p)
	var land := {}
	var patches := {}
	var verge := {}
	var road := {}
	for surf in AdventureSurface.IDS:
		match surf:
			"tarmac", "gravel":
				land[surf] = grass if surf == "tarmac" else grass.lerp(k["rock"], 0.15)
				patches[surf] = patch if surf == "tarmac" else patch.lerp(k["rock"], 0.4)
				verge[surf] = grass.lerp(k["dry"], 0.25).darkened(0.08)
			"sand":
				land[surf] = (AdventureSurface.LAND_COLOR[surf] as Color).lerp(k["dry"], 0.3)
				patches[surf] = (AdventureSurface.LAND_PATCH[surf] as Color).lerp(k["rock"], 0.3)
				verge[surf] = (AdventureSurface.VERGE_COLOR[surf] as Color).lerp(k["dry"], 0.3)
			_:
				land[surf] = AdventureSurface.LAND_COLOR[surf]
				patches[surf] = AdventureSurface.LAND_PATCH[surf]
				verge[surf] = AdventureSurface.VERGE_COLOR[surf]
		road[surf] = AdventureSurface.ROAD_COLOR[surf]
	# Tarmac bleaches in a sunny land; gravel is the local stone.
	road["tarmac"] = (road["tarmac"] as Color).lerp(Color(0.32, 0.31, 0.3), smoothstep(0.4, 0.75, sunny) * 0.6)
	road["gravel"] = (road["gravel"] as Color).lerp(k["rock"], 0.45)
	road["sand"] = (road["sand"] as Color).lerp(k["dry"], 0.3)
	look["land"] = land
	look["patch"] = patches
	look["verge"] = verge
	look["road"] = road
	# What covers the ground.
	var forest: Color = (k["forest"] as Color).lerp(shade["forest"][0], float(shade["forest"][1])).lerp(AUTUMN, autumn * 0.6)
	if kit == "tropical_dry":
		forest = forest.lerp(k["dry"], (1.0 - green) * 0.45)
	var crop: Color
	match kit:
		"tropical_dry", "tropical_wet":
			crop = (k["dry"] as Color).lerp(CROP["green"], green)
		"arid":
			crop = CROP["green"].lerp(k["dry"], 0.2)   # (watered)
		"mediterranean":
			crop = CROP[CROP_YEAR_MED[lm - 1]]
		_:
			crop = CROP[CROP_YEAR[lm - 1]]
	look["cover"] = {
		"forest": [forest, 0.85], "crop": [crop, 0.7], "shrub": [(k["shrub"] as Color).lerp(k["dry"], (1.0 - green) * 0.5), 0.55],
		"urban": [Color(0.52, 0.5, 0.46), 0.65], "sand": [AdventureChunk.BEACH, 0.8],
		"barren": [(k["rock"] as Color).lightened(0.08), 0.65], "rock": [k["rock"], 0.8],
		"water": [Color(0.24, 0.25, 0.19), 0.8], "wetland": [grass.lerp(Color(0.3, 0.4, 0.28), 0.6), 0.6],
	}
	look["woods"] = forest
	# The plants.
	var plants: Dictionary = (k["plants"] as Dictionary).duplicate()
	for kind in shade["plants"]:
		plants[kind] = maxi(0, int(plants.get(kind, 0)) + int(shade["plants"][kind]))
		if int(plants[kind]) == 0:
			plants.erase(kind)
	var lon := float(p.get("lon", 0.0))
	if kit in ["arid", "tropical_dry"] and lon < -30.0:
		plants.merge(AMERICAS_PLANTS)
	if kit in ["tropical_wet", "tropical_dry", "mediterranean"] and bool(p.get("coast", false)) and temp > 12.0:
		plants["palm"] = int(plants.get("palm", 0)) + COAST_PALMS
	if autumn > 0.0 and plants.has("tree"):
		plants["autumn_tree"] = roundi(float(plants["tree"]) * autumn)
		plants["tree"] = roundi(float(plants["tree"]) * (1.0 - autumn))
	look["plants"] = plants
	look["broad"] = shade.get("broad", k["broad"])
	look["needle"] = shade.get("needle", k["needle"])
	# The fields.
	var fields: Array = FIELDS.get(str(p.get("country", "")), KIT_FIELDS[kit])
	look["bounds"] = fields[0]
	look["field_m"] = fields[1]
	# Snow: where the month's mean is cold enough, falling with height from the land's mean.
	var alt: Dictionary = p.get("altitude", {})
	var line := float(alt.get("mean", 0)) + (temp - SNOW_TEMP) / LAPSE
	look["snow_line"] = line if line < float(alt.get("max", 0)) + 300.0 else INF
	look["sky"] = sky(p, month, green, kit)
	look["weather"] = weather(p, month)
	look["start_hour"] = 8.5
	look["guessed"] = guessed
	look["ground"] = []
	return look


## The share of the year's daylight that is sunshine (0..1), from the climate normals.
static func _sun_share(p: Dictionary) -> float:
	var lat := float(p.get("lat", 0.0))
	var sun := 0.0
	var day := 0.0
	for mo in range(1, 13):
		sun += float(PlaceProfile.month(p, mo)["sun_h"])
		day += day_hours(lat, mo) * float(PlaceProfile.MONTH_DAYS[mo - 1])
	return clampf(sun / maxf(day, 1.0), 0.0, 1.0)


## The sky's tint ({top, horizon, fog, amount, haze}, Daylight.tint) and the sun's path (lat, decl): deep blue and clear
## up high, dusty and warm over a desert, pale and hazy in damp air, a sea haze by the coast.
static func sky(p: Dictionary, month: int, green: float, kit: String) -> Dictionary:
	var m := PlaceProfile.month(p, month)
	var high := clampf(float(p["altitude"]["mean"]) / 2500.0, 0.0, 1.0)
	var damp := clampf(float(m["rain_mm"]) / 150.0, 0.0, 1.0) * clampf((float(m["temp_c"]) + 5.0) / 25.0, 0.2, 1.0)
	var dust := (1.0 - green) * (1.0 if kit == "arid" else (0.6 if kit in ["mediterranean", "tropical_dry"] else 0.2))
	var coast := 1.0 if bool(p.get("coast", false)) else 0.0
	var top := Color(0.22, 0.42, 0.75).lerp(Color(0.09, 0.27, 0.72), high).lerp(Color(0.34, 0.48, 0.7), damp * 0.5)
	var horizon := Color(0.72, 0.8, 0.9).lerp(Color(0.88, 0.78, 0.62), dust * 0.8).lerp(Color(0.78, 0.82, 0.84), damp * 0.5)
	var fog := Color(0.72, 0.79, 0.88).lerp(Color(0.88, 0.76, 0.6), dust * 0.8).lerp(Color(0.76, 0.8, 0.82), damp * 0.6)
	if kit == "tropical_wet":
		horizon = horizon.lerp(Color(0.82, 0.86, 0.84), 0.4)
		fog = fog.lerp(Color(0.82, 0.86, 0.84), 0.5)
	# (below nothing up high and dry: the thin clear air takes some of the world's own haze away)
	var haze := maxf(-0.00045, 0.0002 + damp * 0.0006 + dust * 0.0005 + coast * 0.0003 - high * 0.0009)
	return {"top": top, "horizon": horizon, "fog": fog, "amount": 0.55, "haze": haze,
		"lat": float(p.get("lat", 0.0)), "decl": declination(month)}


## The odds of each kind of weather in `month` ({state: weight}, Weather.odds), from the climate normals: rain as
## often as the month has rainy days (it rains for part of a rainy day), clear skies for the share of daylight that is
## sunshine, fog in a cool damp month, more so by the sea and in the hills, and cloud for the rest.
static func weather(p: Dictionary, month: int) -> Dictionary:
	var m := PlaceProfile.month(p, month)
	var days := float(PlaceProfile.MONTH_DAYS[clampi(month, 1, 12) - 1])
	var rain := clampf(float(m["rain_days"]) / days, 0.0, 1.0) * 0.45
	var sun := clampf(float(m["sun_h"]) / maxf(day_hours(float(p.get("lat", 0.0)), month) * days, 1.0), 0.0, 1.0)
	var clear := sun * (1.0 - rain)
	var damp := clampf(float(m["rain_days"]) / days * 1.5, 0.0, 1.0) * (1.0 - smoothstep(8.0, 22.0, float(m["temp_c"])))
	var fog := damp * (0.04 + (0.06 if bool(p.get("coast", false)) else 0.0) + (0.06 if str(p["altitude_band"]) in ["upland", "mountain"] else 0.0))
	var cloudy := maxf(0.0, 1.0 - clear - rain - fog)
	return {"clear": snappedf(clear, 0.001), "cloudy": snappedf(cloudy, 0.001), "fog": snappedf(fog, 0.001), "rain": snappedf(rain, 0.001)}


# ---------------------------------------------------------------------------- a ride's look

## Where (lat, lon) the knots of `pack` are, every `every` knots (its terrain's frame).
static func _points(pack: RealPack, every := 128) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var t := pack.terrain
	if t == null or (t.lat0 == 0.0 and t.lon0 == 0.0):
		return out
	var frame := Vector2(t.lat0, t.lon0)
	for i in range(0, pack.x.size(), every):
		out.append(RealRegion.from_frame(frame, pack.x[i], pack.z[i]))
	if pack.x.size() > 0:
		out.append(RealRegion.from_frame(frame, pack.x[pack.x.size() - 1], pack.z[pack.z.size() - 1]))
	return out


## The cells `pack`'s road crosses, its start's first.
static func cells_of(pack: RealPack) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ll in _points(pack):
		var c := RealRegion.cell_of(ll.x, ll.y)
		if not out.has(c):
			out.append(c)
	return out


## The profile of cell `cell`: a bundled region's (data/profiles) when it's that cell, else PlaceProfile's.
static func profile_of(cell: Vector2i) -> Dictionary:
	var key := "%d_%d" % [cell.x, cell.y]
	_lock.lock()
	if _bundled.is_empty():
		_bundled["_"] = true
		for f in DirAccess.get_files_at(PlaceProfile.BUNDLED_DIR):
			if f.ends_with(".json"):
				var v = JSON.parse_string(FileAccess.get_file_as_string(PlaceProfile.BUNDLED_DIR.path_join(f)))
				if v is Dictionary and str(v.get("cell", "")) != "":
					_bundled[str(v["cell"])] = PlaceProfile.parse(v)
	var have = _bundled.get(key)
	_lock.unlock()
	return have if have is Dictionary else PlaceProfile.of_cell(cell)


## Fetches the profiles of the cells `pack`'s road crosses (a worker's job: the planner's, AdventurePlans).
static func warm(pack: RealPack) -> void:
	for c in cells_of(pack):
		profile_of(c)


## The look of the ride along `pack` in `month`: its start's place's, with the satellite's ground of every cell its
## road crosses. A pack with no frame to find its place by gets a mild temperate one.
static func for_pack(pack: RealPack, month: int) -> Dictionary:
	var cells := cells_of(pack)
	var p := profile_of(cells[0]) if not cells.is_empty() else PlaceProfile.parse({"lat": 52.0, "lon": 0.0})
	var look := choose(p, month)
	look["profile"] = p
	var ground: Array = []
	for c in cells:
		var g := ground_of(c, profile_of(c))
		if not g.is_empty():
			ground.append(g)
	look["ground"] = ground
	return look


## Cell `cell`'s satellite tint as {south, west, north, east, size, rgb (size x size x 3 bytes, north row first)}, or
## {} when its profile has none.
static func ground_of(cell: Vector2i, p: Dictionary) -> Dictionary:
	var tint = p.get("tint")
	if not tint is Dictionary or str(tint.get("png", "")) == "":
		return {}
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(str(tint["png"]))) != OK or img.is_empty():
		return {}
	img.convert(Image.FORMAT_RGB8)
	var south := cell.x * RealRegion.CELL_DEG - 90.0
	var west := cell.y * RealRegion.CELL_DEG - 180.0
	return {"south": south, "west": west, "north": south + RealRegion.CELL_DEG, "east": west + RealRegion.CELL_DEG,
		"size": img.get_width(), "rgb": img.get_data()}


## The satellite's colour of the ground at (lat, lon) in `ground` (the look's), its alpha how much there is to go by
## (0 off the tints, and where they show water: the sea's and the lakes' own colour is no use on the land).
static func ground_at(ground: Array, lat: float, lon: float) -> Color:
	for g: Dictionary in ground:
		if lat < float(g["south"]) or lat >= float(g["north"]) or lon < float(g["west"]) or lon >= float(g["east"]):
			continue
		var n := int(g["size"])
		var rgb: PackedByteArray = g["rgb"]
		var fx := (lon - float(g["west"])) / (float(g["east"]) - float(g["west"])) * n - 0.5
		var fy := (float(g["north"]) - lat) / (float(g["north"]) - float(g["south"])) * n - 0.5
		var x0 := floori(fx)
		var y0 := floori(fy)
		var sum := Color(0, 0, 0, 0)
		var wsum := 0.0
		for dy in 2:
			for dx in 2:
				var x := clampi(x0 + dx, 0, n - 1)
				var y := clampi(y0 + dy, 0, n - 1)
				var w := (1.0 - absf(fx - (x0 + dx))) * (1.0 - absf(fy - (y0 + dy)))
				var o := (y * n + x) * 3
				var c := Color8(rgb[o], rgb[o + 1], rgb[o + 2])
				if c.b >= c.g and c.b >= c.r:
					continue   # (water)
				sum += c * w
				wsum += w
		if wsum <= 0.001:
			return Color(0, 0, 0, 0)
		var col := sum / wsum
		# From space the ground looks dull: a little more colour, as it is from the road.
		var grey := col.get_luminance()
		col = Color(grey, grey, grey).lerp(col, 1.35)
		col.a = minf(wsum * 1.5, 1.0)
		return col
	return Color(0, 0, 0, 0)


## The mean colour of profile `p`'s land from space (its tint's pixels, less the water's), livened as ground_at's;
## alpha 0 when it has no tint.
static func land_tint(p: Dictionary) -> Color:
	var cell := Vector2i(floori((float(p.get("lat", 0.0)) + 90.0) / RealRegion.CELL_DEG), floori((float(p.get("lon", 0.0)) + 180.0) / RealRegion.CELL_DEG))
	var g := ground_of(cell, p)
	if g.is_empty():
		return Color(0, 0, 0, 0)
	var rgb: PackedByteArray = g["rgb"]
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for o in range(0, rgb.size(), 3):
		var c := Color8(rgb[o], rgb[o + 1], rgb[o + 2])
		if c.b >= c.g and c.b >= c.r:
			continue
		sum += c
		n += 1
	if n == 0:
		return Color(0, 0, 0, 0)
	var col := sum / n
	var grey := col.get_luminance()
	col = Color(grey, grey, grey).lerp(col, 1.35)
	col.a = 1.0
	return col


## How much the satellite's ground takes of the land's colour `lat` metres from the road.
static func ground_share(lat: float) -> float:
	return lerpf(float(GROUND_NEAR[1]), float(GROUND_FAR[1]), smoothstep(float(GROUND_NEAR[0]), float(GROUND_FAR[0]), absf(lat)))


# ---------------------------------------------------------------------------- the kits' plants

## The kits' own plants' meshes into `a` (AdventureProps.mesh hands over the kinds it hasn't): false for a kind that
## isn't one of them.
static func plant(a: Dictionary, kind: String) -> bool:
	var trunk := Color(0.32, 0.22, 0.14)
	match kind:
		"birch":
			AdventureProps.cone(a, Transform3D(), 0.18, 0.0, 5.0, Color(0.86, 0.85, 0.8), 6, 0.1)
			AdventureProps.blob(a, Vector3(0, 5.6, 0), Vector3(1.6, 2.4, 1.6), Color(0.36, 0.5, 0.18), 61)
			AdventureProps.blob(a, Vector3(0.5, 4.4, 0.3), Vector3(1.2, 1.4, 1.2), Color(0.4, 0.54, 0.2), 67)
		"autumn_tree":
			AdventureProps.cone(a, Transform3D(), 0.28, 0.0, 2.6, trunk, 6, 0.18)
			AdventureProps.blob(a, Vector3(0, 4.2, 0), Vector3(2.6, 2.3, 2.6), Color(0.72, 0.4, 0.1), 3)
			AdventureProps.blob(a, Vector3(0.9, 5.4, 0.4), Vector3(1.6, 1.4, 1.6), Color(0.8, 0.58, 0.14), 5)
		"olive":
			AdventureProps.cone(a, Transform3D(), 0.32, 0.0, 1.6, Color(0.4, 0.34, 0.26), 6, 0.22)
			AdventureProps.blob(a, Vector3(0, 2.6, 0), Vector3(2.2, 1.4, 2.2), Color(0.42, 0.47, 0.32), 71)
			AdventureProps.blob(a, Vector3(-0.7, 3.2, 0.5), Vector3(1.3, 0.9, 1.3), Color(0.46, 0.5, 0.36), 73)
		"cypress":
			AdventureProps.cone(a, Transform3D(), 0.2, 0.0, 0.8, trunk, 5, 0.15)
			AdventureProps.blob(a, Vector3(0, 4.6, 0), Vector3(0.95, 4.2, 0.95), Color(0.12, 0.22, 0.12), 79)
		"palm":
			var lean := 0.0
			for k in 5:
				var y0 := k * 1.6
				var x0 := lean
				lean += 0.12 * k
				AdventureProps.cone(a, Transform3D(Basis(), Vector3(x0, 0, 0)), 0.22 - k * 0.015, y0, y0 + 1.65, Color(0.48, 0.4, 0.3), 6, 0.2 - k * 0.015)
			var top := Vector3(lean, 8.0, 0)
			for k in 7:
				var b := Basis(Vector3.UP, TAU * k / 7.0) * Basis(Vector3.RIGHT, deg_to_rad(-62.0 if k % 2 == 0 else -75.0))
				AdventureProps.box(a, Transform3D(b, top), Vector3(0.7, 3.4, 0.06), Color(0.2, 0.42, 0.14))
		"acacia":
			AdventureProps.cone(a, Transform3D(), 0.26, 0.0, 3.4, Color(0.38, 0.3, 0.22), 6, 0.16)
			AdventureProps.blob(a, Vector3(0, 4.1, 0), Vector3(3.4, 0.7, 3.0), Color(0.3, 0.38, 0.16), 83)
			AdventureProps.blob(a, Vector3(1.2, 3.8, 0.6), Vector3(1.8, 0.5, 1.6), Color(0.34, 0.4, 0.18), 89)
		"jungle_tree":
			AdventureProps.cone(a, Transform3D(), 0.42, 0.0, 6.0, Color(0.42, 0.36, 0.28), 6, 0.26)
			AdventureProps.blob(a, Vector3(0, 7.0, 0), Vector3(3.6, 2.0, 3.6), Color(0.12, 0.36, 0.1), 97)
			AdventureProps.blob(a, Vector3(-1.4, 5.6, 1.0), Vector3(2.4, 1.6, 2.4), Color(0.16, 0.42, 0.12), 101)
			AdventureProps.blob(a, Vector3(1.5, 8.2, -0.6), Vector3(2.0, 1.4, 2.0), Color(0.1, 0.32, 0.1), 103)
		"agave":
			for k in 9:
				var b := Basis(Vector3.UP, TAU * k / 9.0) * Basis(Vector3.RIGHT, deg_to_rad(-30.0 - (k % 3) * 12.0))
				AdventureProps.cone(a, Transform3D(b, Vector3.ZERO), 0.16, 0.0, 1.3, Color(0.42, 0.54, 0.48), 4)
		"tussock":
			for t: Vector3 in [Vector3(0, 0, 0), Vector3(0.35, 0, 0.2), Vector3(-0.3, 0, 0.3), Vector3(0.1, 0, -0.35)]:
				AdventureProps.cone(a, Transform3D(Basis(), t), 0.3, 0.0, 0.7, Color(0.7, 0.62, 0.38), 5)
		_:
			return false
	return true
