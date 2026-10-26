class_name PlaceProfile
extends RefCounted
## What a cell of the world is like (tools/profile_bake.py, docs/place_profile.md): its country and region, Köppen-Geiger
## climate zone, the months' temperature, rain and sunshine, its cover mix, altitude, sea and coast, how built up it is,
## and perhaps a small tint of its ground. The look and the sound of a ride read it, so a ride in Morocco looks and sounds
## like Morocco.
##
## A profile is a plain Dictionary with every field of docs/place_profile.md present (parse fills any gap), so a reader
## never needs a default of its own. Cells baked before profiles, and a game with no network, get a guessed one
## (guessed: true) from what the game has offline. Safe from any thread; of_cell blocks on the network the first time it
## is asked for a cell the world's store has a profile for, so ask from a worker, or call guess.

const FORMAT := 1
## The bundled regions' profiles: data/profiles/<region id>.json (not in the region's folder: that would change its hash).
const BUNDLED_DIR := "res://data/profiles"
const COVER := ["grass", "forest", "crop", "shrub", "barren", "urban", "sand", "wetland", "water", "rock"]
const CLIMATE_KEYS := ["temp_c", "temp_min_c", "temp_max_c", "rain_mm", "rain_days", "sun_h"]
## (as tools/profile_bake.py: altitude_band by the land's mean height, density by the share built up)
const ALTITUDE_BANDS := [[300.0, "lowland"], [1000.0, "upland"], [2500.0, "mountain"], [INF, "high"]]
const DENSITIES := [[0.0005, "wild"], [0.01, "rural"], [0.05, "village"], [0.2, "town"], [INF, "city"]]
## The credit for what a profile is made from (tools/profile_bake.py), added to a region's when it has profiles.
const CREDIT := ("Place: Natural Earth; Köppen-Geiger zones, Beck, H.E. et al. (2023) (CC BY 4.0); land cover and ground "
	+ "colour, © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA "
	+ "WorldCover consortium (CC BY 4.0); climate, CRU TS 4.09, University of East Anglia and Met Office (Open Government Licence).")
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
## The road rules' regions a region.json names (RealRegion.country) -> its country.
const ROAD_REGIONS := {"uk": ["GB", "United Kingdom"], "jp": ["JP", "Japan"], "japan": ["JP", "Japan"]}

static var _lock := Mutex.new()
## "ROW_COL" -> profile, those asked for this run.
static var _cells := {}
## The world's towns and cities (data/world/places.json), for a guessed profile's country.
static var _places: Array = []
static var _countries := {}


## The profile of cell `cell` (RealRegion.cell_of): the world store's if it has one (kept on disk once fetched), else
## guessed. Blocks while it fetches: a worker's job.
static func of_cell(cell: Vector2i) -> Dictionary:
	var key := "%d_%d" % [cell.x, cell.y]
	_lock.lock()
	var have = _cells.get(key)
	_lock.unlock()
	if have is Dictionary:
		return have
	var p := {}
	var v = CellStore._kept_json("profiles", "profile", key, CellStore.index(), profile_url(key))
	if v is Dictionary and int(v.get("format", 0)) == FORMAT:
		p = parse(v)
	else:
		var mid := RealRegion.cell_middle(cell)
		p = guess(mid.x, mid.y, _cell_meta(cell))
	_lock.lock()
	_cells[key] = p
	_lock.unlock()
	return p


## The profile of the cell that (lat, lon) is in.
static func at(lat: float, lon: float) -> Dictionary:
	return of_cell(RealRegion.cell_of(lat, lon))


## The profile of a region or journey: a bundled region's own (data/profiles), else the cell at its frame's middle.
static func of_region(region: RealRegion) -> Dictionary:
	var path := BUNDLED_DIR.path_join("%s.json" % region.id)
	if region.id != "" and FileAccess.file_exists(path):
		var v = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			return parse(v)
	return at(region.frame_lat, region.frame_lon)


## Whether the game has a profile of its own for bundled region `region_id` (data/profiles).
static func bundled(region_id: String) -> bool:
	return region_id != "" and FileAccess.file_exists(BUNDLED_DIR.path_join("%s.json" % region_id))


## Where cell "ROW_COL"'s profile is in the world's store, beside its index.
static func profile_url(cell: String) -> String:
	return CellStore.index_url.get_base_dir().path_join("profile/c%s.json" % cell)


## Forgets the profiles asked for (the tests change where they come from).
static func forget() -> void:
	_lock.lock()
	_cells = {}
	_lock.unlock()


