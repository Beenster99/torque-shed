extends RefCounted
## Sound of place (PlaceSound, RideAmbience): the eight postcard places each sound different, the rules that choose a
## place's sounds, the mix by day, night and rain, the bells and the call to prayer at their hours, the radio by country
## and the recordings with their licences. Plain data in and out, no scene, so each runs in a moment. Run from
## tests/run_tests.gd (its _test_place_sound_* functions hand over to these).

var t: Node   # the test runner: check()

## The postcard places (hand-made profiles in PlaceProfile's shape; Dales and Atlas are T1's own examples).
const PLACES := ["dales", "bavaria", "atlas", "oaxaca", "shodoshima", "coromandel", "pyrenees", "polder"]
const FIXTURES := "res://tests/fixtures/sound_of_place/"


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func profile(place: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + place + ".json"))


## What you'd hear with your eyes shut: every bed and timed sound that plays, by day and by night.
static func heard(chosen: Dictionary) -> Array:
	var out := []
	for id in chosen["layers"]:
		var l: Dictionary = chosen["layers"][id]
		if float(l["day"]) > 0.05:
			out.append(str(id))
		if float(l["night"]) > 0.05:
			out.append(str(id) + "@night")
	for id in chosen["events"]:
		out.append(str(id))
	out.sort()
	return out


func test_eight_places() -> void:
	for month in [7, 10]:
		var sets := {}
		for place in PLACES:
			sets[place] = heard(PlaceSound.choose(profile(place), month))
			if t.verbose:
				print("    %s in month %d: %s" % [place, month, ", ".join(sets[place])])
		var close := []
		for i in PLACES.size():
			for j in range(i + 1, PLACES.size()):
				var a: Array = sets[PLACES[i]]
				var b: Array = sets[PLACES[j]]
				var differ := a.filter(func(x): return not (x in b)).size() + b.filter(func(x): return not (x in a)).size()
				if differ < 3:
					close.append("%s/%s" % [PLACES[i], PLACES[j]])
		check(close.is_empty(), "in month %d the eight postcard places each sound different (at least three sounds apart)%s" % [month, "" if close.is_empty() else ": too close " + ", ".join(close)])


func test_rules() -> void:
	var july := {}
	for place in PLACES:
		july[place] = heard(PlaceSound.choose(profile(place), 7))
	var has := func(place: String, sounds: Array) -> bool:
		return sounds.all(func(s): return s in july[place])
	check(has.call("dales", ["birds_moor", "sheep", "church_bells"]), "the Dales: curlews and skylarks on the moor, sheep, the village church")
	check(has.call("atlas", ["birds_arid", "goatbells", "call_to_prayer"]) and not ("church_bells" in july["atlas"]), "the Atlas: dry-country birds, goat bells and the call to prayer, no church bells")
	check(has.call("shodoshima", ["birds_east_asia", "cicadas_east_asia", "surf", "temple_bell", "frogs@night"]), "Shodoshima in July: Japan's birds and cicadas, the sea, the temple bell, frogs at night")
	check(has.call("coromandel", ["birds_nz", "surf"]), "Coromandel: tui and bellbirds, and the surf")
	check(has.call("polder", ["birds_wetland", "bicycles"]) and not has.call("polder", ["stream"]), "the polder: lapwings and bicycle bells, and no mountain stream")
	check(has.call("bavaria", ["cowbells", "church_bells", "birds_temperate"]), "Bavaria: cowbells on the hill pastures and the church")
	check(has.call("pyrenees", ["birds_alpine", "stream", "cowbells"]), "the Pyrenees: choughs round the crags, a mountain stream and cowbells")
	check(has.call("oaxaca", ["market_latin", "cicadas", "church_bells", "traffic"]), "Oaxaca: the market, cicadas, church bells and horns")
	# Seasons: the Dales' crickets never come out, Shodoshima's cicadas are gone by October and Coromandel's July is winter.
	var october := heard(PlaceSound.choose(profile("shodoshima"), 10))
	check(not ("cicadas_east_asia" in october) and "crickets@night" in october, "Shodoshima in October: the cicadas are over, crickets sing at night")
	var nz_july := PlaceSound.choose(profile("coromandel"), 7)
	var nz_jan := PlaceSound.choose(profile("coromandel"), 1)
	check(float(nz_july["layers"]["birds_nz"]["day"]) < float(nz_jan["layers"]["birds_nz"]["day"]) or not nz_july["layers"].has("crickets"), "Coromandel's July is its winter: quieter than January")
	check(not ("crickets@night" in july["dales"]) and not ("frogs@night" in july["dales"]), "nights in the Dales are too cold for crickets and frogs")
	# A guessed profile with nothing but its defaults still gets a sound (wind and birds), and nowhere gets nothing.
	var bare := PlaceSound.choose({}, 6)
	check(bare["layers"].has("wind") and bare["layers"].has("birds_temperate") and bare["events"].is_empty(), "an empty profile still has wind and birds, and no town")


