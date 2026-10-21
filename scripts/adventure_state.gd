class_name Adventure
extends RefCounted
## An adventure ride in the shed's shared state (Shed.adventure): the host starts one for the
## whole crew, every player's game loads the same road (from its seed and length, see
## AdventureWorld) and puts them on a bike at the start; reaching the destination, or the host
## ending it, brings everyone back to the shed with their bikes as they were (the fuel burnt,
## the wear and the muck all kept, as after any ride).
##
## Shed.adventure: {} when there's none, else {id, seed, km, theme, dest (where it ends up, see
## AdventureDest), title, by (the host's name),
## riders {peer: bike id, 0 when there was none for them}, arrived (the first peer to reach the
## destination, 0 till then), arrived_name, photo (the crew's photo there, once arrived)}. Never
## carried over in a save: loading one finds everybody back at the shed.
##
## Actions (Shed.request): adventure_start {seed, km, theme, dest, title, plan} (the host, from the route planner:
## the shed's route TV, see RouteTv) and adventure_end (the host: "Ride home"
## once everyone's at the destination), adventure_join {bike: the one you'd like} (each player, on
## loading it) and adventure_arrive (the first there: everyone's brought to the destination, gets
## XP, and the photo goes up on the shed wall); adventure_photo {photo} (the host: a photo from
## their own album hung in this shed, see AdventureDest.hang_album);
## adventure_resume (the host) carries on the one a night's sleep put away (Shed.adventure_save,
## see AdventureNeeds), everyone back where they slept.
## the forks' adventure_vote and adventure_fork_due (see AdventureForks, which keeps votes and
## picks here too); the police's adventure_police_fine and adventure_police_paid (see
## AdventurePolice, which keeps its fines here as "police"); adventure_highlight (see
## AdventureDiary, which keeps the crew's highlights here as "log").

const DEFAULT_KM := 60.0
const MIN_KM := 5.0
const MAX_KM := 400.0
## The kinds of ride (see AdventureTheme: each its roads, scenery, buildings, sky and weather).
const THEMES: Array[String] = ["varied", "desert", "alpine", "coastal", "hills"]
## Real minutes for a whole day and night out on an adventure (the shed's own day is the
## Settings' length): fast enough to ride through a night in a session.
const DAY_MINUTES := 75.0


static func active() -> bool:
	return int(Shed.adventure.get("id", 0)) != 0


## The state as received or loaded: a running adventure kept as it is, anything else none.
static func sanitize(v) -> Dictionary:
	if not (v is Dictionary) or int(v.get("id", 0)) == 0:
		return {}
	var out: Dictionary = v.duplicate(true)
	out["seed"] = int(out.get("seed", 1))
	out["km"] = clampf(float(out.get("km", DEFAULT_KM)), MIN_KM, MAX_KM)
	out["theme"] = str(out.get("theme", "varied"))
	if not (out.get("riders") is Dictionary):
		out["riders"] = {}
	out["arrived"] = int(out.get("arrived", 0))
	out["dest"] = str(out.get("dest", "")) if AdventureDest.exists(str(out.get("dest", ""))) \
		else AdventureDest.default_for(str(out["theme"]), int(out["seed"]))
	out["title"] = str(out.get("title", ""))
	if out.get("plan") is Dictionary:
		# A journey planned on the map: planned here too (the host's road if all is well; if not, what was said is kept,
		# for AdventureTrip.real_mismatch to turn down).
		var plan := AdventurePlans.clean(out["plan"])
		if not plan.is_empty():
			out["plan"] = plan
			AdventurePlans.pack_for(plan)
			return out
		out.erase("plan")
	var pack := RealPack.get_pack(str(out.get("real", ""))) if str(out.get("real", "")) != "" else null
	out["real"] = pack.id if pack != null else ""
	out["real_hash"] = pack.hash if pack != null else ""
	return out


static func _real_hash(id: String) -> String:
	var pack := RealPack.get_pack(id) if id != "" else null
	return pack.hash if pack != null else ""


## Hours of game time a real second, out on an adventure.
static func day_rate() -> float:
	return 24.0 / (DAY_MINUTES * 60.0)


static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


