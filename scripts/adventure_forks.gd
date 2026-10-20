class_name AdventureForks
extends RefCounted
## The crew's side of the forks on an adventure's road (AdventureRoute plans the ways): coming up
## to one, the sat nav and the HUD show the ways ahead (how long, on what, how twisty, about how
## long each takes), everyone votes for one (1, 2 or 3 on the bike, or the paper map's buttons)
## and sees everyone's votes; the host's pick decides, and if the host hasn't picked by the time
## anyone is LOCK_DIST from the fork it's the main road. Once decided, every player's road is
## built along that way (AdventureWorld.apply_picks), and only that way.
##
## In Shed.adventure: votes {fork: {peer: way}} and picks {fork: way}.
## Actions (Shed.request): adventure_vote {fork, way} (anyone; the host's vote is the pick) and
## adventure_fork_due {fork} (sent by whoever gets near an undecided fork first).

## How far before a fork the choice comes up, and how far before it the way's settled.
const PROMPT_DIST := 2500.0
const LOCK_DIST := 450.0
## The signpost's boards, by kind of way: board colour, text colour (a green main road sign, a
## brown one for the scenic route, a white one for the track).
const SIGN_COLOURS := {"main": [Color(0.05, 0.32, 0.16), Color(1.0, 0.86, 0.2)], "scenic": [Color(0.42, 0.22, 0.1), Color(1, 1, 1)],
	"gravel": [Color(0.93, 0.93, 0.9), Color(0.08, 0.08, 0.08)]}


static func votes() -> Dictionary:
	var v = Shed.adventure.get("votes", {})
	return v if v is Dictionary else {}


static func picks() -> Dictionary:
	var v = Shed.adventure.get("picks", {})
	return v if v is Dictionary else {}


## The way picked at fork `f`, or -1 while it's open.
static func pick_of(f: int) -> int:
	var p := picks()
	return int(p[f]) if p.has(f) else -1


## Who's voted for what at fork `f`: {peer: way}.
static func votes_of(f: int) -> Dictionary:
	var v = votes().get(f, {})
	return v if v is Dictionary else {}


static func _route() -> AdventureRoute:
	return AdventureWorld.current.route if AdventureWorld.current != null else null


static func check(peer: int, action: Dictionary) -> String:
	if not Adventure.active():
		return "There's no adventure on."
	var f := int(action.get("fork", -1))
	var r := _route()
	if f < 0 or (r != null and f >= r.forks.size()):
		return "There's no fork there."
	match str(action.get("a", "")):
		"adventure_vote":
			var w := int(action.get("way", -1))
			if w < 0 or w >= (r.forks[f]["ways"].size() if r != null else AdventureRoute.WAY_LETTERS.size()):
				return "There's no such way."
			if pick_of(f) >= 0:
				return "The way's already decided at this fork."
	return ""


## Applies a checked action; returns what to tell (with "*", the whole crew).
static func apply(peer: int, action: Dictionary, who: String) -> String:
	var f := int(action.get("fork", -1))
	if not (Shed.adventure.get("votes") is Dictionary):
		Shed.adventure["votes"] = {}
	if not (Shed.adventure.get("picks") is Dictionary):
		Shed.adventure["picks"] = {}
	var p: Dictionary = Shed.adventure["picks"]
	match str(action.get("a", "")):
		"adventure_vote":
			var w := int(action.get("way", 0))
			var all: Dictionary = Shed.adventure["votes"]
			if not (all.get(f) is Dictionary):
				all[f] = {}
			all[f][peer] = w
			if Adventure._is_host(peer):
				p[f] = w
				AdventureDiary.forked(f, w)
				return "*%s picks %s: everyone that way at the fork." % [who, way_name(f, w)]
			return "*%s votes for %s." % [who, way_name(f, w)]
		"adventure_fork_due":
			if p.has(f):
				return ""
			p[f] = 0
			AdventureDiary.forked(f, 0)
			return "*No pick at the fork, so it's %s." % way_name(f, 0)
	return ""


## "B, Hollow Pass" (just the letter when the road isn't loaded).
static func way_name(f: int, w: int) -> String:
	var r := _route()
	var way := r.way_of(f, w) if r != null else {}
	var letter: String = AdventureRoute.WAY_LETTERS[clampi(w, 0, 2)]
	return letter if way.is_empty() else "%s, %s" % [letter, str(way["name"])]


## The surfaces of `way` in words, most first: "gravel 70%, sand 30%" (just "tarmac" when it's all one).
static func surfaces_text(way: Dictionary) -> String:
	var surfs: Dictionary = way.get("surfaces", {})
	var keys := surfs.keys()
	keys.sort_custom(func(a, b): return float(surfs[a]) > float(surfs[b]))
	var len_m := maxf(float(way.get("len", 1.0)), 1.0)
	if keys.size() == 1:
		return str(AdventureSurface.NAMES.get(keys[0], keys[0])).to_lower()
	var bits := PackedStringArray()
	for k in keys:
		var share := float(surfs[k]) / len_m
		if share >= 0.08:
			bits.append("%s %d%%" % [str(AdventureSurface.NAMES.get(k, k)).to_lower(), roundi(share * 100.0)])
	return ", ".join(bits)


## How twisty `way` is, in a word or two.
static func twist_text(way: Dictionary) -> String:
	var t := float(way.get("twist", 0.0))
	if t < 80.0:
		return "fairly straight"
	if t < 160.0:
		return "sweeping"
	if t < 300.0:
		return "twisty"
	return "very twisty"


