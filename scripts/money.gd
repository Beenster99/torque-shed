class_name Money
extends RefCounted
## Money (Milestone C): what parts and bikes cost and fetch, the business's bank (its settings,
## ledger and loans) and the "money_*" requests the host checks and applies.
##
## There are two kinds of money. Each player's own cash lives in their Progress profile and goes
## with them between sheds. The business's account is Shed.garage_money, saved with the shed,
## with everything around it in Shed.bank (see defaults()):
##   cut: the % of every wage that goes to the business (host setting),
##   owner: the player name who may take money out and run the loans ("" is the host),
##   ledger: the last LEDGER_SIZE movements [{day, amt, why, bal}], newest last,
##   loans: [{id, amount, owed, daily, rate, days, taken, missed}],
##   blocked: a missed repayment stops new loans until that loan is paid off,
##   day: in-game days since the shed opened (the clock passing midnight), history: the
##   account at the end of each day, milestones: account sizes already celebrated, series: the
##   account over in-game time for the graphs (see MoneyGraph),
##   costs: how hard the running costs bite ("off", "normal" or "hard", host setting),
##   overdraft: what the business owes after a bill it couldn't cover (income pays it back first),
##   use: what the crew has used since the last bill (machine units, work done, light hours),
##   last_bill: the lines of the last nightly bill [{why, amt}] and last_bill_day: its day.
##
## Jobs pay wages (Progress.PAY) through Shed.pay_worker: the worker gets the rest after the
## business's cut. The business earns from selling parts and bikes (and other helpers' sales and
## contracts through Shed.credit_garage), and pays for parts, project bikes and loans.
##
## Running costs: every in-game midnight (with the loan repayments) the business pays its bills:
## rent and business rates (more for every extension), insurance (more for more stock and bikes),
## power and water (standing charge, lights on and machines used) and workshop consumables (per
## bit of work done). A bill it can't cover takes what's there and the rest goes on an overdraft,
## which costs OVERDRAFT_RATE a day until income pays it off. Never game over.

const START_FUNDS := 10000
const DEFAULT_CUT := 20
const LEDGER_SIZE := 100
const HISTORY_DAYS := 14
## Bank loans on offer: how much, the interest a day on what's owed, and how many daily repayments.
const LOANS := [{"amount": 5000, "rate": 0.008, "days": 10}, {"amount": 20000, "rate": 0.006, "days": 20},
	{"amount": 50000, "rate": 0.005, "days": 30}]
## The most the business may owe the bank at once.
const MAX_DEBT := 100000
## A missed repayment adds this share of it as a fee (at least MISSED_FEE_MIN).
const MISSED_FEE := 0.1
const MISSED_FEE_MIN := 100
## The account sizes that pay everyone the money_milestone XP the first time the business reaches them.
const MILESTONES := [10000, 25000, 50000, 100000, 250000, 500000, 1000000]
const DEBUG_GRANT := 1000000
## A dealer pays this share of what a part is worth now; a whole bike fetches more when it's
## complete and more again when it's ready to ride.
const SELL_RATE := 0.7
const BONUS_COMPLETE := 0.15
const BONUS_RIDEABLE := 0.15
## A little more for a bike that's been washed spotless (every part clean, see Dirt): it shows well.
const BONUS_CLEAN := 0.03
## A project bike costs this much more than it would fetch as it comes, so restoring it is where
## the profit is.
const PROJECT_MARKUP := 1.25
## Haggler: per rank, parts this much cheaper and sales this much better.
const HAGGLE_BUY := 0.05
const HAGGLE_SELL := 0.03
## New price of a mid-range part of each kind, in pounds. The catalogue lists each kind from
## plain to fancy, so a kind's first part costs 0.6 of this and its last 2x. Engines go by size.
const KIND_PRICE := {"frame": 900, "fork": 450, "shock": 350, "wheel": 250, "tyre": 90, "disc": 80, "caliper": 120,
	"pads": 30, "master": 70, "tank": 220, "saddle": 110, "handlebars": 70, "dashboard": 150, "engine": 1800, "head": 400,
	"fuel": 300, "air_filter": 30, "oil_filter": 15, "spark_plugs": 20, "cooling": 200, "gearbox": 600, "exhaust": 350,
	"final_drive": 80, "chain": 60, "side_stand": 40, "centre_stand": 70, "headlight": 80, "horn": 30, "ecu": 300,
	"panniers": 250, "top_box": 120, "fog_lights": 90, "tail": 90, "fairing": 300, "mirrors": 40,
	"front_mudguard": 80, "indicators": 60, "side_panels": 90, "rearsets": 160, "guards": 180, "number_boards": 70, "swingarm": 260, "steering_damper": 220,
	"tank_bag": 80, "aux_tank": 160, "toolbox": 80, "satnav": 240, "lever_guards": 90}
## Fluids by the litre; empty cans and pans are a flat price.
const FLUID_LITRE := {"petrol": 1.6, "oil": 6.0, "brake_fluid": 12.0, "chain_lube": 25.0}
const EMPTY_CONTAINER := 8

