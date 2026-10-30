class_name JourneyMarks
extends RefCounted
## The milestones of a long ride (Ride Anywhere v2, phase D round 3, D8: docs/scenery.md): where a road crosses into
## another country, a board in the new country's own language and script welcoming you in, its flag, and on the bigger
## roads a customs post (an old stone one where the border is open, a modern canopy and booths elsewhere, by region);
## toll plazas where the map has toll booths, their barriers lifting as you roll through (no charge); and airfields:
## runways, taxiways and aprons drawn on the land beside the roads, the runway's markings, its edge, threshold and
## approach lights lit at dusk, a windsock at a grass strip, a control tower at a bigger airport, an aircraft on a fixed
## approach seen from the road with its lights blinking, and helipads on the ground.
##
## The kit, signs, road paint and side of the road change at the border line itself, not here: RegionKit.at_frame asks
## Borders which side of a border a point is (the baker names each line for the countries to its left and right).
##
## SceneryStreamer hands lay_out a block's rows of the kinds whose kit row names this script and draws what comes back,
## every model one MultiMesh a block; dress puts in what moves (the barriers' arms, the aircraft) and the clock for the
## lamps. Simon's first rule, as here: nothing stands on a road or its verge but a canopy's roof high over it (its legs
## and booths past the verge, its arms swinging up out of the way), a runway or apron is a mesh over the land and stops
## short of any road, and nothing here has collision. The second: every kind wherever the map has it, its look by region
## from the kit library, a default for anywhere a region has none; nothing is keyed to a place.

## Part of what a block lays out: bump it with the look (SceneryStreamer folds the scripts' versions into its own).
const VERSION := 1
const SIZE := 512.0   # RoadBlock.SIZE
## How far past a road's verge a thing beside it stands (m: SceneryStreamer.CLEAR's).
const CLEAR := 1.5
## The roads a border board is put up on, and those big enough for a customs post at the line.
const BOARD_ROADS := ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street"]
const POST_ROADS := ["motorway", "trunk", "primary", "secondary"]
## A mapped border control within this of a road crossing the line is the crossing's post (m); a mapped control or toll
## booth within SNAP of a road is on it; toll booths within JOIN of each other are one plaza.
const CONTROL_NEAR := 400.0
const SNAP := 60.0
const JOIN := 90.0
## A barrier's arm lifts when a rider is within this of it (m), taking LIFT_S seconds.
const ARM_NEAR := 55.0
const LIFT_S := 1.2
## A runway: how far apart its edge lights are (m), how far out its approach lights reach, how long one must be (and in
## an airport's land) to be paved and lit, how long for an aircraft to land on it.
const EDGE_GAP := 60.0
const APPROACH := 900.0
const PAVED_MIN := 1000.0
const PLANE_MIN := 1400.0
## An aircraft's approach: from this far out (m), down a glide path of GLIDE degrees, at SPEED m/s, touching down
## AIM m past the threshold, one landing every PERIOD seconds by the clock (offset by the runway, the same for a crew).
const PLANE_FROM := 9000.0
const GLIDE := 3.0
const SPEED := 72.0
const AIM := 300.0
const PERIOD := 190.0
## A runway's piece of tarmac (m along) and an apron's tiles at the smallest and largest.
const STEP := 20.0
const TILE_MIN := 16.0
const TILE_MAX := 40.0

## The pieces' flags (UV2.x): matte, a lamp lit at night, one blinking at night, a strobe (by day too), a flag that
## waves, a windsock that sways, a window lit at night.
const MATTE := 0.0
const STEADY := 1.0
const BLINK := 2.0
const STROBE := 3.0
const WAVE := 4.0
const SOCK := 5.0
const GLOW := 6.0

const WHITE := Color(0.92, 0.92, 0.9)
const GREY := Color(0.55, 0.56, 0.57)
const DARK := Color(0.16, 0.17, 0.18)
const RED := Color(0.78, 0.1, 0.08)
const YELLOW := Color(0.92, 0.72, 0.1)
const TARMAC := Color(0.21, 0.21, 0.22)
const CONCRETE := Color(0.6, 0.6, 0.58)
const GRASS := Color(0.36, 0.56, 0.22)
const GLASS := Color(0.55, 0.7, 0.75)
const STONE := Color(0.66, 0.6, 0.5)
const ROOF := Color(0.5, 0.25, 0.18)
const LAMPS := {"w": Color(1.0, 0.95, 0.82), "g": Color(0.1, 1.0, 0.3), "r": Color(1.0, 0.1, 0.06),
	"b": Color(0.15, 0.35, 1.0), "a": Color(1.0, 0.65, 0.1)}
## The boards' colours (a kit's "board").
const BOARDS := {"blue": Color(0.05, 0.2, 0.55), "green": Color(0.05, 0.38, 0.2), "brown": Color(0.4, 0.22, 0.1),
	"white": Color(0.93, 0.93, 0.9)}

