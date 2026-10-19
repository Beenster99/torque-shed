class_name AdventureTheme
extends RefCounted
## The kinds of adventure ride (Adventure.THEMES): "varied" (a bit of everything, the first
## build's road), "desert", "alpine", "coastal" and "hills". A theme is plain data read by the
## planner (AdventureRoute: its bends, widths, climbs, surfaces and the ways at its forks), the
## chunk builder (AdventureChunk: the land's colours, the scenery, walls and hedges, the far
## mesas, crags and lighthouses), the stops (AdventureStops: the building style), the far ground
## or the sea (AdventureWorld) and the trip (AdventureTrip: the sky's tint, the weather's odds
## and the time of day at the start). Everything it draws is from the route's seed, so every
## player's game has the same ride; "varied" leaves everything as the first build planned it.
##
## Each theme's entry (all optional but name; a missing one is "varied"'s):
##   name, roads: what the menus and the start's message call it ("Desert", "desert roads").
##   kinds: weights of AdventureRoute.KINDS; bends: {kind: overrides of AdventureRoute.BENDS[kind]}.
##   bag, surf_len: the surfaces drawn in turn and how long each lasts (AdventureRoute.SURFACE_BAG).
##   widths: multipliers on the chances of each road width (narrow lanes in the hills).
##   heights: {h0 start height, lo, hi (the road turns back down past it), steep (times the grades),
##       up (the odds a climb rather than a descent), wave ([metres from top to top, the valleys'
##       height, the tops']: mountain passes, climbing to each top and down the other side)}.
##   hills, lift: times the land's own rise and fall, and the high ground off towards the skyline.
##   snow: snow on the road over the tops (the highest fifth of the road, and never below this).
##   track_sand, pass_rise, pass_snow: a fork's gravel track has sand in it at these odds, a scenic
##       pass climbs this far over its top, and has snow over a high top.
##   sea: the sea (at SEA_Y) off to the left of the road, with cliffs and beaches down to it.
##   land, patch, verge, road: {surface: Color} over AdventureSurface's LAND_COLOR, LAND_PATCH,
##       VERGE_COLOR and ROAD_COLOR.
##   scenery: {surface: {kind: how many a chunk}} over AdventureChunk.SCENERY.
##   far: [kind, odds a chunk, how many at most] (mesas, crags, lighthouses), set back from the road.
##   bounds: [kind, {surface: odds a 600 m stretch has it}] ("fence", "wall", "hedge" or "wall_hedge"
##       for either); buildings: times AdventureChunk.BUILDING_ODDS.
##   style: the buildings ("mixed", "adobe", "chalet", "whitewash", "stone"; see walls()).
##   sky: {top, horizon (the day sky's), fog (the haze's colour), amount (how far they're tinted),
##       haze (more fog density)}; weather: odds of each Weather state; start_hour (-1: as it is).

const IDS: Array[String] = ["varied", "desert", "alpine", "coastal", "hills"]
## The sea's height in the route frame (m).
const SEA_Y := 0.0