## Running costs, a day, in pounds at "normal" (see bill_lines). An idle shed with the lights on
## pays about 200 a day; a solo player doing contracts clears 400 to 1,000 a day for the business.
const COSTS_MODES: Array[String] = ["off", "normal", "hard"]
const COSTS_NAMES := {"off": "Off", "normal": "Normal", "hard": "Hard"}
const COSTS_MULT := {"off": 0.0, "normal": 1.0, "hard": 1.75}
const RENT_BASE := 85
## Each building upgrade adds to the rent (bigger premises).
const RENT_EXTRA := {"wing": 45, "bays_56": 20, "bay_7": 10, "annex": 30, "mezzanine": 15, "lounge": 20, "showroom": 60}
## Business rates: this share of the rent.
const RATES_SHARE := 0.3
const INSURANCE_BASE := 25
## Insurance also covers what's in the shed: this share a day of what its bikes and stock would fetch.
const INSURANCE_WORTH := 0.001
const INSURANCE_RIG := 15
const INSURANCE_MAX := 250
## Power and water: a standing charge, the shed's strip lights (LED lighting uses less) and the
## side rooms' lights by the game hour, and the machines by the unit (MACHINE_UNITS).
const POWER_STANDING := 12
const POWER_LIGHT_HOUR := 0.8
const POWER_LED := 0.6
const POWER_ROOM_HOUR := 0.3
const POWER_UNIT := 0.25
const POWER_USE_MAX := 200
## What one use of each machine adds to the power and water bill (anything else counts as nothing).
const MACHINE_UNITS := {"dyno_run": 8.0, "dyno_fan": 1.0, "blast_use": 4.0, "blast": 2.0, "wash": 3.0, "wash_cells": 0.3,
	"repair": 2.0, "repair_many": 4.0, "clean_many": 2.0, "paint": 1.5, "coat": 2.0, "prime": 2.0, "paint_shake": 1.0,
	"paint_stir": 0.5, "lift": 0.5, "door": 0.5, "tyre_fit": 1.0, "tyre_remove": 1.0}
## Rags, gloves, cleaner and the rest: a little for every bit of work, up to a cap a day.
const CONSUMABLE_EACH := 0.15
const CONSUMABLES_MAX := 60
## Actions that aren't work on the shed's kit (they use no consumables).
const NOT_USE_PREFIXES: Array[String] = ["contract_", "sale_", "recovery_", "coffee_", "pool_", "board_", "money_", "bp_",
	"geo_", "dyno_headphones", "lights", "tv_", "radio", "computer", "sales_pc", "rename", "label", "write_label", "turn_poster",
	"blast_aim", "blast_tick", "wash_aim", "paint_bench_ui"]
## An overdraft costs this share of it a day (at least OVERDRAFT_MIN_FEE).
const OVERDRAFT_RATE := 0.015
const OVERDRAFT_MIN_FEE := 5


static func defaults() -> Dictionary:
	return {"cut": DEFAULT_CUT, "owner": "", "ledger": [], "loans": [], "next_loan": 1, "blocked": false, "day": 0,
		"history": [], "milestones": [], "series": {}, "costs": "normal", "overdraft": 0, "use": empty_use(), "last_bill": [],
		"last_bill_day": -1}


## Nothing used yet since the last bill.
static func empty_use() -> Dictionary:
	return {"machine": 0.0, "work": 0, "light_h": 0.0, "room_h": 0.0}


## A saved or synced bank with every field present and sane (older saves have none).
static func sanitize(b) -> Dictionary:
	var out := defaults()
	if not (b is Dictionary):
		return out
	out["cut"] = clampi(int(b.get("cut", DEFAULT_CUT)), 0, 100)
	out["owner"] = str(b.get("owner", "")).left(24)
	out["next_loan"] = maxi(1, int(b.get("next_loan", 1)))
	out["blocked"] = bool(b.get("blocked", false))
	out["day"] = maxi(0, int(b.get("day", 0)))
	var ledger = b.get("ledger", [])
	if ledger is Array:
		for e in ledger.slice(-LEDGER_SIZE):
			if e is Dictionary:
				out["ledger"].append({"day": int(e.get("day", 0)), "amt": int(e.get("amt", 0)), "why": str(e.get("why", "")).left(60),
					"bal": int(e.get("bal", 0))})
	var loans = b.get("loans", [])
	if loans is Array:
		for l in loans:
			if l is Dictionary and int(l.get("owed", 0)) > 0:
				out["loans"].append({"id": int(l.get("id", 0)), "amount": int(l.get("amount", 0)), "owed": int(l.get("owed", 0)),
					"daily": maxi(1, int(l.get("daily", 1))), "rate": float(l.get("rate", 0.0)), "days": int(l.get("days", 1)),
					"taken": int(l.get("taken", 0)), "missed": int(l.get("missed", 0))})
	var hist = b.get("history", [])
	if hist is Array:
		for v in hist.slice(-HISTORY_DAYS):
			out["history"].append(int(v))
	out["series"] = MoneyGraph.sanitize(b.get("series", {}))
	# Sheds saved before running costs pay them from now on, at normal.
	var mode := str(b.get("costs", "normal"))
	out["costs"] = mode if COSTS_MODES.has(mode) else "normal"
	out["overdraft"] = clampi(int(b.get("overdraft", 0)), 0, 100000000)
	var use = b.get("use", {})
	if use is Dictionary:
		out["use"] = {"machine": maxf(0.0, float(use.get("machine", 0.0))), "work": maxi(0, int(use.get("work", 0))),
			"light_h": maxf(0.0, float(use.get("light_h", 0.0))), "room_h": maxf(0.0, float(use.get("room_h", 0.0)))}
	var bill = b.get("last_bill", [])
	if bill is Array:
		for e in bill.slice(0, 10):
			if e is Dictionary:
				out["last_bill"].append({"why": str(e.get("why", "")).left(60), "amt": maxi(0, int(e.get("amt", 0)))})
	out["last_bill_day"] = int(b.get("last_bill_day", -1))
	var ms = b.get("milestones", [])
	if ms is Array:
		for v in ms:
			out["milestones"].append(int(v))
	return out


