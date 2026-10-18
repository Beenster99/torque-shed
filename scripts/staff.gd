class_name Staff
extends RefCounted
## The garage's own staff: people the business takes on as the crew levels up, to do the work
## while you do something else. Six roles, each unlocked at a character level (UNLOCK):
##   detailer   washes bikes in the wash bay (a list of steps per detailing job, see StaffJobs)
##   reception  minds the reception desk: greets customers and keeps them waiting happily
##   mechanic   services bikes and fits parts (simple ones: nothing else has to come off first)
##   sales      puts bikes on the showroom plinths, prices them and haggles with buyers
##   paint      paint expert: takes a part off, mixes at the bench, sprays it in the booth
##   expert     expert mechanic: any part (stripping what's in the way and refitting it), tyres
##              on the tyre changer, brake fluid as well as oil in a service
## Candidates turn up on the hiring board (the Esc menu's Staff tab), a few new ones a day, each
## with a name, a look, a short back story, a starting skill and a daily wage. Hire one (up to
## MAX_STAFF), give them a job (look at them and press F, or from the Staff tab) and leave them to
## it: they walk round the shed doing it with the same requests the crew make (Shed.request's
## checks and changes, as a pseudo player of their own, see peer_of), so what they do is real.
## When it's done they say so and go back to their role's own duty (reception at the desk, the
## salesman on the showroom floor, the rest at their spot), and now and then someone fetches
## teas from the cafe next door for everyone. Wages go on the nightly running costs bill
## (Money.bill_lines). They get better at their job doing it (XP to a level, MAX_LEVEL: quicker,
## fewer slips, better finishes and prices), their mood goes up and down, and every so often one
## phones in sick for the day.
##
## All of it is host-authoritative shed state in Shed.staff (saved with the shed). Players ask
## for changes with Shed.request({"a": "staff_..."}), which Shed hands to check()/apply(); the
## host runs the staff at TICK a second (process). Everything here is static, like CoffeeShop.

const ROLES: Array[String] = ["detailer", "reception", "mechanic", "sales", "paint", "expert"]
const ROLE_NAMES := {"sales": "Salesman", "reception": "Receptionist", "paint": "Paint Expert", "detailer": "Detailer",
	"mechanic": "Mechanic", "expert": "Expert Mechanic"}
## The character level the person hiring needs for each role.
const UNLOCK := {"detailer": 3, "reception": 4, "mechanic": 5, "sales": 6, "paint": 8, "expert": 12}
## A day's wage at skill level 1 (more for a more skilled hire, see wage_for), at "normal" costs.
const WAGE := {"detailer": 60, "reception": 55, "mechanic": 85, "sales": 70, "paint": 95, "expert": 135}
const WAGE_PER_LEVEL := 0.12
const MAX_STAFF := 6
const MAX_LEVEL := 10
## The host works the staff out this often (seconds), not every frame.
const TICK := 0.25
## Pseudo player ids: worker `id` acts as peer -(PEER_BASE + id), clear of real peers (> 0),
## nobody (0) and the -1s some code uses for "none".
const PEER_BASE := 100
## Jobs, and the roles that do them.
const JOBS := {"service": ["mechanic", "expert"], "fit": ["mechanic", "expert"], "paint": ["paint"],
	"detail": ["detailer"], "sell": ["sales"], "reception": ["reception"], "tea": []}
const JOB_NAMES := {"service": "Service a bike", "fit": "Fit a part", "paint": "Paint a part", "detail": "Wash and detail a bike",
	"sell": "Sell a bike", "reception": "Run reception", "tea": "Fetch teas from the cafe"}
## A day's chance someone phones in sick (more when they're fed up), and the fewest days between.
const SICK_CHANCE := 0.05
const SICK_LOW_MOOD := 0.08
const SICK_GAP := 3
## How often (real seconds) someone idle fetches a round of teas while the cafe's open.
const TEA_EVERY := 540.0
const TEA_FIRST := 240.0
## How long a line said stays over their head, and the news kept for the TV.
const SAY_SECS := 7.0
const MAX_NEWS := 8
## How long the salesman thinks over an offer, and how many jobs in a row can fail before
## they give it up.
const CONSIDER_SECS := 9.0
const MAX_FAILS := 3
const MAX_REPLANS := 80

## Clothes by role, and the town and back story pools (see _story).
const ROLE_TOPS := {
	"mechanic": [Color(0.12, 0.18, 0.35), Color(0.3, 0.32, 0.35), Color(0.55, 0.12, 0.1), Color(0.1, 0.28, 0.18)],
	"expert": [Color(0.08, 0.1, 0.16), Color(0.22, 0.24, 0.26), Color(0.4, 0.1, 0.08)],
	"paint": [Color(0.9, 0.9, 0.88), Color(0.82, 0.84, 0.86), Color(0.75, 0.78, 0.8)],
	"detailer": [Color(0.1, 0.45, 0.6), Color(0.85, 0.45, 0.1), Color(0.2, 0.55, 0.3), Color(0.08, 0.08, 0.1)],
	"sales": [Color(0.15, 0.17, 0.22), Color(0.35, 0.36, 0.4), Color(0.2, 0.12, 0.1)],
	"reception": [Color(0.55, 0.15, 0.3), Color(0.15, 0.3, 0.55), Color(0.9, 0.88, 0.82), Color(0.3, 0.12, 0.4)],
}
const TOWNS := ["Wolverhampton", "Bristol", "Leeds", "Swansea", "Hull", "Carlisle", "Ipswich", "Derby", "Plymouth", "Dundee",
	"Coventry", "Norwich", "Stoke", "Preston", "Bangor", "Grimsby"]
## [first person, third person] with %s for the town.
const ORIGINS := [["I grew up in %s, over a bike shop.", "Grew up in %s, over a bike shop."],
	["I came down from %s last spring.", "Came down from %s last spring."],
	["I was born and raised in %s.", "Born and raised in %s."],
	["I left %s with a toolbox and a bus ticket.", "Left %s with a toolbox and a bus ticket."],
	["Everyone rides where I'm from, %s.", "Comes from %s, where everyone rides."]]
