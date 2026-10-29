extends RefCounted
## The road markings' and signs' checks (RoadMarkings and SignWords, Ride Anywhere v2 T8), run from tests/run_tests.gd:
## its _test_road_markings_* functions hand over to these. The road network's own small graphs (road_block_tests.gd),
## flat, no scene and no network.

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


static func _kit(code: String, density := "rural") -> Dictionary:
	return RegionKit.choose({"country": code, "altitude_band": "low", "koppen": "Cfb", "density": density})


## Each country's style from its facts, and the stop words all baked.
func test_style() -> void:
	var gb := RoadMarkings.style_of(_kit("GB"))
	check(bool(gb["left"]) and str(gb["give_way"]["kind"]) == "double" and bool(gb["triangle"]),
		"Britain drives on the left, gives way at double broken lines with a triangle before them")
	var us := RoadMarkings.style_of(_kit("US"))
	check(us["centre_col"] == RoadMarkings.PAINT["yellow"] and bool(us["major"].get("double", false))
		and str(us["warning"]) == "diamond", "America's centre lines are yellow, double on main roads; its warnings diamonds")
	var jp := RoadMarkings.style_of(_kit("JP"))
	check(str(jp["stop_word"]) == "止まれ" and str(jp["stop_shape"]) == "triangle" and float(jp["stop_share"]) == 1.0,
		"Japan's side roads stop, at a triangle saying 止まれ")
	check(str(RoadMarkings.style_of(_kit("MX"))["stop_word"]) == "ALTO", "Mexico's stop signs say ALTO")
	check(str(RoadMarkings.style_of(_kit("MA"))["stop_word"]) == "قف", "Morocco's say قف")
	check(str(RoadMarkings.style_of(_kit("NL"))["give_way"]["kind"]) == "teeth", "the Dutch give way at shark's teeth")
	check(float(RoadMarkings.style_of(_kit("FR"))["edge"]["dash"]) > 0.0, "French edge lines are broken")
	check(RoadMarkings.style_of({}).is_empty(), "no kit, no style (the plain white lines)")
	# The postcards' eight places can't be mistaken for each other.
	var seen := {}
	for code: String in ["GB", "DE", "MA", "MX", "JP", "NZ", "FR", "NL"]:
		var st := RoadMarkings.style_of(_kit(code))
		var sig := "%s|%s|%s|%s|%s|%s|%s|%s" % [st["left"], st["centre_col"], st["edge"], st["give_way"], st["stop_word"],
			st["warning"], st["warning_face"], st["roundabout_sign"]]
		check(not seen.has(sig), "%s is marked unlike %s" % [code, seen.get(sig, "the rest")])
		seen[sig] = code
	var missing := []
	var f := FileAccess.open(RegionKit.COUNTRIES, FileAccess.READ)
	var countries: Dictionary = JSON.parse_string(f.get_as_text())["countries"]
	for code: String in countries:
		var word := str(countries[code]["stop"])
		if not SignWords.has(word):
			missing.append("%s %s" % [code, word])
	check(missing.is_empty(), "every country's stop word is baked (missing: %s)" % [missing])
	var g := SignWords.of("STOP")
	check(float(g["w"]) > 1.5 and (g["tris"] as Array).size() > 100 and (g["tris"] as Array).size() % 6 == 0,
		"a word is a run of whole triangles")


## A tee with a two-lane side road, at (100, 100), the side road south.
static func _tee() -> RealRegion:
	var rb: GDScript = load("res://tests/road_block_tests.gd")
	return rb.graph([[100, 100], [-200, 100], [400, 100], [100, 400]],
		[[1, 0, "primary"], [0, 2, "primary"], [0, 3, "secondary"]])


static func _ok(a: Dictionary) -> bool:
	var v: PackedVector3Array = a["v"]
	if v.size() % 3 != 0 or (a["c"] as PackedColorArray).size() != v.size():
		return false
	for p in v:
		if not p.is_finite():
			return false
	return true


static func _has(a: Dictionary, col: Color) -> bool:
	for c in a["c"]:
		if c.is_equal_approx(col):
			return true
	return false