# ---------------------------------------------------------------------------- prices

## What a part costs new, in pounds: its "price" in data/parts.json if it has one, else worked
## out from its kind and where it sits in that kind's list (plain to fancy). Light parts cost more.
static func part_price(part_id: String) -> int:
	var p := PartsDB.get_part(part_id)
	if p.is_empty():
		return 0
	if p.has("price"):
		return maxi(0, int(p["price"]))
	var kind := str(p.get("kind", ""))
	var price := 0.0
	if PartsDB.FLUID_KINDS.has(kind):
		if p.get("empty", false):
			return EMPTY_CONTAINER
		price = float(FLUID_LITRE.get(kind, 2.0)) * float(p.get("litres", 1.0)) * (0.8 + 0.8 * _rank_in_kind(part_id, kind))
		return maxi(3, roundi(price))
	if kind == "engine":
		price = (400.0 + float(p.get("displacement", 500.0)) * 2.4) * (1.0 + 0.08 * (int(p.get("cylinders", 1)) - 1))
	else:
		price = float(KIND_PRICE.get(kind, 100)) * (0.6 + 1.4 * _rank_in_kind(part_id, kind))
	if PartsDB.is_lightweight(part_id):
		price *= 1.35
	return _nice(price)


## 0 for the first part of its kind in the catalogue, 1 for the last. Parts with a price of
## their own don't count, so adding them to the catalogue leaves the others' prices alone.
static func _rank_in_kind(part_id: String, kind: String) -> float:
	var ids: Array = PartsDB.by_kind.get(kind, []).filter(func(id): return not PartsDB.get_part(str(id)).has("price"))
	if ids.size() <= 1:
		return 0.5
	return float(maxi(ids.find(part_id), 0)) / float(ids.size() - 1)


## Rounds a price to something a shop would ask: whole pounds, then fives, then tens.
static func _nice(v: float) -> int:
	if v < 50.0:
		return maxi(1, roundi(v))
	if v < 500.0:
		return roundi(v / 5.0) * 5
	return roundi(v / 10.0) * 10


## What `peer` pays for a part: Haggler takes HAGGLE_BUY a rank off.
static func buy_price(part_id: String, peer: int) -> int:
	return roundi(part_price(part_id) * (1.0 - HAGGLE_BUY * _haggle(peer)))


static func _haggle(peer: int) -> int:
	var prog := _prog()
	return int(prog.skill_rank(peer, "haggler")) if prog else 0


static func _prog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Progress") if tree else null


## What one item is worth as it is now, before the dealer's cut: its new price scaled by its
## health squared (a tired part is worth far less), and for fluids by how full it is.
static func item_worth(item: Dictionary) -> float:
	var part := str(item.get("part", ""))
	var price := float(part_price(part))
	if PartsDB.is_fluid(part):
		var cap := maxf(PartsDB.fluid_capacity(part), 0.01)
		var litres := float(item.get("fluid", {}).get("litres", cap)) if item.get("fluid") is Dictionary else cap
		return price if PartsDB.get_part(part).get("empty", false) else price * clampf(litres / cap, 0.0, 1.0)
	var h := BikeBuild.part_health(Shed.condition_of(item))
	return price * h * h


## What the dealer pays for a loose part (with whatever is bolted to an engine block, or the tyre
## on a wheel). Haggler adds HAGGLE_SELL a rank.
static func part_sale(item_id: int, peer := 0) -> int:
	if not Shed.items.has(item_id):
		return 0
	var total := 0.0
	for id in _with_attached(item_id):
		total += item_worth(Shed.items[id])
	return roundi(total * SELL_RATE * (1.0 + HAGGLE_SELL * _haggle(peer)))


## The item and everything that goes with it when it's sold: an engine's parts, a wheel's tyre.
static func _with_attached(item_id: int) -> Array:
	var out := [item_id]
	if Shed.is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := Shed.engine_item(item_id, slot)
			if sub != 0:
				out.append(sub)
	var tyre := Shed.tyre_on_wheel(item_id)
	if tyre != 0:
		out.append(tyre)
	return out


## Whether a bike is complete, bolted up and has petrol and oil in it.
static func rideable(bike_id: int) -> bool:
	if not Shed.is_complete(bike_id):
		return false
	var build := Shed.build_of(bike_id)
	return build.fuel_litres >= 0.05 and build.oil_litres >= 0.1