const CAREERS := {
	"mechanic": [["I did six years at a main dealer and hated the paperwork.", "Did six years at a main dealer and hated the paperwork."],
		["I learned the trade keeping courier scooters alive.", "Learned the trade keeping courier scooters alive."],
		["I raced club motocross till my knees gave out.", "Raced club motocross until the knees gave out."],
		["I rebuilt a Bonneville in a garden shed at fifteen.", "Rebuilt a Bonneville in a garden shed at fifteen."]],
	"expert": [["I built race engines for a superbike team for twenty years.", "Built race engines for a superbike team for twenty years."],
		["I ran my own workshop for a decade before it shut.", "Ran a workshop for a decade before it shut."],
		["I've a drawer full of trophies from the Isle of Man paddock.", "Has a drawer full of trophies from the Isle of Man paddock."],
		["I trained the apprentices at the college for years.", "Trained the apprentices at the college for years."]],
	"paint": [["I sprayed custom helmets for half the club racers up north.", "Sprayed custom helmets for half the club racers up north."],
		["I came over from a car body shop and never looked back.", "Came over from a car body shop and never looked back."],
		["I did the pinstriping at all the county shows.", "Did the pinstriping at all the county shows."],
		["I once matched a colour from a photo of a sunset. The customer cried.", "Once matched a colour from a photo of a sunset, and the customer cried."]],
	"detailer": [["I ran a valeting van out of a supermarket car park.", "Ran a valeting van out of a supermarket car park."],
		["I polished show bikes for a classic dealer.", "Polished show bikes for a classic dealer."],
		["I started washing bikes at the cafe for tips.", "Started washing bikes at the cafe for tips."],
		["I've got strong opinions about microfibre.", "Has strong opinions about microfibre."]],
	"sales": [["I sold cars for years. Don't hold it against me.", "Sold cars for years, and won't be told it shows."],
		["I once talked a vicar into a sports bike.", "Once talked a vicar into a sports bike, and is very proud of it."],
		["I ran a stall at the autojumble every Sunday.", "Ran a stall at the autojumble every Sunday."],
		["I was top seller at a big dealer three years running.", "Was top seller at a big dealer three years running."]],
	"reception": [["I kept a dentist's waiting room calm for ten years.", "Kept a dentist's waiting room calm for ten years."],
		["I ran the front desk at a busy hotel.", "Ran the front desk at a busy hotel."],
		["I organise the bike club's runs and raffles.", "Organises the bike club's runs and raffles."],
		["I can remember every customer's number.", "Can remember every customer's number."]],
}
const QUIRKS := [["I can't start the day without a bacon roll.", "Can't start the day without a bacon roll."],
	["I ride an old Honda at weekends, rain or shine.", "Rides an old Honda at weekends, rain or shine."],
	["I'm saving up for a trip round the Alps.", "Saving up for a trip round the Alps."],
	["I've got a dog called Sprocket.", "Has a dog called Sprocket."],
	["I whistle along to everything on the radio. Sorry.", "Whistles along to everything on the radio."],
	["Two sugars and a digestive, me. Every time.", "Takes two sugars and a digestive, every time."],
	["I keep a tidy toolbox. I'll be judging yours.", "Keeps a tidy toolbox, and judges yours."],
	["I'm learning the guitar. Badly.", "Learning the guitar, badly."]]
const HAPPY := ["Lovely day for it!", "Best job I've had, this.", "Love the smell of a workshop first thing.", "All good here, boss.",
	"Can't complain. Well, I could, but I won't."]
const OK := ["Not bad, ta.", "Plodding on.", "Another day, another bolt.", "Could be worse. Could be raining. Oh, it is."]
const LOW := ["Could murder a cup of tea.", "My back's killing me.", "Any chance of a brew?", "Long day, this.",
	"Don't suppose there's a pay rise going?"]
const ROLE_LINES := {
	"mechanic": ["Torque settings are a suggestion. Joking. Mostly.", "Copper grease on everything, that's my motto.",
		"Give me a bike that won't start and I'm happy."],
	"expert": ["Nothing's seized. It's just not tried hard enough yet.", "Listen to an engine long enough and it tells you what's wrong.",
		"The trick is knowing what comes off first."],
	"paint": ["Prep is everything. The spraying's the easy bit.", "Keep the gun moving and the runs stay away.",
		"Two thin coats beat one fat one."],
	"detailer": ["Top down, never in circles.", "A clean bike sells itself.", "Mud is just paint you didn't ask for."],
	"sales": ["Everyone's a buyer. They just don't know it yet.", "Never say the first number.", "Sell the ride, not the bike."],
	"reception": ["Phone's been quiet. Too quiet.", "I've put the kettle on for the next customer.", "Smile and the customers smile back."],
}
const BYES := ["Fair enough. It was good while it lasted.", "No hard feelings. Mind how you go.", "Right. I'll get my coat.",
	"Your loss, boss. Good luck with the place.", "I'll leave my overalls on the peg."]
const SICK := ["Got a stinking cold, I'm not coming in.", "Ate a dodgy kebab. Not today, boss.", "Bad back. Can't even put my socks on.",
	"The kid's off school and so am I.", "Migraine. Curtains shut, sorry.", "Something's going round and I've got it."]
const BACK := ["Feeling better, ta. What did I miss?", "Back on my feet. Where are we?", "Right as rain. Let's crack on."]
const HELLOS := ["Morning! Glad to be here.", "Right then, where do you want me?", "Nice place. Let's get stuck in."]
const DONE_LINES := ["Done!", "All finished.", "That's that sorted.", "Job's a good 'un."]

## Lines worth repeating when they're asked to do what they're already doing.
## Tests: the day's sick roll (0..1) instead of a random one, when 0 or more.
static var test_roll := -1.0
static var _heard := {}        # worker id -> the last thing the shed told them (host only)


# ---------------------------------------------------------------------------- state

## A new shed: nobody on the payroll, the board drawn on the first day.
static func empty() -> Dictionary:
	return {"next": 1, "workers": {}, "board": {}, "board_day": -1, "clock": 0.0, "news": [], "tea_at": TEA_FIRST, "hired": 0}


## Saved or synced staff made safe to use: sheds from before staff have none.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
		elif s.has(key) and key in ["clock", "tea_at"] and (s[key] is int or s[key] is float):
			out[key] = float(s[key])
	for id in out["workers"].keys():
		if not (out["workers"][id] is Dictionary) or not ROLES.has(str(out["workers"][id].get("role", ""))):
			out["workers"].erase(id)
		else:
			_fill_worker(out["workers"][id], int(id))
	for id in out["board"].keys():
		if not (out["board"][id] is Dictionary) or not ROLES.has(str(out["board"][id].get("role", ""))):
			out["board"].erase(id)
	return out


## Fields every worker has (older saves, odd values): defaults filled in.
static func _fill_worker(w: Dictionary, id: int) -> void:
	var defaults := {"id": id, "name": "Worker", "look": {}, "story": [], "wage": 60, "xp": 0, "mood": 0.75, "hired_day": 0,
		"sick": false, "sick_last": -99, "jobs": 0, "job": {}, "at": StaffNav.idle(str(w.get("role", "mechanic"))),
		"pos": Vector3.ZERO, "yaw": 0.0, "leg": {}, "anim": "", "say": "", "say_at": -100.0, "deal": 0, "deal_at": 0.0,
		"greeted": [], "earned": 0}
	for k in defaults:
		if not w.has(k) or typeof(w[k]) != typeof(defaults[k]):
			if k == "pos" and w.get("pos") is Vector3:
				continue
			w[k] = defaults[k]
	w["id"] = id


static func _st() -> Dictionary:
	if not (Shed.staff is Dictionary) or not Shed.staff.has("workers"):
		Shed.staff = empty()
	return Shed.staff


static func workers() -> Dictionary:
	return _st()["workers"]


static func board() -> Dictionary:
	return _st()["board"]


static func clock() -> float:
	return float(_st()["clock"])


static func worker(id: int) -> Dictionary:
	return workers().get(id, {})


