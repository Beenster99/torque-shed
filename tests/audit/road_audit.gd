extends Node
## The world road audit: the road network's faults in every cell of the world's store, found from the data alone (no
## drawing), so they're put right for every place at once rather than one Simon happens to ride. Run by road_audit.sh.
##
## Each cell's roads are laid out as the network ride lays them (RoadNet, RoadBlock's own checks) and looked over for:
## - "crossing": two roads crossing with no junction and no bridge or tunnel on either (one is laid over the other as
##   a slab of road, or the two cut through each other): how far apart in height they are, with heights;
## - "tangle": two roads out of the same node crossing back over each other near it (the map's lines knotted);
## - "bridge_dead_end": a bridge's deck running into a road's dead end (it stops in the air: a bridge to nowhere);
## - "bridge_end": a road just off a bridge's end that isn't on the land (m up from it, or down), with heights;
## - "step": the roads meeting at a node at different heights (m between the highest and lowest), with heights;
## - "hump": a junction higher (or lower) than every road out of it, 15 m out (m), with heights;
## - "bump": an edge's worst bump (m off the average over 30 m, as the postcards measure it), with heights;
## - "buildings_dropped": a cell's buildings that stand on a road or in a junction (the game leaves them out), as a
##   share of its buildings;
## - "building_cap": a cell holding as many buildings as the bake keeps (tools/region_bake.py BUILDING_MAX), so the
##   ones furthest from a road were left out.
## A cell's findings are kept (OUT/cells/ROW_COL.json) with the hash of its data and of the road code: a cell neither
## has changed for isn't audited again. The findings of all of them, worst first by class, go to OUT/report.json, and a
## short summary to OUT/summary.txt.
##
## Arguments (after --): --cells=ROW_COL,... | --places (the postcards' places) | --sample (those and sample.json's: Rio
## and thirty cells at random) | --all; --heights (fetch the land's
## heights round the roads and do the height checks); --out=DIR; --limit=N (at most N cells); --top=N (in each class);
## --shard=K/N (every Nth cell from the Kth: CI's machines share them); --report (just the report, from the findings
## kept in OUT/cells: the machines' put together).

## How far a bump, step, hump or bridge end may be before it's a fault (m).
const BUMP_M := 0.15
const STEP_M := 0.3
const HUMP_M := 0.3
const BRIDGE_END_M := 1.5
## How far out along each road a junction's hump is measured (m).
const HUMP_OUT := 15.0
## How far in from a cell's edge (m) its roads are looked at.
const EDGE_PAD := 60.0
## The bake's cap on a cell's buildings (tools/region_bake.py BUILDING_MAX).
const BUILDING_MAX := 60000
## The code the findings depend on: a change to any of it audits every cell again.
const CODE := ["res://scripts/road_net.gd", "res://scripts/road_block.gd", "res://scripts/real_region.gd",
	"res://scripts/real_terrain.gd", "res://scripts/height_tiles.gd",
	"res://scripts/route_planner.gd", "res://tests/audit/road_audit.gd"]

var out_dir := "/tmp/road-audit"
var heights := false
var top := 25
var _thread: Thread


