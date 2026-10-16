extends Node
## The player's character: XP, levels, tool upgrades and the skills tree.
##
## XP is one pool. Every job in the shed and every trick on the bike earns some (see XP); the
## host works out how much with award() and hands it to the player who did it, so in co-op
## everyone earns their own. Levels follow a rising curve (xp_for_level). Each level from 2
## gives one tool point (a stage on a hand tool: faster, wider, better looking) and one skill
## point (a rank in the skills tree, see SKILLS).
##
## Playing solo or hosting, the character belongs to the save game (see SaveGame and
## use_profile): each save holds its own, written with the shed. Joining someone else's shed,
## the character comes from user://profile.json on the player's own machine, keyed by player
## name, so it goes with them between co-op sessions. Clients
## report their summary (level, XP, tool stages, skills, goals) to the host, which passes
## everyone's on to everyone, so the host can apply skills that work host-side and TVs can show
## the crew's levels.
##
## award(peer, action, mult, detail): `detail` names what the work was done on ("item:12",
## "bike:3" or any short text). Doing the same job to the same thing again soon earns less and
## less, and one-off rewards ("once" in XP) are only paid once per bike or part.

signal xp_gained(amount: int, label: String)
## This player's own cash went up (amount > 0) or down: for the pound popups.
signal cash_changed(amount: int, label: String)
signal leveled_up(level: int)
## Anything about the character changed: XP, upgrades, skills, or another player's summary.
signal changed

const VERSION := 1
const PATH := "user://profile.json"
const MAX_LEVEL := 50
## The most cash a player can hold.
const MAX_MONEY := 100000000
## A player's own money log kept in the profile, for the My money page: [{day, amt, why}].
const CASH_LOG_SIZE := 60
## How long a repeat of the same job on the same thing keeps counting against it, seconds.
const REPEAT_WINDOW := 120.0
## Jobs with nothing named to them are only cut back after this many in a minute.
const FREE_REPEATS := 6
const NEAR_TEAMMATE := 6.0     # metres: Foreman counts a teammate this close
const MENTOR_REACH := 10.0     # metres: Mentor shares with crew this close

## Every way to earn XP. xp: base amount (award's `mult` scales it). label: the popup's name.
## group: jobs that undo each other share a repeat count (bolting and unbolting the same bolt).
## once: "bike" or "item" pays only once for each (detail "bike:<id>" / "item:<id>").
## tag: which skill boosts it (salvage, builder, air, speed).
const XP := {
	# Moving things about and the spanner: low.
	"carry": {"xp": 1, "label": "Moving parts", "group": "carry"},
	"unbox": {"xp": 1, "label": "Unpacking"},
	"unbolt": {"xp": 2, "label": "Unbolting", "group": "wrench"},
	"bolt": {"xp": 2, "label": "Bolting up", "group": "wrench"},
	"remove": {"xp": 2, "label": "Taking parts off", "group": "fit"},
	"fit": {"xp": 3, "label": "Fitting parts", "group": "fit"},
	"chain_tension": {"xp": 4, "label": "Chain tension"},
	"tune": {"xp": 2, "label": "Tuning"},
	"dyno_run": {"xp": 5, "label": "Dyno run"},
	"dyno_strap": {"xp": 1, "label": "Strapping down", "group": "strap"},
	"dyno_hose": {"xp": 2, "label": "Extraction hose on"},
	"fluids": {"xp": 5, "label": "Fluids"},
	"start_build": {"xp": 10, "label": "New build started", "once": "bike"},
	# Getting rid of things: binning is low, recycling better, metal best.
	"bin": {"xp": 1, "label": "Binning", "tag": "salvage"},
	"tip": {"xp": 2, "label": "Old fluid tipped", "tag": "salvage"},
	"recycle_plastic": {"xp": 3, "label": "Recycling", "tag": "salvage"},
	"recycle_metal": {"xp": 5, "label": "Recycling metal", "tag": "salvage"},
	# Cleaning: higher.
	"brush": {"xp": 6, "label": "Cleaning"},
	"washer": {"xp": 6, "label": "Parts washer"},
	"wash_part": {"xp": 1, "label": "Pressure washing"},
	"pressure_wash": {"xp": 8, "label": "Bike washed"},
	"muddy_wash": {"xp": 12, "label": "Mud monster washed", "once": "bike"},
	"chain_lube": {"xp": 6, "label": "Chain lube"},
	# Repairing and spraying: higher again.
	"repair": {"xp": 10, "label": "Restoring"},
	"sandblast": {"xp": 10, "label": "Sandblasting"},
	"paint": {"xp": 12, "label": "Spraying"},
	"prime": {"xp": 6, "label": "Primer coat"},
	"protect_coat": {"xp": 12, "label": "Protective coat"},
	"lighten": {"xp": 8, "label": "Lightening"},
	# The paint mixing bay (see PaintBay): a tin mixed and saved (more for close to its recipe
	# card and an even stir), a test card, a tin stirred even, a colour matched (over 95%) and
	# a part masked off for a stripe or two-tone.
	"paint_mix": {"xp": 10, "label": "Paint mixed"},
	"test_panel": {"xp": 2, "label": "Test card"},
	"paint_stir": {"xp": 2, "label": "Even stir"},
	"colour_match": {"xp": 14, "label": "Colour matched"},
	"masking": {"xp": 6, "label": "Masking"},
	"tyre_remove": {"xp": 4, "label": "Tyre off"},
	"tyre_fit": {"xp": 10, "label": "Tyre fitting"},
	"restore_part": {"xp": 4, "label": "Part like new", "once": "item"},
	# Milestones: high.
	"engine_build": {"xp": 40, "label": "Engine rebuilt", "once": "item", "tag": "builder"},
	"first_start": {"xp": 25, "label": "First start", "once": "bike"},
	"build_complete": {"xp": 150, "label": "Bike build complete", "once": "bike", "tag": "builder"},
	"scratch_build": {"xp": 100, "label": "Built from scratch", "once": "bike", "tag": "builder"},
	"max_health": {"xp": 300, "label": "Restored to max health", "once": "bike", "tag": "builder"},
	# Money: selling bikes from the showroom and parts at the parts computer, and the business growing.
	"sell_bike": {"xp": 100, "label": "Bike sold"},
	"sell_part": {"xp": 5, "label": "Part sold"},
	"px_deal": {"xp": 40, "label": "Part-exchange deal"},
	"money_milestone": {"xp": 50, "label": "Money milestone"},
	# Contracts (see Contracts): paid to the crew who worked on the job when it's handed back.
	"contract_maint": {"xp": 40, "label": "Service job done"},
	"contract_mot": {"xp": 60, "label": "MOT job done"},
	"contract_respray": {"xp": 80, "label": "Colour match job done"},
	"contract_mod": {"xp": 100, "label": "Modification job done"},
	"contract_bespoke": {"xp": 250, "label": "Bespoke build delivered"},
	"mot_test": {"xp": 6, "label": "MOT test"},
	"garage_upgrade": {"xp": 40, "label": "Garage upgrade"},
	# The coffee shop next door (see CoffeeShop): a break, and a biker's bike bought off them.
	"coffee_break": {"xp": 3, "label": "Coffee break"},
	"cafe_bike": {"xp": 30, "label": "Bought a biker's bike"},
	# Riding: worked out on the rider's own machine (RideXP) and paid by the host.
	"jump": {"xp": 12, "label": "Jump", "tag": "air", "rider": true},
	"jump_record": {"xp": 25, "label": "Longest jump", "tag": "air", "rider": true},
	"wheelie": {"xp": 3, "label": "Wheelie", "rider": true},
	"wheelie_record": {"xp": 20, "label": "Longest wheelie", "rider": true},
	"stoppie": {"xp": 4, "label": "Stoppie", "rider": true},
	"stoppie_record": {"xp": 20, "label": "Longest stoppie", "rider": true},
	"burnout": {"xp": 4, "label": "Burnout", "rider": true},
	"knee_down": {"xp": 5, "label": "Knee down", "rider": true},
	"distance": {"xp": 2, "label": "Miles on the clock", "rider": true},
	"top_speed": {"xp": 10, "label": "Top speed", "tag": "speed", "rider": true},
	"sprint": {"xp": 20, "label": "0-100 time", "tag": "speed", "rider": true},
	# Paid locally when a goal is reached (see GOALS); never sent by award().
	"goal": {"xp": 0, "label": "Goal"},
	"mentor": {"xp": 0, "label": "Mentored"},
}