## Host, after a save is opened: nobody is mid-step (what they held went back on the bench with
## everyone else's, see Shed.load_state). A job in hand starts again from a fresh look at the
## shed, wherever it had got to; everyone's back at their own spot.
static func after_load() -> void:
	var k := {}
	for id in workers():
		var w: Dictionary = workers()[id]
		var role := str(w["role"])
		k[role] = int(k.get(role, 0)) + 1
		w["at"] = StaffNav.idle(role, int(k[role]) - 1)
		w["pos"] = StaffNav.spot(w["at"])
		w["leg"] = {}
		w["anim"] = ""
		w["deal"] = 0
		var job: Dictionary = w["job"]
		if not job.is_empty():
			job["steps"] = [{"do": "plan"}]
			job["i"] = 0
			job["on"] = false
			job["t"] = 0.0
	_st()["clock"] = 0.0
	_st()["tea_at"] = TEA_FIRST


# ---------------------------------------------------------------------------- who's who

## The pseudo player id worker `id` acts as in Shed requests.
static func peer_of(id: int) -> int:
	return -(PEER_BASE + id)


## The worker a pseudo player id is, or 0 for a real player.
static func id_of_peer(peer: int) -> int:
	return -peer - PEER_BASE if peer < -PEER_BASE else 0


static func is_staff_peer(peer: int) -> bool:
	return peer < -PEER_BASE


static func role_name(role: String) -> String:
	return str(ROLE_NAMES.get(role, role.capitalize()))


static func first_name(w: Dictionary) -> String:
	return str(w.get("name", "")).get_slice(" ", 0)


static func money(v: int) -> String:
	return TvChannels.money_text(v)


## The level a worker with `xp` is (1..MAX_LEVEL), and the XP each level starts at.
static func level_of(xp: int) -> int:
	var lv := 1
	while lv < MAX_LEVEL and xp >= xp_for(lv + 1):
		lv += 1
	return lv


static func xp_for(level: int) -> int:
	return 0 if level <= 1 else roundi(30.0 * pow(float(level - 1), 1.6))


static func level(w: Dictionary) -> int:
	return level_of(int(w.get("xp", 0)))


## How far they are through their level, 0..1.
static func level_frac(w: Dictionary) -> float:
	var lv := level(w)
	if lv >= MAX_LEVEL:
		return 1.0
	var a := xp_for(lv)
	return clampf(float(int(w.get("xp", 0)) - a) / maxf(1.0, float(xp_for(lv + 1) - a)), 0.0, 1.0)


## How much quicker than a beginner they work.
static func speed(w: Dictionary) -> float:
	return 1.0 + 0.1 * (level(w) - 1)


## The chance a step goes wrong (a dropped bolt, a run in the paint) and takes longer.
static func slip_chance(w: Dictionary) -> float:
	return lerpf(0.25, 0.02, float(level(w) - 1) / float(MAX_LEVEL - 1))


## How good a finish they turn out, 0..1 (paint and lube jobs).
static func finish(w: Dictionary) -> float:
	return clampf(0.5 + 0.055 * level(w) + Shed._rng.randf_range(-0.04, 0.04), 0.0, 1.0)


## A day's wage for someone of `role` hired at skill `lv`.
static func wage_for(role: String, lv: int) -> int:
	return roundi(float(WAGE.get(role, 60)) * (1.0 + WAGE_PER_LEVEL * (lv - 1)) / 5.0) * 5


## Everyone's wages for a day (before the running costs setting, see Money.bill_lines).
static func wage_bill() -> int:
	var total := 0
	for id in workers():
		total += int(workers()[id]["wage"])
	return total


static func mood_word(w: Dictionary) -> String:
	var m := float(w.get("mood", 0.7))
	if m >= 0.8:
		return "cheerful"
	if m >= 0.6:
		return "content"
	if m >= 0.4:
		return "a bit fed up"
	return "grumpy"


## What they're doing now, in a few words ("Servicing the Barn Find: unbolting the pads").
static func status_text(w: Dictionary) -> String:
	if w.get("sick", false):
		return "Off sick today"
	var job: Dictionary = w.get("job", {})
	if not job.is_empty():
		var doing := str(job.get("doing", ""))
		return str(job.get("label", "Working")) + (": " + doing if doing != "" else "")
	match str(w["role"]):
		"reception":
			return "On reception"
		"sales":
			return "On the showroom floor" if int(w.get("deal", 0)) == 0 else "Talking a buyer round"
	return "Waiting for a job"


## How far through their job they are, 0..1 (0 with none).
static func progress(w: Dictionary) -> float:
	var job: Dictionary = w.get("job", {})
	if job.is_empty():
		return 0.0
	var steps: Array = job.get("steps", [])
	var left := 0.0
	for i in range(int(job.get("i", 0)), steps.size()):
		left += 2.0 if str(steps[i].get("do", "")) == "plan" else 1.0
	var done := float(job.get("done", 0))
	return clampf(done / maxf(1.0, done + left), 0.0, 0.99)


# ---------------------------------------------------------------------------- the hiring board

## A candidate for `role`: a name, a look in the role's clothes, a three-line back story, a
## starting skill and the wage that goes with it.
static func make_candidate(role: String, rng: RandomNumberGenerator, id := 0) -> Dictionary:
	var person := "%s %s" % [Contracts.FIRST_NAMES[rng.randi() % Contracts.FIRST_NAMES.size()],
		Contracts.LAST_NAMES[rng.randi() % Contracts.LAST_NAMES.size()]]
	var tops: Array = ROLE_TOPS.get(role, ROLE_TOPS["mechanic"])
	var top: Color = tops[rng.randi() % tops.size()]
	var look := {"top": top, "legs": top.darkened(0.25) if role in ["mechanic", "expert", "paint"] else Color(0.12, 0.13, 0.17).lerp(Color(0.3, 0.25, 0.2), rng.randf()),
		"skin": Contracts.SKINS[rng.randi() % Contracts.SKINS.size()], "hair": Contracts.HAIR[rng.randi() % Contracts.HAIR.size()],
		"hat": role in ["mechanic", "detailer"] and rng.randf() < 0.35, "tall": rng.randf_range(0.93, 1.06),
		"tie": role == "sales", "bald": rng.randf() < 0.12}
	var lv := 1 + int(floor(pow(rng.randf(), 1.8) * 4.0))
	if role == "expert":
		lv += 2
	var town: String = TOWNS[rng.randi() % TOWNS.size()]
	var origin: Array = ORIGINS[rng.randi() % ORIGINS.size()]
	var careers: Array = CAREERS.get(role, CAREERS["mechanic"])
	var career: Array = careers[rng.randi() % careers.size()]
	var quirk: Array = QUIRKS[rng.randi() % QUIRKS.size()]
	var story := [[str(origin[0]) % town, str(origin[1]) % town], [str(career[0]), str(career[1])], [str(quirk[0]), str(quirk[1])]]
	return {"id": id, "name": person, "role": role, "look": look, "story": story, "level": lv, "xp": xp_for(lv),
		"wage": wage_for(role, lv)}


