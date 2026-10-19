class_name Adventure
extends RefCounted
## An adventure ride in the shed's shared state (Shed.adventure): the host starts one for the
## whole crew, every player's game loads the same road (from its seed and length, see
## AdventureWorld) and puts them on a bike at the start; reaching the destination, or the host
## ending it, brings everyone back to the shed with their bikes as they were (the fuel burnt,
## the wear and the muck all kept, as after any ride).
##
## Shed.adventure: {} when there's none, else {id, seed, km, theme, by (the host's name),
## riders {peer: bike id, 0 when there was none for them}, arrived (the first peer to reach the
## destination, 0 till then), arrived_name}. Never carried over in a save: loading one finds
## everybody back at the shed.
##
## Actions (Shed.request): adventure_start {seed, km, theme} and adventure_end (the host),
## adventure_join {bike: the one you'd like} (each player, on loading it) and adventure_arrive;
## the forks' adventure_vote and adventure_fork_due (see AdventureForks, which keeps votes and
## picks here too).

const DEFAULT_KM := 60.0
const MIN_KM := 5.0
const MAX_KM := 400.0
const THEMES: Array[String] = ["varied"]
## Real minutes for a whole day and night out on an adventure (the shed's own day is the
## Settings' length): fast enough to ride through a night in a session.
const DAY_MINUTES := 75.0
## Seconds between someone reaching the destination and everyone going home.
const ARRIVE_WAIT := 8.0


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
	return out


## Hours of game time a real second, out on an adventure.
static func day_rate() -> float:
	return 24.0 / (DAY_MINUTES * 60.0)


static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


static func check(peer: int, action: Dictionary) -> String:
	match str(action.get("a", "")):
		"adventure_start":
			if not _is_host(peer):
				return "Only the host can start an adventure."
			if active():
				return "There's an adventure on already."
			var km := float(action.get("km", DEFAULT_KM))
			if km < MIN_KM or km > MAX_KM:
				return "Pick between %d and %d km." % [int(MIN_KM), int(MAX_KM)]
			if not THEMES.has(str(action.get("theme", "varied"))):
				return "There's no adventure like that."
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
		_:
			return "Unknown adventure action."
	return ""


## Applies a checked action; returns what to tell the player (or, starting with "*", the whole crew).
static func apply(peer: int, action: Dictionary) -> String:
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match str(action.get("a", "")):
		"adventure_start":
			var km := float(action.get("km", DEFAULT_KM))
			Shed.adventure = {"id": 1 + randi() % 1000000000, "seed": int(action.get("seed", randi())), "km": km,
				"theme": str(action.get("theme", "varied")), "by": who, "riders": {}, "arrived": 0, "arrived_name": ""}
			return "*%s is off on an adventure ride: %d km, %s. Everyone to the start!" % [who, roundi(km), str(Shed.adventure["theme"])]
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
			if bike == 0:
				return "There's no bike ready to ride for you, so you've come along on foot."
			return ""
		"adventure_arrive":
			if int(Shed.adventure.get("arrived", 0)) != 0:
				return ""
			Shed.adventure["arrived"] = peer
			Shed.adventure["arrived_name"] = who
			return "*%s has reached the destination! Back to the shed in a few seconds." % who
		"adventure_vote", "adventure_fork_due":
			return AdventureForks.apply(peer, action, who)
	return ""


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


## The Esc menu's adventure button: the host starts a varied ride of DEFAULT_KM on a fresh seed,
## or ends the one on. (The workbench magazine replaces this later.)
static func menu_action() -> void:
	if active():
		Shed.request({"a": "adventure_end"})
	else:
		start(randi() % 1000000, DEFAULT_KM)


static func start(seed: int, km: float, theme := "varied") -> void:
	Shed.request({"a": "adventure_start", "seed": seed, "km": km, "theme": theme})


## What the Esc menu's button says, and why it can't be pressed ("" when it can).
static func menu_text() -> Array:
	var host := Shed.is_authority()
	if active():
		return ["End the adventure (everyone back to the shed)", "" if host else "The host ends the adventure."]
	return ["Adventure ride: %d km, varied roads (host starts it for everyone)" % int(DEFAULT_KM),
		"" if host else "The host starts adventures."]
