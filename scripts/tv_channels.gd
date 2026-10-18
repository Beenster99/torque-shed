class_name TvChannels
extends RefCounted
## The channels on the shed's screens: the wall TVs bought from the parts computer, and the
## screens built into the shed (one over each bay and the crew board). Look at a screen and
## press R (right mouse, X on a pad) for the next channel, T (B on a pad) for the one before.
##
## Every screen has a key: "f<furniture id>" for a bought TV, "bay0".."bay3" for the bay
## screens and "crew" for the crew board. What each one is tuned to is shed state
## (Shed.screens), changed through the host, so the whole crew sees the same channel.
##
## The money pages read their numbers from one function each here (money_data, garage_data,
## afford_data, see Money); contracts_data returns placeholders until contracts arrive, so
## wiring it up later only touches that function.

## The channels every screen has, in order. A screen's own home channel goes first.
const CHANNELS: Array[String] = ["live", "crew", "xp", "howto", "money_me", "money_garage", "afford", "sales", "contracts", "staff", "workflow"]
const NAMES := {"bay": "Bay", "live": "Live riding", "crew": "Crew board", "xp": "XP goals", "howto": "How to play",
	"money_me": "My money", "money_garage": "Garage money", "afford": "What you can afford", "contracts": "Contracts",
	"sales": "Sales", "staff": "Staff", "workflow": "Workflow"}
const BUILT_IN: Array[String] = ["crew", "bay0", "bay1", "bay2", "bay3"]
## The how-to-play pages turn over on their own, this many seconds each.
const HOWTO_PAGE_TIME := 9.0
const HEADER_INK := Color(0.05, 0.05, 0.05)
const ORANGE := Color(1.0, 0.55, 0.15)
const AMBER := Color(1.0, 0.78, 0.3)
const PANEL := Color(1, 1, 1, 0.05)
const CURRENCY := "£"

## How to play, a page at a time: [title, [[key, what it does]...]]. A blank key is a plain line.
const HOWTO := [
	["The idea", [
		["", "Strip rusty project bikes down, restore every part,"],
		["", "build them back up and ride them out of the roller door."],
		["Look", "at anything: the panel on the right says what it is"],
		["Hold", "the work button to do the job the panel shows"],
		["Co-op", "everyone works on the same bikes, live"],
	]],
	["On foot", [
		["{move}", "walk  ·  {look}: look  ·  {sprint}: run  ·  {crouch}: crouch"],
		["{tool_next}", "next tool  ·  {tool_prev}: the one before (or the number keys)"],
		["{work}", "hold to work"],
		["{interact}", "use, ride, unpack, pick up kit"],
		["{ping}", "ping what you're looking at for the crew"],
		["{alt_act}", "next TV channel when you look at a screen"],
	]],
	["Restoring a bike", [
		["Wrench", "unbolt the part, then take it off with your hands"],
		["Brush", "scrub off dirt, or leave it in the parts washer"],
		["Grinder", "rust and wear, on a repair machine"],
		["Spray", "paint: the can anywhere, the gun in the booth"],
		["Fit", "hold the part, look at the bike, then bolt it up"],
	]],
	["Riding", [
		["{ignition}", "engine on or off  ·  {throttle}: throttle  ·  {front_brake}: front brake"],
		["{rear_brake}", "rear brake  ·  {lean}: lean  ·  {shift_up|shift_down}: gears"],
		["{body_back}", "weight back for a wheelie  ·  {body_forward}: forward"],
		["{respawn}", "reset after a crash  ·  {camera}: camera"],
		["{interact}", "get off when you've stopped"],
	]],
	["Keep the shed tidy", [
		["General", "the black bin takes anything, and old fluid"],
		["Plastic", "the blue bin: oil and brake fluid bottles, cases"],
		["Metal", "the green bin: frames, engines, wheels, cans"],
		["Look", "at a part: its info says which bin it goes in"],
		["XP", "recycling earns more than binning"],
	]],
]


# ---------------------------------------------------------------------------- channels

## Whether a screen with this key is in the shed.
static func screen_exists(key: String) -> bool:
	if BUILT_IN.has(key):
		return true
	if key.begins_with("bay") and key.substr(3).is_valid_int():
		# Bays the garage's extension added (GarageUpgrades) have screens too.
		return int(key.substr(3)) < Workshop.bay_count()
	if key.begins_with("f") and key.substr(1).is_valid_int():
		var f: Dictionary = Shed.furniture.get(int(key.substr(1)), {})
		return str(f.get("kind", "")) == "tv"
	return false


## The channel a screen shows until someone changes it.
static func home(key: String) -> String:
	if key.begins_with("bay"):
		return "bay"
	if key == "crew":
		return "crew"
	return "live"


## Every channel a screen has, its home channel first.
static func channels_for(key: String) -> Array:
	var out := [home(key)]
	if key.begins_with("bay"):
		out.append("workflow")   # a bay screen's next channel is its bike's job card (see WorkflowTv)
	for ch in CHANNELS:
		if not out.has(ch):
			out.append(ch)
	return out