## Wages, in pounds, for the jobs in XP (same keys): the host pays them with Shed.pay_worker,
## so the business takes its cut. They follow the XP's mult and its repeat cut-back (redoing the
## same job pays less and less) and one-offs pay once. Kept modest: selling and contracts are
## where the real money is. Riding pays nothing.
const PAY := {
	"carry": 0, "unbox": 1, "unbolt": 1, "bolt": 1, "remove": 1, "fit": 2, "chain_tension": 3, "tune": 1, "dyno_run": 5,
	"dyno_strap": 0, "dyno_hose": 1, "fluids": 3, "start_build": 10,
	"bin": 0, "tip": 1, "recycle_plastic": 1, "recycle_metal": 2,
	"brush": 3, "washer": 3, "wash_part": 1, "pressure_wash": 4, "muddy_wash": 10, "chain_lube": 3,
	"repair": 6, "sandblast": 6, "paint": 8, "prime": 4, "protect_coat": 8, "lighten": 5, "paint_mix": 5, "test_panel": 1, "paint_stir": 1, "colour_match": 8,
	"masking": 3, "tyre_remove": 2, "tyre_fit": 6, "restore_part": 4,
	"engine_build": 40, "first_start": 20, "build_complete": 120, "scratch_build": 80, "max_health": 200,
	"sell_bike": 50, "sell_part": 2, "px_deal": 20,
}

## Hand tool upgrade stages: the level each needs, its look, and what it does.
const STAGE_NAMES := ["Bare steel", "Polished", "Chrome", "Anodised", "Carbon", "Gold trim"]
const STAGE_LEVEL := [0, 2, 4, 8, 14, 20]
const STAGE_SPEED := 0.12      # each stage takes this much off the work time (as 1 / (1 + n * this))
## What each hand tool's stages improve. speed: what gets quicker ("%d" is how much), spread:
## how much wider per stage (0 = none). Tools not listed just get quicker.
const TOOL_INFO := {
	"hands": {"name": "Hands", "speed": "%d%% quicker fitting, removing, carrying and pouring", "spread": 0.0},
	"wrench": {"name": "Wrench", "speed": "%d%% quicker bolting, unbolting and chain tension", "spread": 0.0},
	"brush": {"name": "Brush", "speed": "%d%% quicker scrubbing", "spread": 0.12, "spread_what": "scrubs a %d%% wider patch"},
	"repair": {"name": "Grinder and welder", "speed": "%d%% quicker restoring", "spread": 0.0},
	"spray": {"name": "Spray can", "speed": "coats %d%% faster", "rate": true, "spread": 0.1, "spread_what": "%d%% wider fan"},
	"lance": {"name": "Pressure washer", "speed": "blasts off %d%% more muck a pass", "rate": true, "spread": 0.15,
		"spread_what": "%d%% wider jet"},
	"gun": {"name": "Spray gun", "speed": "coats %d%% faster", "rate": true, "spread": 0.08, "spread_what": "%d%% wider fan"},
	"watch": {"name": "Stopwatch", "speed": "keeps %d laps", "laps": true, "spread": 0.0},
	"tyre": {"name": "Tyre changer", "speed": "%d%% quicker tyre changes", "spread": 0.0},
}

