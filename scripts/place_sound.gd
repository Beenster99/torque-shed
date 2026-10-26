class_name PlaceSound
extends RefCounted
## What a place sounds like on a ride, from its place profile (PlaceProfile; see the fields there): which looped beds
## play (wind, the birds of its climate and cover, cicadas, crickets and frogs when the month is warm enough, a mountain
## stream, the surf on a coast, sheep, cowbells or goat bells where they graze, a market, horns, scooters and bicycle
## bells in a town) and how loud by day and by night, the bells or the call to prayer that sound at their hours, and
## whose radio is on. Plain data in, plain data out (nothing here touches a scene), so the eight postcard places can be
## told apart in a test; RideAmbience plays what it chooses. The sounds and the country lists are in DATA.

const DATA := "res://data/sound_of_place.json"
const RADIO := "res://data/radio_by_country.json"
## Where the recordings are: <sound>.ogg, each with <sound>.ogg.licence.txt beside it.
const DIR := "res://audio/place/"
## How built up each density is (PlaceProfile's density), for the town's sounds: 0 out in the wild, 1 in a city.
const DENSITY := {"wild": 0.0, "rural": 0.15, "village": 0.4, "town": 0.7, "city": 1.0}
## How much windier each altitude band is.
const ALTITUDE_WIND := {"lowland": 0.0, "upland": 0.15, "mountain": 0.3, "high": 0.45}

## The month's mean night-time low (°C) warm enough for crickets and frogs to sing.
const WARM_NIGHT := 12.0

static var _data := {}
static var _radio := {}


## The sound data (DATA), read once.
static func data() -> Dictionary:
	if _data.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = v if v is Dictionary else {"layers": {}, "events": {}, "countries": {}}
	return _data


## The place's sounds in `month` (1..12): {layers: {id: {day, night}} (0..1 each, only those that play),
## events: {id: level} (bells, the call to prayer), country, radio: the country whose stations play}.
static func choose(profile: Dictionary, month: int) -> Dictionary:
	var lists: Dictionary = data()["countries"]
	var country := str(profile.get("country", ""))
	var k := str(profile.get("koppen", "Cfb"))
	var zone := k.left(1)
	var cover: Dictionary = profile.get("cover", {})
	var c := func(key: String) -> float: return float(cover.get(key, 0.0))
	var forest: float = c.call("forest")
	var open: float = c.call("grass") + c.call("crop") + c.call("shrub") + c.call("barren") + c.call("sand") + c.call("rock") + c.call("wetland")
	var wet: float = c.call("wetland") + c.call("water")
	var band := str(profile.get("altitude_band", "lowland"))
	var high := band != "lowland"
	var coast := bool(profile.get("coast", false))
	var town := float(DENSITY.get(str(profile.get("density", "rural")), 0.15))
	var m := _month(profile, month)
	var layers := {}
	# Wind: always, more in the open, up high and by the sea, less among trees.
	var wind := clampf(0.35 + 0.3 * open + float(ALTITUDE_WIND.get(band, 0.0)) + (0.15 if coast else 0.0) - 0.2 * forest, 0.2, 1.0)
	layers["wind"] = {"day": wind, "night": wind * 0.8}
	# Birds: one chorus, by climate and cover, quieter in winter and in towns; none at night.
	var birds := bird_kind(profile)
	var season := 1.0 if zone == "A" else clampf((float(m["temp_c"]) + 2.0) / 10.0, 0.15, 1.0)
	layers[birds] = {"day": season * lerpf(1.0, 0.5, town), "night": 0.0}
	# Insects: cicadas on hot days, crickets on warm nights, frogs on warm wet nights.
	if float(m["temp_max_c"]) >= 25.0 and zone != "E":
		var cicadas := str((lists["cicadas"] as Dictionary).get(country, "cicadas"))
		layers[cicadas] = {"day": clampf((float(m["temp_max_c"]) - 24.0) / 6.0, 0.2, 1.0) * clampf(0.4 + forest + c.call("shrub"), 0.0, 1.0), "night": 0.0}
	if float(m["temp_min_c"]) >= WARM_NIGHT and zone != "E":
		layers["crickets"] = {"day": 0.0, "night": clampf((float(m["temp_c"]) - 10.0) / 8.0, 0.2, 1.0) * (1.0 - 0.5 * town)}
	if float(m["temp_min_c"]) >= WARM_NIGHT and (float(m["rain_mm"]) >= 80.0 or wet >= 0.08 or (zone == "A")):
		layers["frogs"] = {"day": 0.0, "night": clampf(float(m["rain_mm"]) / 200.0 + wet * 3.0, 0.25, 1.0)}
	# Water: a stream in wet hills, the surf on a coast.
	var rain_year := 0.0
	for r in (profile.get("climate", {}) as Dictionary).get("rain_mm", []):
		rain_year += float(r)
	if high and (rain_year >= 600.0 or forest >= 0.3) and zone != "B":
		layers["stream"] = {"day": 0.5, "night": 0.6}
	if coast:
		var surf := clampf(0.4 + float(profile.get("sea", 0.0)), 0.4, 1.0)
		layers["surf"] = {"day": surf, "night": surf}
	# Animals out grazing, where the country keeps them and the land suits: out in the country, by day.
	var grazing := livestock(profile)
	if grazing != "":
		var out := 1.0 - town
		layers[grazing] = {"day": out, "night": out * 0.1}
	# The town: a market by day, horns, scooters and bicycle bells, all as built up as the place is.
	if town > 0.0:
		var market := str((lists["market"] as Dictionary).get(country, "market"))
		layers[market] = {"day": town * 0.9, "night": town * 0.15}
		var horns := _share(lists["horns"], country) * town
		if horns > 0.02:
			layers["traffic"] = {"day": horns, "night": horns * 0.4}
		var scooters := _share(lists["scooters"], country) * town
		if scooters > 0.02:
			layers["scooters"] = {"day": scooters, "night": scooters * 0.3}
		var bikes := _share(lists["bicycles"], country) * maxf(town, 0.3)
		if bikes > 0.02:
			layers["bicycles"] = {"day": bikes, "night": bikes * 0.1}
	# Bells and the call to prayer carry: heard faintly even from the fields, but not out in the wild.
	var events := {}
	var carry := 0.0 if town <= 0.0 else clampf(0.35 + town, 0.0, 1.0)
	if carry > 0.0:
		for e in town_events(country):
			events[e] = carry
	return {"layers": layers, "events": events, "country": country, "radio": radio_country(country)}


