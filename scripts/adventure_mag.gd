class_name AdventureMag
extends Control
## Adventure Rider, the magazine on the workbench (Simon: "Players can read about the adventures
## in a magazine on the workbench"): anyone can pick it up ({interact} on it, or the Esc menu's
## Adventure ride button) and read it, a page per adventure: its title, theme, the distance and
## about how long it takes, the surfaces and stops on the way (from planning the route itself,
## on a worker thread), the kit to take, the destination and a picture of it. The host picks a
## length (short, ride, epic, or any km) and starts it for the whole crew from its page.
##
## The adventures come in issues, and later issues come out as the host levels up (ISSUES:
## level). Each article is a fixed seed, so a ride read about is the same road every time; a
## theme the game doesn't have yet (AdventureState.THEMES) is ridden on varied roads, to the
## same destination.

signal closed

## Every issue: its number, name, the host's level it's out at, and its adventures: id, title,
## theme, len (a key of AdventureDest.LENGTHS), seed, dest (a key of AdventureDest.DESTS), blurb.
const ISSUES := [
	{"n": 1, "name": "Spring issue", "level": 1, "articles": [
		{"id": "red_rock", "title": "The Red Rock Run", "theme": "desert", "len": "short", "seed": 4101, "dest": "canyon",
			"blurb": "Long straight roads across the desert, sand blowing over the tarmac, and at the end of it a canyon that glows red as the sun goes down. Pack water."},
		{"id": "dales_rally", "title": "Dales Rally Weekender", "theme": "hills", "len": "short", "seed": 4102, "dest": "dales_rally",
			"blurb": "Narrow lanes between stone walls, sheep in the road and a pub in every village, all the way to the Dales' own bike rally."},
		{"id": "lighthouse_loop", "title": "The Lighthouse Loop", "theme": "coastal", "len": "ride", "seed": 4103, "dest": "lighthouse",
			"blurb": "Cliff roads along the sea, beaches and fishing villages, to the lighthouse at the very end of the land. Time it to arrive at dusk."},
	]},
	{"n": 2, "name": "Summer issue", "level": 3, "articles": [
		{"id": "glacier_express", "title": "Glacier Express", "theme": "alpine", "len": "ride", "seed": 4201, "dest": "glacier",
			"blurb": "Hairpins up through the pines, snow by the road near the top, and hot chocolate looking out over the glacier."},
		{"id": "hollow_farm", "title": "Scramble at Hollow Farm", "theme": "hills", "len": "ride", "seed": 4202, "dest": "farm_track",
			"blurb": "Back lanes and farm tracks out to a scramble track in a farmer's field. Bring knobblies and your best jumping trousers."},
		{"id": "grand_tour", "title": "The Grand Tour, lite", "theme": "varied", "len": "short", "seed": 4203, "dest": "big_rally",
			"blurb": "A bit of everything: tarmac, gravel, the odd patch of sand and snow, and the biggest rally of the summer at the end."},
	]},
	{"n": 3, "name": "Autumn issue", "level": 6, "articles": [
		{"id": "dune_days", "title": "Dune Track Days", "theme": "desert", "len": "ride", "seed": 4301, "dest": "dune_track",
			"blurb": "Out past the last fuel station into the dunes, where somebody has built a dirt track with a proper jump."},
		{"id": "pass_race", "title": "Race Weekend on the Pass", "theme": "alpine", "len": "ride", "seed": 4302, "dest": "pass_race",
			"blurb": "Up and over the high pass to race day at the top: the grandstand, the paddock, and the bikes flat out."},
		{"id": "seafront", "title": "The Seafront Bike Meet", "theme": "coastal", "len": "short", "seed": 4303, "dest": "sea_meet",
			"blurb": "Along the coast road to the seafront meet: a field of bikes by the sea, stalls, a stage and chips."},
	]},
	{"n": 4, "name": "Winter issue", "level": 10, "articles": [
		{"id": "coast_canyon", "title": "Coast to Canyon", "theme": "desert", "len": "epic", "seed": 4401, "dest": "canyon",
			"blurb": "The big one: two days from the green lanes to the red rock, with a night under the stars on the way. Fill every tank you've got."},
		{"id": "road_race", "title": "Road Race Sunday", "theme": "varied", "len": "ride", "seed": 4402, "dest": "road_race",
			"blurb": "Every kind of road there is, to watch a road race from the grandstand."},
	]},
	{"n": 5, "name": "Collector's issue", "level": 15, "articles": [
		{"id": "over_the_top", "title": "Over the Top", "theme": "alpine", "len": "epic", "seed": 4501, "dest": "glacier",
			"blurb": "Three passes, two days and a night in a mountain inn, to the glacier at the top of the world. Tyres for snow, and a warm jacket."},
		{"id": "atlantic_edge", "title": "The Atlantic Edge", "theme": "coastal", "len": "epic", "seed": 4502, "dest": "lighthouse",
			"blurb": "The whole coast in one go: every cliff, every cove, a night by the sea, and the lighthouse at the end."},
		{"id": "valley_park", "title": "The Long Way to the Moto Park", "theme": "varied", "len": "epic", "seed": 4503, "dest": "moto_park",
			"blurb": "The longest way round to a dirt track with a jump. Bring a spare chain."},
	]},
]