static func check(peer: int, action: Dictionary) -> String:
	match str(action.get("a", "")):
		"adventure_pin", "adventure_unpin", "adventure_mode", "adventure_clear":
			return AdventureJourney.check(peer, action)
		"adventure_start":
			if not _is_host(peer):
				return "Only the host can start an adventure."
			if active():
				return "There's an adventure on already."
			var planned := action.get("plan") is Dictionary
			var km := float(action.get("km", DEFAULT_KM))
			if planned:
				var why := AdventureJourney.start_check(action)
				if why != "":
					return why
			elif km < MIN_KM or km > MAX_KM:
				return "Pick between %d and %d km." % [int(MIN_KM), int(MAX_KM)]
			if not THEMES.has(str(action.get("theme", "varied"))) and not planned:
				return "There's no adventure like that."
			if str(action.get("dest", "")) != "" and not AdventureDest.exists(str(action["dest"])):
				return "There's no destination like that."
			if str(action.get("real", "")) != "" and RealPack.get_pack(str(action["real"])) == null:
				return "This game doesn't have that road."
		"adventure_photo":
			if not _is_host(peer):
				return "Only the host hangs photos."
			if AdventureDest.sanitize_photo(action.get("photo")).is_empty():
				return "That photo's no good."
		"adventure_resume":
			if not _is_host(peer):
				return "Only the host can carry on an adventure."
			if active():
				return "There's an adventure on already."
			if Shed.adventure_save.is_empty():
				return "There's no adventure put away to carry on."
		"adventure_end":
			if not _is_host(peer):
				return "Only the host can end the adventure."
			if not active():
				return "There's no adventure on."
		"adventure_join", "adventure_arrive":
			if not active():
				return "There's no adventure on."
		"adventure_vote", "adventure_fork_due":
			return AdventureForks.check(peer, action)
		"adventure_police_fine", "adventure_police_paid":
			return AdventurePolice.check(peer, action)
		"adventure_highlight":
			return AdventureDiary.check(peer, action)
		_:
			return "Unknown adventure action."
	return ""


## Applies a checked action; returns what to tell the player (or, starting with "*", the whole crew).
static func apply(peer: int, action: Dictionary) -> String:
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match str(action.get("a", "")):
		"adventure_pin", "adventure_unpin", "adventure_mode", "adventure_clear":
			return AdventureJourney.apply(peer, action, who)
		"adventure_start":
			var km := float(action.get("km", DEFAULT_KM))
			var seed := int(action.get("seed", randi()))
			var theme := str(action.get("theme", "varied"))
			var planned: Dictionary = AdventureJourney.start_info(action) if action.get("plan") is Dictionary else {}
			if not planned.is_empty():
				km = float(planned["km"])
				theme = str(planned["theme"])
			var dest := str(action.get("dest", ""))
			if dest == "":
				dest = AdventureDest.default_for(theme, seed)
			var title := str(action.get("title", "")).left(48)
			Shed.adventure = {"id": 1 + randi() % 1000000000, "seed": seed, "km": km, "theme": theme, "dest": dest,
				"title": title if title != "" else "Ride to %s" % AdventureDest.name_of(dest),
				"real": str(action.get("real", "")), "real_hash": _real_hash(str(action.get("real", ""))), "by": who, "riders": {}, "arrived": 0, "arrived_name": ""}
			if not planned.is_empty():
				Shed.adventure["plan"] = planned["plan"]
				Shed.adventure["real"] = planned["real"]
				Shed.adventure["real_hash"] = planned["real_hash"]
			Shed.adventure_save = {}   # a new adventure: any put away overnight is forgotten
			AdventureDiary.started(true)
			return "*%s is off on an adventure ride: %s, %d km to %s. Everyone to the start!" % [who, str(Shed.adventure["title"]),
				roundi(km), AdventureDest.name_of(dest)]
		"adventure_resume":
			var save := Shed.adventure_save
			Shed.adventure = (save["adventure"] as Dictionary).duplicate(true)
			Shed.adventure["id"] = 1 + randi() % 1000000000
			Shed.adventure["riders"] = {}
			Shed.adventure["arrived"] = 0
			Shed.adventure["arrived_name"] = ""
			Shed.adventure["by"] = who
			Shed.adventure["resume"] = (save["at"] as Dictionary).duplicate()
			Shed.adventure["needs_saved"] = (save["needs"] as Dictionary).duplicate(true)
			if Daylight.current:
				Daylight.current.set_time(float(save.get("hours", AdventureNeeds.MORNING)))
			AdventureDiary.started(false)
			return "*%s carries on the adventure: %.1f of %d km done. Everyone back on the road!" % [who,
				AdventureNeeds.save_s(save) / 1000.0, roundi(float(Shed.adventure.get("km", DEFAULT_KM)))]
		"adventure_end":
			Shed.adventure = {}
			return "*The adventure's over: back to the shed."
		"adventure_join":
			var riders: Dictionary = Shed.adventure["riders"]
			var bike := Shed.riding(peer)
			if bike == 0:
				bike = _bike_for(peer, int(action.get("bike", 0)), riders)
				if bike != 0:
					Shed.bikes[bike]["rider"] = peer
					Shed.bikes[bike]["stand"] = ""
					Shed.bikes[bike]["pusher"] = 0
					if Shed.crew.has(peer):
						Shed.crew[peer]["riding"] = bike
			riders[peer] = bike
			if AdventureNeeds.of(peer).is_empty():
				AdventureNeeds.joined(peer)
			if bike == 0:
				return "There's no bike ready to ride for you, so you've come along on foot."
			return ""
		"adventure_arrive":
			if int(Shed.adventure.get("arrived", 0)) != 0:
				return ""
			Shed.adventure["arrived"] = peer
			Shed.adventure["arrived_name"] = who
			Shed.adventure_save = {}   # there: nothing left to carry on
			AdventureDiary.arrived(peer)
			return "*" + _arrive(who)
		"adventure_photo":
			AdventureDest.hang(action["photo"])
			return ""
		"adventure_vote", "adventure_fork_due":
			return AdventureForks.apply(peer, action, who)
		"adventure_police_fine", "adventure_police_paid":
			return AdventurePolice.apply(peer, action)
		"adventure_highlight":
			return AdventureDiary.apply(peer, action)
	return ""