func _ready() -> void:
	var cells: Array[Vector2i] = []
	var mode := ""
	var limit := 0
	var shard := Vector2i(0, 1)
	var report_only := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cells="):
			mode = "cells"
			for part in a.trim_prefix("--cells=").split(",", false):
				var rc := part.trim_prefix("c").split("_")
				cells.append(Vector2i(int(rc[0]), int(rc[1])))
		elif a == "--places":
			mode = "places"
		elif a == "--sample":
			mode = "sample"
		elif a == "--all":
			mode = "all"
		elif a == "--heights":
			heights = true
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--limit="):
			limit = int(a.trim_prefix("--limit="))
		elif a.begins_with("--top="):
			top = int(a.trim_prefix("--top="))
		elif a.begins_with("--shard="):
			var kn := a.trim_prefix("--shard=").split("/")
			shard = Vector2i(int(kn[0]), int(kn[1]))
		elif a == "--report":
			report_only = true
	if report_only:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("cells"))
		var kept := []
		for name in DirAccess.get_files_at(out_dir.path_join("cells")):
			var got = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("cells").path_join(name)))
			if got is Dictionary:
				kept.append(got)
				heights = heights or str(got.get("key", "")).ends_with("|h")
		_report(kept, 0)
		get_tree().quit()
		return
	var idx := CellStore.index()
	if idx.is_empty():
		printerr("AUDIT: couldn't read the world's index")
		get_tree().quit(1)
		return
	if mode == "sample":
		for key: String in JSON.parse_string(FileAccess.get_file_as_string("res://tests/audit/sample.json"))["cells"]:
			var rc := key.split("_")
			cells.append(Vector2i(int(rc[0]), int(rc[1])))
	if mode == "places" or mode == "sample":
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://tests/postcards/places.json"))
		for place: Dictionary in spec["places"]:
			var a: Array = place["from"]
			var c := RealRegion.cell_of(float(a[0]), float(a[1]))
			if not cells.has(c):
				cells.append(c)
		cells.sort()
	elif mode == "all":
		for key: String in idx["cells"]:
			if not (idx["cells"][key] as Dictionary).has("empty"):
				var rc := key.split("_")
				cells.append(Vector2i(int(rc[0]), int(rc[1])))
		cells.sort()
	if cells.is_empty():
		printerr("AUDIT: no cells (--cells=ROW_COL,... | --places | --sample | --all)")
		get_tree().quit(1)
		return
	if limit > 0:
		cells = cells.slice(0, limit)
	if shard.y > 1:
		var mine: Array[Vector2i] = []
		for i in range(shard.x, cells.size(), shard.y):
			mine.append(cells[i])
		cells = mine
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("cells"))
	# (the fetching blocks: off the main thread)
	_thread = Thread.new()
	_thread.start(_run.bind(cells, idx))
	while _thread.is_alive():
		await get_tree().process_frame
	var code: int = _thread.wait_to_finish()
	get_tree().quit(code)


## Audits `cells` (each from its kept findings if neither it nor the code has changed), then writes the report.
func _run(cells: Array[Vector2i], idx: Dictionary) -> int:
	var code_hash := _code_hash()
	var all := []
	var done := 0
	var t0 := Time.get_ticks_msec()
	for c in cells:
		var name := "%d_%d" % [c.x, c.y]
		var key := "%s|%s|%s" % [str((idx["cells"][name] as Dictionary).get("hash", "")), code_hash, "h" if heights else "-"]
		var path := out_dir.path_join("cells").path_join(name + ".json")
		var kept = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var found: Dictionary
		if kept is Dictionary and str(kept.get("key", "")) == key:
			found = kept
		else:
			var tc := Time.get_ticks_msec()
			found = audit_cell(c)
			found["key"] = key
			found["ms"] = Time.get_ticks_msec() - tc
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify(found))
			f.close()
		done += 1
		print("AUDIT %d/%d %s: %s (%d ms)" % [done, cells.size(), name, _counts_text(found), int(found.get("ms", 0))])
		all.append(found)
	_report(all, Time.get_ticks_msec() - t0)
	return 0