## Host, each new day: the board's old candidates have gone elsewhere and new ones turn up, one
## for each role (locked ones too, to see what's coming).
static func refresh_board(day: int) -> void:
	var s := _st()
	if int(s["board_day"]) == day and not board().is_empty():
		return
	s["board_day"] = day
	var rng: RandomNumberGenerator = Shed._rng
	var keep := {}
	for id in board():
		# Some of yesterday's are still looking.
		if rng.randf() < 0.35:
			keep[id] = board()[id]
	s["board"] = keep
	for role in ROLES:
		var has := false
		for id in board():
			if str(board()[id]["role"]) == role:
				has = true
		if not has:
			var cid := int(s["next"])
			s["next"] = cid + 1
			board()[cid] = make_candidate(role, rng, cid)


## The character level `peer` is (the host's own, or a joiner's from their summary).
static func level_of_peer(peer: int) -> int:
	if peer == Shed.me():
		return Progress.level()
	return int(Progress.summary(peer).get("level", 1))


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a "staff_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	if is_staff_peer(peer):
		return "Staff can't hire staff."
	match a:
		"staff_hire":
			var c: Dictionary = board().get(int(action.get("cand", 0)), {})
			if c.is_empty():
				return "They've taken a job somewhere else."
			if workers().size() >= MAX_STAFF:
				return "The garage can't take on more than %d staff." % MAX_STAFF
			var need := int(UNLOCK.get(str(c["role"]), 1))
			if level_of_peer(peer) < need:
				return "Hiring a %s needs character level %d." % [role_name(str(c["role"])).to_lower(), need]
		"staff_fire", "staff_cancel", "staff_assign":
			var w := worker(int(action.get("worker", 0)))
			if w.is_empty():
				return "They don't work here."
			if a == "staff_assign":
				if w.get("sick", false):
					return "%s is off sick today." % first_name(w)
				return job_check(w, action.get("job", {}))
			if a == "staff_cancel" and (w["job"] as Dictionary).is_empty():
				return "%s isn't doing anything." % first_name(w)
		"staff_debug_hire_all", "staff_debug_sick":
			if Net.is_online() and peer != 1:
				return "Only the host can do that."
		_:
			return "Unknown action."
	return ""


## Why worker `w` can't take on `job` ({kind, bike, slot, part, color, finish, steps}), or "".
static func job_check(w: Dictionary, job) -> String:
	if not (job is Dictionary):
		return "What job?"
	var kind := str(job.get("kind", ""))
	if not JOBS.has(kind):
		return "That's not a job."
	var roles: Array = JOBS[kind]
	if not roles.is_empty() and not roles.has(str(w["role"])):
		return "That's not %s's job: a %s does it." % [first_name(w), " or ".join(roles.map(func(r): return role_name(r).to_lower()))]
	if kind in ["service", "fit", "paint", "detail", "sell"]:
		var b := int(job.get("bike", 0))
		if not Shed.bikes.has(b):
			return "Which bike?"
		if int(Shed.bikes[b].get("rider", 0)) != 0:
			return "Someone's out riding it."
		for id in workers():
			var other: Dictionary = workers()[id]
			if int(id) != int(w["id"]) and int(other["job"].get("bike", 0)) == b:
				return "%s is already working on it." % first_name(other)
	match kind:
		"fit":
			var slot := str(job.get("slot", ""))
			var part := str(job.get("part", ""))
			if not PartsDB.SLOTS.has(slot):
				return "Which slot?"
			if PartsDB.get_part(part).is_empty() or PartsDB.kind_of(part) != PartsDB.SLOT_KIND.get(slot, ""):
				return "That part doesn't go there."
			if slot in ["frame", "engine"]:
				return "Swapping the %s is a job for the crew." % slot
			if PartsDB.is_engine_slot(slot) and not PartsDB.SERVICE_SLOTS.has(slot):
				return "The %s needs the engine out on the stand: one for the crew." % PartsDB.slot_name(slot).to_lower()
			if str(w["role"]) != "expert":
				if PartsDB.SLOT_KIND.get(slot, "") == "tyre":
					return "Tyres need the wheel off and the changer: a job for an expert mechanic."
				for dep in PartsDB.dependents(slot):
					if Shed.item_on(int(job["bike"]), dep) != 0 and Shed.WHEEL_TYRE.get(slot, "") != dep:
						return "The %s has to come off first: a job for an expert mechanic." % PartsDB.slot_name(dep).to_lower()
		"paint":
			var slot := str(job.get("slot", "tank"))
			if not StaffJobs.PAINT_SLOTS.has(slot):
				return "Pick a part to paint."
			if Shed.item_on(int(job["bike"]), slot) == 0:
				return "There's no %s on it." % PartsDB.slot_name(slot).to_lower()
			var idx := int(job.get("color", -1))
			if idx < 0 or idx >= Shed.PAINTS.size():
				return "Pick a colour."
			var on: Dictionary = Shed.items.get(Shed.item_on(int(job["bike"]), slot), {})
			if on.get("color") == Shed.PAINTS[idx] and str(on.get("finish", "")) == str(job.get("finish", "gloss")) \
					and float(on.get("paint_quality", 0.0)) > 0.8:
				return "It's already %s %s." % [str(job.get("finish", "gloss")), str(Shed.PAINT_NAMES[idx]).to_lower()]
		"sell":
			if Sales.is_customer_bike(int(job["bike"])):
				return "That's a customer's bike: it isn't the shed's to sell."
	return ""


## Host: does a checked "staff_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	match a:
		"staff_hire":
			return _hire(int(action["cand"]), str(Shed.crew.get(peer, {}).get("name", "")))
		"staff_fire":
			return _fire(int(action["worker"]))
		"staff_assign":
			var w := worker(int(action["worker"]))
			return assign(w, action["job"])
		"staff_cancel":
			var w := worker(int(action["worker"]))
			_drop_job(w, "Right you are. Leaving that.")
			return "%s stopped." % first_name(w)
		"staff_debug_hire_all":
			return hire_one_of_each()
		"staff_debug_sick":
			return set_all_sick(bool(action.get("sick", true)))
	return ""


static func _hire(cid: int, by: String) -> String:
	var s := _st()
	var c: Dictionary = board()[cid]
	board().erase(cid)
	var id := int(s["next"])
	s["next"] = id + 1
	s["hired"] = int(s["hired"]) + 1
	var role := str(c["role"])
	var same := 0
	for wid in workers():
		if str(workers()[wid]["role"]) == role:
			same += 1
	var w := {"id": id, "name": str(c["name"]), "role": role, "look": c["look"], "story": c["story"], "wage": int(c["wage"]),
		"xp": int(c["xp"]), "mood": clampf(0.7 + Shed._rng.randf_range(-0.05, 0.15), 0.0, 1.0),
		"hired_day": int(Shed.bank.get("day", 0)), "hired_by": by}
	_fill_worker(w, id)
	# They come in through the roller door and go to their spot.
	w["at"] = StaffNav.place("yard", [])
	w["pos"] = Vector3(0.0, 0.0, 72.2)
	workers()[id] = w
	_go_to(w, StaffNav.idle(role, same))
	say(w, HELLOS[Shed._rng.randi() % HELLOS.size()])
	_news("%s started as %s." % [w["name"], _a(role_name(role).to_lower())])
	Shed._mark_dirty()
	return "%s is on the payroll as %s, at %s a day." % [w["name"], _a(role_name(role).to_lower()), money(int(w["wage"]))]


