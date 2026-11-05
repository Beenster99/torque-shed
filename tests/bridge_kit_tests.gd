extends RefCounted
## The bridge designs' checks (scripts/scenery/bridges.gd, BridgeKit), run from tests/run_tests.gd: its
## _test_bridge_* functions hand over to these. Made-up crossings, and small road graphs over made-up land
## (road_block_tests.gd's); no scene and no network.

const Roads := preload("res://tests/road_block_tests.gd")

var t: Node   # the test runner: check()

## design -> [length (m), the deck over the land's lowest (m), water under it]: a crossing that suits each.
const CASES := {
	"stone_arch": [60.0, 12.0, true], "viaduct": [420.0, 45.0, false], "girder": [40.0, 7.0, false],
	"truss": [180.0, 9.0, true], "bowstring": [140.0, 9.0, true], "gorge_arch": [260.0, 90.0, false],
	"cable_stayed": [420.0, 25.0, true], "suspension": [1200.0, 40.0, true], "covered": [40.0, 5.0, true],
	"lift": [30.0, 3.5, true],
}
## The road's half width on the made-up crossings (m), and how high over it nothing of a bridge may be (m).
const E := 3.7
const HEADROOM := 5.0


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A crossing `length` long along x from x 0, its deck at y 30 and the land `drop` under it in the middle, as design
## `design` (or picked, for "").
static func crossing(design: String, length: float, drop: float, wet: bool, facts := {}) -> Dictionary:
	var n := ceili(length / BridgeKit.DS) + 1
	var ds := length / float(n - 1)
	var pts := PackedVector3Array()
	var rights := PackedVector3Array()
	var ground := PackedFloat32Array()
	var wets := PackedFloat32Array()
	for i in n:
		var u := absf(float(i) / float(n - 1) * 2.0 - 1.0)
		pts.append(Vector3(ds * i, 30.0, 0.0))
		rights.append(Vector3(0.0, 0.0, 1.0))
		ground.append(30.0 - drop * (1.0 - pow(u, 6.0)))
		wets.append(1.0 if wet and u < 0.7 else 0.0)
	var f := facts.duplicate()
	if design != "":
		f["design"] = design
	return BridgeKit.make(pts, rights, ground, wets, E + 0.45, AdventureRoute.BRIDGE_DEPTH, f, ds)


func test_picks() -> void:
	var p := func(f: Dictionary) -> String: return BridgeKit.pick(f)
	check(p.call({"length": 25.0, "clear": 4.0, "wet": 1.0, "region": "british_isles", "country": "GB"}) == "stone_arch",
		"a short bridge over a Dales beck stays stone")
	check(p.call({"length": 300.0, "clear": 50.0, "wet": 0.0, "big": true, "region": "western_europe", "roll": 0.9}) == "viaduct",
		"a motorway high over a valley is a concrete viaduct")
	check(p.call({"length": 35.0, "clear": 6.0, "over_road": true, "region": "british_isles"}) == "girder",
		"a bridge over another road is a girder overbridge")
	check(p.call({"length": 1500.0, "clear": 40.0, "wet": 1.0, "region": "british_isles", "roll": 0.9}) == "suspension",
		"a 1.5 km estuary crossing hangs from towers and cables")
	check(p.call({"length": 700.0, "clear": 30.0, "wet": 1.0, "region": "east_asia", "roll": 0.8}) == "cable_stayed",
		"a long river crossing is cable-stayed")
	check(p.call({"length": 200.0, "clear": 80.0, "region": "western_europe", "roll": 0.2}) == "gorge_arch",
		"high over a deep valley, one great arch")
	check(p.call({"length": 120.0, "clear": 9.0, "wet": 1.0, "region": "north_america", "roll": 0.3}) == "truss",
		"a North American river crossing is a steel truss")
	check(p.call({"length": 120.0, "clear": 9.0, "wet": 1.0, "region": "western_europe", "roll": 0.3}) == "bowstring",
		"a modern European one a bowstring arch")
	check(p.call({"length": 20.0, "clear": 3.0, "wet": 1.0, "canal": true, "region": "western_europe", "country": "NL"}) == "lift",
		"over a Dutch canal, a lifting bridge")
	check(p.call({"length": 30.0, "clear": 4.0, "wet": 1.0, "region": "western_europe", "country": "CH", "roll": 0.05}) == "covered",
		"now and then in Switzerland, a covered timber bridge")
	var seen := {}
	for roll in 50:
		for f: Dictionary in [{"length": 25.0, "clear": 4.0, "wet": 1.0}, {"length": 300.0, "clear": 50.0},
				{"length": 120.0, "clear": 9.0, "wet": 1.0, "region": "north_america"}, {"length": 900.0, "clear": 30.0, "wet": 1.0}]:
			var g := f.duplicate()
			g["roll"] = roll / 50.0
			seen[p.call(g)] = true
	for d: String in seen:
		check(d in BridgeKit.DESIGNS, "%s is one of the ten designs" % d)