## The findings of cell `c`: {cell, edges, nodes, buildings, faults: [{class, size, x, z, lat, lon, ...}], why}.
func audit_cell(c: Vector2i) -> Dictionary:
	var name := "%d_%d" % [c.x, c.y]
	var out := {"cell": name, "faults": []}
	var id := RealRegion.cells_area_id([c] as Array[Vector2i])
	var why := RealRegion.fetch_area(id)
	if why != "":
		out["why"] = why
		return out
	RealRegion.forget(id)
	var region := RealRegion.get_region(id)
	if region == null:
		out["why"] = "no region"
		return out
	var t := region.terrain
	if heights:
		var pts := PackedVector2Array()
		for ei in region.edge_count():
			pts.append_array(region.edge_line[ei])
		var missed := HeightTiles.fetch(HeightTiles.keys_near(pts, 40.0, t.zooms[0], t.lat0, t.lon0))
		if missed > 0:
			out["missed_tiles"] = missed
	var net := RoadNet.new(region, t.height if heights else func(_x: float, _z: float) -> float: return 0.0)
	out["edges"] = region.edge_count()
	out["nodes"] = region.node_count()
	out["buildings"] = region.buildings.size()
	var frame := Vector2(region.frame_lat, region.frame_lon)
	var faults: Array = out["faults"]
	# (a road cut off at the cell's edge ends there: what's found right by it is the cell's edge, not the road's)
	var sw := RealRegion.to_frame(frame, c.x * RealRegion.CELL_DEG - 90.0, c.y * RealRegion.CELL_DEG - 180.0)
	var ne := RealRegion.to_frame(frame, (c.x + 1) * RealRegion.CELL_DEG - 90.0, (c.y + 1) * RealRegion.CELL_DEG - 180.0)
	var inner := Rect2(sw, ne - sw).abs().grow(-EDGE_PAD)
	var add := func(kind: String, size: float, p: Vector2, extra := {}) -> void:
		if not kind.begins_with("building") and not inner.has_point(p):
			return
		var geo := RealRegion.from_frame(frame, p.x, p.y)
		var f := {"class": kind, "size": snappedf(size, 0.01), "cell": name, "x": roundi(p.x), "z": roundi(p.y),
			"lat": snappedf(geo.x, 0.00001), "lon": snappedf(geo.y, 0.00001)}
		f.merge(extra)
		faults.append(f)
	_crossings(net, add)
	_bridges(net, t, add)
	if heights:
		_nodes(net, add)
		_bumps(net, add)
	_buildings(net, add, out)
	return out


## Roads crossing with no junction, bridge or tunnel.
func _crossings(net: RoadNet, add: Callable) -> void:
	var region := net.region
	var seen := {}
	for ei in region.edge_count():
		var len := net.length_of(ei)
		for hit: Vector4 in net._crossings(ei, 0.0, len):
			var at := Vector2(hit.x, hit.y)
			var on := _other_at(net, ei, at)
			if on.x < 0:
				continue
			var oe := int(on.x)
			var pair := Vector3i(mini(ei, oe), maxi(ei, oe), roundi(at.x) * 7919 + roundi(at.y))
			if seen.has(pair):
				continue
			seen[pair] = true
			if net.bridge_at(ei, hit.z) > 0.0 or net.bridge_at(oe, on.y) > 0.0 or _in_tunnel(net, ei, hit.z) \
					or _in_tunnel(net, oe, on.y):
				continue
			var size := absf(net.road_y(ei, hit.z) - net.road_y(oe, on.y)) if heights else 0.0
			# (two roads out of the same node crossing back over each other: the map's lines tangled by a junction)
			var shared := region.edge_a[ei] in [region.edge_a[oe], region.edge_b[oe]] or region.edge_b[ei] in [region.edge_a[oe], region.edge_b[oe]]
			add.call("tangle" if shared else "crossing", size, at, {"edges": [ei, oe], "classes": [region.class_of(ei), region.class_of(oe)]})


## The edge other than `ei` whose line passes through `at`, and how far along it: Vector2(edge, s), x -1 for none.
func _other_at(net: RoadNet, ei: int, at: Vector2) -> Vector2:
	var near := net._near_at(at.x, at.y)
	var cands: PackedInt32Array = near[0]
	var best := Vector2(-1, 0)
	var best_d := 0.5
	for c in cands.size():
		if cands[c] == ei:
			continue
		var pr := net._project(cands[c], at, near[1][c])
		if float(pr[2]) < best_d:
			best_d = float(pr[2])
			best = Vector2(cands[c], float(pr[0]))
	return best