static func _a(word: String) -> String:
	return ("an " if word.left(1) in ["a", "e", "i", "o", "u"] else "a ") + word


static func _fire(id: int) -> String:
	var w := worker(id)
	_let_go(w)
	var bye: String = BYES[Shed._rng.randi() % BYES.size()]
	workers().erase(id)
	_heard.erase(id)
	for other in workers().values():
		other["mood"] = maxf(0.0, float(other["mood"]) - 0.06)
	_news("%s left: \"%s\"" % [w["name"], bye])
	Shed._mark_dirty()
	return "%s: \"%s\"" % [w["name"], bye]


## Host: whatever they had hold of goes down (a part back on the bench, a bike they were
## wheeling where it stands, a tray on the counter).
static func _let_go(w: Dictionary) -> void:
	var peer := peer_of(int(w["id"]))
	var held := Shed.held_by(peer)
	if held != 0:
		Shed._put_on_bench(held)
	var pushing := Shed.pushing_bike(peer)
	if pushing != 0:
		Shed.bikes[pushing]["pusher"] = 0
		Shed._park(pushing)
	CoffeeShop.put_back(peer)
	w["leg"] = {}
	w["pos"] = _pos_now(w)


## Host: gives worker `w` `job` to do now (whatever they were doing is dropped). Returns what
## they say.
static func assign(w: Dictionary, job_in: Dictionary) -> String:
	_drop_job(w, "")
	var job := StaffJobs.new_job(w, job_in)
	w["job"] = job
	var ok := ["On it", "Leave it with me", "Righto", "No bother", "Consider it done"]
	var label := str(job["label"])
	var line := "%s: %s." % [ok[Shed._rng.randi() % ok.size()], label.left(1).to_lower() + label.substr(1)]
	if str(job["kind"]) == "reception":
		w["job"] = {}
		line = "I'll be on the desk."
	say(w, line)
	Shed._mark_dirty()
	return "%s: \"%s\"" % [first_name(w), line]


static func _drop_job(w: Dictionary, line: String) -> void:
	if w.is_empty():
		return
	_let_go(w)
	w["job"] = {}
	w["anim"] = ""
	if line != "":
		say(w, line)


# ---------------------------------------------------------------------------- talking

## Says `text` over their head (everyone sees it for SAY_SECS), and with `tell` tells the
## whole crew too (in their messages).
static func say(w: Dictionary, text: String, tell := false, ok := true) -> void:
	w["say"] = text.left(140)
	w["say_at"] = clock()
	Shed._mark_dirty()
	if tell:
		var line := "%s (%s): %s" % [first_name(w), role_name(str(w["role"])), text]
		for p in Shed.crew:
			Shed._tell(int(p), line, ok)
		_news("%s: %s" % [first_name(w), text])


static func _news(text: String) -> void:
	var n: Array = _st()["news"]
	n.append(text.left(120))
	while n.size() > MAX_NEWS:
		n.pop_front()


## What they say when you talk to them: the `n`th thing (a fresh one each time you ask): how
## the job's going, how they feel, their trade, a bit of their back story.
static func talk_line(w: Dictionary, n: int) -> String:
	if w.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w["id"]), n])
	var job: Dictionary = w.get("job", {})
	var story: Array = w.get("story", [])
	var m := float(w.get("mood", 0.7))
	var mood_pool: Array = HAPPY if m >= 0.75 else (OK if m >= 0.45 else LOW)
	var role_pool: Array = ROLE_LINES.get(str(w["role"]), ROLE_LINES["mechanic"])
	match n % 4:
		0:
			if not job.is_empty():
				return "%s. About %d%% there." % [str(job.get("label", "Busy")), roundi(progress(w) * 100.0)]
			return str(mood_pool[rng.randi() % mood_pool.size()]) + " Got a job for me?"
		1:
			return str(mood_pool[rng.randi() % mood_pool.size()])
		2:
			if not story.is_empty():
				var bit: Array = story[rng.randi() % story.size()]
				return str(bit[0]) if bit.size() > 0 else ""
			return str(role_pool[rng.randi() % role_pool.size()])
	return str(role_pool[rng.randi() % role_pool.size()])


## Their back story as a few sentences about them.
static func story_text(w: Dictionary) -> String:
	var out := []
	for bit in w.get("story", []):
		if bit is Array and bit.size() > 1:
			out.append(str(bit[1]))
	return " ".join(out)


## Whether a line they said is still showing, and what it is.
static func saying(w: Dictionary) -> String:
	if str(w.get("say", "")) == "" or clock() - float(w.get("say_at", -100.0)) > SAY_SECS:
		return ""
	return str(w["say"])


# ---------------------------------------------------------------------------- the day

## Host, at midnight (Shed.money_new_day): yesterday's sick are back, someone may phone in sick
## for today, moods drift back towards content, and the hiring board changes.
static func new_day() -> void:
	var day := int(Shed.bank.get("day", 0))
	var rng: RandomNumberGenerator = Shed._rng
	for id in workers():
		var w: Dictionary = workers()[id]
		if w.get("sick", false):
			w["sick"] = false
			w["mood"] = minf(1.0, float(w["mood"]) + 0.1)
			w["at"] = StaffNav.place("yard", [])
			w["pos"] = Vector3(0.0, 0.0, 72.2)
			_go_to(w, _home(w))
			say(w, BACK[rng.randi() % BACK.size()])
		w["mood"] = lerpf(float(w["mood"]), 0.65, 0.15)
	for id in workers():
		var w: Dictionary = workers()[id]
		if day - int(w["sick_last"]) < SICK_GAP or day <= int(w["hired_day"]):
			continue
		var roll := test_roll if test_roll >= 0.0 else rng.randf()
		if roll < SICK_CHANCE + SICK_LOW_MOOD * (1.0 - float(w["mood"])):
			go_sick(w, day)
	refresh_board(day)
	Shed._mark_dirty()


## Host: `w` phones in sick: they're not in today (what they had hold of is put down; a job in
## hand waits for them).
static func go_sick(w: Dictionary, day: int) -> void:
	_let_go(w)
	w["sick"] = true
	w["sick_last"] = day
	w["anim"] = ""
	var job: Dictionary = w["job"]
	if not job.is_empty():
		job["steps"] = [{"do": "plan"}]
		job["i"] = 0
		job["on"] = false
	var excuse: String = SICK[Shed._rng.randi() % SICK.size()]
	say(w, "On the phone: \"%s\"" % excuse, false)
	var line := "%s phoned in sick: \"%s\"" % [w["name"], excuse]
	for p in Shed.crew:
		Shed._tell(int(p), line, false)
	_news(line)


# ---------------------------------------------------------------------------- the shed's hooks

## Host: what the shed told one of the staff after a request (see Shed._tell).
static func heard(peer: int, text: String, _ok: bool) -> void:
	_heard[id_of_peer(peer)] = text


## Host: XP for a job done (see Shed._xp): it goes to their own skill, from the crew's XP table.
static func add_xp(peer: int, action: String, mult := 1.0) -> void:
	var w := worker(id_of_peer(peer))
	if w.is_empty():
		return
	var base := float(Progress.XP.get(action, {}).get("xp", 2)) if Progress.XP.has(action) else 2.0
	gain(w, roundi(base * clampf(mult, 0.0, 5.0)))