func test_mix() -> void:
	var chosen := PlaceSound.choose(profile("oaxaca"), 7)
	var noon := PlaceSound.mix(chosen, 0.0, 12.0)
	var night := PlaceSound.mix(chosen, 1.0, 1.0)
	var dawn := PlaceSound.mix(chosen, 0.0, 6.5)
	var wet := PlaceSound.mix(chosen, 0.0, 12.0, 1.0)
	check(float(noon["birds_tropical"]) > 0.1 and float(night["birds_tropical"]) == 0.0, "birds sing by day, not at night")
	check(float(dawn["birds_tropical"]) > float(noon["birds_tropical"]), "and loudest at dawn")
	check(float(night["crickets"]) > 0.1 and float(noon["crickets"]) == 0.0, "crickets at night")
	check(float(night["market_latin"]) < float(noon["market_latin"]) * 0.5, "the market is quiet at night")
	check(float(wet["birds_tropical"]) < float(noon["birds_tropical"]) * 0.3 and float(wet["wind"]) > float(noon["wind"]), "rain hushes the birds and the wind gets up")
	var outside := []
	for levels: Dictionary in [noon, night, dawn, wet]:
		for id in levels:
			if float(levels[id]) < 0.0 or float(levels[id]) > 1.0:
				outside.append(id)
	check(outside.is_empty(), "every level stays between 0 and 1%s" % ("" if outside.is_empty() else ": not " + ", ".join(outside)))


func test_due() -> void:
	var dales := PlaceSound.choose(profile("dales"), 7)
	var due := PlaceSound.due(dales, 8.9, 9.1)
	check(due.size() == 1 and due[0][0] == "church_bells" and int(due[0][2]) == 9, "the church tolls nine at nine o'clock")
	check(PlaceSound.due(dales, 9.1, 9.9).is_empty(), "and nothing between the hours")
	check(PlaceSound.due(dales, 21.0, 23.9).is_empty(), "and not at night")
	var atlas := PlaceSound.choose(profile("atlas"), 7)
	var day := PlaceSound.due(atlas, 0.0, 24.0).map(func(d): return d[0])
	check(day.count("call_to_prayer") == 5 and not ("church_bells" in day), "the call to prayer five times a day in the Atlas")
	check(PlaceSound.due(atlas, 23.5, 29.5).map(func(d): return d[0]) == ["call_to_prayer"], "including the dawn call, past midnight")
	var japan := PlaceSound.choose(profile("shodoshima"), 7)
	check(PlaceSound.due(japan, 0.0, 24.0).map(func(d): return d[0]) == ["temple_bell", "temple_bell"], "the temple bell at dawn and dusk")