## Flags, by country (data/countries.json's codes): [layout, colours]. Layouts: "v" vertical stripes, "h" horizontal,
## "nordic" a cross off centre ([field, cross, inner cross]), "cross" a centred one, "disc" a disc on a field, "uk",
## "us", "star" a star on a field, "tri" a triangle at the hoist over stripes. A country not here flies "plain" white.
const FLAGS := {
	"FR": ["v", ["#0055a4", "#ffffff", "#ef4135"]], "IT": ["v", ["#009246", "#ffffff", "#ce2b37"]],
	"IE": ["v", ["#169b62", "#ffffff", "#ff883e"]], "BE": ["v", ["#000000", "#fdda24", "#ef3340"]],
	"RO": ["v", ["#002b7f", "#fcd116", "#ce1126"]], "MX": ["v", ["#006847", "#ffffff", "#ce1126"]],
	"PE": ["v", ["#d91023", "#ffffff", "#d91023"]], "NG": ["v", ["#008751", "#ffffff", "#008751"]],
	"MD": ["v", ["#0046ae", "#ffd200", "#cc092f"]], "TD": ["v", ["#002664", "#fecb00", "#c60c30"]],
	"ML": ["v", ["#14b53a", "#fcd116", "#ce1126"]], "GN": ["v", ["#ce1126", "#fcd116", "#009460"]],
	"CI": ["v", ["#f77f00", "#ffffff", "#009e60"]], "GT": ["v", ["#4997d0", "#ffffff", "#4997d0"]],
	"DE": ["h", ["#000000", "#dd0000", "#ffce00"]], "NL": ["h", ["#ae1c28", "#ffffff", "#21468b"]],
	"LU": ["h", ["#ed2939", "#ffffff", "#00a1de"]], "AT": ["h", ["#ed2939", "#ffffff", "#ed2939"]],
	"RU": ["h", ["#ffffff", "#0039a6", "#d52b1e"]], "BG": ["h", ["#ffffff", "#00966e", "#d62612"]],
	"HU": ["h", ["#cd2a3e", "#ffffff", "#436f4d"]], "EE": ["h", ["#0072ce", "#000000", "#ffffff"]],
	"LT": ["h", ["#fdb913", "#006a44", "#c1272d"]], "LV": ["h", ["#9e3039", "#ffffff", "#9e3039"]],
	"PL": ["h", ["#ffffff", "#dc143c"]], "UA": ["h", ["#0057b7", "#ffd700"]], "ID": ["h", ["#ce1126", "#ffffff"]],
	"MC": ["h", ["#ce1126", "#ffffff"]], "CO": ["h", ["#fcd116", "#fcd116", "#003893", "#ce1126"]],
	"ES": ["h", ["#aa151b", "#f1bf00", "#f1bf00", "#aa151b"]], "PT": ["v", ["#006600", "#006600", "#ff0000", "#ff0000", "#ff0000"]],
	"AR": ["h", ["#74acdf", "#ffffff", "#74acdf"]], "SI": ["h", ["#ffffff", "#0000ff", "#ff0000"]],
	"SK": ["h", ["#ffffff", "#0b4ea2", "#ee1c25"]], "HR": ["h", ["#ff0000", "#ffffff", "#171796"]],
	"RS": ["h", ["#c6363c", "#0c4076", "#ffffff"]], "TH": ["h", ["#a51931", "#f4f5f8", "#2d2a4a", "#2d2a4a", "#f4f5f8", "#a51931"]],
	"EG": ["h", ["#ce1126", "#ffffff", "#000000"]], "IN": ["h", ["#ff9933", "#ffffff", "#138808"]],
	"YE": ["h", ["#ce1126", "#ffffff", "#000000"]], "SY": ["h", ["#ce1126", "#ffffff", "#000000"]],
	"IQ": ["h", ["#ce1126", "#ffffff", "#000000"]], "AM": ["h", ["#d90012", "#0033a0", "#f2a800"]],
	"BO": ["h", ["#d52b1e", "#f9e300", "#007934"]], "GA": ["h", ["#009e60", "#fcd116", "#3a75c4"]],
	"SL": ["h", ["#1eb53a", "#ffffff", "#0072c6"]], "YU": ["h", ["#0c4076", "#ffffff", "#c6363c"]],
	"DK": ["nordic", ["#c8102e", "#ffffff"]], "SE": ["nordic", ["#006aa7", "#fecc02"]],
	"NO": ["nordic", ["#ba0c2f", "#ffffff", "#00205b"]], "FI": ["nordic", ["#ffffff", "#002f6c"]],
	"IS": ["nordic", ["#02529c", "#ffffff", "#dc1e35"]], "FO": ["nordic", ["#ffffff", "#0065bd", "#ef303e"]],
	"CH": ["cross", ["#da291c", "#ffffff"]], "GE": ["cross", ["#ffffff", "#ff0000"]],
	"JP": ["disc", ["#ffffff", "#bc002d"]], "BD": ["disc", ["#006a4e", "#f42a41"]], "PW": ["disc", ["#4aadd6", "#ffde00"]],
	"KR": ["disc", ["#ffffff", "#cd2e3a"]], "LA": ["disc", ["#002868", "#ffffff"]],
	"VN": ["star", ["#da251d", "#ffff00"]], "MA": ["star", ["#c1272d", "#006233"]], "CN": ["star", ["#de2910", "#ffde00"]],
	"TR": ["star", ["#e30a17", "#ffffff"]], "TN": ["star", ["#e70013", "#ffffff"]], "DZ": ["v", ["#006233", "#ffffff"]],
	"SO": ["star", ["#4189dd", "#ffffff"]], "GH": ["h", ["#ce1126", "#fcd116", "#006b3f"]],
	"CZ": ["tri", ["#ffffff", "#d7141a", "#11457e"]], "PH": ["tri", ["#0038a8", "#ce1126", "#ffffff"]],
	"JO": ["tri", ["#000000", "#ffffff", "#007a3d", "#ce1126"]], "SD": ["tri", ["#d21034", "#ffffff", "#000000", "#007229"]],
	"KE": ["h", ["#000000", "#bb0000", "#006600"]], "ZA": ["tri", ["#de3831", "#002395", "#007a4d", "#000000"]],
	"GB": ["uk", ["#012169", "#ffffff", "#c8102e"]], "AU": ["uk", ["#012169", "#ffffff", "#c8102e"]],
	"NZ": ["uk", ["#012169", "#ffffff", "#c8102e"]], "US": ["us", ["#b22234", "#ffffff", "#3c3b6e"]],
	"MY": ["us", ["#cc0001", "#ffffff", "#010066"]], "LR": ["us", ["#bf0a30", "#ffffff", "#002868"]],
	"CA": ["v", ["#d80621", "#ffffff", "#ffffff", "#d80621"]], "BR": ["disc", ["#009c3b", "#ffdf00"]],
	"CL": ["h", ["#ffffff", "#d52b1e"]], "UY": ["h", ["#ffffff", "#0038a8", "#ffffff", "#0038a8", "#ffffff"]],
	"GR": ["h", ["#0d5eaf", "#ffffff", "#0d5eaf", "#ffffff", "#0d5eaf", "#ffffff", "#0d5eaf", "#ffffff", "#0d5eaf"]],
	"AL": ["star", ["#e41e20", "#000000"]], "ME": ["star", ["#c40308", "#d4af37"]], "MK": ["disc", ["#d20000", "#ffe600"]],
	"BA": ["tri", ["#002395", "#002395", "#fecb00"]], "BY": ["h", ["#c8313e", "#c8313e", "#4aa657"]],
	"AD": ["v", ["#10069f", "#fedd00", "#d50032"]], "SM": ["h", ["#ffffff", "#5eb6e4"]], "LI": ["h", ["#002b7f", "#ce1126"]],
	"CY": ["plain", ["#ffffff"]], "MT": ["v", ["#ffffff", "#cf142b"]], "IL": ["h", ["#ffffff", "#0038b8", "#ffffff", "#ffffff", "#0038b8", "#ffffff"]],
	"SA": ["plain", ["#006c35"]], "AE": ["tri", ["#00732f", "#ffffff", "#000000", "#ff0000"]],
	"IR": ["h", ["#239f40", "#ffffff", "#da0000"]], "PK": ["star", ["#01411c", "#ffffff"]], "NP": ["plain", ["#dc143c"]],
	"MN": ["v", ["#c4272f", "#015197", "#c4272f"]], "KZ": ["disc", ["#00afca", "#fec50c"]], "UZ": ["h", ["#0099b5", "#ffffff", "#1eb53a"]],
	"KH": ["h", ["#032ea1", "#e00025", "#e00025", "#032ea1"]], "MM": ["h", ["#fecb00", "#34b233", "#ea2839"]],
	"TW": ["us", ["#fe0000", "#fe0000", "#000095"]], "HK": ["star", ["#de2910", "#ffffff"]],
	"VE": ["h", ["#ffcc00", "#00247d", "#cf142b"]], "EC": ["h", ["#ffdd00", "#ffdd00", "#034ea2", "#ed1c24"]],
	"PY": ["h", ["#d52b1e", "#ffffff", "#0038a8"]], "CR": ["h", ["#002b7f", "#ffffff", "#ce1126", "#ce1126", "#ffffff", "#002b7f"]],
	"PA": ["v", ["#ffffff", "#d21034"]], "HN": ["h", ["#0073cf", "#ffffff", "#0073cf"]], "NI": ["h", ["#0067c6", "#ffffff", "#0067c6"]],
	"SV": ["h", ["#0047ab", "#ffffff", "#0047ab"]], "BZ": ["h", ["#ce1126", "#003f87", "#003f87", "#003f87", "#ce1126"]],
	"ZW": ["h", ["#319208", "#ffd200", "#de2010", "#000000", "#de2010", "#ffd200", "#319208"]],
	"TZ": ["tri", ["#1eb53a", "#00a3dd", "#000000"]], "UG": ["h", ["#000000", "#fcdc04", "#d90000", "#000000", "#fcdc04", "#d90000"]],
	"ET": ["h", ["#078930", "#fcdd09", "#da121a"]], "SN": ["v", ["#00853f", "#fdef42", "#e31b23"]],
	"CM": ["v", ["#007a5e", "#ce1126", "#fcd116"]], "BJ": ["v", ["#008751", "#fcd116", "#e8112d"]],
	"BF": ["h", ["#ef2b2d", "#009e49"]], "NE": ["h", ["#e05206", "#ffffff", "#0db02b"]], "MR": ["star", ["#00a95c", "#ffd700"]],
	"LY": ["h", ["#e70013", "#000000", "#000000", "#239e46"]], "NA": ["tri", ["#003580", "#d21034", "#009543"]],
	"BW": ["h", ["#75aadb", "#75aadb", "#000000", "#75aadb", "#75aadb"]], "ZM": ["plain", ["#198a00"]],
	"MZ": ["tri", ["#009a44", "#000000", "#fce100", "#d21034"]], "AO": ["h", ["#cc092f", "#000000"]],
	"CD": ["star", ["#007fff", "#f7d618"]], "CG": ["h", ["#009543", "#fbde4a", "#dc241f"]],
	"RW": ["h", ["#00a1de", "#00a1de", "#fad201", "#20603d"]], "BI": ["cross", ["#ce1126", "#ffffff"]],
	"MW": ["h", ["#000000", "#ce1126", "#339e35"]], "SZ": ["h", ["#3e5eb9", "#ffd900", "#b10c0c", "#b10c0c", "#ffd900", "#3e5eb9"]],
	"LS": ["h", ["#00209f", "#ffffff", "#009543"]], "AF": ["v", ["#000000", "#be0000", "#007a36"]],
	"TJ": ["h", ["#cc0000", "#ffffff", "#006600"]], "KG": ["disc", ["#e8112d", "#ffef00"]], "TM": ["v", ["#00843d", "#00843d", "#00843d"]],
	"AZ": ["h", ["#0092bc", "#e4002b", "#00af66"]], "LB": ["h", ["#ed1c24", "#ffffff", "#ffffff", "#ed1c24"]],
	"OM": ["h", ["#ffffff", "#db161b", "#008000"]], "QA": ["v", ["#ffffff", "#8a1538", "#8a1538"]], "KW": ["tri", ["#007a3d", "#ffffff", "#ce1126", "#000000"]],
	"BH": ["v", ["#ffffff", "#ce1126", "#ce1126"]], "LK": ["plain", ["#8d153a"]], "BT": ["plain", ["#ffd520"]],
	"SG": ["h", ["#ef3340", "#ffffff"]], "BN": ["plain", ["#f7e017"]], "TL": ["tri", ["#dc241f", "#000000"]],
	"PG": ["plain", ["#ce1126"]], "FJ": ["uk", ["#68bfe5", "#ffffff", "#c8102e"]], "CU": ["tri", ["#002a8f", "#ffffff", "#002a8f", "#ffffff", "#002a8f", "#cf142b"]],
	"DO": ["cross", ["#002d62", "#ffffff"]], "HT": ["h", ["#00209f", "#d21034"]], "JM": ["plain", ["#009b3a"]],
	"PR": ["tri", ["#ed0000", "#ffffff", "#ed0000", "#ffffff", "#ed0000", "#0050f0"]], "XK": ["plain", ["#244aa5"]],
}

static var _meshes := {}
static var _meshes_lock := Mutex.new()
static var _material: ShaderMaterial
static var _regions := {}     # region instance id -> _work_out (its plazas, posts, runways, towers)
static var _regions_lock := Mutex.new()
static var _ticked := -1


# ---------------------------------------------------------------------------- laying a block out