## What a whole bike fetches from the trade (the dealer; see Sales for private buyers): what its parts are worth, plus BONUS_COMPLETE when nothing is
## missing or loose and BONUS_RIDEABLE more when it's ready to ride.
static func bike_sale(bike_id: int, peer := 0) -> int:
	if not Shed.bikes.has(bike_id):
		return 0
	var total := 0.0
	for slot in PartsDB.SLOTS:
		var id := Shed.item_on(bike_id, slot)
		if id != 0 and Shed.items.has(id):
			total += item_worth(Shed.items[id])
	var bonus := 1.0
	if Shed.is_complete(bike_id):
		bonus += BONUS_COMPLETE
		if rideable(bike_id):
			bonus += BONUS_RIDEABLE
	bonus += clean_bonus(bike_id)
	return roundi(total * SELL_RATE * bonus * (1.0 + HAGGLE_SELL * _haggle(peer)))


## BONUS_CLEAN for a bike with every part washed clean, else nothing; and what its paintwork
## adds or takes off (a deep gloss and a ceramic coat, a burn-through: see Detail.shine_bonus).
static func clean_bonus(bike_id: int) -> float:
	if not Shed.bikes.has(bike_id) or Shed.item_on(bike_id, "frame") == 0:
		return 0.0
	return (BONUS_CLEAN if Shed._bike_dirt(bike_id, true) <= Dirt.CLEAN else 0.0) + Detail.shine_bonus(bike_id)


## What a project bike costs to buy as it comes (see PROJECT_MARKUP).
static func project_price(bike_id: int) -> int:
	return _nice(bike_sale(bike_id) * PROJECT_MARKUP)


## The going rate for a project bike, for the TV (an average wreck), or for one ordered at
## `quality` (0 worn .. 1 new, see project_age).
static func typical_project_price(quality := -1.0) -> int:
	return _nice(_typical_bike(PartsDB.DEFAULT_BUILD, quality) * PROJECT_MARKUP)


## How worn the worst project bike ordered from the parts computer is (as Shed._new_bike's age
## takes it, at quality 0); better ones in step to new.
const PROJECT_WORST_AGE := 0.9


## The age (see Shed._new_bike) of a project bike ordered at `quality` (0 worn .. 1 new, as
## BikeCopy.quality_of has it): 0 at new.
static func project_age(quality: float) -> float:
	return 0.0 if BikeCopy.is_new(quality) else PROJECT_WORST_AGE * (1.0 - clampf(quality, 0.0, 1.0))


## The {rust, dirt, wear} a part on a bike of `age` has on average (as Shed._aged_item rolls it).
static func aged_cond(age: float) -> Dictionary:
	return {"wear": age * 0.6, "rust": age * 0.37, "dirt": minf(1.0, age * 1.1)}


## What a bike of `build` would fetch from the trade as an average one at `quality` (an average
## wreck when it's below 0): its parts' worth at that condition, complete and rideable, and clean
## when it's new.
static func _typical_bike(build: Dictionary, quality: float) -> float:
	var total := 0.0
	for slot in build:
		var part := str(build[slot])
		if part != "none" and part != "":
			total += part_price(part)
	var worth := 0.36
	var bonus := 1.0 + BONUS_COMPLETE + BONUS_RIDEABLE
	if quality >= 0.0:
		var h := BikeBuild.part_health(aged_cond(project_age(quality)))
		worth = h * h
		if BikeCopy.is_new(quality):
			bonus += BONUS_CLEAN
	return total * worth * SELL_RATE * bonus


## A project bike found to order in a style costs this much more than one that just turns up.
const STYLE_PREMIUM := 1.15


## What a project bike ordered in a style costs as it comes (see STYLE_PREMIUM).
static func style_project_price(bike_id: int) -> int:
	return _nice(bike_sale(bike_id) * PROJECT_MARKUP * STYLE_PREMIUM)


## The going rate for a project bike in a style, for the order button: an average wreck of
## that style's reference build (Contracts.style_build), or an average one at `quality`.
static func typical_style_price(style: String, quality := -1.0) -> int:
	return _nice(_typical_bike(Contracts.style_build(style), quality) * PROJECT_MARKUP * STYLE_PREMIUM)


static var _worth := {}
static var _worth_at := -100000


## What every bike in the shed would fetch, and every loose part, for the Garage TV page
## (worked out at most once a second).
static func shed_worth() -> Dictionary:
	if Time.get_ticks_msec() - _worth_at < 1000 and not _worth.is_empty():
		return _worth
	_worth_at = Time.get_ticks_msec()
	_worth = _shed_worth()
	return _worth


static func _shed_worth() -> Dictionary:
	var bikes := 0
	for id in Shed.bikes:
		bikes += bike_sale(int(id))
	var stock := 0
	for id in Shed.items:
		var at := str(Shed.items[id]["at"])
		if at in ["spot", "floor", "held"]:
			stock += part_sale(int(id))
	return {"bikes": bikes, "stock": stock}


# ---------------------------------------------------------------------------- the bank