## Everyone's at the destination: the crew's photo (hung on the shed wall), XP for each of them
## (more for a longer ride), and the clock to the time of day it's best seen at. What to tell them.
static func _arrive(who: String) -> String:
	var ids := Shed.crew.keys()
	ids.sort()
	var names := ids.map(func(p): return str(Shed.crew[p].get("name", "Rider")))
	var photo := AdventureDest.make_photo(Shed.adventure, names)
	Shed.adventure["photo"] = photo
	AdventureDest.hang(photo)
	var km := float(Shed.adventure.get("km", DEFAULT_KM))
	for p in ids:
		Progress.award(int(p), "adventure_done", km / 100.0, "adventure:%d" % int(Shed.adventure["id"]))
	var dest := AdventureDest.of(str(Shed.adventure.get("dest", "")))
	if float(dest.get("hours", -1.0)) >= 0.0 and Daylight.current:
		Daylight.current.set_time(float(dest["hours"]))
	return "%s has reached %s! Photo time!" % [
		who, AdventureDest.name_of(str(Shed.adventure.get("dest", "")))]


## The bike `peer` takes: `preferred` (the one they were by) if it's free to ride, else the
## first free one that's ready. 0 when there's none.
static func _bike_for(peer: int, preferred: int, riders: Dictionary) -> int:
	var taken := riders.values()
	var order := [preferred] if preferred != 0 else []
	var ids := Shed.bikes.keys()
	ids.sort()
	order.append_array(ids)
	for id in order:
		if not Shed.bikes.has(id) or taken.has(id):
			continue
		if Shed.check(peer, {"a": "mount", "bike": id}) == "":
			return int(id)
	return 0


## The Esc menu's adventure button: opens the route planner (JourneyMap, the same board as the shed's route TV) to plan
## one, or the host ends the one on ("Ride home" once everyone's at the destination).
static func menu_action() -> void:
	if active():
		Shed.request({"a": "adventure_end"})
	elif AdventureTrip.current:
		AdventureTrip.current.open_journey.call_deferred()


## Starts a ride on `seed` of `km` to the theme's destination for it (the Debug tab and tests).
static func start(seed: int, km: float, theme := "varied", dest := "") -> void:
	Shed.request({"a": "adventure_start", "seed": seed, "km": km, "theme": theme, "dest": dest})


## What the Esc menu's button says, and why it can't be pressed ("" when it can).
## The Esc menu's "Continue adventure" button: [text, why it can't be pressed], or [] when
## there's none put away (or one's on).
static func continue_text() -> Array:
	var save := Shed.adventure_save
	if active() or save.is_empty():
		return []
	var km := float((save["adventure"] as Dictionary).get("km", DEFAULT_KM))
	return ["Continue adventure: %.1f of %d km done, %d %s in (host carries it on for everyone)" % [AdventureNeeds.save_s(save) / 1000.0,
		roundi(km), maxi(1, int(save.get("nights", 1))), "night" if int(save.get("nights", 1)) <= 1 else "nights"],
		"" if Shed.is_authority() else "The host carries the adventure on."]


static func menu_text() -> Array:
	var host := Shed.is_authority()
	if active() and int(Shed.adventure.get("arrived", 0)) != 0:
		return ["Ride home (everyone back to the shed)", "" if host else "The host rides everyone home."]
	if active():
		return ["End the adventure (everyone back to the shed)", "" if host else "The host ends the adventure."]
	return ["Adventure ride: plan one on the route TV in the shed, or here (the host starts it for everyone)", ""]