## Whether edge `ei` is in one of the map's tunnels `s` m along.
func _in_tunnel(net: RoadNet, ei: int, s: float) -> bool:
	var n := net.samples_of(ei)
	var sp := net.length_of(ei) / float(n - 1)
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for k in n:
		var p := net.point_at(ei, sp * k)
		xs.append(p.x)
		zs.append(p.y)
	var t := RoutePlanner.spans_along(net.region, xs, zs, 1)
	for k in range(0, t.size() - 1, 2):
		if s >= sp * t[k] - sp and s <= sp * t[k + 1] + sp:
			return true
	return false


## Bridges running into a dead end, and (with heights) bridges whose ends don't come down to the land.
func _bridges(net: RoadNet, t: RealTerrain, add: Callable) -> void:
	var region := net.region
	for ei in region.edge_count():
		var b := net.bridges_of(ei)
		if b.is_empty():
			continue
		var n := net.samples_of(ei)
		var sp := net.length_of(ei) / float(n - 1)
		for k in range(0, b.size() - 1, 2):
			for end in [[b[k], region.edge_a[ei], 0], [b[k + 1], region.edge_b[ei], n - 1]]:
				var at := int(end[0])
				var p := net.point_at(ei, sp * at)
				if at == int(end[2]) and region.adjacent[int(end[1])].size() == 1:
					add.call("bridge_dead_end", sp * float(b[k + 1] - b[k]), p, {"edges": [ei], "node": int(end[1])})
					continue
				if not heights:
					continue
				# (a little way off the deck, the road should be on the land: the land under it held up to it, as a bank)
				var off := sp * (at + (-2 if int(end[2]) == 0 else 2))
				if off < 0.0 or off > net.length_of(ei):
					continue   # (a bridge carried on through a node into another road is that road's end to check)
				var q := net.point_at(ei, off)
				var y := net.road_y(ei, off) - RoadNet.UNDER
				var land := net.ground_at(q.x, q.y, t.height(q.x, q.y))
				if not is_nan(y + land) and absf(y - land) > BRIDGE_END_M:
					add.call("bridge_end", absf(y - land), q, {"edges": [ei], "up": y > land})


## The roads at a node at different heights, and junctions higher or lower than all their roads.
func _nodes(net: RoadNet, add: Callable) -> void:
	var region := net.region
	for node in region.node_count():
		var adj := region.adjacent[node]
		if adj.size() < 2:
			continue
		var lo := INF
		var hi := -INF
		var out_lo := INF
		var out_hi := -INF
		for ei in adj:
			var at_a := region.edge_a[ei] == node
			var len := net.length_of(ei)
			var y := net.road_y(ei, 0.0 if at_a else len)
			var o := net.road_y(ei, minf(HUMP_OUT, len) if at_a else maxf(len - HUMP_OUT, 0.0))
			if is_nan(y + o):
				continue
			lo = minf(lo, y)
			hi = maxf(hi, y)
			out_lo = minf(out_lo, o)
			out_hi = maxf(out_hi, o)
		if hi - lo > STEP_M:
			add.call("step", hi - lo, region.node_pos[node], {"node": node, "roads": adj.size()})
		if adj.size() < 3 or not is_finite(out_lo):
			continue
		var y0 := net.node_y(node)
		var hump := maxf(y0 - out_hi, out_lo - y0)
		if hump > HUMP_M:
			add.call("hump", hump, region.node_pos[node], {"node": node, "roads": adj.size(), "up": y0 > out_hi})


## Each edge's worst bump: how far its height strays from the average over 30 m about it (as the postcards measure).
func _bumps(net: RoadNet, add: Callable) -> void:
	var half := 7
	for ei in net.region.edge_count():
		var len := net.length_of(ei)
		if len < 2.0 * (half * 2 + 1):
			continue
		var ys := PackedFloat32Array()
		var s := 0.0
		while s <= len:
			ys.append(net.road_y(ei, s))
			s += 2.0
		var worst := 0.0
		var at := 0
		for i in range(half, ys.size() - half):
			var sum := 0.0
			for j in range(i - half, i + half + 1):
				sum += ys[j]
			var d := absf(ys[i] - sum / (half * 2 + 1))
			if d > worst:
				worst = d
				at = i
		if worst > BUMP_M:
			add.call("bump", worst, net.point_at(ei, at * 2.0), {"edges": [ei], "class": net.region.class_of(ei)})