## The mean x (region frame) of the paint just south of the tee's mouth, off the centre line.
static func _give_way_x(b: RoadBlock, m: Dictionary, mouth: float) -> float:
	var o := b.anchor()
	var sum := 0.0
	var n := 0
	for p: Vector3 in m["lines"]["v"]:
		var w := p + o
		if w.z > 100.0 + mouth and w.z < 100.0 + mouth + 1.2 and absf(w.x - 100.0) > 0.3 and absf(w.x - 100.0) < 3.5:
			sum += w.x
			n += 1
	return sum / n if n > 0 else 100.0


## Painting a block: valid triangles, the country's side and colours, signs, and the same every time.
func test_paint() -> void:
	var net := RoadNet.new(_tee(), load("res://tests/road_block_tests.gd").flat)
	var b := net.block(RoadBlock.key_of(100.0, 100.0))
	var t0 := Time.get_ticks_usec()
	var gb := RoadMarkings.paint(b, _kit("GB"))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var fr := RoadMarkings.paint(b, _kit("FR"))
	var us := RoadMarkings.paint(b, _kit("US"))
	var jp := RoadMarkings.paint(b, _kit("JP"))
	check(RoadMarkings.paint(b, {}).is_empty(), "no kit, no paint")
	for m: Dictionary in [gb, fr, us, jp]:
		check(_ok(m["lines"]) and _ok(m["signs"]), "its paint and signs are whole, finite triangles")
		check((m["lines"]["v"] as PackedVector3Array).size() > 0 and (m["signs"]["v"] as PackedVector3Array).size() > 0,
			"it paints lines and puts up signs")
	var mouth := net.mouth(2, 0)
	var gx := _give_way_x(b, gb, mouth)
	var fx := _give_way_x(b, fr, mouth)
	check(gx < 99.5 and fx > 100.5, "the give-way is across the lane coming in: on the left in Britain (%.1f), the right in France (%.1f)" % [gx, fx])
	check(_has(us["lines"], RoadMarkings.PAINT["yellow"]) and not _has(gb["lines"], RoadMarkings.PAINT["yellow"]),
		"America's centre lines are yellow, Britain's white")
	check(_has(jp["signs"], RoadMarkings.RED) and _has(jp["signs"], RoadMarkings.WHITE), "Japan's stop sign is red and white")
	var again := RoadMarkings.paint(b, _kit("GB"))
	check(again["lines"]["v"] == gb["lines"]["v"] and again["signs"]["v"] == gb["signs"]["v"], "it paints the same every time")
	check(ms < 60.0, "a block paints quickly (%.1f ms)" % ms)
	# In town: Britain's double yellow lines along the kerbs, Morocco's red and white kerbs.
	var gb_town := RoadMarkings.paint(b, _kit("GB", "town"))
	var ma_town := RoadMarkings.paint(b, _kit("MA", "town"))
	check(_has(gb_town["lines"], RoadMarkings.PAINT["yellow"]), "a British town has its double yellow lines")
	check(_has(ma_town["lines"], RegionKit.KERB_PAINT["red_white"][0]) and not _has(RoadMarkings.paint(b, _kit("MA"))["lines"], RegionKit.KERB_PAINT["red_white"][0]),
		"a Moroccan town's kerbs are red and white, its open road's aren't")
	# A roundabout: Europe's blue disc at each entry, not Britain's.
	var rnet := RoadNet.new(load("res://tests/road_block_tests.gd").roundabout(), load("res://tests/road_block_tests.gd").flat)
	var rb := rnet.block(RoadBlock.key_of(100.0, 100.0))
	var rfr := RoadMarkings.paint(rb, _kit("FR"))
	var rgb := RoadMarkings.paint(rb, _kit("GB"))
	check(_has(rfr["signs"], RoadMarkings.BLUE) and not _has(rgb["signs"], RoadMarkings.BLUE),
		"a French roundabout has its blue discs, a British one doesn't")
	# No speed bumps anywhere (Simon, 2026-10-28), not even Mexico's topes; bollards round a town junction's corners.
	var street := RoadNet.new(load("res://tests/road_block_tests.gd").graph([[100, 100], [-200, 100], [490, 100], [100, 500]],
		[[1, 0, "residential"], [0, 2, "residential"], [0, 3, "residential"]]), load("res://tests/road_block_tests.gd").flat)
	var sb := street.block(RoadBlock.key_of(100.0, 100.0))
	var mx_town := RoadMarkings.paint(sb, _kit("MX", "town"))
	check((mx_town["faces"] as PackedVector3Array).is_empty(),
		"a Mexican town street has no topes, nor any other speed bump")
	var gb_street := RoadMarkings.paint(sb, _kit("GB", "town"))
	check((gb_street["faces"] as PackedVector3Array).is_empty(), "nor a British one")
	check(_has(gb_street["signs"], RoadMarkings.BOLLARDS["british_isles"][1]), "a British town junction has its black and gold bollards")
	# Shop names in the country's own words.
	var rng := RandomNumberGenerator.new()
	check(SignWords.shop_words("ja").has(SignWords.shop_word(_kit("JP")["facts"], rng)), "Japan's shops are named in Japanese")
	check(SignWords.shop_words("en-US").has(SignWords.shop_word(_kit("US")["facts"], rng)), "America's in its own English")
	check(SignWords.shop_words("fr").has(SignWords.shop_word(_kit("FR")["facts"], rng)), "France's in French")
	check(not SignWords.shop_words("xx").is_empty(), "a language with no list of its own takes English's")
	var missing := []
	for k: String in ["en", "fr", "de", "nl", "es", "ja", "ar", "th", "ru", "zh", "ko", "el"]:
		for w: String in SignWords.shop_words(k):
			if not SignWords.has(w):
				missing.append(w)
	check(missing.is_empty(), "every shop word is baked (missing: %s)" % [missing])
	# The block draws them: its lines are the country's, and the signs stand with its buildings.
	check(RoadBlock.VERSION >= 5, "the block's version counts the markings")