const DATA := {
	"varied": {"name": "Varied", "roads": "varied roads", "style": "mixed", "start_hour": -1.0},
	"desert": {
		"name": "Desert", "roads": "desert roads: sand, long straights and mesas",
		"kinds": {"straight": 0.52, "sweeping": 0.33, "curvy": 0.12, "very_curvy": 0.03},
		"bends": {"straight": {"len": [1400.0, 3600.0], "gap": [400.0, 1200.0]}},
		"bag": ["tarmac", "tarmac", "tarmac", "sand", "sand", "sand", "gravel"],
		"surf_len": [2000.0, 5200.0],
		"widths": {"two_lane": 1.6, "single": 0.4},
		"heights": {"h0": 320.0, "lo": 180.0, "hi": 760.0, "steep": 0.5, "up": 0.5},
		"hills": 0.45, "lift": 0.5, "track_sand": 0.95, "pass_rise": [90.0, 200.0], "pass_snow": false,
		"land": {"tarmac": Color(0.72, 0.55, 0.38), "gravel": Color(0.66, 0.48, 0.34), "sand": Color(0.84, 0.62, 0.42)},
		"patch": {"tarmac": Color(0.6, 0.5, 0.32), "gravel": Color(0.58, 0.38, 0.28), "sand": Color(0.76, 0.52, 0.36)},
		"verge": {"tarmac": Color(0.74, 0.6, 0.44), "gravel": Color(0.7, 0.54, 0.4), "sand": Color(0.8, 0.62, 0.44)},
		"road": {"sand": Color(0.78, 0.58, 0.4), "gravel": Color(0.58, 0.46, 0.36)},
		"scenery": {"tarmac": {"cactus": 9, "dry_bush": 10, "red_rock": 9}, "gravel": {"cactus": 6, "dry_bush": 8, "red_rock": 14},
			"sand": {"cactus": 5, "dry_bush": 10, "red_rock": 11}},
		"far": ["mesa", 0.45, 2],
		"bounds": ["fence", {"tarmac": 0.12}], "buildings": 0.6,
		"style": "adobe",
		"sky": {"top": Color(0.16, 0.36, 0.74), "horizon": Color(0.86, 0.76, 0.62), "fog": Color(0.88, 0.76, 0.6), "amount": 0.6, "haze": 0.0004},
		"weather": {"clear": 0.8, "cloudy": 0.17, "fog": 0.0, "rain": 0.03},
		"start_hour": 8.0,
	},
	"alpine": {
		"name": "Alpine", "roads": "mountain passes: hairpins, climbs and snow near the top",
		"kinds": {"straight": 0.04, "sweeping": 0.18, "curvy": 0.3, "very_curvy": 0.48},
		"bends": {"very_curvy": {"r": [16.0, 34.0], "arc": [100.0, 168.0], "t": [10.0, 18.0], "gap": [20.0, 90.0]}},
		"bag": ["tarmac", "tarmac", "tarmac", "tarmac", "gravel"],
		"surf_len": [1500.0, 4000.0],
		"widths": {"two_lane": 0.5, "single": 0.6},
		"heights": {"h0": 820.0, "lo": 450.0, "hi": 2500.0, "steep": 1.3, "up": 0.6, "wave": [32000.0, 750.0, 2400.0]},
		"hills": 1.7, "lift": 2.6, "snow": 1500.0, "track_sand": 0.0, "pass_rise": [260.0, 520.0], "pass_snow": true,
		"land": {"tarmac": Color(0.27, 0.44, 0.19), "gravel": Color(0.33, 0.4, 0.24)},
		"patch": {"tarmac": Color(0.38, 0.5, 0.22), "gravel": Color(0.46, 0.44, 0.4)},
		"verge": {"tarmac": Color(0.32, 0.42, 0.22)},
		"scenery": {"tarmac": {"pine": 22, "tree": 3, "rock": 6, "bush": 4}, "gravel": {"pine": 26, "rock": 10},
			"snow": {"snow_pine": 20, "rock": 8}},
		"far": ["crag", 0.4, 2],
		"bounds": ["fence", {"tarmac": 0.3, "gravel": 0.15}], "buildings": 1.0,
		"style": "chalet",
		"sky": {"top": Color(0.1, 0.3, 0.72), "horizon": Color(0.7, 0.8, 0.92), "fog": Color(0.74, 0.8, 0.9), "amount": 0.55, "haze": 0.0},
		"weather": {"clear": 0.5, "cloudy": 0.25, "fog": 0.18, "rain": 0.07},
		"start_hour": 6.8,
	},
	"coastal": {
		"name": "Coastal", "roads": "cliff roads by the sea, beaches and lighthouses",
		"kinds": {"straight": 0.14, "sweeping": 0.42, "curvy": 0.34, "very_curvy": 0.1},
		"bag": ["tarmac", "tarmac", "tarmac", "tarmac", "gravel", "sand"],
		"surf_len": [1800.0, 4600.0],
		"heights": {"h0": 70.0, "lo": 28.0, "hi": 170.0, "steep": 0.9, "up": 0.5},
		"hills": 0.7, "lift": 0.7, "track_sand": 0.7, "pass_rise": [60.0, 120.0], "pass_snow": false,
		"sea": true,
		"land": {"tarmac": Color(0.36, 0.48, 0.22), "gravel": Color(0.4, 0.46, 0.26), "sand": Color(0.86, 0.8, 0.62)},
		"patch": {"tarmac": Color(0.5, 0.52, 0.26), "gravel": Color(0.48, 0.44, 0.3), "sand": Color(0.72, 0.7, 0.5)},
		"verge": {"sand": Color(0.8, 0.76, 0.58)},
		"road": {"sand": Color(0.8, 0.74, 0.56)},
		"scenery": {"tarmac": {"gorse": 14, "bush": 5, "rock": 6, "tree": 2}, "gravel": {"gorse": 12, "rock": 10, "pine": 3},
			"sand": {"dune_grass": 22, "gorse": 4, "rock": 4}},
		"far": ["lighthouse", 0.01, 1],
		"bounds": ["wall", {"tarmac": 0.35, "gravel": 0.2}], "buildings": 1.0,
		"style": "whitewash",
		"sky": {"top": Color(0.2, 0.44, 0.78), "horizon": Color(0.76, 0.84, 0.9), "fog": Color(0.74, 0.82, 0.88), "amount": 0.5, "haze": 0.0006},
		"weather": {"clear": 0.5, "cloudy": 0.28, "fog": 0.1, "rain": 0.12},
		"start_hour": 9.0,
	},
	"hills": {
		"name": "Hills", "roads": "narrow lanes between stone walls and hedges, sheep on the hills",
		"kinds": {"straight": 0.08, "sweeping": 0.24, "curvy": 0.46, "very_curvy": 0.22},
		"bag": ["tarmac", "tarmac", "tarmac", "tarmac", "gravel"],
		"surf_len": [1500.0, 4200.0],
		"widths": {"two_lane": 0.15, "road": 0.6, "narrow": 1.5, "single": 2.2},
		"heights": {"h0": 180.0, "lo": 60.0, "hi": 560.0, "steep": 1.2, "up": 0.5},
		"hills": 1.1, "lift": 0.85, "track_sand": 0.0, "pass_rise": [70.0, 150.0], "pass_snow": false,
		"land": {"tarmac": Color(0.25, 0.46, 0.17), "gravel": Color(0.3, 0.42, 0.19)},
		"patch": {"tarmac": Color(0.34, 0.52, 0.2), "gravel": Color(0.4, 0.32, 0.33)},
		"verge": {"tarmac": Color(0.3, 0.42, 0.18)},
		"scenery": {"tarmac": {"oak": 8, "tree": 4, "bush": 6, "sheep": 10, "rock": 2}, "gravel": {"oak": 4, "sheep": 12, "rock": 6, "bush": 4}},
		"far": [],
		"bounds": ["wall_hedge", {"tarmac": 0.85, "gravel": 0.6}], "buildings": 1.3,
		"style": "stone",
		"sky": {"top": Color(0.26, 0.44, 0.72), "horizon": Color(0.72, 0.78, 0.8), "fog": Color(0.7, 0.76, 0.76), "amount": 0.45, "haze": 0.0008},
		"weather": {"clear": 0.38, "cloudy": 0.36, "fog": 0.1, "rain": 0.16},
		"start_hour": 8.5,
	},
}