## Adds a line to a ledger, keeping the last LEDGER_SIZE. Lines with the same reason on the same
## day, one after another, add up into one (so the cut of a hundred small wages is one line).
static func log_entry(bank: Dictionary, amt: int, why: String, bal: int) -> void:
	var ledger: Array = bank["ledger"]
	var day := int(bank.get("day", 0))
	if not ledger.is_empty():
		var last: Dictionary = ledger[-1]
		if str(last["why"]) == why and int(last["day"]) == day and (int(last["amt"]) >= 0) == (amt >= 0) and amt != 0:
			last["amt"] = int(last["amt"]) + amt
			last["bal"] = bal
			return
	ledger.append({"day": day, "amt": amt, "why": why.left(60), "bal": bal})
	while ledger.size() > LEDGER_SIZE:
		ledger.pop_front()


## The garage's share of a wage of `gross` pounds.
static func cut_of(gross: int, cut_percent: int) -> int:
	return roundi(gross * clampi(cut_percent, 0, 100) / 100.0)


## A new loan of offer `index` (see LOANS), taken on `day`: a fixed daily repayment that clears
## it with interest in its days.
static func new_loan(index: int, id: int, day: int) -> Dictionary:
	var o: Dictionary = LOANS[index]
	var p := float(o["amount"])
	var r := float(o["rate"])
	var n := int(o["days"])
	var daily := ceili(p * r / (1.0 - pow(1.0 + r, -n)))
	return {"id": id, "amount": int(o["amount"]), "owed": int(o["amount"]), "daily": daily, "rate": r, "days": n,
		"taken": day, "missed": 0}


static func debt(bank: Dictionary) -> int:
	var total := 0
	for l in bank["loans"]:
		total += int(l["owed"])
	return total


static func loan_by_id(bank: Dictionary, id: int) -> Dictionary:
	for l in bank["loans"]:
		if int(l["id"]) == id:
			return l
	return {}


## "5k at 0.8% a day, 10 days" for the loan buttons.
static func offer_text(index: int) -> String:
	var o: Dictionary = LOANS[index]
	var loan := new_loan(index, 0, 0)
	return "Borrow %s: %s a day for %d days (%.1f%% a day)" % [TvChannels.money_text(int(o["amount"])),
		TvChannels.money_text(int(loan["daily"])), int(o["days"]), float(o["rate"]) * 100.0]


## Money in and out of the business over the last `days` days, from the ledger.
static func flow(bank: Dictionary, days := 7) -> Dictionary:
	var since := int(bank.get("day", 0)) - days + 1
	var income := 0
	var out := 0
	for e in bank["ledger"]:
		if int(e["day"]) < since:
			continue
		if int(e["amt"]) > 0:
			income += int(e["amt"])
		else:
			out -= int(e["amt"])
	return {"in": income, "out": out}


## The business's account over the range's buckets ("minute" .. "year"), oldest first and now
## last, for the graphs.
static func graph(range_key: String) -> Array:
	return MoneyGraph.points(Shed.bank.get("series", {}), range_key, MoneyGraph.now_hours(), balance())


## Host: notes the account in the graphs' series when it has moved. True when it had.
static func record_graph() -> bool:
	if not (Shed.bank.get("series") is Dictionary):
		Shed.bank["series"] = {}
	return MoneyGraph.record(Shed.bank["series"], MoneyGraph.now_hours(), balance())


## The business's account less any overdraft: below nothing when it's overdrawn.
static func balance() -> int:
	return Shed.garage_money - int(Shed.bank.get("overdraft", 0))


## The account at the end of each of the last six days and now, for the TV charts.
static func history7(hist: Array, now: int) -> Array:
	var out := []
	for v in hist.slice(-6):
		out.append(int(v))
	while out.size() < 6:
		out.push_front(out[0] if not out.is_empty() else now)
	out.append(now)
	return out


# ---------------------------------------------------------------------------- requests

## The player name that runs the business: the owner setting, or the host.
static func owner_name() -> String:
	var o := str(Shed.bank.get("owner", ""))
	if o != "":
		return o
	return str(Shed.crew.get(1, {}).get("name", Settings.player_name))


## Whether `peer` is the garage owner (the host until the host names someone else).
static func is_owner(peer: int) -> bool:
	var o := str(Shed.bank.get("owner", ""))
	if o == "":
		return peer == 1
	return str(Shed.crew.get(peer, {}).get("name", "")) == o