func test_radio() -> void:
	var langs := {"GB": "english", "DE": "german", "MA": "arabic", "MX": "spanish", "JP": "japanese", "NZ": "english", "FR": "french", "NL": "dutch"}
	for place in PLACES:
		var country := str(profile(place)["country"])
		var chosen := PlaceSound.choose(profile(place), 7)
		var list := PlaceSound.stations(chosen["radio"])
		var ok := list.size() >= 3
		for s: Dictionary in list:
			ok = ok and str(s["url"]).begins_with("http") and str(s["name"]) != "" and str(s["genre"]) != ""
		check(ok and chosen["radio"] == country, "%s's radio has %d of %s's stations" % [place, list.size(), country])
		check(str(PlaceSound.radio()[country]["language"]) == langs[country], "in %s" % langs[country])
	check(PlaceSound.radio().size() > 150, "and %d countries have their own radio" % PlaceSound.radio().size())
	check(PlaceSound.stations("").is_empty() and PlaceSound.radio_country("") == "", "out at sea, no local radio")


func test_files() -> void:
	var missing := []
	var unlicensed := []
	var stereo := []
	var sounds := {}
	for group in ["layers", "events"]:
		for id in PlaceSound.data()[group]:
			sounds[PlaceSound.sound_of(id)] = true
	for sound: String in sounds:
		if sound.begins_with("synth:"):
			continue
		var path := PlaceSound.DIR + sound + ".ogg"
		if not FileAccess.file_exists(path):
			missing.append(sound)
			continue
		var licence := FileAccess.get_file_as_string(path + ".licence.txt")
		if not ("Licence:" in licence and "Source:" in licence and "Author:" in licence):
			unlicensed.append(sound)
		if RideAmbience.channels(path) != 1:
			stereo.append(sound)
	check(missing.is_empty(), "every sound of place has its recording%s" % ("" if missing.is_empty() else ": missing " + ", ".join(missing)))
	check(unlicensed.is_empty(), "each with its licence, source and author beside it%s" % ("" if unlicensed.is_empty() else ": not " + ", ".join(unlicensed)))
	check(stereo.is_empty(), "and mono, to keep them small%s" % ("" if stereo.is_empty() else ": stereo " + ", ".join(stereo)))


func test_ride() -> void:
	# How built up it is round you, from the buildings near the road: none is open country, a cluster a village.
	var pack := RealPack.new()
	var row := func(n: int, x: float) -> Array:
		var out := []
		for i in n:
			out.append([x + i, 10.0, 8.0, 8.0, 0.0, 6.0, "house", 0])
		return out
	pack.buildings = {0: row.call(3, 0.0) + row.call(40, 2000.0)}
	check(RideAmbience.density_of(pack, 0, 0.0, 0.0) == "rural", "three houses by the road is still the country (and a town 2 km off isn't heard)")
	pack.buildings = {0: row.call(10, 0.0), 1: row.call(4, 120.0)}
	check(RideAmbience.density_of(pack, 0, 0.0, 0.0) == "village", "fourteen is a village")
	pack.buildings = {0: row.call(30, 0.0), 2: row.call(50, 250.0)}
	check(RideAmbience.density_of(pack, 1, 100.0, 0.0) == "city", "eighty is a city")
	# The ride's ambience plays the place's beds, eased in, and chooses again as it gets more built up.
	var amb := RideAmbience.new()
	t.add_child(amb)
	amb.setup(profile("atlas"), 7)
	for i in 40:
		amb._process_body(0.25)
	var wind: AudioStreamPlayer = amb.players.get("wind")
	check(wind != null and wind.playing and wind.volume_db > -40.0, "out in the Atlas the wind blows")
	var recorded := ResourceLoader.exists(PlaceSound.DIR + "birds_arid.ogg")
	check(not recorded or (amb.players.has("birds_arid") and amb.players["birds_arid"].playing), "and its birds sing")
	check(not amb.players.has("church_bells") and amb.chosen["events"].has("call_to_prayer"), "the call to prayer, not church bells, is due")
	amb._rechoose("city")
	check(float(amb.chosen["layers"]["market_maghreb"]["day"]) > 0.8 and float(amb.chosen["layers"]["traffic"]["day"]) > 0.5, "riding into town: the souk and the horns")
	amb.queue_free()