## What block `key` holds of the rows (SceneryStreamer's: {points, lines, areas}, each [row, kit]) whose kit names this
## script: {items: {model: [Transform3D in the block's frame]}, dress: {arms, planes, lively}, skipped}. Safe on a
## worker.
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary:
	var b := Fields._Block.new(net, key)
	var dress := {"arms": [], "planes": [], "lively": false}
	var whole := _region_of(net)
	var kit_of := {}   # kind -> a kit row seen in this block (the default with its region's fields over it)
	for part: String in ["points", "lines", "areas"]:
		for pair: Array in rows.get(part, []):
			kit_of[str(pair[0][0])] = pair[1]
	for pair: Array in rows.get("lines", []):
		var row: Array = pair[0]
		match str(row[0]):
			"country_border":
				_border(b, row, pair[1], whole, dress)
			"runway":
				pass   # (the region's runways, below: each laid out from its whole line)
			"taxiway":
				_taxiway(b, row[1], row[3], pair[1])
	for pair: Array in rows.get("areas", []):
		var row: Array = pair[0]
		var ring: PackedVector2Array = row[1]
		match str(row[0]):
			"apron", "runway", "taxiway":
				_surface(b, ring, str(row[0]))
			"helipad":
				_helipad(b, Fields.centroid(ring), ring)
	for pair: Array in rows.get("points", []):
		var row: Array = pair[0]
		var p := Vector2(float(row[1]), float(row[2]))
		match str(row[0]):
			"helipad":
				_helipad(b, p, PackedVector2Array())
			"airstrip", "airfield":
				if b.mine(p) and b.clear(p, CLEAR + 2.0) and not _near_runway(whole, p, 40.0):
					b.stand("windsock", p, Vector2(0, 1), 1.0)
					dress["lively"] = true
	# (the things worked out over the whole region, each in the one block its spot is in)
	for c: Dictionary in whole["controls"]:
		if b.mine(c["at"]):
			_control(b, c, kit_of.get("border_control", SceneryStreamer.kit("border_control")), dress)
	for t: Dictionary in whole["plazas"]:
		if b.mine(t["at"]):
			_plaza(b, t, kit_of.get("toll_booth", SceneryStreamer.kit("toll_booth")), dress)
	for r: Dictionary in whole["runways"]:
		if (r["box"] as Rect2).intersects(b.box):
			_runway(b, r, dress)
	for t: Dictionary in whole["towers"]:
		if b.mine(t["at"]) and b.clear(t["at"], CLEAR + 6.0):
			b.stand("tower", t["at"], t["face"], 1.0)
			dress["lively"] = true
	var out := {"items": b.items, "skipped": b.skipped}
	if not (dress["arms"] as Array).is_empty() or not (dress["planes"] as Array).is_empty() or dress["lively"]:
		out["dress"] = dress
	return out


## The things laid out over a whole region rather than a block's rows, worked out once a region (on a worker, under a
## lock): {controls: the mapped border controls [{at, edge, s}], plazas: the toll plazas (booths within JOIN as one)
## [{at, edge, s}], runways: [{line, width, paved, ends: [is a threshold, ...], box, id}], towers: [{at, face}]}.
static func _region_of(net: RoadNet) -> Dictionary:
	var id := net.region.get_instance_id()
	_regions_lock.lock()
	var have = _regions.get(id)
	if have == null:
		have = _work_out(net)
		if _regions.size() > 4:
			_regions.clear()
		_regions[id] = have
	_regions_lock.unlock()
	return have


static func _work_out(net: RoadNet) -> Dictionary:
	var f: Dictionary = net.region.features
	var controls: Array[Vector2] = []
	var tolls: Array[Vector2] = []
	var fields: Array = []    # [kind, ring, Rect2] of the airports', airfields' and airstrips' land
	for row: Array in f.get("points", []):
		match str(row[0]):
			"border_control": controls.append(Vector2(float(row[1]), float(row[2])))
			"toll_booth": tolls.append(Vector2(float(row[1]), float(row[2])))
	for row: Array in f.get("areas", []):
		var ring: PackedVector2Array = row[1]
		match str(row[0]):
			"border_control": controls.append(Fields.centroid(ring))
			"toll_booth": tolls.append(Fields.centroid(ring))
			"airport", "airfield", "airstrip":
				fields.append([str(row[0]), ring, _box(ring)])
	var out := {"controls": _on_roads(net, _joined(controls, 120.0)), "plazas": _on_roads(net, _joined(tolls, JOIN)),
		"runways": [], "towers": []}
	# (a runway the baker cut at a cell's edge is its pieces end to end: an end that meets another's is no threshold)
	var lines: Array = []
	for row: Array in f.get("lines", []):
		if str(row[0]) == "runway" and (row[1] as PackedVector2Array).size() >= 2:
			lines.append(row)
	var ends := {}
	for row: Array in lines:
		var pts: PackedVector2Array = row[1]
		for p: Vector2 in [pts[0], pts[pts.size() - 1]]:
			var q := Vector2i(roundi(p.x), roundi(p.y))
			ends[q] = int(ends.get(q, 0)) + 1
	var lengths := {}
	for row: Array in lines:
		var pts: PackedVector2Array = row[1]
		var long := _length(pts)
		var mid := _along(pts, long * 0.5)
		var land := ""
		for fl: Array in fields:
			if (fl[2] as Rect2).has_point(mid) and Geometry2D.is_point_in_polygon(mid, fl[1]):
				land = fl[0] if land != "airport" else land
		var width = row[3]
		var paved := land == "airport" or long >= PAVED_MIN or (width != null and float(width) >= 23.0)
		if land in ["airfield", "airstrip"] and long < PAVED_MIN:
			paved = false
		var w := clampf(float(width) if width != null else (45.0 if long >= 2500.0 else 30.0 if paved else 18.0), 10.0, 75.0)
		var first := Vector2i(roundi(pts[0].x), roundi(pts[0].y))
		var last := Vector2i(roundi(pts[pts.size() - 1].x), roundi(pts[pts.size() - 1].y))
		var r := {"line": pts, "long": long, "width": w, "paved": paved, "id": str(row[6]) if row[6] != null else "",
			"ends": [int(ends.get(first, 0)) < 2, int(ends.get(last, 0)) < 2], "box": _box(pts).grow(APPROACH + 60.0),
			"land": land}
		out["runways"].append(r)
		if land == "airport" and paved and long >= 1500.0:
			lengths[_field_of(fields, mid)] = maxf(float(lengths.get(_field_of(fields, mid), 0.0)), long)
	# (a control tower beside the biggest apron of an airport with a long runway)
	for i: int in lengths:
		if i < 0:
			continue
		var ring: PackedVector2Array = fields[i][1]
		var best := PackedVector2Array()
		var most := 0.0
		for row: Array in f.get("areas", []):
			if str(row[0]) != "apron":
				continue
			var a: PackedVector2Array = row[1]
			var c := Fields.centroid(a)
			if not Geometry2D.is_point_in_polygon(c, ring):
				continue
			var area := absf(Fields.signed_area(a))
			if area > most:
				most = area
				best = a
		if best.is_empty():
			continue
		var c := Fields.centroid(best)
		var far := best[0]
		for p in best:
			if _runway_gap(out["runways"], p) > _runway_gap(out["runways"], far):
				far = p
		var away := (far - c).normalized() if far.distance_to(c) > 1.0 else Vector2(0, 1)
		out["towers"].append({"at": far + away * 30.0, "face": -away})
	return out


## Points within `gap` of each other as one, at their middle.
static func _joined(pts: Array[Vector2], gap: float) -> Array[Vector2]:
	var groups: Array = []
	for p in pts:
		var into := -1
		for i in groups.size():
			if (groups[i][0] / float(groups[i][1])).distance_to(p) < gap:
				into = i
				break
		if into < 0:
			groups.append([p, 1])
		else:
			groups[into][0] += p
			groups[into][1] += 1
	var out: Array[Vector2] = []
	for g: Array in groups:
		out.append(g[0] / float(g[1]))
	return out


## Each of `pts` with the road it's on (within SNAP): {at (the road's middle there, or the point itself), edge (-1 off
## any road), s}.
static func _on_roads(net: RoadNet, pts: Array[Vector2]) -> Array:
	var out: Array = []
	for p in pts:
		var on := net.locate(p.x, p.y, -1, false)
		if not on.is_empty() and int(on["node"]) < 0 and absf(float(on["lat"])) < SNAP:
			var e := int(on["edge"])
			out.append({"at": net.point_at(e, float(on["s"])), "edge": e, "s": float(on["s"])})
		else:
			out.append({"at": p, "edge": -1, "s": 0.0})
	return out