## The channel after (step 1) or before (step -1) `was` ({ch, rider}) on a screen. The live
## channel has one stop per rider out on the road before moving on.
static func step(key: String, was: Dictionary, dir: int, riders: Array) -> Dictionary:
	var list := channels_for(key)
	var ch := str(was.get("ch", home(key)))
	if not list.has(ch):
		ch = home(key)
	if ch == "live" and riders.size() > 1:
		var i := maxi(0, riders.find(int(was.get("rider", 0))))
		var j := i + dir
		if j >= 0 and j < riders.size():
			return {"ch": "live", "rider": int(riders[j])}
	var next: String = list[posmod(list.find(ch) + dir, list.size())]
	var rider := 0
	if next == "live" and not riders.is_empty():
		rider = int(riders[0] if dir > 0 else riders[riders.size() - 1])
	return {"ch": next, "rider": rider}


## The peer a live channel is showing: the one it follows if they're still out, else the first.
static func live_rider(state: Dictionary, riders: Array) -> int:
	var want := int(state.get("rider", 0))
	if riders.has(want):
		return want
	return int(riders[0]) if not riders.is_empty() else 0


## "CH 3  XP GOALS", or "CH 1  LIVE: SIMON", for the on-screen display.
static func osd_label(key: String, state: Dictionary, riders: Array) -> String:
	var ch := str(state.get("ch", home(key)))
	var n := channels_for(key).find(ch) + 1
	var title := channel_name(key, ch)
	if ch == "live":
		var peer := live_rider(state, riders)
		title = "Live: %s" % str(Shed.crew[peer]["name"]) if Shed.crew.has(peer) else "Live: nobody riding"
	return "CH %d  %s" % [n, title.to_upper()]


static func channel_name(key: String, ch: String) -> String:
	if ch == "bay":
		return "Bay %d" % (int(key.trim_prefix("bay")) + 1)
	return str(NAMES.get(ch, ch))


# ---------------------------------------------------------------------------- page data

static func _progress() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Progress") if tree and tree.root else null


static func _crew_color(peer: int) -> Color:
	return Shed.PAINTS[int(Shed.crew.get(peer, {}).get("slot", 0)) % Shed.PAINTS.size()]


## The live channel with nobody out: the bikes that are ready to go.
static func nobody_data() -> Dictionary:
	var ready := []
	for id in Shed.bikes:
		if Shed.is_complete(id):
			var bay := int(Shed.bikes[id]["bay"])
			ready.append("%s  ·  %s" % [Shed.bikes[id]["name"], "bay %d" % (bay + 1) if bay >= 0 else "outside"])
	return {"ready": ready}


## Everyone's level and XP from the Progress autoload, and this player's goals.
## {offline: true} when the XP system isn't running.
static func xp_data() -> Dictionary:
	var prog := _progress()
	if prog == null or not prog.has_method("summary"):
		return {"offline": true}
	var players := []
	var ids: Array = Shed.crew.keys()
	ids.sort()
	for peer in ids:
		var s = prog.summary(int(peer))
		if s is Dictionary and not s.is_empty():
			var row: Dictionary = s.duplicate()
			row["name"] = str(s.get("name", Shed.crew[peer].get("name", "Rider")))
			row["color"] = _crew_color(int(peer))
			row["me"] = int(peer) == Shed.me()
			players.append(row)
	var mine = prog.summary(Shed.me())
	if players.is_empty() and not (mine is Dictionary and not mine.is_empty()):
		return {"offline": true}
	return {"players": players, "me": mine if mine is Dictionary else {}}


static func howto_data() -> Dictionary:
	var page := int(Time.get_ticks_msec() / 1000.0 / HOWTO_PAGE_TIME) % HOWTO.size()
	return {"page": page}


## This player's own money: cash in hand (from their Progress profile), the week's money in and
## out and how it's grown (from this machine's own log; other players show just their cash).
static func money_data(peer: int) -> Dictionary:
	var prog := _progress()
	var cash: int = int(prog.money_of(peer)) if prog and prog.has_method("money_of") else 0
	var flow := {"earned": 0, "spent": 0}
	var range_key := Settings.money_graph_range
	var history := []
	for i in int(MoneyGraph.RANGES[range_key]["count"]):
		history.append(cash)
	var sold := 0
	if prog and peer == Shed.me() and prog.has_method("cash_flow"):
		flow = prog.cash_flow(7)
		history = prog.cash_graph(range_key)
		sold = int(prog.profile.get("stats", {}).get("sell_bike", 0))
	return {"name": str(Shed.crew.get(peer, {}).get("name", "You")), "cash": cash,
		"earned_week": int(flow["earned"]), "spent_week": int(flow["spent"]), "sold": sold, "history": history,
		"range": range_key}