## The line for `way`: "6.2 km, about 5 min, tarmac, sweeping, climbs 180 m".
static func way_text(way: Dictionary) -> String:
	var text := "%.1f %s, about %d min, %s, %s" % [Units.distance_value(float(way["len"]) / 1000.0), Units.distance_unit(),
		maxi(1, roundi(float(way["time"]) / 60.0)), surfaces_text(way), twist_text(way)]
	if float(way.get("top", 0.0)) > 60.0:
		text += ", up %d m" % roundi(float(way["top"]))
	return text


## What the sat nav and the HUD show coming up to a fork from `s` along `route`: {} when there's
## none within PROMPT_DIST, else {fork, dist (m to it), picked (-1 while open), ways: [{letter,
## arrow, name, text, kind, voters (names), picked}]}.
static func choice(route: AdventureRoute, s: float) -> Dictionary:
	if route == null:
		return {}
	var f := route.next_fork(s)
	if f < 0:
		return {}
	var dist := route.fork_s(f) - s
	if dist > PROMPT_DIST:
		return {}
	var picked := pick_of(f)
	var out := {"fork": f, "dist": maxf(dist, 0.0), "picked": picked, "ways": []}
	var vs := votes_of(f)
	for w in route.forks[f]["ways"].size():
		var way: Dictionary = route.forks[f]["ways"][w]
		var voters := PackedStringArray()
		for peer in vs:
			if int(vs[peer]) == w:
				voters.append(str(Shed.crew.get(peer, {}).get("name", "?")))
		out["ways"].append({"letter": way["letter"], "arrow": way["arrow"], "name": way["name"], "kind": way["kind"],
			"text": way_text(way), "voters": voters, "picked": picked == w})
	return out


## The lines of the choice for the HUD panel and the sat nav: a heading, then one per way.
static func choice_lines(c: Dictionary, keys := true) -> PackedStringArray:
	var out := PackedStringArray()
	var dist := float(c["dist"])
	var at := "Fork in %.1f %s" % [Units.distance_value(dist / 1000.0), Units.distance_unit()] if dist > 30.0 else "Fork here"
	var letters := PackedStringArray()
	for w in c["ways"]:
		letters.append(str(w["letter"]))
	if int(c["picked"]) >= 0:
		out.append("%s: %s it is" % [at, str(c["ways"][int(c["picked"])]["letter"])])
	else:
		out.append("%s: %s or %s?%s" % [at, ", ".join(letters.slice(0, letters.size() - 1)), letters[-1],
			"  Vote 1-%d, the host decides" % letters.size() if keys else ""])
	for k in c["ways"].size():
		var w: Dictionary = c["ways"][k]
		var mark := "> " if bool(w["picked"]) else ""
		var who := "  [%s]" % ", ".join(w["voters"]) if not (w["voters"] as PackedStringArray).is_empty() else ""
		out.append("%s%s %s %s: %s%s" % [mark, str(w["letter"]), str(w["arrow"]), str(w["name"]), str(w["text"]), who])
	return out


## The signpost before fork `site["fork"]`: a board for each way, its arrow, letter, name and
## length, facing riders coming up to it.
static func signpost(site: Dictionary, xf: Transform3D, route: AdventureRoute) -> Node3D:
	var f := int(site.get("fork", -1))
	if route == null or f < 0 or f >= route.forks.size():
		return null
	var ways: Array = route.forks[f]["ways"]
	var root := Node3D.new()
	root.name = "Signpost"
	root.transform = xf
	var a := AdventureProps.new_arrays()
	var x0 := 0.5
	var bw := 6.0
	var top := 1.8 + ways.size() * 0.86
	for sx: float in [x0 + 0.25, x0 + bw - 0.25]:
		AdventureProps.box(a, Transform3D(Basis(), Vector3(sx, 0.0, 0.0)), Vector3(0.16, top + 0.3, 0.16), Color(0.3, 0.3, 0.32))
	for k in ways.size():
		var way: Dictionary = ways[k]
		var cols: Array = SIGN_COLOURS.get(str(way["kind"]), SIGN_COLOURS["main"])
		var y := top - 0.5 - k * 0.86
		AdventureProps.box(a, Transform3D(Basis(), Vector3(x0 + bw * 0.5, y - 0.37, 0.09)), Vector3(bw, 0.74, 0.05), cols[0])
		var label := Label3D.new()
		label.text = "%s  %s  %s   %.1f km" % [str(way["arrow"]), str(way["letter"]), str(way["name"]), float(way["len"]) / 1000.0]
		label.font_size = 76
		label.pixel_size = 0.0058
		label.modulate = cols[1]
		label.outline_size = 0
		label.position = Vector3(x0 + bw * 0.5, y, 0.125)
		label.visibility_range_end = 160.0
		root.add_child(label)
	var head := Label3D.new()
	head.text = "FORK AHEAD"
	head.font_size = 64
	head.pixel_size = 0.0058
	head.outline_size = 6
	head.position = Vector3(x0 + bw * 0.5, top + 0.25, 0.09)
	head.visibility_range_end = 160.0
	root.add_child(head)
	var mi := MeshInstance3D.new()
	mi.mesh = AdventureProps.to_mesh(a)
	root.add_child(mi)
	return root