func test_designs() -> void:
	for design: String in CASES:
		var c: Array = CASES[design]
		var rec := crossing(design, float(c[0]), float(c[1]), bool(c[2]))
		check(str(rec["design"]) == design and rec.has("edge"), "%s: its record and its sides' style" % design)
		var all := AdventureProps.new_arrays()
		BridgeKit.draw(all, rec, func(_s: float, _p: Vector3) -> bool: return true)
		var v: PackedVector3Array = all["v"]
		check(v.size() > 30, "%s: it's built (%d corners)" % [design, v.size()])
		check(v.size() < 120000, "%s: in few enough corners for a block's mesh (%d)" % [design, v.size()])
		# Nothing in the way of a rider: no part over the road's own width up to HEADROOM above it.
		var hits := 0
		for p: Vector3 in v:
			if absf(p.z) < E - 0.05 and p.y > 30.25 and p.y < 30.0 + HEADROOM:
				hits += 1
		check(hits == 0, "%s: nothing stands in the road or hangs low over it (%d corners do)" % [design, hits])
		# Built a part in each of two blocks, it's the same bridge: every part once.
		var half := float(c[0]) * 0.5
		var a := AdventureProps.new_arrays()
		BridgeKit.draw(a, rec, func(s: float, _p: Vector3) -> bool: return s < half)
		BridgeKit.draw(a, rec, func(s: float, _p: Vector3) -> bool: return s >= half)
		check((a["v"] as PackedVector3Array).size() == v.size(), "%s: built in two halves, every part once (%d, %d)" % [design,
			(a["v"] as PackedVector3Array).size(), v.size()])
		var t0 := Time.get_ticks_usec()
		BridgeKit.draw(AdventureProps.new_arrays(), rec, func(_s: float, _p: Vector3) -> bool: return true)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		check(ms < 400.0, "%s: built quickly enough on a block's worker (%.1f ms)" % [design, ms])
		# Its sides: collision is the caller's, but the look has a top at a parapet's height.
		var side := AdventureProps.new_arrays()
		BridgeKit.edge(side, rec["edge"], Vector3(0, 30, E), Vector3(4, 30, E), Vector3(0, 30, E + 0.45),
			Vector3(4, 30, E + 0.45), AdventureChunk.PARAPET, AdventureRoute.BRIDGE_DEPTH)
		var top := -INF
		for p: Vector3 in side["v"]:
			top = maxf(top, p.y)
		check(top >= 30.0 + AdventureChunk.PARAPET - 0.01 or str(rec["edge"]["kind"]) == "timber",
			"%s: its sides stand a parapet's height (%.2f)" % [design, top - 30.0])


## On the road net: a bridge's design comes from what it crosses, its piers stay out of the road under it, and the
## same bridge is the same from either block it's in.
func test_blocks() -> void:
	# Over another road on the flat: a girder overbridge, nothing of it standing in the road beneath.
	var o := Roads.graph([[-300, 100], [300, 100], [100, -200], [100, 400]], [[0, 1, "primary"], [2, 3, "secondary"]])
	o.spans = [[0, 88.0, 100.0, 112.0, 100.0]]
	var over := RoadNet.new(o, Roads.flat)
	var b := over.block(Vector2i(0, 0))
	var designs := {}
	for rec: Dictionary in b._bridges.values():
		designs[rec["design"]] = true
	check(designs.keys() == ["girder"], "a bridge over another road is a girder overbridge (%s)" % [designs.keys()])
	var v: PackedVector3Array = b.arrays["bridge"]["v"]
	var in_road := 0
	var lowest := INF
	for p: Vector3 in v:
		var q := p + b.anchor()
		if absf(q.x - 100.0) < over.width_of(1) * 0.5 and absf(q.z - 100.0) > 5.0 and absf(q.z - 100.0) < 40.0:
			continue
		if absf(q.x - 100.0) < over.width_of(1) * 0.5 + 0.5 and q.y < 10.0 + 4.5:
			in_road += 1
		lowest = minf(lowest, q.y)
	check(in_road == 0, "and nothing of it stands in the road under it (%d corners)" % in_road)
	# A long bridge high over a valley that's across two blocks: one design, its piers once.
	var valley := func(x: float, _z: float) -> float: return 80.0 - maxf(0.0, 260.0 - absf(x - 512.0)) * 0.3
	var r := Roads.graph([[0, 100], [1000, 100]], [[0, 1, "motorway"]])
	r.spans = [[0, 300.0, 100.0, 724.0, 100.0]]
	var net := RoadNet.new(r, valley)
	var left := net.block(Vector2i(0, 0))
	var right := net.block(Vector2i(1, 0))
	var picks := []
	for blk: RoadBlock in [left, right]:
		for rec: Dictionary in blk._bridges.values():
			picks.append(rec["design"])
	check(picks.size() == 2 and picks[0] == picks[1] and picks[0] == "viaduct",
		"a motorway high over a valley is a viaduct, the same from both blocks it's in (%s)" % [picks])
	var nl := (left.arrays["bridge"]["v"] as PackedVector3Array).size()
	var nr := (right.arrays["bridge"]["v"] as PackedVector3Array).size()
	check(nl > 0 and nr > 0, "each block builds its half (%d, %d corners)" % [nl, nr])
