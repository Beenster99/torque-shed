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
	# Speed bumps on a long town street, by the country's count (Mexico's topes), none out of town; bollards round a
	# town junction's corners.
	var street := RoadNet.new(load("res://tests/road_block_tests.gd").graph([[100, 100], [-200, 100], [490, 100], [100, 500]],
		[[1, 0, "residential"], [0, 2, "residential"], [0, 3, "residential"]]), load("res://tests/road_block_tests.gd").flat)
	var sb := street.block(RoadBlock.key_of(100.0, 100.0))
	var mx_town := RoadMarkings.paint(sb, _kit("MX", "town"))
	check((mx_town["faces"] as PackedVector3Array).size() > 0 and _has(mx_town["signs"], RoadMarkings.YELLOW),
		"a Mexican town street has its topes, striped, to ride over (%d faces)" % [(mx_town["faces"] as PackedVector3Array).size() / 3])
	check((RoadMarkings.paint(sb, _kit("MX"))["faces"] as PackedVector3Array).is_empty(), "and none out of town")
	var gb_street := RoadMarkings.paint(sb, _kit("GB", "town"))
	check(_has(gb_street["signs"], RoadMarkings.BOLLARDS["british_isles"][1]), "a British town junction has its black and gold bollards")
	var ok := true
	for p: Vector3 in mx_town["faces"]:
		ok = ok and p.is_finite() and absf(p.y + sb.anchor().y - 10.0) < 0.3
	check(ok, "the bumps lie on the road")
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