## Why `peer` can't do a "money_*" request, or "". Sending checks the target here; the sender's
## own cash was taken on their machine before asking (see send()).
static func check(peer: int, action: Dictionary) -> String:
	var a := str(action.get("a", ""))
	var amount := int(action.get("amount", 0))
	var bank: Dictionary = Shed.bank
	match a:
		"money_send":
			if amount <= 0:
				return "How much?"
			var to := int(action.get("to", 0))
			if to != 0 and (to == peer or not Shed.crew.has(to)):
				return "They're not in the shed."
		"money_withdraw":
			if not is_owner(peer):
				return "Only the garage owner (%s) can take money out of the business." % owner_name()
			if amount <= 0:
				return "How much?"
			if amount > Shed.garage_money:
				return "The business only has %s." % TvChannels.money_text(Shed.garage_money)
		"money_settings":
			if peer != 1:
				return "Only the host can change the garage's settings."
			if action.has("cut") and not (action["cut"] is int or action["cut"] is float):
				return "Pick a percentage."
			if action.has("costs") and not COSTS_MODES.has(str(action["costs"])):
				return "Pick off, normal or hard."
		"money_loan":
			if not is_owner(peer):
				return "Only the garage owner (%s) can take out a loan." % owner_name()
			var i := int(action.get("offer", -1))
			if i < 0 or i >= LOANS.size():
				return "The bank doesn't offer that."
			if bool(bank["blocked"]):
				return "The bank won't lend more: a repayment was missed. Pay that loan off first."
			if debt(bank) + int(LOANS[i]["amount"]) > MAX_DEBT:
				return "The bank won't lend more than %s in all." % TvChannels.money_text(MAX_DEBT)
		"money_repay":
			if not is_owner(peer):
				return "Only the garage owner (%s) can pay off loans." % owner_name()
			var loan := loan_by_id(bank, int(action.get("loan", 0)))
			if loan.is_empty():
				return "That loan's paid off."
			if amount <= 0:
				return "How much?"
			if mini(amount, int(loan["owed"])) > Shed.garage_money:
				return "The business only has %s." % TvChannels.money_text(Shed.garage_money)
		"money_sell_part":
			var id := int(action.get("item", 0))
			if not Shed.items.has(id):
				return "That part has gone."
			var at := str(Shed.items[id]["at"])
			if at == "bike" or at == "engine" or at == "wheel":
				return "Take it off first: only loose parts can be sold."
			if at == "held" and int(Shed.items[id]["ref"]) != peer:
				return "Someone's holding that."
		"money_sell_bike":
			var b := int(action.get("bike", 0))
			if not Shed.bikes.has(b):
				return "That bike has gone."
			if int(Shed.bikes[b]["rider"]) != 0:
				return "Someone is riding that bike."
			if int(Shed.bikes[b].get("pusher", 0)) != 0:
				return "Someone is wheeling that bike about."
			if Shed.on_dyno(b) and Shed.strapped():
				return "Unstrap it from the dyno first."
			# Bikes are sold from the showroom (see Sales): the trade buys it off its display stand.
			if Shed.showroom_spot_of(b) < 0:
				return "Bikes are sold from the showroom: put it on a display stand in the sales office, then use the office PC."
			if Sales.is_customer_bike(b):
				return "That's a customer's bike: it isn't the shed's to sell."
		"money_debug_grant":
			if peer != 1:
				return "Only the host can do that."
		_:
			return "Unknown action."
	return ""


## Host: does a checked "money_*" request. Returns what to tell the player who asked.
static func apply(peer: int, action: Dictionary) -> String:
	var a := str(action["a"])
	var amount := int(action.get("amount", 0))
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	var bank: Dictionary = Shed.bank
	match a:
		"money_send":
			var to := int(action.get("to", 0))
			if to == 0:
				Shed.credit_garage(amount, "From %s" % who)
				return "Sent %s to the business." % TvChannels.money_text(amount)
			if not Shed.give_cash(to, amount, "From %s" % who):
				Shed.give_cash(peer, amount, "Sent back")
				return "%s couldn't get it, so it's come back to you." % str(Shed.crew[to]["name"])
			Shed._tell(to, "%s sent you %s." % [who, TvChannels.money_text(amount)], true)
			return "Sent %s to %s." % [TvChannels.money_text(amount), str(Shed.crew[to]["name"])]
		"money_withdraw":
			Shed.charge_garage(amount, "Taken out by %s" % who)
			Shed.give_cash(peer, amount, "From the business")
			return "Took %s out of the business." % TvChannels.money_text(amount)
		"money_settings":
			if action.has("cut"):
				bank["cut"] = clampi(int(action["cut"]), 0, 100)
			if action.has("owner"):
				var o := str(action["owner"]).strip_edges().left(24)
				bank["owner"] = "" if o == str(Shed.crew.get(1, {}).get("name", "")) else o
			if action.has("costs"):
				bank["costs"] = str(action["costs"])
				return "Running costs: %s (about %s a day now)." % [str(COSTS_NAMES[bank["costs"]]).to_lower(),
					TvChannels.money_text(bill_total(bill_lines(bank)))]
			return "The business takes %d%% of wages; %s runs it." % [int(bank["cut"]), owner_name()]
		"money_loan":
			var loan := new_loan(int(action["offer"]), int(bank["next_loan"]), int(bank["day"]))
			bank["next_loan"] = int(bank["next_loan"]) + 1
			bank["loans"].append(loan)
			Shed.credit_garage(int(loan["amount"]), "Bank loan")
			return "Borrowed %s. The bank takes %s a day from the business for %d days." % [
				TvChannels.money_text(int(loan["amount"])), TvChannels.money_text(int(loan["daily"])), int(loan["days"])]
		"money_repay":
			var loan := loan_by_id(bank, int(action["loan"]))
			var pay := mini(amount, int(loan["owed"]))
			Shed.charge_garage(pay, "Loan paid off early")
			loan["owed"] = int(loan["owed"]) - pay
			_tidy_loans(bank)
			if int(loan["owed"]) <= 0:
				return "Loan cleared." + (" The bank will lend again." if not bool(bank["blocked"]) else "")
			return "Paid %s off the loan: %s still owed." % [TvChannels.money_text(pay), TvChannels.money_text(int(loan["owed"]))]
		"money_sell_part":
			var id := int(action["item"])
			var price := part_sale(id, peer)
			var what := Shed.item_title(id)
			Shed._erase_item(id)
			Shed.credit_garage(price, "Sold %s" % what)
			Shed._xp(peer, "sell_part")
			return "Sold the %s for %s, into the business." % [what, TvChannels.money_text(price)]
		"money_sell_bike":
			var b := int(action["bike"])
			var price := bike_sale(b, peer)
			var what := str(Shed.bikes[b]["name"])
			Sales.note_trade(b, price)
			Shed._xp(peer, "sell_bike", 1.0, "bike:%d" % b)
			Shed.remove_bike(b)
			Shed.credit_garage(price, "Sold %s" % what)
			return "Sold %s for %s, into the business." % [what, TvChannels.money_text(price)]
		"money_debug_grant":
			Shed.garage_money = mini(Shed.garage_money + DEBUG_GRANT, Shed.MAX_GARAGE_MONEY)
			log_entry(bank, DEBUG_GRANT, "Debug: a gift", Shed.garage_money)
			settle_overdraft(bank)
			_mark_milestones(bank, Shed.garage_money)
			return "The garage got %s." % TvChannels.money_text(DEBUG_GRANT)
	return ""