## A main road west to east through a village (Testby, at 600, 100) with a tee at (100, 100) and a side road south to
## Southam (at 100, 1200); the side road's limit is the map's 48 km/h.
static func _village() -> RealRegion:
	var rb: GDScript = load("res://tests/road_block_tests.gd")
	var r: RealRegion = rb.graph([[100, 100], [-1500, 100], [1500, 100], [100, 1400]],
		[[1, 0, "primary"], [0, 2, "primary"], [0, 3, "secondary"]])
	r.edge_limit[2] = 48
	for k in 34:
		r.buildings.append([500.0 + k * 6.0, 130.0 + (k % 2) * 12.0, 8.0, 8.0, 0.0, 6.0, 0, 0])
	for k in 10:
		r.buildings.append([80.0 + k * 5.0, 1230.0, 8.0, 8.0, 0.0, 6.0, 0, 0])
	r.places = [{"kind": "village", "name": "Testby", "x": 600.0, "z": 100.0, "pop": 0},
		{"kind": "village", "name": "Southam", "x": 100.0, "z": 1200.0, "pop": 0}]
	return r


static func _texts(m: Dictionary) -> Array:
	var out := []
	for l: Dictionary in m["labels"]:
		out.append(str(l["text"]))
	return out


## The single road's signs on the network: limits where they change, the place's name board coming in, fingerposts
## down side roads and chevrons on a roundabout's island, in the country's way.
func test_signs() -> void:
	var rb: GDScript = load("res://tests/road_block_tests.gd")
	var net := RoadNet.new(_village(), rb.flat)
	var ex := RoadSigns.extent_of(net, 0)
	check(int(ex["n"]) == 34 and float(ex["r"]) > 100.0 and float(ex["r"]) < 180.0,
		"a village reaches as far as its houses run (%d buildings, %.0f m)" % [int(ex["n"]), float(ex["r"])])
	var b := net.block(RoadBlock.key_of(100.0, 100.0))
	var gb := RoadMarkings.paint(b, _kit("GB"))
	var de := RoadMarkings.paint(b, _kit("DE"))
	var texts := _texts(gb)
	check(texts.has("Testby"), "the village's name board stands where the road comes in (%s)" % [texts])
	check(texts.count("Testby") == 1 and _texts(de).count("Testby") == 2, "and going out too in Germany (its end board), not in Britain")
	check(texts.has("Southam  ¾") and _texts(de).has("Southam  1"), "the fingerpost down the side road names where it goes, in miles in Britain (%s)" % [texts])
	check(_texts(RoadMarkings.paint(b, _kit("FR"))).has("Southam  1"), "and in kilometres in France")
	for m: Dictionary in [gb, de]:
		check(_ok(m["signs"]), "the signs are whole, finite triangles")
		var ok := true
		for l: Dictionary in m["labels"]:
			var xf: Transform3D = l["xf"]
			ok = ok and xf.origin.is_finite() and absf(xf.basis.z.y) < 0.01 and str(l["text"]) != ""
		check(ok, "each label stands upright, facing along the ground")
		# Every pole's and bollard's foot is off the road: none stands on the carriageway or a junction's surface.
		var o := b.anchor()
		var in_road := 0
		for v: Vector3 in m["signs"]["v"]:
			var on := net.locate(v.x + o.x, v.z + o.z, -1, false)
			if v.y + o.y < rb.flat.call(v.x + o.x, v.z + o.z) + 0.3 and not on.is_empty() and bool(on["on_road"]):
				in_road += 1
		check(in_road == 0, "no sign's post stands in the road (%d points of them on it)" % in_road)
	# Limits: 30 mph coming into Testby and the national limit going out, the side road's 30 off the main road.
	var limits := RoadSigns.put_up(b, _kit("GB"), RoadMarkings.style_of(_kit("GB")), AdventureProps.new_arrays())
	check(limits == gb["labels"], "it signs the same every time")
	var ctx := {"places": RoadSigns.places_near(net, b.rect.grow(1000.0)), "table": "uk"}
	check(RoadSigns.limit_at(net, 1, 500.0, ctx) == 48 and RoadSigns.limit_at(net, 1, 1200.0, ctx) == 96,
		"the limit is the built-up one in the village and the open road's out of it")
	check(RoadSigns.limit_at(net, 2, 100.0, ctx) == 48, "and the map's where it has one")
	var with_limits := AdventureProps.new_arrays()
	RoadSigns._limit_sign(with_limits, Vector3.ZERO, Vector3(0, 0, 1), 48, "primary", {"mph": true, "nsl": true, "rect": false, "canada": false})
	check(_has(with_limits, RoadMarkings.RED) and (with_limits["v"] as PackedVector3Array).size() > 300, "a limit sign is a red ring with its number")
	var nsl := AdventureProps.new_arrays()
	RoadSigns._limit_sign(nsl, Vector3.ZERO, Vector3(0, 0, 1), 96, "primary", {"mph": true, "nsl": true, "rect": false, "canada": false})
	check(not _has(nsl, RoadMarkings.RED), "Britain's open road has the national limit disc")
	var us := AdventureProps.new_arrays()
	RoadSigns._limit_sign(us, Vector3.ZERO, Vector3(0, 0, 1), 88, "primary", {"mph": true, "nsl": false, "rect": true, "canada": false})
	check(not _has(us, RoadMarkings.RED) and _has(us, RoadMarkings.WHITE), "America's is a white rectangle")
	for n in range(5, 135, 5):
		check(SignWords.has(str(n)), "the limit %d is baked" % n)
	# A roundabout's island has a chevron board facing each road in: black and white in Britain, red on white in France.
	var rnet := RoadNet.new(rb.roundabout(), rb.flat)
	var rbk := rnet.block(RoadBlock.key_of(100.0, 100.0))
	var j: Dictionary = rbk.junctions[0]
	check(j["kind"] == "roundabout", "the fixture is a roundabout")
	var ch_gb := AdventureProps.new_arrays()
	var ch_fr := AdventureProps.new_arrays()
	RoadSigns._chevrons(ch_gb, rnet, j, rbk.anchor(), RoadMarkings.style_of(_kit("GB")))
	RoadSigns._chevrons(ch_fr, rnet, j, rbk.anchor(), RoadMarkings.style_of(_kit("FR")))
	check(_ok(ch_gb) and (ch_gb["v"] as PackedVector3Array).size() > 0 and _has(ch_gb, RoadMarkings.BLACK) and not _has(ch_gb, RoadMarkings.RED),
		"Britain's roundabout has black and white chevrons")
	check(_has(ch_fr, RoadMarkings.RED) and ch_fr["v"] != ch_gb["v"], "France's are red on white, pointing the other way round")
	var island_y := float(j["pos"].y) - rbk.anchor().y + RoadBlock.ISLAND_H
	var on := true
	for p: Vector3 in ch_gb["v"]:
		var off := Vector2(p.x, p.z) - Vector2(j["pos"].x - rbk.anchor().x, j["pos"].z - rbk.anchor().z)
		on = on and p.y > island_y - 0.05 and off.length() < rnet.island_r(rnet.junction_of(int(j["node"])), RoadNet._bearing(off)) + 0.2
	check(on, "the chevrons stand on the island")