## Host: `xp` more for `w`, saying so when they go up a level.
static func gain(w: Dictionary, xp: int) -> void:
	if xp <= 0:
		return
	var before := level(w)
	w["xp"] = int(w["xp"]) + xp
	if level(w) > before:
		# Better at it, paid more (see wage_for).
		w["wage"] = maxi(int(w["wage"]), wage_for(str(w["role"]), level(w)))
		say(w, "Getting the hang of this. That's level %d!" % level(w), true)
	Shed._mark_dirty()


# ---------------------------------------------------------------------------- debug

## Host: one of each role hired at once (the Debug tab), whatever the level, while there's room.
static func hire_one_of_each() -> String:
	var n := 0
	for role in ROLES:
		if workers().size() >= MAX_STAFF:
			break
		var s := _st()
		var cid := int(s["next"])
		s["next"] = cid + 1
		board()[cid] = make_candidate(role, Shed._rng, cid)
		_hire(cid, "debug")
		n += 1
	return "Hired %d staff." % n


## Host: everyone off sick (or back well) at once (the Debug tab).
static func set_all_sick(on: bool) -> String:
	var day := int(Shed.bank.get("day", 0))
	for id in workers():
		var w: Dictionary = workers()[id]
		if on and not w["sick"]:
			go_sick(w, day)
		elif not on and w["sick"]:
			w["sick"] = false
			w["at"] = StaffNav.place("yard", [])
			w["pos"] = Vector3(0.0, 0.0, 72.2)
			_go_to(w, _home(w))
			say(w, BACK[Shed._rng.randi() % BACK.size()])
	Shed._mark_dirty()
	return "Everyone's off sick." if on else "Everyone's back at work."


# ---------------------------------------------------------------------------- running them

## Host: moves the staff on `delta` seconds: their clock, and every TICK each one's job or duty.
static func process(delta: float) -> void:
	var s := _st()
	var before := float(s["clock"])
	s["clock"] = before + delta
	if int(s["board_day"]) < 0:
		refresh_board(int(Shed.bank.get("day", 0)))
		Shed._mark_dirty()
	if workers().is_empty() or floor(before / TICK) == floor(float(s["clock"]) / TICK):
		return
	for id in workers().keys():
		if workers().has(id):
			_tick(workers()[id], TICK)
	_maybe_tea()


## Where they are now: along the walk they're on, or where they stopped.
static func _pos_now(w: Dictionary) -> Vector3:
	return pos_at(w, clock())


## Where they are at staff clock time `t` (views draw them between syncs with this).
static func pos_at(w: Dictionary, t: float) -> Vector3:
	var leg: Dictionary = w.get("leg", {})
	if leg.is_empty():
		return w.get("pos", Vector3.ZERO)
	var pts: PackedVector3Array = leg["pts"]
	var s := minf((t - float(leg["t0"])) * float(leg["v"]), float(leg["len"]))
	if int(leg.get("push", 0)) != 0:
		s -= StaffNav.BIKE_AHEAD
		if s < 0.0:
			var d := StaffNav.heading(pts, 0.0)
			return pts[0] + Vector3(sin(d), 0.0, cos(d)) * -s
	return StaffNav.along(pts, s)


## Whether the walk they're on is done.
static func _walked(w: Dictionary) -> bool:
	var leg: Dictionary = w.get("leg", {})
	if leg.is_empty():
		return true
	return (clock() - float(leg["t0"])) * float(leg["v"]) >= float(leg["len"])


## Starts them walking to place `to` (straight away there when it's no distance).
static func _go_to(w: Dictionary, to: Dictionary, push := 0, push_from := {}) -> void:
	var from: Dictionary = push_from if push != 0 else w.get("at", {})
	var start: Vector3 = _pos_now(w) if push == 0 else (Shed.bikes[push]["xf"] as Transform3D).origin
	var pts := StaffNav.route(from, to, start)
	var length := StaffNav.length(pts)
	w["leg"] = {"pts": pts, "t0": clock(), "v": StaffNav.PUSH_SPEED if push != 0 else StaffNav.WALK_SPEED, "len": length,
		"push": push, "n": int(w.get("legs", 0)) + 1}
	w["legs"] = int(w.get("legs", 0)) + 1
	w["to"] = to
	w["anim"] = ""
	Shed._mark_dirty()


## They've got where they were going.
static func _arrive(w: Dictionary) -> void:
	var leg: Dictionary = w.get("leg", {})
	var to: Dictionary = w.get("to", w.get("at", {}))
	if not leg.is_empty():
		var pts: PackedVector3Array = leg["pts"]
		var end := float(leg["len"])
		if int(leg.get("push", 0)) != 0:
			end -= StaffNav.BIKE_AHEAD
		w["pos"] = StaffNav.along(pts, end)
		w["yaw"] = StaffNav.heading(pts, end, float(w.get("yaw", 0.0)))
		if int(leg.get("push", 0)) != 0:
			# Stood behind the bike they've wheeled in: that's where they're at now.
			var p: Array = (to.get("p", []) as Array).duplicate()
			if not p.is_empty():
				p.pop_back()
			p.append(w["pos"])
			to = {"n": to.get("n", "shed"), "p": p}
	else:
		w["pos"] = StaffNav.spot(to)
	if to.has("yaw") and int(leg.get("push", 0)) == 0:
		w["yaw"] = float(to["yaw"])
	w["at"] = to
	w["leg"] = {}
	Shed._mark_dirty()


## The place they go back to with nothing to do.
static func _home(w: Dictionary) -> Dictionary:
	var k := 0
	for id in workers():
		if int(id) == int(w["id"]):
			break
		if str(workers()[id]["role"]) == str(w["role"]):
			k += 1
	return StaffNav.idle(str(w["role"]), k)


static func _tick(w: Dictionary, dt: float) -> void:
	if w.get("sick", false):
		return
	var job: Dictionary = w["job"]
	if not job.is_empty():
		_run_job(w, job, dt)
		return
	if not (w["leg"] as Dictionary).is_empty():
		if _walked(w):
			_arrive(w)
		return
	_duty(w, dt)


## A request made as this worker: checked like anyone's, then done. "" when it went through,
## else why not.
static func act(w: Dictionary, action: Dictionary) -> String:
	var peer := peer_of(int(w["id"]))
	_heard.erase(int(w["id"]))
	var why := Shed.check(peer, action)
	if why != "":
		return Controls.hint(why) if why.contains("{") else why
	Shed._apply(peer, action)
	return ""


## What the shed last told them (the result of their last request), or "".
static func last_heard(w: Dictionary) -> String:
	return str(_heard.get(int(w["id"]), ""))


# ---------------------------------------------------------------------------- the job runner

