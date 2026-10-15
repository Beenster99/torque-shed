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
const CHANNELS: Array[String] = ["live", "crew", "xp", "howto", "money_me", "money_garage", "afford", "contracts"]
const NAMES := {"bay": "Bay", "live": "Live riding", "crew": "Crew board", "xp": "XP goals", "howto": "How to play",
	"money_me": "My money", "money_garage": "Garage money", "afford": "What you can afford", "contracts": "Contracts"}
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
		["WASD", "walk  ·  mouse: look  ·  Shift: run  ·  C: crouch"],
		["1-8", "pick a tool (or Q / E, the mouse wheel, LB / RB)"],
		["L mouse", "hold to work (RT or A on a pad)"],
		["F", "use, ride, unpack, pick up kit (Y on a pad)"],
		["G", "ping what you're looking at for the crew"],
		["R", "next TV channel when you look at a screen (X)"],
	]],
	["Restoring a bike", [
		["Wrench", "unbolt the part, then take it off with your hands"],
		["Brush", "scrub off dirt, or leave it in the parts washer"],
		["Grinder", "rust and wear, on a repair machine"],
		["Spray", "paint: the can anywhere, the gun in the booth"],
		["Fit", "hold the part, look at the bike, then bolt it up"],
	]],
	["Riding", [
		["I", "engine on or off  ·  W: throttle  ·  S: front brake"],
		["Space", "rear brake  ·  A / D: lean  ·  E / Q: gears"],
		["Shift", "weight back for a wheelie  ·  Ctrl: forward"],
		["R", "reset after a crash  ·  C: camera"],
		["F", "get off when you've stopped"],
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
			ready.append("%s  ·  bay %d" % [Shed.bikes[id]["name"], int(Shed.bikes[id]["bay"]) + 1])
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
	var history := [cash, cash, cash, cash, cash, cash, cash]
	var sold := 0
	if prog and peer == Shed.me() and prog.has_method("cash_flow"):
		flow = prog.cash_flow(7)
		history = prog.cash_history()
		sold = int(prog.profile.get("stats", {}).get("sell_bike", 0))
	return {"name": str(Shed.crew.get(peer, {}).get("name", "You")), "cash": cash,
		"earned_week": int(flow["earned"]), "spent_week": int(flow["spent"]), "sold": sold, "history": history}


## The business's account (Shed.garage_money), what its bikes and loose parts would fetch, the
## last seven days' money in and out (from its ledger) and its balance day by day.
static func garage_data() -> Dictionary:
	var worth := Money.shed_worth()
	var flow := Money.flow(Shed.bank, 7)
	return {"cash": Shed.garage_money, "bike_value": int(worth["bikes"]), "stock_value": int(worth["stock"]),
		"income_week": int(flow["in"]), "outgoings_week": int(flow["out"]), "bikes": Shed.bikes.size(),
		"history": Money.history7(Shed.bank.get("history", []), Shed.garage_money), "debt": Money.debt(Shed.bank)}


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

static func _text(c: Control, font: Font, pos: Vector2, text: String, size: int, color := Color.WHITE, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	c.draw_string(font, pos, text, align, width, size, color)


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
	c.draw_rect(rect, PANEL)
	_text(c, font, rect.position + Vector2(16, 28), label, 20, Dashboard.DIM)
	var plot := Rect2(rect.position + Vector2(60, 44), rect.size - Vector2(80, 80))
	var top := 1.0
	for v in values:
		top = maxf(top, absf(float(v)))
	for i in 3:
		var y := plot.position.y + plot.size.y * i / 2.0
		c.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08), 1.0)
	c.draw_line(Vector2(plot.position.x, plot.end.y), plot.end, Color(1, 1, 1, 0.3), 2.0)
	var pts := PackedVector2Array()
	for i in values.size():
		var x := plot.position.x + plot.size.x * i / maxf(1.0, values.size() - 1.0)
		pts.append(Vector2(x, plot.end.y - plot.size.y * clampf(float(values[i]) / top, 0.0, 1.0)))
		_text(c, font, Vector2(x - 30, plot.end.y + 26), "today" if i == values.size() - 1 else "-%dd" % (values.size() - 1 - i),
			15, Dashboard.DIM, 60, HORIZONTAL_ALIGNMENT_CENTER)
	if pts.size() > 1:
		c.draw_polyline(pts, ORANGE, 4.0, true)
	for p in pts:
		c.draw_circle(p, 5.0, ORANGE)
	if values.all(func(v): return float(v) == 0.0):
		_text(c, font, plot.position + Vector2(0, plot.size.y * 0.5), "Nothing in or out yet", 22, Dashboard.DIM, plot.size.x,
			HORIZONTAL_ALIGNMENT_CENTER)


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
		_:
			_title(c, font, "NO SIGNAL")


static func _draw_nobody(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "LIVE RIDING")
	c.draw_circle(Vector2(1000 - 120, 35), 9.0, Color(0.6, 0.05, 0.05))
	_text(c, font, Vector2(1000 - 100, 44), "OFF AIR", 22, HEADER_INK)
	_text(c, font, Vector2(24, 150), "Nobody's out riding", 52)
	_text(c, font, Vector2(24, 200), "Get on a finished bike (F) and you're live on every TV tuned here.", 22, Dashboard.DIM)
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
			_text(c, font, Vector2(24, y - 1), key, 24, ORANGE, 150, HORIZONTAL_ALIGNMENT_CENTER)
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
	_chart(c, font, Rect2(344, 90, 656, 418), data.get("history", []), "Your money over the last week")
	if data.get("placeholder", false):
		_later(c, font, "Money arrives with selling bikes. These are placeholders.")


static func _draw_garage(c: Control, font: Font, data: Dictionary) -> void:
	_title(c, font, "GARAGE MONEY", "The shed's own account")
	_text(c, font, Vector2(24, 110), "SHED ACCOUNT", 20, Dashboard.DIM)
	_text(c, font, Vector2(24, 180), money_text(int(data.get("cash", 0))), 72, Dashboard.GOOD)
	_tile(c, font, Rect2(24, 210, 230, 96), "Bikes worth", money_text(int(data.get("bike_value", 0))))
	_tile(c, font, Rect2(266, 210, 230, 96), "Parts stock", money_text(int(data.get("stock_value", 0))))
	_tile(c, font, Rect2(24, 318, 230, 96), "In this week", money_text(int(data.get("income_week", 0))))
	_tile(c, font, Rect2(266, 318, 230, 96), "Out this week", money_text(int(data.get("outgoings_week", 0))))
	_tile(c, font, Rect2(24, 426, 230, 82), "Bikes in the shed", str(int(data.get("bikes", 0))))
	_tile(c, font, Rect2(266, 426, 230, 82), "Owed to the bank", money_text(int(data.get("debt", 0))))
	_chart(c, font, Rect2(516, 90, 484, 418), data.get("history", []), "Shed account, last week")
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
