extends RefCounted
## Parts bought in the colours you pick at the parts computer (see PartColours), and the colour
## variants of one shape merged into one part, run from tests/run_tests.gd (its _test_part_colour_*
## functions hand over to these).

var t: Node   # the test runner: check(), ride(), get_tree()

## A second player, played on the host's side.
const MATE := 2


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The newest item of `part` in the shed, or 0.
static func _newest(part: String) -> int:
	var best := 0
	for id in Shed.items:
		if str(Shed.items[id]["part"]) == part and int(id) > best:
			best = int(id)
	return best


## Picked at the parts computer: a seat in blue with white piping and a matt finish, a tank with
## a stripe, an exhaust with heat-wrapped headers; each arrives boxed in those colours, and the
## picker only offers what the part has.
func test_picker() -> void:
	Shed.start_new("Tester", 39)
	Shed.garage_money = 1000000
	var pc := PartsComputer.new()
	t.add_child(pc)
	pc.fits_bike = 0
	pc.affordable_only = false
	pc.style_filter = ""
	pc._show_kind("saddle")
	pc._show_part("mx_ribbed_seat")
	check(pc._look_box.visible and pc._second_row.visible and pc._second_label.text == "Piping:" and not pc._trim_pick.visible,
		"a seat comes with a colour picker for its cover and its piping")
	check(pc._colour_row.get_child_count() >= Shed.PAINTS.size() + 1, "every paint shop colour is offered, and the factory's own")
	pc.pick_colour(Shed.PAINTS[1])
	pc.pick_second(Shed.PAINTS[5])
	pc.pick_finish("matte")
	var before := Shed.items.size()
	pc.order()
	var seat := _newest("mx_ribbed_seat")
	check(Shed.items.size() == before + 1 and seat != 0, "ordering it delivers one seat")
	if seat != 0:
		var it: Dictionary = Shed.items[seat]
		check(it["color"] == Shed.PAINTS[1] and it.get("color2") == Shed.PAINTS[5] and str(it["finish"]) == "matte" and it["boxed"],
			"it comes boxed in blue, with white piping, in a matt finish (%s)" % Shed.paint_text(it))
		check(Shed.paint_text(it).to_lower().contains("white piping"), "and its label says so: %s" % Shed.paint_text(it))
		var cond := Shed.condition_of(it)
		check(cond.get("color2") == Shed.PAINTS[5], "the model is given the piping colour")
	# A tank: colour, finish and a stripe.
	pc._show_kind("tank")
	pc._show_part("cafe_15")
	check(pc._second_label.text == "Stripe:" and pc.look.is_empty(), "a tank offers a stripe, and starts as the factory makes it")
	pc.pick_colour(Shed.PAINTS[6])
	pc.pick_finish("metallic")
	pc.pick_second(Shed.PAINTS[9])
	pc.order()
	var tank := _newest("cafe_15")
	check(tank != 0 and Shed.items[tank]["color"] == Shed.PAINTS[6] and str(Shed.items[tank]["finish"]) == "metallic"
		and Shed.items[tank].get("color2") == Shed.PAINTS[9], "a black metallic tank with a gold stripe arrives")
	# An exhaust: its headers' finish, not a second colour.
	pc._show_kind("exhaust")
	pc._show_part("cafe_megaphone_black")
	check(pc._trim_pick.visible and not pc._second_row.visible and pc._second_label.text == "Headers:", "an exhaust offers a finish for its headers")
	pc.pick_trim("wrap_black")
	pc.order()
	var pipe := _newest("cafe_megaphone_black")
	check(pipe != 0 and str(Shed.items[pipe].get("trim", "")) == "wrap_black", "it comes with black heat-wrapped headers")
	# Mirrors have one colour: no second row. An engine has no picker at all.
	pc._show_kind("mirrors")
	pc._show_part("bar_end_mirrors")
	check(pc._look_box.visible and not pc._second_row.visible and not pc._second_label.visible, "bar-end mirrors take a colour and a finish, no second colour")
	pc._show_kind("engine")
	pc._show_part(str(PartsDB.by_kind["engine"][0]))
	check(not pc._look_box.visible, "an engine has no colour picker")
	# Nothing picked: the factory's colours, as before.
	pc._show_kind("saddle")
	pc._show_part("mx_ribbed_seat")
	pc.order()
	var plain := _newest("mx_ribbed_seat")
	check(plain != seat and Shed.items[plain]["color"] == PartsDB.default_color("mx_ribbed_seat") and not Shed.items[plain].has("color2"),
		"with nothing picked it comes as the factory makes it")
	pc.queue_free()
	# The host turns away a look a part can't have.
	var n := Shed.items.size()
	Shed.request({"a": "order_part", "part": "bar_end_mirrors", "look": {"color2": Shed.PAINTS[0]}})
	Shed.request({"a": "order_part", "part": "cafe_15", "look": {"finish": "glitter"}})
	Shed.request({"a": "order_part", "part": "cafe_15", "look": {"color": "red"}})
	Shed.request({"a": "order_part", "part": str(PartsDB.by_kind["engine"][0]), "look": {"color": Shed.PAINTS[0]}})
	check(Shed.items.size() == n, "a second colour on mirrors, a made-up finish, a colour that isn't one or a painted engine block are all turned down")