static func _run_job(w: Dictionary, job: Dictionary, dt: float) -> void:
	var steps: Array = job["steps"]
	var i := int(job["i"])
	if i >= steps.size():
		_finish(w, job)
		return
	var st: Dictionary = steps[i]
	var kind := str(st.get("do", ""))
	if not job.get("on", false):
		job["on"] = true
		job["t"] = 0.0
		if not _enter(w, job, st):
			return
		if not job.get("on", false):
			return   # entering did it all (a plan, a flag)
	job["t"] = float(job["t"]) + dt
	match kind:
		"go", "push":
			if int((w["leg"] as Dictionary).get("push", 0)) != 0:
				_push_bike(w)
			if _walked(w):
				var pushed := int((w["leg"] as Dictionary).get("push", 0))
				_arrive(w)
				if pushed != 0:
					var why := act(w, {"a": "release_bike", "bike": pushed, "xf": st["xf"]})
					if why != "":
						_failed(w, job, why)
						return
				_next(job)
		"work":
			if float(job["t"]) >= float(job.get("need", 1.0)):
				var a = st.get("act")
				if a is Dictionary and not (a as Dictionary).is_empty():
					var why := _act_step(w, job, a)
					if why != "":
						_failed(w, job, why)
						return
				w["anim"] = ""
				if str(st.get("after", "")) != "":
					StaffJobs.after(w, job, str(st["after"]))
				_next(job)
		"wait":
			if float(job["t"]) >= float(st.get("secs", 1.0)):
				w["anim"] = ""
				_next(job)
		_:
			_next(job)


## Starts a step. False when it's taken care of (or failed) already.
static func _enter(w: Dictionary, job: Dictionary, st: Dictionary) -> bool:
	job["doing"] = str(st.get("what", job.get("doing", "")))
	match str(st.get("do", "")):
		"plan":
			var replans := int(job.get("replans", 0)) + 1
			job["replans"] = replans
			if replans > MAX_REPLANS:
				_give_up(w, job, "I'm going round in circles with this one. I'll leave it.")
				return false
			var more := StaffJobs.plan(w, job)
			var steps: Array = job["steps"]
			var i := int(job["i"])
			steps.remove_at(i)
			if job.has("fail"):
				var why := str(job["fail"])
				job.erase("fail")
				_give_up(w, job, why)
				return false
			for k in more.size():
				steps.insert(i + k, more[k])
			job["on"] = false
			Shed._mark_dirty()
			return false
		"go":
			var to: Dictionary = st["to"]
			_go_to(w, to)
			if float(w["leg"]["len"]) < 0.05:
				_arrive(w)
		"push":
			var b := int(st["bike"])
			if not Shed.bikes.has(b) or int(Shed.bikes[b].get("pusher", 0)) != peer_of(int(w["id"])):
				_failed(w, job, "I've lost hold of the bike.")
				return false
			_go_to(w, st["to"], b, st.get("from", StaffNav.bike_out(b)))
		"work":
			var secs := float(st.get("secs", 2.0)) / speed(w)
			if Shed._rng.randf() < slip_chance(w) and st.get("slips", true):
				# A slip: a dropped bolt, a stripped thread, a fumble: it takes longer.
				secs *= 1.6
				job["slips"] = int(job.get("slips", 0)) + 1
				if Shed._rng.randf() < 0.35:
					say(w, ["Whoops. Dropped the bolt.", "Hang on, wrong socket.", "Fiddly little thing, this.",
						"Oops. Let's try that again."][Shed._rng.randi() % 4])
			job["need"] = secs
			w["anim"] = str(st.get("anim", "hands"))
			if st.has("face"):
				w["yaw"] = float(st["face"])
			Shed._mark_dirty()
		"wait":
			w["anim"] = str(st.get("anim", ""))
		"flag":
			job[str(st["k"])] = st.get("v", true)
			_next(job)
			return false
		"say":
			say(w, str(st.get("text", "")), bool(st.get("tell", false)))
			_next(job)
			return false
	return true


## A work step's request, with what it can only know now filled in (the quality of a finish,
## the round of teas).
static func _act_step(w: Dictionary, job: Dictionary, a: Dictionary) -> String:
	var action: Dictionary = a.duplicate(true)
	if action.get("quality") is String:
		action["quality"] = finish(w)
	if action.get("waste") is String:
		action["waste"] = Shed._rng.randf_range(0.12, 0.3) if Shed._rng.randf() < slip_chance(w) else Shed._rng.randf_range(0.0, 0.04)
	match str(action.get("a", "")):
		"staff_tea_round":
			return StaffJobs.buy_round(w, job)
		"staff_sell_list":
			return StaffJobs.list_bike(w, job)
		"move_bike":
			pass
	return act(w, action)


## Keeps the bike they're wheeling just ahead of them (the shed's copy, at the tick rate: every
## game draws it smoothly between, see StaffView).
static func _push_bike(w: Dictionary) -> void:
	var leg: Dictionary = w["leg"]
	var b := int(leg.get("push", 0))
	if not Shed.bikes.has(b):
		return
	var pts: PackedVector3Array = leg["pts"]
	var s := minf((clock() - float(leg["t0"])) * float(leg["v"]), float(leg["len"]))
	var at := StaffNav.along(pts, s)
	var yaw := StaffNav.heading(pts, s)
	act(w, {"a": "move_bike", "bike": b, "xf": Transform3D(Basis(Vector3.UP, yaw), at)})


static func _next(job: Dictionary) -> void:
	job["i"] = int(job["i"]) + 1
	job["on"] = false
	job["done"] = int(job.get("done", 0)) + 1
	Shed._mark_dirty()


## A step that didn't go: they say why, wait a moment and take another look (it may have been
## something in the way), giving up after MAX_FAILS in a row.
static func _failed(w: Dictionary, job: Dictionary, why: String) -> void:
	job["fails"] = int(job.get("fails", 0)) + 1
	w["anim"] = ""
	if int(job["fails"]) >= MAX_FAILS:
		_give_up(w, job, "I can't get this done: %s" % why.trim_suffix("."))
		return
	say(w, "Hmm. %s" % why)
	job["steps"] = [{"do": "wait", "secs": 4.0, "anim": "think"}, {"do": "plan"}]
	job["i"] = 0
	job["on"] = false
	Shed._mark_dirty()


static func _give_up(w: Dictionary, job: Dictionary, why: String) -> void:
	say(w, why, true, false)
	_let_go(w)
	w["job"] = {}
	w["anim"] = ""
	w["mood"] = maxf(0.0, float(w["mood"]) - 0.05)
	_go_to(w, _home(w))


## The job's done: they say so, get the credit and go back to their duty.
static func _finish(w: Dictionary, job: Dictionary) -> void:
	var line := str(job.get("report", ""))
	if line == "":
		line = "%s %s." % [DONE_LINES[Shed._rng.randi() % DONE_LINES.size()], str(job.get("label", "")).trim_suffix(".")]
	gain(w, 12 + 3 * int(job.get("done", 0)) / 2)
	say(w, line, true)
	w["jobs"] = int(w["jobs"]) + 1
	w["mood"] = minf(1.0, float(w["mood"]) + 0.04)
	w["job"] = {}
	w["anim"] = ""
	if (w["leg"] as Dictionary).is_empty():
		_go_to(w, _home(w))


# ---------------------------------------------------------------------------- duties