static func _field_of(fields: Array, p: Vector2) -> int:
	for i in fields.size():
		if str(fields[i][0]) == "airport" and (fields[i][2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, fields[i][1]):
			return i
	return -1


static func _runway_gap(runways: Array, p: Vector2) -> float:
	var best := INF
	for r: Dictionary in runways:
		var pts: PackedVector2Array = r["line"]
		for i in pts.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


static func _near_runway(whole: Dictionary, p: Vector2, d: float) -> bool:
	return _runway_gap(whole["runways"], p) < d


static func _box(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


static func _length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size() - 1:
		s += pts[i].distance_to(pts[i + 1])
	return s


static func _along(pts: PackedVector2Array, s: float) -> Vector2:
	for i in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if s <= d or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf(s / maxf(d, 1e-4), 0.0, 1.0))
		s -= d
	return pts[pts.size() - 1]


# ---------------------------------------------------------------------------- borders

## Where block `b`'s roads cross border `row` (named "LEFT|RIGHT" for the countries either side): for each way across,
## a board welcoming the rider in, in the new country's words, on the side of the road it drives on, with its flag;
## and on the bigger roads with no mapped control near, a customs post at the line.
static func _border(b: Fields._Block, row: Array, k: Dictionary, whole: Dictionary, dress: Dictionary) -> void:
	var sides := str(row[5]).split("|")
	if sides.size() != 2 or sides[0] == "" or sides[1] == "":
		return
	var line: PackedVector2Array = row[1]
	# (only the line's pieces near the block are looked at: a border follows a ridge or a river for miles)
	var near := b.box.grow(64.0)
	var segs := PackedVector2Array()
	for j in line.size() - 1:
		var sb := Rect2(line[j], Vector2.ZERO).expand(line[j + 1])
		if sb.intersects(near, true):
			segs.append(line[j])
			segs.append(line[j + 1])
	if segs.is_empty():
		return
	var lbox := _box(segs).grow(4.0)
	var n := b.n
	for e in n.edges_in(b.key):
		var cls := n.region.class_of(e)
		if not cls in BOARD_ROADS:
			continue
		var road := n.line_of(e)
		if not _box(road).intersects(lbox, true):
			continue
		var s0 := 0.0
		for i in road.size() - 1:
			var a := road[i]
			var c := road[i + 1]
			var seg := a.distance_to(c)
			if Rect2(a, Vector2.ZERO).expand(c).intersects(lbox, true):
				for j in range(0, segs.size(), 2):
					var x = Geometry2D.segment_intersects_segment(a, c, segs[j], segs[j + 1])
					if x == null or not b.mine(x):
						continue
					var dir := (c - a).normalized()
					var across := (segs[j + 1] - segs[j]).normalized()
					# (the side of the line a way leads into: its left is the first country named)
					var into := [sides[0] if across.cross(dir) < 0.0 else sides[1], sides[1] if across.cross(dir) < 0.0 else sides[0]]
					_crossing(b, e, s0 + a.distance_to(x), x, dir, into, cls, k, whole, dress)
			s0 += seg


## The boards (and perhaps a post) where edge `e` crosses the line at `x` going `dir`: into[0] the country `dir` leads
## into, into[1] the one the other way leads into.
static func _crossing(b: Fields._Block, e: int, s: float, x: Vector2, dir: Vector2, into: Array, cls: String,
		k: Dictionary, whole: Dictionary, dress: Dictionary) -> void:
	var n := b.n
	var half := n.width_of(e) * 0.5 + RoadNet.VERGE + CLEAR
	var colour := str(k.get("board", "blue"))
	for w in 2:
		var way := dir if w == 0 else -dir
		var code := str(into[w])
		var left := str(RegionKit.facts(code).get("drive", "right")) == "left"
		var right := Vector2(-way.y, way.x)
		var side := -right if left else right
		var at := x + way * 14.0 + side * (half + 1.6)
		if b.clear(at, CLEAR + 0.5):
			b.stand("board:%s:%s" % [code, colour], at, -way, 1.0)
		var pole := at + side * 3.2 + way * 1.0
		if b.clear(pole, CLEAR):
			b.stand("flag:" + code, pole, -way, 1.0)
			dress["lively"] = true
	if not cls in POST_ROADS or not bool(k.get("post", true)):
		return
	for c: Dictionary in whole["controls"]:
		if (c["at"] as Vector2).distance_to(x) < CONTROL_NEAR:
			return   # (that one is the crossing's post)
	_post(b, e, s, x, dir, str(k.get("style", "old")), [str(into[1]), str(into[0])], dress)


## A mapped border control: a post across the road it's on, or a booth where it is when it's on none.
static func _control(b: Fields._Block, c: Dictionary, k: Dictionary, dress: Dictionary) -> void:
	var at: Vector2 = c["at"]
	var e := int(c["edge"])
	if e < 0:
		if b.clear(at, CLEAR + 2.0):
			b.stand("booth", at, Vector2(0, 1), 1.0)
			dress["lively"] = true
		return
	var n := b.n
	var s := float(c["s"])
	var dir := (n.point_at(e, minf(s + 2.0, n.length_of(e))) - n.point_at(e, maxf(s - 2.0, 0.0))).normalized()
	_post(b, e, s, at, dir, str(k.get("style", "modern")), [], dress)


## A customs post across edge `e` at `at`: "old", a stone customs house beside the road with its striped barrier poles
## up (an open border), or "modern", a canopy over the road on legs past the verge, booths both sides and arms that
## lift as a rider comes. `flags`: the countries' flags flown beside it ([] for none).
static func _post(b: Fields._Block, e: int, s: float, at: Vector2, dir: Vector2, style: String, flags: Array,
		dress: Dictionary) -> void:
	var n := b.n
	var w := n.width_of(e)
	var half := w * 0.5 + RoadNet.VERGE + CLEAR
	var right := Vector2(-dir.y, dir.x)
	var y := n.road_y(e, s) if is_finite(n.road_y(e, s)) else b.ground(at)
	if is_nan(y):
		return
	dress["lively"] = true
	if style == "old":
		var house := at + right * (half + 7.0) + dir * 12.0
		if b.clear(house, CLEAR + 6.0):
			b.stand("customs_house", house, -right, 1.0)
		var hut := at - right * (half + 1.8) - dir * 10.0
		if b.clear(hut, CLEAR + 1.0):
			b.stand("sentry", hut, right, 1.0)
	else:
		var top := Fields.piece(b.local(at, y), dir, Vector3(w + 2.0 * (RoadNet.VERGE + CLEAR + 1.0), 1.0, 1.0))
		b.put("canopy", top)
		for side: float in [-1.0, 1.0]:
			var leg := at + right * side * (half + 0.6)
			if b.clear(leg, CLEAR):
				b.stand("canopy_leg", leg, dir, 1.0)
			var booth := at + right * side * (half + 2.2) + dir * 4.0
			if b.clear(booth, CLEAR + 1.0):
				b.stand("booth", booth, -right * side, 1.0)
	for side: float in [-1.0, 1.0]:
		_arm(b, at + right * side * (half + 0.3) - dir * side * 6.0, -right * side, half + 0.3, style == "old", dress)
	for i in flags.size():
		var pole := at + right * (half + 2.5 + 1.8 * i) - dir * 16.0
		if b.clear(pole, CLEAR):
			b.stand("flag:" + str(flags[i]), pole, -dir, 1.0)


## A barrier arm pivoting at `pivot` (beyond the verge), reaching `length` across the road towards `across`: a dress
## arm that lifts as a rider comes (always up when `open`).
static func _arm(b: Fields._Block, pivot: Vector2, across: Vector2, length: float, open: bool, dress: Dictionary) -> void:
	var y := b.ground(pivot)
	if is_nan(y):
		return
	b.stand("arm_post", pivot, across, 1.0)
	var o := b.local(pivot, y + 1.0)
	var basis := Basis(Vector3(across.x, 0.0, across.y), Vector3.UP, Vector3(-across.y, 0.0, across.x))
	(dress["arms"] as Array).append({"xf": Transform3D(basis, o), "length": length, "open": open})


# ---------------------------------------------------------------------------- toll plazas

## A toll plaza where the map has booths on a road: a canopy over the road on legs past the verge, a booth each side,
## the lanes' lamps under the roof, and an arm each way that lifts as a rider rolls through (no charge is taken).
static func _plaza(b: Fields._Block, t: Dictionary, k: Dictionary, dress: Dictionary) -> void:
	var at: Vector2 = t["at"]
	var e := int(t["edge"])
	if e < 0:
		if b.clear(at, CLEAR + 1.5):
			b.stand("toll_booth", at, Vector2(0, 1), 1.0)
		return
	var n := b.n
	var s := float(t["s"])
	if n.region.class_of(e) == "track":
		return
	var dir := (n.point_at(e, minf(s + 2.0, n.length_of(e))) - n.point_at(e, maxf(s - 2.0, 0.0))).normalized()
	var w := n.width_of(e)
	var half := w * 0.5 + RoadNet.VERGE + CLEAR
	var y := n.road_y(e, s)
	if not is_finite(y):
		y = b.ground(at)
	if is_nan(y):
		return
	var right := Vector2(-dir.y, dir.x)
	var roof := "toll_roof:" + str(k.get("roof", "white"))
	b.put(roof, Fields.piece(b.local(at, y), dir, Vector3(w + 2.0 * (RoadNet.VERGE + CLEAR + 1.0), 1.0, 1.0)))
	for side: float in [-1.0, 1.0]:
		var leg := at + right * side * (half + 0.6)
		if b.clear(leg, CLEAR):
			b.stand("canopy_leg", leg, dir, 1.0)
		var booth := at + right * side * (half + 2.0) - dir * 3.0
		if b.clear(booth, CLEAR + 1.0):
			b.stand("toll_booth", booth, -right * side, 1.0)
		_arm(b, at + right * side * (half + 0.3) + dir * side * 5.0, -right * side, half + 0.3, false, dress)
	dress["lively"] = true


# ---------------------------------------------------------------------------- airfields

## Runway `r`'s part in block `b`: its tarmac (or a grass strip's mown green) in pieces on the land, never over a road,
## its markings, its edge, threshold and approach lights, and the aircraft landing on it; a windsock and a shed at a
## grass strip.
static func _runway(b: Fields._Block, r: Dictionary, dress: Dictionary) -> void:
	var line: PackedVector2Array = r["line"]
	var w := float(r["width"])
	var paved := bool(r["paved"])
	var long := float(r["long"])
	var pad := CLEAR + w * 0.5
	for pc: Array in Fields.steps(b, line, STEP):
		if b.full():
			return
		var p: Vector2 = pc[0]
		var q: Vector2 = pc[1]
		if not (b.clear((p + q) * 0.5, pad) and b.clear(p, pad) and b.clear(q, pad)):
			b.skipped += 1
			continue
		var yp := _level(b, p, q - p, w)
		var yq := _level(b, q, q - p, w)
		if is_nan(yp) or is_nan(yq):
			continue
		var at_s := float(pc[2])
		b.put("tarmac" if paved else "strip", Fields.slope(b.local(p, yp + 0.08), b.local(q, yq + 0.08), w, 1.0))
		if not paved:
			continue
		var from_end := minf(at_s if bool(r["ends"][0]) else INF, long - at_s - STEP if bool(r["ends"][1]) else INF)
		var f := (q - p).normalized()
		var across := Vector2(-f.y, f.x)
		if from_end > 70.0 and fmod(at_s, 2.0 * STEP) < STEP:
			b.put("paint", Fields.slope(b.local(p, yp + 0.11), b.local(q, yq + 0.11), 0.9, 1.0))
		for side: float in [-1.0, 1.0]:
			var o := across * side * (w * 0.5 - 1.2)
			b.put("paint", Fields.slope(b.local(p + o, yp + 0.11), b.local(q + o, yq + 0.11), 0.6, 1.0))
		if from_end >= 0.0 and from_end < 40.0 and from_end > 4.0:
			b.put("threshold", Fields.slope(b.local(p, yp + 0.11), b.local(q, yq + 0.11), w - 4.0, 1.0))
		if absf(from_end - AIM) < STEP * 0.5 or absf(from_end - AIM - STEP * 2.0) < STEP * 0.5:
			b.put("aim", Fields.slope(b.local(p, yp + 0.11), b.local(q, yq + 0.11), w * 0.6, 1.0))
	if not paved:
		var mid := _along(line, long * 0.5)
		var f := (_along(line, long * 0.5 + 5.0) - mid).normalized()
		var side := Vector2(-f.y, f.x) * (1.0 if hash(str(r["id"])) % 2 == 0 else -1.0)
		var sock := mid + side * (w * 0.5 + 25.0)
		if b.mine(sock) and b.clear(sock, CLEAR + 2.0):
			b.stand("windsock", sock, f, 1.0)
			dress["lively"] = true
		var shed := mid - side * (w * 0.5 + 35.0)
		if b.mine(shed) and b.clear(shed, CLEAR + 12.0):
			b.stand("hangar_small", shed, side, 1.0)
		return
	_lights(b, r, dress)


## The height a strip `w` wide going `along` lies at `p`: the highest of the land at its middle and its edges there, so
## the land never shows through it (a runway is level across; its low edge stands a little proud instead).
static func _level(b: Fields._Block, p: Vector2, along: Vector2, w: float) -> float:
	var across := Vector2(-along.y, along.x).normalized() * (w * 0.5)
	return maxf(b.ground(p), maxf(b.ground(p + across), b.ground(p - across)))


## A paved runway's lights: white along its edges, green across each threshold and red at its far end, the approach's
## crossbars out over the land before each threshold (where it's clear of the roads), all lit at dusk.
static func _lights(b: Fields._Block, r: Dictionary, dress: Dictionary) -> void:
	var line: PackedVector2Array = r["line"]
	var w := float(r["width"])
	var long := float(r["long"])
	var any := false
	var s := 0.0
	while s <= long:
		var p := _along(line, s)
		var f := (_along(line, minf(s + 2.0, long)) - _along(line, maxf(s - 2.0, 0.0))).normalized()
		var across := Vector2(-f.y, f.x)
		for side: float in [-1.0, 1.0]:
			var q := p + across * side * (w * 0.5 + 1.5)
			if b.mine(q) and b.clear(q, CLEAR):
				b.stand("lamp:w", q, f, 1.0)
				any = true
		s += EDGE_GAP
	for end in 2:
		if not bool(r["ends"][end]):
			continue
		var at := line[0] if end == 0 else line[line.size() - 1]
		var inward := ((_along(line, 10.0) if end == 0 else _along(line, long - 10.0)) - at).normalized()
		var across := Vector2(-inward.y, inward.x)
		var k := -w * 0.5
		while k <= w * 0.5:
			var q := at + across * k
			if b.mine(q) and b.clear(q, CLEAR):
				b.stand("lamp:g", q, inward, 1.0)
				b.stand("lamp:r", q + inward * 0.6, -inward, 1.0)
				any = true
			k += 3.0
		# (the approach: a lamp every 30 m out from the threshold, a crossbar at every 150)
		var d := 30.0
		while d <= APPROACH:
			var c := at - inward * d
			var bar := 2 if is_zero_approx(fmod(d, 150.0)) else 0
			for j in range(-bar * 4, bar * 4 + 1, 2 if bar > 0 else 1):
				var q := c + across * j * 1.5
				if b.mine(q) and b.clear(q, CLEAR):
					b.stand("approach", q, inward, 1.0)
					any = true
			d += 30.0
		# (the aircraft, by the end the line starts at: landing towards it or away by the runway's own number)
		if end == 0 and b.mine(_along(line, long * 0.5)) and long >= PLANE_MIN:
			var land_end := 0 if hash(str(r["id"])) % 2 == 0 else 1
			var thr := line[0] if land_end == 0 else line[line.size() - 1]
			var into := ((_along(line, 10.0) if land_end == 0 else _along(line, long - 10.0)) - thr).normalized()
			var gy := b.ground(thr)
			if is_nan(gy):
				gy = b.bare(thr)
			if not is_nan(gy):
				(dress["planes"] as Array).append({"at": b.local(thr, gy), "dir": Vector3(into.x, 0.0, into.y),
					"long": long, "phase": float(absi(hash(str(r["id"]))) % 997)})
	if any:
		dress["lively"] = true


## A taxiway line: a strip of tarmac `width` wide (15 m where the map doesn't say), its yellow centre line, blue lamps
## along its edges.
static func _taxiway(b: Fields._Block, line: PackedVector2Array, width, _k: Dictionary) -> void:
	var w := clampf(float(width) if width != null else 15.0, 6.0, 30.0)
	var pad := CLEAR + w * 0.5
	for pc: Array in Fields.steps(b, line, STEP):
		if b.full():
			return
		var p: Vector2 = pc[0]
		var q: Vector2 = pc[1]
		if not (b.clear((p + q) * 0.5, pad) and b.clear(p, pad) and b.clear(q, pad)):
			b.skipped += 1
			continue
		var yp := _level(b, p, q - p, w)
		var yq := _level(b, q, q - p, w)
		if is_nan(yp) or is_nan(yq):
			continue
		b.put("taxi", Fields.slope(b.local(p, yp + 0.07), b.local(q, yq + 0.07), w, 1.0))
		b.put("paint_y", Fields.slope(b.local(p, yp + 0.1), b.local(q, yq + 0.1), 0.3, 1.0))
		if fmod(float(pc[2]), 3.0 * STEP) < STEP:
			var f := (q - p).normalized()
			for side: float in [-1.0, 1.0]:
				var l := p + Vector2(-f.y, f.x) * side * (w * 0.5 + 1.0)
				if b.clear(l, CLEAR):
					b.stand("lamp:b", l, f, 1.0)


## An apron's, runway's or taxiway's land drawn as tiles on it, clear of the roads (bigger tiles on bigger land).
static func _surface(b: Fields._Block, ring: PackedVector2Array, kind: String) -> void:
	var area := absf(Fields.signed_area(ring))
	var size := clampf(sqrt(area) / 12.0, TILE_MIN, TILE_MAX)
	var dir := Fields.axis(ring)
	var model := "tile:apron" if kind == "apron" else "tile:tarmac"
	for p: Vector2 in Fields.grid(b, ring, dir, size, size, 0.0, CLEAR + size * 0.75, 0.0):
		b.drape(model, p, dir, size)


## A helipad: its pad and H on the land (one in a building's outline is on its roof: left out).
static func _helipad(b: Fields._Block, p: Vector2, ring: PackedVector2Array) -> void:
	if not b.mine(p) or not b.clear(p, CLEAR + 11.0):
		return
	for row: Array in b.n.buildings_in(b.key):
		if Vector2(float(row[0]), float(row[1])).distance_to(p) < maxf(float(row[2]), float(row[3])) * 0.5:
			return
	var size := 20.0
	if ring.size() >= 3:
		size = clampf(sqrt(absf(Fields.signed_area(ring))), 12.0, 30.0)
	b.drape("helipad", p, Vector2(0, 1), size)


# ---------------------------------------------------------------------------- dressing a block (main thread)

## Puts block `node`'s barrier arms and landing aircraft in, and the lamps' clock, from lay_out's dress.
static func dress(node: Node3D, data) -> void:
	if not data is Dictionary:
		return
	if not (data["arms"] as Array).is_empty():
		var arms := _Arms.new()
		arms.setup(data["arms"])
		node.add_child(arms)
	for p: Dictionary in data["planes"]:
		var plane := _Plane.new()
		plane.setup(p)
		node.add_child(plane)
	node.add_child(_Tick.new())


## The lamps and flags by the clock, once a frame by whichever block's ticker gets there first.
static func tick() -> void:
	var f := Engine.get_process_frames()
	if f == _ticked:
		return
	_ticked = f
	var m := material()
	m.set_shader_parameter("night", Daylight.current.lamps if Daylight.current != null else 0.0)
	var t := Time.get_unix_time_from_system()
	m.set_shader_parameter("clock", fmod(t, 3600.0))
	m.set_shader_parameter("blink", 1.0 if fmod(t, 1.2) < 0.12 else 0.0)


class _Tick extends Node:
	func _process(_delta: float) -> void:
		JourneyMarks.tick()


## A block's barrier arms: each lifts as a rider comes within ARM_NEAR of it and drops behind them.
class _Arms extends Node3D:
	var arms: Array = []
	var nodes: Array[Node3D] = []
	var up := PackedFloat32Array()

	func setup(list: Array) -> void:
		name = "Barriers"
		arms = list
		for a: Dictionary in arms:
			var pivot := Node3D.new()
			pivot.transform = a["xf"]
			var mi := MeshInstance3D.new()
			mi.mesh = JourneyMarks.mesh("arm")
			mi.scale = Vector3(float(a["length"]), 1.0, 1.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mi)
			add_child(pivot)
			nodes.append(pivot)
			up.append(1.0 if bool(a["open"]) else 0.0)
			_apply(nodes.size() - 1)

	func _apply(i: int) -> void:
		var t: Transform3D = arms[i]["xf"]
		nodes[i].transform = Transform3D(t.basis * Basis(Vector3(0, 0, 1), up[i] * deg_to_rad(84.0)), t.origin)

	func _process(delta: float) -> void:
		var streamer := get_parent().get_parent() if get_parent() != null else null
		var riders: Array[Vector2] = []
		if streamer != null and streamer.has_method("riders"):
			riders = streamer.riders()
		var key: Vector2i = get_parent().get_meta("key", Vector2i.ZERO)
		var corner := Vector2(key) * JourneyMarks.SIZE
		for i in arms.size():
			var a: Dictionary = arms[i]
			var want := 1.0 if bool(a["open"]) else 0.0
			var o: Vector3 = (a["xf"] as Transform3D).origin
			for r in riders:
				if (r - corner).distance_to(Vector2(o.x, o.z)) < JourneyMarks.ARM_NEAR:
					want = 1.0
			var was := up[i]
			up[i] = move_toward(up[i], want, delta / JourneyMarks.LIFT_S)
			if up[i] != was:
				_apply(i)


## An aircraft landing on a runway by the clock: down the glide path from PLANE_FROM out, onto the runway at AIM past
## the threshold, slowing along it, gone until the next (every machine in a crew sees it in the same place).
class _Plane extends MeshInstance3D:
	var at := Vector3.ZERO
	var dir := Vector3.FORWARD
	var long := 2000.0
	var phase := 0.0

	func setup(p: Dictionary) -> void:
		name = "Aircraft"
		at = p["at"]
		dir = p["dir"]
		long = float(p["long"])
		phase = float(p["phase"])
		mesh = JourneyMarks.mesh("plane")
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visibility_range_end = 12000.0
		_move()

	func _process(_delta: float) -> void:
		_move()

	func _move() -> void:
		var got = placed(Time.get_unix_time_from_system())
		visible = got != null
		if got != null:
			transform = got

	## Where the aircraft is at time `t` (seconds by the clock on the wall), or null between landings.
	func placed(t: float) -> Variant:
		var u := fmod(t + phase, JourneyMarks.PERIOD)
		var fly := (JourneyMarks.PLANE_FROM + JourneyMarks.AIM) / JourneyMarks.SPEED
		var roll := minf(long - JourneyMarks.AIM - 200.0, 1400.0)
		var y := Basis(Vector3.UP, atan2(dir.x, dir.z))
		if u < fly:
			var d := JourneyMarks.PLANE_FROM - u * JourneyMarks.SPEED   # (metres before the threshold)
			var h := (d + JourneyMarks.AIM) * tan(deg_to_rad(JourneyMarks.GLIDE))
			# (the flare: the last stretch eases down onto the wheels)
			if d + JourneyMarks.AIM < 200.0:
				h = lerpf(0.0, 200.0 * tan(deg_to_rad(JourneyMarks.GLIDE)), pow((d + JourneyMarks.AIM) / 200.0, 1.6))
			return Transform3D(y * Basis(Vector3.RIGHT, deg_to_rad(-3.0)), at - dir * d + Vector3.UP * (h + 1.6))
		var r := u - fly
		var slow := 2.0 * roll / JourneyMarks.SPEED   # (from landing speed to a stop, evenly)
		if r > slow or roll <= 0.0:
			return null
		var s := JourneyMarks.SPEED * r - 0.5 * (JourneyMarks.SPEED / slow) * r * r
		return Transform3D(y, at + dir * (JourneyMarks.AIM + s) + Vector3.UP * 1.6)


# ---------------------------------------------------------------------------- the models

## The mesh of `model` (built once). "board:CODE:COLOUR" and "flag:CODE" are a country's.
static func mesh(model: String) -> Mesh:
	_meshes_lock.lock()
	var got = _meshes.get(model)
	_meshes_lock.unlock()
	if got != null:
		return got
	var b := _Build.new()
	var parts := model.split(":")
	match parts[0]:
		"board": _board(b, parts[1] if parts.size() > 1 else "", BOARDS.get(parts[2] if parts.size() > 2 else "", BOARDS["blue"]))
		"flag": _flag(b, parts[1] if parts.size() > 1 else "")
		"customs_house": _customs_house(b)
		"sentry": _sentry(b)
		"booth": _booth(b, Color(0.85, 0.86, 0.84))
		"toll_booth": _booth(b, Color(0.95, 0.95, 0.93))
		"canopy": _canopy(b, Color(0.8, 0.8, 0.8), 6.2)
		"toll_roof": _canopy(b, {"white": WHITE, "blue": Color(0.12, 0.3, 0.6), "red": Color(0.7, 0.15, 0.12),
			"green": Color(0.1, 0.45, 0.3), "grey": GREY}.get(parts[1] if parts.size() > 1 else "", WHITE), 5.6)
		"canopy_leg": b.box(Vector3(0, 3.0, 0), Vector3(0.6, 6.0, 0.6), Basis(), GREY)
		"arm_post": _arm_post(b)
		"arm": _arm_mesh(b)
		"tarmac": _slab(b, TARMAC)
		"strip": _slab(b, GRASS.lightened(0.12))
		"taxi": _slab(b, TARMAC.lightened(0.05))
		"paint": _slab(b, WHITE)
		"paint_y": _slab(b, YELLOW)
		"threshold": _threshold(b)
		"aim": _aim(b)
		"tile": _slab(b, CONCRETE if parts.size() > 1 and parts[1] == "apron" else TARMAC.lightened(0.04))
		"helipad": _helipad_mesh(b)
		"lamp": _lamp(b, LAMPS.get(parts[1] if parts.size() > 1 else "w", LAMPS["w"]), 0.45)
		"approach": _approach(b)
		"windsock": _windsock(b)
		"tower": _tower(b)
		"hangar_small": _hangar_small(b)
		"plane": _plane(b)
		_: b.box(Vector3(0, 1.0, 0), Vector3(0.4, 2.0, 0.4), Basis(), RED)
	var m := b.commit(material())
	_meshes_lock.lock()
	_meshes[model] = m
	_meshes_lock.unlock()
	return m


## A welcome board: a panel on two legs, its front (+z) the country's own name over its word of welcome, in its
## language and script (data/border_words.json, the words drawn by SignWords).
static func _board(b: _Build, code: String, colour: Color) -> void:
	for x in [-1.7, 1.7]:
		b.box(Vector3(x, 1.2, -0.08), Vector3(0.12, 2.4, 0.12), Basis(), GREY)
	b.box(Vector3(0, 2.35, 0), Vector3(4.4, 2.3, 0.08), Basis(), colour)
	b.box(Vector3(0, 2.35, -0.01), Vector3(4.6, 2.5, 0.06), Basis(), WHITE)
	var words := border_words(code)
	var ink := DARK if colour == BOARDS["white"] else WHITE
	var a := AdventureProps.new_arrays()
	SignWords.draw(a, str(words.get("name", code)), Vector3(0, 2.75, 0.06), Vector3.RIGHT, Vector3.UP, 0.62, ink, Vector3.BACK, 4.0)
	SignWords.draw(a, str(words.get("welcome", "WELCOME")), Vector3(0, 1.82, 0.06), Vector3.RIGHT, Vector3.UP, 0.38, ink, Vector3.BACK, 3.8)
	b.arrays(a)
	# (a ring of little stars over the name where the board is the European blue)
	if colour == BOARDS["blue"] and RegionKit.region_of(code) in ["western_europe", "nordic", "eastern_europe", "mediterranean"]:
		for i in 12:
			var t := TAU * i / 12.0
			b.box(Vector3(-1.75 + cos(t) * 0.28, 3.12 + sin(t) * 0.28, 0.06), Vector3(0.07, 0.07, 0.02), Basis(), YELLOW)


static var _words := {}


## Country `code`'s board words: {name, welcome, script} (data/border_words.json), its English name where it's not in it.
static func border_words(code: String) -> Dictionary:
	_meshes_lock.lock()
	if _words.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/border_words.json"))
		_words = v.get("countries", {}) if v is Dictionary else {}
	var got: Dictionary = _words.get(code, {})
	_meshes_lock.unlock()
	if got.is_empty():
		return {"name": str(RegionKit.facts(code).get("name", code)).to_upper(), "welcome": "WELCOME"}
	return got


## A flagpole with country `code`'s flag at its top, its fly along +x, waving in the shader.
static func _flag(b: _Build, code: String) -> void:
	b.box(Vector3(0, 3.5, 0), Vector3(0.09, 7.0, 0.09), Basis(), WHITE)
	b.box(Vector3(0, 7.05, 0), Vector3(0.16, 0.12, 0.16), Basis(), YELLOW)
	var spec: Array = FLAGS.get(code, ["plain", ["#f2f2ee"]])
	var cols: Array = []
	for c in spec[1]:
		cols.append(Color(str(c)))
	var w := 1.8
	var h := 1.2
	var top := 6.9
	# (the flag as a grid of little quads: each its colour from where it is on the flag, waving with its distance out)
	var nx := 18
	var ny := 12
	for i in nx:
		for j in ny:
			var u0 := float(i) / nx
			var u1 := float(i + 1) / nx
			var v0 := float(j) / ny
			var v1 := float(j + 1) / ny
			var col := _flag_colour(str(spec[0]), cols, (u0 + u1) * 0.5, (v0 + v1) * 0.5)
			var p := [Vector3(0.05 + u0 * w, top - v0 * h, 0), Vector3(0.05 + u1 * w, top - v0 * h, 0),
				Vector3(0.05 + u1 * w, top - v1 * h, 0), Vector3(0.05 + u0 * w, top - v1 * h, 0)]
			b.quad_waved(p, col, [u0, u1, u1, u0])


## The colour at (u along the fly, v down from the top: 0..1) of a flag laid out `layout` in `cols`.
static func _flag_colour(layout: String, cols: Array, u: float, v: float) -> Color:
	var n := cols.size()
	match layout:
		"v":
			return cols[clampi(int(u * n), 0, n - 1)]
		"h":
			return cols[clampi(int(v * n), 0, n - 1)]
		"nordic":
			var x := absf(u - 0.36)
			var y := absf(v - 0.5)
			if n > 2 and (x < 0.045 or y < 0.07):
				return cols[2]
			if x < 0.085 or y < 0.13:
				return cols[1]
			return cols[0]
		"cross":
			var x := absf(u - 0.5)
			var y := absf(v - 0.5)
			return cols[1] if (x < 0.07 and y < 0.32) or (y < 0.1 and x < 0.22) else cols[0]
		"disc":
			return cols[1] if Vector2((u - 0.5) * 1.5, v - 0.5).length() < 0.3 else cols[0]
		"star":
			var d := Vector2((u - 0.5) * 1.5, v - 0.5)
			var a := atan2(d.y, d.x)
			var r := 0.2 * (0.6 + 0.4 * cos(5.0 * a))
			return cols[1] if d.length() < r else cols[0]
		"tri":
			if u * 1.5 < 0.5 - absf(v - 0.5):
				return cols[n - 1] if n > 3 else cols[0]
			var m := maxi(1, n - (1 if n > 3 else 0))
			return cols[clampi(int(v * m), 0, m - 1)] if n > 2 else cols[1]
		"uk":
			var x := u - 0.5
			var y := (v - 0.5) * 1.5
			var diag := minf(absf(x - y * 0.66), absf(x + y * 0.66))
			if absf(x) < 0.04 or absf(y) < 0.07:
				return cols[2]
			if absf(x) < 0.08 or absf(y) < 0.14:
				return cols[1]
			if diag < 0.03:
				return cols[2]
			if diag < 0.07:
				return cols[1]
			return cols[0]
		"us":
			if u < 0.4 and v < 0.54:
				return cols[2]
			return cols[0] if posmod(int(v * 13.0), 2) == 0 else cols[1]
	return cols[0]


## An old customs house: two storeys of stone, a hipped tiled roof, a lamp by the door; its front +z.
static func _customs_house(b: _Build) -> void:
	b.box(Vector3(0, 3.0, 0), Vector3(11.0, 6.0, 7.0), Basis(), STONE)
	b.roof(Vector3(0, 6.0, 0), Vector3(11.6, 2.6, 7.6), ROOF)
	for x in [-3.6, -1.2, 1.2, 3.6]:
		for y in [1.6, 4.4]:
			b.box(Vector3(x, y, 3.51), Vector3(1.0, 1.3, 0.04), Basis(), GLASS, GLOW)
	b.box(Vector3(0, 1.1, 3.52), Vector3(1.3, 2.2, 0.04), Basis(), Color(0.35, 0.22, 0.14))
	b.lamp(Vector3(1.0, 2.6, 3.7), 0.18, STEADY, LAMPS["a"])


## A sentry box, striped.
static func _sentry(b: _Build) -> void:
	for i in 6:
		b.box(Vector3(0, 0.25 + i * 0.4, 0), Vector3(1.3, 0.4, 1.3), Basis(), RED if i % 2 == 0 else WHITE)
	b.box(Vector3(0, 2.6, 0), Vector3(1.6, 0.15, 1.6), Basis(), DARK)
	b.box(Vector3(0, 1.3, 0.66), Vector3(0.7, 1.1, 0.02), Basis(), GLASS, GLOW)


## A booth: a kiosk of glass under a flat roof, lit inside at night; its window side +z.
static func _booth(b: _Build, colour: Color) -> void:
	b.box(Vector3(0, 0.15, 0), Vector3(2.6, 0.3, 2.0), Basis(), CONCRETE)
	b.box(Vector3(0, 1.4, 0), Vector3(2.2, 2.2, 1.6), Basis(), colour)
	b.box(Vector3(0, 1.6, 0.81), Vector3(1.9, 1.1, 0.04), Basis(), GLASS, GLOW)
	b.box(Vector3(0.0, 1.6, -0.81), Vector3(1.9, 1.1, 0.04), Basis(), GLASS, GLOW)
	b.box(Vector3(0, 2.62, 0), Vector3(2.8, 0.22, 2.3), Basis(), DARK)


## A canopy's roof over a road, one metre across (stretched to the road's width by its piece) and 12 along, at
## `height`, its fascia striped and lamps under it.
static func _canopy(b: _Build, colour: Color, height: float) -> void:
	b.box(Vector3(0, height + 0.5, 0), Vector3(1.0, 1.0, 12.0), Basis(), colour)
	b.box(Vector3(0, height + 0.15, 6.02), Vector3(1.0, 0.3, 0.04), Basis(), RED)
	b.box(Vector3(0, height + 0.15, -6.02), Vector3(1.0, 0.3, 0.04), Basis(), RED)
	for z in [-4.0, 0.0, 4.0]:
		b.lamp(Vector3(0, height - 0.05, z), 0.25, STEADY, LAMPS["w"])


## A barrier's post: the box its arm pivots on.
static func _arm_post(b: _Build) -> void:
	b.box(Vector3(0, 0.55, 0), Vector3(0.45, 1.1, 0.45), Basis(), WHITE)
	b.box(Vector3(0, 1.12, 0), Vector3(0.5, 0.1, 0.5), Basis(), RED)
	b.lamp(Vector3(0, 1.3, 0), 0.12, BLINK, LAMPS["r"])


## A barrier's arm, one metre long along +x from its pivot (stretched to the road's half), striped red and white.
static func _arm_mesh(b: _Build) -> void:
	var n := 8
	for i in n:
		b.box(Vector3((i + 0.5) / n, 0, 0), Vector3(1.0 / n, 0.12, 0.08), Basis(), RED if i % 2 == 0 else WHITE)


## A unit piece of flat surface (x across, z along: -0.5..0.5, its top at 0), for a runway's, taxiway's or apron's
## tarmac, a strip's grass and the paint.
static func _slab(b: _Build, col: Color) -> void:
	b.quad(Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), col)