## The kit each theme wants (Simon's list: tank bag, extra tank, boxes, tyres, tool box, screen, sat nav).
const KIT := {
	"desert": ["Sand or all-terrain tyres", "The extra petrol tank: the pumps are a long way apart", "A tank bag with water and snacks",
		"Tool box with the tyre fix kit"],
	"alpine": ["Tyres for snow and the wet", "A taller screen for the cold up top", "Tool box: tyre fix kit, fluids and a spare chain",
		"Sat nav for the passes"],
	"coastal": ["Road tyres (the odd gravel track to the coves)", "Top box for the beach stops", "A taller screen for the sea wind",
		"Tank bag"],
	"hills": ["Dual-sport tyres for the farm tracks", "Tool box: tyre fix kit and a spare chain", "Tank bag", "Sat nav: the lanes all look the same"],
	"varied": ["All-terrain tyres", "Tool box: tyre fix kit, fluids and a spare chain", "Tank bag or a top box", "Sat nav"],
}
const THEME_NAMES := {"desert": "Desert", "alpine": "Alpine", "coastal": "Coastal", "hills": "Hills", "varied": "Varied"}
const PAPER := Color(0.95, 0.93, 0.88)
const INK := Color(0.12, 0.11, 0.1)
const RED := Color(0.75, 0.12, 0.08)

## The page open (an index into pages()).
var page := 0
## The length picked for each article: "short", "ride", "epic" or "free", and the free km.
var picks := {}
var free_km := {}
var _title: Label
var _kicker: Label
var _blurb: Label
var _what: Label
var _pic: TextureRect
var _facts: Label
var _kit: Label
var _len_box: HBoxContainer
var _len_buttons := {}
var _km: SpinBox
var _start: Button
var _start_note: Label
var _page_l: Label
var _prev: Button
var _next: Button
var _sig := ""

## Route facts, worked out on worker threads: "seed|km|theme" -> facts, and the tasks running.
static var _facts_cache := {}
static var _tasks := {}
static var _results := _Results.new()


class _Results extends RefCounted:
	var mutex := Mutex.new()
	var done := {}