## Which chorus of birds sings here: the country's own (New Zealand's, East Asia's) or by climate and cover (choughs
## among the crags of a mountain, curlews and skylarks on an upland moor, lapwings on wet lowland).
static func bird_kind(profile: Dictionary) -> String:
	var country := str(profile.get("country", ""))
	var own: Dictionary = data()["countries"]["birds"]
	if own.has(country):
		return str(own[country])
	var k := str(profile.get("koppen", "Cfb"))
	var cover: Dictionary = profile.get("cover", {})
	var wet := float(cover.get("wetland", 0.0)) + float(cover.get("water", 0.0))
	var open := 1.0 - float(cover.get("forest", 0.0)) - float(cover.get("urban", 0.0)) - float(cover.get("water", 0.0))
	if k.begins_with("A"):
		return "birds_tropical"
	if k.begins_with("B"):
		return "birds_arid"
	var band := str(profile.get("altitude_band", "lowland"))
	var bare := float(cover.get("rock", 0.0)) + float(cover.get("barren", 0.0))
	if band in ["mountain", "high"] and bare >= 0.1:
		return "birds_alpine"
	if wet >= 0.12 and band == "lowland":
		return "birds_wetland"
	if open >= 0.6 and float(cover.get("forest", 0.0)) < 0.25 and band != "lowland":
		return "birds_moor"
	if k.begins_with("Cs"):
		return "birds_med"
	if k.begins_with("Cw"):
		return "birds_tropical"
	return "birds_temperate"


## What grazes here, heard by its bells or its bleating: "cowbells" on the alpine countries' hill pastures, "goatbells"
## on dry scrubby hills where goats are kept, "sheep" on open grassland where the country keeps sheep; "" for none.
static func livestock(profile: Dictionary) -> String:
	var country := str(profile.get("country", ""))
	var lists: Dictionary = data()["countries"]
	var cover: Dictionary = profile.get("cover", {})
	var grass := float(cover.get("grass", 0.0))
	var scrub := float(cover.get("shrub", 0.0)) + float(cover.get("barren", 0.0)) + float(cover.get("rock", 0.0))
	var high := str(profile.get("altitude_band", "lowland")) != "lowland"
	if country in lists["goats"] and scrub >= 0.3 and scrub > grass:
		return "goatbells"
	if country in lists["cows"] and high and grass >= 0.2:
		return "cowbells"
	if country in lists["sheep"] and grass + float(cover.get("shrub", 0.0)) >= 0.3:
		return "sheep"
	return ""