## With no job: the role's own duty (reception at the desk, the salesman with the buyers), or
## back to their spot.
static func _duty(w: Dictionary, dt: float) -> void:
	match str(w["role"]):
		"reception":
			if _away(w, StaffNav.reception()):
				return
			w["anim"] = "type"
			_greet(w)
			return
		"sales":
			if _sales_duty(w, dt):
				return
	if _away(w, _home(w)):
		return
	w["anim"] = ""


## Whether they're away from `pl` (and if so, on their way there).
static func _away(w: Dictionary, pl: Dictionary) -> bool:
	var there := StaffNav.spot(pl)
	if (w["pos"] as Vector3).distance_to(there) > 0.3:
		_go_to(w, pl)
		return true
	if pl.has("yaw") and absf(float(w["yaw"]) - float(pl["yaw"])) > 0.01:
		w["yaw"] = float(pl["yaw"])
		w["at"] = pl
		Shed._mark_dirty()
	return false


## The receptionist welcomes each customer who comes in (once), tells the crew they're waiting,
## and keeps them happy so they wait longer.
static func _greet(w: Dictionary) -> void:
	var greeted: Array = w["greeted"]
	for cid in Contracts.customers():
		if greeted.has(int(cid)):
			continue
		var c: Dictionary = Contracts.customers()[cid]
		greeted.append(int(cid))
		while greeted.size() > 12:
			greeted.pop_front()
		c["leave_at"] = float(c["leave_at"]) + Contracts.PATIENCE_HOURS * (0.6 + 0.08 * level(w))
		var kind := str(Contracts.KIND_NAMES.get(str(c.get("offer", {}).get("kind", "")), "a"))
		say(w, "Morning! Take a seat, someone'll be right with you.")
		var line := "%s on reception: %s is waiting at the desk with %s job." % [first_name(w), str(c.get("name", "A customer")),
			_a(kind.to_lower())]
		for p in Shed.crew:
			Shed._tell(int(p), line, true)
		_news(line)
		gain(w, 6)
		w["mood"] = minf(1.0, float(w["mood"]) + 0.01)
		return


## The salesman with no job of his own handles the offers on bikes for sale: goes over to the
## bike, thinks it over, then takes it, turns it down or counters (higher the better he is).
## True while there's something to do.
static func _sales_duty(w: Dictionary, _dt: float) -> bool:
	var deal := int(w.get("deal", 0))
	if deal != 0:
		var o: Dictionary = Sales.offers().get(deal, {})
		if o.is_empty() or str(o.get("state", "")) != "open":
			w["deal"] = 0
			return false
		if not (w["leg"] as Dictionary).is_empty():
			return true
		w["anim"] = "talk"
		if clock() < float(w["deal_at"]):
			return true
		w["deal"] = 0
		_decide(w, o)
		return true
	for oid in Sales.offers():
		var o: Dictionary = Sales.offers()[oid]
		if str(o.get("state", "")) != "open" or not Sales.active(int(o["bike"])):
			continue
		if int(o.get("seen_by", 0)) == int(w["id"]) and int(o.get("seen_round", -1)) == int(o.get("rounds", 0)):
			continue
		o["seen_by"] = int(w["id"])
		o["seen_round"] = int(o.get("rounds", 0))
		w["deal"] = int(oid)
		w["deal_at"] = clock() + CONSIDER_SECS / speed(w) + StaffNav.length(StaffNav.route(w["at"], StaffNav.show_side(Sales.stand_of(int(o["bike"]))), w["pos"])) / StaffNav.WALK_SPEED
		_go_to(w, StaffNav.show_side(Sales.stand_of(int(o["bike"]))))
		return true
	return false


## The salesman's answer to an offer: near enough the asking price (or a buyer's last word
## that's fair) he takes; otherwise he counters, pitching nearer what the buyer will really pay
## the better he is at it.
static func _decide(w: Dictionary, o: Dictionary) -> void:
	var amt := int(o["amount"])
	var ask := int(o.get("ask", amt))
	var top := int(o.get("max", amt))
	var lv := level(w)
	if amt >= roundi(ask * 0.97) or bool(o.get("final", false)):
		if amt >= roundi(ask * 0.7):
			var why := act(w, {"a": "sale_accept", "offer": int(o["id"])})
			if why == "":
				say(w, "Sold! %s for %s." % [str(o.get("bike_name", "It")), money(amt)], true)
				gain(w, 20)
			return
		act(w, {"a": "sale_reject", "offer": int(o["id"])})
		say(w, "Turned %s down. Not at %s." % [first_name({"name": str(o.get("buyer", ""))}), money(amt)], true, false)
		return
	var aim := lerpf(float(amt), float(maxi(top, amt)), clampf(0.45 + 0.055 * lv, 0.0, 0.98))
	aim = maxf(aim, amt + maxf(10.0, ask * 0.02))
	var counter := mini(roundi(aim / 10.0) * 10, ask)
	if counter <= amt:
		act(w, {"a": "sale_accept", "offer": int(o["id"])})
		say(w, "Sold! %s for %s." % [str(o.get("bike_name", "It")), money(amt)], true)
		gain(w, 20)
		return
	var why := act(w, {"a": "sale_counter", "offer": int(o["id"]), "amount": counter})
	if why == "":
		say(w, "I've come back at %s with %s for %s." % [str(o.get("buyer", "the buyer")).get_slice(" ", 0), money(counter),
			str(o.get("bike_name", "it"))], true)
		gain(w, 4)


## Every so often, while the cafe's open, someone with nothing on fetches a round of teas.
static func _maybe_tea() -> void:
	var s := _st()
	if clock() < float(s["tea_at"]):
		return
	s["tea_at"] = clock() + TEA_EVERY
	if not CoffeeShop.is_open():
		return
	for id in CoffeeShop.trays():
		var t: Dictionary = CoffeeShop.trays()[id]
		if int(t.get("holder", 0)) == 0 and not (t.get("items", []) as Array).is_empty() and Shed.in_work_area((t["xf"] as Transform3D).origin) \
				and Workshop.room_at((t["xf"] as Transform3D).origin) == "shed":
			return   # there's still a brew on the bench
	var pick: Dictionary = {}
	for id in workers():
		var w: Dictionary = workers()[id]
		if w["sick"] or not (w["job"] as Dictionary).is_empty() or str(w["role"]) == "reception" or int(w.get("deal", 0)) != 0:
			continue
		if pick.is_empty() or level(w) < level(pick):
			pick = w
	if pick.is_empty():
		return
	assign(pick, {"kind": "tea"})


# ---------------------------------------------------------------------------- the TV

## The Staff channel: everyone on the payroll, what they're doing and how far through, their
## skill, mood and wage, and the latest news.
static func tv_data() -> Dictionary:
	var rows := []
	var ids: Array = workers().keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = workers()[id]
		rows.append({"name": str(w["name"]), "role": role_name(str(w["role"])), "doing": status_text(w), "progress": progress(w),
			"busy": not (w["job"] as Dictionary).is_empty(), "level": level(w), "level_frac": level_frac(w), "mood": float(w["mood"]),
			"mood_word": mood_word(w), "sick": bool(w["sick"]), "wage": int(w["wage"]), "top": w["look"].get("top", Color.GRAY)})
	return {"rows": rows, "wages": wage_bill(), "news": (_st()["news"] as Array).duplicate(), "max": MAX_STAFF}