const BRANCHES := ["mechanic", "finisher", "rider", "tuner", "crew"]
const BRANCH_NAMES := {"mechanic": "Mechanic", "finisher": "Finisher", "rider": "Rider", "tuner": "Tuner", "crew": "Crew"}
## Skills tree. tier sets the row and the level it needs (TIER_LEVEL); needs: skills that must
## have at least one rank first; milestone: a later milestone a skill does nothing until (none now).
const TIER_LEVEL := [2, 5, 10]
const SKILLS := {
	"quick_hands": {"name": "Quick Hands", "branch": "mechanic", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Fit, remove, carry and pour 10% faster per rank."},
	"torque_feel": {"name": "Torque Feel", "branch": "mechanic", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Bolt, unbolt and set chain tension 10% faster per rank."},
	"engine_whisperer": {"name": "Engine Whisperer", "branch": "mechanic", "tier": 1, "ranks": 2, "needs": ["torque_feel"],
		"desc": "Work on engines on the stand 15% faster per rank. Part info shows how much power each worn engine part is costing."},
	"salvager": {"name": "Salvager", "branch": "mechanic", "tier": 1, "ranks": 3, "needs": ["quick_hands"],
		"desc": "+20% XP per rank from binning, tipping old fluid and recycling."},
	"master_builder": {"name": "Master Builder", "branch": "mechanic", "tier": 2, "ranks": 2, "needs": ["engine_whisperer"],
		"desc": "+25% XP per rank for finished builds, scratch builds, engine rebuilds and max-health restorations."},
	"elbow_grease": {"name": "Elbow Grease", "branch": "finisher", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Scrub 12% faster per rank, and the pressure washer blasts off 15% more muck per rank."},
	"steady_hand": {"name": "Steady Hand", "branch": "finisher", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Spray can and gun fans 8% wider per rank, paint runs take 10% more per rank, and the sweet spot for an even coat is 5% wider per rank."},
	"hot_welder": {"name": "Hot Welder", "branch": "finisher", "tier": 1, "ranks": 3, "needs": ["elbow_grease"],
		"desc": "Grinder and welder restore a batch 12% faster per rank."},
	"showroom_shine": {"name": "Showroom Shine", "branch": "finisher", "tier": 1, "ranks": 2, "needs": ["steady_hand"],
		"desc": "Paint and chain lube jobs come out 4% better per rank."},
	"balance": {"name": "Balance", "branch": "rider", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Steadier on one wheel: wheelies and stoppies are easier to hold."},
	"throttle_control": {"name": "Throttle Control", "branch": "rider", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Less wheelspin: you feather the throttle when the back tyre lets go."},
	"airtime": {"name": "Airtime", "branch": "rider", "tier": 1, "ranks": 3, "needs": ["balance"],
		"desc": "+15% jump XP per rank, and you ride out landings 4 degrees more nose-up or down per rank."},
	"quick_reset": {"name": "Quick Reset", "branch": "rider", "tier": 1, "ranks": 2, "needs": ["throttle_control"],
		"desc": "Back on the bike a second sooner per rank after a crash."},
	"speed_demon": {"name": "Speed Demon", "branch": "rider", "tier": 2, "ranks": 2, "needs": ["airtime", "quick_reset"],
		"desc": "+25% XP per rank for top speed and 0-100 records."},
	"dyno_reader": {"name": "Dyno Reader", "branch": "tuner", "tier": 0, "ranks": 2, "needs": [],
		"desc": "The dyno desk shows what wear is costing in power (rank 1) and which part to restore for the biggest gain (rank 2)."},
	"featherweight": {"name": "Featherweight", "branch": "tuner", "tier": 0, "ranks": 3, "needs": [],
		"desc": "Drilling and trimming takes 10% more weight off per rank."},
	"fine_tuning": {"name": "Fine Tuning", "branch": "tuner", "tier": 1, "ranks": 3, "needs": ["dyno_reader"],
		"desc": "Fuel map, ignition and rev limiter go 8% further per rank on bikes you tune."},
	"foreman": {"name": "Foreman", "branch": "crew", "tier": 0, "ranks": 3, "needs": [],
		"desc": "+5% XP per rank while a teammate works within 6 m of you."},
	"mentor": {"name": "Mentor", "branch": "crew", "tier": 1, "ranks": 3, "needs": ["foreman"],
		"desc": "Crew within 10 m get a bonus 5% per rank of the XP you earn (you keep all yours)."},
	"haggler": {"name": "Haggler", "branch": "crew", "tier": 1, "ranks": 3, "needs": ["foreman"],
		"desc": "Parts you order cost 5% less per rank, and what you sell fetches 3% more per rank."},
}

## Goals the Character tab lists: reaching one pays its XP once. stat: a count in the profile's
## stats (several are added up), record: a personal best in its records.
const GOALS := [
	{"id": "build", "text": "Complete a bike build", "stat": ["build_complete"], "need": 1, "xp": 50},
	{"id": "restore", "text": "Restore a bike to 95% health", "stat": ["max_health"], "need": 1, "xp": 100},
	{"id": "scratch", "text": "Build a bike from scratch", "stat": ["scratch_build"], "need": 1, "xp": 75},
	{"id": "engine", "text": "Rebuild an engine on the stand", "stat": ["engine_build"], "need": 1, "xp": 50},
	{"id": "clean50", "text": "Clean 50 parts", "stat": ["brush", "washer", "wash_part"], "need": 50, "xp": 30},
	{"id": "repair25", "text": "Restore 25 parts on the grinder", "stat": ["repair"], "need": 25, "xp": 50},
	{"id": "paint10", "text": "Spray 10 parts", "stat": ["paint"], "need": 10, "xp": 30},
	{"id": "recycle20", "text": "Recycle 20 parts", "stat": ["recycle_plastic", "recycle_metal"], "need": 20, "xp": 40},
	{"id": "jump1", "text": "Land a 1 s jump", "record": "air", "need": 1.0, "xp": 25},
	{"id": "jump2", "text": "Land a 2 s jump", "record": "air", "need": 2.0, "xp": 75},
	{"id": "wheelie50", "text": "Wheelie 50 m", "record": "wheelie", "need": 50.0, "xp": 40},
	{"id": "stoppie15", "text": "Stoppie 15 m", "record": "stoppie", "need": 15.0, "xp": 40},
	{"id": "ton", "text": "Hit 100 km/h", "record": "kmh", "need": 100.0, "xp": 15},
	{"id": "double_ton", "text": "Hit 200 km/h", "record": "kmh", "need": 200.0, "xp": 60},
	{"id": "ride10", "text": "Ride 10 km", "record": "km", "need": 10.0, "xp": 30},
	{"id": "ride100", "text": "Ride 100 km", "record": "km", "need": 100.0, "xp": 150},
]

## Where the profile is kept; tests point it somewhere else.
var path := PATH
## This player's character: {name, xp, tools{tool: stage}, skills{id: rank}, stats{action: n},
## records{air, wheelie, stoppie, kmh, km, sprint, bands[]}, goals[]}.
var profile := {}
## Host: everyone else's reported summary, by peer. Clients: the host's relay of everyone's.
var _summaries := {}
var _recent := {}            # host: "peer|key" -> [msec of recent awards]
var _dirty_save := false
var _save_timer := 0.0
var _report_due := false
var _relay_due := false
var _report_timer := 0.0
## The character came from a save game (use_profile): SaveGame writes it with the shed, and
## profile.json is left alone.
var save_bound := false


func _ready() -> void:
	profile = _clean_profile({}, Settings.player_name)
	# Once the first scene is up, so the test scenes get their own profile file.
	select.call_deferred(Settings.player_name)
	Net.connected.connect(func(): _report_due = true)
	Net.player_joined.connect(func(_id, _info): _relay_due = true; _report_due = true)
	Net.player_left.connect(func(id):
		_summaries.erase(id)
		_relay_due = true
		changed.emit())
	Net.disconnected.connect(func(): _summaries.clear())


## The profile file: the real one, or one per player name while the test scenes run.
func _default_path(player_name: String) -> String:
	if _in_tests():
		return "user://profile_test_%s.json" % player_name.validate_filename().replace(" ", "_")
	return PATH


static func _in_tests() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.current_scene != null and tree.current_scene.scene_file_path.begins_with("res://tests/")


# ---------------------------------------------------------------------------- levels

## Total XP needed to reach `level`: 0 for level 1, then a rising curve.
static func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	return roundi(75.0 * pow(float(level - 1), 1.8))


static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_for_level(level + 1):
		level += 1
	return level


func level() -> int:
	return level_for_xp(int(profile.get("xp", 0)))


func tool_points() -> int:
	var spent := 0
	for t in profile["tools"]:
		spent += int(profile["tools"][t])
	return maxi(0, level() - 1 - spent)


func skill_points() -> int:
	var spent := 0
	for s in profile["skills"]:
		spent += int(profile["skills"][s])
	return maxi(0, level() - 1 - spent)


# ---------------------------------------------------------------------------- the profile on disk

## Loads the character for `player_name` (a new one if there's none yet) from profile.json.
func select(player_name: String) -> void:
	if _dirty_save:
		save_profile()
	save_bound = false
	if path == PATH or path.begins_with("user://profile_test_"):
		path = _default_path(player_name)
	var all := _read_all()
	var p = all.get(player_name, {})
	profile = _clean_profile(p if p is Dictionary else {}, player_name)
	_note_cash()   # what it opens with, so the first money in or out shows on the graph as a step
	_report_due = true
	changed.emit()


## Plays on with the character a save game holds (an empty one for a new game). It's kept in
## memory and saved with the shed from now on, until release().
func use_profile(p: Dictionary, player_name: String) -> void:
	if _dirty_save:
		save_profile()
	save_bound = true
	_dirty_save = false
	profile = _clean_profile(p, player_name)
	_note_cash()
	_report_due = true
	changed.emit()


## The save game is closed: back to the profile.json character for `player_name`.
func release(player_name: String) -> void:
	if not save_bound:
		return
	save_bound = false
	_dirty_save = false
	select(player_name)


## A copy of the character for a save game, with the right types.
func save_copy() -> Dictionary:
	return _clean_profile(profile, str(profile.get("name", Settings.player_name)))


## The character for `player_name` stored in profile.json, or {} when there's none.
func stored_profile(player_name: String) -> Dictionary:
	var p = _read_all().get(player_name, {})
	return p if p is Dictionary else {}


func _read_all() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("profiles") is Dictionary:
		return parsed["profiles"]
	return {}


## A profile with every field present and the right types (JSON brings numbers back as floats).
static func _clean_profile(p: Dictionary, player_name: String) -> Dictionary:
	var out := {"name": player_name, "xp": maxi(0, int(p.get("xp", 0))), "tools": {}, "skills": {}, "stats": {},
		"records": {}, "goals": [], "money": clampi(int(p.get("money", 0)), 0, MAX_MONEY), "cash_log": [],
		"series": MoneyGraph.sanitize(p.get("series", {}))}
	var cash_log = p.get("cash_log", [])
	if cash_log is Array:
		for e in cash_log.slice(-CASH_LOG_SIZE):
			if e is Dictionary:
				out["cash_log"].append({"day": int(e.get("day", 0)), "amt": int(e.get("amt", 0)), "why": str(e.get("why", "")).left(60)})
	var tools = p.get("tools", {})
	if tools is Dictionary:
		for t in tools:
			out["tools"][str(t)] = clampi(int(tools[t]), 0, 5)
	var skills = p.get("skills", {})
	if skills is Dictionary:
		for s in skills:
			if SKILLS.has(str(s)):
				out["skills"][str(s)] = clampi(int(skills[s]), 0, int(SKILLS[str(s)]["ranks"]))
	var stats = p.get("stats", {})
	if stats is Dictionary:
		for s in stats:
			out["stats"][str(s)] = int(stats[s])
	var records = p.get("records", {})
	if records is Dictionary:
		for r in records:
			if records[r] is Array:
				out["records"][str(r)] = (records[r] as Array).map(func(v): return int(v))
			else:
				out["records"][str(r)] = float(records[r])
	var goals = p.get("goals", [])
	if goals is Array:
		for g in goals:
			out["goals"].append(str(g))
	# Rider gear bought in the Shop tab (see RiderGear): what's owned and what's worn.
	out["gear"] = RiderGear.clean_gear(p.get("gear", {}))
	return out


## Writes the character to disk now, keeping every other name's character in the file.
func save_profile() -> bool:
	_dirty_save = false
	if profile.is_empty():
		return false
	if save_bound:
		return true   # saved with the shed
	var all := _read_all()
	all[str(profile["name"])] = profile
	var tmp := "%s.%d.tmp" % [path, OS.get_process_id()]
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "profiles": all}, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


func _touch() -> void:
	_note_cash()
	_dirty_save = true
	_save_timer = 1.5
	_report_due = true
	changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _dirty_save:
			save_profile()


func _process(delta: float) -> void:
	if _dirty_save:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_profile()
	_report_timer -= delta
	if _report_timer > 0.0 or not (_report_due or _relay_due):
		return
	_report_timer = 0.5
	if Net.is_online() and not Net.is_host() and _report_due:
		_report.rpc_id(1, own_summary())
	elif Net.is_host() and not Net.players.is_empty():
		var all := _summaries.duplicate()
		all[1] = own_summary()
		_relay.rpc(all)
	_report_due = false
	_relay_due = false


# ---------------------------------------------------------------------------- awarding XP

## Gives `peer_id` XP for `action` (a key of XP), scaled by `mult`. Host only: on a client it
## does nothing (riding XP goes through rider_event). `detail` names what it was done on, for
## the repeat cut and one-off rewards: "bike:<id>", "item:<id>" or any short text.
func award(peer_id: int, action: String, mult := 1.0, detail := "") -> void:
	if not XP.has(action):
		push_warning("Progress.award: unknown XP action '%s'" % action)
		return
	if not Shed.is_authority():
		return
	var e: Dictionary = XP[action]
	if not _once_ok(e, action, detail):
		return
	var amount := float(e["xp"]) * clampf(mult, 0.0, 20.0)
	var repeat := _repeat_factor(peer_id, action, e, detail)
	amount *= repeat
	_pay(peer_id, action, clampf(mult, 0.0, 20.0) * repeat, str(e["label"]))
	amount *= _skill_bonus(peer_id, e)
	var crew_near := _crew_near(peer_id, NEAR_TEAMMATE)
	if not crew_near.is_empty():
		amount *= 1.0 + 0.05 * skill_rank(peer_id, "foreman")
	var xp := roundi(amount)
	if xp <= 0:
		return
	_deliver(peer_id, xp, str(e["label"]), action)
	var mentor := skill_rank(peer_id, "mentor")
	if mentor > 0:
		var share := roundi(xp * 0.05 * mentor)
		if share > 0:
			var from := str(Shed.crew.get(peer_id, {}).get("name", "a mate"))
			for other in _crew_near(peer_id, MENTOR_REACH):
				_deliver(other, share, "Mentored by %s" % from, "mentor")


## XP worked out on this machine while riding (see RideXP): straight to award() on the host,
## or sent to the host to award.
func rider_event(action: String, mult := 1.0, detail := "") -> void:
	if not XP.get(action, {}).get("rider", false) and action != "first_start":
		push_warning("Progress.rider_event: not a riding action '%s'" % action)
		return
	if Shed.is_authority():
		award(Shed.me(), action, mult, detail)
	else:
		_rider_event.rpc_id(1, action, mult, detail)


@rpc("any_peer", "call_remote", "reliable")
func _rider_event(action: String, mult: float, detail: String) -> void:
	if not Shed.is_authority():
		return
	if not XP.get(action, {}).get("rider", false) and action != "first_start":
		return
	award(multiplayer.get_remote_sender_id(), action, minf(mult, 10.0), detail.left(40))


## The wage for a job (see PAY), paid through the shed so the business takes its cut.
func _pay(peer_id: int, action: String, mult: float, label: String) -> void:
	var gross := roundi(float(PAY.get(action, 0)) * mult)
	if gross > 0 and Shed.has_method("pay_worker"):
		Shed.call("pay_worker", peer_id, gross, label)


func _deliver(peer: int, xp: int, label: String, action: String) -> void:
	if peer == Shed.me():
		_receive(xp, label, action)
	elif Net.is_online() and multiplayer.get_peers().has(peer):
		_grant.rpc_id(peer, xp, label, action)


@rpc("authority", "call_remote", "reliable")
func _grant(xp: int, label: String, action: String) -> void:
	_receive(xp, label, action)


## XP arriving for this player: banked, counted, popped up, and any level-up or goal it brings.
func _receive(xp: int, label: String, action: String) -> void:
	if profile.is_empty() or xp <= 0:
		return
	var before := level()
	profile["xp"] = int(profile["xp"]) + xp
	if action != "goal" and action != "mentor":
		profile["stats"][action] = int(profile["stats"].get(action, 0)) + 1
	xp_gained.emit(xp, label)
	var after := level()
	if after > before:
		leveled_up.emit(after)
	_touch()
	check_goals()


## Pays any goal just reached.
func check_goals() -> void:
	for g in GOALS:
		var id := str(g["id"])
		if profile["goals"].has(id) or goal_have(g) < float(g["need"]):
			continue
		profile["goals"].append(id)
		_receive(int(g["xp"]), "Goal: %s" % g["text"], "goal")


func goal_have(g: Dictionary) -> float:
	if g.has("record"):
		return float(profile["records"].get(str(g["record"]), 0.0))
	var n := 0
	for s in g["stat"]:
		n += int(profile["stats"].get(str(s), 0))
	return float(n)


## One-off rewards: false when this bike or part has already paid it (and marks it paid).
func _once_ok(e: Dictionary, action: String, detail: String) -> bool:
	var kind := str(e.get("once", ""))
	if kind == "":
		return true
	if not detail.begins_with(kind + ":"):
		return false
	var id := int(detail.get_slice(":", 1))
	var holder: Dictionary = Shed.bikes.get(id, {}) if kind == "bike" else Shed.items.get(id, {})
	if holder.is_empty():
		return false
	var done: Array = holder.get("xp_once", [])
	if done.has(action):
		return false
	done.append(action)
	holder["xp_once"] = done
	Shed._mark_dirty()
	return true


## Repeating the same job on the same thing soon after pays half as much each time; jobs with
## nothing named are only cut back after FREE_REPEATS in a minute.
func _repeat_factor(peer: int, action: String, e: Dictionary, detail: String) -> float:
	var now := Time.get_ticks_msec()
	var named := detail != "" and str(e.get("once", "")) == ""
	var key := "%d|%s|%s" % [peer, str(e.get("group", action)), detail if named else ""]
	var window := REPEAT_WINDOW if named else 60.0
	var times: Array = _recent.get(key, [])
	times = times.filter(func(t): return now - int(t) < window * 1000.0)
	var n := times.size()
	times.append(now)
	_recent[key] = times
	if named:
		return pow(0.5, n)
	return 1.0 if n < FREE_REPEATS else pow(0.7, n - FREE_REPEATS + 1)


func _skill_bonus(peer: int, e: Dictionary) -> float:
	match str(e.get("tag", "")):
		"salvage":
			return 1.0 + 0.2 * skill_rank(peer, "salvager")
		"builder":
			return 1.0 + 0.25 * skill_rank(peer, "master_builder")
		"air":
			return 1.0 + 0.15 * skill_rank(peer, "airtime")
		"speed":
			return 1.0 + 0.25 * skill_rank(peer, "speed_demon")
	return 1.0


## Other players within `reach` metres of `peer`, on foot in the shed or out riding.
func _crew_near(peer: int, reach: float) -> Array:
	var out := []
	var at = _position_of(peer)
	if at == null:
		return out
	for other in Shed.crew:
		if int(other) == peer:
			continue
		var p = _position_of(int(other))
		if p != null and (p as Vector3).distance_to(at) <= reach:
			out.append(int(other))
	return out


func _position_of(peer: int):
	if not is_inside_tree():
		return null
	if peer == Shed.me():
		var w := get_tree().get_first_node_in_group("local_walker") as Node3D
		return w.global_position if w and w.is_inside_tree() else null
	for rp in get_tree().get_nodes_in_group("remote_players"):
		if int(rp.peer) == peer:
			return rp.world_position()
	return null


# ---------------------------------------------------------------------------- what other code asks

## Everything the crew board and TVs show about a player: name, level, xp, xp_level_start,
## xp_next, tool_points, skill_points, goals [{text, have, need, xp, done}], plus tools and skills.
func summary(peer_id: int) -> Dictionary:
	if peer_id == Shed.me():
		return own_summary()
	if _summaries.has(peer_id):
		return _summaries[peer_id]
	return {"name": str(Shed.crew.get(peer_id, {}).get("name", "Rider")), "level": 1, "xp": 0, "xp_level_start": 0,
		"xp_next": xp_for_level(2), "tool_points": 0, "skill_points": 0, "goals": [], "tools": {}, "skills": {}, "money": 0}


func own_summary() -> Dictionary:
	var lv := level()
	var goals := []
	for g in GOALS:
		goals.append({"text": g["text"], "have": goal_have(g), "need": float(g["need"]), "xp": int(g["xp"]),
			"done": profile["goals"].has(str(g["id"]))})
	return {"name": str(profile.get("name", "Rider")), "level": lv, "xp": int(profile.get("xp", 0)),
		"xp_level_start": xp_for_level(lv), "xp_next": xp_for_level(mini(lv + 1, MAX_LEVEL)),
		"tool_points": tool_points(), "skill_points": skill_points(), "goals": goals,
		"tools": profile["tools"].duplicate(), "skills": profile["skills"].duplicate(), "money": money(),
		"gear": RiderGear.worn_of(Shed.me())}


func tool_stage(peer_id: int, tool: String) -> int:
	var tools: Dictionary = profile.get("tools", {}) if peer_id == Shed.me() else summary(peer_id).get("tools", {})
	return clampi(int(tools.get(tool, 0)), 0, 5)


func skill_rank(peer_id: int, skill: String) -> int:
	var skills: Dictionary = profile.get("skills", {}) if peer_id == Shed.me() else summary(peer_id).get("skills", {})
	return int(skills.get(skill, 0))


@rpc("any_peer", "call_remote", "reliable")
func _report(s: Dictionary) -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	_summaries[peer] = _clean_summary(s)
	_relay_due = true
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _relay(all: Dictionary) -> void:
	_summaries.clear()
	for peer in all:
		if int(peer) != Shed.me() and all[peer] is Dictionary:
			_summaries[int(peer)] = _clean_summary(all[peer])
	changed.emit()


## A reported summary with sane types and limits, so a bad report can't break anything.
static func _clean_summary(s: Dictionary) -> Dictionary:
	var tools := {}
	var t = s.get("tools", {})
	if t is Dictionary:
		for k in t:
			tools[str(k)] = clampi(int(t[k]), 0, 5)
	var skills := {}
	var k2 = s.get("skills", {})
	if k2 is Dictionary:
		for k in k2:
			if SKILLS.has(str(k)):
				skills[str(k)] = clampi(int(k2[k]), 0, int(SKILLS[str(k)]["ranks"]))
	var goals := []
	var g = s.get("goals", [])
	if g is Array:
		for row in g.slice(0, 40):
			if row is Dictionary:
				goals.append({"text": str(row.get("text", "")).left(60), "have": float(row.get("have", 0.0)),
					"need": float(row.get("need", 1.0)), "xp": int(row.get("xp", 0)), "done": bool(row.get("done", false))})
	return {"name": str(s.get("name", "Rider")).left(24), "level": clampi(int(s.get("level", 1)), 1, MAX_LEVEL),
		"xp": maxi(0, int(s.get("xp", 0))), "xp_level_start": int(s.get("xp_level_start", 0)), "xp_next": int(s.get("xp_next", 0)),
		"tool_points": int(s.get("tool_points", 0)), "skill_points": int(s.get("skill_points", 0)), "goals": goals,
		"tools": tools, "skills": skills, "money": clampi(int(s.get("money", 0)), 0, MAX_MONEY),
		"gear": RiderGear.clean_worn(s.get("gear", {}))}


# ---------------------------------------------------------------------------- spending points

func tool_name(tool: String) -> String:
	return str(TOOL_INFO.get(tool, {}).get("name", tool.capitalize()))


## What a tool does at `stage`: "Stage 2, Chrome: 21% quicker bolting...".
func tool_effect_text(tool: String, stage: int) -> String:
	if stage <= 0:
		return "Stage 0, %s: stock" % STAGE_NAMES[0]
	var info: Dictionary = TOOL_INFO.get(tool, {"speed": "%d%% quicker"})
	var lines := []
	var n: int = 5 + stage if info.get("laps", false) else (roundi(STAGE_SPEED * stage * 100.0) if info.get("rate", false)
		else roundi((1.0 - 1.0 / (1.0 + STAGE_SPEED * stage)) * 100.0))
	lines.append(str(info["speed"]) % n)
	if float(info.get("spread", 0.0)) > 0.0:
		lines.append(str(info["spread_what"]) % roundi(float(info["spread"]) * stage * 100.0))
	return "Stage %d, %s: %s" % [stage, STAGE_NAMES[stage], ", ".join(lines)]


## Why the next stage of `tool` can't be bought now, or "".
func tool_block(tool: String) -> String:
	var stage := tool_stage(Shed.me(), tool)
	if stage >= 5:
		return "Fully upgraded."
	if level() < int(STAGE_LEVEL[stage + 1]):
		return "Needs level %d." % STAGE_LEVEL[stage + 1]
	if tool_points() <= 0:
		return "No tool points left. Level up for more."
	return ""


## Spends a tool point on the next stage of `tool`. Returns why not, or "".
func upgrade_tool(tool: String) -> String:
	var why := tool_block(tool)
	if why != "":
		return why
	profile["tools"][tool] = tool_stage(Shed.me(), tool) + 1
	_touch()
	return ""


## Why a rank of `skill` can't be bought now, or "".
func skill_block(skill: String) -> String:
	if not SKILLS.has(skill):
		return "No such skill."
	var s: Dictionary = SKILLS[skill]
	if skill_rank(Shed.me(), skill) >= int(s["ranks"]):
		return "Maxed out."
	var needs: Array = s["needs"]
	if not needs.is_empty() and needs.all(func(n): return skill_rank(Shed.me(), str(n)) <= 0):
		return "Needs %s first." % " or ".join(needs.map(func(n): return SKILLS[n]["name"]))
	if level() < int(TIER_LEVEL[int(s["tier"])]):
		return "Needs level %d." % TIER_LEVEL[int(s["tier"])]
	if skill_points() <= 0:
		return "No skill points left. Level up for more."
	return ""


func buy_skill(skill: String) -> String:
	var why := skill_block(skill)
	if why != "":
		return why
	profile["skills"][skill] = skill_rank(Shed.me(), skill) + 1
	_touch()
	return ""


## Hands back every skill point to spend again.
func respec() -> void:
	profile["skills"] = {}
	_touch()


# ---------------------------------------------------------------------------- effects in the work

## How long a job takes compared with a stock tool and no skills: the tool's stage and the
## skills that speed that job up. `action` is the Shed action the job asks for.
func time_mult(peer: int, tool: String, action: Dictionary) -> float:
	var a := str(action.get("a", ""))
	var m := 1.0 / (1.0 + STAGE_SPEED * tool_stage(peer, tool))
	if a in ["install", "remove", "take", "place", "drop", "set_down", "pour", "drain", "tip", "bin", "start_build"]:
		m *= 1.0 - 0.1 * skill_rank(peer, "quick_hands")
	if a in ["bolt", "unbolt", "adjust_chain"]:
		m *= 1.0 - 0.1 * skill_rank(peer, "torque_feel")
	if a in ["clean", "clean_many"]:
		m *= 1.0 - 0.12 * skill_rank(peer, "elbow_grease")
	if a in ["repair", "repair_many"]:
		m *= 1.0 - 0.12 * skill_rank(peer, "hot_welder")
	if int(action.get("engine", 0)) != 0:
		m *= 1.0 - 0.15 * skill_rank(peer, "engine_whisperer")
	return clampf(m, 0.2, 1.0)


## How much faster a spraying tool lays its coat (the can, gun, or lube can held in the hands).
func cover_rate_mult(peer: int, tool: String) -> float:
	return 1.0 + STAGE_SPEED * tool_stage(peer, tool)


## How much wider a tool's spray, brush or jet reaches.
func spread_mult(peer: int, tool: String) -> float:
	var m := 1.0 + float(TOOL_INFO.get(tool, {}).get("spread", 0.0)) * tool_stage(peer, tool)
	if tool in ["spray", "gun"]:
		m *= 1.0 + 0.08 * skill_rank(peer, "steady_hand")
	return m


## How much wider the spray can's and gun's sweet spot is (the range of distances an even coat
## goes on from): the tool's upgrades and Steady Hand both help, so practice pays off.
func spray_band_mult(peer: int, tool: String) -> float:
	return (1.0 + 0.04 * tool_stage(peer, tool)) * (1.0 + 0.05 * skill_rank(peer, "steady_hand"))


## How many coats a patch takes before it runs, relative to stock: faster tools lay more paint,
## so the runs level rises with them, and Steady Hand lifts it further.
func run_level_mult(peer: int, tool: String) -> float:
	return cover_rate_mult(peer, tool) * (1.0 + 0.1 * skill_rank(peer, "steady_hand"))


## Host: how much more muck each pressure washer pass takes off.
func jet_clean_mult(peer: int) -> float:
	return (1.0 + STAGE_SPEED * tool_stage(peer, "lance")) * (1.0 + 0.15 * skill_rank(peer, "elbow_grease"))


## Host: added to the quality of a paint or lube job.
func finish_bonus(peer: int) -> float:
	return 0.04 * skill_rank(peer, "showroom_shine")


## Host: extra fraction of the usual weight drilling and trimming takes off.
func lighten_bonus(peer: int) -> float:
	return 0.1 * skill_rank(peer, "featherweight")


## Host: how much further the map, ignition and limiter go on a bike this player tunes.
func tune_reach(peer: int) -> float:
	return 0.08 * skill_rank(peer, "fine_tuning")


## How many laps the stopwatch keeps.
func stopwatch_laps(peer: int) -> int:
	return 5 + tool_stage(peer, "watch")


## The riding skills, for the bike this player rides.
func rider_skills() -> Dictionary:
	var out := {}
	for s in ["balance", "throttle_control", "airtime", "quick_reset"]:
		out[s] = skill_rank(Shed.me(), s)
	return out


## A personal best or running total kept in the profile (see RideXP), 0 when none yet.
func record(key: String) -> float:
	var v = profile.get("records", {}).get(key, 0.0)
	return float(v) if not v is Array else 0.0


func set_record(key: String, value: float) -> void:
	profile["records"][key] = value
	_touch()
	check_goals()


## Speed bands already reached, as km/h numbers.
func speed_bands() -> Array:
	var v = profile.get("records", {}).get("bands", [])
	return v if v is Array else []


func add_speed_band(band: int) -> void:
	var bands := speed_bands()
	if not bands.has(band):
		bands.append(band)
	profile["records"]["bands"] = bands
	_touch()


# ---------------------------------------------------------------------------- money and debugging

## This player's cash.
func money() -> int:
	return int(profile.get("money", 0))


## Any player's cash, as far as this machine knows (their reported summary for others).
func money_of(peer_id: int) -> int:
	return money() if peer_id == Shed.me() else int(summary(peer_id).get("money", 0))


## Sets this player's cash (kept in their profile).
func set_money(amount: int) -> void:
	profile["money"] = clampi(amount, 0, MAX_MONEY)
	_touch()


## Adds to this player's own cash (wages, money sent to them, what they take out of the business).
func earn(amount: int, reason: String) -> void:
	if amount <= 0 or profile.is_empty():
		return
	var was := money()
	profile["money"] = clampi(was + amount, 0, MAX_MONEY)
	_log_cash(money() - was, reason)
	cash_changed.emit(money() - was, reason)
	_touch()


## Takes `amount` of this player's own cash. False, and nothing taken, when they haven't got it.
func spend(amount: int, reason: String) -> bool:
	if amount < 0 or profile.is_empty() or money() < amount:
		return false
	if amount == 0:
		return true
	profile["money"] = money() - amount
	_log_cash(-amount, reason)
	cash_changed.emit(-amount, reason)
	_touch()
	return true


func _log_cash(amt: int, why: String) -> void:
	var cash_log: Array = profile["cash_log"]
	var day := _today()
	if not cash_log.is_empty() and str(cash_log[-1]["why"]) == why and int(cash_log[-1]["day"]) == day \
			and (int(cash_log[-1]["amt"]) >= 0) == (amt >= 0):
		cash_log[-1]["amt"] = int(cash_log[-1]["amt"]) + amt
	else:
		cash_log.append({"day": day, "amt": amt, "why": why.left(60)})
	while cash_log.size() > CASH_LOG_SIZE:
		cash_log.pop_front()


## The shed's in-game day (see Money), 0 without one.
func _today() -> int:
	var bank = Shed.get("bank")
	return int(bank.get("day", 0)) if bank is Dictionary else 0


## Host: hands `peer` cash, here for the host's own player, else on their machine. False when
## they aren't connected (nothing is paid).
func give_cash(peer: int, amount: int, reason: String) -> bool:
	if amount <= 0:
		return true
	if peer == Shed.me():
		earn(amount, reason)
		return true
	if Net.is_online() and multiplayer.get_peers().has(peer):
		_cash.rpc_id(peer, amount, reason)
		return true
	return false


@rpc("authority", "call_remote", "reliable")
func _cash(amount: int, reason: String) -> void:
	earn(amount, reason.left(60))


## This player's money over the last `days` in-game days: {earned, spent}.
func cash_flow(days := 7) -> Dictionary:
	var since := _today() - days + 1
	var earned := 0
	var spent := 0
	for e in profile.get("cash_log", []):
		if int(e["day"]) < since:
			continue
		if int(e["amt"]) > 0:
			earned += int(e["amt"])
		else:
			spent -= int(e["amt"])
	return {"earned": earned, "spent": spent}


## Notes this player's cash in the graph's series when it has moved (see MoneyGraph).
func _note_cash() -> void:
	if profile.is_empty():
		return
	if not (profile.get("series") is Dictionary):
		profile["series"] = {}
	MoneyGraph.record(profile["series"], MoneyGraph.now_hours(), money())


## This player's cash over the range's buckets ("minute" .. "year"), oldest first and now last.
func cash_graph(range_key: String) -> Array:
	return MoneyGraph.points(profile.get("series", {}), range_key, MoneyGraph.now_hours(), money())


## This player's cash at the end of each of the last six days and now, worked back from the log.
func cash_history() -> Array:
	var today := _today()
	var out := []
	var bal := money()
	var cash_log: Array = profile.get("cash_log", [])
	var i := cash_log.size() - 1
	for d in range(today, today - 7, -1):
		out.push_front(bal)
		while i >= 0 and int(cash_log[i]["day"]) >= d:
			bal -= int(cash_log[i]["amt"])
			i -= 1
		bal = maxi(bal, 0)
	return out


## Debug: this player back to a new character: level 1, no XP, no tool upgrades, skills or goals.
func debug_reset_xp() -> void:
	profile["xp"] = 0
	profile["tools"] = {}
	profile["skills"] = {}
	profile["goals"] = []
	profile["stats"] = {}
	profile["records"] = {}
	_touch()


## Debug: this player straight to the top level, with every point to spend.
func debug_max_xp() -> void:
	profile["xp"] = maxi(int(profile.get("xp", 0)), xp_for_level(MAX_LEVEL))
	_touch()
	leveled_up.emit(level())


## Debug, host or solo only: every player's XP reset, the host's own here and each client's on
## their machine. False on a client.
func debug_reset_all_xp() -> bool:
	if not Shed.is_authority():
		return false
	debug_reset_xp()
	if Net.is_online():
		_debug_reset.rpc()
	return true


@rpc("authority", "call_remote", "reliable")
func _debug_reset() -> void:
	debug_reset_xp()
	Shed.feedback.emit("The host reset everyone's XP.", true)