func _ready() -> void:
	name = "AdventureMag"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var paper := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(4)
	style.set_content_margin_all(26)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	paper.add_theme_stylebox_override("panel", style)
	paper.custom_minimum_size = Vector2(1080, 640)
	center.add_child(paper)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	paper.add_child(col)
	# The masthead.
	var mast := HBoxContainer.new()
	col.add_child(mast)
	var name_l := _l("ADVENTURE RIDER", 30, RED)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mast.add_child(name_l)
	_page_l = _l("", 15, INK.lightened(0.35))
	_page_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mast.add_child(_page_l)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 28)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spread)
	# Left page: the picture, the title and the story.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	spread.add_child(left)
	_pic = TextureRect.new()
	_pic.custom_minimum_size = Vector2(504, 300)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	left.add_child(_pic)
	_kicker = _l("", 14, RED)
	left.add_child(_kicker)
	_title = _l("", 30, INK)
	left.add_child(_title)
	_blurb = _l("", 16, INK)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_blurb)
	_what = _l("", 15, INK.lightened(0.2))
	_what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_what)
	# Right page: the facts, the kit, the length and the start.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	spread.add_child(right)
	right.add_child(_l("THE ROUTE", 14, RED))
	_facts = _l("", 15, INK)
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_facts)
	right.add_child(_l("TAKE WITH YOU", 14, RED))
	_kit = _l("", 15, INK)
	_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_kit)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(grow)
	right.add_child(_l("HOW FAR", 14, RED))
	_len_box = HBoxContainer.new()
	_len_box.add_theme_constant_override("separation", 6)
	right.add_child(_len_box)
	for id in AdventureDest.LENGTH_ORDER + ["free"]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = "Free km" if id == "free" else "%s %d km" % [str(AdventureDest.LENGTHS[id]["name"]), int(AdventureDest.LENGTHS[id]["km"])]
		b.pressed.connect(_pick_length.bind(id))
		_len_box.add_child(b)
		_len_buttons[id] = b
	_km = SpinBox.new()
	_km.min_value = Adventure.MIN_KM
	_km.max_value = Adventure.MAX_KM
	_km.step = 5.0
	_km.suffix = "km"
	_km.value_changed.connect(func(v):
		var a := article()
		if not a.is_empty():
			free_km[a["id"]] = v
			refresh())
	_len_box.add_child(_km)
	_start = Button.new()
	_start.text = "Start this adventure for everyone"
	_start.pressed.connect(start)
	right.add_child(_start)
	_start_note = _l("", 14, INK.lightened(0.3))
	_start_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_start_note)
	# Turning the pages.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	col.add_child(nav)
	_prev = Button.new()
	_prev.text = "< Previous page"
	_prev.pressed.connect(func(): turn(-1))
	nav.add_child(_prev)
	_next = Button.new()
	_next.text = "Next page >"
	_next.pressed.connect(func(): turn(1))
	nav.add_child(_next)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(gap)
	# Tucked in the back: the Adventure Diaries of the rides this machine has been on (DiaryBook).
	var diaries := Button.new()
	diaries.text = "Adventure diaries"
	diaries.pressed.connect(func():
		if AdventureTrip.current:
			AdventureTrip.current.open_diary())
	nav.add_child(diaries)
	var close := Button.new()
	Controls.bind_text(close, "Put it down ({menu})")
	close.pressed.connect(func(): closed.emit())
	nav.add_child(close)