## A threshold's white bars across a unit piece.
static func _threshold(b: _Build) -> void:
	var n := 8
	for i in n:
		var x0 := -0.5 + (i + 0.2) / n
		var x1 := -0.5 + (i + 0.8) / n
		b.quad(Vector3(x0, 0, -0.5), Vector3(x0, 0, 0.5), Vector3(x1, 0, 0.5), Vector3(x1, 0, -0.5), WHITE)


## The aiming point's two broad bars.
static func _aim(b: _Build) -> void:
	for x in [[-0.5, -0.18], [0.18, 0.5]]:
		b.quad(Vector3(x[0], 0, -0.5), Vector3(x[0], 0, 0.5), Vector3(x[1], 0, 0.5), Vector3(x[1], 0, -0.5), WHITE)


## A helipad: a pale disc with a ring and an H (unit, scaled to the pad's size).
static func _helipad_mesh(b: _Build) -> void:
	var sides := 24
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		b.tri(Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * 0.5, Vector3(cos(a0), 0, sin(a0)) * 0.5, CONCRETE)
		b.quad(Vector3(cos(a0) * 0.42, 0.01, sin(a0) * 0.42), Vector3(cos(a0) * 0.46, 0.01, sin(a0) * 0.46),
			Vector3(cos(a1) * 0.46, 0.01, sin(a1) * 0.46), Vector3(cos(a1) * 0.42, 0.01, sin(a1) * 0.42), YELLOW)
	for r in [[-0.17, -0.11, -0.2, 0.2], [0.11, 0.17, -0.2, 0.2], [-0.11, 0.11, -0.03, 0.03]]:
		b.quad(Vector3(r[0], 0.02, r[2]), Vector3(r[0], 0.02, r[3]), Vector3(r[1], 0.02, r[3]), Vector3(r[1], 0.02, r[2]), WHITE)