## The town's timed sounds in `country`: its church bells, temple bell or call to prayer (or both, where both are heard).
static func town_events(country: String) -> Array:
	var lists: Dictionary = data()["countries"]
	if country == "":
		return []
	var out := []
	if country in lists["prayer"]:
		out.append("call_to_prayer")
	if country in lists["temple"]:
		out.append("temple_bell")
	elif not (country in lists["prayer"]) or country in lists["prayer_and_church"]:
		out.append("church_bells")
	return out


## How loud each of `chosen`'s beds is now (0..1), `dark` being how dark it is (Daylight.darkness), `hour` the time of
## day (birds loudest at dawn, the market busiest late morning) and `rain` how hard it's raining (0..1).
static func mix(chosen: Dictionary, dark: float, hour: float, rain := 0.0) -> Dictionary:
	var out := {}
	var dawn := clampf(1.0 - absf(hour - 6.5) / 2.0, 0.0, 1.0)
	for id in chosen["layers"]:
		var l: Dictionary = chosen["layers"][id]
		var level := lerpf(float(l["day"]), float(l["night"]), clampf(dark, 0.0, 1.0))
		if str(id).begins_with("birds"):
			level = minf(level * (1.0 + 0.6 * dawn), 1.0) * (1.0 - rain * 0.85)
		elif str(id) in ["cicadas", "cicadas_east_asia", "crickets"]:
			level *= 1.0 - rain * 0.8
		elif str(id) == "wind":
			level = minf(level + rain * 0.3, 1.0)
		elif str(id) == "frogs":
			level = minf(level * (1.0 + rain * 0.5), 1.0)
		out[id] = level
	return out


## The timed sounds due between `from` and `to` (hours of the day, `to` past `from`; wraps past midnight), each as
## [event id, hour, how many strokes (the church bells toll the hour; 1 for the others)].
static func due(chosen: Dictionary, from: float, to: float) -> Array:
	var out := []
	var events: Dictionary = data()["events"]
	for id in chosen["events"]:
		for h in (events[id] as Dictionary).get("hours", []):
			var at := float(h)
			for day in [0.0, 24.0]:
				if at + day > from and at + day <= to:
					var strokes := (int(at) % 12 if int(at) % 12 != 0 else 12) if id == "church_bells" else 1
					out.append([id, at, strokes])
	return out


## The country whose radio plays: `country`'s own when the radio list has it, else "".
static func radio_country(country: String) -> String:
	return country if radio().has(country) else ""


## Every country's stations (RADIO): {"GB": {language, stations: [{name, genre, url, language}]}}.
static func radio() -> Dictionary:
	if _radio.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(RADIO))
		_radio = v if v is Dictionary else {}
	return _radio


## `country`'s radio stations, [{name, genre, url}], or [] when it has none in the list.
static func stations(country: String) -> Array:
	return (radio().get(country, {}) as Dictionary).get("stations", [])


## Where a bed's recording is: res://audio/place/<sound>.ogg, or the synth's sound "synth:<name>".
static func sound_of(id: String) -> String:
	var d: Dictionary = data()["layers"].get(id, data()["events"].get(id, {}))
	return str(d.get("sound", id))


## A bed's or an event's full level (dB).
static func db_of(id: String) -> float:
	var d: Dictionary = data()["layers"].get(id, data()["events"].get(id, {}))
	return float(d.get("db", -14.0))


## The month's climate from the profile's normals, with a mild year where it has none.
static func _month(profile: Dictionary, month: int) -> Dictionary:
	var climate: Dictionary = profile.get("climate", {})
	var i := clampi(month, 1, 12) - 1
	var out := {}
	var mild := {"temp_c": 12.0, "temp_min_c": 7.0, "temp_max_c": 17.0, "rain_mm": 70.0}
	for key in mild:
		var a: Array = climate.get(key, [])
		out[key] = float(a[i]) if a.size() == 12 else float(mild[key])
	return out


static func _share(table: Dictionary, country: String) -> float:
	return float(table.get(country, table.get("_default", 0.0)))