static func _l(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event is InputEventKey and event.pressed and not event.echo and not _km.get_line_edit().has_focus():
		if (event as InputEventKey).keycode in [KEY_RIGHT, KEY_D]:
			turn(1)
			get_viewport().set_input_as_handled()
		elif (event as InputEventKey).keycode in [KEY_LEFT, KEY_A]:
			turn(-1)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	poll()
	# Brought up to date when the facts come in, or the host or their level changes.
	var a := article()
	var sig := "%d|%s|%s|%d|%s" % [page, str(_facts_cache.has(_facts_key(a, km_of(a)))) if not a.is_empty() else "",
		str(Shed.is_authority()), level_now(), str(Adventure.active())]
	if sig != _sig:
		refresh()


# ---------------------------------------------------------------------------- the issues

## The host's level, which brings out new issues (in solo, yours).
static func level_now() -> int:
	if Shed.is_authority():
		return Progress.level()
	return int(Progress.summary(1).get("level", 1))


## Every article, in order: each with its issue's n, name and level added.
static func all_articles() -> Array:
	var out := []
	for issue in ISSUES:
		for a in issue["articles"]:
			var e: Dictionary = a.duplicate()
			e["issue"] = int(issue["n"])
			e["issue_name"] = str(issue["name"])
			e["level"] = int(issue["level"])
			out.append(e)
	return out


static func find(id: String) -> Dictionary:
	for a in all_articles():
		if str(a["id"]) == id:
			return a
	return {}


## Whether article `a` is out at `level`.
static func unlocked(a: Dictionary, level: int) -> bool:
	return level >= int(a.get("level", 1))


## The pages to read: every article that's out, then one about the issues still to come.
func pages() -> Array:
	var lv := level_now()
	var out := all_articles().filter(func(a): return unlocked(a, lv))
	var next := next_issue(lv)
	if not next.is_empty():
		out.append({"id": "", "coming": next})
	return out


## The next issue still to come out at `level` ({} when they're all out).
static func next_issue(level: int) -> Dictionary:
	for issue in ISSUES:
		if level < int(issue["level"]):
			return issue
	return {}


## The article on the page open ({} on the "coming soon" page).
func article() -> Dictionary:
	var list := pages()
	page = clampi(page, 0, list.size() - 1)
	var a: Dictionary = list[page]
	return a if str(a.get("id", "")) != "" else {}


## The km article `a` is picked to be ridden at.
func km_of(a: Dictionary) -> float:
	if a.is_empty():
		return Adventure.DEFAULT_KM
	var id := str(picks.get(a["id"], a["len"]))
	if id == "free":
		return float(free_km.get(a["id"], AdventureDest.LENGTHS[a["len"]]["km"]))
	return float(AdventureDest.LENGTHS[id]["km"])


## The theme the road is built as: the article's, or varied when the game doesn't have it yet.
static func road_theme(theme: String) -> String:
	return theme if Adventure.THEMES.has(theme) else "varied"


# ---------------------------------------------------------------------------- opening and turning

func open(at := "") -> void:
	visible = true
	if at != "":
		for i in pages().size():
			if str(pages()[i].get("id", "")) == at:
				page = i
	refresh()


func turn(d: int) -> void:
	page = clampi(page + d, 0, pages().size() - 1)
	refresh()


func _pick_length(id: String) -> void:
	var a := article()
	if a.is_empty():
		return
	picks[a["id"]] = id
	if id == "free" and not free_km.has(a["id"]):
		free_km[a["id"]] = AdventureDest.LENGTHS[a["len"]]["km"]
	refresh()


## Picks the length for the article open ("short", "ride", "epic", or a number of km).
func pick(what) -> void:
	if what is String:
		_pick_length(what)
	else:
		var a := article()
		if not a.is_empty():
			picks[a["id"]] = "free"
			free_km[a["id"]] = clampf(float(what), Adventure.MIN_KM, Adventure.MAX_KM)
			refresh()


## Host: starts the adventure on the page open, at the length picked, for the whole crew.
func start() -> void:
	var a := article()
	if a.is_empty():
		return
	var why := start_reason()
	if why != "":
		Shed.feedback.emit(why, false)
		return
	start_article(a, km_of(a))
	closed.emit()


## Why the host can't start the one open ("" if they can).
func start_reason() -> String:
	if not Shed.is_authority():
		return "The host starts adventures: tell them which page."
	if Adventure.active():
		return "There's an adventure on already."
	return ""


## Starts article `a` at `km` for the crew (the host).
static func start_article(a: Dictionary, km: float) -> void:
	Shed.request({"a": "adventure_start", "seed": int(a["seed"]), "km": km, "theme": road_theme(str(a["theme"])),
		"dest": str(a["dest"]), "title": str(a["title"]), "mag": str(a["id"])})


# ---------------------------------------------------------------------------- the page

func refresh() -> void:
	var list := pages()
	var a := article()
	var lv := level_now()
	_sig = "%d|%s|%s|%d|%s" % [page, str(_facts_cache.has(_facts_key(a, km_of(a)))) if not a.is_empty() else "",
		str(Shed.is_authority()), lv, str(Adventure.active())]
	_prev.disabled = page <= 0
	_next.disabled = page >= list.size() - 1
	if a.is_empty():
		var issue: Dictionary = list[page].get("coming", {})
		_page_l.text = "Page %d of %d" % [page + 1, list.size()]
		_kicker.text = "NEXT ISSUE"
		_title.text = "Issue %d, the %s: coming soon" % [int(issue.get("n", 0)), str(issue.get("name", "")).to_lower()]
		_blurb.text = "Out when the host reaches level %d (now level %d). Its adventures: %s." % [int(issue.get("level", 1)), lv,
			", ".join((issue.get("articles", []) as Array).map(func(x): return str(x["title"])))]
		_what.text = ""
		_pic.texture = null
		_facts.text = "Earn XP in the shed and on the road to level up. Every adventure you finish is worth plenty."
		_kit.text = ""
		_len_box.visible = false
		_start.visible = false
		_start_note.text = ""
		return
	var dest := str(a["dest"])
	var km := km_of(a)
	_page_l.text = "Issue %d, %s  ·  page %d of %d" % [int(a["issue"]), str(a["issue_name"]).to_lower(), page + 1, list.size()]
	_kicker.text = "%s ADVENTURE  ·  %s" % [str(THEME_NAMES.get(a["theme"], "Varied")).to_upper(), AdventureDest.name_of(dest).to_upper()]
	_title.text = str(a["title"])
	_blurb.text = str(a["blurb"])
	_what.text = "At the end: %s." % str(AdventureDest.of(dest).get("what", ""))
	if road_theme(str(a["theme"])) != str(a["theme"]):
		_what.text += "\n(For now the road there is a varied one.)"
	_pic.texture = AdventureDest.picture(dest)
	_facts.text = facts_text(a, km)
	var kit: Array = (KIT.get(a["theme"], KIT["varied"]) as Array).duplicate()
	if AdventureDest.overnight(km):
		kit.append("Side boxes or a top box for a night away (an inn or a campsite on the way)")
	_kit.text = "\n".join(kit.map(func(x): return "•  " + str(x)))
	_len_box.visible = true
	var picked := str(picks.get(a["id"], a["len"]))
	for id in _len_buttons:
		(_len_buttons[id] as Button).set_pressed_no_signal(id == picked)
		(_len_buttons[id] as Button).disabled = not Shed.is_authority()
	_km.visible = picked == "free"
	_km.set_value_no_signal(km)
	_km.editable = Shed.is_authority()
	_start.visible = true
	var why := start_reason()
	_start.disabled = why != ""
	_start_note.text = why if why != "" else "Everyone in the shed comes along, each on the bike they're on or by."


## The route's lines: distance and time, surfaces and stops (once the plan's been worked out).
func facts_text(a: Dictionary, km: float) -> String:
	var lines := ["%d km, %s of riding%s" % [roundi(km), AdventureDest.time_text(km), ", with a night's stop" if AdventureDest.overnight(km) else ""]]
	var f := facts(int(a["seed"]), km, road_theme(str(a["theme"])), str(a["dest"]))
	if f.is_empty():
		lines.append("Working out the surfaces and stops...")
		return "\n".join(lines)
	var surf: Dictionary = f["surfaces"]
	var parts := []
	for id in AdventureSurface.IDS:
		if float(surf.get(id, 0.0)) >= 0.01:
			parts.append("%s %d%%" % [str(AdventureSurface.NAMES[id]).to_lower(), roundi(float(surf[id]) * 100.0)])
	lines.append("Surfaces: %s" % ", ".join(parts))
	lines.append("Stops: %d fuel stations, %d cafes and villages, %d lay-bys and viewpoints%s" % [int(f["fuel"]), int(f["food"]),
		int(f["rest"]), ", %d inns and campsites" % int(f["sleep"]) if int(f["sleep"]) > 0 else ""])
	if int(f["forks"]) > 0:
		lines.append("%d forks where the crew picks the way" % int(f["forks"]))
	return "\n".join(lines)


# ---------------------------------------------------------------------------- the route's facts

static func _facts_key(a: Dictionary, km: float) -> String:
	if a.is_empty():
		return ""
	return "%d|%d|%s|%s" % [int(a["seed"]), roundi(km), road_theme(str(a["theme"])), str(a["dest"])]


## The surfaces (share of the main road each) and stops on a route: {surfaces, fuel, food,
## rest, sleep, forks}, or {} while it's being worked out (on a worker thread, started here).
static func facts(seed: int, km: float, theme: String, dest: String) -> Dictionary:
	var key := "%d|%d|%s|%s" % [seed, roundi(km), theme, dest]
	if _facts_cache.has(key):
		return _facts_cache[key]
	poll()
	if _facts_cache.has(key):
		return _facts_cache[key]
	if not _tasks.has(key):
		var box := _results
		_tasks[key] = WorkerThreadPool.add_task(func():
			var out := route_facts(seed, km, theme, dest)
			box.mutex.lock()
			box.done[key] = out
			box.mutex.unlock())
	return {}


## Collects the facts the worker threads have finished.
static func poll() -> void:
	for key in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
			_results.mutex.lock()
			if _results.done.has(key):
				_facts_cache[key] = _results.done[key]
				_results.done.erase(key)
			_results.mutex.unlock()


## Waits for every route still being worked out (before the game closes).
static func wait_all() -> void:
	for key in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()   # (a task waited for is gone: asking after it again is an error)
	_results.mutex.lock()
	for key in _results.done:
		_facts_cache[key] = _results.done[key]
	_results.done.clear()
	_results.mutex.unlock()


## Plans the route and counts what's on it (any thread).
static func route_facts(seed: int, km: float, theme: String, dest: String) -> Dictionary:
	var r := AdventureRoute.new()
	r.plan(seed, km, theme, [AdventureDest.site(dest, km)])
	var surf := {}
	var n := 0
	for c in r.chunk_surface.size():
		if float(c) * AdventureRoute.CHUNK_LEN > r.length:
			break
		surf[r.chunk_surface[c]] = int(surf.get(r.chunk_surface[c], 0)) + 1
		n += 1
	for id in surf:
		surf[id] = float(surf[id]) / maxf(1.0, float(n))
	var count := func(kinds: Array) -> int:
		return r.sites.filter(func(st): return kinds.has(str(st["kind"]))).size()
	return {"surfaces": surf, "fuel": count.call(["fuel"]), "food": count.call(["cafe", "village"]),
		"rest": count.call(["layby", "rest_area", "viewpoint"]), "sleep": count.call(["inn", "campsite"]), "forks": r.forks.size()}


# ---------------------------------------------------------------------------- on the workbench

## The magazine lying on the back end of the shed's workbench: {interact} on it to read it.
class Prop extends Node3D:
	func _ready() -> void:
		name = "AdventureMagazine"
		var x := Workshop.CENTER.x - Workshop.HALF.x + 0.76
		var z := Workshop.spot_transform("bench_0").origin.z - 0.47
		position = Vector3(x, 0.952, z)
		rotation.y = PI * 0.5 + 0.12
		var cover := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.21, 0.28)
		cover.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = AdventureDest.picture("canyon")
		m.uv1_scale = Vector3(0.75, 1.0, 1.0)
		m.uv1_offset = Vector3(0.12, 0.0, 0.0)
		m.roughness = 0.4
		cover.material_override = m
		cover.rotation.x = -PI * 0.5
		cover.position.y = 0.006
		add_child(cover)
		var pages := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.208, 0.006, 0.278)
		pages.mesh = b
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.92, 0.9, 0.85)
		pages.material_override = pm
		pages.position.y = 0.003
		add_child(pages)
		var mast := Label3D.new()
		mast.text = "ADVENTURE\nRIDER"
		mast.font_size = 40
		mast.pixel_size = 0.0011
		mast.outline_size = 6
		mast.outline_modulate = Color(0, 0, 0, 0.6)
		mast.modulate = Color(1.0, 0.85, 0.3)
		mast.rotation.x = -PI * 0.5
		mast.position = Vector3(0, 0.0075, -0.09)
		add_child(mast)
		var body := StaticBody3D.new()
		body.collision_layer = Workshop.INTERACT_LAYER
		body.collision_mask = 0
		body.set_meta("use_node", self)
		body.set_meta("use", {"what": "magazine"})
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.24, 0.05, 0.31)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.02
		body.add_child(cs)
		add_child(body)

	func use_text(_t: Dictionary) -> String:
		return "Adventure Rider magazine\n{interact}: read about the adventures (the host starts one for everyone)"

	func use(_t: Dictionary) -> void:
		if AdventureTrip.current:
			AdventureTrip.current.open_magazine()
