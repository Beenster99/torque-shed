extends RefCounted
## Real regions' checks (a baked region read by RealRegion), run from tests/run_tests.gd: its _test_region_* functions
## hand over to these.

const REGION := "shodoshima"

var t: Node   # the test runner: check()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func test_region() -> void:
	check(RealRegion.list().has(REGION), "the game has the %s region" % REGION)
	var r := RealRegion.get_region(REGION)
	check(r != null and r.hash != "" and r.credits.size() > 0, "it reads, with its hash and credits")
	if r == null:
		return
	check(RealRegion.get_region(REGION) == r, "and is read once, then shared")
	check(RealRegion.get_region("nowhere") == null, "a region that isn't there is null, not a crash")
	check(r.node_count() == int(r.counts["nodes"]) and r.edge_count() == int(r.counts["edges"]),
		"%d junctions and %d roads, as it says" % [r.node_count(), r.edge_count()])
	check(r.buildings.size() == int(r.counts["buildings"]) and r.pois.size() == int(r.counts["pois"]),
		"%d buildings and %d places to stop" % [r.buildings.size(), r.pois.size()])
	# Every road joins two junctions and runs between them.
	var ok := true
	var linked := 0
	for ei in r.edge_count():
		var line := r.edge_line[ei]
		if line.size() < 2 or line[0] != r.node_pos[r.edge_a[ei]] or line[line.size() - 1] != r.node_pos[r.edge_b[ei]] or r.edge_len[ei] <= 0.0:
			ok = false
		linked += 1
	check(ok and linked == r.edge_count(), "every road runs from its first junction to its second")
	var meets := 0
	for n in r.node_count():
		meets += r.adjacent[n].size()
	check(meets == 2 * r.edge_count(), "and every road is listed at both its ends")


func test_nearest() -> void:
	var r := RealRegion.get_region(REGION)
	if r == null:
		check(false, "region to search")
		return
	var worst := 0.0
	var wrong := 0
	for n in range(0, r.node_count(), 97):
		var p := r.node_pos[n]
		if r.nearest_node(p.x + 3.0, p.y - 2.0, 200.0) != n and r.node_pos[r.nearest_node(p.x + 3.0, p.y - 2.0, 200.0)].distance_to(p + Vector2(3, -2)) > p.distance_to(p + Vector2(3, -2)) + 0.01:
			wrong += 1
		worst = maxf(worst, p.distance_to(r.node_pos[r.nearest_node(p.x, p.y, 10.0)]))
	check(wrong == 0 and worst < 0.01, "the nearest junction to a junction is itself")
	check(r.nearest_node(1.0e6, 1.0e6, 500.0) == -1, "and none is found far from any road")
	# Brute force agrees with the grid.
	var q := Vector2(r.node_pos[5].x + 120.0, r.node_pos[5].y + 60.0)
	var best := -1
	var best_d := INF
	for n in r.node_count():
		var d := r.node_pos[n].distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = n
	check(r.nearest_node(q.x, q.y, 100000.0) == best, "the grid finds the same nearest junction as a search of them all")


func test_land() -> void:
	var r := RealRegion.get_region(REGION)
	if r == null:
		check(false, "region to stand on")
		return
	var known := 0
	var sane := 0
	for n in range(0, r.node_count(), 20):
		var h := r.terrain.height(r.node_pos[n].x, r.node_pos[n].y)
		if is_nan(h):
			continue
		known += 1
		if h > -5.0 and h < 900.0:
			sane += 1
	check(known > 100 and sane == known, "the land is known under the roads (%d of them looked at)" % known)
	var g := r.xz_to_geo(120.0, -340.0)
	var back := r.geo_to_xz(g[0], g[1])
	check(back.distance_to(Vector2(120.0, -340.0)) < 0.01, "a point goes to latitude and longitude and back")
	check(g[0] > 34.4 and g[0] < 34.6 and g[1] > 134.1 and g[1] < 134.4, "and lands on Shodoshima (%.4f, %.4f)" % [g[0], g[1]])
	check(r.name_of(0) != "" and r.country == "jp", "roads have names, and the country is Japan's")