## A runway lamp on its short stalk, `size` across when lit.
static func _lamp(b: _Build, col: Color, size: float) -> void:
	b.box(Vector3(0, 0.2, 0), Vector3(0.12, 0.4, 0.12), Basis(), YELLOW)
	b.lamp(Vector3(0, 0.45, 0), size, STEADY, col)


## An approach lamp on a short mast.
static func _approach(b: _Build) -> void:
	b.box(Vector3(0, 1.0, 0), Vector3(0.1, 2.0, 0.1), Basis(), Color(0.85, 0.45, 0.1))
	b.lamp(Vector3(0, 2.1, 0), 0.5, STEADY, LAMPS["w"])


## A windsock on its pole: an orange and white cone that sways in the shader.
static func _windsock(b: _Build) -> void:
	b.box(Vector3(0, 3.0, 0), Vector3(0.1, 6.0, 0.1), Basis(), WHITE)
	var rings := 5
	for i in rings:
		var x0 := 0.1 + i * 0.7
		var x1 := x0 + 0.7
		var r0 := 0.45 - i * 0.06
		var r1 := r0 - 0.06
		var col := Color(1.0, 0.45, 0.05) if i % 2 == 0 else WHITE
		for s in 8:
			var a0 := TAU * s / 8
			var a1 := TAU * (s + 1) / 8
			var p := [Vector3(x0, 5.8 + cos(a0) * r0, sin(a0) * r0), Vector3(x1, 5.8 + cos(a0) * r1 - 0.25, sin(a0) * r1),
				Vector3(x1, 5.8 + cos(a1) * r1 - 0.25, sin(a1) * r1), Vector3(x0, 5.8 + cos(a1) * r0, sin(a1) * r0)]
			b.quad_flag(p, col, SOCK, [x0, x1, x1, x0])