## Drops paid-off loans; the bank lends again once no loan with a missed repayment is left.
static func _tidy_loans(bank: Dictionary) -> void:
	bank["loans"] = bank["loans"].filter(func(l): return int(l["owed"]) > 0)
	bank["blocked"] = bank["loans"].any(func(l): return int(l["missed"]) > 0)


## Milestones the account has now passed that weren't before: marked, and returned.
static func _mark_milestones(bank: Dictionary, balance: int) -> Array:
	var hit := []
	for m in MILESTONES:
		if balance >= int(m) and not bank["milestones"].has(int(m)):
			bank["milestones"].append(int(m))
			hit.append(int(m))
	return hit


## Host: a new in-game day. The day's account goes into the history, and each loan takes its
## interest and its repayment from the business; one it can't afford is missed, with a fee, and
## stops new loans. Returns what to tell the crew ("" when nothing happened).
static func new_day() -> String:
	var bank: Dictionary = Shed.bank
	bank["history"].append(Shed.garage_money)
	while bank["history"].size() > HISTORY_DAYS:
		bank["history"].pop_front()
	bank["day"] = int(bank["day"]) + 1
	var said := []
	for loan in bank["loans"]:
		loan["owed"] = int(loan["owed"]) + roundi(int(loan["owed"]) * float(loan["rate"]))
		var pay := mini(int(loan["daily"]), int(loan["owed"]))
		if Shed.charge_garage(pay, "Loan repayment"):
			loan["owed"] = int(loan["owed"]) - pay
			said.append("paid %s on the loan" % TvChannels.money_text(pay))
		else:
			var fee := maxi(MISSED_FEE_MIN, roundi(pay * MISSED_FEE))
			loan["owed"] = int(loan["owed"]) + fee
			loan["missed"] = int(loan["missed"]) + 1
			log_entry(bank, 0, "Missed a loan repayment: %s fee" % TvChannels.money_text(fee), Shed.garage_money)
			said.append("MISSED a loan repayment of %s (fee %s, no new loans until it's paid off)" % [
				TvChannels.money_text(pay), TvChannels.money_text(fee)])
	_tidy_loans(bank)
	var bills := pay_bills(bank)
	if bills != "":
		said.append(bills)
	if said.is_empty():
		return ""
	return "Day %d: the business %s." % [int(bank["day"]), ", ".join(said)]


# ---------------------------------------------------------------------------- running costs

## The running costs' multiplier for the bank's setting (0 when they're off).
static func costs_mult(bank: Dictionary) -> float:
	return float(COSTS_MULT.get(str(bank.get("costs", "normal")), 1.0))


## Tonight's bill as it stands, one line each [{key, why, amt}] (nothing when running costs are
## off): rent and rates for the premises (Shed.upgrades), insurance on the premises, the
## recovery rig and what's in the shed, power and water for the lights and machines used since
## the last bill, and consumables for the work done.
## The staff's wages (see Staff) go on it too.
static func bill_lines(bank: Dictionary) -> Array:
	var mult := costs_mult(bank)
	if mult <= 0.0:
		return []
	var rent := float(RENT_BASE)
	for id in RENT_EXTRA:
		if Shed.upgrades.get(id, false):
			rent += float(RENT_EXTRA[id])
	var worth := shed_worth()
	var insure := float(INSURANCE_BASE) + (float(worth["bikes"]) + float(worth["stock"])) * INSURANCE_WORTH
	if Shed.upgrades.get(Recovery.UPGRADE, false):
		insure += INSURANCE_RIG
	insure = minf(insure, INSURANCE_MAX)
	var use: Dictionary = bank.get("use", empty_use())
	var light := POWER_LIGHT_HOUR * (POWER_LED if Shed.upgrades.get("led", false) else 1.0)
	var power := float(POWER_STANDING) + minf(float(use.get("light_h", 0.0)) * light + float(use.get("room_h", 0.0)) * POWER_ROOM_HOUR
		+ float(use.get("machine", 0.0)) * POWER_UNIT, POWER_USE_MAX)
	var kit := minf(int(use.get("work", 0)) * CONSUMABLE_EACH, CONSUMABLES_MAX)
	var out := []
	var staff := Staff.workers().size()
	for l in [["rent", "Rent", rent], ["rates", "Business rates", rent * RATES_SHARE], ["insurance", "Insurance", insure],
			["power", "Power and water", power], ["consumables", "Workshop consumables", kit],
			["wages", "Staff wages (%d on the payroll)" % staff, float(Staff.wage_bill())]]:
		var amt := roundi(float(l[2]) * mult)
		if amt > 0:
			out.append({"key": l[0], "why": l[1], "amt": amt})
	return out