## The buildings the game leaves out for standing on a road (RoadBlock._clear_of_roads), and the bake's cap.
func _buildings(net: RoadNet, add: Callable, out: Dictionary) -> void:
	var region := net.region
	var dropped := 0
	var b := RoadBlock.new()
	b.net = net
	var where := Vector2.ZERO
	for key: Vector2i in net._buildings_by_block:
		for row: Array in net._buildings_by_block[key]:
			if b._clear_of_roads(row).is_empty():
				dropped += 1
				where = Vector2(float(row[0]), float(row[1]))
	out["buildings_dropped"] = dropped
	var total := region.buildings.size()
	if total > 0 and dropped > 0:
		add.call("buildings_dropped", float(dropped) / float(total), where, {"dropped": dropped, "of": total})
	if total >= BUILDING_MAX * 0.98:
		add.call("building_cap", float(total), Vector2.ZERO, {"of": total})


## The hash of the code the findings depend on.
func _code_hash() -> String:
	var text := ""
	for path in CODE:
		text += FileAccess.get_file_as_string(path)
	return text.sha1_text().substr(0, 12)


## A cell's faults counted by class, as text.
func _counts_text(found: Dictionary) -> String:
	if found.has("why"):
		return str(found["why"])
	var counts := {}
	for f: Dictionary in found["faults"]:
		counts[f["class"]] = int(counts.get(f["class"], 0)) + 1
	var parts := PackedStringArray()
	for k: String in counts:
		parts.append("%s %d" % [k, counts[k]])
	return "%d edges, %s" % [int(found.get("edges", 0)), ", ".join(parts) if not parts.is_empty() else "nothing"]


## OUT/report.json (every class's faults, worst first, its top `top`; and counts) and OUT/summary.txt.
func _report(all: Array, ms: int) -> void:
	var by_class := {}
	var cells_with := {}
	var failed := []
	for found: Dictionary in all:
		if found.has("why"):
			failed.append({"cell": found["cell"], "why": found["why"]})
			continue
		for f: Dictionary in found["faults"]:
			var k: String = f["class"]
			if not by_class.has(k):
				by_class[k] = []
				cells_with[k] = {}
			(by_class[k] as Array).append(f)
			cells_with[k][f["cell"]] = true
	var report := {"cells": all.size(), "heights": heights, "failed": failed, "classes": {}}
	var lines := PackedStringArray()
	lines.append("World road audit: %d cells%s" % [all.size(), " with heights" if heights else " (map only)"] + (", %d s" % (ms / 1000) if ms > 0 else ""))
	for k: String in ["crossing", "tangle", "bridge_dead_end", "bridge_end", "step", "hump", "bump", "buildings_dropped", "building_cap"]:
		if not by_class.has(k):
			continue
		var list: Array = by_class[k]
		list.sort_custom(func(p, q): return float(p["size"]) > float(q["size"]))
		report["classes"][k] = {"count": list.size(), "cells": (cells_with[k] as Dictionary).size(), "worst": list.slice(0, top)}
		lines.append("")
		lines.append("%s: %d in %d cells" % [k, list.size(), (cells_with[k] as Dictionary).size()])
		for f: Dictionary in list.slice(0, 5):
			lines.append("  %.2f  cell %s  %.5f, %.5f" % [float(f["size"]), f["cell"], float(f["lat"]), float(f["lon"])])
	if not failed.is_empty():
		lines.append("")
		lines.append("Not audited: %d cells" % failed.size())
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	var text := "\n".join(lines) + "\n"
	f = FileAccess.open(out_dir.path_join("summary.txt"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)