## The business's account (Shed.garage_money), what its bikes and loose parts would fetch, the
## last seven days' money in and out (from its ledger) and its balance day by day.
static func garage_data() -> Dictionary:
	var worth := Money.shed_worth()
	var flow := Money.flow(Shed.bank, 7)
	return {"cash": Money.balance(), "bike_value": int(worth["bikes"]), "stock_value": int(worth["stock"]),
		"income_week": int(flow["in"]), "outgoings_week": int(flow["out"]), "bikes": Shed.bikes.size(),
		"history": Money.graph(Settings.money_graph_range), "range": Settings.money_graph_range, "debt": Money.debt(Shed.bank),
		"bills_day": Money.bill_total(Money.bill_lines(Shed.bank)), "overdraft": int(Shed.bank.get("overdraft", 0))}


## Things worth saving up for, what they cost the business, and whether this player's cash covers them.
static func afford_data(peer: int) -> Dictionary:
	var picks := [["A project bike", "Bikes", Money.typical_project_price()]]
	for part in ["sport_ecu", "race_slick", "carbon_monocoque", "four_1000", "tft_colour", "floating_310"]:
		if not PartsDB.get_part(part).is_empty():
			picks.append([PartsDB.part_name(part), "Bike", Money.buy_price(part, peer)])
	var items := []
	for p in picks:
		items.append({"name": p[0], "what": p[1], "price": int(p[2])})
	return {"cash": int(money_data(peer)["cash"]), "items": items}


## Jobs for the shed: offered (customers at reception), being worked on (with how far along
## each is and its deadline) and done. See Contracts.tv_data.
static func contracts_data() -> Dictionary:
	return Contracts.tv_data()


## The data for a channel's page, for the screen `key` on this player's game.
static func page_data(ch: String) -> Dictionary:
	match ch:
		"xp":
			return xp_data()
		"howto":
			return howto_data()
		"money_me":
			return money_data(Shed.me())
		"money_garage":
			return garage_data()
		"afford":
			return afford_data(Shed.me())
		"contracts":
			return contracts_data()
		"sales":
			return Sales.tv_data()
		"staff":
			return Staff.tv_data()
		"live":
			return nobody_data()
	return {}


## The Dashboard page a channel draws ("live" with nobody out shows "nobody").
static func page_kind(ch: String) -> String:
	return "nobody" if ch == "live" else ch


static func money_text(v: int) -> String:
	var digits := str(absi(v))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if v < 0 else "") + CURRENCY + digits + out


# ---------------------------------------------------------------------------- drawing

## Any {action} in `text` shows that action's key on the device in use (see Controls.hint).
static func _text(c: Control, font: Font, pos: Vector2, text: String, size: int, color := Color.WHITE, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	c.draw_string(font, pos, Controls.hint(text), align, width, size, color)


static func _title(c: Control, font: Font, title: String, right := "") -> void:
	_text(c, font, Vector2(24, 50), title, 40, HEADER_INK)
	if right != "":
		_text(c, font, Vector2(520, 48), right, 24, HEADER_INK, 480, HORIZONTAL_ALIGNMENT_RIGHT)


static func _bar(c: Control, rect: Rect2, frac: float, color: Color) -> void:
	c.draw_rect(rect, Color(1, 1, 1, 0.1))
	c.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), color)


## A box with a small label and a big number.
static func _tile(c: Control, font: Font, rect: Rect2, label: String, value: String, color := Color.WHITE) -> void:
	c.draw_rect(rect, PANEL)
	c.draw_rect(Rect2(rect.position, Vector2(6, rect.size.y)), ORANGE)
	_text(c, font, rect.position + Vector2(20, 32), label, 20, Dashboard.DIM)
	_text(c, font, rect.position + Vector2(20, rect.size.y - 18), value, 36, color)


## The amber "coming in a later update" tag on the placeholder pages.
static func _later(c: Control, font: Font, what: String) -> void:
	var r := Rect2(24, Dashboard.PX.y - 50, Dashboard.PX.x - 48, 36)
	c.draw_rect(r, Color(AMBER, 0.12))
	c.draw_rect(r, Color(AMBER, 0.7), false, 2.0)
	_text(c, font, r.position + Vector2(14, 25), "COMING IN A LATER UPDATE", 18, AMBER)
	_text(c, font, r.position + Vector2(290, 25), what, 18, Color(1, 1, 1, 0.7))


## A simple growth chart: a line through `values`, oldest first, with day marks under it.
static func _chart(c: Control, font: Font, rect: Rect2, values: Array, label: String) -> void:
	chart(c, font, rect, values, label, "day")