## A co-op client's pick goes to the host as a request (over the wire, as bytes) and the host
## delivers the part in it, paid for by the business.
func test_client_order() -> void:
	Shed.start_new("Tester", 39)
	Shed.garage_money = 1000000
	Shed.crew[MATE] = {"name": "Mate", "tool": "hands", "activity": "", "riding": 0, "fitted": 0, "removed": 0, "cleaned": 0,
		"repaired": 0, "painted": 0, "km": 0.0, "top_kmh": 0.0, "kmh": 0.0, "slot": 1}
	var action := {"a": "order_part", "part": "sport_pointed_tail", "look": {"color": Shed.PAINTS[5], "color2": Shed.PAINTS[1], "finish": "gloss"}}
	# What the client sends arrives as the host decodes it.
	var sent = bytes_to_var(var_to_bytes(action))
	var money := Shed.garage_money
	Shed._apply(MATE, sent)
	var tail := _newest("sport_pointed_tail")
	check(tail != 0 and Shed.items[tail]["color"] == Shed.PAINTS[5] and Shed.items[tail].get("color2") == Shed.PAINTS[1]
		and str(Shed.items[tail]["finish"]) == "gloss", "the client's white tail with a blue stripe is delivered on the host")
	check(Shed.garage_money < money and str(Shed.items[tail].get("by", "")) == "Mate", "paid for by the business, with the client's name on the box")
	# The picker's order goes through Shed.request like every other change.
	var src := FileAccess.get_file_as_string("res://scripts/parts_computer.gd")
	check(src.contains("Shed.request({\"a\": \"order_part\", \"part\": _part, \"look\": look.duplicate()})"),
		"the parts computer sends the picked colours to the host in its order request")
	Shed.crew.erase(MATE)


## The colours picked are kept with the shed: saved, quit, loaded.
func test_save() -> void:
	Shed.start_new("Tester", 39)
	Shed.garage_money = 1000000
	Shed.request({"a": "order_part", "part": "classic_tuck_seat", "look": {"color": Shed.PAINTS[12], "color2": Shed.PAINTS[14], "finish": "patina"}})
	Shed.request({"a": "order_part", "part": "mx_titanium", "look": {"trim": "wrap"}})
	var seat := _newest("classic_tuck_seat")
	var pipe := _newest("mx_titanium")
	var text := var_to_str(Shed.save_snapshot())
	Shed.start_new("Tester", 40)
	Shed.load_state(PartsDB.migrate(str_to_var(text)), "Tester")
	check(Shed.items.has(seat) and Shed.items[seat]["color"] == Shed.PAINTS[12] and Shed.items[seat].get("color2") == Shed.PAINTS[14]
		and str(Shed.items[seat]["finish"]) == "patina", "a burgundy seat with cream piping in old patina is still so after a save and load")
	check(Shed.items.has(pipe) and str(Shed.items[pipe].get("trim", "")) == "wrap", "and the exhaust's headers are still heat-wrapped")