## A control tower: a concrete shaft, its glass cab lit at night, a red lamp blinking on top; facing +z.
static func _tower(b: _Build) -> void:
	b.box(Vector3(0, 2.0, 0), Vector3(14.0, 4.0, 10.0), Basis(), CONCRETE)
	b.lathe_box(Vector3(0, 4.0, 0), 3.2, 24.0, CONCRETE)
	b.box(Vector3(0, 29.0, 0), Vector3(8.4, 4.0, 8.4), Basis(), GLASS, GLOW)
	b.box(Vector3(0, 31.3, 0), Vector3(9.0, 0.6, 9.0), Basis(), DARK)
	b.box(Vector3(0, 33.0, 0), Vector3(0.2, 3.0, 0.2), Basis(), WHITE)
	b.lamp(Vector3(0, 34.6, 0), 0.4, BLINK, LAMPS["r"])


## A little hangar at a grass strip: a shed of green sheet with a wide door; facing +z.
static func _hangar_small(b: _Build) -> void:
	b.box(Vector3(0, 2.6, 0), Vector3(18.0, 5.2, 14.0), Basis(), Color(0.28, 0.4, 0.3))
	b.roof(Vector3(0, 5.2, 0), Vector3(18.4, 1.4, 14.4), Color(0.4, 0.42, 0.42))
	b.box(Vector3(0, 2.2, 7.02), Vector3(12.0, 4.4, 0.04), Basis(), Color(0.6, 0.62, 0.6))