static func bill_total(lines: Array) -> int:
	var total := 0
	for l in lines:
		total += int(l["amt"])
	return total


## Host: something a player did in the shed (a checked request) counts towards tonight's power
## and water (MACHINE_UNITS) and consumables (any work on the kit).
static func note_use(action: Dictionary) -> void:
	var a := str(action.get("a", ""))
	if a == "" or Contracts.NOT_WORK.has(a):
		return
	for p in NOT_USE_PREFIXES:
		if a.begins_with(p):
			return
	var use: Dictionary = Shed.bank.get("use", {})
	if use.is_empty():
		use = empty_use()
		Shed.bank["use"] = use
	use["machine"] = float(use.get("machine", 0.0)) + float(MACHINE_UNITS.get(a, 0.0))
	use["work"] = int(use.get("work", 0)) + 1


## Host: `hours` of game time have passed with the shed's lights as they are now.
static func note_lights(hours: float) -> void:
	if hours <= 0.0 or hours > 6.0:
		return
	var use: Dictionary = Shed.bank.get("use", {})
	if use.is_empty():
		use = empty_use()
		Shed.bank["use"] = use
	if Shed.lights_on:
		use["light_h"] = float(use.get("light_h", 0.0)) + hours
	var rooms := 0
	for room in Shed.room_lights:
		if bool(Shed.room_lights[room]):
			rooms += 1
	use["room_h"] = float(use.get("room_h", 0.0)) + hours * rooms


## Host: takes `amount` for `why` from the business; what it can't cover goes on the overdraft.
## Returns how much went on the overdraft.
static func charge_or_overdraw(bank: Dictionary, amount: int, why: String) -> int:
	var paid := mini(amount, maxi(Shed.garage_money, 0))
	var short := amount - paid
	Shed.garage_money -= paid
	bank["overdraft"] = int(bank.get("overdraft", 0)) + short
	log_entry(bank, -amount, why + (" (overdrawn)" if short > 0 else ""), Shed.garage_money)
	return short


## Host: pays back as much of the overdraft as the account holds (income does this first).
static func settle_overdraft(bank: Dictionary) -> void:
	var od := int(bank.get("overdraft", 0))
	if od <= 0 or Shed.garage_money <= 0:
		return
	var pay := mini(od, Shed.garage_money)
	Shed.garage_money -= pay
	bank["overdraft"] = od - pay
	log_entry(bank, -pay, "Overdraft paid back", Shed.garage_money)


## Host, at midnight: interest on any overdraft, then tonight's bill (bill_lines), and what was
## used goes back to nothing. Returns what to tell the crew ("" when there was nothing to pay).
static func pay_bills(bank: Dictionary) -> String:
	var said := []
	var od := int(bank.get("overdraft", 0))
	if od > 0:
		var fee := maxi(OVERDRAFT_MIN_FEE, roundi(od * OVERDRAFT_RATE))
		bank["overdraft"] = od + fee
		log_entry(bank, 0, "Overdraft interest: %s" % TvChannels.money_text(fee), Shed.garage_money)
	var lines := bill_lines(bank)
	bank["use"] = empty_use()
	if lines.is_empty():
		return ""
	var short := 0
	for l in lines:
		short += charge_or_overdraw(bank, int(l["amt"]), str(l["why"]))
	bank["last_bill"] = lines.map(func(l): return {"why": str(l["why"]), "amt": int(l["amt"])})
	bank["last_bill_day"] = int(bank.get("day", 0))
	said.append("paid %s in running costs" % TvChannels.money_text(bill_total(lines)))
	if int(bank["overdraft"]) > 0:
		said.append("is OVERDRAWN by %s%s (%.1f%% a day until income pays it back)" % [
			TvChannels.money_text(int(bank["overdraft"])), "" if short > 0 else " still", OVERDRAFT_RATE * 100.0])
	return ", ".join(said)


# ---------------------------------------------------------------------------- from this machine

## Sends `amount` of this player's own cash to another player (`to` their peer) or to the
## business (`to` 0). The cash leaves here first; the host passes it on, or hands it back if the
## other player has gone. Returns why not, or "".
static func send(to: int, amount: int) -> String:
	if amount <= 0:
		return "How much?"
	var why := check(Shed.me(), {"a": "money_send", "to": to, "amount": amount})
	if why != "":
		return why
	var prog := _prog()
	if prog == null or not prog.spend(amount, "To the business" if to == 0 else "To %s" % str(Shed.crew[to]["name"])):
		return "You only have %s." % TvChannels.money_text(int(prog.money()) if prog else 0)
	Shed.request({"a": "money_send", "to": to, "amount": amount})
	return ""