## The colour variants of one shape are one part now: each old id is mapped to the part it became,
## in the colours it came in, in items, orders, plans and builds; nothing in the game still uses one.
func test_retired() -> void:
	var count := 0
	for kind in PartsDB.RETIRED_PARTS:
		for old in PartsDB.RETIRED_PARTS[kind]:
			count += 1
			var keep: String = PartsDB.RETIRED_PARTS[kind][old]
			if not PartsDB.get_part(old).is_empty() or PartsDB.kind_of(keep) != kind or PartsDB.current_id(old) != keep \
					or not PartsDB.RETIRED_COLOURS.has(old):
				check(false, "%s maps to a %s that's in the catalogue (%s), and is gone itself" % [old, kind, keep])
	check(count >= 40, "%d colour variants are merged into the parts they were the same shape as" % count)
	check(PartsDB.sanitize_build({"saddle": "mx_red_seat", "handlebars": "cafe_black_clip_ons"})["saddle"] == "mx_ribbed_seat",
		"a build with an old seat gets the seat it became")
	# A save from before: a red MX seat on a bike, a blue sports seat in a blueprint, a white tail on order.
	var red: Color = PartsDB.retired_look("mx_red_seat")["color"]
	var old_save := {
		"items": {5: {"id": 5, "part": "mx_red_seat", "kind": "saddle", "rust": 0.1, "dirt": 0.0, "wear": 0.0, "color": red, "finish": ""}},
		"blueprints": {6: {"id": 6, "name": "Blue", "parts": {"saddle": "sport_blue_seat", "tank": "sport_17"}, "colors": {}, "paint": Shed.PAINTS[1]}},
		"on_order": [{"part": "sport_white_tail", "color": null, "finish": "", "paid": 110, "by": "Ann"}],
		"stock": {"sport_white_tail": 2},
	}
	var now: Dictionary = PartsDB.migrate(old_save)
	var it: Dictionary = now["items"][5]
	check(it["part"] == "mx_ribbed_seat" and it["color"] == red and it.get("color2") == PartsDB.retired_look("mx_red_seat")["color2"],
		"an old red MX seat is the MX seat in red, with its black piping")
	var bp: Dictionary = now["blueprints"][6]
	check(bp["parts"]["saddle"] == "naked_sport_seat" and bp["colors"].get("saddle", {}).get("color") == PartsDB.retired_look("sport_blue_seat")["color"]
		and bp["colors"]["saddle"].get("color2") == PartsDB.retired_look("sport_blue_seat")["color2"], "a blueprint's blue sports seat is the sport seat in blue with white stitching")
	var o: Dictionary = now["on_order"][0]
	check(o["part"] == "sport_pointed_tail" and o["color"] == PartsDB.retired_look("sport_white_tail")["color"] and o.get("color2") == PartsDB.retired_look("sport_white_tail")["color2"],
		"a white tail with a blue stripe on order arrives as the pointed tail in white with a blue stripe")
	check(now["stock"].has("sport_pointed_tail") and not now["stock"].has("sport_white_tail"), "kept by id: the old id's entry goes to the part it became")
	# Loaded and delivered: the order comes in those colours.
	Shed.start_new("Tester", 39)
	Shed.on_order = [o.duplicate()]
	Shed._deliver_on_order(5.0)
	var tail := _newest("sport_pointed_tail")
	check(tail != 0 and Shed.items[tail].get("color2") == PartsDB.retired_look("sport_white_tail")["color2"], "and is delivered with its stripe")
	# Nothing in the game's scripts or data still names an old id.
	var left := []
	for path in ["res://scripts/contracts.gd", "res://scripts/shed_state.gd", "res://scripts/parts_computer.gd", "res://scripts/coffee_shop.gd",
			"res://scripts/recovery.gd", "res://scripts/sales.gd", "res://scripts/customer.gd", "res://scripts/bike_shop.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for kind in PartsDB.RETIRED_PARTS:
			for old in PartsDB.RETIRED_PARTS[kind]:
				if src.contains("\"%s\"" % old):
					left.append("%s in %s" % [old, path.get_file()])
	check(left.is_empty(), "no script still names a merged-away part %s" % [left])


## The model draws what was picked: the seat's piping, a tank's stripes, a fender's rib and an
## exhaust's heat-wrapped headers, in the colours the items carry; and the paint on top is the
## part's own colour, sprayed over like any other.
func test_model() -> void:
	var parts: Dictionary = Contracts.style_build("cruiser").duplicate()
	parts["saddle"] = "classic_tuck_seat"
	parts["tank"] = "cafe_15"
	parts["front_mudguard"] = "valanced_painted_guard"
	parts["exhaust"] = "cafe_megaphone_black"
	parts = PartsDB.sanitize_build(parts)
	var green: Color = Shed.PAINTS[3]
	var gold: Color = Shed.PAINTS[9]
	var cond := {
		"saddle": {"rust": 0.0, "dirt": 0.0, "wear": 0.0, "color": Shed.PAINTS[6], "finish": "", "color2": green},
		"tank": {"rust": 0.0, "dirt": 0.0, "wear": 0.0, "color": Shed.PAINTS[0], "finish": "gloss", "color2": gold},
		"front_mudguard": {"rust": 0.0, "dirt": 0.0, "wear": 0.0, "color": Shed.PAINTS[0], "finish": "", "color2": gold},
		"exhaust": {"rust": 0.0, "dirt": 0.0, "wear": 0.0, "color": Shed.PAINTS[6], "finish": "", "trim": "wrap"},
	}
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(BikeBuild.new(parts, cond))
	var piping := _named(m, "saddle", "Piping")
	check(not piping.is_empty() and piping.all(func(mi): return _albedo(mi).is_equal_approx(green)), "the seat's piping is drawn in the green it was ordered with (%d)" % piping.size())
	var stripes := _named(m, "tank", "TankStripe")
	check(stripes.size() == 2 and stripes.all(func(mi): return _albedo(mi).is_equal_approx(gold)), "the tank carries a pair of gold stripes")
	var rib := _named(m, "front_mudguard", "GuardRib")
	check(rib.size() == 1 and _albedo(rib[0]).is_equal_approx(gold), "the mudguard's rib is gold, not chrome")
	var wrap: Array = (m._slot_meshes.get("exhaust", []) as Array).filter(func(mi): return _albedo(mi).is_equal_approx(Color(0.74, 0.69, 0.58)))
	check(not wrap.is_empty(), "the exhaust's headers are heat-wrapped (%d pieces)" % wrap.size())
	m.free()
	# Without a second colour picked, the factory's look: no stripes on a plain tank, a chrome rib.
	var plain := BikeModel.new()
	t.add_child(plain)
	plain.build_from(BikeBuild.new(parts, {}))
	check(_named(plain, "tank", "TankStripe").is_empty(), "a tank ordered without a stripe has none")
	var chrome_rib := _named(plain, "front_mudguard", "GuardRib")
	check(chrome_rib.size() == 1 and _albedo(chrome_rib[0]).is_equal_approx(Color(0.86, 0.87, 0.89)), "and the rib is chrome as it comes")
	plain.free()


## Bikes found or built for someone (project bikes, customers', contracts') come in varied
## colours leaning to their style: not every part as the factory made it, and the same bike the
## same every time.
func test_random_bikes() -> void:
	Shed.start_new("Tester", 39)
	var picked := 0
	var seconds := 0
	var pickable := 0
	for i in 12:
		var id: int = Shed._random_bike(0, 0.3)
		for slot in Shed.bikes[id]["slots"]:
			var item := int(Shed.bikes[id]["slots"][slot])
			if item == 0 or not Shed.items.has(item) or not PartColours.pickable(str(Shed.items[item]["part"])):
				continue
			pickable += 1
			var it: Dictionary = Shed.items[item]
			if it["color"] != PartsDB.default_color(str(it["part"])):
				picked += 1
			if it.has("color2") or it.has("trim"):
				seconds += 1
	check(pickable > 50 and picked > pickable / 5 and seconds > 5,
		"of %d colourable parts on 12 project bikes, %d are in other colours and %d have a second colour or headers picked" % [pickable, picked, seconds])
	var a := PartColours.random_look("classic_tuck_seat", "classic", Shed.PAINTS[0], false, 1234)
	var b := PartColours.random_look("classic_tuck_seat", "classic", Shed.PAINTS[0], false, 1234)
	check(a == b, "the same bike's seat comes out the same every time")
	var looks := {}
	for k in 40:
		looks[var_to_str(PartColours.random_look("classic_tuck_seat", "cafe", Shed.PAINTS[3], false, k))] = true
	check(looks.size() >= 5, "and across bikes they vary (%d different looks in 40)" % looks.size())
	var tank := PartColours.random_look("cafe_15", "cafe", Shed.PAINTS[3], true, 7)
	check(not tank.has("color"), "a painted tank keeps the bike's paint")


static func _named(m: BikeModel, slot: String, n: String) -> Array:
	return (m._slot_meshes.get(slot, []) as Array).filter(func(mi): return is_instance_valid(mi) and str((mi as Node).name).begins_with(n))


static func _albedo(mi) -> Color:
	var mat = (mi as MeshInstance3D).material_override
	return (mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else Color(0, 0, 0, 0)