## The buildings of each style: wall colours, roof colours, and whether the roofs are flat.
const STYLES := {
	"mixed": {"walls": [Color(0.86, 0.82, 0.72), Color(0.72, 0.62, 0.5), Color(0.6, 0.32, 0.24), Color(0.9, 0.9, 0.88), Color(0.68, 0.7, 0.66)],
		"roofs": [Color(0.25, 0.22, 0.22), Color(0.45, 0.2, 0.15), Color(0.32, 0.34, 0.36)], "flat": false},
	"adobe": {"walls": [Color(0.8, 0.56, 0.38), Color(0.86, 0.66, 0.46), Color(0.72, 0.47, 0.33)],
		"roofs": [Color(0.6, 0.4, 0.27), Color(0.55, 0.36, 0.25)], "flat": true},
	"chalet": {"walls": [Color(0.44, 0.29, 0.17), Color(0.54, 0.37, 0.21), Color(0.36, 0.24, 0.15)],
		"roofs": [Color(0.27, 0.22, 0.18), Color(0.24, 0.24, 0.26)], "flat": false},
	"whitewash": {"walls": [Color(0.95, 0.95, 0.93), Color(0.93, 0.93, 0.89), Color(0.88, 0.92, 0.95)],
		"roofs": [Color(0.28, 0.3, 0.35), Color(0.2, 0.3, 0.45)], "flat": false},
	"stone": {"walls": [Color(0.6, 0.58, 0.53), Color(0.7, 0.64, 0.5), Color(0.53, 0.5, 0.46)],
		"roofs": [Color(0.24, 0.25, 0.28), Color(0.3, 0.29, 0.27)], "flat": false},
}


static func has(theme: String) -> bool:
	return DATA.has(theme)


## Theme `theme`'s `key`, or varied's (or `fallback`) when it hasn't one.
static func get_value(theme: String, key: String, fallback: Variant = null) -> Variant:
	var d: Dictionary = DATA.get(theme, DATA["varied"])
	if d.has(key):
		return d[key]
	return DATA["varied"].get(key, fallback)


static func name_of(theme: String) -> String:
	return str(get_value(theme, "name", "Varied"))


static func roads_of(theme: String) -> String:
	return str(get_value(theme, "roads", "varied roads"))


## The theme's colour for `table` ("land", "patch", "verge", "road") on `surf`, or `fallback`.
static func color(theme: String, table: String, surf: String, fallback: Color) -> Color:
	var t: Dictionary = get_value(theme, table, {})
	return t.get(surf, fallback)


## The building style's wall colours, roof colours and flat roofs ({walls, roofs, flat}).
static func style(theme: String) -> Dictionary:
	return STYLES.get(str(get_value(theme, "style", "mixed")), STYLES["mixed"])


## A state of the weather drawn from the theme's odds with `roll` (0..1): "" for no say ("varied").
static func weather_pick(theme: String, roll: float) -> String:
	return weather_pick_from(get_value(theme, "weather", {}), roll)


## A state drawn from `odds` ({state: weight}) with `roll` (0..1); "" when there are none.
static func weather_pick_from(odds: Dictionary, roll: float) -> String:
	if odds.is_empty():
		return ""
	var sum := 0.0
	for k in odds:
		sum += float(odds[k])
	roll *= sum
	var last := ""
	for k in odds:
		if float(odds[k]) <= 0.0:
			continue
		last = str(k)
		roll -= float(odds[k])
		if roll <= 0.0:
			return last
	return last