## Profile `d` with every field there: any missing, or of the wrong kind, takes its default; an open sea cell's
## missing climate is guessed from its latitude.
static func parse(d: Dictionary) -> Dictionary:
	var lat := float(d.get("lat", 0.0))
	var lon := float(d.get("lon", 0.0))
	var p := _defaults(lat, lon)
	for k in p:
		if not d.has(k) or d[k] == null:
			continue
		var want: int = typeof(p[k])
		var got: int = typeof(d[k])
		if want == got or (want == TYPE_FLOAT and got == TYPE_INT) or (want == TYPE_NIL and got == TYPE_DICTIONARY):
			p[k] = d[k]
	for k in d:
		if not p.has(k):
			p[k] = d[k]   # (fields a later format adds: kept, for whoever knows them)
	var cover := {}
	for c in COVER:
		cover[c] = float((p["cover"] as Dictionary).get(c, 0.0))
	p["cover"] = cover
	var alt: Dictionary = p["altitude"]
	p["altitude"] = {"min": int(alt.get("min", 0)), "mean": int(alt.get("mean", 0)), "max": int(alt.get("max", 0))}
	var clim: Dictionary = p["climate"]
	var model := _climate_model(lat, float(p["altitude"]["mean"]))
	var out := {}
	for k in CLIMATE_KEYS:
		var v = clim.get(k)
		out[k] = v if v is Array and (v as Array).size() == 12 else model[k]
	p["climate"] = out
	p["format"] = int(p["format"])
	return p


## The months' climate of profile `p` for `month` (1 to 12): {temp_c, temp_min_c, temp_max_c, rain_mm, rain_days, sun_h}.
static func month(p: Dictionary, m: int) -> Dictionary:
	var i := clampi(m, 1, 12) - 1
	var out := {}
	for k in CLIMATE_KEYS:
		out[k] = float((p["climate"][k] as Array)[i])
	return out


## A profile made from what the game has offline: latitude and altitude for the climate and its zone, the world's
## towns (data/world/places.json) for the country, and `meta` (a region.json: its sea and road rules) where given.
static func guess(lat: float, lon: float, meta := {}) -> Dictionary:
	var p := _defaults(lat, lon)
	var cell := RealRegion.cell_of(lat, lon)
	p["cell"] = "%d_%d" % [cell.x, cell.y]
	p["lat"] = lat
	p["lon"] = lon
	var country := _nearest_country(lat, lon)
	var rules := str(meta.get("region", ""))
	if ROAD_REGIONS.has(rules):
		country = ROAD_REGIONS[rules]
	p["country"] = country[0]
	p["country_name"] = country[1]
	p["countries"] = [[country[0], 1.0]] if country[0] != "" else []
	var sea := bool(meta.get("sea", false))
	p["sea"] = 0.2 if sea else 0.0
	p["coast"] = sea
	p["climate"] = _climate_model(lat, 100.0)
	p["koppen"] = koppen_of(p["climate"], lat)
	p["cover"] = _cover_for(str(p["koppen"]))
	p["built"] = p["cover"]["urban"]
	p["density"] = band(float(p["built"]), DENSITIES)
	p["altitude"] = {"min": 0, "mean": 100, "max": 200}
	p["altitude_band"] = band(100.0, ALTITUDE_BANDS)
	p["guessed"] = true
	return p


## The first band whose limit `value` is under: ALTITUDE_BANDS or DENSITIES.
static func band(value: float, bands: Array) -> String:
	for b in bands:
		if value < float(b[0]):
			return b[1]
	return bands[-1][1]


## A rough Köppen-Geiger zone of a year's climate (as profile.climate) at `lat`: its main group and second letter, and
## the summer's third.
static func koppen_of(climate: Dictionary, lat: float) -> String:
	var t: Array = climate["temp_c"]
	var r: Array = climate["rain_mm"]
	var hot: float = t.max()
	var cold: float = t.min()
	var mean := 0.0
	var rain := 0.0
	for i in 12:
		mean += float(t[i]) / 12.0
		rain += float(r[i])
	if hot < 0.0:
		return "EF"
	if hot < 10.0:
		return "ET"
	# Dry: less rain than the heat takes (Köppen's threshold, rain spread through the year).
	if rain < 20.0 * mean + 140.0:
		return ("BW" if rain < 10.0 * mean + 70.0 else "BS") + ("h" if mean >= 18.0 else "k")
	if cold >= 18.0:
		return "Af" if r.min() >= 60.0 else "Aw"
	var summer := "a" if hot >= 22.0 else "b"
	return ("C" if cold > -3.0 else "D") + "f" + summer