## A growth chart over in-game time: a line through `values`, oldest first, one a bucket of
## `range_key` (see MoneyGraph: minutes up to years), with marks under it ("-3d" .. "now"),
## thinned out when there are lots of them. The scale is zoomed to where the money is (see
## chart_scale), so a few hundred in or out of an account of thousands still shows.
static func chart(c: Control, font: Font, rect: Rect2, values: Array, label: String, range_key: String) -> void:
	c.draw_rect(rect, PANEL)
	_text(c, font, rect.position + Vector2(16, 28), label, 20, Dashboard.DIM)
	var plot := Rect2(rect.position + Vector2(60, 44), rect.size - Vector2(80, 80))
	var span := chart_scale(values)
	var lo: float = span.x
	var hi: float = span.y
	var every := maxi(1, ceili(values.size() * 64.0 / maxf(plot.size.x, 1.0)))
	for i in 3:
		var y := plot.position.y + plot.size.y * i / 2.0
		c.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08), 1.0)
	c.draw_line(Vector2(plot.position.x, plot.end.y), plot.end, Color(1, 1, 1, 0.3), 2.0)
	var pts := chart_points(values, plot, lo, hi)
	for i in values.size():
		if (values.size() - 1 - i) % every == 0:
			var tick := MoneyGraph.tick_text(range_key, i, values.size())
			_text(c, font, Vector2(pts[i].x - 30, plot.end.y + 26), "today" if tick == "now" and range_key == "day" else tick,
				15, Dashboard.DIM, 60, HORIZONTAL_ALIGNMENT_CENTER)
	if pts.size() > 1:
		c.draw_polyline(pts, ORANGE, 4.0, true)
	for p in pts:
		c.draw_circle(p, 5.0 if pts.size() <= 24 else 2.5, ORANGE)
	# The top and bottom of the scale, so the line reads as money.
	_text(c, font, Vector2(plot.position.x - 56, plot.position.y + 6), _short_money(hi), 13, Dashboard.DIM, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, font, Vector2(plot.position.x - 56, plot.end.y + 4), _short_money(lo), 13, Dashboard.DIM, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	if values.all(func(v): return float(v) == 0.0):
		_text(c, font, plot.position + Vector2(0, plot.size.y * 0.5 - 16), "Nothing in or out yet", 22, Dashboard.DIM, plot.size.x,
			HORIZONTAL_ALIGNMENT_CENTER)
	elif values.all(func(v): return float(v) == float(values[0])):
		_text(c, font, plot.position + Vector2(0, plot.size.y * 0.5 - 16), "No money in or out in the %s" % MoneyGraph.span_text(range_key),
			18, Dashboard.DIM, plot.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## The bottom and top of a money chart's scale (x, y) for `values`: a little under the lowest
## to a little over the highest, from nothing when the money has come up from near nothing, and
## a band round the line when it's flat.
static func chart_scale(values: Array) -> Vector2:
	if values.is_empty():
		return Vector2(0.0, 1.0)
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var pad := maxf((hi - lo) * 0.15, maxf(absf(hi) * 0.02, 10.0))
	var bottom := lo - pad
	if lo >= 0.0 and (bottom < 0.0 or lo <= (hi - lo) * 0.5):
		bottom = 0.0
	return Vector2(bottom, maxf(hi + pad, bottom + 1.0))


## Where each of `values` goes in `plot` on the scale from `lo` to `hi`.
static func chart_points(values: Array, plot: Rect2, lo: float, hi: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in values.size():
		var x := plot.position.x + plot.size.x * i / maxf(1.0, values.size() - 1.0)
		var f := clampf((float(values[i]) - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
		pts.append(Vector2(x, plot.end.y - plot.size.y * f))
	return pts


## "£12k", "£1.2m", "£800": a short amount for a chart's scale.
static func _short_money(v: float) -> String:
	if v < 0.0:
		return "-" + _short_money(-v)
	if v >= 1000000.0:
		return CURRENCY + "%.1fm" % (v / 1000000.0)
	if v >= 100000.0:
		return CURRENCY + "%dk" % roundi(v / 1000.0)
	if v >= 1000.0:
		return CURRENCY + "%.1fk" % (v / 1000.0)
	return CURRENCY + "%d" % roundi(v)


## Draws a channel's page (below the orange header bar the Dashboard has already drawn).
static func draw_page(c: Control, font: Font, kind: String, data: Dictionary) -> void:
	match kind:
		"nobody":
			_draw_nobody(c, font, data)
		"xp":
			_draw_xp(c, font, data)
		"howto":
			_draw_howto(c, font, data)
		"money_me":
			_draw_money_me(c, font, data)
		"money_garage":
			_draw_garage(c, font, data)
		"afford":
			_draw_afford(c, font, data)
		"contracts":
			_draw_contracts(c, font, data)
		"sales":
			Sales.draw_tv(c, font, data)
		"staff":
			_draw_staff(c, font, data)
		"workflow":
			WorkflowTv.draw(c, font, data)
		_:
			_title(c, font, "NO SIGNAL")


static func _draw_nobody(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "LIVE RIDING")
	c.draw_circle(Vector2(1000 - 120, 35), 9.0, Color(0.6, 0.05, 0.05))
	_text(c, font, Vector2(1000 - 100, 44), "OFF AIR", 22, HEADER_INK)
	_text(c, font, Vector2(24, 150), "Nobody's out riding", 52)
	_text(c, font, Vector2(24, 200), "Get on a finished bike ({interact}) and you're live on every TV tuned here.", 22, Dashboard.DIM)
	var ready: Array = data.get("ready", [])
	_text(c, font, Vector2(24, 270), "READY TO RIDE", 22, ORANGE)
	if ready.is_empty():
		_text(c, font, Vector2(24, 312), "No bike is finished yet. Fill every slot and bolt it all up.", 26, Dashboard.DIM)
	var y := 312.0
	for line in ready:
		c.draw_rect(Rect2(14, y - 30, Dashboard.PX.x - 28, 42), PANEL)
		c.draw_rect(Rect2(14, y - 30, 8, 42), Dashboard.GOOD)
		_text(c, font, Vector2(34, y), str(line), 28)
		y += 50.0
		if y > Dashboard.PX.y - 20:
			break


static func _draw_xp(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "XP GOALS", "Level up by doing the work")
	if data.get("offline", false):
		_text(c, font, Vector2(24, 170), "XP system starting up", 52)
		_text(c, font, Vector2(24, 225), "Levels, goals and points show here once it's running.", 26, Dashboard.DIM)
		_text(c, font, Vector2(24, 265), "Keep working: fitting, cleaning, restoring and riding all count.", 26, Dashboard.DIM)
		_bar(c, Rect2(24, 320, 976, 22), fmod(Time.get_ticks_msec() / 4000.0, 1.0), Color(ORANGE, 0.6))
		return
	# Left: everyone's level. Right: your goals.
	_text(c, font, Vector2(24, 108), "THE CREW", 20, Dashboard.DIM)
	var y := 150.0
	for p in data.get("players", []):
		var lv := int(p.get("level", 1))
		var start := float(p.get("xp_level_start", 0))
		var next := float(p.get("xp_next", start + 1.0))
		var xp := float(p.get("xp", 0))
		c.draw_rect(Rect2(14, y - 34, 470, 74), PANEL)
		c.draw_rect(Rect2(14, y - 34, 8, 74), p.get("color", Color.WHITE))
		_text(c, font, Vector2(34, y), str(p["name"]).left(14), 28, AMBER if p.get("me", false) else Color.WHITE)
		_text(c, font, Vector2(330, y), "LV %d" % lv, 30, ORANGE, 140, HORIZONTAL_ALIGNMENT_RIGHT)
		_bar(c, Rect2(34, y + 12, 300, 14), (xp - start) / maxf(1.0, next - start), Dashboard.GOOD)
		_text(c, font, Vector2(340, y + 26), "%d / %d" % [roundi(xp), roundi(next)], 16, Dashboard.DIM, 130, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 84.0
		if y > Dashboard.PX.y - 40:
			break
	var me: Dictionary = data.get("me", {})
	_text(c, font, Vector2(510, 108), "YOUR GOALS", 20, Dashboard.DIM)
	var goals: Array = me.get("goals", [])
	if goals.is_empty():
		_text(c, font, Vector2(510, 150), "No goals right now.", 26, Dashboard.DIM)
	var gy := 150.0
	for g in goals:
		var done := bool(g.get("done", false))
		var have := float(g.get("have", 0))
		var need := maxf(1.0, float(g.get("need", 1)))
		c.draw_rect(Rect2(510, gy - 22, 22, 22), Dashboard.GOOD if done else Color(1, 1, 1, 0.15))
		if done:
			c.draw_polyline(PackedVector2Array([Vector2(514, gy - 11), Vector2(520, gy - 4), Vector2(529, gy - 18)]), Dashboard.BG, 3.0)
		_text(c, font, Vector2(544, gy), str(g.get("text", "")).left(30), 22, Dashboard.DIM if done else Color.WHITE)
		_text(c, font, Vector2(880, gy), "+%d XP" % int(g.get("xp", 0)), 20, AMBER, 120, HORIZONTAL_ALIGNMENT_RIGHT)
		_bar(c, Rect2(544, gy + 10, 336, 8), have / need, Dashboard.GOOD if done else ORANGE)
		_text(c, font, Vector2(880, gy + 22), "%d / %d" % [roundi(minf(have, need)), roundi(need)], 15, Dashboard.DIM, 120, HORIZONTAL_ALIGNMENT_RIGHT)
		gy += 58.0
		if gy > Dashboard.PX.y - 60:
			break
	if not me.is_empty():
		_text(c, font, Vector2(510, Dashboard.PX.y - 22), "Tool points %d   ·   Skill points %d" % [int(me.get("tool_points", 0)),
			int(me.get("skill_points", 0))], 22, AMBER)


static func _draw_howto(c: Control, font: Font, data: Dictionary) -> void:
	var page := clampi(int(data.get("page", 0)), 0, HOWTO.size() - 1)
	_title(c, font, "HOW TO PLAY", "%d / %d" % [page + 1, HOWTO.size()])
	var entry: Array = HOWTO[page]
	_text(c, font, Vector2(24, 128), str(entry[0]), 40, ORANGE)
	var y := 196.0
	for row in entry[1]:
		var key := str(row[0])
		if key == "":
			_text(c, font, Vector2(24, y), str(row[1]), 28)
		else:
			var chip := Rect2(24, y - 32, 150, 44)
			c.draw_rect(chip, Color(ORANGE, 0.15))
			c.draw_rect(chip, ORANGE, false, 2.0)
			var shown := Controls.hint(key)
			_text(c, font, Vector2(24, y - 1), shown, 24 if shown.length() <= 10 else 18, ORANGE, 150, HORIZONTAL_ALIGNMENT_CENTER)
			_text(c, font, Vector2(196, y), str(row[1]), 27)
		y += 64.0
	# Dots for the pages, filled for this one.
	for i in HOWTO.size():
		var at := Vector2(Dashboard.PX.x * 0.5 + (i - (HOWTO.size() - 1) * 0.5) * 28.0, Dashboard.PX.y - 24)
		c.draw_circle(at, 7.0, ORANGE if i == page else Color(1, 1, 1, 0.2))


static func _draw_money_me(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "MY MONEY", str(data.get("name", "")))
	_text(c, font, Vector2(24, 110), "CASH IN HAND", 20, Dashboard.DIM)
	_text(c, font, Vector2(24, 180), money_text(int(data.get("cash", 0))), 72, Dashboard.GOOD)
	_tile(c, font, Rect2(24, 210, 300, 96), "Earned this week", money_text(int(data.get("earned_week", 0))))
	_tile(c, font, Rect2(24, 318, 300, 96), "Spent this week", money_text(int(data.get("spent_week", 0))))
	_tile(c, font, Rect2(24, 426, 300, 82), "Bikes sold", str(int(data.get("sold", 0))))
	var key := str(data.get("range", MoneyGraph.DEFAULT_RANGE))
	chart(c, font, Rect2(344, 90, 656, 418), data.get("history", []), "Your money, %s" % MoneyGraph.span_text(key), key)
	if data.get("placeholder", false):
		_later(c, font, "Money arrives with selling bikes. These are placeholders.")


static func _draw_garage(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "GARAGE MONEY", "The shed's own account")
	_text(c, font, Vector2(24, 110), "SHED ACCOUNT", 20, Dashboard.DIM)
	var cash := int(data.get("cash", 0))
	_text(c, font, Vector2(24, 180), money_text(cash), 72, Dashboard.GOOD if cash >= 0 else Dashboard.BAD)
	if int(data.get("overdraft", 0)) > 0:
		_text(c, font, Vector2(260, 110), "OVERDRAWN", 20, Dashboard.BAD)
	_tile(c, font, Rect2(24, 210, 230, 96), "Bikes worth", money_text(int(data.get("bike_value", 0))))
	_tile(c, font, Rect2(266, 210, 230, 96), "Parts stock", money_text(int(data.get("stock_value", 0))))
	_tile(c, font, Rect2(24, 318, 230, 96), "In this week", money_text(int(data.get("income_week", 0))))
	_tile(c, font, Rect2(266, 318, 230, 96), "Out this week", money_text(int(data.get("outgoings_week", 0))))
	_tile(c, font, Rect2(24, 426, 230, 82), "Bills a night", money_text(int(data.get("bills_day", 0))))
	_tile(c, font, Rect2(266, 426, 230, 82), "Owed to the bank", money_text(int(data.get("debt", 0)) + int(data.get("overdraft", 0))))
	var key := str(data.get("range", MoneyGraph.DEFAULT_RANGE))
	chart(c, font, Rect2(516, 90, 484, 418), data.get("history", []), "Shed account, %s" % MoneyGraph.span_text(key), key)
	if data.get("placeholder", false):
		_later(c, font, "The shed's account comes with money. These are placeholders.")


static func _draw_afford(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "WHAT YOU CAN AFFORD", "You have " + money_text(int(data.get("cash", 0))))
	_text(c, font, Vector2(24, 108), "WORTH SAVING UP FOR", 20, Dashboard.DIM)
	_text(c, font, Vector2(640, 108), "PRICE", 20, Dashboard.DIM, 180, HORIZONTAL_ALIGNMENT_RIGHT)
	var y := 152.0
	var cash := int(data.get("cash", 0))
	for it in data.get("items", []):
		var price := int(it.get("price", -1))
		c.draw_rect(Rect2(14, y - 30, Dashboard.PX.x - 28, 44), PANEL)
		_text(c, font, Vector2(30, y), str(it["name"]).left(34), 26)
		_text(c, font, Vector2(500, y), str(it.get("what", "")), 20, Dashboard.DIM)
		_text(c, font, Vector2(640, y), money_text(price) if price >= 0 else CURRENCY + " --", 26, Color.WHITE, 180,
			HORIZONTAL_ALIGNMENT_RIGHT)
		var tag := "SOON" if price < 0 else ("YES" if cash >= price else "NOT YET")
		var col := AMBER if price < 0 else (Dashboard.GOOD if cash >= price else Dashboard.BAD)
		var chip := Rect2(860, y - 26, 130, 36)
		c.draw_rect(chip, Color(col, 0.18))
		_text(c, font, Vector2(860, y - 1), tag, 20, col, 130, HORIZONTAL_ALIGNMENT_CENTER)
		y += 52.0
		if y > Dashboard.PX.y - 60:
			break
	if data.get("placeholder", false):
		_later(c, font, "Prices come with money. The list is a placeholder.")


static func _draw_contracts(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "CONTRACTS", "Reputation %d" % int(data.get("reputation", 0)))
	var cols := [["OFFERED", data.get("offered", []), AMBER], ["IN PROGRESS", data.get("active", []), ORANGE],
		["DONE", data.get("done", []), Dashboard.GOOD]]
	for i in cols.size():
		var x := 24.0 + i * 330.0
		var list: Array = cols[i][1]
		c.draw_rect(Rect2(x, 90, 312, 412), PANEL)
		c.draw_rect(Rect2(x, 90, 312, 6), cols[i][2])
		_text(c, font, Vector2(x + 16, 136), str(cols[i][0]), 24, cols[i][2])
		_text(c, font, Vector2(x + 16, 136), str(list.size()), 40, Color.WHITE, 280, HORIZONTAL_ALIGNMENT_RIGHT)
		if list.is_empty():
			_text(c, font, Vector2(x + 16, 200), "None yet", 26, Dashboard.DIM)
		var y := 200.0
		for job in list:
			var line := str(job.get("title", job)) if job is Dictionary else str(job)
			_text(c, font, Vector2(x + 16, y), line.left(22), 22)
			if job is Dictionary and job.has("sub"):
				_text(c, font, Vector2(x + 16, y + 22), str(job["sub"]).left(30), 16,
					Dashboard.BAD if job.get("late", false) else Dashboard.DIM)
			if job is Dictionary and job.has("progress"):
				_bar(c, Rect2(x + 16, y + 30, 280, 8), float(job["progress"]), Dashboard.GOOD)
				y += 12.0
			y += 36.0 if not (job is Dictionary and job.has("sub")) else 60.0
			if y > 480.0:
				break
	if data.get("placeholder", false):
		_later(c, font, "Customers bring jobs to the shed in a later update.")


## The staff board. Down the left, everyone on the payroll: name, role and level, a line on
## what they're doing and how far through. On the right, one of them in the spotlight (each in
## turn, see Staff.tv_data): what they're up to at length, how they are, a project's list with
## how each task stands, and their log of the day, newest first with the times. The news goes
## under the list.
static func _draw_staff(c: Control, font: Font, data: Dictionary) -> void:
	var rows: Array = data.get("rows", [])
	_title(c, font, "STAFF", "%d of %d  ·  wages %s a day" % [rows.size(), int(data.get("max", 6)), money_text(int(data.get("wages", 0)))])
	if rows.is_empty():
		_text(c, font, Vector2(24, 150), "Nobody on the payroll yet.", 30, Dashboard.DIM)
		_text(c, font, Vector2(24, 196), "Hire staff on the Staff tab of the menu ({menu}).", 22, Dashboard.DIM)
		return
	var spot := clampi(int(data.get("spot", 0)), 0, rows.size() - 1)
	var lw := 400.0
	var y := 82.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var sick := bool(r.get("sick", false))
		var rect := Rect2(16, y, lw, 62)
		c.draw_rect(rect, PANEL)
		c.draw_rect(Rect2(16, y, 6, 62), r.get("top", Color.GRAY) if r.get("top") is Color else Color.GRAY)
		if i == spot:
			c.draw_rect(rect, ORANGE, false, 2.0)
		_text(c, font, Vector2(32, y + 22), str(r.get("name", "")).left(18), 19, Dashboard.DIM if sick else Color.WHITE)
		_text(c, font, Vector2(32, y + 22), "%s  Lv %d" % [str(r.get("role", "")), int(r.get("level", 1))], 13, ORANGE, lw - 24, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, font, Vector2(32, y + 42), str(r.get("doing", "")).left(46), 14, Dashboard.BAD if sick else Color(0.85, 0.9, 0.95), lw - 24)
		if r.get("busy", false):
			_bar(c, Rect2(32, y + 50, lw - 32, 6), float(r.get("progress", 0.0)), Dashboard.GOOD)
		y += 66.0
	var news: Array = data.get("news", [])
	var ny := y + 18.0
	for i in range(news.size() - 1, -1, -1):
		if ny > Dashboard.PX.y - 10:
			break
		c.draw_multiline_string(font, Vector2(16, ny), str(news[i]), HORIZONTAL_ALIGNMENT_LEFT, lw, 13, 2, Dashboard.DIM)
		ny += 18.0 * mini(2, ceili(font.get_string_size(str(news[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / lw)) + 4.0
	_draw_staff_spot(c, font, rows[spot], spot, rows.size())


## The Staff channel's spotlight on one worker (see _draw_staff).
static func _draw_staff_spot(c: Control, font: Font, r: Dictionary, at: int, of: int) -> void:
	var x := 432.0
	var w := Dashboard.PX.x - x - 16.0
	var sick := bool(r.get("sick", false))
	c.draw_rect(Rect2(x, 82, w, Dashboard.PX.y - 98), PANEL)
	c.draw_rect(Rect2(x, 82, w, 6), r.get("top", Color.GRAY) if r.get("top") is Color else Color.GRAY)
	_text(c, font, Vector2(x + 16, 120), str(r.get("name", "")), 28, Color.WHITE, w - 120)
	_text(c, font, Vector2(x + 16, 120), "%d / %d" % [at + 1, of], 16, Dashboard.DIM, w - 32, HORIZONTAL_ALIGNMENT_RIGHT)
	var mood := "off sick" if sick else str(r.get("mood_word", ""))
	_text(c, font, Vector2(x + 16, 146), "%s, level %d  ·  %s  ·  %s a day" % [str(r.get("role", "")), int(r.get("level", 1)), mood,
		money_text(int(r.get("wage", 0)))], 16, ORANGE, w - 32)
	_bar(c, Rect2(x + 16, 156, 160, 6), float(r.get("level_frac", 0.0)), AMBER)
	var mc := Dashboard.BAD if sick or float(r.get("mood", 0.7)) < 0.4 else (Dashboard.GOOD if float(r.get("mood", 0.7)) >= 0.8 else Dashboard.DIM)
	_bar(c, Rect2(x + 192, 156, 160, 6), float(r.get("mood", 0.7)), mc)
	_text(c, font, Vector2(x + 16, 190), "NOW", 14, ORANGE)
	var act := Controls.hint(str(r.get("activity", "")))
	c.draw_multiline_string(font, Vector2(x + 16, 212), act, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 17, 4, Dashboard.BAD if sick else Color.WHITE)
	var y := 212.0 + 20.0 * mini(4, ceili(font.get_string_size(act, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x / (w - 32)))
	if r.get("busy", false):
		_bar(c, Rect2(x + 16, y - 6, w - 32, 6), float(r.get("progress", 0.0)), Dashboard.GOOD)
		y += 14.0
	# A project's list: the one they're on and a few either side.
	var list: Array = r.get("list", [])
	if not list.is_empty():
		_text(c, font, Vector2(x + 16, y + 10), "THE LIST", 14, ORANGE)
		y += 30.0
		var ti := int(r.get("ti", 0))
		var first := clampi(ti - 1, 0, maxi(0, list.size() - 4))
		for i in range(first, mini(list.size(), first + 4)):
			var t: Dictionary = list[i]
			var st := str(t.get("state", "todo"))
			var mark := "•"
			match st:
				"done":
					mark = "✓"
				"skipped":
					mark = "–"
			if i == ti and st in ["todo", "doing"]:
				mark = "▶"
			var col := Dashboard.GOOD if st == "done" else (Dashboard.DIM if st == "skipped" else Color.WHITE)
			var line := str(t.get("text", ""))
			if st == "skipped" and str(t.get("note", "")) != "":
				line += ": " + str(t["note"])
			_text(c, font, Vector2(x + 16, y), mark, 15, col)
			_text(c, font, Vector2(x + 36, y), line, 15, col, w - 52)
			y += 20.0
		if list.size() > first + 4:
			_text(c, font, Vector2(x + 36, y), "and %d more" % (list.size() - first - 4), 13, Dashboard.DIM)
			y += 18.0
	# The log, newest first, as far as there's room.
	_text(c, font, Vector2(x + 16, y + 12), "TODAY", 14, ORANGE)
	y += 34.0
	var log: Array = r.get("log", [])
	if log.is_empty():
		_text(c, font, Vector2(x + 16, y), "Nothing yet.", 15, Dashboard.DIM)
	for i in log.size():
		if y > Dashboard.PX.y - 24:
			break
		var l: Dictionary = log[i]
		var fade := 1.0 - 0.07 * i
		_text(c, font, Vector2(x + 16, y), str(l.get("at", "")), 14, Color(Dashboard.DIM, Dashboard.DIM.a * fade))
		_text(c, font, Vector2(x + 76, y), str(l.get("text", "")), 15, Color(0.9, 0.95, 1.0, fade), w - 92)
		y += 20.0
