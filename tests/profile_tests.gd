extends RefCounted
## Place profiles (tools/profile_bake.py, PlaceProfile): what each cell of the world is like. Run from tests/run_tests.gd
## (its _test_profile_* functions hand over to these). Nothing here touches the network or loads a scene.
##
## The fixtures: tests/fixtures/profiles holds two profiles as docs/place_profile.md sets them out, a Dales cell's and a
## High Atlas cell's (realistic numbers, made by hand).

const FIXTURES := "res://tests/fixtures/profiles"
const FIELDS := ["format", "cell", "lat", "lon", "guessed", "country", "country_name", "countries", "region",
	"region_code", "koppen", "cover", "sea", "coast", "altitude", "altitude_band", "built", "density", "climate", "tint",
	"sources", "bake_key", "hash"]

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _fixture(cell: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURES.path_join("c%s.json" % cell)))


func _complete(p: Dictionary) -> bool:
	for k in FIELDS:
		if not p.has(k):
			return false
	for c in PlaceProfile.COVER:
		if not (p["cover"] as Dictionary).has(c):
			return false
	for k in PlaceProfile.CLIMATE_KEYS:
		if not p["climate"].get(k) is Array or (p["climate"][k] as Array).size() != 12:
			return false
	return true


## A baked profile reads as it is; a part one, or one with fields of the wrong kind, has its gaps filled.
func test_parse() -> void:
	var dales := PlaceProfile.parse(_fixture("576_712"))
	check(_complete(dales), "a baked profile has every field (%s)" % str(dales.keys()))
	check(dales["country"] == "GB" and dales["koppen"] == "Cfb" and not dales["guessed"] and dales["altitude"]["max"] == 716,
		"and its own values")
	check(is_equal_approx(PlaceProfile.month(dales, 7)["temp_c"], 14.4) and PlaceProfile.month(dales, 1)["sun_h"] == 42.0,
		"a month's climate is that month's (July %s)" % str(PlaceProfile.month(dales, 7)))
	var atlas := PlaceProfile.parse(_fixture("484_688"))
	check(atlas["tint"] is Dictionary and (atlas["tint"]["rgb"] as Array).size() == 3, "a tint, when there is one, is kept")
	var bit := PlaceProfile.parse({"lat": 54.1, "lon": -1.9, "country": "GB", "sea": 1, "cover": {"forest": 0.5},
		"altitude": "high", "climate": null, "future_field": 3})
	check(_complete(bit), "a part profile is filled out")
	check(bit["country"] == "GB" and is_equal_approx(bit["sea"], 1.0) and is_equal_approx(bit["cover"]["forest"], 0.5)
		and bit["cover"]["grass"] == 0.0, "what it has is kept (a whole number where a fraction goes too)")
	check(bit["altitude"] is Dictionary and bit["future_field"] == 3, "a field of the wrong kind takes its default; one it doesn't know stays")
	check(PlaceProfile.month(bit, 1)["temp_c"] < PlaceProfile.month(bit, 7)["temp_c"], "an open sea cell's climate comes from its latitude")


## A guessed profile, from what the game has offline: the country of the nearest town, a climate by latitude.
func test_guess() -> void:
	var dales := PlaceProfile.guess(54.3, -1.9)
	check(_complete(dales) and dales["guessed"], "a guess has every field, and says it is one")
	check(dales["country"] == "GB" and dales["country_name"] == "United Kingdom", "the Dales are in Britain (%s)" % dales["country"])
	check(dales["cell"] == "577_712", "its cell is the baker's")
	check(str(dales["koppen"]).begins_with("C"), "and temperate (%s)" % dales["koppen"])
	var sahara := PlaceProfile.guess(23.0, 5.5)
	check(sahara["country"] == "DZ" and str(sahara["koppen"]).begins_with("BW"), "the Sahara is a desert in Algeria (%s, %s)" % [sahara["country"], sahara["koppen"]])
	check(sahara["cover"]["barren"] > 0.4 and PlaceProfile.month(sahara, 7)["sun_h"] > PlaceProfile.month(dales, 7)["sun_h"],
		"bare and sunnier")
	check(str(PlaceProfile.guess(78.2, 15.6)["koppen"]).begins_with("E"), "Svalbard is polar")
	check(str(PlaceProfile.guess(1.3, 103.8)["koppen"]).begins_with("A"), "Singapore tropical")
	var south := PlaceProfile.guess(-37.8, 145.0)
	check(PlaceProfile.month(south, 1)["temp_c"] > PlaceProfile.month(south, 7)["temp_c"] and south["country"] == "AU",
		"in the south January is summer (Melbourne)")
	check(PlaceProfile.guess(-40.0, -30.0)["country"] == "", "mid-ocean is no country")
	check(PlaceProfile.guess(54.3, -1.9, {"sea": true})["coast"], "a cell its region.json says has the sea has a coast")
	check(PlaceProfile.band(310.0, PlaceProfile.ALTITUDE_BANDS) == "upland" and PlaceProfile.band(0.03, PlaceProfile.DENSITIES) == "village",
		"the bands are the baker's")


## A cell's profile is the world store's when its index has one (kept on disk), else a guess; a bundled region has its own.
func test_of_cell() -> void:
	var store := "user://test_profiles"
	RegionStore._remove_tree(store)
	DirAccess.make_dir_recursive_absolute(store.path_join("profile"))
	var text := JSON.stringify(_fixture("576_712"))
	var f := FileAccess.open(store.path_join("profile/c576_712.json"), FileAccess.WRITE)
	f.store_string(text + "\n")
	f.close()
	var index := {"format": 1, "cells": {"576_712": {"hash": "x"}}, "profiles": {"576_712": text.sha1_text().left(12)}}
	f = FileAccess.open(store.path_join("index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(index))
	f.close()
	var was_dir := CellStore.dir
	var was_offline := CellStore.offline
	CellStore.dir = store
	CellStore.offline = true
	CellStore.forget_index()
	PlaceProfile.forget()
	var baked := PlaceProfile.of_cell(Vector2i(576, 712))
	check(not baked["guessed"] and baked["hash"] == "fixture00000" and _complete(baked), "a cell the store has a profile for gets it")
	check(PlaceProfile.at(54.2, -1.8)["hash"] == "fixture00000", "and so does any place in it")
	var other := PlaceProfile.of_cell(Vector2i(484, 688))
	check(other["guessed"] and other["country"] == "MA", "a cell with none is guessed (%s)" % other["country"])
	var dales := RealRegion.get_region("dales")
	var bundled := PlaceProfile.of_region(dales)
	check(not bundled["guessed"] and bundled["country"] == "GB" and bundled["region_code"] == "GB-NYK", "the bundled Dales have their own profile")
	check(dales.credits.has(PlaceProfile.CREDIT) and RouteTv.credits_line(dales.credits).contains("ESA WorldCover 2021 with Copernicus Sentinel data (CC BY 4.0)"),
		"and the route planner credits what profiles are made from (%s)" % RouteTv.credits_line(dales.credits))
	CellStore.dir = was_dir
	CellStore.offline = was_offline
	CellStore.forget_index()
	PlaceProfile.forget()
	RegionStore._remove_tree(store)