## A smooth climate by latitude and height: warmer to the equator and lower down, the seasons wider further from it,
## the subtropics dry and sunny, the tropics wet.
static func _climate_model(lat: float, alt: float) -> Dictionary:
	var a := absf(lat)
	var mean := 27.0 - 0.4 * maxf(0.0, a - 10.0) - 0.006 * pow(maxf(0.0, a - 50.0), 2.0) - 0.0065 * alt
	var swing := clampf(0.15 * (a - 5.0), 0.5, 12.0)
	var dry := clampf(1.0 - absf(a - 24.0) / 8.0, 0.0, 1.0)
	var wet := clampf(1.0 - a / 12.0, 0.0, 1.0)
	var out := {}
	for k in CLIMATE_KEYS:
		out[k] = []
	for m in 12:
		# (coldest in the middle of January in the north, of July in the south)
		var phase := cos(TAU * (float(m) - 0.5) / 12.0)
		var t := mean - swing * (phase if lat >= 0.0 else -phase)
		var rain := 70.0 * (1.0 - dry * 0.95) + 110.0 * wet
		var sunny := 0.4 + 0.35 * dry - 0.1 * wet
		out["temp_c"].append(snappedf(t, 0.1))
		out["temp_min_c"].append(snappedf(t - 4.5, 0.1))
		out["temp_max_c"].append(snappedf(t + 4.5, 0.1))
		out["rain_mm"].append(roundi(rain))
		out["rain_days"].append(clampi(roundi(rain / 6.0), 1, 22))
		out["sun_h"].append(roundi(sunny * day_length(lat, m + 1) * MONTH_DAYS[m]))
	return out


## Hours from sunrise to sunset in the middle of month `m` (1 to 12) at `lat` (as tools/profile_bake.py).
static func day_length(lat: float, m: int) -> float:
	var doy: int = [15, 46, 74, 105, 135, 162, 198, 228, 258, 288, 318, 344][clampi(m, 1, 12) - 1]
	var decl := 0.409 * sin(TAU * doy / 365.0 - 1.39)
	var x := -tan(deg_to_rad(lat)) * tan(decl)
	return 24.0 / PI * acos(clampf(x, -1.0, 1.0))


## A cover mix for a guessed profile, by its zone's main group.
static func _cover_for(koppen: String) -> Dictionary:
	var mix := {}
	for c in COVER:
		mix[c] = 0.0
	match koppen.left(1):
		"A":
			mix.merge({"forest": 0.6, "grass": 0.15, "crop": 0.2, "urban": 0.01, "water": 0.04}, true)
		"B":
			mix.merge({"barren": 0.55, "shrub": 0.3, "grass": 0.1, "crop": 0.04, "urban": 0.01}, true)
		"D":
			mix.merge({"forest": 0.6, "grass": 0.15, "crop": 0.15, "wetland": 0.04, "water": 0.05, "urban": 0.01}, true)
		"E":
			mix.merge({"barren": 0.5, "rock": 0.3, "grass": 0.2}, true)
		_:
			mix.merge({"grass": 0.45, "crop": 0.25, "forest": 0.25, "urban": 0.02, "water": 0.03}, true)
	return mix


## The country of the world's town or city nearest (lat, lon), within about 300 km: [code, name], or ["", ""].
static func _nearest_country(lat: float, lon: float) -> Array:
	_load_places()
	var best := 9.0e9
	var name := ""
	var k := cos(deg_to_rad(lat))
	for pl in _places:
		var dlat := float(pl[1]) - lat
		var dlon := wrapf(float(pl[2]) - lon, -180.0, 180.0) * k
		var d := dlat * dlat + dlon * dlon
		if d < best:
			best = d
			name = str(pl[4])
	if best > 2.7 * 2.7 or name == "":
		return ["", ""]
	return [str(_countries.get(name, "")), name]


static func _load_places() -> void:
	_lock.lock()
	if _places.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/places.json"))
		_places = v if v is Array else []
		var c = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/countries.json"))
		_countries = c if c is Dictionary else {}
	_lock.unlock()


## A cell's region.json if the game has the cell, else {}.
static func _cell_meta(cell: Vector2i) -> Dictionary:
	var d := RealRegion.cell_dir(cell)
	if d == "":
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("region.json")))
	return v if v is Dictionary else {}


## Every field at its default (docs/place_profile.md): a mild temperate grassland nobody has profiled.
static func _defaults(lat: float, lon: float) -> Dictionary:
	var cover := {}
	for c in COVER:
		cover[c] = 0.0
	cover["grass"] = 1.0
	return {
		"format": FORMAT, "cell": "", "lat": lat, "lon": lon, "guessed": true,
		"country": "", "country_name": "", "countries": [], "region": "", "region_code": "",
		"koppen": "Cfb", "cover": cover, "sea": 0.0, "coast": false,
		"altitude": {"min": 0, "mean": 100, "max": 200}, "altitude_band": "lowland",
		"built": 0.0, "density": "rural", "climate": {}, "tint": null,
		"sources": {}, "bake_key": "", "hash": "",
	}