## An airliner, its nose along +z: fuselage, wings, tail, engines; red and green lamps at the wingtips, a white strobe
## and the landing lights.
static func _plane(b: _Build) -> void:
	var body := Color(0.94, 0.94, 0.95)
	b.box(Vector3(0, 2.5, 0), Vector3(3.8, 3.9, 34.0), Basis(), body)
	b.box(Vector3(0, 2.3, 18.2), Vector3(3.2, 3.1, 2.6), Basis(), body)
	b.box(Vector3(0, 2.9, 19.6), Vector3(2.0, 1.6, 1.2), Basis(), Color(0.2, 0.25, 0.3))
	b.box(Vector3(0, 2.0, 1.0), Vector3(34.0, 0.4, 5.0), Basis(), body)
	b.box(Vector3(0, 3.0, -16.0), Vector3(11.0, 0.3, 3.0), Basis(), body)
	b.box(Vector3(0, 6.5, -16.0), Vector3(0.4, 7.0, 4.0), Basis(Vector3.RIGHT, -0.35), Color(0.1, 0.25, 0.55))
	for x in [-6.5, 6.5]:
		b.box(Vector3(x, 1.0, 3.0), Vector3(2.0, 2.0, 4.5), Basis(), GREY)
	for leg in [Vector3(0, 0.25, 14.0), Vector3(-3.2, 0.25, 0.0), Vector3(3.2, 0.25, 0.0)]:
		b.box(leg + Vector3(0, 0.3, 0), Vector3(0.6, 1.6, 0.6), Basis(), DARK)
	b.lamp(Vector3(-17.1, 2.0, 0.5), 0.5, STEADY, LAMPS["r"])
	b.lamp(Vector3(17.1, 2.0, 0.5), 0.5, STEADY, LAMPS["g"])
	b.lamp(Vector3(0, 4.6, 0), 0.6, STROBE, LAMPS["w"])
	b.lamp(Vector3(-17.1, 2.0, 0.0), 0.7, STROBE, LAMPS["w"])
	b.lamp(Vector3(17.1, 2.0, 0.0), 0.7, STROBE, LAMPS["w"])
	b.lamp(Vector3(0, 0.6, 15.0), 1.2, STEADY, LAMPS["w"])


## Builds a mesh of boxes, quads and lamps: vertex coloured, its flags in UV2 (see MATTE).
class _Build:
	var st := SurfaceTool.new()
	var any := false

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, flag := 0.0, w := Vector3.ZERO) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		var ps := [a, b, c]
		for i in 3:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2(flag, w[i]))
			st.add_vertex(ps[i])
		any = true

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flag := 0.0) -> void:
		tri(a, b, c, col, flag)
		tri(a, c, d, col, flag)

	## A quad of a waving flag, `w` each corner's distance out along the fly (0..1).
	func quad_waved(p: Array, col: Color, w: Array) -> void:
		quad_flag(p, col, JourneyMarks.WAVE, w)

	func quad_flag(p: Array, col: Color, flag: float, w: Array) -> void:
		tri(p[0], p[1], p[2], col, flag, Vector3(w[0], w[1], w[2]))
		tri(p[0], p[2], p[3], col, flag, Vector3(w[0], w[2], w[3]))

	## A box centred `c`, `size`, turned by `basis`.
	func box(c: Vector3, size: Vector3, basis: Basis, col: Color, flag := 0.0) -> void:
		var h := size * 0.5
		var p := []
		for i in 8:
			p.append(c + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, flag)

	## A round shaft of radius `r` from `at` up `h`.
	func lathe_box(at: Vector3, r: float, h: float, col: Color) -> void:
		var sides := 12
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			quad(at + Vector3(cos(a0) * r, 0, sin(a0) * r), at + Vector3(cos(a0) * r, h, sin(a0) * r),
				at + Vector3(cos(a1) * r, h, sin(a1) * r), at + Vector3(cos(a1) * r, 0, sin(a1) * r), col)

	## A hipped roof over a box `size` (x, rise, z) whose top's middle is `at`.
	func roof(at: Vector3, size: Vector3, col: Color) -> void:
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		var ridge := minf(hx - hz * 0.8, hx * 0.6)
		var a := at + Vector3(-hx, 0, -hz)
		var bb := at + Vector3(hx, 0, -hz)
		var c := at + Vector3(hx, 0, hz)
		var d := at + Vector3(-hx, 0, hz)
		var r0 := at + Vector3(-ridge, size.y, 0)
		var r1 := at + Vector3(ridge, size.y, 0)
		quad(d, c, r1, r0, col)
		quad(bb, a, r0, r1, col)
		tri(a, d, r0, col)
		tri(c, bb, r1, col)

	## A lamp at `at`, `size` across, that the shader turns to the camera and lights (`kind` STEADY, BLINK or STROBE).
	func lamp(at: Vector3, size: float, kind: float, col: Color) -> void:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.set_uv(corner)
			st.set_uv2(Vector2(kind, size))
			st.add_vertex(at)
		any = true

	## AdventureProps arrays (a sign's words) as matte triangles.
	func arrays(a: Dictionary) -> void:
		var v: PackedVector3Array = a["v"]
		var n: PackedVector3Array = a["n"]
		var c: PackedColorArray = a["c"]
		for i in v.size():
			st.set_normal(n[i])
			st.set_color(c[i])
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(v[i])
		any = any or v.size() > 0

	func commit(mat: Material) -> Mesh:
		var m := st.commit() if any else ArrayMesh.new()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


static func material() -> ShaderMaterial:
	if _material == null:
		var s := Shader.new()
		s.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = s
	return _material


const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float night = 0.0;   // 0 by day .. 1 with the lamps on (Daylight.lamps)
uniform float blink = 0.0;   // the beacons' and strobes' flash, by the clock
uniform float clock = 0.0;   // seconds, by the clock (the flags wave by it)
varying float glow;
varying float lit;

void vertex() {
	glow = 0.0;
	lit = 0.0;
	float flag = UV2.x;
	if (flag > 0.5 && flag < 3.5) {
		// A lamp: a square to the camera, kept a few pixels across however far, lit only when it's on.
		float on = flag < 1.5 ? night : (flag < 2.5 ? night * blink : blink);
		vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float size = max(UV2.y, -c.z * 0.004) * step(0.01, on);
		c.xy += UV * size;
		POSITION = PROJECTION_MATRIX * c;
		glow = on;
	} else {
		if (flag > 3.5 && flag < 4.5) {
			// A flag: waving more the farther out along its fly.
			float w = UV2.y;
			VERTEX.z += sin(clock * 5.0 - VERTEX.x * 3.0) * 0.16 * w;
			VERTEX.y += sin(clock * 3.1 - VERTEX.x * 2.0) * 0.04 * w;
		} else if (flag > 4.5 && flag < 5.5) {
			// A windsock: swinging about its pole a little.
			float w = UV2.y;
			VERTEX.z += sin(clock * 0.9) * 0.35 * w;
			VERTEX.y += sin(clock * 1.7) * 0.06 * w;
		} else if (flag > 5.5) {
			lit = night;
		}
		POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	}
}

void fragment() {
	if (glow > 0.0) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb * 8.0 * glow;
	} else {
		ALBEDO = COLOR.rgb * (1.0 - 0.6 * lit);
		EMISSION = vec3(1.0, 0.85, 0.6) * 1.6 * lit;
	}
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""
